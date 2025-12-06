extends Node

## GroupManager - Handles party/group system for multiplayer
## Groups allow players to share campfire buffs and see each other's health
##
## Group Structure:
## - Leader: The player who created or was promoted to lead the group
## - Members: All players in the group (including leader)
## - Max size: 40 players
##
## Commands:
## /invite <player> - Invite a player to your group
## /accept - Accept pending group invite
## /decline - Decline pending group invite
## /kick <player> - Leader kicks a player from group
## /leave - Leave the current group
## /promote <player> - Leader promotes someone else to leader
## /disband - Leader disbands the entire group

signal group_updated()  # Emitted when group membership changes
signal group_created(leader_id: int)
signal group_disbanded()
signal player_joined_group(player_id: int, player_name: String)
signal player_left_group(player_id: int, player_name: String)
signal leader_changed(new_leader_id: int, new_leader_name: String)
signal invite_received(from_id: int, from_name: String)
signal invite_expired(from_name: String)

const MAX_GROUP_SIZE: int = 40
const INVITE_TIMEOUT: float = 60.0  # Seconds before invite expires

# Group state (synced across all clients)
var group_members: Array[int] = []  # Array of peer_ids in group
var group_leader: int = -1  # Peer ID of leader (-1 = no group)
var member_names: Dictionary = {}  # peer_id -> player_name

# Pending invites (local tracking)
var pending_invites: Dictionary = {}  # from_peer_id -> {name: String, timestamp: float}
var sent_invites: Dictionary = {}  # to_peer_id -> timestamp

func _ready() -> void:
	print("✅ GroupManager initialized")

func _process(_delta: float) -> void:
	# Clean up expired invites
	var current_time = Time.get_unix_time_from_system()
	var expired_invites: Array[int] = []

	for from_id in pending_invites:
		if current_time - pending_invites[from_id].timestamp > INVITE_TIMEOUT:
			expired_invites.append(from_id)

	for from_id in expired_invites:
		var invite_data = pending_invites[from_id]
		pending_invites.erase(from_id)
		invite_expired.emit(invite_data.name)

# ═══════════════════════════════════════════════════════════════════════════
# LOCAL QUERIES
# ═══════════════════════════════════════════════════════════════════════════

func has_group() -> bool:
	"""Check if local player is in a group."""
	return group_leader != -1 and group_members.size() > 0

func is_leader() -> bool:
	"""Check if local player is the group leader."""
	if not multiplayer.has_multiplayer_peer():
		return false
	return group_leader == multiplayer.get_unique_id()

func get_group_members() -> Array[int]:
	"""Get all group member peer IDs."""
	return group_members.duplicate()

func get_member_name(peer_id: int) -> String:
	"""Get player name for a group member."""
	return member_names.get(peer_id, "Unknown")

func is_group_member(peer_id: int) -> bool:
	"""Check if a peer is in the same group."""
	return peer_id in group_members

func has_pending_invite() -> bool:
	"""Check if there are pending invites."""
	return not pending_invites.is_empty()

func get_pending_invite_names() -> Array[String]:
	"""Get names of players who sent pending invites."""
	var names: Array[String] = []
	for from_id in pending_invites:
		names.append(pending_invites[from_id].name)
	return names

func get_local_player_name() -> String:
	"""Get the local player's name."""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		return network_manager.player_name
	return "Player"

# ═══════════════════════════════════════════════════════════════════════════
# COMMAND HANDLERS (Called from ChatUI)
# ═══════════════════════════════════════════════════════════════════════════

func cmd_invite(target_name: String) -> String:
	"""Handle /invite command."""
	if not multiplayer.has_multiplayer_peer():
		return "Cannot invite - not connected to multiplayer."

	if target_name.is_empty():
		return "Usage: /invite <player name>"

	# Check if already in a full group
	if has_group() and group_members.size() >= MAX_GROUP_SIZE:
		return "Group is full (max %d players)." % MAX_GROUP_SIZE

	# Only leader can invite if already in a group
	if has_group() and not is_leader():
		return "Only the group leader can invite players."

	# Find target player by name
	var target_id = _find_player_by_name(target_name)
	if target_id == -1:
		return "Player '%s' not found." % target_name

	if target_id == multiplayer.get_unique_id():
		return "You cannot invite yourself."

	if is_group_member(target_id):
		return "'%s' is already in your group." % target_name

	# Send invite via RPC
	var my_name = get_local_player_name()
	_send_invite.rpc_id(target_id, multiplayer.get_unique_id(), my_name)
	sent_invites[target_id] = Time.get_unix_time_from_system()

	return "Invite sent to '%s'." % target_name

