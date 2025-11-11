extends Node
class_name PlayerCombat

## Handles player combat including attacks, crit rolls, and chain system
## Separated from Player.gd for modularity

signal attack_performed()
signal enemy_hit(enemy: Node, damage: float, is_crit: bool)

@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 0.10
@export var attack_range: float = 100.0
@export var attack_cone_angle: float = 90.0
@export var hold_attack_interval: float = 0.13

var can_attack: bool = true
var attack_direction: Vector2 = Vector2.RIGHT
var is_mouse_held: bool = false
var hold_attack_timer: float = 0.0

var player_body: CharacterBody2D
var crit_system: Node
var crit_window_manager: Node
var attack_feedback: AttackFeedbackSystem

func _ready() -> void:
	player_body = get_parent() as CharacterBody2D
	if not player_body:
		push_error("PlayerCombat must be a child of CharacterBody2D")
		return

	# Find combat systems
	crit_system = player_body.get_node_or_null("CritSystem")
	crit_window_manager = player_body.get_node_or_null("CritWindowManager")

	# Find or create attack feedback system
	attack_feedback = player_body.get_node_or_null("AttackFeedbackSystem") as AttackFeedbackSystem

func set_attack_stats(damage: float, cooldown: float) -> void:
	"""Update attack damage and cooldown"""
	attack_damage = damage
	attack_cooldown = cooldown

func process_hold_attack(delta: float) -> void:
	"""Process held mouse button for continuous attacks"""
	if is_mouse_held and can_attack:
		hold_attack_timer += delta
		if hold_attack_timer >= hold_attack_interval:
			attempt_attack()
			hold_attack_timer = 0.0

func attempt_attack() -> void:
	"""Perform a cone attack in the direction of the mouse"""
	if not can_attack:
		return

	can_attack = false

	# Update attack direction to mouse position
	var mouse_pos: Vector2 = player_body.get_global_mouse_position()
	attack_direction = (mouse_pos - player_body.global_position).normalized()

	# Trigger attack animation via appearance system
	var anim_sprite: AnimatedSprite2D = player_body.get_node_or_null("PlayerSprite") as AnimatedSprite2D
	if anim_sprite:
		var dir_str: String = _get_direction_string(attack_direction)
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("attack_" + dir_str):
			anim_sprite.play("attack_" + dir_str)

	# Register attack with chain system
	ChainManager.register_attack()

	# Get enemies in attack cone
	var enemies_in_cone: Array = get_enemies_in_cone()

	# Play swing sound
	SoundManager.play_sound(SoundManager.SoundType.SWING, player_body.global_position, -8.0)

	if enemies_in_cone.size() > 0:
		attack_enemies_in_cone(enemies_in_cone)
	else:
		# Play miss sound
		SoundManager.play_sound(SoundManager.SoundType.MISS, player_body.global_position, -10.0)

	finish_attack_cooldown()
	attack_performed.emit()

func get_enemies_in_cone() -> Array:
	"""Get all enemies within the attack cone"""
	var enemies_in_cone: Array = []
	var all_enemies: Array = player_body.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var cone_half_angle_rad: float = deg_to_rad(attack_cone_angle / 2.0)
	var forward_direction: Vector2 = attack_direction

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		# Get enemy size for better detection
		var enemy_radius: float = 30.0
		if enemy.has_node("CollisionShape2D"):
			var collision: CollisionShape2D = enemy.get_node("CollisionShape2D")
			if collision.shape is RectangleShape2D:
				var rect: RectangleShape2D = collision.shape as RectangleShape2D
				enemy_radius = max(rect.size.x, rect.size.y) * enemy.scale.x / 2.0

		# Check distance to enemy edge
		var distance_to_center: float = player_body.global_position.distance_to(enemy.global_position)
		var distance_to_edge: float = distance_to_center - enemy_radius

		if distance_to_edge > attack_range:
			continue

		# Check if enemy is within cone angle
		var to_enemy: Vector2 = (enemy.global_position - player_body.global_position).normalized()
		var angle_diff: float = forward_direction.angle_to(to_enemy)
		var angular_tolerance: float = atan2(enemy_radius, distance_to_center)

		if abs(angle_diff) <= cone_half_angle_rad + angular_tolerance:
			enemies_in_cone.append(enemy)

	return enemies_in_cone

func attack_enemies_in_cone(enemies: Array) -> void:
	"""Apply damage to all enemies in the attack cone"""
	var chain_multiplier: float = ChainManager.get_damage_multiplier()

	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue

		# Connect to enemy signals
		_connect_enemy_signals(enemy)

		# Check if enemy already in crit window
		var enemy_already_in_crit_window: bool = false
		if "in_crit_window" in enemy:
			enemy_already_in_crit_window = enemy.in_crit_window

		var damage: float = attack_damage * chain_multiplier

		# Only roll for crit if enemy not already in crit window
		if not enemy_already_in_crit_window and crit_system:
			var is_crit: bool = crit_system.roll_for_crit()

			if is_crit and crit_window_manager:
				# Start crit window
				crit_window_manager.start_window(enemy)
				if not crit_window_manager.window_completed.is_connected(_on_crit_window_completed):
					crit_window_manager.window_completed.connect(_on_crit_window_completed.bind(enemy))
			else:
				# Normal attack
				_apply_damage_with_feedback(enemy, damage, false, false)
		else:
			# Normal damage (no new crit roll)
			_apply_damage_with_feedback(enemy, damage, false, false)

func _connect_enemy_signals(enemy: Node) -> void:
	"""Connect to enemy damage and weakpoint signals"""
	if enemy.has_signal("weakpoint_hit_success"):
		if not enemy.weakpoint_hit_success.is_connected(_on_weakpoint_hit):
			enemy.weakpoint_hit_success.connect(_on_weakpoint_hit.bind(enemy))

	if enemy.has_signal("damage_taken"):
		if not enemy.damage_taken.is_connected(_on_enemy_damaged):
			enemy.damage_taken.connect(_on_enemy_damaged.bind(enemy))

func _on_weakpoint_hit(enemy: Node) -> void:
	"""Handle weakpoint hit feedback"""
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, true, true)

func _on_enemy_damaged(damage: float, is_crit: bool, enemy: Node) -> void:
	"""Handle enemy damage feedback"""
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, false)
	enemy_hit.emit(enemy, damage, is_crit)

func _apply_damage_with_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
	"""Apply damage to enemy and trigger feedback"""
	enemy.take_damage(damage, is_crit)

	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, hit_weakpoint)

	enemy_hit.emit(enemy, damage, is_crit)

func _on_crit_window_completed(success_ratio: float, total_destroyed: int, enemy: Node) -> void:
	"""Handle completed crit window"""
	var damage: float = attack_damage * ChainManager.get_damage_multiplier()
	var final_damage: float = damage * (1.0 + success_ratio)

	# Apply the boosted damage
	if is_instance_valid(enemy) and enemy.has_method("take_damage"):
		enemy.take_damage(final_damage, true)

	# Trigger feedback
	if attack_feedback:
		attack_feedback.trigger_attack_feedback(enemy.global_position, true, total_destroyed > 0)

	enemy_hit.emit(enemy, final_damage, true)

func finish_attack_cooldown() -> void:
	"""Reset attack cooldown"""
	await player_body.get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _get_direction_string(dir: Vector2) -> String:
	"""Convert direction vector to animation string"""
	if abs(dir.x) > abs(dir.y):
		return "right" if dir.x > 0 else "left"
	else:
		return "down" if dir.y > 0 else "up"

func get_attack_direction() -> Vector2:
	"""Get current attack direction"""
	return attack_direction
