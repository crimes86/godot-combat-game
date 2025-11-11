#!/usr/bin/env python3
"""
Generate stonehenge-style ruins sprite for the wasteland
"""

from PIL import Image, ImageDraw
import random
import math

def create_ruins_sprite():
    print("Generating ruins sprite...")

    # Create image
    width, height = 256, 192
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Stone colors (dark gray, weathered)
    stone_dark = (51, 51, 56, 255)
    stone_base = (71, 71, 77, 255)
    stone_light = (89, 89, 97, 255)
    moss_color = (51, 77, 51, 153)
    blood_color = (38, 13, 13, 179)

    # Center position
    center_x = width // 2
    base_y = height - 20

    # === BACK STONES (smaller, background) ===
    draw_standing_stone(img, center_x - 70, base_y - 15, 30, 50, stone_dark)
    draw_standing_stone(img, center_x + 70, base_y - 15, 30, 50, stone_dark)

    # === SIDE STONES ===
    draw_standing_stone(img, center_x - 90, base_y, 35, 70, stone_base)
    draw_standing_stone(img, center_x + 90, base_y, 35, 70, stone_base)

    # === FRONT STONES (tallest) ===
    draw_standing_stone(img, center_x - 50, base_y, 40, 85, stone_light)
    add_moss_texture(img, center_x - 50, base_y - 85, 40, 85, moss_color)

    draw_standing_stone(img, center_x + 50, base_y, 40, 85, stone_light)
    add_moss_texture(img, center_x + 50, base_y - 85, 40, 85, moss_color)

    # === LINTEL STONE (horizontal capstone) ===
    draw_lintel_stone(img, center_x - 50, base_y - 85, 100, 20, stone_light)

    # === FALLEN STONES ===
    draw_fallen_stone(img, center_x - 100, base_y + 10, 45, 18, stone_base)
    draw_fallen_stone(img, center_x + 60, base_y + 15, 50, 16, stone_base)

    # === CENTER ALTAR ===
    draw_altar(img, center_x, base_y - 5, 60, 25, stone_dark)
    add_bloodstain(img, center_x, base_y - 5, 60, 25, blood_color)

    # === GROUND RUBBLE ===
    for i in range(20):
        rubble_x = center_x + random.randint(-110, 110)
        rubble_y = base_y + random.randint(-10, 20)
        rubble_size = random.randint(3, 8)
        draw_rubble(img, rubble_x, rubble_y, rubble_size, stone_dark)

    # Save
    output_path = "assets/environment/wasteland/ruins.png"
    img.save(output_path)
    print(f"[OK] Ruins sprite saved to: {output_path}")
    print(f"   Size: {width}x{height}")

def draw_standing_stone(img, center_x, base_y, width, height, color):
    """Draw a vertical standing stone pillar"""
    pixels = img.load()
    half_w = width // 2
    top_y = base_y - height

    # Tapered pillar
    top_width = int(width * 0.85)
    half_top = top_width // 2

    for y in range(top_y, base_y):
        progress = (y - top_y) / height
        current_half_w = int(half_top + (half_w - half_top) * progress)

        for x in range(-current_half_w, current_half_w):
            px, py = center_x + x, y
            if 0 <= px < img.width and 0 <= py < img.height:
                # Shading variation
                shade = math.sin(y * 0.3) * 0.05
                r = int(color[0] * (1 - shade))
                g = int(color[1] * (1 - shade))
                b = int(color[2] * (1 - shade))
                pixels[px, py] = (r, g, b, color[3])

    # Highlight left edge
    for y in range(top_y, base_y):
        px = center_x - half_w
        if 0 <= px < img.width and 0 <= y < img.height:
            r = min(255, int(color[0] * 1.15))
            g = min(255, int(color[1] * 1.15))
            b = min(255, int(color[2] * 1.15))
            pixels[px, y] = (r, g, b, color[3])

