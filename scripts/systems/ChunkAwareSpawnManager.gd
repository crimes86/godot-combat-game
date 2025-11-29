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

## Enemies per chunk (balanced for gameplay density around lava/ritual sites)
const ENEMIES_PER_CHUNK: int = 120

## Chunk size from Constants singleton (single source of truth)
var CHUNK_SIZE: float:
	get: return Constants.CHUNK_SIZE

## Level bands - enemy level based on distance from campfire
## Campfire is at chunk 0 center (X: CHUNK_SIZE/2)
## Chunk 0 (spawn): Level 1-3 (near campfire safe, edges harder)
## Chunk -1 (west): Level 4-7
## Chunk +1 (east): Level 4-7
## Updated for 8000px chunks
var LEVEL_BANDS: Array:
	get:
		var cs = Constants.CHUNK_SIZE
		return [
			# Chunk 0 - Spawn area (X: 0 to CHUNK_SIZE)
			# Near campfire (center) is safe, edges get harder
			{"min_x": cs * 0.125, "max_x": cs * 0.875, "level": 1},     # Central 75% - level 1
			{"min_x": 0, "max_x": cs * 0.125, "level": 2},              # West edge - level 2
			{"min_x": cs * 0.875, "max_x": cs, "level": 2},             # East edge - level 2
			# Chunk -1 - West end chunk (X: -CHUNK_SIZE to 0)
			{"min_x": -cs * 0.25, "max_x": 0, "level": 3},              # Near chunk 0 border - level 3
			{"min_x": -cs * 0.625, "max_x": -cs * 0.25, "level": 4},    # Mid chunk -1 - level 4
			{"min_x": -cs, "max_x": -cs * 0.625, "level": 5},           # Far west - level 5
			# Chunk +1 - East end chunk (X: CHUNK_SIZE to CHUNK_SIZE*2)
			{"min_x": cs, "max_x": cs * 1.25, "level": 3},              # Near chunk 0 border - level 3
			{"min_x": cs * 1.25, "max_x": cs * 1.625, "level": 4},      # Mid chunk +1 - level 4
			{"min_x": cs * 1.625, "max_x": cs * 2, "level": 5},         # Far east - level 5
		]

## Respawn timer in seconds (0 = no respawn until chunk reload)
@export var respawn_time: float = 300.0  # 5 minutes

