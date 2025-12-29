"""
Weapon Stats Service - Persistence and sync for forged weapon combat biographies.

Handles loading, saving, and validation of weapon stats from Godot client.
Stats are synced periodically and on game exit.

Anti-cheat features:
- Rate limiting: Max updates per time window
- Anomaly detection: Impossible stat ratios
- Spike detection: Unrealistic single-update gains
- IP tracking: Mid-session IP changes
- Telemetry logging: All suspicious activity logged for review
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func
from ..models import WeaponStats, ForgedAchievement, User, SuspiciousActivity

# ═══════════════════════════════════════════════════════════════════════════
# ANTI-CHEAT THRESHOLDS
# ═══════════════════════════════════════════════════════════════════════════

# Rate limiting
MAX_UPDATES_PER_MINUTE = 6  # ~10 sec sync interval minimum
MAX_UPDATES_PER_HOUR = 120  # Allows for reconnects

# Spike detection (per single update)
MAX_KILLS_PER_UPDATE = 500  # ~8 kills/sec for 60 sec sync is ~480
MAX_DAMAGE_PER_UPDATE = 500000  # Reasonable for 60 sec of combat
MAX_LEVEL_GAIN_PER_UPDATE = 5  # Can't gain 10 levels in one sync
MAX_TIME_EQUIPPED_PER_UPDATE = 3600  # 1 hour max per sync

# Impossibility detection
MIN_DAMAGE_PER_KILL = 10  # Can't have 1000 kills with 100 damage total
MIN_SWINGS_PER_KILL = 0.5  # Usually takes at least 1 swing per 2 kills
MAX_CRIT_RATE = 0.95  # 95% crit rate is suspicious

# Suspicious flag bitmask values
FLAG_RATE_EXCEEDED = 1 << 0      # 1
FLAG_IMPOSSIBLE_RATIO = 1 << 1   # 2
FLAG_SPIKE_DETECTED = 1 << 2    # 4
FLAG_IP_MISMATCH = 1 << 3       # 8
FLAG_TIME_TRAVEL = 1 << 4       # 16
FLAG_STAT_REGRESSION = 1 << 5   # 32
FLAG_SUSPICIOUS_PATTERN = 1 << 6 # 64

# Severity score weights
SEVERITY_WEIGHTS = {
    'low': 1.0,
    'medium': 5.0,
    'high': 15.0,
    'critical': 50.0
}

# Auto-flag threshold (cumulative score triggers manual review)
AUTO_FLAG_THRESHOLD = 25.0


def get_weapon_stats(db: Session, forged_achievement_id: int) -> Optional[WeaponStats]:
    """Get weapon stats for a forged achievement, creating if not exists."""
    stats = db.query(WeaponStats).filter(
        WeaponStats.forged_achievement_id == forged_achievement_id
    ).first()

    if not stats:
        # Create virgin stats
        stats = WeaponStats(forged_achievement_id=forged_achievement_id)
        db.add(stats)
        db.commit()
        db.refresh(stats)

    return stats


def get_weapon_stats_by_item_id(db: Session, user_id: int, item_id: str) -> Optional[WeaponStats]:
    """Get weapon stats by item_id for a specific user's forged item."""
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.item_id == item_id,
        (ForgedAchievement.current_owner_id == user_id) |
        (ForgedAchievement.current_owner_id.is_(None) & ForgedAchievement.wallet_account.has(user_id=user_id))
    ).first()

    if not forged:
        return None

    return get_weapon_stats(db, forged.id)


# ═══════════════════════════════════════════════════════════════════════════
# ANTI-CHEAT DETECTION
# ═══════════════════════════════════════════════════════════════════════════

