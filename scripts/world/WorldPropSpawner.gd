class_name WorldPropSpawner
extends RefCounted
## Handles prop spawning: trees, rocks, bones, vegetation, etc.
## Used by game_world.gd for static prop generation
##
## INTEGRATION GUIDE:
## -----------------
## To use this spawner in game_world.gd:
##
## 1. Add to game_world.gd variables:
##    var prop_spawner: WorldPropSpawner = null
##
## 2. In _ready():
##    prop_spawner = WorldPropSpawner.new(self, CAMPFIRE_POS)
##    prop_spawner.set_path_checker(is_position_on_path)  # Pass path check function
##    prop_spawner.set_lava_positions(lava_pool_positions)
##
## 3. For prop spawning:
##    prop_spawner.spawn_trees_everywhere_dynamic(scattered_props_node)
##    prop_spawner.spawn_rock_sprites(scattered_props_node)
##    prop_spawner.load_interactive_props(scattered_props_node)
##    prop_spawner.spawn_bone_clusters(scattered_props_node)
##
## 4. Get tree positions for other systems:
##    var trees = prop_spawner.get_tree_positions()

var world: Node2D

# Track spawned props
var tree_positions: Array = []
var lava_pool_positions: Array = []

# Campfire position
var campfire_pos: Vector2 = Vector2(Constants.CHUNK_SIZE / 2, 0)

# Prop textures (mirrors game_world.gd PROP_TEXTURES)
const PROP_TEXTURES = {
	"dead_tree": "res://assets/environment/dreadland/dead_tree.png",
	"pine_tree": "res://assets/environment/dreadland/pine_tree.png",
	"autumn_tree": "res://assets/environment/dreadland/autumn_tree.png",
	"rock_large": "res://assets/props/rock_large.png",
	"rock_small": "res://assets/props/rock_small.png",
	"skull": "res://assets/props/skull.png",
	"bones": "res://assets/props/bones.png",
	"broken_sword": "res://assets/props/broken_sword.png",
	"ash_pile": "res://assets/props/ash_pile.png",
	"ground_crack_1": "res://assets/props/ground_crack_1.png",
	"ground_crack_2": "res://assets/props/ground_crack_2.png",
}

# Tree scene files - collision positions can be edited visually in these scenes
const TREE_SCENES = {
	"dead_tree": "res://scenes/environment/DeadTree.tscn",
	"pine_tree": "res://scenes/environment/PineTree.tscn",
	"autumn_tree": "res://scenes/environment/AutumnTree.tscn"
}

# Tree types with weighted rarity: 60% dead, 30% pine, 10% autumn
var tree_types = ["dead_tree", "pine_tree", "autumn_tree"]

# Path checker function reference
var is_position_on_path_func: Callable

func _init(world_ref: Node2D, campfire_position: Vector2 = Vector2.ZERO) -> void:
	world = world_ref
	if campfire_position != Vector2.ZERO:
		campfire_pos = campfire_position

func set_path_checker(checker: Callable) -> void:
	"""Set the function to check if position is on path"""
	is_position_on_path_func = checker

func set_lava_positions(positions: Array) -> void:
	"""Set lava pool positions for collision avoidance"""
	lava_pool_positions = positions

func get_tree_positions() -> Array:
	"""Get all tree positions"""
	return tree_positions

# ========================================
# TREE SPAWNING
# ========================================

