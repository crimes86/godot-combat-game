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

# LOD (Level of Detail) system for performance
enum LOD {
	FULL = 0,      # Full AI, particles, animations (< 400px)
	MEDIUM = 1,    # Reduced AI update rate (400-800px)
	MINIMAL = 2,   # Just visible sprite (800-1500px)
	INVISIBLE = 3  # Beyond view distance (> 1500px)
}
var current_lod: int = LOD.FULL

# References
@onready var health_bar: Control = $HealthBar
@onready var sprite: CanvasItem = $Sprite2D  # Can be Sprite2D or AnimatedSprite2D
@onready var click_area: Area2D = $Area2D
var level_label: Label = null  # Created dynamically in show_level()
var shadow_sprite: AnimatedSprite2D = null  # Shadow layer

# Crit window state (minimal - manager owns lifecycle)
var in_crit_window: bool = false  # Simple flag set by grow/shrink methods
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE  # Store original difficulty color
var weakpoints: Array = []  # Just for visual rendering
var is_dying: bool = false

# Corpse state (lootable body system)
var is_corpse: bool = false
var corpse_loot: Array = []  # Generated items for this corpse
var corpse_gold: int = 0  # Gold that can be looted from this corpse
var corpse_creation_time: float = 0.0
var corpse_state: CorpseState.State = CorpseState.State.FRESH
var loot_indicator: Node2D = null  # Visual glow for lootable corpses
var player_in_loot_range: bool = false  # Is player close enough to loot?
var loot_prompt: Label = null  # [F] Loot prompt
var loot_ui_open: bool = false  # Is the loot UI currently open for this corpse?

# Signals for CritWindowManager
signal weakpoint_spawned()  # Emitted when a weakpoint is created
signal weakpoint_destroyed(weakpoint: Node)  # Emitted when a weakpoint is destroyed
signal died()  # Emitted when enemy dies
signal damage_taken(damage: float, is_crit: bool)  # For unified feedback

# Corpse signals
signal corpse_clicked(corpse)  # Emitted when corpse is clicked for looting
signal corpse_looted_empty(corpse)  # Emitted when all items taken from corpse

func _ready() -> void:
	# Set collision layers: enemies on layer 1, detect layers 1 (other entities) and 2 (obstacles like trees)
	collision_layer = 1
	collision_mask = 3  # Bitmask: 1 (layer 1) + 2 (layer 2) = 3

	# Scale stats by enemy level
	max_health = Constants.ENEMY_BASE_HEALTH * pow(Constants.ENEMY_HEALTH_SCALING, enemy_level - 1)  # ~500 HP at level 10
	base_damage = Constants.ENEMY_BASE_DAMAGE * pow(Constants.ENEMY_DAMAGE_SCALING, enemy_level - 1)
	xp_reward = int(xp_reward_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))  # Same scaling as XP

	# Debug gold drop calculation (disabled - too spammy)
	# DebugConfig.debug_log("💰 Enemy initialized - Level: %d, gold_drop_base: %d, gold_drop: %d" % [enemy_level, gold_drop_base, gold_drop])

	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		health_bar.visible = false  # Start hidden, show when player is within 375px
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
		# Check if this is a guardian (uses special armored sprites)
		var is_guardian = get_meta("is_guardian", false)

		# Load sprite sheets based on enemy type
		var walk_path: String
		var slash_path: String
		var hurt_path: String

		if is_guardian:
			# Guardian skeletal warriors with copper armor and longsword
			walk_path = "res://assets/characters/skeletal_guardian/walk_guardian.png"
			slash_path = "res://assets/characters/skeletal_guardian/slash_guardian.png"
			hurt_path = ""  # Guardians use same hurt as regular skeletons for now
		else:
			# Regular skeleton
			walk_path = "res://assets/characters/BODY_skeleton_walk.png"
			slash_path = "res://assets/characters/BODY_skeleton_slash.png"
			hurt_path = "res://assets/characters/BODY_skeleton_hurt.png"

		var walk_tex: Texture2D = null
		var slash_tex: Texture2D = null
		var hurt_tex: Texture2D = null

		# Try to load walking sprite
		if ResourceLoader.exists(walk_path):
			walk_tex = ResourceLoader.load(walk_path, "Texture2D")

		# Try to load attack sprite
		if ResourceLoader.exists(slash_path):
			slash_tex = ResourceLoader.load(slash_path, "Texture2D")

		# Try to load hurt sprite (optional)
		if hurt_path != "" and ResourceLoader.exists(hurt_path):
			hurt_tex = ResourceLoader.load(hurt_path, "Texture2D")
		
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

			# Create shadow layer (before adding main sprite)
			create_shadow_layer()

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

