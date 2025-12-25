extends Node
class_name EnemyAI

## 🤖 MMO-Style Enemy AI
## - Enemies patrol around spawn point (non-aggro)
## - Player can walk right up to them safely
## - Only engages when player attacks first
## - Then: chase, attack, retreat, deal damage
## - On death: respawn and return to patrol

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Patrol (default behavior)
@export var patrol_speed: float = 50.0
@export var patrol_radius: float = 100.0
@export var patrol_pause_min: float = 0.5
@export var patrol_pause_max: float = 2.0

## Aggro System (NEW)
@export var aggro_range: float = 150.0  # Distance to auto-aggro player (150 patrol, 120 guardians)
@export var leash_distance: float = 3000.0  # Max distance from spawn before returning (large for kiting to campfire)
@export var chain_aggro_range: float = 100.0  # Nearby allies aggro too (creates trains!)

## Combat (triggered by player attack OR aggro)
@export var combat_speed: float = 185.0  # Close to player speed (200) - allows skill-based kiting but not infinite
@export var attack_range: float = 60.0
@export var attack_cooldown: float = 1.5
@export var attack_damage: float = 10.0
@export var disengage_distance: float = 2500.0  # Return to patrol if player too far (large for kiting)

## Behavior
@export var retreat_chance: float = 0.25  # 25% chance on hit
@export var retreat_duration: float = 0.8

## Avoidance (stop and pick new target when blocked)
@export var separation_radius: float = 60.0  # Distance to detect blocking enemies (increased)
@export var separation_force_strength: float = 100.0  # How strongly skeletons push apart

# ═══════════════════════════════════════════════════════════════════════════
# STATE MACHINE
# ═══════════════════════════════════════════════════════════════════════════

enum State {
	PATROLLING,   # Default: peaceful wandering
	COMBAT,       # Engaged: chasing player
	ATTACKING,    # In range: striking player
	RETREATING,   # Tactical: backing away
	UNSTUCKING,   # Recovery: walking backward to get unstuck
	CAMPFIRE_ATTRACTED,  # Heading to campfire to investigate
	RETURNING,    # Walking back to spawn after leashing (can re-aggro)
}

var current_state: State = State.PATROLLING
var state_timer: float = 0.0

# ═══════════════════════════════════════════════════════════════════════════
# REFERENCES & STATE
# ═══════════════════════════════════════════════════════════════════════════

var enemy: CharacterBody2D = null
var player: CharacterBody2D = null
var sprite: CanvasItem = null  # ✨ Changed from Sprite2D to support AnimatedSprite2D too
var anim_sprite: AnimatedSprite2D = null  # Cached AnimatedSprite2D reference
var health_bar_node: Control = null  # Cached HealthBar reference
var debug_label: Label = null

# Cached autoload references (set once in _ready)
var _sound_manager: Node = null
var _network_enemy_mgr: Node = null

# Patrol state
var spawn_position: Vector2 = Vector2.ZERO
var original_spawn_position: Vector2 = Vector2.ZERO  # True spawn point (never changes)
var spawn_chunk: String = ""  # Chunk where enemy spawned (for chunk-based leashing)
var patrol_target: Vector2 = Vector2.ZERO
var is_paused: bool = false
var pause_timer: float = 0.0

# Combat state
var is_in_combat: bool = false  # CRITICAL: Only true after player attacks
var attack_timer: float = 0.0
var retreat_direction: Vector2 = Vector2.ZERO
var leash_cooldown_timer: float = 0.0  # Prevent immediate re-aggro after leashing
const LEASH_COOLDOWN_DURATION: float = 3.0  # 3 second cooldown after leashing

# REMOVED: Deterred state variables - players can now fight at campfire with healing

# Stuck detection
var last_position: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var stuck_check_interval: float = 2.0  # Check every 2 seconds
var last_velocity_direction: Vector2 = Vector2.ZERO  # Track velocity direction for sliding detection
var same_direction_timer: float = 0.0  # Track how long we've been sliding same direction

# Attack concurrency prevention
var is_performing_attack: bool = false
var stuck_distance_threshold: float = 5.0  # If moved less than 5px in 2 seconds while walking, considered stuck

# Unstuck behavior (about-face mechanics)
var unstuck_state_before: State = State.PATROLLING  # State to return to after unstuck
var unstuck_original_target: Vector2 = Vector2.ZERO  # Where we were trying to go
var unstuck_direction: Vector2 = Vector2.ZERO  # Direction to walk while unstucking
var unstuck_steps_taken: int = 0  # How many steps we've taken
var unstuck_max_steps: int = 8  # Number of steps to take backward (configurable)

# Sound spam prevention (static across all enemies)
static var last_attack_sound_time: float = 0.0
static var attack_sound_cooldown: float = 0.4  # Min 0.4s between attack sounds (prevents audio stacking)

# Aggro sound spam prevention (per-enemy, not static)
var last_aggro_sound_time: float = 0.0

# Campfire skeleton behavior
var campfire_target: Node2D = null  # The campfire this skeleton is attracted to
var campfire_patrol_timer: float = 0.0  # Time spent patrolling near campfire
const CAMPFIRE_DESPAWN_TIME: float = 600.0  # 10 minutes before despawning
var is_campfire_skeleton: bool = false  # True if spawned by campfire fuel
var aggro_sound_cooldown: float = 3.0  # Min 3.0s between aggro laughs per enemy

# Footstep tracking
var last_footstep_frame: int = -1  # Track last frame that played footstep
var last_facing_direction: String = ""  # Track last direction for idle (random on spawn)

# Performance: Throttle AI updates based on distance from player
var ai_update_timer: float = 0.0
var ai_update_interval: float = 0.1  # Default: update AI every 0.1s instead of 60 FPS
var debug_update_timer: float = 0.0
var cached_player: CharacterBody2D = null  # Cache player reference
var cached_players: Array = []  # Cache all player references (for multiplayer)
var cached_enemies: Array = []  # Cache nearby enemies for separation calculations
var cache_refresh_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 0.5  # Refresh caches every 0.5 seconds

