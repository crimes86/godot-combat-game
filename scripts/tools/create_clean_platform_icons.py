"""
Create clean platform icons with transparent backgrounds
Simple solid color icons on transparent background
"""
from PIL import Image, ImageDraw
import os

def create_battlenet_icon(output_path, size=64):
    """Create a simple Blizzard/Battle.net icon"""
    # Create transparent image
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Blizzard blue color
    color = (0, 120, 215, 255)  # Blizzard blue

    # Draw a simple hexagon shape (rough approximation of Blizzard logo)
    center = size // 2
    radius = size // 2 - 4

    # Draw filled circle as simple icon
    draw.ellipse([center - radius, center - radius,
                  center + radius, center + radius],
                 fill=color)

    # Save
    img.save(output_path, "PNG")
    print(f"Created: {output_path}")

def create_xbox_icon(output_path, size=64):
    """Create a simple Xbox icon"""
    # Create transparent image
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Xbox green color
    color = (16, 124, 16, 255)  # Xbox green

    # Draw a simple X shape
    center = size // 2
    radius = size // 2 - 4

    # Draw filled circle as base
    draw.ellipse([center - radius, center - radius,
                  center + radius, center + radius],
                 fill=color)

    # Save
    img.save(output_path, "PNG")
    print(f"Created: {output_path}")

def main():
    icons_dir = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\ui\icons"

    # Create clean versions
    create_battlenet_icon(os.path.join(icons_dir, "battlenet.png"))
    create_xbox_icon(os.path.join(icons_dir, "xbox.png"))

    print("\nClean platform icons created!")

if __name__ == "__main__":
    main()
