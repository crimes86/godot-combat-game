extends CharacterBody2D
class_name Wolf

## Wolf Enemy - Pack hunter that spawns at bone clusters/ritual sites
## Based on skeleton enemy but with wolf-specific behavior and animations

# Network ID for multiplayer sync
var network_id: int = -1

# Enemy stats (wolves are faster but less tanky than skeletons)
# Health scales with level using Constants (same as skeletons, but 80% of skeleton health)
@export var max_health: float = 80.0
@export var current_health: float = 80.0
@export var base_damage: float = 15.0  # Wolves hit harder but die faster

# Enemy level and progression
@export var enemy_level: int = 1
@export var xp_reward_base: int = 12  # Good XP for pack kills
var xp_reward: int = 12
@export var gold_drop_base: int = 4
var gold_drop: int = 4

# Wolf-specific: pack behavior
var pack_id: String = ""  # Wolves in same pack share this ID
var pack_alpha: bool = false  # Is this the alpha of its pack?
var is_alpha_dire_wolf: bool = false  # Rare variant - 50% bigger, darker, rich loot
const ALPHA_DIRE_WOLF_CHANCE: float = 0.1  # 10% chance per pack alpha

# Movement (wolves are faster than skeletons)
const BASE_SPEED: float = 180.0  # Faster than skeleton's 120
const RUN_SPEED_MULT: float = 1.5  # When chasing
var current_speed: float = BASE_SPEED

# LOD tracking
var current_lod: int = 0
var lod_update_timer: float = 0.0
const LOD_UPDATE_INTERVAL: float = 0.5
const LOD_NEAR_DISTANCE: float = 1200.0
const LOD_FAR_DISTANCE: float = 2500.0

# Cached references
var cached_player: Node = null
var ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.2

# Animation
var sprite: Sprite2D = null
var shadow_sprite: Sprite2D = null
var current_direction: String = "down"
var is_running: bool = false
var is_attacking: bool = false
var current_animation: String = "idle_down"  # Server sync - updated on every animation change

# Health bar and UI
var health_bar: Control = null
var level_label: Label = null

# Combat
var in_crit_window: bool = false
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var weakpoints: Array = []
var is_dying: bool = false

# Corpse state
var is_corpse: bool = false
var corpse_loot: Array = []
var corpse_gold: int = 0
var player_in_loot_range: bool = false
var loot_ui_open: bool = false  # Is the loot UI currently open for this corpse?

# Signals
signal weakpoint_spawned(weakpoint: Node)
signal weakpoint_destroyed(weakpoint: Node)
signal died()
signal damage_taken(damage: float, is_crit: bool)
signal corpse_clicked(corpse)
signal corpse_looted_empty(corpse)

# Sprite sheet paths - separate files per direction
const WOLF_SPRITES = {
	"left": "res://assets/characters/enemies/wolf-left.png",
	"right": "res://assets/characters/enemies/wolf-right.png",
	"down": "res://assets/characters/enemies/wolf-down.png",
	"up": "res://assets/characters/enemies/wolf-up.png",
}

# Frame dimensions per direction type
# Side views (left/right): 320x192 sheet, 6 rows, uniform 64x32 frames
const FRAME_SIZE_SIDE = Vector2(64, 32)
# Front/back views (up/down): 32x64 per frame (user measured)
const FRAME_SIZE_FRONT = Vector2(32, 64)

# Animation definitions per sprite sheet
# wolf-left.png and wolf-right.png layout (uniform 64x32 frames):
#   Row 0: die (4 frames)
#   Row 1: blank (skip)
#   Row 2: howl (4 frames)
#   Row 3: walk (5 frames)
#   Row 4: run (5 frames)
#   Row 5: bite/attack (5 frames)
const ANIMS_SIDE = {
	"die": {"row": 0, "frames": 4},
	"howl": {"row": 2, "frames": 4},
	"walk": {"row": 3, "frames": 5},
	"run": {"row": 4, "frames": 5},
	"attack": {"row": 5, "frames": 5},
}

# wolf-down.png and wolf-up.png layout (uniform 32x64 frames):
#   Row 0: howl (4 frames)
#   Row 1: die (4 frames)
#   Row 2: walk (4 frames)
#   Row 3: run (5 frames)
#   Row 4: bite/attack (5 frames)
const ANIMS_FRONT = {
	"howl": {"row": 0, "frames": 4},
	"die": {"row": 1, "frames": 4},
	"walk": {"row": 2, "frames": 4},
	"run": {"row": 3, "frames": 5},
	"attack": {"row": 4, "frames": 5},
}

# Loaded textures cache
var _wolf_textures: Dictionary = {}

# Server mode flag - skip all visual/texture creation on dedicated server
var _is_server_mode: bool = false

func _ready() -> void:
	_is_server_mode = "--server" in OS.get_cmdline_user_args()
	add_to_group(Constants.GROUP_ENEMIES)
	add_to_group("wolves")

	# Apply level scaling
	apply_level_scaling()

	# Set collision (needed on server for physics)
	collision_layer = 4  # Enemy layer
	collision_mask = 1 | 2  # Player + obstacles

	# Initialize AI variation (desync pack members)
	_init_ai_variation()

	# Connect damage signal to enter combat when hit by ranged weapons
	damage_taken.connect(_on_damage_taken)

	# DEDICATED SERVER: Skip all visual/texture creation
	if _is_server_mode:
		return

	# --- CLIENT-ONLY VISUAL SETUP BELOW ---
	setup_sprite()
	setup_shadow()
	setup_health_bar()
	setup_click_area()

	# Start with idle animation
	play_animation("idle_down")

	# Pack alpha wolves have a chance to howl on spawn (not alpha dire - they have their own)
	if pack_alpha and not is_alpha_dire_wolf:
		if randf() < 0.15:  # 15% chance for pack alpha
			# Pick between distant and pack howl for variety
			var howl_type = "pack" if randf() < 0.4 else "distant"
			call_deferred("_try_spawn_howl", howl_type)


func apply_level_scaling() -> void:
	"""Scale stats based on enemy level - uses Constants like skeletons"""
	# Base health from Constants (wolves have 80% of skeleton health - glass cannons)
	# Rebalanced: Lower base HP (35) with 12% scaling
	max_health = Constants.ENEMY_BASE_HEALTH * pow(Constants.ENEMY_HEALTH_SCALING, enemy_level - 1) * 0.8
	current_health = max_health

	# Damage scales with level (rebalanced: base 7 damage, 8% per level)
	# Higher base makes armor meaningful - naked feels dangerous, armored feels protected
	base_damage = 7.0 * pow(Constants.ENEMY_DAMAGE_SCALING, enemy_level - 1)
	xp_reward = int(xp_reward_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))

	# Pack alpha wolves are stronger
	if pack_alpha:
		max_health *= 1.4
		base_damage *= 1.25
		xp_reward = int(xp_reward * 1.3)
		gold_drop = int(gold_drop * 1.5)

		# Roll for Alpha Dire Wolf (rare variant)
		if randf() < ALPHA_DIRE_WOLF_CHANCE:
			_become_alpha_dire_wolf()

	current_health = max_health


