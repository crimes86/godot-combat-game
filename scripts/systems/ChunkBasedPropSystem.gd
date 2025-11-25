extends Node
class_name ChunkBasedPropSystem

## Chunk-Based Procedural Prop Generation (3 Square Chunks)
## World is divided into 3 square chunks (8000x8000px each)
## Chunk -1 (West), Chunk 0 (Origin/Spawn), Chunk +1 (East)
## Smart loading: current chunk always, neighbors when within 1000px of edges

# Use Constants singleton for chunk size (single source of truth)
var CHUNK_SIZE: float:
	get: return Constants.CHUNK_SIZE

const LOAD_DISTANCE: float = 10000.0  # Load chunks within this distance (doubled)
const UNLOAD_DISTANCE: float = 12000.0  # Unload chunks beyond this distance (doubled)

# Prop density per chunk (8000x8000 = 64M px², 3x density of original 4000x4000)
# Targeting ~600 props per chunk (3x previous count for better performance)
const TREES_PER_CHUNK: int = 210  # Dead trees (lootable - wood)
const ROCKS_LARGE_PER_CHUNK: int = 48  # Large rocks (lootable - stone/ore)
const ROCKS_MEDIUM_PER_CHUNK: int = 75  # Medium rocks (decorative)
const ROCKS_SMALL_PER_CHUNK: int = 60  # Small rocks (decorative)
const MONSTER_LAVA_POOLS_PER_CHUNK: int = 6  # Giant lava pools (anchor points)
const LAVA_POOLS_PER_CHUNK: int = 24  # Regular lava pools (some cluster around monsters)
const BONE_CLUSTERS_PER_CHUNK: int = 9  # Large skeletal remains (decorative)
const DEAD_VEGETATION_PER_CHUNK: int = 24  # Dead bushes/ash piles (decorative)
const CRACKS_PER_CHUNK: int = 30  # Ground cracks (visual)

# World boundaries - 3 chunks: -8000 to 16000 X, -4000 to 4000 Y
var WORLD_MIN: Vector2:
	get: return Vector2(-Constants.CHUNK_SIZE, -Constants.CHUNK_SIZE / 2)
var WORLD_MAX: Vector2:
	get: return Vector2(Constants.CHUNK_SIZE * 2, Constants.CHUNK_SIZE / 2)

# Chunk storage
var loaded_chunks: Dictionary = {}  # {chunk_key: ChunkData}
var player: Node = null
var game_world: Node = null

# Harvested items tracking (so they don't respawn)
var harvested_items: Dictionary = {}  # {unique_id: true} where unique_id = "chunk_key:prop_type:index"

# Prop textures (from game_world.gd)
const PROP_TEXTURES = {
	"dead_tree_1": "res://assets/environment/wasteland/dead_tree_1.png",
	"dead_tree_2": "res://assets/environment/wasteland/dead_tree_2.png",
	"dead_tree_3": "res://assets/environment/wasteland/dead_tree_3.png",
	"dead_tree_4": "res://assets/environment/wasteland/dead_tree_4.png",
	"dead_tree_5": "res://assets/environment/wasteland/dead_tree_5.png",
	"dead_tree_6": "res://assets/environment/wasteland/dead_tree_6.png",
	"dead_tree_7": "res://assets/environment/wasteland/dead_tree_7.png",
	"dead_tree_8": "res://assets/environment/wasteland/dead_tree_8.png",
	"dead_tree_9": "res://assets/environment/wasteland/dead_tree_9.png",
	"dead_tree_10": "res://assets/environment/wasteland/dead_tree_10.png",
	"rock_large": "res://assets/environment/wasteland/rock_large.png",
	"rock_medium": "res://assets/environment/wasteland/rock_medium.png",
	"rock_small": "res://assets/environment/wasteland/rock_small.png",
	"ash_pile": "res://assets/environment/wasteland/ash_pile.png",
	"bones": "res://assets/environment/wasteland/bones.png",
	"skull": "res://assets/environment/wasteland/skull.png",
	"ground_crack_1": "res://assets/environment/wasteland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/wasteland/ground_crack_2.png",
}

const TREE_TYPES = ["dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", "dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10"]

# Path checking - main path runs along Y=0 with zigzag, branch paths go to ruins
const PATH_WIDTH: float = 250.0  # Width to avoid for lava pools
# Campfire position - center of chunk 0
var CAMPFIRE_POS: Vector2:
	get: return Vector2(Constants.CHUNK_SIZE / 2, 0)

class ChunkData:
	var chunk_key: String
	var props_container: Node2D  # Container for all props in this chunk
	var is_loaded: bool = false
	var monster_lava_positions: Array[Dictionary] = []  # [{pos: Vector2, radius: float}] for monster pools
	var lava_pool_positions: Array[Dictionary] = []  # [{pos: Vector2, radius: float}] for exclusion
	var large_rock_positions: Array[Dictionary] = []  # [{pos: Vector2, radius: float}] for rock overlap prevention

func _ready() -> void:
	print("🗺️ ChunkBasedPropSystem initialized - 3 square chunks (%.0fx%.0fpx each)" % [CHUNK_SIZE, CHUNK_SIZE])

	# Create debug label (hidden by default)
	create_debug_label()

	# Connect to DebugConfig F3 toggle
	if DebugConfig:
		DebugConfig.debug_display_toggled.connect(_on_debug_toggled)

func initialize(world: Node) -> void:
	game_world = world
	player = get_tree().get_first_node_in_group("player")

func create_debug_label() -> void:
	"""Create a debug label to show chunk info"""
	debug_label = Label.new()
	debug_label.name = "ChunkDebugLabel"

	# Styling
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_color", Color.YELLOW)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 3)

	# Right-aligned positioning (anchored to top-right)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	debug_label.position = Vector2(10, 10)  # Will be adjusted in _process to stay right

	# Add to canvas layer so it's always visible
	debug_canvas = CanvasLayer.new()
	debug_canvas.name = "ChunkDebugCanvas"
	debug_canvas.layer = 100
	debug_canvas.visible = false  # Hidden by default, toggle with F3
	add_child(debug_canvas)
	debug_canvas.add_child(debug_label)

func _on_debug_toggled(is_visible: bool) -> void:
	"""Called when F3 debug display is toggled"""
	# Disabled - now integrated into main PerformanceProfiler F3 display
	# if debug_canvas:
	# 	debug_canvas.visible = is_visible
	pass

var chunk_update_timer: float = 0.0
const CHUNK_UPDATE_INTERVAL: float = 0.5  # Check chunks every 0.5s for responsive loading/unloading
# No preload distance needed - we always keep current + left + right loaded

var current_player_chunk: String = ""  # Track which chunk player is currently in
var chunks_being_loaded: Dictionary = {}  # {chunk_key: props_remaining} for async loading

# Debug display
var debug_label: Label = null
var debug_canvas: CanvasLayer = null

