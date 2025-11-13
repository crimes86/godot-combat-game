extends CanvasLayer
class_name ShopUI

## Shop UI for vendor interactions
## Displays weapons, armor, and handles purchases

signal shop_closed()
signal item_purchased(item_name: String, price: int)
signal item_sold(item_name: String, value: int)

@onready var vendor_name_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/VendorName
@onready var gold_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/GoldLabel
@onready var weapons_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Weapons/ScrollContainer/WeaponsList
@onready var armor_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Armor/ScrollContainer/ArmorList
@onready var sell_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Sell/ScrollContainer/SellList
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var message_label: Label = $Control/Panel/MarginContainer/VBoxContainer/MessageLabel

var vendor: Vendor = null

func _ready() -> void:
	print("🏪 ShopUI initialized")
	hide()

	# Verify node references
	if not vendor_name_label:
		push_warning("ShopUI: vendor_name_label not found")
	if not gold_label:
		push_warning("ShopUI: gold_label not found")
	if not weapons_list:
		push_warning("ShopUI: weapons_list not found")
	if not armor_list:
		push_warning("ShopUI: armor_list not found")
	if not sell_list:
		push_warning("ShopUI: sell_list not found")
	if not message_label:
		push_warning("ShopUI: message_label not found")

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	else:
		push_warning("ShopUI: close_button not found")

	# Connect to gold changes for auto-update
	CharacterStats.gold_changed.connect(_on_gold_changed)

func _input(event: InputEvent) -> void:
	# Allow F or ESC to close the shop
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.keycode == KEY_ESCAPE:
			close_shop()
			get_viewport().set_input_as_handled()

func open_shop(vendor_node: Vendor) -> void:
	"""Open the shop and populate it with items"""
	vendor = vendor_node

	print("🏪 Opening shop for: %s" % vendor.vendor_name)
	print("   vendor_name_label exists: ", vendor_name_label != null)
	print("   gold_label exists: ", gold_label != null)
	print("   weapons_list exists: ", weapons_list != null)
	print("   armor_list exists: ", armor_list != null)

	if vendor_name_label:
		vendor_name_label.text = vendor.vendor_name + "'s Shop"

	update_gold_display()
	populate_weapons()
	populate_armor()
	populate_sell_items()

	show()

	print("🏪 Shop UI opened for: %s" % vendor.vendor_name)

func close_shop() -> void:
	"""Close the shop"""
	hide()
	shop_closed.emit()
	print("🏪 Shop UI closed")

func update_gold_display() -> void:
	"""Update the gold display"""
	if gold_label:
		gold_label.text = "Gold: %d" % CharacterStats.gold

func _on_gold_changed(_amount: int, total: int) -> void:
	"""Auto-update gold display when gold changes"""
	update_gold_display()

func populate_weapons() -> void:
	"""Populate the weapons list"""
	if not weapons_list:
		push_error("ShopUI: weapons_list is null!")
		return

	print("🔨 Populating weapons list...")
	print("   Weapons to add: %d" % vendor.weapons_for_sale.size())

	# Clear existing items
	for child in weapons_list.get_children():
		child.queue_free()

	# Add weapon items
	for i in range(vendor.weapons_for_sale.size()):
		var weapon: Weapon = vendor.weapons_for_sale[i]
		var price = vendor.get_weapon_price_data(i)

		print("   Adding weapon: %s (price: %d)" % [weapon.weapon_name, price])

		var item_row = create_item_row(
			weapon.weapon_name,
			weapon.description,
			price,
			"Dmg: %.1f | Crit: +%.1f%% | Spd: %+.1f%%" % [
				weapon.base_damage,
				weapon.crit_chance_bonus * 100,
				weapon.attack_speed_bonus * 100
			],
			weapon.required_level,
			get_rarity_color(weapon.rarity),
			func(): purchase_weapon(i)
		)

		weapons_list.add_child(item_row)
		print("   ✅ Weapon row added to list")

	print("✅ Weapons populated: %d items" % weapons_list.get_child_count())

func populate_armor() -> void:
	"""Populate the armor list"""
	if not armor_list:
		return

	# Clear existing items
	for child in armor_list.get_children():
		child.queue_free()

	# Add armor items
	for armor_data in vendor.armor_for_sale:
		var item_row = create_item_row(
			armor_data.get("name", "Unknown"),
			armor_data.get("description", ""),
			armor_data.get("price", 0),
			"Defense: +%.1f" % armor_data.get("defense", 0),
			armor_data.get("required_level", 1),
			get_armor_rarity_color(armor_data.get("rarity", "COMMON")),
			func(): show_message("Armor equipping not yet implemented!", Color.ORANGE)
		)

		armor_list.add_child(item_row)

