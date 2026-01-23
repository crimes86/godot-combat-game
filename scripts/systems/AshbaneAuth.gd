extends Node
## AshbaneAuth - Handles authentication with Ashbane backend
## Device code flow: open browser -> user logs in -> poll for completion

signal auth_started(auth_url: String)
signal auth_completed(user_data: Dictionary)
signal auth_failed(error: String)
signal profile_updated(profile: Dictionary)
signal logout_completed
signal connection_status_changed(status: int)  # ConnectionStatus enum value

# Connection status enum
enum ConnectionStatus { DISCONNECTED, CONNECTING, CONNECTED }

# API Configuration
const API_BASE_PROD = "https://api.ashbane.net"
const API_OVERRIDE_PATH = "user://api_override.txt"  # Dev override: create this file with a URL to use instead
const TOKEN_PATH = "user://ashbane_session.dat"

# LAN testing (only used in editor/debug builds, never in exports)
const API_BASE_LAN = "http://192.168.28.211:8000"
const USE_LAN_IN_EDITOR = false  # Set false to use prod even in editor

const POLL_INTERVAL: float = 2.0
const DEVICE_CODE_EXPIRY: int = 600  # 10 minutes
const HEARTBEAT_INTERVAL: float = 10.0  # Check connection every 10 seconds
const DATA_SYNC_INTERVAL: float = 30.0  # Sync achievement data every 30 seconds

# Auth state
var auth_token: String = ""
var user_id: int = -1
var username: String = ""  # Internal username (ashbane-XXXXXXXX)
var display_name: String = ""  # User-friendly name (Player #N)
var ashbane_tier: Dictionary = {}
var providers: Array = []
var achievements: Array = []
var by_rarity: Dictionary = {}  # Achievement counts by rarity
var tier_thresholds: Dictionary = {}  # Tier definitions from backend
var total_achievements: int = 0
var is_guest: bool = true
var is_authenticated: bool = false
var saved_appearance: Dictionary = {}  # Character appearance for Armory preview

# Device auth state
var _device_code: String = ""
var _poll_timer: Timer = null
var _is_polling: bool = false

# Connection retry state
var _retry_timer: Timer = null
var _retry_count: int = 0
const MAX_RETRY_COUNT: int = 10  # Give up after 10 retries
const RETRY_INTERVAL: float = 5.0  # Retry every 5 seconds

# Live connection monitoring
var connection_status: int = ConnectionStatus.DISCONNECTED
var _heartbeat_timer: Timer = null
var _data_sync_timer: Timer = null
var _last_successful_ping: float = 0.0
var _consecutive_failures: int = 0
const MAX_CONSECUTIVE_FAILURES: int = 3  # Mark disconnected after 3 failed pings

# Pending error message to show after scene change
var pending_error_message: String = ""

# Track profile data hash to detect actual changes (avoid redundant UI refreshes)
var _last_profile_hash: int = 0
var _is_first_profile_load: bool = true  # Always emit on first load

# HTTP request nodes
var _http_request: HTTPRequest = null

# ===============================================================================
# HELPER: Clean error messages (strip HTML from server responses)
# ===============================================================================

static func _clean_error_body(body: String, response_code: int) -> String:
	"""Extract a clean error message from server response, stripping HTML"""
	if body.is_empty():
		return "Empty response"

	# Check if it's HTML (ngrok error pages, etc.)
	if body.strip_edges().begins_with("<!DOCTYPE") or body.strip_edges().begins_with("<html"):
		# Try to extract ngrok error code from noscript tag
		var noscript_start = body.find("<noscript>")
		var noscript_end = body.find("</noscript>")
		if noscript_start != -1 and noscript_end != -1:
			var error_text = body.substr(noscript_start + 10, noscript_end - noscript_start - 10)
			return error_text.strip_edges()
		# Fallback: generic message based on status code
		match response_code:
			400: return "Bad Request (server may be down)"
			502, 503, 504: return "Server unavailable (ngrok tunnel down?)"
			_: return "Server returned HTML error page"

	# If it's JSON-ish, try to extract error field
	if body.strip_edges().begins_with("{"):
		var json = JSON.new()
		if json.parse(body) == OK and json.data is Dictionary:
			var data = json.data as Dictionary
			if data.has("error"):
				return str(data.error)
			if data.has("detail"):
				return str(data.detail)
			if data.has("message"):
				return str(data.message)

	# Truncate long responses
	if body.length() > 100:
		return body.substr(0, 100) + "..."

	return body

