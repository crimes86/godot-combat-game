#!/usr/bin/env python3
"""
Organize weapon sprites from LPC generator for the LPCAnimatedSprite2D addon.
Handles both standard weapons (64x64) and oversize weapons (192x64).
"""

import shutil
from pathlib import Path

LPC_ROOT = Path(r"C:\lpc-generator-full\Universal-LPC-Spritesheet-Character-Generator-master\spritesheets\weapon")
GAME_WEAPONS = Path(r"C:\Users\kevin\OneDrive\fantom\mmo\rhythmrpg\assets\weapons")

# Weapon definitions
WEAPONS = {
    "longsword": {
        "lpc_path": "sword/longsword",
        "type": "oversize",  # Uses 192x64 frames
        "animations": {
            "slash_oversize": "attack_slash/longsword.png",
            "walk": "walk/longsword.png",
        }
    },
    "dagger": {
        "lpc_path": "sword/dagger", 
        "type": "standard",  # Uses 64x64 frames
        "animations": {
            "slash": "slash/dagger.png",
            "walk": "walk/dagger.png",
        }
    },
}

def organize_weapons():
    print("=" * 70)
    print("Organizing Weapon Sprites for LPCAnimatedSprite2D")
    print("=" * 70)
    
    for weapon_name, config in WEAPONS.items():
        print(f"\n{weapon_name.upper()}:")
        
        weapon_dir = GAME_WEAPONS / weapon_name
        lpc_weapon_path = LPC_ROOT / config["lpc_path"]
        
        if not lpc_weapon_path.exists():
            print(f"  ERROR: LPC path not found: {lpc_weapon_path}")
            continue
        
        # Create directory structure based on weapon type
        if config["type"] == "oversize":
            dest_dir = weapon_dir / "custom"
        else:
            dest_dir = weapon_dir / "standard"
        
        dest_dir.mkdir(parents=True, exist_ok=True)
        
        # Copy animations
        for anim_name, source_file in config["animations"].items():
            source_path = lpc_weapon_path / source_file
            dest_path = dest_dir / f"{anim_name}.png"
            
            if source_path.exists():
                shutil.copy2(source_path, dest_path)
                print(f"  OK: {anim_name}.png")
            else:
                print(f"  MISSING: {source_file}")
    
    print("\n" + "=" * 70)
    print("Weapon sprites organized!")
    print("=" * 70)

if __name__ == "__main__":
    organize_weapons()
