extends Node
# NetworkEnemyManager.gd - Server-authoritative enemy management
#
# Handles:
# - Enemy ID assignment and tracking
# - Server-side damage validation
# - Health/death state synchronization
# - Position updates to clients

# Enemy registry: network_id -> Enemy node
var enemies: Dictionary = {}
var next_enemy_id: int = 1

# Position sync rate
const POSITION_SYNC_RATE: float = 0.1  # 10Hz
var position_sync_timer: float = 0.0

# Reference to game world
var game_world: Node = null

func _ready():
	# Will be initialized by game_world
	# Listen for new peer connections to sync existing enemies
	multiplayer.peer_connected.connect(_on_peer_connected)

func _process(delta):
	if not multiplayer.has_multiplayer_peer():
		return

	if not multiplayer.is_server():
		return

	# Periodically sync enemy positions to clients
	position_sync_timer += delta
	if position_sync_timer >= POSITION_SYNC_RATE:
		position_sync_timer = 0.0
		_sync_enemy_positions()

# ═══════════════════════════════════════════════════════════════════════════
# ENEMY REGISTRATION (Server Only)
# ═══════════════════════════════════════════════════════════════════════════

func register_enemy(enemy: Node) -> int:
	"""Register an enemy and assign a network ID. Server only."""
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return -1

	var id = next_enemy_id
	next_enemy_id += 1

	enemy.network_id = id
	enemies[id] = enemy

	# Connect to enemy death signal
	if enemy.has_signal("died"):
		if not enemy.died.is_connected(_on_enemy_died):
			enemy.died.connect(_on_enemy_died.bind(id))

	return id

func unregister_enemy(network_id: int) -> void:
	"""Remove enemy from registry."""
	if enemies.has(network_id):
		enemies.erase(network_id)

func get_enemy(network_id: int) -> Node:
	"""Get enemy by network ID."""
	return enemies.get(network_id, null)

# ═══════════════════════════════════════════════════════════════════════════
# ATTACK SYSTEM (Server Authoritative - handles crit rolls)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_attack(enemy_network_id: int, damage: float) -> void:
	"""Client requests to attack an enemy. Server rolls for crit and handles result."""
	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("🌐 NetworkEnemyManager: Invalid enemy ID %d for attack" % enemy_network_id)
		return

	# Validate enemy is alive and not already in crit window
	if enemy.is_dying or enemy.is_corpse:
		return

	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server's peer ID

	# Check if enemy already in crit window
	var enemy_in_crit = false
	if "in_crit_window" in enemy:
		enemy_in_crit = enemy.in_crit_window

	if enemy_in_crit:
		# Enemy already in crit window - just apply normal damage
		print("🌐 Server: Enemy already in crit window, applying normal damage")
		_apply_damage_internal(enemy_network_id, damage, false, false, attacker_id)
		return

	# Roll for crit on server side (use attacking player's crit system if available)
	var is_crit = _server_roll_for_crit(attacker_id)

	if is_crit:
		print("🌐 Server: CRIT rolled for player %d on enemy %d!" % [attacker_id, enemy_network_id])

		# CLIENT-INDEPENDENT CRIT WINDOWS: Only the attacker sees weakpoints
		if attacker_id == 1:
			# Server player triggered crit - use server's CritWindowManager
			var crit_window_mgr = _get_server_crit_window_manager()
			if crit_window_mgr:
				crit_window_mgr.start_window(enemy)

				# Play crit window opening sound on server
				var sound_manager = get_node_or_null("/root/SoundManager")
				if sound_manager:
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -3.0)
			else:
				# Fallback: just apply damage if crit window manager not available
				print("⚠️ CritWindowManager not found, applying crit damage directly")
				_apply_damage_internal(enemy_network_id, damage * 2.0, true, false, attacker_id)
		else:
			# Client player triggered crit - notify them to start LOCAL crit window
			# Client handles their own grow, weakpoints, timers - server doesn't see their weakpoints
			start_crit_window_for_player(enemy_network_id, attacker_id)
	else:
		# Normal attack
		_apply_damage_internal(enemy_network_id, damage, false, false, attacker_id)