def _log_suspicious_activity(
    db: Session,
    user_id: int,
    weapon_stats: WeaponStats,
    suspicious_type: str,
    severity: str,
    details: Dict[str, Any],
    old_stats: Dict[str, Any],
    new_stats: Dict[str, Any],
    client_ip: Optional[str] = None
) -> SuspiciousActivity:
    """Log suspicious activity to the database."""
    # Calculate delta
    delta = {}
    for key in new_stats:
        if key in old_stats and isinstance(old_stats[key], (int, float)):
            delta[key] = new_stats[key] - old_stats[key]

    activity = SuspiciousActivity(
        user_id=user_id,
        weapon_stats_id=weapon_stats.id if weapon_stats else None,
        forged_achievement_id=weapon_stats.forged_achievement_id if weapon_stats else None,
        suspicious_type=suspicious_type,
        severity=severity,
        details=details,
        old_value=old_stats,
        new_value=new_stats,
        delta=delta,
        client_ip=client_ip,
        action_taken='logged'
    )
    db.add(activity)

    # Update weapon stats flags
    if weapon_stats:
        # Add flag bit
        flag_map = {
            'rate_exceeded': FLAG_RATE_EXCEEDED,
            'impossible_ratio': FLAG_IMPOSSIBLE_RATIO,
            'spike_detected': FLAG_SPIKE_DETECTED,
            'ip_mismatch': FLAG_IP_MISMATCH,
            'time_travel': FLAG_TIME_TRAVEL,
            'stat_regression': FLAG_STAT_REGRESSION,
            'suspicious_pattern': FLAG_SUSPICIOUS_PATTERN
        }
        if suspicious_type in flag_map:
            weapon_stats.suspicious_flags |= flag_map[suspicious_type]

        # Increment suspicion score
        weapon_stats.suspicious_score += SEVERITY_WEIGHTS.get(severity, 1.0)

        # Auto-flag if threshold exceeded
        if weapon_stats.suspicious_score >= AUTO_FLAG_THRESHOLD and not weapon_stats.is_flagged:
            weapon_stats.is_flagged = True
            weapon_stats.flagged_at = datetime.utcnow()

    return activity


def _check_rate_limit(
    db: Session,
    weapon_stats: WeaponStats,
    user_id: int
) -> Optional[Tuple[str, str, Dict]]:
    """Check if updates are coming too fast."""
    if not weapon_stats.last_synced_at:
        return None

    # Count recent updates in last minute
    one_minute_ago = datetime.utcnow() - timedelta(minutes=1)
    recent_count = db.query(func.count(SuspiciousActivity.id)).filter(
        SuspiciousActivity.user_id == user_id,
        SuspiciousActivity.weapon_stats_id == weapon_stats.id,
        SuspiciousActivity.server_timestamp >= one_minute_ago
    ).scalar() or 0

    # Also count by checking sync timing
    seconds_since_sync = (datetime.utcnow() - weapon_stats.last_synced_at).total_seconds()

    if seconds_since_sync < 5:  # Less than 5 seconds between syncs
        return (
            'rate_exceeded',
            'medium',
            {
                'reason': 'Sync too frequent',
                'seconds_since_last': seconds_since_sync,
                'min_expected': 10
            }
        )

    if recent_count >= MAX_UPDATES_PER_MINUTE:
        return (
            'rate_exceeded',
            'high',
            {
                'reason': 'Too many updates in time window',
                'updates_last_minute': recent_count,
                'max_allowed': MAX_UPDATES_PER_MINUTE
            }
        )

    return None


def _check_ip_mismatch(
    stats: WeaponStats,
    client_ip: Optional[str]
) -> Optional[Tuple[str, str, Dict]]:
    """Check for IP changes mid-session (could indicate account sharing or proxy hopping)."""
    if not client_ip or not stats.last_synced_from_ip:
        return None

    if stats.last_synced_at:
        # Only flag if it's within the same session (last 10 minutes)
        minutes_since_sync = (datetime.utcnow() - stats.last_synced_at).total_seconds() / 60

        if minutes_since_sync < 10 and stats.last_synced_from_ip != client_ip:
            return (
                'ip_mismatch',
                'low',  # Low severity - could be VPN, mobile network, etc.
                {
                    'reason': 'IP changed mid-session',
                    'previous_ip': stats.last_synced_from_ip,
                    'current_ip': client_ip,
                    'minutes_since_last_sync': minutes_since_sync
                }
            )

    return None


