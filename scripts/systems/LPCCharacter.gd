extends AnimatedSprite2D
class_name LPCCharacter

## Handles LPC (Liberated Pixel Cup) character spritesheets
## Supports 8-directional movement and animation

# LPC spritesheet layout (each row is 64px tall, each frame is 64px wide)
# Row 0: Spellcast UP
# Row 1: Spellcast LEFT  
# Row 2: Spellcast DOWN
# Row 3: Spellcast RIGHT
# Row 4: Thrust UP
# Row 5: Thrust LEFT
# Row 6: Thrust DOWN
# Row 7: Thrust RIGHT
# Row 8: Walk UP
# Row 9: Walk LEFT
# Row 10: Walk DOWN
# Row 11: Walk RIGHT
# Row 12: Slash UP
# Row 13: Slash LEFT
# Row 14: Slash DOWN
# Row 15: Slash RIGHT
# Row 16: Shoot UP
# Row 17: Shoot LEFT
# Row 18: Shoot DOWN
# Row 19: Shoot RIGHT
# Row 20: Hurt (single frame in various directions)

const FRAME_SIZE = 64
const WALK_UP_ROW = 8
const WALK_LEFT_ROW = 9
const WALK_DOWN_ROW = 10
const WALK_RIGHT_ROW = 11
const SLASH_UP_ROW = 12
const SLASH_LEFT_ROW = 13
const SLASH_DOWN_ROW = 14
const SLASH_RIGHT_ROW = 15

enum Direction {
	DOWN,
	DOWN_RIGHT,
	RIGHT,
	UP_RIGHT,
	UP,
	UP_LEFT,
	LEFT,
	DOWN_LEFT
}

var current_direction: Direction = Direction.DOWN
var is_walking: bool = false
var is_attacking: bool = false

# Layer textures
var body_texture: Texture2D = null
var clothing_textures: Array[Texture2D] = []
var weapon_texture: Texture2D = null

func _ready() -> void:
	# Animation will be set up by parent
	pass

func load_character(body_path: String, clothing_paths: Array = [], weapon_path: String = "") -> void:
	"""Load character from LPC spritesheet layers"""
	body_texture = load(body_path) if body_path != "" else null
	
	clothing_textures.clear()
	for clothing_path in clothing_paths:
		if clothing_path != "":
			clothing_textures.append(load(clothing_path))
	
	weapon_texture = load(weapon_path) if weapon_path != "" else null
	
	# Create combined sprite frames
	setup_animations()

func setup_animations() -> void:
	"""Create animation frames by compositing layers"""
	if not body_texture:
		return
	
	sprite_frames = SpriteFrames.new()
	
	# Create animations for each direction
	create_walk_animations()
	create_idle_animations()
	create_attack_animations()
	
	# Start with idle down
	play("idle_down")

