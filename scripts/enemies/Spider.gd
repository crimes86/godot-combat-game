extends CharacterBody2D
class_name Spider

## Spider Enemy - Roaming creature that spawns in open areas
## Uses LPC spider sprite sheets (640x320, 64x64 frames)

# Network ID for multiplayer sync
var network_id: int = -1

# Enemy stats (spiders are fast and fragile)
@export var max_health: float = 60.0
@export var current_health: float = 60.0
@export var base_damage: float = 12.0

# Enemy level and progression
@export var enemy_level: int = 1
@export var xp_reward_base: int = 10
var xp_reward: int = 10
@export var gold_drop_base: int = 3
var gold_drop: int = 3

# Spider variant (1-11, determines sprite color)
var spider_variant: int = 1

# Movement (spiders are quick and erratic)
const BASE_SPEED: float = 160.0
const RUN_SPEED_MULT: float = 1.6
var current_speed: float = BASE_SPEED

# LOD tracking
var current_lod: int = 0
var lod_update_timer: float = 0.0
const LOD_UPDATE_INTERVAL: float = 0.5
const LOD_NEAR_DISTANCE: float = 1200.0
const LOD_FAR_DISTANCE: float = 2500.0

# Cached references
var cached_player: Node = null

# Animation
var sprite: Sprite2D = null
var shadow_sprite: Sprite2D = null
var current_direction: String = "down"
var is_running: bool = false
var is_attacking: bool = false

# Health bar and UI
var health_bar: Control = null

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
var loot_ui_open: bool = false

# Signals
signal weakpoint_spawned(weakpoint: Node)
signal weakpoint_destroyed(weakpoint: Node)
signal died()
signal damage_taken(damage: float, is_crit: bool)
signal corpse_clicked(corpse)
signal corpse_looted_empty(corpse)

# Spider sprite sheet: 640x320, 64x64 per frame, 10 cols x 5 rows
# Row 0: Walk down (8 frames)
# Row 1: Walk left (8 frames)
# Row 2: Walk right (8 frames)
# Row 3: Walk up (8 frames)
# Row 4: Death (4 frames)
const FRAME_SIZE = Vector2(64, 64)
const SPIDER_ANIMS = {
	"walk_down": {"row": 0, "frames": 8},
	"walk_left": {"row": 1, "frames": 8},
	"walk_right": {"row": 2, "frames": 8},
	"walk_up": {"row": 3, "frames": 8},
	"die": {"row": 4, "frames": 4},
}

var _spider_texture: Texture2D = null
var _current_anim: String = "walk_down"
var _current_frame: int = 0
var _anim_timer: Timer = null
var _is_idle: bool = false


func _ready() -> void:
	add_to_group(Constants.GROUP_ENEMIES)
	add_to_group("spiders")

	# Apply level scaling
	apply_level_scaling()

	# Setup visuals
	setup_sprite()
	setup_shadow()
	setup_health_bar()
	setup_click_area()

	# Set collision
	collision_layer = 4  # Enemy layer
	collision_mask = 1 | 2  # Player + obstacles

	# Initialize AI
	_init_ai_variation()

	# Connect damage signal to enter combat when hit (ranged weapons)
	damage_taken.connect(_on_damage_taken)

	# Start animation
	_start_animation_timer()


func apply_level_scaling() -> void:
	"""Scale stats based on enemy level - rebalanced Dec 2024"""
	# Spiders are fragile (60% of base HP) - fast but squishy
	max_health = Constants.ENEMY_BASE_HEALTH * pow(Constants.ENEMY_HEALTH_SCALING, enemy_level - 1) * 0.6
	current_health = max_health
	# Spider damage (5.8 base) - proportionally scaled with wolf (7.0)
	# Spiders hit slightly softer than wolves but are faster
	base_damage = 5.8 * pow(Constants.ENEMY_DAMAGE_SCALING, enemy_level - 1)
	xp_reward = int(xp_reward_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))


