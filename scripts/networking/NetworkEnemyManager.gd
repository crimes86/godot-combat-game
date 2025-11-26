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
		# Start crit window on server (this will broadcast to clients via Enemy.spawn_weakpoints)
		# Find CritWindowManager from the server's player (it's a child node, not an autoload)
		var crit_window_mgr = _get_server_crit_window_manager()
		if crit_window_mgr:
			crit_window_mgr.start_window(enemy)

			# Play crit window opening sound
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager:
				sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -3.0)
		else:
			# Fallback: just apply damage if crit window manager not available
			print("⚠️ CritWindowManager not found, applying crit damage directly")
			_apply_damage_internal(enemy_network_id, damage * 2.0, true, false, attacker_id)
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
	# Try to find the attacking player's crit system
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1  # Default to server
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()
		elif player.has_meta("peer_id"):
			player_peer_id = player.get_meta("peer_id")

		if player_peer_id == attacker_peer_id:
			# Found the attacking player
			var crit_system = player.get_node_or_null("CritSystem")
			if crit_system and crit_system.has_method("roll_for_crit"):
				print("🌐 Server: Rolling crit for player %d using their CritSystem" % attacker_peer_id)
				return crit_system.roll_for_crit()

	# Fallback: use base crit chance (5%)
	var base_crit_chance = 0.05
	if CharacterStats:
		base_crit_chance = CharacterStats.get_base_crit_chance()
	var roll = randf()
	print("🌐 Server: Crit roll (fallback) for player %d: %.4f vs %.2f%%" % [attacker_peer_id, roll, base_crit_chance * 100])
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
		attacker_id = 1  # Server's peer ID

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
	print("🔊 _client_enemy_damaged() called (is_server=%s, enemy_id=%d, damage=%.1f, attacker=%d)" % [multiplayer.is_server(), enemy_network_id, damage, attacker_id])
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

	# Emit damage signal for any listeners (triggers AI aggro on server)
	if multiplayer.is_server():
		print("🌐 Server emitting damage_taken for %s (damage=%.1f, connections=%d)" % [
			enemy.name, damage, enemy.damage_taken.get_connections().size()
		])
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

	print("🌐 _client_enemy_died: id=%d, killer=%d, gold=%d, items=%d (is_server=%s)" % [
		enemy_network_id, killer_id, loot_gold, loot_items.size(), multiplayer.is_server()
	])

	# Set loot (generated by server) - must happen BEFORE die() to override local generation
	enemy.corpse_loot = loot_items
	enemy.corpse_gold = loot_gold

	# Store killer ID for XP attribution
	enemy.set_meta("killer_peer_id", killer_id)

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
				"in_crit_window": enemy.get("in_crit_window") == true,
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

			# Sync crit window state
			if data.has("in_crit_window"):
				enemy.in_crit_window = data.in_crit_window

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
	print("🌐 Client: Training Dummy spawned at %s (network_id=%d)" % [pos, network_id])

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

	# Debug: print what's under root if we can't find it
	print("🌐 _find_game_world: WARNING - GameWorld not found! Root children:")
	for child in root.get_children():
		print("   - %s (%s)" % [child.name, child.get_class()])
		for gc in child.get_children():
			if gc.name.contains("World") or gc.name.contains("Game"):
				print("     - %s (%s)" % [gc.name, gc.get_class()])

	return null

func _setup_client_enemy(enemy: Node) -> void:
	"""Setup client-side enemy: connect signals and disable AI."""
	if not is_instance_valid(enemy):
		return

	# Connect corpse_clicked signal for loot UI (game_world handles the UI)
	var gw = _find_game_world()
	if gw and gw.has_method("_on_corpse_clicked"):
		if enemy.has_signal("corpse_clicked") and not enemy.corpse_clicked.is_connected(gw._on_corpse_clicked):
			enemy.corpse_clicked.connect(gw._on_corpse_clicked)
			print("🌐 Client: Connected corpse_clicked for: %s" % enemy.name)
	else:
		print("🌐 Client: WARNING - Could not find GameWorld for corpse_clicked signal (gw=%s)" % gw)

	# Disable AI (server controls position)
	_disable_client_enemy_ai(enemy)

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

	print("🌐 NetworkEnemyManager: Syncing %d enemies to new peer %d" % [enemies.size(), peer_id])

	for network_id in enemies:
		var enemy = enemies[network_id]
		if not is_instance_valid(enemy):
			continue
		if enemy.is_corpse or enemy.is_dying:
			continue  # Don't sync dead/dying enemies

		# Check if this is a TrainingDummy (different spawn RPC)
		if enemy is TrainingDummy:
			spawn_training_dummy_on_clients.rpc_id(peer_id, network_id, enemy.global_position)
			print("   → Synced TrainingDummy (id=%d) at %s" % [network_id, enemy.global_position])
		else:
			# Regular enemy
			spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name)
			print("   → Synced enemy %s (id=%d) at %s" % [enemy.name, network_id, enemy.global_position])

# ═══════════════════════════════════════════════════════════════════════════
# CRIT WINDOW SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

func broadcast_crit_window_start(enemy_network_id: int, weakpoint_positions: Array) -> void:
	"""Server broadcasts crit window start to all clients."""
	if not multiplayer.is_server():
		return

	# Convert Vector2 array to serializable format (array of dictionaries)
	var serialized_positions = []
	for pos in weakpoint_positions:
		serialized_positions.append({"x": pos.x, "y": pos.y})

	print("🌐 NetworkEnemyManager: Broadcasting crit window for enemy %d (positions: %s)" % [enemy_network_id, serialized_positions])
	rpc("_client_crit_window_start", enemy_network_id, serialized_positions)

