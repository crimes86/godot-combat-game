extends CharacterBody2D

# Character Gender Selection
enum Gender { MALE, FEMALE }
var selected_gender: Gender = Gender.MALE  # Will be set at game start

# Movement - Now derived from CharacterStats
@export var speed_override: float = -1.0  # -1 = use CharacterStats, otherwise manual override

# Combat - Cone Attack - Now derived from CharacterStats
@export var damage_override: float = -1.0      # -1 = use CharacterStats
@export var cooldown_override: float = -1.0    # -1 = use CharacterStats
@export var hold_attack_interval: float = Constants.PLAYER_HOLD_ATTACK_INTERVAL  # Slightly slower than manual clicking
@export var attack_range: float = Constants.PLAYER_ATTACK_RANGE
@export var attack_cone_angle: float = Constants.PLAYER_ATTACK_CONE_ANGLE
var can_attack: bool = true
var attack_direction: Vector2 = Vector2.RIGHT
var is_mouse_held: bool = false
var hold_attack_timer: float = 0.0

# Combat stats - synced from CharacterStats
var speed: float = Constants.PLAYER_BASE_SPEED
var attack_damage: float = Constants.PLAYER_BASE_ATTACK_DAMAGE
var attack_cooldown: float = Constants.PLAYER_ATTACK_COOLDOWN

# Health - Now derived from CharacterStats
var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false  # Prevent multiple death calls

# References
@onready var health_bar: Control = $HealthBar
@onready var crit_system: Node = $CritSystem
@onready var crit_window_manager: Node = $CritWindowManager

# Effect system
var screen_shake: ScreenShake = null
var attack_feedback: AttackFeedbackSystem = null

# Visual feedback
var cone_visualizer: Polygon2D = null
var debug_mode: bool = false
var debug_shapes: Node2D = null
var world_debug_nodes: Array = []  # Track world-space debug nodes for cleanup
var debug_update_timer: float = 0.0  # Throttle debug updates
var debug_label: Label = null  # Display debug info (coordinates, etc.)
var cone_update_timer: float = 0.0  # Throttle cone color updates (CRITICAL for performance!)

# Camera zoom
@export var zoom_min: float = 0.5   # Zoom out 2x (see more)
@export var zoom_max: float = 2.0   # Zoom in 2x (close-up)
@export var zoom_speed: float = 0.1 # How fast zoom transitions
var target_zoom: float = 1.0
var camera: Camera2D = null

# Character UI
var character_ui: CanvasLayer = null

# Campfire Direction Indicator
var campfire_indicator: CanvasLayer = null

func _ready() -> void:
	print("🎮 Player._ready() started")
	
	# AUTO-SELECT MALE (can switch to female by pressing F key during gameplay)
	print("")
	print("════════════════════════════════════════")
	print("  CHARACTER: MALE WARRIOR")
	print("════════════════════════════════════════")
	print("  (Press F during gameplay to switch to female)")
	print("════════════════════════════════════════")
	print("")
	
	selected_gender = Gender.MALE
	
	# Create player sprite immediately
	create_player_sprite()
	print("✨ Player sprite created!")
	
	# THEN: Initialize everything else
	
	# 🔧 DEBUG: Print initial cooldown values
	print("═══ PLAYER COOLDOWN DEBUG ═══")
	print("cooldown_override: ", cooldown_override)
	print("Initial attack_cooldown: ", attack_cooldown)
	
	# Initialize stats from CharacterStats
	update_stats_from_character()
	
	print("After update - attack_cooldown: ", attack_cooldown)
	print("CharacterStats AGI: ", CharacterStats.agility)
	print("CharacterStats.get_attack_cooldown(): ", CharacterStats.get_attack_cooldown())
	print("═══════════════════════════")
	
	

	
	
	
	# Set health
	current_health = max_health
	health_bar.update_health(current_health, max_health)
	
	# Add to player group
	add_to_group(Constants.GROUP_PLAYER)
	
	# Create cone visualizer
	create_cone_visualizer()
	# create_range_indicator()  # Commented out - don't show range circle
	
	# Setup screen shake
	screen_shake = ScreenShake.new()
	screen_shake.name = "ScreenShake"
	add_child(screen_shake)
	
	# Setup attack feedback system
	attack_feedback = AttackFeedbackSystem.new()
	add_child(attack_feedback)
	
	# Setup debug shapes container
	debug_shapes = Node2D.new()
	debug_shapes.name = "DebugShapes"
	debug_shapes.z_index = 1000
	add_child(debug_shapes)

	# Setup debug label (screen-space coordinates display)
	var debug_canvas = CanvasLayer.new()
	debug_canvas.name = "DebugCanvas"
	debug_canvas.layer = 100  # Draw on top of everything
	add_child(debug_canvas)

	debug_label = Label.new()
	debug_label.name = "DebugLabel"
	debug_label.position = Vector2(10, 10)  # Top-left corner
	debug_label.add_theme_font_size_override("font_size", 16)
	debug_label.add_theme_color_override("font_color", Color.WHITE)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 2)
	debug_label.visible = false  # Hidden by default
	debug_canvas.add_child(debug_label)
	
	# Setup camera
	camera = get_node_or_null("Camera2D")
	if camera:
		camera.enabled = true
		camera.zoom = Vector2(target_zoom, target_zoom)
		print("📷 Camera zoom system initialized (0.5x - 2.0x)")
	else:
		push_error("❌ Camera2D not found on player!")
	
	# Connect to CharacterStats signals
	CharacterStats.level_up.connect(_on_character_level_up)
	CharacterStats.weapon_equipped.connect(_on_weapon_equipped)
	CharacterStats.weapon_unequipped.connect(_on_weapon_unequipped)

	# Create character UI after this frame
	call_deferred("create_character_ui")

	# Create campfire direction indicator
	call_deferred("create_campfire_indicator")

func _exit_tree() -> void:
	# Disconnect signals to prevent crash on exit
	if CharacterStats.level_up.is_connected(_on_character_level_up):
		CharacterStats.level_up.disconnect(_on_character_level_up)
	if CharacterStats.weapon_equipped.is_connected(_on_weapon_equipped):
		CharacterStats.weapon_equipped.disconnect(_on_weapon_equipped)
	if CharacterStats.weapon_unequipped.is_connected(_on_weapon_unequipped):
		CharacterStats.weapon_unequipped.disconnect(_on_weapon_unequipped)

