extends Node
class_name PlayerAppearance

## Handles player visual appearance and animations
## Coordinates with LPC sprite system
## Separated from Player.gd for modularity

signal sprite_created()

enum Gender { MALE, FEMALE }

var player_body: CharacterBody2D
var current_gender: Gender = Gender.MALE
var player_sprite: AnimatedSprite2D

func _ready() -> void:
	player_body = get_parent() as CharacterBody2D
	if not player_body:
		push_error("PlayerAppearance must be a child of CharacterBody2D")

func set_gender(gender: Gender) -> void:
	"""Set character gender"""
	current_gender = gender

func get_gender() -> Gender:
	"""Get current gender"""
	return current_gender

func update_animation(velocity: Vector2, facing_direction: Vector2) -> void:
	"""Update LPC animation based on velocity and facing direction"""
	if not player_sprite:
		player_sprite = player_body.get_node_or_null("PlayerSprite") as AnimatedSprite2D
		if not player_sprite:
			return

	var velocity_dir: Vector2 = velocity if velocity.length() > 10 else facing_direction
	var direction_str: String = _get_direction_string(velocity_dir)

	# Determine animation based on movement
	var anim_name: String
	if velocity.length() > 10:
		anim_name = "walk_" + direction_str
	else:
		anim_name = "idle_" + direction_str

	# Play animation if it exists and isn't already playing
	if player_sprite.sprite_frames and player_sprite.sprite_frames.has_animation(anim_name):
		if player_sprite.animation != anim_name:
			player_sprite.play(anim_name)

func play_animation(anim_name: String) -> void:
	"""Play a specific animation by name"""
	if not player_sprite:
		player_sprite = player_body.get_node_or_null("PlayerSprite") as AnimatedSprite2D
		if not player_sprite:
			return

	if player_sprite.sprite_frames and player_sprite.sprite_frames.has_animation(anim_name):
		player_sprite.play(anim_name)

func stop_animation() -> void:
	"""Stop current animation"""
	if player_sprite:
		player_sprite.stop()

func get_sprite() -> AnimatedSprite2D:
	"""Get the player sprite node"""
	if not player_sprite:
		player_sprite = player_body.get_node_or_null("PlayerSprite") as AnimatedSprite2D
	return player_sprite

func set_sprite_modulate(color: Color) -> void:
	"""Set sprite color modulation"""
	if not player_sprite:
		player_sprite = player_body.get_node_or_null("PlayerSprite") as AnimatedSprite2D
	if player_sprite:
		player_sprite.modulate = color

func _get_direction_string(dir: Vector2) -> String:
	"""Convert direction vector to animation string"""
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"
