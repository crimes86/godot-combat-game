extends Area2D
class_name Campfire

## 🔥 Campfire - Safe Haven
## - Heals player when in radius
## - Deters enemies from entering (they turn back at edge)
## - Provides warmth and safety in hostile world

# Healing configuration
@export var heal_rate: float = 5.0  # HP per second
@export var warmth_radius: float = 150.0  # Healing/deterrent radius

# Visual configuration
@export var fire_color_inner: Color = Color(1.0, 0.8, 0.2)  # Bright yellow-orange
@export var fire_color_outer: Color = Color(1.0, 0.3, 0.0)  # Deep orange-red
@export var warmth_color: Color = Color(1.0, 0.6, 0.2, 0.15)  # Warm glow

# State
var player_in_warmth: bool = false
var heal_timer: float = 0.0
var heal_interval: float = 0.5  # Heal every 0.5 seconds

# References
var player: CharacterBody2D = null
var warmth_circle: Polygon2D = null
var fire_sprite: Node2D = null

func _ready() -> void:
	# Set up collision detection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create visual representation
	create_campfire_visual()
	create_warmth_circle()

	# Add physical collision so player can't walk through fire
	add_collision_body()

	# Set collision shape to match warmth radius
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is CircleShape2D:
			collision.shape.radius = warmth_radius

	print("🔥 Campfire initialized at ", global_position)

func add_collision_body() -> void:
	"""Add StaticBody2D collision so player can't walk through campfire"""
	var collision_body = StaticBody2D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 2  # Layer 2 for obstacles
	collision_body.collision_mask = 0
	add_child(collision_body)

	# Add circular collision shape (smaller than warmth radius)
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 30.0  # Collision around fire logs
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)

	print("   Added collision body to campfire")

func _physics_process(delta: float) -> void:
	# Heal player if in warmth
	if player_in_warmth and player and is_instance_valid(player):
		heal_timer += delta
		if heal_timer >= heal_interval:
			if player.has_method("heal"):
				player.heal(heal_rate * heal_interval)
			heal_timer = 0.0
	
	# Check enemies near warmth and make them turn away
	check_enemy_deterrent()
	
	# Animate fire
	animate_fire(delta)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player = body as CharacterBody2D
		player_in_warmth = true
		heal_timer = 0.0
		print("🔥 Player entered warmth - healing active")

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_warmth = false
		player = null
		print("❄️ Player left warmth")

func check_enemy_deterrent() -> void:
	"""Deter enemies that reach the warmth radius - they get blocked at the edge"""
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var distance_to_fire = enemy.global_position.distance_to(global_position)

		# Enemy reached the campfire warmth radius
		if distance_to_fire <= warmth_radius:
			if enemy.has_node("EnemyAI"):
				var ai = enemy.get_node("EnemyAI")

				# Skip enemies in crit window (let player finish combo)
				if enemy.has_method("get") and enemy.get("in_crit_window"):
					continue

				# Only deter if in combat (chasing player)
				if ai.has_method("get") and ai.get("is_in_combat"):
					# Push enemy back to edge of warmth radius
					var direction_away = (enemy.global_position - global_position).normalized()
					var edge_position = global_position + direction_away * (warmth_radius + 10)

					# Stop enemy and position them at edge
					enemy.velocity = Vector2.ZERO
					enemy.global_position = edge_position

					# Make them look "frustrated" - small random movements
					if randf() < 0.05:  # 5% chance per frame to move slightly
						var random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
						enemy.global_position += random_offset
						enemy.global_position = global_position + (enemy.global_position - global_position).normalized() * warmth_radius

