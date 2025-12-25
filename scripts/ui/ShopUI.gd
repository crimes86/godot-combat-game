extends CanvasLayer
class_name ShopUI

## Shop UI for vendor interactions
## Displays weapons, armor, and handles purchases
## Modern stone grey theme matching CharacterUI

signal shop_closed()
signal item_purchased(item_name: String, price: int)
signal item_sold(item_name: String, value: int)

# Stone Gray UI Palette (matching CharacterUI/InventoryUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.85)  # Dark stone gray (slightly more opaque for shop)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)  # Light steel accent
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)  # Silver headers
const ITEM_BG_COLOR = Color(0.08, 0.08, 0.10, 0.9)  # Dark stone for items
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)  # Dark stone inset

# Slot sizes (matching InventoryUI - square slots)
const SLOT_SIZE = 54  # Match inventory slot width (square)
const ICON_SIZE = 46  # SLOT_SIZE - 8, matches inventory

@onready var main_panel: PanelContainer = $Control/Panel
@onready var vendor_name_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/VendorName
@onready var gold_label: Label = $Control/GoldContainer/GoldLabel
@onready var weapons_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Weapons/ScrollContainer/WeaponsList
@onready var tools_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Tools/ScrollContainer/ToolsList
@onready var armor_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Armor/ScrollContainer/ArmorList
@onready var sell_list: GridContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Sell/ScrollContainer/SellList
@onready var quests_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Quests/ScrollContainer/QuestsList
@onready var forge_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Forge/VBoxContainer/ScrollContainer/ForgeList
@onready var forge_status_label: Label = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Forge/VBoxContainer/ForgeHeader/ForgeStatus
@onready var forge_refresh_btn: Button = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Forge/VBoxContainer/ForgeHeader/RefreshButton
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var message_label: Label = $Control/Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var tab_container: TabContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer

var vendor: Vendor = null
var quest_message_label: Label = null  # Message label inside Quests tab

# Forge tab colors
const FORGE_RARITY_COLORS = {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.4, 0.8, 0.4),
	"rare": Color(0.3, 0.5, 0.9),
	"epic": Color(0.6, 0.2, 0.8),
	"legendary": Color(1.0, 0.5, 0.1)
}

func _ready() -> void:
	print("🏪 ShopUI initialized")
	hide()

	# Set layer to 100 (below inventory at 105, above game prompts)
	layer = 100

	# Add to group for tutorial system to find
	add_to_group("shop_ui")

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

	# Connect tab changes for tutorial system
	if tab_container:
		tab_container.tab_changed.connect(_on_tab_changed)

	# Create quest message label inside Quests tab (at bottom of tab content)
	_create_quest_message_label()

	# Connect to gold changes for auto-update
	CharacterStats.gold_changed.connect(_on_gold_changed)

	# Connect ForgeItemManager signals
	if ForgeItemManager:
		ForgeItemManager.forged_items_loaded.connect(_on_forged_items_loaded)
		ForgeItemManager.forge_claimed.connect(_on_forge_item_claimed)
		ForgeItemManager.item_synced_to_inventory.connect(_on_forge_item_synced)

	# Connect forge refresh button
	if forge_refresh_btn:
		forge_refresh_btn.pressed.connect(_on_forge_refresh_pressed)

	# Connect to QuestManager for item reward choices
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		if qm.has_signal("quest_reward_choice_needed"):
			qm.quest_reward_choice_needed.connect(_on_quest_reward_choice_needed)

func apply_modern_styling() -> void:
	"""Apply Dark Fantasy dreadland theme to match CharacterUI"""
	if main_panel:
		# Dark Fantasy dreadland styling with transparency
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
		panel_style.shadow_color = Color(0, 0, 0, 0.8)  # Darker shadow for dreadland
		panel_style.shadow_offset = Vector2(0, 6)

		main_panel.add_theme_stylebox_override("panel", panel_style)

	# Update text colors to aged parchment
	if vendor_name_label:
		vendor_name_label.add_theme_color_override("font_color", HEADER_COLOR)  # Faded gold
	if gold_label:
		gold_label.add_theme_color_override("font_color", ACCENT_COLOR)  # Tarnished gold

	# Style the close button (blood red for dreadland)
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
	populate_quests()
	populate_forge()
	update_quests_tab_indicator()
	update_forge_tab_indicator()

	# Hide armor tab if vendor doesn't sell armor
	if tab_container and vendor.armor_for_sale.is_empty():
		var armor_tab = tab_container.get_node_or_null("Armor")
		if armor_tab:
			armor_tab.visible = false
			# Switch to Weapons tab if currently on Armor
			if tab_container.current_tab == 1:  # Armor tab index
				tab_container.current_tab = 0  # Switch to Weapons

	# Play blacksmith open sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.BLACKSMITH_OPEN, -10.0)

	show()

	# Notify tutorial system that shop opened (for ACCEPT_QUEST step persistence)
	if TutorialManager and TutorialManager.is_tutorial_active():
		TutorialManager.on_shop_opened()

	print("🏪 Shop UI opened for: %s" % vendor.vendor_name)

func close_shop() -> void:
	"""Close the shop"""
	hide()
	shop_closed.emit()

	# Notify tutorial system that shop closed
	if TutorialManager and TutorialManager.is_tutorial_active():
		TutorialManager.on_shop_closed()

	print("🏪 Shop UI closed")

func update_gold_display() -> void:
	"""Update the gold display (icon is in scene, just update number)"""
	if gold_label:
		gold_label.text = "%d" % CharacterStats.gold

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

		# Check if player already owns this weapon
		var already_owned = _player_owns_weapon(weapon.weapon_name)

		# Build stats string based on weapon type
		var stats: String
		if weapon.is_healing_weapon():
			stats = "Heal: %.1f | Radius: %.0f" % [weapon.get_total_healing(), weapon.heal_radius]
		else:
			# Speed display: negative bonus = faster, positive = slower
			var speed_text = "Normal"
			if weapon.attack_speed_bonus < -0.15:
				speed_text = "Fast"
			elif weapon.attack_speed_bonus > 0.15:
				speed_text = "Slow"
			stats = "Dmg: %.1f | Speed: %s" % [weapon.base_damage, speed_text]

		# Create item data dict for icon generation
		var item_data = {
			"type": "weapon",
			"weapon_type": weapon.weapon_type,
			"name": weapon.weapon_name
		}

		var item_slot = create_shop_slot_with_owned_check(
			weapon.weapon_name,
			weapon.description,
			price,
			stats,
			weapon.required_level,
			get_rarity_color(weapon.rarity),
			item_data,
			func(): purchase_weapon(i),
			already_owned
		)

		weapons_list.add_child(item_slot)
		print("   ✅ Weapon slot added to list")

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
		var tool_type_raw = tool_data.get("tool_type", "tool")
		var tool_type = tool_type_raw.capitalize()

		# Check if player already owns this tool
		var already_owned = _player_owns_tool(tool_name, tool_type_raw)

		# Create item data dict for icon generation
		var item_data = tool_data.duplicate()
		# Only set type to "tool" if not already specified (preserve consumable/placeable types)
		if not item_data.has("type") or item_data["type"] == "":
			item_data["type"] = "tool"

		var item_slot = create_shop_slot_with_owned_check(
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
			item_data,
			func(): purchase_tool(i),
			already_owned
		)

		tools_list.add_child(item_slot)

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
		var armor_name = armor_data.get("name", "Unknown")

		# Check if player already owns this armor (in inventory or equipped)
		var already_owned = _player_owns_armor(armor_name, armor_data.get("slot", ""))

		# Create item data dict for icon generation
		var item_data = armor_data.duplicate()
		item_data["type"] = "armor"

		var item_slot = create_shop_slot_with_owned_check(
			armor_name,
			armor_data.get("description", ""),
			armor_data.get("price", 0),
			"Defense: +%d | Slot: %s" % [armor_data.get("defense", 0), armor_data.get("slot", "").capitalize()],
			armor_data.get("required_level", 1),
			get_armor_rarity_color(armor_data.get("rarity", "COMMON")),
			item_data,
			func(): purchase_armor(i),
			already_owned
		)

		armor_list.add_child(item_slot)

func _player_owns_armor(armor_name: String, armor_slot: String) -> bool:
	"""Check if player already owns this armor piece (in inventory or equipped)"""
	# Check inventory
	if InventorySystem.has_item_by_name(armor_name):
		return true

	# Check equipped armor slot
	if armor_slot and CharacterStats.equipped_armor.has(armor_slot):
		var equipped = CharacterStats.equipped_armor[armor_slot]
		if equipped and equipped.get("name", "") == armor_name:
			return true

	return false