func spawn_trees_everywhere_dynamic(parent: Node2D) -> void:
	"""Spawn trees across the world"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777

	var trees_placed = 0

	for x in range(Constants.WORLD_LEFT, Constants.WORLD_RIGHT, Constants.TREE_GRID_SPACING):
		for y in range(Constants.WORLD_TOP, Constants.WORLD_BOTTOM, Constants.TREE_GRID_SPACING):
			if rng.randf() > Constants.TREE_SPAWN_RATE:
				continue

			var tree_pos = Vector2(
				x + rng.randf_range(-95, 95),
				y + rng.randf_range(-95, 95)
			)

			var buffer = 300.0
			tree_pos.x = clamp(tree_pos.x, -5000 + buffer, 13000 - buffer)
			tree_pos.y = clamp(tree_pos.y, -3000 + buffer, 3000 - buffer)

			# Avoid campfire area
			if tree_pos.distance_to(campfire_pos) < 700:
				continue

			# Don't place trees on the path
			if is_position_on_path_func.is_valid() and is_position_on_path_func.call(tree_pos, 350.0):
				continue

			# Don't place trees on lava pools
			if _is_on_lava(tree_pos, 50):
				continue

			# Weighted tree selection: 60% dead, 30% pine, 10% autumn
			var roll = rng.randf()
			var tree_type: String
			if roll < 0.6:
				tree_type = "dead_tree"
			elif roll < 0.9:
				tree_type = "pine_tree"
			else:
				tree_type = "autumn_tree"
			create_tree_at_position(parent, tree_pos, tree_type, rng)
			tree_positions.append(tree_pos)
			trees_placed += 1

	print("🌲 Placed %d trees (dynamic)" % trees_placed)

func create_tree_at_position(parent: Node2D, pos: Vector2, tree_type: String, rng: RandomNumberGenerator) -> void:
	"""Create a single tree at position using scene files (collision positions editable in scenes)"""
	if not TREE_SCENES.has(tree_type):
		return

	var scene_path = TREE_SCENES[tree_type]
	if not ResourceLoader.exists(scene_path):
		return

	var tree_scene = load(scene_path)
	var prop_container = tree_scene.instantiate()

	prop_container.name = tree_type + "_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	prop_container.collision_layer = 2
	prop_container.collision_mask = 0

	# Determine tree size
	var size_roll = rng.randf()
	var tree_scale: float
	if size_roll < 0.1:
		tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (10%)
	elif size_roll < 0.55:
		tree_scale = rng.randf_range(2.93, 3.9)   # Medium trees (45%)
	else:
		tree_scale = rng.randf_range(3.9, 5.2)    # Large trees (45%)

	var tree_flipped = rng.randf() < 0.5

	# Get nodes from scene
	var sprite = prop_container.get_node_or_null("Sprite")
	var shadow = prop_container.get_node_or_null("Shadow")
	var collision = prop_container.get_node_or_null("CollisionShape2D")

	if sprite:
		sprite.scale = Vector2(tree_scale, tree_scale)
		sprite.flip_h = tree_flipped

		# Tree color variation
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
		var shadow_width = 45 * (tree_scale / 2.5) * 0.75
		var shadow_height = shadow_width * 0.4
		shadow.size = Vector2(shadow_width, shadow_height)
		shadow.position = Vector2(-shadow_width / 2, 56 * tree_scale)

	if collision:
		# Scale collision position based on tree size (scene position is for scale 1.0)
		var base_collision_y = collision.position.y
		collision.position = Vector2(0, base_collision_y * tree_scale)
		if collision.shape is CircleShape2D:
			collision.shape.radius = 10 * tree_scale

	parent.add_child(prop_container)

# ========================================
# ROCK SPAWNING
# ========================================

func spawn_rock_sprites(parent: Node2D) -> void:
	"""Spawn large rock sprites"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	var rocks_placed = 0
	var buffer = 300.0

	for i in range(62):
		var rock_pos = Vector2(
			rng.randf_range(-5000 + buffer, 13000 - buffer),
			rng.randf_range(-3000 + buffer, 3000 - buffer)
		)

		if rock_pos.distance_to(campfire_pos) < 450:
			continue

		if is_position_on_path_func.is_valid() and is_position_on_path_func.call(rock_pos, 150.0):
			continue

		# Check distance to trees
		var too_close_to_tree = false
		for tree_pos in tree_positions:
			if rock_pos.distance_to(tree_pos) < 100:
				too_close_to_tree = true
				break
		if too_close_to_tree:
			continue

		if _is_on_lava(rock_pos, 20):
			continue

		create_rock_at_position(parent, rock_pos, rng)
		rocks_placed += 1

	print("🪨 Placed %d rock sprites" % rocks_placed)

