extends CanvasLayer
class_name HarvestLootUI

## Harvest Loot UI for trees and rocks
## Icon-based grid display matching ChestLootUI and LootBodyUI style

signal item_looted(item: Dictionary)
signal all_items_looted()
signal loot_ui_closed()

var harvest_loot: Array = []
var harvest_type: String = "Resource"  # "Wood" or "Ore"

# UI references
var panel: PanelContainer
var loot_grid: GridContainer
var take_all_button: Button
var close_button: Button
var title_label: Label

# UI Style constants (matching LootBodyUI/ChestLootUI)
const SLOT_SIZE = Vector2(52, 52)
const GRID_COLUMNS = 3
const MIN_SLOTS = 3

# UI colors - use UITheme singleton
var SLOT_BG: Color:
	get: return UITheme.SLOT_BG if UITheme else Color(0.08, 0.08, 0.1, 0.9)
var BORDER_INNER: Color:
	get: return UITheme.BORDER_INNER if UITheme else Color(0.2, 0.22, 0.25, 1.0)
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR if UITheme else Color(0.35, 0.38, 0.42, 1.0)

func _ready() -> void:
	layer = 100  # Above game world
	create_ui()
	hide()

func create_ui() -> void:
	"""Create the harvest loot UI programmatically (matching ChestLootUI structure)"""
	# Main panel - positioned on right side of screen
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 0.75
	panel.anchor_top = 0.5
	panel.anchor_right = 0.75
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	# Style the panel (stone gray theme)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)  # Dark stone gray
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.38, 0.42)  # Steel gray border
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	# Vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header with title and close button
	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(header)

	# Title label (left side, will be set dynamically)
	title_label = Label.new()
	title_label.text = "Harvest"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	# Close button
	close_button = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 16)
	close_button.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
	close_button.add_theme_color_override("font_hover_color", Color(1, 0.3, 0.3))
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Loot grid
	loot_grid = GridContainer.new()
	loot_grid.columns = GRID_COLUMNS
	loot_grid.add_theme_constant_override("h_separation", 4)
	loot_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(loot_grid)

	# Button container
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)

	# Take All button
	take_all_button = Button.new()
	take_all_button.text = "Take All [F]"
	take_all_button.add_theme_font_size_override("font_size", 12)
	take_all_button.pressed.connect(_on_take_all_pressed)
	button_container.add_child(take_all_button)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_on_take_all_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()

func open_harvest_ui(loot_items: Array, type: String) -> void:
	"""Open the harvest loot UI with items"""
	harvest_loot = loot_items.duplicate()
	harvest_type = type

	# Set title based on type
	if title_label:
		title_label.text = type

	populate_loot_grid()
	show()

func populate_loot_grid() -> void:
	"""Populate the loot grid with icon slots"""
	if not loot_grid:
		return

	# Clear existing items
	for child in loot_grid.get_children():
		child.queue_free()

	var total_slots = 0

	# Add loot items as icon slots
	for i in range(harvest_loot.size()):
		var item = harvest_loot[i]
		if item:  # Skip null items (already looted)
			var slot = create_loot_slot(item, i)
			loot_grid.add_child(slot)
			total_slots += 1

	# Add empty slots to reach minimum
	while total_slots < MIN_SLOTS:
		var empty_slot = create_empty_slot()
		loot_grid.add_child(empty_slot)
		total_slots += 1

	# Update take all button state
	var actual_loot_count = harvest_loot.filter(func(item): return item != null).size()
	if take_all_button:
		take_all_button.disabled = (actual_loot_count == 0)

	# If everything was looted, close after brief delay
	if actual_loot_count == 0:
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(self):
			close_ui()

func create_loot_slot(item: Dictionary, index: int) -> Control:
	"""Create an icon-based slot for a loot item (click to loot)"""
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP

	# Store item data and index
	slot_control.set_meta("item_data", item)
	slot_control.set_meta("item_index", index)

	# Get rarity for border color
	var rarity = item.get("rarity", "COMMON")
	var rarity_color = get_rarity_color(rarity)

	# Add panel for styling with rarity glow
	var panel_slot = PanelContainer.new()
	panel_slot.custom_minimum_size = SLOT_SIZE
	panel_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel_slot)

	var slot_style = create_slot_style(SLOT_BG, rarity_color, 3, true)
	panel_slot.add_theme_stylebox_override("panel", slot_style)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_slot.add_child(center)

	# Add icon texture rect
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)

	# Try to get icon from ItemIconGenerator
	if ItemIconGenerator:
		var icon_texture = ItemIconGenerator.get_item_icon(item)
		if icon_texture:
			icon.texture = icon_texture

	# Fallback label if no icon
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
	label.visible = (icon.texture == null)
	if label.visible:
		label.text = item.get("name", "???")
	center.add_child(label)

	# Build tooltip with item info
	var item_name = item.get("name", "Unknown")
	var tooltip = "[%s] %s\n" % [rarity, item_name]
	var desc = item.get("description", item.get("desc", ""))
	if desc:
		tooltip += desc + "\n"

	if item.has("value"):
		tooltip += "Value: %d G\n" % item.get("value", 0)

	tooltip += "\nClick to loot"
	slot_control.tooltip_text = tooltip

	# Connect click to loot
	slot_control.gui_input.connect(_on_loot_slot_input.bind(slot_control))

	return slot_control

