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

## Enemies per chunk - reduced for West→East progression with concentrated camps
## 80 random spawns + camps near lava pools = good density without overwhelming
const ENEMIES_PER_CHUNK: int = 80

## Camp system - higher density clusters near environmental features
const CAMP_SPAWN_RADIUS: float = 150.0  # Enemies spawn within this radius of camp center
const CAMP_MIN_ENEMIES: int = 4  # Minimum enemies per camp
const CAMP_MAX_ENEMIES: int = 8  # Maximum enemies per camp

## Chunk size from Constants singleton (single source of truth)
var CHUNK_SIZE: float:
	get: return Constants.CHUNK_SIZE

## Level bands - enemy level based on X position (West→East progression)
## Campfire is at X: -6000 (chunk -1), players progress eastward to Zone 2 at chunk +1
##
## West→East Layout:
##   Campfire (-6000) → L1-5 (chunk -1) → L5-9 (chunk 0) → L9-15 (chunk +1) → Zone 2 Cave
##
## World spans X: -8000 to +16000 (24,000px total across 3 chunks)
var LEVEL_BANDS: Array:
	get:
		var cs = Constants.CHUNK_SIZE  # 8000px
		return [
			# Chunk -1 (start): Campfire at -6000, levels 1-5
			# X: -8000 to 0
			{"min_x": -cs, "max_x": -cs * 0.5, "level": 1},        # -8000 to -4000: L1 (near campfire)
			{"min_x": -cs * 0.5, "max_x": 0, "level": 3},          # -4000 to 0: L3

			# Chunk 0 (mid): Levels 5-9, harder enemies
			# X: 0 to 8000
			{"min_x": 0, "max_x": cs * 0.5, "level": 5},           # 0 to 4000: L5
			{"min_x": cs * 0.5, "max_x": cs, "level": 7},          # 4000 to 8000: L7

			# Chunk +1 (end): Levels 9-15, Zone 2 entrance at east edge
			# X: 8000 to 16000
			{"min_x": cs, "max_x": cs * 1.5, "level": 9},          # 8000 to 12000: L9
			{"min_x": cs * 1.5, "max_x": cs * 2, "level": 12},     # 12000 to 16000: L12 (near Zone 2)
		]

## Respawn timer in seconds (0 = no respawn until chunk reload)
@export var respawn_time: float = 90.0  # 90 seconds

## Minimum spacing between spawned enemies (prevents crowding)
const MIN_ENEMY_SPACING: float = 80.0

## Roaming enemy configuration (wolves and spiders in open areas)
const ROAMING_SPAWN_DISTANCE_MIN: float = 400.0  # Min distance from lava pools
const ROAMING_SPAWN_DISTANCE_MAX: float = 800.0  # Max distance for open area spawns
const DIRE_WOLF_CHANCE: float = 0.08  # 8% chance for a roaming wolf to be a dire wolf
const ROAMING_SKELETON_WEIGHT: float = 0.40  # 40% roaming skeletons in open areas
const SPIDER_SPAWN_WEIGHT: float = 0.50  # Of remaining 60%: 50% spiders = 30% total
# Remaining 50% of 60% = 30% wolves

## Safe zones - no enemies spawn within these areas
## Campfire is at west side of chunk -1 (X: -6000) for West→East progression
var SAFE_ZONES: Array:
	get: return [
		{"pos": Vector2(-6000, 0), "radius": 600.0},  # Campfire spawn (west start)
	]

## Tutorial zone - enemies within this radius of campfire are always level 1
const TUTORIAL_ZONE_RADIUS: float = 1200.0
var CAMPFIRE_POSITION: Vector2:
	get: return Vector2(-6000, 0)  # West side of chunk -1

## Ruins areas - no random spawns (guardians spawn separately)
## Dynamically populated from game_world.RUINS_POSITIONS at runtime
const RUINS_EXCLUSION_RADIUS: float = 350.0
var ruins_areas: Array = []  # Populated in _ready() from game_world

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

