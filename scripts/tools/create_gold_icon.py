#!/usr/bin/env python3
"""
Generate a pixel art gold coin pile icon for the game UI.
Creates a 16x16 PNG image with transparency.
"""

import struct
import zlib

def create_png(width, height, pixels):
    """Create a PNG file from pixel data (RGBA format)"""

    def png_chunk(chunk_type, data):
        chunk_len = struct.pack('>I', len(data))
        chunk_crc = struct.pack('>I', zlib.crc32(chunk_type + data) & 0xffffffff)
        return chunk_len + chunk_type + data + chunk_crc

    # PNG signature
    signature = b'\x89PNG\r\n\x1a\n'

    # IHDR chunk
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    ihdr = png_chunk(b'IHDR', ihdr_data)

    # IDAT chunk (image data)
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'  # Filter type: None
        for x in range(width):
            idx = (y * width + x) * 4
            raw_data += bytes(pixels[idx:idx+4])

    compressed = zlib.compress(raw_data, 9)
    idat = png_chunk(b'IDAT', compressed)

    # IEND chunk
    iend = png_chunk(b'IEND', b'')

    return signature + ihdr + idat + iend

# 16x16 gold coin pile design
# Colors (RGBA):
TRANSPARENT = (0, 0, 0, 0)
GOLD_DARK = (139, 90, 43, 255)      # Dark gold/brown for shadow
GOLD_MID = (218, 165, 32, 255)      # Goldenrod - main color
GOLD_LIGHT = (255, 215, 0, 255)     # Gold - highlight
GOLD_BRIGHT = (255, 236, 139, 255)  # Light gold - bright highlight

# Shorthand
T = TRANSPARENT
D = GOLD_DARK
M = GOLD_MID
L = GOLD_LIGHT
B = GOLD_BRIGHT

# 16x16 pixel art - pile of 3 overlapping coins
# Design: 3 coins stacked/overlapping to form a small pile
pixel_art = [
    # Row 0
    [T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T],
    # Row 1 - top of back coin
    [T, T, T, T, T, T, D, D, D, D, T, T, T, T, T, T],
    # Row 2
    [T, T, T, T, T, D, L, L, L, M, D, T, T, T, T, T],
    # Row 3
    [T, T, T, T, D, L, B, L, M, M, D, T, T, T, T, T],
    # Row 4 - middle coin starts
    [T, T, T, D, D, L, L, M, M, D, D, D, D, T, T, T],
    # Row 5
    [T, T, D, L, L, B, L, M, D, L, L, L, M, D, T, T],
    # Row 6
    [T, T, D, L, B, L, M, M, D, L, B, L, M, D, T, T],
    # Row 7 - front coin starts
    [T, D, D, L, L, M, M, D, D, L, L, M, M, D, D, T],
    # Row 8
    [T, D, L, L, B, L, D, L, L, B, L, M, D, L, M, D],
    # Row 9
    [D, L, L, B, L, M, D, L, B, L, M, M, D, L, M, D],
    # Row 10
    [D, L, B, L, M, M, D, L, L, M, M, D, D, M, M, D],
    # Row 11
    [D, L, L, M, M, M, D, D, M, M, D, D, M, M, D, T],
    # Row 12
    [D, M, M, M, M, D, D, M, M, M, D, M, M, D, T, T],
    # Row 13
    [T, D, D, D, D, D, M, M, M, D, D, D, D, T, T, T],
    # Row 14
    [T, T, T, T, T, D, D, D, D, D, T, T, T, T, T, T],
    # Row 15
    [T, T, T, T, T, T, T, T, T, T, T, T, T, T, T, T],
]

# Convert to flat RGBA list
width = 16
height = 16
pixels = []
for row in pixel_art:
    for color in row:
        pixels.extend(color)

# Generate PNG
png_data = create_png(width, height, pixels)

# Save to file
output_path = r"C:\Users\kevin\OneDrive\godot-combat-game-master\assets\icons\gold_coins.png"
with open(output_path, 'wb') as f:
    f.write(png_data)

print(f"Created gold coin icon at: {output_path}")
print(f"Size: {width}x{height} pixels")
