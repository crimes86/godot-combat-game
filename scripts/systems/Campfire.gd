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
var coal_brightness_intensity: Array[float] = []  # How bright each coal burns (0.5-1.0)
var coal_color_preferences: Array[int] = []  # 0=green, 1=blue, 2=orange when both fuels present
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

	# Create tree stumps around campfire clearing
	create_clearing_stumps()

	print("🔥 Campfire initialized with fuel system")

func _process(_delta: float) -> void:
	"""Update coal pulsing animation every frame (only when visible)"""
	# Performance: Only update visuals when campfire is visible on screen
	if not is_visible_on_screen():
		return

	update_coal_pulsing()

func is_visible_on_screen() -> bool:
	"""Check if campfire is visible in camera viewport"""
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return true  # Assume visible if no camera

	var viewport_size = get_viewport().get_visible_rect().size
	var camera_pos = camera.global_position
	var zoom = camera.zoom.x

	# Calculate viewport bounds in world space
	var half_viewport = (viewport_size / zoom) / 2.0
	var viewport_rect = Rect2(
		camera_pos - half_viewport,
		viewport_size / zoom
	)

	# Check if campfire position is within viewport (with margin)
	var margin = 200.0  # Extra margin to start updating before fully visible
	viewport_rect = viewport_rect.grow(margin)
	return viewport_rect.has_point(global_position)

