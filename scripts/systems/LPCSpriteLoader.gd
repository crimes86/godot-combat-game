extends Node
class_name LPCSpriteLoader

## Loads and animates LPC (Liberated Pixel Cup) format spritesheets
## LPC Format: 64x64 tiles, arranged in specific animation rows

# LPC spritesheet layout (384x256 total, 64x64 per frame)
# Row 0: Walk Up (6 frames)
# Row 1: Walk Left (6 frames) 
# Row 2: Walk Down (6 frames)
# Row 3: Walk Right (6 frames)
# Row 4-7: Attack animations
# Each animation: 6 frames across

const TILE_SIZE = 64
const FRAMES_PER_ROW = 6

enum AnimationType {
	WALK_UP,
	WALK_LEFT,
	WALK_DOWN,
	WALK_RIGHT,
	WALK_UP_LEFT,
	WALK_UP_RIGHT,
	WALK_DOWN_LEFT,
	WALK_DOWN_RIGHT,
	ATTACK_UP,
	ATTACK_LEFT,
	ATTACK_DOWN,
	ATTACK_RIGHT,
	IDLE_UP,
	IDLE_LEFT,
	IDLE_DOWN,
	IDLE_RIGHT
}

# Map directions to animation rows in LPC spritesheet
const WALK_ROW_MAP = {
	AnimationType.WALK_UP: 0,
	AnimationType.WALK_LEFT: 1,
	AnimationType.WALK_DOWN: 2,
	AnimationType.WALK_RIGHT: 3
}

static func load_spritesheet(base_path: String, layers: Array = []) -> Texture2D:
	"""
	Load and composite LPC spritesheet layers
	base_path: Path to BODY sprite (e.g., "res://assets/characters/BODY_human.png")
	layers: Array of additional layer paths to composite on top
	Returns: Composited texture
	"""
	
	# Load base image
	var base_image = Image.load_from_file(base_path)
	if base_image == null:
		push_error("Failed to load base sprite: " + base_path)
		return null
	
	# Composite additional layers
	for layer_path in layers:
		var layer_image = Image.load_from_file(layer_path)
		if layer_image != null:
			base_image.blend_rect(layer_image, Rect2i(0, 0, layer_image.get_width(), layer_image.get_height()), Vector2i(0, 0))
	
	return ImageTexture.create_from_image(base_image)

