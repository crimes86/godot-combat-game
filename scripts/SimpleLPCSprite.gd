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

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_SPRITE_SETUP: bool = false  # Debug sprite/animation setup
const DEBUG_DAGGER: bool = false  # Focused dagger/psi-blade logging

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

func _dagger_debug(msg: String) -> void:
	if DEBUG_DAGGER:
		print("[DAGGER DEBUG] ", msg)

static func get_attack_frame_indices(num_frames: int) -> Array:
	var indices = []
	for i in range(num_frames):
		indices.append(i)
	return indices

# Shadow layer (below body)
var shadow_sprite: AnimatedSprite2D = null

# Cape layer (behind body when facing south/east/west, on top when facing north)
var cape_sprite: AnimatedSprite2D = null

# Armor layers (optional) - between body and weapon
# z-index order: shadow(-10) -> cape(-5 or 10*) -> body(0) -> base_head(1) -> boots(2) -> pants(3) -> shirt(4) -> arms(5) -> hands(6) -> hair(7) -> head_armor(8) -> weapon(9/-1)
# *cape z-index is -5 (behind) for south/east/west directions, 10 (on top) for north direction
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
var current_weapon_name: String = ""  # Track specific weapon name (e.g., "saw_cleaver")

# Multi-slash weapon support - cycle through slash variants (slash, slash2, slash3)
var weapon_slash_variants: Array[String] = []  # Available slash animation names
var current_slash_index: int = 0  # Current index for cycling

