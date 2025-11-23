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

# Shadow layer (below body)
var shadow_sprite: AnimatedSprite2D = null

# Armor layers (optional) - between body and weapon
# z-index order: shadow(-10) -> body(0) -> base_head(1) -> boots(2) -> pants(3) -> shirt(4) -> arms(5) -> hands(6) -> hair(7) -> head_armor(8) -> weapon(9/-1)
var base_head_sprite: AnimatedSprite2D = null  # Female character uses separate head layer
var boots_sprite: AnimatedSprite2D = null
var pants_sprite: AnimatedSprite2D = null
var shirt_sprite: AnimatedSprite2D = null
var arms_sprite: AnimatedSprite2D = null
var hands_sprite: AnimatedSprite2D = null
var head_sprite: AnimatedSprite2D = null  # Head armor (helmets)
var hair_sprite: AnimatedSprite2D = null

# Weapon layer (optional)
var weapon_sprite: AnimatedSprite2D = null

func setup_lpc_sprite(
	walk_tex: Texture2D,
	slash_tex: Texture2D = null,
	hurt_tex: Texture2D = null,
	shadow_walk_tex: Texture2D = null,
	shadow_slash_tex: Texture2D = null,
	base_head_walk_tex: Texture2D = null,
	base_head_slash_tex: Texture2D = null,
	boots_walk_tex: Texture2D = null,
	boots_slash_tex: Texture2D = null,
	pants_walk_tex: Texture2D = null,
	pants_slash_tex: Texture2D = null,
	shirt_walk_tex: Texture2D = null,
	shirt_slash_tex: Texture2D = null,
	arms_walk_tex: Texture2D = null,
	arms_slash_tex: Texture2D = null,
	hands_walk_tex: Texture2D = null,
	hands_slash_tex: Texture2D = null,
	head_walk_tex: Texture2D = null,
	head_slash_tex: Texture2D = null,
	hair_walk_tex: Texture2D = null,
	hair_slash_tex: Texture2D = null,
	weapon_slash_tex: Texture2D = null,
	weapon_walk_tex: Texture2D = null,
	weapon_type: String = "sword",
	is_female: bool = false
):
	"""Setup LPC sprite with layered body, armor, and weapon textures"""
	print("SimpleLPCSprite.setup_lpc_sprite() called")
	print("  walk_texture: ", walk_tex, " size: ", walk_tex.get_size() if walk_tex else "null")
	print("  slash_texture: ", slash_tex, " size: ", slash_tex.get_size() if slash_tex else "null")
	print("  hurt_texture: ", hurt_tex, " size: ", hurt_tex.get_size() if hurt_tex else "null")
	print("  base_head_walk_tex: ", base_head_walk_tex, " size: ", base_head_walk_tex.get_size() if base_head_walk_tex else "null")
	print("  base_head_slash_tex: ", base_head_slash_tex, " size: ", base_head_slash_tex.get_size() if base_head_slash_tex else "null")
	print("  boots_walk_tex: ", boots_walk_tex, " size: ", boots_walk_tex.get_size() if boots_walk_tex else "null")
	print("  boots_slash_tex: ", boots_slash_tex, " size: ", boots_slash_tex.get_size() if boots_slash_tex else "null")
	print("  pants_walk_tex: ", pants_walk_tex, " size: ", pants_walk_tex.get_size() if pants_walk_tex else "null")
	print("  pants_slash_tex: ", pants_slash_tex, " size: ", pants_slash_tex.get_size() if pants_slash_tex else "null")
	print("  shirt_walk_tex: ", shirt_walk_tex, " size: ", shirt_walk_tex.get_size() if shirt_walk_tex else "null")
	print("  shirt_slash_tex: ", shirt_slash_tex, " size: ", shirt_slash_tex.get_size() if shirt_slash_tex else "null")
	print("  arms_walk_tex: ", arms_walk_tex, " size: ", arms_walk_tex.get_size() if arms_walk_tex else "null")
	print("  arms_slash_tex: ", arms_slash_tex, " size: ", arms_slash_tex.get_size() if arms_slash_tex else "null")
	print("  hands_walk_tex: ", hands_walk_tex, " size: ", hands_walk_tex.get_size() if hands_walk_tex else "null")
	print("  hands_slash_tex: ", hands_slash_tex, " size: ", hands_slash_tex.get_size() if hands_slash_tex else "null")
	print("  head_walk_tex: ", head_walk_tex, " size: ", head_walk_tex.get_size() if head_walk_tex else "null")
	print("  head_slash_tex: ", head_slash_tex, " size: ", head_slash_tex.get_size() if head_slash_tex else "null")
	print("  hair_walk_tex: ", hair_walk_tex, " size: ", hair_walk_tex.get_size() if hair_walk_tex else "null")
	print("  hair_slash_tex: ", hair_slash_tex, " size: ", hair_slash_tex.get_size() if hair_slash_tex else "null")
	print("  weapon_slash_tex: ", weapon_slash_tex, " path: ", weapon_slash_tex.resource_path if weapon_slash_tex else "null", " size: ", weapon_slash_tex.get_size() if weapon_slash_tex else "null")
	print("  weapon_walk_tex: ", weapon_walk_tex, " path: ", weapon_walk_tex.resource_path if weapon_walk_tex else "null", " size: ", weapon_walk_tex.get_size() if weapon_walk_tex else "null")

	sprite_frames = SpriteFrames.new()

	# ✨ Get weapon-specific slash FPS for ALL body parts to sync animations
	var slash_fps = WeaponAnimationDataFactory.get_slash_fps(weapon_type)
	print("  ⚡ Using weapon-specific slash FPS for all body parts: %.1f" % slash_fps)

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

	# Create slash animations (use weapon-specific FPS!)
	if slash_tex:
		var slash_img = slash_tex.get_image()
		print("  Creating slash animations from image...")

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, null, 64)

		print("  Slash animations created")

	# Create hurt animation (single direction - south/row 2)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()
		print("  Creating hurt animation from image...")
		create_animation_from_image(hurt_img, "hurt", 2, 6, [0, 1, 2, 3, 4, 5], 10.0, false, null, 64)

	# Debug: List all animations created
	print("  📋 Animations created: ", sprite_frames.get_animation_names())
	print("  📊 Total animations: ", sprite_frames.get_animation_names().size())

	# Setup shadow layer (z=-10 - below everything)
	if shadow_walk_tex or shadow_slash_tex:
		print("  👤 Creating shadow layer...")
		shadow_sprite = AnimatedSprite2D.new()
		shadow_sprite.name = "ShadowLayer"
		shadow_sprite.centered = true
		shadow_sprite.z_index = -10
		shadow_sprite.sprite_frames = SpriteFrames.new()
		shadow_sprite.modulate = Color(1, 1, 1, 0.6)  # Semi-transparent

		if shadow_walk_tex:
			var shadow_walk_img = shadow_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shadow_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, shadow_sprite.sprite_frames, 64)
				create_animation_from_image(shadow_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, shadow_sprite.sprite_frames, 64)

		if shadow_slash_tex:
			var shadow_slash_img = shadow_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shadow_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, shadow_sprite.sprite_frames, 64)

		add_child(shadow_sprite)
		shadow_sprite.visible = true
		shadow_sprite.play("idle_south")
		print("  ✅ Shadow layer created (z_index=%d, visible=%s, modulate=%s)" % [shadow_sprite.z_index, shadow_sprite.visible, shadow_sprite.modulate])

	# Setup base head layer (z=1 - for female characters with separate head)
	if base_head_walk_tex or base_head_slash_tex:
		print("  👤 Creating base head layer...")
		base_head_sprite = AnimatedSprite2D.new()
		base_head_sprite.name = "BaseHeadLayer"
		base_head_sprite.centered = true
		base_head_sprite.z_index = 1
		base_head_sprite.sprite_frames = SpriteFrames.new()
		base_head_sprite.modulate = Color(1, 1, 1, 1)

		if base_head_walk_tex:
			var base_head_walk_img = base_head_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(base_head_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, base_head_sprite.sprite_frames, 64)
				create_animation_from_image(base_head_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, base_head_sprite.sprite_frames, 64)

		if base_head_slash_tex:
			var base_head_slash_img = base_head_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(base_head_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, base_head_sprite.sprite_frames, 64)

		add_child(base_head_sprite)
		base_head_sprite.visible = true
		base_head_sprite.play("idle_south")
		print("  ✅ Base head layer created (z_index=%d, visible=%s, modulate=%s)" % [base_head_sprite.z_index, base_head_sprite.visible, base_head_sprite.modulate])

	# Setup boots layer (z=2 - above base head)
	if boots_walk_tex or boots_slash_tex:
		print("  🥾 Creating boots layer...")
		boots_sprite = AnimatedSprite2D.new()
		boots_sprite.name = "BootsLayer"
		boots_sprite.centered = true
		boots_sprite.z_index = 2
		boots_sprite.sprite_frames = SpriteFrames.new()
		boots_sprite.modulate = Color(1, 1, 1, 1)

		if boots_walk_tex:
			var boots_walk_img = boots_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(boots_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, boots_sprite.sprite_frames, 64)
				create_animation_from_image(boots_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, boots_sprite.sprite_frames, 64)

		if boots_slash_tex:
			var boots_slash_img = boots_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(boots_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, boots_sprite.sprite_frames, 64)

		add_child(boots_sprite)
		boots_sprite.visible = true
		boots_sprite.play("idle_south")
		print("  ✅ Boots layer created (z_index=%d, visible=%s, modulate=%s)" % [boots_sprite.z_index, boots_sprite.visible, boots_sprite.modulate])

	# Setup pants layer (z=3 - above boots)
	if pants_walk_tex or pants_slash_tex:
		print("  🩳 Creating pants layer...")
		pants_sprite = AnimatedSprite2D.new()
		pants_sprite.name = "PantsLayer"
		pants_sprite.centered = true
		pants_sprite.z_index = 3
		pants_sprite.sprite_frames = SpriteFrames.new()
		pants_sprite.modulate = Color(1, 1, 1, 1)

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
				create_animation_from_image(pants_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, pants_sprite.sprite_frames, 64)

		add_child(pants_sprite)
		pants_sprite.visible = true
		pants_sprite.play("idle_south")
		print("  ✅ Pants layer created (z_index=%d, visible=%s, modulate=%s)" % [pants_sprite.z_index, pants_sprite.visible, pants_sprite.modulate])

	# Setup shirt layer (z=4 - above pants)
	if shirt_walk_tex or shirt_slash_tex:
		print("  👕 Creating shirt layer...")
		shirt_sprite = AnimatedSprite2D.new()
		shirt_sprite.name = "ShirtLayer"
		shirt_sprite.centered = true
		shirt_sprite.z_index = 4
		shirt_sprite.sprite_frames = SpriteFrames.new()
		shirt_sprite.modulate = Color(1, 1, 1, 1)

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
				create_animation_from_image(shirt_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, shirt_sprite.sprite_frames, 64)

		add_child(shirt_sprite)
		shirt_sprite.visible = true
		shirt_sprite.play("idle_south")
		print("  ✅ Shirt layer created (z_index=%d, visible=%s, modulate=%s)" % [shirt_sprite.z_index, shirt_sprite.visible, shirt_sprite.modulate])

	# Setup arms layer (z=5 - above shirt)
	if arms_walk_tex or arms_slash_tex:
		print("  💪 Creating arms layer...")
		arms_sprite = AnimatedSprite2D.new()
		arms_sprite.name = "ArmsLayer"
		arms_sprite.centered = true
		arms_sprite.z_index = 5
		arms_sprite.sprite_frames = SpriteFrames.new()
		arms_sprite.modulate = Color(1, 1, 1, 1)

		if arms_walk_tex:
			var arms_walk_img = arms_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(arms_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, arms_sprite.sprite_frames, 64)
				create_animation_from_image(arms_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, arms_sprite.sprite_frames, 64)

		if arms_slash_tex:
			var arms_slash_img = arms_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(arms_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, arms_sprite.sprite_frames, 64)

		add_child(arms_sprite)
		arms_sprite.visible = true
		arms_sprite.play("idle_south")
		print("  ✅ Arms layer created (z_index=%d, visible=%s, modulate=%s)" % [arms_sprite.z_index, arms_sprite.visible, arms_sprite.modulate])

	# Setup hands layer (z=6 - above arms)
	if hands_walk_tex or hands_slash_tex:
		print("  🧤 Creating hands layer...")
		hands_sprite = AnimatedSprite2D.new()
		hands_sprite.name = "HandsLayer"
		hands_sprite.centered = true
		hands_sprite.z_index = 6
		hands_sprite.sprite_frames = SpriteFrames.new()
		hands_sprite.modulate = Color(1, 1, 1, 1)

		if hands_walk_tex:
			var hands_walk_img = hands_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hands_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, hands_sprite.sprite_frames, 64)
				create_animation_from_image(hands_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, hands_sprite.sprite_frames, 64)

		if hands_slash_tex:
			var hands_slash_img = hands_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hands_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, hands_sprite.sprite_frames, 64)

		add_child(hands_sprite)
		hands_sprite.visible = true
		hands_sprite.play("idle_south")
		print("  ✅ Hands layer created (z_index=%d, visible=%s, modulate=%s)" % [hands_sprite.z_index, hands_sprite.visible, hands_sprite.modulate])

	# Setup hair layer (z=7 - above hands, UNDER head armor)
	if hair_walk_tex or hair_slash_tex:
		print("  💇 Creating hair layer...")
		hair_sprite = AnimatedSprite2D.new()
		hair_sprite.name = "HairLayer"
		hair_sprite.centered = true
		hair_sprite.z_index = 7
		hair_sprite.sprite_frames = SpriteFrames.new()
		hair_sprite.modulate = Color(1, 1, 1, 1)

		if hair_walk_tex:
			var hair_walk_img = hair_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hair_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, hair_sprite.sprite_frames, 64)
				create_animation_from_image(hair_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, hair_sprite.sprite_frames, 64)

		if hair_slash_tex:
			var hair_slash_img = hair_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hair_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, hair_sprite.sprite_frames, 64)

		add_child(hair_sprite)
		hair_sprite.visible = true
		hair_sprite.play("idle_south")
		print("  ✅ Hair layer created (z_index=%d, visible=%s, modulate=%s)" % [hair_sprite.z_index, hair_sprite.visible, hair_sprite.modulate])

	# Setup head layer (z=8 - above hair, for head armor/helmets)
	if head_walk_tex or head_slash_tex:
		print("  🪖 Creating head armor layer...")
		head_sprite = AnimatedSprite2D.new()
		head_sprite.name = "HeadArmorLayer"
		head_sprite.centered = true
		head_sprite.z_index = 8
		head_sprite.sprite_frames = SpriteFrames.new()
		head_sprite.modulate = Color(1, 1, 1, 1)

		if head_walk_tex:
			var head_walk_img = head_walk_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(head_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, head_sprite.sprite_frames, 64)
				create_animation_from_image(head_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, head_sprite.sprite_frames, 64)

		if head_slash_tex:
			var head_slash_img = head_slash_tex.get_image()
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(head_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, head_sprite.sprite_frames, 64)

		add_child(head_sprite)
		head_sprite.visible = true
		head_sprite.play("idle_south")
		print("  ✅ Head layer created (z_index=%d, visible=%s, modulate=%s)" % [head_sprite.z_index, head_sprite.visible, head_sprite.modulate])

	# Setup weapon layer if provided
	if weapon_slash_tex or weapon_walk_tex:
		print("  Creating weapon layer...")
		weapon_sprite = AnimatedSprite2D.new()
		weapon_sprite.name = "WeaponLayer"
		weapon_sprite.centered = true
		weapon_sprite.z_index = 9  # Draw weapon on top (above head armor z=8)
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

			# Weapon slash FPS already set at function scope (line 63)
			print("  ⚡ Weapon type '%s' slash FPS: %.1f" % [weapon_type, slash_fps])

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(weapon_slash_img, "slash_" + dir_name, row, 6, [0, 1, 2, 3, 4, 5], slash_fps, false, weapon_sprite.sprite_frames, slash_tile_size)

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

			# Get weapon-specific walk and idle FPS
			var walk_fps = WeaponAnimationDataFactory.get_walk_fps(weapon_type)
			var idle_fps = WeaponAnimationDataFactory.get_idle_fps(weapon_type)
			print("  ⚡ Weapon type '%s' walk FPS: %.1f, idle FPS: %.1f" % [weapon_type, walk_fps, idle_fps])

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(weapon_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], walk_fps, true, weapon_sprite.sprite_frames, walk_tile_size)
				create_animation_from_image(weapon_walk_img, "idle_" + dir_name, row, 1, [0], idle_fps, true, weapon_sprite.sprite_frames, walk_tile_size)

		add_child(weapon_sprite)

		# Show weapon if we have walk animations, hide otherwise
		if weapon_walk_tex:
			weapon_sprite.visible = true
			weapon_sprite.play("idle_south")  # Start with idle
			print("  ✅ Weapon layer created with walk animations (visible, z_index=9)")
		else:
			weapon_sprite.visible = false
			weapon_sprite.stop()
			print("  ✅ Weapon layer created (slash only, hidden, z_index=9)")

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

	# ✨ SMOOTH TIMING FIX: For slash animations, adjust frame sequence for better pacing
	# Add middle frames twice to prevent rushing, skip last frame duplication to prevent hang
	var adjusted_indices = frame_indices.duplicate()
	if anim_name.begins_with("slash_") and not loop and frame_indices.size() == 6:
		# Original: [0, 1, 2, 3, 4, 5]
		# Adjusted: [0, 1, 2, 2, 3, 3, 4, 4, 5] - middle frames get more time, smooth acceleration
		adjusted_indices = [0, 1, 2, 2, 3, 3, 4, 4, 5]

	for frame_idx in adjusted_indices:
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

	# Sync shadow animation with body animation
	if shadow_sprite:
		if shadow_sprite.sprite_frames.has_animation(anim_key):
			shadow_sprite.play(anim_key)
		elif shadow_sprite.sprite_frames.has_animation(anim_name):
			shadow_sprite.play(anim_name)

	# Sync armor animations with body animation
	if base_head_sprite:
		if base_head_sprite.sprite_frames.has_animation(anim_key):
			base_head_sprite.play(anim_key)
		elif base_head_sprite.sprite_frames.has_animation(anim_name):
			base_head_sprite.play(anim_name)

	if boots_sprite:
		if boots_sprite.sprite_frames.has_animation(anim_key):
			boots_sprite.play(anim_key)
		elif boots_sprite.sprite_frames.has_animation(anim_name):
			boots_sprite.play(anim_name)

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

	if arms_sprite:
		if arms_sprite.sprite_frames.has_animation(anim_key):
			arms_sprite.play(anim_key)
		elif arms_sprite.sprite_frames.has_animation(anim_name):
			arms_sprite.play(anim_name)

	if hands_sprite:
		if hands_sprite.sprite_frames.has_animation(anim_key):
			hands_sprite.play(anim_key)
		elif hands_sprite.sprite_frames.has_animation(anim_name):
			hands_sprite.play(anim_name)

	if head_sprite:
		if head_sprite.sprite_frames.has_animation(anim_key):
			head_sprite.play(anim_key)
		elif head_sprite.sprite_frames.has_animation(anim_name):
			head_sprite.play(anim_name)

	if hair_sprite:
		if hair_sprite.sprite_frames.has_animation(anim_key):
			hair_sprite.play(anim_key)
		elif hair_sprite.sprite_frames.has_animation(anim_name):
			hair_sprite.play(anim_name)

	# Sync weapon animation with body animation
	if weapon_sprite:
		# Allow slash animation to restart for rapid attack feel
		# Only prevent interrupt if it's NOT a slash (e.g., switching to walk/idle mid-slash)
		if weapon_sprite.animation and weapon_sprite.animation.begins_with("slash_") and weapon_sprite.is_playing():
			if anim_name != "slash":
				# Don't interrupt slash with walk/idle
				return

		if weapon_sprite.sprite_frames.has_animation(anim_key):
			weapon_sprite.play(anim_key)
			weapon_sprite.visible = true
			# When facing north (up), draw weapon behind character
			weapon_sprite.z_index = -1 if direction == "north" else 9

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
			weapon_sprite.z_index = -1 if direction == "north" else 9
		else:
			# No matching weapon animation, hide weapon
			weapon_sprite.visible = false
			weapon_sprite.stop()
			if anim_name == "slash":
				print("  ❌ No weapon slash animation found for: %s" % anim_key)

func is_lpc_animation_playing() -> bool:
	"""Check if animation is currently playing"""
	return is_playing()