## Network enemy manager reference
var network_enemy_manager: Node = null

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

	# Get NetworkEnemyManager autoload for multiplayer sync
	network_enemy_manager = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_manager:
		print("🌐 SpawnManager: NetworkEnemyManager connected for multiplayer sync")

	# Create seeded RNG for consistent spawns
	spawn_rng = RandomNumberGenerator.new()
	spawn_rng.seed = 12345  # Fixed seed for reproducibility

	# Populate ruins_areas from game_world's procedurally generated positions
	ruins_areas.clear()
	if game_world and game_world.get("RUINS_POSITIONS"):
		for ruins_key in game_world.RUINS_POSITIONS:
			var ruins_data = game_world.RUINS_POSITIONS[ruins_key]
			var pos = ruins_data.position if ruins_data is Dictionary else ruins_data
			ruins_areas.append({"pos": pos, "radius": RUINS_EXCLUSION_RADIUS})
		print("🏛️ SpawnManager: Loaded %d ruins exclusion zones" % ruins_areas.size())

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

	# Handle unloaded chunks - despawn enemies
	# In multiplayer, only server handles enemy despawning
	var should_handle_despawn = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	if should_handle_despawn:
		var chunks_to_remove = []
		for chunk_key in chunk_enemies.keys():
			if not loaded_chunks.has(chunk_key):
				chunks_to_remove.append(chunk_key)

		for chunk_key in chunks_to_remove:
			on_chunk_unloaded(chunk_key)

