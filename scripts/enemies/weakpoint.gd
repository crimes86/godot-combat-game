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

	# 🫀 VITAL ORGAN - Dark but shiny blood red
	sprite = Polygon2D.new()
	sprite.color = Color(0.9, 0.12, 0.12, 1.0)  # Brighter dark blood red (more visible)

	# Organic oval/heart shape - like looking at a vital organ
	var points = PackedVector2Array()
	var size = 18.0
	var segments = 12

	# Create smooth organic shape (elongated oval, slightly irregular)
	for i in range(segments):
		var angle = (i * TAU) / segments
		var radius = size * (0.8 + 0.2 * sin(angle * 3))  # Slight irregularity
		var x = cos(angle) * radius * 0.8  # Slightly flattened horizontally
		var y = sin(angle) * radius
		points.append(Vector2(x, y))

	sprite.polygon = points
	add_child(sprite)

	# 🩸 INTENSE BLOOD GLOW - Makes it look wet/shiny/alive
	glow_sprite = Polygon2D.new()
	glow_sprite.color = Color(1.4, 0.2, 0.2, 0.85)  # Bright shiny blood glow
	glow_sprite.z_index = -1

	# Make glow slightly larger for depth
	var glow_points = PackedVector2Array()
	var glow_scale = 1.4
	for point in points:
		glow_points.append(point * glow_scale)
	glow_sprite.polygon = glow_points
	sprite.add_child(glow_sprite)

	# ✨ SHINE HIGHLIGHT - makes it look wet/glossy
	var shine = Polygon2D.new()
	shine.color = Color(2.0, 0.6, 0.6, 0.5)  # Bright red-white shine
	shine.z_index = 1

	# Small highlight spot on top-left (like light reflecting off wet surface)
	var shine_points = PackedVector2Array()
	shine_points.append(Vector2(-4, -6))
	shine_points.append(Vector2(2, -7))
	shine_points.append(Vector2(3, -3))
	shine_points.append(Vector2(-2, -2))
	shine.polygon = shine_points
	sprite.add_child(shine)

	# 💓 HEARTBEAT PULSE - thump-thump rhythm
	start_heartbeat_pulse()

	# Dark outline for contrast
	var outline = Line2D.new()
	outline.width = 2.0
	outline.default_color = Color(0.25, 0.03, 0.03, 1.0)  # Dark red-black outline
	outline.closed = true
	for point in points:
		outline.add_point(point)
	sprite.add_child(outline)

	# NO SPARKLES - clean anatomical look

	# Forgiving hitbox
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 25
	col.shape = shape
	add_child(col)

	input_event.connect(_on_input)
	max_hits = randi_range(3, 5)

