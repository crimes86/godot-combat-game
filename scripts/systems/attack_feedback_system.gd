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
func trigger_attack_feedback(target_position: Vector2, is_critical: bool = false, hit_weakpoint: bool = false) -> void:
	if not player:
		return
	
	# 1. Spawn particle visual
	spawn_particle_slash(target_position, is_critical)
	
	# 2. Screen shake (extra for weakpoint hits)
	trigger_screen_shake(is_critical, hit_weakpoint)

## Spawn blood splatter effect at target
func spawn_particle_slash(target_position: Vector2, is_critical: bool) -> void:
	# Calculate direction from player to target (blood splatters away from hit)
	var direction = (target_position - player.global_position).normalized()

	# Create blood splatter particles at enemy position
	var blood = CPUParticles2D.new()
	blood.global_position = target_position
	blood.rotation = direction.angle()

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

## Trigger screen shake
func trigger_screen_shake(is_critical: bool, hit_weakpoint: bool) -> void:
	if not screen_shake:
		return
	
	if hit_weakpoint:
		# Heavy shake for weakpoint hits
		screen_shake.add_trauma(0.6)
	elif is_critical:
		# Medium shake for crits
		screen_shake.add_trauma(0.4)
	else:
		# Light shake for normal hits
		screen_shake.add_trauma(0.2)