# LOD system for props
var lod_update_timer: float = 0.0
const LOD_UPDATE_INTERVAL: float = 1.0  # Update LOD every 1 second
const LOD_SHADOW_DISTANCE: float = 1500.0  # Hide shadows beyond this distance
const LOD_DETAIL_DISTANCE: float = 2500.0  # Simplify props beyond this distance

func _process(delta: float) -> void:
	# In multiplayer server mode, we need to track all players
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Server tracks all players for chunk loading
		process_multiplayer_chunks(delta)
		return

	# Single player or client mode - track local player only
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return

	# Continue async chunk loading if in progress
	process_async_chunk_loading()

	# Update debug display (only if visible)
	if debug_canvas and debug_canvas.visible and debug_label:
		update_debug_display()

	# Only update chunks occasionally (chunks are massive MMO zones)
	chunk_update_timer += delta
	if chunk_update_timer >= CHUNK_UPDATE_INTERVAL:
		chunk_update_timer = 0.0
		update_chunks()

	# Update prop LOD (hide shadows/details on distant props)
	lod_update_timer += delta
	if lod_update_timer >= LOD_UPDATE_INTERVAL:
		lod_update_timer = 0.0
		update_prop_lod()

func process_multiplayer_chunks(delta: float) -> void:
	"""Process chunks for all players in multiplayer mode (server only)"""
	# Continue async chunk loading if in progress
	process_async_chunk_loading()

	# Only update chunks occasionally
	chunk_update_timer += delta
	if chunk_update_timer >= CHUNK_UPDATE_INTERVAL:
		chunk_update_timer = 0.0
		update_chunks_for_all_players()

func update_chunks_for_all_players() -> void:
	"""Update chunks based on all player positions (server only)"""
	var all_players = get_tree().get_nodes_in_group("player")
	if all_players.is_empty():
		return

	var all_chunks_to_load = {}  # Use dict to avoid duplicates

	# Collect chunks needed by all players
	for player_node in all_players:
		if not is_instance_valid(player_node):
			continue

		var player_pos = player_node.global_position
		var player_chunk = get_chunk_key(player_pos)

		# Always load player's current chunk
		all_chunks_to_load[player_chunk] = true

		# Parse chunk coordinates
		var chunk_parts = player_chunk.split(",")
		var chunk_x = int(chunk_parts[0])

		# Calculate position within chunk
		var chunk_origin_x = chunk_x * CHUNK_SIZE
		var pos_in_chunk_x = player_pos.x - chunk_origin_x

		# Define edge threshold (must match single player logic)
		const EDGE_THRESHOLD = 1000.0

		var dist_to_left_edge = pos_in_chunk_x
		var dist_to_right_edge = CHUNK_SIZE - pos_in_chunk_x

		# Load adjacent chunks if player is near edges
		if dist_to_left_edge < EDGE_THRESHOLD:
			var left_chunk_key = "%d,0" % (chunk_x - 1)
			var left_chunk_center = get_chunk_center(left_chunk_key)
			if is_in_world_bounds(left_chunk_center):
				all_chunks_to_load[left_chunk_key] = true

		if dist_to_right_edge < EDGE_THRESHOLD:
			var right_chunk_key = "%d,0" % (chunk_x + 1)
			var right_chunk_center = get_chunk_center(right_chunk_key)
			if is_in_world_bounds(right_chunk_center):
				all_chunks_to_load[right_chunk_key] = true

	# Get list of chunks to load
	var chunks_to_load = all_chunks_to_load.keys()

	# Load new chunks
	for chunk_key in chunks_to_load:
		if not loaded_chunks.has(chunk_key) and not chunks_being_loaded.has(chunk_key):
			start_async_chunk_load(chunk_key, true)  # Priority load for multiplayer

	# Unload distant chunks
	var chunks_to_unload = []
	for loaded_chunk_key in loaded_chunks:
		if not chunks_to_load.has(loaded_chunk_key):
			chunks_to_unload.append(loaded_chunk_key)

	for chunk_key in chunks_to_unload:
		unload_chunk(chunk_key)

	# Debug output
	if chunks_to_load.size() > 0 or chunks_to_unload.size() > 0:
		print("🌐 Server chunk update - Active: %s, Loading: %d, Unloading: %d" % [
			chunks_to_load, chunks_to_load.size(), chunks_to_unload.size()
		])

func update_debug_display() -> void:
	"""Update the debug label with current chunk info"""
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var chunk_key = get_chunk_key(player_pos)

	# Calculate position within chunk (horizontal only)
	var chunk_parts = chunk_key.split(",")
	var chunk_x = int(chunk_parts[0])
	var chunk_origin_x = chunk_x * CHUNK_SIZE
	var pos_in_chunk_x = player_pos.x - chunk_origin_x

	# Calculate distance to left/right edges
	var dist_to_left_edge = pos_in_chunk_x
	var dist_to_right_edge = CHUNK_SIZE - pos_in_chunk_x
	var dist_to_edge = min(dist_to_left_edge, dist_to_right_edge)

	# Calculate total possible chunks in world (horizontal only)
	var world_width = WORLD_MAX.x - WORLD_MIN.x
	var total_chunks = int(ceil(world_width / CHUNK_SIZE))

	# Check if near edges (1000px threshold)
	const EDGE_THRESHOLD = 1000.0
	var near_left = dist_to_left_edge < EDGE_THRESHOLD
	var near_right = dist_to_right_edge < EDGE_THRESHOLD

	# Calculate neighboring chunk info
	var west_chunk_key = "%d,0" % (chunk_x - 1)
	var east_chunk_key = "%d,0" % (chunk_x + 1)
	var west_loaded = loaded_chunks.has(west_chunk_key)
	var east_loaded = loaded_chunks.has(east_chunk_key)

	debug_label.text = "═══ CHUNK SYSTEM DEBUG ═══\n"
	debug_label.text += "Chunk Size: %.0fpx wide (vertical columns)\n" % CHUNK_SIZE
	debug_label.text += "Current Chunk: [%s]\n" % chunk_key
	debug_label.text += "Player X: %.0f\n" % player_pos.x
	debug_label.text += "\n"
	debug_label.text += "── DISTANCES TO EDGES ──\n"
	debug_label.text += "West Edge: %.0fpx%s\n" % [dist_to_left_edge, " ⚠️NEAR" if near_left else ""]
	debug_label.text += "East Edge: %.0fpx%s\n" % [dist_to_right_edge, " ⚠️NEAR" if near_right else ""]
	debug_label.text += "\n"
	debug_label.text += "── NEIGHBORING CHUNKS ──\n"
	debug_label.text += "West [%s]: %s\n" % [west_chunk_key, "✓LOADED" if west_loaded else "NOT LOADED"]
	debug_label.text += "East [%s]: %s\n" % [east_chunk_key, "✓LOADED" if east_loaded else "NOT LOADED"]
	debug_label.text += "\n"
	debug_label.text += "── CHUNK BOUNDARIES ──\n"
	var chunk_start = chunk_x * CHUNK_SIZE
	var chunk_end = (chunk_x + 1) * CHUNK_SIZE
	debug_label.text += "Current: X=%d to X=%d\n" % [chunk_start, chunk_end]
	debug_label.text += "West: X=%d to X=%d\n" % [chunk_start - CHUNK_SIZE, chunk_start]
	debug_label.text += "East: X=%d to X=%d\n" % [chunk_end, chunk_end + CHUNK_SIZE]
	debug_label.text += "\n"
	debug_label.text += "── STATUS ──\n"
	debug_label.text += "Loaded: %d chunks\n" % loaded_chunks.size()
	debug_label.text += "Loading: %d chunks\n" % chunks_being_loaded.size()
	debug_label.text += "Active chunks: "
	for key in loaded_chunks.keys():
		debug_label.text += "[%s] " % key
	debug_label.text += "\n"
	debug_label.text += "Total World: %d chunks" % total_chunks

	# Position on right side of screen
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		debug_label.position = Vector2(viewport_size.x - 380, 10)  # 380px from right edge for wider text

