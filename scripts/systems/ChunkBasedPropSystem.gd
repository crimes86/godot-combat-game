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

# Prop density per chunk (8000x8000 = 64M px²)
# OPTIMIZED: Aggressively reduced for multiplayer performance (~10k node target for 2 chunks)
const TREES_PER_CHUNK: int = 180  # Dead trees (lootable - wood) - doubled from 90
const ROCKS_LARGE_PER_CHUNK: int = 60  # Large rocks (lootable - stone/ore) - doubled from 30
const ROCKS_MEDIUM_PER_CHUNK: int = 30  # Medium rocks (decorative) - reduced from 50
const ROCKS_SMALL_PER_CHUNK: int = 25  # Small rocks (decorative) - reduced from 40
const MONSTER_LAVA_POOLS_PER_CHUNK: int = 3  # Giant lava pools (anchor points) - reduced from 4
const LAVA_POOLS_PER_CHUNK: int = 10  # Regular lava pools (some cluster around monsters) - reduced from 16
const BLISTER_POOLS_PER_CHUNK: int = 45  # Small scattered "blister" pools to fill empty gaps
const BONE_CLUSTERS_PER_CHUNK: int = 16  # Large skeletal remains (ritual piles) - doubled for density
const SCATTERED_BONES_PER_CHUNK: int = 35  # Individual bones filling empty space - reduced from 80

# Bone optimization settings
const PICKABLE_BONE_PERCENTAGE: float = 0.15  # 15% of bones are pickable (interactive)
const BONE_PROXIMITY_LOAD_DISTANCE: float = 2000.0  # Only load pickable bones within this distance
const BONE_PROXIMITY_CHECK_INTERVAL: float = 1.0  # How often to check proximity for bone loading
const DEAD_VEGETATION_PER_CHUNK: int = 12  # Dead bushes/ash piles (decorative) - reduced from 24
const CRACKS_PER_CHUNK: int = 15  # Ground cracks (visual) - reduced from 30

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

# Network sync for harvestables
var harvestables_by_id: Dictionary = {}  # {tree_id or rock_id: HarvestableTree/Rock node}
var harvestable_states: Dictionary = {}  # {id: {is_harvested, is_fallen/is_mined, has_loot}} for sync

# Prop textures (from game_world.gd)
const PROP_TEXTURES = {
	"dead_tree": "res://assets/environment/wasteland/dead_tree.png",
	"pine_tree": "res://assets/environment/wasteland/pine_tree.png",
	"autumn_tree": "res://assets/environment/wasteland/autumn_tree.png",
	"ash_pile": "res://assets/environment/wasteland/ash_pile.png",
	"bones": "res://assets/environment/wasteland/bones.png",
	"skull": "res://assets/environment/wasteland/skull.png",
	"ground_crack_1": "res://assets/environment/wasteland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/wasteland/ground_crack_2.png",
}

# === TIERED ROCK SYSTEM ===
# Zone 1 = Tier 1 (tan), Zone 2 = Tier 2 (grey), Zone 3 = Tier 3 (ancient)
const ROCK_TEXTURES = {
	# Zone 1 - Tan/Brown rocks (Tier 1)
	"zone1": {
		"small": [
			"res://assets/environment/wasteland/rocks/zone1/rock_small_1.png",
		],
		"medium": [
			"res://assets/environment/wasteland/rocks/zone1/rock_medium_1.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_medium_2.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_medium_flat.png",
		],
		"large": [
			"res://assets/environment/wasteland/rocks/zone1/rock_large_1.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_boulder_pair.png",
		],
		"cluster": [
			"res://assets/environment/wasteland/rocks/zone1/rock_spike_cluster.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_cluster_wide.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_xlarge_cluster.png",
		],
		"standing": [
			"res://assets/environment/wasteland/rocks/zone1/rock_standing_1.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_standing_2.png",
			"res://assets/environment/wasteland/rocks/zone1/rock_spike_tall.png",
		],
	},
	# Zone 2 - Grey rocks (Tier 2)
	"zone2": {
		"small": [
			"res://assets/environment/wasteland/rocks/zone2/rock_small_1.png",
		],
		"medium": [
			"res://assets/environment/wasteland/rocks/zone2/rock_medium_1.png",
			"res://assets/environment/wasteland/rocks/zone2/rock_medium_flat.png",
		],
		"large": [
			"res://assets/environment/wasteland/rocks/zone2/rock_large_1.png",
			"res://assets/environment/wasteland/rocks/zone2/rock_large_flat.png",
			"res://assets/environment/wasteland/rocks/zone2/rock_boulder_1.png",
			"res://assets/environment/wasteland/rocks/zone2/rock_boulder_2.png",
			"res://assets/environment/wasteland/rocks/zone2/rock_boulder_3.png",
		],
		"cluster": [
			"res://assets/environment/wasteland/rocks/zone2/rock_xlarge_cluster.png",
		],
		"standing": [
			"res://assets/environment/wasteland/rocks/zone2/rock_standing_1.png",
		],
	},
}

# Rock tier data - defines mining requirements and drops per tier
const ROCK_TIERS = {
	1: {
		"name": "Wasteland Rock",
		"zone": "zone1",
		"pickaxe_tier": 0,  # Basic pickaxe (starter)
		"mine_time": 3.0,
		"xp": 10,
		"drops": {
			"stone": {"min": 1, "max": 3},
			"copper_ore": {"min": 0, "max": 1, "chance": 0.3},
		}
	},
	2: {
		"name": "Highland Rock",
		"zone": "zone2",
		"pickaxe_tier": 1,  # Iron pickaxe
		"mine_time": 4.0,
		"xp": 20,
		"drops": {
			"stone": {"min": 2, "max": 4},
			"iron_ore": {"min": 1, "max": 2},
			"gem_shard": {"min": 0, "max": 1, "chance": 0.15},
		}
	},
	3: {
		"name": "Ancient Stone",
		"zone": "zone3",
		"pickaxe_tier": 2,  # Steel pickaxe
		"mine_time": 5.0,
		"xp": 35,
		"drops": {
			"stone": {"min": 2, "max": 3},
			"iron_ore": {"min": 1, "max": 3},
			"gold_ore": {"min": 0, "max": 2, "chance": 0.4},
			"ancient_fragment": {"min": 0, "max": 1, "chance": 0.1},
		}
	},
}

# Tree scene files - collision positions can be edited visually in these scenes
const TREE_SCENES = {
	"dead_tree": "res://scenes/environment/DeadTree.tscn",
	"pine_tree": "res://scenes/environment/PineTree.tscn",
	"autumn_tree": "res://scenes/environment/AutumnTree.tscn"
}

# Tree types with weighted rarity: 60% dead, 30% pine, 10% autumn
const TREE_TYPES = ["dead_tree", "pine_tree", "autumn_tree"]

