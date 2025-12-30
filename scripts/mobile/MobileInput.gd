extends Node
## Mobile Input Manager
## Singleton that abstracts touch input for mobile platforms.
## Provides:
## - Left stick: Virtual joystick for movement
## - Right side: Touch-to-aim for attack direction and triggering

# Signals for components that need to react to touch events
signal aim_touch_started(world_position: Vector2)
signal aim_touch_ended()
signal aim_touch_moved(world_position: Vector2)
signal pinch_zoom(zoom_delta: float)
signal dash_pressed
signal interact_pressed
signal inventory_pressed
signal character_pressed

# Interact button state (for polling by interactables)
var _interact_just_pressed: bool = false

# Left stick (virtual joystick) state
var _left_stick_value := Vector2.ZERO
var _left_stick_touch_index: int = -1
var _left_stick_center := Vector2.ZERO
var _left_stick_radius: float = 80.0

# Right side (touch-to-aim) state
var _aim_touch_position := Vector2.INF  # World coordinates, INF = not touching
var _aim_touch_screen_position := Vector2.INF  # Screen coordinates
var _aim_touch_index: int = -1
var _aim_touch_active := false

# Pinch-to-zoom state
var _pinch_touch_1: int = -1
var _pinch_touch_2: int = -1
var _pinch_pos_1 := Vector2.ZERO
var _pinch_pos_2 := Vector2.ZERO
var _pinch_start_distance: float = 0.0
var _pinch_active := false
var _zoom_delta: float = 0.0  # Accumulated zoom delta this frame
var pinch_sensitivity: float = 0.005  # How fast pinch affects zoom

# Screen layout
var _screen_divider_ratio: float = 0.35  # Left 35% is joystick zone
var _joystick_zone_rect := Rect2()
var _aim_zone_rect := Rect2()

# Configuration
var joystick_deadzone: float = 0.15
var is_mobile: bool = false

# Reference to viewport for coordinate conversion
var _viewport: Viewport = null
var _canvas_transform := Transform2D.IDENTITY


func _ready() -> void:
	# Detect if running on mobile - only true mobile platforms, not touchscreen laptops
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	# NOTE: Removed auto-enable for touchscreen laptops - many gaming laptops have
	# touchscreens but players use mouse+keyboard. Mobile mode only on actual mobile devices.
	if is_mobile:
		print("[MobileInput] Mobile platform detected - enabling touch input")

	_viewport = get_viewport()
	_update_screen_zones()

	# Update zones when window resizes
	get_tree().root.size_changed.connect(_update_screen_zones)

	print("[MobileInput] Initialized - is_mobile: %s" % is_mobile)


func _update_screen_zones() -> void:
	"""Update touch zone boundaries based on current screen size."""
	var screen_size = get_viewport().get_visible_rect().size
	var divider_x = screen_size.x * _screen_divider_ratio

	# Left zone for joystick (bottom-left area)
	_joystick_zone_rect = Rect2(
		0,
		screen_size.y * 0.4,  # Bottom 60% of left side
		divider_x,
		screen_size.y * 0.6
	)

	# Right zone for aiming (entire right side)
	_aim_zone_rect = Rect2(
		divider_x,
		0,
		screen_size.x - divider_x,
		screen_size.y
	)

	# Default joystick center (can be overridden by VirtualJoystick component)
	_left_stick_center = Vector2(150, screen_size.y - 150)


func _process(_delta: float) -> void:
	# Reset one-shot input flags at end of frame (after physics checks)
	_interact_just_pressed = false


func _input(event: InputEvent) -> void:
	if not is_mobile and not OS.has_feature("editor"):
		return

	# Handle touch events
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var touch_pos = event.position

	if event.pressed:
		# Check for pinch gesture (second finger down while first is active)
		if _pinch_touch_1 == -1:
			_pinch_touch_1 = event.index
			_pinch_pos_1 = touch_pos
		elif _pinch_touch_2 == -1 and event.index != _pinch_touch_1:
			# Second finger - start pinch
			_pinch_touch_2 = event.index
			_pinch_pos_2 = touch_pos
			_pinch_start_distance = _pinch_pos_1.distance_to(_pinch_pos_2)
			_pinch_active = true
			# Cancel any single-finger actions when pinch starts
			_cancel_single_touch_actions()
			get_viewport().set_input_as_handled()
			return

		# Touch started - determine which zone (only if not pinching)
		if not _pinch_active:
			if _is_in_joystick_zone(touch_pos) and _left_stick_touch_index == -1:
				# Start joystick input
				_left_stick_touch_index = event.index
				_left_stick_center = touch_pos  # Dynamic center where finger lands
				_left_stick_value = Vector2.ZERO
				# Consume event so it doesn't hit UI underneath (e.g., chat)
				get_viewport().set_input_as_handled()

			elif _is_in_aim_zone(touch_pos) and _aim_touch_index == -1:
				# Start aim input
				_aim_touch_index = event.index
				_aim_touch_active = true
				_aim_touch_screen_position = touch_pos
				_aim_touch_position = _screen_to_world(touch_pos)
				aim_touch_started.emit(_aim_touch_position)
	else:
		# Touch ended
		# Check if pinch ended
		if event.index == _pinch_touch_1 or event.index == _pinch_touch_2:
			_end_pinch()

		if event.index == _left_stick_touch_index:
			_left_stick_touch_index = -1
			_left_stick_value = Vector2.ZERO
			get_viewport().set_input_as_handled()

		elif event.index == _aim_touch_index:
			_aim_touch_index = -1
			_aim_touch_active = false
			_aim_touch_screen_position = Vector2.INF
			_aim_touch_position = Vector2.INF
			aim_touch_ended.emit()


