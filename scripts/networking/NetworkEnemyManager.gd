extends Node
# NetworkEnemyManager.gd - Server-authoritative enemy management
#
# Handles:
# - Enemy ID assignment and tracking
# - Server-side damage validation
# - Health/death state synchronization
# - Position updates to clients

# Enemy registry: network_id -> Enemy node
var enemies: Dictionary = {}  # Dictionary[int, Node]
var next_enemy_id: int = 1

# Staggered loot notification queue (prevents flash when AOE looting multiple corpses)
var _gold_loot_queue: Array = []  # Array of {amount: int, position: Vector2}
var _gold_loot_timer: float = 0.0
const GOLD_LOOT_STAGGER_DELAY: float = 0.08  # 80ms between each notification

# Position sync rate
const POSITION_SYNC_RATE: float = 0.05  # 20Hz (was 10Hz - increased for smoother movement)
var position_sync_timer: float = 0.0

# Interest Management - only sync enemies near each player (reduces bandwidth ~80%)
const SYNC_RADIUS_FULL: float = 1500.0      # Full 20Hz sync for nearby enemies
const SYNC_RADIUS_REDUCED: float = 3000.0   # 5Hz sync for mid-range enemies
const SYNC_RADIUS_MAX: float = 4000.0       # Beyond this, don't sync at all
var reduced_sync_counter: int = 0           # Counter to throttle reduced-rate syncs

# Interest Management for SPAWNING - clients only load enemies within this radius
# Uses same radius as position sync for consistency
const SPAWN_RADIUS: float = 4000.0          # Spawn enemies within this radius of player
const SPAWN_HYSTERESIS: float = 500.0       # Extra buffer before despawning (prevents flicker)
const VISIBILITY_CHECK_RATE: float = 0.5    # Check visibility every 0.5s (not every frame)
var visibility_check_timer: float = 0.0

# Track which enemies each client knows about: peer_id -> {network_id: true}
var client_known_enemies: Dictionary = {}   # Dictionary[int, Dictionary[int, bool]]

# Client-side interpolation data for smooth movement
var enemy_target_positions: Dictionary = {}  # network_id -> target position
var enemy_interpolation_speeds: Dictionary = {}  # network_id -> calculated speed

# Reference to game world
var game_world: Node = null

# Attack cooldown tracking (server-side anti-cheat)
var attack_cooldowns: Dictionary = {}  # Dictionary[int, int] - peer_id -> last_attack_time_msec
const ATTACK_COOLDOWN_MS: int = 90  # Minimum ms between attacks (tightened from 80ms, client uses 100ms)

# Anti-cheat violation tracking with exponential backoff
var violation_counts: Dictionary = {}  # Dictionary[int, int] - peer_id -> violation_count
var violation_cooldowns: Dictionary = {}  # Dictionary[int, int] - peer_id -> cooldown_until_msec
const VIOLATION_THRESHOLD_WARN: int = 3  # Warn after this many violations
const VIOLATION_THRESHOLD_TIMEOUT: int = 5  # Start timeout after this many
const VIOLATION_THRESHOLD_KICK: int = 10  # Kick after this many
const BASE_TIMEOUT_MS: int = 1000  # Base timeout (1 second)
const MAX_TIMEOUT_MS: int = 60000  # Max timeout (60 seconds)

# Tutorial crit tracking (server-side) - tracks hits per player on training dummy
var tutorial_dummy_hits: Dictionary = {}  # Dictionary[int, int] - peer_id -> hit_count
const TUTORIAL_FORCE_CRIT_HITS: int = 5  # Force crit after this many hits on dummy during tutorial

# Dead player tracking (server-side) - enemies stop attacking dead players
var dead_players: Dictionary = {}  # Dictionary[int, bool] - peer_id -> is_dead

# Valid item rarities and types for validation
const VALID_RARITIES: Array = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const VALID_ITEM_TYPES: Array = ["weapon", "armor", "consumable", "material", "bone", "key_item", "misc"]

func _validate_loot_item(item: Dictionary) -> Dictionary:
	"""Validate and sanitize a loot item. Returns empty dict if invalid."""
	if not item is Dictionary:
		return {}

	# Required fields
	var name = item.get("name", "")
	if not name is String or name.is_empty() or name.length() > 64:
		LogManager.warn("Invalid item: missing or invalid name", "security")
		return {}

	var type = item.get("type", "misc")
	if not type is String or type not in VALID_ITEM_TYPES:
		type = "misc"

	# Sanitize and validate item
	var sanitized: Dictionary = {
		"name": name.strip_edges().substr(0, 64),
		"type": type
	}

	# Optional fields with validation
	var rarity = item.get("rarity", "Common")
	if rarity is String and rarity in VALID_RARITIES:
		sanitized["rarity"] = rarity
	else:
		sanitized["rarity"] = "Common"

	# Numeric fields with clamping
	if item.has("damage"):
		var damage = item.get("damage", 0)
		if damage is float or damage is int:
			sanitized["damage"] = clampi(int(damage), 0, 9999)

	if item.has("defense"):
		var defense = item.get("defense", 0)
		if defense is float or defense is int:
			sanitized["defense"] = clampi(int(defense), 0, 9999)

	if item.has("value"):
		var value = item.get("value", 0)
		if value is float or value is int:
			sanitized["value"] = clampi(int(value), 0, 999999)

	if item.has("quantity"):
		var quantity = item.get("quantity", 1)
		if quantity is float or quantity is int:
			sanitized["quantity"] = clampi(int(quantity), 1, 999)

	# Stacking fields (important for inventory management)
	if item.has("stackable"):
		sanitized["stackable"] = bool(item.get("stackable", false))

	if item.has("max_stack"):
		var max_stack = item.get("max_stack", 1)
		if max_stack is float or max_stack is int:
			sanitized["max_stack"] = clampi(int(max_stack), 1, 999)

	# Copy through other safe fields
	for key in ["description", "sprite_path", "weapon_type", "slot", "fuel_type", "sprite_name", "id"]:
		if item.has(key) and item[key] is String:
			sanitized[key] = item[key].substr(0, 256)

	return sanitized

func _validate_loot_array(items: Array) -> Array:
	"""Validate and sanitize an array of loot items."""
	var validated: Array = []
	for item in items:
		var valid_item = _validate_loot_item(item)
		if not valid_item.is_empty():
			validated.append(valid_item)
		if validated.size() >= 20:  # Max 20 items from one enemy
			break
	return validated

