extends CharacterBody2D

## REFACTOR NOTE (Dec 2024): Asset paths reorganized
## - Weapons moved to: res://assets/equipment/weapons/
## - Clothing layers remain at: res://assets/characters/pants/, shirt/, etc.
## - If weapon sprites fail to load, check paths at equipment/weapons/[type]/

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_EQUIP: bool = true  # Debug all equipping (weapons, armor, sprite creation)
const DEBUG_FORGED_EQUIP: bool = false  # Debug forged weapon loading and effects (extra verbose)

# Weapon type fallbacks - extended types map to core types with available animations
# Based on backend items.json weapon_types.extended definitions
const WEAPON_TYPE_FALLBACKS = {
	"greatsword": "sword",
	"longsword": "sword",
	"crossbow": "staff",
	"bow": "staff",
	"pike": "spear",
	"trident": "spear",
	"flail": "mace",
	"scythe": "spear",
}

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

# PvP Duel System
var is_dueling: bool = false
var duel_opponent_id: int = -1
var has_safe_aura: bool = false
var duel_aura_node: Node2D = null
var safe_aura_node: Node2D = null
var blood_color: Color = Color(0.6, 0.05, 0.05, 0.9)  # Dark blood red (used for PvP hit effects)

# Allegiance System (synced for network visibility)
# "" = Rogue (no allegiance), "ashbane" = Ashbane faction
var allegiance_id: String = "ashbane"

# PvP Weakpoint System (HP threshold-based, scales with level like PvE)
# Two windows per duel: first at 70% HP, second at 35% HP
const PVP_WEAKPOINT_THRESHOLDS: Array = [0.70, 0.35]  # Trigger at 70%, 35% HP
const PVP_WEAKPOINT_DURATION: float = 3.5  # Seconds weakpoint window stays active
const PVP_WEAKPOINT_DAMAGE_PER_HIT: int = 3  # Damage per weakpoint click (balanced for multi-hit windows)
const PVP_WEAKPOINT_SCALE: float = 0.5  # Scale factor for PvP weakpoints (smaller than PvE)
# Weakpoint COUNT scales with level (matches PvE):
# Level 1-10: 1 weakpoint, Level 11-19: 2 weakpoints, Level 20+: 3 weakpoints
var pvp_triggered_thresholds: Array = []  # Which HP thresholds have been triggered
var pvp_weakpoint_active: bool = false  # Is there an active weakpoint window?
var pvp_weakpoints: Array = []  # Active weakpoint instances
var pvp_weakpoint_timer: Timer = null  # Window expiry timer
var pvp_weakpoints_destroyed: int = 0  # Count of cleared weakpoints this window
var pvp_weakpoints_spawned: int = 0  # Total weakpoints spawned in current window

# References
@onready var health_bar: Control = $HealthBar
@onready var crit_system: Node = $CritSystem
@onready var crit_window_manager: Node = $CritWindowManager

# Effect system
var screen_shake: ScreenShake = null
var attack_feedback: AttackFeedbackSystem = null

# Combat subsystem (handles attacks, healing, crit windows)
var combat_system: PlayerCombat = null

# Visual feedback
var cone_visualizer: Polygon2D = null
var circle_visualizer: Node2D = null  # Ranged weapon targeting circle (at cursor)
var _last_heal_pulse_time: float = 0.0  # Rate limit heal pulse visuals
var debug_mode: bool = false  # Synced with Constants.debug_display_visible
var debug_shapes: Node2D = null
var world_debug_nodes: Array = []  # Track world-space debug nodes for cleanup
var debug_update_timer: float = 0.0  # Throttle debug updates
var cone_update_timer: float = 0.0  # Throttle cone color updates (CRITICAL for performance!)

# Camera zoom
@export var zoom_min: float = 0.75  # Zoom out 1.33x (limited to prevent map reveal)
@export var zoom_max: float = 2.0   # Zoom in 2x (close-up)
@export var zoom_speed: float = 0.1 # How fast zoom transitions
var target_zoom: float = 1.0
var camera: Camera2D = null

# Debug zoom (unrestricted when F3 is active)
const DEBUG_ZOOM_MIN: float = 0.05  # Can zoom way out in debug mode
const DEBUG_ZOOM_MAX: float = 5.0   # Can zoom way in in debug mode
var normal_zoom_min: float = 0.75   # Store normal limits to restore
var normal_zoom_max: float = 2.0
var debug_zoom_active: bool = false

# Mobile controls
var mobile_controls: CanvasLayer = null
var _mobile_aim_active: bool = false  # Track if mobile aim touch is active

# Character UI
var character_ui: CanvasLayer = null

# Campfire Direction Indicator
var campfire_indicator: CanvasLayer = null

# Chat UI
var chat_ui: CanvasLayer = null

# Inventory UI (separate from character sheet)
var inventory_ui: CanvasLayer = null

# Portrait HUD (WoW-style health display)
var portrait_hud: CanvasLayer = null

# Duel UI components
var duel_request_popup: CanvasLayer = null
var duel_countdown_ui: CanvasLayer = null
var duel_result_ui: CanvasLayer = null

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

# Movement subsystem (handles dash, speed modifiers)
var movement_system: PlayerMovement = null

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

func get_attack_damage() -> float:
	return attack_damage

func is_invincible() -> bool:
	"""Check if player is currently invincible (for server damage validation)"""
	return is_dashing and dash_invincible

func _ready() -> void:
	# AUTO-SELECT MALE (can switch to female by pressing F key during gameplay)
	# Only set default gender if not already set by apply_appearance_data (for remote players)
	if selected_gender != Gender.FEMALE:
		selected_gender = Gender.MALE

	# Create player sprite immediately
	create_player_sprite()

	# For local player, broadcast appearance to other players after a short delay
	# (to ensure networking is ready)
	if is_multiplayer_authority():
		call_deferred("_broadcast_initial_appearance")
		# Apply saved display settings (resolution, fullscreen)
		call_deferred("_apply_saved_display_settings")

	# THEN: Initialize everything else

	# Initialize stats from CharacterStats - ONLY for local player
	# Remote players get their stats from network sync, not from local CharacterStats
	if is_multiplayer_authority():
		# Initialize stats from CharacterStats
		update_stats_from_character()

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

	# Initialize movement subsystem
	movement_system = PlayerMovement.new(self)
	movement_system.set_base_speed(speed)
	
	# Setup attack feedback system
	attack_feedback = AttackFeedbackSystem.new()
	add_child(attack_feedback)

	# Initialize combat subsystem
	combat_system = PlayerCombat.new(self)
	combat_system.crit_system = crit_system
	combat_system.crit_window_manager = crit_window_manager
	combat_system.screen_shake = screen_shake
	combat_system.attack_feedback = attack_feedback
	combat_system.update_stats(attack_damage, attack_cooldown, attack_range, attack_cone_angle)

	# Register with GameInput and setup mobile controls if needed
	if is_multiplayer_authority():
		GameInput.set_player(self)
		if GameInput.is_mobile():
			_setup_mobile_controls()
		# Connect mobile signals
		if MobileInput:
			MobileInput.pinch_zoom.connect(apply_pinch_zoom)
			MobileInput.dash_pressed.connect(_on_mobile_dash_pressed)
			MobileInput.inventory_pressed.connect(_on_mobile_inventory_pressed)
			MobileInput.character_pressed.connect(_on_mobile_character_pressed)

	# Setup debug shapes container - only for local player
	if is_multiplayer_authority():
		debug_shapes = Node2D.new()
		debug_shapes.name = "DebugShapes"
		debug_shapes.z_index = 1000
		add_child(debug_shapes)

		# Connect to F3 debug toggle from Constants (syncs debug_mode)
		if Constants:
			Constants.debug_display_toggled.connect(_on_constants_debug_toggled)
			debug_mode = Constants.debug_display_visible

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

			# Connect to debug toggle for unrestricted zoom
			if Constants:
				Constants.debug_display_toggled.connect(_on_debug_zoom_toggled)

			# Start background music
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager and sound_manager.has_method("play_game_music"):
				sound_manager.play_game_music(-18.0)  # Background level
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
		CharacterStats.allegiance_changed.connect(_on_allegiance_changed)

		# Sync initial allegiance from CharacterStats
		allegiance_id = CharacterStats.get_allegiance()
		# Broadcast to other players after networking is ready
		call_deferred("_broadcast_allegiance")

		# Create character UI after this frame
		call_deferred("create_character_ui")

		# Create campfire direction indicator
		call_deferred("create_campfire_indicator")

		# Create chat UI
		call_deferred("create_chat_ui")

		# Create inventory UI (separate from character sheet)
		call_deferred("create_inventory_ui")

		# Create portrait HUD (WoW-style health display)
		call_deferred("create_portrait_hud")

		# Create duel UI components
		call_deferred("create_duel_ui")

		# NOTE: Spawn hints no longer auto-show on launch (tutorial system handles new player guidance)
		# Controls menu is still accessible via ESC when no other menus are open

		# Create tutorial blackout if in tutorial and connect to updates
		call_deferred("update_tutorial_blackout")
		if TutorialManager:
			TutorialManager.tutorial_step_completed.connect(_on_tutorial_step_for_blackout)
			TutorialManager.tutorial_completed.connect(_on_tutorial_completed_for_blackout)

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
	if CharacterStats.allegiance_changed.is_connected(_on_allegiance_changed):
		CharacterStats.allegiance_changed.disconnect(_on_allegiance_changed)

	# Clean up circle visualizer (it's parented to root, not player)
	if circle_visualizer and is_instance_valid(circle_visualizer):
		circle_visualizer.queue_free()
		circle_visualizer = null

	# Clean up mobile controls
	if mobile_controls and is_instance_valid(mobile_controls):
		mobile_controls.queue_free()
		mobile_controls = null

	# Disconnect mobile signals
	if MobileInput:
		if MobileInput.pinch_zoom.is_connected(apply_pinch_zoom):
			MobileInput.pinch_zoom.disconnect(apply_pinch_zoom)
		if MobileInput.dash_pressed.is_connected(_on_mobile_dash_pressed):
			MobileInput.dash_pressed.disconnect(_on_mobile_dash_pressed)


func _setup_mobile_controls() -> void:
	"""Set up mobile touch controls UI."""
	var mobile_controls_scene = load("res://scenes/mobile/MobileControls.tscn")
	if mobile_controls_scene:
		mobile_controls = mobile_controls_scene.instantiate()
		get_tree().root.add_child(mobile_controls)
		print("[Player] Mobile controls initialized")
	else:
		push_warning("[Player] Failed to load MobileControls.tscn")


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
	# Sync with movement subsystem
	if movement_system:
		movement_system.set_base_speed(speed)
	
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

	# Sync hold_attack_interval to weapon cooldown (held attacks match weapon speed)
	hold_attack_interval = attack_cooldown

	# Update attack range based on weapon type
	var weapon_type = "unarmed"
	if CharacterStats.equipped_weapon:
		weapon_type = CharacterStats.equipped_weapon.weapon_type
	attack_range = WeaponAnimationData.get_attack_range(weapon_type)

	# Sync with combat subsystem
	if combat_system:
		combat_system.update_stats(attack_damage, attack_cooldown, attack_range, attack_cone_angle)

	# Update cone visualizer to match new range
	update_cone_visualizer()

func gain_experience(amount: int) -> void:
	"""Grant experience to the player (called when enemy dies)"""
	CharacterStats.gain_experience(amount)

func _on_character_level_up(new_level: int) -> void:
	"""Called when character levels up"""

	# Update all stats
	update_stats_from_character()

	# Heal to full
	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if portrait_hud and portrait_hud.has_method("update_health"):
		portrait_hud.update_health(current_health, max_health)

	# Visual feedback
	if screen_shake:
		screen_shake.add_trauma(0.3)

	# Play level up sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_level_up_sound"):
		sound_manager.play_level_up_sound(-8.0)

func _on_weapon_equipped(weapon) -> void:  # weapon is Weapon type
	"""Called when weapon is equipped"""
	if DEBUG_EQUIP:
		print("[Equip] Weapon equipped: %s" % weapon.weapon_name)
	update_stats_from_character()

	# Reset attack state - ensures player can attack after switching weapons
	# This prevents being stuck in can_attack=false if switched during cooldown
	can_attack = true

	# Refresh player sprite to show the new weapon
	create_player_sprite()

	# Switch visualizer based on weapon type (cone for melee, circle for ranged)
	switch_visualizer_mode()

	# Sync to network
	_sync_appearance_to_network()

func _on_weapon_unequipped() -> void:
	"""Called when weapon is unequipped"""
	if DEBUG_EQUIP:
		print("[Equip] Weapon unequipped - back to unarmed")
	update_stats_from_character()

	# Reset attack state - ensures player can attack after switching weapons
	# This prevents being stuck in can_attack=false if unequipped during cooldown
	can_attack = true

	# Refresh player sprite to remove weapon
	create_player_sprite()

	# Switch back to melee visualizer (cone)
	switch_visualizer_mode()

	# Sync to network
	_sync_appearance_to_network()

