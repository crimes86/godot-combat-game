extends Label
class_name CombatText

## Floating combat text that displays damage numbers
## Auto-frees itself after animation completes
## Spawns in random positions within a defined area above enemies

enum TextType {
	NORMAL,    # White text, normal size
	CRIT,      # Yellow text, larger with bounce
	WEAKPOINT, # Orange-red text, largest with explosion feel
	MISS,      # Gray "MISS" text, smaller
	DAMAGE,    # Red text for player taking damage
	HEAL,      # Green text for player gaining health
	XP,        # Cyan text for XP gain (world-space, near mob)
	GOLD,      # Gold text for gold pickup (world-space, near mob)
	SKILL_UP   # Bronze/copper text for weapon skill gain (world-space, near mob)
}

# Spawn area settings - rectangle above enemy
const SPAWN_AREA_WIDTH: float = 60.0   # Total width of spawn area
const SPAWN_AREA_HEIGHT: float = 40.0  # Total height of spawn area
const SPAWN_AREA_Y_OFFSET: float = -50.0  # How far above enemy center

# Stagger settings
const SPAWN_DELAY_MAX: float = 0.05  # Max random delay before appearing (staggered pop-in)
const LIFETIME_VARIANCE: float = 0.15  # Random variance in lifetime (staggered fade-out)

var type: TextType = TextType.NORMAL
var lifetime: float = 1.0
var spawn_delay: float = 0.0

func _ready() -> void:
	# Make sure text renders above everything
	z_index = 1000

	# Start invisible if there's a spawn delay
	if spawn_delay > 0:
		modulate.a = 0

	# Apply random offset within spawn area for damage types
	if type == TextType.NORMAL or type == TextType.CRIT or type == TextType.WEAKPOINT:
		var random_offset = Vector2(
			randf_range(-SPAWN_AREA_WIDTH / 2, SPAWN_AREA_WIDTH / 2),
			randf_range(-SPAWN_AREA_HEIGHT / 2, SPAWN_AREA_HEIGHT / 2) + SPAWN_AREA_Y_OFFSET
		)
		position += random_offset

		# Add random spawn delay for staggered appearance
		spawn_delay = randf_range(0, SPAWN_DELAY_MAX)

		# Add random lifetime variance for staggered fade-out
		lifetime += randf_range(-LIFETIME_VARIANCE, LIFETIME_VARIANCE)
	elif type == TextType.MISS:
		# MISS: slight random offset
		position += Vector2(randf_range(-15, 15), randf_range(-10, 10) + SPAWN_AREA_Y_OFFSET)
	# DAMAGE, HEAL, XP, GOLD, SKILL_UP: no additional offset (positioned by caller)

	# Set up text appearance based on type
	match type:
		TextType.NORMAL:
			add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # Pure white
			add_theme_font_size_override("font_size", 18)
			_animate_pop()
		TextType.CRIT:
			add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))  # Yellow-gold
			add_theme_font_size_override("font_size", 24)
			_animate_pop_big()
		TextType.WEAKPOINT:
			add_theme_color_override("font_color", Color(1.0, 0.3, 0.0))  # Orange-red
			add_theme_font_size_override("font_size", 22)
			_animate_pop_big()
		TextType.MISS:
			add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.9))
			add_theme_font_size_override("font_size", 15)
			text = "MISS"
			_animate_pop_small()
		TextType.DAMAGE:
			add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
			add_theme_font_size_override("font_size", 23)
			_animate_pop()
		TextType.HEAL:
			add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
			add_theme_font_size_override("font_size", 21)
			_animate_pop()
		TextType.XP:
			add_theme_color_override("font_color", Color(0.3, 0.9, 0.95))
			add_theme_font_size_override("font_size", 20)
			_animate_reward()
		TextType.GOLD:
			add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			add_theme_font_size_override("font_size", 18)
			_animate_reward()
		TextType.SKILL_UP:
			add_theme_color_override("font_color", Color(0.85, 0.6, 0.3))
			add_theme_font_size_override("font_size", 16)
			_animate_reward()

	# Add thick black outline for readability
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 3)

	# Auto-delete after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _animate_pop() -> void:
	"""Standard pop animation - quick scale up then fade"""
	lifetime = 0.7 + randf_range(-LIFETIME_VARIANCE, LIFETIME_VARIANCE)

	# Wait for spawn delay (staggered appearance)
	if spawn_delay > 0:
		await get_tree().create_timer(spawn_delay).timeout
		modulate.a = 1.0

	var tween = create_tween()

	# Quick pop in
	scale = Vector2(0.3, 0.3)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.06)

	# Hold briefly then fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.25)