func _create_gender_selection_ui() -> void:
	"""Create and show the gender selection UI - blocks until selection made"""
	print("🎭 Creating gender selection UI...")
	
	# Pause the game while selecting
	get_tree().paused = true
	
	# Create the dialog
	var dialog = CanvasLayer.new()
	dialog.name = "GenderSelectionDialog"
	dialog.layer = 100  # Put it on top of everything
	
	# Full screen background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(bg)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "SELECT YOUR CHARACTER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)
	
	# Male button
	var male_btn = Button.new()
	male_btn.text = "⚔️ MALE WARRIOR"
	male_btn.custom_minimum_size = Vector2(400, 80)
	male_btn.add_theme_font_size_override("font_size", 32)
	vbox.add_child(male_btn)
	
	# Female button  
	var female_btn = Button.new()
	female_btn.text = "⚔️ FEMALE WARRIOR"
	female_btn.custom_minimum_size = Vector2(400, 80)
	female_btn.add_theme_font_size_override("font_size", 32)
	vbox.add_child(female_btn)
	
	# Add to root IMMEDIATELY (not deferred)
	get_tree().root.add_child(dialog)
	
	# Force dialog to process mode ALWAYS so it works even when game is paused
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	
	print("✅ Gender dialog added to scene tree, waiting for selection...")
	
	# Wait one frame to ensure dialog is rendered
	await get_tree().process_frame
	
	# Connect buttons and wait for selection
	var selection_made = false
	
	male_btn.pressed.connect(func():
		print("👨 Male warrior selected!")
		selected_gender = Gender.MALE
		selection_made = true
	)
	
	female_btn.pressed.connect(func():
		print("👩 Female warrior selected!")
		selected_gender = Gender.FEMALE
		selection_made = true
	)
	
	# Wait for button press
	print("⏳ Waiting for player to click a button...")
	while not selection_made:
		await get_tree().process_frame
	
	print("🎮 Gender confirmed: ", "MALE" if selected_gender == Gender.MALE else "FEMALE")
	
	# Clean up dialog
	dialog.queue_free()
	
	# Unpause the game
	get_tree().paused = false
	
	# Now create the player sprite with the selected gender
	await get_tree().process_frame  # Wait one more frame for cleanup
	create_player_sprite()
	print("✨ Player sprite created with selected gender")


func update_stats_from_character() -> void:
	"""Update player combat stats from CharacterStats system"""
	
	# Update health
	max_health = CharacterStats.get_max_health()
	if current_health <= 0 or current_health > max_health:
		current_health = max_health
	
	# Update movement speed
	if speed_override < 0:
		speed = CharacterStats.get_movement_speed()
	else:
		speed = speed_override
	
	# Update attack damage
	if damage_override < 0:
		attack_damage = CharacterStats.get_base_damage()
	else:
		attack_damage = damage_override
	
	# Update attack cooldown
	if cooldown_override < 0:
		attack_cooldown = CharacterStats.get_attack_cooldown()
	else:
		attack_cooldown = cooldown_override
	
	# Update crit system base chance (preserves pity progress)
	if crit_system:
		crit_system.on_weapon_changed()

	print("📊 Player stats updated:")
	print("  Level: ", CharacterStats.level)
	print("  HP: ", max_health)
	print("  Damage: ", attack_damage)
	print("  Attack Speed: %.3fs" % attack_cooldown)
	print("  Crit Chance: %.1f%%" % (crit_system.get_player_base_crit() * 100 if crit_system else 0))
	print("  Movement Speed: ", speed)

func gain_experience(amount: int) -> void:
	"""Grant experience to the player (called when enemy dies)"""
	CharacterStats.gain_experience(amount)

func _on_character_level_up(new_level: int) -> void:
	"""Called when character levels up"""
	print("🎉 Player reached level ", new_level, "!")
	
	# Update all stats
	update_stats_from_character()
	
	# Heal to full
	current_health = max_health
	health_bar.update_health(current_health, max_health)
	
	# Visual feedback
	if screen_shake:
		screen_shake.add_trauma(0.3)
	
	# Play sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.CHAIN_MILESTONE, -2.0)

func _on_weapon_equipped(weapon) -> void:  # weapon is Weapon type
	"""Called when weapon is equipped"""
	print("⚔️ Weapon equipped: ", weapon.weapon_name)
	update_stats_from_character()

	# Refresh player sprite to show the new weapon
	print("🔄 Refreshing player sprite with new weapon...")
	create_player_sprite()

func _on_weapon_unequipped() -> void:
	"""Called when weapon is unequipped"""
	print("👊 Weapon unequipped - back to unarmed")
	update_stats_from_character()

	# Refresh player sprite to remove weapon
	print("🔄 Refreshing player sprite to unarmed...")
	create_player_sprite()

func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction * speed
	move_and_slide()
	update_facing_direction()
	
	# Update LPC animation
	update_lpc_animation(input_direction)
	
	# Update cone visualizer (now handles rotation AND color)
	update_cone_visualizer()
	
	# Update attack direction for combat
	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()
	
	# Handle held attack (continuous attacking while mouse held)
	if is_mouse_held:
		hold_attack_timer += delta
		if hold_attack_timer >= hold_attack_interval:
			hold_attack_timer = 0.0
			if can_attack:
				attempt_attack()
	
	# Update debug visualization if enabled
	if debug_mode:
		debug_update_timer += delta
		if debug_update_timer >= 0.1:  # Update 10 times per second
			debug_update_timer = 0.0
			update_debug_visualization()
	
	# Handle player death
	if current_health <= 0 and not is_dead:
		die()

func update_lpc_animation(velocity_dir: Vector2) -> void:
	"""Update animation based on movement direction"""
	var anim_sprite = get_node_or_null("PlayerSprite") as AnimatedSprite2D
	if not anim_sprite:
		return

	# Get direction string for animation
	var is_moving = velocity_dir.length() > 0.1
	# When moving: ALWAYS use keyboard direction for animation
	# When standing: use cursor direction
	var dir_str = get_direction_string(velocity_dir) if is_moving else get_direction_string(attack_direction)

	# Determine state
	var prefix = "walk_" if is_moving else "idle_"

	# Don't interrupt attack animations
	if anim_sprite.animation.begins_with("attack_") and anim_sprite.is_playing():
		return

	# Play appropriate animation
	var new_anim = prefix + dir_str
	if anim_sprite.animation != new_anim:
		anim_sprite.play(new_anim)

	# ═══════════════════════════════════════════════════════════════════════
	# FLIP LOGIC - CRITICAL: DO NOT MODIFY WITHOUT UNDERSTANDING
	# ═══════════════════════════════════════════════════════════════════════
	# The pre-generated LPC sprite sheet (walk_longsword.png) has weapon positioning:
	# - Row 0 (up):    weapon in right hand, facing up
	# - Row 1 (left):  weapon in right hand, facing left
	# - Row 2 (down):  weapon in LEFT hand (needs horizontal flip to put in right hand)
	# - Row 3 (right): weapon in right hand, facing right
	#
	# FLIP RULES:
	# 1. When moving DOWN (S key): ALWAYS flip to put weapon in right hand
	#    - Sprite shows weapon in left hand by default
	#    - Exception: backwards walking (cursor UP) = don't flip
	#
	# 2. When moving UP (W key): ONLY flip for backwards walking
	#    - Moving UP + cursor DOWN = walking backwards facing down = FLIP
	#
	# 3. When moving LEFT/RIGHT or standing still: Check cursor direction
	#    - Standing facing down = FLIP (weapon in right hand)
	#    - Otherwise use sprite sheet default
	#
	# 4. Animation selection is ALWAYS based on KEYBOARD input (velocity_dir), not cursor
	#    - This prevents animation changing when cursor moves during vertical movement
	# ═══════════════════════════════════════════════════════════════════════

	var keyboard_dir_str = get_direction_string(velocity_dir) if is_moving else ""
	var cursor_dir_str = get_direction_string(attack_direction)

	if is_moving and keyboard_dir_str == "up":
		# Walking UP: flip if facing down (walking backwards)
		anim_sprite.flip_h = (cursor_dir_str == "down" or cursor_dir_str.contains("down_"))
	elif is_moving and keyboard_dir_str == "down":
		# Walking DOWN: ALWAYS flip (weapon in right hand)
		anim_sprite.flip_h = true
	else:
		# Standing still or moving left/right: flip if facing down
		anim_sprite.flip_h = (dir_str == "down" or dir_str.contains("down_"))

