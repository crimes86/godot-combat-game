@tool
extends Marker2D
class_name ManualEnemySpawn

## Manual Enemy Spawn Marker
## Drop this in the scene to manually place enemies
## Will be read by GameWorld on startup

@export var enemy_level: int = 1:
	set(value):
		enemy_level = value
		queue_redraw()

@export var aggro_range: float = 150.0:
	set(value):
		aggro_range = value
		queue_redraw()

@export var enemy_type: String = "skeleton":
	set(value):
		enemy_type = value
		queue_redraw()

func _ready() -> void:
	if Engine.is_editor_hint():
		# Store metadata for runtime spawning
		set_meta("enemy_level", enemy_level)
		set_meta("aggro_range", aggro_range)
		set_meta("enemy_type", enemy_type)
	queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	# Draw spawn point visualization in editor
	var color = get_level_color(enemy_level)

	# Draw circle for spawn point
	draw_circle(Vector2.ZERO, 30, Color(color, 0.3))
	draw_arc(Vector2.ZERO, 30, 0, TAU, 32, color, 2.0)

	# Draw aggro range preview
	draw_arc(Vector2.ZERO, aggro_range, 0, TAU, 64, Color(color, 0.2), 1.0)

	# Draw level indicator
	var font = ThemeDB.fallback_font
	var font_size = 20
	var text = "L%d" % enemy_level
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, Vector2(-text_size.x / 2, 5), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

func get_level_color(level: int) -> Color:
	"""Get color based on enemy level for visualization"""
	if level <= 3:
		return Color.GREEN  # Noob area
	elif level <= 7:
		return Color.YELLOW  # Low level
	elif level <= 12:
		return Color.ORANGE  # Mid level
	elif level <= 18:
		return Color.RED  # High level
	else:
		return Color.PURPLE  # Boss level

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Update metadata when properties change
		set_meta("enemy_level", enemy_level)
		set_meta("aggro_range", aggro_range)
		set_meta("enemy_type", enemy_type)

		# Ensure name matches pattern
		if not name.begins_with("EnemySpawn"):
			name = "EnemySpawn_L%d_%s" % [enemy_level, enemy_type]
