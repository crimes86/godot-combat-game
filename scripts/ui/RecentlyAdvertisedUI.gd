extends CanvasLayer
## Recently Advertised UI - Shows active trade listings
## Toggle with Tab key or /listings command

signal listing_selected(listing: Dictionary)
signal whisper_requested(seller_name: String)
signal show_on_map_requested(position: Vector2, seller_name: String)

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
	"RARE": Color(0.3, 0.5, 0.9),
	"EPIC": Color(0.6, 0.2, 0.8),
	"LEGENDARY": Color(1.0, 0.5, 0.1),
	"ARTIFACT": Color(0.9, 0.2, 0.2)
}

# UI elements
var main_panel: PanelContainer
var listings_container: ScrollContainer
var listings_list: VBoxContainer
var header_label: Label
var close_button: Button
var refresh_button: Button
var no_listings_label: Label

var is_visible: bool = false

func _ready() -> void:
	layer = 115  # Above chat (110) but below tooltips
	_create_ui()
	hide_panel()

	# Connect to TradingManager signals
	if TradingManager:
		TradingManager.listings_loaded.connect(_on_listings_loaded)

func _input(event: InputEvent) -> void:
	# Toggle with Tab key when not typing in chat
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			var chat_ui = get_node_or_null("/root/ChatUI")
			if chat_ui and chat_ui.is_chat_focused():
				return  # Don't toggle if typing in chat

			if is_visible:
				hide_panel()
			else:
				show_panel()
			get_viewport().set_input_as_handled()

		elif event.keycode == KEY_ESCAPE and is_visible:
			hide_panel()
			get_viewport().set_input_as_handled()

func _create_ui() -> void:
	"""Create the listings panel UI"""

	# Main panel
	main_panel = PanelContainer.new()
	main_panel.name = "ListingsPanel"

	# Position at right side of screen
	main_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	main_panel.custom_minimum_size = Vector2(380, 450)
	main_panel.anchor_left = 1.0
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 1.0
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -400
	main_panel.offset_right = -20
	main_panel.offset_top = -225
	main_panel.offset_bottom = 225

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
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header row
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vbox.add_child(header_row)

	# Header label
	header_label = Label.new()
	header_label.text = "RECENTLY ADVERTISED"
	header_label.add_theme_color_override("font_color", HEADER_COLOR)
	header_label.add_theme_font_size_override("font_size", 16)
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_label)

	# Refresh button
	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.custom_minimum_size = Vector2(70, 0)
	_style_button(refresh_button, ACCENT_COLOR)
	refresh_button.pressed.connect(_on_refresh_pressed)
	header_row.add_child(refresh_button)

	# Close button
	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 0)
	_style_button(close_button, Color(0.7, 0.3, 0.3))
	close_button.pressed.connect(hide_panel)
	header_row.add_child(close_button)

	# Hint label
	var hint = Label.new()
	hint.text = "Press Tab to toggle | Trade requires proximity"
	hint.add_theme_color_override("font_color", ACCENT_COLOR)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	# Listings scroll container
	listings_container = ScrollContainer.new()
	listings_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	listings_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	listings_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = INPUT_BG
	scroll_style.corner_radius_top_left = 4
	scroll_style.corner_radius_top_right = 4
	scroll_style.corner_radius_bottom_left = 4
	scroll_style.corner_radius_bottom_right = 4
	listings_container.add_theme_stylebox_override("panel", scroll_style)
	vbox.add_child(listings_container)

	# Listings list
	listings_list = VBoxContainer.new()
	listings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listings_list.add_theme_constant_override("separation", 4)
	listings_container.add_child(listings_list)

	# No listings label
	no_listings_label = Label.new()
	no_listings_label.text = "No items advertised.\n\nUse /sell to list your forged items!"
	no_listings_label.add_theme_color_override("font_color", ACCENT_COLOR)
	no_listings_label.add_theme_font_size_override("font_size", 13)
	no_listings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_listings_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	listings_list.add_child(no_listings_label)

	add_child(main_panel)

func _style_button(button: Button, color: Color) -> void:
	"""Apply consistent button styling"""
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4

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
	"""Show the listings panel"""
	main_panel.visible = true
	is_visible = true
	_refresh_listings()