def _check_spike_detection(
    stats: WeaponStats,
    stats_data: Dict[str, Any]
) -> List[Tuple[str, str, Dict]]:
    """Check for unrealistic stat gains in a single update."""
    anomalies = []

    # Kills spike
    if "kills_total" in stats_data:
        kills_delta = stats_data["kills_total"] - stats.kills_total
        if kills_delta > MAX_KILLS_PER_UPDATE:
            anomalies.append((
                'spike_detected',
                'high',
                {
                    'stat': 'kills_total',
                    'old': stats.kills_total,
                    'new': stats_data["kills_total"],
                    'delta': kills_delta,
                    'max_allowed': MAX_KILLS_PER_UPDATE
                }
            ))

    # Damage spike
    if "damage_total" in stats_data:
        damage_delta = stats_data["damage_total"] - stats.damage_total
        if damage_delta > MAX_DAMAGE_PER_UPDATE:
            anomalies.append((
                'spike_detected',
                'medium',
                {
                    'stat': 'damage_total',
                    'old': stats.damage_total,
                    'new': stats_data["damage_total"],
                    'delta': damage_delta,
                    'max_allowed': MAX_DAMAGE_PER_UPDATE
                }
            ))

    # Level spike
    if "level" in stats_data:
        level_delta = stats_data["level"] - stats.level
        if level_delta > MAX_LEVEL_GAIN_PER_UPDATE:
            anomalies.append((
                'spike_detected',
                'critical',  # Level hacking is serious
                {
                    'stat': 'level',
                    'old': stats.level,
                    'new': stats_data["level"],
                    'delta': level_delta,
                    'max_allowed': MAX_LEVEL_GAIN_PER_UPDATE
                }
            ))

    # Time equipped spike (can't be equipped for 2 hours in a 60 sec sync)
    if "time_equipped_seconds" in stats_data:
        time_delta = stats_data["time_equipped_seconds"] - stats.time_equipped_seconds
        if time_delta > MAX_TIME_EQUIPPED_PER_UPDATE:
            anomalies.append((
                'spike_detected',
                'high',
                {
                    'stat': 'time_equipped_seconds',
                    'old': stats.time_equipped_seconds,
                    'new': stats_data["time_equipped_seconds"],
                    'delta': time_delta,
                    'max_allowed': MAX_TIME_EQUIPPED_PER_UPDATE
                }
            ))

    return anomalies


def _check_impossible_ratios(
    stats: WeaponStats,
    stats_data: Dict[str, Any]
) -> List[Tuple[str, str, Dict]]:
    """Check for stats that violate game logic."""
    anomalies = []

    # Get the values (use incoming data if present, else current stats)
    kills = stats_data.get("kills_total", stats.kills_total)
    damage = stats_data.get("damage_total", stats.damage_total)
    hits = stats_data.get("hits_total", stats.hits_total)
    crits = stats_data.get("crits_landed", stats.crits_landed)
    swings = stats_data.get("swings_total", stats.swings_total)

    # Crits can't exceed hits
    if hits > 0 and crits > hits:
        anomalies.append((
            'impossible_ratio',
            'critical',
            {
                'reason': 'Crits exceed total hits',
                'crits': crits,
                'hits': hits,
                'crit_rate': crits / hits if hits > 0 else 0
            }
        ))

    # Suspiciously high crit rate
    elif hits > 100 and crits / hits > MAX_CRIT_RATE:
        anomalies.append((
            'impossible_ratio',
            'high',
            {
                'reason': 'Crit rate suspiciously high',
                'crits': crits,
                'hits': hits,
                'crit_rate': crits / hits,
                'max_reasonable': MAX_CRIT_RATE
            }
        ))

    # Kills require damage
    if kills > 100 and damage > 0:
        damage_per_kill = damage / kills
        if damage_per_kill < MIN_DAMAGE_PER_KILL:
            anomalies.append((
                'impossible_ratio',
                'high',
                {
                    'reason': 'Damage per kill too low',
                    'kills': kills,
                    'damage': damage,
                    'damage_per_kill': damage_per_kill,
                    'min_expected': MIN_DAMAGE_PER_KILL
                }
            ))

    # Kills usually require swings (melee) or shots (ranged)
    shots = stats_data.get("shots_fired", stats.shots_fired)
    total_attacks = swings + shots

    if kills > 100 and total_attacks > 0:
        attacks_per_kill = total_attacks / kills
        if attacks_per_kill < MIN_SWINGS_PER_KILL:
            anomalies.append((
                'impossible_ratio',
                'medium',
                {
                    'reason': 'Too few attacks per kill',
                    'kills': kills,
                    'attacks': total_attacks,
                    'attacks_per_kill': attacks_per_kill,
                    'min_expected': MIN_SWINGS_PER_KILL
                }
            ))

    return anomalies