def draw_lintel_stone(img, left_x, y, width, height, color):
    """Draw horizontal capstone"""
    pixels = img.load()
    for dy in range(height):
        for dx in range(width):
            px, py = left_x + dx, y + dy
            if 0 <= px < img.width and 0 <= py < img.height:
                shade = 1.0 if dy < height // 2 else 0.85
                r = int(color[0] * shade)
                g = int(color[1] * shade)
                b = int(color[2] * shade)
                pixels[px, py] = (r, g, b, color[3])

def draw_fallen_stone(img, center_x, center_y, width, height, color):
    """Draw a fallen stone on ground"""
    pixels = img.load()
    half_w, half_h = width // 2, height // 2

    for y in range(-half_h, half_h):
        for x in range(-half_w, half_w):
            px, py = center_x + x, center_y + y
            if 0 <= px < img.width and 0 <= py < img.height:
                # Jagged edges
                if abs(x) < half_w - 2 or random.random() > 0.3:
                    shade = random.uniform(0.8, 1.0)
                    r = int(color[0] * shade)
                    g = int(color[1] * shade)
                    b = int(color[2] * shade)
                    pixels[px, py] = (r, g, b, color[3])

def draw_altar(img, center_x, center_y, width, height, color):
    """Draw sacrificial altar"""
    pixels = img.load()
    half_w, half_h = width // 2, height // 2

    for y in range(-half_h, half_h):
        for x in range(-half_w, half_w):
            px, py = center_x + x, center_y + y
            if 0 <= px < img.width and 0 <= py < img.height:
                shade = 1.0 if y < 0 else 0.7
                r = int(color[0] * shade)
                g = int(color[1] * shade)
                b = int(color[2] * shade)
                pixels[px, py] = (r, g, b, color[3])

def add_bloodstain(img, center_x, center_y, width, height, blood_color):
    """Add bloodstain on altar"""
    pixels = img.load()
    stain_w, stain_h = width // 3, height // 3

    for y in range(-stain_h // 2, stain_h // 2):
        for x in range(-stain_w // 2, stain_w // 2):
            px = center_x + x
            py = center_y - height // 4 + y

            if 0 <= px < img.width and 0 <= py < img.height:
                dist = math.sqrt(x * x + y * y)
                if dist < stain_w // 2 and random.random() > 0.2:
                    existing = pixels[px, py]
                    if existing[3] > 0:  # Has alpha
                        # Blend
                        r = int(existing[0] * 0.4 + blood_color[0] * 0.6)
                        g = int(existing[1] * 0.4 + blood_color[1] * 0.6)
                        b = int(existing[2] * 0.4 + blood_color[2] * 0.6)
                        pixels[px, py] = (r, g, b, existing[3])

def add_moss_texture(img, center_x, base_y, width, height, moss_color):
    """Add moss weathering"""
    pixels = img.load()
    half_w = width // 2

    for i in range(40):
        mx = center_x + random.randint(-half_w, half_w)
        my = base_y + random.randint(-height, 0)

        if 0 <= mx < img.width and 0 <= my < img.height:
            existing = pixels[mx, my]
            if existing[3] > 128:  # Has alpha
                r = int(existing[0] * 0.7 + moss_color[0] * 0.3)
                g = int(existing[1] * 0.7 + moss_color[1] * 0.3)
                b = int(existing[2] * 0.7 + moss_color[2] * 0.3)
                pixels[mx, my] = (r, g, b, existing[3])

def draw_rubble(img, x, y, size, color):
    """Draw small rubble"""
    pixels = img.load()
    half_size = size // 2

    for dy in range(-half_size, half_size):
        for dx in range(-half_size, half_size):
            if dx * dx + dy * dy < (size * size) // 4:
                px, py = x + dx, y + dy
                if 0 <= px < img.width and 0 <= py < img.height:
                    shade = random.uniform(0.8, 1.0)
                    r = int(color[0] * shade)
                    g = int(color[1] * shade)
                    b = int(color[2] * shade)
                    pixels[px, py] = (r, g, b, color[3])

if __name__ == "__main__":
    create_ruins_sprite()
