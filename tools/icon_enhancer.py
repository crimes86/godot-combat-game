#!/usr/bin/env python3
"""
Icon Enhancer - Upscale pixel art icons using xBRZ algorithm

Takes 64x64 game icons and upscales them to 256x256 while preserving
pixel art aesthetics using the xBRZ algorithm (same as retro game emulators).

Processes both:
- Forged icons: Hand-crafted 64x64 PNGs in assets/icons/forged/
- Equipment icons: Extracted from LPC walk spritesheets

Usage:
    python icon_enhancer.py --source forged       # Process forged icons
    python icon_enhancer.py --source equipment    # Process equipment icons
    python icon_enhancer.py --all                 # Process everything
    python icon_enhancer.py --file <path>         # Single file
    python icon_enhancer.py --preview             # Generate comparison grid
    python icon_enhancer.py --dry-run             # Show what would be processed

Dependencies:
    pip install Pillow numpy
    pip install xbrz.py[pillow]    # Optional, falls back to Lanczos if unavailable
"""

import argparse
import sys
from pathlib import Path
from typing import Optional, Dict, List, Tuple
import math

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
    import numpy as np
except ImportError:
    print("ERROR: Required packages not found. Install with:")
    print("  pip install Pillow numpy")
    sys.exit(1)

# Try to import xBRZ, will fall back to alternatives if not available
XBRZ_AVAILABLE = False
try:
    import xbrz
    XBRZ_AVAILABLE = True
except ImportError:
    pass

# Project paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
ASSETS_DIR = PROJECT_ROOT / "assets"
FORGED_ICONS_DIR = ASSETS_DIR / "icons" / "forged"
ENHANCED_ICONS_DIR = ASSETS_DIR / "icons" / "enhanced"
EQUIPMENT_DIR = ASSETS_DIR / "equipment"
CHARACTERS_DIR = ASSETS_DIR / "characters"

# Icon constants
FRAME_SIZE = 64
TARGET_SIZE = 256
SCALE_FACTOR = 4

# LPC walk sprite directions (row indices)
DIR_UP = 0
DIR_LEFT = 1
DIR_DOWN = 2
DIR_RIGHT = 3

# Slot-to-direction mapping (which facing looks best for each equipment slot)
SLOT_DIRECTIONS = {
    "chest": DIR_DOWN,
    "shirt": DIR_DOWN,
    "legs": DIR_DOWN,
    "pants": DIR_DOWN,
    "feet": DIR_DOWN,
    "boots": DIR_DOWN,
    "head": DIR_RIGHT,
    "hands": DIR_DOWN,
    "arms": DIR_RIGHT,
    "weapon": DIR_RIGHT,
    "tool": DIR_RIGHT,
}

# Forged icon categories
FORGED_CATEGORIES = ["weapons", "armor", "shields", "accessories", "capes", "tools"]


def upscale_xbrz(image: Image.Image, scale: int = 4) -> Image.Image:
    """
    Upscale image using xBRZ algorithm.

    xBRZ is specifically designed for pixel art - it detects edges and curves,
    then intelligently interpolates to create smooth lines while preserving
    the pixel art aesthetic.
    """
    if not XBRZ_AVAILABLE:
        raise RuntimeError("xBRZ library not available")

    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    # xbrz.scale expects PIL Image and returns PIL Image
    return xbrz.scale_pillow(image, scale)


