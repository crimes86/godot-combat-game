extends CanvasLayer
class_name LootBodyUI

## Loot Body UI for looting corpses
## Displays aggregated loot from multiple corpses in AOE range
## Similar to ChestLootUI but with corpse-specific theming

signal loot_ui_closed()
signal item_looted(item: Dictionary, corpse)
signal all_corpses_looted()

@onready var loot_list: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/LootContainer/LootList
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var take_all_button: Button = $Control/Panel/MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton
@onready var header_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var gold_label: Label = $Control/Panel/MarginContainer/VBoxContainer/Header/GoldLabel

var corpses_looted = []  # All corpses in AOE
var total_gold_collected: int = 0

func _ready() -> void:
	print("💀 LootBodyUI initialized")
	hide()

	# Connect buttons
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if take_all_button:
		take_all_button.pressed.connect(_on_take_all_pressed)

func _input(event: InputEvent) -> void:
	# Allow ESC to close or F to take all items
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_on_take_all_pressed()
			get_viewport().set_input_as_handled()

func open_loot_ui(primary_corpse, nearby_corpses: Array) -> void:
	"""Open the loot UI with aggregated loot from all nearby corpses"""
	# Combine all corpses
	corpses_looted = [primary_corpse] + nearby_corpses

	# Note: Gold was already awarded immediately on death
	# We don't need to collect it again

	# Update header
	var corpse_count = corpses_looted.size()
	if header_label:
		if corpse_count == 1:
			header_label.text = "Looting Body"
		else:
			header_label.text = "Looting %d Bodies" % corpse_count

	# Hide gold label (gold already awarded on death)
	if gold_label:
		gold_label.visible = false

	print("💀 Opening loot body UI with %d corpse(s)" % corpse_count)

	populate_loot_list()
	show()

func close_ui() -> void:
	"""Close the loot UI"""
	hide()
	loot_ui_closed.emit()
	print("💀 Loot body UI closed")

func populate_loot_list() -> void:
	"""Populate the loot list with items from all corpses"""
	if not loot_list:
		return

	# Clear existing items
	for child in loot_list.get_children():
		child.queue_free()

	# Collect all items from all corpses
	var total_items = 0
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue

		for item in corpse.corpse_loot:
			if item:  # Skip null items (already looted)
				var item_row = create_loot_item_row(
					item.get("name", "Unknown"),
					item.get("description", ""),
					item.get("value", 0),
					item.get("rarity", "Common"),
					corpse,
					item
				)
				loot_list.add_child(item_row)
				total_items += 1

	# Show message if all items looted
	if total_items == 0:
		var empty_label = Label.new()
		empty_label.text = "No loot remaining"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loot_list.add_child(empty_label)

		# Close after showing empty message
		await get_tree().create_timer(1.0).timeout
		close_ui()

func create_loot_item_row(item_name: String, description: String, value: int, rarity: String, source_corpse, item_data: Dictionary) -> PanelContainer:
	"""Create a row for a loot item with corpse-themed styling"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 70)

	# Add background with bone-white border (instead of golden)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.6)  # Darker than chest
	style.border_width_left = 4

	# Border color based on rarity
	var border_color = get_rarity_color(rarity)
	style.border_color = border_color

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

	# Item name (with rarity color)
	var name_label = Label.new()
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", border_color)
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(300, 0)
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
	loot_button.pressed.connect(func(): loot_item(source_corpse, item_data))
	hbox.add_child(loot_button)

	return panel

func get_rarity_color(rarity: String) -> Color:
	"""Get color based on item rarity"""
	match rarity:
		"Common":
			return Color(0.7, 0.7, 0.7)  # Gray
		"Uncommon":
			return Color(0.2, 1.0, 0.2)  # Green
		"Rare":
			return Color(0.3, 0.5, 1.0)  # Blue
		"Epic":
			return Color(0.7, 0.3, 1.0)  # Purple
		"Legendary":
			return Color(1.0, 0.6, 0.2)  # Orange
		_:
			return Color(1.0, 1.0, 1.0)  # White fallback

func loot_item(corpse, item: Dictionary) -> void:
	"""Loot a specific item from a corpse"""
	if not is_instance_valid(corpse):
		print("❌ Corpse no longer valid")
		populate_loot_list()
		return

	if not corpse.corpse_loot.has(item):
		print("❌ Item no longer in corpse loot")
		populate_loot_list()
		return

	# Try to add to inventory
	if InventorySystem.add_item(item):
		print("✨ Looted: %s from corpse" % item.get("name", "Unknown"))
		item_looted.emit(item, corpse)

		# Remove from corpse's loot array
		corpse.corpse_loot.erase(item)

		# Check if corpse is now empty
		corpse.check_if_looted_empty()

		# Refresh the list
		populate_loot_list()
	else:
		print("❌ Inventory full! Cannot loot %s" % item.get("name", "Unknown"))

func _on_take_all_pressed() -> void:
	"""Take all items from all corpses"""
	var looted_count = 0
	var total_count = 0

	# Count total items
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			total_count += corpse.corpse_loot.size()

	# Loot all items
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue

		# Make a copy of the array since we'll be modifying it
		var items_to_loot = corpse.corpse_loot.duplicate()

		for item in items_to_loot:
			if item:  # Skip null items
				if InventorySystem.add_item(item):
					looted_count += 1
					item_looted.emit(item, corpse)
					corpse.corpse_loot.erase(item)
				else:
					print("❌ Inventory full! Looted %d of %d items" % [looted_count, total_count])
					# Check which corpses are empty
					for c in corpses_looted:
						if is_instance_valid(c):
							c.check_if_looted_empty()
					populate_loot_list()
					return

		# Check if this corpse is now empty
		if is_instance_valid(corpse):
			corpse.check_if_looted_empty()

	if looted_count > 0:
		print("✨ Looted all %d items from %d corpse(s)" % [looted_count, corpses_looted.size()])
		all_corpses_looted.emit()

	# Refresh and potentially close
	populate_loot_list()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_ui()
