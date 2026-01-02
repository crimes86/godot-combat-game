extends Node
# Server stub - no-op implementation for headless server builds

# Signal stubs for scripts that try to connect to them
signal tutorial_step_completed(step_name: String)
signal tutorial_completed

func is_tutorial_active() -> bool:
	return false

func on_skeleton_killed() -> void:
	pass

func start_tutorial(_player) -> void:
	pass

func skip_tutorial() -> void:
	pass