func get_direction_string(dir: Vector2) -> String:
	"""Convert direction vector to animation name string (8-way)"""
	if dir.length() < 0.1:
		return "down"
	
	var angle = dir.angle()
	
	# Convert to 8 directions
	# Right = 0, Down = PI/2, Left = PI, Up = -PI/2
	var deg = rad_to_deg(angle)
	
	# Normalize to 0-360
	if deg < 0:
		deg += 360
	
	# 8 directions, 45 degrees each
	if deg >= 337.5 or deg < 22.5:
		return "right"
	elif deg >= 22.5 and deg < 67.5:
		return "down_right"
	elif deg >= 67.5 and deg < 112.5:
		return "down"
	elif deg >= 112.5 and deg < 157.5:
		return "down_left"
	elif deg >= 157.5 and deg < 202.5:
		return "left"
	elif deg >= 202.5 and deg < 247.5:
		return "up_left"
	elif deg >= 247.5 and deg < 292.5:
		return "up"
	else:  # 292.5 to 337.5
		return "up_right"

func update_facing_direction() -> void:
	var mouse_pos = get_global_mouse_position()
	var direction_to_mouse = (mouse_pos - global_position).normalized()
	attack_direction = direction_to_mouse

	# ✨ ISOMETRIC STYLE: Flip sprite instead of rotating player
	# Player node stays at 0 rotation, sprite flips left/right

	# NOTE: Flip logic is now handled in update_lpc_animation()
	# Don't flip here - it conflicts with animation-based flipping
	
	# Rotate cone visualizer to show attack direction
	#if cone_visualizer:
		#var target_rotation = direction_to_mouse.angle()
	#	cone_visualizer.rotation = target_rotation

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_mouse_held = true
				hold_attack_timer = 0.0
				
				# ✨ FIX #1: Check if clicking on weakpoint FIRST
				if is_clicking_on_weakpoint(event):
					print("🎯 Clicking on weakpoint - skipping player attack")
					return  # Let the weakpoint handle it!
				
				# ✨ FIX #2: Try crit window click on enemy body
				if check_crit_window_click(event):
					return  # Handled crit window attack
				
				# Normal attack
				attempt_attack()
			else:
				# Mouse released - stop hold state
				is_mouse_held = false
				hold_attack_timer = 0.0
		
		# ✨ FIX: CAMERA ZOOM - Mouse wheel handling (disabled when shop is open)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not is_shop_open():
				zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not is_shop_open():
				zoom_out()
	
	# Debug mode toggle
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_G:
				# Switch gender
				print("🔄 Switching character gender...")
				
				# Flag to prevent animation updates during switch
				var old_process_mode = process_mode
				set_physics_process(false)  # Stop movement updates during switch
				
				if selected_gender == Gender.MALE:
					selected_gender = Gender.FEMALE
					print("🎭 Target: FEMALE character")
				else:
					selected_gender = Gender.MALE
					print("🎭 Target: MALE character")
				
				# Recreate sprite and wait for completion
				await create_player_sprite()
				
				# Wait one more frame to ensure sprite is ready
				await get_tree().process_frame
				
				# Re-enable physics
				set_physics_process(true)
				print("✅ Character sprite switched!")
			
			KEY_F3:
				debug_mode = !debug_mode
				print("Debug mode: ", "ON" if debug_mode else "OFF")
				debug_update_timer = 0.0  # Reset timer
				update_debug_visualization()  # Immediate update
			
			KEY_F4:
				# Add 1 level
				CharacterStats.debug_add_levels(1)
				print("Added 1 level (now level ", CharacterStats.level, ")")
			
			KEY_F5:
				# Add 5 levels
				CharacterStats.debug_add_levels(5)
				print("Added 5 levels (now level ", CharacterStats.level, ")")
			
			KEY_F6:
				# Reset to level 1
				CharacterStats.reset_character()
				update_stats_from_character()
				current_health = max_health
				health_bar.update_health(current_health, max_health)
				print("Character reset to level 1")
			
			KEY_F7:
				# Print all stats
				CharacterStats.print_stats()
			
			KEY_F8:
				# Fix negative XP
				CharacterStats.debug_fix_negative_xp()
				update_stats_from_character()
				print("Press F7 to verify XP is fixed")

			KEY_C:
				# Toggle character sheet (includes inventory)
				if character_ui:
					character_ui.toggle_character_ui()

func check_crit_window_click(event: InputEvent) -> bool:
	"""Check if clicking on enemy during crit window. Returns true if handled."""
	var click_pos = get_global_mouse_position()
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Only handle enemies in crit window
		if not ("in_crit_window" in enemy and enemy.in_crit_window):
			continue
		
		# Check if we clicked on this enemy
		var enemy_size = 30.0
		if enemy.has_node("CollisionShape2D"):
			var collision = enemy.get_node("CollisionShape2D")
			if collision.shape is RectangleShape2D:
				var rect = collision.shape as RectangleShape2D
				enemy_size = max(rect.size.x, rect.size.y) * enemy.scale.x / 2.0
		
		var distance = click_pos.distance_to(enemy.global_position)
		
		# If clicked on this enemy
		if distance < enemy_size:
			# Check if we're in attack range
			var distance_to_edge = global_position.distance_to(enemy.global_position) - enemy_size
			if distance_to_edge <= attack_range + Constants.PLAYER_ATTACK_RANGE_BUFFER:
				handle_crit_window_attack(enemy, click_pos)
				return true  # Handled the click
			else:
				print("⚠️ Crit window enemy out of range")
				return true  # Still handled (prevent normal attack)
	
	return false  # No crit window enemy clicked
	
	
func is_clicking_on_weakpoint(event: InputEvent) -> bool:
	"""Check if clicking on weakpoint and trigger it directly"""
	var click_pos = get_global_mouse_position()
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Only check enemies in crit window
		if not ("in_crit_window" in enemy and enemy.in_crit_window):
			continue
		
		# Check if any weakpoint is at the click position
		if "weakpoints" in enemy:
			for weakpoint in enemy.weakpoints:
				if not is_instance_valid(weakpoint):
					continue
				if "is_destroyed" in weakpoint and weakpoint.is_destroyed:
					continue
				
				var distance = click_pos.distance_to(weakpoint.global_position)
				var weakpoint_radius = 28 * weakpoint.scale.x
				
				if distance < weakpoint_radius:
					print("🎯 Found weakpoint at click position!")
					# ✨ FIX: Directly call hit() instead of relying on input_event
					if weakpoint.has_method("hit"):
						weakpoint.hit()
						print("💥 Manually triggered weakpoint hit!")
					return true
	
	return false

