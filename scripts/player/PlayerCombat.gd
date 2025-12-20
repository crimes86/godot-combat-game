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

# VFX Layer reference for full-brightness weapon effects
var _vfx_layer: Node = null

func _add_vfx(effect: Node) -> void:
	"""Add visual effect to VFX layer (renders at full brightness, ignores CanvasModulate)"""
	if not _vfx_layer:
		_vfx_layer = player.get_node_or_null("/root/VFXLayer")
	if _vfx_layer and _vfx_layer.has_method("add_effect"):
		_vfx_layer.add_effect(effect)
	else:
		# Fallback to root if VFXLayer not available
		player.get_tree().root.add_child(effect)

# Tutorial forced crit tracking (single player)
var tutorial_dummy_hits: int = 0
const TUTORIAL_FORCE_CRIT_HITS: int = 5  # Force crit after this many hits on dummy during tutorial

# Burst fire state (for battle rifle, etc.)
var is_burst_firing: bool = false
var burst_shots_remaining: int = 0
var burst_target_pos: Vector2 = Vector2.ZERO
var burst_damage_per_shot: float = 0.0
var burst_crit_used: bool = false  # Only one shot per burst can crit

func _init(player_ref: CharacterBody2D) -> void:
	player = player_ref

func update_stats(damage: float, cooldown: float, range_val: float = -1, cone_angle: float = -1) -> void:
	"""Update combat stats from CharacterStats"""
	attack_damage = damage
	attack_cooldown = cooldown
	# Sync hold_attack_interval to weapon cooldown (held attacks match weapon speed)
	hold_attack_interval = cooldown
	if range_val > 0:
		attack_range = range_val
	if cone_angle > 0:
		attack_cone_angle = cone_angle

func process_held_attack(delta: float, mouse_pos: Vector2) -> void:
	"""Process continuous attack while mouse is held"""
	if not is_mouse_held:
		return

	hold_attack_timer += delta
	if hold_attack_timer >= hold_attack_interval:
		hold_attack_timer = 0.0

		# Check weapon type and route appropriately
		if CharacterStats.equipped_weapon:
			if CharacterStats.equipped_weapon.is_healing_weapon():
				# Healing staff
				if can_attack:
					attempt_heal()
			elif CharacterStats.equipped_weapon.is_gun_weapon():
				# Gun - check weakpoint first (uncapped attack speed on weakpoints)
				if try_gun_weakpoint_attack(mouse_pos):
					pass  # Hit weakpoint - no cooldown needed
				elif can_attack and not is_burst_firing:
					# Check for burst weapon (battle rifle) vs single shot (railgun)
					if CharacterStats.equipped_weapon.is_burst_weapon():
						attempt_burst_attack()
					else:
						attempt_gun_attack()
			elif CharacterStats.equipped_weapon.is_bow_weapon():
				# Bow - check weakpoint first (uncapped attack speed on weakpoints)
				if try_bow_weakpoint_attack(mouse_pos):
					pass  # Hit weakpoint - no cooldown needed
				elif can_attack:
					attempt_bow_attack()
			else:
				# Melee weapon - check crit window first
				if is_holding_on_crit_window_enemy(mouse_pos):
					pass  # Handled by crit window logic
				elif can_attack:
					attempt_attack()
		else:
			# No weapon (unarmed) - melee
			if is_holding_on_crit_window_enemy(mouse_pos):
				pass
			elif can_attack:
				attempt_attack()

func on_mouse_pressed(mouse_pos: Vector2) -> bool:
	"""Handle mouse button press. Returns true if attack was handled."""
	is_mouse_held = true
	hold_attack_timer = 0.0

	# Check weapon type and route appropriately
	if CharacterStats.equipped_weapon:
		if CharacterStats.equipped_weapon.is_healing_weapon():
			# Healing staff
			attempt_heal()
			return true
		elif CharacterStats.equipped_weapon.is_gun_weapon():
			# Gun - check for weakpoint hit first (uncapped attack speed on weakpoints)
			if try_gun_weakpoint_attack(mouse_pos):
				return true  # Hit weakpoint - no cooldown
			# Check for burst weapon (battle rifle) vs single shot (railgun)
			if CharacterStats.equipped_weapon.is_burst_weapon():
				attempt_burst_attack()
			else:
				attempt_gun_attack()
			return true
		elif CharacterStats.equipped_weapon.is_bow_weapon():
			# Bow - check for weakpoint hit first (uncapped attack speed on weakpoints)
			if try_bow_weakpoint_attack(mouse_pos):
				return true  # Hit weakpoint - no cooldown
			attempt_bow_attack()
			return true

	# Melee/unarmed weapon - check weakpoint first
	if is_clicking_on_weakpoint(mouse_pos):
		return true  # Let the weakpoint handle it

	# Try crit window click on enemy body
	if check_crit_window_click(mouse_pos):
		return true

	# Normal melee attack
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
	# First check PvP weakpoints on players (during duels)
	if _check_pvp_weakpoint_click(mouse_pos):
		return true

	# Then check PvE weakpoints on enemies
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

					# Play slash animation toward the weakpoint (cycles through variants)
					var character_sprite = player.get_node_or_null("CharacterSprite")
					if character_sprite:
						var direction_to_weakpoint = (weakpoint.global_position - player.global_position).normalized()
						var dir_str = player.get_direction_string(direction_to_weakpoint)
						var lpc_dir = player.convert_to_lpc_direction(dir_str)
						var attack_anim = character_sprite.get_next_attack_anim() if character_sprite.has_method("get_next_attack_anim") else "slash"
						character_sprite.play_lpc_animation(attack_anim, lpc_dir)

					# CLIENT-PREDICTED: Call hit() directly for instant feedback
					# Server validates total damage at crit window end
					if weakpoint.has_method("hit"):
						weakpoint.hit()
					return true

	return false

func _check_pvp_weakpoint_click(mouse_pos: Vector2) -> bool:
	"""Check if clicking on a PvP weakpoint during a duel"""
	# Only check if we're in a duel
	if not player.is_dueling:
		return false

	# Check all players for PvP weakpoints
	var all_players = player.get_tree().get_nodes_in_group("player")

	for other_player in all_players:
		if not is_instance_valid(other_player):
			continue

		# Skip self - can't click own weakpoints
		if other_player == player:
			continue

		# Check if this player has active PvP weakpoints
		if not other_player.get("pvp_weakpoint_active"):
			continue

		var pvp_weakpoints = other_player.get("pvp_weakpoints")
		if not pvp_weakpoints or pvp_weakpoints.size() == 0:
			continue

		print("[PvP WP] Checking %d weakpoints on %s" % [pvp_weakpoints.size(), other_player.name])

		for weakpoint in pvp_weakpoints:
			if not is_instance_valid(weakpoint):
				continue
			if weakpoint.is_destroyed:
				continue

			var distance = mouse_pos.distance_to(weakpoint.global_position)
			# Use a forgiving click radius (38px base, scaled by weakpoint scale)
			var click_radius = 38.0 * weakpoint.scale.x

			print("[PvP WP] Weakpoint at %s, click at %s, dist=%.1f, radius=%.1f" % [
				weakpoint.global_position, mouse_pos, distance, click_radius
			])

			if distance < click_radius:
				print("[PvP WP] HIT! Calling weakpoint.hit()")

				# Play slash animation toward the weakpoint
				var character_sprite = player.get_node_or_null("CharacterSprite")
				if character_sprite:
					var direction_to_weakpoint = (weakpoint.global_position - player.global_position).normalized()
					var dir_str = player.get_direction_string(direction_to_weakpoint)
					var lpc_dir = player.convert_to_lpc_direction(dir_str)
					var attack_anim = character_sprite.get_next_attack_anim() if character_sprite.has_method("get_next_attack_anim") else "slash"
					character_sprite.play_lpc_animation(attack_anim, lpc_dir)

				# Call hit() for instant feedback
				if weakpoint.has_method("hit"):
					weakpoint.hit()
				return true

	return false

func handle_crit_window_attack(enemy: Node, _click_pos: Vector2) -> void:
	"""Handle attack during crit window - deal normal damage to enemy body"""
	if not is_instance_valid(enemy):
		return

	# During crit window, clicking on enemy body deals normal damage
	# (weakpoints are handled separately by is_clicking_on_weakpoint)
	apply_damage_with_feedback(enemy, attack_damage, false, false)

