extends CanvasLayer
## In-game authentication overlay
## Shows "waiting for auth" message while guest authenticates in browser
## Can be triggered from anywhere in the game (vendor, settings, etc.)

signal auth_success(user_data: Dictionary)
signal auth_cancelled()

@onready var panel: Panel = $Panel
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var cancel_button: Button = $Panel/VBox/CancelButton

var _is_active: bool = false
var _guest_progress: Dictionary = {}  # Stored progress to sync after auth
var _pending_auth_url: String = ""  # For web: URL to open when user clicks
var _open_login_button: Button = null  # Web-only: manual open button

func _ready() -> void:
	visible = false
	layer = 100  # Above everything

	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)

	# Connect to AshbaneAuth signals
	if AshbaneAuth:
		AshbaneAuth.auth_started.connect(_on_auth_started)
		AshbaneAuth.auth_completed.connect(_on_auth_completed)
		AshbaneAuth.auth_failed.connect(_on_auth_failed)

func show_auth_prompt() -> void:
	"""Show the overlay and start device code auth flow"""
	if _is_active:
		return

	_is_active = true
	visible = true

	# Capture current guest progress before auth
	_capture_guest_progress()

	# Update status
	if status_label:
		status_label.text = "Opening browser...\nPlease log in to continue."

	# Don't pause the game tree - AshbaneAuth needs to poll for auth completion
	# The overlay will block input anyway
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Start the auth flow
	AshbaneAuth.start_login()

func _capture_guest_progress() -> void:
	"""Capture current guest progress to sync after authentication"""
	_guest_progress = {
		"gold": CharacterStats.gold,
		"level": CharacterStats.level,
		"experience": CharacterStats.experience,
		"inventory": _serialize_inventory(),
		"equipped_weapon": CharacterStats.equipped_weapon.weapon_name if CharacterStats.equipped_weapon else "",
	}
	LogManager.info("Captured guest progress for sync: gold=%d, level=%d" % [_guest_progress.gold, _guest_progress.level], "auth")

func _serialize_inventory() -> Array:
	"""Serialize inventory items for backend sync"""
	var items = []
	if CharacterStats.has_method("get_inventory_items"):
		for item in CharacterStats.get_inventory_items():
			items.append({
				"id": item.get("id", ""),
				"name": item.get("name", ""),
				"quantity": item.get("quantity", 1),
				"type": item.get("type", "")
			})
	return items

func _on_auth_started(auth_url: String) -> void:
	"""Browser opened, waiting for user to authenticate"""
	if not _is_active:
		return

	_pending_auth_url = auth_url

	if OS.has_feature("web"):
		# Web: Show a button the user must click to open login page
		# This is required because browsers block popups unless triggered by user gesture
		if status_label:
			status_label.text = "Click the button below to open the login page.\n\nAfter logging in, return to this tab."

		# Create/show manual open button
		if not _open_login_button:
			_open_login_button = Button.new()
			_open_login_button.text = "Open Login Page"
			_open_login_button.pressed.connect(_on_open_login_pressed)
			# Insert before cancel button
			var vbox = $Panel/VBox
			if vbox:
				vbox.add_child(_open_login_button)
				vbox.move_child(_open_login_button, vbox.get_child_count() - 1)
		_open_login_button.visible = true
	else:
		# Desktop: browser opened automatically
		if status_label:
			status_label.text = "A browser window has opened!\n\nLog in there, then return to the game.\n\nWaiting for you to complete login..."

func _on_open_login_pressed() -> void:
	"""Web-only: User clicked to open login page - this is a user gesture so popup works"""
	if _pending_auth_url.is_empty():
		return

	# Use JavaScriptBridge for web to ensure it works
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s', '_blank')" % _pending_auth_url)
	else:
		OS.shell_open(_pending_auth_url)

	# Update UI to show waiting state
	if status_label:
		status_label.text = "Login page opened!\n\nComplete login there, then return to this tab.\n\nWaiting for you to complete login..."

	# Hide the button after clicking
	if _open_login_button:
		_open_login_button.visible = false

func _on_auth_completed(user_data: Dictionary) -> void:
	"""Authentication successful"""
	if not _is_active:
		return

	LogManager.info("In-game auth completed for user: %s" % user_data.get("username", "unknown"), "auth")

	if status_label:
		status_label.text = "Login successful!\n\nSyncing your progress..."

	# Sync guest progress to backend
	_sync_guest_progress_to_backend(user_data)

func _sync_guest_progress_to_backend(user_data: Dictionary) -> void:
	"""Send captured guest progress to backend"""
	if _guest_progress.is_empty():
		_finish_auth(user_data)
		return

	# Create HTTP request to sync progress
	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_sync_response.bind(request, user_data))

	var url = AshbaneAuth.get_api_base() + "/api/character/initialize"
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + AshbaneAuth.auth_token]
	var body = JSON.stringify(_guest_progress)

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.warning("Failed to sync guest progress: %s" % error, "auth")
		# Continue anyway - they're authenticated, just didn't sync progress
		_finish_auth(user_data)

func _on_sync_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, user_data: Dictionary) -> void:
	"""Handle response from progress sync endpoint"""
	request.queue_free()

	var is_new_character: bool = true
	var server_character: Dictionary = {}

	if response_code == 200 or response_code == 201:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and response is Dictionary:
			is_new_character = response.get("character", {}).get("is_new", true)
			server_character = response.get("character", {})

		if is_new_character:
			LogManager.info("Guest progress synced - new character created", "auth")
		else:
			LogManager.info("Existing character loaded from server", "auth")
			# Load server character data into local state
			_load_server_character(server_character)
	else:
		LogManager.warning("Failed to sync guest progress: HTTP %d" % response_code, "auth")

	_finish_auth(user_data, is_new_character)