func _ready() -> void:
	_setup_http_request()
	_load_saved_token()

func _setup_http_request() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)

# ===============================================================================
# PUBLIC API
# ===============================================================================

func start_login() -> void:
	"""Initiate device code authentication flow (generic)"""
	start_login_with_provider("")

func start_login_with_provider(provider: String) -> void:
	"""Initiate device code authentication flow with specific provider"""
	if _is_polling:
		LogManager.warning("Auth already in progress", "ashbane")
		return

	if provider != "":
		LogManager.info("Starting Ashbane auth flow with provider: %s" % provider, "ashbane")
	else:
		LogManager.info("Starting Ashbane device auth flow", "ashbane")
	_request_device_code(provider)

func logout() -> void:
	"""Clear authentication and saved token"""
	auth_token = ""
	user_id = -1
	username = ""
	display_name = ""
	ashbane_tier = {}
	providers = []
	achievements = []
	by_rarity = {}
	tier_thresholds = {}
	total_achievements = 0
	is_guest = true
	is_authenticated = false
	saved_appearance = {}

	# Reset profile change tracking so next login emits signals
	_last_profile_hash = 0
	_is_first_profile_load = true

	_stop_polling()
	_delete_saved_token()
	stop_live_connection()

	# Clear user context from logging system
	LogManager.clear_user_context()

	LogManager.info("Logged out of Ashbane", "ashbane")
	logout_completed.emit()

func save_appearance(appearance_data: Dictionary, callback: Callable = Callable()) -> void:
	"""Save character appearance to backend for Armory preview."""
	if not is_authenticated:
		LogManager.warning("Cannot save appearance - not authenticated", "ashbane")
		if callback.is_valid():
			callback.call(false)
		return

	var url = get_api_base() + "/api/me/appearance"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"Content-Type: application/json",
		"ngrok-skip-browser-warning: true"
	]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_save_appearance_response.bind(request, callback))

	var json_body = JSON.stringify(appearance_data)
	var error = request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if error != OK:
		LogManager.error("Failed to save appearance: %s" % error, "ashbane")
		request.queue_free()
		if callback.is_valid():
			callback.call(false)

func _on_save_appearance_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	var success = result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	if not success:
		LogManager.warning("Failed to save appearance: result=%d, code=%d" % [result, response_code], "ashbane")
	else:
		LogManager.info("Appearance saved successfully", "ashbane")

	if callback.is_valid():
		callback.call(success)

func refresh_profile() -> void:
	"""Fetch latest profile from API"""
	if not is_authenticated:
		LogManager.warning("Cannot refresh profile - not authenticated", "ashbane")
		return

	_fetch_profile()

func is_logged_in() -> bool:
	return is_authenticated and auth_token != "" and user_id > 0

func get_api_base() -> String:
	# Check for local override file first (highest priority)
	if FileAccess.file_exists(API_OVERRIDE_PATH):
		var file = FileAccess.open(API_OVERRIDE_PATH, FileAccess.READ)
		if file:
			var override_url = file.get_as_text().strip_edges()
			file.close()
			if override_url != "":
				return override_url

	# Export builds ALWAYS use production (LAN IP never exposed in releases)
	if OS.has_feature("standalone") or OS.has_feature("template"):
		return API_BASE_PROD

	# Editor/debug builds: use LAN if enabled, otherwise prod
	if USE_LAN_IN_EDITOR:
		return API_BASE_LAN
	return API_BASE_PROD

# ===============================================================================
# DEVICE CODE FLOW
# ===============================================================================

func _request_device_code(provider: String = "") -> void:
	"""Step 1: Request device code from backend"""
	var url = get_api_base() + "/api/auth/device"
	if provider != "":
		url += "?provider=" + provider

	LogManager.info("Requesting device code from: %s" % url, "ashbane")

	var request = HTTPRequest.new()
	request.timeout = 15.0  # 15 second timeout - fail fast if backend is slow
	add_child(request)
	request.request_completed.connect(_on_device_code_response.bind(request))

	# ngrok-skip-browser-warning header bypasses ngrok's interstitial page
	var headers = ["ngrok-skip-browser-warning: true"]
	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to request device code: %s" % error, "ashbane")
		auth_failed.emit("Failed to connect to auth server")

