extends CanvasLayer
class_name ShopUI

## Shop UI for vendor interactions
## Displays weapons, armor, and handles purchases
## Modern stone grey theme matching CharacterUI

signal shop_closed()
signal item_purchased(item_name: String, price: int)
signal item_sold(item_name: String, value: int)

# Stone Gray UI Palette (matching CharacterUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.85)  # Dark stone gray (slightly more opaque for shop)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)  # Light steel accent
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)  # Silver headers
const ITEM_BG_COLOR = Color(0.08, 0.08, 0.10, 0.9)  # Dark stone for items
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)  # Dark stone inset

@onready var main_panel: PanelContainer = $Control/Panel
@onready var vendor_name_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/VendorName
@onready var gold_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/GoldLabel
@onready var weapons_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Weapons/ScrollContainer/WeaponsList
@onready var tools_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Tools/ScrollContainer/ToolsList
@onready var armor_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Armor/ScrollContainer/ArmorList
@onready var sell_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Sell/ScrollContainer/SellList
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var message_label: Label = $Control/Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var tab_container: TabContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer

var vendor: Vendor = null

func _ready() -> void:
	print("🏪 ShopUI initialized")
	hide()

	# Apply modern styling to main panel
	apply_modern_styling()

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

func apply_modern_styling() -> void:
	"""Apply Dark Fantasy Wasteland theme to match CharacterUI"""
	if main_panel:
		# Dark Fantasy Wasteland styling with transparency
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = BG_COLOR  # 85% transparent dark leather
		panel_style.border_width_left = 3
		panel_style.border_width_right = 3
		panel_style.border_width_top = 3
		panel_style.border_width_bottom = 3
		panel_style.border_color = BORDER_COLOR  # Rusted bronze

		# Subtle rounded corners
		panel_style.corner_radius_top_left = 8
		panel_style.corner_radius_top_right = 8
		panel_style.corner_radius_bottom_left = 8
		panel_style.corner_radius_bottom_right = 8

		# Heavy shadow for depth
		panel_style.shadow_size = 12
		panel_style.shadow_color = Color(0, 0, 0, 0.8)  # Darker shadow for wasteland
		panel_style.shadow_offset = Vector2(0, 6)

		main_panel.add_theme_stylebox_override("panel", panel_style)

	# Update text colors to aged parchment
	if vendor_name_label:
		vendor_name_label.add_theme_color_override("font_color", HEADER_COLOR)  # Faded gold
	if gold_label:
		gold_label.add_theme_color_override("font_color", ACCENT_COLOR)  # Tarnished gold

	# Style the close button (blood red for wasteland)
	if close_button:
		close_button.add_theme_font_size_override("font_size", 24)
		close_button.add_theme_color_override("font_color", Color(0.85, 0.20, 0.15))  # Blood red

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
	populate_tools()
	populate_armor()
	populate_sell_items()

	# Hide armor tab if vendor doesn't sell armor
	if tab_container and vendor.armor_for_sale.is_empty():
		var armor_tab = tab_container.get_node_or_null("Armor")
		if armor_tab:
			armor_tab.visible = false
			# Switch to Weapons tab if currently on Armor
			if tab_container.current_tab == 1:  # Armor tab index
				tab_container.current_tab = 0  # Switch to Weapons

	show()

	print("🏪 Shop UI opened for: %s" % vendor.vendor_name)

func close_shop() -> void:
	"""Close the shop"""
	hide()
	shop_closed.emit()
	print("🏪 Shop UI closed")

func update_gold_display() -> void:
	"""Update the gold display with coin icon"""
	if gold_label:
		gold_label.text = "🪙 %d" % CharacterStats.gold

func _on_gold_changed(_amount: int, total: int) -> void:
	"""Auto-update gold display and refresh shop when gold changes"""
	update_gold_display()
	# Refresh shop items to update buy button states
	if vendor and visible:
		populate_weapons()
		populate_tools()
		populate_armor()

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