# LOD (Level of Detail) system
enum LODLevel { FULL, MEDIUM, LOW, PLACEHOLDER, CULLED }
var current_lod: LODLevel = LODLevel.FULL
var lod_update_timer: float = 0.0
var lod_update_interval: float = 1.0  # Check LOD once per second

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	enemy = get_parent() as CharacterBody2D
	if not enemy:
		push_error("EnemyAI must be child of CharacterBody2D!")
		return

	# Cache autoload references (safe to do immediately)
	_sound_manager = get_node_or_null("/root/SoundManager")
	_network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")

	# Wait one frame for node to be fully in scene tree with correct global_position
	# AND for Enemy._ready() to finish converting Sprite2D to AnimatedSprite2D
	await get_tree().process_frame

	# Get sprite references AFTER await (Enemy._ready() has now completed setup)
	# Note: anim_sprite may still be null here if Enemy._ready() hasn't converted Sprite2D yet
	# The lazy re-fetch in update_enemy_animation() handles this case
	if enemy.has_node("Sprite"):
		sprite = enemy.get_node("Sprite")
		anim_sprite = sprite as AnimatedSprite2D
	elif enemy.has_node("Sprite2D"):
		sprite = enemy.get_node("Sprite2D")

	# Cache HealthBar reference
	health_bar_node = enemy.get_node_or_null("HealthBar")

	# Now store spawn position using global_position (which is now valid after await)
	spawn_position = enemy.global_position
	original_spawn_position = enemy.global_position  # Save the TRUE spawn point
	spawn_chunk = get_chunk_key(enemy.global_position)  # Save spawn chunk for leashing
	last_position = enemy.global_position  # Initialize stuck detection

	# Set initial patrol_target to spawn position
	patrol_target = spawn_position

	# Connect to damage signal to detect player attacks
	if enemy.has_signal("damage_taken"):
		enemy.damage_taken.connect(_on_enemy_damaged)

	# Fixed speed (no level scaling - equipment may add bonuses later)
	# Note: combat_speed (185) and patrol_speed (50) use @export defaults

	# Guardian skeleton combat buffs - faster attacks, slightly faster movement
	var is_guardian = enemy.get_meta("is_guardian", false)
	if is_guardian:
		attack_cooldown *= 0.75  # 25% faster attacks (1.5s -> 1.125s)
		combat_speed *= 1.15  # 15% faster chase speed - harder to kite

	# West→East progression: Scale combat abilities based on enemy level
	# Higher level enemies are faster and attack more frequently
	var enemy_level = enemy.enemy_level if enemy.get("enemy_level") != null else 1
	if enemy_level >= 10:
		# Endgame tier (L10+): +30% attack speed, +20% move speed
		attack_cooldown *= 0.7
		combat_speed *= 1.2
	elif enemy_level >= 7:
		# Elite tier (L7-9): +20% attack speed, +10% move speed
		attack_cooldown *= 0.8
		combat_speed *= 1.1
	elif enemy_level >= 4:
		# Armored tier (L4-6): +10% attack speed
		attack_cooldown *= 0.9
	# L1-3: No scaling (base stats)

	# Check if this is a campfire-spawned skeleton (has meta data from Campfire.gd)
	if enemy.has_meta("is_campfire_skeleton") and enemy.get_meta("is_campfire_skeleton"):
		is_campfire_skeleton = true
		campfire_target = enemy.get_meta("campfire_target") if enemy.has_meta("campfire_target") else null
		campfire_patrol_timer = 0.0

		# Start in CAMPFIRE_ATTRACTED state - head toward the fire
		if campfire_target and is_instance_valid(campfire_target):
			change_state(State.CAMPFIRE_ATTRACTED)
		else:
			# No valid campfire target, just patrol normally
			pick_new_patrol_target()
			change_state(State.PATROLLING)
	else:
		# Normal skeleton - start patrolling
		pick_new_patrol_target()
		change_state(State.PATROLLING)

	# Mark as initialized - physics can now run
	_initialized = true

	# Debug label disabled - was causing visual artifacts
	# create_debug_label()

# ═══════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════

var _initialized: bool = false

func _refresh_caches() -> void:
	"""Refresh cached player and enemy lists (called periodically, not every frame)"""
	cached_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	cached_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

func _physics_process(delta: float) -> void:
	if not enemy or not is_instance_valid(enemy):
		return

	# Don't process physics until fully initialized
	if not _initialized:
		enemy.velocity = Vector2.ZERO
		return

	# FIX: Cap velocity to prevent runaway speeds from collision sliding
	var max_speed = 150.0
	if enemy.velocity.length() > max_speed:
		enemy.velocity = enemy.velocity.normalized() * max_speed

	# Only stop movement if THIS enemy is dying
	# Crit window: enemy should keep fighting while player shoots weakpoints!
	if enemy.has_method("get"):
		if enemy.get("is_dying"):
			enemy.velocity = Vector2.ZERO
			enemy.move_and_slide()
			return

	# Update timers
	state_timer += delta
	attack_timer = max(0, attack_timer - delta)
	leash_cooldown_timer = max(0, leash_cooldown_timer - delta)
	ai_update_timer += delta
	cache_refresh_timer += delta

	# Periodically refresh player/enemy caches (not every frame)
	if cache_refresh_timer >= CACHE_REFRESH_INTERVAL:
		cache_refresh_timer = 0.0
		_refresh_caches()

	# Cache player reference (look up once, reuse)
	if not cached_player or not is_instance_valid(cached_player):
		if cached_players.size() > 0:
			cached_player = cached_players[0]
		else:
			cached_player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		player = cached_player

	# Calculate distance-based update rate (using squared distance to avoid sqrt)
	var distance_sq_to_player = 999999.0 * 999999.0
	if cached_player and is_instance_valid(cached_player):
		distance_sq_to_player = enemy.global_position.distance_squared_to(cached_player.global_position)

	# ═══════════════════════════════════════════════════════════════
	# LOD DISABLED - Simplified for debugging
	# Enemies always run full AI, visibility controlled by Enemy.gd only
	# ═══════════════════════════════════════════════════════════════
	# Adjust AI update rate based on distance (performance only, no visibility changes)
	const NEAR_DISTANCE_SQ = 500.0 * 500.0  # 250000
	const MED_DISTANCE_SQ = 1500.0 * 1500.0  # 2250000
	if is_in_combat or distance_sq_to_player < NEAR_DISTANCE_SQ:
		ai_update_interval = 0.05  # 20 FPS when near or in combat
	elif distance_sq_to_player < MED_DISTANCE_SQ:
		ai_update_interval = 0.15  # 6-7 FPS at medium distance
	else:
		ai_update_interval = 0.3   # 3 FPS when far away

	# ═══════════════════════════════════════════════════════════════
	# STUCK DETECTION (runs every frame, independent of AI throttling)
	# ═══════════════════════════════════════════════════════════════
	# Check for stuck (works in PATROLLING and COMBAT, but not while already unstucking)
	if current_state != State.UNSTUCKING and current_state != State.ATTACKING and current_state != State.RETREATING:
		stuck_timer += delta

		# Detect Y-axis sliding (moving but only in one direction, not toward target)
		if enemy.velocity.length() > 10:
			var current_dir = enemy.velocity.normalized()
			# Check if we're sliding perpendicular to our intended direction
			if current_state == State.PATROLLING and patrol_target != Vector2.ZERO:
				var intended_dir = (patrol_target - enemy.global_position).normalized()
				var dot = current_dir.dot(intended_dir)
				# If we're moving mostly perpendicular to target (sliding), count it
				if abs(dot) < 0.3:
					same_direction_timer += delta
					if same_direction_timer > 1.5:  # Sliding for 1.5 seconds
						# Pick a new target to break out of the slide
						pick_new_patrol_target()
						same_direction_timer = 0.0
				else:
					same_direction_timer = 0.0
			last_velocity_direction = current_dir
		else:
			same_direction_timer = 0.0

		if stuck_timer >= stuck_check_interval:
			var distance_moved = enemy.global_position.distance_to(last_position)

			# Lazy re-fetch anim_sprite if needed
			if not anim_sprite and enemy and is_instance_valid(enemy) and enemy.has_node("Sprite"):
				sprite = enemy.get_node("Sprite")
				anim_sprite = sprite as AnimatedSprite2D

			# Check if enemy is in walking animation state (trying to move)
			var is_walking = false
			if anim_sprite and anim_sprite.animation:
				is_walking = anim_sprite.animation.begins_with("walk_")

			# If walking animation is playing but position hasn't changed = STUCK
			if distance_moved < stuck_distance_threshold and is_walking:
				# We're stuck! Start the about-face unstuck maneuver
				unstuck_state_before = current_state
				if current_state == State.PATROLLING:
					unstuck_original_target = patrol_target
				elif current_state == State.COMBAT and player:
					unstuck_original_target = player.global_position

				# Calculate about-face direction (opposite of current velocity, with random Y offset)
				var backward_direction = -enemy.velocity.normalized()
				var y_offset = randf_range(-0.5, 0.5)
				unstuck_direction = (backward_direction + Vector2(0, y_offset)).normalized()
				unstuck_steps_taken = 0
				change_state(State.UNSTUCKING)
			last_position = enemy.global_position
			stuck_timer = 0.0
	else:
		# Reset stuck timer when in states that shouldn't check for stuck
		stuck_timer = 0.0
		same_direction_timer = 0.0
		last_position = enemy.global_position

	# ═══════════════════════════════════════════════════════════════
	# AI THROTTLING (run AI logic at reduced rate based on distance)
	# ═══════════════════════════════════════════════════════════════
	# Only run AI logic at throttled rate (not every frame!)
	var should_update_ai = ai_update_timer >= ai_update_interval
	if not should_update_ai:
		# Still need to apply movement every frame for smooth motion
		enemy.move_and_slide()
		return

	ai_update_timer = 0.0  # Reset timer
	player = cached_player  # Update player reference

	# Debug label disabled - was causing visual artifacts
	# debug_update_timer += delta
	# if debug_label and player and debug_update_timer >= 0.5:
	# 	debug_label.visible = player.get("debug_mode") == true
	# 	if debug_label.visible:
	# 		update_debug_label_position()
	# 	debug_update_timer = 0.0

	# State machine
	match current_state:
		State.PATROLLING:
			process_patrolling(delta)
		State.COMBAT:
			process_combat(delta)
		State.ATTACKING:
			process_attacking(delta)
		State.RETREATING:
			process_retreating(delta)
		State.UNSTUCKING:
			process_unstucking(delta)
		State.CAMPFIRE_ATTRACTED:
			process_campfire_attracted(delta)
		State.RETURNING:
			process_returning(delta)

