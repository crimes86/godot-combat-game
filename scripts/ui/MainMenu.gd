extends Control
## Main menu with authentication system
## Ashbane medieval fantasy UI theme (WoW/Shadowbane inspired)

# Server configuration
const PRODUCTION_SERVER_IP = "167.99.55.245"

# ═══════════════════════════════════════════════════════════════════════════
# ASHBANE THEME COLORS - Medieval fantasy (WoW/Shadowbane inspired)
# ═══════════════════════════════════════════════════════════════════════════
const ASHBANE_BG_DARK = Color(0.05, 0.04, 0.03, 0.98)  # Warm charcoal
const ASHBANE_BG_PANEL = Color(0.08, 0.06, 0.05, 0.95)  # Dark brown-gray
const ASHBANE_ACCENT_PRIMARY = Color(0.7, 0.15, 0.1, 1.0)  # Deep crimson
const ASHBANE_ACCENT_GOLD = Color(0.85, 0.65, 0.2, 1.0)  # Antique gold
const ASHBANE_BORDER_GLOW = Color(0.5, 0.12, 0.08, 0.6)  # Crimson glow
const ASHBANE_TEXT_PRIMARY = Color(0.95, 0.90, 0.82, 1.0)  # Parchment white
const ASHBANE_TEXT_SECONDARY = Color(0.55, 0.50, 0.45, 1.0)  # Warm gray
# Legacy alias for compatibility
const ASHBANE_ACCENT_CYAN = ASHBANE_ACCENT_PRIMARY

# Tier colors - matching backend definitions
const TIER_COLORS = {
	"initiate": Color(0.4, 0.4, 0.4),       # #666666 - Gray
	"bronze": Color(0.804, 0.498, 0.196),   # #CD7F32 - Bronze
	"silver": Color(0.753, 0.753, 0.753),   # #C0C0C0 - Silver
	"gold": Color(1.0, 0.843, 0.0),         # #FFD700 - Gold
	"platinum": Color(0.898, 0.894, 0.886), # #E5E4E2 - Pale platinum
	"diamond": Color(0.725, 0.949, 1.0),    # #B9F2FF - Cyan/Turquoise
	"legendary": Color(1.0, 0.4, 0.0),      # #FF6600 - Orange
	"mythic": Color(1.0, 0.0, 1.0)          # #FF00FF - Magenta
}

# Rarity colors for achievement breakdown - Ashbane theme
const RARITY_COLORS = {
	"common": Color(0.5, 0.48, 0.44),    # Ashen gray
	"uncommon": Color(0.35, 0.6, 0.25),  # Forest green
	"rare": Color(0.3, 0.5, 0.9),        # Blue
	"epic": Color(0.6, 0.2, 0.8),        # Purple
	"legendary": Color(1.0, 0.5, 0.1)    # Orange
}

# Main menu nodes
@onready var name_input = $MenuPanel/VBoxContainer/NameContainer/NameInput
@onready var host_button = $MenuPanel/VBoxContainer/HostButton
@onready var join_button = $MenuPanel/VBoxContainer/JoinButton
@onready var ip_input = $MenuPanel/VBoxContainer/JoinContainer/IPInput
@onready var join_container = $MenuPanel/VBoxContainer/JoinContainer
@onready var status_label = $MenuPanel/VBoxContainer/StatusLabel
var cancel_connect_button: Button = null
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
@onready var resolution_option = $SettingsPanel/VBoxContainer/ResolutionContainer/ResolutionOption
@onready var settings_back_button = $SettingsPanel/VBoxContainer/SettingsBackButton

# Resolution presets (width x height)
const RESOLUTIONS = [
	Vector2i(1280, 720),   # 720p (default)
	Vector2i(1366, 768),   # Common laptop
	Vector2i(1600, 900),   # 900p
	Vector2i(1920, 1080),  # 1080p
	Vector2i(2560, 1440),  # 1440p
]

# Credits panel nodes
@onready var credits_panel = $CreditsPanel
@onready var credits_back_button = $CreditsPanel/VBoxContainer/CreditsBackButton

# Server select panel nodes (for guest play)
@onready var server_select_panel = $ServerSelectPanel
@onready var server_option = $ServerSelectPanel/VBoxContainer/ServerOption
@onready var custom_ip_input = $ServerSelectPanel/VBoxContainer/CustomIPContainer/CustomIPInput
@onready var server_status_label = $ServerSelectPanel/VBoxContainer/ServerStatusLabel
@onready var connect_guest_button = $ServerSelectPanel/VBoxContainer/ConnectGuestButton
@onready var server_select_back_button = $ServerSelectPanel/VBoxContainer/ServerSelectBackButton
# Known servers configuration
const KNOWN_SERVERS = {
	"Production (Dreadland)": "167.99.55.245",
	"LAN (Local Network)": "192.168.28.211",
}

# State
enum MenuState { MAIN, ASHBANE_SCREEN, HOSTING, JOINING, AUTH_FOR_HOST, AUTH_FOR_JOIN, GUEST_SERVER_SELECT }
var current_state: MenuState = MenuState.MAIN
var pending_ip: String = ""
var pending_host_player_data: Dictionary = {}  # Store auth data when hosting
var pending_action: String = ""  # "host" or "join" - what to do after Ashbane screen

func _ready():
	await get_tree().process_frame

	# Start menu music via SoundManager (persists across scenes until entering game world)
	if SoundManager:
		SoundManager.play_menu_music()

	# Stop the scene's ThemeMusic if it's playing (we use SoundManager instead now)
	if theme_music and theme_music.playing:
		theme_music.stop()

	# Ensure all game UI autoloads are hidden when returning to main menu
	_reset_game_ui()

	# Dev mode only available in editor or debug builds (not production exports)
	is_dev_mode = OS.has_feature("editor") or OS.is_debug_build()

	# Check required nodes
	if not name_input or not ip_input:
		push_error("MainMenu: Required nodes not found!")
		return

	# Apply cyberpunk styling to all panels
	_apply_cyberpunk_theme()

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

	# Create cancel connection button (hidden by default)
	_create_cancel_connect_button()

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
	if resolution_option:
		_setup_resolution_options()
		resolution_option.item_selected.connect(_on_resolution_selected)

	# Connect credits panel
	if credits_back_button:
		credits_back_button.pressed.connect(_on_credits_back_pressed)
		credits_back_button.mouse_entered.connect(_on_button_hover)

	# Connect server select panel buttons
	if connect_guest_button:
		connect_guest_button.pressed.connect(_on_connect_guest_pressed)
		connect_guest_button.mouse_entered.connect(_on_button_hover)
	if server_select_back_button:
		server_select_back_button.pressed.connect(_on_server_select_back_pressed)
		server_select_back_button.mouse_entered.connect(_on_button_hover)

	# Setup server select panel
	_setup_server_select_panel()

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

	# Setup Ashbane integration (Link Gaming Accounts)
	_setup_ashbane_integration()

	# Check for client updates (non-blocking)
	_check_for_updates()

	# Check if user is already authenticated (saved token)
	if AshbaneAuth and AshbaneAuth.is_logged_in():
		# Already logged in - go straight to Armory
		LogManager.info("User already authenticated, transitioning to Armory", "ashbane")
		_set_menu_panel_visible(false)
		await get_tree().create_timer(0.5).timeout  # Brief delay for scene to fully load
		_transition_to_armory()
	else:
		# IMPORTANT: Show Ashbane panel FIRST (authenticate before playing)
		# Hide the normal menu panel and show Ashbane panel on startup
		_set_menu_panel_visible(false)
		_show_ashbane_panel()

		# Check if we were booted back due to connection failure
		if AshbaneAuth:
			var pending_error = AshbaneAuth.get_and_clear_pending_error()
			if pending_error != "":
				# Show the error message after a brief delay so UI is ready
				await get_tree().create_timer(0.3).timeout
				_on_ashbane_auth_failed(pending_error)

func _on_button_hover():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_hover_sound()

func _play_click_sound():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_click_sound()

# ═══════════════════════════════════════════════════════════════════════════
# CYBERPUNK THEME STYLING
# ═══════════════════════════════════════════════════════════════════════════

func _apply_cyberpunk_theme():
	"""Apply Ashbane medieval fantasy theme to all panels"""
	# Create full-screen dark background
	_create_theme_background()

	# Style all panels
	_style_menu_panel()
	_style_auth_panel()
	_style_settings_panel()
	_style_credits_panel()

	# Style bottom buttons
	_style_bottom_buttons()

func _create_theme_background():
	"""Create the dark atmospheric background for the entire menu"""
	var bg = ColorRect.new()
	bg.name = "ThemeBackground"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = ASHBANE_BG_DARK
	bg.z_index = -10  # Behind everything
	add_child(bg)
	move_child(bg, 0)

func _style_menu_panel():
	"""Style the main menu panel with cyberpunk aesthetic"""
	var menu_panel = get_node_or_null("MenuPanel")
	if not menu_panel:
		return

	# Apply panel style
	var style = _create_panel_style()
	menu_panel.add_theme_stylebox_override("panel", style)

	# Add corner decorations
	_add_corner_decorations(menu_panel)

	# Style the title if exists
	var title_label = menu_panel.get_node_or_null("VBoxContainer/TitleLabel")
	if title_label:
		title_label.add_theme_font_size_override("font_size", 32)
		title_label.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)

	# Style text inputs
	_style_input_fields(menu_panel)

	# Style all buttons in the menu panel
	_style_panel_buttons(menu_panel)

	# Style status label
	if status_label:
		status_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)

func _style_auth_panel():
	"""Style the authentication panel with cyberpunk aesthetic"""
	if not auth_panel:
		return

	# Apply panel style
	var style = _create_panel_style()
	auth_panel.add_theme_stylebox_override("panel", style)

	# Add corner decorations
	_add_corner_decorations(auth_panel)

	# Style text inputs
	_style_input_fields(auth_panel)

	# Style all buttons
	_style_panel_buttons(auth_panel)

	# Style status label
	if auth_status_label:
		auth_status_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)

