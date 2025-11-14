extends Area2D
class_name Vendor

## Vendor NPC that sells items to the player
## Place near campfire for easy access

signal shop_opened()
signal shop_closed()

@export var vendor_name: String = "Blacksmith"
@export var greeting_text: String = "Need some quality steel?"
@export var vendor_zone: int = 1  # Only sell items for this zone (0 = all zones)

var weapons_for_sale: Array = []
var weapon_prices: Array = []  # Parallel array for weapon prices
var armor_for_sale: Array = []
var player_in_range: bool = false
var shop_ui: CanvasLayer = null
var animated_sprite: AnimatedSprite2D = null
var interaction_prompt: Label = null

func _ready() -> void:
	print("🏪 Vendor '%s' starting initialization..." % vendor_name)

	# Create animated blacksmith sprite
	setup_blacksmith_sprite()

	# Add physical collision so player can't walk through
	add_collision_body()

	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	print("   Signals connected")

	# Load shop inventory
	load_shop_data()

	# Create interaction prompt
	create_interaction_prompt()

	print("🏪 Vendor '%s' initialized with %d weapons and %d armor pieces" % [vendor_name, weapons_for_sale.size(), armor_for_sale.size()])
	print("   Position: ", global_position)
	print("   Monitoring: ", monitoring)

func add_collision_body() -> void:
	"""Add StaticBody2D collision so player can't walk through vendor"""
	var collision_body = StaticBody2D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 2  # Layer 2 for obstacles
	collision_body.collision_mask = 0
	add_child(collision_body)

	# Add circular collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 20.0  # Tight collision around vendor
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)

	print("   Added collision body to vendor")

func create_interaction_prompt() -> void:
	"""Create floating [F] Talk prompt above blacksmith"""
	print("   Creating interaction prompt...")

	# Use CanvasLayer like other interaction prompts
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Talk"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

	print("   Interaction prompt created")

func update_prompt_position() -> void:
	"""Update prompt position to 30 pixels below player's feet"""
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

func setup_blacksmith_sprite() -> void:
	# Create animated sprite for blacksmith
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "BlacksmithSprite"
	animated_sprite.centered = true
	animated_sprite.z_index = 1
	animated_sprite.scale.x = -1  # Flip to face left (toward campfire)
	add_child(animated_sprite)

	# Load blacksmith walk animation (4 frames, 64x64 each)
	var sprite_path = "res://assets/characters/lpc/blacksmith/blacksmith_walk.png"

	if not ResourceLoader.exists(sprite_path):
		DebugConfig.log_warning("Blacksmith sprite not found: %s" % sprite_path)
		return

	var texture = ResourceLoader.load(sprite_path, "Texture2D")
	if not texture:
		DebugConfig.log_error("Failed to load blacksmith sprite")
		return

	# Create sprite frames with single frame (stationary blacksmith)
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("idle")
	sprite_frames.set_animation_loop("idle", false)
	sprite_frames.set_animation_speed("idle", 1.0)

	# Extract frame 3 (facing right) - 256x64 = 4 frames of 64x64 (down, left, up, right)
	var source_img = texture.get_image()
	var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	frame_img.blit_rect(source_img, Rect2i(192, 0, 64, 64), Vector2i(0, 0))  # Frame 3 (right-facing)

	var frame_texture = ImageTexture.create_from_image(frame_img)
	sprite_frames.add_frame("idle", frame_texture)

	# Apply to sprite
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.play("idle")

	DebugConfig.debug_log("🔨 Blacksmith sprite loaded and animating")

func _physics_process(_delta: float) -> void:
	# Update interaction prompt visibility and position
	if interaction_prompt:
		var should_show = player_in_range and (not shop_ui or not shop_ui.visible)
		if should_show != interaction_prompt.visible:
			interaction_prompt.visible = should_show

		# Update position every frame when visible
		if should_show:
			update_prompt_position()

	# Check for F key press when player is in range
	if player_in_range:
		if Input.is_physical_key_pressed(KEY_F):
			# Only open if shop is not already visible
			if not shop_ui or not shop_ui.visible:
				toggle_shop()

