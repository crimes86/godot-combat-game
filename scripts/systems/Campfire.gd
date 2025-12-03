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

## Community vs Competitive Campfires:
## - Community campfires (is_community_campfire = true): Any player can add fuel to a shared pool,
##   and ALL players in warmth radius receive healing and crit buffs. Used for spawn/home areas.
## - Competitive campfires (is_community_campfire = false): Ownership-based system where only
##   the owning group benefits from the fire. Used for ruins and contested areas.

@export var is_community_campfire: bool = false  # If true, all players can fuel and benefit (home/spawn campfires)
@export var starts_unlit: bool = false  # If true, campfire starts unlit and requires fuel to ignite

# Unlit state - player-placed campfires start unlit
var is_unlit: bool = false  # True if campfire hasn't been lit yet
const MIN_FUEL_TO_LIGHT: int = 1  # Minimum wood/embers needed to light the fire

# Constants
const Constants = preload("res://scripts/constants.gd")

# Fuel system constants
const MAX_WOOD: int = 50  # Max wood logs for healing buff
const MAX_BONE_EMBERS: int = 100  # Max bone embers for crit buff
const WOOD_BURN_RATE: float = 1.0 / 3000.0  # 1 log per 3000 seconds (~50 min, 50 logs = ~41 hours)
const BONE_EMBER_BURN_RATE: float = 1.0 / 4500.0  # 1 ember per 4500 seconds (~75 min, 100 embers = ~125 hours)
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

# Fuel state (legacy - for ungrouped/solo players)
var wood_count: int = 0
var bone_ember_count: int = 0

# Group fuel pools - each group has separate fuel that only they benefit from
# Key: group_leader_id (int), Value: {wood: int, bone_embers: int, wood_decay: float, ember_decay: float}
var group_fuel_pools: Dictionary = {}
const SOLO_POOL_KEY: int = -1  # Key for solo/ungrouped players
const NO_OWNER: int = -999  # Key for unowned campfire
const COMMUNITY_POOL_KEY: int = -2  # Key for shared community campfire pool

# Campfire ownership system - only one group can own and benefit from a campfire at a time
var owner_pool_key: int = NO_OWNER  # The group/player that owns this campfire
var owner_group_members: Array = []  # Peer IDs of all members in the owning group
const RELEASE_TIMER_DURATION: float = 60.0  # Seconds until campfire becomes free when no owners nearby
var release_timer: float = 0.0  # Current countdown (0 = not counting)
var is_releasing: bool = false  # True when countdown is active
var release_timer_ui: Control = null  # UI showing time until release

# Skeleton spawning from fuel (every 5 fuel items spawns a skeleton)
const FUEL_PER_SKELETON: int = 5
const MAX_CAMPFIRE_SKELETONS: int = 10  # Maximum active skeletons per campfire
var cumulative_fuel_added: int = 0  # Tracks total fuel for skeleton spawning
var campfire_skeletons: Array = []  # Track skeletons spawned by this campfire

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
var warmth_aura: Polygon2D = null  # Always-visible base healing aura (orange/amber)

# Particle systems
var heal_particles: CPUParticles2D = null
var crit_particles: CPUParticles2D = null

# Campfire size/range
var warmth_radius: float = 150.0  # Healing/buff radius (smaller)
var player_in_warmth: bool = false  # True if LOCAL player is in warmth
var player: CharacterBody2D = null  # Reference to LOCAL player only

# Multi-player tracking: Dictionary of players in warmth for healing
# Key: player node, Value: {heal_timer: float, in_warmth: bool}
var players_in_warmth: Dictionary = {}

# Visual elements
var fire_sprite: Node2D = null

func _ready() -> void:
	add_to_group("campfire")

	# Check if this campfire should start unlit
	if starts_unlit:
		is_unlit = true

	# Disable scene's default CampfireLight (we create our own fire_light dynamically)
	var scene_light = get_node_or_null("CampfireLight")
	if scene_light:
		scene_light.queue_free()

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

	# Create tree stumps around campfire clearing (only for non-player-placed campfires)
	if not starts_unlit:
		create_clearing_stumps()

	# If unlit, hide fire visuals
	if is_unlit:
		set_unlit_visuals(true)

	if is_unlit:
		print("🪵 Unlit campfire placed - add fuel to light it!")
	else:
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
	# Check ownership release timer
	_update_ownership_timer(delta)

	# Heal ALL players in warmth based on fuel state:
	# - No fuel (wood_count == 0): Minimal heal (5 HP/s)
	# - With fuel (wood_count > 0): Scaled heal (5-25 HP/s)
	_heal_all_players_in_warmth(delta)

	# Update no fuel message timer
	if no_fuel_message_timer > 0.0:
		no_fuel_message_timer -= delta

	# Update interaction prompt position and visibility
	update_interaction_prompt()

	# Handle hold-to-fuel mechanic
	handle_fuel_interaction(delta)

	# Apply crit buff to player if in warmth
	# - Community campfires: ALL players get crit buff
	# - Competitive campfires: Only owners get crit buff (or anyone if unclaimed)
	if player_in_warmth and player and is_instance_valid(player):
		if is_community_campfire or owner_pool_key == NO_OWNER or _is_local_player_owner():
			apply_crit_buff_to_player()
		else:
			# Clear crit buff if not an owner (competitive campfire)
			CharacterStats.campfire_crit_buff = 0.0

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
		# Track this player in warmth
		players_in_warmth[body] = {"heal_timer": 0.0, "in_warmth": true}

		# Check if this is the LOCAL player (for UI/sound effects)
		var is_local = _is_local_player(body)
		if is_local:
			player = body as CharacterBody2D
			player_in_warmth = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		# Remove from tracking
		if players_in_warmth.has(body):
			players_in_warmth.erase(body)

		# Check if this is the LOCAL player
		var is_local = _is_local_player(body)
		if is_local:
			player_in_warmth = false
			# Clear crit buff only for LOCAL player
			CharacterStats.campfire_crit_buff = 0.0

func _is_local_player(body: Node2D) -> bool:
	"""Check if body is the local player (handles multiplayer)"""
	if not multiplayer.has_multiplayer_peer():
		return true  # Single player - always local

	var local_peer_id = multiplayer.get_unique_id()
	var player_authority = body.get_multiplayer_authority() if body.has_method("get_multiplayer_authority") else 1
	return player_authority == local_peer_id

