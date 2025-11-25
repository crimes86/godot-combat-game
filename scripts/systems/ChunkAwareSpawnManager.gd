extends Node
class_name ChunkAwareSpawnManager

## Chunk-Based Enemy Spawn Manager
##
## Enemies are managed per-chunk, not per-player. Each chunk maintains its own
## enemy population and spawns/despawns based on chunk load state.
##
## Features:
## - Each chunk has a target enemy count (ENEMIES_PER_CHUNK)
## - Enemies spawn when chunk loads, despawn when chunk unloads
## - Level bands determine enemy levels based on X position
## - Respawn timer for killed enemies
## - No player-centric LOD - all enemies in loaded chunks are active

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Enemies per chunk (3000px wide)
const ENEMIES_PER_CHUNK: int = 60

## Chunk size (must match ChunkBasedPropSystem)
const CHUNK_SIZE: float = 3000.0

## Level bands - enemy level based on X position
## Progression goes WEST to EAST (negative X to positive X)
## Campfire spawn is at X=-2000, so west of that is low level, east gets harder
const LEVEL_BANDS: Array = [
	# West of spawn (low level wilderness)
	{"min_x": -99999, "max_x": -2600, "level": 1},  # Far west - level 1
	# Near spawn (safe-ish area)
	{"min_x": -2600, "max_x": 400, "level": 1},     # Spawn area - level 1
	# Progression eastward
	{"min_x": 400, "max_x": 700, "level": 2},
	{"min_x": 700, "max_x": 1000, "level": 3},
	{"min_x": 1000, "max_x": 1300, "level": 4},
	{"min_x": 1300, "max_x": 1600, "level": 5},
	{"min_x": 1600, "max_x": 1900, "level": 6},
	{"min_x": 1900, "max_x": 2200, "level": 7},
	{"min_x": 2200, "max_x": 2500, "level": 8},
	{"min_x": 2500, "max_x": 2800, "level": 9},
	{"min_x": 2800, "max_x": 99999, "level": 10},   # Far east - level 10
]

## Respawn timer in seconds (0 = no respawn until chunk reload)
@export var respawn_time: float = 300.0  # 5 minutes

## Safe zones - no enemies spawn within these areas
const SAFE_ZONES: Array = [
	{"pos": Vector2(-2000, 0), "radius": 600.0},  # Campfire spawn
]

## Ruins areas - no random spawns (guardians spawn separately)
const RUINS_AREAS: Array = [
	{"pos": Vector2(2184, -1216), "radius": 350.0},  # Ruins 1
	{"pos": Vector2(4368, 0), "radius": 350.0},      # Ruins 2
	{"pos": Vector2(6552, 1216), "radius": 350.0},   # Ruins 3
]

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

## Chunk enemy data
## chunk_key -> ChunkEnemyData
var chunk_enemies: Dictionary = {}

## Manual spawn markers grouped by chunk
## chunk_key -> Array of {position, level, spawned}
var manual_spawns_by_chunk: Dictionary = {}

## Chunk system reference
var chunk_system: Node = null

## Game world reference
var game_world: Node = null

## RNG for spawning (seeded for consistency)
var spawn_rng: RandomNumberGenerator

## Update timers
var spawn_check_timer: float = 0.0
const SPAWN_CHECK_INTERVAL: float = 1.0

# ═══════════════════════════════════════════════════════════════════════════
# CHUNK ENEMY DATA CLASS
# ═══════════════════════════════════════════════════════════════════════════

