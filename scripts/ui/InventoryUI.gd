extends CanvasLayer

## Inventory UI - Standalone inventory window
## Stone Gray UI theme matching CharacterUI
## Press I to toggle

var is_visible: bool = false

# Pending deletion data (for confirmation dialog)
var pending_delete_data: Dictionary = {}

# UI References
var main_panel: PanelContainer
var inventory_slots: Array[Control] = []
var gold_label: Label

# Stone Gray UI Palette (matching CharacterUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.75)  # Dark stone gray (transparent for combat)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)  # Light steel accent
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)  # Silver headers
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)  # Dark stone inset

func _ready() -> void:
	# Set layer above game prompts (campfire hints are at 100)
	# Use layer 105 so inventory can coexist with shop UI which may use similar layers
	layer = 105

	# Add to group for tutorial system to find
	add_to_group("inventory_ui")

	# Start hidden
	visible = false

	# Create UI
	create_inventory_ui()

	# Connect to signals
	CharacterStats.gold_changed.connect(_on_gold_changed)
	InventorySystem.inventory_changed.connect(_on_inventory_changed)

	# Initial update
	refresh_all()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_visible:
			toggle_ui()
			get_viewport().set_input_as_handled()

func create_inventory_ui() -> void:
	"""Create standalone inventory window"""

	# NOTE: We no longer use a full-screen drop zone as it blocks input to other UIs
	# (like ShopUI) due to CanvasLayer input priority. Instead, we handle item deletion
	# by detecting drops outside the inventory panel directly on the panel itself.

	# Create confirmation dialog for deletion
	var delete_dialog = ConfirmationDialog.new()
	delete_dialog.name = "DeleteConfirmDialog"
	delete_dialog.title = "Delete Item"
	delete_dialog.dialog_text = "Are you sure you want to delete this item?"
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(delete_dialog)

	# Main panel container - positioned at bottom-right corner
	main_panel = PanelContainer.new()
	main_panel.name = "InventoryPanel"

	# Position at bottom-right - use custom_minimum_size and anchor to bottom-right
	# The panel will grow upward from the bottom-right corner
	main_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow left from right edge
	main_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN    # Grow up from bottom edge
	main_panel.anchor_left = 1.0
	main_panel.anchor_top = 1.0
	main_panel.anchor_right = 1.0
	main_panel.anchor_bottom = 1.0
	# Position from bottom-right corner with padding
	main_panel.offset_left = -270
	main_panel.offset_right = -10
	main_panel.offset_top = 0   # Will be determined by content size + grow direction
	main_panel.offset_bottom = -10  # 10px from bottom edge

	# Dark Fantasy Wasteland styling with transparency
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_offset = Vector2(0, 4)

	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Main layout with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	main_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Inventory grid (4 columns) - no inner panel, just the grid
	var inv_grid = GridContainer.new()
	inv_grid.columns = 4
	inv_grid.add_theme_constant_override("h_separation", 4)
	inv_grid.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(inv_grid)

	# Create inventory slots
	for i in range(InventorySystem.MAX_INVENTORY_SLOTS):
		var slot_button = create_inventory_slot(i)
		inv_grid.add_child(slot_button)
		inventory_slots.append(slot_button)

	# Gold display at bottom - just icon and number
	var gold_container = HBoxContainer.new()
	gold_container.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_container.add_theme_constant_override("separation", 4)
	main_vbox.add_child(gold_container)

	var gold_icon = TextureRect.new()
	gold_icon.texture = preload("res://assets/icons/gold_coins.png")
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.custom_minimum_size = Vector2(16, 16)
	gold_container.add_child(gold_icon)

	gold_label = create_text_label("0", 16)
	gold_label.add_theme_color_override("font_color", HEADER_COLOR)
	gold_container.add_child(gold_label)

	add_child(main_panel)

