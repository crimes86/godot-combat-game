extends Node
class_name LPCCharacter

## LPC (Liberated Pixel Cup) Character Animation System
## Handles sprite compositing and animation for LPC-format characters
## Supports walk, attack (slash), and hurt animations with multiple layers

enum Gender { MALE, FEMALE }

# Character configuration
var character_name: String = "Character"
var gender: Gender = Gender.MALE
var animated_sprite: AnimatedSprite2D = null

# Layer configuration - paths to sprite sheets
var layers: Dictionary = {
	"body": {"walk": "", "slash": "", "hurt": ""},
	"legs": {"walk": "", "slash": "", "hurt": ""},
	"torso": {"walk": "", "slash": "", "hurt": ""},
	"head": {"walk": "", "slash": "", "hurt": ""},
	"hair": {"walk": "", "slash": "", "hurt": ""},  # Female only
	"beard": {"walk": "", "slash": "", "hurt": ""},  # Male only
	"weapon": {"walk": "", "slash": "", "hurt": ""}
}

# Animation configuration
const FRAME_SIZE: Vector2i = Vector2i(64, 64)
const WALK_FRAMES_PER_ROW: int = 9
const SLASH_FRAMES_PER_ROW: int = 6
const HURT_FRAMES: int = 6

## Initialize LPC character with sprite node
func setup(sprite_node: AnimatedSprite2D) -> void:
	animated_sprite = sprite_node
	DebugConfig.debug_log("🎨 LPCCharacter setup for: %s (Gender: %s)" % [character_name, "MALE" if gender == Gender.MALE else "FEMALE"])

## Set a layer sprite path
func set_layer(layer_name: String, walk_path: String = "", slash_path: String = "", hurt_path: String = "") -> void:
	if not layers.has(layer_name):
		DebugConfig.log_error("Invalid layer name: %s" % layer_name)
		return

	layers[layer_name] = {
		"walk": walk_path,
		"slash": slash_path,
		"hurt": hurt_path
	}

## Generate animations from configured layers
func generate_animations() -> bool:
	if not animated_sprite:
		DebugConfig.log_error("AnimatedSprite2D not set. Call setup() first.")
		return false

	# Composite walk animations
	var walk_composite = _composite_animation_type("walk")
	if not walk_composite:
		DebugConfig.log_error("Failed to composite walk animations")
		return false

	# Composite slash animations
	var slash_composite = _composite_animation_type("slash")
	if not slash_composite:
		DebugConfig.log_error("Failed to composite slash animations")
		return false

	# Composite hurt animations
	var hurt_composite = _composite_animation_type("hurt")
	if not hurt_composite:
		DebugConfig.log_error("Failed to composite hurt animations")
		return false

	# Create sprite frames
	var sprite_frames = SpriteFrames.new()

	# Setup walk animations (4 directions, 9 frames each)
	_create_directional_animation(sprite_frames, walk_composite, "walk_up", 0, WALK_FRAMES_PER_ROW, 8.0)
	_create_directional_animation(sprite_frames, walk_composite, "walk_left", 1, WALK_FRAMES_PER_ROW, 8.0)
	_create_directional_animation(sprite_frames, walk_composite, "walk_down", 2, WALK_FRAMES_PER_ROW, 8.0)
	_create_directional_animation(sprite_frames, walk_composite, "walk_right", 3, WALK_FRAMES_PER_ROW, 8.0)

	# Setup idle animations (use middle frame of walk)
	_create_directional_animation(sprite_frames, walk_composite, "idle_up", 0, 1, 1.0, true, 4)
	_create_directional_animation(sprite_frames, walk_composite, "idle_left", 1, 1, 1.0, true, 4)
	_create_directional_animation(sprite_frames, walk_composite, "idle_down", 2, 1, 1.0, true, 4)
	_create_directional_animation(sprite_frames, walk_composite, "idle_right", 3, 1, 1.0, true, 4)

	# Setup attack animations (4 directions, 6 frames each)
	_create_directional_animation(sprite_frames, slash_composite, "attack_up", 0, SLASH_FRAMES_PER_ROW, 12.0, false)
	_create_directional_animation(sprite_frames, slash_composite, "attack_left", 1, SLASH_FRAMES_PER_ROW, 12.0, false)
	_create_directional_animation(sprite_frames, slash_composite, "attack_down", 2, SLASH_FRAMES_PER_ROW, 12.0, false)
	_create_directional_animation(sprite_frames, slash_composite, "attack_right", 3, SLASH_FRAMES_PER_ROW, 12.0, false)

	# Setup hurt animation (single row, 6 frames)
	_create_hurt_animation(sprite_frames, hurt_composite, "hurt", HURT_FRAMES, 10.0)

	# Apply to sprite
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.play("idle_down")

	DebugConfig.debug_log("✅ LPCCharacter animations generated: %d animations" % sprite_frames.get_animation_names().size())
	return true

