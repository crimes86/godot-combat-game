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
@export var leash_distance: float = 800.0  # Max distance from spawn before returning
@export var chain_aggro_range: float = 100.0  # Nearby allies aggro too (creates trains!)

## Combat (triggered by player attack OR aggro)
@export var combat_speed: float = 100.0
@export var attack_range: float = 60.0
@export var attack_cooldown: float = 1.5
@export var attack_damage: float = 10.0
@export var disengage_distance: float = 600.0  # Return to patrol if too far

## Behavior
@export var retreat_chance: float = 0.25  # 25% chance on hit
@export var retreat_duration: float = 0.8

# ═══════════════════════════════════════════════════════════════════════════
# STATE MACHINE
# ═══════════════════════════════════════════════════════════════════════════

enum State {
	PATROLLING,   # Default: peaceful wandering
	COMBAT,       # Engaged: chasing player
	ATTACKING,    # In range: striking player
	RETREATING,   # Tactical: backing away
	UNSTUCKING,   # Recovery: walking backward to get unstuck
	# REMOVED: DETERRED state - players can now fight at campfire with healing
}

var current_state: State = State.PATROLLING
var state_timer: float = 0.0

# ═══════════════════════════════════════════════════════════════════════════
# REFERENCES & STATE
# ═══════════════════════════════════════════════════════════════════════════

var enemy: CharacterBody2D = null
var player: CharacterBody2D = null
var sprite: CanvasItem = null  # ✨ Changed from Sprite2D to support AnimatedSprite2D too
var debug_label: Label = null

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
static var attack_sound_cooldown: float = 0.15  # Min 0.15s between attack sounds

# Aggro sound spam prevention (per-enemy, not static)
var last_aggro_sound_time: float = 0.0
var aggro_sound_cooldown: float = 3.0  # Min 3.0s between aggro laughs per enemy

# Footstep tracking
var last_footstep_frame: int = -1  # Track last frame that played footstep

# Performance: Throttle AI updates based on distance from player
var ai_update_timer: float = 0.0
var ai_update_interval: float = 0.1  # Default: update AI every 0.1s instead of 60 FPS
var debug_update_timer: float = 0.0
var cached_player: CharacterBody2D = null  # Cache player reference

# LOD (Level of Detail) system
enum LODLevel { FULL, MEDIUM, LOW, PLACEHOLDER, CULLED }
var current_lod: LODLevel = LODLevel.FULL
var lod_update_timer: float = 0.0
var lod_update_interval: float = 1.0  # Check LOD once per second

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	await get_tree().process_frame
	
	enemy = get_parent() as CharacterBody2D
	if not enemy:
		push_error("EnemyAI must be child of CharacterBody2D!")
		return
	
	# Get references
	# Check for "Sprite" first (AnimatedSprite2D), then "Sprite2D" (fallback)
	if enemy.has_node("Sprite"):
		sprite = enemy.get_node("Sprite")
	elif enemy.has_node("Sprite2D"):
		sprite = enemy.get_node("Sprite2D")
	
	# Store spawn position for patrol
	spawn_position = enemy.global_position
	original_spawn_position = enemy.global_position  # Save the TRUE spawn point
	spawn_chunk = get_chunk_key(enemy.global_position)  # Save spawn chunk for leashing
	last_position = enemy.global_position  # Initialize stuck detection
	
	# Connect to damage signal to detect player attacks
	if enemy.has_signal("damage_taken"):
		enemy.damage_taken.connect(_on_enemy_damaged)
	
	# Fixed speed (no level scaling - equipment may add bonuses later)
	# Note: combat_speed and patrol_speed use @export defaults (100.0 and 30.0)
	
	# Start patrolling
	pick_new_patrol_target()
	change_state(State.PATROLLING)

	# Create debug label (always created, visibility controlled by player debug mode)
	create_debug_label()

	# Brief init message with enemy name and position
	print("🤖 %s AI ready at (%.0f, %.0f)" % [enemy.name, enemy.global_position.x, enemy.global_position.y])

