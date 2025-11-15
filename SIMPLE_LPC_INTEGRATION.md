# Simple LPC Integration Guide

## What Changed

**OLD (Complex):** ModularLPCCharacter with multiple layers, weapon overrides, complex synchronization
**NEW (Simple):** SimpleLPCSprite with row-based directions - that's it!

## Key Concept

LPC sprites have **4 rows** in each spritesheet:
- Row 0 = North (facing up)
- Row 1 = West (facing left)
- Row 2 = South (facing down)
- Row 3 = East (facing right)

**NEVER use flip_h or scale.x = -1 with LPC sprites!**

## Integration Steps

###Step 1: Update create_player_sprite() in Player.gd

Replace the entire function with this:

```gdscript
func create_player_sprite() -> void:
	print("🎨 Creating simple LPC sprite system")

	# Create shadow
	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	var shadow_img = Image.create(48, 16, false, Image.FORMAT_RGBA8)
	for x in range(48):
		for y in range(16):
			var dx = (x - 24) / 24.0
			var dy = (y - 8) / 8.0
			var dist = dx * dx + dy * dy
			if dist <= 1.0:
				var alpha = (1.0 - dist) * 0.4
				shadow_img.set_pixel(x, y, Color(0, 0, 0, alpha))
	var shadow_texture = ImageTexture.create_from_image(shadow_img)
	shadow.texture = shadow_texture
	shadow.position = Vector2(0, 20)
	shadow.z_index = -5
	add_child(shadow)
	print("  ✅ Shadow created")

	# Preload SimpleLPCSprite
	var SimpleLPCSprite = preload("res://scripts/SimpleLPCSprite.gd")

	# Create character sprite
	var character_sprite = SimpleLPCSprite.new()
	character_sprite.name = "CharacterSprite"
	character_sprite.position = Vector2(0, -8)
	character_sprite.centered = true

	# Load textures
	var body_type = "body_male" if selected_gender == Gender.MALE else "body_female"
	var walk_tex = load("res://assets/characters/" + body_type + "/standard/walk.png")
	var slash_tex = load("res://assets/characters/" + body_type + "/standard/slash.png")
	var hurt_tex = load("res://assets/characters/" + body_type + "/standard/hurt.png")

	# Setup sprite
	character_sprite.setup_lpc_sprite(walk_tex, slash_tex, hurt_tex)

	add_child(character_sprite)

	# Connect animation_finished signal
	if not character_sprite.animation_finished.is_connected(_on_attack_animation_finished):
		character_sprite.animation_finished.connect(_on_attack_animation_finished)

	print("  ✅ Simple LPC character created")
```

### Step 2: Update update_lpc_animation() in Player.gd

Replace with:

```gdscript
func update_lpc_animation(velocity_dir: Vector2) -> void:
	"""Update animation - NO FLIPPING, use row-based directions!"""
	var character_sprite = get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Don't interrupt attack animations
	if character_sprite.animation and character_sprite.animation.begins_with("slash_") and character_sprite.is_playing():
		return

	# Get direction (down/up/left/right from old system)
	var is_moving = velocity_dir.length() > 0.1
	var dir_str = get_direction_string(velocity_dir) if is_moving else get_direction_string(attack_direction)

	# Convert to LPC direction (south/north/west/east)
	var lpc_dir = convert_to_lpc_direction(dir_str)

	# Play animation
	var anim = "walk" if is_moving else "idle"
	character_sprite.play_lpc_animation(anim, lpc_dir)
```

### Step 3: Add direction conversion helper

Add this function anywhere in Player.gd:

```gdscript
func convert_to_lpc_direction(dir_string: String) -> String:
	"""Convert old direction names to LPC standard"""
	match dir_string:
		"down": return "south"
		"up": return "north"
		"left": return "west"
		"right": return "east"
		_: return "south"
```

### Step 4: Update attempt_attack() in Player.gd

Replace the animation part with:

```gdscript
func attempt_attack() -> void:
	if not can_attack:
		return

	can_attack = false

	# Play attack animation
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		var dir_str = get_direction_string(attack_direction)
		var lpc_dir = convert_to_lpc_direction(dir_str)
		character_sprite.play_lpc_animation("slash", lpc_dir)

	# ... rest of attack logic stays the same ...
	Chain Manager.register_attack()

	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()

	var enemies_in_cone = get_enemies_in_cone()

	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.SWING, global_position, -8.0)

	if enemies_in_cone.size() > 0:
		attack_enemies_in_cone(enemies_in_cone)
		finish_attack_cooldown()
	else:
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.MISS, global_position, -10.0)
		finish_attack_cooldown()
```

### Step 5: Delete old functions

Remove these functions entirely:
- `setup_lpc_animations_layered()`
- `setup_sprite_layer()`
- `create_animation()`

## Testing

After applying changes:
1. Run the game
2. Use arrow keys to walk in all 4 directions
3. Character should face the correct direction WITHOUT flipping
4. Click to attack - weapon should face the same direction as character

## Why This Works

- **Row-based system**: Each direction has its own sprite row in the texture
- **No flip_h**: LPC sprites are designed to NOT be flipped
- **Simple**: One sprite, one system, easy to understand and debug

That's it! Much simpler than the modular system.
