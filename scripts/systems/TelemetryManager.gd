extends Node
## TelemetryManager - Batches and sends logs to backend
## Add to project.godot autoloads as "TelemetryManager" (after LogManager and AshbaneAuth)
##
## Usage:
##   Automatic: Hooks into LogManager.log_written signal
##   Manual: TelemetryManager.track_event("player_died", {"zone": "forest"})
##
## Configuration:
##   TelemetryManager.enabled = true/false
##   TelemetryManager.remote_min_level = LogManager.LogLevel.INFO
##   TelemetryManager.set_remote_categories(["combat", "anticheat"])

signal batch_sent(count: int)
signal batch_failed(error: String)
signal telemetry_enabled_changed(enabled: bool)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Enable/disable remote telemetry
var enabled: bool = true

## Minimum log level to send remotely (DEBUG=0, INFO=1, WARN=2, ERROR=3)
var remote_min_level: int = 1  # INFO and above by default

## Categories to send remotely (empty = all categories that pass level filter)
var remote_categories: Array[String] = []

## Categories that ALWAYS get sent regardless of level (critical events)
var always_send_categories: Array[String] = ["anticheat", "error", "crash", "duel"]

## API endpoint path (appended to AshbaneAuth.get_api_base())
var api_endpoint: String = "/api/logs/batch"

# ═══════════════════════════════════════════════════════════════════════════
# BATCHING SETTINGS
# ═══════════════════════════════════════════════════════════════════════════

## How often to send batched logs (seconds)
const BATCH_INTERVAL: float = 5.0

## Maximum logs to queue before forcing a send
const MAX_BATCH_SIZE: int = 100

## Maximum retry attempts on failure
const MAX_RETRY_ATTEMPTS: int = 3

## Base delay for exponential backoff (seconds)
const RETRY_BACKOFF_BASE: float = 2.0

## Maximum logs to keep in memory when offline
const MAX_OFFLINE_QUEUE: int = 500

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL STATE
# ═══════════════════════════════════════════════════════════════════════════

var _pending_logs: Array = []
var _batch_timer: Timer = null
var _http_request: HTTPRequest = null
var _is_sending: bool = false
var _retry_count: int = 0
var _last_send_failed: bool = false
var _total_sent: int = 0
var _total_dropped: int = 0

# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Skip telemetry on dedicated server (no need for client-side logging)
	if _is_dedicated_server():
		enabled = false
		print("[TelemetryManager] Disabled on dedicated server")
		return

	# Wait a frame to ensure LogManager and AshbaneAuth are ready
	if not is_inside_tree():
		push_warning("[TelemetryManager] Not in tree, skipping initialization")
		return
	await get_tree().process_frame

	_setup_timer()
	_setup_http()
	_connect_to_log_manager()

func _is_dedicated_server() -> bool:
	"""Check if running as dedicated server"""
	var args = OS.get_cmdline_user_args()
	return "--server" in args

func _exit_tree() -> void:
	# Try to flush remaining logs before exit
	if not _pending_logs.is_empty() and enabled:
		_flush_batch_sync()

func _setup_timer() -> void:
	_batch_timer = Timer.new()
	_batch_timer.wait_time = BATCH_INTERVAL
	_batch_timer.timeout.connect(_on_batch_timer)
	_batch_timer.autostart = true
	add_child(_batch_timer)

func _setup_http() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = 30.0
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)

func _connect_to_log_manager() -> void:
	if LogManager:
		LogManager.log_written.connect(_on_log_written)

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func track_event(event_type: String, data: Dictionary = {}) -> void:
	"""Track a custom event (always sent, regardless of level filtering)"""
	if not enabled:
		return

	var entry = _create_log_entry(1, event_type, "event", data)  # INFO level
	entry["event_type"] = event_type
	_pending_logs.append(entry)

	# Flush immediately for important events
	if _pending_logs.size() >= MAX_BATCH_SIZE:
		_flush_batch()

func set_remote_categories(categories: Array[String]) -> void:
	"""Set which categories to send remotely (empty = all)"""
	remote_categories = categories
	LogManager.info("Remote categories set: %s" % (categories if categories else ["ALL"]), "telemetry")

func set_enabled(value: bool) -> void:
	"""Enable or disable remote telemetry"""
	if enabled != value:
		enabled = value
		telemetry_enabled_changed.emit(value)
		LogManager.info("Telemetry %s" % ("enabled" if value else "disabled"), "telemetry")

func force_flush() -> void:
	"""Force an immediate flush of pending logs"""
	_flush_batch()

func get_stats() -> Dictionary:
	"""Get telemetry statistics"""
	return {
		"enabled": enabled,
		"pending": _pending_logs.size(),
		"total_sent": _total_sent,
		"total_dropped": _total_dropped,
		"is_sending": _is_sending,
		"last_failed": _last_send_failed
	}

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL METHODS
# ═══════════════════════════════════════════════════════════════════════════

func _on_log_written(level: int, message: String, category: String, timestamp: float) -> void:
	"""Called when LogManager writes a log entry"""
	if not enabled:
		return

	# Check if this log should be sent remotely
	if not _should_send_remote(level, category):
		return

	var entry = _create_log_entry(level, message, category)
	entry["ts"] = timestamp

	_pending_logs.append(entry)

	# Enforce queue size limit
	while _pending_logs.size() > MAX_OFFLINE_QUEUE:
		_pending_logs.pop_front()
		_total_dropped += 1

	# Flush early for errors or when batch is full
	if level >= LogManager.LogLevel.ERROR or _pending_logs.size() >= MAX_BATCH_SIZE:
		_flush_batch()