func _style_settings_panel():
	"""Style the settings panel with cyberpunk aesthetic"""
	if not settings_panel:
		return

	# Apply panel style
	var style = _create_panel_style()
	settings_panel.add_theme_stylebox_override("panel", style)

	# Add corner decorations
	_add_corner_decorations(settings_panel)

	# Style the title
	var title = settings_panel.get_node_or_null("VBoxContainer/SettingsTitle")
	if title:
		title.add_theme_font_size_override("font_size", 28)
		title.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)

	# Style all labels
	_style_panel_labels(settings_panel)

	# Style sliders
	_style_sliders(settings_panel)

	# Style checkboxes
	_style_checkboxes(settings_panel)

	# Style option button
	if resolution_option:
		_style_option_button(resolution_option)

	# Style back button
	if settings_back_button:
		_style_ashbane_button(settings_back_button, ASHBANE_ACCENT_CYAN, false)

func _style_credits_panel():
	"""Style the credits panel with cyberpunk aesthetic"""
	if not credits_panel:
		return

	# Apply panel style
	var style = _create_panel_style()
	credits_panel.add_theme_stylebox_override("panel", style)

	# Add corner decorations
	_add_corner_decorations(credits_panel)

	# Style all labels
	_style_panel_labels(credits_panel)

	# Style back button
	if credits_back_button:
		_style_ashbane_button(credits_back_button, ASHBANE_ACCENT_CYAN, false)

func _style_bottom_buttons():
	"""Style the bottom row of buttons (Settings, Credits, Exit)"""
	if settings_button:
		_style_ashbane_button(settings_button, ASHBANE_TEXT_SECONDARY, false)
	if credits_button:
		_style_ashbane_button(credits_button, ASHBANE_TEXT_SECONDARY, false)
	if exit_button:
		_style_ashbane_button(exit_button, Color(0.8, 0.3, 0.3), false)

func _create_panel_style() -> StyleBoxFlat:
	"""Create the standard cyberpunk panel style"""
	var style = StyleBoxFlat.new()
	style.bg_color = ASHBANE_BG_PANEL
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = ASHBANE_BORDER_GLOW
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_size = 20
	style.shadow_color = Color(0.4, 0.1, 0.05, 0.25)  # Crimson shadow
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style

func _style_input_fields(parent: Node):
	"""Style all LineEdit inputs in a panel"""
	for child in parent.get_children():
		if child is LineEdit:
			_style_line_edit(child)
		elif child.get_child_count() > 0:
			_style_input_fields(child)

func _style_line_edit(input: LineEdit):
	"""Apply cyberpunk style to a LineEdit"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.04, 0.9)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 2
	style.border_color = ASHBANE_BORDER_GLOW
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5

	var style_focus = style.duplicate()
	style_focus.border_color = ASHBANE_ACCENT_PRIMARY
	style_focus.shadow_size = 5
	style_focus.shadow_color = Color(0.5, 0.12, 0.08, 0.3)  # Crimson glow

	input.add_theme_stylebox_override("normal", style)
	input.add_theme_stylebox_override("focus", style_focus)
	input.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
	input.add_theme_color_override("font_placeholder_color", ASHBANE_TEXT_SECONDARY)
	input.add_theme_color_override("caret_color", ASHBANE_ACCENT_GOLD)  # Gold caret
	input.add_theme_color_override("selection_color", Color(0.5, 0.12, 0.08, 0.4))  # Crimson selection

func _style_panel_buttons(parent: Node):
	"""Style all buttons in a panel"""
	for child in parent.get_children():
		if child is Button and not child is CheckBox:
			# Determine if it's a primary action button
			var is_primary = child.name in ["HostButton", "JoinButton", "LoginButton", "RegisterButton", "GuestButton"]
			var accent = ASHBANE_ACCENT_PRIMARY if is_primary else ASHBANE_TEXT_SECONDARY
			_style_ashbane_button(child, accent, is_primary)
		elif child.get_child_count() > 0:
			_style_panel_buttons(child)

func _style_panel_labels(parent: Node):
	"""Style all labels in a panel"""
	for child in parent.get_children():
		if child is Label:
			# Don't override if already colored (like status labels)
			if not child.has_theme_color_override("font_color"):
				child.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
		elif child.get_child_count() > 0:
			_style_panel_labels(child)

func _style_sliders(parent: Node):
	"""Style all sliders in a panel"""
	for child in parent.get_children():
		if child is HSlider:
			_style_slider(child)
		elif child.get_child_count() > 0:
			_style_sliders(child)

func _style_slider(slider: HSlider):
	"""Apply cyberpunk style to a slider"""
	# Grabber (the handle)
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = ASHBANE_ACCENT_CYAN
	grabber_style.corner_radius_top_left = 4
	grabber_style.corner_radius_top_right = 4
	grabber_style.corner_radius_bottom_left = 4
	grabber_style.corner_radius_bottom_right = 4

	# Track (background)
	var track_style = StyleBoxFlat.new()
	track_style.bg_color = Color(0.1, 0.12, 0.14, 0.8)
	track_style.corner_radius_top_left = 2
	track_style.corner_radius_top_right = 2
	track_style.corner_radius_bottom_left = 2
	track_style.corner_radius_bottom_right = 2

	# Filled portion - crimson fill
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.5, 0.12, 0.08, 0.8)  # Crimson
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2

	slider.add_theme_stylebox_override("grabber_area", fill_style)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_style)
	slider.add_theme_stylebox_override("slider", track_style)

func _style_checkboxes(parent: Node):
	"""Style all checkboxes in a panel"""
	for child in parent.get_children():
		if child is CheckBox:
			child.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
			child.add_theme_color_override("font_hover_color", ASHBANE_ACCENT_PRIMARY)
		elif child.get_child_count() > 0:
			_style_checkboxes(child)

func _style_option_button(option: OptionButton):
	"""Apply Ashbane style to an OptionButton"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.9)  # Warm dark
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ASHBANE_BORDER_GLOW
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	var style_hover = style.duplicate()
	style_hover.border_color = ASHBANE_ACCENT_PRIMARY

	option.add_theme_stylebox_override("normal", style)
	option.add_theme_stylebox_override("hover", style_hover)
	option.add_theme_stylebox_override("pressed", style_hover)
	option.add_theme_stylebox_override("focus", style_hover)
	option.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
	option.add_theme_color_override("font_hover_color", ASHBANE_ACCENT_PRIMARY)

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

	# Set player name
	NetworkManager.set_player_name(name_input.text)
	pending_ip = ip_input.text if is_dev_mode else PRODUCTION_SERVER_IP

	# Connect to server (Ashbane auth already happened at startup)
	status_label.text = "Connecting to server..."
	current_state = MenuState.JOINING

	if NetworkManager.join_game(pending_ip):
		if host_button:
			host_button.disabled = true
		join_button.disabled = true
		_show_cancel_button()
	else:
		status_label.text = "Failed to connect!"
		current_state = MenuState.MAIN

func _on_connected():
	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - update server select panel
		if server_status_label:
			server_status_label.text = "Connected! Authenticating..."
	else:
		status_label.text = "Connected! Waiting for server..."
	_hide_cancel_button()
	# Don't load game yet - wait for authentication

func _on_connection_failed():
	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - update server select panel
		if server_status_label:
			server_status_label.text = "Connection failed!"
		if connect_guest_button:
			connect_guest_button.disabled = false
		if server_select_back_button:
			server_select_back_button.disabled = false
	else:
		status_label.text = "Connection failed!"
		if host_button:
			host_button.disabled = false
		join_button.disabled = false
		current_state = MenuState.MAIN
	_hide_cancel_button()

func _on_server_created():
	status_label.text = "Server created! Loading game..."
	_load_game_world()

func _on_version_mismatch(server_version: String, client_version: String):
	"""Block connection due to version mismatch"""
	var error_msg = "UPDATE REQUIRED\nYour version: %s\nServer version: %s\n\nPlease download the latest version." % [client_version, server_version]

	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - update server select panel
		if server_status_label:
			server_status_label.text = error_msg
			server_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		if connect_guest_button:
			connect_guest_button.disabled = false
		if server_select_back_button:
			server_select_back_button.disabled = false
	else:
		status_label.text = error_msg
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))  # Red error

		# Re-enable buttons so player can retry after updating
		if host_button:
			host_button.disabled = false
		join_button.disabled = false
		current_state = MenuState.MAIN
	_hide_cancel_button()

# ═══════════════════════════════════════════════════════════════════════════
# CANCEL CONNECTION BUTTON
# ═══════════════════════════════════════════════════════════════════════════

func _create_cancel_connect_button() -> void:
	"""Create the cancel button for aborting connection attempts"""
	cancel_connect_button = Button.new()
	cancel_connect_button.text = "Cancel"
	cancel_connect_button.custom_minimum_size = Vector2(100, 36)
	cancel_connect_button.visible = false
	cancel_connect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Style to match the theme
	cancel_connect_button.add_theme_font_size_override("font_size", 14)
	cancel_connect_button.add_theme_color_override("font_color", Color(0.9, 0.6, 0.5))
	cancel_connect_button.add_theme_color_override("font_hover_color", Color(1.0, 0.7, 0.6))

	# Add after status label in the VBoxContainer
	var vbox = status_label.get_parent()
	var status_index = status_label.get_index()
	vbox.add_child(cancel_connect_button)
	vbox.move_child(cancel_connect_button, status_index + 1)

	cancel_connect_button.pressed.connect(_on_cancel_connect_pressed)
	cancel_connect_button.mouse_entered.connect(_on_button_hover)

