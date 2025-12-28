# game_world.gd - Optimized runtime generation (no baking needed!)
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
const ChunkBasedPropSystem = preload("res://scripts/systems/ChunkBasedPropSystem.gd")
# NetworkPlayer scene not needed - using regular player.tscn

# Multiplayer variables
var players = {}  # Dictionary of player_id: Player node
var local_player = null

func get_player_by_peer_id(peer_id: int) -> Node:
	"""Get player node by their peer ID. Returns null if not found."""
	return players.get(peer_id, null)

# Multiplayer-ready spawn manager
var spawn_manager = null  # SpawnManager (type hint removed for compatibility)

# Chunk-based prop system for dynamic loading
var chunk_prop_system: ChunkBasedPropSystem = null

# Cell-based streaming system for smoother chunk transitions (optional replacement)
var cell_streaming_manager: CellStreamingManager = null

const PROP_TEXTURES = {
	"dead_tree": "res://assets/environment/dreadland/dead_tree.png",
	"pine_tree": "res://assets/environment/dreadland/pine_tree.png",
	"autumn_tree": "res://assets/environment/dreadland/autumn_tree.png",
	# Rock spawning now handled by ChunkBasedPropSystem with zone-based textures
	# These are fallback paths for legacy code using zone1 rocks
	"rock_large": "res://assets/environment/dreadland/rocks/zone1/rock_large_1.png",
	"rock_medium": "res://assets/environment/dreadland/rocks/zone1/rock_medium_1.png",
	"rock_small": "res://assets/environment/dreadland/rocks/zone1/rock_small_1.png",
	"skull": "res://assets/environment/dreadland/skull.png",
	"bones": "res://assets/environment/dreadland/bones.png",
	"ground_crack_1": "res://assets/environment/dreadland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/dreadland/ground_crack_2.png",
	"broken_sword": "res://assets/environment/dreadland/broken_sword.png",
	"ash_pile": "res://assets/environment/dreadland/ash_pile.png"
}

# Tree scene files - collision positions can be edited visually in these scenes
const TREE_SCENES = {
	"dead_tree": "res://scenes/environment/DeadTree.tscn",
	"pine_tree": "res://scenes/environment/PineTree.tscn",
	"autumn_tree": "res://scenes/environment/AutumnTree.tscn"
}

const LAYER_TEMPLATE = [
	# Subtle palette for cleared/trafficked areas - closer to ground color (0.15)
	# Edge layers: Ultra-subtle, very large, massive overlap
	{"count": 80, "size_mult": [1.4, 1.9], "spread_mult": 1.2, "darkness": 0.14, "alpha": 0.003},
	{"count": 75, "size_mult": [1.3, 1.8], "spread_mult": 1.1, "darkness": 0.14, "alpha": 0.004},
	{"count": 70, "size_mult": [1.2, 1.7], "spread_mult": 1.0, "darkness": 0.13, "alpha": 0.006},
	{"count": 65, "size_mult": [1.1, 1.6], "spread_mult": 0.9, "darkness": 0.13, "alpha": 0.008},
	# Mid layers: Gradual transition
	{"count": 55, "size_mult": [1.0, 1.45], "spread_mult": 0.75, "darkness": 0.12, "alpha": 0.012},
	{"count": 50, "size_mult": [0.85, 1.25], "spread_mult": 0.65, "darkness": 0.12, "alpha": 0.016},
	{"count": 45, "size_mult": [0.7, 1.05], "spread_mult": 0.55, "darkness": 0.11, "alpha": 0.020},
	{"count": 40, "size_mult": [0.6, 0.9], "spread_mult": 0.45, "darkness": 0.11, "alpha": 0.025},
	# Core layers: Slightly darker center (compacted earth)
	{"count": 32, "size_mult": [0.475, 0.725], "spread_mult": 0.35, "darkness": 0.10, "alpha": 0.030},
	{"count": 25, "size_mult": [0.375, 0.575], "spread_mult": 0.25, "darkness": 0.10, "alpha": 0.035},
	{"count": 20, "size_mult": [0.275, 0.45], "spread_mult": 0.15, "darkness": 0.09, "alpha": 0.040},
	{"count": 16, "size_mult": [0.2, 0.35], "spread_mult": 0.05, "darkness": 0.09, "alpha": 0.045}
]

# World dimensions - derived from Constants
var WORLD_WIDTH: float:
	get: return Constants.CHUNK_SIZE * 3  # 3 chunks
var WORLD_HEIGHT: float:
	get: return Constants.CHUNK_SIZE  # 1 chunk tall
# World layout constants - derived from Constants for chunk size
# West→East progression: Campfire at west, Zone 2 tunnel at east
var CAMPFIRE_POS: Vector2:
	get: return Vector2(-6000, 0)  # West side of chunk -1 (player start area)
var WORLD_MIN_X: float:
	get: return -Constants.CHUNK_SIZE
var WORLD_MAX_X: float:
	get: return Constants.CHUNK_SIZE * 2
var WORLD_MIN_Y: float:
	get: return -Constants.CHUNK_SIZE / 2
var WORLD_MAX_Y: float:
	get: return Constants.CHUNK_SIZE / 2

# Ruins configuration - procedurally generated at runtime
const RUINS_PER_END_CHUNK: int = 2  # 2 ruins per end chunk (-1 and +1)
const RUINS_MIN_DISTANCE_FROM_EDGE: float = 600.0  # Keep away from world edges
const RUINS_MIN_DISTANCE_BETWEEN: float = 1500.0  # Minimum spacing between ruins
const RUINS_PATH_OFFSET_MIN: float = 2500.0  # Minimum Y distance from path (pushed to edges)
const RUINS_PATH_OFFSET_MAX: float = 3500.0  # Maximum Y distance from path (near world edge)

# Placement patterns for ruins in each chunk
enum RuinsPattern {
	BOTH_NORTH,  # Both ruins north of path (Y < 0)
	BOTH_SOUTH,  # Both ruins south of path (Y > 0)
	SPLIT        # One north, one south
}

# Generated ruins positions (populated at runtime)
var RUINS_POSITIONS: Dictionary = {}
var ruins_nodes: Array = []  # Track spawned ruins for cleanup

# POI Manager - handles quadrant-based POI generation for edge chunks
var poi_manager: POIManager = null

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", "dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10"]
var screenshot_mode = false

# ═══════════════════════════════════════════════════════════════════════════════
# DEBUG TOGGLES - Disable these one by one to find freeze cause
# Set to false to disable each system. Test after each change.
# ═══════════════════════════════════════════════════════════════════════════════
const DEBUG_DISABLE_CELL_STREAMING = false  # Disable new cell-based prop streaming
const DEBUG_DISABLE_POI_PRESPAWN = false    # Disable POI pre-spawning at startup
const DEBUG_DISABLE_GROUND_SHADER = false   # Disable ground variation shader
const DEBUG_DISABLE_COMBAT_JUICE = false    # Disable hit stop/slow-mo effects
const DEBUG_DISABLE_CAMP_SPAWNER = false    # Disable enemy camp spawning system
var tree_positions = []  # Track tree positions to avoid spawning small rocks on them
var lava_pool_positions = []  # Track lava pool positions to avoid spawning props on them

# Viewport culling for terrain
var terrain_spots = []  # Store all terrain spot data {pos, size, type, elongation, darkness}
var active_terrain_nodes = {}  # Track which spots are currently rendered {spot_index: Node2D}
var viewport_buffer = 1200.0  # Render terrain this far beyond viewport edges (increased from 800)
var terrain_check_timer = 0.0
const TERRAIN_CHECK_INTERVAL = 1.0  # Check every 1s (was 0.3s - less frequent for better performance)

# Player position sync (multiplayer)
var player_sync_timer = 0.0
const PLAYER_SYNC_INTERVAL = 0.05  # 20Hz - 50ms between syncs

# Lava light time-based updates
var lava_light_timer = 0.0
const LAVA_LIGHT_UPDATE_INTERVAL = 0.1  # Update 10 times per second

func _ready():
	# Add to group so LootSpawnManager can find us on clients
	add_to_group("game_world")

	# Initialize multiplayer
	_setup_multiplayer()

	# Restore UI autoloads that were hidden when returning to main menu
	_restore_ui_autoloads()

	# Connect TimeManager to CanvasModulate for day/night cycle
	var canvas_modulate = $CanvasModulate
	if canvas_modulate and TimeManager:
		TimeManager.set_canvas_modulate(canvas_modulate)

	# Add performance profiler (press F3 to toggle)
	var profiler_scene = load("res://scenes/ui/performance_profiler.tscn")
	if profiler_scene:
		var profiler = profiler_scene.instantiate()
		add_child(profiler)

	# Initialize chunk-based prop system
	chunk_prop_system = ChunkBasedPropSystem.new()
	add_child(chunk_prop_system)
	chunk_prop_system.initialize(self)

	# Initialize cell streaming system if enabled (smoother chunk transitions)
	if ChunkBasedPropSystem.USE_CELL_STREAMING and not DEBUG_DISABLE_CELL_STREAMING:
		cell_streaming_manager = CellStreamingManager.new()
		add_child(cell_streaming_manager)
		cell_streaming_manager.initialize(self, 12345)  # World seed for deterministic generation
		cell_streaming_manager.set_chunk_prop_system(chunk_prop_system)  # Pass chunk system for prop creation
		chunk_prop_system.cell_streaming_manager = cell_streaming_manager
		print("🔲 Cell-based streaming enabled for smooth chunk transitions")
	elif DEBUG_DISABLE_CELL_STREAMING:
		print("⚠️ DEBUG: Cell streaming DISABLED for freeze debugging")

	# Create world boundaries first
	create_world_boundaries()

	# Generate procedural ruins positions and spawn them
	generate_procedural_ruins()

	# TERRAIN GENERATION - Now optimized with campfire exclusion zone
	var enable_terrain = true  # Excludes 1500px radius around spawn for performance
	if enable_terrain:
		# Generate terrain spot data (doesn't create ColorRects yet)
		await generate_optimized_world_layers()

	# Generate dynamic elements (trees, enemies, props)
	generate_dynamic_elements()

	# Spawn tunnel entrances at north edge of each chunk
	spawn_tunnel_entrances()

	# Set camera limits
	setup_camera_limits()

	# Setup corpse loot handling
	setup_corpse_loot_system()

	# Wait for player to be ready, then do initial terrain visibility update
	await get_tree().process_frame
	await get_tree().process_frame
	update_terrain_visibility()

	Constants.log_spawning("✅ GameWorld ready!")

func _process(delta):
	"""Handle viewport culling for terrain and player sync"""
	# Update terrain visibility
	terrain_check_timer += delta
	if terrain_check_timer >= TERRAIN_CHECK_INTERVAL:
		terrain_check_timer = 0.0
		update_terrain_visibility()

	# Update ambient particles position to follow player
	var particles = get_node_or_null("AmbientAsh")
	if particles:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player):
			particles.global_position = player.global_position

	# Sync local player position to other clients (multiplayer)
	if multiplayer.has_multiplayer_peer():
		player_sync_timer += delta
		if player_sync_timer >= PLAYER_SYNC_INTERVAL:
			player_sync_timer = 0.0
			_sync_local_player_position()

	# Update lava lights based on time of day
	lava_light_timer += delta
	if lava_light_timer >= LAVA_LIGHT_UPDATE_INTERVAL:
		lava_light_timer = 0.0
		_update_lava_lights()

func _update_lava_lights():
	"""Scale lava pool lights based on time of day - bright at night, subtle during day"""
	# Get time brightness from TimeManager
	var time_brightness = 1.0
	if TimeManager and TimeManager.canvas_modulate:
		time_brightness = TimeManager.get_brightness()

	# Calculate day factor (0 = night, 1 = day)
	# Night brightness ~0.51, day brightness ~0.99
	var day_factor = inverse_lerp(0.51, 0.99, time_brightness)
	day_factor = clamp(day_factor, 0.0, 1.0)

	# Lava should glow bright at night (2.5x), subtle during day (0.8x)
	var time_multiplier = lerp(2.5, 0.8, day_factor)
	var scale_multiplier = lerp(1.8, 1.0, day_factor)

	# Update all lava lights in the group
	for light in get_tree().get_nodes_in_group("lava_lights"):
		if not is_instance_valid(light):
			continue
		if not light is PointLight2D:
			continue

		var base_energy = light.get_meta("base_energy", 1.5)
		var base_scale = light.get_meta("base_scale", 2.0)

		# Add subtle flickering
		var time = Time.get_ticks_msec() / 1000.0
		var flicker = sin(time * 3.0 + light.get_instance_id() * 0.1) * 0.15

		light.energy = base_energy * time_multiplier * (1.0 + flicker)
		light.texture_scale = base_scale * scale_multiplier

func create_world_boundaries():
	"""Create invisible walls and fog edges around world boundaries"""
	# World bounds: X: -4000 to 8000, Y: -2000 to 2000
	var world_left = Constants.WORLD_LEFT
	var world_right = Constants.WORLD_RIGHT
	var world_top = Constants.WORLD_TOP
	var world_bottom = Constants.WORLD_BOTTOM
	var world_width = Constants.WORLD_WIDTH
	var world_height = Constants.WORLD_HEIGHT
	var world_center_x = (world_left + world_right) / 2.0
	var boundary_thickness = Constants.WORLD_BOUNDARY_THICKNESS

	# Top wall (north)
	var top_wall = StaticBody2D.new()
	top_wall.name = "TopBoundary"
	var top_shape = CollisionShape2D.new()
	var top_rect = RectangleShape2D.new()
	top_rect.size = Vector2(world_width + boundary_thickness * 2, boundary_thickness)
	top_shape.shape = top_rect
	top_shape.position = Vector2(world_center_x, world_top - boundary_thickness/2)
	top_wall.add_child(top_shape)
	add_child(top_wall)

	# Bottom wall (south)
	var bottom_wall = StaticBody2D.new()
	bottom_wall.name = "BottomBoundary"
	var bottom_shape = CollisionShape2D.new()
	var bottom_rect = RectangleShape2D.new()
	bottom_rect.size = Vector2(world_width + boundary_thickness * 2, boundary_thickness)
	bottom_shape.shape = bottom_rect
	bottom_shape.position = Vector2(world_center_x, world_bottom + boundary_thickness/2)
	bottom_wall.add_child(bottom_shape)
	add_child(bottom_wall)

	# Left wall (west)
	var left_wall = StaticBody2D.new()
	left_wall.name = "LeftBoundary"
	var left_shape = CollisionShape2D.new()
	var left_rect = RectangleShape2D.new()
	left_rect.size = Vector2(boundary_thickness, world_height)
	left_shape.shape = left_rect
	left_shape.position = Vector2(world_left - boundary_thickness/2, 0)
	left_wall.add_child(left_shape)
	add_child(left_wall)

	# Right wall (east)
	var right_wall = StaticBody2D.new()
	right_wall.name = "RightBoundary"
	var right_shape = CollisionShape2D.new()
	var right_rect = RectangleShape2D.new()
	right_rect.size = Vector2(boundary_thickness, world_height)
	right_shape.shape = right_rect
	right_shape.position = Vector2(world_right + boundary_thickness/2, 0)
	right_wall.add_child(right_shape)
	add_child(right_wall)

	# Create fog/shadow edges on north and south borders
	create_border_fog(world_left, world_right, world_top, world_bottom)

func create_border_fog(world_left: float, world_right: float, world_top: float, world_bottom: float):
	"""Create gradient fog at north and south world edges"""
	var fog_container = Node2D.new()
	fog_container.name = "BorderFog"
	fog_container.z_index = 100  # Above most things but below UI
	add_child(fog_container)

	var fog_height = 400.0  # Height of fog gradient
	var world_width = world_right - world_left

	# North fog (top edge) - fades from dark at edge to transparent
	var north_fog = ColorRect.new()
	north_fog.name = "NorthFog"
	north_fog.size = Vector2(world_width + 2000, fog_height)
	north_fog.position = Vector2(world_left - 1000, world_top - fog_height)
	north_fog.color = Color(0, 0, 0, 1)
	north_fog.z_index = 100

	# Shader for gradient fade
	var north_shader = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	// Fade from opaque at top to transparent at bottom
	float fade = 1.0 - UV.y;
	fade = smoothstep(0.0, 1.0, fade);
	COLOR.a = fade * 0.9;
}
"""
	north_shader.shader = shader
	north_fog.material = north_shader
	fog_container.add_child(north_fog)

	# South fog (bottom edge) - fades from transparent at top to dark at bottom
	var south_fog = ColorRect.new()
	south_fog.name = "SouthFog"
	south_fog.size = Vector2(world_width + 2000, fog_height)
	south_fog.position = Vector2(world_left - 1000, world_bottom)
	south_fog.color = Color(0, 0, 0, 1)
	south_fog.z_index = 100

	var south_shader = ShaderMaterial.new()
	var south_shader_code = Shader.new()
	south_shader_code.code = """
shader_type canvas_item;

