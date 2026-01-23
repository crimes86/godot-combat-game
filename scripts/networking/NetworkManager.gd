extends Node
# NetworkManager.gd - Core multiplayer functionality

signal player_connected(id)
signal player_disconnected(id)
signal player_authenticated(id: int, player_name: String)  # Fires when player is fully joined with name
signal connected_to_server
signal connection_failed
signal server_created
signal chat_message_received(sender_name: String, message: String, sender_id: int)
signal version_mismatch(server_version: String, client_version: String)  # Emitted on client when versions differ

# Authentication signals
signal login_success(player_data: Dictionary)
signal login_failed(error: String)
signal register_success()
signal register_failed(error: String)
signal authentication_required()  # Emitted when client connects and needs to auth

const DEFAULT_PORT = 7777
const DEFAULT_WS_PORT = 7778  # WebSocket port (for web clients)

# Network protocol selection
# WebSocket works on both desktop and web browsers
# ENet is slightly more efficient but doesn't work in browsers
enum NetworkProtocol { WEBSOCKET, ENET }
var network_protocol: NetworkProtocol = NetworkProtocol.WEBSOCKET

# Detect if running in a web browser
var is_web_build: bool = OS.has_feature("web")

# Player capacity - can be overridden via --max-players CLI arg for scaling tests
# Default 50 for normal play, can scale to 200+ for large battles
const MAX_PLAYERS_DEFAULT = 50
var max_players: int = MAX_PLAYERS_DEFAULT

# Version for client/server compatibility checking
# Git hash for debugging/logging (auto-generated at export)
var GIT_HASH: String = ""

# Semantic versioning (MAJOR.MINOR.PATCH)
# - MAJOR: Breaking changes (new network protocol, save format changes)
# - MINOR: New features (both client and server should update together)
# - PATCH: Bug fixes (client and server can differ in patch version)
const GAME_VERSION: String = "0.1.4"

# Minimum client version the server accepts (server-only setting)
# - Server-only patches: bump GAME_VERSION, keep MIN_CLIENT_VERSION same
# - Client-breaking changes: bump both GAME_VERSION and MIN_CLIENT_VERSION
const MIN_CLIENT_VERSION: String = "0.1.4"

# Legacy alias for update checks
const CLIENT_VERSION: String = GAME_VERSION

# Legacy alias for logging
var NETWORK_VERSION: String:
	get: return GAME_VERSION + " (" + GIT_HASH + ")"

func _get_git_commit_hash() -> String:
	"""Get current git commit hash for version identification"""
	# Try to read from bundled file first (for exported builds)
	if FileAccess.file_exists("res://version.txt"):
		var file = FileAccess.open("res://version.txt", FileAccess.READ)
		if file:
			var version = file.get_line().strip_edges()
			file.close()
			if version.length() > 0:
				return version

	# Fallback: try to get from git directly (works in editor)
	if OS.has_feature("editor"):
		var output = []
		var exit_code = OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)
		if exit_code == 0 and output.size() > 0:
			return output[0].strip_edges()

	# Last fallback
	return "unknown"

var peer = null
var connected_players = {}
var player_name = "Player"
var is_host = false

# Authentication state
var authenticated_players: Dictionary = {}  # peer_id -> {username, player_data, is_guest}
var is_authenticated: bool = false  # Client-side: are we authenticated?
var is_guest: bool = false  # Client-side: are we playing as guest?
var local_player_data: Dictionary = {}  # Client-side: our player data from server

# Rate limiting for chat messages (server only)
var _chat_rate_limits: Dictionary = {}  # peer_id -> last_message_time_msec
const CHAT_RATE_LIMIT_MS: int = 500  # Minimum 500ms between messages

# Server-side: Track client player states for persistence (server only)
var _client_player_states: Dictionary = {}  # peer_id -> {position, inventory, stats, etc.}
var _server_save_timer: Timer = null
const SERVER_SAVE_INTERVAL: float = 120.0  # Save all connected players every 2 minutes

# EQ-style camp/logout system - character stays in world after disconnect
var _pending_logouts: Dictionary = {}  # peer_id -> {timer: Timer, username: String, player_node: Node}
const LOGOUT_TIMER_SECONDS: float = 10.0  # Character stays in world for 10s after logout request

# Backend API for server-side character sync (server syncs to backend on logout)
const BACKEND_API_BASE: String = "https://api.ashbane.net"
# Server API key - set via environment variable in production
# Generate with: openssl rand -hex 32
var SERVER_API_KEY: String = ""

func _ready():
	# Set this as singleton
	set_process(false)

	# Initialize git hash for debugging
	GIT_HASH = _get_git_commit_hash()
	LogManager.info("Version %s" % NETWORK_VERSION, "network")

	# Parse CLI args for server configuration
	_parse_cli_args()

	# Load server API key from environment (for dedicated servers)
	SERVER_API_KEY = OS.get_environment("SERVER_API_KEY")
	if not SERVER_API_KEY.is_empty():
		LogManager.info("Server API key loaded from environment", "network")

func _parse_cli_args():
	"""Parse command line arguments for server configuration."""
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--max-players" and i + 1 < args.size():
			var value = args[i + 1].to_int()
			if value >= 10 and value <= 500:  # Sanity limits
				max_players = value
				LogManager.info("Max players set to %d via CLI" % max_players, "network")
			else:
				LogManager.warn("Invalid --max-players value: %s (must be 10-500)" % args[i + 1], "network")
		elif args[i] == "--websocket":
			network_protocol = NetworkProtocol.WEBSOCKET
			LogManager.info("Network protocol set to WebSocket via CLI", "network")
		elif args[i] == "--enet":
			# ENet only works on desktop, not web
			if is_web_build:
				LogManager.warn("Cannot use ENet in web build, using WebSocket", "network")
				network_protocol = NetworkProtocol.WEBSOCKET
			else:
				network_protocol = NetworkProtocol.ENET
				LogManager.info("Network protocol set to ENet via CLI", "network")

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# Host a game server
# is_dedicated: true for headless dedicated servers (no host player)
func host_game(port: int = DEFAULT_PORT, host_player_data: Dictionary = {}, is_dedicated: bool = false) -> bool:
	var error: Error

	# Web builds MUST use WebSocket
	if is_web_build:
		network_protocol = NetworkProtocol.WEBSOCKET

	if network_protocol == NetworkProtocol.WEBSOCKET:
		peer = WebSocketMultiplayerPeer.new()
		# WebSocket server - bind to all interfaces
		error = peer.create_server(port, "*")
		LogManager.info("Starting WebSocket server on port %d" % port, "network")
	else:
		peer = ENetMultiplayerPeer.new()
		# Bind to IPv4 only to avoid IPv6 port conflicts on some systems
		peer.set_bind_ip("0.0.0.0")
		error = peer.create_server(port, max_players)
		LogManager.info("Starting ENet server on port %d" % port, "network")

	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = true
		is_authenticated = true  # Host is always authenticated

		# Initialize database for this server
		if DatabaseManager:
			DatabaseManager.initialize_database()
			DatabaseManager.reset_all_online_status()

		# Add host to player list (skip for dedicated servers - they have no host player)
		var host_id = multiplayer.get_unique_id()
		var host_is_guest = host_player_data.is_empty()

		if not is_dedicated:
			# Use display_name/character_name from player_data if authenticated, otherwise use random player_name
			var display_name = player_name
			if not host_is_guest:
				# Prefer display_name > character_name > username
				display_name = host_player_data.get("display_name", host_player_data.get("character_name", host_player_data.get("username", player_name)))
				player_name = display_name  # Update player_name to match authenticated name

			connected_players[host_id] = {
				"name": display_name,
				"ready": true
			}

			# Store host's auth info
			authenticated_players[host_id] = {
				"username": display_name if host_is_guest else host_player_data.get("username", player_name),
				"player_data": host_player_data,
				"is_guest": host_is_guest
			}
		local_player_data = host_player_data
		is_guest = host_is_guest

		# Start auto-save for host if not guest
		if not host_is_guest and DatabaseManager:
			var username = host_player_data.get("username", "")
			if not username.is_empty():
				DatabaseManager.start_auto_save(username)
				CharacterStats.start_session()

		# Start server-side save timer for all connected clients
		_start_server_save_timer()

		LogManager.info("Server created on port %d (ID: %d)" % [port, host_id], "network")
		server_created.emit()
		return true
	else:
		LogManager.error("Failed to create server: %s" % error_string(error), "network")
		return false