func _show_cancel_button() -> void:
	"""Show the cancel button during connection"""
	if cancel_connect_button:
		cancel_connect_button.visible = true

func _hide_cancel_button() -> void:
	"""Hide the cancel button"""
	if cancel_connect_button:
		cancel_connect_button.visible = false

func _on_cancel_connect_pressed() -> void:
	"""Cancel the connection attempt"""
	_play_click_sound()

	# Disconnect from network
	if NetworkManager:
		NetworkManager.close_connection()

	# Reset UI state
	status_label.text = "Connection cancelled"
	if host_button:
		host_button.disabled = false
	join_button.disabled = false
	current_state = MenuState.MAIN
	_hide_cancel_button()

	# Clear status after a moment
	var tree = get_tree()
	if tree:
		await tree.create_timer(1.5).timeout
		if current_state == MenuState.MAIN:
			status_label.text = ""

# ═══════════════════════════════════════════════════════════════════════════
# AUTHENTICATION UI
# ═══════════════════════════════════════════════════════════════════════════

func _on_authentication_required():
	"""Server requested authentication - show auth panel for joining OR auto-login as guest"""
	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - automatically send guest login
		var guest_name = name_input.text.strip_edges() if name_input else ""
		if guest_name.is_empty():
			guest_name = "Guest_%d" % (randi() % 10000)
		if server_status_label:
			server_status_label.text = "Joining as guest..."
		NetworkManager.send_guest_login(guest_name)
	else:
		# Normal mode - show auth panel
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
	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - hide server select panel and load game
		if server_status_label:
			server_status_label.text = "Success! Loading game..."
		if server_select_panel:
			server_select_panel.visible = false
		status_label.text = "Loading game..."
		_load_game_world()
	else:
		auth_status_label.text = "Login successful!"
		_hide_auth_panel()
		status_label.text = "Loading game..."
		_load_game_world()

func _on_login_failed(error: String):
	if current_state == MenuState.GUEST_SERVER_SELECT:
		# Guest mode - update server select panel
		if server_status_label:
			server_status_label.text = error
		if connect_guest_button:
			connect_guest_button.disabled = false
		if server_select_back_button:
			server_select_back_button.disabled = false
	else:
		auth_status_label.text = error
		_set_auth_buttons_enabled(true)

func _on_register_success():
	auth_status_label.text = "Account created! You can now log in."
	_set_auth_buttons_enabled(true)

func _on_register_failed(error: String):
	auth_status_label.text = error
	_set_auth_buttons_enabled(true)

# ═══════════════════════════════════════════════════════════════════════════
# ASHBANE INTEGRATION (Link Gaming Accounts Panel)
# ═══════════════════════════════════════════════════════════════════════════

var ashbane_panel: Control = null
var ashbane_status_label: Label = null
var ashbane_link_button: Button = null
var ashbane_login_button: Button = null  # Single login button (replaces provider icons)
var ashbane_skip_button: Button = null
var ashbane_logout_button: Button = null
var ashbane_divider_container: Control = null
var ashbane_back_button: Button = null
var _ashbane_initialized: bool = false
var _connecting_dots_timer: Timer = null
var _connecting_provider_label: String = ""
var _connecting_dots_count: int = 0

func _setup_ashbane_integration():
	"""Setup Ashbane auth integration"""
	if _ashbane_initialized:
		return
	_ashbane_initialized = true

	# Create the Ashbane panel
	_create_ashbane_panel()

	# Connect AshbaneAuth signals
	if AshbaneAuth:
		AshbaneAuth.auth_started.connect(_on_ashbane_auth_started)
		AshbaneAuth.auth_completed.connect(_on_ashbane_auth_completed)
		AshbaneAuth.auth_failed.connect(_on_ashbane_auth_failed)
		AshbaneAuth.profile_updated.connect(_on_ashbane_profile_updated)

func _create_ashbane_panel():
	"""Create simplified authentication panel - 'Authenticate via' with clickable provider icons"""
	# Create main container
	ashbane_panel = Control.new()
	ashbane_panel.name = "AshbanePanel"
	ashbane_panel.visible = false
	ashbane_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ashbane_panel)

	# Dark background overlay
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = ASHBANE_BG_DARK
	ashbane_panel.add_child(bg)

	# Main card panel with glow border
	var card = Panel.new()
	card.name = "AshbaneCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -280
	card.offset_top = -260
	card.offset_right = 280
	card.offset_bottom = 260

	# Create cyberpunk panel style
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = ASHBANE_BG_PANEL
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.border_color = ASHBANE_BORDER_GLOW
	card_style.corner_radius_top_left = 4
	card_style.corner_radius_top_right = 4
	card_style.corner_radius_bottom_left = 4
	card_style.corner_radius_bottom_right = 4
	card_style.shadow_size = 20
	card_style.shadow_color = Color(0.4, 0.1, 0.05, 0.3)  # Crimson shadow
	card.add_theme_stylebox_override("panel", card_style)
	ashbane_panel.add_child(card)

	# Add corner decorations
	_add_corner_decorations(card)

	# Create content container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 40
	vbox.offset_top = 30
	vbox.offset_right = -40
	vbox.offset_bottom = -30
	vbox.add_theme_constant_override("separation", 16)
	card.add_child(vbox)

	# ASHBANE logo - custom drawn M-ashbane with trophy + text
	var logo_section = VBoxContainer.new()
	logo_section.add_theme_constant_override("separation", 4)
	vbox.add_child(logo_section)

	# Custom logo icon (M-ashbane with trophy)
	var logo_icon_container = CenterContainer.new()
	logo_section.add_child(logo_icon_container)
	var logo_icon = _create_ashbane_logo_icon()
	logo_icon_container.add_child(logo_icon)

	# "ASHBANE" text under the icon
	var logo_text = Label.new()
	logo_text.text = "A S H B A N E"
	logo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo_text.add_theme_font_size_override("font_size", 18)
	logo_text.add_theme_color_override("font_color", ASHBANE_ACCENT_PRIMARY)
	logo_section.add_child(logo_text)

	# Decorative line under ASHBANE
	var line_container = CenterContainer.new()
	logo_section.add_child(line_container)
	var accent_line = ColorRect.new()
	accent_line.color = ASHBANE_ACCENT_PRIMARY
	accent_line.custom_minimum_size = Vector2(100, 2)
	line_container.add_child(accent_line)

	# "Authenticate via" title
	var title = Label.new()
	title.text = "LINK YOUR GAMING LEGACY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
	vbox.add_child(title)

	# Tagline under title
	var tagline = Label.new()
	tagline.text = "Your achievements become your appearance.\nA decade of gaming? Look like a legend."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 14)
	tagline.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65, 0.9))
	vbox.add_child(tagline)

	# Status label (shows auth progress)
	ashbane_status_label = Label.new()
	ashbane_status_label.name = "AshbaneStatusLabel"
	ashbane_status_label.text = ""
	ashbane_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ashbane_status_label.add_theme_font_size_override("font_size", 14)
	ashbane_status_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)
	ashbane_status_label.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(ashbane_status_label)

	# Single Login button (provider selection happens in browser after beta key)
	ashbane_login_button = Button.new()
	ashbane_login_button.name = "AshbaneLoginButton"
	ashbane_login_button.text = "Login"
	ashbane_login_button.custom_minimum_size = Vector2(200, 50)
	ashbane_login_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_ashbane_button(ashbane_login_button, ASHBANE_ACCENT_CYAN, true)
	ashbane_login_button.pressed.connect(_on_ashbane_login_pressed)
	ashbane_login_button.mouse_entered.connect(_on_button_hover)
	vbox.add_child(ashbane_login_button)

	# Horizontal divider with "or" text
	ashbane_divider_container = HBoxContainer.new()
	ashbane_divider_container.name = "DividerContainer"
	ashbane_divider_container.alignment = BoxContainer.ALIGNMENT_CENTER
	ashbane_divider_container.add_theme_constant_override("separation", 15)
	vbox.add_child(ashbane_divider_container)

	# Use Control with fixed size for the lines to prevent expansion
	var left_line_container = Control.new()
	left_line_container.custom_minimum_size = Vector2(80, 1)
	left_line_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ashbane_divider_container.add_child(left_line_container)
	var left_line = ColorRect.new()
	left_line.color = Color(0.3, 0.32, 0.35, 0.6)
	left_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_line_container.add_child(left_line)

	var or_label = Label.new()
	or_label.text = "or"
	or_label.add_theme_font_size_override("font_size", 14)
	or_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)
	ashbane_divider_container.add_child(or_label)

	var right_line_container = Control.new()
	right_line_container.custom_minimum_size = Vector2(80, 1)
	right_line_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ashbane_divider_container.add_child(right_line_container)
	var right_line = ColorRect.new()
	right_line.color = Color(0.3, 0.32, 0.35, 0.6)
	right_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_line_container.add_child(right_line)

	# Guest button - styled more prominently
	ashbane_skip_button = Button.new()
	ashbane_skip_button.name = "AshbaneSkipButton"
	ashbane_skip_button.text = "Continue as Guest"
	ashbane_skip_button.custom_minimum_size = Vector2(200, 44)
	ashbane_skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_guest_button(ashbane_skip_button)
	ashbane_skip_button.pressed.connect(_on_ashbane_skip_pressed)
	ashbane_skip_button.mouse_entered.connect(_on_button_hover)
	vbox.add_child(ashbane_skip_button)

	# Logout button - small, only visible when logged in
	ashbane_logout_button = Button.new()
	ashbane_logout_button.name = "AshbaneLogoutButton"
	ashbane_logout_button.text = "Logout"
	ashbane_logout_button.custom_minimum_size = Vector2(80, 28)
	ashbane_logout_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ashbane_logout_button.visible = false  # Hidden until logged in
	_style_logout_button(ashbane_logout_button)
	ashbane_logout_button.pressed.connect(_on_ashbane_logout_pressed)
	ashbane_logout_button.mouse_entered.connect(_on_button_hover)
	vbox.add_child(ashbane_logout_button)

	# Exit button - always visible, quit the game
	var exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "Exit"
	exit_button.custom_minimum_size = Vector2(80, 28)
	exit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_exit_button(exit_button)
	exit_button.pressed.connect(_on_exit_pressed)
	exit_button.mouse_entered.connect(_on_button_hover)
	vbox.add_child(exit_button)

	# Remove the old link button reference (no longer used in simplified UI)
	ashbane_link_button = null