void fragment() {
	// Fade from transparent at top to opaque at bottom
	float fade = UV.y;
	fade = smoothstep(0.0, 1.0, fade);
	COLOR.a = fade * 0.9;
}
"""
	south_shader.shader = south_shader_code
	south_fog.material = south_shader
	fog_container.add_child(south_fog)

	print("🌫️ Border fog created on north and south edges")

# ============================================
# TUNNEL ENTRANCE SYSTEM
# ============================================

const TUNNEL_ENTRANCE_SCENE = preload("res://scenes/trading_hub/TunnelEntrance.tscn")
var tunnel_entrances: Array = []

func spawn_tunnel_entrances():
	"""Spawn tunnel entrances at the north edge of each chunk"""
	# Clear existing entrances
	for entrance in tunnel_entrances:
		if is_instance_valid(entrance):
			entrance.queue_free()
	tunnel_entrances.clear()

	# Zone 2 tunnel only at east end (chunk +1) - West→East progression
	var chunk_ids = [1]

	for chunk_id in chunk_ids:
		var entrance = TUNNEL_ENTRANCE_SCENE.instantiate()

		# Position at center of chunk's X range, at north edge
		var chunk_center_x = chunk_id * Constants.CHUNK_SIZE + Constants.CHUNK_SIZE / 2
		var north_edge_y = -Constants.CHUNK_SIZE / 2 + 50  # Just inside north boundary

		entrance.position = Vector2(chunk_center_x, north_edge_y)
		entrance.setup(chunk_id)

		add_child(entrance)
		tunnel_entrances.append(entrance)

		print("🚪 Tunnel entrance spawned for chunk %d at (%d, %d)" % [chunk_id, chunk_center_x, north_edge_y])

	print("✅ Spawned %d tunnel entrances" % tunnel_entrances.size())

func generate_procedural_ruins():
	"""Generate POI positions using POIManager (ruins, settlements, etc.)"""
	# Clear any existing ruins data
	RUINS_POSITIONS.clear()
	for ruins in ruins_nodes:
		if is_instance_valid(ruins):
			ruins.queue_free()
	ruins_nodes.clear()

	# Initialize POI Manager
	poi_manager = POIManager.new()
	poi_manager.name = "POIManager"
	add_child(poi_manager)
	poi_manager.initialize(self)

	# Convert POI ruins data to RUINS_POSITIONS for backward compatibility
	# West→East progression: guardians scale with position
	# West chunk (-1): Level 3-5 guardians (newbie friendly)
	# East chunk (+1): Level 7-10 guardians (group recommended)
	var guardian_levels = [4, 5, 8, 10]  # Increasing difficulty West→East
	var level_index = 0

	var ruins_pois = poi_manager.get_ruins()
	for poi in ruins_pois:
		var chunk_prefix = "west" if poi.chunk_id == -1 else "east"
		var ruins_key = "%s_%d" % [chunk_prefix, level_index % 2]

		RUINS_POSITIONS[ruins_key] = {
			"position": poi.position,
			"chunk_id": poi.chunk_id,
			"guardian_level": guardian_levels[min(level_index, guardian_levels.size() - 1)],
			"spawned": false
		}
		level_index += 1

	print("🏛️ POI System: Generated %d ruins positions (will spawn per-chunk)" % RUINS_POSITIONS.size())

	# Pre-spawn ALL POIs immediately (for debug verification)
	# This must be AFTER RUINS_POSITIONS is populated
	if not DEBUG_DISABLE_POI_PRESPAWN:
		pre_spawn_all_pois()
	else:
		print("⚠️ DEBUG: POI pre-spawning DISABLED for freeze debugging")

func spawn_ruins_for_chunk(chunk_id: int) -> void:
	"""Spawn ruins that belong to a specific chunk"""
	# Use new pool-based spawn point instead of old ruins campfire
	var ruins_scene = load("res://scenes/world/ruins_spawn_point.tscn")
	if not ruins_scene:
		# Fallback to old scene if new one doesn't exist
		ruins_scene = load("res://scenes/world/ruins_campfire.tscn")
	if not ruins_scene:
		push_error("Could not load ruins scene!")
		return

	for ruins_key in RUINS_POSITIONS.keys():
		var ruins_data = RUINS_POSITIONS[ruins_key]

		# Skip if not in this chunk or already spawned
		if ruins_data.chunk_id != chunk_id or ruins_data.spawned:
			continue

		var pos = ruins_data.position
		var guardian_level = ruins_data.guardian_level

		# Create ruins instance
		var ruins = ruins_scene.instantiate()
		ruins.name = "ProceduralRuins_%s" % ruins_key
		ruins.position = pos

		# Set guardian level (works for both old and new system)
		if "guardian_level" in ruins:
			ruins.guardian_level = guardian_level

		add_child(ruins)
		ruins_nodes.append(ruins)
		ruins_data.spawned = true

		print("Spawned ruins '%s' at %s (level %d) for chunk %d" % [ruins_key, pos, guardian_level, chunk_id])

func despawn_ruins_for_chunk(chunk_id: int) -> void:
	"""Despawn ruins that belong to a specific chunk"""
	var to_remove = []

	for ruins in ruins_nodes:
		if not is_instance_valid(ruins):
			to_remove.append(ruins)
			continue

		# Find which ruins_key this is
		for ruins_key in RUINS_POSITIONS.keys():
			var ruins_data = RUINS_POSITIONS[ruins_key]
			if ruins_data.chunk_id == chunk_id and ruins_data.spawned:
				if ruins.name == "ProceduralRuins_%s" % ruins_key:
					print("🗑️ Despawning ruins '%s' for chunk %d" % [ruins_key, chunk_id])
					ruins.queue_free()
					to_remove.append(ruins)
					ruins_data.spawned = false
					break

	for ruins in to_remove:
		ruins_nodes.erase(ruins)


# ═══════════════════════════════════════════════════════════════════════════════
# POI SPAWNING - Seed Plots, Monster Dens, Resource Nodes, etc.
# ═══════════════════════════════════════════════════════════════════════════════

var seed_plot_nodes: Array = []  # Track spawned seed plots (World Tree locations)
var world_tree_nodes: Array = []  # Track spawned World Trees
const SEED_PLOT_SCENE = preload("res://scenes/world/SeedPlot.tscn")
const WORLD_TREE_SCENE = preload("res://scenes/world/WorldTree.tscn")

func pre_spawn_all_pois() -> void:
	"""Pre-spawn ALL POIs at startup for debug verification"""
	if not poi_manager:
		print("⚠️ POI Manager not available for pre-spawn")
		return

	print("🗺️ Pre-spawning ALL POIs for debug verification...")
	var total_spawned = 0

	# Get all chunk IDs that have POI data
	for chunk_id in poi_manager.poi_data.keys():
		var pois = poi_manager.get_pois_for_chunk(chunk_id)
		print("  Chunk %d: %d POIs" % [chunk_id, pois.size()])

		for poi in pois:
			if poi.spawned:
				continue

			print("    → Spawning %s at %s" % [poi.type, poi.position])
			match poi.type:
				"seed_plot":
					spawn_seed_plot(poi)
				"monster_lava_lake":
					spawn_monster_lava_lake(poi)
				"resource_node":
					spawn_resource_node(poi)
				"monster_den":
					spawn_monster_den(poi)
				"ancient_shrine":
					spawn_ancient_shrine(poi)
				"ruins":
					# Spawn ruins directly here
					pass  # Will be handled below
				_:
					print("    ⚠️ Unknown POI type: %s" % poi.type)

			total_spawned += 1

	# Also spawn all ruins from RUINS_POSITIONS
	print("  Pre-spawning %d ruins..." % RUINS_POSITIONS.size())
	var ruins_scene = load("res://scenes/world/ruins_spawn_point.tscn")
	if not ruins_scene:
		ruins_scene = load("res://scenes/world/ruins_campfire.tscn")

	if ruins_scene:
		for ruins_key in RUINS_POSITIONS.keys():
			var ruins_data = RUINS_POSITIONS[ruins_key]
			if ruins_data.spawned:
				continue

			var pos = ruins_data.position
			var guardian_level = ruins_data.guardian_level
			var chunk_id = ruins_data.chunk_id

			var ruins = ruins_scene.instantiate()
			ruins.name = "ProceduralRuins_%s" % ruins_key
			ruins.position = pos

			if "guardian_level" in ruins:
				ruins.guardian_level = guardian_level

			add_child(ruins)
			ruins_nodes.append(ruins)
			ruins_data.spawned = true

			print("    🏛️ Spawned ruins '%s' at %s (level %d, chunk %d)" % [ruins_key, pos, guardian_level, chunk_id])
			total_spawned += 1
	else:
		print("    ⚠️ Could not load ruins scene!")

	print("✅ Pre-spawned %d POIs across all chunks" % total_spawned)


func spawn_pois_for_chunk(chunk_id: int) -> void:
	"""Spawn all POI types for a chunk (seed plots, monster dens, etc.)"""
	if not poi_manager:
		print("⚠️ POI Manager not available for chunk %d" % chunk_id)
		return

	var pois = poi_manager.get_pois_for_chunk(chunk_id)
	print("🗺️ Spawning %d POIs for chunk %d" % [pois.size(), chunk_id])

	for poi in pois:
		if poi.spawned:
			continue

		print("  → POI type '%s' at %s" % [poi.type, poi.position])
		match poi.type:
			"seed_plot":
				spawn_seed_plot(poi)
			"monster_lava_lake":
				spawn_monster_lava_lake(poi)
			"resource_node":
				spawn_resource_node(poi)
			"monster_den":
				spawn_monster_den(poi)
			"ancient_shrine":
				spawn_ancient_shrine(poi)
			"ruins":
				# Ruins handled by spawn_ruins_for_chunk, just mark as noted
				print("    (ruins spawned via separate system)")
			_:
				print("    ⚠️ Unknown POI type: %s" % poi.type)


func spawn_seed_plot(poi: Dictionary) -> void:
	"""Spawn a SeedPlot scene (World Tree planting location)"""
	# Check if already claimed by a World Tree
	if WorldTreeManager and WorldTreeManager.get_tree_in_chunk(poi.chunk_id):
		poi.spawned = true
		print("🌳 Skipping seed plot at %s - chunk already has World Tree" % poi.position)
		return

	var seed_plot = SEED_PLOT_SCENE.instantiate()
	seed_plot.name = "SeedPlot_%d_%d" % [poi.chunk_id, poi.quadrant]
	seed_plot.position = poi.position
	seed_plot.set_chunk_id(poi.chunk_id)

	# Connect the plot_claimed signal to handle World Tree spawning
	seed_plot.plot_claimed.connect(_on_seed_plot_claimed.bind(poi))

	add_child(seed_plot)
	seed_plot_nodes.append(seed_plot)
	poi.spawned = true

	print("🌱 Spawned seed plot at %s (chunk %d)" % [poi.position, poi.chunk_id])


func _on_seed_plot_claimed(tree_data: WorldTreeData, poi: Dictionary) -> void:
	"""Handle when a seed plot is claimed and World Tree is planted"""
	poi.claimed = true
	print("🌳 Seed plot claimed! World Tree planted for guild: %s" % tree_data.guild_name)

	# Spawn the World Tree at this location
	spawn_world_tree(tree_data, poi.position)


func spawn_world_tree(tree_data: WorldTreeData, at_position: Vector2) -> void:
	"""Spawn a World Tree at the given position"""
	var world_tree = WORLD_TREE_SCENE.instantiate()
	world_tree.name = "WorldTree_%s" % tree_data.tree_id
	world_tree.position = at_position

	# Initialize with tree data
	if world_tree.has_method("initialize"):
		world_tree.initialize(tree_data)

	add_child(world_tree)
	world_tree_nodes.append(world_tree)

	print("🌳 Spawned World Tree for guild '%s' at %s" % [tree_data.guild_name, at_position])


const CLEANSEABLE_LAVA_POOL_SCENE = preload("res://scenes/world/CleanseableLavaPool.tscn")
var cleanseable_pool_nodes: Array = []

func spawn_monster_lava_lake(poi: Dictionary) -> void:
	"""Spawn a large monster-inhabited lava lake with surrounding pools"""
	var base_seed = hash(poi.position)
	var layout_rng = RandomNumberGenerator.new()
	layout_rng.seed = base_seed

	# Register the main POI position as a lava pool for enemy clustering
	if cell_streaming_manager:
		cell_streaming_manager.register_lava_pool(poi.position)

	# Create a container for the lava lake
	var lake_container = Node2D.new()
	lake_container.name = "LavaLake_%d" % poi.chunk_id
	lake_container.position = Vector2.ZERO
	add_child(lake_container)

	if chunk_prop_system and chunk_prop_system.has_method("create_lava_pool"):
		# Track pool positions to prevent overlap
		var pool_positions: Array = []  # [{pos: Vector2, radius: float}]
		var pool_index = 0

		# Helper to get unique RNG for each pool
		var get_pool_rng = func(idx: int) -> RandomNumberGenerator:
			var pool_rng = RandomNumberGenerator.new()
			pool_rng.seed = base_seed + idx * 12345
			return pool_rng

		# 1. Create the LARGE central monster pool (250-400px like original)
		var monster_size = layout_rng.randf_range(280, 380)
		chunk_prop_system.create_lava_pool(poi.position, lake_container, get_pool_rng.call(pool_index), monster_size)
		pool_positions.append({"pos": poi.position, "radius": monster_size / 2})
		pool_index += 1

		# 2. Create 3-5 satellite pools around the main pool
		var satellite_count = layout_rng.randi_range(3, 5)
		var satellites_spawned = 0
		for attempt in range(satellite_count * 3):
			if satellites_spawned >= satellite_count:
				break

			# Distribute satellites evenly around with some randomness
			var base_angle = (float(satellites_spawned) / satellite_count) * TAU
			var angle = base_angle + layout_rng.randf_range(-0.25, 0.25)
			# Distance from center: well outside monster pool edge
			var dist = (monster_size / 2) + layout_rng.randf_range(80, 250)
			var satellite_pos = poi.position + Vector2(cos(angle), sin(angle)) * dist

			# Mix of medium and small pools
			var satellite_size: float
			if layout_rng.randf() < 0.35:
				satellite_size = layout_rng.randf_range(90, 150)
			else:
				satellite_size = layout_rng.randf_range(50, 90)

			# Check for overlap with existing pools (generous spacing)
			var too_close = false
			for existing in pool_positions:
				var min_dist = existing.radius + (satellite_size / 2) + 40  # 40px gap minimum
				if satellite_pos.distance_to(existing.pos) < min_dist:
					too_close = true
					break

			if not too_close:
				chunk_prop_system.create_lava_pool(satellite_pos, lake_container, get_pool_rng.call(pool_index), satellite_size)
				pool_positions.append({"pos": satellite_pos, "radius": satellite_size / 2})
				pool_index += 1
				satellites_spawned += 1

		# 3. Add a couple tiny "blister" pools scattered further out
		var blister_count = layout_rng.randi_range(2, 4)
		for i in range(blister_count):
			var angle = layout_rng.randf() * TAU
			var dist = layout_rng.randf_range(300, 450)
			var blister_pos = poi.position + Vector2(cos(angle), sin(angle)) * dist
			var blister_size = layout_rng.randf_range(30, 50)

			var ok = true
			for existing in pool_positions:
				if blister_pos.distance_to(existing.pos) < existing.radius + 50:  # 50px gap for blisters
					ok = false
					break
			if ok:
				chunk_prop_system.create_lava_pool(blister_pos, lake_container, get_pool_rng.call(pool_index), blister_size)
				pool_index += 1

	# NOTE: Cleanseable pools disabled - they have their own circular visual
	# that conflicts with the elaborate polygon lava pools above.
	# If needed later, place cleanseable pools deliberately, not overlapping visual pools.

	poi.spawned = true
	print("🌋 Spawned monster lava lake at %s" % poi.position)


func spawn_resource_node(poi: Dictionary) -> void:
	"""Spawn a dense resource gathering area"""
	# TODO: Implement dense tree/rock cluster
	poi.spawned = true
	print("⛏️ [PLACEHOLDER] Resource node at %s" % poi.position)


func spawn_monster_den(poi: Dictionary) -> void:
	"""Spawn an elite monster encampment"""
	# TODO: Implement monster den with elite enemies
	poi.spawned = true
	print("👹 [PLACEHOLDER] Monster den at %s" % poi.position)


func spawn_ancient_shrine(poi: Dictionary) -> void:
	"""Spawn a buff altar / lore location"""
	# TODO: Implement shrine with interaction
	poi.spawned = true
	print("⛩️ [PLACEHOLDER] Ancient shrine at %s" % poi.position)


func despawn_pois_for_chunk(chunk_id: int) -> void:
	"""Despawn all POIs for a chunk"""
	if not poi_manager:
		return

	var to_remove = []
	for node in seed_plot_nodes:
		if not is_instance_valid(node):
			to_remove.append(node)
			continue

		# Check if this POI belongs to the chunk being unloaded
		var pois = poi_manager.get_pois_for_chunk(chunk_id)
		for poi in pois:
			if poi.spawned and node.position.distance_to(poi.position) < 50:
				node.queue_free()
				to_remove.append(node)
				poi.spawned = false
				break

	for node in to_remove:
		seed_plot_nodes.erase(node)


func generate_ruins_positions_for_chunk(x_min: float, x_max: float, pattern: int, rng: RandomNumberGenerator) -> Array:
	"""Generate 2 ruins positions within a chunk based on placement pattern"""
	var positions = []
	var y_range_north = Vector2(-RUINS_PATH_OFFSET_MAX, -RUINS_PATH_OFFSET_MIN)  # North of path
	var y_range_south = Vector2(RUINS_PATH_OFFSET_MIN, RUINS_PATH_OFFSET_MAX)   # South of path

	# Determine Y ranges for each ruins based on pattern
	var y_ranges = []
	match pattern:
		0:  # BOTH_NORTH
			y_ranges = [y_range_north, y_range_north]
		1:  # BOTH_SOUTH
			y_ranges = [y_range_south, y_range_south]
		2:  # SPLIT
			y_ranges = [y_range_north, y_range_south]

	# Generate first ruins position
	var x1 = rng.randf_range(x_min, x_min + (x_max - x_min) * 0.4)  # Left side of chunk
	var y1 = rng.randf_range(y_ranges[0].x, y_ranges[0].y)
	positions.append(Vector2(x1, y1))

	# Generate second ruins position (ensure minimum distance)
	var attempts = 0
	while attempts < 50:
		var x2 = rng.randf_range(x_min + (x_max - x_min) * 0.5, x_max)  # Right side of chunk
		var y2 = rng.randf_range(y_ranges[1].x, y_ranges[1].y)
		var pos2 = Vector2(x2, y2)

		# Check distance from first ruins
		if pos2.distance_to(positions[0]) >= RUINS_MIN_DISTANCE_BETWEEN:
			positions.append(pos2)
			break
		attempts += 1

	# Fallback if we couldn't find valid position
	if positions.size() < 2:
		var x2 = rng.randf_range(x_min + (x_max - x_min) * 0.6, x_max)
		var y2 = -y_ranges[1].y if y_ranges[1].y > 0 else y_ranges[1].y  # Flip to opposite side
		positions.append(Vector2(x2, y2))

	return positions

func setup_camera_limits():
	"""Set camera limits to prevent seeing outside world boundaries"""
	await get_tree().process_frame

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var camera = player.get_node_or_null("Camera2D")
	if not camera:
		return

	camera.limit_left = Constants.WORLD_LEFT
	camera.limit_right = Constants.WORLD_RIGHT
	camera.limit_top = Constants.WORLD_TOP
	camera.limit_bottom = Constants.WORLD_BOTTOM

func generate_optimized_world_layers():
	"""Use existing Ground node from scene - don't override colors set in tscn"""
	# Ground color is now set in game_world.tscn - no runtime override needed

	# Trafficked areas now handled by path system (Line2D paths + clearings)
	# create_trafficked_areas()  # Disabled - no longer needed

	# Create path from campfire following torches eastward
	create_path_system()

