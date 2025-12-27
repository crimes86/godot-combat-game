"""
Platform mapping service for cross-platform achievement translation.

Translates Xbox/PSN achievement identifiers to canonical Steam IDs,
allowing items.json to remain Steam-centric while supporting all platforms.

The Tapestry: All achievements are connected through a magical weave.
Provider colors create subtle visual accents but are never explicitly named.
"""

import json
import os
from functools import lru_cache
from typing import Optional, Tuple
import logging

logger = logging.getLogger(__name__)

PLATFORM_MAPPINGS_PATH = os.path.join(
    os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json'
)

# Provider accent colors for visual identity
PROVIDER_COLORS = {
    "steam": "#1B9BD7",      # Steam blue
    "xbox": "#107C10",       # Xbox green
    "psn": "#003791",        # PlayStation blue
    "battlenet": "#00AEFF",  # Blizzard blue
    "roblox": "#00A2FF",     # Roblox blue
}

# The Tapestry lore - unified origin text
TAPESTRY_LORE = {
    "origin_text": "Threaded from the Tapestry",
    "flavor_variants": [
        "Woven from threads of distant triumph",
        "A fragment pulled from the eternal weave",
        "Bound by deeds written in other realms",
    ]
}


@lru_cache(maxsize=1)
def load_platform_mappings() -> dict:
    """Load platform mappings from JSON. Cached for performance."""
    try:
        with open(PLATFORM_MAPPINGS_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        logger.warning(f"Platform mappings file not found: {PLATFORM_MAPPINGS_PATH}")
        return {"games": {}, "exclusive_mappings": {}}
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in platform mappings: {e}")
        return {"games": {}, "exclusive_mappings": {}}


def clear_platform_mappings_cache():
    """Clear the cached mappings (useful for testing or hot-reload)."""
    load_platform_mappings.cache_clear()


def get_provider_color(provider: str) -> str:
    """Get the accent color for a provider."""
    return PROVIDER_COLORS.get(provider, "#FFFFFF")


def get_tapestry_lore() -> dict:
    """Get the Tapestry lore text for display."""
    return TAPESTRY_LORE


def translate_to_canonical(
    provider: str,
    app_id: str,
    api_name: str
) -> Tuple[str, str]:
    """
    Translate Xbox/PSN IDs to canonical Steam IDs.

    Args:
        provider: The provider name ("steam", "xbox", "psn", etc.)
        app_id: The platform-specific game/title ID
        api_name: The platform-specific achievement ID

    Returns:
        Tuple of (canonical_app_id, canonical_api_name) or original values if no mapping.
    """
    # Steam is already canonical
    if provider == "steam":
        return (app_id, api_name)

    mappings = load_platform_mappings()

    # Determine the key field for this provider's app ID
    platform_app_id_key = _get_platform_app_id_key(provider)
    platform_ach_id_key = _get_platform_ach_id_key(provider)

    if not platform_app_id_key:
        return (app_id, api_name)

    # Search for game by platform app_id
    for game_key, game_data in mappings.get("games", {}).items():
        platforms = game_data.get("platforms", {})
        platform_data = platforms.get(provider, {})

        # Skip placeholder values
        platform_app_id = platform_data.get(platform_app_id_key, "")
        if platform_app_id == "TO_RESEARCH" or not platform_app_id:
            continue

        # Check if this game matches
        if str(platform_app_id) != str(app_id):
            continue

        # Found the game - now find the achievement
        achievements = game_data.get("achievements", {})
        for canonical_api_name, ach_platforms in achievements.items():
            platform_ach = ach_platforms.get(provider, {})
            platform_ach_id = platform_ach.get(platform_ach_id_key, "")

            # Skip placeholders
            if platform_ach_id == "TO_RESEARCH" or not platform_ach_id:
                continue

            if str(platform_ach_id) == str(api_name):
                canonical = game_data.get("canonical", {})
                canonical_app_id = canonical.get("app_id", app_id)
                logger.debug(
                    f"Translated {provider}:{app_id}:{api_name} -> "
                    f"steam:{canonical_app_id}:{canonical_api_name}"
                )
                return (canonical_app_id, canonical_api_name)

    # No mapping found - return original
    logger.debug(f"No translation found for {provider}:{app_id}:{api_name}")
    return (app_id, api_name)


def get_exclusive_item_id(provider: str, app_id: str, api_name: str) -> Optional[str]:
    """
    Get item_id for platform-exclusive achievements.

    These are games that only exist on one platform (e.g., Bloodborne on PSN,
    Halo on Xbox) and have direct item mappings.

    Returns:
        The item_id if found, None otherwise.
    """
    mappings = load_platform_mappings()
    exclusive = mappings.get("exclusive_mappings", {}).get(provider, {})

    platform_app_id_key = _get_platform_app_id_key(provider)
    platform_ach_id_key = _get_platform_ach_id_key(provider)

    if not platform_app_id_key:
        return None

    for game_key, game_data in exclusive.items():
        game_app_id = game_data.get(platform_app_id_key, "")

        # Skip placeholders
        if game_app_id == "TO_RESEARCH" or not game_app_id:
            continue

        if str(game_app_id) != str(app_id):
            continue

        # Found the game - check achievements
        achievements = game_data.get("achievements", {})
        for ach_key, ach_data in achievements.items():
            ach_id = ach_data.get(platform_ach_id_key, "")

            if ach_id == "TO_RESEARCH" or not ach_id:
                continue

            if str(ach_id) == str(api_name):
                item_id = ach_data.get("item_id")
                if item_id:
                    logger.debug(
                        f"Found exclusive item mapping: {provider}:{app_id}:{api_name} -> {item_id}"
                    )
                return item_id

    return None


def is_cross_platform_game(steam_app_id: str) -> bool:
    """Check if a Steam game has cross-platform mappings configured."""
    mappings = load_platform_mappings()

    for game_key, game_data in mappings.get("games", {}).items():
        canonical = game_data.get("canonical", {})
        if canonical.get("app_id") == steam_app_id:
            # Check if any platform has non-placeholder values
            platforms = game_data.get("platforms", {})
            for platform, data in platforms.items():
                for key, value in data.items():
                    if value and value != "TO_RESEARCH":
                        return True
    return False


def get_game_platforms(steam_app_id: str) -> list:
    """Get list of platforms a game is mapped on (always includes steam)."""
    platforms = ["steam"]
    mappings = load_platform_mappings()

    for game_key, game_data in mappings.get("games", {}).items():
        canonical = game_data.get("canonical", {})
        if canonical.get("app_id") == steam_app_id:
            for platform, data in game_data.get("platforms", {}).items():
                # Check for non-placeholder values
                platform_app_id_key = _get_platform_app_id_key(platform)
                if platform_app_id_key:
                    value = data.get(platform_app_id_key, "")
                    if value and value != "TO_RESEARCH":
                        platforms.append(platform)
            break

    return platforms


def _get_platform_app_id_key(provider: str) -> Optional[str]:
    """Get the key name for a platform's game/title ID."""
    keys = {
        "xbox": "title_id",
        "psn": "np_communication_id",
    }
    return keys.get(provider)


def _get_platform_ach_id_key(provider: str) -> Optional[str]:
    """Get the key name for a platform's achievement ID."""
    keys = {
        "xbox": "achievement_id",
        "psn": "trophy_id",
    }
    return keys.get(provider)
