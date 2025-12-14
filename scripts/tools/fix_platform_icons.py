"""
Fix platform icons - remove white backgrounds and make them transparent
"""
from PIL import Image
import os

def remove_white_background(image_path):
    """Remove white/light backgrounds from PNG and make transparent"""
    print(f"Processing: {image_path}")

    # Load image
    img = Image.open(image_path).convert("RGBA")

    # Get pixel data
    data = img.getdata()

    new_data = []
    for item in data:
        # If pixel is very light (near white), make it transparent
        # Threshold: if R, G, B are all > 240, it's considered white/light edge
        if item[0] > 240 and item[1] > 240 and item[2] > 240:
            # Make fully transparent
            new_data.append((255, 255, 255, 0))
        else:
            # Keep original pixel
            new_data.append(item)

    # Update image data
    img.putdata(new_data)

    # Save back
    img.save(image_path, "PNG")
    print(f"  Saved with transparent background")

def main():
    # Path to icons
    icons_dir = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\ui\icons"

    # Fix battlenet and xbox icons
    icons_to_fix = ["battlenet.png", "xbox.png"]

    for icon_name in icons_to_fix:
        icon_path = os.path.join(icons_dir, icon_name)
        if os.path.exists(icon_path):
            remove_white_background(icon_path)
        else:
            print(f"Warning: {icon_path} not found")

    print("\nPlatform icons fixed!")

if __name__ == "__main__":
    main()
