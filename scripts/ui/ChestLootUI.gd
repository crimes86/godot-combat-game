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

	# Connect buttons
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if take_all_button:
		take_all_button.pressed.connect(_on_take_all_pressed)

func _input(event: InputEvent) -> void:
	# Allow E, ESC, or F to interact with the chest UI
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
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
	"""Populate the loot list with items"""
	if not loot_list:
		return

	# Clear existing items
	for child in loot_list.get_children():
		child.queue_free()

	# Add loot items
	for i in range(chest_loot.size()):
		var item = chest_loot[i]
		if item:  # Skip null items (already looted)
			var item_row = create_loot_item_row(
				item.get("name", "Unknown"),
				item.get("desc", item.get("description", "")),
				item.get("value", 0),
				func(): loot_item(i)
			)
			loot_list.add_child(item_row)

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

func create_loot_item_row(item_name: String, description: String, value: int, on_loot: Callable) -> PanelContainer:
	"""Create a row for a loot item"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 70)

	# Add background with golden border
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.5)
	style.border_width_left = 4
	style.border_color = Color(1.0, 0.9, 0.4)  # Golden
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
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_label)

	# Value
	var value_label = Label.new()
	value_label.text = "Value: %d gold" % value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(value_label)

	# Right side - Loot button
	var loot_button = Button.new()
	loot_button.text = "LOOT"
	loot_button.custom_minimum_size = Vector2(80, 50)
	loot_button.pressed.connect(on_loot)
	hbox.add_child(loot_button)

	return panel

func loot_item(index: int) -> void:
	"""Loot a specific item from the chest"""
	if index < 0 or index >= chest_loot.size():
		return

	var item = chest_loot[index]
	if not item:  # Already looted
		return

	# Try to add to inventory
	if InventorySystem.add_item(item):
		print("✨ Looted: %s" % item.get("name", "Unknown"))
		item_looted.emit(item)

		# Mark as looted (set to null)
		chest_loot[index] = null

		# Refresh the list
		populate_loot_list()
	else:
		print("❌ Inventory full! Cannot loot %s" % item.get("name", "Unknown"))

func _on_take_all_pressed() -> void:
	"""Take all items from the chest"""
	var looted_count = 0

	for i in range(chest_loot.size()):
		var item = chest_loot[i]
		if item:  # Skip already looted items
			if InventorySystem.add_item(item):
				looted_count += 1
				item_looted.emit(item)
				chest_loot[i] = null
			else:
				print("❌ Inventory full! Looted %d of %d items" % [looted_count, chest_loot.size()])
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
