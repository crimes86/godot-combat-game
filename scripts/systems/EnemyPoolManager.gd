extends Node
class_name EnemyPoolManager

## Aggressive Enemy Pool Management
## Only keeps nearby enemies active, despawns distant ones
## Critical for performance with 1000+ enemies in scene

const MAX_ACTIVE_ENEMIES: int = 50  # Maximum enemies active at once
const ACTIVATION_RADIUS: float = 1500.0  # Spawn enemies within this radius
const DEACTIVATION_RADIUS: float = 2000.0  # Despawn enemies beyond this radius

# Pools
var active_enemies: Array[Node] = []
var inactive_enemy_data: Array[Dictionary] = []  # Store enemy position/type when despawned

# Performance
var update_timer: float = 0.0
var update_interval: float = 1.0  # Check once per second

var player: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("⚡ EnemyPoolManager initialized (max %d active enemies)" % MAX_ACTIVE_ENEMIES)

func _physics_process(delta: float) -> void:
	update_timer += delta
	if update_timer < update_interval:
		return

	update_timer = 0.0

	# Get player
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if not player:
			return

	# Update enemy pool
	update_enemy_pool()

func update_enemy_pool() -> void:
	"""Activate nearby enemies, deactivate distant ones"""
	var player_pos = player.global_position

	# Get all enemies in scene
	var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	active_enemies.clear()

	# Collect active enemies and their distances
	var enemy_distances: Array[Dictionary] = []

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		var distance = enemy.global_position.distance_to(player_pos)
		enemy_distances.append({
			"enemy": enemy,
			"distance": distance
		})

	# Sort by distance (closest first)
	enemy_distances.sort_custom(func(a, b): return a["distance"] < b["distance"])

	# Keep only closest MAX_ACTIVE_ENEMIES active
	var kept_count = 0
	var disabled_count = 0

	for data in enemy_distances:
		var enemy = data["enemy"]
		var distance = data["distance"]

		if kept_count < MAX_ACTIVE_ENEMIES and distance < ACTIVATION_RADIUS:
			# Keep active
			activate_enemy(enemy)
			kept_count += 1
		else:
			# Deactivate to save performance
			deactivate_enemy(enemy)
			disabled_count += 1

	if disabled_count > 0:
		print("🔄 EnemyPool: %d active, %d disabled (saved %.0f%% CPU)" % [
			kept_count,
			disabled_count,
			(float(disabled_count) / float(kept_count + disabled_count)) * 100.0
		])

func activate_enemy(enemy: Node) -> void:
	"""Enable enemy processing"""
	if not is_instance_valid(enemy):
		return

	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.visible = true

	# Enable AI
	if enemy.has_node("EnemyAI"):
		var ai = enemy.get_node("EnemyAI")
		ai.process_mode = Node.PROCESS_MODE_INHERIT

	active_enemies.append(enemy)

func deactivate_enemy(enemy: Node) -> void:
	"""Disable enemy processing to save CPU"""
	if not is_instance_valid(enemy):
		return

	# CRITICAL: Completely pause processing
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemy.visible = false  # Also hide for rendering performance

	# Stop AI
	if enemy.has_node("EnemyAI"):
		var ai = enemy.get_node("EnemyAI")
		ai.process_mode = Node.PROCESS_MODE_DISABLED

	# Clear velocity
	if enemy is CharacterBody2D:
		enemy.velocity = Vector2.ZERO

func get_active_count() -> int:
	return active_enemies.size()