func _on_device_code_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Device code request failed: %d / %d" % [result, response_code], "ashbane")
		auth_failed.emit("Auth server unavailable")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse device code response", "ashbane")
		auth_failed.emit("Invalid server response")
		return

	var data = json.data
	_device_code = data.get("device_code", "")
	var auth_url = data.get("auth_url", "")

	if _device_code == "" or auth_url == "":
		LogManager.error("Invalid device code response", "ashbane")
		auth_failed.emit("Invalid auth response")
		return

	LogManager.info("Device code received, opening browser", "ashbane")

	# Open browser for user to authenticate
	OS.shell_open(auth_url)

	# Emit signal so UI can show "waiting for browser auth"
	auth_started.emit(auth_url)

	# Start polling for completion
	_start_polling()

func _start_polling() -> void:
	"""Poll auth status every POLL_INTERVAL seconds"""
	_is_polling = true

	if _poll_timer:
		_poll_timer.queue_free()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.timeout.connect(_poll_auth_status)
	add_child(_poll_timer)
	_poll_timer.start()

	# Also poll immediately
	_poll_auth_status()

func _stop_polling() -> void:
	_is_polling = false
	if _poll_timer:
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null
	_device_code = ""

func cancel_auth() -> void:
	"""Cancel an in-progress authentication attempt"""
	if _is_polling:
		LogManager.info("Auth cancelled by user", "ashbane")
		_stop_polling()

func _poll_auth_status() -> void:
	"""Check if user has completed browser auth"""
	if _device_code == "":
		_stop_polling()
		return

	var url = get_api_base() + "/api/auth/status?device_code=" + _device_code

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_poll_response.bind(request))

	# ngrok-skip-browser-warning header bypasses ngrok's interstitial page
	var headers = ["ngrok-skip-browser-warning: true"]
	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.warning("Poll request failed: %s" % error, "ashbane")

func _on_poll_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		return  # Silent fail, will retry

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.data
	var status = data.get("status", "")

	match status:
		"pending":
			# Still waiting, continue polling
			pass
		"success":
			_stop_polling()
			_handle_auth_success(data)
		"expired":
			_stop_polling()
			LogManager.warning("Device code expired", "ashbane")
			auth_failed.emit("Login session expired. Please try again.")
		_:
			LogManager.warning("Unknown auth status: %s" % status, "ashbane")

func _handle_auth_success(data: Dictionary) -> void:
	"""Process successful authentication"""
	auth_token = data.get("token", "")
	user_id = data.get("user_id", -1)
	username = data.get("username", "")
	display_name = data.get("display_name", "Player #%d" % user_id if user_id >= 0 else "")

	if auth_token == "" or user_id < 0:
		auth_failed.emit("Invalid auth data received")
		return

	is_guest = false
	is_authenticated = true

	# Save token for future sessions
	_save_token()

	LogManager.info("Authenticated as %s (ID: %d)" % [username, user_id], "ashbane")

	# Bring game window to front after browser auth
	_bring_window_to_front()

	# Fetch full profile
	_fetch_profile()

func _bring_window_to_front() -> void:
	"""Bring the game window to front after browser authentication"""
	var window = get_window()
	if window:
		# Request attention first (flashes taskbar)
		window.request_attention()

		# Try to force focus - Windows is restrictive about this
		# but these calls together usually work
		if window.mode == Window.MODE_MINIMIZED:
			window.mode = Window.MODE_WINDOWED
		window.move_to_foreground()
		window.grab_focus()

		# Double-tap after a brief delay - sometimes needed on Windows
		var tree = get_tree()
		if tree:
			tree.create_timer(0.1).timeout.connect(func():
				window.move_to_foreground()
				window.grab_focus()
			)

		LogManager.info("Requested window focus", "ashbane")

# ===============================================================================
# PROFILE FETCHING
# ===============================================================================

func _fetch_profile() -> void:
	"""GET /api/me to get full profile data"""
	var url = get_api_base() + "/api/me"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"ngrok-skip-browser-warning: true"
	]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_profile_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch profile: %s" % error, "ashbane")

