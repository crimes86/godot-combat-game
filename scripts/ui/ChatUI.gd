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
var header_label: Label
var input_row: HBoxContainer

# Style references for fade effect (fade background, keep text visible)
var panel_style: StyleBoxFlat
var scroll_style: StyleBoxFlat
var input_style_normal: StyleBoxFlat
var input_style_focus: StyleBoxFlat
var button_style_normal: StyleBoxFlat
var button_style_hover: StyleBoxFlat
var button_style_pressed: StyleBoxFlat

# UI colors - use UITheme singleton for consistency
var BG_COLOR: Color:
	get: return UITheme.BG_COLOR
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
var INPUT_BG: Color:
	get: return UITheme.INPUT_BG
var SYSTEM_COLOR: Color:
	get: return UITheme.CHAT_SYSTEM
var LOCAL_COLOR: Color:
	get: return UITheme.CHAT_LOCAL

# Chat history
var max_messages: int = 50
var messages: Array[Dictionary] = []

# Network reference
var network_manager = null

func _ready() -> void:
	# Set layer above game prompts (campfire hints are at 100)
	layer = 110

	# Create UI
	create_chat_ui()

	# Connect to network manager
	network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		network_manager.player_authenticated.connect(_on_player_authenticated)
		network_manager.player_disconnected.connect(_on_player_disconnected)
		network_manager.chat_message_received.connect(_on_chat_message_received)

	# Add system welcome message
	add_system_message("Welcome! Press Enter to chat.")

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	if network_manager:
		if network_manager.player_authenticated.is_connected(_on_player_authenticated):
			network_manager.player_authenticated.disconnect(_on_player_authenticated)
		if network_manager.player_disconnected.is_connected(_on_player_disconnected):
			network_manager.player_disconnected.disconnect(_on_player_disconnected)
		if network_manager.chat_message_received.is_connected(_on_chat_message_received):
			network_manager.chat_message_received.disconnect(_on_chat_message_received)

func _input(event: InputEvent) -> void:
	# Don't process input if admin panel is open
	var admin_panel = get_node_or_null("/root/AccountAdmin")
	if admin_panel and admin_panel.is_visible:
		return

	# "/" key opens chat and starts typing a command
	if event is InputEventKey and event.pressed and event.keycode == KEY_SLASH:
		if not is_input_focused:
			focus_input()
			# Pre-fill with "/" so user can start typing command immediately
			input_field.text = "/"
			input_field.caret_column = 1  # Put cursor after the /
			get_viewport().set_input_as_handled()
			return

	# Readline-style shortcuts when chat is focused
	if is_input_focused and event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_A:  # Ctrl+A - Move cursor to beginning of line
				input_field.caret_column = 0
				get_viewport().set_input_as_handled()
				return
			KEY_E:  # Ctrl+E - Move cursor to end of line
				input_field.caret_column = input_field.text.length()
				get_viewport().set_input_as_handled()
				return
			KEY_U:  # Ctrl+U - Delete from cursor to beginning of line
				var pos = input_field.caret_column
				input_field.text = input_field.text.substr(pos)
				input_field.caret_column = 0
				get_viewport().set_input_as_handled()
				return
			KEY_K:  # Ctrl+K - Delete from cursor to end of line
				input_field.text = input_field.text.substr(0, input_field.caret_column)
				get_viewport().set_input_as_handled()
				return
			KEY_W:  # Ctrl+W - Delete word before cursor
				var text = input_field.text
				var pos = input_field.caret_column
				if pos > 0:
					# Skip trailing spaces
					var end = pos
					while pos > 0 and text[pos - 1] == " ":
						pos -= 1
					# Delete word
					while pos > 0 and text[pos - 1] != " ":
						pos -= 1
					input_field.text = text.substr(0, pos) + text.substr(end)
					input_field.caret_column = pos
				get_viewport().set_input_as_handled()
				return

	# Toggle chat focus with Enter key
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# Don't capture Enter if another UI element has focus
			var focused = get_viewport().gui_get_focus_owner()
			if focused and focused != input_field:
				return  # Let the focused control handle it

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

	# Position at bottom-left (larger size)
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_panel.custom_minimum_size = Vector2(570, 320)
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_right = 0.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 10
	chat_panel.offset_right = 580
	chat_panel.offset_top = -330
	chat_panel.offset_bottom = -10

	# Enable mouse detection for hover fade effect
	chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	chat_panel.mouse_entered.connect(_on_chat_mouse_entered)
	chat_panel.mouse_exited.connect(_on_chat_mouse_exited)

	# Keep panel at full opacity - we'll fade the BACKGROUND colors instead
	# This keeps text visible while backgrounds fade
	chat_panel.modulate.a = 1.0

	# Apply stone gray styling - start fully transparent (ghosted)
	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.0)  # Fully invisible
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.0)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 0  # No shadow when ghosted
	panel_style.shadow_color = Color(0, 0, 0, 0)
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

	# Header - hidden when ghosted, visible on hover
	header_label = Label.new()
	header_label.text = "CHAT"
	header_label.add_theme_color_override("font_color", HEADER_COLOR)
	header_label.add_theme_font_size_override("font_size", 14)
	header_label.modulate.a = 0.0  # Start hidden
	vbox.add_child(header_label)

	# Message scroll container
	message_container = ScrollContainer.new()
	message_container.name = "MessageScroll"
	message_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	# Style scroll container background - start transparent (text floats)
	scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = Color(INPUT_BG.r, INPUT_BG.g, INPUT_BG.b, 0.0)  # Fully transparent
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

	# Input row - hidden when ghosted
	input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 4)
	input_row.modulate.a = 0.0  # Start hidden
	vbox.add_child(input_row)

	# Text input field
	input_field = LineEdit.new()
	input_field.name = "ChatInput"
	input_field.placeholder_text = "Type message... (Enter or / to focus)"
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.max_length = 200

	# Style input field - store reference for fade
	input_style_normal = StyleBoxFlat.new()
	input_style_normal.bg_color = INPUT_BG
	input_style_normal.border_width_bottom = 1
	input_style_normal.border_color = ACCENT_COLOR
	input_style_normal.corner_radius_top_left = 4
	input_style_normal.corner_radius_top_right = 4
	input_style_normal.corner_radius_bottom_left = 4
	input_style_normal.corner_radius_bottom_right = 4
	input_style_normal.content_margin_left = 8
	input_style_normal.content_margin_right = 8
	input_style_normal.content_margin_top = 4
	input_style_normal.content_margin_bottom = 4

	input_field.add_theme_stylebox_override("normal", input_style_normal)
	input_field.add_theme_color_override("font_color", TEXT_COLOR)
	input_field.add_theme_color_override("font_placeholder_color", ACCENT_COLOR)
	input_field.add_theme_font_size_override("font_size", 14)

	# Focus style
	input_style_focus = input_style_normal.duplicate()
	input_style_focus.border_width_bottom = 2
	input_style_focus.border_color = LOCAL_COLOR
	input_field.add_theme_stylebox_override("focus", input_style_focus)

	input_field.focus_entered.connect(_on_input_focus_entered)
	input_field.focus_exited.connect(_on_input_focus_exited)
	input_field.text_submitted.connect(_on_input_submitted)

	input_row.add_child(input_field)

	# Send button
	send_button = Button.new()
	send_button.name = "SendButton"
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(60, 0)

	# Style send button - store references for fade
	button_style_normal = StyleBoxFlat.new()
	button_style_normal.bg_color = ACCENT_COLOR
	button_style_normal.corner_radius_top_left = 4
	button_style_normal.corner_radius_top_right = 4
	button_style_normal.corner_radius_bottom_left = 4
	button_style_normal.corner_radius_bottom_right = 4
	button_style_normal.content_margin_left = 8
	button_style_normal.content_margin_right = 8
	button_style_normal.content_margin_top = 4
	button_style_normal.content_margin_bottom = 4

	button_style_hover = button_style_normal.duplicate()
	button_style_hover.bg_color = HEADER_COLOR

	button_style_pressed = button_style_normal.duplicate()
	button_style_pressed.bg_color = BORDER_INNER

	send_button.add_theme_stylebox_override("normal", button_style_normal)
	send_button.add_theme_stylebox_override("hover", button_style_hover)
	send_button.add_theme_stylebox_override("pressed", button_style_pressed)
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
		_fade_to_active()  # Show fully when typing