func create_shadow_layer() -> void:
	"""Create animated shadow layer for skeleton"""
	# Load shadow textures
	var shadow_walk_path = "res://assets/characters/shadow/standard/walk.png"
	var shadow_slash_path = "res://assets/characters/shadow/standard/slash.png"

	if not ResourceLoader.exists(shadow_walk_path):
		print("⚠️ Shadow sprites not found, skipping shadow layer")
		return

	var shadow_walk_tex: Texture2D = ResourceLoader.load(shadow_walk_path, "Texture2D")
	var shadow_slash_tex: Texture2D = null
	if ResourceLoader.exists(shadow_slash_path):
		shadow_slash_tex = ResourceLoader.load(shadow_slash_path, "Texture2D")

	# Create shadow sprite
	shadow_sprite = AnimatedSprite2D.new()
	shadow_sprite.name = "ShadowLayer"
	shadow_sprite.centered = true
	shadow_sprite.z_index = -10  # Below skeleton body
	shadow_sprite.modulate = Color(1, 1, 1, 0.6)  # Semi-transparent

	# Create sprite frames for shadow
	var shadow_frames = SpriteFrames.new()

	# Walk animations - 4 rows (UP, LEFT, DOWN, RIGHT), 9 frames each
	if shadow_walk_tex:
		var shadow_walk_img = shadow_walk_tex.get_image()
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_up", 0, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_left", 1, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_down", 2, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_right", 3, 9, 8.0)

		# Idle animations - middle frame
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_up", 0, 1, 1.0, true, 4)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_left", 1, 1, 1.0, true, 4)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_down", 2, 1, 1.0, true, 4)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_right", 3, 1, 1.0, true, 4)

	# Attack animations - 6 frames each
	if shadow_slash_tex:
		var shadow_slash_img = shadow_slash_tex.get_image()
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_up", 0, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_left", 1, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_down", 2, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_right", 3, 6, 12.0, false)

	shadow_sprite.sprite_frames = shadow_frames
	add_child(shadow_sprite)

	# Start with idle animation
	if shadow_sprite.sprite_frames.has_animation("idle_down"):
		shadow_sprite.play("idle_down")

	print("  ✅ Shadow layer created for skeleton (z_index=%d, opacity=60%%)" % shadow_sprite.z_index)

func get_enemy_name() -> String:
	"""Generate enemy name based on level and type"""
	var is_guardian = get_meta("is_guardian", false)

	# Name prefixes based on level ranges
	var prefix = ""
	if enemy_level <= 3:
		prefix = "Skeleton"
	elif enemy_level <= 5:
		prefix = "Restless Skeleton"
	elif enemy_level <= 7:
		prefix = "Cursed Skeleton"
	elif enemy_level <= 9:
		prefix = "Dark Skeleton"
	else:
		prefix = "Ancient Skeleton"

	# Guardian modifier
	if is_guardian:
		prefix = "Guardian " + prefix

	return prefix

func get_con_color(player_level: int) -> Color:
	"""Get con (consider) color based on level difference with player
	Classic MMO con system:
	- Gray: 6+ levels below (trivial, no XP)
	- Green: 3-5 levels below (easy)
	- Blue: 1-2 levels below (moderate)
	- White: Same level (even match)
	- Yellow: 1-2 levels above (challenging)
	- Orange: 3-4 levels above (difficult)
	- Red: 5+ levels above (deadly)
	"""
	var level_diff = enemy_level - player_level

	if level_diff <= -6:
		return Color(0.6, 0.6, 0.6)  # Gray (trivial)
	elif level_diff <= -3:
		return Color(0.2, 1.0, 0.2)  # Green (easy)
	elif level_diff <= -1:
		return Color(0.4, 0.6, 1.0)  # Blue (moderate)
	elif level_diff == 0:
		return Color(1.0, 1.0, 1.0)  # White (even)
	elif level_diff <= 2:
		return Color(1.0, 1.0, 0.0)  # Yellow (challenging)
	elif level_diff <= 4:
		return Color(1.0, 0.6, 0.0)  # Orange (difficult)
	else:
		return Color(1.0, 0.2, 0.2)  # Red (deadly)

