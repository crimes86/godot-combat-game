extends AnimatedSprite2D
class_name SimpleLPCSprite

## Simple LPC sprite handler with row-based directions
##
## REFACTOR NOTE (Dec 2024): Asset paths reorganized
## - Equipment moved to: res://assets/equipment/weapons/, tools/, armor/
## - Starter clothes remain at: res://assets/characters/pants/, shirt/, etc.
## - If armor sprites fail to load, check _extract_armor_path() handles the path format
## - Potential issues: armor tier files moved from armor/zone1/ to equipment/armor/tier1/
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

# Helper to detect attack animation frame count from image width
# Thrust = 8 frames (512px), Slash = 6 frames (384px)
static func get_attack_frame_count(img: Image) -> int:
	return 8 if img.get_width() >= 500 else 6

static func get_attack_frame_indices(num_frames: int) -> Array:
	var indices = []
	for i in range(num_frames):
		indices.append(i)
	return indices

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
var current_weapon_type: String = "sword"  # Track weapon type for offset calculations

# Harvest animation support - track if we need slash-based chop
var uses_thrust_animation: bool = false  # True if body uses 8-frame thrust
var body_type_path: String = ""  # e.g. "body_male" for loading slash.png during harvest

# Store armor texture paths for loading slash.png during harvest
var pants_armor_path: String = ""  # e.g. "legs/green_pants"
var shirt_armor_path: String = ""  # e.g. "chest/white_shirt"
var boots_armor_path: String = ""
var arms_armor_path: String = ""
var hands_armor_path: String = ""
var head_armor_path: String = ""  # Head armor (helmets)

# Frame sync - ensures all layers play at exactly the same frame
func _process(_delta: float) -> void:
	# Sync all child layer sprites to match body frame and animation
	# This prevents drift between independently playing AnimatedSprite2Ds
	var body_frame = frame
	var body_anim = animation

	_sync_layer(shadow_sprite, body_anim, body_frame)
	_sync_layer(base_head_sprite, body_anim, body_frame)
	_sync_layer(boots_sprite, body_anim, body_frame)
	_sync_layer(pants_sprite, body_anim, body_frame)
	_sync_layer(shirt_sprite, body_anim, body_frame)
	_sync_layer(arms_sprite, body_anim, body_frame)
	_sync_layer(hands_sprite, body_anim, body_frame)
	_sync_layer(head_sprite, body_anim, body_frame)
	_sync_layer(hair_sprite, body_anim, body_frame)
	# Note: weapon_sprite intentionally NOT synced - may have different frame count (oversize)