func handle_crit_window_attack(enemy: Node, click_pos: Vector2) -> void:
	"""Handle attack on enemy body during crit window"""
	
	# ✨ FIX #2: Simplified - just attack the enemy normally
	# Weakpoints handle themselves now via is_clicking_on_weakpoint()
	
	if can_attack:
		can_attack = false  # Set immediately to prevent spam
		
		# Get chain multiplier for damage calculation
		var chain_multiplier = ChainManager.get_damage_multiplier()
		var damage = attack_damage * chain_multiplier
		
		if "take_damage" in enemy:
			enemy.take_damage(damage, false)
		
		finish_attack_cooldown()
		print("⚔️ Enemy body hit during crit window (%.1f dmg, %.2fs cooldown)" % [damage, attack_cooldown])
	else:
		print("⏱️ Attack on cooldown - ignoring click")


func attempt_attack() -> void:
	# 🔧 FIX: Set flag IMMEDIATELY to prevent spam clicks from racing through
	if not can_attack:
		return
	
	can_attack = false  # Set immediately, before any other code!
	
	# Trigger attack animation
	var anim_sprite = get_node_or_null("PlayerSprite") as AnimatedSprite2D
	if anim_sprite:
		var dir_str = get_direction_string(attack_direction)
		anim_sprite.play("attack_" + dir_str)
	
	ChainManager.register_attack()
	
	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()
	
	var enemies_in_cone = get_enemies_in_cone()
	
	# ✨ NEW: Play swing sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.SWING, global_position, -8.0)
	
	if enemies_in_cone.size() > 0:
		attack_enemies_in_cone(enemies_in_cone)
		finish_attack_cooldown()
	else:
		# ✨ NEW: Play miss sound when no enemies hit
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.MISS, global_position, -10.0)
		finish_attack_cooldown()

func get_enemies_in_cone() -> Array:
	var enemies_in_cone = []
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var cone_half_angle_rad = deg_to_rad(attack_cone_angle / 2.0)
	
	# ✨ ISOMETRIC STYLE: Use attack_direction since player doesn't rotate
	# The cone visual rotates to face attack_direction, so detection matches
	var forward_direction = attack_direction
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		
		# Get enemy size for more forgiving detection
		var enemy_radius = 30.0  # Approximate enemy size
		if enemy.has_node("CollisionShape2D"):
			var collision = enemy.get_node("CollisionShape2D")
			if collision.shape is RectangleShape2D:
				var rect = collision.shape as RectangleShape2D
				enemy_radius = max(rect.size.x, rect.size.y) * enemy.scale.x / 2.0
		
		# Check distance to enemy edge (not just center)
		var distance_to_center = global_position.distance_to(enemy.global_position)
		var distance_to_edge = distance_to_center - enemy_radius
		
		# If enemy edge is beyond attack range, skip
		if distance_to_edge > attack_range:
			continue
		
		# Check if enemy overlaps cone angle
		# We check the angle to the enemy center
		var to_enemy = (enemy.global_position - global_position).normalized()
		var angle_diff = forward_direction.angle_to(to_enemy)
		
		# Add enemy radius as angular tolerance for more forgiving detection
		var angular_tolerance = atan2(enemy_radius, distance_to_center)
		
		# Enemy is in cone if angle difference is within tolerance
		if abs(angle_diff) <= cone_half_angle_rad + angular_tolerance:
			enemies_in_cone.append(enemy)
	
	return enemies_in_cone

func attack_enemies_in_cone(enemies: Array) -> void:
	var chain_multiplier = ChainManager.get_damage_multiplier()
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		
		# Connect to enemy signals
		connect_enemy_signals(enemy)
		
		# ✨ FIX: Don't roll for crit if enemy is already in a crit window!
		var enemy_already_in_crit_window = false
		if "in_crit_window" in enemy:
			enemy_already_in_crit_window = enemy.in_crit_window
		
		var damage = attack_damage * chain_multiplier
		
		# Only roll for NEW crit if enemy is NOT already in a crit window
		if not enemy_already_in_crit_window:
			var is_crit = crit_system.roll_for_crit()
			
			if is_crit:
				# Start crit window
				crit_window_manager.start_window(enemy)
				if not crit_window_manager.window_completed.is_connected(_on_crit_window_completed):
					crit_window_manager.window_completed.connect(_on_crit_window_completed.bind(enemy))
			else:
				# Normal attack
				apply_damage_with_feedback(enemy, damage, false, false)
		else:
			# Enemy already in crit window - just do normal damage (don't roll for new crit)
			print("⚠️ Enemy already in crit window, applying normal damage (no new crit roll)")
			apply_damage_with_feedback(enemy, damage, false, false)

func connect_enemy_signals(enemy: Node) -> void:
	# Connect to weakpoint hit signal
	if enemy.has_signal("weakpoint_hit_success"):
		if not enemy.weakpoint_hit_success.is_connected(_on_weakpoint_hit):
			enemy.weakpoint_hit_success.connect(_on_weakpoint_hit.bind(enemy))
	
	# Connect to damage taken signal (we'll add this to enemy)
	if enemy.has_signal("damage_taken"):
		if not enemy.damage_taken.is_connected(_on_enemy_damaged):
			enemy.damage_taken.connect(_on_enemy_damaged.bind(enemy))

func _on_weakpoint_hit(enemy: Node) -> void:
	# Weakpoint hit - critical feedback with shake
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, true, true)

func _on_enemy_damaged(damage: float, is_crit: bool, enemy: Node) -> void:
	# Enemy took damage - trigger feedback
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, false)

func apply_damage_with_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
	# Apply damage
	enemy.take_damage(damage, is_crit)
	
	# Trigger ALL feedback effects
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, hit_weakpoint)
	
	# Trigger hit flash on enemy
	if enemy.has_node("HitFlash"):
		enemy.get_node("HitFlash").flash(is_crit)

func _on_crit_window_completed(success_ratio: float, total_destroyed: int, enemy: Node) -> void:
	var all_destroyed = (total_destroyed == 3)
	
	# Check if enemy died
	var enemy_died = false
	if not is_instance_valid(enemy) or (enemy.get("is_dying") and enemy.is_dying):
		enemy_died = true
	
	# Update chain
	if all_destroyed:
		ChainManager.on_crit_window_completed(true)
	elif enemy_died:
		print("⚡ Chain maintained (enemy died)")
	else:
		ChainManager.on_crit_window_completed(false)
	
	# Calculate and apply damage
	if is_nan(success_ratio) or is_inf(success_ratio):
		success_ratio = 0.0
	
	var chain_multiplier = ChainManager.get_damage_multiplier()
	var base_crit_damage = attack_damage * 2.0
	var multiplier = 1.0 + success_ratio
	var final_damage = base_crit_damage * multiplier * chain_multiplier
	
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		if not enemy.get("is_dying") and enemy.current_health > 0:
			# Apply damage with full critical feedback
			apply_damage_with_feedback(enemy, final_damage, true, all_destroyed)
	
	# Disconnect
	if crit_window_manager.window_completed.is_connected(_on_crit_window_completed):
		crit_window_manager.window_completed.disconnect(_on_crit_window_completed)

