"""
Game Discovery Service

Automatically detects games during achievement syncs that aren't in platform_mappings.json.
Logs them for admin review to potentially add to the Tapestry.
"""
import json
import os
import logging
from datetime import datetime
from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models import PendingGameDiscovery, User

logger = logging.getLogger(__name__)

# Cache for platform_mappings.json
_platform_mappings_cache: Optional[Dict] = None
_platform_mappings_mtime: float = 0


def _load_platform_mappings() -> Dict:
    """Load and cache platform_mappings.json."""
    global _platform_mappings_cache, _platform_mappings_mtime

    mappings_path = os.path.join(
        os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json'
    )

    try:
        current_mtime = os.path.getmtime(mappings_path)
        if _platform_mappings_cache is None or current_mtime > _platform_mappings_mtime:
            with open(mappings_path, 'r') as f:
                _platform_mappings_cache = json.load(f)
                _platform_mappings_mtime = current_mtime
                logger.info("Reloaded platform_mappings.json")
    except Exception as e:
        logger.error(f"Failed to load platform_mappings.json: {e}")
        if _platform_mappings_cache is None:
            _platform_mappings_cache = {"games": {}, "exclusive_mappings": {}}

    return _platform_mappings_cache


def get_known_game_ids(provider: str) -> set:
    """
    Get all known game IDs for a provider from platform_mappings.json.

    Returns a set of game identifiers that are already in the Tapestry.
    """
    mappings = _load_platform_mappings()
    known_ids = set()

    # Check games where this provider is canonical
    for game_key, game_data in mappings.get("games", {}).items():
        if game_key.startswith("_"):  # Skip comments
            continue

        canonical = game_data.get("canonical", {})
        if canonical.get("platform") == provider:
            # This game has this provider as canonical
            if provider == "steam":
                known_ids.add(canonical.get("app_id", ""))
            elif provider == "xbox":
                known_ids.add(canonical.get("title_id", ""))
            elif provider == "psn":
                known_ids.add(canonical.get("np_communication_id", ""))

        # Check games where this provider is a mapping target
        platforms = game_data.get("platforms", {})
        if provider in platforms:
            platform_data = platforms[provider]
            if provider == "steam":
                known_ids.add(platform_data.get("app_id", ""))
            elif provider == "xbox":
                known_ids.add(platform_data.get("title_id", ""))
            elif provider == "psn":
                known_ids.add(platform_data.get("np_communication_id", ""))

    # Also check exclusive_mappings
    exclusive = mappings.get("exclusive_mappings", {}).get(provider, {})
    for game_key, game_data in exclusive.items():
        if provider == "steam":
            known_ids.add(game_data.get("app_id", ""))
        elif provider == "xbox":
            known_ids.add(game_data.get("title_id", ""))
        elif provider == "psn":
            known_ids.add(game_data.get("np_communication_id", ""))

    # Remove empty strings and TO_RESEARCH
    known_ids.discard("")
    known_ids.discard("TO_RESEARCH")

    return known_ids


def normalize_game_name(name: str) -> str:
    """
    Normalize game name for cross-platform matching.
    Removes common suffixes, punctuation, and platform-specific additions.
    """
    import re
    if not name:
        return ""

    # Lowercase
    normalized = name.lower().strip()

    # Remove platform-specific suffixes
    suffixes_to_remove = [
        r'\s*\(xbox one\)$',
        r'\s*\(xbox series x\|s\)$',
        r'\s*\(xbox\)$',
        r'\s*\(pc\)$',
        r'\s*\(windows\)$',
        r'\s*\(steam\)$',
        r'\s*\(playstation\)$',
        r'\s*\(ps[45]\)$',
        r'\s*-\s*game preview$',
        r'\s*demo$',
        r'\s*goty$',
        r'\s*game of the year edition$',
        r'\s*definitive edition$',
        r'\s*anniversary edition$',
        r'\s*remastered$',
        r'\s*™$',
        r'\s*®$',
    ]

    for suffix in suffixes_to_remove:
        normalized = re.sub(suffix, '', normalized, flags=re.IGNORECASE)

    # Remove special characters but keep spaces
    normalized = re.sub(r'[^\w\s]', '', normalized)

    # Collapse multiple spaces
    normalized = re.sub(r'\s+', ' ', normalized).strip()

    return normalized


def find_cross_platform_match(db: Session, game_name: str, exclude_provider: str) -> Optional[PendingGameDiscovery]:
    """
    Find a pending discovery from a different provider with a similar game name.
    """
    normalized_name = normalize_game_name(game_name)
    if not normalized_name or len(normalized_name) < 3:
        return None

    # Look for discoveries from OTHER providers with similar names
    candidates = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.source_provider != exclude_provider,
        PendingGameDiscovery.status == 'pending'
    ).all()

    for candidate in candidates:
        candidate_normalized = normalize_game_name(candidate.game_name)

        # Exact match after normalization
        if candidate_normalized == normalized_name:
            return candidate

        # Fuzzy match - one contains the other (for cases like "Destiny 2" vs "Destiny 2: Lightfall")
        if len(normalized_name) > 5 and len(candidate_normalized) > 5:
            if normalized_name in candidate_normalized or candidate_normalized in normalized_name:
                return candidate

    return None