func _on_armor_equipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is equipped"""
	if DEBUG_EQUIP:
		print("[Equip] Armor equipped in slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to show the new armor
	create_player_sprite()

	# Sync to network
	_sync_appearance_to_network()

func _on_armor_unequipped(slot: String, armor_item: Dictionary) -> void:
	"""Called when armor is unequipped"""
	if DEBUG_EQUIP:
		print("[Equip] Armor unequipped from slot %s: %s" % [slot, armor_item["name"]])
	update_stats_from_character()

	# Refresh player sprite to remove armor
	create_player_sprite()

	# Sync to network
	_sync_appearance_to_network()

func _physics_process(delta: float) -> void:
	# Only process for local player
	if not is_multiplayer_authority():
		return

	# Get input direction (used for movement and animation)
	# Block movement input when chat is focused
	var input_direction := Vector2.ZERO
	if not (chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused()):
		input_direction = GameInput.get_movement()

	# Use movement subsystem for velocity calculation (handles dash, speed modifiers)
	if movement_system:
		velocity = movement_system.process_movement(delta, input_direction)
		# Sync dash state from subsystem to player (needed for network sync and invincibility)
		is_dashing = movement_system.is_dashing
		dash_direction = movement_system.dash_direction
	else:
		# Fallback if subsystem not initialized
		velocity = input_direction * speed

	move_and_slide()

	# Tutorial boundary - restrict player to safe zone until tutorial complete
	if TutorialManager and TutorialManager.is_tutorial_active():
		var tutorial_step = TutorialManager.current_step
		# During early tutorial steps, keep player near campfire/dummy/blacksmith
		if tutorial_step < TutorialManager.TutorialStep.KILL_SKELETON:
			var campfire_pos = Vector2(Constants.CHUNK_SIZE / 2, 0)  # Center of chunk 0
			var tutorial_radius = 500.0  # Enough for campfire, dummy, and blacksmith
			var distance_from_center = global_position.distance_to(campfire_pos)

			if distance_from_center > tutorial_radius:
				# Push player back inside boundary
				var direction_to_center = (campfire_pos - global_position).normalized()
				global_position = campfire_pos - direction_to_center * tutorial_radius
				velocity = Vector2.ZERO

	# Clamp player position to world boundaries
	if movement_system:
		global_position = movement_system.clamp_to_world_bounds(global_position)
	else:
		# Fallback
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
	var aim_pos := GameInput.get_aim_position()
	attack_direction = GameInput.get_aim_direction()
	# Sync attack direction to combat subsystem
	if combat_system:
		combat_system.attack_direction = attack_direction

	# Handle held attack (continuous attacking/healing while mouse or touch held)
	var is_attack_held = is_mouse_held or GameInput.is_attack_held()
	if is_attack_held:
		# ❌ BLOCK HOLD ATTACKS when UI is open
		if is_ui_blocking_input():
			is_mouse_held = false  # Cancel hold state when UI opens
			hold_attack_timer = 0.0
			if combat_system:
				combat_system.is_mouse_held = false
				combat_system.hold_attack_timer = 0.0
		else:
			# Combat subsystem handles held attack logic
			if combat_system:
				combat_system.process_held_attack(delta, aim_pos)
	
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

	# Process logout timer
	_process_logout_timer(delta, input_direction)

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

	# Don't interrupt attack animations (slash for melee, shoot for guns/bows)
	if character_sprite.animation and character_sprite.is_playing():
		if character_sprite.animation.begins_with("slash_"):
			return
		# Don't interrupt shoot animations on main body (bows use this)
		if character_sprite.animation.begins_with("shoot_"):
			return
		# For gun weapons, check if gun body layer is playing shoot animation
		if character_sprite.gun_body_sprite and character_sprite.gun_body_sprite.visible:
			if character_sprite.gun_body_sprite.animation and character_sprite.gun_body_sprite.animation.begins_with("shoot_") and character_sprite.gun_body_sprite.is_playing():
				return

	# Get direction - always face cursor (attack_direction), not movement direction
	var is_moving = velocity_dir.length() > 0.1
	var dir_str = get_direction_string(attack_direction)

	# Convert to LPC direction (south/north/west/east)
	var lpc_dir = convert_to_lpc_direction(dir_str)

	# Play animation
	var anim = "walk" if is_moving else "idle"
	character_sprite.play_lpc_animation(anim, lpc_dir)

func get_attack_direction() -> Vector2:
	"""Get the player's current facing/attack direction (towards mouse)"""
	return attack_direction


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
	attack_direction = GameInput.get_aim_direction()

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

				# Combat subsystem handles all attack logic
				if combat_system:
					combat_system.is_mouse_held = true
					combat_system.hold_attack_timer = 0.0
					var mouse_pos = get_global_mouse_position()
					combat_system.on_mouse_pressed(mouse_pos)
			else:
				# Mouse released - stop hold state
				is_mouse_held = false
				hold_attack_timer = 0.0
				# Sync to combat subsystem
				if combat_system:
					combat_system.on_mouse_released()
		
		# ✨ FIX: CAMERA ZOOM - Mouse wheel handling (disabled when shop is open or minimap hovered)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if not is_shop_open() and not _is_minimap_hovered():
				zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if not is_shop_open() and not _is_minimap_hovered():
				zoom_out()

	# Mobile touch-to-aim input (mirrors mouse behavior)
	if event is InputEventScreenTouch and GameInput.is_mobile():
		if MobileInput.is_in_aim_zone(event.position):
			var world_pos = MobileInput.screen_to_world(event.position)
			if event.pressed:
				# Touch started in aim zone - trigger attack
				if is_ui_blocking_input():
					return

				# Trigger initial attack (same as mouse press)
				if combat_system:
					combat_system.is_mouse_held = true
					combat_system.hold_attack_timer = 0.0
					combat_system.on_mouse_pressed(world_pos)
			else:
				# Touch ended - stop held attack
				if combat_system:
					combat_system.on_mouse_released()

	# Debug mode toggle (debug builds only)
	if event is InputEventKey and event.pressed:
		# Block most game keys while typing in chat (allow F-keys for debug)
		var is_f_key = event.keycode >= KEY_F1 and event.keycode <= KEY_F12
		if not is_f_key and chat_ui and chat_ui.has_method("is_chat_focused") and chat_ui.is_chat_focused():
			return

		# Debug keys only available in editor or debug builds
		var is_dev_build = OS.has_feature("editor") or OS.is_debug_build()

		match event.keycode:
			KEY_F4 when is_dev_build:
				# DEBUG: Progress equipped weapon (add levels + kills)
				if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.weapon_stats:
					var stats = CharacterStats.equipped_weapon.weapon_stats
					stats.debug_add_levels(10)
					stats.debug_add_kills(500)
					print("🗡️ DEBUG F4: Weapon progressed - Level: %d, Kills: %d, Tier: %s" % [
						stats.level, stats.kills_total, stats.get_visual_tier_name()
					])
					# Refresh visual effects to match new tier
					refresh_forged_weapon_effects()
				else:
					print("🗡️ DEBUG F4: No weapon equipped or no weapon stats")
					print("   equipped_weapon: %s" % CharacterStats.equipped_weapon)
					if CharacterStats.equipped_weapon:
						print("   is_forged: %s" % CharacterStats.equipped_weapon.is_forged)
						print("   forged_id: %s" % CharacterStats.equipped_weapon.forged_id)
						print("   weapon_stats: %s" % CharacterStats.equipped_weapon.weapon_stats)
			KEY_F5 when is_dev_build:
				# Toggle mobile input mode for testing
				var was_mobile = GameInput.is_mobile()
				GameInput.toggle_mobile_mode()
				if was_mobile:
					# Switched to desktop
					if mobile_controls and is_instance_valid(mobile_controls):
						mobile_controls.queue_free()
						mobile_controls = null
					print("📱 DEBUG: Mobile mode DISABLED - using mouse/keyboard")
				else:
					# Switched to mobile
					_setup_mobile_controls()
					print("📱 DEBUG: Mobile mode ENABLED - using touch controls")
			KEY_F6 when is_dev_build:
				# Debug: Heal to full health
				current_health = max_health
				if health_bar and health_bar.has_method("update_health"):
					health_bar.update_health(current_health, max_health)
				print("💚 DEBUG: Healed to full health (%d/%d)" % [current_health, max_health])
			KEY_G when is_dev_build:
				# Switch gender - only for local player (debug only)
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

			# F3 handled by Constants.toggle_debug_display() - Player connects via _on_constants_debug_toggled

			KEY_F6 when is_dev_build:
				# Reset to level 1
				CharacterStats.reset_character()
				update_stats_from_character()
				current_health = max_health
				if health_bar and health_bar.has_method("update_health"):
					health_bar.update_health(current_health, max_health)
				print("Character reset to level 1")

			KEY_F7 when is_dev_build:
				# Print all stats
				CharacterStats.print_stats()

			KEY_F8 when is_dev_build:
				# Fix negative XP
				CharacterStats.debug_fix_negative_xp()
				update_stats_from_character()
				print("Press F7 to verify XP is fixed")

			KEY_F9 when is_dev_build:
				# DEBUG: Toggle full map view (zoom out to see entire world)
				toggle_debug_map_view()
			KEY_F10 when is_dev_build:
				# DEBUG: Toggle allegiance between Ashbane and Rogue
				if CharacterStats.is_rogue():
					CharacterStats.join_ashbane()
					print("🌳 DEBUG: Switched to ASHBANE allegiance")
				else:
					CharacterStats.go_rogue()
					print("⚔️ DEBUG: Switched to ROGUE (no allegiance)")

			KEY_F12 when is_dev_build:
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
				# Dash/dodge - use movement subsystem
				if movement_system and movement_system.can_dash():
					var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
					movement_system.start_dash(input_dir, get_global_mouse_position())
				elif not movement_system:
					# Fallback to old system
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

				# Check if GameMenu settings/credits panel is open
				var game_menu = get_node_or_null("/root/main/GameMenu")
				if game_menu and game_menu.is_open:
					# Let GameMenu handle its own ESC
					return

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

# NOTE: Combat functions moved to PlayerCombat subsystem:
# - check_crit_window_click, is_holding_on_crit_window_enemy, is_clicking_on_weakpoint
# - handle_crit_window_attack, attempt_attack, get_enemies_in_cone, attack_enemies_in_cone

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
	"""Check if a player is friendly for healing purposes based on allegiance.
	- Same allegiance = can heal
	- Party members = can heal (regardless of allegiance)
	- Rogues can only heal party members
	- Different allegiance non-party = cannot heal
	- Duel combatants = cannot heal (unless party member)
	"""
	var target_id = player_node.get_multiplayer_authority()

	# Party members are always friendly
	var is_party_member = GroupManager and GroupManager.is_group_member(target_id)
	if is_party_member:
		return true

	# Duel isolation: cannot heal duel combatants (unless party member)
	if player_node.get("is_dueling") == true:
		return false

	# Get target's allegiance
	var target_allegiance = player_node.get("allegiance_id")
	if target_allegiance == null:
		target_allegiance = "ashbane"  # Default

	# Use CharacterStats allegiance check
	return CharacterStats.can_heal_player(target_allegiance, false)

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
	# Healing scales with Intelligence (caster stat)
	var stat_bonus = (CharacterStats.get_effective_intelligence() - 10) * 0.5
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
		sound_manager.play_healing_cast_sound(global_position, -10.0)

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
				sound_manager.play_healing_impact_sound(target, -8.0)
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

# NOTE: attack_enemies_in_cone moved to PlayerCombat subsystem

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

	# Calculate and apply damage
	if is_nan(success_ratio) or is_inf(success_ratio):
		success_ratio = 0.0

	var base_crit_damage = attack_damage * 2.0
	var multiplier = 1.0 + success_ratio
	var final_damage = base_crit_damage * multiplier

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

	# Only process if we just finished an attack animation (slash for melee, shoot for bows)
	if not character_sprite.animation:
		return
	if not character_sprite.animation.begins_with("slash_") and not character_sprite.animation.begins_with("shoot_"):
		return

	# Return to idle in current facing direction
	var dir_str = get_direction_string(attack_direction)
	var lpc_dir = convert_to_lpc_direction(dir_str)
	character_sprite.play_lpc_animation("idle", lpc_dir)

func take_damage(amount: float, source_type: String = "pve", source_player_id: int = -1) -> void:
	# I-frames during dash
	if is_dashing and dash_invincible:
		print("Damage dodged! (dashing)")
		return

	# SAFE AURA: Block player damage post-duel
	if has_safe_aura and source_type == "player":
		return

	# Handle player damage (PvP)
	if source_type == "player":
		if is_dueling:
			# DUEL ISOLATION: Only duel opponent can damage me during a duel
			if source_player_id != duel_opponent_id:
				return  # Ignore non-duel-opponent damage

			# Check HP thresholds for PvP weakpoint system (before applying damage)
			if not pvp_weakpoint_active:
				var hp_before_pct = current_health / max_health
				var hp_after_pct = (current_health - amount) / max_health
				for threshold in PVP_WEAKPOINT_THRESHOLDS:
					if hp_before_pct > threshold and hp_after_pct <= threshold:
						if threshold not in pvp_triggered_thresholds:
							pvp_triggered_thresholds.append(threshold)
							print("[PvP] HP threshold %.0f%% crossed - spawning weakpoints!" % (threshold * 100))
							spawn_pvp_weakpoint_window()
							break  # Only trigger one window per hit

			# Check for duel end condition (1 HP threshold)
			if current_health - amount <= 1:
				current_health = 1
				if health_bar and health_bar.has_method("update_health"):
					health_bar.update_health(current_health, max_health)
				CombatText.create_damage(amount, global_position, get_tree().root, attack_direction)
				flash_player_sprite()
				# Report loss to DuelManager
				if DuelManager:
					DuelManager.report_duel_loss()
				return
		else:
			# OPEN-WORLD PvP: Server already validated allegiance rules
			# Just accept the damage (no duel mechanics like weakpoints or 1HP threshold)
			pass

	# Cancel logout if taking damage (combat logging prevention)
	if logout_timer_active:
		_cancel_logout()
		if NotificationManager:
			NotificationManager.show_notification("Logout cancelled - you took damage!", "WARNING")

	# SHIELD BLOCKING (PvE only)
	if source_type == "pve":
		var shield = CharacterStats.get_equipped_shield()
		if not shield.is_empty():
			# Calculate block chance: base from shield + bonus from skill
			var base_block_chance = shield.get("block_chance", 0.0)
			var skill_bonus = WeaponSkillManager.get_block_skill_bonus()
			var total_block_chance = min(base_block_chance + skill_bonus, 0.50)  # Cap at 50%

			var roll = randf()
			if roll < total_block_chance:
				# FULL BLOCK - negate all damage
				WeaponSkillManager.on_block()
				CombatText.create_block(global_position, get_tree().root)
				print("🛡️ BLOCKED! (roll %.2f < %.2f)" % [roll, total_block_chance])
				# Play block sound
				SoundManager.play_sound(SoundManager.SoundType.SHIELD_BLOCK, global_position)
				return  # No damage taken
			elif roll < total_block_chance * 1.5:
				# PARTIAL BLOCK - reduce damage based on block efficiency
				WeaponSkillManager.on_partial_block()
				var efficiency = CharacterStats.get_block_efficiency()
				amount = amount * (1.0 - efficiency)
				CombatText.create_partial_block(global_position, get_tree().root)
				print("🛡️ Partial block! %.0f%% reduction (roll %.2f)" % [efficiency * 100, roll])
			else:
				# No block, but still gain some skill for having shield equipped
				WeaponSkillManager.on_hit_with_shield()

	# Apply armor mitigation (PvE only - PvP uses separate balance)
	var mitigated_amount = amount
	if source_type == "pve":
		var defense = CharacterStats.get_total_defense()
		if defense > 0:
			# Diminishing returns formula: mitigation = defense / (defense + K)
			var mitigation_pct = defense / (defense + Constants.DEFENSE_CONSTANT)
			mitigated_amount = amount * (1.0 - mitigation_pct)
			mitigated_amount = max(mitigated_amount, Constants.MIN_DAMAGE_AFTER_MITIGATION)
			if mitigated_amount < amount:
				print("🛡️ Armor mitigated %.1f → %.1f (%.0f%% reduction from %d defense)" % [
					amount, mitigated_amount, mitigation_pct * 100, defense])

	print("Player taking %.1f damage (current: %.1f)" % [mitigated_amount, current_health])
	current_health -= mitigated_amount

	# Ensure health doesn't go below 0
	if current_health < 0:
		current_health = 0

	# Track equipment stats on all forged armor/accessories
	_record_equipment_hit(mitigated_amount, current_health > 0)

	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if portrait_hud and portrait_hud.has_method("update_health"):
		portrait_hud.update_health(current_health, max_health)

	# Spawn damage number behind player (opposite of facing direction)
	CombatText.create_damage(mitigated_amount, global_position, get_tree().root, attack_direction)

	# Reset combat timer (entering combat)
	time_since_last_damage = 0.0
	is_in_combat = true

	print("Player health now: %.1f / %.1f" % [current_health, max_health])

	# Flash player sprite red when hit
	flash_player_sprite()

	# Spawn blood splash particles (especially for PvP)
	if source_type == "player":
		spawn_blood_splash(source_player_id)

	# Play player hurt sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_player_hurt_sound(global_position, -8.0)

	if current_health <= 0:
		print("Player death triggered!")
		die()

func heal(amount: float, source_type: String = "self") -> void:
	"""Heal the player by the given amount
	source_type: 'self' (potions), 'player' (ally heals), 'campfire', 'passive'"""
	# During duel: block outside player healing (campfire/ally heals blocked)
	# Self-heals (potions) are allowed
	if is_dueling and source_type in ["player", "campfire"]:
		return

	# Validate heal amount
	if is_nan(amount) or is_inf(amount) or amount <= 0:
		push_warning("Invalid heal amount: %s" % str(amount))
		return

	if current_health >= max_health:
		return  # Already at full health

	var actual_heal = min(amount, max_health - current_health)
	current_health += actual_heal

	# Update health bar
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if portrait_hud and portrait_hud.has_method("update_health"):
		portrait_hud.update_health(current_health, max_health)

	# Spawn heal number behind player (opposite of facing direction)
	CombatText.create_heal(actual_heal, global_position, get_tree().root, attack_direction)

	print("Player healed %.1f HP (now %.1f / %.1f)" % [actual_heal, current_health, max_health])

# ═══════════════════════════════════════════════════════════════════════════
# EQUIPMENT STAT TRACKING (Forged Armor/Accessories)
# ═══════════════════════════════════════════════════════════════════════════

func _record_equipment_hit(damage: float, survived: bool) -> void:
	"""Record a hit on all equipped forged armor and accessories for stat tracking"""
	if not CharacterStats:
		return

	# Track on all equipped armor
	for slot in CharacterStats.equipped_armor:
		var armor_item = CharacterStats.equipped_armor[slot]
		if armor_item and armor_item is Dictionary:
			# Only track forged items
			if armor_item.get("is_forged", false) or armor_item.get("forged", false):
				_update_equipment_stats(armor_item, damage, survived)

	# Track on equipped accessories (if any - future feature)
	if "equipped_accessories" in CharacterStats and CharacterStats.equipped_accessories:
		for slot in CharacterStats.equipped_accessories:
			var accessory = CharacterStats.equipped_accessories[slot]
			if accessory and accessory is Dictionary:
				if accessory.get("is_forged", false) or accessory.get("forged", false):
					_update_equipment_stats(accessory, damage, survived)

func _update_equipment_stats(item: Dictionary, damage: float, survived: bool) -> void:
	"""Update equipment stats for a forged item"""
	# Get or create equipment_stats
	if not item.has("equipment_stats"):
		item["equipment_stats"] = {}

	var stats_data = item["equipment_stats"]

	# Record hit
	stats_data["hits_received"] = stats_data.get("hits_received", 0) + 1
	stats_data["damage_taken_total"] = stats_data.get("damage_taken_total", 0) + int(damage)

	if survived:
		stats_data["hits_survived"] = stats_data.get("hits_survived", 0) + 1
		# Track max hit survived
		if int(damage) > stats_data.get("damage_max_hit_survived", 0):
			stats_data["damage_max_hit_survived"] = int(damage)

	# Check for close call (below 25% HP)
	var health_percent = current_health / max_health if max_health > 0 else 0
	if health_percent < 0.25 and health_percent > 0:
		stats_data["close_calls"] = stats_data.get("close_calls", 0) + 1

	# Grant XP
	var xp = stats_data.get("experience", 0) + (2 if survived else 1)
	stats_data["experience"] = xp

	# Check for level up
	var level = stats_data.get("level", 0)
	var xp_needed = int(100.0 * pow(1.08, level))
	while xp >= xp_needed:
		xp -= xp_needed
		level += 1
		xp_needed = int(100.0 * pow(1.08, level))
	stats_data["level"] = level
	stats_data["experience"] = xp

	# First hit timestamp
	if stats_data.get("first_hit_taken_at", "") == "":
		var datetime = Time.get_datetime_dict_from_system()
		stats_data["first_hit_taken_at"] = "%04d-%02d-%02dT%02d:%02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]

func _record_equipment_death() -> void:
	"""Record death on all equipped forged armor and accessories"""
	if not CharacterStats:
		return

	for slot in CharacterStats.equipped_armor:
		var armor_item = CharacterStats.equipped_armor[slot]
		if armor_item and armor_item is Dictionary:
			if armor_item.get("is_forged", false) or armor_item.get("forged", false):
				if not armor_item.has("equipment_stats"):
					armor_item["equipment_stats"] = {}
				armor_item["equipment_stats"]["deaths_wearing"] = armor_item["equipment_stats"].get("deaths_wearing", 0) + 1
				armor_item["equipment_stats"]["battles_lost"] = armor_item["equipment_stats"].get("battles_lost", 0) + 1

	if "equipped_accessories" in CharacterStats and CharacterStats.equipped_accessories:
		for slot in CharacterStats.equipped_accessories:
			var accessory = CharacterStats.equipped_accessories[slot]
			if accessory and accessory is Dictionary:
				if accessory.get("is_forged", false) or accessory.get("forged", false):
					if not accessory.has("equipment_stats"):
						accessory["equipment_stats"] = {}
					accessory["equipment_stats"]["deaths_wearing"] = accessory["equipment_stats"].get("deaths_wearing", 0) + 1
					accessory["equipment_stats"]["battles_lost"] = accessory["equipment_stats"].get("battles_lost", 0) + 1