func finish_attack_cooldown() -> void:
	"""Finish the attack cooldown (can_attack already set to false in attempt_attack)"""
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func take_damage(amount: float) -> void:
	print("Player taking %.1f damage (current: %.1f)" % [amount, current_health])
	current_health -= amount
	
	# Ensure health doesn't go below 0
	if current_health < 0:
		current_health = 0
	
	health_bar.update_health(current_health, max_health)

	# Spawn damage number behind player (opposite of facing direction)
	CombatText.create_damage(amount, global_position, get_tree().root, attack_direction)
	
	print("Player health now: %.1f / %.1f" % [current_health, max_health])
	
	# Flash player sprite red when hit
	flash_player_sprite()
	
	if current_health <= 0:
		print("💀 Player death triggered!")
		die()

func heal(amount: float) -> void:
	"""Heal the player by the given amount"""
	if current_health >= max_health:
		return  # Already at full health
	
	var actual_heal = min(amount, max_health - current_health)
	current_health += actual_heal
	
	# Update health bar
	health_bar.update_health(current_health, max_health)

	# Spawn heal number behind player (opposite of facing direction)
	CombatText.create_heal(actual_heal, global_position, get_tree().root, attack_direction)
	
	print("Player healed %.1f HP (now %.1f / %.1f)" % [actual_heal, current_health, max_health])

func flash_player_sprite() -> void:
	"""Flash the player sprite red when taking damage"""
	var player_sprite = get_node_or_null("PlayerSprite")
	if not player_sprite:
		return
	
	# ✨ FIX: Always restore to WHITE, not current color
	# This prevents getting stuck red if multiple rapid hits occur
	player_sprite.modulate = Color(2.0, 0.5, 0.5, 1.0)  # Red flash
	
	# Use a short timer to restore color
	await get_tree().create_timer(0.1).timeout
	
	if player_sprite and is_instance_valid(player_sprite):
		player_sprite.modulate = Color.WHITE  # Always restore to white


## Visual System Functions

# WEAPON SYSTEM REMOVED - To be reimplemented from scratch

func create_player_sprite() -> void:
	print("🧹 Removing old sprites...")
	
	# Get references to sprites to remove
	var player_sprite = get_node_or_null("PlayerSprite")
	var player_shadow = get_node_or_null("PlayerShadow")
	
	# Remove old sprites IMMEDIATELY (not queued)
	if player_sprite:
		remove_child(player_sprite)
		player_sprite.queue_free()
		print("  ❌ Removed old PlayerSprite")
	
	if player_shadow:
		remove_child(player_shadow)
		player_shadow.queue_free()
		print("  ❌ Removed old PlayerShadow")
	
	# Also check for any other Sprite2D or AnimatedSprite2D nodes
	for child in get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			if child.name.contains("Sprite") or child.name.contains("Shadow"):
				remove_child(child)
				child.queue_free()
				print("  ❌ Removed stray sprite: ", child.name)
	
	# Wait to ensure cleanup
	await get_tree().process_frame
	await get_tree().process_frame
	
	print("🎨 Creating NEW sprite for gender: ", "MALE" if selected_gender == Gender.MALE else "FEMALE")
	
	# Create shadow
	var shadow = Sprite2D.new()
	shadow.name = "PlayerShadow"
	var shadow_img = Image.create(48, 16, false, Image.FORMAT_RGBA8)
	shadow_img.fill(Color.TRANSPARENT)
	
	# Draw elliptical shadow
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
	
	# Create animated sprite
	var anim_sprite = AnimatedSprite2D.new()
	anim_sprite.name = "PlayerSprite"
	anim_sprite.position = Vector2(0, -8)
	anim_sprite.centered = true
	
	# No tint for any gender - show natural colors
	anim_sprite.modulate = Color.WHITE
	
	add_child(anim_sprite)
	
	# Load and setup LPC animations
	setup_lpc_animations(anim_sprite)
	
	# Start with idle down
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("idle_down"):
		anim_sprite.play("idle_down")
	else:
		print("ERROR: No animations created!")

