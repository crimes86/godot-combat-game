extends Node
class_name POIManager

## POI (Point of Interest) Manager
## Handles quadrant-based POI generation for edge chunks
## Guarantees: 1 settlement + 1 ruins per edge chunk
## Random fills: lava lakes, resource nodes, monster dens, shrines

# POI Generation seed (deterministic world gen)
const POI_SEED: int = 67890

# Chunk configuration (West→East progression)
# World uses chunk IDs: -1 (west/campfire), 0 (center), +1 (east/Zone 2)
# X coords: -8000 to 0 = chunk -1, 0 to 8000 = chunk 0, 8000 to 16000 = chunk +1
# Campfire is at X: -6000 in chunk -1 (player start area)
var CHUNK_SIZE: float:
	get: return Constants.CHUNK_SIZE  # 8000.0
const QUADRANT_SIZE: float = 4000.0  # CHUNK_SIZE / 2
const EDGE_CHUNKS: Array[int] = [0, 1]  # Chunks with POI quadrants (mid and east)
const STARTER_CHUNK: int = -1  # Safe/noob zone - no POIs (campfire area)

# Hardcoded tutorial lava lakes - guaranteed spawns near campfire for enemy clustering
# These are placed east of the campfire safe zone but still in early game area
# Campfire is at X: -6000, safe radius ~1050, so lakes start around X: -4500
const TUTORIAL_LAVA_LAKES: Array[Dictionary] = [
	{"pos": Vector2(-4200, -1800), "chunk_id": -1},  # NE of campfire
	{"pos": Vector2(-4500, 1600), "chunk_id": -1},   # SE of campfire
	{"pos": Vector2(-2800, -800), "chunk_id": -1},   # East side, north
	{"pos": Vector2(-2500, 1200), "chunk_id": -1},   # East side, south
]

# POI spacing
const MIN_POI_DISTANCE_FROM_PATH: float = 800.0
const POI_CENTER_OFFSET: float = 1000.0  # Offset from quadrant center for variety

# Guaranteed POIs per edge chunk (3 guaranteed, 1 random)
# Each chunk gets: seed_plot, ruins, monster_lava_lake, plus 1 random
const GUARANTEED_POIS: Array[String] = ["seed_plot", "ruins", "monster_lava_lake"]
const SECOND_SEED_PLOT_CHANCE: float = 0.20  # 20% chance for 2 seed plots per chunk

# Random POI pool with weights (for the 4th quadrant)
# Note: resource_node, monster_den, ancient_shrine are placeholders for now
const RANDOM_POI_POOL: Array[Dictionary] = [
	{"type": "monster_lava_lake", "weight": 60},  # High chance for another lava lake
	{"type": "resource_node", "weight": 15},
	{"type": "monster_den", "weight": 15},
	{"type": "ancient_shrine", "weight": 10},
]

# POI type configurations
const POI_CONFIGS: Dictionary = {
	"seed_plot": {
		"radius": 300.0,
		"min_level": 0,
		"description": "Unclaimed World Tree planting location"
	},
	"ruins": {
		"radius": 350.0,
		"min_level": 3,
		"description": "Ancient ruins with enemies and loot"
	},
	"monster_lava_lake": {
		"radius": 400.0,
		"min_level": 5,
		"description": "Giant lava pool with elite spawns"
	},
	"resource_node": {
		"radius": 250.0,
		"min_level": 2,
		"description": "Dense resource area (trees, rocks, ore)"
	},
	"monster_den": {
		"radius": 300.0,
		"min_level": 6,
		"description": "Elite enemy encampment"
	},
	"ancient_shrine": {
		"radius": 150.0,
		"min_level": 4,
		"description": "Buff altar or lore location"
	},
}

# Quadrant identifiers
enum Quadrant { NW, NE, SW, SE }

# Generated POI data
var poi_data: Dictionary = {}  # chunk_id -> Array of POI info
var generated_chunks: Array[int] = []

# Reference to game world for path data
var game_world: Node = null

signal poi_generated(chunk_id: int, pois: Array)
signal poi_spawned(poi_type: String, position: Vector2, chunk_id: int)


func _ready() -> void:
	pass


func initialize(world_ref: Node) -> void:
	"""Initialize POI manager with game world reference"""
	game_world = world_ref
	generate_all_pois()


func generate_all_pois() -> void:
	"""Generate POI positions for all edge chunks"""
	var rng = RandomNumberGenerator.new()
	rng.seed = POI_SEED

	# First, add hardcoded tutorial lava lakes near campfire
	generate_tutorial_lava_lakes()

	# Then generate quadrant-based POIs for edge chunks
	for chunk_id in EDGE_CHUNKS:
		generate_chunk_pois(chunk_id, rng)

	print("🗺️ POI Manager: Generated POIs for %d edge chunks + %d tutorial lava lakes" % [EDGE_CHUNKS.size(), TUTORIAL_LAVA_LAKES.size()])
	_print_poi_summary()


