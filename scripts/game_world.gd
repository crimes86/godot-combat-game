# game_world.gd - Optimized runtime generation (no baking needed!)
extends Node2D

const ENEMY_SCENE = preload("res://scenes/enemies/enemy.tscn")

# Multiplayer-ready spawn manager
var spawn_manager = null  # SpawnManager (type hint removed for compatibility)

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
	# SMOOTH - 8 layers (24 rects/spot) for buttery smooth feathering with viewport culling
	# 50% darker lighter patches for better blending with charcoal base
	# Outer layers: very transparent, wide spread - soft outer glow
	# Inner layers: more opaque, tight spread - solid core
	{"count": 5, "size_mult": [1.4, 1.8], "spread_mult": 1.1, "darkness": 0.28, "alpha": 0.025},
	{"count": 4, "size_mult": [1.2, 1.6], "spread_mult": 0.95, "darkness": 0.26, "alpha": 0.035},
	{"count": 4, "size_mult": [1.0, 1.4], "spread_mult": 0.8, "darkness": 0.25, "alpha": 0.050},
	{"count": 3, "size_mult": [0.8, 1.2], "spread_mult": 0.65, "darkness": 0.23, "alpha": 0.070},
	{"count": 3, "size_mult": [0.6, 1.0], "spread_mult": 0.5, "darkness": 0.22, "alpha": 0.095},
	{"count": 2, "size_mult": [0.4, 0.7], "spread_mult": 0.35, "darkness": 0.20, "alpha": 0.130},
	{"count": 2, "size_mult": [0.3, 0.5], "spread_mult": 0.2, "darkness": 0.19, "alpha": 0.170},
	{"count": 1, "size_mult": [0.2, 0.3], "spread_mult": 0.1, "darkness": 0.18, "alpha": 0.220}
]

# Baking configuration
const BAKED_TERRAIN_PATH = "user://baked_terrain.png"
const WORLD_WIDTH = 18000  # -5000 to 13000
const WORLD_HEIGHT = 6000  # -3000 to 3000
var use_baked_terrain = true  # Set to false to force regeneration

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", "dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10"]
var screenshot_mode = false
var tree_positions = []  # Track tree positions to avoid spawning small rocks on them
var lava_pool_positions = []  # Track lava pool positions to avoid spawning props on them

# Viewport culling for terrain
var terrain_spots = []  # Store all terrain spot data {pos, size, type, elongation, darkness}
var active_terrain_nodes = {}  # Track which spots are currently rendered {spot_index: Node2D}
var viewport_buffer = 800.0  # Render terrain this far beyond viewport edges
var terrain_check_timer = 0.0
const TERRAIN_CHECK_INTERVAL = 0.3  # Check every 0.3s instead of every frame

func _ready():
	DebugConfig.log_spawning("🗺️ GameWorld initializing (viewport-culled terrain system)...")
	print("   📌 Press F11 to force regenerate baked terrain")

	# Create world boundaries first
	create_world_boundaries()

	# Generate terrain spot data (doesn't create ColorRects yet)
	await generate_optimized_world_layers()

	# Generate dynamic elements (trees, enemies, props)
	generate_dynamic_elements()

	# Set camera limits
	setup_camera_limits()

	# Setup corpse loot handling
	setup_corpse_loot_system()

	# Wait for player to be ready, then do initial terrain visibility update
	await get_tree().process_frame
	await get_tree().process_frame
	update_terrain_visibility()

	DebugConfig.log_spawning("✅ GameWorld ready!")

func _process(delta):
	"""Handle viewport culling for terrain, update particle positions, and update spawn manager"""
	terrain_check_timer += delta
	if terrain_check_timer < TERRAIN_CHECK_INTERVAL:
		return
	terrain_check_timer = 0.0

	update_terrain_visibility()

	# Update spawn manager with player positions
	if spawn_manager:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player):
			spawn_manager.update_player_positions([player.global_position])

	# Update ambient particles position to follow player
	var particles = get_node_or_null("AmbientAsh")
	if particles:
		var player = get_tree().get_first_node_in_group("player")
		if player and is_instance_valid(player):
			particles.global_position = player.global_position

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
	"""Generate terrain spot data with viewport culling"""
	print("  🗺️ Generating terrain spot data (viewport culling enabled)...")

	# Create parent nodes for terrain layers
	var ground_layer = Node2D.new()
	ground_layer.name = "GroundTexture"
	ground_layer.z_index = -9
	add_child(ground_layer)

	var terrain_layer = Node2D.new()
	terrain_layer.name = "TerrainVariation"
	terrain_layer.z_index = -8
	add_child(terrain_layer)

	var rock_layer = Node2D.new()
	rock_layer.name = "RockSpots"
	rock_layer.z_index = -7
	add_child(rock_layer)

	var clearing_layer = Node2D.new()
	clearing_layer.name = "Clearings"
	clearing_layer.z_index = -6
	add_child(clearing_layer)

	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	path_layer.z_index = -5
	add_child(path_layer)

	# Generate spot data (no ColorRects created yet)
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	# Ground texture spots
	for x in range(Constants.WORLD_LEFT, Constants.WORLD_RIGHT, Constants.TERRAIN_PATCH_SPACING):
		for y in range(Constants.WORLD_TOP, Constants.WORLD_BOTTOM, Constants.TERRAIN_PATCH_SPACING):
			if rng.randf() > 0.2:
				continue

			var patch_pos = Vector2(
				x + rng.randf_range(-250, 250),
				y + rng.randf_range(-250, 250)
			)
			patch_pos.x = clamp(patch_pos.x, -5000, 13000)
			patch_pos.y = clamp(patch_pos.y, -3000, 3000)

			var base_size = rng.randf_range(100, 140)
			var elongation = rng.randf_range(0.7, 1.5)

			terrain_spots.append({
				"pos": patch_pos,
				"size": base_size,
				"type": "ground",
				"elongation": elongation,
				"darkness": 1.0,
				"parent": ground_layer,
				"rng_state": rng.state
			})

	# Terrain variation spots
	rng.seed = 99999
	for i in range(30):
		var terrain_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)
		var spot_size = rng.randf_range(300, 600)
		var elongation = rng.randf_range(0.4, 2.5)

		terrain_spots.append({
			"pos": terrain_pos,
			"size": spot_size,
			"type": "terrain",
			"elongation": elongation,
			"darkness": 1.0,
			"parent": terrain_layer,
			"rng_state": rng.state
		})

	# Rock dark spots
	rng.seed = 54321
	var campfire_pos = Vector2(-2000, 0)
	for i in range(100):
		var rock_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		if rock_pos.distance_to(campfire_pos) < 450:
			continue

		var spot_size = rng.randf_range(120, 350)
		var elongation = rng.randf_range(0.6, 1.8)

		terrain_spots.append({
			"pos": rock_pos,
			"size": spot_size,
			"type": "rock",
			"elongation": elongation,
			"darkness": 1.0,
			"parent": rock_layer,
			"rng_state": rng.state
		})

	# Campfire clearing (very dark - heavily used)
	rng.seed = 54321
	terrain_spots.append({
		"pos": campfire_pos,
		"size": 200,
		"type": "clearing",
		"elongation": 1.0,
		"darkness": 0.12,  # 0.04-0.07 range = very dark worn ground
		"parent": clearing_layer,
		"rng_state": rng.state
	})

	# Ruins clearings (very dark - heavily used)
	for ruins_pos in [Vector2(1200, -2000), Vector2(4800, 2200), Vector2(8200, -2200)]:
		terrain_spots.append({
			"pos": ruins_pos,
			"size": 340,
			"type": "clearing",
			"elongation": 1.0,
			"darkness": 0.12,  # 0.04-0.07 range = very dark worn ground
			"parent": clearing_layer,
			"rng_state": rng.state
		})

	# Path spots
	rng.seed = 777
	var castle_pos = Vector2(11000, -300)
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
				"darkness": 0.08,  # 0.02-0.05 range = nearly black beaten trail
				"parent": path_layer,
				"rng_state": rng.state
			})

	# Campfire circle (heavily traveled area)
	var radius = 450.0
	var num_spots = 80
	for i in range(num_spots):
		var ring = int(i / 20)
		var angle = (i % 20) * (TAU / 20.0) + rng.randf_range(-0.3, 0.3)  # More angular variance
		var ring_radius = (radius / 4.0) * (ring + 1) + rng.randf_range(-60, 60)  # More radial variance

		var pos = campfire_pos + Vector2(
			cos(angle) * ring_radius,
			sin(angle) * ring_radius
		)

		terrain_spots.append({
			"pos": pos,
			"size": 160,
			"type": "path",
			"elongation": 1.0,
			"darkness": 0.06,  # 0.02-0.04 range = extremely dark, heavily worn
			"parent": path_layer,
			"rng_state": rng.state
		})

	# Branch paths to ruins
	await create_ruins_branch_path_spots(path_layer, path_points, rng)

	print("  ✅ Generated %d terrain spots (viewport culling active)" % terrain_spots.size())

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
					"darkness": 0.08,  # 0.02-0.05 range = nearly black beaten trail
					"parent": path_layer,
					"rng_state": rng.state
				})

	print("   🏛️ Added branch path spots to ruins")

