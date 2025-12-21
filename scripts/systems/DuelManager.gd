extends Node

## DuelManager - Handles consensual 1v1 PvP duel system
##
## Duel Flow:
## 1. Player A requests duel with Player B (must be within MAX_DUEL_DISTANCE)
## 2. Player B sees accept/decline popup (30 second timeout)
## 3. If accepted, 3-2-1 countdown begins
## 4. During duel: players isolated from outside damage/healing
## 5. First player to reach 1 HP loses
## 6. Both players get 10-second safe aura post-duel
##
## Commands:
## /duel <player> - Request a duel with target player
## /accept - Accept pending duel request
## /decline - Decline pending duel request

# Signals
signal duel_requested(challenger_id: int, target_id: int)
signal duel_accepted(player1_id: int, player2_id: int)
signal duel_declined(challenger_id: int, target_id: int)
signal duel_started(player1_id: int, player2_id: int)
signal duel_ended(winner_id: int, loser_id: int)
signal duel_cancelled(player1_id: int, player2_id: int, reason: String)
signal countdown_tick(player1_id: int, player2_id: int, seconds_remaining: int)
signal safe_aura_started(player_id: int)
signal safe_aura_ended(player_id: int)
signal request_received(challenger_id: int, challenger_name: String)
signal request_expired(challenger_name: String)

# Constants
const DUEL_REQUEST_TIMEOUT: float = 30.0
const COUNTDOWN_DURATION: int = 3
const SAFE_AURA_DURATION: float = 10.0
const MAX_DUEL_DISTANCE: float = 100.0  # Max distance to initiate duel
const DUEL_CANCEL_DISTANCE: float = 500.0  # Cancel if players get this far apart

# Active duels: {player_id: opponent_id} - stored both ways for quick lookup
var active_duels: Dictionary = {}

# Pending requests: {target_id: {challenger_id: int, challenger_name: String, timestamp: float}}
var pending_requests: Dictionary = {}

# Sent requests (local tracking): {target_id: timestamp}
var sent_requests: Dictionary = {}

# Safe aura tracking: {player_id: time_remaining}
var safe_aura_timers: Dictionary = {}

# Countdown state
var countdown_active: bool = false
var countdown_player1: int = -1
var countdown_player2: int = -1
var countdown_remaining: int = 0
var countdown_timer: float = 0.0

func _ready() -> void:
	print("DuelManager initialized")

func _process(delta: float) -> void:
	_process_request_timeouts()
	_process_safe_aura_timers(delta)
	_process_countdown(delta)
	_check_duel_distance()

# ═══════════════════════════════════════════════════════════════════════════
# LOCAL QUERIES
# ═══════════════════════════════════════════════════════════════════════════

func is_dueling(player_id: int = -1) -> bool:
	"""Check if a player is currently in a duel. If no ID provided, checks local player."""
	if player_id == -1:
		if not multiplayer.has_multiplayer_peer():
			return false
		player_id = multiplayer.get_unique_id()
	return active_duels.has(player_id)

func get_duel_opponent(player_id: int = -1) -> int:
	"""Get the opponent's peer ID for a dueling player. Returns -1 if not dueling."""
	if player_id == -1:
		if not multiplayer.has_multiplayer_peer():
			return -1
		player_id = multiplayer.get_unique_id()
	return active_duels.get(player_id, -1)

func has_safe_aura(player_id: int = -1) -> bool:
	"""Check if a player has safe aura active."""
	if player_id == -1:
		if not multiplayer.has_multiplayer_peer():
			return false
		player_id = multiplayer.get_unique_id()
	return safe_aura_timers.has(player_id)

func has_pending_request() -> bool:
	"""Check if local player has any pending duel requests."""
	if not multiplayer.has_multiplayer_peer():
		return false
	var my_id = multiplayer.get_unique_id()
	return pending_requests.has(my_id)

func get_pending_request_info() -> Dictionary:
	"""Get info about pending request for local player. Returns empty dict if none."""
	if not multiplayer.has_multiplayer_peer():
		return {}
	var my_id = multiplayer.get_unique_id()
	if pending_requests.has(my_id):
		return pending_requests[my_id]
	return {}

