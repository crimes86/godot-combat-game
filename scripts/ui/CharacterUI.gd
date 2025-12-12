extends CanvasLayer

## Character UI - Character sheet with stats and equipment
## Press C to toggle (Inventory is separate - press I)

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_EQUIP: bool = true  # Debug equipping/unequipping from character sheet

var is_visible: bool = false

# UI References
var main_panel: PanelContainer
var equipment_slots: Dictionary = {}  # slot_name: HBoxContainer (contains slot icon Control + label)
var tool_slots: Dictionary = {}  # tool_name: HBoxContainer (axe, pickaxe)
var stat_labels: Dictionary = {}  # stat_name: Label
var character_name_label: Label
var level_label: Label
var xp_bar: ProgressBar
var hp_label: Label
var defense_label: Label

# UI colors - use UITheme singleton for consistency
# Local aliases for convenience
var BG_COLOR: Color:
	get: return UITheme.BG_COLOR_TRANSPARENT
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR
var BORDER_INNER: Color:
	get: return UITheme.BORDER_INNER
var ACCENT_COLOR: Color:
	get: return UITheme.ACCENT_COLOR
var TEXT_COLOR: Color:
	get: return UITheme.TEXT_COLOR
var HEADER_COLOR: Color:
	get: return UITheme.HEADER_COLOR
var HP_COLOR: Color:
	get: return UITheme.HP_COLOR
var XP_COLOR: Color:
	get: return UITheme.XP_COLOR
var SLOT_BG: Color:
	get: return UITheme.SLOT_BG
var BUFF_COLOR: Color:
	get: return UITheme.BUFF_COLOR
var DEBUFF_COLOR: Color:
	get: return UITheme.DEBUFF_COLOR

# Animation timing (snappy for fast-paced combat)
const ANIM_SPEED = 0.1

# Blocked slot color (for 2h weapon blocking offhand)
const BLOCKED_SLOT_COLOR = Color(0.2, 0.2, 0.2, 0.8)

func _ready() -> void:

	# Set layer above game prompts (campfire hints are at 100)
	layer = 110

	# Start hidden
	visible = false

	# Create UI
	create_character_ui()

	# Connect to signals
	CharacterStats.level_up.connect(_on_stats_changed)
	CharacterStats.experience_gained.connect(_on_xp_changed)
	CharacterStats.armor_equipped.connect(_on_armor_changed)
	CharacterStats.armor_unequipped.connect(_on_armor_changed)
	CharacterStats.weapon_equipped.connect(_on_weapon_changed)
	CharacterStats.weapon_unequipped.connect(_on_weapon_changed)
	InventorySystem.axe_equipped.connect(_on_tool_changed)
	InventorySystem.axe_unequipped.connect(_on_tool_changed)
	InventorySystem.pickaxe_equipped.connect(_on_tool_changed)
	InventorySystem.pickaxe_unequipped.connect(_on_tool_changed)

	# Initial update
	refresh_all()

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	if CharacterStats.level_up.is_connected(_on_stats_changed):
		CharacterStats.level_up.disconnect(_on_stats_changed)
	if CharacterStats.experience_gained.is_connected(_on_xp_changed):
		CharacterStats.experience_gained.disconnect(_on_xp_changed)
	if CharacterStats.armor_equipped.is_connected(_on_armor_changed):
		CharacterStats.armor_equipped.disconnect(_on_armor_changed)
	if CharacterStats.armor_unequipped.is_connected(_on_armor_changed):
		CharacterStats.armor_unequipped.disconnect(_on_armor_changed)
	if CharacterStats.weapon_equipped.is_connected(_on_weapon_changed):
		CharacterStats.weapon_equipped.disconnect(_on_weapon_changed)
	if CharacterStats.weapon_unequipped.is_connected(_on_weapon_changed):
		CharacterStats.weapon_unequipped.disconnect(_on_weapon_changed)
	if InventorySystem.axe_equipped.is_connected(_on_tool_changed):
		InventorySystem.axe_equipped.disconnect(_on_tool_changed)
	if InventorySystem.axe_unequipped.is_connected(_on_tool_changed):
		InventorySystem.axe_unequipped.disconnect(_on_tool_changed)
	if InventorySystem.pickaxe_equipped.is_connected(_on_tool_changed):
		InventorySystem.pickaxe_equipped.disconnect(_on_tool_changed)
	if InventorySystem.pickaxe_unequipped.is_connected(_on_tool_changed):
		InventorySystem.pickaxe_unequipped.disconnect(_on_tool_changed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_visible:
			toggle_character_ui()
			get_viewport().set_input_as_handled()

func create_character_ui() -> void:
	"""Create character sheet with stats and equipment (2 columns)"""

	# Main panel container - centered (narrower for 2 columns)
	main_panel = PanelContainer.new()
	main_panel.name = "CharacterPanel"

	# Center the panel - 2-column layout
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(620, 600)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -310
	main_panel.offset_right = 310
	main_panel.offset_top = -300
	main_panel.offset_bottom = 300
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

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

	# Main horizontal layout (2 columns: Stats | Equipment) with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	main_panel.add_child(margin)

	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_hbox)

	# LEFT COLUMN: Character info + stats
	create_character_info_panel(main_hbox)

	# RIGHT COLUMN: Equipment slots
	create_equipment_panel(main_hbox)

	add_child(main_panel)


