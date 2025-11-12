extends Area2D
class_name Weakpoint

var max_hits: int = 3
var current_hits: int = 0
var is_destroyed: bool = false
var sprite: Polygon2D
var glow_sprite: Polygon2D
var sparkle_particles: CPUParticles2D

signal weakpoint_hit(weakpoint)
signal weakpoint_destroyed(weakpoint)

func _ready() -> void:
	z_index = 300
	input_pickable = true
	
	# ✨ MODERATELY BRIGHT bone spur (50% less than before!)
	sprite = Polygon2D.new()
	sprite.color = Color(1.5, 1.5, 1.6, 1.0)  # Noticeably bright but not blinding
	
	# Draw a jagged bone spur shape
	var points = PackedVector2Array()
	var size = 21.0
	
	# Jagged bone spur shape
	points.append(Vector2(0, -size))
	points.append(Vector2(size * 0.3, -size * 0.6))
	points.append(Vector2(size * 0.5, -size * 0.3))
	points.append(Vector2(size * 0.4, 0))
	points.append(Vector2(size * 0.2, size * 0.3))
	points.append(Vector2(0, size * 0.4))
	points.append(Vector2(-size * 0.2, size * 0.3))
	points.append(Vector2(-size * 0.4, 0))
	points.append(Vector2(-size * 0.5, -size * 0.3))
	points.append(Vector2(-size * 0.3, -size * 0.6))
	
	sprite.polygon = points
	add_child(sprite)
	
	# ✨ MODERATE GLOW - visible but not overpowering
	glow_sprite = Polygon2D.new()
	glow_sprite.color = Color(1.3, 1.3, 1.5, 0.6)  # Subtle glow
	glow_sprite.z_index = -1
	
	# Make glow slightly larger
	var glow_points = PackedVector2Array()
	var glow_scale = 1.4
	for point in points:
		glow_points.append(point * glow_scale)
	glow_sprite.polygon = glow_points
	sprite.add_child(glow_sprite)
	
	# ✨ GENTLE PULSE
	start_glow_pulse()
	
	# Dark outline for contrast
	var outline = Line2D.new()
	outline.width = 2.5
	outline.default_color = Color(0.4, 0.4, 0.4, 1.0)  # Medium gray outline
	outline.closed = true
	for point in points:
		outline.add_point(point)
	sprite.add_child(outline)
	
	# ✨ MODERATE SPARKLES
	create_sparkle_particles()
	
	# Forgiving hitbox
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 25
	col.shape = shape
	add_child(col)
	
	input_event.connect(_on_input)
	max_hits = randi_range(3, 5)

func start_glow_pulse() -> void:
	"""Gentle glow pulse"""
	if not glow_sprite:
		return
	
	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	
	# Gentle pulse
	tween.tween_property(glow_sprite, "color:a", 0.75, 0.5)
	tween.tween_property(glow_sprite, "color:a", 0.4, 0.5)
	
	# Scale pulse
	tween.parallel().tween_property(glow_sprite, "scale", Vector2(1.15, 1.15), 0.5)
	tween.tween_property(glow_sprite, "scale", Vector2(1.0, 1.0), 0.5)

