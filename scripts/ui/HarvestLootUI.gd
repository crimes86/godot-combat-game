extends CanvasLayer
class_name HarvestLootUI

## Mini Harvest Loot UI for trees and rocks
## Small, non-intrusive UI that appears in a consistent spot for quick looting

signal item_looted(item: Dictionary)
signal all_items_looted()
signal loot_ui_closed()

var harvest_loot: Array = []
var harvest_type: String = "Resource"  # "Wood" or "Ore"
var panel: PanelContainer
var item_label: Label
var take_button: Button

func _ready() -> void:
	layer = 100  # Above game world
	create_ui()
	hide()

func create_ui() -> void:
	"""Create the mini loot UI programmatically"""
	# Main control anchored to full screen (we'll position panel relative to player)
	var control = Control.new()
	control.name = "Control"
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(control)

	# Panel container - positioned on right side of screen, vertically centered
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_top = 0.5
	panel.anchor_right = 1.0
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_right = -20
	panel.offset_top = -50
	panel.offset_bottom = 50

	# Style the panel (stone gray theme)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.9)  # Dark stone gray
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
	control.add_child(panel)

	# Vertical layout inside panel
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Item label (shows what's available)
	item_label = Label.new()
	item_label.text = "Wood x3"
	item_label.add_theme_font_size_override("font_size", 18)
	item_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.94))  # Clean white
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(item_label)

	# Take button
	take_button = Button.new()
	take_button.text = "Take [F]"
	take_button.add_theme_font_size_override("font_size", 16)
	take_button.custom_minimum_size = Vector2(100, 35)
	take_button.pressed.connect(_on_take_pressed)

	# Center the button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(take_button)
	vbox.add_child(button_container)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_on_take_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()

func open_harvest_ui(loot_items: Array, type: String) -> void:
	"""Open the harvest loot UI with items"""
	harvest_loot = loot_items.duplicate()
	harvest_type = type

	update_display()
	show()

func update_display() -> void:
	"""Update the item display"""
	if harvest_loot.size() == 0:
		item_label.text = "Empty"
		take_button.disabled = true
		return

	# Count items by name
	var item_counts = {}
	for item in harvest_loot:
		if item:
			var name = item.get("name", "Resource")
			item_counts[name] = item_counts.get(name, 0) + 1

	# Build display text
	var display_parts = []
	for item_name in item_counts:
		var count = item_counts[item_name]
		if count > 1:
			display_parts.append("%s x%d" % [item_name, count])
		else:
			display_parts.append(item_name)

	item_label.text = ", ".join(display_parts)
	take_button.disabled = false

func _on_take_pressed() -> void:
	"""Take all items"""
	# Collect items to loot first
	var items_to_loot: Array = []
	for i in range(harvest_loot.size()):
		var item = harvest_loot[i]
		if item:
			items_to_loot.append({"index": i, "item": item})

	if items_to_loot.is_empty():
		close_ui()
		return

	# Loot items with staggered notifications for cascade effect
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

			looted_count += 1
			item_looted.emit(item)
			harvest_loot[i] = null

			# Show notification and play pickup sound
			if NotificationManager and is_instance_valid(NotificationManager):
				NotificationManager.notify_item_added(item_name, 1, item_rarity.to_upper())

			# Small delay between each notification for cascade effect
			await get_tree().create_timer(0.12).timeout
			if not is_instance_valid(self):
				return  # UI was closed during await
		else:
			# Inventory full
			print("❌ Inventory full! Looted %d of %d items" % [looted_count, items_to_loot.size()])
			update_display()
			return

	if looted_count > 0:
		all_items_looted.emit()

	close_ui()

func close_ui() -> void:
	"""Close the loot UI"""
	hide()
	loot_ui_closed.emit()