# Gun pose support - swap body to Skorpio pose when walking with gun
var is_gun_weapon: bool = false  # True if current weapon is a gun type
var has_gun_walk_animations: bool = false  # True if gun_walk_* animations exist
var gun_body_sprite: AnimatedSprite2D = null  # Separate layer for Skorpio gun pose body

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

	# If using gun pose, sync clothing to gun_body_sprite instead of main body
	if gun_body_sprite and gun_body_sprite.visible:
		body_frame = gun_body_sprite.frame
		body_anim = gun_body_sprite.animation

	# Check if we're in a shoot animation (for bow weapons)
	var is_shoot_anim = String(body_anim).begins_with("shoot_")

	_sync_layer(shadow_sprite, body_anim, body_frame)
	_sync_layer(cape_sprite, body_anim, body_frame)
	# Don't sync base_head during shoot - keep it static on idle
	if not is_shoot_anim:
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
	is_female: bool = false,
	weapon_slash2_tex: Texture2D = null,
	weapon_slash3_tex: Texture2D = null
):
	"""Setup LPC sprite with layered body, armor, and weapon textures"""
	if DEBUG_SPRITE_SETUP:
		print("[LPCSprite] setup_lpc_sprite() called")
		print("  walk_texture: ", walk_tex, " size: ", walk_tex.get_size() if walk_tex else "null")
		print("  slash_texture: ", slash_tex, " size: ", slash_tex.get_size() if slash_tex else "null")
		print("  weapon_slash_tex: ", weapon_slash_tex, " path: ", weapon_slash_tex.resource_path if weapon_slash_tex else "null")
		print("  weapon_walk_tex: ", weapon_walk_tex, " path: ", weapon_walk_tex.resource_path if weapon_walk_tex else "null")

	sprite_frames = SpriteFrames.new()
	current_weapon_type = weapon_type  # Store for offset calculations

	# Check if weapon uses shoot animation (bow/crossbow)
	var bow_weapon_types = ["bow", "crossbow"]
	var uses_shoot_animation = weapon_type in bow_weapon_types

	# Extract weapon name from path (e.g., "saw_cleaver" from ".../weapons/saw_cleaver/walk.png")
	current_weapon_name = ""
	if weapon_walk_tex:
		var weapon_path = weapon_walk_tex.resource_path
		# Path format: res://assets/equipment/[forged/]weapons/weapon_name/walk.png
		var parts = weapon_path.split("/")
		if parts.size() >= 2:
			current_weapon_name = parts[parts.size() - 2]  # Second to last = weapon folder name

	# Reset multi-slash tracking
	weapon_slash_variants.clear()
	current_slash_index = 0

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
		pants_armor_path = _extract_armor_path(pants_slash_tex.resource_path)
	if shirt_slash_tex:
		shirt_armor_path = _extract_armor_path(shirt_slash_tex.resource_path)
	if boots_slash_tex:
		boots_armor_path = _extract_armor_path(boots_slash_tex.resource_path)
	if arms_slash_tex:
		arms_armor_path = _extract_armor_path(arms_slash_tex.resource_path)
	if hands_slash_tex:
		hands_armor_path = _extract_armor_path(hands_slash_tex.resource_path)
	if head_slash_tex:
		head_armor_path = _extract_armor_path(head_slash_tex.resource_path)

	# Get weapon-specific slash FPS for ALL body parts to sync animations
	var slash_fps = WeaponAnimationDataFactory.get_slash_fps(weapon_type)

	if weapon_type == "dagger":
		var walk_size_dbg = walk_tex.get_size() if walk_tex else Vector2.ZERO
		var slash_size_dbg = slash_tex.get_size() if slash_tex else Vector2.ZERO
		_dagger_debug("setup weapon=%s type=%s walk_size=%s slash_size=%s slash_fps=%.2f" % [current_weapon_name, weapon_type, walk_size_dbg, slash_size_dbg, slash_fps])

	# Create walk animations using Image.blit_rect() like skeletons do
	if walk_tex:
		var walk_img = walk_tex.get_image()
		# Walk animations - 4 rows (north/west/south/east), frames 1-8
		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, null, 64)
			create_animation_from_image(walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, null, 64)

	# Create slash/thrust/shoot animations (use weapon-specific FPS!)
	# IMPORTANT: Store body frame count to sync all layers
	# NOTE: We always use "slash_" prefix for animation names (except guns/bows which use "shoot_")
	# This ensures body and weapon animations match, regardless of actual frame count
	var body_attack_frames = 6  # Default to slash
	var attack_anim_prefix = "slash"  # Default - use "slash_" for all melee weapons

	# Guns and bows use "shoot_" animation prefix
	var shoot_weapon_types = ["bow", "crossbow", "gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"]
	if weapon_type in shoot_weapon_types:
		attack_anim_prefix = "shoot"

	if slash_tex:
		var slash_img = slash_tex.get_image()
		var slash_size = slash_img.get_size()

		# Detect frame count from texture width, but keep using slash/shoot prefix
		if slash_size.x >= 800:  # 832px = 13 frames (shoot)
			body_attack_frames = 13
		elif slash_size.x >= 500:  # 512px = 8 frames (thrust uses same motion as slash)
			body_attack_frames = 8
		else:  # 384px = 6 frames (slash)
			body_attack_frames = 6

		var frame_indices = []
		for i in range(body_attack_frames):
			frame_indices.append(i)

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			# Use attack_anim_prefix for animation name (slash_, thrust_, or shoot_)
			create_animation_from_image(slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, frame_indices, slash_fps, false, null, 64)

	# Create hurt animation (single direction - south/row 2)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()
		create_animation_from_image(hurt_img, "hurt", 2, 6, [0, 1, 2, 3, 4, 5], 10.0, false, null, 64)

	# Setup shadow layer (z=-10 - below everything)
	if shadow_walk_tex or shadow_slash_tex:
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
				create_animation_from_image(shadow_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, shadow_sprite.sprite_frames, 64)

		add_child(shadow_sprite)
		shadow_sprite.visible = true
		shadow_sprite.play("idle_south")

	# Setup base head layer (z=1 - for female characters with separate head)
	if base_head_walk_tex or base_head_slash_tex:
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
			var base_head_width = base_head_slash_img.get_width()
			# Detect if using walk texture for attack (576px = 9 frames, used when no shoot.png exists)
			# In this case, use frame 0 (idle position) for all attack frames to create static head
			var is_walk_texture = (base_head_width == 576)
			var head_frame_indices = []
			if is_walk_texture:
				# Static head: use frame 0 for all attack frames
				for i in range(body_attack_frames):
					head_frame_indices.append(0)
			else:
				head_frame_indices = get_attack_frame_indices(body_attack_frames)
			# Use body_attack_frames to sync with body animation
			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(base_head_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, head_frame_indices, slash_fps, false, base_head_sprite.sprite_frames, 64)

		add_child(base_head_sprite)
		base_head_sprite.visible = true
		base_head_sprite.play("idle_south")

	# Setup boots layer (z=2 - above base head)
	if boots_walk_tex or boots_slash_tex:
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
				create_animation_from_image(boots_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, boots_sprite.sprite_frames, 64)

		add_child(boots_sprite)
		boots_sprite.visible = true
		boots_sprite.play("idle_south")

	# Setup pants layer (z=3 - above boots)
	if pants_walk_tex or pants_slash_tex:
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
				create_animation_from_image(pants_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, pants_sprite.sprite_frames, 64)

		add_child(pants_sprite)
		pants_sprite.visible = true
		pants_sprite.play("idle_south")

	# Setup shirt layer (z=4 - above pants)
	if shirt_walk_tex or shirt_slash_tex:
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
				create_animation_from_image(shirt_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, shirt_sprite.sprite_frames, 64)
			if DEBUG_SPRITE_SETUP:
				print("[SimpleLPCSprite] Created shirt %s animations (prefix: %s, frames: %d)" % [attack_anim_prefix, attack_anim_prefix, body_attack_frames])

		add_child(shirt_sprite)
		shirt_sprite.visible = true
		shirt_sprite.play("idle_south")

	# Setup arms layer (z=5 - above shirt)
	if arms_walk_tex or arms_slash_tex:
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
				create_animation_from_image(arms_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, arms_sprite.sprite_frames, 64)

		add_child(arms_sprite)
		arms_sprite.visible = true
		arms_sprite.play("idle_south")

	# Setup hands layer (z=6 - above arms)
	if hands_walk_tex or hands_slash_tex:
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
				create_animation_from_image(hands_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, hands_sprite.sprite_frames, 64)

		add_child(hands_sprite)
		hands_sprite.visible = true
		hands_sprite.play("idle_south")

	# Setup hair layer (z=7 - above hands, UNDER head armor)
	if hair_walk_tex or hair_slash_tex:
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
				create_animation_from_image(hair_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, hair_sprite.sprite_frames, 64)

		add_child(hair_sprite)
		hair_sprite.visible = true
		hair_sprite.play("idle_south")

	# Setup head layer (z=8 - above hair, for head armor/helmets)
	if head_walk_tex or head_slash_tex:
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
				create_animation_from_image(head_slash_img, attack_anim_prefix + "_" + dir_name, row, body_attack_frames, get_attack_frame_indices(body_attack_frames), slash_fps, false, head_sprite.sprite_frames, 64)
			if DEBUG_SPRITE_SETUP:
				print("[SimpleLPCSprite] Created head %s animations (prefix: %s, frames: %d)" % [attack_anim_prefix, attack_anim_prefix, body_attack_frames])

		add_child(head_sprite)
		head_sprite.visible = true
		head_sprite.play("idle_south")

	# Setup weapon layer if provided
	if weapon_slash_tex or weapon_walk_tex:
		weapon_sprite = AnimatedSprite2D.new()
		weapon_sprite.name = "WeaponLayer"
		weapon_sprite.centered = true
		weapon_sprite.z_index = 9  # Draw weapon on top (above head armor z=8)
		weapon_sprite.sprite_frames = SpriteFrames.new()
		# Apply per-weapon tinting (keep most weapons default white)
		if current_weapon_name == "zeratul_warp_blade":
			weapon_sprite.modulate = Color(1.08, 0.7, 1.0, 1.0)  # light magenta/pink shift
		else:
			weapon_sprite.modulate = Color(1, 1, 1, 1)
		# Don't set a static offset here - we'll adjust it per animation type

		# Add attack animations if provided (slash for melee, shoot for guns/bows)
		if weapon_slash_tex:
			var weapon_slash_img = weapon_slash_tex.get_image()
			var slash_size = weapon_slash_img.get_size()

			# Gun weapons use shoot animation (9 frames like walk), others use slash/thrust
			var gun_weapon_types = ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"]
			var is_gun = weapon_type in gun_weapon_types

			if is_gun:
				# Gun shoot animation: 9 frames at 64px, fast playback for snappy muzzle flash
				var shoot_tile_size = 64
				var num_shoot_frames = 9
				var shoot_fps = 20.0  # Fast for muzzle flash effect

				var frame_indices = []
				for i in range(num_shoot_frames):
					frame_indices.append(i)

				for dir_name in DIRECTION_ROWS.keys():
					var row = DIRECTION_ROWS[dir_name]
					create_animation_from_image(weapon_slash_img, "shoot_" + dir_name, row, num_shoot_frames, frame_indices, shoot_fps, false, weapon_sprite.sprite_frames, shoot_tile_size)

				# Track shoot variant for get_next_attack_anim()
				weapon_slash_variants.append("shoot")
			elif uses_shoot_animation:
				# Bow shoot animation: 13 frames at 64px
				var shoot_tile_size = 64
				var num_shoot_frames = 13
				var shoot_fps = 15.0  # Smooth draw and release

				var frame_indices = []
				for i in range(num_shoot_frames):
					frame_indices.append(i)

				for dir_name in DIRECTION_ROWS.keys():
					var row = DIRECTION_ROWS[dir_name]
					create_animation_from_image(weapon_slash_img, "shoot_" + dir_name, row, num_shoot_frames, frame_indices, shoot_fps, false, weapon_sprite.sprite_frames, shoot_tile_size)

				# Track shoot variant for get_next_attack_anim()
				weapon_slash_variants.append("shoot")
			else:
				# Thrust weapons (staff, spear, trident) use 8 frames, slash weapons use 6 frames
				# BUT we always use "slash_" animation prefix to match body animations
				var thrust_weapon_types = ["staff", "spear", "trident"]
				var num_attack_frames = 8 if weapon_type in thrust_weapon_types else 6

				# Calculate tile size dynamically from sprite dimensions
				var slash_tile_size = int(slash_size.x / num_attack_frames)

				if weapon_type == "dagger":
					_dagger_debug("build slash frames weapon=%s size=%s frames=%d tile=%d fps=%.2f" % [current_weapon_name, slash_size, num_attack_frames, slash_tile_size, slash_fps])

				# Build frame indices based on frame count
				var frame_indices = []
				for i in range(num_attack_frames):
					frame_indices.append(i)

				for dir_name in DIRECTION_ROWS.keys():
					var row = DIRECTION_ROWS[dir_name]
					# Always use "slash_" prefix for melee weapons (matches body animation naming)
					create_animation_from_image(weapon_slash_img, "slash_" + dir_name, row, num_attack_frames, frame_indices, slash_fps, false, weapon_sprite.sprite_frames, slash_tile_size)

				# Track slash variant (always "slash" for melee)
				weapon_slash_variants.append("slash")

				# Create slash2 variant if provided (must be inside else block for num_attack_frames scope)
				if weapon_slash2_tex:
					var slash2_img = weapon_slash2_tex.get_image()
					var slash2_size = slash2_img.get_size()
					var slash2_tile_size = int(slash2_size.x / num_attack_frames)
					for dir_name in DIRECTION_ROWS.keys():
						var row = DIRECTION_ROWS[dir_name]
						create_animation_from_image(slash2_img, "slash2_" + dir_name, row, num_attack_frames, frame_indices, slash_fps, false, weapon_sprite.sprite_frames, slash2_tile_size)
					weapon_slash_variants.append("slash2")

				# Create slash3 variant if provided
				if weapon_slash3_tex:
					var slash3_img = weapon_slash3_tex.get_image()
					var slash3_size = slash3_img.get_size()
					var slash3_tile_size = int(slash3_size.x / num_attack_frames)
					for dir_name in DIRECTION_ROWS.keys():
						var row = DIRECTION_ROWS[dir_name]
						create_animation_from_image(slash3_img, "slash3_" + dir_name, row, num_attack_frames, frame_indices, slash_fps, false, weapon_sprite.sprite_frames, slash3_tile_size)
					weapon_slash_variants.append("slash3")

		# Add walk animations if provided
		if weapon_walk_tex:
			var weapon_walk_img = weapon_walk_tex.get_image()
			var walk_size = weapon_walk_img.get_size()

			# LPC walk sprites are 9 columns x 4 rows
			# Calculate tile size dynamically (64px standard, 128px for oversize weapons)
			var walk_tile_size = int(walk_size.x / 9)
			# Zeratul warp blade uses a 13-column (832px wide) sheet; force 64px tiles to avoid scrolling
			if current_weapon_name == "zeratul_warp_blade":
				walk_tile_size = 64

			# Get weapon-specific walk and idle FPS
			var walk_fps = WeaponAnimationDataFactory.get_walk_fps(weapon_type)
			var idle_fps = WeaponAnimationDataFactory.get_idle_fps(weapon_type)

			if weapon_type == "dagger":
				_dagger_debug("build walk frames weapon=%s size=%s tile=%d walk_fps=%.2f idle_fps=%.2f" % [current_weapon_name, walk_size, walk_tile_size, walk_fps, idle_fps])

			for dir_name in DIRECTION_ROWS.keys():
				var row = DIRECTION_ROWS[dir_name]
				create_animation_from_image(weapon_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], walk_fps, true, weapon_sprite.sprite_frames, walk_tile_size)
				create_animation_from_image(weapon_walk_img, "idle_" + dir_name, row, 1, [0], idle_fps, true, weapon_sprite.sprite_frames, walk_tile_size)

		add_child(weapon_sprite)

		# Show weapon if we have walk animations, hide otherwise
		if weapon_walk_tex:
			weapon_sprite.visible = true
			weapon_sprite.play("idle_south")  # Start with idle
		else:
			weapon_sprite.visible = false
			weapon_sprite.stop()

	# Start with idle_south
	if sprite_frames.has_animation("idle_south"):
		play("idle_south")
	else:
		push_error("SimpleLPCSprite: idle_south animation not found!")

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