# Join a game server
# For WebSocket: address can be a full URL (ws://...) or just IP/hostname
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	var error: Error

	# Web builds MUST use WebSocket
	if is_web_build:
		network_protocol = NetworkProtocol.WEBSOCKET

	if network_protocol == NetworkProtocol.WEBSOCKET:
		peer = WebSocketMultiplayerPeer.new()
		# Build WebSocket URL if not already a full URL
		var ws_url: String
		if address.begins_with("ws://") or address.begins_with("wss://"):
			ws_url = address
		else:
			# Determine protocol based on context
			# - Desktop: always use ws://
			# - Web on HTTPS: must use wss://
			# - Web on HTTP (localhost): use ws://
			var protocol = "ws"
			if is_web_build:
				# Check if page is served over HTTPS
				var is_https = JavaScriptBridge.eval("window.location.protocol === 'https:'")
				protocol = "wss" if is_https else "ws"
			ws_url = "%s://%s:%d" % [protocol, address, port]

		error = peer.create_client(ws_url)
		LogManager.info("Connecting via WebSocket to %s..." % ws_url, "network")
	else:
		peer = ENetMultiplayerPeer.new()
		error = peer.create_client(address, port)
		LogManager.info("Connecting via ENet to %s:%d..." % [address, port], "network")

	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = false
		return true
	else:
		LogManager.error("Failed to create client: %s" % error_string(error), "network")
		return false

# Close connection
func close_connection():
	print("[NetworkManager] close_connection called - is_host: %s, is_authenticated: %s, is_guest: %s" % [is_host, is_authenticated, is_guest])
	print("[NetworkManager] local_player_data: %s" % [local_player_data])

	# If we're the server, save all connected players first
	if is_host:
		save_all_players()
		_stop_server_save_timer()
		_client_player_states.clear()

	# Stop auto-save and do final save before disconnecting (if authenticated and not guest)
	if is_authenticated and not is_guest and not local_player_data.is_empty():
		var username = local_player_data.get("username", "")
		print("[NetworkManager] Attempting save for user: %s" % username)
		if not username.is_empty() and DatabaseManager:
			# If we're a client, sync our state to server one last time before disconnecting
			if not is_host:
				client_sync_state()
			# stop_auto_save() does final save internally
			DatabaseManager.stop_auto_save()
			DatabaseManager.logout_player(username)
			LogManager.info("Saved and logged out: %s" % username, "database")
	else:
		print("[NetworkManager] SKIPPING SAVE - conditions not met!")

	# Hide all game UI autoloads before scene change
	_hide_game_ui()

	if peer:
		peer.close()
		peer = null
		multiplayer.multiplayer_peer = null
		connected_players.clear()
		authenticated_players.clear()
		is_host = false
		is_authenticated = false
		is_guest = false
		local_player_data = {}
		LogManager.info("Connection closed", "network")

func _hide_game_ui():
	"""Hide all game UI autoloads when disconnecting"""
	# Use get_node_or_null for autoloads that may not exist in server builds
	var group_ui = get_node_or_null("/root/GroupUI")
	var quest_tracker = get_node_or_null("/root/QuestTrackerUI")
	var minimap = get_node_or_null("/root/Minimap")
	var bug_report = get_node_or_null("/root/BugReportUI")
	var account_admin = get_node_or_null("/root/AccountAdmin")
	var tutorial_mgr = get_node_or_null("/root/TutorialManager")
	var cursor_mgr = get_node_or_null("/root/CursorManager")

	# Hide GroupUI (CanvasLayer autoload) - also hides invite popup
	if group_ui:
		group_ui.visible = false
		group_ui._hide_popup()  # Hide invite popup too
	# Hide QuestTrackerUI (CanvasLayer autoload)
	if quest_tracker:
		quest_tracker.visible = false
	# Hide Minimap (CanvasLayer autoload)
	if minimap:
		minimap.hide_minimap()
	# Hide BugReportUI (CanvasLayer autoload)
	if bug_report:
		bug_report.visible = false
	# Hide AccountAdmin (CanvasLayer autoload)
	if account_admin:
		account_admin.visible = false
	# Hide NotificationManager canvas layer (Node autoload with CanvasLayer child)
	if NotificationManager:
		var notif_canvas = NotificationManager.get_node_or_null("NotificationCanvas")
		if notif_canvas:
			notif_canvas.visible = false
	# Hide TutorialManager UI elements (Node autoload with CanvasLayer children)
	if tutorial_mgr:
		if tutorial_mgr.get("tutorial_ui") and tutorial_mgr.tutorial_ui:
			tutorial_mgr.tutorial_ui.visible = false
		if tutorial_mgr.get("ui_arrow_canvas") and tutorial_mgr.ui_arrow_canvas:
			tutorial_mgr.ui_arrow_canvas.visible = false
	# Hide CursorManager UI (may have custom cursor visible)
	if cursor_mgr and cursor_mgr.has_method("reset_cursor"):
		cursor_mgr.reset_cursor()

# Called when a player connects (server only)
func _on_player_connected(id: int):
	LogManager.info("Player connected: %d (awaiting authentication)" % id, "network")

	if is_host:
		# Don't add to player list yet - wait for authentication
		# Send minimum required version - client checks if it meets requirement
		rpc_id(id, "request_authentication_with_version", MIN_CLIENT_VERSION)

	player_connected.emit(id)

# Called when a player disconnects
func _on_player_disconnected(id: int):
	LogManager.info("Player disconnected: %d" % id, "network")

	# Check if this player has a pending logout timer (EQ-style camp)
	if _pending_logouts.has(id):
		# Player quit early - let the timer continue, character stays in world
		LogManager.info("Player %d quit early - character camping for remaining time" % id, "network")
		print("[Server] Player %d quit early during logout timer - character stays in world" % id)
		# Don't clean up yet - the timer will handle it
		# Just remove from connected_players so they can't receive RPCs
		if connected_players.has(id):
			connected_players.erase(id)
		return

	# No pending logout - this is an unexpected disconnect (crash, force quit, etc.)
	# Start a logout timer to keep character in world (prevents combat logging)
	if is_host and authenticated_players.has(id):
		var auth_info = authenticated_players[id]
		if not auth_info.is_guest:
			# Find the player's character node
			var player_node = _find_player_node(id)
			if player_node:
				LogManager.info("Unexpected disconnect for %s - starting camp timer" % auth_info.username, "network")
				print("[Server] Unexpected disconnect for peer %d - character camping for %.0fs" % [id, LOGOUT_TIMER_SECONDS])
				_start_logout_timer(id, auth_info.username, player_node)
				if connected_players.has(id):
					connected_players.erase(id)
				return

	# Guest or no player node - clean up immediately
	_cleanup_disconnected_player(id)

func _cleanup_disconnected_player(id: int) -> void:
	"""Clean up a disconnected player immediately (no camp timer)"""
	if is_host and authenticated_players.has(id):
		var auth_info = authenticated_players[id]
		if not auth_info.is_guest and DatabaseManager:
			var username = auth_info.username
			# Save player state before logout using cached state
			if _client_player_states.has(id):
				var state = _client_player_states[id]
				DatabaseManager.save_player_data(username, state)
				LogManager.info("Saved disconnecting player: %s" % username, "database")
				_client_player_states.erase(id)
			DatabaseManager.logout_player(username)
		authenticated_players.erase(id)
		if DatabaseManager:
			DatabaseManager.clear_rate_limit(id)
		_chat_rate_limits.erase(id)

	if connected_players.has(id):
		connected_players.erase(id)
		if is_host:
			rpc("player_left", id)

	player_disconnected.emit(id)

func _find_player_node(peer_id: int) -> Node:
	"""Find a player's character node by their peer ID"""
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null

# Called when we connect to server (client only)
func _on_connected_to_server():
	LogManager.info("Connected to server! Waiting for authentication request...", "network")
	# Don't register yet - wait for server to request authentication
	connected_to_server.emit()

# Called when connection fails (client only)
func _on_connection_failed():
	LogManager.error("Connection failed!", "network")
	connection_failed.emit()
	close_connection()

# RPC Functions
@rpc("any_peer", "reliable")
func register_player(_id: int, name: String):
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	# SECURITY: Use actual sender ID, not client-provided ID
	var sender_id = multiplayer.get_remote_sender_id()

	# SECURITY: Only authenticated players can update their info
	if not authenticated_players.has(sender_id):
		LogManager.warn("register_player rejected: peer %d not authenticated" % sender_id, "security")
		return

	# Sanitize name
	name = name.strip_edges()
	if name.is_empty() or name.length() > 16:
		return

	# Update only the sender's own entry
	if connected_players.has(sender_id):
		connected_players[sender_id].name = name
		# Update all players
		rpc("update_player_list", connected_players)

