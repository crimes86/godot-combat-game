extends Node2D
class_name RuinsCampfire

## 🏛️ Ruins Campfire - Convertible Farming Spot
## - Starts as ruins with 6 skeleton spawns
## - Skeletons patrol sporadically across the ruins area
## - Player can convert ruins to campfire when in range
## - Reverts to ruins if abandoned for 2+ minutes
## - Skeleton spawning continues regardless of state

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

@export var skeleton_count: int = 6
@export var skeleton_respawn_time: float = 60.0  # 1 minute
@export var convert_range: float = 100.0  # Distance to allow conversion
@export var base_abandon_time: float = 120.0  # 2 minutes (no fuel)
@export var max_abandon_time: float = 600.0  # 10 minutes (fully fueled)
@export var patrol_before_ruins_time: float = 5.0  # Patrol for 5s before walking to ruins

# Spawn area constraints
@export var spawn_min_distance: float = 200.0  # Min distance from ruins to spawn (shorter walk)
@export var spawn_max_distance: float = 350.0  # Max distance from ruins to spawn (closer patrol)
@export var avoid_campfire_radius: float = 300.0  # Don't spawn near main campfire
@export var avoid_path_distance: float = 150.0  # Don't spawn on path

# Guardian configuration
@export var guardian_min_level: int = 7  # Min level of skeleton guardians
@export var guardian_max_level: int = 10  # Max level of skeleton guardians

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

enum RuinsState {
	RUINS,      # Initial state - skeletons guard ruins
	CAMPFIRE    # Player converted - now a safe campfire
}

var current_state: RuinsState = RuinsState.RUINS
var player_last_near_time: float = 0.0
var time_since_player_near: float = 0.0
var has_killed_skeleton: bool = false  # Track if player killed at least one skeleton

# Skeleton management
var skeleton_data: Array = []  # {skeleton: Node, respawn_timer: float, state: SkeletonState, patrol_timer: float}
var skeleton_scene: PackedScene = null

enum SkeletonState {
	PATROLLING_SPAWN,  # Initial patrol near spawn
	WALKING_TO_RUINS,  # Walking to ruins
	GUARDING_RUINS     # Patrolling at ruins
}

# Visual components
var ruins_sprite: Sprite2D = null
var campfire_node: Node = null
var interaction_area: Area2D = null
var interaction_prompt: Label = null
var ruins_light: PointLight2D = null

# Day/night light scaling
const BASE_RUINS_LIGHT_ENERGY: float = 0.6
const MIN_RUINS_LIGHT_ENERGY: float = 0.1  # Subtle during day
const MAX_RUINS_LIGHT_ENERGY: float = 1.5  # Strong mystical glow at night

# References
var player: CharacterBody2D = null
var main_campfire_position: Vector2 = Vector2(2000, 0)  # Main campfire location (center of chunk 0)

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Load guardian skeleton scene (armored guardians with special loot)
	skeleton_scene = load("res://scenes/enemies/guardian_skeleton.tscn")
	if not skeleton_scene:
		push_error("❌ Could not load guardian_skeleton.tscn!")
		return

	# Cache ruins light reference
	ruins_light = get_node_or_null("RuinsLight")

	# Create visuals
	create_ruins_visual()
	create_interaction_area()
	create_interaction_prompt()

	# IMPORTANT: Wait one frame to ensure RuinsCampfire is fully in tree before spawning
	await get_tree().process_frame

	# Initialize skeletons (async)
	for i in range(skeleton_count):
		await spawn_skeleton(i)


func _exit_tree() -> void:
	"""Clean up when node is removed from tree"""
	# Stop processing immediately to prevent hanging on exit
	set_physics_process(false)
	set_process(false)

	# Clean up all guardian skeletons (they're siblings, not children)
	var cleaned_count = 0
	for data in skeleton_data:
		var skeleton = data.get("skeleton")
		if skeleton and is_instance_valid(skeleton):
			skeleton.queue_free()
			cleaned_count += 1
	skeleton_data.clear()
	print("🗑️ RuinsCampfire cleaned up %d guardian skeletons" % cleaned_count)

