extends Node
# NetworkManager.gd - Core multiplayer functionality

signal player_connected(id)
signal player_disconnected(id)
signal connected_to_server
signal connection_failed
signal server_created

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 4

var peer = null
var connected_players = {}
var player_name = "Player"
var is_host = false

func _ready():
	# Set this as singleton
	set_process(false)

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# Host a game server
func host_game(port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)

	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_host = true

		# Add host to player list
		var host_id = multiplayer.get_unique_id()
		connected_players[host_id] = {
			"name": player_name,
			"ready": true
		}

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
	if peer:
		peer.close()
		peer = null
		multiplayer.multiplayer_peer = null
		connected_players.clear()
		is_host = false
		print("Connection closed")

# Called when a player connects (server only)
func _on_player_connected(id: int):
	print("Player connected: %d" % id)

	# Send current player list to new player
	if is_host:
		rpc_id(id, "receive_player_list", connected_players)

		# Add new player to list
		connected_players[id] = {
			"name": "Player%d" % id,
			"ready": false
		}

		# Notify all players of new connection
		rpc("player_joined", id, connected_players[id])

	player_connected.emit(id)

# Called when a player disconnects
func _on_player_disconnected(id: int):
	print("Player disconnected: %d" % id)

	if connected_players.has(id):
		connected_players.erase(id)

		# Notify remaining players
		if is_host:
			rpc("player_left", id)

	player_disconnected.emit(id)

# Called when we connect to server (client only)
func _on_connected_to_server():
	print("Connected to server!")
	var my_id = multiplayer.get_unique_id()

	# Send our info to server
	rpc_id(1, "register_player", my_id, player_name)

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