extends Node2D
class_name SuccessRing

## Visual effect for successfully clearing all weakpoints
## Light blast shockwave that emanates from center

var center_flash: Sprite2D = null  # Bright center impact
var shockwave_sprite: Sprite2D = null  # Expanding shockwave ring
var outer_glow: Sprite2D = null  # Soft outer distortion
var particles: CPUParticles2D = null
var duration: float = 0.8  # Total animation duration (slower to see it)
var max_scale: float = 2.2  # How large the blast expands (smaller)
var elapsed: float = 0.0

func _ready() -> void:
	print("✨ SuccessRing._ready() called at position: ", global_position)
	# Set high z-index so it appears above everything
	z_index = 200

	# Create bright center flash (the impact point)
	center_flash = Sprite2D.new()
	center_flash.texture = _create_center_flash_texture()
	center_flash.modulate = Color(2.0, 1.8, 1.2, 1.0)  # Very bright white-gold
	center_flash.scale = Vector2(0.3, 0.3)  # Start small but visible
	add_child(center_flash)

	# Create outer glow (soft distortion wave)
	outer_glow = Sprite2D.new()
	outer_glow.texture = _create_blast_glow_texture()
	outer_glow.modulate = Color(1.2, 1.0, 0.6, 0.8)  # Bright warm glow
	outer_glow.scale = Vector2(0.2, 0.2)
	add_child(outer_glow)

	# Create the shockwave ring
	shockwave_sprite = Sprite2D.new()
	shockwave_sprite.texture = _create_shockwave_texture()
	shockwave_sprite.modulate = Color(1.5, 1.3, 0.8, 1.0)  # Bright energy
	shockwave_sprite.scale = Vector2(0.1, 0.1)  # Start very small
	add_child(shockwave_sprite)

	# Add explosive particles
	particles = CPUParticles2D.new()
	_setup_particles()
	add_child(particles)
	particles.emitting = true

func _process(delta: float) -> void:
	elapsed += delta
	var progress = elapsed / duration

	if progress >= 1.0:
		queue_free()
		return

	# Fast initial expansion with ease-out
	var scale_progress = 1.0 - pow(1.0 - progress, 2.5)
	var current_scale = 0.1 + (max_scale - 0.1) * scale_progress

	# Center flash: Quick bright flash then fade
	if progress < 0.12:
		# Rapid expansion from impact point
		var flash_scale = 0.2 + (0.8 - 0.2) * (progress / 0.12)
		center_flash.scale = Vector2(flash_scale, flash_scale)
		center_flash.modulate.a = 1.0
	else:
		# Quick fade
		var fade_progress = (progress - 0.12) / 0.15
		center_flash.modulate.a = max(0, 1.0 - fade_progress)
		center_flash.scale = Vector2(0.8, 0.8)

	# Shockwave ring: Expands outward from center
	shockwave_sprite.scale = Vector2(current_scale, current_scale)

	# Rotate the shockwave as it expands (spinning energy)
	# Fast initial spin that slows down as it expands
	var spin_speed = 8.0 * (1.0 - progress)  # Spins faster at start
	shockwave_sprite.rotation = elapsed * spin_speed

	# Shockwave fades as it expands
	var wave_alpha = 1.0
	if progress > 0.3:
		wave_alpha = 1.0 - ((progress - 0.3) / 0.7)
	shockwave_sprite.modulate.a = wave_alpha

	# Outer glow: Expands faster and larger, softer
	var glow_scale = current_scale * 1.3
	outer_glow.scale = Vector2(glow_scale, glow_scale)

	# Glow fades slower initially, faster at end
	var glow_alpha = 1.0
	if progress > 0.2:
		glow_alpha = 1.0 - pow((progress - 0.2) / 0.8, 1.5)
	outer_glow.modulate.a = glow_alpha * 0.5

func _setup_particles() -> void:
	"""Setup explosive light particles blasting outward"""
	particles.amount = 25  # Fewer particles
	particles.lifetime = 0.4  # Shorter lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0  # All at once - explosion!
	particles.randomness = 0.3

	# Emit from center point (the blast origin)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT

	# Blast outward in all directions
	particles.direction = Vector2(1, 0)  # Base direction
	particles.spread = 180.0  # Full 360 degrees
	particles.gravity = Vector2.ZERO  # No gravity, pure outward blast
	particles.initial_velocity_min = 80.0  # Slower
	particles.initial_velocity_max = 130.0  # Slower
	particles.damping_min = 3.0  # Slow down faster
	particles.damping_max = 4.5

	# Visual - bright energy particles (smaller)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.5, 1.3, 0.8, 1.0)  # Bright white-gold
	particles.color_ramp = _create_particle_gradient()

func _create_particle_gradient() -> Gradient:
	"""Create fade-out gradient for blast particles"""
	var gradient = Gradient.new()
	gradient.set_color(0, Color(2.0, 1.8, 1.0, 1.0))  # Very bright white-gold
	gradient.set_color(1, Color(1.0, 0.7, 0.3, 0.0))   # Fade to orange then transparent
	return gradient

func _create_center_flash_texture() -> ImageTexture:
	"""Create bright center impact flash"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2, size / 2)
	var max_radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)

			if dist < max_radius:
				# Very bright core with soft falloff
				var falloff = 1.0 - (dist / max_radius)
				falloff = pow(falloff, 0.8)  # Softer falloff for bright flash

				# White-hot center
				var brightness = falloff
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, falloff))

	return ImageTexture.create_from_image(img)

func _create_shockwave_texture() -> ImageTexture:
	"""Create expanding shockwave blast ring"""
	var size = 128
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var center = Vector2(size / 2, size / 2)
	var outer_radius = size / 2.0
	var inner_radius = outer_radius * 0.65  # Thicker blast wave

	for x in range(size):
		for y in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			var angle = pos.angle_to_point(center)

			# Create thick shockwave ring
			if dist > inner_radius and dist < outer_radius:
				# Soft anti-aliased edges
				var edge_softness = 5.0
				var outer_alpha = clamp((outer_radius - dist) / edge_softness, 0.0, 1.0)
				var inner_alpha = clamp((dist - inner_radius) / edge_softness, 0.0, 1.0)
				var base_alpha = min(outer_alpha, inner_alpha)

				# Distortion/turbulence in the blast wave
				var turbulence = sin(angle * 12.0 + dist * 0.5) * 0.2 + 0.8
				var energy_streaks = sin(angle * 6.0) * 0.15 + 0.85

				var alpha = base_alpha * turbulence * energy_streaks

				# Brighter at leading edge (outer edge of ring)
				var edge_dist = (dist - inner_radius) / (outer_radius - inner_radius)
				var brightness = 1.0 - edge_dist * 0.4  # Brighter at outer edge

				# White-gold blast color
				var color = Color(1.0 * brightness, 0.95 * brightness, 0.7 * brightness, alpha)
				img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)

func _create_blast_glow_texture() -> ImageTexture:
	"""Create soft outer glow/distortion from blast"""
	var size = 128
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var center = Vector2(size / 2, size / 2)
	var max_radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			var angle = pos.angle_to_point(center)

			# Soft radial gradient with distortion
			if dist < max_radius:
				var falloff = 1.0 - (dist / max_radius)
				falloff = pow(falloff, 2.0)  # Softer, more diffuse

				# Add some directional streaking to the glow (like air distortion)
				var streak = sin(angle * 4.0) * 0.1 + 0.9

				var alpha = falloff * streak * 0.7

				# Warm orange-gold glow
				img.set_pixel(x, y, Color(1.0, 0.8, 0.5, alpha))

	return ImageTexture.create_from_image(img)
