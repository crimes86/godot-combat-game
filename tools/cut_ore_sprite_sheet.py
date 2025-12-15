#!/usr/bin/env python3
"""
Cut ore.png sprite sheet into separate assets:
- Forge animation frames (for trading hub)
- Ore/rock sprites (for harvestable rocks - later use)
"""

from PIL import Image
import os

# Input/output paths
INPUT_FILE = "C:/Users/kevin/Downloads/ore.png"
OUTPUT_DIR = "C:/Users/kevin/OneDrive/godot-combat-game-master/assets"

def analyze_sheet(img):
    """Analyze the sprite sheet to find content boundaries"""
    print(f"Sheet size: {img.size}")
    print(f"Mode: {img.mode}")

    # Find non-transparent bounding boxes for each major section
    width, height = img.size

    # Sample the image to find where forges are
    # Looking at the bottom section for forge sprites
    print("\nAnalyzing bottom section for forges...")

    # The forges appear to be in the bottom ~130 pixels
    # spanning roughly 4 frames across ~260 pixels wide

def extract_forges(img, output_dir):
    """Extract the 4 forge animation frames from the bottom of the sheet"""
    forge_dir = os.path.join(output_dir, "environment", "forge")
    os.makedirs(forge_dir, exist_ok=True)

    # The forges are at y=384 to y=512 (128 pixels tall)
    # Each forge is 64 pixels wide, 4 forges total
    # They start at x=0

    forge_y_start = 400  # Start of forge brick structure
    forge_y_end = 512    # Bottom of sheet
    forge_width = 64
    forge_height = forge_y_end - forge_y_start  # 112 pixels

    frames = []
    for i in range(4):
        x_start = i * forge_width

        # Crop each forge frame - don't trim, keep consistent size
        frame = img.crop((x_start, forge_y_start, x_start + forge_width, forge_y_end))

        frame_path = os.path.join(forge_dir, f"forge_frame_{i}.png")
        frame.save(frame_path)
        frames.append(frame)
        print(f"Saved forge frame {i}: {frame.size}")

    # Also create a sprite sheet for Godot AnimatedSprite2D
    # Horizontal strip format
    if frames:
        # All frames should be same size now
        frame_w = forge_width
        frame_h = forge_height

        # Create horizontal strip
        strip = Image.new('RGBA', (frame_w * 4, frame_h), (0, 0, 0, 0))
        for i, frame in enumerate(frames):
            strip.paste(frame, (i * frame_w, 0))

        strip_path = os.path.join(forge_dir, "forge_spritesheet.png")
        strip.save(strip_path)
        print(f"\nSaved forge sprite sheet: {strip.size}")
        print(f"Frame size for Godot: {frame_w}x{frame_h}")
        print(f"Use 4 columns, 1 row in AnimatedSprite2D")

    return forge_dir

def extract_ores(img, output_dir):
    """Extract ore/rock sprites for later use as harvestable rocks"""
    ore_dir = os.path.join(output_dir, "environment", "ores")
    os.makedirs(ore_dir, exist_ok=True)

    # The ores/rocks are in the top portion of the sheet
    # Save the top section (everything above the forges) for later processing
    ore_section = img.crop((0, 0, 512, 350))
    ore_section.save(os.path.join(ore_dir, "ore_rocks_full.png"))
    print(f"\nSaved ore/rocks section for later: {ore_section.size}")

    # Also extract the individual ingot/nugget sprites (middle section)
    # These are around y=256-320
    ingots_section = img.crop((0, 256, 320, 350))
    ingots_section.save(os.path.join(ore_dir, "ingots_nuggets.png"))
    print(f"Saved ingots/nuggets section: {ingots_section.size}")

    return ore_dir

def main():
    print("=" * 60)
    print("ORE SPRITE SHEET CUTTER")
    print("=" * 60)

    # Load image
    img = Image.open(INPUT_FILE)
    print(f"\nLoaded: {INPUT_FILE}")
    analyze_sheet(img)

    # Extract forges
    print("\n" + "=" * 40)
    print("EXTRACTING FORGE FRAMES")
    print("=" * 40)
    forge_dir = extract_forges(img, OUTPUT_DIR)

    # Extract ores (for later)
    print("\n" + "=" * 40)
    print("EXTRACTING ORE SPRITES (for later)")
    print("=" * 40)
    ore_dir = extract_ores(img, OUTPUT_DIR)

    print("\n" + "=" * 60)
    print("COMPLETE!")
    print("=" * 60)
    print(f"\nForge frames saved to: {forge_dir}")
    print(f"Ore sprites saved to: {ore_dir}")
    print("\nNext steps:")
    print("1. Check forge_spritesheet.png for animation frames")
    print("2. Create AnimatedSprite2D in Godot with 4 frames")
    print("3. Add to TradingHub scene")

if __name__ == "__main__":
    main()
