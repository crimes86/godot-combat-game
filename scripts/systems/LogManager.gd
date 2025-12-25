extends Node
## LogManager - Centralized logging system with toggleable verbosity
## Add to project.godot autoloads as "LogManager"
##
## Usage:
##   LogManager.info("Player spawned at %s" % position)
##   LogManager.debug("Combat calculation: %d" % damage)
##   LogManager.warn("Low health warning")
##   LogManager.error("Failed to load resource")
##
## Log levels can be configured per-category and globally.
## Server builds typically want more verbose logging than clients.
##
## Features:
##   - Console, file, and remote logging
##   - Session/device tracking for log attribution
##   - Automatic log rotation (keeps last 7 days)
##   - Playtest mode routes to in-game ChatUI

## Emitted when a log is written (for TelemetryManager to hook into)
signal log_written(level: int, message: String, category: String, timestamp: float)

enum LogLevel {
	DEBUG = 0,   # Detailed debugging info (combat math, state changes)
	INFO = 1,    # General information (player actions, system events)
	WARN = 2,    # Warnings (non-fatal issues)
	ERROR = 3,   # Errors (failures that need attention)
	NONE = 4     # Disable all logging
}

# Global log level - messages below this level are suppressed
var global_level: LogLevel = LogLevel.INFO

# Category-specific log levels (override global for specific systems)
var category_levels: Dictionary = {}

# Whether to include timestamps in log output
var include_timestamps: bool = true

# Whether to include category prefixes
var include_category: bool = true

# ═══════════════════════════════════════════════════════════════════════════
# SESSION & DEVICE TRACKING
# ═══════════════════════════════════════════════════════════════════════════

## Unique ID for this game session (generated on startup)
var session_id: String = ""

## Persistent device identifier (stored in user://device_id.txt)
var device_id: String = ""

## User context (set after authentication via set_user_context)
var user_id: int = -1
var username: String = ""

# ═══════════════════════════════════════════════════════════════════════════
# FILE LOGGING
# ═══════════════════════════════════════════════════════════════════════════

# Log to file (servers always, clients optionally)
var log_to_file: bool = false
var log_dir: String = "user://logs"
var log_file_path: String = ""  # Set dynamically based on date
var _log_file: FileAccess = null

# Log rotation settings
var max_log_files: int = 7          # Keep logs for 7 days
var max_log_size_mb: float = 10.0   # Rotate if file exceeds this size
var _current_log_date: String = ""  # Track date for rotation

# Client logging (can be enabled separately from server logging)
var client_log_enabled: bool = false

# Playtest mode - routes important debug messages to in-game ChatUI
var playtest_mode: bool = false
var _chat_ui: Node = null
# Categories to show in chat during playtest (keeps chat from being spammed)
var playtest_categories: Array[String] = ["loot", "combat", "network"]

# Category emoji prefixes for visual scanning
const CATEGORY_ICONS: Dictionary = {
	"combat": "⚔️",
	"network": "🌐",
	"player": "🧑",
	"enemy": "👹",
	"inventory": "🎒",
	"database": "📀",
	"ui": "🖥️",
	"audio": "🔊",
	"world": "🌍",
	"quest": "📜",
	"tutorial": "📖",
	"campfire": "🔥",
	"loot": "💎",
	"anticheat": "🛡️",
	"telemetry": "📡",
	"auth": "🔐",
	"trading": "💱",
	"forge": "🔨",
	"equipment": "🎽",
	"pvp": "⚔️",
	"duel": "🤺",
	"default": "📋"
}

func _ready() -> void:
	# Generate session and device IDs first
	_generate_session_id()
	_load_or_create_device_id()

	# Auto-configure based on build type
	if OS.has_feature("dedicated_server") or _is_server_instance():
		# Server: verbose logging, always log to file
		global_level = LogLevel.DEBUG
		log_to_file = true
		include_timestamps = true
	elif OS.is_debug_build():
		# Debug client: verbose console, optional file logging
		global_level = LogLevel.DEBUG
		log_to_file = false  # Can be enabled with enable_client_logging()
	else:
		# Release client: quiet console, but enable file logging for debugging
		global_level = LogLevel.WARN
		log_to_file = true  # Always log to file for bug reports
		client_log_enabled = true

	# Ensure log directory exists and rotate old logs
	if log_to_file or client_log_enabled:
		_ensure_log_directory()
		_rotate_old_logs()
		_open_log_file()

	info("LogManager initialized (level: %s, file: %s, session: %s)" % [
		LogLevel.keys()[global_level],
		log_to_file,
		session_id.substr(0, 8) + "..."
	], "default")

