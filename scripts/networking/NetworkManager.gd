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

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 50  # Target for 3-chunk playtest (single instance)

# Version for client/server compatibility checking
# Auto-generated from git commit hash - no manual incrementing needed
var NETWORK_VERSION: String = ""

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

# Server-side: Track client player states for persistence (server only)
var _client_player_states: Dictionary = {}  # peer_id -> {position, inventory, stats, etc.}
var _server_save_timer: Timer = null
const SERVER_SAVE_INTERVAL: float = 120.0  # Save all connected players every 2 minutes

func _ready():
	# Set this as singleton
	set_process(false)

	# Initialize version from git commit hash
	NETWORK_VERSION = _get_git_commit_hash()
	print("NetworkManager: Version %s" % NETWORK_VERSION)

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# Host a game server
func host_game(port: int = DEFAULT_PORT, host_player_data: Dictionary = {}) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)

	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = true
		is_authenticated = true  # Host is always authenticated

		# Initialize database for this server
		if DatabaseManager:
			DatabaseManager.initialize_database()
			DatabaseManager.reset_all_online_status()

		# Add host to player list
		var host_id = multiplayer.get_unique_id()
		var host_is_guest = host_player_data.is_empty()

		# Use username from player_data if authenticated, otherwise use random player_name
		var display_name = player_name
		if not host_is_guest:
			display_name = host_player_data.get("character_name", host_player_data.get("username", player_name))
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

		print("Server created on port %d (ID: %d)" % [port, host_id])
		server_created.emit()
		return true
	else:
		print("Failed to create server: %s" % error_string(error))
		return false

# Join a game server
func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)

	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = false
		print("Connecting to %s:%d..." % [address, port])
		return true
	else:
		print("Failed to create client: %s" % error_string(error))
		return false

# Close connection
func close_connection():
	# If we're the server, save all connected players first
	if is_host:
		save_all_players()
		_stop_server_save_timer()
		_client_player_states.clear()

	# Stop auto-save and do final save before disconnecting (if authenticated and not guest)
	if is_authenticated and not is_guest and not local_player_data.is_empty():
		var username = local_player_data.get("username", "")
		if not username.is_empty() and DatabaseManager:
			# If we're a client, sync our state to server one last time before disconnecting
			if not is_host:
				client_sync_state()
			# stop_auto_save() does final save internally
			DatabaseManager.stop_auto_save()
			DatabaseManager.logout_player(username)
			print("📀 [NetworkManager] Saved and logged out: %s" % username)

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
		print("Connection closed")

# Called when a player connects (server only)
func _on_player_connected(id: int):
	print("Player connected: %d (awaiting authentication)" % id)

	if is_host:
		# Don't add to player list yet - wait for authentication
		# Send version info along with auth request
		rpc_id(id, "request_authentication_with_version", NETWORK_VERSION)

	player_connected.emit(id)

# Called when a player disconnects
func _on_player_disconnected(id: int):
	print("Player disconnected: %d" % id)

	# Handle logout for authenticated players (server-side)
	if is_host and authenticated_players.has(id):
		var auth_info = authenticated_players[id]
		if not auth_info.is_guest and DatabaseManager:
			var username = auth_info.username
			# Save player state before logout using cached state
			if _client_player_states.has(id):
				var state = _client_player_states[id]
				DatabaseManager.save_player_data(username, state)
				print("📀 [NetworkManager] Saved disconnecting player: %s" % username)
				_client_player_states.erase(id)
			DatabaseManager.logout_player(username)
		authenticated_players.erase(id)
		if DatabaseManager:
			DatabaseManager.clear_rate_limit(id)

	if connected_players.has(id):
		connected_players.erase(id)

		# Notify remaining players
		if is_host:
			rpc("player_left", id)

	player_disconnected.emit(id)

# Called when we connect to server (client only)
func _on_connected_to_server():
	print("Connected to server! Waiting for authentication request...")
	# Don't register yet - wait for server to request authentication
	connected_to_server.emit()

# Called when connection fails (client only)
func _on_connection_failed():
	print("Connection failed!")
	connection_failed.emit()
	close_connection()

# RPC Functions
@rpc("any_peer", "reliable")
func register_player(id: int, name: String):
	if not is_host:
		return

	connected_players[id] = {
		"name": name,
		"ready": false
	}

	# Update all players
	rpc("update_player_list", connected_players)

@rpc("authority", "reliable")
func receive_player_list(players: Dictionary):
	connected_players = players
	print("Received player list: %s" % players)

@rpc("authority", "reliable")
func update_player_list(players: Dictionary):
	connected_players = players
	print("Updated player list: %s" % players)

