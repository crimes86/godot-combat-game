# game_world.gd
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

# Asset paths for props
const PROP_TEXTURES = {
	"dead_tree_1": "res://assets/environment/wasteland/dead_tree_1.png",
	"dead_tree_2": "res://assets/environment/wasteland/dead_tree_1.png",
	"dead_tree_3": "res://assets/environment/wasteland/dead_tree_1.png",
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

func _ready():
	print("🗺️ GameWorld initializing...")
	create_ground_texture()
	create_rock_clusters_with_dark_spots()
	spawn_trees_everywhere()
	create_campfire_clearing_smooth()
	create_path_to_castle_smooth()
	load_small_props_randomly()
	load_path_markers_from_json()
	spawn_all_enemies()
	print("✅ GameWorld ready!")

func create_ground_texture():
	"""Create base ground texture"""
	var ground_texture_layer = Node2D.new()
	ground_texture_layer.name = "GroundTexture"
	ground_texture_layer.z_index = -9
	add_child(ground_texture_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	for x in range(-5000, 13000, 150):
		for y in range(-3000, 3000, 150):
			if rng.randf() > 0.45:
				continue
			
			var patch = ColorRect.new()
			var size = rng.randf_range(60, 100)
			patch.size = Vector2(size, size * rng.randf_range(0.9, 1.1))
			patch.position = Vector2(
				x + rng.randf_range(-75, 75),
				y + rng.randf_range(-75, 75)
			)
			
			var brightness = 0.18 + rng.randf_range(-0.04, 0.04)
			patch.color = Color(
				brightness * 1.3,
				brightness * 1.0,
				brightness * 0.6,
				rng.randf_range(0.15, 0.25)
			)
			patch.rotation = rng.randf() * TAU
			ground_texture_layer.add_child(patch)
	
	for x in range(-5000, 13000, 60):
		for y in range(-3000, 3000, 60):
			if rng.randf() > 0.35:
				continue
			
			var spot = ColorRect.new()
			spot.size = Vector2(rng.randf_range(30, 50), rng.randf_range(30, 50))
			spot.position = Vector2(
				x + rng.randf_range(-30, 30),
				y + rng.randf_range(-30, 30)
			)
			
			var brightness = 0.20 + rng.randf_range(-0.03, 0.03)
			spot.color = Color(
				brightness * 1.3,
				brightness * 1.0,
				brightness * 0.6,
				rng.randf_range(0.10, 0.18)
			)
			spot.rotation = rng.randf() * TAU
			ground_texture_layer.add_child(spot)
	
	print("✨ Created base ground texture")

func create_rock_clusters_with_dark_spots():
	"""Create dark spots ONLY for large rocks"""
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
	
	# True random placement across entire map
	var num_rocks = 85  # Total number of rocks to place
	
	for i in range(num_rocks):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
		)
		
		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue
		
		# Vary the dark spot size
		var spot_size = rng.randf_range(150, 280)
		
		create_ultra_smooth_dark_spot(rock_spots_layer, rock_pos, spot_size, rng)
		create_rock_at_position(scattered_props_node, rock_pos, rng)
		rocks_placed += 1
		
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

func create_ultra_smooth_dark_spot(parent: Node2D, center: Vector2, radius: float, rng: RandomNumberGenerator):
	"""Create 12-layer ultra-smooth feathered dark spot"""
	
	var layers = [
		# Edge layers 1-4: Ultra-subtle, very large, massive overlap
		{"count": 40, "size": [280, 380], "spread": radius * 1.2, "darkness": 0.195, "alpha": 0.01},
		{"count": 38, "size": [260, 360], "spread": radius * 1.1, "darkness": 0.190, "alpha": 0.02},
		{"count": 35, "size": [240, 340], "spread": radius * 1.0, "darkness": 0.185, "alpha": 0.03},
		{"count": 32, "size": [220, 320], "spread": radius * 0.9, "darkness": 0.180, "alpha": 0.04},
		
		# Mid layers 5-8: Gradual transition
		{"count": 28, "size": [200, 290], "spread": radius * 0.75, "darkness": 0.170, "alpha": 0.07},
		{"count": 24, "size": [170, 250], "spread": radius * 0.65, "darkness": 0.155, "alpha": 0.10},
		{"count": 20, "size": [140, 210], "spread": radius * 0.55, "darkness": 0.135, "alpha": 0.14},
		{"count": 16, "size": [120, 180], "spread": radius * 0.45, "darkness": 0.115, "alpha": 0.18},
		
		# Core layers 9-12: Darker center
		{"count": 12, "size": [95, 145], "spread": radius * 0.35, "darkness": 0.095, "alpha": 0.24},
		{"count": 10, "size": [75, 115], "spread": radius * 0.25, "darkness": 0.075, "alpha": 0.30},
		{"count": 8, "size": [55, 90], "spread": radius * 0.15, "darkness": 0.060, "alpha": 0.36},
		{"count": 6, "size": [40, 70], "spread": radius * 0.05, "darkness": 0.050, "alpha": 0.42}
	]
	
	for layer_data in layers:
		for i in range(layer_data["count"]):
			var rect = ColorRect.new()
			
			var size = rng.randf_range(layer_data["size"][0], layer_data["size"][1])
			rect.size = Vector2(size, size * rng.randf_range(0.75, 1.25))
			
			var offset = Vector2(
				rng.randf_range(-layer_data["spread"], layer_data["spread"]),
				rng.randf_range(-layer_data["spread"], layer_data["spread"])
			)
			rect.position = center + offset - rect.size / 2
			
			var darkness = layer_data["darkness"]
			rect.color = Color(
				darkness,
				darkness * 0.8,
				darkness * 0.5,
				layer_data["alpha"]
			)
			
			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

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
	
	for x in range(-3000, 9000, 150):  # Changed from 300 to 150
		for y in range(-2000, 2000, 150):  # Changed from 300 to 150
			if rng.randf() > 0.36:  # Changed from 0.12 to 0.36 (3x density)
				continue
			
			var tree_pos = Vector2(
				x + rng.randf_range(-75, 75),
				y + rng.randf_range(-75, 75)
			)
			
			if tree_pos.distance_to(Vector2.ZERO) < 400:
				continue
			
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
	
	# Create horizontal oval shadow at base - all pieces at same Y
	for i in range(7):
		var shadow_piece = ColorRect.new()
		shadow_piece.name = "ShadowPiece" + str(i)
		shadow_piece.size = Vector2(30, 30)
		var x_offset = (i - 3) * 8  # Spread horizontally only
		shadow_piece.position = Vector2(-15 + x_offset, 30)  # Same Y for all pieces
		shadow_piece.color = Color(0.05, 0.04, 0.03, 0.22)
		shadow_piece.z_index = -1
		shadow_piece.rotation = rng.randf_range(0, TAU)
		prop_container.add_child(shadow_piece)
	
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(rng.randf_range(0.9, 1.3), rng.randf_range(0.9, 1.3))
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

func create_campfire_clearing_smooth():
	"""Create campfire clearing with 12-layer ultra-smooth feathering"""
	var clearing_layer = Node2D.new()
	clearing_layer.name = "CampfireClearing"
	clearing_layer.z_index = -8
	add_child(clearing_layer)
	
	var campfire_pos = Vector2(0, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321
	
	var layers = [
		# Edge layers 1-4: Ultra-subtle outer edges
		{"count": 45, "size": [320, 420], "spread": 380, "darkness": 0.195, "alpha": 0.01},
		{"count": 42, "size": [300, 400], "spread": 360, "darkness": 0.190, "alpha": 0.02},
		{"count": 38, "size": [280, 380], "spread": 340, "darkness": 0.185, "alpha": 0.03},
		{"count": 35, "size": [260, 360], "spread": 320, "darkness": 0.180, "alpha": 0.04},
		
		# Mid layers 5-8: Gradual transition
		{"count": 32, "size": [240, 330], "spread": 290, "darkness": 0.170, "alpha": 0.07},
		{"count": 28, "size": [210, 290], "spread": 250, "darkness": 0.155, "alpha": 0.10},
		{"count": 24, "size": [180, 250], "spread": 210, "darkness": 0.135, "alpha": 0.14},
		{"count": 20, "size": [150, 210], "spread": 170, "darkness": 0.115, "alpha": 0.18},
		
		# Core layers 9-12: Darker center
		{"count": 16, "size": [120, 170], "spread": 130, "darkness": 0.095, "alpha": 0.24},
		{"count": 12, "size": [95, 135], "spread": 95, "darkness": 0.075, "alpha": 0.30},
		{"count": 10, "size": [70, 105], "spread": 60, "darkness": 0.060, "alpha": 0.36},
		{"count": 8, "size": [50, 80], "spread": 30, "darkness": 0.050, "alpha": 0.42}
	]
	
	for layer_data in layers:
		for i in range(layer_data["count"]):
			var angle = rng.randf() * TAU
			var dist = rng.randf() * layer_data["spread"]
			var pos = campfire_pos + Vector2(cos(angle), sin(angle)) * dist
			
			var spot = ColorRect.new()
			var size = rng.randf_range(layer_data["size"][0], layer_data["size"][1])
			spot.size = Vector2(size, size * rng.randf_range(0.75, 1.25))
			spot.position = pos - spot.size / 2
			
			var darkness = layer_data["darkness"]
			spot.color = Color(darkness, darkness * 0.8, darkness * 0.5, layer_data["alpha"])
			spot.rotation = rng.randf() * TAU
			
			clearing_layer.add_child(spot)
	
	print("🔥 Created ultra-smooth campfire clearing with 12-layer feathering")

func create_path_to_castle_smooth():
	"""Create path with 12-layer ultra-smooth feathering"""
	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	path_layer.z_index = -8
	add_child(path_layer)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	
	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)
	
	var path_points = []
	for i in range(50):
		var t = float(i) / 49.0
		var pos = campfire_pos.lerp(castle_pos, t)
		
		if i > 0 and i < 49:
			var curve_amount = sin(t * PI) * 250
			pos.y += sin(t * PI * 2.5) * curve_amount
		
		path_points.append(pos)
	
	var layers = [
		# Edge layers 1-4: Very wide, ultra-subtle
		{"count": 6, "size": [280, 350], "spread": 300, "darkness": 0.195, "alpha": 0.01},
		{"count": 6, "size": [260, 330], "spread": 280, "darkness": 0.190, "alpha": 0.02},
		{"count": 5, "size": [240, 310], "spread": 260, "darkness": 0.185, "alpha": 0.03},
		{"count": 5, "size": [220, 290], "spread": 240, "darkness": 0.180, "alpha": 0.04},
		
		# Mid layers 5-8: Gradual transition
		{"count": 4, "size": [200, 260], "spread": 210, "darkness": 0.170, "alpha": 0.07},
		{"count": 4, "size": [175, 230], "spread": 180, "darkness": 0.155, "alpha": 0.10},
		{"count": 3, "size": [150, 200], "spread": 150, "darkness": 0.135, "alpha": 0.14},
		{"count": 3, "size": [130, 175], "spread": 120, "darkness": 0.115, "alpha": 0.18},
		
		# Core layers 9-12: Path center
		{"count": 3, "size": [110, 150], "spread": 90, "darkness": 0.095, "alpha": 0.24},
		{"count": 2, "size": [90, 125], "spread": 65, "darkness": 0.075, "alpha": 0.30},
		{"count": 2, "size": [70, 100], "spread": 40, "darkness": 0.060, "alpha": 0.36},
		{"count": 2, "size": [55, 80], "spread": 20, "darkness": 0.050, "alpha": 0.42}
	]
	
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var segment_length = start.distance_to(end)
		var num_spots = int(segment_length / 25)
		
		for j in range(num_spots):
			var t = float(j) / float(max(1, num_spots))
			var pos = start.lerp(end, t)
			
			for layer_data in layers:
				for k in range(layer_data["count"]):
					var spot = ColorRect.new()
					
					var spread = rng.randf_range(layer_data["spread"] * 0.5, layer_data["spread"])
					var angle = rng.randf() * TAU
					var offset = Vector2(cos(angle), sin(angle)) * spread
					
					var size = rng.randf_range(layer_data["size"][0], layer_data["size"][1])
					spot.size = Vector2(size, size * rng.randf_range(0.75, 1.25))
					spot.position = pos + offset - spot.size / 2
					
					var darkness = layer_data["darkness"]
					spot.color = Color(darkness, darkness * 0.8, darkness * 0.5, layer_data["alpha"])
					spot.rotation = rng.randf() * TAU
					
					path_layer.add_child(spot)
	
	print("🛤️ Created ultra-smooth path with 12-layer feathering")

func load_small_props_randomly():
	"""Generate small props randomly"""
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765
	
	var small_props = ["skull", "bones", "ash_pile", "broken_sword", "ground_crack_1", "ground_crack_2"]
	
	for i in range(1600):  # Changed from 400 to 1600 (400% increase)
		var prop_type = small_props[rng.randi() % small_props.size()]
		
		var prop_data = {
			"type": prop_type,
			"x": rng.randf_range(-3000, 8000),
			"y": rng.randf_range(-1500, 1500),
			"scale": rng.randf_range(0.5, 1.2),  # More size variation
			"rotation": rng.randf() * TAU,
			"flip_h": rng.randf() < 0.5,
			"z_index": -1,
			"id": 2000 + i
		}
		
		create_prop_sprite(prop_data, scattered_props_node)
	
	print("✅ Generated 1600 small detail props")

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
	
	var shadow = create_shadow_for_prop(prop_type, texture, scale_val, texture_size)
	if shadow:
		prop_container.add_child(shadow)
	
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
