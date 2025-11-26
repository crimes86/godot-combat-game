# generate_varied_props.gd
# Script to generate prop placements on dark spot clusters
extends Node

const ROCK_TYPES = ["rock_small", "rock_medium", "rock_large"]
const TREE_TYPES = ["dead_tree_1", "dead_tree_2", "dead_tree_3"]
const BONE_TYPES = ["skull", "bones"]
const OTHER_DECOR = ["ground_crack_1", "ground_crack_2", "broken_sword", "ash_pile"]

const SIZE_RANGES = {
	"rock_small": {"min": 0.8, "max": 1.4},
	"rock_medium": {"min": 0.9, "max": 1.5},
	"rock_large": {"min": 1.0, "max": 1.8},
	"dead_tree_1": {"min": 0.7, "max": 1.6},
	"dead_tree_2": {"min": 0.7, "max": 1.6},
	"dead_tree_3": {"min": 0.7, "max": 1.6},
}

const CAMPFIRE_X = 0  # Updated to match new origin position
const CAMPFIRE_CLEARING_RADIUS = 280  # Increased to account for new clearing size

const PROP_COLLISION_RADII = {
	"rock_small": 20,
	"rock_medium": 35,
	"rock_large": 65,  # Increased from 50
	"dead_tree_1": 60,
	"dead_tree_2": 60,
	"dead_tree_3": 60,
	"skull": 15,
	"bones": 15,
	"ground_crack_1": 25,
	"ground_crack_2": 25,
	"broken_sword": 12,
	"ash_pile": 18
}


func _ready():
	print("🎨 Generating prop placements on dark spot clusters...")
	generate_props()
	print("✅ Done! Prop placements saved to prop_placements.json")
	get_tree().quit()
	
func check_prop_overlap(new_pos: Vector2, new_type: String, new_scale: float, placed_props: Array) -> bool:
	"""Check if new prop overlaps with any existing props"""
	var new_radius = PROP_COLLISION_RADII.get(new_type, 20) * new_scale
	
	for prop in placed_props:
		var existing_pos = Vector2(prop.x, prop.y)
		var existing_radius = PROP_COLLISION_RADII.get(prop.type, 20) * prop.scale
		
		var distance = new_pos.distance_to(existing_pos)
		var min_distance = new_radius + existing_radius + 10  # Added 10px buffer
		
		if distance < min_distance:
			return true  # Overlap detected
	
	return false  # No overlap

func is_position_on_path(pos: Vector2, width: float) -> bool:
	"""Check if position is on the main path"""
	var path_points = [
		Vector2(0, 0), Vector2(800, -100), Vector2(1200, -200), Vector2(1600, -100),
		Vector2(2000, 50), Vector2(2400, 150), Vector2(2800, 100), Vector2(3200, -100),
		Vector2(3600, -200), Vector2(4000, -100), Vector2(4400, 100), Vector2(4800, 50),
		Vector2(5200, -50), Vector2(5600, 0), Vector2(6000, -50), Vector2(6400, 50),
		Vector2(6800, 0), Vector2(7200, -50), Vector2(7600, 0)
	]
	
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var line = end - start
		var len = line.length()
		if len == 0:
			continue
		var proj = clamp((pos - start).dot(line / len), 0, len)
		if pos.distance_to(start + (line / len) * proj) < width:
			return true
	return false