func setup_gun_walk_animations(gun_body_walk_tex: Texture2D, gun_body_shoot_tex: Texture2D = null) -> void:
	"""Setup gun walk and shoot animations using Skorpio body pose (arms extended for gun)
	Creates a SEPARATE sprite layer for the Skorpio body that shows during gun_walk/shoot.
	The normal LPC body is hidden when this layer is visible."""
	if not gun_body_walk_tex:
		return

	is_gun_weapon = true
	has_gun_walk_animations = true

	# Create a separate sprite layer for the gun pose body (like other clothing layers)
	gun_body_sprite = AnimatedSprite2D.new()
	gun_body_sprite.name = "GunBodyLayer"
	gun_body_sprite.centered = true
	gun_body_sprite.z_index = 0  # Same z as body - will replace it visually
	gun_body_sprite.sprite_frames = SpriteFrames.new()
	gun_body_sprite.visible = false  # Start hidden, show during gun_walk

	var gun_walk_img = gun_body_walk_tex.get_image()

	# Create walk animations on the gun body layer
	for dir_name in DIRECTION_ROWS.keys():
		var row = DIRECTION_ROWS[dir_name]
		create_animation_from_image(gun_walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, gun_body_sprite.sprite_frames, 64)
		# Also create idle (frame 0) for when standing still with gun - use regular body instead
		create_animation_from_image(gun_walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, gun_body_sprite.sprite_frames, 64)

	# Create shoot animations if texture provided (13 frames like LPC shoot)
	if gun_body_shoot_tex:
		var gun_shoot_img = gun_body_shoot_tex.get_image()
		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			# Shoot animation: 13 frames, faster playback for snappy feel
			create_animation_from_image(gun_shoot_img, "shoot_" + dir_name, row, 13, range(13), 15.0, false, gun_body_sprite.sprite_frames, 64)
		if DEBUG_SPRITE_SETUP:
			print("[LPCSprite] Gun shoot animations loaded")

	# Apply midsection tint shader (only tints torso, not head/feet)
	var shader = load("res://shaders/midsection_tint.gdshader")
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		gun_body_sprite.material = mat

	add_child(gun_body_sprite)

	if DEBUG_SPRITE_SETUP:
		print("[LPCSprite] Gun body layer created for Skorpio body swap")
		print("  - gun_body_sprite z_index: ", gun_body_sprite.z_index)
		print("  - Animations: ", gun_body_sprite.sprite_frames.get_animation_names())
		print("  - Midsection tint shader applied: ", gun_body_sprite.material != null)

	# Immediately activate gun mode since we just set up a gun weapon
	# This ensures the Skorpio body is visible from the start
	call_deferred("_set_gun_mode", true)
	call_deferred("_play_initial_gun_idle")