func create_equipment_panel(parent: Control) -> void:
	"""Create equipment panel with body-shaped paperdoll layout"""
	var equipment_panel = PanelContainer.new()
	equipment_panel.custom_minimum_size = Vector2(320, 0)
	equipment_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var equip_style = create_inner_panel_style()
	equipment_panel.add_theme_stylebox_override("panel", equip_style)
	parent.add_child(equipment_panel)

	var equipment_vbox = VBoxContainer.new()
	equipment_vbox.add_theme_constant_override("separation", 2)
	equipment_panel.add_child(equipment_vbox)

	# Title
	var title = create_header_label("Equipment")
	equipment_vbox.add_child(title)

	# Body-shaped grid layout for equipment
	# Layout:
	#        [HEAD]
	#        [BACK]
	#   [MH] [CHEST] [OH]
	#        [ARMS]
	#       [HANDS]
	#        [LEGS]
	#        [FEET]

	# Row 1: Head (centered)
	var row1 = CenterContainer.new()
	equipment_vbox.add_child(row1)
	var head_slot = create_equipment_slot_compact("head", "Head")
	row1.add_child(head_slot)
	equipment_slots["head"] = head_slot

	# Row 1.5: Back/Cape slot (centered, between head and chest)
	var row_back = CenterContainer.new()
	equipment_vbox.add_child(row_back)
	var back_slot = create_equipment_slot_compact("back", "Back")
	row_back.add_child(back_slot)
	equipment_slots["back"] = back_slot

	# Row 2: Mainhand - Chest - Offhand (horizontal row)
	var row2_center = CenterContainer.new()
	equipment_vbox.add_child(row2_center)

	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	row2_center.add_child(row2)

	var mainhand_slot = create_equipment_slot_compact("mainhand", "Main")
	row2.add_child(mainhand_slot)
	equipment_slots["mainhand"] = mainhand_slot

	var chest_slot = create_equipment_slot_compact("chest", "Chest")
	row2.add_child(chest_slot)
	equipment_slots["chest"] = chest_slot

	var offhand_slot = create_equipment_slot_compact("offhand", "Off")
	row2.add_child(offhand_slot)
	equipment_slots["offhand"] = offhand_slot

	# Row 3: Arms (centered)
	var row3 = CenterContainer.new()
	equipment_vbox.add_child(row3)
	var arms_slot = create_equipment_slot_compact("arms", "Arms")
	row3.add_child(arms_slot)
	equipment_slots["arms"] = arms_slot

	# Row 4: Hands (centered)
	var row4 = CenterContainer.new()
	equipment_vbox.add_child(row4)
	var hands_slot = create_equipment_slot_compact("hands", "Hands")
	row4.add_child(hands_slot)
	equipment_slots["hands"] = hands_slot

	# Row 5: Legs + Feet side by side (smaller items)
	var row5_center = CenterContainer.new()
	equipment_vbox.add_child(row5_center)

	var row5 = HBoxContainer.new()
	row5.add_theme_constant_override("separation", 4)
	row5_center.add_child(row5)

	var legs_slot = create_equipment_slot_compact("legs", "Legs")
	row5.add_child(legs_slot)
	equipment_slots["legs"] = legs_slot

	var feet_slot = create_equipment_slot_compact("feet", "Feet")
	row5.add_child(feet_slot)
	equipment_slots["feet"] = feet_slot

	# Defense total
	var defense_container = HBoxContainer.new()
	defense_container.alignment = BoxContainer.ALIGNMENT_CENTER
	equipment_vbox.add_child(defense_container)

	defense_label = create_text_label("Defense: 0", 14)
	defense_label.add_theme_color_override("font_color", HEADER_COLOR)
	defense_container.add_child(defense_label)

	# Separator before tools
	var separator_tools = create_styled_separator()
	equipment_vbox.add_child(separator_tools)

	# Tools section - horizontal layout
	var tools_header = create_header_label("Tools", 14)
	equipment_vbox.add_child(tools_header)

	var tools_row = HBoxContainer.new()
	tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tools_row.add_theme_constant_override("separation", 12)
	equipment_vbox.add_child(tools_row)

	var axe_slot = create_equipment_slot_compact("axe", "Axe", true)
	tools_row.add_child(axe_slot)
	tool_slots["axe"] = axe_slot

	var pickaxe_slot = create_equipment_slot_compact("pickaxe", "Pick", true)
	tools_row.add_child(pickaxe_slot)
	tool_slots["pickaxe"] = pickaxe_slot

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