func _player_owns_weapon(weapon_name: String) -> bool:
	"""Check if player already owns this weapon (in inventory or equipped)"""
	# Check inventory
	if InventorySystem.has_item_by_name(weapon_name):
		return true

	# Check equipped weapon
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.weapon_name == weapon_name:
		return true

	return false

func _player_owns_tool(tool_name: String, tool_type: String) -> bool:
	"""Check if player already owns this tool (in inventory or equipped)"""
	# Check inventory
	if InventorySystem.has_item_by_name(tool_name):
		return true

	# Check equipped tool slots
	if tool_type == "axe" and InventorySystem.has_axe_equipped():
		var equipped = InventorySystem.get_equipped_axe()
		if equipped.get("name", "") == tool_name:
			return true
	elif tool_type == "pickaxe" and InventorySystem.has_pickaxe_equipped():
		var equipped = InventorySystem.get_equipped_pickaxe()
		if equipped.get("name", "") == tool_name:
			return true

	return false

func create_item_row(item_name: String, description: String, price: int, stats: String, req_level: int, color: Color, on_buy: Callable) -> Button:
	"""Create a button slot for shop item - hover for tooltip"""
	var slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(140, 60)  # Compact size
	slot_button.clip_text = true

	# Display name and price on separate lines, centered
	var price_text = "%d G" % price if price > 0 else "FREE"
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

func create_item_slot_with_icon(item_name: String, description: String, price: int, stats: String, req_level: int, color: Color, item_data: Dictionary, on_buy: Callable) -> PanelContainer:
	"""Create a shop slot with icon and price - matches InventoryUI style (square slots)"""
	var slot_dimensions = Vector2(SLOT_SIZE, SLOT_SIZE)

	# Main container
	var panel = PanelContainer.new()
	panel.custom_minimum_size = slot_dimensions

	# Style the panel with rarity border (matching inventory style)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = SLOT_BG
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = color  # Rarity color border
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", panel_style)

	# Icon container (centered, fills slot)
	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = slot_dimensions
	panel.add_child(icon_container)

	# Try to get icon from ItemIconGenerator
	var icon_texture: Texture2D = null
	if ItemIconGenerator:
		icon_texture = ItemIconGenerator.get_item_icon(item_data)

	if icon_texture:
		var icon = TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		icon_container.add_child(icon)
	else:
		# Fallback: show item type as text
		var fallback_label = Label.new()
		fallback_label.text = item_data.get("weapon_type", item_data.get("type", "?")).substr(0, 3).to_upper()
		fallback_label.add_theme_font_size_override("font_size", 14)
		fallback_label.add_theme_color_override("font_color", color)
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_container.add_child(fallback_label)

	# Price label (overlaid at bottom)
	var price_label = Label.new()
	var price_text = "%dG" % price if price > 0 else "FREE"
	price_label.text = price_text
	price_label.add_theme_font_size_override("font_size", 9)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6) if price > 0 else Color(0.5, 0.9, 0.5))
	price_label.add_theme_color_override("font_outline_color", Color.BLACK)
	price_label.add_theme_constant_override("outline_size", 2)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	price_label.offset_top = -14
	price_label.offset_bottom = -2
	panel.add_child(price_label)

	# Clickable overlay button (invisible but handles clicks)
	var click_button = Button.new()
	click_button.flat = true
	click_button.custom_minimum_size = slot_dimensions
	click_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Build rich tooltip
	click_button.tooltip_text = "[%s]\n%s\n\n%s" % [item_name, description, stats]

	# Check if player can afford
	var can_buy = CharacterStats.can_afford(price)
	click_button.disabled = not can_buy

	if not can_buy:
		# Dim the panel when can't afford
		panel.modulate = Color(0.5, 0.5, 0.5, 0.8)

	click_button.pressed.connect(on_buy)

	# Add button on top of panel
	panel.add_child(click_button)

	# Hover effects
	click_button.mouse_entered.connect(func():
		if can_buy:
			panel_style.bg_color = Color(0.18, 0.18, 0.22, 1.0)
			panel_style.border_color = Color(color.r + 0.2, color.g + 0.2, color.b + 0.2, 1.0)
	)
	click_button.mouse_exited.connect(func():
		panel_style.bg_color = SLOT_BG
		panel_style.border_color = color
	)

	return panel

func create_shop_slot_with_owned_check(item_name: String, description: String, price: int, stats: String, req_level: int, color: Color, item_data: Dictionary, on_buy: Callable, already_owned: bool) -> PanelContainer:
	"""Create a shop slot - shows 'Owned' if player already has this item - matches InventoryUI style (square slots)"""
	var slot_dimensions = Vector2(SLOT_SIZE, SLOT_SIZE)

	# Main container - use Control for manual positioning
	var panel = PanelContainer.new()
	panel.custom_minimum_size = slot_dimensions

	# Style the panel with rarity border (matching inventory style)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = SLOT_BG
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = color  # Rarity color border
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", panel_style)

	# Manual layout container (Control for absolute positioning)
	var layout = Control.new()
	layout.custom_minimum_size = slot_dimensions
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(layout)

	# Icon container (centered in slot)
	var icon_container = CenterContainer.new()
	icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_container.offset_bottom = -12  # Leave room for price label at bottom
	layout.add_child(icon_container)

	# Try to get icon from ItemIconGenerator
	var icon_texture: Texture2D = null
	if ItemIconGenerator:
		icon_texture = ItemIconGenerator.get_item_icon(item_data)

	if icon_texture:
		var icon = TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.custom_minimum_size = Vector2(ICON_SIZE - 4, ICON_SIZE - 4)  # Slightly smaller for padding
		icon_container.add_child(icon)
	else:
		# Fallback: show item type as text
		var fallback_label = Label.new()
		var fallback_text = item_data.get("weapon_type", item_data.get("slot", item_data.get("tool_type", "?")))
		fallback_label.text = fallback_text.substr(0, 3).to_upper() if fallback_text else "???"
		fallback_label.add_theme_font_size_override("font_size", 14)
		fallback_label.add_theme_color_override("font_color", color)
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_container.add_child(fallback_label)

	# Price label container (anchored at bottom with background pill)
	var price_container = PanelContainer.new()
	price_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	price_container.anchor_left = 0.5
	price_container.anchor_right = 0.5
	price_container.offset_left = -24
	price_container.offset_right = 24
	price_container.offset_top = -14
	price_container.offset_bottom = -2

	# Style the price background pill
	var price_bg_style = StyleBoxFlat.new()
	price_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)  # Semi-transparent black
	price_bg_style.corner_radius_top_left = 3
	price_bg_style.corner_radius_top_right = 3
	price_bg_style.corner_radius_bottom_left = 3
	price_bg_style.corner_radius_bottom_right = 3
	price_bg_style.content_margin_left = 4
	price_bg_style.content_margin_right = 4
	price_bg_style.content_margin_top = 1
	price_bg_style.content_margin_bottom = 1
	price_container.add_theme_stylebox_override("panel", price_bg_style)
	layout.add_child(price_container)

	var price_label = Label.new()
	if already_owned:
		price_label.text = "OWNED"
		price_label.add_theme_font_size_override("font_size", 8)
		price_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.5))  # Bright green for owned
	else:
		var price_text = "%dG" % price if price > 0 else "FREE"
		price_label.text = price_text
		price_label.add_theme_font_size_override("font_size", 9)
		price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if price > 0 else Color(0.5, 0.95, 0.5))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_container.add_child(price_label)

	# Clickable overlay button (invisible but handles clicks)
	var click_button = Button.new()
	click_button.flat = true
	click_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Build rich tooltip
	var tooltip = "[%s]\n%s\n\n%s" % [item_name, description, stats]
	if already_owned:
		tooltip += "\n\n(Already owned)"
	click_button.tooltip_text = tooltip

	# Check if player can buy (must afford AND not already owned)
	var can_buy = CharacterStats.can_afford(price) and not already_owned
	click_button.disabled = not can_buy

	if not can_buy:
		# Dim the panel when can't buy
		if already_owned:
			panel.modulate = Color(0.65, 0.65, 0.65, 0.95)  # Slightly less dim for owned
		else:
			panel.modulate = Color(0.5, 0.5, 0.5, 0.8)  # Can't afford

	click_button.pressed.connect(on_buy)

	# Add button on top of layout
	layout.add_child(click_button)

	# Hover effects (only if can buy)
	click_button.mouse_entered.connect(func():
		if can_buy:
			panel_style.bg_color = Color(0.18, 0.18, 0.22, 1.0)
			panel_style.border_color = Color(color.r + 0.2, color.g + 0.2, color.b + 0.2, 1.0)
	)
	click_button.mouse_exited.connect(func():
		panel_style.bg_color = SLOT_BG
		panel_style.border_color = color
	)

	return panel

