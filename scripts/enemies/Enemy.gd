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

# Crit window state
var in_crit_window: bool = false
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE  # ✨ Store original difficulty color
var weakpoints: Array = []
var weakpoints_destroyed: int = 0
var num_weakpoints: int = 1  # Will be calculated based on enemy_level in _ready()
var spam_protection_active: bool = false
var window_duration: float = 4.0
var window_timer: Timer = null
var is_dying: bool = false

# ✨ NEW: Track if killed by weakpoint during crit window
var killed_by_weakpoint_in_window: bool = false

# ✨ Crit immunity system (prevents crit window stalemates)
var crit_immune_until: float = 0.0  # Timestamp when immunity ends
const CRIT_IMMUNITY_DURATION: float = 4.0  # 4 seconds of immunity after window

# Signals
signal weakpoint_hit_success()
signal crit_window_complete(weakpoints_destroyed: int)
signal died()
signal damage_taken(damage: float, is_crit: bool)  # ✨ NEW: For unified feedback

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
	health_bar.update_health(current_health, max_health)
	original_scale = scale
	
	# ✨ Store original difficulty color (set by GameWorld)
	await get_tree().process_frame  # Wait one frame for GameWorld to set color
	original_modulate = self.modulate

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
	else:
		combat_text.type = 0  # TextType.NORMAL

	# Position: spawn in front of player, halfway between player and enemy
	# This keeps it visible but not overlapping the enemy sprite
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var spawn_pos = global_position
	if player:
		var direction_to_enemy = (global_position - player.global_position).normalized()
		var distance = player.global_position.distance_to(global_position)
		# Spawn 40% of the way toward enemy (closer to player, in front of player)
		spawn_pos = player.global_position + direction_to_enemy * min(distance * 0.4, 60)

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)
	
	# ✨ NEW: Play hit sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		if is_weakpoint:
			sound_manager.play_sound(sound_manager.SoundType.HIT_WEAKPOINT, global_position, -5.0)
		elif is_crit:
			sound_manager.play_sound(sound_manager.SoundType.HIT_CRIT, global_position, -5.0)
		else:
			sound_manager.play_sound(sound_manager.SoundType.HIT_NORMAL, global_position, -8.0)
	
	# ✨ NEW: Trigger hit flash locally (always works)
	if has_node("HitFlash"):
		get_node("HitFlash").flash(is_crit)
	
	# ✨ NEW: Track if killed by crit during window
	if current_health <= 0 and is_crit and in_crit_window:
		killed_by_weakpoint_in_window = true
		DebugConfig.log_combat("🎯 Enemy killed by weakpoint during crit window!")
	
	if current_health <= 0:
		die()