func update_terrain_visibility():
	"""Update which terrain spots are visible based on camera position"""
	var player = get_tree().get_first_node_in_group("player")
	if not player or not is_instance_valid(player):
		return

	var camera = player.get_node_or_null("Camera2D")
	if not camera or not is_instance_valid(camera):
		return

	# Get camera viewport bounds accounting for zoom
	var viewport_size = get_viewport().get_visible_rect().size
	var camera_pos = player.global_position

	# Account for camera zoom (zoom out = see more world)
	# If zoom is Vector2(0.5, 0.5), we see 2x as much world space
	var zoom = camera.zoom
	var world_viewport_size = viewport_size / zoom  # World space size visible in viewport

	var viewport_rect = Rect2(
		camera_pos - world_viewport_size / 2 - Vector2(viewport_buffer, viewport_buffer),
		world_viewport_size + Vector2(viewport_buffer * 2, viewport_buffer * 2)
	)

	# Check each terrain spot
	for i in range(terrain_spots.size()):
		var spot = terrain_spots[i]
		var spot_pos = spot["pos"]
		var is_visible = viewport_rect.has_point(spot_pos)

		if is_visible and not active_terrain_nodes.has(i):
			# Create terrain for this spot
			create_terrain_spot(i, spot)
		elif not is_visible and active_terrain_nodes.has(i):
			# Remove terrain for this spot
			remove_terrain_spot(i)

func get_region_color_tint(pos: Vector2) -> Color:
	"""Get subtle color tint based on world region"""
	# Default: no tint (pure greyscale)
	var tint = Color(1.0, 1.0, 1.0)

	# Ruins regions: Subtle red tint (corruption/dried blood)
	var ruins1_pos = Vector2(1200, -2000)
	var ruins2_pos = Vector2(4800, 2200)
	var ruins3_pos = Vector2(8200, -2200)

	var min_dist_to_ruins = min(
		pos.distance_to(ruins1_pos),
		min(pos.distance_to(ruins2_pos), pos.distance_to(ruins3_pos))
	)

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

func load_baked_terrain():
	"""Load pre-baked terrain texture as a single sprite"""
	var image = Image.load_from_file(BAKED_TERRAIN_PATH)
	if image == null:
		print("  ❌ Failed to load baked terrain, using fallback rendering...")
		use_baked_terrain = false
		# Fallback: Use regular terrain generation
		await generate_fallback_terrain()
		return

	var texture = ImageTexture.create_from_image(image)

	# Create sprite with baked texture
	var terrain_sprite = Sprite2D.new()
	terrain_sprite.name = "BakedTerrain"
	terrain_sprite.texture = texture
	terrain_sprite.centered = false
	terrain_sprite.position = Vector2(-5000, -3000)  # Top-left corner of world
	terrain_sprite.z_index = -9  # Behind everything
	add_child(terrain_sprite)

	print("    ✅ Loaded baked terrain: %dx%d pixels" % [image.get_width(), image.get_height()])

func generate_fallback_terrain():
	"""Fallback: Generate terrain the old way if baking fails"""
	print("  🔨 Generating terrain layers (fallback mode)...")
	await create_ground_texture_optimized()
	await create_terrain_variation_spots()
	await create_rock_dark_spots()
	create_campfire_clearing()
	await create_path_to_castle_optimized()
	print("  ✅ Fallback terrain complete!")

func bake_terrain_to_texture():
	"""Generate all terrain layers and bake to a single texture"""
	# Create a SubViewport for offscreen rendering
	var viewport = SubViewport.new()
	viewport.size = Vector2i(WORLD_WIDTH, WORLD_HEIGHT)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS  # ALWAYS while generating
	add_child(viewport)

	# Create a camera for the viewport (needed for rendering)
	var camera = Camera2D.new()
	camera.enabled = true
	camera.position = Vector2(WORLD_WIDTH / 2, WORLD_HEIGHT / 2)
	camera.zoom = Vector2.ONE
	viewport.add_child(camera)

	# Create background color (same as Ground ColorRect)
	var bg = ColorRect.new()
	bg.size = Vector2(WORLD_WIDTH, WORLD_HEIGHT)
	bg.color = Color(0.40997362, 0.33598864, 0.27249303, 1)  # Same brown as Ground
	bg.position = Vector2.ZERO
	viewport.add_child(bg)

	# Generate all terrain layers into the viewport
	# NOTE: We offset everything by +5000x, +3000y to work in viewport space (0,0 origin)
	print("    🔨 Generating ground texture...")
	await generate_terrain_layer_for_baking(viewport, "ground")

	print("    🔨 Generating terrain variation...")
	await generate_terrain_layer_for_baking(viewport, "terrain")

	print("    🔨 Generating rock spots...")
	await generate_terrain_layer_for_baking(viewport, "rocks")

	print("    🔨 Generating campfire clearing...")
	await generate_terrain_layer_for_baking(viewport, "campfire")

	print("    🔨 Generating path...")
	await generate_terrain_layer_for_baking(viewport, "path")

	# Switch to DISABLED mode and force one final render
	print("    ⏳ Finalizing rendering...")
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame

	# Force final render
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	# Get the rendered image with null checks (Godot 4 method)
	print("    📸 Capturing rendered image...")

	var image = viewport.get_texture().get_image()
	if image == null:
		print("    ❌ ERROR: Could not get image from viewport!")
		print("    ℹ️ Viewport size: %s" % viewport.size)
		print("    ℹ️ Viewport has texture: %s" % (viewport.get_texture() != null))
		print("    ℹ️ Using fallback rendering instead...")
		viewport.queue_free()
		# Use fallback
		await generate_fallback_terrain()
		return

	# Save to disk
	print("    💾 Saving baked terrain (%dx%d)..." % [image.get_width(), image.get_height()])
	var err = image.save_png(BAKED_TERRAIN_PATH)
	if err != OK:
		print("    ❌ Failed to save baked terrain: ", err)
		print("    ℹ️ Using fallback rendering instead...")
		viewport.queue_free()
		await generate_fallback_terrain()
		return
	else:
		print("    ✅ Baked terrain saved to: ", BAKED_TERRAIN_PATH)

	# Clean up viewport
	viewport.queue_free()

	# Now load the baked texture
	load_baked_terrain()

