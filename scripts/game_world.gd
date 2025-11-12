# game_world.gd - Optimized runtime generation (no baking needed!)
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

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
	"skull": "res://assets/environment/wasteland/skull.png",
	"bones": "res://assets/environment/wasteland/bones.png",
	"ground_crack_1": "res://assets/environment/wasteland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/wasteland/ground_crack_2.png",
	"broken_sword": "res://assets/environment/wasteland/broken_sword.png",
	"ash_pile": "res://assets/environment/wasteland/ash_pile.png"
}

const LAYER_TEMPLATE = [
	# PERFORMANCE MODE: Reduced from 12 layers to 4 layers for smooth gameplay
	# Each spot now creates ~100 rects instead of ~573 (83% reduction)
	{"count": 40, "size_mult": [1.2, 1.6], "spread_mult": 0.8, "darkness": 0.22, "alpha": 0.015},
	{"count": 30, "size_mult": [0.9, 1.3], "spread_mult": 0.6, "darkness": 0.18, "alpha": 0.030},
	{"count": 20, "size_mult": [0.6, 0.9], "spread_mult": 0.4, "darkness": 0.14, "alpha": 0.050},
	{"count": 10, "size_mult": [0.3, 0.5], "spread_mult": 0.2, "darkness": 0.10, "alpha": 0.080}
]

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", "dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10"]
var screenshot_mode = false
var tree_positions = []  # Track tree positions to avoid spawning small rocks on them

func _ready():
	DebugConfig.log_spawning("🗺️ GameWorld initializing (optimized - no baking needed)...")

	# Create world boundaries first
	create_world_boundaries()

	# Generate optimized world layers directly (reduced from 267k to ~40k nodes)
	await generate_optimized_world_layers()

	# Generate dynamic elements (trees, enemies, props)
	generate_dynamic_elements()

	# Set camera limits
	setup_camera_limits()

	DebugConfig.log_spawning("✅ GameWorld ready!")

func create_world_boundaries():
	"""Create invisible walls around world to prevent player from going out of bounds"""
	# World bounds: X: -5000 to 13000, Y: -3000 to 3000
	var boundary_thickness = Constants.WORLD_BOUNDARY_THICKNESS

	# Top wall
	var top_wall = StaticBody2D.new()
	top_wall.name = "TopBoundary"
	var top_shape = CollisionShape2D.new()
	var top_rect = RectangleShape2D.new()
	top_rect.size = Vector2(18000 + boundary_thickness * 2, boundary_thickness)
	top_shape.shape = top_rect
	top_shape.position = Vector2(4000, -3000 - boundary_thickness/2)
	top_wall.add_child(top_shape)
	add_child(top_wall)

	# Bottom wall
	var bottom_wall = StaticBody2D.new()
	bottom_wall.name = "BottomBoundary"
	var bottom_shape = CollisionShape2D.new()
	var bottom_rect = RectangleShape2D.new()
	bottom_rect.size = Vector2(18000 + boundary_thickness * 2, boundary_thickness)
	bottom_shape.shape = bottom_rect
	bottom_shape.position = Vector2(4000, 3000 + boundary_thickness/2)
	bottom_wall.add_child(bottom_shape)
	add_child(bottom_wall)

	# Left wall
	var left_wall = StaticBody2D.new()
	left_wall.name = "LeftBoundary"
	var left_shape = CollisionShape2D.new()
	var left_rect = RectangleShape2D.new()
	left_rect.size = Vector2(boundary_thickness, 6000)
	left_shape.shape = left_rect
	left_shape.position = Vector2(-5000 - boundary_thickness/2, 0)
	left_wall.add_child(left_shape)
	add_child(left_wall)

	# Right wall
	var right_wall = StaticBody2D.new()
	right_wall.name = "RightBoundary"
	var right_shape = CollisionShape2D.new()
	var right_rect = RectangleShape2D.new()
	right_rect.size = Vector2(boundary_thickness, 6000)
	right_shape.shape = right_rect
	right_shape.position = Vector2(13000 + boundary_thickness/2, 0)
	right_wall.add_child(right_shape)
	add_child(right_wall)

	print("🚧 World boundaries created")

func setup_camera_limits():
	"""Set camera limits to prevent seeing outside world boundaries"""
	# Wait for player to be in scene tree
	await get_tree().process_frame

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		print("⚠️ Player not found for camera limits")
		return

	var camera = player.get_node_or_null("Camera2D")
	if not camera:
		print("⚠️ Camera2D not found on player")
		return

	# Set limits to world bounds
	camera.limit_left = Constants.WORLD_LEFT
	camera.limit_right = Constants.WORLD_RIGHT
	camera.limit_top = Constants.WORLD_TOP
	camera.limit_bottom = Constants.WORLD_BOTTOM

	print("📷 Camera limits set to world boundaries")