func update_chunks() -> void:
	"""Smart chunk loading: current chunk always, neighbors only when near edges (1000px threshold)"""
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var player_chunk = get_chunk_key(player_pos)

	# Detect chunk change (player entered new chunk)
	if player_chunk != current_player_chunk:
		print("🗺️ Player entered chunk %s (from %s) at pos %s" % [player_chunk, current_player_chunk, player_pos])
		print("   Currently loaded chunks: %s" % [loaded_chunks.keys()])
		current_player_chunk = player_chunk

	# Parse current chunk X coordinate
	var chunk_parts = player_chunk.split(",")
	var chunk_x = int(chunk_parts[0])

	# Determine which chunks should be loaded (current + edges based on player position)
	var chunks_to_load = []

	# Always load current chunk
	chunks_to_load.append(player_chunk)

	# Calculate player position within chunk
	var chunk_origin_x = chunk_x * CHUNK_SIZE
	var pos_in_chunk_x = player_pos.x - chunk_origin_x

	# Define edge threshold (load neighbors when within this distance from edge)
	const EDGE_THRESHOLD = 1000.0  # Load neighbor when within 1000px of edge

	var dist_to_left_edge = pos_in_chunk_x
	var dist_to_right_edge = CHUNK_SIZE - pos_in_chunk_x

	# Load left chunk only if player is near left edge
	if dist_to_left_edge < EDGE_THRESHOLD:
		var left_chunk_key = "%d,0" % (chunk_x - 1)
		var left_chunk_center = get_chunk_center(left_chunk_key)
		if is_in_world_bounds(left_chunk_center):
			chunks_to_load.append(left_chunk_key)

	# Load right chunk only if player is near right edge
	if dist_to_right_edge < EDGE_THRESHOLD:
		var right_chunk_key = "%d,0" % (chunk_x + 1)
		var right_chunk_center = get_chunk_center(right_chunk_key)
		if is_in_world_bounds(right_chunk_center):
			chunks_to_load.append(right_chunk_key)

	# Load any chunks that aren't loaded yet
	for chunk_key in chunks_to_load:
		if not loaded_chunks.has(chunk_key) and not chunks_being_loaded.has(chunk_key):
			start_async_chunk_load(chunk_key, chunk_key == player_chunk)  # Priority for current chunk

	# Unload chunks that are NOT in our keep list (current + neighbors near edges)
	var chunks_to_unload = []
	for chunk_key in loaded_chunks.keys():
		if not chunks_to_load.has(chunk_key):
			chunks_to_unload.append(chunk_key)

	if chunks_to_unload.size() > 0:
		print("🗑️ Unloading %d chunks: %s (keeping: %s)" % [chunks_to_unload.size(), chunks_to_unload, chunks_to_load])

	for chunk_key in chunks_to_unload:
		unload_chunk(chunk_key)

	# Debug: Always print chunk status when we have multiple chunks loaded
	if loaded_chunks.size() > 1:
		print("📦 Chunks loaded: %s | Player in: %s | Keep list: %s" % [loaded_chunks.keys(), player_chunk, chunks_to_load])

func get_chunk_key(world_pos: Vector2) -> String:
	"""Convert world position to chunk key (horizontal only - Y is always 0)"""
	var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
	return "%d,0" % chunk_x  # Y is always 0 - world is only divided horizontally

func get_chunk_center(chunk_key: String) -> Vector2:
	"""Get center position of chunk from key (square chunks, Y spans full world height)"""
	var parts = chunk_key.split(",")
	var chunk_x = int(parts[0])
	# Square chunks, one row of chunks spanning world height
	# Center Y is 0 (world goes from -CHUNK_SIZE/2 to CHUNK_SIZE/2)
	return Vector2(
		chunk_x * CHUNK_SIZE + CHUNK_SIZE / 2.0,
		0.0  # Center Y of world
	)

func get_chunks_in_radius(center: Vector2, radius: float) -> Array[String]:
	"""Get all chunk keys within radius of center"""
	var chunks: Array[String] = []
	var chunks_to_check = int(ceil(radius / CHUNK_SIZE)) + 1

	var center_chunk_x = int(floor(center.x / CHUNK_SIZE))
	var center_chunk_y = int(floor(center.y / CHUNK_SIZE))

	for dx in range(-chunks_to_check, chunks_to_check + 1):
		for dy in range(-chunks_to_check, chunks_to_check + 1):
			var chunk_x = center_chunk_x + dx
			var chunk_y = center_chunk_y + dy
			var chunk_key = "%d,%d" % [chunk_x, chunk_y]
			var chunk_center = get_chunk_center(chunk_key)

			# Check if chunk center is within radius
			if center.distance_to(chunk_center) <= radius:
				chunks.append(chunk_key)

	return chunks

func update_prop_lod() -> void:
	"""Update LOD for all props - hide shadows on distant props to save render calls"""
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position

	# Process each loaded chunk
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not chunk_data.props_container:
			continue

		# Process trees and rocks in this chunk
		for prop in chunk_data.props_container.get_children():
			if not is_instance_valid(prop):
				continue

			var distance = prop.global_position.distance_to(player_pos)

			# Find and toggle shadow visibility
			var shadow = prop.get_node_or_null("Shadow")
			if shadow:
				shadow.visible = distance < LOD_SHADOW_DISTANCE

			# For lava pools, hide light and particles if far away
			if prop.name.begins_with("LavaPool") or prop.name.begins_with("MonsterLava"):
				for child in prop.get_children():
					if child is PointLight2D:
						child.visible = distance < LOD_DETAIL_DISTANCE
					elif child is GPUParticles2D:
						# Stop emitting particles when far away (saves ~720 particles)
						child.emitting = distance < LOD_DETAIL_DISTANCE

