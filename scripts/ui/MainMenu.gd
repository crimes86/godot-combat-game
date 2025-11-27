extends Control
## Main menu for multiplayer demo
## Stone Gray UI theme matching CharacterUI

@onready var name_input = $MenuPanel/VBoxContainer/NameContainer/NameInput
@onready var host_button = $MenuPanel/VBoxContainer/HostButton
@onready var join_button = $MenuPanel/VBoxContainer/JoinButton
@onready var ip_input = $MenuPanel/VBoxContainer/JoinContainer/IPInput
@onready var join_container = $MenuPanel/VBoxContainer/JoinContainer
@onready var status_label = $MenuPanel/VBoxContainer/StatusLabel
@onready var theme_music = $ThemeMusic

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
		host_button.mouse_entered.connect(_on_button_hover)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
		join_button.mouse_entered.connect(_on_button_hover)

	# Connect to NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)

func _on_button_hover():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_hover_sound()

func _on_host_pressed():
	# Play button click sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_click_sound()

	# Set player name
	NetworkManager.set_player_name(name_input.text)

	# Try to host
	status_label.text = "Creating server..."
	if NetworkManager.host_game():
		# Don't load immediately, wait for server to be ready
		status_label.text = "Server created! Loading..."
		# Server created signal will trigger the load
	else:
		status_label.text = "Failed to create server!"

func _on_join_pressed():
	# Play button click sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_click_sound()

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
	_load_game_world()

func _load_game_world():
	# Fade out music before transitioning
	if theme_music and theme_music.playing:
		var fade_tween = create_tween()
		fade_tween.tween_property(theme_music, "volume_db", -40.0, 0.8)
		await fade_tween.finished
		theme_music.stop()

	# Small delay to ensure network is ready
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://main.tscn")
