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

# Armor layers (optional) - between body and weapon
var shirt_sprite: AnimatedSprite2D = null
var pants_sprite: AnimatedSprite2D = null

# Weapon layer (optional)
var weapon_sprite: AnimatedSprite2D = null

func setup_lpc_sprite(
	walk_tex: Texture2D,
	slash_tex: Texture2D = null,
	hurt_tex: Texture2D = null,
	shirt_walk_tex: Texture2D = null,
	shirt_slash_tex: Texture2D = null,
	pants_walk_tex: Texture2D = null,
	pants_slash_tex: Texture2D = null,
	weapon_slash_tex: Texture2D = null,
	weapon_walk_tex: Texture2D = null
):
	"""Setup LPC sprite with layered body, armor, and weapon textures"""
	print("SimpleLPCSprite.setup_lpc_sprite() called")
	print("  walk_texture: ", walk_tex, " size: ", walk_tex.get_size() if walk_tex else "null")
	print("  slash_texture: ", slash_tex, " size: ", slash_tex.get_size() if slash_tex else "null")
	print("  hurt_texture: ", hurt_tex, " size: ", hurt_tex.get_size() if hurt_tex else "null")
	print("  shirt_walk_tex: ", shirt_walk_tex, " size: ", shirt_walk_tex.get_size() if shirt_walk_tex else "null")
	print("  shirt_slash_tex: ", shirt_slash_tex, " size: ", shirt_slash_tex.get_size() if shirt_slash_tex else "null")
	print("  pants_walk_tex: ", pants_walk_tex, " size: ", pants_walk_tex.get_size() if pants_walk_tex else "null")
	print("  pants_slash_tex: ", pants_slash_tex, " size: ", pants_slash_tex.get_size() if pants_slash_tex else "null")
	print("  weapon_slash_tex: ", weapon_slash_tex, " path: ", weapon_slash_tex.resource_path if weapon_slash_tex else "null", " size: ", weapon_slash_tex.get_size() if weapon_slash_tex else "null")
	print("  weapon_walk_tex: ", weapon_walk_tex, " path: ", weapon_walk_tex.resource_path if weapon_walk_tex else "null", " size: ", weapon_walk_tex.get_size() if weapon_walk_tex else "null")

	sprite_frames = SpriteFrames.new()

	# Create walk animations using Image.blit_rect() like skeletons do
	if walk_tex:
		var walk_img = walk_tex.get_image()
		print("  Creating walk/idle animations from image...")

		# Walk animations - 4 rows (north/west/south/east), frames 1-8
		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, null, 64)
			create_animation_from_image(walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, null, 64)

		print("  Walk/idle animations created")

	# Create slash animations
	if slash_tex:
		var slash_img = slash_tex.get_image()
		print("  Creating slash animations from image...")

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], 12.0, false, null, 64)

		print("  Slash animations created")

	# Create hurt animation (single direction - south/row 2)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()
		print("  Creating hurt animation from image...")
		create_animation_from_image(hurt_img, "hurt", 2, 6, [0, 1, 2, 3, 4, 5], 10.0, false, null, 64)

	# Debug: List all animations created
	print("  📋 Animations created: ", sprite_frames.get_animation_names())
	print("  📊 Total animations: ", sprite_frames.get_animation_names().size())

	# Setup pants layer (z=0.2 - above body, below shirt)
	if pants_walk_tex or pants_slash_tex:
		print("  🩳 Creating pants layer...")
		pants_sprite = AnimatedSprite2D.new()
		pants_sprite.name = "PantsLayer"
		pants_sprite.centered = true
		pants_sprite.z_index = 1  # Above body to be visible
		pants_sprite.sprite_frames = SpriteFrames.new()
		pants_sprite.modulate = Color(1, 1, 1, 1)  # Ensure full visibility

		if pants_walk_tex:
			var pants_walk_img = pants_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(pants_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, pants_sprite.sprite_frames, 64)
				create_animation_from_image(pants_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, pants_sprite.sprite_frames, 64)

		if pants_slash_tex:
			var pants_slash_img = pants_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(pants_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], 12.0, false, pants_sprite.sprite_frames, 64)

		add_child(pants_sprite)
		pants_sprite.visible = true
		pants_sprite.play("idle_south")
		print("  ✅ Pants layer created (z_index=1)")

	# Setup shirt layer (z=0.3 - above pants, below weapon)
	if shirt_walk_tex or shirt_slash_tex:
		print("  👕 Creating shirt layer...")
		shirt_sprite = AnimatedSprite2D.new()
		shirt_sprite.name = "ShirtLayer"
		shirt_sprite.centered = true
		shirt_sprite.z_index = 2  # Above pants (z=1) to be visible
		shirt_sprite.sprite_frames = SpriteFrames.new()
		shirt_sprite.modulate = Color(1, 1, 1, 1)  # Normal visibility

		if shirt_walk_tex:
			var shirt_walk_img = shirt_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shirt_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, shirt_sprite.sprite_frames, 64)
				create_animation_from_image(shirt_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, shirt_sprite.sprite_frames, 64)

		if shirt_slash_tex:
			var shirt_slash_img = shirt_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shirt_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], 12.0, false, shirt_sprite.sprite_frames, 64)

		add_child(shirt_sprite)
		shirt_sprite.visible = true
		shirt_sprite.play("idle_south")
		print("  ✅ Shirt layer created (z_index=2)")

	# Setup weapon layer if provided
	if weapon_slash_tex or weapon_walk_tex:
		print("  Creating weapon layer...")
		weapon_sprite = AnimatedSprite2D.new()
		weapon_sprite.name = "WeaponLayer"
		weapon_sprite.centered = true
		weapon_sprite.z_index = 3  # Draw weapon on top (above shirt z=2)
		weapon_sprite.sprite_frames = SpriteFrames.new()

		# Don't set a static offset here - we'll adjust it per animation type

		# Add slash animations if provided
		if weapon_slash_tex:
			var weapon_slash_img = weapon_slash_tex.get_image()
			var slash_size = weapon_slash_img.get_size()
			# Calculate tile size: width / 6 frames (LPC standard)
			var slash_tile_size = int(slash_size.x / 6)
			print("  📊 Weapon slash image size: ", slash_size)
			print("  📊 Calculated slash tile size: ", slash_tile_size, "x", slash_tile_size)
			print("  📊 Weapon slash image format: ", weapon_slash_img.get_format())

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				# Slower FPS (8.0 instead of 12.0) to make slash more visible - 6 frames at 8fps = 0.75 seconds
				create_animation_from_image(weapon_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], 8.0, false, weapon_sprite.sprite_frames, slash_tile_size)

			# DEBUG: Test if first frame of slash_south has any visible pixels
			var test_frame = weapon_sprite.sprite_frames.get_frame_texture("slash_south", 0)
			if test_frame:
				var test_img = test_frame.get_image()
				print("  🔍 Testing slash_south frame 0: size=", test_img.get_size())
				# Check a few pixels to see if they're transparent
				var pixel_check = []
				for x in [32, 64, 96, 128, 160]:
					for y in [32, 64, 96, 128, 160]:
						if x < test_img.get_width() and y < test_img.get_height():
							var pixel = test_img.get_pixel(x, y)
							if pixel.a > 0.1:  # Not fully transparent
								pixel_check.append("(%d,%d):visible" % [x, y])
				print("  🔍 Visible pixels found: ", pixel_check)

		# Add walk animations if provided
		if weapon_walk_tex:
			var weapon_walk_img = weapon_walk_tex.get_image()
			var walk_size = weapon_walk_img.get_size()
			# Calculate tile size: width / 9 frames (walk has 9 frames)
			var walk_tile_size = int(walk_size.x / 9)
			print("  📊 Weapon walk image size: ", walk_size)
			print("  📊 Calculated walk tile size: ", walk_tile_size, "x", walk_tile_size)

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(weapon_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, weapon_sprite.sprite_frames, walk_tile_size)
				create_animation_from_image(weapon_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, weapon_sprite.sprite_frames, walk_tile_size)

		add_child(weapon_sprite)

		# Show weapon if we have walk animations, hide otherwise
		if weapon_walk_tex:
			weapon_sprite.visible = true
			weapon_sprite.play("idle_south")  # Start with idle
			print("  ✅ Weapon layer created with walk animations (visible, z_index=3)")
		else:
			weapon_sprite.visible = false
			weapon_sprite.stop()
			print("  ✅ Weapon layer created (slash only, hidden, z_index=3)")

	# Start with idle_south
	print("  Starting idle_south animation...")
	if sprite_frames.has_animation("idle_south"):
		play("idle_south")
		print("  ✅ SimpleLPCSprite setup complete!")
		print("  🎬 Currently playing: ", animation)
	else:
		print("  ERROR: idle_south animation not found!")
		print("  Available animations: ", sprite_frames.get_animation_names())