func _physics_process(delta: float) -> void:
	# Heal player based on fuel state:
	# - No fuel (wood_count == 0): Minimal heal (5 HP/s), no visual aura, uses warmth_radius range
	# - With fuel (wood_count > 0): Scaled heal (5-25 HP/s), visual aura, uses heal_aura range
	if player and is_instance_valid(player):
		var player_needs_healing = player.current_health < player.max_health
		var should_heal = false

		# Determine if player should receive healing based on fuel state
		if wood_count == 0:
			# No fuel: Use old warmth system (minimal heal, warmth_radius range)
			should_heal = player_in_warmth and player_needs_healing
		else:
			# With fuel: Player gets healed if in warmth range (buffed system will scale rate)
			should_heal = player_in_warmth and player_needs_healing

		# Apply healing tick
		if should_heal:
			heal_timer += delta
			if heal_timer >= heal_interval:
				if player.has_method("heal"):
					player.heal(heal_rate * heal_interval)
					# Play healing sound in pattern: 6-6-4 (sound 6 twice, then sound 4)
					if heal_pattern_index < 2:
						# Play sound 6 for positions 0 and 1 (healing_6.mp3)
						if healing_audio_1:
							healing_audio_1.play()
					else:
						# Play sound 4 for position 2 (healing_4.mp3)
						if healing_audio_2:
							healing_audio_2.play()
					# Advance pattern: 0 -> 1 -> 2 -> 0 -> 1 -> 2 ... (6-6-4-6-6-4...)
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
		# Removed: check_enemy_deterrent() - players can kite enemies to fire and fight with healing
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

		# Random rotation for more natural appearance
		var rock_rotation = randf_range(0, TAU)

		# Irregular rock shape with smaller sizes
		var rock_size = randf_range(4.0, 6.5)
		var rock_points = PackedVector2Array()
		for j in range(6):
			var rock_angle = (j * TAU) / 6.0 + rock_rotation  # Apply rotation
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
	log_left.z_index = 1  # Above coals and coal glow, visible in flames
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
	log_left_char.z_index = 1
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
	log_right.z_index = 1  # Above coals and coal glow, visible in flames
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
	log_right_char.z_index = 1
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
	log_back.z_index = 1  # Above coals and coal glow, visible in flames
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
	log_back_char.z_index = 1
	fire_sprite.add_child(log_back_char)

	# Create bone ember coals radiating from center
	for i in range(10):
		var coal_angle = randf() * TAU
		var coal_distance = randf_range(5, 20)  # Center cluster
		var coal_pos = Vector2(cos(coal_angle), sin(coal_angle)) * coal_distance

		var coal = Polygon2D.new()
		coal.name = "Coal" + str(i)
		coal.z_index = -2  # Below fire

		# Small irregular bone ember shape
		var coal_size = randf_range(2, 4)
		var coal_points = PackedVector2Array()
		for j in range(5):
			var point_angle = (j * TAU) / 5.0
			var radius = coal_size * randf_range(0.7, 1.0)
			coal_points.append(coal_pos + Vector2(cos(point_angle), sin(point_angle)) * radius)
		coal.polygon = coal_points

		# Blackened bone ember with red glow (unbuffed state)
		coal.color = Color(0.15, 0.08, 0.05, 1.0)  # Dark charcoal/bone color

		# Add ultra-thin dark border for grounding
		var coal_border = Line2D.new()
		coal_border.width = 0.8
		coal_border.default_color = Color(0.08, 0.04, 0.02, 0.9)  # Very dark brown-black
		coal_border.closed = true
		for point in coal_points:
			coal_border.add_point(point - coal_pos)  # Make relative to coal position
		coal.add_child(coal_border)

		fire_sprite.add_child(coal)

		# Add random brightness intensity for this coal (some burn hotter)
		coal_brightness_intensity.append(randf_range(0.6, 1.0))  # Varied heat intensity
		# Mix of green, blue, and orange: 0=green, 1=blue, 2=orange
		coal_color_preferences.append(i % 3)  # Cycle through 0,1,2,0,1,2...

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

	# EMBER PARTICLES (orange glowing embers floating up) - REDUCED for performance
	var ember_particles = CPUParticles2D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.emitting = true
	ember_particles.amount = 8  # Reduced from 15
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

	# SPARK PARTICLES (quick bright sparks) - REDUCED for performance
	var spark_particles = CPUParticles2D.new()
	spark_particles.name = "SparkParticles"
	spark_particles.emitting = true
	spark_particles.amount = 10  # Reduced from 20
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

	# AURORA WISPS (magical green/blue/cyan streaks) - only visible when fuel is added - REDUCED
	var aurora_particles = CPUParticles2D.new()
	aurora_particles.name = "AuroraParticles"
	aurora_particles.emitting = false  # Start disabled, only emit when buffed
	aurora_particles.amount = 8  # Reduced from 15
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
	# These sit on the ground filling the interior, slightly smaller than rock ring
	# Place embers in concentric rings to ensure good coverage
	# PERFORMANCE: Reduced from 4 rings to 2 rings for 60 FPS
	var rings = 2  # Number of concentric rings (was 4)
	var embers_per_ring = [8, 12]  # Reduced from [8, 12, 16, 20]
	var glow_index = 0  # Track total glow ember count for color preferences

	for ring in range(rings):
		var ring_distance = lerp(5.0, 22.0, float(ring) / float(rings - 1))  # Distance for this ring (smaller than 28px rock ring)
		var num_embers = embers_per_ring[ring]

		for i in range(num_embers):
			var coal_glow = Polygon2D.new()
			coal_glow.name = "CoalGlow" + str(ring) + "_" + str(i)

			# Position in ring with some randomness
			var angle = (float(i) / float(num_embers)) * TAU + randf_range(-0.1, 0.1)
			var distance = ring_distance + randf_range(-3.0, 3.0)  # Slight distance variation
			var coal_pos = Vector2(cos(angle), sin(angle)) * distance

			# Varied coal sizes - larger embers in center, smaller toward edges
			var coal_size = randf_range(3.0, 5.5) - (ring * 0.3)
			var coal_points = PackedVector2Array()
			for j in range(5):
				var point_angle = (j * TAU) / 5.0
				var radius = coal_size * randf_range(0.7, 1.0)
				coal_points.append(coal_pos + Vector2(cos(point_angle), sin(point_angle)) * radius)
			coal_glow.polygon = coal_points

			# Start with red-orange pulsing glow (will be animated in update_visual_intensity)
			coal_glow.color = Color(0.9, 0.2, 0.05, 0.85)  # Red-orange glow
			coal_glow.z_index = -2  # Same as main coals

			# Add ultra-thin dark border for grounding
			var glow_border = Line2D.new()
			glow_border.width = 0.8
			glow_border.default_color = Color(0.08, 0.04, 0.02, 0.9)  # Very dark brown-black
			glow_border.closed = true
			for point in coal_points:
				glow_border.add_point(point - coal_pos)  # Make relative to coal position
			coal_glow.add_child(glow_border)

			fire_sprite.add_child(coal_glow)

			# Add random brightness intensity for this coal glow (some burn hotter)
			coal_brightness_intensity.append(randf_range(0.6, 1.0))  # Varied heat intensity
			# Mix of green, blue, and orange: 0=green, 1=blue, 2=orange
			coal_color_preferences.append(glow_index % 3)  # Cycle through 0,1,2,0,1,2...
			glow_index += 1

	# POLYGON FLAMES - Create 3 simple flame layers for natural fire look
	for layer in range(3):
		for i in range(3 + layer * 2):  # 3, 5, 7 flames per layer
			# Skip outer flames on layer 2 (top layer) - only create middle 4
			if layer == 2 and (i == 0 or i == 1 or i == 6):
				continue

			var flame = Polygon2D.new()
			var offset = (i - (1 + layer)) * (8 - layer * 2)  # Tighter as we go up
			# Base flames: 31.2, 14.25, 8.8 (layer 0 is 20% larger, layer 1 is 25% smaller, layer 2 is 20% shorter)
			var height = (26 - layer * 7.5) + randf() * 4
			if layer == 0:  # Bottom layer - 20% larger
				height = (31.2 - layer * 7.5) + randf() * 4.8
			elif layer == 1:  # Middle layer - 25% smaller
				height = 14.25 + randf() * 3.0
			elif layer == 2:  # Top layer - 20% shorter
				height = 8.8 + randf() * 1.6
			var base_width = (6.0 - layer * 1.5)
			if layer == 0:  # Bottom layer - 20% wider
				base_width = 7.2
			elif layer == 1:  # Middle layer - 25% narrower
				base_width = 3.375

			# Vary base Y
			var base_y = 10 - layer * 3 + abs(offset) * 0.15

			# Gentle sway and crown bend
			var lean = offset * 0.3
			var sway = randf_range(-0.4, 0.4)

			# Add outward bend to outermost flames for crown shape
			var is_outermost = (i == 0 or i == (3 + layer * 2) - 1)
			var crown_bend = 0.0
			if is_outermost and layer == 0:  # Bottom layer outer flames
				crown_bend = 3.0 if i == 0 else -3.0  # Bend outward
			elif is_outermost and layer == 1:  # Middle layer outer flames
				crown_bend = 2.0 if i == 0 else -2.0  # Less bend
			elif is_outermost and layer == 2:  # Top layer outer flames
				crown_bend = 1.0 if i == 0 else -1.0  # Subtle bend

			# Simple flame shape with crown bend applied
			flame.polygon = PackedVector2Array([
				Vector2(offset - base_width, base_y),
				Vector2(offset - base_width * 0.7 + lean * 0.4 + sway + crown_bend * 0.3, -height * 0.5),
				Vector2(offset - base_width * 0.4 + lean * 0.7 + sway + crown_bend * 0.6, -height * 0.85),
				Vector2(offset + lean + sway + crown_bend, -height),
				Vector2(offset + base_width * 0.4 + lean * 0.7 + sway + crown_bend * 0.6, -height * 0.85),
				Vector2(offset + base_width * 0.7 + lean * 0.4 + sway + crown_bend * 0.3, -height * 0.5),
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
			else:  # Top - yellow/white (25% dimmer)
				colors.append(Color(1.0, 0.75, 0.25, 0.375))
				colors.append(Color(1.0, 0.85, 0.4, 0.3375))
				colors.append(Color(1.0, 0.95, 0.6, 0.3))
				colors.append(Color(1.0, 1.0, 0.8, 0.2625))
				colors.append(Color(1.0, 0.95, 0.6, 0.3))
				colors.append(Color(1.0, 0.85, 0.4, 0.3375))
				colors.append(Color(1.0, 0.75, 0.25, 0.375))

			flame.vertex_colors = colors
			flame.name = "Flame_" + str(layer) + "_" + str(i)
			flame.z_index = layer
			fire_sprite.add_child(flame)

	print("✅ Created fire particles and flames")


func setup_audio() -> void:
	"""Setup audio streams for fire and healing"""
	# Fire crackling audio (looping)
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.stream = load("res://assets/sounds/ambient/campfire_loop.wav")
	fire_audio.volume_db = -8.0
	fire_audio.max_distance = 500.0
	fire_audio.attenuation = 2.0
	fire_audio.panning_strength = 0.8
	fire_audio.pitch_scale = randf_range(0.95, 1.05)
	fire_audio.autoplay = true
	fire_audio.finished.connect(_on_fire_audio_finished)
	add_child(fire_audio)

	# Healing audio - sound 6 (plays first two times in pattern: 6-6-4)
	healing_audio_1 = AudioStreamPlayer2D.new()
	healing_audio_1.stream = load("res://assets/sounds/player/healing_6.mp3")
	healing_audio_1.volume_db = -8.0
	healing_audio_1.max_distance = 300.0
	healing_audio_1.attenuation = 1.5
	healing_audio_1.panning_strength = 0.8
	add_child(healing_audio_1)

	# Healing audio - sound 4 (plays third time in pattern: 6-6-4)
	healing_audio_2 = AudioStreamPlayer2D.new()
	healing_audio_2.stream = load("res://assets/sounds/player/healing_4.mp3")
	healing_audio_2.volume_db = -8.0
	healing_audio_2.max_distance = 300.0
	healing_audio_2.attenuation = 1.5
	healing_audio_2.panning_strength = 0.8
	add_child(healing_audio_2)

func _on_fire_audio_finished() -> void:
	"""Replay fire audio with heavy randomization to prevent repetitive loop"""
	if not fire_audio or not is_instance_valid(fire_audio):
		return

	# Much wider pitch variation (±15%) for more variety
	fire_audio.pitch_scale = randf_range(0.85, 1.15)

	# Wider volume variation (±4dB) for intensity changes
	fire_audio.volume_db = -8.0 + randf_range(-4.0, 4.0)

	# 40% chance to play backwards for variation
	if randf() < 0.4:
		fire_audio.pitch_scale *= -1.0

	# Random start position (0-50% through the clip) to break up patterns
	var start_position = randf() * 0.5 * fire_audio.stream.get_length()

	# 20% chance for a short silence gap before playing (natural pause)
	if randf() < 0.2:
		await get_tree().create_timer(randf_range(0.3, 1.0)).timeout
		if not is_instance_valid(fire_audio):
			return

	# Replay the audio from random position
	fire_audio.play(start_position)


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
	"""Optimized fire animation using cached references - scales with fuel intensity"""
	var time = Time.get_ticks_msec() / 1000.0

	# Calculate intensity based on total fuel (more fuel = more intense dancing)
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)
	var total_fuel_percent = (wood_percent + bone_percent) / 2.0

	# Animation speed scales from 2.0x (no fuel) to 3.0x (max fuel) - faster, more lively flames
	var animation_speed = 2.0 + (total_fuel_percent * 1.0)

	# Movement intensity scales from base to 2x with fuel
	var movement_intensity = 1.0 + total_fuel_percent

	# Animate each cached flame with slight variations
	for flame in flame_nodes:
		if is_instance_valid(flame):
			# Get flame layer/index from name (e.g. "Flame_0_2")
			var name_parts = flame.name.split("_")
			if name_parts.size() >= 3:
				var layer = int(name_parts[1])
				var index = int(name_parts[2])

				# Layer-specific phase offsets to desynchronize layers
				var layer_phase_offset = layer * 2.1  # Each layer starts at different time
				var index_phase_offset = index * 0.3

				# Different wave speeds for variation - scales with fuel
				var sway = sin(time * 2.0 * animation_speed + layer_phase_offset + index_phase_offset) * 1.5 * movement_intensity
				var stretch_y = 1.0 + sin(time * 3.0 * animation_speed + layer_phase_offset * 1.5 + index_phase_offset) * 0.1 * movement_intensity

				# Add X scale variation (expand/contract) for blending effect
				var expand = 1.0 + sin(time * 2.5 * animation_speed + layer_phase_offset * 0.8 + index_phase_offset + 1.0) * 0.08 * movement_intensity

				# Apply transform
				flame.rotation = sway * 0.03  # Slight rotation
				flame.scale.y = stretch_y
				flame.scale.x = expand  # Expand/contract horizontally

	# Make coals pulse/glow
	var pulse = 0.9 + sin(time * 2.0) * 0.1  # Subtle breathing
	for coal in coal_nodes:
		if is_instance_valid(coal):
			# Modulate brightness without changing alpha
			var base_color = coal.color
			coal.modulate = Color(pulse, pulse, pulse, 1.0)


func create_ground_mist_auras() -> void:
	"""Create simple filled circle auras with low alpha - use light blend to prevent mixing"""
	# CRIT AURA (Cyan-Blue) - larger, behind heal aura
	crit_mist = Polygon2D.new()
	crit_mist.name = "CritAura"
	crit_mist.z_index = -2  # Same as coals, visible above rocks
	crit_mist.color = Color(0.0, 0.6, 1.0, 0.07)  # Low alpha cyan (slightly lower)
	crit_mist.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	crit_mist.material = CanvasItemMaterial.new()
	crit_mist.material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	crit_mist.visible = false
	fire_sprite.add_child(crit_mist)

	# HEAL AURA (Green) - smaller, in front of crit aura
	heal_mist = Polygon2D.new()
	heal_mist.name = "HealAura"
	heal_mist.z_index = -1  # Above crit aura
	heal_mist.color = Color(0.0, 1.0, 0.0, 0.05)  # Lower alpha green (lighter)
	heal_mist.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	heal_mist.material = CanvasItemMaterial.new()
	heal_mist.material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	heal_mist.visible = false
	fire_sprite.add_child(heal_mist)

	print("✅ Created simple polygon auras")


func update_ground_mist(delta: float) -> void:
	"""Update aura circles with wavy edges (throttled for performance)"""
	if not heal_mist or not crit_mist:
		return

	# Performance: Only update mist when visible on screen
	if not is_visible_on_screen():
		return

	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)

	# Calculate radii - both can reach same max size (468.75px) with equal growth rate per item
	# Growth rate: 8.375px per wood, 4.1875px per ember (both reach 468.75px max)
	# Heal aura: 50px base + (8.375px * wood_count) → max 468.75px at 50 wood
	# Crit aura: 50px base + (4.1875px * bone_count) → max 468.75px at 100 embers
	var heal_radius = 50.0 + (wood_count * 8.375)  # 50-468.75px
	var crit_radius = 50.0 + (bone_ember_count * 4.1875)  # 50-468.75px

	# Dynamically set z-index: smaller aura always on top
	if heal_radius < crit_radius:
		# Heal is smaller - put it on top
		heal_mist.z_index = -1
		crit_mist.z_index = -2
	else:
		# Crit is smaller - put it on top
		crit_mist.z_index = -1
		heal_mist.z_index = -2

	# Update heal aura (green circle)
	if wood_count > 0:
		heal_mist.polygon = create_wavy_circle(heal_radius, 64, 0.0)  # No phase offset
		heal_mist.visible = true

		# Update heal mist particle emission points to match aura size
		var heal_mist_particles = fire_sprite.get_node_or_null("HealMistParticles")
		if heal_mist_particles:
			heal_mist_particles.emission_points = create_emission_ring(heal_radius, 32)  # Update ring size
	else:
		heal_mist.visible = false

	# Update crit aura (cyan circle)
	if bone_ember_count > 0:
		crit_mist.polygon = create_wavy_circle(crit_radius, 64, 3.14)  # PI offset for autonomy
		crit_mist.visible = true

		# Update crit mist particle emission points to match aura size
		var crit_mist_particles = fire_sprite.get_node_or_null("CritMistParticles")
		if crit_mist_particles:
			crit_mist_particles.emission_points = create_emission_ring(crit_radius, 32)  # Update ring size
	else:
		crit_mist.visible = false


