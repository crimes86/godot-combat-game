extends CanvasLayer

## PlayerInteractionMenu - Modal menu for player-to-player interactions
## Shows options: Inspect Equipment, Request Trade, Challenge to Duel
##
## Triggered by PlayerInteractionController after F-key radial completion

signal menu_closed
signal option_selected(option: String, target_id: int)

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
var BTN_NORMAL: Color:
	get: return UITheme.BTN_NORMAL
var BTN_HOVER: Color:
	get: return UITheme.BTN_HOVER

# Target player info
var target_player_id: int = -1
var target_player_name: String = ""
var target_player_node: Node2D = null

# UI state
var is_visible: bool = false

# UI elements
var main_panel: PanelContainer
var inspect_button: Button
var trade_button: Button
var duel_button: Button
var cancel_button: Button

func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return

	layer = 115  # Above game, below character sheet (120)
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
			hide_menu()
			get_viewport().set_input_as_handled()

	# Close on click outside
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_viewport().get_mouse_position()
			if not _is_point_in_panel(mouse_pos):
				hide_menu()
				get_viewport().set_input_as_handled()

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func show_menu(player_id: int, player_name: String, player_node: Node2D = null) -> void:
	"""Show the interaction menu for a target player"""
	target_player_id = player_id
	target_player_name = player_name
	target_player_node = player_node

	_update_header()
	_update_button_states()

	main_panel.visible = true
	is_visible = true

	# Fade in
	main_panel.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(main_panel, "modulate:a", 1.0, 0.15)

	# Play sound
	if SoundManager:
		SoundManager.play_inventory_open_sound()

func hide_menu() -> void:
	"""Hide the interaction menu"""
	if not is_visible:
		return

	is_visible = false

	# Fade out
	var tween = create_tween()
	tween.tween_property(main_panel, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func(): main_panel.visible = false)

	# Clear target
	target_player_id = -1
	target_player_name = ""
	target_player_node = null

	menu_closed.emit()

# ═══════════════════════════════════════════════════════════════════════════
# UI CREATION
# ═══════════════════════════════════════════════════════════════════════════

func _create_ui() -> void:
	"""Create the menu UI - modern styled interaction panel"""
	# Main panel - centered on screen
	main_panel = PanelContainer.new()
	main_panel.name = "InteractionMenuPanel"

	# Center positioning - slightly larger for better readability
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(300, 260)
	main_panel.offset_left = -150
	main_panel.offset_right = 150
	main_panel.offset_top = -130
	main_panel.offset_bottom = 130

	# Panel styling - darker background with gold accent border
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.95)  # Near-black
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 3  # Thicker top for accent
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.6, 0.5, 0.3, 0.9)  # Gold/bronze
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 15
	panel_style.shadow_color = Color(0, 0, 0, 0.7)
	panel_style.shadow_offset = Vector2(0, 6)
	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Margin container
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	main_panel.add_child(margin)

	# Main VBox
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header with player name - prominent display
	var header = Label.new()
	header.name = "Header"
	header.text = "Player"  # Will be updated with actual name
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))  # Gold text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Decorative separator - styled line
	var sep = HSeparator.new()
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.45, 0.3, 0.6)
	sep_style.set_content_margin_all(1)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# Button container
	var btn_vbox = VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_vbox)

	# Inspect button - blue theme with icon
	inspect_button = Button.new()
	inspect_button.text = "  Inspect Equipment"
	inspect_button.custom_minimum_size.y = 42
	_style_button(inspect_button, Color(0.2, 0.35, 0.5, 0.9), Color(0.3, 0.5, 0.7))
	inspect_button.pressed.connect(_on_inspect_pressed)
	btn_vbox.add_child(inspect_button)

	# Trade button - green/gold theme with icon
	trade_button = Button.new()
	trade_button.text = "  Request Trade"
	trade_button.custom_minimum_size.y = 42
	_style_button(trade_button, Color(0.35, 0.45, 0.25, 0.9), Color(0.5, 0.6, 0.35))
	trade_button.pressed.connect(_on_trade_pressed)
	btn_vbox.add_child(trade_button)

	# Duel button - red theme with icon
	duel_button = Button.new()
	duel_button.text = "  Challenge to Duel"
	duel_button.custom_minimum_size.y = 42
	_style_button(duel_button, Color(0.5, 0.25, 0.25, 0.9), Color(0.7, 0.35, 0.35))
	duel_button.pressed.connect(_on_duel_pressed)
	btn_vbox.add_child(duel_button)

	# Spacer before cancel
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 4
	vbox.add_child(spacer)

	# Cancel button - subtle gray
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size.y = 34
	_style_button(cancel_button, Color(0.25, 0.25, 0.28, 0.8), Color(0.35, 0.35, 0.4))
	cancel_button.pressed.connect(_on_cancel_pressed)
	vbox.add_child(cancel_button)

	add_child(main_panel)