@rpc("authority", "reliable")
func receive_player_list(players: Dictionary):
	connected_players = players
	LogManager.debug("Received player list: %s" % players, "network")

@rpc("authority", "reliable")
func update_player_list(players: Dictionary):
	connected_players = players
	LogManager.debug("Updated player list: %s" % players, "network")

@rpc("authority", "reliable")
func player_joined(id: int, player_info: Dictionary):
	connected_players[id] = player_info
	var player_name = player_info.get("name", "Player%d" % id)
	LogManager.info("Player %s joined the game" % player_name, "player")

	# Emit signal for UI (ChatUI uses this for "joined the game" message)
	player_authenticated.emit(id, player_name)

	# NOTE: Player name labels are set by game_world.gd when players spawn (line ~4288)
	# No need to call _update_player_name_label here - it causes warnings for players
	# that haven't spawned yet (e.g., when client first joins and receives existing player list)

var _name_update_retries: Dictionary = {}  # peer_id -> retry count

func _update_player_name_label(id: int, player_name: String) -> void:
	"""Deferred update of player name label after spawn completes"""
	LogManager.debug("_update_player_name_label called: id=%d, name='%s'" % [id, player_name], "player")

	var game_world = get_tree().get_first_node_in_group("game_world")
	LogManager.debug("game_world found: %s" % (game_world != null), "player")

	if game_world:
		LogManager.debug("game_world.players keys: %s" % str(game_world.players.keys()), "player")
		LogManager.debug("Looking for player id %d in players dict" % id, "player")

	if game_world and game_world.players.has(id):
		var player = game_world.players[id]
		LogManager.debug("Found player node: %s, valid: %s" % [player, is_instance_valid(player)], "player")

		if is_instance_valid(player):
			LogManager.debug("Player has HealthBar: %s" % player.has_node("HealthBar"), "player")

			if player.has_node("HealthBar"):
				var hb = player.get_node("HealthBar")
				LogManager.debug("HealthBar node: %s" % hb, "player")

				if hb.has_method("set_player_name"):
					hb.set_player_name(player_name)
					LogManager.debug("Set player name '%s' for peer %d" % [player_name, id], "player")
				else:
					LogManager.warn("HealthBar doesn't have set_player_name method!", "player")

				# Set color based on guest status
				var is_guest_player = authenticated_players.has(id) and authenticated_players[id].get("is_guest", false)
				if hb.has_method("set_name_color"):
					if is_guest_player:
						hb.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
					else:
						hb.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated

				# Clear retry counter on success
				_name_update_retries.erase(id)
				return

	# Player not spawned yet, retry with limit
	var retries = _name_update_retries.get(id, 0)
	if retries < 60:  # Try for ~1 second (60 frames)
		_name_update_retries[id] = retries + 1
		LogManager.debug("Player %d not ready, retry %d/60" % [id, retries + 1], "player")
		call_deferred("_update_player_name_label", id, player_name)
	else:
		LogManager.warn("Failed to set name for player %d after 60 retries" % id, "player")
		_name_update_retries.erase(id)

@rpc("authority", "reliable")
func player_left(id: int):
	if connected_players.has(id):
		LogManager.info("Player %s left the game" % connected_players[id].name, "player")
		connected_players.erase(id)

# Utility functions
func get_player_count() -> int:
	return connected_players.size()

func get_player_list() -> Dictionary:
	return connected_players

func is_server() -> bool:
	return is_host

func get_unique_id() -> int:
	return multiplayer.get_unique_id()

func set_player_name(name: String):
	player_name = name

	# Update if already connected
	if peer and multiplayer.has_multiplayer_peer():
		var my_id = multiplayer.get_unique_id()
		if connected_players.has(my_id):
			connected_players[my_id].name = name

			if is_host:
				rpc("update_player_list", connected_players)
			else:
				rpc_id(1, "register_player", my_id, name)

func set_network_protocol(protocol: NetworkProtocol) -> void:
	"""Set the network protocol to use. Must be called before host_game/join_game.
	Note: Web builds always use WebSocket regardless of this setting."""
	if is_web_build and protocol == NetworkProtocol.ENET:
		LogManager.warn("Cannot use ENet in web build, using WebSocket", "network")
		network_protocol = NetworkProtocol.WEBSOCKET
	else:
		network_protocol = protocol
		var protocol_name = "WebSocket" if protocol == NetworkProtocol.WEBSOCKET else "ENet"
		LogManager.info("Network protocol set to %s" % protocol_name, "network")

func get_network_protocol() -> NetworkProtocol:
	"""Get the current network protocol."""
	return network_protocol

func get_network_protocol_name() -> String:
	"""Get the current network protocol as a human-readable string."""
	return "WebSocket" if network_protocol == NetworkProtocol.WEBSOCKET else "ENet"

func is_using_websocket() -> bool:
	"""Check if currently using WebSocket protocol."""
	return network_protocol == NetworkProtocol.WEBSOCKET

# ═══════════════════════════════════════════════════════════════════════════
# CHAT SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func send_chat_message(message: String) -> void:
	"""Send a chat message to all players"""
	if not peer or not multiplayer.has_multiplayer_peer():
		return

	# Sanitize message
	message = message.strip_edges()
	if message.is_empty() or message.length() > 200:
		return

	var my_id = multiplayer.get_unique_id()
	var my_name = player_name

	# If we're the host, broadcast directly
	if is_host:
		rpc("receive_chat_broadcast", my_name, message, my_id)
		# Also emit locally for host's UI
		chat_message_received.emit(my_name, message, my_id)
	else:
		# Send to server for relay
		rpc_id(1, "relay_chat_message", my_name, message)