func update_level_display() -> void:
	"""Show enemy level on sprite"""
	if enemy_level >= 1:  # Show for all enemies including level 1
		# Create name label (shows enemy name with con color)
		level_label = Label.new()
		level_label.text = get_enemy_name()
		level_label.add_theme_font_size_override("font_size", 12)
		# Color will be set dynamically in _process based on player level
		level_label.add_theme_color_override("font_color", Color.WHITE)  # Default white
		level_label.add_theme_color_override("font_outline_color", Color.BLACK)
		level_label.add_theme_constant_override("outline_size", 2)
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # Center the text
		level_label.position = Vector2(-50, -55)  # Centered above health bar (100px wide label)
		level_label.custom_minimum_size = Vector2(100, 0)  # Set label width for centering
		level_label.z_index = 500
		level_label.visible = false  # Start hidden, show when player is within 800px
		add_child(level_label)

func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# If this is a corpse, handle right-click for looting
	if is_corpse and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click on corpse - trigger loot UI
			corpse_clicked.emit(self)
			get_viewport().set_input_as_handled()
			return

	# Let Player handle ALL clicks for living enemies (including crit window)
	# This prevents double-damage bugs where both Player and Enemy handle the same click
	return

func take_damage(amount: float, is_crit: bool = false, is_weakpoint_hit: bool = false) -> void:
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

	DebugConfig.log_combat("Enemy hit! Damage: %d (Crit: %s, Weakpoint: %s) | Health: %d/%d" % [amount, is_crit, is_weakpoint_hit, current_health, max_health])

	# ✨ NEW: Emit signal for player to handle feedback
	damage_taken.emit(amount, is_crit)

	# ✨ NEW: Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# ✨ NEW: Spawn combat text centered at 70% of sprite height
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	# Set damage text
	combat_text.text = str(int(amount))

	# Determine text type based on parameters
	if is_weakpoint_hit:
		combat_text.type = 2  # TextType.WEAKPOINT (orange)
	elif is_crit:
		combat_text.type = 1  # TextType.CRIT (yellow)
		# 🔊 Play critical hit sound (non-weakpoint crits only)
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_critical_hit_sound(global_position, -3.0)
	else:
		combat_text.type = 0  # TextType.NORMAL (white)

	# Calculate spawn position at 70% of sprite height (accounting for scale)
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_height = 64.0 * sprite_scale.y  # LPC sprites are 64px tall
	var sprite_pos = sprite.position if sprite else Vector2.ZERO

	# Spawn at 70% height from bottom (30% from top)
	# Sprite is centered, so top is at -height/2
	var spawn_y_offset = -(sprite_height * 0.3)  # 30% from top = 70% from bottom

	# Horizontal and vertical offset based on hit type
	var spawn_x_offset = -50.0  # All damage text starts -50px left
	if is_weakpoint_hit:
		# Weakpoints: offset to sides and higher than main column
		# Alternate between left and right sides
		if not has_meta("weakpoint_side"):
			set_meta("weakpoint_side", 1)  # Start with right side

		var side = get_meta("weakpoint_side")
		if side > 0:
			# Right side: -30px
			spawn_x_offset = -30.0
		else:
			# Left side: -70px
			spawn_x_offset = -70.0
		spawn_y_offset -= 25.0  # 25px higher than main column
		set_meta("weakpoint_side", -side)  # Flip for next hit

	# Final spawn position: enemy center + sprite offset + calculated offset
	var spawn_pos = global_position + sprite_pos + Vector2(spawn_x_offset, spawn_y_offset)

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)
	
	# ✨ NEW: Play hit sound
	# NOTE: Weakpoint sounds are handled in weakpoint.gd directly
	# Only play sounds here for non-weakpoint hits
	if not is_weakpoint_hit:
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
	# CRITICAL: Don't spawn weakpoints if enemy is already dying/dead
	if is_dying or is_corpse:
		print("⚠️ [WEAKPOINT] Enemy is dying/corpse - skipping weakpoint spawn")
		return

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

		# Connect weakpoint signals - handle damage and forward to manager
		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
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

	# Toggle UI based on player distance (visibility handled by LOD system)
	if not is_corpse:  # Only for living enemies
		var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player and is_instance_valid(player):
			var distance = global_position.distance_to(player.global_position)

			# Decoupled UI visibility thresholds
			var show_level_label = distance <= 800.0  # Level shows at 800px
			var show_healthbar = distance <= 400.0    # Healthbar shows at 400px

			# Update level label visibility, position, and con color
			if level_label:
				level_label.visible = show_level_label

				# Update con color based on player level
				if show_level_label:
					var player_level = player.get("current_level")
					if player_level == null:
						player_level = 1
					var con_color = get_con_color(player_level)
					level_label.add_theme_color_override("font_color", con_color)

				# Stack level label above healthbar when both are visible
				if show_healthbar:
					level_label.position = Vector2(-50, -62)  # Push up to sit above healthbar with small gap
				else:
					level_label.position = Vector2(-50, -55)  # Normal position when alone

			# Update healthbar visibility
			if health_bar:
				health_bar.visible = show_healthbar

	# Handle corpse decay and interaction
	if is_corpse:
		process_corpse_decay(delta)
		update_loot_proximity()

