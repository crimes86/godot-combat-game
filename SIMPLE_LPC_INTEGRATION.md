# Simple LPC Sprite System - Layered Architecture

## Overview

The sprite system uses a **layered approach** with three main components:
1. **Base Body Layer** - The character's body (walk, slash, hurt animations)
2. **Armor Layers** - Equipment worn on the body (chest, legs, etc.)
3. **Weapon Layer** - Held weapons (dynamically loaded based on equipped weapon)

## Key Concept

LPC sprites have **4 rows** in each spritesheet:
- Row 0 = North (facing up)
- Row 1 = West (facing left)
- Row 2 = South (facing down)
- Row 3 = East (facing right)

**NEVER use flip_h or scale.x = -1 with LPC sprites!**

## Sprite Layering System

### Layer 1: Base Body
- Z-index: 0 (base layer)
- Contains walk, slash, hurt animations
- Always visible
- Location: `assets/characters/BODY_{type}_{animation}.png`

### Layer 2: Armor (Future)
- Z-index: 0.5 (between body and weapon)
- Shirt (chest slot) and Pants (legs slot)
- Currently in equipment system but not rendered visually
- Location: `assets/characters/shirt/` and `assets/characters/pants/`

### Layer 3: Weapon
- Z-index: 1 (on top) or -1 (behind when facing north)
- Dynamically loaded based on equipped weapon's `weapon_type`
- Has walk and slash animations
- Auto-hides when no weapon equipped
- Location: `assets/weapons/{weapon_type}/walk.png` and `slash.png`

## Variable Tile Size Support

The system automatically detects sprite tile sizes:
- **Standard sprites**: 64x64 tiles (384x256 sheets)
- **Oversize sprites**: 192x192 tiles (1152x768 sheets)

Calculation: `tile_size = sprite_width / frame_count`

## Weapon System Integration

### Dynamic Weapon Loading
```gdscript
if CharacterStats.equipped_weapon:
    var weapon_type = CharacterStats.equipped_weapon.weapon_type
    var weapon_path = "res://assets/weapons/" + weapon_type + "/"

    weapon_slash_tex = load(weapon_path + "slash.png")
    weapon_walk_tex = load(weapon_path + "walk.png")
```

### Weapon Layer Features
- **Auto-detection**: Tile size calculated from sprite dimensions
- **Direction-based offsets**: Slash animations offset to align with player body
- **Z-index switching**: Weapon renders behind player when facing north
- **Visibility control**: Hidden when no weapon equipped or during walk/idle

### Weapon Slash Offsets
Direction-specific offsets to align weapon with player body:
- **East** (facing right): `(-5, 10)`
- **West** (facing left): `(5, 10)`
- **North** (facing up): `(-10, 0)`
- **South** (facing down): `(-5, 5)`

## Starting Equipment

Players spawn with:
- **Tattered Shirt** (chest) - 0 armor, 1 gold value
- **Tattered Pants** (legs) - 0 armor, 1 gold value
- **No weapon** - must pick up from vendor

All starting items are:
- ✅ Equippable/Unequippable
- ✅ Sellable/Destroyable
- ✅ Tradeable

## SimpleLPCSprite API

### setup_lpc_sprite()
```gdscript
func setup_lpc_sprite(
    walk_tex: Texture2D,
    slash_tex: Texture2D = null,
    hurt_tex: Texture2D = null,
    weapon_slash_tex: Texture2D = null,
    weapon_walk_tex: Texture2D = null
)
```

### play_lpc_animation()
```gdscript
func play_lpc_animation(anim_name: String, direction: String)
```
- `anim_name`: "walk", "idle", "slash", "hurt"
- `direction`: "north", "south", "east", "west"

### create_animation_from_image()
```gdscript
func create_animation_from_image(
    img: Image,
    anim_name: String,
    row: int,
    frame_count: int,
    frame_indices: Array,
    fps: float,
    loop: bool,
    target_frames: SpriteFrames = null,
    tile_size: int = 64  # Auto-calculated for variable sizes
)
```

## Implementation Example

