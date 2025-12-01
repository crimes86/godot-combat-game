class_name PlayerCombat
extends RefCounted
## Handles player combat: attacks, healing, crit windows, damage dealing
## Used as inner class by Player.gd
##
## INTEGRATION GUIDE:
## -----------------
## To use this subsystem in Player.gd:
##
## 1. Add to Player.gd variables:
##    var combat_system: PlayerCombat = null
##
## 2. In _ready():
##    combat_system = PlayerCombat.new(self)
##    combat_system.crit_system = crit_system
##    combat_system.crit_window_manager = crit_window_manager
##    combat_system.screen_shake = screen_shake
##    combat_system.attack_feedback = attack_feedback
##    combat_system.update_stats(attack_damage, attack_cooldown, attack_range, attack_cone_angle)
##
## 3. In _physics_process():
##    combat_system.process_held_attack(delta, get_global_mouse_position())
##
## 4. In _input() for mouse button:
##    if combat_system.on_mouse_pressed(get_global_mouse_position()):
##        return
##
## 5. Replace direct attack calls with:
##    combat_system.attempt_attack()
##    combat_system.attempt_heal()

var player: CharacterBody2D

# Combat state
var can_attack: bool = true
var attack_direction: Vector2 = Vector2.RIGHT
var is_mouse_held: bool = false
var hold_attack_timer: float = 0.0

# Combat stats (synced from CharacterStats via Player)
var attack_damage: float = Constants.PLAYER_BASE_ATTACK_DAMAGE
var attack_cooldown: float = Constants.PLAYER_ATTACK_COOLDOWN
var attack_range: float = Constants.PLAYER_ATTACK_RANGE
var attack_cone_angle: float = Constants.PLAYER_ATTACK_CONE_ANGLE
var hold_attack_interval: float = Constants.PLAYER_HOLD_ATTACK_INTERVAL

# References (set by Player)
var crit_system: Node = null
var crit_window_manager: Node = null
var screen_shake = null
var attack_feedback = null

# Debug
var debug_weakpoint_clicks: bool = false

# Tutorial forced crit tracking (single player)
var tutorial_dummy_hits: int = 0
const TUTORIAL_FORCE_CRIT_HITS: int = 5  # Force crit after this many hits on dummy during tutorial

func _init(player_ref: CharacterBody2D) -> void:
	player = player_ref

func update_stats(damage: float, cooldown: float, range_val: float = -1, cone_angle: float = -1) -> void:
	"""Update combat stats from CharacterStats"""
	attack_damage = damage
	attack_cooldown = cooldown
	if range_val > 0:
		attack_range = range_val
	if cone_angle > 0:
		attack_cone_angle = cone_angle

	# Update crit system base chance (preserves pity progress)
	if crit_system:
		crit_system.on_weapon_changed()

func process_held_attack(delta: float, mouse_pos: Vector2) -> void:
	"""Process continuous attack while mouse is held"""
	if not is_mouse_held:
		return

	hold_attack_timer += delta
	if hold_attack_timer >= hold_attack_interval:
		hold_attack_timer = 0.0

		# Check if using healing weapon
		if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
			if can_attack:
				attempt_heal()
		else:
			# Melee weapon - check crit window first
			if is_holding_on_crit_window_enemy(mouse_pos):
				pass  # Handled by crit window logic
			elif can_attack:
				attempt_attack()

func on_mouse_pressed(mouse_pos: Vector2) -> bool:
	"""Handle mouse button press. Returns true if attack was handled."""
	is_mouse_held = true
	hold_attack_timer = 0.0

	# Check if using a healing weapon
	if CharacterStats.equipped_weapon and CharacterStats.equipped_weapon.is_healing_weapon():
		attempt_heal()
		return true

	# Melee/damage weapon - check weakpoint first
	if is_clicking_on_weakpoint(mouse_pos):
		return true  # Let the weakpoint handle it

	# Try crit window click on enemy body
	if check_crit_window_click(mouse_pos):
		return true

	# Normal attack
	attempt_attack()
	return true

func on_mouse_released() -> void:
	"""Handle mouse button release"""
	is_mouse_held = false
	hold_attack_timer = 0.0