func _become_alpha_dire_wolf() -> void:
	"""Transform this wolf into a rare Alpha Dire Wolf variant"""
	is_alpha_dire_wolf = true

	# 50% bigger
	scale = Vector2(1.5, 1.5)

	# Much stronger stats
	max_health *= 2.5
	base_damage *= 1.8
	xp_reward = int(xp_reward * 3)

	# BIG money loot
	gold_drop = int(gold_drop * 10)  # 10x gold!

	# Darker appearance (applied after sprite setup)
	call_deferred("_apply_alpha_dire_appearance")

	# Alpha Dire Wolf howl on spawn (50% chance, uses alpha howl)
	if randf() < 0.5:
		call_deferred("_try_spawn_howl", "alpha")


func _apply_alpha_dire_appearance() -> void:
	"""Apply dark tint to Alpha Dire Wolf"""
	if sprite:
		sprite.modulate = Color(0.4, 0.35, 0.5, 1.0)  # Dark purple-gray tint


func _try_spawn_howl(howl_type: String = "distant") -> void:
	"""Try to play a howl on spawn (respects cooldown system)"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("try_play_wolf_howl"):
		var played = sound_manager.try_play_wolf_howl(global_position, howl_type, -8.0)
		# Play howl animation if sound was played (not blocked by cooldown)
		if played:
			_play_howl_animation()


var _is_howling: bool = false

func _play_howl_animation() -> void:
	"""Play the howl animation (head up, mouth open)"""
	if _is_howling or is_dying or is_corpse:
		return

	_is_howling = true
	_is_idle = false  # Make sure animation plays

	# Set to howl animation
	_set_animation_type("howl")
	_current_frame = 0
	_update_sprite_region()

	# Hold howl pose for duration of sound (~2-3 seconds for the visual)
	await get_tree().create_timer(2.5).timeout

	if is_instance_valid(self) and not is_dying:
		_is_howling = false
		# Return to idle/walk
		_set_animation_type("walk")
		_is_idle = true  # Pause on idle frame


func setup_sprite() -> void:
	"""Create Sprite2D with region-based animation using separate direction sprites"""
	# Load all direction textures
	for dir_name in WOLF_SPRITES:
		var tex = load(WOLF_SPRITES[dir_name]) as Texture2D
		if tex:
			_wolf_textures[dir_name] = tex
		else:
			push_error("Failed to load wolf sprite: " + WOLF_SPRITES[dir_name])

	# Create sprite
	var sprite2d = Sprite2D.new()
	sprite2d.name = "Sprite2D"

	# Start with down direction
	if _wolf_textures.has("down"):
		sprite2d.texture = _wolf_textures["down"]
		sprite2d.region_enabled = true
		# First frame of walk animation (row 2 for down/up)
		var walk_data = ANIMS_FRONT["walk"]
		sprite2d.region_rect = Rect2(0, walk_data.row * FRAME_SIZE_FRONT.y, FRAME_SIZE_FRONT.x, FRAME_SIZE_FRONT.y)

	sprite2d.scale = Vector2(1.25, 1.25)  # Smaller scale
	sprite2d.z_index = 5
	sprite2d.centered = true
	add_child(sprite2d)

	sprite = sprite2d
	original_scale = sprite2d.scale
	original_modulate = sprite2d.modulate

	# Start animation timer
	_start_animation_timer()


# Animation state
var _current_dir: String = "down"  # Current direction: left, right, up, down
var _current_anim_type: String = "walk"  # Current animation: walk, run, attack, die, howl
var _current_frame: int = 0
var _anim_timer: Timer = null
var _is_idle: bool = false  # When true, animation pauses on current frame


func _start_animation_timer() -> void:
	"""Start timer for manual animation frame updates"""
	_anim_timer = Timer.new()
	_anim_timer.wait_time = 1.0 / 8.0  # 8 FPS
	_anim_timer.timeout.connect(_advance_frame)
	add_child(_anim_timer)
	_anim_timer.start()


func _advance_frame() -> void:
	"""Advance to next animation frame"""
	if not sprite or is_dying or _is_idle:
		return

	# Get animation data for current direction
	var is_side = (_current_dir == "left" or _current_dir == "right")
	var anims = ANIMS_SIDE if is_side else ANIMS_FRONT
	var frame_size = FRAME_SIZE_SIDE if is_side else FRAME_SIZE_FRONT

	if not anims.has(_current_anim_type):
		return

	var anim_data = anims[_current_anim_type]

	# Advance frame
	_current_frame = (_current_frame + 1) % anim_data.frames

	# Update sprite region
	var frame_x = _current_frame * frame_size.x
	var frame_y = anim_data.row * frame_size.y
	sprite.region_rect = Rect2(frame_x, frame_y, frame_size.x, frame_size.y)


func _set_direction(new_dir: String) -> void:
	"""Change sprite direction (swaps texture)"""
	if new_dir == _current_dir:
		return

	if not _wolf_textures.has(new_dir):
		return

	_current_dir = new_dir
	sprite.texture = _wolf_textures[new_dir]

	# Reset to frame 0 of current animation
	_current_frame = 0
	_update_sprite_region()

	# Update shadow scale for direction
	_update_shadow_for_direction()


func _set_animation_type(anim_type: String) -> void:
	"""Change animation type (walk, run, attack, etc)"""
	if anim_type == _current_anim_type:
		return

	_current_anim_type = anim_type
	_current_frame = 0
	_update_sprite_region()


func _update_sprite_region() -> void:
	"""Update sprite region for current direction/animation/frame"""
	if not sprite:
		return

	var is_side = (_current_dir == "left" or _current_dir == "right")
	var anims = ANIMS_SIDE if is_side else ANIMS_FRONT
	var frame_size = FRAME_SIZE_SIDE if is_side else FRAME_SIZE_FRONT

	if not anims.has(_current_anim_type):
		return

	var anim_data = anims[_current_anim_type]
	var frame_x = _current_frame * frame_size.x
	var frame_y = anim_data.row * frame_size.y
	sprite.region_rect = Rect2(frame_x, frame_y, frame_size.x, frame_size.y)


func setup_shadow() -> void:
	"""Create simple shadow under wolf"""
	shadow_sprite = Sprite2D.new()
	shadow_sprite.name = "Shadow"

	# Create oval shadow texture (elongated for side view)
	var img = Image.create(50, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Draw oval shadow
	var center = Vector2(25, 8)
	for x in range(50):
		for y in range(16):
			var dist = Vector2((x - center.x) * 0.7, (y - center.y) * 2).length()
			if dist < 14:
				var alpha = 0.4 * (1.0 - dist / 14.0)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))

	var tex = ImageTexture.create_from_image(img)
	shadow_sprite.texture = tex
	shadow_sprite.position = Vector2(0, 20)  # Moved up 10px
	shadow_sprite.z_index = -1
	add_child(shadow_sprite)


func _update_shadow_for_direction() -> void:
	"""Scale shadow based on facing direction - wider for side views"""
	if not shadow_sprite:
		return
	if _current_dir == "left" or _current_dir == "right":
		shadow_sprite.scale = Vector2(1.4, 1.0)  # Elongated for side view
	else:
		shadow_sprite.scale = Vector2(1.0, 1.0)  # Normal for front/back


func setup_health_bar() -> void:
	"""Create health bar UI using the standard HealthBar scene (like skeletons)"""
	var health_bar_scene = preload("res://scenes/ui/health_bar.tscn")
	health_bar = health_bar_scene.instantiate()
	health_bar.name = "HealthBar"
	add_child(health_bar)

	# Set custom offset for wolf size
	if health_bar.has_method("set_custom_offset"):
		health_bar.set_custom_offset(45.0)

	# Set the wolf name (no level indicator)
	var wolf_name = "Dire Wolf"
	if is_alpha_dire_wolf:
		wolf_name = "Alpha Dire Wolf"
	elif pack_alpha:
		wolf_name = "⍺ Dire Wolf"

	if health_bar.has_method("set_player_name"):
		health_bar.set_player_name(wolf_name)

	# Set name color using con system (based on player level difference)
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var player_level = 1
	if player and player.has_method("get_level"):
		player_level = player.get_level()
	elif CharacterStats:
		player_level = CharacterStats.level

	var name_color = get_con_color(player_level)
	if is_alpha_dire_wolf:
		name_color = Color(0.8, 0.4, 1.0)  # Purple for rare (overrides con)
	if health_bar.has_method("set_name_color"):
		health_bar.set_name_color(name_color)

	# Update health display
	if health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	health_bar.visible = false  # Hidden until damaged


func get_con_color(player_level: int) -> Color:
	"""Get con (consider) color based on level difference with player
	Classic MMO con system:
	- Gray: 6+ levels below (trivial)
	- Green: 3-5 levels below (easy)
	- Blue: 1-2 levels below (moderate)
	- White: Same level (even match)
	- Yellow: 1-2 levels above (challenging)
	- Orange: 3-4 levels above (difficult)
	- Red: 5+ levels above (deadly)
	"""
	var level_diff = enemy_level - player_level

	if level_diff <= -6:
		return Color(0.6, 0.6, 0.6)  # Gray (trivial)
	elif level_diff <= -3:
		return Color(0.2, 1.0, 0.2)  # Green (easy)
	elif level_diff <= -1:
		return Color(0.4, 0.6, 1.0)  # Blue (moderate)
	elif level_diff == 0:
		return Color(1.0, 1.0, 1.0)  # White (even)
	elif level_diff <= 2:
		return Color(1.0, 1.0, 0.0)  # Yellow (challenging)
	elif level_diff <= 4:
		return Color(1.0, 0.6, 0.0)  # Orange (difficult)
	else:
		return Color(1.0, 0.2, 0.2)  # Red (deadly)


func setup_click_area() -> void:
	"""Create click detection area"""
	var area = Area2D.new()
	area.name = "Area2D"
	area.input_pickable = true

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	area.add_child(shape)

	area.input_event.connect(_on_click_area_input)
	add_child(area)


func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	"""Handle click on wolf"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_corpse:
			emit_signal("corpse_clicked", self)
		else:
			# Target this enemy
			var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
			if player and player.has_method("set_target"):
				player.set_target(self)