func create_wavy_circle(radius: float, segments: int, phase_offset: float) -> PackedVector2Array:
	"""Create a filled circle with wavy animated edges"""
	var points = PackedVector2Array()
	var time = Time.get_ticks_msec() / 1000.0

	# Circle edge points with wave distortion (50% slower animation)
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		var wave = sin(angle * 3.0 + time * 1.0 + phase_offset) * 8.0  # Changed from 2.0 to 1.0
		var rad = radius + wave
		points.append(Vector2(cos(angle) * rad, sin(angle) * rad))

	return points

func create_emission_ring(radius: float, num_points: int) -> PackedVector2Array:
	"""Create a ring of emission points for even particle distribution"""
	var points = PackedVector2Array()
	for i in range(num_points):
		var angle = (float(i) / num_points) * TAU
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points

func create_particle_systems() -> void:
	"""Create heavy particle effects - fuel combusts dramatically creating sparks that simmer to ground"""
	# GREEN HEALING PARTICLES (combusting wood sparks)
	heal_particles = CPUParticles2D.new()
	heal_particles.name = "HealParticles"
	heal_particles.emitting = true
	heal_particles.amount = 8  # Base amount (will scale with fuel)
	heal_particles.lifetime = 8.0  # Very long lifetime to reach edges and +Y axis
	heal_particles.lifetime_randomness = 0.4  # Some particles live much longer (up to ~11s)
	heal_particles.one_shot = false

	# Emit from narrow column at fire tip
	heal_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	heal_particles.emission_rect_extents = Vector2(8.0, 2.0)  # Narrow X column at fire tip
	heal_particles.position = Vector2(0, -20)  # At fire tip height

	heal_particles.direction = Vector2(0, -1)  # Straight up (12 o'clock)
	heal_particles.spread = 45.0  # Wider spread - some go sideways/down to cover +Y axis
	heal_particles.gravity = Vector2(0, 25)  # Moderate gravity for controlled arc
	heal_particles.initial_velocity_min = 60.0  # Lower velocity - don't shoot too high
	heal_particles.initial_velocity_max = 90.0

	# Heavy damping to slow them quickly as they rise
	heal_particles.damping_min = 20.0
	heal_particles.damping_max = 30.0

	# Strong tangential acceleration to push them sideways (creates mushroom spread)
	# Negative values push left, positive push right - creates full 360° mushroom
	heal_particles.tangential_accel_min = -120.0
	heal_particles.tangential_accel_max = 120.0

	# Start small, grow, then shrink as they simmer down
	heal_particles.scale_amount_min = 1.5
	heal_particles.scale_amount_max = 3.0
	heal_particles.scale_amount_curve = Curve.new()
	heal_particles.scale_amount_curve.add_point(Vector2(0, 0.3))  # Start small
	heal_particles.scale_amount_curve.add_point(Vector2(0.2, 1.0))  # Peak size
	heal_particles.scale_amount_curve.add_point(Vector2(0.7, 0.8))  # Simmer
	heal_particles.scale_amount_curve.add_point(Vector2(1, 0.0))  # Fade

	heal_particles.color_ramp = Gradient.new()
	heal_particles.color_ramp.add_point(0.0, Color(0.8, 1.0, 0.5, 0.5))  # Bright yellow-green spark (more transparent)
	heal_particles.color_ramp.add_point(0.12, Color(0.4, 1.0, 0.4, 0.45))  # Green
	heal_particles.color_ramp.add_point(0.4, Color(0.2, 0.8, 0.2, 0.35))  # Still bright
	heal_particles.color_ramp.add_point(0.7, Color(0.15, 0.7, 0.15, 0.22))  # Dimming slowly
	heal_particles.color_ramp.add_point(0.9, Color(0.1, 0.5, 0.1, 0.08))  # Simmering
	heal_particles.color_ramp.add_point(1.0, Color(0.0, 0.3, 0.0, 0.0))  # Fade to ground

	fire_sprite.add_child(heal_particles)
	heal_particles.emitting = false  # Start disabled

	# BLUE CRIT PARTICLES (combusting bone ember sparks)
	crit_particles = CPUParticles2D.new()
	crit_particles.name = "CritParticles"
	crit_particles.emitting = true
	crit_particles.amount = 10  # Base amount (will scale with fuel)
	crit_particles.lifetime = 8.0  # Very long lifetime to reach edges and +Y axis
	crit_particles.lifetime_randomness = 0.4  # Some particles live much longer (up to ~11s)
	crit_particles.explosiveness = 0.2  # Some burst, but continuous
	crit_particles.one_shot = false

	# Emit from narrow column at fire tip
	crit_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	crit_particles.emission_rect_extents = Vector2(8.0, 2.0)  # Narrow X column at fire tip
	crit_particles.position = Vector2(0, -20)  # At fire tip height

	crit_particles.direction = Vector2(0, -1)  # Straight up (12 o'clock)
	crit_particles.spread = 45.0  # Wider spread - some go sideways/down to cover +Y axis
	crit_particles.gravity = Vector2(0, 25)  # Moderate gravity for controlled arc
	crit_particles.initial_velocity_min = 60.0  # Lower velocity - don't shoot too high
	crit_particles.initial_velocity_max = 90.0

	# Heavy damping to slow them quickly as they rise
	crit_particles.damping_min = 20.0
	crit_particles.damping_max = 30.0

	# Strong tangential acceleration to push them sideways (creates mushroom spread)
	# Negative values push left, positive push right - creates full 360° mushroom
	crit_particles.tangential_accel_min = -120.0
	crit_particles.tangential_accel_max = 120.0

	# Explosive burst that simmers down
	crit_particles.scale_amount_min = 1.5
	crit_particles.scale_amount_max = 3.5
	crit_particles.scale_amount_curve = Curve.new()
	crit_particles.scale_amount_curve.add_point(Vector2(0, 0.4))  # Start burst
	crit_particles.scale_amount_curve.add_point(Vector2(0.15, 1.0))  # Peak explosion
	crit_particles.scale_amount_curve.add_point(Vector2(0.6, 0.7))  # Simmer
	crit_particles.scale_amount_curve.add_point(Vector2(1, 0.0))  # Fade

	crit_particles.color_ramp = Gradient.new()
	crit_particles.color_ramp.add_point(0.0, Color(1.0, 1.0, 1.0, 0.6))  # White hot spark (more transparent)
	crit_particles.color_ramp.add_point(0.1, Color(0.5, 0.9, 1.0, 0.5))  # Bright cyan
	crit_particles.color_ramp.add_point(0.3, Color(0.2, 0.7, 1.0, 0.4))  # Blue
	crit_particles.color_ramp.add_point(0.6, Color(0.15, 0.6, 0.95, 0.28))  # Still visible
	crit_particles.color_ramp.add_point(0.85, Color(0.1, 0.5, 0.8, 0.12))  # Dimming slowly
	crit_particles.color_ramp.add_point(1.0, Color(0.0, 0.3, 0.6, 0.0))  # Simmer to ground

	fire_sprite.add_child(crit_particles)
	crit_particles.emitting = false  # Start disabled

	# GREEN MIST PARTICLES (rising from heal aura)
	var heal_mist_particles = CPUParticles2D.new()
	heal_mist_particles.name = "HealMistParticles"
	heal_mist_particles.emitting = false  # Start disabled
	heal_mist_particles.amount = 16  # Doubled from 8
	heal_mist_particles.lifetime = 3.5
	heal_mist_particles.one_shot = false

	# Use POINTS emission with ring of points for even distribution
	heal_mist_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	heal_mist_particles.emission_points = create_emission_ring(150.0, 32)  # Even spread

	heal_mist_particles.direction = Vector2(0, -1)
	heal_mist_particles.spread = 25.0
	heal_mist_particles.gravity = Vector2(0, -4)
	heal_mist_particles.initial_velocity_min = 3.0
	heal_mist_particles.initial_velocity_max = 10.0

	# Even smaller particles (50% of previous scale)
	heal_mist_particles.scale_amount_min = 1.5
	heal_mist_particles.scale_amount_max = 2.5

	heal_mist_particles.color_ramp = Gradient.new()
	heal_mist_particles.color_ramp.add_point(0.0, Color(0.0, 1.0, 0.0, 0.0))
	heal_mist_particles.color_ramp.add_point(0.15, Color(0.1, 0.9, 0.1, 0.2))
	heal_mist_particles.color_ramp.add_point(0.5, Color(0.0, 0.7, 0.0, 0.1))
	heal_mist_particles.color_ramp.add_point(1.0, Color(0.0, 0.4, 0.0, 0.0))

	fire_sprite.add_child(heal_mist_particles)

	# CYAN MIST PARTICLES (rising from crit aura)
	var crit_mist_particles = CPUParticles2D.new()
	crit_mist_particles.name = "CritMistParticles"
	crit_mist_particles.emitting = false  # Start disabled
	crit_mist_particles.amount = 16  # Doubled from 8
	crit_mist_particles.lifetime = 3.5
	crit_mist_particles.one_shot = false

	# Use POINTS emission with ring of points for even distribution
	crit_mist_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	crit_mist_particles.emission_points = create_emission_ring(200.0, 32)  # Even spread

	crit_mist_particles.direction = Vector2(0, -1)
	crit_mist_particles.spread = 25.0
	crit_mist_particles.gravity = Vector2(0, -4)
	crit_mist_particles.initial_velocity_min = 3.0
	crit_mist_particles.initial_velocity_max = 10.0

	# Even smaller particles (50% of previous scale)
	crit_mist_particles.scale_amount_min = 1.5
	crit_mist_particles.scale_amount_max = 2.5

	crit_mist_particles.color_ramp = Gradient.new()
	crit_mist_particles.color_ramp.add_point(0.0, Color(0.0, 0.6, 1.0, 0.0))
	crit_mist_particles.color_ramp.add_point(0.15, Color(0.1, 0.8, 1.0, 0.2))
	crit_mist_particles.color_ramp.add_point(0.5, Color(0.0, 0.6, 0.9, 0.1))
	crit_mist_particles.color_ramp.add_point(1.0, Color(0.0, 0.3, 0.6, 0.0))

	fire_sprite.add_child(crit_mist_particles)

	print("✅ Created sparse particle systems with mist")

