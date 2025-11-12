extends Area2D
class_name TreasureChest

## Treasure Chest - Contains random loot
## Press E to open and receive items
## Spawns 1-3 random valuable items when opened

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var is_opened: bool = false

# Visual
var chest_visual: Node2D = null
var lid_sprite: Polygon2D = null
var body_sprite: Polygon2D = null

# Loot table - items that can be found in chests
const LOOT_TABLE = [
	{"name": "Ancient Skull", "desc": "A weathered skull from an ancient warrior", "value": 15},
	{"name": "Old Bones", "desc": "Bones from a long-forgotten battle", "value": 8},
	{"name": "Broken Sword", "desc": "Fragments of a shattered blade", "value": 25},
	{"name": "Tarnished Ring", "desc": "An old ring with faded engravings", "value": 40},
	{"name": "Dusty Gem", "desc": "A gemstone covered in wasteland dust", "value": 60},
	{"name": "Ancient Coin", "desc": "Currency from a forgotten kingdom", "value": 20}
]

func _ready() -> void:
	# Set up Area2D
	collision_layer = 0
	collision_mask = 1  # Detect player on layer 1

	# Create visual representation
	create_chest_visual()

	# Create collision shape
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(60, 50)
	collision.shape = shape
	collision.position = Vector2(0, 0)
	add_child(collision)

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create interaction prompt
	create_interaction_prompt()

	print("📦 TreasureChest initialized at position %s" % global_position)

func _physics_process(_delta: float) -> void:
	# Update interaction prompt visibility
	if interaction_prompt:
		if player_in_range and not is_opened:
			interaction_prompt.visible = true
			update_prompt_position()
		else:
			interaction_prompt.visible = false

	# Check for E key press when player is in range
	if player_in_range and not is_opened:
		if Input.is_key_pressed(KEY_E):
			open_chest()

func create_chest_visual() -> void:
	"""Create a simple treasure chest visual using polygons"""
	chest_visual = Node2D.new()
	chest_visual.name = "ChestVisual"
	add_child(chest_visual)

	# Chest body (bottom part)
	body_sprite = Polygon2D.new()
	body_sprite.name = "ChestBody"
	var body_points = PackedVector2Array([
		Vector2(-25, -15),   # Top left
		Vector2(25, -15),    # Top right
		Vector2(30, 20),     # Bottom right
		Vector2(-30, 20)     # Bottom left
	])
	body_sprite.polygon = body_points
	body_sprite.color = Color(0.4, 0.25, 0.15, 1.0)  # Brown wood color
	chest_visual.add_child(body_sprite)

	# Add body border
	var body_border = Line2D.new()
	body_border.name = "BodyBorder"
	body_border.points = body_points
	body_border.points.append(body_points[0])  # Close the loop
	body_border.width = 2
	body_border.default_color = Color(0.2, 0.1, 0.05, 1.0)  # Dark brown
	body_sprite.add_child(body_border)

	# Chest lid (top part)
	lid_sprite = Polygon2D.new()
	lid_sprite.name = "ChestLid"
	var lid_points = PackedVector2Array([
		Vector2(-25, -15),   # Bottom left
		Vector2(25, -15),    # Bottom right
		Vector2(22, -30),    # Top right
		Vector2(-22, -30)    # Top left
	])
	lid_sprite.polygon = lid_points
	lid_sprite.color = Color(0.5, 0.3, 0.2, 1.0)  # Lighter brown
	chest_visual.add_child(lid_sprite)

	# Add lid border
	var lid_border = Line2D.new()
	lid_border.name = "LidBorder"
	lid_border.points = lid_points
	lid_border.points.append(lid_points[0])  # Close the loop
	lid_border.width = 2
	lid_border.default_color = Color(0.2, 0.1, 0.05, 1.0)
	lid_sprite.add_child(lid_border)

	# Lock/clasp (golden rectangle)
	var clasp = Polygon2D.new()
	clasp.name = "Clasp"
	var clasp_points = PackedVector2Array([
		Vector2(-5, -18),
		Vector2(5, -18),
		Vector2(5, -8),
		Vector2(-5, -8)
	])
	clasp.polygon = clasp_points
	clasp.color = Color(0.8, 0.7, 0.3, 1.0)  # Gold color
	chest_visual.add_child(clasp)

	# Add a subtle shadow
	var shadow = Polygon2D.new()
	shadow.name = "Shadow"
	var shadow_points = PackedVector2Array([
		Vector2(-30, 20),
		Vector2(30, 20),
		Vector2(25, 28),
		Vector2(-25, 28)
	])
	shadow.polygon = shadow_points
	shadow.color = Color(0, 0, 0, 0.4)
	shadow.z_index = -1
	chest_visual.add_child(shadow)

func create_interaction_prompt() -> void:
	"""Create floating [E] prompt above chest"""
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[E] Open Chest"
	interaction_prompt.add_theme_font_size_override("font_size", 14)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_prompt_position() -> void:
	"""Update prompt position to stay above chest on screen"""
	if not interaction_prompt:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Calculate screen position of chest relative to camera
	var world_pos = global_position + Vector2(0, -50)  # Float above chest
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var relative_pos = (world_pos - camera_pos) * camera.zoom.x + screen_center
	interaction_prompt.position = relative_pos - interaction_prompt.size / 2

func open_chest() -> void:
	"""Open chest and give loot to player"""
	if is_opened:
		return

	is_opened = true
	print("📦 Opening treasure chest at position %s" % global_position)

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Animate lid opening
	animate_lid_opening()

	# Generate random loot (1-3 items)
	var num_items = randi_range(1, 3)
	var items_added = 0

	for i in range(num_items):
		# Check if inventory has space
		if not InventorySystem.has_empty_slot():
			print("⚠️ Inventory full! Chest contains more items but cannot pick them up.")
			break

		# Pick random item from loot table
		var item_data = LOOT_TABLE[randi() % LOOT_TABLE.size()].duplicate()

		# Add to inventory
		if InventorySystem.add_item(item_data):
			items_added += 1
			print("  ✨ Found: %s (Value: %d gold)" % [item_data["name"], item_data["value"]])

	print("📦 Chest opened! Received %d items" % items_added)

	# Wait a moment, then fade out and remove chest
	await get_tree().create_timer(2.0).timeout
	fade_out_chest()

func animate_lid_opening() -> void:
	"""Animate the chest lid opening"""
	if not lid_sprite:
		return

	# Rotate lid backwards (opening animation)
	var tween = create_tween()
	tween.set_parallel(false)
	tween.tween_property(lid_sprite, "rotation", -0.7, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func fade_out_chest() -> void:
	"""Fade out and remove chest from world"""
	if not chest_visual:
		queue_free()
		return

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(chest_visual, "modulate:a", 0.0, 1.0)
	tween.tween_property(chest_visual, "scale", Vector2(0.5, 0.5), 1.0)
	await tween.finished

	queue_free()

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