func generate_tutorial_lava_lakes() -> void:
	"""Generate hardcoded lava lake POIs near the tutorial/campfire area"""
	# Initialize chunk -1 data if needed
	if not poi_data.has(STARTER_CHUNK):
		poi_data[STARTER_CHUNK] = []
		generated_chunks.append(STARTER_CHUNK)

	for lake_data in TUTORIAL_LAVA_LAKES:
		var poi_info = {
			"type": "monster_lava_lake",
			"position": lake_data.pos,
			"chunk_id": lake_data.chunk_id,
			"quadrant": Quadrant.NW,  # Not relevant for hardcoded
			"radius": POI_CONFIGS["monster_lava_lake"].get("radius", 400.0),
			"min_level": 1,  # Tutorial area = low level
			"spawned": false,
			"claimed": false,
			"owner_guild": null,
			"is_tutorial_lake": true,  # Flag for special handling
		}
		poi_data[lake_data.chunk_id].append(poi_info)

	print("🌋 Generated %d tutorial lava lakes in chunk %d" % [TUTORIAL_LAVA_LAKES.size(), STARTER_CHUNK])


func generate_chunk_pois(chunk_id: int, rng: RandomNumberGenerator) -> void:
	"""Generate 4 POIs for an edge chunk (one per quadrant)"""
	if chunk_id in generated_chunks:
		return

	generated_chunks.append(chunk_id)
	poi_data[chunk_id] = []

	# Get chunk bounds
	# Chunk -1: X = -8000 to 0
	# Chunk 0:  X = 0 to 8000
	# Chunk +1: X = 8000 to 16000
	# Y is always -4000 to 4000
	var chunk_start_x = chunk_id * CHUNK_SIZE
	var half_chunk = CHUNK_SIZE / 2.0
	var quarter_chunk = CHUNK_SIZE / 4.0

	# Define quadrant centers
	# NW/NE are in negative Y (north), SW/SE are in positive Y (south)
	var quadrant_centers = {
		Quadrant.NW: Vector2(chunk_start_x + quarter_chunk, -quarter_chunk),
		Quadrant.NE: Vector2(chunk_start_x + quarter_chunk * 3, -quarter_chunk),
		Quadrant.SW: Vector2(chunk_start_x + quarter_chunk, quarter_chunk),
		Quadrant.SE: Vector2(chunk_start_x + quarter_chunk * 3, quarter_chunk),
	}

	# Shuffle quadrants for random assignment
	var quadrant_list = [Quadrant.NW, Quadrant.NE, Quadrant.SW, Quadrant.SE]
	quadrant_list.shuffle()

	# Assign guaranteed POIs first
	var assigned_quadrants: Array[Quadrant] = []
	for i in range(GUARANTEED_POIS.size()):
		var poi_type = GUARANTEED_POIS[i]
		var quadrant = quadrant_list[i]
		assigned_quadrants.append(quadrant)

		var poi_pos = _get_poi_position_in_quadrant(quadrant_centers[quadrant], rng)
		_add_poi(chunk_id, poi_type, poi_pos, quadrant)

	# Fill remaining quadrants with random POIs
	# First remaining quadrant has a chance to be a second seed_plot
	var remaining_start = GUARANTEED_POIS.size()
	for i in range(remaining_start, quadrant_list.size()):
		var quadrant = quadrant_list[i]
		var poi_type: String

		# First remaining slot has chance for second seed_plot
		if i == remaining_start and rng.randf() < SECOND_SEED_PLOT_CHANCE:
			poi_type = "seed_plot"
		else:
			poi_type = _pick_random_poi_type(rng)

		var poi_pos = _get_poi_position_in_quadrant(quadrant_centers[quadrant], rng)
		_add_poi(chunk_id, poi_type, poi_pos, quadrant)

	emit_signal("poi_generated", chunk_id, poi_data[chunk_id])


func _get_poi_position_in_quadrant(quadrant_center: Vector2, rng: RandomNumberGenerator) -> Vector2:
	"""Get a randomized position within a quadrant, offset from center"""
	var offset_x = rng.randf_range(-POI_CENTER_OFFSET, POI_CENTER_OFFSET)
	var offset_y = rng.randf_range(-POI_CENTER_OFFSET, POI_CENTER_OFFSET)

	# Clamp to stay within quadrant bounds with padding
	var padding = 500.0
	offset_x = clamp(offset_x, -QUADRANT_SIZE/2 + padding, QUADRANT_SIZE/2 - padding)
	offset_y = clamp(offset_y, -QUADRANT_SIZE/2 + padding, QUADRANT_SIZE/2 - padding)

	return quadrant_center + Vector2(offset_x, offset_y)