def check_and_log_game_discovery(
    db: Session,
    provider: str,
    game_id: str,
    game_name: str,
    achievement_count: int = 0,
    sample_achievements: Optional[List[str]] = None,
    user_id: Optional[int] = None
) -> Optional[PendingGameDiscovery]:
    """
    Check if a game is known in platform_mappings.json.
    If not, log it for admin review.

    Also auto-detects cross-platform games by matching against discoveries
    from other providers.

    Args:
        db: Database session
        provider: Provider name (steam, xbox, psn, etc.)
        game_id: Provider-specific game ID
        game_name: Display name of the game
        achievement_count: Number of achievements the game has
        sample_achievements: First few achievement names for context
        user_id: ID of user who triggered the discovery

    Returns:
        PendingGameDiscovery if game was logged, None if already known
    """
    if not game_id or game_id == "TO_RESEARCH":
        return None

    # Check if game is already known
    known_ids = get_known_game_ids(provider)
    if game_id in known_ids:
        return None

    # Check if already in pending discoveries
    existing = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.source_provider == provider,
        PendingGameDiscovery.provider_game_id == game_id
    ).first()

    if existing:
        # Update existing discovery
        existing.discovery_count += 1
        existing.last_seen_at = datetime.utcnow()

        # Priority: base from user count, +100 if cross-platform
        base_priority = existing.discovery_count
        existing.priority = base_priority + (100 if existing.is_cross_platform else 0)

        # Update achievement count if higher
        if achievement_count > (existing.achievement_count or 0):
            existing.achievement_count = achievement_count

        # Update sample achievements if we have more
        if sample_achievements and (
            not existing.sample_achievements or
            len(sample_achievements) > len(existing.sample_achievements)
        ):
            existing.sample_achievements = sample_achievements[:5]

        db.commit()
        logger.info(
            f"Updated game discovery: {game_name} ({provider}:{game_id}) - "
            f"now {existing.discovery_count} users"
        )
        return existing

    # Check for cross-platform match BEFORE creating new discovery
    cross_match = find_cross_platform_match(db, game_name, provider)

    # Determine match_id
    if cross_match:
        # Use existing match_id or create new one from the matched discovery's id
        match_id = cross_match.cross_platform_match_id or cross_match.id
        is_cross_platform = True
        priority = 101  # Base 1 + 100 for cross-platform

        # Update the matched discovery too
        cross_match.cross_platform_match_id = match_id
        cross_match.is_cross_platform = True
        cross_match.priority = cross_match.discovery_count + 100

        logger.info(
            f"Cross-platform match detected: {game_name} ({provider}) <-> "
            f"{cross_match.game_name} ({cross_match.source_provider})"
        )
    else:
        match_id = None
        is_cross_platform = False
        priority = 1

    # Create new discovery
    discovery = PendingGameDiscovery(
        discovered_by_user_id=user_id,
        source_provider=provider,
        provider_game_id=game_id,
        game_name=game_name,
        achievement_count=achievement_count,
        sample_achievements=sample_achievements[:5] if sample_achievements else None,
        status='pending',
        priority=priority,
        discovery_count=1,
        cross_platform_match_id=match_id,
        is_cross_platform=is_cross_platform,
        first_discovered_at=datetime.utcnow(),
        last_seen_at=datetime.utcnow()
    )

    db.add(discovery)
    db.commit()

    # If this created a new cross-platform link, update match_id to use this discovery's id
    if is_cross_platform and match_id and cross_match:
        # Keep using the original match_id (from the first discovery)
        pass
    elif not match_id:
        # Set match_id to own id for potential future matches
        discovery.cross_platform_match_id = discovery.id
        db.commit()

    logger.info(f"New game discovered: {game_name} ({provider}:{game_id})" +
                (" [CROSS-PLATFORM]" if is_cross_platform else ""))
    return discovery


def detect_cross_platform_matches(db: Session) -> int:
    """
    Retroactively detect cross-platform matches in existing pending discoveries.
    Run this once to link existing discoveries.

    Returns the number of new cross-platform matches found.
    """
    matches_found = 0

    # Get all pending discoveries not yet marked as cross-platform
    discoveries = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.status == 'pending',
        PendingGameDiscovery.is_cross_platform == False
    ).all()

    # Group by normalized name
    by_normalized_name: Dict[str, List[PendingGameDiscovery]] = {}
    for d in discoveries:
        normalized = normalize_game_name(d.game_name)
        if normalized and len(normalized) >= 3:
            if normalized not in by_normalized_name:
                by_normalized_name[normalized] = []
            by_normalized_name[normalized].append(d)

    # Find groups with multiple providers
    for normalized_name, group in by_normalized_name.items():
        providers = set(d.source_provider for d in group)
        if len(providers) > 1:
            # This is a cross-platform game!
            # Use the first discovery's id as the match_id
            match_id = group[0].id

            for d in group:
                if not d.is_cross_platform:
                    d.is_cross_platform = True
                    d.cross_platform_match_id = match_id
                    d.priority = d.discovery_count + 100
                    matches_found += 1

            logger.info(f"Linked cross-platform discoveries: {normalized_name} ({', '.join(providers)})")

    db.commit()
    return matches_found


