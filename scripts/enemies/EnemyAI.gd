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
@export var patrol_speed: float = 30.0
@export var patrol_radius: float = 100.0
@export var patrol_pause_min: float = 2.0
@export var patrol_pause_max: float = 5.0

## Combat (triggered by player attack)
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
	RETREATING    # Tactical: backing away
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
var patrol_target: Vector2 = Vector2.ZERO
var is_paused: bool = false
var pause_timer: float = 0.0

# Combat state
var is_in_combat: bool = false  # CRITICAL: Only true after player attacks
var attack_timer: float = 0.0
var retreat_direction: Vector2 = Vector2.ZERO

# Stuck detection
var last_position: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var stuck_check_interval: float = 5.0  # Check every 5 seconds (longer to avoid false positives)
var stuck_distance_threshold: float = 10.0  # If moved less than this in 5 seconds, considered stuck

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
	last_position = enemy.global_position  # Initialize stuck detection
	
	# Connect to damage signal to detect player attacks
	if enemy.has_signal("damage_taken"):
		enemy.damage_taken.connect(_on_enemy_damaged)
	
	# Scale speed with level
	if enemy.has_method("get") and enemy.get("enemy_level"):
		var level = enemy.enemy_level
		combat_speed = 100.0 * pow(1.05, level - 1)
		patrol_speed = 30.0 * pow(1.03, level - 1)
	
	# Start patrolling
	pick_new_patrol_target()
	change_state(State.PATROLLING)

	# Create debug label (always created, visibility controlled by player debug mode)
	create_debug_label()

	print("🤖 Enemy AI initialized - Patrolling (non-aggro)")

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

	# Find player if needed
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)

	# Update debug label visibility based on player debug mode
	if debug_label and player:
		debug_label.visible = player.get("debug_mode") == true
		if debug_label.visible:
			update_debug_label_position()

	# Check for stuck (only when patrolling, not in combat, and not paused)
	if current_state == State.PATROLLING and not is_in_combat and not is_paused:
		stuck_timer += delta
		if stuck_timer >= stuck_check_interval:
			var distance_moved = enemy.global_position.distance_to(last_position)
			# Also check if we're actually trying to move (velocity is non-zero)
			var is_trying_to_move = enemy.velocity.length() > 5.0
			if distance_moved < stuck_distance_threshold and is_trying_to_move:
				# We're stuck! Physically move backwards and shift on Y axis
				print("⚠️ Enemy stuck (moved %.1f in %.1fs), trying to unstick" % [distance_moved, stuck_check_interval])

				# Move backwards (opposite of current velocity direction)
				var backward_direction = -enemy.velocity.normalized()
				enemy.global_position += backward_direction * 30.0  # Move back 30 pixels

				# Shift up or down on Y axis randomly
				var y_shift = randf_range(-40.0, 40.0)
				enemy.global_position.y += y_shift

				print("  🔄 Moved backwards %.0f pixels, Y shift %.0f" % [30.0, y_shift])

				# Pick a new patrol target
				pick_new_patrol_target()
				is_paused = false  # Unpause if we were paused
			last_position = enemy.global_position
			stuck_timer = 0.0
	else:
		# Reset stuck timer when not actively patrolling
		stuck_timer = 0.0
		last_position = enemy.global_position

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

# ═══════════════════════════════════════════════════════════════════════════
# PATROLLING STATE (Default - Non-Aggro)
# ═══════════════════════════════════════════════════════════════════════════

func process_patrolling(delta: float) -> void:
	# If player attacked us, enter combat
	if is_in_combat and player:
		change_state(State.COMBAT)
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
	
	var distance_to_player = enemy.global_position.distance_to(player.global_position)
	
	# Account for enemy's enlarged size during crit window
	var effective_attack_range = attack_range
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		effective_attack_range = attack_range * 2.0  # 60 * 2 = 120
	
	# Check if player escaped
	if distance_to_player > disengage_distance:
		print("💤 Player escaped - returning to patrol")
		disengage()
		return
	
	# Check if in attack range (adjusted for crit window)
	if distance_to_player < effective_attack_range:
		change_state(State.ATTACKING)
		return
	
	# Chase player
	var direction = (player.global_position - enemy.global_position).normalized()
	enemy.velocity = direction * combat_speed
	update_enemy_animation(direction)
	enemy.move_and_slide()

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
	
	# Attack when ready AND in range
	if attack_timer <= 0 and distance_to_player <= effective_attack_range:
		perform_attack()
		attack_timer = attack_cooldown

