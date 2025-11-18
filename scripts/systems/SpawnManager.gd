extends Node
class_name SpawnManager

## Multiplayer-Ready Enemy Spawn Manager
##
## This system manages enemy spawning/despawning based on player proximity.
## Designed to work in single-player now, but structured for easy multiplayer migration.
##
## Architecture:
## - Server-authoritative: All spawn decisions happen here (will move to server in multiplayer)
## - Area of Interest (AOI): Enemies spawn when ANY player is nearby
## - State preservation: Dead/looted enemies tracked and won't respawn
## - Priority spawning: Closest enemies spawn first when at budget cap
##
## Future Multiplayer Migration:
## 1. Move this script to run on server only
## 2. Sync player_positions from all clients
## 3. Broadcast spawn/despawn commands to clients
## 4. Sync enemy state changes (damage, death, loot)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Maximum active enemies in the world at once
## Single-player: 50-75 enemies
## Multiplayer: Scale up (e.g., 75 per player = 150 for 2 players, 225 for 3 players)
@export var max_active_enemies: int = 75

## Spawn radius around players (px)
## Enemies within this distance will spawn
## Should be LARGER than max camera view to prevent pop-in
@export var spawn_radius: float = 2500.0

## Despawn radius around players (px)
## Enemies beyond this distance from ALL players will despawn
## Should be LARGER than spawn_radius to prevent flickering
@export var despawn_radius: float = 3500.0

## How often to check spawns (seconds)
## Lower = more responsive, higher = better performance
@export var update_interval: float = 0.2  # 5 FPS

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

## Enemy state enum
enum EnemyState {
	UNSPAWNED,  # Not currently active
	ALIVE,      # Active and alive
	DEAD,       # Killed but corpse exists
	LOOTED      # Fully looted, won't respawn
}

## Spawn registry - master list of all spawn points
## Each entry: {
##   position: Vector2,
##   level: int,
##   type: String,
##   state: EnemyState,
##   enemy_instance: Enemy (null if unspawned)
## }
var spawn_registry: Array = []  # Array of Dictionary

## Active enemy lookup by spawn ID
var active_enemies: Dictionary = {}  # {spawn_id: Enemy instance}

## Player positions (updated each frame)
## Single-player: 1 entry
## Multiplayer: N entries (one per player)
var player_positions: Array = []  # Array of Vector2

## Reference to game world (for spawning enemies)
var game_world: Node = null

## Update timer
var update_timer: float = 0.0

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func initialize(world: Node, spawn_markers: Array) -> void:
	"""Initialize spawn manager with game world and spawn markers"""
	game_world = world

	print("\n🌍 ═══════════════════════════════════════════════════")
	print("   SPAWN MANAGER INITIALIZATION")
	print("   ═══════════════════════════════════════════════════")
	print("   Max active enemies: %d" % max_active_enemies)
	print("   Spawn radius: %.0fpx" % spawn_radius)
	print("   Despawn radius: %.0fpx" % despawn_radius)
	print("   Update interval: %.2fs (%.0f FPS)" % [update_interval, 1.0 / update_interval])

	# Build spawn registry from markers
	for marker in spawn_markers:
		var spawn_data = {
			"position": marker.global_position,
			"level": marker.get_meta("enemy_level", 1),
			"type": marker.get_meta("enemy_type", "skeleton"),
			"aggro_range": marker.get_meta("aggro_range", 150.0),
			"state": EnemyState.UNSPAWNED,
			"enemy_instance": null
		}
		spawn_registry.append(spawn_data)

	print("   📍 Loaded %d spawn points" % spawn_registry.size())
	print("   ═══════════════════════════════════════════════════\n")

# ═══════════════════════════════════════════════════════════════════════════
# MAIN UPDATE LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	# Throttle updates for performance
	update_timer += delta
	if update_timer < update_interval:
		return
	update_timer = 0.0

	# Update spawn system
	update_spawns()

func update_spawns() -> void:
	"""Main spawn update - called every update_interval"""

	# Skip if no players
	if player_positions.is_empty():
		return

	# STEP 1: Despawn enemies far from ALL players
	despawn_distant_enemies()

	# STEP 2: Find spawn candidates (close to ANY player, not dead/looted)
	var candidates = collect_spawn_candidates()

	# STEP 3: Spawn closest enemies up to budget
	spawn_priority_enemies(candidates)