def _check_stat_regression(
    stats: WeaponStats,
    stats_data: Dict[str, Any]
) -> List[Tuple[str, str, Dict]]:
    """Check for attempts to decrease stats (should be impossible in normal play)."""
    anomalies = []

    # Fields that should only increase
    increment_only_fields = [
        'kills_total', 'kills_elite', 'kills_boss', 'kills_pvp',
        'damage_total', 'crits_landed', 'hits_total',
        'swings_total', 'shots_fired', 'bursts_fired',
        'deaths_equipped', 'misses_total', 'battles_lost',
        'time_equipped_seconds', 'sessions_equipped'
    ]

    for field in increment_only_fields:
        if field in stats_data:
            old_value = getattr(stats, field, 0)
            new_value = stats_data[field]
            if new_value < old_value:
                anomalies.append((
                    'stat_regression',
                    'critical',  # This should never happen naturally
                    {
                        'stat': field,
                        'old': old_value,
                        'attempted': new_value,
                        'regression': old_value - new_value
                    }
                ))

    return anomalies


def run_anti_cheat_checks(
    db: Session,
    user_id: int,
    stats: WeaponStats,
    stats_data: Dict[str, Any],
    client_ip: Optional[str] = None
) -> List[SuspiciousActivity]:
    """
    Run all anti-cheat checks and log any suspicious activity.
    Returns list of logged suspicious activities.
    """
    logged_activities = []

    # Snapshot current stats for logging
    old_stats = {
        'kills_total': stats.kills_total,
        'damage_total': stats.damage_total,
        'crits_landed': stats.crits_landed,
        'hits_total': stats.hits_total,
        'swings_total': stats.swings_total,
        'shots_fired': stats.shots_fired,
        'level': stats.level,
        'time_equipped_seconds': stats.time_equipped_seconds
    }

    all_anomalies = []

    # Rate limiting
    rate_check = _check_rate_limit(db, stats, user_id)
    if rate_check:
        all_anomalies.append(rate_check)

    # IP mismatch
    ip_check = _check_ip_mismatch(stats, client_ip)
    if ip_check:
        all_anomalies.append(ip_check)

    # Stat regression (attempts to decrease)
    regression_checks = _check_stat_regression(stats, stats_data)
    all_anomalies.extend(regression_checks)

    # Spike detection
    spike_checks = _check_spike_detection(stats, stats_data)
    all_anomalies.extend(spike_checks)

    # Impossible ratios
    ratio_checks = _check_impossible_ratios(stats, stats_data)
    all_anomalies.extend(ratio_checks)

    # Log all detected anomalies
    for suspicious_type, severity, details in all_anomalies:
        activity = _log_suspicious_activity(
            db, user_id, stats, suspicious_type, severity,
            details, old_stats, stats_data, client_ip
        )
        logged_activities.append(activity)

    return logged_activities