func generate_terrain_layer_for_baking(viewport: SubViewport, layer_type: String):
	"""Generate a specific terrain layer in viewport space (offset for 0,0 origin)"""
	var offset = Vector2(5000, 3000)  # Offset to convert world space to viewport space

	match layer_type:
		"ground":
			await create_ground_texture_for_baking(viewport, offset)
		"terrain":
			await create_terrain_variation_for_baking(viewport, offset)
		"rocks":
			await create_rock_spots_for_baking(viewport, offset)
		"campfire":
			create_campfire_clearing_for_baking(viewport, offset)
		"path":
			await create_path_for_baking(viewport, offset)

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

	# Full quality for baking (will be rendered once to texture)
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

	# Full quality for baking (will be rendered once to texture)
	for i in range(100):
		var rock_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		var campfire_pos = Vector2(-2000, 0)
		if rock_pos.distance_to(campfire_pos) < 450:
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

	var campfire_pos = Vector2(-2000, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	create_feathered_area(clearing_layer, campfire_pos, 200, rng, 1.0, 0.12)

func create_path_to_castle_optimized():
	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	path_layer.z_index = -5
	add_child(path_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 777

	var campfire_pos = Vector2(-2000, 0)
	var castle_pos = Vector2(11000, -300)

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

			# Add natural zigzag variance perpendicular to path direction
			var perpendicular = Vector2(-direction.y, direction.x)
			var variance = rng.randf_range(-60, 60)  # ±60px random offset
			pos += perpendicular * variance

			var elongation = 1.5
			if abs(direction.x) > abs(direction.y):
				elongation = 1.6
			else:
				elongation = 0.8

			# Make path nearly black for worn/beaten appearance (0.08 = 2-5% brightness)
			create_feathered_area(path_layer, pos, 180, rng, elongation, 0.08)

		await get_tree().process_frame

	# Create heavily-visited circle around campfire
	create_campfire_circle(path_layer, campfire_pos, rng)

	# Create branch paths that lead to ruins
	await create_ruins_branch_paths(path_layer, path_points, rng)

	# Create clearings at each ruins
	create_ruins_clearings(rng)

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

	# Clearing at Ruins 1 (1,200, -2,000) - 75% of campfire size (450 * 0.75 = 340)
	create_feathered_area(clearing_layer, Vector2(1200, -2000), 340, rng, 1.0, 0.12)

	# Clearing at Ruins 2 (4,800, 2,200) - 75% of campfire size
	create_feathered_area(clearing_layer, Vector2(4800, 2200), 340, rng, 1.0, 0.12)

	# Clearing at Ruins 3 (8,200, -2,200) - 75% of campfire size
	create_feathered_area(clearing_layer, Vector2(8200, -2200), 340, rng, 1.0, 0.12)

	print("🏛️ Created clearings at 3 ruins locations")

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
			# Pure greyscale for charcoal wasteland aesthetic
			rect.color = Color(
				darkness,
				darkness,
				darkness,
				layer_data["alpha"]
			)

			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

func create_campfire_circle(parent: Node2D, center: Vector2, rng: RandomNumberGenerator):
	"""Create a heavily-visited circular area around campfire"""
	var radius = 450.0  # Large circle around campfire
	var num_spots = 80  # Full quality for baking

	for i in range(num_spots):
		# Create spots in concentric rings
		var ring = int(i / 20)  # 4 rings of 20 spots each
		var angle = (i % 20) * (TAU / 20.0) + rng.randf_range(-0.3, 0.3)  # More angular variance
		var ring_radius = (radius / 4.0) * (ring + 1) + rng.randf_range(-60, 60)  # More radial variance

		var pos = center + Vector2(
			cos(angle) * ring_radius,
			sin(angle) * ring_radius
		)

		# Nearly black for heavily-traveled area (0.06 = 2-4% brightness)
		create_feathered_area(parent, pos, 160, rng, 1.0, 0.06)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			toggle_screenshot_mode()
		elif event.keycode == KEY_F11:
			regenerate_baked_terrain()

func regenerate_baked_terrain():
	"""Force regeneration of baked terrain texture (F11)"""
	print("🔄 Regenerating baked terrain...")

	# Delete existing baked file
	if FileAccess.file_exists(BAKED_TERRAIN_PATH):
		DirAccess.remove_absolute(BAKED_TERRAIN_PATH)
		print("   🗑️ Deleted old baked terrain")

	# Delete existing terrain sprite
	var old_terrain = get_node_or_null("BakedTerrain")
	if old_terrain:
		old_terrain.queue_free()
		print("   🗑️ Removed old terrain sprite")

	# Regenerate
	print("   🔨 Baking new terrain...")
	await bake_terrain_to_texture()
	print("✅ Terrain regenerated! Restart the game to see changes.")

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

	# Lava pools FIRST (so trees and props can avoid them)
	spawn_lava_pools()

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

	# Bone clusters (large skeletal remains)
	spawn_bone_clusters(scattered_props_node)

	# Ground cracks in dark areas
	spawn_ground_cracks(scattered_props_node)

	# Sparse dead vegetation
	spawn_dead_vegetation(scattered_props_node)

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
			var campfire_pos = Vector2(-2000, 0)
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

		var campfire_pos = Vector2(-2000, 0)
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
	for i in range(100):  # Optimized for performance (was 250)
		var prop_type = visual_props[rng.randi() % visual_props.size()]
		var prop_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Reduce clutter around campfire by 25%
		var campfire_pos = Vector2(-2000, 0)
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

	# Optimized rock count for performance (was 2400)
	var buffer = 200.0  # Keep small rocks 200px from edges
	for i in range(800):  # Reduced for better FPS while still filling bare areas
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		# Avoid campfire area
		var campfire_pos = Vector2(-2000, 0)
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

	# 2x density in cleared areas (campfire and ruins)
	var cleared_areas = [
		{"pos": Vector2(-2000, 0), "radius": 450, "min_radius": 150},    # Main campfire (donut shape - avoid fire)
		{"pos": Vector2(1200, -2000), "radius": 340, "min_radius": 0},   # Ruins 1 (75% of campfire)
		{"pos": Vector2(4800, 2200), "radius": 340, "min_radius": 0},    # Ruins 2 (75% of campfire)
		{"pos": Vector2(8200, -2200), "radius": 340, "min_radius": 0}    # Ruins 3 (75% of campfire)
	]

	for area in cleared_areas:
		for i in range(30):  # 30 props per cleared area
			var prop_type = battle_props[rng.randi() % battle_props.size()]

			var attempts = 0
			var prop_pos = Vector2.ZERO
			var valid_position = false
			while attempts < 50:
				# Random position within the cleared area
				# Use sqrt for uniform distribution in annulus/circle (spreads props more evenly)
				var angle = rng.randf() * TAU
				var min_r = area.get("min_radius", 0)
				var max_r = area["radius"]
				# For annulus (donut): interpolate between min and max radius using sqrt for uniform distribution
				var distance = sqrt(rng.randf() * (max_r * max_r - min_r * min_r) + min_r * min_r)
				prop_pos = area["pos"] + Vector2(cos(angle), sin(angle)) * distance

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
					"z_index": 0,
					"id": 3000 + props_placed
				}
				create_prop_sprite(prop_data, parent)
				props_placed += 1

	print("⚔️ Placed ", props_placed, " battle props (skulls, bones, swords)")

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
				rng.randf_range(-4000, 12000),
				rng.randf_range(-2500, 2500)
			)

			# Avoid campfire area
			var campfire_pos = Vector2(-2000, 0)
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
	"""Generate possible spawn points for chests (5x more than will actually spawn)"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 55555

	# Generate 50 possible spawn points (LootSpawnManager will spawn 10 at a time)
	for i in range(50):
		# Find a random position (avoid campfire, prefer interesting locations)
		var attempts = 0
		var chest_pos = Vector2.ZERO
		while attempts < 50:
			chest_pos = Vector2(
				rng.randf_range(-4000, 12000),
				rng.randf_range(-2500, 2500)
			)

			# Avoid campfire area
			var campfire_pos = Vector2(-2000, 0)
			if chest_pos.distance_to(campfire_pos) < 800:
				attempts += 1
				continue

			# Avoid main path (chests should be off the beaten track)
			if is_position_on_path(chest_pos, 300.0):
				attempts += 1
				continue

			# Avoid spawning on trees
			var too_close_to_tree = false
			for tree_pos in tree_positions:
				if chest_pos.distance_to(tree_pos) < 100:  # 100px clearance around trees
					too_close_to_tree = true
					break
			if too_close_to_tree:
				attempts += 1
				continue

			# Valid position found
			break

		# Add to spawn manager's pool
		LootSpawnManager.add_chest_spawn_point(chest_pos)

	print("📦 Generated 50 possible chest spawn points")

# ===== HELPER FUNCTIONS =====

func is_position_on_path(pos: Vector2, path_width: float = 100.0) -> bool:
	# Check main path
	var campfire_pos = Vector2(-2000, 0)
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
	# 100% of trees are harvestable
	var is_harvestable = true

	# Use StaticBody2D for collision (or HarvestableTree script if harvestable)
	var prop_container: StaticBody2D
	if is_harvestable:
		# Load and create harvestable tree
		var HarvestableTreeScript = preload("res://scripts/environment/HarvestableTree.gd")
		prop_container = HarvestableTreeScript.new()
	else:
		# Regular static tree
		prop_container = StaticBody2D.new()

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
	var shadow_width = 45 * (tree_scale / 2.5) * 0.75  # Scale shadow with tree (25% smaller)
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

	# Brown tint for dead trees - adds color to the greyscale world
	var color_variation = rng.randf_range(0.85, 1.0)
	sprite.modulate = Color(color_variation, color_variation * 0.7, color_variation * 0.5)

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

	# Pure greyscale for charcoal wasteland aesthetic
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

func create_torches_along_path():
	"""Create torches along the path at regular intervals"""
	# Load path markers data
	var result = JSONValidator.load_json_file("res://data/path_markers.json")
	if not result.success:
		DebugConfig.log_warning("Could not load path markers for torch placement")
		return

	var data = result.data
	if not data.has("PathMarkers") or not data["PathMarkers"] is Array:
		return

	var markers = data["PathMarkers"]
	if markers.size() < 2:
		return

	# Create Torches container node
	var torches_node = Node2D.new()
	torches_node.name = "Torches"
	torches_node.z_index = 5  # Above most other elements
	add_child(torches_node)

	# Extract path positions, starting from campfire
	var path_positions: Array = []
	var campfire_pos = Vector2(-2000, 0)
	path_positions.append(campfire_pos)  # Start path from campfire

	for marker in markers:
		if marker is Dictionary and marker.has("x") and marker.has("y"):
			path_positions.append(Vector2(marker["x"], marker["y"]))

	if path_positions.size() < 2:
		return

	# Calculate total path length first
	var total_path_length = 0.0
	for i in range(path_positions.size() - 1):
		total_path_length += path_positions[i].distance_to(path_positions[i + 1])

	# Determine torch spacing (target 700px average)
	var base_spacing = 700.0
	var torch_count = 0
	var current_distance = 0.0
	var next_torch_at = base_spacing  # First torch at 700px from start

	# Walk along path and place torches
	var segment_index = 0
	var distance_in_segment = 0.0

	while next_torch_at < total_path_length and segment_index < path_positions.size() - 1:
		var start_pos = path_positions[segment_index]
		var end_pos = path_positions[segment_index + 1]
		var segment_length = start_pos.distance_to(end_pos)
		var segment_end_distance = current_distance + segment_length

		# Place all torches that fall within this segment
		while next_torch_at <= segment_end_distance and next_torch_at < total_path_length:
			# Calculate position within this segment
			var distance_into_segment = next_torch_at - current_distance
			var t = distance_into_segment / segment_length
			var torch_pos = start_pos.lerp(end_pos, t)

			# Create torch
			var torch_script = load("res://scripts/systems/Torch.gd")
			if torch_script:
				var torch = Node2D.new()
				torch.set_script(torch_script)
				torch.name = "Torch_" + str(torch_count)
				torch.position = torch_pos
				torches_node.add_child(torch)
				torch_count += 1

			# Next torch with slight random variation (640-760px)
			next_torch_at += randf_range(640.0, 760.0)

		# Move to next segment
		current_distance = segment_end_distance
		segment_index += 1

	print("🔥 Created %d torches along %.0fpx path (avg spacing: %.0fpx)" % [torch_count, total_path_length, total_path_length / max(1, torch_count)])

func spawn_all_enemies():
	"""Initialize multiplayer-ready spawn manager with dynamic spawning"""
	print("🎯 Initializing dynamic enemy spawning system...")

	# STEP 1: Collect all spawn markers (don't spawn yet)
	var spawn_markers = collect_spawn_markers()
	print("   📍 Found %d spawn markers" % spawn_markers.size())

	# STEP 2: Create and initialize SpawnManager
	spawn_manager = SpawnManager.new()
	spawn_manager.name = "SpawnManager"
	add_child(spawn_manager)

	# Initialize with spawn markers
	spawn_manager.initialize(self, spawn_markers)

	# STEP 3: Set initial player position so spawns work on first frame
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player):
		spawn_manager.update_player_positions([player.global_position])
		print("   👤 Player position registered: (%.0f, %.0f)" % [player.global_position.x, player.global_position.y])

	print("✅ Dynamic spawning system initialized (spawns near player only)")
	print("   🎮 Enemies will spawn/despawn based on player proximity")
	print("   💾 Dead/looted enemies won't respawn")

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

	print("\n📍 Scanning for enemy spawn markers...")

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

	if spawn_markers.is_empty():
		print("   ⚠️ No spawn markers found! Add Marker2D nodes named 'EnemySpawn_*'")
	else:
		print("   ✅ Collected %d spawn markers" % spawn_markers.size())

	return spawn_markers

func analyze_spawn_pattern(children: Array) -> void:
	"""Analyze manually placed enemy patterns to learn density, level progression, and distribution"""
	var spawn_data = []
	var campfire_pos = Vector2(-2000, 0)

	print("\n🔍 Analyzing your spawn pattern...")

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

func spawn_zone_1_enemies():
	"""Spawn Zone 1 patrol enemies - uses learned pattern if available, otherwise uses default"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 88888  # Consistent enemy placement

	var total_spawned = 0

	# Check if we have a learned pattern from manual placements
	if has_meta("spawn_pattern"):
		print("\n🎯 Continuing your spawn pattern...")
		total_spawned = spawn_pattern_based_enemies(rng)
	else:
		# Fallback to old corridor-based spawning
		var campfire_pos = Vector2(-2000, 0)
		var ruins1_pos = Vector2(1200, -2000)
		print("\n🎯 Using default spawn pattern...")

		# Main path: Campfire (-2000, 0) to Branch point (~800, 0)
		total_spawned += spawn_path_corridor(campfire_pos, Vector2(800, 0), 1, 5, 8, rng)

		# Branch path: Branch point to Ruins 1 (1200, -2000)
		total_spawned += spawn_path_corridor(Vector2(800, 0), ruins1_pos, 5, 10, 12, rng)

	print("   Zone 1: Spawned %d procedural patrol enemies" % total_spawned)