def upscale_lanczos(image: Image.Image, target_size: int = 256) -> Image.Image:
    """
    Upscale using Lanczos resampling (fallback when xBRZ unavailable).

    Lanczos is high-quality but doesn't preserve pixel art edges as well as xBRZ.
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    return image.resize((target_size, target_size), Image.Resampling.LANCZOS)


def upscale_epx_lanczos(image: Image.Image, target_size: int = 256) -> Image.Image:
    """
    Hybrid approach: EPX 2x first, then Lanczos to target size.

    EPX (Eric's Pixel Expansion) is a simple pixel art scaler that helps
    preserve edges before applying Lanczos smoothing.
    """
    if image.mode != 'RGBA':
        image = image.convert('RGBA')

    # Apply EPX 2x scaling first
    epx_result = apply_epx_2x(image)

    # Then scale to final target with Lanczos
    return epx_result.resize((target_size, target_size), Image.Resampling.LANCZOS)


def apply_epx_2x(image: Image.Image) -> Image.Image:
    """
    Apply EPX (Eric's Pixel Expansion) 2x scaling algorithm.

    EPX is a simple edge-aware pixel art scaler:
    For each pixel P with neighbors A,B,C,D:
        A
      C P B
        D

    The 4 output pixels are:
      1 2    1=P, 2=P, 3=P, 4=P (default)
      3 4    1=A if A==C, 2=A if A==B, 3=C if C==D, 4=B if B==D
    """
    arr = np.array(image, dtype=np.uint8)
    h, w = arr.shape[:2]

    # Create output array (2x size)
    out = np.zeros((h * 2, w * 2, 4), dtype=np.uint8)

    for y in range(h):
        for x in range(w):
            p = arr[y, x]

            # Get neighbors (with bounds checking)
            a = arr[y-1, x] if y > 0 else p
            b = arr[y, x+1] if x < w-1 else p
            c = arr[y, x-1] if x > 0 else p
            d = arr[y+1, x] if y < h-1 else p

            # Output coordinates
            ox, oy = x * 2, y * 2

            # Default: all 4 output pixels are P
            out[oy, ox] = p
            out[oy, ox+1] = p
            out[oy+1, ox] = p
            out[oy+1, ox+1] = p

            # EPX rules (compare RGBA values)
            if np.array_equal(a, c) and not np.array_equal(a, b) and not np.array_equal(c, d):
                out[oy, ox] = a
            if np.array_equal(a, b) and not np.array_equal(a, c) and not np.array_equal(b, d):
                out[oy, ox+1] = b
            if np.array_equal(c, d) and not np.array_equal(a, c) and not np.array_equal(b, d):
                out[oy+1, ox] = c
            if np.array_equal(b, d) and not np.array_equal(a, b) and not np.array_equal(c, d):
                out[oy+1, ox+1] = d

    return Image.fromarray(out)


def upscale_image(image: Image.Image, algorithm: str = "auto",
                  scale: int = 4) -> Image.Image:
    """
    Upscale image using specified algorithm with automatic fallback.

    Args:
        image: Source PIL Image (should be 64x64)
        algorithm: "xbrz", "lanczos", "epx", or "auto"
        scale: Scale factor (default 4 for 64->256)

    Returns:
        Upscaled PIL Image
    """
    target_size = image.width * scale

    if algorithm == "auto":
        # Try xBRZ first, fall back to EPX+Lanczos, then pure Lanczos
        if XBRZ_AVAILABLE:
            try:
                return upscale_xbrz(image, scale)
            except Exception as e:
                print(f"  Warning: xBRZ failed ({e}), falling back to EPX+Lanczos")
        return upscale_epx_lanczos(image, target_size)

    elif algorithm == "xbrz":
        if XBRZ_AVAILABLE:
            return upscale_xbrz(image, scale)
        else:
            print("  Warning: xBRZ not available, using EPX+Lanczos")
            return upscale_epx_lanczos(image, target_size)

    elif algorithm == "epx":
        return upscale_epx_lanczos(image, target_size)

    elif algorithm == "lanczos":
        return upscale_lanczos(image, target_size)

    else:
        raise ValueError(f"Unknown algorithm: {algorithm}")


def get_content_bbox(image: Image.Image) -> Optional[Tuple[int, int, int, int]]:
    """Get bounding box of non-transparent pixels."""
    if image.mode != 'RGBA':
        image = image.convert('RGBA')
    return image.getbbox()


def auto_crop(image: Image.Image, padding: int = 2) -> Image.Image:
    """Crop transparent edges, keeping minimum padding."""
    bbox = get_content_bbox(image)
    if not bbox:
        return image

    x1, y1, x2, y2 = bbox
    # Add padding
    x1 = max(0, x1 - padding)
    y1 = max(0, y1 - padding)
    x2 = min(image.width, x2 + padding)
    y2 = min(image.height, y2 + padding)

    return image.crop((x1, y1, x2, y2))


def center_in_canvas(image: Image.Image, canvas_size: int,
                     fill_percent: float = 0.0) -> Image.Image:
    """
    Center image content in a square canvas.

    Args:
        image: Source image
        canvas_size: Size of output canvas (square)
        fill_percent: If > 0, scale content to fill this percentage of canvas (0.0-1.0)
                      E.g., 0.85 means content will fill 85% of the canvas
    """
    # Auto-crop first to get just the content
    cropped = auto_crop(image, padding=0)

    max_dim = max(cropped.width, cropped.height)
    target_size = canvas_size - 8  # Leave 4px padding on each side

    if fill_percent > 0:
        # Scale content to fill the specified percentage of the canvas
        target_content_size = int(canvas_size * fill_percent)
        scale = target_content_size / max_dim
        new_size = (int(cropped.width * scale), int(cropped.height * scale))
        # Clamp to not exceed canvas
        if new_size[0] > target_size or new_size[1] > target_size:
            fit_scale = min(target_size / new_size[0], target_size / new_size[1])
            new_size = (int(new_size[0] * fit_scale), int(new_size[1] * fit_scale))
        cropped = cropped.resize(new_size, Image.Resampling.LANCZOS)
    elif max_dim > target_size:
        # Only scale down if larger than canvas
        scale = target_size / max_dim
        new_size = (int(cropped.width * scale), int(cropped.height * scale))
        cropped = cropped.resize(new_size, Image.Resampling.LANCZOS)

    # Create canvas and paste centered
    canvas = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - cropped.width) // 2
    y = (canvas_size - cropped.height) // 2
    canvas.paste(cropped, (x, y), cropped)

    return canvas


def extract_frame_from_spritesheet(sprite_path: Path, direction: int = DIR_DOWN,
                                    frame: int = 0) -> Image.Image:
    """
    Extract a single frame from an LPC walk spritesheet.

    LPC walk spritesheets are 576x256 pixels (9 frames x 4 directions, 64x64 each):
    - Row 0: Up (north)
    - Row 1: Left (west)
    - Row 2: Down (south) - typically best for armor display
    - Row 3: Right (east) - typically best for weapons
    """
    img = Image.open(sprite_path).convert('RGBA')

    # Calculate crop coordinates
    x = frame * FRAME_SIZE
    y = direction * FRAME_SIZE

    # Ensure we're within bounds
    if x + FRAME_SIZE > img.width or y + FRAME_SIZE > img.height:
        raise ValueError(f"Frame out of bounds: {sprite_path} (size {img.size})")

    return img.crop((x, y, x + FRAME_SIZE, y + FRAME_SIZE))


def process_forged_icons(output_dir: Path, algorithm: str = "auto",
                         dry_run: bool = False, verbose: bool = True) -> Dict:
    """
    Process all forged icons (hand-crafted 64x64 PNGs).

    Source: assets/icons/forged/{category}/*.png
    Output: assets/icons/enhanced/forged/{category}/*.png
    """
    stats = {"processed": 0, "skipped": 0, "errors": []}

    print("\n=== Processing Forged Icons ===")

    for category in FORGED_CATEGORIES:
        cat_dir = FORGED_ICONS_DIR / category
        if not cat_dir.exists():
            continue

        out_cat_dir = output_dir / "forged" / category

        for icon_path in sorted(cat_dir.glob("*.png")):
            # Skip backup files and preview grids
            if "backup" in str(icon_path).lower() or "preview" in icon_path.name.lower():
                continue

            try:
                img = Image.open(icon_path).convert('RGBA')

                # Validate source size
                if img.size != (FRAME_SIZE, FRAME_SIZE):
                    if verbose:
                        print(f"  SKIP: {category}/{icon_path.name} (size {img.size}, expected {FRAME_SIZE}x{FRAME_SIZE})")
                    stats["skipped"] += 1
                    continue

                if dry_run:
                    print(f"  WOULD PROCESS: {category}/{icon_path.name}")
                else:
                    # Upscale
                    enhanced = upscale_image(img, algorithm)

                    # Save
                    out_path = out_cat_dir / icon_path.name
                    out_cat_dir.mkdir(parents=True, exist_ok=True)
                    enhanced.save(out_path, "PNG")

                    if verbose:
                        print(f"  CREATED: {category}/{icon_path.name} -> {enhanced.size[0]}x{enhanced.size[1]}")

                stats["processed"] += 1

            except Exception as e:
                stats["errors"].append((icon_path, str(e)))
                print(f"  ERROR: {category}/{icon_path.name} - {e}")

    return stats


def discover_equipment_spritesheets() -> List[Tuple[Path, str, str]]:
    """
    Discover all equipment spritesheets that can be converted to icons.

    Returns list of (path, slot, item_name) tuples.
    """
    spritesheets = []

    # Weapons: assets/equipment/weapons/{type}/walk.png
    weapons_dir = EQUIPMENT_DIR / "weapons"
    if weapons_dir.exists():
        for weapon_dir in weapons_dir.iterdir():
            if weapon_dir.is_dir():
                walk_path = weapon_dir / "walk.png"
                if walk_path.exists():
                    spritesheets.append((walk_path, "weapon", weapon_dir.name))

    # Tools: assets/equipment/tools/{type}/walk.png
    tools_dir = EQUIPMENT_DIR / "tools"
    if tools_dir.exists():
        for tool_dir in tools_dir.iterdir():
            if tool_dir.is_dir():
                walk_path = tool_dir / "walk.png"
                if walk_path.exists():
                    spritesheets.append((walk_path, "tool", tool_dir.name))

    # Starter clothes: assets/characters/{slot}/{item}_walk.png
    starter_slots = ["shirt", "pants", "boots", "hands", "arms", "head"]
    for slot in starter_slots:
        slot_dir = CHARACTERS_DIR / slot
        if slot_dir.exists():
            for walk_file in slot_dir.glob("*_walk.png"):
                item_name = walk_file.stem.replace("_walk", "")
                spritesheets.append((walk_file, slot, item_name))

    # Also check female variants
    for slot in starter_slots:
        slot_dir = CHARACTERS_DIR / f"{slot}_female"
        if slot_dir.exists():
            for walk_file in slot_dir.glob("*_walk.png"):
                item_name = walk_file.stem.replace("_walk", "")
                spritesheets.append((walk_file, f"{slot}_female", item_name))

    # Tier armor: assets/equipment/armor/tier1/{slot}/{item}/standard/walk.png
    armor_dir = EQUIPMENT_DIR / "armor"
    if armor_dir.exists():
        for tier_dir in armor_dir.iterdir():
            if tier_dir.is_dir() and tier_dir.name.startswith("tier"):
                for slot_dir in tier_dir.iterdir():
                    if slot_dir.is_dir():
                        for item_dir in slot_dir.iterdir():
                            if item_dir.is_dir():
                                walk_path = item_dir / "standard" / "walk.png"
                                if walk_path.exists():
                                    spritesheets.append((walk_path, slot_dir.name, item_dir.name))

    return spritesheets


def process_equipment_icons(output_dir: Path, algorithm: str = "auto",
                            dry_run: bool = False, verbose: bool = True,
                            fill_percent: float = 0.0) -> Dict:
    """
    Process equipment spritesheets to create enhanced icons.

    Extracts frame 0 from each walk spritesheet, using the appropriate
    direction based on equipment slot.

    Args:
        fill_percent: Scale content to fill this percentage of canvas (0.0-1.0)
                      Use 0.85 for armor pieces that are too small
    """
    stats = {"processed": 0, "skipped": 0, "errors": []}

    print("\n=== Processing Equipment Icons ===")
    if fill_percent > 0:
        print(f"Content fill: {int(fill_percent * 100)}%")

    spritesheets = discover_equipment_spritesheets()
    print(f"Found {len(spritesheets)} equipment spritesheets")

    for sprite_path, slot, item_name in spritesheets:
        try:
            # Determine best direction for this slot
            base_slot = slot.replace("_female", "")
            direction = SLOT_DIRECTIONS.get(base_slot, DIR_DOWN)

            # Extract frame
            frame = extract_frame_from_spritesheet(sprite_path, direction, frame=0)

            # Center in 64x64 canvas (auto-crops transparent edges)
            # Use fill_percent to scale up small content (like armor pieces)
            centered = center_in_canvas(frame, FRAME_SIZE, fill_percent)

            # Determine output path
            out_subdir = output_dir / "equipment" / slot
            out_path = out_subdir / f"{item_name}.png"

            if dry_run:
                print(f"  WOULD PROCESS: equipment/{slot}/{item_name}.png")
            else:
                # Upscale
                enhanced = upscale_image(centered, algorithm)

                # Save
                out_subdir.mkdir(parents=True, exist_ok=True)
                enhanced.save(out_path, "PNG")

                if verbose:
                    print(f"  CREATED: equipment/{slot}/{item_name}.png -> {enhanced.size[0]}x{enhanced.size[1]}")

            stats["processed"] += 1

        except Exception as e:
            stats["errors"].append((sprite_path, str(e)))
            print(f"  ERROR: {slot}/{item_name} - {e}")

    return stats


def process_single_file(file_path: Path, output_path: Optional[Path],
                        algorithm: str = "auto", dry_run: bool = False) -> bool:
    """Process a single icon file."""
    if not file_path.exists():
        print(f"ERROR: File not found: {file_path}")
        return False

    try:
        img = Image.open(file_path).convert('RGBA')

        # If larger than 64x64, might be a spritesheet - extract first frame
        if img.size[0] > FRAME_SIZE or img.size[1] > FRAME_SIZE:
            print(f"  Detected spritesheet ({img.size}), extracting first south-facing frame...")
            img = extract_frame_from_spritesheet(file_path, DIR_DOWN, frame=0)
            img = center_in_canvas(img, FRAME_SIZE)

        if dry_run:
            print(f"  WOULD PROCESS: {file_path.name} ({img.size}) -> {TARGET_SIZE}x{TARGET_SIZE}")
            return True

        # Upscale
        enhanced = upscale_image(img, algorithm)

        # Determine output path
        if output_path is None:
            output_path = file_path.parent / f"{file_path.stem}_enhanced.png"

        output_path.parent.mkdir(parents=True, exist_ok=True)
        enhanced.save(output_path, "PNG")
        print(f"  CREATED: {output_path} ({enhanced.size[0]}x{enhanced.size[1]})")

        return True

    except Exception as e:
        print(f"  ERROR: {e}")
        return False


def generate_preview_grid(output_dir: Path, max_icons: int = 60) -> Optional[Path]:
    """
    Generate a preview grid showing all enhanced icons.

    Creates a grid image with icons at display size for visual QA.
    """
    print("\n=== Generating Preview Grid ===")

    # Collect all enhanced icons
    all_icons = []

    # Forged icons
    forged_dir = output_dir / "forged"
    if forged_dir.exists():
        for category in FORGED_CATEGORIES:
            cat_dir = forged_dir / category
            if cat_dir.exists():
                for icon_path in sorted(cat_dir.glob("*.png")):
                    all_icons.append((f"forged/{category}", icon_path))

    # Equipment icons
    equipment_dir = output_dir / "equipment"
    if equipment_dir.exists():
        for slot_dir in sorted(equipment_dir.iterdir()):
            if slot_dir.is_dir():
                for icon_path in sorted(slot_dir.glob("*.png")):
                    all_icons.append((f"equipment/{slot_dir.name}", icon_path))

    if not all_icons:
        print("  No enhanced icons found to preview")
        return None

    # Limit to max_icons for reasonable grid size
    if len(all_icons) > max_icons:
        print(f"  Limiting preview to first {max_icons} of {len(all_icons)} icons")
        all_icons = all_icons[:max_icons]

    # Grid layout
    cols = 8
    rows = math.ceil(len(all_icons) / cols)
    cell_size = 280  # Slightly larger than 256 for padding
    icon_display_size = 256

    grid_w = cols * cell_size
    grid_h = rows * cell_size + 80  # Header space

    # Create grid
    grid = Image.new('RGBA', (grid_w, grid_h), (30, 30, 35, 255))
    draw = ImageDraw.Draw(grid)

    # Header
    draw.text((grid_w // 2, 20), "ENHANCED ICONS PREVIEW", fill=(100, 200, 255), anchor="mt")
    draw.text((grid_w // 2, 45), f"{len(all_icons)} icons at {icon_display_size}x{icon_display_size}",
              fill=(150, 150, 150), anchor="mt")

    # Place icons
    for idx, (category, icon_path) in enumerate(all_icons):
        row = idx // cols
        col = idx % cols

        cell_x = col * cell_size
        cell_y = row * cell_size + 80

        # Draw cell background
        draw.rectangle([cell_x + 4, cell_y + 4, cell_x + cell_size - 4, cell_y + cell_size - 4],
                       fill=(45, 45, 50), outline=(60, 60, 65))

        # Load and place icon (scale down for display if needed)
        icon = Image.open(icon_path).convert('RGBA')
        display_size = min(icon_display_size, cell_size - 24)
        if icon.size[0] != display_size:
            icon = icon.resize((display_size, display_size), Image.Resampling.LANCZOS)

        x = cell_x + (cell_size - display_size) // 2
        y = cell_y + (cell_size - display_size) // 2 - 8
        grid.paste(icon, (x, y), icon)

        # Label
        name = icon_path.stem.replace('_', ' ').title()
        if len(name) > 15:
            name = name[:14] + '.'
        draw.text((cell_x + cell_size // 2, cell_y + cell_size - 12),
                  name, fill=(180, 180, 180), anchor="mb")

    # Save
    output_path = output_dir / "preview_grid.png"
    grid.save(output_path, "PNG")
    print(f"  Preview saved: {output_path}")

    return output_path


def generate_comparison_grid(output_dir: Path) -> Optional[Path]:
    """
    Generate a side-by-side comparison showing original vs enhanced icons.
    """
    print("\n=== Generating Comparison Grid ===")

    comparisons = []

    # Find matching original/enhanced pairs for forged icons
    for category in FORGED_CATEGORIES:
        orig_dir = FORGED_ICONS_DIR / category
        enhanced_dir = output_dir / "forged" / category

        if orig_dir.exists() and enhanced_dir.exists():
            for orig_path in sorted(orig_dir.glob("*.png")):
                enhanced_path = enhanced_dir / orig_path.name
                if enhanced_path.exists():
                    comparisons.append((orig_path, enhanced_path, f"forged/{category}/{orig_path.stem}"))

    if not comparisons:
        print("  No comparison pairs found")
        return None

    # Limit for reasonable size
    max_comparisons = 20
    if len(comparisons) > max_comparisons:
        comparisons = comparisons[:max_comparisons]

    # Layout: 2 columns (original | enhanced) per item, multiple rows
    cols = 4  # 2 pairs per row
    rows = math.ceil(len(comparisons) / 2)
    cell_w = 320
    cell_h = 340

    grid_w = cols * cell_w
    grid_h = rows * cell_h + 80

    grid = Image.new('RGBA', (grid_w, grid_h), (30, 30, 35, 255))
    draw = ImageDraw.Draw(grid)

    # Header
    draw.text((grid_w // 2, 20), "BEFORE / AFTER COMPARISON", fill=(100, 200, 255), anchor="mt")
    draw.text((grid_w // 2, 45), f"{len(comparisons)} icons | 64x64 -> 256x256 (4x upscale)",
              fill=(150, 150, 150), anchor="mt")

    for idx, (orig_path, enhanced_path, label) in enumerate(comparisons):
        pair_idx = idx % 2
        row = idx // 2

        base_x = pair_idx * 2 * cell_w
        base_y = row * cell_h + 80

        # Original (64x64, displayed at 128x128 for visibility)
        orig = Image.open(orig_path).convert('RGBA')
        orig_display = orig.resize((128, 128), Image.Resampling.NEAREST)  # Nearest to show pixels

        orig_x = base_x + (cell_w - 128) // 2
        orig_y = base_y + 40
        draw.rectangle([orig_x - 4, orig_y - 4, orig_x + 132, orig_y + 132],
                       outline=(80, 80, 80))
        grid.paste(orig_display, (orig_x, orig_y), orig_display)
        draw.text((base_x + cell_w // 2, orig_y - 10), "64x64 (2x zoom)", fill=(120, 120, 120), anchor="mb")

        # Enhanced (256x256, displayed at 128x128)
        enhanced = Image.open(enhanced_path).convert('RGBA')
        enhanced_display = enhanced.resize((128, 128), Image.Resampling.LANCZOS)

        enh_x = base_x + cell_w + (cell_w - 128) // 2
        enh_y = base_y + 40
        draw.rectangle([enh_x - 4, enh_y - 4, enh_x + 132, enh_y + 132],
                       outline=(100, 200, 100))
        grid.paste(enhanced_display, (enh_x, enh_y), enhanced_display)
        draw.text((base_x + cell_w + cell_w // 2, enh_y - 10), "256x256", fill=(100, 200, 100), anchor="mb")

        # Label
        name = orig_path.stem.replace('_', ' ').title()
        if len(name) > 20:
            name = name[:19] + '.'
        draw.text((base_x + cell_w, base_y + 200), name, fill=(200, 200, 200), anchor="mt")

        # Arrow
        arrow_y = base_y + 100
        draw.text((base_x + cell_w, arrow_y), "->", fill=(150, 150, 150), anchor="mm")

    # Save
    output_path = output_dir / "comparison_grid.png"
    grid.save(output_path, "PNG")
    print(f"  Comparison saved: {output_path}")

    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Upscale pixel art icons using xBRZ algorithm",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python icon_enhancer.py --source forged           # Process forged icons
    python icon_enhancer.py --source equipment        # Process equipment icons
    python icon_enhancer.py --all                     # Process everything
    python icon_enhancer.py --file icon.png           # Single file
    python icon_enhancer.py --all --preview           # Process all + generate preview
    python icon_enhancer.py --all --dry-run           # Show what would be processed
    python icon_enhancer.py --compare                 # Generate before/after comparison

Output:
    Enhanced icons are saved to: assets/icons/enhanced/
    Original icons remain unchanged.
"""
    )

    # Source selection
    source_group = parser.add_mutually_exclusive_group()
    source_group.add_argument("--source", choices=["forged", "equipment"],
                              help="Which icon source to process")
    source_group.add_argument("--file", metavar="PATH",
                              help="Process a single icon file")
    source_group.add_argument("--all", action="store_true",
                              help="Process all icons (forged + equipment)")

    # Output options
    parser.add_argument("--output-dir", metavar="PATH",
                        help=f"Output directory (default: {ENHANCED_ICONS_DIR})")

    # Preview and comparison
    parser.add_argument("--preview", action="store_true",
                        help="Generate preview grid after processing")
    parser.add_argument("--compare", action="store_true",
                        help="Generate before/after comparison grid")

    # Processing options
    parser.add_argument("--algorithm", choices=["auto", "xbrz", "epx", "lanczos"],
                        default="auto",
                        help="Upscaling algorithm (default: auto - tries xBRZ, falls back to EPX+Lanczos)")
    parser.add_argument("--fill", type=float, default=0.0, metavar="PERCENT",
                        help="Scale content to fill this %% of canvas (0.0-1.0). Use 0.85 for small armor icons.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be processed without saving")
    parser.add_argument("--quiet", action="store_true",
                        help="Reduce output verbosity")

    args = parser.parse_args()

    # Check xBRZ availability
    if XBRZ_AVAILABLE:
        print("xBRZ library: AVAILABLE")
    else:
        print("xBRZ library: NOT FOUND (will use EPX+Lanczos fallback)")
        print("  Install with: pip install xbrz.py[pillow]")

    # Determine output directory
    output_dir = Path(args.output_dir) if args.output_dir else ENHANCED_ICONS_DIR

    verbose = not args.quiet
    total_stats = {"processed": 0, "skipped": 0, "errors": []}

    # Process based on arguments
    if args.file:
        file_path = Path(args.file)
        success = process_single_file(file_path, None, args.algorithm, args.dry_run)
        if not success:
            sys.exit(1)

    elif args.source == "forged" or args.all:
        stats = process_forged_icons(output_dir, args.algorithm, args.dry_run, verbose)
        total_stats["processed"] += stats["processed"]
        total_stats["skipped"] += stats["skipped"]
        total_stats["errors"].extend(stats["errors"])

    if args.source == "equipment" or args.all:
        stats = process_equipment_icons(output_dir, args.algorithm, args.dry_run, verbose, args.fill)
        total_stats["processed"] += stats["processed"]
        total_stats["skipped"] += stats["skipped"]
        total_stats["errors"].extend(stats["errors"])

    # Generate preview/comparison grids
    if args.preview and not args.dry_run:
        generate_preview_grid(output_dir)

    if args.compare and not args.dry_run:
        generate_comparison_grid(output_dir)

    # Summary
    if args.source or args.all:
        print(f"\n=== SUMMARY ===")
        print(f"Processed: {total_stats['processed']}")
        print(f"Skipped: {total_stats['skipped']}")
        print(f"Errors: {len(total_stats['errors'])}")
        if total_stats['errors']:
            print("\nErrors:")
            for path, error in total_stats['errors']:
                print(f"  {path}: {error}")
        if not args.dry_run:
            print(f"\nOutput: {output_dir}")

    # Show help if no action specified
    if not (args.source or args.all or args.file or args.compare or args.preview):
        parser.print_help()


if __name__ == "__main__":
    main()
