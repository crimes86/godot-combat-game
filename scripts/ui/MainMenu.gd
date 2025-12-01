extends Control
## Main menu with authentication system
## Stone Gray UI theme matching CharacterUI

# Server configuration
const PRODUCTION_SERVER_IP = "167.99.55.245"

# Main menu nodes
@onready var name_input = $MenuPanel/VBoxContainer/NameContainer/NameInput
@onready var host_button = $MenuPanel/VBoxContainer/HostButton
@onready var join_button = $MenuPanel/VBoxContainer/JoinButton
@onready var ip_input = $MenuPanel/VBoxContainer/JoinContainer/IPInput
@onready var join_container = $MenuPanel/VBoxContainer/JoinContainer
@onready var status_label = $MenuPanel/VBoxContainer/StatusLabel
@onready var theme_music = $ThemeMusic

# Dev mode state
var is_dev_mode: bool = false

# Auth UI nodes
@onready var auth_panel = $AuthPanel
@onready var auth_username_input = $AuthPanel/VBoxContainer/UsernameContainer/UsernameInput
@onready var auth_password_input = $AuthPanel/VBoxContainer/PasswordContainer/PasswordInput
@onready var login_button = $AuthPanel/VBoxContainer/LoginButton
@onready var register_button = $AuthPanel/VBoxContainer/RegisterButton
@onready var guest_button = $AuthPanel/VBoxContainer/GuestButton
@onready var auth_status_label = $AuthPanel/VBoxContainer/AuthStatusLabel
@onready var auth_back_button = $AuthPanel/VBoxContainer/BackButton

# Bottom buttons
@onready var settings_button = $BottomButtons/SettingsButton
@onready var credits_button = $BottomButtons/CreditsButton
@onready var exit_button = $BottomButtons/ExitButton

# Settings panel nodes
@onready var settings_panel = $SettingsPanel
@onready var master_volume_slider = $SettingsPanel/VBoxContainer/MasterVolumeContainer/MasterVolumeSlider
@onready var master_volume_value = $SettingsPanel/VBoxContainer/MasterVolumeContainer/MasterVolumeValue
@onready var music_volume_slider = $SettingsPanel/VBoxContainer/MusicVolumeContainer/MusicVolumeSlider
@onready var music_volume_value = $SettingsPanel/VBoxContainer/MusicVolumeContainer/MusicVolumeValue
@onready var sfx_volume_slider = $SettingsPanel/VBoxContainer/SFXVolumeContainer/SFXVolumeSlider
@onready var sfx_volume_value = $SettingsPanel/VBoxContainer/SFXVolumeContainer/SFXVolumeValue
@onready var fullscreen_check = $SettingsPanel/VBoxContainer/FullscreenContainer/FullscreenCheck
@onready var vsync_check = $SettingsPanel/VBoxContainer/VSyncContainer/VSyncCheck
@onready var settings_back_button = $SettingsPanel/VBoxContainer/SettingsBackButton

# Credits panel nodes
@onready var credits_panel = $CreditsPanel
@onready var credits_back_button = $CreditsPanel/VBoxContainer/CreditsBackButton

# State
enum MenuState { MAIN, HOSTING, JOINING, AUTH_FOR_HOST, AUTH_FOR_JOIN }
var current_state: MenuState = MenuState.MAIN
var pending_ip: String = ""
var pending_host_player_data: Dictionary = {}  # Store auth data when hosting