def update_weapon_stats(
    db: Session,
    forged_achievement_id: int,
    stats_data: Dict[str, Any],
    client_ip: Optional[str] = None,
    user_id: Optional[int] = None
) -> Optional[WeaponStats]:
    """
    Update weapon stats from client sync.

    Only allows incrementing stats (no decrements) to prevent cheating.
    Runs anti-cheat validation and logs suspicious activity.
    Returns updated stats or None if validation fails.
    """
    stats = get_weapon_stats(db, forged_achievement_id)
    if not stats:
        return None

    # Run anti-cheat checks before applying any updates
    if user_id:
        suspicious_activities = run_anti_cheat_checks(
            db, user_id, stats, stats_data, client_ip
        )

        # Log count of flagged activities for debugging
        if suspicious_activities:
            critical_count = sum(1 for a in suspicious_activities if a.severity == 'critical')
            if critical_count > 0:
                # For critical violations, we still apply the update but mark it
                # Full blocking would require additional review workflow
                pass

    # Validate and apply increments only
    # Kill stats
    if "kills_total" in stats_data and stats_data["kills_total"] > stats.kills_total:
        stats.kills_total = stats_data["kills_total"]
    if "kills_by_type" in stats_data:
        _merge_kill_counts(stats, stats_data["kills_by_type"])
    if "kills_elite" in stats_data and stats_data["kills_elite"] > stats.kills_elite:
        stats.kills_elite = stats_data["kills_elite"]
    if "kills_boss" in stats_data and stats_data["kills_boss"] > stats.kills_boss:
        stats.kills_boss = stats_data["kills_boss"]
    if "kills_pvp" in stats_data and stats_data["kills_pvp"] > stats.kills_pvp:
        stats.kills_pvp = stats_data["kills_pvp"]

    # Damage stats
    if "damage_total" in stats_data and stats_data["damage_total"] > stats.damage_total:
        stats.damage_total = stats_data["damage_total"]
    if "damage_max_hit" in stats_data and stats_data["damage_max_hit"] > stats.damage_max_hit:
        stats.damage_max_hit = stats_data["damage_max_hit"]
    if "damage_overkill" in stats_data and stats_data["damage_overkill"] > stats.damage_overkill:
        stats.damage_overkill = stats_data["damage_overkill"]

    # Crit stats
    if "crits_landed" in stats_data and stats_data["crits_landed"] > stats.crits_landed:
        stats.crits_landed = stats_data["crits_landed"]
    if "hits_total" in stats_data and stats_data["hits_total"] > stats.hits_total:
        stats.hits_total = stats_data["hits_total"]
    if "weakpoints_destroyed" in stats_data and stats_data["weakpoints_destroyed"] > stats.weakpoints_destroyed:
        stats.weakpoints_destroyed = stats_data["weakpoints_destroyed"]
    if "chain_max_reached" in stats_data and stats_data["chain_max_reached"] > stats.chain_max_reached:
        stats.chain_max_reached = stats_data["chain_max_reached"]

    # Usage stats
    if "swings_total" in stats_data and stats_data["swings_total"] > stats.swings_total:
        stats.swings_total = stats_data["swings_total"]
    if "shots_fired" in stats_data and stats_data["shots_fired"] > stats.shots_fired:
        stats.shots_fired = stats_data["shots_fired"]
    if "bursts_fired" in stats_data and stats_data["bursts_fired"] > stats.bursts_fired:
        stats.bursts_fired = stats_data["bursts_fired"]
    if "time_equipped_seconds" in stats_data and stats_data["time_equipped_seconds"] > stats.time_equipped_seconds:
        stats.time_equipped_seconds = stats_data["time_equipped_seconds"]
    if "sessions_equipped" in stats_data and stats_data["sessions_equipped"] > stats.sessions_equipped:
        stats.sessions_equipped = stats_data["sessions_equipped"]

    # Negative stats (can only increase)
    if "deaths_equipped" in stats_data and stats_data["deaths_equipped"] > stats.deaths_equipped:
        stats.deaths_equipped = stats_data["deaths_equipped"]
    if "misses_total" in stats_data and stats_data["misses_total"] > stats.misses_total:
        stats.misses_total = stats_data["misses_total"]
    if "battles_lost" in stats_data and stats_data["battles_lost"] > stats.battles_lost:
        stats.battles_lost = stats_data["battles_lost"]

    # Visibility toggle (can be changed freely)
    if "show_negative_stats" in stats_data:
        stats.show_negative_stats = bool(stats_data["show_negative_stats"])

    # Milestones (set once, never change)
    if "first_equipped_at" in stats_data and not stats.first_equipped_at:
        stats.first_equipped_at = _parse_timestamp(stats_data["first_equipped_at"])
    if "first_kill_at" in stats_data and not stats.first_kill_at:
        stats.first_kill_at = _parse_timestamp(stats_data["first_kill_at"])
    if "first_crit_at" in stats_data and not stats.first_crit_at:
        stats.first_crit_at = _parse_timestamp(stats_data["first_crit_at"])
    if "milestone_100_kills_at" in stats_data and not stats.milestone_100_kills_at:
        stats.milestone_100_kills_at = _parse_timestamp(stats_data["milestone_100_kills_at"])
    if "milestone_1000_kills_at" in stats_data and not stats.milestone_1000_kills_at:
        stats.milestone_1000_kills_at = _parse_timestamp(stats_data["milestone_1000_kills_at"])
    if "milestone_10000_kills_at" in stats_data and not stats.milestone_10000_kills_at:
        stats.milestone_10000_kills_at = _parse_timestamp(stats_data["milestone_10000_kills_at"])

    # Level (can only increase)
    if "level" in stats_data and stats_data["level"] > stats.level:
        stats.level = stats_data["level"]
    if "experience" in stats_data:
        # Experience can go down on level up, but level must increase
        stats.experience = stats_data["experience"]

    # Achievements (append-only)
    if "achievements" in stats_data:
        _merge_achievements(stats, stats_data["achievements"])

    # Update sync tracking
    stats.last_synced_at = datetime.utcnow()
    if client_ip:
        stats.last_synced_from_ip = client_ip

    db.commit()
    db.refresh(stats)
    return stats


