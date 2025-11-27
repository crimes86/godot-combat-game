extends Node2D
# NetworkPlayer.gd - Wrapper for multiplayer players

class_name NetworkPlayer

@export var player_id: int = 1
@export var player_name: String = "Player"
@export var is_local: bool = false

# Reference to the actual Player scene
var player_instance = null
var player_scene = preload("res://scenes/player/player.tscn")

# Sync variables
var sync_position: Vector2 = Vector2.ZERO
var sync_animation: String = "idle_down"
var sync_health: int = 100
var sync_max_health: int = 100
var sync_level: int = 1
var sync_is_dashing: bool = false  # Track dash state for i-frame validation

# Network interpolation
var last_sync_time: float = 0.0
var interpolation_speed: float = 10.0

func _ready():
	name = "Player_" + str(player_id)
	set_multiplayer_authority(player_id)

	# Spawn the actual player
	player_instance = player_scene.instantiate()
	add_child(player_instance)

	# IMPORTANT: Set multiplayer authority on the player instance too
	# so that is_multiplayer_authority() works correctly inside Player.gd
	player_instance.set_multiplayer_authority(player_id)

	# Setup based on ownership
	if is_multiplayer_authority():
		# This is our player
		is_local = true
		player_instance.set_process(true)
		player_instance.set_physics_process(true)

		# Ensure camera follows this player
		if player_instance.has_node("Camera2D"):
			player_instance.get_node("Camera2D").enabled = true

		print("Spawned local player: %s (ID: %d)" % [player_name, player_id])
	else:
		# Remote player
		is_local = false
		player_instance.set_process(false)
		player_instance.set_physics_process(false)

		# Disable camera for remote players
		if player_instance.has_node("Camera2D"):
			player_instance.get_node("Camera2D").enabled = false

		# Disable AI/input for remote players
		if player_instance.has_method("disable_input"):
			player_instance.disable_input()

		print("Spawned remote player: %s (ID: %d)" % [player_name, player_id])

	# Set player name label if it exists
	if player_instance.has_node("NameLabel"):
		player_instance.get_node("NameLabel").text = player_name

func _physics_process(delta):
	if not player_instance:
		return

	if is_local:
		# Send our position to others
		if Time.get_ticks_msec() - last_sync_time > 50:  # 20Hz update rate
			_send_position_update()
			last_sync_time = Time.get_ticks_msec()
	else:
		# Interpolate to received position
		player_instance.global_position = player_instance.global_position.lerp(
			sync_position,
			interpolation_speed * delta
		)

		# Update animation if changed
		if player_instance.has_method("play_animation"):
			player_instance.play_animation(sync_animation)
		else:
			# Debug: This shouldn't happen anymore
			if randf() < 0.01:
				print("⚠️ [%s] player_instance missing play_animation method!" % name)

func _send_position_update():
	if not player_instance:
		return

	var pos = player_instance.global_position
	var anim = _get_current_animation()
	var health = _get_player_health()
	var max_hp = _get_player_max_health()
	var dashing = _is_player_dashing()

	rpc("receive_position_update", pos, anim, health, max_hp, dashing)

@rpc("any_peer", "call_local", "unreliable_ordered")
func receive_position_update(pos: Vector2, anim: String, health: int, max_hp: int = 100, dashing: bool = false):
	if is_local:
		return  # Ignore our own updates

	# Debug: Log what we're receiving
	if randf() < 0.02:  # Only log occasionally to avoid spam
		print("🌐 [%s] Received anim: %s from peer" % [name, anim])

	sync_position = pos
	sync_animation = anim
	sync_health = health
	sync_max_health = max_hp
	sync_is_dashing = dashing

	# Update remote player's healthbar with synced values
	if player_instance:
		# Update the player instance's health values for display
		if player_instance.get("current_health") != null:
			player_instance.current_health = health
		if player_instance.get("max_health") != null:
			player_instance.max_health = max_hp
		# Update the healthbar visual
		if player_instance.has_node("HealthBar"):
			var hb = player_instance.get_node("HealthBar")
			if hb.has_method("update_health"):
				hb.update_health(health, max_hp)

	# Trigger dash visuals on remote player if they're dashing
	if dashing and player_instance:
		_show_remote_dash_effects()

# Combat synchronization
func take_damage(amount: int, attacker_id: int):
	if not is_local:
		return  # Only process damage locally

	rpc_id(1, "request_damage", player_id, amount, attacker_id)

