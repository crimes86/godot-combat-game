extends Node2D
class_name RuinsSpawnPoint

## Ruins Spawn Point - Endless skeleton spawning with pool-based system
## - Skeletons spawn continuously from the altar
## - Pool fills over time (15-20 seconds per skeleton)
## - Pool capacity: 12-15 skeletons
## - When pool is full, excess become "roamers" that wander further out
## - Players place their own campfire nearby to farm

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

@export var pool_capacity: int = 12  # Maximum skeletons in the pool
@export var spawn_interval: float = 18.0  # Seconds between spawns (pool fill rate)
@export var patrol_inner_radius: float = 375.0  # Inner patrol ring (scaled up 25%)
@export var patrol_outer_radius: float = 500.0  # Outer patrol ring (scaled up 25%)
@export var roamer_extra_distance: float = 300.0  # How much further roamers go

# Guardian configuration
@export var guardian_min_level: int = 7
@export var guardian_max_level: int = 10
@export var guardian_level: int = 0  # If set, overrides min/max

# Aggro settings (tight for body pulling)
@export var aggro_range: float = 120.0
@export var chain_aggro_range: float = 80.0

# Chest spawn configuration
@export var chest_inactivity_time: float = 60.0  # Spawn chest after X seconds of no kills
@export var chest_kill_threshold_min: int = 30  # Min kills to spawn chest
@export var chest_kill_threshold_max: int = 50  # Max kills to spawn chest
@export var chest_random_chance: float = 0.02  # 2% chance per kill to spawn chest

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

var active_skeletons: Array = []  # Currently alive skeletons
var roamer_skeletons: Array = []  # Skeletons that wandered off (overflow)
var spawn_timer: float = 0.0
var skeleton_scene: PackedScene = null

# Chest spawn state
var kill_count: int = 0  # Kills since last chest
var time_since_last_kill: float = 0.0  # Time since last skeleton died
var chest_kill_target: int = 0  # Randomized kill target for current cycle
var active_chest: Node = null  # Currently spawned chest (only one at a time)
var has_player_killed: bool = false  # Has player killed anything this cycle?

# Visual components
var ruins_sprite: Sprite2D = null
var altar_glow: PointLight2D = null

# Day/night light scaling
const BASE_ALTAR_ENERGY: float = 0.6
const MIN_ALTAR_ENERGY: float = 0.1
const MAX_ALTAR_ENERGY: float = 1.5

# References
var player: CharacterBody2D = null
var main_campfire_position: Vector2 = Vector2(2000, 0)

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Load guardian skeleton scene
	skeleton_scene = load("res://scenes/enemies/guardian_skeleton.tscn")
	if not skeleton_scene:
		push_error("Could not load guardian_skeleton.tscn!")
		return

	# Cache altar light reference
	altar_glow = get_node_or_null("RuinsLight")

	# Create visuals
	create_ruins_visual()

	# Initialize chest kill target (randomized)
	chest_kill_target = randi_range(chest_kill_threshold_min, chest_kill_threshold_max)

	# Wait one frame for tree setup
	await get_tree().process_frame

	# Initial pool - spawn a few skeletons immediately
	for i in range(mini(4, pool_capacity)):
		spawn_skeleton()
		await get_tree().create_timer(0.1).timeout  # Stagger spawns

	print("Ruins spawn point initialized at %s (pool: 0/%d, chest target: %d kills)" % [global_position, pool_capacity, chest_kill_target])

func _exit_tree() -> void:
	set_physics_process(false)
	set_process(false)

	# Clean up skeletons
	for skeleton in active_skeletons:
		if is_instance_valid(skeleton):
			skeleton.queue_free()
	active_skeletons.clear()

	for skeleton in roamer_skeletons:
		if is_instance_valid(skeleton):
			skeleton.queue_free()
	roamer_skeletons.clear()

func _physics_process(delta: float) -> void:
	# Find player if needed
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)

	# Update spawn timer
	update_spawn_system(delta)

	# Clean up dead skeletons
	cleanup_dead_skeletons()

	# Update altar glow based on pool fullness and time of day
	update_altar_glow()

	# Update chest inactivity timer
	update_chest_inactivity(delta)

