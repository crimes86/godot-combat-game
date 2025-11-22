extends Node
class_name ChunkAwareSpawnManager

## Chunk-Aware Enemy Spawn Manager
##
## Integrates with ChunkBasedPropSystem to spawn enemies only in loaded chunks.
## Retains manually placed spawn markers from scene, groups them by chunk.
##
## Features:
## - Only spawns in active chunks (current + neighbors)
## - Tunable activation rates per level range
## - Proximity-based LOD for performance
## - Preserves state (dead/looted enemies won't respawn)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Spawn activation rates per level range (0.0 - 1.0)
## Controls what % of markers in each level range will spawn enemies
@export var activation_rates: Dictionary = {
	"L1-3": 0.6,   # 60% of low-level spawns active
	"L4-7": 0.4,   # 40% of mid-level spawns active
	"L8-10": 0.3   # 30% of high-level spawns active
}

## Maximum active enemies across all chunks
@export var max_active_enemies: int = 50

## LOD distance thresholds (px from player)
const LOD_CLOSE: float = 400.0     # Full AI, particles, animations
const LOD_MEDIUM: float = 800.0    # Reduced AI update rate
const LOD_FAR: float = 1500.0      # Minimal processing, visible only

## Update intervals
const SPAWN_CHECK_INTERVAL: float = 1.0   # Check spawns every 1s
const LOD_UPDATE_INTERVAL: float = 0.5    # Update LOD every 0.5s

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

## Enemy state tracking
enum EnemyState {
	UNSPAWNED,  # Not currently active
	ALIVE,      # Active and alive
	DEAD,       # Killed but corpse exists
	LOOTED      # Fully looted, won't respawn
}

## Spawn registry - all spawn markers grouped by chunk
## chunk_key -> Array[SpawnData]
var spawn_registry_by_chunk: Dictionary = {}

## All spawn data (for global lookups)
## spawn_id -> SpawnData
var spawn_registry_global: Dictionary = {}

## Active enemies
## spawn_id -> Enemy instance
var active_enemies: Dictionary = {}

## Chunk system reference
var chunk_system: Node = null

## Game world reference
var game_world: Node = null

## Player reference
var player: Node = null

## Update timers
var spawn_check_timer: float = 0.0
var lod_update_timer: float = 0.0

## Next spawn ID
var next_spawn_id: int = 0

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN DATA CLASS
# ═══════════════════════════════════════════════════════════════════════════