func check_crit_window_click(mouse_pos: Vector2) -> bool:
	"""Check if click should be handled by crit window system"""
	if not crit_window_manager:
		return false

	# Check all enemies in range for active crit windows
	var enemies = get_enemies_in_cone()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if enemy has an active crit window
		if crit_window_manager.has_method("has_active_window_for"):
			if crit_window_manager.has_active_window_for(enemy):
				# Check if click is on enemy body area
				var enemy_pos = enemy.global_position
				var click_dist = mouse_pos.distance_to(enemy_pos)

				# If clicking within enemy collision radius, trigger crit window attack
				if click_dist < 80.0:  # Generous click radius
					handle_crit_window_attack(enemy, mouse_pos)
					return true

	return false

func is_holding_on_crit_window_enemy(mouse_pos: Vector2) -> bool:
	"""Check if mouse is held over an enemy with active crit window"""
	if not crit_window_manager:
		return false

	var enemies = get_enemies_in_cone()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		if crit_window_manager.has_method("has_active_window_for"):
			if crit_window_manager.has_active_window_for(enemy):
				var enemy_pos = enemy.global_position
				var click_dist = mouse_pos.distance_to(enemy_pos)
				if click_dist < 80.0:
					handle_crit_window_attack(enemy, mouse_pos)
					return true

	return false

func is_clicking_on_weakpoint(mouse_pos: Vector2) -> bool:
	"""Check if clicking on weakpoint and trigger it directly"""
	var all_enemies = player.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	if debug_weakpoint_clicks:
		print("[WP_DEBUG] Checking %d enemies for weakpoint click at %s" % [all_enemies.size(), mouse_pos])

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		# Only check enemies in crit window
		var has_crit_prop = "in_crit_window" in enemy
		var crit_val = enemy.in_crit_window if has_crit_prop else false

		if debug_weakpoint_clicks:
			print("[WP_DEBUG] Enemy %s: has_crit=%s, in_crit=%s" % [enemy.name, has_crit_prop, crit_val])

		if not crit_val:
			continue

		# Check if any weakpoint is at the click position
		if "weakpoints" in enemy:
			if debug_weakpoint_clicks:
				print("[WP_DEBUG] Enemy %s has %d weakpoints" % [enemy.name, enemy.weakpoints.size()])

			for weakpoint in enemy.weakpoints:
				if not is_instance_valid(weakpoint):
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] Weakpoint invalid, skipping")
					continue
				if "is_destroyed" in weakpoint and weakpoint.is_destroyed:
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] Weakpoint destroyed, skipping")
					continue

				var distance = mouse_pos.distance_to(weakpoint.global_position)
				var weakpoint_radius = 28 * weakpoint.scale.x

				if debug_weakpoint_clicks:
					print("[WP_DEBUG] Weakpoint at %s, dist=%.1f, radius=%.1f" % [weakpoint.global_position, distance, weakpoint_radius])

				if distance < weakpoint_radius:
					if debug_weakpoint_clicks:
						print("[WP_DEBUG] HIT! Calling weakpoint.hit()")

					# Play slash animation toward the weakpoint
					var character_sprite = player.get_node_or_null("CharacterSprite")
					if character_sprite:
						var direction_to_weakpoint = (weakpoint.global_position - player.global_position).normalized()
						var dir_str = player.get_direction_string(direction_to_weakpoint)
						var lpc_dir = player.convert_to_lpc_direction(dir_str)
						character_sprite.play_lpc_animation("slash", lpc_dir)

					# CLIENT-PREDICTED: Call hit() directly for instant feedback
					# Server validates total damage at crit window end
					if weakpoint.has_method("hit"):
						weakpoint.hit()
					return true

	return false

func handle_crit_window_attack(enemy: Node, click_pos: Vector2) -> void:
	"""Handle attack during crit window (uncapped attack speed)"""
	if not is_instance_valid(enemy):
		return

	# Get crit window overlay from enemy
	var crit_overlay = enemy.get_node_or_null("CritWindowOverlay")
	if not crit_overlay:
		return

	# Try to hit a weakpoint at click position
	if crit_overlay.has_method("try_hit_weakpoint_at"):
		var hit = crit_overlay.try_hit_weakpoint_at(click_pos)
		if hit:
			# Weakpoint destroyed - crit damage!
			var crit_damage = attack_damage * 2.0  # 2x damage for crit
			apply_damage_with_feedback(enemy, crit_damage, true, true)
			return

	# No weakpoint hit - normal damage during crit window
	apply_damage_with_feedback(enemy, attack_damage, false, false)