func start_async_chunk_load(chunk_key: String, is_priority: bool) -> void:
	"""Start async loading of a chunk (spreads generation across frames)"""
	if loaded_chunks.has(chunk_key) or chunks_being_loaded.has(chunk_key):
		return

	# Parse chunk ID
	var chunk_parts = chunk_key.split(",")
	var chunk_id = int(chunk_parts[0])

	# === PHASE 1: Spawn path and torches IMMEDIATELY (visual continuity) ===
	# Path appears first so player sees the road extending
	if game_world and game_world.has_method("spawn_path_for_chunk"):
		game_world.spawn_path_for_chunk(chunk_id)

	# Create chunk container immediately
	var chunk_data = ChunkData.new()
	chunk_data.chunk_key = chunk_key
	chunk_data.props_container = Node2D.new()
	chunk_data.props_container.name = "Chunk_" + chunk_key
	game_world.add_child(chunk_data.props_container)

	# Queue for async generation (props will load over several frames)
	chunks_being_loaded[chunk_key] = {
		"chunk_data": chunk_data,
		"props_to_generate": create_prop_generation_queue(chunk_key),
		"is_priority": is_priority,
		"start_time": Time.get_ticks_msec()
	}

	if is_priority:
		print("🚀 Priority chunk load started: %s (path spawned immediately)" % chunk_key)
	else:
		print("⏳ Background chunk load started: %s (path spawned immediately)" % chunk_key)

func create_prop_generation_queue(chunk_key: String) -> Array:
	"""Create a queue of props to generate (in batches for async loading)"""
	var queue = []

	# IMPORTANT: Monster lava pools generate FIRST (largest, anchor points)
	for i in range(MONSTER_LAVA_POOLS_PER_CHUNK):
		queue.append({"type": "monster_lava_pool", "index": i})

	# Regular lava pools next (some cluster around monster pools)
	for i in range(LAVA_POOLS_PER_CHUNK):
		queue.append({"type": "lava_pool", "index": i})

	# Trees (after lava pools to avoid spawning inside them)
	for i in range(TREES_PER_CHUNK):
		queue.append({"type": "tree", "index": i})

	# Large rocks
	for i in range(ROCKS_LARGE_PER_CHUNK):
		queue.append({"type": "rock_large", "index": i})

	# Medium rocks
	for i in range(ROCKS_MEDIUM_PER_CHUNK):
		queue.append({"type": "rock_medium", "index": i})

	# Small rocks
	for i in range(ROCKS_SMALL_PER_CHUNK):
		queue.append({"type": "rock_small", "index": i})

	# Bone clusters
	for i in range(BONE_CLUSTERS_PER_CHUNK):
		queue.append({"type": "bone_cluster", "index": i})

	# Vegetation
	for i in range(DEAD_VEGETATION_PER_CHUNK):
		queue.append({"type": "vegetation", "index": i})

	# Cracks (last - can overlap slightly with other props)
	for i in range(CRACKS_PER_CHUNK):
		queue.append({"type": "crack", "index": i})

	return queue

func process_async_chunk_loading() -> void:
	"""Process chunk loading queue (generate props in small batches per frame)"""
	const PROPS_PER_FRAME_PRIORITY = 30  # Generate 30 props per frame for priority chunks (~317 props total)
	const PROPS_PER_FRAME_BACKGROUND = 15  # Generate 15 props per frame for background chunks

	for chunk_key in chunks_being_loaded.keys():
		var load_data = chunks_being_loaded[chunk_key]
		var chunk_data = load_data.chunk_data
		var props_queue = load_data.props_to_generate
		var is_priority = load_data.is_priority

		# How many props to generate this frame?
		var batch_size = PROPS_PER_FRAME_PRIORITY if is_priority else PROPS_PER_FRAME_BACKGROUND

		# Generate batch of props
		var generated_this_frame = 0
		while generated_this_frame < batch_size and props_queue.size() > 0:
			var prop_data = props_queue.pop_front()
			generate_single_prop(chunk_key, prop_data, chunk_data)  # Pass chunk_data instead of just container
			generated_this_frame += 1

		# Finished loading this chunk?
		if props_queue.size() == 0:
			chunk_data.is_loaded = true
			loaded_chunks[chunk_key] = chunk_data
			chunks_being_loaded.erase(chunk_key)

			var load_time_ms = Time.get_ticks_msec() - load_data.start_time
			var node_count = count_nodes_recursive(chunk_data.props_container)
			print("✅ Chunk %s fully loaded (%d nodes, %dms)" % [chunk_key, node_count, load_time_ms])
			print("   📊 Exclusions: %d lava pools, %d large rocks | Total chunks: %d" % [chunk_data.lava_pool_positions.size(), chunk_data.large_rock_positions.size(), loaded_chunks.size()])

			# === PHASE 3: Spawn ruins LAST (after all props loaded) ===
			# Ruins are complex scenes with guardians - spawn after environment is ready
			var chunk_parts = chunk_key.split(",")
			var chunk_id = int(chunk_parts[0])
			if game_world and game_world.has_method("spawn_ruins_for_chunk"):
				game_world.spawn_ruins_for_chunk(chunk_id)

func is_position_in_lava_pool(pos: Vector2, chunk_data: ChunkData) -> bool:
	"""Check if a position is inside any lava pool exclusion zone"""
	for pool_data in chunk_data.lava_pool_positions:
		var distance = pos.distance_to(pool_data.pos)
		if distance < pool_data.radius:
			return true
	return false

func is_position_on_path(pos: Vector2, width: float = PATH_WIDTH) -> bool:
	"""Check if position is on the main path or branch paths to ruins"""
	# Main path now runs from world edge to world edge
	# Zigzag amplitude is ~350px, so path can be anywhere from Y=-350 to Y=350

	# Path extends across entire world (100px buffer from edges)
	var path_start_x = -Constants.CHUNK_SIZE + 100
	var path_end_x = Constants.CHUNK_SIZE * 2 - 100

	# Check if near the main horizontal path corridor (Y close to 0)
	if abs(pos.y) < width + 350:  # 350 is zigzag amplitude
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
			if dist_to_path < width:
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

func is_position_on_large_rock(pos: Vector2, chunk_data: ChunkData) -> bool:
	"""Check if a position overlaps with any large rock"""
	for rock_data in chunk_data.large_rock_positions:
		var distance = pos.distance_to(rock_data.pos)
		if distance < rock_data.radius:
			return true
	return false

