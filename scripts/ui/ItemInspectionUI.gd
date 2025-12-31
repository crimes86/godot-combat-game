extends CanvasLayer
## Item Inspection UI - Shows detailed provenance for forged items
## Right-click or long-press on forged items to inspect

signal inspection_closed

# UI colors from UITheme
var BG_COLOR: Color:
	get: return UITheme.BG_COLOR
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR
var ACCENT_COLOR: Color:
	get: return UITheme.ACCENT_COLOR
var TEXT_COLOR: Color:
	get: return UITheme.TEXT_COLOR
var HEADER_COLOR: Color:
	get: return UITheme.HEADER_COLOR
var INPUT_BG: Color:
	get: return UITheme.INPUT_BG

# UI elements
var main_panel: PanelContainer
var is_visible: bool = false
var current_item: Dictionary = {}

func _is_forged_item(item: Dictionary) -> bool:
	"""Check if an item is forged using multiple detection methods"""
	# Direct flags
	if item.get("is_forged", false):
		return true
	if item.get("forged", false):
		return true
	# ID-based checks
	if item.get("forged_id", "") != "":
		return true
	if item.get("forged_item_id", "") != "":
		return true
	if item.get("token_id", 0) > 0:
		return true
	# Fallback: check if item_id exists in ForgeItemDB
	var item_id = item.get("item_id", "")
	if item_id != "" and ForgeItemDB:
		var forge_db_item = ForgeItemDB.get_item_by_id(item_id)
		if not forge_db_item.is_empty():
			return true
	return false

func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return

	layer = 120  # Above most UI
	add_to_group("item_inspection_ui")
	_create_ui()
	hide_panel()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ESCAPE or event.keycode == KEY_F) and is_visible:
			hide_panel()
			get_viewport().set_input_as_handled()

