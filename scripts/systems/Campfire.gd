extends Area2D
class_name Campfire

## 🔥 Campfire - Safe Haven
## - Heals player when in radius
## - Deters enemies from entering (they turn back at edge)
## - Provides warmth and safety in hostile world

# Healing configuration
@export var heal_rate: float = 5.0  # HP per second
@export var warmth_radius: float = 150.0  # Healing/deterrent radius
@export var enable_deterrence: bool = true  # Whether enemies are deterred (false for ruins campfire)

# Visual configuration
@export var fire_color_inner: Color = Color(1.0, 0.8, 0.2)  # Bright yellow-orange
@export var fire_color_outer: Color = Color(1.0, 0.3, 0.0)  # Deep orange-red
@export var warmth_color: Color = Color(1.0, 0.6, 0.2, 0.15)  # Warm glow

# State
var player_in_warmth: bool = false
var heal_timer: float = 0.0
var heal_interval: float = 1.0  # Heal every 1.0 seconds (aligned with heal sound)
var heal_pattern_index: int = 0  # Cycles 0,1,2 for tone1,tone1,tone2 pattern

# Fuel System (NEW - Interactive Campfire Buffs)
var wood_count: int = 0  # Wood logs for healing buff
var bone_ember_count: int = 0  # Bone embers for crit chance buff
const MAX_WOOD: int = 50  # Max wood for full healing buff (+20 HP/s)
const MAX_BONE_EMBERS: int = 100  # Max bone embers for full crit buff (+16.5%)
const BASE_HEAL_RATE: float = 5.0  # Base healing (before buffs)
const MAX_HEAL_BONUS: float = 20.0  # Max bonus healing from wood
const MAX_CRIT_BONUS: float = 0.165  # Max bonus crit chance from bone embers (16.5%)

# Fuel decay (fires slowly burn down)
const WOOD_BURN_RATE: float = 1.0 / 90.0  # 1 wood per 90 seconds (50 wood = 75 min)
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

# Performance optimization
var enemy_check_timer: float = 0.0
var enemy_check_interval: float = 0.2  # Check enemies every 0.2 seconds instead of every frame

# References
var player: CharacterBody2D = null
var warmth_circle: Polygon2D = null
var fire_sprite: Node2D = null
var fire_audio: AudioStreamPlayer2D = null
var healing_audio_1: AudioStreamPlayer2D = null  # First healing tone
var healing_audio_2: AudioStreamPlayer2D = null  # Second healing tone

# Cached references for animation performance
var flame_nodes: Array[Polygon2D] = []
var coal_nodes: Array[Polygon2D] = []
var fire_light: PointLight2D = null

# Buff aura visuals
var heal_aura_ring: Node2D = null  # Visual indicator for healing buff
var crit_aura_ring: Node2D = null  # Visual indicator for crit buff

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

	# Cache fire light reference for performance
	if has_node("FireLight"):
		fire_light = get_node("FireLight")

	# Create looping fire sound
	create_fire_audio()

	# Cache flame and coal nodes for animation performance
	cache_animation_nodes()

	# Create healing tick sound (plays once per heal)
	create_healing_audio()

	# Create interaction prompt for adding fuel
	create_interaction_prompt()

	# Create radial progress circle for hold-to-fuel
	create_progress_circle()

	# Create buff aura visual indicators
	create_buff_aura_rings()

	# Add physical collision so player can't walk through fire
	add_collision_body()

	# Set collision shape to match warmth radius
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is CircleShape2D:
			collision.shape.radius = warmth_radius


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

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player = body as CharacterBody2D
		player_in_warmth = true
		heal_timer = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_warmth = false
		player = null
		heal_pattern_index = 0  # Reset pattern when leaving
		CharacterStats.campfire_crit_buff = 0.0  # Clear crit buff

func check_enemy_deterrent() -> void:
	"""Deter enemies that reach the warmth radius - they get blocked at the edge"""
	# Skip if deterrence is disabled (e.g., ruins campfire)
	if not enable_deterrence:
		return

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

					# Put enemy in DETERRED state (swing at air, then give up)
					if ai.has_method("enter_deterred_state"):
						ai.enter_deterred_state()

