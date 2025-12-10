#!/usr/bin/env python3
"""
Forge Sprite Tinter - Generates tinted weapon sprites for forged items

Takes base weapon sprites and applies color tinting based on forged item definitions.
Outputs pre-tinted sprites that can be loaded directly by the game.

Usage:
    python forge_sprite_tinter.py --preview gyoubu_spear    # Preview single item
    python forge_sprite_tinter.py --generate gyoubu_spear   # Generate single item
    python forge_sprite_tinter.py --generate-all            # Generate all missing
    python forge_sprite_tinter.py --compare gyoubu_spear    # Generate comparison image

Methods:
    - simple: Multiply tint (basic color overlay)
    - additive: Tint + brightness boost (glowing effect)
    - hue_shift: Rotate hue toward target color (preserves shading)
    - hybrid: Hue shift + additive glow based on rarity
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Tuple, Optional
import colorsys
import math

try:
    from PIL import Image, ImageEnhance, ImageDraw, ImageFont
    import numpy as np
except ImportError:
    print("ERROR: Required packages not found. Install with:")
    print("  pip install Pillow numpy")
    sys.exit(1)

# Project paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_ROOT / "assets"
BASE_WEAPONS_DIR = ASSETS_DIR / "equipment" / "weapons"
FORGED_WEAPONS_DIR = ASSETS_DIR / "equipment" / "forged" / "weapons"
OUTPUT_PREVIEW_DIR = SCRIPT_DIR / "tint_previews"

# Sprite types for weapons
SPRITE_TYPES = ["walk", "thrust", "slash", "hurt"]

# Weapon type fallbacks (extended types -> base types with sprites)
WEAPON_TYPE_FALLBACKS = {
    "greatsword": "sword",
    "longsword": "sword",
    "shortsword": "sword",
    "katana": "sword",
    "rapier": "sword",
    "saber": "sword",
    "scimitar": "sword",
    "halberd": "spear",
    "lance": "spear",
    "pike": "spear",
    "glaive": "spear",
    "hammer": "mace",
    "club": "mace",
    "flail": "mace",
    "bow": "staff",
    "crossbow": "staff",
    "rifle": "gun",
    "railgun": "gun",
    "pistol": "gun",
    "shotgun": "gun",
}

# Forged item definitions (extracted from ForgeItemDB.gd)
# Format: item_id -> {weapon_class, glow_color, rarity, base_type_override}
FORGED_ITEMS = {
    "gyoubu_spear": {
        "weapon_class": "spear",
        "glow_color": "#8B4513",  # Saddle brown - worn metal, Sekiro aesthetic
        "rarity": "common",
        "game": "Sekiro",
        "uses_thrust": True,
    },
    "dragonslayer_swordspear": {
        "weapon_class": "spear",
        "glow_color": "#FFD700",  # Gold with lightning
        "rarity": "rare",
        "game": "Dark Souls 3",
        "uses_thrust": True,
    },
    "coiled_sword": {
        "weapon_class": "sword",
        "glow_color": "#FF4500",  # Orange-red ember
        "rarity": "legendary",
        "game": "Dark Souls 3",
    },
    "farron_greatsword": {
        "weapon_class": "greatsword",
        "glow_color": "#4169E1",  # Royal blue - Abyss Watchers
        "rarity": "uncommon",
        "game": "Dark Souls 3",
    },
    "grafted_blade": {
        "weapon_class": "greatsword",
        "glow_color": "#DAA520",  # Goldenrod - Elden Ring gold
        "rarity": "common",
        "game": "Elden Ring",
    },
    "hand_of_malenia": {
        "weapon_class": "katana",
        "glow_color": "#DC143C",  # Crimson - Scarlet Rot
        "rarity": "rare",
        "game": "Elden Ring",
    },
    "radahns_greatswords": {
        "weapon_class": "greatsword",
        "glow_color": "#8A2BE2",  # Blue violet - gravity magic
        "rarity": "uncommon",
        "game": "Elden Ring",
    },
    "pure_nail": {
        "weapon_class": "sword",
        "glow_color": "#E8E8E8",  # Pale white - Hollow Knight
        "rarity": "uncommon",
        "game": "Hollow Knight",
    },
    "stygian_blade": {
        "weapon_class": "sword",
        "glow_color": "#8B0000",  # Dark red - Hades blood
        "rarity": "common",
        "game": "Hades",
    },
    "adamant_rail": {
        "weapon_class": "gun",
        "glow_color": "#FF6347",  # Tomato - infernal red
        "rarity": "uncommon",
        "game": "Hades",
        "is_gun": True,
    },
    "terra_blade": {
        "weapon_class": "sword",
        "glow_color": "#00FF7F",  # Spring green - Terraria
        "rarity": "legendary",
        "game": "Terraria",
    },
    "mortal_blade": {
        "weapon_class": "katana",
        "glow_color": "#DC143C",  # Crimson - blood red
        "rarity": "legendary",
        "game": "Sekiro",
    },
    "witcher_silver_sword": {
        "weapon_class": "sword",
        "glow_color": "#C0C0C0",  # Silver
        "rarity": "common",
        "game": "Witcher 3",
    },
    "moonveil": {
        "weapon_class": "katana",
        "glow_color": "#4169E1",  # Royal blue - moonlight
        "rarity": "epic",
        "game": "Elden Ring",
    },
    "shade_cloak": {
        "weapon_class": "cape",
        "glow_color": "#1A0033",  # Deep void purple - almost black
        "trim_color": "#6A0DAD",  # Vivid purple for trim accent
        "rarity": "rare",
        "game": "Hollow Knight",
        "is_cape": True,
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


def rgb_to_hsl(r: int, g: int, b: int) -> Tuple[float, float, float]:
    """Convert RGB (0-255) to HSL (0-1)."""
    return colorsys.rgb_to_hls(r/255, g/255, b/255)


def hsl_to_rgb(h: float, l: float, s: float) -> Tuple[int, int, int]:
    """Convert HSL (0-1) to RGB (0-255)."""
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return int(r * 255), int(g * 255), int(b * 255)


def apply_simple_tint(image: Image.Image, color: Tuple[int, int, int], intensity: float = 0.5) -> Image.Image:
    """
    Simple multiply tint - blends original with colored version.

    Args:
        image: Source image (RGBA)
        color: Target color RGB
        intensity: How strong the tint is (0-1)

    Returns:
        Tinted image
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    # Convert to numpy for faster processing
    arr = np.array(image, dtype=np.float32)

    # Separate alpha channel
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3:4]

    # Create tint color array
    tint = np.array(color, dtype=np.float32) / 255.0

    # Apply multiply blend
    tinted = rgb / 255.0 * tint

    # Blend with original based on intensity
    result = rgb / 255.0 * (1 - intensity) + tinted * intensity

    # Recombine with alpha
    result = np.clip(result * 255, 0, 255).astype(np.uint8)
    result = np.concatenate([result, alpha.astype(np.uint8)], axis=2)

    return Image.fromarray(result, 'RGBA')


