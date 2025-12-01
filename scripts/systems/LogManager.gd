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

# Log to file (useful for dedicated servers)
var log_to_file: bool = false
var log_file_path: String = "user://server.log"
var _log_file: FileAccess = null

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
	"default": "📋"
}

func _ready() -> void:
	# Auto-configure based on build type
	if OS.has_feature("dedicated_server") or _is_server_instance():
		# Server: verbose logging, log to file
		global_level = LogLevel.DEBUG
		log_to_file = true
		include_timestamps = true
	elif OS.is_debug_build():
		# Debug client: show info and above
		global_level = LogLevel.DEBUG
		log_to_file = false
	else:
		# Release client: only warnings and errors
		global_level = LogLevel.WARN
		log_to_file = false

	# Open log file if enabled
	if log_to_file:
		_open_log_file()

	info("LogManager initialized (level: %s, file: %s)" % [
		LogLevel.keys()[global_level],
		log_to_file
	], "default")

func _exit_tree() -> void:
	if _log_file:
		_log_file.close()

func _is_server_instance() -> bool:
	"""Check if this is running as a dedicated server"""
	# Check command line args for server flags
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--dedicated" or arg == "--headless":
			return true
	return false

func _open_log_file() -> void:
	"""Open log file for writing"""
	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if not _log_file:
		push_error("[LogManager] Failed to open log file: %s" % log_file_path)
		log_to_file = false

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
# INTERNAL METHODS
# ═══════════════════════════════════════════════════════════════════════════

func _log(level: LogLevel, message: String, category: String) -> void:
	"""Internal logging implementation"""
	# Check if this message should be logged
	var effective_level = category_levels.get(category, global_level)
	if level < effective_level:
		return

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
		_log_file.store_line(log_line)
		_log_file.flush()  # Ensure immediate write for crash safety