func _heal_all_players_in_warmth(delta: float) -> void:
	"""Heal all players currently in campfire warmth.
	- Community campfires: ALL players in warmth get healed using shared fuel pool.
	- Competitive campfires: Only owners get healed using their group's fuel pool.
	- Unclaimed campfires: Anyone gets minimal healing (incentivizes claiming)."""
	# No healing from unlit campfires
	if is_unlit:
		return

	# Clean up invalid player references
	var to_remove = []
	for p in players_in_warmth.keys():
		if not is_instance_valid(p):
			to_remove.append(p)
	for p in to_remove:
		players_in_warmth.erase(p)

	# Process healing for each player in warmth
	for p in players_in_warmth.keys():
		if not is_instance_valid(p):
			continue

		# For competitive campfires:
		# - If unclaimed (owner_pool_key == NO_OWNER), anyone gets minimal healing
		# - If claimed, only owners get healed
		# For community campfires: heal ALL players in warmth
		if not is_community_campfire and owner_pool_key != NO_OWNER and not _is_player_owner(p):
			continue

		var player_data = players_in_warmth[p]
		var player_needs_healing = p.current_health < p.max_health if "current_health" in p and "max_health" in p else false

		if not player_needs_healing:
			continue

		# Update this player's heal timer
		player_data.heal_timer += delta
		if player_data.heal_timer >= heal_interval:
			player_data.heal_timer = 0.0

			# Get healing rate based on this player's fuel pool
			var player_heal_rate = get_heal_rate_for_player(p)

			# Apply healing using this player's pool rate
			if p.has_method("heal"):
				p.heal(player_heal_rate * heal_interval)

				# Only play healing sound for LOCAL player
				if _is_local_player(p):
					# Play healing sound in pattern: 6-6-4 (sound 6 twice, then sound 4)
					if heal_pattern_index < 2:
						if healing_audio_1:
							healing_audio_1.play()
					else:
						if healing_audio_2:
							healing_audio_2.play()
					heal_pattern_index = (heal_pattern_index + 1) % 3


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

	# Create 8 rocks in a tighter circle around fire (reduced from 12)
	for i in range(8):
		var angle = (i * TAU) / 8.0 + randf_range(-0.1, 0.1)
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

	# Create bone ember coals radiating from center (reduced from 10 to 5)
	for i in range(5):
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

		fire_sprite.add_child(coal)

		# Add random brightness intensity for this coal (some burn hotter)
		coal_brightness_intensity.append(randf_range(0.6, 1.0))  # Varied heat intensity
		# Mix of green, blue, and orange: 0=green, 1=blue, 2=orange
		coal_color_preferences.append(i % 3)  # Cycle through 0,1,2,0,1,2...

	# Create light source
	fire_light = PointLight2D.new()
	fire_light.enabled = true
	fire_light.texture_scale = 6.0  # Large ambient glow for immersion
	fire_light.color = Color(1.0, 0.65, 0.25)  # Warm orange
	fire_light.energy = 1.5  # Brighter base energy
	fire_light.shadow_enabled = true
	fire_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	fire_light.blend_mode = Light2D.BLEND_MODE_ADD

	# Create procedural radial gradient texture for visible glow
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center = Vector2(128, 128)
	var max_radius = 128.0
	for x in range(256):
		for y in range(256):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			alpha = alpha * alpha  # Smooth falloff
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var texture = ImageTexture.create_from_image(img)
	fire_light.texture = texture

	fire_sprite.add_child(fire_light)
	print("🔥💡 [LIGHT INIT] Created fire_light: enabled=%s, energy=%.2f, texture_scale=%.2f, color=%s" % [
		fire_light.enabled, fire_light.energy, fire_light.texture_scale, fire_light.color
	])

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
	# PERFORMANCE: Single ring with 8 embers (was 2 rings with 20 total)
	var num_glow_embers = 8
	var glow_index = 0

	for i in range(num_glow_embers):
		var coal_glow = Polygon2D.new()
		coal_glow.name = "CoalGlow_" + str(i)

		# Position in ring with some randomness
		var angle = (float(i) / float(num_glow_embers)) * TAU + randf_range(-0.1, 0.1)
		var distance = randf_range(8.0, 20.0)
		var coal_pos = Vector2(cos(angle), sin(angle)) * distance

		# Varied coal sizes
		var coal_size = randf_range(3.0, 5.5)
		var coal_points = PackedVector2Array()
		for j in range(5):
			var point_angle = (j * TAU) / 5.0
			var radius = coal_size * randf_range(0.7, 1.0)
			coal_points.append(coal_pos + Vector2(cos(point_angle), sin(point_angle)) * radius)
		coal_glow.polygon = coal_points

		# Start with red-orange pulsing glow
		coal_glow.color = Color(0.9, 0.2, 0.05, 0.85)
		coal_glow.z_index = -2

		fire_sprite.add_child(coal_glow)

		coal_brightness_intensity.append(randf_range(0.6, 1.0))
		coal_color_preferences.append(glow_index % 3)
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

			# Color by layer - BRIGHT vibrant flames
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - red/orange core
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
				colors.append(Color(1.0, 0.5, 0.0, 0.9))
				colors.append(Color(1.0, 0.65, 0.1, 0.85))
				colors.append(Color(1.0, 0.8, 0.2, 0.8))
				colors.append(Color(1.0, 0.65, 0.1, 0.85))
				colors.append(Color(1.0, 0.5, 0.0, 0.9))
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
			elif layer == 1:  # Middle - orange/yellow
				colors.append(Color(1.0, 0.6, 0.0, 0.9))
				colors.append(Color(1.0, 0.75, 0.15, 0.85))
				colors.append(Color(1.0, 0.9, 0.3, 0.8))
				colors.append(Color(1.0, 1.0, 0.5, 0.75))
				colors.append(Color(1.0, 0.9, 0.3, 0.8))
				colors.append(Color(1.0, 0.75, 0.15, 0.85))
				colors.append(Color(1.0, 0.6, 0.0, 0.9))
			else:  # Top - yellow/white tips
				colors.append(Color(1.0, 0.85, 0.3, 0.7))
				colors.append(Color(1.0, 0.95, 0.5, 0.6))
				colors.append(Color(1.0, 1.0, 0.7, 0.5))
				colors.append(Color(1.0, 1.0, 0.9, 0.4))
				colors.append(Color(1.0, 1.0, 0.7, 0.5))
				colors.append(Color(1.0, 0.95, 0.5, 0.6))
				colors.append(Color(1.0, 0.85, 0.3, 0.7))

			flame.vertex_colors = colors
			flame.name = "Flame_" + str(layer) + "_" + str(i)
			flame.z_index = layer
			fire_sprite.add_child(flame)

	print("✅ Created fire particles and flames")


func setup_audio() -> void:
	"""Setup audio streams for fire and healing"""
	# Fire crackling audio (looping) - ambient level
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.stream = load("res://assets/sounds/ambient/campfire_loop.wav")
	fire_audio.volume_db = -18.0
	fire_audio.max_distance = 500.0
	fire_audio.attenuation = 2.0
	fire_audio.panning_strength = 0.8
	fire_audio.pitch_scale = randf_range(0.95, 1.05)
	fire_audio.autoplay = true
	fire_audio.finished.connect(_on_fire_audio_finished)
	add_child(fire_audio)

	# Healing audio - uses same sounds as healing staff for consistency
	healing_audio_1 = AudioStreamPlayer2D.new()
	healing_audio_1.stream = load("res://assets/sounds/player/healing_staff_cast.wav")
	healing_audio_1.volume_db = -10.0
	healing_audio_1.max_distance = 300.0
	healing_audio_1.attenuation = 1.5
	healing_audio_1.panning_strength = 0.8
	add_child(healing_audio_1)

	# Healing audio - alternate sound (impact) for variety in pattern
	healing_audio_2 = AudioStreamPlayer2D.new()
	healing_audio_2.stream = load("res://assets/sounds/player/healing_staff_impact.wav")
	healing_audio_2.volume_db = -10.0
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

	# Wider volume variation (±4dB) for intensity changes - ambient level
	fire_audio.volume_db = -18.0 + randf_range(-4.0, 4.0)

	# 40% chance for lower pitch variation (simulates different fire intensity)
	# Note: Godot doesn't support negative pitch (reverse playback), so we use lower pitch instead
	if randf() < 0.4:
		fire_audio.pitch_scale = randf_range(0.7, 0.85)

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

	# Get fuel from the correct pool
	var pool = _get_owner_fuel_pool()
	var current_wood = pool.wood
	var current_bone_embers = pool.bone_embers

	# Calculate intensity based on total fuel (more fuel = more intense but subtle)
	var wood_percent = float(current_wood) / float(MAX_WOOD)
	var bone_percent = float(current_bone_embers) / float(MAX_BONE_EMBERS)
	var total_fuel_percent = (wood_percent + bone_percent) / 2.0

	# Animation speed scales from 1.3x (no fuel) to 1.8x (max fuel) - more alive feeling
	var animation_speed = 1.3 + (total_fuel_percent * 0.5)

	# Movement intensity scales modestly - flames stay grounded, not balloon-like
	var movement_intensity = 1.0 + (total_fuel_percent * 0.5)

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

				# Livelier sway - increased amplitude for active fire look
				var sway = sin(time * 2.5 * animation_speed + layer_phase_offset + index_phase_offset) * 0.8 * movement_intensity
				var stretch_y = 1.0 + sin(time * 3.5 * animation_speed + layer_phase_offset * 1.5 + index_phase_offset) * 0.07 * movement_intensity

				# More dynamic X scale variation (expand/contract)
				var expand = 1.0 + sin(time * 3.0 * animation_speed + layer_phase_offset * 0.8 + index_phase_offset + 1.0) * 0.04 * movement_intensity

				# Apply transform - slightly more rotation
				flame.rotation = sway * 0.02
				flame.scale.y = stretch_y
				flame.scale.x = expand

	# Make coals pulse/glow
	var pulse = 0.9 + sin(time * 2.0) * 0.1  # Subtle breathing
	for coal in coal_nodes:
		if is_instance_valid(coal):
			# Modulate brightness without changing alpha
			var base_color = coal.color
			coal.modulate = Color(pulse, pulse, pulse, 1.0)