func _animate_pop_big() -> void:
	"""Bigger pop for crits/weakpoints"""
	lifetime = 0.9 + randf_range(-LIFETIME_VARIANCE, LIFETIME_VARIANCE)

	# Wait for spawn delay (staggered appearance)
	if spawn_delay > 0:
		await get_tree().create_timer(spawn_delay).timeout
		modulate.a = 1.0

	var tween = create_tween()

	# Bigger pop
	scale = Vector2(0.2, 0.2)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Hold longer then fade out
	tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.35)

func _animate_pop_small() -> void:
	"""Subtle pop for miss"""
	lifetime = 0.5

	var tween = create_tween()

	scale = Vector2(0.6, 0.6)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.06).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.12)

func _animate_reward() -> void:
	"""Animation for XP/Gold/Skill rewards - stays longer"""
	lifetime = 1.8

	var tween = create_tween()

	scale = Vector2(0.4, 0.4)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(1.0)

## Helper function to calculate position offset based on direction
static func _get_position_offset_for_direction(direction: Vector2) -> Vector2:
	"""Calculate spawn position offset based on player's facing direction"""
	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var dir = direction.normalized()
	var offset = Vector2.ZERO

	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			offset = Vector2(-85, 0)
		else:
			offset = Vector2(-5, 0)
	else:
		if dir.y > 0:
			offset = Vector2(0, -30)
		else:
			offset = Vector2(0, 15)

	return offset

## Factory functions for easy spawning
static func create_normal(damage: float, world_pos: Vector2, parent: Node) -> CombatText:
	return _create_text(str(int(damage)), TextType.NORMAL, world_pos, parent)

static func create_crit(damage: float, world_pos: Vector2, parent: Node) -> CombatText:
	return _create_text(str(int(damage)), TextType.CRIT, world_pos, parent)

static func create_weakpoint(damage: float, world_pos: Vector2, parent: Node) -> CombatText:
	return _create_text(str(int(damage)), TextType.WEAKPOINT, world_pos, parent)

static func create_miss(world_pos: Vector2, parent: Node) -> CombatText:
	return _create_text("MISS", TextType.MISS, world_pos, parent)

static func create_damage(damage: float, world_pos: Vector2, parent: Node, direction: Vector2 = Vector2.ZERO) -> CombatText:
	var offset = _get_position_offset_for_direction(direction)
	var spawn_pos = world_pos + offset
	return _create_text("-" + str(int(damage)), TextType.DAMAGE, spawn_pos, parent)

static func create_heal(amount: float, world_pos: Vector2, parent: Node, direction: Vector2 = Vector2.ZERO) -> CombatText:
	var offset = _get_position_offset_for_direction(direction)
	var spawn_pos = world_pos + offset
	return _create_text("+" + str(int(amount)), TextType.HEAL, spawn_pos, parent)

static func create_xp(amount: int, world_pos: Vector2, parent: Node) -> CombatText:
	# XP floats up-left with variance
	var variance = Vector2(randf_range(-20, 10), randf_range(-10, 10))
	var spawn_pos = world_pos + Vector2(-25, -50) + variance
	return _create_text("+%d XP" % amount, TextType.XP, spawn_pos, parent)

static func create_gold(amount: int, world_pos: Vector2, parent: Node) -> CombatText:
	# Gold floats up-center with variance
	var variance = Vector2(randf_range(-15, 15), randf_range(-10, 10))
	var spawn_pos = world_pos + Vector2(0, -25) + variance
	return _create_text("+%d Gold" % amount, TextType.GOLD, spawn_pos, parent)

static func create_skill_up(amount: float, category: String, world_pos: Vector2, parent: Node) -> CombatText:
	# Skill floats up-right with variance
	var variance = Vector2(randf_range(-10, 20), randf_range(-10, 10))
	var spawn_pos = world_pos + Vector2(35, -40) + variance
	var display_text = "+%.1f %s" % [amount, category.capitalize()]
	return _create_text(display_text, TextType.SKILL_UP, spawn_pos, parent)

static func _create_text(damage_text: String, text_type: TextType, world_pos: Vector2, parent: Node) -> CombatText:
	var combat_text = preload("res://scenes/ui/combat_text.tscn").instantiate() as CombatText
	combat_text.text = damage_text
	combat_text.type = text_type
	combat_text.global_position = world_pos
	parent.add_child(combat_text)
	return combat_text
