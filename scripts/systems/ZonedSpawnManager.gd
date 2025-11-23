extends Node
class_name ZonedSpawnManager

## MMO-Style Zoned Spawn Manager
## Only spawns enemies in zones near player, level-appropriate, with density control

# Configuration
@export var max_active_enemies: int = 50  # Total enemies active at once
@export var zone_size: float = 2000.0  # Size of each spawn zone (2000x2000)
@export var active_zone_radius: int = 1  # Load zones within N zones of player (1 = 3x3 grid)
@export var enemies_per_zone: int = 5  # Max enemies per zone

@export var enemy_scene: PackedScene  # Default enemy type

# Zone data structure
var spawn_zones: Dictionary = {}  # zone_key -> {spawn_points: Array, enemies: Array, level_range: Vector2i}
var active_zones: Array[String] = []  # Currently loaded zone keys
var player: Node = null

# Spawn point collection
var all_spawn_points: Array[Dictionary] = []  # {position: Vector2, level: int, zone_key: String}

# Performance
var update_timer: float = 0.0
var update_interval: float = 2.0  # Check zones every 2 seconds
var respawn_timer: float = 0.0
var respawn_interval: float = 1.0  # Check respawns every second

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Collect all spawn points from game world
	await get_tree().process_frame
	collect_spawn_points()
	organize_into_zones()

	print("🗺️ ZonedSpawnManager: %d spawn points in %d zones" % [
		all_spawn_points.size(),
		spawn_zones.size()
	])

func _physics_process(delta: float) -> void:
	# Update active zones based on player position
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_active_zones()

	# Check for respawns in active zones
	respawn_timer += delta
	if respawn_timer >= respawn_interval:
		respawn_timer = 0.0
		check_respawns()

func collect_spawn_points() -> void:
	"""Scan game world for all EnemySpawnPoint markers"""
	var root = get_tree().root
	var spawn_markers = find_all_spawn_points(root)

	for marker in spawn_markers:
		if not is_instance_valid(marker):
			continue

		# Determine level based on distance from origin (simple heuristic)
		var distance_from_origin = marker.global_position.length()
		var level = 1 + int(distance_from_origin / 1000.0)  # Every 1000px = +1 level
		level = clampi(level, 1, 20)  # Cap at level 20

		all_spawn_points.append({
			"position": marker.global_position,
			"level": level,
			"marker": marker,
			"zone_key": get_zone_key(marker.global_position),
			"occupied": false,
			"enemy": null
		})

	print("📍 Found %d spawn points" % all_spawn_points.size())

func find_all_spawn_points(node: Node) -> Array:
	"""Recursively find all nodes named 'EnemySpawnPoint' or in 'spawn_points' group"""
	var result = []

	# Check if this node is a spawn point
	if node.name.contains("SpawnPoint") or node.name.contains("EnemySpawn"):
		result.append(node)

	if node.is_in_group("spawn_points"):
		result.append(node)

	# Recurse children
	for child in node.get_children():
		result.append_array(find_all_spawn_points(child))

	return result

func organize_into_zones() -> void:
	"""Group spawn points into spatial zones"""
	for spawn_data in all_spawn_points:
		var zone_key = spawn_data["zone_key"]

		if not spawn_zones.has(zone_key):
			spawn_zones[zone_key] = {
				"spawn_points": [],
				"enemies": [],
				"level_range": Vector2i(999, 0)
			}

		var zone = spawn_zones[zone_key]
		zone["spawn_points"].append(spawn_data)

		# Update level range
		var level = spawn_data["level"]
		zone["level_range"].x = mini(zone["level_range"].x, level)
		zone["level_range"].y = maxi(zone["level_range"].y, level)

	# Print zone info
	for zone_key in spawn_zones.keys():
		var zone = spawn_zones[zone_key]
		print("  Zone %s: %d spawns, levels %d-%d" % [
			zone_key,
			zone["spawn_points"].size(),
			zone["level_range"].x,
			zone["level_range"].y
		])

func get_zone_key(pos: Vector2) -> String:
	"""Get zone key from world position"""
	var zone_x = int(pos.x / zone_size)
	var zone_y = int(pos.y / zone_size)
	return "%d,%d" % [zone_x, zone_y]

