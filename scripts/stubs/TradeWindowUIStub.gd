extends Node
# Server stub for TradeWindowUI - handles RPC relay between clients
# Must have matching RPC signatures to avoid checksum mismatch

var visible: bool = false
var is_trading: bool = false
var trade_partner_id: int = -1

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API (called by other systems)
# ═══════════════════════════════════════════════════════════════════════════

func request_trade(target_id: int) -> Dictionary:
	# Server doesn't initiate trades, but needs this for compatibility
	return {success = false, message = "Server cannot initiate trades"}

func can_request_trade(_target_id: int) -> Dictionary:
	return {valid = false, reason = "Server stub"}

func start_trade(_partner_id: int, _partner_name: String) -> void:
	pass

func close_trade() -> void:
	pass

func hide() -> void:
	pass

func show_trade_window(_partner_id: int, _partner_name: String) -> void:
	pass

func _get_player_name(player_id: int) -> String:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.has_method("get_multiplayer_authority") and p.get_multiplayer_authority() == player_id:
			if "player_name" in p:
				return p.player_name
			elif "username" in p:
				return p.username
	return "Player_%d" % player_id

# ═══════════════════════════════════════════════════════════════════════════
# RPC - SERVER HANDLERS (relay between clients)
# ═══════════════════════════════════════════════════════════════════════════

func _handle_trade_start(requester_id: int, target_id: int) -> void:
	"""Core trade start logic - relay to both clients"""
	var requester_name = _get_player_name(requester_id)
	var target_name = _get_player_name(target_id)

	print("[Trade-Server] Processing trade: %s (%d) <-> %s (%d)" % [requester_name, requester_id, target_name, target_id])

	# Notify requester
	if requester_id != 1:
		rpc_id(requester_id, "_client_trade_started", target_id, target_name)

	# Notify target
	if target_id != 1:
		rpc_id(target_id, "_client_trade_started", requester_id, requester_name)

@rpc("any_peer", "reliable")
func _server_start_immediate_trade(target_id: int) -> void:
	"""Client wants to start immediate trade with target"""
	if not multiplayer.is_server():
		return
	var requester_id = multiplayer.get_remote_sender_id()
	print("[Trade-Server] _server_start_immediate_trade from %d to %d" % [requester_id, target_id])
	_handle_trade_start(requester_id, target_id)

@rpc("any_peer", "reliable")
func _server_request_trade(target_id: int) -> void:
	"""Legacy - redirects to immediate trade"""
	if not multiplayer.is_server():
		return
	_server_start_immediate_trade(target_id)

@rpc("any_peer", "reliable")
func _server_accept_trade(requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	var accepter_id = multiplayer.get_remote_sender_id()
	var accepter_name = _get_player_name(accepter_id)
	rpc_id(requester_id, "_client_trade_accepted", accepter_id, accepter_name)
	rpc_id(accepter_id, "_client_trade_accepted", requester_id, _get_player_name(requester_id))

@rpc("any_peer", "reliable")
func _server_decline_trade(requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	var decliner_id = multiplayer.get_remote_sender_id()
	rpc_id(requester_id, "_client_trade_declined", decliner_id)

@rpc("any_peer", "reliable")
func _server_cancel_trade(partner_id: int) -> void:
	if not multiplayer.is_server():
		return
	var canceller_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_trade_cancelled", canceller_id)

@rpc("any_peer", "reliable")
func _server_update_offer(partner_id: int, items: Array, gold: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_offer_updated", sender_id, items, gold)

@rpc("any_peer", "reliable")
func _server_update_offer_full(partner_id: int, items_data: Array, gold: int) -> void:
	"""Server relay for full item data offer updates"""
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_offer_updated_full", sender_id, items_data, gold)

@rpc("any_peer", "reliable")
func _server_lock_offer(partner_id: int, locked: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	print("[Trade-Server] Relaying lock from %d to %d: %s" % [sender_id, partner_id, locked])
	rpc_id(partner_id, "_client_lock_updated", sender_id, locked)

# ═══════════════════════════════════════════════════════════════════════════
# RPC - CLIENT HANDLERS (no-op on server, but signatures must match)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _client_trade_started(_partner_id: int, _partner_name: String) -> void:
	pass  # Server doesn't open trade windows

@rpc("authority", "call_local", "reliable")
func _client_trade_requested(_requester_id: int, _requester_name: String) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_trade_accepted(_partner_id: int, _partner_name: String) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_trade_declined(_decliner_id: int) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_trade_cancelled(_canceller_id: int) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_offer_updated(_sender_id: int, _items: Array, _gold: int) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_offer_updated_full(_sender_id: int, _items_data: Array, _gold: int) -> void:
	pass

@rpc("authority", "call_local", "reliable")
func _client_lock_updated(_sender_id: int, _locked: bool) -> void:
	pass