func _style_button(button: Button, color: Color, hover_color: Color = Color.BLACK) -> void:
	"""Apply consistent button styling with custom hover color"""
	# If no hover color provided, use lightened version of base
	if hover_color == Color.BLACK:
		hover_color = color.lightened(0.2)

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_bottom = 2
	style.border_color = color.darkened(0.3)  # Subtle bottom border for depth

	var hover = style.duplicate()
	hover.bg_color = hover_color
	hover.border_color = hover_color.darkened(0.2)

	var pressed = style.duplicate()
	pressed.bg_color = color.darkened(0.15)
	pressed.border_width_bottom = 1

	var disabled = style.duplicate()
	disabled.bg_color = Color(0.2, 0.2, 0.22, 0.6)
	disabled.border_color = Color(0.15, 0.15, 0.18, 0.5)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)

	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.92))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48, 0.7))

func _update_header() -> void:
	"""Update the header with target player name"""
	var header = main_panel.get_node_or_null("MarginContainer/VBoxContainer/Header")
	if header:
		header.text = target_player_name

func _update_button_states() -> void:
	"""Update button enabled states based on current conditions"""
	# Check trade availability
	if TradeWindowUI:
		var trade_check = TradeWindowUI.can_request_trade(target_player_id)
		trade_button.disabled = not trade_check.valid
		trade_button.tooltip_text = trade_check.reason if not trade_check.valid else ""
	else:
		trade_button.disabled = true

	# Check duel availability
	if DuelManager:
		var duel_check = DuelManager.can_request_duel(target_player_id)
		duel_button.disabled = not duel_check.valid
		duel_button.tooltip_text = duel_check.reason if not duel_check.valid else ""
	else:
		duel_button.disabled = true

	# Inspect is always available
	inspect_button.disabled = false

# ═══════════════════════════════════════════════════════════════════════════
# BUTTON CALLBACKS
# ═══════════════════════════════════════════════════════════════════════════

func _on_inspect_pressed() -> void:
	"""Open equipment inspection UI"""
	if SoundManager:
		SoundManager.play_button_click_sound()

	option_selected.emit("inspect", target_player_id)

	# Open inspection UI
	if PlayerInspectUI:
		PlayerInspectUI.show_inspection(target_player_id, target_player_name, target_player_node)

	hide_menu()

func _on_trade_pressed() -> void:
	"""Request trade with target player"""
	print("[PlayerInteractionMenu] Trade button pressed for target: %d (%s)" % [target_player_id, target_player_name])

	if SoundManager:
		SoundManager.play_button_click_sound()

	option_selected.emit("trade", target_player_id)

	# Request trade through TradeWindowUI
	if TradeWindowUI:
		print("[PlayerInteractionMenu] Calling TradeWindowUI.request_trade(%d)" % target_player_id)
		var result = TradeWindowUI.request_trade(target_player_id)
		print("[PlayerInteractionMenu] request_trade result: success=%s, message=%s" % [result.success, result.message])
		if result.success:
			if NotificationManager:
				NotificationManager.show_notification(result.message, "INFO")
		else:
			if NotificationManager:
				NotificationManager.show_notification(result.message, "ERROR")
	else:
		print("[PlayerInteractionMenu] ERROR: TradeWindowUI not found!")

	hide_menu()

func _on_duel_pressed() -> void:
	"""Challenge target player to a duel"""
	if SoundManager:
		SoundManager.play_button_click_sound()

	option_selected.emit("duel", target_player_id)

	# Request duel through DuelManager
	if DuelManager:
		var result = DuelManager.request_duel(target_player_id)
		if result.success:
			# Show "waiting for response" message
			if NotificationManager:
				NotificationManager.show_notification(
					"Duel request sent to %s. Waiting for response..." % target_player_name,
					"INFO"
				)
		else:
			if NotificationManager:
				NotificationManager.show_notification(result.message, "ERROR")

	hide_menu()

func _on_cancel_pressed() -> void:
	"""Close the menu"""
	if SoundManager:
		SoundManager.play_button_click_sound()
	hide_menu()

# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _is_point_in_panel(point: Vector2) -> bool:
	"""Check if a point is within the panel bounds"""
	if not main_panel or not main_panel.visible:
		return false

	var rect = main_panel.get_global_rect()
	return rect.has_point(point)