func _add_corner_decorations(parent: Control):
	"""Add medieval corner bracket decorations - Ashbane theme"""
	var corner_size = 20
	var corner_thickness = 2
	var corner_color = ASHBANE_ACCENT_PRIMARY  # Crimson corners

	# Top-left corner
	var tl_h = ColorRect.new()
	tl_h.color = corner_color
	tl_h.size = Vector2(corner_size, corner_thickness)
	tl_h.position = Vector2(0, 0)
	parent.add_child(tl_h)

	var tl_v = ColorRect.new()
	tl_v.color = corner_color
	tl_v.size = Vector2(corner_thickness, corner_size)
	tl_v.position = Vector2(0, 0)
	parent.add_child(tl_v)

	# Top-right corner
	var tr_h = ColorRect.new()
	tr_h.color = corner_color
	tr_h.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_h.size = Vector2(corner_size, corner_thickness)
	tr_h.position = Vector2(-corner_size, 0)
	parent.add_child(tr_h)

	var tr_v = ColorRect.new()
	tr_v.color = corner_color
	tr_v.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_v.size = Vector2(corner_thickness, corner_size)
	tr_v.position = Vector2(-corner_thickness, 0)
	parent.add_child(tr_v)

	# Bottom-left corner
	var bl_h = ColorRect.new()
	bl_h.color = corner_color
	bl_h.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl_h.size = Vector2(corner_size, corner_thickness)
	bl_h.position = Vector2(0, -corner_thickness)
	parent.add_child(bl_h)

	var bl_v = ColorRect.new()
	bl_v.color = corner_color
	bl_v.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl_v.size = Vector2(corner_thickness, corner_size)
	bl_v.position = Vector2(0, -corner_size)
	parent.add_child(bl_v)

	# Bottom-right corner
	var br_h = ColorRect.new()
	br_h.color = corner_color
	br_h.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br_h.size = Vector2(corner_size, corner_thickness)
	br_h.position = Vector2(-corner_size, -corner_thickness)
	parent.add_child(br_h)

	var br_v = ColorRect.new()
	br_v.color = corner_color
	br_v.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	br_v.size = Vector2(corner_thickness, corner_size)
	br_v.position = Vector2(-corner_thickness, -corner_size)
	parent.add_child(br_v)

# Provider icon configuration
# Using cdn.simpleicons.org with white color for tinting
# Xbox is not on Simple Icons CDN so we skip it for now
const SIMPLEICONS_CDN = "https://cdn.simpleicons.org"
const PROVIDER_ICONS = {
	"steam": {"slug": "steam", "color": Color(0.0, 0.85, 1.0), "label": "Steam", "active": true},
	"battlenet": {"slug": "battledotnet", "color": Color(0.0, 0.8, 1.0), "label": "Battle.net", "active": true},
	"playstation": {"slug": "playstation", "color": Color(0.0, 0.5, 0.8), "label": "PlayStation", "active": false},
	"epic": {"slug": "epicgames", "color": Color(0.7, 0.7, 0.75), "label": "Epic", "active": false},
	"gog": {"slug": "gogdotcom", "color": Color(0.6, 0.3, 0.75), "label": "GOG", "active": false}
}
# Note: Xbox removed - not available on Simple Icons CDN

var provider_icon_nodes: Dictionary = {}  # Store references for hover updates

func _create_provider_icons_row() -> Control:
	"""Create a row of clickable provider icons for authentication"""
	var main_container = VBoxContainer.new()
	main_container.name = "ProviderIconsContainer"
	main_container.add_theme_constant_override("separation", 16)

	# Active providers section
	var active_section = HBoxContainer.new()
	active_section.add_theme_constant_override("separation", 30)
	active_section.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(active_section)

	# Separator and "Coming Soon" section
	var inactive_section = VBoxContainer.new()
	inactive_section.add_theme_constant_override("separation", 8)
	main_container.add_child(inactive_section)

	# "Coming Soon" label
	var coming_soon_label = Label.new()
	coming_soon_label.text = "COMING SOON"
	coming_soon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coming_soon_label.add_theme_font_size_override("font_size", 12)
	coming_soon_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5, 0.7))
	inactive_section.add_child(coming_soon_label)

	# Inactive providers row
	var inactive_row = HBoxContainer.new()
	inactive_row.add_theme_constant_override("separation", 20)
	inactive_row.alignment = BoxContainer.ALIGNMENT_CENTER
	inactive_section.add_child(inactive_row)

	# Display order: active providers first, then inactive
	var provider_order = ["steam", "battlenet", "playstation", "epic", "gog"]

	# Create button for each provider
	for provider_key in provider_order:
		if not PROVIDER_ICONS.has(provider_key):
			continue

		var icon_data = PROVIDER_ICONS[provider_key]
		var is_active = icon_data.get("active", false)

		# Choose target container based on active state
		var target_container = active_section if is_active else inactive_row
		var icon_size = 56 if is_active else 40  # Larger touch targets for active

		# Button container for the icon
		var icon_button = Button.new()
		icon_button.name = provider_key + "_button"
		icon_button.custom_minimum_size = Vector2(icon_size, icon_size)
		icon_button.flat = true
		icon_button.tooltip_text = icon_data["label"]  # Tooltip on hover

		if is_active:
			icon_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			icon_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
			icon_button.disabled = true
			icon_button.tooltip_text = icon_data["label"] + " (Coming Soon)"

		# Style the button - active icons get glow background
		var btn_style = StyleBoxFlat.new()
		if is_active:
			btn_style.bg_color = Color(icon_data["color"].r * 0.15, icon_data["color"].g * 0.15, icon_data["color"].b * 0.15, 0.4)
			btn_style.shadow_size = 8
			btn_style.shadow_color = Color(icon_data["color"].r, icon_data["color"].g, icon_data["color"].b, 0.3)
		else:
			btn_style.bg_color = Color(0, 0, 0, 0)
		btn_style.corner_radius_top_left = 8
		btn_style.corner_radius_top_right = 8
		btn_style.corner_radius_bottom_left = 8
		btn_style.corner_radius_bottom_right = 8

		var btn_hover = StyleBoxFlat.new()
		if is_active:
			btn_hover.bg_color = Color(icon_data["color"].r * 0.25, icon_data["color"].g * 0.25, icon_data["color"].b * 0.25, 0.6)
			btn_hover.shadow_size = 12
			btn_hover.shadow_color = Color(icon_data["color"].r, icon_data["color"].g, icon_data["color"].b, 0.5)
		else:
			btn_hover.bg_color = Color(0.15, 0.15, 0.2, 0.3)
		btn_hover.corner_radius_top_left = 8
		btn_hover.corner_radius_top_right = 8
		btn_hover.corner_radius_bottom_left = 8
		btn_hover.corner_radius_bottom_right = 8

		icon_button.add_theme_stylebox_override("normal", btn_style)
		icon_button.add_theme_stylebox_override("hover", btn_hover)
		icon_button.add_theme_stylebox_override("pressed", btn_hover)
		icon_button.add_theme_stylebox_override("focus", btn_style)
		icon_button.add_theme_stylebox_override("disabled", btn_style)

		# The actual icon texture inside the button
		var icon = TextureRect.new()
		icon.name = provider_key + "_icon"
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		var padding = 10 if is_active else 8
		icon.offset_left = padding
		icon.offset_top = padding
		icon.offset_right = -padding
		icon.offset_bottom = -padding
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Start invisible for fade-in animation
		icon.modulate = Color(1, 1, 1, 0)

		icon_button.add_child(icon)

		# Store reference for later updates
		provider_icon_nodes[provider_key] = {
			"button": icon_button,
			"icon": icon,
			"color": icon_data["color"],
			"active": is_active
		}

		# Only connect events for active providers
		if is_active:
			icon_button.pressed.connect(_on_provider_clicked.bind(provider_key))
			icon_button.mouse_entered.connect(_on_provider_icon_hover.bind(provider_key, true))
			icon_button.mouse_exited.connect(_on_provider_icon_hover.bind(provider_key, false))

		target_container.add_child(icon_button)

		# Load icon from CDN
		if icon_data.has("slug"):
			_load_provider_icon_from_cdn(provider_key, icon_data["slug"])

	# Start pulse animation for active icons after a short delay
	get_tree().create_timer(0.5).timeout.connect(_start_active_icons_pulse)

	return main_container

func _start_active_icons_pulse():
	"""Start subtle pulse animation on active provider icons"""
	for provider_key in provider_icon_nodes.keys():
		var node_data = provider_icon_nodes[provider_key]
		if not node_data.get("active", false):
			continue

		var button: Button = node_data.get("button")
		if not button or not is_instance_valid(button):
			continue

		# Create looping pulse tween for the button's glow
		_create_pulse_tween(button, node_data["color"], provider_key)