func _exit_tree() -> void:
	if _log_file:
		_log_file.close()
		_log_file = null

func _is_server_instance() -> bool:
	"""Check if this is running as a dedicated server"""
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--dedicated" or arg == "--headless":
			return true
	return false

# ═══════════════════════════════════════════════════════════════════════════
# SESSION & DEVICE ID MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _generate_session_id() -> void:
	"""Generate a unique session ID for this game launch"""
	# Use UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
	var uuid = ""
	for i in range(32):
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		if i == 12:
			uuid += "4"  # Version 4
		elif i == 16:
			uuid += ["8", "9", "a", "b"][randi() % 4]  # Variant
		else:
			uuid += "0123456789abcdef"[randi() % 16]
	session_id = uuid

func _load_or_create_device_id() -> void:
	"""Load persistent device ID or create one if not exists"""
	var device_file_path = "user://device_id.txt"

	if FileAccess.file_exists(device_file_path):
		var file = FileAccess.open(device_file_path, FileAccess.READ)
		if file:
			device_id = file.get_line().strip_edges()
			file.close()
			if device_id.length() == 36:  # Valid UUID length
				return

	# Generate new device ID
	_generate_session_id()  # Reuse UUID generation
	device_id = session_id
	_generate_session_id()  # Generate fresh session ID

	# Save device ID
	var file = FileAccess.open(device_file_path, FileAccess.WRITE)
	if file:
		file.store_line(device_id)
		file.close()

func set_user_context(p_user_id: int, p_username: String) -> void:
	"""Set user context after authentication (enriches all future logs)"""
	user_id = p_user_id
	username = p_username
	info("User context set: %s (ID: %d)" % [username, user_id], "auth")

func clear_user_context() -> void:
	"""Clear user context on logout"""
	user_id = -1
	username = ""
	info("User context cleared", "auth")

func get_log_context() -> Dictionary:
	"""Get current logging context for external systems (e.g., TelemetryManager)"""
	return {
		"session_id": session_id,
		"device_id": device_id,
		"user_id": user_id,
		"username": username
	}

# ═══════════════════════════════════════════════════════════════════════════
# FILE LOGGING WITH ROTATION
# ═══════════════════════════════════════════════════════════════════════════

func _ensure_log_directory() -> void:
	"""Create log directory if it doesn't exist"""
	if not DirAccess.dir_exists_absolute(log_dir):
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir("logs")

func _get_log_filename_for_date(date: String) -> String:
	"""Get log filename for a specific date"""
	var prefix = "server" if _is_server_instance() else "game"
	return "%s/%s_%s.log" % [log_dir, prefix, date]

func _get_current_date_string() -> String:
	"""Get current date as YYYY-MM-DD string"""
	var date = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date.year, date.month, date.day]

func _open_log_file() -> void:
	"""Open log file for writing (creates new file per day)"""
	# Close existing file if open
	if _log_file:
		_log_file.close()
		_log_file = null

	_current_log_date = _get_current_date_string()
	log_file_path = _get_log_filename_for_date(_current_log_date)

	# Append to existing file for today, or create new
	_log_file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if _log_file:
		_log_file.seek_end()
	else:
		# File doesn't exist, create it
		_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)

	if not _log_file:
		push_error("[LogManager] Failed to open log file: %s" % log_file_path)
		log_to_file = false
	else:
		# Write session start marker
		var timestamp = Time.get_datetime_string_from_system()
		_log_file.store_line("\n" + "=" .repeat(80))
		_log_file.store_line("SESSION START: %s" % timestamp)
		_log_file.store_line("Session ID: %s" % session_id)
		_log_file.store_line("Device ID: %s" % device_id)
		_log_file.store_line("Platform: %s" % OS.get_name())
		_log_file.store_line("=" .repeat(80) + "\n")
		_log_file.flush()