func _process(delta: float) -> void:
	"""Process loop - handles corpse state"""
	if is_corpse:
		_process_corpse(delta)


func play_animation(anim_name: String) -> void:
	"""Play an animation - format: 'type_direction' e.g. 'walk_down', 'attack_left'"""
	# Always track animation for server sync (even without sprite on dedicated server)
	current_animation = anim_name

	if not sprite:
		return

	# Parse animation name (e.g., "walk_down" -> type="walk", dir="down")
	var parts = anim_name.split("_")
	if parts.size() < 2:
		# Handle simple names like "die" - use current direction
		_set_animation_type(anim_name)
		return

	var anim_type = parts[0]  # walk, run, attack, die, howl, idle
	var direction = parts[1]  # left, right, up, down

	# Set idle flag based on animation type
	if anim_type == "idle":
		_is_idle = true
		anim_type = "walk"  # idle uses walk sprite sheet
	else:
		_is_idle = false  # Resume animation for walk/run/attack

	# Set direction and animation type
	_set_direction(direction)
	_set_animation_type(anim_type)


func update_animation_for_direction(direction: Vector2) -> void:
	"""Update animation based on movement direction"""
	if direction.length() < 0.1:
		# Idle - pause animation on current frame
		_is_idle = true
		# Track idle animation for server sync
		current_animation = "idle_" + current_direction
		return

	# Moving - resume animation
	_is_idle = false

	# Determine facing direction with hysteresis to prevent diagonal flickering
	# Only change direction if the new axis is significantly stronger (30% threshold)
	var abs_x = abs(direction.x)
	var abs_y = abs(direction.y)
	var threshold = 1.3  # 30% stronger to switch

	var new_direction: String
	var is_currently_horizontal = current_direction in ["left", "right"]

	if is_currently_horizontal:
		# Currently facing left/right - only switch to up/down if y is significantly larger
		if abs_y > abs_x * threshold:
			new_direction = "down" if direction.y > 0 else "up"
		else:
			new_direction = "right" if direction.x > 0 else "left"
	else:
		# Currently facing up/down - only switch to left/right if x is significantly larger
		if abs_x > abs_y * threshold:
			new_direction = "right" if direction.x > 0 else "left"
		else:
			new_direction = "down" if direction.y > 0 else "up"

	current_direction = new_direction

	# Set direction (swaps sprite sheet)
	_set_direction(current_direction)

	# Set animation type
	var anim_type = "run" if is_running else "walk"
	_set_animation_type(anim_type)

	# Track animation for server sync
	current_animation = anim_type + "_" + current_direction


func take_damage(damage: float, is_crit: bool = false, is_weakpoint_hit: bool = false) -> void:
	"""Handle taking damage (matches Enemy.gd signature)"""
	if is_dying or is_corpse:
		return

	current_health -= damage
	emit_signal("damage_taken", damage, is_crit)

	# Show health bar and update it
	if health_bar:
		health_bar.visible = true
		if health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

	# Flash red (preserve alpha dire wolf tint)
	if sprite:
		var flash_color = Color(1, 0.3, 0.3) if not is_alpha_dire_wolf else Color(0.8, 0.2, 0.4)
		sprite.modulate = flash_color
		var tween = create_tween()
		var restore_color = original_modulate if not is_alpha_dire_wolf else Color(0.4, 0.35, 0.5, 1.0)
		tween.tween_property(sprite, "modulate", restore_color, 0.2)

	# NOTE: Combat text is spawned by PlayerCombat.apply_damage_with_feedback()
	# via AttackFeedbackSystem.spawn_damage_number() - do NOT spawn here to avoid duplicates

	# Play wolf hurt sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_hurt_sound(global_position, -10.0)

	# 🎮 Combat juice - hitstop on weakpoint hits only
	if is_weakpoint_hit:
		var combat_juice = get_node_or_null("/root/CombatJuice")
		if combat_juice:
			combat_juice.on_weakpoint()

	# 💥 Stagger shake on hit
	play_hurt_stagger()

	if current_health <= 0:
		die()

