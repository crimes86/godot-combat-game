extends Control
## Main menu with authentication system
## Stone Gray UI theme matching CharacterUI

# Main menu nodes
@onready var name_input = $MenuPanel/VBoxContainer/NameContainer/NameInput
@onready var host_button = $MenuPanel/VBoxContainer/HostButton
@onready var join_button = $MenuPanel/VBoxContainer/JoinButton
@onready var ip_input = $MenuPanel/VBoxContainer/JoinContainer/IPInput
@onready var join_container = $MenuPanel/VBoxContainer/JoinContainer
@onready var status_label = $MenuPanel/VBoxContainer/StatusLabel
@onready var theme_music = $ThemeMusic

# Auth UI nodes
@onready var auth_panel = $AuthPanel
@onready var auth_username_input = $AuthPanel/VBoxContainer/UsernameContainer/UsernameInput
@onready var auth_password_input = $AuthPanel/VBoxContainer/PasswordContainer/PasswordInput
@onready var login_button = $AuthPanel/VBoxContainer/LoginButton
@onready var register_button = $AuthPanel/VBoxContainer/RegisterButton
@onready var guest_button = $AuthPanel/VBoxContainer/GuestButton
@onready var auth_status_label = $AuthPanel/VBoxContainer/AuthStatusLabel
@onready var auth_back_button = $AuthPanel/VBoxContainer/BackButton

# State
enum MenuState { MAIN, HOSTING, JOINING, AUTH_FOR_HOST, AUTH_FOR_JOIN }
var current_state: MenuState = MenuState.MAIN
var pending_ip: String = ""
var pending_host_player_data: Dictionary = {}  # Store auth data when hosting

func _ready():
	await get_tree().process_frame

	# Check required nodes
	if not name_input or not ip_input:
		push_error("MainMenu: Required nodes not found!")
		return

	# Set defaults
	name_input.text = "Player" + str(randi() % 1000)
	ip_input.text = "127.0.0.1"
	join_container.visible = false
	status_label.text = ""

	# Hide auth panel initially
	if auth_panel:
		auth_panel.visible = false

	# Connect main menu buttons
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
		host_button.mouse_entered.connect(_on_button_hover)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
		join_button.mouse_entered.connect(_on_button_hover)

	# Connect auth buttons
	if login_button:
		login_button.pressed.connect(_on_login_pressed)
		login_button.mouse_entered.connect(_on_button_hover)
	if register_button:
		register_button.pressed.connect(_on_register_pressed)
		register_button.mouse_entered.connect(_on_button_hover)
	if guest_button:
		guest_button.pressed.connect(_on_guest_pressed)
		guest_button.mouse_entered.connect(_on_button_hover)
	if auth_back_button:
		auth_back_button.pressed.connect(_on_auth_back_pressed)
		auth_back_button.mouse_entered.connect(_on_button_hover)

	# Connect NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.authentication_required.connect(_on_authentication_required)
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.login_failed.connect(_on_login_failed)
	NetworkManager.register_success.connect(_on_register_success)
	NetworkManager.register_failed.connect(_on_register_failed)

func _on_button_hover():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_hover_sound()

func _play_click_sound():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_click_sound()

# ═══════════════════════════════════════════════════════════════════════════
# MAIN MENU ACTIONS
# ═══════════════════════════════════════════════════════════════════════════

func _on_host_pressed():
	_play_click_sound()

	# Set player name
	NetworkManager.set_player_name(name_input.text)

	# Show auth panel for host to login/register or play as guest
	current_state = MenuState.AUTH_FOR_HOST
	_show_auth_panel_for_host()

func _on_join_pressed():
	_play_click_sound()

	if not join_container.visible:
		# Show IP input
		join_container.visible = true
		join_button.text = "Connect"
	else:
		# Try to connect
		NetworkManager.set_player_name(name_input.text)
		pending_ip = ip_input.text
		status_label.text = "Connecting to %s..." % pending_ip
		current_state = MenuState.JOINING

		if NetworkManager.join_game(pending_ip):
			host_button.disabled = true
			join_button.disabled = true
		else:
			status_label.text = "Failed to connect!"
			current_state = MenuState.MAIN

