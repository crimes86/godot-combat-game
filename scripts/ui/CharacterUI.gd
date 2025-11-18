extends CanvasLayer

## Character UI - EverQuest-style unified character sheet
## Combines character info, stats, equipment, and inventory in one window
## Press C to toggle

var is_visible: bool = false

# Pending deletion data (for confirmation dialog)
var pending_delete_data: Dictionary = {}

# UI References
var main_panel: PanelContainer
var equipment_slots: Dictionary = {}  # slot_name: VBoxContainer (contains CenterContainer with Button + Label)
var inventory_slots: Array[Control] = []  # Changed from Array[Button] to Array[Control]
var stat_labels: Dictionary = {}  # stat_name: Label
var character_name_label: Label
var level_label: Label
var xp_bar: ProgressBar
var gold_label: Label
var hp_label: Label
var defense_label: Label

# Dark Fantasy Wasteland Palette
const BG_COLOR = Color(0.12, 0.10, 0.08, 0.75)  # Dark weathered leather (transparent for combat)
const BORDER_COLOR = Color(0.45, 0.30, 0.18, 1.0)  # Rusted bronze/copper
const BORDER_INNER = Color(0.08, 0.06, 0.05, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.65, 0.50, 0.30, 1.0)  # Tarnished gold
const TEXT_COLOR = Color(0.95, 0.92, 0.85, 1.0)  # Aged parchment white
const HEADER_COLOR = Color(0.85, 0.70, 0.45, 1.0)  # Faded gold headers
const HP_COLOR = Color(0.85, 0.20, 0.15, 1.0)  # Blood red
const XP_COLOR = Color(0.40, 0.55, 0.70, 1.0)  # Muted steel blue
const SLOT_BG = Color(0.10, 0.08, 0.06, 0.8)  # Darker leather inset
const BUFF_COLOR = Color(0.3, 0.8, 0.3, 1.0)  # Sickly green for buffs
const DEBUFF_COLOR = Color(0.8, 0.3, 0.2, 1.0)  # Rust red for debuffs

# Animation timing (snappy for rhythm combat)
const ANIM_SPEED = 0.1

func _ready() -> void:
	print("🎨 CharacterUI._ready() started")

	# Set layer above game elements but below shop
	layer = 95

	# Start hidden
	visible = false

	# Create UI
	create_character_ui()

	# Connect to signals
	CharacterStats.level_up.connect(_on_stats_changed)
	CharacterStats.experience_gained.connect(_on_xp_changed)
	CharacterStats.gold_changed.connect(_on_gold_changed)
	CharacterStats.armor_equipped.connect(_on_armor_changed)
	CharacterStats.armor_unequipped.connect(_on_armor_changed)
	InventorySystem.inventory_changed.connect(_on_inventory_changed)

	# Initial update
	refresh_all()

	print("🎨 CharacterUI._ready() COMPLETED")

func create_character_ui() -> void:
	"""Create EverQuest-style character sheet"""

	# Create full-screen drop zone for deletion (sits behind everything)
	var drop_zone = Control.new()
	drop_zone.name = "FullScreenDropZone"
	drop_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	drop_zone.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass clicks but receive drag events

	# Enable drag-drop on the drop zone
	drop_zone.set_drag_forwarding(
		Callable(self, "_get_drop_zone_drag_data"),
		Callable(self, "_can_drop_on_drop_zone"),
		Callable(self, "_drop_on_drop_zone")
	)

	add_child(drop_zone)

	# Create confirmation dialog for deletion
	var delete_dialog = ConfirmationDialog.new()
	delete_dialog.name = "DeleteConfirmDialog"
	delete_dialog.title = "Delete Item"
	delete_dialog.dialog_text = "Are you sure you want to delete this item?"
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(delete_dialog)

	# Main panel container - centered (wider for 3 columns)
	main_panel = PanelContainer.new()
	main_panel.name = "CharacterPanel"

	# Center the panel - wider for 3-column layout
	main_panel.set_anchors_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	main_panel.custom_minimum_size = Vector2(1000, 600)
	main_panel.offset_left = -500
	main_panel.offset_right = 500
	main_panel.offset_top = -300
	main_panel.offset_bottom = 300

	# Dark Fantasy Wasteland styling with transparency
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR  # 75% transparent dark leather
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = BORDER_COLOR  # Rusted bronze

	# Subtle rounded corners
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8

	# Heavy shadow for depth
	panel_style.shadow_size = 12
	panel_style.shadow_color = Color(0, 0, 0, 0.8)  # Darker shadow for wasteland
	panel_style.shadow_offset = Vector2(0, 6)

	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Don't enable drag-drop on main panel - we'll use a full-screen drop zone instead

	# Main horizontal layout (3 columns: Stats | Equipment | Inventory) with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	main_panel.add_child(margin)

	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_hbox)

	# LEFT COLUMN: Character info + stats (NO inventory/gold)
	create_character_info_panel(main_hbox)

	# MIDDLE COLUMN: Equipment slots
	create_equipment_panel(main_hbox)

	# RIGHT COLUMN: Inventory + Gold
	create_inventory_panel(main_hbox)

	add_child(main_panel)

	print("✅ Character UI created")