# Zone to tier mapping - determines which rock textures and tier data to use
# Chunk -1 and 0 = Zone 1 (tier 1, tan rocks)
# Chunk 1+ = Zone 2 (tier 2, grey rocks)
# Zone 3 (tier 3) reserved for future expansion
func get_zone_for_chunk(chunk_key: String) -> String:
	"""Determine which zone a chunk belongs to based on chunk key"""
	var chunk_x = int(chunk_key.split(",")[0])
	if chunk_x <= 0:
		return "zone1"
	else:
		return "zone2"

func get_tier_for_chunk(chunk_key: String) -> int:
	"""Determine rock tier based on chunk position"""
	var zone = get_zone_for_chunk(chunk_key)
	if zone == "zone1":
		return 1
	elif zone == "zone2":
		return 2
	else:
		return 3

func get_rock_texture_for_zone(zone: String, size_category: String, rng: RandomNumberGenerator) -> String:
	"""Get a random rock texture path for a given zone and size category"""
	if not ROCK_TEXTURES.has(zone):
		zone = "zone1"  # Fallback to zone1

	var zone_textures = ROCK_TEXTURES[zone]
	if not zone_textures.has(size_category):
		# Try to find a fallback size
		if zone_textures.has("medium"):
			size_category = "medium"
		elif zone_textures.has("small"):
			size_category = "small"
		else:
			return ""  # No textures available

	var textures = zone_textures[size_category]
	if textures.is_empty():
		return ""

	return textures[rng.randi() % textures.size()]

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
	var tree_positions: Array[Vector2] = []  # Tree positions for spacing enforcement
	var all_prop_positions: Array[Dictionary] = []  # [{pos: Vector2, radius: float}] ALL props for bone fill
	var ritual_sites: Array[Dictionary] = []  # {pos: Vector2, size: int} - dense bone ritual areas
	# Bone optimization: store deferred pickable bones (spawn when player is near)
	var deferred_pickable_bones: Array[Dictionary] = []  # [{pos, texture, scale, rotation, modulate}]
	var active_pickable_bones: Array[Node2D] = []  # Currently spawned pickable bones

func _ready() -> void:
	print("🗺️ ChunkBasedPropSystem initialized - 3 square chunks (%.0fx%.0fpx each)" % [CHUNK_SIZE, CHUNK_SIZE])

	# Register with GlobalDebugOverlay for F3 debug display
	_register_debug_overlay()

	# Connect to Constants F3 toggle for bone highlighting
	if Constants:
		Constants.debug_display_toggled.connect(_on_debug_toggled)

	# Listen for new peer connections to sync harvestable state
	multiplayer.peer_connected.connect(_on_peer_connected)

func initialize(world: Node) -> void:
	game_world = world
	player = get_tree().get_first_node_in_group("player")

func _register_debug_overlay() -> void:
	"""Register chunk debug info with GlobalDebugOverlay"""
	var overlay = get_node_or_null("/root/GlobalDebugOverlay")
	if overlay and overlay.has_method("register_section"):
		overlay.register_section("chunks", _get_chunk_debug_info)
	else:
		# Retry after a frame if overlay not ready yet
		call_deferred("_register_debug_overlay_deferred")

func _register_debug_overlay_deferred() -> void:
	var overlay = get_node_or_null("/root/GlobalDebugOverlay")
	if overlay and overlay.has_method("register_section"):
		overlay.register_section("chunks", _get_chunk_debug_info)

func _on_debug_toggled(is_visible: bool) -> void:
	"""Called when F3 debug display is toggled"""
	# Highlight bones when debug is active
	highlight_bones_debug(is_visible)

var chunk_update_timer: float = 0.0
const CHUNK_UPDATE_INTERVAL: float = 0.5  # Check chunks every 0.5s for responsive loading/unloading
# No preload distance needed - we always keep current + left + right loaded

var current_player_chunk: String = ""  # Track which chunk player is currently in
var chunks_being_loaded: Dictionary = {}  # {chunk_key: props_remaining} for async loading

# LOD system for props
var lod_update_timer: float = 0.0
const LOD_UPDATE_INTERVAL: float = 1.0  # Update LOD every 1 second
const LOD_SHADOW_DISTANCE: float = 1500.0  # Hide shadows beyond this distance
const LOD_DETAIL_DISTANCE: float = 2500.0  # Simplify props beyond this distance

# Bone proximity loading timer
var bone_proximity_timer: float = 0.0

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

	# Update bone proximity loading (spawn/despawn pickable bones based on player distance)
	bone_proximity_timer += delta
	if bone_proximity_timer >= BONE_PROXIMITY_CHECK_INTERVAL:
		bone_proximity_timer = 0.0
		update_bone_proximity()

func process_multiplayer_chunks(delta: float) -> void:
	"""Process chunks for all players in multiplayer mode (server only)"""
	# Continue async chunk loading if in progress
	process_async_chunk_loading()

	# Only update chunks occasionally
	chunk_update_timer += delta
	if chunk_update_timer >= CHUNK_UPDATE_INTERVAL:
		chunk_update_timer = 0.0
		update_chunks_for_all_players()

	# Update bone proximity loading (spawn/despawn pickable bones based on player distance)
	bone_proximity_timer += delta
	if bone_proximity_timer >= BONE_PROXIMITY_CHECK_INTERVAL:
		bone_proximity_timer = 0.0
		update_bone_proximity_multiplayer()

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

