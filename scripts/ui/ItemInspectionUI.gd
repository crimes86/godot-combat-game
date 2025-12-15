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

func _ready() -> void:
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

	# Center on screen - compact size
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(360, 520)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -180
	main_panel.offset_right = 180
	main_panel.offset_top = -260
	main_panel.offset_bottom = 260

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

	# Combat Stats section (for weapons - always visible for weapons)
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
		main_panel.offset_top = -260
		main_panel.offset_bottom = 260

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
		var game = item.get("game", item.get("achievement", "Unknown"))
		var achievement = item.get("achievement_name", item.get("achievement", ""))
		if achievement != "":
			item_source.text = "From: %s - \"%s\"" % [game, achievement]
		else:
			item_source.text = "From: %s" % game

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

	# Populate basic provenance
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

	# Populate combat stats if this is a weapon
	_populate_combat_stats(item, vbox)

func _populate_combat_stats(item: Dictionary, vbox: Control) -> void:
	"""Populate combat stats section for weapons - always show all stats with values"""
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

	# Show the section
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

	# XP row
	_add_stat_cell(grid, "XP:", "%s/%s" % [_format_number(experience), _format_number(xp_needed)])
	_add_stat_cell(grid, "", "")  # Empty cell for alignment

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

	if not MantleAuth or not MantleAuth.is_logged_in():
		return

	var url = MantleAuth.get_api_base() + "/api/forge/provenance/%d" % token_id
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

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
