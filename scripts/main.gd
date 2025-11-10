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