func setup_lpc_animations(anim_sprite: AnimatedSprite2D) -> void:
	"""Setup all LPC animations with layered compositing - separate walk, attack, and hurt sprites"""
	print("🎨 setup_lpc_animations called")
	print("   Selected gender: ", selected_gender)
	
	# Determine body type based on selected gender
	var body_type = "human" if selected_gender == Gender.MALE else "female"
	print("   Body type: ", body_type)
	
	# WALK sprite paths
	var BODY_WALK_PATH = "res://assets/characters/BODY_" + body_type + "_walk.png"
	print("   Checking for: ", BODY_WALK_PATH)
	print("   File exists: ", ResourceLoader.exists(BODY_WALK_PATH))
	const TORSO_WALK_PATH = "res://assets/characters/TORSO_leather_armor_torso_walk.png"
	const LEGS_WALK_PATH = "res://assets/characters/LEGS_pants_greenish_walk.png"
	const HAT_WALK_PATH = "res://assets/characters/HEAD_leather_armor_hat_walk.png"
	
	# For female, add hair layer
	var HAIR_PATH = ""
	if selected_gender == Gender.FEMALE:
		HAIR_PATH = "res://assets/characters/HAIR_female.png"
	
	# SLASH sprite paths
	var BODY_SLASH_PATH = "res://assets/characters/BODY_" + body_type + "_slash.png"
	const TORSO_SLASH_PATH = "res://assets/characters/TORSO_leather_armor_torso_slash.png"
	const LEGS_SLASH_PATH = "res://assets/characters/LEGS_pants_greenish_slash.png"
	const HAT_SLASH_PATH = "res://assets/characters/HEAD_leather_armor_hat_slash.png"
	# WEAPON SYSTEM REMOVED - see git commit for details on issues faced
	
	# HURT sprite paths
	var BODY_HURT_PATH = "res://assets/characters/BODY_" + body_type + "_hurt.png"
	const TORSO_HURT_PATH = "res://assets/characters/TORSO_leather_armor_torso_hurt.png"
	const LEGS_HURT_PATH = "res://assets/characters/LEGS_pants_greenish_hurt.png"
	const HAT_HURT_PATH = "res://assets/characters/HEAD_leather_armor_hat_hurt.png"
	
	# For female, add hair layer (frame-by-frame compositing)
	var hair_img = null
	if selected_gender == Gender.FEMALE and HAIR_PATH != "" and ResourceLoader.exists(HAIR_PATH):
		var tex = ResourceLoader.load(HAIR_PATH, "Texture2D")
		if tex:
			hair_img = tex.get_image()
			print("   🦱 Hair sprite loaded: ", hair_img.get_size())
			print("   🦱 Hair layout: 3 columns (down/up/right) x 7 rows (styles)")
	
	# Load and composite WALK sprites (NO WEAPON - weapons only show during attacks)
	var walk_composite: Image = null

	# STEP 1: Start with body
	if ResourceLoader.exists(BODY_WALK_PATH):
		var body_tex = ResourceLoader.load(BODY_WALK_PATH, "Texture2D")
		if body_tex:
			walk_composite = body_tex.get_image().duplicate()
			print("   📦 Base body loaded: ", walk_composite.get_size())

	if walk_composite:
		# For FEMALE: Overlay just the HAIR portion from hair sprite (not face/arms)
		if selected_gender == Gender.FEMALE and hair_img:
			print("   🦱 Overlaying HAIR ONLY from hair sprite...")
			overlay_hair_on_spritesheet(walk_composite, hair_img, 9, 4, 64)

		# Layer clothing on sprite (works for both male and female)
		if ResourceLoader.exists(LEGS_WALK_PATH):
			var legs_tex = ResourceLoader.load(LEGS_WALK_PATH, "Texture2D")
			if legs_tex:
				print("   👖 Adding legs/pants layer")
				walk_composite.blend_rect(legs_tex.get_image(), Rect2i(0, 0, 576, 256), Vector2i(0, 0))

		if ResourceLoader.exists(TORSO_WALK_PATH):
			var torso_tex = ResourceLoader.load(TORSO_WALK_PATH, "Texture2D")
			if torso_tex:
				print("   👕 Adding torso/armor layer")
				walk_composite.blend_rect(torso_tex.get_image(), Rect2i(0, 0, 576, 256), Vector2i(0, 0))

		# Only apply hat for male characters (female shows hair instead)
		if selected_gender == Gender.MALE and ResourceLoader.exists(HAT_WALK_PATH):
			var hat_tex = ResourceLoader.load(HAT_WALK_PATH, "Texture2D")
			if hat_tex:
				print("   🎩 Adding hat layer (male only)")
				walk_composite.blend_rect(hat_tex.get_image(), Rect2i(0, 0, 576, 256), Vector2i(0, 0))

		# NOTE: Weapons are NOT shown during walk animations (sheathed)
		# Weapons only appear during attack/slash animations
		print("   ✅ Walk sprite complete (weapon sheathed)")

	# Load and composite SLASH sprites (NO WEAPONS - system removed)
	var slash_composite: Image = null

	# STEP 1: Start with body sprite
	if ResourceLoader.exists(BODY_SLASH_PATH):
		var body_tex = ResourceLoader.load(BODY_SLASH_PATH, "Texture2D")
		if body_tex:
			slash_composite = body_tex.get_image().duplicate()
			print("   📦 Base body loaded for slash")

	if slash_composite:
		# For FEMALE: Overlay just hair
		if selected_gender == Gender.FEMALE and hair_img:
			print("   🦱 Overlaying HAIR ONLY for slash...")
			overlay_hair_on_spritesheet(slash_composite, hair_img, 6, 4, 64)

		# Layer clothing
		if ResourceLoader.exists(LEGS_SLASH_PATH):
			var legs_tex = ResourceLoader.load(LEGS_SLASH_PATH, "Texture2D")
			if legs_tex: slash_composite.blend_rect(legs_tex.get_image(), Rect2i(0, 0, 384, 256), Vector2i(0, 0))

		if ResourceLoader.exists(TORSO_SLASH_PATH):
			var torso_tex = ResourceLoader.load(TORSO_SLASH_PATH, "Texture2D")
			if torso_tex: slash_composite.blend_rect(torso_tex.get_image(), Rect2i(0, 0, 384, 256), Vector2i(0, 0))

		# Only apply hat for male characters (female shows hair instead)
		if selected_gender == Gender.MALE and ResourceLoader.exists(HAT_SLASH_PATH):
			var hat_tex = ResourceLoader.load(HAT_SLASH_PATH, "Texture2D")
			if hat_tex: slash_composite.blend_rect(hat_tex.get_image(), Rect2i(0, 0, 384, 256), Vector2i(0, 0))

		print("   ✅ Slash sprite complete (unarmed - weapon system removed)")
	
	# Load and composite HURT sprites
	var hurt_composite: Image = null
	
	# Start with body sprite as base
	if ResourceLoader.exists(BODY_HURT_PATH):
		var body_tex = ResourceLoader.load(BODY_HURT_PATH, "Texture2D")
		if body_tex:
			hurt_composite = body_tex.get_image().duplicate()
	
	if hurt_composite:
		# For FEMALE: Overlay hair/face
		if selected_gender == Gender.FEMALE and hair_img:
			print("   🦱 Overlaying HAIR ONLY for hurt...")
			overlay_hair_on_spritesheet(hurt_composite, hair_img, 6, 1, 64)
		
		# Layer clothing
		if ResourceLoader.exists(LEGS_HURT_PATH):
			var legs_tex = ResourceLoader.load(LEGS_HURT_PATH, "Texture2D")
			if legs_tex: hurt_composite.blend_rect(legs_tex.get_image(), Rect2i(0, 0, 384, 64), Vector2i(0, 0))
		
		if ResourceLoader.exists(TORSO_HURT_PATH):
			var torso_tex = ResourceLoader.load(TORSO_HURT_PATH, "Texture2D")
			if torso_tex: hurt_composite.blend_rect(torso_tex.get_image(), Rect2i(0, 0, 384, 64), Vector2i(0, 0))
		
		# Only apply hat for male characters (female shows hair instead)
		if selected_gender == Gender.MALE and ResourceLoader.exists(HAT_HURT_PATH):
			var hat_tex = ResourceLoader.load(HAT_HURT_PATH, "Texture2D")
			if hat_tex: hurt_composite.blend_rect(hat_tex.get_image(), Rect2i(0, 0, 384, 64), Vector2i(0, 0))
	
	if not walk_composite:
		print("ERROR: Could not load player walk sprites for ", body_type)
		# Fallback
		var fallback_frames = SpriteFrames.new()
		fallback_frames.add_animation("idle_down")
		var fallback_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color.BROWN)
		fallback_frames.add_frame("idle_down", ImageTexture.create_from_image(fallback_img))
		anim_sprite.sprite_frames = fallback_frames
		return
	
	print("🎨 Player using ", body_type.to_upper(), " character with separate WALK and SLASH sprites")
	
	var walk_texture = ImageTexture.create_from_image(walk_composite)
	var slash_texture = null
	if slash_composite:
		slash_texture = ImageTexture.create_from_image(slash_composite)
	
	var sprite_frames = SpriteFrames.new()
	
	# WALK animations - Use frames 1-8 (skip frame 0, same as LPC generator)
	# LPC generator uses 8 FPS and frames [1,2,3,4,5,6,7,8]
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_up", 0, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_left", 1, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_down", 2, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_right", 3, 8, 8.0, true, 1)
	
	# Diagonals - reuse cardinal directions
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_up_left", 1, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_up_right", 3, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_down_left", 1, 8, 8.0, true, 1)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "walk_down_right", 3, 8, 8.0, true, 1)
	
	# IDLE animations - use middle frame (frame 4) from walk
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_up", 0, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_left", 1, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_down", 2, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_right", 3, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_up_left", 0, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_up_right", 0, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_down_left", 2, 1, 1.0, true, 4)
	create_lpc_animation_with_offset(sprite_frames, walk_texture, "idle_down_right", 2, 1, 1.0, true, 4)
	
	# ATTACK animations from slash sprite - 6 frames per row
	if slash_texture:
		create_lpc_animation(sprite_frames, slash_texture, "attack_up", 0, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_left", 1, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_down", 2, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_right", 3, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_up_left", 0, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_up_right", 0, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_down_left", 2, 6, 15.0, false)
		create_lpc_animation(sprite_frames, slash_texture, "attack_down_right", 2, 6, 15.0, false)
	
	# HURT animation from hurt sprite - 6 frames, single row
	if hurt_composite:
		var hurt_texture = ImageTexture.create_from_image(hurt_composite)
		create_lpc_animation(sprite_frames, hurt_texture, "hurt", 0, 6, 12.0, false)
	
	anim_sprite.sprite_frames = sprite_frames
	print("LPC animations loaded successfully (Walk + Slash + Hurt sprites)!")
	