func create_inventory_slot(slot_index: int) -> Control:
	"""Create a single inventory slot button with drag-drop support"""
	var slot_control = Control.new()
	slot_control.name = "InvSlot_" + str(slot_index)
	slot_control.custom_minimum_size = Vector2(56, 56)
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we receive input
	slot_control.set_meta("slot_index", slot_index)
	slot_control.set_meta("slot_type", "inventory")

	# Enable drag-drop
	slot_control.set_drag_forwarding(
		Callable(self, "_get_inventory_drag_data").bind(slot_index),
		Callable(self, "_can_drop_inventory_data").bind(slot_index),
		Callable(self, "_drop_inventory_data").bind(slot_index)
	)

	# Add panel for styling
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(56, 56)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# Add icon texture rect (scaled to fit)
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false  # Hidden until we have an icon
	center.add_child(icon)

	# Add label for item text (fallback when no icon)
	var label = Label.new()
	label.name = "ItemLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(label)

	# Stack count label (bottom-right corner)
	var stack_label = Label.new()
	stack_label.name = "StackLabel"
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", 10)
	stack_label.add_theme_color_override("font_color", Color.WHITE)
	stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stack_label.add_theme_constant_override("outline_size", 2)
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stack_label.offset_left = -30
	stack_label.offset_top = -16
	stack_label.offset_right = -2
	stack_label.offset_bottom = -2
	stack_label.visible = false
	panel.add_child(stack_label)

	# Connect click event
	slot_control.gui_input.connect(_on_inventory_slot_gui_input.bind(slot_index))

	return slot_control

func create_header_label(text: String, size: int = 18) -> Label:
	"""Create a header label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", HEADER_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func create_text_label(text: String, size: int = 14) -> Label:
	"""Create a standard text label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label

func create_styled_separator() -> Control:
	"""Create a styled separator line"""
	var separator_container = MarginContainer.new()
	separator_container.add_theme_constant_override("margin_top", 8)
	separator_container.add_theme_constant_override("margin_bottom", 8)
	separator_container.add_theme_constant_override("margin_left", 20)
	separator_container.add_theme_constant_override("margin_right", 20)

	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 2)

	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = BORDER_COLOR
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", sep_style)

	separator_container.add_child(separator)
	return separator_container

func create_slot_style(bg_color: Color, border_color: Color = BORDER_COLOR, border_width: int = 2, use_glow: bool = false) -> StyleBoxFlat:
	"""Create style for inventory slots"""
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	if use_glow and border_color != BORDER_INNER:
		style.shadow_size = 3
		style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.3)
	else:
		style.shadow_size = 3
		style.shadow_color = BORDER_INNER

	return style

func create_inner_panel_style() -> StyleBoxFlat:
	"""Create style for inner panels"""
	var style = StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = BORDER_INNER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_size = 4
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func get_rarity_glow_color(rarity_str: String) -> Color:
	"""Get glow color for item rarity"""
	match rarity_str.to_upper():
		"COMMON":
			return Color(0.6, 0.6, 0.6, 0.9)
		"UNCOMMON":
			return Color(0.4, 0.8, 0.4, 1.0)
		"RARE":
			return Color(0.4, 0.5, 0.9, 1.0)
		"EPIC":
			return Color(0.7, 0.4, 0.9, 1.0)
		"LEGENDARY":
			return Color(0.9, 0.6, 0.2, 1.0)
		"ARTIFACT":
			return Color(0.9, 0.8, 0.3, 1.0)
		_:
			return BORDER_INNER

func toggle_ui() -> void:
	"""Toggle inventory UI visibility"""
	is_visible = !is_visible
	visible = is_visible

	# Play inventory open/close sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_inventory_open_sound()

	if is_visible:
		refresh_all()
		# Notify tutorial system
		if TutorialManager:
			TutorialManager.on_inventory_opened()
	else:
		# Notify tutorial system inventory closed
		if TutorialManager:
			TutorialManager.on_inventory_closed()

func refresh_all() -> void:
	"""Refresh all UI elements"""
	refresh_inventory()
	refresh_gold()

func refresh_gold() -> void:
	"""Update gold display"""
	if gold_label:
		gold_label.text = "%d" % CharacterStats.gold

