extends Control
class_name CampfireFuelUI

## Campfire Fuel Management UI
## Shows current fuel levels, buffs, and allows adding fuel

# UI Elements
var panel: Panel
var title_label: Label
var close_button: Button

# Fuel info labels
var wood_label: Label
var bone_ember_label: Label
var heal_buff_label: Label
var crit_buff_label: Label

# Progress bars
var wood_progress: ProgressBar
var bone_ember_progress: ProgressBar

# Buttons
var add_all_wood_btn: Button
var add_all_embers_btn: Button
var add_all_both_btn: Button
var add_custom_btn: Button

# Custom input fields
var wood_input: SpinBox
var bone_input: SpinBox

# Reference to the campfire
var campfire: Campfire = null

func _ready() -> void:
	# UI will be created dynamically
	create_ui()
	visible = false

func create_ui() -> void:
	"""Create the campfire fuel UI"""
	# Main panel (dark wasteland theme)
	panel = Panel.new()
	panel.name = "MainPanel"
	panel.custom_minimum_size = Vector2(500, 600)
	add_child(panel)

	# Apply stone gray theme colors
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.12, 0.12, 0.14, 0.95)  # Dark stone gray
	style_box.border_color = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
	style_box.border_width_left = 3
	style_box.border_width_right = 3
	style_box.border_width_top = 3
	style_box.border_width_bottom = 3
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style_box)

	# VBox for layout
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "🔥 CAMPFIRE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	vbox.add_child(title_label)

	# Close button
	close_button = Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.position = Vector2(460, 10)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# === FUEL STATUS SECTION ===
	var status_label = Label.new()
	status_label.text = "═══ FUEL STATUS ═══"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(status_label)

	# Wood info
	create_fuel_display(vbox, "🪵 WOOD (Healing Buff)", "wood")

	# Bone ember info
	create_fuel_display(vbox, "🦴 BONE EMBERS (Crit Buff)", "bone_ember")

	# === CURRENT BUFFS SECTION ===
	var buffs_label = Label.new()
	buffs_label.text = "═══ ACTIVE BUFFS ═══"
	buffs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buffs_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(buffs_label)

	heal_buff_label = Label.new()
	heal_buff_label.text = "Healing: 5.0 HP/s"
	heal_buff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_buff_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	vbox.add_child(heal_buff_label)

	crit_buff_label = Label.new()
	crit_buff_label.text = "Crit Chance: +0.0%"
	crit_buff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crit_buff_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	vbox.add_child(crit_buff_label)

	# === ADD FUEL SECTION ===
	var add_fuel_label = Label.new()
	add_fuel_label.text = "═══ ADD FUEL ═══"
	add_fuel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_fuel_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(add_fuel_label)

	# Quick add buttons
	add_all_wood_btn = create_button("Add All Wood")
	add_all_wood_btn.pressed.connect(_on_add_all_wood)
	vbox.add_child(add_all_wood_btn)

	add_all_embers_btn = create_button("Add All Bone Embers")
	add_all_embers_btn.pressed.connect(_on_add_all_embers)
	vbox.add_child(add_all_embers_btn)

	add_all_both_btn = create_button("Add All (Wood + Embers)")
	add_all_both_btn.pressed.connect(_on_add_all_both)
	vbox.add_child(add_all_both_btn)

	# Custom amounts section
	var custom_label = Label.new()
	custom_label.text = "Custom Amounts:"
	custom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(custom_label)

	var custom_hbox = HBoxContainer.new()
	custom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	custom_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(custom_hbox)

	wood_input = SpinBox.new()
	wood_input.min_value = 0
	wood_input.max_value = 200
	wood_input.value = 10
	wood_input.custom_minimum_size = Vector2(100, 30)
	custom_hbox.add_child(wood_input)

	var wood_custom_label = Label.new()
	wood_custom_label.text = "Wood"
	custom_hbox.add_child(wood_custom_label)

	bone_input = SpinBox.new()
	bone_input.min_value = 0
	bone_input.max_value = 200
	bone_input.value = 10
	bone_input.custom_minimum_size = Vector2(100, 30)
	custom_hbox.add_child(bone_input)

	var bone_custom_label = Label.new()
	bone_custom_label.text = "Embers"
	custom_hbox.add_child(bone_custom_label)

	add_custom_btn = create_button("Add Custom Amounts")
	add_custom_btn.pressed.connect(_on_add_custom)
	vbox.add_child(add_custom_btn)

	# Center the panel
	set_anchors_preset(Control.PRESET_CENTER)