func setup_cape(walk_tex: Texture2D, slash_tex: Texture2D = null, thrust_tex: Texture2D = null, hurt_tex: Texture2D = null) -> void:
	"""Setup cape layer that renders dynamically based on facing direction.
	Capes use z-index -5 (behind body) for south/east/west directions,
	and z-index 10 (on top) when facing north to show cape over back.
	Call this AFTER setup_lpc_sprite() to add a cape to the character."""
	if not walk_tex:
		return

	# Remove existing cape if present
	if cape_sprite:
		cape_sprite.queue_free()
		cape_sprite = null

	cape_sprite = AnimatedSprite2D.new()
	cape_sprite.name = "CapeLayer"
	cape_sprite.centered = true
	cape_sprite.z_index = -5  # Behind body (0) but above shadow (-10)
	cape_sprite.sprite_frames = SpriteFrames.new()
	cape_sprite.modulate = Color(1, 1, 1, 1)

	var walk_img = walk_tex.get_image()

	# Create walk and idle animations (8 frames walk, frame 0 for idle)
	for dir_name in DIRECTION_ROWS.keys():
		var row = DIRECTION_ROWS[dir_name]
		create_animation_from_image(walk_img, "walk_" + dir_name, row, 8, [1, 2, 3, 4, 5, 6, 7, 8], 10.0, true, cape_sprite.sprite_frames, 64)
		create_animation_from_image(walk_img, "idle_" + dir_name, row, 1, [0], 1.0, true, cape_sprite.sprite_frames, 64)

	# Create attack animations (slash or thrust)
	var attack_tex = slash_tex if slash_tex else thrust_tex
	if attack_tex:
		var attack_img = attack_tex.get_image()
		var attack_size = attack_img.get_size()
		# Detect frame count: thrust has 8 frames (512px wide), slash has 6 frames (384px wide)
		var is_thrust = attack_size.x >= 500
		var attack_frames = 8 if is_thrust else 6
		var cape_attack_prefix = "thrust" if is_thrust else "slash"
		var frame_indices = []
		for i in range(attack_frames):
			frame_indices.append(i)

		for dir_name in DIRECTION_ROWS.keys():
			var row = DIRECTION_ROWS[dir_name]
			create_animation_from_image(attack_img, cape_attack_prefix + "_" + dir_name, row, attack_frames, frame_indices, 10.0, false, cape_sprite.sprite_frames, 64)

	# Create hurt animation if provided
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()
		create_animation_from_image(hurt_img, "hurt", 0, 6, [0, 1, 2, 3, 4, 5], 10.0, false, cape_sprite.sprite_frames, 64)

	add_child(cape_sprite)
	cape_sprite.visible = true
	cape_sprite.play("idle_south")

	if DEBUG_SPRITE_SETUP:
		print("[LPCSprite] Cape layer created")
		print("  - cape_sprite z_index: ", cape_sprite.z_index)
		print("  - Animations: ", cape_sprite.sprite_frames.get_animation_names())

func remove_cape() -> void:
	"""Remove the cape layer from the character"""
	if cape_sprite:
		cape_sprite.queue_free()
		cape_sprite = null
		if DEBUG_SPRITE_SETUP:
			print("[LPCSprite] Cape layer removed")

func _play_initial_gun_idle() -> void:
	"""Play initial idle animation for gun mode after setup"""
	if gun_body_sprite and gun_body_sprite.sprite_frames.has_animation("idle_south"):
		gun_body_sprite.play("idle_south")
	if weapon_sprite and weapon_sprite.sprite_frames.has_animation("idle_south"):
		weapon_sprite.play("idle_south")

