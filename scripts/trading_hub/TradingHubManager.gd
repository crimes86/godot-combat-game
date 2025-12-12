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
var _returning_from_hub: bool = false  # Flag to indicate player just exited hub

# Player state preservation across transitions
var _preserved_player_state: Dictionary = {}  # health, status effects, etc.

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

func is_returning_from_hub() -> bool:
	"""Check if player just exited the hub and needs special spawn position"""
	return _returning_from_hub

func clear_returning_flag() -> void:
	"""Clear the returning flag after spawn position is used"""
	_returning_from_hub = false

# ============================================
# PLAYER STATE PRESERVATION
# ============================================

func save_player_state(player: Node) -> void:
	"""Save player state before scene transition"""
	if not player or not is_instance_valid(player):
		return

	_preserved_player_state.clear()

	# Save health (Player uses current_health, not health)
	if "current_health" in player:
		_preserved_player_state["current_health"] = player.current_health
	if "max_health" in player:
		_preserved_player_state["max_health"] = player.max_health

	# Save stamina if exists
	if "current_stamina" in player:
		_preserved_player_state["current_stamina"] = player.current_stamina
	if "max_stamina" in player:
		_preserved_player_state["max_stamina"] = player.max_stamina

	# Save any status effects if the player has them
	if player.has_method("get_status_effects"):
		_preserved_player_state["status_effects"] = player.get_status_effects()

	print("[TradingHubManager] Saved player state: %s" % _preserved_player_state)

func restore_player_state(player: Node) -> void:
	"""Restore player state after scene transition"""
	if not player or not is_instance_valid(player):
		return

	if _preserved_player_state.is_empty():
		print("[TradingHubManager] No preserved state to restore")
		return

	# Restore health (Player uses current_health, not health)
	if _preserved_player_state.has("current_health") and "current_health" in player:
		player.current_health = _preserved_player_state["current_health"]
	if _preserved_player_state.has("max_health") and "max_health" in player:
		player.max_health = _preserved_player_state["max_health"]

	# Restore stamina
	if _preserved_player_state.has("current_stamina") and "current_stamina" in player:
		player.current_stamina = _preserved_player_state["current_stamina"]
	if _preserved_player_state.has("max_stamina") and "max_stamina" in player:
		player.max_stamina = _preserved_player_state["max_stamina"]

	# Restore status effects
	if _preserved_player_state.has("status_effects") and player.has_method("set_status_effects"):
		player.set_status_effects(_preserved_player_state["status_effects"])

	# Update UI
	if player.has_method("update_health_bar"):
		player.update_health_bar()

	print("[TradingHubManager] Restored player state: %s" % _preserved_player_state)
	_preserved_player_state.clear()

func has_preserved_state() -> bool:
	"""Check if there's preserved player state to restore"""
	return not _preserved_player_state.is_empty()

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
		# Set flag so game_world knows to spawn at tunnel exit
		_returning_from_hub = true
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
# SCENE TRANSITIONS
# ============================================

var _pending_hub_transition: bool = false
# TEMPORARILY using minimal TestHub to debug scene loading issues
var _hub_scene_path: String = "res://scenes/trading_hub/TestHub.tscn"
var _hub_scene_cached: PackedScene = null  # Pre-loaded scene

func _ready() -> void:
	# Ensure this autoload always processes, even if game is paused or scenes are changing
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[TradingHubManager] Initialized")
	# Skip preloading - load fresh each time to avoid cache issues during development
	print("[TradingHubManager] Preloading disabled for development")

var _preload_poll_count: int = 0

func _start_preload_poll() -> void:
	"""Poll for preload completion"""
	var timer = get_tree().create_timer(0.1)
	timer.timeout.connect(_check_preload_status, CONNECT_ONE_SHOT)