func on_chunk_loaded(chunk_key: String) -> void:
	"""Called when a chunk is loaded - spawn enemies (server only in multiplayer)"""
	# In multiplayer, only server spawns enemies
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

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
	var max_attempts = count * 15  # 15 attempts per enemy max (more attempts for spacing checks)

	# Track spawn positions in this chunk to enforce minimum spacing
	var spawn_positions: Array[Vector2] = []
	# Also consider existing enemies in the chunk
	for enemy in chunk_data.enemies:
		if is_instance_valid(enemy):
			spawn_positions.append(enemy.global_position)

	# Parse chunk coordinates
	var chunk_parts = chunk_key.split(",")
	var chunk_x = int(chunk_parts[0])
	var chunk_min_x = chunk_x * CHUNK_SIZE
	var chunk_max_x = (chunk_x + 1) * CHUNK_SIZE

	# Use chunk-specific seed for consistent spawns
	var chunk_seed = hash(chunk_key) + chunk_data.enemies.size()
	spawn_rng.seed = chunk_seed

	# Get spawn anchor points from the prop system
	var lava_data = get_lava_pools_in_chunk(chunk_key)
	var monster_pools = lava_data.monster   # Large lake pools (high level cores)
	var regular_pools = lava_data.regular   # Small isolated pools (low level)
	var all_pools = lava_data.all           # All lava pools for roaming exclusion

	var total_lava = monster_pools.size() + regular_pools.size()
	print("💀 Chunk %s spawn anchors: %d monster lakes, %d regular pools" % [
		chunk_key, monster_pools.size(), regular_pools.size()
	])

	# Distribution: 45% at monster lakes, 30% at regular pools, 25% roaming wolves/spiders
	# Skeletons spawn at lava, wolves/spiders roam open areas
	var has_lava = total_lava > 0
	var monster_count = int(count * 0.45) if monster_pools.size() > 0 else 0
	var regular_count = int(count * 0.30) if regular_pools.size() > 0 else 0
	var roaming_count = int(count * 0.25)  # Always have roaming enemies

	# If no lava pools, shift all skeleton spawns to roaming
	if not has_lava:
		roaming_count = count
		monster_count = 0
		regular_count = 0

	# Calculate remainder and distribute
	var remainder = count - monster_count - regular_count - roaming_count
	if remainder > 0:
		roaming_count += remainder

	# Handle missing anchor types by redistributing
	if monster_pools.size() == 0 and monster_count > 0:
		if regular_pools.size() > 0:
			regular_count += monster_count / 2
			roaming_count += monster_count - monster_count / 2
		else:
			roaming_count += monster_count
		monster_count = 0

	if regular_pools.size() == 0 and regular_count > 0:
		if monster_pools.size() > 0:
			monster_count += regular_count / 2
			roaming_count += regular_count - regular_count / 2
		else:
			roaming_count += regular_count
		regular_count = 0

	var monster_spawned = 0
	var regular_spawned = 0
	var roaming_spawned = 0

	# Per-pool spawn limits to prevent crowding
	const MAX_ENEMIES_PER_MONSTER_POOL: int = 8
	const MAX_ENEMIES_PER_REGULAR_POOL: int = 4

	# Track spawns per pool (by index)
	var monster_pool_counts: Dictionary = {}  # pool_index -> count
	var regular_pool_counts: Dictionary = {}  # pool_index -> count

	# World Y bounds (half chunk height)
	var world_y_min = -Constants.CHUNK_SIZE / 2
	var world_y_max = Constants.CHUNK_SIZE / 2

	while spawned < count and attempts < max_attempts:
		attempts += 1

		var spawn_pos: Vector2
		var level: int = 1
		var spawn_type: String = "skeleton"  # Track what type to spawn
		var selected_pool_idx: int = -1  # Track which pool was selected

		# Phase 1: Monster lake pools (45%) - Level scaling by distance from center
		# Edge = Level 1-3, Core/Center = Level 4-6
		if monster_spawned < monster_count and monster_pools.size() > 0:
			# Find a pool that hasn't reached its limit
			var available_pools: Array = []
			for idx in range(monster_pools.size()):
				var current_count = monster_pool_counts.get(idx, 0)
				if current_count < MAX_ENEMIES_PER_MONSTER_POOL:
					available_pools.append(idx)

			# If all pools are full, shift remaining to roaming
			if available_pools.is_empty():
				roaming_count += monster_count - monster_spawned
				monster_count = monster_spawned
				continue

			selected_pool_idx = available_pools[spawn_rng.randi() % available_pools.size()]
			var pool = monster_pools[selected_pool_idx]

			# Decide spawn zone: 60% edge (low level), 40% core (high level)
			var spawn_at_edge = spawn_rng.randf() < 0.6
			var angle = spawn_rng.randf() * TAU

			if spawn_at_edge:
				# Edge spawn: further from pool (Level 1-3)
				var edge_dist = pool.radius + spawn_rng.randf_range(80, 200)
				spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * edge_dist
				level = spawn_rng.randi_range(1, 3)
			else:
				# Core spawn: just outside the lava edge (Level 4-6)
				# Spawn just outside pool radius (not inside!)
				var core_dist = pool.radius + spawn_rng.randf_range(20, 60)
				spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * core_dist
				level = spawn_rng.randi_range(4, 6)

			# Clamp to chunk bounds
			spawn_pos.x = clamp(spawn_pos.x, chunk_min_x, chunk_max_x)
			spawn_pos.y = clamp(spawn_pos.y, world_y_min, world_y_max)

			if is_valid_spawn_position(spawn_pos) and is_position_spaced(spawn_pos, spawn_positions):
				monster_spawned += 1
				monster_pool_counts[selected_pool_idx] = monster_pool_counts.get(selected_pool_idx, 0) + 1
				spawn_type = "skeleton"
			else:
				continue

		# Phase 2: Regular small pools (30%) - Low level only (1-3)
		elif regular_spawned < regular_count and regular_pools.size() > 0:
			# Find a pool that hasn't reached its limit
			var available_pools: Array = []
			for idx in range(regular_pools.size()):
				var current_count = regular_pool_counts.get(idx, 0)
				if current_count < MAX_ENEMIES_PER_REGULAR_POOL:
					available_pools.append(idx)

			# If all pools are full, shift remaining to roaming
			if available_pools.is_empty():
				roaming_count += regular_count - regular_spawned
				regular_count = regular_spawned
				continue

			selected_pool_idx = available_pools[spawn_rng.randi() % available_pools.size()]
			var pool = regular_pools[selected_pool_idx]

			# Spawn at the edge of small pools - increased distance range
			var angle = spawn_rng.randf() * TAU
			var edge_dist = pool.radius + spawn_rng.randf_range(30, 120)
			spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * edge_dist
			level = spawn_rng.randi_range(1, 3)  # Always low level at small pools

			# Clamp to chunk bounds
			spawn_pos.x = clamp(spawn_pos.x, chunk_min_x, chunk_max_x)
			spawn_pos.y = clamp(spawn_pos.y, world_y_min, world_y_max)

			if is_valid_spawn_position(spawn_pos) and is_position_spaced(spawn_pos, spawn_positions):
				regular_spawned += 1
				regular_pool_counts[selected_pool_idx] = regular_pool_counts.get(selected_pool_idx, 0) + 1
				spawn_type = "skeleton"
			else:
				continue

		# Phase 3: Roaming wolves/spiders in open areas (25%)
		# These spawn AWAY from lava pools in the open dreadland
		elif roaming_spawned < roaming_count:
			# Find a position away from all lava pools
			spawn_pos = find_open_area_spawn(chunk_min_x, chunk_max_x, world_y_min, world_y_max, all_pools)
			if spawn_pos == Vector2.ZERO:
				continue

			# Determine level based on chunk position
			if chunk_x == 0:
				level = spawn_rng.randi_range(1, 5)
			else:
				level = spawn_rng.randi_range(5, 9)

			if is_valid_spawn_position(spawn_pos) and is_position_spaced(spawn_pos, spawn_positions):
				roaming_spawned += 1
				spawn_type = "roaming"
			else:
				continue

		# All quotas filled
		else:
			break

		# Spawn the enemy based on type
		var enemy: Node = null
		if spawn_type == "roaming":
			# Roaming spawn - spawn wolf or spider
			enemy = spawn_roaming_enemy(spawn_pos, level, chunk_key)
		else:
			# Lava pool spawn - spawn skeleton
			enemy = spawn_single_enemy(spawn_pos, level, chunk_key)

		if enemy:
			chunk_data.enemies.append(enemy)
			spawn_positions.append(spawn_pos)
			spawned += 1

	if spawned > 0:
		print("✨ Spawned %d enemies in chunk %s (total: %d)" % [
			spawned, chunk_key, chunk_data.get_alive_count()
		])
		print("   📍 Monster lakes: %d (L1-6), Regular pools: %d (L1-3), Roaming: %d (skeletons/wolves/spiders)" % [
			monster_spawned, regular_spawned, roaming_spawned
		])