func purchase_weapon(index: int) -> void:
	"""Attempt to purchase a weapon"""
	if not vendor:
		return

	if index < 0 or index >= vendor.weapons_for_sale.size():
		return

	var weapon: Weapon = vendor.weapons_for_sale[index]

	# Double-check: prevent duplicate purchases (failsafe for rapid clicking)
	if _player_owns_weapon(weapon.weapon_name):
		show_message("You already own this weapon!", Color(0.9, 0.7, 0.2))
		populate_weapons()  # Refresh UI to show "Owned"
		return

	var success = vendor.purchase_weapon(index)

	if success:
		var price = vendor.get_weapon_price_data(index)

		# Get rarity as string
		var rarity_str = Weapon.Rarity.keys()[weapon.rarity]

		# Show item added notification
		NotificationManager.notify_item_added(weapon.weapon_name, 1, rarity_str)

		item_purchased.emit(weapon.weapon_name, price)

		# Play gold loot sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

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
	var armor_slot = armor_data.get("slot", "")
	var armor_rarity = armor_data.get("rarity", "COMMON")

	# Double-check: prevent duplicate purchases (failsafe for rapid clicking)
	if _player_owns_armor(armor_name, armor_slot):
		show_message("You already own this armor!", Color(0.9, 0.7, 0.2))
		populate_armor()  # Refresh UI to show "Owned"
		return

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
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

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
	var tool_type = tool_data.get("tool_type", "tool")
	var tool_rarity = tool_data.get("rarity", "COMMON")

	# Double-check: prevent duplicate purchases (failsafe for rapid clicking)
	if _player_owns_tool(tool_name, tool_type):
		show_message("You already own this tool!", Color(0.9, 0.7, 0.2))
		populate_tools()  # Refresh UI to show "Owned"
		return

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
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

		# Refresh the UI
		update_gold_display()
		populate_tools()
		populate_sell_items()

		# Inventory notification handles feedback - no need for extra message
	else:
		show_message("Cannot purchase this item!", Color.RED)

func show_message(text: String, color: Color) -> void:
	"""Show a temporary message to the player (top of shop UI)"""
	if not message_label:
		return

	message_label.text = text
	message_label.add_theme_color_override("font_color", color)
	message_label.show()

	# Hide after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if message_label:
		message_label.hide()

func _create_quest_message_label() -> void:
	"""Create a message label above the shop window for quest feedback"""
	var control = get_node_or_null("Control")
	if not control:
		return

	# Create message label positioned above the shop panel
	quest_message_label = Label.new()
	quest_message_label.name = "QuestMessageLabel"
	quest_message_label.visible = false
	quest_message_label.add_theme_font_size_override("font_size", 18)
	quest_message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	quest_message_label.add_theme_constant_override("outline_size", 3)
	quest_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Position above the panel (panel is centered with offset_top = -300)
	quest_message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	quest_message_label.anchor_top = 0.5
	quest_message_label.anchor_bottom = 0.5
	quest_message_label.offset_top = -330  # Above the panel's top edge (-300 - 30)
	quest_message_label.offset_bottom = -305
	quest_message_label.offset_left = -300
	quest_message_label.offset_right = 300

	control.add_child(quest_message_label)

func show_quest_message(text: String, color: Color) -> void:
	"""Show a temporary message in the Quests tab area"""
	if not quest_message_label:
		return

	quest_message_label.text = text
	quest_message_label.add_theme_color_override("font_color", color)
	quest_message_label.show()

	# Hide after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if quest_message_label and is_instance_valid(quest_message_label):
		quest_message_label.hide()

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
	"""Populate the sell list with inventory items using icon grid"""
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
			var item_slot = create_sell_item_slot(item, i)
			sell_list.add_child(item_slot)

	# Show message if inventory is empty
	if not has_items:
		var empty_label = Label.new()
		empty_label.text = "Your inventory is empty"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sell_list.add_child(empty_label)

func create_sell_item_slot(item_data: Dictionary, slot_index: int) -> PanelContainer:
	"""Create a sell slot with icon, quantity badge, and price - matches InventoryUI style (square slots)"""
	var slot_dimensions = Vector2(SLOT_SIZE, SLOT_SIZE)

	var item_name = item_data.get("name", "Unknown")
	var item_desc = item_data.get("description", "")
	var item_value = item_data.get("value", 0)
	var quantity = item_data.get("quantity", 1)
	var total_value = item_value * quantity
	var item_rarity = item_data.get("rarity", "COMMON")

	# Get rarity color (use string version since inventory items store rarity as string)
	var rarity_color = get_armor_rarity_color(item_rarity)

	# Main container
	var panel = PanelContainer.new()
	panel.custom_minimum_size = slot_dimensions

	# Style the panel with rarity border (matching inventory style)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = SLOT_BG
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = rarity_color
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", panel_style)

	# Manual layout container (Control for absolute positioning)
	var layout = Control.new()
	layout.custom_minimum_size = slot_dimensions
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(layout)

	# Icon container (centered in slot)
	var icon_container = CenterContainer.new()
	icon_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_container.offset_bottom = -12  # Leave room for price label at bottom
	layout.add_child(icon_container)

	# Try to get icon from ItemIconGenerator
	var icon_texture: Texture2D = null
	if ItemIconGenerator:
		icon_texture = ItemIconGenerator.get_item_icon(item_data)

	if icon_texture:
		var icon = TextureRect.new()
		icon.texture = icon_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.custom_minimum_size = Vector2(ICON_SIZE - 4, ICON_SIZE - 4)
		icon_container.add_child(icon)
	else:
		# Fallback: show item type as text
		var fallback_label = Label.new()
		var type_text = item_data.get("weapon_type", item_data.get("type", "?"))
		if type_text is String:
			fallback_label.text = type_text.substr(0, 3).to_upper()
		else:
			fallback_label.text = "???"
		fallback_label.add_theme_font_size_override("font_size", 14)
		fallback_label.add_theme_color_override("font_color", rarity_color)
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_container.add_child(fallback_label)

	# Quantity badge (top-right corner) if more than 1
	if quantity > 1:
		var qty_container = PanelContainer.new()
		qty_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		qty_container.offset_left = -22
		qty_container.offset_right = -2
		qty_container.offset_top = 2
		qty_container.offset_bottom = 14

		var qty_bg_style = StyleBoxFlat.new()
		qty_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
		qty_bg_style.corner_radius_top_left = 3
		qty_bg_style.corner_radius_top_right = 3
		qty_bg_style.corner_radius_bottom_left = 3
		qty_bg_style.corner_radius_bottom_right = 3
		qty_bg_style.content_margin_left = 2
		qty_bg_style.content_margin_right = 2
		qty_container.add_theme_stylebox_override("panel", qty_bg_style)
		layout.add_child(qty_container)

		var qty_label = Label.new()
		qty_label.text = "x%d" % quantity
		qty_label.add_theme_font_size_override("font_size", 8)
		qty_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_container.add_child(qty_label)

	# Price label container (anchored at bottom with background pill)
	var price_container = PanelContainer.new()
	price_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	price_container.anchor_left = 0.5
	price_container.anchor_right = 0.5
	price_container.offset_left = -24
	price_container.offset_right = 24
	price_container.offset_top = -14
	price_container.offset_bottom = -2

	var price_bg_style = StyleBoxFlat.new()
	price_bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	price_bg_style.corner_radius_top_left = 3
	price_bg_style.corner_radius_top_right = 3
	price_bg_style.corner_radius_bottom_left = 3
	price_bg_style.corner_radius_bottom_right = 3
	price_bg_style.content_margin_left = 4
	price_bg_style.content_margin_right = 4
	price_bg_style.content_margin_top = 1
	price_bg_style.content_margin_bottom = 1
	price_container.add_theme_stylebox_override("panel", price_bg_style)
	layout.add_child(price_container)

	var price_label = Label.new()
	price_label.text = "%dG" % total_value
	price_label.add_theme_font_size_override("font_size", 9)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_container.add_child(price_label)

	# Clickable overlay button (invisible but handles clicks)
	var click_button = Button.new()
	click_button.flat = true
	click_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Build tooltip
	var tooltip = "[%s]" % item_name
	if item_desc:
		tooltip += "\n%s" % item_desc
	tooltip += "\n\nSell for %d G" % total_value
	if quantity > 1:
		tooltip += " (%d G each)" % item_value
	click_button.tooltip_text = tooltip

	click_button.pressed.connect(func(): sell_item(slot_index))

	# Add button on top of layout
	layout.add_child(click_button)

	# Hover effects
	click_button.mouse_entered.connect(func():
		panel_style.bg_color = Color(0.18, 0.18, 0.22, 1.0)
		panel_style.border_color = Color(rarity_color.r + 0.2, rarity_color.g + 0.2, rarity_color.b + 0.2, 1.0)
	)
	click_button.mouse_exited.connect(func():
		panel_style.bg_color = SLOT_BG
		panel_style.border_color = rarity_color
	)

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
		sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

	# Refresh the UI
	update_gold_display()
	populate_sell_items()