func _create_ui() -> void:
	"""Create the inspection panel UI - compact layout"""

	# Main panel - centered modal
	main_panel = PanelContainer.new()
	main_panel.name = "InspectionPanel"

	# Center on screen - size to accommodate item stats + combat stats + provenance
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(360, 600)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -180
	main_panel.offset_right = 180
	main_panel.offset_top = -300
	main_panel.offset_bottom = 300

	# Apply styling
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
	panel_style.shadow_color = Color(0, 0, 0, 0.7)
	panel_style.shadow_offset = Vector2(0, 4)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	main_panel.add_child(margin)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row (icon + name/rarity + close button)
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	vbox.add_child(header_row)

	# Icon container - same size as inventory (54x54)
	var icon_container = PanelContainer.new()
	icon_container.name = "IconContainer"
	icon_container.custom_minimum_size = Vector2(54, 54)
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0.08, 0.08, 0.1)
	icon_style.border_color = BORDER_COLOR
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(4)
	icon_container.add_theme_stylebox_override("panel", icon_style)
	header_row.add_child(icon_container)

	var icon_center = CenterContainer.new()
	icon_container.add_child(icon_center)

	var icon_texture = TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.custom_minimum_size = Vector2(46, 46)
	icon_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_center.add_child(icon_texture)

	# Item info column
	var item_info = VBoxContainer.new()
	item_info.name = "ItemInfo"
	item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_info.add_theme_constant_override("separation", 2)
	header_row.add_child(item_info)

	var item_name = Label.new()
	item_name.name = "ItemName"
	item_name.text = "Unknown Item"
	item_name.add_theme_font_size_override("font_size", 14)
	item_name.add_theme_color_override("font_color", TEXT_COLOR)
	item_info.add_child(item_name)

	var item_rarity = Label.new()
	item_rarity.name = "ItemRarity"
	item_rarity.text = "Common"
	item_rarity.add_theme_font_size_override("font_size", 11)
	item_rarity.add_theme_color_override("font_color", ACCENT_COLOR)
	item_info.add_child(item_rarity)

	var item_source = Label.new()
	item_source.name = "ItemSource"
	item_source.text = "From: Unknown"
	item_source.add_theme_font_size_override("font_size", 11)
	item_source.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	item_info.add_child(item_source)

	var close_button = UITheme.create_close_button()
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # Anchor to top
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(hide_panel)
	header_row.add_child(close_button)

	# Item Stats section (damage, stat bonuses, effects)
	var item_stats_header = Label.new()
	item_stats_header.name = "ItemStatsHeader"
	item_stats_header.text = "ITEM STATS"
	item_stats_header.add_theme_color_override("font_color", HEADER_COLOR)
	item_stats_header.add_theme_font_size_override("font_size", 11)
	item_stats_header.visible = false
	vbox.add_child(item_stats_header)

	var item_stats_panel = PanelContainer.new()
	item_stats_panel.name = "ItemStatsPanel"
	var item_stats_style = StyleBoxFlat.new()
	item_stats_style.bg_color = INPUT_BG
	item_stats_style.set_corner_radius_all(4)
	item_stats_style.set_content_margin_all(8)
	item_stats_panel.add_theme_stylebox_override("panel", item_stats_style)
	item_stats_panel.visible = false
	vbox.add_child(item_stats_panel)

	var item_stats_content = VBoxContainer.new()
	item_stats_content.name = "ItemStatsContent"
	item_stats_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_stats_content.add_theme_constant_override("separation", 2)
	item_stats_panel.add_child(item_stats_content)

	# Combat Tracking section (for weapons - kills, damage dealt, etc.)
	var combat_header = Label.new()
	combat_header.name = "CombatHeader"
	combat_header.text = "COMBAT STATS"
	combat_header.add_theme_color_override("font_color", HEADER_COLOR)
	combat_header.add_theme_font_size_override("font_size", 11)
	combat_header.visible = false
	vbox.add_child(combat_header)

	var combat_panel = PanelContainer.new()
	combat_panel.name = "CombatPanel"
	var combat_style = StyleBoxFlat.new()
	combat_style.bg_color = INPUT_BG
	combat_style.set_corner_radius_all(4)
	combat_style.set_content_margin_all(8)
	combat_panel.add_theme_stylebox_override("panel", combat_style)
	combat_panel.visible = false
	vbox.add_child(combat_panel)

	var combat_content = VBoxContainer.new()
	combat_content.name = "CombatContent"
	combat_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	combat_content.add_theme_constant_override("separation", 2)
	combat_panel.add_child(combat_content)

	# Equipment Stats section (for armor/accessories - hits taken, survivals, etc.)
	var equipment_header = Label.new()
	equipment_header.name = "EquipmentHeader"
	equipment_header.text = "EQUIPMENT STATS"
	equipment_header.add_theme_color_override("font_color", HEADER_COLOR)
	equipment_header.add_theme_font_size_override("font_size", 11)
	equipment_header.visible = false
	vbox.add_child(equipment_header)

	var equipment_panel = PanelContainer.new()
	equipment_panel.name = "EquipmentPanel"
	var equip_style = StyleBoxFlat.new()
	equip_style.bg_color = INPUT_BG
	equip_style.set_corner_radius_all(4)
	equip_style.set_content_margin_all(8)
	equipment_panel.add_theme_stylebox_override("panel", equip_style)
	equipment_panel.visible = false
	vbox.add_child(equipment_panel)

	var equipment_content = VBoxContainer.new()
	equipment_content.name = "EquipmentContent"
	equipment_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_content.add_theme_constant_override("separation", 2)
	equipment_panel.add_child(equipment_content)

	# Provenance section
	var provenance_header = Label.new()
	provenance_header.name = "ProvenanceHeader"
	provenance_header.text = "PROVENANCE"
	provenance_header.add_theme_color_override("font_color", HEADER_COLOR)
	provenance_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(provenance_header)

	var provenance_panel = PanelContainer.new()
	provenance_panel.name = "ProvenancePanel"
	var prov_style = StyleBoxFlat.new()
	prov_style.bg_color = INPUT_BG
	prov_style.set_corner_radius_all(4)
	prov_style.set_content_margin_all(8)
	provenance_panel.add_theme_stylebox_override("panel", prov_style)
	vbox.add_child(provenance_panel)

	var prov_grid = GridContainer.new()
	prov_grid.name = "ProvenanceGrid"
	prov_grid.columns = 2
	prov_grid.add_theme_constant_override("h_separation", 12)
	prov_grid.add_theme_constant_override("v_separation", 3)
	provenance_panel.add_child(prov_grid)

	# Provenance fields - compact
	_add_prov_row(prov_grid, "ForgerLabel", "Forger:", "ForgerValue", "Unknown")
	_add_prov_row(prov_grid, "ForgedAtLabel", "Forged:", "ForgedAtValue", "Unknown")
	_add_prov_row(prov_grid, "TokenIdLabel", "Token:", "TokenIdValue", "Not minted")
	_add_prov_row(prov_grid, "TradeCountLabel", "Trades:", "TradeCountValue", "0")
	_add_prov_row(prov_grid, "OwnerLabel", "Owner:", "OwnerValue", "You")
	_add_prov_row(prov_grid, "OwnedSinceLabel", "Since:", "OwnedSinceValue", "Original")

	# Trade history section
	var history_header = Label.new()
	history_header.name = "HistoryHeader"
	history_header.text = "TRADE HISTORY"
	history_header.add_theme_color_override("font_color", HEADER_COLOR)
	history_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(history_header)

	var history_scroll = ScrollContainer.new()
	history_scroll.name = "HistoryScroll"
	history_scroll.custom_minimum_size = Vector2(0, 60)
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(history_scroll)

	var history_list = VBoxContainer.new()
	history_list.name = "HistoryList"
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_list.add_theme_constant_override("separation", 3)
	history_scroll.add_child(history_list)

	var no_history = Label.new()
	no_history.name = "NoHistoryLabel"
	no_history.text = "Never traded"
	no_history.add_theme_color_override("font_color", ACCENT_COLOR)
	no_history.add_theme_font_size_override("font_size", 11)
	history_list.add_child(no_history)

	# Chain verification section - compact
	var chain_section = HBoxContainer.new()
	chain_section.name = "ChainSection"
	chain_section.add_theme_constant_override("separation", 6)
	vbox.add_child(chain_section)

	var chain_status = Label.new()
	chain_status.name = "ChainStatus"
	chain_status.text = "✓ Verified on Polygon"
	chain_status.add_theme_font_size_override("font_size", 11)
	chain_status.add_theme_color_override("font_color", Color(0.4, 0.75, 0.4))
	chain_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_section.add_child(chain_status)

	var view_chain_btn = UITheme.create_button("View on Chain", "custom", true, Color(0.25, 0.4, 0.6))
	view_chain_btn.name = "ViewChainBtn"
	view_chain_btn.custom_minimum_size = Vector2(100, 0)
	view_chain_btn.pressed.connect(_on_view_chain_pressed)
	chain_section.add_child(view_chain_btn)

	add_child(main_panel)

func _add_prov_row(grid: GridContainer, label_name: String, label_text: String, value_name: String, value_text: String) -> void:
	"""Add a label-value row to the provenance grid"""
	var label = Label.new()
	label.name = label_name
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	grid.add_child(label)

	var value = Label.new()
	value.name = value_name
	value.text = value_text
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(value)

func show_panel() -> void:
	"""Show the inspection panel with smooth fade-in animation"""
	# Reset initial state for animation
	main_panel.modulate.a = 0.0
	main_panel.scale = Vector2(0.95, 0.95)
	main_panel.visible = true
	is_visible = true

	# Play panel open sound
	if SoundManager:
		SoundManager.play_button_click_sound()

	# Smooth fade-in + scale animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(main_panel, "modulate:a", 1.0, UITheme.ANIM_NORMAL)
	tween.tween_property(main_panel, "scale", Vector2(1.0, 1.0), UITheme.ANIM_NORMAL).set_trans(Tween.TRANS_BACK)

