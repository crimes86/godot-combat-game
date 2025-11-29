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
var circle_visualizer: Node2D = null  # Ranged weapon targeting circle (at cursor)
var _last_heal_pulse_time: float = 0.0  # Rate limit heal pulse visuals
var debug_mode: bool = false
var debug_shapes: Node2D = null
var world_debug_nodes: Array = []  # Track world-space debug nodes for cleanup
var debug_update_timer: float = 0.0  # Throttle debug updates
var debug_label: Label = null  # Display debug info (coordinates, etc.)
var cone_update_timer: float = 0.0  # Throttle cone color updates (CRITICAL for performance!)

# Debug flag for weakpoint interaction troubleshooting (set to true to enable detailed logging)
var debug_weakpoint_clicks: bool = false

# Camera zoom
@export var zoom_min: float = 0.75  # Zoom out 1.33x (limited to prevent map reveal)
@export var zoom_max: float = 2.0   # Zoom in 2x (close-up)
@export var zoom_speed: float = 0.1 # How fast zoom transitions
var target_zoom: float = 1.0
var camera: Camera2D = null

# Character UI
var character_ui: CanvasLayer = null

# Campfire Direction Indicator
var campfire_indicator: CanvasLayer = null

# Chat UI
var chat_ui: CanvasLayer = null

# Inventory UI (separate from character sheet)
var inventory_ui: CanvasLayer = null

# Dash/Dodge System
var is_dashing: bool = false
var dash_cooldown: float = 1.5  # Seconds between dashes
var dash_duration: float = 0.2  # How long the dash lasts
var dash_speed_multiplier: float = 3.0  # Speed boost during dash (reduced 25%)
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_invincible: bool = true  # I-frames during dash

# Movement modifiers (for debuffs like lava slow)
var movement_modifiers: Dictionary = {}  # source_name -> multiplier (0.0-1.0)

# Multiplayer helper methods
func get_current_animation() -> String:
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.animation:
		return character_sprite.animation
	return "idle_south"

func play_animation(anim_name: String) -> void:
	"""Play animation by full name (for network sync of remote players).
	Animation format: 'action_direction' e.g. 'walk_south', 'idle_north', 'slash_east'"""
	var character_sprite = get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Parse the animation name to extract action and direction
	# Format: "action_direction" e.g. "walk_south", "idle_north"
	var parts = anim_name.rsplit("_", true, 1)  # Split from right, max 1 split
	if parts.size() == 2:
		var action = parts[0]
		var direction = parts[1]
		if character_sprite.has_method("play_lpc_animation"):
			character_sprite.play_lpc_animation(action, direction)
	elif character_sprite.sprite_frames and character_sprite.sprite_frames.has_animation(anim_name):
		# Fallback: play directly if it's a valid animation name
		character_sprite.play(anim_name)

func get_health() -> int:
	return int(current_health)

func is_invincible() -> bool:
	"""Check if player is currently invincible (for server damage validation)"""
	return is_dashing and dash_invincible

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
	
	# Only set default gender if not already set by apply_appearance_data (for remote players)
	if selected_gender != Gender.FEMALE:
		selected_gender = Gender.MALE

	# Create player sprite immediately
	create_player_sprite()
	print("✨ Player sprite created!")

	# For local player, broadcast appearance to other players after a short delay
	# (to ensure networking is ready)
	if is_multiplayer_authority():
		call_deferred("_broadcast_initial_appearance")
	
	# THEN: Initialize everything else

	# Initialize stats from CharacterStats - ONLY for local player
	# Remote players get their stats from network sync, not from local CharacterStats
	if is_multiplayer_authority():
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

		# Set player name on health bar from NetworkManager
		if health_bar and health_bar.has_method("set_player_name"):
			var network_manager = get_node_or_null("/root/NetworkManager")
			if network_manager:
				health_bar.set_player_name(network_manager.player_name)
				# Use different color for guests vs authenticated players
				if network_manager.is_guest:
					health_bar.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
				else:
					health_bar.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated
	else:
		# Remote player - start with default values, will be updated via network sync
		max_health = 100
		current_health = 100
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)
	
	# Add to player group
	add_to_group(Constants.GROUP_PLAYER)
	
	# Create cone visualizer - ONLY for local player (others shouldn't see our attack range)
	if is_multiplayer_authority():
		create_cone_visualizer()
	# create_range_indicator()  # Commented out - don't show range circle
	
	# Setup screen shake
	screen_shake = ScreenShake.new()
	screen_shake.name = "ScreenShake"
	add_child(screen_shake)
	
	# Setup attack feedback system
	attack_feedback = AttackFeedbackSystem.new()
	add_child(attack_feedback)
	
	# Setup debug shapes container - only for local player
	if is_multiplayer_authority():
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
	
	# Setup camera - only for the local player
	camera = get_node_or_null("Camera2D")
	if camera:
		# Only enable camera for local player
		if is_multiplayer_authority():
			camera.enabled = true
			camera.zoom = Vector2(target_zoom, target_zoom)

			# Enable audio listener for 2D spatial audio
			var listener = AudioListener2D.new()
			listener.name = "AudioListener2D"
			camera.add_child(listener)
			listener.make_current()
			print("📷 Camera zoom system initialized (0.5x - 2.0x)")
			print("🔊 AudioListener2D enabled for spatial audio")

			# Start background music
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager and sound_manager.has_method("play_game_music"):
				sound_manager.play_game_music(-15.0)  # Background level
				print("🎵 Game music started")
		else:
			# Disable camera for remote players
			camera.enabled = false
	else:
		push_error("❌ Camera2D not found on player!")
	
	# Only connect to CharacterStats and create UI for local player
	# Remote players don't need these - they get their visuals synced from the network
	if is_multiplayer_authority():
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

		# Create chat UI
		call_deferred("create_chat_ui")

		# Create inventory UI (separate from character sheet)
		call_deferred("create_inventory_ui")

		# Show spawn hints for new players
		call_deferred("create_spawn_hints")

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

	# Clean up circle visualizer (it's parented to root, not player)
	if circle_visualizer and is_instance_valid(circle_visualizer):
		circle_visualizer.queue_free()
		circle_visualizer = null

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

	# Play level up sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_level_up_sound"):
		sound_manager.play_level_up_sound(-4.0)

func _on_weapon_equipped(weapon) -> void:  # weapon is Weapon type
	"""Called when weapon is equipped"""
	print("⚔️ Weapon equipped: ", weapon.weapon_name)
	update_stats_from_character()

	# Reset attack state - ensures player can attack after switching weapons
	# This prevents being stuck in can_attack=false if switched during cooldown
	can_attack = true

	# Refresh player sprite to show the new weapon
	print("🔄 Refreshing player sprite with new weapon...")
	create_player_sprite()

	# Switch visualizer based on weapon type (cone for melee, circle for ranged)
	switch_visualizer_mode()

	# Sync to network
	_sync_appearance_to_network()

func _on_weapon_unequipped() -> void:
	"""Called when weapon is unequipped"""
	print("👊 Weapon unequipped - back to unarmed")
	update_stats_from_character()

	# Reset attack state - ensures player can attack after switching weapons
	# This prevents being stuck in can_attack=false if unequipped during cooldown
	can_attack = true

	# Refresh player sprite to remove weapon
	print("🔄 Refreshing player sprite to unarmed...")
	create_player_sprite()

	# Switch back to melee visualizer (cone)
	switch_visualizer_mode()

	# Sync to network
	_sync_appearance_to_network()