static func get_animation_frame(texture: Texture2D, anim_type: AnimationType, frame: int) -> AtlasTexture:
	"""
	Extract a single frame from LPC spritesheet
	texture: The composited spritesheet texture
	anim_type: Which animation to use
	frame: Frame number (0-5 for most animations)
	Returns: AtlasTexture with the specific frame
	"""
	
	var atlas = AtlasTexture.new()
	atlas.atlas = texture
	
	# Determine row based on animation type
	var row = 0
	match anim_type:
		AnimationType.WALK_UP, AnimationType.WALK_UP_LEFT, AnimationType.WALK_UP_RIGHT, AnimationType.IDLE_UP:
			row = 0
		AnimationType.WALK_LEFT, AnimationType.IDLE_LEFT:
			row = 1
		AnimationType.WALK_DOWN, AnimationType.WALK_DOWN_LEFT, AnimationType.WALK_DOWN_RIGHT, AnimationType.IDLE_DOWN:
			row = 2
		AnimationType.WALK_RIGHT, AnimationType.IDLE_RIGHT:
			row = 3
		AnimationType.ATTACK_UP:
			row = 4
		AnimationType.ATTACK_LEFT:
			row = 5
		AnimationType.ATTACK_DOWN:
			row = 6
		AnimationType.ATTACK_RIGHT:
			row = 7
	
	# For idle, use frame 0 (standing still)
	var actual_frame = frame
	if anim_type in [AnimationType.IDLE_UP, AnimationType.IDLE_LEFT, AnimationType.IDLE_DOWN, AnimationType.IDLE_RIGHT]:
		actual_frame = 0
	
	# Clamp frame to valid range
	actual_frame = clamp(actual_frame, 0, FRAMES_PER_ROW - 1)
	
	# Set region
	atlas.region = Rect2(actual_frame * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	
	return atlas

static func get_animation_for_direction(velocity: Vector2, is_moving: bool) -> AnimationType:
	"""
	Determine which animation to play based on movement direction
	Supports 8-directional movement
	"""
	
	if not is_moving or velocity.length() < 0.1:
		# Idle - determine facing based on last direction
		# Default to down if no direction
		if abs(velocity.x) > abs(velocity.y):
			return AnimationType.IDLE_RIGHT if velocity.x > 0 else AnimationType.IDLE_LEFT
		else:
			return AnimationType.IDLE_DOWN if velocity.y > 0 else AnimationType.IDLE_UP
	
	# Normalize velocity to get direction
	var dir = velocity.normalized()
	
	# Determine 8-directional animation
	# Check diagonals first (45 degree cone)
	if dir.x > 0.5 and dir.y < -0.5:
		return AnimationType.WALK_UP_RIGHT
	elif dir.x < -0.5 and dir.y < -0.5:
		return AnimationType.WALK_UP_LEFT
	elif dir.x > 0.5 and dir.y > 0.5:
		return AnimationType.WALK_DOWN_RIGHT
	elif dir.x < -0.5 and dir.y > 0.5:
		return AnimationType.WALK_DOWN_LEFT
	
	# Cardinal directions
	elif abs(dir.x) > abs(dir.y):
		return AnimationType.WALK_RIGHT if dir.x > 0 else AnimationType.WALK_LEFT
	else:
		return AnimationType.WALK_DOWN if dir.y > 0 else AnimationType.WALK_UP

static func create_animation_player(sprite: Sprite2D, texture: Texture2D) -> AnimationPlayer:
	"""
	Create an AnimationPlayer with all LPC animations set up
	"""
	var anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	
	# Walk animations (all 8 directions)
	for anim_name in ["walk_up", "walk_left", "walk_down", "walk_right", 
					  "walk_up_left", "walk_up_right", "walk_down_left", "walk_down_right"]:
		var anim = Animation.new()
		var track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, ".:texture")
		anim.length = 0.6  # 6 frames at 10fps
		
		# Determine animation type
		var anim_type: AnimationType
		match anim_name:
			"walk_up": anim_type = AnimationType.WALK_UP
			"walk_left": anim_type = AnimationType.WALK_LEFT
			"walk_down": anim_type = AnimationType.WALK_DOWN
			"walk_right": anim_type = AnimationType.WALK_RIGHT
			"walk_up_left": anim_type = AnimationType.WALK_UP_LEFT
			"walk_up_right": anim_type = AnimationType.WALK_UP_RIGHT
			"walk_down_left": anim_type = AnimationType.WALK_DOWN_LEFT
			"walk_down_right": anim_type = AnimationType.WALK_DOWN_RIGHT
		
		# Add frames
		for frame in range(6):
			var time = frame * 0.1
			var frame_texture = get_animation_frame(texture, anim_type, frame)
			anim.track_insert_key(track_idx, time, frame_texture)
		
		anim.loop_mode = Animation.LOOP_LINEAR
		anim_player.add_animation(anim_name, anim)
	
	# Idle animations (4 directions, single frame each)
	for anim_name in ["idle_up", "idle_left", "idle_down", "idle_right"]:
		var anim = Animation.new()
		var track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, ".:texture")
		anim.length = 0.1
		
		var anim_type: AnimationType
		match anim_name:
			"idle_up": anim_type = AnimationType.IDLE_UP
			"idle_left": anim_type = AnimationType.IDLE_LEFT
			"idle_down": anim_type = AnimationType.IDLE_DOWN
			"idle_right": anim_type = AnimationType.IDLE_RIGHT
		
		var frame_texture = get_animation_frame(texture, anim_type, 0)
		anim.track_insert_key(track_idx, 0.0, frame_texture)
		
		anim_player.add_animation(anim_name, anim)
	
	# Attack animations (4 directions)
	for anim_name in ["attack_up", "attack_left", "attack_down", "attack_right"]:
		var anim = Animation.new()
		var track_idx = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, ".:texture")
		anim.length = 0.3  # Faster attack
		
		var anim_type: AnimationType
		match anim_name:
			"attack_up": anim_type = AnimationType.ATTACK_UP
			"attack_left": anim_type = AnimationType.ATTACK_LEFT
			"attack_down": anim_type = AnimationType.ATTACK_DOWN
			"attack_right": anim_type = AnimationType.ATTACK_RIGHT
		
		for frame in range(6):
			var time = frame * 0.05
			var frame_texture = get_animation_frame(texture, anim_type, frame)
			anim.track_insert_key(track_idx, time, frame_texture)
		
		anim_player.add_animation(anim_name, anim)
	
	return anim_player