func create_campfire_visual() -> void:
	"""Create enhanced campfire with detailed logs, rocks, and particle effects"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.position = Vector2(0, -15)  # Raised 5px higher over coals
	fire_sprite.scale = Vector2(2.0, 2.0)  # Scale up 2x
	add_child(fire_sprite)

	# === ROCK RING === (surrounding the fire pit)
	var rock_colors = [
		Color(0.35, 0.32, 0.30, 1.0),  # Grey
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

	# Left log highlight (thicker, moved up 20px, scaled 75%)
	var log_left_highlight = Line2D.new()
	log_left_highlight.width = 1.69  # 75% of 2.25
	log_left_highlight.default_color = log_color_light
	log_left_highlight.add_point(Vector2(-15, 8.25))    # 75% scale
	log_left_highlight.add_point(Vector2(-3.75, -9.75)) # 75% scale
	log_left_highlight.z_index = -1
	fire_sprite.add_child(log_left_highlight)

	# Right log (leaning left) - 50% thicker, scaled 75%
	var log_right = Polygon2D.new()
	log_right.polygon = PackedVector2Array([
		Vector2(17.25, 6.75),   # Bottom right (75% scale)
		Vector2(6, -10.5),      # Top right (75% scale)
		Vector2(3.75, -9.75),   # Top left (75% scale)
		Vector2(15, 8.25)       # Bottom left (75% scale)
	])
	log_right.color = log_color
	log_right.name = "LogRight"
	log_right.z_index = -1
	fire_sprite.add_child(log_right)

	# Right log charred end (50% thicker, moved up 20px, scaled 75%)
	var log_right_char = Polygon2D.new()
	log_right_char.polygon = PackedVector2Array([
		Vector2(15, 6.75),      # 75% scale
		Vector2(12.75, 5.25),   # 75% scale
		Vector2(11.25, 6.75),   # 75% scale
		Vector2(13.5, 8.25)     # 75% scale
	])
	log_right_char.color = log_color_burnt
	log_right_char.z_index = -1
	fire_sprite.add_child(log_right_char)

	# Right log highlight (thicker, moved up 20px, scaled 75%)
	var log_right_highlight = Line2D.new()
	log_right_highlight.width = 1.69  # 75% of 2.25
	log_right_highlight.default_color = log_color_light
	log_right_highlight.add_point(Vector2(15, 8.25))    # 75% scale
	log_right_highlight.add_point(Vector2(3.75, -9.75)) # 75% scale
	log_right_highlight.z_index = -1
	fire_sprite.add_child(log_right_highlight)

	# Back center log (50% thicker, moved up 20px, scaled 75%)
	var log_back = Polygon2D.new()
	log_back.polygon = PackedVector2Array([
		Vector2(-2.25, 6.75),   # Bottom left (75% scale)
		Vector2(2.25, 6.75),    # Bottom right (75% scale)
		Vector2(3.375, -12.75), # Top right (75% scale)
		Vector2(-3.375, -12.75) # Top left (75% scale)
	])
	log_back.color = log_color_dark
	log_back.z_index = -1
	log_back.name = "LogBack"
	fire_sprite.add_child(log_back)

	# Back log charred end (moved up 20px, thicker, scaled 75%)
	var log_back_char = Polygon2D.new()
	log_back_char.polygon = PackedVector2Array([
		Vector2(-2.25, 6.75),  # 75% scale
		Vector2(2.25, 6.75),   # 75% scale
		Vector2(1.125, 4.5),   # 75% scale
		Vector2(-1.125, 4.5)   # 75% scale
	])
	log_back_char.color = log_color_burnt
	log_back_char.z_index = -1
	fire_sprite.add_child(log_back_char)

	# Add some smaller broken logs at base (50% thicker, moved up 20px, scaled 75%)
	for i in range(3):
		var broken_log = Polygon2D.new()
		var offset_x = randf_range(-11.25, 11.25)  # 75% of -15 to 15
		broken_log.polygon = PackedVector2Array([
			Vector2(offset_x - 4.5, 9.75),   # 75% scale
			Vector2(offset_x + 4.5, 9.75),   # 75% scale
			Vector2(offset_x + 3.375, 8.25), # 75% scale
			Vector2(offset_x - 3.375, 8.25)  # 75% scale
		])
		broken_log.color = log_color_dark
		broken_log.z_index = -1
		fire_sprite.add_child(broken_log)
	
	# === GLOWING COAL BED === (radiate from fire center, don't touch rocks)
	# Create coals radiating from center, staying clear of rock ring
	for i in range(25):  # Reduced count for performance
		var coal = Polygon2D.new()
		# Radiate from center but stop well before rocks (rock ring is ~28px radius)
		var angle = randf() * TAU
		var distance = randf() * 20.0  # Stop well before rocks (20px < 28px rock radius)
		var coal_offset = Vector2(cos(angle), sin(angle)) * distance
		coal_offset.y = abs(coal_offset.y) * 0.3 + randf_range(0, 6)  # Smaller y spread to avoid edge

		# Size varies - smaller at edges
		var distance_ratio = distance / 22.0  # 0 at center, 1 at edge
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

	# SMOKE particles - ultra minimal (2-3 particles) for performance
	var smoke_particles = CPUParticles2D.new()
	smoke_particles.name = "SmokeParticles"
	smoke_particles.emitting = true
	smoke_particles.amount = 3  # Ultra minimal - just 2-3 particles
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

	# EMBER particles (bright sparks shooting upward) - reduced for performance
	var ember_particles = CPUParticles2D.new()
	ember_particles.name = "EmberParticles"
	ember_particles.emitting = true
	ember_particles.amount = 20  # Reduced from 35 for performance
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

	# SPARK particles (quick bright flashes) - reduced for performance
	var spark_particles = CPUParticles2D.new()
	spark_particles.name = "SparkParticles"
	spark_particles.emitting = true
	spark_particles.amount = 15  # Reduced from 25 for performance
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

			# Color by layer - darker to brighter (very transparent to see wood clearly)
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - red/orange (very transparent)
				colors.append(Color(0.8, 0.2, 0.0, 0.45))
				colors.append(Color(0.95, 0.4, 0.0, 0.4))
				colors.append(Color(1.0, 0.55, 0.1, 0.35))
				colors.append(Color(1.0, 0.7, 0.2, 0.25))
				colors.append(Color(1.0, 0.55, 0.1, 0.35))
				colors.append(Color(0.95, 0.4, 0.0, 0.4))
				colors.append(Color(0.8, 0.2, 0.0, 0.45))
			elif layer == 1:  # Middle - orange/yellow (very transparent)
				colors.append(Color(1.0, 0.5, 0.0, 0.4))
				colors.append(Color(1.0, 0.65, 0.15, 0.35))
				colors.append(Color(1.0, 0.8, 0.3, 0.3))
				colors.append(Color(1.0, 0.9, 0.5, 0.25))
				colors.append(Color(1.0, 0.8, 0.3, 0.3))
				colors.append(Color(1.0, 0.65, 0.15, 0.35))
				colors.append(Color(1.0, 0.5, 0.0, 0.4))
			else:  # Top - yellow/white (very transparent)
				colors.append(Color(1.0, 0.75, 0.25, 0.35))
				colors.append(Color(1.0, 0.85, 0.4, 0.3))
				colors.append(Color(1.0, 0.95, 0.6, 0.25))
				colors.append(Color(1.0, 1.0, 0.8, 0.2))
				colors.append(Color(1.0, 0.95, 0.6, 0.25))
				colors.append(Color(1.0, 0.85, 0.4, 0.3))
				colors.append(Color(1.0, 0.75, 0.25, 0.35))

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
	fire_audio.volume_db = -8.0  # Base volume (will be randomized)
	fire_audio.bus = "Master"
	fire_audio.autoplay = false

	# Spatial audio settings - fade matches warmth radius
	fire_audio.max_distance = warmth_radius * 2.5  # Hear it up to 375 units away
	fire_audio.attenuation = 2.0  # Natural quadratic falloff (sounds more realistic)
	fire_audio.panning_strength = 0.8  # Strong stereo positioning

	add_child(fire_audio)

	# Connect finished signal to randomize pitch/volume on each loop
	fire_audio.finished.connect(_on_fire_audio_loop)

	# Wait a frame for node to be in tree
	await get_tree().process_frame

	# Play manually with initial randomization
	randomize_fire_audio()
	fire_audio.play()


func randomize_fire_audio() -> void:
	"""Randomly vary pitch and volume to prevent repetitive sound"""
	if not fire_audio:
		return

	# Randomize pitch more noticeably (0.90 to 1.10 = ±10%)
	fire_audio.pitch_scale = randf_range(0.90, 1.10)

	# Randomize volume more (−11.0 to -5.0 dB = ±3dB from -8.0)
	fire_audio.volume_db = randf_range(-11.0, -5.0)

func _on_fire_audio_loop() -> void:
	"""Called when fire audio finishes - randomize and replay for variation"""
	if fire_audio:
		randomize_fire_audio()
		fire_audio.play()

func create_healing_audio() -> void:
	"""Create healing tick sounds that play in pattern: tone1, tone1, tone2"""
	# Load first healing tone
	var healing_sound_1 = load("res://assets/sounds/ambient/healing_tick_1.mp3")
	if not healing_sound_1:
		push_warning("⚠️ Failed to load healing_tick_1.mp3")
		return

	# Load second healing tone
	var healing_sound_2 = load("res://assets/sounds/ambient/healing_tick_2.mp3")
	if not healing_sound_2:
		push_warning("⚠️ Failed to load healing_tick_2.mp3")
		return

	# Create first healing audio player
	healing_audio_1 = AudioStreamPlayer2D.new()
	healing_audio_1.name = "HealingAudio1"
	healing_audio_1.stream = healing_sound_1
	healing_audio_1.volume_db = -6.0  # Slightly louder than fire for prominence
	healing_audio_1.bus = "Master"
	healing_audio_1.autoplay = false
	healing_audio_1.max_distance = warmth_radius * 2.5
	healing_audio_1.attenuation = 2.0
	healing_audio_1.panning_strength = 0.8
	add_child(healing_audio_1)

	# Create second healing audio player
	healing_audio_2 = AudioStreamPlayer2D.new()
	healing_audio_2.name = "HealingAudio2"
	healing_audio_2.stream = healing_sound_2
	healing_audio_2.volume_db = -6.0
	healing_audio_2.bus = "Master"
	healing_audio_2.autoplay = false
	healing_audio_2.max_distance = warmth_radius * 2.5
	healing_audio_2.attenuation = 2.0
	healing_audio_2.panning_strength = 0.8
	add_child(healing_audio_2)


func cache_animation_nodes() -> void:
	"""Cache references to animated nodes for performance"""
	if not fire_sprite:
		return

	flame_nodes.clear()
	coal_nodes.clear()

	# Cache all flame and coal nodes once
	for child in fire_sprite.get_children():
		if child.name.begins_with("Flame_") and child is Polygon2D:
			flame_nodes.append(child as Polygon2D)
		elif child.name.begins_with("Coal") and child is Polygon2D:
			coal_nodes.append(child as Polygon2D)


func animate_fire(delta: float) -> void:
	"""Optimized fire animation using cached references"""
	if not fire_sprite:
		return

	var time = Time.get_ticks_msec() / 1000.0

	# Animate flames using cached array (no string comparisons!)
	for i in range(flame_nodes.size()):
		var child = flame_nodes[i]
		if not is_instance_valid(child):
			continue

		var speed = 1.0 + i * 0.15
		var flicker = sin(time * speed + i * 1.5)
		var sway = cos(time * speed * 0.6 + i * 0.8)

		# Vertical flicker (height variation)
		child.scale.y = 1.0 + flicker * 0.2
		# Horizontal sway
		child.scale.x = 1.0 + sway * 0.1
		# Opacity flicker
		child.modulate.a = 0.9 + flicker * 0.1
		# Position wobble
		child.position.x = sway * 0.5

	# Animate coal glow using cached array
	for i in range(coal_nodes.size()):
		var child = coal_nodes[i]
		if not is_instance_valid(child):
			continue

		var pulse = sin(time * 2.0 + i * 0.5)
		child.modulate = Color(1.0, 1.0, 1.0, 0.9 + pulse * 0.1)
		var scale_pulse = 1.0 + pulse * 0.05
		child.scale = Vector2(scale_pulse, scale_pulse)

	# Subtle warmth circle pulse
	if warmth_circle:
		var pulse = sin(time * 0.5)
		warmth_circle.modulate.a = 0.9 + pulse * 0.1

	# Animate fire light (subtle flickering) using cached reference
	if fire_light and is_instance_valid(fire_light):
		var flicker = sin(time * 2.5) * 0.5 + cos(time * 3.7) * 0.3
		fire_light.energy = 1.2 + flicker * 0.15  # Subtle flicker between 1.05 and 1.35

	# Animate buff aura indicators
	animate_buff_auras(delta)

func create_buff_aura_rings() -> void:
	"""Create visual indicators for heal and crit buffs"""
	# Create crit aura ring (ghostly blue/white) - LARGER, draw first (bottom layer)
	# Auras go BELOW flames (which are z_index 1-3), so use z_index 0
	crit_aura_ring = Node2D.new()
	crit_aura_ring.name = "CritAuraRing"
	crit_aura_ring.z_index = 0  # Below flames (1-3), above ground
	crit_aura_ring.light_mask = 1
	crit_aura_ring.self_modulate = Color(1, 1, 1, 1)
	crit_aura_ring.show()
	crit_aura_ring.position = Vector2.ZERO
	add_child(crit_aura_ring)
	crit_aura_ring.draw.connect(_draw_crit_aura)

	print("✅ Created crit aura ring at z_index=0")

	# Create heal aura ring (green/life energy) - SMALLER, draw second (top layer)
	heal_aura_ring = Node2D.new()
	heal_aura_ring.name = "HealAuraRing"
	heal_aura_ring.z_index = 0  # Same as crit, blend with additive mode
	heal_aura_ring.light_mask = 1
	heal_aura_ring.self_modulate = Color(1, 1, 1, 1)

	# Set additive blend mode for color mixing
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	heal_aura_ring.material = material

	heal_aura_ring.show()
	heal_aura_ring.position = Vector2.ZERO
	add_child(heal_aura_ring)
	heal_aura_ring.draw.connect(_draw_heal_aura)

	print("✅ Created heal aura ring at z_index=0 with ADDITIVE blend")

func _draw_heal_aura() -> void:
	"""Draw the healing buff aura - filled transparent green circle"""
	if not heal_aura_ring or wood_count <= 0:
		return

	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var time = Time.get_ticks_msec() / 1000.0

	# Scale from 0 to 300px radius based on fuel (doubled)
	var max_radius = 300.0  # Was 150, now 2x bigger
	var current_radius = wood_percent * max_radius

	if current_radius <= 0:
		return

	# Debug: Only print once when first drawing
	if wood_count == MAX_WOOD and Engine.get_frames_drawn() % 300 == 0:
		print("🟢 Drawing GREEN heal aura: radius=%.1f, wood=%d/%d" % [current_radius, wood_count, MAX_WOOD])

	# Create flowing magical edge with noise
	var segments = 64  # More segments for smooth flow
	var edge_points = PackedVector2Array()

	# Create wavy flowing edge
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU

		# Add flowing wave animation to radius
		var wave1 = sin(angle * 3.0 + time * 2.0) * 5.0
		var wave2 = cos(angle * 5.0 - time * 1.5) * 3.0
		var wave3 = sin(angle * 7.0 + time * 3.0) * 2.0
		var radius_offset = wave1 + wave2 + wave3

		var point_radius = current_radius + radius_offset
		var point = Vector2(cos(angle), sin(angle)) * point_radius
		edge_points.append(point)

	# Draw aura with radial fade - brighter at center, fades to transparent at edges
	# Draw 8 concentric circles for smoother radial gradient
	for layer in range(7, -1, -1):  # 8 layers, outside-in
		var layer_percent = float(layer) / 7.0  # 0.0 (center) to 1.0 (edge)

		# Create points for this layer
		var layer_points = PackedVector2Array()
		for i in range(segments + 1):
			var angle = (float(i) / float(segments)) * TAU
			var wave1 = sin(angle * 3.0 + time * 2.0) * 5.0
			var wave2 = cos(angle * 5.0 - time * 1.5) * 3.0
			var wave3 = sin(angle * 7.0 + time * 3.0) * 2.0
			var radius_offset = wave1 + wave2 + wave3
			var point_radius = (current_radius * (0.3 + layer_percent * 0.7)) + radius_offset
			var point = Vector2(cos(angle), sin(angle)) * point_radius
			layer_points.append(point)

		# Radial fade: subtle at center, transparent at edge
		var alpha = 0.06 * (1.0 - layer_percent * layer_percent)  # Quadratic fade, more subtle
		var layer_color = Color(0.0, 1.0, 0.0, alpha)
		heal_aura_ring.draw_colored_polygon(layer_points, layer_color)

func _draw_crit_aura() -> void:
	"""Draw the crit buff aura - filled transparent blue circle"""
	if not crit_aura_ring or bone_ember_count <= 0:
		return

	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)
	var time = Time.get_ticks_msec() / 1000.0

	# Scale from 0 to 375px radius based on fuel (doubled)
	var max_radius = 375.0  # Was 187.5, now 2x bigger
	var current_radius = bone_percent * max_radius

	if current_radius <= 0:
		return

	# Debug: Only print once when first drawing
	if bone_ember_count == MAX_BONE_EMBERS and Engine.get_frames_drawn() % 300 == 0:
		print("🔵 Drawing BLUE crit aura: radius=%.1f, embers=%d/%d" % [current_radius, bone_ember_count, MAX_BONE_EMBERS])

	# Create flowing magical edge with different pattern than heal
	var segments = 64  # More segments for smooth flow
	var edge_points = PackedVector2Array()

	# Create wavy flowing edge (different pattern from heal)
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU

		# Different wave pattern for ghostly effect
		var wave1 = sin(angle * 4.0 - time * 2.5) * 6.0
		var wave2 = cos(angle * 6.0 + time * 1.8) * 4.0
		var wave3 = sin(angle * 8.0 - time * 2.2) * 2.5
		var radius_offset = wave1 + wave2 + wave3

		var point_radius = current_radius + radius_offset
		var point = Vector2(cos(angle), sin(angle)) * point_radius
		edge_points.append(point)

	# Draw aura with radial fade - brighter at center, fades to transparent at edges
	# Draw 8 concentric circles for smoother radial gradient
	for layer in range(7, -1, -1):  # 8 layers, outside-in
		var layer_percent = float(layer) / 7.0  # 0.0 (center) to 1.0 (edge)

		# Create points for this layer
		var layer_points = PackedVector2Array()
		for i in range(segments + 1):
			var angle = (float(i) / float(segments)) * TAU
			# Different wave pattern for ghostly effect
			var wave1 = sin(angle * 4.0 - time * 2.5) * 6.0
			var wave2 = cos(angle * 6.0 + time * 1.8) * 4.0
			var wave3 = sin(angle * 8.0 - time * 2.2) * 2.5
			var radius_offset = wave1 + wave2 + wave3
			var point_radius = (current_radius * (0.3 + layer_percent * 0.7)) + radius_offset
			var point = Vector2(cos(angle), sin(angle)) * point_radius
			layer_points.append(point)

		# Radial fade: subtle at center, transparent at edge
		var alpha = 0.06 * (1.0 - layer_percent * layer_percent)  # Quadratic fade, more subtle
		var layer_color = Color(0.0, 0.5, 1.0, alpha)  # Cyan-blue
		crit_aura_ring.draw_colored_polygon(layer_points, layer_color)

func animate_buff_auras(delta: float) -> void:
	"""Animate the buff aura rings with flowing edges"""
	# Debug: Print state every 5 seconds
	if Engine.get_frames_drawn() % 300 == 0:
		print("🎨 Aura state: wood=%d/%d, embers=%d/%d" % [wood_count, MAX_WOOD, bone_ember_count, MAX_BONE_EMBERS])
		if heal_aura_ring:
			print("   Green aura ring exists: visible=%s, alpha=%.2f" % [heal_aura_ring.visible, heal_aura_ring.modulate.a])
		if crit_aura_ring:
			print("   Blue aura ring exists: visible=%s, alpha=%.2f" % [crit_aura_ring.visible, crit_aura_ring.modulate.a])

	# Just trigger redraws - the animation is in the draw functions
	if heal_aura_ring:
		if wood_count > 0:
			heal_aura_ring.modulate.a = 1.0
			heal_aura_ring.queue_redraw()
		else:
			heal_aura_ring.modulate.a = 0.0

	if crit_aura_ring:
		if bone_ember_count > 0:
			crit_aura_ring.modulate.a = 1.0
			crit_aura_ring.queue_redraw()
		else:
			crit_aura_ring.modulate.a = 0.0

func get_deterrent_radius() -> float:
	"""Return the radius that deters enemies"""
	return warmth_radius

# ============================================
# FUEL SYSTEM - Interactive Campfire Buffs
# ============================================

func get_current_heal_rate() -> float:
	"""Calculate current healing rate based on wood fuel"""
	var heal_buff_percent = float(wood_count) / float(MAX_WOOD)
	heal_buff_percent = clamp(heal_buff_percent, 0.0, 1.0)
	var bonus_healing = MAX_HEAL_BONUS * heal_buff_percent
	return BASE_HEAL_RATE + bonus_healing

func get_current_crit_bonus() -> float:
	"""Calculate current crit chance bonus based on bone ember fuel"""
	var crit_buff_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)
	crit_buff_percent = clamp(crit_buff_percent, 0.0, 1.0)
	return MAX_CRIT_BONUS * crit_buff_percent

func add_wood_fuel(amount: int) -> bool:
	"""Add wood logs to campfire (returns true if added, false if maxed)"""
	if wood_count >= MAX_WOOD:
		return false

	var added = min(amount, MAX_WOOD - wood_count)
	wood_count += added
	update_visual_intensity()
	return true

func add_bone_ember_fuel(amount: int) -> bool:
	"""Add bone embers to campfire (returns true if added, false if maxed)"""
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

	# Scale flame size based on wood (0.5x to 1.5x)
	var flame_scale = 0.5 + (wood_percent * 1.0)
	for flame in flame_nodes:
		if is_instance_valid(flame):
			flame.scale = Vector2(flame_scale, flame_scale)

	# Add ghostly glow to fire light based on bone embers
	if fire_light and is_instance_valid(fire_light):
		# Base: warm orange (1.0, 0.7, 0.3)
		# With bone embers: shift toward ghostly blue-white
		var ghostly_mix = bone_percent * 0.4  # Max 40% ghostly
		var r = 1.0
		var g = lerp(0.7, 0.9, ghostly_mix)  # More green/white
		var b = lerp(0.3, 0.8, ghostly_mix)  # Much more blue
		fire_light.color = Color(r, g, b)

		# Increase light intensity with fuel
		var base_energy = 1.2
		var bonus_energy = (wood_percent + bone_percent) * 0.3  # Up to +60% brightness
		fire_light.energy = base_energy + bonus_energy

func get_fuel_status() -> Dictionary:
	"""Get current fuel levels and buffs for UI"""
	return {
		"wood_count": wood_count,
		"bone_ember_count": bone_ember_count,
		"max_wood": MAX_WOOD,
		"max_bone_embers": MAX_BONE_EMBERS,
		"heal_rate": get_current_heal_rate(),
		"crit_bonus": get_current_crit_bonus(),
		"wood_percent": float(wood_count) / float(MAX_WOOD),
		"bone_percent": float(bone_ember_count) / float(MAX_BONE_EMBERS)
	}

func create_interaction_prompt() -> void:
	"""Create Hold [F] Add Fuel prompt near campfire"""
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "Hold [F] Add Fuel"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))  # Warm orange
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
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
	canvas.layer = 51  # Above interaction prompt
	add_child(canvas)

	# Create custom drawable node for radial progress
	progress_circle = Node2D.new()
	progress_circle.name = "ProgressCircle"
	progress_circle.visible = false
	canvas.add_child(progress_circle)

	# Connect draw function
	progress_circle.draw.connect(_draw_progress_circle)

func _draw_progress_circle() -> void:
	"""Draw the radial progress circle with wasteland/fire theme"""
	if not progress_circle or not is_fueling:
		return

	# Position circle above campfire
	var circle_world_pos = global_position + Vector2(0, -80)

	# Convert world position to screen position (CanvasLayer uses screen coordinates)
	var canvas_transform = get_viewport().get_canvas_transform()
	var fire_screen_pos = canvas_transform * circle_world_pos

	# === FIRE THEME ===
	var radius = 25.0
	var thickness = 4.0

	# Color palette matching campfire theme
	var bg_color = Color(0.12, 0.10, 0.08, 0.85)  # Dark weathered
	var border_outer = Color(1.0, 0.6, 0.2, 1.0)  # Warm orange
	var border_inner = Color(0.08, 0.06, 0.05, 1.0)  # Dark inner shadow
	var progress_fire = Color(1.0, 0.7, 0.3, 0.95)  # Fire yellow-orange
	var progress_glow = Color(1.0, 0.9, 0.5, 0.6)  # Bright glow

	# Draw outer shadow (depth effect)
	progress_circle.draw_circle(fire_screen_pos, radius + 4, Color(0.0, 0.0, 0.0, 0.6))

	# Draw background circle
	progress_circle.draw_circle(fire_screen_pos, radius, bg_color)

	# Draw inner shadow ring
	progress_circle.draw_arc(fire_screen_pos, radius - 2, 0, TAU, 48, border_inner, 3.0)

	# Draw progress arc
	if fuel_progress > 0.0:
		var angle_from = -PI / 2  # Start from top
		var angle_to = angle_from + (fuel_progress * TAU)  # Sweep clockwise

		# Draw glow layer first (underneath)
		var glow_points = 64
		var glow_arc = PackedVector2Array()
		glow_arc.append(fire_screen_pos)  # Center point
		for i in range(glow_points + 1):
			var t = float(i) / float(glow_points)
			var angle = lerp(angle_from, angle_to, t)
			var point = fire_screen_pos + Vector2(cos(angle), sin(angle)) * (radius - 3)
			glow_arc.append(point)
		progress_circle.draw_colored_polygon(glow_arc, progress_glow)

		# Draw main progress arc
		progress_circle.draw_arc(fire_screen_pos, radius - thickness / 2, angle_from, angle_to, 48, progress_fire, thickness)

		# Add inner bright edge
		var highlight_color = Color(1.0, 1.0, 0.8, 0.9)  # Bright highlight
		progress_circle.draw_arc(fire_screen_pos, radius - thickness - 1, angle_from, angle_to, 48, highlight_color, 1.5)

	# Draw outer border ring (fire orange)
	progress_circle.draw_arc(fire_screen_pos, radius + 1, 0, TAU, 48, border_outer, 3.0)

	# Draw inner border ring
	progress_circle.draw_arc(fire_screen_pos, radius - thickness - 3, 0, TAU, 48, border_inner, 2.0)

func handle_fuel_interaction(delta: float) -> void:
	"""Handle hold-to-fuel mechanic"""
	if not player_in_interact_range:
		# Player left range - cancel immediately
		if is_fueling:
			cancel_fueling()
		return

	var f_is_pressed = Input.is_physical_key_pressed(KEY_F)

	if f_is_pressed:
		# F is being held - reset grace timer and fuel
		cancel_grace_timer = 0.0

		if not is_fueling:
			start_fueling()
		else:
			# Increase progress while F is held
			fuel_progress += delta / fuel_time_required

			# Update progress circle
			if progress_circle:
				progress_circle.queue_redraw()

			# Complete fuel when progress reaches 100%
			if fuel_progress >= 1.0:
				complete_fueling()
	else:
		# F is not pressed - use grace period before cancelling
		if is_fueling:
			cancel_grace_timer += delta

			# Only cancel if grace period has elapsed
			if cancel_grace_timer >= cancel_grace_period:
				cancel_fueling()

func start_fueling() -> void:
	"""Start the fueling process"""
	is_fueling = true
	fuel_progress = 0.0
	cancel_grace_timer = 0.0

	if progress_circle:
		progress_circle.visible = true
		progress_circle.queue_redraw()

func cancel_fueling() -> void:
	"""Cancel fueling (F released or player moved away)"""
	is_fueling = false
	fuel_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

func complete_fueling() -> void:
	"""Complete fueling after progress reaches 100%"""
	is_fueling = false
	fuel_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Add all fuel from inventory
	attempt_add_fuel_from_inventory()

func attempt_add_fuel_from_inventory() -> void:
	"""Automatically add all wood and bone embers from player inventory"""
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
	var crit_bonus = get_current_crit_bonus()
	CharacterStats.campfire_crit_buff = crit_bonus

func decay_fuel(delta: float) -> void:
	"""Slowly burn down fuel over time"""
	# Decay wood (only if we have wood to burn)
	if wood_count > 0:
		wood_decay_accumulator += delta * WOOD_BURN_RATE
		if wood_decay_accumulator >= 1.0:
			var wood_to_remove = int(wood_decay_accumulator)
			wood_count = max(0, wood_count - wood_to_remove)
			wood_decay_accumulator -= wood_to_remove
			if wood_to_remove > 0:
				update_visual_intensity()

	# Decay bone embers (only if we have embers to burn)
	if bone_ember_count > 0:
		bone_ember_decay_accumulator += delta * BONE_EMBER_BURN_RATE
		if bone_ember_decay_accumulator >= 1.0:
			var embers_to_remove = int(bone_ember_decay_accumulator)
			bone_ember_count = max(0, bone_ember_count - embers_to_remove)
			bone_ember_decay_accumulator -= embers_to_remove
			if embers_to_remove > 0:
				update_visual_intensity()

func get_fuel_level_percent() -> float:
	"""Get average fuel level as percentage (0.0 to 1.0) for scaling abandonment time"""
	var wood_percent = float(wood_count) / float(MAX_WOOD)
	var bone_percent = float(bone_ember_count) / float(MAX_BONE_EMBERS)
	return (wood_percent + bone_percent) / 2.0