# ═══════════════════════════════════════════════════════════════════════════
# PATROLLING STATE (Default - Non-Aggro)
# ═══════════════════════════════════════════════════════════════════════════

func process_patrolling(delta: float) -> void:
	# Campfire skeletons: track despawn timer even while patrolling
	if is_campfire_skeleton:
		campfire_patrol_timer += delta
		if campfire_patrol_timer >= CAMPFIRE_DESPAWN_TIME:
			despawn_campfire_skeleton()
			return

	# If player attacked us, enter combat (but not if they're dead)
	if is_in_combat and player:
		if player.get("is_dead"):
			# Player died while we were in combat - disengage
			disengage()
			return
		change_state(State.COMBAT)
		return

	# In multiplayer, find the nearest ALIVE player for aggro checks
	var aggro_target = player
	if multiplayer.has_multiplayer_peer():
		var nearest_distance: float = INF
		for p in cached_players:
			if is_instance_valid(p) and not p.get("is_dead"):
				var dist = enemy.global_position.distance_to(p.global_position)
				if dist < nearest_distance:
					nearest_distance = dist
					aggro_target = p

	# Check for player in aggro range (auto-aggro) - but only if not on leash cooldown and player is alive
	if aggro_target and is_instance_valid(aggro_target) and not aggro_target.get("is_dead") and leash_cooldown_timer <= 0:
		var distance_to_player = enemy.global_position.distance_to(aggro_target.global_position)
		if distance_to_player <= aggro_range:
			# AGGRO!
			player = aggro_target  # Update player reference to the one who triggered aggro
			trigger_aggro()
			return

	# Calculate separation force from nearby enemies (always check, even when paused)
	var separation_force = get_separation_force()

	# Handle patrol pause
	if is_paused:
		pause_timer -= delta
		if pause_timer <= 0:
			is_paused = false
			pick_new_patrol_target()

		# Even when paused, apply separation if too close to another skeleton
		if separation_force.length() > 0.3:
			enemy.velocity = separation_force * separation_force_strength
			update_enemy_animation(separation_force)
		else:
			enemy.velocity = Vector2.ZERO
			update_enemy_animation(Vector2.ZERO)

		enemy.move_and_slide()
		return

	# Move toward patrol target
	var distance_to_target = enemy.global_position.distance_to(patrol_target)

	if distance_to_target < 10.0:
		# Reached target - pause
		is_paused = true
		pause_timer = randf_range(patrol_pause_min, patrol_pause_max)
		# Still apply separation even when reaching target
		if separation_force.length() > 0.3:
			enemy.velocity = separation_force * separation_force_strength
			update_enemy_animation(separation_force)
		else:
			enemy.velocity = Vector2.ZERO
			update_enemy_animation(Vector2.ZERO)
	else:
		# Check if another enemy is blocking our path
		if is_path_blocked_by_enemy():
			# Pick a new patrol target instead of pushing through
			pick_new_patrol_target()
			# Apply separation force while picking new target
			if separation_force.length() > 0.1:
				enemy.velocity = separation_force * separation_force_strength
				update_enemy_animation(separation_force)
			else:
				enemy.velocity = Vector2.ZERO
				update_enemy_animation(Vector2.ZERO)
		# Check if path would cross lava
		elif is_path_crossing_lava(enemy.global_position, patrol_target):
			# Pick a new patrol target to avoid lava
			pick_new_patrol_target()
			enemy.velocity = separation_force * separation_force_strength
			update_enemy_animation(separation_force if separation_force.length() > 0.1 else Vector2.ZERO)
		else:
			# Move toward target with separation - separation takes priority when close
			var direction = (patrol_target - enemy.global_position).normalized()
			if separation_force.length() > 0.5:
				# Strong separation needed - prioritize getting apart
				var combined_direction = (direction * 0.3 + separation_force * 0.7).normalized()
				enemy.velocity = combined_direction * patrol_speed
				update_enemy_animation(combined_direction)
			else:
				# Normal patrolling with mild separation
				var combined_direction = (direction + separation_force * 0.3).normalized()
				enemy.velocity = combined_direction * patrol_speed
				update_enemy_animation(combined_direction)

	enemy.move_and_slide()

func pick_new_patrol_target() -> void:
	"""Pick a random point within patrol_radius of spawn, avoiding lava pools and other enemies"""
	var max_attempts = 8
	var best_target = spawn_position
	var best_min_distance = 0.0

	for _i in range(max_attempts):
		var angle = randf() * TAU
		var distance = randf() * patrol_radius
		var candidate = spawn_position + Vector2(cos(angle), sin(angle)) * distance

		# Check if candidate is inside a lava pool
		if is_position_in_lava(candidate):
			continue

		# Check distance to other enemies' patrol targets to avoid convergence
		var min_dist_to_others = INF
		for other_enemy in cached_enemies:
			if other_enemy == enemy or not is_instance_valid(other_enemy):
				continue
			if other_enemy.is_dying or other_enemy.is_corpse:
				continue

			var other_ai = other_enemy.get_node_or_null("EnemyAI")
			if other_ai:
				var dist_to_target = candidate.distance_to(other_ai.patrol_target)
				var dist_to_enemy = candidate.distance_to(other_enemy.global_position)
				min_dist_to_others = min(min_dist_to_others, min(dist_to_target, dist_to_enemy))

		# Keep the target that's most spread out from others
		if min_dist_to_others > best_min_distance:
			best_min_distance = min_dist_to_others
			best_target = candidate

	patrol_target = best_target