# ═══════════════════════════════════════════════════════════════════════════
# PVP DUEL STATE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

func spawn_blood_splash(attacker_id: int) -> void:
	"""Spawn blood splash particles when taking PvP damage"""
	# Get attacker position to calculate splash direction
	var attacker_pos = global_position + Vector2.LEFT * 50  # Default direction if attacker not found

	if DuelManager:
		var attacker_node = DuelManager._get_player_node(attacker_id)
		if attacker_node:
			attacker_pos = attacker_node.global_position

	# Calculate direction away from attacker (blood splatters away from hit)
	var direction = (global_position - attacker_pos).normalized()

	# Create blood splatter particles
	var blood = CPUParticles2D.new()
	blood.global_position = global_position
	blood.rotation = direction.angle()

	# Use player's blood color
	blood.amount = 10
	blood.color = blood_color
	blood.scale_amount_min = 1.5
	blood.scale_amount_max = 3.0
	blood.initial_velocity_min = 50.0
	blood.initial_velocity_max = 90.0

	# Particle properties
	blood.emitting = true
	blood.one_shot = true
	blood.lifetime = 0.35
	blood.speed_scale = 2.5
	blood.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	blood.spread = 55.0  # Spray pattern
	blood.gravity = Vector2(0, 180)  # Blood falls down
	blood.damping_min = 60.0
	blood.damping_max = 120.0

	# Fade out gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 1))
	gradient.add_point(0.6, Color(1, 1, 1, 0.8))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	blood.color_ramp = gradient

	# Add to world
	get_parent().add_child(blood)

	# Cleanup after particles finish
	var timer = get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		if is_instance_valid(blood):
			blood.queue_free()
	)

func enter_duel_state(opponent_id: int) -> void:
	"""Called by DuelManager when duel starts"""
	is_dueling = true
	duel_opponent_id = opponent_id
	pvp_triggered_thresholds.clear()  # Reset HP threshold tracking
	clear_pvp_weakpoint_window()
	_create_duel_aura()
	print("Entered duel state vs player %d" % opponent_id)

func exit_duel_state() -> void:
	"""Called by DuelManager when duel ends"""
	is_dueling = false
	duel_opponent_id = -1
	pvp_triggered_thresholds.clear()  # Reset HP threshold tracking
	clear_pvp_weakpoint_window()
	_remove_duel_aura()
	print("Exited duel state")

func apply_safe_aura() -> void:
	"""Called by DuelManager after duel ends - 10 second protection"""
	has_safe_aura = true
	_create_safe_aura()
	print("Safe aura applied")

func remove_safe_aura() -> void:
	"""Called by DuelManager when safe aura expires"""
	has_safe_aura = false
	_remove_safe_aura_visual()
	print("Safe aura removed")

# ============================================
# ALLEGIANCE SYSTEM
# ============================================

func _on_allegiance_changed(_old_allegiance: String, new_allegiance: String) -> void:
	"""Called when CharacterStats allegiance changes"""
	allegiance_id = new_allegiance
	_broadcast_allegiance()

func _broadcast_allegiance() -> void:
	"""Broadcast our allegiance to all other players"""
	if not multiplayer.has_multiplayer_peer():
		return
	rpc("_receive_allegiance", allegiance_id)

@rpc("any_peer", "reliable")
func _receive_allegiance(new_allegiance: String) -> void:
	"""Receive allegiance update from another player"""
	allegiance_id = new_allegiance
	# Update shield if exists
	var shield = get_node_or_null("AllegianceShield")
	if shield and shield.has_method("set_allegiance"):
		shield.set_allegiance(new_allegiance)

func is_rogue() -> bool:
	"""Check if this player is a rogue (no allegiance)"""
	return allegiance_id.is_empty()

func get_allegiance() -> String:
	"""Get this player's allegiance ID"""
	return allegiance_id

func _create_duel_aura() -> void:
	"""Create red pulsing aura for duel state"""
	if duel_aura_node:
		return  # Already exists

	duel_aura_node = Node2D.new()
	duel_aura_node.name = "DuelAura"
	duel_aura_node.z_index = -1  # Behind player

	# Create pulsing red circle
	var circle = _create_aura_circle(Color(1.0, 0.3, 0.2, 0.4), 28.0)
	duel_aura_node.add_child(circle)

	add_child(duel_aura_node)
	_start_aura_pulse(duel_aura_node, Color(1.0, 0.3, 0.2, 0.4), Color(1.0, 0.5, 0.3, 0.6))

func _remove_duel_aura() -> void:
	"""Remove duel aura visual"""
	if duel_aura_node and is_instance_valid(duel_aura_node):
		duel_aura_node.queue_free()
		duel_aura_node = null

func _create_safe_aura() -> void:
	"""Create golden pulsing aura for safe state"""
	if safe_aura_node:
		return  # Already exists

	safe_aura_node = Node2D.new()
	safe_aura_node.name = "SafeAura"
	safe_aura_node.z_index = -1  # Behind player

	# Create pulsing golden circle
	var circle = _create_aura_circle(Color(1.0, 0.85, 0.3, 0.35), 32.0)
	safe_aura_node.add_child(circle)

	add_child(safe_aura_node)
	_start_aura_pulse(safe_aura_node, Color(1.0, 0.85, 0.3, 0.35), Color(1.0, 0.95, 0.5, 0.5))

func _remove_safe_aura_visual() -> void:
	"""Remove safe aura visual"""
	if safe_aura_node and is_instance_valid(safe_aura_node):
		safe_aura_node.queue_free()
		safe_aura_node = null

func _create_aura_circle(color: Color, radius: float) -> Polygon2D:
	"""Create a circular aura polygon"""
	var circle = Polygon2D.new()
	var points: PackedVector2Array = []
	var segments = 24

	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	circle.polygon = points
	circle.color = color
	return circle

func _start_aura_pulse(aura_node: Node2D, color_min: Color, color_max: Color) -> void:
	"""Start pulsing animation on aura"""
	if not aura_node or not is_instance_valid(aura_node):
		return

	var circle = aura_node.get_child(0) as Polygon2D
	if not circle:
		return

	# Create looping tween for pulse effect
	var tween = create_tween().set_loops()
	tween.tween_property(circle, "color", color_max, 0.6).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(circle, "color", color_min, 0.6).set_ease(Tween.EASE_IN_OUT)

# ============================================
# PVP WEAKPOINT SYSTEM (v2 - Multi-click gem weakpoints)
# ============================================

func spawn_pvp_weakpoint_window() -> void:
	"""Spawn a clickable weakpoint window on this player during a duel.
	Called locally when HP threshold crossed - broadcasts to all peers via RPC."""
	print("[PvP] spawn_pvp_weakpoint_window called, active=%s, is_dueling=%s" % [pvp_weakpoint_active, is_dueling])
	if pvp_weakpoint_active or not is_dueling:
		print("[PvP] spawn_pvp_weakpoint_window blocked: active=%s, is_dueling=%s" % [pvp_weakpoint_active, is_dueling])
		return

	# Broadcast to all peers (including self via call_local)
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	print("[PvP] Broadcasting weakpoint spawn, my_peer_id=%d, is_server=%s" % [my_peer_id, multiplayer.is_server()])
	if multiplayer.is_server():
		_sync_pvp_weakpoint_window_spawn.rpc(my_peer_id)
	else:
		# Client requests server to broadcast
		_request_pvp_weakpoint_window_spawn.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_pvp_weakpoint_window_spawn() -> void:
	"""Client requests server to broadcast weakpoint window spawn"""
	print("[PvP] _request_pvp_weakpoint_window_spawn received, is_server=%s" % multiplayer.is_server())
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	print("[PvP] Server processing weakpoint request from peer %d" % sender_id)
	# Broadcast to all peers
	_sync_pvp_weakpoint_window_spawn.rpc(sender_id)

@rpc("any_peer", "call_local", "reliable")
func _sync_pvp_weakpoint_window_spawn(target_peer_id: int) -> void:
	"""Server broadcasts weakpoint window spawn to all peers.
	This RPC is called on the target player's node, so we spawn directly on self."""
	print("[PvP] _sync_pvp_weakpoint_window_spawn received for peer %d on node %s" % [target_peer_id, name])

	# Verify this is the correct player node (the one that should get weakpoints)
	var my_authority = get_multiplayer_authority()
	if my_authority != target_peer_id:
		print("[PvP] Skipping - this node (authority %d) is not target peer %d" % [my_authority, target_peer_id])
		return

	print("[PvP] Spawning weakpoints on self: %s" % name)
	_create_pvp_weakpoints_local()

func _create_pvp_weakpoints_local() -> void:
	"""Create actual Weakpoint instances on this player (called on all peers)"""
	if pvp_weakpoint_active:
		return  # Already has active window

	pvp_weakpoint_active = true
	pvp_weakpoints_destroyed = 0
	pvp_weakpoints_spawned = 0
	pvp_weakpoints.clear()

	# Calculate weakpoint count based on level (matches PvE scaling)
	var weakpoint_count = _get_pvp_weakpoint_count()

	# Spawn weakpoints at different positions on the player
	var positions = _get_pvp_weakpoint_positions()

	for i in range(min(weakpoint_count, positions.size())):
		var wp = _spawn_single_pvp_weakpoint(positions[i])
		if wp:
			pvp_weakpoints.append(wp)
			pvp_weakpoints_spawned += 1

	# Start window timer (only on authority)
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var my_authority = get_multiplayer_authority()
	if my_peer_id == my_authority:
		if pvp_weakpoint_timer and is_instance_valid(pvp_weakpoint_timer):
			pvp_weakpoint_timer.queue_free()
		pvp_weakpoint_timer = Timer.new()
		pvp_weakpoint_timer.wait_time = PVP_WEAKPOINT_DURATION
		pvp_weakpoint_timer.one_shot = true
		pvp_weakpoint_timer.timeout.connect(_on_pvp_weakpoint_window_timeout)
		add_child(pvp_weakpoint_timer)
		pvp_weakpoint_timer.start()

	print("🎯 PvP Weakpoint window spawned with %d weakpoints (level %d)!" % [pvp_weakpoints.size(), CharacterStats.level])

func _get_pvp_weakpoint_count() -> int:
	"""Calculate number of PvP weakpoints based on player level (matches PvE scaling)"""
	var level = CharacterStats.level
	if level >= 20:
		return 3  # Level 20+: 3 weakpoints
	elif level >= 11:
		return 2  # Level 11-19: 2 weakpoints
	else:
		return 1  # Level 1-10: 1 weakpoint

func _get_pvp_weakpoint_positions() -> Array:
	"""Get spawn positions for PvP weakpoints on the player body"""
	# Positions relative to player center - spread out for easier clicking
	# At 0.5 scale, visual radius is ~9px, so positions need 20+ pixel separation
	var positions = [
		Vector2(-18, -24),   # Left side, mid torso
		Vector2(18, -24),    # Right side, mid torso
		Vector2(0, -44),     # Head/top (well separated from torso positions)
	]
	# Shuffle to add variety
	positions.shuffle()
	return positions

func _spawn_single_pvp_weakpoint(local_pos: Vector2) -> Node:
	"""Spawn a single Weakpoint instance at the given local position"""
	var WeakpointScene = preload("res://scripts/enemies/weakpoint.gd")
	var wp = Weakpoint.new()
	wp.color_theme = "pvp"  # Use purple PvP theme
	wp.max_hits = randi_range(2, 3)  # Faster to clear than PvE (2-3 clicks instead of 3-5)
	wp.scale = Vector2(PVP_WEAKPOINT_SCALE, PVP_WEAKPOINT_SCALE)  # Smaller for player hitbox
	wp.position = local_pos
	wp.z_index = 100  # Above player sprite

	# Set damage per hit for tracking
	wp.damage_per_hit = PVP_WEAKPOINT_DAMAGE_PER_HIT

	# Connect signals for tracking
	wp.weakpoint_destroyed.connect(_on_pvp_weakpoint_destroyed.bind(wp))

	add_child(wp)

	# Debug: verify weakpoint is configured for input
	print("[PvP] Spawned weakpoint at %s, input_pickable=%s, z_index=%d, scale=%s" % [
		local_pos, wp.input_pickable, wp.z_index, wp.scale
	])

	return wp

func _on_pvp_weakpoint_destroyed(weakpoint: Node) -> void:
	"""Called when a PvP weakpoint is cleared by clicking"""
	if not pvp_weakpoint_active:
		return

	pvp_weakpoints_destroyed += 1

	# Remove from array
	var idx = pvp_weakpoints.find(weakpoint)
	if idx >= 0:
		pvp_weakpoints.remove_at(idx)

	print("🎯 PvP Weakpoint destroyed! (%d/%d)" % [pvp_weakpoints_destroyed, pvp_weakpoints_spawned])

	# Check if all weakpoints cleared
	if pvp_weakpoints.size() == 0:
		_on_pvp_weakpoints_all_cleared()

func _on_pvp_weakpoints_all_cleared() -> void:
	"""Called when all weakpoints in the window are cleared"""
	print("🎯 ALL PvP Weakpoints cleared! Window complete!")

	# Stop timer early
	if pvp_weakpoint_timer and is_instance_valid(pvp_weakpoint_timer):
		pvp_weakpoint_timer.stop()
		pvp_weakpoint_timer.queue_free()
		pvp_weakpoint_timer = null

	pvp_weakpoint_active = false

	# Play success sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_weakpoint_destroyed_sound"):
		sound_manager.play_weakpoint_destroyed_sound(global_position, -6.0)

func _on_pvp_weakpoint_window_timeout() -> void:
	"""Weakpoint window expired - cleanup remaining weakpoints"""
	if not pvp_weakpoint_active:
		return

	print("🎯 PvP Weakpoint window expired (%d/%d cleared)" % [pvp_weakpoints_destroyed, pvp_weakpoints_spawned])

	# Force-destroy any remaining weakpoints
	for wp in pvp_weakpoints:
		if is_instance_valid(wp):
			wp.queue_free()
	pvp_weakpoints.clear()

	pvp_weakpoint_active = false

	if pvp_weakpoint_timer and is_instance_valid(pvp_weakpoint_timer):
		pvp_weakpoint_timer.queue_free()
		pvp_weakpoint_timer = null

func clear_pvp_weakpoint_window() -> void:
	"""Remove any active PvP weakpoint window (called on duel end)"""
	pvp_weakpoint_active = false
	pvp_weakpoints_destroyed = 0

	# Clear all weakpoints
	for wp in pvp_weakpoints:
		if is_instance_valid(wp):
			wp.queue_free()
	pvp_weakpoints.clear()

	# Stop timer
	if pvp_weakpoint_timer and is_instance_valid(pvp_weakpoint_timer):
		pvp_weakpoint_timer.stop()
		pvp_weakpoint_timer.queue_free()
		pvp_weakpoint_timer = null

func get_pvp_weakpoint_area() -> Area2D:
	"""Get the first active PvP weakpoint area (for ranged weapon hit detection)"""
	for wp in pvp_weakpoints:
		if is_instance_valid(wp):
			return wp  # Weakpoint extends Area2D
	return null

func has_active_pvp_weakpoints() -> bool:
	"""Check if this player has active PvP weakpoints"""
	return pvp_weakpoint_active and pvp_weakpoints.size() > 0