func create_walk_animations() -> void:
	"""Create walking animations for all 8 directions"""
	# Down
	sprite_frames.add_animation("walk_down")
	sprite_frames.set_animation_loop("walk_down", true)
	sprite_frames.set_animation_speed("walk_down", 8.0)
	add_frames_from_row("walk_down", WALK_DOWN_ROW, 9)
	
	# Down-Right (mirror down-left)
	sprite_frames.add_animation("walk_down_right")
	sprite_frames.set_animation_loop("walk_down_right", true)
	sprite_frames.set_animation_speed("walk_down_right", 8.0)
	add_frames_from_row("walk_down_right", WALK_DOWN_ROW, 9)  # We'll flip these
	
	# Right
	sprite_frames.add_animation("walk_right")
	sprite_frames.set_animation_loop("walk_right", true)
	sprite_frames.set_animation_speed("walk_right", 8.0)
	add_frames_from_row("walk_right", WALK_RIGHT_ROW, 9)
	
	# Up-Right (mirror up-left)
	sprite_frames.add_animation("walk_up_right")
	sprite_frames.set_animation_loop("walk_up_right", true)
	sprite_frames.set_animation_speed("walk_up_right", 8.0)
	add_frames_from_row("walk_up_right", WALK_UP_ROW, 9)  # We'll flip these
	
	# Up
	sprite_frames.add_animation("walk_up")
	sprite_frames.set_animation_loop("walk_up", true)
	sprite_frames.set_animation_speed("walk_up", 8.0)
	add_frames_from_row("walk_up", WALK_UP_ROW, 9)
	
	# Up-Left
	sprite_frames.add_animation("walk_up_left")
	sprite_frames.set_animation_loop("walk_up_left", true)
	sprite_frames.set_animation_speed("walk_up_left", 8.0)
	add_frames_from_row("walk_up_left", WALK_UP_ROW, 9)
	
	# Left
	sprite_frames.add_animation("walk_left")
	sprite_frames.set_animation_loop("walk_left", true)
	sprite_frames.set_animation_speed("walk_left", 8.0)
	add_frames_from_row("walk_left", WALK_LEFT_ROW, 9)
	
	# Down-Left
	sprite_frames.add_animation("walk_down_left")
	sprite_frames.set_animation_loop("walk_down_left", true)
	sprite_frames.set_animation_speed("walk_down_left", 8.0)
	add_frames_from_row("walk_down_left", WALK_DOWN_ROW, 9)

func create_idle_animations() -> void:
	"""Create idle animations (first frame of walk)"""
	var directions = ["down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left"]
	var rows = [WALK_DOWN_ROW, WALK_DOWN_ROW, WALK_RIGHT_ROW, WALK_UP_ROW, WALK_UP_ROW, WALK_UP_ROW, WALK_LEFT_ROW, WALK_DOWN_ROW]
	
	for i in range(directions.size()):
		var anim_name = "idle_" + directions[i]
		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_loop(anim_name, true)
		sprite_frames.set_animation_speed(anim_name, 1.0)
		add_frames_from_row(anim_name, rows[i], 1)  # Just first frame

func create_attack_animations() -> void:
	"""Create attack/slash animations for all 8 directions"""
	# Down
	sprite_frames.add_animation("attack_down")
	sprite_frames.set_animation_loop("attack_down", false)
	sprite_frames.set_animation_speed("attack_down", 12.0)
	add_frames_from_row("attack_down", SLASH_DOWN_ROW, 6)
	
	# Down-Right
	sprite_frames.add_animation("attack_down_right")
	sprite_frames.set_animation_loop("attack_down_right", false)
	sprite_frames.set_animation_speed("attack_down_right", 12.0)
	add_frames_from_row("attack_down_right", SLASH_DOWN_ROW, 6)
	
	# Right
	sprite_frames.add_animation("attack_right")
	sprite_frames.set_animation_loop("attack_right", false)
	sprite_frames.set_animation_speed("attack_right", 12.0)
	add_frames_from_row("attack_right", SLASH_RIGHT_ROW, 6)
	
	# Up-Right
	sprite_frames.add_animation("attack_up_right")
	sprite_frames.set_animation_loop("attack_up_right", false)
	sprite_frames.set_animation_speed("attack_up_right", 12.0)
	add_frames_from_row("attack_up_right", SLASH_UP_ROW, 6)
	
	# Up
	sprite_frames.add_animation("attack_up")
	sprite_frames.set_animation_loop("attack_up", false)
	sprite_frames.set_animation_speed("attack_up", 12.0)
	add_frames_from_row("attack_up", SLASH_UP_ROW, 6)
	
	# Up-Left
	sprite_frames.add_animation("attack_up_left")
	sprite_frames.set_animation_loop("attack_up_left", false)
	sprite_frames.set_animation_speed("attack_up_left", 12.0)
	add_frames_from_row("attack_up_left", SLASH_UP_ROW, 6)
	
	# Left
	sprite_frames.add_animation("attack_left")
	sprite_frames.set_animation_loop("attack_left", false)
	sprite_frames.set_animation_speed("attack_left", 12.0)
	add_frames_from_row("attack_left", SLASH_LEFT_ROW, 6)
	
	# Down-Left
	sprite_frames.add_animation("attack_down_left")
	sprite_frames.set_animation_loop("attack_down_left", false)
	sprite_frames.set_animation_speed("attack_down_left", 12.0)
	add_frames_from_row("attack_down_left", SLASH_DOWN_ROW, 6)