func _on_connected():
	status_label.text = "Connected! Waiting for server..."
	# Don't load game yet - wait for authentication

func _on_connection_failed():
	status_label.text = "Connection failed!"
	host_button.disabled = false
	join_button.disabled = false
	current_state = MenuState.MAIN

func _on_server_created():
	status_label.text = "Server created! Loading game..."
	_load_game_world()

# ═══════════════════════════════════════════════════════════════════════════
# AUTHENTICATION UI
# ═══════════════════════════════════════════════════════════════════════════

func _on_authentication_required():
	"""Server requested authentication - show auth panel for joining"""
	current_state = MenuState.AUTH_FOR_JOIN
	_show_auth_panel_for_join()

func _show_auth_panel_for_host():
	"""Show auth panel for host - authenticates locally before starting server"""
	if not auth_panel:
		# No auth panel - just host as guest
		_start_host_as_guest()
		return

	# Initialize database for local auth check
	if DatabaseManager:
		DatabaseManager.initialize_database()

	# Hide main menu panel, show auth panel
	_set_menu_panel_visible(false)
	auth_panel.visible = true
	auth_status_label.text = "Login to save progress, or play as guest"

	# Pre-fill username
	if auth_username_input:
		auth_username_input.text = name_input.text
	if auth_password_input:
		auth_password_input.text = ""

	_set_auth_buttons_enabled(true)

func _show_auth_panel_for_join():
	"""Show auth panel for joining client"""
	if not auth_panel:
		push_warning("Auth panel not found - proceeding as guest")
		NetworkManager.send_guest_login(name_input.text)
		return

	# Hide main menu panel, show auth panel
	_set_menu_panel_visible(false)
	auth_panel.visible = true
	auth_status_label.text = ""

	if auth_username_input:
		auth_username_input.text = name_input.text
	if auth_password_input:
		auth_password_input.text = ""

	_set_auth_buttons_enabled(true)

func _hide_auth_panel():
	"""Hide the authentication panel and show main menu"""
	if auth_panel:
		auth_panel.visible = false
	_set_menu_panel_visible(true)

func _set_menu_panel_visible(visible: bool):
	"""Show or hide the main menu panel"""
	var menu_panel = get_node_or_null("MenuPanel")
	if menu_panel:
		menu_panel.visible = visible

func _set_auth_buttons_enabled(enabled: bool):
	if login_button:
		login_button.disabled = not enabled
	if register_button:
		register_button.disabled = not enabled
	if guest_button:
		guest_button.disabled = not enabled

func _start_host_as_guest():
	"""Start hosting as guest (no persistence)"""
	pending_host_player_data = {}
	status_label.text = "Creating server..."
	if NetworkManager.host_game(NetworkManager.DEFAULT_PORT, {}):
		status_label.text = "Server created! Loading..."
	else:
		status_label.text = "Failed to create server!"
		current_state = MenuState.MAIN

func _start_host_with_account(player_data: Dictionary):
	"""Start hosting with authenticated account"""
	pending_host_player_data = player_data
	status_label.text = "Creating server..."
	if NetworkManager.host_game(NetworkManager.DEFAULT_PORT, player_data):
		status_label.text = "Server created! Loading..."
	else:
		status_label.text = "Failed to create server!"
		current_state = MenuState.MAIN

func _on_login_pressed():
	_play_click_sound()

	var username = auth_username_input.text.strip_edges() if auth_username_input else ""
	var password = auth_password_input.text if auth_password_input else ""

	# Validate inputs
	if username.is_empty():
		auth_status_label.text = "Please enter a username"
		return
	if password.is_empty():
		auth_status_label.text = "Please enter a password"
		return

	auth_status_label.text = "Logging in..."
	_set_auth_buttons_enabled(false)

	if current_state == MenuState.AUTH_FOR_HOST:
		# Host authenticates locally
		_host_local_login(username, password)
	else:
		# Client sends to server
		NetworkManager.send_login(username, password)

