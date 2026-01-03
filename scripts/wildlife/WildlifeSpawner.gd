class_name WildlifeSpawner
extends Node2D
## Spawns and manages wildlife animals in a zone
## SERVER-AUTHORITATIVE: Only spawns on server, synced via NetworkWildlifeManager

# Spawn configuration
@export var spawn_area_min: Vector2 = Vector2(-2000, -9500)  # Top-left of spawn zone
@export var spawn_area_max: Vector2 = Vector2(2000, -6000)   # Bottom-right of spawn zone
@export var max_animals: int = 12
@export var spawn_interval: float = 3.0  # Seconds between spawn attempts
@export var player_proximity_required: float = 2500.0  # Only spawn if player within this range
@export var despawn_distance: float = 4000.0  # Despawn animals this far from all players

# Spawn weights (higher = more common)
@export var rabbit_weight: int = 60
@export var fox_weight: int = 40

# State
var active_animals: Array[Node] = []
var spawn_timer: float = 0.0
var total_weight: int = 0

# Reference to NetworkWildlifeManager
var network_manager: Node = null


func _ready() -> void:
	total_weight = rabbit_weight + fox_weight
	# Stagger initial spawn
	spawn_timer = randf_range(0.5, 2.0)

	# Get NetworkWildlifeManager reference
	network_manager = get_node_or_null("/root/NetworkWildlifeManager")


func _is_server() -> bool:
	"""Check if we're the server or in single-player."""
	if not multiplayer.has_multiplayer_peer():
		return true  # Single player acts as server
	return multiplayer.is_server()


func _process(delta: float) -> void:
	# Only server spawns wildlife
	if not _is_server():
		return

	spawn_timer -= delta

	if spawn_timer <= 0:
		spawn_timer = spawn_interval
		_cleanup_dead_animals()
		_despawn_far_animals()
		_try_spawn_animal()


func _cleanup_dead_animals() -> void:
	# Remove invalid/freed references
	active_animals = active_animals.filter(func(a): return is_instance_valid(a))


func _despawn_far_animals() -> void:
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	if players.is_empty():
		return

	for animal in active_animals.duplicate():
		if not is_instance_valid(animal):
			continue

		var min_distance = INF
		for player in players:
			var dist = animal.global_position.distance_to(player.global_position)
			min_distance = min(min_distance, dist)

		if min_distance > despawn_distance:
			# Unregister from network manager before freeing
			if network_manager and animal.has_meta("network_id"):
				network_manager.unregister_wildlife(animal.get_meta("network_id"))
			animal.queue_free()
			active_animals.erase(animal)


func _try_spawn_animal() -> void:
	if active_animals.size() >= max_animals:
		return

	# Check if any player is close enough
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	var player_nearby = false
	var nearest_player: Node2D = null
	var nearest_dist: float = INF

	for player in players:
		var dist = player.global_position.distance_to(_get_zone_center())
		if dist < player_proximity_required:
			player_nearby = true
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_player = player

	if not player_nearby:
		return

	# Find spawn position away from player
	var spawn_pos = _get_spawn_position(nearest_player)
	if spawn_pos == Vector2.ZERO:
		return

	# Roll for animal type
	var animal_type = _roll_animal_type()

	# Spawn via NetworkWildlifeManager if available (multiplayer)
	# Otherwise spawn directly (single player)
	var animal: Node = null

	if network_manager:
		animal = network_manager.spawn_wildlife_server(animal_type, spawn_pos, get_parent())
	else:
		# Single player fallback - spawn directly
		animal = _spawn_local(animal_type, spawn_pos)

	if animal:
		active_animals.append(animal)
		# Connect death signal for cleanup
		if animal.has_signal("animal_died"):
			animal.animal_died.connect(_on_animal_died)


func _spawn_local(animal_type: String, spawn_pos: Vector2) -> Node:
	"""Single-player spawn without network manager."""
	var scene: PackedScene = null
	match animal_type:
		"rabbit":
			scene = load("res://scenes/wildlife/Rabbit.tscn")
		"fox":
			scene = load("res://scenes/wildlife/Fox.tscn")

	if not scene:
		return null

	var animal = scene.instantiate()
	animal.global_position = spawn_pos
	get_parent().add_child(animal)
	return animal


func _get_zone_center() -> Vector2:
	return (spawn_area_min + spawn_area_max) / 2.0


func _get_spawn_position(avoid_player: Node2D = null) -> Vector2:
	# Try to find a valid spawn position
	for _attempt in range(10):
		var pos = Vector2(
			randf_range(spawn_area_min.x, spawn_area_max.x),
			randf_range(spawn_area_min.y, spawn_area_max.y)
		)

		# Make sure it's not too close to player
		if avoid_player:
			if pos.distance_to(avoid_player.global_position) < 500.0:
				continue

		# Make sure it's not too close to other animals
		var too_close = false
		for animal in active_animals:
			if is_instance_valid(animal) and pos.distance_to(animal.global_position) < 200.0:
				too_close = true
				break

		if not too_close:
			return pos

	return Vector2.ZERO  # Failed to find position


func _roll_animal_type() -> String:
	var roll = randi() % total_weight

	if roll < rabbit_weight:
		return "rabbit"
	else:
		return "fox"


func _on_animal_died(animal: Node, _killer: Node) -> void:
	active_animals.erase(animal)


# === DEBUG ===

func get_spawn_info() -> Dictionary:
	return {
		"active_animals": active_animals.size(),
		"max_animals": max_animals,
		"spawn_area": {"min": spawn_area_min, "max": spawn_area_max},
		"is_server": _is_server()
	}