class ChunkEnemyData:
	var chunk_key: String
	var enemies: Array = []  # Array of enemy instances
	var dead_enemies: Array = []  # Array of {position, level, death_time}
	var target_count: int = 0

	func _init(key: String, target: int):
		chunk_key = key
		target_count = target

	func get_alive_count() -> int:
		var count = 0
		for enemy in enemies:
			if is_instance_valid(enemy) and not enemy.is_dying and not enemy.is_corpse:
				count += 1
		return count

	func cleanup_invalid() -> void:
		# Remove invalid enemy references
		var valid_enemies = []
		for enemy in enemies:
			if is_instance_valid(enemy):
				valid_enemies.append(enemy)
		enemies = valid_enemies

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func initialize(world: Node, chunk_prop_system: Node, spawn_markers: Array) -> void:
	"""Initialize spawn manager with game world, chunk system, and manual spawn markers"""
	game_world = world
	chunk_system = chunk_prop_system

	# Create seeded RNG for consistent spawns
	spawn_rng = RandomNumberGenerator.new()
	spawn_rng.seed = 12345  # Fixed seed for reproducibility

	# Process manual spawn markers - group by chunk
	var markers_by_level = {}
	for marker in spawn_markers:
		var pos = marker.global_position
		var level = marker.get_meta("enemy_level", 1)
		var chunk_key = get_chunk_key(pos)

		if not manual_spawns_by_chunk.has(chunk_key):
			manual_spawns_by_chunk[chunk_key] = []

		manual_spawns_by_chunk[chunk_key].append({
			"position": pos,
			"level": level,
			"spawned": false
		})

		# Track for debug output
		if not markers_by_level.has(level):
			markers_by_level[level] = 0
		markers_by_level[level] += 1

	print("\n🌍 ═══════════════════════════════════════════════════")
	print("   CHUNK-BASED ENEMY SPAWN MANAGER")
	print("   ═══════════════════════════════════════════════════")
	print("   Enemies per chunk: %d (procedural)" % ENEMIES_PER_CHUNK)
	print("   Manual spawn markers: %d" % spawn_markers.size())
	if not markers_by_level.is_empty():
		print("   Manual markers by level:")
		var levels = markers_by_level.keys()
		levels.sort()
		for level in levels:
			print("      L%d: %d markers" % [level, markers_by_level[level]])
		print("   Manual markers by chunk:")
		var chunks = manual_spawns_by_chunk.keys()
		chunks.sort()
		for chunk_key in chunks:
			print("      [%s]: %d markers" % [chunk_key, manual_spawns_by_chunk[chunk_key].size()])
	print("   Chunk size: %.0fpx" % CHUNK_SIZE)
	print("   Respawn time: %.0fs" % respawn_time)
	print("   Level bands: %d zones" % LEVEL_BANDS.size())
	print("   ═══════════════════════════════════════════════════\n")

# ═══════════════════════════════════════════════════════════════════════════
# MAIN UPDATE LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not chunk_system:
		return

	spawn_check_timer += delta
	if spawn_check_timer >= SPAWN_CHECK_INTERVAL:
		spawn_check_timer = 0.0
		update_chunk_enemies()
		check_respawns()

func update_chunk_enemies() -> void:
	"""Sync enemy state with loaded chunks"""
	if not chunk_system:
		return

	var loaded_chunks = chunk_system.loaded_chunks.keys()

	# Handle newly loaded chunks - spawn enemies
	for chunk_key in loaded_chunks:
		if not chunk_enemies.has(chunk_key):
			on_chunk_loaded(chunk_key)
		else:
			# Top up enemies if below target
			var chunk_data = chunk_enemies[chunk_key]
			chunk_data.cleanup_invalid()
			var alive_count = chunk_data.get_alive_count()
			var needed = chunk_data.target_count - alive_count
			if needed > 0:
				spawn_enemies_in_chunk(chunk_key, needed)

	# Handle unloaded chunks - despawn enemies (skip in multiplayer to avoid sync issues)
	if not multiplayer.has_multiplayer_peer():
		var chunks_to_remove = []
		for chunk_key in chunk_enemies.keys():
			if not loaded_chunks.has(chunk_key):
				chunks_to_remove.append(chunk_key)

		for chunk_key in chunks_to_remove:
			on_chunk_unloaded(chunk_key)

func on_chunk_loaded(chunk_key: String) -> void:
	"""Called when a chunk is loaded - spawn enemies"""
	print("📦 Chunk %s loaded - spawning enemies" % chunk_key)

	# Create chunk data
	var chunk_data = ChunkEnemyData.new(chunk_key, ENEMIES_PER_CHUNK)
	chunk_enemies[chunk_key] = chunk_data

	# STEP 1: Spawn from manual markers first (these have priority)
	var manual_spawned = 0
	if manual_spawns_by_chunk.has(chunk_key):
		for spawn_data in manual_spawns_by_chunk[chunk_key]:
			if spawn_data.spawned:
				continue  # Already spawned

			var enemy = spawn_single_enemy(spawn_data.position, spawn_data.level, chunk_key)
			if enemy:
				chunk_data.enemies.append(enemy)
				spawn_data.spawned = true
				manual_spawned += 1

		if manual_spawned > 0:
			print("   📍 Spawned %d enemies from manual markers" % manual_spawned)

	# STEP 2: Fill remaining capacity with procedural spawns
	var remaining = ENEMIES_PER_CHUNK - chunk_data.enemies.size()
	if remaining > 0:
		spawn_enemies_in_chunk(chunk_key, remaining)

