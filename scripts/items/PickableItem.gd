extends Area2D
class_name PickableItem

## Pickable Item - Can be collected by player and added to inventory
## Place in world as a prop with an interaction area
## Press F to pick up when near
## Disappears when picked up, new items spawn elsewhere

# Item data
var item_name: String = "Unknown Item"
var item_description: String = "A mysterious item."
var item_value: int = 10  # Gold value for selling
var item_icon: String = ""  # Optional icon texture path

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var is_picked_up: bool = false

# Visual
var sprite: Sprite2D = null

func _ready() -> void:
	# Set up Area2D
	collision_layer = 0
	collision_mask = 1  # Detect player on layer 1

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create interaction prompt
	create_interaction_prompt()

	print("💎 PickableItem '%s' initialized at position %s" % [item_name, global_position])

func _physics_process(_delta: float) -> void:
	# Update interaction prompt visibility
	if interaction_prompt:
		if player_in_range and not is_picked_up:
			interaction_prompt.visible = true
			update_prompt_position()
		else:
			interaction_prompt.visible = false

	# Check for F key press when player is in range (use is_physical_key_pressed to get just-pressed)
	if player_in_range and not is_picked_up:
		if Input.is_physical_key_pressed(KEY_F):
			pick_up_item()

func create_interaction_prompt() -> void:
	"""Create floating [F] prompt above item"""
	# Create a CanvasLayer for the label (so it's always on top)
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Pick up %s" % item_name
	interaction_prompt.add_theme_font_size_override("font_size", 12)
	interaction_prompt.add_theme_color_override("font_color", Color.WHITE)
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_prompt_position() -> void:
	"""Update prompt position to fixed screen location above player"""
	if not interaction_prompt:
		return

	var viewport_size = get_viewport().get_visible_rect().size

	# Fixed position: centered horizontally, 100 pixels from top (above player health bar)
	var screen_x = viewport_size.x / 2 - interaction_prompt.size.x / 2
	var screen_y = 100.0

	interaction_prompt.position = Vector2(screen_x, screen_y)

func pick_up_item() -> void:
	"""Add item to player inventory and remove from world"""
	if is_picked_up:
		return

	# Create item dictionary for inventory
	var item_data = {
		"name": item_name,
		"description": item_description,
		"value": item_value,
		"icon": item_icon
	}

	# Try to add to inventory
	if InventorySystem.add_item(item_data):
		is_picked_up = true
		print("✨ Player picked up: %s (Value: %d gold)" % [item_name, item_value])

		# Notify spawn manager
		if has_node("/root/LootSpawnManager"):
			get_node("/root/LootSpawnManager").on_item_looted()

		# Hide interaction prompt
		if interaction_prompt:
			interaction_prompt.visible = false

		# Play pickup animation/effect (fade out and scale up)
		if sprite:
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
			tween.tween_property(sprite, "scale", sprite.scale * 1.5, 0.3)
			await tween.finished

		# Remove from world
		queue_free()
	else:
		print("❌ Inventory full! Cannot pick up %s" % item_name)

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		print("👤 Player entered range of %s" % item_name)

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		print("👤 Player left range of %s" % item_name)

# ===== SETUP HELPERS =====

func setup_item(name_str: String, description: String, value: int, texture: Texture2D = null) -> void:
	"""Configure item properties (call before adding to tree)"""
	item_name = name_str
	item_description = description
	item_value = value

	# If texture provided, create sprite
	if texture:
		sprite = Sprite2D.new()
		sprite.name = "ItemSprite"
		sprite.texture = texture
		sprite.centered = true
		add_child(sprite)

	# Create collision shape for interaction
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 40.0  # Pick up range
	collision.shape = shape
	add_child(collision)
