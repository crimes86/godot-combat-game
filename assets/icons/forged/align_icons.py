"""
Icon Alignment Script for Forge Shop Grid
Centers all icons in their canvas and rotates horizontal weapons to 45°
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math

ICON_SIZE = 64
FORGED_DIR = Path(__file__).parent

# Items that need rotation from horizontal to diagonal
ROTATE_ITEMS = {
    "mortal_blade.png": 45,
    "hand_of_malenia.png": 45,
}

def get_content_bbox(img):
    """Get bounding box of non-transparent pixels"""
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    alpha = img.split()[3]
    return alpha.getbbox()

def center_content(img):
    """Center the non-transparent content in the canvas"""
    bbox = get_content_bbox(img)
    if not bbox:
        return img

    # Crop to content
    content = img.crop(bbox)
    content_w, content_h = content.size

    # Calculate centered position
    new_x = (ICON_SIZE - content_w) // 2
    new_y = (ICON_SIZE - content_h) // 2

    # Create new canvas and paste centered
    new_img = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    new_img.paste(content, (new_x, new_y))

    return new_img

def rotate_and_center(img, angle):
    """Rotate image by angle degrees and re-center"""
    # Rotate with expand to avoid clipping
    rotated = img.rotate(angle, expand=True, resample=Image.BICUBIC)

    # Now fit it back into 64x64 centered
    bbox = get_content_bbox(rotated)
    if not bbox:
        return img

    content = rotated.crop(bbox)
    content_w, content_h = content.size

    # Scale down if too big
    max_dim = ICON_SIZE - 8  # 4px padding on each side
    if content_w > max_dim or content_h > max_dim:
        scale = max_dim / max(content_w, content_h)
        new_size = (int(content_w * scale), int(content_h * scale))
        content = content.resize(new_size, Image.LANCZOS)
        content_w, content_h = content.size

    # Center in new canvas
    new_x = (ICON_SIZE - content_w) // 2
    new_y = (ICON_SIZE - content_h) // 2

    new_img = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    new_img.paste(content, (new_x, new_y))

    return new_img

def analyze_icon(img_path):
    """Analyze icon positioning and return stats"""
    img = Image.open(img_path)
    bbox = get_content_bbox(img)
    if not bbox:
        return None

    x1, y1, x2, y2 = bbox
    content_w = x2 - x1
    content_h = y2 - y1
    center_x = x1 + content_w // 2
    center_y = y1 + content_h // 2

    # How far from canvas center?
    offset_x = center_x - ICON_SIZE // 2
    offset_y = center_y - ICON_SIZE // 2

    return {
        'bbox': bbox,
        'content_size': (content_w, content_h),
        'content_center': (center_x, center_y),
        'offset': (offset_x, offset_y),
        'needs_centering': abs(offset_x) > 2 or abs(offset_y) > 2
    }

def process_all_icons(dry_run=True):
    """Process all icons - analyze and optionally fix alignment"""
    categories = ['weapons', 'armor', 'shields', 'accessories']
    results = []

    for category in categories:
        cat_dir = FORGED_DIR / category
        if not cat_dir.exists():
            continue

        for icon_path in cat_dir.glob('*.png'):
            stats = analyze_icon(icon_path)
            if not stats:
                continue

            needs_rotation = icon_path.name in ROTATE_ITEMS

            results.append({
                'path': icon_path,
                'category': category,
                'name': icon_path.stem,
                'stats': stats,
                'needs_rotation': needs_rotation,
                'rotation_angle': ROTATE_ITEMS.get(icon_path.name, 0)
            })

            print(f"\n{category}/{icon_path.name}:")
            print(f"  Content size: {stats['content_size']}")
            print(f"  Offset from center: {stats['offset']}")
            print(f"  Needs centering: {stats['needs_centering']}")
            if needs_rotation:
                print(f"  Needs rotation: {ROTATE_ITEMS[icon_path.name]}°")

            if not dry_run and (stats['needs_centering'] or needs_rotation):
                img = Image.open(icon_path)

                if needs_rotation:
                    img = rotate_and_center(img, ROTATE_ITEMS[icon_path.name])
                else:
                    img = center_content(img)

                # Save backup
                backup_dir = FORGED_DIR / 'backups' / category
                backup_dir.mkdir(parents=True, exist_ok=True)
                backup_path = backup_dir / icon_path.name
                if not backup_path.exists():
                    Image.open(icon_path).save(backup_path)

                img.save(icon_path)
                print(f"  -> FIXED")

    return results

def generate_preview_grid(output_path=None):
    """Generate a preview grid of all icons"""
    categories = ['weapons', 'armor', 'shields', 'accessories']
    all_icons = []

    for category in categories:
        cat_dir = FORGED_DIR / category
        if not cat_dir.exists():
            continue
        for icon_path in sorted(cat_dir.glob('*.png')):
            all_icons.append((category, icon_path))

    # Grid layout
    cols = 6
    rows = math.ceil(len(all_icons) / cols)
    cell_size = 80
    padding = 8

    grid_w = cols * cell_size
    grid_h = rows * cell_size + 60  # Extra for title

    grid = Image.new('RGBA', (grid_w, grid_h), (30, 30, 35, 255))
    draw = ImageDraw.Draw(grid)

    # Title
    draw.text((grid_w // 2, 15), "FORGE ITEMS PREVIEW", fill=(100, 200, 255), anchor="mt")
    draw.text((grid_w // 2, 35), f"{len(all_icons)} items", fill=(150, 150, 150), anchor="mt")

    # Draw icons
    for idx, (category, icon_path) in enumerate(all_icons):
        row = idx // cols
        col = idx % cols

        x = col * cell_size + (cell_size - ICON_SIZE) // 2
        y = row * cell_size + 60 + (cell_size - ICON_SIZE) // 2

        # Cell background
        cell_x = col * cell_size
        cell_y = row * cell_size + 60
        draw.rectangle([cell_x + 2, cell_y + 2, cell_x + cell_size - 2, cell_y + cell_size - 2],
                      fill=(45, 45, 50), outline=(60, 60, 65))

        # Icon
        icon = Image.open(icon_path)
        grid.paste(icon, (x, y), icon)

        # Label
        name = icon_path.stem.replace('_', ' ').title()
        if len(name) > 12:
            name = name[:11] + '...'
        draw.text((cell_x + cell_size // 2, cell_y + cell_size - 6),
                 name, fill=(180, 180, 180), anchor="mb")

    if output_path is None:
        output_path = FORGED_DIR / 'preview_grid.png'

    grid.save(output_path)
    print(f"\nPreview saved to: {output_path}")
    return output_path

if __name__ == '__main__':
    import sys

    if len(sys.argv) > 1 and sys.argv[1] == '--fix':
        print("=== FIXING ICONS ===")
        process_all_icons(dry_run=False)
        print("\n=== GENERATING PREVIEW ===")
        generate_preview_grid()
    else:
        print("=== ANALYSIS MODE (dry run) ===")
        print("Run with --fix to apply changes\n")
        process_all_icons(dry_run=True)
        print("\n\nTo apply fixes, run: python align_icons.py --fix")
