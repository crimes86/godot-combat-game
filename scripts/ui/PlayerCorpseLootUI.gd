extends CanvasLayer
class_name PlayerCorpseLootUI

## Player Corpse Loot UI - Simple 2-column grid with pagination

signal loot_ui_closed()

var current_corpse: PlayerCorpse = null

# All items combined (equipped + inventory)
var all_items: Array = []  # Array of {item: Dictionary, type: String, slot: String, index: int}
var current_page: int = 0
const ITEMS_PER_PAGE = 16  # 2 columns x 8 rows
const GRID_COLUMNS = 2

# UI Style
const SLOT_SIZE = Vector2(48, 48)
const ICON_SIZE = Vector2(32, 32)
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)
const LOOT_RANGE = 150.0  # Max distance to loot corpses

# Dynamic UI elements
var panel: PanelContainer
var title_label: Label
var items_grid: GridContainer
var gold_label: Label
var page_label: Label
var prev_button: Button
var next_button: Button
var take_all_button: Button
var close_button: Button

func _ready() -> void:
	_build_ui()
	hide()

func _process(_delta: float) -> void:
	"""Check if player is still in range of corpse"""
	if not visible or not current_corpse:
		return

	# Get player position
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Check distance to corpse
	if is_instance_valid(current_corpse):
		var distance = player.global_position.distance_to(current_corpse.global_position)
		if distance > LOOT_RANGE:
			close_ui()

func _build_ui() -> void:
	"""Build the UI programmatically"""
	# Main panel - sized to fit 2 columns snugly
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -70
	panel.offset_right = 70
	panel.offset_top = -200
	panel.offset_bottom = 200
	add_child(panel)
	_apply_panel_style()

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header with title and close button
	var header = HBoxContainer.new()
	vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "YOUR CORPSE"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Items grid
	items_grid = GridContainer.new()
	items_grid.columns = GRID_COLUMNS
	items_grid.add_theme_constant_override("h_separation", 4)
	items_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(items_grid)

	# Gold display (clickable)
	var gold_button = Button.new()
	gold_button.flat = true
	gold_button.mouse_filter = Control.MOUSE_FILTER_STOP
	gold_button.pressed.connect(_on_gold_clicked)
	vbox.add_child(gold_button)

	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 12)
	gold_label.add_theme_color_override("font_color", Color(1, 0.85, 0))
	gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_button.add_child(gold_label)

	# Page controls
	var page_row = HBoxContainer.new()
	page_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(page_row)

	prev_button = Button.new()
	prev_button.text = "<"
	prev_button.add_theme_font_size_override("font_size", 10)
	prev_button.pressed.connect(_on_prev_page)
	page_row.add_child(prev_button)

	page_label = Label.new()
	page_label.text = "1/1"
	page_label.add_theme_font_size_override("font_size", 10)
	page_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	page_row.add_child(page_label)

	next_button = Button.new()
	next_button.text = ">"
	next_button.add_theme_font_size_override("font_size", 10)
	next_button.pressed.connect(_on_next_page)
	page_row.add_child(next_button)

	# Take All button
	take_all_button = Button.new()
	take_all_button.text = "Take All [F]"
	take_all_button.add_theme_font_size_override("font_size", 10)
	take_all_button.pressed.connect(_on_take_all_pressed)
	vbox.add_child(take_all_button)

func _apply_panel_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_on_take_all_pressed()
			get_viewport().set_input_as_handled()

func open_corpse_ui(corpse: PlayerCorpse) -> void:
	current_corpse = corpse
	current_page = 0
	_gather_all_items()
	_populate_grid()
	show()

	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.CORPSE_LOOT, -10.0)

func close_ui() -> void:
	hide()
	loot_ui_closed.emit()
	if current_corpse:
		current_corpse.loot_ui_open = false
	current_corpse = null