func _get_sprite_dominant_color(sprite: AnimatedSprite2D) -> Color:
	"""Sample the dominant armor color from a sprite's first frame.
	Used to tint the Skorpio body to match armor color.

	For pants sprites: samples from leg region (y=40-56) which is solid armor
	For other sprites: samples from center region"""
	if not sprite or not sprite.sprite_frames:
		return Color(1, 1, 1, 1)

	# Get a valid animation with frames (prefer idle_south or walk_south)
	var anims = sprite.sprite_frames.get_animation_names()
	if anims.is_empty():
		return Color(1, 1, 1, 1)

	# Find an animation that actually has frames (avoid "default" which is often empty)
	var target_anim = ""
	var preferred = ["idle_south", "walk_south", "idle_east", "walk_east"]
	for pref in preferred:
		if sprite.sprite_frames.has_animation(pref) and sprite.sprite_frames.get_frame_count(pref) > 0:
			target_anim = pref
			break

	# Fallback: find any animation with frames
	if target_anim == "":
		for anim in anims:
			if sprite.sprite_frames.get_frame_count(anim) > 0:
				target_anim = anim
				break

	if target_anim == "":
		return Color(1, 1, 1, 1)

	var tex = sprite.sprite_frames.get_frame_texture(target_anim, 0)
	if not tex:
		return Color(1, 1, 1, 1)

	var img = tex.get_image()
	if not img:
		return Color(1, 1, 1, 1)

	# Sample colors from CHEST/TORSO region - y=24-40 is the torso area
	# LPC frames are 64x64
	var color_sum = Vector3.ZERO
	var count = 0

	# For chest armor: sample from center torso area
	var sample_x_start = 24
	var sample_x_end = 40
	var sample_y_start = 24
	var sample_y_end = 40

	for y in range(sample_y_start, min(sample_y_end, img.get_height())):
		for x in range(sample_x_start, min(sample_x_end, img.get_width())):
			var pixel = img.get_pixel(x, y)
			if pixel.a > 0.5:  # Only count non-transparent pixels
				color_sum += Vector3(pixel.r, pixel.g, pixel.b)
				count += 1

	# If no pixels found in chest region, try full scan
	if count == 0:
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var pixel = img.get_pixel(x, y)
				if pixel.a > 0.5:
					color_sum += Vector3(pixel.r, pixel.g, pixel.b)
					count += 1

	if count == 0:
		return Color(1, 1, 1, 1)

	var avg = color_sum / count
	return Color(avg.x, avg.y, avg.z, 1.0)

func _set_gun_mode(enabled: bool) -> void:
	"""Toggle between Skorpio gun body and regular LPC body.
	When gun mode is ON:
	  - Skorpio body visible (body with arms in gun-holding pose - gun NOT included)
	  - Weapon sprite visible (the actual gun layered on top)
	  - Hair visible (for character identity)
	  - Shadow visible
	  - Lower body clothing visible (pants, boots - same position as LPC)
	  - Upper body clothing hidden (shirt, arms, hands - different pose)
	When gun mode is OFF:
	  - Regular LPC body and all clothing visible
	  - Skorpio body hidden"""

	if enabled:
		# SKORPIO MODE: Hide LPC body, show Skorpio body + compatible clothing
		self_modulate.a = 0.0  # Hide main LPC body
		if base_head_sprite:
			base_head_sprite.visible = false
		# Keep lower body clothing - legs are in same position
		if pants_sprite:
			pants_sprite.visible = true
		if boots_sprite:
			boots_sprite.visible = true
		# Hide upper body clothing - arms are in different position (conflicts with Skorpio pose)
		if shirt_sprite:
			shirt_sprite.visible = false
		if arms_sprite:
			arms_sprite.visible = false
		if hands_sprite:
			hands_sprite.visible = false
		# Keep head armor visible
		if head_sprite:
			head_sprite.visible = true
		# Keep weapon visible - gun sprite goes on top of Skorpio body
		if weapon_sprite:
			weapon_sprite.visible = true
		# Keep hair visible for character identity
		if hair_sprite:
			hair_sprite.visible = true
		# =============================================================================
		# GUN BODY TINT HACK - "Skorpio Armor Illusion"
		# =============================================================================
		# Problem: Skorpio gun-pose body sprite doesn't have armor variants.
		# Solution: Tint the Skorpio body to match equipped chest armor color.
		# BUT we only tint the MIDSECTION (torso) - head and feet stay original.
		# This is done via midsection_tint.gdshader (top 56%, bottom 30% excluded).
		# Only applies for EAST/WEST directions - north/south use normal LPC body.
		# =============================================================================
		if gun_body_sprite:
			gun_body_sprite.visible = true
			gun_body_sprite.z_index = 0  # Same z as body (replaces it)
			# Sample armor color from chest, fallback to pants/boots
			var armor_color = Color(1, 1, 1, 1)
			if shirt_sprite and shirt_sprite.sprite_frames:
				armor_color = _get_sprite_dominant_color(shirt_sprite)
			if armor_color == Color(1, 1, 1, 1) and pants_sprite and pants_sprite.sprite_frames:
				armor_color = _get_sprite_dominant_color(pants_sprite)
			if armor_color == Color(1, 1, 1, 1) and boots_sprite and boots_sprite.sprite_frames:
				armor_color = _get_sprite_dominant_color(boots_sprite)
			# Apply tint via shader (only affects midsection, not head/feet)
			if gun_body_sprite.material and gun_body_sprite.material is ShaderMaterial:
				gun_body_sprite.material.set_shader_parameter("tint_color", armor_color)
			else:
				gun_body_sprite.modulate = armor_color
	else:
		# LPC MODE: Show regular body and clothing, hide Skorpio
		self_modulate.a = 1.0  # Show main LPC body
		if base_head_sprite:
			base_head_sprite.visible = true
		if pants_sprite:
			pants_sprite.visible = true
		if shirt_sprite:
			shirt_sprite.visible = true
		if boots_sprite:
			boots_sprite.visible = true
		if arms_sprite:
			arms_sprite.visible = true
		if hands_sprite:
			hands_sprite.visible = true
		if head_sprite:
			head_sprite.visible = true
		if hair_sprite:
			hair_sprite.visible = true
		# Keep weapon visible
		if weapon_sprite:
			weapon_sprite.visible = true
		# Hide Skorpio body
		if gun_body_sprite:
			gun_body_sprite.visible = false

func get_next_attack_anim() -> String:
	"""Get the next attack animation name, cycling through variants if available.
	Call this instead of hardcoding 'slash' to enable multi-slash weapons."""
	if weapon_slash_variants.is_empty():
		return "slash"  # Default fallback

	var anim = weapon_slash_variants[current_slash_index]
	current_slash_index = (current_slash_index + 1) % weapon_slash_variants.size()
	return anim

