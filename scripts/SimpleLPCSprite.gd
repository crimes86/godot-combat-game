extends AnimatedSprite2D
class_name SimpleLPCSprite

## Simple LPC sprite handler with row-based directions
## NO SPRITE FLIPPING - uses correct row for each direction

# Direction to row mapping (LPC standard)
const DIRECTION_ROWS = {
	"north": 0,
	"west": 1,
	"south": 2,
	"east": 3
}

# Current state
var current_direction := "south"
var sprite_frames_data := {}

func setup_lpc_sprite(walk_texture: Texture2D, slash_texture: Texture2D = null, hurt_texture: Texture2D = null):
	"""Setup LPC sprite with standard walk/slash/hurt textures"""
	sprite_frames = SpriteFrames.new()

	# Create walk animations for all 4 directions
	if walk_texture:
		create_lpc_animation("walk", walk_texture, 9, [1, 2, 3, 4, 5, 6, 7, 8], 10.0)
		create_lpc_animation("idle", walk_texture, 1, [0], 1.0)

	# Create slash animations for all 4 directions
	if slash_texture:
		create_lpc_animation("slash", slash_texture, 6, null, 12.0, false)

	# Create hurt animation (usually only south direction)
	if hurt_texture:
		create_single_direction_animation("hurt", hurt_texture, 6, 10.0, false)

func create_lpc_animation(anim_name: String, texture: Texture2D, frame_count: int, custom_frames: Array = [], fps: float = 10.0, loop: bool = true):
	"""Create animation for all 4 directions using LPC row-based system"""
	for dir_name in DIRECTION_ROWS.keys():
		var anim_key = anim_name + "_" + dir_name
		sprite_frames.add_animation(anim_key)
		sprite_frames.set_animation_loop(anim_key, loop)
		sprite_frames.set_animation_speed(anim_key, fps)

		var row = DIRECTION_ROWS[dir_name]
		var frames_to_use = custom_frames if custom_frames.size() > 0 else range(frame_count)

		for frame_idx in frames_to_use:
			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(frame_idx * 64, row * 64, 64, 64)
			sprite_frames.add_frame(anim_key, atlas)

func create_single_direction_animation(anim_name: String, texture: Texture2D, frame_count: int, fps: float = 10.0, loop: bool = false):
	"""Create animation with only one direction (like hurt)"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	for frame_idx in range(frame_count):
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(frame_idx * 64, 0, 64, 64)  # Always row 0
		sprite_frames.add_frame(anim_name, atlas)

func play_lpc_animation(anim_name: String, direction: String):
	"""Play animation with direction - NO FLIPPING!"""
	current_direction = direction

	# Check if this animation has directions
	var anim_key = anim_name + "_" + direction
	if sprite_frames and sprite_frames.has_animation(anim_key):
		play(anim_key)
	elif sprite_frames and sprite_frames.has_animation(anim_name):
		# Animation without directions (like hurt)
		play(anim_name)
	else:
		push_warning("Animation not found: " + anim_key)

func is_lpc_animation_playing() -> bool:
	"""Check if animation is currently playing"""
	return is_playing()