func generate_single_prop(chunk_key: String, prop_data: Dictionary, chunk_data: ChunkData) -> void:
	"""Generate a single prop based on type (used for async loading)"""
	var prop_type = prop_data.type
	var index = prop_data.index
	var container = chunk_data.props_container

	# Use chunk position as seed for deterministic generation
	var seed_value = hash(chunk_key)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value

	# Skip ahead in RNG to get to this prop's position
	# (This ensures same props generate in same positions regardless of batch order)
	for i in range(index * 10):
		rng.randf()

	var chunk_center = get_chunk_center(chunk_key)
	var campfire_pos = CAMPFIRE_POS
	var avoid_campfire_radius = 1050.0

	match prop_type:
		"tree":
			var tree_id = "%s:tree:%d" % [chunk_key, index]
			if harvested_items.has(tree_id):
				return

			# Square chunks: CHUNK_SIZE x CHUNK_SIZE
			var tree_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(tree_pos):
				return
			if tree_pos.distance_to(campfire_pos) < avoid_campfire_radius:
				return
			if is_position_in_lava_pool(tree_pos, chunk_data):
				return  # Don't spawn trees in lava pools

			var tree_type = TREE_TYPES[rng.randi() % TREE_TYPES.size()]
			create_tree(tree_pos, tree_type, container, rng, tree_id)

		"rock_large":
			var rock_id = "%s:rock_large:%d" % [chunk_key, index]
			if harvested_items.has(rock_id):
				return

			var rock_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(rock_pos):
				return
			if rock_pos.distance_to(campfire_pos) < avoid_campfire_radius:
				return
			if is_position_in_lava_pool(rock_pos, chunk_data):
				return  # Don't spawn rocks in lava pools

			# Register large rock position BEFORE creating it (for other rocks to avoid)
			# Large rocks scale from 1.2 to 1.95, average rock size is ~50px
			var exclusion_radius = 60.0  # Generous exclusion to prevent any overlap
			chunk_data.large_rock_positions.append({
				"pos": rock_pos,
				"radius": exclusion_radius
			})

			create_lootable_rock(rock_pos, "rock_large", container, rng, rock_id)

		"rock_medium":
			var rock_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(rock_pos):
				return
			if is_position_in_lava_pool(rock_pos, chunk_data):
				return  # Don't spawn rocks in lava pools
			if is_position_on_large_rock(rock_pos, chunk_data):
				return  # Don't spawn medium rocks on top of large rocks

			create_rock_with_shadow(rock_pos, "rock_medium", container, rng, 0.7, 1.3)

		"rock_small":
			var rock_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(rock_pos):
				return
			if is_position_in_lava_pool(rock_pos, chunk_data):
				return  # Don't spawn rocks in lava pools
			if is_position_on_large_rock(rock_pos, chunk_data):
				return  # Don't spawn small rocks on top of large rocks

			create_rock_with_shadow(rock_pos, "rock_small", container, rng, 0.6, 1.0)

		"monster_lava_pool":
			# MONSTER pools - huge lava lakes that serve as anchor points
			var pool_pos = Vector2.ZERO
			var found_valid = false
			for attempt in range(15):
				pool_pos = chunk_center + Vector2(
					rng.randf_range(-CHUNK_SIZE / 2 + 400, CHUNK_SIZE / 2 - 400),  # Keep away from edges
					rng.randf_range(-CHUNK_SIZE / 2 + 400, CHUNK_SIZE / 2 - 400)
				)

				if not is_in_world_bounds(pool_pos):
					continue
				if pool_pos.distance_to(campfire_pos) < 1200:  # Keep further from campfire
					continue
				# Don't spawn on paths
				if is_position_on_path(pool_pos, PATH_WIDTH + 200):  # Extra buffer for monster pools
					continue
				# Don't spawn too close to other monster pools
				var too_close = false
				for existing in chunk_data.monster_lava_positions:
					if pool_pos.distance_to(existing.pos) < 800:
						too_close = true
						break
				if too_close:
					continue

				found_valid = true
				break

			if not found_valid:
				return

			# Monster pool size: 250-400px (HUGE)
			var pool_size = rng.randf_range(250, 400)
			var exclusion_radius = (pool_size / 2) + 50  # Pool radius + buffer zone

			# Register monster pool position
			chunk_data.monster_lava_positions.append({
				"pos": pool_pos,
				"radius": exclusion_radius
			})
			# Also add to regular lava_pool_positions for exclusion checks
			chunk_data.lava_pool_positions.append({
				"pos": pool_pos,
				"radius": exclusion_radius
			})

			# Create the monster pool
			create_lava_pool(pool_pos, container, rng, pool_size)

		"lava_pool":
			# Regular lava pools - 50% cluster around monster pools, 50% random
			var pool_pos = Vector2.ZERO
			var found_valid = false
			var cluster_around_monster = rng.randf() < 0.5 and chunk_data.monster_lava_positions.size() > 0

			for attempt in range(10):
				if cluster_around_monster:
					# Pick a random monster pool to cluster around
					var monster = chunk_data.monster_lava_positions[rng.randi() % chunk_data.monster_lava_positions.size()]
					# Spawn 200-500px away from monster pool center
					var angle = rng.randf() * TAU
					var distance = rng.randf_range(200, 500)
					pool_pos = monster.pos + Vector2(cos(angle), sin(angle)) * distance
				else:
					# Random position
					pool_pos = chunk_center + Vector2(
						rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
						rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
					)

				if not is_in_world_bounds(pool_pos):
					continue
				if pool_pos.distance_to(campfire_pos) < 800:
					continue
				# Don't spawn lava pools on paths - paths deliberately avoid them!
				if is_position_on_path(pool_pos, PATH_WIDTH + 100):  # Extra buffer for lava
					continue
				# Don't overlap with existing pools
				var overlaps = false
				for existing in chunk_data.lava_pool_positions:
					if pool_pos.distance_to(existing.pos) < existing.radius + 80:
						overlaps = true
						break
				if overlaps:
					continue

				found_valid = true
				break

			if not found_valid:
				return

			# Regular pool size: 60-150px
			var pool_size = rng.randf_range(60, 150)
			var exclusion_radius = (pool_size / 2) + 30  # Pool radius + buffer zone

			# Register lava pool position BEFORE creating it (for other props to avoid)
			chunk_data.lava_pool_positions.append({
				"pos": pool_pos,
				"radius": exclusion_radius
			})

			# Pass pool_size to ensure same size is used for both exclusion and visual
			create_lava_pool(pool_pos, container, rng, pool_size)

		"bone_cluster":
			var cluster_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(cluster_pos):
				return
			if cluster_pos.distance_to(campfire_pos) < 600:
				return
			if is_position_in_lava_pool(cluster_pos, chunk_data):
				return  # Don't spawn bones in lava pools

			create_bone_cluster(cluster_pos, container, rng)

		"vegetation":
			var veg_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(veg_pos):
				return
			if veg_pos.distance_to(campfire_pos) < 600:
				return
			if is_position_in_lava_pool(veg_pos, chunk_data):
				return  # Don't spawn vegetation in lava pools

			create_prop(veg_pos, "ash_pile", container, rng)

		"crack":
			var crack_pos = chunk_center + Vector2(
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
				rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
			)

			if not is_in_world_bounds(crack_pos):
				return
			# Cracks can appear near lava pools (visual effect), so no exclusion check

			var crack_type = ["ground_crack_1", "ground_crack_2"][rng.randi() % 2]
			create_prop(crack_pos, crack_type, container, rng)