func is_path_blocked_by_enemy() -> bool:
	"""Check if another enemy is directly in our path to the patrol target"""
	var direction_to_target = (patrol_target - enemy.global_position).normalized()

	for other_enemy in cached_enemies:
		if other_enemy == enemy or not is_instance_valid(other_enemy):
			continue
		if other_enemy.is_dying or other_enemy.is_corpse:
			continue

		var distance = enemy.global_position.distance_to(other_enemy.global_position)
		# Check at larger range for early detection
		if distance < separation_radius * 1.5:
			# Check if this enemy is roughly in our path (within 90 degree cone)
			var direction_to_other = (other_enemy.global_position - enemy.global_position).normalized()
			var dot = direction_to_target.dot(direction_to_other)
			if dot > 0.3:  # Within ~70 degree cone ahead (was 0.5/60 degrees)
				return true
			# Also check if we're facing each other (collision course)
			if distance < separation_radius:
				var other_ai = other_enemy.get_node_or_null("EnemyAI")
				if other_ai and other_ai.current_state == State.PATROLLING:
					var other_direction = (other_ai.patrol_target - other_enemy.global_position).normalized()
					var facing_each_other = direction_to_target.dot(-other_direction) > 0.5
					if facing_each_other:
						return true

	return false

func get_separation_force() -> Vector2:
	"""Calculate a force pushing away from nearby enemies (prevents stacking)"""
	var force = Vector2.ZERO
	var overlap_radius = separation_radius * 1.5  # Slightly larger than blocking radius
	var overlap_radius_sq = overlap_radius * overlap_radius

	for other_enemy in cached_enemies:
		if other_enemy == enemy or not is_instance_valid(other_enemy):
			continue
		if other_enemy.is_dying or other_enemy.is_corpse:
			continue

		var to_other = other_enemy.global_position - enemy.global_position
		var distance_sq = to_other.length_squared()

		# Early out if too far (avoids sqrt for distant enemies)
		if distance_sq >= overlap_radius_sq:
			continue

		if distance_sq > 0.01:  # 0.1 squared
			# Within overlap range - calculate actual distance for strength
			var distance = sqrt(distance_sq)
			var strength = 1.0 - (distance / overlap_radius)
			strength = strength * strength  # Square for aggressive close-range separation
			force -= to_other.normalized() * strength
		else:
			# Nearly on top of each other - push in random direction
			var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			force += random_dir * 2.0

	# Return scaled force (not just normalized) for more aggressive separation
	var force_len_sq = force.length_squared()
	if force_len_sq > 0.01:  # 0.1 squared
		var force_len = sqrt(force_len_sq)
		return force.normalized() * minf(force_len, 1.5)  # Cap at 1.5x strength
	return Vector2.ZERO

# ═══════════════════════════════════════════════════════════════════════════
# COMBAT STATE (Chasing Player)
# ═══════════════════════════════════════════════════════════════════════════

func process_combat(delta: float) -> void:
	# In multiplayer, find the nearest ALIVE player instead of relying on cached_player
	# This ensures enemies chase the correct player (the one who attacked them)
	if multiplayer.has_multiplayer_peer():
		var nearest_player: CharacterBody2D = null
		var nearest_distance: float = INF
		for p in cached_players:
			if is_instance_valid(p) and not p.get("is_dead"):
				var dist = enemy.global_position.distance_to(p.global_position)
				if dist < nearest_distance:
					nearest_distance = dist
					nearest_player = p
		player = nearest_player

	if not player or not is_instance_valid(player):
		disengage()
		return

	# Disengage if target player is dead - don't camp the corpse!
	if player.get("is_dead"):
		disengage()
		return

	# Chunk-based leashing - ALL mobs use chunk edges as leash boundaries
	# This allows kiting within a chunk but prevents pulling mobs across chunks
	# Skip this check in multiplayer - server is authoritative and players may be in different chunks
	if not multiplayer.has_multiplayer_peer():
		var player_chunk = get_chunk_key(player.global_position)
		if player_chunk != spawn_chunk:
			start_returning()
			return

	var distance_to_player = enemy.global_position.distance_to(player.global_position)

	# Account for enemy's enlarged size during crit window
	var effective_attack_range = attack_range
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		effective_attack_range = attack_range * 2.0

	# Check if player escaped (too far away)
	if distance_to_player > disengage_distance:
		start_returning()
		return
	
	# Check if in attack range (adjusted for crit window)
	if distance_to_player < effective_attack_range:
		change_state(State.ATTACKING)
		return
	
	# Chase player
	var direction = (player.global_position - enemy.global_position).normalized()
	var speed = combat_speed

	# Slow enemy during crit window (60% slow for easier weakpoint targeting)
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		speed *= 0.4  # 60% slow

	# Get separation force from other enemies (prevent stacking during chase)
	var separation_force = get_separation_force()

	# Check if next position would be in lava - try to go around
	var next_pos = enemy.global_position + direction * speed * 0.1  # Look ahead 0.1 seconds
	if is_position_in_lava(next_pos):
		# Try perpendicular directions to go around the lava
		var perpendicular_right = Vector2(-direction.y, direction.x)
		var perpendicular_left = Vector2(direction.y, -direction.x)

		var right_pos = enemy.global_position + perpendicular_right * speed * 0.1
		var left_pos = enemy.global_position + perpendicular_left * speed * 0.1

		if not is_position_in_lava(right_pos):
			direction = (direction + perpendicular_right).normalized()
		elif not is_position_in_lava(left_pos):
			direction = (direction + perpendicular_left).normalized()
		else:
			# Both sides blocked, stop and wait
			enemy.velocity = Vector2.ZERO
			update_enemy_animation(Vector2.ZERO)
			enemy.move_and_slide()
			return

	# Apply separation force during combat (prevents stacking on player)
	if separation_force.length() > 0.3:
		# Blend chase direction with separation (separation less important during chase)
		direction = (direction * 0.7 + separation_force * 0.3).normalized()

	enemy.velocity = direction * speed
	update_enemy_animation(direction)
	enemy.move_and_slide()

	# Fix magnet effect: if we collided, reduce velocity temporarily
	if enemy.get_slide_collision_count() > 0:
		for i in range(enemy.get_slide_collision_count()):
			var collision = enemy.get_slide_collision(i)
			var collider = collision.get_collider()
			# If we hit the player or another entity, stop pushing
			if collider and (collider.is_in_group(Constants.GROUP_PLAYER) or collider is CharacterBody2D):
				enemy.velocity *= 0.3  # Reduce velocity to 30% to prevent sticking
				break

# ═══════════════════════════════════════════════════════════════════════════
# ATTACKING STATE (In Range)
# ═══════════════════════════════════════════════════════════════════════════

