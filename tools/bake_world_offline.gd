# bake_world_offline.gd
# Run this scene ONCE to generate the world texture, then never again
extends Node2D

const PROP_TEXTURES = {
	"dead_tree_1": "res://assets/environment/wasteland/dead_tree_1.png",
	"dead_tree_2": "res://assets/environment/wasteland/dead_tree_2.png",
	"dead_tree_3": "res://assets/environment/wasteland/dead_tree_3.png",
	# Zone-based rock textures (zone1 used for baking)
	"rock_large": "res://assets/environment/wasteland/rocks/zone1/rock_large_1.png",
	"rock_medium": "res://assets/environment/wasteland/rocks/zone1/rock_medium_1.png",
	"rock_small": "res://assets/environment/wasteland/rocks/zone1/rock_small_1.png",
	"skull": "res://assets/environment/wasteland/skull.png",
	"bones": "res://assets/environment/wasteland/bones.png",
	"ground_crack_1": "res://assets/environment/wasteland/ground_crack_1.png",
	"ground_crack_2": "res://assets/environment/wasteland/ground_crack_2.png",
	"broken_sword": "res://assets/environment/wasteland/broken_sword.png",
	"ash_pile": "res://assets/environment/wasteland/ash_pile.png"
}

const LAYER_TEMPLATE = [
	{"count": 80, "size_mult": [1.4, 1.9], "spread_mult": 1.2, "darkness": 0.24, "alpha": 0.003},
	{"count": 75, "size_mult": [1.3, 1.8], "spread_mult": 1.1, "darkness": 0.23, "alpha": 0.005},
	{"count": 70, "size_mult": [1.2, 1.7], "spread_mult": 1.0, "darkness": 0.22, "alpha": 0.008},
	{"count": 65, "size_mult": [1.1, 1.6], "spread_mult": 0.9, "darkness": 0.21, "alpha": 0.011},
	{"count": 55, "size_mult": [1.0, 1.45], "spread_mult": 0.75, "darkness": 0.20, "alpha": 0.018},
	{"count": 50, "size_mult": [0.85, 1.25], "spread_mult": 0.65, "darkness": 0.18, "alpha": 0.025},
	{"count": 45, "size_mult": [0.7, 1.05], "spread_mult": 0.55, "darkness": 0.16, "alpha": 0.032},
	{"count": 40, "size_mult": [0.6, 0.9], "spread_mult": 0.45, "darkness": 0.15, "alpha": 0.040},
	{"count": 32, "size_mult": [0.475, 0.725], "spread_mult": 0.35, "darkness": 0.14, "alpha": 0.048},
	{"count": 25, "size_mult": [0.375, 0.575], "spread_mult": 0.25, "darkness": 0.12, "alpha": 0.058},
	{"count": 20, "size_mult": [0.275, 0.45], "spread_mult": 0.15, "darkness": 0.11, "alpha": 0.070},
	{"count": 16, "size_mult": [0.2, 0.35], "spread_mult": 0.05, "darkness": 0.10, "alpha": 0.082}
]

var tree_types = ["dead_tree_1", "dead_tree_2", "dead_tree_3"]

func _ready():
	print("================================================================================")
	print("🎨 OFFLINE WORLD BAKER")
	print("================================================================================")
	print("This will generate the world texture and save it to:")
	print("  res://assets/environment/baked_world_background.png")
	print("")
	print("⏳ Starting in 2 seconds...")
	print("================================================================================")

	await get_tree().create_timer(2.0).timeout
	await bake_world_to_file()

