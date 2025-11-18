extends Label
class_name CombatText

## Floating combat text that displays damage numbers
## Auto-frees itself after animation completes

enum TextType {
	NORMAL,    # White text, normal size
	CRIT,      # Yellow text, larger with bounce
	WEAKPOINT, # Orange-red text, largest with explosion feel
	MISS,      # Gray "MISS" text, smaller
	DAMAGE,    # Red text for player taking damage
	HEAL       # Green text for player gaining health
}

var type: TextType = TextType.NORMAL
var lifetime: float = 1.0  # Reduced from 1.2 for faster cycling
var float_speed: float = 100.0  # Increased from 50 for faster scrolling
var random_offset: Vector2 = Vector2.ZERO
var arc_offset: Vector2 = Vector2.ZERO  # For fountain/arc pattern

func _ready() -> void:
	# Make sure text renders above everything
	z_index = 1000

	# Random horizontal offset to prevent overlapping (but NOT for player damage/heal text)
	# Player damage/heal text should appear at precise positions based on facing direction
	if type != TextType.DAMAGE and type != TextType.HEAL:
		# Larger spread for better separation (fountain effect)
		random_offset = Vector2(randf_range(-50, 50), randf_range(-15, 15))
		position += random_offset

		# Arc offset for fountain pattern (numbers curve outward as they rise)
		# Direction depends on initial horizontal offset
		arc_offset = Vector2(random_offset.x * 0.5, 0)  # Continue in same direction
	
	# Set up text appearance based on type
	match type:
		TextType.NORMAL:
			add_theme_color_override("font_color", Color.WHITE)
			add_theme_font_size_override("font_size", 24)
			animate_normal()
		TextType.CRIT:
			add_theme_color_override("font_color", Color(1.0, 0.9, 0.0))  # Yellow-gold
			add_theme_font_size_override("font_size", 36)
			animate_crit()
		TextType.WEAKPOINT:
			add_theme_color_override("font_color", Color(1.0, 0.4, 0.0))  # Orange-red
			add_theme_font_size_override("font_size", 21)  # Half of previous size (was 42)
			animate_weakpoint()
		TextType.MISS:
			add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))  # Gray
			add_theme_font_size_override("font_size", 20)
			text = "MISS"
			animate_miss()
		TextType.DAMAGE:
			add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))  # Bright red
			add_theme_font_size_override("font_size", 30)
			animate_damage()
		TextType.HEAL:
			add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))  # Bright green
			add_theme_font_size_override("font_size", 28)
			animate_heal()
	
	# Add thick black outline for readability
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 3)
	
	# Auto-delete after lifetime
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func animate_normal() -> void:
	# Arc/fountain pattern - float up and outward, then fade
	var tween = create_tween()
	tween.set_parallel(true)

	# Move up and outward in an arc (fountain effect)
	var target_pos = position + Vector2(arc_offset.x, -float_speed)
	tween.tween_property(self, "position", target_pos, lifetime).set_ease(Tween.EASE_OUT)

	# Faster fade for quicker cycling
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)

func animate_crit() -> void:
	# Bounce in, arc upward, fade out
	var tween = create_tween()

	# Initial pop
	scale = Vector2(0.5, 0.5)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

	# Float up and outward in arc, faster than normal
	tween.set_parallel(true)
	var target_pos = position + Vector2(arc_offset.x, -float_speed * 1.5)
	tween.tween_property(self, "position", target_pos, lifetime).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)

func animate_weakpoint() -> void:
	# Explosive entry, arc upward with fountain effect (now smaller and faster)
	var tween = create_tween()

	# Explosive pop (reduced since text is now smaller)
	scale = Vector2(0.5, 0.5)
	rotation_degrees = randf_range(-10, 10)

	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.2)

	# Faster float with arc (reduced from 1.5s to 1.2s)
	lifetime = 1.2
	tween.set_parallel(true)
	var target_pos = position + Vector2(arc_offset.x, -float_speed * 1.2)
	tween.tween_property(self, "position", target_pos, lifetime).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)

func animate_miss() -> void:
	# Quick fade, minimal movement
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed * 0.5), lifetime * 0.8)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5)
	lifetime = 0.8

func animate_damage() -> void:
	# Sharp, attention-grabbing animation for taking damage
	var tween = create_tween()
	
	# Quick shake effect
	scale = Vector2(0.8, 0.8)
	var shake_offset = Vector2(randf_range(-5, 5), randf_range(-5, 5))
	position += shake_offset
	
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Float and fade
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed * 1.2), lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)

func animate_heal() -> void:
	# Gentle, uplifting animation for healing
	var tween = create_tween()
	
	# Gentle pulse
	scale = Vector2(0.7, 0.7)
	tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Slower float with sparkle feel
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed * 0.8), lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)

## Helper function to calculate position offset based on direction
static func _get_position_offset_for_direction(direction: Vector2) -> Vector2:
	"""Calculate spawn position offset based on player's facing direction
	Used for player damage/heal text positioning
	Offsets: RIGHT(-25,0), LEFT(25,0), DOWN(0,-30), UP(0,50)"""
	if direction == Vector2.ZERO:
		return Vector2.ZERO

	var dir = direction.normalized()
	var offset = Vector2.ZERO

	# Determine primary facing direction
	if abs(dir.x) > abs(dir.y):
		# Horizontal facing (left or right)
		if dir.x > 0:
			# Facing RIGHT
			offset = Vector2(-25, 0)
		else:
			# Facing LEFT
			offset = Vector2(25, 0)
	else:
		# Vertical facing (up or down)
		if dir.y > 0:
			# Facing DOWN
			offset = Vector2(0, -30)
		else:
			# Facing UP
			offset = Vector2(0, 50)

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

static func _create_text(damage_text: String, text_type: TextType, world_pos: Vector2, parent: Node) -> CombatText:
	var combat_text = preload("res://scenes/ui/combat_text.tscn").instantiate() as CombatText
	combat_text.text = damage_text
	combat_text.type = text_type
	combat_text.global_position = world_pos
	parent.add_child(combat_text)
	return combat_text
