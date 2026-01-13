"""
Convert green/yellow buds on dead trees to black/dark to make them look truly dead.
"""

from PIL import Image
import os

DREADLAND_PATH = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\environment\dreadland"

# Trees that have green buds that need to be darkened
TREES_WITH_BUDS = [
    "dead_tree_lpc_24.png",
    "dead_tree_lpc_25.png",
    "dead_tree_lpc_28.png",
    "dead_tree_lpc_35.png",
    "dead_tree_lpc_37.png",
]

def is_green_or_yellow_bud(r, g, b, a):
    """Check if a pixel is a green/yellow bud color."""
    if a < 128:  # Skip transparent pixels
        return False

    # Green buds: green is dominant or close to dominant
    # Yellow-green buds: high green and red, low blue

    # Check for greenish pixels (buds are typically bright green/yellow-green)
    is_greenish = (
        g > 80 and  # Has significant green
        g > b and   # Green > Blue
        (g > r * 0.8 or (r > 100 and g > 100 and b < 80))  # Green dominant OR yellow-ish
    )

    # Also catch yellow buds
    is_yellowish = (
        r > 120 and g > 120 and b < 100 and  # Yellow-ish
        abs(r - g) < 60  # Red and green are close
    )

    return is_greenish or is_yellowish

def darken_buds(image_path):
    """Convert green/yellow buds to dark/black."""
    img = Image.open(image_path).convert("RGBA")
    pixels = img.load()
    width, height = img.size

    changed_count = 0

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            if is_green_or_yellow_bud(r, g, b, a):
                # Convert to very dark brown/black (like dead twigs)
                # Keep some variation based on original brightness
                brightness = (r + g + b) / 3
                dark_value = int(brightness * 0.15)  # Make very dark
                dark_value = max(10, min(40, dark_value))  # Clamp to 10-40

                pixels[x, y] = (dark_value, dark_value - 2, dark_value - 5, a)
                changed_count += 1

    if changed_count > 0:
        img.save(image_path)
        print(f"  Modified {changed_count} pixels in {os.path.basename(image_path)}")
    else:
        print(f"  No buds found in {os.path.basename(image_path)}")

    return changed_count

def main():
    print("Converting green buds to black on dead trees...\n")

    total_changed = 0

    for tree_file in TREES_WITH_BUDS:
        tree_path = os.path.join(DREADLAND_PATH, tree_file)
        if os.path.exists(tree_path):
            changed = darken_buds(tree_path)
            total_changed += changed
        else:
            print(f"  WARNING: {tree_file} not found!")

    print(f"\nDone! Modified {total_changed} total pixels across {len(TREES_WITH_BUDS)} trees.")

if __name__ == "__main__":
    main()