func attempt_attack() -> void:
	"""Try to perform an attack"""
	if not can_attack:
		return

	can_attack = false
	# Sync to player for compatibility
	if player:
		player.can_attack = false

	# Play attack animation (cycles through slash variants for multi-slash weapons)
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		var dir_str = player.get_direction_string(attack_direction)
		var lpc_dir = player.convert_to_lpc_direction(dir_str)
		var attack_anim = character_sprite.get_next_attack_anim() if character_sprite.has_method("get_next_attack_anim") else "slash"
		character_sprite.play_lpc_animation(attack_anim, lpc_dir)

	# Spawn weapon swoosh visual effect
	if attack_feedback:
		attack_feedback.spawn_weapon_swoosh(attack_direction)

	# Get enemies in attack cone
	# Play weapon swing sound (whoosh) - plays immediately on attack
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		if CharacterStats.equipped_weapon:
			sound_manager.play_sword_swing_sound(player.global_position, -14.0)
		else:
			sound_manager.play_unarmed_swing_sound(player.global_position, -14.0)

	# Track swing for forged weapons
	_track_weapon_swing()

	var enemies = get_enemies_in_cone()

	if enemies.size() > 0:
		attack_enemies_in_cone(enemies)
	else:
		# No enemies hit = miss
		_track_weapon_miss()

	# PvP: Attack players in cone during duel
	if player.is_dueling:
		var players_hit = get_players_in_cone()
		print("[PvP] In duel, found %d players in cone (opponent_id: %d)" % [players_hit.size(), player.duel_opponent_id])
		if players_hit.size() > 0:
			attack_players_in_cone(players_hit)
		else:
			# Debug: Check why no players found
			var all_players = player.get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
			print("[PvP] Total players in group: %d" % all_players.size())
			for p in all_players:
				if p != player:
					var dist = player.global_position.distance_to(p.global_position)
					print("[PvP]   Other player at dist=%.1f (attack_range=%.1f)" % [dist, attack_range])

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

func get_players_in_cone() -> Array:
	"""Get other players within attack cone (for PvP dueling)"""
	var players_in_range = []
	var all_players = player.get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	for other_player in all_players:
		if not is_instance_valid(other_player):
			continue

		# Skip self
		if other_player == player:
			continue

		# Check distance
		var distance = player.global_position.distance_to(other_player.global_position)
		if distance > attack_range:
			continue

		# Check angle (cone)
		var to_player = (other_player.global_position - player.global_position).normalized()
		var angle_diff = abs(attack_direction.angle_to(to_player))

		if angle_diff <= attack_cone_angle / 2.0:
			players_in_range.append(other_player)

	return players_in_range

func attack_players_in_cone(target_players: Array) -> void:
	"""Deal damage to players in attack cone (PvP)"""
	var my_peer_id = player.get_tree().get_multiplayer().get_unique_id()
	print("[PvP] attack_players_in_cone called with %d targets" % target_players.size())

	for target_player in target_players:
		if not is_instance_valid(target_player):
			print("[PvP]   Target invalid, skipping")
			continue

		# Only attack duel opponent during a duel
		if player.is_dueling:
			var target_id = _get_player_peer_id(target_player)
			print("[PvP]   target_id=%d, duel_opponent_id=%d" % [target_id, player.duel_opponent_id])
			if target_id != player.duel_opponent_id:
				print("[PvP]   Skipping - not duel opponent")
				continue  # Skip non-opponent players

		print("[PvP]   Attacking target!")

		# Deal weapon damage (PvP weakpoints are clicked directly, not via weapon attacks)
		var final_damage = attack_damage

		# Send PvP damage through network
		_send_pvp_damage(target_player, int(final_damage))

		# Visual feedback for attacker
		if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
			attack_feedback.spawn_damage_number(target_player.global_position, final_damage, false, false)

		# Hit sound
		var sound_manager = player.get_node_or_null("/root/SoundManager")
		if sound_manager:
			var weapon_type = "unarmed"
			if CharacterStats.equipped_weapon:
				weapon_type = CharacterStats.equipped_weapon.weapon_type
			sound_manager.play_normal_hit_sound(target_player.global_position, -12.0, weapon_type)

func _get_player_peer_id(target_player: Node) -> int:
	"""Get the peer ID for a player node using multiple methods"""
	# Method 1: Check if player has multiplayer authority set
	if target_player.get_multiplayer_authority() > 0:
		return target_player.get_multiplayer_authority()

	# Method 2: Check parent for NetworkPlayer with player_id
	var parent = target_player.get_parent()
	if parent and parent.get("player_id") != null:
		return parent.player_id

	# Method 3: Extract from parent name (Player_XXXXX)
	if parent and parent.name.begins_with("Player_"):
		var id_str = parent.name.substr(7)
		if id_str.is_valid_int():
			return int(id_str)

	# Method 4: Search in Players container for matching player_instance
	var players_container = player.get_node_or_null("/root/GameWorld/Players")
	if players_container:
		for network_player in players_container.get_children():
			if network_player.get("player_instance") == target_player:
				if network_player.get("player_id") != null:
					return network_player.player_id

	return -1

func _try_hit_pvp_weakpoint(target_player: Node, hit_pos: Vector2) -> bool:
	"""Check if bullet hit a PvP weakpoint on the target player. Returns true if hit.

	Guns can hit weakpoints by shooting them - we check if the hit position is within
	any active weakpoint's hitbox radius. Uses a generous radius since aiming precisely
	at a small moving target is difficult.
	"""
	if not is_instance_valid(target_player):
		return false

	# Check if target has active PvP weakpoints
	if not target_player.has_method("has_active_pvp_weakpoints"):
		return false
	if not target_player.has_active_pvp_weakpoints():
		print("[PvP] Target has no active weakpoints")
		return false

	# Get the weakpoints array from target player
	var weakpoints = target_player.get("pvp_weakpoints")
	if not weakpoints or weakpoints.is_empty():
		return false

	print("[PvP] Checking %d weakpoints, hit_pos=%s, target_pos=%s" % [weakpoints.size(), hit_pos, target_player.global_position])

	# Check each weakpoint for collision with hit position
	for wp in weakpoints:
		if not is_instance_valid(wp):
			continue
		if wp.get("is_destroyed"):
			continue

		# Get weakpoint's world position (it's a child of the target player)
		var wp_world_pos = target_player.global_position + wp.position

		# Use a generous hitbox for gun hits - weakpoints are small and targets move
		# Base radius from weakpoint + extra 15px for gun accuracy tolerance
		var hitbox_radius = 45.0  # Generous radius for gun hits
		if wp.has_method("calculate_hitbox_radius"):
			hitbox_radius = wp.calculate_hitbox_radius() + 15.0  # Add tolerance

		# Check if hit position is within weakpoint hitbox
		var distance = hit_pos.distance_to(wp_world_pos)
		print("[PvP] Weakpoint at %s, distance=%.1f, radius=%.1f" % [wp_world_pos, distance, hitbox_radius])

		if distance <= hitbox_radius:
			# Hit the weakpoint!
			print("[PvP] ✓ Bullet hit weakpoint at distance %.1f (radius %.1f)" % [distance, hitbox_radius])
			if wp.has_method("hit"):
				wp.hit()
			return true

	print("[PvP] No weakpoint hit (closest was outside radius)")
	return false

func _check_pvp_weakpoint_hit_at_cursor(cursor_pos: Vector2) -> bool:
	"""Check if cursor position hits any duel opponent's weakpoint directly.

	This is used to detect weakpoint hits even when aiming above the player's body
	(weakpoints spawn above the head).
	"""
	if not player.is_dueling:
		return false

	# Find the duel opponent
	var all_players = player.get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for other_player in all_players:
		if not is_instance_valid(other_player):
			continue
		if other_player == player:
			continue

		var target_id = _get_player_peer_id(other_player)
		if target_id != player.duel_opponent_id:
			continue

		# Found opponent - check their weakpoints
		return _try_hit_pvp_weakpoint(other_player, cursor_pos)

	return false

func _send_pvp_damage(target_player: Node, damage: int) -> void:
	"""Send PvP damage request to server via DuelManager"""
	var target_peer_id = _get_player_peer_id(target_player)

	if target_peer_id < 0:
		print("[PvP] Cannot find target peer ID for damage")
		return

	var duel_manager = player.get_node_or_null("/root/DuelManager")
	if not duel_manager:
		print("[PvP] DuelManager not found")
		return

	# Send damage request through DuelManager
	if player.get_tree().get_multiplayer().is_server():
		# Server processes directly - call the RPC locally
		duel_manager.request_pvp_damage(target_peer_id, damage)
	else:
		# Client sends RPC to server
		duel_manager.request_pvp_damage.rpc_id(1, target_peer_id, damage)

	print("[PvP] Sent damage request: %d to player %d" % [damage, target_peer_id])

