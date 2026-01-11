"""
Tree Preview Generator
Slices LPC sprite sheets and creates a visual preview of all available trees
"""

from PIL import Image, ImageDraw, ImageFont
import os
from pathlib import Path

# Paths
PROJECT_ROOT = Path(__file__).parent.parent
TREE_PREVIEW_DIR = PROJECT_ROOT / "assets" / "environment" / "tree_preview"
DREADLAND_DIR = PROJECT_ROOT / "assets" / "environment" / "dreadland"
OUTPUT_DIR = TREE_PREVIEW_DIR / "sliced"
PREVIEW_OUTPUT = TREE_PREVIEW_DIR / "ALL_TREES_PREVIEW.png"

# Create output directory
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def find_sprite_bounds(img, start_x, start_y, max_width, max_height):
    """Find the bounding box of a sprite starting from a position"""
    pixels = img.load()
    width, height = img.size

    # Find actual bounds by scanning for non-transparent pixels
    min_x, min_y = max_width, max_height
    max_x, max_y = 0, 0
    found_pixel = False

    for y in range(start_y, min(start_y + max_height, height)):
        for x in range(start_x, min(start_x + max_width, width)):
            if len(pixels[x, y]) == 4 and pixels[x, y][3] > 10:  # Has alpha > 10
                found_pixel = True
                min_x = min(min_x, x - start_x)
                max_x = max(max_x, x - start_x)
                min_y = min(min_y, y - start_y)
                max_y = max(max_y, y - start_y)

    if not found_pixel:
        return None

    return (start_x + min_x, start_y + min_y, start_x + max_x + 1, start_y + max_y + 1)

