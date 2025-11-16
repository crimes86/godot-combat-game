extends StaticBody2D
class_name TrainingDummy

## Training Dummy - Hittable target that spins when hit
## Can be attacked by player for combat practice
## Displays damage numbers and tracks DPS

# Stats
var max_health: float = 999999.0  # Essentially infinite
var current_health: float = 999999.0

# References
var sprite: AnimatedSprite2D = null
var click_area: Area2D = null
var health_bar: Control = null

# Spin animation state
var is_spinning: bool = false
var spin_duration: float = 0.5  # How long the spin lasts
var spin_timer: float = 0.0

# Damage tracking (for training feedback)
var total_damage_dealt: float = 0.0
var last_damage_time: float = 0.0
var damage_window: float = 3.0  # DPS calculation window

# Crit window support (same as Enemy)
var in_crit_window: bool = false
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var weakpoints: Array = []

# Signals
signal damage_taken(damage: float, is_crit: bool)
signal weakpoint_hit_success()
signal crit_window_complete(weakpoints_destroyed: int)
signal died()

func _ready() -> void:

	# Add to enemies group so player can target it
	add_to_group(Constants.GROUP_ENEMIES)

	# Set collision layers (same as enemies)
	collision_layer = 1
	collision_mask = 0  # Doesn't need to detect anything

	# Create sprite
	create_dummy_sprite()

	# Create clickable area
	create_click_area()

	# Create health bar (optional - could just show damage numbers)
	create_health_bar()

	# Create hit flash for visual feedback
	create_hit_flash()

	# Store original scale and modulate for crit window
	original_scale = scale
	await get_tree().process_frame
	original_modulate = self.modulate

func create_dummy_sprite() -> void:
	"""Create animated sprite from dummy spritesheet"""
	const DUMMY_PATH = "res://assets/characters/BODY_Dummy_animation.png"

	if not ResourceLoader.exists(DUMMY_PATH):
		push_error("❌ Dummy texture not found at: " + DUMMY_PATH)
		return

	var dummy_tex: Texture2D = ResourceLoader.load(DUMMY_PATH, "Texture2D")
	if not dummy_tex:
		push_error("❌ Failed to load dummy texture")
		return

	var dummy_img = dummy_tex.get_image()

	# Create animated sprite
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"  # Name it "Sprite" so HitFlash can find it
	sprite.centered = true
	sprite.position = Vector2(0, -32)  # Offset up like player/enemies
	add_child(sprite)

	# Create sprite frames for spin animation
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("idle")
	sprite_frames.add_animation("spin")

	# Idle: Just the first frame
	var idle_frame = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	idle_frame.blit_rect(dummy_img, Rect2i(0, 0, 64, 64), Vector2i(0, 0))
	sprite_frames.add_frame("idle", ImageTexture.create_from_image(idle_frame))
	sprite_frames.set_animation_loop("idle", true)
	sprite_frames.set_animation_speed("idle", 1.0)

	# Spin: All 8 frames
	sprite_frames.set_animation_loop("spin", false)
	sprite_frames.set_animation_speed("spin", 16.0)  # Fast spin

	for i in range(8):
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(dummy_img, Rect2i(i * 64, 0, 64, 64), Vector2i(0, 0))
		sprite_frames.add_frame("spin", ImageTexture.create_from_image(frame_img))

	sprite.sprite_frames = sprite_frames
	sprite.play("idle")

	# Connect animation finished signal
	sprite.animation_finished.connect(_on_animation_finished)

func create_click_area() -> void:
	"""Create Area2D for clicking detection"""
	click_area = Area2D.new()
	click_area.name = "ClickArea"
	click_area.collision_layer = 0
	click_area.collision_mask = 0
	click_area.input_pickable = true
	add_child(click_area)

	# Create circular collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 40.0  # Match enemy size
	collision.shape = shape
	collision.position = Vector2(0, -32)  # Match sprite position
	click_area.add_child(collision)

func create_health_bar() -> void:
	"""Create simple health bar (optional for dummy)"""
	# For now, skip health bar - just show damage numbers
	# Could add a DPS display here later
	pass

func create_hit_flash() -> void:
	"""Create HitFlash node for visual feedback"""
	const HIT_FLASH_SCRIPT = preload("res://scripts/enemies/hitflash.gd")

	var hit_flash = Node.new()
	hit_flash.name = "HitFlash"
	hit_flash.set_script(HIT_FLASH_SCRIPT)
	add_child(hit_flash)