func create_item_row(item_name: String, description: String, price: int, stats: String, req_level: int, color: Color, on_buy: Callable) -> PanelContainer:
	"""Create a row for an item in the shop"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 80)

	# Add subtle background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.5)
	style.border_width_left = 4
	style.border_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Left side - Item info
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	# Item name
	var name_label = Label.new()
	name_label.text = item_name
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_label)

	# Stats
	var stats_label = Label.new()
	stats_label.text = stats
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	vbox.add_child(stats_label)

	# Right side - Price and buy button
	var right_vbox = VBoxContainer.new()
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_vbox)

	# Price
	var price_label = Label.new()
	price_label.text = "%d gold" % price
	price_label.add_theme_font_size_override("font_size", 16)
	price_label.add_theme_color_override("font_color", Color.GOLD if price > 0 else Color.GREEN)
	right_vbox.add_child(price_label)

	# Level requirement
	if req_level > 1:
		var level_label = Label.new()
		level_label.text = "Lv %d" % req_level
		level_label.add_theme_font_size_override("font_size", 12)
		level_label.add_theme_color_override("font_color", Color.ORANGE if CharacterStats.level < req_level else Color.GREEN)
		right_vbox.add_child(level_label)

	# Buy button
	var buy_button = Button.new()
	buy_button.text = "BUY" if price > 0 else "TAKE"
	buy_button.custom_minimum_size = Vector2(80, 40)

	# Check if can afford/level requirement
	var can_buy = CharacterStats.can_afford(price) and CharacterStats.level >= req_level
	buy_button.disabled = not can_buy

	buy_button.pressed.connect(on_buy)
	right_vbox.add_child(buy_button)

	return panel

func purchase_weapon(index: int) -> void:
	"""Attempt to purchase a weapon"""
	if not vendor:
		return

	var success = vendor.purchase_weapon(index)

	if success:
		var weapon: Weapon = vendor.weapons_for_sale[index]
		var price = vendor.get_weapon_price_data(index)
		show_message("Purchased %s for %d gold!" % [weapon.weapon_name, price], Color.GREEN)
		item_purchased.emit(weapon.weapon_name, price)

		# Refresh the UI
		update_gold_display()
		populate_weapons()
		populate_armor()
	else:
		show_message("Cannot purchase this item!", Color.RED)

func show_message(text: String, color: Color) -> void:
	"""Show a temporary message to the player"""
	if not message_label:
		return

	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.show()

	# Hide after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if message_label:
		message_label.hide()

func get_rarity_color(rarity: Weapon.Rarity) -> Color:
	"""Get color for weapon rarity"""
	match rarity:
		Weapon.Rarity.COMMON:
			return Color.WHITE
		Weapon.Rarity.UNCOMMON:
			return Color.GREEN_YELLOW
		Weapon.Rarity.RARE:
			return Color.DODGER_BLUE
		Weapon.Rarity.EPIC:
			return Color.MEDIUM_PURPLE
		Weapon.Rarity.LEGENDARY:
			return Color.ORANGE
		_:
			return Color.WHITE

func get_armor_rarity_color(rarity_str: String) -> Color:
	"""Get color for armor rarity string"""
	match rarity_str:
		"COMMON":
			return Color.WHITE
		"UNCOMMON":
			return Color.GREEN_YELLOW
		"RARE":
			return Color.DODGER_BLUE
		"EPIC":
			return Color.MEDIUM_PURPLE
		"LEGENDARY":
			return Color.ORANGE
		_:
			return Color.WHITE

func populate_sell_items() -> void:
	"""Populate the sell list with inventory items"""
	if not sell_list:
		return

	# Clear existing items
	for child in sell_list.get_children():
		child.queue_free()

	# Add inventory items (only non-null slots)
	var has_items = false
	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item:  # Skip null/empty slots
			has_items = true
			var item_name = item.get("name", "Unknown")
			var item_desc = item.get("description", "")
			var item_value = item.get("value", 0)
			var quantity = item.get("quantity", 1)
			var total_value = item_value * quantity

			var item_row = create_sell_item_row(
				item_name,
				item_desc,
				item_value,
				quantity,
				total_value,
				func(): sell_item(i)
			)

			sell_list.add_child(item_row)

	# Show message if inventory is empty
	if not has_items:
		var empty_label = Label.new()
		empty_label.text = "Your inventory is empty"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sell_list.add_child(empty_label)

func create_sell_item_row(item_name: String, description: String, unit_value: int, quantity: int, total_value: int, on_sell: Callable) -> PanelContainer:
	"""Create a row for an item to sell"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 70)

	# Add subtle background
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.5)
	style.border_width_left = 4
	style.border_color = Color.GOLD
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Left side - Item info
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	# Item name with quantity
	var name_label = Label.new()
	if quantity > 1:
		name_label.text = "%s x%d" % [item_name, quantity]
	else:
		name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_label)

	# Right side - Value and sell button
	var right_vbox = VBoxContainer.new()
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_vbox)

	# Value (show per-item and total if stacked)
	var value_label = Label.new()
	if quantity > 1:
		value_label.text = "%d gold total\n(%d ea)" % [total_value, unit_value]
	else:
		value_label.text = "%d gold" % total_value
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color.GOLD)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(value_label)

	# Sell button
	var sell_button = Button.new()
	sell_button.text = "SELL"
	sell_button.custom_minimum_size = Vector2(80, 40)
	sell_button.pressed.connect(on_sell)
	right_vbox.add_child(sell_button)

	return panel

func sell_item(slot: int) -> void:
	"""Sell an item from inventory (entire stack if stackable)"""
	if slot < 0 or slot >= InventorySystem.inventory_items.size():
		return

	var item = InventorySystem.inventory_items[slot]
	if not item:  # Slot is empty
		return

	var item_name = item.get("name", "Unknown")
	var item_value = item.get("value", 0)
	var quantity = item.get("quantity", 1)
	var total_value = item_value * quantity

	# Remove from inventory and add gold for entire stack
	InventorySystem.remove_item(slot)
	CharacterStats.add_gold(total_value)

	if quantity > 1:
		show_message("Sold %s x%d for %d gold!" % [item_name, quantity, total_value], Color.GREEN)
	else:
		show_message("Sold %s for %d gold!" % [item_name, total_value], Color.GREEN)
	item_sold.emit(item_name, total_value)

	# Refresh the UI
	update_gold_display()
	populate_sell_items()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_shop()
