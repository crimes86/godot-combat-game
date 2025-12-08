"""
FORGED ICON STANDARDS
=====================
Baseline specification for shop/vendor grid display icons.

CANVAS SPECS:
- Size: 64x64 pixels
- Format: PNG with transparency (RGBA)
- Background: Transparent

ALIGNMENT RULES:
- All content CENTERED in canvas (equal padding on all sides)
- Minimum padding: 4px from edge

ORIENTATION BY CATEGORY:

  WEAPONS (swords, blades, spears):
    - Diagonal ~45° angle
    - Tip pointing UPPER-RIGHT
    - Handle at lower-left

  ARMOR (crowns, helmets, hats):
    - Upright orientation
    - Centered horizontally
    - Vertically centered (slight upward bias OK for "worn" feel)

  SHIELDS:
    - Upright orientation
    - Centered in canvas

  ACCESSORIES (fragments, chains, rings):
    - Natural orientation
    - Centered in canvas

USAGE:
  # Analyze icons (dry run)
  python icon_standards.py

  # Fix alignment issues
  python icon_standards.py --fix

  # Fix specific icon orientation (flip/rotate)
  python icon_standards.py --orient weapons/new_sword.png upper-right

  # Validate new icons against standards
  python icon_standards.py --validate

  # Generate preview grid
  python icon_standards.py --preview
"""

from PIL import Image, ImageDraw
from pathlib import Path
import math
import sys

ICON_SIZE = 64
MIN_PADDING = 4
FORGED_DIR = Path(__file__).parent

CATEGORIES = ['weapons', 'armor', 'shields', 'accessories', 'capes', 'tools']


def get_content_bbox(img):
    """Get bounding box of non-transparent pixels"""
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    alpha = img.split()[3]
    return alpha.getbbox()


def get_content_stats(img):
    """Analyze icon content positioning"""
    bbox = get_content_bbox(img)
    if not bbox:
        return None

    x1, y1, x2, y2 = bbox
    content_w = x2 - x1
    content_h = y2 - y1
    center_x = x1 + content_w // 2
    center_y = y1 + content_h // 2

    canvas_center = ICON_SIZE // 2
    offset_x = center_x - canvas_center
    offset_y = center_y - canvas_center

    return {
        'bbox': bbox,
        'size': (content_w, content_h),
        'center': (center_x, center_y),
        'offset': (offset_x, offset_y),
        'padding': {
            'left': x1,
            'top': y1,
            'right': ICON_SIZE - x2,
            'bottom': ICON_SIZE - y2
        }
    }


def center_content(img):
    """Center non-transparent content in canvas"""
    bbox = get_content_bbox(img)
    if not bbox:
        return img

    content = img.crop(bbox)
    content_w, content_h = content.size

    new_x = (ICON_SIZE - content_w) // 2
    new_y = (ICON_SIZE - content_h) // 2

    new_img = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    new_img.paste(content, (new_x, new_y))
    return new_img


def flip_horizontal(img):
    """Flip image horizontally"""
    return img.transpose(Image.FLIP_LEFT_RIGHT)


def flip_vertical(img):
    """Flip image vertically"""
    return img.transpose(Image.FLIP_TOP_BOTTOM)


def rotate_image(img, angle):
    """Rotate and re-center image"""
    rotated = img.rotate(angle, expand=True, resample=Image.BICUBIC)

    bbox = get_content_bbox(rotated)
    if not bbox:
        return img

    content = rotated.crop(bbox)
    content_w, content_h = content.size

    max_dim = ICON_SIZE - (MIN_PADDING * 2)
    if content_w > max_dim or content_h > max_dim:
        scale = max_dim / max(content_w, content_h)
        new_size = (int(content_w * scale), int(content_h * scale))
        content = content.resize(new_size, Image.LANCZOS)
        content_w, content_h = content.size

    new_x = (ICON_SIZE - content_w) // 2
    new_y = (ICON_SIZE - content_h) // 2

    new_img = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    new_img.paste(content, (new_x, new_y))
    return new_img


def is_centered(stats, tolerance=3):
    """Check if content is centered within tolerance"""
    if not stats:
        return False
    return abs(stats['offset'][0]) <= tolerance and abs(stats['offset'][1]) <= tolerance


def validate_icon(img_path):
    """Validate icon against standards, return issues list"""
    issues = []

    img = Image.open(img_path)

    # Check size
    if img.size != (ICON_SIZE, ICON_SIZE):
        issues.append(f"Wrong size: {img.size}, expected {ICON_SIZE}x{ICON_SIZE}")

    # Check mode
    if img.mode != 'RGBA':
        issues.append(f"Wrong mode: {img.mode}, expected RGBA")

    # Check centering
    stats = get_content_stats(img)
    if stats:
        if not is_centered(stats):
            issues.append(f"Not centered: offset {stats['offset']}")

        # Check padding
        for side, pad in stats['padding'].items():
            if pad < MIN_PADDING:
                issues.append(f"Insufficient {side} padding: {pad}px (min {MIN_PADDING}px)")

    return issues


def get_all_icons():
    """Get all icon paths organized by category"""
    icons = {}
    for category in CATEGORIES:
        cat_dir = FORGED_DIR / category
        if cat_dir.exists():
            icons[category] = sorted(cat_dir.glob('*.png'))
    return icons