func can_request_duel(target_id: int) -> Dictionary:
	"""Check if local player can request a duel with target. Returns {valid: bool, reason: String}"""
	print("[DuelManager] can_request_duel(%d)" % target_id)
	if not multiplayer.has_multiplayer_peer():
		return {valid = false, reason = "Not connected to server"}

	var my_id = multiplayer.get_unique_id()
	print("[DuelManager] my_id=%d, target_id=%d" % [my_id, target_id])

	# Can't duel yourself
	if target_id == my_id:
		return {valid = false, reason = "Cannot duel yourself"}

	# Already in a duel
	if is_dueling(my_id):
		return {valid = false, reason = "You are already in a duel"}

	if is_dueling(target_id):
		return {valid = false, reason = "Target is already in a duel"}

	# Already have a pending request to this player
	if sent_requests.has(target_id):
		return {valid = false, reason = "Request already pending"}

	# Check distance
	var my_node = _get_player_node(my_id)
	var target_node = _get_player_node(target_id)
	print("[DuelManager] my_node=%s, target_node=%s" % [my_node, target_node])

	var distance = _get_player_distance(my_id, target_id)
	print("[DuelManager] distance=%f" % distance)
	if distance < 0:
		return {valid = false, reason = "Cannot find target player"}
	if distance > MAX_DUEL_DISTANCE:
		return {valid = false, reason = "Target is too far away (max %.0f)" % MAX_DUEL_DISTANCE}

	return {valid = true, reason = ""}

# ═══════════════════════════════════════════════════════════════════════════
# DUEL STATE MANAGEMENT (called by server/authority)
# ═══════════════════════════════════════════════════════════════════════════

func _start_duel_local(player1_id: int, player2_id: int) -> void:
	"""Start duel state locally (called after countdown)"""
	active_duels[player1_id] = player2_id
	active_duels[player2_id] = player1_id

	# Remove safe aura if either player had one
	_remove_safe_aura(player1_id)
	_remove_safe_aura(player2_id)

	# Notify players to enter duel state
	_notify_player_enter_duel(player1_id, player2_id)
	_notify_player_enter_duel(player2_id, player1_id)

	duel_started.emit(player1_id, player2_id)
	print("Duel started: %d vs %d" % [player1_id, player2_id])

func _end_duel_local(winner_id: int, loser_id: int) -> void:
	"""End duel and declare winner (called by server)"""
	if not active_duels.has(winner_id) or not active_duels.has(loser_id):
		push_warning("Attempted to end non-existent duel")
		return

	# Remove duel state
	active_duels.erase(winner_id)
	active_duels.erase(loser_id)

	# Notify players to exit duel state
	_notify_player_exit_duel(winner_id)
	_notify_player_exit_duel(loser_id)

	# Apply safe aura to both players
	_apply_safe_aura(winner_id)
	_apply_safe_aura(loser_id)

	duel_ended.emit(winner_id, loser_id)
	print("Duel ended: %d wins, %d loses" % [winner_id, loser_id])

func _cancel_duel_local(player1_id: int, player2_id: int, reason: String) -> void:
	"""Cancel duel without declaring a winner"""
	active_duels.erase(player1_id)
	active_duels.erase(player2_id)

	_notify_player_exit_duel(player1_id)
	_notify_player_exit_duel(player2_id)

	# Apply safe aura on cancel too
	_apply_safe_aura(player1_id)
	_apply_safe_aura(player2_id)

	duel_cancelled.emit(player1_id, player2_id, reason)
	print("Duel cancelled: %s" % reason)

# ═══════════════════════════════════════════════════════════════════════════
# COUNTDOWN MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _start_countdown(player1_id: int, player2_id: int) -> void:
	"""Begin the 3-2-1 countdown before duel starts"""
	countdown_active = true
	countdown_player1 = player1_id
	countdown_player2 = player2_id
	countdown_remaining = COUNTDOWN_DURATION
	countdown_timer = 1.0

	countdown_tick.emit(player1_id, player2_id, countdown_remaining)
	print("Duel countdown started: %d vs %d" % [player1_id, player2_id])

func _process_countdown(delta: float) -> void:
	if not countdown_active:
		return

	countdown_timer -= delta
	if countdown_timer <= 0:
		countdown_remaining -= 1
		countdown_timer = 1.0

		if countdown_remaining > 0:
			countdown_tick.emit(countdown_player1, countdown_player2, countdown_remaining)
		else:
			# Countdown finished - start the duel
			countdown_active = false
			_start_duel_local(countdown_player1, countdown_player2)
			countdown_player1 = -1
			countdown_player2 = -1