func unfocus_input() -> void:
	"""Remove focus from chat input and return control to game"""
	if input_field:
		input_field.release_focus()
		is_input_focused = false
		_fade_to_ghosted()  # Fade back to ghosted when done typing
		# Explicitly release GUI focus so game input works immediately
		get_viewport().gui_release_focus()

func send_message() -> void:
	"""Send the current message"""
	if not input_field:
		return

	var text = input_field.text.strip_edges()
	if text.is_empty():
		return

	# Clear input first
	input_field.text = ""

	# Check for admin commands (start with /)
	if text.begins_with("/"):
		_handle_admin_command(text.substr(1))  # Remove the /
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
	msg_label.add_theme_font_size_override("normal_font_size", 11)

	# Format message with color
	var name_color = LOCAL_COLOR if is_local else TEXT_COLOR
	var name_hex = name_color.to_html(false)
	msg_label.text = "[color=#%s]%s:[/color] %s" % [name_hex, sender, text]

	message_list.add_child(msg_label)

	# Scroll to bottom after layout updates
	_scroll_to_bottom()

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

	# Scroll to bottom after layout updates
	_scroll_to_bottom()

func _scroll_to_bottom() -> void:
	"""Scroll chat to bottom after layout updates - needs multiple frames for RichTextLabel sizing"""
	if not message_container:
		return

	# Wait for two frames to ensure RichTextLabel has finished sizing
	await get_tree().process_frame
	await get_tree().process_frame

	if is_instance_valid(message_container):
		var scrollbar = message_container.get_v_scroll_bar()
		if scrollbar:
			message_container.scroll_vertical = int(scrollbar.max_value)

# Signal callbacks
func _on_input_focus_entered() -> void:
	is_input_focused = true

func _on_input_focus_exited() -> void:
	is_input_focused = false

func _on_input_submitted(_text: String) -> void:
	send_message()
	# Unfocus after sending so player can move immediately
	# Press / or Enter to start typing again
	unfocus_input()

func _on_send_pressed() -> void:
	send_message()
	# Unfocus after sending so player can move immediately
	unfocus_input()

func _on_player_authenticated(id: int, player_name: String) -> void:
	add_system_message("%s joined the game." % player_name)

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

# ═══════════════════════════════════════════════════════════════════════════
# ADMIN COMMANDS (type /help for list)
# ═══════════════════════════════════════════════════════════════════════════

var _selected_account: String = ""  # For account commands

# Admin command security - only server host can use admin commands
const ADMIN_COMMANDS: Array[String] = [
	"accounts", "select", "info", "setpos", "resetpos",
	"setgold", "setlevel", "setstats", "ban", "unban",
	"forceoffline", "delete", "tp", "goto"
]

# Input validation bounds
const MAX_GOLD: int = 999999999
const MIN_GOLD: int = 0
const MAX_LEVEL: int = 30
const MIN_LEVEL: int = 1
const MAX_STAT: int = 999
const MIN_STAT: int = 1
const MAX_POSITION: float = 50000.0
const MIN_POSITION: float = -50000.0

func _is_admin() -> bool:
	"""Check if current user has admin privileges (must be server host)"""
	if not multiplayer:
		return false
	# Only the server (peer_id 1) or host can use admin commands
	if multiplayer.is_server():
		return true
	# In single player or when hosting, peer_id is 1
	if multiplayer.get_unique_id() == 1:
		return true
	return false

func _require_admin(command: String) -> bool:
	"""Check admin permission and show error if not authorized"""
	if not _is_admin():
		add_system_message("[Error] Admin commands require server host privileges")
		add_system_message("Only the server host can use /%s" % command)
		return false
	return true

