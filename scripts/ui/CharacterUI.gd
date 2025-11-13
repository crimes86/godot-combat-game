extends CanvasLayer

## Character UI - EverQuest-style unified character sheet
## Combines character info, stats, equipment, and inventory in one window
## Press C to toggle

var is_visible: bool = false

# UI References
var main_panel: PanelContainer
var equipment_slots: Dictionary = {}  # slot_name: VBoxContainer (contains CenterContainer with Button + Label)
var inventory_slots: Array[Button] = []
var stat_labels: Dictionary = {}  # stat_name: Label
var character_name_label: Label
var level_label: Label
var xp_bar: ProgressBar
var gold_label: Label
var hp_label: Label
var defense_label: Label

# EverQuest color palette
const BG_COLOR = Color(0.25, 0.25, 0.28, 0.95)  # Stone grey background
const BORDER_COLOR = Color(0.42, 0.41, 0.41, 1.0)  # Stone gray border
const TEXT_COLOR = Color(1.0, 1.0, 1.0, 1.0)  # White text
const HEADER_COLOR = Color(1.0, 1.0, 1.0, 1.0)  # White headers
const HP_COLOR = Color(0.77, 0.19, 0.19, 1.0)  # Red
const XP_COLOR = Color(0.26, 0.60, 0.83, 1.0)  # Blue
const BUFF_COLOR = Color(0.2, 0.9, 0.2, 1.0)  # Green for buffed stats
const DEBUFF_COLOR = Color(0.9, 0.2, 0.2, 1.0)  # Red for debuffed stats

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

	# Modern polished background with rounded corners and shadow
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.6, 0.6, 1.0)  # Lighter border for contrast

	# Rounded corners for modern look
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12

	# Drop shadow for depth
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_offset = Vector2(0, 4)

	main_panel.add_theme_stylebox_override("panel", panel_style)

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
	var slot_names = ["mainhand", "offhand", "head", "chest", "hands", "legs", "feet"]
	var slot_labels = {
		"mainhand": "MAIN HAND",
		"offhand": "OFF HAND",
		"head": "HEAD",
		"chest": "CHEST",
		"hands": "HANDS",
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

	# Modern styled progress bar
	var xp_bg = StyleBoxFlat.new()
	xp_bg.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	xp_bg.border_width_left = 1
	xp_bg.border_width_right = 1
	xp_bg.border_width_top = 1
	xp_bg.border_width_bottom = 1
	xp_bg.border_color = Color(0.4, 0.4, 0.45, 0.6)
	xp_bg.corner_radius_top_left = 4
	xp_bg.corner_radius_top_right = 4
	xp_bg.corner_radius_bottom_left = 4
	xp_bg.corner_radius_bottom_right = 4

	var xp_fill = StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.3, 0.65, 0.9, 1.0)  # Bright blue
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
	"""Create a single equipment slot button"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Button centered in a CenterContainer
	var button_center = CenterContainer.new()
	container.add_child(button_center)

	var button = Button.new()
	button.name = "Equip_" + slot_name
	button.custom_minimum_size = Vector2(60, 60)
	button.text = ""

	# Modern slot styling with smooth hover transitions
	var slot_style_normal = create_slot_style(Color(0.2, 0.2, 0.25, 1.0))
	var slot_style_hover = create_slot_style(Color(0.28, 0.32, 0.38, 1.0))  # Brighter on hover
	var slot_style_pressed = create_slot_style(Color(0.15, 0.18, 0.22, 1.0))  # Darker when pressed

	button.add_theme_stylebox_override("normal", slot_style_normal)
	button.add_theme_stylebox_override("hover", slot_style_hover)
	button.add_theme_stylebox_override("pressed", slot_style_pressed)

	button.pressed.connect(_on_equipment_slot_clicked.bind(slot_name))
	button_center.add_child(button)

	# Label centered below button
	var label = create_text_label(label_text, 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container

func create_inventory_slot(slot_index: int) -> Button:
	"""Create a single inventory slot button"""
	var button = Button.new()
	button.name = "InvSlot_" + str(slot_index)
	button.custom_minimum_size = Vector2(70, 70)
	button.text = ""

	# Modern slot styling with smooth hover transitions
	var slot_style_normal = create_slot_style(Color(0.2, 0.2, 0.25, 1.0))
	var slot_style_hover = create_slot_style(Color(0.28, 0.32, 0.38, 1.0))  # Brighter on hover
	var slot_style_pressed = create_slot_style(Color(0.15, 0.18, 0.22, 1.0))  # Darker when pressed

	button.add_theme_stylebox_override("normal", slot_style_normal)
	button.add_theme_stylebox_override("hover", slot_style_hover)
	button.add_theme_stylebox_override("pressed", slot_style_pressed)

	button.pressed.connect(_on_inventory_slot_clicked.bind(slot_index))

	return button

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
	"""Create a modern styled separator line"""
	var separator_container = MarginContainer.new()
	separator_container.add_theme_constant_override("margin_top", 8)
	separator_container.add_theme_constant_override("margin_bottom", 8)
	separator_container.add_theme_constant_override("margin_left", 20)
	separator_container.add_theme_constant_override("margin_right", 20)

	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 2)

	# Create styled separator with gradient effect
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.5, 0.55, 0.6)  # Lighter grey with transparency
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", sep_style)

	separator_container.add_child(separator)
	return separator_container

func create_slot_style(bg_color: Color) -> StyleBoxFlat:
	"""Create a modern style for equipment/inventory slots"""
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.55, 0.8)  # Lighter border for modern look

	# Rounded corners for modern feel
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6

	# Subtle inner shadow for depth
	style.shadow_size = 2
	style.shadow_color = Color(0, 0, 0, 0.3)

	return style

func create_inner_panel_style() -> StyleBoxFlat:
	"""Create modern style for inner panels"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.23, 0.5)  # Darker stone grey

	# Modern rounded borders
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.5, 0.55, 0.4)

	# Rounded corners
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	return style

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
		var button = button_center.get_child(0) as Button

		var armor_item = CharacterStats.equipped_armor[slot_name]
		if armor_item:
			button.text = armor_item.get("name", "???")
			button.tooltip_text = "%s\nDefense: +%d" % [armor_item.get("description", ""), armor_item.get("defense", 0)]
		else:
			button.text = ""
			button.tooltip_text = "Empty " + slot_name + " slot"

