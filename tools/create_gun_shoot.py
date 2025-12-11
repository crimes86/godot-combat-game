#!/usr/bin/env python3
"""
Create gun shoot animation from Skorpio walk sprite.

For the gun attack, we use frames from the walk animation where arms are extended,
creating a simple 3-frame shoot animation:
1. Aim pose (walk frame 0)
2. Recoil/shoot (shifted slightly back)
3. Return to aim

Output: 13 frames x 4 directions (832x256) - matching LPC shoot format
"""

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow required. Install with: pip install Pillow")
    sys.exit(1)

# LPC shoot animation is 13 frames x 4 directions
FRAME_SIZE = 64
SHOOT_FRAMES = 13
DIRECTIONS = 4  # up, left, down, right

# Source walk is 9 frames x 4 directions
WALK_FRAMES = 9

def create_shoot_from_walk(walk_path: Path, output_path: Path):
    """Create shoot animation from walk sprite."""

    walk_img = Image.open(walk_path).convert('RGBA')
    walk_width, walk_height = walk_img.size

    print(f"Walk sprite: {walk_width}x{walk_height}")
    print(f"Expected: {WALK_FRAMES * FRAME_SIZE}x{DIRECTIONS * FRAME_SIZE}")

    # Create output image for shoot (13 frames x 4 directions)
    shoot_width = SHOOT_FRAMES * FRAME_SIZE
    shoot_height = DIRECTIONS * FRAME_SIZE
    shoot_img = Image.new('RGBA', (shoot_width, shoot_height), (0, 0, 0, 0))

    # For each direction row
    for dir_idx in range(DIRECTIONS):
        y = dir_idx * FRAME_SIZE

        # Extract key frames from walk for this direction
        # Frame 0: neutral/aim pose
        # Frame 4: mid-stride (arms fully extended)
        frame_aim = walk_img.crop((0, y, FRAME_SIZE, y + FRAME_SIZE))
        frame_mid = walk_img.crop((4 * FRAME_SIZE, y, 5 * FRAME_SIZE, y + FRAME_SIZE))

        # Create shoot animation sequence (13 frames):
        # Frames 0-3: Hold aim pose
        # Frames 4-6: Recoil (use mid frame, slight shift)
        # Frames 7-9: Return to aim
        # Frames 10-12: Hold aim again

        sequence = []

        # Frames 0-3: Aim
        for i in range(4):
            sequence.append(frame_aim.copy())

        # Frames 4-6: "Recoil" - use mid frame (slightly different pose)
        # Apply a tiny horizontal offset to simulate recoil
        for i in range(3):
            recoil = Image.new('RGBA', (FRAME_SIZE, FRAME_SIZE), (0, 0, 0, 0))
            # Shift by 1-2 pixels in direction opposite to aim
            offset = 2 if i == 1 else 1  # More offset at peak
            if dir_idx == 1:  # left
                recoil.paste(frame_mid, (offset, 0))
            elif dir_idx == 3:  # right
                recoil.paste(frame_mid, (-offset, 0))
            elif dir_idx == 0:  # up
                recoil.paste(frame_mid, (0, offset))
            else:  # down
                recoil.paste(frame_mid, (0, -offset))
            sequence.append(recoil)

        # Frames 7-9: Return
        for i in range(3):
            sequence.append(frame_aim.copy())

        # Frames 10-12: Hold
        for i in range(3):
            sequence.append(frame_aim.copy())

        # Paste sequence into output
        for frame_idx, frame in enumerate(sequence):
            x = frame_idx * FRAME_SIZE
            shoot_img.paste(frame, (x, y))

    # Save
    output_path.parent.mkdir(parents=True, exist_ok=True)
    shoot_img.save(output_path)
    print(f"Created: {output_path}")
    print(f"Size: {shoot_width}x{shoot_height} ({SHOOT_FRAMES} frames x {DIRECTIONS} directions)")

    return True


def main():
    base_dir = Path(__file__).parent.parent

    walk_path = base_dir / "assets/characters/body_gun_pose/walk.png"
    shoot_path = base_dir / "assets/characters/body_gun_pose/shoot.png"

    if not walk_path.exists():
        print(f"ERROR: Walk sprite not found: {walk_path}")
        return False

    return create_shoot_from_walk(walk_path, shoot_path)


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