class SpawnData:
	var spawn_id: int
	var position: Vector2
	var level: int
	var enemy_type: String
	var aggro_range: float
	var chunk_key: String
	var is_active: bool  # Determined by activation rate
	var state: int  # EnemyState enum
	var enemy_instance: Node  # null if unspawned

	func _init(id: int, pos: Vector2, lvl: int, chunk: String):
		spawn_id = id
		position = pos
		level = lvl
		chunk_key = chunk
		enemy_type = "skeleton"
		aggro_range = 150.0
		is_active = false
		state = EnemyState.UNSPAWNED
		enemy_instance = null

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func initialize(world: Node, chunk_prop_system: Node, spawn_markers: Array) -> void:
	"""Initialize spawn manager with game world, chunk system, and spawn markers"""
	game_world = world
	chunk_system = chunk_prop_system

	print("\n🌍 ═══════════════════════════════════════════════════")
	print("   CHUNK-AWARE SPAWN MANAGER INITIALIZATION")
	print("   ═══════════════════════════════════════════════════")
	print("   Total spawn markers: %d" % spawn_markers.size())
	print("   Activation rates:")
	for range_name in activation_rates.keys():
		print("      %s: %.0f%%" % [range_name, activation_rates[range_name] * 100])

	# RNG for consistent spawn activation
	var rng = RandomNumberGenerator.new()
	rng.seed = 88888  # Fixed seed for consistent spawns across runs

	# Group spawn markers by chunk
	var markers_by_level = {}  # Track counts per level

	for marker in spawn_markers:
		# Create spawn data
		var spawn_data = create_spawn_data_from_marker(marker, rng)

		# Add to global registry
		spawn_registry_global[spawn_data.spawn_id] = spawn_data

		# Add to chunk registry
		if not spawn_registry_by_chunk.has(spawn_data.chunk_key):
			spawn_registry_by_chunk[spawn_data.chunk_key] = []
		spawn_registry_by_chunk[spawn_data.chunk_key].append(spawn_data)

		# Track level counts
		if not markers_by_level.has(spawn_data.level):
			markers_by_level[spawn_data.level] = {"total": 0, "active": 0}
		markers_by_level[spawn_data.level]["total"] += 1
		if spawn_data.is_active:
			markers_by_level[spawn_data.level]["active"] += 1

	# Print distribution
	print("\n   📊 Spawn Distribution by Level:")
	var levels = markers_by_level.keys()
	levels.sort()
	for level in levels:
		var data = markers_by_level[level]
		var pct = (data["active"] * 100.0 / data["total"]) if data["total"] > 0 else 0
		print("      L%d: %d active / %d total (%.0f%%)" % [level, data["active"], data["total"], pct])

	print("\n   📍 Spawn Markers Grouped by Chunk:")
	var chunk_keys = spawn_registry_by_chunk.keys()
	chunk_keys.sort()
	for chunk_key in chunk_keys:
		var spawns = spawn_registry_by_chunk[chunk_key]
		var active_count = 0
		for spawn_data in spawns:
			if spawn_data.is_active:
				active_count += 1
		print("      Chunk %s: %d active / %d total spawns" % [chunk_key, active_count, spawns.size()])

	print("   ═══════════════════════════════════════════════════\n")

func create_spawn_data_from_marker(marker: Node, rng: RandomNumberGenerator) -> SpawnData:
	"""Create SpawnData from a spawn marker node"""
	# Extract level
	var level = 1
	if marker.has_meta("enemy_level"):
		level = marker.get_meta("enemy_level")
	elif marker.has_method("get") and "enemy_level" in marker:
		level = marker.get("enemy_level")

	# Determine chunk key
	var chunk_key = get_chunk_key(marker.global_position)

	# Create spawn data
	var spawn_data = SpawnData.new(next_spawn_id, marker.global_position, level, chunk_key)
	next_spawn_id += 1

	# Extract optional properties
	if marker.has_meta("enemy_type"):
		spawn_data.enemy_type = marker.get_meta("enemy_type")
	elif marker.has_method("get") and "enemy_type" in marker:
		spawn_data.enemy_type = marker.get("enemy_type")

	if marker.has_meta("aggro_range"):
		spawn_data.aggro_range = marker.get_meta("aggro_range")
	elif marker.has_method("get") and "aggro_range" in marker:
		spawn_data.aggro_range = marker.get("aggro_range")

	# Determine if this spawn is active based on activation rate
	var activation_rate = get_activation_rate_for_level(level)

	# Use spawn_id as seed for consistent per-marker randomness
	rng.seed = 88888 + spawn_data.spawn_id
	spawn_data.is_active = rng.randf() < activation_rate

	return spawn_data

func get_activation_rate_for_level(level: int) -> float:
	"""Get activation rate for a given level"""
	if level >= 1 and level <= 3:
		return activation_rates.get("L1-3", 0.6)
	elif level >= 4 and level <= 7:
		return activation_rates.get("L4-7", 0.4)
	elif level >= 8 and level <= 10:
		return activation_rates.get("L8-10", 0.3)
	else:
		return 0.3  # Default for higher levels

func get_chunk_key(world_pos: Vector2) -> String:
	"""Get chunk key from world position (horizontal only - matches ChunkBasedPropSystem)"""
	# ChunkBasedPropSystem uses 3000px wide horizontal chunks
	const CHUNK_SIZE = 3000.0
	var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
	return "%d,0" % chunk_x  # Y is always 0 - world divided horizontally only