# ═══════════════════════════════════════════════════════════════════════════
# QUESTS TAB
# ═══════════════════════════════════════════════════════════════════════════

const QUEST_AVAILABLE_COLOR = Color(1.0, 0.85, 0.2)  # Gold (existing !)
const QUEST_COMPLETE_COLOR = Color(1.0, 0.9, 0.3)    # Bright gold
const QUEST_LOCKED_COLOR = Color(0.4, 0.4, 0.45)     # Dim gray

func populate_quests() -> void:
	"""Populate the quests list with available and completable quests"""
	if not quests_list:
		return

	# Clear existing items
	for child in quests_list.get_children():
		child.queue_free()

	# Check if QuestManager exists
	if not has_node("/root/QuestManager"):
		var no_quests = Label.new()
		no_quests.text = "Quest system not available"
		no_quests.add_theme_font_size_override("font_size", 16)
		no_quests.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_quests.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quests_list.add_child(no_quests)
		return

	var qm = get_node("/root/QuestManager")
	var giver = vendor.vendor_name.to_lower() if vendor else "blacksmith"

	# Get quests ready for turn-in, available, and in-progress
	var completed_quests = qm.get_completed_quests(giver)
	var available_quests = qm.get_available_quests(giver)
	var active_quests = qm.get_active_quests()  # All active quests (in progress)

	# Filter active quests to only show ones from this vendor that aren't complete
	var in_progress_quests = []
	for quest in active_quests:
		var quest_giver = quest.get("giver", "").to_lower()
		if quest_giver == giver:
			var quest_id = quest.get("id", "")
			var state = qm.get_quest_state(quest_id)
			if state == qm.QuestState.ACTIVE:  # Only in-progress, not complete
				in_progress_quests.append(quest)

	var has_content = false

	# Show completed quests first (ready for turn-in)
	if completed_quests.size() > 0:
		has_content = true
		var turn_in_header = Label.new()
		turn_in_header.text = "READY TO TURN IN"
		turn_in_header.add_theme_font_size_override("font_size", 14)
		turn_in_header.add_theme_color_override("font_color", QUEST_COMPLETE_COLOR)
		quests_list.add_child(turn_in_header)

		for quest in completed_quests:
			var card = create_quest_card(quest, true)
			quests_list.add_child(card)

		# Separator
		var sep = HSeparator.new()
		sep.add_theme_constant_override("separation", 8)
		quests_list.add_child(sep)

	# Show in-progress quests
	if in_progress_quests.size() > 0:
		has_content = true
		var progress_header = Label.new()
		progress_header.text = "IN PROGRESS"
		progress_header.add_theme_font_size_override("font_size", 14)
		progress_header.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))  # Light blue
		quests_list.add_child(progress_header)

		for quest in in_progress_quests:
			var card = create_quest_progress_card(quest)
			quests_list.add_child(card)

		# Separator
		var sep = HSeparator.new()
		sep.add_theme_constant_override("separation", 8)
		quests_list.add_child(sep)

	# Show available quests
	if available_quests.size() > 0:
		has_content = true
		var avail_header = Label.new()
		avail_header.text = "AVAILABLE QUESTS"
		avail_header.add_theme_font_size_override("font_size", 14)
		avail_header.add_theme_color_override("font_color", QUEST_AVAILABLE_COLOR)
		quests_list.add_child(avail_header)

		for quest in available_quests:
			var card = create_quest_card(quest, false)
			quests_list.add_child(card)

	# Show upcoming/locked quests preview
	var locked_quests = qm.get_locked_quests(giver, 3)
	if locked_quests.size() > 0:
		# Add separator
		var sep = HSeparator.new()
		sep.custom_minimum_size.y = 10
		quests_list.add_child(sep)

		var locked_header = Label.new()
		locked_header.text = "UPCOMING QUESTS"
		locked_header.add_theme_font_size_override("font_size", 14)
		locked_header.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		quests_list.add_child(locked_header)

		for quest in locked_quests:
			var locked_card = create_locked_quest_card(quest)
			quests_list.add_child(locked_card)

	# No quests message - only if nothing to show at all
	if not has_content and locked_quests.size() == 0:
		var no_quests = Label.new()
		no_quests.text = "No quests available.\nLevel up to unlock more!"
		no_quests.add_theme_font_size_override("font_size", 16)
		no_quests.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_quests.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		quests_list.add_child(no_quests)

func create_quest_card(quest: Dictionary, is_complete: bool) -> PanelContainer:
	"""Create a quest card with description and accept/turn-in button"""
	var quest_id = quest.get("id", "")
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120)

	# Style the card with enhanced visuals
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.10, 0.12, 0.95)  # Slightly lighter background
	card_style.border_width_left = 3
	card_style.border_width_right = 3
	card_style.border_width_top = 3
	card_style.border_width_bottom = 3
	card_style.border_color = QUEST_COMPLETE_COLOR if is_complete else QUEST_AVAILABLE_COLOR
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 12
	card_style.content_margin_bottom = 12
	card_style.shadow_size = 4
	card_style.shadow_color = Color(0, 0, 0, 0.4)
	card_style.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Quest name with indicator - larger and bolder
	var name_hbox = HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(name_hbox)

	var indicator = Label.new()
	indicator.text = "?" if is_complete else "!"
	indicator.add_theme_font_size_override("font_size", 22)
	indicator.add_theme_color_override("font_color", QUEST_COMPLETE_COLOR if is_complete else QUEST_AVAILABLE_COLOR)
	indicator.add_theme_color_override("font_outline_color", Color.BLACK)
	indicator.add_theme_constant_override("outline_size", 2)
	name_hbox.add_child(indicator)

	var name_label = Label.new()
	name_label.text = quest.get("name", "Unknown Quest")
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 1)
	name_hbox.add_child(name_label)

	# Description with better styling
	var desc_label = Label.new()
	desc_label.text = quest.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.82))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# Objectives (for available quests) - in styled container
	if not is_complete:
		var objectives = quest.get("objectives", [])
		if objectives.size() > 0:
			var obj_container = VBoxContainer.new()
			obj_container.add_theme_constant_override("separation", 6)
			vbox.add_child(obj_container)

			for obj in objectives:
				var obj_hbox = HBoxContainer.new()
				obj_hbox.add_theme_constant_override("separation", 8)
				obj_container.add_child(obj_hbox)

				var bullet = Label.new()
				bullet.text = "▸"
				bullet.add_theme_font_size_override("font_size", 15)
				bullet.add_theme_color_override("font_color", QUEST_AVAILABLE_COLOR)
				obj_hbox.add_child(bullet)

				var obj_label = Label.new()
				obj_label.text = "%s (0/%d)" % [obj.get("desc", ""), obj.get("count", 1)]
				obj_label.add_theme_font_size_override("font_size", 15)
				obj_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.82))
				obj_hbox.add_child(obj_label)

	# Separator line
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# Rewards and button row - with icons
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(bottom_hbox)

	var rewards_hbox = HBoxContainer.new()
	rewards_hbox.add_theme_constant_override("separation", 12)
	rewards_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(rewards_hbox)

	var xp_reward = quest.get("xp_reward", 0)
	var gold_reward = quest.get("gold_reward", 0)

	# XP reward with icon
	var xp_label = Label.new()
	xp_label.text = "⭐ %d XP" % xp_reward
	xp_label.add_theme_font_size_override("font_size", 14)
	xp_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))  # Light blue for XP
	rewards_hbox.add_child(xp_label)

	# Gold reward with icon
	if gold_reward > 0:
		var gold_hbox = HBoxContainer.new()
		gold_hbox.add_theme_constant_override("separation", 4)
		var gold_icon = TextureRect.new()
		gold_icon.texture = preload("res://assets/icons/materials/gold_coins.png")
		gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gold_icon.custom_minimum_size = Vector2(16, 16)
		gold_hbox.add_child(gold_icon)
		var gold_amount_label = Label.new()
		gold_amount_label.text = "%d" % gold_reward
		gold_amount_label.add_theme_font_size_override("font_size", 14)
		gold_amount_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Gold color
		gold_hbox.add_child(gold_amount_label)
		rewards_hbox.add_child(gold_hbox)

	# Action button - more prominent
	var action_btn = Button.new()
	action_btn.text = "✓ TURN IN" if is_complete else "► ACCEPT"
	action_btn.add_theme_font_size_override("font_size", 14)
	action_btn.custom_minimum_size = Vector2(100, 32)

	# Style button with gradient effect
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.25, 0.5, 0.25, 1.0) if is_complete else Color(0.25, 0.35, 0.5, 1.0)
	btn_style.border_width_left = 2
	btn_style.border_width_right = 2
	btn_style.border_width_top = 2
	btn_style.border_width_bottom = 2
	btn_style.border_color = QUEST_COMPLETE_COLOR if is_complete else QUEST_AVAILABLE_COLOR
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn_style.content_margin_left = 16
	btn_style.content_margin_right = 16
	btn_style.content_margin_top = 6
	btn_style.content_margin_bottom = 6
	action_btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.35, 0.6, 0.35, 1.0) if is_complete else Color(0.35, 0.45, 0.6, 1.0)
	btn_hover.border_color = Color(1.0, 1.0, 1.0, 0.8)
	action_btn.add_theme_stylebox_override("hover", btn_hover)

	action_btn.add_theme_color_override("font_color", Color.WHITE)
	action_btn.add_theme_color_override("font_hover_color", Color.WHITE)

	if is_complete:
		action_btn.pressed.connect(func(): _on_turn_in_quest(quest_id))
	else:
		action_btn.pressed.connect(func(): _on_accept_quest(quest_id))

	bottom_hbox.add_child(action_btn)

	return card