func play_hurt_stagger() -> void:
	"""Quick jolt for stagger feedback - tight, not bouncy"""
	if is_dying or is_corpse:
		return

	# Kill any existing stagger tween to prevent bouncy overlap
	if _stagger_tween and _stagger_tween.is_valid():
		_stagger_tween.kill()

	# Tight jolt and snap back - single sharp movement
	var original_pos = position
	_stagger_tween = create_tween()
	_stagger_tween.tween_property(self, "position", original_pos + Vector2(3, -1), 0.02).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_stagger_tween.tween_property(self, "position", original_pos, 0.04).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func die() -> void:
	"""Handle wolf death (matches Enemy.gd death flow)"""
	if is_dying:
		if OS.is_debug_build():
			print("🐺 [Wolf.die] Already dying, returning early - name: %s" % name)
		return
	is_dying = true

	if OS.is_debug_build():
		var is_server = multiplayer.has_multiplayer_peer() and multiplayer.is_server()
		print("🐺 [Wolf.die] Starting death - name: %s, is_server: %s" % [name, is_server])

	# Clean up crit window state
	if in_crit_window or _crit_window_transitioning:
		in_crit_window = false
		_crit_window_transitioning = false
		if _grow_tween and _grow_tween.is_valid():
			_grow_tween.kill()
			_grow_tween = null
		if sprite:
			sprite.scale = Vector2(1.25, 1.25)  # Wolf's normal scale
			sprite.modulate = Color.WHITE
		z_index = 0

	# DEDICATED SERVER: Skip visual/audio operations
	var is_dedicated_server = "--server" in OS.get_cmdline_user_args()

	# Clean up weakpoints - just queue_free on server, let clients animate
	if is_dedicated_server:
		for wp in weakpoints:
			if is_instance_valid(wp):
				wp.queue_free()
		weakpoints.clear()
	else:
		# Client: let weakpoints finish their animations first
		var world = get_tree().current_scene
		for wp in weakpoints:
			if is_instance_valid(wp):
				var wp_pos = wp.global_position
				# Reparent to world FIRST so it survives while animating
				if wp.get_parent():
					wp.get_parent().remove_child(wp)
				world.add_child(wp)
				wp.global_position = wp_pos
				# If not already destroyed, trigger destruction animation
				if not wp.is_destroyed:
					wp.destroy()
		weakpoints.clear()

	# Grant XP to player (only on clients - server has no local player)
	if not is_dedicated_server:
		var should_grant_xp = true
		if multiplayer.has_multiplayer_peer():
			var killer_id = get_meta("killer_peer_id", -1)
			should_grant_xp = (killer_id == multiplayer.get_unique_id())

		if should_grant_xp:
			var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
			if player and player.has_method("gain_experience"):
				player.gain_experience(xp_reward)
				print("🐺 Wolf killed! Granting %d XP" % xp_reward)
				# Show world-space XP text floating up from mob
				var game_world = get_tree().get_first_node_in_group("game_world")
				if game_world:
					CombatText.create_xp(xp_reward, global_position, game_world)

			# Forged weapon stats: track kill for equipped forged weapons
			if player and player.has_node("PlayerCombat"):
				var combat_system = player.get_node("PlayerCombat")
				if combat_system.has_method("track_enemy_killed"):
					var is_elite_enemy = is_in_group("elite") or is_in_group("guardian")
					var is_boss_enemy = is_in_group("boss")
					combat_system.track_enemy_killed("wolf", is_elite_enemy, is_boss_enemy)

	# Store gold in corpse
	if corpse_gold == 0:
		corpse_gold = gold_drop

	# Skip visual/audio on dedicated server
	if not is_dedicated_server:
		# Play wolf death sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_wolf_death_sound(global_position, -8.0)

		# Play death animation - keep _is_idle false so it animates
		_is_idle = false
		_set_animation_type("die")
		_current_frame = 0
		_update_sprite_region()

		# Wait for death animation (4 frames at 8fps = 0.5s)
		await get_tree().create_timer(0.5).timeout
		if not is_instance_valid(self):
			return

		# Stop on last death frame
		_is_idle = true
		var is_side = (_current_dir == "left" or _current_dir == "right")
		var anims = ANIMS_SIDE if is_side else ANIMS_FRONT
		if anims.has("die"):
			_current_frame = anims["die"].frames - 1
			_update_sprite_region()

	# Generate loot
	if corpse_loot.is_empty():
		corpse_loot = generate_corpse_loot()

	# Emit died signal
	died.emit()

	# Notify quest manager
	if QuestManager:
		QuestManager.on_enemy_killed("wolf", enemy_level, is_alpha_dire_wolf)

	# Become corpse
	become_corpse()


func generate_corpse_loot() -> Array:
	"""Generate loot items for this wolf corpse"""
	var loot = []

	# Roll for loot using CorpseState
	var num_items = CorpseState.roll_loot_count()

	# Alpha Dire Wolves always drop at least 1 item
	if is_alpha_dire_wolf and num_items == 0:
		num_items = 1

	for i in range(num_items):
		var item = CorpseState.roll_loot_item(is_alpha_dire_wolf, enemy_level)
		if not item.is_empty():
			if item.get("stackable", false):
				item["quantity"] = 1
			loot.append(item)

	return loot


func become_corpse() -> void:
	"""Transition wolf to corpse state (lootable)"""
	is_corpse = true

	if OS.is_debug_build():
		var is_server = multiplayer.has_multiplayer_peer() and multiplayer.is_server()
		print("🐺 [Wolf.become_corpse] Transitioning to corpse - name: %s, is_server: %s, gold: %d, loot_items: %d" % [
			name, is_server, corpse_gold, corpse_loot.size()
		])
		print("🐺 [Wolf.become_corpse] corpse_clicked signal connections: %d" % corpse_clicked.get_connections().size())

	# Disable health bar
	if health_bar:
		health_bar.visible = false

	# Change collision layers
	collision_layer = 8  # Corpse layer
	collision_mask = 0

	# Change groups
	remove_from_group(Constants.GROUP_ENEMIES)
	remove_from_group("wolves")
	add_to_group("corpses")

	# Add loot indicator if has gold/items (client-only - creates looping tweens)
	if not _is_server_mode and (corpse_gold > 0 or corpse_loot.size() > 0):
		add_loot_indicator()
		if OS.is_debug_build():
			print("🐺 [Wolf.become_corpse] Added loot indicator - gold: %d, items: %d" % [corpse_gold, corpse_loot.size()])

	# Darken sprite
	if sprite:
		sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)

	# Hide shadow
	if shadow_sprite:
		shadow_sprite.visible = false


var loot_indicator: Node2D = null
var loot_prompt: Label = null


func add_loot_indicator() -> void:
	"""Add shiny sparkle effect (WoW-style) - matches Enemy.gd"""
	if loot_indicator:
		return

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10

	var sparkle_positions = [
		Vector2(-3, -5),
		Vector2(3, -5),
		Vector2(-2, 0),
		Vector2(2, 0)
	]

	for i in range(sparkle_positions.size()):
		var sparkle = _create_sparkle()
		sparkle.position = sparkle_positions[i]
		loot_indicator.add_child(sparkle)
		_animate_sparkle(sparkle, i * 0.2)

	add_child(loot_indicator)