func create_trafficked_areas():
	"""Add dark disturbed earth patches around ruins (heavily trafficked)
	   Note: Campfire area is handled by spawn_path_for_chunk() in chunk 0"""
	var traffic_layer = Node2D.new()
	traffic_layer.name = "TraffickedAreas"
	traffic_layer.z_index = -9
	add_child(traffic_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	# Campfire area is now handled by spawn_path_for_chunk() with create_campfire_circle()
	# This prevents double-layering and ensures consistent appearance with the path

	# Create traffic circles around all procedurally generated ruins
	for ruins_key in RUINS_POSITIONS:
		var ruins_data = RUINS_POSITIONS[ruins_key]
		var ruins_pos = ruins_data.position if ruins_data is Dictionary else ruins_data
		create_traffic_circle(traffic_layer, ruins_pos, 400, 24, rng)

func create_traffic_circle(parent: Node2D, center: Vector2, radius: float, num_spots: int, rng: RandomNumberGenerator):
	"""Create scattered dark spots in a circular area"""
	for i in range(num_spots):
		# Random position within radius
		var angle = rng.randf() * TAU
		var dist = rng.randf_range(0, radius)
		var pos = center + Vector2(cos(angle), sin(angle)) * dist

		# Random spot size
		var spot_size = rng.randf_range(120, 250)

		# Create 2-layer spot for performance (not 3)
		var layers = [
			{"size_mult": 1.3, "alpha": 0.04},
			{"size_mult": 0.8, "alpha": 0.06}
		]

		for layer in layers:
			var patch = ColorRect.new()
			var size = spot_size * layer.size_mult * rng.randf_range(0.9, 1.1)
			patch.size = Vector2(size, size)
			patch.position = pos - patch.size / 2
			# Very subtle trafficked areas - nearly invisible blending
			patch.color = Color(0.13, 0.13, 0.14, layer.alpha)
			patch.rotation = rng.randf() * TAU
			parent.add_child(patch)

func create_path_system():
	"""Initialize path system container. Actual paths are spawned per-chunk."""
	# Create main path container (paths will be added as children when chunks load)
	var path_layer = get_node_or_null("PathSystem")
	if not path_layer:
		path_layer = Node2D.new()
		path_layer.name = "PathSystem"
		path_layer.z_index = -8
		add_child(path_layer)

	print("🛤️ Path system container initialized (paths spawn per-chunk)")

# Store generated path points for reuse (torch placement, etc.)
var chunk_path_points: Dictionary = {}  # {chunk_id: Array of points}

func spawn_path_for_chunk(chunk_id: int) -> void:
	"""Spawn path segment and torches for a specific chunk"""
	var path_layer = get_node_or_null("PathSystem")
	if not path_layer:
		path_layer = Node2D.new()
		path_layer.name = "PathSystem"
		path_layer.z_index = -8
		add_child(path_layer)

	# Check if path already exists for this chunk
	var chunk_path_name = "PathChunk_%d" % chunk_id
	if path_layer.get_node_or_null(chunk_path_name):
		return  # Already loaded

	var rng = RandomNumberGenerator.new()
	rng.seed = 77777 + chunk_id  # Different but deterministic seed per chunk

	# Create path container for this chunk
	var chunk_path = Node2D.new()
	chunk_path.name = chunk_path_name
	path_layer.add_child(chunk_path)

	# Calculate chunk boundaries
	var cs = Constants.CHUNK_SIZE
	var chunk_start_x = chunk_id * cs
	var chunk_end_x = (chunk_id + 1) * cs

	# Clamp to world boundaries
	chunk_start_x = clamp(chunk_start_x, -cs, cs * 2)
	chunk_end_x = clamp(chunk_end_x, -cs, cs * 2)

	# For chunk -1 (campfire chunk), split path around campfire clearing
	# Campfire is at X: -6000 in chunk -1 for West→East progression
	var main_path: Array = []
	var clearing_radius = 400.0

	if chunk_id == -1:
		# Paths extend well into clearing so they blend naturally
		var overlap = 200.0

		# Left path: chunk start to inside clearing (clip to chunk boundary)
		var left_end = Vector2(CAMPFIRE_POS.x - clearing_radius + overlap, CAMPFIRE_POS.y)
		var left_path = create_zigzag_path(Vector2(chunk_start_x, 0), left_end, 8, 250, rng)
		draw_path_from_points(chunk_path, left_path, 260, rng, chunk_start_x, INF)

		# Right path: inside clearing to chunk end (clip to chunk boundary)
		var right_start = Vector2(CAMPFIRE_POS.x + clearing_radius - overlap, CAMPFIRE_POS.y)
		var right_path = create_zigzag_path(right_start, Vector2(chunk_end_x, 0), 8, 250, rng)
		draw_path_from_points(chunk_path, right_path, 260, rng, -INF, chunk_end_x)

		# Draw campfire clearing LAST (on top) to cover path ends cleanly
		create_campfire_circle(chunk_path, CAMPFIRE_POS, rng)

		# Combine for torch placement
		main_path = left_path + right_path
	else:
		# Other chunks: single continuous path with hard edges at chunk boundaries
		var path_start = Vector2(chunk_start_x, 0)
		var path_end = Vector2(chunk_end_x, 0)
		main_path = create_zigzag_path(path_start, path_end, 8, 250, rng)

		# Draw branch paths FIRST (so they render UNDER the main path)
		for ruins_key in RUINS_POSITIONS.keys():
			var ruins_data = RUINS_POSITIONS[ruins_key]
			if ruins_data.chunk_id != chunk_id:
				continue

			var ruins_pos = ruins_data.position
			# Branch point on main path - find where to connect
			var branch_x = clamp(ruins_pos.x + (400 if chunk_id < 0 else -400), chunk_start_x + 200, chunk_end_x - 200)
			var main_path_y = get_path_y_at_x(main_path, branch_x)

			# Start branch path OFFSET from main path to avoid overlap blob
			# Move start point 200px towards the ruins (in Y direction)
			var y_direction = sign(ruins_pos.y - main_path_y)
			var branch_start = Vector2(branch_x, main_path_y + y_direction * 200)

			var ruins_path = create_zigzag_path(branch_start, ruins_pos, 6, 200, rng)
			draw_path_from_points(chunk_path, ruins_path, 195, rng)  # Branch paths don't need clipping
			print("🛤️ Branch path to %s at %s" % [ruins_key, ruins_pos])

		# Draw main path LAST (on top of branch paths) - clip to chunk boundaries
		draw_path_from_points(chunk_path, main_path, 260, rng, chunk_start_x, chunk_end_x)

	# Store path points for torch/enemy systems
	chunk_path_points[chunk_id] = main_path

	# Spawn torches along this chunk's path
	spawn_torches_for_chunk(chunk_id, main_path, chunk_path)

	print("🛤️ Path spawned for chunk %d (X: %.0f to %.0f)" % [chunk_id, chunk_start_x, chunk_end_x])

func despawn_path_for_chunk(chunk_id: int) -> void:
	"""Despawn path segment and torches for a specific chunk"""
	var path_layer = get_node_or_null("PathSystem")
	if not path_layer:
		return

	var chunk_path_name = "PathChunk_%d" % chunk_id
	var chunk_path = path_layer.get_node_or_null(chunk_path_name)
	if chunk_path:
		print("🗑️ Despawning path for chunk %d" % chunk_id)
		chunk_path.queue_free()

	# Also despawn torches
	despawn_torches_for_chunk(chunk_id)

	# Clear stored path points
	chunk_path_points.erase(chunk_id)

func get_path_y_at_x(path_points: Array, target_x: float) -> float:
	"""Find the Y coordinate on a path at a given X position (interpolated)"""
	# Find the two points that bracket the target X
	for i in range(path_points.size() - 1):
		var p1 = path_points[i]
		var p2 = path_points[i + 1]

		# Check if target_x falls between these two points
		var min_x = min(p1.x, p2.x)
		var max_x = max(p1.x, p2.x)

		if target_x >= min_x and target_x <= max_x:
			# Interpolate Y based on X position
			if abs(p2.x - p1.x) < 0.001:
				return p1.y  # Avoid division by zero
			var t = (target_x - p1.x) / (p2.x - p1.x)
			return lerp(p1.y, p2.y, t)

	# Fallback: return Y=0 if not found
	return 0.0

func create_zigzag_path(start: Vector2, end: Vector2, _num_zigs: int, zig_amplitude: float, rng: RandomNumberGenerator) -> Array:
	"""Generate a meandering zig-zag path between two points"""
	var points: Array = []
	var total_distance = start.distance_to(end)
	var direction = (end - start).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)

	# More points for detailed meandering (every ~300px)
	var num_points = int(total_distance / 300) + 2
	num_points = clamp(num_points, 6, 30)

	# Multiple overlapping waves for organic zig-zag
	var wave1_freq = rng.randf_range(3.0, 4.5)  # Primary zig-zag
	var wave2_freq = rng.randf_range(6.0, 8.0)  # Secondary wobble
	var phase1 = rng.randf() * TAU
	var phase2 = rng.randf() * TAU

	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var base_pos = start.lerp(end, t)

		# Taper at ends so path connects cleanly
		var taper = sin(t * PI)

		# Primary zig-zag wave (strong)
		var wave1 = sin(t * wave1_freq * PI + phase1)
		# Secondary smaller wave for organic feel
		var wave2 = sin(t * wave2_freq * PI + phase2) * 0.3

		# Combined offset with full amplitude
		var offset = (wave1 + wave2) * zig_amplitude * taper

		# Random noise for organic variation (subtle)
		var noise = rng.randf_range(-20, 20) * taper

		var final_offset = perpendicular * (offset + noise)
		points.append(base_pos + final_offset)

	return points

func _catmull_rom_interpolate(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	"""Catmull-Rom spline interpolation between p1 and p2"""
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _smooth_path_points(points: Array, subdivisions: int = 4) -> Array:
	"""Smooth path using Catmull-Rom spline interpolation"""
	if points.size() < 2:
		return points

	var smoothed: Array = []

	for i in range(points.size() - 1):
		# Get 4 control points for Catmull-Rom (handle edges by duplicating)
		var p0 = points[max(0, i - 1)]
		var p1 = points[i]
		var p2 = points[min(points.size() - 1, i + 1)]
		var p3 = points[min(points.size() - 1, i + 2)]

		# Add interpolated points
		for j in range(subdivisions):
			var t = float(j) / float(subdivisions)
			smoothed.append(_catmull_rom_interpolate(p0, p1, p2, p3, t))

	# Add final point
	smoothed.append(points[points.size() - 1])
	return smoothed

func draw_path_from_points(parent: Node2D, points: Array, width: float, rng: RandomNumberGenerator, clip_min_x: float = -INF, clip_max_x: float = INF):
	"""Draw path with textured/organic edges using overlapping lines.
	Optional clip_min_x/clip_max_x create hard edges at chunk boundaries."""
	if points.size() < 2:
		return

	# Smooth the path using Catmull-Rom splines for natural curves
	var smooth_points = _smooth_path_points(points, 5)

	# Clip points to chunk boundaries if specified
	var has_clipping = clip_min_x > -INF or clip_max_x < INF
	if has_clipping:
		smooth_points = _clip_path_to_bounds(smooth_points, clip_min_x, clip_max_x)

	if smooth_points.size() < 2:
		return

	# Consistent path color - single shade
	const PATH_COLOR = Color(0.06, 0.06, 0.07, 0.85)

	# Create multiple overlapping lines for soft edges (tightened fade)
	var layers = [
		{"width_mult": 1.85, "alpha": 0.6, "noise": 4},    # Outer fade (reduced noise for smooth edges)
		{"width_mult": 1.5, "alpha": 0.85, "noise": 2},    # Core path (minimal noise)
	]

	for layer in layers:
		var line = Line2D.new()
		line.width = width * layer.width_mult
		line.default_color = Color(PATH_COLOR.r, PATH_COLOR.g, PATH_COLOR.b, layer.alpha)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		# Use square caps at chunk boundaries for hard edges
		if has_clipping:
			line.begin_cap_mode = Line2D.LINE_CAP_BOX
			line.end_cap_mode = Line2D.LINE_CAP_BOX
		else:
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true

		# Add smoothed points with subtle noise for organic edges
		for i in range(smooth_points.size()):
			var point = smooth_points[i]
			var noise_amount = layer.noise
			# No noise at endpoints for hard chunk edges
			if i == 0 or i == smooth_points.size() - 1:
				if has_clipping:
					noise_amount = 0  # Hard edge - no noise
				else:
					noise_amount *= 0.3
			var noisy_point = point + Vector2(
				rng.randf_range(-noise_amount, noise_amount),
				rng.randf_range(-noise_amount, noise_amount)
			)
			line.add_point(noisy_point)

		parent.add_child(line)

func _clip_path_to_bounds(points: Array, min_x: float, max_x: float) -> Array:
	"""Clip path points to X boundaries, creating hard edges at chunk borders."""
	var clipped: Array = []

	for i in range(points.size()):
		var point = points[i]

		# Skip points outside bounds entirely
		if point.x < min_x or point.x > max_x:
			# But if we're crossing a boundary, add an edge point
			if clipped.size() > 0 and i > 0:
				var prev = points[i - 1]
				if prev.x >= min_x and prev.x <= max_x:
					# Interpolate to find exact boundary crossing
					if point.x < min_x:
						var t = (min_x - prev.x) / (point.x - prev.x)
						clipped.append(Vector2(min_x, lerp(prev.y, point.y, t)))
					elif point.x > max_x:
						var t = (max_x - prev.x) / (point.x - prev.x)
						clipped.append(Vector2(max_x, lerp(prev.y, point.y, t)))
			continue

		# If this point is inside but previous was outside, add entry point
		if clipped.size() == 0 and i > 0:
			var prev = points[i - 1]
			if prev.x < min_x:
				var t = (min_x - prev.x) / (point.x - prev.x)
				clipped.append(Vector2(min_x, lerp(prev.y, point.y, t)))
			elif prev.x > max_x:
				var t = (max_x - prev.x) / (point.x - prev.x)
				clipped.append(Vector2(max_x, lerp(prev.y, point.y, t)))

		clipped.append(point)

	# Ensure first and last points are exactly on boundary
	if clipped.size() >= 2:
		if clipped[0].x > min_x and min_x > -INF:
			clipped[0].x = min_x
		if clipped[clipped.size() - 1].x < max_x and max_x < INF:
			clipped[clipped.size() - 1].x = max_x

	return clipped

func draw_path_from_points_avoiding_area(parent: Node2D, points: Array, width: float, rng: RandomNumberGenerator, avoid_center: Vector2, avoid_radius: float):
	"""Draw path as Line2D, with gap around avoid area"""
	if points.size() < 2:
		return

	# If no avoid area, just draw normally
	if avoid_radius <= 0:
		draw_path_from_points(parent, points, width, rng)
		return

	# Split points into segments outside the avoid area
	var current_segment: Array = []

	for point in points:
		var in_avoid_area = point.distance_to(avoid_center) < avoid_radius

		if not in_avoid_area:
			current_segment.append(point)
		else:
			# End current segment if it has points
			if current_segment.size() >= 2:
				draw_path_from_points(parent, current_segment, width, rng)
			current_segment = []

	# Draw final segment
	if current_segment.size() >= 2:
		draw_path_from_points(parent, current_segment, width, rng)

func create_curved_path(start: Vector2, end: Vector2, num_points: int, rng: RandomNumberGenerator) -> Array:
	"""Generate curved path points between two positions"""
	var points = []
	for i in range(num_points):
		var t = float(i) / float(num_points - 1)
		var pos = start.lerp(end, t)

		# Add sine curve for natural path wandering
		if i > 0 and i < num_points - 1:
			var curve_amount = sin(t * PI) * 200
			pos.y += sin(t * PI * 2.5) * curve_amount

		points.append(pos)

	return points

func create_ruins_branch_path_spots(path_layer: Node2D, main_path_points: Array, rng: RandomNumberGenerator):
	"""Create branching path spots to ruins"""
	# Branch to Ruins 1 (1,200, -2,000)
	var ruins1_start_index = 7
	var ruins1_start = main_path_points[ruins1_start_index]
	var ruins1_target = Vector2(1200, -2000)
	var ruins1_points = create_branch_to_target(ruins1_start, ruins1_target, 20, rng)

	# Branch to Ruins 2 (4,800, 2,200)
	var ruins2_start_index = 15
	var ruins2_start = main_path_points[ruins2_start_index]
	var ruins2_target = Vector2(4800, 2200)
	var ruins2_points = create_branch_to_target(ruins2_start, ruins2_target, 22, rng)

	# Branch to Ruins 3 (8,200, -2,200)
	var ruins3_start_index = 23
	var ruins3_start = main_path_points[ruins3_start_index]
	var ruins3_target = Vector2(8200, -2200)
	var ruins3_points = create_branch_to_target(ruins3_start, ruins3_target, 22, rng)

	# Add spot data for all branches
	for branch in [ruins1_points, ruins2_points, ruins3_points]:
		for i in range(branch.size() - 1):
			var start = branch[i]
			var end = branch[i + 1]
			var segment_length = start.distance_to(end)
			var num_spots = int(segment_length / 100) + 1

			for j in range(num_spots):
				var t = float(j) / float(max(1, num_spots - 1))
				var pos = start.lerp(end, t)

				var direction = (end - start).normalized()

				# Add natural zigzag variance perpendicular to path direction
				var perpendicular = Vector2(-direction.y, direction.x)
				var variance = rng.randf_range(-60, 60)  # ±60px random offset
				pos += perpendicular * variance

				var elongation = 1.5
				if abs(direction.x) > abs(direction.y):
					elongation = 1.6
				else:
					elongation = 0.8

				terrain_spots.append({
					"pos": pos,
					"size": 180,
					"type": "path",
					"elongation": elongation,
					"darkness": 0.20,  # Darker than terrain for worn path effect
					"parent": path_layer,
					"rng_state": rng.state
				})

	print("   🏛️ Added branch path spots to ruins")

func update_terrain_visibility():
	"""DISABLED - No terrain spot rendering"""
	pass

func get_region_color_tint(pos: Vector2) -> Color:
	"""Get subtle color tint based on world region"""
	# Default: no tint (pure greyscale)
	var tint = Color(1.0, 1.0, 1.0)

	# Ruins regions: Subtle red tint (corruption/dried blood)
	var min_dist_to_ruins = INF
	for ruins_pos in RUINS_POSITIONS.values():
		var dist = pos.distance_to(ruins_pos)
		if dist < min_dist_to_ruins:
			min_dist_to_ruins = dist

	if min_dist_to_ruins < 800:  # Within 800px of any ruins
		var strength = 1.0 - (min_dist_to_ruins / 800.0)  # Stronger near center
		tint = Color(1.0 + strength * 0.2, 1.0 - strength * 0.15, 1.0 - strength * 0.15)  # Subtle red

	# Deep woods regions: Subtle blue tint (cold/cursed)
	# Areas far from path (high Y values)
	var distance_from_path = abs(pos.y)
	if distance_from_path > 1200:  # Deep in the woods
		var strength = clamp((distance_from_path - 1200) / 1000.0, 0.0, 0.5)  # Max 50% strength
		tint = Color(1.0 - strength * 0.15, 1.0 - strength * 0.1, 1.0 + strength * 0.2)  # Subtle blue

	return tint

func create_terrain_spot(spot_index: int, spot_data: Dictionary):
	"""Create ColorRects for a terrain spot"""
	var parent = spot_data["parent"]
	var center = spot_data["pos"]
	var base_size = spot_data["size"]
	var elongation = spot_data["elongation"]
	var darkness_multiplier = spot_data["darkness"]

	# Create container for this spot's ColorRects
	var container = Node2D.new()
	container.name = "Spot_%d" % spot_index
	parent.add_child(container)

	# Restore RNG state for consistent generation
	var rng = RandomNumberGenerator.new()
	rng.state = spot_data["rng_state"]

	# Create feathered layers
	for layer_data in LAYER_TEMPLATE:
		for i in range(layer_data["count"]):
			var rect = ColorRect.new()

			var size = rng.randf_range(
				base_size * layer_data["size_mult"][0],
				base_size * layer_data["size_mult"][1]
			)

			var aspect_variation = rng.randf_range(0.5, 1.8)
			rect.size = Vector2(
				size * elongation * aspect_variation,
				size / elongation * aspect_variation
			)

			var spread = base_size * layer_data["spread_mult"]
			var offset = Vector2(
				rng.randf_range(-spread, spread),
				rng.randf_range(-spread, spread)
			)
			rect.position = center + offset - rect.size / 2

			var darkness = layer_data["darkness"] * rng.randf_range(0.85, 1.15) * darkness_multiplier

			# Apply region-based color tinting
			var region_tint = get_region_color_tint(center)
			rect.color = Color(
				darkness * region_tint.r,
				darkness * region_tint.g,
				darkness * region_tint.b,
				layer_data["alpha"]
			)

			rect.rotation = rng.randf() * TAU
			container.add_child(rect)

	# Track this spot as active
	active_terrain_nodes[spot_index] = container

func remove_terrain_spot(spot_index: int):
	"""Remove ColorRects for a terrain spot"""
	if active_terrain_nodes.has(spot_index):
		var container = active_terrain_nodes[spot_index]
		if is_instance_valid(container):
			container.queue_free()
		active_terrain_nodes.erase(spot_index)

func create_branch_paths(path_layer: Node2D, main_path_points: Array, rng: RandomNumberGenerator):
	"""Create branching paths that fork off main path to dead ends"""

	# Branch 1: Early fork going north (around 25% along main path)
	var branch1_start = main_path_points[7]  # Fork at point 7 of 30
	var branch1_points = []
	branch1_points.append(branch1_start)
	for i in range(1, 15):  # 15 point branch
		var t = float(i) / 14.0
		var pos = branch1_start + Vector2(t * 800, -1200 - t * 400)  # Go north-ish
		# Add some curves
		pos.x += sin(t * PI * 3) * 150
		branch1_points.append(pos)

	# Branch 2: Mid-path fork going south (around 50% along main path)
	var branch2_start = main_path_points[15]  # Fork at midpoint
	var branch2_points = []
	branch2_points.append(branch2_start)
	for i in range(1, 18):  # 18 point branch
		var t = float(i) / 17.0
		var pos = branch2_start + Vector2(t * 600, 1400 + t * 300)  # Go south-ish
		# Add some curves
		pos.x += sin(t * PI * 2.5) * 120
		branch2_points.append(pos)

	# Branch 3: Late fork going north-east (around 70% along main path)
	var branch3_start = main_path_points[21]  # Fork at point 21
	var branch3_points = []
	branch3_points.append(branch3_start)
	for i in range(1, 12):  # 12 point branch
		var t = float(i) / 11.0
		var pos = branch3_start + Vector2(t * 900, -900 - t * 200)  # Go northeast-ish
		# Add some curves
		pos.y += sin(t * PI * 2) * 100
		branch3_points.append(pos)

	# Draw all branches
	for branch in [branch1_points, branch2_points, branch3_points]:
		for i in range(branch.size() - 1):
			var start = branch[i]
			var end = branch[i + 1]
			var segment_length = start.distance_to(end)
			var num_spots = int(segment_length / 100) + 1

			for j in range(num_spots):
				var t = float(j) / float(max(1, num_spots - 1))
				var pos = start.lerp(end, t)

				var direction = (end - start).normalized()
				var elongation = 1.5
				if abs(direction.x) > abs(direction.y):
					elongation = 1.6
				else:
					elongation = 0.8

				# Nearly black for beaten trail
				create_feathered_area(path_layer, pos, 180, rng, elongation, 0.08)

			await get_tree().process_frame

	print("🔀 Created 3 branch paths with dead ends")

func create_ruins_branch_paths(path_layer: Node2D, main_path_points: Array, rng: RandomNumberGenerator):
	"""Create branching paths from main path to each ruins"""

	# Branch to Ruins 1 (1,200, -2,000) - north branch around 25% of path
	var ruins1_start_index = 7  # Around x=1,200
	var ruins1_start = main_path_points[ruins1_start_index]
	var ruins1_target = Vector2(1200, -2000)
	var ruins1_points = create_branch_to_target(ruins1_start, ruins1_target, 20, rng)

	# Branch to Ruins 2 (4,800, 2,200) - south branch around 52% of path
	var ruins2_start_index = 15  # Around x=4,800
	var ruins2_start = main_path_points[ruins2_start_index]
	var ruins2_target = Vector2(4800, 2200)
	var ruins2_points = create_branch_to_target(ruins2_start, ruins2_target, 22, rng)

	# Branch to Ruins 3 (8,200, -2,200) - north branch around 78% of path
	var ruins3_start_index = 23  # Around x=8,200
	var ruins3_start = main_path_points[ruins3_start_index]
	var ruins3_target = Vector2(8200, -2200)
	var ruins3_points = create_branch_to_target(ruins3_start, ruins3_target, 22, rng)

	# Draw all ruins branches
	for branch in [ruins1_points, ruins2_points, ruins3_points]:
		for i in range(branch.size() - 1):
			var start = branch[i]
			var end = branch[i + 1]
			var segment_length = start.distance_to(end)
			var num_spots = int(segment_length / 100) + 1

			for j in range(num_spots):
				var t = float(j) / float(max(1, num_spots - 1))
				var pos = start.lerp(end, t)

				var direction = (end - start).normalized()

				# Add natural zigzag variance perpendicular to path direction
				var perpendicular = Vector2(-direction.y, direction.x)
				var variance = rng.randf_range(-60, 60)  # ±60px random offset
				pos += perpendicular * variance

				var elongation = 1.5
				if abs(direction.x) > abs(direction.y):
					elongation = 1.6
				else:
					elongation = 0.8

				# Nearly black for beaten trail
				create_feathered_area(path_layer, pos, 180, rng, elongation, 0.08)

			await get_tree().process_frame

	print("🏛️ Created 3 branch paths to ruins")

func create_branch_to_target(start: Vector2, target: Vector2, num_points: int, rng: RandomNumberGenerator) -> Array:
	"""Create a curved path from start to target"""
	var points = []
	points.append(start)

	for i in range(1, num_points):
		var t = float(i) / float(num_points - 1)
		var pos = start.lerp(target, t)

		# Add some natural curves perpendicular to direction
		var direction = (target - start).normalized()
		var perpendicular = Vector2(-direction.y, direction.x)
		var curve_amount = sin(t * PI) * 150.0  # Max 150px deviation
		pos += perpendicular * curve_amount * rng.randf_range(-1.0, 1.0)

		points.append(pos)

	points.append(target)  # Ensure we end exactly at target
	return points

func create_ruins_clearings(rng: RandomNumberGenerator):
	"""Create clearings around each ruins location"""
	var clearing_layer = Node2D.new()
	clearing_layer.name = "RuinsClearings"
	clearing_layer.z_index = -6
	add_child(clearing_layer)

	# Create clearing at each ruins location - 75% of campfire size (450 * 0.75 = 340)
	for ruins_name in RUINS_POSITIONS:
		var ruins_data = RUINS_POSITIONS[ruins_name]
		var ruins_pos = ruins_data.position if ruins_data is Dictionary else ruins_data
		create_feathered_area(clearing_layer, ruins_pos, 340, rng, 1.0, 0.12)

	print("🏛️ Created clearings at %d ruins locations" % RUINS_POSITIONS.size())

func create_feathered_area(parent: Node2D, center: Vector2, base_size: float, rng: RandomNumberGenerator, elongation: float = 1.0, darkness_multiplier: float = 1.0):
	for layer_data in LAYER_TEMPLATE:
		for i in range(layer_data["count"]):
			var rect = ColorRect.new()

			var size = rng.randf_range(
				base_size * layer_data["size_mult"][0],
				base_size * layer_data["size_mult"][1]
			)

			var aspect_variation = rng.randf_range(0.5, 1.8)
			rect.size = Vector2(
				size * elongation * aspect_variation,
				size / elongation * aspect_variation
			)

			var spread = base_size * layer_data["spread_mult"]
			var offset = Vector2(
				rng.randf_range(-spread, spread),
				rng.randf_range(-spread, spread)
			)
			rect.position = center + offset - rect.size / 2

			var darkness = layer_data["darkness"] * rng.randf_range(0.85, 1.15) * darkness_multiplier
			# Pure greyscale for charcoal dreadland aesthetic
			rect.color = Color(
				darkness,
				darkness,
				darkness,
				layer_data["alpha"]
			)

			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

func create_campfire_circle(parent: Node2D, center: Vector2, rng: RandomNumberGenerator):
	"""Create worn circular clearing around campfire with soft fade edge"""
	var clearing_radius = 400.0

	# Generate base shape points (reused for both layers)
	var num_points = 32
	var base_points = []
	for i in range(num_points):
		var angle = (float(i) / float(num_points)) * TAU
		var wobble = sin(angle * 2) * 15 + cos(angle * 3) * 10
		var noise = rng.randf_range(-10, 10)
		base_points.append({"angle": angle, "wobble": wobble, "noise": noise})

	# Outer fade layer (larger, semi-transparent) - drawn first
	var outer_polygon = Polygon2D.new()
	outer_polygon.position = center
	var outer_points = PackedVector2Array()
	var outer_radius = clearing_radius + 40  # 25% bigger fade
	for p in base_points:
		var point_radius = outer_radius + p.wobble + p.noise
		outer_points.append(Vector2(cos(p.angle), sin(p.angle)) * point_radius)
	outer_polygon.polygon = outer_points
	outer_polygon.color = Color(0.055, 0.055, 0.065, 0.35)  # Between path and old clearing
	outer_polygon.antialiased = true
	parent.add_child(outer_polygon)

	# Main clearing polygon (opaque) - drawn on top
	var polygon = Polygon2D.new()
	polygon.position = center
	var points = PackedVector2Array()
	for p in base_points:
		var point_radius = clearing_radius + p.wobble + p.noise
		points.append(Vector2(cos(p.angle), sin(p.angle)) * point_radius)
	polygon.polygon = points
	polygon.color = Color(0.055, 0.055, 0.065, 1.0)  # Lighter than before, still darker than path (0.06)
	polygon.antialiased = true
	parent.add_child(polygon)

	# Add scattered bones/skulls as decoration on the clearing
	add_campfire_decorations(parent, center, clearing_radius, rng)

func add_campfire_decorations(parent: Node2D, center: Vector2, clearing_radius: float, rng: RandomNumberGenerator):
	"""Add scattered bones, skulls around the campfire clearing"""
	var bone_texture = load("res://assets/environment/dreadland/bones.png") as Texture2D
	var skull_texture = load("res://assets/environment/dreadland/skull.png") as Texture2D

	if not bone_texture:
		return

	# Scatter 10-15 bones/skulls around the clearing (not too close to center campfire)
	var num_decorations = rng.randi_range(10, 15)
	var min_dist = 120.0  # Keep away from campfire center
	var max_dist = clearing_radius - 50.0  # Stay within clearing

	for i in range(num_decorations):
		var angle = rng.randf() * TAU
		var dist = rng.randf_range(min_dist, max_dist)
		var pos = center + Vector2(cos(angle), sin(angle)) * dist

		# 75% bones, 25% skulls
		var is_skull = rng.randf() < 0.25
		var texture = skull_texture if is_skull and skull_texture else bone_texture

		var sprite = Sprite2D.new()
		sprite.texture = texture
		sprite.global_position = pos
		sprite.rotation = rng.randf() * TAU
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 0.9)

		# Brighter so visible on dark clearing
		var brightness = rng.randf_range(0.75, 1.0)
		sprite.modulate = Color(brightness, brightness * 0.95, brightness * 0.88, 1.0)

		sprite.z_index = 1  # Above clearing polygon (which is 0)
		parent.add_child(sprite)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			toggle_screenshot_mode()