func _get_chunk_debug_info() -> String:
	"""Return chunk debug info for GlobalDebugOverlay"""
	if not player or not is_instance_valid(player):
		return ""

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

	var text = "═══ CHUNKS ═══\n"
	text += "Chunk Size: %.0fpx\n" % CHUNK_SIZE
	text += "Current: [%s]\n" % chunk_key
	text += "─────────────────\n"
	text += "West Edge: %.0fpx%s\n" % [dist_to_left_edge, " ⚠️" if near_left else ""]
	text += "East Edge: %.0fpx%s\n" % [dist_to_right_edge, " ⚠️" if near_right else ""]
	text += "─────────────────\n"
	text += "West [%s]: %s\n" % [west_chunk_key, "✓" if west_loaded else "✗"]
	text += "East [%s]: %s\n" % [east_chunk_key, "✓" if east_loaded else "✗"]
	text += "─────────────────\n"
	text += "Loaded: %d | Loading: %d\n" % [loaded_chunks.size(), chunks_being_loaded.size()]
	text += "Total World: %d chunks" % total_chunks

	return text

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
	# Pre-calculate squared distances for faster comparison (avoids sqrt)
	var shadow_dist_sq = LOD_SHADOW_DISTANCE * LOD_SHADOW_DISTANCE
	var detail_dist_sq = LOD_DETAIL_DISTANCE * LOD_DETAIL_DISTANCE

	# Process each loaded chunk
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not chunk_data.props_container:
			continue

		# Process trees and rocks in this chunk
		for prop in chunk_data.props_container.get_children():
			if not is_instance_valid(prop):
				continue

			# Use squared distance to avoid expensive sqrt
			var dist_sq = prop.global_position.distance_squared_to(player_pos)

			# Find and toggle shadow visibility
			var shadow = prop.get_node_or_null("Shadow")
			if shadow:
				shadow.visible = dist_sq < shadow_dist_sq

			# For lava pools, hide light and particles if far away
			if prop.name.begins_with("LavaPool") or prop.name.begins_with("MonsterLava"):
				var show_detail = dist_sq < detail_dist_sq
				for child in prop.get_children():
					if child is PointLight2D:
						child.visible = show_detail
					elif child is GPUParticles2D:
						child.emitting = show_detail

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

	# Blister pools - small scattered pools to fill empty gaps
	for i in range(BLISTER_POOLS_PER_CHUNK):
		queue.append({"type": "blister_pool", "index": i})

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

	# Vegetation (before bones so bones can fill around them too)
	for i in range(DEAD_VEGETATION_PER_CHUNK):
		queue.append({"type": "vegetation", "index": i})

	# Cracks
	for i in range(CRACKS_PER_CHUNK):
		queue.append({"type": "crack", "index": i})

	# BONES LAST - fill empty spaces after all other props are placed
	# Ritual sites (dense bone piles at specific locations)
	for i in range(BONE_CLUSTERS_PER_CHUNK):
		queue.append({"type": "ritual_site", "index": i})

	# Scattered bones fill remaining empty space
	queue.append({"type": "bone_fill", "index": 0})

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

			# === PHASE 3: Spawn POIs LAST (after all props loaded) ===
			# POIs are complex scenes - spawn after environment is ready
			var chunk_parts = chunk_key.split(",")
			var chunk_id = int(chunk_parts[0])
			if game_world and game_world.has_method("spawn_ruins_for_chunk"):
				game_world.spawn_ruins_for_chunk(chunk_id)
			if game_world and game_world.has_method("spawn_pois_for_chunk"):
				game_world.spawn_pois_for_chunk(chunk_id)

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

			# Try multiple positions to find valid spot (better distribution)
			const MIN_TREE_SPACING = 180.0  # Minimum distance between trees
			const MAX_ATTEMPTS = 15

			var tree_pos = Vector2.ZERO
			var found_valid = false

			for _attempt in range(MAX_ATTEMPTS):
				# Square chunks: CHUNK_SIZE x CHUNK_SIZE (no edge buffer - fill to edges)
				tree_pos = chunk_center + Vector2(
					rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),
					rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2)
				)

				# Check world bounds
				if not is_in_world_bounds(tree_pos):
					continue

				# Avoid campfire area
				if tree_pos.distance_to(campfire_pos) < avoid_campfire_radius:
					continue

				# Avoid lava pools
				if is_position_in_lava_pool(tree_pos, chunk_data):
					continue

				# Avoid main path (keeps paths visually clear)
				if is_position_on_path(tree_pos, PATH_WIDTH + 50):
					continue

				# Check minimum spacing from other trees (prevents clustering)
				var too_close = false
				for existing_tree in chunk_data.tree_positions:
					if tree_pos.distance_to(existing_tree) < MIN_TREE_SPACING:
						too_close = true
						break
				if too_close:
					continue

				found_valid = true
				break

			if not found_valid:
				return  # Couldn't find valid position after all attempts

			# Weighted tree selection: 60% dead, 30% pine, 10% autumn
			var roll = rng.randf()
			var tree_type: String
			if roll < 0.6:
				tree_type = "dead_tree"
			elif roll < 0.9:
				tree_type = "pine_tree"
			else:
				tree_type = "autumn_tree"
			create_tree(tree_pos, tree_type, container, rng, tree_id)
			# Track position for spacing and bone fill
			chunk_data.tree_positions.append(tree_pos)
			chunk_data.all_prop_positions.append({"pos": tree_pos, "radius": 80.0})

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
			chunk_data.all_prop_positions.append({"pos": rock_pos, "radius": exclusion_radius})

			create_lootable_rock(rock_pos, "large", container, rng, rock_id, chunk_key)

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

			create_rock_with_shadow(rock_pos, "medium", container, rng, chunk_key, 0.7, 1.3)
			chunk_data.all_prop_positions.append({"pos": rock_pos, "radius": 40.0})

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

			create_rock_with_shadow(rock_pos, "small", container, rng, chunk_key, 0.6, 1.0)
			chunk_data.all_prop_positions.append({"pos": rock_pos, "radius": 25.0})

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

		"blister_pool":
			# Small scattered "blister" pools - completely random placement to fill gaps
			var pool_pos = Vector2.ZERO
			var found_valid = false

			for attempt in range(15):
				# Pure random placement across the chunk
				pool_pos = chunk_center + Vector2(
					rng.randf_range(-CHUNK_SIZE / 2 + 50, CHUNK_SIZE / 2 - 50),
					rng.randf_range(-CHUNK_SIZE / 2 + 50, CHUNK_SIZE / 2 - 50)
				)

				if not is_in_world_bounds(pool_pos):
					continue
				if pool_pos.distance_to(campfire_pos) < 600:
					continue
				# Don't spawn on paths
				if is_position_on_path(pool_pos, PATH_WIDTH + 80):
					continue
				# Don't overlap with existing pools (smaller buffer for blisters)
				var overlaps = false
				for existing in chunk_data.lava_pool_positions:
					if pool_pos.distance_to(existing.pos) < existing.radius + 60:
						overlaps = true
						break
				if overlaps:
					continue

				found_valid = true
				break

			if not found_valid:
				return

			# Blister pools are small: 30-60px
			var pool_size = rng.randf_range(30, 60)
			var exclusion_radius = (pool_size / 2) + 20

			chunk_data.lava_pool_positions.append({
				"pos": pool_pos,
				"radius": exclusion_radius
			})

			create_lava_pool(pool_pos, container, rng, pool_size)

		"ritual_site":
			# Find an empty spot for a dense bone ritual pile
			var site_pos = find_empty_spot_for_ritual(chunk_center, chunk_data, rng, campfire_pos)
			if site_pos != Vector2.ZERO:
				# Random size: 1=small (3-4 wolves), 2=medium (4-5), 3=large (5-7)
				var site_size = rng.randi_range(1, 3)
				chunk_data.ritual_sites.append({"pos": site_pos, "size": site_size})
				create_ritual_bone_pile(site_pos, container, rng, site_size)
				# Mark this area as occupied (larger sites have bigger radius)
				var site_radius = 80.0 + site_size * 20.0
				chunk_data.all_prop_positions.append({"pos": site_pos, "radius": site_radius})

		"bone_fill":
			# Fill empty spaces with scattered bones
			fill_empty_space_with_bones(chunk_center, chunk_data, container, rng, campfire_pos)

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
			chunk_data.all_prop_positions.append({"pos": veg_pos, "radius": 30.0})

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

	# Notify game_world to despawn chunk-specific content (path, ruins, POIs, torches)
	var chunk_parts = chunk_key.split(",")
	var chunk_id = int(chunk_parts[0])
	if game_world:
		if game_world.has_method("despawn_path_for_chunk"):
			game_world.despawn_path_for_chunk(chunk_id)
		if game_world.has_method("despawn_ruins_for_chunk"):
			game_world.despawn_ruins_for_chunk(chunk_id)
		if game_world.has_method("despawn_pois_for_chunk"):
			game_world.despawn_pois_for_chunk(chunk_id)

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

	# Cracks at bottom layer, ash piles below rocks, everything else at -1
	if prop_type.begins_with("ground_crack"):
		sprite.z_index = -9  # Bottom layer (on ground, under everything)
	elif prop_type == "ash_pile":
		sprite.z_index = -2  # Below rocks (0) so ash piles don't render on top
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