func _check_bullet_path_player_collision(start: Vector2, end: Vector2, hit_radius: float) -> Dictionary:
	"""Check if bullet path intersects duel opponent player. Returns first hit."""
	if not player.is_dueling:
		return {"hit": false, "player": null, "hit_pos": end}

	var all_players = player.get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	var closest_hit_dist = INF
	var closest_hit_pos = end
	var closest_player = null

	# Calculate projectile path bounds for range culling
	var path_length = start.distance_to(end)
	var path_center = (start + end) / 2.0
	var cull_radius = path_length / 2.0 + 100.0

	for other_player in all_players:
		if not is_instance_valid(other_player):
			continue

		# Skip self
		if other_player == player:
			continue

		# Only check duel opponent
		var target_id = _get_player_peer_id(other_player)
		if target_id != player.duel_opponent_id:
			continue

		# Quick range cull
		var rough_dist = other_player.global_position.distance_to(path_center)
		if rough_dist > cull_radius:
			continue

		# Use a capsule hitbox for the player (similar to enemies)
		var player_pos = other_player.global_position
		var capsule_top = player_pos + Vector2(0, -24)  # Head
		var capsule_bottom = player_pos + Vector2(0, 12)  # Feet
		var capsule_radius = 14.0  # Slightly wider than enemy for easier hitting

		# Check line-capsule intersection
		var intersection = _line_capsule_intersection(start, end, capsule_top, capsule_bottom, capsule_radius)

		if intersection.intersects:
			var hit_dist = start.distance_to(intersection.point)
			if hit_dist < closest_hit_dist:
				closest_hit_dist = hit_dist
				closest_hit_pos = intersection.point
				closest_player = other_player

	return {
		"hit": closest_player != null,
		"player": closest_player,
		"hit_pos": closest_hit_pos
	}

func _attack_player_with_gun(target_player: Node, hit_pos: Vector2) -> void:
	"""Deal gun damage to a player (PvP)"""
	if not is_instance_valid(target_player):
		return

	# Only attack duel opponent
	if player.is_dueling:
		var target_id = _get_player_peer_id(target_player)
		if target_id != player.duel_opponent_id:
			print("[PvP] Gun hit - skipping non-opponent")
			return

	# Check for weakpoint hit first - guns can hit PvP weakpoints!
	var weakpoint_hit = _try_hit_pvp_weakpoint(target_player, hit_pos)
	if weakpoint_hit:
		# Weakpoint was hit - visual feedback on weakpoint position
		_spawn_bullet_impact(hit_pos, true)
		print("[PvP] Gun hit weakpoint!")
		return  # Weakpoint handles its own damage

	# No weakpoint hit - deal regular gun damage
	var final_damage = attack_damage

	# Send PvP damage through network
	_send_pvp_damage(target_player, int(final_damage))

	# Visual feedback - spawn bullet impact on player
	_spawn_bullet_impact(hit_pos, true)

	# Damage number
	if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
		attack_feedback.spawn_damage_number(target_player.global_position, final_damage, false, false)

	# Hit sound
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_normal_hit_sound(target_player.global_position, -12.0, "gun")

	print("[PvP] Gun attack hit player for %d damage" % int(final_damage))

func _attack_player_with_burst(target_player: Node, hit_pos: Vector2) -> void:
	"""Deal burst weapon damage to a player (PvP). Lower damage per shot."""
	if not is_instance_valid(target_player):
		return

	# Only attack duel opponent
	if player.is_dueling:
		var target_id = _get_player_peer_id(target_player)
		if target_id != player.duel_opponent_id:
			return

	# Check for weakpoint hit first - guns can hit PvP weakpoints!
	var weakpoint_hit = _try_hit_pvp_weakpoint(target_player, hit_pos)
	if weakpoint_hit:
		# Weakpoint was hit - visual feedback on weakpoint position
		_spawn_bullet_impact(hit_pos, true)
		print("[PvP] Burst round hit weakpoint!")
		return  # Weakpoint handles its own damage

	# No weakpoint hit - deal regular burst damage
	var final_damage = burst_damage_per_shot

	# Send PvP damage through network
	_send_pvp_damage(target_player, int(final_damage))

	# Visual feedback
	_spawn_bullet_impact(hit_pos, true)

	# Damage number (no combat text for individual burst rounds to reduce spam)
	# if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
	#	attack_feedback.spawn_damage_number(target_player.global_position, final_damage, false, false)

func attack_enemies_in_cone(enemies: Array) -> void:
	"""Deal damage to enemies in attack cone"""
	var TutorialManager = player.get_node_or_null("/root/TutorialManager")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Get enemy health BEFORE damage for threshold checks
		var enemy_hp_before = enemy.current_health if "current_health" in enemy else 100.0
		var enemy_max_hp = enemy.max_health if "max_health" in enemy else 100.0

		# Roll for crit (still gives bonus damage, but NO LONGER triggers weakpoint window)
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
				# NOTE: Crits still deal bonus damage but NO LONGER auto-trigger weakpoint windows
				# Windows are now triggered by hit count and health thresholds via register_hit()

		# Apply damage with feedback
		apply_damage_with_feedback(enemy, final_damage, is_crit, false)

		# NEW: Register hit with CritWindowManager for threshold-based window triggers
		# This replaces the old crit-based trigger system
		if crit_window_manager and crit_window_manager.has_method("register_hit"):
			var window_triggered = crit_window_manager.register_hit(enemy, final_damage, enemy_hp_before, enemy_max_hp)
			if window_triggered:
				# Play crit window opening sound when window triggers
				var sound_manager = player.get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_sound"):
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -10.0)

func apply_damage_with_feedback(enemy: Node, damage: float, is_crit: bool, hit_weakpoint: bool) -> void:
	"""Apply damage to enemy with visual/audio feedback"""
	if not is_instance_valid(enemy):
		return

	# Get enemy HP before damage for overkill calculation
	var enemy_hp_before = 0.0
	if "current_health" in enemy:
		enemy_hp_before = enemy.current_health

	# MULTIPLAYER: Send damage to server for authoritative processing
	var has_peer = player.multiplayer.has_multiplayer_peer()
	var enemy_net_id = enemy.get("network_id") if enemy.get("network_id") != null else -1

	if has_peer and enemy_net_id >= 0:
		var network_enemy_mgr = player.get_node_or_null("/root/NetworkEnemyManager")
		if network_enemy_mgr:
			if player.multiplayer.is_server():
				# Server processes damage directly (no RPC to self)
				network_enemy_mgr.request_damage(enemy_net_id, damage, is_crit, hit_weakpoint)
			else:
				# Client sends RPC to server
				network_enemy_mgr.request_damage.rpc_id(1, enemy_net_id, damage, is_crit, hit_weakpoint)
			# Server will broadcast visual feedback via _client_enemy_damaged
			# Skip local take_damage - server handles it authoritatively
			_track_weapon_hit(damage, is_crit, enemy, enemy_hp_before)
			return

	# Single player: apply damage directly
	if enemy.has_method("take_damage"):
		enemy.take_damage(damage)

	# Track weapon stats for forged weapons
	_track_weapon_hit(damage, is_crit, enemy, enemy_hp_before)

	# Damage number
	if attack_feedback and attack_feedback.has_method("spawn_damage_number"):
		attack_feedback.spawn_damage_number(enemy.global_position, damage, is_crit, hit_weakpoint)

	# Blood splatter particles at enemy position
	if attack_feedback and attack_feedback.has_method("trigger_attack_feedback"):
		attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, hit_weakpoint)

	# Screen shake disabled - CombatJuice handles hitstop only now
	# if is_crit and screen_shake:
	#	screen_shake.add_trauma(0.2)

	# Hit sound (delayed slightly so swing whoosh plays first)
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		var weapon_type = "unarmed"
		var is_gun = false
		var is_bow = false
		if CharacterStats.equipped_weapon:
			weapon_type = CharacterStats.equipped_weapon.weapon_type
			is_gun = CharacterStats.equipped_weapon.is_gun_weapon()
			is_bow = CharacterStats.equipped_weapon.is_bow_weapon()
		var hit_pos = enemy.global_position
		var tree = player.get_tree()
		tree.create_timer(0.1).timeout.connect(func():
			if is_crit:
				sound_manager.play_critical_hit_sound(hit_pos, -8.0)
			elif is_gun:
				# Use bullet impact sounds for guns - training dummy is armored, others are flesh
				var is_armored = enemy.is_in_group("training_dummy")
				sound_manager.play_bullet_impact_sound(hit_pos, is_armored, -8.0)
			elif is_bow:
				# Skip bow impact sound here - _spawn_arrow_impact already handles it
				pass
			else:
				sound_manager.play_normal_hit_sound(hit_pos, -12.0, weapon_type)
		)

# ========================================
# GUN ATTACK SYSTEM
# ========================================