func _physics_process(delta: float) -> void:
	# Handle spin animation timing
	if is_spinning:
		spin_timer += delta
		if spin_timer >= spin_duration:
			is_spinning = false
			spin_timer = 0.0

func take_damage(amount: float, is_crit: bool = false) -> void:
	"""Handle being hit - spin and show damage"""

	# Validate damage
	if is_nan(amount) or is_inf(amount) or amount < 0:
		return

	# Track damage for DPS calculation
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_damage_time > damage_window:
		# Reset tracking if no damage for a while
		total_damage_dealt = amount
	else:
		total_damage_dealt += amount
	last_damage_time = current_time

	# Don't actually reduce health (infinite HP)
	# current_health stays at max

	# Emit signal for player feedback (damage numbers)
	damage_taken.emit(amount, is_crit)

	# Play skeleton sounds for testing (same as Enemy)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Determine if this is a weakpoint hit
		var is_weakpoint = is_crit and in_crit_window

		if not is_weakpoint:
			# Get player's weapon type for weapon-specific sounds
			var weapon_type = ""
			if CharacterStats.equipped_weapon:
				weapon_type = CharacterStats.equipped_weapon.weapon_type

			# Play hit sound
			if is_crit:
				sound_manager.play_critical_hit_sound(global_position, -8.0)
			else:
				sound_manager.play_normal_hit_sound(global_position, -8.0, weapon_type)

		# Play skeleton hurt reaction sound (for all hit types)
		sound_manager.play_skeleton_hurt_sound(global_position, -8.0)

	# Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	# Spawn combat text (same as Enemy)
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	# Set damage text
	combat_text.text = str(int(amount))

	# Determine text type - check if this is a weakpoint hit during crit window
	var is_weakpoint = is_crit and in_crit_window
	if is_weakpoint:
		combat_text.type = 2  # TextType.WEAKPOINT
	elif is_crit:
		combat_text.type = 1  # TextType.CRIT
	else:
		combat_text.type = 0  # TextType.NORMAL

	# Position: spawn behind dummy (opposite side from player)
	# This keeps damage numbers from overlapping weakpoints/crit windows
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var spawn_pos = global_position
	if player:
		var direction_from_player = (global_position - player.global_position).normalized()
		# Spawn 40px behind dummy (away from player)
		spawn_pos = global_position + direction_from_player * 40

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)

	# Trigger spin animation
	trigger_spin()

func trigger_spin() -> void:
	"""Start spin animation"""
	if not sprite:
		return

	is_spinning = true
	spin_timer = 0.0
	sprite.play("spin")

func _on_animation_finished() -> void:
	"""When spin animation completes, return to idle"""
	if sprite and sprite.animation == "spin":
		sprite.play("idle")

