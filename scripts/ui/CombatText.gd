extends Label
class_name CombatText

## Floating combat text that displays damage numbers
## Auto-frees itself after animation completes
## Uses radial distribution to prevent clumping

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

# Static counter for radial distribution - rotates through positions
static var _spawn_index: int = 0
const RADIAL_POSITIONS: int = 8  # Number of positions around the circle
const RADIAL_RADIUS: float = 25.0  # Distance from center for normal hits
const RADIAL_RADIUS_CRIT: float = 30.0  # Slightly larger for crits
const RADIAL_RADIUS_WEAKPOINT: float = 35.0  # Larger for weakpoints

var type: TextType = TextType.NORMAL
var lifetime: float = 1.0

func _ready() -> void:
	# Make sure text renders above everything
	z_index = 1000

	# Apply radial offset to spread out damage numbers
	# Each spawn gets the next position in a circular pattern
	if type == TextType.NORMAL or type == TextType.CRIT or type == TextType.WEAKPOINT:
		var angle = (float(_spawn_index) / RADIAL_POSITIONS) * TAU  # TAU = 2*PI
		var radius = RADIAL_RADIUS
		if type == TextType.CRIT:
			radius = RADIAL_RADIUS_CRIT
		elif type == TextType.WEAKPOINT:
			radius = RADIAL_RADIUS_WEAKPOINT

		# Calculate offset from center
		var radial_offset = Vector2(cos(angle), sin(angle)) * radius
		# Bias upward slightly so numbers appear more above the enemy
		radial_offset.y -= 10.0
		position += radial_offset

		# Increment for next spawn
		_spawn_index = (_spawn_index + 1) % RADIAL_POSITIONS
	elif type == TextType.MISS:
		# MISS: slight random offset
		position += Vector2(randf_range(-15, 15), randf_range(-10, 10))
	# DAMAGE, HEAL, XP, GOLD, SKILL_UP: no additional offset (positioned by caller)
	
	# Set up text appearance based on type
	match type:
		TextType.NORMAL:
			add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))  # Pure white, full opacity
			add_theme_font_size_override("font_size", 18)  # 24 * 0.75 = 18
			animate_normal()
		TextType.CRIT:
			add_theme_color_override("font_color", Color(1.0, 1.0, 0.2))  # Brighter yellow-gold
			add_theme_font_size_override("font_size", 27)  # 36 * 0.75 = 27
			animate_crit()
		TextType.WEAKPOINT:
			add_theme_color_override("font_color", Color(1.0, 0.3, 0.0))  # Bright red-orange
			add_theme_font_size_override("font_size", 16)  # 21 * 0.75 ≈ 16
			animate_weakpoint()
		TextType.MISS:
			add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.9))  # Brighter gray
			add_theme_font_size_override("font_size", 15)  # 20 * 0.75 = 15
			text = "MISS"
			animate_miss()
		TextType.DAMAGE:
			add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Brighter red
			add_theme_font_size_override("font_size", 23)  # 30 * 0.75 ≈ 23
			animate_damage()
		TextType.HEAL:
			add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))  # Brighter green
			add_theme_font_size_override("font_size", 21)  # 28 * 0.75 = 21
			animate_heal()
		TextType.XP:
			add_theme_color_override("font_color", Color(0.3, 0.9, 0.95))  # Cyan/teal
			add_theme_font_size_override("font_size", 20)
			animate_xp()
		TextType.GOLD:
			add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))  # Gold
			add_theme_font_size_override("font_size", 18)
			animate_gold()
		TextType.SKILL_UP:
			add_theme_color_override("font_color", Color(0.85, 0.6, 0.3))  # Bronze/copper
			add_theme_font_size_override("font_size", 16)
			animate_skill_up()

	# Add thick black outline for readability
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 3)
	
	# Auto-delete after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func animate_normal() -> void:
	# Pop style - appear, stay in place, fade out
	lifetime = 0.8
	var tween = create_tween()

	# Quick pop in
	scale = Vector2(0.5, 0.5)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Hold briefly then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.3)

func animate_crit() -> void:
	# Pop style with bigger bounce for crits
	lifetime = 1.0
	var tween = create_tween()

	# Bigger pop for crits
	scale = Vector2(0.4, 0.4)
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

	# Hold longer then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.4)

func animate_weakpoint() -> void:
	# Pop style with explosive/elastic feel for weakpoints
	# Longer lifetime allows multiple weakpoint hits to stagger visually
	lifetime = 1.4
	var tween = create_tween()

	# Explosive pop with slight rotation for impact feel
	scale = Vector2(0.3, 0.3)
	rotation_degrees = randf_range(-8, 8)

	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.15)

	# Hold longer then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.7)

