# game_world.gd
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

# Asset paths for props - ACTUAL FILES THAT EXIST
const PROP_TEXTURES = {
	"dead_tree_1": "res://assets/environment/wasteland/dead_tree_1.png",
	"rock_large": "res://assets/environment/wasteland/rock_large.png",
	"rock_medium": "res://assets/environment/wasteland/rock_medium.png",
	"rock_small": "res://assets/environment/wasteland/rock_small.png",
	"skull": "res://assets/environment/wasteland/skull.png",
	"bones": "res://assets/environment/wasteland/bones.png",
	"ground_crack_1": "res://assets/environment/wasteland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/wasteland/ground_crack_2.png",
	"broken_sword": "res://assets/environment/wasteland/broken_sword.png",
	"ash_pile": "res://assets/environment/wasteland/ash_pile.png"
}

func _ready():
	print("🗺️ GameWorld initializing...")
	print("📦 Loading props from JSON files...")
	create_ground_texture()  # Add texture to ground first
	create_dark_spots()  # Create dark spots (BEFORE path so path goes over them)
	create_path_layer()  # Create path layer (background)
	load_props_from_json()
	load_path_markers_from_json()
	spawn_all_enemies()
	print("✅ GameWorld ready!")

func create_ground_texture():
	"""Create BARELY VISIBLE ground variation - fine grain only"""
	var ground_texture_layer = Node2D.new()
	ground_texture_layer.name = "GroundTexture"
	ground_texture_layer.z_index = -9  # Just above base ground (-10)
	add_child(ground_texture_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345  # Fixed seed for consistency
	
	# TINY detail spots ONLY - no medium patches at all
	for x in range(-5000, 13000, 80):
		for y in range(-3000, 3000, 80):
			if rng.randf() > 0.3:  # Sparse coverage
				continue
			
			var spot = ColorRect.new()
			spot.size = Vector2(rng.randf_range(20, 40), rng.randf_range(20, 40))  # VERY small
			spot.position = Vector2(
				x + rng.randf_range(-40, 40),
				y + rng.randf_range(-40, 40)
			)
			
			var brightness = 0.20 + rng.randf_range(-0.02, 0.02)
			spot.color = Color(
				brightness * 1.25,
				brightness * 1.0,
				brightness * 0.65,
				rng.randf_range(0.08, 0.15)  # VERY transparent
			)
			
			spot.rotation = rng.randf() * TAU
			ground_texture_layer.add_child(spot)
	
	print("✨ Created subtle ground texture with ", ground_texture_layer.get_child_count(), " tiny details")
	
	# NO dark patches - they're too obvious as squares
	# Ground texture comes from tiny details only

func create_dark_spots():
	"""Create irregular dark spots scattered across the map for props to sit on"""
	var dark_spots_layer = Node2D.new()
	dark_spots_layer.name = "DarkSpots"
	dark_spots_layer.z_index = -7  # Above ground texture, below path
	add_child(dark_spots_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 99999  # Fixed seed for consistency with prop generation
	
	# Create dark spots across the world
	# These will be saved to a JSON file that the prop generator can read
	var dark_spot_positions = []
	
	# Grid-based placement with randomness
	for x in range(-1000, 8000, 400):  # Every 400 pixels
		for y in range(-2000, 2000, 400):
			# 60% chance to place a dark spot
			if rng.randf() > 0.6:
				continue
			
			# Random position within the grid cell
			var spot_x = x + rng.randf_range(-150, 150)
			var spot_y = y + rng.randf_range(-150, 150)
			
			# Skip if too close to campfire (keep it clear)
			var dist_to_campfire = Vector2(spot_x, spot_y).distance_to(Vector2(400, 0))
			if dist_to_campfire < 400:  # 400 pixel radius around campfire
				continue
			
			# Create irregular shape using multiple overlapping circles
			var num_circles = rng.randi_range(4, 8)
			var base_size = rng.randf_range(80, 180)
			
			for i in range(num_circles):
				var circle = ColorRect.new()
				var size = base_size * rng.randf_range(0.6, 1.2)
				circle.size = Vector2(size, size)
				
				# Offset from center to create irregular shape
				var offset = Vector2(
					rng.randf_range(-base_size * 0.3, base_size * 0.3),
					rng.randf_range(-base_size * 0.3, base_size * 0.3)
				)
				circle.position = Vector2(spot_x, spot_y) + offset - circle.size / 2
				
				# Dark brownish color with some variation
				var darkness = rng.randf_range(0.10, 0.16)
				circle.color = Color(
					darkness * 1.2,
					darkness * 0.9,
					darkness * 0.6,
					rng.randf_range(0.3, 0.5)
				)
				
				circle.rotation = rng.randf() * TAU
				dark_spots_layer.add_child(circle)
			
			# Store the center position for prop placement
			dark_spot_positions.append({"x": spot_x, "y": spot_y, "size": base_size})
	
	# Save dark spot positions to JSON for prop generator to use
	var data = {"DarkSpots": dark_spot_positions}
	var file = FileAccess.open("res://dark_spots.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("✨ Created ", dark_spot_positions.size(), " dark spots and saved positions to dark_spots.json")
	else:
		print("❌ Failed to save dark_spots.json")
	
	print("✨ Created ", dark_spots_layer.get_child_count(), " dark spot elements")


func create_path_layer():
	"""Create a smoothly feathered worn-down path"""
	var path_layer = Node2D.new()
	path_layer.name = "PathLayer"
	path_layer.z_index = -8
	add_child(path_layer)
	
	# DARKER worn path color for more definition
	var path_core_color = Color(0.14, 0.10, 0.07, 1.0)  # DARKER core for more contrast
	
	# Path waypoints
	var path_points = [
		Vector2(400, 0), Vector2(800, -100), Vector2(1200, -200), Vector2(1600, -100),
		Vector2(2000, 50), Vector2(2400, 150), Vector2(2800, 100), Vector2(3200, -100),
		Vector2(3600, -200), Vector2(4000, -100), Vector2(4400, 100), Vector2(4800, 50),
		Vector2(5200, -50), Vector2(5600, 0), Vector2(6000, -50), Vector2(6400, 50),
		Vector2(6800, 0), Vector2(7200, -50), Vector2(7600, 0)
	]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321
	
	# Draw path with MORE SPOTS for better coverage - DENSER placement
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var segment_length = start.distance_to(end)
		var num_positions = int(segment_length / 12.0)  # INCREASED from 20 to 12 for MORE spots
		
		for j in range(num_positions):
			var t = float(j) / float(num_positions)
			var center_pos = start.lerp(end, t)
			
			# Create MANY LAYERED spots for smooth blending - 5 LAYERS for silky smooth edges
			# Layer 1: VERY Dark core (center of path)
			for spot_idx in range(2):  # Create 2 core spots per position
				create_path_spot(path_layer, center_pos, rng, 
					35, 60,      # Size range
					20, 40,      # VERY TIGHT spread for defined core
					path_core_color,
					0.65, 0.85)  # High opacity for dark path
			
			# Layer 2: Inner transition
			for spot_idx in range(2):  # 2 inner transition spots
				create_path_spot(path_layer, center_pos, rng,
					50, 75,      # Medium size
					40, 65,      # Tight spread
					path_core_color,
					0.4, 0.6)    # Medium-high opacity
			
			# Layer 3: Mid fade
			for spot_idx in range(2):  # 2 mid-layer spots
				create_path_spot(path_layer, center_pos, rng,
					65, 90,      # Larger
					60, 90,      # Medium spread
					path_core_color,
					0.25, 0.4)   # Medium opacity
			
			# Layer 4: Outer fade (NEW - helps blend edges)
			for spot_idx in range(2):  # 2 outer fade spots
				create_path_spot(path_layer, center_pos, rng,
					85, 115,     # Large
					85, 130,     # Wide spread
					path_core_color,
					0.15, 0.25)  # Low-medium opacity
			
			# Layer 5: Super wide feather (smooths the very edges)
			create_path_spot(path_layer, center_pos, rng,
				100, 140,    # Very large
				120, 170,    # VERY wide spread
				path_core_color,
				0.05, 0.12)  # Very subtle feather
	
	print("✨ Created feathered worn path with ", path_layer.get_child_count(), " gradient spots")

func create_path_spot(parent: Node2D, center: Vector2, rng: RandomNumberGenerator,
	min_size: float, max_size: float,
	min_spread: float, max_spread: float,
	base_color: Color,
	min_alpha: float, max_alpha: float):
	"""Helper to create a single path spot with parameters"""
	var spot = ColorRect.new()
	
	var size = rng.randf_range(min_size, max_size)
	spot.size = Vector2(size, size)
	
	# Random offset from center
	var spread = rng.randf_range(min_spread, max_spread)
	var angle = rng.randf() * TAU
	var offset = Vector2(cos(angle), sin(angle)) * spread
	spot.position = center + offset - spot.size / 2
	
	# Color with brightness variation
	var brightness = rng.randf_range(0.85, 1.1)
	var alpha = rng.randf_range(min_alpha, max_alpha)
	spot.color = Color(
		base_color.r * brightness,
		base_color.g * brightness,
		base_color.b * brightness,
		alpha
	)
	
	spot.rotation = rng.randf() * TAU
	parent.add_child(spot)

func load_props_from_json():
	"""Load and spawn all props from prop_placements.json"""
	var file = FileAccess.open("res://prop_placements.json", FileAccess.READ)
	if not file:
		print("❌ Could not load prop_placements.json")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		print("❌ Error parsing prop_placements.json")
		return
	
	var data = json.data
	var props = data.get("ScatteredProps", [])
	
	print("📦 Creating ", props.size(), " prop sprites...")
	
	var scattered_props_node = $ScatteredProps
	if not scattered_props_node:
		print("❌ ScatteredProps node not found!")
		return
	
	var loaded_count = 0
	for prop in props:
		if create_prop_sprite(prop, scattered_props_node):
			loaded_count += 1
	
	print("✅ Loaded ", loaded_count, " / ", props.size(), " props across expanded world")

func create_prop_sprite(prop_data: Dictionary, parent: Node2D) -> bool:
	"""Create a sprite for a prop with type-specific rotation and shadow rules"""
	var prop_container = Node2D.new()
	prop_container.name = prop_data.get("type", "prop") + "_" + str(prop_data.get("id", 0))
	prop_container.position = Vector2(prop_data.get("x", 0), prop_data.get("y", 0))
	
	var prop_type = prop_data.get("type", "")
	var scale_val = prop_data.get("scale", 1.0)
	
	# Load texture
	if not PROP_TEXTURES.has(prop_type):
		print("⚠️ Unknown prop type: ", prop_type)
		return false
		
	var texture_path = PROP_TEXTURES[prop_type]
	if not ResourceLoader.exists(texture_path):
		print("⚠️ Texture not found: ", texture_path)
		return false
	
	var texture = load(texture_path)
	var texture_size = texture.get_size()
	
	# Create shadow based on prop type
	var shadow = create_shadow_for_prop(prop_type, texture, scale_val, texture_size)
	if shadow:
		prop_container.add_child(shadow)
	
	# Create the main sprite
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.flip_h = prop_data.get("flip_h", false)
	sprite.z_index = prop_data.get("z_index", -1)
	
	# Apply rotation with type-specific rules
	sprite.rotation = get_safe_rotation(prop_type, prop_data.get("rotation", 0.0))
	
	prop_container.add_child(sprite)
	parent.add_child(prop_container)
	return true

func get_safe_rotation(prop_type: String, requested_rotation: float) -> float:
	"""Return safe rotation angle based on prop type rules"""
	match prop_type:
		"dead_tree_1":
			return 0.0  # Always straight up
		"ash_pile":
			return 0.0  # Flat, no rotation
		"rock_medium", "rock_small":
			return 0.0  # No rotation (prevents weird angles)
		_:
			# All others use requested rotation
			return requested_rotation

func create_shadow_for_prop(prop_type: String, texture: Texture2D, scale: float, texture_size: Vector2) -> Sprite2D:
	"""Create appropriate shadow based on prop type with specific rules"""
	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = texture
	shadow.centered = true
	
	match prop_type:
		"dead_tree_1":
			# Tree: shadow at base, straight up only
			shadow.modulate = Color(0, 0, 0, 0.35)  # Darker for visibility
			var tree_height = texture_size.y * scale
			shadow.position = Vector2(6, tree_height * 0.35)
			shadow.scale = Vector2(scale * 0.9, scale * 0.22)
			shadow.skew = 0.15
			shadow.z_index = -2
			return shadow
			
		"rock_large":
			# Large rock: ensure shadow doesn't make it look upside-down
			shadow.modulate = Color(0, 0, 0, 0.4)  # Darker
			var rock_height = texture_size.y * scale
			shadow.position = Vector2(5, rock_height * 0.3)
			shadow.scale = Vector2(scale * 0.95, scale * 0.28)
			shadow.skew = 0.12
			shadow.z_index = -2
			return shadow
			
		"rock_medium", "rock_small":
			# Medium/small rocks: MORE VISIBLE shadow
			shadow.modulate = Color(0, 0, 0, 0.35)  # Darker for visibility
			var small_rock_height = texture_size.y * scale
			shadow.position = Vector2(4, small_rock_height * 0.25)
			shadow.scale = Vector2(scale * 0.9, scale * 0.23)
			shadow.skew = 0.1
			shadow.z_index = -2
			return shadow
			
		"skull":
			# Skull: nestled in dirt with deeper shadow
			shadow.modulate = Color(0, 0, 0, 0.5)  # Darker for visibility
			shadow.position = Vector2(3, 7)
			shadow.scale = Vector2(scale * 0.85, scale * 0.4)
			shadow.skew = 0.05
			shadow.z_index = -2
			return shadow
			
		"bones", "broken_sword":
			# Flat items: MORE VISIBLE shadow to show lying on ground
			shadow.modulate = Color(0, 0, 0, 0.45)  # Darker
			shadow.position = Vector2(3, 5)
			shadow.scale = Vector2(scale * 0.95, scale * 0.22)
			shadow.skew = 0.0
			shadow.z_index = -2
			return shadow
			
		"ground_crack_1", "ground_crack_2":
			# Cracks: VERY DARK fill to look "inside" the ground
			shadow.modulate = Color(0, 0, 0, 0.7)  # Very dark for depth effect
			shadow.position = Vector2(0, 1)  # Almost exactly underneath
			shadow.scale = Vector2(scale * 1.1, scale * 1.1)  # Slightly bigger to "swallow"
			shadow.skew = 0.0
			shadow.z_index = -3  # Below other shadows
			return shadow
			
		"ash_pile":
			# Ash: MORE VISIBLE shadow
			shadow.modulate = Color(0, 0, 0, 0.25)  # Darker
			shadow.position = Vector2(3, 4)
			shadow.scale = Vector2(scale * 0.9, scale * 0.18)
			shadow.z_index = -2
			return shadow
			
		_:
			# Default shadow - MORE VISIBLE
			shadow.modulate = Color(0, 0, 0, 0.35)  # Darker
			shadow.position = Vector2(4, 6)
			shadow.scale = Vector2(scale * 0.9, scale * 0.28)
			shadow.z_index = -2
			return shadow

func load_path_markers_from_json():
	"""Load and spawn all path markers from path_markers.json"""
	var file = FileAccess.open("res://path_markers.json", FileAccess.READ)
	if not file:
		print("❌ Could not load path_markers.json")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		print("❌ Error parsing path_markers.json")
		return
	
	var data = json.data
	var markers = data.get("PathMarkers", [])
	
	print("🗺️ Creating ", markers.size(), " path marker sprites...")
	
	var path_markers_node = $PathMarkers
	if not path_markers_node:
		print("❌ PathMarkers node not found!")
		return
	
	var loaded_count = 0
	for marker in markers:
		if create_marker_sprite(marker, path_markers_node):
			loaded_count += 1
	
	print("✅ Loaded ", loaded_count, " / ", markers.size(), " path markers")

func create_marker_sprite(marker_data: Dictionary, parent: Node2D) -> bool:
	"""Create a sprite for a path marker"""
	var sprite = Sprite2D.new()
	sprite.name = "PathMarker_" + str(marker_data.get("id", 0))
	sprite.position = Vector2(marker_data.get("x", 0), marker_data.get("y", 0))
	sprite.scale = Vector2(1.2, 1.2)  # Make markers slightly bigger so they stand out
	sprite.z_index = -1
	sprite.modulate = Color(1.0, 1.0, 0.5)  # Make them yellow-ish to stand out
	
	# Load rock_small texture as marker
	var texture_path = PROP_TEXTURES.get("rock_small", "")
	if ResourceLoader.exists(texture_path):
		sprite.texture = load(texture_path)
		parent.add_child(sprite)
		return true
	else:
		print("⚠️ Path marker texture not found: ", texture_path)
		return false

func spawn_all_enemies():
	# Find all enemy spawn points
	var spawn_points = []
	
	# Get all children that are EnemySpawnPoint instances
	for child in get_children():
		if "EnemySpawnPoint" in child.name:
			spawn_points.append(child)
	
	if spawn_points.size() > 0:
		print("🎯 Found ", spawn_points.size(), " spawn points")
		
		# Spawn an enemy at each point
		for spawn_point in spawn_points:
			spawn_enemy_at(spawn_point)

func spawn_enemy_at(spawn_point: Node2D):
	var enemy = ENEMY_SCENE.instantiate()
	enemy.global_position = spawn_point.global_position
	
	# Determine zone based on Y position
	var y_pos = spawn_point.global_position.y
	var enemy_type = "medium"
	
	if y_pos > 1100:  # Near campfire (bottom)
		enemy_type = "easy"
	elif y_pos < -700:  # Near castle (top)
		enemy_type = "hard"
	
	# Set stats and color based on type
	match enemy_type:
		"easy":
			enemy.modulate = Color(0.5, 1.0, 0.5)  # Green
			print("  ✅ Spawned EASY skeleton at ", spawn_point.global_position)
		"medium":
			enemy.modulate = Color(1.0, 1.0, 0.5)  # Yellow
			print("  ✅ Spawned MEDIUM skeleton at ", spawn_point.global_position)
		"hard":
			enemy.modulate = Color(1.0, 0.5, 0.5)  # Red
			print("  ✅ Spawned HARD skeleton at ", spawn_point.global_position)
	
	add_child(enemy)