## Safe zones - no enemies spawn within these areas
## Campfire is at chunk 0 center (CHUNK_SIZE/2, 0)
var SAFE_ZONES: Array:
	get: return [
		{"pos": Vector2(Constants.CHUNK_SIZE / 2, 0), "radius": 600.0},  # Campfire spawn
	]

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
	var max_attempts = count * 10  # 10 attempts per enemy max

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
	var ritual_sites = get_ritual_sites_in_chunk(chunk_key)

	var total_lava = monster_pools.size() + regular_pools.size()
	print("💀 Chunk %s spawn anchors: %d monster lakes, %d regular pools, %d ritual sites" % [
		chunk_key, monster_pools.size(), regular_pools.size(), ritual_sites.size()
	])

	# Distribution: 45% at monster lakes, 30% at regular pools, 25% at ritual sites
	# All skeletons MUST be anchored to a landmark (no random wandering)
	var has_anchors = total_lava > 0 or ritual_sites.size() > 0
	var monster_count = int(count * 0.45) if monster_pools.size() > 0 else 0
	var regular_count = int(count * 0.30) if regular_pools.size() > 0 else 0
	var ritual_count = int(count * 0.25) if ritual_sites.size() > 0 else 0

	# Redistribute if some anchor types are missing - spread to available anchors
	if not has_anchors:
		# No anchors at all - skip spawning in this chunk
		print("⚠️ Chunk %s has no spawn anchors, skipping enemy spawns" % chunk_key)
		return

	# Calculate remainder and distribute to available anchor types
	var remainder = count - monster_count - regular_count - ritual_count
	if remainder > 0:
		if monster_pools.size() > 0:
			monster_count += remainder
		elif regular_pools.size() > 0:
			regular_count += remainder
		elif ritual_sites.size() > 0:
			ritual_count += remainder

	# Handle missing anchor types by redistributing
	if monster_pools.size() == 0 and monster_count > 0:
		if regular_pools.size() > 0 and ritual_sites.size() > 0:
			regular_count += monster_count / 2
			ritual_count += monster_count - monster_count / 2
		elif regular_pools.size() > 0:
			regular_count += monster_count
		elif ritual_sites.size() > 0:
			ritual_count += monster_count
		monster_count = 0

	if regular_pools.size() == 0 and regular_count > 0:
		if monster_pools.size() > 0:
			monster_count += regular_count
		elif ritual_sites.size() > 0:
			ritual_count += regular_count
		regular_count = 0

	if ritual_sites.size() == 0 and ritual_count > 0:
		if monster_pools.size() > 0:
			monster_count += ritual_count
		elif regular_pools.size() > 0:
			regular_count += ritual_count
		ritual_count = 0

	var monster_spawned = 0
	var regular_spawned = 0
	var ritual_spawned = 0

	# World Y bounds (half chunk height)
	var world_y_min = -Constants.CHUNK_SIZE / 2
	var world_y_max = Constants.CHUNK_SIZE / 2

	while spawned < count and attempts < max_attempts:
		attempts += 1

		var spawn_pos: Vector2
		var level: int = 1

		# Phase 1: Monster lake pools (40%) - Level scaling by distance from center
		# Edge = Level 1-3, Core/Center = Level 4-6
		if monster_spawned < monster_count and monster_pools.size() > 0:
			var pool = monster_pools[spawn_rng.randi() % monster_pools.size()]

			# Decide spawn zone: 60% edge (low level), 40% core (high level)
			var spawn_at_edge = spawn_rng.randf() < 0.6
			var angle = spawn_rng.randf() * TAU

			if spawn_at_edge:
				# Edge spawn: just outside pool radius (Level 1-3)
				var edge_dist = pool.radius + spawn_rng.randf_range(20, 100)
				spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * edge_dist
				level = spawn_rng.randi_range(1, 3)
			else:
				# Core spawn: closer to center but not IN the lava (Level 4-6)
				# Spawn between 40-80% of pool radius (inner ring)
				var core_dist = pool.radius * spawn_rng.randf_range(0.4, 0.8)
				spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * core_dist
				level = spawn_rng.randi_range(4, 6)

			# Clamp to chunk bounds
			spawn_pos.x = clamp(spawn_pos.x, chunk_min_x, chunk_max_x)
			spawn_pos.y = clamp(spawn_pos.y, world_y_min, world_y_max)

			if is_valid_spawn_position(spawn_pos):
				monster_spawned += 1
			else:
				continue

		# Phase 2: Regular small pools (25%) - Low level only (1-3)
		elif regular_spawned < regular_count and regular_pools.size() > 0:
			var pool = regular_pools[spawn_rng.randi() % regular_pools.size()]
			# Spawn at the edge of small pools
			var angle = spawn_rng.randf() * TAU
			var edge_dist = pool.radius + spawn_rng.randf_range(15, 60)
			spawn_pos = pool.pos + Vector2(cos(angle), sin(angle)) * edge_dist
			level = spawn_rng.randi_range(1, 3)  # Always low level at small pools

			# Clamp to chunk bounds
			spawn_pos.x = clamp(spawn_pos.x, chunk_min_x, chunk_max_x)
			spawn_pos.y = clamp(spawn_pos.y, world_y_min, world_y_max)

			if is_valid_spawn_position(spawn_pos):
				regular_spawned += 1
			else:
				continue

		# Phase 3: Ritual bone sites (25%) - Random levels (thematic: unknown ancient dead)
		elif ritual_spawned < ritual_count and ritual_sites.size() > 0:
			var site = ritual_sites[spawn_rng.randi() % ritual_sites.size()]
			var angle = spawn_rng.randf() * TAU
			var distance = spawn_rng.randf_range(30, 120)
			spawn_pos = site + Vector2(cos(angle), sin(angle)) * distance
			level = spawn_rng.randi_range(1, 5)  # Random mix of levels

			# Clamp to chunk bounds
			spawn_pos.x = clamp(spawn_pos.x, chunk_min_x, chunk_max_x)
			spawn_pos.y = clamp(spawn_pos.y, world_y_min, world_y_max)

			if is_valid_spawn_position(spawn_pos):
				ritual_spawned += 1
			else:
				continue

		# No more phases - all skeletons must be anchored
		else:
			# All anchor quotas filled, break out
			break

		# Spawn the enemy
		var enemy = spawn_single_enemy(spawn_pos, level, chunk_key)
		if enemy:
			chunk_data.enemies.append(enemy)
			spawned += 1

	if spawned > 0:
		print("✨ Spawned %d enemies in chunk %s (total: %d/%d)" % [
			spawned, chunk_key, chunk_data.get_alive_count(), chunk_data.target_count
		])
		print("   📍 Monster lakes: %d (L1-6), Regular pools: %d (L1-3), Ritual sites: %d (L1-5)" % [
			monster_spawned, regular_spawned, ritual_spawned
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