func _get_server_crit_window_manager() -> Node:
	"""Find the CritWindowManager from the server's player."""
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		# On server, use the first player's CritWindowManager (server's player)
		var crit_mgr = player.get_node_or_null("CritWindowManager")
		if crit_mgr:
			return crit_mgr
	return null

func _server_roll_for_crit(attacker_peer_id: int) -> bool:
	"""Server rolls for crit on behalf of a player."""
	# NOTE: We can't use CharacterStats here because it's the SERVER's stats, not the attacker's
	# For fairness, use a fixed base crit chance for all multiplayer rolls
	# The pity system runs locally on each client anyway

	# Base crit chance for multiplayer (5% default, same as level 1 player)
	var base_crit_chance = 0.05

	# If the attacker is the server player, use their actual crit system
	if attacker_peer_id == 1:
		var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
		for player in players:
			var player_peer_id = 1
			if player.has_method("get_multiplayer_authority"):
				player_peer_id = player.get_multiplayer_authority()

			if player_peer_id == 1:
				var crit_system = player.get_node_or_null("CritSystem")
				if crit_system and crit_system.has_method("roll_for_crit"):
					return crit_system.roll_for_crit()
				break

	# For clients, use the fixed base crit chance
	# TODO: Consider syncing player crit chance to server for proper pity system
	var roll = randf()
	return roll < base_crit_chance

func _apply_damage_internal(enemy_network_id: int, damage: float, is_crit: bool, is_weakpoint: bool, attacker_id: int) -> void:
	"""Internal damage application (server only)."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	# Apply damage server-side
	enemy.current_health -= damage
	enemy.current_health = max(enemy.current_health, 0.0)

	# Broadcast damage to all clients for visual feedback (include attacker_id so only attacker plays sounds)
	rpc("_client_enemy_damaged", enemy_network_id, damage, enemy.current_health, enemy.max_health, is_crit, is_weakpoint, attacker_id)

	# Check for death
	if enemy.current_health <= 0:
		_handle_enemy_death(enemy_network_id, attacker_id)

# ═══════════════════════════════════════════════════════════════════════════
# DAMAGE SYSTEM (Server Authoritative)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_damage(enemy_network_id: int, damage: float, is_crit: bool, is_weakpoint: bool) -> void:
	"""Client requests to deal damage to an enemy. Server validates and applies."""
	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("🌐 NetworkEnemyManager: Invalid enemy ID %d" % enemy_network_id)
		return

	# Validate enemy is alive
	if enemy.is_dying or enemy.is_corpse:
		return

	# Validate damage amount (basic sanity check)
	if damage <= 0 or damage > 10000:
		print("NetworkEnemyManager: Suspicious damage amount %f from peer %d" % [damage, multiplayer.get_remote_sender_id()])
		return

	# Get attacker ID for kill credit
	# get_remote_sender_id() returns 0 for local calls, so use server ID (1) in that case
	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server'sasas peer ID

	# Apply damage server-side
	enemy.current_health -= damage
	enemy.current_health = max(enemy.current_health, 0.0)

	# Broadcast damage to all clients for visual feedback (include attacker_id so only attacker plays sounds)
	rpc("_client_enemy_damaged", enemy_network_id, damage, enemy.current_health, enemy.max_health, is_crit, is_weakpoint, attacker_id)

	# Check for death
	if enemy.current_health <= 0:
		_handle_enemy_death(enemy_network_id, attacker_id)

@rpc("authority", "call_local", "reliable")
func _client_enemy_damaged(enemy_network_id: int, damage: float, new_health: float, max_health: float, is_crit: bool, is_weakpoint: bool, attacker_id: int = 0) -> void:
	"""Server broadcasts damage to all clients for visual feedback."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	# Safety check - enemy must be in scene tree for visual feedback
	if not enemy.is_inside_tree():
		# Still update health even if not in tree
		enemy.current_health = new_health
		return

	# Update local health
	enemy.current_health = new_health

	# Trigger visual feedback (hit flash, combat text, sounds)
	if enemy.has_node("HitFlash"):
		enemy.get_node("HitFlash").flash(is_crit)

	# Update health bar
	if enemy.health_bar and enemy.health_bar.has_method("update_health"):
		enemy.health_bar.update_health(new_health, max_health)

	# Spawn combat text
	_spawn_combat_text(enemy, damage, is_crit, is_weakpoint)

	# Play hit sounds (only for the attacker to avoid duplicates when testing locally)
	_play_hit_sounds(enemy, is_crit, is_weakpoint, attacker_id)

	# Trigger spin animation on TrainingDummy
	if enemy.has_method("trigger_spin"):
		enemy.trigger_spin()

	# Trigger attack particle feedback ONLY for the attacker
	# (Other players shouldn't see particles spawn at their position)
	_trigger_attack_feedback_for_attacker(enemy, is_crit, is_weakpoint, attacker_id)

	# Emit damage signal for AI aggro (server only) - don't use for player feedback
	# as that would trigger particles on ALL players
	if multiplayer.is_server():
		enemy.damage_taken.emit(damage, is_crit)