func _on_profile_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	print("[AshbaneAuth] Profile response received: result=%d, code=%d" % [result, response_code])

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Profile fetch failed: %d (retry %d/%d)" % [result, _retry_count, MAX_RETRY_COUNT], "ashbane")
		_schedule_profile_retry()
		return

	# Connection successful - reset retry count
	_retry_count = 0
	_stop_retry_timer()

	if response_code == 401:
		# Token expired, need to re-auth
		LogManager.warning("Token expired, clearing session", "ashbane")
		logout()
		auth_failed.emit("Session expired. Please log in again.")
		return

	if response_code != 200:
		var error_body = body.get_string_from_utf8()
		var clean_error = _clean_error_body(error_body, response_code)
		LogManager.error("Profile fetch returned %d: %s" % [response_code, clean_error], "ashbane")
		# Treat 5xx errors as connection issues and retry
		# 4xx errors (except 401) might be token issues - still retry a few times
		if response_code >= 400 and response_code != 401:
			_schedule_profile_retry()
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse profile response", "ashbane")
		return

	var data = json.data

	# Update local state
	user_id = data.get("user_id", user_id)
	username = data.get("username", username)
	display_name = data.get("display_name", "Player #%d" % user_id if user_id >= 0 else display_name)
	total_achievements = data.get("total_achievements", 0)
	ashbane_tier = data.get("ashbane", {})
	if ashbane_tier == null:
		ashbane_tier = {}
	providers = data.get("providers", [])
	if providers == null:
		providers = []
	by_rarity = data.get("by_rarity", {})
	if by_rarity == null:
		by_rarity = {}
	tier_thresholds = data.get("tier_thresholds", {})
	if tier_thresholds == null:
		tier_thresholds = {}
	achievements = data.get("notable_achievements", [])
	if achievements == null:
		achievements = []
	var appearance_val = data.get("appearance", {})
	if appearance_val == null:
		saved_appearance = {}
	else:
		saved_appearance = appearance_val

	LogManager.info("Profile loaded: %s - %s tier (%d achievements)" % [
		username,
		ashbane_tier.get("name", "Unknown"),
		total_achievements
	], "ashbane")

	# Calculate hash of profile data to detect actual changes
	# Using key fields that affect UI: total_achievements, providers count, tier
	var profile_hash = hash(str(total_achievements) + str(providers.size()) + str(ashbane_tier.get("name", "")))
	var data_changed = _is_first_profile_load or (profile_hash != _last_profile_hash)

	if data_changed:
		print("[AshbaneAuth] Profile data changed (hash %d -> %d), emitting signals" % [_last_profile_hash, profile_hash])
		_last_profile_hash = profile_hash
		_is_first_profile_load = false

		# Set user context for logging system (enriches all future logs)
		LogManager.set_user_context(user_id, username)

		# Emit for cosmetics system to process
		profile_updated.emit(data)
		auth_completed.emit(data)
	else:
		print("[AshbaneAuth] Profile data unchanged, skipping UI refresh")

	# Start live connection monitoring after successful profile load
	start_live_connection()

func _schedule_profile_retry() -> void:
	"""Schedule a retry for profile fetch if backend is unavailable"""
	if _retry_count >= MAX_RETRY_COUNT:
		LogManager.error("Max retries reached. Backend appears to be down.", "ashbane")
		_handle_connection_failure()
		return

	_retry_count += 1
	_set_connection_status(ConnectionStatus.CONNECTING)  # Show reconnecting state

	if _retry_timer:
		_retry_timer.queue_free()

	_retry_timer = Timer.new()
	_retry_timer.wait_time = RETRY_INTERVAL
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry_timer)
	add_child(_retry_timer)
	_retry_timer.start()

	LogManager.info("Will retry connection in %.0f seconds..." % RETRY_INTERVAL, "ashbane")

func _on_retry_timer() -> void:
	"""Retry fetching profile"""
	_set_connection_status(ConnectionStatus.CONNECTING)
	LogManager.info("Retrying Ashbane connection (attempt %d/%d)..." % [_retry_count, MAX_RETRY_COUNT], "ashbane")
	_fetch_profile()

func _stop_retry_timer() -> void:
	"""Stop any pending retry"""
	if _retry_timer:
		_retry_timer.stop()
		_retry_timer.queue_free()
		_retry_timer = null