# ═══════════════════════════════════════════════════════════════════════════
# POOL-BASED SPAWN SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func update_spawn_system(delta: float) -> void:
	"""Continuously spawn skeletons to fill the pool"""
	spawn_timer += delta

	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0

		var current_pool_size = active_skeletons.size()

		if current_pool_size < pool_capacity:
			# Pool has room - spawn a regular skeleton
			spawn_skeleton()
		else:
			# Pool is full - spawn a roamer (wanders further out)
			spawn_roamer()

func spawn_skeleton() -> void:
	"""Spawn a skeleton that patrols around the ruins"""
	if not skeleton_scene:
		return

	# Find an evenly distributed patrol spot INSIDE the ruins
	var angle = find_empty_patrol_angle()
	# Spawn between inner and outer radius (inside the ritual circle)
	var spawn_dist = randf_range(patrol_inner_radius * 0.5, patrol_outer_radius * 0.8)
	var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * spawn_dist

	var skeleton = skeleton_scene.instantiate()
	skeleton.global_position = spawn_pos
	skeleton.name = "RuinsSkeleton_%d" % Time.get_ticks_msec()

	# Set level
	if guardian_level > 0:
		skeleton.enemy_level = guardian_level
	else:
		skeleton.enemy_level = randi_range(guardian_min_level, guardian_max_level)

	# Add to world
	get_parent().add_child(skeleton)

	# Wait for initialization
	await get_tree().process_frame

	# Configure AI for patrol inside ruins
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		ai.aggro_range = aggro_range
		# Patrol around the ruins center but stay in their "slice" of the circle
		ai.spawn_position = spawn_pos
		ai.patrol_radius = 100.0  # Small patrol area to stay in their zone

	# Connect death signal
	if skeleton.has_signal("died"):
		skeleton.died.connect(_on_skeleton_died.bind(skeleton))

	# Connect corpse click
	if skeleton.has_signal("corpse_clicked"):
		var game_world = get_parent()
		if game_world and game_world.has_method("_on_corpse_clicked"):
			skeleton.corpse_clicked.connect(game_world._on_corpse_clicked)

	# Register with NetworkEnemyManager
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(skeleton)
		# Sync to NEARBY clients only (interest management)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_for_nearby_clients(network_id, skeleton)

	active_skeletons.append(skeleton)

func spawn_roamer() -> void:
	"""Spawn a skeleton that wanders further from the ruins (overflow)"""
	if not skeleton_scene:
		return

	# Spawn even further out
	var angle = randf() * TAU
	var spawn_distance = patrol_outer_radius + roamer_extra_distance
	var spawn_pos = global_position + Vector2(cos(angle), sin(angle)) * spawn_distance

	var skeleton = skeleton_scene.instantiate()
	skeleton.global_position = spawn_pos
	skeleton.name = "RuinsRoamer_%d" % Time.get_ticks_msec()

	# Set level (roamers are same level)
	if guardian_level > 0:
		skeleton.enemy_level = guardian_level
	else:
		skeleton.enemy_level = randi_range(guardian_min_level, guardian_max_level)

	get_parent().add_child(skeleton)
	await get_tree().process_frame

	# Configure AI - roamers have larger patrol area
	if skeleton.has_node("EnemyAI"):
		var ai = skeleton.get_node("EnemyAI")
		ai.aggro_range = aggro_range
		ai.spawn_position = spawn_pos  # Patrol around their spawn, not ruins
		ai.patrol_radius = 200.0  # Wider roam

	if skeleton.has_signal("died"):
		skeleton.died.connect(_on_roamer_died.bind(skeleton))

	if skeleton.has_signal("corpse_clicked"):
		var game_world = get_parent()
		if game_world and game_world.has_method("_on_corpse_clicked"):
			skeleton.corpse_clicked.connect(game_world._on_corpse_clicked)

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(skeleton)
		# Sync to NEARBY clients only (interest management)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_for_nearby_clients(network_id, skeleton)

	roamer_skeletons.append(skeleton)