func _check_preload_status() -> void:
	"""Check if preload is complete"""
	_preload_poll_count += 1
	var status = ResourceLoader.load_threaded_get_status(_hub_scene_path)
	print("[TradingHubManager] Preload poll #%d - status: %d" % [_preload_poll_count, status])

	if status == 2:  # THREAD_LOAD_LOADED
		print("[TradingHubManager] Status is 2, calling load_threaded_get()...")
		_hub_scene_cached = ResourceLoader.load_threaded_get(_hub_scene_path)
		print("[TradingHubManager] load_threaded_get returned: %s" % str(_hub_scene_cached))
		if _hub_scene_cached:
			print("[TradingHubManager] ✅ Pre-loaded TradingHub scene successfully!")
		else:
			# Try regular load as fallback
			print("[TradingHubManager] Threaded get returned null, trying regular load()...")
			_hub_scene_cached = load(_hub_scene_path)
			print("[TradingHubManager] Regular load() returned: %s" % str(_hub_scene_cached))
			if _hub_scene_cached:
				print("[TradingHubManager] ✅ Regular load succeeded!")
			else:
				push_error("[TradingHubManager] ❌ Both threaded and regular load returned null!")
	elif status == 1:  # THREAD_LOAD_IN_PROGRESS
		if _preload_poll_count < 100:  # Max ~10 seconds of polling
			_start_preload_poll()
		else:
			push_error("[TradingHubManager] ❌ Preload timeout after %d polls!" % _preload_poll_count)
	elif status == 3:  # THREAD_LOAD_FAILED
		push_error("[TradingHubManager] ❌ Threaded preload FAILED!")
	else:
		push_error("[TradingHubManager] ❌ Preload invalid status: %d" % status)