func _handle_admin_command(cmd: String) -> void:
	"""Process admin commands starting with /"""
	var parts = cmd.strip_edges().split(" ", false)
	if parts.is_empty():
		return

	var command = parts[0].to_lower()
	var args = parts.slice(1)

	# Check admin permission for admin-only commands
	if command in ADMIN_COMMANDS:
		if not _require_admin(command):
			return

	match command:
		"help":
			_cmd_help()
		# Group commands (available to all players)
		"invite":
			_cmd_group_invite(args)
		"accept":
			_cmd_group_accept()
		"decline":
			_cmd_group_decline()
		"kick":
			_cmd_group_kick(args)
		"leave", "leavegroup":
			_cmd_group_leave()
		"promote":
			_cmd_group_promote(args)
		"disband":
			_cmd_group_disband()
		"group", "party":
			_cmd_group_info()
		"players", "who":
			_cmd_players()
		# Duel commands
		"duel":
			_cmd_duel(args)
		"acceptduel":
			_cmd_duel_accept()
		"declineduel":
			_cmd_duel_decline()
		# Trading commands (requires Ashbane auth)
		"sell", "wts":
			_cmd_sell(args)
		"listings", "market", "recently":
			_cmd_listings()
		"mylistings":
			_cmd_my_listings()
		"cancel":
			_cmd_cancel_listing(args)
		"trade":
			_cmd_trade(args)
		"accepttrade":
			_cmd_accept_trade()
		"declinetrade":
			_cmd_decline_trade()
		# Admin commands (server host only - checked above)
		"accounts":
			_cmd_accounts()
		"select":
			_cmd_select(args)
		"info":
			_cmd_info()
		"setpos":
			_cmd_setpos(args)
		"resetpos":
			_cmd_resetpos()
		"setgold":
			_cmd_setgold(args)
		"setlevel":
			_cmd_setlevel(args)
		"setstats":
			_cmd_setstats(args)
		"ban":
			_cmd_ban(true)
		"unban":
			_cmd_ban(false)
		"forceoffline":
			_cmd_force_offline()
		"delete":
			_cmd_delete()
		"tp", "goto":
			_cmd_teleport(args)
		# Debug/Playtest commands (available to all for testing)
		"playtest", "debug":
			_cmd_playtest(args)
		_:
			add_system_message("Unknown command: /%s (type /help)" % command)

# ═══════════════════════════════════════════════════════════════════════════
# GROUP COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_group_invite(args: Array) -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var target_name = " ".join(args) if args.size() > 0 else ""
	var result = group_manager.cmd_invite(target_name)
	add_system_message(result)

func _cmd_group_accept() -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var result = group_manager.cmd_accept()
	add_system_message(result)

func _cmd_group_decline() -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var result = group_manager.cmd_decline()
	add_system_message(result)

func _cmd_group_leave() -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var result = group_manager.cmd_leave()
	add_system_message(result)

func _cmd_group_kick(args: Array) -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var target_name = " ".join(args) if args.size() > 0 else ""
	var result = group_manager.cmd_kick(target_name)
	add_system_message(result)

func _cmd_group_promote(args: Array) -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var target_name = " ".join(args) if args.size() > 0 else ""
	var result = group_manager.cmd_promote(target_name)
	add_system_message(result)

func _cmd_group_disband() -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	var result = group_manager.cmd_disband()
	add_system_message(result)

func _cmd_group_info() -> void:
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		add_system_message("[Error] Group system not available.")
		return

	if not group_manager.has_group():
		add_system_message("You are not in a group.")
		return

	add_system_message("=== Group Info ===")
	var leader_name = group_manager.get_member_name(group_manager.group_leader)
	add_system_message("Leader: %s" % leader_name)
	add_system_message("Members (%d/%d):" % [group_manager.group_members.size(), group_manager.MAX_GROUP_SIZE])
	for member_id in group_manager.group_members:
		var name = group_manager.get_member_name(member_id)
		var is_leader = member_id == group_manager.group_leader
		var is_you = member_id == multiplayer.get_unique_id()
		var suffix = ""
		if is_leader:
			suffix = " [Leader]"
		if is_you:
			suffix += " (You)"
		add_system_message("  - %s%s" % [name, suffix])

func _cmd_players() -> void:
	"""List all connected players - useful for /invite and /duel"""
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	var found_players: Dictionary = {}  # peer_id -> name

	# Try NetworkManager connected_players first
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		for peer_id in network_manager.connected_players:
			var player_info = network_manager.connected_players[peer_id]
			found_players[peer_id] = player_info.get("name", "Player%d" % peer_id)

	# Also search player nodes in scene (fallback for sync issues)
	var tree = get_tree()
	if tree:
		for node in tree.get_nodes_in_group("player"):
			var peer_id = node.get_multiplayer_authority()
			if not found_players.has(peer_id):
				var health_bar = node.get_node_or_null("HealthBar")
				if health_bar:
					var name_label = health_bar.get_node_or_null("NameLabel")
					if name_label:
						found_players[peer_id] = name_label.text

		for node in tree.get_nodes_in_group("players"):
			var peer_id = node.get_multiplayer_authority()
			if not found_players.has(peer_id):
				var health_bar = node.get_node_or_null("HealthBar")
				if health_bar:
					var name_label = health_bar.get_node_or_null("NameLabel")
					if name_label:
						found_players[peer_id] = name_label.text

	if found_players.is_empty():
		add_system_message("No players found.")
		return

	add_system_message("=== Online Players (%d) ===" % found_players.size())
	for peer_id in found_players:
		var name = found_players[peer_id]
		var is_you = peer_id == my_id
		if is_you:
			add_system_message("  %s (You)" % name)
		else:
			add_system_message("  %s" % name)

# ═══════════════════════════════════════════════════════════════════════════
# DUEL COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_duel(args: Array) -> void:
	"""Request a duel with another player"""
	if args.is_empty():
		add_system_message("Usage: /duel <player name>")
		return

	if not DuelManager:
		add_system_message("[Error] Duel system not available.")
		return

	var target_name = " ".join(args)  # Support names with spaces
	var target_id = _find_player_by_name(target_name)

	if target_id == -1:
		add_system_message("[Error] Player '%s' not found." % target_name)
		add_system_message("Use /players to see online players.")
		return

	var result = DuelManager.request_duel(target_id)
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

func _cmd_duel_accept() -> void:
	"""Accept a pending duel request"""
	if not DuelManager:
		add_system_message("[Error] Duel system not available.")
		return

	if not DuelManager.has_pending_request():
		add_system_message("[Error] No pending duel request.")
		return

	var result = DuelManager.accept_duel()
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