@rpc("authority", "reliable")
func player_joined(id: int, player_info: Dictionary):
	connected_players[id] = player_info
	var player_name = player_info.get("name", "Player%d" % id)
	print("Player %s joined the game" % player_name)

	# Emit signal for UI (ChatUI uses this for "joined the game" message)
	player_authenticated.emit(id, player_name)

	# ✨ FIX: Update health bar name label for this player on all clients
	# Use call_deferred to ensure player is spawned first
	call_deferred("_update_player_name_label", id, player_name)

var _name_update_retries: Dictionary = {}  # peer_id -> retry count

func _update_player_name_label(id: int, player_name: String) -> void:
	"""Deferred update of player name label after spawn completes"""
	print("🏷️ [NAME DEBUG] _update_player_name_label called: id=%d, name='%s'" % [id, player_name])

	var game_world = get_tree().get_first_node_in_group("game_world")
	print("🏷️ [NAME DEBUG] game_world found: %s" % (game_world != null))

	if game_world:
		print("🏷️ [NAME DEBUG] game_world.players keys: %s" % str(game_world.players.keys()))
		print("🏷️ [NAME DEBUG] Looking for player id %d in players dict" % id)

	if game_world and game_world.players.has(id):
		var player = game_world.players[id]
		print("🏷️ [NAME DEBUG] Found player node: %s, valid: %s" % [player, is_instance_valid(player)])

		if is_instance_valid(player):
			print("🏷️ [NAME DEBUG] Player has HealthBar: %s" % player.has_node("HealthBar"))

			if player.has_node("HealthBar"):
				var hb = player.get_node("HealthBar")
				print("🏷️ [NAME DEBUG] HealthBar node: %s" % hb)

				if hb.has_method("set_player_name"):
					hb.set_player_name(player_name)
					print("✅ [NAME DEBUG] Set player name '%s' for peer %d" % [player_name, id])
				else:
					print("❌ [NAME DEBUG] HealthBar doesn't have set_player_name method!")

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
		print("🏷️ [NAME DEBUG] Player %d not ready, retry %d/60" % [id, retries + 1])
		call_deferred("_update_player_name_label", id, player_name)
	else:
		print("❌ [NAME DEBUG] Failed to set name for player %d after 60 retries" % id)
		_name_update_retries.erase(id)

@rpc("authority", "reliable")
func player_left(id: int):
	if connected_players.has(id):
		print("Player %s left the game" % connected_players[id].name)
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
func relay_chat_message(sender_name: String, message: String) -> void:
	"""Server receives message from client and broadcasts to all"""
	if not is_host:
		return

	var sender_id = multiplayer.get_remote_sender_id()

	# Sanitize
	message = message.strip_edges()
	if message.is_empty() or message.length() > 200:
		return

	# Broadcast to all players (including sender)
	rpc("receive_chat_broadcast", sender_name, message, sender_id)
	# Emit for host's local UI
	chat_message_received.emit(sender_name, message, sender_id)

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
	print("Server requested authentication (legacy, no version)")
	authentication_required.emit()

@rpc("authority", "reliable")
func request_authentication_with_version(server_version: String) -> void:
	"""Server tells client to authenticate, with version check"""
	print("Server requested authentication (server version: %s, client version: %s)" % [server_version, NETWORK_VERSION])

	if server_version != NETWORK_VERSION:
		push_warning("⚠️ VERSION MISMATCH! Server: %s, Client: %s" % [server_version, NETWORK_VERSION])
		push_warning("   Connection blocked - client must update.")
		version_mismatch.emit(server_version, NETWORK_VERSION)
		# Block connection - don't allow authentication to proceed
		close_connection()
		return
	else:
		print("✅ Version match: %s" % NETWORK_VERSION)

	authentication_required.emit()

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
		print("🏷️ [SERVER] Emitting player_authenticated for peer %d: '%s'" % [peer_id, auth_player_name])
		player_authenticated.emit(peer_id, auth_player_name)

		# Send success to client
		rpc_id(peer_id, "receive_login_response", true, "", result.player_data)
		print("Player %s (peer %d) logged in successfully" % [username, peer_id])
	else:
		rpc_id(peer_id, "receive_login_response", false, result.error, {})
		print("Login failed for peer %d: %s" % [peer_id, result.error])

@rpc("any_peer", "reliable")
func handle_register_request(username: String, password_hash: String) -> void:
	"""Server handles registration request from client"""
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
		print("Account created: %s (peer %d)" % [username, peer_id])
	else:
		rpc_id(peer_id, "receive_register_response", false, result.error)
		print("Registration failed for peer %d: %s" % [peer_id, result.error])

