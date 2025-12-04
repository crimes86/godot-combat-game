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


func _ready() -> void:
	add_to_group(Constants.GROUP_ENEMIES)
	add_to_group("wolves")

	# Apply level scaling
	apply_level_scaling()

	# Create sprite with animations
	setup_sprite()

	# Create shadow
	setup_shadow()

	# Create health bar
	setup_health_bar()

	# Create click area for targeting
	setup_click_area()

	# Set collision
	collision_layer = 4  # Enemy layer
	collision_mask = 1 | 2  # Player + obstacles

	# Initialize AI variation (desync pack members)
	_init_ai_variation()

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
	max_health = Constants.ENEMY_BASE_HEALTH * pow(Constants.ENEMY_HEALTH_SCALING, enemy_level - 1) * 0.8
	current_health = max_health

	# Damage scales with level
	base_damage = 15.0 * pow(1.15, enemy_level - 1)  # 15% per level
	xp_reward = int(xp_reward_base * pow(1.2, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(1.15, enemy_level - 1))

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

	# "idle" maps to "walk" with no movement
	if anim_type == "idle":
		anim_type = "walk"

	# Set direction and animation type
	_set_direction(direction)
	_set_animation_type(anim_type)


func update_animation_for_direction(direction: Vector2) -> void:
	"""Update animation based on movement direction"""
	if direction.length() < 0.1:
		# Idle - pause animation on current frame
		_is_idle = true
		return

	# Moving - resume animation
	_is_idle = false

	# Determine facing direction
	if abs(direction.x) > abs(direction.y):
		current_direction = "right" if direction.x > 0 else "left"
	else:
		current_direction = "down" if direction.y > 0 else "up"

	# Set direction (swaps sprite sheet)
	_set_direction(current_direction)

	# Set animation type
	var anim_type = "run" if is_running else "walk"
	_set_animation_type(anim_type)


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

	# Spawn combat text
	_spawn_combat_text(damage, is_crit, is_weakpoint_hit)

	# Play wolf hurt sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_hurt_sound(global_position, -6.0)

	if current_health <= 0:
		die()


func _spawn_combat_text(damage: float, is_crit: bool, is_weakpoint: bool) -> void:
	"""Spawn floating combat text like skeletons"""
	var spawn_pos = global_position + Vector2(randf_range(-20, 20), -40)
	var parent = get_tree().current_scene

	# Use CombatText static factory methods
	if is_weakpoint:
		CombatText.create_weakpoint(damage, spawn_pos, parent)
	elif is_crit:
		CombatText.create_crit(damage, spawn_pos, parent)
	else:
		CombatText.create_normal(damage, spawn_pos, parent)


func die() -> void:
	"""Handle wolf death (matches Enemy.gd death flow)"""
	if is_dying:
		return
	is_dying = true

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

	# Clean up weakpoints - let them finish their animations first
	# Reparent them to world so they survive wolf death, then let them self-destruct
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

	# Grant XP to player
	var should_grant_xp = true
	if multiplayer.has_multiplayer_peer():
		var killer_id = get_meta("killer_peer_id", -1)
		should_grant_xp = (killer_id == multiplayer.get_unique_id())

	if should_grant_xp:
		var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player and player.has_method("gain_experience"):
			player.gain_experience(xp_reward)
			print("🐺 Wolf killed! Granting %d XP" % xp_reward)
			if NotificationManager and NotificationManager.has_method("notify_xp_gained"):
				NotificationManager.notify_xp_gained(xp_reward, "L%d %s" % [enemy_level, get_display_name()])

	# Store gold in corpse
	if corpse_gold == 0:
		corpse_gold = gold_drop

	# Play wolf death sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_death_sound(global_position, -4.0)

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

	# Add loot indicator if has gold/items
	if corpse_gold > 0 or corpse_loot.size() > 0:
		add_loot_indicator()

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

# Pack roaming/patrol constants
const ROAMING_PACK_CHANCE: float = 0.25  # 25% of packs will roam
const PATROL_REST_MIN: float = 30.0  # Min seconds resting at a site before patrol
const PATROL_REST_MAX: float = 90.0  # Max seconds resting
const PATROL_SPEED_WALK: float = 100.0  # Trotting speed
const PATROL_SPEED_RUN: float = 160.0  # Running speed (occasional bursts)
const PATROL_RUN_CHANCE: float = 0.3  # 30% chance to run instead of trot
const FORMATION_SPACING: float = 60.0  # Distance between pack members in formation

var target_player: Node = null
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 1.5
var _has_alerted_pack: bool = false  # Prevent chain aggro spam

# Per-wolf variation (set in _ready)
var _detection_range: float = BASE_DETECTION_RANGE
var _ai_offset: float = 0.0  # Desync AI updates
var _spawn_position: Vector2 = Vector2.ZERO  # Where wolf spawned (for wandering)
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _is_wandering: bool = false
var _wander_stuck_timer: float = 0.0  # Timeout if can't reach target
var _ambient_howl_timer: float = 0.0  # Timer for ambient howls while idling

# Pack roaming state (only meaningful for pack alphas)
var is_roaming_pack: bool = false  # This pack roams between ritual sites
var _patrol_state: String = "resting"  # "resting", "patrolling", "arriving"
var _patrol_target: Vector2 = Vector2.ZERO  # Current patrol destination
var _patrol_rest_timer: float = 0.0  # Time until next patrol
var _patrol_speed: float = PATROL_SPEED_WALK  # Current patrol speed
var _home_ritual_site: Vector2 = Vector2.ZERO  # Original ritual site position
var _formation_index: int = -1  # Position in pack formation (0 = alpha, 1-6 = followers)
var _pack_alpha_ref: Wolf = null  # Reference to pack alpha (for followers)


func _init_ai_variation() -> void:
	"""Initialize per-wolf AI variation to desync pack behavior"""
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	# Vary detection range slightly (±20px)
	_detection_range = BASE_DETECTION_RANGE + rng.randf_range(-20, 20)

	# Random AI update offset (0-0.5s) to desync thinking
	_ai_offset = rng.randf_range(0, 0.5)

	# Randomize starting animation frame
	_current_frame = rng.randi_range(0, 4)

	# Pack alphas decide if this is a roaming pack
	if pack_alpha:
		is_roaming_pack = randf() < ROAMING_PACK_CHANCE
		if is_roaming_pack:
			_patrol_rest_timer = randf_range(PATROL_REST_MIN, PATROL_REST_MAX)

	# Random initial wander timer
	_wander_timer = rng.randf_range(0, WANDER_INTERVAL_MAX)

	# Random initial ambient howl timer (staggered so wolves don't all howl at once)
	_ambient_howl_timer = rng.randf_range(AMBIENT_HOWL_INTERVAL_MIN, AMBIENT_HOWL_INTERVAL_MAX)

	# Store spawn position for wandering (deferred to ensure position is set)
	call_deferred("_set_spawn_position")


func _set_spawn_position() -> void:
	"""Set spawn position after node is fully in tree with correct position"""
	_spawn_position = global_position
	_wander_target = _spawn_position  # Start at spawn
	_home_ritual_site = global_position  # Remember home for roaming packs


func _physics_process(delta: float) -> void:
	if is_dying or is_corpse:
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
		target_player = null
		is_running = false
		_has_alerted_pack = false  # Reset so pack can be alerted again later
		_do_wander_behavior(delta)
		return

	# In detection range - chase!
	if distance_to_player <= _detection_range and distance_to_player > ATTACK_RANGE:
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
	"""Wander around spawn point when not chasing player"""
	# Don't wander until spawn position is set
	if _spawn_position == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	# Ambient howl check (only pack alphas howl while wandering)
	if pack_alpha or is_alpha_dire_wolf:
		_ambient_howl_timer -= delta
		if _ambient_howl_timer <= 0:
			_ambient_howl_timer = randf_range(AMBIENT_HOWL_INTERVAL_MIN, AMBIENT_HOWL_INTERVAL_MAX)
			# Roll chance and attempt howl (SoundManager handles cooldown/diminishing returns)
			if randf() < AMBIENT_HOWL_CHANCE:
				# Pick howl type - Alpha Dire always uses alpha, pack alphas randomly pick
				var howl_type: String
				if is_alpha_dire_wolf:
					howl_type = "alpha"
				else:
					# Randomly pick between distant (60%), pack (40%) for variety
					howl_type = "pack" if randf() < 0.4 else "distant"
				_try_spawn_howl(howl_type)

	# === PACK PATROL BEHAVIOR ===
	# Pack alphas of roaming packs handle patrol logic
	if pack_alpha and is_roaming_pack:
		_do_patrol_behavior(delta)
		# If patrolling, skip normal wander
		if _patrol_state == "patrolling":
			return

	# Pack members follow their alpha when patrolling
	if _pack_alpha_ref and is_instance_valid(_pack_alpha_ref) and _pack_alpha_ref._patrol_state == "patrolling":
		_follow_alpha_in_formation(delta)
		return

	# === NORMAL WANDER BEHAVIOR ===
	# Pick new wander target when timer expires
	if _wander_timer <= 0:
		_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)

		# 30% chance to stop and idle, 70% chance to pick new wander point
		if randf() < 0.3:
			_is_wandering = false
			_wander_target = Vector2.ZERO
		else:
			_is_wandering = true
			_wander_stuck_timer = 0.0  # Reset stuck timer for new target
			# Pick random point within wander radius of spawn
			var angle = randf() * TAU
			var dist = randf_range(50, WANDER_RADIUS)
			_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * dist

	if _is_wandering and _wander_target != Vector2.ZERO:
		var dist_to_target = global_position.distance_to(_wander_target)

		# Check if stuck trying to reach target
		_wander_stuck_timer += delta
		if _wander_stuck_timer > 3.0:  # Give up after 3 seconds
			_is_wandering = false
			_wander_target = Vector2.ZERO
			_wander_stuck_timer = 0.0
			velocity = Vector2.ZERO
			return

		if dist_to_target > 20:
			# Move toward wander target
			var direction = (_wander_target - global_position).normalized()
			velocity = direction * BASE_SPEED * 0.4  # Slow wander speed
			move_and_slide()
			update_animation_for_direction(direction)
		else:
			# Reached target, stop
			_is_wandering = false
			_wander_stuck_timer = 0.0
			velocity = Vector2.ZERO
			update_animation_for_direction(Vector2.ZERO)
	else:
		# Idle
		velocity = Vector2.ZERO
		update_animation_for_direction(Vector2.ZERO)