func create_clearing_stumps() -> void:
	"""Create ~40 tree stumps around the campfire clearing to show it was cleared by chopping"""
	var stump_count = 40
	var clearing_inner_radius = 400.0  # Start at 400px from campfire
	var clearing_outer_radius = 1000.0  # Expanded radius for more stumps

	# Available tree textures
	var tree_textures = [
		"res://assets/environment/wasteland/dead_tree_1.png",
		"res://assets/environment/wasteland/dead_tree_2.png",
		"res://assets/environment/wasteland/dead_tree_3.png",
		"res://assets/environment/wasteland/dead_tree_4.png",
		"res://assets/environment/wasteland/dead_tree_5.png",
		"res://assets/environment/wasteland/dead_tree_6.png",
		"res://assets/environment/wasteland/dead_tree_7.png",
		"res://assets/environment/wasteland/dead_tree_8.png",
		"res://assets/environment/wasteland/dead_tree_9.png",
		"res://assets/environment/wasteland/dead_tree_10.png"
	]

	# Create a container for all stumps
	var stump_container = Node2D.new()
	stump_container.name = "ClearingStumps"
	stump_container.z_index = 1  # Same as trees
	add_child(stump_container)

	# Seed RNG with campfire position for deterministic placement
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(global_position))

	for i in range(stump_count):
		# Random position in ring around campfire
		var angle = rng.randf() * TAU
		var distance = rng.randf_range(clearing_inner_radius, clearing_outer_radius)
		var stump_pos = Vector2(cos(angle), sin(angle)) * distance

		# Pick random tree texture
		var tree_texture_path = tree_textures[rng.randi() % tree_textures.size()]
		var tree_texture = load(tree_texture_path) as Texture2D
		if not tree_texture:
			continue

		# Simulate full tree setup to get proper stump (like HarvestableTree does)
		# Use random tree scale (same as ChunkBasedPropSystem)
		var size_roll = rng.randf()
		var tree_scale: float
		if size_roll < 0.1:
			tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (10%)
		elif size_roll < 0.55:
			tree_scale = rng.randf_range(2.93, 3.9)  # Medium trees (45%)
		else:
			tree_scale = rng.randf_range(3.9, 5.2)  # Large trees (45%)

		# Create stump: Take original tree, crop to bottom 11% with curved jagged cut
		var source_img = tree_texture.get_image()
		var stump_height = int(source_img.get_height() * 0.11)
		var stump_img = Image.create(source_img.get_width(), stump_height, false, Image.FORMAT_RGBA8)

		# Extract bottom portion
		var src_y = source_img.get_height() - stump_height
		stump_img.blit_rect(source_img, Rect2i(0, src_y, source_img.get_width(), stump_height), Vector2i(0, 0))

		# Add curved jagged cut effect to top (realistic chopped appearance)
		var cut_wave_frequency = 0.15  # How wavy the cut is
		var cut_depth_variation = 8  # Maximum depth of cut variations
		for x in range(stump_img.get_width()):
			# Create wave pattern for natural curve
			var wave = sin(float(x) * cut_wave_frequency) * 0.5 + 0.5  # 0.0 to 1.0
			var base_cut_depth = int(wave * cut_depth_variation) + 3  # Minimum 3 pixels

			# Add random jaggedness on top of the wave
			var jagged_variation = rng.randi_range(-2, 3)
			var total_cut_depth = base_cut_depth + jagged_variation

			# Fade out pixels at the cut line
			for y in range(max(0, total_cut_depth)):
				if y < stump_img.get_height():
					var pixel = stump_img.get_pixel(x, y)
					if pixel.a > 0:
						# Gradually fade based on depth
						var fade = 1.0 - (float(y) / float(total_cut_depth))
						pixel.a *= fade * rng.randf_range(0.2, 0.9)
						stump_img.set_pixel(x, y, pixel)

		# Create stump container (like HarvestableTree does)
		var stump_node = Node2D.new()
		stump_node.name = "Stump_%d" % i
		stump_node.position = stump_pos
		stump_node.z_index = 1

		# Add oval shadow at base (proper ellipse, not rectangle)
		# Scale shadow to match 11% stump size
		var stump_scale_factor = 0.7  # Stumps are 70% of tree size
		var shadow_width = 45 * (tree_scale / 2.5) * 0.75 * stump_scale_factor * 0.65 * 1.1  # 10% bigger
		var shadow_height = shadow_width * 0.4
		var shadow_y = (stump_height * stump_scale_factor) - 3  # Move up 3px on Y axis (was -5, now -3)

		# Create oval shadow using Polygon2D
		var shadow = Polygon2D.new()
		shadow.name = "Shadow"

		# Generate ellipse points
		var ellipse_points = PackedVector2Array()
		var segments = 32  # Smooth circle
		for j in range(segments):
			var ellipse_angle = (float(j) / segments) * TAU
			var x = cos(ellipse_angle) * (shadow_width / 2)
			var y = sin(ellipse_angle) * (shadow_height / 2)
			ellipse_points.append(Vector2(x, y))

		shadow.polygon = ellipse_points
		shadow.position = Vector2(0, shadow_y)
		shadow.color = Color(0, 0, 0, 0.6)
		shadow.z_index = -4
		stump_node.add_child(shadow)

		# Create stump sprite (scale down 30% from normal tree size)
		var stump_sprite = Sprite2D.new()
		stump_sprite.name = "StumpSprite"
		stump_sprite.texture = ImageTexture.create_from_image(stump_img)
		stump_sprite.centered = true
		var stump_scale = tree_scale * 0.7  # 30% smaller than normal trees
		stump_sprite.scale = Vector2(stump_scale, stump_scale)
		stump_sprite.rotation = 0  # NO rotation - flat on X axis like real stumps

		# Mix of brown and white/grey stumps (50/50 like the real trees)
		var is_white_birch = rng.randf() < 0.5
		var color_variation = rng.randf_range(0.9, 1.0)

		if is_white_birch:
			# White/grey birch stump
			stump_sprite.modulate = Color(color_variation * 0.8, color_variation * 0.85, color_variation * 0.9, 1.0)  # Greyish-white
		else:
			# Brown dead tree stump
			stump_sprite.modulate = Color(0.7, 0.6, 0.5, 1.0)

		stump_sprite.z_index = 0

		# Position stump right at the shadow (no offset - it's already just the base)
		stump_sprite.position = Vector2(0, 0)

		stump_node.add_child(stump_sprite)
		stump_container.add_child(stump_node)

	print("🪵 Created %d tree stumps around campfire clearing" % stump_count)

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
	"""Draw radial progress indicator with fire theme"""
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

	# === FIRE/EMBER THEME ===
	var radius = 22.5  # Match tree size
	var thickness = 3.4  # Match tree thickness

	# Color palette - fire/ember theme
	var bg_color = Color(0.12, 0.10, 0.08, 0.85)  # Dark weathered leather (same as tree)
	var border_outer = Color(0.65, 0.25, 0.10, 1.0)  # Ember/burnt orange border
	var border_inner = Color(0.08, 0.06, 0.05, 1.0)  # Dark inner shadow
	var progress_fire = Color(1.0, 0.50, 0.15, 0.95)  # Fire orange
	var progress_glow = Color(1.0, 0.70, 0.30, 0.4)  # Orange glow

	# Draw outer shadow (depth effect)
	progress_circle.draw_circle(screen_pos, radius + 4, Color(0.0, 0.0, 0.0, 0.6))

	# Draw background circle (dark leather texture)
	progress_circle.draw_circle(screen_pos, radius, bg_color)

	# Draw inner shadow ring
	progress_circle.draw_arc(screen_pos, radius - 2, 0, TAU, 48, border_inner, 3.0)

	# Draw progress arc (fire theme with glow)
	if fuel_progress > 0.0:
		var angle_from = -PI / 2  # Start from top
		var angle_to = angle_from + (fuel_progress * TAU)  # Sweep clockwise

		# Draw glow layer first (underneath)
		var glow_points = PackedVector2Array()
		var glow_radius = radius + 2
		for i in range(49):
			var t = float(i) / 48.0
			var angle = lerp(angle_from, angle_to, t)
			glow_points.append(screen_pos + Vector2(cos(angle), sin(angle)) * glow_radius)

		if glow_points.size() > 2:
			progress_circle.draw_colored_polygon(glow_points, progress_glow)

		# Draw main progress arc (thicker, fire colored)
		progress_circle.draw_arc(screen_pos, radius - thickness / 2, angle_from, angle_to, 48, progress_fire, thickness)

		# Add inner bright edge for definition
		var highlight_color = Color(1.0, 0.85, 0.50, 0.8)  # Bright fire highlight
		progress_circle.draw_arc(screen_pos, radius - thickness - 1, angle_from, angle_to, 48, highlight_color, 1.5)

	# Draw outer border ring (ember/burnt orange)
	progress_circle.draw_arc(screen_pos, radius + 1, 0, TAU, 48, border_outer, 3.0)

	# Draw inner border ring (darker, for depth)
	progress_circle.draw_arc(screen_pos, radius - thickness - 3, 0, TAU, 48, border_inner, 2.0)


