#!/usr/bin/env python3
"""
Forge Armor Sprite Tinter - Generates tinted armor sprites for forged items

Takes base armor sprites from LPC zips and applies color tinting based on forged item definitions.
Uses icon analysis to extract accurate color palettes for each item.

Usage:
    python forge_armor_tinter.py --analyze                    # Analyze all icons for colors
    python forge_armor_tinter.py --generate-all               # Generate all armor sprites
    python forge_armor_tinter.py --generate lich_king_boots   # Generate single item
    python forge_armor_tinter.py --preview ghost_hakama       # Preview before generating

Base sprite zips expected in Downloads folder:
    - white_shoes.zip (cloth feet)
    - white_cloth_pants.zip (cloth legs)
    - white_leather_boots.zip (leather feet)
    - white_leather_pants.zip (leather legs)
    - silver_plate_boots.zip (plate feet)
    - silver_plate_legs.zip (plate legs)
"""

import argparse
import os
import sys
import json
import zipfile
import colorsys
from pathlib import Path
from typing import Tuple, Optional, Dict, List
from collections import Counter

try:
    from PIL import Image, ImageDraw, ImageFont
    import numpy as np
except ImportError:
    print("ERROR: Required packages not found. Install with:")
    print("  pip install Pillow numpy")
    sys.exit(1)

# Project paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_ROOT / "assets"
ICONS_DIR = ASSETS_DIR / "icons" / "forged" / "armor"
FORGED_ARMOR_DIR = ASSETS_DIR / "equipment" / "forged" / "armor"
ITEMS_JSON = PROJECT_ROOT / "backend" / "data" / "items.json"
OUTPUT_PREVIEW_DIR = SCRIPT_DIR / "armor_previews"

# User downloads folder for base sprites
DOWNLOADS_DIR = Path.home() / "Downloads"

# Sprite types for armor
SPRITE_TYPES = ["walk", "slash", "thrust", "hurt", "shoot"]

# Base sprite zip mappings
BASE_SPRITE_ZIPS = {
    # (material_type, slot) -> zip filename
    ("cloth", "armor_feet"): "white_shoes.zip",
    ("cloth", "armor_legs"): "white_cloth_pants.zip",
    ("leather", "armor_feet"): "white_leather_boots.zip",
    ("leather", "armor_legs"): "white_leather_pants.zip",
    ("plate", "armor_feet"): "silver_plate_boots.zip",
    ("plate", "armor_legs"): "silver_plate_legs.zip",
}