func refresh_inventory() -> void:
	"""Update inventory slot displays"""
	for i in range(inventory_slots.size()):
		var button = inventory_slots[i]
		var item = InventorySystem.get_item(i)

		if item and item.size() > 0:
			var item_name = item.get("name", "???")
			var quantity = item.get("quantity", 1)
			var is_stackable = item.get("stackable", false)

			if is_stackable and quantity > 1:
				button.text = "%s x%d" % [item_name, quantity]
			else:
				button.text = item_name

			var tooltip = item.get("description", "")
			if item.has("defense"):
				tooltip += "\nDefense: +%d" % item.get("defense", 0)
			if item.has("value"):
				tooltip += "\nValue: %d gold" % item.get("value", 0)
			button.tooltip_text = tooltip
		else:
			button.text = ""
			button.tooltip_text = "Empty slot"

func _on_equipment_slot_clicked(slot_name: String) -> void:
	"""Handle clicking an equipment slot (unequip)"""
	var armor_item = CharacterStats.equipped_armor[slot_name]
	if armor_item:
		if CharacterStats.unequip_armor(slot_name):
			refresh_all()
			print("✅ Unequipped %s" % armor_item.get("name", "Unknown"))
	else:
		print("No armor equipped in %s slot" % slot_name)

func _on_inventory_slot_clicked(slot_index: int) -> void:
	"""Handle clicking an inventory slot (equip if armor)"""
	var item = InventorySystem.get_item(slot_index)

	if item and item.size() > 0:
		# Check if it's armor
		if item.has("slot") and item.get("slot", "") in CharacterStats.equipped_armor:
			# Try to equip it
			if CharacterStats.equip_armor(item):
				# Remove from inventory
				InventorySystem.remove_item(slot_index)
				refresh_all()
				print("✅ Equipped %s" % item.get("name", "Unknown"))
		else:
			print("🖱️ Clicked item: %s (not equippable)" % item.get("name", "Unknown"))
	else:
		print("🖱️ Clicked empty slot %d" % slot_index)

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
	refresh_inventory()
