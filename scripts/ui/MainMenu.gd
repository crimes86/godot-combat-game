extends Control
# Main menu for multiplayer demo

@onready var name_input = $MenuPanel/VBoxContainer/NameContainer/NameInput
@onready var host_button = $MenuPanel/VBoxContainer/HostButton
@onready var join_button = $MenuPanel/VBoxContainer/JoinButton
@onready var ip_input = $MenuPanel/VBoxContainer/JoinContainer/IPInput
@onready var join_container = $MenuPanel/VBoxContainer/JoinContainer
@onready var status_label = $MenuPanel/VBoxContainer/StatusLabel

func _ready():
	# Wait for nodes to be ready
	await get_tree().process_frame

	# Check if nodes exist
	if not name_input:
		push_error("name_input not found! Check node path: MenuPanel/VBoxContainer/NameContainer/NameInput")
		return
	if not ip_input:
		push_error("ip_input not found! Check node path: MenuPanel/VBoxContainer/JoinContainer/IPInput")
		return

	# Set default values
	name_input.text = "Player" + str(randi() % 1000)
	ip_input.text = "127.0.0.1"
	join_container.visible = false
	status_label.text = ""

	# Connect buttons
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)

	# Connect to NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)

func _on_host_pressed():
	# Set player name
	NetworkManager.set_player_name(name_input.text)

	# Try to host
	status_label.text = "Creating server..."
	if NetworkManager.host_game():
		# Server created, load game world
		_load_game_world()
	else:
		status_label.text = "Failed to create server!"

func _on_join_pressed():
	if not join_container.visible:
		# Show IP input
		join_container.visible = true
		join_button.text = "Connect"
	else:
		# Try to join
		NetworkManager.set_player_name(name_input.text)
		status_label.text = "Connecting to %s..." % ip_input.text

		if NetworkManager.join_game(ip_input.text):
			# Wait for connection result
			host_button.disabled = true
			join_button.disabled = true
		else:
			status_label.text = "Failed to connect!"

func _on_connected():
	status_label.text = "Connected! Loading game..."
	_load_game_world()

func _on_connection_failed():
	status_label.text = "Connection failed!"
	host_button.disabled = false
	join_button.disabled = false

func _on_server_created():
	status_label.text = "Server created! Loading game..."

func _load_game_world():
	# Small delay to ensure network is ready
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://main.tscn")