def apply_additive_glow(image: Image.Image, color: Tuple[int, int, int], intensity: float = 0.5) -> Image.Image:
    """
    Additive glow - adds color brightness on top of original.

    Args:
        image: Source image (RGBA)
        color: Glow color RGB
        intensity: Glow strength (0-1)

    Returns:
        Glowing image
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3]
    alpha = arr[:, :, 3:4]

    # Create glow color array
    glow = np.array(color, dtype=np.float32)

    # Only apply glow to non-transparent pixels
    mask = (alpha > 0).astype(np.float32)

    # Additive blend - add glow color scaled by intensity
    result = rgb + glow * intensity * mask

    # Clip to valid range
    result = np.clip(result, 0, 255).astype(np.uint8)
    result = np.concatenate([result, alpha.astype(np.uint8)], axis=2)

    return Image.fromarray(result, 'RGBA')


def apply_hue_shift(image: Image.Image, target_color: Tuple[int, int, int], intensity: float = 0.7) -> Image.Image:
    """
    Hue shift - rotates hue toward target color while preserving luminance/saturation.

    Args:
        image: Source image (RGBA)
        target_color: Target color to shift toward
        intensity: How much to shift (0-1)

    Returns:
        Hue-shifted image
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    arr = np.array(image, dtype=np.float32)
    rgb = arr[:, :, :3] / 255.0
    alpha = arr[:, :, 3]

    # Get target hue
    target_h, target_l, target_s = rgb_to_hsl(*target_color)

    # Process each pixel
    result = np.zeros_like(rgb)

    for y in range(rgb.shape[0]):
        for x in range(rgb.shape[1]):
            if alpha[y, x] > 0:  # Only process visible pixels
                r, g, b = rgb[y, x]
                h, l, s = colorsys.rgb_to_hls(r, g, b)

                # Shift hue toward target
                # Handle hue wraparound (hue is circular 0-1)
                h_diff = target_h - h
                if h_diff > 0.5:
                    h_diff -= 1.0
                elif h_diff < -0.5:
                    h_diff += 1.0

                new_h = (h + h_diff * intensity) % 1.0

                # Optionally boost saturation slightly toward target
                new_s = s + (target_s - s) * intensity * 0.3
                new_s = max(0, min(1, new_s))

                # Convert back to RGB
                new_r, new_g, new_b = colorsys.hls_to_rgb(new_h, l, new_s)
                result[y, x] = [new_r, new_g, new_b]
            else:
                result[y, x] = rgb[y, x]

    # Recombine
    result = (result * 255).astype(np.uint8)
    result = np.dstack([result, alpha.astype(np.uint8)])

    return Image.fromarray(result, 'RGBA')