func create_quest_progress_card(quest: Dictionary) -> PanelContainer:
	"""Create a quest card showing current progress (no action button)"""
	var quest_id = quest.get("id", "")
	var qm = get_node("/root/QuestManager")

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 100)

	# Style the card with light blue border for in-progress
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	card_style.border_width_left = 3
	card_style.border_width_right = 3
	card_style.border_width_top = 3
	card_style.border_width_bottom = 3
	card_style.border_color = Color(0.5, 0.65, 0.85)  # Light blue
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 12
	card_style.content_margin_bottom = 12
	card_style.shadow_size = 4
	card_style.shadow_color = Color(0, 0, 0, 0.4)
	card_style.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Quest name with in-progress indicator
	var name_hbox = HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(name_hbox)

	var indicator = Label.new()
	indicator.text = "◐"  # Half-filled circle for in-progress
	indicator.add_theme_font_size_override("font_size", 18)
	indicator.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85))
	name_hbox.add_child(indicator)

	var name_label = Label.new()
	name_label.text = quest.get("name", "Unknown Quest")
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 1)
	name_hbox.add_child(name_label)

	# Objectives with progress - styled list
	var objectives = quest.get("objectives", [])
	var obj_container = VBoxContainer.new()
	obj_container.add_theme_constant_override("separation", 6)
	vbox.add_child(obj_container)

	for i in range(objectives.size()):
		var obj = objectives[i]
		var current = qm.get_objective_progress(quest_id, i)
		var required = obj.get("count", 1)
		var is_obj_complete = current >= required
		var progress_pct = float(current) / float(required) if required > 0 else 0.0

		var obj_hbox = HBoxContainer.new()
		obj_hbox.add_theme_constant_override("separation", 8)
		obj_container.add_child(obj_hbox)

		# Checkmark or bullet
		var bullet = Label.new()
		bullet.text = "✓" if is_obj_complete else "▸"
		bullet.add_theme_font_size_override("font_size", 16)
		bullet.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if is_obj_complete else Color(0.5, 0.65, 0.85))
		obj_hbox.add_child(bullet)

		# Objective text with progress
		var obj_label = Label.new()
		obj_label.text = "%s: %d/%d" % [obj.get("desc", ""), current, required]
		obj_label.add_theme_font_size_override("font_size", 15)
		obj_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4) if is_obj_complete else Color(0.85, 0.85, 0.88))
		obj_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		obj_hbox.add_child(obj_label)

		# Progress percentage
		if not is_obj_complete:
			var pct_label = Label.new()
			pct_label.text = "(%d%%)" % int(progress_pct * 100)
			pct_label.add_theme_font_size_override("font_size", 14)
			pct_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
			obj_hbox.add_child(pct_label)

	return card