# ═══════════════════════════════════════════════════════════════════════════
# DESPAWN LOGIC
# ═══════════════════════════════════════════════════════════════════════════

func despawn_distant_enemies() -> void:
	"""Despawn enemies that are far from ALL players"""
	var to_despawn = []

	for spawn_id in active_enemies.keys():
		if should_despawn_enemy(spawn_id):
			to_despawn.append(spawn_id)

	# Despawn marked enemies
	for spawn_id in to_despawn:
		despawn_enemy(spawn_id)

func should_despawn_enemy(spawn_id: int) -> bool:
	"""Check if enemy should despawn (far from ALL players)"""
	var spawn_data = spawn_registry[spawn_id]

	# Don't despawn dead enemies with lootable corpses
	if spawn_data.state == EnemyState.DEAD:
		var enemy = spawn_data.enemy_instance
		if is_instance_valid(enemy) and enemy.has_corpse_loot():
			return false

	# Check if ALL players are beyond despawn radius
	for player_pos in player_positions:
		var distance = spawn_data.position.distance_to(player_pos)
		if distance < despawn_radius:
			return false  # At least one player nearby, keep alive

	return true  # All players far away, despawn

func despawn_enemy(spawn_id: int) -> void:
	"""Despawn an enemy and preserve its state"""
	if not active_enemies.has(spawn_id):
		return

	var enemy = active_enemies[spawn_id]
	var spawn_data = spawn_registry[spawn_id]

	# Preserve state before despawning
	if is_instance_valid(enemy):
		# If enemy is dead, keep state as DEAD
		# If enemy is alive, mark as UNSPAWNED (can respawn later)
		if spawn_data.state != EnemyState.DEAD and spawn_data.state != EnemyState.LOOTED:
			spawn_data.state = EnemyState.UNSPAWNED

		# Remove from world
		enemy.queue_free()

	# Remove from active list
	active_enemies.erase(spawn_id)
	spawn_data.enemy_instance = null

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN LOGIC
# ═══════════════════════════════════════════════════════════════════════════

func collect_spawn_candidates() -> Array:
	"""Find all spawn points that should have enemies (close to ANY player, not dead/looted)"""
	var candidates = []

	for spawn_id in range(spawn_registry.size()):
		var spawn_data = spawn_registry[spawn_id]

		# Skip if already spawned
		if active_enemies.has(spawn_id):
			continue

		# Skip if dead or looted (permanent states)
		if spawn_data.state == EnemyState.DEAD or spawn_data.state == EnemyState.LOOTED:
			continue

		# Check if ANY player is within spawn radius
		var closest_distance = INF
		for player_pos in player_positions:
			var distance = spawn_data.position.distance_to(player_pos)
			closest_distance = min(closest_distance, distance)

		if closest_distance < spawn_radius:
			candidates.append({
				"spawn_id": spawn_id,
				"priority": closest_distance  # Closer = higher priority
			})

	return candidates

func spawn_priority_enemies(candidates: Array) -> void:
	"""Spawn enemies from candidate list, prioritizing closest to players"""
	if candidates.is_empty():
		return

	# Sort by distance to nearest player (closest first)
	candidates.sort_custom(func(a, b): return a.priority < b.priority)

	# Spawn enemies up to budget
	var spawned_count = 0
	var spawn_limit = min(candidates.size(), max_active_enemies - active_enemies.size())

	for i in range(spawn_limit):
		var candidate = candidates[i]
		spawn_enemy(candidate.spawn_id)
		spawned_count += 1

	# Debug output (only when spawning)
	if spawned_count > 0:
		print("✨ Spawned %d enemies near player (active: %d/%d)" % [spawned_count, active_enemies.size(), max_active_enemies])

