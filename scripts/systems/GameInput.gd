extends Node
## GameInput - Unified Input Abstraction
## Provides a single API for input regardless of platform (desktop or mobile).
## All platform-specific logic is handled internally.

signal attack_started(world_position: Vector2)
signal attack_ended()

# Cached state
var _is_mobile: bool = false
var _player: Node2D = null  # Reference to local player for position calculations


func _ready() -> void:
	_update_platform_state()


func _update_platform_state() -> void:
	"""Update cached platform state."""
	_is_mobile = MobileInput and MobileInput.is_mobile_platform()


func set_player(player: Node2D) -> void:
	"""Set the local player reference for aim calculations."""
	_player = player


func is_mobile() -> bool:
	"""Check if currently in mobile mode."""
	return _is_mobile


# ============================================
# MOVEMENT INPUT
# ============================================

func get_movement() -> Vector2:
	"""Get movement input as a normalized Vector2.
	Works on both desktop (WASD) and mobile (virtual joystick)."""
	if _is_mobile:
		return MobileInput.get_left_stick()
	else:
		return Input.get_vector("move_left", "move_right", "move_up", "move_down")


# ============================================
# AIM / ATTACK INPUT
# ============================================

func get_aim_position() -> Vector2:
	"""Get the current aim position in world coordinates.
	Desktop: mouse position. Mobile: touch position (or last known)."""
	if _is_mobile and MobileInput.is_aim_touch_active():
		return MobileInput.get_aim_touch_position()
	elif _player and is_instance_valid(_player):
		return _player.get_global_mouse_position()
	else:
		# Fallback - try to get from viewport
		var viewport = get_viewport()
		if viewport:
			var mouse_pos = viewport.get_mouse_position()
			var canvas_transform = viewport.get_canvas_transform()
			return canvas_transform.affine_inverse() * mouse_pos
		return Vector2.ZERO


func get_aim_direction() -> Vector2:
	"""Get the normalized direction from player to aim position."""
	if not _player or not is_instance_valid(_player):
		return Vector2.RIGHT  # Default direction

	var aim_pos = get_aim_position()
	return (_player.global_position.direction_to(aim_pos)).normalized()


func is_attack_held() -> bool:
	"""Check if attack input is being held.
	Desktop: left mouse button. Mobile: touch in aim zone."""
	if _is_mobile:
		return MobileInput.is_aim_touch_active()
	else:
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func is_aim_active() -> bool:
	"""Check if there's active aim input (for updating visualizers).
	On desktop this is always true (mouse always exists).
	On mobile, only true when touching aim zone."""
	if _is_mobile:
		return MobileInput.is_aim_touch_active()
	else:
		return true  # Mouse is always "active" on desktop


# ============================================
# ACTION INPUTS (Dash, Interact, etc.)
# ============================================

func is_dash_pressed() -> bool:
	"""Check if dash input was just pressed.
	Desktop: Space key. Mobile: TODO - dash button."""
	if _is_mobile:
		# TODO: Implement mobile dash button
		return false
	else:
		return Input.is_action_just_pressed("dash") if InputMap.has_action("dash") else Input.is_key_pressed(KEY_SPACE)


func is_interact_just_pressed() -> bool:
	"""Check if interact input was just pressed.
	Desktop: F key. Mobile: interact button."""
	if _is_mobile and MobileInput:
		return MobileInput.is_interact_just_pressed()
	else:
		return Input.is_physical_key_pressed(KEY_F)


# ============================================
# CAMERA / ZOOM
# ============================================

func is_pinching() -> bool:
	"""Check if a pinch gesture is active (mobile only)."""
	if _is_mobile and MobileInput:
		return MobileInput.is_pinching()
	return false


func get_pinch_zoom_delta() -> float:
	"""Get zoom delta from pinch gesture.
	Positive = zoom in (spread fingers), Negative = zoom out (pinch fingers)."""
	if _is_mobile and MobileInput:
		return MobileInput.get_zoom_delta()
	return 0.0


# ============================================
# PLATFORM TOGGLE (for testing)
# ============================================

func enable_mobile_mode() -> void:
	"""Enable mobile mode for testing."""
	if MobileInput:
		MobileInput.enable_for_testing()
	_update_platform_state()


func disable_mobile_mode() -> void:
	"""Disable mobile mode testing."""
	if MobileInput:
		MobileInput.disable_for_testing()
	_update_platform_state()


func toggle_mobile_mode() -> void:
	"""Toggle between mobile and desktop mode."""
	if _is_mobile:
		disable_mobile_mode()
	else:
		enable_mobile_mode()