func _spawn_combat_text(enemy: Node, damage: float, is_crit: bool, is_weakpoint: bool) -> void:
	"""Spawn floating combat text above enemy."""
	# Safety check - enemy must be in scene tree
	if not enemy.is_inside_tree():
		return

	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	combat_text.text = str(int(damage))

	if is_weakpoint:
		combat_text.type = 2  # WEAKPOINT (orange)
	elif is_crit:
		combat_text.type = 1  # CRIT (yellow)
	else:
		combat_text.type = 0  # NORMAL (white)

	# Position at 70% sprite height
	var sprite = enemy.get_node_or_null("Sprite2D")
	if not sprite:
		sprite = enemy.get_node_or_null("Sprite")

	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_height = 64.0 * sprite_scale.y
	var sprite_pos = sprite.position if sprite else Vector2.ZERO
	var spawn_y_offset = -(sprite_height * 0.3)
	var spawn_x_offset = -50.0

	if is_weakpoint:
		if not enemy.has_meta("weakpoint_side"):
			enemy.set_meta("weakpoint_side", 1)
		var side = enemy.get_meta("weakpoint_side")
		spawn_x_offset = -30.0 if side > 0 else -70.0
		spawn_y_offset -= 25.0
		enemy.set_meta("weakpoint_side", -side)

	combat_text.global_position = enemy.global_position + sprite_pos + Vector2(spawn_x_offset, spawn_y_offset)
	enemy.get_tree().root.add_child(combat_text)

func _play_hit_sounds(enemy: Node, is_crit: bool, is_weakpoint: bool, _attacker_id: int = 0) -> void:
	"""Play appropriate hit sounds."""
	if is_weakpoint:
		return  # Weakpoint sounds handled in weakpoint.gd

	var sound_manager = enemy.get_node_or_null("/root/SoundManager")
	if not sound_manager:
		return

	var weapon_type = ""
	if CharacterStats.equipped_weapon:
		weapon_type = CharacterStats.equipped_weapon.weapon_type

	if is_crit:
		sound_manager.play_critical_hit_sound(enemy.global_position, -3.0)
	else:
		sound_manager.play_normal_hit_sound(enemy.global_position, -8.0, weapon_type)

	sound_manager.play_skeleton_hurt_sound(enemy.global_position, -8.0)

func _trigger_attack_feedback_for_attacker(enemy: Node, is_crit: bool, is_weakpoint: bool, attacker_id: int) -> void:
	"""Trigger attack particle feedback only for the player who attacked."""
	# Only trigger for the local player if they're the attacker
	var local_peer_id = multiplayer.get_unique_id()
	if attacker_id != local_peer_id:
		return  # Not our attack, don't show particles

	# Find the local player and trigger their attack feedback
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		# Check if this is the local player
		if player.is_multiplayer_authority():
			if player.get("attack_feedback") and player.attack_feedback:
				player.attack_feedback.trigger_attack_feedback(enemy.global_position, is_crit, is_weakpoint)
			return

# ═══════════════════════════════════════════════════════════════════════════
# DEATH SYSTEM (Server Authoritative)
# ═══════════════════════════════════════════════════════════════════════════