func hide_panel() -> void:
	"""Hide the listings panel"""
	main_panel.visible = false
	is_visible = false

func _on_refresh_pressed() -> void:
	"""Manual refresh button pressed"""
	_refresh_listings()

func _refresh_listings() -> void:
	"""Fetch fresh listings from server"""
	if TradingManager:
		TradingManager.fetch_listings()

func _on_listings_loaded(listings: Array) -> void:
	"""Update UI when listings are loaded"""
	_populate_listings(listings)

func _populate_listings(listings: Array) -> void:
	"""Populate the listings display"""
	# Clear existing items (except no_listings_label)
	for child in listings_list.get_children():
		if child != no_listings_label:
			child.queue_free()

	if listings.is_empty():
		no_listings_label.visible = true
		return

	no_listings_label.visible = false

	# Add listing items
	for listing in listings:
		var item_row = _create_listing_row(listing)
		listings_list.add_child(item_row)

func _create_listing_row(listing: Dictionary) -> Control:
	"""Create a row for a single listing"""
	var item = listing.get("item", {})
	var seller = listing.get("seller", {})

	var row = PanelContainer.new()
	var row_style = StyleBoxFlat.new()
	row_style.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	row_style.border_width_left = 2
	row_style.border_color = _get_rarity_color(item.get("rarity", "COMMON"))
	row_style.corner_radius_top_left = 4
	row_style.corner_radius_top_right = 4
	row_style.corner_radius_bottom_left = 4
	row_style.corner_radius_bottom_right = 4
	row_style.content_margin_left = 8
	row_style.content_margin_right = 8
	row_style.content_margin_top = 6
	row_style.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", row_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	row.add_child(hbox)

	# Item info (left side)
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	# Item name
	var name_label = Label.new()
	name_label.text = item.get("item_name", "Unknown Item")
	name_label.add_theme_color_override("font_color", _get_rarity_color(item.get("rarity", "COMMON")))
	name_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_label)

	# Seller and message
	var seller_name = seller.get("display_name", "Unknown")
	var message = listing.get("message", "")
	var detail_text = "by %s" % seller_name
	if message != "" and message != null:
		detail_text += " - \"%s\"" % message.substr(0, 35)
		if message.length() > 35:
			detail_text += "..."

	var detail_label = Label.new()
	detail_label.text = detail_text
	detail_label.add_theme_color_override("font_color", ACCENT_COLOR)
	detail_label.add_theme_font_size_override("font_size", 11)
	info_vbox.add_child(detail_label)

	# Right side - price and button
	var right_vbox = VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(right_vbox)

	# Price
	var price_label = Label.new()
	price_label.text = "%dg" % listing.get("price_gold", 0)
	price_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))  # Gold color
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_vbox.add_child(price_label)

	# Button row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	right_vbox.add_child(btn_row)

	# Whisper button
	var whisper_btn = Button.new()
	whisper_btn.text = "Whisper"
	whisper_btn.custom_minimum_size = Vector2(60, 0)
	_style_button(whisper_btn, Color(0.3, 0.5, 0.7))
	whisper_btn.pressed.connect(_on_whisper_pressed.bind(seller_name))
	btn_row.add_child(whisper_btn)

	# Show on Map button (only if seller has position)
	var seller_pos = seller.get("position", {})
	if seller_pos and seller_pos.get("x") != null:
		var map_btn = Button.new()
		map_btn.text = "Map"
		map_btn.custom_minimum_size = Vector2(45, 0)
		_style_button(map_btn, Color(0.4, 0.6, 0.4))
		var pos = Vector2(seller_pos.get("x", 0), seller_pos.get("y", 0))
		map_btn.pressed.connect(_on_show_map_pressed.bind(pos, seller_name))
		btn_row.add_child(map_btn)

	# Store listing data on the row for click handling
	row.set_meta("listing", listing)

	return row

func _get_rarity_color(rarity: String) -> Color:
	"""Get color for item rarity"""
	return RARITY_COLORS.get(rarity.to_upper(), Color(0.7, 0.7, 0.7))

func _on_whisper_pressed(seller_name: String) -> void:
	"""Open chat with whisper to seller"""
	whisper_requested.emit(seller_name)

	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui:
		# Pre-fill whisper command in chat
		chat_ui.set_input_text("/w %s " % seller_name)
		chat_ui.focus_input()
		chat_ui.add_system_message("Type your message to whisper %s" % seller_name)
		chat_ui.add_system_message("Meet in-game to trade (5 tile proximity required)")