func toggle_screenshot_mode():
	screenshot_mode = !screenshot_mode

	if screenshot_mode:
		print("📷 Screenshot mode ENABLED - Dynamic elements hidden")
	else:
		print("🎮 Screenshot mode DISABLED - All elements visible")

	# Hide/show dynamic elements
	# Static elements (BakedBackground, ScatteredProps, PathMarkers) remain visible

	# Hide all enemies
	for child in get_children():
		# Enemies are direct children instantiated from ENEMY_SCENE
		if child.scene_file_path == "res://scenes/enemies/enemy.tscn":
			child.visible = !screenshot_mode

	# Hide player (if it exists in the scene tree)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.visible = !screenshot_mode

	# Hide UI elements
	var ui_layer = get_tree().get_first_node_in_group("ui")
	if ui_layer:
		ui_layer.visible = !screenshot_mode

	# Hide animated campfire (if it exists)
	var campfire = get_node_or_null("Campfire")
	if campfire:
		campfire.visible = !screenshot_mode

	# Hide particle effects
	for child in get_tree().get_nodes_in_group("particles"):
		child.visible = !screenshot_mode

func generate_dynamic_elements():
	"""Generate only the elements that need to be interactive/dynamic"""

	# Populate world with enemies - NOW HANDLED BY SpawnManager in spawn_all_enemies()
	# populate_world_enemies()  # DISABLED: Using dynamic spawning instead

	# Use existing ScatteredProps node from scene (don't create new one)
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		# Fallback: create if it doesn't exist
		scattered_props_node = Node2D.new()
		scattered_props_node.name = "ScatteredProps"
		add_child(scattered_props_node)

	# Enable Y-sorting so props layer correctly based on position
	scattered_props_node.y_sort_enabled = true

	# ========================================================================
	# CHUNK-BASED PROP SYSTEM - Props now generated dynamically as player moves
	# ========================================================================
	# The following static prop generation functions are DISABLED in favor of
	# ChunkBasedPropSystem, which loads/unloads chunks as the player moves:
	#   - spawn_trees_everywhere_dynamic() -> trees generated per chunk (LOOTABLE)
	#   - spawn_lava_pools() -> lava pools generated per chunk
	#   - spawn_bone_clusters() -> bone clusters generated per chunk
	#   - spawn_dead_vegetation() -> dead vegetation generated per chunk
	#   - spawn_rock_sprites() -> rocks generated per chunk (large rocks LOOTABLE)
	#   - spawn_scattered_props() -> ash piles generated per chunk
	#   - spawn_small_rocks() -> small rocks generated per chunk
	#   - spawn_ground_cracks() -> cracks generated per chunk
	#
	# This reduces node count from 16,731+ to under 1,000 at spawn for massive FPS gains!
	# Trees and large rocks are still lootable via deterministic chunk generation.
	# ========================================================================

	# Interactive props on the path (skull, bones, broken sword) - KEEP STATIC
	load_interactive_props(scattered_props_node)

	# Register with spawn manager
	LootSpawnManager.register_game_world(self)

	# Generate possible spawn points (many more than will actually spawn)
	generate_item_spawn_points()
	generate_chest_spawn_points()

	# Trigger initial spawn (spawn manager decides which points to use)
	LootSpawnManager.initial_spawn()
	print("📦 LootSpawnManager spawned initial items and chests")

	# Path markers
	load_path_markers_from_json()

	# Torches along path
	create_torches_along_path()

	# Enemies
	spawn_all_enemies()

	# Training Dummy (near campfire for combat practice)
	spawn_training_dummy()

	# Ambient atmosphere
	create_ambient_particles()

# ===== DYNAMIC ELEMENT GENERATION =====
# These functions generate trees, props, and enemies that need to be separate nodes

func spawn_trees_everywhere_dynamic(parent: Node2D):
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777

	var trees_placed = 0

	# Cover full world bounds for tree placement
	# 20% spawn rate (reduced from 40% for better balance)
	for x in range(Constants.WORLD_LEFT, Constants.WORLD_RIGHT, Constants.TREE_GRID_SPACING):
		for y in range(Constants.WORLD_TOP, Constants.WORLD_BOTTOM, Constants.TREE_GRID_SPACING):
			if rng.randf() > Constants.TREE_SPAWN_RATE:
				continue
			
			var tree_pos = Vector2(
				x + rng.randf_range(-95, 95),
				y + rng.randf_range(-95, 95)
			)

			# Clamp to world boundaries with buffer to prevent edge clipping
			var buffer = 300.0  # Keep trees 300px from edges
			tree_pos.x = clamp(tree_pos.x, -5000 + buffer, 13000 - buffer)
			tree_pos.y = clamp(tree_pos.y, -3000 + buffer, 3000 - buffer)

			# Avoid campfire area (larger radius to account for large trees and campfire circle)
			var campfire_pos = CAMPFIRE_POS
			if tree_pos.distance_to(campfire_pos) < 700:
				continue

			# Don't place trees on the path - increased avoidance to prevent creeping
			if is_position_on_path(tree_pos, 350.0):
				continue

			# Don't place trees on lava pools
			var on_lava = false
			for pool in lava_pool_positions:
				var dist = tree_pos.distance_to(pool.pos)
				var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 50  # Larger buffer for trees
				if dist < pool_radius:
					on_lava = true
					break
			if on_lava:
				continue

			var tree_type = tree_types[rng.randi() % tree_types.size()]
			create_tree_at_position(parent, tree_pos, tree_type, rng)
			tree_positions.append(tree_pos)  # Store position to avoid small rocks spawning here
			trees_placed += 1
	
	print("🌲 Placed ", trees_placed, " trees (dynamic)")

func spawn_rock_sprites(parent: Node2D):
	"""Spawn rock sprites on top of the dark spots we created earlier"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	var rocks_placed = 0

	# Cover full world bounds for rock placement with buffer
	var buffer = 300.0  # Keep large rocks 300px from edges
	for i in range(62):  # Increased by 25% to fill more space
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		var campfire_pos = CAMPFIRE_POS
		if rock_pos.distance_to(campfire_pos) < 450:
			continue

		# Don't place rocks on the path - only battle props (skull, bones, sword) go there
		if is_position_on_path(rock_pos, 150.0):
			continue

		# Don't place on top of trees (check distance to all tree positions)
		var too_close_to_tree = false
		for tree_pos in tree_positions:
			if rock_pos.distance_to(tree_pos) < 100:  # 100px clearance around trees
				too_close_to_tree = true
				break
		if too_close_to_tree:
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = rock_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 20  # Buffer
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Skip the dark spot generation (already done)
		# Just create the rock sprite
		create_rock_at_position(parent, rock_pos, rng)
		rocks_placed += 1

	print("🪨 Placed ", rocks_placed, " rock sprites")

func spawn_scattered_props(parent: Node2D):
	"""Spawn small props scattered around (ash piles, small debris, etc.)"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765

	# Just use ash_pile - looks much better than cracks
	var visual_props = ["ash_pile"]
	var props_placed = 0

	# Cover full world with scattered props with buffer
	var buffer = 150.0  # Keep small props 150px from edges
	for i in range(40):  # MASSIVELY reduced from 100 for 60 FPS (was 250)
		var prop_type = visual_props[rng.randi() % visual_props.size()]
		var prop_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Reduce clutter around campfire by 25%
		var campfire_pos = CAMPFIRE_POS
		if prop_pos.distance_to(campfire_pos) < 600:
			if rng.randf() < 0.25:  # Skip 25% of props near campfire
				continue

		# Don't place on the path
		if is_position_on_path(prop_pos, 100.0):
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = prop_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 30
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		var prop_data = {
			"type": prop_type,
			"x": prop_pos.x,
			"y": prop_pos.y,
			"scale": rng.randf_range(0.4, 1.5),  # More variety in ash pile sizes
			"rotation": rng.randf() * TAU,
			"flip_h": rng.randf() < 0.5,
			"z_index": -2,  # Below rocks (0) so ash piles don't render on top
			"id": 3000 + i
		}
		if create_prop_sprite(prop_data, parent):
			props_placed += 1

	print("🌿 Placed ", props_placed, " scattered props")

func spawn_small_rocks(parent: Node2D):
	"""Spawn small rocks everywhere to fill bare sand areas"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	var rocks_placed = 0

	# Optimized rock count for performance (was 2400, then 800)
	var buffer = 200.0  # Keep small rocks 200px from edges
	for i in range(200):  # MASSIVELY reduced from 800 for 60 FPS target
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Avoid campfire area
		var campfire_pos = CAMPFIRE_POS
		if rock_pos.distance_to(campfire_pos) < 450:
			continue

		# Don't place on the path
		if is_position_on_path(rock_pos, 150.0):
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = rock_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 30
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Prefer spawning in bare areas (far from path and campfire)
		# 80% of rocks should be in outer regions away from central path (was 70%)
		var distance_from_center = abs(rock_pos.y)
		if distance_from_center < 800 and rng.randf() > 0.2:
			continue  # Skip 80% of rocks near the path corridor

		var prop_data = {
			"type": "rock_small",
			"x": rock_pos.x,
			"y": rock_pos.y,
			"scale": rng.randf_range(0.6, 1.2),
			"rotation": rng.randf_range(-PI/6, PI/6),  # Horizontal only (-30° to +30°)
			"flip_h": rng.randf() < 0.5,
			"z_index": 0,
			"id": 5000 + i
		}
		if create_prop_sprite(prop_data, parent):
			rocks_placed += 1

	print("🪨 Placed ", rocks_placed, " small rocks (ground fill)")

func load_interactive_props(parent: Node2D):
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765

	var battle_props = ["skull", "bones", "broken_sword"]
	var props_placed = 0

	# Main path props (50 total for full extended path - optimized for performance)
	for i in range(50):
		var prop_type = battle_props[rng.randi() % battle_props.size()]

		var attempts = 0
		var prop_pos = Vector2.ZERO
		var valid_position = false
		while attempts < 50:
			prop_pos = Vector2(
				rng.randf_range(-2200, 11200),  # Cover full new path range
				rng.randf_range(-2500, 2500)     # Wider Y range for ruins branches
			)
			if is_position_on_path(prop_pos, 100.0):
				# Check if not too close to trees
				var too_close_to_tree = false
				for tree_pos in tree_positions:
					if prop_pos.distance_to(tree_pos) < 100:  # 100px clearance around trees
						too_close_to_tree = true
						break

				# Check if not on lava pool
				var on_lava = false
				for pool in lava_pool_positions:
					var dist = prop_pos.distance_to(pool.pos)
					var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 30
					if dist < pool_radius:
						on_lava = true
						break

				if not too_close_to_tree and not on_lava:
					valid_position = true
					break
			attempts += 1

		if valid_position:
			var prop_data = {
				"type": prop_type,
				"x": prop_pos.x,
				"y": prop_pos.y,
				"scale": rng.randf_range(0.5, 1.2),
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": 0,  # Same as trees/rocks for proper Y-sorting
				"id": 2000 + i
			}
			create_prop_sprite(prop_data, parent)
			props_placed += 1

	# NOTE: Dense bone clusters in cleared areas REMOVED - ChunkBasedPropSystem
	# now handles ritual bone piles with wolf pack spawning

	print("⚔️ Placed ", props_placed, " path battle props (skulls, bones, swords)")

func generate_item_spawn_points():
	"""Generate possible spawn points for items (5x more than will actually spawn)"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777

	# Generate 75 possible spawn points (LootSpawnManager will spawn 15 at a time)
	for i in range(75):
		# Find a random position (avoid campfire and path)
		var attempts = 0
		var item_pos = Vector2.ZERO
		while attempts < 50:
			item_pos = Vector2(
				rng.randf_range(-4000, 8000),
				rng.randf_range(-2000, 2000)
			)

			# Avoid campfire area
			var campfire_pos = CAMPFIRE_POS
			if item_pos.distance_to(campfire_pos) < 600:
				attempts += 1
				continue

			# Prefer areas off the main path (but not required)
			if not is_position_on_path(item_pos, 200.0):
				break

			attempts += 1

		# Add to spawn manager's pool
		LootSpawnManager.add_item_spawn_point(item_pos)

	print("💎 Generated 75 possible item spawn points")