func try_gun_weakpoint_attack(mouse_pos: Vector2) -> bool:
	"""Check if gun targeting circle contains a weakpoint and hit it directly.
	This bypasses attack cooldown for skill expression (uncapped attack speed on weakpoints).
	Returns true if a weakpoint was hit."""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_gun_weapon():
		return false

	var cursor_pos = player.get_global_mouse_position()
	var gun_radius = weapon.gun_radius if weapon.get("gun_radius") else 28.0
	var gun_range = weapon.gun_range if weapon.get("gun_range") else 550.0

	# Clamp cursor to max range
	var distance_to_cursor = player.global_position.distance_to(cursor_pos)
	if distance_to_cursor > gun_range:
		var direction = (cursor_pos - player.global_position).normalized()
		cursor_pos = player.global_position + direction * gun_range

	# Check all enemies for weakpoints within gun targeting circle
	var all_enemies = player.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		# Only check enemies in crit window
		if not ("in_crit_window" in enemy and enemy.in_crit_window):
			continue

		if not "weakpoints" in enemy:
			continue

		for weakpoint in enemy.weakpoints:
			if not is_instance_valid(weakpoint):
				continue
			if "is_destroyed" in weakpoint and weakpoint.is_destroyed:
				continue

			# Check if weakpoint is within gun targeting circle at cursor
			var distance = cursor_pos.distance_to(weakpoint.global_position)
			if distance <= gun_radius:
				# HIT! Fire visual effects and hit the weakpoint (NO COOLDOWN)
				_fire_gun_at_weakpoint(weakpoint, cursor_pos)
				return true

	return false

func _fire_gun_at_weakpoint(weakpoint: Node, cursor_pos: Vector2) -> void:
	"""Fire gun at weakpoint with visual effects but NO cooldown."""
	# Face toward weakpoint
	attack_direction = (weakpoint.global_position - player.global_position).normalized()

	# Play shoot animation
	var character_sprite = player.get_node_or_null("CharacterSprite")
	var dir_str = player.get_direction_string(attack_direction)
	var lpc_dir = player.convert_to_lpc_direction(dir_str)
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("shoot", lpc_dir)

	# Calculate barrel position
	var barrel_pos = player.global_position + _get_gun_barrel_offset(lpc_dir)

	# Check if burst weapon (battle rifle) vs single shot (railgun) for VFX
	var weapon = CharacterStats.equipped_weapon
	var is_burst_weapon = weapon and weapon.has_method("is_burst_weapon") and weapon.is_burst_weapon()

	var sound_manager = player.get_node_or_null("/root/SoundManager")

	if is_burst_weapon:
		# Battle rifle style - tracer round and green muzzle flash
		_spawn_battle_rifle_muzzle_flash(barrel_pos)
		_spawn_tracer_round(barrel_pos, weakpoint.global_position)
		if sound_manager and sound_manager.has_method("play_battle_rifle_sound"):
			sound_manager.play_battle_rifle_sound(player.global_position, -10.0)
		elif sound_manager:
			sound_manager.play_gunshot_sound(player.global_position, -10.0)
	else:
		# Railgun style - beam trail and standard muzzle flash
		_spawn_muzzle_flash_at(barrel_pos)
		_spawn_bullet_trail(barrel_pos, weakpoint.global_position)
		if sound_manager:
			sound_manager.play_gunshot_sound(player.global_position, -10.0)

	# Hit the weakpoint directly (client-predicted, no cooldown)
	if weakpoint.has_method("hit"):
		weakpoint.hit()

func attempt_gun_attack() -> void:
	"""Try to perform a gun attack at cursor position (with cooldown)"""
	if not can_attack:
		return

	# Verify gun weapon equipped
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_gun_weapon():
		return

	can_attack = false
	if player:
		player.can_attack = false

	var cursor_pos = player.get_global_mouse_position()
	var gun_radius = weapon.gun_radius if weapon.get("gun_radius") else 28.0
	var gun_range = weapon.gun_range if weapon.get("gun_range") else 550.0

	# Clamp cursor to max range from player
	var distance_to_cursor = player.global_position.distance_to(cursor_pos)
	if distance_to_cursor > gun_range:
		var direction = (cursor_pos - player.global_position).normalized()
		cursor_pos = player.global_position + direction * gun_range

	# Face toward cursor
	attack_direction = (cursor_pos - player.global_position).normalized()

	# Play gun shoot animation (uses Skorpio body pose)
	var character_sprite = player.get_node_or_null("CharacterSprite")
	var dir_str = player.get_direction_string(attack_direction)
	var lpc_dir = player.convert_to_lpc_direction(dir_str)
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("shoot", lpc_dir)

	# Calculate barrel tip position based on direction
	var barrel_pos = player.global_position + _get_gun_barrel_offset(lpc_dir)

	# Spawn muzzle flash at barrel
	_spawn_muzzle_flash_at(barrel_pos)

	# Check for enemies along the bullet path (not just at cursor)
	var hit_result = _check_arrow_path_collision(barrel_pos, cursor_pos, gun_radius)

	var actual_target = cursor_pos
	var hit_enemy = null

	if hit_result.hit:
		actual_target = hit_result.hit_pos
		hit_enemy = hit_result.enemy

	# Spawn bullet trail from barrel to actual hit point
	_spawn_bullet_trail(barrel_pos, actual_target)

	# Play gunshot sound
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_gunshot_sound(player.global_position, -10.0)

	# Track shot for forged weapons
	_track_weapon_shot()

	# Deal damage to enemy hit along path, or check at cursor as fallback
	if hit_enemy and is_instance_valid(hit_enemy):
		attack_enemies_at_cursor([hit_enemy])
		_spawn_bullet_impact(actual_target, false)
	else:
		# Check at cursor position as fallback
		var enemies = get_enemies_in_gun_radius(cursor_pos, gun_radius)
		if enemies.size() > 0:
			attack_enemies_at_cursor(enemies)
		else:
			# Miss - spawn impact at cursor
			_spawn_bullet_impact(cursor_pos, false)
			_track_weapon_miss()

	# PvP: Check for player hits during duel
	if player.is_dueling:
		# First check for direct weakpoint hits (weakpoints are above the player's body)
		var weakpoint_hit = _check_pvp_weakpoint_hit_at_cursor(actual_target)
		if weakpoint_hit:
			print("[PvP] Gun directly hit weakpoint!")
			_spawn_bullet_impact(actual_target, true)
		else:
			# Check for body hits
			var player_hit_result = _check_bullet_path_player_collision(barrel_pos, cursor_pos, gun_radius)
			if player_hit_result.hit:
				print("[PvP] Gun hit player along bullet path!")
				_attack_player_with_gun(player_hit_result.player, actual_target)

	# Start cooldown timer
	player.get_tree().create_timer(attack_cooldown).timeout.connect(finish_attack_cooldown)

# ========================================
# BOW ATTACK SYSTEM
# ========================================

func attempt_bow_attack() -> void:
	"""Try to perform a bow attack at cursor position"""
	if not can_attack:
		return

	# Verify bow weapon equipped
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_bow_weapon():
		return

	can_attack = false
	if player:
		player.can_attack = false

	var cursor_pos = player.get_global_mouse_position()
	var bow_radius = weapon.bow_radius if weapon.get("bow_radius") else 32.0
	var bow_range = weapon.bow_range if weapon.get("bow_range") else 450.0
	var arrow_speed = weapon.arrow_speed if weapon.get("arrow_speed") else 1800.0  # Fast arrows (50% faster)

	# Clamp cursor to max range from player
	var distance_to_cursor = player.global_position.distance_to(cursor_pos)
	if distance_to_cursor > bow_range:
		var direction = (cursor_pos - player.global_position).normalized()
		cursor_pos = player.global_position + direction * bow_range

	# Face toward cursor
	attack_direction = (cursor_pos - player.global_position).normalized()

	# Play bow shoot animation
	var character_sprite = player.get_node_or_null("CharacterSprite")
	var dir_str = player.get_direction_string(attack_direction)
	var lpc_dir = player.convert_to_lpc_direction(dir_str)
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("shoot", lpc_dir)

	# Play bow shot sound (twang!) - plays immediately on attack
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_bow_shot_sound"):
		sound_manager.play_bow_shot_sound(player.global_position, -10.0)

	# Delay arrow spawn to sync with bow draw animation (release mid-animation)
	var draw_delay = weapon.bow_draw_time if weapon.get("bow_draw_time") else 0.25
	await player.get_tree().create_timer(draw_delay).timeout

	# Re-check player is still valid after await
	if not is_instance_valid(player):
		return

	# Calculate arrow start position (from player center, slightly forward)
	var arrow_start = player.global_position + attack_direction * 16.0

	# Spawn arrow projectile
	_spawn_arrow_projectile(arrow_start, cursor_pos, arrow_speed, bow_radius)

	# Track shot for forged weapons
	_track_weapon_shot()

	# Start cooldown timer
	player.get_tree().create_timer(attack_cooldown).timeout.connect(finish_attack_cooldown)