# ═══════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if not enemy or not is_instance_valid(enemy):
		return

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

	# Cache player reference (look up once, reuse for 1 second)
	if not cached_player or not is_instance_valid(cached_player):
		cached_player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		player = cached_player

	# Calculate distance-based update rate
	var distance_to_player = 999999.0
	if cached_player and is_instance_valid(cached_player):
		distance_to_player = enemy.global_position.distance_to(cached_player.global_position)

	# ═══════════════════════════════════════════════════════════════
	# LOD (LEVEL OF DETAIL) SYSTEM - Aggressive performance optimization
	# ═══════════════════════════════════════════════════════════════
	lod_update_timer += delta
	if lod_update_timer >= lod_update_interval:
		lod_update_timer = 0.0
		update_lod_level(distance_to_player)

	# Apply LOD-based optimizations
	match current_lod:
		LODLevel.CULLED:
			# Beyond 2500px: Completely disabled (not visible)
			enemy.velocity = Vector2.ZERO
			enemy.visible = false
			if sprite:
				sprite.visible = false
			if enemy.shadow_sprite:
				enemy.shadow_sprite.visible = false
			return  # Skip all processing

		LODLevel.PLACEHOLDER:
			# 1500-2500px: Minimal "placeholder" state
			# - Simple idle animation or static sprite
			# - No AI, no collision, no particles
			# - Visible but not interactive
			enemy.velocity = Vector2.ZERO
			enemy.visible = true
			if sprite:
				sprite.visible = true
				# Show only idle animation
				var anim_sprite = sprite as AnimatedSprite2D
				if anim_sprite and anim_sprite.sprite_frames:
					if not anim_sprite.animation.begins_with("idle_"):
						anim_sprite.play("idle_down")
						anim_sprite.speed_scale = 0.5  # Slow animation
			# Hide shadow in placeholder mode
			if enemy.shadow_sprite:
				enemy.shadow_sprite.visible = false
			return  # Skip AI processing

		LODLevel.LOW:
			# 1000-1500px: Minimal features
			# - Basic AI (patrol only, no combat unless already engaged)
			# - No footsteps, no shadows
			# - Slow update rate (0.3s)
			ai_update_interval = 0.3  # 3 FPS
			if sprite:
				sprite.visible = true
			if enemy.shadow_sprite:
				enemy.shadow_sprite.visible = false
			# Don't aggro at this distance unless already in combat
			if not is_in_combat:
				enemy.velocity = Vector2.ZERO
				enemy.move_and_slide()
				return

		LODLevel.MEDIUM:
			# 500-1000px: Reduced features
			# - Full AI but slower updates
			# - Shadows visible but no footstep particles
			# - Medium update rate (0.15s)
			ai_update_interval = 0.15  # 6-7 FPS
			if sprite:
				sprite.visible = true
			if enemy.shadow_sprite:
				enemy.shadow_sprite.visible = true

		LODLevel.FULL:
			# 0-500px: Full quality
			# - Full AI, all features enabled
			# - Fast update rate
			if is_in_combat or distance_to_player < 300:
				ai_update_interval = 0.05  # 20 FPS when near or in combat
			else:
				ai_update_interval = 0.1   # 10 FPS when close but not in combat
			if sprite:
				sprite.visible = true
			if enemy.shadow_sprite:
				enemy.shadow_sprite.visible = true

	# ═══════════════════════════════════════════════════════════════
	# STUCK DETECTION (runs every frame, independent of AI throttling)
	# ═══════════════════════════════════════════════════════════════
	# Check for stuck (works in PATROLLING and COMBAT, but not while already unstucking)
	if current_state != State.UNSTUCKING and current_state != State.ATTACKING and current_state != State.RETREATING:
		stuck_timer += delta
		if stuck_timer >= stuck_check_interval:
			var distance_moved = enemy.global_position.distance_to(last_position)

			# Check if enemy is in walking animation state (trying to move)
			var is_walking = false
			var anim_sprite = enemy.get_node_or_null("Sprite") as AnimatedSprite2D
			if anim_sprite and anim_sprite.animation:
				is_walking = anim_sprite.animation.begins_with("walk_")

			# If walking animation is playing but position hasn't changed = STUCK
			if distance_moved < stuck_distance_threshold and is_walking:
				# We're stuck! Start the about-face unstuck maneuver
				print("⚠️ %s STUCK at (%.0f, %.0f) - walking but only moved %.1fpx in %.1fs" % [
					enemy.name,
					enemy.global_position.x,
					enemy.global_position.y,
					distance_moved,
					stuck_check_interval
				])

				# Store current state and destination to resume later
				unstuck_state_before = current_state
				if current_state == State.PATROLLING:
					unstuck_original_target = patrol_target
				elif current_state == State.COMBAT and player:
					unstuck_original_target = player.global_position

				# Calculate about-face direction (opposite of current velocity, with random Y offset)
				var backward_direction = -enemy.velocity.normalized()
				var y_offset = randf_range(-0.5, 0.5)  # Random Y component for variation
				unstuck_direction = (backward_direction + Vector2(0, y_offset)).normalized()

				# Reset unstuck counter
				unstuck_steps_taken = 0

				print("   🔄 %s: About-face (%d steps), then resume %s" % [enemy.name, unstuck_max_steps, get_state_name()])

				# Enter unstuck state
				change_state(State.UNSTUCKING)
			last_position = enemy.global_position
			stuck_timer = 0.0
	else:
		# Reset stuck timer when in states that shouldn't check for stuck
		stuck_timer = 0.0
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

	# Update debug label (only when AI updates, not every frame)
	debug_update_timer += delta
	if debug_label and player and debug_update_timer >= 0.5:  # Update label twice per second max
		debug_label.visible = player.get("debug_mode") == true
		if debug_label.visible:
			update_debug_label_position()
		debug_update_timer = 0.0

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
		# REMOVED: DETERRED state processing

