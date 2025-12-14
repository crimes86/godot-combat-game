#!/usr/bin/env python3
"""
Fix ALL material icons: resize to 64x64 and add transparency
"""

from PIL import Image
import os

def fix_icon(input_path, output_path, make_transparent_bg=True):
    """Resize icon to 64x64 and add alpha channel"""
    print(f"Processing: {os.path.basename(input_path)}")

    # Open image
    img = Image.open(input_path)

    # Convert to RGBA if not already
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Make white/light background transparent
    if make_transparent_bg:
        datas = img.getdata()
        new_data = []

        for item in datas:
            # Change all white/light colors (R, G, B all > 240) to transparent
            if item[0] > 240 and item[1] > 240 and item[2] > 240:
                new_data.append((255, 255, 255, 0))  # Transparent
            else:
                new_data.append(item)

        img.putdata(new_data)

    # Resize to 64x64 with high-quality downsampling
    img_resized = img.resize((64, 64), Image.Resampling.LANCZOS)

    # Save
    img_resized.save(output_path, 'PNG')
    print(f"  [OK] Saved 64x64 RGBA to: {os.path.basename(output_path)}")

# Base paths
readyicon_dir = r"C:\Users\kevin\OneDrive\godot-combat-game-master\readyicon\materials"
materials_dir = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\icons\materials"
consumables_dir = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\icons\consumables"

print("=" * 60)
print("FIXING MATERIAL ICONS")
print("=" * 60)
print()

# Material icons mapping (source -> destination)
material_icons = {
    "boneember.png": "bone_ember.png",
    "bonestack.png": "old_bones.png",
    "broken_sword.png": "broken_sword.png",
    "cursedfemur.png": "cursed_femur.png",
    "drylog.png": "dry_log.png",
    "lichfinger.png": "lichs_finger_bone.png",
    "redgem.png": "dusty_gem.png",
    "ring.png": "tarnished_ring.png",
    "skull.png": "ancient_skull.png",
    "ancientcoin.png": "ancient_coin.png"
}

for source, dest in material_icons.items():
    fix_icon(
        os.path.join(readyicon_dir, source),
        os.path.join(materials_dir, dest),
        make_transparent_bg=True
    )

print()
print("=" * 60)
print("FIXING CONSUMABLE ICONS")
print("=" * 60)
print()

# Consumable icons
consumable_icons = {
    "greenvial.png": ["empty_vial.png", "purified_water.png"]
}

for source, destinations in consumable_icons.items():
    for dest in destinations:
        fix_icon(
            os.path.join(readyicon_dir, source),
            os.path.join(consumables_dir, dest),
            make_transparent_bg=True
        )

print()
print("[SUCCESS] ALL ICONS FIXED!")
print(f"   - 10 material icons resized to 64x64 RGBA")
print(f"   - 2 consumable icons resized to 64x64 RGBA")
print(f"   - All white backgrounds made transparent")