func _handle_connection_failure() -> void:
	"""Handle failed connection to Ashbane backend - logout and return to main menu"""
	LogManager.error("Cannot connect to Ashbane server. Returning to main menu.", "ashbane")

	# Set disconnected status
	_set_connection_status(ConnectionStatus.DISCONNECTED)

	# Clear auth state (but keep the saved token for next attempt)
	auth_token = ""
	user_id = -1
	username = ""
	display_name = ""
	ashbane_tier = {}
	providers = []
	achievements = []
	by_rarity = {}
	tier_thresholds = {}
	total_achievements = 0
	is_guest = true
	is_authenticated = false
	_retry_count = 0

	# Store error message to show after MainMenu loads
	pending_error_message = "Could not connect to Ashbane server. Please check your connection and try again."

	# Return to main menu (MainMenu will check pending_error_message)
	var tree = get_tree()
	if tree:
		tree.change_scene_to_file("res://scenes/ui/MainMenu.tscn")

func get_and_clear_pending_error() -> String:
	"""Get pending error message and clear it (called by MainMenu on load)"""
	var error = pending_error_message
	pending_error_message = ""
	return error

# ===============================================================================
# TOKEN PERSISTENCE
# ===============================================================================

func _load_saved_token() -> void:
	"""Load token from storage on startup (works on both desktop and web)"""
	# Use WebStorage for cross-platform compatibility
	var data = WebStorage.load_json("session_token", {})

	# Fallback: check legacy file path for migration (desktop only)
	if data.is_empty() and not WebStorage.is_web():
		if FileAccess.file_exists(TOKEN_PATH):
			var file = FileAccess.open(TOKEN_PATH, FileAccess.READ)
			if file:
				var json_string = file.get_as_text()
				file.close()
				var json = JSON.new()
				if json.parse(json_string) == OK:
					data = json.data
					# Migrate to WebStorage
					WebStorage.save_json("session_token", data)
					# Remove old file
					DirAccess.remove_absolute(TOKEN_PATH)
					LogManager.info("Migrated session token to WebStorage", "ashbane")

	if data.is_empty():
		LogManager.info("No saved Ashbane session", "ashbane")
		return

	auth_token = data.get("token", "")
	user_id = data.get("user_id", -1)
	username = data.get("username", "")
	display_name = data.get("display_name", "Player #%d" % user_id if user_id >= 0 else "")

	if auth_token != "" and user_id > 0:
		is_guest = false
		is_authenticated = true
		_set_connection_status(ConnectionStatus.CONNECTING)  # Show connecting while we verify

		# Set user context immediately for logging (will be refreshed when profile loads)
		LogManager.set_user_context(user_id, username)

		LogManager.info("Restored Ashbane session for %s (fetching profile...)" % username, "ashbane")
		# Verify token is still valid by fetching profile
		# NOTE: total_achievements will be 0 until _on_profile_response completes
		_fetch_profile()
	else:
		_delete_saved_token()

func _save_token() -> void:
	"""Save token to storage for session persistence (works on both desktop and web)"""
	var data = {
		"token": auth_token,
		"user_id": user_id,
		"username": username,
		"display_name": display_name,
		"saved_at": Time.get_unix_time_from_system()
	}

	if WebStorage.save_json("session_token", data):
		LogManager.info("Saved Ashbane session (%s)" % WebStorage.get_storage_type(), "ashbane")
	else:
		LogManager.error("Failed to save Ashbane token", "ashbane")

func _delete_saved_token() -> void:
	"""Remove saved token from storage"""
	WebStorage.delete_string("session_token")
	# Also clean up legacy file if it exists (desktop only)
	if not WebStorage.is_web() and FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(TOKEN_PATH)

# ===============================================================================
# MULTIPLAYER BADGE API
# ===============================================================================

func get_player_badge(player_user_id: int, callback: Callable) -> void:
	"""Fetch another player's badge for multiplayer display"""
	var url = get_api_base() + "/api/player/%d/badge" % player_user_id

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_badge_response.bind(request, callback))

	var error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		callback.call(null)

func _on_badge_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		callback.call(null)
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		callback.call(null)
		return

	callback.call(json.data)

# ===============================================================================
# LIVE CONNECTION MONITORING
# ===============================================================================

func start_live_connection() -> void:
	"""Start heartbeat monitoring and data sync timers. Call after successful auth."""
	LogManager.info("Starting live connection monitoring", "ashbane")
	_set_connection_status(ConnectionStatus.CONNECTED)
	_consecutive_failures = 0
	_last_successful_ping = Time.get_unix_time_from_system()

	# Start heartbeat timer
	if _heartbeat_timer:
		_heartbeat_timer.queue_free()
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_on_heartbeat_tick)
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()

	# Start data sync timer
	if _data_sync_timer:
		_data_sync_timer.queue_free()
	_data_sync_timer = Timer.new()
	_data_sync_timer.wait_time = DATA_SYNC_INTERVAL
	_data_sync_timer.timeout.connect(_on_data_sync_tick)
	add_child(_data_sync_timer)
	_data_sync_timer.start()