func refresh_inventory() -> void:
	"""Update inventory slot displays"""
	for i in range(inventory_slots.size()):
		var slot_control = inventory_slots[i]
		var item = InventorySystem.get_item(i)

		var panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			continue

		# Get icon, label, and stack label nodes
		var icon_rect: TextureRect = null
		var label: Label = null
		var stack_label: Label = null

		# Try new structure: Panel > CenterContainer > ItemIcon/ItemLabel
		var center = panel.get_node_or_null("CenterContainer")
		if center:
			icon_rect = center.get_node_or_null("ItemIcon")
			label = center.get_node_or_null("ItemLabel")

		# Stack label is directly under panel
		stack_label = panel.get_node_or_null("StackLabel")

		# Fallback: search recursively
		if not label:
			label = _find_node_recursive(panel, "ItemLabel")
		if not icon_rect:
			icon_rect = _find_node_recursive(panel, "ItemIcon")
		if not stack_label:
			stack_label = _find_node_recursive(panel, "StackLabel")

		if not label:
			print("⚠️ InventoryUI: Could not find ItemLabel in slot %d" % i)
			continue

		if item and item.size() > 0:
			var item_name = item.get("name", "???")
			var quantity = item.get("quantity", 1)
			var is_stackable = item.get("stackable", false)

			# Try to get icon from ItemIconGenerator
			var icon_texture: Texture2D = null
			if ItemIconGenerator:
				icon_texture = ItemIconGenerator.get_item_icon(item)

			if icon_texture and icon_rect:
				# We have an icon - show it
				icon_rect.texture = icon_texture
				icon_rect.visible = true
				label.visible = false
				label.text = ""
				# Show stack count in bottom-right corner
				if stack_label:
					if is_stackable and quantity > 1:
						stack_label.visible = true
						stack_label.text = "x%d" % quantity
					else:
						stack_label.visible = false
						stack_label.text = ""
			else:
				# No icon - show text name
				if icon_rect:
					icon_rect.visible = false
				label.visible = true
				if is_stackable and quantity > 1:
					label.text = "%s\nx%d" % [item_name, quantity]
				else:
					label.text = item_name
				if stack_label:
					stack_label.visible = false

			var rarity = item.get("rarity", "COMMON")
			var glow_color = get_rarity_glow_color(rarity)
			var glow_style = create_slot_style(SLOT_BG, glow_color, 3, true)
			panel.add_theme_stylebox_override("panel", glow_style)

			# Build tooltip with item name first
			var tooltip = "[%s]\n" % item_name
			var desc = item.get("description", "")
			if desc:
				tooltip += desc

			if item.get("type") == "weapon":
				if item.has("base_damage"):
					tooltip += "\nDamage: +%.1f" % item.get("base_damage", 0)
				if item.has("attack_speed_bonus"):
					var speed_bonus = item.get("attack_speed_bonus", 0.0)
					if speed_bonus != 0:
						tooltip += "\nAttack Speed: %+.1f%%" % (speed_bonus * 100)
				if item.has("crit_chance_bonus"):
					var crit_bonus = item.get("crit_chance_bonus", 0.0)
					if crit_bonus != 0:
						tooltip += "\nCrit Chance: +%.1f%%" % (crit_bonus * 100)

			if item.has("defense"):
				tooltip += "\nDefense: +%d" % item.get("defense", 0)

			if item.has("value"):
				tooltip += "\nValue: %d G" % item.get("value", 0)

			slot_control.tooltip_text = tooltip
		else:
			# Empty slot
			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false
			if stack_label:
				stack_label.visible = false
			label.visible = false
			label.text = ""
			slot_control.tooltip_text = "Empty slot"
			var default_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
			panel.add_theme_stylebox_override("panel", default_style)