func bake_world_to_file():
	print("\n🔨 Step 1: Generating world layers...")

	# Create temporary container
	var temp_world = Node2D.new()
	temp_world.name = "TempWorld"
	add_child(temp_world)

	# Generate all visual layers (same as game_world.gd)
	await create_ground_texture_in(temp_world)
	print("  ✓ Ground texture complete")

	await create_terrain_variation_spots_in(temp_world)
	print("  ✓ Terrain variation complete")

	await create_rock_clusters_with_dark_spots_in(temp_world)
	print("  ✓ Rock clusters complete")

	await create_campfire_clearing_smooth_in(temp_world)
	print("  ✓ Campfire clearing complete")

	await create_path_to_castle_smooth_in(temp_world)
	print("  ✓ Path to castle complete")

	# SKIPPING visual props - they're too small to see in baked texture anyway
	# await load_visual_props_in(temp_world)
	print("  ✓ Visual props skipped (too small for baked texture)")

	print("\n🎨 Step 2: Rendering to texture...")

	# Define world bounds
	var world_min = Vector2(-3000, -2500)
	var world_max = Vector2(9000, 2500)
	var world_size = world_max - world_min

	# Offset temp_world for viewport
	temp_world.position = -world_min

	# Create SubViewport for rendering
	var viewport = SubViewport.new()
	viewport.size = world_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.transparent_bg = false

	# Background color
	var bg_rect = ColorRect.new()
	bg_rect.size = world_size
	bg_rect.color = Color(0.40997362, 0.33598864, 0.27249303, 1)  # Match Ground color from scene
	viewport.add_child(bg_rect)

	# Move world to viewport
	remove_child(temp_world)
	viewport.add_child(temp_world)

	# Add viewport to scene tree
	get_tree().root.add_child(viewport)

	# Force render
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame for safety

	print("  ✓ Rendering complete")

	print("\n💾 Step 3: Saving to PNG...")

	# Get rendered texture
	var img = viewport.get_texture().get_image()

	# Save to file
	var save_path = "res://assets/environment/baked_world_background.png"
	var error = img.save_png(save_path)

	if error == OK:
		print("  ✅ SUCCESS! Saved to: " + save_path)
		print("")
		print("================================================================================")
		print("✨ BAKING COMPLETE!")
		print("================================================================================")
		print("Next steps:")
		print("  1. Close this scene")
		print("  2. Run your main game - it will now load instantly!")
		print("================================================================================")
	else:
		print("  ❌ ERROR: Failed to save PNG (error code: " + str(error) + ")")

	# Cleanup
	get_tree().root.remove_child(viewport)
	viewport.queue_free()

	# Exit after a moment
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()

# Copy all the generation functions from game_world.gd below:

func create_ground_texture_in(container: Node2D):
	var ground_texture_layer = Node2D.new()
	ground_texture_layer.name = "GroundTexture"
	container.add_child(ground_texture_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var patch_count = 0
	# REDUCED spacing from 400 to 600 for faster baking
	for x in range(-5000, 13000, 600):
		for y in range(-3000, 3000, 600):
			if rng.randf() > 0.5:
				continue

			var patch_pos = Vector2(
				x + rng.randf_range(-250, 250),
				y + rng.randf_range(-250, 250)
			)

			var base_size = rng.randf_range(100, 140)
			var elongation = rng.randf_range(0.7, 1.5)
			create_feathered_area(ground_texture_layer, patch_pos, base_size, rng, elongation)

			patch_count += 1
			if patch_count % 3 == 0:
				print("    Ground patches: " + str(patch_count))
				await get_tree().process_frame

func create_terrain_variation_spots_in(container: Node2D):
	var terrain_layer = Node2D.new()
	terrain_layer.name = "TerrainVariation"
	container.add_child(terrain_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	for i in range(30):
		var terrain_pos = Vector2(
			rng.randf_range(-4000, 10000),
			rng.randf_range(-2500, 2500)
		)

		var spot_size = rng.randf_range(300, 600)
		var elongation = rng.randf_range(0.4, 2.5)

		create_feathered_area(terrain_layer, terrain_pos, spot_size, rng, elongation)

		if i % 3 == 0:
			await get_tree().process_frame

func create_rock_clusters_with_dark_spots_in(container: Node2D):
	var rock_spots_layer = Node2D.new()
	rock_spots_layer.name = "RockSpots"
	container.add_child(rock_spots_layer)

	# Skip rock sprites in baking - just create the dark spots
	# var rock_sprites = Node2D.new()
	# rock_sprites.name = "RockSprites"
	# container.add_child(rock_sprites)

	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	for i in range(85):
		var rock_pos = Vector2(
			rng.randf_range(-3000, 9000),
			rng.randf_range(-2000, 2000)
		)

		if rock_pos.distance_to(Vector2.ZERO) < 450:
			continue

		var spot_size = rng.randf_range(120, 350)
		var elongation = rng.randf_range(0.6, 1.8)

		create_feathered_area(rock_spots_layer, rock_pos, spot_size, rng, elongation)
		# Skip creating rock sprites - just the dark spots matter for baked texture
		# create_rock_at_position(rock_sprites, rock_pos, rng)

		if i % 5 == 0:
			await get_tree().process_frame

func create_campfire_clearing_smooth_in(container: Node2D):
	var clearing_layer = Node2D.new()
	clearing_layer.name = "CampfireClearing"
	container.add_child(clearing_layer)

	var campfire_pos = Vector2(0, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	create_feathered_area(clearing_layer, campfire_pos, 200, rng, 1.0)

func create_path_to_castle_smooth_in(container: Node2D):
	var path_layer = Node2D.new()
	path_layer.name = "PathToCastle"
	container.add_child(path_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 777

	var campfire_pos = Vector2(0, 0)
	var castle_pos = Vector2(7600, 0)

	var path_points = []
	# REDUCED from 100 to 50 points for faster baking
	for i in range(50):
		var t = float(i) / 49.0
		var pos = campfire_pos.lerp(castle_pos, t)

		if i > 0 and i < 49:
			var curve_amount = sin(t * PI) * 250
			pos.y += sin(t * PI * 2.5) * curve_amount

		path_points.append(pos)

	var spot_count = 0
	for i in range(path_points.size() - 1):
		var start = path_points[i]
		var end = path_points[i + 1]
		var segment_length = start.distance_to(end)

		# REDUCED spot density from 30 to 60 for faster baking
		var num_spots = int(segment_length / 60) + 1

		for j in range(num_spots):
			var t = float(j) / float(max(1, num_spots - 1))
			var pos = start.lerp(end, t)

			var direction = (end - start).normalized()
			var elongation = 1.5
			if abs(direction.x) > abs(direction.y):
				elongation = 1.6
			else:
				elongation = 0.8

			# Use simpler feathering for path (not the wide version)
			create_feathered_area(path_layer, pos, 180, rng, elongation)

			spot_count += 1
			if spot_count % 5 == 0:
				print("    Path spots: " + str(spot_count))
				await get_tree().process_frame

func load_visual_props_in(container: Node2D):
	var props_layer = Node2D.new()
	props_layer.name = "VisualProps"
	container.add_child(props_layer)

	var rng = RandomNumberGenerator.new()
	rng.seed = 98765

	var visual_props = ["ash_pile", "ground_crack_1", "ground_crack_2"]

	for i in range(800):
		var prop_type = visual_props[rng.randi() % visual_props.size()]
		var prop_pos = Vector2(
			rng.randf_range(-3000, 8000),
			rng.randf_range(-1500, 1500)
		)

		if not is_position_on_path(prop_pos, 100.0):
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
			create_prop_sprite(prop_data, props_layer)

		if i % 50 == 0:
			await get_tree().process_frame

func create_feathered_area(parent: Node2D, center: Vector2, base_size: float, rng: RandomNumberGenerator, elongation: float = 1.0):
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

			var darkness = layer_data["darkness"] * rng.randf_range(0.85, 1.15)
			rect.color = Color(
				darkness,
				darkness * 0.8,
				darkness * 0.5,
				layer_data["alpha"]
			)

			rect.rotation = rng.randf() * TAU
			parent.add_child(rect)

func create_feathered_area_wide_path(parent: Node2D, center: Vector2, base_size: float, rng: RandomNumberGenerator, elongation: float = 1.0):
	var path_layers = [
		{"count": 80, "size_mult": [1.4, 1.9], "spread_mult": 1.4, "darkness": 0.24, "alpha": 0.003},
		{"count": 75, "size_mult": [1.3, 1.8], "spread_mult": 1.3, "darkness": 0.23, "alpha": 0.005},
		{"count": 70, "size_mult": [1.2, 1.7], "spread_mult": 1.2, "darkness": 0.22, "alpha": 0.008},
		{"count": 65, "size_mult": [1.1, 1.6], "spread_mult": 1.1, "darkness": 0.21, "alpha": 0.011},
		{"count": 55, "size_mult": [1.0, 1.45], "spread_mult": 1.0, "darkness": 0.20, "alpha": 0.018},
		{"count": 50, "size_mult": [0.85, 1.25], "spread_mult": 0.9, "darkness": 0.18, "alpha": 0.025},
		{"count": 45, "size_mult": [0.7, 1.05], "spread_mult": 0.8, "darkness": 0.16, "alpha": 0.032},
		{"count": 40, "size_mult": [0.6, 0.9], "spread_mult": 0.7, "darkness": 0.15, "alpha": 0.040},
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

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator):
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