func _cmd_duel_decline() -> void:
	"""Decline a pending duel request"""
	if not DuelManager:
		add_system_message("[Error] Duel system not available.")
		return

	if not DuelManager.has_pending_request():
		add_system_message("[Error] No pending duel request.")
		return

	var result = DuelManager.decline_duel()
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

func _find_player_by_name(search_name: String) -> int:
	"""Find player peer ID by name (case-insensitive partial match)"""
	var search_lower = search_name.to_lower()
	print("[Duel] Searching for player: '%s'" % search_name)

	# First try NetworkManager connected_players
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		print("[Duel] connected_players: %s" % str(network_manager.connected_players))
		for peer_id in network_manager.connected_players:
			var player_info = network_manager.connected_players[peer_id]
			var name = player_info.get("name", "").to_lower()
			if name == search_lower or name.begins_with(search_lower):
				print("[Duel] Found in connected_players: %d" % peer_id)
				return peer_id

	# Fallback: search actual player nodes in scene
	var tree = get_tree()
	if tree:
		# Search all Player_* nodes directly
		for node in tree.get_nodes_in_group("player"):
			print("[Duel] Checking 'player' group node: %s (auth=%d)" % [node.name, node.get_multiplayer_authority()])
			var health_bar = node.get_node_or_null("HealthBar")
			if health_bar:
				var name_label = health_bar.get_node_or_null("NameLabel")
				if name_label:
					print("[Duel]   HealthBar name: '%s'" % name_label.text)
					if name_label.text.to_lower().begins_with(search_lower):
						return node.get_multiplayer_authority()

		for node in tree.get_nodes_in_group("players"):
			print("[Duel] Checking 'players' group node: %s (auth=%d)" % [node.name, node.get_multiplayer_authority()])
			var health_bar = node.get_node_or_null("HealthBar")
			if health_bar:
				var name_label = health_bar.get_node_or_null("NameLabel")
				if name_label:
					print("[Duel]   HealthBar name: '%s'" % name_label.text)
					if name_label.text.to_lower().begins_with(search_lower):
						return node.get_multiplayer_authority()

		# Last resort: search by node name pattern Player_*
		var world = tree.current_scene
		if world:
			for child in world.get_children():
				if child.name.begins_with("Player_"):
					print("[Duel] Found Player_ node: %s (auth=%d)" % [child.name, child.get_multiplayer_authority()])
					var health_bar = child.get_node_or_null("HealthBar")
					if health_bar:
						var name_label = health_bar.get_node_or_null("NameLabel")
						if name_label:
							print("[Duel]   HealthBar name: '%s'" % name_label.text)
							if name_label.text.to_lower().begins_with(search_lower):
								return child.get_multiplayer_authority()

	print("[Duel] Player not found!")
	return -1

# ═══════════════════════════════════════════════════════════════════════════
# TRADING COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_sell(args: Array) -> void:
	"""Create a trade listing for a forged item
	Usage: /sell <token_id> <price> [message]
	       /sell list - Show your forged items with token IDs
	"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		add_system_message("[Error] Trading requires Ashbane authentication.")
		add_system_message("Log in at the main menu to link your gaming accounts.")
		return

	if not TradingManager:
		add_system_message("[Error] Trading system not available.")
		return

	# /sell list - Show available items
	if args.size() == 1 and args[0].to_lower() == "list":
		_show_forged_items_list()
		return

	# /sell <token_id> <price> [message]
	if args.size() < 2:
		add_system_message("Usage: /sell <token_id> <price> [message]")
		add_system_message("       /sell list - Show your forged items")
		add_system_message("Example: /sell 42 500 Rare sword from my Steam days!")
		return

	# Validate token_id
	if not args[0].is_valid_int():
		add_system_message("[Error] Token ID must be a number. Use /sell list to see your items.")
		return

	var token_id = int(args[0])

	# Validate price
	if not args[1].is_valid_int():
		add_system_message("[Error] Price must be a whole number (gold).")
		return

	var price = int(args[1])
	if price <= 0:
		add_system_message("[Error] Price must be greater than 0.")
		return

	if price > 999999999:
		add_system_message("[Error] Price is too high (max 999,999,999 gold).")
		return

	# Optional message (remaining args joined)
	var message = ""
	if args.size() > 2:
		message = " ".join(args.slice(2))
		if message.length() > 256:
			message = message.substr(0, 256)

	# Verify player owns this item
	var forged_item = _find_forged_item_by_token(token_id)
	if forged_item.is_empty():
		add_system_message("[Error] You don't own an item with token ID %d." % token_id)
		add_system_message("Use /sell list to see your forged items.")
		return

	# Connect to response signal (one-shot)
	if not TradingManager.listing_created.is_connected(_on_listing_created):
		TradingManager.listing_created.connect(_on_listing_created, CONNECT_ONE_SHOT)
	if not TradingManager.trading_error.is_connected(_on_trading_error):
		TradingManager.trading_error.connect(_on_trading_error, CONNECT_ONE_SHOT)

	# Create the listing
	add_system_message("Creating listing for %s..." % forged_item.get("item_name", "item"))
	TradingManager.create_listing(token_id, price, message)

func _on_listing_created(listing: Dictionary) -> void:
	"""Handle successful listing creation"""
	# Disconnect error handler if still connected
	if TradingManager.trading_error.is_connected(_on_trading_error):
		TradingManager.trading_error.disconnect(_on_trading_error)

	add_system_message("[Trade] Listing created! Expires in 30 minutes.")
	add_system_message("[Trade] Other players can see your item in /listings")

func _on_trading_error(error: String) -> void:
	"""Handle trading errors"""
	# Disconnect success handler if still connected
	if TradingManager.listing_created.is_connected(_on_listing_created):
		TradingManager.listing_created.disconnect(_on_listing_created)

	add_system_message("[Error] %s" % error)

func _show_forged_items_list() -> void:
	"""Display player's forged items with token IDs"""
	if not ForgeItemManager:
		add_system_message("[Error] Forge system not available.")
		return

	var items = ForgeItemManager.get_all_forged_items()
	if items.is_empty():
		add_system_message("You have no forged items.")
		add_system_message("Forge items from achievements in the Armory!")
		return

	add_system_message("=== Your Forged Items ===")
	for item in items:
		var token_id = item.get("token_id", 0)
		var name = item.get("item_name", "Unknown")
		var rarity = item.get("item_rarity", "COMMON")
		add_system_message("  [%d] %s (%s)" % [token_id, name, rarity])
	add_system_message("Use: /sell <token_id> <price> [message]")