func _load_server_character(character: Dictionary) -> void:
	"""Replace local guest state with server character data"""
	if character.is_empty():
		return

	# Update CharacterStats with server values
	if character.has("gold"):
		CharacterStats.gold = character.gold
	if character.has("level"):
		CharacterStats.level = character.level
		# Recalculate experience_to_next_level from level (backend doesn't store this)
		var level_exponent = min(CharacterStats.level - 1, 50)
		CharacterStats.experience_to_next_level = int(Constants.BASE_XP_REQUIREMENT * pow(Constants.XP_SCALING_EXPONENT, level_exponent))
	if character.has("experience"):
		CharacterStats.experience = character.experience
		# Clamp experience to current level range
		if CharacterStats.experience >= CharacterStats.experience_to_next_level:
			CharacterStats.experience = CharacterStats.experience_to_next_level - 1

	# Load inventory from server
	if character.has("inventory") and character.inventory is Array:
		# Clear existing inventory and load server data
		InventorySystem.inventory_items.clear()
		for i in range(InventorySystem.current_slot_count):
			InventorySystem.inventory_items.append(null)

		# Add items from server
		for item in character.inventory:
			if item != null and item is Dictionary:
				InventorySystem.add_item(item)

		LogManager.info("Loaded %d inventory items from server" % character.inventory.size(), "auth")

	# Load equipped armor from server
	if character.has("equipped_armor") and character.equipped_armor is Dictionary:
		for slot in character.equipped_armor:
			var armor_item = character.equipped_armor[slot]
			if armor_item != null and armor_item is Dictionary:
				CharacterStats.equipped_armor[slot] = armor_item
		LogManager.info("Loaded equipped armor from server", "auth")

	# Load equipped weapon from server (just the ID - actual equipping happens in-game)
	if character.has("equipped_weapon") and character.equipped_weapon != "":
		CharacterStats.equipped_weapon_data = {"id": character.equipped_weapon}
		LogManager.info("Loaded equipped weapon: %s" % character.equipped_weapon, "auth")

	LogManager.info("Loaded server character: Level %d, %d gold" % [
		character.get("level", 1),
		character.get("gold", 0)
	], "auth")

func _finish_auth(user_data: Dictionary, is_new_character: bool = true) -> void:
	"""Complete the auth flow and return to game or Armory"""
	# Prefer display_name (e.g., "Player #1") over internal username (e.g., "ashbane-XXXXXXXX")
	var display_name = user_data.get("display_name", "")
	if display_name.is_empty():
		display_name = AshbaneAuth.display_name if AshbaneAuth and not AshbaneAuth.display_name.is_empty() else user_data.get("username", "Player")

	if is_new_character:
		# New account - guest progress synced, continue playing
		if status_label:
			status_label.text = "Welcome, %s!\n\nYour progress has been saved.\nResuming game..." % display_name

		# Update player name in NetworkManager and UI
		if NetworkManager:
			NetworkManager.set_player_name(display_name)

		# Update PortraitHUD if it exists
		var portrait_hud = get_node_or_null("/root/PortraitHUD")
		if portrait_hud and portrait_hud.has_method("set_player_name"):
			portrait_hud.set_player_name(display_name)

		# Update local player's health bar nameplate
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var health_bar = player.get_node_or_null("HealthBar")
			if health_bar and health_bar.has_method("set_player_name"):
				health_bar.set_player_name(display_name)
				if health_bar.has_method("set_name_color"):
					health_bar.set_name_color(Color(0.4, 0.8, 1.0, 1.0))

		# Brief delay then continue playing
		await get_tree().create_timer(1.0).timeout
		_hide_overlay()
		auth_success.emit(user_data)
	else:
		# Existing character - redirect to Armory to properly load it
		if status_label:
			status_label.text = "Welcome back, %s!\n\nYou have an existing character.\nLoading Armory..." % display_name

		LogManager.info("Existing character detected - redirecting to Armory", "auth")

		# Update NetworkManager player name for when they join a new game
		if NetworkManager:
			NetworkManager.set_player_name(display_name)

		await get_tree().create_timer(1.5).timeout
		_hide_overlay()

		# Disconnect from current game if in multiplayer
		if NetworkManager and NetworkManager.peer != null:
			NetworkManager.close_connection()

		# Destroy PortraitHUD - it shouldn't persist into Armory
		var portrait_hud = get_node_or_null("/root/PortraitHUD")
		if portrait_hud:
			portrait_hud.queue_free()

		# Go to Armory scene
		get_tree().change_scene_to_file("res://scenes/ui/Armory.tscn")

func _on_auth_failed(error: String) -> void:
	"""Authentication failed"""
	if not _is_active:
		return

	LogManager.warning("In-game auth failed: %s" % error, "auth")

	if status_label:
		status_label.text = "Login failed:\n%s\n\nClick Cancel to return to game." % error

func _on_cancel_pressed() -> void:
	"""User cancelled authentication"""
	AshbaneAuth.cancel_auth()
	_hide_overlay()
	auth_cancelled.emit()

func _hide_overlay() -> void:
	"""Hide overlay"""
	_is_active = false
	visible = false
	_guest_progress = {}
	_pending_auth_url = ""
	if _open_login_button:
		_open_login_button.queue_free()
		_open_login_button = null
