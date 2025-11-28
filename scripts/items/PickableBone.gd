extends Area2D
class_name PickableBone

## Pickable Bone - Scattered bones that can be collected for Bone Ember fuel
## Press F when near to pick up
## Adds "Bone Ember" to inventory for campfire fuel

signal bone_picked_up(bone_node: Node2D)

# Visual
var sprite: Sprite2D = null

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var is_picked_up: bool = false

# Bone Ember item data (same as skeleton drops)
const BONE_EMBER_ITEM = {
	"name": "Bone Ember",
	"description": "Wasteland bones infused with supernatural heat. Burns with ghostly fire.",
	"value": 5,
	"rarity": "Common",
	"type": "material",
	"stackable": true,
	"max_stack": 200,
	"quantity": 1,
	"fuel_type": "bone_ember"
}

func _ready() -> void:
	# Set up Area2D
	collision_layer = 0
	collision_mask = 1  # Detect player on layer 1

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create collision shape for interaction
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 35.0  # Pick up range
	collision.shape = shape
	add_child(collision)

	# Create interaction prompt
	create_interaction_prompt()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle F-key input for picking up bone"""
	if not player_in_range or is_picked_up:
		return

	# Only respond if we're the active interactable
	if not InteractionManager.is_active_interactable(self):
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		pick_up_bone()
		get_viewport().set_input_as_handled()

func create_interaction_prompt() -> void:
	"""Create floating [F] prompt above bone"""
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Bone Ember"
	interaction_prompt.add_theme_font_size_override("font_size", 14)
	interaction_prompt.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))  # Bone color
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_prompt_position() -> void:
	"""Update prompt position below player's feet"""
	if not interaction_prompt:
		return

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Position below player's feet
	var player_world_pos = player.global_position + Vector2(0, 30)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var player_screen_pos = (player_world_pos - camera_pos) * camera.zoom.x + screen_center

	var screen_x = player_screen_pos.x
	if interaction_prompt.size.x > 0:
		screen_x -= interaction_prompt.size.x / 2

	interaction_prompt.position = Vector2(screen_x, player_screen_pos.y)

func _physics_process(_delta: float) -> void:
	"""Update interaction prompt visibility and position"""
	# Check if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)

	if interaction_prompt:
		if player_in_range and not is_picked_up and is_active:
			interaction_prompt.visible = true
			update_prompt_position()
		else:
			interaction_prompt.visible = false

func pick_up_bone() -> void:
	"""Add Bone Ember to inventory and remove from world"""
	if is_picked_up:
		return

	# Create item data
	var item_data = BONE_EMBER_ITEM.duplicate()

	# Try to add to inventory (local player only)
	if not InventorySystem.add_item(item_data):
		# Inventory full - could show message but bones are common so just ignore
		return

	is_picked_up = true

	# Show inventory notification
	NotificationManager.notify_item_added("Bone Ember", 1, "COMMON")

	# Check if we need network sync
	var network_id = get_meta("network_id", "")
	if network_id != "" and multiplayer.has_multiplayer_peer():
		# Go through network sync - request server to remove bone for all players
		if multiplayer.is_server():
			# Server - broadcast removal to all clients
			_sync_bone_picked_up.rpc(network_id)
		else:
			# Client - request server to broadcast
			_request_pickup_bone.rpc_id(1, network_id)
		return

	# Single player - just remove locally
	_remove_bone_locally()

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		# Register with InteractionManager
		var distance = global_position.distance_to(body.global_position)
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.PICKABLE_ITEM, distance)

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		# Unregister from InteractionManager
		InteractionManager.unregister_interactable(self)

# ===== SETUP HELPER =====

func setup_bone(texture: Texture2D, bone_scale: Vector2, bone_rotation: float, bone_modulate: Color) -> void:
	"""Configure bone visuals"""
	sprite = Sprite2D.new()
	sprite.name = "BoneSprite"
	sprite.texture = texture
	sprite.centered = true
	sprite.rotation = bone_rotation
	sprite.scale = bone_scale
	sprite.modulate = bone_modulate
	add_child(sprite)

# ═══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER: Network Sync for Bone Pickup
# ═══════════════════════════════════════════════════════════════════════════════

func _remove_bone_locally() -> void:
	"""Remove bone from world with animation"""
	# Emit signal so chunk system can clean up tracking
	bone_picked_up.emit(self)

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Play pickup animation (fade out and scale up)
	if sprite:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(sprite, "modulate:a", 0.0, 0.25)
		tween.tween_property(sprite, "scale", sprite.scale * 1.3, 0.25)
		await tween.finished

	# Remove from world
	queue_free()

@rpc("any_peer", "reliable")
func _request_pickup_bone(network_id: String) -> void:
	"""Client requests bone pickup - server validates and broadcasts"""
	if not multiplayer.is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	print("🦴 Server: Bone %s picked up (requested by peer %d)" % [network_id, peer_id])

	# Broadcast to all clients (including the one who requested)
	_sync_bone_picked_up.rpc(network_id)

@rpc("authority", "call_local", "reliable")
func _sync_bone_picked_up(network_id: String) -> void:
	"""All clients receive bone pickup notification"""
	print("🦴 [Sync] Bone %s picked up" % network_id)

	# Find the bone by network_id and remove it
	var prop_system = get_node_or_null("/root/ChunkBasedPropSystem")
	if prop_system:
		# Mark as harvested so it doesn't respawn
		prop_system.mark_as_harvested(network_id)

	# Remove this bone locally
	_remove_bone_locally()