func create_rock_with_shadow(pos: Vector2, size_category: String, container: Node2D, rng: RandomNumberGenerator, chunk_key: String, scale_min: float = 0.8, scale_max: float = 1.2) -> void:
	"""Create a decorative rock sprite with feathered shadow using zone-based textures"""
	var zone = get_zone_for_chunk(chunk_key)
	var texture_path = get_rock_texture_for_zone(zone, size_category, rng)
	if texture_path.is_empty():
		return

	var texture = load(texture_path) as Texture2D
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

func add_ground_disturbance(_parent_node: Node2D, _base_size: float, _rng: RandomNumberGenerator, _darkness: float = 0.2) -> void:
	"""DISABLED - Old terrain alteration before shader. Now using shader for ground effects."""
	pass

func is_in_world_bounds(pos: Vector2) -> bool:
	"""Check if position is within world boundaries"""
	return pos.x >= WORLD_MIN.x and pos.x <= WORLD_MAX.x and \
		   pos.y >= WORLD_MIN.y and pos.y <= WORLD_MAX.y

func create_tree(pos: Vector2, tree_type: String, container: Node2D, rng: RandomNumberGenerator, tree_id: String) -> void:
	"""Create a lootable tree using scene files (collision positions editable in scenes)"""
	if not TREE_SCENES.has(tree_type):
		return

	var scene_path = TREE_SCENES[tree_type]
	if not ResourceLoader.exists(scene_path):
		return

	var tree_scene = load(scene_path)
	var tree_node = tree_scene.instantiate()

	tree_node.name = "Tree_" + tree_id.replace(":", "_")
	tree_node.position = pos
	tree_node.collision_layer = 2  # Layer 2 for obstacles
	tree_node.collision_mask = 0
	tree_node.z_index = 10  # Above all player layers (player max z=9)

	# Determine tree size (small trees rare - only 10%)
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.1:
		tree_scale = rng.randf_range(0.3, 0.45)  # Small trees (rare - 10%)
	elif size_roll < 0.55:
		tree_scale = rng.randf_range(0.45, 0.6)  # Medium trees (45%)
	else:
		tree_scale = rng.randf_range(0.6, 0.8)  # Large trees (45%)

	var tree_flipped = rng.randf() < 0.5

	# Get nodes from scene
	var sprite = tree_node.get_node_or_null("Sprite")
	var shadow = tree_node.get_node_or_null("Shadow")
	var collision = tree_node.get_node_or_null("CollisionShape2D")

	if sprite:
		sprite.scale = Vector2(tree_scale, tree_scale)
		sprite.flip_h = tree_flipped
		sprite.z_index = 10

		# Add variation to trees - brightness, saturation, and slight hue shifts
		var brightness = rng.randf_range(0.8, 1.15)
		var saturation_shift = rng.randf_range(0.85, 1.15)
		var hue_shift = rng.randf_range(-0.08, 0.08)

		# Apply variation based on tree type
		if tree_type == "dead_tree":
			var dead_tree_darkness = 0.55
			sprite.modulate = Color(
				brightness * dead_tree_darkness * (1.0 + hue_shift),
				brightness * dead_tree_darkness * (0.95 - abs(hue_shift) * 0.5),
				brightness * dead_tree_darkness * (0.9 - hue_shift),
				1.0
			)
		elif tree_type == "pine_tree":
			var pine_mute = 0.7
			sprite.modulate = Color(
				brightness * pine_mute * (0.85 + hue_shift),
				brightness * pine_mute * saturation_shift * 0.9,
				brightness * pine_mute * (0.8 - hue_shift),
				1.0
			)
		else:  # autumn_tree
			sprite.modulate = Color(
				brightness * min(1.2, 1.0 + hue_shift * 2),
				brightness * (0.7 - hue_shift),
				brightness * 0.6,
				1.0
			)

	if shadow:
		var shadow_width = 45 * (tree_scale / 2.5) * 0.75
		var shadow_height = shadow_width * 0.4
		shadow.size = Vector2(shadow_width, shadow_height)
		shadow.position = Vector2(-shadow_width / 2, 56 * tree_scale)

	if collision:
		# Scale collision position based on tree size (scene position is for scale 1.0)
		var base_collision_y = collision.position.y
		collision.position = Vector2(0, base_collision_y * tree_scale)
		if collision.shape is CircleShape2D:
			collision.shape.radius = 10 * tree_scale

	# Store tree ID for harvest tracking
	tree_node.set_meta("tree_id", tree_id)
	tree_node.set_meta("lootable_type", "tree")
	tree_node.set_meta("network_id", tree_id)

	container.add_child(tree_node)

	# Track for network sync
	harvestables_by_id[tree_id] = tree_node

func create_lootable_rock(pos: Vector2, size_category: String, container: Node2D, rng: RandomNumberGenerator, rock_id: String, chunk_key: String) -> void:
	"""Create a lootable rock using zone-based textures and tier system"""
	var zone = get_zone_for_chunk(chunk_key)
	var rock_tier = get_tier_for_chunk(chunk_key)

	# Get random texture for this zone and size
	var texture_path = get_rock_texture_for_zone(zone, size_category, rng)
	if texture_path.is_empty():
		return

	var texture = load(texture_path) as Texture2D
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

	# Set rock tier based on zone (this determines drops and mining requirements)
	rock_node.set_rock_tier(rock_tier, size_category)

	# Store rock ID for harvest tracking
	rock_node.set_meta("rock_id", rock_id)
	rock_node.set_meta("lootable_type", "rock")
	rock_node.set_meta("network_id", rock_id)  # Use rock_id as network ID

	container.add_child(rock_node)

	# Track for network sync
	harvestables_by_id[rock_id] = rock_node