func _ready():
	# Will be initialized by game_world
	# Listen for peer connections to sync existing enemies and cleanup on disconnect
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_disconnected(peer_id: int) -> void:
	"""Clean up attack cooldown and violation tracking when a player disconnects"""
	attack_cooldowns.erase(peer_id)
	tutorial_dummy_hits.erase(peer_id)
	violation_counts.erase(peer_id)
	violation_cooldowns.erase(peer_id)
	client_known_enemies.erase(peer_id)  # Clean up enemy visibility tracking

func _is_peer_connected(peer_id: int) -> bool:
	"""Check if a peer is still connected before sending RPCs.
	Prevents 'unknown peer ID' errors when peers disconnect mid-sync."""
	if peer_id == 1:
		return true  # Server is always "connected"
	return peer_id in multiplayer.get_peers()

func _record_violation(peer_id: int, violation_type: String) -> bool:
	"""Record an anti-cheat violation and apply exponential backoff.
	Returns true if the action should be blocked, false if just warned."""
	var current_time = Time.get_ticks_msec()

	# Initialize if first violation
	if not violation_counts.has(peer_id):
		violation_counts[peer_id] = 0

	# Increment violation count
	violation_counts[peer_id] += 1
	var count = violation_counts[peer_id]

	# Log the violation
	push_warning("Anti-cheat: Player %d violation #%d: %s" % [peer_id, count, violation_type])

	# Check if player is in timeout
	if violation_cooldowns.has(peer_id):
		if current_time < violation_cooldowns[peer_id]:
			var remaining = (violation_cooldowns[peer_id] - current_time) / 1000.0
			push_warning("Anti-cheat: Player %d in timeout (%.1fs remaining)" % [peer_id, remaining])
			return true  # Block action

	# Apply escalating consequences
	if count >= VIOLATION_THRESHOLD_KICK:
		push_error("Anti-cheat: Player %d exceeded violation limit (%d), should be kicked" % [peer_id, count])
		# Note: Actual kick would need NetworkManager integration
		# For now, apply max timeout
		violation_cooldowns[peer_id] = current_time + MAX_TIMEOUT_MS
		return true

	if count >= VIOLATION_THRESHOLD_TIMEOUT:
		# Calculate exponential backoff: BASE * 2^(violations - threshold)
		var backoff_multiplier = 1 << (count - VIOLATION_THRESHOLD_TIMEOUT)  # 2^n
		var timeout_ms = mini(BASE_TIMEOUT_MS * backoff_multiplier, MAX_TIMEOUT_MS)
		violation_cooldowns[peer_id] = current_time + timeout_ms
		push_warning("Anti-cheat: Player %d timed out for %d ms" % [peer_id, timeout_ms])
		return true

	if count >= VIOLATION_THRESHOLD_WARN:
		push_warning("Anti-cheat: Player %d has %d violations (kick at %d)" % [peer_id, count, VIOLATION_THRESHOLD_KICK])

	return false  # Allow action but recorded violation

func _is_player_timed_out(peer_id: int) -> bool:
	"""Check if a player is currently in anti-cheat timeout"""
	if not violation_cooldowns.has(peer_id):
		return false
	return Time.get_ticks_msec() < violation_cooldowns[peer_id]

func _process(delta):
	# Process staggered gold loot notifications
	_process_gold_loot_queue(delta)

	if not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		# Periodically sync enemy positions to clients
		position_sync_timer += delta
		if position_sync_timer >= POSITION_SYNC_RATE:
			position_sync_timer = 0.0
			_sync_enemy_positions()

		# Periodically check which enemies should be spawned/despawned for each client
		visibility_check_timer += delta
		if visibility_check_timer >= VISIBILITY_CHECK_RATE:
			visibility_check_timer = 0.0
			_update_client_enemy_visibility()
	else:
		# Client: smoothly interpolate enemies toward their target positions
		_interpolate_enemy_positions(delta)

func _interpolate_enemy_positions(delta: float) -> void:
	"""Client-side smooth interpolation of enemy positions using exponential smoothing."""
	const LERP_SPEED: float = 12.0  # Higher = snappier, lower = smoother (10-15 feels good)

	for id in enemy_target_positions:
		var enemy = get_enemy(id)
		if not enemy or not is_instance_valid(enemy):
			continue

		var target_pos = enemy_target_positions[id]
		var current_pos = enemy.global_position
		var distance = current_pos.distance_to(target_pos)

		# If very close, snap to target
		if distance < 0.5:
			enemy.global_position = target_pos
			continue

		# If too far (lag spike or teleport), snap immediately
		if distance > 500.0:
			enemy.global_position = target_pos
			continue

		# Exponential smoothing - moves faster when far, slower when close
		# This creates smooth deceleration as enemy approaches target
		var t = clampf(delta * LERP_SPEED, 0.0, 1.0)
		enemy.global_position = current_pos.lerp(target_pos, t)

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
	"""Get enemy by network ID. Returns null if enemy is freed or doesn't exist."""
	if not enemies.has(network_id):
		return null

	# Check validity before returning - use is_instance_valid on the dictionary value directly
	if not is_instance_valid(enemies[network_id]):
		# Clean up freed enemy from dictionary
		enemies.erase(network_id)
		return null

	return enemies[network_id]

