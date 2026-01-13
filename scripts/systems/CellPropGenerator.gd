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
const TREES_PER_CELL: int = 3  # Base scattered trees per cell (not on treelines)

# Treeline system - dense lines of trees forming barriers
# 2 large treelines + 2 small treelines per chunk
const LARGE_TREELINES_PER_CHUNK: int = 2
const SMALL_TREELINES_PER_CHUNK: int = 2
const TREELINE_TREE_SPACING: float = 160.0  # Distance between trees along treeline (increased for interaction)
const TREELINE_WIDTH: float = 50.0  # Perpendicular jitter (not rows, just variation)
const TREELINE_ROWS: int = 2  # Number of parallel rows in treeline
const TREELINE_ROW_SPACING: float = 110.0  # Distance between rows (enough to click each tree)
const LARGE_TREELINE_MIN_LENGTH: float = 2500.0  # Much longer treelines
const LARGE_TREELINE_MAX_LENGTH: float = 5000.0  # Very long treelines
const SMALL_TREELINE_MIN_LENGTH: float = 1000.0  # Small ones are still decent size
const SMALL_TREELINE_MAX_LENGTH: float = 2000.0
const TREELINE_WAVINESS: float = 250.0  # More curve for longer lines

# Cache for treeline data (deterministic per chunk)
var _treeline_cache: Dictionary = {}  # chunk_key -> Array of treeline segments

# Tree position cache for collision checking
var _tree_positions_cache: Dictionary = {}  # chunk_key -> Array of Vector2
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
# Campfire is at west side of chunk -1 for West→East progression
var CAMPFIRE_POS: Vector2:
	get: return Vector2(-6000, 0)
const CAMPFIRE_SAFE_RADIUS = 1050.0
const PATH_WIDTH = 350.0  # Increased to account for zigzag path amplitude

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

func get_chunk_id_from_key(chunk_key: String) -> int:
	"""Extract chunk ID (X component) from chunk key"""
	var parts = chunk_key.split(",")
	return int(parts[0])

func get_treelines_for_chunk(chunk_key: String) -> Array:
	"""Get deterministic treeline segments for a chunk (2 large + 2 small)"""
	if _treeline_cache.has(chunk_key):
		return _treeline_cache[chunk_key]

	var treelines = []
	var chunk_id = get_chunk_id_from_key(chunk_key)

	# Create deterministic RNG for this chunk's treelines
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("treeline_" + chunk_key) + world_seed

	# Chunk bounds
	var chunk_start_x = chunk_id * CHUNK_SIZE
	var chunk_end_x = chunk_start_x + CHUNK_SIZE
	var chunk_half_height = CHUNK_SIZE / 2.0
	var margin = 600.0

	# Track existing treeline centers to avoid overlap
	var existing_centers = []

	# Generate large treelines first
	for i in range(LARGE_TREELINES_PER_CHUNK):
		var treeline = _generate_single_treeline(rng, chunk_start_x, chunk_end_x, chunk_half_height, margin, existing_centers, true)
		if treeline:
			treelines.append(treeline)
			existing_centers.append(treeline.center)

	# Then generate small treelines
	for i in range(SMALL_TREELINES_PER_CHUNK):
		var treeline = _generate_single_treeline(rng, chunk_start_x, chunk_end_x, chunk_half_height, margin, existing_centers, false)
		if treeline:
			treelines.append(treeline)
			existing_centers.append(treeline.center)

	_treeline_cache[chunk_key] = treelines
	return treelines

func _generate_single_treeline(rng: RandomNumberGenerator, chunk_start_x: float, chunk_end_x: float, chunk_half_height: float, margin: float, existing_centers: Array, is_large: bool) -> Dictionary:
	"""Generate a single treeline, avoiding existing ones"""
	var min_length = LARGE_TREELINE_MIN_LENGTH if is_large else SMALL_TREELINE_MIN_LENGTH
	var max_length = LARGE_TREELINE_MAX_LENGTH if is_large else SMALL_TREELINE_MAX_LENGTH
	var min_separation = 1500.0 if is_large else 800.0

	# Try a few times to find a good position
	for attempt in range(5):
		var start = Vector2(
			rng.randf_range(chunk_start_x + margin, chunk_end_x - margin),
			rng.randf_range(-chunk_half_height + margin, chunk_half_height - margin)
		)

		# Skip if too close to campfire
		if start.distance_to(CAMPFIRE_POS) < CAMPFIRE_SAFE_RADIUS + 300:
			continue

		# Skip if too close to existing treelines
		var too_close = false
		for center in existing_centers:
			if start.distance_to(center) < min_separation:
				too_close = true
				break
		if too_close:
			continue

		# Random angle (prefer horizontal/diagonal lines)
		var angle = rng.randf_range(-PI/4, PI/4)  # -45 to +45 degrees
		if rng.randf() > 0.5:
			angle += PI  # Some lines go the other way

		# Random length
		var length = rng.randf_range(min_length, max_length)

		# Generate wavy line points
		var points = []
		var segments = int(length / 250.0)  # Control point every ~250px
		segments = max(segments, 2)
		var dir = Vector2.from_angle(angle)
		var perp = dir.rotated(PI/2)

		for j in range(segments + 1):
			var t = float(j) / segments
			var base_pos = start + dir * (t * length)
			# Add waviness with variation
			var wave_freq = 1.5 + rng.randf() * 0.5
			var wave_offset = sin(t * PI * wave_freq) * TREELINE_WAVINESS * rng.randf_range(0.3, 1.0)
			var point = base_pos + perp * wave_offset
			points.append(point)

		if points.size() >= 2:
			var center = start + dir * (length / 2)
			return {
				"points": points,
				"start": start,
				"end": points[points.size() - 1],
				"length": length,
				"center": center,
				"is_large": is_large
			}

	return {}