func create_locked_quest_card(quest: Dictionary) -> PanelContainer:
	"""Create a grayed-out card for locked/upcoming quests"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 70)

	# Style with muted colors
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.08, 0.09, 0.8)
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color(0.3, 0.3, 0.35)
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Quest name row
	var name_hbox = HBoxContainer.new()
	name_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(name_hbox)

	var lock_icon = Label.new()
	lock_icon.text = "🔒"
	lock_icon.add_theme_font_size_override("font_size", 14)
	name_hbox.add_child(lock_icon)

	var name_label = Label.new()
	name_label.text = quest.get("name", "Unknown Quest")
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	name_hbox.add_child(name_label)

	# Level requirement
	var level_req = quest.get("level_req", 1)
	var level_label = Label.new()
	level_label.text = "Lv.%d" % level_req
	level_label.add_theme_font_size_override("font_size", 13)
	level_label.add_theme_color_override("font_color", Color(0.6, 0.5, 0.3))
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_hbox.add_child(level_label)

	# Lock reason
	var reason = quest.get("_locked_reason", "Locked")
	var reason_label = Label.new()
	reason_label.text = reason
	reason_label.add_theme_font_size_override("font_size", 13)
	reason_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
	vbox.add_child(reason_label)

	return card

func _on_accept_quest(quest_id: String) -> void:
	"""Handle quest accept button"""
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	if qm.accept_quest(quest_id):
		var quest = qm.get_quest(quest_id)
		show_quest_message("Quest accepted: %s" % quest.get("name", ""), Color(0.5, 0.9, 0.5))

		# Play quest accept sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.QUEST_ACCEPT, -10.0)

		# Refresh the list and tab indicator
		populate_quests()
		update_quests_tab_indicator()
	else:
		show_quest_message("Cannot accept quest - max quests reached!", Color.RED)

func _on_turn_in_quest(quest_id: String) -> void:
	"""Handle quest turn-in button"""
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	if qm.turn_in_quest(quest_id):
		# Note: If quest has item reward choice, turn_in_quest returns true but
		# doesn't complete - it emits quest_reward_choice_needed signal instead
		var quest = qm.get_quest(quest_id)

		# Check if quest is still COMPLETE (waiting for item choice)
		if qm.get_quest_state(quest_id) == qm.QuestState.COMPLETE:
			# Item choice popup will handle completion
			return

		var xp = quest.get("xp_reward", 0)
		var gold = quest.get("gold_reward", 0)
		show_quest_message("Quest complete! +%d XP, +%d G" % [xp, gold], Color(1.0, 0.85, 0.2))

		# Play quest turn in sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.QUEST_TURN_IN, -10.0)

		# Refresh the list, gold display, and tab indicator
		update_gold_display()
		populate_quests()
		update_quests_tab_indicator()
	else:
		show_quest_message("Cannot turn in quest!", Color.RED)

# ═══════════════════════════════════════════════════════════════════════════
# QUEST REWARD CHOICE POPUP
# ═══════════════════════════════════════════════════════════════════════════

var reward_choice_popup: PanelContainer = null
var pending_reward_quest_id: String = ""

func _on_quest_reward_choice_needed(quest_id: String, quest_name: String, options: Array) -> void:
	"""Show popup for player to choose their armor reward"""
	print("🎁 Showing reward choice for quest: %s" % quest_name)
	pending_reward_quest_id = quest_id
	_show_reward_choice_popup(quest_name, options)

func _show_reward_choice_popup(quest_name: String, options: Array) -> void:
	"""Create and display the reward choice popup"""
	# Remove existing popup if any
	if reward_choice_popup and is_instance_valid(reward_choice_popup):
		reward_choice_popup.queue_free()

	# Create popup panel
	reward_choice_popup = PanelContainer.new()
	reward_choice_popup.name = "RewardChoicePopup"

	# Style the popup
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.08, 0.08, 0.10, 0.95)
	popup_style.border_width_left = 3
	popup_style.border_width_right = 3
	popup_style.border_width_top = 3
	popup_style.border_width_bottom = 3
	popup_style.border_color = Color(0.8, 0.7, 0.3)  # Gold border for reward
	popup_style.corner_radius_top_left = 8
	popup_style.corner_radius_top_right = 8
	popup_style.corner_radius_bottom_left = 8
	popup_style.corner_radius_bottom_right = 8
	popup_style.shadow_size = 15
	popup_style.shadow_color = Color(0, 0, 0, 0.9)
	reward_choice_popup.add_theme_stylebox_override("panel", popup_style)

	# Main container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	reward_choice_popup.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "Choose Your Reward"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # Gold
	vbox.add_child(header)

	# Subheader with quest name
	var subheader = Label.new()
	subheader.text = quest_name
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subheader.add_theme_font_size_override("font_size", 14)
	subheader.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(subheader)

	# Options container (horizontal)
	var options_hbox = HBoxContainer.new()
	options_hbox.add_theme_constant_override("separation", 15)
	options_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(options_hbox)

	# Create option buttons
	for option in options:
		var option_btn = _create_reward_option_button(option)
		options_hbox.add_child(option_btn)

	# Add popup to the Control node (same level as main panel)
	var control = get_node_or_null("Control")
	if control:
		control.add_child(reward_choice_popup)
	else:
		add_child(reward_choice_popup)

	# Center the popup
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	var popup_size = reward_choice_popup.size
	reward_choice_popup.position = (viewport_size - popup_size) / 2

func _create_reward_option_button(option: Dictionary) -> VBoxContainer:
	"""Create a clickable option for a reward choice"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)

	# Button with styled background
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(120, 100)

	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	btn_style.border_width_left = 2
	btn_style.border_width_right = 2
	btn_style.border_width_top = 2
	btn_style.border_width_bottom = 2
	btn_style.border_color = BORDER_COLOR
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover = btn_style.duplicate()
	btn_hover.border_color = Color(0.8, 0.7, 0.3)  # Gold on hover
	btn_hover.bg_color = Color(0.2, 0.2, 0.22, 1.0)
	btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed = btn_style.duplicate()
	btn_pressed.border_color = Color(1.0, 0.85, 0.3)
	btn_pressed.bg_color = Color(0.25, 0.22, 0.15, 1.0)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	# Icon/armor type indicator
	var armor_type = option.get("armor_type", "plate")
	var icon_label = Label.new()
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Use text symbols for armor types
	match armor_type:
		"plate":
			icon_label.text = "[P]"
			icon_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))  # Steel
		"leather":
			icon_label.text = "[L]"
			icon_label.add_theme_color_override("font_color", Color(0.6, 0.45, 0.3))  # Brown
		"cloth":
			icon_label.text = "[C]"
			icon_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))  # Grey-blue

	icon_label.add_theme_font_size_override("font_size", 28)

	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(0, 50)
	icon_container.add_child(icon_label)
	btn.add_child(icon_container)

	container.add_child(btn)

	# Item name label
	var name_label = Label.new()
	name_label.text = option.get("name", "Unknown")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size = Vector2(110, 0)
	container.add_child(name_label)

	# Armor type label
	var type_label = Label.new()
	type_label.text = armor_type.capitalize()
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 10)
	type_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(type_label)

	# Connect button press
	var item_id = option.get("id", "")
	btn.pressed.connect(func(): _on_reward_option_selected(item_id))

	return container

func _on_reward_option_selected(item_id: String) -> void:
	"""Handle player selecting a reward option"""
	print("🎁 Player selected reward: %s" % item_id)

	# Close popup
	if reward_choice_popup and is_instance_valid(reward_choice_popup):
		reward_choice_popup.queue_free()
		reward_choice_popup = null

	# Grant the reward
	if pending_reward_quest_id.is_empty():
		push_error("[ShopUI] No pending reward quest ID!")
		return

	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	if qm.grant_item_reward(pending_reward_quest_id, item_id):
		var quest = qm.get_quest(pending_reward_quest_id)
		var xp = quest.get("xp_reward", 0)
		var gold = quest.get("gold_reward", 0)
		show_quest_message("Quest complete! Armor received!", Color(1.0, 0.85, 0.2))

		# Play quest turn in sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.QUEST_TURN_IN, -10.0)

		# Refresh the list, gold display, and tab indicator
		update_gold_display()
		populate_quests()
		update_quests_tab_indicator()

	pending_reward_quest_id = ""

func _on_close_pressed() -> void:
	"""Handle close button press"""
	_play_click_sound()
	close_shop()

func _on_tab_changed(tab_idx: int) -> void:
	"""Handle tab changes - notify tutorial system if waiting for Quests tab"""
	_play_click_sound()
	if not tab_container:
		return

	var tab_title = tab_container.get_tab_title(tab_idx)
	print("🏪 Tab changed to: %s (idx %d)" % [tab_title, tab_idx])

	# Notify tutorial system if we clicked on Quests tab
	if tab_title.begins_with("Quests"):
		if TutorialManager and TutorialManager.is_tutorial_active():
			TutorialManager.on_quests_tab_selected()

func update_quests_tab_indicator() -> void:
	"""Update the Quests tab title with indicator based on available/complete quests"""
	if not tab_container:
		return

	# Find the Quests tab index
	var quests_tab_idx = -1
	for i in range(tab_container.get_tab_count()):
		var title = tab_container.get_tab_title(i)
		if title.begins_with("Quests"):
			quests_tab_idx = i
			break

	if quests_tab_idx == -1:
		return

	# Check for available and completable quests
	var has_turn_in = false
	var has_available = false

	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		var giver = vendor.vendor_name.to_lower() if vendor else "blacksmith"

		var completed_quests = qm.get_completed_quests(giver)
		var available_quests = qm.get_available_quests(giver)

		has_turn_in = completed_quests.size() > 0
		has_available = available_quests.size() > 0

	# Simple approach: just change the tab title text
	# Priority: ? (turn-in) > ! (available) > none
	var tab_title = "Quests"
	if has_turn_in:
		tab_title = "Quests (?)"  # Ready to turn in
	elif has_available:
		tab_title = "Quests (!)"  # New quests available

	tab_container.set_tab_title(quests_tab_idx, tab_title)

# ═══════════════════════════════════════════════════════════════════════════
# FORGE TAB
# ═══════════════════════════════════════════════════════════════════════════

func populate_forge() -> void:
	"""Populate the forge tab with ALL ForgeItemDB items for PLAYTEST claiming"""
	if not forge_list:
		return

	# Clear existing items
	for child in forge_list.get_children():
		child.queue_free()

	# Header message
	var info = Label.new()
	info.text = "PLAYTEST FORGE - Select any item to claim it once (isolated from NFT system)"
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_list.add_child(info)

	# Separator
	var sep1 = Control.new()
	sep1.custom_minimum_size = Vector2(0, 8)
	forge_list.add_child(sep1)

	# Get all items from ForgeItemDB
	var all_items = []
	for achievement_key in ForgeItemDB.FORGE_ITEMS.keys():
		var forge_db = ForgeItemDB.FORGE_ITEMS[achievement_key]
		var item_id = forge_db.get("item_id", "")
		if item_id == "":
			continue

		all_items.append({
			"item_id": item_id,
			"item_name": forge_db.get("item_name", "Unknown"),
			"item_type": ForgeItemDB.ItemType.keys()[forge_db.get("item_type", 0)].to_lower(),
			"rarity": ForgeItemDB.ItemRarity.keys()[forge_db.get("rarity", 0)].to_lower(),
		})

	# Sort by rarity (legendary first)
	all_items.sort_custom(func(a, b): return _playtest_rarity_value(a.rarity) < _playtest_rarity_value(b.rarity))

	# Separate into unclaimed and claimed
	var unclaimed_items = []
	var claimed_items = []
	for item in all_items:
		if CharacterStats.has_claimed_playtest_item(item.item_id):
			claimed_items.append(item)
		else:
			unclaimed_items.append(item)

	# Show unclaimed items first
	if unclaimed_items.size() > 0:
		var claim_header = Label.new()
		claim_header.text = "⚒ AVAILABLE TO CLAIM (%d)" % unclaimed_items.size()
		claim_header.add_theme_font_size_override("font_size", 14)
		claim_header.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2))  # Orange
		forge_list.add_child(claim_header)

		# Create grid for unclaimed items
		var unclaimed_grid = _create_forge_grid()
		forge_list.add_child(unclaimed_grid)

		for item in unclaimed_items:
			var slot = _create_playtest_forge_slot(item, false)
			unclaimed_grid.add_child(slot)

		# Separator
		var sep = Control.new()
		sep.custom_minimum_size = Vector2(0, 12)
		forge_list.add_child(sep)

	# Show claimed items
	if claimed_items.size() > 0:
		var claimed_header = Label.new()
		claimed_header.text = "✓ CLAIMED (%d)" % claimed_items.size()
		claimed_header.add_theme_font_size_override("font_size", 14)
		claimed_header.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))  # Green
		forge_list.add_child(claimed_header)

		# Create grid for claimed items
		var claimed_grid = _create_forge_grid()
		forge_list.add_child(claimed_grid)

		for item in claimed_items:
			var slot = _create_playtest_forge_slot(item, true)
			claimed_grid.add_child(slot)

	# DEBUG: Clear forged items button (for playtesting)
	var sep2 = Control.new()
	sep2.custom_minimum_size = Vector2(0, 12)
	forge_list.add_child(sep2)

	var clear_button_container = CenterContainer.new()
	forge_list.add_child(clear_button_container)

	var clear_btn = Button.new()
	clear_btn.text = "🗑 Clear All Forged Items (Playtest)"
	clear_btn.custom_minimum_size = Vector2(250, 32)
	clear_btn.pressed.connect(_on_clear_forged_items_pressed)
	clear_button_container.add_child(clear_btn)

	# Update status
	_update_forge_status("Claimed: %d / %d" % [claimed_items.size(), all_items.size()])

