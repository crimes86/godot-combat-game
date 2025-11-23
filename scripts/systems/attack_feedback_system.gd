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

## Spawn particle slash
func spawn_particle_slash(target_position: Vector2, is_critical: bool) -> void:
	# Calculate direction
	var direction = (target_position - player.global_position).normalized()
	
	# Create particles
	var slash = CPUParticles2D.new()
	slash.global_position = player.global_position
	slash.rotation = direction.angle()
	
	# Configure based on crit
	if is_critical:
		# Gold critical particles
		slash.amount = 40
		slash.color = Color(1, 0.9, 0.3, 1)
		slash.scale_amount_min = 3.0
		slash.scale_amount_max = 6.0
		slash.initial_velocity_min = 100.0
		slash.initial_velocity_max = 150.0
	else:
		# White normal particles
		slash.amount = 25
		slash.color = Color(1, 1, 1, 1)
		slash.scale_amount_min = 2.0
		slash.scale_amount_max = 4.0
		slash.initial_velocity_min = 80.0
		slash.initial_velocity_max = 120.0
	
	# Common properties
	slash.emitting = true
	slash.one_shot = true
	slash.lifetime = 0.25  # Fast animation
	slash.speed_scale = 4.0  # Very fast
	slash.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	slash.emission_sphere_radius = 10.0
	slash.spread = 45.0
	slash.gravity = Vector2.ZERO
	
	# Add to scene
	player.get_parent().add_child(slash)
	
	# Quick cleanup
	await player.get_tree().create_timer(0.3).timeout
	if is_instance_valid(slash):
		slash.queue_free()

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
