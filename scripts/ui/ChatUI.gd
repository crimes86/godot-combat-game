extends CanvasLayer

## Chat UI - Multiplayer chat system
## Stone Gray UI theme matching CharacterUI/MainMenu
## Press Enter to focus chat input, Escape to unfocus

signal chat_message_sent(message: String)

var is_input_focused: bool = false

# UI References
var chat_panel: PanelContainer
var message_container: ScrollContainer
var message_list: VBoxContainer
var input_field: LineEdit
var send_button: Button

# Stone Gray UI Palette (matching CharacterUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.85)  # Dark stone gray
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)  # Light steel accent
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)  # Silver headers
const INPUT_BG = Color(0.08, 0.08, 0.10, 0.9)  # Dark stone inset
const SYSTEM_COLOR = Color(0.6, 0.7, 0.9, 1.0)  # Blue-ish for system messages
const LOCAL_COLOR = Color(0.9, 0.85, 0.5, 1.0)  # Gold for local player

# Chat history
var max_messages: int = 50
var messages: Array[Dictionary] = []

# Network reference
var network_manager = null

func _ready() -> void:
	# Set layer above game but below important UI
	layer = 90

	# Create UI
	create_chat_ui()

	# Connect to network manager
	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)
		network_manager.chat_message_received.connect(_on_chat_message_received)

	# Add system welcome message
	add_system_message("Welcome! Press Enter to chat.")

func _input(event: InputEvent) -> void:
	# Toggle chat focus with Enter key
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not is_input_focused:
				focus_input()
				get_viewport().set_input_as_handled()
			elif input_field and input_field.text.strip_edges() != "":
				send_message()
				get_viewport().set_input_as_handled()
			else:
				unfocus_input()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_input_focused:
			unfocus_input()
			get_viewport().set_input_as_handled()

func create_chat_ui() -> void:
	"""Create chat panel at bottom-left of screen"""

	# Main chat panel
	chat_panel = PanelContainer.new()
	chat_panel.name = "ChatPanel"

	# Position at bottom-left
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.custom_minimum_size = Vector2(400, 200)
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_right = 0.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 10
	chat_panel.offset_right = 410
	chat_panel.offset_top = -210
	chat_panel.offset_bottom = -10

	# Apply stone gray styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_offset = Vector2(0, 4)

	chat_panel.add_theme_stylebox_override("panel", panel_style)

	# Margin container for padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	chat_panel.add_child(margin)

	# Main vertical layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "CHAT"
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header.add_theme_font_size_override("font_size", 12)
	vbox.add_child(header)

	# Message scroll container
	message_container = ScrollContainer.new()
	message_container.name = "MessageScroll"
	message_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# Style scroll container background
	var scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = INPUT_BG
	scroll_style.corner_radius_top_left = 4
	scroll_style.corner_radius_top_right = 4
	scroll_style.corner_radius_bottom_left = 4
	scroll_style.corner_radius_bottom_right = 4
	message_container.add_theme_stylebox_override("panel", scroll_style)
	vbox.add_child(message_container)

	# Message list container
	message_list = VBoxContainer.new()
	message_list.name = "MessageList"
	message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_list.add_theme_constant_override("separation", 2)
	message_container.add_child(message_list)

	# Input row
	var input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	vbox.add_child(input_row)

	# Text input field
	input_field = LineEdit.new()
	input_field.name = "ChatInput"
	input_field.placeholder_text = "Type message..."
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.max_length = 200

	# Style input field
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = INPUT_BG
	input_style.border_width_bottom = 1
	input_style.border_color = ACCENT_COLOR
	input_style.corner_radius_top_left = 4
	input_style.corner_radius_top_right = 4
	input_style.corner_radius_bottom_left = 4
	input_style.corner_radius_bottom_right = 4
	input_style.content_margin_left = 8
	input_style.content_margin_right = 8
	input_style.content_margin_top = 4
	input_style.content_margin_bottom = 4

	input_field.add_theme_stylebox_override("normal", input_style)
	input_field.add_theme_color_override("font_color", TEXT_COLOR)
	input_field.add_theme_color_override("font_placeholder_color", ACCENT_COLOR)
	input_field.add_theme_font_size_override("font_size", 13)

	# Focus style
	var focus_style = input_style.duplicate()
	focus_style.border_width_bottom = 2
	focus_style.border_color = LOCAL_COLOR
	input_field.add_theme_stylebox_override("focus", focus_style)

	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)
	input_field.text_submitted.connect(_on_input_submitted)

	input_row.add_child(input_field)

	# Send button
	send_button = Button.new()
	send_button.name = "SendButton"
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(60, 0)

	# Style send button
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = ACCENT_COLOR
	button_style.corner_radius_top_left = 4
	button_style.corner_radius_top_right = 4
	button_style.corner_radius_bottom_left = 4
	button_style.corner_radius_bottom_right = 4
	button_style.content_margin_left = 8
	button_style.content_margin_right = 8
	button_style.content_margin_top = 4
	button_style.content_margin_bottom = 4

	var button_hover = button_style.duplicate()
	button_hover.bg_color = HEADER_COLOR

	var button_pressed = button_style.duplicate()
	button_pressed.bg_color = BORDER_INNER

	send_button.add_theme_stylebox_override("normal", button_style)
	send_button.add_theme_stylebox_override("hover", button_hover)
	send_button.add_theme_stylebox_override("pressed", button_pressed)
	send_button.add_theme_color_override("font_color", BG_COLOR)
	send_button.add_theme_font_size_override("font_size", 12)

	send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(send_button)

	add_child(chat_panel)