func find_empty_patrol_angle() -> float:
	"""Find an angle around the ruins that's away from existing skeletons"""
	if active_skeletons.is_empty():
		return randf() * TAU

	# Collect angles of existing skeletons
	var occupied_angles: Array[float] = []
	for skeleton in active_skeletons:
		if is_instance_valid(skeleton) and not skeleton.get("is_dying") and not skeleton.get("is_corpse"):
			var dir_to_skeleton = skeleton.global_position - global_position
			occupied_angles.append(atan2(dir_to_skeleton.y, dir_to_skeleton.x))

	if occupied_angles.is_empty():
		return randf() * TAU

	# Try to find an angle with maximum distance from occupied angles
	var best_angle = randf() * TAU
	var best_min_distance = 0.0

	# Check 12 candidate angles around the circle
	for i in range(12):
		var candidate = (i * TAU / 12.0) + randf() * 0.3  # Slight randomness

		# Find minimum angular distance to any occupied angle
		var min_dist = TAU
		for occ_angle in occupied_angles:
			var diff = abs(candidate - occ_angle)
			if diff > PI:
				diff = TAU - diff
			min_dist = minf(min_dist, diff)

		if min_dist > best_min_distance:
			best_min_distance = min_dist
			best_angle = candidate

	return best_angle

func cleanup_dead_skeletons() -> void:
	"""Remove dead skeletons from tracking arrays"""
	# Clean active pool
	var to_remove = []
	for skeleton in active_skeletons:
		if not is_instance_valid(skeleton):
			to_remove.append(skeleton)
		elif skeleton.has_method("get") and skeleton.get("is_dying"):
			to_remove.append(skeleton)
		elif skeleton.has_method("get") and skeleton.get("is_corpse"):
			to_remove.append(skeleton)

	for skeleton in to_remove:
		active_skeletons.erase(skeleton)

	# Clean roamers
	to_remove.clear()
	for skeleton in roamer_skeletons:
		if not is_instance_valid(skeleton):
			to_remove.append(skeleton)
		elif skeleton.has_method("get") and skeleton.get("is_dying"):
			to_remove.append(skeleton)
		elif skeleton.has_method("get") and skeleton.get("is_corpse"):
			to_remove.append(skeleton)

	for skeleton in to_remove:
		roamer_skeletons.erase(skeleton)

func _on_skeleton_died(skeleton: Node) -> void:
	"""Called when a pool skeleton dies - pool slot opens up"""
	if skeleton in active_skeletons:
		active_skeletons.erase(skeleton)

	# Track kill for chest spawning
	on_skeleton_killed()

func _on_roamer_died(skeleton: Node) -> void:
	"""Called when a roamer dies"""
	if skeleton in roamer_skeletons:
		roamer_skeletons.erase(skeleton)

	# Track kill for chest spawning
	on_skeleton_killed()

# ═══════════════════════════════════════════════════════════════════════════
# VISUALS
# ═══════════════════════════════════════════════════════════════════════════

# Visual element references for animation
var summoning_rune: Polygon2D = null
var inner_rune: Polygon2D = null
var rune_particles: CPUParticles2D = null
var pillar_sprites: Array = []

func create_ruins_visual() -> void:
	"""Create elaborate ruins scene with stone circle, skulls, bones, and glowing rune"""

	# Container for all visuals
	ruins_sprite = Sprite2D.new()
	ruins_sprite.name = "RuinsContainer"
	ruins_sprite.centered = true
	add_child(ruins_sprite)

	# Layer 1: Ground - dark scorched earth circle
	create_ground_circle()

	# Layer 2: Outer stone circle (rocks arranged in ring)
	create_stone_circle()

	# Layer 3: Summoning rune (glowing, pulsing)
	create_summoning_rune()

	# Layer 4: Bone piles and skulls scattered
	create_bone_decorations()

	# Layer 5: Central skull pile (focal point)
	create_central_altar()

	# Layer 6: Stone pillars as backdrop (the original ruins)
	create_pillar_backdrop()

	# Layer 7: Rising dark particles
	create_dark_particles()