func _create_pulse_tween(button: Button, brand_color: Color, provider_key: String):
	"""Create a subtle pulsing glow effect on the button"""
	var tween = create_tween()
	tween.set_loops()  # Loop forever

	# Pulse between normal and brighter glow
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(brand_color.r * 0.15, brand_color.g * 0.15, brand_color.b * 0.15, 0.4)
	normal_style.shadow_size = 8
	normal_style.shadow_color = Color(brand_color.r, brand_color.g, brand_color.b, 0.3)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8

	var bright_style = StyleBoxFlat.new()
	bright_style.bg_color = Color(brand_color.r * 0.2, brand_color.g * 0.2, brand_color.b * 0.2, 0.5)
	bright_style.shadow_size = 14
	bright_style.shadow_color = Color(brand_color.r, brand_color.g, brand_color.b, 0.5)
	bright_style.corner_radius_top_left = 8
	bright_style.corner_radius_top_right = 8
	bright_style.corner_radius_bottom_left = 8
	bright_style.corner_radius_bottom_right = 8

	# Store reference to stop later if needed
	provider_icon_nodes[provider_key]["pulse_tween"] = tween

	# Animate shadow_size and shadow_color alpha via property
	tween.tween_callback(func(): button.add_theme_stylebox_override("normal", bright_style))
	tween.tween_interval(1.5)
	tween.tween_callback(func(): button.add_theme_stylebox_override("normal", normal_style))
	tween.tween_interval(1.5)

func _start_connecting_dots_animation():
	"""Start the animated dots in 'Connecting to X...' text"""
	_stop_connecting_dots_animation()

	_connecting_dots_count = 0
	_connecting_dots_timer = Timer.new()
	_connecting_dots_timer.wait_time = 0.4
	_connecting_dots_timer.timeout.connect(_on_connecting_dots_tick)
	add_child(_connecting_dots_timer)
	_connecting_dots_timer.start()

	# Initial update
	_on_connecting_dots_tick()

func _stop_connecting_dots_animation():
	"""Stop the animated dots timer"""
	if _connecting_dots_timer:
		_connecting_dots_timer.stop()
		_connecting_dots_timer.queue_free()
		_connecting_dots_timer = null

func _on_connecting_dots_tick():
	"""Update the connecting text with cycling dots"""
	_connecting_dots_count = (_connecting_dots_count % 3) + 1
	var dots = ".".repeat(_connecting_dots_count)
	# Pad to 3 chars to prevent text shifting
	dots = dots + " ".repeat(3 - _connecting_dots_count)

	if ashbane_status_label and _connecting_provider_label != "":
		ashbane_status_label.text = "Connecting to %s%s" % [_connecting_provider_label, dots]

func _on_provider_clicked(provider_key: String):
	"""Handle click on provider icon - start OAuth for that provider"""
	_play_click_sound()

	if ashbane_status_label:
		var label = PROVIDER_ICONS[provider_key].get("label", provider_key)
		_connecting_provider_label = label
		_start_connecting_dots_animation()
		ashbane_status_label.add_theme_color_override("font_color", ASHBANE_ACCENT_CYAN)

	# Disable all provider buttons during auth
	for key in provider_icon_nodes.keys():
		var btn = provider_icon_nodes[key].get("button")
		if btn:
			btn.disabled = true

	if ashbane_skip_button:
		ashbane_skip_button.disabled = true

	# Start OAuth with the selected provider
	if AshbaneAuth:
		AshbaneAuth.start_login_with_provider(provider_key)
	else:
		_on_ashbane_auth_failed("Ashbane service not available")

func _load_provider_icon_from_cdn(provider_key: String, slug: String):
	"""Load provider icon from Simple Icons CDN with white color"""
	# Request white SVG so we can tint it with modulate
	var url = "%s/%s/FFFFFF" % [SIMPLEICONS_CDN, slug]

	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_provider_icon_loaded.bind(http, provider_key))

	var error = http.request(url)
	if error != OK:
		push_warning("MainMenu: Failed to request icon for %s: %s" % [provider_key, error])
		http.queue_free()

func _on_provider_icon_loaded(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, provider_key: String):
	"""Handle CDN icon response"""
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("MainMenu: Failed to load icon for %s (code: %d)" % [provider_key, response_code])
		return

	if not provider_icon_nodes.has(provider_key):
		return

	# Parse SVG data and create texture
	var svg_string = body.get_string_from_utf8()
	var image = Image.new()

	# Load SVG at higher resolution for crisp icons
	var error = image.load_svg_from_string(svg_string, 2.0)  # 2x scale for sharpness
	if error != OK:
		push_warning("MainMenu: Failed to parse SVG for %s" % provider_key)
		return

	# Create texture from image
	var texture = ImageTexture.create_from_image(image)

	# Apply to icon
	var node_data = provider_icon_nodes[provider_key]
	var icon: TextureRect = node_data["icon"]
	if icon and is_instance_valid(icon):
		icon.texture = texture

		# Set target color based on active state
		var target_color: Color
		if node_data.get("active", false):
			target_color = node_data["color"]
		else:
			# Grayed out for inactive providers
			target_color = Color(0.4, 0.42, 0.45, 0.6)

		# Fade-in animation
		var tween = create_tween()
		tween.tween_property(icon, "modulate", target_color, 0.3).set_ease(Tween.EASE_OUT)

func _on_provider_icon_hover(provider_key: String, hovered: bool):
	"""Handle provider icon hover - glow brighter (only for active providers)"""
	if not provider_icon_nodes.has(provider_key):
		return

	var node_data = provider_icon_nodes[provider_key]
	var icon: TextureRect = node_data["icon"]
	var brand_color: Color = node_data["color"]

	# Only active providers have hover effects
	if not node_data.get("active", false):
		return

	if hovered:
		# Glow: brighten the brand color significantly
		icon.modulate = Color(
			min(brand_color.r * 1.8, 1.0),
			min(brand_color.g * 1.8, 1.0),
			min(brand_color.b * 1.8, 1.0),
			1.0
		)
		_on_button_hover()
	else:
		# Return to normal brand color
		icon.modulate = brand_color