func hide_panel() -> void:
	"""Hide the inspection panel with smooth fade-out animation"""
	is_visible = false

	# Smooth fade-out animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(main_panel, "modulate:a", 0.0, UITheme.ANIM_FAST)

	# Hide panel after animation completes
	await tween.finished
	main_panel.visible = false
	current_item = {}
	inspection_closed.emit()

func inspect_item(item: Dictionary) -> void:
	"""Show inspection panel for a forged item (centered)"""
	_reset_to_center()
	current_item = item
	_populate_item_data(item)
	show_panel()

	# Fetch full provenance from backend
	_fetch_provenance(item)

func inspect_item_beside(item: Dictionary, beside_panel: Control) -> void:
	"""Show inspection panel positioned to the right of another panel (legacy method)"""
	# Calculate positions based on beside_panel
	var gap = 8
	var offset_l = beside_panel.offset_right + gap if beside_panel else -180
	var offset_r = offset_l + 360
	position_beside(item, offset_l, offset_r)

func position_beside(item: Dictionary, offset_l: int, offset_r: int) -> void:
	"""Show inspection panel at specified position (standardized method)"""
	current_item = item
	_populate_item_data(item)

	# Position using provided offsets
	if main_panel:
		main_panel.offset_left = offset_l
		main_panel.offset_right = offset_r

	show_panel()
	_fetch_provenance(item)

func _reset_to_center() -> void:
	"""Reset panel to centered position (internal)"""
	if main_panel:
		main_panel.offset_left = -180
		main_panel.offset_right = 180
		main_panel.offset_top = -300
		main_panel.offset_bottom = 300

func reset_to_center() -> void:
	"""Reset panel to centered position (public, with animation)"""
	if main_panel:
		var tween = create_tween()
		tween.tween_property(main_panel, "offset_left", -180, 0.15)
		tween.parallel().tween_property(main_panel, "offset_right", 180, 0.15)

func reposition(offset_l: int, offset_r: int) -> void:
	"""Reposition the panel with animation"""
	if main_panel:
		var tween = create_tween()
		tween.tween_property(main_panel, "offset_left", offset_l, 0.15)
		tween.parallel().tween_property(main_panel, "offset_right", offset_r, 0.15)

func _populate_item_data(item: Dictionary) -> void:
	"""Populate the UI with item data"""
	var vbox = main_panel.find_child("MainVBox", true, false)
	if not vbox:
		return

	# Item name and rarity
	var item_name = vbox.find_child("ItemName", true, false)
	var item_rarity = vbox.find_child("ItemRarity", true, false)
	var item_source = vbox.find_child("ItemSource", true, false)
	var icon_texture = vbox.find_child("IconTexture", true, false)
	var icon_container = vbox.find_child("IconContainer", true, false)

	var name_text = item.get("item_name", item.get("name", "Unknown Item"))
	var rarity = item.get("item_rarity", item.get("rarity", "Common")).to_upper()
	var rarity_color = UITheme.get_rarity_color_by_name(rarity)

	if item_name:
		item_name.text = name_text
		item_name.add_theme_color_override("font_color", rarity_color)

	if item_rarity:
		item_rarity.text = rarity.capitalize()
		item_rarity.add_theme_color_override("font_color", rarity_color.darkened(0.2))

	if item_source:
		# Check if forged (from external achievement) or in-game item
		var is_forged_item = _is_forged_item(item)
		if is_forged_item:
			var game = item.get("game", item.get("achievement", "Unknown"))
			var achievement = item.get("achievement_name", item.get("achievement", ""))
			if achievement != "":
				item_source.text = "From: %s - \"%s\"" % [game, achievement]
			else:
				item_source.text = "From: %s" % game
			item_source.add_theme_color_override("font_color", Color(0.6, 0.5, 0.8))  # Purple for forged
		else:
			# In-game item - show zone or vendor source
			var zone = item.get("zone", item.get("drop_zone", ""))
			var vendor = item.get("vendor", item.get("sold_by", ""))
			if vendor != "":
				item_source.text = "Sold by: %s" % vendor
			elif zone != "":
				item_source.text = "Found in: Zone %s" % zone
			else:
				item_source.text = "In-game item"
			item_source.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))  # Gray for in-game

	# Load icon - try multiple possible keys
	if icon_texture:
		var icon_path = item.get("icon", "")
		if icon_path == "":
			icon_path = item.get("icon_path", "")
		if icon_path == "":
			# Try to get from sprites dict
			var sprites = item.get("sprites", {})
			if sprites is Dictionary:
				icon_path = sprites.get("icon", "")

		# Debug: print what we're trying to load
		print("[ItemInspection] Icon path: ", icon_path, " - exists: ", ResourceLoader.exists(icon_path) if icon_path != "" else "empty")

		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon_texture.texture = load(icon_path)
		else:
			# Try to generate icon from ItemIconGenerator if available
			if is_instance_valid(ItemIconGenerator):
				var generated = ItemIconGenerator.get_item_icon(item)
				if generated:
					icon_texture.texture = generated
				else:
					icon_texture.texture = null
			else:
				icon_texture.texture = null

	# Update icon border color
	if icon_container:
		var style = icon_container.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat:
			style.border_color = rarity_color.darkened(0.3)
			icon_container.add_theme_stylebox_override("panel", style)

	# Check if this is a forged item (from external achievements)
	var is_forged = _is_forged_item(item)

	# DEBUG: Print item data to diagnose provenance detection
	print("[ItemInspection] Item: %s" % item.get("name", item.get("item_name", "Unknown")))
	print("  is_forged field: %s" % item.get("is_forged", "NOT SET"))
	print("  forged field: %s" % item.get("forged", "NOT SET"))
	print("  forged_id field: '%s'" % item.get("forged_id", ""))
	print("  forged_item_id field: '%s'" % item.get("forged_item_id", ""))
	print("  item_id field: '%s'" % item.get("item_id", ""))
	print("  token_id field: %s" % item.get("token_id", "NOT SET"))
	print("  DETECTED AS FORGED: %s" % is_forged)

	# Get provenance-related UI elements
	var provenance_header = vbox.find_child("ProvenanceHeader", true, false)
	var provenance_panel = vbox.find_child("ProvenancePanel", true, false)
	var history_header = vbox.find_child("HistoryHeader", true, false)
	var history_scroll = vbox.find_child("HistoryScroll", true, false)
	var chain_section = vbox.find_child("ChainSection", true, false)

	# Only show provenance sections for forged items
	if provenance_header:
		provenance_header.visible = is_forged
	if provenance_panel:
		provenance_panel.visible = is_forged
	if history_header:
		history_header.visible = is_forged
	if history_scroll:
		history_scroll.visible = is_forged
	if chain_section:
		chain_section.visible = is_forged

	# Populate basic provenance (only if forged)
	if not is_forged:
		# Skip provenance population for in-game items
		# Populate item stats (damage, bonuses, effects)
		_populate_item_stats(item, vbox)
		# Populate combat tracking stats if this is a weapon
		_populate_combat_stats(item, vbox)
		# Populate equipment stats if this is armor/accessory
		_populate_equipment_stats(item, vbox)
		return

	var prov_grid = vbox.find_child("ProvenanceGrid", true, false)
	if prov_grid:
		var forger_value = prov_grid.find_child("ForgerValue", true, false)
		var forged_at_value = prov_grid.find_child("ForgedAtValue", true, false)
		var token_id_value = prov_grid.find_child("TokenIdValue", true, false)
		var trade_count_value = prov_grid.find_child("TradeCountValue", true, false)
		var owner_value = prov_grid.find_child("OwnerValue", true, false)
		var owned_since_value = prov_grid.find_child("OwnedSinceValue", true, false)

		if forger_value:
			forger_value.text = item.get("forger_name", item.get("original_forger", "Unknown"))

		if forged_at_value:
			var forged_at = item.get("forged_at", "")
			if forged_at != "":
				forged_at_value.text = _format_date(forged_at)
			else:
				forged_at_value.text = "Unknown"

		if token_id_value:
			var token_id = item.get("token_id", 0)
			if token_id > 0:
				token_id_value.text = "#%d" % token_id
			else:
				token_id_value.text = "Not minted"

		if trade_count_value:
			trade_count_value.text = str(item.get("trade_count", 0))

		if owner_value:
			owner_value.text = item.get("current_owner_name", "You")

		if owned_since_value:
			var owned_since = item.get("owned_since", "")
			if owned_since != "":
				owned_since_value.text = _format_date(owned_since)
			else:
				owned_since_value.text = "Original owner"

	# Populate item stats (damage, bonuses, effects)
	_populate_item_stats(item, vbox)

	# Populate combat tracking stats if this is a weapon
	_populate_combat_stats(item, vbox)

	# Populate equipment stats if this is armor/accessory
	_populate_equipment_stats(item, vbox)