func _create_sparkle() -> Polygon2D:
	"""Create 4-pointed star sparkle"""
	var sparkle = Polygon2D.new()
	var size = 6.0
	sparkle.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(-1, -1),
		Vector2(-size, 0),
		Vector2(-1, 1),
		Vector2(0, size),
		Vector2(1, 1),
		Vector2(size, 0),
		Vector2(1, -1)
	])
	sparkle.color = Color(1.0, 1.0, 0.8, 0.9)
	return sparkle


func _animate_sparkle(sparkle: Polygon2D, delay: float) -> void:
	"""Animate sparkle floating up"""
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(sparkle):
		return

	var start_pos = sparkle.position
	var tween = create_tween().set_loops()
	tween.tween_property(sparkle, "position:y", start_pos.y - 20, 1.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.5, 1.5)
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.9, 0.0)
	tween.parallel().tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.5)


func _process_corpse(delta: float) -> void:
	"""Handle corpse state - loot prompt visibility"""
	if not is_corpse:
		return

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		if loot_prompt:
			loot_prompt.visible = false
		return

	var distance = global_position.distance_to(player.global_position)
	var loot_range = 100.0

	if distance <= loot_range and (corpse_gold > 0 or corpse_loot.size() > 0) and not loot_ui_open:
		player_in_loot_range = true
		if not loot_prompt:
			_create_loot_prompt()
		loot_prompt.visible = true
		_update_loot_prompt_position()
	else:
		player_in_loot_range = false
		if loot_prompt:
			loot_prompt.visible = false


func _create_loot_prompt() -> void:
	"""Create [F] Loot prompt"""
	if loot_prompt:
		return

	var canvas = CanvasLayer.new()
	canvas.name = "LootPromptCanvas"
	canvas.layer = 50
	add_child(canvas)

	loot_prompt = Label.new()
	loot_prompt.name = "LootPrompt"
	loot_prompt.text = "[F] Loot"
	loot_prompt.add_theme_font_size_override("font_size", 16)
	loot_prompt.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))
	loot_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	loot_prompt.add_theme_constant_override("outline_size", 2)
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_prompt.visible = false
	canvas.add_child(loot_prompt)


func _update_loot_prompt_position() -> void:
	"""Position loot prompt above corpse"""
	if not loot_prompt:
		return

	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	var prompt_world_pos = global_position + Vector2(0, -50)
	var screen_pos = get_viewport().get_canvas_transform() * prompt_world_pos
	loot_prompt.position = screen_pos - Vector2(loot_prompt.size.x / 2, 0)


func _unhandled_input(event: InputEvent) -> void:
	"""Handle F key for looting"""
	if not is_corpse or not player_in_loot_range:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		open_loot_ui()
		get_viewport().set_input_as_handled()


func has_corpse_loot() -> bool:
	"""Check if corpse has any lootable items or gold remaining"""
	return not corpse_loot.is_empty() or corpse_gold > 0


func get_nearby_corpses(radius: float) -> Array:
	"""Find all corpses within radius for AOE looting"""
	var nearby = []
	var all_corpses = get_tree().get_nodes_in_group("corpses")

	for node in all_corpses:
		if node == self:
			continue  # Skip self

		# Check if valid corpse and within radius
		if is_instance_valid(node) and node.global_position.distance_to(global_position) <= radius:
			nearby.append(node)

	return nearby


func check_if_looted_empty() -> void:
	"""Called when items are taken - check if corpse is now empty"""
	if corpse_loot.is_empty() and corpse_gold == 0:
		# Remove loot indicator
		if loot_indicator:
			loot_indicator.queue_free()
			loot_indicator = null

		# Hide loot prompt
		if loot_prompt:
			loot_prompt.queue_free()
			loot_prompt = null

		# Emit signal
		corpse_looted_empty.emit(self)

		# Quick fade out
		graceful_despawn()


func graceful_despawn() -> void:
	"""Gradual fade out for fully looted corpses"""
	# Disable any remaining interactions
	if has_node("Area2D"):
		var area = get_node("Area2D")
		area.monitoring = false
		area.monitorable = false

	# Fade out over 1.5 seconds
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	tween.tween_property(self, "scale", Vector2(0.7, 0.7), 1.5)
	tween.tween_property(self, "position:y", position.y + 10, 1.5)
	await tween.finished

	if is_instance_valid(self):
		queue_free()


func open_loot_ui() -> void:
	"""Open loot UI for this corpse"""
	if corpse_gold == 0 and corpse_loot.is_empty():
		return

	# Check if signal is connected
	var connection_count = corpse_clicked.get_connections().size()

	if connection_count > 0:
		corpse_clicked.emit(self)
	else:
		# Fallback: directly create loot UI if signal not connected
		var game_world = get_tree().current_scene
		if game_world and game_world.has_method("_on_corpse_clicked"):
			game_world._on_corpse_clicked(self)


func _get_local_player() -> Node:
	"""Get the local player"""
	if cached_player and is_instance_valid(cached_player):
		return cached_player

	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	if players.size() > 0:
		cached_player = players[0]
		return players[0]
	return null


func get_display_name() -> String:
	"""Get display name for UI"""
	if is_alpha_dire_wolf:
		return "Alpha Dire Wolf"
	elif pack_alpha:
		return "⍺ Dire Wolf"
	return "Dire Wolf"


func get_enemy_type() -> String:
	return "wolf"


# ═══════════════════════════════════════════════════════════════════════════════
# CRIT WINDOW & WEAKPOINT SYSTEM (matches Enemy.gd)
# ═══════════════════════════════════════════════════════════════════════════════

var _crit_window_transitioning: bool = false
var _grow_tween: Tween = null
var _stagger_tween: Tween = null  # Track stagger tween to prevent bouncy overlaps


func grow_for_crit_window(_difficulty: float = 1.0) -> void:
	"""Visual effect: grow sprite and spawn weakpoints (called by CritWindowManager)"""
	if is_dying or in_crit_window or _crit_window_transitioning:
		return

	_crit_window_transitioning = true
	in_crit_window = true

	# Brighten sprite slightly for crit window
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)

	# Scale up sprite
	var base_scale = Vector2(1.25, 1.25)  # Wolf's normal sprite scale
	var target_scale = base_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER

	if sprite:
		_grow_tween = create_tween()
		_grow_tween.tween_property(sprite, "scale", target_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
		z_index = Constants.CRIT_WINDOW_Z_INDEX
		await _grow_tween.finished
		_grow_tween = null

	if in_crit_window and is_instance_valid(self):
		spawn_weakpoints()

	_crit_window_transitioning = false


func spawn_weakpoints() -> void:
	"""Spawn clickable weakpoints on the wolf (red circles)"""
	if is_dying or is_corpse:
		return

	# Number of weakpoints based on player level
	var player_level = CharacterStats.level
	var num_weakpoints = 1
	if player_level >= 21:
		num_weakpoints = 3
	elif player_level >= 11:
		num_weakpoints = 2

	# Wolf sprite bounds (smaller than skeleton)
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_width = 40.0 * sprite_scale.x
	var sprite_height = 30.0 * sprite_scale.y

	# Define weakpoint positions (spread across body)
	var positions = [
		Vector2(0, -sprite_height * 0.3),      # Head
		Vector2(-sprite_width * 0.3, 0),       # Left flank
		Vector2(sprite_width * 0.3, 0),        # Right flank
	]

	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(min(num_weakpoints, positions.size())):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		weakpoint.color_theme = "blood"  # Red color for wolves
		weakpoint.position = positions[i]
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 2.5
		weakpoint.rotation = randf_range(-PI, PI)

		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed)

		add_child(weakpoint)
		weakpoints.append(weakpoint)
		weakpoint_spawned.emit(weakpoint)


