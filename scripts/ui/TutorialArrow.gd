extends Node2D

## Tutorial Arrow - Points from player to target in world space
## Draws an animated arrow that guides the player

var target_position: Vector2 = Vector2.ZERO
var player_position: Vector2 = Vector2.ZERO

var arrow_color: Color = Color(1.0, 0.9, 0.3, 0.9)  # Gold
var arrow_size: float = 30.0
var pulse_time: float = 0.0

func _process(delta: float) -> void:
	pulse_time += delta * 3.0  # Pulse speed
	queue_redraw()

func _draw() -> void:
	if target_position == Vector2.ZERO or player_position == Vector2.ZERO:
		return

	var direction = (target_position - player_position).normalized()
	var distance = player_position.distance_to(target_position)

	# Don't draw if very close
	if distance < 100:
		return

	# Position arrow between player and target, closer to player
	var arrow_distance = min(150, distance * 0.3)
	var arrow_pos = player_position + direction * arrow_distance

	# Convert to local coordinates
	var local_pos = arrow_pos - global_position

	# Pulse effect
	var pulse = 1.0 + sin(pulse_time) * 0.2
	var current_size = arrow_size * pulse

	# Calculate arrow points
	var angle = direction.angle()
	var tip = local_pos + direction * current_size
	var back_left = local_pos + Vector2(cos(angle + 2.5), sin(angle + 2.5)) * current_size * 0.7
	var back_right = local_pos + Vector2(cos(angle - 2.5), sin(angle - 2.5)) * current_size * 0.7

	# Draw arrow with outline
	var outline_color = Color.BLACK
	var points = PackedVector2Array([tip, back_left, local_pos, back_right])

	# Outline
	draw_polyline(points + PackedVector2Array([tip]), outline_color, 6.0)

	# Fill
	draw_colored_polygon(points, arrow_color)

	# Distance text
	var dist_text = "%dm" % int(distance / 10)  # Convert to "meters"
	draw_string(
		ThemeDB.fallback_font,
		local_pos + Vector2(-20, -30),
		dist_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		20,
		arrow_color
	)