func create_lava_pool(pos: Vector2, container: Node2D, rng: RandomNumberGenerator, preset_pool_size: float = -1.0) -> void:
	"""Create a lava pool - optimized version with fewer nodes"""
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

	# Create just 3 cracks (reduced from 4-8)
	var num_cracks = 3
	for crack_i in range(num_cracks):
		var crack = Line2D.new()
		crack.width = rng.randf_range(1.5, 3.5)
		crack.default_color = Color(0.02, 0.02, 0.02, rng.randf_range(0.6, 0.9))
		crack.joint_mode = Line2D.LINE_JOINT_SHARP
		crack.antialiased = false

		var angle = (float(crack_i) / num_cracks) * TAU + rng.randf_range(-0.2, 0.2)
		var start_radius = (pool_size / 2) + 8
		var start_x = cos(angle) * start_radius * elongation_x
		var start_y = sin(angle) * start_radius * elongation_y

		var crack_length = rng.randf_range(pool_size * 0.2, pool_size * 0.6)
		var num_segments = 3  # Reduced from 3-6

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

	# Single border (reduced from 3)
	var border = Polygon2D.new()
	var border_vertices = PackedVector2Array()
	for j in range(32):  # Reduced from 64 vertices
		var angle = (float(j) / 32) * TAU
		var radius = (pool_size / 2) + 10
		var x = cos(angle) * radius * elongation_x
		var y = sin(angle) * radius * elongation_y
		border_vertices.append(Vector2(x, y))
	border.polygon = border_vertices
	border.color = Color(0.04, 0.04, 0.04, 0.6)
	lava_pool.add_child(border)

	# Reduced gradient layers (3 instead of 5)
	var layer_data = [
		{"size": 1.00, "color": Color(0.7, 0.15, 0.0, 1.0)},
		{"size": 0.50, "color": Color(1.0, 0.4, 0.05, 0.7)},
		{"size": 0.15, "color": Color(1.0, 0.7, 0.15, 0.65)}
	]

	for layer in layer_data:
		var circle = Polygon2D.new()
		var vertices = PackedVector2Array()

		for j in range(24):  # Reduced from 64 vertices
			var angle = (float(j) / 24) * TAU
			var radius = pool_size / 2 * layer.size
			radius += rng.randf_range(-4, 4)
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

	# Add damage area for players walking on lava
	var damage_area = Area2D.new()
	damage_area.collision_layer = 0  # Don't exist on any layer
	damage_area.collision_mask = 1  # Detect layer 1 (player)

	# Add damage script (handles damage + 50% movement slow)
	var damage_script = load("res://scripts/effects/LavaDamage.gd")
	if damage_script:
		damage_area.set_script(damage_script)

	# Create collision shape (60% of pool size so edges are safe to walk on)
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	# Use 60% of the smaller dimension to create tight circle
	var damage_radius = (pool_size / 2) * 0.6 * min(elongation_x, elongation_y)
	circle_shape.radius = damage_radius
	collision_shape.shape = circle_shape

	damage_area.add_child(collision_shape)
	lava_pool.add_child(damage_area)

	# Add discovery zone for large pools (monster pools 200+) - triggers quest without needing to step in lava
	if pool_size >= 200:
		var discovery_area = Area2D.new()
		discovery_area.name = "DiscoveryZone"
		discovery_area.collision_layer = 0
		discovery_area.collision_mask = 1  # Detect player

		var discovery_shape = CollisionShape2D.new()
		var discovery_circle = CircleShape2D.new()
		# Discovery radius is pool radius + 80px buffer (can discover from the edge)
		discovery_circle.radius = (pool_size / 2) + 80
		discovery_shape.shape = discovery_circle

		discovery_area.add_child(discovery_shape)
		lava_pool.add_child(discovery_area)

		# Connect discovery signal
		discovery_area.body_entered.connect(func(body):
			if body.is_in_group("player"):
				var quest_manager = discovery_area.get_node_or_null("/root/QuestManager")
				if quest_manager and quest_manager.has_method("on_location_discovered"):
					quest_manager.on_location_discovered("lava_pool")
					print("🔥 Discovered lava pool!")
		)

	container.add_child(lava_pool)

func find_guaranteed_ritual_spot(chunk_center: Vector2, chunk_data: ChunkData, rng: RandomNumberGenerator, campfire_pos: Vector2, target_zone: String) -> Vector2:
	"""Find a ritual spot in a guaranteed zone (upper_mid or lower_mid).
	Ensures ritual sites spawn in the middle of upper and lower halves."""

	const RITUAL_SITE_RADIUS: float = 120.0

	# Target Y ranges for upper/lower middle zones
	var y_min: float
	var y_max: float
	match target_zone:
		"upper_mid":
			y_min = 1500.0   # Middle-ish of upper half (Y 0 to 4000)
			y_max = 3000.0
		"lower_mid":
			y_min = -3000.0  # Middle-ish of lower half (Y -4000 to 0)
			y_max = -1500.0
		_:
			return Vector2.ZERO

	for attempt in range(40):
		var test_pos = Vector2(
			chunk_center.x + rng.randf_range(-CHUNK_SIZE / 2 + 200, CHUNK_SIZE / 2 - 200),
			rng.randf_range(y_min, y_max)
		)

		if not is_in_world_bounds(test_pos):
			continue
		if test_pos.distance_to(campfire_pos) < 600:
			continue

		# Must NOT be inside or too close to any lava pool
		var too_close_to_lava = false
		for pool in chunk_data.lava_pool_positions:
			var dist_to_pool = test_pos.distance_to(pool.pos)
			if dist_to_pool < pool.radius + RITUAL_SITE_RADIUS:
				too_close_to_lava = true
				break
		if too_close_to_lava:
			continue

		# Must be OFF the path
		if is_position_on_path(test_pos, PATH_WIDTH + 150):
			continue

		# Check against existing props
		var too_close = false
		for prop in chunk_data.all_prop_positions:
			if test_pos.distance_to(prop.pos) < prop.radius + 80:
				too_close = true
				break

		# Also check ritual sites
		for site in chunk_data.ritual_sites:
			if test_pos.distance_to(site.pos) < 250:
				too_close = true
				break

		if not too_close:
			return test_pos

	return Vector2.ZERO

func find_empty_spot_for_ritual(chunk_center: Vector2, chunk_data: ChunkData, rng: RandomNumberGenerator, campfire_pos: Vector2) -> Vector2:
	"""Find an empty spot away from other props for a ritual bone pile.
	Ritual sites must be OFF the path and NOT inside lava pools. Spread throughout the world."""

	const RITUAL_SITE_RADIUS: float = 120.0   # Ritual site bone spread radius + buffer

	for attempt in range(30):
		var test_pos = chunk_center + Vector2(
			rng.randf_range(-CHUNK_SIZE / 2 + 100, CHUNK_SIZE / 2 - 100),
			rng.randf_range(-CHUNK_SIZE / 2 + 100, CHUNK_SIZE / 2 - 100)
		)

		if not is_in_world_bounds(test_pos):
			continue
		if test_pos.distance_to(campfire_pos) < 600:
			continue

		# Must NOT be inside or too close to any lava pool
		var too_close_to_lava = false
		for pool in chunk_data.lava_pool_positions:
			var dist_to_pool = test_pos.distance_to(pool.pos)
			# Must be outside pool radius + ritual radius + buffer
			if dist_to_pool < pool.radius + RITUAL_SITE_RADIUS:
				too_close_to_lava = true
				break
		if too_close_to_lava:
			continue

		# Ritual sites must be OFF the path - wolves cross the path to roam
		if is_position_on_path(test_pos, PATH_WIDTH + 150):
			continue

		# Check against all existing props - need at least 120px clearance for ritual site
		var too_close = false
		for prop in chunk_data.all_prop_positions:
			if test_pos.distance_to(prop.pos) < prop.radius + 80:
				too_close = true
				break

		# Also check ritual sites
		for site in chunk_data.ritual_sites:
			if test_pos.distance_to(site.pos) < 250:  # Keep ritual sites spread out
				too_close = true
				break

		if not too_close:
			return test_pos

	return Vector2.ZERO  # No valid spot found