func create_rock_at_position(parent: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Create a single rock at position"""
	var HarvestableRockClass = preload("res://scripts/environment/HarvestableRock.gd")
	var prop_container = HarvestableRockClass.new()
	prop_container.name = "rock_large_at_" + str(pos.x) + "_" + str(pos.y)
	prop_container.position = pos
	prop_container.collision_layer = 2
	prop_container.collision_mask = 0

	var texture_path = PROP_TEXTURES["rock_large"]
	if not ResourceLoader.exists(texture_path):
		return

	var texture = load(texture_path)

	# Rock size
	var size_roll = rng.randf()
	var rock_scale: float
	if size_roll < 0.4:
		rock_scale = rng.randf_range(1.5, 2.0)    # Large
	elif size_roll < 0.75:
		rock_scale = rng.randf_range(2.0, 2.75)   # Extra Large
	else:
		rock_scale = rng.randf_range(2.75, 3.5)   # XXL Boulders

	# Create shadow
	var shadow_width = 45 * (rock_scale / 1.5)
	var shadow = _create_shadow(shadow_width, (48 * rock_scale / 2.5) - 2, -4)
	shadow.position.x += 3  # Offset
	prop_container.add_child(shadow)

	# Create sprite
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(rock_scale, rock_scale)
	sprite.flip_h = rng.randf() < 0.5
	sprite.rotation = rng.randf_range(-PI/6, PI/6)
	sprite.z_index = 0

	var color_variation = rng.randf_range(0.8, 1.0)
	sprite.modulate = Color(color_variation, color_variation, color_variation)

	prop_container.add_child(sprite)

	# Collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 20 * rock_scale
	collision_shape.shape = shape
	prop_container.add_child(collision_shape)

	# Set ore amount
	if rock_scale < 2.0:
		prop_container.ore_amount = 1
	elif rock_scale < 2.75:
		prop_container.ore_amount = 2
	else:
		prop_container.ore_amount = 3

	parent.add_child(prop_container)

# ========================================
# INTERACTIVE PROPS (skulls, bones, swords)
# ========================================

func load_interactive_props(parent: Node2D) -> void:
	"""Spawn battle props along the path"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765

	var battle_props = ["skull", "bones", "broken_sword"]
	var props_placed = 0

	# Main path props
	for i in range(50):
		var prop_type = battle_props[rng.randi() % battle_props.size()]

		var attempts = 0
		var prop_pos = Vector2.ZERO
		var valid_position = false
		while attempts < 50:
			prop_pos = Vector2(
				rng.randf_range(-2200, 11200),
				rng.randf_range(-2500, 2500)
			)
			if is_position_on_path_func.is_valid() and is_position_on_path_func.call(prop_pos, 100.0):
				if not _is_too_close_to_tree(prop_pos, 100) and not _is_on_lava(prop_pos, 30):
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
				"id": 2000 + i
			}
			create_prop_sprite(prop_data, parent)
			props_placed += 1

	print("⚔️ Placed %d battle props" % props_placed)

func create_prop_sprite(prop_data: Dictionary, parent: Node2D) -> bool:
	"""Create a generic prop sprite"""
	var prop_container = Node2D.new()
	prop_container.name = prop_data.get("type", "prop") + "_" + str(prop_data.get("id", 0))
	prop_container.position = Vector2(prop_data.get("x", 0), prop_data.get("y", 0))

	var prop_type = prop_data.get("type", "")
	var scale_val = prop_data.get("scale", 1.0)
	var rotation_val = _get_safe_rotation(prop_type, prop_data.get("rotation", 0.0))

	if not PROP_TEXTURES.has(prop_type):
		return false

	var texture_path = PROP_TEXTURES[prop_type]
	if not ResourceLoader.exists(texture_path):
		return false

	var texture = load(texture_path)

	# Create shadow
	var shadow_width = 20 * scale_val
	var shadow_y = (24 * scale_val / 4) - 3

	if prop_type == "broken_sword":
		shadow_width = 32 * scale_val
		shadow_y = 2 * scale_val

	var shadow = _create_shadow(shadow_width, shadow_y, -4)
	prop_container.add_child(shadow)

	# Create sprite
	var sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.scale = Vector2(scale_val, scale_val)
	sprite.flip_h = prop_data.get("flip_h", false)
	sprite.z_index = prop_data.get("z_index", -1)
	sprite.rotation = rotation_val

	var brightness = prop_data.get("brightness", randf_range(0.8, 1.0))
	sprite.modulate = Color(brightness, brightness, brightness, 1.0)

	prop_container.add_child(sprite)
	parent.add_child(prop_container)
	return true