func _should_send_remote(level: int, category: String) -> bool:
	"""Determine if a log entry should be sent to the backend"""
	# Always send critical categories
	if category in always_send_categories:
		return true

	# Check level filter
	if level < remote_min_level:
		return false

	# Check category filter (empty = all categories)
	if not remote_categories.is_empty() and category not in remote_categories:
		return false

	return true

func _create_log_entry(level: int, message: String, category: String, extra: Dictionary = {}) -> Dictionary:
	"""Create a log entry dictionary"""
	var context = LogManager.get_log_context()

	var entry = {
		"ts": Time.get_unix_time_from_system(),
		"level": level,
		"category": category,
		"message": message,
		"session_id": context.session_id,
		"device_id": context.device_id,
	}

	# Add user context if authenticated
	if context.user_id > 0:
		entry["user_id"] = context.user_id
		entry["username"] = context.username

	# Merge any extra data
	entry.merge(extra)

	return entry

func _on_batch_timer() -> void:
	"""Timer callback to flush batched logs"""
	if not _pending_logs.is_empty():
		_flush_batch()

func _flush_batch() -> void:
	"""Send pending logs to backend"""
	if _pending_logs.is_empty() or _is_sending:
		return

	# Check if authenticated
	if not _is_authenticated():
		# Keep logs in queue, will send after auth
		return

	_is_sending = true
	var batch = _pending_logs.duplicate()
	_pending_logs.clear()

	var payload = {
		"logs": batch,
		"client_version": _get_client_version(),
		"platform": OS.get_name(),
		"is_host": _is_multiplayer_host(),
	}

	var url = _get_api_url()
	var headers = _get_auth_headers()

	var json_body = JSON.stringify(payload)
	var error = _http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)

	if error != OK:
		LogManager.warn("Failed to send telemetry batch: %s" % error, "telemetry")
		# Put logs back for retry
		_pending_logs.append_array(batch)
		_is_sending = false
		_last_send_failed = true

func _flush_batch_sync() -> void:
	"""Synchronous flush for exit (best effort)"""
	if _pending_logs.is_empty() or not _is_authenticated():
		return

	# Use a fresh HTTPRequest for sync
	var http = HTTPRequest.new()
	add_child(http)

	var payload = {
		"logs": _pending_logs,
		"client_version": _get_client_version(),
		"platform": OS.get_name(),
		"is_host": _is_multiplayer_host(),
	}

	var url = _get_api_url()
	var headers = _get_auth_headers()

	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	# Don't wait for response - best effort on exit

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	"""Handle HTTP response"""
	_is_sending = false

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.warn("Telemetry request failed (result: %d)" % result, "telemetry")
		_handle_failure()
		return

	if response_code != 200:
		var body_text = body.get_string_from_utf8()
		LogManager.warn("Telemetry rejected (code: %d): %s" % [response_code, body_text.substr(0, 100)], "telemetry")
		_handle_failure()
		return

	# Success!
	_retry_count = 0
	_last_send_failed = false

	# Parse response to get count
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK:
		var data = json.get_data()
		if data is Dictionary and data.has("count"):
			_total_sent += data.count
			batch_sent.emit(data.count)

func _handle_failure() -> void:
	"""Handle send failure with exponential backoff"""
	_last_send_failed = true
	_retry_count += 1

	if _retry_count >= MAX_RETRY_ATTEMPTS:
		LogManager.error("Telemetry: Max retries reached, dropping batch", "telemetry")
		_retry_count = 0
		batch_failed.emit("Max retries exceeded")
		return

	# Exponential backoff
	var delay = RETRY_BACKOFF_BASE * pow(2, _retry_count - 1)
	LogManager.debug("Telemetry: Retrying in %.1fs (attempt %d/%d)" % [delay, _retry_count, MAX_RETRY_ATTEMPTS], "telemetry")

	# Schedule retry
	get_tree().create_timer(delay).timeout.connect(_flush_batch)

# ═══════════════════════════════════════════════════════════════════════════
# HELPER METHODS
# ═══════════════════════════════════════════════════════════════════════════

func _is_authenticated() -> bool:
	"""Check if we have valid auth to send logs"""
	if not AshbaneAuth:
		return false
	return AshbaneAuth.is_authenticated and AshbaneAuth.auth_token != ""

func _get_api_url() -> String:
	"""Get full API URL for logging endpoint"""
	if AshbaneAuth and AshbaneAuth.has_method("get_api_base"):
		return AshbaneAuth.get_api_base() + api_endpoint
	# Fallback
	return "https://api.ashbane.net" + api_endpoint

func _get_auth_headers() -> PackedStringArray:
	"""Get authentication headers for API request"""
	var headers = PackedStringArray()
	if AshbaneAuth and AshbaneAuth.auth_token:
		headers.append("Authorization: Bearer " + AshbaneAuth.auth_token)
	headers.append("Content-Type: application/json")
	return headers

func _get_client_version() -> String:
	"""Get client version string"""
	if NetworkManager and "NETWORK_VERSION" in NetworkManager:
		return str(NetworkManager.NETWORK_VERSION)
	return "unknown"

func _is_multiplayer_host() -> bool:
	"""Check if this client is hosting a multiplayer game"""
	if multiplayer:
		return multiplayer.is_server()
	return false