# ═══════════════════════════════════════════════════════════════════════════════
# PACK ROAMING/PATROL BEHAVIOR
# ═══════════════════════════════════════════════════════════════════════════════

func setup_pack_formation(alpha: Wolf, index: int) -> void:
	"""Called by spawner to set up pack formation references"""
	_pack_alpha_ref = alpha
	_formation_index = index
	# Inherit roaming status from alpha
	if alpha and alpha.is_roaming_pack:
		is_roaming_pack = true


func _do_patrol_behavior(delta: float) -> void:
	"""Handle pack patrol behavior (only for roaming pack alphas)"""
	if not pack_alpha or not is_roaming_pack:
		return

	match _patrol_state:
		"resting":
			# Count down rest timer
			_patrol_rest_timer -= delta
			if _patrol_rest_timer <= 0:
				# Time to patrol! Find a destination
				_start_patrol()

		"patrolling":
			# Move toward patrol target
			var dist_to_target = global_position.distance_to(_patrol_target)

			if dist_to_target < 100:
				# Arrived at destination
				_patrol_state = "arriving"
				_patrol_rest_timer = randf_range(PATROL_REST_MIN, PATROL_REST_MAX)
				_spawn_position = _patrol_target  # Update spawn position for wandering
				# Maybe howl on arrival
				if randf() < 0.4:
					_try_spawn_howl("pack")
			else:
				# Check if pack members are falling behind - alpha waits for stragglers
				var should_wait = _check_pack_stragglers()

				if should_wait:
					# Pause and wait for pack to regroup
					velocity = Vector2.ZERO
					update_animation_for_direction(Vector2.ZERO)
				else:
					# Keep moving toward target
					var direction = (_patrol_target - global_position).normalized()
					velocity = direction * _patrol_speed
					is_running = _patrol_speed > PATROL_SPEED_WALK
					move_and_slide()
					update_animation_for_direction(direction)

		"arriving":
			# Brief settling period, then back to resting
			_patrol_rest_timer -= delta
			if _patrol_rest_timer <= 0:
				_patrol_state = "resting"
				_patrol_rest_timer = randf_range(PATROL_REST_MIN, PATROL_REST_MAX)