func start_crit_window(difficulty: float = 1.0) -> void:
	"""Start crit window - dummy version (simpler than Enemy)"""
	if in_crit_window:
		return

	in_crit_window = true

	# Change to subtle white for crit window
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)
		# Tell HitFlash the new base color
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(Color(1.0, 1.0, 1.05, 1.0))

	# Scale up animation - ONLY SPRITE, not collision box!
	# Sprite always starts at Vector2.ONE (base scale)
	var base_sprite_scale = Vector2.ONE
	var target_sprite_scale = base_sprite_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER
	if sprite:
		var scale_tween = create_tween()
		scale_tween.tween_property(sprite, "scale", target_sprite_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
		z_index = Constants.CRIT_WINDOW_Z_INDEX

		await scale_tween.finished
	else:
		print("⚠️ TrainingDummy: No sprite to scale!")

	# Spawn weakpoints (simplified - just spawn 1 for practice)
	spawn_weakpoints()

	# Start window timer (4 seconds default)
	var timer = Timer.new()
	timer.wait_time = 4.0 / difficulty
	timer.one_shot = true
	timer.timeout.connect(_on_crit_window_timeout)
	add_child(timer)
	timer.start()

func spawn_weakpoints() -> void:
	"""Spawn weakpoints based on player level (1-3 weakpoints, sectioned)"""

	# Get player level to determine number of weakpoints
	var player_level = CharacterStats.level
	var num_weakpoints = 1

	# Level cap is 30, no stat gains past 25
	# Breakpoints: 1-10 = 1 WP, 11-20 = 2 WP, 21+ = 3 WP
	if player_level >= 21:
		num_weakpoints = 3
	elif player_level >= 11:
		num_weakpoints = 2
	else:
		num_weakpoints = 1

	print("🎯 Training Dummy: Player level %d → spawning %d weakpoint(s)" % [player_level, num_weakpoints])

	# Calculate sprite bounds for random positioning within sections
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_pos = sprite.position  # Local position relative to dummy root

	# LPC sprites are 64x64, sprite is CENTERED (centered = true)
	# Character occupies roughly 32x64 in center of the sprite
	var sprite_width = 32.0 * sprite_scale.x
	var sprite_height = 64.0 * sprite_scale.y

	# Divide into 3 equal sections (in local space)
	var section_height = sprite_height / 3.0
	var sprite_top = sprite_pos.y - (sprite_height / 2.0)

	# Define the 3 sections with their bounds
	var sections = [
		{
			"name": "upper",
			"y_min": sprite_top,
			"y_max": sprite_top + section_height
		},
		{
			"name": "mid",
			"y_min": sprite_top + section_height,
			"y_max": sprite_top + 2.0 * section_height
		},
		{
			"name": "lower",
			"y_min": sprite_top + 2.0 * section_height,
			"y_max": sprite_top + 3.0 * section_height
		}
	]

	# Shuffle sections so we pick random ones
	sections.shuffle()

	var chosen_positions = []

	# Pick exactly 1 weakpoint from each of the first N sections
	for i in range(min(num_weakpoints, sections.size())):
		var section = sections[i]

		# Generate random position within this section's bounds
		# Use 80% of width to avoid edges (10% margin on each side)
		var margin_x = sprite_width * 0.1
		var random_x = randf_range(-sprite_width / 2.0 + margin_x, sprite_width / 2.0 - margin_x)

		# Different margins for different sections
		var random_y = 0.0
		if section["name"] == "upper" or section["name"] == "lower":
			# Top and bottom sections: 25% margin on top/bottom
			var margin_y = section_height * 0.25
			random_y = randf_range(section["y_min"] + margin_y, section["y_max"] - margin_y)
		else:
			# Middle section: no margin
			random_y = randf_range(section["y_min"], section["y_max"])

		var random_pos = Vector2(random_x, random_y)

		chosen_positions.append(random_pos)

		print("   🎯 Picked weakpoint in %s section at %s" % [section["name"], random_pos])

	# Spawn weakpoints
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(chosen_positions.size()):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		# Set blood theme for training dummy (has blood!)
		weakpoint.color_theme = "blood"

		# ✨ Weakpoints are children of ROOT, positions are in root's local space
		weakpoint.position = chosen_positions[i]
		weakpoint.z_index = 150
		# ✨ Make weakpoints 3x larger (300% bigger)
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 3.0

		# Random rotation for dynamic look
		weakpoint.rotation = randf_range(-PI, PI)

		# Connect weakpoint signals
		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed)

		add_child(weakpoint)
		weakpoints.append(weakpoint)

func _on_weakpoint_hit(weakpoint) -> void:
	"""Handle weakpoint being hit - deal damage and show combat text"""
	# Calculate crit damage using player's base damage
	var base_damage = CharacterStats.get_base_damage()
	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER

	# Deal damage with crit flag
	take_damage(crit_damage, true)

	# Emit signal for any listeners
	emit_signal("weakpoint_hit_success")

func _on_weakpoint_destroyed(weakpoint) -> void:
	"""Handle weakpoint destruction - end crit window when all destroyed"""
	print("🎯 TrainingDummy._on_weakpoint_destroyed() CALLED")
	print("   - Weakpoint array size: %d" % weakpoints.size())

	# Count how many weakpoints are left
	var remaining_weakpoints = 0
	for wp in weakpoints:
		if is_instance_valid(wp):
			print("   - Checking weakpoint: is_destroyed=%s" % wp.is_destroyed)
			if not wp.is_destroyed:
				remaining_weakpoints += 1

	print("   - Remaining weakpoints: %d" % remaining_weakpoints)

	# If all weakpoints destroyed, end crit window early
	if remaining_weakpoints == 0:
		print("✅ All weakpoints destroyed! Ending crit window early")
		end_crit_window()
	else:
		print("⏳ Still have %d weakpoints remaining" % remaining_weakpoints)

func _on_crit_window_timeout() -> void:
	"""Crit window expired - return to normal"""
	end_crit_window()