func stop_live_connection() -> void:
	"""Stop heartbeat and data sync. Call on logout."""
	LogManager.info("Stopping live connection monitoring", "ashbane")
	if _heartbeat_timer:
		_heartbeat_timer.stop()
		_heartbeat_timer.queue_free()
		_heartbeat_timer = null
	if _data_sync_timer:
		_data_sync_timer.stop()
		_data_sync_timer.queue_free()
		_data_sync_timer = null
	_set_connection_status(ConnectionStatus.DISCONNECTED)

func _set_connection_status(new_status: int) -> void:
	"""Update connection status and emit signal if changed"""
	if connection_status != new_status:
		var old_status = connection_status
		connection_status = new_status
		var status_names = ["DISCONNECTED", "CONNECTING", "CONNECTED"]
		LogManager.info("Connection status: %s -> %s" % [status_names[old_status], status_names[new_status]], "ashbane")
		connection_status_changed.emit(new_status)

func _on_heartbeat_tick() -> void:
	"""Periodic ping to check if backend is alive"""
	if not is_authenticated or auth_token == "":
		return

	var url = get_api_base() + "/api/health"
	var headers = ["ngrok-skip-browser-warning: true"]

	var request = HTTPRequest.new()
	request.timeout = 5.0  # Short timeout for heartbeat
	add_child(request)
	request.request_completed.connect(_on_heartbeat_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_handle_heartbeat_failure()
		request.queue_free()

func _on_heartbeat_response(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		# Connection healthy
		_consecutive_failures = 0
		_last_successful_ping = Time.get_unix_time_from_system()
		if connection_status != ConnectionStatus.CONNECTED:
			_set_connection_status(ConnectionStatus.CONNECTED)
			# Connection restored - refresh all data
			LogManager.info("Connection restored! Refreshing data...", "ashbane")
			_refresh_all_data()
	else:
		_handle_heartbeat_failure()

func _handle_heartbeat_failure() -> void:
	"""Handle a failed heartbeat ping"""
	_consecutive_failures += 1
	LogManager.warning("Heartbeat failed (attempt %d/%d)" % [_consecutive_failures, MAX_CONSECUTIVE_FAILURES], "ashbane")

	if _consecutive_failures >= MAX_CONSECUTIVE_FAILURES:
		if connection_status != ConnectionStatus.DISCONNECTED:
			_set_connection_status(ConnectionStatus.DISCONNECTED)
	elif connection_status == ConnectionStatus.CONNECTED:
		_set_connection_status(ConnectionStatus.CONNECTING)  # Show "reconnecting" state

func _on_data_sync_tick() -> void:
	"""Periodic sync of achievement data (NOT forge items - those are event-driven)"""
	if connection_status != ConnectionStatus.CONNECTED:
		return  # Don't try to sync if disconnected

	if not is_authenticated or auth_token == "":
		return

	LogManager.info("Syncing achievement data...", "ashbane")
	_fetch_profile()

	# NOTE: Forge items are NOT polled here - they're fetched once on login
	# and refreshed only after specific events (forge, trade, bridge-in/out)

func _refresh_all_data() -> void:
	"""Refresh all data after connection is restored"""
	_fetch_profile()

	# Refresh forge items
	if ForgeItemManager:
		ForgeItemManager.fetch_forged_items()
		ForgeItemManager.fetch_forge_status()
		ForgeItemManager.fetch_wallet_status()
		ForgeItemManager.fetch_bridge_in_available()

func is_connected_to_backend() -> bool:
	"""Check if we have an active connection to the backend"""
	return connection_status == ConnectionStatus.CONNECTED

func get_connection_status_name() -> String:
	"""Get human-readable connection status"""
	match connection_status:
		ConnectionStatus.DISCONNECTED:
			return "Disconnected"
		ConnectionStatus.CONNECTING:
			return "Reconnecting..."
		ConnectionStatus.CONNECTED:
			return "Connected"
		_:
			return "Unknown"

# ═══════════════════════════════════════════════════════════════════════════
# VENDOR PURCHASE API
# ═══════════════════════════════════════════════════════════════════════════

signal vendor_purchase_completed(success: bool, response: Dictionary)

func purchase_from_vendor(item_id: String, vendor_type: String, quantity: int = 1) -> void:
	"""
	Purchase an item from the vendor via backend API.
	Emits vendor_purchase_completed when done.

	vendor_type: "weapons", "armor", "misc", "tools"
	"""
	if not is_authenticated or auth_token == "":
		LogManager.warning("Cannot purchase: not authenticated", "vendor")
		vendor_purchase_completed.emit(false, {"error": "NOT_AUTHENTICATED", "message": "You must be logged in to purchase items"})
		return

	if connection_status != ConnectionStatus.CONNECTED:
		LogManager.warning("Cannot purchase: not connected to backend", "vendor")
		vendor_purchase_completed.emit(false, {"error": "NOT_CONNECTED", "message": "Cannot connect to server"})
		return

	var url = get_api_base() + "/api/vendor/purchase"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"Content-Type: application/json",
		"ngrok-skip-browser-warning: true"
	]

	var body = JSON.stringify({
		"item_id": item_id,
		"vendor_type": vendor_type,
		"quantity": quantity
	})

	var request = HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_vendor_purchase_response.bind(request))

	LogManager.info("Purchasing %s from %s vendor..." % [item_id, vendor_type], "vendor")

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to send purchase request: %d" % error, "vendor")
		request.queue_free()
		vendor_purchase_completed.emit(false, {"error": "REQUEST_FAILED", "message": "Failed to send request"})