# ═══════════════════════════════════════════════════════════════════════════
# PATROLLING STATE (Default - Non-Aggro)
# ═══════════════════════════════════════════════════════════════════════════

func process_patrolling(delta: float) -> void:
	# If player attacked us, enter combat
	if is_in_combat and player:
		change_state(State.COMBAT)
		return

	# Check for player in aggro range (auto-aggro) - but only if not on leash cooldown
	if player and is_instance_valid(player) and leash_cooldown_timer <= 0:
		var distance_to_player = enemy.global_position.distance_to(player.global_position)
		if distance_to_player <= aggro_range:
			# AGGRO!
			trigger_aggro()
			return

	# Handle patrol pause
	if is_paused:
		pause_timer -= delta
		if pause_timer <= 0:
			is_paused = false
			pick_new_patrol_target()
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
		enemy.velocity = Vector2.ZERO
		update_enemy_animation(Vector2.ZERO)
	else:
		# Move toward target
		var direction = (patrol_target - enemy.global_position).normalized()
		enemy.velocity = direction * patrol_speed
		update_enemy_animation(direction)

	enemy.move_and_slide()

func pick_new_patrol_target() -> void:
	"""Pick a random point within patrol_radius of spawn"""
	var angle = randf() * TAU
	var distance = randf() * patrol_radius
	patrol_target = spawn_position + Vector2(cos(angle), sin(angle)) * distance

# ═══════════════════════════════════════════════════════════════════════════
# COMBAT STATE (Chasing Player)
# ═══════════════════════════════════════════════════════════════════════════