func cmd_accept() -> String:
	"""Handle /accept command."""
	if pending_invites.is_empty():
		return "No pending invites."

	if has_group():
		return "You must leave your current group first (/leave)."

	# Accept the most recent invite
	var from_id = pending_invites.keys().back()
	var invite_data = pending_invites[from_id]
	pending_invites.clear()

	# Notify the inviter we accepted
	_accept_invite.rpc_id(from_id, multiplayer.get_unique_id(), get_local_player_name())

	return "Accepted invite from '%s'." % invite_data.name

func cmd_decline() -> String:
	"""Handle /decline command."""
	if pending_invites.is_empty():
		return "No pending invites."

	# Decline all pending invites
	var names: Array[String] = []
	for from_id in pending_invites:
		names.append(pending_invites[from_id].name)
		_decline_invite.rpc_id(from_id, multiplayer.get_unique_id())

	pending_invites.clear()
	return "Declined invite(s) from: %s" % ", ".join(names)

func cmd_leave() -> String:
	"""Handle /leave command."""
	if not has_group():
		return "You are not in a group."

	var my_id = multiplayer.get_unique_id()
	var my_name = get_local_player_name()

	# Notify server/leader about leaving
	_request_leave_group.rpc_id(1, my_id, my_name)

	return "You left the group."

func cmd_kick(target_name: String) -> String:
	"""Handle /kick command."""
	if not has_group():
		return "You are not in a group."

	if not is_leader():
		return "Only the group leader can kick players."

	if target_name.is_empty():
		return "Usage: /kick <player name>"

	var target_id = _find_group_member_by_name(target_name)
	if target_id == -1:
		return "'%s' is not in your group." % target_name

	if target_id == multiplayer.get_unique_id():
		return "You cannot kick yourself. Use /leave or /disband."

	# Send kick command to server
	_request_kick.rpc_id(1, target_id, target_name)

	return "Kicked '%s' from the group." % target_name

func cmd_promote(target_name: String) -> String:
	"""Handle /promote command."""
	if not has_group():
		return "You are not in a group."

	if not is_leader():
		return "Only the group leader can promote players."

	if target_name.is_empty():
		return "Usage: /promote <player name>"

	var target_id = _find_group_member_by_name(target_name)
	if target_id == -1:
		return "'%s' is not in your group." % target_name

	if target_id == multiplayer.get_unique_id():
		return "You are already the leader."

	# Send promote command to server
	_request_promote.rpc_id(1, target_id, target_name)

	return "Promoted '%s' to group leader." % target_name

func cmd_disband() -> String:
	"""Handle /disband command."""
	if not has_group():
		return "You are not in a group."

	if not is_leader():
		return "Only the group leader can disband the group."

	# Send disband command to server
	_request_disband.rpc_id(1)

	return "Group disbanded."

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

func _find_player_by_name(target_name: String) -> int:
	"""Find a player's peer ID by their name.
	Searches scene tree player nodes (same as /players command) for reliability."""
	var search_lower = target_name.to_lower().strip_edges()

	if search_lower.is_empty():
		return -1

	print("🔍 Looking for player: '%s'" % search_lower)

	var tree = get_tree()
	if not tree:
		return -1

	# Search player nodes in scene tree (matches /players command output)
	for node in tree.get_nodes_in_group("player"):
		var health_bar = node.get_node_or_null("HealthBar")
		if health_bar:
			var name_label = health_bar.get_node_or_null("NameLabel")
			if name_label:
				var node_name = name_label.text.to_lower().strip_edges()
				print("🔍 Checking player node: '%s' (auth=%d)" % [name_label.text, node.get_multiplayer_authority()])
				if node_name == search_lower or node_name.begins_with(search_lower):
					return node.get_multiplayer_authority()

	# Also check "players" group (remote players)
	for node in tree.get_nodes_in_group("players"):
		var health_bar = node.get_node_or_null("HealthBar")
		if health_bar:
			var name_label = health_bar.get_node_or_null("NameLabel")
			if name_label:
				var node_name = name_label.text.to_lower().strip_edges()
				print("🔍 Checking remote player: '%s' (auth=%d)" % [name_label.text, node.get_multiplayer_authority()])
				if node_name == search_lower or node_name.begins_with(search_lower):
					return node.get_multiplayer_authority()

	# Fallback: check connected_players dictionary
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager:
		print("🔍 Fallback: checking connected_players: %s" % str(network_manager.connected_players))
		for peer_id in network_manager.connected_players:
			var player_info = network_manager.connected_players[peer_id]
			var player_name = player_info.get("name", "").to_lower().strip_edges()
			if player_name == search_lower or player_name.begins_with(search_lower):
				return peer_id

	print("🔍 Player not found!")
	return -1

