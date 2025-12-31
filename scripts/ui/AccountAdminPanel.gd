extends CanvasLayer
class_name AccountAdminPanel

## Account Admin Panel - Debug tool for managing player accounts
## Press F2 to toggle (only works when DatabaseManager is initialized)

var panel: PanelContainer
var account_list: ItemList
var info_label: RichTextLabel
var command_input: LineEdit
var output_label: RichTextLabel

var selected_username: String = ""
var is_visible: bool = false

func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return

	layer = 100
	visible = false
	_create_ui()

func _input(event: InputEvent) -> void:
	# Block mouse scroll when panel is visible (prevent camera zoom)
	if is_visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo:
		# F2 toggles panel (dev builds only)
		if event.keycode == KEY_F2:
			if not (OS.has_feature("editor") or OS.is_debug_build()):
				return
			toggle_panel()
			get_viewport().set_input_as_handled()
			return

		# Only handle other keys when panel is visible
		if not is_visible:
			return

		# ESC closes panel
		if event.keycode == KEY_ESCAPE:
			toggle_panel()
			get_viewport().set_input_as_handled()
			return

		# Enter submits command when command input is focused
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if command_input and command_input.has_focus():
				_on_command_submitted(command_input.text)
				get_viewport().set_input_as_handled()
				return

func toggle_panel() -> void:
	is_visible = not is_visible
	visible = is_visible

	if is_visible:
		_refresh_account_list()
		command_input.grab_focus()

func _create_ui() -> void:
	# Main panel
	panel = PanelContainer.new()
	panel.name = "AdminPanel"

	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.4, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(15)
	panel.add_theme_stylebox_override("panel", style)

	# Position at top-left
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(700, 500)
	panel.position = Vector2(20, 20)  # Top-left with small margin

	add_child(panel)

	# Main layout
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "Account Admin Panel (F2 to close)"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	# Horizontal split: account list | info panel
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hbox)

	# Left side: Account list
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.custom_minimum_size.x = 250
	hbox.add_child(left_vbox)

	var list_label = Label.new()
	list_label.text = "Accounts:"
	list_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	left_vbox.add_child(list_label)

	account_list = ItemList.new()
	account_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	account_list.add_theme_color_override("font_color", Color.WHITE)
	account_list.item_selected.connect(_on_account_selected)
	left_vbox.add_child(account_list)

	# Buttons under list
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 5)
	left_vbox.add_child(btn_hbox)

	var refresh_btn = Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_account_list)
	btn_hbox.add_child(refresh_btn)

	var delete_btn = Button.new()
	delete_btn.text = "Delete"
	delete_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	delete_btn.pressed.connect(_delete_selected_account)
	btn_hbox.add_child(delete_btn)

	# Right side: Info panel
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right_vbox)

	var info_title = Label.new()
	info_title.text = "Account Details:"
	info_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	right_vbox.add_child(info_title)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_label.add_theme_color_override("default_color", Color.WHITE)
	right_vbox.add_child(info_label)

	# Command section
	var cmd_label = Label.new()
	cmd_label.text = "Commands:"
	cmd_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	main_vbox.add_child(cmd_label)

	command_input = LineEdit.new()
	command_input.placeholder_text = "Type command: help, setpos <x> <y>, setgold <amount>, setlevel <level>, resetpos"
	command_input.text_submitted.connect(_on_command_submitted)
	main_vbox.add_child(command_input)

	# Output
	output_label = RichTextLabel.new()
	output_label.bbcode_enabled = true
	output_label.custom_minimum_size.y = 80
	output_label.add_theme_color_override("default_color", Color(0.7, 0.9, 0.7))
	main_vbox.add_child(output_label)

func _refresh_account_list() -> void:
	account_list.clear()
	info_label.text = ""
	selected_username = ""

	# Admin panel only works on server (security - clients shouldn't access DB directly)
	if not NetworkManager.is_server():
		_log("[color=yellow]Admin panel is server-only.[/color]\n\nTo manage accounts:\n1. SSH into your VPS\n2. Or host locally and use F2")
		return

	if not DatabaseManager or not DatabaseManager.is_initialized:
		_log("[color=red]Database not initialized. Host a game first.[/color]")
		return

	for username in DatabaseManager.players_data.keys():
		var data = DatabaseManager.players_data[username]
		var level = data.get("level", 1)
		var is_online = data.get("is_online", false)
		var status = " [ONLINE]" if is_online else ""
		account_list.add_item("%s (Lv.%d)%s" % [username, level, status])
		account_list.set_item_metadata(account_list.item_count - 1, username)

	_log("Loaded %d accounts" % account_list.item_count)

func _on_account_selected(index: int) -> void:
	selected_username = account_list.get_item_metadata(index)
	_show_account_info(selected_username)