func _ready():
	await get_tree().process_frame

	# Ensure all game UI autoloads are hidden when returning to main menu
	_reset_game_ui()

	# Dev mode only available in editor or debug builds (not production exports)
	is_dev_mode = OS.has_feature("editor") or OS.is_debug_build()

	# Check required nodes
	if not name_input or not ip_input:
		push_error("MainMenu: Required nodes not found!")
		return

	# Set defaults
	name_input.text = "Player" + str(randi() % 1000)
	ip_input.text = PRODUCTION_SERVER_IP  # Always use production server
	join_container.visible = false
	status_label.text = ""

	# Hide auth panel initially
	if auth_panel:
		auth_panel.visible = false

	# Hide host button unless in dev mode
	if host_button:
		if is_dev_mode:
			host_button.pressed.connect(_on_host_pressed)
			host_button.mouse_entered.connect(_on_button_hover)
			host_button.text = "HOST (DEV)"
		else:
			host_button.visible = false

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

	# Connect bottom buttons (Settings, Credits, Exit)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
		settings_button.mouse_entered.connect(_on_button_hover)
	if credits_button:
		credits_button.pressed.connect(_on_credits_pressed)
		credits_button.mouse_entered.connect(_on_button_hover)
	if exit_button:
		exit_button.pressed.connect(_on_exit_pressed)
		exit_button.mouse_entered.connect(_on_button_hover)

	# Connect settings panel controls
	if settings_back_button:
		settings_back_button.pressed.connect(_on_settings_back_pressed)
		settings_back_button.mouse_entered.connect(_on_button_hover)
	if master_volume_slider:
		master_volume_slider.value_changed.connect(_on_master_volume_changed)
	if music_volume_slider:
		music_volume_slider.value_changed.connect(_on_music_volume_changed)
	if sfx_volume_slider:
		sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	if fullscreen_check:
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if vsync_check:
		vsync_check.toggled.connect(_on_vsync_toggled)

	# Connect credits panel
	if credits_back_button:
		credits_back_button.pressed.connect(_on_credits_back_pressed)
		credits_back_button.mouse_entered.connect(_on_button_hover)

	# Hide settings and credits panels initially
	if settings_panel:
		settings_panel.visible = false
	if credits_panel:
		credits_panel.visible = false

	# Initialize settings from current state
	_load_settings()

	# Connect NetworkManager signals
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.authentication_required.connect(_on_authentication_required)
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.login_failed.connect(_on_login_failed)
	NetworkManager.register_success.connect(_on_register_success)
	NetworkManager.register_failed.connect(_on_register_failed)
	NetworkManager.version_mismatch.connect(_on_version_mismatch)

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

	# In dev mode, allow custom IP input
	if is_dev_mode:
		if not join_container.visible:
			# Show IP input for dev mode
			join_container.visible = true
			join_button.text = "Connect"
			return

	# Connect to server (production IP or dev mode custom IP)
	NetworkManager.set_player_name(name_input.text)
	pending_ip = ip_input.text if is_dev_mode else PRODUCTION_SERVER_IP
	status_label.text = "Connecting to server..."
	current_state = MenuState.JOINING

	if NetworkManager.join_game(pending_ip):
		if host_button:
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

func _on_version_mismatch(server_version: String, client_version: String):
	"""Block connection due to version mismatch"""
	status_label.text = "UPDATE REQUIRED\nYour version: %s\nServer version: %s\n\nPlease download the latest version." % [client_version, server_version]
	status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))  # Red error

	# Re-enable buttons so player can retry after updating
	if host_button:
		host_button.disabled = false
	join_button.disabled = false
	current_state = MenuState.MAIN

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

# ═══════════════════════════════════════════════════════════════════════════
# SETTINGS, CREDITS, EXIT
# ═══════════════════════════════════════════════════════════════════════════

func _on_settings_pressed():
	_play_click_sound()
	_set_menu_panel_visible(false)
	if settings_panel:
		settings_panel.visible = true

func _on_settings_back_pressed():
	_play_click_sound()
	if settings_panel:
		settings_panel.visible = false
	_set_menu_panel_visible(true)
	_save_settings()

func _on_credits_pressed():
	_play_click_sound()
	_set_menu_panel_visible(false)
	if credits_panel:
		credits_panel.visible = true

func _on_credits_back_pressed():
	_play_click_sound()
	if credits_panel:
		credits_panel.visible = false
	_set_menu_panel_visible(true)

func _on_exit_pressed():
	_play_click_sound()
	# Save settings before exiting
	_save_settings()
	get_tree().quit()

# ═══════════════════════════════════════════════════════════════════════════
# SETTINGS CONTROLS
# ═══════════════════════════════════════════════════════════════════════════

func _on_master_volume_changed(value: float):
	if master_volume_value:
		master_volume_value.text = "%d%%" % int(value)
	# Convert 0-100 to dB (0 = -40dB, 100 = 0dB)
	var db = lerp(-40.0, 0.0, value / 100.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

func _on_music_volume_changed(value: float):
	if music_volume_value:
		music_volume_value.text = "%d%%" % int(value)
	# Apply to theme music and music bus if exists
	var db = lerp(-40.0, 0.0, value / 100.0)
	if theme_music:
		theme_music.volume_db = db + 10.0  # Offset since base is -10
	# Try to set Music bus if it exists
	var music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, db)