func try_bow_weakpoint_attack(mouse_pos: Vector2) -> bool:
	"""Check if bow can hit a weakpoint at cursor position (uncapped attack speed).
	Returns true if a weakpoint was hit."""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_bow_weapon():
		return false

	var bow_radius = weapon.bow_radius if weapon.get("bow_radius") else 32.0

	# Get all enemies
	var all_enemies = player.get_tree().get_nodes_in_group("enemies")

	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue

		# Only check enemies in crit window
		if not ("in_crit_window" in enemy and enemy.in_crit_window):
			continue

		if not "weakpoints" in enemy:
			continue

		# Check each weakpoint
		for weakpoint in enemy.weakpoints:
			if not is_instance_valid(weakpoint):
				continue
			if not weakpoint.visible:
				continue

			# Check if cursor is within bow radius of weakpoint
			var dist_to_wp = mouse_pos.distance_to(weakpoint.global_position)
			if dist_to_wp <= bow_radius:
				# Hit! Fire arrow at weakpoint (instant, no draw delay for weakpoints)
				_fire_bow_at_weakpoint(weakpoint, mouse_pos)
				return true

	return false

func _fire_bow_at_weakpoint(weakpoint: Node, cursor_pos: Vector2) -> void:
	"""Fire bow at weakpoint with visual effects but NO cooldown."""
	# Face toward weakpoint
	attack_direction = (weakpoint.global_position - player.global_position).normalized()

	# Play shoot animation
	var character_sprite = player.get_node_or_null("CharacterSprite")
	var dir_str = player.get_direction_string(attack_direction)
	var lpc_dir = player.convert_to_lpc_direction(dir_str)
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("shoot", lpc_dir)

	# Play bow shot sound immediately
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_bow_shot_sound"):
		sound_manager.play_bow_shot_sound(player.global_position, -10.0)

	# Calculate arrow start position
	var arrow_start = player.global_position + attack_direction * 16.0

	# Spawn arrow projectile at weakpoint (fast, direct hit)
	var arrow_speed = 2250.0  # Extra fast for weakpoint shots (50% faster)
	_spawn_arrow_at_weakpoint(arrow_start, weakpoint)

	# Hit the weakpoint directly (client-predicted, no cooldown)
	if weakpoint.has_method("hit"):
		weakpoint.hit()

func _spawn_arrow_at_weakpoint(start_pos: Vector2, weakpoint: Node) -> void:
	"""Spawn arrow that instantly travels to and hits a weakpoint."""
	var target_pos = weakpoint.global_position
	var arrow_speed = 2250.0

	# Create arrow visual
	var arrow = Line2D.new()
	arrow.name = "ArrowProjectile"
	arrow.width = 2.0
	arrow.default_color = Color(0.8, 0.6, 0.2, 1.0)  # Brighter for weakpoint hit
	arrow.z_index = 5

	var direction = (target_pos - start_pos).normalized()
	var arrow_length = 20.0
	arrow.add_point(Vector2.ZERO)
	arrow.add_point(direction * arrow_length)

	arrow.global_position = start_pos
	_add_vfx(arrow)

	# Fast travel to weakpoint
	var distance = start_pos.distance_to(target_pos)
	var travel_time = distance / arrow_speed

	var tween = player.get_tree().create_tween()
	tween.tween_property(arrow, "global_position", target_pos - direction * arrow_length, travel_time)
	tween.tween_callback(func():
		# Impact effect
		_spawn_arrow_impact(target_pos, true)
		arrow.queue_free()
	)

func _spawn_arrow_projectile(start_pos: Vector2, target_pos: Vector2, speed: float, hit_radius: float) -> void:
	"""Spawn an arrow projectile that checks for collisions along its entire flight path."""
	# Check for enemies along the flight path FIRST (raycast-style)
	var direction = (target_pos - start_pos).normalized()
	var max_distance = start_pos.distance_to(target_pos)

	# Find the first enemy hit along the arrow's path
	var hit_result = _check_arrow_path_collision(start_pos, target_pos, hit_radius)

	var actual_target = target_pos
	var hit_enemy = null

	if hit_result.hit:
		# Arrow will stop at the first enemy it hits
		actual_target = hit_result.hit_pos
		hit_enemy = hit_result.enemy

	# Create arrow visual
	var arrow = Line2D.new()
	arrow.name = "ArrowProjectile"
	arrow.width = 2.0
	arrow.default_color = Color(0.6, 0.4, 0.2, 1.0)  # Brown arrow color
	arrow.z_index = 5

	# Arrow is a line from tail to tip
	var arrow_length = 20.0
	arrow.add_point(Vector2.ZERO)  # Tail
	arrow.add_point(direction * arrow_length)  # Tip

	arrow.global_position = start_pos
	_add_vfx(arrow)

	# Calculate travel time to actual target (hit point or original target)
	var distance = start_pos.distance_to(actual_target)
	var travel_time = distance / speed

	# Animate arrow flying to target
	var tween = player.get_tree().create_tween()
	tween.tween_property(arrow, "global_position", actual_target - direction * arrow_length, travel_time)
	tween.tween_callback(func():
		if hit_enemy and is_instance_valid(hit_enemy):
			# Hit the enemy we detected along the path
			attack_enemies_at_cursor([hit_enemy])
			_spawn_arrow_impact(actual_target, true)
		else:
			# Check at final position as fallback (in case enemy moved into path)
			var enemies = get_enemies_in_gun_radius(actual_target, hit_radius)
			if enemies.size() > 0:
				attack_enemies_at_cursor(enemies)
				_spawn_arrow_impact(actual_target, true)
			else:
				# Miss
				_spawn_arrow_impact(actual_target, false)
				_track_weapon_miss()

		# Remove arrow
		arrow.queue_free()
	)

func _check_arrow_path_collision(start: Vector2, end: Vector2, _hit_radius: float) -> Dictionary:
	"""Check if arrow path intersects any enemy capsule hitbox. Returns first hit.
	Optimized with range culling for multiplayer scalability."""
	var enemies = player.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var closest_hit_dist = INF
	var closest_hit_pos = end
	var closest_enemy = null

	# Calculate projectile path bounds for range culling
	var path_length = start.distance_to(end)
	var path_center = (start + end) / 2.0
	var cull_radius = path_length / 2.0 + 100.0  # Half path length + buffer for enemy size

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# OPTIMIZATION: Quick range cull - skip enemies far from projectile path
		var rough_dist = enemy.global_position.distance_to(path_center)
		if rough_dist > cull_radius:
			continue

		# Get enemy's capsule hitbox (pill shape from head to toe)
		var capsule = _get_enemy_capsule_hitbox(enemy)

		# Check line-capsule intersection
		var intersection = _line_capsule_intersection(start, end, capsule.top, capsule.bottom, capsule.radius)

		if intersection.intersects:
			# Check if this is the closest hit
			var hit_dist = start.distance_to(intersection.point)
			if hit_dist < closest_hit_dist:
				closest_hit_dist = hit_dist
				closest_hit_pos = intersection.point
				closest_enemy = enemy

	return {
		"hit": closest_enemy != null,
		"enemy": closest_enemy,
		"hit_pos": closest_hit_pos
	}

func _line_capsule_intersection(line_start: Vector2, line_end: Vector2, cap_top: Vector2, cap_bottom: Vector2, cap_radius: float) -> Dictionary:
	"""Check if a line segment intersects a capsule (pill shape).
	Capsule = line segment from cap_top to cap_bottom with radius cap_radius around it."""

	# Find the closest distance between the two line segments
	var closest = _closest_points_between_segments(line_start, line_end, cap_top, cap_bottom)

	if closest.distance <= cap_radius:
		# Intersection! Return the point on the projectile line
		return {"intersects": true, "point": closest.point_on_line1}

	return {"intersects": false, "point": line_end}

