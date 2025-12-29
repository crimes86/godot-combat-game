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


def load_platform_mappings() -> Dict:
    """Load platform_mappings.json."""
    try:
        mappings_path = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json')
        with open(mappings_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Failed to load platform_mappings.json: {e}")
        return {"games": {}}


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

    if not game_data:
        return {"error": "Game not found in platform mappings"}

    canonical = game_data.get('canonical', {})
    canonical_app_id = canonical.get('app_id')
    target_platform_info = game_data.get('platforms', {}).get(target_platform, {})
    achievements_map = game_data.get('achievements', {})

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

    # Build list of unmapped achievements
    unmapped = []
    mapped = []

    for ach in canonical_achievements:
        ach_mapping = achievements_map.get(ach.api_name, {})
        target_mapping = ach_mapping.get(target_platform, {})

        # Check if unmapped (TO_RESEARCH)
        is_unmapped = False
        if isinstance(target_mapping, dict):
            for value in target_mapping.values():
                if value == "TO_RESEARCH":
                    is_unmapped = True
                    break

        ach_data = {
            "id": ach.id,
            "api_name": ach.api_name,
            "name": ach.name or ach.display_name or ach.api_name,
            "description": ach.description or "",
            "icon_url": ach.icon_url,
            "rarity_tier": ach.rarity_tier or "Common",
            "unlocked": ach.id in user_unlocked,
        }

        if is_unmapped:
            unmapped.append(ach_data)
        else:
            mapped.append({**ach_data, "mapping": target_mapping})

    # Get achievements from target platform (if available)
    target_app_id = target_platform_info.get('title_id') or target_platform_info.get('np_communication_id')
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

    for ach in target_achs:
        target_achievements.append({
            "id": ach.id,
            "api_name": ach.api_name,
            "name": ach.name or ach.display_name or ach.api_name,
            "description": ach.description or "",
            "icon_url": ach.icon_url,
            "rarity_tier": ach.rarity_tier or "Common",
            "unlocked": ach.id in user_unlocked,
        })

    return {
        "game_key": game_key,
        "game_name": game_data.get('_display_name', game_key),
        "canonical_platform": canonical.get('platform', 'steam'),
        "target_platform": target_platform,
        "unmapped_achievements": unmapped,
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