func spawn_single_enemy(pos: Vector2, level: int, chunk_key: String) -> Node:
	"""Spawn a single enemy at position"""
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		push_error("Failed to load enemy scene!")
		return null

	var enemy = enemy_scene.instantiate()
	enemy.enemy_level = level

	# Generate unique name
	var enemy_name = "Enemy_%s_%d" % [chunk_key.replace(",", "_"), randi()]
	enemy.name = enemy_name

	# Set position BEFORE adding to tree, so _ready() sees the correct position
	# Use 'position' (local) since game_world is at origin, this equals global_position
	enemy.position = pos

	# Add to world - _ready() will run and see the correct position
	game_world.add_child(enemy)

	# Register with network enemy manager for multiplayer sync
	var network_id = -1
	if network_enemy_manager:
		network_id = network_enemy_manager.register_enemy(enemy)

	# Connect death signal for respawn tracking
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(enemy, chunk_key))

	# Connect corpse loot signal
	if enemy.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		enemy.corpse_clicked.connect(game_world._on_corpse_clicked)

	# In multiplayer, sync to clients via NetworkEnemyManager
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and network_enemy_manager:
		network_enemy_manager.spawn_enemy_on_clients.rpc(network_id, pos, level, enemy_name)

	return enemy

func find_open_area_spawn(min_x: float, max_x: float, min_y: float, max_y: float, lava_pools: Array) -> Vector2:
	"""Find a spawn position in open areas away from lava pools"""
	var attempts = 0
	var max_attempts = 20

	while attempts < max_attempts:
		attempts += 1

		# Random position within chunk bounds
		var pos = Vector2(
			spawn_rng.randf_range(min_x + 100, max_x - 100),
			spawn_rng.randf_range(min_y + 100, max_y - 100)
		)

		# Check distance from all lava pools
		var too_close = false
		for pool in lava_pools:
			var pool_pos = pool.pos if pool is Dictionary else pool
			var pool_radius = pool.radius if pool is Dictionary else 100.0
			var min_distance = pool_radius + ROAMING_SPAWN_DISTANCE_MIN
			if pos.distance_to(pool_pos) < min_distance:
				too_close = true
				break

		if not too_close:
			return pos

	return Vector2.ZERO