func create_equipment_panel(parent: Control) -> void:
	"""Create middle panel with equipment slots"""
	var equipment_panel = PanelContainer.new()
	equipment_panel.custom_minimum_size = Vector2(280, 0)
	equipment_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var equip_style = create_inner_panel_style()
	equipment_panel.add_theme_stylebox_override("panel", equip_style)
	parent.add_child(equipment_panel)

	var equipment_vbox = VBoxContainer.new()
	equipment_vbox.add_theme_constant_override("separation", 12)
	equipment_panel.add_child(equipment_vbox)

	# Title
	var title = create_header_label("Equipment")
	equipment_vbox.add_child(title)

	# Equipment slots container - CENTERED
	var slots_container = VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", 8)
	slots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_vbox.add_child(slots_container)

	# Create equipment slots (weapons first, then armor)
	var slot_names = ["mainhand", "offhand", "head", "chest", "arms", "legs", "feet"]
	var slot_labels = {
		"mainhand": "MAIN HAND",
		"offhand": "OFF HAND",
		"head": "HEAD",
		"chest": "CHEST",
		"arms": "ARMS",
		"legs": "LEGS",
		"feet": "FEET"
	}

	for slot in slot_names:
		var slot_button = create_equipment_slot(slot, slot_labels[slot])
		slots_container.add_child(slot_button)
		equipment_slots[slot] = slot_button

	# Add spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	equipment_vbox.add_child(spacer)

	# Defense total
	var defense_container = HBoxContainer.new()
	defense_container.alignment = BoxContainer.ALIGNMENT_CENTER
	equipment_vbox.add_child(defense_container)

	var defense_icon = create_text_label("🛡️", 18)
	defense_container.add_child(defense_icon)

	defense_label = create_text_label("Defense: 0", 16)
	defense_label.add_theme_color_override("font_color", HEADER_COLOR)
	defense_container.add_child(defense_label)

func create_character_info_panel(parent: Control) -> void:
	"""Create character info and stats panel (left column)"""
	var info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(280, 0)
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var info_style = create_inner_panel_style()
	info_panel.add_theme_stylebox_override("panel", info_style)
	parent.add_child(info_panel)

	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(info_vbox)

	# Character name + level
	var name_hbox = HBoxContainer.new()
	name_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.add_child(name_hbox)

	character_name_label = create_header_label("Adventurer")
	name_hbox.add_child(character_name_label)

	level_label = create_text_label("Level 1", 16)
	level_label.add_theme_color_override("font_color", HEADER_COLOR)
	name_hbox.add_child(level_label)

	# HP Bar
	var hp_container = VBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 2)
	info_vbox.add_child(hp_container)

	hp_label = create_text_label("HP: 100 / 100", 14)
	hp_label.add_theme_color_override("font_color", HP_COLOR)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_container.add_child(hp_label)

	# XP Bar
	var xp_container = VBoxContainer.new()
	xp_container.add_theme_constant_override("separation", 2)
	info_vbox.add_child(xp_container)

	var xp_label = create_text_label("Experience", 14)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_container.add_child(xp_label)

	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 24)
	xp_bar.show_percentage = true
	xp_bar.add_theme_color_override("font_color", TEXT_COLOR)

	# Dark wasteland styled progress bar
	var xp_bg = StyleBoxFlat.new()
	xp_bg.bg_color = SLOT_BG  # Dark leather inset
	xp_bg.border_width_left = 2
	xp_bg.border_width_right = 2
	xp_bg.border_width_top = 2
	xp_bg.border_width_bottom = 2
	xp_bg.border_color = BORDER_INNER  # Dark inner shadow
	xp_bg.corner_radius_top_left = 4
	xp_bg.corner_radius_top_right = 4
	xp_bg.corner_radius_bottom_left = 4
	xp_bg.corner_radius_bottom_right = 4

	var xp_fill = StyleBoxFlat.new()
	xp_fill.bg_color = XP_COLOR  # Muted steel blue
	xp_fill.corner_radius_top_left = 4
	xp_fill.corner_radius_top_right = 4
	xp_fill.corner_radius_bottom_left = 4
	xp_fill.corner_radius_bottom_right = 4

	xp_bar.add_theme_stylebox_override("background", xp_bg)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)

	xp_container.add_child(xp_bar)

	# Separator
	var separator1 = create_styled_separator()
	info_vbox.add_child(separator1)

	# Stats section
	var stats_header = create_header_label("Combat Stats", 16)
	info_vbox.add_child(stats_header)

	# Create stat rows - CENTERED
	var stats_center = CenterContainer.new()
	info_vbox.add_child(stats_center)

	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 4)
	stats_center.add_child(stats_grid)

	var stat_names = ["Strength", "Agility", "Vitality", "Luck"]
	for stat_name in stat_names:
		var stat_row = create_stat_row(stat_name)
		stats_grid.add_child(stat_row)
		# Store the value label (second child of the HBoxContainer)
		stat_labels[stat_name.to_lower()] = stat_row.get_child(1)

	# Separator
	var separator2 = create_styled_separator()
	info_vbox.add_child(separator2)

	# Derived stats
	var derived_header = create_header_label("Derived Stats", 16)
	info_vbox.add_child(derived_header)

	# CENTERED derived stats grid
	var derived_center = CenterContainer.new()
	info_vbox.add_child(derived_center)

	var derived_grid = GridContainer.new()
	derived_grid.columns = 2
	derived_grid.add_theme_constant_override("h_separation", 20)
	derived_grid.add_theme_constant_override("v_separation", 4)
	derived_center.add_child(derived_grid)

	var derived_names = ["Attack", "Crit Chance"]
	for derived_name in derived_names:
		var derived_label = create_text_label(derived_name + ":", 14)
		derived_grid.add_child(derived_label)

		var value_label = create_text_label("0", 14)
		value_label.add_theme_color_override("font_color", HEADER_COLOR)
		derived_grid.add_child(value_label)
		stat_labels[derived_name.to_lower().replace(" ", "_")] = value_label

	# No gold display here - moved to inventory panel