func create_ground_mist_auras() -> void:
	"""Create simple filled circle auras with additive blend so fire glow shows through"""
	# WARMTH AURA (Orange/Amber) - tight visual glow around fire (decoupled from healing radius)
	var visual_aura_radius = 26.0  # Tight glow around fire, NOT tied to healing
	warmth_aura = Polygon2D.new()
	warmth_aura.name = "WarmthAura"
	warmth_aura.z_index = -3  # Behind all other auras
	warmth_aura.color = Color(1.0, 0.5, 0.1, 0.08)  # Soft orange/amber, slightly more visible
	warmth_aura.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	warmth_aura.material = CanvasItemMaterial.new()
	warmth_aura.material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	warmth_aura.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	warmth_aura.polygon = create_wavy_circle(visual_aura_radius, 48, 0.0)  # Tight 40px
	warmth_aura.visible = true  # Always visible
	fire_sprite.add_child(warmth_aura)

	# CRIT AURA (Cyan-Blue) - fuel-based, grows with bone embers
	crit_mist = Polygon2D.new()
	crit_mist.name = "CritAura"
	crit_mist.z_index = -2  # Above warmth, below heal
	crit_mist.color = Color(0.0, 0.6, 1.0, 0.12)  # Slightly higher alpha for additive blend
	crit_mist.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	crit_mist.material = CanvasItemMaterial.new()
	crit_mist.material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	crit_mist.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # Additive: fire glow shows through
	crit_mist.visible = false
	fire_sprite.add_child(crit_mist)

	# HEAL AURA (Green) - fuel-based, grows with wood
	heal_mist = Polygon2D.new()
	heal_mist.name = "HealAura"
	heal_mist.z_index = -1  # Above crit aura
	heal_mist.color = Color(0.0, 1.0, 0.0, 0.10)  # Slightly higher alpha for additive blend
	heal_mist.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	heal_mist.material = CanvasItemMaterial.new()
	heal_mist.material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	heal_mist.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD  # Additive: fire glow shows through
	heal_mist.visible = false
	fire_sprite.add_child(heal_mist)

	print("✅ Created simple polygon auras (including warmth aura)")


func update_ground_mist(delta: float) -> void:
	"""Update aura circles with wavy edges (throttled for performance).
	Auras are drawn based on the OWNER's fuel pool so everyone can see them."""
	if not heal_mist or not crit_mist:
		return

	# Performance: Only update mist when visible on screen
	if not is_visible_on_screen():
		return

	# Update warmth aura with flickering fire-like pulse animation (always visible)
	if warmth_aura and is_instance_valid(warmth_aura):
		var time = Time.get_ticks_msec() / 1000.0
		# Alpha flickers to match flame animation speeds
		var alpha_flicker = 0.05 + sin(time * 3.25) * 0.015 + sin(time * 4.5) * 0.01
		var visual_aura_radius = 26.0  # Tight glow, decoupled from healing
		warmth_aura.polygon = create_fire_pulse_circle(visual_aura_radius, 48, time)
		warmth_aura.color = Color(1.0, 0.5, 0.1, alpha_flicker)

	# Get fuel counts from the OWNER's pool (so everyone sees the same auras)
	var owner_pool = _get_owner_fuel_pool()
	var owner_wood = owner_pool.wood
	var owner_bone_embers = owner_pool.bone_embers

	# Calculate radii - both can reach same max size (468.75px) with equal growth rate per item
	# Growth rate: 8.375px per wood, 4.1875px per ember (both reach 468.75px max)
	# Heal aura: 50px base + (8.375px * wood_count) → max 468.75px at 50 wood
	# Crit aura: 50px base + (4.1875px * bone_count) → max 468.75px at 100 embers
	var heal_radius = 50.0 + (owner_wood * 8.375)  # 50-468.75px
	var crit_radius = 50.0 + (owner_bone_embers * 4.1875)  # 50-468.75px

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
	if owner_wood > 0:
		heal_mist.polygon = create_wavy_circle(heal_radius, 64, 0.0)  # No phase offset
		heal_mist.visible = true

		# Update heal mist particle emission points to match aura size
		var heal_mist_particles = fire_sprite.get_node_or_null("HealMistParticles")
		if heal_mist_particles:
			heal_mist_particles.emission_points = create_emission_ring(heal_radius, 32)  # Update ring size
	else:
		heal_mist.visible = false

	# Update crit aura (cyan circle)
	if owner_bone_embers > 0:
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

func create_fire_pulse_circle(radius: float, segments: int, time: float) -> PackedVector2Array:
	"""Create a circle that pulses outward like flickering fire - no rotation, matches flame speed"""
	var points = PackedVector2Array()

	# Global pulse - matches flame animation speeds (2.5x, 3.0x, 3.5x base)
	var pulse1 = sin(time * 3.25) * 10.0  # Primary pulse - matches flame sway
	var pulse2 = sin(time * 4.5) * 6.0   # Secondary pulse - matches flame stretch
	var pulse3 = sin(time * 3.9) * 4.0   # Tertiary pulse - matches flame expand
	var global_pulse = pulse1 + pulse2 + pulse3

	# Create circle with static irregular edge (like fire shape) + global pulse
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		# Static flame shape - fixed bumps that don't rotate
		var flame_shape = sin(angle * 4.0) * 6.0 + sin(angle * 7.0) * 3.0
		# Add the global pulse to make it breathe
		var rad = radius + flame_shape + global_pulse
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
	"""Create tree stumps around the campfire clearing to show it was cleared by chopping"""
	var stump_count = 18  # Stumps around clearing edge
	var clearing_inner_radius = 180.0  # Start just outside campfire area
	var clearing_outer_radius = 700.0  # Spread out to edge of clearing

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
	stump_container.z_index = 1
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

		# Use random tree scale (same as ChunkBasedPropSystem)
		var size_roll = rng.randf()
		var tree_scale: float
		if size_roll < 0.1:
			tree_scale = rng.randf_range(1.95, 2.93)  # Small trees (10%)
		elif size_roll < 0.55:
			tree_scale = rng.randf_range(2.93, 3.9)  # Medium trees (45%)
		else:
			tree_scale = rng.randf_range(3.9, 5.2)  # Large trees (45%)

		# Create stump: Take original tree, crop to bottom 12%
		var source_img = tree_texture.get_image()
		var stump_height = int(source_img.get_height() * 0.12)
		var stump_img = Image.create(source_img.get_width(), stump_height, false, Image.FORMAT_RGBA8)

		# Extract bottom portion
		var src_y = source_img.get_height() - stump_height
		stump_img.blit_rect(source_img, Rect2i(0, src_y, source_img.get_width(), stump_height), Vector2i(0, 0))

		# Make ALL pixels fully opaque (no transparency)
		for x in range(stump_img.get_width()):
			for y in range(stump_img.get_height()):
				var pixel = stump_img.get_pixel(x, y)
				if pixel.a > 0.1:
					pixel.a = 1.0
					stump_img.set_pixel(x, y, pixel)

		# Add simple jagged top edge (just remove some pixels at very top)
		for x in range(stump_img.get_width()):
			var cut_depth = rng.randi_range(0, 3)  # Only 0-3 pixels deep
			for y in range(cut_depth):
				if y < stump_img.get_height():
					stump_img.set_pixel(x, y, Color(0, 0, 0, 0))

		# Create stump with collision (StaticBody2D)
		var stump_node = StaticBody2D.new()
		stump_node.name = "Stump_%d" % i
		stump_node.position = stump_pos

		# Add small collision shape for the stump
		var collision = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 8.0  # Small collision radius
		collision.shape = shape
		collision.position = Vector2(0, 5)  # Slightly below center
		stump_node.add_child(collision)

		var stump_scale = tree_scale * 0.7  # 30% smaller than normal trees

		# Add oval shadow at base of stump
		var shadow_width = 15.0 + (stump_scale * 8.0)  # Visible shadow scaled with stump
		var shadow_height = shadow_width * 0.4

		var shadow = Polygon2D.new()
		shadow.name = "Shadow"

		# Generate ellipse points
		var ellipse_points = PackedVector2Array()
		var segments = 16
		for j in range(segments):
			var ellipse_angle = (float(j) / segments) * TAU
			var px = cos(ellipse_angle) * (shadow_width / 2)
			var py = sin(ellipse_angle) * (shadow_height / 2)
			ellipse_points.append(Vector2(px, py))

		shadow.polygon = ellipse_points
		# Shadow Y offset: base 7px, +3px extra for large stumps (tree_scale >= 3.9)
		var shadow_y_offset = 7.0
		if tree_scale >= 3.9:
			shadow_y_offset = 10.0  # Large stumps need more offset
		shadow.position = Vector2(0, shadow_y_offset)
		shadow.color = Color(0, 0, 0, 0.4)
		shadow.z_index = -1
		stump_node.add_child(shadow)

		# Create stump sprite
		var stump_sprite = Sprite2D.new()
		stump_sprite.name = "StumpSprite"
		stump_sprite.texture = ImageTexture.create_from_image(stump_img)
		stump_sprite.centered = true
		stump_sprite.scale = Vector2(stump_scale, stump_scale)

		# Mix of stump types: 40% brown oak/maple, 30% white birch, 30% grey/silver
		var stump_roll = rng.randf()
		if stump_roll < 0.4:
			# Brown oak/maple stumps - warm natural wood tones
			var base_brown = rng.randf_range(0.7, 0.9)
			stump_sprite.modulate = Color(
				base_brown,
				base_brown * rng.randf_range(0.7, 0.85),
				base_brown * rng.randf_range(0.5, 0.65),
				1.0
			)
		elif stump_roll < 0.7:
			# White birch stumps - bright cream/white
			var brightness = rng.randf_range(0.9, 1.0)
			stump_sprite.modulate = Color(brightness, brightness * 0.98, brightness * 0.94, 1.0)
		else:
			# Grey/silver birch stumps
			var grey = rng.randf_range(0.75, 0.95)
			stump_sprite.modulate = Color(grey, grey, grey * 1.02, 1.0)

		stump_sprite.z_index = 0
		stump_sprite.position = Vector2(0, 0)

		stump_node.add_child(stump_sprite)
		stump_container.add_child(stump_node)

	print("🪵 Created %d tree stumps around campfire clearing" % stump_count)