func _show_account_info(username: String) -> void:
	if not DatabaseManager.players_data.has(username):
		info_label.text = "Account not found"
		return

	var data = DatabaseManager.players_data[username]

	var text = "[b]Username:[/b] %s\n" % username
	text += "[b]Character:[/b] %s\n" % data.get("character_name", username)
	text += "[b]Level:[/b] %d\n" % data.get("level", 1)
	text += "[b]XP:[/b] %d\n" % data.get("xp", 0)
	text += "[b]Gold:[/b] %d\n" % data.get("gold", 0)
	text += "\n[b]Stats:[/b]\n"
	text += "  STR: %d  AGI: %d  DEX: %d\n" % [data.get("strength", 10), data.get("agility", 10), data.get("dexterity", 10)]
	text += "  INT: %d  WIS: %d  VIT: %d\n" % [data.get("intelligence", 10), data.get("wisdom", 10), data.get("vitality", 10)]
	text += "\n[b]Position:[/b] (%.0f, %.0f)\n" % [data.get("position_x", 0), data.get("position_y", 0)]
	text += "[b]HP:[/b] %.0f / %.0f\n" % [data.get("current_hp", 100), data.get("max_hp", 100)]

	var playtime = data.get("total_playtime_seconds", 0)
	var hours = int(playtime / 3600)
	var mins = int((playtime - hours * 3600) / 60)
	text += "[b]Playtime:[/b] %dh %dm\n" % [hours, mins]

	text += "\n[b]Status:[/b] %s\n" % ("ONLINE" if data.get("is_online", false) else "Offline")
	text += "[b]Banned:[/b] %s\n" % ("YES" if data.get("is_banned", false) else "No")

	# Last login
	var last_login = data.get("last_login", 0)
	if last_login > 0:
		var dt = Time.get_datetime_dict_from_unix_time(last_login)
		text += "[b]Last Login:[/b] %04d-%02d-%02d %02d:%02d\n" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

	info_label.text = text

func _on_command_submitted(cmd: String) -> void:
	print("[AdminPanel] Command received: '%s'" % cmd)  # Debug

	var parts = cmd.strip_edges().split(" ", false)
	if parts.is_empty():
		command_input.clear()
		return

	var command = parts[0].to_lower()
	var args = parts.slice(1)

	command_input.clear()
	command_input.grab_focus()  # Keep focus on input after command

	match command:
		"help":
			_show_help()
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
			_delete_selected_account()
		_:
			_log("[color=red]Unknown command: %s[/color]" % command)

func _show_help() -> void:
	var help_text = """[color=yellow]Available Commands:[/color]
[b]help[/b] - Show this help
[b]setpos <x> <y>[/b] - Set position (e.g., setpos 4000 0)
[b]resetpos[/b] - Reset to campfire spawn (0, 0)
[b]setgold <amount>[/b] - Set gold amount
[b]setlevel <level>[/b] - Set character level
[b]setstats <str> <agi> <dex> <int> <wis> <vit>[/b] - Set all stats
[b]ban[/b] / [b]unban[/b] - Toggle ban status
[b]forceoffline[/b] - Force account offline (fix stuck logins)
[b]delete[/b] - Delete selected account"""
	_log(help_text)

func _cmd_setpos(args: Array) -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return
	if args.size() < 2:
		_log("[color=red]Usage: setpos <x> <y>[/color]")
		return

	var x = float(args[0])
	var y = float(args[1])

	DatabaseManager.players_data[selected_username]["position_x"] = x
	DatabaseManager.players_data[selected_username]["position_y"] = y
	DatabaseManager.save_database()

	_log("[color=green]Set %s position to (%.0f, %.0f)[/color]" % [selected_username, x, y])
	_show_account_info(selected_username)

func _cmd_resetpos() -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return

	DatabaseManager.players_data[selected_username]["position_x"] = 0.0
	DatabaseManager.players_data[selected_username]["position_y"] = 0.0
	DatabaseManager.save_database()

	_log("[color=green]Reset %s position to campfire spawn[/color]" % selected_username)
	_show_account_info(selected_username)

func _cmd_setgold(args: Array) -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return
	if args.is_empty():
		_log("[color=red]Usage: setgold <amount>[/color]")
		return

	var amount = int(args[0])
	DatabaseManager.players_data[selected_username]["gold"] = amount
	DatabaseManager.save_database()

	_log("[color=green]Set %s gold to %d[/color]" % [selected_username, amount])
	_show_account_info(selected_username)

func _cmd_setlevel(args: Array) -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return
	if args.is_empty():
		_log("[color=red]Usage: setlevel <level>[/color]")
		return

	var level = clampi(int(args[0]), 1, 30)
	DatabaseManager.players_data[selected_username]["level"] = level
	DatabaseManager.save_database()

	_log("[color=green]Set %s level to %d[/color]" % [selected_username, level])
	_show_account_info(selected_username)

func _cmd_setstats(args: Array) -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return
	if args.size() < 6:
		_log("[color=red]Usage: setstats <str> <agi> <dex> <int> <wis> <vit>[/color]")
		return

	var data = DatabaseManager.players_data[selected_username]
	data["strength"] = int(args[0])
	data["agility"] = int(args[1])
	data["dexterity"] = int(args[2])
	data["intelligence"] = int(args[3])
	data["wisdom"] = int(args[4])
	data["vitality"] = int(args[5])
	DatabaseManager.save_database()

	_log("[color=green]Updated %s stats[/color]" % selected_username)
	_show_account_info(selected_username)

func _cmd_ban(ban: bool) -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return

	DatabaseManager.players_data[selected_username]["is_banned"] = ban
	DatabaseManager.save_database()

	if ban:
		_log("[color=orange]Banned account: %s[/color]" % selected_username)
	else:
		_log("[color=green]Unbanned account: %s[/color]" % selected_username)
	_show_account_info(selected_username)

func _cmd_force_offline() -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return

	DatabaseManager.players_data[selected_username]["is_online"] = false
	DatabaseManager.save_database()

	_log("[color=green]Forced %s offline[/color]" % selected_username)
	_refresh_account_list()

func _delete_selected_account() -> void:
	if selected_username.is_empty():
		_log("[color=red]Select an account first[/color]")
		return

	var username = selected_username
	DatabaseManager.players_data.erase(username)
	DatabaseManager.save_database()

	_log("[color=orange]Deleted account: %s[/color]" % username)
	_refresh_account_list()

func _log(text: String) -> void:
	output_label.text = text