func focus_input() -> void:
	"""Focus the chat input field"""
	if input_field:
		input_field.grab_focus()
		is_input_focused = true

func unfocus_input() -> void:
	"""Remove focus from chat input"""
	if input_field:
		input_field.release_focus()
		is_input_focused = false

func send_message() -> void:
	"""Send the current message"""
	if not input_field:
		return

	var text = input_field.text.strip_edges()
	if text.is_empty():
		return

	# Get player name
	var sender_name = "Player"
	if network_manager:
		sender_name = network_manager.player_name

	# Add message locally (single player or when network not connected)
	var is_multiplayer = network_manager and multiplayer.has_multiplayer_peer()

	if is_multiplayer:
		# Use NetworkManager to send (it will broadcast to all including us)
		network_manager.send_chat_message(text)
	else:
		# Single player - just show locally
		add_chat_message(sender_name, text, true)

	# Clear input
	input_field.text = ""

	# Emit signal
	chat_message_sent.emit(text)

func add_chat_message(sender: String, text: String, is_local: bool = false) -> void:
	"""Add a chat message to the display"""
	var msg_data = {
		"sender": sender,
		"text": text,
		"is_local": is_local,
		"timestamp": Time.get_unix_time_from_system()
	}
	messages.append(msg_data)

	# Trim old messages
	while messages.size() > max_messages:
		messages.pop_front()
		if message_list.get_child_count() > 0:
			message_list.get_child(0).queue_free()

	# Create message label
	var msg_label = RichTextLabel.new()
	msg_label.bbcode_enabled = true
	msg_label.fit_content = true
	msg_label.scroll_active = false
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_font_size_override("normal_font_size", 12)

	# Format message with color
	var name_color = LOCAL_COLOR if is_local else TEXT_COLOR
	var name_hex = name_color.to_html(false)
	msg_label.text = "[color=#%s]%s:[/color] %s" % [name_hex, sender, text]

	message_list.add_child(msg_label)

	# Scroll to bottom
	await get_tree().process_frame
	if message_container:
		message_container.scroll_vertical = int(message_container.get_v_scroll_bar().max_value)

func add_system_message(text: String) -> void:
	"""Add a system message (server announcements, join/leave, etc.)"""
	var msg_label = RichTextLabel.new()
	msg_label.bbcode_enabled = true
	msg_label.fit_content = true
	msg_label.scroll_active = false
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_label.add_theme_font_size_override("normal_font_size", 11)

	var color_hex = SYSTEM_COLOR.to_html(false)
	msg_label.text = "[color=#%s][i]%s[/i][/color]" % [color_hex, text]

	message_list.add_child(msg_label)

	# Scroll to bottom
	await get_tree().process_frame
	if message_container:
		message_container.scroll_vertical = int(message_container.get_v_scroll_bar().max_value)

# Signal callbacks
func _on_input_focus_entered() -> void:
	is_input_focused = true

func _on_input_focus_exited() -> void:
	is_input_focused = false

func _on_input_submitted(_text: String) -> void:
	send_message()
	# Keep focus after sending
	focus_input()

func _on_send_pressed() -> void:
	send_message()
	focus_input()

func _on_player_connected(id: int) -> void:
	var player_info = network_manager.connected_players.get(id, {})
	var name = player_info.get("name", "Player%d" % id)
	add_system_message("%s joined the game." % name)

func _on_player_disconnected(id: int) -> void:
	add_system_message("A player disconnected.")

func _on_chat_message_received(sender_name: String, message: String, sender_id: int) -> void:
	"""Handle chat messages from NetworkManager"""
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	var is_local = (sender_id == my_id)
	add_chat_message(sender_name, message, is_local)

# Public API
func is_chat_focused() -> bool:
	"""Check if chat input is currently focused (for disabling game input)"""
	return is_input_focused