func generate_chest_spawn_points():
	"""Generate possible spawn points for chests - 40% near lava pools, 60% scattered"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 55555

	# Get lava pool positions from chunk system
	var all_lava_pools = []
	if chunk_prop_system and chunk_prop_system.get("loaded_chunks"):
		for chunk_key in chunk_prop_system.loaded_chunks:
			var chunk_data = chunk_prop_system.loaded_chunks[chunk_key]
			if chunk_data and chunk_data.lava_pool_positions:
				all_lava_pools.append_array(chunk_data.lava_pool_positions)

	# Also check our local lava_pool_positions if chunk system hasn't loaded yet
	if all_lava_pools.is_empty() and lava_pool_positions.size() > 0:
		for pool in lava_pool_positions:
			all_lava_pools.append({"pos": pool.pos, "radius": pool.size / 2 + 30})

	var lava_pool_chest_count = 20 if all_lava_pools.size() > 0 else 0  # 40% near lava (20 of 50)
	var scattered_chest_count = 50 - lava_pool_chest_count

	# Generate chests near lava pools (high danger = high reward)
	for i in range(lava_pool_chest_count):
		if all_lava_pools.is_empty():
			break

		var pool = all_lava_pools[rng.randi() % all_lava_pools.size()]
		var attempts = 0
		var chest_pos = Vector2.ZERO

		while attempts < 30:
			# Spawn 200-500px from lava pool center (close but not in lava)
			var angle = rng.randf() * TAU
			var distance = rng.randf_range(200, 500)
			chest_pos = pool.pos + Vector2(cos(angle), sin(angle)) * distance

			# Clamp to world bounds
			chest_pos.x = clamp(chest_pos.x, -4000, 8000)
			chest_pos.y = clamp(chest_pos.y, -2000, 2000)

			# Avoid spawning inside lava pools
			if is_position_in_lava(chest_pos, 30.0):
				attempts += 1
				continue

			# Avoid spawning on trees
			var too_close_to_tree = false
			for tree_pos in tree_positions:
				if chest_pos.distance_to(tree_pos) < 100:
					too_close_to_tree = true
					break
			if too_close_to_tree:
				attempts += 1
				continue

			break

		LootSpawnManager.add_chest_spawn_point(chest_pos)

	# Generate scattered chests (deep in the wilderness, far from path)
	for i in range(scattered_chest_count):
		var attempts = 0
		var chest_pos = Vector2.ZERO
		while attempts < 50:
			# Spawn chests in the wilderness zones (north or south of the path)
			# North wilderness: y from -800 to -2000
			# South wilderness: y from 800 to 2000
			var in_north = rng.randf() < 0.5
			if in_north:
				chest_pos = Vector2(
					rng.randf_range(-4000, 8000),
					rng.randf_range(-2000, -800)  # Deep north wilderness
				)
			else:
				chest_pos = Vector2(
					rng.randf_range(-4000, 8000),
					rng.randf_range(800, 2000)  # Deep south wilderness
				)

			# Avoid campfire area
			var campfire_pos = CAMPFIRE_POS
			if chest_pos.distance_to(campfire_pos) < 1200:
				attempts += 1
				continue

			# Avoid main path with larger buffer (chests should be deep in wilderness)
			if is_position_on_path(chest_pos, 600.0):
				attempts += 1
				continue

			# Avoid spawning inside lava pools
			if is_position_in_lava(chest_pos, 30.0):
				attempts += 1
				continue

			# Avoid spawning on trees
			var too_close_to_tree = false
			for tree_pos in tree_positions:
				if chest_pos.distance_to(tree_pos) < 100:
					too_close_to_tree = true
					break
			if too_close_to_tree:
				attempts += 1
				continue

			# Valid position found
			break

		LootSpawnManager.add_chest_spawn_point(chest_pos)

	print("📦 Generated 50 chest spawn points (%d near lava pools, %d scattered)" % [lava_pool_chest_count, scattered_chest_count])

# ===== HELPER FUNCTIONS =====

func is_position_in_lava(pos: Vector2, buffer: float = 20.0) -> bool:
	"""Check if a position is inside or too close to a lava pool"""
	for pool in lava_pool_positions:
		var pool_radius = pool.size / 2 + buffer
		if pos.distance_to(pool.pos) < pool_radius:
			return true
	return false

func is_position_on_path(pos: Vector2, path_width: float = 100.0) -> bool:
	# Check main path
	var campfire_pos = CAMPFIRE_POS
	var castle_pos = Vector2(11000, -300)

	if pos.x >= campfire_pos.x and pos.x <= castle_pos.x:
		var path_length = castle_pos.x - campfire_pos.x
		var t = (pos.x - campfire_pos.x) / path_length
		var path_y = lerp(campfire_pos.y, castle_pos.y, t)
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			path_y += sin(t * PI * 2.5) * curve_amount

		var distance_from_path = abs(pos.y - path_y)
		if distance_from_path <= path_width:
			return true

	# Check Ruins 1 branch (to 1,200, -2,000)
	# Branch from main path around x=1,200 northward to ruins
	if pos.x >= 800 and pos.x <= 1600:
		var branch_start_index = 7  # Approximate fork point
		var t = float(branch_start_index) / 29.0
		var branch_start = campfire_pos.lerp(castle_pos, t)
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			branch_start.y += sin(t * PI * 2.5) * curve_amount
		var branch_end = Vector2(1200, -2000)
		var closest_dist = point_to_line_segment_distance(pos, branch_start, branch_end)
		if closest_dist <= path_width:
			return true

	# Check Ruins 2 branch (to 4,800, 2,200)
	# Branch from main path around x=4,800 southward to ruins
	if pos.x >= 4400 and pos.x <= 5200:
		var branch_start_index = 15  # Approximate fork point
		var t = float(branch_start_index) / 29.0
		var branch_start = campfire_pos.lerp(castle_pos, t)
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			branch_start.y += sin(t * PI * 2.5) * curve_amount
		var branch_end = Vector2(4800, 2200)
		var closest_dist = point_to_line_segment_distance(pos, branch_start, branch_end)
		if closest_dist <= path_width:
			return true

	# Check Ruins 3 branch (to 8,200, -2,200)
	# Branch from main path around x=8,200 northward to ruins
	if pos.x >= 7800 and pos.x <= 8600:
		var branch_start_index = 23  # Approximate fork point
		var t = float(branch_start_index) / 29.0
		var branch_start = campfire_pos.lerp(castle_pos, t)
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			branch_start.y += sin(t * PI * 2.5) * curve_amount
		var branch_end = Vector2(8200, -2200)
		var closest_dist = point_to_line_segment_distance(pos, branch_start, branch_end)
		if closest_dist <= path_width:
			return true

	return false

func point_to_line_segment_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calculate shortest distance from point to line segment"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len = line_vec.length()

	if line_len == 0:
		return point.distance_to(line_start)

	var t = clamp(point_vec.dot(line_vec) / (line_len * line_len), 0.0, 1.0)
	var projection = line_start + t * line_vec
	return point.distance_to(projection)

func create_tree_at_position(parent: Node2D, pos: Vector2, tree_type: String, rng: RandomNumberGenerator):
	# Load tree scene (collision positions are set visually in these scenes)
	if not TREE_SCENES.has(tree_type):
		return

	var scene_path = TREE_SCENES[tree_type]
	if not ResourceLoader.exists(scene_path):
		return

	var tree_scene = load(scene_path)
	var prop_container = tree_scene.instantiate()

	prop_container.name = tree_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	prop_container.collision_layer = 2  # Layer 2 for obstacles
	prop_container.collision_mask = 0

	# Determine tree size (small trees now rare - only 10%)
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.1:
		tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (rare - 10%)
	elif size_roll < 0.55:
		tree_scale = rng.randf_range(2.93, 3.9)  # Medium trees (45%)
	else:
		tree_scale = rng.randf_range(3.9, 5.2)  # Large trees (45%)

	var tree_flipped = rng.randf() < 0.5

	# Get sprite and collision from scene and apply scaling
	var sprite = prop_container.get_node_or_null("Sprite")
	var shadow = prop_container.get_node_or_null("Shadow")
	var collision = prop_container.get_node_or_null("CollisionShape2D")

	if sprite:
		sprite.scale = Vector2(tree_scale, tree_scale)
		sprite.flip_h = tree_flipped

		# Mix of tree types: 40% brown oak/maple, 30% white birch, 30% grey/silver
		var tree_roll = rng.randf()
		if tree_roll < 0.4:
			var base_brown = rng.randf_range(0.7, 0.9)
			sprite.modulate = Color(
				base_brown,
				base_brown * rng.randf_range(0.7, 0.85),
				base_brown * rng.randf_range(0.5, 0.65),
				1.0
			)
		elif tree_roll < 0.7:
			var brightness = rng.randf_range(0.9, 1.0)
			sprite.modulate = Color(brightness, brightness * 0.98, brightness * 0.94, 1.0)
		else:
			var grey = rng.randf_range(0.75, 0.95)
			sprite.modulate = Color(grey, grey, grey * 1.02, 1.0)

	if shadow:
		# Scale shadow with tree
		var shadow_width = 45 * (tree_scale / 2.5) * 0.75
		var shadow_height = shadow_width * 0.4
		shadow.size = Vector2(shadow_width, shadow_height)
		shadow.position = Vector2(-shadow_width / 2, 56 * tree_scale)

	if collision:
		# Scale collision position and radius based on tree size
		# The scene's collision.position.y is the base offset for scale 1.0
		var base_collision_y = collision.position.y
		collision.position = Vector2(0, base_collision_y * tree_scale)
		if collision.shape is CircleShape2D:
			collision.shape.radius = 10 * tree_scale

	parent.add_child(prop_container)

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator):
	# Use HarvestableRock for mineable rocks
	var HarvestableRockClass = preload("res://scripts/environment/HarvestableRock.gd")
	var prop_container = HarvestableRockClass.new()
	prop_container.name = "rock_large_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	# Set collision layers (layer 2 for obstacles)
	prop_container.collision_layer = 2
	prop_container.collision_mask = 0

	var texture_path = PROP_TEXTURES["rock_large"]
	if not ResourceLoader.exists(texture_path):
		return

	var texture = load(texture_path)

	# Varied boulder sizes: Large, Extra Large, XXL
	var size_roll = rng.randf()
	var rock_scale: float
	if size_roll < 0.4:
		rock_scale = rng.randf_range(1.5, 2.0)  # Large
	elif size_roll < 0.75:
		rock_scale = rng.randf_range(2.0, 2.75)  # Extra Large
	else:
		rock_scale = rng.randf_range(2.75, 3.5)  # XXL Boulders

	# Create simple dark oval shadow at base of rock
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 45 * (rock_scale / 1.5)  # Scale shadow with rock
	var shadow_height = shadow_width * 0.3  # More elongated oval for sideways rocks
	shadow.size = Vector2(shadow_width, shadow_height)
	# Position at bottom of rock (rocks are ~48px tall base, scaled)
	var shadow_y = (48 * rock_scale / 2.5) - 2
	shadow.position = Vector2(-shadow_width/2 + 3, shadow_y)
	shadow.color = Color(0, 0, 0, 0.6)  # Darker shadow
	shadow.z_index = -4  # Above ground layers, below props

	# Apply oval shader with soft gradient falloff
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;  // Convert to -1 to 1 range
	float dist = length(uv);  // Distance from center
	if (dist > 1.0) {
		discard;  // Make it circular
	}
	// Soft gradient falloff at edges
	float alpha = 1.0 - smoothstep(0.6, 1.0, dist);
	COLOR.a *= alpha;
}
"""
	shader_material.shader = shader
	shadow.material = shader_material

	prop_container.add_child(shadow)

	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(rock_scale, rock_scale)
	sprite.flip_h = rng.randf() < 0.5
	# Only spawn sideways - restrict rotation to horizontal (-30° to +30°)
	sprite.rotation = rng.randf_range(-PI/6, PI/6)
	sprite.z_index = 0  # Same as trees for proper Y-sorting

	# Pure greyscale for charcoal dreadland aesthetic
	var color_variation = rng.randf_range(0.8, 1.0)
	sprite.modulate = Color(color_variation, color_variation, color_variation)

	prop_container.add_child(sprite)

	# Add collision shape for large rocks
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	# Collision radius scales with rock size
	shape.radius = 20 * rock_scale  # Rocks are wider than tree trunks
	collision_shape.shape = shape
	# Position collision at center of rock
	collision_shape.position = Vector2(0, 0)
	prop_container.add_child(collision_shape)

	# Set ore amount based on rock size (for HarvestableRock)
	if rock_scale < 2.0:
		prop_container.ore_amount = 1  # Small rocks
	elif rock_scale < 2.75:
		prop_container.ore_amount = 2  # Medium rocks
	else:
		prop_container.ore_amount = 3  # Large rocks

	parent.add_child(prop_container)

func create_prop_sprite(prop_data: Dictionary, parent: Node2D) -> bool:
	var prop_container = Node2D.new()
	prop_container.name = prop_data.get("type", "prop") + "_" + str(prop_data.get("id", 0))
	prop_container.position = Vector2(prop_data.get("x", 0), prop_data.get("y", 0))

	var prop_type = prop_data.get("type", "")
	var scale_val = prop_data.get("scale", 1.0)
	var rotation_val = get_safe_rotation(prop_type, prop_data.get("rotation", 0.0))

	if not PROP_TEXTURES.has(prop_type):
		return false

	var texture_path = PROP_TEXTURES[prop_type]
	if not ResourceLoader.exists(texture_path):
		return false

	var texture = load(texture_path)

	# Create simple dark oval shadow at base of small props
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 20 * scale_val
	var shadow_height = shadow_width * 0.4  # Oval shape
	var shadow_y = (24 * scale_val / 4) - 3  # Moved up 5px from previous position
	var shadow_x_offset = -shadow_width/2 + 2

	# Custom shadow for broken_sword - elongated to match sword shape
	if prop_type == "broken_sword":
		shadow_width = 28 * scale_val  # Shadow length for sword
		shadow_height = 6 * scale_val   # Thinner shadow
		shadow_y = 8 * scale_val        # Position below sword
		shadow_x_offset = -shadow_width / 2  # Center shadow under sword

	shadow.size = Vector2(shadow_width, shadow_height)
	shadow.position = Vector2(shadow_x_offset, shadow_y)
	shadow.color = Color(0, 0, 0, 0.6)  # Darker shadow
	shadow.z_index = -4  # Above ground layers, below props

	# Apply oval shader with soft gradient falloff
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;  // Convert to -1 to 1 range
	float dist = length(uv);  // Distance from center
	if (dist > 1.0) {
		discard;  // Make it circular
	}
	// Soft gradient falloff at edges
	float alpha = 1.0 - smoothstep(0.6, 1.0, dist);
	COLOR.a *= alpha;
}
"""
	shader_material.shader = shader
	shadow.material = shader_material

	prop_container.add_child(shadow)

	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.flip_h = prop_data.get("flip_h", false)
	sprite.z_index = prop_data.get("z_index", -1)
	sprite.rotation = rotation_val

	# Add varied brightness for age/wear (80-100%)
	var brightness = prop_data.get("brightness", randf_range(0.8, 1.0))
	sprite.modulate = Color(brightness, brightness, brightness, 1.0)

	prop_container.add_child(sprite)
	parent.add_child(prop_container)
	return true

func get_safe_rotation(prop_type: String, requested_rotation: float) -> float:
	match prop_type:
		"dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", "dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10", "ash_pile":
			return 0.0
		_:
			return requested_rotation

func load_path_markers_from_json():
	# DISABLED - These were debug markers (yellow rocks) used during path development
	return

	# Load path markers with validation
	var result = JSONValidator.load_json_file("res://data/path_markers.json")
	if not result.success:
		Constants.log_error("Failed to load path_markers.json: %s" % result.error)
		return

	var data = result.data
	if not data.has("PathMarkers"):
		Constants.log_error("path_markers.json missing 'PathMarkers' array")
		return

	var markers = data["PathMarkers"]
	if not markers is Array:
		Constants.log_error("PathMarkers in path_markers.json is not an array")
		return

	# Use existing PathMarkers node from scene (don't create new one)
	var path_markers_node = get_node_or_null("PathMarkers")
	if not path_markers_node:
		# Fallback: create if it doesn't exist
		path_markers_node = Node2D.new()
		path_markers_node.name = "PathMarkers"
		add_child(path_markers_node)

	for marker in markers:
		if marker is Dictionary:
			# Validate required marker fields
			if JSONValidator.validate_required_fields(marker, ["id", "x", "y"], "path marker"):
				create_marker_sprite(marker, path_markers_node)
		else:
			Constants.log_warning("Invalid path marker entry (not a Dictionary)")

func create_marker_sprite(marker_data: Dictionary, parent: Node2D) -> bool:
	var sprite = Sprite2D.new()
	sprite.name = "PathMarker_" + str(marker_data.get("id", 0))
	sprite.position = Vector2(marker_data.get("x", 0), marker_data.get("y", 0))
	sprite.scale = Vector2(1.2, 1.2)
	sprite.z_index = -1
	sprite.modulate = Color(1.0, 1.0, 0.5)
	
	var texture_path = PROP_TEXTURES.get("rock_small", "")
	if ResourceLoader.exists(texture_path):
		sprite.texture = load(texture_path)
		parent.add_child(sprite)
		return true
	return false

func create_torches_along_path():
	"""Initialize torches container. Actual torches are spawned per-chunk."""
	# Create main Torches container node (torches will be added as children when chunks load)
	var torches_node = get_node_or_null("Torches")
	if not torches_node:
		torches_node = Node2D.new()
		torches_node.name = "Torches"
		torches_node.z_index = 5  # Above most other elements
		add_child(torches_node)

	print("🔥 Torches container initialized (torches spawn per-chunk)")

func spawn_torches_for_chunk(chunk_id: int, path_points: Array, parent: Node2D) -> void:
	"""Spawn torches along a chunk's path (called from spawn_path_for_chunk)"""
	var torches_node = get_node_or_null("Torches")
	if not torches_node:
		torches_node = Node2D.new()
		torches_node.name = "Torches"
		torches_node.z_index = 5
		add_child(torches_node)

	# Check if torches already exist
	var chunk_torches_name = "TorchesChunk_%d" % chunk_id
	if torches_node.get_node_or_null(chunk_torches_name):
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = 77777 + chunk_id

	# Create torch container for this chunk
	var chunk_torches = Node2D.new()
	chunk_torches.name = chunk_torches_name
	torches_node.add_child(chunk_torches)

	var torch_count = place_torches_along_path(path_points, chunk_torches, rng)
	print("🔥 Spawned %d torches for chunk %d" % [torch_count, chunk_id])

func despawn_torches_for_chunk(chunk_id: int) -> void:
	"""Despawn torches for a specific chunk"""
	var torches_node = get_node_or_null("Torches")
	if not torches_node:
		return

	var chunk_torches_name = "TorchesChunk_%d" % chunk_id
	var chunk_torches = torches_node.get_node_or_null(chunk_torches_name)
	if chunk_torches:
		chunk_torches.queue_free()

func place_torches_along_path(path_positions: Array, parent: Node2D, rng: RandomNumberGenerator) -> int:
	"""Place torches along a path, returns count placed"""
	if path_positions.size() < 2:
		return 0

	# Calculate total path length
	var total_path_length = 0.0
	for i in range(path_positions.size() - 1):
		total_path_length += path_positions[i].distance_to(path_positions[i + 1])

	# Torch placement with sparse spacing (50% fewer torches for performance)
	var base_spacing = 1700.0  # Torch every ~1700px (doubled from 850px)
	var torch_count = 0
	var current_distance = 0.0
	var next_torch_at = base_spacing

	# Walk along path and place torches
	var segment_index = 0

	while next_torch_at < total_path_length and segment_index < path_positions.size() - 1:
		var start_pos = path_positions[segment_index]
		var end_pos = path_positions[segment_index + 1]
		var segment_length = start_pos.distance_to(end_pos)
		var segment_end_distance = current_distance + segment_length

		while next_torch_at <= segment_end_distance and next_torch_at < total_path_length:
			var distance_into_segment = next_torch_at - current_distance
			var t = distance_into_segment / segment_length
			var torch_pos = start_pos.lerp(end_pos, t)

			# Add perpendicular offset to stagger torches
			var direction = (end_pos - start_pos).normalized()
			var perpendicular = Vector2(-direction.y, direction.x)
			var offset = rng.randf_range(-180.0, 180.0)
			torch_pos += perpendicular * offset

			# Create torch
			var torch_script = load("res://scripts/systems/Torch.gd")
			if torch_script:
				var torch = Node2D.new()
				torch.set_script(torch_script)
				torch.name = "Torch_" + str(torch_count)
				torch.position = torch_pos
				parent.add_child(torch)
				torch_count += 1

			next_torch_at += rng.randf_range(1400.0, 2000.0)  # Sparse torches (doubled from 700-1000)

		current_distance = segment_end_distance
		segment_index += 1

	return torch_count

func spawn_all_enemies():
	"""Initialize chunk-based enemy spawn manager

	The system supports two spawn modes:
	1. Manual spawn markers (Marker2D nodes with enemy_level metadata)
	2. Procedural spawns (fills chunks to target count based on X position level bands)

	Manual markers take priority - procedural spawns fill remaining capacity.
	"""
	# In multiplayer, only server manages enemies
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Collect manual spawn markers from the scene
	var spawn_markers = collect_spawn_markers()
	print("📍 Found %d manual spawn markers in scene" % spawn_markers.size())

	# Create and initialize ChunkAwareSpawnManager
	const ChunkAwareSpawnManager = preload("res://scripts/systems/ChunkAwareSpawnManager.gd")
	spawn_manager = ChunkAwareSpawnManager.new()
	spawn_manager.name = "ChunkAwareSpawnManager"
	add_child(spawn_manager)

	# Hook up NetworkEnemyManager
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		spawn_manager.network_enemy_manager = network_enemy_mgr
		network_enemy_mgr.game_world = self
		print("🌐 NetworkEnemyManager connected to SpawnManager")

	# Initialize with chunk system and manual markers
	spawn_manager.initialize(self, chunk_prop_system, spawn_markers)

