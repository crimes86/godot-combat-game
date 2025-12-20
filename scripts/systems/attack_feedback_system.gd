extends Node
class_name AttackFeedbackSystem

## Centralized Attack Feedback System
## Ensures EVERY attack gets visual/audio/shake feedback

var player: Node = null
var screen_shake: Node = null

func _ready() -> void:
	# Get player reference
	await get_tree().process_frame
	player = get_parent()
	
	# Get screen shake
	if player.has_node("ScreenShake"):
		screen_shake = player.get_node("ScreenShake")

## Main function - call this for EVERY attack
func trigger_attack_feedback(target_position: Vector2, is_critical: bool = false, _hit_weakpoint: bool = false) -> void:
	if not player:
		return

	# Spawn particle visual (blood splatter / sparks)
	spawn_particle_slash(target_position, is_critical)

	# NOTE: Screen shake removed - enemy stagger provides enough feedback

## Spawn blood splatter effect at target
func spawn_particle_slash(target_position: Vector2, is_critical: bool) -> void:
	# Calculate direction from player to target (blood splatters away from hit)
	var direction = (target_position - player.global_position).normalized()

	# Create blood splatter particles at enemy position
	var blood = CPUParticles2D.new()
	blood.global_position = target_position
	blood.rotation = direction.angle()
	blood.z_index = 100  # Render above enemy sprites

	# Configure based on crit
	if is_critical:
		# More dramatic gold/yellow sparks for crits (keep crits special)
		blood.amount = 12
		blood.color = Color(1, 0.85, 0.2, 1)  # Golden sparks
		blood.scale_amount_min = 2.0
		blood.scale_amount_max = 4.0
		blood.initial_velocity_min = 60.0
		blood.initial_velocity_max = 100.0
	else:
		# Dark red blood splatter for normal hits
		blood.amount = 8
		blood.color = Color(0.6, 0.05, 0.05, 0.9)  # Dark blood red
		blood.scale_amount_min = 1.5
		blood.scale_amount_max = 3.0
		blood.initial_velocity_min = 40.0
		blood.initial_velocity_max = 80.0

	# Common properties - particles spray away from player
	blood.emitting = true
	blood.one_shot = true
	blood.lifetime = 0.3
	blood.speed_scale = 2.5
	blood.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	blood.spread = 60.0  # Wider spread for splatter effect
	blood.gravity = Vector2(0, 150)  # Slight downward gravity for realism
	blood.damping_min = 50.0
	blood.damping_max = 100.0  # Slow down quickly

	# Add to scene
	player.get_parent().add_child(blood)

	# Quick cleanup
	await player.get_tree().create_timer(0.5).timeout
	if is_instance_valid(blood):
		blood.queue_free()

## Trigger screen shake based on hit type
func trigger_screen_shake(is_critical: bool, hit_weakpoint: bool) -> void:
	if not screen_shake:
		return

	if hit_weakpoint:
		screen_shake.add_trauma(0.5)  # Medium-heavy for weakpoints
	elif is_critical:
		screen_shake.add_trauma(0.35)  # Medium for crits
	else:
		screen_shake.add_trauma(0.15)  # Light for normal hits

## Spawn damage number at target position (used for PvP and PvE)
func spawn_damage_number(world_pos: Vector2, damage: float, is_crit: bool = false, hit_weakpoint: bool = false) -> void:
	if not player:
		return

	# Get parent for spawning (game world)
	var spawn_parent = player.get_parent()
	if not spawn_parent:
		return

	# Use CombatText factory methods
	if hit_weakpoint:
		CombatText.create_weakpoint(damage, world_pos, spawn_parent)
	elif is_crit:
		CombatText.create_crit(damage, world_pos, spawn_parent)
	else:
		CombatText.create_normal(damage, world_pos, spawn_parent)

## Spawn heal number at target position
func spawn_heal_number(world_pos: Vector2, amount: float) -> void:
	if not player:
		return

	var spawn_parent = player.get_parent()
	if not spawn_parent:
		return

	CombatText.create_heal(amount, world_pos, spawn_parent)

## Spawn weapon swoosh/trail effect on attack swing
func spawn_weapon_swoosh(attack_direction: Vector2) -> void:
	if not player:
		return

	var spawn_parent = player.get_parent()
	if not spawn_parent:
		return

	# Create swoosh arc using Line2D
	var swoosh = Line2D.new()
	swoosh.width = 8.0
	swoosh.default_color = Color(1.0, 1.0, 1.0, 0.7)  # White with transparency
	swoosh.z_index = 50  # Above player but below UI
	swoosh.begin_cap_mode = Line2D.LINE_CAP_ROUND
	swoosh.end_cap_mode = Line2D.LINE_CAP_ROUND
	swoosh.antialiased = true

	# Create width curve - thick at start, thin at end
	var width_curve = Curve.new()
	width_curve.add_point(Vector2(0, 1.0))
	width_curve.add_point(Vector2(0.3, 0.8))
	width_curve.add_point(Vector2(1.0, 0.1))
	swoosh.width_curve = width_curve

	# Create gradient - white to transparent
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	swoosh.gradient = gradient

	# Calculate arc points
	var arc_radius = 45.0  # Distance from player
	var arc_angle = PI * 0.6  # ~108 degree arc
	var base_angle = attack_direction.angle()

	# Generate arc points (sweep from one side to the other)
	var num_points = 12
	for i in range(num_points):
		var t = float(i) / float(num_points - 1)
		var angle = base_angle - arc_angle / 2.0 + arc_angle * t
		var point = Vector2(cos(angle), sin(angle)) * arc_radius
		swoosh.add_point(point)

	# Position at player center
	swoosh.global_position = player.global_position

	spawn_parent.add_child(swoosh)

	# Animate: expand slightly and fade out
	var tween = spawn_parent.create_tween()
	tween.set_parallel(true)
	tween.tween_property(swoosh, "modulate:a", 0.0, 0.15)
	tween.tween_property(swoosh, "scale", Vector2(1.3, 1.3), 0.15)

	# Cleanup
	tween.finished.connect(func():
		if is_instance_valid(swoosh):
			swoosh.queue_free()
	)