func create_interaction_prompt() -> void:
	"""Create UI prompt for fuel interaction"""
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 40  # Below hints panel (50) and UI windows (110)
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
	var was_in_range = player_in_interact_range
	player_in_interact_range = distance <= 100.0  # Interact range slightly smaller than warmth radius

	# Register/unregister with InteractionManager
	if player_in_interact_range and not was_in_range:
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.CAMPFIRE, distance)
	elif not player_in_interact_range and was_in_range:
		InteractionManager.unregister_interactable(self)
	elif player_in_interact_range:
		# Update distance
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.CAMPFIRE, distance)

	# Only show prompt if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)
	if player_in_interact_range and is_active and not is_fueling:
		# Check if player has any fuel items - only show prompt if they do
		var has_fuel = player_has_fuel_items()
		if not has_fuel:
			interaction_prompt.visible = false
			return

		if is_unlit:
			interaction_prompt.text = "Hold [F] Light Fire"
			interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))  # Orange-red
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
	canvas.layer = 40  # Below hints panel (50) and UI windows (110)
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
	# Only respond if we're the active interactable
	if not player_in_interact_range or not player or not is_instance_valid(player) or not InteractionManager.is_active_interactable(self):
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

func player_has_fuel_items() -> bool:
	"""Check if player has any fuel items (Dry Log or Bone Ember) in inventory"""
	for slot_idx in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.get_item(slot_idx)
		if item:
			var item_name = item.get("name", "")
			if item_name == "Dry Log" or item_name == "Bone Ember":
				return true
	return false

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

	# Try to add 1 wood (normal sound for tap)
	if wood_slot != -1:
		var wood_item = InventorySystem.get_item(wood_slot)
		add_wood_fuel(1, false)
		wood_added = 1
		# Decrease quantity or remove item
		var quantity = wood_item.get("quantity", 1)
		if quantity > 1:
			wood_item["quantity"] = quantity - 1
		else:
			InventorySystem.remove_item(wood_slot)

	# Try to add 1 bone ember (normal sound for tap)
	if bone_slot != -1:
		var bone_item = InventorySystem.get_item(bone_slot)
		add_bone_ember_fuel(1, false)
		bone_added = 1
		# Decrease quantity or remove item
		var quantity = bone_item.get("quantity", 1)
		if quantity > 1:
			bone_item["quantity"] = quantity - 1
		else:
			InventorySystem.remove_item(bone_slot)

	# Debug output
	if wood_added > 0 or bone_added > 0:
		var pool = _get_owner_fuel_pool()
		print("🔥 Campfire fueled: %d wood log(s), %d bone ember(s) added" % [wood_added, bone_added])
		print("   Current fuel: %d/%d wood, %d/%d embers" % [pool.wood, MAX_WOOD, pool.bone_embers, MAX_BONE_EMBERS])

func attempt_add_all_fuel_from_inventory() -> void:
	"""Add ALL wood and bone embers from player inventory"""
	var wood_added = 0
	var bone_added = 0

	# Find all Dry Log items (iterate backwards to avoid index issues)
	# Use enhanced sound = true for hold action
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Dry Log":
			var quantity = item.get("quantity", 1)
			add_wood_fuel(quantity, true)
			wood_added += quantity
			InventorySystem.remove_item(slot_idx)

	# Find all Bone Ember items (iterate backwards to avoid index issues)
	# Use enhanced sound = true for hold action
	for slot_idx in range(InventorySystem.inventory_items.size() - 1, -1, -1):
		var item = InventorySystem.get_item(slot_idx)
		if item and item.get("name") == "Bone Ember":
			var quantity = item.get("quantity", 1)
			add_bone_ember_fuel(quantity, true)
			bone_added += quantity
			InventorySystem.remove_item(slot_idx)

	# Debug output
	var pool = _get_owner_fuel_pool()
	print("🔥 Campfire fueled: %d wood logs, %d bone embers added (ALL)" % [wood_added, bone_added])
	print("   Current fuel: %d/%d wood, %d/%d embers" % [pool.wood, MAX_WOOD, pool.bone_embers, MAX_BONE_EMBERS])

# ═══════════════════════════════════════════════════════════════════════════
# CAMPFIRE OWNERSHIP SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func _is_local_player_owner() -> bool:
	"""Check if the local player is part of the owning group."""
	if owner_pool_key == NO_OWNER:
		return false
	var my_pool_key = _get_player_fuel_pool_key()
	return my_pool_key == owner_pool_key

func _is_player_owner(player_node: Node) -> bool:
	"""Check if a specific player node is part of the owning group."""
	if owner_pool_key == NO_OWNER:
		return false

	# Get player's peer ID
	var player_peer_id = 1
	if player_node.has_method("get_multiplayer_authority"):
		player_peer_id = player_node.get_multiplayer_authority()

	return player_peer_id in owner_group_members

func _claim_ownership() -> void:
	"""Claim ownership of this campfire for the local player's group."""
	var pool_key = _get_player_fuel_pool_key()
	owner_pool_key = pool_key
	_update_owner_group_members()
	is_releasing = false
	release_timer = 0.0
	_update_release_timer_ui()
	print("🔥 Campfire claimed by pool_key: %d, owner_members: %s" % [pool_key, owner_group_members])

	# Sync ownership to all clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_ownership_to_clients.rpc(owner_pool_key, owner_group_members)

func _release_ownership() -> void:
	"""Release ownership of this campfire, making it claimable."""
	print("🔥 Campfire released from pool_key: %d" % owner_pool_key)
	owner_pool_key = NO_OWNER
	owner_group_members.clear()
	is_releasing = false
	release_timer = 0.0
	_update_release_timer_ui()

	# Sync release to all clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_ownership_to_clients.rpc(NO_OWNER, [])

func _update_owner_group_members() -> void:
	"""Update the list of peer IDs in the owning group."""
	owner_group_members.clear()
	if owner_pool_key == NO_OWNER:
		return

	if owner_pool_key == SOLO_POOL_KEY:
		# Solo player - just add their peer ID
		var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
		owner_group_members.append(my_id)
	else:
		# Group - get all members from GroupManager
		var group_manager = get_node_or_null("/root/GroupManager")
		if group_manager and group_manager.has_group():
			owner_group_members = group_manager.group_members.duplicate()

func _is_any_owner_nearby() -> bool:
	"""Check if any owner group member is within the aura radius.
	Uses the larger of heal/crit aura so players can fight at edge of their buffs."""
	if owner_pool_key == NO_OWNER:
		return false

	# Calculate the ownership radius based on the owner's fuel (larger of heal/crit auras)
	var owner_pool = _get_owner_fuel_pool()
	var heal_radius = 50.0 + (owner_pool.wood * 8.375)
	var crit_radius = 50.0 + (owner_pool.bone_embers * 4.1875)
	var ownership_radius = max(heal_radius, crit_radius)
	# Ensure minimum radius is at least warmth_radius
	ownership_radius = max(ownership_radius, warmth_radius)

	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player_node in players:
		if not is_instance_valid(player_node):
			continue

		# Get player's peer ID
		var player_peer_id = 1
		if player_node.has_method("get_multiplayer_authority"):
			player_peer_id = player_node.get_multiplayer_authority()

		# Check if this player is an owner
		if player_peer_id in owner_group_members:
			# Check if within ownership radius (aura edge)
			var distance = global_position.distance_to(player_node.global_position)
			if distance <= ownership_radius:
				return true

	return false

func _update_ownership_timer(delta: float) -> void:
	"""Update the ownership release timer."""
	if owner_pool_key == NO_OWNER:
		return

	# Refresh owner group members periodically (in case group changed)
	_update_owner_group_members()

	var any_owner_nearby = _is_any_owner_nearby()

	if any_owner_nearby:
		# Owner is nearby - stop/reset the release timer
		if is_releasing:
			is_releasing = false
			release_timer = 0.0
			_update_release_timer_ui()
	else:
		# No owners nearby - start or continue the release timer
		if not is_releasing:
			is_releasing = true
			release_timer = RELEASE_TIMER_DURATION
			_update_release_timer_ui()
		else:
			release_timer -= delta
			_update_release_timer_ui()

			if release_timer <= 0.0:
				_release_ownership()

