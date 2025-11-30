extends Node
## ServerRunner.gd - Handles dedicated server mode via CLI arguments
##
## Usage:
##   Godot_v4.x.exe --headless -- --server --port 7000
##
## Arguments (after "--"):
##   --server       Start as dedicated server (no local player)
##   --port XXXX    Server port (default: 7000)
##
## Systemd Integration:
##   - Responds to SIGTERM (systemctl stop) with graceful shutdown
##   - Saves all player data before exit
##   - Auto-restarts via systemd Restart=always
##
## CLI Admin Commands (type in console):
##   help              - Show all commands
##   status            - Show server status
##   players           - List online players
##   accounts          - List all accounts
##   kick <name>       - Kick a player
##   ban <name>        - Ban an account
##   unban <name>      - Unban an account
##   setgold <name> <amount> - Set player gold
##   save              - Force save all players
##   stop              - Graceful shutdown

var is_dedicated_server: bool = false
var server_start_time: int = 0
var stdin_thread: Thread = null
var command_queue: Array = []
var command_mutex: Mutex = null

func _ready():
	var args = OS.get_cmdline_user_args()  # Gets args after "--"

	if "--server" in args:
		is_dedicated_server = true
		server_start_time = Time.get_unix_time_from_system()
		print("═══════════════════════════════════════════════════════")
		print("   WASTELAND DEDICATED SERVER")
		print("═══════════════════════════════════════════════════════")
		_start_dedicated_server(args)

func _start_dedicated_server(args: Array):
	# Parse port (default 7000)
	var port = NetworkManager.DEFAULT_PORT
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])

	print("🖥️  Initializing server on port %d..." % port)
	print("   PID: %d" % OS.get_process_id())

	# Initialize database
	if DatabaseManager:
		DatabaseManager.initialize_database()
		print("📀 Database initialized")

	# Start server with no local player (empty player_data = no host player)
	if NetworkManager.host_game(port, {}):
		print("✅ Server started successfully!")
		print("   Version: %s" % NetworkManager.NETWORK_VERSION)
		print("   Port: %d" % port)
		print("   Max Players: %d" % NetworkManager.MAX_PLAYERS)
		print("═══════════════════════════════════════════════════════")
		print("   Type 'help' for admin commands")
		print("   Use 'systemctl stop wasteland' for graceful shutdown")
		print("═══════════════════════════════════════════════════════")

		# Start CLI input thread
		_start_cli_thread()

		# Skip MainMenu, go straight to game world
		await get_tree().process_frame
		get_tree().change_scene_to_file("res://main.tscn")
	else:
		push_error("❌ Failed to start server on port %d" % port)
		get_tree().quit(1)

# ═══════════════════════════════════════════════════════════════════════════
# CLI ADMIN INTERFACE
# ═══════════════════════════════════════════════════════════════════════════

func _start_cli_thread() -> void:
	"""Start background thread to read stdin commands."""
	command_mutex = Mutex.new()
	stdin_thread = Thread.new()
	stdin_thread.start(_stdin_reader_thread)
	print("🎮 CLI admin interface ready")

func _stdin_reader_thread() -> void:
	"""Background thread that reads stdin line by line."""
	while is_dedicated_server:
		var line = OS.read_string_from_stdin().strip_edges()
		if not line.is_empty():
			command_mutex.lock()
			command_queue.append(line)
			command_mutex.unlock()

func _process_cli_commands() -> void:
	"""Process any queued CLI commands (called from main thread)."""
	if command_mutex == null:
		return

	command_mutex.lock()
	var commands = command_queue.duplicate()
	command_queue.clear()
	command_mutex.unlock()

	for cmd in commands:
		_execute_command(cmd)