func create_equipment_slot_compact(slot_name: String, label_text: String, is_tool: bool = false) -> Control:
	"""Create a compact equipment slot with small icon + text label below"""
	# Main container - vertical layout with icon box and label
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.custom_minimum_size = Vector2(76, 76)
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Slot control wrapper for drag-drop
	var slot_control = Control.new()
	slot_control.name = "Slot_" + slot_name
	slot_control.custom_minimum_size = Vector2(56, 56)
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_control.set_meta("slot_name", slot_name)
	slot_control.set_meta("slot_type", "tool" if is_tool else "equipment")

	# Enable drag-drop based on type
	if is_tool:
		slot_control.set_drag_forwarding(
			Callable(self, "_get_tool_drag_data").bind(slot_name),
			Callable(self, "_can_drop_tool_data").bind(slot_name),
			Callable(self, "_drop_tool_data").bind(slot_name)
		)
		slot_control.gui_input.connect(_on_tool_slot_gui_input.bind(slot_name))
	else:
		slot_control.set_drag_forwarding(
			Callable(self, "_get_equipment_drag_data").bind(slot_name),
			Callable(self, "_can_drop_equipment_data").bind(slot_name),
			Callable(self, "_drop_equipment_data").bind(slot_name)
		)
		slot_control.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_name))

	# Panel for slot styling
	var panel = PanelContainer.new()
	panel.name = "SlotPanel"
	panel.custom_minimum_size = Vector2(56, 56)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style)

	# Center for icon
	var icon_center = CenterContainer.new()
	icon_center.name = "CenterContainer"
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon_center)

	# Icon (matched to inventory size)
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	icon_center.add_child(icon)

	# Item name label (hidden when empty, shown below icon)
	var item_label = Label.new()
	item_label.name = "ItemLabel"
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.add_theme_font_size_override("font_size", 8)
	item_label.add_theme_color_override("font_color", Color.WHITE)
	item_label.add_theme_color_override("font_outline_color", Color.BLACK)
	item_label.add_theme_constant_override("outline_size", 1)
	item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_label.visible = false
	icon_center.add_child(item_label)

	# Blocked overlay (X) for when slot is disabled (e.g., offhand with 2h weapon)
	var blocked_label = Label.new()
	blocked_label.name = "BlockedOverlay"
	blocked_label.text = "X"
	blocked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blocked_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	blocked_label.add_theme_font_size_override("font_size", 28)
	blocked_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.2, 0.9))
	blocked_label.add_theme_color_override("font_outline_color", Color.BLACK)
	blocked_label.add_theme_constant_override("outline_size", 2)
	blocked_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocked_label.visible = false
	blocked_label.custom_minimum_size = Vector2(52, 52)
	icon_center.add_child(blocked_label)

	# Center the slot control
	var slot_center = CenterContainer.new()
	slot_center.add_child(slot_control)
	container.add_child(slot_center)

	# Slot type label below (always visible)
	var type_label = Label.new()
	type_label.name = "SlotTypeLabel"
	type_label.text = label_text
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 9)
	type_label.add_theme_color_override("font_color", ACCENT_COLOR)
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(type_label)

	return container