func _physics_process(delta: float) -> void:
	# Find player if needed
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)

	# Update skeleton systems
	update_skeletons(delta)

	# Update interaction prompt
	update_interaction_prompt()

	# Check for abandonment (only in campfire mode)
	if current_state == RuinsState.CAMPFIRE:
		check_abandonment(delta)

	# Update ruins light based on time of day
	update_ruins_light()

	# Debug: Track skeleton states every 5 seconds
	if Engine.get_physics_frames() % 300 == 0:  # Every 5 seconds at 60fps
		var patrol_count = 0
		var walking_count = 0
		var guarding_count = 0
		var dead_count = 0
		for data in skeleton_data:
			var skeleton = data["skeleton"]
			if not is_instance_valid(skeleton):
				dead_count += 1
			else:
				match data["state"]:
					SkeletonState.PATROLLING_SPAWN:
						patrol_count += 1
					SkeletonState.WALKING_TO_RUINS:
						walking_count += 1
					SkeletonState.GUARDING_RUINS:
						guarding_count += 1
		# Status logging disabled - was spamming console
		pass

# ═══════════════════════════════════════════════════════════════════════════
# SKELETON MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func spawn_skeleton(index: int) -> void:
	"""Spawn a skeleton at a random valid location"""
	if not skeleton_scene:
		push_error("❌ Skeleton scene not loaded!")
		return

	var spawn_pos = find_valid_spawn_position()

	var skeleton = skeleton_scene.instantiate()
	if not skeleton:
		push_error("❌ Failed to instantiate skeleton!")
		return

	skeleton.global_position = spawn_pos
	skeleton.name = "RuinsSkeleton_" + str(index)
	skeleton.enemy_level = randi_range(guardian_min_level, guardian_max_level)  # Random level 7-10

	# Add to world (parent is the game world)
	get_parent().add_child(skeleton)

	# Wait a frame for skeleton to initialize
	await get_tree().process_frame

	# Set 120px aggro range for guardians (allows body pulls)
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		ai.aggro_range = 120.0  # Tighter aggro for body pulls

	# Verify skeleton was added
	if not is_instance_valid(skeleton):
		push_error("❌ Skeleton %d became invalid after adding to tree!" % index)
		return

	# Connect death signal
	if skeleton.has_signal("died"):
		skeleton.died.connect(_on_skeleton_died.bind(skeleton))

	# Connect corpse loot signal to game_world
	if skeleton.has_signal("corpse_clicked"):
		var game_world = get_parent()
		if game_world and game_world.has_method("_on_corpse_clicked"):
			skeleton.corpse_clicked.connect(game_world._on_corpse_clicked)

	# Register with NetworkEnemyManager for loot system
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(skeleton)
		# Broadcast spawn to clients in multiplayer
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_on_clients.rpc(network_id, spawn_pos, skeleton.enemy_level, skeleton.name)

	# Calculate random guard position sporadically across the ruins area
	var angle = randf() * TAU  # Random angle
	var guard_distance = randf_range(80.0, 200.0)  # Random distance from center (some close, some far)
	var guard_position = global_position + Vector2(cos(angle), sin(angle)) * guard_distance

	# Store skeleton data
	var data = {
		"skeleton": skeleton,
		"respawn_timer": 0.0,
		"state": SkeletonState.PATROLLING_SPAWN,
		"patrol_timer": patrol_before_ruins_time,
		"spawn_position": spawn_pos,
		"guard_position": guard_position,
		"index": index,
		"last_position": spawn_pos,
		"stuck_timer": 0.0,
		"stuck_check_interval": 3.0,  # Check every 3 seconds
		"stuck_distance_threshold": 30.0  # Must move at least 30 units in 3 seconds
	}
	skeleton_data.append(data)

func find_valid_spawn_position() -> Vector2:
	"""Find a random position that avoids campfire and path"""
	var max_attempts = 50
	var attempts = 0

	while attempts < max_attempts:
		attempts += 1

		# Random position around ruins
		var angle = randf() * TAU
		var distance = randf_range(spawn_min_distance, spawn_max_distance)
		var pos = global_position + Vector2(cos(angle), sin(angle)) * distance

		# Check if too close to main campfire
		var dist_to_campfire = pos.distance_to(main_campfire_position)
		if dist_to_campfire < avoid_campfire_radius:
			continue

		# Check if on path (paths are roughly along y=0, so avoid that area)
		if abs(pos.y) < avoid_path_distance:
			continue

		# Valid position found
		return pos

	# Fallback: just spawn somewhere
	var fallback_angle = randf() * TAU
	return global_position + Vector2(cos(fallback_angle), sin(fallback_angle)) * spawn_min_distance