def analyze_all(verbose=True):
    """Analyze all icons and report status"""
    icons = get_all_icons()
    results = {'ok': [], 'issues': []}

    for category, paths in icons.items():
        for path in paths:
            issues = validate_icon(path)
            if issues:
                results['issues'].append((path, issues))
                if verbose:
                    print(f"\n{category}/{path.name}: ISSUES")
                    for issue in issues:
                        print(f"  - {issue}")
            else:
                results['ok'].append(path)
                if verbose:
                    print(f"{category}/{path.name}: OK")

    print(f"\n=== SUMMARY ===")
    print(f"Valid: {len(results['ok'])}")
    print(f"Issues: {len(results['issues'])}")
    return results


def fix_all():
    """Fix centering on all icons"""
    icons = get_all_icons()
    fixed = 0

    for category, paths in icons.items():
        backup_dir = FORGED_DIR / 'backups' / category
        backup_dir.mkdir(parents=True, exist_ok=True)

        for path in paths:
            stats = get_content_stats(Image.open(path))
            if stats and not is_centered(stats):
                # Backup
                backup_path = backup_dir / path.name
                if not backup_path.exists():
                    Image.open(path).save(backup_path)

                # Fix
                img = center_content(Image.open(path))
                img.save(path)
                print(f"Fixed: {category}/{path.name}")
                fixed += 1

    print(f"\nFixed {fixed} icons")
    return fixed


def orient_icon(rel_path, direction):
    """Orient a specific icon to point in given direction"""
    full_path = FORGED_DIR / rel_path
    if not full_path.exists():
        print(f"Not found: {rel_path}")
        return False

    img = Image.open(full_path)

    if direction == 'upper-right':
        # Flip horizontal to point upper-right
        img = flip_horizontal(img)
    elif direction == 'upper-left':
        img = flip_vertical(flip_horizontal(img))
    elif direction == 'lower-right':
        img = flip_vertical(img)
    elif direction == 'lower-left':
        pass  # Usually the default diagonal
    elif direction == 'flip-h':
        img = flip_horizontal(img)
    elif direction == 'flip-v':
        img = flip_vertical(img)
    elif direction.startswith('rotate-'):
        angle = int(direction.replace('rotate-', ''))
        img = rotate_image(img, angle)

    img = center_content(img)
    img.save(full_path)
    print(f"Oriented {rel_path} -> {direction}")
    return True


def generate_preview_grid(output_path=None):
    """Generate preview grid of all icons"""
    icons = get_all_icons()
    all_icons = []
    for category in CATEGORIES:
        if category in icons:
            for path in icons[category]:
                all_icons.append((category, path))

    if not all_icons:
        print("No icons found")
        return

    cols = 6
    rows = math.ceil(len(all_icons) / cols)
    cell_size = 80

    grid_w = cols * cell_size
    grid_h = rows * cell_size + 60

    grid = Image.new('RGBA', (grid_w, grid_h), (30, 30, 35, 255))
    draw = ImageDraw.Draw(grid)

    draw.text((grid_w // 2, 15), "FORGE ITEMS PREVIEW", fill=(100, 200, 255), anchor="mt")
    draw.text((grid_w // 2, 35), f"{len(all_icons)} items", fill=(150, 150, 150), anchor="mt")

    for idx, (category, icon_path) in enumerate(all_icons):
        row = idx // cols
        col = idx % cols

        x = col * cell_size + (cell_size - ICON_SIZE) // 2
        y = row * cell_size + 60 + (cell_size - ICON_SIZE) // 2

        cell_x = col * cell_size
        cell_y = row * cell_size + 60
        draw.rectangle([cell_x + 2, cell_y + 2, cell_x + cell_size - 2, cell_y + cell_size - 2],
                       fill=(45, 45, 50), outline=(60, 60, 65))

        icon = Image.open(icon_path)
        grid.paste(icon, (x, y), icon)

        name = icon_path.stem.replace('_', ' ').title()
        if len(name) > 12:
            name = name[:11] + '.'
        draw.text((cell_x + cell_size // 2, cell_y + cell_size - 6),
                  name, fill=(180, 180, 180), anchor="mb")

    if output_path is None:
        output_path = FORGED_DIR / 'preview_grid.png'

    grid.save(output_path)
    print(f"Preview saved: {output_path}")
    return output_path


def print_help():
    print(__doc__)
    print("""
COMMANDS:
  (no args)        Analyze all icons (dry run)
  --fix            Fix centering on all icons
  --validate       Validate all icons against standards
  --preview        Generate preview grid
  --orient PATH DIR  Orient specific icon
                     DIR: upper-right, upper-left, lower-right, lower-left,
                          flip-h, flip-v, rotate-N (N = degrees)
  --help           Show this help
""")


if __name__ == '__main__':
    args = sys.argv[1:]

    if not args:
        analyze_all()
    elif args[0] == '--help':
        print_help()
    elif args[0] == '--fix':
        fix_all()
        generate_preview_grid()
    elif args[0] == '--validate':
        results = analyze_all()
        sys.exit(0 if not results['issues'] else 1)
    elif args[0] == '--preview':
        generate_preview_grid()
    elif args[0] == '--orient' and len(args) >= 3:
        orient_icon(args[1], args[2])
        generate_preview_grid()
    else:
        print_help()