func handle_fuel_interaction(delta: float) -> void:
	"""Handle F press/hold for fuel: tap=1 of each, hold=all"""
	if not player_in_interact_range or not player or not is_instance_valid(player):
		if is_fueling:
			cancel_fueling()
		return

	# Check for F key press/hold
	if Input.is_physical_key_pressed(KEY_F):
		if not is_fueling:
			# Just pressed F - start fueling process
			start_fueling()
		else:
			# Holding F - increment progress
			fuel_progress += delta / fuel_time_required

			# Only show progress circle after 20% progress (prevents flash on quick tap)
			if fuel_progress >= 0.2 and progress_circle:
				if not progress_circle.visible:
					progress_circle.visible = true
				progress_circle.queue_redraw()

			# Complete fueling when progress reaches 100%
			if fuel_progress >= 1.0:
				complete_fueling_all()
	else:
		# F released
		if is_fueling:
			cancel_grace_timer += delta
			# If released quickly (within grace period), deposit 1 of each
			if cancel_grace_timer >= cancel_grace_period:
				# Grace period elapsed - was a tap, not a hold
				if fuel_progress < 0.2:  # Released before 20% progress = tap
					attempt_add_single_fuel_from_inventory()
				cancel_fueling()

func start_fueling() -> void:
	"""Start the fueling process (check if player has fuel)"""
	# First check if player has any fuel in inventory
	var has_wood = false
	var has_bone = false

	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item:
			if item.get("name") == "Dry Log":
				has_wood = true
			if item.get("name") == "Bone Ember":
				has_bone = true

	# If no fuel at all, show notification and don't start fueling
	if not has_wood and not has_bone:
		print("⚠️ You have no fuel to add to the campfire!")
		no_fuel_message_timer = no_fuel_message_duration  # Trigger red message
		return

	print("✅ Starting fueling process...")
	is_fueling = true
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	# Don't show progress circle yet - will show after delay in handle_fuel_interaction