func on_chunk_unloaded(chunk_key: String) -> void:
	"""Called when a chunk is unloaded - despawn enemies"""
	if not chunk_enemies.has(chunk_key):
		return

	print("🗑️ Chunk %s unloaded - despawning enemies" % chunk_key)

	var chunk_data = chunk_enemies[chunk_key]

	# Despawn all enemies in this chunk
	for enemy in chunk_data.enemies:
		if is_instance_valid(enemy):
			# Don't despawn corpses with loot
			if enemy.is_corpse and enemy.has_method("has_corpse_loot") and enemy.has_corpse_loot():
				continue
			enemy.queue_free()

	chunk_enemies.erase(chunk_key)

	# Reset manual spawn markers so they respawn when chunk reloads
	if manual_spawns_by_chunk.has(chunk_key):
		for spawn_data in manual_spawns_by_chunk[chunk_key]:
			spawn_data.spawned = false

# ═══════════════════════════════════════════════════════════════════════════
# SPAWNING
# ═══════════════════════════════════════════════════════════════════════════

func spawn_enemies_in_chunk(chunk_key: String, count: int) -> void:
	"""Spawn a specific number of enemies in a chunk"""
	if not chunk_enemies.has(chunk_key):
		return

	# In multiplayer, only server spawns
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var chunk_data = chunk_enemies[chunk_key]
	var spawned = 0
	var attempts = 0
	var max_attempts = count * 10  # 10 attempts per enemy max

	# Parse chunk coordinates
	var chunk_parts = chunk_key.split(",")
	var chunk_x = int(chunk_parts[0])
	var chunk_min_x = chunk_x * CHUNK_SIZE
	var chunk_max_x = (chunk_x + 1) * CHUNK_SIZE

	# Use chunk-specific seed for consistent spawns
	var chunk_seed = hash(chunk_key) + chunk_data.enemies.size()
	spawn_rng.seed = chunk_seed

	while spawned < count and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		var spawn_x = spawn_rng.randf_range(chunk_min_x, chunk_max_x)
		var spawn_y = spawn_rng.randf_range(-2500, 2500)  # World height range
		var spawn_pos = Vector2(spawn_x, spawn_y)

		# Validate position
		if not is_valid_spawn_position(spawn_pos):
			continue

		# Determine level based on X position
		var level = get_level_for_position(spawn_pos)

		# Spawn the enemy
		var enemy = spawn_single_enemy(spawn_pos, level, chunk_key)
		if enemy:
			chunk_data.enemies.append(enemy)
			spawned += 1

	if spawned > 0:
		print("✨ Spawned %d enemies in chunk %s (total: %d/%d)" % [
			spawned, chunk_key, chunk_data.get_alive_count(), chunk_data.target_count
		])

func spawn_single_enemy(pos: Vector2, level: int, chunk_key: String) -> Node:
	"""Spawn a single enemy at position"""
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		push_error("Failed to load enemy scene!")
		return null

	var enemy = enemy_scene.instantiate()
	enemy.global_position = pos
	enemy.enemy_level = level

	# Generate unique name
	var enemy_name = "Enemy_%s_%d" % [chunk_key.replace(",", "_"), randi()]
	enemy.name = enemy_name

	# Add to world
	game_world.call_deferred("add_child", enemy)

	# Connect death signal for respawn tracking
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy, chunk_key))

	# Connect corpse loot signal
	if enemy.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		enemy.corpse_clicked.connect(game_world._on_corpse_clicked)

	# In multiplayer, sync to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc("client_spawn_enemy", pos, level, enemy_name)

	return enemy

