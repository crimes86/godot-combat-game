"""
Visual Mapping Tool Service

Provides an intelligent flow for cross-platform achievement mapping:
1. Parse user's unlocked achievements
2. Find cross-platform games with unmapped achievements
3. Surface mapping opportunities for user
4. Propagate for community voting
5. Credit author and voters on approval
"""

from sqlalchemy.orm import Session
from sqlalchemy import func, distinct
from typing import Dict, List, Optional, Any, Tuple
from app.models import User, Achievement, AchievementCredit, ProviderAccount
import json
import os
import logging

logger = logging.getLogger(__name__)


def load_platform_mappings() -> Dict:
    """Load platform_mappings.json."""
    try:
        mappings_path = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json')
        with open(mappings_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load platform_mappings.json: {e}")
        return {"games": {}}


def _build_discovered_game_data(db: Session, game_key: str, target_platform: str) -> Optional[Dict]:
    """
    Build a virtual game_data structure from PendingGameDiscovery records.

    For auto-discovered cross-platform games, we don't have JSON entries yet.
    This builds the same structure from the discovery records.
    """
    from app.models import PendingGameDiscovery

    # Extract match_id from game_key (e.g., "discovered_1" -> 1)
    try:
        match_id = int(game_key.replace("discovered_", ""))
    except ValueError:
        return None

    # Get all discoveries with this match_id
    discoveries = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.cross_platform_match_id == match_id,
        PendingGameDiscovery.status == 'pending'
    ).all()

    if not discoveries:
        # Try using match_id as the discovery's own ID
        discovery = db.query(PendingGameDiscovery).filter(
            PendingGameDiscovery.id == match_id
        ).first()
        if discovery:
            discoveries = [discovery]
            # Also get any linked discoveries
            if discovery.cross_platform_match_id:
                linked = db.query(PendingGameDiscovery).filter(
                    PendingGameDiscovery.cross_platform_match_id == discovery.cross_platform_match_id,
                    PendingGameDiscovery.id != discovery.id
                ).all()
                discoveries.extend(linked)

    if not discoveries:
        return None

    # Determine canonical platform (prefer Steam)
    canonical_discovery = None
    target_discovery = None

    for d in discoveries:
        if d.source_provider == "steam":
            canonical_discovery = d
        if d.source_provider == target_platform:
            target_discovery = d

    # If no Steam, use the first one as canonical
    if not canonical_discovery:
        for pref in ["xbox", "psn", "battlenet"]:
            for d in discoveries:
                if d.source_provider == pref and d.source_provider != target_platform:
                    canonical_discovery = d
                    break
            if canonical_discovery:
                break

    if not canonical_discovery:
        canonical_discovery = discoveries[0]

    # Build game_data structure
    canonical_platform = canonical_discovery.source_provider
    canonical_app_id = canonical_discovery.provider_game_id

    # Build platforms dict
    platforms = {}
    for d in discoveries:
        if d.source_provider != canonical_platform:
            if d.source_provider == "steam":
                platforms[d.source_provider] = {"app_id": d.provider_game_id}
            elif d.source_provider == "xbox":
                platforms[d.source_provider] = {"title_id": d.provider_game_id}
            elif d.source_provider == "psn":
                platforms[d.source_provider] = {"np_communication_id": d.provider_game_id}
            else:
                platforms[d.source_provider] = {"app_id": d.provider_game_id}

    # Build canonical dict
    canonical = {"platform": canonical_platform}
    if canonical_platform == "steam":
        canonical["app_id"] = canonical_app_id
    elif canonical_platform == "xbox":
        canonical["title_id"] = canonical_app_id
    elif canonical_platform == "psn":
        canonical["np_communication_id"] = canonical_app_id
    else:
        canonical["app_id"] = canonical_app_id

    # Check if there are any existing mappings under game_{app_id} key
    # (contributions may have been approved and saved there)
    mappings = load_platform_mappings()
    achievements = {}

    # Check for mappings under game_{steam_app_id}
    if canonical_platform == "steam":
        alt_game_key = f"game_{canonical_app_id}"
    else:
        # For non-Steam canonical, check if we have Steam in platforms
        steam_app_id = platforms.get("steam", {}).get("app_id")
        alt_game_key = f"game_{steam_app_id}" if steam_app_id else None

    if alt_game_key:
        alt_game_data = mappings.get('games', {}).get(alt_game_key, {})
        achievements = alt_game_data.get('achievements', {})
        logger.info(f"Loaded {len(achievements)} existing mappings for discovered game from {alt_game_key}")

    return {
        "_display_name": canonical_discovery.game_name,
        "canonical": canonical,
        "platforms": platforms,
        "achievements": achievements,  # Include any existing mappings
        "_is_discovered": True,
        "_alt_game_key": alt_game_key,  # Track the alternate key for reference
    }


