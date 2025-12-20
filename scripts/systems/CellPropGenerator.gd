extends Node
class_name CellPropGenerator

## Cell Prop Generator
## Generates deterministic prop lists for each cell based on cell coordinates
## Actual prop creation delegates to ChunkBasedPropSystem for consistency

# Reference to streaming manager
var streaming_manager: CellStreamingManager = null
var chunk_prop_system: ChunkBasedPropSystem = null
var world_seed: int = 12345

# Cell size from constants
var CELL_SIZE: float:
	get: return Constants.CELL_SIZE
var CHUNK_SIZE: float:
	get: return Constants.CHUNK_SIZE

# Props per cell (distributed from chunk totals)
# Chunk has ~900 props, cell is 1/64 of chunk area
const TREES_PER_CELL: int = 3  # 180/64 ≈ 3
const ROCKS_LARGE_PER_CELL: int = 1  # 60/64 ≈ 1
const ROCKS_MEDIUM_PER_CELL: int = 1  # 30/64 ≈ 0.5, round up
const ROCKS_SMALL_PER_CELL: int = 1  # 25/64 ≈ 0.4, round up
const LAVA_POOLS_PER_CELL: int = 0  # Handled specially (cluster-based)
const BLISTER_POOLS_PER_CELL: int = 1  # 45/64 ≈ 0.7
const BONE_CLUSTERS_PER_CELL: int = 0  # 16/64 ≈ 0.25, rare
const SCATTERED_BONES_PER_CELL: int = 1  # 35/64 ≈ 0.5
const VEGETATION_PER_CELL: int = 0  # 12/64 ≈ 0.2, rare
const CRACKS_PER_CELL: int = 0  # 15/64 ≈ 0.25, rare

# Probability for rare props (per cell)
const LAVA_POOL_CHANCE: float = 0.08  # ~10/64 cells have a lava pool
const BONE_CLUSTER_CHANCE: float = 0.25  # ~16/64 cells
const VEGETATION_CHANCE: float = 0.2  # ~12/64 cells
const CRACK_CHANCE: float = 0.25  # ~15/64 cells
const MONSTER_LAVA_CHANCE: float = 0.015  # ~3 per chunk (very rare)

# Special zones to avoid
# Campfire is at center of chunk 0: (CHUNK_SIZE / 2, 0) = (4000, 0)
var CAMPFIRE_POS: Vector2:
	get: return Vector2(Constants.CHUNK_SIZE / 2, 0)
const CAMPFIRE_SAFE_RADIUS = 1050.0
const PATH_WIDTH = 200.0

func initialize(p_streaming_manager: CellStreamingManager, p_world_seed: int) -> void:
	"""Initialize the prop generator"""
	streaming_manager = p_streaming_manager
	world_seed = p_world_seed
	# chunk_prop_system will be set by CellStreamingManager after initialization

func set_chunk_prop_system(p_chunk_prop_system: ChunkBasedPropSystem) -> void:
	"""Set reference to ChunkBasedPropSystem for prop creation"""
	chunk_prop_system = p_chunk_prop_system

func get_cell_rng(cell_key: String) -> RandomNumberGenerator:
	"""Get deterministic RNG for a cell"""
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(cell_key) + world_seed
	return rng

func get_cell_bounds(cell_key: String) -> Rect2:
	"""Get world bounds of a cell"""
	var parts = cell_key.split(",")
	var cell_x = int(parts[0])
	var cell_y = int(parts[1])
	return Rect2(
		cell_x * CELL_SIZE,
		cell_y * CELL_SIZE,
		CELL_SIZE,
		CELL_SIZE
	)

func get_chunk_key_for_cell(cell_key: String) -> String:
	"""Get the parent chunk key for a cell"""
	var parts = cell_key.split(",")
	var cell_x = int(parts[0])
	var cell_y = int(parts[1])

	# Calculate chunk from cell position
	var world_x = cell_x * CELL_SIZE + CELL_SIZE / 2
	var chunk_x = floori(world_x / CHUNK_SIZE)
	return "%d,0" % chunk_x

