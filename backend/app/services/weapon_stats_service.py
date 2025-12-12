"""
Weapon Stats Service - Persistence and sync for forged weapon combat biographies.

Handles loading, saving, and validation of weapon stats from Godot client.
Stats are synced periodically and on game exit.
"""

from datetime import datetime
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from ..models import WeaponStats, ForgedAchievement, User


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


def update_weapon_stats(
    db: Session,
    forged_achievement_id: int,
    stats_data: Dict[str, Any],
    client_ip: Optional[str] = None
) -> Optional[WeaponStats]:
    """
    Update weapon stats from client sync.

    Only allows incrementing stats (no decrements) to prevent cheating.
    Returns updated stats or None if validation fails.
    """
    stats = get_weapon_stats(db, forged_achievement_id)
    if not stats:
        return None

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
    """Get visual tier based on kills."""
    if is_virgin(stats):
        return "PRISTINE"
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