# Cache for items.json data (set to None to reload)
_items_cache = None


def clear_items_cache():
    """Clear the items.json cache to force reload."""
    global _items_cache
    _items_cache = None


def load_items_data() -> Dict:
    """Load items.json with achievement mappings and candidates."""
    global _items_cache
    if _items_cache is not None:
        return _items_cache

    try:
        items_path = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'items.json')
        with open(items_path, 'r') as f:
            _items_cache = json.load(f)
            return _items_cache
    except Exception as e:
        print(f"Failed to load items.json: {e}")
        return {"achievement_mappings": {}, "candidate_achievements": {}, "items": []}


def get_item_for_achievement(app_id: str, api_name: str) -> Optional[Dict]:
    """
    Check if an achievement has a forge item mapped to it.

    Returns item details if found, None otherwise.
    Keys to check: "app_id:api_name" format
    """
    items_data = load_items_data()
    mappings = items_data.get("achievement_mappings", {})
    items_list = items_data.get("items", [])

    # Build lookup key
    key = f"{app_id}:{api_name}"

    item_id = mappings.get(key)
    if not item_id:
        return None

    # Find item details in items array
    items_by_id = {item["item_id"]: item for item in items_list if "item_id" in item}
    item = items_by_id.get(item_id)

    if item:
        return {
            "item_id": item_id,
            "item_name": item.get("item_name", item_id),
            "item_type": item.get("item_type", "unknown"),
            "weapon_type": item.get("weapon_type"),
            "base_rarity": item.get("base_rarity", "common"),
            "theme": item.get("theme"),
        }

    # Item ID exists in mappings but not in items array (might be defined differently)
    return {
        "item_id": item_id,
        "item_name": item_id.replace("_", " ").title(),
        "item_type": "unknown",
    }


def get_candidate_for_achievement(app_id: str, api_name: str) -> Optional[Dict]:
    """
    Check if an achievement is a candidate for a future forge item.

    Returns candidate details if found, None otherwise.
    """
    items_data = load_items_data()
    candidates = items_data.get("candidate_achievements", {})

    # Build lookup key
    key = f"{app_id}:{api_name}"

    candidate = candidates.get(key)
    if not candidate or not isinstance(candidate, dict):
        return None

    return {
        "proposed_item": candidate.get("proposed_item", "Unnamed Item"),
        "proposed_type": candidate.get("proposed_type", "unknown"),
        "weapon_type": candidate.get("weapon_type"),
        "priority": candidate.get("priority", "medium"),
        "notes": candidate.get("notes", ""),
    }


def get_achievement_forge_status(app_id: str, api_name: str) -> Dict:
    """
    Get the forge status of an achievement.

    Returns:
        {
            "has_item": bool,
            "item": {...} or None,
            "is_candidate": bool,
            "candidate": {...} or None,
        }
    """
    item = get_item_for_achievement(app_id, api_name)
    candidate = get_candidate_for_achievement(app_id, api_name)

    return {
        "has_item": item is not None,
        "item": item,
        "is_candidate": candidate is not None,
        "candidate": candidate,
    }


def get_crossplatform_games_needing_mappings() -> List[Dict]:
    """
    Get all games from platform_mappings.json that:
    1. Have cross-platform presence (defined in platforms section)
    2. Have achievements with "TO_RESEARCH" entries (unmapped)

    Returns list of games with their unmapped achievement info.
    """
    mappings = load_platform_mappings()
    games_needing_work = []

    for game_key, game_data in mappings.get('games', {}).items():
        display_name = game_data.get('_display_name', game_key.replace('_', ' ').title())
        canonical = game_data.get('canonical', {})
        platforms = game_data.get('platforms', {})
        achievements = game_data.get('achievements', {})

        if not canonical or not platforms or not achievements:
            continue

        # Count unmapped achievements per platform
        unmapped_by_platform = {}
        total_unmapped = 0

        for ach_key, ach_data in achievements.items():
            for platform in ['xbox', 'psn', 'battlenet', 'roblox']:
                platform_data = ach_data.get(platform, {})
                if isinstance(platform_data, dict):
                    # Check for TO_RESEARCH in any field
                    for value in platform_data.values():
                        if value == "TO_RESEARCH":
                            unmapped_by_platform[platform] = unmapped_by_platform.get(platform, 0) + 1
                            total_unmapped += 1
                            break

        if total_unmapped > 0:
            games_needing_work.append({
                "game_key": game_key,
                "display_name": display_name,
                "canonical_platform": canonical.get('platform', 'steam'),
                "canonical_app_id": canonical.get('app_id'),
                "platforms": list(platforms.keys()),
                "total_achievements": len(achievements),
                "unmapped_by_platform": unmapped_by_platform,
                "total_unmapped": total_unmapped,
            })

    # Sort by most unmapped first
    games_needing_work.sort(key=lambda x: -x['total_unmapped'])
    return games_needing_work