func populate_tools() -> void:
	"""Populate the tools list"""
	if not tools_list:
		return

	# Clear existing items
	for child in tools_list.get_children():
		child.queue_free()

	# Add tool items
	for i in range(vendor.tools_for_sale.size()):
		var tool_data = vendor.tools_for_sale[i]
		var price = tool_data.get("price", 0)
		var tool_name = tool_data.get("name", "Unknown")
		var tool_type = tool_data.get("tool_type", "tool").capitalize()

		var item_row = create_item_row(
			tool_name,
			tool_data.get("description", ""),
			price,
			"Type: %s | Efficiency: %.0f%% | Durability: %d" % [
				tool_type,
				tool_data.get("efficiency", 1.0) * 100,
				tool_data.get("durability", 100)
			],
			1,  # Tools have no level requirement
			get_armor_rarity_color(tool_data.get("rarity", "COMMON")),
			func(): purchase_tool(i)
		)

		tools_list.add_child(item_row)

func populate_armor() -> void:
	"""Populate the armor list"""
	if not armor_list:
		return

	# Clear existing items
	for child in armor_list.get_children():
		child.queue_free()

	# Add armor items
	for i in range(vendor.armor_for_sale.size()):
		var armor_data = vendor.armor_for_sale[i]
		var item_row = create_item_row(
			armor_data.get("name", "Unknown"),
			armor_data.get("description", ""),
			armor_data.get("price", 0),
			"Defense: +%d | Slot: %s" % [armor_data.get("defense", 0), armor_data.get("slot", "").capitalize()],
			armor_data.get("required_level", 1),
			get_armor_rarity_color(armor_data.get("rarity", "COMMON")),
			func(): purchase_armor(i)
		)

		armor_list.add_child(item_row)

func create_item_row(item_name: String, description: String, price: int, stats: String, req_level: int, color: Color, on_buy: Callable) -> Button:
	"""Create a button slot for shop item - hover for tooltip"""
	var slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(140, 60)  # Compact size
	slot_button.clip_text = true

	# Display name and price on separate lines, centered
	var price_text = "🪙 %d" % price if price > 0 else "FREE"
	slot_button.text = "%s\n%s" % [item_name, price_text]
	slot_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Set tooltip with full stat card info
	slot_button.tooltip_text = "%s\n%s\n%s" % [item_name, description, stats]

	# Text styling - larger, readable font
	slot_button.add_theme_font_size_override("font_size", 14)
	slot_button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	slot_button.add_theme_color_override("font_hover_color", Color.WHITE)
	slot_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))

	# Style the button with rarity border
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = ITEM_BG_COLOR
	btn_normal.border_width_left = 2
	btn_normal.border_width_right = 2
	btn_normal.border_width_top = 2
	btn_normal.border_width_bottom = 2
	btn_normal.border_color = color  # Rarity color border
	btn_normal.corner_radius_top_left = 4
	btn_normal.corner_radius_top_right = 4
	btn_normal.corner_radius_bottom_left = 4
	btn_normal.corner_radius_bottom_right = 4
	btn_normal.content_margin_left = 8
	btn_normal.content_margin_right = 8
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6

	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.18, 0.18, 0.22, 1.0)  # Lighter on hover
	btn_hover.border_width_left = 2
	btn_hover.border_width_right = 2
	btn_hover.border_width_top = 2
	btn_hover.border_width_bottom = 2
	btn_hover.border_color = Color(color.r + 0.2, color.g + 0.2, color.b + 0.2, 1.0)  # Brighter border
	btn_hover.corner_radius_top_left = 4
	btn_hover.corner_radius_top_right = 4
	btn_hover.corner_radius_bottom_left = 4
	btn_hover.corner_radius_bottom_right = 4
	btn_hover.content_margin_left = 8
	btn_hover.content_margin_right = 8
	btn_hover.content_margin_top = 6
	btn_hover.content_margin_bottom = 6

	var btn_pressed = StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.06, 0.06, 0.08, 1.0)  # Darker when pressed
	btn_pressed.border_width_left = 2
	btn_pressed.border_width_right = 2
	btn_pressed.border_width_top = 2
	btn_pressed.border_width_bottom = 2
	btn_pressed.border_color = color
	btn_pressed.content_margin_left = 8
	btn_pressed.content_margin_right = 8
	btn_pressed.content_margin_top = 6
	btn_pressed.content_margin_bottom = 6
	btn_pressed.corner_radius_top_left = 4
	btn_pressed.corner_radius_top_right = 4
	btn_pressed.corner_radius_bottom_left = 4
	btn_pressed.corner_radius_bottom_right = 4

	var btn_disabled = StyleBoxFlat.new()
	btn_disabled.bg_color = Color(0.05, 0.05, 0.06, 0.8)  # Dimmed when disabled
	btn_disabled.border_width_left = 2
	btn_disabled.border_width_right = 2
	btn_disabled.border_width_top = 2
	btn_disabled.border_width_bottom = 2
	btn_disabled.border_color = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.6)
	btn_disabled.corner_radius_top_left = 4
	btn_disabled.corner_radius_top_right = 4
	btn_disabled.corner_radius_bottom_left = 4
	btn_disabled.corner_radius_bottom_right = 4
	btn_disabled.content_margin_left = 8
	btn_disabled.content_margin_right = 8
	btn_disabled.content_margin_top = 6
	btn_disabled.content_margin_bottom = 6

	slot_button.add_theme_stylebox_override("normal", btn_normal)
	slot_button.add_theme_stylebox_override("hover", btn_hover)
	slot_button.add_theme_stylebox_override("pressed", btn_pressed)
	slot_button.add_theme_stylebox_override("disabled", btn_disabled)

	# Only check gold - no level requirement for purchasing
	var can_buy = CharacterStats.can_afford(price)
	slot_button.disabled = not can_buy

	slot_button.pressed.connect(on_buy)

	return slot_button