func _on_show_map_pressed(position: Vector2, seller_name: String) -> void:
	"""Show seller location on the minimap"""
	show_on_map_requested.emit(position, seller_name)

	# Create a temporary waypoint marker
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var distance = player.global_position.distance_to(position) / 32.0  # Convert to tiles
		var direction = (position - player.global_position).normalized()
		var compass = _get_compass_direction(direction)

		var chat_ui = get_node_or_null("/root/ChatUI")
		if chat_ui:
			chat_ui.add_system_message("%s is %s (%.0f tiles %s)" % [seller_name, _format_position(position), distance, compass])
			chat_ui.add_system_message("Look for the marker on your minimap!")

	# Emit a signal that the game world can use to create a waypoint
	_create_waypoint_marker(position, seller_name)

func _get_compass_direction(direction: Vector2) -> String:
	"""Convert direction vector to compass direction"""
	var angle = rad_to_deg(direction.angle())
	if angle < -157.5 or angle > 157.5:
		return "West"
	elif angle < -112.5:
		return "NW"
	elif angle < -67.5:
		return "North"
	elif angle < -22.5:
		return "NE"
	elif angle < 22.5:
		return "East"
	elif angle < 67.5:
		return "SE"
	elif angle < 112.5:
		return "South"
	else:
		return "SW"

func _format_position(pos: Vector2) -> String:
	"""Format position as coordinates"""
	return "at (%.0f, %.0f)" % [pos.x / 32.0, pos.y / 32.0]

func _create_waypoint_marker(position: Vector2, label_text: String) -> void:
	"""Create a temporary waypoint marker in the game world"""
	# This will be picked up by the minimap/world
	var waypoint_data = {
		"position": position,
		"label": label_text,
		"color": Color(0.3, 0.8, 0.4),  # Green for seller
		"duration": 60.0  # Show for 60 seconds
	}

	# Try to notify the game world
	var game_world = get_tree().get_first_node_in_group("game_world")
	if game_world and game_world.has_method("add_waypoint"):
		game_world.add_waypoint(waypoint_data)
	else:
		# Fallback: create a simple visual indicator
		_create_simple_waypoint(position, label_text)

func _create_simple_waypoint(position: Vector2, label_text: String) -> void:
	"""Create a simple waypoint indicator in the world"""
	var game_world = get_tree().get_first_node_in_group("game_world")
	if not game_world:
		return

	# Create a simple pulsing circle marker
	var marker = Node2D.new()
	marker.name = "TradeWaypoint_%s" % label_text.replace(" ", "_")
	marker.global_position = position
	marker.z_index = 100
	game_world.add_child(marker)

	# Draw script for the marker
	var marker_script = GDScript.new()
	marker_script.source_code = """
extends Node2D

var lifetime: float = 60.0
var elapsed: float = 0.0
var label_text: String = ""
var pulse_phase: float = 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	elapsed += delta
	pulse_phase += delta * 3.0
	if elapsed >= lifetime:
		queue_free()
	queue_redraw()

func _draw() -> void:
	var alpha = 1.0 - (elapsed / lifetime) * 0.5  # Fade out over time
	var pulse = 0.5 + 0.5 * sin(pulse_phase)
	var radius = 16.0 + pulse * 8.0

	# Outer glow
	draw_circle(Vector2.ZERO, radius + 4, Color(0.3, 0.8, 0.4, alpha * 0.3))
	# Main circle
	draw_circle(Vector2.ZERO, radius, Color(0.3, 0.8, 0.4, alpha * 0.6))
	# Inner highlight
	draw_circle(Vector2.ZERO, radius * 0.5, Color(0.5, 1.0, 0.6, alpha * 0.8))

	# Draw label
	var font = ThemeDB.fallback_font
	var font_size = 12
	draw_string(font, Vector2(-40, -radius - 8), label_text, HORIZONTAL_ALIGNMENT_CENTER, 80, font_size, Color(1, 1, 1, alpha))
"""
	marker.set_script(marker_script)
	marker.set("label_text", label_text)