func process_passive_healing(delta: float) -> void:
	"""Handle out-of-combat passive health regeneration"""
	# Don't process if dead
	if is_dead:
		return

	# Always track time since last damage (for combat state)
	time_since_last_damage += delta

	# Check if player has been out of combat long enough
	if time_since_last_damage >= out_of_combat_delay:
		# Player is out of combat
		if is_in_combat:
			is_in_combat = false
			print("✨ Out of combat")

	# Don't heal if already at full health
	if current_health >= max_health:
		return

	# Don't heal if still in combat (must wait out_of_combat_delay after last damage)
	if time_since_last_damage < out_of_combat_delay:
		passive_heal_timer = 0.0  # Reset heal timer while in combat
		return

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
			if portrait_hud and portrait_hud.has_method("update_health"):
				portrait_hud.update_health(current_health, max_health)

			# Only show combat text for significant heals (5%+ of max HP) to reduce spam
			# This means text appears roughly every 2.5 seconds instead of every 1 second
			if actual_heal >= max_health * 0.05:
				CombatText.create_heal(actual_heal, global_position, get_tree().root, attack_direction)

			# Quiet log for passive healing
			if current_health >= max_health:
				print("💚 Passive healing complete (%.1f / %.1f)" % [current_health, max_health])

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
	if DEBUG_EQUIP:
		print("[Equip] CREATE_PLAYER_SPRITE called on: %s (authority=%d, is_local=%s)" % [name, get_multiplayer_authority(), is_multiplayer_authority()])
		print("  Children BEFORE cleanup:")
		for child in get_children():
			var type_name = child.get_class()
			var visible_str = " (visible)" if child.get("visible") == true else " (hidden)" if child.get("visible") == false else ""
			print("    - %s [%s]%s" % [child.name, type_name, visible_str])

	# Remove old sprites if they exist (for weapon equip/unequip)
	var old_character_sprite = get_node_or_null("CharacterSprite")
	if old_character_sprite:
		remove_child(old_character_sprite)
		old_character_sprite.queue_free()

	var old_shadow = get_node_or_null("Shadow")
	if old_shadow:
		remove_child(old_shadow)
		old_shadow.queue_free()

	# Hide AND remove the placeholder Sprite2D from the scene
	var placeholder_sprite = get_node_or_null("Sprite2D")
	if placeholder_sprite:
		placeholder_sprite.visible = false
		remove_child(placeholder_sprite)
		placeholder_sprite.queue_free()

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
	# Staff, spear and trident use thrust animation
	# Bow and crossbow use shoot animation
	# All other weapons use slash
	var uses_thrust = false
	var uses_shoot = false
	var thrust_weapons = ["staff", "spear", "trident"]
	var bow_weapons = ["bow", "crossbow"]
	if is_local and CharacterStats.equipped_weapon:
		uses_thrust = CharacterStats.equipped_weapon.weapon_type in thrust_weapons
		uses_shoot = CharacterStats.equipped_weapon.weapon_type in bow_weapons
	elif not is_local:
		if remote_weapon_type in thrust_weapons:
			uses_thrust = true
		elif remote_weapon_type in bow_weapons:
			uses_shoot = true

	var attack_anim_name = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
	var attack_tex_path = "res://assets/characters/" + body_type + "/standard/" + attack_anim_name + ".png"
	var slash_tex: Texture2D = null
	if ResourceLoader.exists(attack_tex_path):
		slash_tex = load(attack_tex_path)
		# Validate thrust texture has correct dimensions (512px = 8 frames)
		# If wrong dimensions, fall back to slash to ensure animation works
		if uses_thrust and slash_tex:
			var tex_width = slash_tex.get_width()
			if tex_width != 512:
				print("[Equip] WARNING: thrust.png has wrong dimensions (%d px, expected 512). Falling back to slash." % tex_width)
				attack_anim_name = "slash"
				uses_thrust = false
				slash_tex = load("res://assets/characters/" + body_type + "/standard/slash.png")
	elif uses_shoot:
		# Bow/crossbow fallback: try thrust (8 frames, closer to shoot's 13) before slash (6 frames)
		var thrust_path = "res://assets/characters/" + body_type + "/standard/thrust.png"
		if ResourceLoader.exists(thrust_path):
			slash_tex = load(thrust_path)
		else:
			slash_tex = load("res://assets/characters/" + body_type + "/standard/slash.png")
	else:
		slash_tex = load("res://assets/characters/" + body_type + "/standard/slash.png")

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

	# Load base head textures (separate head layer for face details)
	var base_head_walk_tex = null
	var base_head_slash_tex = null
	var head_path = "res://assets/characters/head_female/standard/" if selected_gender == Gender.FEMALE else "res://assets/characters/head_male/standard/"
	if ResourceLoader.exists(head_path + "walk.png"):
		base_head_walk_tex = load(head_path + "walk.png")
	var head_attack_path = head_path + attack_anim_name + ".png"
	if ResourceLoader.exists(head_attack_path):
		base_head_slash_tex = load(head_attack_path)
	elif uses_shoot:
		# For bow weapons without head shoot animation, use walk for static head during shoot
		base_head_slash_tex = base_head_walk_tex
	elif ResourceLoader.exists(head_path + "slash.png"):
		base_head_slash_tex = load(head_path + "slash.png")

	# Load weapon textures based on equipped weapon
	var weapon_slash_tex = null
	var weapon_slash2_tex = null  # Multi-slash variant 2
	var weapon_slash3_tex = null  # Multi-slash variant 3
	var weapon_walk_tex = null
	var weapon_type = "unarmed"  # Default to unarmed when no weapon equipped
	var effective_weapon_type = ""

	# Debug: Check if equipped weapon is forged
	var is_forged_weapon = false
	var forged_weapon_data: Dictionary = {}

	if is_local and CharacterStats.equipped_weapon:
		effective_weapon_type = CharacterStats.equipped_weapon.weapon_type
		# Check if we have forged weapon data stored
		if CharacterStats.has_method("get_equipped_weapon_data"):
			forged_weapon_data = CharacterStats.get_equipped_weapon_data()
		is_forged_weapon = forged_weapon_data.get("is_forged", false)

		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip] ═══════════════════════════════════════")
			print("[ForgedEquip] Equipped weapon: %s" % CharacterStats.equipped_weapon.weapon_name)
			print("[ForgedEquip]   weapon_type: %s" % effective_weapon_type)
			print("[ForgedEquip]   is_forged: %s" % is_forged_weapon)
			if is_forged_weapon:
				print("[ForgedEquip]   glow_color: %s" % forged_weapon_data.get("glow_color", "none"))
				print("[ForgedEquip]   effect_name: %s" % forged_weapon_data.get("effect_name", "none"))
				print("[ForgedEquip]   effect_intensity: %s" % forged_weapon_data.get("effect_intensity", 0))

	elif not is_local and remote_weapon_type != "":
		effective_weapon_type = remote_weapon_type
		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip] Remote player weapon_type: %s" % effective_weapon_type)

	if effective_weapon_type != "":
		weapon_type = effective_weapon_type
		var weapon_path = "res://assets/equipment/weapons/" + weapon_type + "/"

		# For forged weapons, check if pre-tinted sprites exist in forged folder
		var forged_item_id = forged_weapon_data.get("item_id", "")
		var forged_weapon_path = ""
		if is_forged_weapon and forged_item_id != "":
			forged_weapon_path = "res://assets/equipment/forged/weapons/" + forged_item_id + "/"
			if DEBUG_FORGED_EQUIP:
				print("[ForgedEquip]   Forged item_id: %s" % forged_item_id)
				print("[ForgedEquip]   Forged weapon path: %s" % forged_weapon_path)

		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip]   Base weapon path: %s" % weapon_path)

		# Check if weapon folder has sprites, use fallback if not
		var animation_type = weapon_type  # The actual type used for animations
		var has_weapon_sprites = ResourceLoader.exists(weapon_path + "slash.png") or \
								 ResourceLoader.exists(weapon_path + "thrust.png") or \
								 ResourceLoader.exists(weapon_path + "thrust_oversize.png") or \
								 ResourceLoader.exists(weapon_path + "shoot.png")

		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip]   Has weapon sprites at path: %s" % has_weapon_sprites)
			print("[ForgedEquip]     Checked: %s/slash.png = %s" % [weapon_path, ResourceLoader.exists(weapon_path + "slash.png")])
			print("[ForgedEquip]     Checked: %s/thrust.png = %s" % [weapon_path, ResourceLoader.exists(weapon_path + "thrust.png")])
			print("[ForgedEquip]     Checked: %s/thrust_oversize.png = %s" % [weapon_path, ResourceLoader.exists(weapon_path + "thrust_oversize.png")])

		if not has_weapon_sprites:
			# Try fallback weapon type
			if WEAPON_TYPE_FALLBACKS.has(weapon_type):
				animation_type = WEAPON_TYPE_FALLBACKS[weapon_type]
				weapon_path = "res://assets/equipment/weapons/" + animation_type + "/"
				if DEBUG_EQUIP or DEBUG_FORGED_EQUIP:
					print("[Equip] Weapon type '%s' not found, using fallback: %s" % [weapon_type, animation_type])
			else:
				if DEBUG_FORGED_EQUIP:
					print("[ForgedEquip]   No fallback defined for weapon_type: %s" % weapon_type)

		# Try to load weapon sprites
		# For forged weapons, prefer pre-tinted sprites from forged folder
		# Staff uses thrust_oversize animation, spear uses thrust, gun uses walk only, others use slash
		if animation_type == "gun":
			# Guns use shoot.png with muzzle flash for attack animation
			# Check forged folder first for pre-tinted sprites
			if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "shoot.png"):
				weapon_slash_tex = load(forged_weapon_path + "shoot.png")
				if DEBUG_FORGED_EQUIP:
					print("[ForgedEquip]   Loaded tinted shoot.png from forged folder")
			elif ResourceLoader.exists(weapon_path + "shoot.png"):
				weapon_slash_tex = load(weapon_path + "shoot.png")
		elif animation_type == "bow" or animation_type == "crossbow":
			# Bows use shoot.png (13 frames) for attack animation
			if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "shoot.png"):
				weapon_slash_tex = load(forged_weapon_path + "shoot.png")
				if DEBUG_FORGED_EQUIP:
					print("[ForgedEquip]   Loaded tinted shoot.png from forged folder (bow)")
			elif ResourceLoader.exists(weapon_path + "shoot.png"):
				weapon_slash_tex = load(weapon_path + "shoot.png")
		elif animation_type == "staff":
			# Check forged folder first
			if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "thrust_oversize.png"):
				weapon_slash_tex = load(forged_weapon_path + "thrust_oversize.png")
			elif ResourceLoader.exists(weapon_path + "thrust_oversize.png"):
				weapon_slash_tex = load(weapon_path + "thrust_oversize.png")
		elif animation_type == "spear":
			# Check forged folder first
			if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "thrust.png"):
				weapon_slash_tex = load(forged_weapon_path + "thrust.png")
			elif ResourceLoader.exists(weapon_path + "thrust.png"):
				weapon_slash_tex = load(weapon_path + "thrust.png")
		else:
			# Check forged folder first for slash animation
			if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "slash.png"):
				weapon_slash_tex = load(forged_weapon_path + "slash.png")
				if DEBUG_FORGED_EQUIP:
					print("[ForgedEquip]   Loaded tinted slash.png from forged folder")
			elif ResourceLoader.exists(weapon_path + "slash.png"):
				weapon_slash_tex = load(weapon_path + "slash.png")

		# Load additional slash variants for multi-slash weapons (slash2, slash3)
		# Check forged folder first
		if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "slash2.png"):
			weapon_slash2_tex = load(forged_weapon_path + "slash2.png")
			if DEBUG_EQUIP:
				print("[Equip] Multi-slash weapon: loaded slash2.png from forged folder")
		elif ResourceLoader.exists(weapon_path + "slash2.png"):
			weapon_slash2_tex = load(weapon_path + "slash2.png")
			if DEBUG_EQUIP:
				print("[Equip] Multi-slash weapon: loaded slash2.png")
		if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "slash3.png"):
			weapon_slash3_tex = load(forged_weapon_path + "slash3.png")
			if DEBUG_EQUIP:
				print("[Equip] Multi-slash weapon: loaded slash3.png from forged folder")
		elif ResourceLoader.exists(weapon_path + "slash3.png"):
			weapon_slash3_tex = load(weapon_path + "slash3.png")
			if DEBUG_EQUIP:
				print("[Equip] Multi-slash weapon: loaded slash3.png")

		# Load walk texture - check forged folder first for pre-tinted sprites
		if forged_weapon_path != "" and ResourceLoader.exists(forged_weapon_path + "walk.png"):
			weapon_walk_tex = load(forged_weapon_path + "walk.png")
			if DEBUG_FORGED_EQUIP:
				print("[ForgedEquip]   Loaded tinted walk.png from forged folder")
		elif ResourceLoader.exists(weapon_path + "walk.png"):
			weapon_walk_tex = load(weapon_path + "walk.png")

		if DEBUG_EQUIP:
			print("[Equip] Loading weapon sprites: %s → %s (attack=%s, walk=%s)" % [weapon_type, animation_type, "OK" if weapon_slash_tex else "MISSING", "OK" if weapon_walk_tex else "MISSING"])

		# Apply forged weapon visual effects (glow, particles, trails)
		if is_forged_weapon:
			_apply_forged_weapon_effects(forged_weapon_data)
	else:
		if DEBUG_EQUIP:
			print("[Equip] No weapon equipped - unarmed")

	# Load armor textures based on equipped armor (5 layers: boots, pants, shirt, arms, head)
	# Use shoot/thrust/slash suffix based on weapon type
	var attack_suffix = "_shoot" if uses_shoot else ("_thrust" if uses_thrust else "_slash")
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

	# Check for equipped boots (feet) - support forged armor
	var feet_sprite_name = ""
	var is_forged_feet = false
	var forged_feet_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("feet") and CharacterStats.equipped_armor["feet"] != null:
		var boots_armor = CharacterStats.equipped_armor["feet"]
		feet_sprite_name = boots_armor.get("sprite_name", "")
		is_forged_feet = boots_armor.get("is_forged", false)
		if is_forged_feet:
			forged_feet_data = boots_armor
	elif not is_local and remote_feet_sprite != "":
		feet_sprite_name = remote_feet_sprite

	# Load forged feet armor from ForgeItemDB
	if is_forged_feet and forged_feet_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_feet_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load feet sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				boots_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				boots_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				boots_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged feet armor: %s" % forged_item_id)
	elif feet_sprite_name != "":
		# Standard (non-forged) feet armor loading
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

	# Check for equipped leg armor (pants) - support forged armor
	var legs_sprite_name = ""
	var is_forged_legs = false
	var forged_legs_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("legs") and CharacterStats.equipped_armor["legs"] != null:
		var leg_armor = CharacterStats.equipped_armor["legs"]
		legs_sprite_name = leg_armor.get("sprite_name", "green_pants")
		is_forged_legs = leg_armor.get("is_forged", false)
		if is_forged_legs:
			forged_legs_data = leg_armor
	elif not is_local and remote_legs_sprite != "":
		legs_sprite_name = remote_legs_sprite

	# Load forged legs armor from ForgeItemDB
	if is_forged_legs and forged_legs_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_legs_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load legs sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				pants_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				pants_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				pants_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged legs armor: %s" % forged_item_id)
	elif legs_sprite_name != "":
		# Standard (non-forged) legs armor loading
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

	# Check for equipped chest armor (shirt) - support forged armor
	var chest_sprite_name = ""
	var is_forged_chest = false
	var forged_chest_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("chest") and CharacterStats.equipped_armor["chest"] != null:
		var chest_armor = CharacterStats.equipped_armor["chest"]
		chest_sprite_name = chest_armor.get("sprite_name", "white_shirt")
		is_forged_chest = chest_armor.get("is_forged", false)
		if is_forged_chest:
			forged_chest_data = chest_armor
	elif not is_local and remote_chest_sprite != "":
		chest_sprite_name = remote_chest_sprite

	# Load forged chest armor from ForgeItemDB
	if is_forged_chest and forged_chest_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_chest_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load chest sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				shirt_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				shirt_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				shirt_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged chest armor: %s" % forged_item_id)
	elif chest_sprite_name != "":
		# Standard (non-forged) chest armor loading
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
			if DEBUG_EQUIP:
				print("[Equip] Loaded chest armor %s attack: %s%s%s.png" % [attack_anim_name, shirt_path, chest_sprite_name, attack_suffix])
		elif ResourceLoader.exists(shirt_path + chest_sprite_name + "_slash.png"):
			shirt_slash_tex = load(shirt_path + chest_sprite_name + "_slash.png")
			if DEBUG_EQUIP:
				print("[Equip] Loaded chest armor slash (fallback): %s%s_slash.png" % [shirt_path, chest_sprite_name])

	# Check for equipped arm armor - support forged armor
	var arms_sprite_name = ""
	var is_forged_arms = false
	var forged_arms_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("arms") and CharacterStats.equipped_armor["arms"] != null:
		var arm_armor = CharacterStats.equipped_armor["arms"]
		arms_sprite_name = arm_armor.get("sprite_name", "")
		is_forged_arms = arm_armor.get("is_forged", false)
		if is_forged_arms:
			forged_arms_data = arm_armor
	elif not is_local and remote_arms_sprite != "":
		arms_sprite_name = remote_arms_sprite

	# Load forged arms armor from ForgeItemDB
	if is_forged_arms and forged_arms_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_arms_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load arms sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				arms_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				arms_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				arms_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged arms armor: %s" % forged_item_id)
	elif arms_sprite_name != "":
		# Standard (non-forged) arms armor loading
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

	# Check for equipped hand armor (gloves) - support forged armor
	var hands_sprite_name = ""
	var is_forged_hands = false
	var forged_hands_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("hands") and CharacterStats.equipped_armor["hands"] != null:
		var hand_armor = CharacterStats.equipped_armor["hands"]
		hands_sprite_name = hand_armor.get("sprite_name", "")
		is_forged_hands = hand_armor.get("is_forged", false)
		if is_forged_hands:
			forged_hands_data = hand_armor
	elif not is_local and remote_hands_sprite != "":
		hands_sprite_name = remote_hands_sprite

	# Load forged hands armor from ForgeItemDB
	if is_forged_hands and forged_hands_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_hands_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load hands sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				hands_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				hands_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				hands_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged hands armor: %s" % forged_item_id)
	elif hands_sprite_name != "":
		# Standard (non-forged) hands armor loading
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

	# Check for equipped head armor (supports forged armor with visual overrides)
	var head_sprite_name = ""
	var is_forged_head = false
	var forged_head_data: Dictionary = {}
	if is_local and CharacterStats.equipped_armor.has("head") and CharacterStats.equipped_armor["head"] != null:
		var head_armor = CharacterStats.equipped_armor["head"]
		head_sprite_name = head_armor.get("sprite_name", "")
		is_forged_head = head_armor.get("is_forged", false)
		if is_forged_head:
			forged_head_data = head_armor
	elif not is_local and remote_head_sprite != "":
		head_sprite_name = remote_head_sprite

	# Load forged head armor from ForgeItemDB (with visual override support)
	if is_forged_head and forged_head_data.get("forged_item_id", "") != "":
		var forged_item_id = forged_head_data.get("forged_item_id", "")
		var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
		if forged_db_data and forged_db_data.has("sprites"):
			var sprites = forged_db_data["sprites"]
			# Load head sprites from forged item
			if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
				head_walk_tex = load(sprites["walk"])
			# Pick shoot/thrust/slash based on weapon type
			var attack_key = "shoot" if uses_shoot else ("thrust" if uses_thrust else "slash")
			if sprites.has(attack_key) and ResourceLoader.exists(sprites[attack_key]):
				head_slash_tex = load(sprites[attack_key])
			elif sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
				head_slash_tex = load(sprites["slash"])

			if DEBUG_EQUIP:
				print("[ForgedArmor] Loaded forged head armor: %s" % forged_item_id)

			# Check for visual_override_slots (e.g., robes that override chest/legs)
			if forged_db_data.has("visual_override_slots"):
				var overrides = forged_db_data["visual_override_slots"]

				# Override chest (shirt) sprites if specified
				if overrides.has("chest"):
					var chest_override = overrides["chest"]
					if chest_override.has("walk") and ResourceLoader.exists(chest_override["walk"]):
						shirt_walk_tex = load(chest_override["walk"])
					if chest_override.has(attack_key) and ResourceLoader.exists(chest_override[attack_key]):
						shirt_slash_tex = load(chest_override[attack_key])
					elif chest_override.has("slash") and ResourceLoader.exists(chest_override["slash"]):
						shirt_slash_tex = load(chest_override["slash"])
					if DEBUG_EQUIP:
						print("[ForgedArmor]   Visual override: chest -> %s" % chest_override.get("walk", ""))

				# Override legs (pants) sprites if specified
				if overrides.has("legs"):
					var legs_override = overrides["legs"]
					if legs_override.has("walk") and ResourceLoader.exists(legs_override["walk"]):
						pants_walk_tex = load(legs_override["walk"])
					if legs_override.has(attack_key) and ResourceLoader.exists(legs_override[attack_key]):
						pants_slash_tex = load(legs_override[attack_key])
					elif legs_override.has("slash") and ResourceLoader.exists(legs_override["slash"]):
						pants_slash_tex = load(legs_override["slash"])
					if DEBUG_EQUIP:
						print("[ForgedArmor]   Visual override: legs -> %s" % legs_override.get("walk", ""))
	elif head_sprite_name != "":
		# Standard (non-forged) head armor loading
		# Try gender-specific path first, then fall back to gender-neutral
		var head_armor_path = "res://assets/characters/head_female_armor/" if selected_gender == Gender.FEMALE else "res://assets/characters/head/"
		if not ResourceLoader.exists(head_armor_path + head_sprite_name + "_walk.png"):
			head_armor_path = "res://assets/characters/head/"

		if ResourceLoader.exists(head_armor_path + head_sprite_name + "_walk.png"):
			head_walk_tex = load(head_armor_path + head_sprite_name + "_walk.png")
		# Try thrust first if using staff, fall back to slash
		if ResourceLoader.exists(head_armor_path + head_sprite_name + attack_suffix + ".png"):
			head_slash_tex = load(head_armor_path + head_sprite_name + attack_suffix + ".png")
			if DEBUG_EQUIP:
				print("[Equip] Loaded head armor %s attack: %s%s%s.png" % [attack_anim_name, head_armor_path, head_sprite_name, attack_suffix])
		elif ResourceLoader.exists(head_armor_path + head_sprite_name + "_slash.png"):
			head_slash_tex = load(head_armor_path + head_sprite_name + "_slash.png")
			if DEBUG_EQUIP:
				print("[Equip] Loaded head armor slash (fallback): %s_slash.png" % head_sprite_name)

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

	# Load shield textures if offhand has a shield equipped
	var shield_walk_tex = null
	var shield_slash_tex = null
	if is_local and CharacterStats.equipped_armor.has("offhand") and CharacterStats.equipped_armor["offhand"] != null:
		var offhand_item = CharacterStats.equipped_armor["offhand"]
		var shield_sprite_name = offhand_item.get("sprite_name", "")
		var is_forged_shield = offhand_item.get("is_forged", false)

		if is_forged_shield and offhand_item.get("forged_item_id", "") != "":
			# Load forged shield sprites
			var forged_item_id = offhand_item.get("forged_item_id", "")
			var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
			if forged_db_data and forged_db_data.has("sprites"):
				var sprites = forged_db_data["sprites"]
				if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
					shield_walk_tex = load(sprites["walk"])
				if sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
					shield_slash_tex = load(sprites["slash"])
				if DEBUG_EQUIP:
					print("[Equip] Loaded forged shield: %s" % forged_item_id)
		elif shield_sprite_name != "":
			# Load standard shield sprites
			var shield_path = "res://assets/equipment/shields/" + shield_sprite_name + "/"
			if ResourceLoader.exists(shield_path + "walk.png"):
				shield_walk_tex = load(shield_path + "walk.png")
			if ResourceLoader.exists(shield_path + "slash.png"):
				shield_slash_tex = load(shield_path + "slash.png")
			if DEBUG_EQUIP:
				print("[Equip] Loaded shield sprites from: %s" % shield_path)

	# Setup sprite with shadow + all armor layers + base_head + hair + shield
	var is_female = (selected_gender == Gender.FEMALE)
	character_sprite.setup_lpc_sprite(walk_tex, slash_tex, hurt_tex, shadow_walk_tex, shadow_slash_tex, base_head_walk_tex, base_head_slash_tex, boots_walk_tex, boots_slash_tex, pants_walk_tex, pants_slash_tex, shirt_walk_tex, shirt_slash_tex, arms_walk_tex, arms_slash_tex, hands_walk_tex, hands_slash_tex, head_walk_tex, head_slash_tex, hair_walk_tex, hair_slash_tex, weapon_slash_tex, weapon_walk_tex, weapon_type, is_female, weapon_slash2_tex, weapon_slash3_tex, shield_walk_tex, shield_slash_tex)

	# Gun pose body swap: If weapon is a gun type, load Skorpio body for walk and shoot animations
	# This makes the character use the shooting stance body when walking/shooting with a gun
	var gun_weapon_types = ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"]
	if weapon_type in gun_weapon_types:
		var gun_body_walk_path = "res://assets/characters/body_gun_pose/walk.png"
		var gun_body_shoot_path = "res://assets/characters/body_gun_pose/shoot.png"
		if ResourceLoader.exists(gun_body_walk_path):
			var gun_body_walk_tex = load(gun_body_walk_path)
			var gun_body_shoot_tex = null
			if ResourceLoader.exists(gun_body_shoot_path):
				gun_body_shoot_tex = load(gun_body_shoot_path)
			character_sprite.setup_gun_walk_animations(gun_body_walk_tex, gun_body_shoot_tex)
			if DEBUG_EQUIP:
				print("[Equip] Gun weapon detected - loaded Skorpio gun pose body for walk animations")
				if gun_body_shoot_tex:
					print("[Equip] Gun shoot animation also loaded")

	# Cape/back slot: Load cape sprites if equipped
	_setup_equipped_cape(character_sprite)

	add_child(character_sprite)

	# Connect animation signals
	if not character_sprite.animation_finished.is_connected(_on_attack_animation_finished):
		character_sprite.animation_finished.connect(_on_attack_animation_finished)

	# Connect frame_changed signal for footsteps
	if not character_sprite.frame_changed.is_connected(_on_sprite_frame_changed):
		character_sprite.frame_changed.connect(_on_sprite_frame_changed)

	if DEBUG_EQUIP:
		# List ALL player children after sprite creation
		print("[Equip] Player children AFTER sprite creation:")
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
		print("[Equip] CREATE_PLAYER_SPRITE complete for: %s" % name)

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
	if DEBUG_EQUIP:
		print("[Equip] Syncing appearance to network: %s" % str(appearance))
	rpc("_receive_appearance_update", appearance["gender"], appearance["weapon_type"],
		appearance["feet_sprite"], appearance["legs_sprite"], appearance["chest_sprite"],
		appearance["arms_sprite"], appearance["hands_sprite"], appearance["head_sprite"])