@rpc("authority", "call_local", "reliable")
func client_spawn_enemy(pos: Vector2, level: int, enemy_name: String) -> void:
	"""Called by server to spawn enemy on clients"""
	# Skip if we're the server (already spawned)
	if multiplayer.is_server():
		return

	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		return

	var enemy = enemy_scene.instantiate()
	enemy.global_position = pos
	enemy.enemy_level = level
	enemy.name = enemy_name

	game_world.call_deferred("add_child", enemy)

func is_valid_spawn_position(pos: Vector2) -> bool:
	"""Check if position is valid for spawning"""
	# Check safe zones
	for zone in SAFE_ZONES:
		if pos.distance_to(zone.pos) < zone.radius:
			return false

	# Check ruins areas
	for ruins in RUINS_AREAS:
		if pos.distance_to(ruins.pos) < ruins.radius:
			return false

	# Check world bounds
	if pos.y < -2800 or pos.y > 2800:
		return false

	return true

func get_level_for_position(pos: Vector2) -> int:
	"""Get enemy level based on X position"""
	for band in LEVEL_BANDS:
		if pos.x >= band.min_x and pos.x < band.max_x:
			return band.level
	return 1  # Default level 1

func get_chunk_key(world_pos: Vector2) -> String:
	"""Get chunk key from world position"""
	var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
	return "%d,0" % chunk_x

# ═══════════════════════════════════════════════════════════════════════════
# RESPAWN SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func _on_enemy_died(enemy: Node, chunk_key: String) -> void:
	"""Called when an enemy dies - track for respawn"""
	if not chunk_enemies.has(chunk_key):
		return

	var chunk_data = chunk_enemies[chunk_key]

	# Record death for respawn
	if respawn_time > 0:
		chunk_data.dead_enemies.append({
			"position": enemy.global_position,
			"level": enemy.enemy_level,
			"death_time": Time.get_ticks_msec() / 1000.0
		})

func check_respawns() -> void:
	"""Check for enemies ready to respawn"""
	if respawn_time <= 0:
		return

	var current_time = Time.get_ticks_msec() / 1000.0

	for chunk_key in chunk_enemies.keys():
		var chunk_data = chunk_enemies[chunk_key]

		# Check if chunk is still loaded
		if not chunk_system.loaded_chunks.has(chunk_key):
			continue

		# Process dead enemies
		var still_dead = []
		for dead_data in chunk_data.dead_enemies:
			var time_since_death = current_time - dead_data.death_time

			if time_since_death >= respawn_time:
				# Ready to respawn - spawn new enemy
				var enemy = spawn_single_enemy(dead_data.position, dead_data.level, chunk_key)
				if enemy:
					chunk_data.enemies.append(enemy)
					print("♻️ Enemy respawned in chunk %s at (%d, %d)" % [
						chunk_key, int(dead_data.position.x), int(dead_data.position.y)
					])
			else:
				# Not ready yet
				still_dead.append(dead_data)

		chunk_data.dead_enemies = still_dead

# ═══════════════════════════════════════════════════════════════════════════
# DEBUG & STATS
# ═══════════════════════════════════════════════════════════════════════════

func get_stats() -> Dictionary:
	"""Get current spawn manager statistics"""
	var stats = {
		"total_chunks": chunk_enemies.size(),
		"total_enemies": 0,
		"enemies_per_chunk": {}
	}

	for chunk_key in chunk_enemies.keys():
		var chunk_data = chunk_enemies[chunk_key]
		chunk_data.cleanup_invalid()
		var alive = chunk_data.get_alive_count()
		stats.enemies_per_chunk[chunk_key] = alive
		stats.total_enemies += alive

	return stats

func print_stats() -> void:
	"""Print current spawn manager statistics"""
	var stats = get_stats()
	print("\n📊 CHUNK-BASED SPAWN MANAGER STATS:")
	print("   Active chunks: %d" % stats.total_chunks)
	print("   Total enemies: %d" % stats.total_enemies)
	print("   Per chunk:")
	for chunk_key in stats.enemies_per_chunk.keys():
		print("      [%s]: %d/%d" % [chunk_key, stats.enemies_per_chunk[chunk_key], ENEMIES_PER_CHUNK])
	print("")