func generate_props():
	var props = []
	var prop_id = 0
	
	var dark_spots = load_dark_spots()
	if dark_spots.size() == 0:
		print("❌ No dark spots found! Run the game once first to generate dark_spots.json")
		return
	
	print("📍 Loaded ", dark_spots.size(), " dark spot clusters")
	
	# Generate path props
	print("🛤️ Generating main path props...")
	var path_props = generate_path_props(prop_id)
	for prop in path_props:
		props.append(prop)
		prop_id += 1
	print("   ✓ Generated ", path_props.size(), " path props")
	
	# Place large props on dark spots
	print("🌑 Placing large props on dark spot clusters...")
	var spot_count = 0
	for spot in dark_spots:
		spot_count += 1
		if spot_count % 100 == 0:
			print("   Processing spot ", spot_count, "/", dark_spots.size())
		
		var spot_pos = Vector2(spot.x, spot.y)
		var spot_size = spot.size
		var on_path = spot.get("on_path", false)
		
		if on_path:
			continue
		
		# Check if near campfire
		if spot_pos.distance_to(Vector2(CAMPFIRE_X, 0)) < CAMPFIRE_CLEARING_RADIUS + 100:
			continue
		
		var distance_from_campfire = spot_pos.distance_to(Vector2(CAMPFIRE_X, 0))
		var num_props = int(clamp(spot_size / 80.0, 1, 3))
		
		for i in range(num_props):
			var attempts = 0
			var max_attempts = 5
			var placed = false
	
			while attempts < max_attempts and not placed:
				# REDUCED offset - keep props closer to dark spot center
				var offset = Vector2(
					randf_range(-spot_size * 0.15, spot_size * 0.15),  # Was 0.3
					randf_range(-spot_size * 0.15, spot_size * 0.15)   # Was 0.3
				)
				var prop_pos = Vector2(spot_pos.x + offset.x, spot_pos.y + offset.y)
				
				# Don't place trees in campfire clearing
				if prop_pos.distance_to(Vector2(CAMPFIRE_X, 0)) < CAMPFIRE_CLEARING_RADIUS + 80:
					attempts += 1
					continue
				
				var prop_data = decide_large_prop_type(distance_from_campfire)
				
				if prop_data:
					# Skip trees on the path
					if prop_data.type in ["dead_tree_1", "dead_tree_2", "dead_tree_3"]:
						if is_position_on_path(prop_pos, 150):  # 150px path clearance
							attempts += 1
							continue
					
					# Check for overlap
					if not check_prop_overlap(prop_pos, prop_data.type, prop_data.scale, props):
						prop_data["id"] = prop_id
						prop_data["x"] = prop_pos.x
						prop_data["y"] = prop_pos.y
						prop_data["z_index"] = -1
						props.append(prop_data)
						prop_id += 1
						placed = true
				
				attempts += 1
	
	print("   ✓ Placed ", props.size() - path_props.size(), " large props")
	
	# Scatter small props (increased density)
	print("🎲 Scattering small props randomly...")
	var world_bounds = {
		"x_min": -1000, "x_max": 8000,
		"y_min": -2000, "y_max": 2000
	}
	var grid_spacing = 120  # Reduced from 180 to spawn more props
	var small_props_start = props.size()

	var grid_count = 0
	var total_grid_cells = ((world_bounds.x_max - world_bounds.x_min) / grid_spacing) * ((world_bounds.y_max - world_bounds.y_min) / grid_spacing)
	
	for x in range(world_bounds.x_min, world_bounds.x_max, grid_spacing):
		for y in range(world_bounds.y_min, world_bounds.y_max, grid_spacing):
			grid_count += 1
			if grid_count % 200 == 0:
				print("   Processing grid ", grid_count, "/", int(total_grid_cells))
			
			var actual_x = x + randf_range(-50, 50)
			var actual_y = y + randf_range(-50, 50)
			
			var pos = Vector2(actual_x, actual_y)
			if pos.distance_to(Vector2(CAMPFIRE_X, 0)) < CAMPFIRE_CLEARING_RADIUS:
				continue
			
			# Skip props directly on the path
			if is_position_on_path(pos, 100):  # 100px path clearance for small props
				continue
			
			var distance = pos.distance_to(Vector2(CAMPFIRE_X, 0))
			
			if randf() > 0.55:  # Increased from 0.35 to spawn more props
				continue
			
			var prop_data = decide_small_prop_type(distance)
			if prop_data:
				# Check for overlap
				if not check_prop_overlap(pos, prop_data.type, prop_data.scale, props):
					prop_data["id"] = prop_id
					prop_data["x"] = actual_x
					prop_data["y"] = actual_y
					prop_data["z_index"] = -1
					props.append(prop_data)
					prop_id += 1
	
	print("   ✓ Scattered ", props.size() - small_props_start, " small props")
	print("📊 Generated ", props.size(), " total props (overlap-free)")
	
	# Save to JSON
	var data = {"ScatteredProps": props}
	var file = FileAccess.open("res://prop_placements.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("💾 Saved ", props.size(), " props to prop_placements.json")
	else:
		print("❌ Failed to save prop_placements.json")

func load_dark_spots() -> Array:
	"""Load dark spot cluster positions from JSON"""
	var file = FileAccess.open("res://dark_spots.json", FileAccess.READ)
	if not file:
		return []
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		return []
	
	var data = json.data
	return data.get("DarkSpots", [])

func generate_path_props(start_id: int) -> Array:
	"""Generate path-appropriate props (NO large rocks or trees)"""
	var path_props = []
	var prop_id = start_id
	
	var path_points = [
		Vector2(0, 0), Vector2(800, -100), Vector2(1200, -200), Vector2(1600, -100),
		Vector2(2000, 50), Vector2(2400, 150), Vector2(2800, 100), Vector2(3200, -100),
		Vector2(3600, -200), Vector2(4000, -100), Vector2(4400, 100), Vector2(4800, 50),
		Vector2(5200, -50), Vector2(5600, 0), Vector2(6000, -50), Vector2(6400, 50),
		Vector2(6800, 0), Vector2(7200, -50), Vector2(7600, 0)
	]
	
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var segment_length = start.distance_to(end)
		var num_props = int(segment_length / 150.0)
		
		for j in range(num_props):
			var t = float(j) / float(num_props)
			var pos = start.lerp(end, t)
			
			var path_dir = (end - start).normalized()
			var perpendicular = Vector2(-path_dir.y, path_dir.x)
			var offset = perpendicular * randf_range(-60, 60)
			pos += offset
			
			# Only small path-appropriate props
			var rand = randf()
			var prop_data = {}
			
			if rand < 0.4:  # Bones/skulls
				var bone_type = BONE_TYPES[randi() % BONE_TYPES.size()]
				prop_data = {
					"type": bone_type,
					"scale": randf_range(0.6, 1.0),
					"rotation": randf() * TAU,
					"flip_h": randf() > 0.5,
					"shadow_type": "embedded"
				}
			elif rand < 0.7:  # Small rocks ONLY
				prop_data = {
					"type": "rock_small",
					"scale": randf_range(0.7, 1.1),
					"rotation": randf() * TAU,
					"flip_h": randf() > 0.5,
					"shadow_type": "normal"
				}
			elif rand < 0.85:  # Cracks
				var crack_type = ["ground_crack_1", "ground_crack_2"][randi() % 2]
				prop_data = {
					"type": crack_type,
					"scale": randf_range(0.7, 1.2),
					"rotation": randf() * TAU,
					"flip_h": randf() > 0.5,
					"shadow_type": "normal"
				}
			else:  # Weapons
				prop_data = {
					"type": "broken_sword",
					"scale": randf_range(0.7, 1.1),
					"rotation": randf() * TAU,
					"flip_h": randf() > 0.5,
					"shadow_type": "normal"
				}
			
			if prop_data:
				prop_data["id"] = prop_id
				prop_data["x"] = pos.x
				prop_data["y"] = pos.y
				prop_data["z_index"] = -1
				path_props.append(prop_data)
				prop_id += 1
	
	return path_props

func decide_large_prop_type(distance_from_campfire: float) -> Dictionary:
	"""Decide large prop type for dark spots - randomly pick from 3 tree types"""
	var max_distance = 7000.0
	var death_intensity = clamp(distance_from_campfire / max_distance, 0.0, 1.0)
	
	var rand = randf()
	
	# More trees near campfire, fewer far away
	var tree_chance = lerp(0.6, 0.2, death_intensity)
	if rand < tree_chance:
		# Randomly pick one of the 3 tree types
		var tree_type = TREE_TYPES[randi() % TREE_TYPES.size()]
		var size_range = SIZE_RANGES[tree_type]
		var scale = randf_range(size_range.min, size_range.max)
		
		# 10% chance of oversized tree for visual interest
		if randf() < 0.1:
			scale *= randf_range(1.3, 1.6)
		
		return {
			"type": tree_type,
			"scale": scale,
			"rotation": 0.0,
			"flip_h": randf() > 0.5,
			"shadow_type": "normal"
		}
	
	# Otherwise spawn large rock (CONSTRAINED ROTATION)
	var size_range = SIZE_RANGES["rock_large"]
	var scale = randf_range(size_range.min, size_range.max)
	
	# 10% chance of oversized rock
	if randf() < 0.1:
		scale *= randf_range(1.3, 1.6)
	
	# Constrain rotation to keep large side down (only rotate slightly, not flip)
	var rotation = randf_range(-0.3, 0.3)  # Max ~17 degrees tilt
	
	return {
		"type": "rock_large",
		"scale": scale,
		"rotation": rotation,  # Small tilt only
		"flip_h": randf() > 0.5,
		"shadow_type": "normal"
	}

func decide_small_prop_type(distance_from_campfire: float) -> Dictionary:
	"""Decide small prop type for random scattering - NO trees or large rocks"""
	var max_distance = 7000.0
	var death_intensity = clamp(distance_from_campfire / max_distance, 0.0, 1.0)
	
	# Density gradient: more props near campfire, but still good coverage far away
	var density_modifier = lerp(0.7, 0.5, death_intensity)  # Increased from 0.6/0.3 to 0.7/0.5
	if randf() > density_modifier:
		return {}
	
	var rand = randf()
	
	# Bones increase with distance
	var bone_chance = lerp(0.15, 0.35, death_intensity)
	if rand < bone_chance:
		var bone_type = BONE_TYPES[randi() % BONE_TYPES.size()]
		return {
			"type": bone_type,
			"scale": randf_range(0.7, 1.4),
			"rotation": randf() * TAU,
			"flip_h": randf() > 0.5,
			"shadow_type": "embedded"
		}
	
	rand -= bone_chance
	
	# Small and medium rocks - increased spawn rate
	var rock_chance = 0.5  # Increased from 0.4 to spawn more rocks
	if rand < rock_chance:
		var rock_type = ["rock_small", "rock_medium"][randi() % 2]
		var size_range = SIZE_RANGES.get(rock_type, {"min": 0.8, "max": 1.4})
		return {
			"type": rock_type,
			"scale": randf_range(size_range.min, size_range.max),
			"rotation": randf() * TAU,
			"flip_h": randf() > 0.5,
			"shadow_type": "normal"
		}
	
	rand -= rock_chance
	
	# Cracks and other decor
	if rand < 0.3:
		var decor_type = OTHER_DECOR[randi() % OTHER_DECOR.size()]
		return {
			"type": decor_type,
			"scale": randf_range(0.8, 1.3),
			"rotation": randf() * TAU,
			"flip_h": randf() > 0.5,
			"shadow_type": "normal"
		}
	
	return {}