func generate_prop_list(cell_key: String) -> Array:
	"""Generate deterministic prop list for a cell"""
	var props = []
	var rng = get_cell_rng(cell_key)
	var bounds = get_cell_bounds(cell_key)
	var chunk_key = get_chunk_key_for_cell(cell_key)

	# Generate props with positions
	# Order: Lava first (exclusion zones), then trees, rocks, decorative

	# Monster lava pools (very rare, anchor points)
	if rng.randf() < MONSTER_LAVA_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "monster_lava_pool",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Regular lava pools
	if rng.randf() < LAVA_POOL_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "lava_pool",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Blister pools (small lava)
	for i in range(BLISTER_POOLS_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "blister_pool",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Trees (lootable)
	for i in range(TREES_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		var tree_id = "%s:tree:%d" % [cell_key, i]
		if _is_valid_position(pos) and not streaming_manager.is_harvested(tree_id):
			props.append({
				"type": "tree",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"index": i,
				"tree_id": tree_id,
				"rng_offset": rng.randi()
			})

	# Large rocks (lootable)
	for i in range(ROCKS_LARGE_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		var rock_id = "%s:rock_large:%d" % [cell_key, i]
		if _is_valid_position(pos) and not streaming_manager.is_harvested(rock_id):
			props.append({
				"type": "rock_large",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"index": i,
				"rock_id": rock_id,
				"rng_offset": rng.randi()
			})

	# Medium rocks (decorative)
	for i in range(ROCKS_MEDIUM_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "rock_medium",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Small rocks (decorative)
	for i in range(ROCKS_SMALL_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "rock_small",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Bone clusters (rare)
	if rng.randf() < BONE_CLUSTER_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "bone_cluster",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Scattered bones
	for i in range(SCATTERED_BONES_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "scattered_bone",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Vegetation (rare)
	if rng.randf() < VEGETATION_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "vegetation",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Ground cracks (rare)
	if rng.randf() < CRACK_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "crack",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	return props

func _random_position_in_bounds(bounds: Rect2, rng: RandomNumberGenerator) -> Vector2:
	"""Get random position within cell bounds"""
	return Vector2(
		rng.randf_range(bounds.position.x, bounds.position.x + bounds.size.x),
		rng.randf_range(bounds.position.y, bounds.position.y + bounds.size.y)
	)

func _is_valid_position(pos: Vector2) -> bool:
	"""Check if position is valid for prop placement"""
	# Check campfire safe zone
	if pos.distance_to(CAMPFIRE_POS) < CAMPFIRE_SAFE_RADIUS:
		return false

	# Check world bounds
	if pos.x < Constants.WORLD_LEFT or pos.x > Constants.WORLD_RIGHT:
		return false
	if pos.y < Constants.WORLD_TOP or pos.y > Constants.WORLD_BOTTOM:
		return false

	# Check exclusion zones (lava, large rocks)
	if streaming_manager and streaming_manager.is_position_in_exclusion_zone(pos):
		return false

	return true

func _is_on_path(pos: Vector2) -> bool:
	"""Check if position is on the main path"""
	# Main path runs along Y=0
	return abs(pos.y) < PATH_WIDTH

func create_prop(prop_def: Dictionary, container: Node2D) -> void:
	"""Create a single prop from definition"""
	var prop_type = prop_def.type
	var pos = prop_def.pos

	# Create RNG with stored offset for consistency
	var rng = RandomNumberGenerator.new()
	rng.seed = prop_def.rng_offset

	# If we have ChunkBasedPropSystem, delegate to its creation methods
	if chunk_prop_system:
		_create_prop_via_chunk_system(prop_def, container, rng)
	else:
		_create_prop_simple(prop_def, container, rng)

func _create_prop_via_chunk_system(prop_def: Dictionary, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Create prop using ChunkBasedPropSystem methods"""
	var prop_type = prop_def.type
	var pos = prop_def.pos
	var chunk_key = prop_def.chunk_key

	match prop_type:
		"tree":
			var tree_id = prop_def.tree_id
			# Determine tree type
			var roll = rng.randf()
			var tree_type: String
			if roll < 0.6:
				tree_type = "dead_tree"
			elif roll < 0.9:
				tree_type = "pine_tree"
			else:
				tree_type = "autumn_tree"
			chunk_prop_system.create_tree(pos, tree_type, container, rng, tree_id)
			streaming_manager.register_harvestable(tree_id, container.get_child(container.get_child_count() - 1) if container.get_child_count() > 0 else null)

		"rock_large":
			var rock_id = prop_def.rock_id
			chunk_prop_system.create_lootable_rock(pos, "large", container, rng, rock_id, chunk_key)
			streaming_manager.register_large_rock(pos)
			streaming_manager.register_harvestable(rock_id, container.get_child(container.get_child_count() - 1) if container.get_child_count() > 0 else null)

		"rock_medium":
			chunk_prop_system.create_rock_with_shadow(pos, "medium", container, rng, chunk_key)

		"rock_small":
			chunk_prop_system.create_rock_with_shadow(pos, "small", container, rng, chunk_key)

		"lava_pool", "monster_lava_pool":
			var is_monster = prop_type == "monster_lava_pool"
			_create_lava_pool(pos, container, rng, is_monster)
			streaming_manager.register_lava_pool(pos)

		"blister_pool":
			_create_blister_pool(pos, container, rng)

		"bone_cluster":
			_create_bone_cluster(pos, container, rng)

		"scattered_bone":
			_create_scattered_bone(pos, container, rng)

		"vegetation":
			chunk_prop_system.create_prop(pos, "ash_pile", container, rng)

		"crack":
			var crack_type = ["ground_crack_1", "ground_crack_2"][rng.randi() % 2]
			chunk_prop_system.create_prop(pos, crack_type, container, rng)

func _create_prop_simple(prop_def: Dictionary, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Simple fallback prop creation (no ChunkBasedPropSystem available)"""
	var pos = prop_def.pos

	# Create basic sprite placeholder
	var sprite = Sprite2D.new()
	sprite.global_position = pos
	sprite.z_index = -1
	sprite.modulate = Color(0.5, 0.5, 0.5, 0.5)  # Grey placeholder
	container.add_child(sprite)

func _create_lava_pool(pos: Vector2, container: Node2D, rng: RandomNumberGenerator, is_monster: bool) -> void:
	"""Create a lava pool using ChunkBasedPropSystem"""
	if not chunk_prop_system:
		return

	# Use chunk system's lava creation - size is pool radius
	if chunk_prop_system.has_method("create_lava_pool"):
		var size = rng.randf_range(100, 180) if is_monster else rng.randf_range(60, 120)
		chunk_prop_system.create_lava_pool(pos, container, rng, size)

func _create_blister_pool(pos: Vector2, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Create a small blister lava pool"""
	if not chunk_prop_system:
		return

	if chunk_prop_system.has_method("create_lava_pool"):
		var size = rng.randf_range(30, 50)
		chunk_prop_system.create_lava_pool(pos, container, rng, size)

func _create_bone_cluster(pos: Vector2, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Create a cluster of bones"""
	if not chunk_prop_system:
		return

	# Create multiple bone props in cluster
	for i in range(rng.randi_range(3, 6)):
		var offset = Vector2(
			rng.randf_range(-50, 50),
			rng.randf_range(-50, 50)
		)
		var bone_type = ["bones", "skull"][rng.randi() % 2]
		chunk_prop_system.create_prop(pos + offset, bone_type, container, rng, 0.6, 1.0)

func _create_scattered_bone(pos: Vector2, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Create a single scattered bone"""
	if not chunk_prop_system:
		return

	var bone_type = ["bones", "skull"][rng.randi() % 2]
	chunk_prop_system.create_prop(pos, bone_type, container, rng, 0.5, 0.8)
