# main.gd
extends Node2D

@onready var player = $Player
@onready var game_world = $GameWorld

func _ready():
	# Position player at the spawn point in game world
	if player and game_world:
		var spawn_point = game_world.get_node_or_null("PlayerSpawnPoint")
		if spawn_point:
			player.global_position = spawn_point.global_position
			print("🎮 Player spawned at: ", spawn_point.global_position)

func _notification(what):
	# Handle window close request to prevent freeze
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("🚪 Game closing - cleaning up...")
		# Stop all tweens to prevent hang
		get_tree().call_group("tweens", "kill")
		# Force immediate quit without waiting for cleanup
		get_tree().quit()
