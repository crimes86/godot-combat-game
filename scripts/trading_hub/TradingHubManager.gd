# TradingHubManager.gd - Manages trading hub state and player routing
# Autoload singleton for hub management
extends Node

signal player_entered_hub(player_id: int, shard_id: String)
signal player_exited_hub(player_id: int, destination: String)

# Hub configuration
const SOFT_CAP: int = 100
const HARD_CAP: int = 150
const AFK_WARNING_TIME: float = 480.0  # 8 minutes
const AFK_KICK_TIME: float = 600.0     # 10 minutes

# Player tracking
var _player_origin_chunks: Dictionary = {}  # player_id -> chunk_id they entered from
var _player_in_hub: Dictionary = {}  # player_id -> bool
var _current_shard: String = "Hub-A"  # For now, single shard

# For single player / early implementation
var _local_origin_chunk: int = 0

func _ready() -> void:
	print("[TradingHubManager] Initialized")

# ============================================
# ENTRY / EXIT MANAGEMENT
# ============================================

func set_player_origin_chunk(chunk_id: int) -> void:
	"""Store which chunk the local player entered from (for return trip)"""
	_local_origin_chunk = chunk_id
	print("[TradingHubManager] Player origin chunk set to: %d" % chunk_id)

func get_player_origin_chunk() -> int:
	"""Get the chunk the player should return to when exiting south"""
	return _local_origin_chunk

func get_origin_spawn_position() -> Vector2:
	"""Calculate spawn position in Zone 1 when exiting hub"""
	# Spawn just south of where the tunnel entrance would be
	var chunk_center_x = _local_origin_chunk * Constants.CHUNK_SIZE + Constants.CHUNK_SIZE / 2
	var spawn_y = -Constants.CHUNK_SIZE / 2 + 200  # Just inside the world, south of tunnel
	return Vector2(chunk_center_x, spawn_y)

func is_player_in_hub() -> bool:
	"""Check if local player is currently in the hub"""
	return _player_in_hub.get(multiplayer.get_unique_id(), false)

func set_player_in_hub(in_hub: bool) -> void:
	"""Mark local player as in/out of hub"""
	var player_id = multiplayer.get_unique_id()
	_player_in_hub[player_id] = in_hub

	if in_hub:
		player_entered_hub.emit(player_id, _current_shard)
	else:
		player_exited_hub.emit(player_id, "zone1")

# ============================================
# SHARD MANAGEMENT (Simplified for MVP)
# ============================================

func get_current_shard() -> String:
	"""Get current shard ID (placeholder for future multi-shard)"""
	return _current_shard

func get_shard_population() -> int:
	"""Get current shard population (placeholder)"""
	# TODO: Implement actual player counting
	return _player_in_hub.size()

func get_available_shards() -> Array:
	"""Get list of available shards with population info"""
	# Placeholder for future multi-shard system
	return [
		{"id": "Hub-A", "population": get_shard_population(), "is_current": true}
	]

# ============================================
# ZONE 2 EXIT (Placeholder)
# ============================================

func get_zone2_destination() -> Dictionary:
	"""Get assigned Zone 2 chunk when exiting north"""
	# Placeholder - will implement load balancing later
	return {
		"chunk_id": 0,
		"spawn_position": Vector2(Constants.CHUNK_SIZE / 2, Constants.CHUNK_SIZE / 2 - 200),
		"is_new_chunk": false
	}

# ============================================
# CLEANUP
# ============================================

func clear_player_data() -> void:
	"""Clear all player hub data (on disconnect, etc)"""
	_player_origin_chunks.clear()
	_player_in_hub.clear()
	_local_origin_chunk = 0