@rpc("any_peer", "reliable")
func relay_chat_message(_sender_name: String, message: String) -> void:
	"""Server receives message from client and broadcasts to all"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	var sender_id = multiplayer.get_remote_sender_id()

	# SECURITY: Validate sender is authenticated and get their ACTUAL name
	# Do NOT trust client-sent sender_name (could be spoofed)
	if not authenticated_players.has(sender_id):
		LogManager.warn("Chat rejected: peer %d not authenticated" % sender_id, "security")
		return

	# SECURITY: Rate limit chat messages (prevent spam/flood)
	var current_time = Time.get_ticks_msec()
	var last_message_time = _chat_rate_limits.get(sender_id, 0)
	if current_time - last_message_time < CHAT_RATE_LIMIT_MS:
		LogManager.debug("Chat rate limited: peer %d (too fast)" % sender_id, "security")
		return
	_chat_rate_limits[sender_id] = current_time

	var actual_name = connected_players.get(sender_id, {}).get("name", "Unknown")

	# Sanitize message
	message = message.strip_edges()
	if message.is_empty() or message.length() > 200:
		return

	# Broadcast to all players using verified sender name
	rpc("receive_chat_broadcast", actual_name, message, sender_id)
	# Emit for host's local UI
	chat_message_received.emit(actual_name, message, sender_id)

@rpc("authority", "reliable", "call_remote")
func receive_chat_broadcast(sender_name: String, message: String, sender_id: int) -> void:
	"""All clients receive broadcasted chat message"""
	chat_message_received.emit(sender_name, message, sender_id)

# ═══════════════════════════════════════════════════════════════════════════
# AUTHENTICATION SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "reliable")
func request_authentication() -> void:
	"""Server tells client to authenticate (legacy - no version check)"""
	LogManager.info("Server requested authentication (legacy, no version)", "network")
	authentication_required.emit()

@rpc("authority", "reliable")
func request_authentication_with_version(min_version_required: String) -> void:
	"""Server tells client to authenticate, with version check"""
	LogManager.info("Server requires min version: %s, client version: %s" % [min_version_required, GAME_VERSION], "network")

	# In dev mode (editor or debug builds), skip version check for local testing
	var is_dev_mode = OS.has_feature("editor") or OS.is_debug_build()

	# Check if client meets minimum version requirement
	var client_meets_requirement = _compare_versions(GAME_VERSION, min_version_required) >= 0

	if not client_meets_requirement and not is_dev_mode:
		LogManager.warn("VERSION TOO OLD! Server requires: %s, Client has: %s - connection blocked" % [min_version_required, GAME_VERSION], "network")
		version_mismatch.emit(min_version_required, GAME_VERSION)
		# Block connection - don't allow authentication to proceed
		close_connection()
		return
	elif not client_meets_requirement:
		LogManager.warn("VERSION TOO OLD (dev mode - allowing): Server requires: %s, Client has: %s" % [min_version_required, GAME_VERSION], "network")
	else:
		LogManager.info("Version OK: %s >= %s" % [GAME_VERSION, min_version_required], "network")

	authentication_required.emit()

func _compare_versions(version_a: String, version_b: String) -> int:
	"""Compare two semver strings. Returns: -1 if a < b, 0 if equal, 1 if a > b"""
	var parts_a = version_a.split(".")
	var parts_b = version_b.split(".")

	for i in range(max(parts_a.size(), parts_b.size())):
		var a = int(parts_a[i]) if i < parts_a.size() else 0
		var b = int(parts_b[i]) if i < parts_b.size() else 0
		if a < b:
			return -1
		elif a > b:
			return 1
	return 0

# --- Client-side auth functions ---

func send_login(username: String, password: String) -> void:
	"""Client sends login request to server"""
	if not peer or not multiplayer.has_multiplayer_peer():
		login_failed.emit("Not connected to server")
		return

	# Hash password client-side before sending
	var password_hash = _hash_password_for_transport(password)
	rpc_id(1, "handle_login_request", username, password_hash)

func send_register(username: String, password: String) -> void:
	"""Client sends registration request to server"""
	if not peer or not multiplayer.has_multiplayer_peer():
		register_failed.emit("Not connected to server")
		return

	# Hash password client-side before sending
	var password_hash = _hash_password_for_transport(password)
	rpc_id(1, "handle_register_request", username, password_hash)

func send_guest_login(guest_name: String) -> void:
	"""Client requests to join as guest (no persistence)"""
	if not peer or not multiplayer.has_multiplayer_peer():
		login_failed.emit("Not connected to server")
		return

	rpc_id(1, "handle_guest_request", guest_name)


func send_ashbane_login(username: String, user_id: int, display_name: String = "") -> void:
	"""Client sends Ashbane-authenticated login (persistent, server trusts client auth)"""
	if not peer or not multiplayer.has_multiplayer_peer():
		login_failed.emit("Not connected to server")
		return

	var name_to_use = display_name if not display_name.is_empty() else username
	LogManager.info("Sending Ashbane auth: %s (user_id: %d)" % [name_to_use, user_id], "network")
	rpc_id(1, "handle_ashbane_auth_request", username, user_id, name_to_use)

func _hash_password_for_transport(password: String) -> String:
	"""Hash password for network transport (additional server-side hashing will be applied)"""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(password.to_utf8_buffer())
	return ctx.finish().hex_encode()

# --- Server-side auth handlers ---

@rpc("any_peer", "reliable")
func handle_login_request(username: String, password_hash: String) -> void:
	"""Server handles login request from client"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Check rate limiting
	if DatabaseManager:
		var rate_check = DatabaseManager.check_rate_limit(peer_id)
		if not rate_check.allowed:
			rpc_id(peer_id, "receive_login_response", false, "Too many attempts. Wait %d seconds." % rate_check.wait_seconds, {})
			return

	# Authenticate via database
	if not DatabaseManager:
		rpc_id(peer_id, "receive_login_response", false, "Database not available", {})
		return

	# The password_hash from client is SHA256(password)
	# We need to verify against our stored hash which is SHA256(SHA256(password) + salt)
	# So we pass the transport hash directly and let DatabaseManager handle it
	var result = DatabaseManager.authenticate(username, password_hash)
	DatabaseManager.record_login_attempt(peer_id, result.success)

	if result.success:
		# Add to authenticated players
		authenticated_players[peer_id] = {
			"username": username,
			"player_data": result.player_data,
			"is_guest": false
		}

		# Add to connected players list
		connected_players[peer_id] = {
			"name": result.player_data.get("character_name", username),
			"ready": true
		}

		# Notify all players (clients)
		rpc("player_joined", peer_id, connected_players[peer_id])

		# CRITICAL: Emit player_authenticated signal on the SERVER so game_world can spawn the player
		# The rpc("player_joined") only runs on clients, not on the server itself!
		var auth_player_name = connected_players[peer_id].get("name", "Player%d" % peer_id)
		LogManager.debug("Emitting player_authenticated for peer %d: '%s'" % [peer_id, auth_player_name], "network")
		player_authenticated.emit(peer_id, auth_player_name)

		# Send success to client
		rpc_id(peer_id, "receive_login_response", true, "", result.player_data)
		LogManager.info("Player %s (peer %d) logged in successfully" % [username, peer_id], "player")
	else:
		rpc_id(peer_id, "receive_login_response", false, result.error, {})
		LogManager.warn("Login failed for peer %d: %s" % [peer_id, result.error], "network")

@rpc("any_peer", "reliable")
func handle_register_request(username: String, password_hash: String) -> void:
	"""Server handles registration request from client"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	if not DatabaseManager:
		rpc_id(peer_id, "receive_register_response", false, "Database not available")
		return

	# Create account (password_hash from client is used as the password input)
	var result = DatabaseManager.create_account(username, password_hash)

	if result.success:
		rpc_id(peer_id, "receive_register_response", true, "")
		LogManager.info("Account created: %s (peer %d)" % [username, peer_id], "database")
	else:
		rpc_id(peer_id, "receive_register_response", false, result.error)
		LogManager.warn("Registration failed for peer %d: %s" % [peer_id, result.error], "network")

func _sanitize_guest_name(raw_name: String) -> String:
	"""Sanitize guest name: only allow alphanumeric and underscore, limit length"""
	var sanitized = ""
	raw_name = raw_name.strip_edges()

	for i in range(mini(raw_name.length(), 16)):
		var c = raw_name[i]
		var code = c.unicode_at(0)
		# Allow A-Z, a-z, 0-9, underscore
		if (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95:
			sanitized += c

	if sanitized.is_empty():
		sanitized = "Guest"  # Server adds suffix if conflicts

	return sanitized

@rpc("any_peer", "reliable")
func handle_guest_request(guest_name: String) -> void:
	"""Server handles guest login request"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# SECURITY: Sanitize guest name (remove special chars, control chars, etc.)
	guest_name = _sanitize_guest_name(guest_name)

	# Check for duplicate names among connected players
	for pid in connected_players:
		if connected_players[pid].name.to_lower() == guest_name.to_lower():
			guest_name = "%s_%d" % [guest_name, randi() % 1000]
			break

	# Create guest player data (default values, no persistence)
	# 6-stat system: STR, AGI, DEX, INT, WIS, VIT
	var guest_data = {
		"id": -peer_id,  # Negative ID indicates guest
		"username": guest_name,
		"character_name": guest_name,
		"gender": "male",
		"level": 1,
		"xp": 0,
		"gold": 100,
		"strength": 10,
		"agility": 10,
		"dexterity": 10,
		"intelligence": 10,
		"wisdom": 10,
		"vitality": 10,
		"current_hp": 100.0,
		"max_hp": 100.0,
		"position_x": -2000.0,
		"position_y": 0.0,
		"inventory": [],
		"equipment": {},
		"appearance": {}
	}

	# Add to authenticated players as guest
	authenticated_players[peer_id] = {
		"username": guest_name,
		"player_data": guest_data,
		"is_guest": true
	}

	# Add to connected players
	connected_players[peer_id] = {
		"name": guest_name,
		"ready": true
	}

	# Notify all players (clients)
	rpc("player_joined", peer_id, connected_players[peer_id])

	# CRITICAL: Emit player_authenticated signal on the SERVER so game_world can spawn the player
	# The rpc("player_joined") only runs on clients, not on the server itself!
	LogManager.debug("Emitting player_authenticated for guest peer %d: '%s'" % [peer_id, guest_name], "network")
	player_authenticated.emit(peer_id, guest_name)

	# Send success to client
	rpc_id(peer_id, "receive_login_response", true, "", guest_data)
	LogManager.info("Guest %s (peer %d) joined" % [guest_name, peer_id], "player")


# Pending Ashbane auth requests (while waiting for backend fetch)
var _pending_ashbane_auth: Dictionary = {}  # peer_id -> {user_id, username, display_name, storage_key}

