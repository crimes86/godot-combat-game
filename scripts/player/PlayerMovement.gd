class_name PlayerMovement
extends RefCounted
## Handles player movement: dash, speed modifiers, boundary clamping
## Used as inner class by Player.gd
##
## INTEGRATION GUIDE:
## -----------------
## To use this subsystem in Player.gd:
##
## 1. Add to Player.gd variables:
##    var movement_system: PlayerMovement = null
##
## 2. In _ready():
##    movement_system = PlayerMovement.new(self)
##    movement_system.set_base_speed(speed)
##
## 3. In _physics_process():
##    velocity = movement_system.process_movement(delta, input_direction)
##    move_and_slide()
##    global_position = movement_system.clamp_to_world_bounds(global_position)
##    # Sync dash state: is_dashing = movement_system.is_dashing
##
## 4. For movement modifiers (lava slow, etc):
##    movement_system.add_movement_modifier("lava", 0.5)  # 50% speed
##    movement_system.remove_movement_modifier("lava")
##
## 5. For dash:
##    if Input.is_action_just_pressed("dash"):
##        movement_system.start_dash(input_direction, get_global_mouse_position())

var player: CharacterBody2D

# Movement stats
var base_speed: float = Constants.PLAYER_BASE_SPEED

# Backpedal slowdown (moving opposite to facing direction)
const BACKPEDAL_SPEED_MULT: float = 0.65  # 65% speed when moving backward
const STRAFE_SPEED_MULT: float = 0.85  # 85% speed when strafing sideways
const BACKPEDAL_THRESHOLD: float = -0.3  # Dot product threshold for "moving backward"
const STRAFE_THRESHOLD: float = 0.3  # Dot product below this = strafing

# Dash/Dodge System
var is_dashing: bool = false
var dash_cooldown: float = 1.5  # Seconds between dashes
var dash_duration: float = 0.2  # How long the dash lasts
var dash_speed_multiplier: float = 3.0  # Speed boost during dash
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_invincible: bool = true  # I-frames during dash

# Movement modifiers (for debuffs like lava slow)
var movement_modifiers: Dictionary = {}  # source_name -> multiplier (0.0-1.0)

# Afterimage spawning
var _dash_afterimage_timer: float = 0.0
const DASH_AFTERIMAGE_INTERVAL: float = 0.03

func _init(player_ref: CharacterBody2D) -> void:
	player = player_ref

func set_base_speed(speed: float) -> void:
	"""Update base movement speed"""
	base_speed = speed

func get_movement_modifier() -> float:
	"""Calculate total movement modifier from all sources"""
	if movement_modifiers.is_empty():
		return 1.0

	var total_modifier = 1.0
	for source in movement_modifiers:
		total_modifier *= movement_modifiers[source]

	return clamp(total_modifier, 0.1, 2.0)  # Clamp to reasonable range

func add_movement_modifier(source: String, multiplier: float) -> void:
	"""Add a movement speed modifier from a source"""
	movement_modifiers[source] = clamp(multiplier, 0.0, 2.0)

func remove_movement_modifier(source: String) -> void:
	"""Remove a movement speed modifier"""
	movement_modifiers.erase(source)

func clear_movement_modifiers() -> void:
	"""Clear all movement modifiers"""
	movement_modifiers.clear()

func is_invincible() -> bool:
	"""Check if player is currently invincible (dash i-frames)"""
	return is_dashing and dash_invincible

func process_movement(delta: float, input_direction: Vector2) -> Vector2:
	"""Process movement and return velocity to apply"""
	# Update dash cooldown
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta

	# Calculate effective speed with modifiers
	var effective_speed = base_speed * get_movement_modifier()

	# Handle dash movement
	if is_dashing:
		dash_timer -= delta
		update_dash_visuals(delta)

		if dash_timer <= 0:
			end_dash()

		# Dash ignores slow effects and backpedal penalty
		return dash_direction * base_speed * dash_speed_multiplier
	else:
		# Apply backpedal/strafe slowdown based on movement vs facing direction
		var directional_mult = get_directional_speed_mult(input_direction)
		return input_direction * effective_speed * directional_mult


func get_directional_speed_mult(move_direction: Vector2) -> float:
	"""Calculate speed multiplier based on movement direction vs facing direction.
	Moving backward = slower, strafing = slightly slower, forward = full speed."""
	if move_direction.length_squared() < 0.01:
		return 1.0  # Not moving

	# Get player's facing direction (towards mouse/attack target)
	var facing_direction = Vector2.ZERO
	if player.has_method("get_attack_direction"):
		facing_direction = player.get_attack_direction()
	elif "attack_direction" in player:
		facing_direction = player.attack_direction
	else:
		return 1.0  # No facing info, no penalty

	if facing_direction.length_squared() < 0.01:
		return 1.0  # No facing direction

	# Normalize both directions
	var move_norm = move_direction.normalized()
	var face_norm = facing_direction.normalized()

	# Dot product: 1 = same direction, -1 = opposite, 0 = perpendicular
	var dot = move_norm.dot(face_norm)

	# Moving backward (opposite to facing)
	if dot < BACKPEDAL_THRESHOLD:
		return BACKPEDAL_SPEED_MULT
	# Strafing (perpendicular to facing)
	elif dot < STRAFE_THRESHOLD:
		return STRAFE_SPEED_MULT
	# Moving forward or mostly forward
	else:
		return 1.0

