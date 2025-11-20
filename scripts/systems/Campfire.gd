extends Area2D
class_name Campfire

## Enhanced Campfire with fuel system, visual intensity scaling, and ground-hugging mystical auras
## Features:
## - Hold F to add all wood/bone embers from inventory
## - Wood increases healing rate (5-25 HP/s)
## - Bone embers increase crit chance (+16.5% max)
## - Bright magical coals (green/blue) as focal point
## - Subtle ground-hugging mist effect (ankle-height)
## - Sparse particle effects from magical coals

# Constants
const Constants = preload("res://scripts/constants.gd")

# Fuel system constants
const MAX_WOOD: int = 50  # Max wood logs for healing buff
const MAX_BONE_EMBERS: int = 100  # Max bone embers for crit buff
const WOOD_BURN_RATE: float = 1.0 / 30.0  # 1 log per 30 seconds (50 logs = 25 min)
const BONE_EMBER_BURN_RATE: float = 1.0 / 45.0  # 1 ember per 45 seconds (100 embers = 75 min)
var wood_decay_accumulator: float = 0.0
var bone_ember_decay_accumulator: float = 0.0

# Interaction (Hold-to-fuel system)
var player_in_interact_range: bool = false
var interaction_prompt: Label = null
var is_fueling: bool = false
var fuel_progress: float = 0.0  # 0.0 to 1.0
var fuel_time_required: float = 2.0  # 2 seconds to add fuel
var progress_circle: Node2D = null
var cancel_grace_timer: float = 0.0  # Prevent immediate cancellation
var cancel_grace_period: float = 0.15  # 0.15 second grace period
var no_fuel_message_timer: float = 0.0  # Timer for "no fuel" message
var no_fuel_message_duration: float = 2.0  # Show message for 2 seconds

# Performance optimization
var enemy_check_timer: float = 0.0
var enemy_check_interval: float = 0.2  # Check enemies every 0.2 seconds instead of every frame

# Fuel state
var wood_count: int = 0
var bone_ember_count: int = 0

# Healing system
var heal_rate: float = 5.0  # HP per interval (scales with fuel)
var heal_interval: float = 1.0  # Heal every 1 second
var heal_timer: float = 0.0
var heal_pattern_index: int = 0  # For sound pattern: 0, 1, 2, repeat

# Audio
var fire_audio: AudioStreamPlayer2D = null
var healing_audio_1: AudioStreamPlayer2D = null  # First healing tone
var healing_audio_2: AudioStreamPlayer2D = null  # Second healing tone

# Cached references for animation performance
var flame_nodes: Array[Polygon2D] = []
var coal_nodes: Array[Polygon2D] = []
var coal_glow_nodes: Array[Polygon2D] = []  # Glowing coals between rocks and fire
var fire_light: PointLight2D = null

# Ground mist auras
var heal_mist: Polygon2D = null
var crit_mist: Polygon2D = null

# Particle systems
var heal_particles: CPUParticles2D = null
var crit_particles: CPUParticles2D = null

# Campfire size/range
var warmth_radius: float = 150.0  # Healing/buff radius (smaller)
var player_in_warmth: bool = false
var player: CharacterBody2D = null

# Visual elements
var fire_sprite: Node2D = null

func _ready() -> void:
	add_to_group("campfire")

	# Create campfire visuals
	create_campfire_scene()

	# Setup area detection
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Create UI elements
	create_interaction_prompt()
	create_progress_circle()
	create_fuel_ui()

	# Setup audio
	setup_audio()

	# Cache animated nodes for performance
	cache_animation_nodes()

	# Create ground-hugging mist auras
	create_ground_mist_auras()

	# Create particle systems
	create_particle_systems()

	print("🔥 Campfire initialized with fuel system")


func _physics_process(delta: float) -> void:
	# Heal player if in warmth
	if player_in_warmth and player and is_instance_valid(player):
		# Check if player needs healing
		var player_needs_healing = player.current_health < player.max_health

		# Apply healing tick
		if player_needs_healing:
			heal_timer += delta
			if heal_timer >= heal_interval:
				if player.has_method("heal"):
					player.heal(heal_rate * heal_interval)
					# Play healing sound in pattern: tone1, tone1, tone2, repeat
					if heal_pattern_index < 2:
						# Play tone 1 for positions 0 and 1
						if healing_audio_1:
							healing_audio_1.play()
					else:
						# Play tone 2 for position 2
						if healing_audio_2:
							healing_audio_2.play()
					# Advance pattern: 0 -> 1 -> 2 -> 0 -> 1 -> 2 ...
					heal_pattern_index = (heal_pattern_index + 1) % 3
				heal_timer = 0.0

	# Update no fuel message timer
	if no_fuel_message_timer > 0.0:
		no_fuel_message_timer -= delta

	# Update interaction prompt position and visibility
	update_interaction_prompt()

	# Handle hold-to-fuel mechanic
	handle_fuel_interaction(delta)

	# Apply crit buff to player if in warmth
	if player_in_warmth and player and is_instance_valid(player):
		apply_crit_buff_to_player()

	# Check enemies near warmth (throttled for performance)
	enemy_check_timer += delta
	if enemy_check_timer >= enemy_check_interval:
		check_enemy_deterrent()
		enemy_check_timer = 0.0

	# Fuel decay system (fires slowly burn down)
	decay_fuel(delta)

	# Animate fire
	animate_fire(delta)

	# Update ground mist shaders
	update_ground_mist(delta)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player = body as CharacterBody2D
		player_in_warmth = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_warmth = false
		# Clear crit buff when player leaves
		if player and is_instance_valid(player):
			CharacterStats.campfire_crit_buff = 0.0


func add_collision_body() -> void:
	"""Add StaticBody2D collision so player can't walk through campfire"""
	# Create collision body
	var collision_body = StaticBody2D.new()
	collision_body.name = "CampfireCollision"
	collision_body.collision_layer = 1  # Environment layer
	collision_body.collision_mask = 0  # Don't detect anything
	add_child(collision_body)

	# Add small circular collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 20.0  # Small radius so player can get close
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)