func _gather_all_items() -> void:
	"""Gather all items from corpse into a single list, stacking stackable items"""
	all_items.clear()
	if not current_corpse:
		return

	var loot = current_corpse.get_all_loot()

	# Add equipped armor
	for slot in ["head", "chest", "hands", "legs", "feet"]:
		if loot.equipped_armor.has(slot) and loot.equipped_armor[slot]:
			all_items.append({
				"item": loot.equipped_armor[slot],
				"type": "armor",
				"slot": slot,
				"index": -1,
				"indices": []  # Not used for equipped items
			})

	# Add weapon
	if not loot.equipped_weapon.is_empty():
		all_items.append({
			"item": loot.equipped_weapon,
			"type": "weapon",
			"slot": "mainhand",
			"index": -1,
			"indices": []  # Not used for equipped items
		})

	# Stack inventory items by name if stackable
	var stacked_items = {}  # item_name -> {item, indices, total_qty}

	for i in range(loot.inventory.size()):
		if not loot.inventory[i]:
			continue

		var item = loot.inventory[i]
		var item_name = item.get("name", "")
		var is_stackable = item.get("stackable", false)
		var quantity = item.get("quantity", 1)

		if is_stackable and stacked_items.has(item_name):
			# Add to existing stack
			stacked_items[item_name]["indices"].append(i)
			stacked_items[item_name]["total_qty"] += quantity
		else:
			# New stack or non-stackable item
			var key = item_name if is_stackable else "%s_%d" % [item_name, i]
			stacked_items[key] = {
				"item": item.duplicate(),
				"indices": [i],
				"total_qty": quantity
			}

	# Convert stacked items to all_items entries
	for key in stacked_items:
		var stack_data = stacked_items[key]
		var item = stack_data["item"]
		var indices = stack_data["indices"]
		var total_qty = stack_data["total_qty"]

		# Update item quantity to reflect total
		item["quantity"] = total_qty

		all_items.append({
			"item": item,
			"type": "inventory",
			"slot": "",
			"index": indices[0],  # Primary index for first item
			"indices": indices  # All indices for stacked items
		})

func _populate_grid() -> void:
	"""Populate the grid with current page items"""
	# Clear grid
	for child in items_grid.get_children():
		child.queue_free()

	# Calculate pagination
	var total_pages = max(1, ceili(float(all_items.size()) / ITEMS_PER_PAGE))
	current_page = clamp(current_page, 0, total_pages - 1)

	var start_idx = current_page * ITEMS_PER_PAGE
	var end_idx = min(start_idx + ITEMS_PER_PAGE, all_items.size())

	# Add item slots for this page
	for i in range(start_idx, end_idx):
		var entry = all_items[i]
		var slot = _create_item_slot(entry)
		items_grid.add_child(slot)

	# Update gold
	if current_corpse:
		var loot = current_corpse.get_all_loot()
		if loot.gold > 0:
			gold_label.text = "Gold: %d (click to take)" % loot.gold
			gold_label.get_parent().visible = true
		else:
			gold_label.get_parent().visible = false

	# Update page controls
	page_label.text = "%d/%d" % [current_page + 1, total_pages]
	prev_button.visible = total_pages > 1
	next_button.visible = total_pages > 1
	page_label.visible = total_pages > 1
	prev_button.disabled = current_page == 0
	next_button.disabled = current_page >= total_pages - 1