func update_skeletons(delta: float) -> void:
	"""Update all skeleton AI states and respawn timers"""
	for data in skeleton_data:
		var skeleton = data["skeleton"]

		# Handle respawn timer
		if not is_instance_valid(skeleton):
			data["respawn_timer"] += delta
			if data["respawn_timer"] >= skeleton_respawn_time:
				# Respawn skeleton (non-blocking)
				data["respawn_timer"] = 0.0
				respawn_skeleton_async(data)
			continue

		if skeleton.has_method("get") and skeleton.get("is_dying"):
			data["respawn_timer"] += delta
			if data["respawn_timer"] >= skeleton_respawn_time:
				# Respawn skeleton (non-blocking)
				data["respawn_timer"] = 0.0
				respawn_skeleton_async(data)
			continue

		# Update skeleton state machine
		match data["state"]:
			SkeletonState.PATROLLING_SPAWN:
				update_skeleton_patrol_spawn(data, delta)
			SkeletonState.WALKING_TO_RUINS:
				update_skeleton_walking_to_ruins(data, delta)
			SkeletonState.GUARDING_RUINS:
				update_skeleton_guarding_ruins(data, delta)

func update_skeleton_patrol_spawn(data: Dictionary, delta: float) -> void:
	"""Skeleton patrols near spawn for a few seconds"""
	var skeleton = data["skeleton"]

	# If skeleton entered combat, skip to guarding state
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		if ai.is_in_combat:
			data["state"] = SkeletonState.GUARDING_RUINS
			return

	# If in campfire mode, skip patrol and head directly to campfire
	if current_state == RuinsState.CAMPFIRE:
		data["state"] = SkeletonState.WALKING_TO_RUINS
		# Reset stuck detection for the new state
		data["stuck_timer"] = 0.0
		data["last_position"] = skeleton.global_position
		return

	data["patrol_timer"] -= delta

	if data["patrol_timer"] <= 0:
		# Time to walk to ruins
		data["state"] = SkeletonState.WALKING_TO_RUINS
		# Reset stuck detection for the new state
		data["stuck_timer"] = 0.0
		data["last_position"] = skeleton.global_position
		# print("  💀 Skeleton %d heading to ruins" % data["index"])

func update_skeleton_walking_to_ruins(data: Dictionary, delta: float) -> void:
	"""Skeleton walks toward ruins"""
	var skeleton = data["skeleton"]
	if not is_instance_valid(skeleton):
		return

	# Get guard position first (needed for stuck detection)
	var guard_pos = data["guard_position"]

	# If skeleton is in combat, stop controlling them - let AI handle combat
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		if ai.is_in_combat:
			# Skeleton is fighting, skip to guarding state so we stop interfering
			data["state"] = SkeletonState.GUARDING_RUINS
			return

	# Check if stuck (not moving much)
	data["stuck_timer"] += delta
	if data["stuck_timer"] >= data["stuck_check_interval"]:
		var distance_moved = skeleton.global_position.distance_to(data["last_position"])
		if distance_moved < data["stuck_distance_threshold"]:
			# Skeleton is stuck! Physically move backwards and shift on Y axis
			# print("  ⚠️ Skeleton %d stuck, repositioning..." % data["index"])

			# Move backwards (opposite of current velocity direction)
			var backward_direction = -skeleton.velocity.normalized() if skeleton.velocity.length() > 0 else Vector2(-1, 0)
			skeleton.global_position += backward_direction * 40.0  # Move back 40 pixels

			# Shift up or down on Y axis randomly
			var y_shift = randf_range(-50.0, 50.0)
			skeleton.global_position.y += y_shift

			# Try picking a new path via AI
			if skeleton.has_node("EnemyAI"):
				var ai = skeleton.get_node("EnemyAI")
				# Now try going to the target again after physical repositioning
				ai.patrol_target = guard_pos
				ai.is_paused = false

		data["last_position"] = skeleton.global_position
		data["stuck_timer"] = 0.0

	var distance_to_guard_spot = skeleton.global_position.distance_to(guard_pos)

	# Check if reached designated guard position (larger threshold to avoid getting stuck trying to reach exact spot)
	if distance_to_guard_spot < 80.0:
		# Arrived at guard position
		data["state"] = SkeletonState.GUARDING_RUINS

		# Update AI to patrol around their designated spot
		if skeleton.has_node("EnemyAI"):
			var ai = skeleton.get_node("EnemyAI")
			ai.spawn_position = guard_pos  # Patrol around guard spot, not ruins center
			ai.patrol_radius = 60.0  # Patrol radius around their spot (increased for more spread)
			ai.pick_new_patrol_target()

	else:
		# Override AI's patrol target to go to their guard position
		if skeleton.has_node("EnemyAI"):
			var ai = skeleton.get_node("EnemyAI")
			# CRITICAL FIX: Set spawn_position so AI knows where to patrol from
			# Without this, spawn_position might be (0,0) and AI won't move properly
			ai.spawn_position = skeleton.global_position

			# Make sure AI is in patrol state and actively moving
			if ai.current_state != ai.State.PATROLLING:
				ai.change_state(ai.State.PATROLLING)
			ai.patrol_target = guard_pos
			ai.is_paused = false  # Make sure not paused

			# If we're very close to patrol_target (within 10 units), pick a new one
			# This prevents the AI from thinking it's "done" and stopping
			var dist_to_target = skeleton.global_position.distance_to(ai.patrol_target)
			if dist_to_target < 10.0:
				ai.patrol_target = guard_pos