func _execute_command(input: String) -> void:
	"""Execute a CLI admin command."""
	var parts = input.split(" ", false)
	if parts.is_empty():
		return

	var cmd = parts[0].to_lower()
	var args = parts.slice(1)

	match cmd:
		"help", "?":
			_cmd_help()
		"status":
			_print_server_status()
		"players", "online":
			_cmd_players()
		"accounts", "list":
			_cmd_accounts()
		"kick":
			_cmd_kick(args)
		"ban":
			_cmd_ban(args, true)
		"unban":
			_cmd_ban(args, false)
		"setgold":
			_cmd_setgold(args)
		"setlevel":
			_cmd_setlevel(args)
		"resetpos":
			_cmd_resetpos(args)
		"save":
			_cmd_save()
		"stop", "quit", "exit":
			_graceful_shutdown()
		"broadcast", "say":
			_cmd_broadcast(args)
		"bugs":
			_cmd_bugs(args)
		"clearbug":
			_cmd_clearbug(args)
		_:
			print("❓ Unknown command: %s (type 'help' for commands)" % cmd)

func _cmd_help() -> void:
	print("")
	print("═══════════════════════════════════════════════════════")
	print("   ADMIN COMMANDS")
	print("═══════════════════════════════════════════════════════")
	print("  status              - Show server status")
	print("  players             - List online players")
	print("  accounts            - List all registered accounts")
	print("  kick <name>         - Kick player from server")
	print("  ban <name>          - Ban account (prevents login)")
	print("  unban <name>        - Remove ban from account")
	print("  setgold <name> <n>  - Set player's gold")
	print("  setlevel <name> <n> - Set player's level")
	print("  resetpos <name>     - Reset player to spawn")
	print("  broadcast <msg>     - Send message to all players")
	print("  save                - Force save all players")
	print("  bugs [id]           - List bug reports (or view one)")
	print("  clearbug <id|all>   - Clear bug report(s)")
	print("  stop                - Graceful shutdown")
	print("═══════════════════════════════════════════════════════")
	print("")

func _cmd_players() -> void:
	print("")
	print("📋 Online Players:")
	var count = 0
	for peer_id in NetworkManager.authenticated_players:
		var info = NetworkManager.authenticated_players[peer_id]
		var name = info.get("username", "Unknown")
		var is_guest = info.get("is_guest", false)
		var tag = " (guest)" if is_guest else ""
		print("   [%d] %s%s" % [peer_id, name, tag])
		count += 1
	if count == 0:
		print("   (no players online)")
	print("")

func _cmd_accounts() -> void:
	print("")
	print("📋 Registered Accounts:")
	if not DatabaseManager or not DatabaseManager.is_initialized:
		print("   (database not initialized)")
		return

	var count = 0
	for username in DatabaseManager.players_data.keys():
		var data = DatabaseManager.players_data[username]
		var level = data.get("level", 1)
		var gold = data.get("gold", 0)
		var online = " [ONLINE]" if data.get("is_online", false) else ""
		var banned = " [BANNED]" if data.get("is_banned", false) else ""
		print("   %s - Lv.%d, %dg%s%s" % [username, level, gold, online, banned])
		count += 1
	print("   Total: %d accounts" % count)
	print("")

func _cmd_kick(args: Array) -> void:
	if args.is_empty():
		print("❌ Usage: kick <player_name>")
		return

	var target_name = args[0].to_lower()
	for peer_id in NetworkManager.authenticated_players:
		var info = NetworkManager.authenticated_players[peer_id]
		if info.get("username", "").to_lower() == target_name:
			# Disconnect the peer
			NetworkManager.peer.disconnect_peer(peer_id)
			print("✅ Kicked player: %s (peer %d)" % [info.username, peer_id])
			return

	print("❌ Player not found: %s" % args[0])

func _cmd_ban(args: Array, ban: bool) -> void:
	if args.is_empty():
		print("❌ Usage: %s <account_name>" % ("ban" if ban else "unban"))
		return

	var target = args[0]
	if not DatabaseManager.players_data.has(target):
		print("❌ Account not found: %s" % target)
		return

	DatabaseManager.players_data[target]["is_banned"] = ban
	DatabaseManager.save_database()

	if ban:
		print("🚫 Banned account: %s" % target)
		# Kick if online
		_cmd_kick([target])
	else:
		print("✅ Unbanned account: %s" % target)

