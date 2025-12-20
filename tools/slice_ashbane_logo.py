#!/usr/bin/env python3
"""
Slice the Ashbane logo composite image into separate assets.
"""

from PIL import Image
import os

def slice_logo(source_path, output_dir):
    """Slice the composite logo image into 3 separate logos."""

    # Load the source image
    img = Image.open(source_path)
    width, height = img.size
    print(f"Source image: {width}x{height}")

    # The image appears to be laid out as:
    # Top row: [icon with padding] [full logo]
    # Bottom row: [mono logo centered]

    # Calculate approximate regions based on the layout
    # Top half contains 2 images side by side
    # Bottom half contains 1 centered image

    top_height = height // 2
    bottom_height = height - top_height

    # Top-left: Icon version (with dark gray background)
    # Appears to be roughly left 40% of top half
    icon_region = img.crop((0, 0, width // 2, top_height))

    # Top-right: Full hero version (black background with embers)
    full_region = img.crop((width // 2, 0, width, top_height))

    # Bottom: Mono version (white background)
    mono_region = img.crop((0, top_height, width, height))

    # Create output directories
    godot_branding = os.path.join(output_dir, "assets", "branding")
    backend_logo = os.path.join(output_dir, "backend", "static", "logo")
    backend_icons = os.path.join(output_dir, "backend", "static", "icons")

    os.makedirs(godot_branding, exist_ok=True)
    os.makedirs(backend_logo, exist_ok=True)
    os.makedirs(backend_icons, exist_ok=True)

    # Save the sliced images

    # Icon version - trim and save at multiple sizes
    icon_trimmed = trim_transparent_or_dark(icon_region)
    icon_path = os.path.join(godot_branding, "ashbane-icon.png")
    icon_trimmed.save(icon_path)
    print(f"Saved: {icon_path}")

    # Also save icon sizes for various uses
    for size in [256, 128, 64, 32, 16]:
        icon_resized = icon_trimmed.resize((size, size), Image.Resampling.LANCZOS)
        icon_size_path = os.path.join(godot_branding, f"ashbane-icon-{size}.png")
        icon_resized.save(icon_size_path)
        print(f"Saved: {icon_size_path}")

    # Full hero version
    full_path = os.path.join(godot_branding, "ashbane-logo-full.png")
    full_region.save(full_path)
    print(f"Saved: {full_path}")

    # Mono version
    mono_path = os.path.join(godot_branding, "ashbane-logo-mono.png")
    mono_region.save(mono_path)
    print(f"Saved: {mono_path}")

    # Copy to backend as well
    icon_trimmed.save(os.path.join(backend_logo, "ashbane-icon.png"))
    full_region.save(os.path.join(backend_logo, "ashbane-logo-full.png"))
    mono_region.save(os.path.join(backend_logo, "ashbane-logo-mono.png"))
    print("Copied to backend/static/logo/")

    # Create favicon sizes for web
    for size in [180, 32, 16]:
        favicon = icon_trimmed.resize((size, size), Image.Resampling.LANCZOS)
        if size == 180:
            favicon.save(os.path.join(backend_logo, "apple-touch-icon.png"))
        elif size == 32:
            favicon.save(os.path.join(backend_logo, "favicon-32x32.png"))
        elif size == 16:
            favicon.save(os.path.join(backend_logo, "favicon-16x16.png"))
    print("Created favicon sizes")

    # Update Godot project icon
    godot_icon_path = os.path.join(output_dir, "icon.png")
    icon_256 = icon_trimmed.resize((256, 256), Image.Resampling.LANCZOS)
    icon_256.save(godot_icon_path)
    print(f"Updated Godot icon: {godot_icon_path}")

    print("\nDone! Logo assets created successfully.")

def trim_transparent_or_dark(img):
    """Trim dark/transparent edges from an image."""
    # Convert to RGBA if not already
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Get the bounding box of non-dark content
    # We'll consider pixels with brightness > 30 as content
    pixels = img.load()
    width, height = img.size

    min_x, min_y = width, height
    max_x, max_y = 0, 0

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            # Check if pixel is "content" (not too dark and not transparent)
            brightness = (r + g + b) / 3
            if a > 128 and brightness > 25:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)

    # Add some padding
    padding = 10
    min_x = max(0, min_x - padding)
    min_y = max(0, min_y - padding)
    max_x = min(width, max_x + padding)
    max_y = min(height, max_y + padding)

    # Make it square (use the larger dimension)
    crop_width = max_x - min_x
    crop_height = max_y - min_y
    size = max(crop_width, crop_height)

    # Center the content in the square
    center_x = (min_x + max_x) // 2
    center_y = (min_y + max_y) // 2

    new_min_x = max(0, center_x - size // 2)
    new_min_y = max(0, center_y - size // 2)
    new_max_x = min(width, new_min_x + size)
    new_max_y = min(height, new_min_y + size)

    return img.crop((new_min_x, new_min_y, new_max_x, new_max_y))

if __name__ == "__main__":
    import sys

    # Default paths
    source = r"C:\Users\kevin\OneDrive\pictures\Screenshots\ChatGPT Image Dec 16, 2025, 11_45_48 PM.png"
    output = r"C:\Users\kevin\OneDrive\godot-combat-game-master"

    if len(sys.argv) > 1:
        source = sys.argv[1]
    if len(sys.argv) > 2:
        output = sys.argv[2]

    slice_logo(source, output)
