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
var fire_audio: AudioStreamPlayer2D = null

func _ready() -> void:
	# Add to campfire group so NPCs can find and face it
	add_to_group("campfire")

	# Set up collision detection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create visual representation
	create_scorched_ground()  # Add burnt ground first (lowest layer)
	create_campfire_visual()
	create_warmth_circle()

	# Create lighting
	create_fire_light()

	# Create looping fire sound
	create_fire_audio()

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
	"""Create enhanced campfire with detailed logs, rocks, and particle effects"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.position = Vector2(0, -10)
	fire_sprite.scale = Vector2(2.0, 2.0)  # Scale up 2x
	add_child(fire_sprite)

	# === ROCK RING === (surrounding the fire pit)
	var rock_colors = [
		Color(0.35, 0.32, 0.30, 1.0),  # Grey
		Color(0.40, 0.35, 0.32, 1.0),  # Light grey-brown
		Color(0.30, 0.28, 0.26, 1.0),  # Dark grey
	]

	# Create 12 rocks in a tighter circle around fire (reduced and tightened)
	for i in range(12):
		var angle = (i * TAU) / 12.0 + randf_range(-0.1, 0.1)
		var distance = 28.0 + randf_range(-2, 2)
		var rock_pos = Vector2(cos(angle), sin(angle)) * distance

		var rock = Polygon2D.new()
		rock.name = "Rock" + str(i)
		rock.z_index = -3

		# Irregular rock shape with smaller sizes
		var rock_size = randf_range(4.0, 6.5)
		var rock_points = PackedVector2Array()
		for j in range(6):
			var rock_angle = (j * TAU) / 6.0
			var rock_radius = rock_size * randf_range(0.7, 1.0)
			rock_points.append(rock_pos + Vector2(cos(rock_angle), sin(rock_angle)) * rock_radius)
		rock.polygon = rock_points
		rock.color = rock_colors[i % rock_colors.size()]

		# Add highlight to top of rock
		var highlight = Line2D.new()
		highlight.width = 1.0
		highlight.default_color = Color(0.5, 0.48, 0.45, 0.6)
		highlight.add_point(rock_points[0])
		highlight.add_point(rock_points[1])
		rock.add_child(highlight)

		fire_sprite.add_child(rock)

	# === WOOD LOGS === (triangle teepee formation, deteriorating)
	var log_color_burnt = Color(0.15, 0.12, 0.10, 1.0)  # Charred
	var log_color_dark = Color(0.25, 0.18, 0.12, 1.0)   # Dark wood
	var log_color = Color(0.35, 0.25, 0.18, 1.0)        # Medium wood
	var log_color_light = Color(0.45, 0.32, 0.22, 1.0)  # Light wood
	var ember_glow = Color(1.0, 0.3, 0.0, 0.8)          # Glowing embers

	# Bottom logs (stacked on top of coals - teepee formation)
	# Left log (leaning right) - positioned on coals, 50% thicker
	var log_left = Polygon2D.new()
	log_left.polygon = PackedVector2Array([
		Vector2(-23, 9),     # Bottom left (moved up 20px from 29)
		Vector2(-8, -14),    # Top left (moved up 20px from 6)
		Vector2(-5, -13),    # Top right (moved up 20px from 7)
		Vector2(-20, 11)     # Bottom right (moved up 20px from 31)
	])
	log_left.color = log_color
	log_left.name = "LogLeft"
	log_left.z_index = -1  # Above coals
	fire_sprite.add_child(log_left)

	# Left log charred end (50% thicker, moved up 20px)
	var log_left_char = Polygon2D.new()
	log_left_char.polygon = PackedVector2Array([
		Vector2(-20, 9),     # Moved up 20px from 29
		Vector2(-17, 7),     # Moved up 20px from 27
		Vector2(-15, 9),     # Moved up 20px from 29
		Vector2(-18, 11)     # Moved up 20px from 31
	])
	log_left_char.color = log_color_burnt
	log_left_char.z_index = -1
	fire_sprite.add_child(log_left_char)

	# Left log highlight (thicker, moved up 20px)
	var log_left_highlight = Line2D.new()
	log_left_highlight.width = 2.25  # 50% thicker (1.5 * 1.5)
	log_left_highlight.default_color = log_color_light
	log_left_highlight.add_point(Vector2(-20, 11))   # Moved up 20px from 31
	log_left_highlight.add_point(Vector2(-5, -13))   # Moved up 20px from 7
	log_left_highlight.z_index = -1
	fire_sprite.add_child(log_left_highlight)

	# Right log (leaning left) - 50% thicker
	var log_right = Polygon2D.new()
	log_right.polygon = PackedVector2Array([
		Vector2(23, 9),      # Bottom right (moved up 20px from 29)
		Vector2(8, -14),     # Top right (moved up 20px from 6)
		Vector2(5, -13),     # Top left (moved up 20px from 7)
		Vector2(20, 11)      # Bottom left (moved up 20px from 31)
	])
	log_right.color = log_color
	log_right.name = "LogRight"
	log_right.z_index = -1
	fire_sprite.add_child(log_right)

	# Right log charred end (50% thicker, moved up 20px)
	var log_right_char = Polygon2D.new()
	log_right_char.polygon = PackedVector2Array([
		Vector2(20, 9),      # Moved up 20px from 29
		Vector2(17, 7),      # Moved up 20px from 27
		Vector2(15, 9),      # Moved up 20px from 29
		Vector2(18, 11)      # Moved up 20px from 31
	])
	log_right_char.color = log_color_burnt
	log_right_char.z_index = -1
	fire_sprite.add_child(log_right_char)

	# Right log highlight (thicker, moved up 20px)
	var log_right_highlight = Line2D.new()
	log_right_highlight.width = 2.25  # 50% thicker (1.5 * 1.5)
	log_right_highlight.default_color = log_color_light
	log_right_highlight.add_point(Vector2(20, 11))   # Moved up 20px from 31
	log_right_highlight.add_point(Vector2(5, -13))   # Moved up 20px from 7
	log_right_highlight.z_index = -1
	fire_sprite.add_child(log_right_highlight)

	# Back center log (50% thicker, moved up 20px)
	var log_back = Polygon2D.new()
	log_back.polygon = PackedVector2Array([
		Vector2(-3, 9),     # Bottom left (moved up 20px from 29)
		Vector2(3, 9),      # Bottom right (moved up 20px from 29)
		Vector2(4.5, -17),  # Top right (moved up 20px from 3)
		Vector2(-4.5, -17)  # Top left (moved up 20px from 3)
	])
	log_back.color = log_color_dark
	log_back.z_index = -1
	log_back.name = "LogBack"
	fire_sprite.add_child(log_back)

	# Back log charred end (moved up 20px, thicker)
	var log_back_char = Polygon2D.new()
	log_back_char.polygon = PackedVector2Array([
		Vector2(-3, 9),      # Moved up 20px from 29
		Vector2(3, 9),       # Moved up 20px from 29
		Vector2(1.5, 6),     # Moved up 20px from 26
		Vector2(-1.5, 6)     # Moved up 20px from 26
	])
	log_back_char.color = log_color_burnt
	log_back_char.z_index = -1
	fire_sprite.add_child(log_back_char)

	# Add some smaller broken logs at base (50% thicker, moved up 20px)
	for i in range(3):
		var broken_log = Polygon2D.new()
		var offset_x = randf_range(-15, 15)
		broken_log.polygon = PackedVector2Array([
			Vector2(offset_x - 6, 13),    # Moved up 20px from 33
			Vector2(offset_x + 6, 13),    # Moved up 20px from 33
			Vector2(offset_x + 4.5, 11),  # Moved up 20px from 31
			Vector2(offset_x - 4.5, 11)   # Moved up 20px from 31
		])
		broken_log.color = log_color_dark
		broken_log.z_index = -1
		fire_sprite.add_child(broken_log)
	
	# === GLOWING COAL BED === (spread across rockbed, below flames, semi-transparent)
	# Create coals filling rock circle, below flames so fire is visible
	for i in range(35):  # Reduced count - less cluttered
		var coal = Polygon2D.new()
		# Spread across ENTIRE rockbed area (rock ring is ~28px radius)
		var angle = randf() * TAU
		var distance = randf() * 28.0  # Fill entire rock circle radius
		var coal_offset = Vector2(cos(angle), sin(angle)) * distance
		coal_offset.y = abs(coal_offset.y) * 0.4 + randf_range(0, 8)  # Spread y from 0-10 range

		# Size varies - smaller at edges
		var distance_ratio = distance / 28.0  # 0 at center, 1 at edge
		var coal_size = randf_range(3.0, 5.5) * (1.3 - distance_ratio * 0.5)  # Smaller at edges

		var coal_points = PackedVector2Array()
		for j in range(5):
			var coal_angle = (j * TAU) / 5.0
			var radius = coal_size * randf_range(0.8, 1.0)
			coal_points.append(coal_offset + Vector2(cos(coal_angle), sin(coal_angle)) * radius)
		coal.polygon = coal_points

		# Fade intensity from bright center to dimmer edges, with transparency
		var coal_brightness = randf_range(0.7, 1.0) * (1.2 - distance_ratio * 0.6)  # Dimmer at edges
		coal_brightness = clamp(coal_brightness, 0.3, 1.0)
		var coal_alpha = randf_range(0.6, 0.8)  # Semi-transparent
		coal.color = Color(1.0 * coal_brightness, 0.3 * coal_brightness, 0.0, coal_alpha)
		coal.name = "Coal" + str(i)
		coal.z_index = -2  # Below wood and flames
		fire_sprite.add_child(coal)

		# Add bright ember glow on coals (brighter at center, dimmer at edges)
		if randf() > 0.4:  # Less frequent
			var ember_glow_poly = Polygon2D.new()
			var ember_points = PackedVector2Array()
			for j in range(4):
				var glow_angle = (j * TAU) / 4.0
				ember_points.append(coal_offset + Vector2(cos(glow_angle), sin(glow_angle)) * coal_size * 0.5)
			ember_glow_poly.polygon = ember_points
			# Ember glow fades with distance from center, semi-transparent
			var glow_alpha = 0.7 * (1.2 - distance_ratio * 0.7)  # More transparent
			glow_alpha = clamp(glow_alpha, 0.2, 0.7)
			ember_glow_poly.color = Color(1.0, 0.9, 0.4, glow_alpha)
			ember_glow_poly.z_index = -2  # Below wood and flames
			fire_sprite.add_child(ember_glow_poly)

	# === PARTICLE-BASED FLAMES === (realistic, organic fire)
	create_fire_particles()

	# === HEAT SHIMMER GLOW === (very subtle base glow only)
	# Removed inner glow - too obvious as yellow ring

	# Subtle base glow beneath fire
	var base_glow = Polygon2D.new()
	var base_points = PackedVector2Array()
	for i in range(16):
		var angle = (i * TAU) / 16.0
		var radius = 25.0 + randf() * 3.0
		base_points.append(Vector2(cos(angle), sin(angle)) * radius)
	base_glow.polygon = base_points
	base_glow.color = Color(1.0, 0.5, 0.1, 0.08)  # Very faint orange glow
	base_glow.z_index = -1
	fire_sprite.add_child(base_glow)
	
	# === PARTICLE EFFECTS ===
	create_particle_effects()

func create_particle_effects() -> void:
	"""Add enhanced smoke and ember particle effects for 2x scale campfire"""

	# SMOKE particles - subtle and minimal (3-5 particles)
	var smoke_particles = CPUParticles2D.new()
	smoke_particles.name = "SmokeParticles"
	smoke_particles.emitting = true
	smoke_particles.amount = 4  # Minimal - just 3-5 particles
	smoke_particles.lifetime = 5.0  # Long lifetime for slow drift
	smoke_particles.preprocess = 1.0

	# Smoke appearance - small emission area
	smoke_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	smoke_particles.emission_sphere_radius = 8.0  # Concentrated at fire top

	# Smoke movement - slow gentle drift upward
	smoke_particles.direction = Vector2(0, -1)
	smoke_particles.spread = 15.0  # Minimal spread
	smoke_particles.gravity = Vector2(0, -5)  # Very light gravity for slow drift
	smoke_particles.initial_velocity_min = 8.0  # Slow rise
	smoke_particles.initial_velocity_max = 15.0

	# Smoke visuals - translucent wisps
	smoke_particles.scale_amount_min = 2.0
	smoke_particles.scale_amount_max = 4.0
	smoke_particles.scale_amount_curve = Curve.new()
	smoke_particles.scale_amount_curve.add_point(Vector2(0, 0.2))  # Start small
	smoke_particles.scale_amount_curve.add_point(Vector2(0.3, 1.0))  # Grow
	smoke_particles.scale_amount_curve.add_point(Vector2(1, 0.1))  # Fade small

	# Smoke color - very translucent
	smoke_particles.color = Color(0.3, 0.28, 0.25, 0.25)  # Very transparent
	smoke_particles.color_ramp = Gradient.new()
	smoke_particles.color_ramp.add_point(0.0, Color(0.35, 0.32, 0.28, 0.3))  # Translucent start
	smoke_particles.color_ramp.add_point(0.5, Color(0.3, 0.28, 0.25, 0.2))   # Lighter
	smoke_particles.color_ramp.add_point(1.0, Color(0.25, 0.24, 0.22, 0.0))  # Fade completely

	fire_sprite.add_child(smoke_particles)

	# EMBER particles (bright sparks shooting upward) - significantly more!
	var ember_particles = CPUParticles2D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.emitting = true
	ember_particles.amount = 35  # Much more embers for dramatic effect
	ember_particles.lifetime = 2.2  # Longer lifetime
	ember_particles.preprocess = 0.5

	# Ember appearance - larger emission area
	ember_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ember_particles.emission_sphere_radius = 20.0  # Wider area

	# Ember movement - shoot high into the air
	ember_particles.direction = Vector2(0, -1)
	ember_particles.spread = 35.0  # More spread for variety
	ember_particles.gravity = Vector2(0, -12)  # Lighter gravity = shoot higher
	ember_particles.initial_velocity_min = 40.0  # Much faster shooting
	ember_particles.initial_velocity_max = 80.0  # Some embers shoot very high

	# Ember visuals - varied sizes for realism
	ember_particles.scale_amount_min = 0.8
	ember_particles.scale_amount_max = 2.5
	ember_particles.scale_amount_curve = Curve.new()
	ember_particles.scale_amount_curve.add_point(Vector2(0, 1.2))  # Start bright
	ember_particles.scale_amount_curve.add_point(Vector2(0.3, 1.0))
	ember_particles.scale_amount_curve.add_point(Vector2(0.85, 0.6))  # Fade
	ember_particles.scale_amount_curve.add_point(Vector2(1, 0.0))  # Disappear

	# Ember color - bright glowing orange to dark red
	ember_particles.color = Color(1.0, 0.65, 0.25, 1.0)
	ember_particles.color_ramp = Gradient.new()
	ember_particles.color_ramp.add_point(0.0, Color(1.0, 1.0, 0.6, 1.0))   # Bright white-yellow start
	ember_particles.color_ramp.add_point(0.2, Color(1.0, 0.8, 0.3, 1.0))   # Bright yellow-orange
	ember_particles.color_ramp.add_point(0.5, Color(1.0, 0.5, 0.2, 0.9))   # Orange
	ember_particles.color_ramp.add_point(0.8, Color(0.7, 0.2, 0.0, 0.5))   # Dark red
	ember_particles.color_ramp.add_point(1.0, Color(0.2, 0.05, 0.0, 0.0))  # Fade to black

	fire_sprite.add_child(ember_particles)

	# SPARK particles (quick bright flashes) - new addition
	var spark_particles = CPUParticles2D.new()
	spark_particles.name = "SparkParticles"
	spark_particles.emitting = true
	spark_particles.amount = 25  # Lots of small sparks
	spark_particles.lifetime = 0.8  # Short-lived quick sparks
	spark_particles.preprocess = 0.2

	# Spark appearance - concentrated at fire center
	spark_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	spark_particles.emission_sphere_radius = 12.0

	# Spark movement - explosive outward burst
	spark_particles.direction = Vector2(0, -1)
	spark_particles.spread = 180.0  # All directions
	spark_particles.gravity = Vector2(0, 20)  # Fall back down quickly
	spark_particles.initial_velocity_min = 30.0
	spark_particles.initial_velocity_max = 60.0

	# Spark visuals - tiny bright points
	spark_particles.scale_amount_min = 0.3
	spark_particles.scale_amount_max = 1.0
	spark_particles.scale_amount_curve = Curve.new()
	spark_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	spark_particles.scale_amount_curve.add_point(Vector2(0.5, 0.7))
	spark_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Spark color - very bright yellow-white
	spark_particles.color = Color(1.0, 0.95, 0.7, 1.0)
	spark_particles.color_ramp = Gradient.new()
	spark_particles.color_ramp.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))    # Bright white
	spark_particles.color_ramp.add_point(0.3, Color(1.0, 0.9, 0.5, 0.9))    # Yellow
	spark_particles.color_ramp.add_point(0.7, Color(1.0, 0.5, 0.1, 0.4))    # Orange fade
	spark_particles.color_ramp.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))    # Dark

	fire_sprite.add_child(spark_particles)

func create_fire_particles() -> void:
	"""Create simple layered polygon flames - back to basics"""

	# Create 3 simple flame layers for natural fire look
	for layer in range(3):
		for i in range(3 + layer * 2):  # 3, 5, 7 flames per layer
			var flame = Polygon2D.new()
			var offset = (i - (1 + layer)) * (8 - layer * 2)  # Tighter as we go up
			# Top layer shorter: 20, 15, 7 (instead of 10)
			var height = (20 - layer * 5) + randf() * 3
			if layer == 2:  # Top layer
				height = 7 + randf() * 2
			var base_width = (6.0 - layer * 1.5)

			# Vary base Y
			var base_y = 10 - layer * 3 + abs(offset) * 0.15

			# Gentle sway
			var lean = offset * 0.3
			var sway = randf_range(-0.4, 0.4)

			# Simple flame shape
			flame.polygon = PackedVector2Array([
				Vector2(offset - base_width, base_y),
				Vector2(offset - base_width * 0.7 + lean * 0.4 + sway, -height * 0.5),
				Vector2(offset - base_width * 0.4 + lean * 0.7 + sway, -height * 0.85),
				Vector2(offset + lean + sway, -height),
				Vector2(offset + base_width * 0.4 + lean * 0.7 + sway, -height * 0.85),
				Vector2(offset + base_width * 0.7 + lean * 0.4 + sway, -height * 0.5),
				Vector2(offset + base_width, base_y)
			])

			# Color by layer - darker to brighter (more transparent to see wood)
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - red/orange (more transparent)
				colors.append(Color(0.8, 0.2, 0.0, 0.65))
				colors.append(Color(0.95, 0.4, 0.0, 0.6))
				colors.append(Color(1.0, 0.55, 0.1, 0.5))
				colors.append(Color(1.0, 0.7, 0.2, 0.35))
				colors.append(Color(1.0, 0.55, 0.1, 0.5))
				colors.append(Color(0.95, 0.4, 0.0, 0.6))
				colors.append(Color(0.8, 0.2, 0.0, 0.65))
			elif layer == 1:  # Middle - orange/yellow (more transparent)
				colors.append(Color(1.0, 0.5, 0.0, 0.6))
				colors.append(Color(1.0, 0.65, 0.15, 0.55))
				colors.append(Color(1.0, 0.8, 0.3, 0.5))
				colors.append(Color(1.0, 0.9, 0.5, 0.35))
				colors.append(Color(1.0, 0.8, 0.3, 0.5))
				colors.append(Color(1.0, 0.65, 0.15, 0.55))
				colors.append(Color(1.0, 0.5, 0.0, 0.6))
			else:  # Top - yellow/white (more transparent)
				colors.append(Color(1.0, 0.75, 0.25, 0.55))
				colors.append(Color(1.0, 0.85, 0.4, 0.5))
				colors.append(Color(1.0, 0.95, 0.6, 0.4))
				colors.append(Color(1.0, 1.0, 0.8, 0.3))
				colors.append(Color(1.0, 0.95, 0.6, 0.4))
				colors.append(Color(1.0, 0.85, 0.4, 0.5))
				colors.append(Color(1.0, 0.75, 0.25, 0.55))

			flame.vertex_colors = colors
			flame.name = "Flame_L" + str(layer) + "_" + str(i)
			flame.z_index = layer + 1
			fire_sprite.add_child(flame)

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

func create_scorched_ground() -> void:
	"""Create burnt/darkened ground beneath the campfire"""
	var scorched_ground = Polygon2D.new()
	scorched_ground.name = "ScorchedGround"
	scorched_ground.z_index = -20  # Below everything

	# Create irregular circle about 2x the stone ring size (stone ring is ~32 radius)
	var scorch_radius = 70.0  # About 2x the rock ring
	var segments = 24
	var points = PackedVector2Array()
	var colors = PackedColorArray()

	# Center point
	points.append(Vector2.ZERO)
	colors.append(Color(0.12, 0.10, 0.08, 0.9))  # Very dark brown/black center

	# Outer irregular edge
	for i in range(segments):
		var angle = (i * TAU) / segments
		var radius_variance = randf_range(0.85, 1.15)  # Irregular edge
		var point = Vector2(cos(angle), sin(angle)) * scorch_radius * radius_variance
		points.append(point)
		colors.append(Color(0.25, 0.20, 0.15, 0.3))  # Fade to lighter brown at edges

	# Close the circle
	var angle = 0.0
	var point = Vector2(cos(angle), sin(angle)) * scorch_radius
	points.append(point)
	colors.append(Color(0.25, 0.20, 0.15, 0.3))

	scorched_ground.polygon = points
	scorched_ground.vertex_colors = colors
	add_child(scorched_ground)

func create_fire_light() -> void:
	"""Create dramatic firelight with soft gradient falloff"""
	var fire_light = PointLight2D.new()
	fire_light.name = "FireLight"
	fire_light.position = Vector2(0, -10)  # Slightly above fire base

	# Enhanced lighting - 50% increased range via texture_scale
	fire_light.energy = 1.2
	fire_light.texture_scale = 2.25  # 50% increase from base (warmth_radius * 2.25 / 150 ≈ 2.25)

	# Warm orange-yellow fire color
	fire_light.color = Color(1.0, 0.7, 0.3)

	# Enable shadows for dramatic effect
	fire_light.shadow_enabled = true
	fire_light.shadow_color = Color(0.0, 0.0, 0.0, 0.8)

	# Blend mode for nice atmospheric effect
	fire_light.blend_mode = Light2D.BLEND_MODE_ADD

	add_child(fire_light)

	print("🔥 Fire light created with texture_scale: ", fire_light.texture_scale)

func create_fire_audio() -> void:
	"""Create looping campfire crackling sound with spatial audio"""
	var campfire_sound = load("res://assets/sounds/ambient/campfire_loop.wav")
	if not campfire_sound:
		push_warning("⚠️ Failed to load campfire_loop.wav")
		return

	# Use AudioStreamPlayer2D for spatial audio
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.name = "FireAudio"
	fire_audio.stream = campfire_sound
	fire_audio.volume_db = -8.0  # Moderate volume
	fire_audio.bus = "Master"
	fire_audio.autoplay = false

	# Spatial audio settings - fade matches warmth radius
	fire_audio.max_distance = warmth_radius * 2.5  # Hear it up to 375 units away
	fire_audio.attenuation = 2.0  # Natural quadratic falloff (sounds more realistic)
	fire_audio.panning_strength = 0.8  # Strong stereo positioning

	add_child(fire_audio)

	# Wait a frame for node to be in tree
	await get_tree().process_frame

	# Play manually
	fire_audio.play()

	print("🔥 Campfire audio loaded and playing (spatial)")
	print("   Type: ", campfire_sound.get_class())
	print("   Loop mode: ", campfire_sound.loop_mode if campfire_sound is AudioStreamWAV else "N/A")
	print("   Playing: ", fire_audio.playing)
	print("   Volume: ", fire_audio.volume_db, " dB")
	print("   Max distance: ", fire_audio.max_distance)
	print("   Attenuation: ", fire_audio.attenuation)

func animate_fire(delta: float) -> void:
	"""Enhanced flickering animation for fire with scale, position, and color changes"""
	if not fire_sprite:
		return

	var time = Time.get_ticks_msec() / 1000.0

	# Animate flames (flicker and sway)
	for child in fire_sprite.get_children():
		if child.name.begins_with("Flame_"):
			var idx = child.get_index()
			var speed = 1.0 + idx * 0.15
			var flicker = sin(time * speed + idx * 1.5)
			var sway = cos(time * speed * 0.6 + idx * 0.8)

			# Vertical flicker (height variation)
			child.scale.y = 1.0 + flicker * 0.2
			# Horizontal sway
			child.scale.x = 1.0 + sway * 0.1
			# Opacity flicker
			child.modulate.a = 0.9 + flicker * 0.1
			# Position wobble
			child.position.x = sway * 1.5

	# Animate coal glow (pulsing)
	for child in fire_sprite.get_children():
		if child.name.begins_with("Coal"):
			var pulse = sin(time * 2.0 + child.get_index() * 0.5)
			child.modulate = Color(1.0, 1.0, 1.0, 0.9 + pulse * 0.1)
			var scale_pulse = 1.0 + pulse * 0.05
			child.scale = Vector2(scale_pulse, scale_pulse)

	# Animate base glow (subtle breathe)
	for child in fire_sprite.get_children():
		if child is Polygon2D and "glow" in child.name.to_lower():
			var breathe = sin(time * 0.8)
			child.modulate.a = 0.08 + breathe * 0.02  # Very subtle pulse
	
	# Subtle warmth circle pulse
	if warmth_circle:
		var pulse = sin(time * 0.5)
		warmth_circle.modulate.a = 0.9 + pulse * 0.1

	# Animate fire light (subtle flickering)
	if has_node("FireLight"):
		var fire_light = get_node("FireLight")
		var flicker = sin(time * 2.5) * 0.5 + cos(time * 3.7) * 0.3
		fire_light.energy = 1.2 + flicker * 0.15  # Subtle flicker between 1.05 and 1.35

func get_deterrent_radius() -> float:
	"""Return the radius that deters enemies"""
	return warmth_radius
