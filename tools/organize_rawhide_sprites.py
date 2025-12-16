#!/usr/bin/env python3
"""
Copy rawhide leather armor sprites from equipment folder to characters folder
with proper naming convention for Player.gd loading.

Player.gd expects sprites in:
- characters/shirt/[sprite_name]_walk.png for chest
- characters/pants/[sprite_name]_walk.png for legs
- characters/boots/[sprite_name]_walk.png for feet
- characters/arms/[sprite_name]_walk.png for arms
- characters/hands/[sprite_name]_walk.png for hands
- characters/head/[sprite_name]_walk.png for head
"""

import os
import shutil
from pathlib import Path

# Base paths
EQUIPMENT_BASE = Path(r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\equipment\armor\tier1")
CHARACTERS_BASE = Path(r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\characters")

# Slot mapping: equipment slot -> (characters folder, sprite_name prefix)
SLOT_MAP = {
    "chest": ("shirt", "rawhide"),
    "legs": ("pants", "rawhide"),
    "feet": ("boots", "rawhide"),
    "arms": ("arms", "rawhide"),
    "hands": ("hands", "rawhide"),
    "head": ("head", "rawhide"),  # Player.gd uses characters/head/ for head armor
}

# Animation mapping: equipment animation name -> character animation suffix
ANIMATION_MAP = {
    "walk": "_walk",
    "slash": "_slash",
    "thrust": "_thrust",
    "hurt": "_hurt",
    "shoot": "_shoot",
    "idle": "_idle",
    "run": "_run",
    "spellcast": "_spellcast",
}

def copy_slot_sprites(slot_name: str, char_folder: str, sprite_prefix: str):
    """Copy sprites for a single slot from equipment to characters folder."""

    # Source folder
    source_dir = EQUIPMENT_BASE / slot_name / "rawhide" / "standard"

    # Destination folder
    dest_dir = CHARACTERS_BASE / char_folder

    if not source_dir.exists():
        print(f"  [SKIP] Source not found: {source_dir}")
        return 0

    # Create destination if needed
    dest_dir.mkdir(parents=True, exist_ok=True)

    copied = 0

    for anim_name, suffix in ANIMATION_MAP.items():
        source_file = source_dir / f"{anim_name}.png"
        if source_file.exists():
            dest_file = dest_dir / f"{sprite_prefix}{suffix}.png"
            shutil.copy2(source_file, dest_file)
            print(f"  [OK] {dest_file.name}")
            copied += 1

    return copied

def main():
    print("Rawhide Sprite Organizer")
    print("=" * 50)
    print(f"Source: {EQUIPMENT_BASE}")
    print(f"Destination: {CHARACTERS_BASE}")
    print("=" * 50)

    total = 0

    for slot_name, (char_folder, sprite_prefix) in SLOT_MAP.items():
        print(f"\n{slot_name} -> {char_folder}/{sprite_prefix}_*.png")
        copied = copy_slot_sprites(slot_name, char_folder, sprite_prefix)
        total += copied

    print(f"\n{'='*50}")
    print(f"COMPLETE: Copied {total} files")
    print(f"{'='*50}")

    print("\nSprite name for shop_armor.json: 'rawhide'")

if __name__ == "__main__":
    main()
