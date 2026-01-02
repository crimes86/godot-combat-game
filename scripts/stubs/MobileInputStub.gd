extends Node
# Server stub - no-op implementation for headless server builds

signal attack_pressed
signal interact_pressed

var is_mobile: bool = false
var movement_vector: Vector2 = Vector2.ZERO

func is_attack_held() -> bool:
	return false

func is_interact_pressed() -> bool:
	return false

func is_mobile_platform() -> bool:
	return false

func show_controls() -> void:
	pass

func hide_controls() -> void:
	pass