func load_shop_data() -> void:
	# Load weapons with validation
	var weapons_result = JSONValidator.load_json_file("res://data/shop_weapons.json")
	if weapons_result.success:
		var data = weapons_result.data
		if data.has("weapons") and data["weapons"] is Array:
			for weapon_data in data["weapons"]:
				if weapon_data is Dictionary:
					# Skip weapons not matching vendor's zone (unless vendor_zone is 0 = all zones)
					var weapon_zone = weapon_data.get("zone", 1)
					if vendor_zone > 0 and weapon_zone != vendor_zone:
						continue

					# Skip drop-only items
					if weapon_data.get("drop_only", false):
						continue

					# Validate required weapon fields (removed "type" - now using unified damage)
					if JSONValidator.validate_required_fields(weapon_data, ["name", "weapon_type", "base_damage"], "weapon"):
						var weapon = create_weapon_from_data(weapon_data)
						if weapon:
							weapons_for_sale.append(weapon)
							# Store price alongside weapon
							var price = weapon_data.get("price", 0)
							weapon_prices.append(price)
							print("   Loaded weapon: %s (zone %d, price: %d)" % [weapon.weapon_name, weapon_zone, price])
				else:
					DebugConfig.log_warning("Invalid weapon entry in shop_weapons.json (not a Dictionary)")
		else:
			DebugConfig.log_error("shop_weapons.json missing 'weapons' array")
	else:
		DebugConfig.log_error("Failed to load shop_weapons.json: %s" % weapons_result.error)

	# Load armor with validation
	var armor_result = JSONValidator.load_json_file("res://data/shop_armor.json")
	if armor_result.success:
		var data = armor_result.data
		if data.has("armor") and data["armor"] is Array:
			for armor_data in data["armor"]:
				if armor_data is Dictionary:
					# Validate required armor fields
					if JSONValidator.validate_required_fields(armor_data, ["name", "slot"], "armor"):
						armor_for_sale.append(armor_data)
				else:
					DebugConfig.log_warning("Invalid armor entry in shop_armor.json (not a Dictionary)")
		else:
			DebugConfig.log_error("shop_armor.json missing 'armor' array")
	else:
		DebugConfig.log_error("Failed to load shop_armor.json: %s" % armor_result.error)

func create_weapon_from_data(data: Dictionary) -> Weapon:
	"""Create a Weapon resource from JSON data"""
	var weapon = Weapon.new()

	weapon.weapon_name = data.get("name", "Unknown")
	weapon.weapon_type = data.get("weapon_type", "sword")  # Visual type (club, sword, dagger, etc)
	weapon.damage_type = "unified"  # Unified damage system (no slash/pierce/blunt)
	weapon.description = data.get("description", "")
	weapon.base_damage = data.get("base_damage", 5.0)

	# Convert attack_speed category to numeric multiplier
	# fast = -0.30 (30% faster), medium = 0.0, slow = +0.30 (30% slower)
	var attack_speed_category = data.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30  # 30% faster (1.5x attack rate)
		"slow":
			weapon.attack_speed_bonus = 0.30   # 30% slower (0.7x attack rate)
		_:  # "medium" or any other value
			weapon.attack_speed_bonus = 0.0

	# Crit chance is already in the right format
	weapon.crit_chance_bonus = data.get("crit_chance", 0.0)
	weapon.required_level = data.get("required_level", 1)
	weapon.can_trade = true

	# Set rarity (support both "Common" and "COMMON" formats)
	var rarity_str = data.get("rarity", "COMMON").to_upper()
	match rarity_str:
		"COMMON":
			weapon.rarity = Weapon.Rarity.COMMON
		"UNCOMMON":
			weapon.rarity = Weapon.Rarity.UNCOMMON
		"RARE":
			weapon.rarity = Weapon.Rarity.RARE
		"EPIC":
			weapon.rarity = Weapon.Rarity.EPIC
		"LEGENDARY":
			weapon.rarity = Weapon.Rarity.LEGENDARY

	return weapon

