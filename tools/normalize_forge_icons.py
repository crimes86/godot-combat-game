#!/usr/bin/env python3
"""
Normalize Forge Icons - Standardize all forge icons to 64x64 with optional smoothing.

Usage:
    python normalize_forge_icons.py [--smooth] [--preview]

Options:
    --smooth   Apply edge smoothing to reduce pixelation
    --preview  Show before/after preview without saving
    --backup   Create backup of originals before processing
"""

import os
import sys
import shutil
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    print("ERROR: Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

# Configuration
TARGET_SIZE = (64, 64)
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent
BACKUP_DIR = PROJECT_ROOT / "assets" / "icons" / "_backup_originals"

# Folders to process
ICON_FOLDERS = [
    PROJECT_ROOT / "assets" / "icons" / "enhanced" / "forged" / "armor",
    PROJECT_ROOT / "assets" / "icons" / "enhanced" / "forged" / "weapons",
    PROJECT_ROOT / "assets" / "icons" / "enhanced" / "forged" / "accessories",
    PROJECT_ROOT / "assets" / "icons" / "enhanced" / "forged" / "capes",
    PROJECT_ROOT / "assets" / "icons" / "enhanced" / "forged" / "shields",
    PROJECT_ROOT / "assets" / "icons" / "forged" / "armor",
    PROJECT_ROOT / "assets" / "icons" / "forged" / "weapons",
    PROJECT_ROOT / "assets" / "icons" / "forged" / "accessories",
    PROJECT_ROOT / "assets" / "icons" / "forged" / "capes",
    PROJECT_ROOT / "assets" / "icons" / "forged" / "shields",
]


def smooth_icon(img: Image.Image) -> Image.Image:
    """Apply edge smoothing to reduce blocky pixelation."""
    # Convert to RGBA if needed
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Split into RGB and Alpha
    r, g, b, a = img.split()

    # Apply slight smoothing to RGB channels only (preserve alpha edges)
    rgb = Image.merge('RGB', (r, g, b))

    # Smooth then sharpen for cleaner edges
    rgb = rgb.filter(ImageFilter.SMOOTH_MORE)
    rgb = rgb.filter(ImageFilter.SHARPEN)

    # Recombine with original alpha
    r, g, b = rgb.split()
    return Image.merge('RGBA', (r, g, b, a))


def process_icon(filepath: Path, apply_smooth: bool = False, backup: bool = False) -> dict:
    """Process a single icon file. Returns status dict."""
    result = {
        "file": filepath.name,
        "original_size": None,
        "action": "skipped",
        "error": None
    }

    try:
        img = Image.open(filepath)
        result["original_size"] = img.size

        # Skip if already target size and no smoothing requested
        if img.size == TARGET_SIZE and not apply_smooth:
            result["action"] = "already_correct"
            return result

        # Backup original if requested
        if backup:
            backup_path = BACKUP_DIR / filepath.parent.name / filepath.name
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            if not backup_path.exists():
                shutil.copy2(filepath, backup_path)

        # Convert to RGBA for processing
        if img.mode != 'RGBA':
            img = img.convert('RGBA')

        # Resize if needed
        if img.size != TARGET_SIZE:
            # Use LANCZOS for high-quality downscaling
            img = img.resize(TARGET_SIZE, Image.LANCZOS)
            result["action"] = f"resized_{result['original_size'][0]}x{result['original_size'][1]}_to_64x64"

        # Apply smoothing if requested
        if apply_smooth:
            img = smooth_icon(img)
            if "resized" in result["action"]:
                result["action"] += "+smoothed"
            else:
                result["action"] = "smoothed"

        # Save
        img.save(filepath, "PNG", optimize=True)

    except Exception as e:
        result["error"] = str(e)
        result["action"] = "error"

    return result


def preview_icon(filepath: Path, apply_smooth: bool = False):
    """Show before/after preview of an icon."""
    try:
        original = Image.open(filepath)

        # Process copy
        processed = original.copy()
        if processed.mode != 'RGBA':
            processed = processed.convert('RGBA')

        if processed.size != TARGET_SIZE:
            processed = processed.resize(TARGET_SIZE, Image.LANCZOS)

        if apply_smooth:
            processed = smooth_icon(processed)

        # Scale both up for preview
        preview_size = (256, 256)
        original_preview = original.resize(preview_size, Image.NEAREST)
        processed_preview = processed.resize(preview_size, Image.NEAREST)

        # Create side-by-side
        combined = Image.new('RGBA', (preview_size[0] * 2 + 20, preview_size[1] + 40), (40, 40, 40, 255))
        combined.paste(original_preview, (0, 40))
        combined.paste(processed_preview, (preview_size[0] + 20, 40))

        # Add labels (requires PIL ImageDraw)
        try:
            from PIL import ImageDraw
            draw = ImageDraw.Draw(combined)
            draw.text((10, 10), f"Original ({original.size[0]}x{original.size[1]})", fill=(255, 255, 255))
            draw.text((preview_size[0] + 30, 10), f"Processed (64x64)", fill=(255, 255, 255))
        except:
            pass

        combined.show()
        return True

    except Exception as e:
        print(f"Preview error: {e}")
        return False


def main():
    args = sys.argv[1:]
    apply_smooth = "--smooth" in args
    preview_mode = "--preview" in args
    backup_mode = "--backup" in args

    print("=" * 60)
    print("FORGE ICON NORMALIZER")
    print("=" * 60)
    print(f"Target size: {TARGET_SIZE[0]}x{TARGET_SIZE[1]}")
    print(f"Smoothing: {'ON' if apply_smooth else 'OFF'}")
    print(f"Mode: {'PREVIEW' if preview_mode else 'PROCESS'}")
    if backup_mode:
        print(f"Backup dir: {BACKUP_DIR}")
    print("=" * 60)

    # Collect all icons
    all_icons = []
    for folder in ICON_FOLDERS:
        if folder.exists():
            icons = list(folder.glob("*.png"))
            all_icons.extend(icons)
            print(f"Found {len(icons)} icons in {folder.name}/")

    if not all_icons:
        print("No icons found!")
        return

    print(f"\nTotal: {len(all_icons)} icons")
    print("-" * 60)

    # Preview mode - just show one example
    if preview_mode:
        # Find a 256x256 icon to preview
        for icon in all_icons:
            img = Image.open(icon)
            if img.size == (256, 256):
                print(f"Previewing: {icon.name}")
                preview_icon(icon, apply_smooth)
                return
        print("No 256x256 icons found for preview")
        return

    # Process all icons
    stats = {
        "resized": 0,
        "smoothed": 0,
        "skipped": 0,
        "errors": 0
    }

    for icon in all_icons:
        result = process_icon(icon, apply_smooth, backup_mode)

        if result["error"]:
            print(f"  ERROR: {result['file']} - {result['error']}")
            stats["errors"] += 1
        elif "resized" in result["action"]:
            print(f"  Resized: {result['file']} ({result['original_size'][0]}x{result['original_size'][1]} -> 64x64)")
            stats["resized"] += 1
        elif result["action"] == "smoothed":
            stats["smoothed"] += 1
        elif result["action"] == "already_correct":
            stats["skipped"] += 1

    # Summary
    print("-" * 60)
    print("SUMMARY:")
    print(f"  Resized: {stats['resized']}")
    print(f"  Smoothed only: {stats['smoothed']}")
    print(f"  Already 64x64: {stats['skipped']}")
    print(f"  Errors: {stats['errors']}")
    print("=" * 60)

    if stats["resized"] > 0 or stats["smoothed"] > 0:
        print("\nDone! Icons have been normalized.")
        print("NOTE: You may need to reimport textures in Godot (Project > Reload Current Project)")


if __name__ == "__main__":
    main()