func collect_spawn_markers() -> Array:
	"""Collect all enemy spawn markers (don't spawn yet - SpawnManager handles that)

	HOW TO USE:
	1. In Godot editor, add Marker2D nodes as children of GameWorld
	2. Name them like: 'EnemySpawn_L3' (for level 3)
	3. Set metadata on the marker:
	   - 'enemy_level' (int): Enemy level (required)
	   - 'enemy_type' (String): Optional, defaults to 'skeleton'
	   - 'aggro_range' (float): Optional aggro radius override

	Example in editor:
	- Create Marker2D node
	- Name: EnemySpawn_L1_Noob1
	- In Inspector > Node > Meta: Add 'enemy_level' = 1

	Returns: Array of spawn marker nodes
	"""
	var spawn_markers = []

	# Find all Marker2D children with enemy spawn data
	# Matches: "EnemySpawn*" or "L<num>_*" (level-prefixed markers from radial pattern tool)
	for child in get_children():
		if not (child is Marker2D):
			continue

		# Check if this is a spawn marker
		var is_spawn_marker = false
		if child.name.begins_with("EnemySpawn"):
			is_spawn_marker = true
		elif child.name.begins_with("L") and child.name.length() > 1:
			# Check if second character is a digit (L1_*, L2_*, etc.)
			var second_char = child.name.substr(1, 1)
			if second_char.is_valid_int():
				is_spawn_marker = true

		if not is_spawn_marker:
			continue

		# Read properties from exported vars (if ManualEnemySpawn) or metadata
		var level = 1
		var enemy_type = "skeleton"
		var aggro_override = 150.0

		# Try reading from exported properties first (ManualEnemySpawn tool script)
		if child.has_method("get"):
			if "enemy_level" in child:
				level = child.get("enemy_level")
			if "enemy_type" in child:
				enemy_type = child.get("enemy_type")
			if "aggro_range" in child:
				aggro_override = child.get("aggro_range")

		# Fallback to metadata (plain Marker2D)
		if child.has_meta("enemy_level"):
			level = child.get_meta("enemy_level", 1)
		if child.has_meta("enemy_type"):
			enemy_type = child.get_meta("enemy_type", "skeleton")
		if child.has_meta("aggro_range"):
			aggro_override = child.get_meta("aggro_range", 150.0)

		# Store metadata on marker for SpawnManager
		child.set_meta("enemy_level", level)
		child.set_meta("enemy_type", enemy_type)
		child.set_meta("aggro_range", aggro_override)

		spawn_markers.append(child)

	return spawn_markers

func analyze_spawn_pattern(children: Array) -> void:
	"""Analyze manually placed enemy patterns to learn density, level progression, and distribution"""
	var spawn_data = []
	var campfire_pos = CAMPFIRE_POS

	# Collect all manual spawn data
	for child in children:
		if child is Marker2D and child.name.begins_with("EnemySpawn"):
			var level = 1
			if child.has_method("get") and "enemy_level" in child:
				level = child.get("enemy_level")
			else:
				level = child.get_meta("enemy_level", 1)

			var distance_from_campfire = child.global_position.distance_to(campfire_pos)
			var distance_from_path = abs(child.global_position.y)  # Approximate distance from y=0 path

			spawn_data.append({
				"pos": child.global_position,
				"level": level,
				"dist_from_campfire": distance_from_campfire,
				"dist_from_path": distance_from_path
			})

	if spawn_data.is_empty():
		return

	# Calculate statistics
	var total_spawns = spawn_data.size()
	var avg_level = 0.0
	var avg_dist_from_campfire = 0.0
	var avg_dist_from_path = 0.0
	var min_distance_between = 999999.0

	# Level buckets by distance from campfire
	var level_by_distance = {}

	for data in spawn_data:
		avg_level += data["level"]
		avg_dist_from_campfire += data["dist_from_campfire"]
		avg_dist_from_path += data["dist_from_path"]

		# Calculate distance buckets (every 500px)
		var bucket = int(data["dist_from_campfire"] / 500) * 500
		if not level_by_distance.has(bucket):
			level_by_distance[bucket] = []
		level_by_distance[bucket].append(data["level"])

	avg_level /= total_spawns
	avg_dist_from_campfire /= total_spawns
	avg_dist_from_path /= total_spawns

	# Calculate minimum distance between spawns
	for i in range(spawn_data.size()):
		for j in range(i + 1, spawn_data.size()):
			var dist = spawn_data[i]["pos"].distance_to(spawn_data[j]["pos"])
			min_distance_between = min(min_distance_between, dist)

	# Calculate average level per distance bucket
	var level_progression = {}
	for bucket in level_by_distance.keys():
		var levels = level_by_distance[bucket]
		var sum = 0
		for level in levels:
			sum += level
		level_progression[bucket] = sum / float(levels.size())

	# Print analysis
	print("   📈 Pattern Analysis:")
	print("      Total manual spawns: %d" % total_spawns)
	print("      Avg level: %.1f" % avg_level)
	print("      Avg distance from campfire: %.0fpx" % avg_dist_from_campfire)
	print("      Avg distance from path: %.0fpx" % avg_dist_from_path)
	print("      Min spacing between spawns: %.0fpx" % min_distance_between)
	print("      Level progression by distance:")

	var sorted_buckets = level_progression.keys()
	sorted_buckets.sort()
	for bucket in sorted_buckets:
		print("         %d-%dpx: Level %.1f (n=%d)" % [bucket, bucket + 500, level_progression[bucket], level_by_distance[bucket].size()])

	# Store pattern data for procedural generation
	set_meta("spawn_pattern", {
		"avg_dist_from_path": avg_dist_from_path,
		"min_spacing": max(min_distance_between, 150.0),  # At least 150px
		"level_progression": level_progression,
		"manual_count": total_spawns,
		"campfire_pos": campfire_pos
	})

func spawn_training_dummy():
	"""Spawn a training dummy near the campfire for combat practice"""
	# In multiplayer, only server spawns - clients receive via RPC
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		print("🎯 Training Dummy: Client skipping spawn (server will sync)")
		return

	const DUMMY_SCENE = preload("res://scenes/training/training_dummy.tscn")

	# Spawn dummy north of campfire (negative Y = north)
	var dummy_pos = CAMPFIRE_POS + Vector2(0, -280)  # North of campfire in cleared area

	var dummy = DUMMY_SCENE.instantiate()
	dummy.global_position = dummy_pos
	dummy.name = "TrainingDummy"
	add_child(dummy)

	# Register with NetworkEnemyManager for multiplayer sync
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(dummy)
		# Broadcast spawn to clients
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_training_dummy_on_clients.rpc(network_id, dummy_pos)
			print("🎯 Training Dummy registered with network_id: ", network_id)

	print("🎯 Training Dummy spawned at: ", dummy_pos)

	# Spawn starter skeletons near the clearing for tutorial
	spawn_tutorial_skeletons()

func spawn_tutorial_skeletons():
	"""Spawn a few level 1-2 skeletons just outside the campfire clearing for new players"""
	# In multiplayer, only server spawns
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")
	var campfire_pos = CAMPFIRE_POS

	# Spawn positions in a ring just outside the safe zone (600 radius)
	# Place them at 650-850 radius so they're visible but not in the clearing
	var spawn_positions = [
		# Level 1 skeletons (10 total, spread around) - noob practice targets
		{"offset": Vector2(700, -100), "level": 1},   # East-north
		{"offset": Vector2(700, 100), "level": 1},    # East-south
		{"offset": Vector2(720, 0), "level": 1},      # East center
		{"offset": Vector2(-700, 0), "level": 1},     # West
		{"offset": Vector2(-680, 150), "level": 1},   # West-south
		{"offset": Vector2(-680, -150), "level": 1},  # West-north
		{"offset": Vector2(0, 680), "level": 1},      # South
		{"offset": Vector2(200, 660), "level": 1},    # South-east
		{"offset": Vector2(-200, 660), "level": 1},   # South-west
		{"offset": Vector2(0, -700), "level": 1},     # North
		# Level 2 skeletons (5 total, slightly further)
		{"offset": Vector2(800, -300), "level": 2},   # East-north far
		{"offset": Vector2(800, 300), "level": 2},    # East-south far
		{"offset": Vector2(-750, -200), "level": 2},  # West-north
		{"offset": Vector2(-750, 200), "level": 2},   # West-south
		{"offset": Vector2(0, -800), "level": 2},     # North far
	]

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var spawned_count = 0

	for spawn_data in spawn_positions:
		var spawn_pos = campfire_pos + spawn_data.offset

		var enemy = ENEMY_SCENE.instantiate()
		enemy.global_position = spawn_pos
		enemy.enemy_level = spawn_data.level
		enemy.name = "TutorialSkeleton_%d" % spawned_count
		add_child(enemy)

		# Register with NetworkEnemyManager for multiplayer sync
		if network_enemy_mgr:
			var network_id = network_enemy_mgr.register_enemy(enemy)
			# Sync to NEARBY clients only (interest management)
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				network_enemy_mgr.spawn_enemy_for_nearby_clients(network_id, enemy)

		spawned_count += 1

	print("💀 Spawned %d tutorial skeletons around campfire clearing" % spawned_count)

func spawn_bone_clusters(parent: Node2D):
	"""Spawn clusters of bones and skulls, plus scattered individual bones everywhere"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12121212

	var clusters_placed = 0
	var scattered_placed = 0

	# PART 1: Spawn 60 dense bone clusters (ritual piles / skeletal remains)
	for i in range(60):
		var cluster_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Avoid campfire area
		var campfire_pos = CAMPFIRE_POS
		if cluster_pos.distance_to(campfire_pos) < 600:
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = cluster_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 150
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Create a cluster of 8-15 bones/skulls (denser piles)
		var num_items = rng.randi_range(8, 15)
		for j in range(num_items):
			var bone_types = ["skull", "bones"]
			var bone_type = bone_types[rng.randi() % bone_types.size()]

			# Position within cluster (30-120px radius for tighter piles)
			var angle = rng.randf() * TAU
			var distance = rng.randf_range(30, 120)
			var bone_pos = cluster_pos + Vector2(cos(angle), sin(angle)) * distance

			var prop_data = {
				"type": bone_type,
				"x": bone_pos.x,
				"y": bone_pos.y,
				"scale": rng.randf_range(0.7, 1.4),  # Varied sizes in clusters
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": 0,
				"id": 8000 + clusters_placed * 20 + j
			}
			create_prop_sprite(prop_data, parent)

		clusters_placed += 1

	# PART 2: Spawn scattered individual bones across the entire world
	# Much higher density to fill in empty spaces
	for i in range(400):
		var bone_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Avoid campfire area
		var campfire_pos = CAMPFIRE_POS
		if bone_pos.distance_to(campfire_pos) < 500:
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = bone_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 100
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Scattered bones can be anywhere (including near path for battle aftermath feel)
		# More bones than skulls for scattered (75% bones, 25% skulls)
		var bone_type = "bones" if rng.randf() < 0.75 else "skull"

		var prop_data = {
			"type": bone_type,
			"x": bone_pos.x,
			"y": bone_pos.y,
			"scale": rng.randf_range(0.4, 0.9),  # Smaller scattered bones
			"rotation": rng.randf() * TAU,
			"flip_h": rng.randf() < 0.5,
			"z_index": 0,
			"id": 9000 + scattered_placed
		}
		create_prop_sprite(prop_data, parent)
		scattered_placed += 1

	print("💀 Placed ", clusters_placed, " bone clusters + ", scattered_placed, " scattered bones")

func spawn_ground_cracks(parent: Node2D):
	"""Spawn large cracks in the dark ground areas"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 13131313

	var cracks_placed = 0

	# Spawn cracks throughout the world (MASSIVELY reduced for 60 FPS)
	for i in range(30):  # Reduced from 100
		var crack_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = crack_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 30
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Prefer cracks on the path and near clearings (broken ground)
		var campfire_pos = CAMPFIRE_POS
		var on_path = abs(crack_pos.y) < 200  # Near path
		var near_campfire = crack_pos.distance_to(campfire_pos) < 500  # Near campfire

		# Reduce clutter around campfire by 25%
		if near_campfire:
			if rng.randf() < 0.25:  # Skip 25% of cracks near campfire
				continue

		# 70% chance to skip if not on path or near campfire
		if not on_path and not near_campfire:
			if rng.randf() > 0.3:
				continue

		# Use both crack types
		var crack_types = ["ground_crack_1", "ground_crack_2"]
		var crack_type = crack_types[rng.randi() % crack_types.size()]

		# Mix of large and thin cracks (0.6-2.5 for variety)
		var scale = rng.randf_range(0.6, 2.5) if rng.randf() < 0.5 else rng.randf_range(1.5, 2.5)

		var prop_data = {
			"type": crack_type,
			"x": crack_pos.x,
			"y": crack_pos.y,
			"scale": scale,  # Mix of large (1.5-2.5) and thin (0.6-2.5) cracks
			"rotation": rng.randf() * TAU,
			"flip_h": rng.randf() < 0.5,
			"z_index": -1,  # Below other props
			"id": 9000 + i
		}
		if create_prop_sprite(prop_data, parent):
			cracks_placed += 1

	print("🕳️ Placed ", cracks_placed, " ground cracks")

func spawn_dead_vegetation(parent: Node2D):
	"""Spawn sparse dead bushes/vegetation (using ash piles)"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 14141414

	var vegetation_placed = 0

	# Spawn 80 dead bushes throughout the world (dense population)
	for i in range(80):
		var veg_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Avoid campfire area
		var campfire_pos = CAMPFIRE_POS
		if veg_pos.distance_to(campfire_pos) < 600:
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = veg_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 30
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Avoid the main path
		if is_position_on_path(veg_pos, 150.0):
			continue

		# Use ash_pile as dead bush
		var prop_data = {
			"type": "ash_pile",
			"x": veg_pos.x,
			"y": veg_pos.y,
			"scale": rng.randf_range(1.0, 2.0),  # Varied sizes
			"rotation": 0.0,  # No rotation for vegetation
			"flip_h": rng.randf() < 0.5,
			"z_index": -2,  # Below rocks (0) so ash piles don't render on top
			"id": 10000 + i
		}

		# Tint with slight brown for dead vegetation feel
		if create_prop_sprite(prop_data, parent):
			# Get the sprite and add brown tint
			var prop_node = parent.get_node_or_null("ash_pile_" + str(10000 + i))
			if prop_node and prop_node.has_node("Sprite"):
				var sprite = prop_node.get_node("Sprite")
				sprite.modulate = Color(0.6, 0.5, 0.3)  # Brown/tan dead vegetation
			vegetation_placed += 1

	print("🌾 Placed ", vegetation_placed, " dead vegetation (sparse coverage)")

func create_ambient_particles():
	"""Create floating ash/dust particles for atmosphere"""
	var particles = GPUParticles2D.new()
	particles.name = "AmbientAsh"
	particles.z_index = 450  # Above combat effects, below UI/labels
	particles.amount = 25  # Reduced from 50
	particles.lifetime = 8.0
	particles.preprocess = 2.0
	particles.explosiveness = 0.0
	particles.randomness = 1.0
	particles.fixed_fps = 30
	particles.local_coords = false  # World space so particles don't move with camera

	# Create process material for particle behavior
	var material = ParticleProcessMaterial.new()

	# Emission
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(800, 600, 0)  # Large area around player

	# Movement
	material.direction = Vector3(0, -1, 0)  # Float upward
	material.spread = 45.0
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 30.0
	material.gravity = Vector3(0, -15, 0)  # Slight upward drift

	# Damping (slow down over time)
	material.damping_min = 0.5
	material.damping_max = 1.0

	# Scale (very small particles)
	material.scale_min = 0.3  # Reduced from 0.5
	material.scale_max = 0.8  # Reduced from 1.5

	# Color (light grey ash)
	material.color = Color(0.7, 0.7, 0.7, 0.15)  # Reduced opacity from 0.3 to 0.15

	# Fade in/out
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 0))  # Fade in
	gradient.add_point(0.2, Color(1, 1, 1, 1))  # Full opacity
	gradient.add_point(0.8, Color(1, 1, 1, 1))  # Stay visible
	gradient.add_point(1.0, Color(1, 1, 1, 0))  # Fade out
	var gradient_texture = GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Create particle texture (small circular gradient)
	var particle_gradient = Gradient.new()
	particle_gradient.set_color(0, Color(1, 1, 1, 1))  # White center
	particle_gradient.set_color(1, Color(0, 0, 0, 0))  # Transparent edge
	var particle_texture = GradientTexture2D.new()
	particle_texture.gradient = particle_gradient
	particle_texture.width = 32
	particle_texture.height = 32
	particle_texture.fill = GradientTexture2D.FILL_RADIAL
	particle_texture.fill_from = Vector2(0.5, 0.5)
	particles.texture = particle_texture

	# Follow player
	var player = get_tree().get_first_node_in_group("player")
	if player:
		particles.global_position = player.global_position

	add_child(particles)

	print("💨 Ambient ash particles created")

func spawn_lava_pools():
	"""Create glowing lava pools scattered across the dreadland"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 15151515

	var pools_placed = 0

	# Spawn 60 lava pools throughout the world (ground about to erupt!)
	for i in range(60):
		var pool_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Avoid campfire area
		var campfire_pos = CAMPFIRE_POS
		if pool_pos.distance_to(campfire_pos) < 800:
			continue

		# Avoid spawning on the main path
		if is_position_on_path(pool_pos, 200.0):
			continue

		# Check if overlaps with existing pools
		var overlaps = false
		for existing_pool in lava_pool_positions:
			var dist = pool_pos.distance_to(existing_pool.pos)
			var combined_radius = (existing_pool.size / 2) * max(existing_pool.elongation_x, existing_pool.elongation_y) + 30
			if dist < combined_radius:
				overlaps = true
				break
		if overlaps:
			continue

		# Random size and shape for variety
		var pool_size = rng.randf_range(60, 200)  # Wider size range

		# 30% chance for perfect circle, otherwise elongated
		var elongation_x = 1.0
		var elongation_y = 1.0
		var pool_rotation = 0.0

		if rng.randf() > 0.3:  # 70% elongated
			elongation_x = rng.randf_range(0.8, 1.25)  # Subtle horizontal stretch (stay rounded)
			elongation_y = rng.randf_range(0.8, 1.25)  # Subtle vertical stretch (stay rounded)
			pool_rotation = rng.randf() * TAU  # Random rotation for elongated pools

		# Create lava pool node
		var lava_pool = Node2D.new()
		lava_pool.name = "LavaPool%d" % i
		lava_pool.position = pool_pos
		lava_pool.rotation = pool_rotation  # Rotate elongated pools randomly
		lava_pool.z_index = -3  # Above ground, below props

		# Add flowing animation script
		var animation_script = load("res://scripts/effects/LavaPoolAnimation.gd")
		lava_pool.set_script(animation_script)

		# Create cracks radiating from pool (eruption crater effect)
		var num_cracks = rng.randi_range(4, 8)  # Fewer cracks for subtler effect
		for crack_i in range(num_cracks):
			var crack = Line2D.new()
			crack.width = rng.randf_range(1.5, 3.5)  # Vary crack thickness
			crack.default_color = Color(0.03, 0.03, 0.03, rng.randf_range(0.6, 0.9))  # Very dark cracks (neutral)
			crack.joint_mode = Line2D.LINE_JOINT_SHARP
			crack.begin_cap_mode = Line2D.LINE_CAP_NONE
			crack.end_cap_mode = Line2D.LINE_CAP_NONE
			crack.antialiased = false  # Crisp pixel-art style

			# Start crack at pool edge
			var angle = (float(crack_i) / num_cracks) * TAU + rng.randf_range(-0.2, 0.2)
			var start_radius = (pool_size / 2) + 8  # Just outside the pool
			var start_x = cos(angle) * start_radius * elongation_x
			var start_y = sin(angle) * start_radius * elongation_y

			# Crack extends outward with random length (half as long)
			var crack_length = rng.randf_range(pool_size * 0.2, pool_size * 0.6)
			var num_segments = rng.randi_range(3, 6)  # Jagged crack with multiple segments

			var points = PackedVector2Array()
			points.append(Vector2(start_x, start_y))

			# Create jagged crack path
			var current_angle = angle
			var current_distance = start_radius
			for seg in range(num_segments):
				# Add some angular deviation for jagged look
				current_angle += rng.randf_range(-0.3, 0.3)
				current_distance += crack_length / num_segments

				var seg_x = cos(current_angle) * current_distance * elongation_x
				var seg_y = sin(current_angle) * current_distance * elongation_y
				points.append(Vector2(seg_x, seg_y))

			crack.points = points
			lava_pool.add_child(crack)

		# Create multiple soft borders for gradual blending to ground
		# Add these BEFORE gradient layers so they render underneath as shadows

		# Outer border - very subtle
		var outer_border = Polygon2D.new()
		var outer_vertices = PackedVector2Array()
		for j in range(64):
			var angle = (float(j) / 64) * TAU
			var radius = (pool_size / 2) + 15  # Wider
			var x = cos(angle) * radius * elongation_x
			var y = sin(angle) * radius * elongation_y
			outer_vertices.append(Vector2(x, y))
		outer_border.polygon = outer_vertices
		outer_border.color = Color(0.13, 0.13, 0.13, 0.3)  # Match ground color, very transparent (neutral)
		lava_pool.add_child(outer_border)

		# Middle border - medium blend
		var mid_border = Polygon2D.new()
		var mid_vertices = PackedVector2Array()
		for j in range(64):
			var angle = (float(j) / 64) * TAU
			var radius = (pool_size / 2) + 10
			var x = cos(angle) * radius * elongation_x
			var y = sin(angle) * radius * elongation_y
			mid_vertices.append(Vector2(x, y))
		mid_border.polygon = mid_vertices
		mid_border.color = Color(0.10, 0.10, 0.10, 0.5)  # Darker, semi-transparent (neutral)
		lava_pool.add_child(mid_border)

		# Inner border - darkest edge
		var inner_border = Polygon2D.new()
		var inner_vertices = PackedVector2Array()
		for j in range(64):
			var angle = (float(j) / 64) * TAU
			var radius = (pool_size / 2) + 5
			var x = cos(angle) * radius * elongation_x
			var y = sin(angle) * radius * elongation_y
			inner_vertices.append(Vector2(x, y))
		inner_border.polygon = inner_vertices
		inner_border.color = Color(0.05, 0.05, 0.05, 0.7)  # Very dark, but still transparent (neutral)
		lava_pool.add_child(inner_border)

		# Create smooth gradient using 10 layered circles with irregular edges
		# Define gradient colors from outer (red) to inner (bright orange) - deep lava colors
		var layer_data = [
			{"size": 1.00, "color": Color(0.7, 0.15, 0.0, 1.0)},   # Deep dark red (solid base)
			{"size": 0.90, "color": Color(0.8, 0.2, 0.0, 0.8)},    # Dark red
			{"size": 0.80, "color": Color(0.9, 0.25, 0.0, 0.7)},   # Red
			{"size": 0.70, "color": Color(1.0, 0.3, 0.0, 0.65)},   # Red
			{"size": 0.60, "color": Color(1.0, 0.35, 0.02, 0.6)},  # Red-orange
			{"size": 0.50, "color": Color(1.0, 0.42, 0.05, 0.55)}, # Orange-red
			{"size": 0.40, "color": Color(1.0, 0.5, 0.08, 0.5)},   # Orange
			{"size": 0.30, "color": Color(1.0, 0.58, 0.1, 0.45)},  # Bright orange
			{"size": 0.20, "color": Color(1.0, 0.65, 0.12, 0.5)},  # Brighter orange
			{"size": 0.12, "color": Color(1.0, 0.7, 0.15, 0.6)}    # Deep bright orange center (no yellow!)
		]

		for layer in layer_data:
			var circle = Polygon2D.new()
			var vertices = PackedVector2Array()

			# Create irregular circle with random perturbations
			for j in range(64):
				var angle = (float(j) / 64) * TAU
				var radius = pool_size / 2 * layer.size

				# Add significant irregularity to each vertex (breaks up rings)
				radius += rng.randf_range(-4, 4)

				# Apply elongation for oval shapes
				var x = cos(angle) * radius * elongation_x
				var y = sin(angle) * radius * elongation_y

				vertices.append(Vector2(x, y))

			circle.polygon = vertices
			circle.color = layer.color
			lava_pool.add_child(circle)

		# Add PointLight2D for glowing effect (scales with pool size)
		var light = PointLight2D.new()
		light.name = "LavaLight"
		light.enabled = true
		light.position = Vector2.ZERO
		light.color = Color(1.0, 0.4, 0.05, 1.0)  # Deep orange-red glow
		light.energy = rng.randf_range(1.2, 1.8)  # Base intensity
		light.blend_mode = PointLight2D.BLEND_MODE_ADD  # Additive blending for glow
		light.range_z_min = -10
		light.range_z_max = 10
		light.shadow_enabled = false

		# Store base energy for time-based scaling
		light.set_meta("base_energy", light.energy)

		# Create gradient texture for light falloff
		var light_gradient = Gradient.new()
		light_gradient.set_color(0, Color(1, 1, 1, 1))
		light_gradient.set_color(1, Color(0, 0, 0, 0))
		var light_texture = GradientTexture2D.new()
		light_texture.gradient = light_gradient
		light_texture.width = 256
		light_texture.height = 256
		light_texture.fill = GradientTexture2D.FILL_RADIAL
		light_texture.fill_from = Vector2(0.5, 0.5)
		light.texture = light_texture

		# Scale light based on average of elongation (bigger pools = bigger glow)
		var avg_elongation = (elongation_x + elongation_y) / 2.0
		var base_scale = (pool_size / 80.0) * avg_elongation
		light.texture_scale = base_scale
		light.set_meta("base_scale", base_scale)

		# Add to lava_lights group for time-based updates
		light.add_to_group("lava_lights")

		lava_pool.add_child(light)

		# Add heat particles (embers rising) - sharper and more defined
		var particles = GPUParticles2D.new()
		particles.amount = int(pool_size / 8)  # More particles for bigger pools
		particles.lifetime = 2.5
		particles.explosiveness = 0.0
		particles.randomness = 0.7
		particles.local_coords = false

		var material = ParticleProcessMaterial.new()
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		# Box emission with elongation to match pool shape
		var emission_width = (pool_size / 3) * elongation_x
		var emission_height = (pool_size / 3) * elongation_y
		material.emission_box_extents = Vector3(emission_width, emission_height, 0)
		material.direction = Vector3(0, -1, 0)  # Rise upward
		material.spread = 12.0  # Very tight spread
		material.initial_velocity_min = 25.0
		material.initial_velocity_max = 50.0
		material.gravity = Vector3(0, -28, 0)  # Float upward faster
		material.scale_min = 1.0  # Smaller, tighter particles
		material.scale_max = 2.0

		# Hot orange embers that fade to red (realistic lava)
		material.color = Color(1.0, 0.65, 0.1, 1.0)  # Bright orange embers

		# Color over lifetime: bright orange -> red-orange -> red -> fade
		var particle_gradient = Gradient.new()
		particle_gradient.add_point(0.0, Color(1.0, 0.7, 0.15, 0))  # Fade in bright orange
		particle_gradient.add_point(0.08, Color(1.0, 0.65, 0.12, 1))  # Full bright orange
		particle_gradient.add_point(0.35, Color(1.0, 0.5, 0.08, 1))  # Orange
		particle_gradient.add_point(0.65, Color(0.95, 0.3, 0.05, 1))  # Red-orange
		particle_gradient.add_point(1.0, Color(0.6, 0.15, 0.0, 0))  # Fade to dark red
		var particle_gradient_tex = GradientTexture1D.new()
		particle_gradient_tex.gradient = particle_gradient
		material.color_ramp = particle_gradient_tex

		particles.process_material = material

		# Crisp pixel-art style texture - very small with hard edges
		var ember_gradient = Gradient.new()
		ember_gradient.set_color(0, Color(1, 1, 1, 1))  # Solid bright center
		ember_gradient.set_color(0.7, Color(1, 1, 1, 1))  # Hold solid longer
		ember_gradient.set_color(0.85, Color(1, 1, 1, 0.5))  # Sharp falloff
		ember_gradient.set_color(1, Color(0, 0, 0, 0))  # Transparent edge
		var ember_texture = GradientTexture2D.new()
		ember_texture.gradient = ember_gradient
		ember_texture.width = 4  # Tiny = crisp pixel-art look
		ember_texture.height = 4
		ember_texture.fill = GradientTexture2D.FILL_RADIAL
		ember_texture.fill_from = Vector2(0.5, 0.5)
		particles.texture = ember_texture

		lava_pool.add_child(particles)

		# Add damage area (tighter circle - 60% of pool size so edges are safe)
		var damage_area = Area2D.new()
		damage_area.collision_layer = 0  # Don't exist on any layer
		damage_area.collision_mask = 1  # Detect layer 1 (player)

		# Add damage script
		var damage_script = load("res://scripts/effects/LavaDamage.gd")
		damage_area.set_script(damage_script)

		# Create circular collision shape (60% of pool size)
		var collision_shape = CollisionShape2D.new()
		var circle_shape = CircleShape2D.new()
		# Use 60% of the smaller dimension to create tight circle
		var damage_radius = (pool_size / 2) * 0.6 * min(elongation_x, elongation_y)
		circle_shape.radius = damage_radius
		collision_shape.shape = circle_shape

		damage_area.add_child(collision_shape)
		lava_pool.add_child(damage_area)

		add_child(lava_pool)

		# Store pool position and size for collision avoidance
		lava_pool_positions.append({
			"pos": pool_pos,
			"size": pool_size,
			"elongation_x": elongation_x,
			"elongation_y": elongation_y
		})

		pools_placed += 1

	print("🔥 Placed ", pools_placed, " lava pools with glowing effects")

