extends Node
class_name CellStreamingManager

## Cell-Based Streaming System
## Replaces chunk-boundary loading with distance-based cell streaming
## Props load/unload gradually as player moves, eliminating hard chunk transitions

# Cell data structure
class CellData:
	var cell_key: String
	var props_container: Node2D
	var props_list: Array = []  # Pre-computed prop definitions for this cell
	var props_generated: int = 0
	var is_fully_loaded: bool = false
	var world_pos: Vector2  # Center position of this cell

	func _init(key: String, center: Vector2):
		cell_key = key
		world_pos = center

# Constants from singleton
var CELL_SIZE: float:
	get: return Constants.CELL_SIZE
var LOAD_RADIUS: float:
	get: return Constants.CELL_LOAD_RADIUS
var UNLOAD_RADIUS: float:
	get: return Constants.CELL_UNLOAD_RADIUS
var CACHE_TIME: float:
	get: return Constants.CELL_CACHE_TIME
var MAX_LOADS_PER_FRAME: int:
	get: return Constants.CELL_MAX_LOADS_PER_FRAME
var MAX_UNLOADS_PER_FRAME: int:
	get: return Constants.CELL_MAX_UNLOADS_PER_FRAME

# Cell state tracking
var loaded_cells: Dictionary = {}      # cell_key -> CellData
var cached_cells: Dictionary = {}      # cell_key -> {data: CellData, unload_time: float}
var loading_cells: Dictionary = {}     # cell_key -> CellData (being loaded)
var loading_queue: Array = []          # [cell_key, ...] sorted by distance (closest first)
var unloading_queue: Array = []        # [cell_key, ...] sorted by distance (farthest first)

# References
var game_world: Node = null
var prop_generator: Node = null  # CellPropGenerator instance
var props_parent: Node2D = null  # Parent node for all cell containers

# Player tracking
var player: Node = null
var last_player_cell: String = ""

# Exclusion zones (shared across cells for consistency)
var global_lava_positions: Array = []  # All lava pool centers
var global_large_rock_positions: Array = []  # All large rock positions

# World seed for deterministic generation
var world_seed: int = 12345

# Debug stats
var cells_loaded_this_session: int = 0
var props_generated_this_session: int = 0

signal cell_loaded(cell_key: String)
signal cell_unloaded(cell_key: String)

func _ready() -> void:
	print("🔲 CellStreamingManager initialized")

func initialize(p_game_world: Node, p_world_seed: int = 12345) -> void:
	"""Initialize the cell streaming system"""
	game_world = p_game_world
	world_seed = p_world_seed

	# Create parent node for all cell containers
	props_parent = Node2D.new()
	props_parent.name = "CellProps"
	game_world.add_child(props_parent)

	# Create prop generator
	prop_generator = CellPropGenerator.new()
	prop_generator.initialize(self, world_seed)
	add_child(prop_generator)

	print("🔲 CellStreamingManager ready (seed: %d, cell size: %d)" % [world_seed, int(CELL_SIZE)])

func set_chunk_prop_system(p_chunk_prop_system: ChunkBasedPropSystem) -> void:
	"""Set reference to ChunkBasedPropSystem for prop creation"""
	if prop_generator:
		prop_generator.set_chunk_prop_system(p_chunk_prop_system)

func _process(delta: float) -> void:
	if not game_world:
		return

	# Find player if not set
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if not player:
			return

	# Update cell streaming
	_update_cell_visibility()
	_process_loading_queue()
	_process_unloading_queue()
	_cleanup_cache(delta)

# ═══════════════════════════════════════════════════════════════════════════
# CELL KEY UTILITIES
# ═══════════════════════════════════════════════════════════════════════════

func get_cell_key(world_pos: Vector2) -> String:
	"""Get cell key for a world position"""
	var cell_x = floori(world_pos.x / CELL_SIZE)
	var cell_y = floori(world_pos.y / CELL_SIZE)
	return "%d,%d" % [cell_x, cell_y]

func get_cell_center(cell_key: String) -> Vector2:
	"""Get world center position of a cell"""
	var parts = cell_key.split(",")
	var cell_x = int(parts[0])
	var cell_y = int(parts[1])
	return Vector2(
		cell_x * CELL_SIZE + CELL_SIZE / 2,
		cell_y * CELL_SIZE + CELL_SIZE / 2
	)

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