func spawn_enemy(spawn_id: int) -> void:
	"""Spawn a single enemy at the given spawn point"""
	if spawn_id < 0 or spawn_id >= spawn_registry.size():
		push_error("Invalid spawn_id: %d (registry size: %d)" % [spawn_id, spawn_registry.size()])
		return

	var spawn_data = spawn_registry[spawn_id]

	# Load enemy scene - use correct path with lowercase 'e'
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		push_error("Failed to load enemy scene at res://scenes/enemies/enemy.tscn!")
		return

	# Instantiate enemy
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_data.position
	enemy.enemy_level = spawn_data.level
	# Note: enemy_type not set - all enemies are skeletons (no type system in Enemy.gd)

	# Add to world
	game_world.add_child(enemy)

	# Track in active enemies
	active_enemies[spawn_id] = enemy
	spawn_data.enemy_instance = enemy
	spawn_data.state = EnemyState.ALIVE

	# Connect signals for state tracking
	connect_enemy_signals(enemy, spawn_id)

	# Connect corpse loot signal (for game_world loot system)
	# This is critical - without this, corpses won't open loot UI when clicked
	if enemy.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		# Check if not already connected (avoid duplicates)
		if not enemy.corpse_clicked.is_connected(game_world._on_corpse_clicked):
			enemy.corpse_clicked.connect(game_world._on_corpse_clicked)

	# Debug: Verify tracking worked
	if not active_enemies.has(spawn_id):
		push_error("BUG: Failed to track spawn_id %d in active_enemies!" % spawn_id)

# ═══════════════════════════════════════════════════════════════════════════
# STATE TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func connect_enemy_signals(enemy: Node, spawn_id: int) -> void:
	"""Connect to enemy signals to track state changes"""

	# Connect death signal
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died.bind(spawn_id))

	# Connect loot signal
	if enemy.has_signal("corpse_looted_empty"):
		enemy.corpse_looted_empty.connect(_on_enemy_looted.bind(spawn_id))

func _on_enemy_died(enemy: Node, spawn_id: int) -> void:
	"""Called when enemy dies"""
	if spawn_id >= spawn_registry.size():
		return

	var spawn_data = spawn_registry[spawn_id]
	spawn_data.state = EnemyState.DEAD

	print("💀 Enemy died at spawn %d (state: DEAD)" % spawn_id)

func _on_enemy_looted(enemy: Node, spawn_id: int) -> void:
	"""Called when enemy corpse is fully looted"""
	if spawn_id >= spawn_registry.size():
		return

	var spawn_data = spawn_registry[spawn_id]
	spawn_data.state = EnemyState.LOOTED

	# Despawn the corpse
	if active_enemies.has(spawn_id):
		despawn_enemy(spawn_id)

	print("💰 Enemy looted at spawn %d (state: LOOTED, won't respawn)" % spawn_id)

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func update_player_positions(positions: Array) -> void:
	"""Update player positions (called by game_world each frame)"""
	player_positions.clear()
	for pos in positions:
		if pos is Vector2:
			player_positions.append(pos)

func add_player_position(position: Vector2) -> void:
	"""Add a player position to tracking (multiplayer support)"""
	if not player_positions.has(position):
		player_positions.append(position)

func remove_player_position(position: Vector2) -> void:
	"""Remove a player position from tracking (multiplayer support)"""
	player_positions.erase(position)

# ═══════════════════════════════════════════════════════════════════════════
# DEBUG & STATS
# ═══════════════════════════════════════════════════════════════════════════

func get_stats() -> Dictionary:
	"""Get current spawn manager statistics"""
	var stats = {
		"total_spawns": spawn_registry.size(),
		"active_enemies": active_enemies.size(),
		"unspawned": 0,
		"alive": 0,
		"dead": 0,
		"looted": 0
	}

	for spawn_data in spawn_registry:
		match spawn_data.state:
			EnemyState.UNSPAWNED:
				stats.unspawned += 1
			EnemyState.ALIVE:
				stats.alive += 1
			EnemyState.DEAD:
				stats.dead += 1
			EnemyState.LOOTED:
				stats.looted += 1

	return stats

func print_stats() -> void:
	"""Print current spawn manager statistics"""
	var stats = get_stats()
	print("\n📊 SPAWN MANAGER STATS:")
	print("   Total spawn points: %d" % stats.total_spawns)
	print("   Active enemies: %d / %d" % [stats.active_enemies, max_active_enemies])
	print("   Unspawned: %d" % stats.unspawned)
	print("   Alive: %d" % stats.alive)
	print("   Dead: %d" % stats.dead)
	print("   Looted: %d\n" % stats.looted)
