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

# Rarity colors
const RARITY_COLORS = {
	"COMMON": Color(0.7, 0.7, 0.7),
	"UNCOMMON": Color(0.3, 0.8, 0.3),
	"RARE": Color(0.3, 0.5, 1.0),
	"EPIC": Color(0.6, 0.3, 0.9),
	"LEGENDARY": Color(1.0, 0.6, 0.1),
	"ARTIFACT": Color(0.9, 0.2, 0.2)
}

# UI elements
var main_panel: PanelContainer
var is_visible: bool = false
var current_item: Dictionary = {}

func _ready() -> void:
	layer = 120  # Above most UI
	_create_ui()
	hide_panel()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_visible:
			hide_panel()
			get_viewport().set_input_as_handled()

func _create_ui() -> void:
	"""Create the inspection panel UI"""

	# Main panel - centered modal
	main_panel = PanelContainer.new()
	main_panel.name = "InspectionPanel"

	# Center on screen
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(500, 550)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -250
	main_panel.offset_right = 250
	main_panel.offset_top = -275
	main_panel.offset_bottom = 275

	# Apply styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_size = 15
	panel_style.shadow_color = Color(0, 0, 0, 0.8)
	panel_style.shadow_offset = Vector2(0, 5)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	main_panel.add_child(margin)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header row (title + close button)
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vbox.add_child(header_row)

	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "ITEM INSPECTION"
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_label)

	var close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	_style_button(close_button, Color(0.7, 0.3, 0.3))
	close_button.pressed.connect(hide_panel)
	header_row.add_child(close_button)

	# Item header section (icon + name + rarity)
	var item_header = HBoxContainer.new()
	item_header.name = "ItemHeader"
	item_header.add_theme_constant_override("separation", 12)
	vbox.add_child(item_header)

	# Icon container
	var icon_container = PanelContainer.new()
	icon_container.name = "IconContainer"
	icon_container.custom_minimum_size = Vector2(80, 80)
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = Color(0.08, 0.08, 0.1)
	icon_style.border_color = BORDER_COLOR
	icon_style.set_border_width_all(2)
	icon_style.set_corner_radius_all(6)
	icon_container.add_theme_stylebox_override("panel", icon_style)
	item_header.add_child(icon_container)

	var icon_center = CenterContainer.new()
	icon_container.add_child(icon_center)

	var icon_texture = TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.custom_minimum_size = Vector2(64, 64)
	icon_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_center.add_child(icon_texture)

	# Item info column
	var item_info = VBoxContainer.new()
	item_info.name = "ItemInfo"
	item_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_info.add_theme_constant_override("separation", 4)
	item_header.add_child(item_info)

	var item_name = Label.new()
	item_name.name = "ItemName"
	item_name.text = "Unknown Item"
	item_name.add_theme_font_size_override("font_size", 20)
	item_name.add_theme_color_override("font_color", TEXT_COLOR)
	item_info.add_child(item_name)

	var item_rarity = Label.new()
	item_rarity.name = "ItemRarity"
	item_rarity.text = "Common"
	item_rarity.add_theme_font_size_override("font_size", 14)
	item_rarity.add_theme_color_override("font_color", ACCENT_COLOR)
	item_info.add_child(item_rarity)

	var item_source = Label.new()
	item_source.name = "ItemSource"
	item_source.text = "From: Unknown Achievement"
	item_source.add_theme_font_size_override("font_size", 12)
	item_source.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	item_info.add_child(item_source)

	# Provenance section
	var provenance_header = Label.new()
	provenance_header.text = "PROVENANCE"
	provenance_header.add_theme_color_override("font_color", HEADER_COLOR)
	provenance_header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(provenance_header)

	var provenance_panel = PanelContainer.new()
	provenance_panel.name = "ProvenancePanel"
	var prov_style = StyleBoxFlat.new()
	prov_style.bg_color = INPUT_BG
	prov_style.set_corner_radius_all(6)
	prov_style.set_content_margin_all(10)
	provenance_panel.add_theme_stylebox_override("panel", prov_style)
	vbox.add_child(provenance_panel)

	var prov_grid = GridContainer.new()
	prov_grid.name = "ProvenanceGrid"
	prov_grid.columns = 2
	prov_grid.add_theme_constant_override("h_separation", 20)
	prov_grid.add_theme_constant_override("v_separation", 8)
	provenance_panel.add_child(prov_grid)

	# Provenance fields
	_add_prov_row(prov_grid, "ForgerLabel", "Original Forger:", "ForgerValue", "Unknown")
	_add_prov_row(prov_grid, "ForgedAtLabel", "Forged:", "ForgedAtValue", "Unknown date")
	_add_prov_row(prov_grid, "TokenIdLabel", "Token ID:", "TokenIdValue", "#0")
	_add_prov_row(prov_grid, "TradeCountLabel", "Times Traded:", "TradeCountValue", "0")
	_add_prov_row(prov_grid, "OwnerLabel", "Current Owner:", "OwnerValue", "Unknown")
	_add_prov_row(prov_grid, "OwnedSinceLabel", "Owned Since:", "OwnedSinceValue", "Unknown")

	# Trade history section
	var history_header = Label.new()
	history_header.text = "TRADE HISTORY"
	history_header.add_theme_color_override("font_color", HEADER_COLOR)
	history_header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(history_header)

	var history_scroll = ScrollContainer.new()
	history_scroll.name = "HistoryScroll"
	history_scroll.custom_minimum_size = Vector2(0, 120)
	history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(history_scroll)

	var history_list = VBoxContainer.new()
	history_list.name = "HistoryList"
	history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_list.add_theme_constant_override("separation", 4)
	history_scroll.add_child(history_list)

	var no_history = Label.new()
	no_history.name = "NoHistoryLabel"
	no_history.text = "This item has never been traded."
	no_history.add_theme_color_override("font_color", ACCENT_COLOR)
	no_history.add_theme_font_size_override("font_size", 12)
	history_list.add_child(no_history)

	# Chain verification section
	var chain_section = HBoxContainer.new()
	chain_section.name = "ChainSection"
	chain_section.add_theme_constant_override("separation", 8)
	vbox.add_child(chain_section)

	var chain_icon = Label.new()
	chain_icon.name = "ChainIcon"
	chain_icon.text = ""
	chain_icon.add_theme_font_size_override("font_size", 16)
	chain_section.add_child(chain_icon)

	var chain_status = Label.new()
	chain_status.name = "ChainStatus"
	chain_status.text = "Verified on Polygon"
	chain_status.add_theme_font_size_override("font_size", 12)
	chain_status.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	chain_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_section.add_child(chain_status)

	var view_chain_btn = Button.new()
	view_chain_btn.name = "ViewChainBtn"
	view_chain_btn.text = "View on PolygonScan"
	view_chain_btn.custom_minimum_size = Vector2(140, 0)
	_style_button(view_chain_btn, Color(0.3, 0.5, 0.7))
	view_chain_btn.pressed.connect(_on_view_chain_pressed)
	chain_section.add_child(view_chain_btn)

	add_child(main_panel)