func update_skeleton_guarding_ruins(data: Dictionary, delta: float) -> void:
	"""Skeleton patrols around their designated guard spot"""
	var skeleton = data["skeleton"]
	if not is_instance_valid(skeleton):
		return

	# Only update spawn position if not in combat
	# When in combat, let AI handle everything naturally
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		if not ai.is_in_combat:
			# AI handles patrolling around guard position automatically
			# Just ensure spawn position stays at their designated guard spot
			ai.spawn_position = data["guard_position"]

func respawn_skeleton_async(data: Dictionary) -> void:
	"""Trigger async respawn without blocking physics process"""
	_do_respawn_skeleton(data)

func _do_respawn_skeleton(data: Dictionary) -> void:
	"""Internal async respawn handler"""
	await respawn_skeleton(data)

func respawn_skeleton(data: Dictionary) -> void:
	"""Respawn a dead skeleton"""
	var spawn_pos = data["spawn_position"]

	var skeleton = skeleton_scene.instantiate()
	skeleton.global_position = spawn_pos
	skeleton.name = "RuinsSkeleton_" + str(data["index"])
	skeleton.enemy_level = randi_range(guardian_min_level, guardian_max_level)  # Random level 7-10

	get_parent().add_child(skeleton)

	# Wait for skeleton to initialize
	await get_tree().process_frame

	# Set 120px aggro range for guardians (allows body pulls)
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		ai.aggro_range = 120.0  # Tighter aggro for body pulls

	if skeleton.has_signal("died"):
		skeleton.died.connect(_on_skeleton_died.bind(skeleton))

	# Connect corpse loot signal to game_world
	if skeleton.has_signal("corpse_clicked"):
		var game_world = get_parent()
		if game_world and game_world.has_method("_on_corpse_clicked"):
			skeleton.corpse_clicked.connect(game_world._on_corpse_clicked)

	# Register with NetworkEnemyManager for loot system
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(skeleton)
		# Broadcast spawn to clients in multiplayer
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_on_clients.rpc(network_id, spawn_pos, skeleton.enemy_level, skeleton.name)

	data["skeleton"] = skeleton
	data["state"] = SkeletonState.PATROLLING_SPAWN
	data["patrol_timer"] = patrol_before_ruins_time
	data["last_position"] = spawn_pos
	data["stuck_timer"] = 0.0

func _on_skeleton_died(skeleton: Node) -> void:
	"""Called when a skeleton dies"""
	has_killed_skeleton = true

func update_ruins_light() -> void:
	"""Scale ruins light based on time of day"""
	if not ruins_light or not is_instance_valid(ruins_light):
		return

	# Get day/night brightness factor from TimeManager
	var time_brightness = 1.0
	if TimeManager and TimeManager.canvas_modulate:
		time_brightness = TimeManager.get_brightness()

	# Map: night (0.51) -> MAX, day (0.99) -> MIN
	var day_factor = inverse_lerp(0.51, 0.99, time_brightness)
	day_factor = clamp(day_factor, 0.0, 1.0)
	ruins_light.energy = lerp(MAX_RUINS_LIGHT_ENERGY, MIN_RUINS_LIGHT_ENERGY, day_factor)
	# Scale light radius - bigger glow at night
	var base_texture_scale = lerp(4.5, 2.5, day_factor)  # 4.5x at night, 2.5x at day
	ruins_light.texture_scale = base_texture_scale

