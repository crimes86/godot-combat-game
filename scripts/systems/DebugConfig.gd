extends Node

## Debug configuration autoload
## Centralizes debug flags and logging
## Add to project.godot autoloads as "DebugConfig"

## Signal emitted when F3 debug display is toggled
signal debug_display_toggled(visible: bool)

## Master debug flag - set to false for production
@export var ENABLE_DEBUG: bool = true

## F3 Debug display visibility
var debug_display_visible: bool = false

## Feature-specific debug flags
@export var DEBUG_COMBAT: bool = true
@export var DEBUG_MOVEMENT: bool = false
@export var DEBUG_AI: bool = false
@export var DEBUG_SPAWNING: bool = false
@export var DEBUG_VISUALS: bool = false

## Performance monitoring
@export var SHOW_FPS: bool = true
@export var LOG_FRAME_TIME: bool = false

## Debug visual settings
@export var SHOW_COLLISION_SHAPES: bool = false
@export var SHOW_ATTACK_CONES: bool = false
@export var SHOW_AI_PATHS: bool = false

func debug_log(message: String, category: String = "") -> void:
	# Centralized logging function
	if not ENABLE_DEBUG:
		return

	var prefix: String = "[DEBUG]"
	if category != "":
		prefix = "[%s]" % category.to_upper()

	print("%s %s" % [prefix, message])

func log_combat(message: String) -> void:
	# Log combat-related messages
	if ENABLE_DEBUG and DEBUG_COMBAT:
		debug_log(message, "COMBAT")

func log_movement(message: String) -> void:
	# Log movement-related messages
	if ENABLE_DEBUG and DEBUG_MOVEMENT:
		debug_log(message, "MOVEMENT")

func log_ai(message: String) -> void:
	# Log AI-related messages
	if ENABLE_DEBUG and DEBUG_AI:
		debug_log(message, "AI")

func log_spawning(message: String) -> void:
	# Log spawning-related messages
	if ENABLE_DEBUG and DEBUG_SPAWNING:
		debug_log(message, "SPAWN")

func log_error(message: String) -> void:
	# Log errors (always shown, even in production)
	push_error("[ERROR] %s" % message)

func log_warning(message: String) -> void:
	# Log warnings (always shown, even in production)
	push_warning("[WARNING] %s" % message)

func is_debug_enabled() -> bool:
	# Check if debug mode is enabled
	return ENABLE_DEBUG

func set_debug_mode(enabled: bool) -> void:
	# Toggle debug mode at runtime
	ENABLE_DEBUG = enabled
	debug_log("Debug mode %s" % ("ENABLED" if enabled else "DISABLED"))

func toggle_debug_display() -> void:
	"""Toggle F3 debug display visibility"""
	debug_display_visible = !debug_display_visible
	debug_display_toggled.emit(debug_display_visible)
	debug_log("Debug display %s" % ("SHOWN" if debug_display_visible else "HIDDEN"))

func _input(event: InputEvent) -> void:
	"""Listen for F3 key to toggle debug displays (debug builds only)"""
	# Only allow in editor or debug builds
	if not (OS.has_feature("editor") or OS.is_debug_build()):
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		toggle_debug_display()

func _ready() -> void:
	debug_log("DebugConfig initialized")
	if ENABLE_DEBUG:
		debug_log("🐛 Debug mode ENABLED")
	else:
		debug_log("🚀 Debug mode DISABLED (production)")
	debug_log("Press F3 to toggle debug displays")
