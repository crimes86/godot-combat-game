# Migration to LPCAnimatedSprite2D Addon

## Changes Required in Player.gd

### 1. Replace Sprite Node Creation (Lines ~1000-1048)

**OLD:**
```gdscript
var body_sprite = AnimatedSprite2D.new()
body_sprite.name = "BodySprite"
body_sprite.position = base_position
body_sprite.centered = true
body_sprite.z_index = 0
add_child(body_sprite)
```

**NEW:**
```gdscript
var body_sprite = LPCAnimatedSprite2D.new()
body_sprite.name = "BodySprite"
body_sprite.position = base_position
body_sprite.centered = true
body_sprite.z_index = 0

# Set sprite path and animation data
var body_type = "body_male" if selected_gender == Gender.MALE else "body_female"
body_sprite.spritesheets_path = "res://assets/characters/" + body_type
body_sprite.animation_data = LPCAnimationData.new()

add_child(body_sprite)
```

### 2. Remove Custom Animation Setup Functions

**DELETE THESE FUNCTIONS:**
- `setup_lpc_animations_layered()` (lines ~1058-1119)
- `setup_sprite_layer()` (lines ~1132-1212)
- `create_animation()` (lines ~1214-1226)

**REPLACE WITH:** Nothing! The addon handles all animation setup automatically.

### 3. Update Animation Playback

**Direction Mapping:**
- `down` → `south`
- `up` → `north`
- `left` → `west`
- `right` → `east`

**Animation Mapping:**
- `idle_X` → `idle` (X = direction)
- `walk_X` → `walk`
- `attack_X` → `slash`

**OLD:**
```gdscript
sprite.play("walk_down")
sprite.play("attack_left")
sprite.play("idle_up")
```

**NEW:**
```gdscript
sprite.play_animation("walk", "south")
sprite.play_animation("slash", "west")
sprite.play_animation("idle", "north")
```

### 4. Weapon Handling

**For oversize weapons (longsword):**
- Use `slash_oversize` animation instead of `slash`
- Addon automatically handles 192x64 frames

**OLD:**
```gdscript
var weapon_base = "res://assets/weapons/" + weapon_name + "/"
var WEAPON_SLASH_FRONT = weapon_base + "slash_front.png"
setup_sprite_layer("WeaponFrontSprite", ..., WEAPON_SLASH_FRONT, ...)
```

**NEW:**
```gdscript
var weapon_sprite = LPCAnimatedSprite2D.new()
weapon_sprite.spritesheets_path = "res://assets/weapons/" + weapon_name
weapon_sprite.animation_data = LPCAnimationData.new()

# The addon will automatically use slash_oversize if available
weapon_sprite.play_animation("slash_oversize", "south")
```

## Summary of Files to Update

1. **Player.gd**: Main refactoring
   - Sprite creation (~lines 1000-1048)
   - Animation playback (~lines 380-700)
   - Attack handling (~lines 650-700)

2. **Direction conversion helper** (add new function):
```gdscript
func get_lpc_direction(velocity_dir: Vector2) -> String:
	if abs(velocity_dir.x) > abs(velocity_dir.y):
		return "east" if velocity_dir.x > 0 else "west"
	else:
		return "south" if velocity_dir.y > 0 else "north"
```