func attempt_attack() -> void:
	"""Try to perform an attack"""
	if not can_attack:
		return

	can_attack = false
	# Sync to player for compatibility
	if player:
		player.can_attack = false

	# Play attack animation
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		var dir_str = player.get_direction_string(attack_direction)
		var lpc_dir = player.convert_to_lpc_direction(dir_str)
		character_sprite.play_lpc_animation("slash", lpc_dir)

	# Get enemies in attack cone
	var enemies = get_enemies_in_cone()

	if enemies.size() > 0:
		attack_enemies_in_cone(enemies)

	# Play weapon swing sound (whoosh)
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Play weapon-specific swing sound
		if CharacterStats.equipped_weapon:
			# Use sword swing sound for all weapon types (universal whoosh)
			sound_manager.play_sword_swing_sound(player.global_position, -10.0)
		else:
			# Unarmed swing
			sound_manager.play_unarmed_swing_sound(player.global_position, -10.0)

	# Start cooldown timer
	player.get_tree().create_timer(attack_cooldown).timeout.connect(finish_attack_cooldown)

func get_enemies_in_cone() -> Array:
	"""Get all enemies within attack cone"""
	var enemies_in_range = []
	var enemies = player.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check distance
		var distance = player.global_position.distance_to(enemy.global_position)
		if distance > attack_range:
			continue

		# Check angle (cone)
		var to_enemy = (enemy.global_position - player.global_position).normalized()
		var angle_diff = abs(attack_direction.angle_to(to_enemy))

		if angle_diff <= attack_cone_angle / 2.0:
			enemies_in_range.append(enemy)

	return enemies_in_range

func attack_enemies_in_cone(enemies: Array) -> void:
	"""Deal damage to enemies in attack cone"""
	var TutorialManager = player.get_node_or_null("/root/TutorialManager")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Roll for crit
		var is_crit = false
		var final_damage = attack_damage

		if crit_system and crit_system.has_method("roll_for_crit"):
			is_crit = crit_system.roll_for_crit()

			# Tutorial: force crit on training dummy after enough hits
			var is_training_dummy = enemy.is_in_group("training_dummy")
			if is_training_dummy and TutorialManager and TutorialManager.is_tutorial_active():
				tutorial_dummy_hits += 1
				if not is_crit and tutorial_dummy_hits >= TUTORIAL_FORCE_CRIT_HITS:
					is_crit = true
					tutorial_dummy_hits = 0  # Reset for next crit window
					print("🎯 FORCED CRIT for tutorial (hit dummy %d times)" % TUTORIAL_FORCE_CRIT_HITS)
				elif is_crit:
					tutorial_dummy_hits = 0  # Reset on natural crit

			if is_crit:
				var crit_mult = crit_system.get_crit_multiplier() if crit_system.has_method("get_crit_multiplier") else 2.0
				final_damage *= crit_mult

				# Play crit window opening sound
				var sound_manager = player.get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_sound"):
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -8.0)

				# Start crit window
				if crit_window_manager and crit_window_manager.has_method("start_window"):
					crit_window_manager.start_window(enemy)

		apply_damage_with_feedback(enemy, final_damage, is_crit, false)

func apply_damage_with_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
	"""Apply damage to enemy with visual/audio feedback"""
	if not is_instance_valid(enemy):
		return

	# Apply damage
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	# Damage number
	if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
		attack_feedback.spawn_damage_number(enemy.global_position, damage, is_crit, hit_weakpoint)

	# Screen shake on crit
	if is_crit and screen_shake:
		screen_shake.add_trauma(0.2)

	# Hit sound
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		if is_crit:
			sound_manager.play_critical_hit_sound(enemy.global_position, -6.0)
		else:
			sound_manager.play_normal_hit_sound(enemy.global_position, -10.0)

func finish_attack_cooldown() -> void:
	"""Reset attack cooldown"""
	can_attack = true
	# Sync back to player for compatibility with other code
	if player:
		player.can_attack = true