func purchase_weapon(index: int) -> void:
	"""Attempt to purchase a weapon"""
	if not vendor:
		return

	var success = vendor.purchase_weapon(index)

	if success:
		var weapon: Weapon = vendor.weapons_for_sale[index]
		var price = vendor.get_weapon_price_data(index)

		# Get rarity as string
		var rarity_str = Weapon.Rarity.keys()[weapon.rarity]

		# Show item added notification
		NotificationManager.notify_item_added(weapon.weapon_name, 1, rarity_str)

		item_purchased.emit(weapon.weapon_name, price)

		# Play gold loot sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -5.0)

		# Refresh the UI
		update_gold_display()
		populate_weapons()
		populate_armor()
	else:
		show_message("Cannot purchase this item!", Color.RED)

func purchase_armor(index: int) -> void:
	"""Attempt to purchase armor"""
	if not vendor:
		return

	if index < 0 or index >= vendor.armor_for_sale.size():
		return

	var armor_data = vendor.armor_for_sale[index]
	var price = armor_data.get("price", 0)
	var armor_name = armor_data.get("name", "Unknown")
	var armor_rarity = armor_data.get("rarity", "COMMON")

	# Check gold
	if not CharacterStats.can_afford(price):
		show_message("Not enough gold!", Color.RED)
		return

	# Purchase successful
	if CharacterStats.spend_gold(price):
		# Add armor to inventory
		InventorySystem.add_item(armor_data)

		# Show item added notification
		NotificationManager.notify_item_added(armor_name, 1, armor_rarity)

		item_purchased.emit(armor_name, price)

		# Play gold loot sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -5.0)

		# Refresh the UI
		update_gold_display()
		populate_armor()
		populate_sell_items()
	else:
		show_message("Cannot purchase this item!", Color.RED)

func purchase_tool(index: int) -> void:
	"""Attempt to purchase a tool"""
	if not vendor:
		return

	if index < 0 or index >= vendor.tools_for_sale.size():
		return

	var tool_data = vendor.tools_for_sale[index]
	var price = tool_data.get("price", 0)
	var tool_name = tool_data.get("name", "Unknown")
	var tool_rarity = tool_data.get("rarity", "COMMON")

	# Check gold (skip check if item is free)
	if price > 0 and not CharacterStats.can_afford(price):
		show_message("Not enough gold!", Color.RED)
		return

	# Purchase successful
	if price == 0 or CharacterStats.spend_gold(price):
		# Add tool to inventory
		InventorySystem.add_item(tool_data)

		# Show item added notification
		NotificationManager.notify_item_added(tool_name, 1, tool_rarity)

		item_purchased.emit(tool_name, price)

		# Play gold loot sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -5.0)

		# Refresh the UI
		update_gold_display()
		populate_tools()
		populate_sell_items()

		# Inventory notification handles feedback - no need for extra message
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
	"""Get muted glow color for weapon rarity (visible but not overwhelming)"""
	match rarity:
		Weapon.Rarity.COMMON:
			return Color(0.6, 0.6, 0.6, 0.9)  # Subtle grey
		Weapon.Rarity.UNCOMMON:
			return Color(0.4, 0.8, 0.4, 1.0)  # Muted green
		Weapon.Rarity.RARE:
			return Color(0.4, 0.5, 0.9, 1.0)  # Muted blue
		Weapon.Rarity.EPIC:
			return Color(0.7, 0.4, 0.9, 1.0)  # Muted purple
		Weapon.Rarity.LEGENDARY:
			return Color(0.9, 0.6, 0.2, 1.0)  # Muted orange
		_:
			return BORDER_INNER  # Default to dark border