func _find_group_member_by_name(target_name: String) -> int:
	"""Find a group member's peer ID by their name."""
	target_name = target_name.to_lower().strip_edges()

	for peer_id in group_members:
		var name = member_names.get(peer_id, "").to_lower()
		if name == target_name:
			return peer_id

	return -1

func _clear_local_group_state() -> void:
	"""Clear local group state."""
	group_members.clear()
	group_leader = -1
	member_names.clear()
	group_updated.emit()

# ═══════════════════════════════════════════════════════════════════════════
# RPC - INVITE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _send_invite(from_id: int, from_name: String) -> void:
	"""Receive an invite from another player."""
	# Store pending invite
	pending_invites[from_id] = {
		"name": from_name,
		"timestamp": Time.get_unix_time_from_system()
	}

	invite_received.emit(from_id, from_name)
	print("📨 Received group invite from %s" % from_name)

@rpc("any_peer", "reliable")
func _accept_invite(accepter_id: int, accepter_name: String) -> void:
	"""Handle when someone accepts our invite."""
	# Remove from sent invites
	sent_invites.erase(accepter_id)

	# If we're not in a group yet, create one with us as leader
	if not has_group():
		var my_id = multiplayer.get_unique_id()
		var my_name = get_local_player_name()

		# Create group on server - if we ARE the server, call directly
		if multiplayer.is_server():
			_server_create_group(my_id, my_name, accepter_id, accepter_name)
		else:
			_server_create_group.rpc_id(1, my_id, my_name, accepter_id, accepter_name)
	else:
		# Add to existing group (server handles this)
		if multiplayer.is_server():
			_server_add_to_group(accepter_id, accepter_name)
		else:
			_server_add_to_group.rpc_id(1, accepter_id, accepter_name)

@rpc("any_peer", "reliable")
func _decline_invite(decliner_id: int) -> void:
	"""Handle when someone declines our invite."""
	sent_invites.erase(decliner_id)
	print("❌ Invite declined")

# ═══════════════════════════════════════════════════════════════════════════
# RPC - SERVER GROUP MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func _server_create_group(leader_id: int, leader_name: String, member_id: int, member_name: String) -> void:
	"""Server creates a new group."""
	if not multiplayer.is_server():
		return

	# Broadcast new group to all members - use untyped Array for RPC compatibility
	var members: Array = [leader_id, member_id]
	var names: Dictionary = {leader_id: leader_name, member_id: member_name}

	_sync_group_state.rpc(leader_id, members, names)
	print("👥 Group created: %s + %s" % [leader_name, member_name])

@rpc("any_peer", "reliable")
func _server_add_to_group(new_member_id: int, new_member_name: String) -> void:
	"""Server adds a player to an existing group."""
	if not multiplayer.is_server():
		return

	# Validate sender is the leader
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != group_leader:
		return

	if group_members.size() >= MAX_GROUP_SIZE:
		return

	# Add new member
	var new_members = group_members.duplicate()
	new_members.append(new_member_id)
	var new_names = member_names.duplicate()
	new_names[new_member_id] = new_member_name

	# Broadcast updated group to all
	_sync_group_state.rpc(group_leader, new_members, new_names)
	print("➕ %s joined the group" % new_member_name)