# ═══════════════════════════════════════════════════════════════════════════
# ATTACK SYSTEM (Server Authoritative - handles crit rolls)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_attack(enemy_network_id: int, damage: float) -> void:
	"""Client requests to attack an enemy. Server rolls for crit and handles result."""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		push_warning("NetworkEnemyManager: Invalid enemy ID %d for attack" % enemy_network_id)
		return

	# Validate enemy is alive and not already in crit window
	if enemy.is_dying or enemy.is_corpse:
		return

	# SECURITY: Get actual sender ID (cannot be spoofed)
	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server's peer ID

	# SECURITY: Check if player is in anti-cheat timeout
	if _is_player_timed_out(attacker_id):
		return  # Silently ignore requests during timeout

	# NOTE: Attack speed is uncapped by design - we validate damage instead

	# SECURITY: Validate damage is within reasonable bounds for player's level
	var max_base_damage = _get_max_player_damage(attacker_id)
	if damage <= 0 or damage > max_base_damage * 1.5:  # Allow 50% buffer for variance
		_record_violation(attacker_id, "suspicious damage %.1f (max: %.1f)" % [damage, max_base_damage])
		damage = clampf(damage, 1.0, max_base_damage)

	# Check if enemy already in crit window
	var enemy_in_crit = false
	if "in_crit_window" in enemy:
		enemy_in_crit = enemy.in_crit_window

	if enemy_in_crit:
		# Enemy already in crit window - just apply normal damage
		LogManager.debug("Enemy already in crit window, applying normal damage", "combat")
		_apply_damage_internal(enemy_network_id, damage, false, false, attacker_id)
		return

	# Check if this is a training dummy - track tutorial hits for forced crit
	var is_training_dummy = enemy.is_in_group("training_dummy")
	if is_training_dummy:
		if not tutorial_dummy_hits.has(attacker_id):
			tutorial_dummy_hits[attacker_id] = 0
		tutorial_dummy_hits[attacker_id] += 1

	# Roll for crit on server side (use attacking player's crit system if available)
	# Force crit on training dummy after enough hits during tutorial
	var is_crit = false
	if is_training_dummy and tutorial_dummy_hits.get(attacker_id, 0) >= TUTORIAL_FORCE_CRIT_HITS:
		# Force crit for tutorial
		is_crit = true
		tutorial_dummy_hits[attacker_id] = 0  # Reset for next crit window
		LogManager.debug("FORCED CRIT for tutorial (player %d hit dummy %d times)" % [attacker_id, TUTORIAL_FORCE_CRIT_HITS], "tutorial")
	else:
		is_crit = _server_roll_for_crit(attacker_id, is_training_dummy)

	# Check if legacy crit-based triggers are enabled (for backwards compatibility)
	# New system uses hit count and health thresholds instead of random crits
	var use_legacy_crit_triggers = Constants.WEAKPOINT_TRIGGER_ON_CRIT if "WEAKPOINT_TRIGGER_ON_CRIT" in Constants else false

	if is_crit and use_legacy_crit_triggers:
		LogManager.debug("CRIT rolled for player %d on enemy %d! (LEGACY MODE)" % [attacker_id, enemy_network_id], "combat")

		# CLIENT-INDEPENDENT CRIT WINDOWS: Only the attacker sees weakpoints
		if attacker_id == 1:
			# Server player triggered crit - use server's CritWindowManager
			var crit_window_mgr = _get_server_crit_window_manager()
			if crit_window_mgr:
				crit_window_mgr.start_window(enemy)

				# Play crit window opening sound on server
				var sound_manager = get_node_or_null("/root/SoundManager")
				if sound_manager:
					sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -10.0)
			else:
				# Fallback: just apply damage if crit window manager not available
				LogManager.warn("CritWindowManager not found, applying crit damage directly", "combat")
				_apply_damage_internal(enemy_network_id, damage * 2.0, true, false, attacker_id)
		else:
			# Client player triggered crit - notify them to start LOCAL crit window
			# Client handles their own grow, weakpoints, timers - server doesn't see their weakpoints
			start_crit_window_for_player(enemy_network_id, attacker_id)
	else:
		# NEW SYSTEM: Crits deal bonus damage but windows are triggered by hit count/health thresholds
		# Window triggering is handled client-side via PlayerCombat.register_hit()
		var final_damage = damage
		if is_crit:
			final_damage = damage * 2.0  # Crit still deals double damage
			LogManager.debug("CRIT rolled for player %d on enemy %d (bonus damage only, no window)" % [attacker_id, enemy_network_id], "combat")
		_apply_damage_internal(enemy_network_id, final_damage, is_crit, false, attacker_id)

func _get_server_crit_window_manager() -> Node:
	"""Find the CritWindowManager from the server's player."""
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		# On server, use the first player's CritWindowManager (server's player)
		var crit_mgr = player.get_node_or_null("CritWindowManager")
		if crit_mgr:
			return crit_mgr
	return null

func _server_roll_for_crit(attacker_peer_id: int, is_training_dummy: bool = false) -> bool:
	"""Server rolls for crit on behalf of a player."""
	# NOTE: We can't use CharacterStats here because it's the SERVER's stats, not the attacker's
	# For fairness, use a fixed base crit chance for all multiplayer rolls
	# The pity system runs locally on each client anyway

	# Base crit chance for multiplayer (5% default, same as level 1 player)
	# Training dummy has higher crit chance (15%) to help with tutorial progression
	var base_crit_chance = 0.15 if is_training_dummy else 0.05

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
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		push_warning("NetworkEnemyManager: Invalid enemy ID %d" % enemy_network_id)
		return

	# Validate enemy is alive
	if enemy.is_dying or enemy.is_corpse:
		return

	# SECURITY: Get actual sender ID (cannot be spoofed)
	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server's peer ID

	# SECURITY: Check if player is in anti-cheat timeout
	if _is_player_timed_out(attacker_id):
		return  # Silently ignore requests during timeout

	# NOTE: Attack speed is uncapped by design - we validate damage instead

	# SECURITY: Validate damage amount based on player's actual stats
	var max_expected_damage = _get_max_player_damage(attacker_id)
	if is_crit:
		max_expected_damage *= 2.5  # Crit multiplier + buffer
	if is_weakpoint:
		max_expected_damage *= 2.5  # Weakpoint multiplier + buffer

	if damage <= 0 or damage > max_expected_damage:
		_record_violation(attacker_id, "suspicious damage %.1f (max: %.1f, crit: %s, wp: %s)" % [
			damage, max_expected_damage, is_crit, is_weakpoint
		])
		damage = clampf(damage, 1.0, max_expected_damage)

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

	# Update local health (needed on both server and client)
	enemy.current_health = new_health

	# Emit damage signal for AI aggro (needed on server for enemy AI)
	if enemy.is_inside_tree():
		enemy.damage_taken.emit(damage, is_crit)

	# DEDICATED SERVER: Skip all visual/audio operations to prevent memory leak
	# Combat text, sounds, particles, etc. are client-only visual feedback
	if "--server" in OS.get_cmdline_user_args():
		return

	# Safety check - enemy must be in scene tree for visual feedback
	if not enemy.is_inside_tree():
		return

	# Tutorial: Notify TutorialManager if this is the training dummy
	if enemy.is_in_group("training_dummy"):
		var tutorial_mgr = get_node_or_null("/root/TutorialManager")
		if tutorial_mgr and tutorial_mgr.is_tutorial_active():
			tutorial_mgr.on_dummy_hit(is_crit)
			# NOTE: Don't call on_weakpoint_hit() here - it's called in _on_weakpoint_destroyed_local()
			# when the weakpoint is actually destroyed (not just hit). This prevents double-counting.

	# Trigger visual feedback (hit flash, combat text, sounds)
	if enemy.has_node("HitFlash"):
		enemy.get_node("HitFlash").flash(is_crit)

	# Trigger stagger animation (position shake)
	if enemy.has_method("play_hurt_stagger"):
		enemy.play_hurt_stagger()

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
	# NORMAL/CRIT: Centered above enemy (x=0)
	# WEAKPOINT: Flanking on left/right sides
	var spawn_x_offset = 0.0  # Normal/crit damage centered

	if is_weakpoint:
		if not enemy.has_meta("weakpoint_side"):
			enemy.set_meta("weakpoint_side", 1)
		var side = enemy.get_meta("weakpoint_side")
		spawn_x_offset = 40.0 if side > 0 else -40.0  # Flank on sides
		spawn_y_offset -= 15.0  # Slightly higher than main column
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
		sound_manager.play_critical_hit_sound(enemy.global_position, -8.0)
	else:
		sound_manager.play_normal_hit_sound(enemy.global_position, -12.0, weapon_type)

	sound_manager.play_skeleton_hurt_sound(enemy.global_position, -14.0)

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

	# Serialize loot items to JSON string for reliable RPC transmission
	# Godot's RPC has issues with Array[Dictionary] serialization
	var loot_json = JSON.stringify(loot_data.items)
	LogManager.debug("Sending death for enemy #%d with %d items, json length: %d" % [
		enemy_network_id, loot_data.items.size(), loot_json.length()
	], "loot")

	# Broadcast death to all clients (loot as JSON string)
	rpc("_client_enemy_died", enemy_network_id, killer_id, loot_json, loot_data.gold)