func animate_miss() -> void:
	# Pop style - quick appear and fade for miss
	lifetime = 0.6
	var tween = create_tween()

	# Subtle pop
	scale = Vector2(0.7, 0.7)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08).set_ease(Tween.EASE_OUT)

	# Quick fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.15)

func animate_damage() -> void:
	# Pop style with shake for player damage
	lifetime = 0.9
	var tween = create_tween()

	# Quick shake offset (stays in place after)
	var shake_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
	position += shake_offset

	# Sharp pop
	scale = Vector2(0.6, 0.6)
	tween.tween_property(self, "scale", Vector2(1.25, 1.25), 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

	# Hold then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.45).set_delay(0.35)

func animate_heal() -> void:
	# Pop style with gentle pulse for healing
	lifetime = 0.9
	var tween = create_tween()

	# Gentle pulse pop
	scale = Vector2(0.6, 0.6)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

	# Hold then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.45).set_delay(0.35)

func animate_xp() -> void:
	# Pop style for XP gain - stays longer so player can read it
	lifetime = 2.0
	var tween = create_tween()

	# Pop in effect
	scale = Vector2(0.3, 0.3)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Hold longer then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.6).set_delay(1.2)

func animate_gold() -> void:
	# Pop style for gold pickup - stays longer so player can read it
	lifetime = 1.8
	var tween = create_tween()

	# Smaller pop
	scale = Vector2(0.4, 0.4)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Hold longer then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(1.1)

func animate_skill_up() -> void:
	# Pop style for skill up - stays longer so player can read it
	lifetime = 2.0
	var tween = create_tween()

	# Subtle pop
	scale = Vector2(0.5, 0.5)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

	# Hold longer then fade out (no movement)
	tween.tween_property(self, "modulate:a", 0.0, 0.6).set_delay(1.2)

## Helper function to calculate position offset based on direction
static func _get_position_offset_for_direction(direction: Vector2) -> Vector2:
	"""Calculate spawn position offset based on player's facing direction
	Used for player damage/heal text positioning
	Offsets: RIGHT(-85,0), LEFT(-5,0), DOWN(0,-30), UP(0,15)"""
	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var dir = direction.normalized()
	var offset = Vector2.ZERO

	# Determine primary facing direction
	if abs(dir.x) > abs(dir.y):
		# Horizontal facing (left or right)
		if dir.x > 0:
			# Facing RIGHT - offset left by 85px
			offset = Vector2(-85, 0)
		else:
			# Facing LEFT - offset left by 5px (-10 more from 5 = -5)
			offset = Vector2(-5, 0)
	else:
		# Vertical facing (up or down)
		if dir.y > 0:
			# Facing DOWN - no change
			offset = Vector2(0, -30)
		else:
			# Facing UP - offset up by 15 (-15 more from 30 = 15)
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
	# Spawn damage text based on player's facing direction
	var offset = _get_position_offset_for_direction(direction)
	var spawn_pos = world_pos + offset
	return _create_text("-" + str(int(damage)), TextType.DAMAGE, spawn_pos, parent)

static func create_heal(amount: float, world_pos: Vector2, parent: Node, direction: Vector2 = Vector2.ZERO) -> CombatText:
	# Spawn heal text based on player's facing direction (same as damage)
	var offset = _get_position_offset_for_direction(direction)
	var spawn_pos = world_pos + offset
	return _create_text("+" + str(int(amount)), TextType.HEAL, spawn_pos, parent)

static func create_xp(amount: int, world_pos: Vector2, parent: Node) -> CombatText:
	# XP text spawns above the mob's death position
	var spawn_pos = world_pos + Vector2(0, -40)  # Offset above mob center
	return _create_text("+%d XP" % amount, TextType.XP, spawn_pos, parent)

static func create_gold(amount: int, world_pos: Vector2, parent: Node) -> CombatText:
	# Gold text spawns slightly below XP
	var spawn_pos = world_pos + Vector2(0, -20)  # Offset above mob center, below XP
	return _create_text("+%d Gold" % amount, TextType.GOLD, spawn_pos, parent)

static func create_skill_up(amount: float, category: String, world_pos: Vector2, parent: Node) -> CombatText:
	# Skill-up text spawns offset to the right of XP/Gold
	var spawn_pos = world_pos + Vector2(30, -30)  # Offset to right and above mob center
	var display_text = "+%.1f %s" % [amount, category.capitalize()]
	return _create_text(display_text, TextType.SKILL_UP, spawn_pos, parent)

static func _create_text(damage_text: String, text_type: TextType, world_pos: Vector2, parent: Node) -> CombatText:
	var combat_text = preload("res://scenes/ui/combat_text.tscn").instantiate() as CombatText
	combat_text.text = damage_text
	combat_text.type = text_type
	combat_text.global_position = world_pos
	parent.add_child(combat_text)
	return combat_text
