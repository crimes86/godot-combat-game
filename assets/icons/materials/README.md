# Material Icons Directory

This directory contains 64x64 PNG icons for material items (bones, wood, gems, etc.).

## How to Add Icons

1. Generate icons using the prompts in `docs/MATERIAL_ICON_PROMPTS.md`
2. Save as PNG files with the following names:
   - `bone_ember.png`
   - `dry_log.png`
   - `ancient_skull.png`
   - `cursed_femur.png`
   - `lichs_finger_bone.png`
   - `old_bones.png`
   - `broken_sword.png`
   - `tarnished_ring.png`
   - `dusty_gem.png`
   - `ancient_coin.png`

3. Place the PNG files in this directory
4. Icons will automatically load instead of using procedural generation

## Icon Requirements

- **Size**: 64x64 pixels
- **Format**: PNG with transparency (RGBA)
- **Padding**: Minimum 4px from edges
- **Naming**: lowercase_with_underscores.png

## Enhanced Icons

For higher quality 256x256 versions, place them in:
`assets/icons/enhanced/materials/`

The game will automatically use enhanced versions if `USE_ENHANCED_ICONS` is enabled in ItemIconGenerator.gd.

## Fallback

If an icon file is missing, the game will automatically fall back to procedural generation, so you can add icons incrementally.