func _get_owner_fuel_pool() -> Dictionary:
	"""Get the fuel pool for aura drawing.
	- Community campfires: Always use the shared community pool.
	- Competitive campfires: Use the current owner's pool."""
	if is_community_campfire:
		return _get_or_create_fuel_pool(COMMUNITY_POOL_KEY)
	if owner_pool_key == NO_OWNER:
		return {"wood": 0, "bone_embers": 0, "wood_decay": 0.0, "ember_decay": 0.0}
	var pool = _get_or_create_fuel_pool(owner_pool_key)
	return pool

# ═══════════════════════════════════════════════════════════════════════════
# NETWORK SYNC FOR CAMPFIRE OWNERSHIP AND FUEL
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _sync_ownership_to_clients(new_owner_pool_key: int, new_owner_members: Array) -> void:
	"""Receive ownership sync from server."""
	owner_pool_key = new_owner_pool_key
	owner_group_members = new_owner_members.duplicate()
	is_releasing = false
	release_timer = 0.0
	_update_release_timer_ui()
	print("🔥 [CLIENT] Ownership synced: pool_key=%d, members=%s" % [owner_pool_key, owner_group_members])

@rpc("authority", "call_local", "reliable")
func _sync_fuel_to_clients(pool_key: int, wood: int, bone_embers: int) -> void:
	"""Receive fuel state sync from server."""
	var pool = _get_or_create_fuel_pool(pool_key)
	pool.wood = wood
	pool.bone_embers = bone_embers
	update_visual_intensity()
	print("🔥 [CLIENT] Fuel synced for pool %d: wood=%d, embers=%d" % [pool_key, wood, bone_embers])

func _sync_fuel_state_to_clients() -> void:
	"""Server broadcasts current fuel state to all clients."""
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return

	# Determine which pool to sync
	var pool_key_to_sync: int
	if is_community_campfire:
		# Community campfires always sync the shared pool
		pool_key_to_sync = COMMUNITY_POOL_KEY
	else:
		# Competitive campfires sync the owner's pool
		if owner_pool_key == NO_OWNER:
			return
		pool_key_to_sync = owner_pool_key

	var pool = _get_or_create_fuel_pool(pool_key_to_sync)
	_sync_fuel_to_clients.rpc(pool_key_to_sync, pool.wood, pool.bone_embers)

func _create_release_timer_ui() -> void:
	"""Create the UI element showing time until campfire becomes free."""
	if release_timer_ui:
		return  # Already created

	release_timer_ui = Control.new()
	release_timer_ui.name = "ReleaseTimerUI"
	release_timer_ui.z_index = 100
	add_child(release_timer_ui)

	# Background panel
	var panel = Panel.new()
	panel.name = "Panel"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.border_color = Color(0.8, 0.4, 0.1, 1.0)  # Orange border for warning
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(-60, -80)  # Above campfire
	panel.size = Vector2(120, 40)
	release_timer_ui.add_child(panel)

	# Timer label
	var label = Label.new()
	label.name = "TimerLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 1.0))
	label.position = Vector2(0, 0)
	label.size = Vector2(120, 40)
	label.text = "Releasing: 60s"
	panel.add_child(label)

	release_timer_ui.visible = false

func _update_release_timer_ui() -> void:
	"""Update the release timer UI display."""
	if not release_timer_ui:
		_create_release_timer_ui()

	if is_releasing and release_timer > 0.0:
		release_timer_ui.visible = true
		var label = release_timer_ui.get_node_or_null("Panel/TimerLabel")
		if label:
			var seconds = int(ceil(release_timer))
			label.text = "Releasing: %ds" % seconds
	else:
		release_timer_ui.visible = false

# ═══════════════════════════════════════════════════════════════════════════
# GROUP FUEL POOL MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _get_player_fuel_pool_key() -> int:
	"""Get the fuel pool key for the local player.
	Returns group_leader_id if in a group, or SOLO_POOL_KEY (-1) if solo."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager and group_manager.has_group():
		return group_manager.group_leader
	return SOLO_POOL_KEY

func _get_or_create_fuel_pool(pool_key: int) -> Dictionary:
	"""Get or create a fuel pool for the given key."""
	if not group_fuel_pools.has(pool_key):
		group_fuel_pools[pool_key] = {
			"wood": 0,
			"bone_embers": 0,
			"wood_decay": 0.0,
			"ember_decay": 0.0
		}
	return group_fuel_pools[pool_key]

func _get_fuel_pool_for_player(player_node: Node) -> Dictionary:
	"""Get the appropriate fuel pool for a specific player."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		return _get_or_create_fuel_pool(SOLO_POOL_KEY)

	# Get player's peer ID
	var player_peer_id = 1
	if player_node.has_method("get_multiplayer_authority"):
		player_peer_id = player_node.get_multiplayer_authority()

	# Check if this player is in a group
	if group_manager.is_group_member(player_peer_id):
		return _get_or_create_fuel_pool(group_manager.group_leader)

	return _get_or_create_fuel_pool(SOLO_POOL_KEY)

func get_wood_count_for_player() -> int:
	"""Get wood count for the campfire's relevant fuel pool.
	- Community campfires: Returns shared pool count.
	- Competitive campfires: Returns local player's pool count."""
	var pool: Dictionary
	if is_community_campfire:
		pool = _get_or_create_fuel_pool(COMMUNITY_POOL_KEY)
	else:
		pool = _get_or_create_fuel_pool(_get_player_fuel_pool_key())
	return pool.wood

func get_bone_ember_count_for_player() -> int:
	"""Get bone ember count for the campfire's relevant fuel pool.
	- Community campfires: Returns shared pool count.
	- Competitive campfires: Returns local player's pool count."""
	var pool: Dictionary
	if is_community_campfire:
		pool = _get_or_create_fuel_pool(COMMUNITY_POOL_KEY)
	else:
		pool = _get_or_create_fuel_pool(_get_player_fuel_pool_key())
	return pool.bone_embers

func apply_crit_buff_to_player() -> void:
	"""Apply crit chance buff to player while in campfire warmth.
	Uses community pool for community campfires, player's group pool otherwise."""
	CharacterStats.campfire_crit_buff = get_current_crit_buff_for_player()

func get_current_crit_buff_for_player() -> float:
	"""Get crit buff based on the campfire's fuel pool.
	- Community campfires: Uses shared pool.
	- Competitive campfires: Uses local player's group pool."""
	var pool: Dictionary
	if is_community_campfire:
		pool = _get_or_create_fuel_pool(COMMUNITY_POOL_KEY)
	else:
		pool = _get_or_create_fuel_pool(_get_player_fuel_pool_key())
	var bone_percent = float(pool.bone_embers) / float(MAX_BONE_EMBERS)
	return bone_percent * 0.165  # 0-16.5% bonus crit chance

func get_heal_rate_for_player(player_node: Node) -> float:
	"""Get healing rate for a specific player based on their fuel pool.
	- Community campfires: Uses shared pool for ALL players.
	- Competitive campfires: Uses player's group pool.
	Base: 5 HP/s, Max: 25 HP/s (linear scaling with wood)."""
	var pool: Dictionary
	if is_community_campfire:
		pool = _get_or_create_fuel_pool(COMMUNITY_POOL_KEY)
	else:
		pool = _get_fuel_pool_for_player(player_node)
	if pool.wood > 0:
		var wood_percent = float(pool.wood) / float(MAX_WOOD)
		return 5.0 + (wood_percent * 20.0)  # 5 + (0-20) = 5-25 HP/s
	else:
		return 5.0

func add_wood_fuel_to_pool(amount: int, enhanced_sound: bool = false) -> bool:
	"""Add wood fuel to the campfire.
	- Community campfires: Uses shared pool, anyone can add fuel.
	- Competitive campfires: Uses player's group pool, claims ownership if unowned."""
	var pool_key: int

	if is_community_campfire:
		# Community campfires use a shared pool - anyone can add fuel
		pool_key = COMMUNITY_POOL_KEY
	else:
		# Competitive campfires use player's group pool
		pool_key = _get_player_fuel_pool_key()

		# Check ownership - can only add fuel if unowned or we own it
		if owner_pool_key != NO_OWNER and owner_pool_key != pool_key:
			# Campfire owned by someone else - can't add fuel
			return false

		# Claim ownership if unowned
		if owner_pool_key == NO_OWNER:
			_claim_ownership()

	var pool = _get_or_create_fuel_pool(pool_key)

	var added = min(amount, MAX_WOOD - pool.wood)
	if added > 0:
		pool.wood += added
		update_visual_intensity()

		# Light the fire if it was unlit
		if is_unlit:
			light_campfire()

	# Track cumulative fuel for skeleton spawning
	track_fuel_for_skeletons(amount)

	# Play sound
	if added > 0:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_fire_fuel_sound(global_position, -12.0, enhanced_sound)

	return added > 0