func _cmd_setgold(args: Array) -> void:
	if args.size() < 2:
		print("❌ Usage: setgold <account_name> <amount>")
		return

	var target = args[0]
	var amount = int(args[1])

	if not DatabaseManager.players_data.has(target):
		print("❌ Account not found: %s" % target)
		return

	DatabaseManager.players_data[target]["gold"] = amount
	DatabaseManager.save_database()
	print("✅ Set %s gold to %d" % [target, amount])

func _cmd_setlevel(args: Array) -> void:
	if args.size() < 2:
		print("❌ Usage: setlevel <account_name> <level>")
		return

	var target = args[0]
	var level = clampi(int(args[1]), 1, 100)

	if not DatabaseManager.players_data.has(target):
		print("❌ Account not found: %s" % target)
		return

	DatabaseManager.players_data[target]["level"] = level
	DatabaseManager.save_database()
	print("✅ Set %s level to %d" % [target, level])

func _cmd_resetpos(args: Array) -> void:
	if args.is_empty():
		print("❌ Usage: resetpos <account_name>")
		return

	var target = args[0]
	if not DatabaseManager.players_data.has(target):
		print("❌ Account not found: %s" % target)
		return

	DatabaseManager.players_data[target]["position_x"] = 4000.0
	DatabaseManager.players_data[target]["position_y"] = 0.0
	DatabaseManager.save_database()
	print("✅ Reset %s position to spawn (4000, 0)" % target)

func _cmd_broadcast(args: Array) -> void:
	if args.is_empty():
		print("❌ Usage: broadcast <message>")
		return

	var message = " ".join(args)
	# Send as system message via chat
	if NetworkManager.is_server():
		NetworkManager.rpc("receive_chat_broadcast", "[SERVER]", message, 0)
		print("📢 Broadcast: %s" % message)

func _cmd_save() -> void:
	NetworkManager.save_all_players()
	print("💾 Saved all player data")

func _notification(what: int) -> void:
	# Handle graceful shutdown (SIGTERM from systemctl stop, window close, etc.)
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_dedicated_server:
			_graceful_shutdown()

func _graceful_shutdown() -> void:
	"""Save all players and shut down gracefully."""
	print("")
	print("═══════════════════════════════════════════════════════")
	print("   SERVER SHUTTING DOWN")
	print("═══════════════════════════════════════════════════════")

	# Stop the stdin thread
	is_dedicated_server = false  # Signal thread to stop
	if stdin_thread and stdin_thread.is_started():
		# Thread is blocking on stdin, can't wait for it
		# Just let it terminate with the process
		pass

	# Count connected players
	var player_count = NetworkManager.authenticated_players.size()
	print("💾 Saving %d player(s)..." % player_count)

	# Save all connected players
	if NetworkManager.is_server():
		NetworkManager.save_all_players()

	# Calculate uptime
	var uptime = Time.get_unix_time_from_system() - server_start_time
	var hours = int(uptime) / 3600
	var minutes = (int(uptime) % 3600) / 60
	var seconds = int(uptime) % 60
	print("⏱️  Uptime: %02d:%02d:%02d" % [hours, minutes, seconds])

	print("✅ Shutdown complete. Goodbye!")
	print("═══════════════════════════════════════════════════════")

	# Exit cleanly
	get_tree().quit(0)

func _process(_delta):
	if not is_dedicated_server:
		return

	# Process any CLI commands from stdin
	_process_cli_commands()

	var frame = Engine.get_process_frames()

	# Periodic server status (every 60 seconds at 60fps = 3600 frames)
	if frame % 3600 == 0 and frame > 0:
		_print_server_status()