func add_frames_from_row(animation_name: String, row: int, frame_count: int) -> void:
	"""Extract frames from a spritesheet row and composite layers"""
	for frame_idx in range(frame_count):
		var combined = create_combined_frame(row, frame_idx)
		if combined:
			sprite_frames.add_frame(animation_name, combined)

func create_combined_frame(row: int, frame_idx: int) -> ImageTexture:
	"""Composite all layers for a single frame"""
	var combined_image = Image.create(FRAME_SIZE, FRAME_SIZE, false, Image.FORMAT_RGBA8)
	combined_image.fill(Color.TRANSPARENT)
	
	# Draw body layer
	if body_texture:
		blit_frame(combined_image, body_texture.get_image(), row, frame_idx)
	
	# Draw clothing layers
	for clothing_tex in clothing_textures:
		blit_frame(combined_image, clothing_tex.get_image(), row, frame_idx)
	
	# Draw weapon layer
	if weapon_texture:
		blit_frame(combined_image, weapon_texture.get_image(), row, frame_idx)
	
	return ImageTexture.create_from_image(combined_image)

func blit_frame(dest: Image, source: Image, row: int, frame_idx: int) -> void:
	"""Copy a single frame from spritesheet to destination"""
	var src_rect = Rect2i(frame_idx * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
	dest.blit_rect(source, src_rect, Vector2i.ZERO)

func update_animation(velocity: Vector2, attacking: bool = false) -> void:
	"""Update animation based on movement and state"""
	# Determine direction from velocity
	if velocity.length() > 0 or attacking:
		current_direction = get_direction_from_vector(velocity if velocity.length() > 0 else Vector2.DOWN)
	
	# Get direction string
	var dir_str = get_direction_string(current_direction)
	
	# Play appropriate animation
	if attacking:
		play("attack_" + dir_str)
		is_attacking = true
	elif velocity.length() > 0:
		play("walk_" + dir_str)
		is_walking = true
		is_attacking = false
	else:
		play("idle_" + dir_str)
		is_walking = false
		is_attacking = false
	
	# Handle flipping for diagonal directions
	flip_h = current_direction in [Direction.DOWN_RIGHT, Direction.RIGHT, Direction.UP_RIGHT]

func get_direction_from_vector(vec: Vector2) -> Direction:
	"""Convert velocity vector to 8-way direction"""
	if vec.length() == 0:
		return current_direction
	
	var angle = vec.angle()
	
	# Convert angle to direction (8-way)
	# -PI to PI, divide into 8 sections
	var section = int(round((angle + PI) / (PI / 4))) % 8
	
	match section:
		0: return Direction.LEFT
		1: return Direction.DOWN_LEFT
		2: return Direction.DOWN
		3: return Direction.DOWN_RIGHT
		4: return Direction.RIGHT
		5: return Direction.UP_RIGHT
		6: return Direction.UP
		7: return Direction.UP_LEFT
		_: return Direction.DOWN

func get_direction_string(dir: Direction) -> String:
	"""Convert direction enum to animation name string"""
	match dir:
		Direction.DOWN: return "down"
		Direction.DOWN_RIGHT: return "down_right"
		Direction.RIGHT: return "right"
		Direction.UP_RIGHT: return "up_right"
		Direction.UP: return "up"
		Direction.UP_LEFT: return "up_left"
		Direction.LEFT: return "left"
		Direction.DOWN_LEFT: return "down_left"
		_: return "down"

func play_attack() -> void:
	"""Trigger attack animation"""
	var dir_str = get_direction_string(current_direction)
	play("attack_" + dir_str)
	is_attacking = true