def get_user_mapping_opportunities(db: Session, user_id: int) -> List[Dict]:
    """
    Find mapping opportunities for a user based on their achievements.

    Returns games where:
    1. The user has achievements from the canonical platform (Steam)
    2. The game has unmapped achievements to other platforms
    3. User could potentially help map them
    """
    crossplatform_games = get_crossplatform_games_needing_mappings()

    if not crossplatform_games:
        return []

    # Get user's achievements grouped by app_id
    user_achievements = (
        db.query(
            Achievement.app_id,
            AchievementCredit.provider_name,
            func.count(AchievementCredit.id).label('count')
        )
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.is_original_claim == True
        )
        .group_by(Achievement.app_id, AchievementCredit.provider_name)
        .all()
    )

    # Build lookup: app_id -> {provider: count}
    user_games = {}
    for app_id, provider, count in user_achievements:
        if app_id not in user_games:
            user_games[app_id] = {}
        user_games[app_id][provider] = count

    opportunities = []

    for game in crossplatform_games:
        canonical_app_id = game['canonical_app_id']

        # Check if user has achievements from this game
        if canonical_app_id in user_games:
            user_provider_data = user_games[canonical_app_id]

            # User has achievements - this is an opportunity
            opportunity = {
                **game,
                "user_achievement_count": sum(user_provider_data.values()),
                "user_providers": list(user_provider_data.keys()),
                "can_contribute": True,
            }
            opportunities.append(opportunity)

    # Sort by user's achievement count (more = more qualified)
    opportunities.sort(key=lambda x: -x['user_achievement_count'])
    return opportunities


