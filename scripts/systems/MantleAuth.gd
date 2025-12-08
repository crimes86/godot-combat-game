extends Node
## MantleAuth - Handles authentication with Mantle backend
## Device code flow: open browser -> user logs in -> poll for completion

signal auth_started(auth_url: String)
signal auth_completed(user_data: Dictionary)
signal auth_failed(error: String)
signal profile_updated(profile: Dictionary)
signal logout_completed

# API Configuration
const API_BASE_DEV = "http://127.0.0.1:8000"  # Use IP to avoid IPv6 resolution delay
const API_BASE_PROD = ""  # TBD
const TOKEN_PATH = "user://mantle_session.dat"
const POLL_INTERVAL: float = 2.0
const DEVICE_CODE_EXPIRY: int = 600  # 10 minutes

# Auth state
var auth_token: String = ""
var user_id: int = -1
var username: String = ""
var mantle_tier: Dictionary = {}
var providers: Array = []
var achievements: Array = []
var by_rarity: Dictionary = {}  # Achievement counts by rarity
var tier_thresholds: Dictionary = {}  # Tier definitions from backend
var total_achievements: int = 0
var is_guest: bool = true
var is_authenticated: bool = false

# Device auth state
var _device_code: String = ""
var _poll_timer: Timer = null
var _is_polling: bool = false

# HTTP request nodes
var _http_request: HTTPRequest = null

func _ready() -> void:
	_setup_http_request()
	_load_saved_token()

func _setup_http_request() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	add_child(_http_request)

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func start_login() -> void:
	"""Initiate device code authentication flow (generic)"""
	start_login_with_provider("")

func start_login_with_provider(provider: String) -> void:
	"""Initiate device code authentication flow with specific provider"""
	if _is_polling:
		LogManager.warning("Auth already in progress", "mantle")
		return

	if provider != "":
		LogManager.info("Starting Mantle auth flow with provider: %s" % provider, "mantle")
	else:
		LogManager.info("Starting Mantle device auth flow", "mantle")
	_request_device_code(provider)

func logout() -> void:
	"""Clear authentication and saved token"""
	auth_token = ""
	user_id = -1
	username = ""
	mantle_tier = {}
	providers = []
	achievements = []
	by_rarity = {}
	tier_thresholds = {}
	total_achievements = 0
	is_guest = true
	is_authenticated = false

	_stop_polling()
	_delete_saved_token()

	LogManager.info("Logged out of Mantle", "mantle")
	logout_completed.emit()

func refresh_profile() -> void:
	"""Fetch latest profile from API"""
	if not is_authenticated:
		LogManager.warning("Cannot refresh profile - not authenticated", "mantle")
		return

	_fetch_profile()

func is_logged_in() -> bool:
	return is_authenticated and auth_token != "" and user_id > 0

func get_api_base() -> String:
	# TODO: Add environment detection
	return API_BASE_DEV

# ═══════════════════════════════════════════════════════════════════════════
# DEVICE CODE FLOW
# ═══════════════════════════════════════════════════════════════════════════

func _request_device_code(provider: String = "") -> void:
	"""Step 1: Request device code from backend"""
	var url = get_api_base() + "/api/auth/device"
	if provider != "":
		url += "?provider=" + provider

	var request = HTTPRequest.new()
	request.timeout = 15.0  # 15 second timeout - fail fast if backend is slow
	add_child(request)
	request.request_completed.connect(_on_device_code_response.bind(request))

	var error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to request device code: %s" % error, "mantle")
		auth_failed.emit("Failed to connect to auth server")

func _on_device_code_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Device code request failed: %d / %d" % [result, response_code], "mantle")
		auth_failed.emit("Auth server unavailable")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse device code response", "mantle")
		auth_failed.emit("Invalid server response")
		return

	var data = json.data
	_device_code = data.get("device_code", "")
	var auth_url = data.get("auth_url", "")

	if _device_code == "" or auth_url == "":
		LogManager.error("Invalid device code response", "mantle")
		auth_failed.emit("Invalid auth response")
		return

	LogManager.info("Device code received, opening browser", "mantle")

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

