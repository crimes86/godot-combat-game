#!/usr/bin/env python3
"""
Reorganize LPC sprites into the structure expected by LPCAnimatedSprite2D addon.

The addon expects:
  spritesheets_path/standard/walk.png
  spritesheets_path/standard/slash.png
  spritesheets_path/standard/hurt.png
  spritesheets_path/custom/slash_oversize.png (for weapons)
"""

import shutil
from pathlib import Path

ASSETS = Path(r"C:\Users\kevin\OneDrive\fantom\mmo\dreadland\assets")
CHARACTERS = ASSETS / "characters"

# Create organized structure for body types
BODY_TYPES = {
    "body_male": ["BODY_human"],
    "body_female": ["BODY_female"],
    "body_skeleton": ["BODY_skeleton"],
}

EQUIPMENT = {
    "legs_greenish": ["LEGS_pants_greenish"],
    "legs_robe": ["LEGS_robe"],
    "torso_leather": ["TORSO_leather_armor_torso"],
    "head_leather_hat": ["HEAD_leather_armor_hat"],
}

def organize_sprites():
    print("=" * 70)
    print("Organizing LPC Sprites for LPCAnimatedSprite2D Addon")
    print("=" * 70)
    
    # Organize body types
    for folder_name, prefixes in BODY_TYPES.items():
        organize_layer(folder_name, prefixes)
    
    # Organize equipment
    for folder_name, prefixes in EQUIPMENT.items():
        organize_layer(folder_name, prefixes)
    
    print("\n" + "=" * 70)
    print("Sprite organization complete!")
    print("=" * 70)

def organize_layer(folder_name, prefixes):
    """Organize sprites for a single equipment layer."""
    print(f"\nOrganizing: {folder_name}")
    
    # Create directories
    layer_dir = CHARACTERS / folder_name
    standard_dir = layer_dir / "standard"
    standard_dir.mkdir(parents=True, exist_ok=True)
    
    animations = ["walk", "slash", "hurt"]
    
    for prefix in prefixes:
        for anim in animations:
            # Find source file
            source = CHARACTERS / f"{prefix}_{anim}.png"
            if not source.exists():
                print(f"  SKIP: {source.name} (not found)")
                continue
            
            # Destination
            dest = standard_dir / f"{anim}.png"
            
            # Copy file
            shutil.copy2(source, dest)
            print(f"  OK: {anim}.png")

if __name__ == "__main__":
    organize_sprites()