# ═══════════════════════════════════════════════════════════════════════════
# STATE CONVERSION
# ═══════════════════════════════════════════════════════════════════════════

func convert_to_campfire() -> void:
	"""Convert ruins to campfire - initiates multiplayer sync if needed"""
	if current_state == RuinsState.CAMPFIRE:
		return

	# Require player to kill at least one skeleton first
	if not has_killed_skeleton:
		return

	# In multiplayer, sync the conversion to all players
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			# Server: perform conversion and broadcast to clients
			_do_convert_to_campfire()
			_sync_convert_to_campfire.rpc()
		else:
			# Client: request server to convert
			_request_convert_to_campfire.rpc_id(1)
	else:
		# Single player: just convert
		_do_convert_to_campfire()

@rpc("any_peer", "reliable")
func _request_convert_to_campfire() -> void:
	"""Client requests server to convert ruins to campfire"""
	if not multiplayer.is_server():
		return

	# Validate that this client has killed a skeleton (server tracks this)
	# For now, trust the client since has_killed_skeleton is set by _on_skeleton_died
	if not has_killed_skeleton:
		return

	_do_convert_to_campfire()
	_sync_convert_to_campfire.rpc()

@rpc("authority", "reliable", "call_local")
func _sync_convert_to_campfire() -> void:
	"""Server broadcasts campfire conversion to all clients"""
	_do_convert_to_campfire()

func _do_convert_to_campfire() -> void:
	"""Actually perform the conversion (called on all peers)"""
	if current_state == RuinsState.CAMPFIRE:
		return

	current_state = RuinsState.CAMPFIRE
	player_last_near_time = Time.get_ticks_msec() / 1000.0
	time_since_player_near = 0.0

	# Hide ruins, show campfire
	if ruins_sprite:
		ruins_sprite.visible = false

	create_campfire_visual()

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	print("🏛️➡️🔥 Ruins converted to campfire at %s" % global_position)

func convert_to_ruins() -> void:
	"""Convert campfire back to ruins - initiates multiplayer sync if needed"""
	if current_state == RuinsState.RUINS:
		return

	# In multiplayer, only server can trigger reversion (abandonment check)
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_do_convert_to_ruins()
			_sync_convert_to_ruins.rpc()
	else:
		_do_convert_to_ruins()

@rpc("authority", "reliable", "call_local")
func _sync_convert_to_ruins() -> void:
	"""Server broadcasts ruins reversion to all clients"""
	_do_convert_to_ruins()

func _do_convert_to_ruins() -> void:
	"""Actually perform the reversion (called on all peers)"""
	if current_state == RuinsState.RUINS:
		return

	current_state = RuinsState.RUINS

	# Show ruins, hide campfire
	if ruins_sprite:
		ruins_sprite.visible = true

	if campfire_node:
		campfire_node.queue_free()
		campfire_node = null

	print("🔥➡️🏛️ Campfire reverted to ruins at %s" % global_position)

func check_abandonment(delta: float) -> void:
	"""Check if ALL players have abandoned the campfire (multiplayer aware)"""
	# Calculate scaled abandonment time based on fuel levels
	var current_abandon_time = base_abandon_time
	if campfire_node and is_instance_valid(campfire_node):
		if campfire_node.has_method("get_fuel_level_percent"):
			var fuel_percent = campfire_node.get_fuel_level_percent()
			# Scale from base_abandon_time to max_abandon_time based on fuel
			current_abandon_time = base_abandon_time + (max_abandon_time - base_abandon_time) * fuel_percent

	# Check if ANY player is near the campfire
	var any_player_near = false
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	for p in all_players:
		if is_instance_valid(p):
			var distance = p.global_position.distance_to(global_position)
			if distance < convert_range * 2.0:  # Twice the convert range
				any_player_near = true
				break

	if any_player_near:
		# At least one player is near
		player_last_near_time = Time.get_ticks_msec() / 1000.0
		time_since_player_near = 0.0
	else:
		# No players near
		time_since_player_near += delta
		if time_since_player_near >= current_abandon_time:
			convert_to_ruins()