func load_chunk(chunk_key: String) -> void:
	"""Legacy sync chunk loading (now redirects to async system)"""
	start_async_chunk_load(chunk_key, true)

func unload_chunk(chunk_key: String) -> void:
	"""Unload and remove props from a chunk"""
	if not loaded_chunks.has(chunk_key):
		return

	var chunk_data = loaded_chunks[chunk_key]
	if is_instance_valid(chunk_data.props_container):
		chunk_data.props_container.queue_free()

	loaded_chunks.erase(chunk_key)

	# Notify game_world to despawn chunk-specific content (path, ruins, torches)
	var chunk_parts = chunk_key.split(",")
	var chunk_id = int(chunk_parts[0])
	if game_world:
		if game_world.has_method("despawn_path_for_chunk"):
			game_world.despawn_path_for_chunk(chunk_id)
		if game_world.has_method("despawn_ruins_for_chunk"):
			game_world.despawn_ruins_for_chunk(chunk_id)

	print("❌ Unloaded chunk %s (%d remaining)" % [chunk_key, loaded_chunks.size()])

# Old synchronous chunk generation function removed - now using async system (see generate_single_prop)

func create_prop(pos: Vector2, prop_type: String, container: Node2D, rng: RandomNumberGenerator, scale_min: float = 0.8, scale_max: float = 1.2) -> void:
	"""Create a single prop sprite"""
	if not PROP_TEXTURES.has(prop_type):
		return

	var texture = load(PROP_TEXTURES[prop_type]) as Texture2D
	if not texture:
		return

	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.global_position = pos

	# Cracks should be at bottom layer, everything else at -1
	if prop_type.begins_with("ground_crack"):
		sprite.z_index = -9  # Bottom layer (on ground, under everything)
	else:
		sprite.z_index = -1  # Normal prop layer

	# Random rotation
	sprite.rotation = rng.randf() * TAU

	# Random scale variation with custom range
	var scale_var = rng.randf_range(scale_min, scale_max)
	sprite.scale = Vector2(scale_var, scale_var)

	# Darker for depth
	sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)

	container.add_child(sprite)

func create_rock_with_shadow(pos: Vector2, prop_type: String, container: Node2D, rng: RandomNumberGenerator, scale_min: float = 0.8, scale_max: float = 1.2) -> void:
	"""Create a rock sprite with feathered shadow"""
	if not PROP_TEXTURES.has(prop_type):
		return

	var texture = load(PROP_TEXTURES[prop_type]) as Texture2D
	if not texture:
		return

	# Create container for rock + shadow
	var rock_container = Node2D.new()
	rock_container.global_position = pos
	rock_container.z_index = -1  # Below player, above ground

	# Random scale
	var scale_var = rng.randf_range(scale_min, scale_max)

	# Add shadow (3 layers)
	add_rock_shadow(rock_container, scale_var, rng)

	# Create sprite
	var sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.rotation = rng.randf() * TAU
	sprite.scale = Vector2(scale_var, scale_var)
	sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)
	sprite.z_index = 0  # Above shadow

	rock_container.add_child(sprite)

	container.add_child(rock_container)

func add_rock_shadow(rock_node: Node2D, rock_scale: float, rng: RandomNumberGenerator) -> void:
	"""Add dark disturbed earth patch under rock"""
	add_ground_disturbance(rock_node, rock_scale * 50, rng, 0.25)

func add_ground_disturbance(parent_node: Node2D, base_size: float, rng: RandomNumberGenerator, darkness: float = 0.2) -> void:
	"""Add subtle dark patch to ground for disturbed earth effect"""
	# Check distance to campfire and reduce alpha if within glow
	var campfire_pos = Vector2(Constants.CHUNK_SIZE / 2, 0)  # Center of chunk 0
	var distance_to_campfire = parent_node.global_position.distance_to(campfire_pos)
	var glow_radius = 3000.0  # Campfire glow range

	# Calculate alpha reduction based on distance (closer = lighter)
	var alpha_multiplier = 1.0
	if distance_to_campfire < glow_radius:
		# Fade from 0.3x at center to 1.0x at edge
		var fade = distance_to_campfire / glow_radius
		alpha_multiplier = lerp(0.3, 1.0, fade)

	# Create 3-layer feathered patch for smooth blending
	var layers = [
		{"size_mult": 1.4, "alpha": darkness * 0.4 * alpha_multiplier},
		{"size_mult": 1.0, "alpha": darkness * 0.6 * alpha_multiplier},
		{"size_mult": 0.6, "alpha": darkness * 0.8 * alpha_multiplier}
	]

	for layer in layers:
		var patch = ColorRect.new()
		var size = base_size * layer.size_mult * rng.randf_range(0.9, 1.1)
		patch.size = Vector2(size, size)
		patch.position = -patch.size / 2 + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		patch.color = Color(0.08, 0.06, 0.05, layer.alpha)  # Dark brown
		patch.z_index = -9  # Just above ground
		patch.rotation = rng.randf() * TAU
		parent_node.add_child(patch)

func is_in_world_bounds(pos: Vector2) -> bool:
	"""Check if position is within world boundaries"""
	return pos.x >= WORLD_MIN.x and pos.x <= WORLD_MAX.x and \
		   pos.y >= WORLD_MIN.y and pos.y <= WORLD_MAX.y