func _playtest_rarity_value(rarity: String) -> int:
	"""Helper for sorting by rarity (legendary first)"""
	match rarity:
		"legendary": return 0
		"epic": return 1
		"rare": return 2
		"uncommon": return 3
		"common": return 4
		_: return 5

func _create_forge_grid() -> GridContainer:
	"""Create a grid container for forge item slots"""
	var grid = GridContainer.new()
	grid.columns = 10  # Match BlacksmithForgeUI
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid

func _create_forge_slot(item: Dictionary, is_claimed: bool) -> PanelContainer:
	"""Create a 54px icon slot for a forged item - matches inventory style"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if not is_claimed else Control.MOUSE_FILTER_IGNORE

	# Get item properties
	var item_id = item.get("item_id", "")
	var item_name = item.get("item_name", "Unknown Item")
	var item_rarity = item.get("rarity", "common").to_lower()
	var rarity_color = FORGE_RARITY_COLORS.get(item_rarity, Color(0.6, 0.6, 0.6))

	# Slot style with rarity border
	var slot_style = StyleBoxFlat.new()
	if is_claimed:
		slot_style.bg_color = Color(0.03, 0.03, 0.04, 1.0)
		slot_style.border_color = Color(0.15, 0.15, 0.18)
	else:
		slot_style.bg_color = SLOT_BG
		slot_style.border_color = rarity_color
		slot_style.shadow_size = 6
		slot_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.4)

	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(5)
	slot.add_theme_stylebox_override("panel", slot_style)

	# Store item data for click handling
	slot.set_meta("item_data", item)
	slot.set_meta("is_claimed", is_claimed)

	# Load icon (enhanced first, then regular) - icons are organized by type
	var item_type = item.get("item_type", "weapon")
	# Map item types to icon folder names (armor is singular, others are plural)
	var icon_folder = item_type
	match item_type:
		"weapon": icon_folder = "weapons"
		"armor": icon_folder = "armor"  # singular
		"shield": icon_folder = "shields"
		"accessory": icon_folder = "accessories"
		"cape": icon_folder = "capes"
		"tool": icon_folder = "tools"

	var icon_path = "res://assets/icons/forged/" + icon_folder + "/" + item_id + ".png"
	var enhanced_icon_path = "res://assets/icons/enhanced/forged/" + icon_folder + "/" + item_id + ".png"

	var texture = null
	if ResourceLoader.exists(enhanced_icon_path):
		texture = load(enhanced_icon_path)
	elif ResourceLoader.exists(icon_path):
		texture = load(icon_path)

	if texture:
		var icon = TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if is_claimed:
			icon.modulate = Color(0.3, 0.3, 0.3, 0.5)  # Dim claimed items
		slot.add_child(icon)

	# Claimed checkmark overlay
	if is_claimed:
		var check = Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 24)
		check.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		check.position = Vector2(SLOT_SIZE - 20, SLOT_SIZE - 24)
		slot.add_child(check)

	# Click handler for unclaimed items
	if not is_claimed:
		slot.gui_input.connect(_on_forge_slot_clicked.bind(slot))

	# Tooltip
	var tooltip_lines = []
	tooltip_lines.append(item_name)
	tooltip_lines.append(item_rarity.capitalize())
	if is_claimed:
		tooltip_lines.append("[In Inventory]")
	else:
		tooltip_lines.append("[Click to Claim]")
	slot.tooltip_text = "\n".join(tooltip_lines)

	return slot

func _create_playtest_forge_slot(item: Dictionary, is_claimed: bool) -> PanelContainer:
	"""Create a 54px icon slot for a PLAYTEST forge item - matches inventory style"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP if not is_claimed else Control.MOUSE_FILTER_IGNORE

	# Get item properties
	var item_id = item.get("item_id", "")
	var item_name = item.get("item_name", "Unknown Item")
	var item_rarity = item.get("rarity", "common")
	var rarity_color = FORGE_RARITY_COLORS.get(item_rarity, Color(0.6, 0.6, 0.6))

	# Slot style with rarity border
	var slot_style = StyleBoxFlat.new()
	if is_claimed:
		slot_style.bg_color = Color(0.03, 0.03, 0.04, 1.0)
		slot_style.border_color = Color(0.15, 0.15, 0.18)
	else:
		slot_style.bg_color = SLOT_BG
		slot_style.border_color = rarity_color
		slot_style.shadow_size = 6
		slot_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.4)

	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(5)
	slot.add_theme_stylebox_override("panel", slot_style)

	# Store item data for click handling
	slot.set_meta("item_data", item)
	slot.set_meta("is_claimed", is_claimed)

	# Load icon (enhanced first, then regular) - icons are organized by type
	var item_type = item.get("item_type", "weapon")
	# Map item types to icon folder names
	var icon_folder = item_type
	match item_type:
		"armor_head", "armor_chest", "armor_legs", "armor_feet", "armor_hands":
			icon_folder = "armor"
		"weapon":
			icon_folder = "weapons"
		"shield":
			icon_folder = "shields"
		"accessory":
			icon_folder = "accessories"
		"cape":
			icon_folder = "capes"
		"tool":
			icon_folder = "tools"

	var icon_path = "res://assets/icons/forged/" + icon_folder + "/" + item_id + ".png"
	var enhanced_icon_path = "res://assets/icons/enhanced/forged/" + icon_folder + "/" + item_id + ".png"

	var texture = null
	if ResourceLoader.exists(enhanced_icon_path):
		texture = load(enhanced_icon_path)
	elif ResourceLoader.exists(icon_path):
		texture = load(icon_path)

	if texture:
		var icon = TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if is_claimed:
			icon.modulate = Color(0.3, 0.3, 0.3, 0.5)  # Dim claimed items
		slot.add_child(icon)

	# Claimed checkmark overlay
	if is_claimed:
		var check = Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 24)
		check.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		check.position = Vector2(SLOT_SIZE - 20, SLOT_SIZE - 24)
		slot.add_child(check)

	# Click handler for unclaimed items
	if not is_claimed:
		slot.gui_input.connect(_on_playtest_forge_slot_clicked.bind(slot))

	# Tooltip
	var tooltip_lines = []
	tooltip_lines.append(item_name)
	tooltip_lines.append(item_rarity.capitalize())
	if is_claimed:
		tooltip_lines.append("[Claimed]")
	else:
		tooltip_lines.append("[Click to Claim]")
	slot.tooltip_text = "\n".join(tooltip_lines)

	return slot

