# Blacksmith NPC Sprites

Place your exported LPC blacksmith sprites here.

## Required Files:

### Option 1: Composite (Easiest)
Export the full blacksmith character from LPC generator:
- `blacksmith_walk.png` (576x256)
- `blacksmith_slash.png` (384x256)
- `blacksmith_hurt.png` (384x64)

### Option 2: Layered (More Flexible)
Export each layer separately:

**Body:**
- `body_male_walk.png`
- `body_male_slash.png`
- `body_male_hurt.png`

**Beard:**
- `beard_male_walk.png`
- `beard_male_slash.png`
- `beard_male_hurt.png`

**Apron/Clothes:**
- `apron_walk.png`
- `apron_slash.png`
- `apron_hurt.png`

## Next Steps:

1. Go to: https://liberatedpixelcup.github.io/Universal-LPC-Spritesheet-Character-Generator/
2. Design your blacksmith (male, beard, apron, work clothes)
3. Export walk, slash, and hurt animations
4. Place files here
5. Update paths in `scripts/npcs/BlacksmithNPC.gd` if needed
6. Create blacksmith scene in Godot editor

See `LPC_SPRITE_GUIDE.md` in project root for detailed instructions!