func _rotate_old_logs() -> void:
	"""Delete log files older than max_log_files days"""
	var dir = DirAccess.open(log_dir)
	if not dir:
		return

	var today = Time.get_unix_time_from_system()
	var max_age_seconds = max_log_files * 24 * 60 * 60

	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if filename.ends_with(".log"):
			var file_path = log_dir + "/" + filename
			var modified_time = FileAccess.get_modified_time(file_path)
			if today - modified_time > max_age_seconds:
				dir.remove(filename)
				print("[LogManager] Rotated old log: %s" % filename)
		filename = dir.get_next()
	dir.list_dir_end()

func _check_log_rotation() -> void:
	"""Check if we need to rotate to a new log file (date change or size limit)"""
	var current_date = _get_current_date_string()

	# Rotate on date change
	if current_date != _current_log_date:
		_open_log_file()
		return

	# Rotate on size limit
	if _log_file:
		var size_mb = _log_file.get_position() / (1024.0 * 1024.0)
		if size_mb >= max_log_size_mb:
			# Rename current file with timestamp suffix
			_log_file.close()
			var timestamp = Time.get_time_dict_from_system()
			var suffix = "_%02d%02d%02d" % [timestamp.hour, timestamp.minute, timestamp.second]
			var new_path = log_file_path.replace(".log", suffix + ".log")
			DirAccess.rename_absolute(log_file_path, new_path)
			_open_log_file()

func enable_client_logging() -> void:
	"""Enable file logging for clients (useful for debugging)"""
	if not log_to_file:
		client_log_enabled = true
		log_to_file = true
		_ensure_log_directory()
		_rotate_old_logs()
		_open_log_file()
		info("Client file logging enabled: %s" % log_file_path, "default")

func disable_client_logging() -> void:
	"""Disable file logging for clients"""
	if client_log_enabled:
		client_log_enabled = false
		log_to_file = false
		if _log_file:
			_log_file.close()
			_log_file = null
		info("Client file logging disabled", "default")

func get_log_file_path() -> String:
	"""Get current log file path (for sharing with support)"""
	return log_file_path

func get_all_log_files() -> Array[String]:
	"""Get list of all log files (for bug report attachment)"""
	var files: Array[String] = []
	var dir = DirAccess.open(log_dir)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if filename.ends_with(".log"):
				files.append(log_dir + "/" + filename)
			filename = dir.get_next()
		dir.list_dir_end()
	return files

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC LOGGING METHODS
# ═══════════════════════════════════════════════════════════════════════════

func debug(message: String, category: String = "default") -> void:
	"""Log debug-level message (detailed info for development)"""
	_log(LogLevel.DEBUG, message, category)

func info(message: String, category: String = "default") -> void:
	"""Log info-level message (general system events)"""
	_log(LogLevel.INFO, message, category)

func warn(message: String, category: String = "default") -> void:
	"""Log warning-level message (non-fatal issues)"""
	_log(LogLevel.WARN, message, category)
	push_warning(message)  # Also use Godot's warning system

func warning(message: String, category: String = "default") -> void:
	"""Alias for warn()"""
	warn(message, category)

func error(message: String, category: String = "default") -> void:
	"""Log error-level message (failures needing attention)"""
	_log(LogLevel.ERROR, message, category)
	push_error(message)  # Also use Godot's error system

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION METHODS
# ═══════════════════════════════════════════════════════════════════════════

func set_level(level: LogLevel) -> void:
	"""Set global log level"""
	global_level = level
	info("Log level changed to: %s" % LogLevel.keys()[level], "default")

func set_category_level(category: String, level: LogLevel) -> void:
	"""Set log level for a specific category"""
	category_levels[category] = level

func enable_file_logging(path: String = "") -> void:
	"""Enable logging to file"""
	if not path.is_empty():
		log_file_path = path
	log_to_file = true
	_open_log_file()

func disable_file_logging() -> void:
	"""Disable logging to file"""
	log_to_file = false
	if _log_file:
		_log_file.close()
		_log_file = null

func set_verbose(verbose: bool) -> void:
	"""Quick toggle for verbose (debug) vs quiet (warn) mode"""
	global_level = LogLevel.DEBUG if verbose else LogLevel.WARN