func _populate_item_stats(item: Dictionary, vbox: Control) -> void:
	"""Populate item stats section (damage, stat bonuses, effects)"""
	var item_stats_header = vbox.find_child("ItemStatsHeader", true, false)
	var item_stats_panel = vbox.find_child("ItemStatsPanel", true, false)
	var item_stats_content = vbox.find_child("ItemStatsContent", true, false)

	if not item_stats_header or not item_stats_panel or not item_stats_content:
		return

	# Check if this is a weapon or armor
	var item_type = item.get("type", item.get("item_type", ""))
	var is_weapon = item_type == "weapon" or item_type == "ItemType.WEAPON" or item.has("base_damage") or item.has("weapon_type")
	var is_armor = item_type == "armor" or item.has("defense")
	var is_accessory = item_type == "accessory" or item_type == "ring" or item_type == "amulet"

	if not is_weapon and not is_armor and not is_accessory:
		item_stats_header.visible = false
		item_stats_panel.visible = false
		return

	# Show the section
	item_stats_header.visible = true
	item_stats_panel.visible = true

	# Clear existing content
	for child in item_stats_content.get_children():
		child.queue_free()

	# Build stats display
	var stats_lines: Array[String] = []

	# Weapon damage
	if is_weapon:
		var base_damage = item.get("base_damage", 0)
		if base_damage is Dictionary:
			# Range format: {"min": X, "max": Y}
			stats_lines.append("Damage: +%.1f - %.1f" % [base_damage.get("min", 0), base_damage.get("max", 0)])
		elif base_damage > 0:
			stats_lines.append("Damage: +%.1f" % base_damage)

		# Attack speed
		var attack_speed = item.get("attack_speed", "")
		if attack_speed != "":
			stats_lines.append("Speed: %s" % str(attack_speed).capitalize())

		# Weapon type
		var weapon_type = item.get("weapon_type", "")
		if weapon_type != "":
			stats_lines.append("Type: %s" % weapon_type.capitalize())

	# Armor defense
	if is_armor and item.has("defense"):
		stats_lines.append("Defense: +%d" % item.get("defense", 0))

	# Stat bonuses (STR, AGI, DEX, INT, WIS, VIT)
	var stat_bonuses = item.get("stat_bonuses", {})
	if stat_bonuses is Dictionary and not stat_bonuses.is_empty():
		var bonus_parts: Array[String] = []
		if stat_bonuses.get("str", 0) > 0:
			bonus_parts.append("+%d STR" % stat_bonuses.get("str"))
		if stat_bonuses.get("agi", 0) > 0:
			bonus_parts.append("+%d AGI" % stat_bonuses.get("agi"))
		if stat_bonuses.get("dex", 0) > 0:
			bonus_parts.append("+%d DEX" % stat_bonuses.get("dex"))
		if stat_bonuses.get("int", 0) > 0:
			bonus_parts.append("+%d INT" % stat_bonuses.get("int"))
		if stat_bonuses.get("wis", 0) > 0:
			bonus_parts.append("+%d WIS" % stat_bonuses.get("wis"))
		if stat_bonuses.get("vit", 0) > 0:
			bonus_parts.append("+%d VIT" % stat_bonuses.get("vit"))
		if not bonus_parts.is_empty():
			stats_lines.append(", ".join(bonus_parts))

	# HP bonus
	var hp_bonus = item.get("hp_bonus", 0)
	if hp_bonus > 0:
		stats_lines.append("+%d HP" % hp_bonus)

	# Lifesteal
	var lifesteal = item.get("lifesteal", 0.0)
	if lifesteal > 0:
		stats_lines.append("Lifesteal: %.1f%%" % (lifesteal * 100))

	# Abilities - use ForgeItemDB lookup for proper names
	var item_id = item.get("item_id", "")
	var has_ability_display = false

	if item_id != "" and ForgeItemDB and ForgeItemDB.has_abilities(item_id):
		# Get ability info from ForgeItemDB
		var passive_name = ForgeItemDB.get_passive_ability_name(item_id)
		var passive_desc = ForgeItemDB.get_passive_ability_description(item_id)
		var active_name = ForgeItemDB.get_active_ability_name(item_id)
		var active_desc = ForgeItemDB.get_active_ability_description(item_id)

		if passive_name != "":
			stats_lines.append("Passive: %s" % passive_name)
			if passive_desc != "":
				stats_lines.append("  %s" % passive_desc)
			has_ability_display = true

		if active_name != "":
			stats_lines.append("Active: %s" % active_name)
			if active_desc != "":
				stats_lines.append("  %s" % active_desc)
			has_ability_display = true

	# Fallback to raw effects if no ForgeItemDB entry
	if not has_ability_display:
		var effects = item.get("effects", {})
		if effects is Dictionary:
			var passive = effects.get("passive", [])
			var active = effects.get("active")
			if passive is Array and not passive.is_empty():
				for effect in passive:
					stats_lines.append("Effect: %s" % _format_effect_name(effect))
			if active != null and active != "":
				stats_lines.append("Active: %s" % _format_effect_name(active))
		elif effects is Array and not effects.is_empty():
			# Handle array format (legacy)
			for effect in effects:
				stats_lines.append("Effect: %s" % _format_effect_name(effect))

		# Also check for simple effect field
		var effect = item.get("effect", item.get("effect_name", ""))
		if effect != "" and effect != null:
			# Don't duplicate if already in effects
			var already_shown = false
			for line in stats_lines:
				if "Effect:" in line and effect in line:
					already_shown = true
					break
			if not already_shown:
				stats_lines.append("Effect: %s" % _format_effect_name(effect))

	# Value
	var value = item.get("value", item.get("sell_value", 0))
	if value > 0:
		stats_lines.append("Value: %d G" % value)

	# Add labels for each stat line
	for line in stats_lines:
		var label = Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 11)
		# Color code based on content
		if line.begins_with("Damage:") or line.begins_with("Defense:") or line.begins_with("Value:"):
			label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))  # Gold
		elif line.begins_with("+") or "STR" in line or "AGI" in line or "DEX" in line or "INT" in line or "WIS" in line or "VIT" in line or "HP" in line:
			label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))  # Green
		elif line.begins_with("Passive:"):
			label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))  # Purple for passive abilities
		elif line.begins_with("Active:"):
			label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))  # Orange for active abilities
		elif line.begins_with("  "):
			# Indented description text - slightly dimmer
			label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
			label.add_theme_font_size_override("font_size", 10)  # Slightly smaller
		elif line.begins_with("Effect:"):
			label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))  # Blue for legacy effects
		elif line.begins_with("Lifesteal:"):
			label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))  # Red
		else:
			label.add_theme_color_override("font_color", TEXT_COLOR)
		item_stats_content.add_child(label)