func process_combat(delta: float) -> void:
	if not player or not is_instance_valid(player):
		disengage()
		return

	# Check chunk-based leashing - if player left spawn chunk, disengage
	var player_chunk = get_chunk_key(player.global_position)
	if player_chunk != spawn_chunk:
		print("🏠 %s: Player left spawn chunk (spawn: %s, player: %s) - disengaging" % [enemy.name, spawn_chunk, player_chunk])
		disengage()
		return

	var distance_to_player = enemy.global_position.distance_to(player.global_position)

	# Account for enemy's enlarged size during crit window
	var effective_attack_range = attack_range
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		effective_attack_range = attack_range * 2.0  # 60 * 2 = 120

	# Check if player escaped
	if distance_to_player > disengage_distance:
		print("💤 %s: Player escaped (%.0fpx away)" % [enemy.name, distance_to_player])
		disengage()
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
	if not player or not is_instance_valid(player):
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

	# ✨ FIX: Don't override attack animation if it's playing
	var anim_sprite = enemy.get_node_or_null("Sprite") as AnimatedSprite2D
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
		print("   ✅ %s: Unstuck complete, resuming %s" % [enemy.name, get_state_name_for_state(unstuck_state_before)])

		# Resume original state
		if unstuck_state_before == State.PATROLLING:
			# Always pick a NEW patrol target after unstuck to avoid walking back into the same obstacle
			pick_new_patrol_target()
			change_state(State.PATROLLING)

		elif unstuck_state_before == State.COMBAT:
			# Resume combat (will automatically chase player)
			change_state(State.COMBAT)
		else:
			# Fallback: return to patrol
			change_state(State.PATROLLING)

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

	# Play attack sound IMMEDIATELY (before animation) with spam prevention
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_attack_sound_time >= attack_sound_cooldown:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.SKELETON_ATTACK, enemy.global_position, -8.0)
			last_attack_sound_time = current_time

	# Play attack animation
	var anim_sprite = enemy.get_node_or_null("Sprite") as AnimatedSprite2D
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
			# ✨ FIX: Don't flip! We have dedicated directional attack animations
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

	# Deal damage
	if player.has_method("take_damage"):
		var damage = attack_damage
		if enemy.has_method("get") and enemy.get("enemy_level"):
			damage = attack_damage * pow(1.08, enemy.enemy_level - 1)

		player.take_damage(damage)

	# ✨ FIX: Enhanced visual feedback for attack
	if is_instance_valid(enemy):
		var original_scale = enemy.scale
		var tween = enemy.create_tween()
		tween.set_parallel(false)  # Sequential animations

		# Bigger scale pulse (30% instead of 15%)
		tween.tween_property(enemy, "scale", original_scale * 1.3, 0.1)
		tween.tween_property(enemy, "scale", original_scale, 0.15)

		# Shake/wobble effect
		var rot_tween = enemy.create_tween()
		rot_tween.set_parallel(false)
		rot_tween.tween_property(enemy, "rotation_degrees", -8, 0.05)
		rot_tween.tween_property(enemy, "rotation_degrees", 8, 0.05)
		rot_tween.tween_property(enemy, "rotation_degrees", 0, 0.05)

	# Reset attack flag (allow next attack)
	is_performing_attack = false

# ═══════════════════════════════════════════════════════════════════════════
# AGGRO SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func trigger_aggro() -> void:
	"""Called when player enters aggro range - enemy charges!"""
	if is_in_combat:
		return  # Already in combat

	print("👁️ %s: AGGRO! Spotted player" % enemy.name)
	is_in_combat = true

	# Play aggro sound (menacing skeleton cackle) with spam prevention
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_aggro_sound_time >= aggro_sound_cooldown:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.SKELETON_AGGRO, enemy.global_position, -5.0)
		last_aggro_sound_time = current_time

	# Chain aggro - alert nearby allies!
	trigger_chain_aggro()

	# Enter combat immediately
	if current_state == State.PATROLLING:
		change_state(State.COMBAT)