func create_equipment_slot(slot_name: String, label_text: String) -> HBoxContainer:
	"""Create a single equipment slot button with drag-drop support (legacy)"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2(200, 60)  # Fixed width so all slots align

	# Use a Control wrapper for drag-drop support
	var slot_control = Control.new()
	slot_control.name = "Equip_" + slot_name
	slot_control.custom_minimum_size = Vector2(60, 60)
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we receive input
	slot_control.set_meta("slot_name", slot_name)
	slot_control.set_meta("slot_type", "equipment")

	# Enable drag-drop
	slot_control.set_drag_forwarding(
		Callable(self, "_get_equipment_drag_data").bind(slot_name),
		Callable(self, "_can_drop_equipment_data").bind(slot_name),
		Callable(self, "_drop_equipment_data").bind(slot_name)
	)
	container.add_child(slot_control)

	# Add panel for styling
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(60, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# Wasteland slot styling with deep inset
	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Center container for icon and label
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# VBox to stack icon and label
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Add icon texture rect
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false  # Hidden until we have an icon
	vbox.add_child(icon)

	# Add label for item text (fallback when no icon)
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
	label.clip_text = true
	label.custom_minimum_size = Vector2(56, 0)  # Limit width to slot size
	vbox.add_child(label)

	# Connect click event
	slot_control.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_name))

	# Label to the right of button
	var slot_label = create_text_label(label_text, 11)
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(slot_label)

	return container

func create_tool_slot(tool_name: String, label_text: String) -> HBoxContainer:
	"""Create a single tool slot button with drag-drop support"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2(200, 60)  # Fixed width so all slots align

	# Use a Control wrapper for drag-drop support
	var slot_control = Control.new()
	slot_control.name = "Tool_" + tool_name
	slot_control.custom_minimum_size = Vector2(60, 60)
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we receive input
	slot_control.set_meta("tool_name", tool_name)
	slot_control.set_meta("slot_type", "tool")

	# Enable drag-drop
	slot_control.set_drag_forwarding(
		Callable(self, "_get_tool_drag_data").bind(tool_name),
		Callable(self, "_can_drop_tool_data").bind(tool_name),
		Callable(self, "_drop_tool_data").bind(tool_name)
	)
	container.add_child(slot_control)

	# Add panel for styling
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(60, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# Wasteland slot styling with deep inset
	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Center container for icon and label
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# VBox to stack icon and label
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Add icon texture rect
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false  # Hidden until we have an icon
	vbox.add_child(icon)

	# Add label for item text (fallback when no icon)
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
	label.clip_text = true
	label.custom_minimum_size = Vector2(56, 0)  # Limit width to slot size
	vbox.add_child(label)

	# Connect click event
	slot_control.gui_input.connect(_on_tool_slot_gui_input.bind(tool_name))

	# Label to the right of button
	var slot_label = create_text_label(label_text, 11)
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(slot_label)

	return container

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
			return UITheme.RARITY_COMMON
		"UNCOMMON":
			return UITheme.RARITY_UNCOMMON
		"RARE":
			return UITheme.RARITY_RARE
		"EPIC":
			return UITheme.RARITY_EPIC
		"LEGENDARY":
			return UITheme.RARITY_LEGENDARY
		"ARTIFACT":
			return UITheme.RARITY_MYTHIC
		_:
			return UITheme.BORDER_INNER

func toggle_character_ui() -> void:
	"""Toggle character UI visibility"""
	is_visible = !is_visible
	visible = is_visible

	# Play character sheet open/close sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_character_sheet_sound()

	if is_visible:
		refresh_all()

func refresh_all() -> void:
	"""Refresh all UI elements"""
	refresh_character_info()
	refresh_stats()
	refresh_equipment()
	refresh_tools()

func refresh_character_info() -> void:
	"""Update character name, level, HP, XP, gold"""
	if character_name_label:
		var player_name = "Adventurer"
		if NetworkManager and NetworkManager.player_name != "":
			player_name = NetworkManager.player_name
		character_name_label.text = player_name

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

func is_offhand_blocked() -> bool:
	"""Check if offhand slot is blocked by a 2-handed weapon in mainhand"""
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_two_handed:
		return true
	return false

func refresh_equipment() -> void:
	"""Update equipment slot displays"""
	for slot_name in equipment_slots:
		var slot_container = equipment_slots[slot_name]

		# Find the slot_control and panel using recursive search (works for both old and new layouts)
		var slot_control = _find_node_by_prefix(slot_container, "Slot_")
		if not slot_control:
			slot_control = _find_node_by_prefix(slot_container, "Equip_")
		if not slot_control:
			continue

		# Find panel
		var panel = slot_control.get_node_or_null("SlotPanel")
		if not panel:
			panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			continue

		# Get icon and label nodes
		var icon_rect: TextureRect = _find_node_recursive(slot_container, "ItemIcon")
		var label: Label = _find_node_recursive(slot_container, "ItemLabel")
		var blocked_overlay: Label = _find_node_recursive(slot_container, "BlockedOverlay")

		if not label:
			continue

		# Check if offhand slot is blocked by 2h weapon
		if slot_name == "offhand" and is_offhand_blocked():
			# Show blocked X overlay
			if blocked_overlay:
				blocked_overlay.visible = true
			if icon_rect:
				icon_rect.visible = false
			label.visible = false
			# Apply blocked style (dark/grayed out)
			var blocked_style = create_slot_style(BLOCKED_SLOT_COLOR, Color(0.3, 0.1, 0.1), 2)
			panel.add_theme_stylebox_override("panel", blocked_style)
			slot_control.tooltip_text = "Off-hand blocked (2H weapon equipped)"
			continue
		else:
			# Ensure blocked overlay is hidden for non-blocked slots
			if blocked_overlay:
				blocked_overlay.visible = false

		# Special handling for mainhand - check equipped_weapon instead of equipped_armor
		var armor_item = null
		if slot_name == "mainhand" and CharacterStats.equipped_weapon:
			# Use stored weapon data (preserves forged metadata)
			armor_item = CharacterStats.get_equipped_weapon_data()
		else:
			armor_item = CharacterStats.equipped_armor[slot_name]

		if armor_item:
			# Try to get icon from ItemIconGenerator
			var icon_texture: Texture2D = null
			if ItemIconGenerator:
				icon_texture = ItemIconGenerator.get_item_icon(armor_item)

			if icon_texture and icon_rect:
				# We have an icon - show it and hide label
				icon_rect.texture = icon_texture
				icon_rect.visible = true
				label.visible = false
				label.text = ""
			else:
				# No icon - show text name
				if icon_rect:
					icon_rect.visible = false
				label.visible = true
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
			# Empty slot
			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false
			label.visible = false
			label.text = ""
			slot_control.tooltip_text = "Empty " + slot_name + " slot"
			# Reset to default style when empty
			var default_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
			panel.add_theme_stylebox_override("panel", default_style)

func refresh_tools() -> void:
	"""Update tool slot displays"""
	for tool_name in tool_slots:
		var slot_container = tool_slots[tool_name]  # VBoxContainer (compact slot)

		# Find the slot_control using recursive search (works for both old and new layouts)
		var slot_control = _find_node_by_prefix(slot_container, "Slot_")
		if not slot_control:
			slot_control = _find_node_by_prefix(slot_container, "Tool_")
		if not slot_control:
			continue

		# Find panel
		var panel = slot_control.get_node_or_null("SlotPanel")
		if not panel:
			panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			continue

		# Get icon and label nodes using recursive search
		var icon_rect: TextureRect = _find_node_recursive(slot_container, "ItemIcon")
		var label: Label = _find_node_recursive(slot_container, "ItemLabel")

		if not label:
			continue

		# Get the equipped tool
		var tool_item = null
		if tool_name == "axe":
			tool_item = InventorySystem.get_equipped_axe()
		elif tool_name == "pickaxe":
			tool_item = InventorySystem.get_equipped_pickaxe()

		if tool_item and not tool_item.is_empty():
			# Try to get icon from ItemIconGenerator
			var icon_texture: Texture2D = null
			if ItemIconGenerator:
				icon_texture = ItemIconGenerator.get_item_icon(tool_item)

			if icon_texture and icon_rect:
				# We have an icon - show it and hide label
				icon_rect.texture = icon_texture
				icon_rect.visible = true
				label.visible = false
				label.text = ""
			else:
				# No icon - show text name
				if icon_rect:
					icon_rect.visible = false
				label.visible = true
				label.text = tool_item.get("name", "???")

			# Apply subtle rarity glow to slot border
			var rarity = tool_item.get("rarity", "COMMON")
			var glow_color = get_rarity_glow_color(rarity)
			var glow_style = create_slot_style(SLOT_BG, glow_color, 3, true)  # Subtle border + glow
			panel.add_theme_stylebox_override("panel", glow_style)

			var tooltip = tool_item.get("description", "")

			# Tool stats
			if tool_item.has("efficiency"):
				tooltip += "\nEfficiency: +%d%%" % (tool_item.get("efficiency", 0) * 100)
			if tool_item.has("durability"):
				tooltip += "\nDurability: %d" % tool_item.get("durability", 100)

			slot_control.tooltip_text = tooltip
		else:
			# Empty slot
			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false
			label.visible = false
			label.text = ""
			slot_control.tooltip_text = "Empty " + tool_name + " slot"
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
				if DEBUG_EQUIP:
					print("[Equip] Unequipping weapon: %s" % CharacterStats.equipped_weapon.weapon_name)
				if CharacterStats.unequip_weapon():
					SoundManager.play_equip_sound()  # Unequip sound
					refresh_all()
				elif DEBUG_EQUIP:
					print("[Equip] Failed to unequip weapon (inventory full?)")
			else:
				var armor_item = CharacterStats.equipped_armor[slot_name]
				if armor_item:
					if CharacterStats.unequip_armor(slot_name):
						SoundManager.play_equip_sound()  # Unequip sound
						refresh_all()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Special handling for mainhand - check equipped_weapon
			if slot_name == "mainhand" and CharacterStats.equipped_weapon:
				if DEBUG_EQUIP:
					print("[Equip] Unequipping weapon: %s" % CharacterStats.equipped_weapon.weapon_name)
				if CharacterStats.unequip_weapon():
					SoundManager.play_equip_sound()  # Unequip sound
					refresh_all()
				elif DEBUG_EQUIP:
					print("[Equip] Failed to unequip weapon (inventory full?)")
			else:
				var armor_item = CharacterStats.equipped_armor[slot_name]
				if armor_item:
					if CharacterStats.unequip_armor(slot_name):
						SoundManager.play_equip_sound()  # Unequip sound
						refresh_all()

func _on_tool_slot_gui_input(event: InputEvent, tool_name: String) -> void:
	"""Handle GUI input on tool slot (double-click or right-click to unequip)"""
	if event is InputEventMouseButton and event.pressed:
		# Double-click or right-click to unequip
		if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			if tool_name == "axe":
				InventorySystem.unequip_axe()
				SoundManager.play_equip_sound()  # Unequip sound
				refresh_all()
			elif tool_name == "pickaxe":
				InventorySystem.unequip_pickaxe()
				SoundManager.play_equip_sound()  # Unequip sound
				refresh_all()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if tool_name == "axe":
				InventorySystem.unequip_axe()
				SoundManager.play_equip_sound()  # Unequip sound
				refresh_all()
			elif tool_name == "pickaxe":
				InventorySystem.unequip_pickaxe()
				SoundManager.play_equip_sound()  # Unequip sound
				refresh_all()

# ============================================
# DRAG AND DROP FUNCTIONS
# ============================================

func dict_to_weapon(item_dict: Dictionary) -> Weapon:
	"""Convert a weapon dictionary to a Weapon resource"""
	var weapon = Weapon.new()

	weapon.weapon_name = item_dict.get("name", "Unknown")
	weapon.weapon_type = item_dict.get("weapon_type", "sword")
	weapon.damage_type = "unified"
	weapon.description = item_dict.get("description", "")
	weapon.base_damage = item_dict.get("base_damage", 5.0)

	var attack_speed_category = item_dict.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30
		"slow":
			weapon.attack_speed_bonus = 0.30
		_:
			weapon.attack_speed_bonus = 0.0

	weapon.crit_chance_bonus = item_dict.get("crit_chance", 0.0)
	weapon.required_level = item_dict.get("required_level", 1)
	weapon.can_trade = item_dict.get("can_trade", true)
	weapon.sell_value = item_dict.get("value", 0)

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

	# Gun weapon properties
	weapon.gun_radius = item_dict.get("gun_radius", 28.0)
	weapon.gun_range = item_dict.get("gun_range", 350.0)
	weapon.gun_subtype = item_dict.get("gun_subtype", "railgun")
	weapon.burst_count = item_dict.get("burst_count", 1)
	weapon.burst_delay = item_dict.get("burst_delay", 0.10)

	# Two-handed property (blocks offhand slot)
	weapon.is_two_handed = item_dict.get("is_two_handed", false)

	return weapon

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
	var slot_container = equipment_slots[slot_name]  # VBoxContainer (compact slot)
	var slot_control = _find_node_by_prefix(slot_container, "Slot_")
	if not slot_control:
		slot_control = _find_node_by_prefix(slot_container, "Equip_")
	if slot_control:
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

	# Block offhand drops when 2h weapon equipped
	if slot_name == "offhand" and is_offhand_blocked():
		return false

	# Check if item's slot matches this equipment slot
	var item_slot = item.get("slot", "")

	# Shields can be equipped to offhand slot
	var item_type = item.get("item_type", item.get("type", ""))
	if item_type == "shield" and slot_name == "offhand":
		return true

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
	var item_type = dragged_item.get("item_type", dragged_item.get("type", ""))

	# Allow shields to go to offhand slot
	var is_shield_to_offhand = (item_type == "shield" and slot_name == "offhand")

	if item_slot != slot_name and not is_shield_to_offhand:
		return

	if source_type == "inventory":
		# Equip from inventory
		var source_index = data.get("source_index", -1)
		if source_index >= 0:
			var equipped = false

			# Check if it's a weapon
			if dragged_item.get("type", "") == "weapon" and slot_name == "mainhand":
				# If there's already a weapon equipped, unequip it first
				if CharacterStats.equipped_weapon:
					if DEBUG_EQUIP:
						print("[Equip] Swapping weapons - unequipping %s first" % CharacterStats.equipped_weapon.weapon_name)
					if not CharacterStats.unequip_weapon():
						if DEBUG_EQUIP:
							print("[Equip] Cannot swap weapons - inventory full!")
						return
				# Convert dict to Weapon resource and equip
				var weapon = dict_to_weapon(dragged_item)
				if weapon:
					CharacterStats.equip_weapon(weapon, dragged_item)  # Pass item data for forged metadata
					equipped = true
			# Check if it's a shield going to offhand
			elif is_shield_to_offhand:
				# If there's already something in offhand, unequip it first
				if CharacterStats.equipped_armor["offhand"]:
					if DEBUG_EQUIP:
						print("[Equip] Swapping offhand - unequipping existing item first")
					CharacterStats.unequip_armor("offhand")
				# Set the slot to offhand for proper equipping
				var shield_item = dragged_item.duplicate()
				shield_item["slot"] = "offhand"
				equipped = CharacterStats.equip_armor(shield_item)
				if DEBUG_EQUIP:
					print("[Equip] Shield equipped to offhand: %s" % shield_item.get("name", "Unknown"))
			# Otherwise it's armor
			else:
				equipped = CharacterStats.equip_armor(dragged_item)

			if equipped:
				# Remove from inventory
				InventorySystem.remove_item(source_index)
				SoundManager.play_equip_sound()  # Equip sound
				refresh_all()
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

# ============================================
# TOOL DRAG AND DROP
# ============================================

func _get_tool_drag_data(at_position: Vector2, tool_name: String) -> Variant:
	"""Start dragging an equipped tool"""
	var tool_item = null
	if tool_name == "axe":
		tool_item = InventorySystem.get_equipped_axe()
	elif tool_name == "pickaxe":
		tool_item = InventorySystem.get_equipped_pickaxe()

	if not tool_item or tool_item.is_empty():
		return null

	# Create drag preview
	var preview = Label.new()
	preview.text = tool_item.get("name", "Tool")
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color.GOLD)
	preview.modulate = Color(1, 1, 1, 0.8)  # Slightly transparent

	# Get the tool slot control and set preview on it
	var slot_container = tool_slots[tool_name]  # VBoxContainer (compact slot)
	var slot_control = _find_node_by_prefix(slot_container, "Slot_")
	if not slot_control:
		slot_control = _find_node_by_prefix(slot_container, "Tool_")
	if slot_control:
		slot_control.set_drag_preview(preview)

	# Return drag data
	return {
		"source_type": "tool",
		"source_tool_name": tool_name,
		"item": tool_item
	}