def apply_hybrid_tint(image: Image.Image, color: Tuple[int, int, int], rarity: str) -> Image.Image:
    """
    Hybrid approach - hue shift base + additive glow based on rarity.

    Args:
        image: Source image (RGBA)
        color: Target color
        rarity: Item rarity for glow intensity

    Returns:
        Tinted and glowing image
    """
    # Get intensity based on rarity
    glow_intensity = RARITY_GLOW_INTENSITY.get(rarity.lower(), 0.5)

    # First apply hue shift (moderate intensity)
    result = apply_hue_shift(image, color, intensity=0.6)

    # Then add glow based on rarity
    if glow_intensity > 0.3:
        result = apply_additive_glow(result, color, intensity=glow_intensity * 0.3)

    return result


def get_base_weapon_path(weapon_class: str) -> Path:
    """Get the base weapon sprite folder for a weapon class."""
    # Apply fallback if needed
    base_type = WEAPON_TYPE_FALLBACKS.get(weapon_class, weapon_class)
    return BASE_WEAPONS_DIR / base_type


def load_sprite(path: Path) -> Optional[Image.Image]:
    """Load a sprite image, return None if not found."""
    if path.exists():
        return Image.open(path).convert('RGBA')
    return None


def generate_comparison_image(item_id: str, output_path: Path) -> bool:
    """
    Generate a comparison image showing all tinting methods side by side.

    Args:
        item_id: Forged item ID
        output_path: Where to save the comparison image

    Returns:
        True if successful
    """
    if item_id not in FORGED_ITEMS:
        print(f"ERROR: Unknown item '{item_id}'")
        return False

    item = FORGED_ITEMS[item_id]
    weapon_class = item["weapon_class"]
    glow_color = hex_to_rgb(item["glow_color"])
    rarity = item["rarity"]

    # Get base weapon path
    base_path = get_base_weapon_path(weapon_class)

    # Try to load walk sprite (most representative)
    sprite_path = base_path / "walk.png"
    if not sprite_path.exists():
        print(f"ERROR: Base sprite not found: {sprite_path}")
        return False

    original = Image.open(sprite_path).convert('RGBA')

    # Extract a single frame for comparison (first frame, south-facing)
    frame_size = 64
    frame = original.crop((0, frame_size * 2, frame_size, frame_size * 3))  # Row 2 (south)

    # Generate all variants
    variants = {
        "Original": frame,
        "Simple Tint": apply_simple_tint(frame.copy(), glow_color, 0.5),
        "Additive Glow": apply_additive_glow(frame.copy(), glow_color, 0.4),
        "Hue Shift": apply_hue_shift(frame.copy(), glow_color, 0.7),
        "Hybrid": apply_hybrid_tint(frame.copy(), glow_color, rarity),
    }

    # Create comparison image
    padding = 10
    label_height = 20
    cols = len(variants)
    width = cols * frame_size + (cols + 1) * padding
    height = frame_size + label_height + padding * 3

    comparison = Image.new('RGBA', (width, height), (40, 40, 40, 255))
    draw = ImageDraw.Draw(comparison)

    # Try to load a font, fall back to default
    try:
        font = ImageFont.truetype("arial.ttf", 12)
    except:
        font = ImageFont.load_default()

    # Place each variant
    x = padding
    for name, img in variants.items():
        # Draw label
        draw.text((x, padding), name, fill=(255, 255, 255, 255), font=font)

        # Paste image
        comparison.paste(img, (x, padding + label_height + 5), img)

        x += frame_size + padding

    # Add item info at bottom
    info_text = f"{item_id} | {item['game']} | {rarity.upper()} | {item['glow_color']}"
    draw.text((padding, height - 15), info_text, fill=(180, 180, 180, 255), font=font)

    # Save
    output_path.parent.mkdir(parents=True, exist_ok=True)
    comparison.save(output_path)
    print(f"Saved comparison: {output_path}")

    return True