func overlay_hair_on_spritesheet(body_sheet: Image, hair_sheet: Image, frames_per_row: int, num_rows: int, cell_size: int) -> void:
	"""Overlay hair/face from hair sprite onto body spritesheet
	Only overlays the TOP PORTION (hair + face, NOT arms/shoulders)
	"""
	
	var hair_cell_size = 40
	var hair_style_row = 0
	
	# Only use top 50% of hair sprite (top 20 pixels = hair + face only, no arms)
	var hair_height_to_use = hair_cell_size / 2  # Only top 20 pixels
	
	# Map directions
	var direction_map = {
		0: 1,  # up
		1: 2,  # left
		2: 0,  # down
		3: 2   # right
	}
	
	for row in range(num_rows):
		var hair_col = direction_map.get(row, 0)
		
		for frame in range(frames_per_row):
			var dest_x = frame * cell_size
			var dest_y = row * cell_size
			
			var hair_x = hair_col * hair_cell_size
			var hair_y = hair_style_row * hair_cell_size
			
			# Center hair horizontally and position on top of head
			var offset_x = (cell_size - hair_cell_size) / 2
			var offset_y = 8  # Position hair 8px down to sit on top of head
			
			# Overlay ONLY TOP HALF of hair pixels (hair + face, no arms!)
			for y in range(hair_height_to_use):  # Only top 20 pixels!
				for x in range(hair_cell_size):
					var src_x = hair_x + x
					var src_y = hair_y + y
					if src_x < hair_sheet.get_width() and src_y < hair_sheet.get_height():
						var hair_pixel = hair_sheet.get_pixel(src_x, src_y)
						if hair_pixel.a > 0.01:
							var out_x = dest_x + offset_x + x
							var out_y = dest_y + offset_y + y
							if out_x < body_sheet.get_width() and out_y < body_sheet.get_height():
								var body_pixel = body_sheet.get_pixel(out_x, out_y)
								var blended = body_pixel.lerp(hair_pixel, hair_pixel.a)
								body_sheet.set_pixel(out_x, out_y, blended)
	
	print("   ✅ Hair overlaid (top 20px only)")

func create_lpc_animation(sprite_frames: SpriteFrames, texture: ImageTexture, anim_name: String, row: int, frame_count: int, fps: float, loop: bool = true) -> void:
	"""Extract frames from LPC spritesheet row and create animation"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)
	
	var source_image = texture.get_image()
	
	for frame_idx in range(frame_count):
		# Extract 64x64 frame from row
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(source_image, Rect2i(frame_idx * 64, row * 64, 64, 64), Vector2i(0, 0))
		
		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

func create_lpc_animation_with_offset(sprite_frames: SpriteFrames, texture: ImageTexture, anim_name: String, row: int, frame_count: int, fps: float, loop: bool, start_frame: int) -> void:
	"""Extract frames from LPC spritesheet row starting at specific frame"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)
	
	var source_image = texture.get_image()
	
	for i in range(frame_count):
		var frame_idx = start_frame + i
		# Extract 64x64 frame from row
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(source_image, Rect2i(frame_idx * 64, row * 64, 64, 64), Vector2i(0, 0))
		
		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

func create_cone_visualizer() -> void:
	"""Create visual cone showing attack area"""
	# Remove old visualizer if it exists
	if cone_visualizer:
		cone_visualizer.queue_free()
	
	cone_visualizer = Polygon2D.new()
	cone_visualizer.name = "ConeVisualizer"
	
	# Set color all at once (Color is a value type, not a reference!)
	cone_visualizer.color = Color(1.0, 0.0, 0.0, 1.0)  # Red, 100% opaque
	cone_visualizer.z_index = 1  # In front of player
	cone_visualizer.visible = true
	
	# Create cone shape points
	var points = PackedVector2Array()
	var segments = 32
	var cone_half_angle_rad = deg_to_rad(attack_cone_angle / 2.0)
	
	# Start at player position (origin)
	points.append(Vector2.ZERO)
	
	# Create arc from -half_angle to +half_angle
	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var angle = lerp(-cone_half_angle_rad, cone_half_angle_rad, t)
		var point = Vector2(cos(angle), sin(angle)) * attack_range
		points.append(point)
	
	# Close the cone back to center
	points.append(Vector2.ZERO)
	
	cone_visualizer.polygon = points
	add_child(cone_visualizer)
	cone_visualizer.queue_redraw()
	
	print("✅ Cone visualizer created (angle: %.0f°, range: %.0f)" % [attack_cone_angle, attack_range])
	print("   🔴 Should be BRIGHT RED and visible!")
	
func create_range_indicator() -> void:
	"""Create visual indicator for attack range"""
	var attack_range_node = get_node_or_null("AttackRange")
	if not attack_range_node:
		push_error("❌ AttackRange node not found!")
		return
	
	# Create circle line for range indicator
	var circle = Line2D.new()
	circle.name = "RangeIndicator"
	circle.width = 3.0
	circle.default_color = Color(0.5, 0.5, 0.5, 0.3)  # Gray, semi-transparent
	circle.z_index = -1  # Behind player
	
	# Create circle points
	var segments = 64
	var radius = attack_range
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = Vector2(cos(angle), sin(angle)) * radius
		circle.add_point(point)
	
	attack_range_node.add_child(circle)
	print("✅ Range indicator created (radius: %.0f)" % radius)

func update_cone_visualizer() -> void:
	"""Update cone visualizer rotation and color (color throttled for performance)"""
	if not cone_visualizer:
		return

	# ALWAYS rotate cone to face mouse cursor (cheap, needs to be smooth)
	var mouse_pos = get_global_mouse_position()
	var direction_to_mouse = (mouse_pos - global_position).normalized()
	cone_visualizer.rotation = direction_to_mouse.angle()

	# THROTTLED: Only update color every 0.1s instead of 60 FPS (10x performance boost!)
	# get_enemies_in_cone() is VERY expensive (checks all enemies in scene)
	# Color update doesn't need to be 60 FPS - 10 FPS is plenty
	cone_update_timer += get_physics_process_delta_time()
	if cone_update_timer >= 0.1:  # Update 10 times per second
		cone_update_timer = 0.0

		# Update color based on enemies in cone
		var enemies_in_range = get_enemies_in_cone()
		if enemies_in_range.size() > 0:
			# Bright green when enemies are targetable (35% alpha = VISIBLE)
			cone_visualizer.color = Color(0.2, 1.0, 0.2, 0.35)
		else:
			# Light gray when no enemies (25% alpha = VISIBLE)
			cone_visualizer.color = Color(0.6, 0.6, 0.7, 0.25)