func _closest_points_between_segments(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Dictionary:
	"""Find closest points between two line segments.
	Returns {point_on_line1, point_on_line2, distance}"""

	var d1 = p2 - p1  # Direction of line 1
	var d2 = p4 - p3  # Direction of line 2
	var r = p1 - p3

	var a = d1.dot(d1)  # Squared length of line 1
	var e = d2.dot(d2)  # Squared length of line 2
	var f = d2.dot(r)

	var s: float = 0.0
	var t: float = 0.0

	# Check if either or both segments are points
	if a <= 0.0001 and e <= 0.0001:
		# Both segments are points
		s = 0.0
		t = 0.0
	elif a <= 0.0001:
		# First segment is a point
		s = 0.0
		t = clamp(f / e, 0.0, 1.0)
	elif e <= 0.0001:
		# Second segment is a point
		t = 0.0
		s = clamp(-d1.dot(r) / a, 0.0, 1.0)
	else:
		# General case
		var b = d1.dot(d2)
		var c = d1.dot(r)
		var denom = a * e - b * b

		if denom != 0.0:
			s = clamp((b * f - c * e) / denom, 0.0, 1.0)
		else:
			s = 0.0

		# Compute t for the closest point on segment 2
		t = (b * s + f) / e

		# Clamp t and recompute s if needed
		if t < 0.0:
			t = 0.0
			s = clamp(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clamp((b - c) / a, 0.0, 1.0)

	var closest_on_line1 = p1 + d1 * s
	var closest_on_line2 = p3 + d2 * t
	var dist = closest_on_line1.distance_to(closest_on_line2)

	return {
		"point_on_line1": closest_on_line1,
		"point_on_line2": closest_on_line2,
		"distance": dist
	}

func _spawn_arrow_impact(pos: Vector2, hit: bool) -> void:
	"""Spawn arrow impact visual and sound at position"""
	# Play impact sound
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_bow_impact_sound"):
		sound_manager.play_bow_impact_sound(pos, hit, -8.0)

	# Create a simple impact circle
	var impact = Polygon2D.new()
	impact.name = "ArrowImpact"
	impact.global_position = pos
	impact.z_index = 4

	var color = Color(0.8, 0.6, 0.2, 0.6) if hit else Color(0.5, 0.4, 0.3, 0.4)
	impact.color = color

	# Create small circle
	var points = PackedVector2Array()
	var radius = 8.0 if hit else 5.0
	for i in range(12):
		var angle = (float(i) / 12.0) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	impact.polygon = points

	_add_vfx(impact)

	# Fade out and remove
	var tween = player.get_tree().create_tween()
	tween.tween_property(impact, "modulate:a", 0.0, 0.3)
	tween.tween_callback(impact.queue_free)

# ========================================
# BURST FIRE SYSTEM (Battle Rifle)
# ========================================

func attempt_burst_attack() -> void:
	"""Perform a burst-fire attack (e.g., battle rifle 3-round burst)"""
	if not can_attack or is_burst_firing:
		return

	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_gun_weapon():
		return

	can_attack = false
	is_burst_firing = true
	if player:
		player.can_attack = false

	var cursor_pos = player.get_global_mouse_position()
	var gun_range = weapon.gun_range if weapon.get("gun_range") else 550.0

	# Clamp cursor to max range
	var distance_to_cursor = player.global_position.distance_to(cursor_pos)
	if distance_to_cursor > gun_range:
		var direction = (cursor_pos - player.global_position).normalized()
		cursor_pos = player.global_position + direction * gun_range

	# Store burst state
	burst_target_pos = cursor_pos
	burst_shots_remaining = weapon.burst_count
	burst_damage_per_shot = attack_damage / float(weapon.burst_count)
	burst_crit_used = false  # Reset crit tracking for new burst

	# Track burst for forged weapons
	_track_weapon_burst()

	# Face toward cursor
	attack_direction = (cursor_pos - player.global_position).normalized()

	# Play battle rifle burst sound ONCE (the sound file contains all 3 shots)
	var sound_manager = player.get_node_or_null("/root/SoundManager")
	if sound_manager:
		if sound_manager.has_method("play_battle_rifle_sound"):
			sound_manager.play_battle_rifle_sound(player.global_position, -10.0)
		else:
			sound_manager.play_gunshot_sound(player.global_position, -10.0)

	# Start burst sequence
	_fire_burst_round()

func _fire_burst_round() -> void:
	"""Fire a single round in a burst sequence"""
	if burst_shots_remaining <= 0:
		_finish_burst()
		return

	var weapon = CharacterStats.equipped_weapon
	if not weapon:
		_finish_burst()
		return

	burst_shots_remaining -= 1

	# Play shoot animation
	var character_sprite = player.get_node_or_null("CharacterSprite")
	var dir_str = player.get_direction_string(attack_direction)
	var lpc_dir = player.convert_to_lpc_direction(dir_str)
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("shoot", lpc_dir)

	# Calculate barrel position
	var barrel_pos = player.global_position + _get_gun_barrel_offset(lpc_dir)

	# Check for enemies along the bullet path
	var gun_radius = weapon.gun_radius if weapon.get("gun_radius") else 28.0
	var hit_result = _check_arrow_path_collision(barrel_pos, burst_target_pos, gun_radius)

	var actual_target = burst_target_pos
	var hit_enemy = null

	if hit_result.hit:
		actual_target = hit_result.hit_pos
		hit_enemy = hit_result.enemy

	# Spawn battle rifle visuals (green/teal Halo style)
	# Note: Sound is played once in attempt_burst_attack(), not per round
	_spawn_battle_rifle_muzzle_flash(barrel_pos)
	_spawn_tracer_round(barrel_pos, actual_target)

	# Deal damage to enemy hit along path, or check at target as fallback
	if hit_enemy and is_instance_valid(hit_enemy):
		_attack_enemies_burst_round([hit_enemy])
	else:
		var enemies = get_enemies_in_gun_radius(burst_target_pos, gun_radius)
		if enemies.size() > 0:
			_attack_enemies_burst_round(enemies)
		else:
			_spawn_bullet_impact(burst_target_pos, false)

	# PvP: Check for player hits during duel (burst weapons)
	if player.is_dueling:
		# First check for direct weakpoint hits (weakpoints are above the player's body)
		var weakpoint_hit = _check_pvp_weakpoint_hit_at_cursor(actual_target)
		if weakpoint_hit:
			print("[PvP] Burst round directly hit weakpoint!")
			_spawn_bullet_impact(actual_target, true)
		else:
			# Check for body hits
			var player_hit_result = _check_bullet_path_player_collision(barrel_pos, burst_target_pos, gun_radius)
			if player_hit_result.hit:
				print("[PvP] Burst round hit player!")
				_attack_player_with_burst(player_hit_result.player, actual_target)

	# Schedule next burst round or finish
	if burst_shots_remaining > 0:
		var burst_delay = weapon.burst_delay if weapon.get("burst_delay") else 0.10
		player.get_tree().create_timer(burst_delay).timeout.connect(_fire_burst_round)
	else:
		_finish_burst()

func _attack_enemies_burst_round(enemies: Array) -> void:
	"""Apply damage from a single burst round with crit chance.
	Only ONE shot per burst can crit to prevent advantage over single-shot weapons."""
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Get enemy health BEFORE damage for threshold checks
		var enemy_hp_before = enemy.current_health if "current_health" in enemy else 100.0
		var enemy_max_hp = enemy.max_health if "max_health" in enemy else 100.0

		var final_damage = burst_damage_per_shot
		var is_crit = false

		# Roll for crit if we haven't used our crit this burst
		if not burst_crit_used and crit_system and crit_system.has_method("roll_for_crit"):
			is_crit = crit_system.roll_for_crit()

			# Tutorial: force crit on training dummy after enough hits
			if enemy.is_in_group("training_dummy"):
				tutorial_dummy_hits += 1
				if not is_crit and tutorial_dummy_hits >= TUTORIAL_FORCE_CRIT_HITS:
					is_crit = true
					tutorial_dummy_hits = 0
				elif is_crit:
					tutorial_dummy_hits = 0

			if is_crit:
				burst_crit_used = true  # Lock out further crits this burst
				var crit_mult = crit_system.get_crit_multiplier() if crit_system.has_method("get_crit_multiplier") else 2.0
				final_damage *= crit_mult
				# NOTE: Crits still deal bonus damage but NO LONGER auto-trigger weakpoint windows

		# Apply damage - blood splatter is handled by attack_feedback system
		apply_damage_with_feedback(enemy, final_damage, is_crit, false)

		# NEW: Register hit with CritWindowManager for threshold-based window triggers
		if crit_window_manager and crit_window_manager.has_method("register_hit"):
			var window_triggered = crit_window_manager.register_hit(enemy, final_damage, enemy_hp_before, enemy_max_hp)
			if window_triggered:
				# Play crit window opening sound when window triggers
				var sound_manager = player.get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_sound"):
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -10.0)

func _finish_burst() -> void:
	"""Complete burst sequence and start cooldown"""
	is_burst_firing = false
	burst_shots_remaining = 0

	# Standard cooldown after burst completes
	player.get_tree().create_timer(attack_cooldown).timeout.connect(finish_attack_cooldown)

func get_enemies_in_gun_radius(center_pos: Vector2, radius: float) -> Array:
	"""Get all enemies whose capsule hitbox overlaps with targeting circle at cursor.
	Uses capsule (pill) hitbox for enemies, circle for targeting area."""
	var enemies_in_radius = []
	var enemies = player.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Get enemy's capsule hitbox
		var capsule = _get_enemy_capsule_hitbox(enemy)

		# Check if targeting circle overlaps with capsule
		# This is point-to-capsule distance check
		var dist_to_capsule = _point_to_capsule_distance(center_pos, capsule.top, capsule.bottom)

		# Hit if targeting circle overlaps capsule
		if dist_to_capsule <= radius + capsule.radius:
			enemies_in_radius.append(enemy)

	return enemies_in_radius

func _point_to_capsule_distance(point: Vector2, cap_top: Vector2, cap_bottom: Vector2) -> float:
	"""Get minimum distance from a point to a capsule's center line."""
	var line_vec = cap_bottom - cap_top
	var point_vec = point - cap_top

	var line_len_sq = line_vec.length_squared()
	if line_len_sq < 0.0001:
		# Capsule is essentially a point
		return point.distance_to(cap_top)

	# Project point onto line, clamped to segment
	var t = clamp(point_vec.dot(line_vec) / line_len_sq, 0.0, 1.0)
	var closest_on_line = cap_top + line_vec * t

	return point.distance_to(closest_on_line)

func _get_enemy_hit_center(enemy: Node) -> Vector2:
	"""Get the center point of an enemy for projectile hit detection.
	This targets the body/sprite center, not the feet position."""
	var capsule = _get_enemy_capsule_hitbox(enemy)
	# Return the center of the capsule
	return (capsule.top + capsule.bottom) / 2.0

func _get_enemy_capsule_hitbox(enemy: Node) -> Dictionary:
	"""Get capsule/pill hitbox parameters for an enemy.
	Returns: {top: Vector2, bottom: Vector2, radius: float}
	The capsule covers head to toe and scales with crit window."""

	# Base dimensions for LPC sprites (64x64 frame, ~32x56 character)
	var base_height = 52.0  # Head to toe coverage
	var base_radius = 14.0  # Half-width of body

	# Get scale factor (for crit window growth)
	var scale_factor = 1.0
	if enemy.get("sprite") and is_instance_valid(enemy.sprite):
		scale_factor = enemy.sprite.scale.y
	elif enemy.get("in_crit_window") and enemy.in_crit_window:
		# Fallback: check if in crit window and use expected scale
		scale_factor = 1.5  # Default crit window scale

	# Apply scale to dimensions
	# Height scales less aggressively to avoid oversized hitbox during crit window
	var height_scale = 1.0 + (scale_factor - 1.0) * 0.3  # 30% of the scale increase for height
	var height = base_height * height_scale
	var radius = base_radius * scale_factor

	# Calculate capsule position
	var base_pos = enemy.global_position

	# Check for sprite offset
	if enemy.get("sprite") and is_instance_valid(enemy.sprite):
		var sprite = enemy.sprite
		if sprite.position != Vector2.ZERO:
			base_pos = enemy.global_position + sprite.position

	# For LPC sprites: feet are at global_position, head is above
	# Capsule top = head level, capsule bottom = feet level
	# Offset 30px south to better align with skeleton sprites
	# Additional 25px south when scaled up (crit window) to match grown sprite
	var south_offset = 30.0
	if scale_factor > 1.1:
		south_offset += 25.0  # Extra offset for scaled enemies
	var capsule_top = base_pos + Vector2(0, -height + 4 + south_offset)  # Head
	var capsule_bottom = base_pos + Vector2(0, 4 + south_offset)  # Feet

	return {
		"top": capsule_top,
		"bottom": capsule_bottom,
		"radius": radius
	}

func attack_enemies_at_cursor(enemies: Array) -> void:
	"""Deal damage to enemies at gun cursor position - mirrors attack_enemies_in_cone()"""
	var TutorialManager = player.get_node_or_null("/root/TutorialManager")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Get enemy health BEFORE damage for threshold checks
		var enemy_hp_before = enemy.current_health if "current_health" in enemy else 100.0
		var enemy_max_hp = enemy.max_health if "max_health" in enemy else 100.0

		# Roll for crit (still gives bonus damage, but NO LONGER triggers weakpoint window)
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
					tutorial_dummy_hits = 0
					print("🎯 FORCED CRIT for tutorial (gun hit dummy %d times)" % TUTORIAL_FORCE_CRIT_HITS)
				elif is_crit:
					tutorial_dummy_hits = 0

			if is_crit:
				var crit_mult = crit_system.get_crit_multiplier() if crit_system.has_method("get_crit_multiplier") else 2.0
				final_damage *= crit_mult
				# NOTE: Crits still deal bonus damage but NO LONGER auto-trigger weakpoint windows

		# Apply damage - blood splatter is handled by attack_feedback system
		apply_damage_with_feedback(enemy, final_damage, is_crit, false)

		# NEW: Register hit with CritWindowManager for threshold-based window triggers
		if crit_window_manager and crit_window_manager.has_method("register_hit"):
			var window_triggered = crit_window_manager.register_hit(enemy, final_damage, enemy_hp_before, enemy_max_hp)
			if window_triggered:
				# Play crit window opening sound when window triggers
				var sound_manager = player.get_node_or_null("/root/SoundManager")
				if sound_manager and sound_manager.has_method("play_sound"):
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -10.0)

