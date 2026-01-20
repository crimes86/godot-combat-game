extends CanvasLayer

## PlayerInspectUI - Read-only view of another player's equipped gear
## Shows equipment slots and basic stats in a paperdoll layout
##
## Data is requested via RPC from the target player

signal inspection_closed

# UI colors from UITheme singleton
var BG_COLOR: Color:
	get: return UITheme.BG_COLOR
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR
var TEXT_COLOR: Color:
	get: return UITheme.TEXT_COLOR
var HEADER_COLOR: Color:
	get: return UITheme.HEADER_COLOR
var ACCENT_COLOR: Color:
	get: return UITheme.ACCENT_COLOR
var SLOT_BG: Color:
	get: return UITheme.SLOT_BG

# Slot sizes (match CharacterUI)
const SLOT_SIZE = 54
const ICON_SIZE = 46

# Inspection state
var target_player_id: int = -1
var target_player_name: String = ""
var target_player_node: Node2D = null
var is_visible: bool = false
var pending_request: bool = false

# Equipment data received from target
var equipment_data: Dictionary = {}

# UI elements
var main_panel: PanelContainer
var header_label: Label
var loading_label: Label
var equipment_container: VBoxContainer
var stats_row: HBoxContainer
var equipment_slots: Dictionary = {}

func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return

	layer = 118  # Above interaction menu (115), below character sheet (120)
	_create_ui()
	# Ensure panel starts hidden
	main_panel.visible = false
	is_visible = false

func _input(event: InputEvent) -> void:
	if not is_visible:
		return

	# Close on Escape
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			hide_inspection()
			get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func show_inspection(player_id: int, player_name: String, player_node: Node2D = null) -> void:
	"""Show inspection UI for a target player"""
	target_player_id = player_id
	target_player_name = player_name
	target_player_node = player_node

	# Update header
	if header_label:
		header_label.text = "Inspecting: %s" % player_name

	# Check if this is a bot (IDs >= 20000)
	if player_id >= 20000:
		_show_bot_info()
		# Show panel
		main_panel.visible = true
		is_visible = true
		# Fade in
		main_panel.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(main_panel, "modulate:a", 1.0, 0.15)
		if SoundManager:
			SoundManager.play_inventory_open_sound()
		return

	# Show loading state
	_show_loading()

	# Request equipment data
	pending_request = true
	_request_equipment_data()

	# Show panel
	main_panel.visible = true
	is_visible = true

	# Fade in
	main_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(main_panel, "modulate:a", 1.0, 0.15)

	if SoundManager:
		SoundManager.play_inventory_open_sound()

func hide_inspection() -> void:
	"""Hide the inspection UI"""
	if not is_visible:
		return

	is_visible = false
	pending_request = false

	var tween = create_tween()
	tween.tween_property(main_panel, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func(): main_panel.visible = false)

	# Clear state
	target_player_id = -1
	target_player_name = ""
	target_player_node = null
	equipment_data = {}

	inspection_closed.emit()

func receive_equipment_data(data: Dictionary) -> void:
	"""Called when equipment data is received from target player"""
	if not pending_request:
		return

	pending_request = false
	equipment_data = data

	# Hide loading, show equipment
	_hide_loading()
	_display_equipment(data)

# ═══════════════════════════════════════════════════════════════════════════
# EQUIPMENT DATA REQUEST
# ═══════════════════════════════════════════════════════════════════════════

func _request_equipment_data() -> void:
	"""Request equipment data from target player via RPC"""
	if target_player_node and is_instance_valid(target_player_node):
		if target_player_node.has_method("request_equipment_for_inspection"):
			var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
			target_player_node.request_equipment_for_inspection.rpc_id(target_player_id, my_id)
		else:
			# Fallback: Try to get visible appearance data
			_display_fallback_data()
	else:
		# No node available
		_display_fallback_data()

func _display_fallback_data() -> void:
	"""Display fallback when RPC isn't available"""
	_hide_loading()
	# Show "Data unavailable" message
	if loading_label:
		loading_label.text = "Equipment data unavailable"
		loading_label.visible = true