func spawn_roaming_enemy(pos: Vector2, level: int, chunk_key: String) -> Node:
	"""Spawn a roaming enemy (skeleton, wolf, or spider) in open areas"""
	var roll = spawn_rng.randf()

	# 40% chance for roaming skeleton
	if roll < ROAMING_SKELETON_WEIGHT:
		return spawn_single_enemy(pos, level, chunk_key)

	# Remaining 60% split between wolves and spiders
	# SPIDER_SPAWN_WEIGHT (0.5) of remaining 60% = 30% spiders
	var remaining_roll = (roll - ROAMING_SKELETON_WEIGHT) / (1.0 - ROAMING_SKELETON_WEIGHT)
	if remaining_roll < SPIDER_SPAWN_WEIGHT:
		return spawn_single_spider(pos, level, chunk_key)
	else:
		# 30% wolves (with rare dire wolf chance)
		var is_dire = spawn_rng.randf() < DIRE_WOLF_CHANCE
		return spawn_single_wolf_roaming(pos, level, chunk_key, is_dire)


func spawn_single_spider(pos: Vector2, level: int, chunk_key: String) -> Node:
	"""Spawn a single spider at position"""
	var spider_scene = load("res://scenes/enemies/spider.tscn")
	if not spider_scene:
		push_error("Failed to load spider scene!")
		return null

	var spider = spider_scene.instantiate()
	spider.enemy_level = level

	# Random spider variant (1-11)
	spider.spider_variant = spawn_rng.randi_range(1, 11)

	# Generate unique name
	var spider_name = "Spider_%s_%d" % [chunk_key.replace(",", "_"), randi()]
	spider.name = spider_name

	# Set position BEFORE adding to tree
	spider.position = pos

	# Add to world
	game_world.add_child(spider)

	# Register with network enemy manager for multiplayer sync
	if network_enemy_manager:
		var network_id = network_enemy_manager.register_enemy(spider)
		# Broadcast to clients so they spawn the same enemy
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_manager.spawn_enemy_on_clients.rpc(network_id, pos, spider.enemy_level, spider.name)

	# Connect death signal for respawn tracking
	if spider.has_signal("died"):
		spider.died.connect(_on_roaming_enemy_died.bind(spider, chunk_key, "spider"))

	# Connect corpse loot signal
	if spider.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		spider.corpse_clicked.connect(game_world._on_corpse_clicked)

	return spider