def get_cross_platform_candidates(db: Session, limit: int = 50) -> List[Dict[str, Any]]:
    """
    Get cross-platform game candidates grouped by match_id.
    These are the highest priority for adding to the Tapestry.
    """
    from sqlalchemy import func

    # Get all cross-platform discoveries
    discoveries = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.status == 'pending',
        PendingGameDiscovery.is_cross_platform == True
    ).order_by(PendingGameDiscovery.priority.desc()).all()

    # Group by match_id
    by_match: Dict[int, List[PendingGameDiscovery]] = {}
    for d in discoveries:
        mid = d.cross_platform_match_id or d.id
        if mid not in by_match:
            by_match[mid] = []
        by_match[mid].append(d)

    # Build result
    result = []
    for match_id, group in by_match.items():
        platforms = {}
        total_users = 0
        total_achievements = 0
        primary_name = group[0].game_name

        for d in group:
            platforms[d.source_provider] = {
                "game_id": d.provider_game_id,
                "game_name": d.game_name,
                "achievement_count": d.achievement_count or 0,
                "discovery_count": d.discovery_count,
            }
            total_users += d.discovery_count
            total_achievements = max(total_achievements, d.achievement_count or 0)

        result.append({
            "match_id": match_id,
            "primary_name": primary_name,
            "platforms": platforms,
            "platform_count": len(platforms),
            "total_users": total_users,
            "max_achievements": total_achievements,
        })

    # Sort by platform count (more = better), then by users
    result.sort(key=lambda x: (-x["platform_count"], -x["total_users"]))

    return result[:limit]


def get_pending_discoveries(
    db: Session,
    status: Optional[str] = None,
    provider: Optional[str] = None,
    limit: int = 50,
    offset: int = 0
) -> List[PendingGameDiscovery]:
    """Get pending game discoveries for admin review."""
    query = db.query(PendingGameDiscovery)

    if status:
        query = query.filter(PendingGameDiscovery.status == status)
    if provider:
        query = query.filter(PendingGameDiscovery.source_provider == provider)

    # Order by priority (most users first), then by discovery date
    query = query.order_by(
        PendingGameDiscovery.priority.desc(),
        PendingGameDiscovery.first_discovered_at.desc()
    )

    return query.offset(offset).limit(limit).all()


def get_discovery_stats(db: Session) -> Dict[str, Any]:
    """Get statistics about game discoveries."""
    total = db.query(func.count(PendingGameDiscovery.id)).scalar()
    pending = db.query(func.count(PendingGameDiscovery.id)).filter(
        PendingGameDiscovery.status == 'pending'
    ).scalar()
    added = db.query(func.count(PendingGameDiscovery.id)).filter(
        PendingGameDiscovery.status == 'added'
    ).scalar()

    by_provider = db.query(
        PendingGameDiscovery.source_provider,
        func.count(PendingGameDiscovery.id)
    ).filter(
        PendingGameDiscovery.status == 'pending'
    ).group_by(PendingGameDiscovery.source_provider).all()

    return {
        "total": total,
        "pending": pending,
        "added": added,
        "by_provider": {p: c for p, c in by_provider}
    }


def update_discovery_status(
    db: Session,
    discovery_id: int,
    status: str,
    admin_user_id: int,
    notes: Optional[str] = None,
    cross_platform_data: Optional[Dict] = None
) -> Optional[PendingGameDiscovery]:
    """Update the status of a game discovery."""
    discovery = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.id == discovery_id
    ).first()

    if not discovery:
        return None

    discovery.status = status
    discovery.reviewed_at = datetime.utcnow()
    discovery.reviewed_by_id = admin_user_id

    if notes:
        discovery.admin_notes = notes

    if cross_platform_data:
        discovery.available_on_steam = cross_platform_data.get("steam")
        discovery.available_on_xbox = cross_platform_data.get("xbox")
        discovery.available_on_psn = cross_platform_data.get("psn")
        discovery.steam_app_id = cross_platform_data.get("steam_app_id")
        discovery.xbox_title_id = cross_platform_data.get("xbox_title_id")
        discovery.psn_np_id = cross_platform_data.get("psn_np_id")
        discovery.cross_platform_notes = cross_platform_data.get("notes")
        discovery.has_forge_items = cross_platform_data.get("has_forge_items")
        discovery.forge_item_count = cross_platform_data.get("forge_item_count")

    db.commit()
    return discovery