# Wave 2 armor items with their properties
# Format: item_id -> {slot, material_type, glow_color, rarity, theme}
WAVE2_ARMOR_ITEMS = {
    # PLATE items
    "berserker_tassets": {
        "slot": "armor_legs",
        "material_type": "plate",
        "glow_color": "#8B0000",  # Dark red
        "rarity": "epic",
        "theme": "diablo",
    },
    "cog_boots": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#4A5568",  # Gray
        "rarity": "rare",
        "theme": "gears_of_war",
    },
    "lich_king_boots": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#00CED1",  # Cyan/frost
        "rarity": "legendary",
        "theme": "wow",
    },
    "marauder_treads": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#FF4500",  # Orange-red
        "rarity": "epic",
        "theme": "doom",
    },
    "minecraft_leggings": {
        "slot": "armor_legs",
        "material_type": "plate",
        "glow_color": "#00FFFF",  # Cyan/diamond
        "rarity": "rare",
        "theme": "minecraft",
    },
    "returnal_scout_greaves": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#9400D3",  # Purple
        "rarity": "legendary",
        "theme": "returnal",
    },
    "spartan_greaves": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#00CED1",  # Teal/green - actually more olive green for Halo
        "rarity": "legendary",
        "theme": "halo",
    },
    "tier_set_boots": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#9400D3",  # Purple
        "rarity": "epic",
        "theme": "wow",
    },
    "zealot_boots": {
        "slot": "armor_feet",
        "material_type": "plate",
        "glow_color": "#FFD700",  # Gold
        "rarity": "epic",
        "theme": "starcraft",
    },

    # LEATHER items
    "aloy_strider_boots": {
        "slot": "armor_feet",
        "material_type": "leather",
        "glow_color": "#8B4513",  # Saddle brown
        "rarity": "epic",
        "theme": "horizon",
    },
    "apex_boots": {
        "slot": "armor_feet",
        "material_type": "leather",
        "glow_color": "#FF4500",  # Orange-red
        "rarity": "rare",
        "theme": "apex_legends",
    },
    "hunter_boots": {
        "slot": "armor_feet",
        "material_type": "leather",
        "glow_color": "#8B0000",  # Dark red
        "rarity": "epic",
        "theme": "bloodborne",
    },
    "pilots_flight_point": {
        "slot": "armor_feet",
        "material_type": "leather",
        "glow_color": "#FF6600",  # Orange
        "rarity": "epic",
        "theme": "titanfall",
    },
    "pirate_boots": {
        "slot": "armor_feet",
        "material_type": "leather",
        "glow_color": "#1E90FF",  # Blue (but icon shows more brown)
        "rarity": "rare",
        "theme": "sea_of_thieves",
    },

    # CLOTH items
    "cuphead_shoes": {
        "slot": "armor_feet",
        "material_type": "cloth",
        "glow_color": "#FFD700",  # Gold (but icon shows brown/tan)
        "rarity": "rare",
        "theme": "cuphead",
    },
    "ghost_hakama": {
        "slot": "armor_legs",
        "material_type": "cloth",
        "glow_color": "#1A1A2E",  # Dark navy/black
        "rarity": "epic",
        "theme": "ghost_of_tsushima",
    },
    "mountaineer_trouser": {
        "slot": "armor_legs",
        "material_type": "cloth",
        "glow_color": "#228B22",  # Forest green
        "rarity": "uncommon",
        "theme": "adventure",
    },
    "portal_boots": {
        "slot": "armor_feet",
        "material_type": "cloth",
        "glow_color": "#00CED1",  # Cyan (but icon shows white with orange trim)
        "rarity": "epic",
        "theme": "portal",
    },
    "survivor_pants": {
        "slot": "armor_legs",
        "material_type": "cloth",
        "glow_color": "#556B2F",  # Olive
        "rarity": "rare",
        "theme": "left4dead",
    },
    "tracer_pants": {
        "slot": "armor_legs",
        "material_type": "cloth",
        "glow_color": "#FF8C00",  # Orange
        "rarity": "rare",
        "theme": "overwatch",
    },
}

# Rarity multipliers for glow intensity
RARITY_GLOW_INTENSITY = {
    "common": 0.3,
    "uncommon": 0.5,
    "rare": 0.7,
    "epic": 0.9,
    "legendary": 1.0,
}


