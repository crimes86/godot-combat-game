extends Node
# NetworkManager.gd - Core multiplayer functionality

signal player_connected(id)
signal player_disconnected(id)
signal connected_to_server
signal connection_failed
signal server_created
signal chat_message_received(sender_name: String, message: String, sender_id: int)

# Authentication signals
signal login_success(player_data: Dictionary)
signal login_failed(error: String)
signal register_success()
signal register_failed(error: String)
signal authentication_required()  # Emitted when client connects and needs to auth

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 4

var peer = null
var connected_players = {}
var player_name = "Player"
var is_host = false

# Authentication state
var authenticated_players: Dictionary = {}  # peer_id -> {username, player_data, is_guest}
var is_authenticated: bool = false  # Client-side: are we authenticated?
var is_guest: bool = false  # Client-side: are we playing as guest?
var local_player_data: Dictionary = {}  # Client-side: our player data from server

func _ready():
	# Set this as singleton
	set_process(false)

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
		connected_players[host_id] = {
			"name": player_name,
			"ready": true
		}

		# Store host's auth info
		var host_is_guest = host_player_data.is_empty()
		authenticated_players[host_id] = {
			"username": player_name if host_is_guest else host_player_data.get("username", player_name),
			"player_data": host_player_data,
			"is_guest": host_is_guest
		}
		local_player_data = host_player_data
		is_guest = host_is_guest

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
	# Save player data before disconnecting (if authenticated and not guest)
	if is_authenticated and not is_guest and not local_player_data.is_empty():
		var username = local_player_data.get("username", "")
		if not username.is_empty() and DatabaseManager:
			DatabaseManager.logout_player(username)

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
		# Tell the client they need to authenticate
		rpc_id(id, "request_authentication")

	player_connected.emit(id)

# Called when a player disconnects
func _on_player_disconnected(id: int):
	print("Player disconnected: %d" % id)

	# Handle logout for authenticated players (server-side)
	if is_host and authenticated_players.has(id):
		var auth_info = authenticated_players[id]
		if not auth_info.is_guest and DatabaseManager:
			var username = auth_info.username
			# TODO: Save player state before logout
			DatabaseManager.logout_player(username)
		authenticated_players.erase(id)
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
	print("Player %s joined the game" % player_info.name)

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
	"""Server tells client to authenticate"""
	print("Server requested authentication")
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

		# Notify all players
		rpc("player_joined", peer_id, connected_players[peer_id])

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

	# Notify all players
	rpc("player_joined", peer_id, connected_players[peer_id])

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