func _handle_enemy_death(enemy_network_id: int, killer_id: int) -> void:
	"""Server handles enemy death - generates loot, broadcasts to clients."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	# Generate loot server-side (deterministic from this point)
	var loot_data = _generate_loot(enemy)

	# Broadcast death to all clients
	rpc("_client_enemy_died", enemy_network_id, killer_id, loot_data.items, loot_data.gold)

func _generate_loot(enemy: Node) -> Dictionary:
	"""Generate loot for enemy corpse. Server only."""
	var items = []
	var gold = enemy.gold_drop

	# Roll for item drops using CorpseState
	var num_items = CorpseState.roll_loot_count()
	var is_guardian = enemy.name.contains("Guardian")

	for i in range(num_items):
		var item = CorpseState.roll_loot_item(is_guardian)
		if item:
			items.append(item)

	return {"items": items, "gold": gold}

@rpc("authority", "call_local", "reliable")
func _client_enemy_died(enemy_network_id: int, killer_id: int, loot_items: Array, loot_gold: int) -> void:
	"""Server broadcasts enemy death to all clients."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return


	# Set loot (generated by server) - must happen BEFORE die() to override local generation
	enemy.corpse_loot = loot_items
	enemy.corpse_gold = loot_gold

	# Store killer ID for XP attribution
	enemy.set_meta("killer_peer_id", killer_id)

	# Connect corpse_clicked signal NOW (GameWorld should be loaded by the time enemies die)
	# This is more reliable than connecting during spawn when GameWorld may not exist yet
	if not multiplayer.is_server():
		_ensure_corpse_signal_connected(enemy)

	# Call die() which handles:
	# - Weakpoint cleanup
	# - XP grant (only to the player who killed)
	# - Death animation
	# - Corpse transition
	if not enemy.is_dying:
		enemy.die()

func _on_enemy_died(enemy_network_id: int) -> void:
	"""Called when enemy dies (connected in register_enemy)."""
	# Death is now handled through _handle_enemy_death
	pass

# ═══════════════════════════════════════════════════════════════════════════
# POSITION SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

func _sync_enemy_positions() -> void:
	"""Send position updates for all active enemies."""
	if enemies.is_empty():
		return

	# Build position data
	var positions = {}
	for id in enemies:
		var enemy = enemies[id]
		if is_instance_valid(enemy) and not enemy.is_corpse:
			positions[id] = {
				"pos": enemy.global_position,
				"anim": _get_enemy_animation(enemy),
				"health": enemy.current_health,
				"max_health": enemy.max_health,
				# NOTE: in_crit_window is NOT synced - crit windows are per-player/local only
				"is_dying": enemy.is_dying
			}

	if not positions.is_empty():
		rpc("_client_sync_positions", positions)

@rpc("authority", "unreliable_ordered")
func _client_sync_positions(positions: Dictionary) -> void:
	"""Receive position updates from server."""
	if multiplayer.is_server():
		return  # Server doesn't need to receive its own updates

	for id in positions:
		var enemy = get_enemy(id)
		if enemy and is_instance_valid(enemy):
			var data = positions[id]
			# Interpolate to new position
			enemy.global_position = enemy.global_position.lerp(data.pos, 0.3)

			# Sync health
			if data.has("health"):
				enemy.current_health = data.health
				if enemy.health_bar and enemy.health_bar.has_method("update_health"):
					enemy.health_bar.update_health(data.health, data.get("max_health", enemy.max_health))

			# NOTE: in_crit_window is NOT synced from server
			# Crit windows are per-player/local only - each player manages their own

			# Update animation if enemy has animated sprite
			var sprite = enemy.get_node_or_null("Sprite")
			if sprite and sprite is AnimatedSprite2D and data.has("anim"):
				if sprite.animation != data.anim:
					sprite.play(data.anim)

