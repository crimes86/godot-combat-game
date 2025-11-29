extends CanvasLayer
class_name ChestLootUI

## Chest Loot UI for interactive looting
## Displays chest contents and allows player to pick items individually or take all

signal loot_ui_closed()
signal item_looted(item: Dictionary)
signal all_items_looted()

@onready var loot_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/LootContainer/LootList
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var take_all_button: Button = $Control/Panel/MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton

var chest_loot: Array = []  # Items available in the chest
var chest_owner: TreasureChest = null

func _ready() -> void:
	print("📦 ChestLootUI initialized")
	hide()

	# Apply stone gray theme to panel
	apply_panel_style()

	# Connect buttons
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if take_all_button:
		take_all_button.pressed.connect(_on_take_all_pressed)

func apply_panel_style() -> void:
	"""Apply standardized stone gray theme to panel"""
	var panel = get_node_or_null("Control/Panel")
	if not panel:
		return

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)  # Dark stone gray
	style.border_color = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

func _input(event: InputEvent) -> void:
	# Allow ESC to close or F to take all items from the chest UI
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_on_take_all_pressed()
			get_viewport().set_input_as_handled()

func open_chest_ui(chest: TreasureChest, loot_items: Array) -> void:
	"""Open the chest loot UI and populate it with items"""
	chest_owner = chest
	chest_loot = loot_items.duplicate()

	print("📦 Opening chest loot UI with %d items" % chest_loot.size())

	populate_loot_list()
	show()

func close_ui() -> void:
	"""Close the loot UI"""
	hide()
	loot_ui_closed.emit()
	print("📦 Chest loot UI closed")

func populate_loot_list() -> void:
	"""Populate the loot list with item icon slots"""
	if not loot_list:
		return

	# Clear existing items
	for child in loot_list.get_children():
		child.queue_free()

	# Create a grid container for icon slots
	var grid = GridContainer.new()
	grid.columns = 4  # 4 items per row
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	loot_list.add_child(grid)

	# Add loot items as icon slots
	for i in range(chest_loot.size()):
		var item = chest_loot[i]
		if item:  # Skip null items (already looted)
			var item_slot = create_loot_item_row(item, func(): loot_item(i))
			grid.add_child(item_slot)

	# Show message if all items looted
	if chest_loot.filter(func(item): return item != null).size() == 0:
		var empty_label = Label.new()
		empty_label.text = "Chest is empty"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loot_list.add_child(empty_label)

		# Close after showing empty message
		await get_tree().create_timer(1.0).timeout
		close_ui()

func create_loot_item_row(item: Dictionary, on_loot: Callable) -> Control:
	"""Create a compact icon slot for a loot item with hoverable tooltip"""
	var item_name = item.get("name", "Unknown")
	var description = item.get("desc", item.get("description", ""))
	var value = item.get("value", 0)
	var rarity = item.get("rarity", "common")

	# Get rarity color for border
	var rarity_color = get_rarity_color(rarity)

	# Use Button as the slot (handles click and has built-in styling)
	var slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(56, 56)
	slot_button.text = get_item_icon_text(item)
	slot_button.clip_text = true  # Clip text that doesn't fit
	slot_button.add_theme_font_size_override("font_size", 10)
	slot_button.add_theme_color_override("font_color", rarity_color)
	slot_button.add_theme_color_override("font_hover_color", Color.WHITE)

	# Style the button
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	style.border_color = rarity_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot_button.add_theme_stylebox_override("normal", style)

	# Hover style
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.25, 0.25, 0.30, 0.95)
	slot_button.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	slot_button.add_theme_stylebox_override("pressed", pressed_style)

	# Build tooltip text
	var tooltip = "%s\n%s" % [item_name, description]
	if value > 0:
		tooltip += "\nValue: 🪙 %d" % value
	slot_button.tooltip_text = tooltip

	# Connect click
	slot_button.pressed.connect(on_loot)

	return slot_button

func get_rarity_color(rarity: String) -> Color:
	"""Get color based on item rarity"""
	match rarity.to_lower():
		"common":
			return Color(0.6, 0.6, 0.6)  # Gray
		"uncommon":
			return Color(0.2, 0.8, 0.2)  # Green
		"rare":
			return Color(0.2, 0.4, 1.0)  # Blue
		"epic":
			return Color(0.6, 0.2, 0.8)  # Purple
		"legendary":
			return Color(1.0, 0.5, 0.0)  # Orange
		_:
			return Color(0.6, 0.6, 0.6)  # Default gray

func get_item_icon_text(item: Dictionary) -> String:
	"""Get short display text for item icon"""
	var item_type = item.get("type", "")
	var slot = item.get("slot", "")
	var name = item.get("name", "?")

	# Return abbreviated name (first 6 chars or full short name)
	if name.length() <= 8:
		return name
	else:
		# Get first word or abbreviate
		var words = name.split(" ")
		if words.size() > 1:
			return words[0].substr(0, 6)
		return name.substr(0, 6)

func loot_item(index: int) -> void:
	"""Loot a specific item from the chest"""
	if index < 0 or index >= chest_loot.size():
		return

	var item = chest_loot[index]
	if not item:  # Already looted
		return

	# Try to add to inventory
	if InventorySystem.add_item(item):
		var item_name = item.get("name", "Unknown")
		var item_rarity = item.get("rarity", "Common")
		print("✨ Looted: %s" % item_name)

		# Show notification (plays pickup sound)
		if NotificationManager and is_instance_valid(NotificationManager):
			NotificationManager.notify_item_added(item_name, 1, item_rarity)

		item_looted.emit(item)

		# Mark as looted (set to null)
		chest_loot[index] = null

		# Refresh the list
		populate_loot_list()
	else:
		print("❌ Inventory full! Cannot loot %s" % item.get("name", "Unknown"))

func _on_take_all_pressed() -> void:
	"""Take all items from the chest"""
	# Collect items to loot first
	var items_to_loot: Array = []
	for i in range(chest_loot.size()):
		var item = chest_loot[i]
		if item:
			items_to_loot.append({"index": i, "item": item})

	if items_to_loot.is_empty():
		populate_loot_list()
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
			var item_name = item.get("name", "Unknown")
			var item_rarity = item.get("rarity", "Common")

			# Show notification (plays pickup sound)
			if NotificationManager and is_instance_valid(NotificationManager):
				NotificationManager.notify_item_added(item_name, 1, item_rarity)

			looted_count += 1
			item_looted.emit(item)
			chest_loot[i] = null

			# Small delay between each notification for cascade effect
			await get_tree().create_timer(0.12).timeout
			if not is_instance_valid(self):
				return  # UI was closed during await
		else:
			print("❌ Inventory full! Looted %d of %d items" % [looted_count, items_to_loot.size()])
			populate_loot_list()
			return

	if looted_count > 0:
		print("✨ Looted all %d items from chest" % looted_count)
		all_items_looted.emit()

	# Refresh and close
	populate_loot_list()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_ui()