func shrink_after_crit_window() -> void:
	"""Shrink sprite back to normal after crit window ends"""
	if not in_crit_window:
		return

	in_crit_window = false

	# Wait for any grow tween to finish
	if _grow_tween and _grow_tween.is_running():
		await _grow_tween.finished

	# Restore sprite
	if sprite:
		var restore_color = Color(0.4, 0.35, 0.5, 1.0) if is_alpha_dire_wolf else original_modulate
		sprite.modulate = restore_color

		var shrink_tween = create_tween()
		shrink_tween.tween_property(sprite, "scale", Vector2(1.25, 1.25), Constants.CRIT_WINDOW_SCALE_DURATION)
		z_index = 0

	# Clear weakpoints
	for wp in weakpoints:
		if is_instance_valid(wp):
			wp.queue_free()
	weakpoints.clear()


func _on_weakpoint_hit(weakpoint) -> void:
	"""Handle weakpoint being clicked"""
	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER
	take_damage(crit_damage, true, true)


func _on_weakpoint_destroyed(weakpoint) -> void:
	"""Handle weakpoint destruction"""
	weakpoint_destroyed.emit(weakpoint)


func get_crit_window_weakpoint_count() -> int:
	"""Returns number of weakpoints for this crit window"""
	if weakpoints.size() > 0:
		return weakpoints.size()
	var player_level = CharacterStats.level
	if player_level >= 21:
		return 3
	elif player_level >= 11:
		return 2
	return 1


# ═══════════════════════════════════════════════════════════════════════════════
# AI BEHAVIOR
# ═══════════════════════════════════════════════════════════════════════════════

# Aggro properties (similar to skeleton but slightly increased range)
const BASE_DETECTION_RANGE: float = 180.0  # Base range at which wolf detects player (skeleton: 150)
const ATTACK_RANGE: float = 60.0  # Range at which wolf attacks (matches skeleton)
const LOSE_INTEREST_RANGE: float = 600.0  # Range at which wolf gives up chase (leash)
const CHAIN_AGGRO_RANGE: float = 150.0  # Pack alerts nearby wolves (skeleton: 100)
const WANDER_RADIUS: float = 150.0  # How far wolves wander from spawn
const WANDER_INTERVAL_MIN: float = 2.0  # Min time between wander direction changes
const WANDER_INTERVAL_MAX: float = 5.0  # Max time between wander direction changes
const AMBIENT_HOWL_INTERVAL_MIN: float = 30.0  # Min seconds between ambient howl attempts
const AMBIENT_HOWL_INTERVAL_MAX: float = 90.0  # Max seconds between ambient howl attempts
const AMBIENT_HOWL_CHANCE: float = 0.15  # 15% chance when timer fires (only pack alphas)

# Pack behavior constants (SIMPLIFIED)
const PACK_FOLLOW_DISTANCE: float = 180.0  # Followers stay within this distance of alpha (wider spread)
const PACK_TELEPORT_DISTANCE: float = 400.0  # If further than this, teleport to alpha
const PACK_MOVE_SPEED: float = 100.0  # Pack movement speed
const PACK_DIRECTION_CHANGE_MIN: float = 5.0  # Min seconds before alpha changes direction
const PACK_DIRECTION_CHANGE_MAX: float = 15.0  # Max seconds before alpha changes direction
const PACK_SEPARATION_DISTANCE: float = 80.0  # Min distance between pack members (increased)
const PACK_SEPARATION_FORCE: float = 120.0  # How strongly wolves push apart (increased)

var target_player: Node = null
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 1.5
var _has_alerted_pack: bool = false  # Prevent chain aggro spam
var _was_attacked: bool = false  # Track if wolf was hit (for ranged aggro)

# Per-wolf variation (set in _ready)
var _detection_range: float = BASE_DETECTION_RANGE
var _ai_offset: float = 0.0  # Desync AI updates
var _spawn_position: Vector2 = Vector2.ZERO  # Where wolf spawned (for wandering)
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _is_wandering: bool = false
var _wander_stuck_timer: float = 0.0  # Timeout if can't reach target
var _ambient_howl_timer: float = 0.0  # Timer for ambient howls while idling

# Simple pack state
var _pack_alpha_ref: Wolf = null  # Reference to pack alpha (for followers)
var _pack_move_direction: Vector2 = Vector2.ZERO  # Current movement direction (alpha only)
var _pack_direction_timer: float = 0.0  # Time until next direction change (alpha only)
var _pack_is_moving: bool = false  # Is the pack currently moving?

# Per-wolf individuality (makes pack feel organic, not robotic)
var _individual_speed_mult: float = 1.0  # Each wolf moves slightly different speed
var _individual_direction_offset: float = 0.0  # Each wolf wanders slightly off-course
var _individual_pause_timer: float = 0.0  # Wolves occasionally pause independently
var _individual_pause_chance: float = 0.0  # How likely to pause (varies per wolf)


func _init_ai_variation() -> void:
	"""Initialize per-wolf AI variation to desync pack behavior"""
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# Vary detection range slightly (±20px)
	_detection_range = BASE_DETECTION_RANGE + rng.randf_range(-20, 20)

	# Randomize starting animation frame
	_current_frame = rng.randi_range(0, 4)

	# Pack alphas start with a random direction timer
	if pack_alpha:
		_pack_direction_timer = randf_range(PACK_DIRECTION_CHANGE_MIN, PACK_DIRECTION_CHANGE_MAX)

	# Random initial wander timer
	_wander_timer = rng.randf_range(0, WANDER_INTERVAL_MAX)

	# Random initial ambient howl timer (staggered so wolves don't all howl at once)
	_ambient_howl_timer = rng.randf_range(AMBIENT_HOWL_INTERVAL_MIN, AMBIENT_HOWL_INTERVAL_MAX)

	# Per-wolf individuality - each wolf has its own personality
	_individual_speed_mult = rng.randf_range(0.7, 1.15)  # Some wolves faster/slower
	_individual_direction_offset = rng.randf_range(-0.6, 0.6)  # Wander off-course slightly
	_individual_pause_chance = rng.randf_range(0.02, 0.08)  # 2-8% chance to pause each update
	_individual_pause_timer = rng.randf_range(0, 2.0)  # Stagger initial pauses

	# Store spawn position for wandering (deferred to ensure position is set)
	call_deferred("_set_spawn_position")


func _set_spawn_position() -> void:
	"""Set spawn position after node is fully in tree with correct position"""
	_spawn_position = global_position
	_wander_target = _spawn_position  # Start at spawn