func _sync_layer(layer: AnimatedSprite2D, target_anim: StringName, target_frame: int) -> void:
	if not layer:
		return
	# Only sync if layer has the same animation
	if layer.sprite_frames and layer.sprite_frames.has_animation(target_anim):
		if layer.animation != target_anim:
			layer.play(target_anim)
		# Clamp frame to layer's actual frame count
		var layer_frame_count = layer.sprite_frames.get_frame_count(target_anim)
		var safe_frame = mini(target_frame, layer_frame_count - 1)
		if layer.frame != safe_frame:
			layer.frame = safe_frame

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
	current_weapon_type = weapon_type  # Store for offset calculations

	# Detect if we're using thrust animation (8 frames) vs slash (6 frames)
	# This affects harvest/chop animation - we need slash-based chop for proper swing
	if slash_tex:
		var tex_width = slash_tex.get_width()
		uses_thrust_animation = tex_width >= 500  # 512px = 8 frames (thrust), 384px = 6 frames (slash)
		# Extract body type from texture path for loading slash.png during harvest
		var res_path = slash_tex.resource_path
		if "/body_" in res_path:
			var start = res_path.find("/body_") + 1
			var end = res_path.find("/", start)
			if end > start:
				body_type_path = res_path.substr(start, end - start)

	# Extract armor paths for harvest animation (need to load slash.png during chop)
	if pants_slash_tex:
		var pants_res_path = pants_slash_tex.resource_path
		pants_armor_path = _extract_armor_path(pants_res_path)
		print("  📦 Pants texture path: %s -> extracted: '%s'" % [pants_res_path, pants_armor_path])
	if shirt_slash_tex:
		var shirt_res_path = shirt_slash_tex.resource_path
		shirt_armor_path = _extract_armor_path(shirt_res_path)
		print("  📦 Shirt texture path: %s -> extracted: '%s'" % [shirt_res_path, shirt_armor_path])
	if boots_slash_tex:
		boots_armor_path = _extract_armor_path(boots_slash_tex.resource_path)
		if boots_armor_path != "":
			print("  📦 Detected boots armor path: %s" % boots_armor_path)
	if arms_slash_tex:
		arms_armor_path = _extract_armor_path(arms_slash_tex.resource_path)
		if arms_armor_path != "":
			print("  📦 Detected arms armor path: %s" % arms_armor_path)
	if hands_slash_tex:
		hands_armor_path = _extract_armor_path(hands_slash_tex.resource_path)
		if hands_armor_path != "":
			print("  📦 Detected hands armor path: %s" % hands_armor_path)
	if head_slash_tex:
		head_armor_path = _extract_armor_path(head_slash_tex.resource_path)
		if head_armor_path != "":
			print("  📦 Detected head armor path: %s" % head_armor_path)

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

	# Create slash/thrust animations (use weapon-specific FPS!)
	# IMPORTANT: Store body frame count to sync all layers
	var body_attack_frames = 6  # Default to slash
	if slash_tex:
		var slash_img = slash_tex.get_image()
		var slash_size = slash_img.get_size()

		# Detect frame count: thrust has 8 frames (512px wide), slash has 6 frames (384px wide)
		body_attack_frames = 8 if slash_size.x >= 500 else 6
		var frame_indices = []
		for i in range(body_attack_frames):
			frame_indices.append(i)

		print("  Creating attack animations (%d frames) from image..." % body_attack_frames)

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(slash_img, "slash_" + dir_name, row, body_attack_frames, frame_indices, slash_fps, false, null, 64)

		print("  Attack animations created")

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shadow_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, shadow_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(base_head_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, base_head_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(boots_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, boots_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(pants_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, pants_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(shirt_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, shirt_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(arms_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, arms_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hands_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, hands_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(hair_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, hair_sprite.sprite_frames, 64)

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
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(head_slash_img, "slash_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, head_sprite.sprite_frames, 64)

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

			# Thrust weapons (staff, spear) use 8 frames, slash weapons use 6 frames
			var thrust_weapons = ["staff", "spear"]
			var num_attack_frames = 8 if weapon_type in thrust_weapons else 6

			# Calculate tile size - spear uses 64px tiles (LPC standard), staff uses oversize 192px
			var slash_tile_size: int
			if weapon_type == "spear":
				slash_tile_size = 64  # Spear uses standard 64px LPC tiles
			else:
				slash_tile_size = int(slash_size.x / num_attack_frames)

			# Build frame indices based on frame count
			var frame_indices = []
			for i in range(num_attack_frames):
				frame_indices.append(i)

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(weapon_slash_img, "slash_" + dir_name, row, num_attack_frames, frame_indices, slash_fps, false, weapon_sprite.sprite_frames, slash_tile_size)

		# Add walk animations if provided
		if weapon_walk_tex:
			var weapon_walk_img = weapon_walk_tex.get_image()
			var walk_size = weapon_walk_img.get_size()

			# LPC walk sprites are always 9 columns x 4 rows with 64x64 tiles
			# Some exports may have extra blank columns (e.g., 832px = 13 cols with 4 blank)
			# Always use 64px tile size for proper alignment
			var walk_tile_size = 64

			# Get weapon-specific walk and idle FPS
			var walk_fps = WeaponAnimationDataFactory.get_walk_fps(weapon_type)
			var idle_fps = WeaponAnimationDataFactory.get_idle_fps(weapon_type)

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

	# Calculate how many frames the source image actually has
	var actual_frame_count = img.get_width() / tile_size

	# ✨ SMOOTH TIMING FIX: For slash animations, adjust frame sequence for better pacing
	# Add middle frames twice to prevent rushing, skip last frame duplication to prevent hang
	var adjusted_indices = frame_indices.duplicate()
	if anim_name.begins_with("slash_") and not loop and frame_indices.size() == 6:
		# Original: [0, 1, 2, 3, 4, 5]
		# Adjusted: [0, 1, 2, 2, 3, 3, 4, 4, 5] - middle frames get more time, smooth acceleration
		adjusted_indices = [0, 1, 2, 2, 3, 3, 4, 4, 5]

	for frame_idx in adjusted_indices:
		# Clamp frame index to actual available frames (prevents reading garbage beyond image)
		var safe_frame_idx = mini(frame_idx, actual_frame_count - 1)
		# Create new image for this frame (using calculated tile_size)
		var frame_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		# Blit the region from the source image
		frame_img.blit_rect(img, Rect2i(safe_frame_idx * tile_size, row * tile_size, tile_size, tile_size), Vector2i(0, 0))
		# Convert to texture
		var frame_texture = ImageTexture.create_from_image(frame_img)
		# Add to sprite frames
		frames.add_frame(anim_name, frame_texture)

func play_lpc_animation(anim_name: String, direction: String):
	"""Play animation with direction - NO FLIPPING!"""
	current_direction = direction

	# Check if this animation has directions
	var anim_key = anim_name + "_" + direction

	# NOTE: Animation speeds are set during setup_lpc_sprite() and should NOT be modified here
	# All layers must use the same FPS that was set during creation (weapon-specific)
	# Previously this code was overriding FPS to 30 which caused desync with armor layers

	if sprite_frames and sprite_frames.has_animation(anim_key):
		play(anim_key)
	elif sprite_frames and sprite_frames.has_animation(anim_name):
		# Animation without directions (like hurt)
		play(anim_name)
	else:
		push_warning("Animation not found: " + anim_key)
		print("  ❌ Available animations: %s" % sprite_frames.get_animation_names())

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

		# Adjust hands z-index: on top of weapon when idle facing east/west
		if anim_name == "idle" and direction in ["east", "west"]:
			hands_sprite.z_index = 10  # Above weapon (z=9)
		else:
			hands_sprite.z_index = 6  # Default position

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
			# Adjust weapon z-index based on direction and animation
			if direction == "north":
				weapon_sprite.z_index = -1  # Behind character when facing up
			elif anim_name == "walk" and current_weapon_type == "spear" and direction in ["east", "west"]:
				weapon_sprite.z_index = -1  # Spear goes under body when walking sideways
			elif anim_name == "idle" and direction in ["east", "west"]:
				weapon_sprite.z_index = -1  # Weapon behind hands when idle facing sideways
			else:
				weapon_sprite.z_index = 9  # On top normally

			# Adjust offset based on animation type and weapon
			# Oversize weapons (192x192 like staff) need offsets, standard weapons (64x64) don't
			if anim_name == "slash":
				var slash_offset = Vector2(0, 0)

				# Only apply offsets for oversize weapons (staff uses 192x192 tiles)
				if current_weapon_type == "staff":
					match direction:
						"east":  # facing right
							slash_offset = Vector2(-10, 5)
						"west":  # facing left
							slash_offset = Vector2(10, 5)
						"north":  # facing up
							slash_offset = Vector2(-10, 0)
						"south":  # facing down
							slash_offset = Vector2(-5, 5)
				# Spear and other standard 64x64 weapons use no offset

				weapon_sprite.offset = slash_offset
				print("  ✅ Weapon playing slash: %s (visible=%s, z=%d, offset=%s, type=%s)" % [anim_key, weapon_sprite.visible, weapon_sprite.z_index, weapon_sprite.offset, current_weapon_type])
			else:
				# Walk/idle animations - weapon sprites should align with character
				weapon_sprite.offset = Vector2(0, 0)
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


# Tool-specific harvest animation support
var harvest_tool_sprite: AnimatedSprite2D = null
var is_harvesting: bool = false

func play_harvest_animation(tool_type: String, direction: String) -> void:
	"""Play harvest animation with specific tool (axe/pickaxe)"""
	print("🪓 Playing harvest animation: tool=%s, direction=%s, uses_thrust=%s" % [tool_type, direction, uses_thrust_animation])
	print("   DEBUG body_type_path: '%s'" % body_type_path)
	is_harvesting = true

	# Convert direction from old format (up/down/left/right) to LPC format (north/south/west/east)
	var lpc_direction = direction
	match direction:
		"up": lpc_direction = "north"
		"down": lpc_direction = "south"
		"left": lpc_direction = "west"
		"right": lpc_direction = "east"

	print("   Converted direction: %s -> %s" % [direction, lpc_direction])

	# Use reversed "chop_" animation for harvesting (swing starts high, ends low)
	var chop_anim = "chop_" + lpc_direction
	var slash_anim = "slash_" + lpc_direction  # Source animation

	# If using thrust animation, create slash-based chop from actual slash.png
	# This gives proper top-to-bottom swing motion instead of reversed thrust
	if uses_thrust_animation and body_type_path != "":
		print("   DEBUG: Using slash-based chop for thrust weapon")
		_ensure_slash_based_chop(sprite_frames, chop_anim, lpc_direction, body_type_path)
		# Also create slash-based chop for character layers (shadow, head, hair)
		_ensure_layer_slash_chop(shadow_sprite, chop_anim, lpc_direction, "shadow")
		_ensure_layer_slash_chop(base_head_sprite, chop_anim, lpc_direction, "head_male" if body_type_path == "body_male" else "head_female")
		_ensure_layer_slash_chop(hair_sprite, chop_anim, lpc_direction, "hair_male" if body_type_path == "body_male" else "hair_female")
		# Armor layers need actual slash.png loaded from armor folders (not reversed thrust)
		_ensure_armor_slash_chop(boots_sprite, chop_anim, lpc_direction, boots_armor_path)
		_ensure_armor_slash_chop(pants_sprite, chop_anim, lpc_direction, pants_armor_path)
		_ensure_armor_slash_chop(shirt_sprite, chop_anim, lpc_direction, shirt_armor_path)
		_ensure_armor_slash_chop(arms_sprite, chop_anim, lpc_direction, arms_armor_path)
		_ensure_armor_slash_chop(hands_sprite, chop_anim, lpc_direction, hands_armor_path)
		_ensure_armor_slash_chop(head_sprite, chop_anim, lpc_direction, head_armor_path)
		# Debug: Print frame counts for all layers
		print("   DEBUG frame counts:")
		print("     body chop: %d frames" % sprite_frames.get_frame_count(chop_anim) if sprite_frames.has_animation(chop_anim) else "     body chop: NOT FOUND")
		if shadow_sprite and shadow_sprite.sprite_frames and shadow_sprite.sprite_frames.has_animation(chop_anim):
			print("     shadow chop: %d frames" % shadow_sprite.sprite_frames.get_frame_count(chop_anim))
		if base_head_sprite and base_head_sprite.sprite_frames and base_head_sprite.sprite_frames.has_animation(chop_anim):
			print("     base_head chop: %d frames" % base_head_sprite.sprite_frames.get_frame_count(chop_anim))
		if boots_sprite and boots_sprite.sprite_frames and boots_sprite.sprite_frames.has_animation(chop_anim):
			print("     boots chop: %d frames" % boots_sprite.sprite_frames.get_frame_count(chop_anim))
		if pants_sprite and pants_sprite.sprite_frames and pants_sprite.sprite_frames.has_animation(chop_anim):
			print("     pants chop: %d frames" % pants_sprite.sprite_frames.get_frame_count(chop_anim))
		if shirt_sprite and shirt_sprite.sprite_frames and shirt_sprite.sprite_frames.has_animation(chop_anim):
			print("     shirt chop: %d frames" % shirt_sprite.sprite_frames.get_frame_count(chop_anim))
		if arms_sprite and arms_sprite.sprite_frames and arms_sprite.sprite_frames.has_animation(chop_anim):
			print("     arms chop: %d frames" % arms_sprite.sprite_frames.get_frame_count(chop_anim))
		if hands_sprite and hands_sprite.sprite_frames and hands_sprite.sprite_frames.has_animation(chop_anim):
			print("     hands chop: %d frames" % hands_sprite.sprite_frames.get_frame_count(chop_anim))
		if hair_sprite and hair_sprite.sprite_frames and hair_sprite.sprite_frames.has_animation(chop_anim):
			print("     hair chop: %d frames" % hair_sprite.sprite_frames.get_frame_count(chop_anim))
		if head_sprite and head_sprite.sprite_frames and head_sprite.sprite_frames.has_animation(chop_anim):
			print("     head_armor chop: %d frames" % head_sprite.sprite_frames.get_frame_count(chop_anim))
	else:
		# Create chop animation if it doesn't exist (reversed slash)
		_ensure_chop_animation(sprite_frames, slash_anim, chop_anim)
		# Animate ALL clothing layers with chop animation
		_play_layer_chop(base_head_sprite, slash_anim, chop_anim)
		_play_layer_chop(boots_sprite, slash_anim, chop_anim)
		_play_layer_chop(pants_sprite, slash_anim, chop_anim)
		_play_layer_chop(shirt_sprite, slash_anim, chop_anim)
		_play_layer_chop(arms_sprite, slash_anim, chop_anim)
		_play_layer_chop(hands_sprite, slash_anim, chop_anim)
		_play_layer_chop(hair_sprite, slash_anim, chop_anim)
		_play_layer_chop(head_sprite, slash_anim, chop_anim)
		_play_layer_chop(shadow_sprite, slash_anim, chop_anim)

	# RESTART chop animation on the main body for fresh swing
	if sprite_frames.has_animation(chop_anim):
		stop()
		frame = 0
		play(chop_anim)
		print("   Playing body chop: %s" % chop_anim)

	# Play chop on layers that have it (created above)
	if uses_thrust_animation:
		_play_layer_if_has_anim(shadow_sprite, chop_anim)
		_play_layer_if_has_anim(base_head_sprite, chop_anim)
		_play_layer_if_has_anim(hair_sprite, chop_anim)
		# Also play chop on armor layers
		_play_layer_if_has_anim(boots_sprite, chop_anim)
		_play_layer_if_has_anim(pants_sprite, chop_anim)
		_play_layer_if_has_anim(shirt_sprite, chop_anim)
		_play_layer_if_has_anim(arms_sprite, chop_anim)
		_play_layer_if_has_anim(hands_sprite, chop_anim)
		_play_layer_if_has_anim(head_sprite, chop_anim)

	# Play the tool sprite overlay (axe/pickaxe)
	_play_harvest_tool(tool_type, lpc_direction)

	# Debug: Print what each layer is actually playing
	print("   DEBUG: Layer states after chop setup:")
	print("     ALL CHILDREN of SimpleLPCSprite:")
	for child in get_children():
		if child is AnimatedSprite2D:
			print("       - %s: anim=%s, visible=%s, z=%d" % [child.name, child.animation, child.visible, child.z_index])
		else:
			print("       - %s: type=%s, visible=%s" % [child.name, child.get_class(), child.visible if "visible" in child else "N/A"])
	print("     body: anim=%s, frame=%d, visible=%s, z=%d" % [animation, frame, visible, z_index])
	if shadow_sprite:
		print("     shadow: anim=%s, frame=%d, visible=%s, z=%d" % [shadow_sprite.animation, shadow_sprite.frame, shadow_sprite.visible, shadow_sprite.z_index])
	if base_head_sprite:
		print("     base_head: anim=%s, frame=%d, visible=%s, z=%d" % [base_head_sprite.animation, base_head_sprite.frame, base_head_sprite.visible, base_head_sprite.z_index])
	if boots_sprite:
		print("     boots: anim=%s, frame=%d, visible=%s, z=%d" % [boots_sprite.animation, boots_sprite.frame, boots_sprite.visible, boots_sprite.z_index])
	if pants_sprite:
		print("     pants: anim=%s, frame=%d, visible=%s, z=%d" % [pants_sprite.animation, pants_sprite.frame, pants_sprite.visible, pants_sprite.z_index])
	if shirt_sprite:
		print("     shirt: anim=%s, frame=%d, visible=%s, z=%d" % [shirt_sprite.animation, shirt_sprite.frame, shirt_sprite.visible, shirt_sprite.z_index])
	if arms_sprite:
		print("     arms: anim=%s, frame=%d, visible=%s, z=%d" % [arms_sprite.animation, arms_sprite.frame, arms_sprite.visible, arms_sprite.z_index])
	if hands_sprite:
		print("     hands: anim=%s, frame=%d, visible=%s, z=%d" % [hands_sprite.animation, hands_sprite.frame, hands_sprite.visible, hands_sprite.z_index])
	if hair_sprite:
		print("     hair: anim=%s, frame=%d, visible=%s, z=%d" % [hair_sprite.animation, hair_sprite.frame, hair_sprite.visible, hair_sprite.z_index])
	if head_sprite:
		print("     head_armor: anim=%s, frame=%d, visible=%s, z=%d" % [head_sprite.animation, head_sprite.frame, head_sprite.visible, head_sprite.z_index])
	if weapon_sprite:
		print("     weapon: visible=%s, z=%d" % [weapon_sprite.visible, weapon_sprite.z_index])

func _extract_armor_path(resource_path: String) -> String:
	"""Extract armor path from full texture path"""
	# Handle standard armor paths: res://assets/equipment/armor/legs/green_pants/standard/thrust.png -> armor:legs/green_pants
	if "/armor/" in resource_path:
		var start = resource_path.find("/armor/") + 7  # Skip "/armor/"
		var end = resource_path.find("/standard/", start)
		if end > start:
			return "armor:" + resource_path.substr(start, end - start)

	# Handle starter clothes paths: res://assets/characters/pants/green_pants_thrust.png -> chars:pants/green_pants
	if "/characters/" in resource_path:
		# Extract folder and item name from path like: /characters/pants/green_pants_thrust.png
		var start = resource_path.find("/characters/") + 12  # Skip "/characters/"
		var end = resource_path.rfind("/")  # Find last /
		if end > start:
			var folder = resource_path.substr(start, end - start)  # e.g., "pants"
			# Extract item name from filename (before _walk/_slash/_thrust suffix)
			var filename = resource_path.get_file().get_basename()  # e.g., "green_pants_thrust"
			for suffix in ["_walk", "_slash", "_thrust", "_hurt"]:
				if filename.ends_with(suffix):
					filename = filename.substr(0, filename.length() - suffix.length())
					break
			return "chars:" + folder + "/" + filename  # e.g., "chars:pants/green_pants"
	return ""

func _ensure_chop_animation(frames: SpriteFrames, slash_anim: String, chop_anim: String) -> void:
	"""Create reversed chop animation from slash animation if it doesn't exist"""
	if frames.has_animation(chop_anim):
		return
	if not frames.has_animation(slash_anim):
		return

	# Create new animation with reversed frames
	frames.add_animation(chop_anim)
	frames.set_animation_loop(chop_anim, false)
	frames.set_animation_speed(chop_anim, frames.get_animation_speed(slash_anim))

	# Copy frames in reverse order
	var frame_count = frames.get_frame_count(slash_anim)
	for i in range(frame_count - 1, -1, -1):
		var tex = frames.get_frame_texture(slash_anim, i)
		var duration = frames.get_frame_duration(slash_anim, i)
		frames.add_frame(chop_anim, tex, duration)

func _play_layer_chop(layer: AnimatedSprite2D, slash_anim: String, chop_anim: String) -> void:
	"""Play chop animation on a layer, creating it if needed"""
	if not layer or not layer.sprite_frames:
		return
	_ensure_chop_animation(layer.sprite_frames, slash_anim, chop_anim)
	if layer.sprite_frames.has_animation(chop_anim):
		layer.stop()
		layer.frame = 0
		layer.play(chop_anim)

func _ensure_slash_based_chop(frames: SpriteFrames, chop_anim: String, lpc_direction: String, asset_folder: String) -> void:
	"""Create chop animation from slash.png (not thrust) for proper top-to-bottom swing"""
	if frames.has_animation(chop_anim):
		return

	var slash_path = "res://assets/characters/" + asset_folder + "/standard/slash.png"
	if not ResourceLoader.exists(slash_path):
		print("   ⚠️ Slash texture not found: %s" % slash_path)
		return

	var slash_tex = load(slash_path)
	var slash_img = slash_tex.get_image()
	var row = DIRECTION_ROWS[lpc_direction]

	print("   🪓 Creating slash-based chop from: %s" % slash_path)

	# Slash has 6 frames, create reversed animation for top-to-bottom swing
	frames.add_animation(chop_anim)
	frames.set_animation_loop(chop_anim, false)
	frames.set_animation_speed(chop_anim, 15.0)

	var tile_size = 64
	for frame_idx in [5, 4, 3, 2, 1, 0]:
		var frame_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(slash_img, Rect2i(frame_idx * tile_size, row * tile_size, tile_size, tile_size), Vector2i(0, 0))
		var frame_texture = ImageTexture.create_from_image(frame_img)
		frames.add_frame(chop_anim, frame_texture)

func _ensure_layer_slash_chop(layer: AnimatedSprite2D, chop_anim: String, lpc_direction: String, asset_folder: String) -> void:
	"""Create slash-based chop animation for a layer sprite (characters folder)"""
	if not layer or not layer.sprite_frames:
		return
	if layer.sprite_frames.has_animation(chop_anim):
		return

	var slash_path = "res://assets/characters/" + asset_folder + "/standard/slash.png"
	if not ResourceLoader.exists(slash_path):
		# No slash.png for this layer, skip
		return

	var slash_tex = load(slash_path)
	var slash_img = slash_tex.get_image()
	var row = DIRECTION_ROWS[lpc_direction]

	# Create reversed slash animation
	layer.sprite_frames.add_animation(chop_anim)
	layer.sprite_frames.set_animation_loop(chop_anim, false)
	layer.sprite_frames.set_animation_speed(chop_anim, 15.0)

	var tile_size = 64
	for frame_idx in [5, 4, 3, 2, 1, 0]:
		var frame_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(slash_img, Rect2i(frame_idx * tile_size, row * tile_size, tile_size, tile_size), Vector2i(0, 0))
		var frame_texture = ImageTexture.create_from_image(frame_img)
		layer.sprite_frames.add_frame(chop_anim, frame_texture)

func _ensure_armor_slash_chop(layer: AnimatedSprite2D, chop_anim: String, lpc_direction: String, armor_path: String) -> void:
	"""Create slash-based chop animation for an armor layer (loads from armor or characters folder)"""
	if not layer or not layer.sprite_frames:
		return
	if layer.sprite_frames.has_animation(chop_anim):
		return
	if armor_path == "":
		return

	# Build path based on source type (armor: or chars:)
	var slash_path: String
	if armor_path.begins_with("armor:"):
		# Standard armor: res://assets/equipment/armor/legs/green_pants/standard/slash.png
		var sub_path = armor_path.substr(6)  # Remove "armor:" prefix
		slash_path = "res://assets/equipment/armor/" + sub_path + "/standard/slash.png"
	elif armor_path.begins_with("chars:"):
		# Starter clothes: res://assets/characters/pants/green_pants_slash.png
		var sub_path = armor_path.substr(6)  # Remove "chars:" prefix
		# sub_path is like "pants/green_pants" -> need "pants/green_pants_slash.png"
		var parts = sub_path.split("/")
		if parts.size() >= 2:
			slash_path = "res://assets/characters/" + parts[0] + "/" + parts[1] + "_slash.png"
		else:
			print("   ⚠️ Invalid chars path format: %s" % armor_path)
			return
	else:
		# Legacy format without prefix - assume armor folder
		slash_path = "res://assets/equipment/armor/" + armor_path + "/standard/slash.png"

	if not ResourceLoader.exists(slash_path):
		print("   ⚠️ Slash texture not found: %s" % slash_path)
		return

	var slash_tex = load(slash_path)
	var slash_img = slash_tex.get_image()
	var row = DIRECTION_ROWS[lpc_direction]

	# Check if this is actually 6-frame slash (384px) or 8-frame thrust (512px)
	var tex_width = slash_img.get_width()
	if tex_width >= 500:
		# This is thrust.png, not slash.png - skip (we want actual 6-frame slash)
		print("   ⚠️ Slash texture is thrust format (8 frames), skipping: %s" % slash_path)
		return

	print("   ✅ Loading slash texture: %s (6 frames)" % slash_path)

	# Create reversed slash animation
	layer.sprite_frames.add_animation(chop_anim)
	layer.sprite_frames.set_animation_loop(chop_anim, false)
	layer.sprite_frames.set_animation_speed(chop_anim, 15.0)

	var tile_size = 64
	for frame_idx in [5, 4, 3, 2, 1, 0]:
		var frame_img = Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(slash_img, Rect2i(frame_idx * tile_size, row * tile_size, tile_size, tile_size), Vector2i(0, 0))
		var frame_texture = ImageTexture.create_from_image(frame_img)
		layer.sprite_frames.add_frame(chop_anim, frame_texture)

func _play_layer_if_has_anim(layer: AnimatedSprite2D, anim_name: String) -> void:
	"""Play animation on layer if it exists"""
	if not layer or not layer.sprite_frames:
		return
	if layer.sprite_frames.has_animation(anim_name):
		layer.stop()
		layer.frame = 0
		layer.play(anim_name)

func _play_harvest_tool(tool_type: String, lpc_direction: String) -> void:
	"""Play the tool sprite animation (axe/pickaxe overlay)"""
	# Hide regular weapon if present
	if weapon_sprite:
		weapon_sprite.visible = false
		print("   Hiding regular weapon")

	# Get or create tool sprite
	if not harvest_tool_sprite:
		harvest_tool_sprite = get_node_or_null("HarvestTool")

	# Create if it doesn't exist (similar structure to weapon_sprite)
	if not harvest_tool_sprite:
		harvest_tool_sprite = AnimatedSprite2D.new()
		harvest_tool_sprite.name = "HarvestTool"
		harvest_tool_sprite.centered = true
		harvest_tool_sprite.z_index = 20  # Put it way above everything else
		harvest_tool_sprite.position = Vector2(0, 0)  # Center it on the player
		harvest_tool_sprite.modulate = Color(1, 1, 1, 1)  # Full opacity
		harvest_tool_sprite.sprite_frames = SpriteFrames.new()

		# Add as child of SimpleLPCSprite (same as weapon)
		add_child(harvest_tool_sprite)

		# Connect animation_finished to hide tool when swing completes
		harvest_tool_sprite.animation_finished.connect(_on_harvest_tool_animation_finished)
		print("   Created harvest tool sprite as child of SimpleLPCSprite")

	# Use the ACTUAL tool sprites from the custom/slash_128 folder
	var tool_path: String
	if tool_type == "axe":
		tool_path = "res://assets/equipment/tools/axe/custom/slash_128/140 tool_smash_.png"
	else:  # pickaxe
		tool_path = "res://assets/equipment/tools/pickaxe/custom/slash_128/140 tool_smash_.png"

	print("   Loading tool animation from: %s" % tool_path)

	if not ResourceLoader.exists(tool_path):
		print("   ⚠️ Tool sprite not found at: %s" % tool_path)
		# Fallback to using weapon sprites as placeholder
		if tool_type == "axe":
			tool_path = "res://assets/equipment/weapons/mace/slash.png"
		else:
			tool_path = "res://assets/equipment/weapons/sword/slash.png"
		print("   Falling back to weapon sprite: %s" % tool_path)

	var tool_tex = load(tool_path)
	var tool_img = tool_tex.get_image()
	print("   Loaded tool texture: %s" % tool_img.get_size())

	# 768x512 sheet = 6 columns x 4 rows at 128x128 per frame
	var num_frames = 6
	var tile_size = 128
	var row = DIRECTION_ROWS[lpc_direction]

	# Create animation using same method as weapons
	# Reverse frame order for chopping motion (start high, swing down)
	var anim_name = tool_type + "_slash_" + lpc_direction
	if not harvest_tool_sprite.sprite_frames.has_animation(anim_name):
		create_animation_from_image(tool_img, anim_name, row, num_frames, [5, 4, 3, 2, 1, 0], 10.0, false, harvest_tool_sprite.sprite_frames, tile_size)
		print("   Created tool animation: %s (row %d)" % [anim_name, row])

	# Hide regular weapon
	if weapon_sprite:
		weapon_sprite.visible = false

	# Play tool animation
	if harvest_tool_sprite.sprite_frames.has_animation(anim_name):
		harvest_tool_sprite.stop()
		harvest_tool_sprite.frame = 0
		harvest_tool_sprite.visible = true
		harvest_tool_sprite.play(anim_name)

		# Z-index: behind player when facing north, in front otherwise
		harvest_tool_sprite.z_index = -1 if lpc_direction == "north" else 20
		print("   Playing tool: %s" % anim_name)

func _on_harvest_tool_animation_finished() -> void:
	"""Called when harvest tool swing animation completes - hide tool until next swing"""
	if harvest_tool_sprite:
		harvest_tool_sprite.visible = false

	# Safety: If no longer harvesting, restore weapon visibility
	if not is_harvesting and weapon_sprite:
		weapon_sprite.visible = true

func stop_harvest_animation() -> void:
	"""Stop harvest animation and hide tool"""
	is_harvesting = false

	# Make sure main body sprite is visible again
	self.visible = true

	if harvest_tool_sprite:
		harvest_tool_sprite.stop()
		harvest_tool_sprite.visible = false

	# Restore regular weapon visibility if we have one
	if weapon_sprite:
		weapon_sprite.visible = true

func is_harvest_active() -> bool:
	"""Check if currently harvesting (used by Player to prevent animation interruption)"""
	return is_harvesting

func is_lpc_animation_playing() -> bool:
	"""Check if animation is currently playing"""
	return is_playing()