func create_campfire_visual() -> void:
	"""Create an improved campfire with particle effects"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.position = Vector2(0, -10)  # ADD THIS LINE - shifts fire up so it centers better
	add_child(fire_sprite)
	
	# === LOGS === (more detailed, stacked arrangement)
	var log_color_dark = Color(0.25, 0.15, 0.08, 1.0)
	var log_color = Color(0.35, 0.22, 0.12, 1.0)
	var log_color_light = Color(0.45, 0.28, 0.15, 1.0)
	
	# Bottom log (horizontal)
	var log1 = Polygon2D.new()
	log1.polygon = PackedVector2Array([
		Vector2(-25, 15),
		Vector2(25, 15),
		Vector2(22, 12),
		Vector2(-22, 12)
	])
	log1.color = log_color
	fire_sprite.add_child(log1)
	
	# Log highlight
	var log1_highlight = Line2D.new()
	log1_highlight.width = 2.0
	log1_highlight.default_color = log_color_light
	log1_highlight.add_point(Vector2(-22, 12))
	log1_highlight.add_point(Vector2(22, 12))
	fire_sprite.add_child(log1_highlight)
	
	# Left angled log
	var log2 = Polygon2D.new()
	log2.polygon = PackedVector2Array([
		Vector2(-18, 12),
		Vector2(-8, 8),
		Vector2(-6, 10),
		Vector2(-16, 14)
	])
	log2.color = log_color_dark
	fire_sprite.add_child(log2)
	
	# Right angled log
	var log3 = Polygon2D.new()
	log3.polygon = PackedVector2Array([
		Vector2(18, 12),
		Vector2(8, 8),
		Vector2(6, 10),
		Vector2(16, 14)
	])
	log3.color = log_color_dark
	fire_sprite.add_child(log3)
	
	# === COALS/EMBERS === (glowing base under flames)
	var coals = Polygon2D.new()
	var coal_points = PackedVector2Array()
	for i in range(12):
		var angle = (i * TAU) / 12.0
		var radius = 12.0 + randf() * 3.0
		coal_points.append(Vector2(cos(angle), sin(angle)) * radius)
	coals.polygon = coal_points
	coals.color = Color(0.8, 0.2, 0.0, 1.0)  # Hot orange
	coals.name = "Coals"
	fire_sprite.add_child(coals)
	
	# === FLAMES === (layered for depth)
	# Back flames (darker)
	for i in range(2):
		var flame = Polygon2D.new()
		var offset = (i - 0.5) * 16
		var height = 25 + randf() * 8
		flame.polygon = PackedVector2Array([
			Vector2(offset - 6, 0),
			Vector2(offset - 10, -height * 0.7),
			Vector2(offset - 4, -height),
			Vector2(offset + 4, -height),
			Vector2(offset + 10, -height * 0.7),
			Vector2(offset + 6, 0)
		])
		flame.color = fire_color_outer
		flame.name = "FlameBack" + str(i)
		flame.z_index = -1
		fire_sprite.add_child(flame)
	
	# Front flames (brighter)
	for i in range(3):
		var flame = Polygon2D.new()
		var offset = (i - 1) * 12
		var height = 22 + randf() * 10
		flame.polygon = PackedVector2Array([
			Vector2(offset - 5, 0),
			Vector2(offset - 8, -height * 0.6),
			Vector2(offset - 3, -height),
			Vector2(offset + 3, -height),
			Vector2(offset + 8, -height * 0.6),
			Vector2(offset + 5, 0)
		])
		flame.color = fire_color_inner if i % 2 == 0 else fire_color_outer.lerp(fire_color_inner, 0.3)
		flame.name = "Flame" + str(i)
		fire_sprite.add_child(flame)
	
	# === INNER GLOW === (bright core)
	var inner_glow = Polygon2D.new()
	var glow_segments = 8
	var glow_points = PackedVector2Array()
	for i in range(glow_segments):
		var angle = (i * TAU) / glow_segments
		var point = Vector2(cos(angle), sin(angle)) * 18.0
		glow_points.append(point)
	inner_glow.polygon = glow_points
	inner_glow.color = Color(1.0, 0.9, 0.3, 0.6)
	inner_glow.name = "InnerGlow"
	fire_sprite.add_child(inner_glow)
	
	# === OUTER GLOW === (warm ambient light)
	var outer_glow = Polygon2D.new()
	var outer_segments = 16
	var outer_points = PackedVector2Array()
	for i in range(outer_segments):
		var angle = (i * TAU) / outer_segments
		var point = Vector2(cos(angle), sin(angle)) * 35.0
		outer_points.append(point)
	outer_glow.polygon = outer_points
	outer_glow.color = Color(1.0, 0.5, 0.0, 0.25)
	outer_glow.z_index = -2
	fire_sprite.add_child(outer_glow)
	
	# === PARTICLE EFFECTS ===
	create_particle_effects()

func create_particle_effects() -> void:
	"""Add smoke and ember particle effects"""
	
	# SMOKE particles
	var smoke_particles = CPUParticles2D.new()
	smoke_particles.name = "SmokeParticles"
	smoke_particles.emitting = true
	smoke_particles.amount = 8
	smoke_particles.lifetime = 2.0
	smoke_particles.preprocess = 0.5
	
	# Smoke appearance
	smoke_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke_particles.emission_sphere_radius = 8.0
	
	# Smoke movement
	smoke_particles.direction = Vector2(0, -1)
	smoke_particles.spread = 20.0
	smoke_particles.gravity = Vector2(0, -10)
	smoke_particles.initial_velocity_min = 15.0
	smoke_particles.initial_velocity_max = 25.0
	
	# Smoke visuals
	smoke_particles.scale_amount_min = 2.0
	smoke_particles.scale_amount_max = 4.0
	smoke_particles.scale_amount_curve = Curve.new()
	smoke_particles.scale_amount_curve.add_point(Vector2(0, 0.5))
	smoke_particles.scale_amount_curve.add_point(Vector2(0.5, 1.0))
	smoke_particles.scale_amount_curve.add_point(Vector2(1, 0.3))
	
	# Smoke color (gray/white)
	smoke_particles.color = Color(0.3, 0.3, 0.3, 0.4)
	smoke_particles.color_ramp = Gradient.new()
	smoke_particles.color_ramp.add_point(0.0, Color(0.4, 0.35, 0.3, 0.6))
	smoke_particles.color_ramp.add_point(0.5, Color(0.3, 0.3, 0.3, 0.4))
	smoke_particles.color_ramp.add_point(1.0, Color(0.2, 0.2, 0.2, 0.0))
	
	fire_sprite.add_child(smoke_particles)
	
	# EMBER particles (bright sparks)
	var ember_particles = CPUParticles2D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.emitting = true
	ember_particles.amount = 12
	ember_particles.lifetime = 1.5
	ember_particles.preprocess = 0.3
	
	# Ember appearance
	ember_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ember_particles.emission_sphere_radius = 10.0
	
	# Ember movement (float upward)
	ember_particles.direction = Vector2(0, -1)
	ember_particles.spread = 30.0
	ember_particles.gravity = Vector2(0, -15)
	ember_particles.initial_velocity_min = 20.0
	ember_particles.initial_velocity_max = 40.0
	
	# Ember visuals (small bright dots)
	ember_particles.scale_amount_min = 0.5
	ember_particles.scale_amount_max = 1.5
	ember_particles.scale_amount_curve = Curve.new()
	ember_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	ember_particles.scale_amount_curve.add_point(Vector2(0.8, 0.8))
	ember_particles.scale_amount_curve.add_point(Vector2(1, 0.0))
	
	# Ember color (bright orange to dark)
	ember_particles.color = Color(1.0, 0.6, 0.2, 1.0)
	ember_particles.color_ramp = Gradient.new()
	ember_particles.color_ramp.add_point(0.0, Color(1.0, 0.9, 0.4, 1.0))
	ember_particles.color_ramp.add_point(0.3, Color(1.0, 0.5, 0.2, 1.0))
	ember_particles.color_ramp.add_point(0.7, Color(0.8, 0.2, 0.0, 0.6))
	ember_particles.color_ramp.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))
	
	fire_sprite.add_child(ember_particles)

func create_warmth_circle() -> void:
	"""Create gradient warmth circle with radial falloff"""
	warmth_circle = Polygon2D.new()
	warmth_circle.name = "WarmthCircle"
	warmth_circle.z_index = -10
	warmth_circle.visible = false
	
	# Create circle with many segments for smooth gradients
	var segments = 64
	var points = PackedVector2Array()
	var colors = PackedColorArray()
	
	# Center point
	points.append(Vector2.ZERO)
	colors.append(Color(1.0, 0.7, 0.3, 0.3))  # Warm orange-yellow center
	
	# Outer ring points
	for i in range(segments):
		var angle = (i * TAU) / segments
		var point = Vector2(cos(angle), sin(angle)) * warmth_radius
		points.append(point)
		colors.append(Color(0.8, 0.4, 0.1, 0.0))  # Fade to transparent at edge
	
	# Close the circle
	var angle = 0.0
	var point = Vector2(cos(angle), sin(angle)) * warmth_radius
	points.append(point)
	colors.append(Color(0.8, 0.4, 0.1, 0.0))
	
	warmth_circle.polygon = points
	warmth_circle.vertex_colors = colors
	add_child(warmth_circle)

func animate_fire(delta: float) -> void:
	"""Enhanced flickering animation for fire with scale, position, and color changes"""
	if not fire_sprite:
		return
	
	var time = Time.get_ticks_msec() / 1000.0
	
	# Animate individual flames with different speeds
	for child in fire_sprite.get_children():
		if child.name.begins_with("Flame"):
			var idx = child.get_index()
			var speed = 1.5 + idx * 0.3
			var flicker = sin(time * speed + idx * 1.2)
			var flicker2 = cos(time * speed * 0.7 + idx * 0.8)
			
			# Vertical scale (height flicker)
			child.scale.y = 1.0 + flicker * 0.25
			# Slight horizontal sway
			child.scale.x = 1.0 + flicker2 * 0.15
			# Opacity flicker
			child.modulate.a = 0.85 + flicker * 0.15
			# Slight position wobble
			child.position.x = flicker2 * 2.0
	
	# Animate coals (pulsing glow)
	for child in fire_sprite.get_children():
		if child.name == "Coals":
			var pulse = sin(time * 2.0)
			child.modulate = Color(1.0, 1.0, 1.0, 0.9 + pulse * 0.1)
			child.scale = Vector2.ONE * (1.0 + pulse * 0.05)
	
	# Animate inner glow (bright pulse)
	for child in fire_sprite.get_children():
		if child.name == "InnerGlow":
			var pulse = sin(time * 3.0)
			child.modulate.a = 0.6 + pulse * 0.2
			child.scale = Vector2.ONE * (1.0 + pulse * 0.1)
	
	# Animate outer glow (slow breathe)
	for child in fire_sprite.get_children():
		if child.name == "OuterGlow" or child is Polygon2D:
			if "glow" in child.name.to_lower():
				var breathe = sin(time * 0.8)
				child.modulate.a = child.modulate.a * (0.9 + breathe * 0.1)
	
	# Subtle warmth circle pulse
	if warmth_circle:
		var pulse = sin(time * 0.5)
		warmth_circle.modulate.a = 0.9 + pulse * 0.1

func get_deterrent_radius() -> float:
	"""Return the radius that deters enemies"""
	return warmth_radius