func update_debug_visualization() -> void:
	if not debug_shapes:
		return

	# === STEP 1: IMMEDIATE CLEANUP ===
	# Clean up player-space debug shapes IMMEDIATELY
	for child in debug_shapes.get_children():
		debug_shapes.remove_child(child)
		child.queue_free()

	# Clean up ALL tracked world-space debug nodes IMMEDIATELY
	for node in world_debug_nodes:
		if is_instance_valid(node) and node.get_parent():
			node.get_parent().remove_child(node)
			node.queue_free()
	world_debug_nodes.clear()

	# Update debug label visibility and text
	if debug_label:
		if debug_mode:
			debug_label.visible = true
			debug_label.text = "Position: (%.1f, %.1f)" % [global_position.x, global_position.y]
		else:
			debug_label.visible = false

	# If debug mode is off, stop here
	if not debug_mode:
		return
	
	# === STEP 2: DRAW NEW DEBUG SHAPES ===
	# Draw player collision shape (in local space - rotates with player)
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is CircleShape2D:
			var circle = collision.shape as CircleShape2D
			var debug_circle = draw_debug_circle(Vector2.ZERO, circle.radius, Color.GREEN)
			debug_shapes.add_child(debug_circle)
	
	# Draw attack cone outline (in local space - rotates with player)
	var cone_outline = Line2D.new()
	cone_outline.width = 2.0
	cone_outline.default_color = Color.RED
	
	var half_angle = deg_to_rad(attack_cone_angle / 2.0)
	cone_outline.add_point(Vector2.ZERO)
	cone_outline.add_point(Vector2(cos(-half_angle), sin(-half_angle)) * attack_range)
	cone_outline.add_point(Vector2.ZERO)
	cone_outline.add_point(Vector2(cos(half_angle), sin(half_angle)) * attack_range)
	
	debug_shapes.add_child(cone_outline)
	
	# Draw enemy collision shapes in WORLD SPACE (don't rotate)
	var parent = get_parent()
	if parent:
		var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.has_method("draw_debug_shapes_world"):
				var enemy_debug_node = enemy.draw_debug_shapes_world(parent)
				if enemy_debug_node:
					world_debug_nodes.append(enemy_debug_node)

func draw_debug_circle(center: Vector2, radius: float, color: Color) -> Line2D:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color
	
	var segments = 32
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)
	
	return line

# ═══════════════════════════════════════════════════════════════════════════
# CAMERA ZOOM SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func zoom_in() -> void:
	"""Zoom camera in (closer view)"""
	target_zoom = clamp(target_zoom + zoom_speed, zoom_min, zoom_max)
	if camera:
		camera.zoom = Vector2(target_zoom, target_zoom)
		print("📷 Zoom: %.1fx" % target_zoom)

func zoom_out() -> void:
	"""Zoom camera out (wider view)"""
	target_zoom = clamp(target_zoom - zoom_speed, zoom_min, zoom_max)
	if camera:
		camera.zoom = Vector2(target_zoom, target_zoom)
		print("📷 Zoom: %.1fx" % target_zoom)

func update_camera_zoom(delta: float) -> void:
	"""Smoothly interpolate camera zoom to target"""
	if not camera:
		return

	# Smoothly lerp current zoom to target zoom
	var current_zoom_value = camera.zoom.x
	var new_zoom = lerp(current_zoom_value, target_zoom, zoom_speed)
	camera.zoom = Vector2(new_zoom, new_zoom)

func is_shop_open() -> bool:
	"""Check if any shop UI is currently open"""
	# Look for ShopUI in the scene tree
	var root = get_tree().root
	for child in root.get_children():
		if child is CanvasLayer and child.has_method("close_shop"):
			if child.visible:
				return true
	return false

# ═══════════════════════════════════════════════════════════════════════════
# DEATH & RESPAWN
# ═══════════════════════════════════════════════════════════════════════════

func die() -> void:
	if is_dead:
		print("⚠️  Already dead, ignoring duplicate die() call")
		return
	
	is_dead = true
	print("\n💀 ===== PLAYER DEATH =====")
	print("Position: ", global_position)
	print("Remaining health: ", current_health)
	
	# Disable player controls during death
	set_physics_process(false)
	
	# ✨ Play death animation (hurt animation) and wait for it to complete
	var anim_sprite = get_node_or_null("PlayerSprite") as AnimatedSprite2D
	if anim_sprite and anim_sprite.sprite_frames:
		if anim_sprite.sprite_frames.has_animation("hurt"):
			print("   🎬 Playing death (hurt) animation...")
			anim_sprite.stop()  # Stop any current animation
			anim_sprite.play("hurt")
			
			# Wait for the animation to finish OR timeout after 1 second
			var timer = get_tree().create_timer(1.0)
			await anim_sprite.animation_finished
			print("   ✅ Death animation complete")
		else:
			print("   ⚠️ No 'hurt' animation found in sprite_frames")
			print("   Available animations: ", anim_sprite.sprite_frames.get_animation_names())
			await get_tree().create_timer(0.5).timeout
	else:
		# Fallback if animation doesn't exist
		print("   ⚠️ No AnimatedSprite2D or sprite_frames found, waiting 0.5s...")
		await get_tree().create_timer(0.5).timeout
	
	# Deaggro ALL enemies
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in all_enemies:
		if enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			if ai.has_method("reset_to_patrol"):
				ai.reset_to_patrol()
	
	print("🔄 All enemies deaggroed")

	# Reset player position to campfire spawn point
	global_position = Vector2(-2000, 0)
	velocity = Vector2.ZERO
	
	# Restore health (but keep XP, level, stats, weapons)
	current_health = max_health
	health_bar.update_health(current_health, max_health)
	
	# Re-enable player controls
	set_physics_process(true)
	
	# Reset death flag
	is_dead = false
	
	print("✨ Player respawned at origin")
	print("   Stats preserved: Level %d, XP: %d" % [CharacterStats.level, CharacterStats.experience])
	print("===== END PLAYER DEATH =====\n")

func create_character_ui() -> void:
	"""Create and add character UI to scene tree"""
	print("🏗️ Player.create_character_ui() called (deferred)")
	var CharacterUIScript = load("res://scripts/ui/CharacterUI.gd")
	character_ui = CharacterUIScript.new()
	character_ui.name = "CharacterUI"

	# Add to scene tree (now that Player is fully ready, this works properly)
	get_tree().root.add_child(character_ui)

	print("📋 Character UI added to scene tree")
	print("   In tree: ", character_ui.is_inside_tree())
	print("   Parent: ", character_ui.get_parent())

func create_campfire_indicator() -> void:
	"""Create and add campfire direction indicator to scene tree"""
	print("🏗️ Player.create_campfire_indicator() called (deferred)")
	var CampfireIndicatorScript = load("res://scripts/ui/CampfireIndicator.gd")
	campfire_indicator = CampfireIndicatorScript.new()
	campfire_indicator.name = "CampfireIndicator"

	# Add to scene tree
	get_tree().root.add_child(campfire_indicator)

	print("🧭 Campfire indicator added to scene tree")
	print("   In tree: ", campfire_indicator.is_inside_tree())

	# Wait one frame for _ready() to complete
	await get_tree().process_frame
	print("🧭 Campfire indicator initialized")