var _loot_id_counter: int = 0  # Unique ID generator for loot items

func _generate_loot(enemy: Node) -> Dictionary:
	"""Generate loot for enemy corpse. Server only."""
	var items = []
	var gold = enemy.gold_drop

	# Roll for item drops using CorpseState
	var num_items = CorpseState.roll_loot_count()
	var is_guardian = enemy.name.contains("Guardian") or enemy.get_meta("is_guardian", false)
	var enemy_level = enemy.get("enemy_level") if enemy.get("enemy_level") else 1

	for i in range(num_items):
		var item = CorpseState.roll_loot_item(is_guardian, enemy_level)
		if item:
			# Add unique loot_id for reliable syncing across clients
			_loot_id_counter += 1
			item["loot_id"] = _loot_id_counter
			items.append(item)

	return {"items": items, "gold": gold}

@rpc("authority", "call_local", "reliable")
func _client_enemy_died(enemy_network_id: int, killer_id: int, loot_json: String, loot_gold: int) -> void:
	"""Server broadcasts enemy death to all clients."""
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	var is_server = multiplayer.is_server()

	# Deserialize and validate loot items from JSON string
	var loot_items: Array = []
	if loot_json.length() > 0:
		var parsed = JSON.parse_string(loot_json)
		if parsed is Array:
			# SECURITY: Validate all loot items before using
			loot_items = _validate_loot_array(parsed)
		else:
			LogManager.warn("Failed to parse loot JSON: %s" % loot_json, "loot")

	LogManager.debug("[%s] Enemy #%d died - received %d loot items, %d gold (json len: %d)" % [
		"Server" if is_server else "Client",
		enemy_network_id,
		loot_items.size(),
		loot_gold,
		loot_json.length()
	], "loot")

	# Set loot (generated by server) - must happen BEFORE die() to override local generation
	enemy.corpse_loot = loot_items
	enemy.corpse_gold = loot_gold

	# Debug: verify loot was set correctly
	LogManager.debug("[%s] Verified enemy.corpse_loot has %d items after assignment" % [
		"Server" if is_server else "Client",
		enemy.corpse_loot.size()
	], "loot")

	# Store killer ID for XP attribution
	enemy.set_meta("killer_peer_id", killer_id)

	# Connect corpse_clicked signal NOW (GameWorld should be loaded by the time enemies die)
	# This is more reliable than connecting during spawn when GameWorld may not exist yet
	if not multiplayer.is_server():
		_ensure_corpse_signal_connected(enemy)
		if OS.is_debug_build():
			print("💀 [_client_enemy_died] Connected corpse signal for enemy: %s (class: %s)" % [
				enemy.name, enemy.get_class()
			])

	# Call die() which handles:
	# - Weakpoint cleanup
	# - XP grant (only to the player who killed)
	# - Death animation
	# - Corpse transition
	if not enemy.is_dying:
		if OS.is_debug_build():
			print("💀 [_client_enemy_died] Calling die() on enemy: %s (class: %s)" % [
				enemy.name, enemy.get_class()
			])
		enemy.die()
	else:
		if OS.is_debug_build():
			print("💀 [_client_enemy_died] Enemy already dying, skipping die(): %s" % enemy.name)

	# Track kill for quest objectives (local player only)
	var local_peer_id = multiplayer.get_unique_id()
	if killer_id == local_peer_id:
		_track_quest_kill(enemy)

func _track_quest_kill(enemy: Node) -> void:
	"""Notify QuestManager of enemy kill for quest tracking"""
	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")

	# Get enemy type (e.g., "skeleton")
	var enemy_type = "skeleton"  # Default
	if enemy.has_method("get_enemy_type"):
		enemy_type = enemy.get_enemy_type()
	elif "enemy_type" in enemy:
		enemy_type = enemy.enemy_type

	# Get enemy level
	var enemy_level = 1
	if "level" in enemy:
		enemy_level = enemy.level

	# Check if it's a guardian
	var is_guardian = enemy.name.contains("Guardian") or (enemy.has_meta("is_guardian") and enemy.get_meta("is_guardian"))

	qm.on_enemy_killed(enemy_type, enemy_level, is_guardian)

func _on_enemy_died(enemy_network_id: int) -> void:
	"""Called when enemy dies (connected in register_enemy)."""
	# Death is now handled through _handle_enemy_death
	pass

# ═══════════════════════════════════════════════════════════════════════════
# POSITION SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