func _find_forged_item_by_token(token_id: int) -> Dictionary:
	"""Find a forged item by token ID"""
	if not ForgeItemManager:
		return {}

	for item in ForgeItemManager.get_all_forged_items():
		if item.get("token_id", -1) == token_id:
			return item
	return {}

func _cmd_listings() -> void:
	"""Show recently advertised items - opens UI panel"""
	if not TradingManager:
		add_system_message("[Error] Trading system not available.")
		return

	# Open the UI panel
	if RecentlyAdvertisedUI:
		RecentlyAdvertisedUI.show_panel()
		add_system_message("Opening listings panel... (Press Tab to toggle)")
	else:
		# Fallback to chat display if UI not available
		var listings = TradingManager.get_active_listings()
		if listings.is_empty():
			add_system_message("No active listings. Check back later!")
			add_system_message("Use /sell to list your forged items.")
			return

		add_system_message("=== Recently Advertised ===")
		for listing in listings.slice(0, 10):
			var item = listing.get("item", {})
			var item_name = item.get("item_name", "Unknown Item")
			var rarity = item.get("rarity", "COMMON")
			var price = listing.get("price_gold", 0)
			var seller = listing.get("seller", {})
			var seller_name = seller.get("display_name", "Unknown")
			var message = listing.get("message", "")

			var msg = "  %s (%s) - %dg by %s" % [item_name, rarity, price, seller_name]
			if message != "":
				msg += " \"%s\"" % message.substr(0, 40)
			add_system_message(msg)

		if listings.size() > 10:
			add_system_message("  ... and %d more listings" % (listings.size() - 10))

func _cmd_my_listings() -> void:
	"""Show player's own active listings"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		add_system_message("[Error] Not logged in to Ashbane.")
		return

	if not TradingManager:
		add_system_message("[Error] Trading system not available.")
		return

	var all_listings = TradingManager.get_active_listings()
	var my_user_id = AshbaneAuth.user_id

	var my_listings = []
	for listing in all_listings:
		var seller = listing.get("seller", {})
		if seller.get("user_id", -1) == my_user_id:
			my_listings.append(listing)

	if my_listings.is_empty():
		add_system_message("You have no active listings.")
		return

	add_system_message("=== Your Active Listings ===")
	for listing in my_listings:
		var listing_id = listing.get("listing_id", 0)
		var item = listing.get("item", {})
		var item_name = item.get("item_name", "Unknown")
		var price = listing.get("price_gold", 0)
		add_system_message("  [%d] %s - %dg" % [listing_id, item_name, price])
	add_system_message("Use /cancel <listing_id> to remove a listing")

func _cmd_cancel_listing(args: Array) -> void:
	"""Cancel an active listing"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		add_system_message("[Error] Not logged in to Ashbane.")
		return

	if args.is_empty():
		add_system_message("Usage: /cancel <listing_id>")
		add_system_message("Use /mylistings to see your active listings.")
		return

	if not args[0].is_valid_int():
		add_system_message("[Error] Listing ID must be a number.")
		return

	var listing_id = int(args[0])

	# Connect to response
	if not TradingManager.listing_cancelled.is_connected(_on_listing_cancelled):
		TradingManager.listing_cancelled.connect(_on_listing_cancelled, CONNECT_ONE_SHOT)
	if not TradingManager.trading_error.is_connected(_on_cancel_error):
		TradingManager.trading_error.connect(_on_cancel_error, CONNECT_ONE_SHOT)

	add_system_message("Cancelling listing...")
	TradingManager.cancel_listing(listing_id)

func _on_listing_cancelled() -> void:
	if TradingManager.trading_error.is_connected(_on_cancel_error):
		TradingManager.trading_error.disconnect(_on_cancel_error)
	add_system_message("[Trade] Listing cancelled.")

func _on_cancel_error(error: String) -> void:
	if TradingManager.listing_cancelled.is_connected(_on_listing_cancelled):
		TradingManager.listing_cancelled.disconnect(_on_listing_cancelled)
	add_system_message("[Error] %s" % error)

func _cmd_trade(args: Array) -> void:
	"""Request a trade with another player"""
	if args.is_empty():
		add_system_message("Usage: /trade <player name>")
		add_system_message("Must be within 5 tiles to trade.")
		return

	if not TradeWindowUI:
		add_system_message("[Error] Trade system not available.")
		return

	var target_name = " ".join(args)
	var target_id = _find_player_by_name(target_name)

	if target_id == -1:
		add_system_message("[Error] Player '%s' not found." % target_name)
		add_system_message("Use /players to see online players.")
		return

	var result = TradeWindowUI.request_trade(target_id)
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

func _cmd_accept_trade() -> void:
	"""Accept a pending trade request"""
	if not TradeWindowUI:
		add_system_message("[Error] Trade system not available.")
		return

	if not TradeWindowUI.has_pending_request():
		add_system_message("[Error] No pending trade request.")
		return

	var result = TradeWindowUI.accept_trade()
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

func _cmd_decline_trade() -> void:
	"""Decline a pending trade request"""
	if not TradeWindowUI:
		add_system_message("[Error] Trade system not available.")
		return

	if not TradeWindowUI.has_pending_request():
		add_system_message("[Error] No pending trade request.")
		return

	var result = TradeWindowUI.decline_trade()
	if result.success:
		add_system_message(result.message)
	else:
		add_system_message("[Error] %s" % result.message)