## ============================================
## CORPSE LOOT SYSTEM
## ============================================

func setup_corpse_loot_system() -> void:
	"""Setup handlers for corpse looting system"""
	for enemy in get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES):
		if enemy.has_signal("corpse_clicked"):
			enemy.corpse_clicked.connect(_on_corpse_clicked)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	"""Connect to newly spawned enemies"""
	if node.is_in_group(Constants.GROUP_ENEMIES):
		if node.has_signal("corpse_clicked"):
			if not node.corpse_clicked.is_connected(_on_corpse_clicked):
				node.corpse_clicked.connect(_on_corpse_clicked)
				print("🌐 Connected corpse_clicked for: %s" % node.name)

func _on_corpse_clicked(corpse) -> void:
	"""Handle corpse being clicked - open loot UI with AOE aggregation"""
	if not is_instance_valid(corpse):
		return

	# Get nearby corpses for AOE looting (if enemy supports it)
	var nearby_corpses: Array = []
	if corpse.has_method("get_nearby_corpses"):
		nearby_corpses = corpse.get_nearby_corpses(CorpseState.AOE_LOOT_RADIUS)
	_create_loot_ui_deferred.call_deferred(corpse, nearby_corpses)

func _create_loot_ui_deferred(corpse, nearby_corpses: Array) -> void:
	"""Create loot UI from scene file"""
	var loot_scene = load("res://scenes/ui/loot_body_ui.tscn")
	if not loot_scene:
		push_error("Failed to load loot UI scene")
		return

	var loot_ui = loot_scene.instantiate()
	if not loot_ui:
		push_error("Failed to instantiate loot UI")
		return

	get_tree().root.add_child(loot_ui)
	loot_ui.loot_ui_closed.connect(func(): loot_ui.queue_free())
	loot_ui.open_loot_ui(corpse, nearby_corpses)

# ========================
# UI RESTORATION
# ========================

func _restore_ui_autoloads():
	"""Restore UI autoloads that were hidden when returning to main menu"""
	# These are hidden in NetworkManager._return_to_main_menu()
	if QuestTrackerUI:
		QuestTrackerUI.visible = true
	if GroupUI:
		GroupUI.visible = true
		# Note: invite popup visibility is managed internally by GroupUI
	if BugReportUI:
		BugReportUI.visible = true
	if NotificationManager:
		var notif_canvas = NotificationManager.get_node_or_null("NotificationCanvas")
		if notif_canvas:
			notif_canvas.visible = true
	# Show minimap when entering game world
	if Minimap:
		Minimap.set_game_world(self)
		Minimap.show_minimap()

# ========================
# MULTIPLAYER FUNCTIONS
# ========================

func _setup_multiplayer():
	"""Initialize multiplayer functionality"""
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] _setup_multiplayer() called")
		print("   has_multiplayer_peer: %s" % multiplayer.has_multiplayer_peer())
		print("   unique_id: %s" % multiplayer.get_unique_id())
		print("   is_server: %s" % multiplayer.is_server())

	# Connect to NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.player_authenticated.connect(_on_player_authenticated)

	# If we're already connected (came from menu), spawn players
	if multiplayer.has_multiplayer_peer():
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] Multiplayer active - calling _spawn_initial_players deferred")
		call_deferred("_spawn_initial_players")

func _spawn_initial_players():
	"""Spawn all connected players"""
	var my_id = multiplayer.get_unique_id()
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] _spawn_initial_players() called, my_id=%d, is_server=%s" % [my_id, multiplayer.is_server()])
		print("   Current players dict: %s" % str(players.keys()))

	# Check if not already spawned
	if not players.has(my_id):
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] Spawning local player %d" % my_id)

		# Check if returning from Trading Hub - use hub exit position
		var saved_pos = Vector2.ZERO
		var hub_manager = get_node_or_null("/root/TradingHubManager")
		var _restore_hub_state = false
		if hub_manager and hub_manager.is_returning_from_hub():
			# Player is returning from hub - spawn near tunnel entrance
			saved_pos = hub_manager.get_origin_spawn_position()
			_restore_hub_state = true
			if OS.is_debug_build():
				print("🚪 [PLAYER DEBUG] Returning from hub, spawning at tunnel: %s" % saved_pos)
			# Clear the flag so next spawn uses normal logic
			hub_manager.clear_returning_flag()
			# Restore zone music (hub music was playing)
			if SoundManager and SoundManager.has_method("play_game_music"):
				SoundManager.stop_game_music()  # Stop hub music first
				SoundManager.play_game_music(-12.0)
				print("🎵 Restored zone music after hub exit")
		elif not NetworkManager.is_guest and DatabaseManager:
			# Get saved position for authenticated players
			var username = NetworkManager.local_player_data.get("username", "")
			if not username.is_empty():
				saved_pos = DatabaseManager.get_saved_position(username)
				if saved_pos != Vector2.ZERO and OS.is_debug_build():
					print("📍 [PLAYER DEBUG] Restoring saved position: %s" % saved_pos)

		spawn_player(my_id, saved_pos)

		# Restore player state if returning from hub
		if _restore_hub_state and hub_manager and hub_manager.has_preserved_state() and players.has(my_id):
			hub_manager.restore_player_state(players[my_id])

		# Apply saved data to game systems after player spawns
		if not NetworkManager.is_guest and DatabaseManager:
			var username = NetworkManager.local_player_data.get("username", "")
			if not username.is_empty() and players.has(my_id):
				# Defer to ensure player is fully ready
				call_deferred("_apply_saved_data_to_player", username, my_id)
		else:
			# Guest player - still show tutorial
			if OS.is_debug_build():
				print("📚 [Tutorial] Guest player detected, starting tutorial...")
			call_deferred("_start_guest_tutorial", my_id)
	else:
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] Player %d already in dict, skipping spawn" % my_id)

	# Server handles spawning for connected players
	if multiplayer.is_server():
		var connected = NetworkManager.get_player_list()
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] Server - connected players: %s" % str(connected))
		for player_id in connected:
			if player_id != my_id and not players.has(player_id):
				if OS.is_debug_build():
					print("🔍 [PLAYER DEBUG] Server spawning remote player %d" % player_id)
				# Get player name from connected_players
				var player_info = NetworkManager.connected_players.get(player_id, {})
				var player_name = player_info.get("name", "")
				var is_guest = false
				if NetworkManager.authenticated_players.has(player_id):
					is_guest = NetworkManager.authenticated_players[player_id].get("is_guest", false)
				spawn_player(player_id, Vector2.ZERO, 0, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", false, "", player_name, is_guest)
	else:
		# Client: Request existing players from server
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] Client - requesting existing players from server")
		rpc_id(1, "_request_existing_players", my_id)

@rpc("any_peer", "reliable")
func _request_existing_players(_deprecated_id: int = 0):
	"""Client requests list of existing players from server"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		return

	# Security: Use actual sender ID, not client-provided parameter
	var requester_id = multiplayer.get_remote_sender_id()

	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] Server received request for existing players from %d" % requester_id)

	# Send all existing players to the requesting client
	for existing_id in players:
		if existing_id != requester_id:
			var existing_player = players[existing_id]
			if is_instance_valid(existing_player):
				# Get full appearance data from player
				var gender = 0
				var weapon_type = ""
				var feet_sprite = ""
				var legs_sprite = ""
				var chest_sprite = ""
				var arms_sprite = ""
				var hands_sprite = ""
				var head_sprite = ""
				var feet_forged_id = ""
				var legs_forged_id = ""
				var chest_forged_id = ""
				var arms_forged_id = ""
				var hands_forged_id = ""
				var head_forged_id = ""
				var weapon_glow_color = ""
				var weapon_effect_name = ""
				var weapon_theme = ""
				var weapon_is_forged = false
				var weapon_item_id = ""
				if existing_player.has_method("get_appearance_data"):
					var appearance = existing_player.get_appearance_data()
					gender = appearance.get("gender", 0)
					weapon_type = appearance.get("weapon_type", "")
					feet_sprite = appearance.get("feet_sprite", "")
					legs_sprite = appearance.get("legs_sprite", "")
					chest_sprite = appearance.get("chest_sprite", "")
					arms_sprite = appearance.get("arms_sprite", "")
					hands_sprite = appearance.get("hands_sprite", "")
					head_sprite = appearance.get("head_sprite", "")
					feet_forged_id = appearance.get("feet_forged_id", "")
					legs_forged_id = appearance.get("legs_forged_id", "")
					chest_forged_id = appearance.get("chest_forged_id", "")
					arms_forged_id = appearance.get("arms_forged_id", "")
					hands_forged_id = appearance.get("hands_forged_id", "")
					head_forged_id = appearance.get("head_forged_id", "")
					weapon_glow_color = appearance.get("weapon_glow_color", "")
					weapon_effect_name = appearance.get("weapon_effect_name", "")
					weapon_theme = appearance.get("weapon_theme", "")
					weapon_is_forged = appearance.get("weapon_is_forged", false)
					weapon_item_id = appearance.get("weapon_item_id", "")
				# Get player name, guest status, and tier from NetworkManager
				var p_name = NetworkManager.player_name if existing_id == 1 else ""
				var p_is_guest = NetworkManager.is_player_guest(existing_id)
				var p_tier = "initiate"
				if NetworkManager.authenticated_players.has(existing_id):
					p_name = NetworkManager.authenticated_players[existing_id].username
					var p_data = NetworkManager.authenticated_players[existing_id].get("player_data", {})
					var ashbane_data = p_data.get("ashbane", {})
					p_tier = ashbane_data.get("tier", "initiate")
				# Also check player's shield for current tier
				if existing_player.has_node("AllegianceShield"):
					p_tier = existing_player.get_node("AllegianceShield").current_tier
				if OS.is_debug_build():
					print("🔍 [PLAYER DEBUG] Sending player %d (pos: %s, gender: %d, weapon: %s, chest_forged: %s, weapon_forged: %s, name: %s, tier: %s) to client %d" % [existing_id, existing_player.global_position, gender, weapon_type, chest_forged_id, weapon_is_forged, p_name, p_tier, requester_id])
				rpc_id(requester_id, "spawn_player", existing_id, existing_player.global_position, gender, weapon_type, feet_sprite, legs_sprite, chest_sprite, arms_sprite, hands_sprite, head_sprite, feet_forged_id, legs_forged_id, chest_forged_id, arms_forged_id, hands_forged_id, head_forged_id, weapon_glow_color, weapon_effect_name, weapon_theme, weapon_is_forged, weapon_item_id, p_name, p_is_guest, p_tier)
			else:
				if OS.is_debug_build():
					print("🔍 [PLAYER DEBUG] Sending player %d (default pos) to client %d" % [existing_id, requester_id])
				var p_name2 = ""
				var p_is_guest2 = true
				var p_tier2 = "initiate"
				if NetworkManager.authenticated_players.has(existing_id):
					p_name2 = NetworkManager.authenticated_players[existing_id].username
					p_is_guest2 = NetworkManager.authenticated_players[existing_id].is_guest
					var p_data2 = NetworkManager.authenticated_players[existing_id].get("player_data", {})
					var ashbane_data2 = p_data2.get("ashbane", {})
					p_tier2 = ashbane_data2.get("tier", "initiate")
				rpc_id(requester_id, "spawn_player", existing_id, Vector2.ZERO, 0, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", false, "", p_name2, p_is_guest2, p_tier2)

func _on_player_connected(id: int):
	"""Handle new player connection - DON'T spawn yet, wait for authentication"""
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] _on_player_connected(%d) - is_server=%s (waiting for auth before spawn)" % [id, multiplayer.is_server()])
	# Don't spawn here - wait for _on_player_authenticated

