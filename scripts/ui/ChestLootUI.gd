extends CanvasLayer
class_name ChestLootUI

## Chest Loot UI for interactive looting
## Displays chest contents with icon-based grid (like LootBodyUI)

signal loot_ui_closed()
signal item_looted(item: Dictionary)
signal all_items_looted()

@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var take_all_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton
@onready var loot_grid: GridContainer = $Panel/MarginContainer/VBoxContainer/LootGrid

var chest_loot: Array = []  # Items available in the chest
var chest_owner: TreasureChest = null

# UI Style constants (matching LootBodyUI)
const SLOT_SIZE = Vector2(52, 52)
const GRID_COLUMNS = 3
const MIN_SLOTS = 3
const LOOT_RANGE = 150.0  # Max distance to loot chest

# UI colors - use UITheme singleton
var SLOT_BG: Color:
	get: return UITheme.SLOT_BG
var BORDER_INNER: Color:
	get: return UITheme.BORDER_INNER
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR

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

	if loot_grid:
		loot_grid.columns = GRID_COLUMNS

func _process(_delta: float) -> void:
	"""Check if player is still in range of chest"""
	if not visible or not chest_owner:
		return

	# Get player position
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	# Check distance to chest
	if is_instance_valid(chest_owner):
		var distance = player.global_position.distance_to(chest_owner.global_position)
		if distance > LOOT_RANGE:
			close_ui()

func apply_panel_style() -> void:
	"""Apply standardized stone gray theme to panel"""
	var panel = get_node_or_null("Panel")
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

	populate_loot_grid()
	show()

func close_ui() -> void:
	"""Close the loot UI"""
	hide()
	loot_ui_closed.emit()
	print("📦 Chest loot UI closed")

func populate_loot_grid() -> void:
	"""Populate the loot grid with icon slots"""
	if not loot_grid:
		return

	# Clear existing items
	for child in loot_grid.get_children():
		child.queue_free()

	var total_slots = 0

	# Add loot items as icon slots
	for i in range(chest_loot.size()):
		var item = chest_loot[i]
		if item:  # Skip null items (already looted)
			var slot = create_loot_slot(item, i)
			loot_grid.add_child(slot)
			total_slots += 1

	# Add empty slots to reach minimum
	while total_slots < MIN_SLOTS:
		var empty_slot = create_empty_slot()
		loot_grid.add_child(empty_slot)
		total_slots += 1

	# If everything was looted, close after brief delay
	var actual_loot_count = chest_loot.filter(func(item): return item != null).size()
	if actual_loot_count == 0:
		await get_tree().create_timer(0.5).timeout
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
	var rarity = item.get("rarity", "Common")
	var rarity_color = get_rarity_color(rarity)

	# Add panel for styling with rarity glow
	var panel = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(SLOT_BG, rarity_color, 3, true)
	panel.add_theme_stylebox_override("panel", slot_style)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

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

	if item.get("type") == "weapon":
		if item.has("base_damage"):
			tooltip += "Damage: +%.1f\n" % item.get("base_damage", 0)
		if item.has("attack_speed_bonus"):
			var speed_bonus = item.get("attack_speed_bonus", 0.0)
			if speed_bonus != 0:
				tooltip += "Attack Speed: %+.1f%%\n" % (speed_bonus * 100)
		if item.has("crit_chance_bonus"):
			var crit_bonus = item.get("crit_chance_bonus", 0.0)
			if crit_bonus != 0:
				tooltip += "Crit Chance: +%.1f%%\n" % (crit_bonus * 100)

	if item.has("defense"):
		tooltip += "Defense: +%d\n" % item.get("defense", 0)

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
	var panel = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(Color(0.05, 0.05, 0.07, 0.5), BORDER_INNER, 1, false)
	panel.add_theme_stylebox_override("panel", slot_style)

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
		populate_loot_grid()
	else:
		print("❌ Inventory full! Cannot loot %s" % item.get("name", "Unknown"))

func _on_take_all_pressed() -> void:
	"""Take all items from the chest"""
	_play_click_sound()
	# Collect items to loot first
	var items_to_loot: Array = []
	for i in range(chest_loot.size()):
		var item = chest_loot[i]
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
			populate_loot_grid()
			return

	if looted_count > 0:
		print("✨ Looted all %d items from chest" % looted_count)
		all_items_looted.emit()

	# Refresh and close
	populate_loot_grid()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	_play_click_sound()
	close_ui()

func _play_click_sound() -> void:
	"""Play button click sound"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()