func _on_register_pressed():
	_play_click_sound()

	var username = auth_username_input.text.strip_edges() if auth_username_input else ""
	var password = auth_password_input.text if auth_password_input else ""

	# Validate inputs
	if username.is_empty():
		auth_status_label.text = "Please enter a username"
		return
	if password.length() < 4:
		auth_status_label.text = "Password must be at least 4 characters"
		return

	auth_status_label.text = "Creating account..."
	_set_auth_buttons_enabled(false)

	if current_state == MenuState.AUTH_FOR_HOST:
		# Host registers locally
		_host_local_register(username, password)
	else:
		# Client sends to server
		NetworkManager.send_register(username, password)

func _on_guest_pressed():
	_play_click_sound()

	if current_state == MenuState.AUTH_FOR_HOST:
		# Host starts as guest
		_hide_auth_panel()
		_start_host_as_guest()
	else:
		# Client requests guest login from server
		var guest_name = name_input.text.strip_edges()
		if guest_name.is_empty():
			guest_name = "Guest_%d" % (randi() % 10000)
		auth_status_label.text = "Joining as guest..."
		_set_auth_buttons_enabled(false)
		NetworkManager.send_guest_login(guest_name)

func _on_auth_back_pressed():
	_play_click_sound()
	_hide_auth_panel()

	if current_state == MenuState.AUTH_FOR_JOIN:
		# Was trying to join - close connection
		NetworkManager.close_connection()

	# Reset main menu state
	host_button.disabled = false
	join_button.disabled = false
	status_label.text = ""
	current_state = MenuState.MAIN

# ═══════════════════════════════════════════════════════════════════════════
# HOST LOCAL AUTHENTICATION
# ═══════════════════════════════════════════════════════════════════════════

func _host_local_login(username: String, password: String):
	"""Host authenticates locally against the database"""
	if not DatabaseManager:
		auth_status_label.text = "Database not available"
		_set_auth_buttons_enabled(true)
		return

	# Hash password the same way NetworkManager does for transport
	var password_hash = _hash_password(password)
	var result = DatabaseManager.authenticate(username, password_hash)

	if result.success:
		auth_status_label.text = "Login successful!"
		_hide_auth_panel()
		_start_host_with_account(result.player_data)
	else:
		auth_status_label.text = result.error
		_set_auth_buttons_enabled(true)

func _host_local_register(username: String, password: String):
	"""Host registers locally in the database"""
	if not DatabaseManager:
		auth_status_label.text = "Database not available"
		_set_auth_buttons_enabled(true)
		return

	# Hash password the same way NetworkManager does
	var password_hash = _hash_password(password)
	var result = DatabaseManager.create_account(username, password_hash)

	if result.success:
		auth_status_label.text = "Account created! You can now log in."
		_set_auth_buttons_enabled(true)
	else:
		auth_status_label.text = result.error
		_set_auth_buttons_enabled(true)

func _hash_password(password: String) -> String:
	"""Hash password for storage (matches NetworkManager's transport hash)"""
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(password.to_utf8_buffer())
	return ctx.finish().hex_encode()

# ═══════════════════════════════════════════════════════════════════════════
# AUTH RESPONSE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_login_success(player_data: Dictionary):
	auth_status_label.text = "Login successful!"
	_hide_auth_panel()
	status_label.text = "Loading game..."
	_load_game_world()

func _on_login_failed(error: String):
	auth_status_label.text = error
	_set_auth_buttons_enabled(true)

func _on_register_success():
	auth_status_label.text = "Account created! You can now log in."
	_set_auth_buttons_enabled(true)

func _on_register_failed(error: String):
	auth_status_label.text = error
	_set_auth_buttons_enabled(true)

# ═══════════════════════════════════════════════════════════════════════════
# GAME LOADING
# ═══════════════════════════════════════════════════════════════════════════

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