func set_lod_level(lod_level: int) -> void:
	"""Set Level of Detail for performance optimization"""
	if current_lod == lod_level:
		return  # No change

	current_lod = lod_level

	match lod_level:
		LOD.FULL:  # < 400px - Full detail
			visible = true
			set_physics_process(true)
			set_process(true)
			# Enable AI if exists
			if has_node("EnemyAI"):
				var ai = get_node("EnemyAI")
				ai.set_physics_process(true)
				ai.set_process(true)
			# Enable particles if they exist
			for child in get_children():
				if child is GPUParticles2D:
					child.emitting = true

		LOD.MEDIUM:  # 400-800px - Reduced AI
			visible = true
			set_physics_process(true)
			set_process(true)
			# Reduce AI update rate (handled by EnemyAI's own LOD if implemented)
			if has_node("EnemyAI"):
				var ai = get_node("EnemyAI")
				ai.set_physics_process(true)
				ai.set_process(true)
			# Reduce particles
			for child in get_children():
				if child is GPUParticles2D:
					child.amount = max(1, child.amount / 2)

		LOD.MINIMAL:  # 800-1500px - Just visible
			visible = true
			set_physics_process(false)  # No physics
			set_process(true)  # Keep process for UI updates
			# Disable AI
			if has_node("EnemyAI"):
				var ai = get_node("EnemyAI")
				ai.set_physics_process(false)
				ai.set_process(false)
			# Stop walking animation and switch to idle
			if sprite is AnimatedSprite2D:
				var anim_sprite = sprite as AnimatedSprite2D
				if anim_sprite.animation and anim_sprite.animation.begins_with("walk_"):
					# Get direction from current animation
					var direction = anim_sprite.animation.replace("walk_", "")
					var idle_anim = "idle_" + direction
					if anim_sprite.sprite_frames.has_animation(idle_anim):
						anim_sprite.play(idle_anim)
				# Also stop shadow animation
				if shadow_sprite and shadow_sprite.animation and shadow_sprite.animation.begins_with("walk_"):
					var direction = shadow_sprite.animation.replace("walk_", "")
					var idle_anim = "idle_" + direction
					if shadow_sprite.sprite_frames.has_animation(idle_anim):
						shadow_sprite.play(idle_anim)
			# Disable particles
			for child in get_children():
				if child is GPUParticles2D:
					child.emitting = false

		LOD.INVISIBLE:  # > 1500px - Not visible
			visible = false
			set_physics_process(false)
			set_process(false)
			# Disable AI
			if has_node("EnemyAI"):
				var ai = get_node("EnemyAI")
				ai.set_physics_process(false)
				ai.set_process(false)
			# Disable particles
			for child in get_children():
				if child is GPUParticles2D:
					child.emitting = false