func spawn_single_wolf_roaming(pos: Vector2, level: int, chunk_key: String, is_dire: bool = false) -> Node:
	"""Spawn a single roaming wolf at position (no pack behavior)"""
	var wolf_scene = load("res://scenes/enemies/wolf.tscn")
	if not wolf_scene:
		push_error("Failed to load wolf scene!")
		return null

	var wolf = wolf_scene.instantiate()
	wolf.enemy_level = level

	# Roaming wolves have no pack - they're lone wolves
	wolf.pack_id = ""
	wolf.pack_alpha = false

	# Dire wolves are stronger and have special visual
	if is_dire:
		wolf.enemy_level = level + 3  # Dire wolves are +3 levels
		wolf.max_health *= 2.0  # Double health
		wolf.base_damage *= 1.5  # 50% more damage
		# The wolf script can check for dire status via level/stats

	# Generate unique name
	var wolf_name = "%s_%s_%d" % ["DireWolf" if is_dire else "Wolf", chunk_key.replace(",", "_"), randi()]
	wolf.name = wolf_name

	# Set position BEFORE adding to tree
	wolf.position = pos

	# Add to world
	game_world.add_child(wolf)

	# Register with network enemy manager for multiplayer sync
	if network_enemy_manager:
		var network_id = network_enemy_manager.register_enemy(wolf)
		# Broadcast to clients so they spawn the same enemy
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_manager.spawn_enemy_on_clients.rpc(network_id, pos, wolf.enemy_level, wolf.name)

	# Connect death signal for respawn tracking
	if wolf.has_signal("died"):
		wolf.died.connect(_on_roaming_enemy_died.bind(wolf, chunk_key, "wolf"))

	# Connect corpse loot signal
	if wolf.has_signal("corpse_clicked") and game_world.has_method("_on_corpse_clicked"):
		wolf.corpse_clicked.connect(game_world._on_corpse_clicked)

	if is_dire:
		print("🐺💀 Spawned DIRE WOLF at L%d in chunk %s!" % [wolf.enemy_level, chunk_key])

	return wolf


func _on_roaming_enemy_died(enemy: Node, chunk_key: String, enemy_type: String) -> void:
	"""Called when a roaming wolf or spider dies - track for respawn"""
	if not chunk_enemies.has(chunk_key):
		return

	var chunk_data = chunk_enemies[chunk_key]

	# Record death for respawn
	if respawn_time > 0:
		chunk_data.dead_enemies.append({
			"position": enemy.global_position,
			"level": enemy.enemy_level,
			"death_time": Time.get_ticks_msec() / 1000.0,
			"enemy_type": enemy_type,
			"is_roaming": true
		})


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

	# Check ruins areas (dynamically populated)
	for ruins in ruins_areas:
		if pos.distance_to(ruins.pos) < ruins.radius:
			return false

	# Check world bounds (Y: -CHUNK_SIZE/2 to CHUNK_SIZE/2)
	var y_bound = Constants.CHUNK_SIZE / 2
	if pos.y < -y_bound or pos.y > y_bound:
		return false

	# Don't spawn enemies on or near the path (100px buffer)
	if is_position_on_path(pos, 100):
		return false

	return true

func is_position_spaced(pos: Vector2, existing_positions: Array[Vector2]) -> bool:
	"""Check if position maintains minimum spacing from existing enemies"""
	for existing_pos in existing_positions:
		if pos.distance_to(existing_pos) < MIN_ENEMY_SPACING:
			return false
	return true

func is_position_on_path(pos: Vector2, buffer: float = 100.0) -> bool:
	"""Check if position is on the main path or branch paths to ruins"""
	# Main path runs from world edge to world edge
	# Zigzag amplitude is ~350px, so path can be anywhere from Y=-350 to Y=350
	const PATH_WIDTH: float = 250.0

	# Path extends across entire world (100px buffer from edges)
	var path_start_x = -Constants.CHUNK_SIZE + 100
	var path_end_x = Constants.CHUNK_SIZE * 2 - 100

	# Check if near the main horizontal path corridor (Y close to 0)
	if abs(pos.y) < buffer + 350:  # 350 is zigzag amplitude
		# Check if in the full path X range (entire world)
		if pos.x >= path_start_x and pos.x <= path_end_x:
			return true

	# Check branch paths to ruins (if RUINS_POSITIONS exists in game_world)
	if game_world and game_world.get("RUINS_POSITIONS"):
		for ruins_key in game_world.RUINS_POSITIONS:
			var ruins_data = game_world.RUINS_POSITIONS[ruins_key]
			var ruins_pos = ruins_data.position if ruins_data is Dictionary else ruins_data
			# Branch paths connect from main path to ruins
			# Estimate branch point on main path (roughly at ruins X ± 400)
			var branch_x = ruins_pos.x + 400 if ruins_pos.x < 2000 else ruins_pos.x - 400
			var branch_point = Vector2(branch_x, 0)  # Main path is roughly at Y=0
			# Check if position is along the line from branch point to ruins
			var dist_to_path = point_to_line_distance(pos, branch_point, ruins_pos)
			if dist_to_path < buffer + PATH_WIDTH:
				# Also check if within the segment bounds (not beyond the line)
				var to_pos = pos - branch_point
				var to_ruins = ruins_pos - branch_point
				if to_ruins.length_squared() > 0:
					var t = to_pos.dot(to_ruins) / to_ruins.length_squared()
					if t >= 0 and t <= 1:
						return true

	return false

