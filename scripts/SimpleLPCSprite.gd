extends AnimatedSprite2D
class_name SimpleLPCSprite

## Simple LPC sprite handler with row-based directions
## NO SPRITE FLIPPING - uses correct row for each direction
## Uses the SAME approach as working Enemy.gd skeleton code

# Direction to row mapping (LPC standard)
const DIRECTION_ROWS = {
	"north": 0,  # up
	"west": 1,   # left
	"south": 2,  # down
	"east": 3    # right
}

# Current state
var current_direction := "south"

func setup_lpc_sprite(walk_tex: Texture2D, slash_tex: Texture2D = null, hurt_tex: Texture2D = null):
	"""Setup LPC sprite with standard walk/slash/hurt textures - EXACTLY like Enemy.gd"""
	print("SimpleLPCSprite.setup_lpc_sprite() called")
	print("  walk_texture: ", walk_tex, " size: ", walk_tex.get_size() if walk_tex else "null")
	print("  slash_texture: ", slash_tex, " size: ", slash_tex.get_size() if slash_tex else "null")
	print("  hurt_texture: ", hurt_tex, " size: ", hurt_tex.get_size() if hurt_tex else "null")

	sprite_frames = SpriteFrames.new()

	# Create walk animations using Image.blit_rect() like skeletons do
	if walk_tex:
		var walk_img = walk_tex.get_image()
		print("  Creating walk/idle animations from image...")

		# Walk animations - 4 rows (north/west/south/east), frames 1-8
		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true)
			create_animation_from_image(walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true)

		print("  Walk/idle animations created")

	# Create slash animations
	if slash_tex:
		var slash_img = slash_tex.get_image()
		print("  Creating slash animations from image...")

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], 12.0, false)

		print("  Slash animations created")

	# Create hurt animation (single direction - south/row 2)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()
		print("  Creating hurt animation from image...")
		create_animation_from_image(hurt_img, "hurt", 2, 6, [0, 1, 2, 3, 4, 5], 10.0, false)

	# Debug: List all animations created
	print("  📋 Animations created: ", sprite_frames.get_animation_names())
	print("  📊 Total animations: ", sprite_frames.get_animation_names().size())

	# Start with idle_south
	print("  Starting idle_south animation...")
	if sprite_frames.has_animation("idle_south"):
		play("idle_south")
		print("  ✅ SimpleLPCSprite setup complete!")
		print("  🎬 Currently playing: ", animation)
	else:
		print("  ERROR: idle_south animation not found!")
		print("  Available animations: ", sprite_frames.get_animation_names())

func create_animation_from_image(img: Image, anim_name: String, row: int, frame_count: int, frame_indices: Array, fps: float, loop: bool):
	"""Create animation from spritesheet using Image.blit_rect() - EXACTLY like Enemy.gd create_skeleton_animation()"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	for frame_idx in frame_indices:
		# Create new 64x64 image for this frame
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		# Blit the region from the source image
		frame_img.blit_rect(img, Rect2i(frame_idx * 64, row * 64, 64, 64), Vector2i(0, 0))
		# Convert to texture
		var frame_texture = ImageTexture.create_from_image(frame_img)
		# Add to sprite frames
		sprite_frames.add_frame(anim_name, frame_texture)

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