# ═══════════════════════════════════════════════════════════════════════════
# REQUEST MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _add_pending_request(target_id: int, challenger_id: int, challenger_name: String) -> void:
	"""Add a pending duel request (called when receiving request)"""
	pending_requests[target_id] = {
		challenger_id = challenger_id,
		challenger_name = challenger_name,
		timestamp = Time.get_unix_time_from_system()
	}

	# If this is for the local player, emit signal for UI
	if multiplayer.has_multiplayer_peer() and target_id == multiplayer.get_unique_id():
		request_received.emit(challenger_id, challenger_name)

func _remove_pending_request(target_id: int) -> void:
	"""Remove a pending request"""
	pending_requests.erase(target_id)

func _process_request_timeouts() -> void:
	"""Check for expired duel requests"""
	var current_time = Time.get_unix_time_from_system()
	var expired: Array[int] = []

	for target_id in pending_requests:
		var request = pending_requests[target_id]
		if current_time - request.timestamp > DUEL_REQUEST_TIMEOUT:
			expired.append(target_id)

	for target_id in expired:
		var request = pending_requests[target_id]
		pending_requests.erase(target_id)
		sent_requests.erase(target_id)
		request_expired.emit(request.challenger_name)
		duel_declined.emit(request.challenger_id, target_id)

# ═══════════════════════════════════════════════════════════════════════════
# SAFE AURA MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _apply_safe_aura(player_id: int) -> void:
	"""Apply safe aura to a player after duel ends"""
	safe_aura_timers[player_id] = SAFE_AURA_DURATION
	_notify_player_safe_aura(player_id, true)
	safe_aura_started.emit(player_id)

func _remove_safe_aura(player_id: int) -> void:
	"""Remove safe aura from a player"""
	if safe_aura_timers.has(player_id):
		safe_aura_timers.erase(player_id)
		_notify_player_safe_aura(player_id, false)
		safe_aura_ended.emit(player_id)

func _process_safe_aura_timers(delta: float) -> void:
	"""Update safe aura timers"""
	var expired: Array[int] = []

	for player_id in safe_aura_timers:
		safe_aura_timers[player_id] -= delta
		if safe_aura_timers[player_id] <= 0:
			expired.append(player_id)

	for player_id in expired:
		_remove_safe_aura(player_id)

# ═══════════════════════════════════════════════════════════════════════════
# DISTANCE CHECKING
# ═══════════════════════════════════════════════════════════════════════════

func _check_duel_distance() -> void:
	"""Cancel duels if players get too far apart"""
	var to_cancel: Array = []
	var checked: Dictionary = {}  # Avoid checking same pair twice

	for player1_id in active_duels:
		var player2_id = active_duels[player1_id]

		# Skip if already checked this pair
		var pair_key = min(player1_id, player2_id) * 1000000 + max(player1_id, player2_id)
		if checked.has(pair_key):
			continue
		checked[pair_key] = true

		var distance = _get_player_distance(player1_id, player2_id)
		if distance < 0 or distance > DUEL_CANCEL_DISTANCE:
			to_cancel.append([player1_id, player2_id])

	for pair in to_cancel:
		_cancel_duel_local(pair[0], pair[1], "Players too far apart")

func _get_player_distance(player1_id: int, player2_id: int) -> float:
	"""Get distance between two players. Returns -1 if either not found."""
	var p1 = _get_player_node(player1_id)
	var p2 = _get_player_node(player2_id)

	if not p1 or not p2:
		return -1.0

	return p1.global_position.distance_to(p2.global_position)

func _get_player_node(player_id: int) -> Node2D:
	"""Get the player node for a given peer ID"""
	# Check if this is the local player
	if multiplayer.has_multiplayer_peer() and player_id == multiplayer.get_unique_id():
		var local_player = get_tree().get_first_node_in_group("player")
		if local_player:
			return local_player

	# Search for Player_<id> node directly in the scene
	var world = get_tree().current_scene
	if world:
		var player_node_name = "Player_%d" % player_id
		var player_node = world.get_node_or_null(player_node_name)
		if player_node:
			return player_node

	# Also search in "player" group (local player)
	for player in get_tree().get_nodes_in_group("player"):
		if player.has_method("get_multiplayer_authority"):
			if player.get_multiplayer_authority() == player_id:
				return player

	# Fallback: search in "players" group (remote players)
	for player in get_tree().get_nodes_in_group("players"):
		if player.has_method("get_multiplayer_authority"):
			if player.get_multiplayer_authority() == player_id:
				return player

	return null