@rpc("any_peer", "call_local", "reliable")
func request_damage(target_id: int, amount: int, attacker_id: int):
	# Only server processes damage
	if not multiplayer.is_server():
		return

	# Server-side i-frame validation: check if target is dashing
	if sync_is_dashing and target_id == player_id:
		print("Server: Damage blocked - player %d is dashing (i-frames)" % target_id)
		return

	# Validate and apply damage
	rpc("apply_damage", target_id, amount, attacker_id)

@rpc("authority", "call_local", "reliable")
func apply_damage(target_id: int, amount: int, attacker_id: int):
	if target_id != player_id:
		return

	if player_instance and player_instance.has_method("take_damage"):
		player_instance.take_damage(amount)

		# Check for death
		if _get_player_health() <= 0:
			rpc("handle_death", player_id, attacker_id)

@rpc("authority", "call_local", "reliable")
func handle_death(dead_player_id: int, killer_id: int):
	if dead_player_id != player_id:
		return

	print("%s was killed by Player %d" % [player_name, killer_id])

	# Handle death animation
	if player_instance and player_instance.has_method("die"):
		player_instance.die()

	# Respawn after delay
	if is_local:
		await get_tree().create_timer(5.0).timeout
		request_respawn()

func request_respawn():
	if not is_local:
		return

	rpc_id(1, "server_respawn_player", player_id)

@rpc("any_peer", "call_local", "reliable")
func server_respawn_player(respawn_player_id: int):
	if not multiplayer.is_server():
		return

	# Find a spawn point
	var spawn_point = _get_random_spawn_point()
	rpc("execute_respawn", respawn_player_id, spawn_point)

@rpc("authority", "call_local", "reliable")
func execute_respawn(respawn_player_id: int, spawn_pos: Vector2):
	if respawn_player_id != player_id:
		return

	if player_instance:
		player_instance.global_position = spawn_pos
		if player_instance.has_method("revive"):
			player_instance.revive()
		if player_instance.has_method("restore_health"):
			player_instance.restore_health()

	print("%s respawned at %s" % [player_name, spawn_pos])

# Utility functions
func _get_current_animation() -> String:
	if player_instance and player_instance.has_method("get_current_animation"):
		return player_instance.get_current_animation()
	return "idle_down"

func _get_player_health() -> int:
	if player_instance:
		if player_instance.has_method("get_health"):
			return player_instance.get_health()
		elif player_instance.get("health") != null:
			return player_instance.health
	return sync_health

func _get_player_max_health() -> int:
	if player_instance:
		if player_instance.get("max_health") != null:
			return player_instance.max_health
	return sync_max_health

func _get_random_spawn_point() -> Vector2:
	# Get spawn points from game world
	var game_world = get_node("/root/GameWorld")
	if game_world and game_world.has_method("get_spawn_points"):
		var points = game_world.get_spawn_points()
		if points.size() > 0:
			return points[randi() % points.size()]

	# Default spawn area around campfire
	var angle = randf() * TAU
	var distance = 200 + randf() * 100
	return Vector2(cos(angle) * distance, sin(angle) * distance)

func set_player_name_display(name: String):
	player_name = name
	if player_instance and player_instance.has_node("NameLabel"):
		player_instance.get_node("NameLabel").text = name

func get_player_position() -> Vector2:
	if player_instance:
		return player_instance.global_position
	return Vector2.ZERO

func _is_player_dashing() -> bool:
	"""Check if local player is currently dashing"""
	if player_instance:
		if player_instance.has_method("is_invincible"):
			return player_instance.is_invincible()
		elif player_instance.get("is_dashing") != null:
			return player_instance.is_dashing
	return false

func _show_remote_dash_effects():
	"""Show dash visual effects for remote players"""
	if not player_instance:
		return

	# Use the player's spawn_dash_afterimage if available
	if player_instance.has_method("spawn_dash_afterimage"):
		player_instance.spawn_dash_afterimage()
		return

	# Fallback: spawn basic afterimage
	var character_sprite = player_instance.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.sprite_frames:
		var afterimage = Sprite2D.new()
		afterimage.texture = character_sprite.sprite_frames.get_frame_texture(character_sprite.animation, character_sprite.frame)
		afterimage.global_position = player_instance.global_position + character_sprite.position
		afterimage.modulate = Color(0.5, 0.7, 1.0, 0.5)  # Blue-tinted
		afterimage.z_index = -1

		get_tree().root.add_child(afterimage)

		# Fade out
		var tween = afterimage.create_tween()
		tween.tween_property(afterimage, "modulate:a", 0.0, 0.15)
		tween.tween_callback(afterimage.queue_free)