func _sync_enemy_positions() -> void:
	"""Send position updates using Interest Management - only nearby enemies per player."""
	if enemies.is_empty():
		return

	# Increment reduced sync counter (for 5Hz throttling of mid-range enemies)
	reduced_sync_counter = (reduced_sync_counter + 1) % 4  # Every 4th tick = 5Hz
	var include_reduced_range = (reduced_sync_counter == 0)

	# Get all players on server
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	if all_players.is_empty():
		return

	# Build a mapping of peer_id -> player_position
	var player_positions: Dictionary = {}  # peer_id -> Vector2
	for player in all_players:
		if not is_instance_valid(player):
			continue
		var peer_id = player.get_multiplayer_authority()
		player_positions[peer_id] = player.global_position

	# Pre-compute all enemy data once (avoid redundant work)
	var all_enemy_data: Dictionary = {}  # enemy_id -> {data, pos}
	for id in enemies:
		var enemy = enemies[id]
		if is_instance_valid(enemy) and not enemy.is_corpse:
			all_enemy_data[id] = {
				"data": {
					"pos": enemy.global_position,
					"anim": _get_enemy_animation(enemy),
					"health": enemy.current_health,
					"max_health": enemy.max_health,
					"is_dying": enemy.is_dying
				},
				"world_pos": enemy.global_position
			}

	# Send filtered updates to each player based on distance
	for peer_id in player_positions:
		# Skip server (peer_id 1) - server doesn't need to RPC to itself
		if peer_id == 1:
			continue

		# Skip if peer disconnected during iteration
		if not _is_peer_connected(peer_id):
			continue

		var player_pos = player_positions[peer_id]
		var positions_for_player: Dictionary = {}

		for enemy_id in all_enemy_data:
			var enemy_info = all_enemy_data[enemy_id]
			var distance = player_pos.distance_to(enemy_info.world_pos)

			# Full sync for nearby enemies (every tick = 20Hz)
			if distance <= SYNC_RADIUS_FULL:
				positions_for_player[enemy_id] = enemy_info.data
			# Reduced sync for mid-range enemies (every 4th tick = 5Hz)
			elif distance <= SYNC_RADIUS_REDUCED and include_reduced_range:
				positions_for_player[enemy_id] = enemy_info.data
			# Beyond SYNC_RADIUS_MAX: don't sync at all (client doesn't need it)

		# Send to this specific player if they have any nearby enemies
		if not positions_for_player.is_empty():
			_client_sync_positions.rpc_id(peer_id, positions_for_player)

	# Debug: Log sync stats occasionally (every ~5 seconds)
	if reduced_sync_counter == 0 and randf() < 0.05:  # ~5% chance each reduced tick
		var total_enemies = all_enemy_data.size()
		var avg_synced = 0
		for peer_id in player_positions:
			var player_pos = player_positions[peer_id]
			var count = 0
			for enemy_id in all_enemy_data:
				if player_pos.distance_to(all_enemy_data[enemy_id].world_pos) <= SYNC_RADIUS_REDUCED:
					count += 1
			avg_synced += count
		if player_positions.size() > 0:
			avg_synced = avg_synced / player_positions.size()
		LogManager.debug("[Interest Mgmt] %d players, %d total enemies, avg %.0f synced/player (%.0f%% reduction)" % [
			player_positions.size(), total_enemies, avg_synced,
			100.0 * (1.0 - float(avg_synced) / max(total_enemies, 1))
		], "network")

@rpc("authority", "unreliable_ordered")
func _client_sync_positions(positions: Dictionary) -> void:
	"""Receive position updates from server."""
	if multiplayer.is_server():
		return  # Server doesn't need to receive its own updates

	for id in positions:
		var enemy = get_enemy(id)
		if enemy and is_instance_valid(enemy):
			var data = positions[id]

			# Store target position for smooth interpolation in _process
			var old_target = enemy_target_positions.get(id, enemy.global_position)
			enemy_target_positions[id] = data.pos

			# Calculate interpolation speed based on distance and sync rate
			# This ensures we reach the target before next update arrives
			var distance = old_target.distance_to(data.pos)
			# Move at speed that covers distance in ~80% of sync interval (allows for jitter)
			var target_time = POSITION_SYNC_RATE * 0.8
			enemy_interpolation_speeds[id] = distance / target_time if target_time > 0 else 200.0

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
	"""Get current animation name for enemy.
	Uses enemy.current_animation variable which works on dedicated servers without sprites."""
	# Use the tracked animation state (works on headless server without sprites)
	if "current_animation" in enemy:
		return enemy.current_animation

	# Fallback: try to read from sprite (for backwards compatibility)
	var sprite = enemy.get_node_or_null("Sprite")
	if sprite and sprite is AnimatedSprite2D:
		return sprite.animation
	return "idle_down"

# ═══════════════════════════════════════════════════════════════════════════
# ENEMY VISIBILITY STREAMING (Interest Management for Spawning)
# ═══════════════════════════════════════════════════════════════════════════
# Clients only load enemies within SPAWN_RADIUS - reduces memory and CPU load
# Enemies are dynamically spawned/despawned as players move around the world

func _update_client_enemy_visibility() -> void:
	"""Server periodically checks which enemies should be visible to each client.
	Spawns enemies entering view radius, despawns those leaving (with hysteresis)."""
	if not multiplayer.is_server():
		return

	# Get all player positions
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	if all_players.is_empty():
		return

	var player_positions: Dictionary = {}  # peer_id -> Vector2
	for player in all_players:
		if not is_instance_valid(player):
			continue
		var peer_id = player.get_multiplayer_authority()
		if peer_id != 1:  # Only track clients, not server
			player_positions[peer_id] = player.global_position

	if player_positions.is_empty():
		return  # No clients to update

	# For each client, check which enemies should be visible
	for peer_id in player_positions:
		# Skip if peer disconnected during iteration
		if not _is_peer_connected(peer_id):
			continue

		var player_pos = player_positions[peer_id]

		# Initialize tracking dict for this peer if needed
		if not client_known_enemies.has(peer_id):
			client_known_enemies[peer_id] = {}

		var known = client_known_enemies[peer_id]
		var enemies_to_spawn: Array = []
		var enemies_to_despawn: Array = []

		# Check all enemies
		for network_id in enemies:
			var enemy = enemies[network_id]
			if not is_instance_valid(enemy):
				continue
			if enemy.is_corpse or enemy.is_dying:
				continue  # Don't spawn dead/dying enemies

			var distance = player_pos.distance_to(enemy.global_position)
			var is_known = known.has(network_id)

			if distance <= SPAWN_RADIUS:
				# Enemy is in range - spawn if not known
				if not is_known:
					enemies_to_spawn.append(network_id)
			elif distance > SPAWN_RADIUS + SPAWN_HYSTERESIS:
				# Enemy is out of range (with hysteresis) - despawn if known
				if is_known:
					enemies_to_despawn.append(network_id)
			# Else: enemy is in hysteresis zone, don't change state

		# Spawn new enemies for this client
		# Check peer still connected before sending batch of RPCs
		if not _is_peer_connected(peer_id):
			continue

		for network_id in enemies_to_spawn:
			var enemy = enemies[network_id]
			if not is_instance_valid(enemy):
				continue

			# Mark as known BEFORE sending RPC (prevents duplicate spawns)
			known[network_id] = true

			# Send spawn RPC to this specific client
			var scene_path = _infer_enemy_scene_path(enemy.name)
			if enemy is TrainingDummy:
				spawn_training_dummy_on_clients.rpc_id(peer_id, network_id, enemy.global_position)
			else:
				spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name, scene_path)

		# Despawn enemies that left view for this client
		# Check peer again before despawn batch
		if not _is_peer_connected(peer_id):
			continue

		for network_id in enemies_to_despawn:
			known.erase(network_id)
			despawn_enemy_for_client.rpc_id(peer_id, network_id)

		# Debug log occasionally
		if not enemies_to_spawn.is_empty() or not enemies_to_despawn.is_empty():
			if OS.is_debug_build():
				print("🌐 [Visibility] Peer %d: +%d spawned, -%d despawned (total known: %d)" % [
					peer_id, enemies_to_spawn.size(), enemies_to_despawn.size(), known.size()
				])