func start_crit_window(difficulty: float = 1.0) -> void:
	DebugConfig.log_combat("🔍 start_crit_window called - in_crit_window: %s, is_dying: %s" % [in_crit_window, is_dying])

	if in_crit_window or is_dying:
		DebugConfig.log_combat("⚠️  Crit window blocked: already in window or dying")
		return

	in_crit_window = true
	# ✨ CHANGED: Don't activate spam protection immediately - allow attacks during growth
	spam_protection_active = false
	weakpoints_destroyed = 0
	killed_by_weakpoint_in_window = false  # ✨ NEW: Reset flag

	DebugConfig.log_combat("🌟 Starting crit window")
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
	var target_scale = original_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER

	if scale.x >= target_scale.x * Constants.CRIT_WINDOW_SCALE_THRESHOLD:  # If already 90% of target, skip growth
		print("   ⚠️ Already at target scale, skipping growth animation")
		# Just spawn weakpoints immediately
		spawn_weakpoints()
	else:
		print("   Scaling from %s to %s" % [scale, target_scale])
		
		# ✨ FIX: Store reference to ensure tween isn't garbage collected
		var scale_tween = create_tween()
		scale_tween.set_parallel(false)
		scale_tween.tween_property(self, "scale", target_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
		z_index = Constants.CRIT_WINDOW_Z_INDEX
		
		# ✨ NEW: Player can attack during growth animation!
		# Weakpoints will spawn after growth completes
		
		await scale_tween.finished
		
		print("   ✅ Scale animation complete - final scale: %s" % scale)
		
		# Spawn weakpoints AFTER growth
		spawn_weakpoints()
	
	# ✨ CHANGED: Very short protection after growth (just to prevent double-click)
	spam_protection_active = true
	get_tree().create_timer(Constants.CRIT_WINDOW_SPAM_PROTECTION).timeout.connect(func():
		if is_instance_valid(self) and not is_dying:
			spam_protection_active = false
			print("Weakpoints active!")
	)
	
	# Start timer
	var scaled_duration = window_duration / difficulty
	window_timer = Timer.new()
	window_timer.wait_time = scaled_duration
	window_timer.one_shot = true
	window_timer.timeout.connect(_on_window_timeout)
	add_child(window_timer)
	window_timer.start()

func spawn_weakpoints() -> void:
	# Calculate weakpoint count based on CURRENT PLAYER level (when crit triggers, not when enemy spawned)
	# Level cap is 30, no stat gains past 25
	var player_level = CharacterStats.level
	if player_level >= 21:
		num_weakpoints = 3  # Level 21+: All 3 weakpoints
	elif player_level >= 11:
		num_weakpoints = 2  # Level 11-20: 2 weakpoints
	else:
		num_weakpoints = 1  # Level 1-10: 1 weakpoint

	print("🎯 Calculating weakpoints: Player level %d → %d weakpoints" % [player_level, num_weakpoints])

	# 🎯 SECTIONED POSITION POOL - Organized by body parts!
	# Max 2 weakpoints per section for better spread

	# 🎯 OPTIMIZED POSITIONS - Better spacing, no clustering!
	# 17 well-distributed positions (down from 20)
	# Minimum 8+ pixel spacing between all positions
	
	var upper_positions = [
		# HEAD & SHOULDERS - 5 positions, well-spaced
		Vector2(0, -14),      # Top of skull (crown)
		Vector2(-6, -11),     # Left temple
		Vector2(6, -11),      # Right temple  
		Vector2(-8, -6),      # Left shoulder
		Vector2(8, -6),       # Right shoulder
	]
	
	var mid_positions = [
		# TORSO & ARMS - 9 positions, maximum coverage
		Vector2(0, -3),       # Upper chest (sternum)
		Vector2(-6, -2),      # Left upper ribs
		Vector2(6, -2),       # Right upper ribs
		Vector2(-5, 1),       # Left mid ribs
		Vector2(5, 1),        # Right mid ribs
		Vector2(0, 3),        # Center spine/lower ribs
		Vector2(-5, 5),       # Left hip
		Vector2(5, 5),        # Right hip
		Vector2(0, 7),        # Center pelvis (top)
	]
	
	var lower_positions = [
		# LEGS - 3 positions, clear spacing
		Vector2(-4, 10),      # Left upper leg
		Vector2(4, 10),       # Right upper leg
		Vector2(0, 12),       # Between legs (pelvis bottom)
	]
	
	# 🎲 New distribution: Exactly 1 weakpoint per section, sections chosen randomly
	var chosen_positions = []
	var sections = [
		{"name": "upper", "positions": upper_positions},
		{"name": "mid", "positions": mid_positions},
		{"name": "lower", "positions": lower_positions}
	]

	# Shuffle sections to pick random sections when we have < 3 weakpoints
	sections.shuffle()

	var spots_needed = num_weakpoints  # 1, 2, or 3 based on enemy level
	var positions_per_section = {}

	# Initialize counters
	for section in sections:
		positions_per_section[section["name"]] = 0

	# Minimum distance between weakpoints to prevent overlap (based on hitbox size)
	var min_distance = 40.0  # Buffer to prevent visual overlap (hitbox is 18-35px radius)

	# Pick exactly 1 weakpoint from each of the first N sections (where N = num_weakpoints)
	for i in range(min(spots_needed, sections.size())):
		var section = sections[i]
		var section_name = section["name"]
		var section_positions = section["positions"]

		# Try to find a position that doesn't overlap with already chosen positions
		var random_pos = null
		var attempts = 0
		var max_attempts = 10  # Prevent infinite loop

		while attempts < max_attempts:
			var candidate_pos = section_positions[randi() % section_positions.size()]

			# Check distance to all already-chosen positions
			var is_valid = true
			for chosen_pos in chosen_positions:
				if candidate_pos.distance_to(chosen_pos) < min_distance:
					is_valid = false
					break

			if is_valid:
				random_pos = candidate_pos
				break

			attempts += 1

		# Fallback: if no valid position found after max_attempts, use any random position
		if random_pos == null:
			random_pos = section_positions[randi() % section_positions.size()]
			print("⚠️ Could not find non-overlapping position in %s section, using fallback" % section_name)

		# Add the position!
		chosen_positions.append(random_pos)
		positions_per_section[section_name] = 1

		print("🎯 Picked weakpoint in %s section at %s" % [section_name, random_pos])

	print("📊 Final distribution - Upper: %d | Mid: %d | Lower: %d (Total: %d)" %
		[positions_per_section["upper"], positions_per_section["mid"], positions_per_section["lower"], spots_needed])

	print("🎯 SPAWNING %d WEAKPOINTS for player level %d" % [spots_needed, CharacterStats.level])

	# Slightly smaller scale for better fit
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR
	
	for i in range(chosen_positions.size()):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		# Set bone theme for skeletons (no blood!)
		weakpoint.color_theme = "bone"

		# Position from randomly chosen pool
		weakpoint.position = chosen_positions[i]
		weakpoint.scale = Vector2(counter_scale, counter_scale)

		# ✨ RANDOM ROTATION for dynamic look!
		weakpoint.rotation = randf_range(-PI, PI)

		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed)
		add_child(weakpoint)
		weakpoints.append(weakpoint)
	
	# 🔍 DEBUG: Show all possible positions on the blown-up sprite
	print("🔍 DEBUG: Spawned weakpoints, triggering debug visualization")
	queue_redraw()  # Trigger _draw() to show debug circles