func get_neighboring_zones(center_zone_key: String) -> Array[String]:
	"""Get all zones within active_zone_radius"""
	var parts = center_zone_key.split(",")
	var center_x = int(parts[0])
	var center_y = int(parts[1])

	var neighbors: Array[String] = []
	for dx in range(-active_zone_radius, active_zone_radius + 1):
		for dy in range(-active_zone_radius, active_zone_radius + 1):
			var zone_key = "%d,%d" % [center_x + dx, center_y + dy]
			if spawn_zones.has(zone_key):
				neighbors.append(zone_key)

	return neighbors

func update_active_zones() -> void:
	"""Activate zones near player, deactivate distant ones"""
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if not player:
			return

	var player_zone = get_zone_key(player.global_position)
	var should_be_active = get_neighboring_zones(player_zone)

	# Activate new zones
	for zone_key in should_be_active:
		if not active_zones.has(zone_key):
			activate_zone(zone_key)

	# Deactivate distant zones
	var to_deactivate = []
	for zone_key in active_zones:
		if not should_be_active.has(zone_key):
			to_deactivate.append(zone_key)

	for zone_key in to_deactivate:
		deactivate_zone(zone_key)

func activate_zone(zone_key: String) -> void:
	"""Start spawning enemies in this zone"""
	if not spawn_zones.has(zone_key):
		return

	active_zones.append(zone_key)
	var zone = spawn_zones[zone_key]

	print("✅ Activating zone %s (levels %d-%d)" % [
		zone_key,
		zone["level_range"].x,
		zone["level_range"].y
	])

	# Spawn initial enemies for this zone
	spawn_enemies_in_zone(zone_key)

func deactivate_zone(zone_key: String) -> void:
	"""Stop spawning and despawn enemies in this zone"""
	if not spawn_zones.has(zone_key):
		return

	active_zones.erase(zone_key)
	var zone = spawn_zones[zone_key]

	print("❌ Deactivating zone %s" % zone_key)

	# Despawn all enemies in this zone
	for spawn_data in zone["spawn_points"]:
		if spawn_data["occupied"] and is_instance_valid(spawn_data["enemy"]):
			spawn_data["enemy"].queue_free()
			spawn_data["occupied"] = false
			spawn_data["enemy"] = null

func spawn_enemies_in_zone(zone_key: String) -> void:
	"""Spawn enemies at random spawn points in zone"""
	if not spawn_zones.has(zone_key):
		return

	var zone = spawn_zones[zone_key]
	var spawn_points = zone["spawn_points"]

	# Count how many enemies already spawned
	var current_count = 0
	for spawn_data in spawn_points:
		if spawn_data["occupied"] and is_instance_valid(spawn_data["enemy"]):
			current_count += 1

	# Spawn up to enemies_per_zone
	var to_spawn = enemies_per_zone - current_count
	if to_spawn <= 0:
		return

	# Get available spawn points
	var available = []
	for spawn_data in spawn_points:
		if not spawn_data["occupied"]:
			available.append(spawn_data)

	# Shuffle and pick random points
	available.shuffle()
	to_spawn = mini(to_spawn, available.size())

	for i in range(to_spawn):
		spawn_enemy_at_point(available[i])

func spawn_enemy_at_point(spawn_data: Dictionary) -> void:
	"""Spawn a single enemy at a spawn point"""
	if not enemy_scene:
		push_error("No enemy_scene set on ZonedSpawnManager!")
		return

	# Check global enemy limit
	var total_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES).size()
	if total_enemies >= max_active_enemies:
		return  # Hit global limit

	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_data["position"]

	# Set level
	if enemy.has_method("set"):
		enemy.set("enemy_level", spawn_data["level"])

	# Add to scene
	get_tree().root.add_child(enemy)

	# Track
	spawn_data["occupied"] = true
	spawn_data["enemy"] = enemy

	# Connect death signal
	if enemy.has_signal("died"):
		enemy.died.connect(func(): _on_enemy_died(spawn_data))

func _on_enemy_died(spawn_data: Dictionary) -> void:
	"""Handle enemy death - mark spawn point available for respawn"""
	spawn_data["occupied"] = false
	spawn_data["enemy"] = null

	# Respawn will happen automatically in check_respawns()

func check_respawns() -> void:
	"""Check active zones for respawn opportunities"""
	for zone_key in active_zones:
		if not spawn_zones.has(zone_key):
			continue

		spawn_enemies_in_zone(zone_key)

func get_active_enemy_count() -> int:
	"""Count total active enemies"""
	return get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES).size()