func toggle_shop() -> void:
	"""Open or close the shop UI"""
	if not shop_ui:
		# Create shop UI if it doesn't exist
		create_shop_ui()
		shop_ui.open_shop(self)
	else:
		# Toggle visibility
		if shop_ui.visible:
			shop_ui.close_shop()
		else:
			shop_ui.open_shop(self)

func create_shop_ui() -> void:
	"""Create the shop UI dynamically"""
	print("🏪 Creating shop UI...")

	# Load the shop UI scene
	var shop_scene = load("res://scenes/ui/shop_ui.tscn")
	if not shop_scene:
		push_error("Failed to load shop UI scene!")
		return

	shop_ui = shop_scene.instantiate()

	# Add to the scene tree (as a child of the root)
	get_tree().root.add_child(shop_ui)

	# Connect signals
	shop_ui.shop_closed.connect(_on_shop_closed)
	shop_ui.item_purchased.connect(_on_item_purchased)

	print("✅ Shop UI created and added to scene tree")

func _on_shop_closed() -> void:
	"""Handle shop closed signal"""
	shop_closed.emit()

func _on_item_purchased(item_name: String, price: int) -> void:
	"""Handle item purchased signal"""
	print("✅ Purchased: %s for %d gold" % [item_name, price])

func get_weapon_price_data(index: int) -> int:
	# Get weapon price from stored array (loaded at startup)
	if index >= 0 and index < weapon_prices.size():
		return weapon_prices[index]
	return 0

func weapon_to_dict(weapon: Weapon, price: int) -> Dictionary:
	"""Convert a Weapon resource to a dictionary for inventory storage"""
	# Convert attack_speed_bonus back to category for display
	var attack_speed_category = "medium"
	if weapon.attack_speed_bonus < -0.15:
		attack_speed_category = "fast"
	elif weapon.attack_speed_bonus > 0.15:
		attack_speed_category = "slow"

	return {
		"name": weapon.weapon_name,
		"description": weapon.description,
		"type": "weapon",
		"weapon_type": weapon.weapon_type,  # Visual type (club, sword, etc)
		"base_damage": weapon.base_damage,
		"attack_speed": attack_speed_category,  # Converted from numeric to category
		"crit_chance": weapon.crit_chance_bonus,  # Renamed for consistency
		"required_level": weapon.required_level,
		"rarity": Weapon.Rarity.keys()[weapon.rarity],
		"value": max(1, int(price * 0.5)),  # Sell for 50% of purchase price
		"slot": "mainhand",  # Weapons go in mainhand slot
		"can_trade": weapon.can_trade,
		"stackable": false,
		"quantity": 1
	}

func purchase_weapon(index: int) -> bool:
	"""Attempt to purchase a weapon by index"""
	if index < 0 or index >= weapons_for_sale.size():
		return false

	var weapon: Weapon = weapons_for_sale[index]
	var price = get_weapon_price_data(index)

	# Check gold (skip check if item is free)
	if price > 0 and not CharacterStats.can_afford(price):
		print("❌ Not enough gold! Need %d gold" % price)
		return false

	# Purchase successful
	if price == 0 or CharacterStats.spend_gold(price):
		# Convert weapon to dictionary and add to inventory
		var weapon_dict = weapon_to_dict(weapon, price)
		if InventorySystem.add_item(weapon_dict):
			if price == 0:
				print("✅ Took %s (free item)!" % weapon.weapon_name)
			else:
				print("✅ Purchased %s for %d gold!" % [weapon.weapon_name, price])
			return true
		else:
			# Inventory full - refund the gold
			if price > 0:
				CharacterStats.add_gold(price)
			print("❌ Inventory full! Cannot purchase %s" % weapon.weapon_name)
			return false

	return false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		print("💬 %s: %s (Press F to shop)" % [vendor_name, greeting_text])

func _on_body_exited(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		print("👋 Player left vendor area")

		# Close shop if player leaves
		if shop_ui and shop_ui.visible:
			shop_ui.close_shop()