func spawn_pattern_based_enemies(rng: RandomNumberGenerator) -> int:
	"""Spawn enemies based on learned pattern from manual placements"""
	var pattern = get_meta("spawn_pattern")
	var campfire_pos = pattern["campfire_pos"]
	var min_spacing = pattern["min_spacing"]
	var avg_dist_from_path = pattern["avg_dist_from_path"]
	var level_progression = pattern["level_progression"]
	var manual_count = pattern["manual_count"]

	# Get all existing spawn positions (manual + ruins)
	var existing_positions: Array[Vector2] = []
	if has_meta("manual_spawn_positions"):
		existing_positions = get_meta("manual_spawn_positions").duplicate()

	# Ruins exclusion zones
	const RUINS_POSITIONS = [
		Vector2(1200, -2000),
		Vector2(4800, 2200),
		Vector2(8200, -2200)
	]
	const RUINS_EXCLUSION_RADIUS = 450.0

	var spawned = 0
	var target_total = manual_count * 3  # Spawn 3x the manual count to fill the world
	const MAX_ATTEMPTS_PER_ENEMY = 100

	print("   🎲 Generating %d enemies based on your pattern..." % (target_total - manual_count))
	print("   📏 Using spacing: %.0fpx, Path offset: %.0fpx" % [min_spacing, avg_dist_from_path])

	# Calculate world bounds based on manual placements
	var world_min_x = campfire_pos.x - 500
	var world_max_x = 1500  # Extend to just before Ruins 1
	var world_min_y = -2500
	var world_max_y = 2500

	for i in range(target_total - manual_count):
		var attempts = 0
		var valid_spawn = false
		var spawn_pos = Vector2.ZERO
		var spawn_level = 1

		while attempts < MAX_ATTEMPTS_PER_ENEMY and not valid_spawn:
			attempts += 1

			# Generate random position in world bounds
			spawn_pos = Vector2(
				rng.randf_range(world_min_x, world_max_x),
				rng.randf_range(world_min_y, world_max_y)
			)

			# Calculate distance from campfire to determine level
			var dist_from_campfire = spawn_pos.distance_to(campfire_pos)
			var bucket = int(dist_from_campfire / 500) * 500

			# Find appropriate level from learned progression
			spawn_level = 1
			if level_progression.has(bucket):
				spawn_level = int(level_progression[bucket])
				# Add some variance (±1 level)
				spawn_level += rng.randi_range(-1, 1)
				spawn_level = clamp(spawn_level, 1, 10)
			else:
				# Interpolate between known buckets
				var closest_bucket = -1
				var closest_dist = 999999
				for known_bucket in level_progression.keys():
					var dist = abs(bucket - known_bucket)
					if dist < closest_dist:
						closest_dist = dist
						closest_bucket = known_bucket
				if closest_bucket >= 0:
					spawn_level = int(level_progression[closest_bucket])
					# Add distance-based scaling
					spawn_level += int((bucket - closest_bucket) / 1000.0)
					spawn_level = clamp(spawn_level, 1, 10)

			# Prefer positions near the learned average distance from path
			# But allow variance (50% within ±200px, 50% anywhere)
			if rng.randf() < 0.5:
				var target_y_offset = avg_dist_from_path * (1 if rng.randf() < 0.5 else -1)
				target_y_offset += rng.randf_range(-200, 200)
				spawn_pos.y = target_y_offset

			# Validation checks
			valid_spawn = true

			# Check ruins exclusion
			for ruins_pos in RUINS_POSITIONS:
				if spawn_pos.distance_to(ruins_pos) < RUINS_EXCLUSION_RADIUS:
					valid_spawn = false
					break

			# Check spacing from existing spawns
			if valid_spawn:
				for existing_pos in existing_positions:
					if spawn_pos.distance_to(existing_pos) < min_spacing:
						valid_spawn = false
						break

		# Spawn if valid position found
		if valid_spawn:
			spawn_patrol_enemy(spawn_pos, spawn_level)
			existing_positions.append(spawn_pos)
			spawned += 1

	return spawned