# ═══════════════════════════════════════════════════════════════════════════
# MAIN UPDATE LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	# Get player
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return

	# Check spawns periodically
	spawn_check_timer += delta
	if spawn_check_timer >= SPAWN_CHECK_INTERVAL:
		spawn_check_timer = 0.0
		update_spawns()

	# Update LOD for active enemies
	lod_update_timer += delta
	if lod_update_timer >= LOD_UPDATE_INTERVAL:
		lod_update_timer = 0.0
		update_enemy_lod()

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN LOGIC
# ═══════════════════════════════════════════════════════════════════════════

func update_spawns() -> void:
	"""Update spawns based on loaded chunks"""
	if not chunk_system:
		return

	# Get loaded chunks from chunk system
	var loaded_chunks = chunk_system.loaded_chunks.keys()

	if loaded_chunks.is_empty():
		return

	# STEP 1: Despawn enemies in unloaded chunks
	despawn_enemies_in_unloaded_chunks(loaded_chunks)

	# STEP 2: Spawn enemies in loaded chunks
	spawn_enemies_in_loaded_chunks(loaded_chunks)

func spawn_enemies_in_loaded_chunks(loaded_chunks: Array) -> void:
	"""Spawn enemies in currently loaded chunks"""
	var spawned_count = 0

	for chunk_key in loaded_chunks:
		# Skip if this chunk has no spawn markers
		if not spawn_registry_by_chunk.has(chunk_key):
			continue

		# Get spawn data for this chunk
		var chunk_spawns = spawn_registry_by_chunk[chunk_key]

		for spawn_data in chunk_spawns:
			# Skip if not active (determined by activation rate)
			if not spawn_data.is_active:
				continue

			# Skip if already spawned
			if active_enemies.has(spawn_data.spawn_id):
				continue

			# Skip if dead or looted (permanent states)
			if spawn_data.state == EnemyState.DEAD or spawn_data.state == EnemyState.LOOTED:
				continue

			# Check global enemy limit
			if active_enemies.size() >= max_active_enemies:
				return  # Hit limit, stop spawning

			# Spawn enemy
			spawn_enemy(spawn_data)
			spawned_count += 1

	# Debug output (only when spawning)
	if spawned_count > 0:
		print("✨ Spawned %d enemies in loaded chunks (active: %d/%d)" % [spawned_count, active_enemies.size(), max_active_enemies])

func despawn_enemies_in_unloaded_chunks(loaded_chunks: Array) -> void:
	"""Despawn enemies that are in chunks that have been unloaded"""
	var to_despawn = []

	for spawn_id in active_enemies.keys():
		var spawn_data = spawn_registry_global[spawn_id]

		# Check if this enemy's chunk is still loaded
		if not loaded_chunks.has(spawn_data.chunk_key):
			# Don't despawn dead enemies with lootable corpses
			if spawn_data.state == EnemyState.DEAD:
				var enemy = spawn_data.enemy_instance
				if is_instance_valid(enemy) and enemy.has_method("has_corpse_loot") and enemy.has_corpse_loot():
					continue  # Keep corpse

			to_despawn.append(spawn_id)

	# Despawn marked enemies
	for spawn_id in to_despawn:
		despawn_enemy(spawn_id)

func spawn_enemy(spawn_data: SpawnData) -> void:
	"""Spawn a single enemy"""
	# Load enemy scene
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		push_error("Failed to load enemy scene!")
		return

	# Instantiate enemy
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_data.position
	enemy.enemy_level = spawn_data.level

	# Add to world
	game_world.add_child(enemy)

	# Track in active enemies
	active_enemies[spawn_data.spawn_id] = enemy
	spawn_data.enemy_instance = enemy
	spawn_data.state = EnemyState.ALIVE

	# Connect signals for state tracking
	connect_enemy_signals(enemy, spawn_data.spawn_id)

	# Connect corpse loot signal (for game_world loot system)
	if enemy.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		if not enemy.corpse_clicked.is_connected(game_world._on_corpse_clicked):
			enemy.corpse_clicked.connect(game_world._on_corpse_clicked)

	# Set initial LOD
	update_enemy_lod_single(enemy, spawn_data.spawn_id)

