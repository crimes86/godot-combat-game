#!/usr/bin/env python3
"""
Composite LPC skeletal guardian sprites from individual layers
Creates walk_guardian.png and slash_guardian.png
"""

from PIL import Image
import os

# Base path to skeletal guardian animations
BASE_PATH = r"C:\Users\kevin\OneDrive\fantom\mmo\dreadland\assets\characters\skeletal_guardian\standard"
OUTPUT_PATH = r"C:\Users\kevin\OneDrive\fantom\mmo\dreadland\assets\characters\skeletal_guardian"

# Layer order (bottom to top) - numeric prefix determines order
LAYERS_WALK = [
    "009 weapon sword longsword universal_behind longsword.png",  # Sword behind body
    "010 body bodies skeleton skeleton.png",  # Skeleton body
    "015 feet armour plate male copper.png",  # Copper boots
    "020 legs armour plate male copper.png",  # Copper greaves
    "060 torso armour plate male copper.png",  # Copper chest
    "060 arms armour plate male copper.png",  # Copper armguards
    "065 shoulders plate male copper.png",  # Copper shoulders
    "070 arms gloves male copper.png",  # Copper gloves
    "100 head heads skeleton adult skeleton.png",  # Skeleton head
    "130 hat helmet bascinet adult copper.png",  # Copper helmet
    "140 weapon sword longsword longsword.png",  # Sword in front
]

# Slash animation doesn't include weapon (handled by oversize)
LAYERS_SLASH = [
    "010 body bodies skeleton skeleton.png",  # Skeleton body
    "015 feet armour plate male copper.png",  # Copper boots
    "020 legs armour plate male copper.png",  # Copper greaves
    "060 torso armour plate male copper.png",  # Copper chest
    "060 arms armour plate male copper.png",  # Copper armguards
    "065 shoulders plate male copper.png",  # Copper shoulders
    "070 arms gloves male copper.png",  # Copper gloves
    "100 head heads skeleton adult skeleton.png",  # Skeleton head
    "130 hat helmet bascinet adult copper.png",  # Copper helmet
]

LAYER_SETS = {
    "walk": LAYERS_WALK,
    "slash": LAYERS_SLASH
}

def composite_animation(animation_name: str):
    """Composite all layers for a given animation (walk or slash)"""
    anim_path = os.path.join(BASE_PATH, animation_name)

    if not os.path.exists(anim_path):
        print(f"ERROR: Animation path not found: {anim_path}")
        return

    print(f"\nCompositing {animation_name}...")

    # Get layer set for this animation
    layers = LAYER_SETS.get(animation_name, LAYERS_WALK)

    # Load first layer to get dimensions
    first_layer_path = os.path.join(anim_path, layers[0])
    if not os.path.exists(first_layer_path):
        print(f"ERROR: First layer not found: {first_layer_path}")
        return

    base_image = Image.open(first_layer_path).convert("RGBA")
    width, height = base_image.size
    print(f"   Dimensions: {width}x{height}")

    # Create composite
    composite = Image.new("RGBA", (width, height), (0, 0, 0, 0))

    # Composite each layer
    layers_composited = 0
    for layer_file in layers:
        layer_path = os.path.join(anim_path, layer_file)
        if os.path.exists(layer_path):
            layer = Image.open(layer_path).convert("RGBA")
            composite = Image.alpha_composite(composite, layer)
            layers_composited += 1
            print(f"   + {layer_file}")
        else:
            print(f"   - Skipped (not found): {layer_file}")

    # Save output
    output_filename = f"{animation_name}_guardian.png"
    output_path = os.path.join(OUTPUT_PATH, output_filename)
    composite.save(output_path, "PNG")
    print(f"   Saved: {output_filename} ({layers_composited} layers)")

    return output_path

def main():
    print("=" * 60)
    print("SKELETAL GUARDIAN SPRITE COMPOSITOR")
    print("=" * 60)

    # Check if PIL is available
    try:
        from PIL import Image
    except ImportError:
        print("ERROR: PIL (Pillow) not installed!")
        print("   Install with: pip install Pillow")
        return

    # Composite animations
    animations = ["walk", "slash"]

    for anim in animations:
        output = composite_animation(anim)
        if output:
            print(f"   Created: {output}")

    print("\nDone! Skeletal guardian sprites created:")
    print(f"   - {OUTPUT_PATH}\\walk_guardian.png")
    print(f"   - {OUTPUT_PATH}\\slash_guardian.png")
    print("\nImport these into Godot and configure in guardian_skeleton.tscn")

if __name__ == "__main__":
    main()