func spawn_path_corridor(start: Vector2, end: Vector2, min_level: int, max_level: int, count: int, rng: RandomNumberGenerator) -> int:
	"""Spawn enemies along a path corridor - dense near path, sparse at edges"""
	var spawned = 0
	var path_length = start.distance_to(end)
	var spawned_positions: Array[Vector2] = []  # Track spawned positions
	const MIN_SPAWN_DISTANCE = 150.0  # Minimum distance between spawns (increased for better spread)

	# Get manually placed spawn positions to avoid
	var manual_positions: Array[Vector2] = []
	if has_meta("manual_spawn_positions"):
		manual_positions = get_meta("manual_spawn_positions")

	# Ruins exclusion zones (guardian-only areas)
	const RUINS_POSITIONS = [
		Vector2(1200, -2000),   # Ruins 1
		Vector2(4800, 2200),    # Ruins 2
		Vector2(8200, -2200)    # Ruins 3
	]
	const RUINS_EXCLUSION_RADIUS = 450.0  # Block 450px radius around ruins (larger than clearing for safety)

	for i in range(count):
		var spawn_pos = Vector2.ZERO
		var valid_position = false
		var attempts = 0
		const MAX_ATTEMPTS = 50  # Prevent infinite loops

		# Keep trying until we find a valid position
		while not valid_position and attempts < MAX_ATTEMPTS:
			attempts += 1

			# Position along path (0.0 to 1.0) with randomness to avoid grid pattern
			var base_t = float(i) / float(count - 1) if count > 1 else 0.5
			# Add jitter: ±0.15 (30% overlap between spawn zones for natural distribution)
			var jitter = rng.randf_range(-0.15, 0.15)
			var t = clamp(base_t + jitter, 0.0, 1.0)
			var path_point = start.lerp(end, t)

			# Offset perpendicular to path with more variation
			# 50% close (200-600px), 30% medium (600-1000px), 20% far (1000-1500px)
			var offset_distance = 0.0
			var rand_val = rng.randf()
			if rand_val < 0.5:
				offset_distance = rng.randf_range(200, 600)  # Close to path
			elif rand_val < 0.8:
				offset_distance = rng.randf_range(600, 1000)  # Medium distance
			else:
				offset_distance = rng.randf_range(1000, 1500)  # Far from path

			var offset_side = 1 if rng.randf() < 0.5 else -1  # North or south

			# Calculate perpendicular direction
			var path_dir = (end - start).normalized()
			var perpendicular = Vector2(-path_dir.y, path_dir.x) * offset_side

			spawn_pos = path_point + perpendicular * offset_distance

			# Check if position is too close to any ruins (BLOCK RUINS AREAS)
			valid_position = true
			for ruins_pos in RUINS_POSITIONS:
				if spawn_pos.distance_to(ruins_pos) < RUINS_EXCLUSION_RADIUS:
					valid_position = false
					break

			# Check if too close to manually placed enemies
			if valid_position:
				for manual_pos in manual_positions:
					if spawn_pos.distance_to(manual_pos) < MIN_SPAWN_DISTANCE:
						valid_position = false
						break

			# If not in ruins area or manual areas, check distance to all previously spawned enemies
			if valid_position:
				for existing_pos in spawned_positions:
					if spawn_pos.distance_to(existing_pos) < MIN_SPAWN_DISTANCE:
						valid_position = false
						break

		# If we found a valid position (or ran out of attempts), spawn the enemy
		if valid_position or attempts >= MAX_ATTEMPTS:
			if attempts >= MAX_ATTEMPTS:
				print("  ⚠️ Max spawn attempts reached for enemy %d, using last position" % i)

			spawn_patrol_enemy(spawn_pos, int(lerp(min_level, max_level, float(i) / float(count - 1))))
			spawned_positions.append(spawn_pos)
			spawned += 1

	return spawned