func despawn_enemy(spawn_id: int) -> void:
	"""Despawn an enemy and preserve its state"""
	if not active_enemies.has(spawn_id):
		return

	var enemy = active_enemies[spawn_id]
	var spawn_data = spawn_registry_global[spawn_id]

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
# LOD SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func update_enemy_lod() -> void:
	"""Update LOD for all active enemies based on distance to player"""
	if not player or not is_instance_valid(player):
		return

	for spawn_id in active_enemies.keys():
		update_enemy_lod_single(active_enemies[spawn_id], spawn_id)

func update_enemy_lod_single(enemy: Node, spawn_id: int) -> void:
	"""Update LOD for a single enemy"""
	if not is_instance_valid(enemy):
		return

	if not player or not is_instance_valid(player):
		return

	var distance = enemy.global_position.distance_to(player.global_position)

	# Determine LOD level
	var lod_level = 0
	if distance < LOD_CLOSE:
		lod_level = 0  # FULL
	elif distance < LOD_MEDIUM:
		lod_level = 1  # MEDIUM
	elif distance < LOD_FAR:
		lod_level = 2  # MINIMAL
	else:
		lod_level = 3  # INVISIBLE (beyond chunk view)

	# Apply LOD if enemy has the method
	if enemy.has_method("set_lod_level"):
		enemy.set_lod_level(lod_level)

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
	if not spawn_registry_global.has(spawn_id):
		return

	var spawn_data = spawn_registry_global[spawn_id]
	spawn_data.state = EnemyState.DEAD

	print("💀 Enemy died at spawn %d (chunk: %s, state: DEAD)" % [spawn_id, spawn_data.chunk_key])

func _on_enemy_looted(enemy: Node, spawn_id: int) -> void:
	"""Called when enemy corpse is fully looted"""
	if not spawn_registry_global.has(spawn_id):
		return

	var spawn_data = spawn_registry_global[spawn_id]
	spawn_data.state = EnemyState.LOOTED

	# Despawn the corpse
	if active_enemies.has(spawn_id):
		despawn_enemy(spawn_id)

	print("💰 Enemy looted at spawn %d (chunk: %s, state: LOOTED, won't respawn)" % [spawn_id, spawn_data.chunk_key])

# ═══════════════════════════════════════════════════════════════════════════
# DEBUG & STATS
# ═══════════════════════════════════════════════════════════════════════════

func get_stats() -> Dictionary:
	"""Get current spawn manager statistics"""
	var stats = {
		"total_spawns": spawn_registry_global.size(),
		"active_enemies": active_enemies.size(),
		"unspawned": 0,
		"alive": 0,
		"dead": 0,
		"looted": 0,
		"loaded_chunks": 0
	}

	for spawn_data in spawn_registry_global.values():
		match spawn_data.state:
			EnemyState.UNSPAWNED:
				stats.unspawned += 1
			EnemyState.ALIVE:
				stats.alive += 1
			EnemyState.DEAD:
				stats.dead += 1
			EnemyState.LOOTED:
				stats.looted += 1

	if chunk_system:
		stats.loaded_chunks = chunk_system.loaded_chunks.size()

	return stats

func print_stats() -> void:
	"""Print current spawn manager statistics"""
	var stats = get_stats()
	print("\n📊 CHUNK-AWARE SPAWN MANAGER STATS:")
	print("   Loaded chunks: %d" % stats.loaded_chunks)
	print("   Total spawn points: %d" % stats.total_spawns)
	print("   Active enemies: %d / %d" % [stats.active_enemies, max_active_enemies])
	print("   Unspawned: %d" % stats.unspawned)
	print("   Alive: %d" % stats.alive)
	print("   Dead: %d" % stats.dead)
	print("   Looted: %d\n" % stats.looted)