# ═══════════════════════════════════════════════════════════════════════════
# HELP COMMAND
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_help() -> void:
	add_system_message("=== General Commands ===")
	add_system_message("/players - List online players")
	add_system_message("/playtest - Toggle debug messages in chat")
	add_system_message("=== Trading Commands ===")
	add_system_message("/trade <player> - Request direct trade")
	add_system_message("/accepttrade - Accept trade request")
	add_system_message("/declinetrade - Decline trade request")
	add_system_message("/sell list - Show your forged items")
	add_system_message("/sell <id> <price> [msg] - List item for sale")
	add_system_message("/listings - View recently advertised (Tab)")
	add_system_message("/mylistings - View your active listings")
	add_system_message("/cancel <id> - Cancel a listing")
	add_system_message("=== Duel Commands ===")
	add_system_message("/duel <player> - Challenge to a duel")
	add_system_message("/acceptduel - Accept duel request")
	add_system_message("/declineduel - Decline duel request")
	add_system_message("=== Group Commands ===")
	add_system_message("/invite <player> - Invite to group")
	add_system_message("/accept - Accept group invite")
	add_system_message("/decline - Decline group invite")
	add_system_message("/leave - Leave current group")
	add_system_message("/kick <player> - Kick from group (leader)")
	add_system_message("/promote <player> - Promote to leader")
	add_system_message("/disband - Disband group (leader)")
	add_system_message("/group - Show group info")
	add_system_message("=== Admin Commands ===")
	add_system_message("/tp <x> <y> - Teleport to coordinates")
	add_system_message("/tp hub|zone1|campfire - Cross-scene teleport")
	add_system_message("/tp forge|stash|trader - Hub locations")
	add_system_message("/tp tunnel|west|east|castle - Zone 1 POIs")
	add_system_message("/accounts - List all accounts")
	add_system_message("/select <username> - Select account to edit")
	add_system_message("/info - Show selected account details")
	add_system_message("/setpos <x> <y> - Set DB position")
	add_system_message("/resetpos - Reset DB to campfire (0,0)")
	add_system_message("/setgold <amount> - Set gold")
	add_system_message("/setlevel <1-30> - Set level")
	add_system_message("/setstats <str> <agi> <vit> <luck>")
	add_system_message("/ban /unban - Toggle ban")
	add_system_message("/forceoffline - Fix stuck login")
	add_system_message("/delete - Delete selected account")

# ═══════════════════════════════════════════════════════════════════════════
# PLAYTEST/DEBUG COMMAND
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_playtest(args: Array) -> void:
	"""Toggle playtest mode or configure categories"""
	if args.is_empty():
		# Toggle playtest mode
		LogManager.toggle_playtest_mode()
		return

	var subcommand = args[0].to_lower()
	match subcommand:
		"on":
			LogManager.enable_playtest_mode()
		"off":
			LogManager.disable_playtest_mode()
		"add":
			if args.size() > 1:
				LogManager.add_playtest_category(args[1])
			else:
				add_system_message("Usage: /playtest add <category>")
		"remove":
			if args.size() > 1:
				LogManager.remove_playtest_category(args[1])
			else:
				add_system_message("Usage: /playtest remove <category>")
		"categories":
			add_system_message("Available: loot, combat, network, player, enemy, inventory, quest")
			add_system_message("Currently watching: %s" % ", ".join(LogManager.playtest_categories))
		"status":
			var status = "ON" if LogManager.playtest_mode else "OFF"
			add_system_message("Playtest mode: %s" % status)
			add_system_message("Watching: %s" % ", ".join(LogManager.playtest_categories))
		_:
			add_system_message("Usage: /playtest [on|off|add|remove|categories|status]")

func _cmd_accounts() -> void:
	if not DatabaseManager or not DatabaseManager.is_initialized:
		add_system_message("[Error] Database not initialized. Host a game first.")
		return

	add_system_message("=== Accounts ===")
	for username in DatabaseManager.players_data.keys():
		var data = DatabaseManager.players_data[username]
		var level = data.get("level", 1)
		var online = " [ONLINE]" if data.get("is_online", false) else ""
		add_system_message("  %s (Lv.%d)%s" % [username, level, online])
	add_system_message("Total: %d accounts" % DatabaseManager.players_data.size())

func _cmd_select(args: Array) -> void:
	if args.is_empty():
		add_system_message("[Error] Usage: /select <username>")
		return

	var username = args[0]
	if not DatabaseManager or not DatabaseManager.players_data.has(username):
		add_system_message("[Error] Account not found: %s" % username)
		return

	_selected_account = username
	add_system_message("Selected: %s" % username)
	_cmd_info()

func _cmd_info() -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return

	if not DatabaseManager.players_data.has(_selected_account):
		add_system_message("[Error] Account not found: %s" % _selected_account)
		_selected_account = ""
		return

	var data = DatabaseManager.players_data[_selected_account]
	add_system_message("=== %s ===" % _selected_account)
	add_system_message("Level: %d | Gold: %d" % [data.get("level", 1), data.get("gold", 0)])
	add_system_message("Stats: STR %d | AGI %d | DEX %d | INT %d | WIS %d | VIT %d" % [
		data.get("strength", 10), data.get("agility", 10),
		data.get("dexterity", 10), data.get("intelligence", 10),
		data.get("wisdom", 10), data.get("vitality", 10)
	])
	add_system_message("Position: (%.0f, %.0f)" % [data.get("position_x", 0), data.get("position_y", 0)])
	add_system_message("Status: %s%s" % [
		"ONLINE" if data.get("is_online", false) else "Offline",
		" | BANNED" if data.get("is_banned", false) else ""
	])

func _cmd_setpos(args: Array) -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return
	if args.size() < 2:
		add_system_message("[Error] Usage: /setpos <x> <y>")
		return

	# Validate numeric input
	if not args[0].is_valid_float() or not args[1].is_valid_float():
		add_system_message("[Error] Position must be numeric values")
		return

	var x = clampf(float(args[0]), MIN_POSITION, MAX_POSITION)
	var y = clampf(float(args[1]), MIN_POSITION, MAX_POSITION)
	DatabaseManager.players_data[_selected_account]["position_x"] = x
	DatabaseManager.players_data[_selected_account]["position_y"] = y
	DatabaseManager.save_database()
	add_system_message("Set %s position to (%.0f, %.0f)" % [_selected_account, x, y])

func _cmd_resetpos() -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return

	DatabaseManager.players_data[_selected_account]["position_x"] = 0.0
	DatabaseManager.players_data[_selected_account]["position_y"] = 0.0
	DatabaseManager.save_database()
	add_system_message("Reset %s position to campfire spawn" % _selected_account)