### Player.gd - create_player_sprite()
```gdscript
# Load base body textures
var body_type = "human" if selected_gender == Gender.MALE else "female"
var walk_tex = load("res://assets/characters/BODY_" + body_type + "_walk.png")
var slash_tex = load("res://assets/characters/BODY_" + body_type + "_slash.png")
var hurt_tex = load("res://assets/characters/BODY_" + body_type + "_hurt.png")

# Load weapon textures based on equipped weapon
var weapon_slash_tex = null
var weapon_walk_tex = null

if CharacterStats.equipped_weapon:
    var weapon_type = CharacterStats.equipped_weapon.weapon_type
    var weapon_path = "res://assets/weapons/" + weapon_type + "/"

    if ResourceLoader.exists(weapon_path + "slash.png"):
        weapon_slash_tex = load(weapon_path + "slash.png")
    if ResourceLoader.exists(weapon_path + "walk.png"):
        weapon_walk_tex = load(weapon_path + "walk.png")

# Setup layered sprite
character_sprite.setup_lpc_sprite(walk_tex, slash_tex, hurt_tex, weapon_slash_tex, weapon_walk_tex)
```

### Player.gd - update_lpc_animation()
```gdscript
func update_lpc_animation(velocity_dir: Vector2) -> void:
    var character_sprite = get_node_or_null("CharacterSprite")
    if not character_sprite:
        return

    # Don't interrupt attack animations
    if character_sprite.animation and character_sprite.animation.begins_with("slash_") and character_sprite.is_playing():
        return

    # Get direction
    var is_moving = velocity_dir.length() > 0.1
    var dir_str = get_direction_string(velocity_dir) if is_moving else get_direction_string(attack_direction)
    var lpc_dir = convert_to_lpc_direction(dir_str)

    # Play animation
    var anim = "walk" if is_moving else "idle"
    character_sprite.play_lpc_animation(anim, lpc_dir)
```

### Player.gd - attempt_attack()
```gdscript
func attempt_attack() -> void:
    # ... attack logic ...

    # Play attack animation
    var character_sprite = get_node_or_null("CharacterSprite")
    if character_sprite:
        var dir_str = get_direction_string(attack_direction)
        var lpc_dir = convert_to_lpc_direction(dir_str)
        character_sprite.play_lpc_animation("slash", lpc_dir)
```

## Weapon Equipment Flow

1. **Player picks up weapon from vendor** → Added to inventory
2. **Player equips weapon** → `CharacterStats.equip_weapon()` called
3. **Signal emitted** → `weapon_equipped` signal triggers
4. **Player sprite refreshed** → `create_player_sprite()` rebuilds sprite with weapon
5. **Weapon layer created** → SimpleLPCSprite creates weapon AnimatedSprite2D child
6. **Animations synced** → Weapon animations play in sync with body animations

## Supported Weapon Types

The system supports any weapon type with sprites in `assets/weapons/{type}/`:
- `mace` - Default starter weapon (Wooden Mace - free)
- `sword` - Longsword family
- `dagger` - Fast attack weapons
- `spear` - Polearms
- `hammer` - Slow, heavy weapons
- `rapier` - Fast precision weapons

## Future: Armor Layer System

To render shirt and pants visually, implement armor layers:
1. Add armor sprite children to SimpleLPCSprite
2. Load armor textures from equipped_armor slots
3. Layer between body (z=0) and weapon (z=1)
4. Sync animations with body layer

## Testing

After changes:
1. ✅ Walk in all 4 directions - character faces correctly without flipping
2. ✅ Pick up Wooden Mace from vendor - weapon appears
3. ✅ Attack in all directions - weapon slashes in correct direction
4. ✅ Unequip weapon - weapon disappears
5. ✅ Check equipment UI - Tattered Shirt and Pants shown in slots

## Why This Works

- **Row-based system**: Each direction has its own sprite row
- **No flip_h**: LPC sprites designed to NOT be flipped
- **Layered rendering**: Clean separation between body, armor, and weapons
- **Dynamic loading**: Weapons loaded based on equipment, not hardcoded
- **Variable tile sizes**: Supports both standard (64x64) and oversize (192x192) sprites
