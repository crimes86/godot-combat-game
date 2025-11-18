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

# Passive Healing System (Out-of-Combat Regeneration)
@export var out_of_combat_delay: float = 5.0  # Seconds after taking damage before healing starts
@export var passive_heal_rate: float = 0.02   # 2% of max health per second (slower than campfire)
@export var passive_heal_tick_interval: float = 1.0  # Heal every 1 second
var time_since_last_damage: float = 0.0
var is_in_combat: bool = false
var passive_heal_timer: float = 0.0

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
	if health_bar and health_bar.has_method("update_health"):
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
	CharacterStats.armor_equipped.connect(_on_armor_equipped)
	CharacterStats.armor_unequipped.connect(_on_armor_unequipped)

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
	if CharacterStats.armor_equipped.is_connected(_on_armor_equipped):
		CharacterStats.armor_equipped.disconnect(_on_armor_equipped)
	if CharacterStats.armor_unequipped.is_connected(_on_armor_unequipped):
		CharacterStats.armor_unequipped.disconnect(_on_armor_unequipped)

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
	if health_bar and health_bar.has_method("update_health"):
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

func _on_armor_equipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is equipped"""
	print("🛡️ Armor equipped in slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to show the new armor
	print("🔄 Refreshing player sprite with new armor...")
	create_player_sprite()

func _on_armor_unequipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is unequipped"""
	print("👕 Armor unequipped from slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to remove armor
	print("🔄 Refreshing player sprite without armor...")
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

			# ✨ CRIT WINDOW: Check if holding on enemy in crit window (uncapped speed!)
			if is_holding_on_crit_window_enemy(mouse_pos):
				# Handled by crit window logic - no cooldown check needed!
				pass
			elif can_attack:
				# Normal attack - cooldown enforced
				attempt_attack()
	
	# Update debug visualization if enabled
	if debug_mode:
		debug_update_timer += delta
		if debug_update_timer >= 0.1:  # Update 10 times per second
			debug_update_timer = 0.0
			update_debug_visualization()

	# Passive Healing System (Out-of-Combat Regeneration)
	process_passive_healing(delta)

	# Handle player death
	if current_health <= 0 and not is_dead:
		die()

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

func get_direction_string(dir: Vector2) -> String:
	"""Convert direction vector to animation name string (4-way for LPC sprites)"""
	if dir.length() < 0.1:
		return "down"

	var angle = dir.angle()

	# Convert to degrees
	# Right = 0, Down = PI/2, Left = PI, Up = -PI/2
	var deg = rad_to_deg(angle)

	# Normalize to 0-360
	if deg < 0:
		deg += 360

	# LPC sprites only have 4 directions, so map to closest cardinal direction
	# Divide into 4 quadrants, 90 degrees each
	if deg >= 315 or deg < 45:
		return "right"  # East (mostly right)
	elif deg >= 45 and deg < 135:
		return "down"   # South (mostly down)
	elif deg >= 135 and deg < 225:
		return "left"   # West (mostly left)
	else:  # 225 to 315
		return "up"     # North (mostly up)

func convert_to_lpc_direction(dir_string: String) -> String:
	"""Convert old direction names to LPC standard"""
	match dir_string:
		"down": return "south"
		"up": return "north"
		"left": return "west"
		"right": return "east"
		_: return "south"

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
				if health_bar and health_bar.has_method("update_health"):
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

func is_holding_on_crit_window_enemy(mouse_pos: Vector2) -> bool:
	"""Check if holding mouse on enemy in crit window (for hold-to-attack). Returns true if attack was triggered."""

	# Update attack direction based on mouse
	attack_direction = (mouse_pos - global_position).normalized()

	# Use the same cone detection as normal attacks
	var enemies_in_cone = get_enemies_in_cone()

	# Check if any enemy in cone is in crit window
	for enemy in enemies_in_cone:
		if not is_instance_valid(enemy):
			continue

		# Only handle enemies in crit window
		if "in_crit_window" in enemy and enemy.in_crit_window:
			handle_crit_window_attack(enemy, mouse_pos)
			return true  # Triggered attack

	return false  # No crit window enemy in attack cone
	
	
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

					# Play slash animation toward the weakpoint
					var character_sprite = get_node_or_null("CharacterSprite")
					if character_sprite:
						var direction_to_weakpoint = (weakpoint.global_position - global_position).normalized()
						var dir_str = get_direction_string(direction_to_weakpoint)
						var lpc_dir = convert_to_lpc_direction(dir_str)
						character_sprite.play_lpc_animation("slash", lpc_dir)

					# ✨ FIX: Directly call hit() instead of relying on input_event
					if weakpoint.has_method("hit"):
						weakpoint.hit()
						print("💥 Manually triggered weakpoint hit!")
					return true
	
	return false

func handle_crit_window_attack(enemy: Node, click_pos: Vector2) -> void:
	"""Handle attack on enemy body during crit window"""

	# ✨ CRIT WINDOW: Attack speed is UNCAPPED! No cooldown check!
	# Weakpoints handle themselves now via is_clicking_on_weakpoint()

	# Play slash animation toward the enemy
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		var direction_to_enemy = (enemy.global_position - global_position).normalized()
		var dir_str = get_direction_string(direction_to_enemy)
		var lpc_dir = convert_to_lpc_direction(dir_str)
		character_sprite.play_lpc_animation("slash", lpc_dir)

	# Get chain multiplier for damage calculation
	var chain_multiplier = ChainManager.get_damage_multiplier()
	var damage = attack_damage * chain_multiplier

	if "take_damage" in enemy:
		enemy.take_damage(damage, false)

	print("⚔️ Enemy body hit during crit window (%.1f dmg, UNCAPPED SPEED!)" % damage)


func attempt_attack() -> void:
	# 🔧 FIX: Set flag IMMEDIATELY to prevent spam clicks from racing through
	if not can_attack:
		return
	
	can_attack = false  # Set immediately, before any other code!

	# Play attack animation
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		var dir_str = get_direction_string(attack_direction)
		var lpc_dir = convert_to_lpc_direction(dir_str)
		character_sprite.play_lpc_animation("slash", lpc_dir)

	ChainManager.register_attack()
	
	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()
	
	var enemies_in_cone = get_enemies_in_cone()

	# Sound is now handled by weapon-specific sounds in Enemy.gd
	var sound_manager = get_node_or_null("/root/SoundManager")

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

func _on_attack_animation_finished() -> void:
	"""Called when attack animation finishes - return to idle"""
	var character_sprite = get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Only process if we just finished an attack animation
	if not character_sprite.animation or not character_sprite.animation.begins_with("slash_"):
		return

	# Return to idle in current facing direction
	var dir_str = get_direction_string(attack_direction)
	var lpc_dir = convert_to_lpc_direction(dir_str)
	character_sprite.play_lpc_animation("idle", lpc_dir)

func take_damage(amount: float) -> void:
	print("Player taking %.1f damage (current: %.1f)" % [amount, current_health])
	current_health -= amount

	# Ensure health doesn't go below 0
	if current_health < 0:
		current_health = 0

	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# Spawn damage number behind player (opposite of facing direction)
	CombatText.create_damage(amount, global_position, get_tree().root, attack_direction)

	# Reset combat timer (entering combat)
	time_since_last_damage = 0.0
	is_in_combat = true

	print("Player health now: %.1f / %.1f" % [current_health, max_health])

	# Flash player sprite red when hit
	flash_player_sprite()

	if current_health <= 0:
		print("💀 Player death triggered!")
		die()

func heal(amount: float) -> void:
	"""Heal the player by the given amount"""
	# Validate heal amount
	if is_nan(amount) or is_inf(amount) or amount <= 0:
		push_warning("⚠️  Invalid heal amount: %s" % str(amount))
		return

	if current_health >= max_health:
		return  # Already at full health
	
	var actual_heal = min(amount, max_health - current_health)
	current_health += actual_heal
	
	# Update health bar
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# Spawn heal number behind player (opposite of facing direction)
	CombatText.create_heal(actual_heal, global_position, get_tree().root, attack_direction)
	
	print("Player healed %.1f HP (now %.1f / %.1f)" % [actual_heal, current_health, max_health])

func process_passive_healing(delta: float) -> void:
	"""Handle out-of-combat passive health regeneration"""
	# Don't heal if already at full health or dead
	if current_health >= max_health or is_dead:
		return

	# Track time since last damage
	time_since_last_damage += delta

	# Check if player has been out of combat long enough
	if time_since_last_damage >= out_of_combat_delay:
		# Player is out of combat
		if is_in_combat:
			is_in_combat = false
			print("✨ Out of combat - passive healing starting...")

		# Accumulate heal timer
		passive_heal_timer += delta

		# Heal every tick interval
		if passive_heal_timer >= passive_heal_tick_interval:
			passive_heal_timer = 0.0

			# Calculate heal amount (percentage of max health)
			var heal_amount = max_health * passive_heal_rate * passive_heal_tick_interval

			# Apply heal (will cap at max health and show combat text)
			if current_health < max_health:
				var actual_heal = min(heal_amount, max_health - current_health)
				current_health += actual_heal
				if health_bar and health_bar.has_method("update_health"):
					health_bar.update_health(current_health, max_health)

				# Only show combat text for significant heals (5%+ of max HP) to reduce spam
				# This means text appears roughly every 2.5 seconds instead of every 1 second
				if actual_heal >= max_health * 0.05:
					CombatText.create_heal(actual_heal, global_position, get_tree().root, attack_direction)

				# Quiet log for passive healing
				if current_health >= max_health:
					print("💚 Passive healing complete (%.1f / %.1f)" % [current_health, max_health])
	else:
		# Still in combat or recently damaged
		passive_heal_timer = 0.0

func flash_player_sprite() -> void:
	"""Flash all player sprite layers red when taking damage"""
	# Get all sprite layers
	var sprite_layers = [
		get_node_or_null("BodySprite"),
		get_node_or_null("LegsSprite"),
		get_node_or_null("TorsoSprite"),
		get_node_or_null("HatSprite"),
		get_node_or_null("WeaponSprite")
	]

	# Flash all layers red
	for sprite in sprite_layers:
		if sprite:
			sprite.modulate = Color(2.0, 0.5, 0.5, 1.0)  # Red flash

	# Use a short timer to restore color
	await get_tree().create_timer(0.1).timeout

	# Restore all layers to white
	for sprite in sprite_layers:
		if sprite and is_instance_valid(sprite):
			sprite.modulate = Color.WHITE


## Visual System Functions

# WEAPON SYSTEM REMOVED - To be reimplemented from scratch

func create_player_sprite() -> void:
	print("Creating simple LPC sprite system")

	# Remove old sprites if they exist (for weapon equip/unequip)
	var old_character_sprite = get_node_or_null("CharacterSprite")
	if old_character_sprite:
		print("  Removing old CharacterSprite")
		remove_child(old_character_sprite)
		old_character_sprite.queue_free()

	var old_shadow = get_node_or_null("Shadow")
	if old_shadow:
		print("  Removing old Shadow")
		remove_child(old_shadow)
		old_shadow.queue_free()

	# Hide the placeholder Sprite2D from the scene
	var placeholder_sprite = get_node_or_null("Sprite2D")
	if placeholder_sprite:
		placeholder_sprite.visible = false
		print("  Hidden placeholder sprite")

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
	print("  Shadow created")

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

	# Load weapon textures based on equipped weapon
	var weapon_slash_tex = null
	var weapon_walk_tex = null

	if CharacterStats.equipped_weapon:
		var weapon_type = CharacterStats.equipped_weapon.weapon_type
		var weapon_path = "res://assets/weapons/" + weapon_type + "/"

		# Try to load weapon sprites
		if ResourceLoader.exists(weapon_path + "slash.png"):
			weapon_slash_tex = load(weapon_path + "slash.png")
		if ResourceLoader.exists(weapon_path + "walk.png"):
			weapon_walk_tex = load(weapon_path + "walk.png")

		print("🗡️ Loading weapon sprites for: %s (type: %s)" % [CharacterStats.equipped_weapon.weapon_name, weapon_type])
		print("   Slash: %s" % ("✅" if weapon_slash_tex else "❌"))
		print("   Walk: %s" % ("✅" if weapon_walk_tex else "❌"))
	else:
		print("👊 No weapon equipped - player is unarmed")

	# Load armor textures based on equipped armor
	var shirt_walk_tex = null
	var shirt_slash_tex = null
	var pants_walk_tex = null
	var pants_slash_tex = null

	# Check for equipped chest armor (shirt)
	if CharacterStats.equipped_armor.has("chest") and CharacterStats.equipped_armor["chest"] != null:
		var chest_armor = CharacterStats.equipped_armor["chest"]
		var sprite_name = chest_armor.get("sprite_name", "white_shirt")
		var shirt_path = "res://assets/characters/shirt/"

		# Try to load shirt sprites based on sprite_name
		if ResourceLoader.exists(shirt_path + sprite_name + "_walk.png"):
			shirt_walk_tex = load(shirt_path + sprite_name + "_walk.png")
		if ResourceLoader.exists(shirt_path + sprite_name + "_slash.png"):
			shirt_slash_tex = load(shirt_path + sprite_name + "_slash.png")

		print("👕 Loading chest armor: %s (sprite: %s)" % [chest_armor["name"], sprite_name])
		print("   Walk: %s" % ("✅" if shirt_walk_tex else "❌"))
		print("   Slash: %s" % ("✅" if shirt_slash_tex else "❌"))

	# Check for equipped leg armor (pants)
	if CharacterStats.equipped_armor.has("legs") and CharacterStats.equipped_armor["legs"] != null:
		var leg_armor = CharacterStats.equipped_armor["legs"]
		var sprite_name = leg_armor.get("sprite_name", "green_pants")
		var pants_path = "res://assets/characters/pants/"

		# Try to load pants sprites based on sprite_name
		if ResourceLoader.exists(pants_path + sprite_name + "_walk.png"):
			pants_walk_tex = load(pants_path + sprite_name + "_walk.png")
		if ResourceLoader.exists(pants_path + sprite_name + "_slash.png"):
			pants_slash_tex = load(pants_path + sprite_name + "_slash.png")

		print("👖 Loading leg armor: %s (sprite: %s)" % [leg_armor["name"], sprite_name])
		print("   Walk: %s" % ("✅" if pants_walk_tex else "❌"))
		print("   Slash: %s" % ("✅" if pants_slash_tex else "❌"))

	# Setup sprite with all layers
	character_sprite.setup_lpc_sprite(walk_tex, slash_tex, hurt_tex, shirt_walk_tex, shirt_slash_tex, pants_walk_tex, pants_slash_tex, weapon_slash_tex, weapon_walk_tex)

	add_child(character_sprite)

	# Connect animation_finished signal
	if not character_sprite.animation_finished.is_connected(_on_attack_animation_finished):
		character_sprite.animation_finished.connect(_on_attack_animation_finished)

	# Debug: List all sprite children
	print("  🔍 Player children after sprite creation:")
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			print("    - ", child.name, " (", child.get_class(), ") visible=", child.visible, " z_index=", child.z_index)

	print("  Simple LPC character created")

# Old animation functions removed - now using SimpleLPCSprite system

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

	# Draw combat text spawn position boxes (player damage/heal text)
	# Shows where red damage and green heal numbers will appear based on facing direction
	_draw_combat_text_debug_boxes()

	# Draw enemy collision shapes in WORLD SPACE (don't rotate)
	var parent = get_parent()
	if parent:
		var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.has_method("draw_debug_shapes_world"):
				var enemy_debug_node = enemy.draw_debug_shapes_world(parent)
				if enemy_debug_node:
					world_debug_nodes.append(enemy_debug_node)

func _draw_combat_text_debug_boxes() -> void:
	"""Draw persistent boxes showing where player damage/heal text spawns for each direction"""
	# Box size
	var box_size = Vector2(30, 30)

	# Calculate offsets for each direction (matching CombatText.gd logic)
	# Facing RIGHT: (-25, 0)
	var offset_right = Vector2(-25, 0)
	# Facing LEFT: (25, 0)
	var offset_left = Vector2(25, 0)
	# Facing DOWN: (0, -30)
	var offset_down = Vector2(0, -30)
	# Facing UP: (0, 50)
	var offset_up = Vector2(0, 50)

	# Draw boxes for all 4 directions
	# RIGHT - Yellow box
	var box_right = _create_debug_box(offset_right, box_size, Color.YELLOW, "RIGHT")
	debug_shapes.add_child(box_right)

	# LEFT - Cyan box
	var box_left = _create_debug_box(offset_left, box_size, Color.CYAN, "LEFT")
	debug_shapes.add_child(box_left)

	# DOWN - Magenta box
	var box_down = _create_debug_box(offset_down, box_size, Color.MAGENTA, "DOWN")
	debug_shapes.add_child(box_down)

	# UP - Green box
	var box_up = _create_debug_box(offset_up, box_size, Color.GREEN, "UP")
	debug_shapes.add_child(box_up)

func _create_debug_box(offset: Vector2, size: Vector2, color: Color, label_text: String) -> Node2D:
	"""Create a colored box with label at the specified offset"""
	var container = Node2D.new()

	# Draw box outline
	var box = Line2D.new()
	box.width = 2.0
	box.default_color = color

	# Box corners (centered on offset point)
	var half_size = size / 2
	box.add_point(offset + Vector2(-half_size.x, -half_size.y))  # Top-left
	box.add_point(offset + Vector2(half_size.x, -half_size.y))   # Top-right
	box.add_point(offset + Vector2(half_size.x, half_size.y))    # Bottom-right
	box.add_point(offset + Vector2(-half_size.x, half_size.y))   # Bottom-left
	box.add_point(offset + Vector2(-half_size.x, -half_size.y))  # Close the box

	container.add_child(box)

	# Add label
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)
	label.position = offset + Vector2(-15, half_size.y + 2)  # Below box
	container.add_child(label)

	return container

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
	if health_bar and health_bar.has_method("update_health"):
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