func _on_vendor_purchase_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Purchase request failed: result=%d" % result, "vendor")
		vendor_purchase_completed.emit(false, {"error": "CONNECTION_ERROR", "message": "Connection error"})
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		LogManager.error("Failed to parse purchase response", "vendor")
		vendor_purchase_completed.emit(false, {"error": "PARSE_ERROR", "message": "Invalid server response"})
		return

	var data = json.get_data()

	if response_code == 200 and data.get("success", false):
		LogManager.info("Purchase successful: %s for %d gold" % [data.get("item", {}).get("name", "?"), data.get("gold_spent", 0)], "vendor")
		vendor_purchase_completed.emit(true, data)
	else:
		# Error response
		var error_msg = data.get("message", data.get("detail", {}).get("message", "Purchase failed"))
		var error_code = data.get("error", data.get("detail", {}).get("error", "UNKNOWN"))
		LogManager.warning("Purchase failed: %s - %s" % [error_code, error_msg], "vendor")
		vendor_purchase_completed.emit(false, {"error": error_code, "message": error_msg})


signal vendor_sell_completed(success: bool, response: Dictionary)

func sell_to_vendor(item_id: String, vendor_type: String, item_name: String = "Item", quantity: int = 1) -> void:
	"""
	Sell an item to the vendor via backend API.
	Server calculates sell value from its catalog (50% of buy price).

	Args:
		item_id: The item's unique ID (e.g., "rusty_blade", "copper_plate_cuirass")
		vendor_type: One of "weapons", "armor", "misc", "tools", "loot"
		item_name: Display name for logging (not used for value calculation)
		quantity: Number of items to sell

	Emits vendor_sell_completed when done.
	"""
	if not is_authenticated or auth_token == "":
		LogManager.warning("Cannot sell: not authenticated", "vendor")
		vendor_sell_completed.emit(false, {"error": "NOT_AUTHENTICATED", "message": "You must be logged in to sell items"})
		return

	if connection_status != ConnectionStatus.CONNECTED:
		LogManager.warning("Cannot sell: not connected to backend", "vendor")
		vendor_sell_completed.emit(false, {"error": "NOT_CONNECTED", "message": "Cannot connect to server"})
		return

	var url = get_api_base() + "/api/vendor/sell"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"Content-Type: application/json",
		"ngrok-skip-browser-warning: true"
	]

	# Server calculates sell value - we just send item info
	var body = JSON.stringify({
		"item_id": item_id,
		"vendor_type": vendor_type,
		"item_name": item_name,
		"quantity": quantity
	})

	var request = HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_vendor_sell_response.bind(request))

	LogManager.info("Selling %s (x%d) to vendor..." % [item_name, quantity], "vendor")

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to send sell request: %d" % error, "vendor")
		request.queue_free()
		vendor_sell_completed.emit(false, {"error": "REQUEST_FAILED", "message": "Failed to send request"})