def generate_forged_sprites(item_id: str, method: str = "hybrid", dry_run: bool = False) -> bool:
    """
    Generate all tinted sprites for a forged item.

    Args:
        item_id: Forged item ID
        method: Tinting method (simple, additive, hue_shift, hybrid)
        dry_run: If True, don't actually save files

    Returns:
        True if successful
    """
    if item_id not in FORGED_ITEMS:
        print(f"ERROR: Unknown item '{item_id}'")
        return False

    item = FORGED_ITEMS[item_id]
    weapon_class = item["weapon_class"]
    glow_color = hex_to_rgb(item["glow_color"])
    rarity = item["rarity"]
    uses_thrust = item.get("uses_thrust", False)

    # Get base weapon path
    base_path = get_base_weapon_path(weapon_class)
    output_path = FORGED_WEAPONS_DIR / item_id

    print(f"\nGenerating sprites for: {item_id}")
    print(f"  Weapon class: {weapon_class}")
    print(f"  Base path: {base_path}")
    print(f"  Output path: {output_path}")
    print(f"  Glow color: {item['glow_color']}")
    print(f"  Rarity: {rarity}")
    print(f"  Method: {method}")

    if not base_path.exists():
        print(f"ERROR: Base weapon folder not found: {base_path}")
        return False

    # Determine which sprite types to generate
    sprite_types = ["walk", "hurt"]
    if uses_thrust:
        sprite_types.append("thrust")
    else:
        sprite_types.append("slash")
        sprite_types.append("thrust")  # Some weapons have both

    # Process each sprite type
    generated = []
    for sprite_type in sprite_types:
        src_path = base_path / f"{sprite_type}.png"
        dst_path = output_path / f"{sprite_type}.png"

        if not src_path.exists():
            print(f"  SKIP: {sprite_type}.png (not found in base)")
            continue

        # Load source sprite
        sprite = Image.open(src_path).convert('RGBA')

        # Apply tinting method
        if method == "simple":
            tinted = apply_simple_tint(sprite, glow_color, 0.5)
        elif method == "additive":
            tinted = apply_additive_glow(sprite, glow_color, 0.4)
        elif method == "hue_shift":
            tinted = apply_hue_shift(sprite, glow_color, 0.7)
        elif method == "hybrid":
            tinted = apply_hybrid_tint(sprite, glow_color, rarity)
        else:
            print(f"ERROR: Unknown method '{method}'")
            return False

        if dry_run:
            print(f"  WOULD GENERATE: {dst_path}")
        else:
            output_path.mkdir(parents=True, exist_ok=True)
            tinted.save(dst_path)
            print(f"  GENERATED: {dst_path}")

        generated.append(sprite_type)

    print(f"  Total: {len(generated)} sprites")
    return True