func setup_sprite() -> void:
	"""Create sprite with spider texture"""
	# Load spider variant texture
	var variant_str = "%02d" % spider_variant
	var texture_path = "res://assets/characters/enemies/spiders/spider%s.png" % variant_str
	_spider_texture = load(texture_path) as Texture2D

	if not _spider_texture:
		# Fallback to spider01
		_spider_texture = load("res://assets/characters/enemies/spiders/spider01.png") as Texture2D

	sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = _spider_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, FRAME_SIZE.x, FRAME_SIZE.y)
	sprite.scale = Vector2(1.0, 1.0)
	sprite.z_index = 5
	sprite.centered = true
	add_child(sprite)

	original_scale = sprite.scale
	original_modulate = sprite.modulate


func _start_animation_timer() -> void:
	"""Start timer for animation frame updates"""
	_anim_timer = Timer.new()
	_anim_timer.wait_time = 1.0 / 10.0  # 10 FPS
	_anim_timer.timeout.connect(_advance_frame)
	add_child(_anim_timer)
	_anim_timer.start()


func _advance_frame() -> void:
	"""Advance to next animation frame"""
	if not sprite or is_dying and _current_anim != "die" or _is_idle:
		return

	if not SPIDER_ANIMS.has(_current_anim):
		return

	var anim_data = SPIDER_ANIMS[_current_anim]
	_current_frame = (_current_frame + 1) % anim_data.frames

	var frame_x = _current_frame * FRAME_SIZE.x
	var frame_y = anim_data.row * FRAME_SIZE.y
	sprite.region_rect = Rect2(frame_x, frame_y, FRAME_SIZE.x, FRAME_SIZE.y)


func play_animation(anim_name: String) -> void:
	"""Play an animation by name"""
	if _current_anim == anim_name:
		return

	_current_anim = anim_name
	_current_frame = 0
	_is_idle = false

	if SPIDER_ANIMS.has(anim_name):
		var anim_data = SPIDER_ANIMS[anim_name]
		sprite.region_rect = Rect2(0, anim_data.row * FRAME_SIZE.y, FRAME_SIZE.x, FRAME_SIZE.y)


func update_animation_for_direction(direction: Vector2) -> void:
	"""Update animation based on movement direction"""
	if direction.length() < 0.1:
		_is_idle = true
		return

	_is_idle = false

	# Determine facing direction
	var new_anim: String
	if abs(direction.x) > abs(direction.y):
		new_anim = "walk_right" if direction.x > 0 else "walk_left"
	else:
		new_anim = "walk_down" if direction.y > 0 else "walk_up"

	if new_anim != _current_anim:
		play_animation(new_anim)


func setup_shadow() -> void:
	"""Create simple shadow under spider"""
	shadow_sprite = Sprite2D.new()
	shadow_sprite.name = "Shadow"

	var img = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var center = Vector2(20, 10)
	for x in range(40):
		for y in range(20):
			var dist = Vector2((x - center.x) * 0.8, (y - center.y) * 1.5).length()
			if dist < 12:
				var alpha = 0.35 * (1.0 - dist / 12.0)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))

	var tex = ImageTexture.create_from_image(img)
	shadow_sprite.texture = tex
	shadow_sprite.position = Vector2(0, 0)
	shadow_sprite.z_index = -1
	add_child(shadow_sprite)


func setup_health_bar() -> void:
	"""Create health bar UI"""
	var health_bar_scene = preload("res://scenes/ui/health_bar.tscn")
	health_bar = health_bar_scene.instantiate()
	health_bar.name = "HealthBar"
	add_child(health_bar)

	if health_bar.has_method("set_custom_offset"):
		health_bar.set_custom_offset(40.0)

	if health_bar.has_method("set_player_name"):
		health_bar.set_player_name("Spider")

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var player_level = CharacterStats.level if CharacterStats else 1
	var name_color = get_con_color(player_level)
	if health_bar.has_method("set_name_color"):
		health_bar.set_name_color(name_color)

	if health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	health_bar.visible = false