func create_inventory_panel(parent: Control) -> void:
	"""Create inventory grid + gold display (right column)"""
	var inv_panel = PanelContainer.new()
	inv_panel.custom_minimum_size = Vector2(320, 0)
	inv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var inv_style = create_inner_panel_style()
	inv_panel.add_theme_stylebox_override("panel", inv_style)
	parent.add_child(inv_panel)

	var inv_vbox = VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 12)
	inv_panel.add_child(inv_vbox)

	# Title
	var title = create_header_label("Inventory", 16)
	inv_vbox.add_child(title)

	# Center the inventory grid
	var inv_center = CenterContainer.new()
	inv_vbox.add_child(inv_center)

	# Inventory grid (4 slots for now, expandable)
	var inv_grid = GridContainer.new()
	inv_grid.columns = 4
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	inv_center.add_child(inv_grid)

	# Create inventory slots
	for i in range(InventorySystem.MAX_INVENTORY_SLOTS):
		var slot_button = create_inventory_slot(i)
		inv_grid.add_child(slot_button)
		inventory_slots.append(slot_button)

	# Add spacer to push gold to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_vbox.add_child(spacer)

	# Gold display at bottom
	var separator_gold = create_styled_separator()
	inv_vbox.add_child(separator_gold)

	var gold_container = HBoxContainer.new()
	gold_container.alignment = BoxContainer.ALIGNMENT_CENTER
	inv_vbox.add_child(gold_container)

	var gold_icon = create_text_label("💰", 18)
	gold_container.add_child(gold_icon)

	gold_label = create_text_label("0 Gold", 18)
	gold_label.add_theme_color_override("font_color", HEADER_COLOR)
	gold_container.add_child(gold_label)