func _create_item_slot(entry: Dictionary) -> Control:
	"""Create a slot for an item"""
	var item = entry.item
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_control.set_meta("entry", entry)

	var rarity = item.get("rarity", "Common")
	var rarity_color = _get_rarity_color(rarity)

	# Background panel
	var bg = PanelContainer.new()
	bg.custom_minimum_size = SLOT_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(bg)

	var style = StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_color = rarity_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	bg.add_theme_stylebox_override("panel", style)

	# Center container
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)

	# Item icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.size = ICON_SIZE  # Force size to 32x32
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ItemIconGenerator:
		var icon_texture = ItemIconGenerator.get_item_icon(item)
		if icon_texture:
			icon.texture = icon_texture

	center.add_child(icon)

	# Add stack quantity label if stackable and qty > 1
	var quantity = item.get("quantity", 1)
	var is_stackable = item.get("stackable", false)
	if is_stackable and quantity > 1:
		var stack_label = Label.new()
		stack_label.name = "StackLabel"
		stack_label.text = "x%d" % quantity
		stack_label.add_theme_font_size_override("font_size", 11)
		stack_label.add_theme_color_override("font_color", Color.WHITE)
		stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
		stack_label.add_theme_constant_override("outline_size", 2)
		stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stack_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		stack_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		stack_label.offset_left = -32
		stack_label.offset_right = -2
		stack_label.offset_top = 2  # Inside slot, top corner
		stack_label.offset_bottom = 14
		bg.add_child(stack_label)

	# Tooltip with control hints
	var item_name = item.get("name", "Unknown")
	var type_str = entry.slot.capitalize() if entry.slot != "" else "Item"
	var is_equippable = entry.type == "armor" or entry.type == "weapon" or item.get("item_type", "") == "tool" or item.has("slot") or item.has("weapon_type")

	var tooltip_qty_text = ""
	if is_stackable and quantity > 1:
		tooltip_qty_text = "\nQuantity: %d" % quantity

	if is_equippable:
		slot_control.tooltip_text = "[%s] %s\n%s%s\nLeft-click: Take | Right-click: Equip" % [rarity, item_name, type_str, tooltip_qty_text]
	else:
		slot_control.tooltip_text = "[%s] %s\n%s%s\nClick to take" % [rarity, item_name, type_str, tooltip_qty_text]

	# Click handler
	slot_control.gui_input.connect(_on_slot_input.bind(slot_control))

	return slot_control

func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_upper():
		"COMMON": return Color(0.5, 0.5, 0.5)
		"UNCOMMON": return Color(0.4, 0.8, 0.4)
		"RARE": return Color(0.4, 0.5, 0.9)
		"EPIC": return Color(0.7, 0.4, 0.9)
		"LEGENDARY": return Color(0.9, 0.6, 0.2)
		_: return Color(0.3, 0.3, 0.3)

func _on_slot_input(event: InputEvent, slot: Control) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	var entry = slot.get_meta("entry")
	var item = entry.item

	# Check if item is equippable (armor, weapon, or tool)
	var is_equippable = entry.type == "armor" or entry.type == "weapon" or item.get("item_type", "") == "tool"

	if event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: Equip if equippable, otherwise take to inventory
		if is_equippable:
			_equip_item(entry)
		else:
			_take_item(entry)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			# Double left-click: Take to inventory
			_take_item(entry)
		else:
			# Single left-click: Take to inventory (for non-equippables) or just take
			_take_item(entry)

func _take_item(entry: Dictionary) -> void:
	if not current_corpse:
		return

	match entry.type:
		"armor":
			if not InventorySystem.has_space():
				_show_notification("Inventory full!")
				return
			var taken_item = current_corpse.remove_equipped_armor(entry.slot)
			if not taken_item.is_empty():
				InventorySystem.add_item(taken_item)
				_show_notification("Took %s" % taken_item.get("name", "item"))

		"weapon":
			if not InventorySystem.has_space():
				_show_notification("Inventory full!")
				return
			var taken_item = current_corpse.remove_weapon()
			if not taken_item.is_empty():
				InventorySystem.add_item(taken_item)
				_show_notification("Took %s" % taken_item.get("name", "item"))

		"inventory":
			# For stacked items, take all items in the stack
			var indices = entry.get("indices", [entry.index])
			var item_name = entry.item.get("name", "item")
			var total_quantity = entry.item.get("quantity", 1)

			# Check if we have space for at least one
			if not InventorySystem.has_space():
				_show_notification("Inventory full!")
				return

			# Take all items in the stack (sorted in reverse to maintain indices)
			indices.sort()
			indices.reverse()
			var taken_any = false

			for idx in indices:
				var taken_item = current_corpse.remove_inventory_item(idx)
				if not taken_item.is_empty():
					InventorySystem.add_item(taken_item)
					taken_any = true

			if taken_any:
				if total_quantity > 1:
					_show_notification("Took %s x%d" % [item_name, total_quantity])
				else:
					_show_notification("Took %s" % item_name)

	_gather_all_items()
	_populate_grid()

	# Check if corpse is empty and close UI
	if current_corpse and current_corpse._is_empty():
		await get_tree().create_timer(0.3).timeout
		close_ui()