@rpc("any_peer", "reliable")
func handle_ashbane_auth_request(username: String, user_id: int, display_name: String) -> void:
	"""Server handles Ashbane-authenticated user login.
	The server fetches character data from backend API (authoritative source)."""
	if not multiplayer:
		return

	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Use Ashbane user_id as the storage key (guaranteed unique and valid format)
	var storage_key = "ashbane_%d" % user_id

	# Use display_name for in-game name, fallback to username
	var player_name = display_name if not display_name.is_empty() else username
	player_name = _sanitize_guest_name(player_name)

	print("[Server] Ashbane auth: peer=%d, user_id=%d, storage_key=%s, display=%s" % [peer_id, user_id, storage_key, player_name])
	LogManager.info("Ashbane auth request from peer %d: %s (user_id: %d, key: %s)" % [peer_id, player_name, user_id, storage_key], "network")

	# Store pending auth info
	_pending_ashbane_auth[peer_id] = {
		"user_id": user_id,
		"username": username,
		"display_name": player_name,
		"storage_key": storage_key
	}

	# Fetch character data from backend API (authoritative source)
	if not SERVER_API_KEY.is_empty():
		_fetch_character_from_backend(peer_id, user_id)
	else:
		# No API key configured - fall back to local storage
		print("[Server] No SERVER_API_KEY - using local storage for %s" % storage_key)
		_complete_ashbane_auth_with_local_data(peer_id)


func _fetch_character_from_backend(peer_id: int, user_id: int) -> void:
	"""Fetch character data from backend API."""
	var url = BACKEND_API_BASE + "/api/server/character/%d" % user_id
	var headers = PackedStringArray([
		"X-Server-Key: " + SERVER_API_KEY,
		"Content-Type: application/json"
	])

	var http = HTTPRequest.new()
	http.timeout = 5  # 5 second timeout
	add_child(http)
	http.request_completed.connect(_on_backend_fetch_completed.bind(peer_id, http))

	var error = http.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("[Server] Failed to start backend fetch for peer %d: error %d" % [peer_id, error])
		http.queue_free()
		# Fall back to local storage
		_complete_ashbane_auth_with_local_data(peer_id)


func _on_backend_fetch_completed(result: int, code: int, _headers: PackedStringArray,
								body: PackedByteArray, peer_id: int, http: HTTPRequest) -> void:
	"""Handle backend character fetch response."""
	http.queue_free()

	if not _pending_ashbane_auth.has(peer_id):
		print("[Server] Backend fetch completed but peer %d no longer pending" % peer_id)
		return

	var auth_info = _pending_ashbane_auth[peer_id]
	var storage_key = auth_info.get("storage_key", "")

	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		# Parse backend response
		var body_text = body.get_string_from_utf8()
		var backend_data = JSON.parse_string(body_text)

		if backend_data and backend_data.get("success", false):
			print("[Server] Backend fetch SUCCESS for %s: level=%d, gold=%d" % [
				storage_key, backend_data.get("level", 1), backend_data.get("gold", 0)
			])
			_complete_ashbane_auth_with_backend_data(peer_id, backend_data)
			return
		else:
			print("[Server] Backend returned invalid data for %s" % storage_key)
	else:
		var body_text = body.get_string_from_utf8() if body.size() > 0 else ""
		print("[Server] Backend fetch FAILED for %s: result=%d, code=%d, body=%s" % [
			storage_key, result, code, body_text.substr(0, 200)
		])

	# Fall back to local storage on any error
	_complete_ashbane_auth_with_local_data(peer_id)


func _complete_ashbane_auth_with_backend_data(peer_id: int, backend_data: Dictionary) -> void:
	"""Complete auth using data from backend API."""
	if not _pending_ashbane_auth.has(peer_id):
		return

	var auth_info = _pending_ashbane_auth[peer_id]
	var storage_key: String = auth_info.get("storage_key", "")
	var player_name: String = auth_info.get("display_name", "")
	var user_id: int = auth_info.get("user_id", 0)

	# Build player_data from backend response
	var player_data = {
		"username": storage_key,
		"character_name": player_name,
		"id": user_id,
		"level": backend_data.get("level", 1),
		"xp": backend_data.get("experience", 0),
		"gold": backend_data.get("gold", 100),
		"strength": backend_data.get("strength", 10),
		"agility": backend_data.get("agility", 10),
		"dexterity": backend_data.get("dexterity", 10),
		"intelligence": backend_data.get("intelligence", 10),
		"wisdom": backend_data.get("wisdom", 10),
		"vitality": backend_data.get("vitality", 10),
		"inventory": JSON.stringify(backend_data.get("inventory", [])),
		"equipped_weapon": backend_data.get("equipped_weapon", ""),
		"equipped_armor": backend_data.get("equipped_armor", {}),
		"weapon_skills": JSON.stringify(backend_data.get("weapon_skills", {}))
	}

	# Save to local database for future reference
	if DatabaseManager:
		if not DatabaseManager.player_exists(storage_key):
			DatabaseManager.create_account(storage_key, "ashbane_auth_%d" % user_id)
		DatabaseManager.save_player_data(storage_key, player_data)

	_finalize_ashbane_auth(peer_id, player_data)


func _complete_ashbane_auth_with_local_data(peer_id: int) -> void:
	"""Complete auth using local database (fallback when backend unavailable)."""
	if not _pending_ashbane_auth.has(peer_id):
		return

	var auth_info = _pending_ashbane_auth[peer_id]
	var storage_key: String = auth_info.get("storage_key", "")
	var player_name: String = auth_info.get("display_name", "")
	var user_id: int = auth_info.get("user_id", 0)

	var player_data: Dictionary = {}
	if DatabaseManager:
		var existing = DatabaseManager.get_player_data(storage_key)
		if not existing.is_empty():
			player_data = existing
			player_data["character_name"] = player_name
			print("[Server] Loaded from LOCAL storage: %s, level=%d" % [storage_key, player_data.get("level", 1)])
		else:
			# New user - create with defaults
			var create_result = DatabaseManager.create_account(storage_key, "ashbane_auth_%d" % user_id)
			if create_result.success:
				player_data = DatabaseManager.get_player_data(storage_key)
				if not player_data.is_empty():
					player_data["character_name"] = player_name
					DatabaseManager.save_player_data(storage_key, player_data)
				print("[Server] Created new Ashbane user (local): %s" % storage_key)
			else:
				print("[Server] ERROR: Failed to create account: %s" % storage_key)
				rpc_id(peer_id, "receive_login_response", false, "Failed to create account", {})
				_pending_ashbane_auth.erase(peer_id)
				return

	if player_data.is_empty():
		print("[Server] ERROR: No player data for: %s" % storage_key)
		rpc_id(peer_id, "receive_login_response", false, "Failed to load player data", {})
		_pending_ashbane_auth.erase(peer_id)
		return

	player_data["username"] = storage_key
	player_data["character_name"] = player_name
	if not player_data.has("id"):
		player_data["id"] = user_id

	_finalize_ashbane_auth(peer_id, player_data)


func _finalize_ashbane_auth(peer_id: int, player_data: Dictionary) -> void:
	"""Finalize Ashbane authentication after data is loaded."""
	if not _pending_ashbane_auth.has(peer_id):
		return

	var auth_info = _pending_ashbane_auth[peer_id]
	var storage_key: String = auth_info.get("storage_key", "")
	var player_name: String = auth_info.get("display_name", "")
	var user_id: int = auth_info.get("user_id", 0)

	# Clean up pending auth
	_pending_ashbane_auth.erase(peer_id)

	# Add to authenticated players (NOT guest!)
	authenticated_players[peer_id] = {
		"username": storage_key,
		"player_data": player_data,
		"is_guest": false,
		"user_id": user_id
	}

	# Add to connected players
	connected_players[peer_id] = {
		"name": player_name,
		"ready": true
	}

	# Notify all players
	rpc("player_joined", peer_id, connected_players[peer_id])

	# Emit player_authenticated signal on SERVER
	LogManager.debug("Emitting player_authenticated for Ashbane peer %d: '%s'" % [peer_id, player_name], "network")
	player_authenticated.emit(peer_id, player_name)

	# Cache initial state for disconnect handling (before client sends state sync)
	# This prevents data loss if player disconnects immediately after login
	_client_player_states[peer_id] = {
		"level": player_data.get("level", 1),
		"xp": player_data.get("xp", player_data.get("experience", 0)),
		"gold": player_data.get("gold", 0),
		"inventory": player_data.get("inventory", "[]"),
		"equipped_weapon": player_data.get("equipped_weapon", ""),
		"equipped_armor": player_data.get("equipped_armor", {}),
		"weapon_skills": player_data.get("weapon_skills", "{}")
	}

	print("[Server] Player %s registered for server-side auto-save" % storage_key)

	# Send success to client
	rpc_id(peer_id, "receive_login_response", true, "", player_data)
	print("[Server] Ashbane auth SUCCESS: %s (peer %d) - level %d, xp %d" % [player_name, peer_id, player_data.get("level", 1), player_data.get("xp", 0)])
	LogManager.info("Ashbane user %s (peer %d) authenticated - level %d" % [player_name, peer_id, player_data.get("level", 1)], "player")