# ========================================
# GUN VISUAL EFFECTS
# ========================================

func _get_gun_barrel_offset(direction: String) -> Vector2:
	"""Get the barrel tip offset from player center based on facing direction.
	These offsets are tuned for the Skorpio gun-pose sprites (64x64 frames)."""
	match direction:
		"east":
			return Vector2(23, -3)   # Barrel extends right
		"west":
			return Vector2(-23, -3)  # Barrel extends left
		"north":
			return Vector2(10, -24)  # Barrel points up
		"south":
			return Vector2(-10, 23)  # Barrel points down
		_:
			return Vector2(20, -3)   # Default fallback

func _spawn_muzzle_flash_at(flash_pos: Vector2) -> void:
	"""Spawn code-generated muzzle flash - starburst effect"""
	var flash_container = Node2D.new()
	flash_container.name = "MuzzleFlash"
	flash_container.global_position = flash_pos
	flash_container.rotation = attack_direction.angle()
	flash_container.z_index = 15
	_add_vfx(flash_container)

	# Core bright circle (white-magenta to match beam)
	var core = Polygon2D.new()
	core.color = Color(1.0, 0.8, 1.0, 0.95)  # Bright magenta-white
	var core_points = PackedVector2Array()
	for i in range(12):
		var angle = (float(i) / 12) * TAU
		core_points.append(Vector2(cos(angle), sin(angle)) * 6)
	core.polygon = core_points
	flash_container.add_child(core)

	# Outer glow (purple-magenta to match beam)
	var glow = Polygon2D.new()
	glow.color = Color(0.85, 0.2, 0.9, 0.6)  # Purple-magenta (same as beam)
	var glow_points = PackedVector2Array()
	for i in range(12):
		var angle = (float(i) / 12) * TAU
		glow_points.append(Vector2(cos(angle), sin(angle)) * 12)
	glow.polygon = glow_points
	glow.z_index = -1
	flash_container.add_child(glow)

	# Spikes/rays shooting outward (3-5 random spikes)
	var num_spikes = randi_range(3, 5)
	for i in range(num_spikes):
		var spike = Polygon2D.new()
		spike.color = Color(0.9, 0.5, 1.0, 0.8)  # Light purple
		var spike_angle = randf_range(-0.4, 0.4)  # Spread around forward direction
		var spike_length = randf_range(14, 22)
		var spike_width = randf_range(2, 4)
		spike.polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(spike_length, -spike_width),
			Vector2(spike_length + 4, 0),
			Vector2(spike_length, spike_width)
		])
		spike.rotation = spike_angle
		flash_container.add_child(spike)

	# Quick scale up then fade out
	flash_container.scale = Vector2(0.5, 0.5)
	var tween = player.get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_container, "scale", Vector2(1.2, 1.2), 0.04)
	tween.tween_property(flash_container, "modulate:a", 0.0, 0.1)
	tween.set_parallel(false)
	tween.tween_callback(flash_container.queue_free)

func _spawn_bullet_trail(from_pos: Vector2, to_pos: Vector2) -> void:
	"""Spawn bullet trail line from gun to target"""
	var trail = Line2D.new()
	trail.name = "BulletTrail"
	trail.width = 2.0
	trail.default_color = Color(0.85, 0.2, 0.9, 0.8)  # Purple-magenta beam (Hades Lucifer style)
	trail.add_point(from_pos)
	trail.add_point(to_pos)
	trail.z_index = 10

	_add_vfx(trail)

	# Quick fade out
	var tween = player.get_tree().create_tween()
	tween.tween_property(trail, "modulate:a", 0.0, 0.12)
	tween.tween_callback(trail.queue_free)