func get_cells_in_radius(center: Vector2, radius: float) -> Array:
	"""Get all cell keys within radius of a point"""
	var cells = []
	var cell_radius = ceili(radius / CELL_SIZE) + 1
	var center_cell_x = floori(center.x / CELL_SIZE)
	var center_cell_y = floori(center.y / CELL_SIZE)

	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var cell_x = center_cell_x + dx
			var cell_y = center_cell_y + dy
			var cell_center = Vector2(
				cell_x * CELL_SIZE + CELL_SIZE / 2,
				cell_y * CELL_SIZE + CELL_SIZE / 2
			)

			# Check if cell center is within radius
			if center.distance_to(cell_center) <= radius + CELL_SIZE * 0.7:  # Slight buffer
				cells.append("%d,%d" % [cell_x, cell_y])

	return cells

# ═══════════════════════════════════════════════════════════════════════════
# CELL VISIBILITY & LOADING
# ═══════════════════════════════════════════════════════════════════════════

func _update_cell_visibility() -> void:
	"""Update which cells should be loaded/unloaded based on player position"""
	var player_pos = player.global_position
	var current_cell = get_cell_key(player_pos)

	# Get cells that should be loaded
	var cells_to_load = get_cells_in_radius(player_pos, LOAD_RADIUS)

	# Queue cells for loading (not already loaded or loading)
	for cell_key in cells_to_load:
		if not loaded_cells.has(cell_key) and not loading_cells.has(cell_key):
			# Check cache first
			if cached_cells.has(cell_key):
				_restore_from_cache(cell_key)
			elif cell_key not in loading_queue:
				loading_queue.append(cell_key)

	# Sort loading queue by distance (closest first)
	loading_queue.sort_custom(func(a, b):
		var dist_a = player_pos.distance_to(get_cell_center(a))
		var dist_b = player_pos.distance_to(get_cell_center(b))
		return dist_a < dist_b
	)

	# Find cells to unload (beyond unload radius)
	for cell_key in loaded_cells.keys():
		var cell_center = get_cell_center(cell_key)
		var distance = player_pos.distance_to(cell_center)
		if distance > UNLOAD_RADIUS:
			if cell_key not in unloading_queue:
				unloading_queue.append(cell_key)

	# Sort unloading queue by distance (farthest first)
	unloading_queue.sort_custom(func(a, b):
		var dist_a = player_pos.distance_to(get_cell_center(a))
		var dist_b = player_pos.distance_to(get_cell_center(b))
		return dist_a > dist_b
	)

	# Track cell changes for debug
	if current_cell != last_player_cell:
		last_player_cell = current_cell
		if OS.is_debug_build():
			print("🔲 Player entered cell %s (loaded: %d, loading: %d, cached: %d)" % [
				current_cell, loaded_cells.size(), loading_cells.size(), cached_cells.size()
			])

func _process_loading_queue() -> void:
	"""Process cells waiting to be loaded"""
	var loaded_this_frame = 0

	# First, continue loading cells that are in progress
	for cell_key in loading_cells.keys():
		var cell_data = loading_cells[cell_key]
		var props_to_load = mini(MAX_LOADS_PER_FRAME - loaded_this_frame, cell_data.props_list.size() - cell_data.props_generated)

		if props_to_load > 0:
			_generate_props_for_cell(cell_data, props_to_load)
			loaded_this_frame += props_to_load

		# Check if cell is fully loaded
		if cell_data.props_generated >= cell_data.props_list.size():
			cell_data.is_fully_loaded = true
			loaded_cells[cell_key] = cell_data
			loading_cells.erase(cell_key)
			cells_loaded_this_session += 1
			emit_signal("cell_loaded", cell_key)

			if OS.is_debug_build():
				print("✅ Cell %s loaded (%d props)" % [cell_key, cell_data.props_generated])

		if loaded_this_frame >= MAX_LOADS_PER_FRAME:
			return

	# Start loading new cells from queue
	while loading_queue.size() > 0 and loaded_this_frame < MAX_LOADS_PER_FRAME:
		var cell_key = loading_queue.pop_front()

		# Skip if already loaded or loading
		if loaded_cells.has(cell_key) or loading_cells.has(cell_key):
			continue

		# Start loading this cell
		_start_cell_load(cell_key)
		loaded_this_frame += 1