func _get_enemy_animation(enemy: Node) -> String:
	"""Get current animation name for enemy."""
	var sprite = enemy.get_node_or_null("Sprite")
	if sprite and sprite is AnimatedSprite2D:
		return sprite.animation
	return "idle_down"

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func spawn_enemy_on_clients(network_id: int, pos: Vector2, level: int, enemy_name: String) -> void:
	"""Server tells clients to spawn an enemy."""
	if multiplayer.is_server():
		return  # Server already spawned

	var enemy_scene = load("res://scenes/enemies/enemy.tscn")
	if not enemy_scene:
		return

	var enemy = enemy_scene.instantiate()
	enemy.global_position = pos
	enemy.enemy_level = level
	enemy.name = enemy_name
	enemy.network_id = network_id

	# Register locally
	enemies[network_id] = enemy

	# Add to world - use helper to find GameWorld
	var target_parent = _find_game_world()
	if not target_parent:
		target_parent = get_tree().root

	target_parent.call_deferred("add_child", enemy)
	# Connect signals and disable AI after enemy is in tree
	call_deferred("_setup_client_enemy", enemy)

@rpc("authority", "reliable")
func despawn_enemy_on_clients(network_id: int) -> void:
	"""Server tells clients to remove an enemy."""
	var enemy = get_enemy(network_id)
	if enemy and is_instance_valid(enemy):
		enemy.queue_free()
	unregister_enemy(network_id)

@rpc("authority", "call_local", "reliable")
func spawn_training_dummy_on_clients(network_id: int, pos: Vector2) -> void:
	"""Server tells clients to spawn the training dummy."""
	if multiplayer.is_server():
		return  # Server already spawned

	var dummy_scene = load("res://scenes/training/training_dummy.tscn")
	if not dummy_scene:
		print("🌐 Client: ERROR - Could not load training_dummy.tscn")
		return

	var dummy = dummy_scene.instantiate()
	dummy.global_position = pos
	dummy.name = "TrainingDummy"
	dummy.network_id = network_id

	# Register locally
	enemies[network_id] = dummy

	# Add to world
	var target_parent = _find_game_world()
	if not target_parent:
		target_parent = get_tree().root

	target_parent.call_deferred("add_child", dummy)

func _find_game_world() -> Node:
	"""Find GameWorld node (works on both server and client)."""
	# Try cached reference first
	if game_world and is_instance_valid(game_world):
		return game_world

	# Try common paths - the main scene node name might vary
	var root = get_tree().root

	# Path 1: /root/main/GameWorld (common structure)
	var gw = root.get_node_or_null("main/GameWorld")
	if gw:
		game_world = gw  # Cache it
		return gw

	# Path 2: /root/GameWorld (direct child)
	gw = root.get_node_or_null("GameWorld")
	if gw:
		game_world = gw
		return gw

	# Path 3: Search all children of root for GameWorld
	for child in root.get_children():
		# Check if this child IS GameWorld
		if child.name == "GameWorld":
			game_world = child
			return child
		# Check if this child HAS a GameWorld child
		var potential_gw = child.get_node_or_null("GameWorld")
		if potential_gw:
			game_world = potential_gw
			return potential_gw
		# Also check if it has a Node2D child named GameWorld (scene instance)
		for grandchild in child.get_children():
			if grandchild.name == "GameWorld":
				game_world = grandchild
				return grandchild

	return null

func _setup_client_enemy(enemy: Node) -> void:
	"""Setup client-side enemy: connect signals and disable AI."""
	if not is_instance_valid(enemy):
		return

	# Try to connect corpse_clicked signal now, but don't worry if GameWorld isn't ready
	# The signal will be connected again in _client_enemy_died when the enemy actually dies
	_ensure_corpse_signal_connected(enemy)

	# Disable AI (server controls position)
	_disable_client_enemy_ai(enemy)

func _ensure_corpse_signal_connected(enemy: Node) -> void:
	"""Ensure corpse_clicked signal is connected for loot UI. Can be called multiple times safely."""
	if not is_instance_valid(enemy):
		return

	if not enemy.has_signal("corpse_clicked"):
		return

	var gw = _find_game_world()
	if gw and gw.has_method("_on_corpse_clicked"):
		if not enemy.corpse_clicked.is_connected(gw._on_corpse_clicked):
			enemy.corpse_clicked.connect(gw._on_corpse_clicked)