func _poll_auth_status() -> void:
	"""Check if user has completed browser auth"""
	if _device_code == "":
		_stop_polling()
		return

	var url = get_api_base() + "/api/auth/status?device_code=" + _device_code

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_poll_response.bind(request))

	var error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.warning("Poll request failed: %s" % error, "mantle")

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
			LogManager.warning("Device code expired", "mantle")
			auth_failed.emit("Login session expired. Please try again.")
		_:
			LogManager.warning("Unknown auth status: %s" % status, "mantle")

func _handle_auth_success(data: Dictionary) -> void:
	"""Process successful authentication"""
	auth_token = data.get("token", "")
	user_id = data.get("user_id", -1)
	username = data.get("username", "")

	if auth_token == "" or user_id < 0:
		auth_failed.emit("Invalid auth data received")
		return

	is_guest = false
	is_authenticated = true

	# Save token for future sessions
	_save_token()

	LogManager.info("Authenticated as %s (ID: %d)" % [username, user_id], "mantle")

	# Fetch full profile
	_fetch_profile()

# ═══════════════════════════════════════════════════════════════════════════
# PROFILE FETCHING
# ═══════════════════════════════════════════════════════════════════════════

func _fetch_profile() -> void:
	"""GET /api/me to get full profile data"""
	var url = get_api_base() + "/api/me"
	var headers = ["Authorization: Bearer " + auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_profile_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch profile: %s" % error, "mantle")

func _on_profile_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Profile fetch failed: %d" % result, "mantle")
		return

	if response_code == 401:
		# Token expired, need to re-auth
		LogManager.warning("Token expired, clearing session", "mantle")
		logout()
		auth_failed.emit("Session expired. Please log in again.")
		return

	if response_code != 200:
		LogManager.error("Profile fetch returned %d" % response_code, "mantle")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse profile response", "mantle")
		return

	var data = json.data

	# Update local state
	user_id = data.get("user_id", user_id)
	username = data.get("username", username)
	total_achievements = data.get("total_achievements", 0)
	mantle_tier = data.get("mantle", {})
	if mantle_tier == null:
		mantle_tier = {}
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

	LogManager.info("Profile loaded: %s - %s tier (%d achievements)" % [
		username,
		mantle_tier.get("name", "Unknown"),
		total_achievements
	], "mantle")

	# Emit for cosmetics system to process
	profile_updated.emit(data)
	auth_completed.emit(data)

# ═══════════════════════════════════════════════════════════════════════════
# TOKEN PERSISTENCE
# ═══════════════════════════════════════════════════════════════════════════

func _load_saved_token() -> void:
	"""Load token from disk on startup"""
	if not FileAccess.file_exists(TOKEN_PATH):
		LogManager.info("No saved Mantle session", "mantle")
		return

	var file = FileAccess.open(TOKEN_PATH, FileAccess.READ)
	if not file:
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		LogManager.warning("Failed to parse saved token", "mantle")
		_delete_saved_token()
		return

	var data = json.data
	auth_token = data.get("token", "")
	user_id = data.get("user_id", -1)
	username = data.get("username", "")

	if auth_token != "" and user_id > 0:
		is_guest = false
		is_authenticated = true
		LogManager.info("Restored Mantle session for %s" % username, "mantle")
		# Verify token is still valid by fetching profile
		_fetch_profile()
	else:
		_delete_saved_token()

func _save_token() -> void:
	"""Save token to disk for session persistence"""
	var file = FileAccess.open(TOKEN_PATH, FileAccess.WRITE)
	if not file:
		LogManager.error("Failed to save Mantle token", "mantle")
		return

	var data = {
		"token": auth_token,
		"user_id": user_id,
		"username": username,
		"saved_at": Time.get_unix_time_from_system()
	}

	file.store_string(JSON.stringify(data))
	file.close()
	LogManager.info("Saved Mantle session", "mantle")

func _delete_saved_token() -> void:
	"""Remove saved token file"""
	if FileAccess.file_exists(TOKEN_PATH):
		DirAccess.remove_absolute(TOKEN_PATH)

# ═══════════════════════════════════════════════════════════════════════════
# MULTIPLAYER BADGE API
# ═══════════════════════════════════════════════════════════════════════════

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