func process_attacking(delta: float) -> void:
	# In multiplayer, find the nearest ALIVE player
	if multiplayer.has_multiplayer_peer():
		var nearest_player: CharacterBody2D = null
		var nearest_distance: float = INF
		for p in cached_players:
			if is_instance_valid(p) and not p.get("is_dead"):
				var dist = enemy.global_position.distance_to(p.global_position)
				if dist < nearest_distance:
					nearest_distance = dist
					nearest_player = p
		player = nearest_player

	if not player or not is_instance_valid(player):
		disengage()
		return

	# Disengage if target player is dead - don't camp the corpse!
	if player.get("is_dead"):
		disengage()
		return

	var distance_to_player = enemy.global_position.distance_to(player.global_position)
	
	# Account for enemy's enlarged size during crit window
	var effective_attack_range = attack_range
	var in_crit = false
	if enemy.has_method("get"):
		in_crit = enemy.get("in_crit_window")
		if in_crit:
			effective_attack_range = attack_range * 2.0  # Bigger enemy = longer reach
	
	# Check if player moved out of range (use effective range)
	if distance_to_player > effective_attack_range * 1.2:  # 1.2x = small buffer
		change_state(State.COMBAT)  # Go back to chasing
		return
	
	# Stop moving
	enemy.velocity = Vector2.ZERO

	# Lazy re-fetch anim_sprite if needed
	if not anim_sprite and enemy and is_instance_valid(enemy) and enemy.has_node("Sprite"):
		sprite = enemy.get_node("Sprite")
		anim_sprite = sprite as AnimatedSprite2D

	# Don't override attack animation if it's playing
	var is_playing_attack = false
	if anim_sprite:
		is_playing_attack = anim_sprite.animation.begins_with("attack_") and anim_sprite.is_playing()

	# Only update to idle if not currently playing an attack animation
	if not is_playing_attack:
		var direction = (player.global_position - enemy.global_position).normalized()
		update_enemy_animation(Vector2.ZERO)  # Show idle

	enemy.move_and_slide()

	# Fix magnetism: if colliding with player while attacking, push apart slightly
	if enemy.get_slide_collision_count() > 0:
		for i in range(enemy.get_slide_collision_count()):
			var collision = enemy.get_slide_collision(i)
			var collider = collision.get_collider()
			if collider and collider.is_in_group(Constants.GROUP_PLAYER):
				# Push enemy away from player slightly to prevent sticking
				var push_direction = (enemy.global_position - player.global_position).normalized()
				enemy.global_position += push_direction * 2.0  # Move 2 pixels away
				break

	# Attack when ready AND in range
	if attack_timer <= 0 and distance_to_player <= effective_attack_range:
		perform_attack()
		attack_timer = attack_cooldown

# ═══════════════════════════════════════════════════════════════════════════
# RETREATING STATE (Tactical Retreat)
# ═══════════════════════════════════════════════════════════════════════════

func process_retreating(delta: float) -> void:
	# If crit window opens, stop retreating and fight
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		change_state(State.COMBAT)
		return

	# Retreat for duration
	if state_timer > retreat_duration:
		change_state(State.COMBAT)
		return

	# Move away from player
	enemy.velocity = retreat_direction * combat_speed * 1.2
	update_enemy_animation(retreat_direction)
	enemy.move_and_slide()

# ═══════════════════════════════════════════════════════════════════════════
# REMOVED: DETERRED STATE - Players can now fight at campfire with healing
# ═══════════════════════════════════════════════════════════════════════════
# UNSTUCKING STATE (About-Face Recovery)
# ═══════════════════════════════════════════════════════════════════════════

func process_unstucking(delta: float) -> void:
	"""Perform about-face maneuver: walk backward, then resume original behavior"""

	# Take a step backward
	var step_speed = patrol_speed * 0.8  # Slightly slower than patrol
	enemy.velocity = unstuck_direction * step_speed
	update_enemy_animation(unstuck_direction)
	enemy.move_and_slide()

	# Count steps (roughly based on distance traveled)
	# Each "step" is about 0.1 seconds of movement
	if state_timer >= unstuck_steps_taken * 0.15:  # 0.15s per step
		unstuck_steps_taken += 1

	# After enough steps, resume original behavior
	if unstuck_steps_taken >= unstuck_max_steps:
		# Resume original state
		if unstuck_state_before == State.PATROLLING:
			# Always pick a NEW patrol target after unstuck to avoid walking back into the same obstacle
			pick_new_patrol_target()
			change_state(State.PATROLLING)

		elif unstuck_state_before == State.COMBAT:
			# Resume combat (will automatically chase player)
			change_state(State.COMBAT)
		elif unstuck_state_before == State.CAMPFIRE_ATTRACTED:
			# Resume walking to campfire
			change_state(State.CAMPFIRE_ATTRACTED)
		elif unstuck_state_before == State.RETURNING:
			# Resume returning to spawn
			change_state(State.RETURNING)
		else:
			# Fallback: return to patrol
			change_state(State.PATROLLING)

# ═══════════════════════════════════════════════════════════════════════════
# CAMPFIRE ATTRACTED STATE (Spawned by campfire fuel, walking to investigate)
# ═══════════════════════════════════════════════════════════════════════════

func process_campfire_attracted(delta: float) -> void:
	"""Walk toward the campfire that spawned us, then patrol nearby"""

	# Update despawn timer
	campfire_patrol_timer += delta

	# Check for despawn (10 minutes)
	if campfire_patrol_timer >= CAMPFIRE_DESPAWN_TIME:
		despawn_campfire_skeleton()
		return

	# If player attacked us, enter combat (they take priority)
	if is_in_combat and player:
		change_state(State.COMBAT)
		return

	# In multiplayer, find the nearest ALIVE player for aggro checks
	var aggro_target = player
	if multiplayer.has_multiplayer_peer():
		var nearest_distance: float = INF
		for p in cached_players:
			if is_instance_valid(p) and not p.get("is_dead"):
				var dist = enemy.global_position.distance_to(p.global_position)
				if dist < nearest_distance:
					nearest_distance = dist
					aggro_target = p

	# Check for player in aggro range (auto-aggro) - campfire skeletons still aggro, but not on dead players
	if aggro_target and is_instance_valid(aggro_target) and not aggro_target.get("is_dead") and leash_cooldown_timer <= 0:
		var distance_to_player = enemy.global_position.distance_to(aggro_target.global_position)
		if distance_to_player <= aggro_range:
			player = aggro_target  # Update player reference
			trigger_aggro()
			return

	# Check if campfire still exists
	if not campfire_target or not is_instance_valid(campfire_target):
		# Campfire is gone, just patrol where we are
		spawn_position = enemy.global_position
		pick_new_patrol_target()
		change_state(State.PATROLLING)
		return

	var distance_to_campfire = enemy.global_position.distance_to(campfire_target.global_position)

	# If close to campfire, switch to patrol mode nearby
	if distance_to_campfire < 150.0:
		# Set spawn position near campfire so patrol stays in the area
		spawn_position = campfire_target.global_position
		pick_new_patrol_target()
		change_state(State.PATROLLING)
		return

	# Move toward campfire
	var direction = (campfire_target.global_position - enemy.global_position).normalized()
	enemy.velocity = direction * combat_speed * 0.8  # Walk at 80% combat speed
	update_enemy_animation(direction)
	enemy.move_and_slide()

func despawn_campfire_skeleton() -> void:
	"""Remove this skeleton after patrol timer expires"""
	if not enemy or not is_instance_valid(enemy):
		return

	# Fade out and remove
	var tween = enemy.create_tween()
	tween.tween_property(enemy, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if is_instance_valid(enemy):
			enemy.queue_free()
	)

# ═══════════════════════════════════════════════════════════════════════════
# RETURNING STATE (Walking back to spawn after leashing)
# ═══════════════════════════════════════════════════════════════════════════

func start_returning() -> void:
	"""Start walking back to spawn point - enemy can still re-aggro if player follows"""
	is_in_combat = false
	leash_cooldown_timer = LEASH_COOLDOWN_DURATION  # Prevent immediate re-aggro
	change_state(State.RETURNING)