func trigger_chain_aggro() -> void:
	"""Alert nearby enemies to join the fight (creates trains!)"""
	# Performance: Use Area2D query instead of checking all enemies
	var space_state = enemy.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = enemy.global_position
	query.collision_mask = 1  # Layer 1 for enemies

	# Simple proximity check - just get enemies within range
	var nearby_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var checked = 0

	for other_enemy in nearby_enemies:
		if not is_instance_valid(other_enemy) or other_enemy == enemy:
			continue

		# Early out if too far (square distance check is faster)
		var dx = other_enemy.global_position.x - enemy.global_position.x
		var dy = other_enemy.global_position.y - enemy.global_position.y
		var dist_squared = dx * dx + dy * dy
		var range_squared = chain_aggro_range * chain_aggro_range

		if dist_squared <= range_squared:
			# Alert the nearby enemy's AI
			if other_enemy.has_node("EnemyAI"):
				var other_ai = other_enemy.get_node("EnemyAI")
				if other_ai.has_method("trigger_aggro") and not other_ai.is_in_combat:
					print("   ⚡ Chain aggro: %s joins the fight!" % other_enemy.name)
					other_ai.trigger_aggro()
					checked += 1
					if checked >= 5:  # Max 5 chain aggros at once
						break

# ═══════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_enemy_damaged(damage: float, is_crit: bool) -> void:
	"""Called when enemy takes damage - this triggers combat!"""

	# CRITICAL: This is how we enter combat (player attacked us)
	if not is_in_combat:
		print("⚔️ %s: Engaged! (Player attacked)" % enemy.name)
		is_in_combat = true

		# Chain aggro - alert nearby allies when attacked!
		trigger_chain_aggro()

		# Enter combat immediately
		if current_state == State.PATROLLING:
			change_state(State.COMBAT)
	
	# Already in combat - chance to retreat
	elif current_state != State.RETREATING:
		# Don't retreat during crit window - stand and fight!
		if enemy.has_method("get") and enemy.get("in_crit_window"):
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

			print("🏃 %s: Retreating!" % enemy.name)
			change_state(State.RETREATING)

func disengage() -> void:
	"""Exit combat and return to patrol"""
	print("🔄 %s: Disengaging, resetting health" % enemy.name)
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
				var health_bar = enemy.get_node("HealthBar")
				if health_bar.has_method("update_health"):
					health_bar.update_health(max_hp, max_hp)
		else:
			push_error("❌ Cannot reset enemy health - invalid max_health: %s" % str(max_hp))

	# Return to original spawn position (don't stay where we are!)
	spawn_position = original_spawn_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)

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
				var health_bar = enemy.get_node("HealthBar")
				if health_bar.has_method("update_health"):
					health_bar.update_health(max_hp, max_hp)
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
	return "UNKNOWN"

func update_enemy_animation(velocity: Vector2) -> void:
	"""Update enemy animation based on movement"""
	var anim_sprite = enemy.get_node_or_null("Sprite") as AnimatedSprite2D
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
		if anim_name.begins_with("walk_"):
			var current_frame = anim_sprite.frame
			if current_frame in [1, 3, 5, 7] and current_frame != last_footstep_frame:
				last_footstep_frame = current_frame
				play_enemy_footstep()

		# ✨ FIX: Don't flip sprites! We have dedicated directional animations.
		# Each row (up, left, down, right) is pre-drawn facing that direction.
		# Flipping would make them face the wrong way.
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
		var all_enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

		for other_enemy in all_enemies:
			if other_enemy == enemy or not is_instance_valid(other_enemy):
				continue

			var other_distance = other_enemy.global_position.distance_to(camera_pos)
			if other_distance < closest_distance:
				# Found a closer skeleton, don't play sound for this one
				closest_distance = other_distance

		# Only play sound if this is the closest skeleton
		if closest_distance == distance:
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager:
				sound_manager.play_skeleton_footstep(enemy.global_position, camera_pos)

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
	const CHUNK_SIZE = 3000.0
	var chunk_x = int(floor(position.x / CHUNK_SIZE))
	return "%d,0" % chunk_x  # Y is always 0 (horizontal chunks only)
