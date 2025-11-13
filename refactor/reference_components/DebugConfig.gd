extends Node

## Debug configuration autoload
## Centralizes debug flags and logging
## Add to project.godot autoloads as "DebugConfig"

## Master debug flag - set to false for production
@export var ENABLE_DEBUG: bool = true

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

func log(message: String, category: String = "") -> void:
	"""Centralized logging function"""
	if not ENABLE_DEBUG:
		return

	var prefix: String = "[DEBUG]"
	if category != "":
		prefix = "[%s]" % category.to_upper()

	print("%s %s" % [prefix, message])

func log_combat(message: String) -> void:
	"""Log combat-related messages"""
	if ENABLE_DEBUG and DEBUG_COMBAT:
		log(message, "COMBAT")

func log_movement(message: String) -> void:
	"""Log movement-related messages"""
	if ENABLE_DEBUG and DEBUG_MOVEMENT:
		log(message, "MOVEMENT")

func log_ai(message: String) -> void:
	"""Log AI-related messages"""
	if ENABLE_DEBUG and DEBUG_AI:
		log(message, "AI")

func log_spawning(message: String) -> void:
	"""Log spawning-related messages"""
	if ENABLE_DEBUG and DEBUG_SPAWNING:
		log(message, "SPAWN")

func log_error(message: String) -> void:
	"""Log errors (always shown, even in production)"""
	push_error("[ERROR] %s" % message)

func log_warning(message: String) -> void:
	"""Log warnings (always shown, even in production)"""
	push_warning("[WARNING] %s" % message)

func is_debug_enabled() -> bool:
	"""Check if debug mode is enabled"""
	return ENABLE_DEBUG

func set_debug_mode(enabled: bool) -> void:
	"""Toggle debug mode at runtime"""
	ENABLE_DEBUG = enabled
	log("Debug mode %s" % ("ENABLED" if enabled else "DISABLED"))

func _ready() -> void:
	log("DebugConfig initialized")
	if ENABLE_DEBUG:
		log("🐛 Debug mode ENABLED")
	else:
		log("🚀 Debug mode DISABLED (production)")