func cancel_fueling() -> void:
	"""Cancel fueling (F released or player moved away)"""
	is_fueling = false
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = false
		progress_circle.queue_redraw()

func complete_fueling_all() -> void:
	"""Complete fueling and add ALL fuel from inventory"""
	is_fueling = false
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = false
		progress_circle.queue_redraw()

	# Add all fuel from inventory
	attempt_add_all_fuel_from_inventory()

func attempt_add_single_fuel_from_inventory() -> void:
	"""Add 1 of each fuel type from inventory (or whichever is available)"""
	var wood_slot = -1
	var bone_slot = -1

	# Find first slot with each fuel type
	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item:
			if item.get("name") == "Dry Log" and wood_slot == -1:
				wood_slot = slot_idx
			if item.get("name") == "Bone Ember" and bone_slot == -1:
				bone_slot = slot_idx

	# If no fuel at all, show notification and return
	if wood_slot == -1 and bone_slot == -1:
		print("⚠️ You have no fuel to add to the campfire!")
		no_fuel_message_timer = no_fuel_message_duration
		return

	var wood_added = 0
	var bone_added = 0

	# Try to add 1 wood
	if wood_slot != -1:
		var wood_item = InventorySystem.get_item(wood_slot)
		if add_wood_fuel(1):
			wood_added = 1
			# Decrease quantity or remove item
			var quantity = wood_item.get("quantity", 1)
			if quantity > 1:
				wood_item["quantity"] = quantity - 1
			else:
				InventorySystem.remove_item(wood_slot)
		else:
			print("⚠️ Wood fuel at max capacity")

	# Try to add 1 bone ember
	if bone_slot != -1:
		var bone_item = InventorySystem.get_item(bone_slot)
		if add_bone_ember_fuel(1):
			bone_added = 1
			# Decrease quantity or remove item
			var quantity = bone_item.get("quantity", 1)
			if quantity > 1:
				bone_item["quantity"] = quantity - 1
			else:
				InventorySystem.remove_item(bone_slot)
		else:
			print("⚠️ Bone ember fuel at max capacity")

	# Debug output
	if wood_added > 0 or bone_added > 0:
		print("🔥 Campfire fueled: %d wood log(s), %d bone ember(s) added" % [wood_added, bone_added])
		print("   Current fuel: %d/%d wood, %d/%d embers" % [wood_count, MAX_WOOD, bone_ember_count, MAX_BONE_EMBERS])