# 🔍 DEBUG VISUALIZATION - Shows where all 17 positions are!
func _draw() -> void:
	# Only draw if we have weakpoints spawned
	if weakpoints.is_empty():
		return
	
	print("🔍 DEBUG: Drawing position circles (17 red dots + 3 green dots)")
	
	# Draw circles at ALL 17 possible positions (optimized spread)
	var position_pool = [
		# Upper (5)
		Vector2(0, -14), Vector2(-6, -11), Vector2(6, -11),
		Vector2(-8, -6), Vector2(8, -6),
		# Mid (9)
		Vector2(0, -3), Vector2(-6, -2), Vector2(6, -2),
		Vector2(-5, 1), Vector2(5, 1), Vector2(0, 3),
		Vector2(-5, 5), Vector2(5, 5), Vector2(0, 7),
		# Lower (3)
		Vector2(-4, 10), Vector2(4, 10), Vector2(0, 12)
	]
	
	# Draw small red circles at each possible position
	for pos in position_pool:
		draw_circle(pos, 3, Color(1, 0, 0, 0.7))  # Red
	
	# Draw larger green circles at the 3 chosen positions
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			draw_circle(weakpoint.position, 5, Color(0, 1, 0, 0.9))  # Bright green
	
	print("🔍 DEBUG: Drew %d red circles and %d green circles" % [position_pool.size(), weakpoints.size()])

# Keep redrawing while in crit window
func _process(delta: float) -> void:
	if in_crit_window and not weakpoints.is_empty():
		queue_redraw()  # Continuously redraw while weakpoints are active