func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	"""Handle GUI input on inventory slot (double-click or right-click to equip)"""
	if event is InputEventMouseButton and event.pressed:
		print("🖱️ Inventory slot %d clicked - button: %d, double_click: %s" % [slot_index, event.button_index, event.double_click])
		if (event.button_index == MOUSE_BUTTON_LEFT and event.double_click) or event.button_index == MOUSE_BUTTON_RIGHT:
			var item = InventorySystem.get_item(slot_index)
			print("   Item in slot: %s" % (item if item else "empty"))

			if item and item.size() > 0:
				print("   Item type: '%s', slot: '%s'" % [item.get("type", ""), item.get("slot", "")])
				# Check if it's a tool
				if item.get("type", "") == "tool":
					var tool_type = item.get("tool_type", "")
					var equipped = false

					if tool_type == "axe":
						equipped = InventorySystem.equip_axe(item)
					elif tool_type == "pickaxe":
						equipped = InventorySystem.equip_pickaxe(item)

					if equipped:
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
				# Check if it's a weapon
				elif item.get("type", "") == "weapon" and item.get("slot", "") == "mainhand":
					var weapon = dict_to_weapon(item)
					if weapon:
						# If there's already a weapon equipped, unequip it first
						if CharacterStats.equipped_weapon:
							print("⚔️ Swapping weapons - unequipping %s first" % CharacterStats.equipped_weapon.weapon_name)
							if not CharacterStats.unequip_weapon():
								print("❌ Cannot swap weapons - inventory full!")
								return
						CharacterStats.equip_weapon(weapon)
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
						# Notify tutorial system
						if TutorialManager:
							TutorialManager.on_item_equipped(item)
				# Check if it's armor
				elif item.has("slot") and item.get("slot", "") in CharacterStats.equipped_armor:
					if CharacterStats.equip_armor(item):
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
						# Notify tutorial system
						if TutorialManager:
							TutorialManager.on_item_equipped(item)

func dict_to_weapon(item_dict: Dictionary) -> Weapon:
	"""Convert a weapon dictionary to a Weapon resource"""
	var weapon = Weapon.new()

	weapon.weapon_name = item_dict.get("name", "Unknown")
	weapon.weapon_type = item_dict.get("weapon_type", "sword")
	weapon.damage_type = "unified"
	weapon.description = item_dict.get("description", "")
	weapon.base_damage = item_dict.get("base_damage", 5.0)

	# Healing weapon properties
	weapon.attack_mode = item_dict.get("attack_mode", "melee")
	weapon.healing_power = item_dict.get("healing_power", 0.0)
	weapon.heal_radius = item_dict.get("heal_radius", 80.0)

	var attack_speed_category = item_dict.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30
		"slow":
			weapon.attack_speed_bonus = 0.30
		_:
			weapon.attack_speed_bonus = 0.0

	weapon.crit_chance_bonus = item_dict.get("crit_chance", 0.0)
	weapon.required_level = item_dict.get("required_level", 1)
	weapon.can_trade = item_dict.get("can_trade", true)

	var rarity_str = item_dict.get("rarity", "COMMON").to_upper()
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

# ============================================
# DRAG AND DROP FUNCTIONS
# ============================================

func _get_inventory_drag_data(at_position: Vector2, slot_index: int) -> Variant:
	"""Start dragging an inventory item"""
	print("🎯 _get_inventory_drag_data called for slot %d" % slot_index)
	var item = InventorySystem.get_item(slot_index)
	if not item or item.is_empty():
		print("   No item in slot, returning null")
		_current_drag_data = null
		return null

	print("   Starting drag for: %s" % item.get("name", "Unknown"))
	var preview = Label.new()
	preview.text = item.get("name", "Item")
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color.GOLD)
	preview.modulate = Color(1, 1, 1, 0.8)

	var slot_control = inventory_slots[slot_index]
	slot_control.set_drag_preview(preview)

	var drag_data = {
		"source_type": "inventory",
		"source_index": slot_index,
		"item": item,
		"source_ui": "inventory_ui"
	}

	# Store for deletion detection when drag ends
	_current_drag_data = drag_data

	return drag_data

