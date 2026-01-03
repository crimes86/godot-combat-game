extends CanvasLayer

## Character UI - Character sheet with stats and equipment
## Press C to toggle (Inventory is separate - press I)

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_EQUIP: bool = true  # Debug equipping/unequipping from character sheet

var is_visible: bool = false

# Mouse click-and-hold tracking for inspection
var _long_hold_timer: Timer = null
var _long_hold_slot: String = ""  # Tracks which slot/feature is being held
var _long_hold_type: String = ""  # "mastery", "equipment"
var _long_hold_start_time: float = 0.0
var _radial_progress: Control = null
const LONG_HOLD_DURATION = 0.6  # seconds (snappy but intentional)

# UI References
var main_panel: PanelContainer
var equipment_slots: Dictionary = {}  # slot_name: HBoxContainer (contains slot icon Control + label)
var tool_slots: Dictionary = {}  # tool_name: HBoxContainer (axe, pickaxe)
var stat_labels: Dictionary = {}  # stat_name: Label
var character_name_label: Label
var level_label: Label
var xp_bar: ProgressBar
var hp_label: Label

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

# Slot sizes - use UITheme constants for consistency
const SLOT_SIZE = UITheme.SLOT_SIZE  # 54px - matches inventory
const ICON_SIZE = UITheme.ICON_SIZE  # 46px - SLOT_SIZE - 8

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
	CharacterStats.allegiance_changed.connect(_on_allegiance_changed)
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
	if CharacterStats.allegiance_changed.is_connected(_on_allegiance_changed):
		CharacterStats.allegiance_changed.disconnect(_on_allegiance_changed)
	if InventorySystem.axe_equipped.is_connected(_on_tool_changed):
		InventorySystem.axe_equipped.disconnect(_on_tool_changed)
	if InventorySystem.axe_unequipped.is_connected(_on_tool_changed):
		InventorySystem.axe_unequipped.disconnect(_on_tool_changed)
	if InventorySystem.pickaxe_equipped.is_connected(_on_tool_changed):
		InventorySystem.pickaxe_equipped.disconnect(_on_tool_changed)
	if InventorySystem.pickaxe_unequipped.is_connected(_on_tool_changed):
		InventorySystem.pickaxe_unequipped.disconnect(_on_tool_changed)

func _on_allegiance_changed(_old_allegiance: String, _new_allegiance: String) -> void:
	"""Called when allegiance changes"""
	_update_allegiance_display()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Close skills panel first if open
			if _active_skills_panel and is_instance_valid(_active_skills_panel):
				_active_skills_panel.queue_free()  # tree_exiting handles cleanup
				get_viewport().set_input_as_handled()
			elif is_visible:
				toggle_character_ui()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	"""Update cursor-following radial progress indicator"""
	if not is_visible:
		return

	# Update radial progress position and fill
	if _radial_progress and _long_hold_start_time > 0:
		_radial_progress.global_position = get_viewport().get_mouse_position() - Vector2(24, 24)
		var elapsed = (Time.get_ticks_msec() / 1000.0) - _long_hold_start_time
		var progress = clampf(elapsed / LONG_HOLD_DURATION, 0.0, 1.0)
		_radial_progress.set_meta("progress", progress)
		_radial_progress.queue_redraw()

func create_character_ui() -> void:
	"""Create character sheet with stats and equipment (2 columns)"""

	# Main panel container - centered (narrower for 2 columns)
	main_panel = PanelContainer.new()
	main_panel.name = "CharacterPanel"

	# Center the panel - 2-column layout (compact)
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(580, 560)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -290
	main_panel.offset_right = 290
	main_panel.offset_top = -280
	main_panel.offset_bottom = 280
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	# Dark Fantasy dreadland styling with transparency
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR  # 75% transparent dark leather
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR  # Rusted bronze

	# Subtle rounded corners
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8

	# Heavy shadow for depth
	panel_style.shadow_size = 12
	panel_style.shadow_color = Color(0, 0, 0, 0.8)  # Darker shadow for dreadland
	panel_style.shadow_offset = Vector2(0, 6)

	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Main layout with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 15)
	main_panel.add_child(margin)

	# Vertical layout: header row + content
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Header row with title and close button
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header_row)

	var title_label = Label.new()
	title_label.text = "Character"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_label)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	# Style close button to match theme (red X)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.5, 0.15, 0.12, 0.8)
	close_style.set_corner_radius_all(4)
	var close_hover = close_style.duplicate()
	close_hover.bg_color = Color(0.65, 0.2, 0.15, 0.9)
	var close_pressed = close_style.duplicate()
	close_pressed.bg_color = Color(0.4, 0.1, 0.08, 0.9)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_pressed)
	close_btn.add_theme_color_override("font_color", TEXT_COLOR)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(toggle_character_ui)
	header_row.add_child(close_btn)

	# Two columns: Stats | Equipment
	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 15)
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(main_hbox)

	# LEFT COLUMN: Character info + stats
	create_character_info_panel(main_hbox)

	# RIGHT COLUMN: Equipment slots
	create_equipment_panel(main_hbox)

	add_child(main_panel)


func create_equipment_panel(parent: Control) -> void:
	"""Create equipment panel with compact body-shaped paperdoll layout"""
	var equipment_panel = PanelContainer.new()
	equipment_panel.custom_minimum_size = Vector2(280, 0)
	equipment_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var equip_style = create_inner_panel_style()
	equipment_panel.add_theme_stylebox_override("panel", equip_style)
	parent.add_child(equipment_panel)

	var equipment_vbox = VBoxContainer.new()
	equipment_vbox.add_theme_constant_override("separation", 0)
	equipment_panel.add_child(equipment_vbox)

	# Title
	var title = create_header_label("Equipment")
	equipment_vbox.add_child(title)

	# Compact body-shaped paperdoll layout:
	#          [HEAD]
	#    [AMULET]  [BACK]
	#   [MH] [CHEST] [OH]
	#          [ARMS]
	#   [R1] [HANDS] [R2]
	#     [LEGS] [FEET]

	# Row 1: Head (centered)
	var row1 = CenterContainer.new()
	equipment_vbox.add_child(row1)
	var head_slot = create_equipment_slot_compact("head", "Head")
	row1.add_child(head_slot)
	equipment_slots["head"] = head_slot

	# Row 2: Amulet + Back side by side (neck/shoulder area)
	var row2_center = CenterContainer.new()
	equipment_vbox.add_child(row2_center)

	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2_center.add_child(row2)

	var amulet_slot = create_equipment_slot_compact("amulet", "Amulet")
	row2.add_child(amulet_slot)
	equipment_slots["amulet"] = amulet_slot

	var back_slot = create_equipment_slot_compact("back", "Back")
	row2.add_child(back_slot)
	equipment_slots["back"] = back_slot

	# Row 3: Mainhand - Chest - Offhand (torso row)
	var row3_center = CenterContainer.new()
	equipment_vbox.add_child(row3_center)

	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	row3_center.add_child(row3)

	var mainhand_slot = create_equipment_slot_compact("mainhand", "Main")
	row3.add_child(mainhand_slot)
	equipment_slots["mainhand"] = mainhand_slot

	var chest_slot = create_equipment_slot_compact("chest", "Chest")
	row3.add_child(chest_slot)
	equipment_slots["chest"] = chest_slot

	var offhand_slot = create_equipment_slot_compact("offhand", "Off")
	row3.add_child(offhand_slot)
	equipment_slots["offhand"] = offhand_slot

	# Row 4: Arms (centered - bracers)
	var row4 = CenterContainer.new()
	equipment_vbox.add_child(row4)
	var arms_slot = create_equipment_slot_compact("arms", "Arms")
	row4.add_child(arms_slot)
	equipment_slots["arms"] = arms_slot

	# Row 5: Ring1 - Hands - Ring2 (hands with rings)
	var row5_center = CenterContainer.new()
	equipment_vbox.add_child(row5_center)

	var row5 = HBoxContainer.new()
	row5.add_theme_constant_override("separation", 4)
	row5_center.add_child(row5)

	var ring1_slot = create_equipment_slot_compact("ring1", "Ring")
	row5.add_child(ring1_slot)
	equipment_slots["ring1"] = ring1_slot

	var hands_slot = create_equipment_slot_compact("hands", "Hands")
	row5.add_child(hands_slot)
	equipment_slots["hands"] = hands_slot

	var ring2_slot = create_equipment_slot_compact("ring2", "Ring")
	row5.add_child(ring2_slot)
	equipment_slots["ring2"] = ring2_slot

	# Row 6: Legs + Feet side by side
	var row6_center = CenterContainer.new()
	equipment_vbox.add_child(row6_center)

	var row6 = HBoxContainer.new()
	row6.add_theme_constant_override("separation", 8)
	row6_center.add_child(row6)

	var legs_slot = create_equipment_slot_compact("legs", "Legs")
	row6.add_child(legs_slot)
	equipment_slots["legs"] = legs_slot

	var feet_slot = create_equipment_slot_compact("feet", "Feet")
	row6.add_child(feet_slot)
	equipment_slots["feet"] = feet_slot

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

	# Dark dreadland styled progress bar
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
	stats_grid.columns = 2  # 2 stat rows side by side (each row is an HBox with label+value)
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 4)
	stats_center.add_child(stats_grid)

	# 6-stat system: STR, AGI, DEX, INT, WIS, VIT
	var stat_names = ["Strength", "Agility", "Dexterity", "Intelligence", "Wisdom", "Vitality"]
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

	var derived_names = ["Attack", "Crit Chance", "Defense"]
	for derived_name in derived_names:
		var derived_label = create_text_label(derived_name + ":", 14)
		derived_grid.add_child(derived_label)

		var value_label = create_text_label("0", 14)
		value_label.add_theme_color_override("font_color", HEADER_COLOR)
		derived_grid.add_child(value_label)
		stat_labels[derived_name.to_lower().replace(" ", "_")] = value_label

	# Separator before Weapon Mastery
	var separator3 = create_styled_separator()
	info_vbox.add_child(separator3)

	# Weapon Mastery section (compact - hold to expand)
	create_weapon_mastery_section(info_vbox)

	# Separator before Allegiance
	var separator4 = create_styled_separator()
	info_vbox.add_child(separator4)

	# Allegiance section
	create_allegiance_section(info_vbox)