func _on_armor_equipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is equipped"""
	print("🛡️ Armor equipped in slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to show the new armor
	print("🔄 Refreshing player sprite with new armor...")
	create_player_sprite()

	# Sync to network
	_sync_appearance_to_network()

func _on_armor_unequipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is unequipped"""
	print("👕 Armor unequipped from slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to remove armor
	print("🔄 Refreshing player sprite without armor...")
	create_player_sprite()

	# Sync to network
	_sync_appearance_to_network()

func _physics_process(delta: float) -> void:
	# Only process for local player
	if not is_multiplayer_authority():
		return

	# Update dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# Get input direction (used for movement and animation)
	# Block movement input when chat is focused
	var input_direction := Vector2.ZERO
	if not (chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused()):
		input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# Calculate effective speed with modifiers
	var effective_speed = speed * get_movement_modifier()

	# Handle dash movement
	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * speed * dash_speed_multiplier  # Dash ignores slow effects

		# Update dash visual effects
		update_dash_visuals(delta)

		if dash_timer <= 0:
			end_dash()
	else:
		velocity = input_direction * effective_speed

	move_and_slide()

	# Clamp player position to world boundaries (with 50px buffer)
	var x_min = -Constants.CHUNK_SIZE + 50
	var x_max = Constants.CHUNK_SIZE * 2 - 50
	var y_min = -Constants.CHUNK_SIZE / 2 + 50 
	var y_max = Constants.CHUNK_SIZE / 2 - 50
	global_position.x = clamp(global_position.x, x_min, x_max)
	global_position.y = clamp(global_position.y, y_min, y_max)

	update_facing_direction()
	
	# Update LPC animation
	update_lpc_animation(input_direction)
	
	# Update visualizers based on weapon type
	update_cone_visualizer()
	update_circle_visualizer()
	
	# Update attack direction for combat
	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()
	
	# Handle held attack (continuous attacking/healing while mouse held)
	if is_mouse_held:
		# ❌ BLOCK HOLD ATTACKS when UI is open
		if is_ui_blocking_input():
			is_mouse_held = false  # Cancel hold state when UI opens
			hold_attack_timer = 0.0
		else:
			hold_attack_timer += delta
			if hold_attack_timer >= hold_attack_interval:
				hold_attack_timer = 0.0

				# Check if using healing weapon
				if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
					# Healing staff - continuous healing
					if can_attack:
						attempt_heal()
				else:
					# Melee weapon - normal attack logic
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

	# Periodic node count check for debugging memory leaks
	_debug_node_check_timer += delta
	if _debug_node_check_timer >= 5.0:  # Every 5 seconds
		_debug_node_check_timer = 0.0
		var root_children = get_tree().root.get_child_count()
		var heal_pulses = get_tree().get_nodes_in_group("heal_pulse").size() if get_tree().has_group("heal_pulse") else 0
		# Count HealPulse nodes directly
		var pulse_count = 0
		for child in get_tree().root.get_children():
			if child.name.begins_with("HealPulse"):
				pulse_count += 1
		if pulse_count > 0 or _heal_pulse_count > 0:
			print("🔍 DEBUG: Root children=%d, HealPulse nodes=%d, _heal_pulse_count=%d" % [root_children, pulse_count, _heal_pulse_count])

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

	# Don't interrupt harvest animations
	if character_sprite.has_method("is_harvest_active") and character_sprite.is_harvest_active():
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
	# Only process input for the local player
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# ❌ BLOCK ATTACKS when clicking inside UI windows
				if is_ui_blocking_input():
					return

				is_mouse_held = true
				hold_attack_timer = 0.0

				# Check if using a healing weapon
				if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
					# Healing staff - attempt heal instead of attack
					attempt_heal()
				else:
					# Melee/damage weapon - normal attack flow
					# ✨ FIX #1: Check if clicking on weakpoint FIRST
					if is_clicking_on_weakpoint(event):
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
		# Block most game keys while typing in chat (allow F-keys for debug)
		var is_f_key = event.keycode >= KEY_F1 and event.keycode <= KEY_F12
		if not is_f_key and chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused():
			return

		match event.keycode:
			KEY_F6:
				# Debug: Heal to full health
				current_health = max_health
				if health_bar and health_bar.has_method("update_health"):
					health_bar.update_health(current_health, max_health)
				print("💚 DEBUG: Healed to full health (%d/%d)" % [current_health, max_health])
			KEY_G:
				# Switch gender - only for local player
				if not is_multiplayer_authority():
					return

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

				# Sync gender change to other players
				_sync_appearance_to_network()
			
			KEY_F3:
				debug_mode = !debug_mode
				print("Debug mode: ", "ON" if debug_mode else "OFF")
				debug_update_timer = 0.0  # Reset timer
				update_debug_visualization()  # Immediate update
			
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
			KEY_F9:
				# DEBUG: Toggle full map view (zoom out to see entire world)
				toggle_debug_map_view()
			KEY_F10:
				# DEBUG: Add campfire fuel to inventory (Press F10)
				var debug_fuel = load("res://scripts/debug/debug_fuel_items.gd")
				if debug_fuel:
					var instance = debug_fuel.new()
					add_child(instance)
					await instance.add_fuel_to_inventory()
					# Clean up after async function completes
					instance.queue_free()

			KEY_F12:
				# DEBUG: Toggle between melee weapon and healing staff
				_debug_toggle_healing_staff()

			KEY_C:
				# Toggle character sheet
				if character_ui:
					character_ui.toggle_character_ui()

			KEY_I, KEY_B:
				# Toggle inventory (I or B)
				if inventory_ui:
					inventory_ui.toggle_ui()

			KEY_SPACE:
				# Dash/dodge
				if not is_dashing and dash_cooldown_timer <= 0:
					start_dash()

			KEY_ESCAPE:
				# Toggle help/hints menu - only if no other UI is open
				var any_ui_open = false

				# Check if character sheet is open
				if character_ui and character_ui.visible:
					any_ui_open = true

				# Check if inventory is open
				if inventory_ui and inventory_ui.visible:
					any_ui_open = true

				# Check if shop is open (look for ShopUI in scene)
				var shop_ui = get_tree().get_first_node_in_group("shop_ui")
				if shop_ui and shop_ui.visible:
					any_ui_open = true

				# Check if any loot UI is open
				var loot_uis = get_tree().get_nodes_in_group("loot_ui")
				for loot_ui in loot_uis:
					if is_instance_valid(loot_ui) and loot_ui.visible:
						any_ui_open = true
						break

				# Only toggle hints if no other UI is open
				if not any_ui_open:
					toggle_spawn_hints()

var _debug_melee_backup: Weapon = null  # Store melee weapon when switching to healing staff

func _debug_toggle_healing_staff() -> void:
	"""DEBUG: Toggle between current weapon and healing staff for testing."""
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
		# Switch back to melee
		if _debug_melee_backup:
			CharacterStats.equipped_weapon = _debug_melee_backup
			print("🗡️ DEBUG: Switched back to melee weapon: %s" % _debug_melee_backup.weapon_name)
		else:
			CharacterStats.equipped_weapon = Weapon.create_starter_weapon()
			print("🗡️ DEBUG: Switched to default melee weapon")
		_debug_melee_backup = null
	else:
		# Switch to healing staff
		_debug_melee_backup = CharacterStats.equipped_weapon
		CharacterStats.equipped_weapon = Weapon.create_healing_staff(CharacterStats.level)
		print("💚 DEBUG: Equipped Healing Staff (radius: %.0f, healing: %.1f)" % [
			CharacterStats.equipped_weapon.heal_radius,
			CharacterStats.equipped_weapon.get_total_healing()
		])

	# Update visualizers
	switch_visualizer_mode()

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
	
	
func is_clicking_on_weakpoint(_event: InputEvent) -> bool:
	"""Check if clicking on weakpoint and trigger it directly"""
	var click_pos = get_global_mouse_position()
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	if debug_weakpoint_clicks:
		print("[WP_DEBUG] Checking %d enemies for weakpoint click at %s" % [all_enemies.size(), click_pos])

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		# Only check enemies in crit window
		var has_crit_prop = "in_crit_window" in enemy
		var crit_val = enemy.in_crit_window if has_crit_prop else false

		if debug_weakpoint_clicks:
			print("[WP_DEBUG] Enemy %s: has_crit=%s, in_crit=%s" % [enemy.name, has_crit_prop, crit_val])

		if not crit_val:
			continue

		# Check if any weakpoint is at the click position
		if "weakpoints" in enemy:
			if debug_weakpoint_clicks:
				print("[WP_DEBUG] Enemy %s has %d weakpoints" % [enemy.name, enemy.weakpoints.size()])

			for weakpoint in enemy.weakpoints:
				if not is_instance_valid(weakpoint):
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] Weakpoint invalid, skipping")
					continue
				if "is_destroyed" in weakpoint and weakpoint.is_destroyed:
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] Weakpoint destroyed, skipping")
					continue

				var distance = click_pos.distance_to(weakpoint.global_position)
				var weakpoint_radius = 28 * weakpoint.scale.x

				if debug_weakpoint_clicks:
					print("[WP_DEBUG] Weakpoint at %s, dist=%.1f, radius=%.1f" % [weakpoint.global_position, distance, weakpoint_radius])

				if distance < weakpoint_radius:
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] HIT! Calling weakpoint.hit()")

					# Play slash animation toward the weakpoint
					var character_sprite = get_node_or_null("CharacterSprite")
					if character_sprite:
						var direction_to_weakpoint = (weakpoint.global_position - global_position).normalized()
						var dir_str = get_direction_string(direction_to_weakpoint)
						var lpc_dir = convert_to_lpc_direction(dir_str)
						character_sprite.play_lpc_animation("slash", lpc_dir)

					# CLIENT-PREDICTED: Call hit() directly for instant feedback
					# Server validates total damage at crit window end
					if weakpoint.has_method("hit"):
						weakpoint.hit()
					return true

	return false

# NOTE: _report_weakpoint_hit_to_server() was removed - client-predicted system now tracks
# damage locally and reports total at crit window end via CritWindowManager

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

	# Play weapon swing sound (whoosh)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Play weapon-specific swing sound
		if CharacterStats.equipped_weapon:
			# Use sword swing sound for all weapon types (universal whoosh)
			sound_manager.play_sword_swing_sound(global_position, -10.0)
		else:
			# No weapon equipped - use unarmed sound
			sound_manager.play_unarmed_swing_sound(global_position, -10.0)

	# Get chain multiplier for damage calculation
	var chain_multiplier = ChainManager.get_damage_multiplier()
	var damage = attack_damage * chain_multiplier

	if "take_damage" in enemy:
		apply_damage_with_feedback(enemy, damage, false, false)

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

	# Play weapon swing sound (whoosh)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Play weapon-specific swing sound
		if CharacterStats.equipped_weapon:
			# Use sword swing sound for all weapon types (universal whoosh)
			sound_manager.play_sword_swing_sound(global_position, -10.0)
		else:
			# No weapon equipped - use unarmed sound
			sound_manager.play_unarmed_swing_sound(global_position, -10.0)

	ChainManager.register_attack()
	
	var mouse_pos = get_global_mouse_position()
	attack_direction = (mouse_pos - global_position).normalized()
	
	var enemies_in_cone = get_enemies_in_cone()

	# Sound is now handled by weapon-specific sounds in Enemy.gd
	# (sound_manager already retrieved above for swing sound)

	if enemies_in_cone.size() > 0:
		attack_enemies_in_cone(enemies_in_cone)
		finish_attack_cooldown()
	else:
		# Swing sound already played above - no additional miss sound needed
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

# ============================================
# HEALING STAFF - RANGED HEALING SYSTEM
# ============================================

func get_allies_in_radius(center_pos: Vector2, radius: float) -> Array:
	"""Get all friendly players within a circular radius around a point.
	Used for healing staff targeting. Includes self for self-healing."""
	var allies_in_radius = []
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	for player_node in all_players:
		if not is_instance_valid(player_node):
			continue

		# Check if player is within radius
		var distance = center_pos.distance_to(player_node.global_position)
		if distance <= radius:
			# Check if friendly (includes self for self-healing)
			if player_node == self or _is_friendly_player(player_node):
				allies_in_radius.append(player_node)

	return allies_in_radius

