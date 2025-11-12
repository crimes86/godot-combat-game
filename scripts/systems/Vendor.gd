extends Area2D
class_name Vendor

## Vendor NPC that sells items to the player
## Place near campfire for easy access

signal shop_opened()
signal shop_closed()

@export var vendor_name: String = "Blacksmith"
@export var greeting_text: String = "Need some quality steel?"

var weapons_for_sale: Array = []
var armor_for_sale: Array = []
var player_in_range: bool = false
var shop_ui: CanvasLayer = null
var animated_sprite: AnimatedSprite2D = null

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

func setup_blacksmith_sprite() -> void:
	# Create animated sprite for blacksmith
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "BlacksmithSprite"
	animated_sprite.centered = true
	animated_sprite.z_index = 1
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

func _input(event: InputEvent) -> void:
	# Use E key to interact with vendor
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and player_in_range:
			# Only open if shop is not already visible
			if not shop_ui or not shop_ui.visible:
				toggle_shop()
				get_viewport().set_input_as_handled()

func load_shop_data() -> void:
	# Load weapons with validation
	var weapons_result = JSONValidator.load_json_file("res://data/shop_weapons.json")
	if weapons_result.success:
		var data = weapons_result.data
		if data.has("weapons") and data["weapons"] is Array:
			for weapon_data in data["weapons"]:
				if weapon_data is Dictionary:
					# Validate required weapon fields
					if JSONValidator.validate_required_fields(weapon_data, ["name", "type", "base_damage"], "weapon"):
						var weapon = create_weapon_from_data(weapon_data)
						if weapon:
							weapons_for_sale.append(weapon)
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
	weapon.weapon_type = data.get("type", "sword")
	weapon.description = data.get("description", "")
	weapon.base_damage = data.get("base_damage", 5.0)
	weapon.attack_speed_bonus = data.get("attack_speed_bonus", 0.0)
	weapon.crit_chance_bonus = data.get("crit_chance_bonus", 0.0)
	weapon.required_level = data.get("required_level", 1)
	weapon.can_trade = true

	# Set rarity
	var rarity_str = data.get("rarity", "COMMON")
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
	# Get weapon price from the JSON data with validation
	var result = JSONValidator.load_json_file("res://data/shop_weapons.json")
	if result.success:
		var data = result.data
		if data.has("weapons") and data["weapons"] is Array:
			if index >= 0 and index < data["weapons"].size():
				var weapon = data["weapons"][index]
				if weapon is Dictionary:
					return JSONValidator.get_safe_value(weapon, "price", 0)

	return 0

func purchase_weapon(index: int) -> bool:
	"""Attempt to purchase a weapon by index"""
	if index < 0 or index >= weapons_for_sale.size():
		return false

	var weapon: Weapon = weapons_for_sale[index]
	var price = get_weapon_price_data(index)

	# Check level requirement
	if CharacterStats.level < weapon.required_level:
		print("❌ Level %d required to purchase %s" % [weapon.required_level, weapon.weapon_name])
		return false

	# Check gold
	if not CharacterStats.can_afford(price):
		print("❌ Not enough gold! Need %d gold" % price)
		return false

	# Purchase successful
	if CharacterStats.spend_gold(price):
		CharacterStats.equip_weapon(weapon)
		print("✅ Purchased %s for %d gold!" % [weapon.weapon_name, price])
		return true

	return false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		print("💬 %s: %s (Press E to shop)" % [vendor_name, greeting_text])

func _on_body_exited(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		print("👋 Player left vendor area")

		# Close shop if player leaves
		if shop_ui and shop_ui.visible:
			shop_ui.close_shop()