func create_fuel_display(parent: Control, label_text: String, fuel_type: String) -> void:
	"""Create a fuel display with progress bar"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 5)
	parent.add_child(container)

	var label = Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	container.add_child(label)

	var progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(400, 25)
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = false
	container.add_child(progress)

	var count_label = Label.new()
	count_label.text = "0 / 100 (0%)"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	container.add_child(count_label)

	# Store references
	if fuel_type == "wood":
		wood_progress = progress
		wood_label = count_label
	else:
		bone_ember_progress = progress
		bone_ember_label = count_label

func create_button(text: String) -> Button:
	"""Create a themed button"""
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 40)

	# Style button (stone gray theme)
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.25, 0.26, 0.30, 0.8)  # Medium stone gray
	style_normal.border_color = Color(0.45, 0.48, 0.52, 1.0)  # Light steel border
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.32, 0.34, 0.40, 0.9)  # Lighter stone on hover
	btn.add_theme_stylebox_override("hover", style_hover)

	return btn

func show_for_campfire(fire: Campfire) -> void:
	"""Show the UI for a specific campfire"""
	campfire = fire
	update_display()
	visible = true
	get_viewport().gui_release_focus()  # Prevent click-through

func update_display() -> void:
	"""Update all UI elements with current campfire stats"""
	if not campfire or not is_instance_valid(campfire):
		return

	var status = campfire.get_fuel_status()

	# Update progress bars
	wood_progress.value = status.wood_percent * 100
	bone_ember_progress.value = status.bone_percent * 100

	# Update labels
	wood_label.text = "%d / %d (%.0f%%)" % [status.wood_count, status.max_wood, status.wood_percent * 100]
	bone_ember_label.text = "%d / %d (%.0f%%)" % [status.bone_ember_count, status.max_bone_embers, status.bone_percent * 100]

	# Update buff labels
	heal_buff_label.text = "💚 Healing: %.1f HP/s" % status.heal_rate
	crit_buff_label.text = "⚔️ Crit Chance: +%.1f%%" % (status.crit_bonus * 100)

func _on_add_all_wood() -> void:
	if not campfire:
		return
	# Collect all wood slots first (to avoid modifying during iteration)
	var wood_slots = []
	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Dry Log":
			wood_slots.append({"slot": slot_idx, "quantity": item.get("quantity", 1)})

	# Add wood to campfire
	var wood_added = 0
	for slot_data in wood_slots:
		var quantity = slot_data.quantity
		if campfire.add_wood_fuel(quantity):
			wood_added += quantity
			InventorySystem.remove_item(slot_data.slot)

	update_display()

func _on_add_all_embers() -> void:
	if not campfire:
		return
	# Collect all ember slots first (to avoid modifying during iteration)
	var ember_slots = []
	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Bone Ember":
			ember_slots.append({"slot": slot_idx, "quantity": item.get("quantity", 1)})

	# Add embers to campfire
	var bone_added = 0
	for slot_data in ember_slots:
		var quantity = slot_data.quantity
		if campfire.add_bone_ember_fuel(quantity):
			bone_added += quantity
			InventorySystem.remove_item(slot_data.slot)

	update_display()

func _on_add_all_both() -> void:
	_on_add_all_wood()
	_on_add_all_embers()

func _on_add_custom() -> void:
	if not campfire:
		return

	var wood_to_add = int(wood_input.value)
	var embers_to_add = int(bone_input.value)

	# Add wood
	if wood_to_add > 0:
		var wood_remaining = wood_to_add
		for slot_idx in range(InventorySystem.inventory_items.size()):
			if wood_remaining <= 0:
				break
			var item = InventorySystem.get_item(slot_idx)
			if item and item.get("name") == "Dry Log":
				var qty = item.get("quantity", 1)
				var take = min(qty, wood_remaining)
				if campfire.add_wood_fuel(take):
					InventorySystem.reduce_quantity(slot_idx, take)
					wood_remaining -= take

	# Add embers
	if embers_to_add > 0:
		var embers_remaining = embers_to_add
		for slot_idx in range(InventorySystem.inventory_items.size()):
			if embers_remaining <= 0:
				break
			var item = InventorySystem.get_item(slot_idx)
			if item and item.get("name") == "Bone Ember":
				var qty = item.get("quantity", 1)
				var take = min(qty, embers_remaining)
				if campfire.add_bone_ember_fuel(take):
					InventorySystem.reduce_quantity(slot_idx, take)
					embers_remaining -= take

	update_display()

func _on_close_pressed() -> void:
	visible = false