func _format_effect_name(effect: String) -> String:
	"""Format effect ID to readable name"""
	# Replace underscores with spaces and capitalize
	return effect.replace("_", " ").capitalize()

func _populate_combat_stats(item: Dictionary, vbox: Control) -> void:
	"""Populate combat stats section for FORGED weapons only - base weapons don't track stats"""
	var combat_header = vbox.find_child("CombatHeader", true, false)
	var combat_panel = vbox.find_child("CombatPanel", true, false)
	var combat_content = vbox.find_child("CombatContent", true, false)

	if not combat_header or not combat_panel or not combat_content:
		return

	# Check if this is a weapon
	var item_type = item.get("type", item.get("item_type", ""))
	var is_weapon = item_type == "weapon" or item_type == "ItemType.WEAPON"

	# Also check equipped weapon
	var weapon: Weapon = null
	if CharacterStats and CharacterStats.equipped_weapon:
		var equipped_name = CharacterStats.equipped_weapon.weapon_name
		var item_name = item.get("name", item.get("item_name", ""))
		if equipped_name == item_name:
			weapon = CharacterStats.equipped_weapon
			is_weapon = true

	if not is_weapon:
		combat_header.visible = false
		combat_panel.visible = false
		return

	# ONLY show combat stats for FORGED items (T4+)
	# Base/vendor weapons (T1-T3) don't have stat tracking
	var is_forged = item.get("is_forged", false) or item.get("forged", false)
	if weapon:
		is_forged = weapon.is_forged

	if not is_forged:
		combat_header.visible = false
		combat_panel.visible = false
		return

	# Show the section for forged items only
	combat_header.visible = true
	combat_panel.visible = true

	# Clear existing content
	for child in combat_content.get_children():
		child.queue_free()

	# Get stats from weapon resource or use defaults
	var stats: WeaponStats = weapon.weapon_stats if weapon and weapon.weapon_stats else null

	# Get values (from stats or default to 0)
	var level = stats.level if stats else 0
	var tier_name = stats.get_visual_tier_name() if stats else "PRISTINE"
	var kills_total = stats.kills_total if stats else 0
	var kills_elite = stats.kills_elite if stats else 0
	var kills_boss = stats.kills_boss if stats else 0
	var damage_total = stats.damage_total if stats else 0
	var damage_max = stats.damage_max_hit if stats else 0
	var crits = stats.crits_landed if stats else 0
	var crit_rate = stats.get_crit_rate_lifetime() if stats else 0.0
	var swings = stats.swings_total if stats else 0
	var shots = stats.shots_fired if stats else 0
	var time_equipped = stats.time_equipped_seconds if stats else 0
	var deaths = stats.deaths_equipped if stats else 0
	var misses = stats.misses_total if stats else 0
	var experience = stats.experience if stats else 0
	var xp_needed = stats.get_experience_to_next_level() if stats else 100

	# Use a compact 2-column grid for stats
	var grid = GridContainer.new()
	grid.columns = 4  # label, value, label, value
	grid.add_theme_constant_override("h_separation", 24)  # More space between columns
	grid.add_theme_constant_override("v_separation", 2)
	combat_content.add_child(grid)

	# Level & Tier row
	_add_stat_cell(grid, "Level:", str(level))
	_add_stat_cell_with_tooltip(grid, "Tier:", tier_name, _get_tier_tooltip())

	# Kills & Damage row
	_add_stat_cell(grid, "Kills:", _format_number(kills_total))
	_add_stat_cell(grid, "Damage:", _format_number(damage_total))

	# Max Hit & Shots/Swings row
	_add_stat_cell(grid, "Max Hit:", _format_number(damage_max))
	# Check if this is a gun weapon type
	var weapon_type = weapon.weapon_type if weapon else item.get("weapon_type", "")
	var gun_weapon_types = ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"]
	var is_gun = weapon_type in gun_weapon_types
	if is_gun:
		_add_stat_cell(grid, "Shots:", _format_number(shots))
	else:
		_add_stat_cell(grid, "Swings:", _format_number(swings))

	# Time & Deaths row
	_add_stat_cell(grid, "Time:", _format_time(time_equipped))
	_add_stat_cell(grid, "Deaths:", str(deaths))

	# XP Progress Bar (full width below the grid)
	var xp_container = VBoxContainer.new()
	xp_container.add_theme_constant_override("separation", 2)
	combat_content.add_child(xp_container)

	# XP label row
	var xp_label_row = HBoxContainer.new()
	xp_container.add_child(xp_label_row)

	var xp_label = Label.new()
	xp_label.text = "Weapon XP"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", ACCENT_COLOR)
	xp_label_row.add_child(xp_label)

	var xp_spacer = Control.new()
	xp_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_label_row.add_child(xp_spacer)

	var xp_text = Label.new()
	xp_text.text = "%s / %s" % [_format_number(experience), _format_number(xp_needed)]
	xp_text.add_theme_font_size_override("font_size", 10)
	xp_text.add_theme_color_override("font_color", TEXT_COLOR)
	xp_label_row.add_child(xp_text)

	# XP progress bar
	var xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 8)
	xp_bar.max_value = 100
	xp_bar.value = (float(experience) / float(max(xp_needed, 1))) * 100.0
	xp_bar.show_percentage = false

	# Style the progress bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.15, 0.15, 0.2)
	bar_style.corner_radius_top_left = 2
	bar_style.corner_radius_top_right = 2
	bar_style.corner_radius_bottom_left = 2
	bar_style.corner_radius_bottom_right = 2
	xp_bar.add_theme_stylebox_override("background", bar_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.4, 0.7, 1.0)  # Blue XP color
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	xp_bar.add_theme_stylebox_override("fill", fill_style)

	xp_container.add_child(xp_bar)

	# Virgin status message
	if stats and stats.is_virgin():
		var virgin_label = Label.new()
		virgin_label.text = "✧ PRISTINE ✧"
		virgin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		virgin_label.add_theme_font_size_override("font_size", 10)
		virgin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		combat_content.add_child(virgin_label)

	# Show achievements if any
	if stats and stats.achievements.size() > 0:
		var ach_row = HBoxContainer.new()
		ach_row.add_theme_constant_override("separation", 4)
		for ach_id in stats.achievements:
			var icon_label = Label.new()
			icon_label.text = stats.get_achievement_icon(ach_id)
			icon_label.add_theme_font_size_override("font_size", 12)
			ach_row.add_child(icon_label)
		combat_content.add_child(ach_row)