func spawn_patrol_enemy(pos: Vector2, level: int):
	"""Spawn a single patrol enemy at position with level"""
	var enemy = ENEMY_SCENE.instantiate()
	enemy.global_position = pos
	enemy.name = "PatrolSkeleton_L%d_%d" % [level, randi()]

	# Set enemy level
	if enemy.has_method("set"):
		enemy.set("enemy_level", level)

	# Set aggro range to 150px for patrol enemies
	if enemy.has_node("EnemyAI"):
		var ai = enemy.get_node("EnemyAI")
		ai.aggro_range = 150.0

	add_child(enemy)

	# Add to enemies group
	enemy.add_to_group(Constants.GROUP_ENEMIES)

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

func spawn_training_dummy():
	"""Spawn a training dummy near the campfire for combat practice"""
	const DUMMY_SCENE = preload("res://scenes/training/training_dummy.tscn")

	# Spawn dummy south of campfire (campfire is at -2000, 0)
	var dummy_pos = Vector2(-2000, 180)  # South of campfire in cleared area

	var dummy = DUMMY_SCENE.instantiate()
	dummy.global_position = dummy_pos
	dummy.name = "TrainingDummy"
	add_child(dummy)

	print("🎯 Training Dummy spawned at: ", dummy_pos)

func spawn_bone_clusters(parent: Node2D):
	"""Spawn clusters of bones and skulls to create larger skeletal remains"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12121212

	var clusters_placed = 0

	# Spawn 40 bone clusters throughout the world (dense population)
	for i in range(40):
		var cluster_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		# Avoid campfire area
		var campfire_pos = Vector2(-2000, 0)
		if cluster_pos.distance_to(campfire_pos) < 600:
			continue

		# Don't place on lava pools
		var on_lava = false
		for pool in lava_pool_positions:
			var dist = cluster_pos.distance_to(pool.pos)
			var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + 150  # Larger buffer for clusters
			if dist < pool_radius:
				on_lava = true
				break
		if on_lava:
			continue

		# Prefer areas near the path but not on it
		var distance_from_path = abs(cluster_pos.y)
		if distance_from_path < 100:  # Too close to path
			continue

		# Create a cluster of 5-8 bones/skulls
		var num_items = rng.randi_range(5, 8)
		for j in range(num_items):
			var bone_types = ["skull", "bones"]
			var bone_type = bone_types[rng.randi() % bone_types.size()]

			# Position within cluster (50-150px radius)
			var angle = rng.randf() * TAU
			var distance = rng.randf_range(50, 150)
			var bone_pos = cluster_pos + Vector2(cos(angle), sin(angle)) * distance

			var prop_data = {
				"type": bone_type,
				"x": bone_pos.x,
				"y": bone_pos.y,
				"scale": rng.randf_range(0.8, 1.5),  # Larger bones
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": 0,
				"id": 8000 + clusters_placed * 10 + j
			}
			create_prop_sprite(prop_data, parent)

		clusters_placed += 1

	print("💀 Placed ", clusters_placed, " bone clusters (skeletal remains)")

func spawn_ground_cracks(parent: Node2D):
	"""Spawn large cracks in the dark ground areas"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 13131313

	var cracks_placed = 0

	# Spawn 100 cracks throughout the world (dense population)
	for i in range(100):
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
		var campfire_pos = Vector2(-2000, 0)
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
		var campfire_pos = Vector2(-2000, 0)
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
			"z_index": 0,
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
	particles.z_index = 100  # Above everything
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
	"""Create glowing lava pools scattered across the wasteland"""
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
		var campfire_pos = Vector2(-2000, 0)
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
			crack.default_color = Color(0.02, 0.015, 0.01, rng.randf_range(0.6, 0.9))  # Very dark cracks
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
		outer_border.color = Color(0.09, 0.085, 0.08, 0.3)  # Match ground color, very transparent
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
		mid_border.color = Color(0.07, 0.06, 0.055, 0.5)  # Darker, semi-transparent
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
		inner_border.color = Color(0.04, 0.03, 0.02, 0.7)  # Very dark, but still transparent
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
		light.enabled = true
		light.position = Vector2.ZERO
		light.color = Color(1.0, 0.5, 0.1, 1.0)  # Warm orange glow
		light.energy = rng.randf_range(1.0, 1.6)  # Vary intensity
		light.blend_mode = PointLight2D.BLEND_MODE_ADD  # Additive blending for glow
		light.range_z_min = -10
		light.range_z_max = 10
		light.shadow_enabled = false

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
		light.texture_scale = (pool_size / 80.0) * avg_elongation

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

# ═══════════════════════════════════════════════════════════════════════════
# TERRAIN BAKING FUNCTIONS (for generating high-quality texture once)
# ═══════════════════════════════════════════════════════════════════════════