func update_loot_proximity() -> void:
	"""Check if player is close enough to loot and show/hide prompt"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		player_in_loot_range = false
		if loot_prompt:
			loot_prompt.visible = false
		return

	# Check distance to player
	var distance = global_position.distance_to(player.global_position)
	var was_in_range = player_in_loot_range
	player_in_loot_range = distance <= 80.0  # Same range as chest interaction

	# Update prompt visibility (show if has gold OR items, and UI not open)
	if player_in_loot_range and (corpse_gold > 0 or corpse_loot.size() > 0) and not loot_ui_open:
		if not loot_prompt:
			create_loot_prompt()
		loot_prompt.visible = true
		update_loot_prompt_position()
	else:
		if loot_prompt:
			loot_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	"""Handle F-key input for looting (only if not handled by other nodes)"""
	if not is_corpse:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		if player_in_loot_range and (corpse_gold > 0 or corpse_loot.size() > 0):
			print("💀 Corpse handling F-key (unhandled input)")
			open_loot_ui()
			get_viewport().set_input_as_handled()

func create_loot_prompt() -> void:
	"""Create [F] Loot prompt above corpse"""
	if loot_prompt:
		return

	var canvas = CanvasLayer.new()
	canvas.name = "LootPromptCanvas"
	canvas.layer = 50
	add_child(canvas)

	loot_prompt = Label.new()
	loot_prompt.name = "LootPrompt"
	loot_prompt.text = "[F] Loot"
	loot_prompt.add_theme_font_size_override("font_size", 16)
	loot_prompt.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))  # Yellow-white
	loot_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	loot_prompt.add_theme_constant_override("outline_size", 2)
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_prompt.visible = false
	canvas.add_child(loot_prompt)

func update_loot_prompt_position() -> void:
	"""Update prompt position to stay above corpse"""
	if not loot_prompt:
		return

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Position prompt above corpse
	var prompt_world_pos = global_position + Vector2(0, -40)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var prompt_screen_pos = (prompt_world_pos - camera_pos) * camera.zoom.x + screen_center

	# Center horizontally
	var screen_x = prompt_screen_pos.x
	if loot_prompt.size.x > 0:
		screen_x -= loot_prompt.size.x / 2
	var screen_y = prompt_screen_pos.y

	loot_prompt.position = Vector2(screen_x, screen_y)

func open_loot_ui() -> void:
	"""Open loot UI for this corpse (called when F is pressed)"""
	if corpse_gold == 0 and corpse_loot.is_empty():
		print("💀 No loot or gold, not opening UI")
		return

	print("💀 Opening loot UI via F-key for corpse at %s (Gold: %d, Items: %d)" % [global_position, corpse_gold, corpse_loot.size()])
	print("💀 Signal connections: %d" % corpse_clicked.get_connections().size())
	corpse_clicked.emit(self)
	print("💀 Signal emitted!")

func _on_weakpoint_hit(weakpoint) -> void:
	"""Handle weakpoint being hit - deal damage and show combat text"""
	# Calculate crit damage using player's base damage
	var base_damage = CharacterStats.get_base_damage()
	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER

	# Deal damage with crit flag and weakpoint flag for orange text
	take_damage(crit_damage, true, true)  # damage, is_crit, is_weakpoint

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

	# CRITICAL: Clean up any active weakpoints to prevent artifacting
	# Use multiple methods to ensure all weakpoints are destroyed
	print("💀 [CLEANUP] Enemy dying, cleaning up weakpoints...")

	# Method 1: Clear from array and free
	var weakpoint_count = weakpoints.size()
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			print("   - Freeing weakpoint from array: %s" % weakpoint.name)
			weakpoint.visible = false
			weakpoint.input_pickable = false
			weakpoint.monitoring = false
			weakpoint.monitorable = false
			weakpoint.queue_free()
	weakpoints.clear()

	# Method 2: Iterate children and destroy any Weakpoint nodes (catches any missed)
	for child in get_children():
		if child is Weakpoint:
			print("   - Found weakpoint in children (not in array): %s" % child.name)
			child.visible = false
			child.input_pickable = false
			child.monitoring = false
			child.monitorable = false
			child.queue_free()

	print("💀 [CLEANUP] Cleaned up %d weakpoints" % weakpoint_count)

	# Grant XP to player (immediate reward)
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("gain_experience"):
		player.gain_experience(xp_reward)

	# Store gold in corpse for looting (NOT auto-awarded)
	corpse_gold = gold_drop
	print("💀 Storing %d gold in corpse for looting" % corpse_gold)

	# Play death sound (skeleton-specific bone collapse)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_skeleton_death_sound(global_position, -3.0)

	# Play death animation (hurt animation) and wait for it to complete
	var anim_sprite = sprite as AnimatedSprite2D
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("hurt"):
		anim_sprite.play("hurt")
		# Wait for the full animation to finish
		await anim_sprite.animation_finished

		# FREEZE on last frame
		anim_sprite.stop()
		var frame_count = anim_sprite.sprite_frames.get_frame_count("hurt")
		anim_sprite.frame = frame_count - 1
	else:
		# Fallback if animation doesn't exist (e.g., guardians have no hurt animation)
		# Stop any playing animation and freeze on last frame
		if anim_sprite:
			anim_sprite.stop()
			# Freeze on the last frame of current animation
			if anim_sprite.sprite_frames and anim_sprite.animation:
				var frame_count = anim_sprite.sprite_frames.get_frame_count(anim_sprite.animation)
				if frame_count > 0:
					anim_sprite.frame = frame_count - 1
		await get_tree().create_timer(0.6).timeout

	# Generate loot for this corpse
	corpse_loot = generate_corpse_loot()

	# Emit died signal - spawner will respawn immediately
	died.emit()

	# Transition to corpse state (don't despawn)
	become_corpse()

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

## ============================================
## CORPSE SYSTEM
## ============================================

func generate_corpse_loot() -> Array:
	"""Generate loot items for this corpse using CorpseState loot tables"""
	var loot = []

	# Check if this is a guardian (Ruins skeleton with special loot)
	var is_guardian = get_meta("is_guardian", false)

	# Roll for number of items (0-2)
	var num_items = CorpseState.roll_loot_count()
	print("💀 Rolled %d loot items for %s" % [num_items, "guardian" if is_guardian else "corpse"])

	# Generate each item
	for i in range(num_items):
		var item = CorpseState.roll_loot_item(is_guardian)
		if not item.is_empty():
			# Add quantity for stackable items
			if item.get("stackable", false):
				item["quantity"] = 1
			loot.append(item)
			print("   💎 Generated: %s" % item.get("name", "Unknown"))

	return loot

func become_corpse() -> void:
	"""Transition enemy from living to corpse state"""
	print("💀 Becoming corpse with %d loot items" % corpse_loot.size())
	is_corpse = true
	corpse_creation_time = Time.get_ticks_msec() / 1000.0
	corpse_state = CorpseState.State.FRESH

	# Clean up any active weakpoints (if enemy died during crit window)
	if not weakpoints.is_empty():
		print("   🧹 Cleaning up %d active weakpoints" % weakpoints.size())
		for wp in weakpoints:
			if is_instance_valid(wp):
				wp.queue_free()
		weakpoints.clear()
		in_crit_window = false

	# Disable AI
	if has_node("EnemyAI"):
		var ai = get_node("EnemyAI")
		ai.set_process(false)
		ai.set_physics_process(false)

	# Disable health bar
	if health_bar:
		health_bar.visible = false

	# Keep collision for clicking, but change layers
	# Layer 4 = corpses (separate from living enemies)
	collision_layer = 8  # 2^3 = layer 4
	collision_mask = 0   # Don't detect anything

	# Change groups
	remove_from_group(Constants.GROUP_ENEMIES)
	add_to_group("corpses")

	# Add loot indicator if has gold OR items
	if corpse_gold > 0 or corpse_loot.size() > 0:
		print("   ✨ Adding loot indicator (sparkles) - Gold: %d, Items: %d" % [corpse_gold, corpse_loot.size()])
		add_loot_indicator()
	else:
		print("   ⚫ No loot - no indicator")

	# Darken sprite slightly
	if sprite:
		sprite.modulate = Color(0.8, 0.8, 0.8, 1.0)

func add_loot_indicator() -> void:
	"""Add shiny glimmer effect to indicate this corpse has loot (WoW-style)"""
	if loot_indicator:
		return  # Already has indicator

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10  # Draw on top

	# Create 3-4 small sparkle points clustered tightly on the corpse
	var sparkle_positions = [
		Vector2(-3, -5),  # Upper left (tight cluster)
		Vector2(3, -5),   # Upper right (tight cluster)
		Vector2(-2, 0),   # Lower left (tight cluster)
		Vector2(2, 0)     # Lower right (tight cluster)
	]

	for i in range(sparkle_positions.size()):
		var sparkle = create_sparkle()
		sparkle.position = sparkle_positions[i]
		loot_indicator.add_child(sparkle)

		# Stagger animation start times for shimmer effect
		var delay = i * 0.2
		animate_sparkle(sparkle, delay)

	add_child(loot_indicator)

func create_sparkle() -> Polygon2D:
	"""Create a single sparkle (4-pointed star)"""
	var sparkle = Polygon2D.new()

	# Create 4-pointed star shape
	var size = 6.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Top point
		Vector2(-1, -1),        # Inner top-left
		Vector2(-size, 0),      # Left point
		Vector2(-1, 1),         # Inner bottom-left
		Vector2(0, size),       # Bottom point
		Vector2(1, 1),          # Inner bottom-right
		Vector2(size, 0),       # Right point
		Vector2(1, -1)          # Inner top-right
	])

	sparkle.polygon = points
	sparkle.color = Color(1.0, 1.0, 0.8, 0.9)  # Bright yellow-white

	return sparkle

func animate_sparkle(sparkle: Polygon2D, delay: float) -> void:
	"""Animate sparkle floating upward and fading out"""
	# Wait for delay
	await get_tree().create_timer(delay).timeout

	if not is_instance_valid(sparkle):
		return

	# Store initial position
	var start_pos = sparkle.position

	# Create looping animation
	var tween = create_tween()
	tween.set_loops()

	# Float up and fade out, then reset
	tween.tween_property(sparkle, "position:y", start_pos.y - 20, 1.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.5, 1.5)

	# Reset instantly and wait before next cycle
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.9, 0.0)
	tween.parallel().tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.5)  # Pause before next shimmer

func process_corpse_decay(delta: float) -> void:
	"""Handle corpse decay over time"""
	var elapsed = (Time.get_ticks_msec() / 1000.0) - corpse_creation_time

	# Check if fully rotted (5 minutes)
	if elapsed >= CorpseState.CORPSE_DECAY_TIME:
		rot_and_despawn()
		return

	# Check if transitioned to decaying state (after 1 minute)
	if elapsed >= CorpseState.CORPSE_FRESH_TIME:
		if corpse_state == CorpseState.State.FRESH:
			corpse_state = CorpseState.State.DECAYING
			update_decay_visual()

func update_decay_visual() -> void:
	"""Update visual appearance for decaying state"""
	if sprite:
		# Make more transparent
		var current_color = sprite.modulate
		sprite.modulate = Color(
			current_color.r * CorpseState.DECAY_ALPHA_MULTIPLIER,
			current_color.g * CorpseState.DECAY_ALPHA_MULTIPLIER,
			current_color.b * CorpseState.DECAY_ALPHA_MULTIPLIER,
			0.8  # More transparent
		)

func rot_and_despawn() -> void:
	"""Corpse has rotted - fade out and remove"""
	if corpse_state == CorpseState.State.ROTTED:
		return  # Already rotting

	corpse_state = CorpseState.State.ROTTED

	# Fade out animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 2.0)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 2.0)
	await tween.finished

	queue_free()

func check_if_looted_empty() -> void:
	"""Called when items are taken - check if corpse is now empty"""
	# Corpse is empty when BOTH gold is 0 AND items are gone
	if corpse_loot.is_empty() and corpse_gold == 0:
		# Remove loot indicator
		if loot_indicator:
			loot_indicator.queue_free()
			loot_indicator = null

		# Hide loot prompt
		if loot_prompt:
			loot_prompt.queue_free()
			loot_prompt = null

		# Emit signal
		corpse_looted_empty.emit(self)

		# Quick fade out
		graceful_despawn()

func graceful_despawn() -> void:
	"""Quick fade out for fully looted corpses"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.5)
	await tween.finished

	queue_free()

func has_corpse_loot() -> bool:
	"""Check if corpse has any lootable items or gold remaining (used by SpawnManager)"""
	return not corpse_loot.is_empty() or corpse_gold > 0

func get_nearby_corpses(radius: float) -> Array:
	"""Find all corpses within radius for AOE looting"""
	var nearby = []
	var all_corpses = get_tree().get_nodes_in_group("corpses")

	for node in all_corpses:
		if node == self:
			continue  # Skip self

		# Check if valid corpse and within radius
		if is_instance_valid(node) and node.global_position.distance_to(global_position) <= radius:
			nearby.append(node)

	return nearby
