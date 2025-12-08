"""
Fix weapon orientations - all should point up and to the right
"""

from PIL import Image
from pathlib import Path

FORGED_DIR = Path(__file__).parent

# Weapons that need flipping to point upper-right
FIXES = {
    # Katanas: currently pointing down-left, need horizontal flip
    "weapons/mortal_blade.png": "flip_horizontal",
    "weapons/hand_of_malenia.png": "flip_horizontal",

    # Spear and Nail: currently pointing down-right, need 180° rotation
    "weapons/gyoubu_spear.png": "rotate_180",
    "weapons/pure_nail.png": "rotate_180",
}

def fix_orientation(img_path, fix_type):
    """Apply orientation fix"""
    img = Image.open(img_path)

    if fix_type == "flip_horizontal":
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    elif fix_type == "flip_vertical":
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    elif fix_type == "rotate_180":
        img = img.rotate(180)
    elif fix_type == "flip_both":
        img = img.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM)

    return img

def main():
    for rel_path, fix_type in FIXES.items():
        full_path = FORGED_DIR / rel_path
        if not full_path.exists():
            print(f"Not found: {rel_path}")
            continue

        print(f"Fixing {rel_path} with {fix_type}...")
        img = fix_orientation(full_path, fix_type)
        img.save(full_path)
        print(f"  -> Done")

    # Regenerate preview
    print("\nRegenerating preview grid...")
    from align_icons import generate_preview_grid
    generate_preview_grid()

if __name__ == '__main__':
    main()