func process_returning(delta: float) -> void:
	"""Walk back to original spawn point, can re-aggro if player gets close"""

	# Check for player in aggro range - can re-aggro while returning!
	# This allows players to chase and re-engage if they want
	if leash_cooldown_timer <= 0:
		var aggro_target = player
		if multiplayer.has_multiplayer_peer():
			var nearest_distance: float = INF
			for p in cached_players:
				if is_instance_valid(p) and not p.get("is_dead"):
					var dist = enemy.global_position.distance_to(p.global_position)
					if dist < nearest_distance:
						nearest_distance = dist
						aggro_target = p

		if aggro_target and is_instance_valid(aggro_target) and not aggro_target.get("is_dead"):
			var distance_to_player = enemy.global_position.distance_to(aggro_target.global_position)
			if distance_to_player <= aggro_range:
				# Re-aggro! Player is following
				player = aggro_target
				trigger_aggro()
				return

	# Check if we've reached spawn position
	var distance_to_spawn = enemy.global_position.distance_to(original_spawn_position)
	if distance_to_spawn < 30.0:
		# Reached spawn! Regenerate health and start patrolling
		_restore_health_at_spawn()
		spawn_position = original_spawn_position
		pick_new_patrol_target()
		change_state(State.PATROLLING)
		return

	# Walk toward spawn point
	var direction = (original_spawn_position - enemy.global_position).normalized()
	var return_speed = patrol_speed * 1.5  # Walk back a bit faster than patrol

	# Avoid lava while returning
	var next_pos = enemy.global_position + direction * return_speed * 0.1
	if is_position_in_lava(next_pos):
		# Try to go around lava
		var perpendicular_right = Vector2(-direction.y, direction.x)
		var perpendicular_left = Vector2(direction.y, -direction.x)

		var right_pos = enemy.global_position + perpendicular_right * return_speed * 0.1
		var left_pos = enemy.global_position + perpendicular_left * return_speed * 0.1

		if not is_position_in_lava(right_pos):
			direction = (direction + perpendicular_right).normalized()
		elif not is_position_in_lava(left_pos):
			direction = (direction + perpendicular_left).normalized()

	enemy.velocity = direction * return_speed
	update_enemy_animation(direction)
	enemy.move_and_slide()

func _restore_health_at_spawn() -> void:
	"""Restore health when enemy reaches spawn point after returning"""
	if enemy.has_method("get") and enemy.has_method("set"):
		var max_hp = enemy.get("max_health")

		# Validate max_health before resetting
		if max_hp != null and max_hp > 0 and not is_nan(max_hp) and not is_inf(max_hp):
			enemy.set("current_health", max_hp)

			# Update health bar if it exists
			if enemy.has_node("HealthBar"):
				if health_bar_node and health_bar_node.has_method("update_health"):
					health_bar_node.update_health(max_hp, max_hp)
		else:
			push_error("Cannot reset enemy health - invalid max_health: %s" % str(max_hp))

# ═══════════════════════════════════════════════════════════════════════════
# COMBAT ACTIONS
# ═══════════════════════════════════════════════════════════════════════════

func perform_attack() -> void:
	"""Attack the player"""
	if not is_instance_valid(player):
		return

	# CRITICAL: Prevent concurrent attacks (fixes 1000 attack sound bug)
	if is_performing_attack:
		return

	# CRITICAL: Verify enemy still exists before starting attack
	if not is_instance_valid(enemy):
		return

	is_performing_attack = true

	# Play attack sound (sound manager handles preventing overlap)
	if _sound_manager:
		_sound_manager.play_skeleton_attack_sound(enemy.global_position, -14.0)

	# Lazy re-fetch anim_sprite if needed
	if not anim_sprite and enemy and is_instance_valid(enemy):
		if enemy.has_node("Sprite"):
			sprite = enemy.get_node("Sprite")
			anim_sprite = sprite as AnimatedSprite2D

	# Play attack animation
	if anim_sprite and anim_sprite.sprite_frames:
		# Determine direction to player
		var direction = (player.global_position - enemy.global_position).normalized()
		var angle = direction.angle()
		var deg = rad_to_deg(angle)
		if deg < 0:
			deg += 360

		# Get direction string
		var dir_str = "down"
		if deg >= 315 or deg < 45:
			dir_str = "right"
		elif deg >= 45 and deg < 135:
			dir_str = "down"
		elif deg >= 135 and deg < 225:
			dir_str = "left"
		else:
			dir_str = "up"

		# Play attack animation
		var attack_anim = "attack_" + dir_str
		if anim_sprite.sprite_frames.has_animation(attack_anim):
			anim_sprite.play(attack_anim)
			# Don't flip - we have dedicated directional attack animations
			anim_sprite.flip_h = false

			# Sync shadow animation
			if enemy.shadow_sprite and enemy.shadow_sprite.sprite_frames.has_animation(attack_anim):
				enemy.shadow_sprite.play(attack_anim)

	# ✨ Small delay for attack animation to play before dealing damage
	await get_tree().create_timer(0.2).timeout

	# CRITICAL: After await, verify everything still exists
	if not is_instance_valid(enemy) or not is_instance_valid(player):
		is_performing_attack = false
		return

	# Don't deal damage to dead players
	if player.get("is_dead"):
		is_performing_attack = false
		disengage()
		return

	# Deal damage
	var damage = attack_damage
	if enemy.has_method("get") and enemy.get("enemy_level"):
		damage = attack_damage * pow(1.08, enemy.enemy_level - 1)

	# In multiplayer, route damage through NetworkEnemyManager
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Find which peer owns this player
		var target_peer_id = 1  # Default to server
		if player.has_method("get_multiplayer_authority"):
			target_peer_id = player.get_multiplayer_authority()
		elif player.has_meta("peer_id"):
			target_peer_id = player.get_meta("peer_id")

		if _network_enemy_mgr:
			_network_enemy_mgr.deal_damage_to_player(target_peer_id, damage)
		else:
			# Fallback: direct damage (only works for local player)
			if player.has_method("take_damage"):
				player.take_damage(damage)
	else:
		# Single player or client (shouldn't happen - AI only runs on server)
		if player.has_method("take_damage"):
			player.take_damage(damage)

	# ✨ FIX: Enhanced visual feedback for attack (single tween for performance)
	if is_instance_valid(enemy):
		var original_scale = enemy.scale
		var tween = enemy.create_tween()

		# Scale pulse and rotation shake run in parallel
		tween.set_parallel(true)

		# Scale track: pulse to 1.3x then back
		tween.tween_property(enemy, "scale", original_scale * 1.3, 0.1)

		# Rotation track: quick shake (-8, +8, 0) - chain with set_parallel(false) for rotation sequence
		tween.chain().set_parallel(false)
		tween.tween_property(enemy, "rotation_degrees", -8, 0.05)
		tween.tween_property(enemy, "rotation_degrees", 8, 0.05)
		tween.tween_property(enemy, "rotation_degrees", 0, 0.05)

		# Scale back to original (after initial scale up)
		tween.parallel().tween_property(enemy, "scale", original_scale, 0.15).set_delay(0.1)

	# Reset attack flag (allow next attack)
	is_performing_attack = false

# ═══════════════════════════════════════════════════════════════════════════
# AGGRO SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func trigger_aggro() -> void:
	"""Called when player enters aggro range - enemy charges!"""
	if is_in_combat:
		return  # Already in combat

	is_in_combat = true

	# Play aggro sound (sound manager handles preventing overlap)
	if _sound_manager:
		_sound_manager.play_skeleton_aggro_sound(enemy.global_position, -14.0)

	# Chain aggro - alert nearby allies!
	trigger_chain_aggro()

	# Enter combat immediately
	if current_state == State.PATROLLING:
		change_state(State.COMBAT)