func create_ritual_bone_pile(pos: Vector2, container: Node2D, rng: RandomNumberGenerator, site_size: int = 2) -> void:
	"""Create a dense ritual pile of bones and skulls. Size: 1=small, 2=medium, 3=large"""
	var pile = Node2D.new()
	pile.name = "RitualBonePile"
	pile.position = pos
	pile.z_index = -1

	# Bone count based on size: small=4-6, medium=6-10, large=10-15
	var num_bones: int
	var cluster_radius: float
	match site_size:
		1:  # Small
			num_bones = rng.randi_range(4, 6)
			cluster_radius = 50.0
		2:  # Medium
			num_bones = rng.randi_range(6, 10)
			cluster_radius = 70.0
		3:  # Large
			num_bones = rng.randi_range(10, 15)
			cluster_radius = 100.0
		_:
			num_bones = rng.randi_range(6, 10)
			cluster_radius = 70.0

	for i in range(num_bones):
		# 55% bones, 45% skulls (more skulls in ritual piles)
		var bone_type = "bones" if rng.randf() < 0.55 else "skull"
		if not PROP_TEXTURES.has(bone_type):
			continue

		var texture = load(PROP_TEXTURES[bone_type]) as Texture2D
		if not texture:
			continue

		var sprite = Sprite2D.new()
		sprite.texture = texture
		# Cluster radius based on size
		var angle = rng.randf() * TAU
		var dist = rng.randf_range(15, cluster_radius)
		sprite.position = Vector2(cos(angle), sin(angle)) * dist
		sprite.rotation = rng.randf() * TAU
		sprite.scale = Vector2.ONE * rng.randf_range(0.6, 1.4)
		# Pale bone color - high contrast
		var brightness = rng.randf_range(0.8, 1.1)
		sprite.modulate = Color(brightness, brightness * 0.97, brightness * 0.9, 1.0)

		pile.add_child(sprite)

	container.add_child(pile)

func fill_empty_space_with_bones(chunk_center: Vector2, chunk_data: ChunkData, container: Node2D, rng: RandomNumberGenerator, campfire_pos: Vector2) -> void:
	"""Fill empty spaces between props with scattered bones using a grid approach"""
	var bones_placed = 0
	var grid_spacing = 300  # Check every 300px (reduced from 150 for performance)
	var half_chunk = CHUNK_SIZE / 2

	# Iterate through grid positions in the chunk
	var x = chunk_center.x - half_chunk + 50
	while x < chunk_center.x + half_chunk - 50:
		var y = chunk_center.y - half_chunk + 50
		while y < chunk_center.y + half_chunk - 50:
			var base_pos = Vector2(x, y)

			# Add some randomness to the grid position
			var test_pos = base_pos + Vector2(
				rng.randf_range(-60, 60),
				rng.randf_range(-60, 60)
			)

			# Skip if not valid
			if not is_in_world_bounds(test_pos):
				y += grid_spacing
				continue
			if test_pos.distance_to(campfire_pos) < 500:
				y += grid_spacing
				continue
			if is_position_in_lava_pool(test_pos, chunk_data):
				y += grid_spacing
				continue

			# Check if this spot is empty (not too close to props)
			var is_empty = true
			var min_distance = 50.0  # Minimum distance from any prop

			for prop in chunk_data.all_prop_positions:
				var dist = test_pos.distance_to(prop.pos)
				if dist < prop.radius + 20:  # Too close to prop
					is_empty = false
					break

			if is_empty:
				# Random chance to place bone (40% fill rate - reduced for performance)
				if rng.randf() < 0.4:
					create_single_bone(test_pos, container, rng, chunk_data)
					bones_placed += 1

			y += grid_spacing
		x += grid_spacing

func create_single_bone(pos: Vector2, container: Node2D, rng: RandomNumberGenerator, chunk_data: ChunkData = null) -> void:
	"""Create a single scattered bone - 90% static sprites, 10% pickable (deferred loading)"""
	# 80% bones, 20% skulls for scattered
	var bone_type = "bones" if rng.randf() < 0.8 else "skull"
	if not PROP_TEXTURES.has(bone_type):
		return

	var texture_path = PROP_TEXTURES[bone_type]
	var texture = load(texture_path) as Texture2D
	if not texture:
		return

	# Visual properties
	var bone_rotation = rng.randf() * TAU
	var bone_scale = Vector2.ONE * rng.randf_range(0.35, 0.75)  # Smaller scattered bones
	var brightness = rng.randf_range(0.7, 0.95)
	var bone_modulate = Color(brightness, brightness * 0.97, brightness * 0.9, 1.0)

	# Decide if this bone is pickable (10%) or static (90%)
	var is_pickable = rng.randf() < PICKABLE_BONE_PERCENTAGE

	if is_pickable and chunk_data != null:
		# Store data for deferred spawning (proximity-based)
		chunk_data.deferred_pickable_bones.append({
			"pos": pos,
			"texture_path": texture_path,
			"scale": bone_scale,
			"rotation": bone_rotation,
			"modulate": bone_modulate,
			"spawned": false
		})
	else:
		# Create static sprite (minimal node - just a Sprite2D)
		var sprite = Sprite2D.new()
		sprite.name = "StaticBone"
		sprite.texture = texture
		sprite.position = pos
		sprite.rotation = bone_rotation
		sprite.scale = bone_scale
		sprite.modulate = bone_modulate
		sprite.z_index = -1
		container.add_child(sprite)

func update_bone_proximity() -> void:
	"""Spawn/despawn pickable bones based on player proximity"""
	if not player or not is_instance_valid(player):
		return

	var player_pos = player.global_position
	var load_dist_sq = BONE_PROXIMITY_LOAD_DISTANCE * BONE_PROXIMITY_LOAD_DISTANCE
	var unload_dist_sq = (BONE_PROXIMITY_LOAD_DISTANCE + 500) * (BONE_PROXIMITY_LOAD_DISTANCE + 500)

	var total_deferred = 0
	var total_active = 0
	var spawned_this_update = 0

	# Process each loaded chunk
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not chunk_data.props_container:
			continue

		total_deferred += chunk_data.deferred_pickable_bones.size()
		total_active += chunk_data.active_pickable_bones.size()

		# Spawn bones that are now in range
		for bone_data in chunk_data.deferred_pickable_bones:
			if bone_data.spawned:
				continue

			var dist_sq = bone_data.pos.distance_squared_to(player_pos)
			if dist_sq < load_dist_sq:
				# Spawn the pickable bone
				var bone = spawn_pickable_bone(bone_data, chunk_data.props_container)
				if bone:
					bone_data.spawned = true
					bone_data.node = bone
					chunk_data.active_pickable_bones.append(bone)
					spawned_this_update += 1

		# Despawn bones that are now out of range
		var bones_to_remove = []
		for bone in chunk_data.active_pickable_bones:
			if not is_instance_valid(bone):
				bones_to_remove.append(bone)
				continue

			var dist_sq = bone.global_position.distance_squared_to(player_pos)
			if dist_sq > unload_dist_sq:
				# Find the data and mark as not spawned
				for bone_data in chunk_data.deferred_pickable_bones:
					if bone_data.get("node") == bone:
						bone_data.spawned = false
						bone_data.erase("node")
						break
				bone.queue_free()
				bones_to_remove.append(bone)

		# Clean up removed bones from active list
		for bone in bones_to_remove:
			chunk_data.active_pickable_bones.erase(bone)

	# Debug output (remove after testing)
	if spawned_this_update > 0 or Engine.get_process_frames() % 300 == 0:
		print("🦴 Bones - Deferred: %d | Active: %d | Spawned: %d" % [total_deferred, total_active, spawned_this_update])

