class_name WildlifeAnimal
extends CharacterBody2D
## Base class for huntable wildlife (rabbits, foxes, deer, etc.)
## Simple AI: Roam around, flee from players, can be hunted for resources
##
## MULTIPLAYER: Server runs AI and syncs to clients via NetworkWildlifeManager
## Client copies have is_client_copy=true and skip AI processing

enum State {
	IDLE,
	ROAMING,
	ALERT,
	FLEEING,
	DEAD
}

# Animal configuration (override in subclasses)
@export var animal_type: String = "generic"
@export var max_health: float = 20.0
@export var roam_speed: float = 30.0
@export var flee_speed: float = 120.0
@export var detection_range: float = 300.0  # Distance to detect player
@export var flee_range: float = 500.0  # Distance before stopping flee
@export var roam_radius: float = 400.0  # How far from home to roam

# Loot configuration
@export var carcass_item_id: String = "rabbit_carcass"
@export var base_pelt_quality: float = 1.0  # Affected by how it was killed

# Sprite sheet textures (exported from scene)
@export var idle_texture: Texture2D
@export var walk_texture: Texture2D
@export var run_texture: Texture2D
@export var idle_frames: int = 8
@export var walk_frames: int = 8
@export var run_frames: int = 6

# State
var current_state: State = State.IDLE
var current_health: float = 20.0
var home_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var facing_right: bool = true
var hit_count: int = 0  # More hits = worse pelt quality

# Timers
var idle_timer: float = 0.0
var alert_timer: float = 0.0
const IDLE_TIME_MIN: float = 1.0
const IDLE_TIME_MAX: float = 4.0
const ALERT_TIME: float = 1.5

# Single sprite reference (we switch textures instead of multiple sprites)
var sprite: Sprite2D = null
var detection_area: Area2D = null

# Animation state
var current_anim: String = "idle"
var current_frames: int = 8
var frame_timer: float = 0.0
var animation_fps: float = 8.0

# Signals
signal animal_died(animal: WildlifeAnimal, killer: Node)
signal animal_fled(animal: WildlifeAnimal)


func _ready() -> void:
	add_to_group("wildlife")
	add_to_group("huntable")

	home_position = global_position
	current_health = max_health

	# Get node references explicitly in _ready to ensure they exist
	sprite = get_node_or_null("Sprite")
	detection_area = get_node_or_null("DetectionArea")

	# Set up detection area if it exists
	if detection_area:
		detection_area.body_entered.connect(_on_body_entered_detection)
		detection_area.body_exited.connect(_on_body_exited_detection)

	# Start with random idle time
	idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)

	# Initialize sprite - ensure hframes is set correctly for sprite sheet animation
	if sprite:
		print("[Wildlife] %s init - idle_frames=%d, walk_frames=%d, run_frames=%d" % [animal_type, idle_frames, walk_frames, run_frames])
		print("[Wildlife] %s textures - idle=%s, walk=%s, run=%s" % [animal_type, idle_texture, walk_texture, run_texture])

		# Explicitly disable region mode to ensure hframes works
		sprite.region_enabled = false

		if idle_texture:
			sprite.texture = idle_texture
			# Print texture size for debugging
			print("[Wildlife] %s texture size: %s" % [animal_type, idle_texture.get_size()])

		sprite.hframes = idle_frames
		sprite.vframes = 1
		sprite.frame = 0
		current_anim = ""  # Reset so _play_animation will run fully
		current_frames = idle_frames

		print("[Wildlife] %s sprite after init: hframes=%d, vframes=%d, frame=%d, region_enabled=%s" % [
			animal_type, sprite.hframes, sprite.vframes, sprite.frame, sprite.region_enabled])

		# Verify state after first frame with deferred call
		call_deferred("_verify_sprite_state")
	else:
		push_error("[Wildlife] %s - NO SPRITE FOUND!" % animal_type)

	# Initialize sprite with idle animation
	_play_animation("idle")