func _start_patrol() -> void:
	"""Begin a patrol to another ritual site"""
	var destination = _find_patrol_destination()
	if destination == Vector2.ZERO:
		# No valid destination, stay put
		_patrol_rest_timer = randf_range(PATROL_REST_MIN, PATROL_REST_MAX)
		return

	_patrol_target = destination
	_patrol_state = "patrolling"

	# Decide speed - 30% chance to run
	if randf() < PATROL_RUN_CHANCE:
		_patrol_speed = PATROL_SPEED_RUN
	else:
		_patrol_speed = PATROL_SPEED_WALK

	# Howl to signal pack movement
	if randf() < 0.5:
		_try_spawn_howl("distant")


func _find_patrol_destination() -> Vector2:
	"""Find another ritual site to patrol to.
	STRONGLY prefers sites on the opposite side of the path (Y=0) to create danger for travelers."""
	# Get all wolves and find other pack alphas (they mark ritual sites)
	var cross_path_sites: Array[Vector2] = []  # Sites that require crossing the path
	var same_side_sites: Array[Vector2] = []   # Fallback sites on same side
	var my_pos = global_position
	var my_side = sign(my_pos.y)  # Which side of path we're on (path is at Y=0)

	# Patrol range - must be long enough to cross the path to other ritual sites
	const MIN_PATROL_DIST: float = 400.0   # Don't patrol to super close sites
	const MAX_PATROL_DIST: float = 8000.0  # Can patrol across entire chunk width

	for wolf in get_tree().get_nodes_in_group("wolves"):
		if not is_instance_valid(wolf) or wolf == self:
			continue
		if wolf.pack_alpha and wolf.pack_id != pack_id:
			# This is another pack's alpha - their spawn position is a ritual site
			var site_pos = wolf._spawn_position if wolf._spawn_position != Vector2.ZERO else wolf.global_position
			# Only consider sites within patrol range
			var dist = my_pos.distance_to(site_pos)
			if dist > MIN_PATROL_DIST and dist < MAX_PATROL_DIST:
				# Check if this site is on the opposite side of the path
				var site_side = sign(site_pos.y)
				if site_side != my_side and site_side != 0 and my_side != 0:
					# This site requires crossing the path - PREFERRED!
					cross_path_sites.append(site_pos)
				else:
					# Same side of path - fallback only
					same_side_sites.append(site_pos)

	# Strongly prefer cross-path destinations (90% chance if available)
	if not cross_path_sites.is_empty():
		if same_side_sites.is_empty() or randf() < 0.9:
			return cross_path_sites[randi() % cross_path_sites.size()]

	# Fall back to same-side sites
	if not same_side_sites.is_empty():
		return same_side_sites[randi() % same_side_sites.size()]

	# No good destinations, maybe return home (if it's across the path)
	if _home_ritual_site != Vector2.ZERO and my_pos.distance_to(_home_ritual_site) > 300:
		return _home_ritual_site

	return Vector2.ZERO