func get_armor_rarity_color(rarity_str: String) -> Color:
	"""Get muted glow color for armor rarity (visible but not overwhelming)"""
	match rarity_str.to_upper():
		"COMMON":
			return Color(0.6, 0.6, 0.6, 0.9)  # Subtle grey
		"UNCOMMON":
			return Color(0.4, 0.8, 0.4, 1.0)  # Muted green
		"RARE":
			return Color(0.4, 0.5, 0.9, 1.0)  # Muted blue
		"EPIC":
			return Color(0.7, 0.4, 0.9, 1.0)  # Muted purple
		"LEGENDARY":
			return Color(0.9, 0.6, 0.2, 1.0)  # Muted orange
		_:
			return BORDER_INNER  # Default to dark border

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

func create_sell_item_row(item_name: String, description: String, unit_value: int, quantity: int, total_value: int, on_sell: Callable) -> Button:
	"""Create a square button slot for sell item - click to sell"""
	var slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(168, 80)  # Match buy item size
	slot_button.clip_text = true

	# Display name with quantity and sell value
	var name_text = item_name
	if quantity > 1:
		name_text = "%s x%d" % [item_name, quantity]
	var value_text = "🪙 %d" % total_value
	slot_button.text = "%s\n%s" % [name_text, value_text]

	# Set tooltip with description
	slot_button.tooltip_text = "%s\n%s\nSell for 🪙 %d" % [item_name, description, total_value]

	# Style the button with gold border (sell items)
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = ITEM_BG_COLOR
	btn_normal.border_width_left = 3
	btn_normal.border_width_right = 3
	btn_normal.border_width_top = 3
	btn_normal.border_width_bottom = 3
	btn_normal.border_color = ACCENT_COLOR  # Gold border for sell items
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6

	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.18, 0.18, 0.22, 1.0)  # Lighter on hover
	btn_hover.border_width_left = 3
	btn_hover.border_width_right = 3
	btn_hover.border_width_top = 3
	btn_hover.border_width_bottom = 3
	btn_hover.border_color = Color(0.85, 0.75, 0.55, 1.0)  # Brighter gold
	btn_hover.corner_radius_top_left = 6
	btn_hover.corner_radius_top_right = 6
	btn_hover.corner_radius_bottom_left = 6
	btn_hover.corner_radius_bottom_right = 6

	var btn_pressed = StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.06, 0.06, 0.08, 1.0)  # Darker when pressed
	btn_pressed.border_width_left = 3
	btn_pressed.border_width_right = 3
	btn_pressed.border_width_top = 3
	btn_pressed.border_width_bottom = 3
	btn_pressed.border_color = ACCENT_COLOR
	btn_pressed.corner_radius_top_left = 6
	btn_pressed.corner_radius_top_right = 6
	btn_pressed.corner_radius_bottom_left = 6
	btn_pressed.corner_radius_bottom_right = 6

	slot_button.add_theme_stylebox_override("normal", btn_normal)
	slot_button.add_theme_stylebox_override("hover", btn_hover)
	slot_button.add_theme_stylebox_override("pressed", btn_pressed)

	# Text styling
	slot_button.add_theme_font_size_override("font_size", 12)
	slot_button.add_theme_color_override("font_color", TEXT_COLOR)
	slot_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	slot_button.pressed.connect(on_sell)

	return slot_button

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
	var item_rarity = item.get("rarity", "COMMON")

	# Remove from inventory and add gold for entire stack
	InventorySystem.remove_item(slot)
	CharacterStats.add_gold(total_value)

	# Show item removed notification
	NotificationManager.notify_item_removed(item_name, quantity, item_rarity)

	item_sold.emit(item_name, total_value)

	# Play gold loot sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -5.0)

	# Refresh the UI
	update_gold_display()
	populate_sell_items()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_shop()
