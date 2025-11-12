extends CanvasLayer

## Inventory UI - WoW-style bag in bottom-right corner
## Press B to toggle
## Shows gold and 4 item slots

var is_visible: bool = false
var slot_buttons: Array[Button] = []

# UI References
var panel: PanelContainer
var gold_label: Label
var slots_grid: GridContainer

func _ready() -> void:
	# Set layer above game elements
	layer = 100

	# Start hidden
	visible = false

	# Create UI first
	create_inventory_ui()

	# Then connect to inventory system (after UI is created)
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.item_added.connect(_on_item_added)
	InventorySystem.item_removed.connect(_on_item_removed)

	# Initial update (UI is guaranteed to exist now)
	_on_inventory_changed()

func create_inventory_ui() -> void:
	"""Create WoW-style inventory bag in bottom-right corner"""

	# Main panel container
	panel = PanelContainer.new()
	panel.name = "InventoryPanel"

	# Position in bottom-right corner with proper anchors
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(200, 180)

	# Adjust position from bottom-right corner
	panel.position = Vector2(-220, -200)

	# Add subtle background color
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)  # Dark semi-transparent
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.35, 0.3, 1.0)  # Brown border (WoW-style)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	# VBox layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Title label
	var title = Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.6))  # Gold color
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Gold display
	var gold_container = HBoxContainer.new()
	gold_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(gold_container)

	var gold_icon = Label.new()
	gold_icon.text = "💰"
	gold_icon.add_theme_font_size_override("font_size", 16)
	gold_container.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0 Gold"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))  # Gold color
	gold_container.add_child(gold_label)

	# Separator
	var separator = HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	vbox.add_child(separator)

	# Item slots (2x2 grid)
	slots_grid = GridContainer.new()
	slots_grid.columns = 2
	slots_grid.add_theme_constant_override("h_separation", 8)
	slots_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(slots_grid)

	# Create 4 item slot buttons
	for i in range(4):
		var slot_button = Button.new()
		slot_button.name = "Slot%d" % i
		slot_button.custom_minimum_size = Vector2(70, 70)
		slot_button.text = ""  # Empty initially

		# Style the button
		var slot_style_normal = StyleBoxFlat.new()
		slot_style_normal.bg_color = Color(0.2, 0.2, 0.25, 1.0)  # Dark gray
		slot_style_normal.border_width_left = 1
		slot_style_normal.border_width_right = 1
		slot_style_normal.border_width_top = 1
		slot_style_normal.border_width_bottom = 1
		slot_style_normal.border_color = Color(0.5, 0.5, 0.5, 1.0)
		slot_button.add_theme_stylebox_override("normal", slot_style_normal)

		var slot_style_hover = slot_style_normal.duplicate()
		slot_style_hover.border_color = Color(0.8, 0.7, 0.5, 1.0)  # Gold on hover
		slot_button.add_theme_stylebox_override("hover", slot_style_hover)

		# Connect button press
		slot_button.pressed.connect(_on_slot_clicked.bind(i))

		slots_grid.add_child(slot_button)
		slot_buttons.append(slot_button)

	add_child(panel)

	# Ensure panel inherits visibility from parent
	panel.visible = true

	print("✅ Inventory UI created")
	print("   Panel size: ", panel.size)
	print("   Panel position: ", panel.position)
	print("   Panel visible: ", panel.visible)

func toggle_inventory() -> void:
	"""Toggle inventory visibility"""
	is_visible = !is_visible
	visible = is_visible

	if is_visible:
		print("📦 Inventory opened")
		print("   CanvasLayer visible: ", visible)
		print("   CanvasLayer layer: ", layer)
		if panel:
			print("   Panel visible: ", panel.visible)
			print("   Panel in tree: ", panel.is_inside_tree())
			print("   Panel global_position: ", panel.global_position)
		_on_inventory_changed()  # Refresh display
	else:
		print("📦 Inventory closed")

func _on_inventory_changed() -> void:
	"""Update UI when inventory changes"""
	# Null check - UI might not be created yet
	if not gold_label or slot_buttons.is_empty():
		return

	# Update gold display
	var gold_amount = InventorySystem.get_gold()
	gold_label.text = "%d Gold" % gold_amount

	# Update item slots
	for i in range(slot_buttons.size()):
		var item = InventorySystem.get_item(i)
		var button = slot_buttons[i]

		if item and item.size() > 0:
			# Show item
			button.text = item.get("name", "???")
			button.tooltip_text = "%s\nValue: %d gold" % [item.get("description", ""), item.get("value", 0)]
		else:
			# Empty slot
			button.text = ""
			button.tooltip_text = "Empty slot"

func _on_item_added(item: Dictionary) -> void:
	"""Called when an item is added"""
	print("✨ Item added to inventory: ", item.get("name", "Unknown"))

func _on_item_removed(item: Dictionary, slot: int) -> void:
	"""Called when an item is removed"""
	print("📤 Item removed from slot %d: %s" % [slot, item.get("name", "Unknown")])

func _on_slot_clicked(slot_index: int) -> void:
	"""Handle clicking an inventory slot"""
	var item = InventorySystem.get_item(slot_index)

	if item and item.size() > 0:
		print("🖱️ Clicked slot %d: %s" % [slot_index, item.get("name", "Unknown")])
		# Future: Could show item details, use item, sell item, etc.
	else:
		print("🖱️ Clicked empty slot %d" % slot_index)