func end_crit_window() -> void:
	"""End crit window and return dummy to normal size"""
	if not in_crit_window:
		return

	# ✨ DON'T set in_crit_window = false yet!
	# Wait until tween finishes to prevent overlapping crit windows

	# Remove any remaining weakpoints
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			weakpoint.queue_free()
	weakpoints.clear()

	# Return to normal size and color - ONLY SPRITE, not collision box!
	if sprite:
		sprite.modulate = original_modulate
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(original_modulate)

		var base_sprite_scale = Vector2.ONE  # Sprite base scale is always ONE
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "scale", base_sprite_scale, 0.3)
		tween.tween_property(self, "z_index", 0, 0.3)

		# ✨ Wait for tween to finish BEFORE clearing the flag
		await tween.finished

	# ✨ NOW it's safe to clear the flag - prevents new crit windows during scale-down
	in_crit_window = false

	# Emit completion signal
	emit_signal("crit_window_complete", 0)

## Debug Visualization (F3)
func draw_debug_shapes_world(world_container: Node2D) -> Node2D:
	"""Draw debug shapes for training dummy in world space"""

	# Create temporary container for this dummy's debug shapes
	var dummy_debug = Node2D.new()
	dummy_debug.name = "DummyDebug_" + name
	world_container.add_child(dummy_debug)

	# Draw static collision shape (green - physics body)
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			var rect_shape = collision.shape as RectangleShape2D
			var rect_pos = collision.global_position
			var rect = draw_debug_rect_world(rect_pos, rect_shape.size * scale, Color.GREEN)
			dummy_debug.add_child(rect)

	# Draw click area (cyan - clickable area for attacks)
	# This is just for mouse click detection, NOT the actual attack hitbox!
	# Actual attacks use the player's attack cone which is shown in red on the player
	if has_node("ClickArea"):
		var click_area_node = get_node("ClickArea")
		# Look for CollisionShape2D child
		for child in click_area_node.get_children():
			if child is CollisionShape2D:
				var area_collision = child as CollisionShape2D
				if area_collision.shape is CircleShape2D:
					var circle_shape = area_collision.shape as CircleShape2D
					var circle_pos = area_collision.global_position
					var circle = draw_debug_circle_world(circle_pos, circle_shape.radius * scale.x, Color.CYAN)
					dummy_debug.add_child(circle)
					break

	# ✨ Draw PURPLE boxes - 3 equal sections for weakpoint placement visualization
	if sprite:
		var sprite_scale = sprite.scale
		var sprite_pos = sprite.global_position

		# LPC sprites are 64x64, sprite is CENTERED (centered = true)
		# Character occupies roughly 32x64 in center of the sprite
		var sprite_width = 32.0 * sprite_scale.x
		var sprite_height = 64.0 * sprite_scale.y

		# Divide into 3 equal sections
		var section_height = sprite_height / 3.0

		# Calculate the top of the sprite (sprite is centered)
		var sprite_top = sprite_pos.y - (sprite_height / 2.0)

		# Draw 3 boxes: upper, mid, lower
		var sections = [
			{"name": "upper", "y": sprite_top + section_height / 2.0},
			{"name": "mid", "y": sprite_top + section_height * 1.5},
			{"name": "lower", "y": sprite_top + section_height * 2.5}
		]

		for section in sections:
			var section_center = Vector2(sprite_pos.x, section["y"])
			var section_size = Vector2(sprite_width, section_height)
			var purple_box = draw_debug_rect_world(section_center, section_size, Color.MAGENTA)
			dummy_debug.add_child(purple_box)

	# Draw weakpoint hitboxes (red - if in crit window)
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint) and not weakpoint.is_destroyed:
			if weakpoint.has_node("CollisionShape2D"):
				var wp_collision = weakpoint.get_node("CollisionShape2D")
				if wp_collision.shape is CircleShape2D:
					var wp_shape = wp_collision.shape as CircleShape2D
					var wp_pos = weakpoint.global_position
					var wp_circle = draw_debug_circle_world(wp_pos, wp_shape.radius, Color.RED)
					dummy_debug.add_child(wp_circle)

	return dummy_debug

func draw_debug_circle_world(center: Vector2, radius: float, color: Color) -> Line2D:
	"""Draw a circle in world space for debug visualization"""
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color

	var segments = 32
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)

	return line

func draw_debug_rect_world(center: Vector2, size: Vector2, color: Color) -> Line2D:
	"""Draw a rectangle in world space for debug visualization"""
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color

	# Draw rectangle outline
	var half_size = size / 2.0
	line.add_point(center + Vector2(-half_size.x, -half_size.y))  # Top-left
	line.add_point(center + Vector2(half_size.x, -half_size.y))   # Top-right
	line.add_point(center + Vector2(half_size.x, half_size.y))    # Bottom-right
	line.add_point(center + Vector2(-half_size.x, half_size.y))   # Bottom-left
	line.add_point(center + Vector2(-half_size.x, -half_size.y))  # Back to top-left

	return line