func trigger_chain_aggro() -> void:
	"""Alert nearby enemies to join the fight (creates trains!)"""
	# Use cached enemies for proximity check
	var checked = 0
	var my_pos = enemy.global_position
	var range_squared = chain_aggro_range * chain_aggro_range

	for other_enemy in cached_enemies:
		if not is_instance_valid(other_enemy) or other_enemy == enemy:
			continue

		# Early out if too far (square distance check is faster)
		var dist_squared = my_pos.distance_squared_to(other_enemy.global_position)

		if dist_squared <= range_squared:
			# Alert the nearby enemy's AI
			var other_ai = other_enemy.get_node_or_null("EnemyAI")
			if other_ai and not other_ai.is_in_combat:
				other_ai.trigger_aggro()
				checked += 1
				if checked >= 5:  # Max 5 chain aggros at once
					break

# ═══════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_enemy_damaged(_damage: float, is_crit: bool) -> void:
	"""Called when enemy takes damage - this triggers combat!"""
	if not is_in_combat:
		is_in_combat = true

		# Chain aggro - alert nearby allies when attacked!
		trigger_chain_aggro()

		# Enter combat immediately - from ANY non-combat state
		if current_state != State.COMBAT and current_state != State.ATTACKING:
			change_state(State.COMBAT)
	# Already in combat - chance to retreat
	elif current_state != State.RETREATING:
		# Don't retreat during crit window - stand and fight!
		if enemy.has_method("get") and enemy.get("in_crit_window"):
			return

		# Don't retreat if player has ranged weapon (distance doesn't help!)
		if _player_has_ranged_weapon():
			return

		var retreat_roll = retreat_chance
		if is_crit:
			retreat_roll += 0.2  # +20% on crit

		if randf() < retreat_roll:
			# Calculate retreat direction
			if is_instance_valid(player):
				retreat_direction = (enemy.global_position - player.global_position).normalized()
			else:
				retreat_direction = Vector2(randf() * 2 - 1, randf() * 2 - 1).normalized()

			change_state(State.RETREATING)

func disengage() -> void:
	"""Exit combat and return to patrol"""
	is_in_combat = false
	leash_cooldown_timer = LEASH_COOLDOWN_DURATION  # Prevent immediate re-aggro

	# Regenerate health to full when resetting
	if enemy.has_method("get") and enemy.has_method("set"):
		var max_hp = enemy.get("max_health")

		# Validate max_health before resetting
		if max_hp != null and max_hp > 0 and not is_nan(max_hp) and not is_inf(max_hp):
			enemy.set("current_health", max_hp)

			# Update health bar if it exists
			if enemy.has_node("HealthBar"):
				if health_bar_node and health_bar_node.has_method("update_health"):
					health_bar_node.update_health(max_hp, max_hp)
		else:
			push_error("❌ Cannot reset enemy health - invalid max_health: %s" % str(max_hp))

	# Return to original spawn position (don't stay where we are!)
	spawn_position = original_spawn_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)

func _player_has_ranged_weapon() -> bool:
	"""Check if player has a ranged weapon equipped (bow, gun, etc).
	Ranged weapons make retreating pointless since player can still hit from range."""
	if not is_instance_valid(player):
		return false

	# Access player's equipped weapon through CharacterStats
	if not CharacterStats or not CharacterStats.equipped_weapon:
		return false

	var weapon_type = CharacterStats.equipped_weapon.weapon_type

	# Define ranged weapon types
	var ranged_types = [
		"bow", "crossbow",  # Bows
		"gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"  # Guns
	]

	return weapon_type in ranged_types

# ═══════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	
	current_state = new_state
	state_timer = 0.0
	
	# State entry
	match new_state:
		State.PATROLLING:
			is_paused = false
		State.ATTACKING:
			attack_timer = 0.0  # Attack immediately
		State.COMBAT:
			pass
		State.RETREATING:
			pass

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func reset_to_patrol() -> void:
	"""Reset enemy to patrol mode (called on respawn)"""
	# Safety check - enemy might not be set yet if called too early
	if not enemy or not is_instance_valid(enemy):
		await get_tree().process_frame
		if not enemy or not is_instance_valid(enemy):
			return

	# CRITICAL: Don't reset if enemy is in crit window - let it keep fighting!
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		return

	is_in_combat = false
	# Return to original spawn position (don't stay where we are!)
	spawn_position = original_spawn_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)

func disengage_to_spawn() -> void:
	"""Disengage from combat and return to ORIGINAL spawn point (for campfire de-aggro)"""
	# Safety check
	if not enemy or not is_instance_valid(enemy):
		return

	# CRITICAL: Don't reset if enemy is in crit window - let it keep fighting!
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		return

	is_in_combat = false
	leash_cooldown_timer = LEASH_COOLDOWN_DURATION  # Prevent immediate re-aggro

	# Regenerate health to full when resetting
	if enemy.has_method("get") and enemy.has_method("set"):
		var max_hp = enemy.get("max_health")

		# Validate max_health before resetting
		if max_hp != null and max_hp > 0 and not is_nan(max_hp) and not is_inf(max_hp):
			enemy.set("current_health", max_hp)

			# Update health bar if it exists
			if enemy.has_node("HealthBar"):
				if health_bar_node and health_bar_node.has_method("update_health"):
					health_bar_node.update_health(max_hp, max_hp)
		else:
			push_error("❌ Cannot reset enemy health - invalid max_health: %s" % str(max_hp))

	# Reset to ORIGINAL spawn position (not current position)
	spawn_position = original_spawn_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)

# REMOVED: enter_deterred_state() - players can now fight at campfire with healing

func get_state_name() -> String:
	return get_state_name_for_state(current_state)

func get_state_name_for_state(state: State) -> String:
	match state:
		State.PATROLLING: return "PATROLLING"
		State.COMBAT: return "COMBAT"
		State.ATTACKING: return "ATTACKING"
		State.RETREATING: return "RETREATING"
		State.UNSTUCKING: return "UNSTUCKING"
		State.CAMPFIRE_ATTRACTED: return "CAMPFIRE_ATTRACTED"
		State.RETURNING: return "RETURNING"
	return "UNKNOWN"

func update_enemy_animation(velocity: Vector2) -> void:
	"""Update enemy animation based on movement"""
	# Lazy re-fetch: if anim_sprite is null, try to get it from enemy.sprite
	# This handles timing where EnemyAI._ready() runs before Enemy._ready() converts Sprite2D to AnimatedSprite2D
	if not anim_sprite and enemy and is_instance_valid(enemy):
		if enemy.has_node("Sprite"):
			sprite = enemy.get_node("Sprite")
			anim_sprite = sprite as AnimatedSprite2D

	if not anim_sprite or not anim_sprite.sprite_frames:
		return

	# ✨ FIX: Don't interrupt attack animations
	if anim_sprite.animation.begins_with("attack_") and anim_sprite.is_playing():
		return

	var is_moving = velocity.length() > 0.1

	# Get direction
	var dir_str = "down"  # default
	if is_moving:
		var angle = velocity.angle()
		var deg = rad_to_deg(angle)
		if deg < 0:
			deg += 360

		# 4 directions only for enemies
		if deg >= 315 or deg < 45:
			dir_str = "right"
		elif deg >= 45 and deg < 135:
			dir_str = "down"
		elif deg >= 135 and deg < 225:
			dir_str = "left"
		else:
			dir_str = "up"

		# Remember facing direction for when we stop
		last_facing_direction = dir_str
	else:
		# Use last facing direction when idle, or random if never moved
		if last_facing_direction != "":
			dir_str = last_facing_direction
		elif last_facing_direction == "":
			# First idle - pick random direction
			var directions = ["up", "down", "left", "right"]
			last_facing_direction = directions[randi() % directions.size()]
			dir_str = last_facing_direction
	
	# Play appropriate animation
	var prefix = "walk_" if is_moving else "idle_"
	var anim_name = prefix + dir_str

	if anim_sprite.sprite_frames.has_animation(anim_name):
		if anim_sprite.animation != anim_name:
			anim_sprite.play(anim_name)

			# Sync shadow animation
			if enemy.shadow_sprite and enemy.shadow_sprite.sprite_frames.has_animation(anim_name):
				enemy.shadow_sprite.play(anim_name)

	# Play footsteps on walk animations (frames 1, 3, 5, 7 of 9-frame walk cycle)
	if anim_sprite.animation.begins_with("walk_"):
		var current_frame = anim_sprite.frame
		if current_frame in [1, 3, 5, 7] and current_frame != last_footstep_frame:
			last_footstep_frame = current_frame
			play_enemy_footstep()

	# Don't flip sprites - we have dedicated directional animations
	anim_sprite.flip_h = false