func point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calculate perpendicular distance from point to line segment"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_length = line_vec.length()
	if line_length == 0:
		return point_vec.length()
	var line_unit = line_vec / line_length
	var proj_length = point_vec.dot(line_unit)
	proj_length = clamp(proj_length, 0, line_length)
	var closest_point = line_start + line_unit * proj_length
	return point.distance_to(closest_point)

func get_level_for_position(pos: Vector2) -> int:
	"""Get enemy level based on X position"""
	# Tutorial zone: enemies near campfire are always level 1
	if pos.distance_to(CAMPFIRE_POSITION) <= TUTORIAL_ZONE_RADIUS:
		return 1

	for band in LEVEL_BANDS:
		if pos.x >= band.min_x and pos.x < band.max_x:
			return band.level
	return 1  # Default level 1

func get_chunk_key(world_pos: Vector2) -> String:
	"""Get chunk key from world position"""
	var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
	return "%d,0" % chunk_x

func get_lava_pools_in_chunk(chunk_key: String) -> Dictionary:
	"""Get lava pool positions from the chunk prop system, separated by type"""
	var result = {"monster": [], "regular": [], "all": []}

	if not game_world:
		return result

	# Access chunk_prop_system variable directly (not by node name)
	if not game_world.get("chunk_prop_system"):
		return result

	var prop_system = game_world.chunk_prop_system

	# Check if using cell streaming mode
	if prop_system and prop_system.USE_CELL_STREAMING:
		# Get lava positions from CellStreamingManager instead
		var cell_manager = game_world.get("cell_streaming_manager")
		if cell_manager and cell_manager.global_lava_positions.size() > 0:
			# Parse chunk bounds
			var chunk_parts = chunk_key.split(",")
			var chunk_x = int(chunk_parts[0])
			var chunk_min_x = chunk_x * Constants.CHUNK_SIZE
			var chunk_max_x = (chunk_x + 1) * Constants.CHUNK_SIZE

			# Filter lava positions to those within this chunk
			for lava_pos in cell_manager.global_lava_positions:
				if lava_pos.x >= chunk_min_x and lava_pos.x < chunk_max_x:
					var pool_data = {"pos": lava_pos, "radius": 100.0}
					result.all.append(pool_data)
					# Classify as monster or regular based on position
					# Monster pools tend to be larger and in specific locations
					# For now, treat first few as monster pools
					if result.monster.size() < 3:
						result.monster.append(pool_data)
					else:
						result.regular.append(pool_data)

			return result

	# Traditional chunk-based loading path
	if not prop_system or not prop_system.loaded_chunks.has(chunk_key):
		return result

	var chunk_data = prop_system.loaded_chunks[chunk_key]
	if not chunk_data:
		return result

	# Get monster (large lake) pools
	if chunk_data.monster_lava_positions:
		result.monster = chunk_data.monster_lava_positions

	# Get all pools (includes monster pools)
	if chunk_data.lava_pool_positions:
		result.all = chunk_data.lava_pool_positions

		# Regular pools = all pools minus monster pools
		var monster_positions = []
		for m in result.monster:
			monster_positions.append(m.pos)

		for pool in chunk_data.lava_pool_positions:
			var is_monster = false
			for m_pos in monster_positions:
				if pool.pos.distance_to(m_pos) < 10:  # Same position = monster pool
					is_monster = true
					break
			if not is_monster:
				result.regular.append(pool)

	return result

