extends Node
class_name PerformanceManager

## Central Performance Manager
## Manages LOD (Level of Detail) for enemies, campfires, and effects based on camera distance
## Provides FPS monitoring and adaptive quality settings

# Performance thresholds
const TARGET_FPS: float = 60.0
const LOW_FPS_THRESHOLD: float = 30.0
const CRITICAL_FPS_THRESHOLD: float = 15.0

# LOD Distance Thresholds (from camera)
const LOD_DISTANCE_CLOSE: float = 500.0      # Full quality
const LOD_DISTANCE_MEDIUM: float = 1000.0    # Reduced quality
const LOD_DISTANCE_FAR: float = 1500.0       # Minimal/placeholder
const LOD_DISTANCE_CULL: float = 2000.0      # Completely disabled

# FPS tracking
var fps_history: Array[float] = []
var fps_history_size: int = 60  # Track last 60 frames (1 second at 60 FPS)
var average_fps: float = 60.0

# Performance settings
var adaptive_quality_enabled: bool = true
var show_performance_overlay: bool = false

# Singleton pattern
static var instance: PerformanceManager = null

func _ready() -> void:
	instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS  # Always run even when paused
	print("⚡ PerformanceManager initialized")

func _process(delta: float) -> void:
	# Track FPS
	var current_fps = Engine.get_frames_per_second()
	fps_history.append(current_fps)
	if fps_history.size() > fps_history_size:
		fps_history.pop_front()

	# Calculate average FPS
	if fps_history.size() > 0:
		var sum = 0.0
		for fps in fps_history:
			sum += fps
		average_fps = sum / fps_history.size()

func get_average_fps() -> float:
	return average_fps

func get_lod_level_for_distance(distance: float) -> LODLevel:
	"""Determine LOD level based on distance from camera"""
	if distance < LOD_DISTANCE_CLOSE:
		return LODLevel.FULL
	elif distance < LOD_DISTANCE_MEDIUM:
		return LODLevel.MEDIUM
	elif distance < LOD_DISTANCE_FAR:
		return LODLevel.LOW
	else:
		return LODLevel.CULLED

func is_low_performance() -> bool:
	"""Returns true if FPS is below target"""
	return average_fps < LOW_FPS_THRESHOLD

func is_critical_performance() -> bool:
	"""Returns true if FPS is critically low"""
	return average_fps < CRITICAL_FPS_THRESHOLD

enum LODLevel {
	FULL,      # Full quality - all features enabled
	MEDIUM,    # Reduced quality - some features disabled
	LOW,       # Low quality - minimal features
	CULLED     # Completely disabled - not visible
}

# Static helper for quick access
static func get_instance() -> PerformanceManager:
	return instance