func create_ground_circle() -> void:
	"""Dark scorched ground beneath the summoning circle"""
	var ground = Polygon2D.new()
	ground.name = "ScorchedGround"
	ground.z_index = -10

	# Create irregular circle for natural look - scaled up 25%
	var points = PackedVector2Array()
	var base_radius = 350.0  # Scaled up 25% from 280
	var segments = 48
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position)  # Consistent per-ruins

	for i in range(segments):
		var angle = (i * TAU) / segments
		var radius_variation = rng.randf_range(-30.0, 30.0)  # More variation
		var r = base_radius + radius_variation
		points.append(Vector2(cos(angle), sin(angle)) * r)

	ground.polygon = points
	ground.color = Color(0.12, 0.1, 0.08, 0.9)  # Very dark brown/black
	ruins_sprite.add_child(ground)

	# Add cracked texture overlay (lighter cracks)
	var cracks = Polygon2D.new()
	cracks.name = "GroundCracks"
	cracks.z_index = -9
	cracks.polygon = points
	cracks.color = Color(0.18, 0.15, 0.12, 0.3)
	ruins_sprite.add_child(cracks)

func create_stone_circle() -> void:
	"""Arrange rocks in a natural-looking ritual circle - scaled up 25%"""
	# Use zone1 rock textures (zone-based system in ChunkBasedPropSystem)
	var rock_large_tex = load("res://assets/environment/dreadland/rocks/zone1/rock_large_1.png")
	var rock_medium_tex = load("res://assets/environment/dreadland/rocks/zone1/rock_medium_1.png")
	var rock_small_tex = load("res://assets/environment/dreadland/rocks/zone1/rock_small_1.png")

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position)

	# Large stones - NOT at perfect cardinal directions, organic placement
	# Base radius ~300px (scaled up 25%), with significant random offset
	var num_large = 5 + rng.randi_range(0, 2)  # 5-7 large rocks
	for i in range(num_large):
		if rock_large_tex:
			# Start with even spacing but add significant randomness
			var base_angle = (i * TAU / num_large)
			var angle = base_angle + rng.randf_range(-0.4, 0.4)  # Big angle variation
			var dist = rng.randf_range(270, 330)  # Distance variation

			var rock = Sprite2D.new()
			rock.texture = rock_large_tex
			rock.position = Vector2(cos(angle), sin(angle)) * dist
			rock.position += Vector2(rng.randf_range(-25, 25), rng.randf_range(-25, 25))  # Extra offset
			rock.rotation = rng.randf_range(-0.5, 0.5)
			rock.scale = Vector2(1.0, 1.0) * rng.randf_range(0.85, 1.25)
			rock.z_index = -5
			rock.modulate = Color(0.7, 0.7, 0.75, 1.0)
			ruins_sprite.add_child(rock)

	# Medium stones - fill gaps between large stones, organic placement
	var num_medium = 6 + rng.randi_range(0, 3)  # 6-9 medium rocks
	for i in range(num_medium):
		if rock_medium_tex:
			var base_angle = (i * TAU / num_medium) + (TAU / (num_medium * 2))  # Offset from large
			var angle = base_angle + rng.randf_range(-0.5, 0.5)  # Big angle variation
			var dist = rng.randf_range(220, 290)  # Slightly closer than large

			var rock = Sprite2D.new()
			rock.texture = rock_medium_tex
			rock.position = Vector2(cos(angle), sin(angle)) * dist
			rock.position += Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
			rock.rotation = rng.randf_range(-0.7, 0.7)
			rock.scale = Vector2(0.9, 0.9) * rng.randf_range(0.8, 1.2)
			rock.z_index = -5
			rock.modulate = Color(0.7, 0.7, 0.75, 1.0)
			ruins_sprite.add_child(rock)

	# Small stones - scattered more randomly throughout
	var num_small = 15 + rng.randi_range(0, 5)  # 15-20 small rocks
	for i in range(num_small):
		if rock_small_tex:
			var angle = rng.randf() * TAU  # Completely random angle
			var dist = rng.randf_range(180, 340)  # Wide range

			var rock = Sprite2D.new()
			rock.texture = rock_small_tex
			rock.position = Vector2(cos(angle), sin(angle)) * dist
			rock.position += Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			rock.rotation = rng.randf_range(-PI, PI)
			rock.scale = Vector2(0.8, 0.8) * rng.randf_range(0.6, 1.2)
			rock.z_index = -6
			rock.modulate = Color(0.65, 0.65, 0.7, 1.0)
			ruins_sprite.add_child(rock)