func create_animation_from_image(img: Image, anim_name: String, row: int, frame_count: int, frame_indices: Array, fps: float, loop: bool, target_frames: SpriteFrames = null, tile_size: int = 64):
	"""Create animation from spritesheet using Image.blit_rect() - EXACTLY like Enemy.gd create_skeleton_animation()"""
	var frames = target_frames if target_frames else sprite_frames

	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)

	for frame_idx in frame_indices:
		# Create new image for this frame (using calculated tile_size)
		var frame_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		# Blit the region from the source image
		frame_img.blit_rect(img, Rect2i(frame_idx * tile_size, row * tile_size, tile_size, tile_size), Vector2i(0, 0))
		# Convert to texture
		var frame_texture = ImageTexture.create_from_image(frame_img)
		# Add to sprite frames
		frames.add_frame(anim_name, frame_texture)

func play_lpc_animation(anim_name: String, direction: String):
	"""Play animation with direction - NO FLIPPING!"""
	current_direction = direction

	# Check if this animation has directions
	var anim_key = anim_name + "_" + direction

	if anim_name == "slash":
		print("🗡️ SLASH ANIMATION REQUESTED: key='%s'" % anim_key)

	if sprite_frames and sprite_frames.has_animation(anim_key):
		play(anim_key)
		if anim_name == "slash":
			print("  ✅ Body playing slash: %s" % anim_key)
	elif sprite_frames and sprite_frames.has_animation(anim_name):
		# Animation without directions (like hurt)
		play(anim_name)
	else:
		push_warning("Animation not found: " + anim_key)

	# Sync armor animations with body animation
	if pants_sprite:
		if pants_sprite.sprite_frames.has_animation(anim_key):
			pants_sprite.play(anim_key)
		elif pants_sprite.sprite_frames.has_animation(anim_name):
			pants_sprite.play(anim_name)

	if shirt_sprite:
		if shirt_sprite.sprite_frames.has_animation(anim_key):
			shirt_sprite.play(anim_key)
		elif shirt_sprite.sprite_frames.has_animation(anim_name):
			shirt_sprite.play(anim_name)

	# Sync weapon animation with body animation
	if weapon_sprite:
		# Don't interrupt weapon slash animation if it's still playing
		if weapon_sprite.animation and weapon_sprite.animation.begins_with("slash_") and weapon_sprite.is_playing():
			if anim_name != "slash":  # Unless we're starting a new slash
				if anim_name == "slash":
					print("  ⚠️ Weapon already playing slash, keeping it")
				return  # Keep playing the current slash animation

		if weapon_sprite.sprite_frames.has_animation(anim_key):
			weapon_sprite.play(anim_key)
			weapon_sprite.visible = true
			# When facing north (up), draw weapon behind character
			weapon_sprite.z_index = -1 if direction == "north" else 3

			# Adjust offset based on animation type
			# Slash animations (192x192) need to be pulled closer to center based on direction
			if anim_name == "slash":
				# Direction-specific offsets to pull weapon toward player body
				var slash_offset = Vector2(0, 0)
				match direction:
					"east":  # facing right
						slash_offset = Vector2(-10, 5)
					"west":  # facing left
						slash_offset = Vector2(10, 5)
					"north":  # facing up
						slash_offset = Vector2(-10, 0)
					"south":  # facing down
						slash_offset = Vector2(-5, 5)
				weapon_sprite.offset = slash_offset
				print("  ✅ Weapon playing slash: %s (visible=%s, z=%d, offset=%s)" % [anim_key, weapon_sprite.visible, weapon_sprite.z_index, weapon_sprite.offset])
			else:
				weapon_sprite.offset = Vector2(0, 0)  # Normal position for walk/idle
		elif weapon_sprite.sprite_frames.has_animation(anim_name):
			# Animation without directions (like hurt)
			weapon_sprite.play(anim_name)
			weapon_sprite.visible = true
			weapon_sprite.z_index = -1 if direction == "north" else 3
		else:
			# No matching weapon animation, hide weapon
			weapon_sprite.visible = false
			weapon_sprite.stop()
			if anim_name == "slash":
				print("  ❌ No weapon slash animation found for: %s" % anim_key)

func is_lpc_animation_playing() -> bool:
	"""Check if animation is currently playing"""
	return is_playing()