func _start_cell_load(cell_key: String) -> void:
	"""Begin loading a cell"""
	var cell_center = get_cell_center(cell_key)
	var cell_data = CellData.new(cell_key, cell_center)

	# Create container for this cell's props
	cell_data.props_container = Node2D.new()
	cell_data.props_container.name = "Cell_" + cell_key
	props_parent.add_child(cell_data.props_container)

	# Generate prop list for this cell (deterministic based on cell key)
	cell_data.props_list = prop_generator.generate_prop_list(cell_key)

	# Add to loading cells
	loading_cells[cell_key] = cell_data

func _generate_props_for_cell(cell_data: CellData, count: int) -> void:
	"""Generate a batch of props for a cell"""
	var start_idx = cell_data.props_generated
	var end_idx = mini(start_idx + count, cell_data.props_list.size())

	for i in range(start_idx, end_idx):
		var prop_def = cell_data.props_list[i]
		prop_generator.create_prop(prop_def, cell_data.props_container)
		props_generated_this_session += 1

	cell_data.props_generated = end_idx

func _process_unloading_queue() -> void:
	"""Process cells waiting to be unloaded"""
	var unloaded_this_frame = 0

	while unloading_queue.size() > 0 and unloaded_this_frame < MAX_UNLOADS_PER_FRAME:
		var cell_key = unloading_queue.pop_front()

		# Skip if not actually loaded
		if not loaded_cells.has(cell_key):
			continue

		# Double-check distance (player may have moved back)
		if player and is_instance_valid(player):
			var distance = player.global_position.distance_to(get_cell_center(cell_key))
			if distance <= UNLOAD_RADIUS:
				continue

		_unload_cell(cell_key)
		unloaded_this_frame += 1

func _unload_cell(cell_key: String) -> void:
	"""Unload a cell and move to cache"""
	if not loaded_cells.has(cell_key):
		return

	var cell_data = loaded_cells[cell_key]

	# Hide container but keep in memory (cache)
	if is_instance_valid(cell_data.props_container):
		cell_data.props_container.visible = false

	# Move to cache
	cached_cells[cell_key] = {
		"data": cell_data,
		"unload_time": Time.get_unix_time_from_system()
	}

	loaded_cells.erase(cell_key)
	emit_signal("cell_unloaded", cell_key)

	if OS.is_debug_build():
		print("📦 Cell %s cached (loaded: %d, cached: %d)" % [cell_key, loaded_cells.size(), cached_cells.size()])

func _restore_from_cache(cell_key: String) -> void:
	"""Restore a cell from cache"""
	if not cached_cells.has(cell_key):
		return

	var cache_entry = cached_cells[cell_key]
	var cell_data = cache_entry.data

	# Show container again
	if is_instance_valid(cell_data.props_container):
		cell_data.props_container.visible = true

	# Move back to loaded
	loaded_cells[cell_key] = cell_data
	cached_cells.erase(cell_key)

	# Remove from loading queue if present
	var queue_idx = loading_queue.find(cell_key)
	if queue_idx >= 0:
		loading_queue.remove_at(queue_idx)

	emit_signal("cell_loaded", cell_key)

	if OS.is_debug_build():
		print("♻️ Cell %s restored from cache" % cell_key)

func _cleanup_cache(delta: float) -> void:
	"""Remove cells from cache that have been unloaded too long"""
	var current_time = Time.get_unix_time_from_system()
	var cells_to_remove = []

	for cell_key in cached_cells.keys():
		var cache_entry = cached_cells[cell_key]
		var age = current_time - cache_entry.unload_time

		if age > CACHE_TIME:
			cells_to_remove.append(cell_key)

	for cell_key in cells_to_remove:
		var cache_entry = cached_cells[cell_key]
		var cell_data = cache_entry.data

		# Actually free the nodes
		if is_instance_valid(cell_data.props_container):
			cell_data.props_container.queue_free()

		cached_cells.erase(cell_key)

		if OS.is_debug_build():
			print("🗑️ Cell %s expired from cache" % cell_key)