@rpc("any_peer", "reliable")
func handle_guest_request(guest_name: String) -> void:
	"""Server handles guest login request"""
	if not is_host:
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Sanitize guest name
	guest_name = guest_name.strip_edges()
	if guest_name.is_empty() or guest_name.length() > 16:
		guest_name = "Guest_%d" % (randi() % 10000)

	# Check for duplicate names among connected players
	for pid in connected_players:
		if connected_players[pid].name.to_lower() == guest_name.to_lower():
			guest_name = "%s_%d" % [guest_name, randi() % 1000]
			break

	# Create guest player data (default values, no persistence)
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
		"vitality": 10,
		"luck": 10,
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
	print("🏷️ [SERVER] Emitting player_authenticated for guest peer %d: '%s'" % [peer_id, guest_name])
	player_authenticated.emit(peer_id, guest_name)

	# Send success to client
	rpc_id(peer_id, "receive_login_response", true, "", guest_data)
	print("Guest %s (peer %d) joined" % [guest_name, peer_id])

# --- Client-side auth response handlers ---

@rpc("authority", "reliable")
func receive_login_response(success: bool, error: String, player_data: Dictionary) -> void:
	"""Client receives login response from server"""
	if success:
		is_authenticated = true
		is_guest = player_data.get("id", 0) < 0  # Negative ID = guest
		local_player_data = player_data
		player_name = player_data.get("character_name", player_data.get("username", "Player"))

		# Start auto-save for non-guest players
		if not is_guest and DatabaseManager:
			var username = player_data.get("username", "")
			if not username.is_empty():
				DatabaseManager.start_auto_save(username)
				# Start session playtime tracking
				CharacterStats.start_session()

		login_success.emit(player_data)
		print("Login successful! Playing as: %s" % player_name)
	else:
		is_authenticated = false
		login_failed.emit(error)
		print("Login failed: %s" % error)

@rpc("authority", "reliable")
func receive_register_response(success: bool, error: String) -> void:
	"""Client receives registration response from server"""
	if success:
		register_success.emit()
		print("Registration successful!")
	else:
		register_failed.emit(error)
		print("Registration failed: %s" % error)

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
	print("📀 [NetworkManager] Server save timer started (every %.0fs)" % SERVER_SAVE_INTERVAL)

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

	var saved_count = 0
	for peer_id in authenticated_players:
		var auth_info = authenticated_players[peer_id]
		if auth_info.is_guest:
			continue

		var username = auth_info.username
		if _client_player_states.has(peer_id):
			var state = _client_player_states[peer_id]
			if DatabaseManager.save_player_data(username, state):
				saved_count += 1

	if saved_count > 0:
		print("📀 [NetworkManager] Server auto-saved %d player(s)" % saved_count)

func save_all_players() -> void:
	"""Force save all connected authenticated players (server-only)"""
	if not is_host:
		return
	_on_server_save_timer()

# --- Client → Server: Sync player state ---

@rpc("any_peer", "reliable")
func sync_player_state_to_server(state_data: Dictionary) -> void:
	"""Client sends their current state to server for persistence"""
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
	# print("📀 [NetworkManager] Received state from peer %d" % peer_id)  # Uncomment for debug

func _validate_player_state(state: Dictionary) -> bool:
	"""Validate that player state has reasonable values"""
	# Check required fields exist
	var required = ["position_x", "position_y", "level", "gold"]
	for field in required:
		if not state.has(field):
			return false

	# Sanity checks
	var level = state.get("level", 0)
	if level < 1 or level > 100:
		return false

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

	# Get stats from CharacterStats
	var stats_data = CharacterStats.get_save_data()
	state["level"] = stats_data.get("level", 1)
	state["xp"] = stats_data.get("experience", 0)
	state["gold"] = stats_data.get("gold", 100)
	state["strength"] = stats_data.get("strength", 10)
	state["agility"] = stats_data.get("agility", 10)
	state["vitality"] = stats_data.get("vitality", 10)
	state["luck"] = stats_data.get("luck", 10)
	state["character_stats"] = JSON.stringify(stats_data)

	# Get inventory
	var inv_data = InventorySystem.get_save_data()
	state["inventory"] = JSON.stringify(inv_data)

	# Playtime
	state["total_playtime_seconds"] = stats_data.get("total_playtime", 0)

	return state

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER HEALING SYSTEM (Healing Staff)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_player_heal(target_peer_id: int, heal_amount: float) -> void:
	"""Client requests to heal another player. Server validates and applies."""
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
		# Apply heal on server
		target_player.heal(heal_amount)
		print("💚 Server: Player %d healed player %d for %.1f" % [healer_peer_id, target_peer_id, heal_amount])

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
		print("💚 Client: Health synced to %.1f/%.1f" % [current_hp, max_hp])

func _get_local_player() -> Node:
	"""Get the local player node."""
	var game_world = get_node_or_null("/root/GameWorld")
	if game_world:
		return game_world.get_player_by_peer_id(multiplayer.get_unique_id())
	return null