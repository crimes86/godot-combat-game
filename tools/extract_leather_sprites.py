#!/usr/bin/env python3
"""
Extract tier 1 leather armor sprites from LPC generator zip export.
Organizes sprites into the game's expected folder structure.
"""

import os
import shutil
from pathlib import Path

# Source and destination paths
SOURCE_DIR = Path(r"C:\Users\kevin\Downloads\tier1leather_extracted\standard")
DEST_BASE = Path(r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\equipment\armor\tier1")

# Animation folder mapping: LPC folder name -> game animation name
ANIMATION_MAP = {
    "1h_backslash": "backslash",
    "1h_halfslash": "halfslash",
    "1h_slash": "slash",
    "climb": "climb",
    "combat": "combat_idle",
    "emote": "emote",
    "hurt": "hurt",
    "idle": "idle",
    "jump": "jump",
    "run": "run",
    "shoot": "shoot",
    "sit": "sit",
    "slash": "slash",  # Alternate slash folder
    "spellcast": "spellcast",
    "thrust": "thrust",
    "walk": "walk",
    "watering": "watering",  # For harvest animation
}

# Slot mapping: slot name -> (layer pattern to match, destination folder)
SLOT_MAP = {
    "chest": {
        "pattern": "060 leather__brown_",
        "dest_folder": "chest/rawhide/standard",
    },
    "legs": {
        "pattern": "020 pants__brown_",
        "dest_folder": "legs/rawhide/standard",
    },
    "feet": {
        "pattern": "025 basic_boots__brown_",
        "dest_folder": "feet/rawhide/standard",
    },
    "hands": {
        "pattern": "070 gloves__brown_",
        "dest_folder": "hands/rawhide/standard",
    },
    "head": {
        "pattern": "130 leather_cap__base_",
        "dest_folder": "head/rawhide/standard",
    },
}

def find_layer_file(animation_dir: Path, pattern: str):
    """Find a layer file matching the pattern in the animation directory."""
    for file in animation_dir.iterdir():
        if file.is_file() and pattern in file.name and file.suffix == ".png":
            return file
    return None

def extract_slot_sprites(slot_name: str, config: dict):
    """Extract all animation sprites for a single slot."""
    pattern = config["pattern"]
    dest_folder = DEST_BASE / config["dest_folder"]

    # Create destination directory
    dest_folder.mkdir(parents=True, exist_ok=True)

    print(f"\n{'='*50}")
    print(f"Processing slot: {slot_name}")
    print(f"Pattern: {pattern}")
    print(f"Destination: {dest_folder}")
    print(f"{'='*50}")

    copied = 0
    missing = []

    for lpc_name, game_name in ANIMATION_MAP.items():
        anim_dir = SOURCE_DIR / lpc_name

        if not anim_dir.exists():
            # Skip if animation folder doesn't exist
            continue

        layer_file = find_layer_file(anim_dir, pattern)

        if layer_file:
            dest_file = dest_folder / f"{game_name}.png"
            shutil.copy2(layer_file, dest_file)
            print(f"  [OK] {game_name}.png <- {layer_file.name}")
            copied += 1
        else:
            missing.append(game_name)

    print(f"\nCopied {copied} files for {slot_name}")
    if missing:
        print(f"Missing animations: {', '.join(missing)}")

    return copied

def main():
    print("Leather Armor Sprite Extractor")
    print("=" * 50)

    # Check source exists
    if not SOURCE_DIR.exists():
        print(f"ERROR: Source directory not found: {SOURCE_DIR}")
        print("Make sure to extract tier1leather.zip first!")
        return

    # List available animations
    print(f"\nSource: {SOURCE_DIR}")
    print("Available animations:")
    for anim in sorted(SOURCE_DIR.iterdir()):
        if anim.is_dir():
            print(f"  - {anim.name}")

    total_copied = 0

    # Process each slot
    for slot_name, config in SLOT_MAP.items():
        copied = extract_slot_sprites(slot_name, config)
        total_copied += copied

    print(f"\n{'='*50}")
    print(f"COMPLETE: Copied {total_copied} total sprite files")
    print(f"{'='*50}")

    # Print verification commands
    print("\nVerify with:")
    for slot_name, config in SLOT_MAP.items():
        dest_folder = DEST_BASE / config["dest_folder"]
        print(f"  ls \"{dest_folder}\"")

if __name__ == "__main__":
    main()