func create_summoning_rune() -> void:
	"""Glowing magical rune circle on the ground - larger and more spread out"""
	# Outer rune circle - increased size
	summoning_rune = Polygon2D.new()
	summoning_rune.name = "SummoningRune"
	summoning_rune.z_index = -8

	var outer_points = PackedVector2Array()
	var outer_radius = 150.0  # Increased from 100
	var inner_radius = 130.0  # Increased from 85
	var segments = 64

	# Create ring shape
	for i in range(segments):
		var angle = (i * TAU) / segments
		outer_points.append(Vector2(cos(angle), sin(angle)) * outer_radius)
	for i in range(segments - 1, -1, -1):
		var angle = (i * TAU) / segments
		outer_points.append(Vector2(cos(angle), sin(angle)) * inner_radius)

	summoning_rune.polygon = outer_points
	summoning_rune.color = Color(0.2, 0.8, 0.5, 0.4)  # Ghostly green
	ruins_sprite.add_child(summoning_rune)

	# Inner rune pattern (hexagram) - larger
	inner_rune = Polygon2D.new()
	inner_rune.name = "InnerRune"
	inner_rune.z_index = -7

	# Create hexagram (two overlapping triangles)
	var hex_points = PackedVector2Array()
	var hex_radius = 110.0  # Increased from 70

	# First triangle
	for i in range(3):
		var angle = (i * TAU / 3) - PI/2
		hex_points.append(Vector2(cos(angle), sin(angle)) * hex_radius)

	inner_rune.polygon = hex_points
	inner_rune.color = Color(0.3, 1.0, 0.6, 0.3)  # Ghostly green
	ruins_sprite.add_child(inner_rune)

	# Second triangle (rotated)
	var inner_rune2 = Polygon2D.new()
	inner_rune2.name = "InnerRune2"
	inner_rune2.z_index = -7

	var hex_points2 = PackedVector2Array()
	for i in range(3):
		var angle = (i * TAU / 3) + PI/2
		hex_points2.append(Vector2(cos(angle), sin(angle)) * hex_radius)

	inner_rune2.polygon = hex_points2
	inner_rune2.color = Color(0.3, 1.0, 0.6, 0.3)  # Ghostly green
	ruins_sprite.add_child(inner_rune2)

	# Central circle - larger
	var center_circle = Polygon2D.new()
	center_circle.name = "CenterCircle"
	center_circle.z_index = -7

	var center_points = PackedVector2Array()
	for i in range(32):
		var angle = (i * TAU) / 32
		center_points.append(Vector2(cos(angle), sin(angle)) * 40.0)  # Increased from 25

	center_circle.polygon = center_points
	center_circle.color = Color(0.4, 1.0, 0.7, 0.5)  # Ghostly green center
	ruins_sprite.add_child(center_circle)

func create_bone_decorations() -> void:
	"""Scatter bones and skulls around the circle - spread out more"""
	var skull_tex = load("res://assets/environment/dreadland/skull.png")
	var bones_tex = load("res://assets/environment/dreadland/bones.png")

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position) + 1

	# Skulls around the perimeter - pushed out to 100-150px
	for i in range(6):
		if skull_tex:
			var angle = (i * TAU / 6) + rng.randf_range(-0.3, 0.3)
			var dist = rng.randf_range(100, 150)  # Increased from 60-90
			var skull = Sprite2D.new()
			skull.texture = skull_tex
			skull.position = Vector2(cos(angle), sin(angle)) * dist
			skull.rotation = rng.randf_range(-0.5, 0.5)
			skull.scale = Vector2(1.3, 1.3) * rng.randf_range(0.8, 1.2)
			skull.z_index = -3
			skull.modulate = Color(0.85, 0.85, 0.8, 1.0)
			ruins_sprite.add_child(skull)

	# Bone piles scattered - spread out to 80-180px
	for i in range(10):  # More bones
		if bones_tex:
			var angle = rng.randf() * TAU
			var dist = rng.randf_range(80, 180)  # Increased from 40-110
			var bones = Sprite2D.new()
			bones.texture = bones_tex
			bones.position = Vector2(cos(angle), sin(angle)) * dist
			bones.rotation = rng.randf_range(-PI, PI)
			bones.scale = Vector2(1.1, 1.1) * rng.randf_range(0.8, 1.4)
			bones.z_index = -4
			bones.modulate = Color(0.8, 0.8, 0.75, 0.9)
			ruins_sprite.add_child(bones)