func _broadcast_initial_appearance():
	"""Broadcast appearance after initial spawn (called deferred from _ready)"""
	# Wait a couple frames to ensure multiplayer is fully set up
	await get_tree().process_frame
	await get_tree().process_frame

	if multiplayer.has_multiplayer_peer():
		if DEBUG_EQUIP:
			print("[Equip] Broadcasting initial appearance for local player")
		_sync_appearance_to_network()

@rpc("any_peer", "call_remote", "reliable")
func _receive_appearance_update(gender_int: int, weapon_type: String, feet_sprite: String, legs_sprite: String, chest_sprite: String, arms_sprite: String, hands_sprite: String, head_sprite: String):
	"""Receive appearance update from another player"""
	if DEBUG_EQUIP:
		print("[Equip] Received appearance for player %s: gender=%d, weapon=%s" % [name, gender_int, weapon_type])

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

func get_appearance_data() -> Dictionary:
	"""Get current appearance data for network sync"""
	var weapon_type = ""
	var feet_sprite = ""
	var legs_sprite = ""
	var chest_sprite = ""
	var arms_sprite = ""
	var hands_sprite = ""
	var head_sprite = ""

	# Forged item IDs for armor pieces
	var feet_forged_id = ""
	var legs_forged_id = ""
	var chest_forged_id = ""
	var arms_forged_id = ""
	var hands_forged_id = ""
	var head_forged_id = ""

	# Get from CharacterStats if this is the local player
	if is_multiplayer_authority():
		if CharacterStats.equipped_weapon:
			weapon_type = CharacterStats.equipped_weapon.weapon_type
		if CharacterStats.equipped_armor.get("feet"):
			var feet_armor = CharacterStats.equipped_armor["feet"]
			feet_sprite = feet_armor.get("sprite_name", "")
			if feet_armor.get("is_forged", false):
				feet_forged_id = feet_armor.get("forged_item_id", "")
		if CharacterStats.equipped_armor.get("legs"):
			var legs_armor = CharacterStats.equipped_armor["legs"]
			legs_sprite = legs_armor.get("sprite_name", "")
			if legs_armor.get("is_forged", false):
				legs_forged_id = legs_armor.get("forged_item_id", "")
		if CharacterStats.equipped_armor.get("chest"):
			var chest_armor = CharacterStats.equipped_armor["chest"]
			chest_sprite = chest_armor.get("sprite_name", "")
			if chest_armor.get("is_forged", false):
				chest_forged_id = chest_armor.get("forged_item_id", "")
		if CharacterStats.equipped_armor.get("arms"):
			var arms_armor = CharacterStats.equipped_armor["arms"]
			arms_sprite = arms_armor.get("sprite_name", "")
			if arms_armor.get("is_forged", false):
				arms_forged_id = arms_armor.get("forged_item_id", "")
		if CharacterStats.equipped_armor.get("hands"):
			var hands_armor = CharacterStats.equipped_armor["hands"]
			hands_sprite = hands_armor.get("sprite_name", "")
			if hands_armor.get("is_forged", false):
				hands_forged_id = hands_armor.get("forged_item_id", "")
		if CharacterStats.equipped_armor.get("head"):
			var head_armor = CharacterStats.equipped_armor["head"]
			head_sprite = head_armor.get("sprite_name", "")
			if head_armor.get("is_forged", false):
				head_forged_id = head_armor.get("forged_item_id", "")
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
		"head_sprite": head_sprite,
		"feet_forged_id": feet_forged_id,
		"legs_forged_id": legs_forged_id,
		"chest_forged_id": chest_forged_id,
		"arms_forged_id": arms_forged_id,
		"hands_forged_id": hands_forged_id,
		"head_forged_id": head_forged_id
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

# ═══════════════════════════════════════════════════════════════════════════
# EQUIPMENT INSPECTION RPC
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_equipment_for_inspection(requester_id: int) -> void:
	"""Another player is requesting to inspect our equipment"""
	# Only respond if we're the authority for this player
	if not is_multiplayer_authority():
		return

	# Gather equipment data
	var equipment_data = _get_full_equipment_data()

	# Send back to requester
	rpc_id(requester_id, "_receive_equipment_inspection", equipment_data)

@rpc("any_peer", "call_local", "reliable")
func _receive_equipment_inspection(data: Dictionary) -> void:
	"""Receive equipment inspection data from another player"""
	# Forward to PlayerInspectUI
	if PlayerInspectUI:
		PlayerInspectUI.receive_equipment_data(data)

func _get_full_equipment_data() -> Dictionary:
	"""Get full equipment data for inspection sharing"""
	var player_name = "Player"
	if NetworkManager and NetworkManager.player_name:
		player_name = NetworkManager.player_name

	var level = 1
	if CharacterStats:
		level = CharacterStats.level

	# Get equipped armor snapshot
	var armor_snapshot = {}
	if CharacterStats:
		armor_snapshot = CharacterStats.get_armor_snapshot()

	# Get equipped weapon as dict
	var weapon_dict = {}
	if CharacterStats:
		weapon_dict = CharacterStats.get_weapon_as_dict()

	# Calculate stats
	var attack = 0.0
	var defense = 0
	var health = 100
	if CharacterStats:
		attack = CharacterStats.get_base_damage()
		defense = CharacterStats.get_total_defense()
		health = CharacterStats.get_max_health()

	return {
		"player_name": player_name,
		"level": level,
		"equipped_armor": armor_snapshot,
		"equipped_weapon": weapon_dict,
		"stats": {
			"attack": attack,
			"defense": defense,
			"health": health
		}
	}

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
	"""Update cone visualizer rotation and rebuild if attack_range changed"""
	# Rebuild cone if attack range changed (e.g. weapon swap)
	if cone_visualizer:
		# Check if we need to rebuild by comparing current range
		# The cone was built with attack_range, so rebuild if different
		var cone_half_angle_rad = deg_to_rad(attack_cone_angle / 2.0)
		var expected_outer_point = Vector2(cos(cone_half_angle_rad), sin(cone_half_angle_rad)) * attack_range
		# Get the last point before closing (index 16 since we have 0=center, 1-17=arc, 18=center)
		if cone_visualizer.polygon.size() > 2:
			var actual_point = cone_visualizer.polygon[cone_visualizer.polygon.size() / 2]
			if abs(actual_point.length() - attack_range) > 1.0:  # Range changed significantly
				print("🔄 Rebuilding cone visualizer for new range: %.0f" % attack_range)
				create_cone_visualizer()
				return

	if not cone_visualizer:
		return

	# Hide cone if using ranged weapon
	var is_ranged = CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_ranged_weapon()
	cone_visualizer.visible = not is_ranged

	if is_ranged:
		return  # Don't update rotation if hidden

	# ALWAYS rotate cone to face aim position (mouse or touch)
	var direction_to_aim = GameInput.get_aim_direction()
	cone_visualizer.rotation = direction_to_aim.angle()

	# Color is now constant - no need to update based on enemies

# ============================================
# RANGED WEAPON CIRCLE VISUALIZER
# ============================================

func create_circle_visualizer() -> void:
	"""Create targeting circle for ranged weapons (healing staff, guns, etc.)
	This circle follows the mouse cursor and shows the heal/attack radius.
	- Healing weapons: Large green circle
	- Gun weapons: Small red/orange reticle"""
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

	# Determine radius and color based on weapon type
	var radius = 80.0
	var fill_color = Color(0.4, 1.0, 0.5, 0.04)  # Default: faint green for healing
	var is_precision_weapon = false  # For center dot

	if CharacterStats.equipped_weapon:
		if CharacterStats.equipped_weapon.is_bow_weapon():
			# Bow: Medium amber/brown reticle for arrow targeting
			radius = CharacterStats.equipped_weapon.bow_radius
			fill_color = Color(0.9, 0.6, 0.2, 0.10)  # Amber/brown
			is_precision_weapon = true
		elif CharacterStats.equipped_weapon.is_gun_weapon():
			# Gun: Small red/orange reticle for precision targeting
			radius = CharacterStats.equipped_weapon.gun_radius
			fill_color = Color(1.0, 0.3, 0.2, 0.08)  # Red-orange, slightly more visible
			is_precision_weapon = true
		elif CharacterStats.equipped_weapon.is_healing_weapon():
			# Healing staff: Large green circle
			radius = CharacterStats.equipped_weapon.heal_radius
			fill_color = Color(0.4, 1.0, 0.5, 0.04)  # Faint green

	circle_fill.color = fill_color

	# Create circle points
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	circle_fill.polygon = points
	circle_visualizer.add_child(circle_fill)

	# For precision weapons (guns, bows), add a center dot for aiming
	if is_precision_weapon:
		var center_dot = Polygon2D.new()
		center_dot.name = "CenterDot"
		# Match the weapon's color scheme for the center dot
		if CharacterStats.equipped_weapon.is_bow_weapon():
			center_dot.color = Color(1.0, 0.7, 0.3, 0.20)  # Brighter amber
		else:
			center_dot.color = Color(1.0, 0.4, 0.3, 0.15)  # Red-orange for guns
		var dot_points = PackedVector2Array()
		var dot_radius = 3.0  # Small center dot
		for i in range(16):
			var angle = (float(i) / 16.0) * TAU
			dot_points.append(Vector2(cos(angle), sin(angle)) * dot_radius)
		center_dot.polygon = dot_points
		circle_visualizer.add_child(center_dot)

	# Add to scene tree root so it stays in world space at cursor position
	get_tree().root.add_child(circle_visualizer)
	circle_visualizer.visible = false  # Hidden until we have a ranged weapon

func update_circle_visualizer() -> void:
	"""Update circle visualizer position to follow aim position (mouse or touch)."""
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
		# Position at aim position (touch or mouse)
		circle_visualizer.global_position = GameInput.get_aim_position()

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