func has_multi_slash() -> bool:
	"""Returns true if this weapon has multiple slash variants."""
	return weapon_slash_variants.size() > 1

func play_lpc_animation(anim_name: String, direction: String):
	"""Play animation with direction - NO FLIPPING!"""
	current_direction = direction

	# Check if this animation has directions
	var anim_key = anim_name + "_" + direction

	# GUN MODE: When gun is equipped, use Skorpio body for EAST/WEST only
	# North/South can use regular LPC body+armor (no pose conflict)
	# Exception: harvest animations (chop) - those use regular LPC body with tool
	var is_harvesting = anim_name == "chop" or anim_name == "harvest"
	var is_side_facing = direction in ["east", "west"]
	var use_gun_mode = is_gun_weapon and has_gun_walk_animations and gun_body_sprite and not is_harvesting and is_side_facing

	if use_gun_mode:
		# Enable Skorpio body mode
		_set_gun_mode(true)

		# Map LPC animation names to Skorpio animations
		# Body stays in idle/walk pose - gun itself handles shoot animation
		var gun_anim = ""
		match anim_name:
			"idle":
				gun_anim = "idle_" + direction
			"walk":
				gun_anim = "walk_" + direction
			"shoot":
				# Keep body in idle pose during shoot - gun sprite handles the visual
				gun_anim = "idle_" + direction
			"hurt":
				# For hurt, just hold idle pose (Skorpio doesn't have hurt animation)
				gun_anim = "idle_" + direction
			_:
				# Fallback to idle for any unknown animation
				gun_anim = "idle_" + direction

		# Play the Skorpio animation
		if gun_body_sprite.sprite_frames.has_animation(gun_anim):
			gun_body_sprite.play(gun_anim)
		else:
			# Fallback to idle if animation doesn't exist
			var fallback = "idle_" + direction
			if gun_body_sprite.sprite_frames.has_animation(fallback):
				gun_body_sprite.play(fallback)

		# Sync weapon sprite to match Skorpio body pose
		if weapon_sprite:
			var weapon_anim = "idle_" + direction
			# For shoot action, try to play shoot animation on the gun if it exists
			if anim_name == "shoot":
				var shoot_anim = "shoot_" + direction
				if weapon_sprite.sprite_frames.has_animation(shoot_anim):
					weapon_anim = shoot_anim

			if weapon_sprite.sprite_frames.has_animation(weapon_anim):
				weapon_sprite.play(weapon_anim)
				weapon_sprite.visible = true
				# Z-index: behind when facing north, in front otherwise
				weapon_sprite.z_index = -1 if direction == "north" else 9
				weapon_sprite.offset = Vector2(0, 0)

		# Sync hair sprite to match Skorpio body animation
		if hair_sprite:
			var hair_anim = "idle_" + direction
			if anim_name == "walk":
				hair_anim = "walk_" + direction
			if hair_sprite.sprite_frames.has_animation(hair_anim):
				hair_sprite.play(hair_anim)

		# Adjust cape z-index for gun mode too
		if cape_sprite:
			if direction == "north":
				cape_sprite.z_index = 10  # Above all body layers when facing away
			else:
				cape_sprite.z_index = -5  # Behind body (default)

		# Stop the main body animation to prevent any visual artifacts
		stop()
		return  # Don't play LPC animations when in gun mode
	else:
		# Regular LPC mode - disable gun mode if it was enabled
		if is_gun_weapon and gun_body_sprite:
			_set_gun_mode(false)

	# NOTE: Animation speeds are set during setup_lpc_sprite() and should NOT be modified here
	# All layers must use the same FPS that was set during creation (weapon-specific)
	# Previously this code was overriding FPS to 30 which caused desync with armor layers

	# For gun weapons shooting north/south: body stays idle, only weapon animates
	# Preserve original animation for weapon sprite (it will still play "shoot")
	var weapon_anim_name = anim_name
	var weapon_anim_key = anim_key
	if is_gun_weapon and anim_name == "shoot":
		# Override shoot animation to idle for body/armor layers
		# Weapon will use weapon_anim_key which is still "shoot_north" or "shoot_south"
		anim_name = "idle"
		anim_key = "idle_" + direction

	if current_weapon_type == "dagger" and weapon_sprite:
		var has_key = weapon_sprite.sprite_frames.has_animation(weapon_anim_key)
		var has_anim = weapon_sprite.sprite_frames.has_animation(weapon_anim_name)
		var key_count = -1
		var anim_count = -1
		if has_key:
			key_count = weapon_sprite.sprite_frames.get_frame_count(weapon_anim_key)
		if has_anim:
			anim_count = weapon_sprite.sprite_frames.get_frame_count(weapon_anim_name)
		_dagger_debug("play_lpc_animation anim=%s dir=%s weapon=%s key=%s(%d) anim=%s(%d)" % [
			anim_name, direction, current_weapon_name, weapon_anim_key, key_count, weapon_anim_name, anim_count
		])

	if sprite_frames and sprite_frames.has_animation(anim_key):
		play(anim_key)
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

	# Sync cape animation with body animation
	if cape_sprite:
		if cape_sprite.sprite_frames.has_animation(anim_key):
			cape_sprite.play(anim_key)
		elif cape_sprite.sprite_frames.has_animation(anim_name):
			cape_sprite.play(anim_name)

		# Adjust cape z-index: on top when facing north (cape visible over back), behind otherwise
		if direction == "north":
			cape_sprite.z_index = 10  # Above all body layers when facing away
		else:
			cape_sprite.z_index = -5  # Behind body (default)

	# Sync armor animations with body animation
	# For base_head: keep on idle during shoot animations (head doesn't animate during archery)
	if base_head_sprite:
		if anim_name == "shoot":
			# Keep head static on idle during shoot
			var idle_key = "idle_" + direction
			if base_head_sprite.sprite_frames.has_animation(idle_key):
				base_head_sprite.play(idle_key)
		elif base_head_sprite.sprite_frames.has_animation(anim_key):
			base_head_sprite.play(anim_key)
		elif base_head_sprite.sprite_frames.has_animation(anim_name):
			base_head_sprite.play(anim_name)

	if boots_sprite:
		if boots_sprite.sprite_frames.has_animation(anim_key):
			boots_sprite.play(anim_key)
		elif boots_sprite.sprite_frames.has_animation(anim_name):
			boots_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if boots_sprite.sprite_frames.has_animation(slash_key):
				boots_sprite.play(slash_key)

	if pants_sprite:
		if pants_sprite.sprite_frames.has_animation(anim_key):
			pants_sprite.play(anim_key)
		elif pants_sprite.sprite_frames.has_animation(anim_name):
			pants_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if pants_sprite.sprite_frames.has_animation(slash_key):
				pants_sprite.play(slash_key)

	if shirt_sprite:
		if shirt_sprite.sprite_frames.has_animation(anim_key):
			shirt_sprite.play(anim_key)
		elif shirt_sprite.sprite_frames.has_animation(anim_name):
			shirt_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if shirt_sprite.sprite_frames.has_animation(slash_key):
				shirt_sprite.play(slash_key)

	if arms_sprite:
		if arms_sprite.sprite_frames.has_animation(anim_key):
			arms_sprite.play(anim_key)
		elif arms_sprite.sprite_frames.has_animation(anim_name):
			arms_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if arms_sprite.sprite_frames.has_animation(slash_key):
				arms_sprite.play(slash_key)

	if hands_sprite:
		if hands_sprite.sprite_frames.has_animation(anim_key):
			hands_sprite.play(anim_key)
		elif hands_sprite.sprite_frames.has_animation(anim_name):
			hands_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if hands_sprite.sprite_frames.has_animation(slash_key):
				hands_sprite.play(slash_key)

		# Adjust hands z-index: on top of weapon when idle facing east/west
		if anim_name == "idle" and direction in ["east", "west"]:
			hands_sprite.z_index = 10  # Above weapon (z=9)
		else:
			hands_sprite.z_index = 6  # Default position

	if head_sprite:
		if head_sprite.sprite_frames.has_animation(anim_key):
			head_sprite.play(anim_key)
			if DEBUG_SPRITE_SETUP:
				print("[SimpleLPCSprite] Playing head animation: %s" % anim_key)
		elif head_sprite.sprite_frames.has_animation(anim_name):
			head_sprite.play(anim_name)
			if DEBUG_SPRITE_SETUP:
				print("[SimpleLPCSprite] Playing head animation (no dir): %s" % anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for armor that doesn't have ranged animations
			var slash_key = "slash_" + direction
			if head_sprite.sprite_frames.has_animation(slash_key):
				head_sprite.play(slash_key)
				if DEBUG_SPRITE_SETUP:
					print("[SimpleLPCSprite] Playing head fallback: %s -> %s" % [anim_key, slash_key])
		else:
			if DEBUG_SPRITE_SETUP:
				print("[SimpleLPCSprite] WARNING: Head animation not found: %s or %s" % [anim_key, anim_name])

	if hair_sprite:
		if hair_sprite.sprite_frames.has_animation(anim_key):
			hair_sprite.play(anim_key)
		elif hair_sprite.sprite_frames.has_animation(anim_name):
			hair_sprite.play(anim_name)
		elif anim_name in ["shoot", "thrust"]:
			# Fallback: shoot/thrust -> slash for cosmetic layers
			var slash_key = "slash_" + direction
			if hair_sprite.sprite_frames.has_animation(slash_key):
				hair_sprite.play(slash_key)

	# Sync weapon animation with body animation
	if weapon_sprite:
		# Allow slash animation to restart for rapid attack feel
		# Only prevent interrupt if it's NOT a slash (e.g., switching to walk/idle mid-slash)
		if weapon_sprite.animation and weapon_sprite.animation.begins_with("slash_") and weapon_sprite.is_playing():
			if weapon_anim_name != "slash":
				# Don't interrupt slash with walk/idle
				return

		# For gun weapons, sync weapon to Skorpio body animations (idle/walk during gun mode)
		if is_gun_weapon and has_gun_walk_animations and gun_body_sprite and gun_body_sprite.visible:
			# Gun weapon needs to follow the Skorpio pose - use idle animation to match held position
			var gun_weapon_anim = "idle_" + direction
			if weapon_sprite.sprite_frames.has_animation(gun_weapon_anim):
				weapon_sprite.play(gun_weapon_anim)
				weapon_sprite.visible = true
				# Z-index: behind when facing north, in front otherwise
				weapon_sprite.z_index = -1 if direction == "north" else 9
				weapon_sprite.offset = Vector2(0, 0)
			return

		# Use weapon-specific animation (preserves "shoot" for guns even when body is on "idle")
		if weapon_sprite.sprite_frames.has_animation(weapon_anim_key):
			weapon_sprite.play(weapon_anim_key)
			weapon_sprite.visible = true
			# Adjust weapon z-index based on direction and animation
			if current_weapon_name == "kerrigan_psi_blade":
				weapon_sprite.z_index = 9  # Always on top for Kerrigan blade
			elif direction == "north":
				weapon_sprite.z_index = -1  # Behind character when facing up
			elif anim_name == "walk" and current_weapon_type == "spear" and direction in ["east", "west"]:
				weapon_sprite.z_index = -1  # Spear goes under body when walking sideways
			elif anim_name in ["walk", "idle"] and current_weapon_type in ["bow", "crossbow"]:
				weapon_sprite.z_index = -1  # Bow on back goes behind player for all directions
			elif anim_name == "idle" and direction in ["east", "west"]:
				weapon_sprite.z_index = -1  # Weapon behind hands when idle facing sideways
			else:
				weapon_sprite.z_index = 9  # On top normally

			# Adjust offset based on animation type and weapon
			# Oversize weapons (192x192 like staff) need offsets, standard weapons (64x64) don't
			if weapon_anim_name in ["slash", "thrust", "shoot"]:
				var attack_offset = Vector2(0, 0)

				# Only apply offsets for oversize weapons (staff uses 192x192 tiles)
				if current_weapon_type == "staff":
					match direction:
						"east":  # facing right
							attack_offset = Vector2(-10, 5)
						"west":  # facing left
							attack_offset = Vector2(10, 5)
						"north":  # facing up
							attack_offset = Vector2(-10, 0)
						"south":  # facing down
							attack_offset = Vector2(-5, 5)
				elif current_weapon_type == "trident":
					match direction:
						"east", "west":  # facing left/right - Y down 5px
							attack_offset = Vector2(0, 5)
				# Saw cleaver / king slayer need offset when facing north
				elif current_weapon_name in ["saw_cleaver", "king_slayer"]:
					if direction == "north":
						attack_offset = Vector2(0, -5)  # Up 5px when attacking north
				elif current_weapon_type == "dagger":
					# Keep dagger behind the body when swinging sideways
					if direction in ["east", "west"]:
						if current_weapon_name == "kerrigan_psi_blade":
							weapon_sprite.z_index = 9  # keep in front for Kerrigan blade
							attack_offset = Vector2(-6 if direction == "east" else 6, 2)
						else:
							weapon_sprite.z_index = -1
							attack_offset = Vector2(-6 if direction == "east" else 6, 2)
					else:
						attack_offset = Vector2(0, 0)
					_dagger_debug("attack anim=%s dir=%s weapon=%s z=%d offset=%s has_anim=%s" % [
						weapon_anim_key, direction, current_weapon_name, weapon_sprite.z_index, attack_offset,
						weapon_sprite.sprite_frames.has_animation(weapon_anim_key)
					])
				# Spear and other standard 64x64 weapons use no offset

				weapon_sprite.offset = attack_offset
				if current_weapon_type == "dagger" and weapon_sprite.sprite_frames.has_animation(weapon_anim_key):
					var tex = weapon_sprite.sprite_frames.get_frame_texture(weapon_anim_key, 0)
					_dagger_debug("attack frame tex=%s size=%s z=%d offset=%s dir=%s" % [
						tex, tex and tex.get_size(), weapon_sprite.z_index, attack_offset, direction
					])
			else:
				# Walk/idle animations - weapon sprites should align with character
				var walk_offset = Vector2(0, 0)
				# Saw cleaver / king slayer need offset when facing north
				if current_weapon_name in ["saw_cleaver", "king_slayer"]:
					if direction == "north":
						walk_offset = Vector2(0, -10)  # Up 10px when walking/idling north
				if current_weapon_type == "dagger" and direction in ["east", "west"]:
					if current_weapon_name == "kerrigan_psi_blade":
						weapon_sprite.z_index = 9  # keep in front for Kerrigan blade
					else:
						weapon_sprite.z_index = -1  # dagger behind body when walking sideways
					_dagger_debug("walk dir=%s weapon=%s z=%d offset=%s anim=%s has_anim=%s" % [
						direction, current_weapon_name, weapon_sprite.z_index, walk_offset, weapon_anim_key, weapon_sprite.sprite_frames.has_animation(weapon_anim_name)
					])
				weapon_sprite.offset = walk_offset
		elif weapon_sprite.sprite_frames.has_animation(weapon_anim_name):
			# Animation without directions (like hurt)
			weapon_sprite.play(weapon_anim_name)
			weapon_sprite.visible = true
			weapon_sprite.z_index = -1 if direction == "north" else 9
		else:
			# No matching weapon animation, hide weapon
			weapon_sprite.visible = false
			weapon_sprite.stop()


# Tool-specific harvest animation support
var harvest_tool_sprite: AnimatedSprite2D = null
var is_harvesting: bool = false

func play_harvest_animation(tool_type: String, direction: String) -> void:
	"""Play harvest animation with specific tool (axe/pickaxe)"""
	is_harvesting = true

	# Convert direction from old format (up/down/left/right) to LPC format (north/south/west/east)
	var lpc_direction = direction
	match direction:
		"up": lpc_direction = "north"
		"down": lpc_direction = "south"
		"left": lpc_direction = "west"
		"right": lpc_direction = "east"

	# Use reversed "chop_" animation for harvesting (swing starts high, ends low)
	var chop_anim = "chop_" + lpc_direction
	var slash_anim = "slash_" + lpc_direction  # Source animation

	# If using thrust animation, create slash-based chop from actual slash.png
	# This gives proper top-to-bottom swing motion instead of reversed thrust
	if uses_thrust_animation and body_type_path != "":
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
		return

	var slash_tex = load(slash_path)
	var slash_img = slash_tex.get_image()
	var row = DIRECTION_ROWS[lpc_direction]

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
			return
	else:
		# Legacy format without prefix - assume armor folder
		slash_path = "res://assets/equipment/armor/" + armor_path + "/standard/slash.png"

	if not ResourceLoader.exists(slash_path):
		return

	var slash_tex = load(slash_path)
	var slash_img = slash_tex.get_image()
	var row = DIRECTION_ROWS[lpc_direction]

	# Check if this is actually 6-frame slash (384px) or 8-frame thrust (512px)
	var tex_width = slash_img.get_width()
	if tex_width >= 500:
		# This is thrust.png, not slash.png - skip (we want actual 6-frame slash)
		return

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

	# Use the ACTUAL tool sprites from the custom/slash_128 folder
	var tool_path: String
	if tool_type == "axe":
		tool_path = "res://assets/equipment/tools/axe/custom/slash_128/140 tool_smash_.png"
	else:  # pickaxe
		tool_path = "res://assets/equipment/tools/pickaxe/custom/slash_128/140 tool_smash_.png"

	if not ResourceLoader.exists(tool_path):
		# Fallback to using weapon sprites as placeholder
		if tool_type == "axe":
			tool_path = "res://assets/equipment/weapons/mace/slash.png"
		else:
			tool_path = "res://assets/equipment/weapons/sword/slash.png"

	var tool_tex = load(tool_path)
	var tool_img = tool_tex.get_image()

	# 768x512 sheet = 6 columns x 4 rows at 128x128 per frame
	var num_frames = 6
	var tile_size = 128
	var row = DIRECTION_ROWS[lpc_direction]

	# Create animation using same method as weapons
	# Reverse frame order for chopping motion (start high, swing down)
	var anim_name = tool_type + "_slash_" + lpc_direction
	if not harvest_tool_sprite.sprite_frames.has_animation(anim_name):
		create_animation_from_image(tool_img, anim_name, row, num_frames, [5, 4, 3, 2, 1, 0], 10.0, false, harvest_tool_sprite.sprite_frames, tile_size)

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