# --- Client-side auth response handlers ---

@rpc("authority", "reliable")
func receive_login_response(success: bool, error: String, player_data: Dictionary) -> void:
	"""Client receives login response from server"""
	if success:
		is_authenticated = true

		# Check Ashbane auth - if authenticated there, we're NOT a guest
		# (even if game server assigned a guest ID)
		var ashbane_auth = get_node_or_null("/root/AshbaneAuth")
		if ashbane_auth and ashbane_auth.is_authenticated and not ashbane_auth.is_guest:
			is_guest = false
			# NOTE: Do NOT override player_data["username"] - server uses storage_key (ashbane_XXXX)
			# for persistence. Keep the server-assigned username for save/load consistency.
			LogManager.info("Ashbane-authenticated user (storage: %s)" % player_data.get("username", "?"), "network")
		else:
			is_guest = player_data.get("id", 0) < 0  # Negative ID = guest

		local_player_data = player_data
		# Prefer display_name > character_name > username > "Player"
		player_name = player_data.get("display_name", player_data.get("character_name", player_data.get("username", "Player")))

		# Start auto-save for non-guest players
		# This triggers periodic client->server state sync
		if not is_guest and DatabaseManager:
			var storage_key = player_data.get("username", "")
			if not storage_key.is_empty():
				# CRITICAL: Save backend player_data to client's local storage BEFORE apply_player_data_to_systems runs
				# This ensures equipped_weapon and other backend data is available for restoration
				if not DatabaseManager.player_exists(storage_key):
					DatabaseManager.create_account(storage_key, "client_local_%d" % player_data.get("id", 0))
				DatabaseManager.save_player_data(storage_key, player_data)
				print("[Client] Saved backend data to local storage for: %s (equipped_weapon: %s)" % [storage_key, player_data.get("equipped_weapon", "")])

				DatabaseManager.start_auto_save(storage_key)
				print("[Client] Auto-save started for storage_key: %s" % storage_key)
				# Start session playtime tracking
				CharacterStats.start_session()

		login_success.emit(player_data)
		LogManager.info("Login successful! Playing as: %s" % player_name, "player")
	else:
		is_authenticated = false
		login_failed.emit(error)
		LogManager.warn("Login failed: %s" % error, "network")

@rpc("authority", "reliable")
func receive_register_response(success: bool, error: String) -> void:
	"""Client receives registration response from server"""
	if success:
		register_success.emit()
		LogManager.info("Registration successful!", "database")
	else:
		register_failed.emit(error)
		LogManager.warn("Registration failed: %s" % error, "network")

# --- Utility functions for auth ---

func is_player_authenticated(peer_id: int) -> bool:
	"""Check if a peer is authenticated (server-side)"""
	return authenticated_players.has(peer_id)

func get_authenticated_player_data(peer_id: int) -> Dictionary:
	"""Get authenticated player's data (server-side)"""
	if authenticated_players.has(peer_id):
		return authenticated_players[peer_id].player_data
	return {}

func is_player_guest(peer_id: int) -> bool:
	"""Check if a peer is playing as guest (server-side)"""
	if authenticated_players.has(peer_id):
		return authenticated_players[peer_id].is_guest
	return true  # Assume guest if not found

# ═══════════════════════════════════════════════════════════════════════════
# SERVER-SIDE PLAYER PERSISTENCE
# ═══════════════════════════════════════════════════════════════════════════

func _start_server_save_timer() -> void:
	"""Start the server's periodic save timer for all connected players (server-only)"""
	if not is_host:
		return

	if _server_save_timer:
		_server_save_timer.stop()
		_server_save_timer.queue_free()

	_server_save_timer = Timer.new()
	_server_save_timer.name = "ServerSaveTimer"
	_server_save_timer.one_shot = false
	_server_save_timer.timeout.connect(_on_server_save_timer)
	add_child(_server_save_timer)
	_server_save_timer.start(SERVER_SAVE_INTERVAL)
	LogManager.info("Server save timer started (every %.0fs)" % SERVER_SAVE_INTERVAL, "database")

func _stop_server_save_timer() -> void:
	"""Stop the server save timer"""
	if _server_save_timer:
		_server_save_timer.stop()
		_server_save_timer.queue_free()
		_server_save_timer = null

func _on_server_save_timer() -> void:
	"""Periodic save of all connected authenticated players (server-only)"""
	if not is_host or not DatabaseManager:
		return

	print("[Server] Auto-save timer fired. Authenticated players: %d" % authenticated_players.size())
	var saved_count = 0
	var skipped_guest = 0
	var no_state = 0

	for peer_id in authenticated_players:
		var auth_info = authenticated_players[peer_id]
		if auth_info.is_guest:
			skipped_guest += 1
			continue

		var username = auth_info.username
		if _client_player_states.has(peer_id):
			var state = _client_player_states[peer_id]
			print("[Server] Saving peer %d (%s): level=%d, xp=%d" % [peer_id, username, state.get("level", 0), state.get("xp", 0)])
			if DatabaseManager.save_player_data(username, state):
				saved_count += 1
			else:
				print("[Server] ERROR: Failed to save %s" % username)
		else:
			no_state += 1
			print("[Server] No cached state for peer %d (%s)" % [peer_id, username])

	print("[Server] Auto-save complete: saved=%d, guests=%d, no_state=%d" % [saved_count, skipped_guest, no_state])
	if saved_count > 0:
		LogManager.info("Server auto-saved %d player(s)" % saved_count, "database")

func save_all_players() -> void:
	"""Force save all connected authenticated players (server-only)"""
	if not is_host:
		return
	_on_server_save_timer()

# ═══════════════════════════════════════════════════════════════════════════
# EQ-STYLE CAMP/LOGOUT SYSTEM
# Character stays in world after disconnect, vulnerable to attack
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_logout() -> void:
	"""Client requests to start logout timer (EQ-style camp)"""
	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()
	if not authenticated_players.has(peer_id):
		return

	var auth_info = authenticated_players[peer_id]
	if auth_info.is_guest:
		# Guests can logout immediately
		return

	var player_node = _find_player_node(peer_id)
	if not player_node:
		return

	# Start the logout timer
	_start_logout_timer(peer_id, auth_info.username, player_node)
	LogManager.info("Player %s started logout timer (%.0fs)" % [auth_info.username, LOGOUT_TIMER_SECONDS], "network")
	print("[Server] Player %s (peer %d) started camp timer - %.0fs" % [auth_info.username, peer_id, LOGOUT_TIMER_SECONDS])

@rpc("any_peer", "reliable")
func cancel_logout() -> void:
	"""Client cancels their logout timer"""
	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()
	if _pending_logouts.has(peer_id):
		var logout_info = _pending_logouts[peer_id]
		if logout_info.timer and is_instance_valid(logout_info.timer):
			logout_info.timer.stop()
			logout_info.timer.queue_free()
		_pending_logouts.erase(peer_id)
		LogManager.info("Player cancelled logout", "network")
		print("[Server] Peer %d cancelled logout timer" % peer_id)

func _start_logout_timer(peer_id: int, username: String, player_node: Node) -> void:
	"""Start server-side logout timer - character stays in world"""
	# Cancel any existing timer
	if _pending_logouts.has(peer_id):
		var existing = _pending_logouts[peer_id]
		if existing.timer and is_instance_valid(existing.timer):
			existing.timer.stop()
			existing.timer.queue_free()

	# Create timer
	var timer = Timer.new()
	timer.name = "LogoutTimer_%d" % peer_id
	timer.one_shot = true
	timer.timeout.connect(_complete_player_logout.bind(peer_id))
	add_child(timer)
	timer.start(LOGOUT_TIMER_SECONDS)

	# Store pending logout info
	_pending_logouts[peer_id] = {
		"timer": timer,
		"username": username,
		"player_node": player_node
	}