func _populate_equipment_stats(item: Dictionary, vbox: Control) -> void:
	"""Populate equipment stats section for armor/accessories"""
	var equipment_header = vbox.find_child("EquipmentHeader", true, false)
	var equipment_panel = vbox.find_child("EquipmentPanel", true, false)
	var equipment_content = vbox.find_child("EquipmentContent", true, false)

	if not equipment_header or not equipment_panel or not equipment_content:
		return

	# Check if this is armor or accessory (not weapon)
	var item_type = item.get("type", item.get("item_type", ""))
	var is_weapon = item_type == "weapon" or item_type == "ItemType.WEAPON"
	var is_armor = item_type == "armor" or item.has("defense") or item.has("armor_slot")
	var is_accessory = item_type == "accessory" or item_type == "ring" or item_type == "amulet" or item.has("accessory_slot")

	# Only show for forged armor/accessories
	var is_forged = _is_forged_item(item)

	if is_weapon or (not is_armor and not is_accessory) or not is_forged:
		equipment_header.visible = false
		equipment_panel.visible = false
		return

	# Show the section
	equipment_header.visible = true
	equipment_panel.visible = true

	# Clear existing content
	for child in equipment_content.get_children():
		child.queue_free()

	# Get stats from item data or create default
	var stats_data = item.get("equipment_stats", {})
	var stats: EquipmentStats = null
	if stats_data and stats_data.size() > 0:
		stats = EquipmentStats.from_dict(stats_data)
	else:
		stats = EquipmentStats.new()

	# Get values
	var level = stats.level if stats else 0
	var tier_name = stats.get_visual_tier_name() if stats else "PRISTINE"
	var hits_received = stats.hits_received if stats else 0
	var hits_survived = stats.hits_survived if stats else 0
	var damage_taken = stats.damage_taken_total if stats else 0
	var damage_absorbed = stats.damage_absorbed if stats else 0
	var max_hit_survived = stats.damage_max_hit_survived if stats else 0
	var deaths = stats.deaths_wearing if stats else 0
	var close_calls = stats.close_calls if stats else 0
	var boss_fights = stats.boss_fights_survived if stats else 0
	var time_equipped = stats.time_equipped_seconds if stats else 0
	var experience = stats.experience if stats else 0
	var xp_needed = stats.get_experience_to_next_level() if stats else 100

	# Use a compact 2-column grid for stats
	var grid = GridContainer.new()
	grid.columns = 4  # label, value, label, value
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	equipment_content.add_child(grid)

	# Level & Tier row
	_add_stat_cell(grid, "Level:", str(level))
	_add_stat_cell_with_tooltip(grid, "Tier:", tier_name, _get_equipment_tier_tooltip())

	# Hits & Damage row
	_add_stat_cell(grid, "Hits:", _format_number(hits_received))
	_add_stat_cell(grid, "Survived:", _format_number(hits_survived))

	# Damage stats row
	_add_stat_cell(grid, "Dmg Taken:", _format_number(damage_taken))
	_add_stat_cell(grid, "Absorbed:", _format_number(damage_absorbed))

	# Max Hit & Deaths row
	_add_stat_cell(grid, "Max Hit:", _format_number(max_hit_survived))
	_add_stat_cell(grid, "Deaths:", str(deaths))

	# Close Calls & Boss Fights row
	_add_stat_cell(grid, "Close Calls:", str(close_calls))
	_add_stat_cell(grid, "Boss Wins:", str(boss_fights))

	# Time row
	_add_stat_cell(grid, "Time:", _format_time(time_equipped))
	_add_stat_cell(grid, "", "")  # Empty cell for alignment

	# XP Progress Bar (full width below the grid)
	var xp_container = VBoxContainer.new()
	xp_container.add_theme_constant_override("separation", 2)
	equipment_content.add_child(xp_container)

	# XP label row
	var xp_label_row = HBoxContainer.new()
	xp_container.add_child(xp_label_row)

	var xp_label = Label.new()
	xp_label.text = "Equipment XP"
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", ACCENT_COLOR)
	xp_label_row.add_child(xp_label)

	var xp_spacer = Control.new()
	xp_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_label_row.add_child(xp_spacer)

	var xp_text = Label.new()
	xp_text.text = "%s / %s" % [_format_number(experience), _format_number(xp_needed)]
	xp_text.add_theme_font_size_override("font_size", 10)
	xp_text.add_theme_color_override("font_color", TEXT_COLOR)
	xp_label_row.add_child(xp_text)

	# XP progress bar
	var xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 8)
	xp_bar.max_value = 100
	xp_bar.value = (float(experience) / float(max(xp_needed, 1))) * 100.0
	xp_bar.show_percentage = false

	# Style the progress bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.15, 0.15, 0.2)
	bar_style.corner_radius_top_left = 2
	bar_style.corner_radius_top_right = 2
	bar_style.corner_radius_bottom_left = 2
	bar_style.corner_radius_bottom_right = 2
	xp_bar.add_theme_stylebox_override("background", bar_style)

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.8, 0.5)  # Green for equipment
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	xp_bar.add_theme_stylebox_override("fill", fill_style)

	xp_container.add_child(xp_bar)

	# Virgin status message
	if stats and stats.is_virgin():
		var virgin_label = Label.new()
		virgin_label.text = "✧ PRISTINE ✧"
		virgin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		virgin_label.add_theme_font_size_override("font_size", 10)
		virgin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		equipment_content.add_child(virgin_label)

	# Show achievements if any
	if stats and stats.achievements.size() > 0:
		var ach_row = HBoxContainer.new()
		ach_row.add_theme_constant_override("separation", 4)
		for ach_id in stats.achievements:
			var icon_label = Label.new()
			icon_label.text = stats.get_achievement_icon(ach_id)
			icon_label.add_theme_font_size_override("font_size", 12)
			ach_row.add_child(icon_label)
		equipment_content.add_child(ach_row)