func add_bone_ember_fuel_to_pool(amount: int, enhanced_sound: bool = false) -> bool:
	"""Add bone ember fuel to the campfire.
	- Community campfires: Uses shared pool, anyone can add fuel.
	- Competitive campfires: Uses player's group pool, claims ownership if unowned."""
	var pool_key: int

	if is_community_campfire:
		# Community campfires use a shared pool - anyone can add fuel
		pool_key = COMMUNITY_POOL_KEY
	else:
		# Competitive campfires use player's group pool
		pool_key = _get_player_fuel_pool_key()

		# Check ownership - can only add fuel if unowned or we own it
		if owner_pool_key != NO_OWNER and owner_pool_key != pool_key:
			# Campfire owned by someone else - can't add fuel
			return false

		# Claim ownership if unowned
		if owner_pool_key == NO_OWNER:
			_claim_ownership()

	var pool = _get_or_create_fuel_pool(pool_key)

	var added = min(amount, MAX_BONE_EMBERS - pool.bone_embers)
	if added > 0:
		pool.bone_embers += added
		update_visual_intensity()

		# Light the fire if it was unlit
		if is_unlit:
			light_campfire()

	# Track cumulative fuel for skeleton spawning
	track_fuel_for_skeletons(amount)

	# Play sound
	if added > 0:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_fire_fuel_sound(global_position, -12.0, enhanced_sound)

	return added > 0

func decay_group_fuel_pools(delta: float) -> void:
	"""Decay fuel in all group pools over time."""
	var pools_to_remove: Array[int] = []

	for pool_key in group_fuel_pools:
		var pool = group_fuel_pools[pool_key]

		# Decay wood
		if pool.wood > 0:
			pool.wood_decay += delta * WOOD_BURN_RATE
			if pool.wood_decay >= 1.0:
				var wood_to_remove = int(pool.wood_decay)
				pool.wood = max(0, pool.wood - wood_to_remove)
				pool.wood_decay -= float(wood_to_remove)

		# Decay bone embers
		if pool.bone_embers > 0:
			pool.ember_decay += delta * BONE_EMBER_BURN_RATE
			if pool.ember_decay >= 1.0:
				var embers_to_remove = int(pool.ember_decay)
				pool.bone_embers = max(0, pool.bone_embers - embers_to_remove)
				pool.ember_decay -= float(embers_to_remove)

		# Mark empty pools for cleanup (except solo pool)
		if pool_key != SOLO_POOL_KEY and pool.wood == 0 and pool.bone_embers == 0:
			pools_to_remove.append(pool_key)

	# Clean up empty group pools
	for key in pools_to_remove:
		group_fuel_pools.erase(key)

func merge_solo_fuel_to_group(group_leader_id: int) -> void:
	"""Merge the local player's solo fuel into a group pool when joining.
	Called when a player joins a group to transfer their campfire progress."""
	if not group_fuel_pools.has(SOLO_POOL_KEY):
		return  # No solo fuel to merge

	var solo_pool = group_fuel_pools[SOLO_POOL_KEY]
	if solo_pool.wood == 0 and solo_pool.bone_embers == 0:
		return  # Nothing to merge

	# Get or create the group pool
	var group_pool = _get_or_create_fuel_pool(group_leader_id)

	# Merge fuel (capped at max)
	var wood_to_add = min(solo_pool.wood, MAX_WOOD - group_pool.wood)
	var embers_to_add = min(solo_pool.bone_embers, MAX_BONE_EMBERS - group_pool.bone_embers)

	group_pool.wood += wood_to_add
	group_pool.bone_embers += embers_to_add

	# Clear solo pool
	solo_pool.wood = 0
	solo_pool.bone_embers = 0

	if wood_to_add > 0 or embers_to_add > 0:
		print("🔥 Merged solo fuel into group: +%d wood, +%d embers" % [wood_to_add, embers_to_add])
		update_visual_intensity()

func on_player_joined_group(group_leader_id: int) -> void:
	"""Called when the local player joins a group - merges their solo fuel."""
	merge_solo_fuel_to_group(group_leader_id)

func on_player_left_group() -> void:
	"""Called when the local player leaves a group - their contribution stays with group."""
	# Fuel stays with the group - this is intentional game design
	# (you contributed to the group fire, it doesn't come back when you leave)
	pass


# REMOVED: check_enemy_deterrent() function
# Players can now kite enemies to campfire and fight while being healed by auras


func decay_fuel(delta: float) -> void:
	"""Slowly burn through fuel over time - handles both legacy and group pools"""
	# Decay all group fuel pools
	decay_group_fuel_pools(delta)

	# Legacy decay for backwards compatibility (solo pool uses group system now)
	if wood_count > 0:
		wood_decay_accumulator += delta * WOOD_BURN_RATE
		if wood_decay_accumulator >= 1.0:
			var wood_to_remove = int(wood_decay_accumulator)
			wood_count = max(0, wood_count - wood_to_remove)
			wood_decay_accumulator -= float(wood_to_remove)
			update_visual_intensity()

	if bone_ember_count > 0:
		bone_ember_decay_accumulator += delta * BONE_EMBER_BURN_RATE
		if bone_ember_decay_accumulator >= 1.0:
			var embers_to_remove = int(bone_ember_decay_accumulator)
			bone_ember_count = max(0, bone_ember_count - embers_to_remove)
			bone_ember_decay_accumulator -= float(embers_to_remove)
			update_visual_intensity()


func add_wood_fuel(amount: int, enhanced_sound: bool = false) -> bool:
	"""Add wood fuel (increases healing rate).
	- Community campfires: Uses shared pool, anyone can add fuel.
	- Competitive campfires: Uses group fuel pool, claims ownership if unowned.
	In multiplayer, this requests the server to add fuel."""

	# Track fuel for quest objectives (local player adding fuel)
	_track_quest_fuel(amount)

	# In multiplayer, route through server for proper sync
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_add_wood_fuel.rpc_id(1, amount, enhanced_sound)
		return true  # Assume success, server will sync back

	# Server or single player - process locally
	return _server_add_wood_fuel(amount, enhanced_sound)

@rpc("any_peer", "reliable")
func _request_add_wood_fuel(amount: int, enhanced_sound: bool) -> void:
	"""Client requests server to add wood fuel."""
	if not multiplayer.is_server():
		return
	_server_add_wood_fuel(amount, enhanced_sound)

func _server_add_wood_fuel(amount: int, enhanced_sound: bool) -> bool:
	"""Server-side wood fuel addition with sync to all clients."""
	var pool_key: int

	if is_community_campfire:
		# Community campfires use a shared pool - anyone can add fuel
		pool_key = COMMUNITY_POOL_KEY
	else:
		# Competitive campfires use player's group pool
		pool_key = _get_player_fuel_pool_key()

		# Check ownership - can only add fuel if unowned or we own it
		if owner_pool_key != NO_OWNER and owner_pool_key != pool_key:
			# Campfire owned by someone else - can't add fuel
			print("🔥 Cannot add fuel - campfire owned by another group")
			return false

		# Claim ownership if unowned
		if owner_pool_key == NO_OWNER:
			_claim_ownership()

	var pool = _get_or_create_fuel_pool(pool_key)

	# Add fuel up to max (excess is wasted but still consumed)
	var added = min(amount, MAX_WOOD - pool.wood)
	if added > 0:
		pool.wood += added
		update_visual_intensity()
		# Sync fuel state to all clients
		_sync_fuel_state_to_clients()

	# Track cumulative fuel for skeleton spawning (all fuel counts, even wasted)
	track_fuel_for_skeletons(amount)

	# Play fire fuel sound on all clients
	if multiplayer.has_multiplayer_peer():
		_play_fuel_sound.rpc(enhanced_sound)
	else:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_fire_fuel_sound(global_position, -12.0, enhanced_sound)

	return true

@rpc("any_peer", "call_local", "reliable")
func _play_fuel_sound(enhanced_sound: bool) -> void:
	"""Play fuel sound on all clients."""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_fire_fuel_sound(global_position, -12.0, enhanced_sound)

