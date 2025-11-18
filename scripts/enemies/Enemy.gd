extends CharacterBody2D

# Enemy stats
@export var max_health: float = 500.0
@export var current_health: float = 500.0
@export var base_damage: float = 10.0

# Enemy level and progression
@export var enemy_level: int = 1
@export var xp_reward_base: int = 10  # Base XP, scales with level
var xp_reward: int = 10  # Actual XP granted
@export var gold_drop_base: int = 5  # Base gold drop, scales with level
var gold_drop: int = 5  # Actual gold dropped

# References
@onready var health_bar: Control = $HealthBar
@onready var sprite: CanvasItem = $Sprite2D  # Can be Sprite2D or AnimatedSprite2D
@onready var click_area: Area2D = $Area2D

# Crit window state (minimal - manager owns lifecycle)
var in_crit_window: bool = false  # Simple flag set by grow/shrink methods
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE  # Store original difficulty color
var weakpoints: Array = []  # Just for visual rendering
var is_dying: bool = false

# Signals for CritWindowManager
signal weakpoint_spawned()  # Emitted when a weakpoint is created
signal weakpoint_destroyed(weakpoint: Node)  # Emitted when a weakpoint is destroyed
signal died()  # Emitted when enemy dies
signal damage_taken(damage: float, is_crit: bool)  # For unified feedback

func _ready() -> void:
	# Set collision layers: enemies on layer 1, detect layers 1 (other entities) and 2 (obstacles like trees)
	collision_layer = 1
	collision_mask = 3  # Bitmask: 1 (layer 1) + 2 (layer 2) = 3

	# Scale stats by enemy level
	max_health = Constants.ENEMY_BASE_HEALTH * pow(Constants.ENEMY_HEALTH_SCALING, enemy_level - 1)  # ~500 HP at level 10
	base_damage = Constants.ENEMY_BASE_DAMAGE * pow(Constants.ENEMY_DAMAGE_SCALING, enemy_level - 1)
	xp_reward = int(xp_reward_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))  # Same scaling as XP

	# Debug gold drop calculation
	DebugConfig.debug_log("💰 Enemy initialized - Level: %d, gold_drop_base: %d, gold_drop: %d" % [enemy_level, gold_drop_base, gold_drop])

	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	original_scale = scale  # For general reference

	# ✨ Store original difficulty color (set by GameWorld)
	await get_tree().process_frame  # Wait one frame for GameWorld to set color
	original_modulate = self.modulate

	# ✨ Store sprite's original scale (for crit window scaling)
	# Sprite always starts at Vector2.ONE, but store it just in case
	if sprite:
		sprite.scale = Vector2.ONE  # Ensure sprite starts at base scale

	# Debug: Check what sprite node we have
	if not sprite:
		push_error("❌ Enemy sprite is null! Cannot load skeleton animation.")
		return
	
	# Create animated skeleton sprite
	if sprite:
		# Load ALL sprite sheets - walk, attack, and hurt
		const SKELETON_WALK_PATH = "res://assets/characters/BODY_skeleton_walk.png"
		const SKELETON_SLASH_PATH = "res://assets/characters/BODY_skeleton_slash.png"
		const SKELETON_HURT_PATH = "res://assets/characters/BODY_skeleton_hurt.png"
		
		var walk_tex: Texture2D = null
		var slash_tex: Texture2D = null
		var hurt_tex: Texture2D = null

		# Try to load walking sprite
		if ResourceLoader.exists(SKELETON_WALK_PATH):
			walk_tex = ResourceLoader.load(SKELETON_WALK_PATH, "Texture2D")
		
		# Try to load attack sprite
		if ResourceLoader.exists(SKELETON_SLASH_PATH):
			slash_tex = ResourceLoader.load(SKELETON_SLASH_PATH, "Texture2D")

		# Try to load hurt sprite
		if ResourceLoader.exists(SKELETON_HURT_PATH):
			hurt_tex = ResourceLoader.load(SKELETON_HURT_PATH, "Texture2D")
		
		if walk_tex:
			# Store old sprite properties
			var old_position = sprite.position
			var old_scale = sprite.scale
			var old_z_index = sprite.z_index
			
			# Create new AnimatedSprite2D
			var anim_sprite = AnimatedSprite2D.new()
			anim_sprite.name = "Sprite"
			anim_sprite.centered = true
			anim_sprite.position = old_position
			anim_sprite.scale = old_scale
			anim_sprite.modulate = Color.WHITE  # ✨ WHITE, not red!
			anim_sprite.z_index = old_z_index
			anim_sprite.visible = true
			
			# Setup skeleton animations from ALL sprite sheets
			setup_skeleton_animations(anim_sprite, walk_tex, slash_tex, hurt_tex)
			
			# Verify sprite_frames was set
			if not anim_sprite.sprite_frames:
				push_error("❌ Failed to setup sprite_frames!")
				return

			# Remove old sprite and add animated one
			var old_sprite = sprite
			remove_child(old_sprite)
			old_sprite.queue_free()

			add_child(anim_sprite)
			sprite = anim_sprite

			# Verify animation exists before playing
			if anim_sprite.sprite_frames.has_animation("idle_down"):
				anim_sprite.play("idle_down")
			else:
				push_error("❌ idle_down animation not found!")

			# ✨ FIX: Refresh HitFlash sprite reference after conversion
			if has_node("HitFlash"):
				await get_tree().process_frame  # Wait for scene tree to update
				var hit_flash = get_node("HitFlash")
				hit_flash.sprite = anim_sprite  # Directly set the new sprite
		else:
			# Fallback to red square if texture fails to load
			push_error("⚠️ Failed to load skeleton texture, using RED fallback")
			if sprite is Sprite2D:
				var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
				img.fill(Color.RED)
				sprite.texture = ImageTexture.create_from_image(img)
				sprite.visible = true
				print("   ✅ Red fallback texture set")
			else:
				push_error("   ❌ Sprite is not Sprite2D, cannot set fallback texture")

	
	# Ensure collision shape matches visual
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			# Match collision to sprite size
			collision.shape.size = Vector2(32, 56)
	
	# Add to group
	add_to_group(Constants.GROUP_ENEMIES)
	
	# Add level display
	update_level_display()
	
	# Connect click area
	if click_area:
		click_area.input_event.connect(_on_click_area_input)