func _on_constants_debug_toggled(visible: bool) -> void:
	"""Called when F3 debug display is toggled via Constants"""
	debug_mode = visible
	debug_update_timer = 0.0  # Reset timer
	update_debug_visualization()  # Immediate update

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

	# Draw ranged weapon targeting circle at cursor (WORLD SPACE)
	var parent = get_parent()
	var is_bow = CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_bow_weapon()
	var is_gun = CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_gun_weapon()

	# Leniency: Player's targeting circle is slightly larger than enemy hurtbox
	# This gives visual feedback that you're "close enough" to hit
	const TARGETING_LENIENCY: float = 8.0  # Extra pixels on player reticle

	if parent and (is_gun or is_bow):
		var cursor_pos = get_global_mouse_position()
		var hit_radius = 28.0  # Default
		var circle_color = Color.YELLOW
		var label_text = "GUN"

		if is_bow:
			hit_radius = CharacterStats.equipped_weapon.bow_radius if CharacterStats.equipped_weapon.get("bow_radius") else 32.0
			circle_color = Color.ORANGE
			label_text = "BOW"
		elif is_gun:
			hit_radius = CharacterStats.equipped_weapon.gun_radius if CharacterStats.equipped_weapon.get("gun_radius") else 28.0
			circle_color = Color.YELLOW
			label_text = "GUN"

		# Reticle circle at cursor (with leniency - larger than actual hit area)
		var reticle_debug = Node2D.new()
		reticle_debug.name = label_text + "Debug"
		parent.add_child(reticle_debug)
		world_debug_nodes.append(reticle_debug)

		var reticle = Line2D.new()
		reticle.width = 2.0
		reticle.default_color = circle_color
		var display_radius = hit_radius + TARGETING_LENIENCY
		for i in range(33):
			var angle = (i * TAU) / 32
			reticle.add_point(cursor_pos + Vector2(cos(angle), sin(angle)) * display_radius)
		reticle_debug.add_child(reticle)

	# Draw enemy HIT DETECTION areas in WORLD SPACE (PILL/CAPSULE shapes)
	# This shows EXACTLY where arrows/bullets will register as hits
	if parent:
		var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
		for enemy in enemies:
			if is_instance_valid(enemy):
				# Get enemy capsule hitbox (pill shape from head to toe)
				var capsule = _get_debug_enemy_capsule(enemy)

				var hitbox_marker = Node2D.new()
				hitbox_marker.name = "EnemyHitbox_" + enemy.name
				parent.add_child(hitbox_marker)
				world_debug_nodes.append(hitbox_marker)

				# Draw pill/capsule shape (magenta)
				var pill = _draw_debug_pill(capsule.top, capsule.bottom, capsule.radius, Color.MAGENTA)
				hitbox_marker.add_child(pill)

				# Draw center line of capsule (cyan)
				var center_line = Line2D.new()
				center_line.width = 2.0
				center_line.default_color = Color.CYAN
				center_line.add_point(capsule.top)
				center_line.add_point(capsule.bottom)
				hitbox_marker.add_child(center_line)

				# Cross at capsule center
				var capsule_center = (capsule.top + capsule.bottom) / 2.0
				var cross_h = Line2D.new()
				cross_h.width = 2.0
				cross_h.default_color = Color.CYAN
				cross_h.add_point(capsule_center + Vector2(-8, 0))
				cross_h.add_point(capsule_center + Vector2(8, 0))
				hitbox_marker.add_child(cross_h)

func _get_debug_enemy_capsule(enemy: Node) -> Dictionary:
	"""Get capsule/pill hitbox parameters for debug visualization.
	Must match _get_enemy_capsule_hitbox() in PlayerCombat.gd exactly."""

	# Base dimensions for LPC sprites (64x64 frame, ~32x56 character)
	var base_height = 52.0  # Head to toe coverage
	var base_radius = 14.0  # Half-width of body

	# Get scale factor (for crit window growth)
	var scale_factor = 1.0
	if enemy.get("sprite") and is_instance_valid(enemy.sprite):
		scale_factor = enemy.sprite.scale.y
	elif enemy.get("in_crit_window") and enemy.in_crit_window:
		scale_factor = 1.5  # Default crit window scale

	# Apply scale to dimensions
	# Height scales less aggressively to avoid oversized hitbox during crit window
	var height_scale = 1.0 + (scale_factor - 1.0) * 0.3  # 30% of the scale increase for height
	var height = base_height * height_scale
	var radius = base_radius * scale_factor

	# Calculate capsule position
	var base_pos = enemy.global_position

	# Check for sprite offset
	if enemy.get("sprite") and is_instance_valid(enemy.sprite):
		var sprite = enemy.sprite
		if sprite.position != Vector2.ZERO:
			base_pos = enemy.global_position + sprite.position

	# For LPC sprites: feet are at global_position, head is above
	# Offset 30px south to better align with skeleton sprites
	# Additional 25px south when scaled up (crit window) to match grown sprite
	var south_offset = 30.0
	if scale_factor > 1.1:
		south_offset += 25.0  # Extra offset for scaled enemies
	var capsule_top = base_pos + Vector2(0, -height + 4 + south_offset)
	var capsule_bottom = base_pos + Vector2(0, 4 + south_offset)

	return {
		"top": capsule_top,
		"bottom": capsule_bottom,
		"radius": radius
	}

func _draw_debug_pill(top: Vector2, bottom: Vector2, radius: float, color: Color) -> Line2D:
	"""Draw a pill/capsule shape (vertical rounded rectangle)."""
	var pill = Line2D.new()
	pill.width = 2.0
	pill.default_color = color

	# Calculate direction and perpendicular
	var direction = (bottom - top).normalized()
	var perp = Vector2(-direction.y, direction.x)  # Perpendicular

	# Draw left side (top to bottom)
	pill.add_point(top + perp * radius)
	pill.add_point(bottom + perp * radius)

	# Draw bottom semicircle
	var segments = 8
	for i in range(segments + 1):
		var angle = PI * float(i) / float(segments)  # 0 to PI (half circle)
		var offset = Vector2(cos(angle), sin(angle)) * radius
		# Rotate offset to align with capsule orientation
		var rotated = Vector2(
			perp.x * offset.x + direction.x * offset.y,
			perp.y * offset.x + direction.y * offset.y
		)
		pill.add_point(bottom + rotated)

	# Draw right side (bottom to top)
	pill.add_point(bottom - perp * radius)
	pill.add_point(top - perp * radius)

	# Draw top semicircle
	for i in range(segments + 1):
		var angle = PI + PI * float(i) / float(segments)  # PI to 2*PI (half circle)
		var offset = Vector2(cos(angle), sin(angle)) * radius
		var rotated = Vector2(
			perp.x * offset.x + direction.x * offset.y,
			perp.y * offset.x + direction.y * offset.y
		)
		pill.add_point(top + rotated)

	# Close the shape
	pill.add_point(top + perp * radius)

	return pill

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


func apply_pinch_zoom(zoom_delta: float) -> void:
	"""Apply zoom from pinch gesture. Positive = zoom in, negative = zoom out."""
	if is_shop_open():
		return  # Don't zoom while shop is open
	target_zoom = clamp(target_zoom + zoom_delta, zoom_min, zoom_max)
	if camera:
		camera.zoom = Vector2(target_zoom, target_zoom)


func _on_mobile_dash_pressed() -> void:
	"""Handle dash button press from mobile controls."""
	if movement_system and movement_system.can_dash():
		var input_dir = GameInput.get_movement()
		var aim_pos = GameInput.get_aim_position()
		movement_system.start_dash(input_dir, aim_pos)
	elif not movement_system:
		# Fallback to old system
		if not is_dashing and dash_cooldown_timer <= 0:
			start_dash()


func _on_mobile_inventory_pressed() -> void:
	"""Handle inventory button press from mobile controls."""
	if inventory_ui:
		inventory_ui.toggle_ui()


func _on_mobile_character_pressed() -> void:
	"""Handle character button press from mobile controls."""
	if character_ui:
		character_ui.toggle_character_ui()


func update_camera_zoom(delta: float) -> void:
	"""Smoothly interpolate camera zoom to target"""
	if not camera:
		return

	# Smoothly lerp current zoom to target zoom
	var current_zoom_value = camera.zoom.x
	var new_zoom = lerp(current_zoom_value, target_zoom, zoom_speed)
	camera.zoom = Vector2(new_zoom, new_zoom)

func _on_debug_zoom_toggled(is_debug_visible: bool) -> void:
	"""Toggle between normal and unrestricted zoom limits when F3 debug is toggled"""
	debug_zoom_active = is_debug_visible

	if is_debug_visible:
		# Save current normal limits and switch to debug (unrestricted) limits
		normal_zoom_min = zoom_min
		normal_zoom_max = zoom_max
		zoom_min = DEBUG_ZOOM_MIN
		zoom_max = DEBUG_ZOOM_MAX
		print("📷 Debug zoom ENABLED (%.2fx - %.1fx)" % [DEBUG_ZOOM_MIN, DEBUG_ZOOM_MAX])
	else:
		# Restore normal zoom limits
		zoom_min = normal_zoom_min
		zoom_max = normal_zoom_max
		# Clamp current zoom to normal limits if it's outside them
		if target_zoom < zoom_min or target_zoom > zoom_max:
			target_zoom = clamp(target_zoom, zoom_min, zoom_max)
			if camera:
				camera.zoom = Vector2(target_zoom, target_zoom)
		print("📷 Debug zoom DISABLED (%.2fx - %.1fx)" % [zoom_min, zoom_max])

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

	# Check if ESC menu (spawn hints overlay) is open AND mouse is over it
	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		var hints_panel = spawn_hints_overlay.get_node_or_null("FullRect/HintsPanel")
		if hints_panel and hints_panel.visible:
			var rect = hints_panel.get_global_rect()
			if rect.has_point(mouse_pos):
				return true

	# Check if any UI control has focus (text input, etc.)
	var focused = get_viewport().gui_get_focus_owner()
	if focused:
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
			# Check for any CanvasLayer with a visible PanelContainer (generic UI panels like BugReportUI)
			for panel in child.get_children():
				if panel is PanelContainer and panel.visible:
					var rect = panel.get_global_rect()
					if rect.has_point(mouse_pos):
						return true
	return false

func _is_mouse_over_canvas_layer(canvas_layer: CanvasLayer, mouse_pos: Vector2) -> bool:
	"""Check if mouse position is within any Control child of a CanvasLayer"""
	if not canvas_layer or not canvas_layer.visible:
		return false

	# Find Control children and check if mouse is over any of them
	# Only check controls with MOUSE_FILTER_STOP (blocks input) - skip PASS and IGNORE
	for child in canvas_layer.get_children():
		if child is Control and child.visible:
			# Only block for controls that stop mouse input (actual UI panels)
			# Skip MOUSE_FILTER_IGNORE and MOUSE_FILTER_PASS (like full-screen drop zones)
			if child.mouse_filter != Control.MOUSE_FILTER_STOP:
				continue
			var rect = child.get_global_rect()
			if rect.has_point(mouse_pos):
				return true
	return false

func is_shop_open() -> bool:
	"""Legacy function - kept for compatibility. Use is_ui_blocking_input() instead"""
	return is_ui_blocking_input()


func _is_minimap_hovered() -> bool:
	"""Check if mouse is hovering over the minimap"""
	if Minimap and Minimap.is_mouse_over:
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
	var death_position = global_position
	print("\n💀 ===== PLAYER DEATH =====")
	print("Position: ", death_position)
	print("Remaining health: ", current_health)

	# Track death for forged weapon stats
	if combat_system and combat_system.has_method("track_player_death"):
		combat_system.track_player_death()

	# Track death for forged armor/accessory stats
	_record_equipment_death()

	# Close any open loot UIs on death
	for child in get_tree().root.get_children():
		if child is LootBodyUI and child.visible:
			child.close_ui()
			print("   📦 Closed LootBodyUI on death")
		elif child is ChestLootUI and child.visible:
			child.close_ui()
			print("   📦 Closed ChestLootUI on death")

	# Play death sound (gender-specific)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		var is_female = (selected_gender == Gender.FEMALE)
		sound_manager.play_player_death_sound(global_position, is_female, -6.0)

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

	# === SPAWN CORPSE WITH ALL LOOT ===
	var corpse_scene = load("res://scenes/world/PlayerCorpse.tscn")
	if corpse_scene:
		var corpse = corpse_scene.instantiate()
		corpse.initialize(self, death_position)
		get_tree().current_scene.add_child(corpse)
		_active_corpses.append(corpse)
		print("   💀 Spawned player corpse at %s" % death_position)

	# === HIDE PLAYER AND MAKE UNTARGETABLE ===
	# Hide player sprite so only corpse is visible
	var char_sprite = get_node_or_null("CharacterSprite")
	if char_sprite:
		char_sprite.visible = false
	# Also hide health bar
	if health_bar:
		health_bar.visible = false
	# Hide attack cone visualizer
	var cone = get_node_or_null("ConeVisualizer")
	if cone:
		cone.visible = false
	# Cancel combat state (removes red border)
	is_in_combat = false
	# Remove from player group so enemies can't target
	remove_from_group("player")
	# Disable collision
	collision_layer = 0
	collision_mask = 0
	print("   👻 Player hidden and untargetable")

	# === APPLY XP PENALTY ===
	var xp_lost = CharacterStats.apply_death_xp_penalty()
	print("   📉 Lost %d XP" % xp_lost)

	# === DEAGGRO ALL ENEMIES IMMEDIATELY ===
	# Do this before showing death screen so player doesn't hear attacks
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in all_enemies:
		if enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			if ai.has_method("reset_to_patrol"):
				ai.reset_to_patrol()
			# Also clear their target directly
			if "current_target" in ai:
				ai.current_target = null
	print("🔄 All enemies deaggroed")

	# === SHOW DEATH SCREEN ===
	var death_screen = _get_or_create_death_screen()
	if death_screen:
		death_screen.show_death_screen(xp_lost, death_position)
		print("   💀 Death screen shown - waiting for respawn...")
		await death_screen.respawn_requested
		print("   ✅ Respawn requested!")

	# === STRIP PLAYER OF EVERYTHING ===
	# Clear inventory (saved to corpse already)
	InventorySystem.clear_all()

	# Clear all equipment and reset to default clothes
	CharacterStats.clear_all_equipment()
	CharacterStats.reset_equipment_to_default()

	# Reset player position to campfire spawn point (center of chunk 0)
	global_position = _get_bind_point()
	velocity = Vector2.ZERO

	# === RESTORE PLAYER VISIBILITY AND TARGETING ===
	# Re-add to player group so systems can find us
	if not is_in_group("player"):
		add_to_group("player")
	# Restore collision (layer 1 = player)
	collision_layer = 1
	collision_mask = 1
	# Show health bar
	if health_bar:
		health_bar.visible = true
	# Show attack cone visualizer
	var cone_vis = get_node_or_null("ConeVisualizer")
	if cone_vis:
		cone_vis.visible = true

	# Restore health
	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if portrait_hud and portrait_hud.has_method("update_health"):
		portrait_hud.update_health(current_health, max_health)

	# Note: Player visuals will update automatically through CharacterStats signals
	# when reset_equipment_to_default() equips the starter clothes

	# Re-enable player controls
	set_physics_process(true)

	# Reset death flag
	is_dead = false

	print("✨ Player respawned at bind point")
	print("   XP lost: %d (now at %d)" % [xp_lost, CharacterStats.experience])
	print("   Equipment: Default clothes only")
	print("   Gold: 0 (on corpse)")
	print("===== END PLAYER DEATH =====\n")

# Track player's corpses
var _active_corpses: Array = []

# Death screen reference
var _death_screen: DeathScreenUI = null

func _get_or_create_death_screen() -> DeathScreenUI:
	"""Get existing death screen or create a new one"""
	if _death_screen and is_instance_valid(_death_screen):
		return _death_screen

	# Check if one already exists in the scene
	_death_screen = get_tree().root.get_node_or_null("DeathScreenUI") as DeathScreenUI
	if _death_screen:
		return _death_screen

	# Create new death screen
	var death_screen_scene = load("res://scenes/ui/DeathScreenUI.tscn")
	if death_screen_scene:
		_death_screen = death_screen_scene.instantiate()
		get_tree().root.add_child(_death_screen)
		print("   💀 Created DeathScreenUI")
		return _death_screen

	push_error("Failed to load DeathScreenUI scene!")
	return null

func _get_bind_point() -> Vector2:
	"""Get respawn location - guild World Tree or default campfire"""
	# Default spawn point (chunk 0 center / starting area campfire)
	var default_spawn = Vector2(Constants.CHUNK_SIZE / 2, 0)

	# Check for guild World Tree
	if WorldTreeManager and WorldTreeManager.has_method("get_tree_by_guild"):
		var guild_id = _get_player_guild_id()
		if guild_id and guild_id != "":
			var tree = WorldTreeManager.get_tree_by_guild(guild_id)
			if tree and is_instance_valid(tree):
				# Respawn slightly offset from tree center
				return tree.position + Vector2(100, 50)

	return default_spawn


func _get_player_guild_id() -> String:
	"""Get the current player's guild ID for respawn binding"""
	if GroupManager and GroupManager.has_group():
		return "guild_%d" % GroupManager.group_leader

	# Solo players have their own "guild" for World Tree purposes
	if AshbaneAuth and AshbaneAuth.is_logged_in():
		return "solo_guild_%d" % AshbaneAuth.user_id

	return "solo_guild_local_player"

func create_character_ui() -> void:
	"""Create and add character UI to scene tree (reuses existing if present)"""
	print("🏗️ Player.create_character_ui() called (deferred)")

	# Check if CharacterUI already exists in root
	var existing = get_tree().root.get_node_or_null("CharacterUI")
	if existing:
		character_ui = existing
		print("📋 Character UI already exists, reusing existing instance")
		return

	var CharacterUIScript = load("res://scripts/ui/CharacterUI.gd")
	character_ui = CharacterUIScript.new()
	character_ui.name = "CharacterUI"

	# Add to scene tree (now that Player is fully ready, this works properly)
	get_tree().root.add_child(character_ui)

	print("📋 Character UI added to scene tree")
	print("   In tree: ", character_ui.is_inside_tree())
	print("   Parent: ", character_ui.get_parent())