func create_equipment_slot(slot_name: String, label_text: String) -> VBoxContainer:
	"""Create a single equipment slot button with drag-drop support"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Button centered in a CenterContainer
	var button_center = CenterContainer.new()
	container.add_child(button_center)

	# Use a Control wrapper for drag-drop support
	var slot_control = Control.new()
	slot_control.name = "Equip_" + slot_name
	slot_control.custom_minimum_size = Vector2(60, 60)
	slot_control.set_meta("slot_name", slot_name)
	slot_control.set_meta("slot_type", "equipment")

	# Enable drag-drop
	slot_control.set_drag_forwarding(
		Callable(self, "_get_equipment_drag_data").bind(slot_name),
		Callable(self, "_can_drop_equipment_data").bind(slot_name),
		Callable(self, "_drop_equipment_data").bind(slot_name)
	)
	button_center.add_child(slot_control)

	# Add panel for styling
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(60, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# Wasteland slot styling with deep inset
	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Add label for item text
	var label = Label.new()
	label.name = "ItemLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)  # Larger font
	label.add_theme_color_override("font_color", Color.WHITE)  # Bright white
	label.add_theme_color_override("font_outline_color", Color.BLACK)  # Black outline
	label.add_theme_constant_override("outline_size", 2)  # Outline for contrast
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap long item names
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	# Connect click event
	slot_control.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_name))

	# Label centered below button
	var slot_label = create_text_label(label_text, 11)
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(slot_label)

	return container

func create_inventory_slot(slot_index: int) -> Control:
	"""Create a single inventory slot button with drag-drop support"""
	# Create a custom control for drag-drop
	var slot_control = Control.new()
	slot_control.name = "InvSlot_" + str(slot_index)
	slot_control.custom_minimum_size = Vector2(70, 70)
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
	panel.custom_minimum_size = Vector2(70, 70)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# Wasteland slot styling with deep inset
	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Add label for item text
	var label = Label.new()
	label.name = "ItemLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)  # Larger font
	label.add_theme_color_override("font_color", Color.WHITE)  # Bright white
	label.add_theme_color_override("font_outline_color", Color.BLACK)  # Black outline
	label.add_theme_constant_override("outline_size", 2)  # Outline for contrast
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # Wrap long item names
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(label)

	# Connect click event
	slot_control.gui_input.connect(_on_inventory_slot_gui_input.bind(slot_index))

	return slot_control

func create_stat_row(stat_name: String) -> HBoxContainer:
	"""Create a row for displaying a stat with tooltip"""
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Add tooltip to the entire row
	hbox.tooltip_text = get_stat_tooltip(stat_name)
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP  # Enable mouse detection for tooltip

	var name_label = create_text_label(stat_name + ":", 14)
	hbox.add_child(name_label)

	var value_label = create_text_label("0", 14)
	value_label.add_theme_color_override("font_color", HEADER_COLOR)
	hbox.add_child(value_label)

	return hbox

func get_stat_tooltip(stat_name: String) -> String:
	"""Get tooltip description for a stat"""
	match stat_name:
		"Strength":
			return "Increases attack damage"
		"Agility":
			return "Increases attack speed and dodge chance"
		"Vitality":
			return "Increases max HP and healing effectiveness"
		"Luck":
			return "Increases critical hit chance"
		_:
			return ""

func create_header_label(text: String, size: int = 18) -> Label:
	"""Create a gold-colored header label"""
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
	"""Create a wasteland styled separator line"""
	var separator_container = MarginContainer.new()
	separator_container.add_theme_constant_override("margin_top", 8)
	separator_container.add_theme_constant_override("margin_bottom", 8)
	separator_container.add_theme_constant_override("margin_left", 20)
	separator_container.add_theme_constant_override("margin_right", 20)

	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 2)

	# Rusted metal separator
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = BORDER_COLOR  # Rusted bronze
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", sep_style)

	separator_container.add_child(separator)
	return separator_container

func create_slot_style(bg_color: Color, border_color: Color = BORDER_COLOR, border_width: int = 2, use_glow: bool = false) -> StyleBoxFlat:
	"""Create a wasteland style for equipment/inventory slots with optional rarity glow"""
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color

	# Subtle rounded corners
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	# Shadow - either outer glow for rarity or inner shadow for empty slots
	if use_glow and border_color != BORDER_INNER:
		# Subtle outer glow for items with rarity
		style.shadow_size = 3
		style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.3)
	else:
		# Deep inner shadow for inset effect (empty slots)
		style.shadow_size = 3
		style.shadow_color = BORDER_INNER

	return style

func create_inner_panel_style() -> StyleBoxFlat:
	"""Create wasteland style for inner panels"""
	var style = StyleBoxFlat.new()
	style.bg_color = SLOT_BG  # Darker leather inset

	# Rusted metal borders
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = BORDER_INNER  # Dark inner shadow

	# Subtle rounded corners
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6

	# Inset shadow effect
	style.shadow_size = 4
	style.shadow_color = Color(0, 0, 0, 0.5)

	return style

func get_rarity_glow_color(rarity_str: String) -> Color:
	"""Get subtle glow color for item rarity (muted but visible)"""
	match rarity_str.to_upper():
		"COMMON":
			return Color(0.6, 0.6, 0.6, 0.9)  # Subtle grey
		"UNCOMMON":
			return Color(0.4, 0.8, 0.4, 1.0)  # Muted green
		"RARE":
			return Color(0.4, 0.5, 0.9, 1.0)  # Muted blue
		"EPIC":
			return Color(0.7, 0.4, 0.9, 1.0)  # Muted purple
		"LEGENDARY":
			return Color(0.9, 0.6, 0.2, 1.0)  # Muted orange
		"ARTIFACT":
			return Color(0.9, 0.8, 0.3, 1.0)  # Muted gold
		_:
			return BORDER_INNER  # Default to dark border

func toggle_character_ui() -> void:
	"""Toggle character UI visibility"""
	is_visible = !is_visible
	visible = is_visible

	if is_visible:
		print("📋 Character sheet opened")
		refresh_all()
	else:
		print("📋 Character sheet closed")

func refresh_all() -> void:
	"""Refresh all UI elements"""
	refresh_character_info()
	refresh_stats()
	refresh_equipment()
	refresh_inventory()

func refresh_character_info() -> void:
	"""Update character name, level, HP, XP, gold"""
	if character_name_label:
		character_name_label.text = "Adventurer"  # TODO: Add character name to CharacterStats

	if level_label:
		level_label.text = "Level " + str(CharacterStats.level)

	if hp_label:
		var player = get_tree().get_first_node_in_group("player")
		if player:
			hp_label.text = "HP: %d / %d" % [int(player.current_health), int(player.max_health)]
		else:
			var max_hp = CharacterStats.get_max_health()
			hp_label.text = "HP: %d / %d" % [int(max_hp), int(max_hp)]

	if xp_bar:
		var xp_percent = 0.0
		if CharacterStats.experience_to_next_level > 0:
			xp_percent = float(CharacterStats.experience) / float(CharacterStats.experience_to_next_level) * 100.0
		xp_bar.value = xp_percent

	if gold_label:
		gold_label.text = "%d Gold" % CharacterStats.gold

func refresh_stats() -> void:
	"""Update all stat displays"""
	if stat_labels.has("strength"):
		stat_labels["strength"].text = str(CharacterStats.strength)
	if stat_labels.has("agility"):
		stat_labels["agility"].text = str(CharacterStats.agility)
	if stat_labels.has("vitality"):
		stat_labels["vitality"].text = str(CharacterStats.vitality)
	if stat_labels.has("luck"):
		stat_labels["luck"].text = str(CharacterStats.luck)

	# Derived stats
	if stat_labels.has("attack"):
		stat_labels["attack"].text = "%.1f" % CharacterStats.get_base_damage()
	if stat_labels.has("crit_chance"):
		stat_labels["crit_chance"].text = "%.1f%%" % (CharacterStats.get_base_crit_chance() * 100.0)

	# Update defense
	if defense_label:
		var defense = CharacterStats.get_total_defense()
		var equipped = CharacterStats.get_equipped_armor_count()
		defense_label.text = "Defense: %d (%d/5 equipped)" % [defense, equipped]

func refresh_equipment() -> void:
	"""Update equipment slot displays"""
	for slot_name in equipment_slots:
		var slot_container = equipment_slots[slot_name]  # VBoxContainer
		var button_center = slot_container.get_child(0)  # CenterContainer
		var slot_control = button_center.get_child(0)  # Control wrapper

		# Get the label from the slot control
		var panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			continue

		var label = panel.get_node_or_null("ItemLabel")
		if not label:
			continue

		# Special handling for mainhand - check equipped_weapon instead of equipped_armor
		var armor_item = null
		if slot_name == "mainhand" and CharacterStats.equipped_weapon:
			# Convert Weapon resource to dict for display
			var weapon = CharacterStats.equipped_weapon
			armor_item = {
				"name": weapon.weapon_name,
				"description": weapon.description,
				"type": "weapon",
				"base_damage": weapon.base_damage,
				"attack_speed_bonus": weapon.attack_speed_bonus,
				"crit_chance_bonus": weapon.crit_chance_bonus,
				"rarity": Weapon.Rarity.keys()[weapon.rarity]
			}
		else:
			armor_item = CharacterStats.equipped_armor[slot_name]

		if armor_item:
			label.text = armor_item.get("name", "???")

			# Apply subtle rarity glow to slot border
			var rarity = armor_item.get("rarity", "COMMON")
			var glow_color = get_rarity_glow_color(rarity)
			var glow_style = create_slot_style(SLOT_BG, glow_color, 3, true)  # Subtle border + glow
			panel.add_theme_stylebox_override("panel", glow_style)

			var tooltip = armor_item.get("description", "")

			# Weapon stats (for mainhand/offhand)
			if armor_item.get("type") == "weapon":
				if armor_item.has("base_damage"):
					tooltip += "\nDamage: +%.1f" % armor_item.get("base_damage", 0)
				if armor_item.has("attack_speed_bonus"):
					var speed_bonus = armor_item.get("attack_speed_bonus", 0.0)
					if speed_bonus != 0:
						tooltip += "\nAttack Speed: %+.1f%%" % (speed_bonus * 100)
				if armor_item.has("crit_chance_bonus"):
					var crit_bonus = armor_item.get("crit_chance_bonus", 0.0)
					if crit_bonus != 0:
						tooltip += "\nCrit Chance: +%.1f%%" % (crit_bonus * 100)
			# Armor stats
			elif armor_item.has("defense"):
				tooltip += "\nDefense: +%d" % armor_item.get("defense", 0)

			slot_control.tooltip_text = tooltip
		else:
			label.text = ""
			slot_control.tooltip_text = "Empty " + slot_name + " slot"
			# Reset to default style when empty
			var default_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
			panel.add_theme_stylebox_override("panel", default_style)

func refresh_inventory() -> void:
	"""Update inventory slot displays"""
	print("🔄 CharacterUI: Refreshing inventory...")
	print("   inventory_slots.size() = %d" % inventory_slots.size())
	print("   InventorySystem.inventory_items.size() = %d" % InventorySystem.inventory_items.size())
	for i in range(inventory_slots.size()):
		var slot_control = inventory_slots[i]
		var item = InventorySystem.get_item(i)

		# Get the label from the slot control
		var panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			print("  ❌ Slot %d: No panel found" % i)
			continue

		var label = panel.get_node_or_null("ItemLabel")
		if not label:
			print("  ❌ Slot %d: No label found" % i)
			continue

		if item and item.size() > 0:
			var item_name = item.get("name", "???")
			print("  ✅ Slot %d: Found item: %s" % [i, item_name])
			print("    Setting label text to: '%s'" % item_name)
			var quantity = item.get("quantity", 1)
			var is_stackable = item.get("stackable", false)

			if is_stackable and quantity > 1:
				label.text = "%s x%d" % [item_name, quantity]
			else:
				label.text = item_name

			# Apply subtle rarity glow to slot border
			var rarity = item.get("rarity", "COMMON")
			var glow_color = get_rarity_glow_color(rarity)
			var glow_style = create_slot_style(SLOT_BG, glow_color, 3, true)  # Subtle border + glow
			panel.add_theme_stylebox_override("panel", glow_style)

			print("    Label text set to: '%s' (visible: %s)" % [label.text, label.visible])

			var tooltip = item.get("description", "")

			# Weapon stats
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

			# Armor stats
			if item.has("defense"):
				tooltip += "\nDefense: +%d" % item.get("defense", 0)

			# Value
			if item.has("value"):
				tooltip += "\nValue: %d gold" % item.get("value", 0)

			slot_control.tooltip_text = tooltip
		else:
			print("  ⬜ Slot %d: Empty" % i)
			label.text = ""
			slot_control.tooltip_text = "Empty slot"
			# Reset to default style when empty
			var default_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
			panel.add_theme_stylebox_override("panel", default_style)

func _on_equipment_slot_gui_input(event: InputEvent, slot_name: String) -> void:
	"""Handle GUI input on equipment slot (double-click or right-click to unequip)"""
	if event is InputEventMouseButton and event.pressed:
		# Double-click or right-click to unequip
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			# Special handling for mainhand - check equipped_weapon
			if slot_name == "mainhand" and CharacterStats.equipped_weapon:
				CharacterStats.unequip_weapon()
				refresh_all()
				print("✅ Unequipped weapon (double-click)")
			else:
				var armor_item = CharacterStats.equipped_armor[slot_name]
				if armor_item:
					if CharacterStats.unequip_armor(slot_name):
						refresh_all()
						print("✅ Unequipped %s (double-click)" % armor_item.get("name", "Unknown"))
				else:
					print("No armor equipped in %s slot" % slot_name)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Special handling for mainhand - check equipped_weapon
			if slot_name == "mainhand" and CharacterStats.equipped_weapon:
				CharacterStats.unequip_weapon()
				refresh_all()
				print("✅ Unequipped weapon (right-click)")
			else:
				var armor_item = CharacterStats.equipped_armor[slot_name]
				if armor_item:
					if CharacterStats.unequip_armor(slot_name):
						refresh_all()
						print("✅ Unequipped %s (right-click)" % armor_item.get("name", "Unknown"))
				else:
					print("No armor equipped in %s slot" % slot_name)

func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	"""Handle GUI input on inventory slot (double-click or right-click to equip)"""
	if event is InputEventMouseButton and event.pressed:
		# Double-click or right-click to equip
		if (event.button_index == MOUSE_BUTTON_LEFT and event.double_click) or event.button_index == MOUSE_BUTTON_RIGHT:
			var item = InventorySystem.get_item(slot_index)

			if item and item.size() > 0:
				var action = "double-click" if event.double_click else "right-click"

				# Check if it's a weapon
				if item.get("type", "") == "weapon" and item.get("slot", "") == "mainhand":
					# Convert dict to Weapon resource and equip
					var weapon = dict_to_weapon(item)
					if weapon:
						CharacterStats.equip_weapon(weapon)
						# Remove from inventory
						InventorySystem.remove_item(slot_index)
						refresh_all()
						print("✅ Equipped weapon %s (%s)" % [item.get("name", "Unknown"), action])
					else:
						print("❌ Failed to create weapon resource for %s" % item.get("name", "Unknown"))
				# Check if it's armor (has a slot)
				elif item.has("slot") and item.get("slot", "") in CharacterStats.equipped_armor:
					# Try to equip armor
					if CharacterStats.equip_armor(item):
						# Remove from inventory
						InventorySystem.remove_item(slot_index)
						refresh_all()
						print("✅ Equipped armor %s (%s)" % [item.get("name", "Unknown"), action])
				else:
					print("🖱️ Item not equippable: %s" % item.get("name", "Unknown"))
			else:
				print("🖱️ Empty slot %d" % slot_index)

func dict_to_weapon(item_dict: Dictionary) -> Weapon:
	"""Convert a weapon dictionary (from inventory) to a Weapon resource"""
	var weapon = Weapon.new()

	weapon.weapon_name = item_dict.get("name", "Unknown")
	weapon.weapon_type = item_dict.get("weapon_type", "sword")
	weapon.damage_type = "unified"  # Unified damage system
	weapon.description = item_dict.get("description", "")
	weapon.base_damage = item_dict.get("base_damage", 5.0)

	# Convert attack_speed category to numeric multiplier
	var attack_speed_category = item_dict.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30  # 30% faster
		"slow":
			weapon.attack_speed_bonus = 0.30   # 30% slower
		_:  # "medium" or any other value
			weapon.attack_speed_bonus = 0.0

	# Crit chance
	weapon.crit_chance_bonus = item_dict.get("crit_chance", 0.0)
	weapon.required_level = item_dict.get("required_level", 1)
	weapon.can_trade = item_dict.get("can_trade", true)

	# Set rarity
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
	print("🖱️ _get_inventory_drag_data called for slot %d" % slot_index)
	var item = InventorySystem.get_item(slot_index)
	if not item or item.is_empty():
		print("  ❌ No item to drag")
		return null

	print("  ✅ Starting drag for: %s" % item.get("name", "Item"))

	# Create drag preview
	var preview = Label.new()
	preview.text = item.get("name", "Item")
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color.GOLD)
	preview.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	# Get the slot control and set preview on it
	var slot_control = inventory_slots[slot_index]
	slot_control.set_drag_preview(preview)

	# Return drag data
	return {
		"source_type": "inventory",
		"source_index": slot_index,
		"item": item
	}

func _can_drop_inventory_data(at_position: Vector2, data: Variant, slot_index: int) -> bool:
	"""Check if data can be dropped on this inventory slot"""
	if not data is Dictionary:
		return false

	# Can always drop items into inventory
	return data.has("item")

func _drop_inventory_data(at_position: Vector2, data: Dictionary, slot_index: int) -> void:
	"""Handle dropping data on an inventory slot"""
	print("📥 _drop_inventory_data called for slot %d" % slot_index)
	if not data.has("item"):
		return

	var source_type = data.get("source_type", "")
	var source_index = data.get("source_index", -1)
	var dragged_item = data.get("item", {})

	if source_type == "inventory":
		# Swap inventory items
		if source_index != slot_index:
			var target_item = InventorySystem.get_item(slot_index)

			# Remove both items
			InventorySystem.set_item(source_index, {})
			InventorySystem.set_item(slot_index, {})

			# Swap them
			InventorySystem.set_item(slot_index, dragged_item)
			if target_item and not target_item.is_empty():
				InventorySystem.set_item(source_index, target_item)

			refresh_all()
			print("🔄 Swapped inventory items")

	elif source_type == "equipment":
		# Move from equipment to inventory
		var source_slot_name = data.get("source_slot_name", "")
		if source_slot_name:
			# Special handling for mainhand weapon
			if source_slot_name == "mainhand" and CharacterStats.equipped_weapon:
				CharacterStats.unequip_weapon()
				refresh_all()
				print("✅ Unequipped %s to inventory" % dragged_item.get("name", "Unknown"))
			# Unequip armor
			elif CharacterStats.unequip_armor(source_slot_name):
				# Item is now in inventory via unequip_armor
				refresh_all()
				print("✅ Unequipped %s to inventory" % dragged_item.get("name", "Unknown"))

func _get_equipment_drag_data(at_position: Vector2, slot_name: String) -> Variant:
	"""Start dragging an equipped item"""
	# Special handling for mainhand - check equipped_weapon
	var armor_item = null
	if slot_name == "mainhand" and CharacterStats.equipped_weapon:
		# Convert Weapon resource to dict for dragging
		var weapon = CharacterStats.equipped_weapon
		armor_item = {
			"name": weapon.weapon_name,
			"description": weapon.description,
			"type": "weapon",
			"slot": "mainhand",
			"weapon_type": weapon.weapon_type,
			"base_damage": weapon.base_damage,
			"attack_speed": "medium",  # Will be converted properly on equip
			"crit_chance": weapon.crit_chance_bonus,
			"rarity": Weapon.Rarity.keys()[weapon.rarity]
		}
	else:
		armor_item = CharacterStats.equipped_armor[slot_name]

	if not armor_item or (armor_item is Dictionary and armor_item.is_empty()):
		return null

	# Create drag preview
	var preview = Label.new()
	preview.text = armor_item.get("name", "Item")
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color.GOLD)
	preview.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	# Get the equipment slot control and set preview on it
	var slot_container = equipment_slots[slot_name]  # VBoxContainer
	var button_center = slot_container.get_child(0)  # CenterContainer
	var slot_control = button_center.get_child(0)  # Control wrapper
	slot_control.set_drag_preview(preview)

	# Return drag data
	return {
		"source_type": "equipment",
		"source_slot_name": slot_name,
		"item": armor_item
	}

func _can_drop_equipment_data(at_position: Vector2, data: Variant, slot_name: String) -> bool:
	"""Check if data can be dropped on this equipment slot"""
	if not data is Dictionary:
		return false

	if not data.has("item"):
		return false

	var item = data.get("item", {})

	# Check if item has a slot type
	if not item.has("slot"):
		return false

	# Check if item's slot matches this equipment slot
	var item_slot = item.get("slot", "")
	if item_slot != slot_name:
		return false

	# No level requirement - twinking allowed!
	return true

func _drop_equipment_data(at_position: Vector2, data: Dictionary, slot_name: String) -> void:
	"""Handle dropping data on an equipment slot"""
	if not data.has("item"):
		return

	var source_type = data.get("source_type", "")
	var dragged_item = data.get("item", {})

	# Validate the drop
	var item_slot = dragged_item.get("slot", "")
	if item_slot != slot_name:
		print("❌ Cannot equip %s in %s slot (requires %s slot)" % [dragged_item.get("name", ""), slot_name, item_slot])
		return

	if source_type == "inventory":
		# Equip from inventory
		var source_index = data.get("source_index", -1)
		if source_index >= 0:
			var equipped = false

			# Check if it's a weapon
			if dragged_item.get("type", "") == "weapon" and slot_name == "mainhand":
				# Convert dict to Weapon resource and equip
				var weapon = dict_to_weapon(dragged_item)
				if weapon:
					CharacterStats.equip_weapon(weapon)
					equipped = true
			# Otherwise it's armor
			else:
				equipped = CharacterStats.equip_armor(dragged_item)

			if equipped:
				# Remove from inventory
				InventorySystem.remove_item(source_index)
				refresh_all()
				print("✅ Equipped %s to %s" % [dragged_item.get("name", "Unknown"), slot_name])
			else:
				print("❌ Failed to equip %s" % dragged_item.get("name", "Unknown"))

	elif source_type == "equipment":
		# Swap equipment
		var source_slot_name = data.get("source_slot_name", "")
		if source_slot_name and source_slot_name != slot_name:
			var target_item = CharacterStats.equipped_armor[slot_name]

			# Unequip both items
			CharacterStats.unequip_armor(source_slot_name)
			if target_item:
				CharacterStats.unequip_armor(slot_name)

			# Equip them in swapped positions
			CharacterStats.equip_armor(dragged_item)
			if target_item:
				CharacterStats.equip_armor(target_item)

			refresh_all()
			print("🔄 Swapped equipment slots")

# ============================================
# DROP ZONE (DELETE ITEMS WITH CONFIRMATION)
# ============================================

func _get_drop_zone_drag_data(at_position: Vector2) -> Variant:
	"""Drop zone can't be dragged"""
	return null

