extends Node2D
# NetworkPlayer.gd - Wrapper for multiplayer players

class_name NetworkPlayer

@export var player_id: int = 1
@export var player_name: String = "Player"
@export var is_local: bool = false

# Reference to the actual Player scene
var player_instance: Node = null
var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

# Sync variables
var sync_position: Vector2 = Vector2.ZERO
var sync_animation: String = "idle_down"
var sync_health: int = 100
var sync_max_health: int = 100
var sync_level: int = 1
var sync_is_dashing: bool = false  # Track dash state for i-frame validation

# Network interpolation
var last_sync_time: float = 0.0
var interpolation_speed: float = 15.0  # Increased for smoother movement
var target_position: Vector2 = Vector2.ZERO  # Target position to interpolate toward
var calculated_move_speed: float = 200.0  # Calculated speed based on distance/time

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

		# Initialize target position to current position (avoid interpolating from origin)
		target_position = player_instance.global_position

		# Disable camera for remote players
		if player_instance.has_node("Camera2D"):
			player_instance.get_node("Camera2D").enabled = false

		# Disable AI/input for remote players
		if player_instance.has_method("disable_input"):
			player_instance.disable_input()

		print("Spawned remote player: %s (ID: %d)" % [player_name, player_id])

	# Set player name on health bar
	if player_instance.has_node("HealthBar"):
		var hb = player_instance.get_node("HealthBar")
		if hb.has_method("set_player_name"):
			hb.set_player_name(player_name)
		# Set name color based on guest status
		if hb.has_method("set_name_color"):
			var is_player_guest = NetworkManager.is_player_guest(player_id) if multiplayer.is_server() else false
			if is_player_guest:
				hb.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
			else:
				hb.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated

func _physics_process(delta):
	if not player_instance:
		return

	if is_local:
		# Send our position to others at 30Hz for smoother remote player movement
		if Time.get_ticks_msec() - last_sync_time > 33:  # 30Hz update rate (was 20Hz)
			_send_position_update()
			last_sync_time = Time.get_ticks_msec()
	else:
		# Smooth interpolation toward target position
		var current_pos = player_instance.global_position
		var distance = current_pos.distance_to(target_position)

		if distance < 1.0:
			# Close enough, snap to target
			player_instance.global_position = target_position
		elif distance > 500.0:
			# Too far (likely teleport/respawn), snap immediately
			player_instance.global_position = target_position
		else:
			# Smooth movement at calculated speed
			var speed = clampf(calculated_move_speed, 100.0, 600.0)
			var move_distance = speed * delta

			if move_distance >= distance:
				player_instance.global_position = target_position
			else:
				var direction = (target_position - current_pos).normalized()
				player_instance.global_position = current_pos + direction * move_distance

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

	# Calculate interpolation speed based on distance between updates
	# This ensures smooth movement that reaches target before next update
	if player_instance:
		var old_target = target_position if target_position != Vector2.ZERO else player_instance.global_position
		var distance = old_target.distance_to(pos)
		# At 30Hz, updates arrive every ~33ms. Move at speed to cover distance in ~25ms (75% of interval)
		var target_time = 0.025
		calculated_move_speed = distance / target_time if target_time > 0 else 200.0

	# Set target position for interpolation
	target_position = pos
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

	# SECURITY: Validate attacker_id matches actual sender (prevent spoofing)
	var actual_sender = multiplayer.get_remote_sender_id()
	if actual_sender == 0:
		actual_sender = 1  # Server's peer ID
	if attacker_id != actual_sender:
		push_warning("Anti-cheat: Player %d tried to spoof damage as player %d" % [actual_sender, attacker_id])
		attacker_id = actual_sender  # Use real sender ID

	# SECURITY: Validate sender is authenticated
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and not network_manager.is_player_authenticated(actual_sender):
		push_warning("Anti-cheat: Unauthenticated peer %d tried to deal damage" % actual_sender)
		return

	# SECURITY: Validate damage amount against player's actual stats
	var max_damage = _get_max_pvp_damage(attacker_id)
	if amount <= 0 or amount > max_damage:
		push_warning("Anti-cheat: Invalid PvP damage amount %d from player %d (max expected: %d)" % [amount, attacker_id, max_damage])
		amount = clampi(amount, 1, max_damage)

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
		# Pass source info for duel system - PvP damage from another player
		player_instance.take_damage(amount, "player", attacker_id)

		# Check for death (only if not in duel - duel uses 1 HP threshold)
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

	# SECURITY: Validate sender is requesting their own respawn
	var actual_sender = multiplayer.get_remote_sender_id()
	if actual_sender == 0:
		actual_sender = 1  # Server's peer ID
	if respawn_player_id != actual_sender:
		push_warning("Anti-cheat: Player %d tried to respawn player %d" % [actual_sender, respawn_player_id])
		return

	# SECURITY: Validate sender is authenticated
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and not network_manager.is_player_authenticated(actual_sender):
		push_warning("Anti-cheat: Unauthenticated peer %d tried to respawn" % actual_sender)
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
	var game_world = get_node_or_null("/root/GameWorld")
	if game_world and game_world.has_method("get_spawn_points"):
		var points = game_world.get_spawn_points()
		if points.size() > 0:
			return points[randi() % points.size()]

	# Default spawn area around campfire
	var angle = randf() * TAU
	var distance = 200 + randf() * 100
	return Vector2(cos(angle) * distance, sin(angle) * distance)

func set_player_name_display(new_name: String, is_guest_player: bool = false):
	player_name = new_name
	# Update health bar name label
	if player_instance and player_instance.has_node("HealthBar"):
		var hb = player_instance.get_node("HealthBar")
		if hb.has_method("set_player_name"):
			hb.set_player_name(new_name)
		# Set name color based on guest status
		if hb.has_method("set_name_color"):
			if is_guest_player:
				hb.set_name_color(Color(0.7, 0.75, 0.7, 1.0))  # Greenish-gray for guests
			else:
				hb.set_name_color(Color(0.4, 0.8, 1.0, 1.0))  # Cyan for authenticated

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

func _get_max_pvp_damage(attacker_peer_id: int) -> int:
	"""Get maximum expected PvP damage for a player based on their actual stats."""
	var base_damage: float = 15.0  # Default base damage

	# Try to find the attacking player's actual damage stat
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()

		if player_peer_id == attacker_peer_id:
			if player.get("attack_damage") != null:
				base_damage = player.attack_damage
			break

	# Add buffer for weapon variance, combo multipliers, etc.
	# Max realistic damage with best gear and max combo is ~150-200 base * 2x combo = 400
	return int(maxf(base_damage * 3.0, 200.0))  # 3x multiplier minimum 200