def _merge_kill_counts(stats: WeaponStats, new_counts: Dict[str, int]) -> None:
    """Merge kill counts, only allowing increases."""
    current = stats.kills_by_type or {}
    for enemy_type, count in new_counts.items():
        if enemy_type not in current or count > current[enemy_type]:
            current[enemy_type] = count
    stats.kills_by_type = current


def _merge_achievements(stats: WeaponStats, new_achievements: list) -> None:
    """Merge achievements, append-only."""
    current = stats.achievements or []
    for ach in new_achievements:
        if ach not in current:
            current.append(ach)
    stats.achievements = current


def _parse_timestamp(ts: str) -> Optional[datetime]:
    """Parse ISO timestamp string."""
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def stats_to_dict(stats: WeaponStats) -> Dict[str, Any]:
    """Convert WeaponStats model to dictionary for API response."""
    return {
        "forged_achievement_id": stats.forged_achievement_id,
        # Kill stats
        "kills_total": stats.kills_total,
        "kills_by_type": stats.kills_by_type or {},
        "kills_elite": stats.kills_elite,
        "kills_boss": stats.kills_boss,
        "kills_pvp": stats.kills_pvp,
        # Damage stats
        "damage_total": stats.damage_total,
        "damage_max_hit": stats.damage_max_hit,
        "damage_overkill": stats.damage_overkill,
        # Crit stats
        "crits_landed": stats.crits_landed,
        "hits_total": stats.hits_total,
        "weakpoints_destroyed": stats.weakpoints_destroyed,
        "chain_max_reached": stats.chain_max_reached,
        # Usage stats
        "swings_total": stats.swings_total,
        "shots_fired": stats.shots_fired,
        "bursts_fired": stats.bursts_fired,
        "time_equipped_seconds": stats.time_equipped_seconds,
        "sessions_equipped": stats.sessions_equipped,
        # Negative stats
        "deaths_equipped": stats.deaths_equipped,
        "misses_total": stats.misses_total,
        "battles_lost": stats.battles_lost,
        "show_negative_stats": stats.show_negative_stats,
        # Milestones
        "first_equipped_at": stats.first_equipped_at.isoformat() if stats.first_equipped_at else None,
        "first_kill_at": stats.first_kill_at.isoformat() if stats.first_kill_at else None,
        "first_crit_at": stats.first_crit_at.isoformat() if stats.first_crit_at else None,
        "milestone_100_kills_at": stats.milestone_100_kills_at.isoformat() if stats.milestone_100_kills_at else None,
        "milestone_1000_kills_at": stats.milestone_1000_kills_at.isoformat() if stats.milestone_1000_kills_at else None,
        "milestone_10000_kills_at": stats.milestone_10000_kills_at.isoformat() if stats.milestone_10000_kills_at else None,
        # Level
        "level": stats.level,
        "experience": stats.experience,
        # Achievements
        "achievements": stats.achievements or [],
        # Computed
        "is_virgin": is_virgin(stats),
        "visual_tier": get_visual_tier(stats),
        "combat_prefix": get_combat_prefix(stats),
        "crit_rate_lifetime": get_crit_rate(stats),
    }