# Weapon Mastery UI references
var mastery_container: Control = null
var mastery_weapon_label: Label = null
var mastery_title_label: Label = null
var mastery_skill_label: Label = null
var mastery_progress_bar: ProgressBar = null

# Allegiance UI references
var allegiance_label: Label = null
var allegiance_button: Button = null

func create_weapon_mastery_section(parent: Control) -> void:
	"""Create compact weapon mastery section with press-hold to expand"""
	var mastery_header = create_header_label("Weapon Mastery", 16)
	parent.add_child(mastery_header)

	# Container for the mastery display (clickable area for press-hold)
	mastery_container = PanelContainer.new()
	mastery_container.name = "MasteryContainer"
	mastery_container.mouse_filter = Control.MOUSE_FILTER_STOP
	mastery_container.gui_input.connect(_on_mastery_gui_input)

	# Subtle inner panel styling
	var mastery_style = StyleBoxFlat.new()
	mastery_style.bg_color = Color(SLOT_BG.r, SLOT_BG.g, SLOT_BG.b, 0.5)
	mastery_style.border_width_left = 1
	mastery_style.border_width_right = 1
	mastery_style.border_width_top = 1
	mastery_style.border_width_bottom = 1
	mastery_style.border_color = BORDER_INNER
	mastery_style.corner_radius_top_left = 4
	mastery_style.corner_radius_top_right = 4
	mastery_style.corner_radius_bottom_left = 4
	mastery_style.corner_radius_bottom_right = 4
	mastery_style.content_margin_left = 8
	mastery_style.content_margin_right = 8
	mastery_style.content_margin_top = 6
	mastery_style.content_margin_bottom = 6
	mastery_container.add_theme_stylebox_override("panel", mastery_style)
	parent.add_child(mastery_container)

	var mastery_vbox = VBoxContainer.new()
	mastery_vbox.add_theme_constant_override("separation", 4)
	mastery_container.add_child(mastery_vbox)

	# Row 1: Weapon type + Title
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	mastery_vbox.add_child(top_row)

	mastery_weapon_label = create_text_label("Sword", 13)
	mastery_weapon_label.add_theme_color_override("font_color", ACCENT_COLOR)
	top_row.add_child(mastery_weapon_label)

	mastery_title_label = create_text_label("Squire", 13)
	mastery_title_label.add_theme_color_override("font_color", HEADER_COLOR)
	mastery_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(mastery_title_label)

	# Row 2: Skill level + Progress bar
	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 8)
	mastery_vbox.add_child(bottom_row)

	mastery_skill_label = create_text_label("Skill: 0/10", 11)
	mastery_skill_label.custom_minimum_size.x = 70
	bottom_row.add_child(mastery_skill_label)

	# Compact progress bar
	mastery_progress_bar = ProgressBar.new()
	mastery_progress_bar.custom_minimum_size = Vector2(0, 10)
	mastery_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_progress_bar.show_percentage = false

	var prog_bg = StyleBoxFlat.new()
	prog_bg.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	prog_bg.corner_radius_top_left = 3
	prog_bg.corner_radius_top_right = 3
	prog_bg.corner_radius_bottom_left = 3
	prog_bg.corner_radius_bottom_right = 3

	var prog_fill = StyleBoxFlat.new()
	prog_fill.bg_color = Color(0.45, 0.55, 0.65, 1.0)  # Steel blue color
	prog_fill.corner_radius_top_left = 3
	prog_fill.corner_radius_top_right = 3
	prog_fill.corner_radius_bottom_left = 3
	prog_fill.corner_radius_bottom_right = 3

	mastery_progress_bar.add_theme_stylebox_override("background", prog_bg)
	mastery_progress_bar.add_theme_stylebox_override("fill", prog_fill)
	bottom_row.add_child(mastery_progress_bar)

	# Hint text
	var hint_label = create_text_label("[Click and hold to view all skills]", 9)
	hint_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.8))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mastery_vbox.add_child(hint_label)

	# Set tooltip
	mastery_container.tooltip_text = "Your proficiency with your current weapon type.\nHigher skill = better hit chance and damage.\n\n[Click and hold to view all weapon skills]"

func create_allegiance_section(parent: Control) -> void:
	"""Create allegiance display and toggle section"""
	var allegiance_header = create_header_label("Allegiance", 16)
	parent.add_child(allegiance_header)

	# Container for allegiance display
	var allegiance_container = PanelContainer.new()
	allegiance_container.name = "AllegianceContainer"

	# Subtle inner panel styling
	var allegiance_style = StyleBoxFlat.new()
	allegiance_style.bg_color = Color(SLOT_BG.r, SLOT_BG.g, SLOT_BG.b, 0.5)
	allegiance_style.border_width_left = 1
	allegiance_style.border_width_right = 1
	allegiance_style.border_width_top = 1
	allegiance_style.border_width_bottom = 1
	allegiance_style.border_color = BORDER_INNER
	allegiance_style.corner_radius_top_left = 4
	allegiance_style.corner_radius_top_right = 4
	allegiance_style.corner_radius_bottom_left = 4
	allegiance_style.corner_radius_bottom_right = 4
	allegiance_style.content_margin_left = 8
	allegiance_style.content_margin_right = 8
	allegiance_style.content_margin_top = 6
	allegiance_style.content_margin_bottom = 6
	allegiance_container.add_theme_stylebox_override("panel", allegiance_style)
	parent.add_child(allegiance_container)

	var allegiance_vbox = VBoxContainer.new()
	allegiance_vbox.add_theme_constant_override("separation", 6)
	allegiance_container.add_child(allegiance_vbox)

	# Current allegiance label
	allegiance_label = create_text_label("Ashbane", 14)
	allegiance_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 1.0))  # Green tint for Ashbane
	allegiance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	allegiance_vbox.add_child(allegiance_label)

	# Toggle button
	allegiance_button = Button.new()
	allegiance_button.text = "Go Rogue"
	allegiance_button.custom_minimum_size = Vector2(120, 28)

	# Style button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.4, 0.25, 0.2, 0.8)  # Reddish for "Go Rogue"
	btn_style.set_corner_radius_all(4)
	btn_style.border_width_left = 1
	btn_style.border_width_right = 1
	btn_style.border_width_top = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = Color(0.5, 0.3, 0.25, 1.0)

	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.5, 0.3, 0.25, 0.9)

	var btn_pressed = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.3, 0.2, 0.15, 0.9)

	allegiance_button.add_theme_stylebox_override("normal", btn_style)
	allegiance_button.add_theme_stylebox_override("hover", btn_hover)
	allegiance_button.add_theme_stylebox_override("pressed", btn_pressed)
	allegiance_button.add_theme_color_override("font_color", TEXT_COLOR)
	allegiance_button.add_theme_font_size_override("font_size", 12)
	allegiance_button.pressed.connect(_on_allegiance_button_pressed)

	# Center the button
	var btn_center = CenterContainer.new()
	btn_center.add_child(allegiance_button)
	allegiance_vbox.add_child(btn_center)

	# Set tooltip
	allegiance_container.tooltip_text = "Your faction allegiance.\nAshbane: Cannot attack same-faction players.\nRogue: Can attack anyone (except party)."

	# Update display based on current allegiance
	_update_allegiance_display()