def hex_to_rgb(hex_color: str) -> Tuple[int, int, int]:
    """Convert hex color string to RGB tuple."""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Convert RGB tuple to hex color string."""
    return f"#{r:02X}{g:02X}{b:02X}"


def rgb_to_hsl(r: int, g: int, b: int) -> Tuple[float, float, float]:
    """Convert RGB (0-255) to HSL (0-1)."""
    return colorsys.rgb_to_hls(r/255, g/255, b/255)


def hsl_to_rgb(h: float, l: float, s: float) -> Tuple[int, int, int]:
    """Convert HSL (0-1) to RGB (0-255)."""
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return int(r * 255), int(g * 255), int(b * 255)


def analyze_icon_colors(icon_path: Path, num_colors: int = 5) -> List[Tuple[Tuple[int, int, int], float]]:
    """
    Analyze an icon to extract dominant colors.

    Returns list of (RGB tuple, percentage) sorted by frequency.
    """
    if not icon_path.exists():
        return []

    try:
        img = Image.open(icon_path).convert('RGBA')
    except Exception as e:
        print(f"  WARNING: Cannot read icon {icon_path}: {e}")
        return []
    arr = np.array(img)

    # Only consider non-transparent pixels
    mask = arr[:, :, 3] > 128
    pixels = arr[:, :, :3][mask]

    if len(pixels) == 0:
        return []

    # Quantize colors for better grouping (reduce to 32 levels per channel)
    quantized = (pixels // 8) * 8

    # Count occurrences
    color_counts = Counter(tuple(c) for c in quantized)
    total = sum(color_counts.values())

    # Get top N colors
    top_colors = color_counts.most_common(num_colors)

    return [(color, count / total) for color, count in top_colors]


def get_icon_primary_colors(icon_path: Path) -> Dict[str, Tuple[int, int, int]]:
    """
    Extract primary and secondary colors from an icon.

    Returns dict with 'primary', 'secondary', 'accent' colors.
    """
    colors = analyze_icon_colors(icon_path, num_colors=10)

    if not colors:
        return {"primary": (128, 128, 128), "secondary": (96, 96, 96), "accent": (160, 160, 160)}

    # Filter out near-black (shadows) and near-white (highlights)
    def is_interesting(rgb):
        r, g, b = rgb
        brightness = (r + g + b) / 3
        saturation = max(r, g, b) - min(r, g, b)
        # Skip very dark, very bright, and very desaturated
        return 20 < brightness < 240 and saturation > 15

    interesting = [(c, p) for c, p in colors if is_interesting(c)]

    if len(interesting) >= 3:
        return {
            "primary": interesting[0][0],
            "secondary": interesting[1][0],
            "accent": interesting[2][0],
        }
    elif len(interesting) >= 2:
        return {
            "primary": interesting[0][0],
            "secondary": interesting[1][0],
            "accent": interesting[0][0],
        }
    elif len(interesting) >= 1:
        return {
            "primary": interesting[0][0],
            "secondary": interesting[0][0],
            "accent": interesting[0][0],
        }
    else:
        # Fall back to first colors
        return {
            "primary": colors[0][0] if colors else (128, 128, 128),
            "secondary": colors[1][0] if len(colors) > 1 else colors[0][0],
            "accent": colors[2][0] if len(colors) > 2 else colors[0][0],
        }


def apply_color_tint(image: Image.Image, target_color: Tuple[int, int, int],
                     intensity: float = 0.7, preserve_brightness: bool = True) -> Image.Image:
    """
    Apply color tint to a grayscale/white base sprite.

    For white base sprites, this colorizes them to the target color
    while preserving the luminance/shading.
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3:4]

    # For white/gray base sprites, use the brightness as a multiplier
    if preserve_brightness:
        # Get brightness of each pixel (0-1)
        brightness = np.mean(rgb, axis=2, keepdims=True) / 255.0

        # Create target color array
        target = np.array(target_color, dtype=np.float32)

        # Apply target color modulated by brightness
        result = target * brightness

        # Blend with original based on intensity
        original_contribution = rgb * (1 - intensity)
        tinted_contribution = result * intensity
        result = original_contribution + tinted_contribution
    else:
        # Simple multiply blend
        target = np.array(target_color, dtype=np.float32) / 255.0
        result = rgb * target

    # Clip and recombine
    result = np.clip(result, 0, 255).astype(np.uint8)
    result = np.concatenate([result, alpha.astype(np.uint8)], axis=2)

    return Image.fromarray(result, mode='RGBA')


