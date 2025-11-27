extends Area2D
class_name TreasureChest

## Treasure Chest - Contains random loot
## Press E to open and see loot UI
## Spawns 1-3 random valuable items when opened
## Player can click items to loot or press F to take all
## Disappears when looted, new chest spawns elsewhere

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var is_opened: bool = false
var loot_ui: CanvasLayer = null
var generated_loot: Array = []

# Visual
var chest_visual: Node2D = null
var lid_sprite: Polygon2D = null
var body_sprite: Polygon2D = null
var loot_indicator: Node2D = null  # Sparkle effect for unopened chests

# Loot table - items that can be found in chests
const LOOT_TABLE = [
	{"name": "Ancient Skull", "desc": "A weathered skull from an ancient warrior", "value": 15, "drop_weight": 30},
	{"name": "Old Bones", "desc": "Bones from a long-forgotten battle", "value": 8, "drop_weight": 35},
	{"name": "Broken Sword", "desc": "Fragments of a shattered blade", "value": 25, "drop_weight": 25},
	{"name": "Tarnished Ring", "desc": "An old ring with faded engravings", "value": 40, "drop_weight": 20},
	{"name": "Dusty Gem", "desc": "A gemstone covered in wasteland dust", "value": 60, "drop_weight": 15},
	{"name": "Ancient Coin", "desc": "Currency from a forgotten kingdom", "value": 20, "drop_weight": 25},
	# Copper Plate Armor Pieces (rare drops from chests)
	{
		"id": "copper_plate_greaves",
		"name": "Copper Plate Greaves",
		"description": "Tier 1 copper-plated leg armor. Solid leg protection.",
		"slot": "legs",
		"defense": 8,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 8,  # 8% chance - rare armor drop
		"stackable": false
	},
	{
		"id": "copper_plate_helmet",
		"name": "Copper Plate Helmet",
		"description": "Tier 1 copper-plated helmet. Essential head protection.",
		"slot": "head",
		"defense": 7,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 7,  # 7% chance - rare armor drop
		"stackable": false
	}
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

	# Add sparkle effect for unopened chest
	add_loot_indicator()

	print("📦 TreasureChest initialized at position %s" % global_position)

func _physics_process(_delta: float) -> void:
	# Check if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)

	# Update interaction prompt visibility (only show if active)
	if interaction_prompt:
		if player_in_range and not is_opened and is_active:
			interaction_prompt.visible = true
			update_prompt_position()
		else:
			interaction_prompt.visible = false

	# Check for F key press when player is in range AND we're active
	if player_in_range and not is_opened and is_active:
		if Input.is_key_pressed(KEY_F):
			open_chest()

func create_chest_visual() -> void:
	"""Create a simple treasure chest visual using polygons"""
	chest_visual = Node2D.new()
	chest_visual.name = "ChestVisual"
	# Scale down 30% overall (0.7), then stretch lengthwise (X axis)
	chest_visual.scale = Vector2(0.7 * 1.3, 0.7)  # 30% smaller, 30% longer on X
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

	# Chest lid (top part) - 25% bigger
	lid_sprite = Polygon2D.new()
	lid_sprite.name = "ChestLid"
	var lid_points = PackedVector2Array([
		Vector2(-31.25, -15),   # Bottom left (25% wider: -25 * 1.25)
		Vector2(31.25, -15),    # Bottom right (25% wider: 25 * 1.25)
		Vector2(27.5, -37.5),   # Top right (25% taller: 22 * 1.25, -30 * 1.25)
		Vector2(-27.5, -37.5)   # Top left (25% taller: -22 * 1.25, -30 * 1.25)
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

	# Add a wider shadow that covers the whole bottom
	var shadow = Polygon2D.new()
	shadow.name = "Shadow"
	var shadow_points = PackedVector2Array([
		Vector2(-30, 20),
		Vector2(30, 20),
		Vector2(35, 28),
		Vector2(-35, 28)
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
	interaction_prompt.text = "[F] Open Chest"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
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

func open_chest() -> void:
	"""Open chest and show loot UI"""
	if is_opened:
		return

	# Check if we need to go through network sync
	var network_id = get_meta("network_id", -1)
	if network_id != -1 and multiplayer.has_multiplayer_peer():
		# Go through LootSpawnManager for network sync
		var loot_manager = get_node_or_null("/root/LootSpawnManager")
		if loot_manager:
			loot_manager.request_open_chest(self)
			return

	# Single player - open directly
	_do_open_chest()

func _do_open_chest() -> void:
	"""Actually open the chest (called directly in single player, or after network sync)"""
	if is_opened:
		return

	is_opened = true
	print("📦 Opening treasure chest at position %s" % global_position)

	# Play chest open sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.CHEST_OPEN, global_position, -8.0)

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Remove sparkle indicator
	if loot_indicator:
		loot_indicator.queue_free()
		loot_indicator = null

	# Animate lid opening
	animate_lid_opening()

	# Generate random loot (1-3 items) - only in single player
	# In multiplayer, loot is generated by server and synced
	if not multiplayer.has_multiplayer_peer():
		generate_loot()

	# Create and show loot UI
	create_loot_ui()

func _on_chest_opened_synced() -> void:
	"""Called when chest is opened via network sync (loot already set)"""
	print("📦 [Sync] Chest opened at position %s" % global_position)

	# Play chest open sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.CHEST_OPEN, global_position, -8.0)

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Remove sparkle indicator
	if loot_indicator:
		loot_indicator.queue_free()
		loot_indicator = null

	# Animate lid opening
	animate_lid_opening()

	# Only show loot UI if this is the local player who opened it
	# (Check if player is in range - they initiated the open)
	if player_in_range:
		create_loot_ui()

func generate_loot() -> void:
	"""Generate random loot items for the chest using weighted drop rates"""
	var num_items = randi_range(1, 3)
	generated_loot.clear()

	# Calculate total weight
	var total_weight = 0
	for item in LOOT_TABLE:
		total_weight += item.get("drop_weight", 1)

	for i in range(num_items):
		# Pick weighted random item from loot table
		var roll = randi() % total_weight
		var cumulative = 0

		for item_data in LOOT_TABLE:
			cumulative += item_data.get("drop_weight", 1)
			if roll < cumulative:
				var loot_item = item_data.duplicate()
				generated_loot.append(loot_item)

				# Log different messages for armor vs vendor trash
				if loot_item.get("type") == "armor":
					print("  ⚔️ Chest contains ARMOR: %s (%s, +%d defense)" % [
						loot_item.get("name", "Unknown"),
						loot_item.get("slot", "unknown"),
						loot_item.get("defense", 0)
					])
				else:
					print("  ✨ Chest contains: %s (Value: %d gold)" % [
						loot_item.get("name", "Unknown"),
						loot_item.get("value", 0)
					])
				break

	print("📦 Chest generated %d items" % generated_loot.size())

func create_loot_ui() -> void:
	"""Create and open the loot UI"""
	# Load the loot UI scene
	var loot_scene = load("res://scenes/ui/chest_loot_ui.tscn")
	if not loot_scene:
		push_error("Failed to load chest loot UI scene!")
		return

	loot_ui = loot_scene.instantiate()

	# Add to scene tree
	get_tree().root.add_child(loot_ui)

	# Connect signals
	loot_ui.loot_ui_closed.connect(_on_loot_ui_closed)

	# Open with loot
	loot_ui.open_chest_ui(self, generated_loot)

	print("✅ Chest loot UI opened")

func _on_loot_ui_closed() -> void:
	"""Handle loot UI closing"""
	print("📦 Loot UI closed, removing chest")

	# Notify spawn manager
	if has_node("/root/LootSpawnManager"):
		get_node("/root/LootSpawnManager").on_chest_looted()

	# Fade out and remove chest
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
		# Register with InteractionManager
		var distance = global_position.distance_to(body.global_position)
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.TREASURE_CHEST, distance)

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		# Unregister from InteractionManager
		InteractionManager.unregister_interactable(self)

func add_loot_indicator() -> void:
	"""Add shiny glimmer effect to indicate this chest has loot (WoW-style)"""
	if loot_indicator:
		return  # Already has indicator

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10  # Draw on top

	# Create 4 small sparkle points tightly clustered near the chest
	var sparkle_positions = [
		Vector2(-4, -20),  # Upper left
		Vector2(4, -20),   # Upper right
		Vector2(-3, -16),  # Lower left
		Vector2(3, -16)    # Lower right
	]

	for i in range(sparkle_positions.size()):
		var sparkle = create_sparkle()
		sparkle.position = sparkle_positions[i]
		loot_indicator.add_child(sparkle)

		# Stagger animation start times for shimmer effect
		var delay = i * 0.2
		animate_sparkle(sparkle, delay)

	add_child(loot_indicator)

func create_sparkle() -> Polygon2D:
	"""Create a single sparkle (4-pointed star)"""
	var sparkle = Polygon2D.new()

	# Create 4-pointed star shape
	var size = 6.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Top point
		Vector2(1, -1),         # Inner top-right
		Vector2(size, 0),       # Right point
		Vector2(1, 1),          # Inner bottom-right
		Vector2(0, size),       # Bottom point
		Vector2(-1, 1),         # Inner bottom-left
		Vector2(-size, 0),      # Left point
		Vector2(-1, -1)         # Inner top-left
	])

	sparkle.polygon = points
	sparkle.color = Color(1.0, 1.0, 0.8, 0.9)  # Bright yellow-white

	return sparkle

func animate_sparkle(sparkle: Polygon2D, delay: float) -> void:
	"""Animate sparkle floating upward and fading out"""
	# Wait for delay
	await get_tree().create_timer(delay).timeout

	if not is_instance_valid(sparkle):
		return

	# Store initial position
	var start_pos = sparkle.position

	# Create looping animation
	var tween = create_tween()
	tween.set_loops()

	# Float up slightly and fade out, then reset (tight animation)
	tween.tween_property(sparkle, "position:y", start_pos.y - 8, 0.9).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.25, 0.9)

	# Reset instantly and wait before next cycle
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.9, 0.0)
	tween.parallel().tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.3)  # Pause before next shimmer