# ═══════════════════════════════════════════════════════════════════════════
# EXCLUSION ZONES (for cross-cell collision avoidance)
# ═══════════════════════════════════════════════════════════════════════════

func register_lava_pool(pos: Vector2) -> void:
	"""Register a lava pool position for exclusion checking"""
	global_lava_positions.append(pos)

func register_large_rock(pos: Vector2) -> void:
	"""Register a large rock position for exclusion checking"""
	global_large_rock_positions.append(pos)

func is_position_in_exclusion_zone(pos: Vector2, lava_radius: float = 300.0, rock_radius: float = 150.0) -> bool:
	"""Check if a position is too close to lava pools or large rocks"""
	for lava_pos in global_lava_positions:
		if pos.distance_to(lava_pos) < lava_radius:
			return true

	for rock_pos in global_large_rock_positions:
		if pos.distance_to(rock_pos) < rock_radius:
			return true

	return false

# ═══════════════════════════════════════════════════════════════════════════
# HARVESTABLE TRACKING (for network sync)
# ═══════════════════════════════════════════════════════════════════════════

var harvestables_by_id: Dictionary = {}  # {id: Node}
var harvested_items: Dictionary = {}  # {unique_id: true}

func register_harvestable(id: String, node: Node) -> void:
	"""Register a harvestable (tree/rock) for network sync"""
	harvestables_by_id[id] = node

func mark_harvested(id: String) -> void:
	"""Mark an item as harvested (won't respawn)"""
	harvested_items[id] = true

func is_harvested(id: String) -> bool:
	"""Check if an item has been harvested"""
	return harvested_items.has(id)

# ═══════════════════════════════════════════════════════════════════════════
# DEBUG & STATS
# ═══════════════════════════════════════════════════════════════════════════

func get_debug_info() -> Dictionary:
	"""Get debug information about cell streaming state"""
	return {
		"loaded_cells": loaded_cells.size(),
		"loading_cells": loading_cells.size(),
		"cached_cells": cached_cells.size(),
		"loading_queue": loading_queue.size(),
		"unloading_queue": unloading_queue.size(),
		"total_props": props_generated_this_session,
		"total_cells_loaded": cells_loaded_this_session,
		"player_cell": last_player_cell
	}

func get_prop_stats() -> Dictionary:
	"""Get detailed prop statistics for debug display (matches ChunkBasedPropSystem format)"""
	var stats = {
		"trees": 0,
		"tree_nodes": 0,
		"rocks_large": 0,
		"rocks_medium": 0,
		"rocks_small": 0,
		"rock_nodes": 0,
		"lava_pools": 0,
		"bones": 0,
		"other": 0,
		"total_props": 0,
		"total_nodes": 0,
		"cells_loaded": loaded_cells.size(),
		"cells_cached": cached_cells.size()
	}

	# Count props in all loaded cells
	for cell_key in loaded_cells.keys():
		var cell_data = loaded_cells[cell_key]
		if not cell_data or not is_instance_valid(cell_data.props_container):
			continue

		for child in cell_data.props_container.get_children():
			var child_name = child.name
			var child_nodes = _count_nodes_recursive(child)
			stats.total_nodes += child_nodes
			stats.total_props += 1

			if child_name.begins_with("Tree_"):
				stats.trees += 1
				stats.tree_nodes += child_nodes
			elif child_name.begins_with("Rock_"):
				stats.rock_nodes += child_nodes
				if "large" in child_name.to_lower():
					stats.rocks_large += 1
				elif "medium" in child_name.to_lower():
					stats.rocks_medium += 1
				else:
					stats.rocks_small += 1
			elif child_name.begins_with("Lava") or child_name.begins_with("Monster"):
				stats.lava_pools += 1
			elif child_name.begins_with("Bone") or child_name.begins_with("Skull"):
				stats.bones += 1
			else:
				stats.other += 1

	return stats

func _count_nodes_recursive(node: Node) -> int:
	"""Count total nodes in a subtree"""
	var count = 1
	for child in node.get_children():
		count += _count_nodes_recursive(child)
	return count