def slice_spritesheet_auto(img_path, output_prefix, min_size=20):
    """Auto-detect and slice individual sprites from a spritesheet"""
    img = Image.open(img_path).convert("RGBA")
    pixels = img.load()
    width, height = img.size

    sliced = []
    visited = set()

    def flood_find_bounds(start_x, start_y):
        """Find connected region bounds"""
        stack = [(start_x, start_y)]
        min_x, min_y = start_x, start_y
        max_x, max_y = start_x, start_y

        while stack:
            x, y = stack.pop()
            if (x, y) in visited or x < 0 or y < 0 or x >= width or y >= height:
                continue

            pixel = pixels[x, y]
            if len(pixel) < 4 or pixel[3] < 10:
                continue

            visited.add((x, y))
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)

            # Check neighbors (8-connected for better grouping)
            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    if dx == 0 and dy == 0:
                        continue
                    stack.append((x + dx, y + dy))

        return min_x, min_y, max_x, max_y

    # Scan for sprites
    for y in range(height):
        for x in range(width):
            if (x, y) in visited:
                continue
            pixel = pixels[x, y]
            if len(pixel) >= 4 and pixel[3] > 10:
                bounds = flood_find_bounds(x, y)
                if bounds:
                    min_x, min_y, max_x, max_y = bounds
                    w = max_x - min_x + 1
                    h = max_y - min_y + 1
                    if w >= min_size and h >= min_size:
                        sliced.append((min_x, min_y, max_x + 1, max_y + 1))

    # Sort by position (top-left to bottom-right)
    sliced.sort(key=lambda b: (b[1] // 50, b[0]))

    # Save individual sprites
    saved = []
    for i, bounds in enumerate(sliced):
        sprite = img.crop(bounds)
        out_path = OUTPUT_DIR / f"{output_prefix}_{i:02d}.png"
        sprite.save(out_path)
        saved.append((out_path, sprite.size))
        print(f"  Saved: {out_path.name} ({sprite.size[0]}x{sprite.size[1]})")

    return saved

def collect_existing_trees():
    """Collect existing tree images from dreadland folder"""
    existing = []

    # Main trees
    for name in ["dead_tree.png", "pine_tree.png", "autumn_tree.png"]:
        path = DREADLAND_DIR / name
        if path.exists():
            img = Image.open(path)
            existing.append((path, img.size, "CURRENT"))

    # Numbered dead trees
    for i in range(1, 11):
        path = DREADLAND_DIR / f"dead_tree_{i}.png"
        if path.exists():
            img = Image.open(path)
            existing.append((path, img.size, "CURRENT"))

    return existing

def create_preview_image(all_trees):
    """Create a large preview image showing all trees with labels"""
    # Group trees by category
    categories = {}
    for path, size, category in all_trees:
        if category not in categories:
            categories[category] = []
        categories[category].append((path, size))

    # Calculate layout
    padding = 20
    label_height = 30
    max_row_width = 2000

    # Calculate total height needed
    total_height = padding
    category_layouts = {}

    for cat_name, trees in categories.items():
        total_height += label_height + padding

        # Layout trees in rows
        rows = []
        current_row = []
        current_width = padding
        max_height_in_row = 0

        for path, size in trees:
            w, h = size
            if current_width + w + padding > max_row_width and current_row:
                rows.append((current_row, max_height_in_row))
                current_row = []
                current_width = padding
                max_height_in_row = 0

            current_row.append((path, size))
            current_width += w + padding
            max_height_in_row = max(max_height_in_row, h)

        if current_row:
            rows.append((current_row, max_height_in_row))

        category_layouts[cat_name] = rows
        for row, row_height in rows:
            total_height += row_height + padding

    # Create preview image
    preview = Image.new("RGBA", (max_row_width, total_height), (40, 40, 45, 255))
    draw = ImageDraw.Draw(preview)

    try:
        font = ImageFont.truetype("arial.ttf", 20)
        small_font = ImageFont.truetype("arial.ttf", 12)
    except:
        font = ImageFont.load_default()
        small_font = font

    y = padding

    for cat_name, rows in category_layouts.items():
        # Draw category label
        draw.text((padding, y), f"=== {cat_name} ===", fill=(255, 255, 100, 255), font=font)
        y += label_height + padding

        for row, row_height in rows:
            x = padding
            for path, size in row:
                try:
                    tree_img = Image.open(path).convert("RGBA")
                    # Center vertically in row
                    y_offset = (row_height - size[1]) // 2
                    preview.paste(tree_img, (x, y + y_offset), tree_img)

                    # Draw filename below
                    filename = path.name[:20] + "..." if len(path.name) > 20 else path.name
                    draw.text((x, y + row_height + 2), filename, fill=(180, 180, 180, 255), font=small_font)
                except Exception as e:
                    print(f"Error loading {path}: {e}")

                x += size[0] + padding

            y += row_height + padding + 15  # Extra space for filename

    preview.save(PREVIEW_OUTPUT)
    print(f"\nPreview saved to: {PREVIEW_OUTPUT}")
    return PREVIEW_OUTPUT

def main():
    print("=== Tree Preview Generator ===\n")

    all_trees = []

    # 1. Collect existing trees
    print("Collecting existing trees...")
    existing = collect_existing_trees()
    for path, size, cat in existing:
        all_trees.append((path, size, cat))
    print(f"  Found {len(existing)} existing trees\n")

    # 2. Slice LPC trees sprite sheets
    lpc_trees_dir = TREE_PREVIEW_DIR / "lpc-trees" / "lpc-trees"
    if lpc_trees_dir.exists():
        for sheet_name in ["trees-dead.png", "trees-brown.png", "trees-orange.png", "trees-pale.png", "trees-green.png"]:
            sheet_path = lpc_trees_dir / sheet_name
            if sheet_path.exists():
                print(f"Slicing {sheet_name}...")
                prefix = sheet_name.replace(".png", "").replace("-", "_")
                sliced = slice_spritesheet_auto(sheet_path, f"lpc_{prefix}")
                for path, size in sliced:
                    all_trees.append((path, size, f"LPC {sheet_name.replace('.png', '').replace('trees-', '').upper()}"))

    # 3. Slice conifers
    conifers_path = TREE_PREVIEW_DIR / "lpc-conifers" / "lpc-conifers" / "conifers.png"
    if conifers_path.exists():
        print(f"\nSlicing conifers.png...")
        sliced = slice_spritesheet_auto(conifers_path, "lpc_conifer")
        for path, size in sliced:
            all_trees.append((path, size, "LPC CONIFERS"))

    # 4. Create preview
    print(f"\nTotal trees: {len(all_trees)}")
    print("\nCreating preview image...")
    create_preview_image(all_trees)

    print("\nDone! Open ALL_TREES_PREVIEW.png to review trees.")

if __name__ == "__main__":
    main()