func _get_equipment_tier_tooltip() -> String:
	"""Get tooltip text explaining the equipment tier system"""
	return "PRISTINE: 0 hits\nTESTED: 1-99\nPROVEN: 100-999\nBATTLE-WORN: 1K-9,999\nLEGENDARY: 10K-49,999\nMYTHIC: 50K+"

func _add_stat_cell(grid: GridContainer, label_text: String, value_text: String) -> void:
	"""Add a label-value pair to the stat grid"""
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	grid.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(value)

func _add_stat_cell_with_tooltip(grid: GridContainer, label_text: String, value_text: String, tooltip: String) -> void:
	"""Add a label-value pair with a tooltip on the value"""
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	grid.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # Gold for hoverable
	value.tooltip_text = tooltip
	value.mouse_filter = Control.MOUSE_FILTER_STOP  # Enable mouse events for tooltip
	grid.add_child(value)

func _get_tier_tooltip() -> String:
	"""Get tooltip text explaining the tier system"""
	return "PRISTINE: 0 kills\nBLOODED: 1-99\nVETERAN: 100-999\nBATTLE-WORN: 1K-9,999\nLEGENDARY: 10K-49,999\nMYTHIC: 50K+"

func _create_section_header(text: String) -> Label:
	"""Create a section header label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", HEADER_COLOR)
	return label

func _create_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	"""Create a stat row with label and value"""
	var row = HBoxContainer.new()

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	if value_text != "":
		var value = Label.new()
		value.text = value_text
		value.add_theme_font_size_override("font_size", 11)
		value.add_theme_color_override("font_color", TEXT_COLOR)
		row.add_child(value)

	return row

func _format_number(num: int) -> String:
	"""Format large numbers with commas"""
	var s = str(num)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _format_time(seconds: int) -> String:
	"""Format seconds as human-readable duration"""
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60

	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	else:
		return "%dm" % minutes

func _get_achievement_name(ach_id: String) -> String:
	"""Get display name for achievement"""
	match ach_id:
		"FIRST_BLOOD": return "First Blood"
		"CENTURION": return "Centurion"
		"SLAYER": return "Slayer"
		"LEGEND": return "Legend"
		"PERFECTIONIST": return "Perfectionist"
		"CRIT_MASTER": return "Crit Master"
		"CHAIN_KING": return "Chain King"
		"UNTOUCHED": return "Untouched"
		"OVERKILL": return "Overkill"
		"VETERAN": return "Veteran"
		_: return ach_id

func _fetch_provenance(item: Dictionary) -> void:
	"""Fetch full provenance from backend API"""
	var token_id = item.get("token_id", 0)
	if token_id <= 0:
		return

	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return

	var url = AshbaneAuth.get_api_base() + "/api/forge/provenance/%d" % token_id
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_provenance_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()

func _on_provenance_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.data
	_update_provenance_display(data)

func _update_provenance_display(data: Dictionary) -> void:
	"""Update display with full provenance data from API"""
	var vbox = main_panel.find_child("MainVBox", true, false)
	if not vbox:
		return

	var prov_grid = vbox.find_child("ProvenanceGrid", true, false)
	if prov_grid:
		var forger_value = prov_grid.find_child("ForgerValue", true, false)
		var trade_count_value = prov_grid.find_child("TradeCountValue", true, false)
		var owner_value = prov_grid.find_child("OwnerValue", true, false)

		if forger_value and data.has("forger"):
			forger_value.text = data["forger"].get("username", "Unknown")

		if trade_count_value:
			trade_count_value.text = str(data.get("trade_count", 0))

		if owner_value and data.has("current_owner"):
			owner_value.text = data["current_owner"].get("username", "Unknown")

	# Update trade history
	var history_list = vbox.find_child("HistoryList", true, false)
	var no_history_label = vbox.find_child("NoHistoryLabel", true, false)

	if history_list:
		# Clear existing history (except the "no history" label)
		for child in history_list.get_children():
			if child != no_history_label:
				child.queue_free()

		var trades = data.get("trades", [])
		if trades.is_empty():
			if no_history_label:
				no_history_label.visible = true
		else:
			if no_history_label:
				no_history_label.visible = false

			for trade in trades:
				var row = _create_trade_history_row(trade)
				history_list.add_child(row)

	# Update chain status
	var chain_icon = vbox.find_child("ChainIcon", true, false)
	var chain_status = vbox.find_child("ChainStatus", true, false)
	var view_chain_btn = vbox.find_child("ViewChainBtn", true, false)

	var is_on_chain = data.get("is_on_chain", false)
	if chain_icon:
		chain_icon.text = "" if is_on_chain else ""
	if chain_status:
		if is_on_chain:
			chain_status.text = "Verified on Polygon"
			chain_status.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
		else:
			chain_status.text = "Pending chain sync"
			chain_status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	if view_chain_btn:
		view_chain_btn.visible = is_on_chain

func _create_trade_history_row(trade: Dictionary) -> Control:
	"""Create a row for trade history display"""
	var row = PanelContainer.new()
	var row_style = StyleBoxFlat.new()
	row_style.bg_color = Color(0.12, 0.12, 0.15)
	row_style.set_corner_radius_all(4)
	row_style.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", row_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# Date
	var date_label = Label.new()
	var traded_at = trade.get("traded_at", "")
	date_label.text = _format_date(traded_at) if traded_at else "Unknown"
	date_label.add_theme_font_size_override("font_size", 11)
	date_label.add_theme_color_override("font_color", ACCENT_COLOR)
	date_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(date_label)

	# From -> To
	var from_user = trade.get("from_user", {}).get("username", "Unknown")
	var to_user = trade.get("to_user", {}).get("username", "Unknown")
	var transfer_label = Label.new()
	transfer_label.text = "%s -> %s" % [from_user, to_user]
	transfer_label.add_theme_font_size_override("font_size", 11)
	transfer_label.add_theme_color_override("font_color", TEXT_COLOR)
	transfer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(transfer_label)

	# Price
	var price = trade.get("price_gold", 0)
	var price_label = Label.new()
	if price > 0:
		price_label.text = "%dg" % price
		price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	else:
		price_label.text = "Gift"
		price_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	price_label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(price_label)

	return row

func _format_date(iso_date: String) -> String:
	"""Format ISO date string to readable format"""
	if iso_date == "":
		return "Unknown"

	# Parse ISO format (2024-01-15T12:30:00)
	var parts = iso_date.split("T")
	if parts.size() >= 1:
		var date_parts = parts[0].split("-")
		if date_parts.size() == 3:
			var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
			var month_idx = int(date_parts[1]) - 1
			if month_idx >= 0 and month_idx < 12:
				return "%s %s, %s" % [months[month_idx], date_parts[2], date_parts[0]]

	return iso_date.substr(0, 10)

func _on_view_chain_pressed() -> void:
	"""Open PolygonScan to view the token"""
	var token_id = current_item.get("token_id", 0)
	if token_id <= 0:
		return

	# Get contract address from environment or use default
	var contract_address = "0x0000000000000000000000000000000000000000"  # Placeholder
	var url = "https://polygonscan.com/token/%s?a=%d" % [contract_address, token_id]
	OS.shell_open(url)
