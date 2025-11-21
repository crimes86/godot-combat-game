extends CPUParticles2D
class_name FootstepDust

## Footstep dust puff effect
## Spawns a small burst of dust particles at character's feet when walking

func _ready() -> void:
	# Particle settings
	emitting = false
	one_shot = true
	explosiveness = 1.0  # All particles emit at once
	amount = 8  # Small puff
	lifetime = 0.4  # Short-lived

	# Emission shape (small circle at feet)
	emission_shape = EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 8.0

	# Movement (spread outward and slightly up)
	direction = Vector2(0, -1)  # Upward
	spread = 80.0  # Wide spread
	initial_velocity_min = 20.0
	initial_velocity_max = 40.0
	gravity = Vector2(0, 30.0)  # Slight downward pull

	# Scale (start small, grow slightly, fade)
	scale_amount_min = 2.0
	scale_amount_max = 4.0
	scale_amount_curve = _create_grow_curve()

	# Color (dusty brown/tan, fade to transparent)
	color = Color(0.7, 0.6, 0.5, 0.6)  # Light dusty brown
	color_ramp = _create_fade_ramp()

	# Rendering
	z_index = -5  # Below characters, above shadows

	# Auto-cleanup when finished
	finished.connect(_on_finished)

func _create_grow_curve() -> Curve:
	"""Particles start tiny, grow, then shrink"""
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.3))  # Start small
	curve.add_point(Vector2(0.5, 1.0))  # Grow to full size
	curve.add_point(Vector2(1.0, 0.2))  # Shrink at end
	return curve

func _create_fade_ramp() -> Gradient:
	"""Fade from visible to transparent"""
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.7, 0.6, 0.5, 0.6))  # Start visible
	gradient.set_color(1, Color(0.7, 0.6, 0.5, 0.0))  # Fade to transparent
	return gradient

func spawn_dust() -> void:
	"""Trigger the dust puff"""
	restart()

func _on_finished() -> void:
	"""Clean up after effect finishes"""
	queue_free()
