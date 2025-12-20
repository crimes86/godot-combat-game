#!/usr/bin/env python3
"""
Item Manifest Generator for Ashbane Forge System.

Scans LPC sprite folders and generates/updates data/items.json.
This allows the Godot engineer to add new items by simply dropping sprites
into the correct folder structure, then running this tool.

Usage:
    python tools/generate_item_manifest.py --sprites-dir path/to/lpc_sprites

Expected LPC folder structure:
    lpc_sprites/
        weapons/
            sword/
                coiled_sword/
                    idle.png
                    slash.png
                    thrust.png
            dagger/
                ...
        armor/
            plate/
                ...
        shields/
            ...
        accessories/
            ...

The tool will:
1. Scan folders to discover items
2. Detect which animations are available (has_sprites)
3. Generate item entries with deterministic IDs
4. Merge with existing items.json (preserving manual edits)
"""

import os
import sys
import json
import argparse
from pathlib import Path
from datetime import datetime


# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

ITEMS_JSON_PATH = PROJECT_ROOT / "data" / "items.json"

# Animation files that indicate sprites are ready
REQUIRED_ANIMATIONS = {
    "weapon": ["idle.png", "slash.png"],
    "armor": ["idle.png"],
    "shield": ["idle.png"],
    "accessory": ["idle.png"],
}

# Default theme detection from folder names
THEME_KEYWORDS = {
    "dark_souls": ["dark", "souls", "ds", "coiled", "ember", "firelink"],
    "steam": ["steam", "valve", "portal", "hl"],
    "battlenet": ["blizzard", "wow", "warcraft", "diablo", "overwatch"],
    "discord": ["discord", "nitro"],
    "github": ["github", "octocat"],
    "generic": ["basic", "default", "common"],
}


def detect_theme(item_name: str, folder_path: str) -> str:
    """Detect theme from item name or folder path."""
    name_lower = item_name.lower()
    path_lower = folder_path.lower()

    for theme, keywords in THEME_KEYWORDS.items():
        if theme == "generic":
            continue
        for keyword in keywords:
            if keyword in name_lower or keyword in path_lower:
                return theme

    return "generic"


def has_required_animations(folder: Path, item_type: str) -> bool:
    """Check if folder has required animation files."""
    required = REQUIRED_ANIMATIONS.get(item_type, ["idle.png"])

    # Check for .png files
    for anim in required:
        if not (folder / anim).exists():
            return False
    return True


def scan_item_folder(folder: Path, item_type: str, weapon_type: str = None) -> dict:
    """Scan a single item folder and return item data."""
    item_id = folder.name

    # Generate display name from folder name
    display_name = item_id.replace("_", " ").title()

    # Detect theme
    theme = detect_theme(item_id, str(folder))

    # Check if sprites are ready
    has_sprites = has_required_animations(folder, item_type)

    # Build relative sprite path
    sprite_folder = str(folder.relative_to(folder.parent.parent.parent))

    item = {
        "item_id": item_id,
        "item_name": display_name,
        "item_type": item_type,
        "theme": theme,
        "base_rarity": "common",
        "has_sprites": has_sprites,
        "visuals": {
            "sprite_folder": sprite_folder,
            "effect": "standard_particles",
            "glow_color": "#888888",
        },
    }

    if item_type == "weapon" and weapon_type:
        item["weapon_type"] = weapon_type

    return item