func start_heartbeat_pulse() -> void:
	"""Heartbeat pulse - thump-thump rhythm like a vital organ"""
	if not sprite or not glow_sprite:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_CIRC)  # More organic curve
	tween.set_ease(Tween.EASE_IN_OUT)

	# THUMP (quick expand)
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.15)
	tween.parallel().tween_property(glow_sprite, "color:a", 1.0, 0.15)

	# Release (quick contract)
	tween.tween_property(sprite, "scale", Vector2(0.95, 0.95), 0.15)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.6, 0.15)

	# THUMP (second beat)
	tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.12)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.95, 0.12)

	# Release and rest
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.7, 0.2)

	# Pause before next heartbeat
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.4)

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
	
	# Red sparkle texture
	var img = Image.create(7, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(2, 5):
		for y in range(2, 5):
			img.set_pixel(x, y, Color(2.0, 0.3, 0.3, 1.0))
	var tex = ImageTexture.create_from_image(img)
	sparkle_particles.texture = tex

	sparkle_particles.direction = Vector2(0, -1)
	sparkle_particles.spread = 180.0
	sparkle_particles.initial_velocity_min = 12.0
	sparkle_particles.initial_velocity_max = 25.0
	sparkle_particles.gravity = Vector2(0, -12)

	sparkle_particles.scale_amount_min = 2.0
	sparkle_particles.scale_amount_max = 4.0

	# Red sparkles
	sparkle_particles.color = Color(2.0, 0.3, 0.3, 1.0)
	
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

	# 🩸 BLOOD BURST feedback - fast and responsive for spam-clicking
	if sprite:
		var progress = float(current_hits) / float(max_hits)
		var scale_factor = 1.0 - (progress * 0.3)

		# 🔴 FRESH BLOOD FLASH - bright oxygenated red
		sprite.color = Color(1.2, 0.15, 0.15, 1.0)  # Bright fresh blood red
		sprite.rotation += 0.25

		var flash_tween = create_tween()
		flash_tween.set_parallel(true)

		# Fast color return to dark blood (snappy feedback)
		flash_tween.tween_property(sprite, "color", Color(0.9, 0.12, 0.12, 1.0), 0.08)

		# Quick squish (like hitting an organ)
		var pop_scale = Vector2(1.3, 1.3) * scale_factor
		sprite.scale = pop_scale
		flash_tween.tween_property(sprite, "scale", Vector2(scale_factor, scale_factor), 0.08).set_ease(Tween.EASE_OUT)

		# Blood glow burst
		if glow_sprite:
			glow_sprite.color = Color(1.0, 0.2, 0.2, 1.0)  # Bright blood glow
			flash_tween.tween_property(glow_sprite, "color", Color(0.8, 0.1, 0.1, 0.7), 0.08)

	if current_hits >= max_hits:
		destroy()

func spawn_hit_number() -> void:
	"""Show HIT indicator"""
	var label = Label.new()
	label.text = "CRACK!"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(2.2, 0.5, 0.3, 1.0))  # Red-orange
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
	ring.default_color = Color(2.0, 0.3, 0.3, 1.0)  # Bright red
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
	"""💥 EXPLOSIVE BLOOD SHOCKWAVES"""
	# Get world container to avoid parent scaling issues
	var world = get_tree().root.get_node_or_null("World")
	if not world:
		return

	for i in range(4):  # 4 waves instead of 3
		await get_tree().create_timer(i * 0.04).timeout

		var ring = Line2D.new()
		ring.width = 5.5 - i  # Thicker initial wave
		ring.default_color = Color(1.8, 0.2, 0.2, 1.0)  # Deep blood red
		ring.z_index = 299

		var segments = 64  # Smoother circles
		for j in range(segments + 1):
			var angle = (j * TAU) / segments
			var point = Vector2(cos(angle), sin(angle)) * 25  # Start larger
			ring.add_point(point)

		ring.global_position = global_position
		world.add_child(ring)
		
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
	img.fill(Color(2.0, 0.3, 0.3, 1.0))
	var tex = ImageTexture.create_from_image(img)
	particles.texture = tex

	particles.direction = Vector2(0, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 55.0
	particles.initial_velocity_max = 100.0
	particles.gravity = Vector2(0, 85)

	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0

	particles.color = Color(2.0, 0.3, 0.3, 1.0)
	
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
	"""💥 DRAMATIC BLOOD EXPLOSION when weakpoint destroyed"""
	# Get world container to avoid parent scaling issues
	var world = get_tree().root.get_node_or_null("World")
	if not world:
		return

	# 🩸 BLOOD SPRAY - bright red particles bursting out
	var blood_spray = CPUParticles2D.new()
	blood_spray.emitting = false
	blood_spray.one_shot = true
	blood_spray.explosiveness = 1.0
	blood_spray.amount = 40  # More particles for dramatic effect
	blood_spray.lifetime = 0.8
	blood_spray.local_coords = false
	blood_spray.global_position = global_position

	blood_spray.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	blood_spray.emission_sphere_radius = 20.0

	var img = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.5, 0.15, 0.15, 1.0))  # Bright blood red
	var tex = ImageTexture.create_from_image(img)
	blood_spray.texture = tex

	blood_spray.direction = Vector2(0, 0)
	blood_spray.spread = 180.0
	blood_spray.initial_velocity_min = 100.0
	blood_spray.initial_velocity_max = 200.0  # Faster burst
	blood_spray.gravity = Vector2(0, 120)

	blood_spray.scale_amount_min = 2.5
	blood_spray.scale_amount_max = 6.0  # Bigger particles

	blood_spray.color = Color(1.5, 0.15, 0.15, 1.0)

	var spray_gradient = Gradient.new()
	spray_gradient.add_point(0.0, Color(1, 1, 1, 1))
	spray_gradient.add_point(0.6, Color(1, 1, 1, 0.6))
	spray_gradient.add_point(1.0, Color(1, 1, 1, 0))
	blood_spray.color_ramp = spray_gradient

	world.add_child(blood_spray)
	blood_spray.emitting = true

	# 💀 DARK BLOOD CHUNKS - slower, heavier pieces
	var chunks = CPUParticles2D.new()
	chunks.emitting = false
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 12  # More chunks
	chunks.lifetime = 1.0
	chunks.local_coords = false
	chunks.global_position = global_position

	chunks.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	chunks.emission_sphere_radius = 15.0
	chunks.texture = tex

	chunks.direction = Vector2(0, 0)
	chunks.spread = 180.0
	chunks.initial_velocity_min = 60.0
	chunks.initial_velocity_max = 130.0
	chunks.gravity = Vector2(0, 150)

	chunks.scale_amount_min = 5.0
	chunks.scale_amount_max = 10.0

	chunks.color = Color(1.8, 0.2, 0.2, 1.0)  # Dark red chunks

	var chunk_gradient = Gradient.new()
	chunk_gradient.add_point(0.0, Color(1, 1, 1, 1))
	chunk_gradient.add_point(0.8, Color(1, 1, 1, 0.35))
	chunk_gradient.add_point(1.0, Color(1, 1, 1, 0))
	chunks.color_ramp = chunk_gradient

	chunks.angular_velocity_min = -560.0
	chunks.angular_velocity_max = 560.0

	world.add_child(chunks)
	chunks.emitting = true

	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(blood_spray):
		blood_spray.queue_free()
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
