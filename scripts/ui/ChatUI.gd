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

func _input(event: InputEvent) -> void:
	# Don't process input if admin panel is open
	var admin_panel = get_node_or_null("/root/AccountAdmin")
	if admin_panel and admin_panel.is_visible:
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

	# Start faded out
	chat_panel.modulate.a = 0.3

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
	header.add_theme_font_size_override("font_size", 14)
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
	input_field.add_theme_font_size_override("font_size", 14)

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
		_fade_to(1.0)  # Show fully when typing

func unfocus_input() -> void:
	"""Remove focus from chat input"""
	if input_field:
		input_field.release_focus()
		is_input_focused = false
		_fade_to(0.3)  # Fade back out when done typing

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
	msg_label.add_theme_font_size_override("normal_font_size", 14)

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
	msg_label.add_theme_font_size_override("normal_font_size", 13)

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
	"forceoffline", "delete"
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
	"""List all connected players - useful for /invite"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		add_system_message("[Error] Not connected.")
		return

	var players = network_manager.connected_players
	if players.is_empty():
		add_system_message("No players connected.")
		return

	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else -1
	add_system_message("=== Online Players (%d) ===" % players.size())
	for peer_id in players:
		var player_info = players[peer_id]
		var name = player_info.get("name", "Unknown")
		var is_you = peer_id == my_id
		if is_you:
			add_system_message("  %s (You)" % name)
		else:
			add_system_message("  %s" % name)

# ═══════════════════════════════════════════════════════════════════════════
# HELP COMMAND
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_help() -> void:
	add_system_message("=== General Commands ===")
	add_system_message("/players - List online players")
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
	add_system_message("/accounts - List all accounts")
	add_system_message("/select <username> - Select account to edit")
	add_system_message("/info - Show selected account details")
	add_system_message("/setpos <x> <y> - Set position")
	add_system_message("/resetpos - Reset to campfire (0,0)")
	add_system_message("/setgold <amount> - Set gold")
	add_system_message("/setlevel <1-30> - Set level")
	add_system_message("/setstats <str> <agi> <vit> <luck>")
	add_system_message("/ban /unban - Toggle ban")
	add_system_message("/forceoffline - Fix stuck login")
	add_system_message("/delete - Delete selected account")

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
	add_system_message("Stats: STR %d | AGI %d | VIT %d | LUCK %d" % [
		data.get("strength", 10), data.get("agility", 10),
		data.get("vitality", 10), data.get("luck", 10)
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
	if args.size() < 4:
		add_system_message("[Error] Usage: /setstats <str> <agi> <vit> <luck>")
		return

	# Validate numeric inputs
	for i in range(4):
		if not args[i].is_valid_int():
			add_system_message("[Error] All stats must be whole numbers")
			return

	var data = DatabaseManager.players_data[_selected_account]
	data["strength"] = clampi(int(args[0]), MIN_STAT, MAX_STAT)
	data["agility"] = clampi(int(args[1]), MIN_STAT, MAX_STAT)
	data["vitality"] = clampi(int(args[2]), MIN_STAT, MAX_STAT)
	data["luck"] = clampi(int(args[3]), MIN_STAT, MAX_STAT)
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

# ═══════════════════════════════════════════════════════════════════════════
# HOVER FADE EFFECT
# ═══════════════════════════════════════════════════════════════════════════

var _fade_tween: Tween = null

func _on_chat_mouse_entered() -> void:
	"""Fade in when mouse hovers over chat"""
	_fade_to(1.0)

func _on_chat_mouse_exited() -> void:
	"""Fade out when mouse leaves chat (unless input is focused)"""
	if not is_input_focused:
		_fade_to(0.3)

func _fade_to(target_alpha: float) -> void:
	"""Smoothly fade chat panel to target alpha"""
	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(chat_panel, "modulate:a", target_alpha, 0.2)