func _cancel_single_touch_actions() -> void:
	"""Cancel joystick and aim when pinch starts."""
	_left_stick_touch_index = -1
	_left_stick_value = Vector2.ZERO
	_aim_touch_index = -1
	_aim_touch_active = false
	_aim_touch_screen_position = Vector2.INF
	_aim_touch_position = Vector2.INF


func _end_pinch() -> void:
	"""End pinch gesture and reset state."""
	_pinch_touch_1 = -1
	_pinch_touch_2 = -1
	_pinch_active = false
	_pinch_start_distance = 0.0
	_zoom_delta = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	# Handle pinch zoom
	if _pinch_active:
		if event.index == _pinch_touch_1:
			_pinch_pos_1 = event.position
		elif event.index == _pinch_touch_2:
			_pinch_pos_2 = event.position

		# Calculate new distance and zoom delta
		var current_distance = _pinch_pos_1.distance_to(_pinch_pos_2)
		if _pinch_start_distance > 0:
			var distance_delta = current_distance - _pinch_start_distance
			_zoom_delta = distance_delta * pinch_sensitivity
			pinch_zoom.emit(_zoom_delta)
			# Update start distance for continuous zooming
			_pinch_start_distance = current_distance
		get_viewport().set_input_as_handled()
		return

	if event.index == _left_stick_touch_index:
		# Update joystick value
		var offset = event.position - _left_stick_center
		var distance = offset.length()

		if distance > _left_stick_radius:
			offset = offset.normalized() * _left_stick_radius

		_left_stick_value = offset / _left_stick_radius

		# Apply deadzone
		if _left_stick_value.length() < joystick_deadzone:
			_left_stick_value = Vector2.ZERO

		# Consume event so it doesn't hit UI underneath
		get_viewport().set_input_as_handled()

	elif event.index == _aim_touch_index:
		# Update aim position
		_aim_touch_screen_position = event.position
		_aim_touch_position = _screen_to_world(event.position)
		aim_touch_moved.emit(_aim_touch_position)


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	"""Convert screen coordinates to world coordinates."""
	if _viewport:
		_canvas_transform = _viewport.get_canvas_transform()
		return _canvas_transform.affine_inverse() * screen_pos
	return screen_pos


func _is_in_joystick_zone(pos: Vector2) -> bool:
	"""Check if position is in the joystick zone (left side, bottom half)."""
	return _joystick_zone_rect.has_point(pos)


func _is_in_aim_zone(pos: Vector2) -> bool:
	"""Check if position is in the aim zone (right side)."""
	return _aim_zone_rect.has_point(pos)


# ============================================
# PUBLIC API
# ============================================

func get_left_stick() -> Vector2:
	"""Get the current left stick value (movement input).
	Returns Vector2 with components in range [-1, 1]."""
	return _left_stick_value


func get_aim_touch_position() -> Vector2:
	"""Get the current aim touch position in world coordinates.
	Returns Vector2.INF if not touching."""
	return _aim_touch_position


func get_aim_touch_screen_position() -> Vector2:
	"""Get the current aim touch position in screen coordinates.
	Returns Vector2.INF if not touching."""
	return _aim_touch_screen_position


func is_aim_touch_active() -> bool:
	"""Check if the aim touch is currently active (finger down on right side)."""
	return _aim_touch_active


func is_in_aim_zone(screen_pos: Vector2) -> bool:
	"""Check if a screen position is in the aim zone. Useful for UI checks."""
	return _is_in_aim_zone(screen_pos)


func screen_to_world(screen_pos: Vector2) -> Vector2:
	"""Convert screen coordinates to world coordinates. Public wrapper."""
	return _screen_to_world(screen_pos)


func set_joystick_center(center: Vector2) -> void:
	"""Set the joystick center position (called by VirtualJoystick component)."""
	_left_stick_center = center


func set_joystick_radius(radius: float) -> void:
	"""Set the joystick radius (called by VirtualJoystick component)."""
	_left_stick_radius = radius


func is_mobile_platform() -> bool:
	"""Check if running on a mobile platform."""
	return is_mobile


func is_pinching() -> bool:
	"""Check if a pinch gesture is active."""
	return _pinch_active


func get_zoom_delta() -> float:
	"""Get the current zoom delta from pinch gesture.
	Positive = zoom in (fingers spreading), Negative = zoom out (fingers pinching)."""
	return _zoom_delta


func trigger_dash() -> void:
	"""Trigger a dash action (called by UI button)."""
	dash_pressed.emit()


func trigger_interact() -> void:
	"""Trigger an interact action (called by UI button)."""
	_interact_just_pressed = true
	interact_pressed.emit()


func is_interact_just_pressed() -> bool:
	"""Check if interact was just pressed this frame."""
	return _interact_just_pressed


func consume_interact() -> void:
	"""Consume the interact press so other interactables don't also trigger."""
	_interact_just_pressed = false


func trigger_inventory() -> void:
	"""Trigger inventory toggle (called by UI button)."""
	inventory_pressed.emit()


func trigger_character() -> void:
	"""Trigger character panel toggle (called by UI button)."""
	character_pressed.emit()


func enable_for_testing() -> void:
	"""Enable mobile input for testing in editor."""
	is_mobile = true
	print("[MobileInput] Enabled for testing")


func disable_for_testing() -> void:
	"""Disable mobile input testing mode."""
	is_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
	# Preserve touchscreen detection
	if not is_mobile and DisplayServer.is_touchscreen_available():
		is_mobile = true
	print("[MobileInput] Testing mode disabled, is_mobile: %s" % is_mobile)
