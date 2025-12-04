extends Control
class_name VirtualJoystick
## Virtual Joystick for mobile touch input.
## Displays a visual joystick and reports input to MobileInput singleton.

# Visual components
@onready var base: TextureRect = $Base
@onready var stick: TextureRect = $Base/Stick

# Configuration
@export var joystick_radius: float = 80.0
@export var deadzone: float = 0.15
@export var dynamic_position: bool = true  # Joystick appears where you touch

# State
var _is_pressed: bool = false
var _touch_index: int = -1
var _center_position := Vector2.ZERO
var _current_output := Vector2.ZERO


func _ready() -> void:
	# Set up initial position
	_center_position = base.position + base.size / 2

	# Register with MobileInput
	if MobileInput:
		MobileInput.set_joystick_radius(joystick_radius)

	# Initially hidden if dynamic
	if dynamic_position:
		modulate.a = 0.3


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Check if touch is in our zone (left side of screen)
		var screen_size = get_viewport().get_visible_rect().size
		if event.position.x < screen_size.x * 0.4 and _touch_index == -1:
			_touch_index = event.index
			_is_pressed = true

			if dynamic_position:
				# Move joystick to touch position
				_center_position = event.position
				base.global_position = event.position - base.size / 2
				modulate.a = 0.8

			_update_stick_position(event.position)
	else:
		if event.index == _touch_index:
			_release()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _touch_index and _is_pressed:
		_update_stick_position(event.position)


func _update_stick_position(touch_pos: Vector2) -> void:
	var offset = touch_pos - _center_position
	var distance = offset.length()

	# Clamp to radius
	if distance > joystick_radius:
		offset = offset.normalized() * joystick_radius

	# Calculate normalized output
	_current_output = offset / joystick_radius

	# Apply deadzone
	if _current_output.length() < deadzone:
		_current_output = Vector2.ZERO

	# Update visual stick position
	if stick:
		stick.position = base.size / 2 + offset - stick.size / 2


func _release() -> void:
	_is_pressed = false
	_touch_index = -1
	_current_output = Vector2.ZERO

	# Reset stick to center
	if stick:
		stick.position = base.size / 2 - stick.size / 2

	if dynamic_position:
		modulate.a = 0.3


func get_output() -> Vector2:
	"""Get the current joystick output vector."""
	return _current_output


func is_pressed() -> bool:
	"""Check if the joystick is currently being pressed."""
	return _is_pressed