func _on_vendor_sell_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Sell request failed: result=%d" % result, "vendor")
		vendor_sell_completed.emit(false, {"error": "CONNECTION_ERROR", "message": "Connection error"})
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		LogManager.error("Failed to parse sell response", "vendor")
		vendor_sell_completed.emit(false, {"error": "PARSE_ERROR", "message": "Invalid server response"})
		return

	var data = json.get_data()

	if response_code == 200 and data.get("success", false):
		LogManager.info("Sell successful: earned %d gold (total: %d)" % [data.get("gold_earned", 0), data.get("new_gold_balance", 0)], "vendor")
		vendor_sell_completed.emit(true, data)
	else:
		var error_msg = data.get("message", data.get("detail", {}).get("message", "Sell failed"))
		var error_code = data.get("error", data.get("detail", {}).get("error", "UNKNOWN"))
		LogManager.warning("Sell failed: %s - %s" % [error_code, error_msg], "vendor")
		vendor_sell_completed.emit(false, {"error": error_code, "message": error_msg})


signal character_sync_completed(success: bool, response: Dictionary)

func sync_character_to_backend(level: int, experience: int, gold: int, inventory: Array, equipped_weapon: String, equipped_armor: Dictionary, weapon_skills: Dictionary = {}, quests: Dictionary = {}, tutorial_completed: bool = false, deleted_forged_items: Dictionary = {}, position_x: float = 0.0, position_y: float = 0.0) -> void:
	"""
	Full character sync to backend on logout - persistent world save.
	Saves gold, level, XP, inventory, equipped items, weapon skills, quests, tutorial state, deleted forged items, and position.
	Emits character_sync_completed when done.
	"""
	if not is_authenticated or auth_token == "":
		LogManager.warning("Cannot sync character: not authenticated", "auth")
		character_sync_completed.emit(false, {"error": "NOT_AUTHENTICATED"})
		return

	var url = get_api_base() + "/api/vendor/character/logout-sync"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"Content-Type: application/json",
		"ngrok-skip-browser-warning: true"
	]

	var body = JSON.stringify({
		"gold": gold,
		"level": level,
		"experience": experience,
		"inventory": inventory,
		"equipped_weapon": equipped_weapon,
		"equipped_armor": equipped_armor,
		"weapon_skills": weapon_skills,
		"quests": quests,
		"tutorial_completed": tutorial_completed,
		"deleted_forged_items": deleted_forged_items,
		"position_x": position_x,
		"position_y": position_y
	})

	var request = HTTPRequest.new()
	request.timeout = 5.0  # Short timeout for logout
	add_child(request)
	request.request_completed.connect(_on_character_sync_response.bind(request))

	LogManager.info("Syncing character to backend: level=%d, gold=%d, inventory=%d items" % [level, gold, inventory.size()], "auth")

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to send character sync request: %d" % error, "auth")
		request.queue_free()
		character_sync_completed.emit(false, {"error": "REQUEST_FAILED"})

func _on_character_sync_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Character sync failed: result=%d" % result, "auth")
		character_sync_completed.emit(false, {"error": "CONNECTION_ERROR"})
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		LogManager.error("Failed to parse character sync response", "auth")
		character_sync_completed.emit(false, {"error": "PARSE_ERROR"})
		return

	var data = json.get_data()

	if response_code == 200 and data.get("success", false):
		LogManager.info("Character synced to backend: level=%d" % data.get("level", 0), "auth")
		character_sync_completed.emit(true, data)
	else:
		var error_msg = data.get("detail", "Sync failed")
		LogManager.warning("Character sync failed: %s" % error_msg, "auth")
		character_sync_completed.emit(false, {"error": "SYNC_FAILED", "message": error_msg})


func get_vendor_character_info(callback: Callable) -> void:
	"""Get character gold and level from backend"""
	if not is_authenticated or auth_token == "":
		callback.call(false, {})
		return

	var url = get_api_base() + "/api/vendor/character"
	var headers = [
		"Authorization: Bearer " + auth_token,
		"ngrok-skip-browser-warning: true"
	]

	var request = HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_vendor_character_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		callback.call(false, {})

func _on_vendor_character_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		callback.call(false, {})
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		callback.call(false, {})
		return

	var data = json.get_data()
	callback.call(true, data)
