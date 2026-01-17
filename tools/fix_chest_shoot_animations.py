#!/usr/bin/env python3
"""
Fix chest armor shoot.png animations by tinting LPC base sprites.

This script takes properly animated LPC base shoot.png files and tints them
to match the existing forged armor colors (sampled from their slash.png).

Usage:
    python fix_chest_shoot_animations.py --preview    # Show what would be done
    python fix_chest_shoot_animations.py --generate   # Generate the shoot.png files
"""

import argparse
import zipfile
import os
import sys
from pathlib import Path
import colorsys

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("ERROR: Required packages not found. Install with:")
    print("  pip install Pillow numpy")
    sys.exit(1)

# Paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
FORGED_ARMOR_DIR = PROJECT_ROOT / "assets" / "equipment" / "forged" / "armor" / "chest"
DOWNLOADS_DIR = Path.home() / "Downloads"

# Mapping: forged_armor_id -> (zip_file, needs_tint)
# If needs_tint is True, we'll sample color from the armor's slash.png
ARMOR_TO_BASE = {
    "ashen_armor": ("chainmail.zip", False),  # Already gray chainmail
    "insane_straitjacket": ("straight_jacket.zip", True),  # Need to tint to tan/brown
    "natalyas_shadow": ("white_leather_chest.zip", True),  # Need to tint to dark teal
    "survivor_vest": ("white_leather_chest.zip", True),  # Need to tint to dark green
    "grandmaster_armor": ("steel_chest.zip", False),  # Already steel gray
    "elden_armory": ("gold_plate_chest.zip", False),  # Already gold
    "ironclad_armor": ("gold_plate_chest.zip", True),  # Need to tint more orange/copper
}

def sample_dominant_color(image_path: Path) -> tuple:
    """Sample the dominant non-transparent color from an image."""
    img = Image.open(image_path).convert('RGBA')
    arr = np.array(img)

    # Get non-transparent pixels
    mask = arr[:, :, 3] > 128
    rgb_pixels = arr[mask][:, :3]

    if len(rgb_pixels) == 0:
        return (128, 128, 128)

    # Calculate average color (simple approach)
    avg_color = rgb_pixels.mean(axis=0).astype(int)
    return tuple(avg_color)


def rgb_to_hsl(r, g, b):
    """Convert RGB (0-255) to HSL (0-1)."""
    return colorsys.rgb_to_hls(r/255, g/255, b/255)


def hsl_to_rgb(h, l, s):
    """Convert HSL (0-1) to RGB (0-255)."""
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return int(r * 255), int(g * 255), int(b * 255)


def apply_hue_shift(image: Image.Image, target_color: tuple, intensity: float = 0.7) -> Image.Image:
    """Shift image hue toward target color while preserving luminance."""
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3] / 255.0
    alpha = arr[:, :, 3]

    # Get target hue
    target_h, target_l, target_s = rgb_to_hsl(*target_color)

    result = np.zeros_like(rgb)

    for y in range(rgb.shape[0]):
        for x in range(rgb.shape[1]):
            if alpha[y, x] > 0:
                r, g, b = rgb[y, x]
                h, l, s = colorsys.rgb_to_hls(r, g, b)

                # Shift hue toward target
                h_diff = target_h - h
                if h_diff > 0.5:
                    h_diff -= 1.0
                elif h_diff < -0.5:
                    h_diff += 1.0

                new_h = (h + h_diff * intensity) % 1.0
                new_s = s + (target_s - s) * intensity * 0.5
                new_s = max(0, min(1, new_s))

                new_r, new_g, new_b = colorsys.hls_to_rgb(new_h, l, new_s)
                result[y, x] = [new_r, new_g, new_b]
            else:
                result[y, x] = rgb[y, x]

    result = (result * 255).astype(np.uint8)
    result = np.dstack([result, alpha.astype(np.uint8)])

    return Image.fromarray(result, 'RGBA')


def process_armor(armor_id: str, zip_name: str, needs_tint: bool, dry_run: bool = True):
    """Process a single armor - extract shoot.png and optionally tint it."""
    armor_dir = FORGED_ARMOR_DIR / armor_id
    zip_path = DOWNLOADS_DIR / zip_name

    if not armor_dir.exists():
        print(f"  SKIP: {armor_id} - armor folder not found")
        return False

    if not zip_path.exists():
        print(f"  SKIP: {armor_id} - zip not found: {zip_path}")
        return False

    # Extract shoot.png from zip
    with zipfile.ZipFile(zip_path, 'r') as z:
        shoot_data = z.read('standard/shoot.png')

    from io import BytesIO
    base_img = Image.open(BytesIO(shoot_data)).convert('RGBA')

    if needs_tint:
        # Sample color from existing slash.png
        slash_path = armor_dir / "slash.png"
        if slash_path.exists():
            target_color = sample_dominant_color(slash_path)
            print(f"  {armor_id}: Tinting to RGB{target_color}")
            result_img = apply_hue_shift(base_img, target_color, intensity=0.8)
        else:
            print(f"  {armor_id}: No slash.png to sample, using base")
            result_img = base_img
    else:
        print(f"  {armor_id}: Using base (no tint needed)")
        result_img = base_img

    # Save
    output_path = armor_dir / "shoot.png"
    if dry_run:
        print(f"  Would save: {output_path}")
    else:
        result_img.save(output_path, 'PNG')
        print(f"  Saved: {output_path}")

    return True


def main():
    parser = argparse.ArgumentParser(description="Fix chest armor shoot.png animations")
    parser.add_argument("--preview", action="store_true", help="Preview what would be done")
    parser.add_argument("--generate", action="store_true", help="Generate the shoot.png files")
    parser.add_argument("--armor", type=str, help="Process only this armor")
    args = parser.parse_args()

    if not args.preview and not args.generate:
        parser.print_help()
        return

    dry_run = args.preview

    print(f"{'PREVIEW' if dry_run else 'GENERATING'} chest armor shoot.png files\n")

    # Check which zips exist
    print("Checking base sprite zips:")
    zips_found = set()
    for zip_name in set(z for z, _ in ARMOR_TO_BASE.values()):
        zip_path = DOWNLOADS_DIR / zip_name
        if zip_path.exists():
            print(f"  OK: {zip_name}")
            zips_found.add(zip_name)
        else:
            print(f"  MISSING: {zip_name}")
    print()

    # Process armors
    print("Processing armors:")
    success = 0
    for armor_id, (zip_name, needs_tint) in ARMOR_TO_BASE.items():
        if args.armor and args.armor != armor_id:
            continue
        if zip_name not in zips_found:
            print(f"  SKIP: {armor_id} - base zip missing")
            continue
        if process_armor(armor_id, zip_name, needs_tint, dry_run):
            success += 1

    print(f"\n{'Would process' if dry_run else 'Processed'}: {success} armors")

    if dry_run:
        print("\nRun with --generate to create the files")


if __name__ == "__main__":
    main()