# ========================================
# BONE CLUSTERS
# ========================================

func spawn_bone_clusters(parent: Node2D) -> void:
	"""Spawn clusters of bones and skulls"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12121212

	var clusters_placed = 0
	var scattered_placed = 0

	# Dense bone clusters
	for i in range(60):
		var cluster_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		if cluster_pos.distance_to(campfire_pos) < 600:
			continue
		if _is_on_lava(cluster_pos, 150):
			continue

		var num_items = rng.randi_range(8, 15)
		for j in range(num_items):
			var bone_types = ["skull", "bones"]
			var bone_type = bone_types[rng.randi() % bone_types.size()]

			var angle = rng.randf() * TAU
			var distance = rng.randf_range(30, 120)
			var bone_pos = cluster_pos + Vector2(cos(angle), sin(angle)) * distance

			var prop_data = {
				"type": bone_type,
				"x": bone_pos.x,
				"y": bone_pos.y,
				"scale": rng.randf_range(0.7, 1.4),
				"rotation": rng.randf() * TAU,
				"flip_h": rng.randf() < 0.5,
				"z_index": 0,
				"id": 8000 + clusters_placed * 20 + j
			}
			create_prop_sprite(prop_data, parent)

		clusters_placed += 1

	# Scattered individual bones
	for i in range(400):
		var bone_pos = Vector2(
			rng.randf_range(-4000, 12000),
			rng.randf_range(-2500, 2500)
		)

		if bone_pos.distance_to(campfire_pos) < 500:
			continue
		if _is_on_lava(bone_pos, 100):
			continue

		var bone_type = "bones" if rng.randf() < 0.75 else "skull"

		var prop_data = {
			"type": bone_type,
			"x": bone_pos.x,
			"y": bone_pos.y,
			"scale": rng.randf_range(0.4, 0.9),
			"rotation": rng.randf() * TAU,
			"flip_h": rng.randf() < 0.5,
			"z_index": 0,
			"id": 9000 + scattered_placed
		}
		create_prop_sprite(prop_data, parent)
		scattered_placed += 1

	print("💀 Placed %d bone clusters + %d scattered bones" % [clusters_placed, scattered_placed])

# ========================================
# UTILITY FUNCTIONS
# ========================================

func _create_shadow(width: float, y_pos: float, z: int) -> ColorRect:
	"""Create an oval shadow ColorRect"""
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_height = width * 0.4
	shadow.size = Vector2(width, shadow_height)
	shadow.position = Vector2(-width/2, y_pos)
	shadow.color = Color(0, 0, 0, 0.6)
	shadow.z_index = z

	# Apply oval shader
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	if (dist > 1.0) {
		discard;
	}
	float alpha = 1.0 - smoothstep(0.6, 1.0, dist);
	COLOR.a *= alpha;
}
"""
	shader_material.shader = shader
	shadow.material = shader_material

	return shadow

func _is_on_lava(pos: Vector2, buffer: float) -> bool:
	"""Check if position overlaps with any lava pool"""
	for pool in lava_pool_positions:
		var dist = pos.distance_to(pool.pos)
		var pool_radius = (pool.size / 2) * max(pool.elongation_x, pool.elongation_y) + buffer
		if dist < pool_radius:
			return true
	return false

func _is_too_close_to_tree(pos: Vector2, min_distance: float) -> bool:
	"""Check if position is too close to any tree"""
	for tree_pos in tree_positions:
		if pos.distance_to(tree_pos) < min_distance:
			return true
	return false

func _get_safe_rotation(prop_type: String, requested_rotation: float) -> float:
	"""Get safe rotation for prop type"""
	match prop_type:
		"dead_tree_1", "dead_tree_2", "dead_tree_3", "dead_tree_4", "dead_tree_5", \
		"dead_tree_6", "dead_tree_7", "dead_tree_8", "dead_tree_9", "dead_tree_10", "ash_pile":
			return 0.0
		_:
			return requested_rotation