func _can_drop_tool_data(at_position: Vector2, data: Variant, tool_name: String) -> bool:
	"""Check if data can be dropped on this tool slot"""
	if not data is Dictionary:
		return false

	if not data.has("item"):
		return false

	var item = data.get("item", {})

	# Check if item is a tool
	if item.get("type", "") != "tool":
		return false

	# Check if tool type matches this slot
	var tool_type = item.get("tool_type", "")
	if tool_type != tool_name:
		return false

	return true

func _drop_tool_data(at_position: Vector2, data: Dictionary, tool_name: String) -> void:
	"""Handle dropping data on a tool slot"""
	if not data.has("item"):
		return

	var source_type = data.get("source_type", "")
	var dragged_item = data.get("item", {})

	# Validate the drop
	var tool_type = dragged_item.get("tool_type", "")
	if tool_type != tool_name:
		return

	if source_type == "inventory":
		# Equip from inventory
		var source_index = data.get("source_index", -1)
		if source_index >= 0:
			var equipped = false

			if tool_name == "axe":
				equipped = InventorySystem.equip_axe(dragged_item)
			elif tool_name == "pickaxe":
				equipped = InventorySystem.equip_pickaxe(dragged_item)

			if equipped:
				# Remove from inventory
				InventorySystem.remove_item(source_index)
				SoundManager.play_equip_sound()  # Equip sound
				refresh_all()
	elif source_type == "tool":
		# Can't swap tools between slots (different types)
		pass

# ============================================
# SIGNAL HANDLERS
# ============================================

func _on_stats_changed(_level: int = 0) -> void:
	"""Called when character stats change"""
	refresh_all()

func _on_xp_changed(_amount: int, _total: int) -> void:
	"""Called when XP changes"""
	refresh_character_info()

func _on_armor_changed(_slot: String, _armor: Dictionary) -> void:
	"""Called when armor is equipped/unequipped"""
	refresh_all()

func _on_weapon_changed(_weapon = null) -> void:
	"""Called when weapon is equipped/unequipped"""
	refresh_all()

func _on_tool_changed(_tool: Dictionary) -> void:
	"""Called when a tool is equipped/unequipped"""
	refresh_tools()

func _find_node_recursive(parent: Node, node_name: String) -> Node:
	"""Recursively search for a node by name"""
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found = _find_node_recursive(child, node_name)
		if found:
			return found
	return null

func _find_node_by_prefix(parent: Node, prefix: String) -> Node:
	"""Recursively search for a node whose name starts with prefix"""
	for child in parent.get_children():
		if child.name.begins_with(prefix):
			return child
		var found = _find_node_by_prefix(child, prefix)
		if found:
			return found
	return null