func add_bone_ember_fuel(amount: int, enhanced_sound: bool = false) -> bool:
	"""Add bone ember fuel (increases crit chance).
	- Community campfires: Uses shared pool, anyone can add fuel.
	- Competitive campfires: Uses group fuel pool, claims ownership if unowned.
	In multiplayer, this requests the server to add fuel."""

	# Track fuel for quest objectives (local player adding fuel)
	_track_quest_fuel(amount)

	# In multiplayer, route through server for proper sync
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_add_bone_ember_fuel.rpc_id(1, amount, enhanced_sound)
		return true  # Assume success, server will sync back

	# Server or single player - process locally
	return _server_add_bone_ember_fuel(amount, enhanced_sound)

@rpc("any_peer", "reliable")
func _request_add_bone_ember_fuel(amount: int, enhanced_sound: bool) -> void:
	"""Client requests server to add bone ember fuel."""
	if not multiplayer.is_server():
		return
	_server_add_bone_ember_fuel(amount, enhanced_sound)

func _server_add_bone_ember_fuel(amount: int, enhanced_sound: bool) -> bool:
	"""Server-side bone ember fuel addition with sync to all clients."""
	var pool_key: int

	if is_community_campfire:
		# Community campfires use a shared pool - anyone can add fuel
		pool_key = COMMUNITY_POOL_KEY
	else:
		# Competitive campfires use player's group pool
		pool_key = _get_player_fuel_pool_key()

		# Check ownership - can only add fuel if unowned or we own it
		if owner_pool_key != NO_OWNER and owner_pool_key != pool_key:
			# Campfire owned by someone else - can't add fuel
			print("🔥 Cannot add fuel - campfire owned by another group")
			return false

		# Claim ownership if unowned
		if owner_pool_key == NO_OWNER:
			_claim_ownership()

	var pool = _get_or_create_fuel_pool(pool_key)

	# Add fuel up to max (excess is wasted but still consumed)
	var added = min(amount, MAX_BONE_EMBERS - pool.bone_embers)
	if added > 0:
		pool.bone_embers += added
		update_visual_intensity()
		# Sync fuel state to all clients
		_sync_fuel_state_to_clients()

	# Track cumulative fuel for skeleton spawning (all fuel counts, even wasted)
	track_fuel_for_skeletons(amount)

	# Play fire fuel sound on all clients
	if multiplayer.has_multiplayer_peer():
		_play_fuel_sound.rpc(enhanced_sound)
	else:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_fire_fuel_sound(global_position, -12.0, enhanced_sound)

	return true

func _track_quest_fuel(amount: int) -> void:
	"""Notify QuestManager of fuel added for quest tracking"""
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	qm.on_campfire_fueled(amount)

func track_fuel_for_skeletons(amount: int) -> void:
	"""Track cumulative fuel and spawn skeletons every 5 items"""
	var old_total = cumulative_fuel_added
	cumulative_fuel_added += amount

	# Calculate how many skeletons to spawn
	var old_skeleton_threshold = old_total / FUEL_PER_SKELETON
	var new_skeleton_threshold = cumulative_fuel_added / FUEL_PER_SKELETON
	var skeletons_to_spawn = new_skeleton_threshold - old_skeleton_threshold

	if skeletons_to_spawn > 0:
		print("🔥💀 Fuel threshold reached! Spawning %d skeleton(s) (total fuel: %d)" % [skeletons_to_spawn, cumulative_fuel_added])
		for i in range(skeletons_to_spawn):
			spawn_campfire_skeleton()

func spawn_campfire_skeleton() -> void:
	"""Spawn a skeleton that's attracted to the campfire"""
	# In multiplayer, clients request spawn from server
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_skeleton_spawn.rpc_id(1)  # Send request to server (peer 1)
		return

	_do_spawn_campfire_skeleton()

@rpc("any_peer", "reliable")
func _request_skeleton_spawn() -> void:
	"""Client requests server to spawn a campfire skeleton"""
	if not multiplayer.is_server():
		return
	print("🌐 Server received skeleton spawn request from peer %d" % multiplayer.get_remote_sender_id())
	_do_spawn_campfire_skeleton()

func _do_spawn_campfire_skeleton() -> void:
	"""Actually spawn the skeleton (server only)"""
	# Clean up dead/invalid skeletons from tracking array
	_cleanup_dead_skeletons()

	# Check if we're at the skeleton cap
	if campfire_skeletons.size() >= MAX_CAMPFIRE_SKELETONS:
		print("🔥💀 Campfire at max skeletons (%d), not spawning more" % MAX_CAMPFIRE_SKELETONS)
		return

	# Find a random spawn position 800-1200 units away from campfire
	var spawn_distance = randf_range(800.0, 1200.0)
	var spawn_angle = randf() * TAU
	var spawn_pos = global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * spawn_distance

	# Load enemy scene
	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		push_warning("Cannot spawn campfire skeleton: enemy scene not found at res://scenes/enemies/enemy.tscn")
		return

	var skeleton = enemy_scene.instantiate()
	skeleton.global_position = spawn_pos

	# Set random level 1-6 for home campfire skeletons
	skeleton.enemy_level = randi_range(1, 6)

	# Mark this skeleton as campfire-attracted (set meta BEFORE adding to tree)
	skeleton.set_meta("campfire_target", self)
	skeleton.set_meta("campfire_spawn_time", Time.get_ticks_msec())
	skeleton.set_meta("is_campfire_skeleton", true)

	# Add to enemies group BEFORE adding to tree - this is critical!
	# game_world._on_node_added() checks group membership to auto-connect corpse_clicked signal
	skeleton.add_to_group(Constants.GROUP_ENEMIES)

	# Generate unique name for network sync
	var skeleton_name = "CampfireSkeleton_%d_%d" % [Time.get_ticks_msec(), randi() % 1000]
	skeleton.name = skeleton_name

	# Add to scene tree
	# This triggers game_world._on_node_added() which will connect corpse_clicked signal
	get_tree().root.add_child(skeleton)

	# Track this skeleton
	campfire_skeletons.append(skeleton)

	# Register with NetworkEnemyManager for multiplayer sync
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(skeleton)
		# Broadcast spawn to clients
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_on_clients.rpc(network_id, spawn_pos, skeleton.enemy_level, skeleton_name)

	print("💀🔥 Spawned campfire skeleton at %s (%d/%d active)" % [spawn_pos, campfire_skeletons.size(), MAX_CAMPFIRE_SKELETONS])

func _cleanup_dead_skeletons() -> void:
	"""Remove dead or invalid skeletons from tracking array"""
	var valid_skeletons: Array = []
	for skeleton in campfire_skeletons:
		if is_instance_valid(skeleton) and not skeleton.is_corpse:
			valid_skeletons.append(skeleton)
	campfire_skeletons = valid_skeletons