func get_trees_on_treeline(treeline: Dictionary, treeline_index: int, chunk_key: String) -> Array:
	"""Generate deterministic tree positions along a treeline with multiple rows"""
	var trees = []
	var points = treeline.points

	if points.size() < 2:
		return trees

	# Use deterministic RNG seeded by treeline identity (not cell)
	var tree_rng = RandomNumberGenerator.new()
	tree_rng.seed = hash("treeline_trees_%s_%d" % [chunk_key, treeline_index]) + world_seed

	var is_large = treeline.get("is_large", true)
	var num_rows = TREELINE_ROWS if is_large else 2  # Large treelines get 3 rows, small get 2
	var tree_id = 0

	# Walk along the treeline and place trees at regular intervals
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i + 1]
		var segment_length = p1.distance_to(p2)
		var segment_dir = (p2 - p1).normalized()
		var perp = segment_dir.rotated(PI/2)

		var pos_along = 0.0
		while pos_along < segment_length:
			var base_pos = p1 + segment_dir * pos_along

			# Density variation - sometimes skip trees (creates gaps)
			var density_roll = tree_rng.randf()
			var skip_chance = 0.15  # 15% chance to skip a column
			if density_roll < skip_chance:
				pos_along += TREELINE_TREE_SPACING
				continue

			# Place multiple rows of trees perpendicular to the line
			for row in range(num_rows):
				# Calculate row offset from center line
				var row_offset = (row - (num_rows - 1) / 2.0) * TREELINE_ROW_SPACING

				# Add some randomness to row position
				row_offset += tree_rng.randf_range(-20, 20)

				var tree_pos = base_pos + perp * row_offset

				# Add jitter along the line direction too
				tree_pos += segment_dir * tree_rng.randf_range(-25, 25)

				# Small additional random jitter
				tree_pos.x += tree_rng.randf_range(-10, 10)
				tree_pos.y += tree_rng.randf_range(-10, 10)

				# Sometimes skip individual trees in a row for variation
				if tree_rng.randf() < 0.1:  # 10% skip
					continue

				trees.append({
					"pos": tree_pos,
					"treeline_id": treeline_index,
					"tree_idx": tree_id
				})
				tree_id += 1

			# Vary spacing along the line
			pos_along += TREELINE_TREE_SPACING + tree_rng.randf_range(-15, 25)

	return trees

func get_nearest_treeline_distance(pos: Vector2, chunk_key: String) -> float:
	"""Get distance to nearest treeline"""
	var treelines = get_treelines_for_chunk(chunk_key)
	var min_dist = INF

	for treeline in treelines:
		var points = treeline.points
		for i in range(points.size() - 1):
			var dist = _point_to_segment_distance(pos, points[i], points[i + 1])
			min_dist = min(min_dist, dist)

	return min_dist

