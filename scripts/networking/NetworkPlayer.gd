extends Node2D
# NetworkPlayer.gd - Wrapper for multiplayer players

class_name NetworkPlayer

@export var player_id: int = 1
@export var player_name: String = "Player"
@export var is_local: bool = false

# Reference to the actual Player scene
var player_instance = null
var player_scene = preload("res://scenes/player/player.tscn")

# Sync variables
var sync_position: Vector2 = Vector2.ZERO
var sync_animation: String = "idle_down"
var sync_health: int = 100
var sync_max_health: int = 100
var sync_level: int = 1

# Network interpolation
var last_sync_time: float = 0.0
var interpolation_speed: float = 10.0

func _ready():
	name = "Player_" + str(player_id)
	set_multiplayer_authority(player_id)

	# Spawn the actual player
	player_instance = player_scene.instantiate()
	add_child(player_instance)

	# Setup based on ownership
	if is_multiplayer_authority():
		# This is our player
		is_local = true
		player_instance.set_process(true)
		player_instance.set_physics_process(true)

		# Ensure camera follows this player
		if player_instance.has_node("Camera2D"):
			player_instance.get_node("Camera2D").enabled = true

		print("Spawned local player: %s (ID: %d)" % [player_name, player_id])
	else:
		# Remote player
		is_local = false
		player_instance.set_process(false)
		player_instance.set_physics_process(false)

		# Disable camera for remote players
		if player_instance.has_node("Camera2D"):
			player_instance.get_node("Camera2D").enabled = false

		# Disable AI/input for remote players
		if player_instance.has_method("disable_input"):
			player_instance.disable_input()

		print("Spawned remote player: %s (ID: %d)" % [player_name, player_id])

	# Set player name label if it exists
	if player_instance.has_node("NameLabel"):
		player_instance.get_node("NameLabel").text = player_name

func _physics_process(delta):
	if not player_instance:
		return

	if is_local:
		# Send our position to others
		if Time.get_ticks_msec() - last_sync_time > 50:  # 20Hz update rate
			_send_position_update()
			last_sync_time = Time.get_ticks_msec()
	else:
		# Interpolate to received position
		player_instance.global_position = player_instance.global_position.lerp(
			sync_position,
			interpolation_speed * delta
		)

		# Update animation if changed
		if player_instance.has_method("play_animation"):
			player_instance.play_animation(sync_animation)

func _send_position_update():
	if not player_instance:
		return

	var pos = player_instance.global_position
	var anim = _get_current_animation()
	var health = _get_player_health()

	rpc("receive_position_update", pos, anim, health)

@rpc("any_peer", "call_local", "unreliable_ordered")
func receive_position_update(pos: Vector2, anim: String, health: int):
	if is_local:
		return  # Ignore our own updates

	sync_position = pos
	sync_animation = anim
	sync_health = health

# Combat synchronization
func take_damage(amount: int, attacker_id: int):
	if not is_local:
		return  # Only process damage locally

	rpc_id(1, "request_damage", player_id, amount, attacker_id)

@rpc("any_peer", "call_local", "reliable")
func request_damage(target_id: int, amount: int, attacker_id: int):
	# Only server processes damage
	if not multiplayer.is_server():
		return

	# Validate and apply damage
	rpc("apply_damage", target_id, amount, attacker_id)

@rpc("authority", "call_local", "reliable")
func apply_damage(target_id: int, amount: int, attacker_id: int):
	if target_id != player_id:
		return

	if player_instance and player_instance.has_method("take_damage"):
		player_instance.take_damage(amount)

		# Check for death
		if _get_player_health() <= 0:
			rpc("handle_death", player_id, attacker_id)

@rpc("authority", "call_local", "reliable")
func handle_death(dead_player_id: int, killer_id: int):
	if dead_player_id != player_id:
		return

	print("%s was killed by Player %d" % [player_name, killer_id])

	# Handle death animation
	if player_instance and player_instance.has_method("die"):
		player_instance.die()

	# Respawn after delay
	if is_local:
		await get_tree().create_timer(5.0).timeout
		request_respawn()

func request_respawn():
	if not is_local:
		return

	rpc_id(1, "server_respawn_player", player_id)

@rpc("any_peer", "call_local", "reliable")
func server_respawn_player(respawn_player_id: int):
	if not multiplayer.is_server():
		return

	# Find a spawn point
	var spawn_point = _get_random_spawn_point()
	rpc("execute_respawn", respawn_player_id, spawn_point)

@rpc("authority", "call_local", "reliable")
func execute_respawn(respawn_player_id: int, spawn_pos: Vector2):
	if respawn_player_id != player_id:
		return

	if player_instance:
		player_instance.global_position = spawn_pos
		if player_instance.has_method("revive"):
			player_instance.revive()
		if player_instance.has_method("restore_health"):
			player_instance.restore_health()

	print("%s respawned at %s" % [player_name, spawn_pos])

# Utility functions
func _get_current_animation() -> String:
	if player_instance and player_instance.has_method("get_current_animation"):
		return player_instance.get_current_animation()
	return "idle_down"

func _get_player_health() -> int:
	if player_instance:
		if player_instance.has_method("get_health"):
			return player_instance.get_health()
		elif player_instance.get("health") != null:
			return player_instance.health
	return sync_health

func _get_random_spawn_point() -> Vector2:
	# Get spawn points from game world
	var game_world = get_node("/root/GameWorld")
	if game_world and game_world.has_method("get_spawn_points"):
		var points = game_world.get_spawn_points()
		if points.size() > 0:
			return points[randi() % points.size()]

	# Default spawn area around campfire
	var angle = randf() * TAU
	var distance = 200 + randf() * 100
	return Vector2(cos(angle) * distance, sin(angle) * distance)

func set_player_name_display(name: String):
	player_name = name
	if player_instance and player_instance.has_node("NameLabel"):
		player_instance.get_node("NameLabel").text = name

func get_player_position() -> Vector2:
	if player_instance:
		return player_instance.global_position
	return Vector2.ZERO