func create_central_altar() -> void:
	"""Central skull pile - the focal point where skeletons rise"""
	var skull_tex = load("res://assets/environment/dreadland/skull.png")
	if not skull_tex:
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position) + 2

	# Pile of skulls in center (3-4 overlapping)
	var skull_offsets = [
		Vector2(0, 5),
		Vector2(-12, -5),
		Vector2(12, -3),
		Vector2(0, -12),
	]

	for i in range(skull_offsets.size()):
		var skull = Sprite2D.new()
		skull.texture = skull_tex
		skull.position = skull_offsets[i] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		skull.rotation = rng.randf_range(-0.4, 0.4)
		skull.scale = Vector2(1.5, 1.5) * rng.randf_range(0.9, 1.1)
		skull.z_index = -2 + i  # Stack them
		skull.modulate = Color(0.9, 0.88, 0.8, 1.0)
		ruins_sprite.add_child(skull)

func create_pillar_backdrop() -> void:
	"""Add the original ruins pillars as backdrop elements - scaled up 25%"""
	var ruins_tex = load("res://assets/environment/dreadland/ruins.png")
	if not ruins_tex:
		return

	# Main pillars behind the circle - scaled up 25%
	var pillars = Sprite2D.new()
	pillars.texture = ruins_tex
	pillars.position = Vector2(0, -100)  # Pushed back (north) - scaled from -80
	pillars.scale = Vector2(1.0, 1.0)  # Scaled up 25% from 0.8
	pillars.z_index = -1  # Behind skulls but in front of ground
	pillars.modulate = Color(0.6, 0.6, 0.65, 0.9)  # Darker, slightly desaturated
	ruins_sprite.add_child(pillars)
	pillar_sprites.append(pillars)

func create_dark_particles() -> void:
	"""Rising dark/green particles from the summoning circle - scaled up 25%"""
	rune_particles = CPUParticles2D.new()
	rune_particles.name = "RuneParticles"
	rune_particles.z_index = 5
	rune_particles.emitting = true
	rune_particles.amount = 20
	rune_particles.lifetime = 3.0
	rune_particles.speed_scale = 0.8

	# Emission shape - circle (scaled up 25%)
	rune_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rune_particles.emission_sphere_radius = 75.0  # Scaled up from 60

	# Movement - rise upward
	rune_particles.direction = Vector2(0, -1)
	rune_particles.spread = 25.0
	rune_particles.initial_velocity_min = 15.0
	rune_particles.initial_velocity_max = 30.0
	rune_particles.gravity = Vector2(0, -5)  # Float upward

	# Appearance
	rune_particles.scale_amount_min = 2.0
	rune_particles.scale_amount_max = 5.0

	# Color - ghostly green fading out
	var gradient = Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(0.2, 0.9, 0.5, 0.6))
	gradient.add_point(0.5, Color(0.3, 0.8, 0.5, 0.4))
	gradient.add_point(1.0, Color(0.2, 0.6, 0.4, 0.0))
	rune_particles.color_ramp = gradient

	ruins_sprite.add_child(rune_particles)