func generate_optimized_world_layers():
	"""Generate world with reduced complexity - no baking needed!"""
	print("  🔨 Generating ground texture...")
	await create_ground_texture_optimized()

	print("  🔨 Generating terrain variation...")
	await create_terrain_variation_spots()

	print("  🔨 Generating rock dark spots...")
	await create_rock_dark_spots()

	print("  🔨 Generating campfire clearing...")
	create_campfire_clearing()

	print("  🔨 Generating path to castle...")
	await create_path_to_castle_optimized()

	print("  ✅ World layers complete!")

func create_ground_texture_optimized():
	var ground_layer = Node2D.new()
	ground_layer.name = "GroundTexture"
	ground_layer.z_index = -9
	add_child(ground_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	# Performance mode: 900px spacing for smooth gameplay
	# Cover full world bounds
	for x in range(Constants.WORLD_LEFT, Constants.WORLD_RIGHT, Constants.TERRAIN_PATCH_SPACING):
		for y in range(Constants.WORLD_TOP, Constants.WORLD_BOTTOM, Constants.TERRAIN_PATCH_SPACING):
			if rng.randf() > 0.2:  # 80% coverage (doubled from 40%)
				continue

			var patch_pos = Vector2(
				x + rng.randf_range(-250, 250),
				y + rng.randf_range(-250, 250)
			)

			# Clamp to world boundaries
			patch_pos.x = clamp(patch_pos.x, -5000, 13000)
			patch_pos.y = clamp(patch_pos.y, -3000, 3000)

			var base_size = rng.randf_range(100, 140)
			var elongation = rng.randf_range(0.7, 1.5)
			create_feathered_area(ground_layer, patch_pos, base_size, rng, elongation)

			await get_tree().process_frame

func create_terrain_variation_spots():
	var terrain_layer = Node2D.new()
	terrain_layer.name = "TerrainVariation"
	terrain_layer.z_index = -8
	add_child(terrain_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	# Performance mode: 30 spots to cover full world (doubled for better coverage)
	for i in range(30):
		var terrain_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		var spot_size = rng.randf_range(300, 600)
		var elongation = rng.randf_range(0.4, 2.5)

		create_feathered_area(terrain_layer, terrain_pos, spot_size, rng, elongation)

		await get_tree().process_frame

func create_rock_dark_spots():
	var rock_layer = Node2D.new()
	rock_layer.name = "RockSpots"
	rock_layer.z_index = -7
	add_child(rock_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	# Performance mode: 100 spots to cover full world (doubled for better coverage)
	for i in range(100):
		var rock_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue

		var spot_size = rng.randf_range(120, 350)
		var elongation = rng.randf_range(0.6, 1.8)

		create_feathered_area(rock_layer, rock_pos, spot_size, rng, elongation)

		await get_tree().process_frame

func create_campfire_clearing():
	var clearing_layer = Node2D.new()
	clearing_layer.name = "CampfireClearing"
	clearing_layer.z_index = -6
	add_child(clearing_layer)

	var campfire_pos = Vector2(0, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	create_feathered_area(clearing_layer, campfire_pos, 200, rng, 1.0)

func create_path_to_castle_optimized():
	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	path_layer.z_index = -5
	add_child(path_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 777

	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)

	# Performance mode: 30 points for smooth gameplay
	var path_points = []
	for i in range(30):
		var t = float(i) / 29.0
		var pos = campfire_pos.lerp(castle_pos, t)

		if i > 0 and i < 29:
			var curve_amount = sin(t * PI) * 250
			pos.y += sin(t * PI * 2.5) * curve_amount

		path_points.append(pos)

	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var segment_length = start.distance_to(end)

		# Performance mode: 100px spacing for smooth gameplay
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

			# Make path much darker for worn appearance (0.55 = 45% darker)
			create_feathered_area(path_layer, pos, 180, rng, elongation, 0.55)

		await get_tree().process_frame

	# Create heavily-visited circle around campfire
	create_campfire_circle(path_layer, campfire_pos, rng)

	# Create branch paths that lead to dead ends
	await create_branch_paths(path_layer, path_points, rng)

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

				# Same darkness as main path
				create_feathered_area(path_layer, pos, 180, rng, elongation, 0.55)

			await get_tree().process_frame

	print("🔀 Created 3 branch paths with dead ends")

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
			rect.color = Color(
				darkness,
				darkness * 0.8,
				darkness * 0.5,
				layer_data["alpha"]
			)

			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

func create_campfire_circle(parent: Node2D, center: Vector2, rng: RandomNumberGenerator):
	"""Create a heavily-visited circular area around campfire"""
	var radius = 450.0  # Large circle around campfire
	var num_spots = 80  # Dense coverage

	for i in range(num_spots):
		# Create spots in concentric rings
		var ring = int(i / 20)  # 4 rings of 20 spots each
		var angle = (i % 20) * (TAU / 20.0) + rng.randf_range(-0.2, 0.2)
		var ring_radius = (radius / 4.0) * (ring + 1) + rng.randf_range(-40, 40)

		var pos = center + Vector2(
			cos(angle) * ring_radius,
			sin(angle) * ring_radius
		)

		# Even darker than the path for heavily-traveled area (0.45 = 55% darker)
		create_feathered_area(parent, pos, 160, rng, 1.0, 0.45)

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

	# Use existing ScatteredProps node from scene (don't create new one)
	var scattered_props_node = get_node_or_null("ScatteredProps")
	if not scattered_props_node:
		# Fallback: create if it doesn't exist
		scattered_props_node = Node2D.new()
		scattered_props_node.name = "ScatteredProps"
		add_child(scattered_props_node)

	# Enable Y-sorting so props layer correctly based on position
	scattered_props_node.y_sort_enabled = true

	# Trees (need to be separate for proper z-ordering with player)
	spawn_trees_everywhere_dynamic(scattered_props_node)

	# Rock sprites (placed on top of the dark spots we created earlier)
	spawn_rock_sprites(scattered_props_node)

	# Scattered props outside the path (ash, cracks, etc.)
	spawn_scattered_props(scattered_props_node)

	# Small rocks to fill bare sand areas
	spawn_small_rocks(scattered_props_node)

	# Interactive props on the path (skull, bones, broken sword)
	load_interactive_props(scattered_props_node)

	# Path markers
	load_path_markers_from_json()

	# Enemies
	spawn_all_enemies()

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
			if tree_pos.distance_to(Vector2.ZERO) < 700:
				continue

			# Don't place trees on the path - increased avoidance to prevent creeping
			if is_position_on_path(tree_pos, 350.0):
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
	for i in range(50):  # Increased from 40 to cover larger area
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue

		# Don't place rocks on the path - only battle props (skull, bones, sword) go there
		if is_position_on_path(rock_pos, 150.0):
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
	for i in range(250):  # Increased to cover larger area
		var prop_type = visual_props[rng.randi() % visual_props.size()]
		var prop_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Don't place on the path
		if not is_position_on_path(prop_pos, 100.0):
			var prop_data = {
				"type": prop_type,
				"x": prop_pos.x,
				"y": prop_pos.y,
				"scale": rng.randf_range(0.4, 1.5),  # More variety in ash pile sizes
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": 0,  # Same as trees/rocks for proper Y-sorting
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

	# Lots of small rocks to fill in bare areas across full world with buffer
	var buffer = 200.0  # Keep small rocks 200px from edges
	for i in range(1200):  # Increased significantly to fill bare spots
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Avoid campfire area
		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue

		# Don't place on the path
		if is_position_on_path(rock_pos, 150.0):
			continue

		# Prefer spawning in bare areas (far from path and campfire)
		# 70% of rocks should be in outer regions away from central path
		var distance_from_center = abs(rock_pos.y)
		if distance_from_center < 800 and rng.randf() > 0.3:
			continue  # Skip 70% of rocks near the path corridor

		# Don't place on top of trees (check distance to all tree positions)
		var too_close_to_tree = false
		for tree_pos in tree_positions:
			if rock_pos.distance_to(tree_pos) < 120:  # 120px clearance around trees
				too_close_to_tree = true
				break
		if too_close_to_tree:
			continue

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
	
	for i in range(40):
		var prop_type = battle_props[rng.randi() % battle_props.size()]
		
		var attempts = 0
		var prop_pos = Vector2.ZERO
		while attempts < 50:
			prop_pos = Vector2(
				rng.randf_range(0, 7600),
				rng.randf_range(-800, 800)
			)
			if is_position_on_path(prop_pos, 100.0):
				break
			attempts += 1
		
		if attempts < 50:
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

# ===== HELPER FUNCTIONS =====

func is_position_on_path(pos: Vector2, path_width: float = 100.0) -> bool:
	# Check main path
	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)

	if pos.x >= campfire_pos.x and pos.x <= castle_pos.x:
		var t = pos.x / 7600.0
		var path_y = 0.0
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			path_y = sin(t * PI * 2.5) * curve_amount

		var distance_from_path = abs(pos.y - path_y)
		if distance_from_path <= path_width:
			return true

	# Check branch 1 (early north fork)
	# Approximate branch path: starts around x=1800, goes to x=2600, y from 0 to -1600
	if pos.x >= 1600 and pos.x <= 2800:
		var branch_start = Vector2(1800, -150)
		var branch_end = Vector2(2600, -1600)
		var closest_dist = point_to_line_segment_distance(pos, branch_start, branch_end)
		if closest_dist <= path_width:
			return true

	# Check branch 2 (mid-path south fork)
	# Approximate branch path: starts around x=3800, goes to x=4400, y from 0 to 1700
	if pos.x >= 3600 and pos.x <= 4600:
		var branch_start = Vector2(3800, 150)
		var branch_end = Vector2(4400, 1700)
		var closest_dist = point_to_line_segment_distance(pos, branch_start, branch_end)
		if closest_dist <= path_width:
			return true

	# Check branch 3 (late north-east fork)
	# Approximate branch path: starts around x=6000, goes to x=6900, y from 0 to -1100
	if pos.x >= 5800 and pos.x <= 7100:
		var branch_start = Vector2(6000, -50)
		var branch_end = Vector2(6900, -1100)
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
	# Use StaticBody2D for collision
	var prop_container = StaticBody2D.new()
	prop_container.name = tree_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	# Set collision layers (layer 1 = environment, blocks player and enemies)
	prop_container.collision_layer = 2  # Layer 2 for obstacles
	prop_container.collision_mask = 0  # Doesn't need to detect anything

	var texture_path = PROP_TEXTURES[tree_type]
	if not ResourceLoader.exists(texture_path):
		return

	var texture = load(texture_path)

	# Determine tree size (small trees now rare - only 10% instead of 30%)
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.1:
		tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (rare - 10%)
	elif size_roll < 0.55:
		tree_scale = rng.randf_range(2.93, 3.9)  # Medium trees (45%)
	else:
		tree_scale = rng.randf_range(3.9, 5.2)  # Large trees (45%)

	var tree_flipped = rng.randf() < 0.5

	# Create simple dark oval shadow at base of tree
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 45 * (tree_scale / 2.5)  # Scale shadow with tree (tighter)
	var shadow_height = shadow_width * 0.4  # Oval shape
	shadow.size = Vector2(shadow_width, shadow_height)
	# Position at bottom of tree - new sprites are 128x128, tree base is at y=120 (56 from center when centered)
	var shadow_y = 56 * tree_scale  # Tree base position scaled
	# Center shadow horizontally (no skew adjustment needed with new symmetric trees)
	var shadow_x = -shadow_width / 2
	shadow.position = Vector2(shadow_x, shadow_y)
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
	sprite.scale = Vector2(tree_scale, tree_scale)
	sprite.flip_h = tree_flipped
	sprite.z_index = 0

	var color_variation = rng.randf_range(0.85, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.95, color_variation * 0.9)

	prop_container.add_child(sprite)

	# Add collision shape at tree trunk base
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	# Collision radius scales with tree size (trunk width) - tighter for better feel
	shape.radius = 10 * tree_scale  # Reduced from 15 for tighter collision
	collision_shape.shape = shape
	# Position collision at base of tree trunk (where sprite base is)
	collision_shape.position = Vector2(0, 50 * tree_scale)  # Near bottom of tree
	prop_container.add_child(collision_shape)

	parent.add_child(prop_container)

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator):
	# Use StaticBody2D for collision
	var prop_container = StaticBody2D.new()
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

	var color_variation = rng.randf_range(0.8, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.95, color_variation * 0.9)

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
	shadow.size = Vector2(shadow_width, shadow_height)
	var shadow_y = (24 * scale_val / 4) - 3  # Moved up 5px from previous position
	shadow.position = Vector2(-shadow_width/2 + 2, shadow_y)
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
	# Load path markers with validation
	var result = JSONValidator.load_json_file("res://data/path_markers.json")
	if not result.success:
		DebugConfig.log_error("Failed to load path_markers.json: %s" % result.error)
		return

	var data = result.data
	if not data.has("PathMarkers"):
		DebugConfig.log_error("path_markers.json missing 'PathMarkers' array")
		return

	var markers = data["PathMarkers"]
	if not markers is Array:
		DebugConfig.log_error("PathMarkers in path_markers.json is not an array")
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
			DebugConfig.log_warning("Invalid path marker entry (not a Dictionary)")

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
		"medium":
			enemy.modulate = Color(1.0, 1.0, 0.5)
		"hard":
			enemy.modulate = Color(1.0, 0.5, 0.5)
	
	add_child(enemy)