func _follow_alpha_in_formation(delta: float) -> void:
	"""Pack members follow their alpha in formation"""
	if not _pack_alpha_ref or not is_instance_valid(_pack_alpha_ref):
		return

	# Only follow if alpha is patrolling
	if _pack_alpha_ref._patrol_state != "patrolling":
		return

	# Calculate formation position behind alpha
	var alpha_pos = _pack_alpha_ref.global_position
	var alpha_velocity = _pack_alpha_ref.velocity

	# Get formation offset based on index (V-formation)
	var formation_offset = _get_formation_offset(_formation_index, alpha_velocity)
	var target_pos = alpha_pos + formation_offset

	var dist_to_target = global_position.distance_to(target_pos)

	if dist_to_target > 20:
		var direction = (target_pos - global_position).normalized()
		# Match alpha's speed with slight variation
		var speed = _pack_alpha_ref._patrol_speed * randf_range(0.95, 1.05)
		# Speed up if falling behind
		if dist_to_target > FORMATION_SPACING * 2:
			speed *= 1.3
		velocity = direction * speed
		is_running = speed > PATROL_SPEED_WALK
		move_and_slide()
		update_animation_for_direction(direction)
	else:
		velocity = Vector2.ZERO


func _get_formation_offset(index: int, leader_velocity: Vector2) -> Vector2:
	"""Get position offset for V-formation behind leader"""
	if leader_velocity.length() < 10:
		# Leader not moving, spread out in circle
		var angle = (index - 1) * (TAU / 6)
		return Vector2(cos(angle), sin(angle)) * FORMATION_SPACING

	# V-formation behind leader
	var back_dir = -leader_velocity.normalized()
	var side_dir = back_dir.rotated(PI / 2)

	# Alternate left/right in V shape
	var row = (index + 1) / 2  # 1,1,2,2,3,3...
	var side = 1 if index % 2 == 1 else -1  # Left, right, left, right...

	var back_offset = back_dir * (FORMATION_SPACING * row * 0.8)
	var side_offset = side_dir * (FORMATION_SPACING * row * 0.5 * side)

	return back_offset + side_offset


