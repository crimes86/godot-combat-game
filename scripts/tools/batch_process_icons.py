#!/usr/bin/env python3
"""
Batch process all forged icons: scale up content, then enhance.

Usage:
    python batch_process_icons.py                    # Process all icons
    python batch_process_icons.py --scale-only       # Just scale content (no enhance)
    python batch_process_icons.py --enhance-only     # Just enhance (no scale)
    python batch_process_icons.py --dry-run          # Show what would be processed
    python batch_process_icons.py --scale 1.5        # Custom scale factor (default: 2.0)

Order of operations:
1. Scale up icon content within 64x64 canvas (makes small sprites fill more space)
2. Run xBRZ enhancement to create 256x256 versions
"""

import sys
import argparse
from pathlib import Path

# Add tools dir to path for imports
SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from scale_icon_content import scale_icon_content, get_content_bounds
from PIL import Image

# Paths
FORGED_ICONS_DIR = PROJECT_ROOT / "assets" / "icons" / "forged"
ENHANCED_ICONS_DIR = PROJECT_ROOT / "assets" / "icons" / "enhanced"

# Categories to process
CATEGORIES = ["weapons", "armor", "shields", "accessories", "capes", "tools"]

# Skip these files
SKIP_PATTERNS = ["backup", "preview", "_old", "_bak"]


def should_skip(path: Path) -> bool:
    """Check if file should be skipped."""
    path_str = str(path).lower()
    return any(pattern in path_str for pattern in SKIP_PATTERNS)


def needs_scaling(icon_path: Path, min_content_ratio: float = 0.5) -> bool:
    """
    Check if icon content is too small and needs scaling.

    Returns True if content fills less than min_content_ratio of the canvas.
    """
    try:
        img = Image.open(icon_path).convert('RGBA')
        canvas_size = img.size[0]  # Assume square

        bounds = get_content_bounds(img)
        if not bounds:
            return False

        min_x, min_y, max_x, max_y = bounds
        content_width = max_x - min_x
        content_height = max_y - min_y

        # Calculate content area ratio
        content_area = content_width * content_height
        canvas_area = canvas_size * canvas_size
        ratio = content_area / canvas_area

        return ratio < min_content_ratio
    except Exception:
        return False


def get_content_fill_ratio(icon_path: Path) -> float:
    """Get the ratio of content area to canvas area."""
    try:
        img = Image.open(icon_path).convert('RGBA')
        canvas_size = img.size[0]

        bounds = get_content_bounds(img)
        if not bounds:
            return 0.0

        min_x, min_y, max_x, max_y = bounds
        content_width = max_x - min_x
        content_height = max_y - min_y

        content_area = content_width * content_height
        canvas_area = canvas_size * canvas_size
        return content_area / canvas_area
    except Exception:
        return 0.0


def collect_icons() -> list:
    """Collect all forged icons to process."""
    icons = []

    for category in CATEGORIES:
        cat_dir = FORGED_ICONS_DIR / category
        if not cat_dir.exists():
            continue

        for icon_path in sorted(cat_dir.glob("*.png")):
            if should_skip(icon_path):
                continue
            icons.append((category, icon_path))

    return icons


def run_scale_pass(icons: list, scale_factor: float, dry_run: bool = False,
                   force: bool = False, min_ratio: float = 0.4) -> dict:
    """
    Scale up icon content for icons that need it.

    Args:
        icons: List of (category, path) tuples
        scale_factor: How much to scale content
        dry_run: If True, don't actually modify files
        force: If True, scale all icons regardless of current size
        min_ratio: Only scale icons with content ratio below this
    """
    stats = {"scaled": 0, "skipped": 0, "errors": []}

    print(f"\n{'='*60}")
    print(f"PHASE 1: SCALE UP CONTENT (factor: {scale_factor}x)")
    print(f"{'='*60}")

    for category, icon_path in icons:
        try:
            ratio = get_content_fill_ratio(icon_path)

            if not force and ratio >= min_ratio:
                print(f"  SKIP: {category}/{icon_path.name} (fill ratio {ratio:.1%} >= {min_ratio:.0%})")
                stats["skipped"] += 1
                continue

            if dry_run:
                print(f"  WOULD SCALE: {category}/{icon_path.name} (fill ratio {ratio:.1%})")
            else:
                scale_icon_content(icon_path, scale_factor)
                new_ratio = get_content_fill_ratio(icon_path)
                print(f"  SCALED: {category}/{icon_path.name} ({ratio:.1%} -> {new_ratio:.1%})")

            stats["scaled"] += 1

        except Exception as e:
            stats["errors"].append((icon_path, str(e)))
            print(f"  ERROR: {category}/{icon_path.name} - {e}")

    return stats