func _equip_item(entry: Dictionary) -> void:
	"""Directly equip an item from the corpse"""
	if not current_corpse:
		return

	var item = entry.item

	match entry.type:
		"armor":
			var taken_item = current_corpse.remove_equipped_armor(entry.slot)
			if not taken_item.is_empty():
				CharacterStats.equip_armor(taken_item)
				_show_notification("Equipped %s" % taken_item.get("name", "item"))

		"weapon":
			var weapon_dict = current_corpse.remove_weapon()
			if not weapon_dict.is_empty():
				var weapon = _dict_to_weapon(weapon_dict)
				if weapon:
					CharacterStats.equip_weapon(weapon, weapon_dict)  # Pass item data for forged metadata
					_show_notification("Equipped %s" % weapon_dict.get("name", "weapon"))

		"inventory":
			# Check if it's a tool or equippable from inventory
			var item_type = item.get("item_type", "")
			if item_type == "tool":
				# Tools go to inventory, player can equip from there
				if InventorySystem.has_space():
					var taken_item = current_corpse.remove_inventory_item(entry.index)
					if not taken_item.is_empty():
						InventorySystem.add_item(taken_item)
						_show_notification("Took %s" % taken_item.get("name", "item"))
			elif item.has("slot"):
				# It's armor in inventory
				if InventorySystem.has_space():
					var taken_item = current_corpse.remove_inventory_item(entry.index)
					if not taken_item.is_empty():
						CharacterStats.equip_armor(taken_item)
						_show_notification("Equipped %s" % taken_item.get("name", "item"))
			elif item.has("weapon_type"):
				# It's a weapon in inventory
				var taken_item = current_corpse.remove_inventory_item(entry.index)
				if not taken_item.is_empty():
					var weapon = _dict_to_weapon(taken_item)
					if weapon:
						CharacterStats.equip_weapon(weapon, taken_item)  # Pass item data for forged metadata
						_show_notification("Equipped %s" % taken_item.get("name", "weapon"))

	_gather_all_items()
	_populate_grid()

	if current_corpse._is_empty():
		await get_tree().create_timer(0.3).timeout
		close_ui()

func _on_gold_clicked() -> void:
	if not current_corpse:
		return

	var gold = current_corpse.take_gold()
	if gold > 0:
		CharacterStats.add_gold(gold)
		_show_notification("Took %d gold" % gold)
		_populate_grid()

		if current_corpse._is_empty():
			await get_tree().create_timer(0.3).timeout
			close_ui()

func _on_prev_page() -> void:
	if current_page > 0:
		current_page -= 1
		_populate_grid()

func _on_next_page() -> void:
	var total_pages = max(1, ceili(float(all_items.size()) / ITEMS_PER_PAGE))
	if current_page < total_pages - 1:
		current_page += 1
		_populate_grid()