func spawn_enemy_for_nearby_clients(network_id: int, enemy: Node) -> void:
	"""Called when server spawns a new enemy - notify only nearby clients.
	This replaces the old broadcast-to-all approach."""
	if not multiplayer.is_server():
		return

	if not is_instance_valid(enemy):
		return

	var enemy_pos = enemy.global_position

	# Get all client player positions
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in all_players:
		if not is_instance_valid(player):
			continue

		var peer_id = player.get_multiplayer_authority()
		if peer_id == 1:
			continue  # Skip server

		# Skip if peer disconnected
		if not _is_peer_connected(peer_id):
			continue

		var distance = player.global_position.distance_to(enemy_pos)
		if distance <= SPAWN_RADIUS:
			# Client is close enough - spawn the enemy for them
			if not client_known_enemies.has(peer_id):
				client_known_enemies[peer_id] = {}

			# Only spawn if not already known
			if not client_known_enemies[peer_id].has(network_id):
				client_known_enemies[peer_id][network_id] = true

				var scene_path = _infer_enemy_scene_path(enemy.name)
				if enemy is TrainingDummy:
					spawn_training_dummy_on_clients.rpc_id(peer_id, network_id, enemy.global_position)
				else:
					spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name, scene_path)

				if OS.is_debug_build():
					print("🌐 [Spawn] Enemy %d spawned for nearby peer %d (dist: %.0f)" % [network_id, peer_id, distance])

@rpc("authority", "reliable")
func despawn_enemy_for_client(network_id: int) -> void:
	"""Server tells a specific client to remove an enemy (interest management)."""
	if multiplayer.is_server():
		return  # Server doesn't despawn its own enemies this way

	var enemy = get_enemy(network_id)
	if enemy and is_instance_valid(enemy):
		if OS.is_debug_build():
			print("🌐 [Client] Despawning enemy %d (out of range)" % network_id)
		enemy.queue_free()

	# Clean up local tracking
	unregister_enemy(network_id)
	enemy_target_positions.erase(network_id)
	enemy_interpolation_speeds.erase(network_id)

# ═══════════════════════════════════════════════════════════════════════════
# SPAWN SYNC (Server -> Clients)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func spawn_enemy_on_clients(network_id: int, pos: Vector2, level: int, enemy_name: String, scene_path: String = "") -> void:
	"""Server tells clients to spawn an enemy.
	scene_path: Optional explicit scene path. If empty, inferred from enemy_name."""
	if multiplayer.is_server():
		return  # Server already spawned

	# DUPLICATE CHECK: Skip if this enemy already exists
	var existing = get_enemy(network_id)
	if existing and is_instance_valid(existing):
		# Already have this enemy, just update position if needed
		existing.global_position = pos
		return

	# Determine scene path from enemy name if not provided
	var actual_scene_path = scene_path
	if actual_scene_path.is_empty():
		actual_scene_path = _infer_enemy_scene_path(enemy_name)

	if OS.is_debug_build():
		print("🌐 [Client] Spawning enemy '%s' (net#%d) using scene: %s" % [enemy_name, network_id, actual_scene_path])

	var enemy_scene = load(actual_scene_path)
	if not enemy_scene:
		LogManager.error("Failed to load enemy scene: %s" % actual_scene_path, "network")
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