func _is_friendly_player(player_node: Node) -> bool:
	"""Check if a player is friendly for healing purposes.
	Currently allows healing ALL players globally (PvP healing allowed).
	PvP damage will be restricted separately when implemented."""
	# For now, all players are friendly for healing purposes
	# This allows healers to help anyone, which encourages cooperative play
	# When PvP is implemented, this can check faction/group membership
	return true

func attempt_heal() -> void:
	"""Attempt to heal allies at cursor position with healing staff."""
	if not can_attack:
		return

	# Verify we have a healing weapon equipped
	if not CharacterStats.equipped_weapon or not CharacterStats.equipped_weapon.is_healing_weapon():
		return

	can_attack = false

	var weapon = CharacterStats.equipped_weapon
	var mouse_pos = get_global_mouse_position()
	var heal_radius = weapon.heal_radius

	# Get allies in the healing circle
	var allies = get_allies_in_radius(mouse_pos, heal_radius)

	# Calculate healing amount
	var base_heal = weapon.get_total_healing()
	# Add stat scaling (could use a new stat, for now use a fraction of strength)
	var stat_bonus = (CharacterStats.strength - 10) * 0.3
	var heal_amount = base_heal + stat_bonus

	# Play cast animation (use slash for now - could add dedicated cast animation later)
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		var dir_str = get_direction_string(attack_direction)
		var lpc_dir = convert_to_lpc_direction(dir_str)
		character_sprite.play_lpc_animation("slash", lpc_dir)

	# Show initial heal circle indicator and spawn first pulse
	_spawn_heal_pulse(mouse_pos, heal_radius)

	# Fire healing projectile from staff to target - triggers second pulse on arrival
	_spawn_heal_projectile(mouse_pos, heal_radius, heal_amount)

	# Play healing cast sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_healing_cast_sound"):
		sound_manager.play_healing_cast_sound(global_position, -5.0)

	if allies.size() > 0:
		heal_allies(allies, heal_amount)

	finish_attack_cooldown()

func heal_allies(allies: Array, heal_amount: float) -> void:
	"""Apply healing to all allies in the array. Healer sees all heal numbers."""
	for ally in allies:
		if not is_instance_valid(ally):
			continue

		# In multiplayer, send heal request to server
		var has_peer = multiplayer.has_multiplayer_peer()
		var is_server = multiplayer.is_server()

		if has_peer and not is_server:
			# Client: request heal through server
			var ally_peer_id = ally.get_multiplayer_authority()
			var network_manager = get_node_or_null("/root/NetworkManager")
			if network_manager and network_manager.has_method("request_player_heal"):
				network_manager.request_player_heal.rpc_id(1, ally_peer_id, heal_amount)
		else:
			# Server or single player: apply heal directly
			if ally.has_method("heal"):
				ally.heal(heal_amount)

		# Healer always sees heal text for allies they healed
		CombatText.create_heal(heal_amount, ally.global_position, get_tree().root, Vector2.ZERO)

func _spawn_heal_pulse(center_pos: Vector2, radius: float, skip_rate_limit: bool = false) -> void:
	"""Spawn a green pulse effect at the healing location. Broadcast to all players."""
	# Rate limit pulse visuals to prevent spam (max 4 per second for double-pulse effect)
	var current_time = Time.get_ticks_msec() / 1000.0
	if not skip_rate_limit and current_time - _last_heal_pulse_time < 0.25:
		return  # Skip visual if too soon
	_last_heal_pulse_time = current_time

	# Always spawn locally for the healer
	_create_heal_pulse_visual(center_pos, radius)

	# In multiplayer, broadcast to other players
	var has_peer = multiplayer.has_multiplayer_peer()
	if has_peer:
		if multiplayer.is_server():
			# Server: broadcast to all clients (excluding self since we already spawned)
			rpc("_remote_spawn_heal_pulse", center_pos, radius)
		else:
			# Client: request server to broadcast to everyone else
			rpc_id(1, "_request_heal_pulse", center_pos, radius)

@rpc("any_peer", "reliable")
func _request_heal_pulse(center_pos: Vector2, radius: float) -> void:
	"""Client requests server to broadcast heal pulse to all players."""
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	# Spawn on server
	_create_heal_pulse_visual(center_pos, radius)
	# Broadcast to all clients except the original sender (they already have it)
	for peer_id in multiplayer.get_peers():
		if peer_id != sender_id:
			rpc_id(peer_id, "_remote_spawn_heal_pulse", center_pos, radius)

@rpc("authority", "reliable")
func _remote_spawn_heal_pulse(center_pos: Vector2, radius: float) -> void:
	"""Server broadcasts heal pulse to clients."""
	_create_heal_pulse_visual(center_pos, radius)

var _heal_pulse_count: int = 0  # Debug: track active pulses
var _debug_node_check_timer: float = 0.0  # Periodic node count check

func _create_heal_pulse_visual(center_pos: Vector2, radius: float) -> void:
	"""Create the actual visual pulse effect."""
	# Safety check - don't create if tree is not available
	if not is_inside_tree():
		return

	# Debug: Track pulse count
	_heal_pulse_count += 1
	if _heal_pulse_count > 5:
		push_warning("⚠️ HEAL PULSE COUNT HIGH: %d active pulses!" % _heal_pulse_count)

	var pulse = Node2D.new()
	pulse.name = "HealPulse"
	pulse.global_position = center_pos
	pulse.z_index = -1

	# Create filled circle
	var circle = Polygon2D.new()
	circle.name = "PulseCircle"
	circle.color = Color(0.4, 1.0, 0.5, 0.3)  # Bright green, semi-transparent

	# Build circle polygon
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points

	pulse.add_child(circle)
	get_tree().root.add_child(pulse)

	# Animate the pulse: expand slightly and fade out
	var tween = pulse.create_tween()
	if tween:
		tween.set_parallel(true)

		# Scale up slightly
		tween.tween_property(pulse, "scale", Vector2(1.3, 1.3), 0.4).set_ease(Tween.EASE_OUT)

		# Fade out
		tween.tween_property(circle, "color:a", 0.0, 0.4).set_ease(Tween.EASE_OUT)

		# Clean up after animation - use lambda to decrement counter
		tween.chain().tween_callback(func():
			_heal_pulse_count -= 1
			pulse.queue_free()
		)
	else:
		# Fallback: just free immediately if tween failed
		_heal_pulse_count -= 1
		pulse.queue_free()