func _cmd_setgold(args: Array) -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return
	if args.is_empty():
		add_system_message("[Error] Usage: /setgold <amount>")
		return

	# Validate numeric input
	if not args[0].is_valid_int():
		add_system_message("[Error] Gold amount must be a whole number")
		return

	var amount = clampi(int(args[0]), MIN_GOLD, MAX_GOLD)
	DatabaseManager.players_data[_selected_account]["gold"] = amount
	DatabaseManager.save_database()
	add_system_message("Set %s gold to %d" % [_selected_account, amount])

func _cmd_setlevel(args: Array) -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return
	if args.is_empty():
		add_system_message("[Error] Usage: /setlevel <level>")
		return

	# Validate numeric input
	if not args[0].is_valid_int():
		add_system_message("[Error] Level must be a whole number")
		return

	var level = clampi(int(args[0]), MIN_LEVEL, MAX_LEVEL)
	DatabaseManager.players_data[_selected_account]["level"] = level
	DatabaseManager.save_database()
	add_system_message("Set %s level to %d" % [_selected_account, level])

func _cmd_setstats(args: Array) -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return
	if args.size() < 6:
		add_system_message("[Error] Usage: /setstats <str> <agi> <dex> <int> <wis> <vit>")
		return

	# Validate numeric inputs
	for i in range(6):
		if not args[i].is_valid_int():
			add_system_message("[Error] All stats must be whole numbers")
			return

	var data = DatabaseManager.players_data[_selected_account]
	data["strength"] = clampi(int(args[0]), MIN_STAT, MAX_STAT)
	data["agility"] = clampi(int(args[1]), MIN_STAT, MAX_STAT)
	data["dexterity"] = clampi(int(args[2]), MIN_STAT, MAX_STAT)
	data["intelligence"] = clampi(int(args[3]), MIN_STAT, MAX_STAT)
	data["wisdom"] = clampi(int(args[4]), MIN_STAT, MAX_STAT)
	data["vitality"] = clampi(int(args[5]), MIN_STAT, MAX_STAT)
	DatabaseManager.save_database()
	add_system_message("Updated %s stats (clamped to %d-%d)" % [_selected_account, MIN_STAT, MAX_STAT])

func _cmd_ban(ban: bool) -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return

	DatabaseManager.players_data[_selected_account]["is_banned"] = ban
	DatabaseManager.save_database()
	add_system_message("%s account: %s" % ["Banned" if ban else "Unbanned", _selected_account])

func _cmd_force_offline() -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return

	DatabaseManager.players_data[_selected_account]["is_online"] = false
	DatabaseManager.save_database()
	add_system_message("Forced %s offline" % _selected_account)

func _cmd_delete() -> void:
	if _selected_account.is_empty():
		add_system_message("[Error] No account selected. Use /select <username>")
		return

	var username = _selected_account
	DatabaseManager.players_data.erase(username)
	DatabaseManager.save_database()
	_selected_account = ""
	add_system_message("Deleted account: %s" % username)

func _cmd_teleport(args: Array) -> void:
	"""Teleport local player to specified coordinates or named locations
	Supports cross-scene teleportation between Zone 1 and Trading Hub
	"""
	# Find local player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		add_system_message("[Error] No player found.")
		return

	# Detect current scene
	var current_scene = get_tree().current_scene
	var scene_name = current_scene.name if current_scene else "unknown"
	var in_hub = scene_name == "TradingHub"

	# Handle named locations
	if args.size() == 1:
		var location = args[0].to_lower()

		# === CROSS-SCENE TELEPORTS (work from any scene) ===
		match location:
			"hub", "trade", "trading", "passage":
				# Teleport to Trading Hub (scene change if needed)
				if in_hub:
					# Already in hub - go to center
					player.global_position = Vector2(0, -2500)
					add_system_message("Teleported to Hub Center (0, -2500)")
				else:
					# Load the Trading Hub scene
					add_system_message("Entering Trading Hub...")
					var hub_manager = get_node_or_null("/root/TradingHubManager")
					if hub_manager:
						hub_manager.set_player_origin_chunk(0)
						hub_manager.transition_to_hub()
					else:
						add_system_message("[Error] TradingHubManager not found")
				return

			"zone1", "world", "dreadland", "overworld":
				# Return to Zone 1 (scene change if needed)
				if in_hub:
					add_system_message("Returning to Zone 1...")
					var hub_manager = get_node_or_null("/root/TradingHubManager")
					if hub_manager:
						hub_manager.set_player_in_hub(false)
						hub_manager.transition_to_zone1()
					else:
						get_tree().change_scene_to_file("res://main.tscn")
				else:
					# Already in Zone 1 - go to campfire
					player.global_position = Vector2(0, 0)
					add_system_message("Teleported to Zone 1 Campfire (0, 0)")
				return

			"campfire", "camp", "fire", "spawn", "home":
				# Campfire - works in both scenes
				if in_hub:
					# Hub central hearth (TestHub layout)
					player.global_position = Vector2(0, 0)
					add_system_message("Teleported to Hub Hearth (0, 0)")
				else:
					# Zone 1 campfire at world origin
					player.global_position = Vector2(0, 0)
					add_system_message("Teleported to Campfire (0, 0)")
				return

		# === TRADING HUB LOCATIONS ===
		# These work from anywhere - if in Zone 1, transition to hub first
		# TradingHub layout: hearth at (0,0), south exit Y>6800, zone2 grass Y<-2800
		var hub_locations = {
			"forge": Vector2(150, -100),
			"smith": Vector2(150, -100),
			"blacksmith": Vector2(150, -100),
			"stash": Vector2(-300, -200),
			"storage": Vector2(-300, -200),
			"bank": Vector2(-300, -200),
			"trader": Vector2(300, -200),
			"vendor": Vector2(300, -200),
			"shop": Vector2(300, -200),
			"merchant": Vector2(300, -200),
			"hubfire": Vector2(0, 0),
			"firepit": Vector2(0, 0),
			"center": Vector2(0, 0),
			"hearth": Vector2(0, 0),
			"hubsouth": Vector2(0, 200),
			"southentry": Vector2(0, 200),
			"entry": Vector2(0, 200),
			"hubwest": Vector2(-200, 0),
			"westentry": Vector2(-200, 0),
			"hubeast": Vector2(200, 0),
			"eastentry": Vector2(200, 0),
			"hubnorth": Vector2(0, -3500),
			"zone2": Vector2(0, -3500),
			"grass": Vector2(0, -3500),
			"outdoor": Vector2(0, -3500),
			"cavemouth": Vector2(0, -2400),
			"mouth": Vector2(0, -2400),
			"cliff": Vector2(0, -2400),
			"southexit": Vector2(0, 6500),
			"westexit": Vector2(-5000, 2700),
			"eastexit": Vector2(5000, 2700),
		}

		if hub_locations.has(location):
			if in_hub:
				player.global_position = hub_locations[location]
				add_system_message("Teleported to %s" % location)
			else:
				# Transition to hub - position will be set by spawn system
				add_system_message("Entering Trading Hub...")
				var hub_manager = get_node_or_null("/root/TradingHubManager")
				if hub_manager:
					hub_manager.set_player_origin_chunk(0)
					hub_manager.transition_to_hub()
				else:
					add_system_message("[Error] TradingHubManager not found")
			return

		# === ZONE 1 LOCATIONS (only work when in Zone 1) ===
		if not in_hub:
			match location:
				"tunnel":
					# Tunnel entrance at chunk 0 (north edge, center)
					player.global_position = Vector2(4000, -3950)
					add_system_message("Teleported to Tunnel Entrance (4000, -3950)")
					return
				"west", "w":
					# West chunk center (chunk -1)
					player.global_position = Vector2(-4000, 0)
					add_system_message("Teleported to West (-4000, 0)")
					return
				"east", "e":
					# East chunk center (chunk 1)
					player.global_position = Vector2(12000, 0)
					add_system_message("Teleported to East (12000, 0)")
					return
				"castle", "end":
					# End of main path (castle position)
					player.global_position = Vector2(7600, 0)
					add_system_message("Teleported to Castle (7600, 0)")
					return
				"north", "n":
					# North edge of world
					player.global_position = Vector2(player.global_position.x, -3900)
					add_system_message("Teleported to North edge (Y: -3900)")
					return
				"south", "s":
					# South edge of world
					player.global_position = Vector2(player.global_position.x, 3900)
					add_system_message("Teleported to South edge (Y: 3900)")
					return

		# Unknown location
		if location.is_valid_float():
			add_system_message("[Error] Usage: /tp <x> <y>")
			_show_tp_locations(in_hub)
			return
		add_system_message("[Error] Unknown location: %s" % location)
		_show_tp_locations(in_hub)
		return

	# Require x and y coordinates
	if args.size() < 2:
		add_system_message("Usage: /tp <x> <y>  OR  /tp <location>")
		_show_tp_locations(in_hub)
		add_system_message("Current: (%.0f, %.0f) in %s" % [player.global_position.x, player.global_position.y, "Hub" if in_hub else "Zone 1"])
		return

	# Validate numeric input
	if not args[0].is_valid_float() or not args[1].is_valid_float():
		add_system_message("[Error] Coordinates must be numeric values")
		return

	var x = clampf(float(args[0]), MIN_POSITION, MAX_POSITION)
	var y = clampf(float(args[1]), MIN_POSITION, MAX_POSITION)

	player.global_position = Vector2(x, y)
	add_system_message("Teleported to (%.0f, %.0f)" % [x, y])