func _ensure_scene_loaded() -> bool:
	"""Ensure the hub scene is loaded. Returns true if successful."""
	if _hub_scene_cached != null:
		return true

	print("[TradingHubManager] Loading TradingHub scene on-demand...")
	print("[TradingHubManager] Path: %s" % _hub_scene_path)

	# Check if file exists first
	var file_exists = FileAccess.file_exists(_hub_scene_path)
	var resource_exists = ResourceLoader.exists(_hub_scene_path)
	print("[TradingHubManager] File exists: %s, Resource exists: %s" % [file_exists, resource_exists])

	if not resource_exists:
		push_error("[TradingHubManager] Scene resource does not exist!")
		return false

	# Try loading with ResourceLoader (more control than load())
	print("[TradingHubManager] About to call ResourceLoader.load()...")
	_hub_scene_cached = ResourceLoader.load(_hub_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
	print("[TradingHubManager] ResourceLoader.load() returned: %s" % str(_hub_scene_cached))

	if _hub_scene_cached:
		print("[TradingHubManager] ✅ Scene loaded successfully: %s" % _hub_scene_cached)
		return true
	else:
		push_error("[TradingHubManager] ❌ Failed to load scene!")
		return false

func transition_to_hub() -> void:
	"""Transition to TradingHub scene - called from TunnelEntrance"""
	print("[TradingHubManager] transition_to_hub() called")
	if _pending_hub_transition:
		print("[TradingHubManager] Already transitioning, ignoring duplicate call")
		return
	_pending_hub_transition = true

	# Debug: Show what's currently in the scene tree
	_debug_scene_tree_state("BEFORE TRANSITION")

	# Use a timer to ensure we're completely outside the current frame's processing
	# call_deferred runs at end of frame but physics may still be locked
	print("[TradingHubManager] Scheduling transition for next frame via timer...")
	var timer = get_tree().create_timer(0.0)  # Zero-duration = next frame
	timer.timeout.connect(_do_deferred_hub_transition, CONNECT_ONE_SHOT)

func _do_deferred_hub_transition() -> void:
	"""Actually perform the hub transition - called via timer"""
	print("[TradingHubManager] _do_deferred_hub_transition() running (timer callback)")

	var tree = get_tree()
	if not tree:
		push_error("[TradingHubManager] No scene tree!")
		_pending_hub_transition = false
		return

	# If we have a pre-loaded scene, use change_scene_to_packed instead
	if _hub_scene_cached:
		print("[TradingHubManager] Using pre-loaded scene with change_scene_to_packed...")
		var err = tree.change_scene_to_packed(_hub_scene_cached)
		print("[TradingHubManager] change_scene_to_packed returned: %d (OK=0, ERR_LOCKED=19)" % err)
		if err == OK:
			print("[TradingHubManager] ✅ Scene change initiated successfully!")
			_pending_hub_transition = false
			return
		# If packed approach also fails, try manual swap
		print("[TradingHubManager] change_scene_to_packed failed, trying manual swap...")
		_do_manual_scene_swap()
		return

	# Fallback: Try the standard Godot approach: change_scene_to_file
	print("[TradingHubManager] No pre-loaded scene, attempting change_scene_to_file('%s')..." % _hub_scene_path)
	var err = tree.change_scene_to_file(_hub_scene_path)
	print("[TradingHubManager] change_scene_to_file returned: %d (OK=0, ERR_LOCKED=19)" % err)

	if err == OK:
		print("[TradingHubManager] ✅ Scene change initiated successfully!")
		_pending_hub_transition = false
		return

	# If standard approach fails, try threaded loading
	print("[TradingHubManager] Standard approach failed (err=%d), starting threaded load..." % err)
	_start_threaded_load()

func _start_threaded_load() -> void:
	"""Start loading the scene in a background thread"""
	print("[TradingHubManager] ResourceLoader.load_threaded_request('%s')..." % _hub_scene_path)
	var err = ResourceLoader.load_threaded_request(_hub_scene_path, "PackedScene")
	print("[TradingHubManager] load_threaded_request returned: %d" % err)

	if err != OK:
		push_error("[TradingHubManager] Failed to start threaded load!")
		_pending_hub_transition = false
		return

	# Poll for completion
	_poll_threaded_load()

func _poll_threaded_load() -> void:
	"""Check if threaded load is complete"""
	print("[TradingHubManager] _poll_threaded_load() entered")
	var status = ResourceLoader.load_threaded_get_status(_hub_scene_path)
	print("[TradingHubManager] Threaded load status: %d" % status)
	print("[TradingHubManager] Checking if status == 2...")

	# Use direct int comparison to avoid any enum comparison issues
	if status == 2:  # THREAD_LOAD_LOADED
		print("[TradingHubManager] YES! status == 2")
		# Load complete - get the resource
		print("[TradingHubManager] ✅ Status=2 (LOADED)! Getting resource...")
		_hub_scene_cached = ResourceLoader.load_threaded_get(_hub_scene_path)
		print("[TradingHubManager] load_threaded_get returned: %s" % str(_hub_scene_cached))

		# If threaded get returns null, try regular load (resource should be cached now)
		if not _hub_scene_cached:
			print("[TradingHubManager] Threaded get returned null, trying regular load()...")
			_hub_scene_cached = load(_hub_scene_path)
			print("[TradingHubManager] Regular load() returned: %s" % str(_hub_scene_cached))

		if _hub_scene_cached:
			print("[TradingHubManager] Scene acquired, calling _do_manual_scene_swap()...")
			_do_manual_scene_swap()
		else:
			push_error("[TradingHubManager] Both threaded and regular load returned null!")
			_pending_hub_transition = false
	elif status == 1:  # THREAD_LOAD_IN_PROGRESS
		# Still loading - check again next frame
		print("[TradingHubManager] Still loading (status=1), polling again in 50ms...")
		get_tree().create_timer(0.05).timeout.connect(_poll_threaded_load, CONNECT_ONE_SHOT)
	elif status == 3:  # THREAD_LOAD_FAILED
		push_error("[TradingHubManager] Threaded load FAILED (status=3)!")
		_pending_hub_transition = false
	elif status == 0:  # THREAD_LOAD_INVALID_RESOURCE
		push_error("[TradingHubManager] Invalid resource (status=0)!")
		_pending_hub_transition = false
	else:
		push_error("[TradingHubManager] Unknown status: %d" % status)
		_pending_hub_transition = false

func _do_manual_scene_swap() -> void:
	"""Swap scenes manually after loading"""
	print("[TradingHubManager] _do_manual_scene_swap() called")

	if not _hub_scene_cached:
		push_error("[TradingHubManager] No cached scene to swap!")
		_pending_hub_transition = false
		return

	print("[TradingHubManager] Instantiating scene...")
	var new_scene_instance = _hub_scene_cached.instantiate()
	if not new_scene_instance:
		push_error("[TradingHubManager] Failed to instantiate scene!")
		_pending_hub_transition = false
		return

	print("[TradingHubManager] instantiate() returned: %s" % str(new_scene_instance))

	var tree = get_tree()
	var root = tree.root
	var current_scene = tree.current_scene

	print("[TradingHubManager] Current scene: %s" % (current_scene.name if current_scene else "null"))

	# Remove current scene
	if current_scene:
		print("[TradingHubManager] Removing current scene...")
		root.remove_child(current_scene)
		current_scene.queue_free()

	# Add new scene
	print("[TradingHubManager] Adding new scene...")
	root.add_child(new_scene_instance)
	tree.current_scene = new_scene_instance

	print("[TradingHubManager] ✅ Scene swap complete!")
	_pending_hub_transition = false

func _debug_scene_tree_state(context: String) -> void:
	"""Print debug info about current scene tree state"""
	print("=" .repeat(50))
	print("[DEBUG] Scene Tree State - %s" % context)
	print("=" .repeat(50))

	var tree = get_tree()
	if not tree:
		print("  SceneTree is NULL!")
		return

	# Check if we're inside a physics callback
	print("  is_physics_processing: %s" % is_physics_processing())
	print("  is_processing: %s" % is_processing())

	# Current scene info
	var current = tree.current_scene
	if current:
		print("  current_scene: %s (%s)" % [current.name, current.get_class()])
		print("  current_scene is_inside_tree: %s" % current.is_inside_tree())
		print("  current_scene is_processing: %s" % current.is_processing())
	else:
		print("  current_scene: null")

	# Root children (autoloads + current scene)
	print("  Root children (%d):" % tree.root.get_child_count())
	for i in range(tree.root.get_child_count()):
		var child = tree.root.get_child(i)
		var processing_info = ""
		if child.is_processing():
			processing_info += " [processing]"
		if child.is_physics_processing():
			processing_info += " [physics]"
		print("    [%d] %s (%s)%s" % [i, child.name, child.get_class(), processing_info])

	# Check for any Area2D that might be in a collision callback
	var areas = tree.get_nodes_in_group("areas_with_body")
	if areas.size() > 0:
		print("  Active Area2D nodes with bodies: %d" % areas.size())

	# Check for players in collision
	var players = tree.get_nodes_in_group("player")
	print("  Players in tree: %d" % players.size())
	for p in players:
		if p.is_inside_tree():
			print("    - %s at %s, processing: %s" % [p.name, p.global_position, p.is_processing()])

	print("=" .repeat(50))

func _do_hub_transition_packed(packed_scene: PackedScene) -> void:
	print("[TradingHubManager] _do_hub_transition_packed called!")
	var tree = get_tree()
	if not tree:
		push_error("[TradingHubManager] SceneTree is null!")
		_pending_hub_transition = false
		return

	# Try change_scene_to_packed first
	print("[TradingHubManager] Calling change_scene_to_packed...")
	var err = tree.change_scene_to_packed(packed_scene)
	print("[TradingHubManager] change_scene_to_packed returned: %d (OK=0)" % err)

	if err != OK:
		# Try call_deferred as fallback
		print("[TradingHubManager] Direct call failed, trying call_deferred...")
		tree.call_deferred("change_scene_to_packed", packed_scene)
		print("[TradingHubManager] Deferred call queued")

	_pending_hub_transition = false

func transition_to_zone1() -> void:
	"""Transition back to Zone 1 - called from TradingHub exits"""
	print("[TradingHubManager] transition_to_zone1() called")
	var tree = get_tree()
	if tree:
		# Use call_deferred to ensure scene change happens outside any locked context
		print("[TradingHubManager] Queuing scene change to main.tscn via call_deferred...")
		tree.call_deferred("change_scene_to_file", "res://main.tscn")
	else:
		push_error("[TradingHubManager] SceneTree is null!")

# ============================================
# CLEANUP
# ============================================

func clear_player_data() -> void:
	"""Clear all player hub data (on disconnect, etc)"""
	_player_origin_chunks.clear()
	_player_in_hub.clear()
	_local_origin_chunk = 0
