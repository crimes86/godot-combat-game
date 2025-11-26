extends Node

## Ultra-Responsive Hit Flash
## Can be spammed - always shows feedback
## CRITICAL: Respects crit window gold color!

var sprite: CanvasItem  # ✨ Changed from Sprite2D to support AnimatedSprite2D too
var base_color: Color = Color.WHITE  # Default white (normal enemies)
var flash_tween: Tween = null
var parent: Node = null  # Cache parent reference

func _ready() -> void:
	# Get sprite and parent from parent
	parent = get_parent()
	
	# Try "Sprite" first (AnimatedSprite2D), then "Sprite2D" (fallback)
	if parent.has_node("Sprite"):
		sprite = parent.get_node("Sprite")
	elif parent.has_node("Sprite2D"):
		sprite = parent.get_node("Sprite2D")

## Main flash function - can be called rapidly
func flash(is_critical: bool = false) -> void:
	if not sprite:
		return
	
	# Cancel any existing flash tween
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	
	# ✨ FIX: Always restore to base_color, not current sprite color
	# This prevents issues when:
	# - Enemy is in crit window (gold) but sprite is currently flashing white
	# - Multiple rapid hits occur
	var restore_color = base_color
	
	# Flash color (bright white for normal, red for crit/weakpoint)
	var flash_color = Color(5, 5, 5, 1) if not is_critical else Color(5, 1, 1, 1)
	
	# Instant flash
	sprite.modulate = flash_color
	
	# Create tween to restore
	flash_tween = create_tween()
	flash_tween.set_ease(Tween.EASE_OUT)
	flash_tween.set_trans(Tween.TRANS_CUBIC)
	flash_tween.tween_property(sprite, "modulate", restore_color, 0.15)

## Update base color (call when enemy changes state)
func set_base_color(color: Color) -> void:
	base_color = color
