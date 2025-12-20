#!/usr/bin/env python3
"""
Convert provider SVG icons to PNG format for Godot compatibility.

Godot's HTTPRequest can't load SVGs from URLs, so we need PNG versions
of all provider icons that get served at /static/icons/{provider}.png

Usage:
    pip install cairosvg pillow
    python tools/convert_provider_icons.py

This will convert all SVG files in static/icons/ to 64x64 PNGs.
"""

import os
import sys
from pathlib import Path

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

ICONS_DIR = Path(__file__).parent.parent / "static" / "icons"
OUTPUT_SIZE = 64  # 64x64 pixels


def convert_svg_to_png(svg_path: Path, png_path: Path, size: int = OUTPUT_SIZE):
    """Convert a single SVG to PNG using cairosvg."""
    try:
        import cairosvg
        cairosvg.svg2png(
            url=str(svg_path),
            write_to=str(png_path),
            output_width=size,
            output_height=size
        )
        return True
    except ImportError:
        print("ERROR: cairosvg not installed. Run: pip install cairosvg")
        return False
    except Exception as e:
        print(f"ERROR converting {svg_path.name}: {e}")
        return False


def main():
    """Convert all SVG provider icons to PNG."""
    if not ICONS_DIR.exists():
        print(f"ERROR: Icons directory not found: {ICONS_DIR}")
        sys.exit(1)

    # Provider icons that need conversion (exclude utility SVGs)
    provider_svgs = [
        "steam.svg",
        "battlenet.svg",
        "xbox.svg",
        "playstation.svg",
        "psn.svg",
        "discord.svg",
        "github.svg",
        "epic.svg",
        "gog.svg",
        "facebook.svg",
        "roblox.svg",
        "Ashbane.svg",
    ]

    converted = 0
    skipped = 0
    failed = 0

    for svg_name in provider_svgs:
        svg_path = ICONS_DIR / svg_name
        png_path = ICONS_DIR / svg_name.replace(".svg", ".png")

        if not svg_path.exists():
            print(f"SKIP: {svg_name} (not found)")
            skipped += 1
            continue

        if png_path.exists():
            # Check if SVG is newer than PNG
            if svg_path.stat().st_mtime <= png_path.stat().st_mtime:
                print(f"SKIP: {svg_name} (PNG up to date)")
                skipped += 1
                continue

        print(f"Converting: {svg_name} -> {png_path.name}")
        if convert_svg_to_png(svg_path, png_path):
            converted += 1
        else:
            failed += 1

    print(f"\nDone: {converted} converted, {skipped} skipped, {failed} failed")

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
