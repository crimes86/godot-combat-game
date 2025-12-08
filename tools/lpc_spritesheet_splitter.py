#!/usr/bin/env python3
"""
LPC Spritesheet Splitter for Forge Items

This script takes a full LPC spritesheet (downloaded from the Universal LPC Generator)
and splits it into individual animation files for use in Godot.

Usage:
    python lpc_spritesheet_splitter.py <spritesheet.png> <output_directory> [--item-type weapon|armor|shield]

The Universal LPC Generator creates full spritesheets that include all animations.
This script extracts the specific animations we need for the Forge system.

LPC Full Spritesheet Layout (64x64 per frame):
- Row 0-3: Spellcast (7 frames x 4 directions)
- Row 4-7: Thrust (8 frames x 4 directions)
- Row 8-11: Walk (9 frames x 4 directions)
- Row 12-15: Slash (6 frames x 4 directions)
- Row 16-19: Shoot (13 frames x 4 directions)
- Row 20: Hurt (6 frames, single direction)

Output files created:
- walk.png (576x256 - 9 frames x 4 directions)
- slash.png (384x256 - 6 frames x 4 directions)
- thrust.png (512x256 - 8 frames x 4 directions)
- hurt.png (384x64 - 6 frames x 1 direction)
"""

import sys
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow library required. Install with: pip install Pillow")
    sys.exit(1)

# LPC Standard dimensions
FRAME_WIDTH = 64
FRAME_HEIGHT = 64

# Animation definitions (row_start, num_directions, num_frames)
ANIMATIONS = {
    'spellcast': (0, 4, 7),
    'thrust': (4, 4, 8),
    'walk': (8, 4, 9),
    'slash': (12, 4, 6),
    'shoot': (16, 4, 13),
    'hurt': (20, 1, 6),
}

# What animations we need for different item types
ITEM_ANIMATIONS = {
    'weapon': ['walk', 'slash', 'thrust', 'hurt'],
    'armor': ['walk', 'slash', 'thrust', 'hurt'],
    'shield': ['walk'],  # Shields typically only show during walk/idle
    'cape': ['walk', 'slash', 'thrust', 'hurt'],
    'all': ['walk', 'slash', 'thrust', 'hurt', 'spellcast', 'shoot'],
}


def extract_animation(source_img, anim_name):
    """Extract a single animation from the full spritesheet."""
    if anim_name not in ANIMATIONS:
        raise ValueError(f"Unknown animation: {anim_name}")

    row_start, num_directions, num_frames = ANIMATIONS[anim_name]

    # Calculate output dimensions
    out_width = num_frames * FRAME_WIDTH
    out_height = num_directions * FRAME_HEIGHT

    # Create output image
    output = Image.new('RGBA', (out_width, out_height), (0, 0, 0, 0))

    for direction in range(num_directions):
        src_row = row_start + direction
        for frame in range(num_frames):
            # Source position
            src_x = frame * FRAME_WIDTH
            src_y = src_row * FRAME_HEIGHT

            # Destination position
            dst_x = frame * FRAME_WIDTH
            dst_y = direction * FRAME_HEIGHT

            # Extract and paste frame
            box = (src_x, src_y, src_x + FRAME_WIDTH, src_y + FRAME_HEIGHT)
            frame_img = source_img.crop(box)
            output.paste(frame_img, (dst_x, dst_y))

    return output


def split_spritesheet(input_path, output_dir, item_type='weapon'):
    """Split a full LPC spritesheet into individual animation files."""
    # Validate input
    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        return False

    # Create output directory
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    # Load source image
    print(f"Loading: {input_path}")
    source = Image.open(input_path).convert('RGBA')

    # Validate dimensions
    expected_width = 13 * FRAME_WIDTH  # shoot has most frames (13)
    expected_height = 21 * FRAME_HEIGHT  # 21 rows total

    if source.width < expected_width or source.height < expected_height:
        print(f"WARNING: Spritesheet smaller than expected ({source.width}x{source.height})")
        print(f"         Expected at least {expected_width}x{expected_height}")

    # Get animations to extract
    animations = ITEM_ANIMATIONS.get(item_type, ITEM_ANIMATIONS['weapon'])

    print(f"Extracting {len(animations)} animations for item type '{item_type}'...")

    for anim_name in animations:
        try:
            anim_img = extract_animation(source, anim_name)
            output_path = os.path.join(output_dir, f"{anim_name}.png")
            anim_img.save(output_path, 'PNG')
            print(f"  Created: {output_path} ({anim_img.width}x{anim_img.height})")
        except Exception as e:
            print(f"  ERROR extracting {anim_name}: {e}")

    print("Done!")
    return True