func _disable_client_enemy_ai(enemy: Node) -> void:
	"""Disable AI and physics on client-side enemies (server controls position)."""
	if not is_instance_valid(enemy):
		return

	# Disable EnemyAI if present
	var ai = enemy.get_node_or_null("EnemyAI")
	if ai:
		ai.set_process(false)
		ai.set_physics_process(false)

	# Mark as client-controlled (position from network)
	enemy.set_meta("is_network_puppet", true)

# ═══════════════════════════════════════════════════════════════════════════
# NEW PEER SYNC (Send existing enemies to newly connected clients)
# ═══════════════════════════════════════════════════════════════════════════

func _on_peer_connected(peer_id: int) -> void:
	"""When a new peer connects, send them all existing enemies."""
	if not multiplayer.is_server():
		return

	# Small delay to let client fully initialize
	await get_tree().create_timer(0.5).timeout


	for network_id in enemies:
		var enemy = enemies[network_id]
		if not is_instance_valid(enemy):
			continue
		if enemy.is_corpse or enemy.is_dying:
			continue  # Don't sync dead/dying enemies

		# Check if this is a TrainingDummy (different spawn RPC)
		if enemy is TrainingDummy:
			spawn_training_dummy_on_clients.rpc_id(peer_id, network_id, enemy.global_position)
		else:
			# Regular enemy
			spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name)

# ═══════════════════════════════════════════════════════════════════════════
# CRIT WINDOW SYSTEM (Client-Independent - each player sees only their own)
# ═══════════════════════════════════════════════════════════════════════════

func start_crit_window_for_player(enemy_network_id: int, attacker_peer_id: int) -> void:
	"""Server triggers crit window for a specific player. Only that player sees weakpoints."""
	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	if attacker_peer_id == 1:
		# Attacker is the server - run crit window locally
		# The server's CritWindowManager is found and used in request_attack()
		pass
	else:
		# Attacker is a client - send notification to start their local crit window
		_client_start_local_crit_window.rpc_id(attacker_peer_id, enemy_network_id)

@rpc("authority", "reliable")
func _client_start_local_crit_window(enemy_network_id: int) -> void:
	"""Client receives notification to start their OWN local crit window on this enemy."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		push_warning("Client: Cannot start crit window - enemy %d not found" % enemy_network_id)
		return

	# Play crit window opening sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and enemy.is_inside_tree():
		sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -3.0)

	# Find the local player's CritWindowManager
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	var local_player = null
	for player in all_players:
		# Find the player that belongs to this client (has multiplayer authority)
		if player.get_multiplayer_authority() == multiplayer.get_unique_id():
			local_player = player
			break

	if not local_player:
		push_warning("Client: No local player found for crit window")
		return

	var crit_window_mgr = local_player.get_node_or_null("CritWindowManager")
	if crit_window_mgr:
		# Start local crit window - this handles grow, weakpoints, timers, everything
		crit_window_mgr.start_window(enemy)
	else:
		push_warning("Client: CritWindowManager not found on player")

func notify_crit_window_end_to_player(enemy_network_id: int, attacker_peer_id: int) -> void:
	"""Server notifies a specific player that their crit window ended (for cleanup sync)."""
	if not multiplayer.is_server():
		return

	if attacker_peer_id != 1:
		# Only send to clients, server handles its own cleanup
		_client_crit_window_ended.rpc_id(attacker_peer_id, enemy_network_id)

@rpc("authority", "reliable")
func _client_crit_window_ended(_enemy_network_id: int) -> void:
	"""Client receives notification that their crit window ended (server-side cleanup confirmation)."""
	# This is just for sync purposes - the client's crit_window_manager already handles local cleanup
	pass

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER DAMAGE SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

func deal_damage_to_player(target_peer_id: int, damage: float) -> void:
	"""Server tells a specific client to take damage."""
	if not multiplayer.is_server():
		return

	# If target is server (peer_id 1), apply locally
	if target_peer_id == 1:
		var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player and player.has_method("take_damage"):
			player.take_damage(damage)
	else:
		# Send to specific client
		_client_take_damage.rpc_id(target_peer_id, damage)

@rpc("authority", "reliable")
func _client_take_damage(damage: float) -> void:
	"""Client receives damage from server (enemy attack)."""
	# Find local player and apply damage
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		# Find the player that belongs to this client
		if player.has_method("take_damage"):
			# In multiplayer, each client has their own local player
			if player.get_multiplayer_authority() == multiplayer.get_unique_id() or not multiplayer.has_multiplayer_peer():
				player.take_damage(damage)
				return

	# Fallback: just damage first player found
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("take_damage"):
		player.take_damage(damage)

# ═══════════════════════════════════════════════════════════════════════════
# CRIT WINDOW RESULT REPORTING (Client-Predicted System)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func report_crit_window_result(enemy_network_id: int, weakpoints_destroyed: int, total_damage: int) -> void:
	"""Client reports crit window results. Server validates and applies damage."""
	if not multiplayer.is_server():
		return

	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server's peer ID

	process_crit_window_result(enemy_network_id, weakpoints_destroyed, total_damage, attacker_id)

func process_crit_window_result(enemy_network_id: int, weakpoints_destroyed: int, total_damage: int, attacker_id: int) -> void:
	"""Server processes and validates crit window results."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	# Get attacker's expected weakpoint count based on their level
	var expected_weakpoints = _get_expected_weakpoint_count(attacker_id)

	# Anti-cheat: Check if reported weakpoints exceeds what player should have
	if weakpoints_destroyed > expected_weakpoints:
		push_warning("Anti-cheat: Player %d reported %d weakpoints but should have max %d (level-based)" % [
			attacker_id, weakpoints_destroyed, expected_weakpoints
		])
		# Clamp to expected value
		weakpoints_destroyed = expected_weakpoints

	# Validate damage doesn't exceed maximum possible
	var max_damage = _calculate_max_crit_damage(enemy, attacker_id)
	var validated_damage = mini(total_damage, max_damage)

	# Apply validated damage
	if validated_damage > 0:
		_apply_damage_internal(enemy_network_id, float(validated_damage), true, true, attacker_id)

	# CLIENT-INDEPENDENT: Crit window cleanup is handled locally by each player's CritWindowManager
	# Optionally notify the specific attacker that server processed their results
	notify_crit_window_end_to_player(enemy_network_id, attacker_id)