func _on_player_authenticated(id: int, player_name: String):
	"""Handle player authentication complete - NOW spawn the player"""
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] _on_player_authenticated(%d, '%s') - is_server=%s" % [id, player_name, multiplayer.is_server()])
	if not multiplayer.is_server():
		return

	# Now spawn the authenticated player with their name
	var is_guest = false
	var player_tier = "initiate"
	if NetworkManager.authenticated_players.has(id):
		is_guest = NetworkManager.authenticated_players[id].get("is_guest", false)
		var p_data = NetworkManager.authenticated_players[id].get("player_data", {})
		var ashbane_data = p_data.get("ashbane", {})
		player_tier = ashbane_data.get("tier", "initiate")

	# Broadcast spawn to ALL peers (call_local ensures server also runs it)
	# Note: New client may not have game_world loaded yet, but they'll spawn
	# themselves in _spawn_initial_players when they load the scene
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] Broadcasting spawn_player RPC for %d (tier: %s) to all peers" % [id, player_tier])
	spawn_player.rpc(id, Vector2.ZERO, 0, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", false, "", player_name, is_guest, player_tier)

	# Tell the new player about existing players (but NOT themselves!)
	# Note: Client will also request this via _request_existing_players as a backup
	for existing_id in players:
		if existing_id != id:
			# Spawn existing player at their current position with full appearance
			var existing_player = players[existing_id]
			if is_instance_valid(existing_player):
				var gender = 0
				var weapon_type = ""
				var feet_sprite = ""
				var legs_sprite = ""
				var chest_sprite = ""
				var arms_sprite = ""
				var hands_sprite = ""
				var head_sprite = ""
				var feet_forged_id = ""
				var legs_forged_id = ""
				var chest_forged_id = ""
				var arms_forged_id = ""
				var hands_forged_id = ""
				var head_forged_id = ""
				var weapon_glow_color = ""
				var weapon_effect_name = ""
				var weapon_theme = ""
				var weapon_is_forged = false
				var weapon_item_id = ""
				if existing_player.has_method("get_appearance_data"):
					var appearance = existing_player.get_appearance_data()
					gender = appearance.get("gender", 0)
					weapon_type = appearance.get("weapon_type", "")
					feet_sprite = appearance.get("feet_sprite", "")
					legs_sprite = appearance.get("legs_sprite", "")
					chest_sprite = appearance.get("chest_sprite", "")
					arms_sprite = appearance.get("arms_sprite", "")
					hands_sprite = appearance.get("hands_sprite", "")
					head_sprite = appearance.get("head_sprite", "")
					feet_forged_id = appearance.get("feet_forged_id", "")
					legs_forged_id = appearance.get("legs_forged_id", "")
					chest_forged_id = appearance.get("chest_forged_id", "")
					arms_forged_id = appearance.get("arms_forged_id", "")
					hands_forged_id = appearance.get("hands_forged_id", "")
					head_forged_id = appearance.get("head_forged_id", "")
					weapon_glow_color = appearance.get("weapon_glow_color", "")
					weapon_effect_name = appearance.get("weapon_effect_name", "")
					weapon_theme = appearance.get("weapon_theme", "")
					weapon_is_forged = appearance.get("weapon_is_forged", false)
					weapon_item_id = appearance.get("weapon_item_id", "")
				# Get player name, guest status, and tier from NetworkManager
				var p_name = NetworkManager.player_name if existing_id == 1 else ""
				var p_is_guest = NetworkManager.is_player_guest(existing_id)
				var p_tier = "initiate"
				if NetworkManager.authenticated_players.has(existing_id):
					p_name = NetworkManager.authenticated_players[existing_id].username
					var p_data = NetworkManager.authenticated_players[existing_id].get("player_data", {})
					var ashbane_data = p_data.get("ashbane", {})
					p_tier = ashbane_data.get("tier", "initiate")
				# Also check player's shield for current tier
				if existing_player.has_node("AllegianceShield"):
					var shield = existing_player.get_node("AllegianceShield")
					if shield.has_method("get") and shield.get("current_tier"):
						p_tier = shield.current_tier
				if OS.is_debug_build():
					print("🔍 [PLAYER DEBUG] Sending existing player %d (gender: %d, weapon: %s, chest_forged: %s, weapon_forged: %s, name: %s, tier: %s) to new client %d" % [existing_id, gender, weapon_type, chest_forged_id, weapon_is_forged, p_name, p_tier, id])
				rpc_id(id, "spawn_player", existing_id, existing_player.global_position, gender, weapon_type, feet_sprite, legs_sprite, chest_sprite, arms_sprite, hands_sprite, head_sprite, feet_forged_id, legs_forged_id, chest_forged_id, arms_forged_id, hands_forged_id, head_forged_id, weapon_glow_color, weapon_effect_name, weapon_theme, weapon_is_forged, weapon_item_id, p_name, p_is_guest, p_tier)
			else:
				var p_name2 = ""
				var p_is_guest2 = true
				var p_tier2 = "initiate"
				if NetworkManager.authenticated_players.has(existing_id):
					p_name2 = NetworkManager.authenticated_players[existing_id].username
					p_is_guest2 = NetworkManager.authenticated_players[existing_id].is_guest
					var p_data2 = NetworkManager.authenticated_players[existing_id].get("player_data", {})
					var ashbane_data2 = p_data2.get("ashbane", {})
					p_tier2 = ashbane_data2.get("tier", "initiate")
				rpc_id(id, "spawn_player", existing_id, Vector2.ZERO, 0, "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", false, "", p_name2, p_is_guest2, p_tier2)

func _on_player_disconnected(id: int):
	"""Handle player disconnection"""
	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] _on_player_disconnected(%d)" % id)

	# Clean up spatial grid for AOI optimization
	SpatialGrid.remove_player(id)

	# Broadcast despawn to all peers so everyone removes the player
	if multiplayer.is_server():
		despawn_player.rpc(id)
	else:
		despawn_player(id)  # Client just removes locally

@rpc("any_peer", "call_local", "reliable")
func spawn_player(id: int, spawn_pos: Vector2 = Vector2.ZERO, gender: int = 0, weapon_type: String = "", feet_sprite: String = "", legs_sprite: String = "", chest_sprite: String = "", arms_sprite: String = "", hands_sprite: String = "", head_sprite: String = "", feet_forged_id: String = "", legs_forged_id: String = "", chest_forged_id: String = "", arms_forged_id: String = "", hands_forged_id: String = "", head_forged_id: String = "", weapon_glow_color: String = "", weapon_effect_name: String = "", weapon_theme: String = "", weapon_is_forged: bool = false, weapon_item_id: String = "", display_name: String = "", is_guest_player: bool = false, ashbane_tier: String = "initiate"):
	"""Spawn a player (local or remote)"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	# Security: Only server can spawn players via RPC (except local calls)
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:  # 0 = local call, 1 = server
		push_warning("spawn_player rejected from non-server peer %d" % sender_id)
		return

	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] spawn_player(%d) called on peer %d" % [id, multiplayer.get_unique_id()])
		print("   Appearance: gender=%d, weapon=%s, feet=%s, legs=%s, chest=%s, arms=%s, hands=%s, head=%s" % [gender, weapon_type, feet_sprite, legs_sprite, chest_sprite, arms_sprite, hands_sprite, head_sprite])
		print("   Forged IDs: feet=%s, legs=%s, chest=%s, arms=%s, hands=%s, head=%s" % [feet_forged_id, legs_forged_id, chest_forged_id, arms_forged_id, hands_forged_id, head_forged_id])
		print("   Weapon forged: %s, glow=%s, item_id=%s" % [weapon_is_forged, weapon_glow_color, weapon_item_id])
		print("   Name: %s (guest=%s) tier=%s" % [display_name, is_guest_player, ashbane_tier])
		print("   Current players: %s" % str(players.keys()))

	if players.has(id):
		if OS.is_debug_build():
			print("🔍 [PLAYER DEBUG] ⚠️ DUPLICATE BLOCKED - Player %d already in dict!" % id)
		return

	# Default spawn position near campfire
	if spawn_pos == Vector2.ZERO:
		spawn_pos = get_spawn_point()

	var player_scene = load("res://scenes/player/player.tscn")
	if not player_scene:
		push_error("Failed to load player scene!")
		return

	var player = player_scene.instantiate()
	player.name = "Player_" + str(id)
	player.set_multiplayer_authority(id)
	player.position = spawn_pos

	# Apply appearance data for remote players BEFORE adding to tree
	var is_local = (id == multiplayer.get_unique_id())
	if not is_local:
		# Set appearance before _ready() runs and creates the sprite
		if player.has_method("apply_appearance_data"):
			player.apply_appearance_data({
				"gender": gender,
				"weapon_type": weapon_type,
				"feet_sprite": feet_sprite,
				"legs_sprite": legs_sprite,
				"chest_sprite": chest_sprite,
				"arms_sprite": arms_sprite,
				"hands_sprite": hands_sprite,
				"head_sprite": head_sprite,
				"feet_forged_id": feet_forged_id,
				"legs_forged_id": legs_forged_id,
				"chest_forged_id": chest_forged_id,
				"arms_forged_id": arms_forged_id,
				"hands_forged_id": hands_forged_id,
				"head_forged_id": head_forged_id,
				"weapon_glow_color": weapon_glow_color,
				"weapon_effect_name": weapon_effect_name,
				"weapon_theme": weapon_theme,
				"weapon_is_forged": weapon_is_forged,
				"weapon_item_id": weapon_item_id
			})

	add_child(player)
	players[id] = player

	# ALL players (local AND remote) must be in "player" group for enemy AI to detect them
	player.add_to_group("player")

	if OS.is_debug_build():
		print("🔍 [PLAYER DEBUG] ✅ Player %d spawned at %s (local=%s)" % [id, spawn_pos, is_local])

	if is_local:
		local_player = player
		if player.has_node("Camera2D"):
			player.get_node("Camera2D").enabled = true
		# Enable collision with other players (layer 4) for body-blocking
		# Local player: layer 1 (normal), mask 1+4 (world + other players)
		player.collision_layer = 1
		player.collision_mask = 1 | 4  # Collide with world (1) and other players (4)
		# Set local player's name on health bar
		var local_name = display_name
		if local_name == "":
			local_name = NetworkManager.player_name if NetworkManager else "Player"
		if player.has_node("HealthBar"):
			var hb = player.get_node("HealthBar")
			if hb.has_method("set_player_name"):
				hb.set_player_name(local_name)
			if hb.has_method("set_name_color"):
				var is_guest = NetworkManager.is_guest if NetworkManager else false
				if is_guest:
					hb.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
				else:
					hb.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated

		# Determine local player's Ashbane tier
		var local_tier = ashbane_tier
		if AshbaneAuth and AshbaneAuth.is_logged_in():
			local_tier = AshbaneAuth.ashbane_tier.get("tier", "initiate")

		# Apply tier to health bar name coloring
		if player.has_node("HealthBar"):
			var hb = player.get_node("HealthBar")
			if hb.has_method("set_ashbane_tier"):
				hb.set_ashbane_tier(local_tier)

		# Create Allegiance Shield
		_add_allegiance_shield(player, local_tier)

		# Apply cosmetics to player
		if AshbaneAuth and AshbaneAuth.is_logged_in():
			_apply_ashbane_cosmetics(player)
	else:
		# Disable processing for remote players - they are updated via RPC in _receive_player_position
		player.set_physics_process(false)
		player.set_process(false)
		if player.has_method("set_process_unhandled_input"):
			player.set_process_unhandled_input(false)
		if player.has_node("Camera2D"):
			player.get_node("Camera2D").enabled = false
		# Use layer 4 for player body-blocking (doesn't interfere with enemies on layer 1)
		# This allows players to bump into each other without the magnet effect
		player.collision_layer = 4  # Player body-blocking layer
		player.collision_mask = 0   # Remote players don't detect anything themselves
		# Add a small collision shape at feet for body-blocking
		_add_body_blocking_collision(player)

		# Set player name on health bar for remote players
		if display_name != "" and player.has_node("HealthBar"):
			var hb = player.get_node("HealthBar")
			if hb.has_method("set_player_name"):
				hb.set_player_name(display_name)
			if hb.has_method("set_name_color"):
				if is_guest_player:
					hb.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
				else:
					hb.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated
			# Apply tier to health bar name coloring
			if hb.has_method("set_ashbane_tier"):
				hb.set_ashbane_tier(ashbane_tier)

		# Create Allegiance Shield for remote player
		_add_allegiance_shield(player, ashbane_tier)

@rpc("any_peer", "call_local", "reliable")
func despawn_player(id: int):
	"""Remove a player from the game"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	# Security: Only server can despawn players via RPC (except local calls)
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != 1:  # 0 = local call, 1 = server
		push_warning("despawn_player rejected from non-server peer %d" % sender_id)
		return

	if not players.has(id):
		return

	players[id].queue_free()
	players.erase(id)

	if local_player and local_player.get_instance_id() == id:
		local_player = null

func get_spawn_point() -> Vector2:
	"""Get spawn point south of campfire, away from the training dummy"""
	# Campfire is at chunk 0 center
	# Training Dummy is 180px NORTH of campfire
	# Spawn player SOUTH of campfire so "walk to dummy" feels deliberate
	var campfire_pos = CAMPFIRE_POS
	var spawn_offset = Vector2(0, 200)  # South of campfire (positive Y = south)
	# Add slight randomization
	spawn_offset.x += randf_range(-50, 50)
	return campfire_pos + spawn_offset

func get_spawn_points() -> Array:
	"""Get all available spawn points around campfire"""
	var points = []

	# Add campfire area spawns (around CAMPFIRE_POS)
	for i in range(4):
		var angle = (TAU / 4) * i
		var offset = Vector2(cos(angle) * 250, sin(angle) * 250)
		points.append(CAMPFIRE_POS + offset)

	return points

func _apply_saved_data_to_player(username: String, player_id: int) -> void:
	"""Apply saved inventory, stats, and equipment to the player after spawn"""
	if not players.has(player_id):
		push_warning("[game_world] Cannot apply saved data - player %d not found" % player_id)
		return

	var player = players[player_id]
	if not is_instance_valid(player):
		return

	# Apply saved data to game systems
	if DatabaseManager:
		DatabaseManager.apply_player_data_to_systems(username, player)
		print("✅ [game_world] Applied saved data for player: %s" % username)

		# Start tutorial for new players who haven't completed it
		var tutorial_done = DatabaseManager.has_completed_tutorial(username)
		print("📚 [Tutorial] Checking tutorial for %s - completed: %s" % [username, tutorial_done])
		if not tutorial_done:
			print("📚 [Tutorial] Starting tutorial in 1 second...")
			# Small delay to let player fully load
			await get_tree().create_timer(1.0).timeout
			print("📚 [Tutorial] Timer done, TutorialManager exists: %s, player valid: %s" % [TutorialManager != null, is_instance_valid(player)])
			if TutorialManager and is_instance_valid(player):
				print("📚 [Tutorial] Calling start_tutorial()")
				TutorialManager.start_tutorial(player)
				TutorialManager.tutorial_completed.connect(func():
					DatabaseManager.set_tutorial_completed(username)
				, CONNECT_ONE_SHOT)
			else:
				print("📚 [Tutorial] ERROR - TutorialManager or player invalid!")

func _start_guest_tutorial(player_id: int) -> void:
	"""Start tutorial for guest players (no database tracking)"""
	if not players.has(player_id):
		print("📚 [Tutorial] Guest tutorial - player not found")
		return

	var player = players[player_id]
	if not is_instance_valid(player):
		print("📚 [Tutorial] Guest tutorial - player invalid")
		return

	print("📚 [Tutorial] Starting guest tutorial in 1 second...")
	await get_tree().create_timer(1.0).timeout

	if TutorialManager and is_instance_valid(player):
		print("📚 [Tutorial] Calling start_tutorial() for guest")
		TutorialManager.start_tutorial(player)
	else:
		print("📚 [Tutorial] ERROR - TutorialManager or player invalid for guest!")

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER POSITION SYNC (Multiplayer)
# ═══════════════════════════════════════════════════════════════════════════

func _sync_local_player_position():
	"""Send local player position to all other clients"""
	if not local_player or not is_instance_valid(local_player):
		return

	var my_id = multiplayer.get_unique_id()
	var pos = local_player.global_position
	var anim = _get_player_animation(local_player)
	var health = int(local_player.current_health)
	var is_dashing = local_player.is_dashing if local_player.get("is_dashing") != null else false


	# Broadcast to all peers (unreliable for position - speed matters more than reliability)
	rpc("_receive_player_position", my_id, pos, anim, health, is_dashing)

# Track missing player requests to avoid spamming
var _missing_player_requests: Dictionary = {}

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _receive_player_position(player_id: int, pos: Vector2, anim: String, health: int, is_dashing: bool):
	"""Receive position update for a remote player"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	# Security: Verify sender is the player they claim to be (prevent position spoofing)
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id and sender_id != 1:  # Allow server (1) to relay positions
		return  # Reject spoofed position updates

	if player_id == multiplayer.get_unique_id():
		return  # Ignore our own position updates

	if not players.has(player_id):
		# Only log once per player and request spawn
		if not _missing_player_requests.has(player_id):
			if OS.is_debug_build():
				print("🔄 [SYNC] Player %d not in players dict! Requesting spawn..." % player_id)
			_missing_player_requests[player_id] = Time.get_ticks_msec()
			# Request this player's info from server
			if not multiplayer.is_server():
				rpc_id(1, "_request_existing_players", multiplayer.get_unique_id())
		return  # Player not spawned yet

	# Clear from missing requests if we now have them
	if _missing_player_requests.has(player_id):
		_missing_player_requests.erase(player_id)

	var player = players[player_id]
	if not is_instance_valid(player):
		if OS.is_debug_build():
			print("🔄 [SYNC] Player %d invalid instance!" % player_id)
		return

	# Smoothly interpolate to new position (instead of snapping)
	player.global_position = player.global_position.lerp(pos, 0.3)

	# Update animation for remote player
	# Use play_lpc_animation() to sync ALL sprite layers (body, clothes, weapon, etc.)
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite is AnimatedSprite2D:
		if character_sprite.animation != anim:
			# Parse animation name to get type and direction (e.g., "walk_south" -> "walk", "south")
			if character_sprite.has_method("play_lpc_animation"):
				var parts = anim.split("_")
				if parts.size() >= 2:
					var anim_type = parts[0]  # walk, idle, slash
					var direction = parts[1]  # north, south, east, west
					character_sprite.play_lpc_animation(anim_type, direction)
				else:
					character_sprite.play(anim)
			else:
				character_sprite.play(anim)

	# Update health for remote player
	player.current_health = health
	if player.health_bar and player.health_bar.has_method("update_health"):
		player.health_bar.update_health(health, player.max_health)

	# Handle dash visual effects on remote player
	if is_dashing and player.has_method("spawn_dash_afterimage"):
		player.spawn_dash_afterimage()

func _get_player_animation(player: Node) -> String:
	"""Get current animation name from player"""
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite is AnimatedSprite2D:
		return character_sprite.animation
	return "idle_south"

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER BODY-BLOCKING COLLISION
# ═══════════════════════════════════════════════════════════════════════════

func _add_body_blocking_collision(player: Node) -> void:
	"""Add a small collision shape at player's feet for body-blocking in PvP.
	This creates a small circle at the feet so players can't walk through each other."""
	# Check if player already has a collision shape
	var existing_collision = player.get_node_or_null("CollisionShape2D")
	if existing_collision:
		# Modify existing shape to be smaller (feet-sized)
		var shape = existing_collision.shape
		if shape is CircleShape2D:
			shape.radius = 8.0  # Small circle at feet
		elif shape is CapsuleShape2D:
			shape.radius = 8.0
			shape.height = 4.0
		return

	# Create new collision shape if none exists
	var collision_shape = CollisionShape2D.new()
	collision_shape.name = "BodyBlockCollision"
	var circle = CircleShape2D.new()
	circle.radius = 8.0  # Small circle at feet for body-blocking
	collision_shape.shape = circle
	collision_shape.position = Vector2(0, 8)  # Offset to feet level
	player.add_child(collision_shape)

# ═══════════════════════════════════════════════════════════════════════════
# ALLEGIANCE SHIELD SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func _add_allegiance_shield(player: Node, tier: String) -> void:
	"""Add an Allegiance Shield to display player's faction and tier"""
	if not is_instance_valid(player):
		return

	# Check if shield already exists
	if player.has_node("AllegianceShield"):
		var existing = player.get_node("AllegianceShield")
		if existing.has_method("set_tier"):
			existing.set_tier(tier)
		return

	# Create new shield
	var shield = AllegianceShield.new()
	shield.name = "AllegianceShield"
	player.add_child(shield)

	# Set tier after adding to tree
	if shield.has_method("set_tier"):
		shield.set_tier(tier)

# ═══════════════════════════════════════════════════════════════════════════
# ASHBANE COSMETICS INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════

func _apply_ashbane_cosmetics(player: Node) -> void:
	"""Apply Ashbane tier cosmetics to a player character"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return

	if not AshbaneCosmetics:
		return

	# Get the player's profile and calculate cosmetics
	var profile = {
		"ashbane": AshbaneAuth.ashbane_tier,
		"providers": AshbaneAuth.providers,
		"achievements": AshbaneAuth.achievements,
		"total_achievements": AshbaneAuth.total_achievements
	}

	var cosmetics = AshbaneCosmetics.calculate_cosmetics(profile)

	# Apply cosmetics to the player (instant for now, transformation later)
	AshbaneCosmetics.apply_to_character(player, cosmetics, true)

	LogManager.info("Applied Ashbane cosmetics: %s tier" % cosmetics.get("tier", "unknown"), "ashbane")