def is_virgin(stats: WeaponStats) -> bool:
    """Check if weapon is pristine (never used)."""
    return (
        stats.kills_total == 0 and
        stats.hits_total == 0 and
        stats.swings_total == 0 and
        stats.shots_fired == 0
    )


def get_visual_tier(stats: WeaponStats) -> str:
    """
    Get visual tier based on kills for weapon evolution.

    Tiers (per FORGED_WEAPON_STATS.md):
    - VIRGIN: 0 kills (pristine, collectors' items)
    - BLOODED: 1-99 kills
    - VETERAN: 100-999 kills
    - BATTLE-WORN: 1K-9,999 kills
    - LEGENDARY: 10K-49,999 kills
    - MYTHIC: 50K+ kills
    """
    if is_virgin(stats):
        return "VIRGIN"
    elif stats.kills_total >= 50000:
        return "MYTHIC"
    elif stats.kills_total >= 10000:
        return "LEGENDARY"
    elif stats.kills_total >= 1000:
        return "BATTLE-WORN"
    elif stats.kills_total >= 100:
        return "VETERAN"
    else:
        return "BLOODED"


# Combat tier prefixes for item display names
COMBAT_TIER_PREFIXES = {
    "VIRGIN": "",           # No prefix for virgin weapons - they're pure
    "BLOODED": "Blooded",
    "VETERAN": "Veteran",
    "BATTLE-WORN": "Battle-Worn",
    "LEGENDARY": "Legendary",
    "MYTHIC": "Mythic",
}


def get_combat_prefix(stats: WeaponStats) -> str:
    """Get the combat tier prefix for display name."""
    tier = get_visual_tier(stats)
    return COMBAT_TIER_PREFIXES.get(tier, "")


def get_display_name_with_combat_tier(base_name: str, stats: Optional[WeaponStats]) -> str:
    """
    Generate item display name with combat tier prefix.

    Examples:
    - Virgin weapon: "Coiled Sword"
    - Blooded: "Blooded Coiled Sword"
    - Veteran: "Veteran Coiled Sword"
    - Mythic: "Mythic Coiled Sword"
    """
    if not stats:
        return base_name

    prefix = get_combat_prefix(stats)
    if prefix:
        return f"{prefix} {base_name}"
    return base_name


def get_crit_rate(stats: WeaponStats) -> float:
    """Calculate lifetime crit rate as percentage."""
    if stats.hits_total == 0:
        return 0.0
    return (stats.crits_landed / stats.hits_total) * 100.0


def get_damage_bonus(stats: WeaponStats) -> float:
    """Calculate damage bonus from level (soft cap at 50)."""
    if stats.level <= 50:
        return stats.level * 1.0
    else:
        return 50.0 + (stats.level - 50) * 0.1