func _is_provider_connected(provider_key: String) -> bool:
	"""Check if a provider is connected via AshbaneAuth"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return false

	# Map of provider key to possible API names
	var name_variants = {
		"steam": ["steam"],
		"xbox": ["xbox", "xbl", "xbox live"],
		"battlenet": ["battlenet", "battle.net", "blizzard", "bnet"],
		"playstation": ["playstation", "psn", "playstation network"],
		"epic": ["epic", "epic games"],
		"gog": ["gog", "gog.com"]
	}

	var valid_names = name_variants.get(provider_key, [provider_key])

	# AshbaneAuth.providers contains connected provider data
	for provider in AshbaneAuth.providers:
		var provider_name = provider.get("provider", "").to_lower().strip_edges()
		# Also check 'name' field as fallback
		if provider_name == "":
			provider_name = provider.get("name", "").to_lower().strip_edges()

		for valid_name in valid_names:
			if provider_name == valid_name:
				return true

	return false

func _update_provider_icons_state():
	"""Update all provider icons based on connection status"""
	for provider_key in provider_icon_nodes.keys():
		var node_data = provider_icon_nodes[provider_key]
		var icon: TextureRect = node_data["icon"]
		var brand_color: Color = node_data["color"]

		if _is_provider_connected(provider_key):
			# Connected - show brand color
			icon.modulate = Color(brand_color.r, brand_color.g, brand_color.b, 1.0)
		else:
			# Not connected - dim white
			icon.modulate = Color(0.5, 0.5, 0.55, 0.7)

func _create_ashbane_logo_icon() -> Control:
	"""Create the Ashbane logo icon - M-ashbane shape with trophy on top using Line2D"""
	var container = Control.new()
	container.name = "AshbaneLogoIcon"
	container.custom_minimum_size = Vector2(60, 48)

	var w = 60.0
	var h = 48.0
	var cx = w / 2.0
	var logo_color = ASHBANE_ACCENT_CYAN
	var line_width = 2.5

	# M-Ashbane shape dimensions
	var ashbane_top = h * 0.5
	var ashbane_bottom = h * 0.95
	var outer_width = w * 0.7
	var inner_width = w * 0.28

	var left_outer = cx - outer_width / 2
	var left_inner = cx - inner_width / 2
	var right_outer = cx + outer_width / 2
	var right_inner = cx + inner_width / 2

	# M-Ashbane shape (the shelf/fireplace ashbane)
	var ashbane_line = Line2D.new()
	ashbane_line.name = "AshbaneLine"
	ashbane_line.width = line_width
	ashbane_line.default_color = logo_color
	ashbane_line.joint_mode = Line2D.LINE_JOINT_ROUND
	ashbane_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ashbane_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	ashbane_line.add_point(Vector2(left_outer, ashbane_bottom))    # Bottom left
	ashbane_line.add_point(Vector2(left_outer, ashbane_top))       # Top left outer
	ashbane_line.add_point(Vector2(left_inner, ashbane_top))       # Shelf left edge
	ashbane_line.add_point(Vector2(left_inner, ashbane_top + 10))  # Shelf inner left (deeper dip)
	ashbane_line.add_point(Vector2(right_inner, ashbane_top + 10)) # Shelf inner right (deeper dip)
	ashbane_line.add_point(Vector2(right_inner, ashbane_top))      # Shelf right edge
	ashbane_line.add_point(Vector2(right_outer, ashbane_top))      # Top right outer
	ashbane_line.add_point(Vector2(right_outer, ashbane_bottom))   # Bottom right
	ashbane_line.modulate.a = 0  # Start invisible for animation
	container.add_child(ashbane_line)

	# Trophy sitting on the shelf
	var trophy_bottom = ashbane_top - 2
	var trophy_top = h * 0.08
	var trophy_width = w * 0.28

	# Group all trophy parts for easier animation
	var trophy_group = Control.new()
	trophy_group.name = "TrophyGroup"
	trophy_group.modulate.a = 0  # Start invisible
	container.add_child(trophy_group)

	# Trophy base
	var trophy_base = Line2D.new()
	trophy_base.width = line_width
	trophy_base.default_color = logo_color
	trophy_base.add_point(Vector2(cx - trophy_width * 0.25, trophy_bottom))
	trophy_base.add_point(Vector2(cx + trophy_width * 0.25, trophy_bottom))
	trophy_group.add_child(trophy_base)

	# Trophy stem (goes up into cup)
	var trophy_stem = Line2D.new()
	trophy_stem.width = line_width
	trophy_stem.default_color = logo_color
	trophy_stem.add_point(Vector2(cx, trophy_bottom))
	trophy_stem.add_point(Vector2(cx, trophy_bottom - 5))
	trophy_group.add_child(trophy_stem)

	# Trophy stand - extends down through M to complete the letter (slightly duller)
	var trophy_stand = Line2D.new()
	trophy_stand.width = line_width
	trophy_stand.default_color = Color(logo_color.r * 0.6, logo_color.g * 0.6, logo_color.b * 0.6, 0.7)
	trophy_stand.add_point(Vector2(cx, trophy_bottom))
	trophy_stand.add_point(Vector2(cx, ashbane_bottom))
	trophy_group.add_child(trophy_stand)

	# Trophy cup (left side)
	var cup_left = Line2D.new()
	cup_left.width = line_width
	cup_left.default_color = logo_color
	cup_left.add_point(Vector2(cx - trophy_width * 0.12, trophy_bottom - 5))
	cup_left.add_point(Vector2(cx - trophy_width * 0.45, trophy_top))
	trophy_group.add_child(cup_left)

	# Trophy cup (right side)
	var cup_right = Line2D.new()
	cup_right.width = line_width
	cup_right.default_color = logo_color
	cup_right.add_point(Vector2(cx + trophy_width * 0.12, trophy_bottom - 5))
	cup_right.add_point(Vector2(cx + trophy_width * 0.45, trophy_top))
	trophy_group.add_child(cup_right)

	# Trophy rim
	var cup_rim = Line2D.new()
	cup_rim.width = line_width
	cup_rim.default_color = logo_color
	cup_rim.add_point(Vector2(cx - trophy_width * 0.45, trophy_top))
	cup_rim.add_point(Vector2(cx + trophy_width * 0.45, trophy_top))
	trophy_group.add_child(cup_rim)

	# Left handle (simple arc approximation with lines)
	var handle_left = Line2D.new()
	handle_left.width = line_width - 0.5
	handle_left.default_color = logo_color
	handle_left.add_point(Vector2(cx - trophy_width * 0.45, trophy_top + 2))
	handle_left.add_point(Vector2(cx - trophy_width * 0.58, trophy_top + 5))
	handle_left.add_point(Vector2(cx - trophy_width * 0.45, trophy_top + 8))
	trophy_group.add_child(handle_left)

	# Right handle
	var handle_right = Line2D.new()
	handle_right.width = line_width - 0.5
	handle_right.default_color = logo_color
	handle_right.add_point(Vector2(cx + trophy_width * 0.45, trophy_top + 2))
	handle_right.add_point(Vector2(cx + trophy_width * 0.58, trophy_top + 5))
	handle_right.add_point(Vector2(cx + trophy_width * 0.45, trophy_top + 8))
	trophy_group.add_child(handle_right)

	# Start animation after a short delay
	_animate_ashbane_logo.call_deferred(ashbane_line, trophy_group)

	return container

func _animate_ashbane_logo(ashbane_line: Line2D, trophy_group: Control):
	"""Animate the logo: M draws in, then trophy fades in, then subtle pulse"""
	await get_tree().create_timer(0.3).timeout

	var tween = create_tween()

	# Phase 1: M-ashbane fades/draws in
	tween.tween_property(ashbane_line, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)

	# Phase 2: Trophy drops in and fades
	tween.tween_property(trophy_group, "position:y", -3.0, 0.0)  # Start slightly above
	tween.tween_property(trophy_group, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(trophy_group, "position:y", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)

	# Phase 3: Subtle glow pulse
	tween.tween_interval(0.2)
	tween.tween_property(ashbane_line, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.15)
	tween.parallel().tween_property(trophy_group, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.15)
	tween.tween_property(ashbane_line, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)
	tween.parallel().tween_property(trophy_group, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

func _style_logout_button(button: Button):
	"""Style the small logout button"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.08, 0.1, 0.6)
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.4, 0.2, 0.2, 0.5)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.15, 0.08, 0.08, 0.8)
	style_hover.border_color = Color(0.6, 0.3, 0.3, 0.8)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_hover)
	button.add_theme_stylebox_override("focus", style_normal)

	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4, 0.8))
	button.add_theme_color_override("font_hover_color", Color(0.9, 0.5, 0.5, 1.0))

func _on_ashbane_logout_pressed():
	"""Handle logout button press"""
	_play_click_sound()

	if AshbaneAuth:
		AshbaneAuth.logout()

	# Reset UI to logged-out state
	if ashbane_logout_button:
		ashbane_logout_button.visible = false

	if ashbane_skip_button:
		ashbane_skip_button.text = "Continue as Guest"

	if ashbane_status_label:
		ashbane_status_label.text = "Logged out"
		ashbane_status_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)

	# Re-enable provider buttons
	for key in provider_icon_nodes.keys():
		var node_data = provider_icon_nodes[key]
		if node_data.get("active", false):
			var btn = node_data.get("button")
			if btn:
				btn.disabled = false

	# Update provider icons to non-connected state
	_update_provider_icons_state()

func _style_exit_button(button: Button):
	"""Style the Exit button - subtle gray"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.3, 0.3, 0.3, 0.6)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.25, 0.25, 0.25, 0.9)
	style_hover.border_color = Color(0.4, 0.4, 0.4, 0.8)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.1, 0.1, 0.1, 0.9)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", style_hover)

	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.9))
	button.add_theme_color_override("font_hover_color", Color(0.8, 0.8, 0.8, 1.0))

func _style_guest_button(button: Button):
	"""Style the Continue as Guest button"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.14, 0.16, 0.9)
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.35, 0.38, 0.42, 0.7)
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.16, 0.18, 0.22, 0.95)
	style_hover.border_color = Color(0.5, 0.55, 0.6, 0.9)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.1, 0.12, 0.14, 0.95)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", style_hover)

	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75, 0.9))
	button.add_theme_color_override("font_hover_color", ASHBANE_TEXT_PRIMARY)

func _style_ashbane_button(button: Button, accent_color: Color, prominent: bool):
	"""Apply Ashbane cyberpunk style to a button"""
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.1, 0.12, 0.9) if prominent else Color(0.05, 0.06, 0.08, 0.7)
	style_normal.border_width_left = 2 if prominent else 1
	style_normal.border_width_right = 2 if prominent else 1
	style_normal.border_width_top = 2 if prominent else 1
	style_normal.border_width_bottom = 2 if prominent else 1
	style_normal.border_color = accent_color if prominent else Color(0.3, 0.3, 0.35, 0.5)
	style_normal.corner_radius_top_left = 4
	style_normal.corner_radius_top_right = 4
	style_normal.corner_radius_bottom_left = 4
	style_normal.corner_radius_bottom_right = 4
	if prominent:
		style_normal.shadow_size = 8
		style_normal.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.3)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.1, 0.15, 0.18, 0.95) if prominent else Color(0.08, 0.1, 0.12, 0.8)
	style_hover.border_color = Color(accent_color.r * 1.2, accent_color.g * 1.2, accent_color.b * 1.2, 1.0)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.05, 0.08, 0.1, 0.95)

	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("focus", style_hover)

	button.add_theme_font_size_override("font_size", 18 if prominent else 14)
	button.add_theme_color_override("font_color", accent_color if prominent else ASHBANE_TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1) if prominent else ASHBANE_TEXT_PRIMARY)

func _show_ashbane_panel():
	"""Show the Ashbane panel for linking gaming accounts"""
	current_state = MenuState.ASHBANE_SCREEN

	# Hide main menu, show ashbane panel
	_set_menu_panel_visible(false)
	if ashbane_panel:
		ashbane_panel.visible = true

	# Update status based on whether already linked
	_update_ashbane_panel_status()

func _hide_ashbane_panel():
	"""Hide the Ashbane panel"""
	if ashbane_panel:
		ashbane_panel.visible = false

func _update_ashbane_panel_status():
	"""Update the Ashbane panel status display"""
	if not ashbane_status_label:
		return

	if AshbaneAuth and AshbaneAuth.is_logged_in():
		var tier_name = AshbaneAuth.ashbane_tier.get("name", "Unknown")
		var tier_color_hex = AshbaneAuth.ashbane_tier.get("color", "#FFFFFF")
		var provider_count = AshbaneAuth.providers.size()

		ashbane_status_label.text = "Player #%d\n%s Tier - %d providers connected" % [
			AshbaneAuth.user_id, tier_name, provider_count
		]
		var tier_color = Color.from_string(tier_color_hex, Color.WHITE)
		ashbane_status_label.add_theme_color_override("font_color", tier_color)

		if ashbane_skip_button:
			ashbane_skip_button.text = "Continue to Game"

		if ashbane_logout_button:
			ashbane_logout_button.visible = true

		# Hide login button and "or" divider when logged in
		if ashbane_login_button:
			ashbane_login_button.visible = false
		if ashbane_divider_container:
			ashbane_divider_container.visible = false
	else:
		ashbane_status_label.text = ""
		ashbane_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))

		if ashbane_skip_button:
			ashbane_skip_button.text = "Continue as Guest"

		if ashbane_logout_button:
			ashbane_logout_button.visible = false

		# Show login button and "or" divider when logged out
		if ashbane_login_button:
			ashbane_login_button.visible = true
			ashbane_login_button.disabled = false
		if ashbane_divider_container:
			ashbane_divider_container.visible = true