func setup_skeleton_animations(anim_sprite: AnimatedSprite2D, walk_tex: Texture2D, slash_tex: Texture2D, hurt_tex: Texture2D = null) -> void:
	"""Setup skeleton animations from separate walk, attack, and hurt sprite sheets"""
	var sprite_frames = SpriteFrames.new()
	
	# Setup WALKING animations from walk texture (9 frames per row)
	if walk_tex:
		var walk_img = walk_tex.get_image()

		# Walk animations - 4 rows (UP, LEFT, DOWN, RIGHT), 9 frames each
		create_skeleton_animation(sprite_frames, walk_img, "walk_up", 0, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_left", 1, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_down", 2, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_right", 3, 9, 8.0)

		# Idle animations - use middle frame (frame 4 of 9) for neutral pose
		create_skeleton_animation(sprite_frames, walk_img, "idle_up", 0, 1, 1.0, true, 4)
		create_skeleton_animation(sprite_frames, walk_img, "idle_left", 1, 1, 1.0, true, 4)
		create_skeleton_animation(sprite_frames, walk_img, "idle_down", 2, 1, 1.0, true, 4)
		create_skeleton_animation(sprite_frames, walk_img, "idle_right", 3, 1, 1.0, true, 4)

	# Setup ATTACK animations from slash texture (6 frames per row)
	if slash_tex:
		var slash_img = slash_tex.get_image()

		# Attack animations - 4 rows (UP, LEFT, DOWN, RIGHT), 6 frames each
		create_skeleton_animation(sprite_frames, slash_img, "attack_up", 0, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_left", 1, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_down", 2, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_right", 3, 6, 12.0, false)

	# Setup HURT animation from hurt texture (6 frames, single row)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()

		# Hurt animation - 1 row, 6 frames (getting hit and falling)
		create_skeleton_animation(sprite_frames, hurt_img, "hurt", 0, 6, 10.0, false)

	anim_sprite.sprite_frames = sprite_frames

func create_skeleton_animation(sprite_frames: SpriteFrames, skeleton_img: Image, anim_name: String, row: int, frame_count: int, fps: float, loop: bool = true, start_frame: int = 0) -> void:
	"""Create animation from skeleton spritesheet
	start_frame: which frame to start extracting from (useful for idle = middle frame)
	"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)
	
	for i in range(frame_count):
		var frame_idx = start_frame + i
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(skeleton_img, Rect2i(frame_idx * 64, row * 64, 64, 64), Vector2i(0, 0))
		
		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

func update_level_display() -> void:
	"""Show enemy level on sprite"""
	if enemy_level > 1:
		# Create level label
		var level_label = Label.new()
		level_label.text = "Lv.%d" % enemy_level
		level_label.add_theme_font_size_override("font_size", 12)
		level_label.add_theme_color_override("font_color", Color.YELLOW)
		level_label.add_theme_color_override("font_outline_color", Color.BLACK)
		level_label.add_theme_constant_override("outline_size", 2)
		level_label.position = Vector2(-15, -40)
		level_label.z_index = 500
		add_child(level_label)

func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Let Player handle ALL clicks (including crit window)
	# This prevents double-damage bugs where both Player and Enemy handle the same click
	return

func take_damage(amount: float, is_crit: bool = false) -> void:
	if is_dying:
		return
	
	# Validate amount
	if is_nan(amount) or is_inf(amount) or amount < 0:
		print("ERROR: Invalid damage amount: ", amount)
		return
	
	if current_health <= 0:
		return
	
	current_health -= amount
	current_health = max(current_health, 0.0)

	DebugConfig.log_combat("Enemy hit! Damage: %d (Crit: %s) | Health: %d/%d" % [amount, is_crit, current_health, max_health])
	
	# ✨ NEW: Emit signal for player to handle feedback
	damage_taken.emit(amount, is_crit)
	
	# ✨ NEW: Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# ✨ NEW: Spawn combat text
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	# Set damage text
	combat_text.text = str(int(amount))

	# Determine text type - check if this is a weakpoint hit
	var is_weakpoint = is_crit and in_crit_window
	if is_weakpoint:
		combat_text.type = 2  # TextType.WEAKPOINT
	elif is_crit:
		combat_text.type = 1  # TextType.CRIT
		# 🔊 Play critical hit sound (non-weakpoint crits only)
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_critical_hit_sound(global_position, -3.0)
	else:
		combat_text.type = 0  # TextType.NORMAL

	# Position: spawn based on player's facing direction for better visibility
	# Adjustments: left(-50x,-50y), right(0x,-50y), up(0x,-50y), down(no adjustment)
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var spawn_pos = global_position
	if player:
		# Get direction from player to enemy to determine facing
		var direction_to_enemy = (global_position - player.global_position).normalized()

		# Determine primary facing direction
		var offset = Vector2.ZERO
		if abs(direction_to_enemy.x) > abs(direction_to_enemy.y):
			# Horizontal facing (left or right)
			if direction_to_enemy.x < 0:
				# Facing LEFT (enemy to the left of player)
				offset = Vector2(-50, -50)
			else:
				# Facing RIGHT (enemy to the right of player)
				offset = Vector2(0, -50)
		else:
			# Vertical facing (up or down)
			if direction_to_enemy.y < 0:
				# Facing UP (enemy above player)
				offset = Vector2(0, -50)
			else:
				# Facing DOWN (enemy below player)
				offset = Vector2(0, 0)  # Good as is

		spawn_pos = global_position + offset

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)
	
	# ✨ NEW: Play hit sound
	# NOTE: Weakpoint sounds are handled in weakpoint.gd directly
	# Only play sounds here for non-weakpoint hits
	if not is_weakpoint:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			# Get player's weapon type for weapon-specific sounds
			var weapon_type = ""
			if CharacterStats.equipped_weapon:
				weapon_type = CharacterStats.equipped_weapon.weapon_type

			if is_crit:
				# Critical hit sound already played above at line 286
				pass
			else:
				sound_manager.play_normal_hit_sound(global_position, -8.0, weapon_type)

			# Play skeleton hurt reaction sound (for all hit types)
			sound_manager.play_skeleton_hurt_sound(global_position, -8.0)
	
	# ✨ NEW: Trigger hit flash locally (always works)
	if has_node("HitFlash"):
		get_node("HitFlash").flash(is_crit)

	if current_health <= 0:
		die()

func grow_for_crit_window(difficulty: float = 1.0) -> void:
	"""Visual effect: grow sprite and spawn weakpoints (called by CritWindowManager)"""
	if is_dying:
		push_warning("Enemy is dying - skipping crit window visual")
		return

	print("🔍 [CRIT WINDOW] grow_for_crit_window() called")
	print("     Timestamp: ", Time.get_ticks_msec())

	in_crit_window = true  # Set flag for local checks

	DebugConfig.log_combat("🌟 Growing sprite for crit window")
	DebugConfig.log_combat("   Current scale: %s (original: %s)" % [scale, original_scale])
	DebugConfig.log_combat("   Current color: %s" % (sprite.modulate if sprite else "no sprite"))
	
	# ✨ NEW: Play crit window opening sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, global_position, -3.0)
	
	# ✨ FIX: Override BOTH parent and sprite modulate for SUBTLE white
	# 50% less bright - more comfortable!
	self.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Reset parent to neutral
	
	# Change to SUBTLE WHITE for crit window (bone spurs will still pop!)
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)  # Barely brighter than normal (subtle!)
		print("   ✅ Changed sprite color to SUBTLE WHITE: %s" % sprite.modulate)
		print("   ✅ Reset parent modulate to neutral: %s" % self.modulate)
		
		# Tell HitFlash the new base color
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(Color(1.0, 1.0, 1.05, 1.0))
			print("   ✅ Told HitFlash about SUBTLE WHITE color")
	else:
		print("   ❌ No sprite found!")
	
	# ✨ FIX: Check if we're already at target scale (prevents no-grow bug)
	# Sprite always starts at Vector2.ONE (base scale)
	var base_sprite_scale = Vector2.ONE
	var target_sprite_scale = base_sprite_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER

	# Check sprite scale, not root node scale (since we only scale sprite now)
	var current_sprite_scale = sprite.scale if sprite else Vector2.ONE
	if current_sprite_scale.x >= target_sprite_scale.x * Constants.CRIT_WINDOW_SCALE_THRESHOLD:  # If already 90% of target, skip growth
		print("   ⚠️ Already at target scale (%s), skipping growth animation" % current_sprite_scale)
		# Just spawn weakpoints immediately
		spawn_weakpoints()
	else:
		print("   Scaling sprite from %s to %s" % [current_sprite_scale, target_sprite_scale])

		# ✨ CHANGED: Only scale the SPRITE, not the collision box!
		# This prevents collision/pathing issues while still showing visual growth
		if sprite:
			print("🔍 [SPRITE SCALE] Starting GROW tween - current scale: %s, target: %s" % [sprite.scale, target_sprite_scale])
			var scale_tween = create_tween()
			scale_tween.set_parallel(false)
			scale_tween.tween_property(sprite, "scale", target_sprite_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
			z_index = Constants.CRIT_WINDOW_Z_INDEX

			# ✨ NEW: Player can attack during growth animation!
			# Weakpoints will spawn after growth completes

			await scale_tween.finished

			print("   ✅ [SPRITE SCALE] Sprite GROW animation complete - final sprite scale: %s" % sprite.scale)
		else:
			print("   ⚠️ No sprite to scale!")

		# Spawn weakpoints AFTER growth
		spawn_weakpoints()

	print("✅ [CRIT WINDOW] Grow complete, weakpoints active")

func spawn_weakpoints() -> void:
	# Calculate weakpoint count based on CURRENT PLAYER level (when crit triggers, not when enemy spawned)
	# Level cap is 30, no stat gains past 25
	var player_level = CharacterStats.level
	var num_weakpoints = 1  # Default to 1
	if player_level >= 21:
		num_weakpoints = 3  # Level 21+: All 3 weakpoints
	elif player_level >= 11:
		num_weakpoints = 2  # Level 11-20: 2 weakpoints
	else:
		num_weakpoints = 1  # Level 1-10: 1 weakpoint

	# print("🎯 Calculating weakpoints: Player level %d → %d weakpoints" % [player_level, num_weakpoints])

	# Calculate sprite bounds for random positioning within sections
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_pos = sprite.position  # Local position relative to enemy root

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

	# Slightly smaller scale for better fit
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(chosen_positions.size()):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		# Set bone theme for skeletons (no blood!)
		weakpoint.color_theme = "bone"

		# ✨ Weakpoints are children of ROOT, positions are in root's local space
		weakpoint.position = chosen_positions[i]
		# ✨ Make weakpoints 3x larger (300% bigger)
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 3.0

		# ✨ RANDOM ROTATION for dynamic look!
		weakpoint.rotation = randf_range(-PI, PI)

		# Connect weakpoint signals - just forward to manager
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed_local)

		add_child(weakpoint)
		weakpoints.append(weakpoint)

		# Emit signal so CritWindowManager can track it
		weakpoint_spawned.emit()
	
	# 🔍 DEBUG: Show all possible positions on the blown-up sprite
	# print("🔍 DEBUG: Spawned weakpoints, triggering debug visualization")
	# queue_redraw()  # Trigger _draw() to show debug circles

# 🔍 DEBUG VISUALIZATION - Shows where all 17 positions are!
func _draw() -> void:
	pass
	# Only draw if we have weakpoints spawned
	# if weakpoints.is_empty():
	# 	return

	# print("🔍 DEBUG: Drawing position circles (17 red dots + 3 green dots)")

	# Draw circles at ALL 17 possible positions (optimized spread)
	# var position_pool = [
	# 	# Upper (5)
	# 	Vector2(0, -14), Vector2(-6, -11), Vector2(6, -11),
	# 	Vector2(-8, -6), Vector2(8, -6),
	# 	# Mid (9)
	# 	Vector2(0, -3), Vector2(-6, -2), Vector2(6, -2),
	# 	Vector2(-5, 1), Vector2(5, 1), Vector2(0, 3),
	# 	Vector2(-5, 5), Vector2(5, 5), Vector2(0, 7),
	# 	# Lower (3)
	# 	Vector2(-4, 10), Vector2(4, 10), Vector2(0, 12)
	# ]

	# Draw small red circles at each possible position
	# for pos in position_pool:
	# 	draw_circle(pos, 3, Color(1, 0, 0, 0.7))  # Red

	# Draw larger green circles at the 3 chosen positions
	# for weakpoint in weakpoints:
	# 	if is_instance_valid(weakpoint):
	# 		draw_circle(weakpoint.position, 5, Color(0, 1, 0, 0.9))  # Bright green

	# print("🔍 DEBUG: Drew %d red circles and %d green circles" % [position_pool.size(), weakpoints.size()])

# Keep redrawing while in crit window
func _process(delta: float) -> void:
	if in_crit_window and not weakpoints.is_empty():
		queue_redraw()  # Continuously redraw while weakpoints are active

func _on_weakpoint_destroyed_local(weakpoint) -> void:
	"""Local handler - just forward to manager"""
	print("🔍 [ENEMY] Weakpoint destroyed locally - emitting signal to manager")

	# Play victory sound if it's the last one (manager will know)
	# We can check locally by counting remaining weakpoints
	var remaining = 0
	for wp in weakpoints:
		if is_instance_valid(wp) and not wp.is_destroyed:
			remaining += 1

	# Emit signal for manager to handle
	weakpoint_destroyed.emit(weakpoint)

func shrink_after_crit_window() -> void:
	"""Visual effect: shrink sprite and cleanup weakpoints (called by CritWindowManager)"""
	print("🔚 [CRIT WINDOW] shrink_after_crit_window() called")

	in_crit_window = false  # Clear flag

	# Don't manually free weakpoints - they will free themselves after their explosion animations
	# Just clear the array reference
	weakpoints.clear()

	# Reset HitFlash
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("reset"):
			hit_flash.reset()
		hit_flash.set_base_color(Color.WHITE)

	# Restore original difficulty color (parent modulate)
	self.modulate = original_modulate
	print("   ✅ Restored parent modulate: %s" % self.modulate)

	# Change sprite back to white (normal enemy color)
	if sprite:
		sprite.modulate = Color.WHITE

	# Scale SPRITE back to base (not collision box)
	if is_instance_valid(self) and sprite:
		var base_sprite_scale = Vector2.ONE
		print("🔍 [SPRITE SCALE] Starting shrink tween - current scale: %s, target: %s" % [sprite.scale, base_sprite_scale])
		var tween = create_tween()
		tween.tween_property(sprite, "scale", base_sprite_scale, 0.25)

		# Wait for tween to finish, then FORCE final state
		await get_tree().create_timer(0.26).timeout

		if is_instance_valid(self) and sprite:
			sprite.scale = base_sprite_scale
			z_index = 0
			sprite.modulate = Color.WHITE
			print("✅ [SPRITE SCALE] Enemy sprite scaled back to normal: %s" % sprite.scale)

func die() -> void:
	if is_dying:
		return
	
	is_dying = true
	# print("\n☠️ ===== ENEMY DEATH =====")
	# print("Enemy name: ", name)
	# print("Enemy level: ", enemy_level)
	# print("Position: ", global_position)
	# print("Health: ", current_health)
	# print("Is in tree: ", is_inside_tree())

	# Grant XP to player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("gain_experience"):
		player.gain_experience(xp_reward)
		# print("💰 Granted ", xp_reward, " XP to player")

	# Grant gold to player
	DebugConfig.debug_log("💰 Attempting to drop %d gold (gold_drop_base=%d, enemy_level=%d)" % [gold_drop, gold_drop_base, enemy_level])
	CharacterStats.add_gold(gold_drop)
	DebugConfig.debug_log("💰 CharacterStats.add_gold() called - Player total gold now: %d" % CharacterStats.gold)
	
	# ✨ NEW: Play death sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.ENEMY_DEATH, global_position, -3.0)
	
	# ✨ Play death animation (hurt animation) and wait for it to complete
	var anim_sprite = sprite as AnimatedSprite2D
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("hurt"):
		print("   🎬 Playing death animation...")
		anim_sprite.play("hurt")
		# Wait for the full animation to finish
		await anim_sprite.animation_finished
		print("   ✅ Death animation complete")
	else:
		# Fallback if animation doesn't exist
		print("   ⚠️ No hurt animation, waiting 0.6s...")
		await get_tree().create_timer(0.6).timeout
	
	# Emit died signal - CritWindowManager will handle cleanup if needed
	died.emit()

	# print("Calling queue_free()...")
	queue_free()
	# print("Enemy queued for deletion")
	# print("===== END DEATH =====\n")

## Debug Visualization
func draw_debug_shapes(debug_container: Node2D) -> void:
	# OLD VERSION - draws in player space (rotates)
	# Kept for backwards compatibility but not used
	pass

func draw_debug_shapes_world(world_container: Node2D) -> Node2D:
	# NEW VERSION - draws in world space (doesn't rotate)
	# RETURNS the container node for proper cleanup tracking
	
	# Create temporary container for this enemy's debug shapes
	var enemy_debug = Node2D.new()
	enemy_debug.name = "EnemyDebug_" + name
	world_container.add_child(enemy_debug)
	
	# Draw collision shape
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			var rect_shape = collision.shape as RectangleShape2D
			var rect = draw_debug_rect_world(global_position, rect_shape.size * scale, rotation, Color.GREEN)
			enemy_debug.add_child(rect)
	
	# Draw click area
	if has_node("Area2D/CollisionShape2D"):
		var area_collision = get_node("Area2D/CollisionShape2D")
		if area_collision.shape is RectangleShape2D:
			var rect_shape = area_collision.shape as RectangleShape2D
			var rect = draw_debug_rect_world(area_collision.global_position, rect_shape.size * scale, rotation, Color.CYAN)
			enemy_debug.add_child(rect)

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
			var purple_box = draw_debug_rect_world(section_center, section_size, 0.0, Color.MAGENTA)
			enemy_debug.add_child(purple_box)

	# Draw weakpoint hitboxes
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint) and weakpoint.has_method("draw_debug_hitbox_world"):
			weakpoint.draw_debug_hitbox_world(enemy_debug)
	
	return enemy_debug  # Return for tracking

func draw_debug_rect_world(center: Vector2, size: Vector2, angle: float, color: Color) -> Line2D:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color
	line.z_index = 1000
	
	var half_size = size / 2.0
	
	# Create corners
	var corners = [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	]
	
	# Rotate and translate corners
	for i in range(4):
		var rotated = corners[i].rotated(angle)
		line.add_point(center + rotated)
	
	# Close the rectangle
	var rotated = corners[0].rotated(angle)
	line.add_point(center + rotated)
	
	return line
