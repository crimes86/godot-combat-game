#!/usr/bin/env python3
"""
Generate shoot.png for forged armor that's missing it.

For chest/head/leg armor, the torso pose doesn't change much between walk and shoot
(it's the arms that move when drawing a bow). So we can create shoot.png by using
the standing pose from walk.png.

The shoot animation has 13 frames per direction (832x256 total).
We use frame 0 from walk repeated 13 times for each direction.

Usage:
    python generate_armor_shoot.py [--dry-run]
"""

import sys
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow library required. Install with: pip install Pillow")
    sys.exit(1)

# LPC dimensions
FRAME_SIZE = 64
SHOOT_FRAMES = 13
DIRECTIONS = 4

# Forged armor paths to check
FORGED_ARMOR_PATHS = [
    "assets/equipment/forged/armor/chest",
    "assets/equipment/forged/armor/head",
    "assets/equipment/forged/armor/legs",
    "assets/equipment/forged/armor/arms",
    "assets/equipment/forged/armor/feet",
    "assets/equipment/forged/armor/hands",
]

def generate_shoot_from_walk(walk_path, shoot_path, dry_run=False):
    """Generate shoot.png from walk.png by using frame 0 repeated 13 times."""
    walk_img = Image.open(walk_path).convert('RGBA')

    # Calculate source format
    src_frame_count = walk_img.width // FRAME_SIZE

    # Create shoot image (13 frames x 4 directions)
    shoot_width = SHOOT_FRAMES * FRAME_SIZE  # 832
    shoot_height = DIRECTIONS * FRAME_SIZE   # 256
    shoot_img = Image.new('RGBA', (shoot_width, shoot_height), (0, 0, 0, 0))

    # For each direction, extract frame 0 from walk and repeat it 13 times
    for direction in range(DIRECTIONS):
        src_y = direction * FRAME_SIZE

        # Get frame 0 from walk (standing pose)
        src_box = (0, src_y, FRAME_SIZE, src_y + FRAME_SIZE)
        frame = walk_img.crop(src_box)

        # Paste it 13 times for shoot animation
        for frame_idx in range(SHOOT_FRAMES):
            dst_x = frame_idx * FRAME_SIZE
            dst_y = direction * FRAME_SIZE
            shoot_img.paste(frame, (dst_x, dst_y))

    if dry_run:
        print(f"  Would create: {shoot_path} (832x256)")
    else:
        shoot_img.save(shoot_path, 'PNG')
        print(f"  Created: {shoot_path} (832x256)")

    return True


def process_armor_directory(armor_path, dry_run=False):
    """Process a single armor directory."""
    walk_path = os.path.join(armor_path, "walk.png")
    shoot_path = os.path.join(armor_path, "shoot.png")

    # Skip if no walk.png
    if not os.path.exists(walk_path):
        return False, "no walk.png"

    # Skip if shoot.png already exists
    if os.path.exists(shoot_path):
        return False, "shoot.png exists"

    # Generate shoot.png
    generate_shoot_from_walk(walk_path, shoot_path, dry_run)
    return True, "generated"


def main():
    dry_run = "--dry-run" in sys.argv

    if dry_run:
        print("DRY RUN - No files will be created\n")

    # Get project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent

    total_generated = 0
    total_skipped = 0

    for armor_base in FORGED_ARMOR_PATHS:
        armor_dir = project_root / armor_base

        if not armor_dir.exists():
            continue

        print(f"\n{armor_base}:")

        for item_dir in sorted(armor_dir.iterdir()):
            if not item_dir.is_dir():
                continue

            # Handle both flat structure and /standard/ subfolder
            if (item_dir / "walk.png").exists():
                target_dir = item_dir
            elif (item_dir / "standard" / "walk.png").exists():
                target_dir = item_dir / "standard"
            else:
                continue

            generated, reason = process_armor_directory(str(target_dir), dry_run)

            if generated:
                total_generated += 1
            else:
                total_skipped += 1
                if reason != "shoot.png exists":
                    print(f"  {item_dir.name}: Skipped ({reason})")

    print(f"\n{'Would generate' if dry_run else 'Generated'}: {total_generated}")
    print(f"Skipped (already had shoot.png): {total_skipped}")

    if dry_run:
        print("\nRun without --dry-run to actually create files")


if __name__ == '__main__':
    main()