# _on_ashbane_link_pressed removed - now using _on_provider_clicked for each provider icon

func _on_ashbane_login_pressed():
	"""Handle login button press - opens browser for provider selection after beta key"""
	_play_click_sound()

	if ashbane_status_label:
		ashbane_status_label.text = "Opening browser..."
		ashbane_status_label.add_theme_color_override("font_color", ASHBANE_ACCENT_CYAN)

	# Disable buttons during auth
	if ashbane_login_button:
		ashbane_login_button.disabled = true
	if ashbane_skip_button:
		ashbane_skip_button.disabled = true

	# Start generic login (no provider specified - user picks in browser)
	if AshbaneAuth:
		AshbaneAuth.start_login()
	else:
		_on_ashbane_auth_failed("Ashbane service not available")

func _on_ashbane_skip_pressed():
	"""Handle skip/continue button based on auth state"""
	_play_click_sound()

	# Check if user is authenticated with Ashbane
	if AshbaneAuth and AshbaneAuth.is_authenticated:
		# Authenticated user - go directly to Armory (pre-game hub)
		_hide_ashbane_panel()
		_transition_to_armory()
	else:
		# Guest - go directly to server selection
		_hide_ashbane_panel()
		_on_guest_play_pressed()

func _proceed_to_main_menu():
	"""Show main menu with PLAY button after Ashbane auth/skip"""
	_hide_ashbane_panel()
	_set_menu_panel_visible(true)
	current_state = MenuState.MAIN

	# Update the menu to show Ashbane status if linked
	_update_menu_with_ashbane_status()

var ashbane_menu_status: Control = null  # Container for tier display in main menu

func _update_menu_with_ashbane_status():
	"""Update main menu to show Ashbane tier if linked"""
	var menu_vbox = get_node_or_null("MenuPanel/VBoxContainer")
	if not menu_vbox:
		return

	# Create tier display container if it doesn't exist
	if not ashbane_menu_status:
		ashbane_menu_status = _create_tier_display_widget()
		menu_vbox.add_child(ashbane_menu_status)
		menu_vbox.move_child(ashbane_menu_status, 0)

	# Update the display based on Ashbane status
	_update_tier_display_content()

func _create_tier_display_widget() -> Control:
	"""Create a fancy tier display widget with glow effects"""
	var container = VBoxContainer.new()
	container.name = "AshbaneTierDisplay"
	container.add_theme_constant_override("separation", 4)

	# Username label
	var username_label = Label.new()
	username_label.name = "UsernameLabel"
	username_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	username_label.add_theme_font_size_override("font_size", 14)
	username_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)
	container.add_child(username_label)

	# Tier badge container (with glow effect)
	var badge_container = CenterContainer.new()
	badge_container.name = "BadgeContainer"
	container.add_child(badge_container)

	var badge_panel = Panel.new()
	badge_panel.name = "TierBadge"
	badge_panel.custom_minimum_size = Vector2(180, 36)
	badge_container.add_child(badge_panel)

	# Tier label
	var tier_label = Label.new()
	tier_label.name = "TierLabel"
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tier_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	tier_label.add_theme_font_size_override("font_size", 16)
	badge_panel.add_child(tier_label)

	# Achievement count
	var ach_label = Label.new()
	ach_label.name = "AchievementLabel"
	ach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ach_label.add_theme_font_size_override("font_size", 12)
	ach_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)
	container.add_child(ach_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	container.add_child(spacer)

	return container

func _update_tier_display_content():
	"""Update the tier display widget content"""
	if not ashbane_menu_status:
		return

	var username_label = ashbane_menu_status.get_node_or_null("UsernameLabel")
	var badge_panel = ashbane_menu_status.get_node_or_null("BadgeContainer/TierBadge")
	var tier_label = ashbane_menu_status.get_node_or_null("BadgeContainer/TierBadge/TierLabel")
	var ach_label = ashbane_menu_status.get_node_or_null("AchievementLabel")

	if AshbaneAuth and AshbaneAuth.is_logged_in():
		var tier_name = AshbaneAuth.ashbane_tier.get("name", "Unknown")
		var tier_key = tier_name.to_lower()
		var tier_color_hex = AshbaneAuth.ashbane_tier.get("color", "#FFFFFF")
		var tier_color = Color.from_string(tier_color_hex, Color.WHITE)
		var total_ach = AshbaneAuth.total_achievements
		var provider_count = AshbaneAuth.providers.size()

		# Use our tier colors if available
		if TIER_COLORS.has(tier_key):
			tier_color = TIER_COLORS[tier_key]

		# Update player number
		if username_label:
			username_label.text = "Player #%d" % AshbaneAuth.user_id
			username_label.visible = true

		# Style the tier badge with glow
		if badge_panel:
			var badge_style = StyleBoxFlat.new()
			badge_style.bg_color = Color(tier_color.r * 0.15, tier_color.g * 0.15, tier_color.b * 0.15, 0.9)
			badge_style.border_width_left = 2
			badge_style.border_width_right = 2
			badge_style.border_width_top = 2
			badge_style.border_width_bottom = 2
			badge_style.border_color = tier_color
			badge_style.corner_radius_top_left = 4
			badge_style.corner_radius_top_right = 4
			badge_style.corner_radius_bottom_left = 4
			badge_style.corner_radius_bottom_right = 4
			badge_style.shadow_size = 12
			badge_style.shadow_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.4)
			badge_panel.add_theme_stylebox_override("panel", badge_style)

		# Update tier label
		if tier_label:
			tier_label.text = "%s TIER" % tier_name.to_upper()
			tier_label.add_theme_color_override("font_color", tier_color)

		# Update achievement count
		if ach_label:
			ach_label.text = "%d achievements • %d providers" % [total_ach, provider_count]
			ach_label.visible = true

		ashbane_menu_status.visible = true
	else:
		# Guest mode - simple display
		if username_label:
			username_label.visible = false

		if badge_panel:
			var guest_style = StyleBoxFlat.new()
			guest_style.bg_color = Color(0.08, 0.08, 0.1, 0.8)
			guest_style.border_width_left = 1
			guest_style.border_width_right = 1
			guest_style.border_width_top = 1
			guest_style.border_width_bottom = 1
			guest_style.border_color = Color(0.4, 0.4, 0.45, 0.5)
			guest_style.corner_radius_top_left = 4
			guest_style.corner_radius_top_right = 4
			guest_style.corner_radius_bottom_left = 4
			guest_style.corner_radius_bottom_right = 4
			badge_panel.add_theme_stylebox_override("panel", guest_style)

		if tier_label:
			tier_label.text = "GUEST"
			tier_label.add_theme_color_override("font_color", ASHBANE_TEXT_SECONDARY)

		if ach_label:
			ach_label.text = "Link accounts for cosmetics"
			ach_label.visible = true

		ashbane_menu_status.visible = true

func _on_ashbane_auth_started(auth_url: String):
	"""Browser opened for authentication"""
	_stop_connecting_dots_animation()

	if ashbane_status_label:
		ashbane_status_label.text = "Complete login in your browser...\nWaiting for authentication..."
		ashbane_status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))

func _on_ashbane_auth_completed(user_data: Dictionary):
	"""Successfully authenticated with Ashbane"""
	_stop_connecting_dots_animation()

	# Show success message briefly
	if ashbane_status_label:
		var tier_name = user_data.get("ashbane", {}).get("name", "Unknown")
		var total_ach = user_data.get("total_achievements", 0)
		ashbane_status_label.text = "Welcome, %s!\n%s Tier - %d achievements\n\nSyncing to Armory..." % [
			user_data.get("username", "Player"), tier_name, total_ach
		]
		# Green color to signify success and syncing
		ashbane_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))

	# Update provider icons to show connected state
	_update_provider_icons_state()

	# Transition to Armory after a brief delay
	var tree = get_tree()
	if tree:
		await tree.create_timer(1.5).timeout
		_transition_to_armory()
	else:
		# Fallback if tree not available
		_transition_to_armory()

func _on_ashbane_auth_failed(error: String):
	"""Ashbane authentication failed"""
	_stop_connecting_dots_animation()

	if ashbane_status_label:
		ashbane_status_label.text = error
		ashbane_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

	# Re-enable login button
	if ashbane_login_button:
		ashbane_login_button.disabled = false

	if ashbane_skip_button:
		ashbane_skip_button.disabled = false

func _on_ashbane_profile_updated(profile: Dictionary):
	"""Ashbane profile updated with new data"""
	if current_state == MenuState.ASHBANE_SCREEN:
		_update_ashbane_panel_status()
	# Update provider icons to reflect any newly connected providers
	_update_provider_icons_state()

# ═══════════════════════════════════════════════════════════════════════════
# ARMORY TRANSITION
# ═══════════════════════════════════════════════════════════════════════════

func _transition_to_armory():
	"""Transition to Armory scene after authentication"""
	LogManager.info("Transitioning to Armory", "ashbane")

	# Menu music continues playing via SoundManager (persists across scenes)

	# Load Armory scene
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/Armory.tscn")

# ═══════════════════════════════════════════════════════════════════════════
# GAME LOADING
# ═══════════════════════════════════════════════════════════════════════════

func _load_game_world():
	# Stop menu music before transitioning to game world
	if SoundManager:
		SoundManager.stop_menu_music(0.8)  # Fade out over 0.8 seconds

	# Small delay to ensure network is ready
	var tree = get_tree()
	if tree:
		await tree.create_timer(0.3).timeout
		tree.change_scene_to_file("res://main.tscn")

# ═══════════════════════════════════════════════════════════════════════════
# SETTINGS, CREDITS, EXIT
# ═══════════════════════════════════════════════════════════════════════════

func _on_settings_pressed():
	_play_click_sound()
	# Hide whichever panel is currently showing
	_set_menu_panel_visible(false)
	_hide_ashbane_panel()
	if server_select_panel:
		server_select_panel.visible = false
	if settings_panel:
		settings_panel.visible = true