## Composite all layers for a specific animation type (walk/slash/hurt)
func _composite_animation_type(anim_type: String) -> Image:
	var layer_order = ["body", "legs", "torso", "head", "hair", "beard", "weapon"]
	var base_image: Image = null

	# Get expected dimensions based on animation type
	var expected_width: int
	var expected_height: int

	match anim_type:
		"walk":
			expected_width = WALK_FRAMES_PER_ROW * FRAME_SIZE.x
			expected_height = 4 * FRAME_SIZE.y  # 4 directions
		"slash":
			expected_width = SLASH_FRAMES_PER_ROW * FRAME_SIZE.x
			expected_height = 4 * FRAME_SIZE.y  # 4 directions
		"hurt":
			expected_width = HURT_FRAMES * FRAME_SIZE.x
			expected_height = FRAME_SIZE.y  # Single row
		_:
			DebugConfig.log_error("Unknown animation type: %s" % anim_type)
			return null

	# Composite layers in order
	for layer_name in layer_order:
		var layer_path = layers[layer_name][anim_type]

		# Skip empty layers
		if layer_path.is_empty():
			continue

		# Skip gender-specific layers
		if layer_name == "hair" and gender == Gender.MALE:
			continue
		if layer_name == "beard" and gender == Gender.FEMALE:
			continue

		# Load layer image
		if not ResourceLoader.exists(layer_path):
			DebugConfig.log_warning("Layer file not found: %s" % layer_path)
			continue

		var texture = ResourceLoader.load(layer_path, "Texture2D")
		if not texture:
			DebugConfig.log_warning("Failed to load texture: %s" % layer_path)
			continue

		var layer_img = texture.get_image()

		# Create base image if first layer
		if base_image == null:
			base_image = Image.create(expected_width, expected_height, false, Image.FORMAT_RGBA8)
			base_image.fill(Color(0, 0, 0, 0))  # Transparent

		# Composite layer onto base
		base_image.blend_rect(layer_img, Rect2i(0, 0, layer_img.get_width(), layer_img.get_height()), Vector2i(0, 0))

	return base_image

## Create animation from sprite sheet row
func _create_directional_animation(sprite_frames: SpriteFrames, source_img: Image, anim_name: String, row: int, frame_count: int, fps: float, loop: bool = true, start_frame: int = 0) -> void:
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	for i in range(frame_count):
		var frame_idx = start_frame + i
		var frame_img = Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(source_img, Rect2i(frame_idx * FRAME_SIZE.x, row * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y), Vector2i(0, 0))

		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

## Create hurt animation (single row)
func _create_hurt_animation(sprite_frames: SpriteFrames, source_img: Image, anim_name: String, frame_count: int, fps: float) -> void:
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, false)
	sprite_frames.set_animation_speed(anim_name, fps)

	for i in range(frame_count):
		var frame_img = Image.create(FRAME_SIZE.x, FRAME_SIZE.y, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(source_img, Rect2i(i * FRAME_SIZE.x, 0, FRAME_SIZE.x, FRAME_SIZE.y), Vector2i(0, 0))

		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

## Quick setup for simple characters (single body sprite)
static func create_simple(sprite_node: AnimatedSprite2D, body_walk: String, body_slash: String, body_hurt: String, character_gender: Gender = Gender.MALE) -> LPCCharacter:
	var lpc = LPCCharacter.new()
	lpc.gender = character_gender
	lpc.setup(sprite_node)
	lpc.set_layer("body", body_walk, body_slash, body_hurt)
	lpc.generate_animations()
	return lpc