func _is_client_copy() -> bool:
	"""Check if this is a client-side copy (AI runs on server only)."""
	return has_meta("is_client_copy") and get_meta("is_client_copy") == true


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	# Client copies only update animations, server handles AI
	if _is_client_copy():
		_update_animation(delta)
		_update_facing()
		return

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.ROAMING:
			_process_roaming(delta)
		State.ALERT:
			_process_alert(delta)
		State.FLEEING:
			_process_fleeing(delta)

	# Advance animation frames
	_update_animation(delta)

	# Update sprite facing
	_update_facing()

	move_and_slide()


func _process_idle(delta: float) -> void:
	velocity = Vector2.ZERO

	idle_timer -= delta
	if idle_timer <= 0:
		# Decide to roam somewhere
		_pick_roam_target()
		current_state = State.ROAMING
		_play_animation("walk")


func _process_roaming(delta: float) -> void:
	var direction = (target_position - global_position).normalized()
	velocity = direction * roam_speed

	# Check if we've reached target
	if global_position.distance_to(target_position) < 20.0:
		current_state = State.IDLE
		idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		_play_animation("idle")
		velocity = Vector2.ZERO


func _process_alert(delta: float) -> void:
	velocity = Vector2.ZERO

	# Face the threat
	var player = _get_nearest_player()
	if player:
		facing_right = player.global_position.x > global_position.x

	alert_timer -= delta
	if alert_timer <= 0:
		# Check if player is still close
		if player and global_position.distance_to(player.global_position) < detection_range:
			# Start fleeing!
			current_state = State.FLEEING
			_play_animation("run")
			animal_fled.emit(self)
		else:
			# Threat gone, return to idle
			current_state = State.IDLE
			idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
			_play_animation("idle")


func _process_fleeing(delta: float) -> void:
	var player = _get_nearest_player()

	if player:
		# Flee directly away from player
		var flee_direction = (global_position - player.global_position).normalized()
		velocity = flee_direction * flee_speed

		# Check if we've fled far enough
		var distance = global_position.distance_to(player.global_position)
		if distance > flee_range:
			# Safe! Stop fleeing
			current_state = State.IDLE
			idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
			home_position = global_position  # New home
			_play_animation("idle")
			velocity = Vector2.ZERO
	else:
		# No player, stop fleeing
		current_state = State.IDLE
		idle_timer = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
		_play_animation("idle")
		velocity = Vector2.ZERO


func _pick_roam_target() -> void:
	# Pick a random point within roam radius of home
	var angle = randf() * TAU
	var distance = randf_range(roam_radius * 0.3, roam_radius)
	target_position = home_position + Vector2(cos(angle), sin(angle)) * distance


func _update_animation(delta: float) -> void:
	if not sprite:
		return

	frame_timer += delta
	var frame_duration = 1.0 / animation_fps

	if frame_timer >= frame_duration:
		frame_timer -= frame_duration
		# Advance to next frame, loop if needed
		var next_frame = sprite.frame + 1
		if next_frame >= current_frames:
			next_frame = 0
		sprite.frame = next_frame


func _update_facing() -> void:
	if velocity.length_squared() > 1.0:
		facing_right = velocity.x > 0

	# Update sprite flip_h (sprites face right by default)
	if sprite:
		sprite.flip_h = not facing_right


func _play_animation(anim_name: String) -> void:
	if not sprite:
		push_warning("[Wildlife] _play_animation called but sprite is null!")
		return

	# Don't restart if same animation (but still ensure hframes is correct)
	var same_anim = (anim_name == current_anim and sprite.texture != null)

	current_anim = anim_name

	# Switch texture and frame count based on animation
	match anim_name:
		"idle":
			sprite.texture = idle_texture
			current_frames = idle_frames
			animation_fps = 8.0
		"walk":
			sprite.texture = walk_texture
			current_frames = walk_frames
			animation_fps = 10.0
		"run":
			sprite.texture = run_texture
			current_frames = run_frames
			animation_fps = 12.0
		_:
			sprite.texture = idle_texture
			current_frames = idle_frames
			animation_fps = 8.0

	# ALWAYS configure sprite for horizontal sprite sheet (even if same animation)
	# This fixes issues where hframes might have been reset
	sprite.region_enabled = false
	sprite.hframes = current_frames
	sprite.vframes = 1

	# Only reset frame if animation changed
	if not same_anim:
		sprite.frame = 0
		frame_timer = 0.0