@rpc("any_peer", "reliable")
func _request_leave_group(leaver_id: int, leaver_name: String) -> void:
	"""Server handles a player leaving the group."""
	if not multiplayer.is_server():
		return

	if leaver_id not in group_members:
		return

	# Remove the leaver
	var new_members: Array[int] = []
	for m in group_members:
		if m != leaver_id:
			new_members.append(m)

	var new_names = member_names.duplicate()
	new_names.erase(leaver_id)

	# If leader left, promote next member
	var new_leader = group_leader
	if leaver_id == group_leader and new_members.size() > 0:
		new_leader = new_members[0]

	# If only one person left, disband
	if new_members.size() <= 1:
		_sync_group_disband.rpc()
		print("👋 Group disbanded - %s left" % leaver_name)
	else:
		_sync_group_state.rpc(new_leader, new_members, new_names)
		print("👋 %s left the group" % leaver_name)

@rpc("any_peer", "reliable")
func _request_kick(target_id: int, target_name: String) -> void:
	"""Server handles kicking a player."""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != group_leader:
		return

	if target_id not in group_members:
		return

	# Remove the kicked player
	var new_members: Array[int] = []
	for m in group_members:
		if m != target_id:
			new_members.append(m)

	var new_names = member_names.duplicate()
	new_names.erase(target_id)

	# Notify kicked player
	_notify_kicked.rpc_id(target_id)

	# If only one person left, disband
	if new_members.size() <= 1:
		_sync_group_disband.rpc()
	else:
		_sync_group_state.rpc(group_leader, new_members, new_names)

	print("🚫 %s was kicked from the group" % target_name)

@rpc("any_peer", "reliable")
func _request_promote(target_id: int, target_name: String) -> void:
	"""Server handles promoting a new leader."""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != group_leader:
		return

	if target_id not in group_members:
		return

	# Broadcast with new leader
	_sync_group_state.rpc(target_id, group_members, member_names)
	print("👑 %s is now the group leader" % target_name)

@rpc("any_peer", "reliable")
func _request_disband() -> void:
	"""Server handles disbanding the group."""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != group_leader:
		return

	_sync_group_disband.rpc()
	print("💥 Group disbanded by leader")

# ═══════════════════════════════════════════════════════════════════════════
# RPC - STATE SYNC (Server -> All Clients)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func _sync_group_state(leader_id: int, members: Array, names: Dictionary) -> void:
	"""Sync group state to all clients."""
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	var was_in_group = has_group()
	var old_leader = group_leader
	var i_was_in_group = my_id in group_members

	group_leader = leader_id
	group_members.clear()
	for m in members:
		group_members.append(m)
	member_names = names.duplicate()

	var i_am_now_in_group = my_id in group_members

	# Emit appropriate signals
	if not was_in_group:
		group_created.emit(leader_id)

	if old_leader != leader_id and old_leader != -1:
		leader_changed.emit(leader_id, names.get(leader_id, "Unknown"))

	# If I just joined a group, notify campfire to merge my solo fuel
	if not i_was_in_group and i_am_now_in_group:
		_notify_campfire_joined_group(leader_id)

	group_updated.emit()

func _notify_campfire_joined_group(leader_id: int) -> void:
	"""Notify campfire that we joined a group - merge solo fuel."""
	# Find the campfire and merge fuel
	var campfires = get_tree().get_nodes_in_group("campfire")
	for campfire in campfires:
		if campfire.has_method("on_player_joined_group"):
			campfire.on_player_joined_group(leader_id)

@rpc("any_peer", "call_local", "reliable")
func _sync_group_disband() -> void:
	"""Sync group disband to all clients."""
	_clear_local_group_state()
	group_disbanded.emit()
	print("💔 Group disbanded")

@rpc("any_peer", "reliable")
func _notify_kicked() -> void:
	"""Notify a player they were kicked."""
	_clear_local_group_state()
	print("🚫 You were kicked from the group")

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER DISCONNECT HANDLING
# ═══════════════════════════════════════════════════════════════════════════

func on_player_disconnected(peer_id: int) -> void:
	"""Called when a player disconnects - server should handle group cleanup."""
	if not multiplayer.is_server():
		return

	if peer_id not in group_members:
		return

	# Treat disconnect like leaving
	var player_name = member_names.get(peer_id, "Unknown")
	_request_leave_group(peer_id, player_name)
