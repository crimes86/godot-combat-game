#!/usr/bin/env python3
"""
LPC Sprite Tinter for Forge Items

Takes base weapon/equipment sprites and applies color tinting to create
forged item variants.

Usage:
    python lpc_sprite_tinter.py <input_dir> <output_dir> --tint <color>

Tint presets for forge items:
    golden      - Elden Ring gold (Grafted Blade, Elden Lord items)
    silver      - Witcher silver sword
    crimson     - Dark Souls ember, Sekiro Mortal Blade
    purple      - Gravity/void theme (Radahn's swords)
    blue        - Moonlight/magic (Carian items)
    green       - Nature/terra (Terra Blade, Stardew)
    dark        - Void/shadow (Hollow Knight items)
    ember       - Orange fire glow (Coiled Sword)
"""

import sys
import os
from pathlib import Path

try:
    from PIL import Image, ImageEnhance
except ImportError:
    print("ERROR: Pillow library required. Install with: pip install Pillow")
    sys.exit(1)

# Tint color presets (R, G, B, intensity)
# Intensity: 0.0 = no tint, 1.0 = full color replacement
TINT_PRESETS = {
    'golden': {
        'color': (255, 200, 80),
        'intensity': 0.35,
        'brightness': 1.1,
        'saturation': 1.2,
        'description': 'Golden/brass tint for Elden Ring items'
    },
    'silver': {
        'color': (200, 210, 230),
        'intensity': 0.25,
        'brightness': 1.15,
        'saturation': 0.7,
        'description': 'Silver gleam for Witcher weapons'
    },
    'crimson': {
        'color': (200, 50, 50),
        'intensity': 0.4,
        'brightness': 1.0,
        'saturation': 1.3,
        'description': 'Blood red for Sekiro/Dark Souls'
    },
    'purple': {
        'color': (150, 80, 200),
        'intensity': 0.35,
        'brightness': 1.0,
        'saturation': 1.2,
        'description': 'Gravity purple for Radahn items'
    },
    'blue': {
        'color': (100, 150, 255),
        'intensity': 0.3,
        'brightness': 1.1,
        'saturation': 1.1,
        'description': 'Moonlight blue for Carian/magic items'
    },
    'green': {
        'color': (80, 200, 100),
        'intensity': 0.35,
        'brightness': 1.1,
        'saturation': 1.2,
        'description': 'Nature green for Terra Blade'
    },
    'dark': {
        'color': (40, 30, 50),
        'intensity': 0.3,
        'brightness': 0.8,
        'saturation': 0.8,
        'description': 'Void dark for Hollow Knight'
    },
    'ember': {
        'color': (255, 120, 40),
        'intensity': 0.4,
        'brightness': 1.15,
        'saturation': 1.3,
        'description': 'Ember orange for Dark Souls fire'
    },
    'white': {
        'color': (240, 245, 255),
        'intensity': 0.2,
        'brightness': 1.2,
        'saturation': 0.5,
        'description': 'Pure white for Pure Nail'
    },
    'infernal': {
        'color': (180, 80, 40),
        'intensity': 0.35,
        'brightness': 1.0,
        'saturation': 1.2,
        'description': 'Infernal bronze for Hades'
    }
}


def apply_tint(image, tint_color, intensity):
    """Apply a color tint to an image while preserving alpha."""
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    # Split into channels
    r, g, b, a = image.split()

    # Create tinted version
    tint_r, tint_g, tint_b = tint_color

    # Blend original with tint color
    def blend_channel(channel, tint_value):
        return channel.point(lambda x: int(x * (1 - intensity) + tint_value * intensity))

    r = blend_channel(r, tint_r)
    g = blend_channel(g, tint_g)
    b = blend_channel(b, tint_b)

    # Merge back
    return Image.merge('RGBA', (r, g, b, a))


def adjust_image(image, brightness=1.0, saturation=1.0):
    """Adjust brightness and saturation."""
    if brightness != 1.0:
        enhancer = ImageEnhance.Brightness(image)
        image = enhancer.enhance(brightness)

    if saturation != 1.0:
        enhancer = ImageEnhance.Color(image)
        image = enhancer.enhance(saturation)

    return image


def process_sprite(input_path, output_path, preset_name):
    """Process a single sprite with the given tint preset."""
    if preset_name not in TINT_PRESETS:
        print(f"ERROR: Unknown preset '{preset_name}'")
        print(f"Available: {', '.join(TINT_PRESETS.keys())}")
        return False

    preset = TINT_PRESETS[preset_name]

    # Load image
    image = Image.open(input_path).convert('RGBA')

    # Apply tint
    image = apply_tint(image, preset['color'], preset['intensity'])

    # Adjust brightness/saturation
    image = adjust_image(image, preset['brightness'], preset['saturation'])

    # Save
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, 'PNG')

    return True