func _on_allegiance_button_pressed() -> void:
	"""Handle allegiance toggle button press"""
	if SoundManager:
		SoundManager.play_button_click_sound()

	if CharacterStats.is_rogue():
		# Try to join Ashbane (1 hour cooldown after going rogue)
		if CharacterStats.join_ashbane():
			_update_allegiance_display()
			if NotificationManager:
				NotificationManager.show_notification("Joined Ashbane faction!", "INFO")
		else:
			# Show remaining cooldown time
			var remaining = _get_rogue_rejoin_cooldown_remaining()
			if NotificationManager:
				NotificationManager.show_notification("Cannot rejoin yet. %d min remaining." % remaining, "WARNING")
	else:
		# Try to go rogue (no cooldown)
		if CharacterStats.go_rogue():
			_update_allegiance_display()
			if NotificationManager:
				NotificationManager.show_notification("You are now a Rogue!", "WARNING")

func _get_rogue_rejoin_cooldown_remaining() -> int:
	"""Get remaining minutes until can rejoin Ashbane"""
	var current_time = Time.get_unix_time_from_system()
	var time_since_change = current_time - CharacterStats.allegiance_last_change
	var remaining = CharacterStats.ROGUE_REJOIN_COOLDOWN - time_since_change
	return max(1, int(remaining / 60))  # At least 1 minute shown

func _update_allegiance_display() -> void:
	"""Update allegiance label and button based on current state"""
	if not allegiance_label or not allegiance_button:
		return

	if CharacterStats.is_rogue():
		allegiance_label.text = "Rogue (No Allegiance)"
		allegiance_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))  # Gray
		allegiance_button.text = "Join Ashbane"
		# Green button for joining
		var btn_style = allegiance_button.get_theme_stylebox("normal").duplicate()
		btn_style.bg_color = Color(0.25, 0.4, 0.3, 0.8)
		btn_style.border_color = Color(0.3, 0.5, 0.35, 1.0)
		allegiance_button.add_theme_stylebox_override("normal", btn_style)
		var btn_hover = btn_style.duplicate()
		btn_hover.bg_color = Color(0.3, 0.5, 0.35, 0.9)
		allegiance_button.add_theme_stylebox_override("hover", btn_hover)
	else:
		allegiance_label.text = "Ashbane"
		allegiance_label.add_theme_color_override("font_color", Color(0.6, 0.75, 0.6, 1.0))  # Green tint
		allegiance_button.text = "Go Rogue"
		# Red button for going rogue
		var btn_style = allegiance_button.get_theme_stylebox("normal").duplicate()
		btn_style.bg_color = Color(0.4, 0.25, 0.2, 0.8)
		btn_style.border_color = Color(0.5, 0.3, 0.25, 1.0)
		allegiance_button.add_theme_stylebox_override("normal", btn_style)
		var btn_hover = btn_style.duplicate()
		btn_hover.bg_color = Color(0.5, 0.3, 0.25, 0.9)
		allegiance_button.add_theme_stylebox_override("hover", btn_hover)