func _can_drop_inventory_data(at_position: Vector2, data: Variant, slot_index: int) -> bool:
	"""Check if data can be dropped on this inventory slot"""
	if not data is Dictionary:
		return false
	return data.has("item")

func _drop_inventory_data(at_position: Vector2, data: Dictionary, slot_index: int) -> void:
	"""Handle dropping data on an inventory slot"""
	if not data.has("item"):
		return

	# Clear drag data since this is a valid drop
	_current_drag_data = null

	var source_type = data.get("source_type", "")
	var source_index = data.get("source_index", -1)
	var dragged_item = data.get("item", {})

	if source_type == "inventory":
		# Swap inventory items
		if source_index != slot_index:
			var target_item = InventorySystem.get_item(slot_index)

			InventorySystem.set_item(source_index, {})
			InventorySystem.set_item(slot_index, {})

			InventorySystem.set_item(slot_index, dragged_item)
			if target_item and not target_item.is_empty():
				InventorySystem.set_item(source_index, target_item)

			SoundManager.play_inventory_move_sound()
			refresh_all()

	elif source_type == "equipment":
		# Move from equipment to inventory
		var source_slot_name = data.get("source_slot_name", "")
		if source_slot_name:
			if source_slot_name == "mainhand" and CharacterStats.equipped_weapon:
				CharacterStats.unequip_weapon()
				SoundManager.play_equip_sound()
				refresh_all()
			elif CharacterStats.unequip_armor(source_slot_name):
				SoundManager.play_equip_sound()
				refresh_all()

	elif source_type == "tool":
		# Move from tool slot to inventory
		var source_tool_name = data.get("source_tool_name", "")
		if source_tool_name == "axe":
			InventorySystem.unequip_axe()
			SoundManager.play_equip_sound()
			refresh_all()
		elif source_tool_name == "pickaxe":
			InventorySystem.unequip_pickaxe()
			SoundManager.play_equip_sound()
			refresh_all()

# ============================================
# ITEM DELETION (DROP OUTSIDE PANEL)
# ============================================

# Track the current drag data for deletion detection
var _current_drag_data: Variant = null

func _notification(what: int) -> void:
	# Detect when drag ends to check if item was dropped outside panel
	if what == NOTIFICATION_DRAG_END:
		_on_drag_ended()

func _on_drag_ended() -> void:
	"""Called when any drag operation ends - check if we should delete an item"""
	if not is_visible or not _current_drag_data:
		_current_drag_data = null
		return

	var data = _current_drag_data
	_current_drag_data = null

	# Only handle inventory items from this UI
	if not data is Dictionary or not data.has("item"):
		return
	if data.get("source_ui") != "inventory_ui":
		return

	# Check if mouse is outside the inventory panel
	var mouse_pos = get_viewport().get_mouse_position()
	if main_panel:
		var panel_rect = main_panel.get_global_rect()
		if not panel_rect.has_point(mouse_pos):
			# Dropped outside - prompt for deletion
			_prompt_delete_item(data)

func _prompt_delete_item(data: Dictionary) -> void:
	"""Show confirmation dialog for item deletion"""
	pending_delete_data = data

	var item_name = data.get("item", {}).get("name", "Unknown")

	var dialog = get_node_or_null("DeleteConfirmDialog")
	if dialog:
		dialog.dialog_text = "Are you sure you want to delete '%s'?" % item_name
		dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if pending_delete_data.is_empty():
		return

	var source_type = pending_delete_data.get("source_type", "")
	var dragged_item = pending_delete_data.get("item", {})

	if source_type == "inventory":
		var source_index = pending_delete_data.get("source_index", -1)
		if source_index >= 0:
			InventorySystem.remove_item(source_index)
			refresh_all()

	pending_delete_data = {}

func _on_gold_changed(_amount: int, _total: int) -> void:
	refresh_gold()

func _on_inventory_changed() -> void:
	refresh_inventory()

func _find_node_recursive(parent: Node, node_name: String) -> Node:
	"""Recursively search for a node by name"""
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found = _find_node_recursive(child, node_name)
		if found:
			return found
	return null