func update_altar_glow() -> void:
	"""Scale altar glow and rune visuals based on pool fullness and time of day"""
	# Pool fullness affects intensity
	var pool_percent = float(active_skeletons.size()) / float(pool_capacity)

	# Update the PointLight2D if it exists
	if altar_glow and is_instance_valid(altar_glow):
		# Base intensity from time of day
		var time_brightness = 1.0
		if TimeManager and TimeManager.canvas_modulate:
			time_brightness = TimeManager.get_brightness()

		var day_factor = inverse_lerp(0.51, 0.99, time_brightness)
		day_factor = clamp(day_factor, 0.0, 1.0)
		var base_energy = lerp(MAX_ALTAR_ENERGY, MIN_ALTAR_ENERGY, day_factor)

		# Boost glow based on pool fullness (danger indicator)
		var danger_boost = lerp(0.0, 0.5, pool_percent)  # Up to 50% brighter when full

		altar_glow.energy = base_energy + danger_boost

		# Scale texture size based on pool fullness
		var base_scale = lerp(3.0, 4.5, 1.0 - day_factor)  # Bigger at night
		var pool_scale_boost = lerp(0.0, 1.0, pool_percent)  # Bigger when full
		altar_glow.texture_scale = base_scale + pool_scale_boost

	# Pulse the summoning rune based on pool status and time
	if summoning_rune and is_instance_valid(summoning_rune):
		var time = Time.get_ticks_msec() / 1000.0
		var pulse = (sin(time * 2.0) + 1.0) / 2.0  # 0 to 1 pulse

		# Base alpha increases with pool fullness
		var base_alpha = lerp(0.2, 0.5, pool_percent)
		var pulse_alpha = lerp(0.0, 0.3, pool_percent) * pulse

		summoning_rune.color = Color(0.2, 0.8, 0.5, base_alpha + pulse_alpha)

	# Pulse inner rune as well
	if inner_rune and is_instance_valid(inner_rune):
		var time = Time.get_ticks_msec() / 1000.0
		var pulse = (sin(time * 3.0 + 0.5) + 1.0) / 2.0  # Offset pulse

		var base_alpha = lerp(0.15, 0.4, pool_percent)
		var pulse_alpha = lerp(0.0, 0.25, pool_percent) * pulse

		inner_rune.color = Color(0.3, 1.0, 0.6, base_alpha + pulse_alpha)

	# Particle intensity based on pool
	if rune_particles and is_instance_valid(rune_particles):
		# More particles when pool is fuller
		var particle_amount = int(lerp(10, 30, pool_percent))
		if rune_particles.amount != particle_amount:
			rune_particles.amount = particle_amount

# ═══════════════════════════════════════════════════════════════════════════
# CHEST SPAWN SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func on_skeleton_killed() -> void:
	"""Track a skeleton kill and check chest spawn conditions"""
	kill_count += 1
	time_since_last_kill = 0.0
	has_player_killed = true

	# Don't spawn chest if one already exists
	if active_chest and is_instance_valid(active_chest):
		return

	var should_spawn = false
	var spawn_reason = ""

	# Check kill threshold
	if kill_count >= chest_kill_target:
		should_spawn = true
		spawn_reason = "kill threshold reached (%d/%d)" % [kill_count, chest_kill_target]

	# Random chance per kill (small)
	elif randf() < chest_random_chance:
		should_spawn = true
		spawn_reason = "random drop (%.1f%% chance)" % (chest_random_chance * 100)

	if should_spawn:
		spawn_ruins_chest(spawn_reason)

func update_chest_inactivity(delta: float) -> void:
	"""Check if pool has been inactive long enough to spawn chest"""
	if not has_player_killed:
		return  # Don't spawn chest if player hasn't killed anything yet

	# Don't update if there's already a chest
	if active_chest and is_instance_valid(active_chest):
		return

	time_since_last_kill += delta

	# Check if pool is full AND inactive for X seconds (incentive to clear)
	if active_skeletons.size() >= pool_capacity and time_since_last_kill >= chest_inactivity_time:
		spawn_ruins_chest("inactivity timer (%.0fs with full pool)" % chest_inactivity_time)