func _physics_process(delta: float) -> void:
	if is_dying or is_corpse:
		return

	# CLIENT: Don't run AI - server controls movement and animation
	# Clients receive position/animation via NetworkEnemyManager sync
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Don't move while howling
	if _is_howling:
		velocity = Vector2.ZERO
		return

	# Update attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Update wander timer
	_wander_timer -= delta

	# Find player if not targeting
	if not is_instance_valid(target_player):
		target_player = _get_local_player()

	if not target_player:
		# No player - wander around spawn point
		_do_wander_behavior(delta)
		return

	var distance_to_player = global_position.distance_to(target_player.global_position)
	var direction_to_player = (target_player.global_position - global_position).normalized()

	# Lose interest if player too far
	if distance_to_player > LOSE_INTEREST_RANGE:
		# Only lose interest if we weren't attacked from range
		# If we were shot, keep chasing until we attack or they escape further
		if not _was_attacked:
			target_player = null
			is_running = false
			_has_alerted_pack = false  # Reset so pack can be alerted again later
			_do_wander_behavior(delta)
			return
		# If attacked from range but beyond LOSE_INTEREST, use extended chase range
		elif distance_to_player > LOSE_INTEREST_RANGE * 2.5:  # 1500px max chase when attacked
			target_player = null
			is_running = false
			_has_alerted_pack = false
			_was_attacked = false  # Only reset after truly escaping
			_do_wander_behavior(delta)
			return

	# Chase if: in detection range OR was attacked (ranged weapons trigger chase from any distance)
	if (distance_to_player <= _detection_range or _was_attacked) and distance_to_player > ATTACK_RANGE:
		_is_wandering = false
		is_running = true
		# Alert pack members on first detection
		_trigger_chain_aggro()
		var speed = BASE_SPEED * RUN_SPEED_MULT
		velocity = direction_to_player * speed
		move_and_slide()
		update_animation_for_direction(direction_to_player)

	# In attack range - attack!
	elif distance_to_player <= ATTACK_RANGE:
		_is_wandering = false
		is_running = false
		velocity = Vector2.ZERO

		if attack_cooldown <= 0 and not is_attacking:
			perform_attack(target_player, direction_to_player)

	# Outside detection but inside lose interest - wander but face player occasionally
	elif distance_to_player > _detection_range:
		is_running = false
		_do_wander_behavior(delta)


func _do_wander_behavior(delta: float) -> void:
	"""Simplified wander/pack behavior - wolves stay together naturally"""
	# Don't wander until spawn position is set
	if _spawn_position == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	# Ambient howl check (only pack alphas howl while wandering)
	if pack_alpha or is_alpha_dire_wolf:
		_ambient_howl_timer -= delta
		if _ambient_howl_timer <= 0:
			_ambient_howl_timer = randf_range(AMBIENT_HOWL_INTERVAL_MIN, AMBIENT_HOWL_INTERVAL_MAX)
			if randf() < AMBIENT_HOWL_CHANCE:
				var howl_type = "alpha" if is_alpha_dire_wolf else ("pack" if randf() < 0.4 else "distant")
				_try_spawn_howl(howl_type)

	# === PACK ALPHA BEHAVIOR ===
	if pack_alpha:
		_do_alpha_wander(delta)
		return

	# === PACK FOLLOWER BEHAVIOR ===
	if _pack_alpha_ref and is_instance_valid(_pack_alpha_ref):
		_do_follower_behavior(delta)
		return

	# === SOLO WOLF WANDER (no pack) ===
	_do_solo_wander(delta)


func _do_alpha_wander(delta: float) -> void:
	"""Alpha wolf picks random directions and leads the pack"""
	_pack_direction_timer -= delta

	# Time to pick a new direction or stop
	if _pack_direction_timer <= 0:
		_pack_direction_timer = randf_range(PACK_DIRECTION_CHANGE_MIN, PACK_DIRECTION_CHANGE_MAX)

		# 40% chance to rest, 60% chance to move in new direction
		if randf() < 0.4:
			_pack_is_moving = false
			_pack_move_direction = Vector2.ZERO
		else:
			_pack_is_moving = true
			# Pick random direction, biased to stay near spawn
			var to_spawn = (_spawn_position - global_position)
			var dist_from_spawn = to_spawn.length()

			if dist_from_spawn > WANDER_RADIUS * 2:
				# Too far from spawn, head back
				_pack_move_direction = to_spawn.normalized()
			else:
				# Random direction with slight bias toward spawn
				var random_angle = randf() * TAU
				var random_dir = Vector2(cos(random_angle), sin(random_angle))
				if dist_from_spawn > WANDER_RADIUS:
					# Blend toward spawn
					_pack_move_direction = (random_dir + to_spawn.normalized() * 0.5).normalized()
				else:
					_pack_move_direction = random_dir

	# Calculate separation force (alpha also avoids clumping)
	var separation = _calculate_separation_force()

	# Move or idle
	if _pack_is_moving and _pack_move_direction != Vector2.ZERO:
		velocity = _pack_move_direction * PACK_MOVE_SPEED + separation
		is_running = false
		move_and_slide()
		update_animation_for_direction(velocity.normalized() if velocity.length() > 10 else _pack_move_direction)
	else:
		# Even when idle, apply separation
		if separation.length() > 5:
			velocity = separation
			move_and_slide()
			update_animation_for_direction(separation.normalized())
		else:
			velocity = Vector2.ZERO
			update_animation_for_direction(Vector2.ZERO)


func _do_follower_behavior(delta: float) -> void:
	"""Followers stay near alpha but move with individual personality"""
	var alpha = _pack_alpha_ref
	var dist_to_alpha = global_position.distance_to(alpha.global_position)

	# Teleport if way too far (prevents getting stuck/lost)
	if dist_to_alpha > PACK_TELEPORT_DISTANCE:
		_teleport_near_alpha()
		return

	# Individual pause behavior - wolves occasionally stop to sniff/look around
	_individual_pause_timer -= delta
	if _individual_pause_timer <= 0:
		# Roll for pause
		if randf() < _individual_pause_chance:
			_individual_pause_timer = randf_range(1.0, 3.0)  # Pause for 1-3 seconds
			velocity = Vector2.ZERO
			update_animation_for_direction(Vector2.ZERO)
			return
		else:
			_individual_pause_timer = randf_range(0.5, 1.5)  # Check again soon

	# Calculate separation force from nearby wolves
	var separation = _calculate_separation_force()

	# If close enough, loosely follow alpha's behavior
	if dist_to_alpha < PACK_FOLLOW_DISTANCE:
		# Stay with pack - move in similar direction as alpha (but not identical)
		if alpha._pack_is_moving and alpha._pack_move_direction != Vector2.ZERO:
			# Each wolf has its own direction offset (persistent personality)
			var my_direction = alpha._pack_move_direction.rotated(_individual_direction_offset)
			# Add additional random drift that changes over time
			my_direction = my_direction.rotated(randf_range(-0.2, 0.2))

			# Each wolf moves at its own speed
			var my_speed = PACK_MOVE_SPEED * _individual_speed_mult
			var base_velocity = my_direction * my_speed

			# Apply separation force
			velocity = base_velocity + separation
			is_running = false
			move_and_slide()
			update_animation_for_direction(velocity.normalized() if velocity.length() > 10 else my_direction)
		else:
			# Pack is resting - apply separation to spread out, maybe wander a tiny bit
			if separation.length() > 5:
				velocity = separation
				move_and_slide()
				update_animation_for_direction(separation.normalized())
			elif randf() < 0.01:  # 1% chance to do a small independent wander
				var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
				velocity = random_dir * PACK_MOVE_SPEED * 0.3
				move_and_slide()
				update_animation_for_direction(random_dir)
			else:
				velocity = Vector2.ZERO
				update_animation_for_direction(Vector2.ZERO)
	else:
		# Too far - move toward alpha (but at individual speed)
		var direction = (alpha.global_position - global_position).normalized()
		# Add slight wander to catching up
		direction = direction.rotated(randf_range(-0.15, 0.15))
		var catch_up_speed = PACK_MOVE_SPEED * 1.2 * _individual_speed_mult
		velocity = direction * catch_up_speed + separation * 0.5
		is_running = false
		move_and_slide()
		update_animation_for_direction(velocity.normalized())