func _on_settings_back_pressed():
	_play_click_sound()
	if settings_panel:
		settings_panel.visible = false
	_save_settings()
	# Return to appropriate panel based on state
	_return_to_current_panel()

func _on_credits_pressed():
	_play_click_sound()
	# Hide whichever panel is currently showing
	_set_menu_panel_visible(false)
	_hide_ashbane_panel()
	if server_select_panel:
		server_select_panel.visible = false
	if credits_panel:
		credits_panel.visible = true

func _on_credits_back_pressed():
	_play_click_sound()
	if credits_panel:
		credits_panel.visible = false
	# Return to appropriate panel based on state
	_return_to_current_panel()

func _return_to_current_panel():
	"""Return to the appropriate panel based on current menu state"""
	match current_state:
		MenuState.ASHBANE_SCREEN:
			_show_ashbane_panel()
		MenuState.GUEST_SERVER_SELECT:
			if server_select_panel:
				server_select_panel.visible = true
		_:
			# Default: show Ashbane panel (startup state)
			_show_ashbane_panel()

# ═══════════════════════════════════════════════════════════════════════════
# GUEST SERVER SELECT
# ═══════════════════════════════════════════════════════════════════════════

func _setup_server_select_panel():
	"""Initialize the server select panel with known servers"""
	if not server_option:
		return

	# Clear and populate server options
	server_option.clear()

	# Always add production server first
	server_option.add_item("Production (Dreadland)")

	# Add LAN option only in dev mode
	if is_dev_mode:
		server_option.add_item("LAN (Local Network)")

	# Add custom option
	server_option.add_item("Custom IP...")

	# Style the option button to match theme
	_style_server_option_button()

	# Hide server select panel initially
	if server_select_panel:
		server_select_panel.visible = false

func _style_server_option_button():
	"""Apply Ashbane styling to the server option button"""
	if not server_option:
		return

	var style = StyleBoxFlat.new()
	style.bg_color = ASHBANE_BG_PANEL
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.04, 0.03, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	server_option.add_theme_stylebox_override("normal", style)
	server_option.add_theme_stylebox_override("hover", style)
	server_option.add_theme_stylebox_override("pressed", style)
	server_option.add_theme_stylebox_override("focus", style)
	server_option.add_theme_color_override("font_color", ASHBANE_TEXT_PRIMARY)
	server_option.add_theme_color_override("font_hover_color", ASHBANE_ACCENT_GOLD)

func _on_guest_play_pressed():
	"""Show server selection panel for guest play"""
	current_state = MenuState.GUEST_SERVER_SELECT

	# Hide main menu, show server select
	_set_menu_panel_visible(false)
	if server_select_panel:
		server_select_panel.visible = true

	# Reset status
	if server_status_label:
		server_status_label.text = ""
	if custom_ip_input:
		custom_ip_input.text = ""

	# Select production server by default
	if server_option and server_option.item_count > 0:
		server_option.select(0)

func _on_connect_guest_pressed():
	"""Connect to selected server as guest"""
	_play_click_sound()

	# Determine which IP to use based on selected option
	var selected_idx = server_option.selected if server_option else 0
	var selected_text = server_option.get_item_text(selected_idx) if server_option else ""
	var target_ip: String

	if selected_text.begins_with("Production"):
		target_ip = KNOWN_SERVERS["Production (Dreadland)"]
	elif selected_text.begins_with("LAN"):
		target_ip = KNOWN_SERVERS["LAN (Local Network)"]
	elif selected_text.begins_with("Custom"):
		# Custom IP selected
		target_ip = custom_ip_input.text.strip_edges() if custom_ip_input else ""
		if target_ip.is_empty():
			if server_status_label:
				server_status_label.text = "Please enter a server IP"
			return
	else:
		# Fallback to production
		target_ip = PRODUCTION_SERVER_IP

	# Set player name
	var guest_name = name_input.text.strip_edges() if name_input else ""
	if guest_name.is_empty():
		guest_name = "Guest_%d" % (randi() % 10000)
	NetworkManager.set_player_name(guest_name)

	# Store for guest login after connection
	pending_ip = target_ip

	# Update UI
	if server_status_label:
		server_status_label.text = "Connecting to %s..." % target_ip
	if connect_guest_button:
		connect_guest_button.disabled = true
	if server_select_back_button:
		server_select_back_button.disabled = true

	# Connect to server
	if NetworkManager.join_game(target_ip):
		# Connection initiated - wait for connected signal
		pass
	else:
		if server_status_label:
			server_status_label.text = "Failed to connect!"
		if connect_guest_button:
			connect_guest_button.disabled = false
		if server_select_back_button:
			server_select_back_button.disabled = false
		current_state = MenuState.MAIN

func _on_server_select_back_pressed():
	"""Go back to Ashbane panel from server select"""
	_play_click_sound()

	# Close any pending connection
	if current_state == MenuState.GUEST_SERVER_SELECT:
		NetworkManager.close_connection()

	# Hide server select, show Ashbane panel
	if server_select_panel:
		server_select_panel.visible = false

	# Re-enable buttons
	if connect_guest_button:
		connect_guest_button.disabled = false
	if server_select_back_button:
		server_select_back_button.disabled = false

	# Return to Ashbane auth screen
	_show_ashbane_panel()

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
		# Disable resolution dropdown in fullscreen (doesn't apply)
		if resolution_option:
			resolution_option.disabled = true
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Re-enable resolution dropdown
		if resolution_option:
			resolution_option.disabled = false
		# Apply saved resolution when exiting fullscreen
		var config = ConfigFile.new()
		if config.load("user://settings.cfg") == OK:
			var res_index = config.get_value("display", "resolution_index", 0)
			if res_index >= 0 and res_index < RESOLUTIONS.size():
				DisplayServer.window_set_size(RESOLUTIONS[res_index])

func _on_vsync_toggled(enabled: bool):
	if enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _setup_resolution_options():
	"""Populate resolution dropdown with presets"""
	if not resolution_option:
		return
	resolution_option.clear()
	for i in range(RESOLUTIONS.size()):
		var res = RESOLUTIONS[i]
		resolution_option.add_item("%dx%d" % [res.x, res.y], i)

	# Select current resolution or closest match
	var current_size = DisplayServer.window_get_size()
	var best_match = 0
	var best_diff = INF
	for i in range(RESOLUTIONS.size()):
		var res = RESOLUTIONS[i]
		var diff = abs(res.x - current_size.x) + abs(res.y - current_size.y)
		if diff < best_diff:
			best_diff = diff
			best_match = i
	resolution_option.select(best_match)

func _on_resolution_selected(index: int):
	"""Apply selected resolution (only applies in windowed mode)"""
	if index < 0 or index >= RESOLUTIONS.size():
		return

	# Save the setting
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("display", "resolution_index", index)
	config.save("user://settings.cfg")

	# Only apply if not in fullscreen
	var window_mode = DisplayServer.window_get_mode()
	if window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return  # Resolution doesn't apply in fullscreen

	# Must be in windowed mode to resize (handles maximized)
	if window_mode != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_size(RESOLUTIONS[index])

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
		# Load resolution
		var saved_res_index = config.get_value("display", "resolution_index", 0)
		if resolution_option and saved_res_index >= 0 and saved_res_index < RESOLUTIONS.size():
			resolution_option.select(saved_res_index)
			_on_resolution_selected(saved_res_index)
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
	if resolution_option:
		config.set_value("display", "resolution_index", resolution_option.selected)

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
	# Hide Minimap (CanvasLayer autoload)
	if Minimap:
		Minimap.hide_minimap()
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

# ═══════════════════════════════════════════════════════════════════════════
# VERSION CHECK SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func _check_for_updates() -> void:
	"""Check backend for newer client version"""
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_version_check_completed.bind(http))

	var url = AshbaneAuth.get_api_base() + "/api/version"
	var error = http.request(url)
	if error != OK:
		LogManager.warn("Version check failed to start", "update")
		http.queue_free()

func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warn("Version check failed: HTTP %d" % response_code, "update")
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		LogManager.warn("Version check: Invalid JSON response", "update")
		return

	var data = json.get_data()
	var server_version = data.get("version", "")
	var download_url = data.get("download_url", "https://ashbane.itch.io/ashbane")
	var client_version = NetworkManager.CLIENT_VERSION  # Use semver, not git hash

	LogManager.info("Version check: client=%s, server=%s" % [client_version, server_version], "update")

	if _is_version_outdated(client_version, server_version):
		_show_update_prompt(server_version, download_url)

func _is_version_outdated(client: String, server: String) -> bool:
	"""Check if client version is older than server version"""
	# Empty server version means no update info available
	if server == "":
		return false
	# If versions match, not outdated
	if client == server:
		return false
	# Different versions - server has newer version
	return true

func _show_update_prompt(new_version: String, download_url: String) -> void:
	"""Show non-blocking update available dialog"""
	var client_version = NetworkManager.CLIENT_VERSION

	# Create styled dialog matching Ashbane theme
	var dialog = AcceptDialog.new()
	dialog.title = "Update Available"
	dialog.dialog_text = "A new version of Ashbane is available!\n\nYour version: %s\nNew version: %s\n\nWould you like to download the update?" % [client_version, new_version]
	dialog.ok_button_text = "Later"

	# Add Download button
	var download_btn = dialog.add_button("Download", true, "download")
	dialog.custom_action.connect(func(action: StringName):
		if action == "download":
			OS.shell_open(download_url)
			dialog.hide()
	)

	# Style the dialog
	dialog.min_size = Vector2(400, 200)

	add_child(dialog)
	dialog.popup_centered()

	LogManager.info("Showing update prompt for version %s" % new_version, "update")