# ═══════════════════════════════════════════════════════════════════════════
# PLAYTEST MODE - Routes debug to in-game chat
# ═══════════════════════════════════════════════════════════════════════════

func enable_playtest_mode(categories: Array[String] = []) -> void:
	"""Enable playtest mode - shows debug messages in ChatUI"""
	playtest_mode = true
	if not categories.is_empty():
		playtest_categories = categories
	# Also enable debug logging
	global_level = LogLevel.DEBUG
	_send_to_chat("[PLAYTEST] Debug mode enabled - watching: %s" % ", ".join(playtest_categories))
	info("Playtest mode enabled for categories: %s" % playtest_categories)

func disable_playtest_mode() -> void:
	"""Disable playtest mode"""
	playtest_mode = false
	_send_to_chat("[PLAYTEST] Debug mode disabled")
	info("Playtest mode disabled")

func toggle_playtest_mode() -> void:
	"""Toggle playtest mode on/off"""
	if playtest_mode:
		disable_playtest_mode()
	else:
		enable_playtest_mode()

func add_playtest_category(category: String) -> void:
	"""Add a category to watch in playtest mode"""
	if category not in playtest_categories:
		playtest_categories.append(category)
		_send_to_chat("[PLAYTEST] Now watching: %s" % category)

func remove_playtest_category(category: String) -> void:
	"""Remove a category from playtest watch list"""
	var idx = playtest_categories.find(category)
	if idx >= 0:
		playtest_categories.remove_at(idx)
		_send_to_chat("[PLAYTEST] Stopped watching: %s" % category)

func _get_chat_ui() -> Node:
	"""Find ChatUI in the scene tree"""
	if _chat_ui and is_instance_valid(_chat_ui):
		return _chat_ui

	# Search for ChatUI in tree
	var root = get_tree().root if get_tree() else null
	if root:
		# ChatUI is usually a direct child of root or under main scene
		_chat_ui = root.find_child("ChatUI", true, false)
	return _chat_ui

func _send_to_chat(message: String) -> void:
	"""Send a message to the in-game ChatUI"""
	var chat = _get_chat_ui()
	if chat and chat.has_method("add_system_message"):
		chat.add_system_message(message)

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL METHODS
# ═══════════════════════════════════════════════════════════════════════════

func _log(level: LogLevel, message: String, category: String) -> void:
	"""Internal logging implementation"""
	# Check if this message should be logged
	var effective_level = category_levels.get(category, global_level)
	if level < effective_level:
		return

	# Get timestamp for this log entry
	var timestamp = Time.get_unix_time_from_system()

	# Build log line
	var parts: Array[String] = []

	# Timestamp
	if include_timestamps:
		var time = Time.get_time_dict_from_system()
		parts.append("[%02d:%02d:%02d]" % [time.hour, time.minute, time.second])

	# Level indicator
	var level_str = ""
	match level:
		LogLevel.DEBUG:
			level_str = "[DBG]"
		LogLevel.INFO:
			level_str = "[INF]"
		LogLevel.WARN:
			level_str = "[WRN]"
		LogLevel.ERROR:
			level_str = "[ERR]"
	parts.append(level_str)

	# Category with icon
	if include_category:
		var icon = CATEGORY_ICONS.get(category, CATEGORY_ICONS["default"])
		parts.append("%s %s:" % [icon, category])

	# Message
	parts.append(message)

	# Combine and output
	var log_line = " ".join(parts)

	# Print to console
	print(log_line)

	# Write to file if enabled
	if log_to_file and _log_file:
		# Check if we need to rotate (date change or size limit)
		_check_log_rotation()
		if _log_file:  # Recheck after rotation
			_log_file.store_line(log_line)
			_log_file.flush()  # Ensure immediate write for crash safety

	# Send to ChatUI in playtest mode (for specified categories)
	if playtest_mode and category in playtest_categories:
		var icon = CATEGORY_ICONS.get(category, "📋")
		var chat_msg = "%s %s" % [icon, message]
		_send_to_chat(chat_msg)

	# Emit signal for TelemetryManager to capture (for remote logging)
	log_written.emit(level, message, category, timestamp)