def get_unmapped_achievements_for_game(
    db: Session,
    user_id: int,
    game_key: str,
    target_platform: str
) -> Dict[str, Any]:
    """
    Get unmapped achievements for a specific game that need mapping to target platform.

    Returns:
    - canonical_achievements: List of canonical (Steam) achievements
    - target_platform_achievements: List of achievements from target platform (if user has any)
    - unmapped_canonical: Canonical achievements that need mapping to target platform
    """
    mappings = load_platform_mappings()
    game_data = mappings.get('games', {}).get(game_key)

    # Handle discovered games (from PendingGameDiscovery table)
    if not game_data and game_key.startswith("discovered_"):
        game_data = _build_discovered_game_data(db, game_key, target_platform)

    if not game_data:
        return {"error": "Game not found in platform mappings"}

    canonical = game_data.get('canonical', {})
    canonical_platform = canonical.get('platform', 'steam')
    platforms_info = game_data.get('platforms', {})
    target_platform_info = platforms_info.get(target_platform, {})
    achievements_map = game_data.get('achievements', {})

    # Get the canonical app_id based on platform type
    if canonical_platform == 'steam':
        canonical_app_id = canonical.get('app_id')
        source_platform = 'steam'
    elif canonical_platform == 'xbox':
        canonical_app_id = canonical.get('title_id')
        source_platform = 'xbox'
    elif canonical_platform == 'psn':
        canonical_app_id = canonical.get('np_communication_id')
        source_platform = 'psn'
    else:
        canonical_app_id = canonical.get('app_id')
        source_platform = canonical_platform

    # For Xbox/PSN canonical games, if we don't have data, use Steam as source if available
    # This is a practical workaround since Steam data is most readily available
    use_steam_as_source = False
    if canonical_platform in ['xbox', 'psn'] and 'steam' in platforms_info:
        steam_info = platforms_info.get('steam', {})
        steam_app_id = steam_info.get('app_id')
        if steam_app_id:
            # Check if we have Steam achievements in DB
            from app.models import Achievement as AchModel
            steam_ach_count = db.query(AchModel).filter(AchModel.app_id == steam_app_id).count()
            canonical_ach_count = db.query(AchModel).filter(AchModel.app_id == canonical_app_id).count() if canonical_app_id else 0

            if steam_ach_count > canonical_ach_count:
                # Use Steam as source since we have more data there
                canonical_app_id = steam_app_id
                source_platform = 'steam'
                use_steam_as_source = True

    # Get canonical achievements from DB
    canonical_achievements = (
        db.query(Achievement)
        .filter(Achievement.app_id == canonical_app_id)
        .order_by(Achievement.name)
        .all()
    )

    # Get user's unlocked achievement IDs
    user_unlocked = set(
        credit.achievement_id for credit in
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.is_original_claim == True
        )
        .all()
    )

    # Get pending contributions for this game/target platform
    from app.models import CommunityContribution
    pending_contributions = db.query(CommunityContribution).filter(
        CommunityContribution.contribution_type == "platform_mapping",
        CommunityContribution.status == "pending",
    ).all()

    # Build set of api_names that have pending mappings
    # Check both directions: source→target and target→source
    pending_source_api_names = set()
    pending_target_api_names = set()
    for contrib in pending_contributions:
        data = contrib.data or {}
        contrib_source = data.get("source_platform") or "steam"
        contrib_target = data.get("target_platform")

        # If this pending is source→target_platform, mark source api_name
        if contrib_target == target_platform:
            pending_source_api_names.add(data.get("steam_api_name"))

        # If this pending is target_platform→something, mark target api_name as pending on source side
        if contrib_source == target_platform:
            pending_target_api_names.add(data.get("target_api_name"))

        # Also check reverse direction for the current source platform
        if contrib_target == source_platform:
            pending_target_api_names.add(data.get("target_api_name"))
        if contrib_source == source_platform:
            pending_source_api_names.add(data.get("steam_api_name"))

    # Build list of unmapped achievements
    unmapped = []
    mapped = []

    for ach in canonical_achievements:
        ach_mapping = achievements_map.get(ach.api_name, {})
        target_mapping = ach_mapping.get(target_platform, {})

        # Check if ALREADY MAPPED (has real value, not TO_RESEARCH or empty)
        # target_mapping can be:
        #   - a string (direct api_name mapping, e.g., "XBOX_ACH_NAME")
        #   - a dict (legacy format with nested values)
        #   - empty dict/None (unmapped)
        is_mapped = False
        if isinstance(target_mapping, str) and target_mapping and target_mapping != "TO_RESEARCH":
            # Direct string mapping (most common after contribution approval)
            is_mapped = True
        elif isinstance(target_mapping, dict) and target_mapping:
            # Dict format - check if any value is a real mapping
            for value in target_mapping.values():
                if value and value != "TO_RESEARCH":
                    is_mapped = True
                    break

        # Get forge status for this achievement
        forge_status = get_achievement_forge_status(str(canonical_app_id), ach.api_name)

        ach_data = {
            "id": ach.id,
            "api_name": ach.api_name,
            "name": ach.name or ach.display_name or ach.api_name,
            "description": ach.description or "",
            "icon_url": ach.icon_url,
            "rarity_tier": ach.rarity_tier or "Common",
            "unlocked": ach.id in user_unlocked,
            # Forge status
            "has_item": forge_status["has_item"],
            "item": forge_status["item"],
            "is_candidate": forge_status["is_candidate"],
            "candidate": forge_status["candidate"],
            # Pending mapping check - check both source and target sets
            "has_pending": ach.api_name in pending_source_api_names or ach.api_name in pending_target_api_names,
        }

        # ALL achievements are available for mapping unless already mapped
        ach_data["is_mapped"] = is_mapped
        if is_mapped:
            ach_data["mapping"] = target_mapping
            mapped.append(ach_data)
        else:
            unmapped.append(ach_data)

    # Get achievements from target platform (if available)
    # Different platforms use different ID fields
    target_app_id = (
        target_platform_info.get('app_id') or  # Steam
        target_platform_info.get('title_id') or  # Xbox
        target_platform_info.get('np_communication_id')  # PSN
    )
    target_achievements = []
    discovered_app_id = None

    if target_app_id and target_app_id != "TO_RESEARCH":
        # We know the target platform's app_id - query directly
        target_achs = (
            db.query(Achievement)
            .filter(Achievement.app_id == target_app_id)
            .order_by(Achievement.name)
            .all()
        )
    else:
        # title_id unknown - try to find by game name matching
        # Look for games in the Game table that match this game's display name
        from app.models import Game
        display_name = game_data.get('_display_name', game_key)

        # Find games with similar names from the target platform's provider
        # Game.name is stored when achievements sync
        matching_games = (
            db.query(Game)
            .filter(Game.name.ilike(f"%{display_name}%"))
            .all()
        )

        # Filter to games that are from the target platform (by checking achievements)
        target_achs = []
        for game in matching_games:
            # Check if this game has achievements credited from the target platform
            has_platform_credits = (
                db.query(AchievementCredit)
                .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
                .filter(
                    Achievement.app_id == game.app_id,
                    AchievementCredit.provider_name == target_platform
                )
                .first()
            )

            if has_platform_credits:
                # Found a match - get all achievements for this app_id
                discovered_app_id = game.app_id
                target_achs = (
                    db.query(Achievement)
                    .filter(Achievement.app_id == game.app_id)
                    .order_by(Achievement.name)
                    .all()
                )
                break

    # Build set of target api_names that are already mapped
    mapped_target_api_names = set()
    for ach_key, ach_mapping in achievements_map.items():
        target_mapping = ach_mapping.get(target_platform)
        if isinstance(target_mapping, str) and target_mapping and target_mapping != "TO_RESEARCH":
            mapped_target_api_names.add(target_mapping)
        elif isinstance(target_mapping, dict):
            for value in target_mapping.values():
                if value and value != "TO_RESEARCH":
                    mapped_target_api_names.add(value)

    for ach in target_achs:
        # Get forge status for target achievement (using target app_id)
        target_ach_app_id = target_app_id or discovered_app_id or ""
        forge_status = get_achievement_forge_status(str(target_ach_app_id), ach.api_name)

        # Check if this target achievement is already mapped
        is_target_mapped = ach.api_name in mapped_target_api_names
        has_target_pending = ach.api_name in pending_target_api_names

        target_achievements.append({
            "id": ach.id,
            "api_name": ach.api_name,
            "name": ach.name or ach.display_name or ach.api_name,
            "description": ach.description or "",
            "icon_url": ach.icon_url,
            "rarity_tier": ach.rarity_tier or "Common",
            "unlocked": ach.id in user_unlocked,
            # Forge status
            "has_item": forge_status["has_item"],
            "item": forge_status["item"],
            "is_candidate": forge_status["is_candidate"],
            "candidate": forge_status["candidate"],
            # Mapping status
            "is_mapped": is_target_mapped,
            "has_pending": has_target_pending,
        })

    return {
        "game_key": game_key,
        "game_name": game_data.get('_display_name', game_key),
        "canonical_platform": canonical_platform,
        "source_platform": source_platform,  # Actual platform being used as source (may differ if using Steam fallback)
        "canonical_app_id": canonical_app_id,
        "use_steam_as_source": use_steam_as_source,
        "target_platform": target_platform,
        "unmapped_achievements": unmapped,
        "canonical_achievements": unmapped + mapped,  # All canonical achievements
        "mapped_achievements": mapped,
        "target_achievements": target_achievements,
        "has_target_data": bool(target_achievements),
        "discovered_app_id": discovered_app_id,  # Auto-discovered from game name matching
    }