func _calculate_separation_force() -> Vector2:
	"""Calculate force to push this wolf away from nearby pack members"""
	var separation = Vector2.ZERO

	for other in get_tree().get_nodes_in_group("wolves"):
		if other == self or not is_instance_valid(other):
			continue
		if other.is_dying or other.is_corpse:
			continue

		var to_other = other.global_position - global_position
		var dist = to_other.length()

		if dist < PACK_SEPARATION_DISTANCE and dist > 0:
			# Push away from nearby wolf - stronger when closer
			var push_strength = (PACK_SEPARATION_DISTANCE - dist) / PACK_SEPARATION_DISTANCE
			separation -= to_other.normalized() * PACK_SEPARATION_FORCE * push_strength

	return separation


func _teleport_near_alpha() -> void:
	"""Teleport follower to a random position near the alpha, avoiding other wolves"""
	if not _pack_alpha_ref or not is_instance_valid(_pack_alpha_ref):
		return

	var alpha_pos = _pack_alpha_ref.global_position

	# Try to find a position that doesn't overlap other wolves
	var best_pos = alpha_pos
	var best_min_dist = 0.0

	for _attempt in range(8):  # Try up to 8 random positions
		var angle = randf() * TAU
		var dist = randf_range(80, 150)  # Wider spread (was 60-100)
		var test_pos = alpha_pos + Vector2(cos(angle), sin(angle)) * dist

		# Check distance to all other wolves
		var min_dist_to_others = INF
		for other in get_tree().get_nodes_in_group("wolves"):
			if other == self or not is_instance_valid(other):
				continue
			var d = test_pos.distance_to(other.global_position)
			min_dist_to_others = min(min_dist_to_others, d)

		# Keep this position if it's the most spaced out
		if min_dist_to_others > best_min_dist:
			best_min_dist = min_dist_to_others
			best_pos = test_pos

	global_position = best_pos
	velocity = Vector2.ZERO


func _do_solo_wander(delta: float) -> void:
	"""Simple wander for wolves without a pack"""
	_wander_timer -= delta

	if _wander_timer <= 0:
		_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)

		if randf() < 0.3:
			_is_wandering = false
			_wander_target = Vector2.ZERO
		else:
			_is_wandering = true
			_wander_stuck_timer = 0.0
			var angle = randf() * TAU
			var dist = randf_range(50, WANDER_RADIUS)
			_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * dist

	if _is_wandering and _wander_target != Vector2.ZERO:
		var dist_to_target = global_position.distance_to(_wander_target)

		_wander_stuck_timer += delta
		if _wander_stuck_timer > 3.0:
			_is_wandering = false
			_wander_target = Vector2.ZERO
			_wander_stuck_timer = 0.0
			velocity = Vector2.ZERO
			return

		if dist_to_target > 20:
			var direction = (_wander_target - global_position).normalized()
			velocity = direction * BASE_SPEED * 0.4
			move_and_slide()
			update_animation_for_direction(direction)
		else:
			_is_wandering = false
			_wander_stuck_timer = 0.0
			velocity = Vector2.ZERO
			update_animation_for_direction(Vector2.ZERO)
	else:
		velocity = Vector2.ZERO
		update_animation_for_direction(Vector2.ZERO)


# ═══════════════════════════════════════════════════════════════════════════════
# PACK SETUP (simplified)
# ═══════════════════════════════════════════════════════════════════════════════

func setup_pack_formation(alpha: Wolf, _index: int) -> void:
	"""Called by spawner to link follower to alpha"""
	_pack_alpha_ref = alpha


func _trigger_chain_aggro() -> void:
	"""Alert nearby pack members when this wolf detects a player"""
	if _has_alerted_pack:
		return
	_has_alerted_pack = true

	# Play wolf aggro sound (growl/snarl)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_aggro_sound(global_position, -12.0)

	var range_squared = CHAIN_AGGRO_RANGE * CHAIN_AGGRO_RANGE
	var alerted = 0

	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		if not other is Wolf:
			continue
		if other.is_dying or other.is_corpse:
			continue

		var dist_sq = global_position.distance_squared_to(other.global_position)
		if dist_sq <= range_squared:
			# Alert this packmate
			if not other._has_alerted_pack and other.target_player == null:
				other.target_player = target_player
				other._has_alerted_pack = true
				alerted += 1
				if alerted >= 5:  # Max 5 chain alerts
					break


func perform_attack(player: Node, direction: Vector2) -> void:
	"""Perform attack on player"""
	is_attacking = true
	attack_cooldown = ATTACK_COOLDOWN_TIME

	# Determine attack animation based on direction
	var attack_anim = "attack_down"
	if abs(direction.x) > abs(direction.y):
		attack_anim = "attack_right" if direction.x > 0 else "attack_left"

	play_animation(attack_anim)

	# Play wolf attack sound (bite)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_attack_sound(global_position, -12.0)

	# Deal damage after a short delay (sync with animation)
	await get_tree().create_timer(0.3).timeout

	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= ATTACK_RANGE * 1.5:
		# Use NetworkEnemyManager for proper multiplayer damage sync
		var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
		if network_enemy_mgr and network_enemy_mgr.has_method("deal_damage_to_player"):
			var peer_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 1
			network_enemy_mgr.deal_damage_to_player(peer_id, base_damage)
		elif player.has_method("take_damage"):
			# Fallback for singleplayer
			player.take_damage(base_damage)
		# Reset _was_attacked after successfully attacking - wolf got its revenge
		_was_attacked = false

	# Wait for attack animation to finish
	await get_tree().create_timer(0.5).timeout
	is_attacking = false


func _on_damage_taken(_damage: float, _is_crit: bool) -> void:
	"""Called when wolf takes damage - enter chase mode to attack the player"""
	if is_dying or is_corpse:
		return

	# Mark as attacked so wolf chases even from outside detection range (ranged weapons)
	_was_attacked = true

	# Get local player as target (the one who hit us)
	if not is_instance_valid(target_player):
		target_player = _get_local_player()

	# Enter combat mode - start running at the player
	if target_player:
		is_running = true
		_is_wandering = false
		# Trigger pack aggro so nearby wolves also attack
		_trigger_chain_aggro()
