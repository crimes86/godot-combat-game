extends Node
# Server stub - no-op implementation for headless server builds

func add_effect(_effect: Node) -> void:
	pass

func spawn_effect(_effect_name: String, _position: Vector2) -> Node:
	return null

func clear_effects() -> void:
	pass