func create_ground_texture_for_baking(viewport: SubViewport, offset: Vector2):
	"""Generate ground texture in viewport space"""
	var ground_layer = Node2D.new()
	ground_layer.name = "GroundTexture"
	ground_layer.z_index = -9
	viewport.add_child(ground_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	for x in range(Constants.WORLD_LEFT, Constants.WORLD_RIGHT, Constants.TERRAIN_PATCH_SPACING):
		for y in range(Constants.WORLD_TOP, Constants.WORLD_BOTTOM, Constants.TERRAIN_PATCH_SPACING):
			if rng.randf() > 0.2:
				continue

			var patch_pos = Vector2(
				x + rng.randf_range(-250, 250),
				y + rng.randf_range(-250, 250)
			)

			patch_pos.x = clamp(patch_pos.x, -5000, 13000)
			patch_pos.y = clamp(patch_pos.y, -3000, 3000)

			var base_size = rng.randf_range(100, 140)
			var elongation = rng.randf_range(0.7, 1.5)
			create_feathered_area(ground_layer, patch_pos + offset, base_size, rng, elongation)
		await get_tree().process_frame

func create_terrain_variation_for_baking(viewport: SubViewport, offset: Vector2):
	"""Generate terrain variation in viewport space"""
	var terrain_layer = Node2D.new()
	terrain_layer.name = "TerrainVariation"
	terrain_layer.z_index = -8
	viewport.add_child(terrain_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	for i in range(30):
		var terrain_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		var spot_size = rng.randf_range(300, 600)
		var elongation = rng.randf_range(0.4, 2.5)
		create_feathered_area(terrain_layer, terrain_pos + offset, spot_size, rng, elongation)
		await get_tree().process_frame

func create_rock_spots_for_baking(viewport: SubViewport, offset: Vector2):
	"""Generate rock dark spots in viewport space"""
	var rock_layer = Node2D.new()
	rock_layer.name = "RockSpots"
	rock_layer.z_index = -7
	viewport.add_child(rock_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	for i in range(100):
		var rock_pos = Vector2(
			rng.randf_range(-5000, 13000),
			rng.randf_range(-3000, 3000)
		)

		var campfire_pos = Vector2(-2000, 0)
		if rock_pos.distance_to(campfire_pos) < 450:
			continue

		var spot_size = rng.randf_range(120, 350)
		var elongation = rng.randf_range(0.6, 1.8)
		create_feathered_area(rock_layer, rock_pos + offset, spot_size, rng, elongation)
		await get_tree().process_frame

func create_campfire_clearing_for_baking(viewport: SubViewport, offset: Vector2):
	"""Generate campfire clearing in viewport space"""
	var clearing_layer = Node2D.new()
	clearing_layer.name = "CampfireClearing"
	clearing_layer.z_index = -6
	viewport.add_child(clearing_layer)

	var campfire_pos = Vector2(-2000, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	create_feathered_area(clearing_layer, campfire_pos + offset, 200, rng, 1.0, 0.12)

	# Ruins clearings
	create_feathered_area(clearing_layer, Vector2(1200, -2000) + offset, 340, rng, 1.0, 0.12)
	create_feathered_area(clearing_layer, Vector2(4800, 2200) + offset, 340, rng, 1.0, 0.12)
	create_feathered_area(clearing_layer, Vector2(8200, -2200) + offset, 340, rng, 1.0, 0.12)

func create_path_for_baking(viewport: SubViewport, offset: Vector2):
	"""Generate path in viewport space"""
	var path_layer = Node2D.new()
	path_layer.name = "PathLayer"
	path_layer.z_index = -5
	viewport.add_child(path_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 11111

	# Main path segments
	var path_points = [
		Vector2(-2000, 0),
		Vector2(-800, 0),
		Vector2(800, 0),
		Vector2(1200, -2000),
		Vector2(4800, 2200),
		Vector2(8200, -2200),
		Vector2(11000, -300)
	]

	# Generate path between points
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var distance = start.distance_to(end)
		var steps = int(distance / 200.0)

		for j in range(steps):
			var t = float(j) / float(steps)
			var pos = start.lerp(end, t)
			var elongation = rng.randf_range(0.8, 1.6)
			create_feathered_area(path_layer, pos + offset, 180, rng, elongation, 0.08)
		await get_tree().process_frame

	# Campfire circle
	var radius = 450.0
	var num_spots = 80
	for i in range(num_spots):
		var ring = int(i / 20)
		var angle = (i % 20) * (TAU / 20.0) + rng.randf_range(-0.2, 0.2)
		var ring_radius = (radius / 4.0) * (ring + 1) + rng.randf_range(-40, 40)
		var pos = Vector2(-2000, 0) + Vector2(cos(angle) * ring_radius, sin(angle) * ring_radius)
		create_feathered_area(path_layer, pos + offset, 160, rng, 1.0, 0.06)

## ============================================
## CORPSE LOOT SYSTEM
## ============================================

func setup_corpse_loot_system() -> void:
	"""Setup handlers for corpse looting system"""
	print("💀 Setting up corpse loot system...")

	# Connect to all existing enemies
	for enemy in get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES):
		if enemy.has_signal("corpse_clicked"):
			enemy.corpse_clicked.connect(_on_corpse_clicked)

	# Use a deferred call to listen for new enemies spawning
	get_tree().node_added.connect(_on_node_added)

	print("✅ Corpse loot system ready")

func _on_node_added(node: Node) -> void:
	"""Connect to newly spawned enemies"""
	if node.is_in_group(Constants.GROUP_ENEMIES):
		if node.has_signal("corpse_clicked"):
			node.corpse_clicked.connect(_on_corpse_clicked)

func _on_corpse_clicked(corpse) -> void:
	"""Handle corpse being clicked - open loot UI with AOE aggregation"""
	print("🎯 _on_corpse_clicked() HANDLER CALLED!")
	if not is_instance_valid(corpse):
		print("❌ Corpse not valid")
		return
	print("✅ Corpse is valid, proceeding...")

	# Find all nearby corpses within AOE radius
	print("📦 Finding nearby corpses...")
	var nearby_corpses = corpse.get_nearby_corpses(CorpseState.AOE_LOOT_RADIUS)
	print("📦 Found %d nearby corpses" % nearby_corpses.size())

	# Create and open loot UI (deferred to avoid blocking)
	print("📦 Starting deferred UI creation...")
	_create_loot_ui_deferred.call_deferred(corpse, nearby_corpses)
	print("✅ Deferred call queued")

func _create_loot_ui_deferred(corpse, nearby_corpses: Array) -> void:
	"""Create loot UI from scene file"""
	print("📦 Loading loot UI scene...")
	
	var loot_scene = load("res://scenes/ui/loot_body_ui.tscn")
	if not loot_scene:
		push_error("❌ Failed to load scene")
		return
	print("✅ Scene loaded")
	
	var loot_ui = loot_scene.instantiate()
	if not loot_ui:
		push_error("❌ Failed to instantiate")
		return
	print("✅ UI instantiated")
	
	get_tree().root.add_child(loot_ui)
	print("✅ Added to tree")
	
	loot_ui.loot_ui_closed.connect(func(): loot_ui.queue_free())
	loot_ui.open_loot_ui(corpse, nearby_corpses)
	print("✅ UI opened!")
func populate_world_enemies() -> void:
	"""Populate Zone 1 with directional spawning: N/W/S = noob area (1-5), E = progressive (1-10)"""
	print("\n🦴 Populating Zone 1 with directional spawning...")

	const CAMPFIRE_POS = Vector2(400, 0)
	const RUINS1_X = 2184  # Zone 1 eastern boundary
	const WORLD_NORTH = -2000  # Northern world edge
	const WORLD_SOUTH = 2000   # Southern world edge
	const WORLD_WEST = -2500   # Western world edge
	const SAFE_ZONE_RADIUS = 350  # Don't spawn too close to campfire
	const MIN_DISTANCE_FROM_PATH = 200
	const RESPAWN_DELAY = 60.0

	var spawners_node = Node2D.new()
	spawners_node.name = "Zone1EnemySpawners"
	add_child(spawners_node)

	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	var total_spawned = 0

	# NORTH AREA: Level 1-5 noob farming zone
	print("  📍 Spawning NORTH area (noob zone, levels 1-5)...")
	var north_spawned = spawn_noob_area(spawners_node, rng, CAMPFIRE_POS, "north",
		WORLD_NORTH, SAFE_ZONE_RADIUS, MIN_DISTANCE_FROM_PATH, RESPAWN_DELAY)
	total_spawned += north_spawned
	print("     ✅ North: %d enemies" % north_spawned)

	# WEST AREA: Level 1-5 noob farming zone
	print("  📍 Spawning WEST area (noob zone, levels 1-5)...")
	var west_spawned = spawn_noob_area(spawners_node, rng, CAMPFIRE_POS, "west",
		WORLD_WEST, SAFE_ZONE_RADIUS, MIN_DISTANCE_FROM_PATH, RESPAWN_DELAY)
	total_spawned += west_spawned
	print("     ✅ West: %d enemies" % west_spawned)

	# SOUTH AREA: Level 1-5 noob farming zone
	print("  📍 Spawning SOUTH area (noob zone, levels 1-5)...")
	var south_spawned = spawn_noob_area(spawners_node, rng, CAMPFIRE_POS, "south",
		WORLD_SOUTH, SAFE_ZONE_RADIUS, MIN_DISTANCE_FROM_PATH, RESPAWN_DELAY)
	total_spawned += south_spawned
	print("     ✅ South: %d enemies" % south_spawned)

	# EAST AREA: Progressive Level 1-10 toward Ruins 1
	print("  📍 Spawning EAST area (progressive zone, levels 1-10)...")
	var east_spawned = spawn_progressive_east(spawners_node, rng, CAMPFIRE_POS, RUINS1_X,
		SAFE_ZONE_RADIUS, MIN_DISTANCE_FROM_PATH, RESPAWN_DELAY)
	total_spawned += east_spawned
	print("     ✅ East: %d enemies" % east_spawned)

	print("\n✅ Zone 1 populated with %d total enemies" % total_spawned)
	print("   🧭 North/West/South: Noob areas (Level 1-5)")
	print("   🧭 East: Progressive difficulty (Level 1-10 → Ruins 1)")
	print("   📍 Respawn timer: %.0f seconds\n" % RESPAWN_DELAY)

func spawn_noob_area(parent: Node, rng: RandomNumberGenerator, campfire_pos: Vector2,
					 direction: String, world_edge: float, safe_zone: float,
					 path_clearance: float, respawn_delay: float) -> int:
	"""Spawn Level 1-5 enemies in a noob farming area (North/West/South)"""
	var spawned = 0
	const ENEMIES_PER_LEVEL = 3  # 3 enemies per level = 15 total per area
	const SPAWN_ATTEMPTS = 100

	# Spawn 3 enemies each of levels 1, 2, 3, 4, 5
	for level in range(1, 6):  # Level 1-5
		for i in range(ENEMIES_PER_LEVEL):
			for attempt in range(SPAWN_ATTEMPTS):
				var spawn_pos = generate_position_in_direction(
					rng, campfire_pos, direction, world_edge, safe_zone
				)

				# Validate position
				if not is_valid_spawn_position(spawn_pos, campfire_pos, safe_zone,
											   path_clearance):
					continue

				# Valid spawn
				create_enemy_spawner(parent, spawn_pos, level, 1, respawn_delay)
				spawned += 1
				break

	return spawned

func spawn_progressive_east(parent: Node, rng: RandomNumberGenerator, campfire_pos: Vector2,
							 ruins1_x: float, safe_zone: float, path_clearance: float,
							 respawn_delay: float) -> int:
	"""Spawn progressive Level 1-10 enemies going east toward Ruins 1"""
	var spawned = 0
	const LEVEL_BANDS = [
		{"level": 1, "min_x": 400 + 350, "max_x": 600},
		{"level": 2, "min_x": 600, "max_x": 800},
		{"level": 3, "min_x": 800, "max_x": 1000},
		{"level": 4, "min_x": 1000, "max_x": 1200},
		{"level": 5, "min_x": 1200, "max_x": 1400},
		{"level": 6, "min_x": 1400, "max_x": 1600},
		{"level": 7, "min_x": 1600, "max_x": 1800},
		{"level": 8, "min_x": 1800, "max_x": 2000},
		{"level": 9, "min_x": 2000, "max_x": 2200},
		{"level": 10, "min_x": 2200, "max_x": 2400}
	]

	const ENEMIES_PER_LEVEL = 4  # 4 enemies per level in progression zone
	const SPAWN_ATTEMPTS = 100

	for band in LEVEL_BANDS:
		var level = band["level"]
		var min_x = band["min_x"]
		var max_x = band["max_x"]

		for i in range(ENEMIES_PER_LEVEL):
			for attempt in range(SPAWN_ATTEMPTS):
				# Generate position in this X band, allowing east/northeast/southeast
				var x = rng.randf_range(min_x, max_x)
				var y = rng.randf_range(-1000, 1000)  # Spread vertically
				var spawn_pos = Vector2(x, y)

				# Check if position is actually eastward (not too far north/south)
				var angle_from_campfire = (spawn_pos - campfire_pos).angle()
				var degrees = rad_to_deg(angle_from_campfire)
				if degrees < 0:
					degrees += 360

				# East/Northeast/Southeast = roughly 315° to 45° (90° total arc)
				var is_eastward = (degrees >= 315 and degrees <= 360) or (degrees >= 0 and degrees <= 45)
				if not is_eastward:
					continue

				# Validate position
				if not is_valid_spawn_position(spawn_pos, campfire_pos, safe_zone, path_clearance):
					continue

				# Don't spawn past Ruins 1
				if spawn_pos.x > 2184:
					continue

				# Valid spawn
				create_enemy_spawner(parent, spawn_pos, level, 1, respawn_delay)
				spawned += 1
				break

	return spawned

func generate_position_in_direction(rng: RandomNumberGenerator, campfire_pos: Vector2,
									 direction: String, world_edge: float,
									 safe_zone: float) -> Vector2:
	"""Generate a random position in the specified direction from campfire"""
	var pos = Vector2.ZERO

	match direction:
		"north":
			# North of campfire to world edge
			pos.x = rng.randf_range(campfire_pos.x - 1000, campfire_pos.x + 1000)
			pos.y = rng.randf_range(world_edge, campfire_pos.y - safe_zone)
		"west":
			# West of campfire to world edge
			pos.x = rng.randf_range(world_edge, campfire_pos.x - safe_zone)
			pos.y = rng.randf_range(campfire_pos.y - 1000, campfire_pos.y + 1000)
		"south":
			# South of campfire to world edge
			pos.x = rng.randf_range(campfire_pos.x - 1000, campfire_pos.x + 1000)
			pos.y = rng.randf_range(campfire_pos.y + safe_zone, world_edge)

	return pos

func is_valid_spawn_position(pos: Vector2, campfire_pos: Vector2, safe_zone: float,
							  path_clearance: float) -> bool:
	"""Check if spawn position is valid"""
	# Too close to campfire?
	if pos.distance_to(campfire_pos) < safe_zone:
		return false

	# Too close to path?
	var path_start = campfire_pos
	var path_end = Vector2(7600, 0)
	var distance_from_path = point_to_line_distance(pos, path_start, path_end)
	if distance_from_path < path_clearance:
		return false

	# In ruins area?
	if is_in_ruins_area(pos):
		return false

	return true

func is_in_ruins_area(pos: Vector2) -> bool:
	"""Check if position is inside any ruins area"""
	const RUINS_RADIUS = 300  # Don't spawn enemies within ruins

	# Ruins 1 at (2184, -1216)
	if pos.distance_to(Vector2(2184, -1216)) < RUINS_RADIUS:
		return true

	# Ruins 2 position (estimate based on zone progression)
	if pos.distance_to(Vector2(4500, -1500)) < RUINS_RADIUS:
		return true

	# Ruins 3 position (estimate)
	if pos.distance_to(Vector2(6500, -800)) < RUINS_RADIUS:
		return true

	return false

func point_to_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	"""Calculate shortest distance from point to line segment"""
	var line_vec = line_end - line_start
	var point_vec = point - line_start
	var line_len_sq = line_vec.length_squared()

	if line_len_sq == 0:
		return point.distance_to(line_start)

	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var projection = line_start + t * line_vec
	return point.distance_to(projection)

func create_enemy_spawner(parent: Node, position: Vector2, level: int, count: int, respawn_delay: float) -> void:
	"""Create an enemy spawner node at the given position"""
	var spawner_scene = preload("res://scripts/systems/enemy_spawner.gd")
	var spawner = Node2D.new()
	spawner.set_script(spawner_scene)
	spawner.name = "EnemySpawner_L%d_%d" % [level, randi()]
	spawner.global_position = position

	# Set spawner properties
	spawner.set("enemy_scene", ENEMY_SCENE)
	spawner.set("max_enemies", count)
	spawner.set("respawn_delay", respawn_delay)
	spawner.set("enemy_level", level)

	# Create a marker for spawn position
	var marker = Marker2D.new()
	marker.global_position = position
	spawner.add_child(marker)

	parent.add_child(spawner)

	# Wait for spawner to be in tree, then set enemy level
	await get_tree().process_frame

	# The spawner will spawn enemies, we need to set their level after spawn
	# Connect to the spawner's enemy creation to set level
	if spawner.has_method("spawn_enemy_at"):
		# We'll need to modify the spawned enemy's level
		# This will be handled by connecting to signals or by modifying enemy_spawner.gd
		pass