def get_crit_bonus(stats: WeaponStats) -> float:
    """Calculate crit chance bonus from level (soft cap at 50)."""
    if stats.level <= 50:
        return stats.level * 0.002
    else:
        return 0.10 + (stats.level - 50) * 0.0002


# ═══════════════════════════════════════════════════════════════════════════
# ADMIN / ANTI-CHEAT REVIEW FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def get_flagged_weapons(db: Session, limit: int = 50) -> List[WeaponStats]:
    """Get weapons flagged for manual review, ordered by suspicion score."""
    return db.query(WeaponStats).filter(
        WeaponStats.is_flagged == True
    ).order_by(
        WeaponStats.suspicious_score.desc()
    ).limit(limit).all()


def get_suspicious_activity_for_weapon(
    db: Session,
    weapon_stats_id: int,
    limit: int = 100
) -> List[SuspiciousActivity]:
    """Get all suspicious activity logs for a specific weapon."""
    return db.query(SuspiciousActivity).filter(
        SuspiciousActivity.weapon_stats_id == weapon_stats_id
    ).order_by(
        SuspiciousActivity.server_timestamp.desc()
    ).limit(limit).all()


def get_suspicious_activity_for_user(
    db: Session,
    user_id: int,
    limit: int = 100
) -> List[SuspiciousActivity]:
    """Get all suspicious activity logs for a user across all weapons."""
    return db.query(SuspiciousActivity).filter(
        SuspiciousActivity.user_id == user_id
    ).order_by(
        SuspiciousActivity.server_timestamp.desc()
    ).limit(limit).all()


def get_recent_suspicious_activity(
    db: Session,
    severity: Optional[str] = None,
    hours: int = 24,
    limit: int = 200
) -> List[SuspiciousActivity]:
    """Get recent suspicious activity for admin dashboard."""
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    query = db.query(SuspiciousActivity).filter(
        SuspiciousActivity.server_timestamp >= cutoff
    )

    if severity:
        query = query.filter(SuspiciousActivity.severity == severity)

    return query.order_by(
        SuspiciousActivity.server_timestamp.desc()
    ).limit(limit).all()


def mark_weapon_reviewed(
    db: Session,
    weapon_stats_id: int,
    review_notes: str,
    clear_flag: bool = False
) -> Optional[WeaponStats]:
    """Mark a weapon as reviewed by admin."""
    stats = db.query(WeaponStats).filter(
        WeaponStats.id == weapon_stats_id
    ).first()

    if not stats:
        return None

    stats.review_notes = review_notes

    if clear_flag:
        stats.is_flagged = False
        # Don't reset suspicious_score - keep for historical reference

    db.commit()
    db.refresh(stats)
    return stats


def get_user_suspicion_summary(db: Session, user_id: int) -> Dict[str, Any]:
    """Get summary of all suspicious activity for a user."""
    activities = db.query(SuspiciousActivity).filter(
        SuspiciousActivity.user_id == user_id
    ).all()

    weapons = db.query(WeaponStats).join(
        ForgedAchievement,
        WeaponStats.forged_achievement_id == ForgedAchievement.id
    ).filter(
        (ForgedAchievement.current_owner_id == user_id) |
        (ForgedAchievement.wallet_account.has(user_id=user_id))
    ).all()

    severity_counts = {'low': 0, 'medium': 0, 'high': 0, 'critical': 0}
    type_counts = {}

    for activity in activities:
        severity_counts[activity.severity] = severity_counts.get(activity.severity, 0) + 1
        type_counts[activity.suspicious_type] = type_counts.get(activity.suspicious_type, 0) + 1

    total_suspicion_score = sum(w.suspicious_score for w in weapons)
    flagged_weapons = sum(1 for w in weapons if w.is_flagged)

    return {
        'user_id': user_id,
        'total_activities': len(activities),
        'severity_counts': severity_counts,
        'type_counts': type_counts,
        'total_suspicion_score': total_suspicion_score,
        'flagged_weapons': flagged_weapons,
        'total_weapons': len(weapons)
    }