func _check_pack_stragglers() -> bool:
	"""Check if any pack members are too far behind - alpha should wait for them"""
	if not pack_alpha:
		return false  # Only alpha checks for stragglers

	const MAX_STRAGGLER_DISTANCE: float = 350.0  # If any member is this far, wait

	# Find all wolves in our pack
	for wolf in get_tree().get_nodes_in_group("wolves"):
		if not is_instance_valid(wolf) or wolf == self:
			continue
		if wolf.pack_id != pack_id:
			continue
		if wolf.is_dying or wolf.is_corpse:
			continue

		# Check distance from alpha (us) to this pack member
		var dist = global_position.distance_to(wolf.global_position)
		if dist > MAX_STRAGGLER_DISTANCE:
			return true  # Someone is too far behind, wait for them

	return false  # Pack is together, keep moving


func _trigger_chain_aggro() -> void:
	"""Alert nearby pack members when this wolf detects a player"""
	if _has_alerted_pack:
		return
	_has_alerted_pack = true

	# Play wolf aggro sound (growl/snarl)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_wolf_aggro_sound(global_position, -8.0)

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
		sound_manager.play_wolf_attack_sound(global_position, -8.0)

	# Deal damage after a short delay (sync with animation)
	await get_tree().create_timer(0.3).timeout

	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= ATTACK_RANGE * 1.5:
		if player.has_method("take_damage"):
			player.take_damage(base_damage)

	# Wait for attack animation to finish
	await get_tree().create_timer(0.5).timeout
	is_attacking = false