func create_empty_slot() -> Control:
	"""Create an empty placeholder slot"""
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add panel for styling (dimmed empty slot)
	var panel_slot = PanelContainer.new()
	panel_slot.custom_minimum_size = SLOT_SIZE
	panel_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel_slot)

	var slot_style = create_slot_style(Color(0.05, 0.05, 0.07, 0.5), BORDER_INNER, 1, false)
	panel_slot.add_theme_stylebox_override("panel", slot_style)

	return slot_control

func create_slot_style(bg_color: Color, border_color: Color = BORDER_COLOR, border_width: int = 2, use_glow: bool = false) -> StyleBoxFlat:
	"""Create style for loot slots"""
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

func _on_loot_slot_input(event: InputEvent, slot: Control) -> void:
	"""Handle click on loot slot to loot the item"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index = slot.get_meta("item_index")
		loot_item(index)

func get_rarity_color(rarity: String) -> Color:
	"""Get color based on item rarity"""
	if UITheme:
		match rarity.to_upper():
			"COMMON":
				return UITheme.RARITY_COMMON
			"UNCOMMON":
				return UITheme.RARITY_UNCOMMON
			"RARE":
				return UITheme.RARITY_RARE
			"EPIC":
				return UITheme.RARITY_EPIC
			"LEGENDARY":
				return UITheme.RARITY_LEGENDARY
			_:
				return UITheme.BORDER_INNER
	else:
		# Fallback colors
		match rarity.to_upper():
			"COMMON":
				return Color(0.6, 0.6, 0.6)
			"UNCOMMON":
				return Color(0.12, 0.8, 0.12)
			"RARE":
				return Color(0.0, 0.44, 0.87)
			"EPIC":
				return Color(0.64, 0.21, 0.93)
			"LEGENDARY":
				return Color(1.0, 0.5, 0.0)
			_:
				return Color(0.2, 0.22, 0.25)

func loot_item(index: int) -> void:
	"""Loot a specific item"""
	if index < 0 or index >= harvest_loot.size():
		return

	var item = harvest_loot[index]
	if not item:  # Already looted
		return

	# Try to add to inventory
	if InventorySystem.add_item(item):
		var item_name = item.get("name", "Unknown")
		var item_rarity = item.get("rarity", "COMMON")
		print("✨ Looted: %s" % item_name)

		# Show notification (plays pickup sound)
		if NotificationManager and is_instance_valid(NotificationManager):
			NotificationManager.notify_item_added(item_name, 1, item_rarity.to_upper())

		item_looted.emit(item)

		# Mark as looted (set to null)
		harvest_loot[index] = null

		# Refresh the list
		populate_loot_grid()
	else:
		print("❌ Inventory full! Cannot loot %s" % item.get("name", "Unknown"))

func _on_take_all_pressed() -> void:
	"""Take all items"""
	_play_click_sound()

	# Collect items to loot first
	var items_to_loot: Array = []
	for i in range(harvest_loot.size()):
		var item = harvest_loot[i]
		if item:
			items_to_loot.append({"index": i, "item": item})

	if items_to_loot.is_empty():
		populate_loot_grid()
		return

	# Loot items with staggered notifications
	_loot_items_staggered(items_to_loot)

func _loot_items_staggered(items_to_loot: Array) -> void:
	"""Loot items one by one with slight delay for cascading effect"""
	var looted_count = 0

	for entry in items_to_loot:
		var i = entry["index"]
		var item = entry["item"]

		if InventorySystem.add_item(item):
			var item_name = item.get("name", "Resource")
			var item_rarity = item.get("rarity", "COMMON")

			# Show notification (plays pickup sound)
			if NotificationManager and is_instance_valid(NotificationManager):
				NotificationManager.notify_item_added(item_name, 1, item_rarity.to_upper())

			looted_count += 1
			item_looted.emit(item)
			harvest_loot[i] = null

			# Small delay between each notification for cascade effect
			await get_tree().create_timer(0.12).timeout
			if not is_instance_valid(self):
				return  # UI was closed during await
		else:
			# Inventory full
			print("❌ Inventory full! Looted %d of %d items" % [looted_count, items_to_loot.size()])
			populate_loot_grid()
			return

	if looted_count > 0:
		all_items_looted.emit()

	# Refresh and close
	populate_loot_grid()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	_play_click_sound()
	close_ui()

func close_ui() -> void:
	"""Close the loot UI"""
	hide()
	loot_ui_closed.emit()

func _play_click_sound() -> void:
	"""Play button click sound"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()