func _point_to_segment_distance(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	"""Calculate distance from point to line segment"""
	var seg = seg_end - seg_start
	var seg_len_sq = seg.length_squared()

	if seg_len_sq < 0.001:
		return point.distance_to(seg_start)

	var t = clamp((point - seg_start).dot(seg) / seg_len_sq, 0.0, 1.0)
	var projection = seg_start + t * seg
	return point.distance_to(projection)

func generate_prop_list(cell_key: String) -> Array:
	"""Generate deterministic prop list for a cell"""
	var props = []
	var rng = get_cell_rng(cell_key)
	var bounds = get_cell_bounds(cell_key)
	var chunk_key = get_chunk_key_for_cell(cell_key)
	var chunk_id = get_chunk_id_from_key(chunk_key)

	# Generate props with positions
	# Order: Lava first (exclusion zones), then trees, rocks, decorative

	# Skip random lava pools in chunk -1 (tutorial area has hardcoded POI lava lakes)
	var skip_random_lava = (chunk_id == -1)

	# Monster lava pools (very rare, anchor points) - skip in tutorial chunk
	if not skip_random_lava and rng.randf() < MONSTER_LAVA_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos):
			props.append({
				"type": "monster_lava_pool",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Regular lava pools - skip in tutorial chunk
	if not skip_random_lava and rng.randf() < LAVA_POOL_CHANCE:
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

	# Trees (lootable) - treeline system creates dense barriers
	var treelines = get_treelines_for_chunk(chunk_key)
	var tree_index = 0
	var tree_positions_in_cell = []  # Track tree positions to avoid rock overlap

	# Add trees from treelines that pass through or near this cell
	for tl_idx in range(treelines.size()):
		var treeline = treelines[tl_idx]

		# Get all tree positions on this treeline (deterministic based on treeline, not cell)
		var treeline_trees = get_trees_on_treeline(treeline, tl_idx, chunk_key)

		for tree_data in treeline_trees:
			var tree_pos = tree_data.pos

			# Only add trees that are within this cell's bounds
			if bounds.has_point(tree_pos):
				# Use globally unique tree_id based on treeline + tree index
				var tree_id = "%s:tl%d:t%d" % [chunk_key, tl_idx, tree_data.tree_idx]

				if _is_valid_position(tree_pos) and not streaming_manager.is_harvested(tree_id):
					props.append({
						"type": "tree",
						"pos": tree_pos,
						"cell_key": cell_key,
						"chunk_key": chunk_key,
						"index": tree_index,
						"tree_id": tree_id,
						"rng_offset": rng.randi()
					})
					tree_positions_in_cell.append(tree_pos)
					tree_index += 1

	# Add a few scattered trees outside of treelines
	for i in range(TREES_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		var tree_id = "%s:scatter:%d" % [cell_key, i]

		# Only add if not too close to a treeline (don't duplicate)
		var dist_to_treeline = get_nearest_treeline_distance(pos, chunk_key)
		if dist_to_treeline > 150 and _is_valid_position(pos) and not streaming_manager.is_harvested(tree_id):
			props.append({
				"type": "tree",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"index": tree_index + i,
				"tree_id": tree_id,
				"rng_offset": rng.randi()
			})
			tree_positions_in_cell.append(pos)

	# Large rocks (lootable) - check against tree positions
	for i in range(ROCKS_LARGE_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		var rock_id = "%s:rock_large:%d" % [cell_key, i]
		if _is_valid_position(pos) and not streaming_manager.is_harvested(rock_id) and not _is_too_close_to_trees(pos, tree_positions_in_cell, 120.0):
			props.append({
				"type": "rock_large",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"index": i,
				"rock_id": rock_id,
				"rng_offset": rng.randi()
			})

	# Medium rocks (decorative - allowed on path) - check against trees
	for i in range(ROCKS_MEDIUM_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true) and not _is_too_close_to_trees(pos, tree_positions_in_cell, 80.0):
			props.append({
				"type": "rock_medium",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Small rocks (decorative - allowed on path) - check against trees
	for i in range(ROCKS_SMALL_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true) and not _is_too_close_to_trees(pos, tree_positions_in_cell, 50.0):
			props.append({
				"type": "rock_small",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Bone clusters (rare - allowed on path)
	if rng.randf() < BONE_CLUSTER_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true):
			props.append({
				"type": "bone_cluster",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Scattered bones (allowed on path)
	for i in range(SCATTERED_BONES_PER_CELL):
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true):
			props.append({
				"type": "scattered_bone",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Vegetation (rare - allowed on path)
	if rng.randf() < VEGETATION_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true):
			props.append({
				"type": "vegetation",
				"pos": pos,
				"cell_key": cell_key,
				"chunk_key": chunk_key,
				"rng_offset": rng.randi()
			})

	# Ground cracks (rare - allowed on path)
	if rng.randf() < CRACK_CHANCE:
		var pos = _random_position_in_bounds(bounds, rng)
		if _is_valid_position(pos, true):
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

func _is_valid_position(pos: Vector2, allow_on_path: bool = false) -> bool:
	"""Check if position is valid for prop placement"""
	# Check campfire safe zone
	if pos.distance_to(CAMPFIRE_POS) < CAMPFIRE_SAFE_RADIUS:
		return false

	# Check if on main path (only for large props)
	if not allow_on_path and _is_on_path(pos):
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

func _is_too_close_to_trees(pos: Vector2, tree_positions: Array, min_distance: float) -> bool:
	"""Check if position is too close to any tree position"""
	for tree_pos in tree_positions:
		if pos.distance_to(tree_pos) < min_distance:
			return true
	return false

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
			# Zone-based tree selection
			var zone = chunk_prop_system.get_zone_for_chunk(chunk_key)

			if zone == "zone1":
				# Zone 1: Only dead trees with new LPC variants
				var all_dead_textures = chunk_prop_system.DEAD_TREE_TEXTURES.large + chunk_prop_system.DEAD_TREE_TEXTURES.medium + chunk_prop_system.DEAD_TREE_TEXTURES.small
				var texture_path = all_dead_textures[rng.randi() % all_dead_textures.size()]
				var tree_scale_range = Vector2(1.35, 2.1)  # Trees tower over player (25% smaller than before)
				chunk_prop_system.create_grove_tree(pos, texture_path, tree_scale_range, container, rng, tree_id)
			else:
				# Zone 2+: Mix of tree types (60% dead, 30% pine, 10% autumn)
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