func _spawn_heal_projectile(target_pos: Vector2, radius: float, heal_amount: float) -> void:
	"""Spawn a healing projectile that travels from staff to target, then explodes."""
	if not is_inside_tree():
		return

	# Calculate start position (staff tip, offset from player center based on facing direction)
	var staff_offset = attack_direction.normalized() * 20.0  # Staff extends ~20px from center
	var start_pos = global_position + staff_offset + Vector2(0, -16)  # Adjust for sprite height

	# Create the projectile node
	var projectile = Node2D.new()
	projectile.name = "HealProjectile"
	projectile.global_position = start_pos
	projectile.z_index = 10

	# Create glowing orb (main projectile body)
	var orb = Polygon2D.new()
	orb.name = "Orb"
	orb.color = Color(0.5, 1.0, 0.6, 0.9)  # Bright healing green
	var orb_points = PackedVector2Array()
	var orb_radius = 6.0
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		orb_points.append(Vector2(cos(angle), sin(angle)) * orb_radius)
	orb.polygon = orb_points
	projectile.add_child(orb)

	# Create inner glow (brighter core)
	var core = Polygon2D.new()
	core.name = "Core"
	core.color = Color(0.8, 1.0, 0.9, 1.0)  # Bright white-green core
	var core_points = PackedVector2Array()
	var core_radius = 3.0
	for i in range(8):
		var angle = (float(i) / 8.0) * TAU
		core_points.append(Vector2(cos(angle), sin(angle)) * core_radius)
	core.polygon = core_points
	projectile.add_child(core)

	# Create trailing mist particles (simple circles that follow)
	var trail_container = Node2D.new()
	trail_container.name = "Trail"
	projectile.add_child(trail_container)

	get_tree().root.add_child(projectile)

	# Calculate travel time based on distance (speed: ~400 pixels/sec)
	var distance = start_pos.distance_to(target_pos)
	var travel_time = clampf(distance / 400.0, 0.15, 0.6)  # Min 0.15s, max 0.6s

	# Animate projectile flight
	var tween = projectile.create_tween()

	# Move to target with slight arc (ease out for "magic" feel)
	tween.tween_property(projectile, "global_position", target_pos, travel_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Pulse the orb size slightly during flight
	tween.parallel().tween_property(orb, "scale", Vector2(1.2, 1.2), travel_time * 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(orb, "scale", Vector2(1.0, 1.0), travel_time * 0.5).set_ease(Tween.EASE_IN_OUT).set_delay(travel_time * 0.5)

	# On arrival: trigger mist explosion and second heal pulse
	var self_ref = self
	var target = target_pos
	var rad = radius
	var heal = heal_amount
	tween.tween_callback(func():
		if is_instance_valid(self_ref) and self_ref.is_inside_tree():
			self_ref._spawn_mist_explosion(target, rad)
			# Second heal pulse with slight delay for visual impact
			self_ref._spawn_heal_pulse(target, rad)
			# Apply second round of healing to allies in radius
			var allies = self_ref.get_allies_in_radius(target, rad)
			if allies.size() > 0:
				self_ref.heal_allies(allies, heal * 0.5)  # Second pulse heals 50% of original
			# Play healing impact sound (second pulse explosion)
			var sound_manager = self_ref.get_node_or_null("/root/SoundManager")
			if sound_manager and sound_manager.has_method("play_healing_impact_sound"):
				sound_manager.play_healing_impact_sound(target, -3.0)
		projectile.queue_free()
	)

func _spawn_mist_explosion(center_pos: Vector2, radius: float) -> void:
	"""Create a refined healing burst effect at the target location."""
	if not is_inside_tree():
		return

	var effect = Node2D.new()
	effect.name = "HealBurst"
	effect.global_position = center_pos
	effect.z_index = 5

	# Central flash - bright burst at impact point
	var flash = Polygon2D.new()
	flash.name = "Flash"
	var flash_points = PackedVector2Array()
	var flash_radius = 12.0
	for i in range(16):
		var angle = (float(i) / 16.0) * TAU
		flash_points.append(Vector2(cos(angle), sin(angle)) * flash_radius)
	flash.polygon = flash_points
	flash.color = Color(0.7, 1.0, 0.8, 0.8)  # Bright white-green
	flash.scale = Vector2(0.3, 0.3)
	effect.add_child(flash)

	# Soft ring that expands outward
	var ring = Polygon2D.new()
	ring.name = "Ring"
	var ring_points_outer = PackedVector2Array()
	var ring_points_inner = PackedVector2Array()
	var ring_segments = 32
	var ring_thickness = 4.0
	var ring_radius = 8.0
	# Build ring as a series of quads
	for i in range(ring_segments + 1):
		var angle = (float(i) / float(ring_segments)) * TAU
		ring_points_outer.append(Vector2(cos(angle), sin(angle)) * ring_radius)
		ring_points_inner.append(Vector2(cos(angle), sin(angle)) * (ring_radius - ring_thickness))
	# Combine for polygon (outer ring then inner ring reversed)
	var ring_poly = PackedVector2Array()
	for p in ring_points_outer:
		ring_poly.append(p)
	for i in range(ring_points_inner.size() - 1, -1, -1):
		ring_poly.append(ring_points_inner[i])
	ring.polygon = ring_poly
	ring.color = Color(0.5, 1.0, 0.6, 0.6)
	effect.add_child(ring)

	# Small sparkle particles - clean circular dots
	var sparkle_count = 8
	var sparkles: Array[Polygon2D] = []
	for i in range(sparkle_count):
		var sparkle = Polygon2D.new()
		var angle = (float(i) / float(sparkle_count)) * TAU

		# Clean circular shape
		var sparkle_points = PackedVector2Array()
		var sparkle_size = 3.0
		for j in range(8):
			var s_angle = (float(j) / 8.0) * TAU
			sparkle_points.append(Vector2(cos(s_angle), sin(s_angle)) * sparkle_size)
		sparkle.polygon = sparkle_points
		sparkle.color = Color(0.6, 1.0, 0.7, 0.7)
		sparkle.position = Vector2.ZERO
		sparkle.set_meta("angle", angle)
		sparkle.set_meta("target_dist", radius * 0.5)
		effect.add_child(sparkle)
		sparkles.append(sparkle)

	get_tree().root.add_child(effect)

	# Animate everything
	var tween = effect.create_tween()
	tween.set_parallel(true)

	# Flash: quick scale up then fade
	tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "color:a", 0.0, 0.2).set_ease(Tween.EASE_IN)

	# Ring: expand outward and fade
	tween.tween_property(ring, "scale", Vector2(radius / 8.0, radius / 8.0), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CIRC)
	tween.tween_property(ring, "color:a", 0.0, 0.35).set_ease(Tween.EASE_IN)

	# Sparkles: radiate outward and fade
	for sparkle in sparkles:
		var s_angle = sparkle.get_meta("angle")
		var s_dist = sparkle.get_meta("target_dist")
		var target_pos = Vector2(cos(s_angle), sin(s_angle)) * s_dist
		tween.tween_property(sparkle, "position", target_pos, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(sparkle, "color:a", 0.0, 0.35).set_ease(Tween.EASE_IN).set_delay(0.1)
		tween.tween_property(sparkle, "scale", Vector2(0.3, 0.3), 0.35).set_ease(Tween.EASE_IN)

	# Clean up
	tween.chain().tween_callback(func():
		effect.queue_free()
	)

func attack_enemies_in_cone(enemies: Array) -> void:
	var chain_multiplier = ChainManager.get_damage_multiplier()
	var has_peer = multiplayer.has_multiplayer_peer()
	var is_server = multiplayer.is_server()

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
			# In multiplayer, only SERVER rolls for crits - clients send attack requests
			# Server will broadcast crit windows to clients via RPC
			if has_peer and not is_server:
				# Client: send attack request to server (server handles crit rolls)
				var enemy_net_id = enemy.get("network_id") if enemy.get("network_id") != null else -1
				if enemy_net_id >= 0:
					var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
					if network_enemy_mgr:
						print("🌐 Client: Sending attack request to server (enemy_id=%d, damage=%.1f)" % [enemy_net_id, damage])
						network_enemy_mgr.request_attack.rpc_id(1, enemy_net_id, damage)
				else:
					print("⚠️ Client: Enemy has no network_id, cannot attack")
			else:
				# Server or single player: roll for crit locally
				var is_crit = crit_system.roll_for_crit()

				if is_crit:
					# Play crit window opening sound on successful crit roll
					var sound_manager = get_node_or_null("/root/SoundManager")
					if sound_manager:
						sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -8.0)

					# Start crit window (server broadcasts to clients via Enemy.spawn_weakpoints)
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
	# NOTE: In multiplayer, attack feedback is handled by NetworkEnemyManager._trigger_attack_feedback_for_attacker
	# to ensure only the attacker sees particles (not all players)
	if multiplayer.has_multiplayer_peer():
		return  # Multiplayer handles this centrally

	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, false)

func apply_damage_with_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
	# In multiplayer, send damage request to server
	var has_peer = multiplayer.has_multiplayer_peer()
	var enemy_net_id = enemy.get("network_id") if enemy.get("network_id") != null else -1

	if has_peer and enemy_net_id >= 0:
		var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
		if network_enemy_mgr:
			if multiplayer.is_server():
				# Server processes damage directly (no RPC to self)
				network_enemy_mgr.request_damage(enemy_net_id, damage, is_crit, hit_weakpoint)
			else:
				# Client sends RPC to server
				network_enemy_mgr.request_damage.rpc_id(1, enemy_net_id, damage, is_crit, hit_weakpoint)
			# Visual feedback will be triggered by server broadcast
			return
	# Single player: apply damage directly
	enemy.take_damage(damage, is_crit, hit_weakpoint)

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

func _on_sprite_frame_changed() -> void:
	"""Called when sprite animation frame changes - play footsteps on walk frames"""
	# Only process for local player
	if not is_multiplayer_authority():
		return

	var character_sprite = get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Only play footsteps during walk animations
	if not character_sprite.animation or not character_sprite.animation.begins_with("walk_"):
		return

	var frame = character_sprite.frame
	# Play footstep on foot-down frames (frames 1, 3, 5, 7 of 8-frame walk cycle)
	if frame in [1, 3, 5, 7]:
		# Play footstep sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_player_footstep(global_position)

		# Spawn dust puff at feet - adjust position based on facing direction
		var dust_offset = Vector2(0, 25)  # Default: at feet (5px lower than original)

		# Adjust offset based on animation direction
		# Check current velocity to detect diagonal movement
		var is_moving_diagonally = abs(velocity.x) > 10 and abs(velocity.y) > 10

		if character_sprite.animation.ends_with("_north"):
			if is_moving_diagonally:
				dust_offset = Vector2(0, -10)  # Diagonal northwest/northeast: 15px higher
			else:
				dust_offset = Vector2(0, 5)  # Straight north
		elif character_sprite.animation.ends_with("_south"):
			dust_offset = Vector2(0, 35)  # In front of player when facing down
		elif character_sprite.animation.ends_with("_east"):
			if is_moving_diagonally:
				dust_offset = Vector2(25, 10)  # Diagonal northeast/southeast: 15px higher
			else:
				dust_offset = Vector2(25, 25)  # Straight east
		elif character_sprite.animation.ends_with("_west"):
			if is_moving_diagonally:
				dust_offset = Vector2(-25, 10)  # Diagonal northwest/southwest: 15px higher
			else:
				dust_offset = Vector2(-25, 25)  # Straight west

		var dust = preload("res://scripts/effects/FootstepDust.gd").new()
		dust.global_position = global_position + dust_offset
		get_tree().root.add_child(dust)
		dust.spawn_dust()