func _show_tp_locations(in_hub: bool) -> void:
	"""Show available teleport locations based on current scene"""
	add_system_message("=== Anywhere ===")
	add_system_message("  hub, zone1, campfire")
	add_system_message("  forge, stash, trader, hearth")
	if in_hub:
		add_system_message("=== Hub Only ===")
		add_system_message("  zone2/grass, cavemouth")
		add_system_message("  southexit, westexit, eastexit")
	else:
		add_system_message("=== Zone 1 Only ===")
		add_system_message("  tunnel, west, east, castle, north, south")

# ═══════════════════════════════════════════════════════════════════════════
# HOVER FADE EFFECT - Background fades, text stays visible (floating effect)
# ═══════════════════════════════════════════════════════════════════════════

var _fade_tween: Tween = null
var _is_active: bool = false  # Track current state

func _on_chat_mouse_entered() -> void:
	"""Fade in backgrounds when mouse hovers over chat"""
	_fade_to_active()

func _on_chat_mouse_exited() -> void:
	"""Fade out backgrounds when mouse leaves chat (unless input is focused)"""
	if not is_input_focused:
		_fade_to_ghosted()

func _fade_to_active() -> void:
	"""Show full UI - backgrounds visible, all elements shown"""
	if _is_active:
		return
	_is_active = true

	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)

	# Fade in panel background
	_fade_tween.tween_property(panel_style, "bg_color:a", 0.95, 0.2)
	_fade_tween.tween_property(panel_style, "border_color:a", 1.0, 0.2)
	_fade_tween.tween_property(panel_style, "shadow_size", 8, 0.2)
	_fade_tween.tween_property(panel_style, "shadow_color:a", 0.6, 0.2)

	# Fade in scroll container background
	_fade_tween.tween_property(scroll_style, "bg_color:a", 1.0, 0.2)

	# Show header and input row
	_fade_tween.tween_property(header_label, "modulate:a", 1.0, 0.2)
	_fade_tween.tween_property(input_row, "modulate:a", 1.0, 0.2)

func _fade_to_ghosted() -> void:
	"""Ghost UI - backgrounds nearly invisible, text floats on screen"""
	if not _is_active:
		return
	_is_active = false

	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)

	# Fade out panel background to nearly invisible
	_fade_tween.tween_property(panel_style, "bg_color:a", 0.0, 0.3)
	_fade_tween.tween_property(panel_style, "border_color:a", 0.0, 0.3)
	_fade_tween.tween_property(panel_style, "shadow_size", 0, 0.3)
	_fade_tween.tween_property(panel_style, "shadow_color:a", 0.0, 0.3)

	# Fade out scroll container background completely
	_fade_tween.tween_property(scroll_style, "bg_color:a", 0.0, 0.3)

	# Hide header and input row
	_fade_tween.tween_property(header_label, "modulate:a", 0.0, 0.3)
	_fade_tween.tween_property(input_row, "modulate:a", 0.0, 0.3)