def apply_hue_shift(image: Image.Image, target_color: Tuple[int, int, int],
                    intensity: float = 0.7) -> Image.Image:
    """
    Shift hue toward target color while preserving luminance.
    Works well for colored base sprites (like silver plate).
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3] / 255.0
    alpha = arr[:, :, 3]

    # Get target HSL
    target_h, target_l, target_s = rgb_to_hsl(*target_color)

    # Process each pixel
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

                # Slightly adjust saturation toward target
                new_s = s + (target_s - s) * intensity * 0.5
                new_s = max(0, min(1, new_s))

                new_r, new_g, new_b = colorsys.hls_to_rgb(new_h, l, new_s)
                result[y, x] = [new_r, new_g, new_b]
            else:
                result[y, x] = rgb[y, x]

    result = (result * 255).astype(np.uint8)
    result = np.dstack([result, alpha.astype(np.uint8)])

    return Image.fromarray(result, mode='RGBA')


def apply_additive_glow(image: Image.Image, color: Tuple[int, int, int],
                        intensity: float = 0.3) -> Image.Image:
    """Add subtle glow effect for legendary/epic items."""
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3:4]

    # Create glow
    glow = np.array(color, dtype=np.float32)
    mask = (alpha > 0).astype(np.float32)

    result = rgb + glow * intensity * mask
    result = np.clip(result, 0, 255).astype(np.uint8)
    result = np.concatenate([result, alpha.astype(np.uint8)], axis=2)

    return Image.fromarray(result, mode='RGBA')


def apply_hybrid_tint(image: Image.Image, primary_color: Tuple[int, int, int],
                      rarity: str, is_white_base: bool = True) -> Image.Image:
    """
    Apply smart tinting based on base sprite type and rarity.

    White base sprites get colorized, colored bases get hue-shifted.
    Higher rarity items get additive glow.
    """
    glow_intensity = RARITY_GLOW_INTENSITY.get(rarity.lower(), 0.5)

    if is_white_base:
        # For white/gray bases, colorize
        result = apply_color_tint(image, primary_color, intensity=0.85)
    else:
        # For colored bases (silver plate), hue shift
        result = apply_hue_shift(image, primary_color, intensity=0.7)

    # Add glow for epic/legendary
    if glow_intensity >= 0.7:
        result = apply_additive_glow(result, primary_color, intensity=glow_intensity * 0.2)

    return result


def extract_sprites_from_zip(zip_path: Path) -> Dict[str, Image.Image]:
    """
    Extract sprite sheets from an LPC zip file.

    Returns dict of animation_name -> Image.
    """
    sprites = {}

    with zipfile.ZipFile(zip_path, 'r') as zf:
        for name in zf.namelist():
            # Look for PNG files in standard folder
            if 'standard/' in name and name.endswith('.png'):
                # Extract animation type from path
                parts = name.split('/')
                if len(parts) >= 2:
                    # Find the animation folder name
                    for i, part in enumerate(parts):
                        if part == 'standard' and i + 1 < len(parts):
                            anim_folder = parts[i + 1]
                            # Handle nested structure
                            if anim_folder in SPRITE_TYPES:
                                # File is directly in anim folder
                                with zf.open(name) as f:
                                    img = Image.open(f).convert('RGBA')
                                    # Take the last one if multiple (usually just one)
                                    sprites[anim_folder] = img.copy()
                            break

    # If no sprites found in standard/ format, try flat structure
    if not sprites:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            for name in zf.namelist():
                if name.endswith('.png'):
                    for anim in SPRITE_TYPES:
                        if anim in name.lower():
                            with zf.open(name) as f:
                                img = Image.open(f).convert('RGBA')
                                sprites[anim] = img.copy()
                            break

    return sprites


def get_base_sprites(material_type: str, slot: str) -> Optional[Dict[str, Image.Image]]:
    """
    Get base sprites for a material/slot combination.
    """
    key = (material_type, slot)
    if key not in BASE_SPRITE_ZIPS:
        print(f"  ERROR: No base sprite defined for {material_type}/{slot}")
        return None

    zip_name = BASE_SPRITE_ZIPS[key]
    zip_path = DOWNLOADS_DIR / zip_name

    if not zip_path.exists():
        print(f"  ERROR: Base sprite zip not found: {zip_path}")
        return None

    return extract_sprites_from_zip(zip_path)


def generate_armor_sprites(item_id: str, dry_run: bool = False) -> bool:
    """
    Generate all tinted sprites for a forged armor item.
    """
    if item_id not in WAVE2_ARMOR_ITEMS:
        print(f"ERROR: Unknown item '{item_id}'")
        return False

    item = WAVE2_ARMOR_ITEMS[item_id]
    slot = item["slot"]
    material_type = item["material_type"]
    rarity = item["rarity"]

    # Get colors from icon
    icon_path = ICONS_DIR / f"{item_id}.png"
    icon_colors = None
    if icon_path.exists():
        icon_colors = get_icon_primary_colors(icon_path)
        primary_color = icon_colors["primary"]
        # Check if color is too dark/gray (failed to extract properly)
        r, g, b = primary_color
        brightness = (r + g + b) / 3
        saturation = max(r, g, b) - min(r, g, b)
        if brightness < 30 or saturation < 15:
            # Fall back to glow_color for very dark/gray colors
            primary_color = hex_to_rgb(item["glow_color"])
            print(f"  Icon too dark/gray, using glow_color: {item['glow_color']}")
        else:
            print(f"  Icon colors: primary={rgb_to_hex(*primary_color)}")
    else:
        # Fall back to glow_color from definition
        primary_color = hex_to_rgb(item["glow_color"])
        print(f"  No icon found, using glow_color: {item['glow_color']}")

    # Get base sprites
    base_sprites = get_base_sprites(material_type, slot)
    if not base_sprites:
        return False

    print(f"\nGenerating sprites for: {item_id}")
    print(f"  Slot: {slot}")
    print(f"  Material: {material_type}")
    print(f"  Rarity: {rarity}")
    print(f"  Base sprites: {list(base_sprites.keys())}")

    # Determine if base is white (cloth/leather) or silver (plate)
    is_white_base = material_type in ("cloth", "leather")

    output_path = FORGED_ARMOR_DIR / item_id
    generated = []

    for anim_name, sprite in base_sprites.items():
        # Apply tinting
        tinted = apply_hybrid_tint(sprite, primary_color, rarity, is_white_base)

        dst_path = output_path / f"{anim_name}.png"

        if dry_run:
            print(f"  WOULD GENERATE: {dst_path}")
        else:
            output_path.mkdir(parents=True, exist_ok=True)
            tinted.save(dst_path)
            print(f"  GENERATED: {dst_path}")

        generated.append(anim_name)

    print(f"  Total: {len(generated)} sprites")
    return len(generated) > 0


def generate_preview(item_id: str) -> bool:
    """
    Generate a preview image showing base sprite, icon, and tinted result.
    """
    if item_id not in WAVE2_ARMOR_ITEMS:
        print(f"ERROR: Unknown item '{item_id}'")
        return False

    item = WAVE2_ARMOR_ITEMS[item_id]
    slot = item["slot"]
    material_type = item["material_type"]
    rarity = item["rarity"]

    # Get icon
    icon_path = ICONS_DIR / f"{item_id}.png"
    icon = None
    if icon_path.exists():
        icon = Image.open(icon_path).convert('RGBA')
        icon_colors = get_icon_primary_colors(icon_path)
        primary_color = icon_colors["primary"]
    else:
        primary_color = hex_to_rgb(item["glow_color"])

    # Get base sprites
    base_sprites = get_base_sprites(material_type, slot)
    if not base_sprites or "walk" not in base_sprites:
        print(f"  ERROR: No walk sprite for preview")
        return False

    base_walk = base_sprites["walk"]

    # Extract single frame (south-facing, first frame)
    frame_w, frame_h = 64, 64
    # Row 2 is south-facing in LPC sheets
    base_frame = base_walk.crop((0, frame_h * 2, frame_w, frame_h * 3))

    # Generate tinted version
    is_white_base = material_type in ("cloth", "leather")
    tinted_frame = apply_hybrid_tint(base_frame.copy(), primary_color, rarity, is_white_base)

    # Create preview image
    padding = 10
    label_height = 20

    # Components: icon (64), base frame (64), tinted frame (64)
    width = 64 * 3 + padding * 4
    height = 64 + label_height * 2 + padding * 3

    preview = Image.new('RGBA', (width, height), (40, 40, 40, 255))
    draw = ImageDraw.Draw(preview)

    try:
        font = ImageFont.truetype("arial.ttf", 12)
    except:
        font = ImageFont.load_default()

    x = padding

    # Icon
    if icon:
        icon_resized = icon.resize((64, 64), Image.Resampling.LANCZOS)
        preview.paste(icon_resized, (x, padding + label_height), icon_resized)
        draw.text((x, padding), "Icon", fill=(255, 255, 255), font=font)
    x += 64 + padding

    # Base frame
    preview.paste(base_frame, (x, padding + label_height), base_frame)
    draw.text((x, padding), "Base", fill=(255, 255, 255), font=font)
    x += 64 + padding

    # Tinted frame
    preview.paste(tinted_frame, (x, padding + label_height), tinted_frame)
    draw.text((x, padding), "Tinted", fill=(255, 255, 255), font=font)

    # Info bar
    info_y = padding + label_height + 64 + 5
    info_text = f"{item_id} | {material_type} | {rarity.upper()} | {rgb_to_hex(*primary_color)}"
    draw.text((padding, info_y), info_text, fill=(180, 180, 180), font=font)

    # Save preview
    OUTPUT_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    preview_path = OUTPUT_PREVIEW_DIR / f"{item_id}_preview.png"
    preview.save(preview_path)
    print(f"Preview saved: {preview_path}")

    return True


def analyze_all_icons():
    """Analyze and display colors for all wave 2 armor icons."""
    print("\nIcon Color Analysis for Wave 2 Armor:")
    print("=" * 70)

    for item_id, item in sorted(WAVE2_ARMOR_ITEMS.items()):
        icon_path = ICONS_DIR / f"{item_id}.png"

        if not icon_path.exists():
            print(f"\n{item_id}: MISSING ICON")
            continue

        colors = get_icon_primary_colors(icon_path)
        defined_color = item["glow_color"]

        print(f"\n{item_id} ({item['material_type']} {item['slot']})")
        print(f"  Defined: {defined_color}")
        print(f"  Primary: {rgb_to_hex(*colors['primary'])}")
        print(f"  Secondary: {rgb_to_hex(*colors['secondary'])}")
        print(f"  Accent: {rgb_to_hex(*colors['accent'])}")


def check_base_zips():
    """Check which base sprite zips are available."""
    print("\nBase Sprite Zip Status:")
    print("=" * 50)

    for key, zip_name in BASE_SPRITE_ZIPS.items():
        zip_path = DOWNLOADS_DIR / zip_name
        status = "OK" if zip_path.exists() else "MISSING"
        material, slot = key
        print(f"  {material:8s} {slot:12s} -> {zip_name:30s} [{status}]")


def update_items_json_sprites():
    """Update has_sprites flags in items.json for generated armor."""
    with open(ITEMS_JSON, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # Items are under the "items" key
    items_list = data.get("items", [])

    updated = []
    for item in items_list:
        if not isinstance(item, dict):
            continue
        item_id = item.get("item_id")
        if item_id in WAVE2_ARMOR_ITEMS:
            output_path = FORGED_ARMOR_DIR / item_id
            has_sprites = output_path.exists() and len(list(output_path.glob("*.png"))) >= 2

            if item.get("has_sprites") != has_sprites:
                item["has_sprites"] = has_sprites
                updated.append(item_id)

    if updated:
        with open(ITEMS_JSON, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2)
        print(f"\nUpdated has_sprites for: {', '.join(updated)}")
    else:
        print("\nNo items needed has_sprites update")


def main():
    parser = argparse.ArgumentParser(
        description="Generate tinted armor sprites for forged items",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python forge_armor_tinter.py --check             # Check base zip availability
    python forge_armor_tinter.py --analyze           # Analyze icon colors
    python forge_armor_tinter.py --preview ghost_hakama  # Preview single item
    python forge_armor_tinter.py --generate lich_king_boots  # Generate single
    python forge_armor_tinter.py --generate-all      # Generate all missing
    python forge_armor_tinter.py --update-json       # Update has_sprites flags
        """
    )

    parser.add_argument("--check", action="store_true",
                        help="Check base sprite zip availability")
    parser.add_argument("--analyze", action="store_true",
                        help="Analyze icon colors for all items")
    parser.add_argument("--preview", metavar="ITEM_ID",
                        help="Generate preview for an item")
    parser.add_argument("--preview-all", action="store_true",
                        help="Generate previews for all items")
    parser.add_argument("--generate", metavar="ITEM_ID",
                        help="Generate sprites for an item")
    parser.add_argument("--generate-all", action="store_true",
                        help="Generate sprites for all items")
    parser.add_argument("--update-json", action="store_true",
                        help="Update has_sprites flags in items.json")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be done without saving")
    parser.add_argument("--list", action="store_true",
                        help="List all wave 2 armor items")

    args = parser.parse_args()

    if args.list:
        print("\nWave 2 Armor Items:")
        print("-" * 70)
        for item_id, item in sorted(WAVE2_ARMOR_ITEMS.items()):
            output_path = FORGED_ARMOR_DIR / item_id
            has_sprites = output_path.exists() and len(list(output_path.glob("*.png"))) >= 2
            status = "OK" if has_sprites else "NEEDS SPRITES"
            print(f"  {item_id:30s} {item['material_type']:8s} {item['slot']:12s} [{status}]")
        return

    if args.check:
        check_base_zips()
        return

    if args.analyze:
        analyze_all_icons()
        return

    if args.preview:
        generate_preview(args.preview)
        return

    if args.preview_all:
        for item_id in WAVE2_ARMOR_ITEMS:
            generate_preview(item_id)
        return

    if args.generate:
        generate_armor_sprites(args.generate, dry_run=args.dry_run)
        return

    if args.generate_all:
        print("Generating sprites for all wave 2 armor items...")
        for item_id in WAVE2_ARMOR_ITEMS:
            output_path = FORGED_ARMOR_DIR / item_id
            if output_path.exists() and len(list(output_path.glob("*.png"))) >= 2:
                print(f"\nSKIP: {item_id} (sprites already exist)")
                continue
            generate_armor_sprites(item_id, dry_run=args.dry_run)
        return

    if args.update_json:
        update_items_json_sprites()
        return

    parser.print_help()


if __name__ == "__main__":
    main()