func _can_drop_on_drop_zone(at_position: Vector2, data: Variant) -> bool:
	"""Accept any item drop on drop zone (outside UI panel)"""
	print("🔍 _can_drop_on_drop_zone called at position: %s" % at_position)

	if not data is Dictionary:
		print("  ❌ Data is not a Dictionary")
		return false

	if not data.has("item"):
		print("  ❌ No item in data")
		return false

	# Check if drop position is outside the main panel
	if main_panel:
		var panel_rect = main_panel.get_global_rect()
		var is_outside = not panel_rect.has_point(at_position)
		print("  Drop position: %s, Panel rect: %s, Outside: %s" % [at_position, panel_rect, is_outside])
		return is_outside

	return false

func _drop_on_drop_zone(at_position: Vector2, data: Dictionary) -> void:
	"""Handle dropping item outside UI - show confirmation dialog"""
	print("🗑️ _drop_on_drop_zone called - showing confirmation")

	if not data.has("item"):
		print("  ❌ No item in data")
		return

	# Store the deletion data for confirmation
	pending_delete_data = data

	var item_name = data.get("item", {}).get("name", "Unknown")

	# Show confirmation dialog
	var dialog = get_node_or_null("DeleteConfirmDialog")
	if dialog:
		dialog.dialog_text = "Are you sure you want to delete '%s'?" % item_name
		dialog.popup_centered()
		print("  ✅ Showing delete confirmation for: %s" % item_name)
	else:
		print("  ❌ DeleteConfirmDialog not found!")