func get_ritual_sites_in_chunk(chunk_key: String) -> Array:
	"""Get ritual bone site positions from the chunk prop system"""
	if not game_world:
		return []

	# Access chunk_prop_system variable directly (not by node name)
	if not game_world.get("chunk_prop_system"):
		return []

	var prop_system = game_world.chunk_prop_system
	if not prop_system or not prop_system.loaded_chunks.has(chunk_key):
		return []

	var chunk_data = prop_system.loaded_chunks[chunk_key]
	if chunk_data and chunk_data.ritual_sites:
		return chunk_data.ritual_sites

	return []

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

		# Build list of existing enemy positions for spacing check
		var existing_positions: Array[Vector2] = []
		for existing_enemy in chunk_data.enemies:
			if is_instance_valid(existing_enemy) and not existing_enemy.is_corpse:
				existing_positions.append(existing_enemy.global_position)

		# Process dead enemies
		var still_dead = []
		for dead_data in chunk_data.dead_enemies:
			var time_since_death = current_time - dead_data.death_time

			if time_since_death >= respawn_time:
				# Find a valid respawn position (original or offset if blocked)
				var respawn_pos = find_spaced_respawn_position(dead_data.position, existing_positions)

				if respawn_pos != Vector2.ZERO:
					# Spawn the correct enemy type
					var enemy: Node = null
					var enemy_type = dead_data.get("enemy_type", "skeleton")
					var is_roaming = dead_data.get("is_roaming", false)

					if is_roaming:
						# Roaming enemies respawn as a random roaming type
						enemy = spawn_roaming_enemy(respawn_pos, dead_data.level, chunk_key)
					elif enemy_type == "spider":
						enemy = spawn_single_spider(respawn_pos, dead_data.level, chunk_key)
					elif enemy_type == "wolf":
						enemy = spawn_single_wolf_roaming(respawn_pos, dead_data.level, chunk_key, false)
					else:
						# Default: skeleton
						enemy = spawn_single_enemy(respawn_pos, dead_data.level, chunk_key)

					if enemy:
						chunk_data.enemies.append(enemy)
						existing_positions.append(respawn_pos)  # Track for next respawn in same batch
						print("♻️ %s respawned in chunk %s at (%d, %d)" % [
							enemy_type.capitalize(), chunk_key, int(respawn_pos.x), int(respawn_pos.y)
						])
				else:
					# Couldn't find valid position, delay respawn
					dead_data.death_time = current_time - respawn_time + 5.0  # Try again in 5 seconds
					still_dead.append(dead_data)
			else:
				# Not ready yet
				still_dead.append(dead_data)

		chunk_data.dead_enemies = still_dead

func find_spaced_respawn_position(original_pos: Vector2, existing_positions: Array[Vector2]) -> Vector2:
	"""Find a respawn position that maintains spacing from existing enemies"""
	# First try the original position - must also be valid (not in safe zones)
	if is_valid_spawn_position(original_pos) and is_position_spaced(original_pos, existing_positions):
		return original_pos

	# Try offset positions in a spiral pattern
	var offsets = [
		Vector2(MIN_ENEMY_SPACING, 0),
		Vector2(-MIN_ENEMY_SPACING, 0),
		Vector2(0, MIN_ENEMY_SPACING),
		Vector2(0, -MIN_ENEMY_SPACING),
		Vector2(MIN_ENEMY_SPACING, MIN_ENEMY_SPACING),
		Vector2(-MIN_ENEMY_SPACING, MIN_ENEMY_SPACING),
		Vector2(MIN_ENEMY_SPACING, -MIN_ENEMY_SPACING),
		Vector2(-MIN_ENEMY_SPACING, -MIN_ENEMY_SPACING),
	]

	for offset in offsets:
		var candidate = original_pos + offset
		if is_valid_spawn_position(candidate) and is_position_spaced(candidate, existing_positions):
			return candidate

	# No valid position found
	return Vector2.ZERO

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