func clamp_to_world_bounds(pos: Vector2) -> Vector2:
	"""Clamp position to world boundaries"""
	var buffer = 50.0

	# Check if we're in TestHub/TradingHub - use expanded bounds
	var current_scene = player.get_tree().current_scene
	if current_scene and current_scene.name in ["TestHub", "TradingHub"]:
		# TestHub bounds: X: -6000 to 6000, Y: -8000 to 8000
		var x_min = -6000.0 + buffer
		var x_max = 6000.0 - buffer
		var y_min = -8000.0 + buffer
		var y_max = 8000.0 - buffer
		return Vector2(
			clamp(pos.x, x_min, x_max),
			clamp(pos.y, y_min, y_max)
		)

	# Default Zone 1 world bounds
	var x_min = -Constants.CHUNK_SIZE + buffer
	var x_max = Constants.CHUNK_SIZE * 2 - buffer
	var y_min = -Constants.CHUNK_SIZE / 2 + buffer
	var y_max = Constants.CHUNK_SIZE / 2 - buffer

	return Vector2(
		clamp(pos.x, x_min, x_max),
		clamp(pos.y, y_min, y_max)
	)

func clamp_to_tutorial_bounds(pos: Vector2, tutorial_step: int) -> Vector2:
	"""Clamp position to tutorial boundaries during early steps"""
	var TutorialManager = player.get_node_or_null("/root/TutorialManager")
	if not TutorialManager or not TutorialManager.is_tutorial_active():
		return pos

	# During early tutorial steps, keep player near campfire/dummy/blacksmith
	if tutorial_step < 4:  # Before KILL_SKELETON step
		var campfire_pos = Vector2(Constants.CHUNK_SIZE / 2, 0)  # Center of chunk 0
		var tutorial_radius = 500.0

		var distance_from_center = pos.distance_to(campfire_pos)
		if distance_from_center > tutorial_radius:
			var direction_to_center = (campfire_pos - pos).normalized()
			return campfire_pos - direction_to_center * tutorial_radius

	return pos

# ========================================
# DASH SYSTEM
# ========================================

func can_dash() -> bool:
	"""Check if dash is available"""
	return not is_dashing and dash_cooldown_timer <= 0

func start_dash(input_direction: Vector2, mouse_pos: Vector2) -> bool:
	"""Start a dash in the input direction (or towards mouse if no input)"""
	if not can_dash():
		return false

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	_dash_afterimage_timer = 0.0

	# Dash direction: Use input if moving, otherwise dash towards mouse
	if input_direction.length() > 0.1:
		dash_direction = input_direction.normalized()
	else:
		dash_direction = (mouse_pos - player.global_position).normalized()

	# Play dash/dodge whoosh sound
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_dodge_sound(player.global_position, -10.0)

	# Initial dust
	spawn_dash_dust()

	return true

func end_dash() -> void:
	"""End the current dash"""
	is_dashing = false
	dash_direction = Vector2.ZERO

	# End dust
	spawn_dash_dust()

func update_dash_visuals(delta: float) -> void:
	"""Update visual effects during dash"""
	_dash_afterimage_timer += delta
	if _dash_afterimage_timer >= DASH_AFTERIMAGE_INTERVAL:
		_dash_afterimage_timer = 0.0
		spawn_dash_afterimage()

func spawn_dash_dust() -> void:
	"""Spawn dust particles at player's feet"""
	var dust = GPUParticles2D.new()
	dust.emitting = true
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = 8
	dust.lifetime = 0.4

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 15.0
	material.direction = Vector3(0, -1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 30.0
	material.initial_velocity_max = 60.0
	material.gravity = Vector3(0, 50, 0)
	material.scale_min = 2.0
	material.scale_max = 4.0
	material.color = Color(0.7, 0.6, 0.5, 0.6)

	dust.process_material = material
	dust.global_position = player.global_position + Vector2(0, 30)
	dust.z_index = -1

	player.get_tree().root.add_child(dust)

	# Auto cleanup
	player.get_tree().create_timer(1.0).timeout.connect(dust.queue_free)

func spawn_dash_afterimage() -> void:
	"""Spawn a fading afterimage of the player - delegates to Player's method for full gear rendering"""
	# Use Player's spawn_dash_afterimage which properly copies all sprite layers (body, armor, weapon)
	if player.has_method("spawn_dash_afterimage"):
		player.spawn_dash_afterimage()