func _on_delete_confirmed() -> void:
	"""Handle deletion confirmation - actually delete the item"""
	print("✅ Delete confirmed!")

	if pending_delete_data.is_empty():
		print("  ❌ No pending deletion data")
		return

	var source_type = pending_delete_data.get("source_type", "")
	var dragged_item = pending_delete_data.get("item", {})
	var item_name = dragged_item.get("name", "Unknown")

	print("  Deleting: %s from %s" % [item_name, source_type])

	if source_type == "inventory":
		# Remove from inventory
		var source_index = pending_delete_data.get("source_index", -1)
		if source_index >= 0:
			InventorySystem.remove_item(source_index)
			refresh_all()
			print("🗑️ Deleted %s from inventory" % item_name)

	elif source_type == "equipment":
		# Unequip and delete (don't add to inventory)
		var source_slot_name = pending_delete_data.get("source_slot_name", "")
		if source_slot_name:
			# Directly remove from equipped_armor without adding to inventory
			CharacterStats.equipped_armor[source_slot_name] = null
			CharacterStats.armor_unequipped.emit(source_slot_name, {})
			refresh_all()
			print("🗑️ Deleted %s from equipment" % item_name)

	# Clear pending data
	pending_delete_data = {}

func _on_stats_changed(_level: int = 0) -> void:
	"""Called when character stats change"""
	refresh_all()

func _on_xp_changed(_amount: int, _total: int) -> void:
	"""Called when XP changes"""
	refresh_character_info()

func _on_gold_changed(_amount: int, _total: int) -> void:
	"""Called when gold changes"""
	if gold_label:
		gold_label.text = "%d Gold" % _total

func _on_armor_changed(_slot: String, _armor: Dictionary) -> void:
	"""Called when armor is equipped/unequipped"""
	refresh_all()

func _on_inventory_changed() -> void:
	"""Called when inventory changes"""
	print("📢 CharacterUI._on_inventory_changed() called!")
	refresh_inventory()