func _print_server_status() -> void:
	"""Print current server status to logs."""
	var player_count = NetworkManager.get_player_count()
	var auth_count = NetworkManager.authenticated_players.size()

	# Calculate uptime
	var uptime = Time.get_unix_time_from_system() - server_start_time
	var hours = int(uptime) / 3600
	var minutes = (int(uptime) % 3600) / 60

	print("📊 [Status] Players: %d | Uptime: %dh %dm" % [auth_count, hours, minutes])

# ═══════════════════════════════════════════════════════════════════════════
# BUG REPORT COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_bugs(args: Array) -> void:
	"""List bug reports or view a specific one."""
	var reports = _load_bug_reports()

	if reports.is_empty():
		print("🐛 No bug reports.")
		return

	# View specific report
	if not args.is_empty():
		var id = int(args[0])
		for report in reports:
			if report.get("id", 0) == id:
				_print_bug_detail(report)
				return
		print("❌ Bug #%d not found" % id)
		return

	# List all reports
	print("")
	print("🐛 Bug Reports (%d total):" % reports.size())
	print("─────────────────────────────────────────────────────")
	for report in reports:
		var id = report.get("id", 0)
		var title = report.get("title", "Untitled")
		var category = report.get("category", "Other")
		var player = report.get("player_name", "Unknown")
		var timestamp = report.get("timestamp", 0)

		var date_str = ""
		if timestamp > 0:
			var dt = Time.get_datetime_dict_from_unix_time(int(timestamp))
			date_str = "%02d/%02d %02d:%02d" % [dt.month, dt.day, dt.hour, dt.minute]

		print("  #%d [%s] %s" % [id, category, title])
		print("      by %s @ %s" % [player, date_str])
	print("─────────────────────────────────────────────────────")
	print("  Use 'bugs <id>' to view details")
	print("")

func _print_bug_detail(report: Dictionary) -> void:
	"""Print detailed bug report."""
	print("")
	print("═══════════════════════════════════════════════════════")
	print("  BUG #%d: %s" % [report.get("id", 0), report.get("title", "Untitled")])
	print("═══════════════════════════════════════════════════════")
	print("  Category:  %s" % report.get("category", "Other"))
	print("  Player:    %s%s" % [report.get("player_name", "Unknown"), " (guest)" if report.get("is_guest", false) else ""])
	print("  Position:  %s" % report.get("position", "unknown"))
	print("  Version:   %s" % report.get("version", "unknown"))

	var timestamp = report.get("timestamp", 0)
	if timestamp > 0:
		var dt = Time.get_datetime_dict_from_unix_time(int(timestamp))
		print("  Time:      %04d-%02d-%02d %02d:%02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second])

	print("───────────────────────────────────────────────────────")
	print("  Description:")
	var desc = report.get("description", "No description")
	for line in desc.split("\n"):
		print("    %s" % line)
	print("═══════════════════════════════════════════════════════")
	print("")

func _cmd_clearbug(args: Array) -> void:
	"""Clear bug report(s)."""
	if args.is_empty():
		print("❌ Usage: clearbug <id> or clearbug all")
		return

	var reports = _load_bug_reports()

	if args[0].to_lower() == "all":
		_save_bug_reports([])
		print("🗑️ Cleared all %d bug reports" % reports.size())
		return

	var id = int(args[0])
	var new_reports: Array = []
	var found = false
	for report in reports:
		if report.get("id", 0) == id:
			found = true
		else:
			new_reports.append(report)

	if found:
		_save_bug_reports(new_reports)
		print("🗑️ Deleted bug #%d" % id)
	else:
		print("❌ Bug #%d not found" % id)

func _load_bug_reports() -> Array:
	"""Load bug reports from file."""
	var reports_file = "user://bug_reports.json"
	if not FileAccess.file_exists(reports_file):
		return []

	var file = FileAccess.open(reports_file, FileAccess.READ)
	if not file:
		return []

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Array:
		file.close()
		return json.data

	file.close()
	return []

func _save_bug_reports(reports: Array) -> void:
	"""Save bug reports to file."""
	var file = FileAccess.open("user://bug_reports.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(reports, "\t"))
		file.close()