# ═══════════════════════════════════════════════════════════════════════════
# UI CREATION
# ═══════════════════════════════════════════════════════════════════════════

func _create_ui() -> void:
	"""Create the inspection UI"""
	main_panel = PanelContainer.new()
	main_panel.name = "InspectPanel"

	# Position - right side of screen
	main_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	main_panel.custom_minimum_size = Vector2(300, 500)
	main_panel.offset_left = -320
	main_panel.offset_right = -20
	main_panel.offset_top = -250
	main_panel.offset_bottom = 250

	# Panel styling
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
	panel_style.shadow_size = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	main_panel.add_child(margin)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row with close button
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	vbox.add_child(header_row)

	header_label = Label.new()
	header_label.text = "Inspecting: Player"
	header_label.add_theme_font_size_override("font_size", 16)
	header_label.add_theme_color_override("font_color", HEADER_COLOR)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_label)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(hide_inspection)
	_style_close_button(close_btn)
	header_row.add_child(close_btn)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Loading label
	loading_label = Label.new()
	loading_label.text = "Loading..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_color_override("font_color", ACCENT_COLOR)
	loading_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(loading_label)

	# Equipment container (paperdoll layout)
	equipment_container = VBoxContainer.new()
	equipment_container.add_theme_constant_override("separation", 4)
	equipment_container.visible = false
	vbox.add_child(equipment_container)

	_create_equipment_slots()

	# Stats row at bottom
	var stats_sep = HSeparator.new()
	vbox.add_child(stats_sep)

	stats_row = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 20)
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.visible = false
	vbox.add_child(stats_row)

	_create_stats_row()

	add_child(main_panel)

func _create_equipment_slots() -> void:
	"""Create paperdoll equipment slot layout"""
	# Row 1: Head (centered)
	var row1 = CenterContainer.new()
	equipment_container.add_child(row1)
	var head_slot = _create_slot("head", "Head")
	row1.add_child(head_slot)
	equipment_slots["head"] = head_slot

	# Row 2: Amulet + Back
	var row2_center = CenterContainer.new()
	equipment_container.add_child(row2_center)
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	row2_center.add_child(row2)

	var amulet_slot = _create_slot("amulet", "Amulet")
	row2.add_child(amulet_slot)
	equipment_slots["amulet"] = amulet_slot

	var back_slot = _create_slot("back", "Back")
	row2.add_child(back_slot)
	equipment_slots["back"] = back_slot

	# Row 3: Mainhand - Chest - Offhand
	var row3_center = CenterContainer.new()
	equipment_container.add_child(row3_center)
	var row3 = HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	row3_center.add_child(row3)

	var mainhand_slot = _create_slot("mainhand", "Main")
	row3.add_child(mainhand_slot)
	equipment_slots["mainhand"] = mainhand_slot

	var chest_slot = _create_slot("chest", "Chest")
	row3.add_child(chest_slot)
	equipment_slots["chest"] = chest_slot

	var offhand_slot = _create_slot("offhand", "Off")
	row3.add_child(offhand_slot)
	equipment_slots["offhand"] = offhand_slot

	# Row 4: Arms
	var row4 = CenterContainer.new()
	equipment_container.add_child(row4)
	var arms_slot = _create_slot("arms", "Arms")
	row4.add_child(arms_slot)
	equipment_slots["arms"] = arms_slot

	# Row 5: Ring1 - Hands - Ring2
	var row5_center = CenterContainer.new()
	equipment_container.add_child(row5_center)
	var row5 = HBoxContainer.new()
	row5.add_theme_constant_override("separation", 4)
	row5_center.add_child(row5)

	var ring1_slot = _create_slot("ring1", "Ring")
	row5.add_child(ring1_slot)
	equipment_slots["ring1"] = ring1_slot

	var hands_slot = _create_slot("hands", "Hands")
	row5.add_child(hands_slot)
	equipment_slots["hands"] = hands_slot

	var ring2_slot = _create_slot("ring2", "Ring")
	row5.add_child(ring2_slot)
	equipment_slots["ring2"] = ring2_slot

	# Row 6: Legs + Feet
	var row6_center = CenterContainer.new()
	equipment_container.add_child(row6_center)
	var row6 = HBoxContainer.new()
	row6.add_theme_constant_override("separation", 8)
	row6_center.add_child(row6)

	var legs_slot = _create_slot("legs", "Legs")
	row6.add_child(legs_slot)
	equipment_slots["legs"] = legs_slot

	var feet_slot = _create_slot("feet", "Feet")
	row6.add_child(feet_slot)
	equipment_slots["feet"] = feet_slot