func _add_prov_row(grid: GridContainer, label_name: String, label_text: String, value_name: String, value_text: String) -> void:
	"""Add a label-value row to the provenance grid"""
	var label = Label.new()
	label.name = label_name
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	grid.add_child(label)

	var value = Label.new()
	value.name = value_name
	value.text = value_text
	value.add_theme_font_size_override("font_size", 12)
	value.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(value)

func _style_button(button: Button, color: Color) -> void:
	"""Apply consistent button styling"""
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	var hover = style.duplicate()
	hover.bg_color = color.lightened(0.2)

	var pressed = style.duplicate()
	pressed.bg_color = color.darkened(0.2)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_font_size_override("font_size", 12)

func show_panel() -> void:
	"""Show the inspection panel"""
	main_panel.visible = true
	is_visible = true

func hide_panel() -> void:
	"""Hide the inspection panel"""
	main_panel.visible = false
	is_visible = false
	current_item = {}
	inspection_closed.emit()

func inspect_item(item: Dictionary) -> void:
	"""Show inspection panel for a forged item"""
	current_item = item
	_populate_item_data(item)
	show_panel()

	# Fetch full provenance from backend
	_fetch_provenance(item)

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
	var rarity_color = RARITY_COLORS.get(rarity, Color.WHITE)

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

	# Load icon
	if icon_texture:
		var icon_path = item.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon_texture.texture = load(icon_path)
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