func _complete_player_logout(peer_id: int) -> void:
	"""Called when logout timer expires - save character state and remove from world"""
	if not _pending_logouts.has(peer_id):
		return

	var logout_info = _pending_logouts[peer_id]
	var username = logout_info.username
	var player_node = logout_info.player_node

	# Get user_id from authenticated_players BEFORE we erase it (needed for backend sync)
	var user_id: int = 0
	var is_guest_player: bool = true
	if authenticated_players.has(peer_id):
		var auth_info = authenticated_players[peer_id]
		user_id = auth_info.get("user_id", 0)
		is_guest_player = auth_info.get("is_guest", true)

	print("[Server] Camp timer complete for %s (peer %d) - saving and removing character" % [username, peer_id])
	LogManager.info("Logout complete for %s - saving character" % username, "network")

	# Save the player's CURRENT state from the node (not cached - they may have died!)
	var state: Dictionary = {}
	if player_node and is_instance_valid(player_node) and DatabaseManager:
		state = _build_state_from_player_node(player_node, peer_id)
		if not state.is_empty():
			DatabaseManager.save_player_data(username, state)
			print("[Server] Saved %s: level=%d, hp=%.0f, dead=%s" % [
				username,
				state.get("level", 1),
				state.get("current_hp", 0),
				str(state.get("current_hp", 0) <= 0)
			])
		DatabaseManager.logout_player(username)

	# Sync to backend API (for non-guest Ashbane users)
	if not is_guest_player and user_id > 0 and not state.is_empty():
		_sync_player_to_backend(user_id, username, state, "camp_complete")

	# Remove player from world
	if player_node and is_instance_valid(player_node):
		player_node.queue_free()

	# Clean up timer
	if logout_info.timer and is_instance_valid(logout_info.timer):
		logout_info.timer.queue_free()

	# Clean up tracking
	_pending_logouts.erase(peer_id)
	authenticated_players.erase(peer_id)
	_client_player_states.erase(peer_id)
	_chat_rate_limits.erase(peer_id)
	if DatabaseManager:
		DatabaseManager.clear_rate_limit(peer_id)

	# Notify remaining players
	rpc("player_left", peer_id)
	player_disconnected.emit(peer_id)

func _build_state_from_player_node(player_node: Node, peer_id: int) -> Dictionary:
	"""Build save state directly from player node (for logout after disconnect)"""
	var state = {}

	# Position and health from the actual node
	if player_node and is_instance_valid(player_node):
		state["position_x"] = player_node.global_position.x
		state["position_y"] = player_node.global_position.y
		if "current_health" in player_node:
			state["current_hp"] = player_node.current_health

	# Try to get from cached state first (has inventory, stats, etc.)
	if _client_player_states.has(peer_id):
		var cached = _client_player_states[peer_id]
		# Merge cached data but override position/hp with current values
		for key in cached:
			if not state.has(key):
				state[key] = cached[key]

	return state

# --- Server → Backend: Sync character on logout ---

func _sync_player_to_backend(user_id: int, username: String, state: Dictionary, disconnect_reason: String = "") -> void:
	"""Sync player state to backend API using server key.
	Called when camp timer completes or player disconnects unexpectedly.
	Server is authoritative for final state (player may have died during camp)."""
	if not is_host:
		return

	if SERVER_API_KEY.is_empty():
		print("[Server] Cannot sync to backend - SERVER_API_KEY not configured")
		return

	if user_id <= 0:
		print("[Server] Cannot sync %s to backend - no user_id" % username)
		return

	# Parse inventory from JSON string and extract items array
	# Client stores as JSON.stringify({items: [...], equipped_axe: {...}, ...})
	var inventory_raw = state.get("inventory", "[]")
	var inventory_items: Array = []
	if typeof(inventory_raw) == TYPE_STRING and inventory_raw != "":
		var json = JSON.new()
		if json.parse(inventory_raw) == OK:
			var parsed = json.get_data()
			if typeof(parsed) == TYPE_DICTIONARY:
				inventory_items = parsed.get("items", [])
			elif typeof(parsed) == TYPE_ARRAY:
				inventory_items = parsed
	elif typeof(inventory_raw) == TYPE_ARRAY:
		inventory_items = inventory_raw

	# Parse weapon_skills from JSON string
	var weapon_skills_raw = state.get("weapon_skills", "{}")
	var weapon_skills_data: Dictionary = {}
	if typeof(weapon_skills_raw) == TYPE_STRING and weapon_skills_raw != "":
		var json = JSON.new()
		if json.parse(weapon_skills_raw) == OK:
			var parsed = json.get_data()
			if typeof(parsed) == TYPE_DICTIONARY:
				weapon_skills_data = parsed
	elif typeof(weapon_skills_raw) == TYPE_DICTIONARY:
		weapon_skills_data = weapon_skills_raw

	# Extract weapon ID string from equipped_weapon dict
	# Backend expects a string, not the full weapon object
	var equipped_weapon_raw = state.get("equipped_weapon", "")
	print("[Server] Backend sync - equipped_weapon_raw type=%d, value=%s" % [typeof(equipped_weapon_raw), str(equipped_weapon_raw).substr(0, 200)])
	var equipped_weapon_str: String = ""
	if typeof(equipped_weapon_raw) == TYPE_DICTIONARY and not equipped_weapon_raw.is_empty():
		# Prefer forged_id for forged weapons, else weapon_name
		if equipped_weapon_raw.get("is_forged", false) and equipped_weapon_raw.has("forged_id"):
			equipped_weapon_str = equipped_weapon_raw.get("forged_id", "")
		else:
			equipped_weapon_str = equipped_weapon_raw.get("weapon_name", "")
		print("[Server] Backend sync - extracted weapon ID: '%s' (is_forged=%s)" % [equipped_weapon_str, equipped_weapon_raw.get("is_forged", false)])
	elif typeof(equipped_weapon_raw) == TYPE_STRING:
		equipped_weapon_str = equipped_weapon_raw
		print("[Server] Backend sync - weapon was already a string: '%s'" % equipped_weapon_str)
	else:
		print("[Server] Backend sync - no equipped weapon found (type=%d)" % typeof(equipped_weapon_raw))

	var payload = {
		"user_id": user_id,
		"gold": state.get("gold", 0),
		"level": state.get("level", 1),
		"experience": state.get("xp", 0),
		"inventory": inventory_items,
		"equipped_weapon": equipped_weapon_str,
		"equipped_armor": state.get("equipped_armor", {}),
		"weapon_skills": weapon_skills_data,
		"disconnect_reason": disconnect_reason
	}

	var url = BACKEND_API_BASE + "/api/server/character-sync"
	var headers = PackedStringArray([
		"X-Server-Key: " + SERVER_API_KEY,
		"Content-Type: application/json"
	])

	# Create HTTP request for this sync
	var http = HTTPRequest.new()
	http.timeout = 10
	add_child(http)
	http.request_completed.connect(_on_backend_sync_completed.bind(username, http))

	var json_body = JSON.stringify(payload)
	var error = http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		print("[Server] Failed to start backend sync for %s: error %d" % [username, error])
		http.queue_free()
		return

	print("[Server] Syncing %s (user_id=%d) to backend: level=%d, gold=%d" % [
		username, user_id, state.get("level", 1), state.get("gold", 0)
	])


func _on_backend_sync_completed(result: int, code: int, _headers: PackedStringArray,
								body: PackedByteArray, username: String, http: HTTPRequest) -> void:
	"""Handle backend sync HTTP response"""
	http.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		print("[Server] Backend sync SUCCESS for %s" % username)
		LogManager.info("Backend sync success: %s" % username, "network")
	else:
		var body_text = body.get_string_from_utf8() if body.size() > 0 else ""
		print("[Server] Backend sync FAILED for %s: result=%d, code=%d, body=%s" % [
			username, result, code, body_text.substr(0, 200)
		])
		LogManager.warn("Backend sync failed for %s: code=%d" % [username, code], "network")

# --- Client → Server: Sync player state ---