func _pick_random_poi_type(rng: RandomNumberGenerator) -> String:
	"""Pick a random POI type from the weighted pool"""
	var total_weight = 0
	for poi in RANDOM_POI_POOL:
		total_weight += poi.weight

	var roll = rng.randi_range(0, total_weight - 1)
	var cumulative = 0

	for poi in RANDOM_POI_POOL:
		cumulative += poi.weight
		if roll < cumulative:
			return poi.type

	return RANDOM_POI_POOL[0].type  # Fallback


func _add_poi(chunk_id: int, poi_type: String, position: Vector2, quadrant: Quadrant) -> void:
	"""Add a POI to the data structure"""
	var config = POI_CONFIGS.get(poi_type, {})

	var poi_info = {
		"type": poi_type,
		"position": position,
		"chunk_id": chunk_id,
		"quadrant": quadrant,
		"radius": config.get("radius", 200.0),
		"min_level": config.get("min_level", 0),
		"spawned": false,
		"claimed": false,  # For settlements
		"owner_guild": null,  # For settlements
	}

	poi_data[chunk_id].append(poi_info)


func _print_poi_summary() -> void:
	"""Print summary of generated POIs"""
	var type_counts = {}

	print("📍 POI Summary by chunk:")
	for chunk_id in poi_data:
		print("   Chunk %d: %d POIs" % [chunk_id, poi_data[chunk_id].size()])
		for poi in poi_data[chunk_id]:
			var t = poi.type
			type_counts[t] = type_counts.get(t, 0) + 1
			print("      - %s at %s" % [t, poi.position])

	print("📍 POI Totals:")
	for poi_type in type_counts:
		print("   - %s: %d" % [poi_type, type_counts[poi_type]])


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func get_pois_for_chunk(chunk_id: int) -> Array:
	"""Get all POIs for a specific chunk"""
	return poi_data.get(chunk_id, [])


func get_pois_by_type(poi_type: String) -> Array:
	"""Get all POIs of a specific type across all chunks"""
	var result = []
	for chunk_id in poi_data:
		for poi in poi_data[chunk_id]:
			if poi.type == poi_type:
				result.append(poi)
	return result


func get_seed_plots() -> Array:
	"""Get all seed plot POIs (World Tree planting locations)"""
	return get_pois_by_type("seed_plot")


func get_ruins() -> Array:
	"""Get all ruins POIs"""
	return get_pois_by_type("ruins")


func get_nearest_poi(position: Vector2, poi_type: String = "") -> Dictionary:
	"""Get the nearest POI to a position, optionally filtered by type"""
	var nearest = {}
	var nearest_dist = INF

	for chunk_id in poi_data:
		for poi in poi_data[chunk_id]:
			if poi_type != "" and poi.type != poi_type:
				continue

			var dist = position.distance_to(poi.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = poi

	return nearest


func is_position_in_poi(position: Vector2, poi_type: String = "") -> Dictionary:
	"""Check if a position is within any POI radius, returns the POI or empty dict"""
	for chunk_id in poi_data:
		for poi in poi_data[chunk_id]:
			if poi_type != "" and poi.type != poi_type:
				continue

			var dist = position.distance_to(poi.position)
			if dist <= poi.radius:
				return poi

	return {}


func mark_poi_spawned(chunk_id: int, poi_type: String, position: Vector2) -> void:
	"""Mark a POI as spawned (visual elements created)"""
	for poi in poi_data.get(chunk_id, []):
		if poi.type == poi_type and poi.position.distance_to(position) < 10:
			poi.spawned = true
			emit_signal("poi_spawned", poi_type, position, chunk_id)
			break


func claim_seed_plot(position: Vector2, guild_id: String) -> bool:
	"""Attempt to claim a seed plot for a guild (plant a World Tree)"""
	for chunk_id in poi_data:
		for poi in poi_data[chunk_id]:
			if poi.type != "seed_plot":
				continue

			var dist = position.distance_to(poi.position)
			if dist <= poi.radius and not poi.claimed:
				poi.claimed = true
				poi.owner_guild = guild_id
				print("🌳 Seed plot claimed at %s by guild %s" % [position, guild_id])
				return true

	return false


func get_chunk_for_position(position: Vector2) -> int:
	"""Get the chunk ID for a world position"""
	return int(position.x / CHUNK_SIZE)


func is_edge_chunk(chunk_id: int) -> bool:
	"""Check if a chunk is an edge chunk (has POIs)"""
	return chunk_id in EDGE_CHUNKS