func get_con_color(player_level: int) -> Color:
	"""Get con color based on level difference"""
	var level_diff = enemy_level - player_level
	if level_diff <= -6:
		return Color(0.6, 0.6, 0.6)  # Gray
	elif level_diff <= -3:
		return Color(0.2, 1.0, 0.2)  # Green
	elif level_diff <= -1:
		return Color(0.4, 0.6, 1.0)  # Blue
	elif level_diff == 0:
		return Color(1.0, 1.0, 1.0)  # White
	elif level_diff <= 2:
		return Color(1.0, 1.0, 0.0)  # Yellow
	elif level_diff <= 4:
		return Color(1.0, 0.6, 0.0)  # Orange
	else:
		return Color(1.0, 0.2, 0.2)  # Red


func setup_click_area() -> void:
	"""Create click detection area"""
	var area = Area2D.new()
	area.name = "Area2D"
	area.input_pickable = true

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 35.0
	shape.shape = circle
	area.add_child(shape)

	area.input_event.connect(_on_click_area_input)
	add_child(area)


func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	"""Handle click on spider"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_corpse:
			emit_signal("corpse_clicked", self)
		else:
			var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
			if player and player.has_method("set_target"):
				player.set_target(self)


func _process(delta: float) -> void:
	if is_corpse:
		_process_corpse(delta)


# ═══════════════════════════════════════════════════════════════════════════════
# COMBAT
# ═══════════════════════════════════════════════════════════════════════════════

func take_damage(damage: float, is_crit: bool = false, is_weakpoint_hit: bool = false) -> void:
	"""Handle taking damage"""
	if is_dying or is_corpse:
		return

	current_health -= damage
	emit_signal("damage_taken", damage, is_crit)

	if health_bar:
		health_bar.visible = true
		if health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

	# Flash red
	if sprite:
		sprite.modulate = Color(1, 0.3, 0.3)
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", original_modulate, 0.2)

	# NOTE: Combat text is spawned by PlayerCombat.apply_damage_with_feedback()
	# via AttackFeedbackSystem.spawn_damage_number() - do NOT spawn here to avoid duplicates

	# Play hurt sound (use skeleton sound for now)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_skeleton_hurt_sound(global_position, -10.0)

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

	# Shake the whole spider, not just sprite
	var original_pos = position
	var stagger_tween = create_tween()
	stagger_tween.tween_property(self, "position", original_pos + Vector2(3, -1), 0.03).set_ease(Tween.EASE_OUT)
	stagger_tween.tween_property(self, "position", original_pos, 0.05).set_ease(Tween.EASE_IN)


func die() -> void:
	"""Handle spider death"""
	if is_dying:
		if OS.is_debug_build():
			print("🕷️ [Spider.die] Already dying, returning early - name: %s" % name)
		return
	is_dying = true

	if OS.is_debug_build():
		var is_server = multiplayer.has_multiplayer_peer() and multiplayer.is_server()
		print("🕷️ [Spider.die] Starting death - name: %s, is_server: %s" % [name, is_server])

	# Clean up crit window
	in_crit_window = false
	for wp in weakpoints:
		if is_instance_valid(wp):
			wp.queue_free()
	weakpoints.clear()

	# Grant XP
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("gain_experience"):
		player.gain_experience(xp_reward)
		var game_world = get_tree().get_first_node_in_group("game_world")
		if game_world:
			CombatText.create_xp(xp_reward, global_position, game_world)

	# Store gold
	if corpse_gold == 0:
		corpse_gold = gold_drop

	# Play death animation
	_is_idle = false
	play_animation("die")

	# Wait for death animation
	await get_tree().create_timer(0.4).timeout
	if not is_instance_valid(self):
		return

	# Stop on last frame
	_is_idle = true
	_current_frame = SPIDER_ANIMS["die"].frames - 1
	var frame_y = SPIDER_ANIMS["die"].row * FRAME_SIZE.y
	sprite.region_rect = Rect2(_current_frame * FRAME_SIZE.x, frame_y, FRAME_SIZE.x, FRAME_SIZE.y)

	# Generate loot
	if corpse_loot.is_empty():
		corpse_loot = generate_corpse_loot()

	died.emit()

	if QuestManager:
		QuestManager.on_enemy_killed("spider", enemy_level, false)

	become_corpse()


func generate_corpse_loot() -> Array:
	"""Generate loot items"""
	var loot = []
	var num_items = CorpseState.roll_loot_count()

	for i in range(num_items):
		var item = CorpseState.roll_loot_item(false, enemy_level)
		if not item.is_empty():
			if item.get("stackable", false):
				item["quantity"] = 1
			loot.append(item)

	return loot


func become_corpse() -> void:
	"""Transition to corpse state"""
	is_corpse = true

	if OS.is_debug_build():
		var is_server = multiplayer.has_multiplayer_peer() and multiplayer.is_server()
		print("🕷️ [Spider.become_corpse] Transitioning to corpse - name: %s, is_server: %s, gold: %d, loot_items: %d" % [
			name, is_server, corpse_gold, corpse_loot.size()
		])
		print("🕷️ [Spider.become_corpse] corpse_clicked signal connections: %d" % corpse_clicked.get_connections().size())

	if health_bar:
		health_bar.visible = false

	collision_layer = 8
	collision_mask = 0

	remove_from_group(Constants.GROUP_ENEMIES)
	remove_from_group("spiders")
	add_to_group("corpses")

	if corpse_gold > 0 or corpse_loot.size() > 0:
		add_loot_indicator()
		if OS.is_debug_build():
			print("🕷️ [Spider.become_corpse] Added loot indicator - gold: %d, items: %d" % [corpse_gold, corpse_loot.size()])

	if sprite:
		sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)

	if shadow_sprite:
		shadow_sprite.visible = false


var loot_indicator: Node2D = null
var loot_prompt: Label = null


func add_loot_indicator() -> void:
	"""Add sparkle loot indicator"""
	if loot_indicator:
		return

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10

	var positions = [Vector2(-3, -5), Vector2(3, -5), Vector2(-2, 0), Vector2(2, 0)]
	for i in range(positions.size()):
		var sparkle = _create_sparkle()
		sparkle.position = positions[i]
		loot_indicator.add_child(sparkle)
		_animate_sparkle(sparkle, i * 0.2)

	add_child(loot_indicator)


func _create_sparkle() -> Polygon2D:
	var sparkle = Polygon2D.new()
	var size = 5.0
	sparkle.polygon = PackedVector2Array([
		Vector2(0, -size), Vector2(-1, -1), Vector2(-size, 0), Vector2(-1, 1),
		Vector2(0, size), Vector2(1, 1), Vector2(size, 0), Vector2(1, -1)
	])
	sparkle.color = Color(1.0, 1.0, 0.8, 0.9)
	return sparkle


func _animate_sparkle(sparkle: Polygon2D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(sparkle):
		return

	var start_pos = sparkle.position
	var tween = create_tween().set_loops()
	tween.tween_property(sparkle, "position:y", start_pos.y - 18, 1.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.5, 1.5)
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.9, 0.0)
	tween.parallel().tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.5)


func _process_corpse(_delta: float) -> void:
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
	if not loot_prompt:
		return
	var prompt_world_pos = global_position + Vector2(0, -45)
	var screen_pos = get_viewport().get_canvas_transform() * prompt_world_pos
	loot_prompt.position = screen_pos - Vector2(loot_prompt.size.x / 2, 0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_corpse or not player_in_loot_range:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		open_loot_ui()
		get_viewport().set_input_as_handled()


func has_corpse_loot() -> bool:
	return not corpse_loot.is_empty() or corpse_gold > 0


func check_if_looted_empty() -> void:
	if corpse_loot.is_empty() and corpse_gold == 0:
		if loot_indicator:
			loot_indicator.queue_free()
			loot_indicator = null
		if loot_prompt:
			loot_prompt.queue_free()
			loot_prompt = null
		corpse_looted_empty.emit(self)
		graceful_despawn()


func graceful_despawn() -> void:
	if has_node("Area2D"):
		var area = get_node("Area2D")
		area.monitoring = false
		area.monitorable = false

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	tween.tween_property(self, "scale", Vector2(0.7, 0.7), 1.5)
	await tween.finished

	if is_instance_valid(self):
		queue_free()


func open_loot_ui() -> void:
	if corpse_gold == 0 and corpse_loot.is_empty():
		return

	if corpse_clicked.get_connections().size() > 0:
		corpse_clicked.emit(self)
	else:
		var game_world = get_tree().current_scene
		if game_world and game_world.has_method("_on_corpse_clicked"):
			game_world._on_corpse_clicked(self)


func get_display_name() -> String:
	return "Spider"


func get_enemy_type() -> String:
	return "spider"


# ═══════════════════════════════════════════════════════════════════════════════
# CRIT WINDOW SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

var _crit_window_transitioning: bool = false
var _grow_tween: Tween = null


func grow_for_crit_window(_difficulty: float = 1.0) -> void:
	if is_dying or in_crit_window or _crit_window_transitioning:
		return

	_crit_window_transitioning = true
	in_crit_window = true

	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)

	var target_scale = original_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER
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
	if is_dying or is_corpse:
		return

	var player_level = CharacterStats.level
	var num_weakpoints = 1
	if player_level >= 21:
		num_weakpoints = 3
	elif player_level >= 11:
		num_weakpoints = 2

	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var positions = [
		Vector2(0, -20 * sprite_scale.y),
		Vector2(-25 * sprite_scale.x, 5),
		Vector2(25 * sprite_scale.x, 5),
	]

	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(min(num_weakpoints, positions.size())):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()
		weakpoint.color_theme = "poison"  # Green for spiders
		weakpoint.position = positions[i]
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 2.5
		weakpoint.rotation = randf_range(-PI, PI)
		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed)
		add_child(weakpoint)
		weakpoints.append(weakpoint)
		weakpoint_spawned.emit(weakpoint)


func shrink_after_crit_window() -> void:
	if not in_crit_window:
		return

	in_crit_window = false

	if _grow_tween and _grow_tween.is_running():
		await _grow_tween.finished

	if sprite:
		sprite.modulate = original_modulate
		var shrink_tween = create_tween()
		shrink_tween.tween_property(sprite, "scale", original_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
		z_index = 0

	for wp in weakpoints:
		if is_instance_valid(wp):
			wp.queue_free()
	weakpoints.clear()


func _on_weakpoint_hit(weakpoint) -> void:
	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER
	take_damage(crit_damage, true, true)


func _on_weakpoint_destroyed(weakpoint) -> void:
	weakpoint_destroyed.emit(weakpoint)


func get_crit_window_weakpoint_count() -> int:
	if weakpoints.size() > 0:
		return weakpoints.size()
	var player_level = CharacterStats.level
	if player_level >= 21:
		return 3
	elif player_level >= 11:
		return 2
	return 1


# ═══════════════════════════════════════════════════════════════════════════════
# AI BEHAVIOR - Simple roaming (no pack)
# ═══════════════════════════════════════════════════════════════════════════════

const BASE_DETECTION_RANGE: float = 200.0
const ATTACK_RANGE: float = 50.0
const LOSE_INTEREST_RANGE: float = 500.0
const WANDER_RADIUS: float = 200.0
const WANDER_INTERVAL_MIN: float = 1.5
const WANDER_INTERVAL_MAX: float = 4.0

var target_player: Node = null
var attack_cooldown: float = 0.0
const ATTACK_COOLDOWN_TIME: float = 1.2

var _detection_range: float = BASE_DETECTION_RANGE
var _was_attacked: bool = false  # Set when hit, forces chase even from outside detection range
var _spawn_position: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_timer: float = 0.0
var _is_wandering: bool = false


func _init_ai_variation() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	_detection_range = BASE_DETECTION_RANGE + rng.randf_range(-30, 30)
	_current_frame = rng.randi_range(0, 7)
	_wander_timer = rng.randf_range(0, WANDER_INTERVAL_MAX)

	call_deferred("_set_spawn_position")


func _set_spawn_position() -> void:
	_spawn_position = global_position
	_wander_target = _spawn_position


func _physics_process(delta: float) -> void:
	if is_dying or is_corpse:
		return

	if attack_cooldown > 0:
		attack_cooldown -= delta

	_wander_timer -= delta

	# Find target player (multiplayer aware)
	if not is_instance_valid(target_player):
		_update_target_player()

	if not target_player:
		_do_wander(delta)
		return

	var distance = global_position.distance_to(target_player.global_position)
	var direction = (target_player.global_position - global_position).normalized()

	if distance > LOSE_INTEREST_RANGE:
		target_player = null
		is_running = false
		_was_attacked = false  # Reset attack flag when losing interest
		_do_wander(delta)
		return

	# Chase if: in detection range OR was attacked (ranged weapons trigger chase from any distance)
	if (distance <= _detection_range or _was_attacked) and distance > ATTACK_RANGE:
		_is_wandering = false
		is_running = true
		velocity = direction * BASE_SPEED * RUN_SPEED_MULT
		move_and_slide()
		update_animation_for_direction(direction)
	elif distance <= ATTACK_RANGE:
		_is_wandering = false
		is_running = false
		velocity = Vector2.ZERO
		if attack_cooldown <= 0 and not is_attacking:
			perform_attack(target_player, direction)
	else:
		is_running = false
		_do_wander(delta)


func _do_wander(delta: float) -> void:
	if _spawn_position == Vector2.ZERO:
		velocity = Vector2.ZERO
		return

	if _wander_timer <= 0:
		_wander_timer = randf_range(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX)

		if randf() < 0.35:
			_is_wandering = false
			_wander_target = Vector2.ZERO
		else:
			_is_wandering = true
			var angle = randf() * TAU
			var dist = randf_range(40, WANDER_RADIUS)
			_wander_target = _spawn_position + Vector2(cos(angle), sin(angle)) * dist

	if _is_wandering and _wander_target != Vector2.ZERO:
		var dist_to_target = global_position.distance_to(_wander_target)
		if dist_to_target > 15:
			var direction = (_wander_target - global_position).normalized()
			velocity = direction * BASE_SPEED * 0.5
			move_and_slide()
			update_animation_for_direction(direction)
		else:
			_is_wandering = false
			_wander_target = Vector2.ZERO
			velocity = Vector2.ZERO
			update_animation_for_direction(Vector2.ZERO)
	else:
		velocity = Vector2.ZERO
		update_animation_for_direction(Vector2.ZERO)


func perform_attack(player: Node, direction: Vector2) -> void:
	is_attacking = true
	attack_cooldown = ATTACK_COOLDOWN_TIME

	# Spider lunges toward player
	var attack_anim = "walk_down"
	if abs(direction.x) > abs(direction.y):
		attack_anim = "walk_right" if direction.x > 0 else "walk_left"
	else:
		attack_anim = "walk_down" if direction.y > 0 else "walk_up"

	play_animation(attack_anim)

	# Quick lunge
	var lunge_tween = create_tween()
	lunge_tween.tween_property(self, "global_position", global_position + direction * 20, 0.15)

	await get_tree().create_timer(0.2).timeout

	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= ATTACK_RANGE * 1.8:
		if player.has_method("take_damage"):
			player.take_damage(base_damage)

	await get_tree().create_timer(0.3).timeout
	is_attacking = false


func _on_damage_taken(_damage: float, _is_crit: bool) -> void:
	"""Called when spider takes damage - enter chase mode to attack the player."""
	if is_dying or is_corpse:
		return

	# Mark as attacked so spider chases even from outside detection range (ranged weapons)
	_was_attacked = true

	# Find nearest player to target (multiplayer aware)
	_update_target_player()

	# Enter combat mode
	if target_player:
		is_running = true
		_is_wandering = false


func _update_target_player() -> void:
	"""Find the nearest valid player to target (multiplayer aware)."""
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	if players.is_empty():
		target_player = null
		return

	# In multiplayer, find the nearest alive player
	var nearest_player: Node = null
	var nearest_distance: float = INF

	for p in players:
		if not is_instance_valid(p):
			continue
		if p.get("is_dead"):
			continue

		var dist = global_position.distance_to(p.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest_player = p

	target_player = nearest_player