func create_campfire_indicator() -> void:
	"""Create and add campfire direction indicator to scene tree (reuses existing if present)"""
	print("🏗️ Player.create_campfire_indicator() called (deferred)")

	# Check if CampfireIndicator already exists in root
	var existing = get_tree().root.get_node_or_null("CampfireIndicator")
	if existing:
		campfire_indicator = existing
		print("🧭 Campfire indicator already exists, reusing existing instance")
		return

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
	"""Create and add chat UI to scene tree (reuses existing if present)"""
	print("🏗️ Player.create_chat_ui() called (deferred)")

	# Check if ChatUI already exists in root (persists across scene changes)
	var existing = get_tree().root.get_node_or_null("ChatUI")
	if existing:
		chat_ui = existing
		print("💬 Chat UI already exists, reusing existing instance")
		return

	var ChatUIScript = load("res://scripts/ui/ChatUI.gd")
	chat_ui = ChatUIScript.new()
	chat_ui.name = "ChatUI"

	# Add to scene tree
	get_tree().root.add_child(chat_ui)

	print("💬 Chat UI added to scene tree")
	print("   In tree: ", chat_ui.is_inside_tree())

func create_inventory_ui() -> void:
	"""Create and add inventory UI to scene tree (reuses existing if present)"""
	print("🏗️ Player.create_inventory_ui() called (deferred)")

	# Check if InventoryUI already exists in root
	var existing = get_tree().root.get_node_or_null("InventoryUI")
	if existing:
		inventory_ui = existing
		print("📦 Inventory UI already exists, reusing existing instance")
		return

	var InventoryUIScript = load("res://scripts/ui/InventoryUI.gd")
	inventory_ui = InventoryUIScript.new()
	inventory_ui.name = "InventoryUI"

	# Add to scene tree
	get_tree().root.add_child(inventory_ui)

	print("Inventory UI added to scene tree")
	print("   In tree: ", inventory_ui.is_inside_tree())

func create_portrait_hud() -> void:
	"""Create and add portrait HUD to scene tree"""
	print("🏗️ Player.create_portrait_hud() called (deferred)")

	# Check if portrait HUD already exists
	var existing = get_tree().root.get_node_or_null("PortraitHUD")
	if existing:
		portrait_hud = existing
		# Update health on existing HUD
		if portrait_hud.has_method("update_health"):
			portrait_hud.update_health(current_health, max_health)
		print("🖼️ Portrait HUD already exists, reusing existing instance")
		return

	var PortraitHUDScript = load("res://scripts/ui/PortraitHUD.gd")
	portrait_hud = PortraitHUDScript.new()
	portrait_hud.name = "PortraitHUD"

	# Add to scene tree
	get_tree().root.add_child(portrait_hud)

	# Initialize with current health
	if portrait_hud.has_method("update_health"):
		portrait_hud.update_health(current_health, max_health)

	print("Portrait HUD added to scene tree")

func create_duel_ui() -> void:
	"""Create and add duel UI components to scene tree"""
	print("Creating duel UI components (deferred)")

	# Check for existing duel request popup
	var existing_popup = get_tree().root.get_node_or_null("DuelRequestPopup")
	if existing_popup:
		duel_request_popup = existing_popup
		print("⚔️ DuelRequestPopup already exists, reusing")
	else:
		var DuelRequestPopupScene = load("res://scenes/ui/DuelRequestPopup.tscn")
		if DuelRequestPopupScene:
			duel_request_popup = DuelRequestPopupScene.instantiate()
			get_tree().root.add_child(duel_request_popup)

	# Check for existing duel countdown UI
	var existing_countdown = get_tree().root.get_node_or_null("DuelCountdownUI")
	if existing_countdown:
		duel_countdown_ui = existing_countdown
		print("⚔️ DuelCountdownUI already exists, reusing")
	else:
		var DuelCountdownUIScene = load("res://scenes/ui/DuelCountdownUI.tscn")
		if DuelCountdownUIScene:
			duel_countdown_ui = DuelCountdownUIScene.instantiate()
			get_tree().root.add_child(duel_countdown_ui)

	# Check for existing duel result UI
	var existing_result = get_tree().root.get_node_or_null("DuelResultUI")
	if existing_result:
		duel_result_ui = existing_result
		print("⚔️ DuelResultUI already exists, reusing")
	else:
		var DuelResultUIScene = load("res://scenes/ui/DuelResultUI.tscn")
		if DuelResultUIScene:
			duel_result_ui = DuelResultUIScene.instantiate()
			get_tree().root.add_child(duel_result_ui)

	print("Duel UI components added to scene tree")

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN HINTS OVERLAY
# ═══════════════════════════════════════════════════════════════════════════

var spawn_hints_overlay: CanvasLayer = null
var has_talked_to_blacksmith: bool = false

# Logout timer system
var logout_timer_overlay: CanvasLayer = null
var logout_timer_active: bool = false
var logout_time_remaining: float = 0.0
const LOGOUT_TIMER_DURATION: float = 10.0  # 10 seconds to logout

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

	# SOUND section
	var sound_sep = HSeparator.new()
	sound_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(sound_sep)

	var sound_title = Label.new()
	sound_title.text = "SOUND"
	sound_title.add_theme_font_size_override("font_size", 16)
	sound_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))  # Gold
	sound_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sound_title)

	# Load saved settings
	var config = ConfigFile.new()
	var saved_master = 80.0
	var saved_music = 70.0
	var saved_sfx = 80.0
	if config.load("user://settings.cfg") == OK:
		saved_master = config.get_value("audio", "master_volume", 80.0)
		saved_music = config.get_value("audio", "music_volume", 70.0)
		saved_sfx = config.get_value("audio", "sfx_volume", 80.0)

	# Master Volume row
	var master_row = HBoxContainer.new()
	master_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var master_label = Label.new()
	master_label.text = "Master"
	master_label.add_theme_font_size_override("font_size", 14)
	master_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	master_label.custom_minimum_size = Vector2(50, 0)
	master_row.add_child(master_label)

	var master_slider = HSlider.new()
	master_slider.name = "MasterVolumeSlider"
	master_slider.min_value = 0.0
	master_slider.max_value = 100.0
	master_slider.step = 1.0
	master_slider.value = saved_master
	master_slider.custom_minimum_size = Vector2(100, 20)
	master_slider.value_changed.connect(_on_master_volume_changed)
	master_row.add_child(master_slider)

	var master_value = Label.new()
	master_value.name = "MasterVolumeValue"
	master_value.text = "%d%%" % int(saved_master)
	master_value.add_theme_font_size_override("font_size", 12)
	master_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	master_value.custom_minimum_size = Vector2(35, 0)
	master_row.add_child(master_value)
	vbox.add_child(master_row)

	# Music Volume row
	var music_row = HBoxContainer.new()
	music_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var music_label = Label.new()
	music_label.text = "Music"
	music_label.add_theme_font_size_override("font_size", 14)
	music_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	music_label.custom_minimum_size = Vector2(50, 0)
	music_row.add_child(music_label)

	var music_slider = HSlider.new()
	music_slider.name = "MusicVolumeSlider"
	music_slider.min_value = 0.0
	music_slider.max_value = 100.0
	music_slider.step = 1.0
	music_slider.value = saved_music
	music_slider.custom_minimum_size = Vector2(100, 20)
	music_slider.value_changed.connect(_on_music_volume_changed)
	music_row.add_child(music_slider)

	var music_value = Label.new()
	music_value.name = "MusicVolumeValue"
	music_value.text = "%d%%" % int(saved_music)
	music_value.add_theme_font_size_override("font_size", 12)
	music_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	music_value.custom_minimum_size = Vector2(35, 0)
	music_row.add_child(music_value)
	vbox.add_child(music_row)

	# SFX Volume row
	var sfx_row = HBoxContainer.new()
	sfx_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sfx_label = Label.new()
	sfx_label.text = "SFX"
	sfx_label.add_theme_font_size_override("font_size", 14)
	sfx_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	sfx_label.custom_minimum_size = Vector2(50, 0)
	sfx_row.add_child(sfx_label)

	var sfx_slider = HSlider.new()
	sfx_slider.name = "SFXVolumeSlider"
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 100.0
	sfx_slider.step = 1.0
	sfx_slider.value = saved_sfx
	sfx_slider.custom_minimum_size = Vector2(100, 20)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_row.add_child(sfx_slider)

	var sfx_value = Label.new()
	sfx_value.name = "SFXVolumeValue"
	sfx_value.text = "%d%%" % int(saved_sfx)
	sfx_value.add_theme_font_size_override("font_size", 12)
	sfx_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sfx_value.custom_minimum_size = Vector2(35, 0)
	sfx_row.add_child(sfx_value)
	vbox.add_child(sfx_row)

	# DISPLAY section
	var display_sep = HSeparator.new()
	display_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(display_sep)

	var display_title = Label.new()
	display_title.text = "DISPLAY"
	display_title.add_theme_font_size_override("font_size", 16)
	display_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))  # Gold
	display_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(display_title)

	# Resolution row
	var res_row = HBoxContainer.new()
	res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var res_label = Label.new()
	res_label.text = "Resolution"
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	res_label.custom_minimum_size = Vector2(70, 0)
	res_row.add_child(res_label)

	var res_option = OptionButton.new()
	res_option.name = "ResolutionOption"
	res_option.add_theme_font_size_override("font_size", 12)
	res_option.custom_minimum_size = Vector2(110, 26)
	# Add resolution options
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]
	for i in range(resolutions.size()):
		var res = resolutions[i]
		res_option.add_item("%dx%d" % [res.x, res.y], i)
	# Select saved resolution from config
	var res_config = ConfigFile.new()
	var saved_res_index = 0
	if res_config.load("user://settings.cfg") == OK:
		saved_res_index = res_config.get_value("display", "resolution_index", 0)
	res_option.select(saved_res_index)
	res_option.item_selected.connect(_on_resolution_selected)
	# Disable if in fullscreen (resolution doesn't apply)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		res_option.disabled = true
	res_row.add_child(res_option)
	vbox.add_child(res_row)

	# Fullscreen row
	var fs_row = HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fs_label = Label.new()
	fs_label.text = "Fullscreen"
	fs_label.add_theme_font_size_override("font_size", 14)
	fs_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	fs_label.custom_minimum_size = Vector2(70, 0)
	fs_row.add_child(fs_label)

	var fs_check = CheckButton.new()
	fs_check.name = "FullscreenCheck"
	fs_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_check.toggled.connect(_on_fullscreen_toggled.bind(res_option))
	fs_row.add_child(fs_check)
	vbox.add_child(fs_row)

	# MENU section
	var menu_sep = HSeparator.new()
	menu_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(menu_sep)

	var menu_title = Label.new()
	menu_title.text = "MENU"
	menu_title.add_theme_font_size_override("font_size", 16)
	menu_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))  # Gold
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(menu_title)

	# Menu buttons container
	var menu_buttons = HBoxContainer.new()
	menu_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(menu_buttons)

	# Credits button
	var credits_button = Button.new()
	credits_button.name = "CreditsButton"
	credits_button.text = "Credits"
	credits_button.add_theme_font_size_override("font_size", 12)
	credits_button.custom_minimum_size = Vector2(70, 26)
	credits_button.pressed.connect(_on_menu_credits_pressed)
	menu_buttons.add_child(credits_button)

	# Disconnect button
	var disconnect_button = Button.new()
	disconnect_button.name = "DisconnectButton"
	disconnect_button.text = "Disconnect"
	disconnect_button.add_theme_font_size_override("font_size", 12)
	disconnect_button.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
	disconnect_button.custom_minimum_size = Vector2(80, 26)
	disconnect_button.pressed.connect(_on_menu_disconnect_pressed)
	menu_buttons.add_child(disconnect_button)

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

func _find_node_by_name(root: Node, node_name: String) -> Node:
	"""Recursively find a node by name"""
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found = _find_node_by_name(child, node_name)
		if found:
			return found
	return null

func _on_master_volume_changed(value: float) -> void:
	"""Handle master volume slider change"""
	# Update label
	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		var label = _find_node_by_name(spawn_hints_overlay, "MasterVolumeValue")
		if label:
			label.text = "%d%%" % int(value)

	# Apply volume
	var db = lerp(-40.0, 0.0, value / 100.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
	_save_sound_settings()

func _on_music_volume_changed(value: float) -> void:
	"""Handle music volume slider change"""
	# Update label
	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		var label = _find_node_by_name(spawn_hints_overlay, "MusicVolumeValue")
		if label:
			label.text = "%d%%" % int(value)

	# Apply volume
	var db = lerp(-40.0, 0.0, value / 100.0)
	var music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, db)
	_save_sound_settings()

func _on_sfx_volume_changed(value: float) -> void:
	"""Handle SFX volume slider change"""
	# Update label
	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		var label = _find_node_by_name(spawn_hints_overlay, "SFXVolumeValue")
		if label:
			label.text = "%d%%" % int(value)

	# Apply volume
	var db = lerp(-40.0, 0.0, value / 100.0)
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, db)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("set_sfx_volume"):
		sound_manager.set_sfx_volume(value / 100.0)
	_save_sound_settings()

func _save_sound_settings() -> void:
	"""Save sound settings to config file"""
	if not spawn_hints_overlay or not is_instance_valid(spawn_hints_overlay):
		return

	var config = ConfigFile.new()
	config.load("user://settings.cfg")  # Load existing to preserve other settings

	# Find sliders and save their values
	var master_slider = _find_node_by_name(spawn_hints_overlay, "MasterVolumeSlider")
	var music_slider = _find_node_by_name(spawn_hints_overlay, "MusicVolumeSlider")
	var sfx_slider = _find_node_by_name(spawn_hints_overlay, "SFXVolumeSlider")

	if master_slider:
		config.set_value("audio", "master_volume", master_slider.value)
	if music_slider:
		config.set_value("audio", "music_volume", music_slider.value)
	if sfx_slider:
		config.set_value("audio", "sfx_volume", sfx_slider.value)

	config.save("user://settings.cfg")

func _apply_saved_display_settings() -> void:
	"""Apply saved display settings when entering game"""
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return

	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]

	# Apply resolution
	var res_index = config.get_value("display", "resolution_index", 0)
	if res_index >= 0 and res_index < resolutions.size():
		DisplayServer.window_set_size(resolutions[res_index])

	# Apply fullscreen setting
	var fullscreen = config.get_value("display", "fullscreen", false)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# Don't force windowed mode - let the resolution handler do that if needed

func _on_resolution_selected(index: int) -> void:
	"""Handle resolution dropdown change (only applies in windowed mode)"""
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
	]
	if index < 0 or index >= resolutions.size():
		return

	# Save setting regardless of current mode
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("display", "resolution_index", index)
	config.save("user://settings.cfg")

	# Only apply if in windowed mode
	var window_mode = DisplayServer.window_get_mode()
	if window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return  # Resolution doesn't apply in fullscreen

	# Must be in windowed mode to resize (handles maximized)
	if window_mode != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_size(resolutions[index])

func _on_fullscreen_toggled(enabled: bool, res_option: OptionButton = null) -> void:
	"""Handle fullscreen toggle"""
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		# Disable resolution dropdown (doesn't apply in fullscreen)
		if res_option:
			res_option.disabled = true
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Enable resolution dropdown
		if res_option:
			res_option.disabled = false
		# Apply saved resolution when exiting fullscreen
		var resolutions = [
			Vector2i(1280, 720),
			Vector2i(1366, 768),
			Vector2i(1600, 900),
			Vector2i(1920, 1080),
			Vector2i(2560, 1440),
		]
		var config_temp = ConfigFile.new()
		if config_temp.load("user://settings.cfg") == OK:
			var res_index = config_temp.get_value("display", "resolution_index", 0)
			if res_index >= 0 and res_index < resolutions.size():
				DisplayServer.window_set_size(resolutions[res_index])

	# Save setting
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("display", "fullscreen", enabled)
	config.save("user://settings.cfg")

func _on_menu_credits_pressed() -> void:
	"""Open credits panel from ESC menu"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()

	# Hide spawn hints and open GameMenu credits
	toggle_spawn_hints()
	var game_menu = get_node_or_null("/root/main/GameMenu")
	if game_menu and game_menu.has_method("open_credits"):
		game_menu.open_credits()

func _on_menu_disconnect_pressed() -> void:
	"""Start logout timer - prevents combat logging"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()

	# Close spawn hints overlay
	if spawn_hints_overlay and is_instance_valid(spawn_hints_overlay):
		spawn_hints_overlay.queue_free()
		spawn_hints_overlay = null

	# Start logout timer instead of immediate disconnect
	_start_logout_timer()

func _start_logout_timer() -> void:
	"""Create and show logout timer UI"""
	if logout_timer_active:
		return  # Already logging out

	logout_timer_active = true
	logout_time_remaining = LOGOUT_TIMER_DURATION

	# Create overlay
	logout_timer_overlay = CanvasLayer.new()
	logout_timer_overlay.name = "LogoutTimerOverlay"
	logout_timer_overlay.layer = 150  # Above everything

	# Semi-transparent background
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.6)
	logout_timer_overlay.add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	logout_timer_overlay.add_child(center)

	# Panel
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 200)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.8, 0.4, 0.2, 1)  # Orange border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 15)
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(inner_vbox)

	# Title
	var title = Label.new()
	title.text = "LOGGING OUT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))  # Orange
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(title)

	# Timer label
	var timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "10"
	timer_label.add_theme_font_size_override("font_size", 36)
	timer_label.add_theme_color_override("font_color", Color(1, 1, 1))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(timer_label)

	# Info text
	var info = Label.new()
	info.text = "Stay still to logout safely\nMoving will cancel"
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(info)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_child(btn_row)

	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 35)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(_cancel_logout)
	btn_row.add_child(cancel_btn)

	# Quit Now button - exits immediately but character stays for full 10s
	var quit_btn = Button.new()
	quit_btn.name = "QuitNowButton"
	quit_btn.text = "Quit Now"
	quit_btn.custom_minimum_size = Vector2(100, 35)
	quit_btn.add_theme_font_size_override("font_size", 14)
	quit_btn.pressed.connect(_quit_now)
	btn_row.add_child(quit_btn)

	# Style quit button with warning color
	var quit_style = StyleBoxFlat.new()
	quit_style.bg_color = Color(0.5, 0.25, 0.1, 1.0)  # Dark orange
	quit_style.set_corner_radius_all(4)
	quit_btn.add_theme_stylebox_override("normal", quit_style)
	var quit_hover = StyleBoxFlat.new()
	quit_hover.bg_color = Color(0.6, 0.35, 0.15, 1.0)  # Lighter orange
	quit_hover.set_corner_radius_all(4)
	quit_btn.add_theme_stylebox_override("hover", quit_hover)

	# Warning text about quit now
	var warning = Label.new()
	warning.text = "Quit Now: You stay in-game for 10s"
	warning.add_theme_font_size_override("font_size", 10)
	warning.add_theme_color_override("font_color", Color(0.8, 0.5, 0.3))  # Orange warning
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(warning)

	get_tree().root.add_child(logout_timer_overlay)