func create_campfire_scene() -> void:
	"""Create enhanced campfire with detailed logs, rocks, and particle effects"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	add_child(fire_sprite)

	# Rock color variations (grey-brown tones)
	var rock_colors = [
		Color(0.35, 0.30, 0.28, 1.0),  # Medium grey-brown
		Color(0.40, 0.35, 0.32, 1.0),  # Light grey-brown
		Color(0.30, 0.28, 0.26, 1.0),  # Dark grey
	]

	# Create 12 rocks in a tighter circle around fire
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

		# Use solid, visible rock colors (not transparent)
		var base_rock_color = rock_colors[i % rock_colors.size()]
		rock.color = Color(base_rock_color.r, base_rock_color.g, base_rock_color.b, 1.0)  # Full opacity

		# Add highlight to top of rock for depth
		var highlight = Line2D.new()
		highlight.width = 1.5
		highlight.default_color = Color(0.6, 0.58, 0.55, 0.8)  # Brighter highlight
		highlight.add_point(rock_points[0])
		highlight.add_point(rock_points[1])
		rock.add_child(highlight)

		fire_sprite.add_child(rock)

	# === WOOD LOGS === (triangle teepee formation, deteriorating)
	var log_color_burnt = Color(0.15, 0.12, 0.10, 1.0)  # Charred
	var log_color_dark = Color(0.25, 0.18, 0.12, 1.0)   # Dark wood
	var log_color = Color(0.35, 0.25, 0.18, 1.0)        # Medium wood
	var log_color_light = Color(0.45, 0.32, 0.22, 1.0)  # Light wood

	# Bottom logs (stacked on top of coals - teepee formation)
	# Left log (leaning right) - positioned on coals, 50% thicker, scaled 75%
	var log_left = Polygon2D.new()
	log_left.polygon = PackedVector2Array([
		Vector2(-17.25, 6.75),   # Bottom left (75% scale)
		Vector2(-6, -10.5),      # Top left (75% scale)
		Vector2(-3.75, -9.75),   # Top right (75% scale)
		Vector2(-15, 8.25)       # Bottom right (75% scale)
	])
	log_left.color = log_color
	log_left.name = "LogLeft"
	log_left.z_index = -1  # Above coals
	fire_sprite.add_child(log_left)

	# Left log charred end (50% thicker, moved up 20px, scaled 75%)
	var log_left_char = Polygon2D.new()
	log_left_char.polygon = PackedVector2Array([
		Vector2(-15, 6.75),      # 75% scale
		Vector2(-12.75, 5.25),   # 75% scale
		Vector2(-11.25, 6.75),   # 75% scale
		Vector2(-13.5, 8.25)     # 75% scale
	])
	log_left_char.color = log_color_burnt
	log_left_char.z_index = -1
	fire_sprite.add_child(log_left_char)

	# Right log (leaning left) - positioned on coals, 50% thicker, scaled 75%
	var log_right = Polygon2D.new()
	log_right.polygon = PackedVector2Array([
		Vector2(15, 8.25),       # Bottom left (75% scale)
		Vector2(3.75, -9.75),    # Top left (75% scale)
		Vector2(6, -10.5),       # Top right (75% scale)
		Vector2(17.25, 6.75)     # Bottom right (75% scale)
	])
	log_right.color = log_color
	log_right.name = "LogRight"
	log_right.z_index = -1
	fire_sprite.add_child(log_right)

	# Right log charred end (50% thicker, moved up 20px, scaled 75%)
	var log_right_char = Polygon2D.new()
	log_right_char.polygon = PackedVector2Array([
		Vector2(11.25, 6.75),    # 75% scale
		Vector2(12.75, 5.25),    # 75% scale
		Vector2(15, 6.75),       # 75% scale
		Vector2(13.5, 8.25)      # 75% scale
	])
	log_right_char.color = log_color_burnt
	log_right_char.z_index = -1
	fire_sprite.add_child(log_right_char)

	# Back log (centered, vertical) - positioned on coals, 50% thicker, scaled 75%
	var log_back = Polygon2D.new()
	log_back.polygon = PackedVector2Array([
		Vector2(-3, 6),          # Bottom left (75% scale)
		Vector2(-1.5, -12),      # Top left (75% scale)
		Vector2(1.5, -12),       # Top right (75% scale)
		Vector2(3, 6)            # Bottom right (75% scale)
	])
	log_back.color = log_color_dark
	log_back.name = "LogBack"
	log_back.z_index = -1
	fire_sprite.add_child(log_back)

	# Back log charred end (50% thicker, moved up 20px, scaled 75%)
	var log_back_char = Polygon2D.new()
	log_back_char.polygon = PackedVector2Array([
		Vector2(-3, 6),          # 75% scale
		Vector2(-1.5, 4.5),      # 75% scale
		Vector2(1.5, 4.5),       # 75% scale
		Vector2(3, 6)            # 75% scale
	])
	log_back_char.color = log_color_burnt
	log_back_char.z_index = -1
	fire_sprite.add_child(log_back_char)

	# Create coals radiating from center, staying clear of rock ring
	for i in range(10):
		var coal_angle = randf() * TAU
		var coal_distance = randf_range(5, 20)  # Center cluster
		var coal_pos = Vector2(cos(coal_angle), sin(coal_angle)) * coal_distance

		var coal = Polygon2D.new()
		coal.name = "Coal" + str(i)
		coal.z_index = -2  # Below fire

		# Small irregular coal shape
		var coal_size = randf_range(2, 4)
		var coal_points = PackedVector2Array()
		for j in range(5):
			var point_angle = (j * TAU) / 5.0
			var radius = coal_size * randf_range(0.7, 1.0)
			coal_points.append(coal_pos + Vector2(cos(point_angle), sin(point_angle)) * radius)
		coal.polygon = coal_points

		# Base orange-red coal color
		coal.color = Color(1.0, 0.3, 0.0, 1.0)
		fire_sprite.add_child(coal)

	# Create light source
	fire_light = PointLight2D.new()
	fire_light.enabled = true
	fire_light.texture_scale = 2.5
	fire_light.color = Color(1.0, 0.7, 0.3)
	fire_light.energy = 1.2
	fire_light.shadow_enabled = true
	fire_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	fire_sprite.add_child(fire_light)

	# Create simple fire particles
	create_fire_particles()

	# Add collision
	add_collision_body()

	# Set collision shape to match largest visual aura (crit aura = 375px at max fuel)
	# Start at base warmth_radius (150), will expand as fuel is added
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is CircleShape2D:
			collision.shape.radius = warmth_radius


func create_fire_particles() -> void:
	"""Create enhanced particle effects with embers, sparks, and aurora wisps"""

	# EMBER PARTICLES (orange glowing embers floating up)
	var ember_particles = CPUParticles2D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.emitting = true
	ember_particles.amount = 15
	ember_particles.lifetime = 2.5
	ember_particles.preprocess = 1.0

	# Ember appearance
	ember_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ember_particles.emission_sphere_radius = 10.0

	# Ember movement - slow float upward
	ember_particles.direction = Vector2(0, -1)
	ember_particles.spread = 30.0
	ember_particles.gravity = Vector2(0, -15)
	ember_particles.initial_velocity_min = 10.0
	ember_particles.initial_velocity_max = 25.0

	# Ember visuals - glowing particles
	ember_particles.scale_amount_min = 1.0
	ember_particles.scale_amount_max = 2.0
	ember_particles.scale_amount_curve = Curve.new()
	ember_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	ember_particles.scale_amount_curve.add_point(Vector2(0.5, 0.8))
	ember_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Ember color - orange to red fade
	ember_particles.color = Color(1.0, 0.5, 0.2, 1.0)
	ember_particles.color_ramp = Gradient.new()
	ember_particles.color_ramp.add_point(0.0, Color(1.0, 0.7, 0.3, 1.0))
	ember_particles.color_ramp.add_point(0.3, Color(1.0, 0.4, 0.1, 0.9))
	ember_particles.color_ramp.add_point(0.7, Color(0.8, 0.2, 0.0, 0.5))
	ember_particles.color_ramp.add_point(1.0, Color(0.3, 0.1, 0.0, 0.0))

	fire_sprite.add_child(ember_particles)

	# SPARK PARTICLES (quick bright sparks)
	var spark_particles = CPUParticles2D.new()
	spark_particles.name = "SparkParticles"
	spark_particles.emitting = true
	spark_particles.amount = 20
	spark_particles.lifetime = 0.8
	spark_particles.explosiveness = 0.3

	# Spark appearance - burst from center
	spark_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	spark_particles.emission_sphere_radius = 8.0

	# Spark movement - quick burst in all directions
	spark_particles.spread = 180.0
	spark_particles.gravity = Vector2(0, 30)  # Fall down
	spark_particles.initial_velocity_min = 40.0
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

	# AURORA WISPS (magical green/blue/cyan streaks) - only visible when fuel is added
	var aurora_particles = CPUParticles2D.new()
	aurora_particles.name = "AuroraParticles"
	aurora_particles.emitting = true
	aurora_particles.amount = 15
	aurora_particles.lifetime = 3.0  # Long-lived magical wisps
	aurora_particles.preprocess = 1.0

	# Aurora appearance - rise from fire
	aurora_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	aurora_particles.emission_sphere_radius = 15.0

	# Aurora movement - slow graceful rise
	aurora_particles.direction = Vector2(0, -1)
	aurora_particles.spread = 25.0
	aurora_particles.gravity = Vector2(0, -8)  # Light upward drift
	aurora_particles.initial_velocity_min = 15.0
	aurora_particles.initial_velocity_max = 30.0

	# Aurora visuals - wispy streaks
	aurora_particles.scale_amount_min = 1.5
	aurora_particles.scale_amount_max = 3.0
	aurora_particles.scale_amount_curve = Curve.new()
	aurora_particles.scale_amount_curve.add_point(Vector2(0, 0.3))
	aurora_particles.scale_amount_curve.add_point(Vector2(0.2, 1.0))
	aurora_particles.scale_amount_curve.add_point(Vector2(0.8, 0.8))
	aurora_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	# Aurora colors - Northern Lights (green/cyan/blue)
	aurora_particles.color = Color(0.3, 1.0, 0.7, 0.6)
	aurora_particles.color_ramp = Gradient.new()
	aurora_particles.color_ramp.add_point(0.0, Color(0.0, 1.0, 0.5, 0.0))   # Start transparent green
	aurora_particles.color_ramp.add_point(0.2, Color(0.2, 1.0, 0.7, 0.4))   # Bright cyan
	aurora_particles.color_ramp.add_point(0.5, Color(0.3, 0.8, 1.0, 0.5))   # Blue
	aurora_particles.color_ramp.add_point(0.7, Color(0.5, 1.0, 0.9, 0.3))   # Sea green
	aurora_particles.color_ramp.add_point(1.0, Color(0.2, 0.6, 0.9, 0.0))   # Fade to transparent blue

	fire_sprite.add_child(aurora_particles)

	# GLOWING COALS (between rock ring and fire base) - ambient glow around fire
	# These sit on the ground in the gap between rocks (~28px) and fire base
	for i in range(20):
		var coal_glow = Polygon2D.new()
		coal_glow.name = "CoalGlow" + str(i)

		# Position INSIDE rock ring, filling the space between rocks and fire
		var angle = randf() * TAU
		var distance = randf_range(12.0, 24.0)  # Inside the 28px rock ring radius
		var coal_pos = Vector2(cos(angle), sin(angle)) * distance

		# Small irregular coal shapes
		var coal_size = randf_range(2.5, 4.5)
		var coal_points = PackedVector2Array()
		for j in range(5):
			var point_angle = (j * TAU) / 5.0
			var radius = coal_size * randf_range(0.7, 1.0)
			coal_points.append(coal_pos + Vector2(cos(point_angle), sin(point_angle)) * radius)
		coal_glow.polygon = coal_points

		# Glowing ember color - orange to red
		var brightness = randf_range(0.6, 1.0)
		coal_glow.color = Color(1.0 * brightness, 0.25 * brightness, 0.0, 0.85)
		coal_glow.z_index = -2  # Same as main coals
		coal_glow.name = "CoalGlow" + str(i)
		fire_sprite.add_child(coal_glow)

	# POLYGON FLAMES - Create 3 simple flame layers for natural fire look (taller and brighter)
	for layer in range(3):
		for i in range(3 + layer * 2):  # 3, 5, 7 flames per layer
			var flame = Polygon2D.new()
			var offset = (i - (1 + layer)) * (8 - layer * 2)  # Tighter as we go up
			# TALLER flames: 35, 25, 15 (was 20, 15, 7)
			var height = (35 - layer * 10) + randf() * 5
			if layer == 2:  # Top layer
				height = 15 + randf() * 3
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

			# Color by layer - BRIGHTER (increased alpha)
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - red/orange (brighter)
				colors.append(Color(0.8, 0.2, 0.0, 0.65))
				colors.append(Color(0.95, 0.4, 0.0, 0.6))
				colors.append(Color(1.0, 0.55, 0.1, 0.55))
				colors.append(Color(1.0, 0.7, 0.2, 0.5))
				colors.append(Color(1.0, 0.55, 0.1, 0.55))
				colors.append(Color(0.95, 0.4, 0.0, 0.6))
				colors.append(Color(0.8, 0.2, 0.0, 0.65))
			elif layer == 1:  # Middle - orange/yellow (brighter)
				colors.append(Color(1.0, 0.5, 0.0, 0.6))
				colors.append(Color(1.0, 0.65, 0.15, 0.55))
				colors.append(Color(1.0, 0.8, 0.3, 0.5))
				colors.append(Color(1.0, 0.9, 0.5, 0.45))
				colors.append(Color(1.0, 0.8, 0.3, 0.5))
				colors.append(Color(1.0, 0.65, 0.15, 0.55))
				colors.append(Color(1.0, 0.5, 0.0, 0.6))
			else:  # Top - yellow/white (brighter)
				colors.append(Color(1.0, 0.75, 0.25, 0.5))
				colors.append(Color(1.0, 0.85, 0.4, 0.45))
				colors.append(Color(1.0, 0.95, 0.6, 0.4))
				colors.append(Color(1.0, 1.0, 0.8, 0.35))
				colors.append(Color(1.0, 0.95, 0.6, 0.4))
				colors.append(Color(1.0, 0.85, 0.4, 0.45))
				colors.append(Color(1.0, 0.75, 0.25, 0.5))

			flame.vertex_colors = colors
			flame.name = "Flame_" + str(layer) + "_" + str(i)
			flame.z_index = layer
			fire_sprite.add_child(flame)

	print("✅ Created fire particles and flames")


func setup_audio() -> void:
	"""Setup audio streams for fire and healing"""
	# Fire crackling audio (looping) - disabled, audio file not available
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.volume_db = -8.0
	fire_audio.max_distance = 500.0
	fire_audio.attenuation = 2.0
	fire_audio.panning_strength = 0.8
	add_child(fire_audio)

	# Healing audio - tone 1 (C note, 261 Hz)
	healing_audio_1 = AudioStreamPlayer2D.new()
	var gen1 = AudioStreamGenerator.new()
	gen1.mix_rate = 44100.0
	gen1.buffer_length = 0.5
	healing_audio_1.stream = gen1
	healing_audio_1.volume_db = -15.0
	healing_audio_1.max_distance = 200.0
	healing_audio_1.attenuation = 1.5
	healing_audio_1.panning_strength = 0.8
	add_child(healing_audio_1)

	# Healing audio - tone 2 (E note, 329 Hz)
	healing_audio_2 = AudioStreamPlayer2D.new()
	var gen2 = AudioStreamGenerator.new()
	gen2.mix_rate = 44100.0
	gen2.buffer_length = 0.5
	healing_audio_2.stream = gen2
	healing_audio_2.volume_db = -15.0
	healing_audio_2.max_distance = 200.0
	healing_audio_2.attenuation = 1.5
	healing_audio_2.panning_strength = 0.8
	add_child(healing_audio_2)


func cache_animation_nodes() -> void:
	"""Cache references to animated nodes for performance"""
	if not fire_sprite:
		return

	flame_nodes.clear()
	coal_nodes.clear()
	coal_glow_nodes.clear()

	# Cache all flame, coal, and coal glow nodes once
	for child in fire_sprite.get_children():
		if child.name.begins_with("Flame_") and child is Polygon2D:
			flame_nodes.append(child as Polygon2D)
		elif child.name.begins_with("CoalGlow") and child is Polygon2D:
			coal_glow_nodes.append(child as Polygon2D)
		elif child.name.begins_with("Coal") and child is Polygon2D:
			coal_nodes.append(child as Polygon2D)


func animate_fire(delta: float) -> void:
	"""Optimized fire animation using cached references"""
	var time = Time.get_ticks_msec() / 1000.0

	# Animate each cached flame with slight variations
	for flame in flame_nodes:
		if is_instance_valid(flame):
			# Get flame layer/index from name (e.g. "Flame_0_2")
			var name_parts = flame.name.split("_")
			if name_parts.size() >= 3:
				var layer = int(name_parts[1])
				var index = int(name_parts[2])

				# Different wave speeds for variation
				var wave_offset = (layer * 0.5) + (index * 0.3)
				var sway = sin(time * 2.0 + wave_offset) * 1.5
				var stretch = 1.0 + sin(time * 3.0 + wave_offset) * 0.1

				# Apply transform
				flame.rotation = sway * 0.03  # Slight rotation
				flame.scale.y = stretch

	# Make coals pulse/glow
	var pulse = 0.9 + sin(time * 2.0) * 0.1  # Subtle breathing
	for coal in coal_nodes:
		if is_instance_valid(coal):
			# Modulate brightness without changing alpha
			var base_color = coal.color
			coal.modulate = Color(pulse, pulse, pulse, 1.0)


func create_ground_mist_auras() -> void:
	"""Create simple filled circle auras with low alpha"""
	# CRIT AURA (Cyan-Blue) - larger, behind heal aura
	crit_mist = Polygon2D.new()
	crit_mist.name = "CritAura"
	crit_mist.z_index = -5
	crit_mist.color = Color(0.0, 0.6, 1.0, 0.20)  # Higher alpha cyan to make it visible
	crit_mist.visible = false
	fire_sprite.add_child(crit_mist)

	# HEAL AURA (Green) - smaller, in front of crit aura
	heal_mist = Polygon2D.new()
	heal_mist.name = "HealAura"
	heal_mist.z_index = -4
	heal_mist.color = Color(0.0, 1.0, 0.0, 0.08)  # Low alpha green
	heal_mist.visible = false
	fire_sprite.add_child(heal_mist)

	print("✅ Created simple polygon auras")


func update_ground_mist(delta: float) -> void:
	"""Update aura circles with wavy edges"""
	if not heal_mist or not crit_mist:
		return

	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)

	# Update heal aura (green circle)
	if wood_count > 0:
		var heal_radius = 50.0 + (wood_percent * 250.0)  # 50-300px
		heal_mist.polygon = create_wavy_circle(heal_radius, 64)
		heal_mist.visible = true
	else:
		heal_mist.visible = false

	# Update crit aura (cyan circle)
	if bone_ember_count > 0:
		var crit_radius = 50.0 + (bone_percent * 325.0)  # 50-375px
		crit_mist.polygon = create_wavy_circle(crit_radius, 64)
		crit_mist.visible = true
	else:
		crit_mist.visible = false


func create_wavy_circle(radius: float, segments: int) -> PackedVector2Array:
	"""Create a filled circle with wavy animated edges"""
	var points = PackedVector2Array()
	var time = Time.get_ticks_msec() / 1000.0

	# Circle edge points with wave distortion
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		var wave = sin(angle * 3.0 + time * 2.0) * 8.0
		var rad = radius + wave
		points.append(Vector2(cos(angle) * rad, sin(angle) * rad))

	return points


func create_particle_systems() -> void:
	"""Create sparse particle effects from magical coals"""
	# GREEN HEALING PARTICLES (from green coals) - REDUCED
	heal_particles = CPUParticles2D.new()
	heal_particles.name = "HealParticles"
	heal_particles.emitting = true
	heal_particles.amount = 3  # Very sparse
	heal_particles.lifetime = 2.0
	heal_particles.one_shot = false

	heal_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	heal_particles.emission_sphere_radius = 15.0

	heal_particles.direction = Vector2(0, -1)
	heal_particles.spread = 20.0
	heal_particles.gravity = Vector2(0, -12)
	heal_particles.initial_velocity_min = 8.0
	heal_particles.initial_velocity_max = 18.0

	# Larger, softer particles
	heal_particles.scale_amount_min = 2.0
	heal_particles.scale_amount_max = 3.5
	heal_particles.scale_amount_curve = Curve.new()
	heal_particles.scale_amount_curve.add_point(Vector2(0, 0.5))
	heal_particles.scale_amount_curve.add_point(Vector2(0.3, 1.0))
	heal_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	heal_particles.color_ramp = Gradient.new()
	heal_particles.color_ramp.add_point(0.0, Color(0.2, 1.0, 0.2, 0.0))
	heal_particles.color_ramp.add_point(0.2, Color(0.3, 1.0, 0.3, 0.5))
	heal_particles.color_ramp.add_point(0.7, Color(0.2, 0.8, 0.2, 0.3))
	heal_particles.color_ramp.add_point(1.0, Color(0.1, 0.5, 0.1, 0.0))

	fire_sprite.add_child(heal_particles)
	heal_particles.emitting = false  # Start disabled

	# BLUE CRIT PARTICLES (burst pattern from blue coals) - REDUCED
	crit_particles = CPUParticles2D.new()
	crit_particles.name = "CritParticles"
	crit_particles.emitting = true
	crit_particles.amount = 4  # Very sparse bursts
	crit_particles.lifetime = 1.5
	crit_particles.explosiveness = 0.8  # Burst pattern
	crit_particles.one_shot = false

	crit_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	crit_particles.emission_sphere_radius = 12.0

	crit_particles.spread = 180.0
	crit_particles.gravity = Vector2(0, -8)
	crit_particles.initial_velocity_min = 15.0
	crit_particles.initial_velocity_max = 35.0

	# Larger, softer particles
	crit_particles.scale_amount_min = 2.0
	crit_particles.scale_amount_max = 3.5
	crit_particles.scale_amount_curve = Curve.new()
	crit_particles.scale_amount_curve.add_point(Vector2(0, 1.0))
	crit_particles.scale_amount_curve.add_point(Vector2(0.4, 0.7))
	crit_particles.scale_amount_curve.add_point(Vector2(1, 0.0))

	crit_particles.color_ramp = Gradient.new()
	crit_particles.color_ramp.add_point(0.0, Color(0.8, 1.0, 1.0, 0.8))  # Softer cyan
	crit_particles.color_ramp.add_point(0.3, Color(0.2, 0.8, 1.0, 0.6))
	crit_particles.color_ramp.add_point(0.7, Color(0.1, 0.5, 0.8, 0.3))
	crit_particles.color_ramp.add_point(1.0, Color(0.0, 0.3, 0.5, 0.0))

	fire_sprite.add_child(crit_particles)
	crit_particles.emitting = false  # Start disabled

	# GREEN MIST PARTICLES (rising from heal aura edge) - REDUCED
	var heal_mist_particles = CPUParticles2D.new()
	heal_mist_particles.name = "HealMistParticles"
	heal_mist_particles.emitting = false  # Start disabled
	heal_mist_particles.amount = 8  # Much fewer
	heal_mist_particles.lifetime = 3.5
	heal_mist_particles.one_shot = false

	heal_mist_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	heal_mist_particles.emission_sphere_radius = 200.0  # Emit from aura edge

	heal_mist_particles.direction = Vector2(0, -1)
	heal_mist_particles.spread = 25.0
	heal_mist_particles.gravity = Vector2(0, -4)
	heal_mist_particles.initial_velocity_min = 3.0
	heal_mist_particles.initial_velocity_max = 10.0

	# Larger, softer particles
	heal_mist_particles.scale_amount_min = 6.0
	heal_mist_particles.scale_amount_max = 10.0

	heal_mist_particles.color_ramp = Gradient.new()
	heal_mist_particles.color_ramp.add_point(0.0, Color(0.0, 1.0, 0.0, 0.0))
	heal_mist_particles.color_ramp.add_point(0.15, Color(0.1, 0.9, 0.1, 0.2))
	heal_mist_particles.color_ramp.add_point(0.5, Color(0.0, 0.7, 0.0, 0.1))
	heal_mist_particles.color_ramp.add_point(1.0, Color(0.0, 0.4, 0.0, 0.0))

	fire_sprite.add_child(heal_mist_particles)

	# CYAN MIST PARTICLES (rising from crit aura edge) - REDUCED
	var crit_mist_particles = CPUParticles2D.new()
	crit_mist_particles.name = "CritMistParticles"
	crit_mist_particles.emitting = false  # Start disabled
	crit_mist_particles.amount = 8  # Much fewer
	crit_mist_particles.lifetime = 3.5
	crit_mist_particles.one_shot = false

	crit_mist_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	crit_mist_particles.emission_sphere_radius = 250.0  # Emit from aura edge

	crit_mist_particles.direction = Vector2(0, -1)
	crit_mist_particles.spread = 25.0
	crit_mist_particles.gravity = Vector2(0, -4)
	crit_mist_particles.initial_velocity_min = 3.0
	crit_mist_particles.initial_velocity_max = 10.0

	# Larger, softer particles
	crit_mist_particles.scale_amount_min = 6.0
	crit_mist_particles.scale_amount_max = 10.0

	crit_mist_particles.color_ramp = Gradient.new()
	crit_mist_particles.color_ramp.add_point(0.0, Color(0.0, 0.6, 1.0, 0.0))
	crit_mist_particles.color_ramp.add_point(0.15, Color(0.1, 0.8, 1.0, 0.2))
	crit_mist_particles.color_ramp.add_point(0.5, Color(0.0, 0.6, 0.9, 0.1))
	crit_mist_particles.color_ramp.add_point(1.0, Color(0.0, 0.3, 0.6, 0.0))

	fire_sprite.add_child(crit_mist_particles)

	print("✅ Created sparse particle systems with mist")


func create_interaction_prompt() -> void:
	"""Create UI prompt for fuel interaction"""
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 100  # Top layer
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.text = "Hold [F] Add Fuel"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	interaction_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	interaction_prompt.add_theme_constant_override("outline_size", 4)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_interaction_prompt() -> void:
	"""Update prompt visibility and position"""
	if not interaction_prompt:
		return

	# Only show if player is near campfire and not currently fueling
	if not player or not is_instance_valid(player):
		interaction_prompt.visible = false
		return

	var distance = player.global_position.distance_to(global_position)
	player_in_interact_range = distance <= 100.0  # Interact range slightly smaller than warmth radius

	if player_in_interact_range and not is_fueling:
		# Check if we should show "no fuel" message
		if no_fuel_message_timer > 0.0:
			interaction_prompt.text = "Acquire bone embers or dry logs first"
			interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red
		else:
			interaction_prompt.text = "Hold [F] Add Fuel"
			interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))  # Warm orange

		interaction_prompt.visible = true
		# Position prompt above campfire
		var viewport_size = get_viewport().get_visible_rect().size
		var camera = get_viewport().get_camera_2d()
		if camera:
			var prompt_world_pos = global_position + Vector2(0, -80)
			var camera_pos = camera.global_position
			var screen_center = viewport_size / 2
			var prompt_screen_pos = (prompt_world_pos - camera_pos) * camera.zoom.x + screen_center

			# Center horizontally
			var screen_x = prompt_screen_pos.x
			if interaction_prompt.size.x > 0:
				screen_x -= interaction_prompt.size.x / 2
			var screen_y = prompt_screen_pos.y

			interaction_prompt.position = Vector2(screen_x, screen_y)
	else:
		interaction_prompt.visible = false

func create_progress_circle() -> void:
	"""Create radial progress indicator for hold-to-fuel"""
	var canvas = CanvasLayer.new()
	canvas.name = "ProgressCanvas"
	canvas.layer = 100
	add_child(canvas)

	progress_circle = Node2D.new()
	progress_circle.name = "ProgressCircle"
	progress_circle.visible = false
	canvas.add_child(progress_circle)

	# Connect draw signal
	progress_circle.draw.connect(_draw_progress_circle)

func _draw_progress_circle() -> void:
	"""Draw radial progress indicator"""
	if not progress_circle or not is_fueling:
		return

	# Get screen position
	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	var world_pos = global_position
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var screen_pos = (world_pos - camera_pos) * camera.zoom.x + screen_center

	# Draw background circle
	progress_circle.draw_arc(screen_pos, 30.0, 0, TAU, 32, Color(0.2, 0.2, 0.2, 0.5), 4.0)

	# Draw progress arc
	var progress_angle = fuel_progress * TAU
	progress_circle.draw_arc(screen_pos, 30.0, -PI/2, -PI/2 + progress_angle, 32, Color(1.0, 0.8, 0.2), 4.0)


func handle_fuel_interaction(delta: float) -> void:
	"""Handle hold-to-fuel mechanic"""
	if not player_in_interact_range or not player or not is_instance_valid(player):
		if is_fueling:
			cancel_fueling()
		# Debug only on F key press
		if Input.is_physical_key_pressed(KEY_F):
			print("🔥 DEBUG: Can't interact - player_in_range: %s, player exists: %s" % [player_in_interact_range, player != null])
		return

	# Check for F key press/hold
	if Input.is_physical_key_pressed(KEY_F):
		print("🔥 DEBUG: F key pressed at campfire!")
		if not is_fueling:
			print("🔥 DEBUG: Not currently fueling, calling start_fueling()")
			start_fueling()
		else:
			print("🔥 DEBUG: Already fueling, progress: %.2f" % fuel_progress)
			# Increment progress
			fuel_progress += delta / fuel_time_required
			if progress_circle:
				progress_circle.queue_redraw()

			# Complete fueling
			if fuel_progress >= 1.0:
				complete_fueling()
	else:
		# F released - cancel if not in grace period
		if is_fueling:
			cancel_grace_timer += delta
			# Only cancel if grace period has elapsed
			if cancel_grace_timer >= cancel_grace_period:
				cancel_fueling()

func start_fueling() -> void:
	"""Start the fueling process"""
	# First check if player has any fuel in inventory
	var has_wood = false
	var has_bone = false

	print("🔍 DEBUG: Checking inventory for fuel items...")
	print("   Inventory size: %d" % InventorySystem.inventory_items.size())

	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item:
			print("   Slot %d: %s (qty: %s)" % [slot_idx, item.get("name", "???"), item.get("quantity", "?")])
			if item.get("name") == "Dry Log":
				has_wood = true
			if item.get("name") == "Bone Ember":
				has_bone = true

	print("   Has wood: %s, Has bone: %s" % [has_wood, has_bone])

	# If no fuel at all, show notification and don't start fueling
	if not has_wood and not has_bone:
		print("⚠️ You have no fuel to add to the campfire!")
		no_fuel_message_timer = no_fuel_message_duration  # Trigger red message for 2 seconds
		return

	print("✅ Starting fueling process...")
	is_fueling = true
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = true
		progress_circle.queue_redraw()
	else:
		print("⚠️ DEBUG: progress_circle is null!")

func cancel_fueling() -> void:
	"""Cancel fueling (F released or player moved away)"""
	is_fueling = false
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = false
		progress_circle.queue_redraw()

func complete_fueling() -> void:
	"""Complete fueling and add all fuel from inventory"""
	is_fueling = false
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = false
		progress_circle.queue_redraw()

	# Add all fuel from inventory
	attempt_add_fuel_from_inventory()

func attempt_add_fuel_from_inventory() -> void:
	"""Automatically add all wood and bone embers from player inventory"""
	# First check if player has any fuel in inventory
	var has_wood = false
	var has_bone = false

	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Dry Log":
			has_wood = true
		if item and item.get("name") == "Bone Ember":
			has_bone = true

	# If no fuel at all, show notification and return
	if not has_wood and not has_bone:
		print("⚠️ You have no fuel to add to the campfire!")
		return

	# Find Dry Log items in inventory (iterate backwards to avoid index issues)
	var wood_added = 0
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Dry Log":
			var quantity = item.get("quantity", 1)
			if add_wood_fuel(quantity):
				wood_added += quantity
				InventorySystem.remove_item(slot_idx)
			else:
				print("⚠️ Wood fuel at max capacity, couldn't add %d logs" % quantity)

	# Find Bone Ember items in inventory (iterate backwards to avoid index issues)
	var bone_added = 0
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Bone Ember":
			var quantity = item.get("quantity", 1)
			if add_bone_ember_fuel(quantity):
				bone_added += quantity
				InventorySystem.remove_item(slot_idx)
			else:
				print("⚠️ Bone ember fuel at max capacity, couldn't add %d embers" % quantity)

	# Debug output
	print("🔥 Campfire fueled: %d wood logs, %d bone embers added" % [wood_added, bone_added])
	print("   Current fuel: %d/%d wood, %d/%d embers" % [wood_count, MAX_WOOD, bone_ember_count, MAX_BONE_EMBERS])

func apply_crit_buff_to_player() -> void:
	"""Apply crit chance buff to player while in campfire warmth"""
	# Update CharacterStats with current campfire crit buff
	CharacterStats.campfire_crit_buff = get_current_crit_buff()


func check_enemy_deterrent() -> void:
	"""Deter enemies from entering campfire warmth (performance optimized)"""
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var distance = enemy.global_position.distance_to(global_position)
		if distance <= warmth_radius:
			# Enemy in warmth - mark as deterred
			if enemy.has_method("set_deterred"):
				enemy.set_deterred(true)
		else:
			# Enemy outside warmth
			if enemy.has_method("set_deterred"):
				enemy.set_deterred(false)


func decay_fuel(delta: float) -> void:
	"""Slowly burn through fuel over time"""
	# Decay wood
	if wood_count > 0:
		wood_decay_accumulator += delta * WOOD_BURN_RATE
		if wood_decay_accumulator >= 1.0:
			var wood_to_remove = int(wood_decay_accumulator)
			wood_count = max(0, wood_count - wood_to_remove)
			wood_decay_accumulator -= float(wood_to_remove)
			update_visual_intensity()

	# Decay bone embers
	if bone_ember_count > 0:
		bone_ember_decay_accumulator += delta * BONE_EMBER_BURN_RATE
		if bone_ember_decay_accumulator >= 1.0:
			var embers_to_remove = int(bone_ember_decay_accumulator)
			bone_ember_count = max(0, bone_ember_count - embers_to_remove)
			bone_ember_decay_accumulator -= float(embers_to_remove)
			update_visual_intensity()


func add_wood_fuel(amount: int) -> bool:
	"""Add wood fuel (increases healing rate)"""
	if wood_count >= MAX_WOOD:
		return false

	var added = min(amount, MAX_WOOD - wood_count)
	wood_count += added
	update_visual_intensity()
	return true

func add_bone_ember_fuel(amount: int) -> bool:
	"""Add bone ember fuel (increases crit chance)"""
	if bone_ember_count >= MAX_BONE_EMBERS:
		return false

	var added = min(amount, MAX_BONE_EMBERS - bone_ember_count)
	bone_ember_count += added
	update_visual_intensity()
	return true

func update_visual_intensity() -> void:
	"""Update campfire visual intensity based on fuel levels"""
	# Update heal rate
	heal_rate = get_current_heal_rate()

	# Calculate fuel percentages
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)

	# Scale flame size based on total fuel - flames should be tall like real fire
	var total_fuel_percent = (wood_percent + bone_percent) / 2.0
	var flame_scale_x = 1.0 + (total_fuel_percent * 0.8)  # Modest horizontal growth
	var flame_scale_y = 1.2 + (total_fuel_percent * 2.0)  # Much taller vertically
	for flame in flame_nodes:
		if is_instance_valid(flame):
			flame.scale = Vector2(flame_scale_x, flame_scale_y)

	# Update coal colors - BRIGHT SATURATED EMISSIVE for magical source
	var time = Time.get_ticks_msec() / 1000.0
	var pulse = 0.9 + sin(time * 2.0) * 0.1  # Subtle pulsing

	for coal in coal_nodes:
		if is_instance_valid(coal):
			# Base orange-red coal
			var base_coal_color = Color(1.0, 0.3, 0.0, 1.0)
			# BRIGHT GREEN from wood fuel (pure saturated)
			var green_coal_color = Color(0.0, 1.0, 0.0, 1.0) * pulse
			# BRIGHT CYAN-BLUE from bone embers (vivid saturated)
			var blue_coal_color = Color(0.0, 0.6, 1.0, 1.0) * pulse

			# Mix colors based on fuel levels - coals are BRIGHTEST element
			var coal_with_wood = base_coal_color.lerp(green_coal_color, wood_percent * 0.8)
			var final_coal_color = coal_with_wood.lerp(blue_coal_color, bone_percent * 0.9)
			coal.color = final_coal_color

	# Update coal glow colors (small embers between rocks and fire)
	for coal_glow in coal_glow_nodes:
		if is_instance_valid(coal_glow):
			# Base orange-red glow
			var base_glow_color = Color(1.0, 0.25, 0.0, 0.85)
			# BRIGHT GREEN from wood fuel
			var green_glow_color = Color(0.3, 1.0, 0.3, 0.9) * pulse
			# BRIGHT CYAN-BLUE from bone embers
			var blue_glow_color = Color(0.2, 0.8, 1.0, 0.9) * pulse

			# Mix colors based on fuel levels
			var glow_with_wood = base_glow_color.lerp(green_glow_color, wood_percent * 0.9)
			var final_glow_color = glow_with_wood.lerp(blue_glow_color, bone_percent * 1.0)
			coal_glow.color = final_glow_color

	# Add ghostly glow to fire light based on fuel
	if fire_light and is_instance_valid(fire_light):
		# Base: warm orange (1.0, 0.7, 0.3)
		# With fuel: shift toward green/cyan based on fuel mix
		var color_r = 1.0
		var color_g = lerp(0.7, 0.9, wood_percent * 0.5 + bone_percent * 0.3)
		var color_b = lerp(0.3, 0.7, bone_percent * 0.5)
		fire_light.color = Color(color_r, color_g, color_b)

		# Increase light intensity with fuel
		var base_energy = 1.2
		var bonus_energy = total_fuel_percent * 0.4  # Up to +40% brightness
		fire_light.energy = base_energy + bonus_energy

	# Update collision area to match largest active aura radius
	update_buff_collision_radius()

	# Enable/disable particle systems based on fuel
	if heal_particles:
		heal_particles.emitting = wood_count > 0
	if crit_particles:
		crit_particles.emitting = bone_ember_count > 0

	# Enable/disable mist particles based on fuel
	var heal_mist_particles = fire_sprite.get_node_or_null("HealMistParticles")
	if heal_mist_particles:
		heal_mist_particles.emitting = wood_count > 0
	var crit_mist_particles = fire_sprite.get_node_or_null("CritMistParticles")
	if crit_mist_particles:
		crit_mist_particles.emitting = bone_ember_count > 0

func update_buff_collision_radius() -> void:
	"""Update Area2D collision radius to match the largest active buff aura"""
	if not has_node("CollisionShape2D"):
		return

	var collision = get_node("CollisionShape2D")
	if not collision.shape is CircleShape2D:
		return

	# Calculate current aura radii based on fuel levels
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)

	# Heal aura: scales from 0 to 300px
	var heal_aura_radius = wood_percent * 300.0

	# Crit aura: scales from 0 to 375px
	var crit_aura_radius = bone_percent * 375.0

	# Use the larger of the two auras, but minimum of base warmth_radius (150)
	var new_radius = max(warmth_radius, max(heal_aura_radius, crit_aura_radius))

	# Update collision shape
	collision.shape.radius = new_radius

func get_fuel_status() -> Dictionary:
	"""Get current fuel levels and buffs for UI"""
	return {
		"wood_count": wood_count,
		"bone_ember_count": bone_ember_count,
		"max_wood": MAX_WOOD,
		"max_bone_embers": MAX_BONE_EMBERS,
		"heal_rate": heal_rate,
		"crit_buff": get_current_crit_buff()
	}

func get_current_heal_rate() -> float:
	"""Calculate current heal rate based on wood count"""
	# Base: 5 HP/s, Max: 25 HP/s (linear scaling)
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	return 5.0 + (wood_percent * 20.0)  # 5 + (0-20) = 5-25 HP/s

func get_current_crit_buff() -> float:
	"""Calculate current crit chance buff based on bone ember count"""
	# Max buff: +16.5% (linear scaling)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)
	return bone_percent * 16.5  # 0-16.5% crit chance

func create_fuel_ui() -> void:
	"""Create UI panel showing current fuel levels and buffs"""
	var canvas = CanvasLayer.new()
	canvas.name = "FuelUICanvas"
	canvas.layer = 100
	add_child(canvas)

	# This will be implemented with CampfireFuelUI scene
	# For now, just create the canvas layer
	print("✅ Fuel UI canvas created (waiting for CampfireFuelUI scene)")
