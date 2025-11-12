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
var lifetime: float = 1.2
var float_speed: float = 50.0
var random_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Make sure text renders above everything
	z_index = 1000
	
	# Random horizontal offset to prevent overlapping
	random_offset = Vector2(randf_range(-30, 30), randf_range(-10, 10))
	position += random_offset
	
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
			add_theme_font_size_override("font_size", 42)
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
	# Simple float up and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed), lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.7).set_delay(lifetime * 0.3)

func animate_crit() -> void:
	# Bounce in, float up, fade out
	var tween = create_tween()
	
	# Initial pop
	scale = Vector2(0.5, 0.5)
	tween.tween_property(self, "scale", Vector2(1.3, 1.3), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Float and fade
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed * 1.5), lifetime)
	tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.6).set_delay(lifetime * 0.4)

func animate_weakpoint() -> void:
	# Explosive entry, longer hang time, dramatic float
	var tween = create_tween()
	
	# Explosive pop
	scale = Vector2(0.3, 0.3)
	rotation_degrees = randf_range(-15, 15)
	
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.15)
	tween.tween_property(self, "rotation_degrees", 0.0, 0.3)
	
	# Slower float with longer visibility
	lifetime = 1.5
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector2(0, -float_speed * 1.2), lifetime)
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
	# Spawn damage text behind player (opposite of facing direction)
	var spawn_pos = world_pos
	if direction != Vector2.ZERO:
		spawn_pos = world_pos - direction.normalized() * 40  # 40px behind player
	return _create_text("-" + str(int(damage)), TextType.DAMAGE, spawn_pos, parent)

static func create_heal(amount: float, world_pos: Vector2, parent: Node, direction: Vector2 = Vector2.ZERO) -> CombatText:
	# Spawn heal text behind player (opposite of facing direction)
	var spawn_pos = world_pos
	if direction != Vector2.ZERO:
		spawn_pos = world_pos - direction.normalized() * 40  # 40px behind player
	return _create_text("+" + str(int(amount)), TextType.HEAL, spawn_pos, parent)

static func _create_text(damage_text: String, text_type: TextType, world_pos: Vector2, parent: Node) -> CombatText:
	var combat_text = preload("res://scenes/ui/combat_text.tscn").instantiate() as CombatText
	combat_text.text = damage_text
	combat_text.type = text_type
	combat_text.global_position = world_pos
	parent.add_child(combat_text)
	return combat_text