func update_lod_level(distance: float) -> void:
	"""Update LOD level based on distance from player"""
	var new_lod: LODLevel

	if distance > 2500:
		new_lod = LODLevel.CULLED
	elif distance > 1500:
		new_lod = LODLevel.PLACEHOLDER
	elif distance > 1000:
		new_lod = LODLevel.LOW
	elif distance > 500:
		new_lod = LODLevel.MEDIUM
	else:
		new_lod = LODLevel.FULL

	# Only update if LOD changed
	if new_lod != current_lod:
		current_lod = new_lod

func play_enemy_footstep() -> void:
	"""Play skeleton footstep sound and dust puff"""
	if not enemy or not is_instance_valid(enemy):
		return

	# Skip footsteps for LOW quality and below
	if current_lod >= LODLevel.LOW:
		return

	# Get camera position for distance culling
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	var camera_pos = camera.global_position

	# Calculate distance to camera once
	var distance = enemy.global_position.distance_to(camera_pos)

	# Only play footstep sound for the CLOSEST skeleton within 400px
	if distance <= 400.0:
		# Check if this is the closest skeleton
		var closest_distance = distance

		for other_enemy in cached_enemies:
			if other_enemy == enemy or not is_instance_valid(other_enemy):
				continue

			var other_distance = other_enemy.global_position.distance_to(camera_pos)
			if other_distance < closest_distance:
				# Found a closer skeleton, don't play sound for this one
				closest_distance = other_distance

		# Only play sound if this is the closest skeleton
		if closest_distance == distance:
			if _sound_manager:
				_sound_manager.play_skeleton_footstep(enemy.global_position, camera_pos)

	# Only spawn dust if within visual range (1000px)
	if distance < 1000.0:
		# Get sprite to determine facing direction
		var anim_sprite = enemy.sprite as AnimatedSprite2D
		if not anim_sprite:
			return

		# Spawn dust puff at skeleton's feet - adjust position based on facing direction
		var dust_offset = Vector2(0, 30)  # Default: at feet

		# Check if moving diagonally by examining velocity
		var is_moving_diagonally = abs(enemy.velocity.x) > 10 and abs(enemy.velocity.y) > 10

		# Adjust offset based on animation direction
		if anim_sprite.animation and anim_sprite.animation.begins_with("walk_"):
			if anim_sprite.animation.ends_with("_up"):
				if is_moving_diagonally:
					dust_offset = Vector2(0, 5)  # Diagonal up: lower to be visible
				else:
					dust_offset = Vector2(0, 15)  # Straight up: lower to be visible
			elif anim_sprite.animation.ends_with("_down"):
				if is_moving_diagonally:
					dust_offset = Vector2(0, 30)  # Diagonal down: lower
				else:
					dust_offset = Vector2(0, 40)  # Straight down
			elif anim_sprite.animation.ends_with("_right"):
				if is_moving_diagonally:
					dust_offset = Vector2(15, 25)  # Diagonal right: pull back X, lower Y
				else:
					dust_offset = Vector2(10, 30)  # Straight right: pull back X more
			elif anim_sprite.animation.ends_with("_left"):
				if is_moving_diagonally:
					dust_offset = Vector2(-15, 25)  # Diagonal left: pull back X, lower Y
				else:
					dust_offset = Vector2(-10, 30)  # Straight left: pull back X more

		var dust = preload("res://scripts/effects/FootstepDust.gd").new()
		dust.global_position = enemy.global_position + dust_offset
		get_tree().root.add_child(dust)
		dust.spawn_dust()

func create_debug_label() -> void:
	"""Create debug label showing enemy name above head"""
	var canvas = CanvasLayer.new()
	canvas.name = "DebugCanvas"
	canvas.layer = 100  # Draw on top
	enemy.add_child(canvas)

	debug_label = Label.new()
	debug_label.name = "DebugLabel"
	debug_label.add_theme_font_size_override("font_size", 12)
	debug_label.add_theme_color_override("font_color", Color.YELLOW)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 2)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debug_label.visible = false  # Hidden by default
	canvas.add_child(debug_label)

	# Set the label text to the enemy's name
	debug_label.text = enemy.name

	# Position label above enemy head
	update_debug_label_position()

func update_debug_label_position() -> void:
	"""Update debug label position to follow enemy"""
	if not debug_label or not debug_label.visible:
		return

	var camera = enemy.get_viewport().get_camera_2d()
	if camera:
		var viewport_size = enemy.get_viewport().get_visible_rect().size
		var world_pos = enemy.global_position + Vector2(0, -60)  # Above head
		var camera_pos = camera.global_position
		var screen_center = viewport_size / 2
		var relative_pos = (world_pos - camera_pos) * camera.zoom.x + screen_center
		debug_label.position = relative_pos - debug_label.size / 2

# ═══════════════════════════════════════════════════════════════════════════
# CHUNK SYSTEM HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func get_chunk_key(position: Vector2) -> String:
	"""Get chunk key for a world position (matches ChunkBasedPropSystem)"""
	var chunk_x = int(floor(position.x / Constants.CHUNK_SIZE))
	return "%d,0" % chunk_x  # Y is always 0 (single row of square chunks)

# ═══════════════════════════════════════════════════════════════════════════
# LAVA POOL AVOIDANCE
# ═══════════════════════════════════════════════════════════════════════════

func is_position_in_lava(pos: Vector2) -> bool:
	"""Check if a position is inside any lava pool"""
	var spawn_manager = get_node_or_null("/root/GameWorld/ChunkAwareSpawnManager")
	if not spawn_manager:
		return false

	# Access lava_pools from ChunkAwareSpawnManager
	if spawn_manager.has_method("get") or "lava_pools" in spawn_manager:
		var pools = spawn_manager.lava_pools
		for pool in pools:
			var dist = pos.distance_to(pool.center)
			if dist < pool.radius:
				return true

	return false

func is_path_crossing_lava(from_pos: Vector2, to_pos: Vector2) -> bool:
	"""Check if a path would cross through a lava pool"""
	var spawn_manager = get_node_or_null("/root/GameWorld/ChunkAwareSpawnManager")
	if not spawn_manager:
		return false

	if not "lava_pools" in spawn_manager:
		return false

	var pools = spawn_manager.lava_pools
	var direction = (to_pos - from_pos).normalized()
	var distance = from_pos.distance_to(to_pos)

	# Check points along the path
	var check_interval = 50.0  # Check every 50 pixels
	var steps = int(distance / check_interval) + 1

	for i in range(steps):
		var check_pos = from_pos + direction * (i * check_interval)
		for pool in pools:
			var dist_to_pool = check_pos.distance_to(pool.center)
			if dist_to_pool < pool.radius:
				return true

	return false