func _get_expected_weakpoint_count(attacker_peer_id: int) -> int:
	"""Get expected weakpoint count based on attacker's level."""
	var attacker_level = 1

	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()

		if player_peer_id == attacker_peer_id:
			if player.has_method("get_level"):
				attacker_level = player.get_level()
			elif player.get("level") != null:
				attacker_level = player.level
			break

	return _get_weakpoint_count_for_level(attacker_level)

func _calculate_max_crit_damage(_enemy: Node, attacker_peer_id: int) -> int:
	"""Calculate maximum possible crit window damage for validation."""
	# Get player's level and damage stats
	var attacker_level = 1
	var base_damage = 10
	var crit_mult = 2.0

	# Try to find the attacking player's stats
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()

		if player_peer_id == attacker_peer_id:
			if player.get("attack_damage") != null:
				base_damage = player.attack_damage
			# Get player level for weakpoint count calculation
			if player.has_method("get_level"):
				attacker_level = player.get_level()
			elif player.get("level") != null:
				attacker_level = player.level
			break

	# Calculate weakpoint count based on ATTACKER's level (not server's CharacterStats)
	var num_weakpoints = _get_weakpoint_count_for_level(attacker_level)

	# Get max hits per weakpoint (usually 3-5)
	var hits_per_weakpoint = 5  # Max possible

	if "CRIT_DAMAGE_MULTIPLIER" in Constants:
		crit_mult = Constants.CRIT_DAMAGE_MULTIPLIER

	var damage_per_hit = int(base_damage * crit_mult)
	var max_possible = num_weakpoints * hits_per_weakpoint * damage_per_hit

	return max_possible

func _get_weakpoint_count_for_level(player_level: int) -> int:
	"""Calculate number of weakpoints based on player level."""
	if player_level >= 21:
		return 3  # Level 21+: All 3 weakpoints
	elif player_level >= 11:
		return 2  # Level 11-20: 2 weakpoints
	else:
		return 1  # Level 1-10: 1 weakpoint