func update_bone_proximity_multiplayer() -> void:
	"""Spawn/despawn pickable bones for all players in multiplayer mode"""
	var all_players = get_tree().get_nodes_in_group("player")
	if all_players.is_empty():
		return

	var load_dist_sq = BONE_PROXIMITY_LOAD_DISTANCE * BONE_PROXIMITY_LOAD_DISTANCE
	var unload_dist_sq = (BONE_PROXIMITY_LOAD_DISTANCE + 500) * (BONE_PROXIMITY_LOAD_DISTANCE + 500)

	var total_deferred = 0
	var total_active = 0
	var spawned_this_update = 0

	# Process each loaded chunk
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not chunk_data.props_container:
			continue

		total_deferred += chunk_data.deferred_pickable_bones.size()
		total_active += chunk_data.active_pickable_bones.size()

		# Spawn bones that are in range of ANY player
		for bone_data in chunk_data.deferred_pickable_bones:
			if bone_data.spawned:
				continue

			# Check against all players
			var should_spawn = false
			for player_node in all_players:
				if not is_instance_valid(player_node):
					continue
				var dist_sq = bone_data.pos.distance_squared_to(player_node.global_position)
				if dist_sq < load_dist_sq:
					should_spawn = true
					break

			if should_spawn:
				var bone = spawn_pickable_bone(bone_data, chunk_data.props_container)
				if bone:
					bone_data.spawned = true
					bone_data.node = bone
					chunk_data.active_pickable_bones.append(bone)
					spawned_this_update += 1

		# Despawn bones that are out of range of ALL players
		var bones_to_remove = []
		for bone in chunk_data.active_pickable_bones:
			if not is_instance_valid(bone):
				bones_to_remove.append(bone)
				continue

			# Check if any player is close enough to keep it spawned
			var any_player_near = false
			for player_node in all_players:
				if not is_instance_valid(player_node):
					continue
				var dist_sq = bone.global_position.distance_squared_to(player_node.global_position)
				if dist_sq < unload_dist_sq:
					any_player_near = true
					break

			if not any_player_near:
				# Find the data and mark as not spawned
				for bone_data in chunk_data.deferred_pickable_bones:
					if bone_data.get("node") == bone:
						bone_data.spawned = false
						bone_data.erase("node")
						break
				bone.queue_free()
				bones_to_remove.append(bone)

		# Clean up removed bones from active list
		for bone in bones_to_remove:
			chunk_data.active_pickable_bones.erase(bone)

	# Debug output (remove after testing)
	if spawned_this_update > 0 or Engine.get_process_frames() % 300 == 0:
		print("🦴 Bones - Deferred: %d | Active: %d | Spawned: %d" % [total_deferred, total_active, spawned_this_update])

func spawn_pickable_bone(bone_data: Dictionary, container: Node2D) -> Node2D:
	"""Spawn a pickable bone with sparkle effect"""
	var texture = load(bone_data.texture_path) as Texture2D
	if not texture:
		return null

	# Generate network_id if not already set (for multiplayer sync)
	if not bone_data.has("network_id"):
		bone_data["network_id"] = "bone_%d_%d" % [int(bone_data.pos.x), int(bone_data.pos.y)]

	# Check if already harvested
	if harvested_items.has(bone_data.network_id):
		return null

	var PickableBoneClass = preload("res://scripts/items/PickableBone.gd")
	var bone = PickableBoneClass.new()
	bone.name = "PickableBone_%s" % bone_data.network_id
	bone.position = bone_data.pos
	bone.z_index = -1
	bone.set_meta("network_id", bone_data.network_id)

	bone.setup_bone(texture, bone_data.scale, bone_data.rotation, bone_data.modulate)

	# Connect signal to handle pickup cleanup
	bone.bone_picked_up.connect(_on_bone_picked_up)

	# Add sparkle effect to indicate this bone is pickable
	add_bone_sparkle(bone)

	container.add_child(bone)
	return bone

func _on_bone_picked_up(bone_node: Node2D) -> void:
	"""Handle bone pickup - remove from tracking"""
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data:
			continue

		# Remove from active list
		chunk_data.active_pickable_bones.erase(bone_node)

		# Remove from deferred list entirely (so it doesn't respawn)
		for i in range(chunk_data.deferred_pickable_bones.size() - 1, -1, -1):
			var bone_data = chunk_data.deferred_pickable_bones[i]
			if bone_data.get("node") == bone_node:
				chunk_data.deferred_pickable_bones.remove_at(i)
				break

func add_bone_sparkle(bone_node: Node2D) -> void:
	"""Add sparkle effect to pickable bone (like treasure chests)"""
	var sparkle_container = Node2D.new()
	sparkle_container.name = "SparkleContainer"
	sparkle_container.z_index = 10  # Draw on top

	# Create 3 small sparkles tightly clustered above the bone
	var sparkle_offsets = [
		Vector2(0, -8),    # Center above
		Vector2(-4, -6),   # Slightly left
		Vector2(4, -6)     # Slightly right
	]

	for i in range(sparkle_offsets.size()):
		var sparkle = create_bone_sparkle()
		sparkle.position = sparkle_offsets[i]
		sparkle_container.add_child(sparkle)

		# Stagger animation start times
		animate_bone_sparkle(sparkle, i * 0.25)

	bone_node.add_child(sparkle_container)

func create_bone_sparkle() -> Polygon2D:
	"""Create a single sparkle (4-pointed star) - bone colored"""
	var sparkle = Polygon2D.new()

	# Create 4-pointed star shape (smaller than chest sparkles)
	var size = 4.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Top point
		Vector2(0.7, -0.7),     # Inner top-right
		Vector2(size, 0),       # Right point
		Vector2(0.7, 0.7),      # Inner bottom-right
		Vector2(0, size),       # Bottom point
		Vector2(-0.7, 0.7),     # Inner bottom-left
		Vector2(-size, 0),      # Left point
		Vector2(-0.7, -0.7)     # Inner top-left
	])

	sparkle.polygon = points
	# Bone-colored sparkle (warm white/cream)
	sparkle.color = Color(1.0, 0.95, 0.8, 0.85)

	return sparkle