# ========================================
# HEALING SYSTEM
# ========================================

func attempt_heal() -> void:
	"""Try to perform a heal - delegates to Player's attempt_heal for full functionality"""
	if not can_attack:
		return

	# Verify we have a healing weapon equipped
	if not CharacterStats.equipped_weapon or not CharacterStats.equipped_weapon.is_healing_weapon():
		return

	# Set OUR can_attack to false - we'll manage the cooldown ourselves
	can_attack = false

	# Sync player.can_attack to TRUE so player.attempt_heal() doesn't block
	# (player.attempt_heal also checks can_attack, so we need it true)
	if player:
		player.can_attack = true

	# Delegate to Player's attempt_heal which has full projectile/mist/pulse logic
	if player.has_method("attempt_heal"):
		player.attempt_heal()

	# Start our own cooldown timer (Player's finish_attack_cooldown is async and won't sync back properly)
	player.get_tree().create_timer(attack_cooldown).timeout.connect(finish_attack_cooldown)

func get_allies_in_radius(center_pos: Vector2, radius: float) -> Array:
	"""Get all friendly players within radius"""
	var allies = []
	var players = player.get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	for p in players:
		if not is_instance_valid(p):
			continue
		if p == player:
			continue  # Skip self

		var distance = center_pos.distance_to(p.global_position)
		if distance <= radius:
			allies.append(p)

	return allies

func heal_allies(allies: Array, heal_amount: float) -> void:
	"""Heal all allies in array"""
	var sound_manager = player.get_node_or_null("/root/SoundManager")

	for ally in allies:
		if not is_instance_valid(ally):
			continue

		if ally.has_method("heal"):
			ally.heal(heal_amount)

		# Visual feedback
		if attack_feedback and attack_feedback.has_method("spawn_heal_number"):
			attack_feedback.spawn_heal_number(ally.global_position, heal_amount)

		# Play healing impact sound for each ally healed
		if sound_manager:
			sound_manager.play_healing_impact_sound(ally.global_position, -3.0)

var _last_heal_pulse_time: float = 0.0

func _spawn_heal_pulse(center_pos: Vector2, radius: float) -> void:
	"""Spawn heal visual effect"""
	# Rate limit to prevent spam
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_heal_pulse_time < 0.1:
		return
	_last_heal_pulse_time = current_time

	# Create heal pulse visual
	var pulse = Node2D.new()
	pulse.name = "HealPulse"
	pulse.global_position = center_pos
	pulse.z_index = 100

	# Create expanding circle
	var circle = Polygon2D.new()
	circle.color = Color(0.2, 0.8, 0.3, 0.4)  # Green

	# Build circle vertices
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 10)  # Start small
	circle.polygon = points
	pulse.add_child(circle)

	player.get_tree().root.add_child(pulse)

	# Animate expansion and fade
	var tween = player.get_tree().create_tween()
	tween.tween_property(circle, "scale", Vector2(radius / 10.0, radius / 10.0), 0.3)
	tween.parallel().tween_property(circle, "color:a", 0.0, 0.3)
	tween.tween_callback(pulse.queue_free)

# ========================================
# CRIT WINDOW CALLBACKS
# ========================================

func connect_enemy_signals(enemy: Node) -> void:
	"""Connect to enemy's combat signals"""
	if enemy.has_signal("weakpoint_hit"):
		if not enemy.weakpoint_hit.is_connected(_on_weakpoint_hit):
			enemy.weakpoint_hit.connect(_on_weakpoint_hit.bind(enemy))

func _on_weakpoint_hit(enemy: Node) -> void:
	"""Called when weakpoint is destroyed"""
	var crit_damage = attack_damage * 2.0
	apply_damage_with_feedback(enemy, crit_damage, true, true)

func _on_crit_window_completed(success_ratio: float, total_destroyed: int, enemy: Node) -> void:
	"""Called when crit window period ends"""
	if not is_instance_valid(enemy):
		return

	# Bonus damage based on success
	if success_ratio > 0.5:
		var bonus_damage = attack_damage * success_ratio
		apply_damage_with_feedback(enemy, bonus_damage, true, false)