def get_user_games_by_provider(db: Session, user_id: int) -> Dict[str, List[Dict]]:
    """
    Get all games the user has achievements for, grouped by provider.
    Also enriches with cross-platform mapping opportunity info.
    """
    # Get all user's achievement credits with achievement info
    credits = (
        db.query(
            AchievementCredit.provider_name,
            Achievement.app_id,
            func.count(AchievementCredit.id).label('count')
        )
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .filter(AchievementCredit.user_id == user_id)
        .filter(AchievementCredit.is_original_claim == True)
        .group_by(AchievementCredit.provider_name, Achievement.app_id)
        .all()
    )

    # Get crossplatform games info
    crossplatform = {g['canonical_app_id']: g for g in get_crossplatform_games_needing_mappings()}

    # Group by provider
    result = {}

    for provider, app_id, count in credits:
        if provider not in result:
            result[provider] = []

        # Check if this is a crossplatform game
        crossplatform_info = crossplatform.get(app_id)

        display_name = None
        needs_mappings = False
        unmapped_count = 0

        if crossplatform_info:
            display_name = crossplatform_info['display_name']
            needs_mappings = True
            unmapped_count = crossplatform_info['total_unmapped']
        else:
            display_name = get_game_display_name(app_id) or f"Game {app_id}"

        result[provider].append({
            "app_id": app_id,
            "display_name": display_name,
            "count": count,
            "needs_mappings": needs_mappings,
            "unmapped_count": unmapped_count,
        })

    # Sort: games needing mappings first, then by count
    for provider in result:
        result[provider].sort(key=lambda x: (-x['needs_mappings'], -x['count']))

    return result