func attempt_add_all_fuel_from_inventory() -> void:
	"""Add ALL wood and bone embers from player inventory"""
	var wood_added = 0
	var bone_added = 0

	# Find all Dry Log items (iterate backwards to avoid index issues)
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Dry Log":
			var quantity = item.get("quantity", 1)
			if add_wood_fuel(quantity):
				wood_added += quantity
				InventorySystem.remove_item(slot_idx)
			else:
				print("⚠️ Wood fuel at max capacity")

	# Find all Bone Ember items (iterate backwards to avoid index issues)
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Bone Ember":
			var quantity = item.get("quantity", 1)
			if add_bone_ember_fuel(quantity):
				bone_added += quantity
				InventorySystem.remove_item(slot_idx)
			else:
				print("⚠️ Bone ember fuel at max capacity")

	# Debug output
	print("🔥 Campfire fueled: %d wood logs, %d bone embers added (ALL)" % [wood_added, bone_added])
	print("   Current fuel: %d/%d wood, %d/%d embers" % [wood_count, MAX_WOOD, bone_ember_count, MAX_BONE_EMBERS])

func apply_crit_buff_to_player() -> void:
	"""Apply crit chance buff to player while in campfire warmth"""
	# Update CharacterStats with current campfire crit buff
	CharacterStats.campfire_crit_buff = get_current_crit_buff()