func _on_weakpoint_hit(weakpoint) -> void:
	if spam_protection_active or is_dying:
		return

	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER
	take_damage(crit_damage, true)
	weakpoint_hit_success.emit()

func _on_weakpoint_destroyed(weakpoint) -> void:
	weakpoints_destroyed += 1
	DebugConfig.log_combat("💥 Weakpoint destroyed (%d/%d)" % [weakpoints_destroyed, num_weakpoints])

	if weakpoints_destroyed >= num_weakpoints:
		DebugConfig.log_combat("🎯 All weakpoints destroyed")
		
		# ✨ NEW: Play victory sound for clearing all weakpoints
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.ALL_WEAKPOINTS_CLEARED, global_position, -2.0)
		
		end_crit_window()

func _on_window_timeout() -> void:
	if in_crit_window and not is_dying:
		DebugConfig.log_combat("⏱️ Window timeout")
		end_crit_window()

func end_crit_window() -> void:
	if not in_crit_window or is_dying:
		return

	DebugConfig.log_combat("Ending crit window")
	in_crit_window = false
	
	# Stop timer
	if window_timer and is_instance_valid(window_timer):
		window_timer.stop()
		window_timer.queue_free()
		window_timer = null
	
	# Emit signal
	crit_window_complete.emit(weakpoints_destroyed)
	
	# Clean weakpoints
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			weakpoint.queue_free()
	weakpoints.clear()
	
	# ✨ FIXED: Reset HitFlash first, then change color back
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		# Stop any active flash (if method exists)
		if hit_flash.has_method("reset"):
			hit_flash.reset()
		# Set base color back to white
		hit_flash.set_base_color(Color.WHITE)
	
	# ✨ FIX: Restore original difficulty color (parent modulate)
	self.modulate = original_modulate
	print("   ✅ Restored parent modulate: %s" % self.modulate)
	
	# Change sprite back to white (normal enemy color)
	if sprite:
		sprite.modulate = Color.WHITE
	
# ✨ FIX #3: Scale back with forced final state
	if is_instance_valid(self):
		var tween = create_tween()
		tween.tween_property(self, "scale", original_scale, 0.25)
		
		# Wait for tween to finish, then FORCE final state
		await get_tree().create_timer(0.26).timeout
		
		if is_instance_valid(self):
			# Force all properties to final state
			scale = original_scale  # ✨ FORCE scale value!
			z_index = 0
			
			# Force color back to white
			if sprite and is_instance_valid(self):
				sprite.modulate = Color.WHITE
			
			print("✅ Enemy scaled back to normal: ", scale)

func die() -> void:
	if is_dying:
		return
	
	is_dying = true
	print("\n☠️ ===== ENEMY DEATH =====")
	print("Enemy name: ", name)
	print("Enemy level: ", enemy_level)
	print("Position: ", global_position)
	print("Health: ", current_health)
	print("Is in tree: ", is_inside_tree())
	print("Killed by weakpoint in window: ", killed_by_weakpoint_in_window)
	
	# Grant XP to player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("gain_experience"):
		player.gain_experience(xp_reward)
		print("💰 Granted ", xp_reward, " XP to player")

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
	
	# Emit died signal for spawner
	died.emit()
	
	# Force end crit window
	if in_crit_window:
		in_crit_window = false
		if window_timer:
			window_timer.stop()
			window_timer.queue_free()
		for weakpoint in weakpoints:
			if is_instance_valid(weakpoint):
				weakpoint.queue_free()
		weakpoints.clear()
		
		# ✨ NEW: If killed by weakpoint, count it as a successful combo for chain purposes
		if killed_by_weakpoint_in_window:
			# Pass special value to indicate kill-during-window
			crit_window_complete.emit(num_weakpoints)
		else:
			crit_window_complete.emit(weakpoints_destroyed)
	
	print("Calling queue_free()...")
	queue_free()
	print("Enemy queued for deletion")
	print("===== END DEATH =====\n")

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
