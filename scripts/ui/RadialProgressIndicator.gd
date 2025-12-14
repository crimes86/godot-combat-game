extends Control
## RadialProgressIndicator - Shows radial fill while holding a key
## Used for "Hold F to interact" style mechanics

signal progress_completed
signal progress_cancelled

@export var fill_duration: float = 0.4  # How long to hold (seconds)
@export var radius: float = 32.0  # Radius of the circle
@export var thickness: float = 4.0  # Thickness of the progress ring
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.6)  # Dark background
@export var fill_color: Color = Color(1.0, 0.9, 0.3, 0.9)  # Gold fill
@export var completed_color: Color = Color(0.3, 1.0, 0.3, 1.0)  # Green when complete

var progress: float = 0.0  # 0.0 to 1.0
var is_active: bool = false
var is_completed: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2 + 20, radius * 2 + 20)
	modulate.a = 0.0  # Start invisible
	visible = false

func _draw() -> void:
	if not is_active:
		return

	var center = size / 2.0

	# Draw background circle
	draw_arc(center, radius, 0, TAU, 64, background_color, thickness, true)

	# Draw progress arc (starts at top, goes clockwise)
	if progress > 0.0:
		var angle = progress * TAU
		var color = completed_color if is_completed else fill_color
		draw_arc(center, radius, -PI/2, -PI/2 + angle, 64, color, thickness, true)

	# Draw F key hint in center
	var font_size = 18
	var text = "F"
	var text_size = get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = center - text_size / 2.0
	draw_string(get_theme_default_font(), text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func start_progress() -> void:
	"""Start the hold progress"""
	is_active = true
	is_completed = false
	progress = 0.0
	visible = true

	# Fade in
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.1)

	queue_redraw()

func update_progress(delta: float) -> void:
	"""Update progress based on time held"""
	if not is_active or is_completed:
		return

	progress += delta / fill_duration

	if progress >= 1.0:
		progress = 1.0
		is_completed = true
		_on_completed()

	queue_redraw()

func cancel_progress() -> void:
	"""Cancel the hold progress (key released early)"""
	if not is_active:
		return

	is_active = false
	is_completed = false
	progress = 0.0

	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	await tween.finished
	visible = false
	queue_redraw()

	progress_cancelled.emit()

func _on_completed() -> void:
	"""Called when progress reaches 100%"""
	# Flash effect
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.5, 0.1)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	await tween.finished

	is_active = false
	visible = false
	progress_completed.emit()

	# Reset for next use
	progress = 0.0
	is_completed = false
