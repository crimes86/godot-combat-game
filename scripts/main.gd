# main.gd
extends Node2D

@onready var game_world = $GameWorld

func _ready():
	# Player spawning is now handled by game_world.gd multiplayer code
	pass

func _notification(what):
	# Handle window close request to prevent freeze
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("🚪 Game closing - cleaning up...")
		# Stop all tweens to prevent hang
		get_tree().call_group("tweens", "kill")
		# Force immediate quit without waiting for cleanup
		get_tree().quit()