# ═══════════════════════════════════════════════════════════════════════════
# RETREATING STATE (Tactical Retreat)
# ═══════════════════════════════════════════════════════════════════════════

func process_retreating(delta: float) -> void:
	# Retreat for duration
	if state_timer > retreat_duration:
		change_state(State.COMBAT)
		return
	
	# Move away from player
	enemy.velocity = retreat_direction * combat_speed * 1.2
	update_enemy_animation(retreat_direction)
	enemy.move_and_slide()

# ═══════════════════════════════════════════════════════════════════════════
# COMBAT ACTIONS
# ═══════════════════════════════════════════════════════════════════════════

func perform_attack() -> void:
	"""Attack the player"""
	if not is_instance_valid(player):
		return
	
	print("💥 Enemy attacks!")
	
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
			print("   🎬 Playing attack animation: ", attack_anim)
			anim_sprite.play(attack_anim)
			# ✨ FIX: Don't flip! We have dedicated directional attack animations
			anim_sprite.flip_h = false
	
	# ✨ Small delay for attack animation to play before dealing damage
	await get_tree().create_timer(0.2).timeout
	
	# Deal damage
	if player.has_method("take_damage"):
		var damage = attack_damage
		if enemy.has_method("get") and enemy.get("enemy_level"):
			damage = attack_damage * pow(1.08, enemy.enemy_level - 1)
		
		player.take_damage(damage)
		print("   Dealt %.1f damage to player" % damage)
	
	# ✨ FIX: Enhanced visual feedback for attack
	if enemy:
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
	
	# Play sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.HIT_NORMAL, enemy.global_position, -8.0)

# ═══════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_enemy_damaged(damage: float, is_crit: bool) -> void:
	"""Called when enemy takes damage - this triggers combat!"""
	
	# CRITICAL: This is how we enter combat (player attacked us)
	if not is_in_combat:
		print("⚔️  Enemy engaged! Player attacked first!")
		is_in_combat = true
		
		# Enter combat immediately
		if current_state == State.PATROLLING:
			change_state(State.COMBAT)
	
	# Already in combat - chance to retreat
	elif current_state != State.RETREATING:
		var retreat_roll = retreat_chance
		if is_crit:
			retreat_roll += 0.2  # +20% on crit
		
		if randf() < retreat_roll:
			# Calculate retreat direction
			if is_instance_valid(player):
				retreat_direction = (enemy.global_position - player.global_position).normalized()
			else:
				retreat_direction = Vector2(randf() * 2 - 1, randf() * 2 - 1).normalized()
			
			print("🏃 Enemy retreats!")
			change_state(State.RETREATING)

func disengage() -> void:
	"""Exit combat and return to patrol"""
	is_in_combat = false
	spawn_position = enemy.global_position  # New patrol center
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
		print("⚠️  reset_to_patrol called before enemy reference set, deferring...")
		await get_tree().process_frame
		if not enemy or not is_instance_valid(enemy):
			print("⚠️  Enemy still not valid, aborting reset")
			return
	
	# CRITICAL: Don't reset if enemy is in crit window - let it keep fighting!
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		print("⚠️  Enemy in crit window - staying in combat!")
		return
	
	is_in_combat = false
	spawn_position = enemy.global_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)
	print("🔄 Enemy reset to patrol mode")

func disengage_to_spawn() -> void:
	"""Disengage from combat and return to ORIGINAL spawn point (for campfire de-aggro)"""
	# Safety check
	if not enemy or not is_instance_valid(enemy):
		return
	
	# CRITICAL: Don't reset if enemy is in crit window - let it keep fighting!
	if enemy.has_method("get") and enemy.get("in_crit_window"):
		print("⚠️  Enemy in crit window - staying in combat!")
		return
	
	is_in_combat = false
	# Reset to ORIGINAL spawn position (not current position)
	spawn_position = original_spawn_position
	pick_new_patrol_target()
	change_state(State.PATROLLING)
	print("🔄 Enemy disengaged - returning to original spawn")

func get_state_name() -> String:
	match current_state:
		State.PATROLLING: return "PATROLLING"
		State.COMBAT: return "COMBAT"
		State.ATTACKING: return "ATTACKING"
		State.RETREATING: return "RETREATING"
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
		
		# ✨ FIX: Don't flip sprites! We have dedicated directional animations.
		# Each row (up, left, down, right) is pre-drawn facing that direction.
		# Flipping would make them face the wrong way.
		anim_sprite.flip_h = false

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