func _on_attack_animation_finished() -> void:
	"""Called when attack animation finishes - return to idle"""
	# Only process for local player
	if not is_multiplayer_authority():
		return

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
	# I-frames during dash
	if is_dashing and dash_invincible:
		print("💨 Damage dodged! (dashing)")
		return

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

	# Play player hurt sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_player_hurt_sound(global_position, -3.0)

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
	print("═══════════════════════════════════════════════════════════")
	print("🎭 CREATE_PLAYER_SPRITE called on: %s (authority=%d, is_local=%s)" % [name, get_multiplayer_authority(), is_multiplayer_authority()])
	print("═══════════════════════════════════════════════════════════")

	# DEBUG: List ALL children before cleanup
	print("  📋 Children BEFORE cleanup:")
	for child in get_children():
		var type_name = child.get_class()
		var visible_str = " (visible)" if child.get("visible") == true else " (hidden)" if child.get("visible") == false else ""
		print("    - %s [%s]%s" % [child.name, type_name, visible_str])

	# Remove old sprites if they exist (for weapon equip/unequip)
	var old_character_sprite = get_node_or_null("CharacterSprite")
	if old_character_sprite:
		print("  🗑️ Removing old CharacterSprite (had %d children)" % old_character_sprite.get_child_count())
		remove_child(old_character_sprite)
		old_character_sprite.queue_free()

	var old_shadow = get_node_or_null("Shadow")
	if old_shadow:
		print("  🗑️ Removing old Shadow")
		remove_child(old_shadow)
		old_shadow.queue_free()

	# Hide AND remove the placeholder Sprite2D from the scene
	var placeholder_sprite = get_node_or_null("Sprite2D")
	if placeholder_sprite:
		print("  🗑️ Removing placeholder Sprite2D")
		placeholder_sprite.visible = false
		remove_child(placeholder_sprite)
		placeholder_sprite.queue_free()

	# DEBUG: List ALL children after cleanup
	print("  📋 Children AFTER cleanup:")
	for child in get_children():
		var type_name = child.get_class()
		print("    - %s [%s]" % [child.name, type_name])

	# Preload SimpleLPCSprite
	var SimpleLPCSprite = preload("res://scripts/SimpleLPCSprite.gd")

	# Create character sprite
	var character_sprite = SimpleLPCSprite.new()
	character_sprite.name = "CharacterSprite"
	character_sprite.position = Vector2(0, -8)
	character_sprite.centered = true

	# For local player, use CharacterStats. For remote players, use stored remote data.
	var is_local = is_multiplayer_authority()

	# Load textures
	var body_type = "body_male" if selected_gender == Gender.MALE else "body_female"
	var walk_tex = load("res://assets/characters/" + body_type + "/standard/walk.png")
	var hurt_tex = load("res://assets/characters/" + body_type + "/standard/hurt.png")

	# Determine attack animation type based on weapon
	# Staff uses thrust animation, all other weapons use slash
	var uses_thrust = false
	if is_local and CharacterStats.equipped_weapon:
		uses_thrust = CharacterStats.equipped_weapon.weapon_type == "staff"
	elif not is_local and remote_weapon_type == "staff":
		uses_thrust = true

	var attack_anim_name = "thrust" if uses_thrust else "slash"
	var attack_tex_path = "res://assets/characters/" + body_type + "/standard/" + attack_anim_name + ".png"
	var slash_tex = load(attack_tex_path) if ResourceLoader.exists(attack_tex_path) else load("res://assets/characters/" + body_type + "/standard/slash.png")

	# Load shadow textures
	var shadow_walk_tex = null
	var shadow_slash_tex = null
	var shadow_path = "res://assets/characters/shadow/standard/"
	if ResourceLoader.exists(shadow_path + "walk.png"):
		shadow_walk_tex = load(shadow_path + "walk.png")
	var shadow_attack_path = shadow_path + attack_anim_name + ".png"
	if ResourceLoader.exists(shadow_attack_path):
		shadow_slash_tex = load(shadow_attack_path)
	elif ResourceLoader.exists(shadow_path + "slash.png"):
		shadow_slash_tex = load(shadow_path + "slash.png")

	# Load base head textures (separate head layer for both genders)
	var base_head_walk_tex = null
	var base_head_slash_tex = null
	var head_path = "res://assets/characters/head_female/standard/" if selected_gender == Gender.FEMALE else "res://assets/characters/head_male/standard/"
	if ResourceLoader.exists(head_path + "walk.png"):
		base_head_walk_tex = load(head_path + "walk.png")
	var head_attack_path = head_path + attack_anim_name + ".png"
	if ResourceLoader.exists(head_attack_path):
		base_head_slash_tex = load(head_attack_path)
	elif ResourceLoader.exists(head_path + "slash.png"):
		base_head_slash_tex = load(head_path + "slash.png")

	# Load weapon textures based on equipped weapon
	var weapon_slash_tex = null
	var weapon_walk_tex = null
	var weapon_type = "unarmed"  # Default to unarmed when no weapon equipped
	var effective_weapon_type = ""

	if is_local and CharacterStats.equipped_weapon:
		effective_weapon_type = CharacterStats.equipped_weapon.weapon_type
	elif not is_local and remote_weapon_type != "":
		effective_weapon_type = remote_weapon_type

	if effective_weapon_type != "":
		weapon_type = effective_weapon_type
		var weapon_path = "res://assets/weapons/" + weapon_type + "/"

		# Try to load weapon sprites
		# Staff uses thrust_oversize animation instead of slash
		if weapon_type == "staff":
			if ResourceLoader.exists(weapon_path + "thrust_oversize.png"):
				weapon_slash_tex = load(weapon_path + "thrust_oversize.png")
		else:
			if ResourceLoader.exists(weapon_path + "slash.png"):
				weapon_slash_tex = load(weapon_path + "slash.png")

		if ResourceLoader.exists(weapon_path + "walk.png"):
			weapon_walk_tex = load(weapon_path + "walk.png")

		print("🗡️ Loading weapon sprites for type: %s (local=%s)" % [weapon_type, is_local])
		print("   Attack: %s" % ("✅" if weapon_slash_tex else "❌"))
		print("   Walk: %s" % ("✅" if weapon_walk_tex else "❌"))
	else:
		print("👊 No weapon equipped - player is unarmed")

	# Load armor textures based on equipped armor (5 layers: boots, pants, shirt, arms, head)
	print("═══ ARMOR LOADING ═══")
	# Use thrust or slash suffix based on weapon type
	var attack_suffix = "_thrust" if uses_thrust else "_slash"
	var boots_walk_tex = null
	var boots_slash_tex = null
	var pants_walk_tex = null
	var pants_slash_tex = null
	var shirt_walk_tex = null
	var shirt_slash_tex = null
	var arms_walk_tex = null
	var arms_slash_tex = null
	var hands_walk_tex = null
	var hands_slash_tex = null
	var head_walk_tex = null
	var head_slash_tex = null

	# Check for equipped boots (feet)
	var feet_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("feet") and CharacterStats.equipped_armor["feet"] != null:
		var boots_armor = CharacterStats.equipped_armor["feet"]
		feet_sprite_name = boots_armor.get("sprite_name", "")
	elif not is_local and remote_feet_sprite != "":
		feet_sprite_name = remote_feet_sprite

	if feet_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var boots_path = "res://assets/characters/boots_female/" if selected_gender == Gender.FEMALE else "res://assets/characters/boots/"
		# If gender-specific doesn't exist, try gender-neutral
		if not ResourceLoader.exists(boots_path + feet_sprite_name + "_walk.png"):
			boots_path = "res://assets/characters/boots/"

		if ResourceLoader.exists(boots_path + feet_sprite_name + "_walk.png"):
			boots_walk_tex = load(boots_path + feet_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(boots_path + feet_sprite_name + attack_suffix + ".png"):
			boots_slash_tex = load(boots_path + feet_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(boots_path + feet_sprite_name + "_slash.png"):
			boots_slash_tex = load(boots_path + feet_sprite_name + "_slash.png")

	# Check for equipped leg armor (pants)
	var legs_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("legs") and CharacterStats.equipped_armor["legs"] != null:
		var leg_armor = CharacterStats.equipped_armor["legs"]
		legs_sprite_name = leg_armor.get("sprite_name", "green_pants")
	elif not is_local and remote_legs_sprite != "":
		legs_sprite_name = remote_legs_sprite

	if legs_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var pants_path = "res://assets/characters/pants_female/" if selected_gender == Gender.FEMALE else "res://assets/characters/pants/"
		if not ResourceLoader.exists(pants_path + legs_sprite_name + "_walk.png"):
			pants_path = "res://assets/characters/pants/"

		if ResourceLoader.exists(pants_path + legs_sprite_name + "_walk.png"):
			pants_walk_tex = load(pants_path + legs_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(pants_path + legs_sprite_name + attack_suffix + ".png"):
			pants_slash_tex = load(pants_path + legs_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(pants_path + legs_sprite_name + "_slash.png"):
			pants_slash_tex = load(pants_path + legs_sprite_name + "_slash.png")

	# Check for equipped chest armor (shirt)
	var chest_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("chest") and CharacterStats.equipped_armor["chest"] != null:
		var chest_armor = CharacterStats.equipped_armor["chest"]
		chest_sprite_name = chest_armor.get("sprite_name", "white_shirt")
	elif not is_local and remote_chest_sprite != "":
		chest_sprite_name = remote_chest_sprite

	if chest_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var shirt_path = "res://assets/characters/shirt_female/" if selected_gender == Gender.FEMALE else "res://assets/characters/shirt/"
		if not ResourceLoader.exists(shirt_path + chest_sprite_name + "_walk.png"):
			shirt_path = "res://assets/characters/shirt/"

		# Try to load shirt sprites based on sprite_name
		if ResourceLoader.exists(shirt_path + chest_sprite_name + "_walk.png"):
			shirt_walk_tex = load(shirt_path + chest_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(shirt_path + chest_sprite_name + attack_suffix + ".png"):
			shirt_slash_tex = load(shirt_path + chest_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(shirt_path + chest_sprite_name + "_slash.png"):
			shirt_slash_tex = load(shirt_path + chest_sprite_name + "_slash.png")

	# Check for equipped arm armor
	var arms_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("arms") and CharacterStats.equipped_armor["arms"] != null:
		var arm_armor = CharacterStats.equipped_armor["arms"]
		arms_sprite_name = arm_armor.get("sprite_name", "")
	elif not is_local and remote_arms_sprite != "":
		arms_sprite_name = remote_arms_sprite

	if arms_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var arms_path = "res://assets/characters/arms_female/" if selected_gender == Gender.FEMALE else "res://assets/characters/arms/"
		if not ResourceLoader.exists(arms_path + arms_sprite_name + "_walk.png"):
			arms_path = "res://assets/characters/arms/"

		if ResourceLoader.exists(arms_path + arms_sprite_name + "_walk.png"):
			arms_walk_tex = load(arms_path + arms_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(arms_path + arms_sprite_name + attack_suffix + ".png"):
			arms_slash_tex = load(arms_path + arms_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(arms_path + arms_sprite_name + "_slash.png"):
			arms_slash_tex = load(arms_path + arms_sprite_name + "_slash.png")

	# Check for equipped hand armor (gloves)
	var hands_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("hands") and CharacterStats.equipped_armor["hands"] != null:
		var hand_armor = CharacterStats.equipped_armor["hands"]
		hands_sprite_name = hand_armor.get("sprite_name", "")
	elif not is_local and remote_hands_sprite != "":
		hands_sprite_name = remote_hands_sprite

	if hands_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var hands_path = "res://assets/characters/hands_female/" if selected_gender == Gender.FEMALE else "res://assets/characters/hands/"
		if not ResourceLoader.exists(hands_path + hands_sprite_name + "_walk.png"):
			hands_path = "res://assets/characters/hands/"

		if ResourceLoader.exists(hands_path + hands_sprite_name + "_walk.png"):
			hands_walk_tex = load(hands_path + hands_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(hands_path + hands_sprite_name + attack_suffix + ".png"):
			hands_slash_tex = load(hands_path + hands_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(hands_path + hands_sprite_name + "_slash.png"):
			hands_slash_tex = load(hands_path + hands_sprite_name + "_slash.png")

	# Check for equipped head armor
	var head_sprite_name = ""
	if is_local and CharacterStats.equipped_armor.has("head") and CharacterStats.equipped_armor["head"] != null:
		var head_armor = CharacterStats.equipped_armor["head"]
		head_sprite_name = head_armor.get("sprite_name", "")
	elif not is_local and remote_head_sprite != "":
		head_sprite_name = remote_head_sprite

	if head_sprite_name != "":
		# Try gender-specific path first, then fall back to gender-neutral
		var head_armor_path = "res://assets/characters/head_female_armor/" if selected_gender == Gender.FEMALE else "res://assets/characters/head/"
		if not ResourceLoader.exists(head_armor_path + head_sprite_name + "_walk.png"):
			head_armor_path = "res://assets/characters/head/"

		if ResourceLoader.exists(head_armor_path + head_sprite_name + "_walk.png"):
			head_walk_tex = load(head_armor_path + head_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(head_armor_path + head_sprite_name + attack_suffix + ".png"):
			head_slash_tex = load(head_armor_path + head_sprite_name + attack_suffix + ".png")
		elif ResourceLoader.exists(head_armor_path + head_sprite_name + "_slash.png"):
			head_slash_tex = load(head_armor_path + head_sprite_name + "_slash.png")

	# Load hair textures (for both genders)
	var hair_walk_tex = null
	var hair_slash_tex = null
	var hair_type = "hair_male" if selected_gender == Gender.MALE else "hair_female"
	var hair_path = "res://assets/characters/" + hair_type + "/standard/"
	if ResourceLoader.exists(hair_path + "walk.png"):
		hair_walk_tex = load(hair_path + "walk.png")
	# Try thrust first if using staff, fall back to slash
	var hair_attack_path = hair_path + attack_anim_name + ".png"
	if ResourceLoader.exists(hair_attack_path):
		hair_slash_tex = load(hair_attack_path)
	elif ResourceLoader.exists(hair_path + "slash.png"):
		hair_slash_tex = load(hair_path + "slash.png")

	# Setup sprite with shadow + all armor layers + base_head + hair
	var is_female = (selected_gender == Gender.FEMALE)
	character_sprite.setup_lpc_sprite(walk_tex, slash_tex, hurt_tex, shadow_walk_tex, shadow_slash_tex, base_head_walk_tex, base_head_slash_tex, boots_walk_tex, boots_slash_tex, pants_walk_tex, pants_slash_tex, shirt_walk_tex, shirt_slash_tex, arms_walk_tex, arms_slash_tex, hands_walk_tex, hands_slash_tex, head_walk_tex, head_slash_tex, hair_walk_tex, hair_slash_tex, weapon_slash_tex, weapon_walk_tex, weapon_type, is_female)

	add_child(character_sprite)

	# Connect animation signals
	if not character_sprite.animation_finished.is_connected(_on_attack_animation_finished):
		character_sprite.animation_finished.connect(_on_attack_animation_finished)

	# Connect frame_changed signal for footsteps
	if not character_sprite.frame_changed.is_connected(_on_sprite_frame_changed):
		character_sprite.frame_changed.connect(_on_sprite_frame_changed)

	# DEBUG: List ALL player children after sprite creation
	print("  📋 Player children AFTER sprite creation:")
	for child in get_children():
		var type_name = child.get_class()
		var visible_str = " (visible)" if child.get("visible") == true else " (hidden)" if child.get("visible") == false else ""
		print("    - %s [%s]%s" % [child.name, type_name, visible_str])
		# If it's the CharacterSprite, list its children too
		if child.name == "CharacterSprite":
			print("      └── CharacterSprite has %d children:" % child.get_child_count())
			for subchild in child.get_children():
				var sub_type = subchild.get_class()
				var sub_visible = " (visible)" if subchild.get("visible") == true else " (hidden)" if subchild.get("visible") == false else ""
				print("          - %s [%s]%s" % [subchild.name, sub_type, sub_visible])

	print("═══════════════════════════════════════════════════════════")
	print("✅ CREATE_PLAYER_SPRITE complete for: %s" % name)
	print("═══════════════════════════════════════════════════════════")

# ═══════════════════════════════════════════════════════════════════════════
# MULTIPLAYER APPEARANCE SYNC
# ═══════════════════════════════════════════════════════════════════════════

# Remote player equipment storage (since they don't use CharacterStats singleton)
var remote_weapon_type: String = ""
var remote_feet_sprite: String = ""
var remote_legs_sprite: String = ""
var remote_chest_sprite: String = ""
var remote_arms_sprite: String = ""
var remote_hands_sprite: String = ""
var remote_head_sprite: String = ""

func _sync_appearance_to_network():
	"""Send current appearance to all other players"""
	if not multiplayer.has_multiplayer_peer():
		return

	var appearance = get_appearance_data()
	print("🌐 [APPEARANCE] Syncing to network: %s" % str(appearance))
	rpc("_receive_appearance_update", appearance["gender"], appearance["weapon_type"],
		appearance["feet_sprite"], appearance["legs_sprite"], appearance["chest_sprite"],
		appearance["arms_sprite"], appearance["hands_sprite"], appearance["head_sprite"])

func _broadcast_initial_appearance():
	"""Broadcast appearance after initial spawn (called deferred from _ready)"""
	# Wait a couple frames to ensure multiplayer is fully set up
	await get_tree().process_frame
	await get_tree().process_frame

	if multiplayer.has_multiplayer_peer():
		print("🌐 [APPEARANCE] Broadcasting initial appearance for local player")
		_sync_appearance_to_network()

@rpc("any_peer", "call_remote", "reliable")
func _receive_appearance_update(gender_int: int, weapon_type: String, feet_sprite: String, legs_sprite: String, chest_sprite: String, arms_sprite: String, hands_sprite: String, head_sprite: String):
	"""Receive appearance update from another player"""
	print("🌐 [APPEARANCE] Received for player %s: gender=%d, weapon=%s, feet=%s, legs=%s, chest=%s, arms=%s, hands=%s, head=%s" % [name, gender_int, weapon_type, feet_sprite, legs_sprite, chest_sprite, arms_sprite, hands_sprite, head_sprite])

	# Update appearance data
	selected_gender = Gender.MALE if gender_int == 0 else Gender.FEMALE
	remote_weapon_type = weapon_type
	remote_feet_sprite = feet_sprite
	remote_legs_sprite = legs_sprite
	remote_chest_sprite = chest_sprite
	remote_arms_sprite = arms_sprite
	remote_hands_sprite = hands_sprite
	remote_head_sprite = head_sprite

	# Recreate sprite with new appearance
	set_physics_process(false)
	await create_player_sprite()
	await get_tree().process_frame
	set_physics_process(true)
	print("🌐 [APPEARANCE] Updated remote player %s appearance" % name)

func get_appearance_data() -> Dictionary:
	"""Get current appearance data for network sync"""
	var weapon_type = ""
	var feet_sprite = ""
	var legs_sprite = ""
	var chest_sprite = ""
	var arms_sprite = ""
	var hands_sprite = ""
	var head_sprite = ""

	# Get from CharacterStats if this is the local player
	if is_multiplayer_authority():
		if CharacterStats.equipped_weapon:
			weapon_type = CharacterStats.equipped_weapon.weapon_type
		if CharacterStats.equipped_armor.get("feet"):
			feet_sprite = CharacterStats.equipped_armor["feet"].get("sprite_name", "")
		if CharacterStats.equipped_armor.get("legs"):
			legs_sprite = CharacterStats.equipped_armor["legs"].get("sprite_name", "")
		if CharacterStats.equipped_armor.get("chest"):
			chest_sprite = CharacterStats.equipped_armor["chest"].get("sprite_name", "")
		if CharacterStats.equipped_armor.get("arms"):
			arms_sprite = CharacterStats.equipped_armor["arms"].get("sprite_name", "")
		if CharacterStats.equipped_armor.get("hands"):
			hands_sprite = CharacterStats.equipped_armor["hands"].get("sprite_name", "")
		if CharacterStats.equipped_armor.get("head"):
			head_sprite = CharacterStats.equipped_armor["head"].get("sprite_name", "")
	else:
		# For remote players, use stored values
		weapon_type = remote_weapon_type
		feet_sprite = remote_feet_sprite
		legs_sprite = remote_legs_sprite
		chest_sprite = remote_chest_sprite
		arms_sprite = remote_arms_sprite
		hands_sprite = remote_hands_sprite
		head_sprite = remote_head_sprite

	return {
		"gender": 0 if selected_gender == Gender.MALE else 1,
		"weapon_type": weapon_type,
		"feet_sprite": feet_sprite,
		"legs_sprite": legs_sprite,
		"chest_sprite": chest_sprite,
		"arms_sprite": arms_sprite,
		"hands_sprite": hands_sprite,
		"head_sprite": head_sprite
	}

func apply_appearance_data(data: Dictionary):
	"""Apply appearance data received from network"""
	if data.has("gender"):
		selected_gender = Gender.MALE if data["gender"] == 0 else Gender.FEMALE
	if data.has("weapon_type"):
		remote_weapon_type = data["weapon_type"]
	if data.has("feet_sprite"):
		remote_feet_sprite = data["feet_sprite"]
	if data.has("legs_sprite"):
		remote_legs_sprite = data["legs_sprite"]
	if data.has("chest_sprite"):
		remote_chest_sprite = data["chest_sprite"]
	if data.has("arms_sprite"):
		remote_arms_sprite = data["arms_sprite"]
	if data.has("hands_sprite"):
		remote_hands_sprite = data["hands_sprite"]
	if data.has("head_sprite"):
		remote_head_sprite = data["head_sprite"]
	# Note: Caller should call create_player_sprite() after this

# Old animation functions removed - now using SimpleLPCSprite system

func create_cone_visualizer() -> void:
	"""Create subtle cone outline showing attack area"""
	# Remove old visualizer if it exists
	if cone_visualizer:
		cone_visualizer.queue_free()

	# Use a very subtle filled cone with low opacity
	cone_visualizer = Polygon2D.new()
	cone_visualizer.name = "ConeVisualizer"
	cone_visualizer.color = Color(0.5, 0.5, 0.5, 0.04)  # Extremely faint gray
	cone_visualizer.z_index = -1  # Behind player
	cone_visualizer.visible = true

	# Create cone shape points
	var points = PackedVector2Array()
	var segments = 16  # Fewer segments for subtle look
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

	print("✅ Cone visualizer created (subtle outline, angle: %.0f°, range: %.0f)" % [attack_cone_angle, attack_range])
	
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

	# Hide cone if using ranged weapon
	var is_ranged = CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_ranged_weapon()
	cone_visualizer.visible = not is_ranged

	if is_ranged:
		return  # Don't update rotation if hidden

	# ALWAYS rotate cone to face mouse cursor (cheap, needs to be smooth)
	var mouse_pos = get_global_mouse_position()
	var direction_to_mouse = (mouse_pos - global_position).normalized()
	cone_visualizer.rotation = direction_to_mouse.angle()

	# Color is now constant - no need to update based on enemies

# ============================================
# RANGED WEAPON CIRCLE VISUALIZER
# ============================================

func create_circle_visualizer() -> void:
	"""Create targeting circle for ranged weapons (healing staff, etc.)
	This circle follows the mouse cursor and shows the heal/attack radius."""
	# Clean up existing visualizer if any
	if circle_visualizer and is_instance_valid(circle_visualizer):
		circle_visualizer.queue_free()
	circle_visualizer = null

	# Create a Node2D to hold the circle (will be positioned at cursor)
	circle_visualizer = Node2D.new()
	circle_visualizer.name = "CircleVisualizer"
	circle_visualizer.z_index = -1  # Behind characters

	# Create the filled circle using Polygon2D
	var circle_fill = Polygon2D.new()
	circle_fill.name = "CircleFill"
	circle_fill.color = Color(0.4, 1.0, 0.5, 0.04)  # Faint green (same opacity as melee cone)

	# Get radius from equipped weapon or use default
	var radius = 80.0
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
		radius = CharacterStats.equipped_weapon.heal_radius

	# Create circle points
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	circle_fill.polygon = points
	circle_visualizer.add_child(circle_fill)

	# Add to scene tree root so it stays in world space at cursor position
	get_tree().root.add_child(circle_visualizer)
	circle_visualizer.visible = false  # Hidden until we have a ranged weapon

	# Debug print removed - was spamming logs

func update_circle_visualizer() -> void:
	"""Update circle visualizer position to follow mouse cursor."""
	# Safety check for invalid visualizer
	if not circle_visualizer or not is_instance_valid(circle_visualizer):
		circle_visualizer = null
		return

	# Check if we should show circle (ranged weapon equipped)
	var should_show = false
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_ranged_weapon():
		should_show = true

	circle_visualizer.visible = should_show

	if should_show:
		# Position at mouse cursor
		circle_visualizer.global_position = get_global_mouse_position()

func _rebuild_circle_polygon(circle_fill: Polygon2D, radius: float) -> void:
	"""Rebuild the circle polygon with a new radius."""
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle_fill.polygon = points

func switch_visualizer_mode() -> void:
	"""Switch between cone (melee) and circle (ranged) visualizers based on equipped weapon."""
	var is_ranged = CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_ranged_weapon()

	if cone_visualizer:
		cone_visualizer.visible = not is_ranged

	if is_ranged and not circle_visualizer:
		create_circle_visualizer()

	if circle_visualizer:
		circle_visualizer.visible = is_ranged

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

# Debug map view state
var debug_map_view_active: bool = false
var debug_map_saved_zoom: float = 1.0
var debug_map_saved_position: Vector2 = Vector2.ZERO
var debug_map_saved_limits: Dictionary = {}

func toggle_debug_map_view() -> void:
	"""Toggle between normal view and full map debug view (F9)"""
	if not camera:
		print("❌ No camera found!")
		return

	debug_map_view_active = !debug_map_view_active

	if debug_map_view_active:
		# Save current state
		debug_map_saved_zoom = target_zoom
		debug_map_saved_position = global_position  # Player position (for reference)
		debug_map_saved_limits = {
			"left": camera.limit_left,
			"right": camera.limit_right,
			"top": camera.limit_top,
			"bottom": camera.limit_bottom,
			"offset": camera.offset
		}

		# Calculate zoom to fit entire world
		var viewport_size = get_viewport().get_visible_rect().size
		var world_width = Constants.CHUNK_SIZE * 3  # 3 chunks wide
		var world_height = Constants.CHUNK_SIZE  # 1 chunk tall
		var zoom_x = viewport_size.x / world_width
		var zoom_y = viewport_size.y / world_height
		var map_zoom = min(zoom_x, zoom_y) * 0.9  # 90% to add margin

		# Disable camera limits for map view
		camera.limit_left = int(-Constants.CHUNK_SIZE * 2)
		camera.limit_right = int(Constants.CHUNK_SIZE * 4)
		camera.limit_top = int(-Constants.CHUNK_SIZE)
		camera.limit_bottom = int(Constants.CHUNK_SIZE)

		# Use camera offset to view world center WITHOUT moving player
		# Offset = (world center) - (player position)
		var world_center = Vector2(Constants.CHUNK_SIZE / 2, 0)  # Center of chunk 0
		camera.offset = world_center - global_position
		target_zoom = map_zoom
		camera.zoom = Vector2(map_zoom, map_zoom)

		print("🗺️ DEBUG MAP VIEW ON - Press F9 to return (zoom: %.3f)" % map_zoom)
	else:
		# Restore previous state
		camera.limit_left = debug_map_saved_limits.get("left", Constants.WORLD_LEFT)
		camera.limit_right = debug_map_saved_limits.get("right", Constants.WORLD_RIGHT)
		camera.limit_top = debug_map_saved_limits.get("top", Constants.WORLD_TOP)
		camera.limit_bottom = debug_map_saved_limits.get("bottom", Constants.WORLD_BOTTOM)
		camera.offset = debug_map_saved_limits.get("offset", Vector2.ZERO)

		target_zoom = debug_map_saved_zoom
		camera.zoom = Vector2(target_zoom, target_zoom)

		print("🗺️ DEBUG MAP VIEW OFF - Restored normal view")

func is_ui_blocking_input() -> bool:
	"""Check if mouse click is over a UI element that should block game input"""
	# Check if chat is focused (blocks movement/attack while typing)
	if chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused():
		return true

	# Get mouse position for UI hit testing
	var mouse_pos = get_viewport().get_mouse_position()

	# Check if inventory UI is open AND mouse is over it
	if inventory_ui and inventory_ui.visible:
		if _is_mouse_over_canvas_layer(inventory_ui, mouse_pos):
			return true

	# Check if character UI is open AND mouse is over it
	if character_ui and character_ui.visible:
		if _is_mouse_over_canvas_layer(character_ui, mouse_pos):
			return true

	var root = get_tree().root
	for child in root.get_children():
		if child is CanvasLayer and child.visible:
			# Check for specific UI types that should block input when mouse is over them
			if child is ShopUI:
				if _is_mouse_over_canvas_layer(child, mouse_pos):
					return true
			if child is LootBodyUI:
				if _is_mouse_over_canvas_layer(child, mouse_pos):
					return true
			if child is ChestLootUI:
				if _is_mouse_over_canvas_layer(child, mouse_pos):
					return true
	return false

func _is_mouse_over_canvas_layer(canvas_layer: CanvasLayer, mouse_pos: Vector2) -> bool:
	"""Check if mouse position is within any Control child of a CanvasLayer"""
	if not canvas_layer or not canvas_layer.visible:
		return false

	# Find Control children and check if mouse is over any of them
	for child in canvas_layer.get_children():
		if child is Control and child.visible:
			var rect = child.get_global_rect()
			if rect.has_point(mouse_pos):
				return true
	return false

func is_shop_open() -> bool:
	"""Legacy function - kept for compatibility. Use is_ui_blocking_input() instead"""
	return is_ui_blocking_input()

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

	# Play death sound (gender-specific)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		var is_female = (selected_gender == Gender.FEMALE)
		sound_manager.play_player_death_sound(global_position, is_female, -4.0)

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

	# Reset player position to campfire spawn point (center of chunk 0)
	global_position = Vector2(Constants.CHUNK_SIZE / 2, 0)
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

func create_chat_ui() -> void:
	"""Create and add chat UI to scene tree"""
	print("🏗️ Player.create_chat_ui() called (deferred)")
	var ChatUIScript = load("res://scripts/ui/ChatUI.gd")
	chat_ui = ChatUIScript.new()
	chat_ui.name = "ChatUI"

	# Add to scene tree
	get_tree().root.add_child(chat_ui)

	print("💬 Chat UI added to scene tree")
	print("   In tree: ", chat_ui.is_inside_tree())

func create_inventory_ui() -> void:
	"""Create and add inventory UI to scene tree"""
	print("🏗️ Player.create_inventory_ui() called (deferred)")
	var InventoryUIScript = load("res://scripts/ui/InventoryUI.gd")
	inventory_ui = InventoryUIScript.new()
	inventory_ui.name = "InventoryUI"

	# Add to scene tree
	get_tree().root.add_child(inventory_ui)

	print("📦 Inventory UI added to scene tree")
	print("   In tree: ", inventory_ui.is_inside_tree())

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN HINTS OVERLAY
# ═══════════════════════════════════════════════════════════════════════════

var spawn_hints_overlay: CanvasLayer = null
var has_talked_to_blacksmith: bool = false

func create_spawn_hints() -> void:
	"""Create and show spawn hints overlay for new players"""
	print("📋 Creating spawn hints overlay")

	spawn_hints_overlay = CanvasLayer.new()
	spawn_hints_overlay.name = "SpawnHintsOverlay"
	spawn_hints_overlay.layer = 50  # Above game, below menus

	# Full-screen Control to enable anchors
	var full_rect = Control.new()
	full_rect.name = "FullRect"
	full_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spawn_hints_overlay.add_child(full_rect)

	# Main container - dead center on screen (center mass on player)
	var container = PanelContainer.new()
	container.name = "HintsPanel"
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -130
	container.offset_right = 130
	container.offset_top = -110
	container.offset_bottom = 110
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.38, 0.42, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	container.add_theme_stylebox_override("panel", style)

	full_rect.add_child(container)

	# Margin inside panel
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	container.add_child(margin)

	# VBox for hint rows
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))  # Gold
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sep)

	# Hint rows
	var hints = [
		["WASD", "Move"],
		["Left Click", "Attack"],
		["Space", "Dodge"],
		["C", "Character Sheet"],
		["I / B", "Inventory"],
		["F", "Interact / Loot"],
		["Enter", "Chat"],
	]

	for hint in hints:
		var row = HBoxContainer.new()

		var key_label = Label.new()
		key_label.text = hint[0]
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))  # Cyan keys
		key_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(key_label)

		var action_label = Label.new()
		action_label.text = hint[1]
		action_label.add_theme_font_size_override("font_size", 14)
		action_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row.add_child(action_label)

		vbox.add_child(row)

	# Objective hint at bottom (only if player hasn't talked to blacksmith yet)
	if not has_talked_to_blacksmith:
		var obj_sep = HSeparator.new()
		obj_sep.name = "ObjectiveSeparator"
		obj_sep.add_theme_constant_override("separation", 8)
		vbox.add_child(obj_sep)

		var objective = Label.new()
		objective.name = "ObjectiveLabel"
		objective.text = "Talk to the Blacksmith!"
		objective.add_theme_font_size_override("font_size", 14)
		objective.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))  # Yellow
		objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(objective)

	# ESC to close hint at bottom
	var esc_sep = HSeparator.new()
	esc_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(esc_sep)

	var esc_hint = Label.new()
	esc_hint.text = "ESC to close"
	esc_hint.add_theme_font_size_override("font_size", 12)
	esc_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))  # Gray
	esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(esc_hint)

	get_tree().root.add_child(spawn_hints_overlay)
	print("📋 Spawn hints overlay added to scene tree - Press ESC to toggle")

func dismiss_spawn_hints() -> void:
	"""Manually dismiss spawn hints early (called when talking to blacksmith)"""
	has_talked_to_blacksmith = true

	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		var container = spawn_hints_overlay.get_node_or_null("FullRect/HintsPanel")
		if container:
			var tween = create_tween()
			tween.tween_property(container, "modulate:a", 0.0, 0.3)
			await tween.finished
			# Destroy and recreate without the objective next time
			spawn_hints_overlay.queue_free()
			spawn_hints_overlay = null

func toggle_spawn_hints() -> void:
	"""Toggle spawn hints visibility with ESC"""
	# Play sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_character_sheet_sound"):
		sound_manager.play_character_sheet_sound()

	if not spawn_hints_overlay or not is_instance_valid(spawn_hints_overlay):
		# Recreate if it was destroyed
		create_spawn_hints()
		return

	var container = spawn_hints_overlay.get_node_or_null("FullRect/HintsPanel")
	if not container:
		return

	if container.visible:
		# Fade out
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 0.0, 0.2)
		await tween.finished
		container.visible = false
	else:
		# Fade in
		container.visible = true
		container.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(container, "modulate:a", 1.0, 0.2)

# ═══════════════════════════════════════════════════════════════════════════
# DASH/DODGE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func start_dash() -> void:
	"""Initiate a dash/dodge roll"""
	if is_dashing or dash_cooldown_timer > 0:
		return

	# Get dash direction from input, or mouse direction if standing still
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length() > 0.1:
		dash_direction = input_dir.normalized()
	else:
		# Dash toward mouse cursor if no movement input
		dash_direction = (get_global_mouse_position() - global_position).normalized()

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	print("💨 Dash started! Direction: %s" % dash_direction)

	# Visual effects
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		# Speed up animation during dash
		character_sprite.speed_scale = 3.0

		# Squash and stretch effect (subtle flatten in perpendicular direction)
		var stretch_scale = Vector2(1.15, 0.85) if abs(dash_direction.x) > abs(dash_direction.y) else Vector2(0.85, 1.15)
		character_sprite.scale = stretch_scale

	# Spawn initial dust puff
	spawn_dash_dust()

	# Spawn afterimages
	spawn_dash_afterimage()

	# Play dash/dodge whoosh sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_dodge_sound(global_position, -8.0)

func end_dash() -> void:
	"""End the dash and restore normal state"""
	is_dashing = false
	dash_direction = Vector2.ZERO

	# Restore sprite
	var character_sprite = get_node_or_null("CharacterSprite")
	if character_sprite:
		character_sprite.speed_scale = 1.0
		character_sprite.scale = Vector2.ONE

	# Spawn ending dust puff
	spawn_dash_dust()

	print("💨 Dash ended!")

func update_dash_visuals(delta: float) -> void:
	"""Update visual effects during dash"""
	# Spawn afterimages periodically during dash
	if randf() < 0.15:  # ~9 afterimages per second at 60fps
		spawn_dash_afterimage()

func spawn_dash_dust() -> void:
	"""Spawn dust puff effect at player's feet"""
	var dust = preload("res://scripts/effects/FootstepDust.gd").new()
	dust.global_position = global_position + Vector2(0, 20)  # At feet
	get_tree().root.add_child(dust)
	dust.spawn_dust()

	# Spawn a second dust for more impact
	var dust2 = preload("res://scripts/effects/FootstepDust.gd").new()
	dust2.global_position = global_position + Vector2(randf_range(-10, 10), 20)
	get_tree().root.add_child(dust2)
	dust2.spawn_dust()

func spawn_dash_afterimage() -> void:
	"""Spawn a fading afterimage of the player with all equipped gear"""
	var character_sprite = get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Create container for all afterimage layers
	var afterimage_container = Node2D.new()
	afterimage_container.global_position = global_position + character_sprite.position
	afterimage_container.scale = character_sprite.scale
	afterimage_container.modulate = Color(0.5, 0.7, 1.0, 0.6)  # Blue-tinted, semi-transparent
	afterimage_container.z_index = -1  # Behind player

	# Copy all sprite layers from CharacterSprite (body, armor, weapon, etc.)
	# The CharacterSprite has child AnimatedSprite2D nodes for each layer
	_copy_sprite_layer(character_sprite, afterimage_container)  # Main body

	# Copy child layers (shadow, armor, weapon, etc.)
	for child in character_sprite.get_children():
		if child is AnimatedSprite2D:
			_copy_sprite_layer(child, afterimage_container)

	get_tree().root.add_child(afterimage_container)

	# Fade out and remove
	var tween = afterimage_container.create_tween()
	tween.tween_property(afterimage_container, "modulate:a", 0.0, 0.15)
	tween.tween_callback(afterimage_container.queue_free)

func _copy_sprite_layer(source: AnimatedSprite2D, container: Node2D) -> void:
	"""Copy a single sprite layer to the afterimage container"""
	if not source.sprite_frames or not source.animation:
		return
	if not source.sprite_frames.has_animation(source.animation):
		return

	var layer_sprite = Sprite2D.new()
	layer_sprite.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	layer_sprite.position = source.position
	layer_sprite.z_index = source.z_index
	layer_sprite.centered = source.centered
	container.add_child(layer_sprite)

# ═══════════════════════════════════════════════════════════════════════════
# MOVEMENT MODIFIER SYSTEM (for debuffs like lava slow)
# ═══════════════════════════════════════════════════════════════════════════

func apply_movement_modifier(source: String, multiplier: float) -> void:
	"""Apply a movement speed modifier from a named source.
	multiplier: 0.5 = 50% speed reduction, 0.0 = completely stopped"""
	movement_modifiers[source] = clamp(multiplier, 0.0, 1.0)
	print("🦶 Movement modifier applied: %s = %.0f%% speed" % [source, multiplier * 100])

func remove_movement_modifier(source: String) -> void:
	"""Remove a movement modifier by source name"""
	if movement_modifiers.has(source):
		movement_modifiers.erase(source)
		print("🦶 Movement modifier removed: %s" % source)

func get_movement_modifier() -> float:
	"""Get the combined movement modifier (multiplies all active modifiers).
	Returns 1.0 if no modifiers active."""
	if movement_modifiers.is_empty():
		return 1.0

	var combined = 1.0
	for modifier in movement_modifiers.values():
		combined *= modifier
	return combined

func clear_all_movement_modifiers() -> void:
	"""Clear all active movement modifiers (e.g., on death/respawn)"""
	movement_modifiers.clear()
	print("🦶 All movement modifiers cleared")