@rpc("authority", "call_local", "reliable")
func _client_crit_window_start(enemy_network_id: int, serialized_positions: Array) -> void:
	"""Client receives crit window start - spawn weakpoints locally."""
	if multiplayer.is_server():
		return  # Server already has weakpoints

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("🌐 Client: Cannot start crit window - enemy %d not found" % enemy_network_id)
		return

	# Convert serialized positions back to Vector2 array
	var weakpoint_positions = []
	for pos_dict in serialized_positions:
		weakpoint_positions.append(Vector2(pos_dict.x, pos_dict.y))

	print("🌐 Client: Crit window started for enemy %d with %d weakpoints" % [enemy_network_id, weakpoint_positions.size()])

	# Play crit window opening sound on client
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -3.0)

	# Grow sprite for crit window visuals
	enemy.in_crit_window = true
	if enemy.has_method("grow_for_crit_window_client"):
		enemy.grow_for_crit_window_client(weakpoint_positions)
	elif enemy.has_method("spawn_weakpoints_at_positions"):
		enemy.spawn_weakpoints_at_positions(weakpoint_positions)

func broadcast_crit_window_end(enemy_network_id: int) -> void:
	"""Server broadcasts crit window end to all clients."""
	if not multiplayer.is_server():
		return
	rpc("_client_crit_window_end", enemy_network_id)

@rpc("authority", "call_local", "reliable")
func _client_crit_window_end(enemy_network_id: int) -> void:
	"""Client receives crit window end - cleanup weakpoints."""
	if multiplayer.is_server():
		return  # Server handles its own cleanup

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	print("🌐 Client: Crit window ended for enemy %d" % enemy_network_id)
	enemy.in_crit_window = false
	if enemy.has_method("shrink_after_crit_window"):
		enemy.shrink_after_crit_window()

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
				print("🌐 Client: Taking %.1f damage from enemy attack" % damage)
				player.take_damage(damage)
				return

	# Fallback: just damage first player found
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("take_damage"):
		print("🌐 Client: Taking %.1f damage (fallback)" % damage)
		player.take_damage(damage)

# ═══════════════════════════════════════════════════════════════════════════
# WEAKPOINT SYNC (Clients report hits, server broadcasts destruction)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_weakpoint_hit(enemy_network_id: int, weakpoint_index: int) -> void:
	"""Client reports hitting a weakpoint. Server validates and broadcasts destruction if needed."""
	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		print("🌐 Server: Weakpoint hit - invalid enemy %d" % enemy_network_id)
		return

	if not enemy.in_crit_window:
		print("🌐 Server: Weakpoint hit rejected - enemy not in crit window")
		return

	# Find the weakpoint on the server's enemy
	if weakpoint_index < 0 or weakpoint_index >= enemy.weakpoints.size():
		print("🌐 Server: Invalid weakpoint index %d (enemy has %d)" % [weakpoint_index, enemy.weakpoints.size()])
		return

	var weakpoint = enemy.weakpoints[weakpoint_index]
	if not is_instance_valid(weakpoint) or weakpoint.is_destroyed:
		print("🌐 Server: Weakpoint %d already destroyed" % weakpoint_index)
		return

	# Hit the server's weakpoint
	print("🌐 Server: Weakpoint %d hit on enemy %d" % [weakpoint_index, enemy_network_id])
	weakpoint.hit()
	var is_destroyed_now = weakpoint.is_destroyed

	# Broadcast hit to all clients (INCLUDING the sender so they sync destruction state)
	for peer_id in multiplayer.get_peers():
		_client_weakpoint_hit.rpc_id(peer_id, enemy_network_id, weakpoint_index, is_destroyed_now)

@rpc("authority", "reliable")
func _client_weakpoint_hit(enemy_network_id: int, weakpoint_index: int, is_destroyed: bool = false) -> void:
	"""Server broadcasts that a weakpoint was hit (for visual sync on all clients)."""
	if multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	if weakpoint_index < 0 or weakpoint_index >= enemy.weakpoints.size():
		print("🌐 Client: Weakpoint %d - invalid index (have %d)" % [weakpoint_index, enemy.weakpoints.size()])
		return

	var weakpoint = enemy.weakpoints[weakpoint_index]
	if not is_instance_valid(weakpoint):
		print("🌐 Client: Weakpoint %d - instance invalid" % weakpoint_index)
		return

	if is_destroyed:
		# Server says this weakpoint is destroyed - force destruction on client
		if not weakpoint.is_destroyed:
			print("🌐 Client: Weakpoint %d DESTROYED (synced from server)" % weakpoint_index)
			weakpoint.destroy()  # Call destroy directly instead of hit()
	elif not weakpoint.is_destroyed:
		# Just a hit, not destruction - use visual feedback only (don't track hit count)
		print("🌐 Client: Weakpoint %d hit (synced from server)" % weakpoint_index)
		if weakpoint.has_method("_play_hit_feedback_only"):
			weakpoint._play_hit_feedback_only()
		else:
			# Fallback if method doesn't exist - but this shouldn't call hit()
			# as that would increment local count
			pass
