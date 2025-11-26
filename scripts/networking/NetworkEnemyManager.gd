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

	# Broadcast damage to all clients for visual feedback
	rpc("_client_enemy_damaged", enemy_network_id, damage, enemy.current_health, enemy.max_health, is_crit, is_weakpoint)

	# Check for death
	if enemy.current_health <= 0:
		_handle_enemy_death(enemy_network_id, attacker_id)

@rpc("authority", "call_local", "reliable")
func _client_enemy_damaged(enemy_network_id: int, damage: float, new_health: float, max_health: float, is_crit: bool, is_weakpoint: bool) -> void:
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

	# Play hit sounds
	_play_hit_sounds(enemy, is_crit, is_weakpoint)

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

func _play_hit_sounds(enemy: Node, is_crit: bool, is_weakpoint: bool) -> void:
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

	# Add to world - try game_world first, fallback to finding it or using root
	var target_parent = game_world
	if not target_parent:
		target_parent = get_tree().root.get_node_or_null("GameWorld")
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

func _setup_client_enemy(enemy: Node) -> void:
	"""Setup client-side enemy: connect signals and disable AI."""
	if not is_instance_valid(enemy):
		return

	# Connect corpse_clicked signal for loot UI (game_world handles the UI)
	var gw = game_world if game_world else get_tree().root.get_node_or_null("GameWorld")
	if gw and gw.has_method("_on_corpse_clicked"):
		if not enemy.corpse_clicked.is_connected(gw._on_corpse_clicked):
			enemy.corpse_clicked.connect(gw._on_corpse_clicked)
			print("🌐 Client: Connected corpse_clicked for: %s" % enemy.name)

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

		# Send spawn command to this specific peer
		spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name)
		print("   → Synced enemy %s (id=%d) at %s" % [enemy.name, network_id, enemy.global_position])