func _create_slot(slot_name: String, label_text: String) -> Control:
	"""Create a single read-only equipment slot"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)
	container.custom_minimum_size = Vector2(SLOT_SIZE + 16, SLOT_SIZE + 20)

	# Slot panel
	var panel = PanelContainer.new()
	panel.name = "SlotPanel"
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

	var slot_style = StyleBoxFlat.new()
	slot_style.bg_color = SLOT_BG
	slot_style.border_width_left = 1
	slot_style.border_width_right = 1
	slot_style.border_width_top = 1
	slot_style.border_width_bottom = 1
	slot_style.border_color = Color(0.2, 0.2, 0.22, 0.8)
	slot_style.corner_radius_top_left = 4
	slot_style.corner_radius_top_right = 4
	slot_style.corner_radius_bottom_left = 4
	slot_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", slot_style)

	# Icon container
	var icon_center = CenterContainer.new()
	panel.add_child(icon_center)

	var icon_rect = TextureRect.new()
	icon_rect.name = "ItemIcon"
	icon_rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.visible = false
	icon_center.add_child(icon_rect)

	# Slot center
	var slot_center = CenterContainer.new()
	slot_center.add_child(panel)
	container.add_child(slot_center)

	# Label
	var type_label = Label.new()
	type_label.name = "SlotLabel"
	type_label.text = label_text
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 9)
	type_label.add_theme_color_override("font_color", ACCENT_COLOR)
	container.add_child(type_label)

	# Store slot metadata
	container.set_meta("slot_name", slot_name)

	return container

func _create_stats_row() -> void:
	"""Create stats display row"""
	# Attack
	var atk_label = Label.new()
	atk_label.name = "AtkLabel"
	atk_label.text = "ATK: --"
	atk_label.add_theme_font_size_override("font_size", 12)
	atk_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4, 1.0))
	stats_row.add_child(atk_label)

	# Defense
	var def_label = Label.new()
	def_label.name = "DefLabel"
	def_label.text = "DEF: --"
	def_label.add_theme_font_size_override("font_size", 12)
	def_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 1.0))
	stats_row.add_child(def_label)

	# Level
	var lvl_label = Label.new()
	lvl_label.name = "LvlLabel"
	lvl_label.text = "Lv: --"
	lvl_label.add_theme_font_size_override("font_size", 12)
	lvl_label.add_theme_color_override("font_color", HEADER_COLOR)
	stats_row.add_child(lvl_label)

func _style_close_button(button: Button) -> void:
	"""Style close button"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.2, 0.2, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	var hover = style.duplicate()
	hover.bg_color = Color(0.7, 0.3, 0.3, 0.8)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", Color.WHITE)

# ═══════════════════════════════════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════════════════════════════════

func _show_loading() -> void:
	"""Show loading state"""
	if loading_label:
		loading_label.text = "Loading..."
		loading_label.visible = true
	if equipment_container:
		equipment_container.visible = false
	if stats_row:
		stats_row.visible = false

func _hide_loading() -> void:
	"""Hide loading state"""
	if loading_label:
		loading_label.visible = false
	if equipment_container:
		equipment_container.visible = true
	if stats_row:
		stats_row.visible = true

func _show_bot_info() -> void:
	"""Show info for bot players (stress test bots)"""
	if loading_label:
		loading_label.text = "🤖 Stress Test Bot\n\nThis is an automated bot for\nserver load testing.\n\nBots cannot be dueled or traded with."
		loading_label.visible = true
	if equipment_container:
		equipment_container.visible = false
	if stats_row:
		stats_row.visible = false