func animate_bone_sparkle(sparkle: Polygon2D, delay: float) -> void:
	"""Animate sparkle floating upward and fading out"""
	if delay > 0:
		await get_tree().create_timer(delay).timeout

	if not is_instance_valid(sparkle):
		return

	# Store initial position
	var start_pos = sparkle.position

	# Create looping animation
	var tween = create_tween()
	tween.set_loops()

	# Float up slightly and fade out, then reset (tight animation)
	tween.tween_property(sparkle, "position:y", start_pos.y - 6, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.25, 0.9)

	# Reset and pause
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.tween_property(sparkle, "modulate:a", 0.85, 0.0)
	tween.tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.3)

func mark_as_harvested(item_id: String) -> void:
	"""Mark an item as harvested so it doesn't respawn"""
	harvested_items[item_id] = true
	print("🪓 Harvested: %s" % item_id)

# ═══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER: Sync Harvestable State to New Players
# ═══════════════════════════════════════════════════════════════════════════════

func _on_peer_connected(peer_id: int) -> void:
	"""When a new peer connects, send them all harvested states."""
	if not multiplayer.is_server():
		return

	# Small delay to let the client fully initialize and load chunks
	await get_tree().create_timer(1.0).timeout
	sync_harvestable_state_to_peer(peer_id)

func sync_harvestable_state_to_peer(peer_id: int) -> void:
	"""Send all current harvestable states to a newly connected client"""
	if not multiplayer.is_server():
		return

	print("🌲 Syncing harvestable state to peer %d (%d states tracked)" % [peer_id, harvestable_states.size()])

	# Sync all harvested items (so they don't respawn on client)
	for item_id in harvested_items.keys():
		_sync_harvested_item.rpc_id(peer_id, item_id)

	# Sync detailed states for items that may be mid-harvest
	for harvestable_id in harvestable_states.keys():
		var state = harvestable_states[harvestable_id]
		_sync_harvestable_state.rpc_id(peer_id, harvestable_id, state)

@rpc("authority", "call_remote", "reliable")
func _sync_harvested_item(item_id: String) -> void:
	"""Client receives notice that an item is harvested"""
	harvested_items[item_id] = true
	print("🌲 [Client] Received harvested state: %s" % item_id)

	# Find and update the harvestable if it exists
	var harvestable = harvestables_by_id.get(item_id)
	if harvestable and is_instance_valid(harvestable):
		# Apply harvested state
		if harvestable is HarvestableTree:
			if not harvestable.is_harvested:
				harvestable.is_harvested = true
				harvestable.is_fallen = true
				harvestable.tree_loot.clear()
				# Hide the tree sprite
				if harvestable.tree_sprite:
					harvestable.tree_sprite.modulate.a = 0.0
		elif harvestable is HarvestableRock:
			if not harvestable.is_harvested:
				harvestable.is_harvested = true
				harvestable.is_mined = true
				harvestable.rock_loot.clear()
				# Hide the rock sprite
				if harvestable.rock_sprite:
					harvestable.rock_sprite.modulate.a = 0.0

@rpc("authority", "call_remote", "reliable")
func _sync_harvestable_state(harvestable_id: String, state: Dictionary) -> void:
	"""Client receives detailed state for a harvestable"""
	harvestable_states[harvestable_id] = state
	print("🌲 [Client] Received harvestable state: %s = %s" % [harvestable_id, state])

	var harvestable = harvestables_by_id.get(harvestable_id)
	if not harvestable or not is_instance_valid(harvestable):
		return

	# Apply state
	if harvestable is HarvestableTree:
		harvestable.is_harvested = state.get("is_harvested", false)
		harvestable.is_fallen = state.get("is_fallen", false)
		if not state.get("has_loot", true):
			harvestable.tree_loot.clear()
			harvestable.remove_loot_indicator()
	elif harvestable is HarvestableRock:
		harvestable.is_harvested = state.get("is_harvested", false)
		harvestable.is_mined = state.get("is_mined", false)
		if not state.get("has_loot", true):
			harvestable.rock_loot.clear()
			harvestable.remove_loot_indicator()

func count_nodes_recursive(node: Node) -> int:
	"""Count total nodes in a node tree"""
	var count = 1  # Count this node
	for child in node.get_children():
		count += count_nodes_recursive(child)
	return count

func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()

func get_prop_stats() -> Dictionary:
	"""Get detailed prop statistics for debug display"""
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
		"chunks_loaded": loaded_chunks.size()
	}

	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not is_instance_valid(chunk_data.props_container):
			continue

		for child in chunk_data.props_container.get_children():
			var child_name = child.name
			var child_nodes = count_nodes_recursive(child)
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

# Store original modulates for restoration
var _bone_original_modulates: Dictionary = {}

func highlight_bones_debug(enabled: bool) -> void:
	"""Highlight all bones for debugging.
	CYAN = ChunkBasedPropSystem ritual bone piles (wolves spawn here)
	GREEN = ChunkBasedPropSystem scattered/static bones
	RED = game_world.gd bones (NO wolves - from load_interactive_props)"""

	# === CHUNK BASED PROP SYSTEM BONES ===
	for chunk_key in loaded_chunks.keys():
		var chunk_data = loaded_chunks[chunk_key]
		if not chunk_data or not is_instance_valid(chunk_data.props_container):
			continue

		for child in chunk_data.props_container.get_children():
			# Ritual bone piles (dense clusters with wolves)
			if child.name == "RitualBonePile":
				for sprite in child.get_children():
					if sprite is Sprite2D:
						_set_bone_highlight(sprite, enabled, Color.CYAN)

			# Static/scattered bones from ChunkBasedPropSystem
			elif child.name == "StaticBone":
				if child is Sprite2D:
					_set_bone_highlight(child, enabled, Color.GREEN)

	# === GAME_WORLD.GD BONES (ScatteredProps node) ===
	# These are bones from load_interactive_props() - NO wolves spawn here!
	if game_world and is_instance_valid(game_world):
		var scattered_props = game_world.get_node_or_null("ScatteredProps")
		if scattered_props:
			for child in scattered_props.get_children():
				# Bones/skulls from create_prop_sprite: named "bones_123" or "skull_456"
				if child.name.begins_with("bones_") or child.name.begins_with("skull_"):
					# The actual sprite is a child
					for subchild in child.get_children():
						if subchild is Sprite2D and subchild.name != "Shadow":
							_set_bone_highlight(subchild, enabled, Color.RED)

	# Clear stored modulates when disabling
	if not enabled:
		_bone_original_modulates.clear()

	if enabled:
		print("🦴 DEBUG: CYAN=ritual sites (wolves), GREEN=chunk scattered, RED=game_world (NO wolves)")

func _set_bone_highlight(sprite: Sprite2D, enabled: bool, color: Color) -> void:
	"""Helper to set/restore bone highlight color"""
	var key = str(sprite.get_instance_id())
	if enabled:
		if not _bone_original_modulates.has(key):
			_bone_original_modulates[key] = sprite.modulate
		sprite.modulate = color
	else:
		if _bone_original_modulates.has(key):
			sprite.modulate = _bone_original_modulates[key]