func _get_nearest_player() -> Node2D:
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	var nearest: Node2D = null
	var nearest_dist: float = INF

	for player in players:
		var dist = global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest


func _on_body_entered_detection(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		# Player detected! Go to alert state
		if current_state in [State.IDLE, State.ROAMING]:
			current_state = State.ALERT
			alert_timer = ALERT_TIME
			_play_animation("idle")  # Stand still, look alert


func _on_body_exited_detection(body: Node2D) -> void:
	# Player left detection area - handled in _process_alert
	pass


# === DAMAGE / HUNTING ===

func request_damage(amount: float, attacker: Node = null) -> void:
	"""Public API for dealing damage - routes through network in multiplayer."""
	var network_manager = get_node_or_null("/root/NetworkWildlifeManager")

	if network_manager and has_meta("network_id"):
		# Multiplayer: request damage through server
		var network_id = get_meta("network_id")
		network_manager.request_damage_wildlife(network_id, amount, 0)
	else:
		# Single player: apply directly
		take_damage(amount, attacker)


func take_damage(amount: float, attacker: Node = null) -> void:
	"""Apply damage directly (called by server or single-player)."""
	if current_state == State.DEAD:
		return

	current_health -= amount
	hit_count += 1

	# Flash red on all sprites
	_set_all_sprites_modulate(Color.RED)
	get_tree().create_timer(0.1).timeout.connect(_reset_sprite_modulate)

	# Immediately flee if hit (server-side only, clients get state via sync)
	if not _is_client_copy():
		if current_state != State.FLEEING:
			current_state = State.FLEEING
			_play_animation("run")

	if current_health <= 0:
		_die(attacker)


func _set_all_sprites_modulate(color: Color) -> void:
	if sprite:
		sprite.modulate = color


func _reset_sprite_modulate() -> void:
	if sprite:
		sprite.modulate = Color.WHITE


func _die(killer: Node = null) -> void:
	current_state = State.DEAD
	velocity = Vector2.ZERO

	animal_died.emit(self, killer)

	# Calculate pelt quality based on hits
	var quality = _calculate_pelt_quality()

	# Spawn carcass loot or add to player inventory
	_drop_carcass(killer, quality)

	# Death animation - fade out sprite
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	else:
		queue_free()


func _calculate_pelt_quality() -> float:
	# More hits = worse quality
	# 1 hit = pristine (1.0), 2 hits = good (0.8), 3+ hits = poor (0.5)
	match hit_count:
		1: return 1.0
		2: return 0.8
		_: return 0.5


func _drop_carcass(killer: Node, quality: float) -> void:
	# For now, just print - will integrate with inventory later
	print("[Wildlife] %s died. Carcass: %s, Quality: %.0f%%" % [animal_type, carcass_item_id, quality * 100])

	# TODO: Add carcass to killer's inventory or spawn as loot
	# var carcass_data = {
	#     "item_id": carcass_item_id,
	#     "quality": quality,
	#     "animal_type": animal_type
	# }


# === UTILITY ===

func get_animal_info() -> Dictionary:
	return {
		"type": animal_type,
		"state": State.keys()[current_state],
		"health": current_health,
		"max_health": max_health,
		"position": global_position
	}


func _verify_sprite_state() -> void:
	"""Deferred check to verify sprite state after first frame."""
	if not sprite:
		return

	print("[Wildlife] %s VERIFY (deferred): hframes=%d, vframes=%d, frame=%d, region=%s, tex=%s" % [
		animal_type,
		sprite.hframes,
		sprite.vframes,
		sprite.frame,
		sprite.region_enabled,
		sprite.texture.resource_path if sprite.texture else "null"
	])

	# Force hframes again in case something reset it
	if sprite.hframes != current_frames:
		push_warning("[Wildlife] %s hframes was changed! Resetting from %d to %d" % [
			animal_type, sprite.hframes, current_frames])
		sprite.hframes = current_frames
		sprite.vframes = 1