func spawn_ruins_chest(reason: String) -> void:
	"""Spawn a treasure chest in the center of the ruins"""
	print("💎 Spawning ruins chest - %s" % reason)

	# Reset kill tracking
	kill_count = 0
	time_since_last_kill = 0.0
	chest_kill_target = randi_range(chest_kill_threshold_min, chest_kill_threshold_max)

	# Create chest at center of ruins
	var chest = TreasureChest.new()
	chest.global_position = global_position
	chest.name = "RuinsChest_%d" % Time.get_ticks_msec()

	# Override the loot table with ruins-specific loot
	# We'll set this after adding to tree
	get_parent().add_child(chest)

	# Wait one frame then configure loot
	await get_tree().process_frame

	# Configure ruins-specific loot: gold + ruins key
	chest.generated_loot = generate_ruins_chest_loot()

	active_chest = chest

	# Connect to know when chest is opened/removed
	if chest.has_signal("tree_exiting"):
		chest.tree_exiting.connect(_on_chest_removed)

	print("💎 Ruins chest spawned at %s (next target: %d kills)" % [global_position, chest_kill_target])

func generate_ruins_chest_loot() -> Array:
	"""Generate ruins-specific loot: gold pile + ruins key"""
	var loot = []

	# Gold pile (50-150 gold based on guardian levels)
	var avg_level = (guardian_min_level + guardian_max_level) / 2.0
	var base_gold = int(50 + avg_level * 10)
	var gold_amount = randi_range(base_gold, int(base_gold * 1.5))

	loot.append({
		"name": "Gold",
		"description": "A pile of gold coins",
		"value": gold_amount,
		"type": "currency",
		"rarity": "Common",
		"stackable": true,
		"quantity": gold_amount
	})

	# Ruins Key (always drops)
	loot.append({
		"id": "ruins_key",
		"name": "Ruins Key",
		"description": "An ancient key found in the ruins. Opens something special...",
		"value": 0,
		"type": "key",
		"rarity": "Rare",
		"stackable": true,
		"max_stack": 99
	})

	# Small chance for bonus item (armor piece)
	if randf() < 0.15:  # 15% chance for bonus armor
		var armor_options = [
			{
				"id": "copper_plate_greaves",
				"name": "Copper Plate Greaves",
				"description": "Tier 1 copper-plated leg armor. Solid leg protection.",
				"slot": "legs",
				"defense": 8,
				"type": "armor",
				"value": 0,
				"rarity": "Common",
				"sprite_name": "copper_plate",
				"stackable": false
			},
			{
				"id": "copper_plate_helmet",
				"name": "Copper Plate Helmet",
				"description": "Tier 1 copper-plated helmet. Essential head protection.",
				"slot": "head",
				"defense": 7,
				"type": "armor",
				"value": 0,
				"rarity": "Common",
				"sprite_name": "copper_plate",
				"stackable": false
			}
		]
		loot.append(armor_options[randi() % armor_options.size()])

	return loot

func _on_chest_removed() -> void:
	"""Called when the chest is removed from tree"""
	active_chest = null

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func get_pool_status() -> Dictionary:
	"""Get current pool information for UI or debugging"""
	return {
		"active_count": active_skeletons.size(),
		"roamer_count": roamer_skeletons.size(),
		"pool_capacity": pool_capacity,
		"pool_percent": float(active_skeletons.size()) / float(pool_capacity),
		"is_full": active_skeletons.size() >= pool_capacity,
		"kill_count": kill_count,
		"chest_target": chest_kill_target,
		"has_chest": active_chest != null and is_instance_valid(active_chest)
	}

func get_nearest_skeleton_distance() -> float:
	"""Get distance to nearest skeleton (for UI indicators)"""
	if not player or not is_instance_valid(player):
		return INF

	var min_distance = INF
	for skeleton in active_skeletons:
		if is_instance_valid(skeleton) and not skeleton.is_dying:
			var dist = skeleton.global_position.distance_to(player.global_position)
			min_distance = minf(min_distance, dist)

	for skeleton in roamer_skeletons:
		if is_instance_valid(skeleton) and not skeleton.is_dying:
			var dist = skeleton.global_position.distance_to(player.global_position)
			min_distance = minf(min_distance, dist)

	return min_distance
