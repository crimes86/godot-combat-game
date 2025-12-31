extends Node
# Server stub - no-op implementation for headless server builds

var visible: bool = false

func show_for_player(_player_name: String, _player_id: int, _position: Vector2) -> void:
	pass

func hide() -> void:
	pass
