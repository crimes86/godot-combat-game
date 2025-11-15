extends Sprite2D
class_name SimpleLPCSprite

## Simple LPC sprite handler with row-based directions
## NO SPRITE FLIPPING - uses correct row for each direction

# Direction to row mapping (LPC standard)
# LPC sprites use simple row-based directions:
# - Row 0 = north/up
# - Row 1 = west/left
# - Row 2 = south/down
# - Row 3 = east/right
# All animation types (walk, slash, hurt) use these same rows
const DIRECTION_ROWS = {
	"north": 0,  # up
	"west": 1,   # left
	"south": 2,  # down
	"east": 3    # right
}

# Current state
var current_direction := "south"
var current_animation := "idle"
var current_frame := 0
var animation_timer := 0.0
var animation_speed := 10.0  # FPS
var is_playing := false
var loop := true

# Textures
var walk_texture: Texture2D
var slash_texture: Texture2D
var hurt_texture: Texture2D

# Animation data
var animation_frames := {
	"walk": {"frames": [1, 2, 3, 4, 5, 6, 7, 8], "fps": 10.0, "loop": true},
	"idle": {"frames": [0], "fps": 1.0, "loop": true},
	"slash": {"frames": [0, 1, 2, 3, 4, 5], "fps": 12.0, "loop": false},
	"hurt": {"frames": [0, 1, 2, 3, 4, 5], "fps": 10.0, "loop": false}
}

signal animation_finished

func setup_lpc_sprite(walk_tex: Texture2D, slash_tex: Texture2D = null, hurt_tex: Texture2D = null):
	"""Setup LPC sprite with standard walk/slash/hurt textures"""
	print("SimpleLPCSprite.setup_lpc_sprite() called")
	print("  walk_texture: ", walk_tex, " size: ", walk_tex.get_size() if walk_tex else "null")
	print("  slash_texture: ", slash_tex, " size: ", slash_tex.get_size() if slash_tex else "null")
	print("  hurt_texture: ", hurt_tex, " size: ", hurt_tex.get_size() if hurt_tex else "null")

	# Store textures
	walk_texture = walk_tex
	slash_texture = slash_tex
	hurt_texture = hurt_tex

	# Enable region and set initial state
	region_enabled = true
	texture = walk_texture

	# Start with idle south (row 2, frame 0)
	current_animation = "idle"
	current_direction = "south"
	current_frame = 0
	update_sprite_region()

	print("  ✅ Sprite setup complete - region: ", region_rect)

func play_lpc_animation(anim_name: String, direction: String):
	"""Play animation with direction - NO FLIPPING!"""
	if not animation_frames.has(anim_name):
		push_warning("Unknown animation: " + anim_name)
		return

	current_animation = anim_name
	current_direction = direction
	current_frame = 0
	animation_timer = 0.0

	var anim_data = animation_frames[anim_name]
	animation_speed = anim_data["fps"]
	loop = anim_data["loop"]
	is_playing = true

	# Switch texture based on animation
	if anim_name == "slash" and slash_texture:
		texture = slash_texture
	elif anim_name == "hurt" and hurt_texture:
		texture = hurt_texture
	else:
		texture = walk_texture

	update_sprite_region()

func update_sprite_region():
	"""Update the sprite region to show the current frame"""
	if not texture:
		return

	var row = DIRECTION_ROWS[current_direction]
	var anim_data = animation_frames[current_animation]
	var frame_list = anim_data["frames"]
	var actual_frame = frame_list[current_frame]

	region_rect = Rect2(actual_frame * 64, row * 64, 64, 64)

func _process(delta):
	"""Handle animation frame updates"""
	if not is_playing:
		return

	animation_timer += delta
	var frame_time = 1.0 / animation_speed

	if animation_timer >= frame_time:
		animation_timer = 0.0
		var anim_data = animation_frames[current_animation]
		var frame_list = anim_data["frames"]

		current_frame += 1
		if current_frame >= frame_list.size():
			if loop:
				current_frame = 0
			else:
				current_frame = frame_list.size() - 1
				is_playing = false
				animation_finished.emit()

		update_sprite_region()

func is_lpc_animation_playing() -> bool:
	"""Check if animation is currently playing"""
	return is_playing

func play(anim_name: String = ""):
	"""Compatibility wrapper for play()"""
	if anim_name != "":
		# Try to extract direction from name
		if "_" in anim_name:
			var parts = anim_name.split("_")
			play_lpc_animation(parts[0], parts[1])
		else:
			play_lpc_animation(anim_name, current_direction)
	is_playing = true
