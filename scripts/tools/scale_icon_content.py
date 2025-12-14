#!/usr/bin/env python3
"""
Scale up icon content within its canvas.

Usage:
    python scale_icon_content.py <icon_path> [scale_factor]

Examples:
    python scale_icon_content.py assets/icons/forged/armor/survivor_vest.png 2.0
    python scale_icon_content.py assets/icons/forged/armor/survivor_vest.png 1.5
"""

import sys
from pathlib import Path
from PIL import Image

def get_content_bounds(img):
    """Find bounding box of non-transparent content."""
    pixels = img.load()
    width, height = img.size

    min_x, min_y = width, height
    max_x, max_y = 0, 0

    for y in range(height):
        for x in range(width):
            pixel = pixels[x, y]
            # Check alpha channel (RGBA)
            if len(pixel) >= 4 and pixel[3] > 0:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    if max_x < min_x:
        return None  # No content found

    return (min_x, min_y, max_x + 1, max_y + 1)

def scale_icon_content(icon_path, scale_factor=2.0, output_path=None):
    """Scale up the content of an icon while keeping canvas size."""
    img = Image.open(icon_path).convert('RGBA')
    canvas_size = img.size[0]  # Assume square

    # Find content bounds
    bounds = get_content_bounds(img)
    if not bounds:
        print(f"No content found in {icon_path}")
        return

    min_x, min_y, max_x, max_y = bounds
    content_width = max_x - min_x
    content_height = max_y - min_y

    print(f"Original content bounds: ({min_x}, {min_y}) to ({max_x}, {max_y})")
    print(f"Content size: {content_width}x{content_height}")

    # Extract content
    content = img.crop(bounds)

    # Scale up content
    new_width = int(content_width * scale_factor)
    new_height = int(content_height * scale_factor)

    # Clamp to canvas size minus padding (4px on each side)
    max_content_size = canvas_size - 8
    if new_width > max_content_size or new_height > max_content_size:
        # Scale to fit within bounds
        fit_scale = min(max_content_size / new_width, max_content_size / new_height)
        new_width = int(new_width * fit_scale)
        new_height = int(new_height * fit_scale)
        print(f"Clamped to fit canvas: {new_width}x{new_height}")

    scaled_content = content.resize((new_width, new_height), Image.Resampling.LANCZOS)

    print(f"Scaled content size: {new_width}x{new_height}")

    # Create new canvas and center scaled content
    new_img = Image.new('RGBA', (canvas_size, canvas_size), (0, 0, 0, 0))
    paste_x = (canvas_size - new_width) // 2
    paste_y = (canvas_size - new_height) // 2

    new_img.paste(scaled_content, (paste_x, paste_y), scaled_content)

    # Save
    if output_path is None:
        output_path = icon_path  # Overwrite original

    new_img.save(output_path)
    print(f"Saved scaled icon to: {output_path}")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    icon_path = Path(sys.argv[1])
    scale_factor = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0

    if not icon_path.exists():
        print(f"Error: {icon_path} not found")
        sys.exit(1)

    scale_icon_content(icon_path, scale_factor)

if __name__ == "__main__":
    main()