func _infer_enemy_scene_path(enemy_name: String) -> String:
	"""Infer scene path from enemy name (e.g., 'Wolf_123' -> wolf.tscn)."""
	var name_lower = enemy_name.to_lower()

	# Wolf variants
	if name_lower.begins_with("wolf") or name_lower.begins_with("direwolf") or name_lower.begins_with("alpha"):
		return "res://scenes/enemies/wolf.tscn"

	# Spider variants
	if name_lower.begins_with("spider") or name_lower.contains("spider"):
		return "res://scenes/enemies/spider.tscn"

	# Skeleton variants (default enemy)
	if name_lower.begins_with("skeleton") or name_lower.begins_with("guardian"):
		return "res://scenes/enemies/enemy.tscn"

	# Default to generic enemy
	return "res://scenes/enemies/enemy.tscn"

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

	# DUPLICATE CHECK: Skip if this enemy already exists
	var existing = get_enemy(network_id)
	if existing and is_instance_valid(existing):
		existing.global_position = pos
		return

	var dummy_scene = load("res://scenes/training/training_dummy.tscn")
	if not dummy_scene:
		LogManager.error("Could not load training_dummy.tscn", "network")
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
	"""When a new peer connects, send them only NEARBY enemies (interest management)."""
	if not multiplayer.is_server():
		return

	# Initialize tracking for this peer IMMEDIATELY (before await)
	# This prevents _update_client_enemy_visibility from sending duplicates during the delay
	if not client_known_enemies.has(peer_id):
		client_known_enemies[peer_id] = {}

	# Small delay to let client fully initialize and spawn their player
	await get_tree().create_timer(0.5).timeout

	# Check if we're still valid after await
	if not is_instance_valid(self):
		return

	# Check if peer disconnected during the await
	if not client_known_enemies.has(peer_id):
		return

	# Find the new player's position
	var player_pos: Vector2 = Vector2.ZERO
	var found_player = false
	var all_players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in all_players:
		if is_instance_valid(player) and player.get_multiplayer_authority() == peer_id:
			player_pos = player.global_position
			found_player = true
			break

	if not found_player:
		# Player not found yet - the visibility update will catch them later
		push_warning("NetworkEnemyManager: Player for peer %d not found during connect, enemies will stream in via visibility updates" % peer_id)
		return

	var spawned_count = 0
	var total_count = 0

	for network_id in enemies:
		var enemy = enemies[network_id]
		if not is_instance_valid(enemy):
			continue
		if enemy.is_corpse or enemy.is_dying:
			continue  # Don't sync dead/dying enemies

		total_count += 1

		# INTEREST MANAGEMENT: Only spawn enemies within SPAWN_RADIUS
		var distance = player_pos.distance_to(enemy.global_position)
		if distance > SPAWN_RADIUS:
			continue  # Skip - too far from player

		# Check peer still connected before sending RPC
		if not _is_peer_connected(peer_id):
			break

		# Mark as known
		client_known_enemies[peer_id][network_id] = true
		spawned_count += 1

		# Check if this is a TrainingDummy (different spawn RPC)
		if enemy is TrainingDummy:
			spawn_training_dummy_on_clients.rpc_id(peer_id, network_id, enemy.global_position)
		else:
			# Regular enemy - infer scene path from name for proper type sync
			var scene_path = _infer_enemy_scene_path(enemy.name)
			spawn_enemy_on_clients.rpc_id(peer_id, network_id, enemy.global_position, enemy.enemy_level, enemy.name, scene_path)

	print("🌐 [Connect] Peer %d: Spawned %d/%d enemies within %.0f units" % [
		peer_id, spawned_count, total_count, SPAWN_RADIUS
	])

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
		sound_manager.play_sound(sound_manager.SoundType.CRIT_WINDOW_OPEN, enemy.global_position, -10.0)

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
# PLAYER DEATH TRACKING (Server-side)
# Enemies check this to stop attacking dead players
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func notify_player_death() -> void:
	"""Client notifies server that they died. Server tracks this so enemies disengage."""
	if not multiplayer.is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1  # Server's peer ID

	dead_players[peer_id] = true
	LogManager.info("Player %d marked as dead (enemies will disengage)" % peer_id, "network")

@rpc("any_peer", "reliable")
func notify_player_respawn() -> void:
	"""Client notifies server that they respawned. Enemies can target them again."""
	if not multiplayer.is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1  # Server's peer ID

	dead_players.erase(peer_id)
	LogManager.info("Player %d respawned (enemies can target again)" % peer_id, "network")

func is_player_dead(peer_id: int) -> bool:
	"""Check if a player is dead (server-side tracking). Used by EnemyAI."""
	return dead_players.get(peer_id, false)

func get_player_peer_id(player_node: Node) -> int:
	"""Get the peer ID for a player node."""
	if not player_node:
		return -1

	# Check multiplayer authority
	if player_node.has_method("get_multiplayer_authority"):
		return player_node.get_multiplayer_authority()

	# Check meta
	if player_node.has_meta("peer_id"):
		return player_node.get_meta("peer_id")

	# Fallback: search connected players
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and "connected_players" in network_manager:
		for peer_id in network_manager.connected_players:
			var info = network_manager.connected_players[peer_id]
			if info.get("node") == player_node:
				return peer_id

	return -1

# ═══════════════════════════════════════════════════════════════════════════
# CRIT WINDOW RESULT REPORTING (Client-Predicted System)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func report_crit_window_result(enemy_network_id: int, weakpoints_destroyed: int, total_damage: int) -> void:
	"""Client reports crit window results. Server validates and applies damage."""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

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
		_record_violation(attacker_id, "reported %d weakpoints (max: %d)" % [weakpoints_destroyed, expected_weakpoints])
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

func _get_max_player_damage(attacker_peer_id: int) -> float:
	"""Get the maximum expected base damage for a player (for anti-cheat validation)."""
	var base_damage: float = 15.0  # Default base damage

	# Try to find the attacking player's actual damage stat
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()

		if player_peer_id == attacker_peer_id:
			if player.get("attack_damage") != null:
				base_damage = player.attack_damage
			break

	# Add generous buffer for weapon variance, buffs, etc.
	# Max realistic damage at high level with best gear is ~150-200
	return maxf(base_damage * 2.0, 300.0)  # At least 300 to avoid false positives

# ═══════════════════════════════════════════════════════════════════════════
# LOOT SYNC (Server Authoritative)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_loot_gold(enemy_network_id: int) -> void:
	"""Client requests to loot gold from a corpse. Server validates and broadcasts."""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		return

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		return

	if not enemy.is_corpse:
		return

	var looter_id = multiplayer.get_remote_sender_id()
	if looter_id == 0:
		looter_id = 1  # Server is looting

	var gold = enemy.corpse_gold
	if gold <= 0:
		return

	# Clear gold on server
	enemy.corpse_gold = 0

	# Broadcast to all clients (including server via call_local)
	_client_gold_looted.rpc(enemy_network_id, looter_id, gold)

@rpc("authority", "call_local", "reliable")
func _client_gold_looted(enemy_network_id: int, looter_id: int, gold_amount: int) -> void:
	"""Server broadcasts that gold was looted from a corpse.
	Note: The looter already received gold via optimistic update in LootBodyUI.
	This RPC handles corpse sync for all clients."""
	LogManager.debug("_client_gold_looted: enemy=%d, looter=%d, gold=%d" % [enemy_network_id, looter_id, gold_amount], "loot")

	# Note: Looter already added gold optimistically in LootBodyUI
	# This RPC is mainly for syncing corpse state across all clients

	# Handle corpse cleanup (only if enemy still exists)
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		LogManager.debug("_client_gold_looted: Enemy already gone, skipping corpse cleanup", "loot")
		return

	# Clear gold on this client
	enemy.corpse_gold = 0

	# Check if corpse is now fully empty
	enemy.check_if_looted_empty()

func _queue_gold_loot_notification(amount: int, position: Vector2) -> void:
	"""Queue a gold loot notification for staggered display."""
	_gold_loot_queue.append({"amount": amount, "position": position})