def scan_sprites_directory(sprites_dir: Path) -> list:
    """Scan the entire sprites directory for items."""
    items = []

    # Scan weapons (have weapon_type subfolders)
    weapons_dir = sprites_dir / "weapons"
    if weapons_dir.exists():
        for weapon_type_dir in weapons_dir.iterdir():
            if weapon_type_dir.is_dir():
                weapon_type = weapon_type_dir.name
                for item_dir in weapon_type_dir.iterdir():
                    if item_dir.is_dir():
                        item = scan_item_folder(item_dir, "weapon", weapon_type)
                        items.append(item)

    # Scan armor
    armor_dir = sprites_dir / "armor"
    if armor_dir.exists():
        for item_dir in armor_dir.iterdir():
            if item_dir.is_dir():
                item = scan_item_folder(item_dir, "armor")
                items.append(item)

    # Scan shields
    shields_dir = sprites_dir / "shields"
    if shields_dir.exists():
        for item_dir in shields_dir.iterdir():
            if item_dir.is_dir():
                item = scan_item_folder(item_dir, "shield")
                items.append(item)

    # Scan accessories
    accessories_dir = sprites_dir / "accessories"
    if accessories_dir.exists():
        for item_dir in accessories_dir.iterdir():
            if item_dir.is_dir():
                item = scan_item_folder(item_dir, "accessory")
                items.append(item)

    return items


def merge_catalogs(existing: dict, discovered: list) -> dict:
    """Merge discovered items with existing catalog, preserving manual edits."""
    # Index existing items by item_id
    existing_items = {item["item_id"]: item for item in existing.get("items", [])}

    merged_items = []
    discovered_ids = set()

    for item in discovered:
        item_id = item["item_id"]
        discovered_ids.add(item_id)

        if item_id in existing_items:
            # Preserve manual edits, update has_sprites status
            merged = existing_items[item_id].copy()
            merged["has_sprites"] = item["has_sprites"]
            # Update sprite folder path in case it moved
            if "visuals" not in merged:
                merged["visuals"] = {}
            merged["visuals"]["sprite_folder"] = item["visuals"]["sprite_folder"]
            merged_items.append(merged)
        else:
            # New item
            merged_items.append(item)

    # Keep items that weren't discovered (manually added without sprites)
    for item_id, item in existing_items.items():
        if item_id not in discovered_ids:
            # Mark as no longer having sprites if it was from scan
            item_copy = item.copy()
            if item_copy.get("visuals", {}).get("sprite_folder"):
                item_copy["has_sprites"] = False
            merged_items.append(item_copy)

    # Sort by item_type, then item_id
    merged_items.sort(key=lambda x: (x.get("item_type", "zzz"), x.get("item_id", "")))

    result = existing.copy()
    result["items"] = merged_items
    result["_last_scan"] = datetime.utcnow().isoformat() + "Z"

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Generate/update items.json from LPC sprite folders"
    )
    parser.add_argument(
        "--sprites-dir",
        type=Path,
        help="Path to LPC sprites directory",
        default=PROJECT_ROOT / "godot" / "assets" / "sprites" / "items",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Output path for items.json",
        default=ITEMS_JSON_PATH,
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be generated without writing",
    )
    args = parser.parse_args()

    # Load existing catalog
    existing = {}
    if args.output.exists():
        with open(args.output, "r", encoding="utf-8") as f:
            existing = json.load(f)
        print(f"Loaded existing catalog with {len(existing.get('items', []))} items")

    # Scan sprites directory
    if args.sprites_dir.exists():
        discovered = scan_sprites_directory(args.sprites_dir)
        print(f"Discovered {len(discovered)} items in {args.sprites_dir}")
    else:
        print(f"Sprites directory not found: {args.sprites_dir}")
        print("Creating catalog structure with existing items only...")
        discovered = []

    # Merge catalogs
    result = merge_catalogs(existing, discovered)

    # Stats
    total = len(result.get("items", []))
    with_sprites = sum(1 for i in result.get("items", []) if i.get("has_sprites"))

    print(f"\nCatalog summary:")
    print(f"  Total items: {total}")
    print(f"  With sprites: {with_sprites}")
    print(f"  Without sprites: {total - with_sprites}")

    if args.dry_run:
        print("\n[DRY RUN] Would write:")
        print(json.dumps(result, indent=2)[:2000] + "...")
    else:
        # Ensure output directory exists
        args.output.parent.mkdir(parents=True, exist_ok=True)

        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(result, indent=2, fp=f)
        print(f"\nWrote catalog to {args.output}")


if __name__ == "__main__":
    main()