func _display_equipment(data: Dictionary) -> void:
	"""Display equipment from received data"""
	var armor = data.get("equipped_armor", {})
	var weapon = data.get("equipped_weapon", {})

	# Clear all slots first
	for slot_name in equipment_slots:
		_clear_slot(slot_name)

	# Display armor pieces
	for slot_name in armor:
		if armor[slot_name] and armor[slot_name] is Dictionary:
			_display_slot_item(slot_name, armor[slot_name])

	# Display weapon in mainhand
	if weapon and not weapon.is_empty():
		_display_slot_item("mainhand", weapon)

	# Update stats
	var stats = data.get("stats", {})
	_update_stats_display(
		stats.get("attack", 0),
		stats.get("defense", 0),
		data.get("level", 1)
	)

func _display_slot_item(slot_name: String, item: Dictionary) -> void:
	"""Display an item in a slot"""
	if not equipment_slots.has(slot_name):
		return

	var container = equipment_slots[slot_name]
	var icon_rect = _find_node_recursive(container, "ItemIcon")
	var label = _find_node_recursive(container, "SlotLabel")

	if not icon_rect:
		return

	# Try to get item icon
	var icon_texture = _get_item_icon(item)
	if icon_texture:
		icon_rect.texture = icon_texture
		icon_rect.visible = true
	else:
		icon_rect.visible = false

	# Update label with item name
	if label and item.has("name"):
		var item_name = item.get("name", "")
		if item_name.length() > 8:
			item_name = item_name.substr(0, 7) + "..."
		label.text = item_name
		label.add_theme_color_override("font_color", _get_rarity_color(item.get("rarity", "COMMON")))

func _clear_slot(slot_name: String) -> void:
	"""Clear a slot display"""
	if not equipment_slots.has(slot_name):
		return

	var container = equipment_slots[slot_name]
	var icon_rect = _find_node_recursive(container, "ItemIcon")
	var label = _find_node_recursive(container, "SlotLabel")

	if icon_rect:
		icon_rect.texture = null
		icon_rect.visible = false

	# Reset label to slot name
	if label:
		var slot_display = slot_name.capitalize()
		if slot_name == "mainhand":
			slot_display = "Main"
		elif slot_name == "offhand":
			slot_display = "Off"
		elif slot_name in ["ring1", "ring2"]:
			slot_display = "Ring"
		label.text = slot_display
		label.add_theme_color_override("font_color", ACCENT_COLOR)

func _update_stats_display(attack: float, defense: int, level: int) -> void:
	"""Update stats display"""
	var atk_label = stats_row.get_node_or_null("AtkLabel")
	var def_label = stats_row.get_node_or_null("DefLabel")
	var lvl_label = stats_row.get_node_or_null("LvlLabel")

	if atk_label:
		atk_label.text = "ATK: %.1f" % attack
	if def_label:
		def_label.text = "DEF: %d" % defense
	if lvl_label:
		lvl_label.text = "Lv: %d" % level

func _get_item_icon(item: Dictionary) -> Texture2D:
	"""Get icon texture for an item"""
	if ItemIconGenerator:
		return ItemIconGenerator.get_item_icon(item)
	return null

func _get_rarity_color(rarity) -> Color:
	"""Get color for item rarity"""
	var rarity_str = str(rarity).to_upper()
	match rarity_str:
		"COMMON", "0":
			return UITheme.RARITY_COMMON
		"UNCOMMON", "1":
			return UITheme.RARITY_UNCOMMON
		"RARE", "2":
			return UITheme.RARITY_RARE
		"EPIC", "3":
			return UITheme.RARITY_EPIC
		"LEGENDARY", "4":
			return UITheme.RARITY_LEGENDARY
		"MYTHIC", "5":
			return UITheme.RARITY_MYTHIC
		_:
			return ACCENT_COLOR

func _find_node_recursive(node: Node, node_name: String) -> Node:
	"""Find a node by name recursively"""
	if node.name == node_name:
		return node
	for child in node.get_children():
		var found = _find_node_recursive(child, node_name)
		if found:
			return found
	return null
