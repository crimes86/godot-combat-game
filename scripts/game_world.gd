# game_world.gd
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

const PROP_TEXTURES = {
	"dead_tree_1": "res://assets/environment/wasteland/dead_tree_1.png",
	"dead_tree_2": "res://assets/environment/wasteland/dead_tree_2.png",
	"dead_tree_3": "res://assets/environment/wasteland/dead_tree_3.png",
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

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3"]

# ═══════════════════════════════════════════════════════════════════════════
# STANDARDIZED 12-LAYER FEATHERING CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════
const LAYER_TEMPLATE = [
	# Edge layers 1-4: Ultra-subtle, very large, massive overlap
	{"count": 80, "size_mult": [1.4, 1.9], "spread_mult": 1.2, "darkness": 0.24, "alpha": 0.003},
	{"count": 75, "size_mult": [1.3, 1.8], "spread_mult": 1.1, "darkness": 0.23, "alpha": 0.005},
	{"count": 70, "size_mult": [1.2, 1.7], "spread_mult": 1.0, "darkness": 0.22, "alpha": 0.008},
	{"count": 65, "size_mult": [1.1, 1.6], "spread_mult": 0.9, "darkness": 0.21, "alpha": 0.011},
	
	# Mid layers 5-8: Gradual transition
	{"count": 55, "size_mult": [1.0, 1.45], "spread_mult": 0.75, "darkness": 0.20, "alpha": 0.018},
	{"count": 50, "size_mult": [0.85, 1.25], "spread_mult": 0.65, "darkness": 0.18, "alpha": 0.025},
	{"count": 45, "size_mult": [0.7, 1.05], "spread_mult": 0.55, "darkness": 0.16, "alpha": 0.032},
	{"count": 40, "size_mult": [0.6, 0.9], "spread_mult": 0.45, "darkness": 0.15, "alpha": 0.040},
	
	# Core layers 9-12: Darker center
	{"count": 32, "size_mult": [0.475, 0.725], "spread_mult": 0.35, "darkness": 0.14, "alpha": 0.048},
	{"count": 25, "size_mult": [0.375, 0.575], "spread_mult": 0.25, "darkness": 0.12, "alpha": 0.058},
	{"count": 20, "size_mult": [0.275, 0.45], "spread_mult": 0.15, "darkness": 0.11, "alpha": 0.070},
	{"count": 16, "size_mult": [0.2, 0.35], "spread_mult": 0.05, "darkness": 0.10, "alpha": 0.082}
]

func _ready():
	print("🗺️ GameWorld initializing...")
	create_ground_texture()
	create_terrain_variation_spots()
	create_rock_clusters_with_dark_spots()
	spawn_trees_everywhere()
	create_campfire_clearing_smooth()
	create_path_to_castle_smooth()
	load_small_props_randomly()
	load_path_markers_from_json()
	spawn_all_enemies()
	print("✅ GameWorld ready!")

# ═══════════════════════════════════════════════════════════════════════════
# CORE 12-LAYER FEATHERING FUNCTION
# ═══════════════════════════════════════════════════════════════════════════
func create_feathered_area(parent: Node2D, center: Vector2, base_size: float, rng: RandomNumberGenerator, elongation: float = 1.0):
	"""
	Create 12-layer ultra-smooth feathered area
	base_size: Base size in pixels (all layers scale from this)
	elongation: Aspect ratio (1.0 = circle, 2.0 = oval twice as wide, 0.5 = oval twice as tall)
	"""
	for layer_data in LAYER_TEMPLATE:
		for i in range(layer_data["count"]):
			var rect = ColorRect.new()
			
			# Scale size based on base_size
			var size = rng.randf_range(
				base_size * layer_data["size_mult"][0], 
				base_size * layer_data["size_mult"][1]
			)
			
			# Apply elongation for organic shapes with extreme aspect variation
			var aspect_variation = rng.randf_range(0.5, 1.8)
			rect.size = Vector2(
				size * elongation * aspect_variation, 
				size / elongation * aspect_variation
			)
			
			# Position with spread
			var spread = base_size * layer_data["spread_mult"]
			var offset = Vector2(
				rng.randf_range(-spread, spread),
				rng.randf_range(-spread, spread)
			)
			rect.position = center + offset - rect.size / 2
			
			# Color with slight darkness variation per rectangle
			var darkness = layer_data["darkness"] * rng.randf_range(0.85, 1.15)
			rect.color = Color(
				darkness,
				darkness * 0.8,
				darkness * 0.5,
				layer_data["alpha"]
			)
			
			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

# ═══════════════════════════════════════════════════════════════════════════
# GROUND TEXTURE - Now with 12-layer feathering
# ═══════════════════════════════════════════════════════════════════════════
func create_ground_texture():
	"""Create base ground texture using 12-layer feathering"""
	var ground_texture_layer = Node2D.new()
	ground_texture_layer.name = "GroundTexture"
	ground_texture_layer.z_index = -9
	add_child(ground_texture_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	# Scatter feathered patches across the ground
	for x in range(-5000, 13000, 400):
		for y in range(-3000, 3000, 400):
			if rng.randf() > 0.5:
				continue
			
			var patch_pos = Vector2(
				x + rng.randf_range(-200, 200),
				y + rng.randf_range(-200, 200)
			)
			
			# Use smaller base size for subtle ground texture
			var base_size = rng.randf_range(80, 120)
			var elongation = rng.randf_range(0.7, 1.5)
			create_feathered_area(ground_texture_layer, patch_pos, base_size, rng, elongation)
	
	print("✨ Created base ground texture with 12-layer feathering")

# ═══════════════════════════════════════════════════════════════════════════
# TERRAIN VARIATION - Large organic spots for natural look
# ═══════════════════════════════════════════════════════════════════════════
func create_terrain_variation_spots():
	"""Add large, subtle organic spots for terrain variation (breaks up polka dot pattern)"""
	var terrain_layer = Node2D.new()
	terrain_layer.name = "TerrainVariation"
	terrain_layer.z_index = -9
	add_child(terrain_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 99999
	
	# Add ~30 large, subtle terrain spots
	for i in range(30):
		var terrain_pos = Vector2(
			rng.randf_range(-4000, 10000),
			rng.randf_range(-2500, 2500)
		)
		
		# Very large, very organic shapes
		var spot_size = rng.randf_range(300, 600)
		var elongation = rng.randf_range(0.4, 2.5)
		
		create_feathered_area(terrain_layer, terrain_pos, spot_size, rng, elongation)
	
	print("🌄 Created terrain variation spots")

# ═══════════════════════════════════════════════════════════════════════════
# ROCK DARK SPOTS
# ═══════════════════════════════════════════════════════════════════════════
func create_rock_clusters_with_dark_spots():
	"""Create dark spots for large rocks using 12-layer feathering with organic variation"""
	var rock_spots_layer = Node2D.new()
	rock_spots_layer.name = "RockSpots"
	rock_spots_layer.z_index = -9
	add_child(rock_spots_layer)
	
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		scattered_props_node = Node2D.new()
		scattered_props_node.name = "ScatteredProps"
		add_child(scattered_props_node)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321
	
	var rocks_placed = 0
	var num_rocks = 85
	
	for i in range(num_rocks):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
		)
		
		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue
		
		# DRAMATIC size variation (not uniform circles)
		var spot_size = rng.randf_range(120, 350)
		
		# Random elongation for organic shapes
		var elongation = rng.randf_range(0.6, 1.8)
		
		create_feathered_area(rock_spots_layer, rock_pos, spot_size, rng, elongation)
		create_rock_at_position(scattered_props_node, rock_pos, rng)
		rocks_placed += 1
		
		# Sometimes cluster spots together for terrain variation
		if rng.randf() < 0.3:
			var cluster_count = rng.randi_range(1, 3)
			for j in range(cluster_count):
				var offset = Vector2(
					rng.randf_range(-180, 180),
					rng.randf_range(-180, 180)
				)
				var cluster_pos = rock_pos + offset
				var cluster_size = rng.randf_range(80, 200)
				var cluster_elongation = rng.randf_range(0.5, 2.0)
				create_feathered_area(rock_spots_layer, cluster_pos, cluster_size, rng, cluster_elongation)
		
		# Add small rocks nearby
		if rng.randf() < 0.4:
			for j in range(rng.randi_range(1, 2)):
				var offset = Vector2(
					rng.randf_range(-100, 100),
					rng.randf_range(-100, 100)
				)
				var small_rock_pos = rock_pos + offset
				var rock_type = ["rock_medium", "rock_small"][rng.randi() % 2]
				create_small_rock_at_position(scattered_props_node, small_rock_pos, rock_type, rng)
	
	print("📍 Placed ", rocks_placed, " large rocks with ultra-smooth dark spots")

# ═══════════════════════════════════════════════════════════════════════════
# TREES
# ═══════════════════════════════════════════════════════════════════════════
func spawn_trees_everywhere():
	"""Spawn trees randomly across the map"""
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		scattered_props_node = Node2D.new()
		scattered_props_node.name = "ScatteredProps"
		add_child(scattered_props_node)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777
	
	var trees_placed = 0
	
	# Sparse wasteland forest: wide grid (200px) + low probability (35%)
	# More random positioning for sporadic, natural feel (~420 trees)
	for x in range(-3000, 9000, 200):
		for y in range(-2000, 2000, 200):
			if rng.randf() > 0.35:
				continue
			
			var tree_pos = Vector2(
				x + rng.randf_range(-95, 95),
				y + rng.randf_range(-95, 95)
			)
			
			if tree_pos.distance_to(Vector2.ZERO) < 400:
				continue
			
			# Avoid path
			var t = tree_pos.x / 7600.0
			if t >= 0 and t <= 1:
				var path_y = sin(t * PI * 2.5) * 250
				if abs(tree_pos.y - path_y) < 150:
					continue
			
			var tree_type = tree_types[rng.randi() % tree_types.size()]
			create_tree_at_position(scattered_props_node, tree_pos, tree_type, rng)
			trees_placed += 1
	
	print("🌲 Placed ", trees_placed, " trees across the map")

func create_tree_at_position(parent: Node2D, pos: Vector2, tree_type: String, rng: RandomNumberGenerator):
	"""Create a tree with simple oval shadow at base"""
	var prop_container = Node2D.new()
	prop_container.name = tree_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	
	var texture_path = PROP_TEXTURES[tree_type]
	if not ResourceLoader.exists(texture_path):
		return
	
	var texture = load(texture_path)
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	# 2.5x bigger: scale range 2.25-3.25 (was 0.9-1.3)
	sprite.scale = Vector2(rng.randf_range(2.25, 3.25), rng.randf_range(2.25, 3.25))
	sprite.flip_h = rng.randf() < 0.5
	sprite.z_index = 0
	
	var color_variation = rng.randf_range(0.85, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.95, color_variation * 0.9)
	
	prop_container.add_child(sprite)
	parent.add_child(prop_container)

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator):
	"""Create large rock sprite"""
	var prop_container = Node2D.new()
	prop_container.name = "rock_large_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	
	var texture_path = PROP_TEXTURES["rock_large"]
	if not ResourceLoader.exists(texture_path):
		return
	
	var texture = load(texture_path)
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(rng.randf_range(1.0, 1.4), rng.randf_range(1.0, 1.4))
	sprite.flip_h = rng.randf() < 0.5
	sprite.rotation = rng.randf() * TAU
	sprite.z_index = 1
	
	var color_variation = rng.randf_range(0.8, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.95, color_variation * 0.9)
	
	prop_container.add_child(sprite)
	parent.add_child(prop_container)

func create_small_rock_at_position(parent: Node2D, pos: Vector2, rock_type: String, rng: RandomNumberGenerator):
	"""Create small/medium rock sprite"""
	var prop_container = Node2D.new()
	prop_container.name = rock_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	
	var texture_path = PROP_TEXTURES[rock_type]
	if not ResourceLoader.exists(texture_path):
		return
	
	var texture = load(texture_path)
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(rng.randf_range(0.7, 1.1), rng.randf_range(0.7, 1.1))
	sprite.flip_h = rng.randf() < 0.5
	sprite.rotation = rng.randf() * TAU
	sprite.z_index = 0
	
	var color_variation = rng.randf_range(0.8, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.95, color_variation * 0.9)
	
	prop_container.add_child(sprite)
	parent.add_child(prop_container)

# ═══════════════════════════════════════════════════════════════════════════
# CAMPFIRE CLEARING
# ═══════════════════════════════════════════════════════════════════════════
func create_campfire_clearing_smooth():
	"""Create campfire clearing with 12-layer feathering"""
	var clearing_layer = Node2D.new()
	clearing_layer.name = "CampfireClearing"
	clearing_layer.z_index = -8
	add_child(clearing_layer)
	
	var campfire_pos = Vector2(0, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321
	
	# Use standardized feathering (circular)
	create_feathered_area(clearing_layer, campfire_pos, 200, rng, 1.0)
	
	print("🔥 Created ultra-smooth campfire clearing with 12-layer feathering")

func create_feathered_area_wide_path(parent: Node2D, center: Vector2, base_size: float, rng: RandomNumberGenerator, elongation: float = 1.0):
	"""
	Path-specific 12-layer feathering with wider spread for even darkness distribution
	"""
	# Path-specific layer config with WIDER spreads for 200px coverage
	var path_layers = [
		# Edge layers 1-4
		{"count": 80, "size_mult": [1.4, 1.9], "spread_mult": 1.4, "darkness": 0.24, "alpha": 0.003},
		{"count": 75, "size_mult": [1.3, 1.8], "spread_mult": 1.3, "darkness": 0.23, "alpha": 0.005},
		{"count": 70, "size_mult": [1.2, 1.7], "spread_mult": 1.2, "darkness": 0.22, "alpha": 0.008},
		{"count": 65, "size_mult": [1.1, 1.6], "spread_mult": 1.1, "darkness": 0.21, "alpha": 0.011},
		
		# Mid layers 5-8 - WIDER spreads
		{"count": 55, "size_mult": [1.0, 1.45], "spread_mult": 1.0, "darkness": 0.20, "alpha": 0.018},
		{"count": 50, "size_mult": [0.85, 1.25], "spread_mult": 0.9, "darkness": 0.18, "alpha": 0.025},
		{"count": 45, "size_mult": [0.7, 1.05], "spread_mult": 0.8, "darkness": 0.16, "alpha": 0.032},
		{"count": 40, "size_mult": [0.6, 0.9], "spread_mult": 0.7, "darkness": 0.15, "alpha": 0.040},
		
		# Core layers 9-12 - MUCH WIDER spreads (0.6 down to 0.3 instead of 0.35 down to 0.05)
		{"count": 32, "size_mult": [0.475, 0.725], "spread_mult": 0.6, "darkness": 0.14, "alpha": 0.048},
		{"count": 25, "size_mult": [0.375, 0.575], "spread_mult": 0.5, "darkness": 0.12, "alpha": 0.058},
		{"count": 20, "size_mult": [0.275, 0.45], "spread_mult": 0.4, "darkness": 0.11, "alpha": 0.070},
		{"count": 16, "size_mult": [0.2, 0.35], "spread_mult": 0.3, "darkness": 0.10, "alpha": 0.082}
	]
	
	for layer_data in path_layers:
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
			
			var darkness = layer_data["darkness"] * rng.randf_range(0.85, 1.15)
			rect.color = Color(
				darkness,
				darkness * 0.8,
				darkness * 0.5,
				layer_data["alpha"]
			)
			
			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

# ═══════════════════════════════════════════════════════════════════════════
# PATH TO CASTLE
# ═══════════════════════════════════════════════════════════════════════════
func create_path_to_castle_smooth():
	"""Create smooth continuous 150px wide path with 12-layer feathering"""
	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	path_layer.z_index = -8
	add_child(path_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	
	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)
	
	# Generate MORE path points for smoother curve (100 instead of 50)
	var path_points = []
	for i in range(100):
		var t = float(i) / 99.0
		var pos = campfire_pos.lerp(castle_pos, t)
		
		if i > 0 and i < 99:
			var curve_amount = sin(t * PI) * 250
			pos.y += sin(t * PI * 2.5) * curve_amount
		
		path_points.append(pos)
	
	# Place DENSE, overlapping feathered spots along path for continuous coverage
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var direction = (end - start).normalized()
		var segment_length = start.distance_to(end)
		
		# Very dense spacing (30px) for complete coverage
		var num_spots = int(segment_length / 30) + 1
		
		for j in range(num_spots):
			var t = float(j) / float(max(1, num_spots - 1))
			var pos = start.lerp(end, t)
			
			# Calculate elongation aligned with path direction
			# Path moves horizontally more than vertically, so elongate along X
			var angle = direction.angle()
			var elongation = 1.5  # Elongate along path direction for smooth ribbon
			
			# Rotate elongation to match path angle
			# For horizontal-ish paths, we want wide ovals
			if abs(direction.x) > abs(direction.y):
				elongation = 1.6  # Wide along path
			else:
				elongation = 0.8  # Narrow for vertical sections
			
			# Use path-specific feathering with wide spread
			# Base size 180 with wide spreads = 200px even coverage
			create_feathered_area_wide_path(path_layer, pos, 180, rng, elongation)
	
	print("🛤️ Created smooth continuous 200px wide path with spread darkness")

# ═══════════════════════════════════════════════════════════════════════════
# PATH HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════
func is_position_on_path(pos: Vector2, path_width: float = 100.0) -> bool:
	"""Check if a position is within path_width of the path curve"""
	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)
	
	# Check if x is within path bounds
	if pos.x < campfire_pos.x or pos.x > castle_pos.x:
		return false
	
	# Calculate path y at this x position
	var t = pos.x / 7600.0
	var path_y = 0.0
	if t > 0 and t < 1:
		var curve_amount = sin(t * PI) * 250
		path_y = sin(t * PI * 2.5) * curve_amount
	
	# Check if position is within path_width of the path curve
	var distance_from_path = abs(pos.y - path_y)
	return distance_from_path <= path_width

# ═══════════════════════════════════════════════════════════════════════════
# SMALL PROPS
# ═══════════════════════════════════════════════════════════════════════════
func load_small_props_randomly():
	"""Generate small props: battle items on path, environmental items off path"""
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765
	
	# Battle props go ON the path (200px wide)
	var battle_props = ["skull", "bones", "broken_sword"]
	# Environmental props go OFF the path
	var environmental_props = ["ash_pile", "ground_crack_1", "ground_crack_2"]
	
	var props_placed = 0
	var battle_props_placed = 0
	var env_props_placed = 0
	
	# Place 40 battle props on path (sparse coverage)
	for i in range(40):
		var prop_type = battle_props[rng.randi() % battle_props.size()]
		
		# Try to find position on path (rejection sampling)
		var attempts = 0
		var prop_pos = Vector2.ZERO
		while attempts < 50:
			prop_pos = Vector2(
				rng.randf_range(0, 7600),
				rng.randf_range(-800, 800)
			)
			if is_position_on_path(prop_pos, 100.0):  # 200px wide path = ±100px
				break
			attempts += 1
		
		# Only place if we found a valid position
		if attempts < 50:
			var prop_data = {
				"type": prop_type,
				"x": prop_pos.x,
				"y": prop_pos.y,
				"scale": rng.randf_range(0.5, 1.2),
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": -1,
				"id": 2000 + i
			}
			create_prop_sprite(prop_data, scattered_props_node)
			battle_props_placed += 1
	
	# Place 1600 environmental props off path
	for i in range(1600):
		var prop_type = environmental_props[rng.randi() % environmental_props.size()]
		
		# Try to find position off path (rejection sampling)
		var attempts = 0
		var prop_pos = Vector2.ZERO
		while attempts < 50:
			prop_pos = Vector2(
				rng.randf_range(-3000, 8000),
				rng.randf_range(-1500, 1500)
			)
			if not is_position_on_path(prop_pos, 100.0):  # Outside 200px path
				break
			attempts += 1
		
		# Only place if we found a valid position
		if attempts < 50:
			var prop_data = {
				"type": prop_type,
				"x": prop_pos.x,
				"y": prop_pos.y,
				"scale": rng.randf_range(0.5, 1.2),
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": -1,
				"id": 3000 + i
			}
			create_prop_sprite(prop_data, scattered_props_node)
			env_props_placed += 1
	
	print("✅ Generated ", battle_props_placed, " battle props on path, ", env_props_placed, " environmental props off path")

func create_prop_sprite(prop_data: Dictionary, parent: Node2D) -> bool:
	var prop_container = Node2D.new()
	prop_container.name = prop_data.get("type", "prop") + "_" + str(prop_data.get("id", 0))
	prop_container.position = Vector2(prop_data.get("x", 0), prop_data.get("y", 0))
	
	var prop_type = prop_data.get("type", "")
	var scale_val = prop_data.get("scale", 1.0)
	
	if not PROP_TEXTURES.has(prop_type):
		return false
		
	var texture_path = PROP_TEXTURES[prop_type]
	if not ResourceLoader.exists(texture_path):
		return false
	
	var texture = load(texture_path)
	var texture_size = texture.get_size()
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.flip_h = prop_data.get("flip_h", false)
	sprite.z_index = prop_data.get("z_index", -1)
	sprite.rotation = get_safe_rotation(prop_type, prop_data.get("rotation", 0.0))
	
	prop_container.add_child(sprite)
	parent.add_child(prop_container)
	return true

func get_safe_rotation(prop_type: String, requested_rotation: float) -> float:
	match prop_type:
		"dead_tree_1", "dead_tree_2", "dead_tree_3", "ash_pile":
			return 0.0
		_:
			return requested_rotation

func create_shadow_for_prop(prop_type: String, texture: Texture2D, scale: float, texture_size: Vector2) -> Sprite2D:
	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = texture
	shadow.centered = true
	
	match prop_type:
		"skull", "bones", "broken_sword", "ash_pile":
			shadow.modulate = Color(0, 0, 0, 0.25)
			shadow.position = Vector2(3, 5)
			shadow.scale = Vector2(scale * 0.9, scale * 0.2)
			shadow.z_index = -2
			return shadow
		"ground_crack_1", "ground_crack_2":
			shadow.modulate = Color(0, 0, 0, 0.5)
			shadow.position = Vector2(0, 1)
			shadow.scale = Vector2(scale * 1.1, scale * 1.1)
			shadow.z_index = -3
			return shadow
		_:
			shadow.modulate = Color(0, 0, 0, 0.25)
			shadow.position = Vector2(4, 6)
			shadow.scale = Vector2(scale * 0.9, scale * 0.25)
			shadow.z_index = -2
			return shadow

func load_path_markers_from_json():
	var file = FileAccess.open("res://path_markers.json", FileAccess.READ)
	if not file:
		return
	
	var json = JSON.new()
	var parse_result = json.parse(file.get_as_text())
	file.close()
	
	if parse_result != OK:
		return
	
	var data = json.data
	var markers = data.get("PathMarkers", [])
	
	var path_markers_node = $PathMarkers
	if not path_markers_node:
		return
	
	for marker in markers:
		create_marker_sprite(marker, path_markers_node)

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

func spawn_all_enemies():
	var spawn_points = []
	
	for child in get_children():
		if "EnemySpawnPoint" in child.name:
			spawn_points.append(child)
	
	if spawn_points.size() > 0:
		print("🎯 Found ", spawn_points.size(), " spawn points")
		for spawn_point in spawn_points:
			spawn_enemy_at(spawn_point)

func spawn_enemy_at(spawn_point: Node2D):
	var enemy = ENEMY_SCENE.instantiate()
	enemy.global_position = spawn_point.global_position
	
	var y_pos = spawn_point.global_position.y
	var enemy_type = "medium"
	
	if y_pos > 1100:
		enemy_type = "easy"
	elif y_pos < -700:
		enemy_type = "hard"
	
	match enemy_type:
		"easy":
			enemy.modulate = Color(0.5, 1.0, 0.5)
			print("  ✅ Spawned EASY skeleton at ", spawn_point.global_position)
		"medium":
			enemy.modulate = Color(1.0, 1.0, 0.5)
			print("  ✅ Spawned MEDIUM skeleton at ", spawn_point.global_position)
		"hard":
			enemy.modulate = Color(1.0, 0.5, 0.5)
			print("  ✅ Spawned HARD skeleton at ", spawn_point.global_position)
	
	add_child(enemy)