func update_visual_intensity() -> void:
	"""Update campfire visual intensity based on fuel levels"""
	# Get the correct fuel pool for visuals
	var pool = _get_owner_fuel_pool()
	var current_wood = pool.wood
	var current_bone_embers = pool.bone_embers

	# Update heal rate (based on pool)
	heal_rate = 5.0 + (float(current_wood) / float(MAX_WOOD) * 20.0)

	# Calculate fuel percentages from the pool
	var wood_percent = float(current_wood) / float(MAX_WOOD)
	var bone_percent = float(current_bone_embers) / float(MAX_BONE_EMBERS)

	# Scale the entire fire_sprite (flames, coals, logs, rocks) based on total fuel
	var total_fuel_percent = (wood_percent + bone_percent) / 2.0
	if fire_sprite and is_instance_valid(fire_sprite):
		# Start at 125% base scale, grow up to 187.5% with max fuel (25% larger overall)
		var campfire_scale = 1.25 + (total_fuel_percent * 0.625)
		fire_sprite.scale = Vector2(campfire_scale, campfire_scale)

	# Scale flames vertically with fuel (modest increase, not balloon-like)
	var flame_scale_y = 1.0 + (total_fuel_percent * 0.25)  # Subtle vertical stretch
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

		# Base light energy and scale - always visible
		var base_energy = 1.5
		var base_texture_scale = 6.0

		# Add bonus from fuel
		var fuel_bonus_energy = total_fuel_percent * 0.8  # Up to +80% brightness with fuel
		var fuel_bonus_scale = total_fuel_percent * 2.0  # Up to +2.0 scale with fuel

		# Scale light based on time of day (brighter at night)
		var time_brightness = 1.0
		if TimeManager and TimeManager.canvas_modulate:
			time_brightness = TimeManager.get_brightness()
		# Map: night (0.51) -> extra glow, day (0.99) -> base glow
		var day_factor = inverse_lerp(0.51, 0.99, time_brightness)
		day_factor = clamp(day_factor, 0.0, 1.0)
		# At night: 1.5x multiplier for extra warmth, at day: 1.0x (keep base visible)
		var time_multiplier = lerp(1.5, 1.0, day_factor)

		fire_light.energy = (base_energy + fuel_bonus_energy) * time_multiplier
		fire_light.texture_scale = base_texture_scale + fuel_bonus_scale + (1.0 - day_factor) * 2.0  # Extra radius at night

		# DEBUG: Track fire light state
		print("🔥💡 [LIGHT DEBUG] enabled=%s, energy=%.2f, texture_scale=%.2f, color=%s" % [
			fire_light.enabled, fire_light.energy, fire_light.texture_scale, fire_light.color
		])
		print("🔥💡 [LIGHT DEBUG] time_brightness=%.2f, day_factor=%.2f, time_mult=%.2f" % [
			time_brightness, day_factor, time_multiplier
		])
		print("🔥💡 [LIGHT DEBUG] wood=%d, bone=%d, wood_pct=%.2f, bone_pct=%.2f" % [
			current_wood, current_bone_embers, wood_percent, bone_percent
		])

	# Update collision area to match largest active aura radius
	update_buff_collision_radius()

	# Enable/disable and scale particle systems based on fuel
	if heal_particles:
		heal_particles.emitting = current_wood > 0
		if current_wood > 0:
			# Scale from 8 particles at min to 45 at max fuel
			heal_particles.amount = int(8 + (wood_percent * 37))
			# Scale velocity from base to higher
			heal_particles.initial_velocity_max = 180.0 + (wood_percent * 60.0)  # Up to 240

	if crit_particles:
		crit_particles.emitting = current_bone_embers > 0
		if current_bone_embers > 0:
			# Scale from 10 particles at min to 50 at max fuel
			crit_particles.amount = int(10 + (bone_percent * 40))
			# Scale velocity from base to higher
			crit_particles.initial_velocity_max = 180.0 + (bone_percent * 60.0)  # Up to 240

	# Enable/disable mist particles based on fuel
	var heal_mist_particles = fire_sprite.get_node_or_null("HealMistParticles")
	if heal_mist_particles:
		heal_mist_particles.emitting = current_wood > 0
	var crit_mist_particles = fire_sprite.get_node_or_null("CritMistParticles")
	if crit_mist_particles:
		crit_mist_particles.emitting = current_bone_embers > 0

	# Enable/disable aurora particles based on fuel
	var aurora_particles = fire_sprite.get_node_or_null("AuroraParticles")
	if aurora_particles:
		aurora_particles.emitting = (current_wood > 0 or current_bone_embers > 0)

func update_coal_pulsing() -> void:
	"""Animate coal pulsing every frame - synchronized breathing with varied intensity"""
	var time = Time.get_ticks_msec() / 1000.0

	# Synchronized "breathing" pulse - all coals pulse together like a slight breeze
	# Range from 0.6 to 1.0 so they stay mostly lit, just dimming/brightening
	var base_pulse = 0.8 + sin(time * 1.5) * 0.2  # Slow synchronized pulse (0.6 to 1.0)

	# Get fuel from the correct pool
	var pool = _get_owner_fuel_pool()
	var current_wood = pool.wood
	var current_bone_embers = pool.bone_embers

	# Calculate fuel percentages
	var wood_percent = float(current_wood) / float(MAX_WOOD)
	var bone_percent = float(current_bone_embers) / float(MAX_BONE_EMBERS)

	# Update main coal colors
	for i in range(coal_nodes.size()):
		var coal = coal_nodes[i]
		if not is_instance_valid(coal):
			continue

		# Bounds check for safety
		if i >= coal_brightness_intensity.size():
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

	# Update coal glow colors (small embers between rocks and fire) - starts after center coals
	var glow_start_index = coal_nodes.size()  # Dynamic based on actual coal count
	for i in range(coal_glow_nodes.size()):
		var coal_glow = coal_glow_nodes[i]
		if not is_instance_valid(coal_glow):
			continue

		# Bounds check for safety
		var array_index = glow_start_index + i
		if array_index >= coal_brightness_intensity.size():
			continue

		# Get this coal glow's properties
		var brightness = coal_brightness_intensity[array_index]
		var color_pref = coal_color_preferences[array_index]

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

	# Get the correct fuel pool for collision radius calculation
	var pool = _get_owner_fuel_pool()
	var current_wood = pool.wood
	var current_bone_embers = pool.bone_embers

	# Calculate current aura radii based on fuel levels (same formula as update_ground_mist)
	# Both can reach same max size (468.75px)
	var heal_aura_radius = 50.0 + (current_wood * 8.375)  # 50-468.75px
	var crit_aura_radius = 50.0 + (current_bone_embers * 4.1875)  # 50-468.75px

	var new_radius: float

	# If no fuel at all, use warmth_radius (150px) for minimal healing range
	# Otherwise, use the larger aura radius (visual auras start at 50px with fuel)
	if current_wood == 0 and current_bone_embers == 0:
		new_radius = warmth_radius  # 150px - for minimal healing with no visual
	else:
		new_radius = max(50.0, max(heal_aura_radius, crit_aura_radius))

	# Update collision shape
	collision.shape.radius = new_radius

func get_fuel_status() -> Dictionary:
	"""Get current fuel levels and buffs for UI"""
	var pool = _get_owner_fuel_pool()
	return {
		"wood_count": pool.wood,
		"bone_ember_count": pool.bone_embers,
		"max_wood": MAX_WOOD,
		"max_bone_embers": MAX_BONE_EMBERS,
		"heal_rate": heal_rate,
		"crit_buff": get_current_crit_buff()
	}

func get_current_heal_rate() -> float:
	"""Calculate current heal rate based on wood count from the fuel pool"""
	# Get the correct fuel pool
	var pool = _get_owner_fuel_pool()
	# Base: 5 HP/s, Max: 25 HP/s (linear scaling)
	var wood_percent = float(pool.wood) / float(MAX_WOOD)
	return 5.0 + (wood_percent * 20.0)  # 5 + (0-20) = 5-25 HP/s

func get_current_crit_buff() -> float:
	"""Calculate current crit chance buff based on bone ember count.
	Uses the local player's group fuel pool."""
	return get_current_crit_buff_for_player()

func create_fuel_ui() -> void:
	"""Create UI panel showing current fuel levels and buffs"""
	var canvas = CanvasLayer.new()
	canvas.name = "FuelUICanvas"
	canvas.layer = 40  # Below hints panel (50) and UI windows (110)
	add_child(canvas)

	# This will be implemented with CampfireFuelUI scene
	# For now, just create the canvas layer
	print("✅ Fuel UI canvas created (waiting for CampfireFuelUI scene)")

# ═══════════════════════════════════════════════════════════════════════════
# UNLIT CAMPFIRE STATE
# ═══════════════════════════════════════════════════════════════════════════

func set_unlit(unlit: bool) -> void:
	"""Set the campfire's unlit state (called when placing)"""
	is_unlit = unlit
	if is_unlit:
		set_unlit_visuals(true)

func set_unlit_visuals(unlit: bool) -> void:
	"""Show/hide fire visuals based on unlit state"""
	# Hide flames
	for flame in flame_nodes:
		if is_instance_valid(flame):
			flame.visible = not unlit

	# Hide coals
	for coal in coal_nodes:
		if is_instance_valid(coal):
			coal.visible = not unlit

	# Hide coal glows
	for glow in coal_glow_nodes:
		if is_instance_valid(glow):
			glow.visible = not unlit

	# Hide fire light
	if fire_light and is_instance_valid(fire_light):
		fire_light.visible = not unlit

	# Hide mist auras
	if heal_mist and is_instance_valid(heal_mist):
		heal_mist.visible = not unlit
	if crit_mist and is_instance_valid(crit_mist):
		crit_mist.visible = not unlit
	if warmth_aura and is_instance_valid(warmth_aura):
		warmth_aura.visible = not unlit

	# Hide particles
	if heal_particles and is_instance_valid(heal_particles):
		heal_particles.emitting = not unlit
	if crit_particles and is_instance_valid(crit_particles):
		crit_particles.emitting = not unlit

	# Stop/start fire audio
	if fire_audio and is_instance_valid(fire_audio):
		if unlit:
			fire_audio.stop()
		else:
			fire_audio.play()

func light_campfire() -> void:
	"""Light an unlit campfire (called when fuel is first added)"""
	if not is_unlit:
		return

	is_unlit = false
	set_unlit_visuals(false)

	# Play ignition sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_fire_fuel_sound"):
		sound_manager.play_fire_fuel_sound(global_position, -8.0, true)

	# Show notification
	var notification_manager = get_node_or_null("/root/NotificationManager")
	if notification_manager and notification_manager.has_method("show_notification"):
		notification_manager.show_notification("Campfire lit!", Color(1.0, 0.7, 0.3))

	print("🔥 Campfire has been lit!")
