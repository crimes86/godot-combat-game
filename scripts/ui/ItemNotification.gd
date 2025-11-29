extends Label
class_name ItemNotification

## Individual floating notification for items and gold
## Auto-frees itself after animation completes

signal notification_finished()

enum NotificationType {
	ITEM_ADDED,      # Green with rarity color
	ITEM_REMOVED,    # Red text
	SYSTEM_MESSAGE   # Plain text for system notifications
}

var notification_type: NotificationType = NotificationType.ITEM_ADDED
var lifetime: float = 3.0  # How long the notification lasts before fading
var initial_animation_done: bool = false  # Track if pop-in is complete

# Rarity colors matching CombatText
const RARITY_COLORS = {
	"COMMON": Color(0.8, 0.8, 0.8, 1.0),      # Light gray
	"UNCOMMON": Color(0.4, 0.9, 0.4, 1.0),    # Green
	"RARE": Color(0.4, 0.6, 1.0, 1.0),        # Blue
	"EPIC": Color(0.8, 0.4, 1.0, 1.0),        # Purple
	"LEGENDARY": Color(1.0, 0.7, 0.2, 1.0)    # Orange
}

func _ready() -> void:
	# Center alignment
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Add thick black outline for readability
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 3)

	# Size to fit content
	autowrap_mode = TextServer.AUTOWRAP_OFF

	# Start animation
	animate()

	# Auto-delete after lifetime
	await get_tree().create_timer(lifetime).timeout
	notification_finished.emit()
	queue_free()

func setup_item_added(item_name: String, quantity: int, rarity: String) -> void:
	notification_type = NotificationType.ITEM_ADDED

	# Format text
	if quantity > 1:
		text = "+ %s x%d" % [item_name, quantity]
	else:
		text = "+ %s" % item_name

	# Set color based on rarity
	var color = RARITY_COLORS.get(rarity.to_upper(), RARITY_COLORS["COMMON"])
	add_theme_color_override("font_color", color)
	add_theme_font_size_override("font_size", 20)

func setup_item_removed(item_name: String, quantity: int, rarity: String) -> void:
	notification_type = NotificationType.ITEM_REMOVED

	# Format text
	if quantity > 1:
		text = "- %s x%d" % [item_name, quantity]
	else:
		text = "- %s" % item_name

	# Red for removed items
	add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	add_theme_font_size_override("font_size", 20)

func setup_system_message(message: String, msg_type: String) -> void:
	notification_type = NotificationType.SYSTEM_MESSAGE
	text = message

	# Color based on message type
	var color: Color
	match msg_type.to_upper():
		"SUCCESS":
			color = Color(0.4, 0.9, 0.4, 1.0)  # Green
		"WARNING":
			color = Color(1.0, 0.8, 0.2, 1.0)  # Yellow
		"ERROR":
			color = Color(1.0, 0.3, 0.3, 1.0)  # Red
		_:  # INFO and default
			color = Color(0.8, 0.8, 0.8, 1.0)  # Light gray

	add_theme_color_override("font_color", color)
	add_theme_font_size_override("font_size", 18)

func animate() -> void:
	# Simple smooth pop-in animation
	var tween = create_tween()

	# Initial state - small and transparent
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0

	# Pop in with smooth bounce
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "modulate:a", 1.0, 0.2)

	# Mark animation done after pop-in completes
	await tween.finished
	initial_animation_done = true

	# Wait for lifetime, then fade out
	await get_tree().create_timer(lifetime - 0.5).timeout

	# Fade out smoothly
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