func _on_playtest_forge_slot_clicked(event: InputEvent, slot: PanelContainer) -> void:
	"""Handle PLAYTEST forge slot click to claim item"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var item_data = slot.get_meta("item_data", {})
		var item_id = item_data.get("item_id", "")

		if item_id == "":
			return

		# Try to claim
		if not CharacterStats.claim_playtest_item(item_id):
			print("[ShopUI] Item already claimed: %s" % item_id)
			return

		# Play sound
		if SoundManager:
			SoundManager.play_button_click_sound(-3.0)

		# Get item from ForgeItemDB
		var forge_db = ForgeItemDB.get_item_by_id(item_id)
		if forge_db.is_empty():
			print("[ShopUI] Item not found in ForgeItemDB: %s" % item_id)
			return

		# Convert to forged item format
		var forged_item = {
			"item_id": item_id,
			"item_name": forge_db.get("item_name", "Unknown"),
			"item_type": ForgeItemDB.ItemType.keys()[forge_db.get("item_type", 0)].to_lower(),
			"item_rarity": ForgeItemDB.ItemRarity.keys()[forge_db.get("rarity", 0)].to_lower(),
			"description": forge_db.get("description", ""),
			"effect_name": forge_db.get("effects", ["standard_particles"])[0] if forge_db.get("effects", []).size() > 0 else "standard_particles",
		}

		# Use ForgeItemManager to convert to inventory format
		var inventory_item = ForgeItemManager._convert_to_inventory_format(forged_item)
		if inventory_item.is_empty():
			print("[ShopUI] Failed to convert to inventory format")
			return

		# Add to inventory
		if InventorySystem.add_item(inventory_item):
			print("[ShopUI] ✅ Claimed: %s" % inventory_item.get("name"))
			# Use NotificationManager for clean floating notification
			var item_name = inventory_item.get("name", "Item")
			var item_rarity = inventory_item.get("rarity", "COMMON")
			NotificationManager.notify_item_added(item_name, 1, item_rarity)
			# Refresh the forge tab
			populate_forge()
		else:
			print("[ShopUI] Failed to add to inventory (full?)")
			# Use NotificationManager for error too
			NotificationManager.show_notification("Inventory full!", "error")

func _on_forge_slot_clicked(event: InputEvent, slot: PanelContainer) -> void:
	"""Handle forge slot click to claim item (OLD BACKEND SYSTEM - NOT USED FOR PLAYTEST)"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var item_data = slot.get_meta("item_data", {})
		var forged_id = item_data.get("forged_id", 0)
		_on_claim_forge_item(forged_id, item_data)

func _on_clear_forged_items_pressed() -> void:
	"""Clear all forged items from inventory (playtest debug)"""
	if InventorySystem:
		var cleared = InventorySystem.clear_forged_items()
		show_message("Cleared %d forged items" % cleared, Color(0.5, 0.9, 0.5))
	if CharacterStats:
		CharacterStats.clear_playtest_claims()
	populate_forge()  # Refresh the grid

func _create_forge_item_card(item: Dictionary, is_claimed: bool) -> PanelContainer:
	"""Create a card displaying a forged item with claim button if unclaimed"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 80)

	# Get item properties
	var item_name = item.get("item_name", "Unknown Item")
	var item_rarity = item.get("item_rarity", "common").to_lower()
	var item_type = item.get("item_type", "weapon")
	var effort_tier = item.get("effort_tier", "")
	var effect_name = item.get("effect_name", "")
	var rarity_color = FORGE_RARITY_COLORS.get(item_rarity, Color(0.6, 0.6, 0.6))

	# Style the card with rarity border
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.10, 0.12, 0.95)
	card_style.border_width_left = 3
	card_style.border_width_right = 3
	card_style.border_width_top = 3
	card_style.border_width_bottom = 3
	card_style.border_color = rarity_color
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card_style.shadow_size = 3
	card_style.shadow_color = Color(0, 0, 0, 0.4)
	card.add_theme_stylebox_override("panel", card_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# Item icon placeholder (could integrate with ItemIconGenerator)
	var icon_container = CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(48, 48)
	hbox.add_child(icon_container)

	var icon_label = Label.new()
	icon_label.text = "⚔" if item_type == "weapon" else ("🛡" if item_type in ["armor", "shield"] else "💎")
	icon_label.add_theme_font_size_override("font_size", 28)
	icon_label.add_theme_color_override("font_color", rarity_color)
	icon_container.add_child(icon_label)

	# Item info
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	# Name with rarity color
	var name_label = Label.new()
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", rarity_color)
	info_vbox.add_child(name_label)

	# Type and rarity
	var type_label = Label.new()
	type_label.text = "%s • %s" % [item_rarity.capitalize(), item_type.capitalize()]
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(type_label)

	# Effect/tier info
	if effort_tier or effect_name:
		var effect_label = Label.new()
		var effect_parts = []
		if effort_tier:
			effect_parts.append(effort_tier)
		if effect_name:
			effect_parts.append(effect_name.replace("_", " ").capitalize())
		effect_label.text = " • ".join(effect_parts)
		effect_label.add_theme_font_size_override("font_size", 11)
		effect_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
		info_vbox.add_child(effect_label)

	# Claim button or status
	if not is_claimed:
		var claim_btn = Button.new()
		claim_btn.text = "CLAIM"
		claim_btn.add_theme_font_size_override("font_size", 12)
		claim_btn.custom_minimum_size = Vector2(70, 30)

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.4, 0.25)
		btn_style.border_width_left = 2
		btn_style.border_width_right = 2
		btn_style.border_width_top = 2
		btn_style.border_width_bottom = 2
		btn_style.border_color = Color(0.4, 0.8, 0.4)
		btn_style.corner_radius_top_left = 4
		btn_style.corner_radius_top_right = 4
		btn_style.corner_radius_bottom_left = 4
		btn_style.corner_radius_bottom_right = 4
		claim_btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover = btn_style.duplicate()
		btn_hover.bg_color = Color(0.3, 0.5, 0.35)
		claim_btn.add_theme_stylebox_override("hover", btn_hover)

		claim_btn.add_theme_color_override("font_color", Color.WHITE)

		var forged_id = item.get("id", 0)
		claim_btn.pressed.connect(func(): _on_claim_forge_item(forged_id, item))
		hbox.add_child(claim_btn)
	else:
		var status_label = Label.new()
		status_label.text = "✓"
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		hbox.add_child(status_label)

	return card

func _on_claim_forge_item(forged_id: int, item: Dictionary) -> void:
	"""Handle claiming a forged item to inventory"""
	if not ForgeItemManager:
		show_message("Forge system unavailable", Color.RED)
		return

	# Claim the item
	var item_id = item.get("item_id", "")
	ForgeItemManager.claim_single_item(item_id)
	show_message("Claimed %s!" % item.get("item_name", "item"), Color(0.5, 0.9, 0.5))

	# Play sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

	# Refresh display
	populate_forge()
	update_forge_tab_indicator()

func _on_forge_refresh_pressed() -> void:
	"""Handle refresh button press"""
	_play_click_sound()
	if ForgeItemManager:
		_update_forge_status("Refreshing...")
		ForgeItemManager.fetch_forged_items()

func _on_forged_items_loaded(_items: Array) -> void:
	"""Handle forged items loaded from backend"""
	if visible:
		populate_forge()
		update_forge_tab_indicator()

func _on_forge_item_claimed(_item: Dictionary) -> void:
	"""Handle a forge item being claimed"""
	if visible:
		populate_forge()
		update_forge_tab_indicator()

func _on_forge_item_synced(_item: Dictionary) -> void:
	"""Handle a forge item being synced to inventory"""
	if visible:
		populate_forge()
		update_forge_tab_indicator()

func _update_forge_status(text: String) -> void:
	"""Update the forge status label"""
	if forge_status_label:
		forge_status_label.text = text

func update_forge_tab_indicator() -> void:
	"""Update the Forge tab title with indicator for unclaimed items"""
	if not tab_container:
		return

	# Find the Forge tab index
	var forge_tab_idx = -1
	for i in range(tab_container.get_tab_count()):
		var title = tab_container.get_tab_title(i)
		if title.begins_with("Forge"):
			forge_tab_idx = i
			break

	if forge_tab_idx == -1:
		return

	# Count unclaimed items
	var unclaimed_count = 0
	if ForgeItemManager:
		var forged_items = ForgeItemManager.get_all_forged_items()
		for item in forged_items:
			if not item.get("claimed_in_game", false):
				unclaimed_count += 1

	# Update tab title
	var tab_title = "Forge"
	if unclaimed_count > 0:
		tab_title = "Forge (%d)" % unclaimed_count

	tab_container.set_tab_title(forge_tab_idx, tab_title)

func _play_click_sound() -> void:
	"""Play button click sound"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()
