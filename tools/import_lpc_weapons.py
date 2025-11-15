#!/usr/bin/env python3
"""
Import and organize LPC weapon sprites into the game's asset structure.
Creates proper dual-layer (foreground/background) weapon sprite organization.
"""

import os
import shutil
from pathlib import Path

# Source and destination paths
LPC_ROOT = Path(r"C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\weapon")
GAME_ASSETS = Path(r"C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\weapons")

# Weapon definitions - maps game weapon types to LPC paths
WEAPONS = {
    "longsword": {
        "lpc_path": "sword/longsword",
        "files": [
            # Walk animations
            ("walk/longsword.png", "walk_front.png"),
            ("universal_behind/walk/longsword.png", "walk_behind.png"),
            # Slash attack animations
            ("attack_slash/longsword.png", "slash_front.png"),
            ("attack_slash/behind/longsword.png", "slash_behind.png"),
        ]
    },
    "dagger": {
        "lpc_path": "sword/dagger",
        "files": [
            ("slash/dagger.png", "slash_front.png"),
            ("slash/behind/dagger.png", "slash_behind.png"),
            ("walk/dagger.png", "walk_front.png"),
            ("behind/walk/dagger.png", "walk_behind.png"),
        ]
    },
    "rapier": {
        "lpc_path": "sword/rapier",
        "files": [
            ("attack_slash/rapier.png", "slash_front.png"),
            ("attack_slash/behind/rapier.png", "slash_behind.png"),
            ("universal_behind/walk/rapier.png", "walk_behind.png"),
        ]
    },
    "glowsword_blue": {
        "lpc_path": "sword/glowsword",
        "files": [
            ("attack_slash/blue.png", "slash_front.png"),
            ("attack_slash/behind/blue.png", "slash_behind.png"),
            ("universal_behind/walk/blue.png", "walk_behind.png"),
        ]
    },
    "glowsword_red": {
        "lpc_path": "sword/glowsword",
        "files": [
            ("attack_slash/red.png", "slash_front.png"),
            ("attack_slash/behind/red.png", "slash_behind.png"),
            ("universal_behind/walk/red.png", "walk_behind.png"),
        ]
    },
    "club": {
        "lpc_path": "blunt/club",
        "files": [
            ("club.png", "slash_front.png"),
            ("background/club.png", "slash_behind.png"),
        ]
    },
    "mace": {
        "lpc_path": "blunt/mace",
        "files": [
            ("mace.png", "slash_front.png"),
            ("background/mace.png", "slash_behind.png"),
        ]
    },
    "warhammer": {
        "lpc_path": "blunt/waraxe",  # Using waraxe as template
        "files": [
            ("waraxe.png", "slash_front.png"),
            ("background/waraxe.png", "slash_behind.png"),
        ]
    },
    "spear": {
        "lpc_path": "polearm/spear",
        "files": [
            ("foreground/thrust/spear.png", "thrust_front.png"),
            ("background/thrust/spear.png", "thrust_behind.png"),
            ("foreground/walk/spear.png", "walk_front.png"),
            ("background/walk/spear.png", "walk_behind.png"),
        ]
    },
}

def copy_weapon_sprites():
    """Copy and organize weapon sprites from LPC repo to game assets."""
    print("LPC Weapon Sprite Importer")
    print("=" * 60)

    # Create base weapons directory
    GAME_ASSETS.mkdir(parents=True, exist_ok=True)

    for weapon_name, config in WEAPONS.items():
        print(f"\nProcessing: {weapon_name}")

        # Create weapon directory
        weapon_dir = GAME_ASSETS / weapon_name
        weapon_dir.mkdir(exist_ok=True)

        lpc_weapon_path = LPC_ROOT / config["lpc_path"]

        if not lpc_weapon_path.exists():
            print(f"  WARNING: Source not found: {lpc_weapon_path}")
            continue

        # Copy each sprite file
        copied_count = 0
        for source_file, dest_file in config["files"]:
            source_path = lpc_weapon_path / source_file
            dest_path = weapon_dir / dest_file

            if source_path.exists():
                shutil.copy2(source_path, dest_path)
                print(f"  OK: {dest_file}")
                copied_count += 1
            else:
                print(f"  MISSING: {source_file}")

        print(f"  Copied {copied_count}/{len(config['files'])} files")

    print("\n" + "=" * 60)
    print("Import complete!")
    print(f"Weapons imported to: {GAME_ASSETS}")

if __name__ == "__main__":
    copy_weapon_sprites()