func _on_mastery_gui_input(event: InputEvent) -> void:
	"""Handle mouse click-and-hold on mastery container to open skills panel"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_start_long_hold("mastery", "mastery")
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_cancel_long_hold()

var _active_skills_panel: CanvasLayer = null  # Track active skills panel for cleanup
var _inspection_panel_open: bool = false  # Track if inspection panel is beside us
var _skills_panel_open: bool = false  # Track if skills panel is beside us

func _open_weapon_skills_panel() -> void:
	"""Open the full weapon skills panel beside character sheet"""
	# Check if panel already exists
	if _active_skills_panel and is_instance_valid(_active_skills_panel):
		return

	# Play panel open sound
	if SoundManager:
		SoundManager.play_button_click_sound()

	# Set flag BEFORE calculating layout
	_skills_panel_open = true

	# Shift character panel (and inspection if open) to make room
	_shift_character_panel_only()
	# Also reposition inspection if it's already open
	if _inspection_panel_open:
		var layout = _calculate_multi_panel_layout()
		var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
		if inspection_ui and inspection_ui.is_visible:
			inspection_ui.reposition(layout.inspection.left, layout.inspection.right)

	# Get position for skills panel
	var pos = _get_secondary_panel_position(SKILLS_PANEL_WIDTH)

	# Create the skills panel
	_active_skills_panel = _create_weapon_skills_panel(pos.offset_left, pos.offset_right)
	_active_skills_panel.add_to_group("weapon_skills_panel")
	get_tree().root.add_child(_active_skills_panel)

func _on_skills_panel_closed() -> void:
	"""Called when weapon skills panel closes"""
	_active_skills_panel = null
	_skills_panel_open = false
	_reposition_all_panels()

func _create_weapon_skills_panel(offset_l: int, offset_r: int) -> CanvasLayer:
	"""Create the full weapon skills panel showing all weapon types"""
	var canvas = CanvasLayer.new()
	canvas.name = "WeaponSkillsPanel"
	canvas.layer = 115  # Above character sheet

	# Main panel - positioned beside character sheet
	var panel = PanelContainer.new()
	panel.name = "SkillsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(SKILLS_PANEL_WIDTH, 450)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = offset_l
	panel.offset_right = offset_r
	panel.offset_top = -225
	panel.offset_bottom = 225

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.shadow_size = 12
	panel_style.shadow_color = Color(0, 0, 0, 0.8)
	panel_style.shadow_offset = Vector2(0, 6)  # Match main panel styling
	panel.add_theme_stylebox_override("panel", panel_style)
	canvas.add_child(panel)

	# Margin
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# Header with close button
	var header_row = HBoxContainer.new()
	main_vbox.add_child(header_row)

	var title = create_header_label("Weapon Skills", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	# Style close button to match theme
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.5, 0.15, 0.12, 0.8)
	close_style.set_corner_radius_all(4)
	var close_hover = close_style.duplicate()
	close_hover.bg_color = Color(0.65, 0.2, 0.15, 0.9)
	var close_pressed = close_style.duplicate()
	close_pressed.bg_color = Color(0.4, 0.1, 0.08, 0.9)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_stylebox_override("pressed", close_pressed)
	close_btn.add_theme_color_override("font_color", TEXT_COLOR)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(func(): canvas.queue_free())  # tree_exiting handles cleanup
	header_row.add_child(close_btn)

	# Separator
	main_vbox.add_child(create_styled_separator())

	# Scrollable list of weapon skills
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Make ScrollContainer background transparent (Godot default can be light)
	var scroll_panel_style = StyleBoxEmpty.new()
	scroll.add_theme_stylebox_override("panel", scroll_panel_style)
	main_vbox.add_child(scroll)

	var skills_vbox = VBoxContainer.new()
	skills_vbox.add_theme_constant_override("separation", 6)
	skills_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(skills_vbox)

	# Create rows for each weapon type
	var weapon_types = [
		{"type": "Swords", "titles": ["Squire", "Swordsman", "Bladesman", "Blademaster", "Sword Saint", "Kensei"]},
		{"type": "Daggers", "titles": ["Footpad", "Cutthroat", "Assassin", "Shadowblade", "Phantom", "Reaper"]},
		{"type": "Axes", "titles": ["Woodsman", "Hewer", "Cleaver", "Headsman", "Warlord", "Berserker"]},
		{"type": "Maces", "titles": ["Initiate", "Enforcer", "Crusher", "Demolisher", "Juggernaut", "Titan"]},
		{"type": "Hammers", "titles": ["Striker", "Smasher", "Breaker", "Earthshaker", "Worldbreaker", "Godhand"]},
		{"type": "Spears", "titles": ["Militia", "Pikeman", "Hoplite", "Lancer", "Dragoon", "Valkyrie"]},
		{"type": "Bows", "titles": ["Fletcher", "Archer", "Marksman", "Sharpshooter", "Deadeye", "Hawkeye"]},
		{"type": "Healing", "titles": ["Acolyte", "Healer", "Priest", "Bishop", "Cardinal", "Saint"]},
		{"type": "Arcane", "titles": ["Apprentice", "Conjurer", "Mage", "Sorcerer", "Archmage", "Archon"]},
		{"type": "Guns", "titles": ["Recruit", "Gunner", "Sharpshooter", "Sniper", "Ace", "Deadshot"]},
		{"type": "Blocking", "titles": ["Defender", "Guardian", "Bulwark", "Shieldmaster", "Aegis", "Invincible"]}
	]

	# Get current equipped weapon type for highlighting
	var current_weapon_type = "Swords"  # Default
	if CharacterStats.equipped_weapon:
		current_weapon_type = CharacterStats.equipped_weapon.weapon_type.capitalize()
		# Map weapon types to skill categories
		if current_weapon_type in ["Sword", "Katana", "Saber", "Scimitar", "Rapier"]:
			current_weapon_type = "Swords"
		elif current_weapon_type in ["Dagger"]:
			current_weapon_type = "Daggers"
		elif current_weapon_type in ["Axe"]:
			current_weapon_type = "Axes"
		elif current_weapon_type in ["Mace"]:
			current_weapon_type = "Maces"
		elif current_weapon_type in ["Hammer"]:
			current_weapon_type = "Hammers"
		elif current_weapon_type in ["Spear", "Halberd"]:
			current_weapon_type = "Spears"
		elif current_weapon_type in ["Bow"]:
			current_weapon_type = "Bows"
		elif current_weapon_type in ["Staff"]:
			current_weapon_type = "Arcane"  # Default staff to arcane
		elif current_weapon_type in ["Gun"]:
			current_weapon_type = "Guns"

	# Check if shield is equipped for blocking highlight
	var has_shield = not CharacterStats.get_equipped_shield().is_empty()

	for weapon_data in weapon_types:
		# Highlight weapon type if it matches equipped weapon, or blocking if shield equipped
		var is_highlighted = weapon_data.type == current_weapon_type
		if weapon_data.type == "Blocking" and has_shield:
			is_highlighted = true
		var row = _create_skill_row(weapon_data.type, weapon_data.titles, is_highlighted)
		skills_vbox.add_child(row)

	# Footer hint
	var footer = create_text_label("Skill increases as you use weapons. Cap = Level x 10 (max 300)", 10)
	footer.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55, 0.8))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(footer)

	# Handle ESC to close - need to use tree_exiting signal for cleanup
	canvas.tree_exiting.connect(_on_skills_panel_closed)

	return canvas

func _create_skill_row(weapon_type: String, titles: Array, is_current: bool) -> Control:
	"""Create a row for a weapon skill type"""
	var container = PanelContainer.new()

	# Style - highlight current weapon (use solid dark colors matching theme)
	var row_style = StyleBoxFlat.new()
	if is_current:
		row_style.bg_color = Color(0.15, 0.15, 0.17, 0.95)  # Neutral gray highlight
		row_style.border_color = ACCENT_COLOR
		row_style.border_width_left = 2
		row_style.border_width_right = 2
		row_style.border_width_top = 2
		row_style.border_width_bottom = 2
	else:
		row_style.bg_color = Color(0.06, 0.06, 0.07, 0.9)  # Dark charcoal matching theme
		row_style.border_color = BORDER_INNER
		row_style.border_width_left = 1
		row_style.border_width_right = 1
		row_style.border_width_top = 1
		row_style.border_width_bottom = 1
	row_style.corner_radius_top_left = 4
	row_style.corner_radius_top_right = 4
	row_style.corner_radius_bottom_left = 4
	row_style.corner_radius_bottom_right = 4
	row_style.content_margin_left = 10
	row_style.content_margin_right = 10
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	container.add_theme_stylebox_override("panel", row_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	container.add_child(hbox)

	# Weapon type name
	var type_label = create_text_label(weapon_type, 14)
	type_label.add_theme_color_override("font_color", ACCENT_COLOR if is_current else TEXT_COLOR)
	type_label.custom_minimum_size.x = 70
	hbox.add_child(type_label)

	# Get skill value from WeaponSkillManager
	var category = weapon_type.to_lower()  # "Swords" -> "swords"
	var skill_value: float = 0.0
	var max_skill: int = 10
	if WeaponSkillManager:
		skill_value = WeaponSkillManager.get_skill(category)
		max_skill = WeaponSkillManager.get_skill_cap()

	var skill_label = create_text_label("%d/%d" % [int(skill_value), max_skill], 12)
	skill_label.custom_minimum_size.x = 55
	hbox.add_child(skill_label)

	# Progress bar - taller for better visibility
	var progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(100, 16)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.show_percentage = false
	progress.max_value = max_skill if max_skill > 0 else 1
	progress.value = skill_value

	var prog_bg = StyleBoxFlat.new()
	prog_bg.bg_color = Color(0.04, 0.04, 0.05, 0.95)
	prog_bg.set_corner_radius_all(4)
	prog_bg.border_color = Color(0.15, 0.15, 0.18, 0.8)
	prog_bg.set_border_width_all(1)

	var prog_fill = StyleBoxFlat.new()
	prog_fill.bg_color = ACCENT_COLOR if is_current else Color(0.40, 0.40, 0.45, 1.0)
	prog_fill.set_corner_radius_all(3)

	progress.add_theme_stylebox_override("background", prog_bg)
	progress.add_theme_stylebox_override("fill", prog_fill)
	hbox.add_child(progress)

	# Get current title from WeaponSkillManager - brighter for readability
	var current_title = ""
	if WeaponSkillManager:
		current_title = WeaponSkillManager.get_title(category)
	if current_title == "":
		current_title = titles[0] if titles.size() > 0 else "Untrained"
	var title_label = create_text_label(current_title, 13)
	title_label.add_theme_color_override("font_color", TEXT_COLOR if is_current else HEADER_COLOR)
	title_label.custom_minimum_size.x = 90
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(title_label)

	return container

func _get_title_index_for_skill(skill: int) -> int:
	"""Get title tier index based on skill level"""
	# Tiers: 0-49, 50-99, 100-149, 150-199, 200-249, 250-300
	if skill < 50:
		return 0
	elif skill < 100:
		return 1
	elif skill < 150:
		return 2
	elif skill < 200:
		return 3
	elif skill < 250:
		return 4
	else:
		return 5

func refresh_weapon_mastery() -> void:
	"""Update the compact weapon mastery display"""
	if not mastery_weapon_label or not mastery_title_label or not mastery_skill_label or not mastery_progress_bar:
		return

	# Get current weapon category from WeaponSkillManager
	var weapon_category = "swords"  # Default
	if CharacterStats.equipped_weapon and WeaponSkillManager:
		weapon_category = WeaponSkillManager.get_category_for_weapon(CharacterStats.equipped_weapon.weapon_type)

	mastery_weapon_label.text = weapon_category.capitalize()

	# Get skill value from WeaponSkillManager
	var skill_value: float = 0.0
	var max_skill: int = 10
	if WeaponSkillManager:
		skill_value = WeaponSkillManager.get_skill(weapon_category)
		max_skill = WeaponSkillManager.get_skill_cap()

	mastery_skill_label.text = "Skill: %d/%d" % [int(skill_value), max_skill]
	mastery_progress_bar.max_value = max_skill if max_skill > 0 else 1
	mastery_progress_bar.value = skill_value

	# Get title from WeaponSkillManager
	var title = ""
	if WeaponSkillManager:
		title = WeaponSkillManager.get_title(weapon_category)
	if title == "":
		title = "Untrained"
	mastery_title_label.text = title

func _get_titles_for_category(category: String) -> Array:
	"""Get title progression for a weapon category"""
	match category:
		"Swords":
			return ["Squire", "Swordsman", "Bladesman", "Blademaster", "Sword Saint", "Kensei"]
		"Daggers":
			return ["Footpad", "Cutthroat", "Assassin", "Shadowblade", "Phantom", "Reaper"]
		"Axes":
			return ["Woodsman", "Hewer", "Cleaver", "Headsman", "Warlord", "Berserker"]
		"Maces":
			return ["Initiate", "Enforcer", "Crusher", "Demolisher", "Juggernaut", "Titan"]
		"Hammers":
			return ["Striker", "Smasher", "Breaker", "Earthshaker", "Worldbreaker", "Godhand"]
		"Spears":
			return ["Militia", "Pikeman", "Hoplite", "Lancer", "Dragoon", "Valkyrie"]
		"Bows":
			return ["Fletcher", "Archer", "Marksman", "Sharpshooter", "Deadeye", "Hawkeye"]
		"Healing":
			return ["Acolyte", "Healer", "Priest", "Bishop", "Cardinal", "Saint"]
		"Arcane":
			return ["Apprentice", "Conjurer", "Mage", "Sorcerer", "Archmage", "Archon"]
		"Guns":
			return ["Recruit", "Gunner", "Sharpshooter", "Sniper", "Ace", "Deadshot"]
		"Blocking":
			return ["Defender", "Guardian", "Bulwark", "Shieldmaster", "Aegis", "Invincible"]
		_:
			return ["Novice", "Apprentice", "Journeyman", "Expert", "Master", "Grandmaster"]

func create_equipment_slot_compact(slot_name: String, label_text: String, is_tool: bool = false) -> Control:
	"""Create a compact equipment slot with small icon + text label below"""
	# Main container - vertical layout with icon box and label
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.custom_minimum_size = Vector2(SLOT_SIZE + 20, SLOT_SIZE + 20)
	container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Slot control wrapper for drag-drop
	var slot_control = Control.new()
	slot_control.name = "Slot_" + slot_name
	slot_control.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
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

	# Panel for slot styling (matches InventoryUI)
	var panel = PanelContainer.new()
	panel.name = "SlotPanel"
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
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
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)  # Force size
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	blocked_label.add_theme_font_size_override("font_size", 24)
	blocked_label.add_theme_color_override("font_color", Color(0.6, 0.2, 0.2, 0.9))
	blocked_label.add_theme_color_override("font_outline_color", Color.BLACK)
	blocked_label.add_theme_constant_override("outline_size", 2)
	blocked_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocked_label.visible = false
	blocked_label.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
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
	"""Create a single equipment slot button with drag-drop support (legacy) - matches InventoryUI"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2(200, SLOT_SIZE)  # Fixed width so all slots align

	# Use a Control wrapper for drag-drop support
	var slot_control = Control.new()
	slot_control.name = "Equip_" + slot_name
	slot_control.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
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

	# Add panel for styling (matches InventoryUI)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# dreadland slot styling with deep inset
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

	# Add icon texture rect (matches InventoryUI)
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	label.custom_minimum_size = Vector2(SLOT_SIZE, 0)  # Limit width to slot size
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
	"""Create a single tool slot button with drag-drop support - matches InventoryUI"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2(200, SLOT_SIZE)  # Fixed width so all slots align

	# Use a Control wrapper for drag-drop support
	var slot_control = Control.new()
	slot_control.name = "Tool_" + tool_name
	slot_control.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
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

	# Add panel for styling (matches InventoryUI)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Let parent handle input
	slot_control.add_child(panel)

	# dreadland slot styling with deep inset
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

	# Add icon texture rect (matches InventoryUI)
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	label.custom_minimum_size = Vector2(SLOT_SIZE, 0)  # Limit width to slot size
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
			return "Increases damage with heavy weapons (swords, maces, guns)"
		"Agility":
			return "Increases damage with light weapons (daggers, bows)"
		"Dexterity":
			return "Increases melee critical hit chance"
		"Intelligence":
			return "Increases staff damage and healing power"
		"Wisdom":
			return "Increases mana pool and mana regeneration"
		"Vitality":
			return "Increases max HP and defense"
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
	"""Create a dreadland styled separator line"""
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
	"""Create a dreadland style for equipment/inventory slots with optional rarity glow"""
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
	"""Create dreadland style for inner panels"""
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
		# Check if an inspection panel is already open (from inventory)
		var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
		if inspection_ui and inspection_ui.is_visible:
			# Set flag BEFORE layout calculation
			_inspection_panel_open = true
			# Shift character panel and reposition inspection panel
			_shift_character_panel_only()
			var pos = _get_secondary_panel_position(INSPECTION_PANEL_WIDTH)
			inspection_ui.reposition(pos.offset_left, pos.offset_right)
			# Connect to restore when inspection closes
			if not inspection_ui.inspection_closed.is_connected(_on_inspection_closed):
				inspection_ui.inspection_closed.connect(_on_inspection_closed)
		refresh_all()
	else:
		# When closing character sheet, restore inspection panel to center if open
		var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
		if inspection_ui and inspection_ui.is_visible:
			inspection_ui.reset_to_center()
		# Reset all panel tracking flags
		_inspection_panel_open = false
		_skills_panel_open = false

func refresh_all() -> void:
	"""Refresh all UI elements"""
	refresh_character_info()
	refresh_stats()
	refresh_equipment()
	refresh_tools()
	refresh_weapon_mastery()

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
	# 6-stat system: STR, AGI, DEX, INT, WIS, VIT
	if stat_labels.has("strength"):
		stat_labels["strength"].text = str(CharacterStats.get_effective_strength())
	if stat_labels.has("agility"):
		stat_labels["agility"].text = str(CharacterStats.get_effective_agility())
	if stat_labels.has("dexterity"):
		stat_labels["dexterity"].text = str(CharacterStats.get_effective_dexterity())
	if stat_labels.has("intelligence"):
		stat_labels["intelligence"].text = str(CharacterStats.get_effective_intelligence())
	if stat_labels.has("wisdom"):
		stat_labels["wisdom"].text = str(CharacterStats.get_effective_wisdom())
	if stat_labels.has("vitality"):
		stat_labels["vitality"].text = str(CharacterStats.get_effective_vitality())

	# Derived stats
	if stat_labels.has("attack"):
		stat_labels["attack"].text = "%.1f" % CharacterStats.get_base_damage()
	if stat_labels.has("crit_chance"):
		stat_labels["crit_chance"].text = "%.1f%%" % (CharacterStats.get_base_crit_chance() * 100.0)
	if stat_labels.has("defense"):
		var defense = CharacterStats.get_total_defense()
		var equipped = CharacterStats.get_equipped_armor_count()
		stat_labels["defense"].text = "%d (%d/5)" % [defense, equipped]

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

			# Build tooltip - use rich format for forged weapons
			var tooltip = _build_equipment_tooltip(armor_item, slot_name)
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

			# Build tooltip with item name, rarity, and stats
			var item_name = tool_item.get("name", "Unknown")
			var tooltip = "[%s] (%s)" % [item_name, rarity]

			var description = tool_item.get("description", "")
			if description:
				tooltip += "\n%s" % description

			# Tool stats
			if tool_item.has("efficiency"):
				tooltip += "\n\nEfficiency: +%d%%" % (tool_item.get("efficiency", 0) * 100)
			if tool_item.has("durability"):
				tooltip += "\nDurability: %d" % tool_item.get("durability", 100)

			tooltip += "\n\n[Click and hold for details]"
			tooltip += "\n(Right-click to unequip)"

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
	"""Handle GUI input on equipment slot (click-and-hold to inspect, double-click/right-click to unequip)"""
	if event is InputEventMouseButton:
		if event.pressed:
			# Double-click to unequip
			if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				_cancel_long_hold()  # Cancel any ongoing hold
				_unequip_slot(slot_name)
			# Right-click to unequip
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_long_hold()  # Cancel any ongoing hold
				_unequip_slot(slot_name)
			# Single left-click starts hold timer for inspection
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_start_long_hold(slot_name, "equipment")
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mouse button released - cancel hold
			_cancel_long_hold()

func _unequip_slot(slot_name: String) -> void:
	"""Unequip item from slot"""
	if slot_name == "mainhand" and CharacterStats.equipped_weapon:
		if DEBUG_EQUIP:
			print("[Equip] Unequipping weapon: %s" % CharacterStats.equipped_weapon.weapon_name)
		if CharacterStats.unequip_weapon():
			SoundManager.play_equip_sound()
			refresh_all()
		else:
			if DEBUG_EQUIP:
				print("[Equip] Failed to unequip weapon (inventory full?)")
			# Notify player that inventory is full
			var notification_manager = get_node_or_null("/root/NotificationManager")
			if notification_manager and notification_manager.has_method("show_notification"):
				notification_manager.show_notification("Inventory full! Cannot unequip weapon.", "ERROR")
	else:
		var armor_item = CharacterStats.equipped_armor.get(slot_name)
		if armor_item:
			if CharacterStats.unequip_armor(slot_name):
				SoundManager.play_equip_sound()
				refresh_all()

# ============================================
# MOUSE CLICK-AND-HOLD RADIAL SYSTEM
# ============================================

func _start_long_hold(slot_name: String, slot_type: String) -> void:
	"""Start long-hold timer with cursor-following radial progress indicator"""
	_cancel_long_hold()
	_long_hold_slot = slot_name
	_long_hold_type = slot_type
	_long_hold_start_time = Time.get_ticks_msec() / 1000.0

	_long_hold_timer = Timer.new()
	_long_hold_timer.wait_time = LONG_HOLD_DURATION
	_long_hold_timer.one_shot = true
	_long_hold_timer.timeout.connect(_on_long_hold_triggered)
	add_child(_long_hold_timer)
	_long_hold_timer.start()

	# Create cursor-following radial progress indicator
	_radial_progress = _create_radial_progress()
	add_child(_radial_progress)

func _cancel_long_hold() -> void:
	"""Cancel long-hold timer and hide radial progress"""
	if _long_hold_timer:
		_long_hold_timer.stop()
		_long_hold_timer.queue_free()
		_long_hold_timer = null
	if _radial_progress:
		_radial_progress.queue_free()
		_radial_progress = null
	_long_hold_slot = ""
	_long_hold_type = ""
	_long_hold_start_time = 0.0

func _create_radial_progress() -> Control:
	"""Create a cursor-following radial progress indicator"""
	var radial = Control.new()
	radial.custom_minimum_size = Vector2(48, 48)
	radial.size = Vector2(48, 48)
	radial.z_index = 100
	radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial.set_meta("progress", 0.0)

	radial.draw.connect(func():
		var progress = radial.get_meta("progress", 0.0)
		var center = Vector2(24, 24)
		var radius = 18.0
		var inner_radius = 12.0

		# Dark backdrop disc
		radial.draw_circle(center, radius + 4, Color(0.0, 0.0, 0.0, 0.6))

		# Inner dark circle
		radial.draw_circle(center, inner_radius, Color(0.08, 0.08, 0.1, 0.9))

		# Track ring (subtle)
		radial.draw_arc(center, radius, 0, TAU, 48, Color(0.3, 0.3, 0.35, 0.5), 4.0)

		# Progress arc with glow effect
		if progress > 0:
			var start_angle = -PI/2
			var end_angle = -PI/2 + (progress * TAU)

			# Outer glow
			radial.draw_arc(center, radius, start_angle, end_angle, 48, Color(1.0, 0.75, 0.2, 0.3), 8.0)
			# Main arc
			radial.draw_arc(center, radius, start_angle, end_angle, 48, Color(1.0, 0.85, 0.3, 1.0), 4.0)
			# Inner bright edge
			radial.draw_arc(center, radius - 1, start_angle, end_angle, 48, Color(1.0, 0.95, 0.6, 0.8), 1.5)

			# Tip indicator dot
			var tip_pos = center + Vector2(cos(end_angle), sin(end_angle)) * radius
			radial.draw_circle(tip_pos, 4.0, Color(1.0, 0.95, 0.7, 1.0))
			radial.draw_circle(tip_pos, 2.5, Color(1.0, 1.0, 1.0, 1.0))

		# Center icon (magnifying glass hint)
		var icon_color = Color(0.6, 0.6, 0.65, 0.8) if progress == 0 else Color(1.0, 0.9, 0.5, 1.0)
		radial.draw_arc(center + Vector2(-2, -2), 5.0, 0, TAU, 16, icon_color, 1.5)
		radial.draw_line(center + Vector2(2, 2), center + Vector2(6, 6), icon_color, 1.5)
	)

	return radial

func _on_long_hold_triggered() -> void:
	"""Called when long-hold duration reached"""
	var slot_name = _long_hold_slot
	var slot_type = _long_hold_type
	_cancel_long_hold()

	if slot_name == "" or slot_type == "":
		return

	# Handle based on type
	if slot_type == "mastery":
		_open_weapon_skills_panel()
	elif slot_type == "equipment":
		# Get item data from equipment slot
		var item_data: Dictionary = {}
		if slot_name == "mainhand" and CharacterStats.equipped_weapon:
			item_data = CharacterStats.get_equipped_weapon_data()
		else:
			item_data = CharacterStats.equipped_armor.get(slot_name, {})

		if item_data and not item_data.is_empty():
			_open_item_inspection(item_data)

func _open_inspection_for_equipment(slot_name: String) -> void:
	"""Open inspection panel for equipped item in slot"""
	var item_data: Dictionary = {}
	if slot_name == "mainhand" and CharacterStats.equipped_weapon:
		item_data = CharacterStats.get_equipped_weapon_data()
	else:
		item_data = CharacterStats.equipped_armor.get(slot_name, {})

	if item_data and not item_data.is_empty():
		_open_item_inspection(item_data)

func _open_item_inspection(item_data: Dictionary) -> void:
	"""Open the item inspection panel side-by-side with character sheet"""
	var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
	if not inspection_ui:
		inspection_ui = get_node_or_null("/root/ItemInspectionUI")

	if not inspection_ui:
		var InspectionUIScene = load("res://scripts/ui/ItemInspectionUI.gd")
		if InspectionUIScene:
			inspection_ui = InspectionUIScene.new()
			inspection_ui.add_to_group("item_inspection_ui")
			get_tree().root.add_child(inspection_ui)

	if inspection_ui:
		# Set flag BEFORE layout calculation
		_inspection_panel_open = true
		# Only shift character panel (don't tween inspection since we're opening it fresh)
		_shift_character_panel_only()
		var pos = _get_secondary_panel_position(INSPECTION_PANEL_WIDTH)
		inspection_ui.position_beside(item_data, pos.offset_left, pos.offset_right)

		# Connect to restore position when inspection closes
		if not inspection_ui.inspection_closed.is_connected(_on_inspection_closed):
			inspection_ui.inspection_closed.connect(_on_inspection_closed)

# Standardized side-by-side panel layout constants
const PANEL_GAP: int = 8  # Minimal gap between side-by-side panels
const PANEL_EXTRA_GAP: int = 15  # Extra spacing for visual clarity
const CHARACTER_PANEL_WIDTH: int = 580
const INSPECTION_PANEL_WIDTH: int = 360
const SKILLS_PANEL_WIDTH: int = 500

func _calculate_multi_panel_layout() -> Dictionary:
	"""Calculate positions for all panels based on which are currently open.
	Returns a dictionary with positions for character, inspection, and skills panels.
	Layout order: Character (left) | Inspection (middle) | Skills (right)"""

	var panels_width: int = CHARACTER_PANEL_WIDTH
	var gap_total: int = 0

	if _inspection_panel_open:
		panels_width += INSPECTION_PANEL_WIDTH
		gap_total += PANEL_GAP + PANEL_EXTRA_GAP
	if _skills_panel_open:
		panels_width += SKILLS_PANEL_WIDTH
		gap_total += PANEL_GAP + PANEL_EXTRA_GAP

	var total_width = panels_width + gap_total
	var start_x = -total_width / 2

	# Character panel is always on the left
	var char_left = start_x
	var char_right = char_left + CHARACTER_PANEL_WIDTH

	# Inspection panel (middle, if open)
	var inspection_left = char_right + PANEL_GAP + PANEL_EXTRA_GAP
	var inspection_right = inspection_left + INSPECTION_PANEL_WIDTH

	# Skills panel (right, or middle if inspection not open)
	var skills_left: int
	var skills_right: int
	if _inspection_panel_open:
		skills_left = inspection_right + PANEL_GAP + PANEL_EXTRA_GAP
	else:
		skills_left = char_right + PANEL_GAP + PANEL_EXTRA_GAP
	skills_right = skills_left + SKILLS_PANEL_WIDTH

	return {
		"character": {"left": char_left, "right": char_right},
		"inspection": {"left": inspection_left, "right": inspection_right},
		"skills": {"left": skills_left, "right": skills_right}
	}

func _reposition_all_panels() -> void:
	"""Reposition all panels based on which are currently open"""
	var layout = _calculate_multi_panel_layout()

	# Animate character panel
	if main_panel:
		var tween = create_tween()
		if _inspection_panel_open or _skills_panel_open:
			tween.tween_property(main_panel, "offset_left", layout.character.left, 0.15)
			tween.parallel().tween_property(main_panel, "offset_right", layout.character.right, 0.15)
		else:
			# Center when no side panels
			tween.tween_property(main_panel, "offset_left", -290, 0.15)
			tween.parallel().tween_property(main_panel, "offset_right", 290, 0.15)

	# Reposition inspection panel if open and visible
	if _inspection_panel_open:
		var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
		if inspection_ui and inspection_ui.is_visible:
			inspection_ui.reposition(layout.inspection.left, layout.inspection.right)

	# Reposition skills panel if open
	if _skills_panel_open and _active_skills_panel and is_instance_valid(_active_skills_panel):
		var skills_panel = _active_skills_panel.get_node_or_null("SkillsPanel")
		if skills_panel:
			var tween = create_tween()
			tween.tween_property(skills_panel, "offset_left", layout.skills.left, 0.15)
			tween.parallel().tween_property(skills_panel, "offset_right", layout.skills.right, 0.15)

func _shift_character_panel_only() -> void:
	"""Shift only the character panel based on current layout (for opening new side panels)"""
	var layout = _calculate_multi_panel_layout()

	if main_panel:
		var tween = create_tween()
		tween.tween_property(main_panel, "offset_left", layout.character.left, 0.15)
		tween.parallel().tween_property(main_panel, "offset_right", layout.character.right, 0.15)

func _shift_panel_left_for(secondary_width: int) -> void:
	"""Shift character panel left to make room for a secondary panel of given width"""
	# Use the new multi-panel layout system
	_reposition_all_panels()

func _shift_panel_left() -> void:
	"""Shift the character panel to the left to make room for inspection panel"""
	_reposition_all_panels()

func _get_secondary_panel_position(secondary_width: int) -> Dictionary:
	"""Get the offset positions for a secondary panel beside the character panel"""
	var layout = _calculate_multi_panel_layout()

	# Return position based on which panel is being requested
	if secondary_width == INSPECTION_PANEL_WIDTH:
		return {"offset_left": layout.inspection.left, "offset_right": layout.inspection.right}
	elif secondary_width == SKILLS_PANEL_WIDTH:
		return {"offset_left": layout.skills.left, "offset_right": layout.skills.right}
	else:
		# Fallback for unknown panel sizes
		var total_width = CHARACTER_PANEL_WIDTH + PANEL_GAP + secondary_width
		var left_panel_right = -total_width / 2 + CHARACTER_PANEL_WIDTH
		var right_panel_left = left_panel_right + PANEL_GAP + PANEL_EXTRA_GAP
		var right_panel_right = right_panel_left + secondary_width
		return {"offset_left": right_panel_left, "offset_right": right_panel_right}

func _restore_panel_position() -> void:
	"""Restore the character panel to center position"""
	_reposition_all_panels()

func _on_inspection_closed() -> void:
	"""Called when inspection panel closes"""
	_inspection_panel_open = false
	_reposition_all_panels()

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

	# Handle base_damage - can be a number or a Dictionary with min/max
	var base_damage = item_dict.get("base_damage", 5.0)
	if base_damage is Dictionary:
		var dmg_min = base_damage.get("min", 5)
		var dmg_max = base_damage.get("max", 5)
		weapon.damage_min = float(dmg_min)
		weapon.damage_max = float(dmg_max)
		weapon.base_damage = (dmg_min + dmg_max) / 2.0
	elif base_damage is float or base_damage is int:
		weapon.base_damage = float(base_damage)
		# Check for separate damage_min/damage_max fields
		if item_dict.has("damage_min") and item_dict.has("damage_max"):
			weapon.damage_min = float(item_dict.get("damage_min"))
			weapon.damage_max = float(item_dict.get("damage_max"))
	else:
		weapon.base_damage = 5.0

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

	# Gun weapon properties (use explicit null checks since .get() returns null if key exists with null value)
	weapon.gun_radius = item_dict.get("gun_radius") if item_dict.get("gun_radius") != null else 28.0
	weapon.gun_range = item_dict.get("gun_range") if item_dict.get("gun_range") != null else 550.0
	weapon.gun_subtype = item_dict.get("gun_subtype") if item_dict.get("gun_subtype") != null else "railgun"
	weapon.burst_count = item_dict.get("burst_count") if item_dict.get("burst_count") != null else 1
	weapon.burst_delay = item_dict.get("burst_delay") if item_dict.get("burst_delay") != null else 0.10

	# Two-handed property - guns and bows are always two-handed (blocks offhand slot)
	var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
	weapon.is_two_handed = item_dict.get("is_two_handed", is_two_handed_type)

	return weapon

func _get_equipment_drag_data(at_position: Vector2, slot_name: String) -> Variant:
	"""Start dragging an equipped item"""
	# Special handling for mainhand - check equipped_weapon
	var armor_item = null
	if slot_name == "mainhand" and CharacterStats.equipped_weapon:
		# Prefer stored item data (preserves all properties including gun burst_count)
		if not CharacterStats.equipped_weapon_data.is_empty():
			armor_item = CharacterStats.equipped_weapon_data.duplicate(true)
		else:
			# Fallback: Convert Weapon resource to dict for dragging
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
			# Add gun weapon properties
			if weapon.is_gun_weapon():
				armor_item["gun_radius"] = weapon.gun_radius
				armor_item["gun_range"] = weapon.gun_range
				armor_item["gun_subtype"] = weapon.gun_subtype
				armor_item["burst_count"] = weapon.burst_count
				armor_item["burst_delay"] = weapon.burst_delay
			# Add healing weapon properties
			if weapon.attack_mode != "melee":
				armor_item["attack_mode"] = weapon.attack_mode
				armor_item["healing_power"] = weapon.healing_power
				armor_item["heal_radius"] = weapon.heal_radius
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

	# Rings can be equipped to either ring1 or ring2 slot
	# Check both item_type and slot since rings have slot="ring1" but can go to ring2
	if (item_type == "ring" or item_slot in ["ring", "ring1", "ring2"]) and slot_name in ["ring1", "ring2"]:
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

	# Allow rings to go to either ring slot
	# Check both item_type and slot since rings have slot="ring1" but can go to ring2
	var is_ring_to_ring_slot = ((item_type == "ring" or item_slot in ["ring", "ring1", "ring2"]) and slot_name in ["ring1", "ring2"])

	if item_slot != slot_name and not is_shield_to_offhand and not is_ring_to_ring_slot:
		return

	if source_type == "inventory":
		# Equip from inventory
		var source_index = data.get("source_index", -1)
		if source_index >= 0:
			var equipped = false

			# Check if it's a weapon
			if dragged_item.get("type", "") == "weapon" and slot_name == "mainhand":
				# Convert dict to Weapon resource
				var weapon = dict_to_weapon(dragged_item)
				if weapon:
					# If there's already a weapon equipped, do a direct swap
					if CharacterStats.equipped_weapon:
						if DEBUG_EQUIP:
							print("[Equip] Swapping weapons - %s for %s" % [CharacterStats.equipped_weapon.weapon_name, weapon.weapon_name])
						# Get the old weapon data before clearing it
						var old_weapon_dict = CharacterStats.get_equipped_weapon_data()
						if old_weapon_dict.is_empty():
							old_weapon_dict = CharacterStats.get_weapon_as_dict()

						# Clear the equipped weapon without adding to inventory
						CharacterStats.equipped_weapon = null
						CharacterStats.equipped_weapon_data = {}
						CharacterStats.weapon_unequipped.emit()

						# Put old weapon into the inventory slot where new weapon was
						InventorySystem.set_item(source_index, old_weapon_dict)

						# Equip the new weapon (don't remove from inventory - we already swapped)
						CharacterStats.equip_weapon(weapon, dragged_item)
						SoundManager.play_equip_sound()
						refresh_all()
						return  # Exit early - we handled the swap directly
					else:
						# No weapon equipped, equip normally
						CharacterStats.equip_weapon(weapon, dragged_item)
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
			# Check if it's a ring going to ring1/ring2
			elif is_ring_to_ring_slot:
				# If there's already something in this ring slot, unequip it first
				if CharacterStats.equipped_armor[slot_name]:
					if DEBUG_EQUIP:
						print("[Equip] Swapping ring - unequipping existing item first")
					CharacterStats.unequip_armor(slot_name)
				# Set the slot to the target ring slot for proper equipping
				var ring_item = dragged_item.duplicate()
				ring_item["slot"] = slot_name
				equipped = CharacterStats.equip_armor(ring_item)
				if DEBUG_EQUIP:
					print("[Equip] Ring equipped to %s: %s" % [slot_name, ring_item.get("name", "Unknown")])
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

func _build_equipment_tooltip(item: Dictionary, slot_name: String) -> String:
	"""Build tooltip for equipped item - rich format for forged weapons"""
	var item_name = item.get("name", "Unknown")
	var rarity = item.get("rarity", "COMMON")
	var is_forged = item.get("is_forged", false)

	# Check if this is a forged weapon with stats
	var weapon: Weapon = null
	if slot_name == "mainhand" and CharacterStats.equipped_weapon:
		weapon = CharacterStats.equipped_weapon
		is_forged = weapon.is_forged

	# For forged weapons with stats, use rich tooltip format
	if is_forged and weapon and weapon.weapon_stats:
		var stats = weapon.weapon_stats
		var visual_tier = stats.get_visual_tier_name()

		# Header with level
		var tooltip = "[%s] Lv. %d" % [item_name, stats.level]
		tooltip += "\n%s" % rarity
		if visual_tier != "":
			tooltip += " · %s" % visual_tier

		# Virgin badge
		if stats.is_virgin():
			tooltip += "\n\n✧ PRISTINE ✧"
			tooltip += "\nNever drawn in battle"
		else:
			# Kill stats
			tooltip += "\n\n%s kills" % WeaponStatsDisplay.format_number(stats.kills_total)
			var crit_rate = stats.get_crit_rate_lifetime()
			if crit_rate > 0:
				tooltip += " · %.1f%% crit" % crit_rate

			# Top achievements
			if stats.achievements.size() > 0:
				var icons = ""
				var count = mini(stats.achievements.size(), 3)
				for i in range(count):
					icons += stats.get_achievement_icon(stats.achievements[i])
				tooltip += "\n" + icons

		# Combat stats
		tooltip += "\n"
		var damage_display = weapon.get_damage_display()
		# Calculate actual bonus from level using percentage-based multiplier
		var damage_bonus = stats.get_damage_bonus_for_base(weapon.base_damage)
		if damage_bonus > 0:
			tooltip += "\nDamage: +%s (+%.1f from level)" % [damage_display, damage_bonus]
		else:
			tooltip += "\nDamage: +%s" % damage_display

		var crit_bonus = stats.get_crit_bonus() * 100
		if crit_bonus > 0:
			tooltip += "\nCrit Bonus: +%.1f%%" % crit_bonus

		# Weapon type
		var weapon_type = item.get("weapon_type", weapon.weapon_type)
		if weapon_type:
			tooltip += "\nType: %s" % weapon_type.capitalize()

		# Max hit brag
		if stats.damage_max_hit > 0:
			tooltip += "\nMax Hit: %s" % WeaponStatsDisplay.format_number(stats.damage_max_hit)

		# Level progress
		var progress = stats.get_level_progress() * 100
		tooltip += "\n\nLevel Progress: %.0f%%" % progress

		tooltip += "\n\n[Click and hold for details]"
		return tooltip

	# Standard tooltip for non-forged items
	var tooltip = "[%s] (%s)" % [item_name, rarity]

	var description = item.get("description", "")
	if description:
		tooltip += "\n%s" % description

	# Weapon stats (for mainhand/offhand)
	if item.get("type") == "weapon":
		tooltip += "\n"
		if item.has("base_damage"):
			var base_dmg = item.get("base_damage", 0)
			if base_dmg is Dictionary:
				tooltip += "\nDamage: +%d-%d" % [int(base_dmg.get("min", 0)), int(base_dmg.get("max", 0))]
			elif item.has("damage_min") and item.has("damage_max"):
				tooltip += "\nDamage: +%d-%d" % [int(item.get("damage_min")), int(item.get("damage_max"))]
			else:
				tooltip += "\nDamage: +%.1f" % base_dmg
		if item.has("attack_speed_bonus"):
			var speed_bonus = item.get("attack_speed_bonus", 0.0)
			if speed_bonus != 0:
				tooltip += "\nAttack Speed: %+.1f%%" % (speed_bonus * 100)
		# Show weapon type
		var weapon_type = item.get("weapon_type", "")
		if weapon_type:
			tooltip += "\nType: %s" % weapon_type.capitalize()
	# Armor stats
	elif item.has("defense"):
		tooltip += "\n\nDefense: +%d" % item.get("defense", 0)

	# Display stat bonuses (STR, VIT, DEX, AGI, INT, WIS)
	if item.has("stat_bonuses"):
		var bonuses = item.get("stat_bonuses", {})
		var stat_parts = []
		if bonuses.get("str", 0) > 0:
			stat_parts.append("+%d STR" % bonuses.get("str"))
		if bonuses.get("vit", 0) > 0:
			stat_parts.append("+%d VIT" % bonuses.get("vit"))
		if bonuses.get("dex", 0) > 0:
			stat_parts.append("+%d DEX" % bonuses.get("dex"))
		if bonuses.get("agi", 0) > 0:
			stat_parts.append("+%d AGI" % bonuses.get("agi"))
		if bonuses.get("int", 0) > 0:
			stat_parts.append("+%d INT" % bonuses.get("int"))
		if bonuses.get("wis", 0) > 0:
			stat_parts.append("+%d WIS" % bonuses.get("wis"))
		if stat_parts.size() > 0:
			tooltip += "\n" + ", ".join(stat_parts)

	# Accessory bonuses
	if item.has("hp_bonus"):
		tooltip += "\nHP: +%d" % item.get("hp_bonus", 0)

	# Action hint
	tooltip += "\n\n[Click and hold for details]"
	tooltip += "\n(Right-click to unequip)"

	return tooltip

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
