# Female Character Implementation

## Overview
This update adds female character support to the Rhythm RPG game. Players can now choose between male or female character models at game start.

## What's New

### Gender Selection
- When you start the game, a dialog box will appear prompting you to select your character gender
- Two options are available:
  - **MALE WARRIOR** - Uses the original male character sprites
  - **FEMALE WARRIOR** - Uses the new female character sprites

### Features
- Gender selection appears at game startup before any other action
- Both characters use the same armor and equipment system
- Female character includes custom hair layer that displays over armor
- All animations (walk, attack, hurt) are gender-specific
- Same gameplay mechanics regardless of gender choice

## Files Added

### New Character Sprites
- `assets/characters/BODY_female_walk.png` - Female walking animation
- `assets/characters/BODY_female_slash.png` - Female attack animation
- `assets/characters/BODY_female_hurt.png` - Female hurt/damage animation
- `assets/characters/HAIR_female.png` - Female hair layer (rendered on top of armor)

### Modified Files
- `scripts/player/Player.gd` - Added gender selection system and sprite loading logic

## Technical Details

### How It Works
1. When the game starts, `Player._ready()` calls `show_gender_selection_dialog()`
2. The dialog presents two buttons and waits for player selection
3. Selected gender is stored in the `selected_gender` variable (enum: MALE or FEMALE)
4. When sprites are loaded in `setup_lpc_animations()`, it uses gender-specific paths:
   - Male: `BODY_human_*` sprites
   - Female: `BODY_female_*` sprites
5. Female characters get an additional hair layer composite on top of armor

### Sprite Layering Order
For all character types:
1. Body base (gender-specific)
2. Legs (shared armor)
3. Torso (shared armor)
4. Hair (female only - displays over armor)
5. Hat/Helmet (shared armor - displays on top)
6. Weapon (shared)

### Animation Structure
Both character types use the same LPC (Liberated Pixel Cup) format:
- **Walk animations**: 4 rows (up, left, down, right) × 9 frames each
- **Attack animations**: 4 rows (up, left, down, right) × 6 frames each  
- **Hurt animation**: 1 row × 6 frames
- Diagonal directions reuse cardinal direction sprites with flipping

## Gameplay Notes
- Gender is purely cosmetic - no gameplay differences
- Stats, abilities, equipment, and progression are identical
- Gender selection is made once at game start (stored per game session)
- Both characters wear the same armor and weapons

## Future Enhancements
Potential additions could include:
- Save gender preference between sessions
- Additional character customization options (hair color, skin tone)
- More female-specific armor variants
- Additional idle animations