func _cancel_logout() -> void:
	"""Cancel the logout timer"""
	logout_timer_active = false
	logout_time_remaining = 0.0

	if logout_timer_overlay and is_instance_valid(logout_timer_overlay):
		logout_timer_overlay.queue_free()
		logout_timer_overlay = null

	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()

func _quit_now() -> void:
	"""Quit game immediately - client exits but character stays in-game for full 10s"""
	# Save sound settings before leaving
	_save_sound_settings()

	# Disconnect immediately - server will keep character for 10s
	# (Server-side logout timer continues even after client disconnects)
	if NetworkManager:
		NetworkManager.close_connection()

	# Exit the game completely
	get_tree().quit()

func _complete_logout() -> void:
	"""Actually disconnect after timer completes"""
	logout_timer_active = false

	# Clean up logout overlay
	if logout_timer_overlay and is_instance_valid(logout_timer_overlay):
		logout_timer_overlay.queue_free()
		logout_timer_overlay = null

	# Save sound settings before leaving
	_save_sound_settings()

	# Save character appearance to backend for Armory preview
	if AshbaneAuth and AshbaneAuth.is_authenticated:
		var appearance = get_appearance_data()
		AshbaneAuth.save_appearance(appearance)

	# Close connection and return to main menu
	if NetworkManager:
		NetworkManager.close_connection()

	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/MainMenu.tscn")

func _process_logout_timer(delta: float, input_direction: Vector2) -> void:
	"""Process logout countdown - cancel if player moves or takes damage"""
	if not logout_timer_active:
		return

	# Cancel if player is moving
	if input_direction.length() > 0.1:
		_cancel_logout()
		if NotificationManager:
			NotificationManager.show_notification("Logout cancelled - you moved!", "WARNING")
		return

	# Decrement timer
	logout_time_remaining -= delta

	# Update timer display
	if logout_timer_overlay and is_instance_valid(logout_timer_overlay):
		var timer_label = _find_node_by_name(logout_timer_overlay, "TimerLabel")
		if timer_label:
			timer_label.text = str(ceili(logout_time_remaining))

	# Check if timer completed
	if logout_time_remaining <= 0:
		_complete_logout()

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
# TUTORIAL BLACKOUT OVERLAY
# ═══════════════════════════════════════════════════════════════════════════

var tutorial_blackout: Node2D = null
const TUTORIAL_CENTER = Vector2(4000, 0)  # Constants.CHUNK_SIZE / 2, 0
const TUTORIAL_RADIUS = 500.0
# Blackout fade is handled in TutorialBlackoutVisual inner class
# NOTE: tutorial_dummy_hits and TUTORIAL_FORCE_CRIT_HITS moved to PlayerCombat

func create_tutorial_blackout() -> void:
	"""Create a blackout effect that hides the world outside the tutorial area"""
	if tutorial_blackout and is_instance_valid(tutorial_blackout):
		return  # Already exists

	tutorial_blackout = Node2D.new()
	tutorial_blackout.name = "TutorialBlackout"
	tutorial_blackout.z_index = 100  # Above most things but below UI

	# Create the blackout using a custom draw
	var blackout_visual = TutorialBlackoutVisual.new()
	blackout_visual.center = TUTORIAL_CENTER
	blackout_visual.inner_radius = TUTORIAL_RADIUS
	tutorial_blackout.add_child(blackout_visual)

	# Add to scene (not as child of player so it doesn't move)
	get_tree().root.call_deferred("add_child", tutorial_blackout)
	print("🌑 Tutorial blackout created")

func remove_tutorial_blackout() -> void:
	"""Remove the blackout when tutorial advances past the locked area"""
	if tutorial_blackout and is_instance_valid(tutorial_blackout):
		# Fade out
		var tween = create_tween()
		tween.tween_property(tutorial_blackout, "modulate:a", 0.0, 1.0)
		await tween.finished
		if tutorial_blackout and is_instance_valid(tutorial_blackout):
			tutorial_blackout.queue_free()
			tutorial_blackout = null
		print("🌑 Tutorial blackout removed")

func update_tutorial_blackout() -> void:
	"""Check if blackout should be shown/hidden based on tutorial state"""
	if not TutorialManager:
		print("🌑 [Blackout] TutorialManager not found, skipping")
		return

	# Never show tutorial blackout in the Trading Hub
	# Check via TradingHubManager (more reliable than current_scene during scene transitions)
	var hub_manager = get_node_or_null("/root/TradingHubManager")
	var in_hub = hub_manager and hub_manager.is_player_in_hub()
	print("🌑 [Blackout] hub_manager=%s, in_hub=%s" % [hub_manager != null, in_hub])
	if in_hub:
		print("🌑 [Blackout] In Trading Hub - no blackout allowed")
		if tutorial_blackout:
			remove_tutorial_blackout()
		return

	var tutorial_active = TutorialManager.is_tutorial_active()
	var current_step = TutorialManager.current_step
	var should_show_blackout = tutorial_active and current_step < TutorialManager.TutorialStep.KILL_SKELETON
	print("🌑 [Blackout] tutorial_active=%s, step=%s, should_show=%s" % [tutorial_active, current_step, should_show_blackout])

	if should_show_blackout and not tutorial_blackout:
		create_tutorial_blackout()
	elif not should_show_blackout and tutorial_blackout:
		remove_tutorial_blackout()

func _on_tutorial_step_for_blackout(_completed_step: int) -> void:
	"""Called when tutorial step completes - check if blackout should be removed"""
	if not is_instance_valid(self):
		return
	update_tutorial_blackout()

func _on_tutorial_completed_for_blackout() -> void:
	"""Called when tutorial is completed (including skip) - remove blackout immediately"""
	if not is_instance_valid(self):
		return
	remove_tutorial_blackout()

# Inner class for the blackout visual
class TutorialBlackoutVisual extends Node2D:
	var center: Vector2 = Vector2(4000, 0)
	var inner_radius: float = 400.0  # Clear area around tutorial
	var fade_width: float = 100.0    # Short fade distance for sharp edge

	func _draw() -> void:
		# Draw dark overlay everywhere EXCEPT the tutorial circle
		# Use radial segments extending from the circle edge outward
		var outer_radius = inner_radius + fade_width
		var far = 5000.0  # How far out to draw (covers visible area)
		var dark_alpha = 0.88  # Very dark but not completely black
		var segments = 48  # Number of pie slices

		# Draw fade rings from inner to outer radius
		var num_rings = 10
		var ring_width = fade_width / num_rings

		for i in range(num_rings):
			var r1 = inner_radius + i * ring_width
			var r2 = inner_radius + (i + 1) * ring_width
			var t = float(i + 1) / float(num_rings)
			var alpha = t * t * dark_alpha  # Quadratic ease-in

			for j in range(segments):
				var angle1 = j * TAU / segments
				var angle2 = (j + 1) * TAU / segments

				var p1 = center + Vector2(cos(angle1), sin(angle1)) * r1
				var p2 = center + Vector2(cos(angle2), sin(angle2)) * r1
				var p3 = center + Vector2(cos(angle2), sin(angle2)) * r2
				var p4 = center + Vector2(cos(angle1), sin(angle1)) * r2

				draw_colored_polygon([p1, p2, p3, p4], Color(0, 0, 0, alpha))

		# Draw solid dark triangles from outer_radius to far edge (pie slices)
		for j in range(segments):
			var angle1 = j * TAU / segments
			var angle2 = (j + 1) * TAU / segments

			var p1 = center + Vector2(cos(angle1), sin(angle1)) * outer_radius
			var p2 = center + Vector2(cos(angle2), sin(angle2)) * outer_radius
			var p3 = center + Vector2(cos(angle2), sin(angle2)) * far
			var p4 = center + Vector2(cos(angle1), sin(angle1)) * far

			draw_colored_polygon([p1, p2, p3, p4], Color(0, 0, 0, dark_alpha))

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
		sound_manager.play_dodge_sound(global_position, -10.0)

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

	# Copy child layers (armor, weapon, etc.) - skip shadow layer
	for child in character_sprite.get_children():
		if child is AnimatedSprite2D:
			# Skip shadow layer - shadows look weird on afterimages
			if child.name == "ShadowLayer":
				continue
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
	# Sync with movement subsystem
	if movement_system:
		movement_system.add_movement_modifier(source, multiplier)
	# Keep local copy for fallback/compatibility
	movement_modifiers[source] = clamp(multiplier, 0.0, 1.0)
	print("🦶 Movement modifier applied: %s = %.0f%% speed" % [source, multiplier * 100])

func remove_movement_modifier(source: String) -> void:
	"""Remove a movement modifier by source name"""
	# Sync with movement subsystem
	if movement_system:
		movement_system.remove_movement_modifier(source)
	# Keep local copy for fallback/compatibility
	if movement_modifiers.has(source):
		movement_modifiers.erase(source)
		print("🦶 Movement modifier removed: %s" % source)

func get_movement_modifier() -> float:
	"""Get the combined movement modifier (multiplies all active modifiers).
	Returns 1.0 if no modifiers active."""
	# Use movement subsystem if available
	if movement_system:
		return movement_system.get_movement_modifier()
	# Fallback to local calculation
	if movement_modifiers.is_empty():
		return 1.0

	var combined = 1.0
	for modifier in movement_modifiers.values():
		combined *= modifier
	return combined

func clear_all_movement_modifiers() -> void:
	"""Clear all active movement modifiers (e.g., on death/respawn)"""
	# Sync with movement subsystem
	if movement_system:
		movement_system.clear_movement_modifiers()
	# Keep local copy for fallback/compatibility
	movement_modifiers.clear()
	print("🦶 All movement modifiers cleared")

# ═══════════════════════════════════════════════════════════════════════════
# CAPE/BACK SLOT EQUIPMENT
# ═══════════════════════════════════════════════════════════════════════════

func _setup_equipped_cape(sprite: SimpleLPCSprite) -> void:
	"""Load and setup cape sprites if player has a cape equipped in the back slot.
	Checks inventory for forged capes and loads their sprites from ForgeItemDB."""
	if not sprite:
		return

	# Check for equipped cape in inventory (slot type "back" or item type "cape")
	var equipped_cape: Dictionary = {}
	for slot in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[slot]
		if item and (item.get("slot") == "back" or item.get("type") == "cape"):
			# Check if item is equipped (in equipment slot)
			if item.get("equipped", false) or item.get("is_equipped", false):
				equipped_cape = item
				break

	# Also check CharacterStats for equipped back slot
	if equipped_cape.is_empty() and CharacterStats:
		var back_item = CharacterStats.get_equipped_item("back")
		if back_item and not back_item.is_empty():
			equipped_cape = back_item

	if equipped_cape.is_empty():
		# No cape equipped - remove any existing cape layer
		sprite.remove_cape()
		return

	# Get forged item data from ForgeItemDB
	var forged_item_id = equipped_cape.get("item_id", equipped_cape.get("forged_item_id", ""))
	if forged_item_id == "":
		if DEBUG_EQUIP:
			print("[Equip] Cape equipped but no item_id - cannot load sprites")
		return

	var forged_db_data = ForgeItemDB.get_item_by_id(forged_item_id)
	if not forged_db_data or not forged_db_data.has("sprites"):
		if DEBUG_EQUIP:
			print("[Equip] Cape item_id '%s' not found in ForgeItemDB or has no sprites" % forged_item_id)
		return

	var sprites = forged_db_data["sprites"]

	# Load cape textures
	var cape_walk_tex: Texture2D = null
	var cape_slash_tex: Texture2D = null
	var cape_thrust_tex: Texture2D = null
	var cape_hurt_tex: Texture2D = null

	if sprites.has("walk") and ResourceLoader.exists(sprites["walk"]):
		cape_walk_tex = load(sprites["walk"])
	if sprites.has("slash") and ResourceLoader.exists(sprites["slash"]):
		cape_slash_tex = load(sprites["slash"])
	if sprites.has("thrust") and ResourceLoader.exists(sprites["thrust"]):
		cape_thrust_tex = load(sprites["thrust"])
	if sprites.has("hurt") and ResourceLoader.exists(sprites["hurt"]):
		cape_hurt_tex = load(sprites["hurt"])

	if not cape_walk_tex:
		if DEBUG_EQUIP:
			print("[Equip] Cape has no walk texture - cannot setup cape layer")
		return

	# Setup the cape layer
	sprite.setup_cape(cape_walk_tex, cape_slash_tex, cape_thrust_tex, cape_hurt_tex)

	if DEBUG_EQUIP:
		print("[Equip] Cape equipped: %s" % forged_db_data.get("item_name", forged_item_id))
		print("[Equip]   Walk: %s" % sprites.get("walk", "none"))
		print("[Equip]   Slash: %s" % sprites.get("slash", "none"))

# ═══════════════════════════════════════════════════════════════════════════
# FORGED WEAPON VISUAL EFFECTS
# ═══════════════════════════════════════════════════════════════════════════

func _apply_forged_weapon_effects(forged_data: Dictionary) -> void:
	"""Apply visual effects to forged weapons based on stats and theme.
	Effects scale with weapon level/kills using the evolution tier system."""

	# Clear any existing forged weapon effects first
	_clear_forged_weapon_effects()

	if forged_data.is_empty():
		return

	# Get weapon stats from the equipped weapon resource
	var weapon_stats: WeaponStats = null
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.weapon_stats:
		weapon_stats = CharacterStats.equipped_weapon.weapon_stats

	# Get theme and base effect from forged data
	var theme = forged_data.get("theme", "generic")
	var base_effect = forged_data.get("effect_name", "")
	var glow_color_str = forged_data.get("glow_color", "")

	# Parse glow color if provided
	var theme_color: Color = Color.WHITE
	if glow_color_str != "" and glow_color_str != "none":
		theme_color = Color(glow_color_str)

	# Use WeaponVisualEvolution to calculate effects based on stats
	var effect_config = WeaponVisualEvolution.get_effects_for_weapon(weapon_stats, theme, base_effect)

	if DEBUG_FORGED_EQUIP:
		print("[ForgedEquip] ═══════════════════════════════════════")
		print("[ForgedEquip] Applying visual effects:")
		print("[ForgedEquip]   Theme: %s" % theme)
		print("[ForgedEquip]   Evolution Tier: %s" % effect_config.tier_name)
		print("[ForgedEquip]   Effects: %s" % effect_config.effects)
		print("[ForgedEquip]   Intensity: %.2f" % effect_config.intensity)
		print("[ForgedEquip]   Particle Multiplier: %.2f" % effect_config.particle_multiplier)
		print("[ForgedEquip]   Trail Enabled: %s" % effect_config.trail_enabled)
		print("[ForgedEquip]   Aura Enabled: %s" % effect_config.aura_enabled)
		if effect_config.special_effects.size() > 0:
			print("[ForgedEquip]   Achievement Effects: %s" % effect_config.special_effects)

	# Skip if no effects to apply
	if effect_config.effects.is_empty():
		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip]   No effects to apply (virgin weapon with minimal visuals)")
		return

	# Prepare modifiers for effect application
	var modifiers = {
		"effect_intensity": effect_config.intensity,
		"particle_multiplier": effect_config.particle_multiplier,
		"theme_color": theme_color
	}

	# Apply effects to the weapon sprite, not the player
	var weapon_sprite = get_node_or_null("WeaponSprite")
	if weapon_sprite:
		ForgeVisualEffects.apply_effects_to_entity(weapon_sprite, effect_config.effects, modifiers)
		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip] ✓ Visual effects applied to WeaponSprite")
	else:
		# Fallback to player if no weapon sprite found
		ForgeVisualEffects.apply_effects_to_entity(self, effect_config.effects, modifiers)
		if DEBUG_FORGED_EQUIP:
			print("[ForgedEquip] ✓ Visual effects applied to Player (no WeaponSprite found)")

func _clear_forged_weapon_effects() -> void:
	"""Clear all forged weapon visual effects from the weapon sprite"""
	var weapon_sprite = get_node_or_null("WeaponSprite")
	if weapon_sprite:
		ForgeVisualEffects.clear_effects_from_entity(weapon_sprite)
	# Also clear from player in case effects were applied there previously
	ForgeVisualEffects.clear_effects_from_entity(self)
	if DEBUG_FORGED_EQUIP:
		print("[ForgedEquip] Cleared existing forged weapon effects")

func refresh_forged_weapon_effects() -> void:
	"""Refresh forged weapon effects - call after weapon stats update (level up, etc.)"""
	if not CharacterStats.equipped_weapon or not CharacterStats.equipped_weapon.is_forged:
		_clear_forged_weapon_effects()
		return

	var forged_data = CharacterStats.get_equipped_weapon_data()
	if forged_data.get("is_forged", false):
		_apply_forged_weapon_effects(forged_data)
