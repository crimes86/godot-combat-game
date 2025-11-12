extends StaticBody2D
class_name HarvestableTree

## Harvestable Tree - Can be chopped for wood
## Press E when near to chop down the tree
## Drops wood that can be sold for gold
## Tree respawns after 120 seconds

# Harvesting
var player_in_range: bool = false
var is_harvested: bool = false
var interaction_prompt: Label = null
var interaction_area: Area2D = null

# Respawn
var respawn_time: float = 120.0  # 2 minutes to respawn
var respawn_timer: float = 0.0

# Visual references (set by game_world.gd)
var tree_sprite: Sprite2D = null
var tree_shadow: Node = null
var original_modulate: Color = Color.WHITE
var original_scale: Vector2 = Vector2.ONE

# Resource yield
var wood_amount: int = 0  # Set based on tree size (1-3 wood)

func _ready() -> void:
	print("🌲 HarvestableTree._ready() started for: ", name)

	# Find sprite and shadow from children (created by game_world.gd)
	tree_sprite = get_node_or_null("Sprite")
	tree_shadow = get_node_or_null("Shadow")

	print("   Found sprite: ", tree_sprite != null)
	print("   Found shadow: ", tree_shadow != null)

	if tree_sprite:
		original_modulate = tree_sprite.modulate
		original_scale = tree_sprite.scale

		# Determine wood amount based on tree size
		var tree_scale_avg = (tree_sprite.scale.x + tree_sprite.scale.y) / 2.0
		if tree_scale_avg < 2.5:
			wood_amount = 1  # Small trees
		elif tree_scale_avg < 4.0:
			wood_amount = 2  # Medium trees
		else:
			wood_amount = 3  # Large trees

		print("   Tree scale: %.2f, wood amount: %d" % [tree_scale_avg, wood_amount])

	# Create interaction area
	create_interaction_area()

	# Create interaction prompt
	create_interaction_prompt()

	print("🌲 HarvestableTree._ready() completed")

func _physics_process(delta: float) -> void:
	# Handle respawn timer
	if is_harvested:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn_tree()
		return

	# Update interaction prompt visibility
	if interaction_prompt:
		var should_show = player_in_range and not is_harvested
		if should_show != interaction_prompt.visible:
			interaction_prompt.visible = should_show
			if should_show:
				print("   🪵 Showing tree chop prompt")
			else:
				print("   🪵 Hiding tree chop prompt")

		if should_show:
			update_prompt_position()

	# Check for E key press when player is in range
	if player_in_range and not is_harvested:
		if Input.is_key_pressed(KEY_E):
			print("🪓 E key pressed near tree!")
			chop_tree()

func create_interaction_area() -> void:
	"""Create Area2D to detect player proximity"""
	print("   Creating interaction area...")
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1  # Detect player on layer 1
	add_child(interaction_area)

	# Create larger interaction radius than collision
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 80.0  # Generous harvest range
	collision.shape = shape

	# Position at base of tree (same as collision shape)
	if tree_sprite:
		collision.position = Vector2(0, 50 * tree_sprite.scale.y)
		print("   Collision position: ", collision.position)
	else:
		collision.position = Vector2(0, 100)
		print("   Collision position (no sprite): ", collision.position)

	interaction_area.add_child(collision)

	# Connect signals
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	print("   Interaction area created and signals connected")

func create_interaction_prompt() -> void:
	"""Create floating [E] prompt above tree"""
	print("   Creating interaction prompt...")
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[E] Chop Tree"
	interaction_prompt.add_theme_font_size_override("font_size", 12)
	interaction_prompt.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Light green
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)
	print("   Interaction prompt created")

func update_prompt_position() -> void:
	"""Update prompt position to stay above tree on screen"""
	if not interaction_prompt or not tree_sprite:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Calculate screen position above tree
	var tree_height = 64 * tree_sprite.scale.y  # Approximate tree height
	var world_pos = global_position + Vector2(0, -tree_height - 20)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var relative_pos = (world_pos - camera_pos) * camera.zoom.x + screen_center
	interaction_prompt.position = relative_pos - interaction_prompt.size / 2

func chop_tree() -> void:
	"""Chop down the tree and drop wood"""
	if is_harvested:
		return

	is_harvested = true
	respawn_timer = 0.0
	print("🪓 Chopping tree at position %s (yields %d wood)" % [global_position, wood_amount])

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Spawn wood items
	spawn_wood_drops()

	# Animate tree falling/fading
	animate_tree_chop()

func spawn_wood_drops() -> void:
	"""Spawn wood items at tree base"""
	var wood_item_data = {
		"name": "Dead Wood",
		"description": "Dry wood from a dead wasteland tree. Burns well.",
		"value": 12
	}

	# Try to add wood to inventory
	var added_count = 0
	for i in range(wood_amount):
		if InventorySystem.add_item(wood_item_data.duplicate()):
			added_count += 1
		else:
			print("⚠️ Inventory full! Could not collect all wood.")
			break

	if added_count > 0:
		print("  🪵 Collected %d wood (Value: %d gold each)" % [added_count, wood_item_data["value"]])

func animate_tree_chop() -> void:
	"""Animate tree being chopped down"""
	if not tree_sprite:
		return

	# Fade out and shrink
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(tree_sprite, "modulate:a", 0.2, 1.0)  # Mostly transparent
	tween.tween_property(tree_sprite, "scale", original_scale * 0.8, 1.0)

	# Also fade shadow
	if tree_shadow:
		tween.tween_property(tree_shadow, "modulate:a", 0.1, 1.0)

func respawn_tree() -> void:
	"""Respawn the tree after timer completes"""
	if not is_harvested:
		return

	is_harvested = false
	respawn_timer = 0.0
	print("🌲 Tree respawned at position %s" % global_position)

	# Restore tree visual
	if tree_sprite:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(tree_sprite, "modulate:a", original_modulate.a, 0.5)
		tween.tween_property(tree_sprite, "scale", original_scale, 0.5)

	# Restore shadow
	if tree_shadow:
		var tween2 = create_tween()
		tween2.tween_property(tree_shadow, "modulate:a", 0.6, 0.5)

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		print("👤 Player entered range of harvestable tree: ", name)

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		print("👤 Player left range of harvestable tree: ", name)