func create_sparkle_particles() -> void:
	"""Subtle sparkle particles"""
	sparkle_particles = CPUParticles2D.new()
	sparkle_particles.emitting = true
	sparkle_particles.amount = 6  # Reduced for less clutter
	sparkle_particles.lifetime = 1.0
	sparkle_particles.preprocess = 0.5
	sparkle_particles.local_coords = true
	
	sparkle_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparkle_particles.emission_sphere_radius = 28.0
	
	# Moderate sparkle texture
	var img = Image.create(7, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(2, 5):
		for y in range(2, 5):
			img.set_pixel(x, y, Color(1.5, 1.5, 1.6, 1.0))
	var tex = ImageTexture.create_from_image(img)
	sparkle_particles.texture = tex
	
	sparkle_particles.direction = Vector2(0, -1)
	sparkle_particles.spread = 180.0
	sparkle_particles.initial_velocity_min = 12.0
	sparkle_particles.initial_velocity_max = 25.0
	sparkle_particles.gravity = Vector2(0, -12)
	
	sparkle_particles.scale_amount_min = 2.0
	sparkle_particles.scale_amount_max = 4.0
	
	# Moderate brightness
	sparkle_particles.color = Color(1.5, 1.5, 1.6, 1.0)
	
	# Twinkle fade
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 0))
	gradient.add_point(0.2, Color(1, 1, 1, 1))
	gradient.add_point(0.8, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	sparkle_particles.color_ramp = gradient
	
	add_child(sparkle_particles)

func _on_input(_vp: Node, event: InputEvent, _idx: int) -> void:
	if is_destroyed:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hit()

func hit() -> void:
	if is_destroyed:
		return
	
	current_hits += 1
	weakpoint_hit.emit(self)
	
	spawn_crack_particles()
	spawn_impact_wave()
	spawn_hit_number()
	
	# Shrink and rotate
	if sprite:
		var progress = float(current_hits) / float(max_hits)
		var scale_factor = 1.0 - (progress * 0.3)
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.rotation += 0.4
		
		# ✨ BRIGHT FLASH (but not blinding)
		sprite.color = Color(2.5, 2.5, 2.5, 1.0)  # Noticeable flash
		var flash_tween = create_tween()
		flash_tween.set_parallel(true)
		flash_tween.tween_property(sprite, "color", Color(1.5, 1.5, 1.6, 1.0), 0.15)
		
		# Pop scale
		var pop_scale = Vector2(1.2, 1.2) * scale_factor
		sprite.scale = pop_scale
		flash_tween.tween_property(sprite, "scale", Vector2(scale_factor, scale_factor), 0.15).set_ease(Tween.EASE_OUT)
		
		# Glow flare
		if glow_sprite:
			glow_sprite.color.a = 0.9
	
	if current_hits >= max_hits:
		destroy()

func spawn_hit_number() -> void:
	"""Show HIT indicator"""
	var label = Label.new()
	label.text = "CRACK!"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(1.8, 1.8, 1.5, 1.0))  # Moderate bright
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.15, 0.15, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-32, -42)
	label.z_index = 500
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 32, 0.55)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.08).set_delay(0.08)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.2)
	tween.finished.connect(func(): label.queue_free())

func spawn_impact_wave() -> void:
	"""Expanding ring effect"""
	var ring = Line2D.new()
	ring.width = 3.5
	ring.default_color = Color(1.5, 1.5, 1.6, 1.0)  # Moderate bright
	ring.z_index = 299
	
	var segments = 32
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = Vector2(cos(angle), sin(angle)) * 16
		ring.add_point(point)
	
	ring.global_position = global_position
	get_parent().add_child(ring)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "width", 0.5, 0.32)
	tween.tween_property(ring, "modulate:a", 0.0, 0.32)
	
	for i in range(ring.get_point_count()):
		var point = ring.get_point_position(i)
		tween.tween_method(
			func(scale_val): ring.set_point_position(i, point * scale_val),
			1.0, 3.2, 0.32
		)
	
	tween.finished.connect(func(): ring.queue_free())

func destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	
	if sparkle_particles:
		sparkle_particles.emitting = false
	
	spawn_destruction_particles()
	spawn_destruction_wave()
	
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.WEAKPOINT_DESTROYED, global_position, -3.0)
	
	weakpoint_destroyed.emit(self)
	
	# Shatter
	if sprite:
		var shake_tween = create_tween()
		shake_tween.set_loops(5)
		shake_tween.tween_property(sprite, "position", Vector2(4, 0), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(-4, 0), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(0, 0), 0.02)
		await shake_tween.finished
		
		var explode_tween = create_tween()
		explode_tween.set_parallel(true)
		explode_tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.16)
		explode_tween.tween_property(sprite, "modulate:a", 0.0, 0.16)
		await explode_tween.finished
	
	queue_free()