# REMOVED: check_enemy_deterrent() function
# Players can now kite enemies to campfire and fight while being healed by auras


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

	# Scale the entire fire_sprite (flames, coals, logs, rocks) based on total fuel
	var total_fuel_percent = (wood_percent + bone_percent) / 2.0
	if fire_sprite and is_instance_valid(fire_sprite):
		# Start at 125% base scale, grow up to 187.5% with max fuel (25% larger overall)
		var campfire_scale = 1.25 + (total_fuel_percent * 0.625)
		fire_sprite.scale = Vector2(campfire_scale, campfire_scale)

	# Scale flames vertically with fuel (larger, but same brightness)
	var flame_scale_y = 1.0 + (total_fuel_percent * 0.5)  # Extra vertical stretch
	for flame in flame_nodes:
		if is_instance_valid(flame):
			flame.scale.y = flame_scale_y

	# Increase ember and spark particle intensity with fuel
	var ember_particles = fire_sprite.get_node_or_null("EmberParticles")
	if ember_particles:
		# Base amount: 15, scale up to 30 with full fuel
		ember_particles.amount = int(15 + (total_fuel_percent * 15))
		# Increase velocity for more dramatic effect
		ember_particles.initial_velocity_max = 25.0 + (total_fuel_percent * 25.0)  # Up to 50

	var spark_particles = fire_sprite.get_node_or_null("SparkParticles")
	if spark_particles:
		# Base amount: 20, scale up to 40 with full fuel
		spark_particles.amount = int(20 + (total_fuel_percent * 20))
		# Increase velocity
		spark_particles.initial_velocity_max = 60.0 + (total_fuel_percent * 40.0)  # Up to 100

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

	# Enable/disable and scale particle systems based on fuel
	if heal_particles:
		heal_particles.emitting = wood_count > 0
		if wood_count > 0:
			# Scale from 8 particles at min to 45 at max fuel
			heal_particles.amount = int(8 + (wood_percent * 37))
			# Scale velocity from base to higher
			heal_particles.initial_velocity_max = 180.0 + (wood_percent * 60.0)  # Up to 240

	if crit_particles:
		crit_particles.emitting = bone_ember_count > 0
		if bone_ember_count > 0:
			# Scale from 10 particles at min to 50 at max fuel
			crit_particles.amount = int(10 + (bone_percent * 40))
			# Scale velocity from base to higher
			crit_particles.initial_velocity_max = 180.0 + (bone_percent * 60.0)  # Up to 240

	# Enable/disable mist particles based on fuel
	var heal_mist_particles = fire_sprite.get_node_or_null("HealMistParticles")
	if heal_mist_particles:
		heal_mist_particles.emitting = wood_count > 0
	var crit_mist_particles = fire_sprite.get_node_or_null("CritMistParticles")
	if crit_mist_particles:
		crit_mist_particles.emitting = bone_ember_count > 0

	# Enable/disable aurora particles based on fuel
	var aurora_particles = fire_sprite.get_node_or_null("AuroraParticles")
	if aurora_particles:
		aurora_particles.emitting = (wood_count > 0 or bone_ember_count > 0)

func update_coal_pulsing() -> void:
	"""Animate coal pulsing every frame - synchronized breathing with varied intensity"""
	var time = Time.get_ticks_msec() / 1000.0

	# Synchronized "breathing" pulse - all coals pulse together like a slight breeze
	# Range from 0.6 to 1.0 so they stay mostly lit, just dimming/brightening
	var base_pulse = 0.8 + sin(time * 1.5) * 0.2  # Slow synchronized pulse (0.6 to 1.0)

	# Calculate fuel percentages
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)

	# Update main coal colors (first 10 coals)
	for i in range(coal_nodes.size()):
		var coal = coal_nodes[i]
		if not is_instance_valid(coal):
			continue

		# Get this coal's properties
		var brightness = coal_brightness_intensity[i]  # How hot this coal burns
		var color_pref = coal_color_preferences[i]  # 0=green, 1=blue, 2=orange

		# Apply brightness variation to the synchronized pulse
		# Hotter coals (higher brightness) glow more, cooler coals glow less
		var coal_pulse = base_pulse * brightness

		# Base charcoal color (dark, almost black)
		var charcoal_color = Color(0.15, 0.08, 0.05, 1.0)

		# All coals glow red-orange like regular hot coals
		var glow_color = Color(0.9, 0.35, 0.05, 1.0)  # Red-orange glow

		# Pulse between charcoal and glow color, modulated by coal's brightness
		coal.color = charcoal_color.lerp(glow_color, coal_pulse)

	# Update coal glow colors (small embers between rocks and fire) - starts at index 10
	var glow_start_index = 10
	for i in range(coal_glow_nodes.size()):
		var coal_glow = coal_glow_nodes[i]
		if not is_instance_valid(coal_glow):
			continue

		# Get this coal glow's properties
		var brightness = coal_brightness_intensity[glow_start_index + i]
		var color_pref = coal_color_preferences[glow_start_index + i]

		# Apply brightness variation to the synchronized pulse
		var coal_pulse = base_pulse * brightness

		# Base charcoal color (dark, almost black)
		var charcoal_color = Color(0.15, 0.08, 0.05, 0.85)

		# All coal glows are red-orange like regular hot coals
		var glow_color = Color(0.9, 0.35, 0.05, 0.9)  # Red-orange glow

		# Pulse between charcoal and glow color, modulated by coal's brightness
		coal_glow.color = charcoal_color.lerp(glow_color, coal_pulse)

func update_buff_collision_radius() -> void:
	"""Update Area2D collision radius to match the largest active buff aura"""
	if not has_node("CollisionShape2D"):
		return

	var collision = get_node("CollisionShape2D")
	if not collision.shape is CircleShape2D:
		return

	# Calculate current aura radii based on fuel levels (same formula as update_ground_mist)
	# Both can reach same max size (468.75px)
	var heal_aura_radius = 50.0 + (wood_count * 8.375)  # 50-468.75px
	var crit_aura_radius = 50.0 + (bone_ember_count * 4.1875)  # 50-468.75px

	var new_radius: float

	# If no fuel at all, use warmth_radius (150px) for minimal healing range
	# Otherwise, use the larger aura radius (visual auras start at 50px with fuel)
	if wood_count == 0 and bone_ember_count == 0:
		new_radius = warmth_radius  # 150px - for minimal healing with no visual
	else:
		new_radius = max(50.0, max(heal_aura_radius, crit_aura_radius))

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
	return bone_percent * 0.165  # 0-0.165 (0-16.5% crit chance)

func create_fuel_ui() -> void:
	"""Create UI panel showing current fuel levels and buffs"""
	var canvas = CanvasLayer.new()
	canvas.name = "FuelUICanvas"
	canvas.layer = 100
	add_child(canvas)

	# This will be implemented with CampfireFuelUI scene
	# For now, just create the canvas layer
	print("✅ Fuel UI canvas created (waiting for CampfireFuelUI scene)")