def run_enhance_pass(icons: list, dry_run: bool = False) -> dict:
    """
    Run xBRZ enhancement on all icons.
    """
    stats = {"enhanced": 0, "skipped": 0, "errors": []}

    print(f"\n{'='*60}")
    print(f"PHASE 2: ENHANCE TO 256x256")
    print(f"{'='*60}")

    # Import icon_enhancer
    try:
        from icon_enhancer import upscale_image, FRAME_SIZE
    except ImportError:
        print("ERROR: Could not import icon_enhancer.py from tools/")
        print("Make sure tools/icon_enhancer.py exists")
        return stats

    for category, icon_path in icons:
        try:
            img = Image.open(icon_path).convert('RGBA')

            # Validate size
            if img.size != (FRAME_SIZE, FRAME_SIZE):
                print(f"  SKIP: {category}/{icon_path.name} (size {img.size}, expected {FRAME_SIZE}x{FRAME_SIZE})")
                stats["skipped"] += 1
                continue

            # Output path
            out_dir = ENHANCED_ICONS_DIR / "forged" / category
            out_path = out_dir / icon_path.name

            if dry_run:
                print(f"  WOULD ENHANCE: {category}/{icon_path.name}")
            else:
                # Upscale
                enhanced = upscale_image(img, "auto")

                # Save
                out_dir.mkdir(parents=True, exist_ok=True)
                enhanced.save(out_path, "PNG")
                print(f"  ENHANCED: {category}/{icon_path.name} -> {enhanced.size[0]}x{enhanced.size[1]}")

            stats["enhanced"] += 1

        except Exception as e:
            stats["errors"].append((icon_path, str(e)))
            print(f"  ERROR: {category}/{icon_path.name} - {e}")

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Batch process forged icons: scale up content, then enhance",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument("--scale-only", action="store_true",
                        help="Only run scale pass (no enhancement)")
    parser.add_argument("--enhance-only", action="store_true",
                        help="Only run enhance pass (no scaling)")
    parser.add_argument("--scale", type=float, default=2.0,
                        help="Scale factor for content (default: 2.0)")
    parser.add_argument("--min-ratio", type=float, default=0.4,
                        help="Only scale icons with fill ratio below this (default: 0.4)")
    parser.add_argument("--force-scale", action="store_true",
                        help="Scale all icons regardless of current size")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be processed without modifying files")
    parser.add_argument("--list", action="store_true",
                        help="Just list icons and their fill ratios")

    args = parser.parse_args()

    # Collect icons
    icons = collect_icons()
    print(f"Found {len(icons)} forged icons to process")

    if args.list:
        print(f"\n{'Icon':<50} {'Fill Ratio':<12} {'Needs Scale'}")
        print("-" * 70)
        for category, icon_path in icons:
            ratio = get_content_fill_ratio(icon_path)
            needs = "YES" if ratio < args.min_ratio else "no"
            print(f"{category}/{icon_path.name:<40} {ratio:>10.1%}   {needs}")
        return

    if not icons:
        print("No icons found to process")
        return

    total_stats = {
        "scaled": 0, "scale_skipped": 0, "scale_errors": [],
        "enhanced": 0, "enhance_skipped": 0, "enhance_errors": []
    }

    # Phase 1: Scale up content
    if not args.enhance_only:
        scale_stats = run_scale_pass(
            icons, args.scale, args.dry_run,
            force=args.force_scale, min_ratio=args.min_ratio
        )
        total_stats["scaled"] = scale_stats["scaled"]
        total_stats["scale_skipped"] = scale_stats["skipped"]
        total_stats["scale_errors"] = scale_stats["errors"]

    # Phase 2: Enhance to 256x256
    if not args.scale_only:
        enhance_stats = run_enhance_pass(icons, args.dry_run)
        total_stats["enhanced"] = enhance_stats["enhanced"]
        total_stats["enhance_skipped"] = enhance_stats["skipped"]
        total_stats["enhance_errors"] = enhance_stats["errors"]

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")

    if not args.enhance_only:
        print(f"Scale pass:   {total_stats['scaled']} scaled, {total_stats['scale_skipped']} skipped, {len(total_stats['scale_errors'])} errors")

    if not args.scale_only:
        print(f"Enhance pass: {total_stats['enhanced']} enhanced, {total_stats['enhance_skipped']} skipped, {len(total_stats['enhance_errors'])} errors")

    all_errors = total_stats.get("scale_errors", []) + total_stats.get("enhance_errors", [])
    if all_errors:
        print(f"\nErrors:")
        for path, error in all_errors:
            print(f"  {path}: {error}")

    if not args.dry_run:
        print(f"\nEnhanced icons saved to: {ENHANCED_ICONS_DIR}")


if __name__ == "__main__":
    main()
