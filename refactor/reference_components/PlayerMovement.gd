extends Node
class_name PlayerMovement

## Handles player movement, input, and facing direction
## Separated from Player.gd for modularity

signal direction_changed(new_direction: Vector2)

@export var speed: float = 200.0

var player_body: CharacterBody2D
var facing_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	player_body = get_parent() as CharacterBody2D
	if not player_body:
		push_error("PlayerMovement must be a child of CharacterBody2D")

func process_movement(delta: float) -> void:
	"""Main movement processing - call from Player's _physics_process"""
	var input_direction := get_input_direction()

	if input_direction != Vector2.ZERO:
		player_body.velocity = input_direction * speed
		last_move_direction = input_direction
		update_facing_direction(input_direction)
	else:
		player_body.velocity = player_body.velocity.move_toward(Vector2.ZERO, speed * delta * 10)

	player_body.move_and_slide()

func get_input_direction() -> Vector2:
	"""Get normalized movement input from WASD/arrow keys"""
	var direction := Vector2.ZERO
	direction.x = Input.get_axis("move_left", "move_right")
	direction.y = Input.get_axis("move_up", "move_down")
	return direction.normalized()

func update_facing_direction(move_dir: Vector2) -> void:
	"""Update facing direction based on movement"""
	if move_dir == Vector2.ZERO:
		return

	var old_direction := facing_direction

	# Prioritize cardinal directions over diagonals
	if abs(move_dir.x) > abs(move_dir.y):
		facing_direction = Vector2.RIGHT if move_dir.x > 0 else Vector2.LEFT
	else:
		facing_direction = Vector2.DOWN if move_dir.y > 0 else Vector2.UP

	if facing_direction != old_direction:
		direction_changed.emit(facing_direction)

func get_direction_string(dir: Vector2) -> String:
	"""Convert direction vector to animation string (up/down/left/right)"""
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"

func get_facing_direction() -> Vector2:
	"""Get current facing direction"""
	return facing_direction

func get_last_move_direction() -> Vector2:
	"""Get last non-zero movement direction"""
	return last_move_direction

func set_speed(new_speed: float) -> void:
	"""Update movement speed"""
	speed = new_speed