# ═══════════════════════════════════════════════════════════════════════════
# INTERACTION
# ═══════════════════════════════════════════════════════════════════════════

func create_interaction_area() -> void:
	"""Create area for player interaction"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	add_child(interaction_area)

	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = convert_range
	collision.shape = shape
	interaction_area.add_child(collision)

	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)

func create_interaction_prompt() -> void:
	"""Create floating prompt above ruins"""
	# Create a Node2D container positioned above the ruins
	var prompt_container = Node2D.new()
	prompt_container.name = "PromptContainer"
	prompt_container.position = Vector2(0, -120)  # Above ruins
	add_child(prompt_container)

	# Create CanvasLayer for the label
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	prompt_container.add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Destroy ruins and build campfire"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color.WHITE)
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_interaction_prompt() -> void:
	"""Update interaction prompt visibility"""
	if not interaction_prompt:
		return

	# Only show in ruins mode
	if current_state != RuinsState.RUINS:
		interaction_prompt.visible = false
		return

	# Check if player is near
	if not player or not is_instance_valid(player):
		interaction_prompt.visible = false
		return

	var distance = player.global_position.distance_to(global_position)

	if distance < convert_range:
		interaction_prompt.visible = true
		# Center the label on screen
		var viewport_size = get_viewport().get_visible_rect().size
		var camera = get_viewport().get_camera_2d()
		if camera:
			# Calculate screen position of prompt relative to camera
			var world_pos = global_position + Vector2(0, -120)
			var camera_pos = camera.global_position
			var screen_center = viewport_size / 2
			var relative_pos = (world_pos - camera_pos) * camera.zoom.x + screen_center
			# Center prompt (wait for size to be calculated)
			var offset = Vector2.ZERO
			if interaction_prompt.size.x > 0:
				offset = interaction_prompt.size / 2
			interaction_prompt.position = relative_pos - offset
	else:
		interaction_prompt.visible = false

func _on_interaction_body_entered(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player = body

func _on_interaction_body_exited(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER) and body == player:
		pass  # Don't clear player reference

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		# Only handle F-key if player is close enough to convert ruins
		if current_state == RuinsState.RUINS and player:
			var distance = player.global_position.distance_to(global_position)
			if distance < convert_range:
				convert_to_campfire()
				get_viewport().set_input_as_handled()  # Mark input as handled

# ═══════════════════════════════════════════════════════════════════════════
# VISUALS
# ═══════════════════════════════════════════════════════════════════════════

func create_ruins_visual() -> void:
	"""Create ruins sprite"""
	ruins_sprite = Sprite2D.new()
	ruins_sprite.name = "RuinsSprite"
	ruins_sprite.texture = load("res://assets/environment/wasteland/ruins.png")
	ruins_sprite.centered = true
	ruins_sprite.offset = Vector2(0, -40)  # Offset so bottom is at position
	add_child(ruins_sprite)

	# Add a subtle glow/highlight circle to make ruins visible from distance
	var highlight = Polygon2D.new()
	highlight.name = "RuinsHighlight"
	highlight.z_index = -1
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments):
		var angle = (i * TAU) / segments
		points.append(Vector2(cos(angle), sin(angle)) * 80)
	highlight.polygon = points
	highlight.color = Color(0.6, 0.5, 0.4, 0.2)  # Subtle brown glow
	ruins_sprite.add_child(highlight)  # Add as child of sprite so it hides with sprite

func create_campfire_visual() -> void:
	"""Create campfire (reuse existing Campfire scene)"""
	var campfire_scene = load("res://scenes/world/campfire.tscn")
	if campfire_scene:
		campfire_node = campfire_scene.instantiate()
		campfire_node.name = "Campfire"

		# Disable enemy deterrence for ruins campfire (enemies can chase player into it)
		if "enable_deterrence" in campfire_node:
			campfire_node.enable_deterrence = false

		# Ruins campfires are COMPETITIVE (ownership-based), not community
		# Override the scene default since campfire.tscn is set to community for home campfire
		if "is_community_campfire" in campfire_node:
			campfire_node.is_community_campfire = false

		add_child(campfire_node)
	else:
		push_error("❌ Could not load campfire.tscn!")