func _on_sfx_volume_changed(value: float):
	if sfx_volume_value:
		sfx_volume_value.text = "%d%%" % int(value)
	# Apply to SFX bus if it exists
	var db = lerp(-40.0, 0.0, value / 100.0)
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, db)
	# Also update SoundManager if available
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("set_sfx_volume"):
		sound_manager.set_sfx_volume(value / 100.0)

func _on_fullscreen_toggled(enabled: bool):
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_vsync_toggled(enabled: bool):
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _load_settings():
	"""Load settings from config file or use defaults"""
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")

	if err == OK:
		# Load saved values
		if master_volume_slider:
			master_volume_slider.value = config.get_value("audio", "master_volume", 80.0)
		if music_volume_slider:
			music_volume_slider.value = config.get_value("audio", "music_volume", 70.0)
		if sfx_volume_slider:
			sfx_volume_slider.value = config.get_value("audio", "sfx_volume", 80.0)
		if fullscreen_check:
			fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
		if vsync_check:
			vsync_check.button_pressed = config.get_value("display", "vsync", true)
	else:
		# Apply defaults
		if master_volume_slider:
			_on_master_volume_changed(master_volume_slider.value)
		if music_volume_slider:
			_on_music_volume_changed(music_volume_slider.value)
		if sfx_volume_slider:
			_on_sfx_volume_changed(sfx_volume_slider.value)

	# Apply current fullscreen/vsync state
	if fullscreen_check:
		var is_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fullscreen_check.button_pressed = is_fullscreen
	if vsync_check:
		var is_vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		vsync_check.button_pressed = is_vsync

func _save_settings():
	"""Save settings to config file"""
	var config = ConfigFile.new()

	if master_volume_slider:
		config.set_value("audio", "master_volume", master_volume_slider.value)
	if music_volume_slider:
		config.set_value("audio", "music_volume", music_volume_slider.value)
	if sfx_volume_slider:
		config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	if fullscreen_check:
		config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	if vsync_check:
		config.set_value("display", "vsync", vsync_check.button_pressed)

	config.save("user://settings.cfg")

# ═══════════════════════════════════════════════════════════════════════════
# GAME UI RESET (called when returning from game)
# ═══════════════════════════════════════════════════════════════════════════

func _reset_game_ui():
	"""Hide all game UI autoloads when returning to main menu"""
	# Hide GroupUI (CanvasLayer autoload) - also hides invite popup
	if GroupUI:
		GroupUI.visible = false
		GroupUI._hide_popup()  # Hide invite popup too
	# Hide QuestTrackerUI (CanvasLayer autoload)
	if QuestTrackerUI:
		QuestTrackerUI.visible = false
	# Hide BugReportUI (CanvasLayer autoload)
	if BugReportUI:
		BugReportUI.visible = false
	# Hide AccountAdmin (CanvasLayer autoload)
	if AccountAdmin:
		AccountAdmin.visible = false
	# Hide NotificationManager canvas layer
	if NotificationManager:
		var notif_canvas = NotificationManager.get_node_or_null("NotificationCanvas")
		if notif_canvas:
			notif_canvas.visible = false
	# Hide TutorialManager UI elements
	if TutorialManager:
		if TutorialManager.get("tutorial_ui") and TutorialManager.tutorial_ui:
			TutorialManager.tutorial_ui.visible = false
		if TutorialManager.get("ui_arrow_canvas") and TutorialManager.ui_arrow_canvas:
			TutorialManager.ui_arrow_canvas.visible = false
	# Reset CursorManager
	if CursorManager and CursorManager.has_method("reset_cursor"):
		CursorManager.reset_cursor()

	# Clean up any orphaned game overlays (logout timer, spawn hints, tutorial blackout, etc.)
	var root = get_tree().root
	var nodes_to_remove: Array[Node] = []
	for child in root.get_children():
		if child.name in ["LogoutTimerOverlay", "SpawnHintsOverlay", "GameMenu", "TutorialBlackout"]:
			nodes_to_remove.append(child)
	for node in nodes_to_remove:
		node.queue_free()