def get_game_display_name(app_id: str) -> Optional[str]:
    """Look up game display name from platform_mappings.json."""
    mappings = load_platform_mappings()

    for game_key, game_data in mappings.get('games', {}).items():
        canonical = game_data.get('canonical', {})
        platforms = game_data.get('platforms', {})

        # Check canonical
        if canonical.get('app_id') == app_id:
            return game_data.get('_display_name', game_key.replace('_', ' ').title())

        # Check other platforms
        for platform, platform_data in platforms.items():
            if isinstance(platform_data, dict):
                if platform_data.get('title_id') == app_id or platform_data.get('app_id') == app_id:
                    return game_data.get('_display_name', game_key.replace('_', ' ').title())

    return None


def get_achievements_for_game(
    db: Session,
    user_id: int,
    provider: str,
    app_id: str,
    search: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Get all achievements for a specific game/provider, with user's unlock status.
    """
    # Get all achievements for this app_id
    query = db.query(Achievement).filter(Achievement.app_id == app_id)

    if search:
        search_lower = f"%{search.lower()}%"
        query = query.filter(
            (Achievement.name.ilike(search_lower)) |
            (Achievement.description.ilike(search_lower))
        )

    achievements = query.order_by(Achievement.name).all()

    # Get user's unlocked achievement IDs for this provider
    unlocked_ids = set(
        credit.achievement_id for credit in
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.provider_name == provider,
            AchievementCredit.is_original_claim == True
        )
        .all()
    )

    result = []
    for ach in achievements:
        result.append({
            "id": ach.id,
            "api_name": ach.api_name,
            "name": ach.name or ach.display_name or ach.api_name,
            "description": ach.description or "",
            "icon_url": ach.icon_url,
            "rarity_tier": ach.rarity_tier or "Common",
            "unlocked": ach.id in unlocked_ids
        })

    # Sort: unlocked first, then by name
    result.sort(key=lambda x: (not x['unlocked'], x['name'].lower()))

    return result


def validate_mapping_submission(
    db: Session,
    user_id: int,
    left_achievement_id: int,
    right_achievement_id: int
) -> Dict[str, Any]:
    """
    Validate a mapping submission.
    User must have unlocked at least one of the achievements.
    """
    left_ach = db.query(Achievement).filter(Achievement.id == left_achievement_id).first()
    right_ach = db.query(Achievement).filter(Achievement.id == right_achievement_id).first()

    if not left_ach or not right_ach:
        return {"valid": False, "error": "Achievement not found"}

    if left_ach.app_id == right_ach.app_id:
        return {"valid": False, "error": "Both achievements are from the same game"}

    # Check user has unlocked at least one
    user_credits = db.query(AchievementCredit).filter(
        AchievementCredit.user_id == user_id,
        AchievementCredit.achievement_id.in_([left_achievement_id, right_achievement_id]),
        AchievementCredit.is_original_claim == True
    ).all()

    if not user_credits:
        return {
            "valid": False,
            "error": "You must have unlocked at least one of these achievements to submit a mapping"
        }

    return {
        "valid": True,
        "left": {
            "id": left_ach.id,
            "app_id": left_ach.app_id,
            "api_name": left_ach.api_name,
            "name": left_ach.name
        },
        "right": {
            "id": right_ach.id,
            "app_id": right_ach.app_id,
            "api_name": right_ach.api_name,
            "name": right_ach.name
        }
    }


def get_provider_color(provider: str) -> str:
    """Get the brand color for a provider."""
    colors = {
        "steam": "#1B9BD7",
        "xbox": "#107C10",
        "psn": "#003791",
        "battlenet": "#00AEFF",
        "roblox": "#00A2FF",
        "github": "#6e5494",
        "discord": "#5865F2"
    }
    return colors.get(provider, "#888888")


def get_provider_display_name(provider: str) -> str:
    """Get display name for a provider."""
    names = {
        "steam": "Steam",
        "xbox": "Xbox",
        "psn": "PlayStation",
        "battlenet": "Battle.net",
        "roblox": "Roblox",
        "github": "GitHub",
        "discord": "Discord"
    }
    return names.get(provider, provider.title())