func _get_player_name(player_id: int) -> String:
	"""Get player name for a peer ID"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.connected_players.has(player_id):
		return network_manager.connected_players[player_id].get("name", "Player%d" % player_id)
	return "Player%d" % player_id

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER NOTIFICATION HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _notify_player_enter_duel(player_id: int, opponent_id: int) -> void:
	"""Notify a player to enter duel state"""
	var player = _get_player_node(player_id)
	if player and player.has_method("enter_duel_state"):
		player.enter_duel_state(opponent_id)

func _notify_player_exit_duel(player_id: int) -> void:
	"""Notify a player to exit duel state"""
	var player = _get_player_node(player_id)
	if player and player.has_method("exit_duel_state"):
		player.exit_duel_state()

func _notify_player_safe_aura(player_id: int, active: bool) -> void:
	"""Notify a player about safe aura state change"""
	var player = _get_player_node(player_id)
	if player:
		if active and player.has_method("apply_safe_aura"):
			player.apply_safe_aura()
		elif not active and player.has_method("remove_safe_aura"):
			player.remove_safe_aura()

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API (for UI and commands)
# ═══════════════════════════════════════════════════════════════════════════

func request_duel(target_id: int) -> Dictionary:
	"""Request a duel with target player. Returns {success: bool, message: String}"""
	var check = can_request_duel(target_id)
	if not check.valid:
		return {success = false, message = check.reason}

	var my_id = multiplayer.get_unique_id()
	sent_requests[target_id] = Time.get_unix_time_from_system()

	# Send request to server (RPC will be added in Phase 4)
	if multiplayer.is_server():
		_handle_duel_request(my_id, target_id)
	else:
		rpc_id(1, "_server_request_duel", target_id)

	var target_name = _get_player_name(target_id)
	duel_requested.emit(my_id, target_id)
	return {success = true, message = "Duel request sent to %s" % target_name}

func accept_duel() -> Dictionary:
	"""Accept the pending duel request. Returns {success: bool, message: String}"""
	if not has_pending_request():
		return {success = false, message = "No pending duel request"}

	var request = get_pending_request_info()
	var challenger_id = request.challenger_id
	var my_id = multiplayer.get_unique_id()

	# Check if we can still duel
	if is_dueling():
		return {success = false, message = "You are already in a duel"}

	if is_dueling(challenger_id):
		_remove_pending_request(my_id)
		return {success = false, message = "Challenger is already in a duel"}

	# Accept the duel
	if multiplayer.is_server():
		_handle_duel_accept(my_id, challenger_id)
	else:
		rpc_id(1, "_server_accept_duel", challenger_id)

	return {success = true, message = "Duel accepted!"}

func decline_duel() -> Dictionary:
	"""Decline the pending duel request. Returns {success: bool, message: String}"""
	if not has_pending_request():
		return {success = false, message = "No pending duel request"}

	var request = get_pending_request_info()
	var challenger_id = request.challenger_id
	var my_id = multiplayer.get_unique_id()

	# Decline the duel
	if multiplayer.is_server():
		_handle_duel_decline(my_id, challenger_id)
	else:
		rpc_id(1, "_server_decline_duel", challenger_id)

	return {success = true, message = "Duel declined"}

func report_duel_loss() -> void:
	"""Called when local player reaches 1 HP during duel"""
	if not is_dueling():
		return

	var my_id = multiplayer.get_unique_id()
	var opponent_id = get_duel_opponent()

	if multiplayer.is_server():
		_end_duel_local(opponent_id, my_id)
		rpc("_client_duel_ended", opponent_id, my_id)
	else:
		rpc_id(1, "_server_report_loss", opponent_id)

# ═══════════════════════════════════════════════════════════════════════════
# SERVER-SIDE HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _handle_duel_request(challenger_id: int, target_id: int) -> void:
	"""Server handles duel request"""
	# Validate both players can duel
	if is_dueling(challenger_id) or is_dueling(target_id):
		return

	var distance = _get_player_distance(challenger_id, target_id)
	if distance < 0 or distance > MAX_DUEL_DISTANCE:
		return

	var challenger_name = _get_player_name(challenger_id)
	_add_pending_request(target_id, challenger_id, challenger_name)

	# Notify target
	rpc_id(target_id, "_client_request_received", challenger_id, challenger_name)

func _handle_duel_accept(accepter_id: int, challenger_id: int) -> void:
	"""Server handles duel acceptance"""
	# Validate pending request exists
	if not pending_requests.has(accepter_id):
		return

	var request = pending_requests[accepter_id]
	if request.challenger_id != challenger_id:
		return

	# Remove pending request
	_remove_pending_request(accepter_id)

	# Start countdown for both players
	_start_countdown(challenger_id, accepter_id)
	rpc("_client_countdown_started", challenger_id, accepter_id, COUNTDOWN_DURATION)

	duel_accepted.emit(challenger_id, accepter_id)

func _handle_duel_decline(decliner_id: int, challenger_id: int) -> void:
	"""Server handles duel decline"""
	if not pending_requests.has(decliner_id):
		return

	_remove_pending_request(decliner_id)

	# Notify challenger
	rpc_id(challenger_id, "_client_request_declined", decliner_id)

	duel_declined.emit(challenger_id, decliner_id)

# ═══════════════════════════════════════════════════════════════════════════
# NETWORK RPCs (Phase 4 - stubs for now)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _server_request_duel(target_id: int) -> void:
	"""Client requests a duel with target"""
	if not multiplayer.is_server():
		return
	var challenger_id = multiplayer.get_remote_sender_id()
	_handle_duel_request(challenger_id, target_id)

@rpc("any_peer", "reliable")
func _server_accept_duel(challenger_id: int) -> void:
	"""Client accepts a duel request"""
	if not multiplayer.is_server():
		return
	var accepter_id = multiplayer.get_remote_sender_id()
	_handle_duel_accept(accepter_id, challenger_id)

@rpc("any_peer", "reliable")
func _server_decline_duel(challenger_id: int) -> void:
	"""Client declines a duel request"""
	if not multiplayer.is_server():
		return
	var decliner_id = multiplayer.get_remote_sender_id()
	_handle_duel_decline(decliner_id, challenger_id)

@rpc("any_peer", "reliable")
func _server_report_loss(opponent_id: int) -> void:
	"""Client reports they lost the duel (hit 1 HP)"""
	if not multiplayer.is_server():
		return
	var loser_id = multiplayer.get_remote_sender_id()

	# Validate duel exists
	if not is_dueling(loser_id) or get_duel_opponent(loser_id) != opponent_id:
		return

	_end_duel_local(opponent_id, loser_id)
	rpc("_client_duel_ended", opponent_id, loser_id)

@rpc("authority", "call_local", "reliable")
func _client_request_received(challenger_id: int, challenger_name: String) -> void:
	"""Server notifies client of incoming duel request"""
	var my_id = multiplayer.get_unique_id()
	_add_pending_request(my_id, challenger_id, challenger_name)

@rpc("authority", "call_local", "reliable")
func _client_request_declined(decliner_id: int) -> void:
	"""Server notifies challenger that request was declined"""
	sent_requests.erase(decliner_id)
	var decliner_name = _get_player_name(decliner_id)
	if NotificationManager:
		NotificationManager.show_notification("%s declined your duel request" % decliner_name, "INFO")

@rpc("authority", "call_local", "reliable")
func _client_countdown_started(player1_id: int, player2_id: int, duration: int) -> void:
	"""Server notifies clients that countdown has started"""
	_start_countdown(player1_id, player2_id)

@rpc("authority", "call_local", "reliable")
func _client_duel_ended(winner_id: int, loser_id: int) -> void:
	"""Server notifies clients that duel has ended"""
	_end_duel_local(winner_id, loser_id)

# ============================================
# PVP DAMAGE HANDLING
# ============================================

@rpc("any_peer", "reliable")
func request_pvp_damage(target_id: int, damage: int) -> void:
	"""Client requests to deal PvP damage (duel or open-world based on allegiance)"""
	if not multiplayer.is_server():
		return

	var attacker_id = multiplayer.get_remote_sender_id()
	if attacker_id == 0:
		attacker_id = 1  # Server's peer ID

	var attacker_player = _get_player_node(attacker_id)
	var target_player = _get_player_node(target_id)

	if not attacker_player or not target_player:
		print("[PvP] Damage rejected: invalid player nodes")
		return

	# Check if attacker is in a duel
	var is_in_duel = active_duels.has(attacker_id)
	var is_dueling_target = is_in_duel and active_duels[attacker_id] == target_id

	# Validate PvP permission
	if is_in_duel:
		# During duel: only allow damage to duel opponent
		if not is_dueling_target:
			print("[PvP] Damage rejected: target %d is not duel opponent" % target_id)
			return
	else:
		# Open-world PvP: check allegiance rules
		if not _can_damage_player_server(attacker_player, target_player, attacker_id, target_id):
			print("[PvP] Damage rejected: allegiance rules prevent damage")
			return

	# Validate damage amount against player's actual stats
	var max_damage = _get_max_pvp_damage(attacker_id)
	if damage <= 0 or damage > max_damage:
		push_warning("Anti-cheat: Invalid PvP damage %d from player %d (max expected: %d)" % [damage, attacker_id, max_damage])
		damage = clampi(damage, 1, max_damage)

	# Check if target is dashing (i-frames)
	if target_player.get("is_dashing") == true:
		print("[PvP] Damage blocked - target %d is dashing" % target_id)
		return

	# Check safe aura
	if target_player.get("has_safe_aura") == true:
		print("[PvP] Damage blocked - target %d has safe aura" % target_id)
		return

	print("[PvP] Server applying %d damage from %d to %d" % [damage, attacker_id, target_id])

	# Apply damage via RPC to all clients
	rpc("apply_pvp_damage", target_id, damage, attacker_id)

func _can_damage_player_server(attacker: Node, target: Node, attacker_id: int, target_id: int) -> bool:
	"""Server-side allegiance check for open-world PvP"""
	# Safe zone check - no PvP in chunk 0 (spawn area)
	if _is_in_safe_zone(attacker) or _is_in_safe_zone(target):
		print("[PvP] Safe zone protection - no open-world PvP allowed")
		return false

	# Party protection
	if GroupManager and GroupManager.has_group():
		# Check if both are in the same group
		var attacker_in_group = GroupManager.is_group_member(attacker_id) or GroupManager.group_leader_id == attacker_id
		var target_in_group = GroupManager.is_group_member(target_id) or GroupManager.group_leader_id == target_id
		if attacker_in_group and target_in_group:
			return false

	# Get allegiances
	var attacker_allegiance = attacker.get("allegiance_id")
	var target_allegiance = target.get("allegiance_id")
	if attacker_allegiance == null:
		attacker_allegiance = "ashbane"
	if target_allegiance == null:
		target_allegiance = "ashbane"

	# Rogues can damage and be damaged by everyone
	if attacker_allegiance == "" or target_allegiance == "":
		return true

	# Same allegiance = no damage
	if attacker_allegiance == target_allegiance:
		return false

	# Different allegiance = can damage
	return true

func _is_in_safe_zone(player_node: Node) -> bool:
	"""Check if player is in a safe zone (chunk 0 = spawn area)"""
	if not player_node or not is_instance_valid(player_node):
		return false

	var pos = player_node.global_position
	var chunk_size = 8000.0  # Default chunk size

	# Try to get chunk size from ChunkBasedPropSystem
	var prop_system = get_node_or_null("/root/GameWorld/ChunkBasedPropSystem")
	if prop_system and prop_system.get("CHUNK_SIZE"):
		chunk_size = prop_system.CHUNK_SIZE

	# Chunk 0 is from x=0 to x=chunk_size
	var chunk_x = int(floor(pos.x / chunk_size))
	return chunk_x == 0

@rpc("authority", "call_local", "reliable")
func apply_pvp_damage(target_id: int, damage: int, attacker_id: int) -> void:
	"""Server broadcasts PvP damage to all clients"""
	var target_player = _get_player_node(target_id)
	if not target_player:
		print("[PvP] Could not find target player %d" % target_id)
		return

	# Only the target processes the actual damage
	var my_id = -1
	if multiplayer.has_multiplayer_peer():
		my_id = multiplayer.get_unique_id()

	if my_id == target_id and target_player.has_method("take_damage"):
		target_player.take_damage(damage, "player", attacker_id)
		print("[PvP] Applied %d damage to self from player %d" % [damage, attacker_id])

# ============================================
# DAMAGE VALIDATION HELPERS
# ============================================

func _get_max_pvp_damage(attacker_peer_id: int) -> int:
	"""Get maximum expected PvP damage for a player based on their actual stats."""
	var base_damage: float = 15.0  # Default base damage

	# Try to find the attacking player's actual damage stat
	var attacker = _get_player_node(attacker_peer_id)
	if attacker and attacker.get("attack_damage") != null:
		base_damage = attacker.attack_damage

	# Add buffer for weapon variance, combo multipliers, etc.
	# Max realistic damage with best gear and max combo is ~150-200 base * 2x combo = 400
	return int(maxf(base_damage * 3.0, 200.0))  # 3x multiplier minimum 200