func _on_take_all_pressed() -> void:
	if not current_corpse:
		return

	var items_taken = 0

	# Take gold
	var gold = current_corpse.take_gold()
	if gold > 0:
		CharacterStats.add_gold(gold)
		items_taken += 1

	# Take all items
	var loot = current_corpse.get_all_loot()

	for i in range(loot.inventory.size()):
		if loot.inventory[i] and InventorySystem.has_space():
			var item = current_corpse.remove_inventory_item(i)
			if not item.is_empty():
				InventorySystem.add_item(item)
				items_taken += 1

	for slot in loot.equipped_armor:
		if loot.equipped_armor[slot] and InventorySystem.has_space():
			var item = current_corpse.remove_equipped_armor(slot)
			if not item.is_empty():
				InventorySystem.add_item(item)
				items_taken += 1

	if not loot.equipped_weapon.is_empty() and InventorySystem.has_space():
		var weapon = current_corpse.remove_weapon()
		if not weapon.is_empty():
			InventorySystem.add_item(weapon)
			items_taken += 1

	if items_taken > 0:
		_show_notification("Took %d items" % items_taken)

	_gather_all_items()
	_populate_grid()

	if current_corpse._is_empty():
		await get_tree().create_timer(0.3).timeout
		close_ui()

func _dict_to_weapon(weapon_dict: Dictionary):
	if weapon_dict.is_empty():
		return null

	var Weapon = load("res://scripts/resources/Weapon.gd")
	var weapon = Weapon.new()
	weapon.weapon_name = weapon_dict.get("name", "Unknown")
	weapon.description = weapon_dict.get("description", "")
	weapon.weapon_type = weapon_dict.get("weapon_type", "sword")

	# Handle base_damage - can be a number or a Dictionary with min/max
	var base_damage = weapon_dict.get("base_damage", 5.0)
	if base_damage is Dictionary:
		var dmg_min = base_damage.get("min", 5)
		var dmg_max = base_damage.get("max", 5)
		weapon.base_damage = (dmg_min + dmg_max) / 2.0
	elif base_damage is float or base_damage is int:
		weapon.base_damage = float(base_damage)
	else:
		weapon.base_damage = 5.0

	weapon.attack_speed_bonus = weapon_dict.get("attack_speed_bonus", 0.0)
	weapon.crit_chance_bonus = weapon_dict.get("crit_chance_bonus", 0.0)
	weapon.required_level = weapon_dict.get("required_level", 1)
	weapon.sell_value = weapon_dict.get("value", 0)
	weapon.can_trade = weapon_dict.get("can_trade", true)

	var rarity_str = weapon_dict.get("rarity", "COMMON")
	match rarity_str.to_upper():
		"COMMON": weapon.rarity = Weapon.Rarity.COMMON
		"UNCOMMON": weapon.rarity = Weapon.Rarity.UNCOMMON
		"RARE": weapon.rarity = Weapon.Rarity.RARE
		"EPIC": weapon.rarity = Weapon.Rarity.EPIC
		"LEGENDARY": weapon.rarity = Weapon.Rarity.LEGENDARY

	if weapon_dict.has("attack_mode"):
		weapon.attack_mode = weapon_dict.get("attack_mode", "melee")
		weapon.healing_power = weapon_dict.get("healing_power", 0.0)
		weapon.heal_radius = weapon_dict.get("heal_radius", 0.0)

	# Gun weapon properties (use explicit null checks since .get() returns null if key exists with null value)
	weapon.gun_radius = weapon_dict.get("gun_radius") if weapon_dict.get("gun_radius") != null else 28.0
	weapon.gun_range = weapon_dict.get("gun_range") if weapon_dict.get("gun_range") != null else 550.0
	weapon.gun_subtype = weapon_dict.get("gun_subtype") if weapon_dict.get("gun_subtype") != null else "railgun"
	weapon.burst_count = weapon_dict.get("burst_count") if weapon_dict.get("burst_count") != null else 1
	weapon.burst_delay = weapon_dict.get("burst_delay") if weapon_dict.get("burst_delay") != null else 0.10

	# Two-handed property - guns and bows are always two-handed (blocks offhand slot)
	var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
	weapon.is_two_handed = weapon_dict.get("is_two_handed", is_two_handed_type)

	return weapon

func _on_close_pressed() -> void:
	close_ui()

func _show_notification(message: String) -> void:
	var notification_mgr = get_node_or_null("/root/NotificationManager")
	if notification_mgr and notification_mgr.has_method("show_notification"):
		notification_mgr.show_notification(message)