func _process_gold_loot_queue(delta: float) -> void:
	"""Process queued gold loot notifications with stagger delay."""
	if _gold_loot_queue.is_empty():
		return

	_gold_loot_timer += delta
	if _gold_loot_timer >= GOLD_LOOT_STAGGER_DELAY:
		_gold_loot_timer = 0.0

		# Pop and show the next notification
		var entry = _gold_loot_queue.pop_front()
		_show_gold_loot_notification(entry.amount, entry.position)

func _show_gold_loot_notification(amount: int, position: Vector2) -> void:
	"""Actually display the gold loot notification and play sound."""
	# Show world-space gold text floating up from corpse
	var gw = get_tree().get_first_node_in_group("game_world")
	if gw and position != Vector2.ZERO:
		CombatText.create_gold(amount, position, gw)

	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -12.0)

@rpc("any_peer", "call_local", "reliable")
func request_loot_item(enemy_network_id: int, item_index: int) -> void:
	"""Client requests to loot an item from a corpse. Server validates and broadcasts."""
	# Guard against null multiplayer during scene transitions
	if not multiplayer:
		return

	if not multiplayer.is_server():
		LogManager.debug("request_loot_item: Not server, ignoring", "loot")
		return

	LogManager.debug("request_loot_item for enemy=%d, index=%d" % [enemy_network_id, item_index], "loot")

	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		LogManager.debug("Enemy not found for loot request", "loot")
		return

	if not enemy.is_corpse:
		LogManager.debug("Enemy is not a corpse for loot request", "loot")
		return

	var looter_id = multiplayer.get_remote_sender_id()
	if looter_id == 0:
		looter_id = 1  # Server is looting

	LogManager.debug("Looter ID = %d, corpse has %d items" % [looter_id, enemy.corpse_loot.size()], "loot")

	# Validate item index
	if item_index < 0 or item_index >= enemy.corpse_loot.size():
		LogManager.debug("Invalid item index %d (corpse has %d items)" % [item_index, enemy.corpse_loot.size()], "loot")
		return

	var item = enemy.corpse_loot[item_index]
	if not item:
		LogManager.debug("Item at index %d is null" % item_index, "loot")
		return

	var item_name = item.get("name", "Unknown")
	LogManager.debug("Looting '%s' from corpse" % item_name, "loot")

	# Remove item from server's corpse loot
	enemy.corpse_loot.remove_at(item_index)
	LogManager.debug("Removed item, corpse now has %d items" % enemy.corpse_loot.size(), "loot")

	# Serialize item to JSON for reliable RPC transmission
	var item_json = JSON.stringify(item)

	# Broadcast to all clients (including server via call_local)
	LogManager.debug("Broadcasting _client_item_looted to all peers", "loot")
	_client_item_looted.rpc(enemy_network_id, looter_id, item_index, item_json)

@rpc("authority", "call_local", "reliable")
func _client_item_looted(enemy_network_id: int, looter_id: int, item_index: int, item_json: String) -> void:
	"""Server broadcasts that an item was looted from a corpse.
	Note: The looter already received item via optimistic update in LootBodyUI.
	This RPC handles corpse sync for all clients."""
	LogManager.debug("_client_item_looted: enemy=%d, looter=%d, index=%d" % [enemy_network_id, looter_id, item_index], "loot")

	# Deserialize item from JSON for corpse sync (need name for matching)
	var item: Dictionary = {}
	if item_json.length() > 0:
		var parsed = JSON.parse_string(item_json)
		if parsed is Dictionary:
			item = _validate_loot_item(parsed)
			if item.is_empty():
				LogManager.warn("Invalid item data rejected in _client_item_looted", "security")
				return
		else:
			LogManager.warn("Failed to parse item JSON: %s" % item_json, "loot")
			return
	else:
		LogManager.warn("Empty item_json in _client_item_looted", "loot")
		return

	var item_name = item.get("name", "")

	# Note: Looter already added item and showed notification optimistically in LootBodyUI
	# This RPC is mainly for syncing corpse state across all clients

	# Handle corpse cleanup (only if enemy still exists)
	var enemy = get_enemy(enemy_network_id)
	if not enemy or not is_instance_valid(enemy):
		LogManager.debug("_client_item_looted: Enemy already gone, skipping corpse cleanup", "loot")
		return

	# Remove item from local corpse loot
	# For server: already removed in request_loot_item, skip removal
	# For clients: need to remove from local corpse using the index provided by server
	if not multiplayer.is_server():
		var removed = false
		var loot_id = item.get("loot_id", -1)
		LogManager.debug("Client removing item '%s' (loot_id=%d) at index %d from corpse (has %d items)" % [item_name, loot_id, item_index, enemy.corpse_loot.size()], "loot")

		# First try exact index match (most reliable when arrays are in sync)
		if item_index >= 0 and item_index < enemy.corpse_loot.size():
			var corpse_item = enemy.corpse_loot[item_index]
			# Match by loot_id if available, otherwise by name
			if corpse_item:
				var corpse_loot_id = corpse_item.get("loot_id", -1)
				if (loot_id > 0 and corpse_loot_id == loot_id) or (loot_id <= 0 and corpse_item.get("name", "") == item_name):
					enemy.corpse_loot.remove_at(item_index)
					removed = true
					LogManager.debug("Removed '%s' at exact index %d (loot_id=%d)" % [item_name, item_index, loot_id], "loot")

		# Fallback: search by loot_id or name if exact index didn't match (array out of sync)
		if not removed:
			LogManager.debug("Exact index mismatch, searching by loot_id/name...", "loot")
			for i in range(enemy.corpse_loot.size()):
				var corpse_item = enemy.corpse_loot[i]
				if corpse_item:
					var corpse_loot_id = corpse_item.get("loot_id", -1)
					# Prefer loot_id match, fall back to name match
					if (loot_id > 0 and corpse_loot_id == loot_id) or (loot_id <= 0 and corpse_item.get("name", "") == item_name):
						enemy.corpse_loot.remove_at(i)
						removed = true
						LogManager.debug("Fallback: Removed '%s' at index %d (expected %d, loot_id=%d)" % [item_name, i, item_index, loot_id], "loot")
						break

		if not removed:
			LogManager.warn("Could not find '%s' (loot_id=%d) in corpse loot to remove (expected index %d)" % [item_name, loot_id, item_index], "loot")
		LogManager.debug("Client corpse now has %d items" % enemy.corpse_loot.size(), "loot")

	# Check if corpse is now fully empty
	enemy.check_if_looted_empty()