func spawn_destruction_wave() -> void:
	"""Multiple shockwaves"""
	for i in range(3):
		await get_tree().create_timer(i * 0.05).timeout
		
		var ring = Line2D.new()
		ring.width = 4.5 - i
		ring.default_color = Color(1.5, 1.5, 1.6, 1.0)
		ring.z_index = 299
		
		var segments = 48
		for j in range(segments + 1):
			var angle = (j * TAU) / segments
			var point = Vector2(cos(angle), sin(angle)) * 20
			ring.add_point(point)
		
		ring.global_position = global_position
		get_parent().add_child(ring)
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring, "width", 0.5, 0.5)
		tween.tween_property(ring, "modulate:a", 0.0, 0.5)
		
		for j in range(ring.get_point_count()):
			var point = ring.get_point_position(j)
			tween.tween_method(
				func(scale_val): ring.set_point_position(j, point * scale_val),
				1.0, 5.0, 0.5
			)
		
		tween.finished.connect(func(): ring.queue_free())

func spawn_crack_particles() -> void:
	"""Subtle crack particles"""
	var particles = CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8  # Reduced for less clutter
	particles.lifetime = 0.4
	particles.local_coords = false
	particles.global_position = global_position
	
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 8.0
	
	var img = Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.5, 1.5, 1.6, 1.0))
	var tex = ImageTexture.create_from_image(img)
	particles.texture = tex
	
	particles.direction = Vector2(0, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 55.0
	particles.initial_velocity_max = 100.0
	particles.gravity = Vector2(0, 85)
	
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	
	particles.color = Color(1.5, 1.5, 1.6, 1.0)
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	particles.color_ramp = gradient
	
	get_parent().add_child(particles)
	particles.emitting = true
	
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func spawn_destruction_particles() -> void:
	"""Subtle explosion"""

	var dust = CPUParticles2D.new()
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.amount = 20  # Reduced for less clutter
	dust.lifetime = 0.65
	dust.local_coords = false
	dust.global_position = global_position
	
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = 15.0
	
	var img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.5, 1.5, 1.6, 1.0))
	var tex = ImageTexture.create_from_image(img)
	dust.texture = tex
	
	dust.direction = Vector2(0, 0)
	dust.spread = 180.0
	dust.initial_velocity_min = 85.0
	dust.initial_velocity_max = 145.0
	dust.gravity = Vector2(0, 105)
	
	dust.scale_amount_min = 2.0
	dust.scale_amount_max = 5.0
	
	dust.color = Color(1.5, 1.5, 1.6, 1.0)
	
	var dust_gradient = Gradient.new()
	dust_gradient.add_point(0.0, Color(1, 1, 1, 1))
	dust_gradient.add_point(0.7, Color(1, 1, 1, 0.5))
	dust_gradient.add_point(1.0, Color(1, 1, 1, 0))
	dust.color_ramp = dust_gradient
	
	get_parent().add_child(dust)
	dust.emitting = true
	
	# Chunks
	var chunks = CPUParticles2D.new()
	chunks.emitting = false
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 6  # Reduced for less clutter
	chunks.lifetime = 0.85
	chunks.local_coords = false
	chunks.global_position = global_position
	
	chunks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	chunks.emission_sphere_radius = 10.0
	chunks.texture = tex
	
	chunks.direction = Vector2(0, 0)
	chunks.spread = 180.0
	chunks.initial_velocity_min = 45.0
	chunks.initial_velocity_max = 100.0
	chunks.gravity = Vector2(0, 125)
	
	chunks.scale_amount_min = 5.0
	chunks.scale_amount_max = 10.0
	
	chunks.color = Color(1.4, 1.4, 1.5, 1.0)
	
	var chunk_gradient = Gradient.new()
	chunk_gradient.add_point(0.0, Color(1, 1, 1, 1))
	chunk_gradient.add_point(0.8, Color(1, 1, 1, 0.35))
	chunk_gradient.add_point(1.0, Color(1, 1, 1, 0))
	chunks.color_ramp = chunk_gradient
	
	chunks.angular_velocity_min = -560.0
	chunks.angular_velocity_max = 560.0
	
	get_parent().add_child(chunks)
	chunks.emitting = true
	
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(dust):
		dust.queue_free()
	if is_instance_valid(chunks):
		chunks.queue_free()

## Debug
func draw_debug_hitbox(debug_container: Node2D) -> void:
	pass

func draw_debug_hitbox_world(world_container: Node2D) -> void:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color.CYAN
	line.z_index = 1000
	
	var segments = 24
	var radius = 25 * scale.x
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = global_position + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)
	
	world_container.add_child(line)