func _spawn_bullet_impact(pos: Vector2, is_crit: bool) -> void:
	"""Spawn bullet impact effect at position (used for misses or ground hits)"""
	# Only railgun gets impact marker - battle rifle uses tracer rounds instead
	var weapon = CharacterStats.equipped_weapon
	var gun_subtype = weapon.gun_subtype if weapon and weapon.get("gun_subtype") else "railgun"
	if gun_subtype == "battle_rifle":
		return  # No impact marker for battle rifle

	# Create impact flash
	var impact = Node2D.new()
	impact.name = "BulletImpact"
	impact.global_position = pos
	impact.z_index = 12

	# Purple-magenta circle for railgun
	var circle = Polygon2D.new()
	if is_crit:
		circle.color = Color(1.0, 0.8, 0.2, 0.6)  # Gold for crit
	else:
		circle.color = Color(0.85, 0.2, 0.9, 0.6)  # Purple-magenta for railgun

	var points = PackedVector2Array()
	var segments = 12
	var radius = 6.0
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	circle.polygon = points
	impact.add_child(circle)

	_add_vfx(impact)

	# Expand and fade
	var tween = player.get_tree().create_tween()
	var final_scale = 3.0 if is_crit else 2.0
	tween.tween_property(circle, "scale", Vector2(final_scale, final_scale), 0.15)
	tween.parallel().tween_property(circle, "color:a", 0.0, 0.15)
	tween.tween_callback(impact.queue_free)

func _spawn_blood_splatter(pos: Vector2, is_crit: bool) -> void:
	"""Spawn blood splatter particles when projectile hits enemy.
	Same effect as melee hits for consistency."""
	if not player:
		return

	# Calculate direction from player to impact (blood splatters away from shot)
	var direction = (pos - player.global_position).normalized()

	# Create blood splatter particles
	var blood = CPUParticles2D.new()
	blood.global_position = pos
	blood.rotation = direction.angle()
	blood.z_index = 100  # Make sure it's visible above everything

	# Configure based on crit
	if is_crit:
		# More dramatic gold/yellow sparks for crits
		blood.amount = 24
		blood.color = Color(1, 0.85, 0.2, 1)  # Golden sparks
		blood.scale_amount_min = 0.8
		blood.scale_amount_max = 1.5
		blood.initial_velocity_min = 80.0
		blood.initial_velocity_max = 140.0
	else:
		# Dense red blood droplets - small and round
		blood.amount = 20
		blood.color = Color(0.85, 0.08, 0.08, 1.0)  # Blood red
		blood.scale_amount_min = 0.6
		blood.scale_amount_max = 1.2
		blood.initial_velocity_min = 50.0
		blood.initial_velocity_max = 90.0

	# Common properties - particles spray away from player
	blood.emitting = true
	blood.one_shot = true
	blood.lifetime = 0.4
	blood.speed_scale = 2.0
	blood.explosiveness = 0.9  # All particles spawn at once
	blood.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	blood.direction = Vector2(1, 0)  # Base direction (will be rotated)
	blood.spread = 45.0  # Cone spread
	blood.gravity = Vector2(0, 200)  # Downward gravity
	blood.damping_min = 30.0
	blood.damping_max = 60.0

	# Add to VFX layer for full brightness
	_add_vfx(blood)

	# Quick cleanup
	player.get_tree().create_timer(0.6).timeout.connect(func():
		if is_instance_valid(blood):
			blood.queue_free()
	)

# ========================================
# BATTLE RIFLE VISUAL EFFECTS (Military 7.62 Style)
# ========================================

# Track shots for tracer pattern (every 3rd round is a tracer, military style)
var _br_shot_count: int = 0

func _spawn_tracer_round(from_pos: Vector2, to_pos: Vector2) -> void:
	"""Spawn military-style 7.62 round - yellow tracer on every 3rd shot."""
	_br_shot_count += 1
	var is_tracer = (_br_shot_count % 3 == 0)  # Every 3rd round is a tracer

	if is_tracer:
		# Yellow/orange tracer round - bright streak
		var tracer = Line2D.new()
		tracer.name = "TracerRound"
		tracer.width = 2.5
		tracer.default_color = Color(1.0, 0.85, 0.2, 0.9)  # Bright yellow tracer
		tracer.add_point(from_pos)
		tracer.add_point(to_pos)
		tracer.z_index = 10

		# Add glow effect with wider faded line behind
		var glow = Line2D.new()
		glow.width = 5.0
		glow.default_color = Color(1.0, 0.6, 0.1, 0.4)  # Orange glow
		glow.add_point(from_pos)
		glow.add_point(to_pos)
		glow.z_index = 9
		tracer.add_child(glow)

		_add_vfx(tracer)

		# Quick fade out
		var tween = player.get_tree().create_tween()
		tween.tween_property(tracer, "modulate:a", 0.0, 0.1)
		tween.tween_callback(tracer.queue_free)
	else:
		# Non-tracer rounds - subtle bullet trail (barely visible)
		var trail = Line2D.new()
		trail.name = "BulletTrail"
		trail.width = 1.0
		trail.default_color = Color(0.8, 0.8, 0.7, 0.3)  # Faint gray
		trail.add_point(from_pos)
		trail.add_point(to_pos)
		trail.z_index = 8

		_add_vfx(trail)

		# Very quick fade
		var tween = player.get_tree().create_tween()
		tween.tween_property(trail, "modulate:a", 0.0, 0.06)
		tween.tween_callback(trail.queue_free)

func _spawn_battle_rifle_muzzle_flash(flash_pos: Vector2) -> void:
	"""Spawn military-style yellow/orange muzzle flash"""
	var flash_container = Node2D.new()
	flash_container.name = "BRMuzzleFlash"
	flash_container.global_position = flash_pos
	flash_container.rotation = attack_direction.angle()
	flash_container.z_index = 15
	_add_vfx(flash_container)

	# Core bright (white-yellow)
	var core = Polygon2D.new()
	core.color = Color(1.0, 0.95, 0.8, 0.95)  # Bright white-yellow
	var core_points = PackedVector2Array()
	for i in range(8):
		var angle = (float(i) / 8) * TAU
		core_points.append(Vector2(cos(angle), sin(angle)) * 4)
	core.polygon = core_points
	flash_container.add_child(core)

	# Outer glow (orange)
	var glow = Polygon2D.new()
	glow.color = Color(1.0, 0.6, 0.1, 0.6)  # Orange
	var glow_points = PackedVector2Array()
	for i in range(8):
		var angle = (float(i) / 8) * TAU
		glow_points.append(Vector2(cos(angle), sin(angle)) * 8)
	glow.polygon = glow_points
	glow.z_index = -1
	flash_container.add_child(glow)

	# Muzzle spikes (directional flash)
	var num_spikes = randi_range(2, 4)
	for i in range(num_spikes):
		var spike = Polygon2D.new()
		spike.color = Color(1.0, 0.8, 0.3, 0.7)  # Yellow-orange
		var spike_angle = randf_range(-0.3, 0.3)  # Spread around forward
		var spike_length = randf_range(10, 16)
		var spike_width = randf_range(1.5, 3)
		spike.polygon = PackedVector2Array([
			Vector2(0, 0),
			Vector2(spike_length, -spike_width),
			Vector2(spike_length + 3, 0),
			Vector2(spike_length, spike_width)
		])
		spike.rotation = spike_angle
		flash_container.add_child(spike)

	# Quick fade
	var tween = player.get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash_container, "scale", Vector2(1.2, 1.2), 0.025)
	tween.tween_property(flash_container, "modulate:a", 0.0, 0.06)
	tween.set_parallel(false)
	tween.tween_callback(flash_container.queue_free)

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
			sound_manager.play_healing_impact_sound(ally.global_position, -8.0)

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

	_add_vfx(pulse)

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

# ========================================
# FORGED WEAPON STATS TRACKING
# ========================================

func _track_weapon_hit(damage: float, is_crit: bool, enemy: Node, enemy_hp_before: float) -> void:
	"""Track hit stats for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return

	# Get enemy type
	var enemy_type = "unknown"
	if "enemy_type" in enemy:
		enemy_type = enemy.enemy_type
	elif enemy.is_in_group("training_dummy"):
		enemy_type = "training_dummy"

	# Calculate HP remaining after damage
	var hp_remaining = enemy_hp_before - damage

	# Record hit
	weapon.weapon_stats.record_hit(damage, is_crit, enemy_type, hp_remaining)

	# Check if enemy died (kill tracking handled separately via signal)

func _track_weapon_swing() -> void:
	"""Track melee swing for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_swing()

func _track_weapon_shot() -> void:
	"""Track gun shot for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_shot()

func _track_weapon_burst() -> void:
	"""Track burst fire for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_burst()

func _track_weapon_miss() -> void:
	"""Track missed attack for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_miss()

func _track_weakpoint_destroyed() -> void:
	"""Track weakpoint destruction for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_weakpoint_destroyed()

func track_enemy_killed(enemy_type: String, is_elite: bool = false, is_boss: bool = false) -> void:
	"""Track enemy kill for forged weapons (called from Enemy.gd or kill handler)"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_kill(enemy_type, is_elite, is_boss)

func track_player_death() -> void:
	"""Track player death for forged weapons"""
	var weapon = CharacterStats.equipped_weapon
	if not weapon or not weapon.is_forged or not weapon.weapon_stats:
		return
	weapon.weapon_stats.record_death()