def generate_cape_sprites(item_id: str, base_path: Path, method: str = "hybrid", dry_run: bool = False) -> bool:
    """
    Generate tinted cape sprites from separate base + trim layers.

    Args:
        item_id: Forged item ID (e.g., 'shade_cloak')
        base_path: Path to LPC download folder with standard/ subfolder
        method: Tinting method
        dry_run: If True, don't save files

    Returns:
        True if successful
    """
    if item_id not in FORGED_ITEMS:
        print(f"ERROR: Unknown item '{item_id}'")
        return False

    item = FORGED_ITEMS[item_id]
    glow_color = hex_to_rgb(item["glow_color"])
    trim_color = hex_to_rgb(item.get("trim_color", item["glow_color"]))
    rarity = item["rarity"]

    output_path = FORGED_WEAPONS_DIR.parent / "capes" / item_id

    print(f"\nGenerating cape sprites for: {item_id}")
    print(f"  Base path: {base_path}")
    print(f"  Output path: {output_path}")
    print(f"  Cape color: {item['glow_color']}")
    print(f"  Trim color: {item.get('trim_color', 'same as cape')}")
    print(f"  Rarity: {rarity}")

    # Map our animation names to LPC folder names
    anim_mapping = {
        "walk": "walk",
        "slash": "slash",
        "thrust": "thrust",
        "hurt": "hurt",
    }

    generated = []
    for our_name, lpc_name in anim_mapping.items():
        lpc_folder = base_path / "standard" / lpc_name
        if not lpc_folder.exists():
            print(f"  SKIP: {our_name} (folder not found)")
            continue

        # Find cape base and trim files
        cape_file = None
        trim_file = None
        for f in lpc_folder.iterdir():
            if "solid" in f.name.lower() and f.suffix == ".png":
                cape_file = f
            elif "trim" in f.name.lower() and f.suffix == ".png":
                trim_file = f

        if not cape_file:
            print(f"  SKIP: {our_name} (no cape base found)")
            continue

        # Load sprites
        cape_img = Image.open(cape_file).convert('RGBA')

        # Apply tint to cape
        if method == "hybrid":
            tinted_cape = apply_hybrid_tint(cape_img, glow_color, rarity)
        elif method == "hue_shift":
            tinted_cape = apply_hue_shift(cape_img, glow_color, 0.7)
        else:
            tinted_cape = apply_simple_tint(cape_img, glow_color, 0.5)

        # If trim exists, tint and composite
        if trim_file:
            trim_img = Image.open(trim_file).convert('RGBA')
            # Tint trim with accent color (slightly more vibrant)
            if method == "hybrid":
                tinted_trim = apply_hybrid_tint(trim_img, trim_color, rarity)
            else:
                tinted_trim = apply_hue_shift(trim_img, trim_color, 0.8)

            # Composite trim on top of cape
            tinted_cape = Image.alpha_composite(tinted_cape, tinted_trim)

        # Save
        dst_path = output_path / f"{our_name}.png"
        if dry_run:
            print(f"  WOULD GENERATE: {dst_path}")
        else:
            output_path.mkdir(parents=True, exist_ok=True)
            tinted_cape.save(dst_path)
            print(f"  GENERATED: {dst_path}")

        generated.append(our_name)

    print(f"  Total: {len(generated)} sprites")
    return len(generated) > 0