def create_icon(input_path, output_path, frame_x=0, frame_y=0, size=64):
    """Extract a single frame as an icon."""
    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        return False

    source = Image.open(input_path).convert('RGBA')

    # Extract frame
    box = (frame_x * FRAME_WIDTH, frame_y * FRAME_HEIGHT,
           (frame_x + 1) * FRAME_WIDTH, (frame_y + 1) * FRAME_HEIGHT)
    icon = source.crop(box)

    # Resize if needed
    if size != FRAME_WIDTH:
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)

    # Save
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    icon.save(output_path, 'PNG')
    print(f"Created icon: {output_path} ({size}x{size})")
    return True


def batch_process(config_file):
    """Process multiple spritesheets from a config file."""
    # Config file format (one per line):
    # input_path,output_dir,item_type

    if not os.path.exists(config_file):
        print(f"ERROR: Config file not found: {config_file}")
        return

    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            parts = line.split(',')
            if len(parts) >= 2:
                input_path = parts[0].strip()
                output_dir = parts[1].strip()
                item_type = parts[2].strip() if len(parts) > 2 else 'weapon'

                print(f"\n--- Processing: {input_path} ---")
                split_spritesheet(input_path, output_dir, item_type)


def print_usage():
    """Print usage information."""
    print("""
LPC Spritesheet Splitter for Forge Items
=========================================

USAGE:
  python lpc_spritesheet_splitter.py <command> [options]

COMMANDS:
  split <input.png> <output_dir> [--type weapon|armor|shield|cape|all]
      Split a full LPC spritesheet into animation files.

  icon <input.png> <output.png> [--frame X,Y] [--size 64]
      Extract a single frame as an icon.

  batch <config.txt>
      Process multiple spritesheets from a config file.

EXAMPLES:
  # Split a weapon spritesheet
  python lpc_spritesheet_splitter.py split downloaded_sword.png assets/equipment/forged/weapons/stygian_blade/ --type weapon

  # Create a 64x64 icon from frame at row 8 (walk facing down), column 0
  python lpc_spritesheet_splitter.py icon downloaded_sword.png assets/icons/forged/weapons/stygian_blade.png --frame 0,8

WORKFLOW:
  1. Go to https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/
  2. Select the weapon/armor you want
  3. Click "Download PNG" to get the full spritesheet
  4. Run this script to split it into animation files
  5. Copy the files to your Godot project
""")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(0)

    command = sys.argv[1].lower()

    if command == 'split':
        if len(sys.argv) < 4:
            print("ERROR: split requires input file and output directory")
            print_usage()
            sys.exit(1)

        input_path = sys.argv[2]
        output_dir = sys.argv[3]
        item_type = 'weapon'

        # Parse optional --type argument
        for i, arg in enumerate(sys.argv):
            if arg == '--type' and i + 1 < len(sys.argv):
                item_type = sys.argv[i + 1]

        split_spritesheet(input_path, output_dir, item_type)

    elif command == 'icon':
        if len(sys.argv) < 4:
            print("ERROR: icon requires input file and output path")
            print_usage()
            sys.exit(1)

        input_path = sys.argv[2]
        output_path = sys.argv[3]
        frame_x, frame_y = 0, 8  # Default: walk facing down, first frame
        size = 64

        # Parse optional arguments
        for i, arg in enumerate(sys.argv):
            if arg == '--frame' and i + 1 < len(sys.argv):
                parts = sys.argv[i + 1].split(',')
                frame_x, frame_y = int(parts[0]), int(parts[1])
            elif arg == '--size' and i + 1 < len(sys.argv):
                size = int(sys.argv[i + 1])

        create_icon(input_path, output_path, frame_x, frame_y, size)

    elif command == 'batch':
        if len(sys.argv) < 3:
            print("ERROR: batch requires config file")
            print_usage()
            sys.exit(1)

        batch_process(sys.argv[2])

    else:
        print(f"Unknown command: {command}")
        print_usage()
        sys.exit(1)
