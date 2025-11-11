# game_world.gd - Optimized runtime generation (no baking needed!)
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

const LAYER_TEMPLATE = [
	# PERFORMANCE MODE: Reduced from 12 layers to 4 layers for smooth gameplay
	# Each spot now creates ~100 rects instead of ~573 (83% reduction)
	{"count": 40, "size_mult": [1.2, 1.6], "spread_mult": 0.8, "darkness": 0.22, "alpha": 0.015},
	{"count": 30, "size_mult": [0.9, 1.3], "spread_mult": 0.6, "darkness": 0.18, "alpha": 0.030},
	{"count": 20, "size_mult": [0.6, 0.9], "spread_mult": 0.4, "darkness": 0.14, "alpha": 0.050},
	{"count": 10, "size_mult": [0.3, 0.5], "spread_mult": 0.2, "darkness": 0.10, "alpha": 0.080}
]

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3"]
var screenshot_mode = false
var tree_positions = []  # Track tree positions to avoid spawning small rocks on them

func _ready():
	print("🗺️ GameWorld initializing (optimized - no baking needed)...")

	# Generate optimized world layers directly (reduced from 267k to ~40k nodes)
	await generate_optimized_world_layers()

	# Generate dynamic elements (trees, enemies, props)
	generate_dynamic_elements()

	print("✅ GameWorld ready!")

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
	for x in range(-5000, 13000, 900):
		for y in range(-3000, 3000, 900):
			if rng.randf() > 0.6:
				continue

			var patch_pos = Vector2(
				x + rng.randf_range(-250, 250),
				y + rng.randf_range(-250, 250)
			)

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

	# Performance mode: 12 spots for smooth gameplay
	for i in range(12):
		var terrain_pos = Vector2(
			rng.randf_range(-4000, 10000),
			rng.randf_range(-2500, 2500)
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

	# Performance mode: 40 spots for smooth gameplay
	for i in range(40):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
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
	
	for x in range(-3000, 9000, 200):
		for y in range(-2000, 2000, 200):
			if rng.randf() > 0.35:
				continue
			
			var tree_pos = Vector2(
				x + rng.randf_range(-95, 95),
				y + rng.randf_range(-95, 95)
			)

			# Avoid campfire area (larger radius to account for large trees and campfire circle)
			if tree_pos.distance_to(Vector2.ZERO) < 700:
				continue

			# Don't place trees on the path - only battle props (skull, bones, sword) go there
			if is_position_on_path(tree_pos, 250.0):
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

	# Use same seed/positions as rock dark spots
	for i in range(40):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
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

	# Reduced from 800 to 200 for performance
	for i in range(200):
		var prop_type = visual_props[rng.randi() % visual_props.size()]
		var prop_pos = Vector2(
			rng.randf_range(-3000, 8000),
			rng.randf_range(-1500, 1500)
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

	# Lots of small rocks to fill in bare areas (500 rocks)
	for i in range(500):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
		)

		# Avoid campfire area
		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue

		# Don't place on the path
		if is_position_on_path(rock_pos, 150.0):
			continue

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
	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)
	
	if pos.x < campfire_pos.x or pos.x > castle_pos.x:
		return false
	
	var t = pos.x / 7600.0
	var path_y = 0.0
	if t > 0 and t < 1:
		var curve_amount = sin(t * PI) * 250
		path_y = sin(t * PI * 2.5) * curve_amount
	
	var distance_from_path = abs(pos.y - path_y)
	return distance_from_path <= path_width

func create_tree_at_position(parent: Node2D, pos: Vector2, tree_type: String, rng: RandomNumberGenerator):
	var prop_container = Node2D.new()
	prop_container.name = tree_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos

	var texture_path = PROP_TEXTURES[tree_type]
	if not ResourceLoader.exists(texture_path):
		return

	var texture = load(texture_path)

	# Determine tree size (small, medium, large for more variety)
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.3:
		tree_scale = rng.randf_range(1.5, 2.25)  # Small trees
	elif size_roll < 0.7:
		tree_scale = rng.randf_range(2.25, 3.0)  # Medium trees
	else:
		tree_scale = rng.randf_range(3.0, 4.0)  # Large trees

	var tree_flipped = rng.randf() < 0.5

	# Create simple dark oval shadow at base of tree
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 60 * (tree_scale / 2.5)  # Scale shadow with tree
	var shadow_height = shadow_width * 0.4  # Oval shape
	shadow.size = Vector2(shadow_width, shadow_height)
	# Position at bottom of tree - offset scales with tree size
	var shadow_y = (64 * tree_scale / 2) + (tree_scale * 8)  # Scales: small=60, medium=100, large=160
	# Adjust shadow X based on tree direction (flipped trees slant left)
	var shadow_x = -shadow_width/2 + (5 if not tree_flipped else -8)
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
	parent.add_child(prop_container)

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator):
	var prop_container = Node2D.new()
	prop_container.name = "rock_large_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos

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
		"dead_tree_1", "dead_tree_2", "dead_tree_3", "ash_pile":
			return 0.0
		_:
			return requested_rotation

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

	# Use existing PathMarkers node from scene (don't create new one)
	var path_markers_node = get_node_or_null("PathMarkers")
	if not path_markers_node:
		# Fallback: create if it doesn't exist
		path_markers_node = Node2D.new()
		path_markers_node.name = "PathMarkers"
		add_child(path_markers_node)

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
		"medium":
			enemy.modulate = Color(1.0, 1.0, 0.5)
		"hard":
			enemy.modulate = Color(1.0, 0.5, 0.5)
	
	add_child(enemy)
