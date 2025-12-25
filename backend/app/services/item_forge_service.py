# app/services/item_forge_service.py
"""
Item forge computation service.

Computes in-game item properties from achievement data at forge time.
Reads item catalog from data/items.json (source of truth shared with Godot).
"""

import json
import os
import hashlib
from datetime import datetime
from typing import Optional, Dict, List, Any
from functools import lru_cache

# =============================================================================
# CATALOG LOADING
# =============================================================================

ITEMS_JSON_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'items.json')


@lru_cache(maxsize=1)
def load_items_catalog() -> Dict[str, Any]:
    """Load the items catalog from JSON. Cached for performance."""
    try:
        with open(ITEMS_JSON_PATH, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        # Return minimal fallback if file doesn't exist
        return {
            "items": [],
            "themes": {},
            "fallbacks": {},
            "weapon_types": {"core": {}, "extended": {}},
        }


def reload_catalog():
    """Force reload the catalog (call after items.json updates)."""
    load_items_catalog.cache_clear()
    return load_items_catalog()


def get_catalog() -> Dict[str, Any]:
    """Get the current items catalog."""
    return load_items_catalog()


def get_items() -> List[Dict[str, Any]]:
    """Get all items from catalog."""
    return get_catalog().get("items", [])


def get_themes() -> Dict[str, Any]:
    """Get all themes from catalog."""
    return get_catalog().get("themes", {})


def get_item_by_id(item_id: str) -> Optional[Dict[str, Any]]:
    """Look up item by ID."""
    for item in get_items():
        if item.get("item_id") == item_id:
            return item
    return None


def get_items_by_theme(theme: str) -> List[Dict[str, Any]]:
    """Get all items for a theme."""
    return [item for item in get_items() if item.get("theme") == theme]


def get_items_by_type(item_type: str) -> List[Dict[str, Any]]:
    """Get all items of a specific type."""
    return [item for item in get_items() if item.get("item_type") == item_type]


def get_available_items() -> List[Dict[str, Any]]:
    """Get items that have sprites available."""
    return [item for item in get_items() if item.get("has_sprites", False)]


def get_production_items() -> List[Dict[str, Any]]:
    """
    Get only production-ready items (those with valid achievement mappings).

    Filters out items with placeholder achievement IDs (e.g., Blizzard items
    awaiting API integration). This ensures backend catalog matches Godot's
    ForgeItemDB which only loads items with valid mappings.

    Returns:
        List of items that have valid achievement mappings in items.json
    """
    mappings = get_achievement_mappings()
    all_items = get_items()

    # Get set of item_ids that have valid achievement mappings
    valid_item_ids = set(mappings.values())

    # Filter items to only those with valid mappings
    production_items = [
        item for item in all_items
        if item.get("item_id") in valid_item_ids
    ]

    return production_items


def get_achievement_mappings() -> Dict[str, str]:
    """Get explicit achievement→item mappings."""
    mappings = get_catalog().get("achievement_mappings", {})
    # Filter out comment keys
    return {k: v for k, v in mappings.items() if not k.startswith("_")}


def get_mapped_item(app_id: str, api_name: str) -> Optional[Dict[str, Any]]:
    """
    Check if achievement has an explicit item mapping.

    Returns the mapped item if found, None otherwise.
    """
    mappings = get_achievement_mappings()
    key = f"{app_id}:{api_name}"

    if key in mappings:
        item_id = mappings[key]
        return get_item_by_id(item_id)

    return None


# =============================================================================
# THEME DETECTION
# =============================================================================

def detect_theme(app_id: str, provider: str) -> str:
    """Detect theme from app_id or provider."""
    themes = get_themes()

    # Check app_id against each theme
    for theme_key, theme_data in themes.items():
        if app_id in theme_data.get("app_ids", []):
            return theme_key

    # Check if provider itself is a theme (discord, github)
    if provider in themes:
        return provider

    return "generic"


def get_theme_color(theme: str) -> str:
    """Get the primary color for a theme."""
    themes = get_themes()
    return themes.get(theme, {}).get("color", "#888888")


def get_theme_effects(theme: str) -> List[str]:
    """Get available effects for a theme."""
    themes = get_themes()
    return themes.get(theme, {}).get("effects", ["standard_particles"])


# =============================================================================
# ITEM SELECTION
# =============================================================================

def select_item_for_achievement(
    achievement_id: int,
    api_name: str,
    app_id: str,
    provider: str,
    rarity_tier: str,
) -> Dict[str, Any]:
    """
    Select an item from the catalog for an achievement.

    Selection priority:
    1. Explicit mapping in achievement_mappings (app_id:api_name → item_id)
    2. Items matching game theme + similar rarity
    3. Items matching game theme (any rarity)
    4. Generic items matching rarity
    5. Fallback item
    """
    # Priority 1: Check explicit mapping
    mapped_item = get_mapped_item(app_id, api_name)
    if mapped_item:
        return mapped_item

    # Priority 2-5: Theme-based selection
    theme = detect_theme(app_id, provider)
    rarity_lower = (rarity_tier or "common").lower()

    # Get items for this theme
    theme_items = get_items_by_theme(theme)

    # Filter by availability if possible
    available_theme_items = [i for i in theme_items if i.get("has_sprites", False)]
    if not available_theme_items:
        available_theme_items = theme_items  # Fall back to all theme items

    # Try to match rarity
    matching_rarity = [i for i in available_theme_items if i.get("base_rarity", "").lower() == rarity_lower]

    # Choose pool based on what's available
    if matching_rarity:
        pool = matching_rarity
    elif available_theme_items:
        pool = available_theme_items
    else:
        # Fall back to any available items
        pool = get_available_items() or get_items()

    if not pool:
        # Ultimate fallback
        return get_fallback_item("weapon")

    # Deterministic selection using hash
    hash_input = f"{achievement_id}:{api_name}:{app_id}"
    hash_value = int(hashlib.md5(hash_input.encode()).hexdigest(), 16)
    index = hash_value % len(pool)

    return pool[index]


def get_fallback_item(item_type: str) -> Dict[str, Any]:
    """Get fallback item for a type."""
    fallbacks = get_catalog().get("fallbacks", {})
    fallback = fallbacks.get(item_type, fallbacks.get("weapon", {}))

    return {
        "item_id": fallback.get("item_id", "basic_item"),
        "item_name": "Basic " + item_type.replace("_", " ").title(),
        "item_type": item_type,
        "weapon_type": "sword" if item_type == "weapon" else None,
        "base_rarity": "common",
        "theme": "generic",
        "visuals": {
            "sprite_folder": fallback.get("sprite_folder"),
            "effect": "standard_particles",
            "glow_color": "#888888"
        }
    }


# =============================================================================
# EFFORT & VINTAGE CALCULATIONS
# =============================================================================

EFFORT_TIERS = [
    (90, "Exceptional"),
    (75, "Superior"),
    (60, "Remarkable"),
    (45, "Notable"),
    (30, "Solid"),
    (15, "Modest"),
    (0, "Common"),
]

VINTAGE_PREFIXES = [
    (10, "Ancient"),
    (7, "Venerable"),
    (5, "Veteran's"),
    (3, "Seasoned"),
    (1, "Proven"),
    (0, ""),
]

RARITY_PREFIXES = {
    "legendary": "Mythic",
    "epic": "Exalted",
    "rare": "Enchanted",
    "uncommon": "Refined",
    "common": "",
}


def compute_effect_intensity(effort_score: float) -> float:
    """Convert effort score (0-100) to effect intensity (0.0-1.0)."""
    if effort_score is None:
        effort_score = 50.0
    normalized = max(0, min(100, effort_score)) / 100.0
    return round(0.3 + (normalized ** 0.8) * 0.7, 3)


def get_effort_tier(effort_score: float) -> str:
    """Get effort tier label from score."""
    if effort_score is None:
        effort_score = 50.0
    for threshold, tier_name in EFFORT_TIERS:
        if effort_score >= threshold:
            return tier_name
    return "Common"


def calculate_vintage_years(unlocked_at: Optional[datetime]) -> int:
    """Calculate years since achievement was unlocked."""
    if not unlocked_at:
        return 0
    now = datetime.utcnow()
    delta = now - unlocked_at
    return max(0, int(delta.days / 365.25))


def get_vintage_prefix(vintage_years: int) -> str:
    """Get name prefix based on vintage."""
    for threshold, prefix in VINTAGE_PREFIXES:
        if vintage_years >= threshold:
            return prefix
    return ""


def generate_item_name(
    base_name: str,
    rarity: str,
    vintage_years: int,
    is_secret: bool
) -> str:
    """
    Generate full item name with prefixes.

    Examples:
    - "Ancient Mythic Coiled Sword" (10yr old Legendary)
    - "Occult Enchanted Frost Spear" (secret Rare)
    """
    prefixes = []

    vintage_prefix = get_vintage_prefix(vintage_years)
    if vintage_prefix:
        prefixes.append(vintage_prefix)

    if is_secret:
        prefixes.append("Occult")

    rarity_prefix = RARITY_PREFIXES.get((rarity or "common").lower(), "")
    if rarity_prefix:
        prefixes.append(rarity_prefix)

    if prefixes:
        return f"{' '.join(prefixes)} {base_name}"
    return base_name


# =============================================================================
# MAIN COMPUTATION FUNCTION
# =============================================================================

def compute_forged_item(
    achievement_id: int,
    api_name: str,
    app_id: str,
    game_name: str,
    provider: str,
    rarity_tier: str,
    effort_score: float,
    hidden: bool,
    unlocked_at: Optional[datetime],
) -> dict:
    """
    Compute all forged item properties from achievement data.

    Returns dict with all fields needed for ForgedAchievement model.
    All computations are deterministic.
    """
    # Select item from catalog
    selected_item = select_item_for_achievement(
        achievement_id=achievement_id,
        api_name=api_name,
        app_id=app_id,
        provider=provider,
        rarity_tier=rarity_tier,
    )

    # Get visual properties from item
    visuals = selected_item.get("visuals", {})
    theme = selected_item.get("theme", "generic")

    # Compute dynamic properties
    effect_intensity = compute_effect_intensity(effort_score)
    effort_tier = get_effort_tier(effort_score)
    vintage_years = calculate_vintage_years(unlocked_at)

    # Generate full item name with prefixes
    item_name = generate_item_name(
        base_name=selected_item.get("item_name", "Unknown Item"),
        rarity=rarity_tier or "common",
        vintage_years=vintage_years,
        is_secret=hidden or False,
    )

    # Select effect - prefer item's effect, fall back to theme default
    effect_name = visuals.get("effect")
    if not effect_name:
        theme_effects = get_theme_effects(theme)
        effect_name = theme_effects[0] if theme_effects else "standard_particles"

    # Get glow color - prefer item's color, fall back to theme color
    glow_color = visuals.get("glow_color") or get_theme_color(theme)

    return {
        "item_type": selected_item.get("item_type", "weapon"),
        "weapon_type": selected_item.get("weapon_type"),
        "item_id": selected_item.get("item_id", "unknown"),
        "item_name": item_name,
        "item_rarity": (rarity_tier or "common").lower(),
        "effect_intensity": effect_intensity,
        "effect_name": effect_name,
        "glow_color": glow_color,
        "effort_tier": effort_tier,
        "vintage_years": vintage_years,
        "is_secret": hidden or False,
        "theme": theme,
        "sprite_folder": visuals.get("sprite_folder"),
        "icon_url": visuals.get("icon_url"),
    }


# =============================================================================
# CATALOG INFO FOR API
# =============================================================================

def get_mappings_with_items() -> List[Dict[str, Any]]:
    """
    Get all achievement mappings with full item details.

    Useful for Godot asset generation - shows exactly what items
    need sprites for which achievements.
    """
    mappings = get_achievement_mappings()
    result = []

    for key, item_id in mappings.items():
        parts = key.split(":", 1)
        app_id = parts[0]
        api_name = parts[1] if len(parts) > 1 else ""

        item = get_item_by_id(item_id)
        if item:
            result.append({
                "achievement_key": key,
                "app_id": app_id,
                "api_name": api_name,
                "item_id": item_id,
                "item": item,
                "needs_sprites": not item.get("has_sprites", False),
            })
        else:
            result.append({
                "achievement_key": key,
                "app_id": app_id,
                "api_name": api_name,
                "item_id": item_id,
                "item": None,
                "error": f"Item '{item_id}' not found in catalog",
            })

    return result


def resolve_icon_url(item_id: str, item_type: str = "weapon") -> str:
    """
    Resolve the web-accessible icon URL for a forged item.

    Checks multiple locations in order of preference:
    1. /static/items/icons/{item_id}.png (GPT-generated icons - highest priority)
    2. /assets/icons/enhanced/forged/{type}/{item_id}.png (enhanced, typed)
    3. /assets/icons/forged/{type}/{item_id}.png (base, typed)
    4. /assets/icons/forged/{item_id}.png (base, root - for misplaced icons)

    Returns the URL path for the first existing icon, or static path as default.
    """
    import pathlib

    # Map item_type to folder name
    type_folder_map = {
        "weapon": "weapons",
        "armor_head": "armor",
        "armor_chest": "armor",
        "armor_legs": "armor",
        "armor_hands": "armor",
        "armor_feet": "armor",
        "cape": "capes",
        "shield": "shields",
        "accessory": "accessories",
        "ring": "accessories",
        "amulet": "accessories",
        "emote": "accessories",
        "title": "accessories",
        "tool": "tools",
    }
    folder = type_folder_map.get(item_type, "weapons")

    # Base paths on disk
    backend_dir = pathlib.Path(__file__).parent.parent.parent
    static_icons_dir = backend_dir / "static" / "items" / "icons"
    assets_dir = backend_dir.parent / "assets" / "icons"

    # Check locations in priority order (GPT icons first!)
    candidates = [
        (static_icons_dir / f"{item_id}.png",
         f"/static/items/icons/{item_id}.png"),
        (assets_dir / "enhanced" / "forged" / folder / f"{item_id}.png",
         f"/assets/icons/enhanced/forged/{folder}/{item_id}.png"),
        (assets_dir / "forged" / folder / f"{item_id}.png",
         f"/assets/icons/forged/{folder}/{item_id}.png"),
        (assets_dir / "forged" / f"{item_id}.png",
         f"/assets/icons/forged/{item_id}.png"),
    ]

    for disk_path, url_path in candidates:
        if disk_path.exists():
            return url_path

    # Default to static path (will 404 if missing, but that's expected for missing icons)
    return f"/static/items/icons/{item_id}.png"


def get_icon_url_for_item(item: Dict[str, Any]) -> str:
    """Get the icon URL for a catalog item."""
    item_id = item.get("item_id", "")
    item_type = item.get("item_type", "weapon")

    # Cache-busting version (increment when icons are updated to bypass CF cache)
    ICON_VERSION = "v8"

    # Check if item has explicit icon URL in visuals
    visuals = item.get("visuals", {})
    if visuals.get("icon_url"):
        url = visuals["icon_url"]
        # /static/items/icons/ URLs are GPT-generated icons - add cache buster
        if url.startswith("/static/items/icons/"):
            return f"{url}?{ICON_VERSION}"
        return url

    base_url = resolve_icon_url(item_id, item_type)
    return f"{base_url}?{ICON_VERSION}"


def get_catalog_summary() -> dict:
    """
    Get summary of the production-ready catalog for API responses.

    Uses get_production_items() to match the filtered catalog returned
    by /api/forge/catalog endpoint.
    """
    items = get_production_items()  # Changed from get_items() to match catalog
    themes = get_themes()

    available = [i for i in items if i.get("has_sprites")]

    by_type = {}
    by_theme = {}
    by_rarity = {}

    for item in items:
        item_type = item.get("item_type", "unknown")
        theme = item.get("theme", "unknown")
        rarity = item.get("base_rarity", "unknown")

        by_type[item_type] = by_type.get(item_type, 0) + 1
        by_theme[theme] = by_theme.get(theme, 0) + 1
        by_rarity[rarity] = by_rarity.get(rarity, 0) + 1

    return {
        "total_items": len(items),
        "available_items": len(available),
        "by_type": by_type,
        "by_theme": by_theme,
        "by_rarity": by_rarity,
        "themes": list(themes.keys()),
    }
