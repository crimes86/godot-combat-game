extends Node
class_name ScreenShake

## Screen Shake System
## Provides camera shake for impactful feedback
## Uses real time so shake works during hitstop (time_scale = 0)

var camera: Camera2D
var shake_amount: float = 0.0
var shake_decay: float = 5.0  # How fast shake fades
var trauma: float = 0.0  # 0-1, how much shake is happening
var _last_time: float = 0.0  # For real-time delta calculation

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when time_scale is 0
	_last_time = Time.get_ticks_msec() / 1000.0

	# Find the camera in the scene
	await get_tree().process_frame
	camera = get_viewport().get_camera_2d()

	if not camera:
		push_error("ScreenShake: No Camera2D found in scene!")

func _process(_delta: float) -> void:
	# Use REAL time delta (not affected by Engine.time_scale)
	var current_time = Time.get_ticks_msec() / 1000.0
	var real_delta = current_time - _last_time
	_last_time = current_time

	# Clamp real_delta to avoid huge jumps
	real_delta = min(real_delta, 0.1)

	if trauma > 0 and camera:
		# Decay trauma over real time
		trauma = max(trauma - shake_decay * real_delta, 0.0)

		# Calculate shake amount (squared for smoother feel)
		shake_amount = trauma * trauma

		# Apply random offset to camera
		var offset_x = randf_range(-shake_amount, shake_amount) * 10
		var offset_y = randf_range(-shake_amount, shake_amount) * 10
		camera.offset = Vector2(offset_x, offset_y)
	elif camera:
		# Reset camera when no shake
		camera.offset = Vector2.ZERO

## Add trauma to trigger shake
## amount: 0.0-1.0, intensity of shake
func add_trauma(amount: float) -> void:
	trauma = min(trauma + amount, 1.0)

## Convenience functions for different shake intensities
func shake_light() -> void:
	add_trauma(0.2)

func shake_medium() -> void:
	add_trauma(0.4)

func shake_heavy() -> void:
	add_trauma(0.6)

func shake_critical() -> void:
	add_trauma(0.8)

func shake_for_damage(damage: float, is_critical: bool = false) -> void:
	# Scale shake based on damage amount
	var base_trauma = clamp(damage / 50.0, 0.1, 0.5)
	if is_critical:
		base_trauma *= 1.5
	add_trauma(base_trauma)
