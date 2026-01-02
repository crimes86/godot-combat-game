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
var item_stackable: bool = false  # Can this item stack?
var item_max_stack: int = 1  # Max stack size
var item_quantity: int = 1  # Current quantity

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var is_picked_up: bool = false

# Visual
var sprite: Sprite2D = null

var _is_server_mode: bool = false

func _ready() -> void:
	# Check if running on dedicated server
	_is_server_mode = "--server" in OS.get_cmdline_user_args()

	# Set up Area2D
	collision_layer = 0
	collision_mask = 1  # Detect player on layer 1

	# Skip visual/UI on dedicated server
	if _is_server_mode:
		set_physics_process(false)
		return

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create interaction prompt
	create_interaction_prompt()

	print("💎 PickableItem '%s' initialized at position %s" % [item_name, global_position])

func _physics_process(_delta: float) -> void:
	# Check if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)

	# Update interaction prompt visibility
	if interaction_prompt:
		if player_in_range and not is_picked_up and is_active:
			interaction_prompt.visible = true
			update_prompt_position()
		else:
			interaction_prompt.visible = false

	# Check for interact input when player is in range AND we're active
	if player_in_range and not is_picked_up and is_active:
		if Input.is_physical_key_pressed(KEY_F) or GameInput.is_interact_just_pressed():
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
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color.WHITE)
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_prompt_position() -> void:
	"""Update prompt position to 10 pixels below player's feet"""
	if not interaction_prompt:
		return

	# Find the player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Get player position in screen space, then add 30 pixels below feet
	var player_world_pos = player.global_position + Vector2(0, 30)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var player_screen_pos = (player_world_pos - camera_pos) * camera.zoom.x + screen_center

	# Center the prompt horizontally on player (wait for size to be calculated)
	var screen_x = player_screen_pos.x
	if interaction_prompt.size.x > 0:
		screen_x -= interaction_prompt.size.x / 2
	var screen_y = player_screen_pos.y

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
		"icon": item_icon,
		"stackable": item_stackable,
		"max_stack": item_max_stack,
		"quantity": item_quantity
	}

	# Try to add to inventory (local player only)
	if not InventorySystem.add_item(item_data):
		print("❌ Inventory full! Cannot pick up %s" % item_name)
		return

	is_picked_up = true
	print("✨ Player picked up: %s (Value: %d gold)" % [item_name, item_value])

	# Check if we need to go through network sync
	var network_id = get_meta("network_id", -1)
	if network_id != -1 and multiplayer.has_multiplayer_peer():
		# Go through LootSpawnManager for network sync
		var loot_manager = get_node_or_null("/root/LootSpawnManager")
		if loot_manager:
			loot_manager.request_pickup_item(self)
			# Don't queue_free here - LootSpawnManager will handle removal
			# Just hide locally for now
			if interaction_prompt:
				interaction_prompt.visible = false
			visible = false
			return

	# Single player - notify spawn manager and remove
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

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		# Register with InteractionManager
		var distance = global_position.distance_to(body.global_position)
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.PICKABLE_ITEM, distance)
		print("👤 Player entered range of %s" % item_name)

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		# Unregister from InteractionManager
		InteractionManager.unregister_interactable(self)
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