@rpc("any_peer", "reliable")
func sync_player_state_to_server(state_data: Dictionary) -> void:
	"""Client sends their current state to server for persistence"""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Only accept from authenticated non-guest players
	if not authenticated_players.has(peer_id):
		return
	if authenticated_players[peer_id].is_guest:
		return

	# Validate state data has expected fields
	if not _validate_player_state(state_data):
		push_warning("[NetworkManager] Invalid state data from peer %d" % peer_id)
		return

	# Store the state
	_client_player_states[peer_id] = state_data
	var weapon_info = state_data.get("equipped_weapon", {})
	print("[Server] Received state sync from peer %d: level=%d, xp=%d, equipped_weapon=%s" % [peer_id, state_data.get("level", 0), state_data.get("xp", 0), str(weapon_info).substr(0, 150)])

	# Immediately save to database (don't wait for auto-save timer)
	# This ensures quit-now doesn't lose data
	var username = authenticated_players[peer_id].username
	if DatabaseManager and not username.is_empty():
		if DatabaseManager.save_player_data(username, state_data):
			print("[Server] Immediate save for %s: level=%d, xp=%d" % [username, state_data.get("level", 0), state_data.get("xp", 0)])
		else:
			print("[Server] ERROR: Failed immediate save for %s" % username)

func _validate_player_state(state: Dictionary) -> bool:
	"""Validate that player state has reasonable values"""
	# Check required fields exist
	var required = ["position_x", "position_y", "level", "gold"]
	for field in required:
		if not state.has(field):
			return false

	# Position bounds validation (prevent teleport exploits)
	const MAX_WORLD_COORD: float = 100000.0
	var pos_x = state.get("position_x", 0.0)
	var pos_y = state.get("position_y", 0.0)

	# Check for NaN/INF and reasonable bounds
	if not is_finite(pos_x) or not is_finite(pos_y):
		LogManager.warn("Invalid position: NaN/INF detected", "security")
		return false

	if absf(pos_x) > MAX_WORLD_COORD or absf(pos_y) > MAX_WORLD_COORD:
		LogManager.warn("Invalid position: out of bounds (%f, %f)" % [pos_x, pos_y], "security")
		return false

	# Level sanity check
	var level = state.get("level", 0)
	if level < 1 or level > 100:
		return false

	# Gold sanity check
	var gold = state.get("gold", -1)
	if gold < 0 or gold > 999999999:
		return false

	return true

# --- Called by game systems to sync state to server ---

func client_sync_state() -> void:
	"""Client calls this to sync their state to the server"""
	if is_host or is_guest or not is_authenticated:
		return

	if not peer or not multiplayer.has_multiplayer_peer():
		return

	# Build state from local systems
	var state = _build_local_player_state()
	if not state.is_empty():
		rpc_id(1, "sync_player_state_to_server", state)

func _build_local_player_state() -> Dictionary:
	"""Build current player state from local game systems"""
	var state = {}

	# Get player position
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and is_instance_valid(player):
		state["position_x"] = player.global_position.x
		state["position_y"] = player.global_position.y
		if "current_health" in player:
			state["current_hp"] = player.current_health

	# Get stats from CharacterStats - 6-stat system
	var stats_data = CharacterStats.get_save_data()
	state["level"] = stats_data.get("level", 1)
	state["xp"] = stats_data.get("experience", 0)
	state["gold"] = stats_data.get("gold", 0)
	state["strength"] = stats_data.get("strength", 10)
	state["agility"] = stats_data.get("agility", 10)
	state["dexterity"] = stats_data.get("dexterity", 10)
	state["intelligence"] = stats_data.get("intelligence", 10)
	state["wisdom"] = stats_data.get("wisdom", 10)
	state["vitality"] = stats_data.get("vitality", 10)
	state["character_stats"] = JSON.stringify(stats_data)

	# Get equipped items from CharacterStats
	state["equipped_weapon"] = stats_data.get("equipped_weapon", {})
	state["equipped_armor"] = stats_data.get("equipped_armor", {})
	print("[Client] Building state - equipped_weapon: %s" % str(state["equipped_weapon"]).substr(0, 200))

	# Get inventory - send items array, not stringified
	var inv_data = InventorySystem.get_save_data()
	state["inventory"] = inv_data.get("items", [])

	# Get weapon skills - send dict, not stringified
	if WeaponSkillManager:
		var ws_data = WeaponSkillManager.get_save_data()
		state["weapon_skills"] = ws_data.get("weapon_skills", {})

	# Playtime
	state["total_playtime_seconds"] = stats_data.get("total_playtime", 0)

	return state

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER HEALING SYSTEM (Healing Staff)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_player_heal(target_peer_id: int, heal_amount: float) -> void:
	"""Client requests to heal another player. Server validates and applies."""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		return

	var healer_peer_id = multiplayer.get_remote_sender_id()

	# SECURITY: Validate healer is authenticated
	if not authenticated_players.has(healer_peer_id):
		push_warning("Anti-cheat: Unauthenticated peer %d tried to heal" % healer_peer_id)
		return

	# SECURITY: Get healer's player node and validate they have a healing weapon
	var game_world = get_node_or_null("/root/GameWorld")
	if not game_world:
		return

	var healer_player = game_world.get_player_by_peer_id(healer_peer_id)
	if not healer_player or not is_instance_valid(healer_player):
		return

	# Validate healer has a healing staff equipped
	var has_healing_weapon = false
	var max_heal_amount = 100.0  # Default cap
	if healer_player.has_method("get_equipped_weapon"):
		var weapon = healer_player.get_equipped_weapon()
		if weapon and weapon.has_method("is_healing_weapon") and weapon.is_healing_weapon():
			has_healing_weapon = true
			if weapon.has_method("get_total_healing"):
				max_heal_amount = weapon.get_total_healing() * 1.5  # Allow 50% buffer for stat scaling

	if not has_healing_weapon:
		push_warning("Anti-cheat: Player %d tried to heal without healing weapon" % healer_peer_id)
		return

	# SECURITY: Clamp heal amount to weapon's max (prevents arbitrary heal exploits)
	heal_amount = clampf(heal_amount, 1.0, max_heal_amount)

	# Find target player and apply heal
	var target_player = game_world.get_player_by_peer_id(target_peer_id)
	if target_player and is_instance_valid(target_player) and target_player.has_method("heal"):
		# ALLEGIANCE CHECK: Validate healer can heal target
		if not _can_heal_player_server(healer_player, target_player, healer_peer_id, target_peer_id):
			push_warning("Allegiance: Player %d cannot heal player %d" % [healer_peer_id, target_peer_id])
			return

		# Apply heal on server (pass healer ID for assist tracking)
		target_player.heal(heal_amount, "player", healer_peer_id)
		LogManager.debug("Player %d healed player %d for %.1f" % [healer_peer_id, target_peer_id, heal_amount], "combat")

		# Sync health to the target player's client
		if target_peer_id != 1:  # Don't RPC to server (already updated locally)
			_sync_player_health.rpc_id(target_peer_id, target_player.current_health, target_player.max_health)

@rpc("authority", "reliable")
func _sync_player_health(current_hp: float, max_hp: float) -> void:
	"""Server syncs health to client after healing."""
	var local_player = _get_local_player()
	if local_player and is_instance_valid(local_player):
		local_player.current_health = current_hp
		local_player.max_health = max_hp
		if local_player.health_bar and local_player.health_bar.has_method("update_health"):
			local_player.health_bar.update_health(current_hp, max_hp)
		LogManager.debug("Health synced to %.1f/%.1f" % [current_hp, max_hp], "combat")

func _can_heal_player_server(healer: Node, target: Node, healer_id: int, target_id: int) -> bool:
	"""Server-side allegiance check for healing."""
	# Self-healing is always allowed
	if healer_id == target_id:
		return true

	# Party members can always heal each other
	var is_same_party = false
	if GroupManager and GroupManager.has_group():
		var healer_in_group = GroupManager.is_group_member(healer_id) or GroupManager.group_leader_id == healer_id
		var target_in_group = GroupManager.is_group_member(target_id) or GroupManager.group_leader_id == target_id
		if healer_in_group and target_in_group:
			is_same_party = true

	if is_same_party:
		return true

	# Duel isolation: cannot heal duel combatants (unless same party - handled above)
	if target.get("is_dueling") == true:
		return false

	# Get allegiances
	var healer_allegiance = healer.get("allegiance_id")
	var target_allegiance = target.get("allegiance_id")
	if healer_allegiance == null:
		healer_allegiance = "ashbane"
	if target_allegiance == null:
		target_allegiance = "ashbane"

	# Rogues can only heal party members (handled above)
	if healer_allegiance == "" or target_allegiance == "":
		return false

	# Same allegiance = can heal
	if healer_allegiance == target_allegiance:
		return true

	# Different allegiance = cannot heal
	return false

func _get_local_player() -> Node:
	"""Get the local player node."""
	var game_world = get_node_or_null("/root/GameWorld")
	if game_world:
		return game_world.get_player_by_peer_id(multiplayer.get_unique_id())
	return null