def process_directory(input_dir, output_dir, preset_name):
    """Process all PNG files in a directory."""
    if not os.path.isdir(input_dir):
        print(f"ERROR: Input directory not found: {input_dir}")
        return False

    preset = TINT_PRESETS.get(preset_name)
    if not preset:
        print(f"ERROR: Unknown preset '{preset_name}'")
        return False

    print(f"Tinting sprites with '{preset_name}' preset")
    print(f"  {preset['description']}")
    print(f"  Color: RGB{preset['color']}, Intensity: {preset['intensity']}")
    print(f"  Input: {input_dir}")
    print(f"  Output: {output_dir}")
    print()

    # Process all PNGs
    count = 0
    for filename in os.listdir(input_dir):
        if filename.lower().endswith('.png'):
            input_path = os.path.join(input_dir, filename)
            output_path = os.path.join(output_dir, filename)

            if process_sprite(input_path, output_path, preset_name):
                print(f"  Created: {filename}")
                count += 1

    print(f"\nProcessed {count} sprites.")
    return True


def create_icon_from_sprite(sprite_path, icon_path, preset_name, frame_x=0, frame_y=0, size=64):
    """Extract a frame from a sprite and create a tinted icon."""
    FRAME_SIZE = 64

    image = Image.open(sprite_path).convert('RGBA')

    # Extract frame
    box = (frame_x * FRAME_SIZE, frame_y * FRAME_SIZE,
           (frame_x + 1) * FRAME_SIZE, (frame_y + 1) * FRAME_SIZE)
    icon = image.crop(box)

    # Apply tint
    preset = TINT_PRESETS.get(preset_name)
    if preset:
        icon = apply_tint(icon, preset['color'], preset['intensity'])
        icon = adjust_image(icon, preset['brightness'], preset['saturation'])

    # Resize if needed
    if size != FRAME_SIZE:
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)

    # Save
    Path(icon_path).parent.mkdir(parents=True, exist_ok=True)
    icon.save(icon_path, 'PNG')
    print(f"Created icon: {icon_path}")
    return True


def list_presets():
    """List all available tint presets."""
    print("\nAvailable tint presets:\n")
    for name, preset in TINT_PRESETS.items():
        print(f"  {name:12} - {preset['description']}")
        print(f"               RGB{preset['color']}, intensity={preset['intensity']}")
    print()


def print_usage():
    print("""
LPC Sprite Tinter for Forge Items
==================================

USAGE:
  python lpc_sprite_tinter.py <command> [options]

COMMANDS:
  tint <input_dir> <output_dir> --preset <name>
      Apply tint to all sprites in a directory.

  icon <sprite.png> <icon.png> --preset <name> [--frame X,Y] [--size 64]
      Create a tinted icon from a sprite frame.

  presets
      List all available tint presets.

PRESETS:
  golden, silver, crimson, purple, blue, green, dark, ember, white, infernal

EXAMPLES:
  # Create golden Grafted Blade from base sword
  python lpc_sprite_tinter.py tint assets/equipment/weapons/sword assets/equipment/forged/weapons/grafted_blade --preset golden

  # Create icon
  python lpc_sprite_tinter.py icon assets/equipment/forged/weapons/grafted_blade/walk.png assets/icons/forged/weapons/grafted_blade.png --preset golden --frame 0,0
""")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(0)

    command = sys.argv[1].lower()

    if command == 'tint':
        if len(sys.argv) < 4:
            print("ERROR: tint requires input_dir and output_dir")
            print_usage()
            sys.exit(1)

        input_dir = sys.argv[2]
        output_dir = sys.argv[3]
        preset = 'golden'  # default

        for i, arg in enumerate(sys.argv):
            if arg == '--preset' and i + 1 < len(sys.argv):
                preset = sys.argv[i + 1]

        process_directory(input_dir, output_dir, preset)

    elif command == 'icon':
        if len(sys.argv) < 4:
            print("ERROR: icon requires sprite path and output path")
            print_usage()
            sys.exit(1)

        sprite_path = sys.argv[2]
        icon_path = sys.argv[3]
        preset = 'golden'
        frame_x, frame_y = 0, 0
        size = 64

        for i, arg in enumerate(sys.argv):
            if arg == '--preset' and i + 1 < len(sys.argv):
                preset = sys.argv[i + 1]
            elif arg == '--frame' and i + 1 < len(sys.argv):
                parts = sys.argv[i + 1].split(',')
                frame_x, frame_y = int(parts[0]), int(parts[1])
            elif arg == '--size' and i + 1 < len(sys.argv):
                size = int(sys.argv[i + 1])

        create_icon_from_sprite(sprite_path, icon_path, preset, frame_x, frame_y, size)

    elif command == 'presets':
        list_presets()

    else:
        print(f"Unknown command: {command}")
        print_usage()
        sys.exit(1)