func create_tree(pos: Vector2, tree_type: String, container: Node2D, rng: RandomNumberGenerator, tree_id: String) -> void:
	"""Create a lootable tree with proper scaling and collision"""
	if not PROP_TEXTURES.has(tree_type):
		return

	var texture = load(PROP_TEXTURES[tree_type]) as Texture2D
	if not texture:
		return

	# Load HarvestableTree script if available
	var HarvestableTreeScript = load("res://scripts/environment/HarvestableTree.gd")
	var tree_node: StaticBody2D
	if HarvestableTreeScript:
		tree_node = HarvestableTreeScript.new()
	else:
		tree_node = StaticBody2D.new()

	tree_node.name = "Tree_" + tree_id.replace(":", "_")
	tree_node.position = pos
	tree_node.collision_layer = 2  # Layer 2 for obstacles
	tree_node.collision_mask = 0
	tree_node.z_index = 10  # Above all player layers (player max z=9)

	# Determine tree size (small trees rare - only 10%)
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.1:
		tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (rare - 10%)
	elif size_roll < 0.55:
		tree_scale = rng.randf_range(2.93, 3.9)  # Medium trees (45%)
	else:
		tree_scale = rng.randf_range(3.9, 5.2)  # Large trees (45%)

	var tree_flipped = rng.randf() < 0.5

	# Create shadow at base of tree
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 45 * (tree_scale / 2.5) * 0.75
	var shadow_height = shadow_width * 0.4
	shadow.size = Vector2(shadow_width, shadow_height)
	var shadow_y = 56 * tree_scale
	var shadow_x = -shadow_width / 2
	shadow.position = Vector2(shadow_x, shadow_y)
	shadow.color = Color(0, 0, 0, 0.6)
	shadow.z_index = -4

	# Apply oval shader
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	if (dist > 1.0) {
		discard;
	}
	float alpha = 1.0 - smoothstep(0.6, 1.0, dist);
	COLOR.a *= alpha;
}
"""
	shader_material.shader = shader
	shadow.material = shader_material
	tree_node.add_child(shadow)

	# Add ground disturbance (dark earth patch around tree base)
	add_ground_disturbance(tree_node, tree_scale * 80, rng, 0.18)

	# Create sprite with proper scale
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(tree_scale, tree_scale)
	sprite.flip_h = tree_flipped
	sprite.z_index = 10  # Above all player layers (player max z=9)

	# Mix of brown dead trees and white birch healing trees (50/50 split)
	var is_white_birch = rng.randf() < 0.5
	var color_variation = rng.randf_range(0.9, 1.0)

	if is_white_birch:
		# White birch tint for magical healing trees
		sprite.modulate = Color(color_variation * 1.1, color_variation * 1.15, color_variation * 1.2, 1.0)
	else:
		# Brown tint for dead trees
		sprite.modulate = Color(color_variation, color_variation * 0.7, color_variation * 0.5, 1.0)

	tree_node.add_child(sprite)

	# Birch tree healing shimmer particles removed for performance
	# (was ~945 particles across all birch trees)

	# Add collision shape at tree trunk base
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 10 * tree_scale
	collision_shape.shape = shape
	collision_shape.position = Vector2(0, 50 * tree_scale)
	tree_node.add_child(collision_shape)

	# Store tree ID for harvest tracking
	tree_node.set_meta("tree_id", tree_id)
	tree_node.set_meta("lootable_type", "tree")

	container.add_child(tree_node)

func create_lootable_rock(pos: Vector2, rock_type: String, container: Node2D, rng: RandomNumberGenerator, rock_id: String) -> void:
	"""Create a lootable rock"""
	if not PROP_TEXTURES.has(rock_type):
		return

	var texture = load(PROP_TEXTURES[rock_type]) as Texture2D
	if not texture:
		return

	# Create HarvestableRock for mineable rocks
	var HarvestableRockClass = preload("res://scripts/environment/HarvestableRock.gd")
	var rock_node = HarvestableRockClass.new()
	rock_node.name = "Rock_" + rock_id.replace(":", "_")
	rock_node.global_position = pos
	rock_node.z_index = -1  # Below player, above ground

	# Set collision layers (layer 2 for obstacles)
	rock_node.collision_layer = 2
	rock_node.collision_mask = 0

	# Add shadow under rock (3-layer feathering)
	add_rock_shadow(rock_node, 1.5, rng)  # Base scale for large rocks

	# Create sprite with variable scaling for large rocks (50% bigger overall)
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.rotation = rng.randf() * TAU
	var scale_var = rng.randf_range(1.2, 1.95)  # 50% bigger: 0.8*1.5=1.2, 1.3*1.5=1.95
	sprite.scale = Vector2(scale_var, scale_var)
	sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)
	sprite.z_index = 0  # Above shadow

	rock_node.add_child(sprite)

	# Add collision shape for the rock body
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 30.0 * scale_var  # Scale collision with rock size
	collision_shape.shape = shape
	rock_node.add_child(collision_shape)

	# Set ore amount based on rock size
	if scale_var < 1.4:
		rock_node.ore_amount = 1  # Small rocks
	elif scale_var < 1.7:
		rock_node.ore_amount = 2  # Medium rocks
	else:
		rock_node.ore_amount = 3  # Large rocks

	# Store rock ID for harvest tracking
	rock_node.set_meta("rock_id", rock_id)
	rock_node.set_meta("lootable_type", "rock")

	container.add_child(rock_node)

func create_lava_pool(pos: Vector2, container: Node2D, rng: RandomNumberGenerator, preset_pool_size: float = -1.0) -> void:
	"""Create a lava pool with gradient colors, borders, and cracks"""
	var pool_size = preset_pool_size if preset_pool_size > 0 else rng.randf_range(60, 150)

	# 30% chance for perfect circle, otherwise elongated
	var elongation_x = 1.0
	var elongation_y = 1.0
	var pool_rotation = 0.0

	if rng.randf() > 0.3:  # 70% elongated
		elongation_x = rng.randf_range(0.8, 1.25)
		elongation_y = rng.randf_range(0.8, 1.25)
		pool_rotation = rng.randf() * TAU

	var lava_pool = Node2D.new()
	lava_pool.name = "LavaPool"
	lava_pool.position = pos
	lava_pool.rotation = pool_rotation
	lava_pool.z_index = -3

	# Add animation script if available
	var animation_script = load("res://scripts/effects/LavaPoolAnimation.gd")
	if animation_script:
		lava_pool.set_script(animation_script)

	# Create cracks radiating from pool
	var num_cracks = rng.randi_range(4, 8)
	for crack_i in range(num_cracks):
		var crack = Line2D.new()
		crack.width = rng.randf_range(1.5, 3.5)
		crack.default_color = Color(0.02, 0.015, 0.01, rng.randf_range(0.6, 0.9))
		crack.joint_mode = Line2D.LINE_JOINT_SHARP
		crack.antialiased = false

		var angle = (float(crack_i) / num_cracks) * TAU + rng.randf_range(-0.2, 0.2)
		var start_radius = (pool_size / 2) + 8
		var start_x = cos(angle) * start_radius * elongation_x
		var start_y = sin(angle) * start_radius * elongation_y

		var crack_length = rng.randf_range(pool_size * 0.2, pool_size * 0.6)
		var num_segments = rng.randi_range(3, 6)

		var points = PackedVector2Array()
		points.append(Vector2(start_x, start_y))

		var current_angle = angle
		var current_distance = start_radius
		for seg in range(num_segments):
			current_angle += rng.randf_range(-0.3, 0.3)
			current_distance += crack_length / num_segments
			var seg_x = cos(current_angle) * current_distance * elongation_x
			var seg_y = sin(current_angle) * current_distance * elongation_y
			points.append(Vector2(seg_x, seg_y))

		crack.points = points
		lava_pool.add_child(crack)

	# Create soft borders for gradual blending
	var outer_border = Polygon2D.new()
	var outer_vertices = PackedVector2Array()
	for j in range(64):
		var angle = (float(j) / 64) * TAU
		var radius = (pool_size / 2) + 15
		var x = cos(angle) * radius * elongation_x
		var y = sin(angle) * radius * elongation_y
		outer_vertices.append(Vector2(x, y))
	outer_border.polygon = outer_vertices
	outer_border.color = Color(0.09, 0.085, 0.08, 0.3)
	lava_pool.add_child(outer_border)

	var mid_border = Polygon2D.new()
	var mid_vertices = PackedVector2Array()
	for j in range(64):
		var angle = (float(j) / 64) * TAU
		var radius = (pool_size / 2) + 10
		var x = cos(angle) * radius * elongation_x
		var y = sin(angle) * radius * elongation_y
		mid_vertices.append(Vector2(x, y))
	mid_border.polygon = mid_vertices
	mid_border.color = Color(0.07, 0.06, 0.055, 0.5)
	lava_pool.add_child(mid_border)

	var inner_border = Polygon2D.new()
	var inner_vertices = PackedVector2Array()
	for j in range(64):
		var angle = (float(j) / 64) * TAU
		var radius = (pool_size / 2) + 5
		var x = cos(angle) * radius * elongation_x
		var y = sin(angle) * radius * elongation_y
		inner_vertices.append(Vector2(x, y))
	inner_border.polygon = inner_vertices
	inner_border.color = Color(0.04, 0.03, 0.02, 0.7)
	lava_pool.add_child(inner_border)

	# Create gradient layers from dark red to bright orange
	var layer_data = [
		{"size": 1.00, "color": Color(0.7, 0.15, 0.0, 1.0)},
		{"size": 0.75, "color": Color(0.9, 0.25, 0.0, 0.7)},
		{"size": 0.50, "color": Color(1.0, 0.42, 0.05, 0.6)},
		{"size": 0.30, "color": Color(1.0, 0.58, 0.1, 0.5)},
		{"size": 0.15, "color": Color(1.0, 0.7, 0.15, 0.65)}
	]

	for layer in layer_data:
		var circle = Polygon2D.new()
		var vertices = PackedVector2Array()

		for j in range(64):
			var angle = (float(j) / 64) * TAU
			var radius = pool_size / 2 * layer.size
			radius += rng.randf_range(-4, 4)  # Irregularity
			var x = cos(angle) * radius * elongation_x
			var y = sin(angle) * radius * elongation_y
			vertices.append(Vector2(x, y))

		circle.polygon = vertices
		circle.color = layer.color
		lava_pool.add_child(circle)

	# Add PointLight2D for glowing effect
	var light = PointLight2D.new()
	light.enabled = true
	light.position = Vector2.ZERO
	light.color = Color(1.0, 0.5, 0.1, 1.0)
	light.energy = rng.randf_range(1.0, 1.6)
	light.blend_mode = PointLight2D.BLEND_MODE_ADD
	light.range_z_min = -10
	light.range_z_max = 10
	light.shadow_enabled = false

	var light_gradient = Gradient.new()
	light_gradient.set_color(0, Color(1, 1, 1, 1))
	light_gradient.set_color(1, Color(0, 0, 0, 0))
	var light_texture = GradientTexture2D.new()
	light_texture.gradient = light_gradient
	light_texture.width = 256
	light_texture.height = 256
	light_texture.fill = GradientTexture2D.FILL_RADIAL
	light_texture.fill_from = Vector2(0.5, 0.5)
	light_texture.fill_to = Vector2(0, 0.5)
	light.texture = light_texture
	light.texture_scale = pool_size / 80.0

	lava_pool.add_child(light)

	# Add heat particles (embers rising)
	var particles = GPUParticles2D.new()
	particles.amount = int(pool_size / 8)
	particles.lifetime = 2.5
	particles.explosiveness = 0.0
	particles.randomness = 0.7
	particles.local_coords = false

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var emission_width = (pool_size / 3) * elongation_x
	var emission_height = (pool_size / 3) * elongation_y
	material.emission_box_extents = Vector3(emission_width, emission_height, 0)
	material.direction = Vector3(0, -1, 0)
	material.spread = 12.0
	material.initial_velocity_min = 25.0
	material.initial_velocity_max = 50.0
	material.gravity = Vector3(0, -28, 0)
	material.scale_min = 1.0
	material.scale_max = 2.0
	material.color = Color(1.0, 0.65, 0.1, 1.0)

	var particle_gradient = Gradient.new()
	particle_gradient.add_point(0.0, Color(1.0, 0.7, 0.15, 0))
	particle_gradient.add_point(0.08, Color(1.0, 0.65, 0.12, 1))
	particle_gradient.add_point(0.35, Color(1.0, 0.5, 0.08, 1))
	particle_gradient.add_point(0.65, Color(0.95, 0.3, 0.05, 1))
	particle_gradient.add_point(1.0, Color(0.6, 0.15, 0.0, 0))
	var particle_gradient_tex = GradientTexture1D.new()
	particle_gradient_tex.gradient = particle_gradient
	material.color_ramp = particle_gradient_tex

	particles.process_material = material

	var ember_gradient = Gradient.new()
	ember_gradient.set_color(0, Color(1, 1, 1, 1))
	ember_gradient.set_color(0.7, Color(1, 1, 1, 1))
	ember_gradient.set_color(0.85, Color(1, 1, 1, 0.5))
	ember_gradient.set_color(1, Color(0, 0, 0, 0))
	var ember_texture = GradientTexture2D.new()
	ember_texture.gradient = ember_gradient
	ember_texture.width = 4
	ember_texture.height = 4
	ember_texture.fill = GradientTexture2D.FILL_RADIAL
	ember_texture.fill_from = Vector2(0.5, 0.5)
	particles.texture = ember_texture

	lava_pool.add_child(particles)

	container.add_child(lava_pool)

func create_bone_cluster(pos: Vector2, container: Node2D, rng: RandomNumberGenerator) -> void:
	"""Create a cluster of bones and skulls"""
	var cluster = Node2D.new()
	cluster.name = "BoneCluster"
	cluster.position = pos
	cluster.z_index = -1

	# Create 3-5 bones/skulls in a cluster
	var num_bones = rng.randi_range(3, 5)
	for i in range(num_bones):
		var bone_type = ["bones", "skull"][rng.randi() % 2]
		if not PROP_TEXTURES.has(bone_type):
			continue

		var texture = load(PROP_TEXTURES[bone_type]) as Texture2D
		if not texture:
			continue

		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.position = Vector2(
			rng.randf_range(-30, 30),
			rng.randf_range(-30, 30)
		)
		sprite.rotation = rng.randf() * TAU
		sprite.scale = Vector2.ONE * rng.randf_range(0.8, 1.2)
		sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)

		cluster.add_child(sprite)

	container.add_child(cluster)

func mark_as_harvested(item_id: String) -> void:
	"""Mark an item as harvested so it doesn't respawn"""
	harvested_items[item_id] = true
	print("🪓 Harvested: %s" % item_id)

func count_nodes_recursive(node: Node) -> int:
	"""Count total nodes in a node tree"""
	var count = 1  # Count this node
	for child in node.get_children():
		count += count_nodes_recursive(child)
	return count

func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()
