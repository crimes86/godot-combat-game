extends Area2D
class_name Vendor

## Vendor NPC that sells items to the player
## Place near campfire for easy access

signal shop_opened()
signal shop_closed()

@export var vendor_name: String = "Merchant"
@export var greeting_text: String = "Welcome, traveler! Browse my wares."

var weapons_for_sale: Array = []
var armor_for_sale: Array = []
var player_in_range: bool = false
var shop_ui: CanvasLayer = null

func _ready() -> void:
	print("🏪 Vendor '%s' starting initialization..." % vendor_name)

	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	print("   Signals connected")

	# Load shop inventory
	load_shop_data()

	print("🏪 Vendor '%s' initialized with %d weapons and %d armor pieces" % [vendor_name, weapons_for_sale.size(), armor_for_sale.size()])
	print("   Position: ", global_position)
	print("   Monitoring: ", monitoring)

func _input(event: InputEvent) -> void:
	# Use E key to interact with vendor
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and player_in_range:
			# Only open if shop is not already visible
			if not shop_ui or not shop_ui.visible:
				toggle_shop()
				get_viewport().set_input_as_handled()

func load_shop_data() -> void:
	"""Load weapons and armor from JSON data files"""
	# Load weapons
	var weapons_file = FileAccess.open("res://data/shop_weapons.json", FileAccess.READ)
	if weapons_file:
		var json = JSON.new()
		var parse_result = json.parse(weapons_file.get_as_text())
		weapons_file.close()

		if parse_result == OK:
			var data = json.data
			if data.has("weapons"):
				for weapon_data in data["weapons"]:
					var weapon = create_weapon_from_data(weapon_data)
					if weapon:
						weapons_for_sale.append(weapon)
		else:
			push_error("Failed to parse shop_weapons.json")

	# Load armor
	var armor_file = FileAccess.open("res://data/shop_armor.json", FileAccess.READ)
	if armor_file:
		var json = JSON.new()
		var parse_result = json.parse(armor_file.get_as_text())
		armor_file.close()

		if parse_result == OK:
			var data = json.data
			if data.has("armor"):
				for armor_data in data["armor"]:
					armor_for_sale.append(armor_data)
		else:
			push_error("Failed to parse shop_armor.json")

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
	"""Get weapon price from the JSON data (temporary until proper UI)"""
	var weapons_file = FileAccess.open("res://data/shop_weapons.json", FileAccess.READ)
	if weapons_file:
		var json = JSON.new()
		var parse_result = json.parse(weapons_file.get_as_text())
		weapons_file.close()

		if parse_result == OK:
			var data = json.data
			if data.has("weapons") and index < data["weapons"].size():
				return data["weapons"][index].get("price", 0)

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