def main():
    parser = argparse.ArgumentParser(
        description="Generate tinted weapon sprites for forged items",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python forge_sprite_tinter.py --compare gyoubu_spear
    python forge_sprite_tinter.py --generate gyoubu_spear --method hybrid
    python forge_sprite_tinter.py --generate-all --method hybrid
    python forge_sprite_tinter.py --cape shade_cloak --cape-path "C:/path/to/lpc/download"
    python forge_sprite_tinter.py --list
        """
    )

    parser.add_argument("--compare", metavar="ITEM_ID",
                        help="Generate comparison image for an item")
    parser.add_argument("--generate", metavar="ITEM_ID",
                        help="Generate tinted sprites for an item")
    parser.add_argument("--generate-all", action="store_true",
                        help="Generate sprites for all items missing them")
    parser.add_argument("--method", choices=["simple", "additive", "hue_shift", "hybrid"],
                        default="hybrid", help="Tinting method (default: hybrid)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be generated without saving")
    parser.add_argument("--list", action="store_true",
                        help="List all known forged items")
    parser.add_argument("--compare-all", action="store_true",
                        help="Generate comparison images for all items")
    parser.add_argument("--cape", metavar="ITEM_ID",
                        help="Generate cape sprites from LPC layers")
    parser.add_argument("--cape-path", metavar="PATH",
                        help="Path to LPC download folder for cape generation")

    args = parser.parse_args()

    if args.list:
        print("\nKnown forged items:")
        print("-" * 60)
        for item_id, item in sorted(FORGED_ITEMS.items()):
            base_type = WEAPON_TYPE_FALLBACKS.get(item["weapon_class"], item["weapon_class"])
            has_base = (BASE_WEAPONS_DIR / base_type).exists()
            forged_path = FORGED_WEAPONS_DIR / item_id
            has_sprites = forged_path.exists() and any(forged_path.glob("*.png"))

            status = "OK" if has_sprites else ("BASE" if has_base else "NO BASE")
            print(f"  {item_id:30s} {item['weapon_class']:12s} {item['rarity']:10s} [{status}]")
        return

    if args.compare:
        output_path = OUTPUT_PREVIEW_DIR / f"{args.compare}_comparison.png"
        generate_comparison_image(args.compare, output_path)
        return

    if args.compare_all:
        OUTPUT_PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        for item_id in FORGED_ITEMS:
            output_path = OUTPUT_PREVIEW_DIR / f"{item_id}_comparison.png"
            generate_comparison_image(item_id, output_path)
        print(f"\nAll comparisons saved to: {OUTPUT_PREVIEW_DIR}")
        return

    if args.generate:
        generate_forged_sprites(args.generate, method=args.method, dry_run=args.dry_run)
        return

    if args.generate_all:
        print("Generating sprites for all items with missing sprites...")
        for item_id in FORGED_ITEMS:
            # Skip capes - they need special handling
            if FORGED_ITEMS[item_id].get("is_cape"):
                print(f"\nSKIP: {item_id} (cape - use --cape flag)")
                continue
            forged_path = FORGED_WEAPONS_DIR / item_id
            # Check if sprites already exist
            if forged_path.exists() and len(list(forged_path.glob("*.png"))) >= 2:
                print(f"\nSKIP: {item_id} (sprites already exist)")
                continue
            generate_forged_sprites(item_id, method=args.method, dry_run=args.dry_run)
        return

    if args.cape:
        if not args.cape_path:
            print("ERROR: --cape-path required for cape generation")
            print("Example: --cape shade_cloak --cape-path 'C:/Users/kevin/Downloads/lpc_...'")
            return
        cape_path = Path(args.cape_path)
        if not cape_path.exists():
            print(f"ERROR: Cape path not found: {cape_path}")
            return
        generate_cape_sprites(args.cape, cape_path, method=args.method, dry_run=args.dry_run)
        return

    # No action specified, show help
    parser.print_help()


if __name__ == "__main__":
    main()
