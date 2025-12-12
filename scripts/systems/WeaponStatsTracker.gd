extends Node

## WeaponStatsTracker - Autoload for managing forged weapon stats
## Handles loading, saving, and syncing weapon stats with backend
## Add to Project Settings > AutoLoad as "WeaponStatsTracker"

signal stats_loaded(forged_id: String, stats: WeaponStats)
signal stats_saved(forged_id: String)
signal stats_sync_failed(forged_id: String, error: String)

# Cache of loaded weapon stats by forged_id
var _stats_cache: Dictionary = {}  # forged_id -> WeaponStats

# Track equipped time
var _equipped_weapon_id: String = ""
var _equipped_start_time: float = 0.0
const EQUIPPED_TIME_UPDATE_INTERVAL: float = 60.0  # Update every minute
var _equipped_time_timer: float = 0.0

# Auto-save interval
const AUTO_SAVE_INTERVAL: float = 300.0  # Save every 5 minutes
var _auto_save_timer: float = 0.0

# Backend sync
var _pending_syncs: Array[String] = []
var _is_syncing: bool = false

func _ready() -> void:
	# Connect to CharacterStats weapon changes
	if CharacterStats.has_signal("weapon_changed"):
		CharacterStats.weapon_changed.connect(_on_weapon_changed)

func _process(delta: float) -> void:
	# Update equipped time
	if _equipped_weapon_id != "":
		_equipped_time_timer += delta
		if _equipped_time_timer >= EQUIPPED_TIME_UPDATE_INTERVAL:
			_equipped_time_timer = 0.0
			_update_equipped_time()

	# Auto-save
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		_auto_save_all()

# ========================================
# PUBLIC API
# ========================================

func get_stats(forged_id: String) -> WeaponStats:
	"""Get stats for a forged weapon, loading from cache or creating new"""
	if forged_id in _stats_cache:
		return _stats_cache[forged_id]

	# Try to load from local storage
	var stats = _load_stats_local(forged_id)
	if stats:
		_stats_cache[forged_id] = stats
		return stats

	# Create new virgin stats
	stats = WeaponStats.new()
	_stats_cache[forged_id] = stats
	return stats

func save_stats(forged_id: String) -> void:
	"""Save stats for a forged weapon to local storage"""
	if not forged_id in _stats_cache:
		return

	var stats = _stats_cache[forged_id]
	_save_stats_local(forged_id, stats)
	stats_saved.emit(forged_id)

func save_all_stats() -> void:
	"""Save all cached stats"""
	for forged_id in _stats_cache:
		save_stats(forged_id)

func sync_to_backend(forged_id: String) -> void:
	"""Queue stats for sync to backend"""
	if not forged_id in _pending_syncs:
		_pending_syncs.append(forged_id)
	_process_sync_queue()

func attach_stats_to_weapon(weapon: Weapon) -> void:
	"""Attach stats to a forged weapon resource"""
	if not weapon.is_forged or weapon.forged_id == "":
		return

	weapon.weapon_stats = get_stats(weapon.forged_id)
	weapon.weapon_stats.record_equip()

func on_weapon_equipped(weapon: Weapon) -> void:
	"""Called when a forged weapon is equipped"""
	if not weapon or not weapon.is_forged:
		_equipped_weapon_id = ""
		return

	# Save previous weapon's stats
	if _equipped_weapon_id != "" and _equipped_weapon_id != weapon.forged_id:
		_update_equipped_time()
		save_stats(_equipped_weapon_id)

	# Start tracking new weapon
	_equipped_weapon_id = weapon.forged_id
	_equipped_start_time = Time.get_ticks_msec() / 1000.0
	_equipped_time_timer = 0.0

	# Attach stats if not already
	if not weapon.weapon_stats:
		attach_stats_to_weapon(weapon)

func on_weapon_unequipped() -> void:
	"""Called when weapon is unequipped"""
	if _equipped_weapon_id != "":
		_update_equipped_time()
		save_stats(_equipped_weapon_id)
		_equipped_weapon_id = ""

# ========================================
# LOCAL STORAGE
# ========================================

func _get_stats_path(forged_id: String) -> String:
	"""Get path for weapon stats file"""
	return "user://weapon_stats/%s.json" % forged_id

func _load_stats_local(forged_id: String) -> WeaponStats:
	"""Load stats from local file"""
	var path = _get_stats_path(forged_id)

	if not FileAccess.file_exists(path):
		return null

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Failed to open weapon stats file: %s" % path)
		return null

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse weapon stats JSON: %s" % json.get_error_message())
		return null

	var data = json.get_data()
	if not data is Dictionary:
		push_error("Invalid weapon stats data format")
		return null

	var stats = WeaponStats.from_dict(data)
	stats_loaded.emit(forged_id, stats)
	return stats

func _save_stats_local(forged_id: String, stats: WeaponStats) -> void:
	"""Save stats to local file"""
	# Ensure directory exists
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("weapon_stats"):
		dir.make_dir("weapon_stats")

	var path = _get_stats_path(forged_id)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open weapon stats file for writing: %s" % path)
		return

	var data = stats.to_dict()
	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()

func _update_equipped_time() -> void:
	"""Update equipped time for current weapon"""
	if _equipped_weapon_id == "" or not _equipped_weapon_id in _stats_cache:
		return

	var stats = _stats_cache[_equipped_weapon_id]
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed = int(current_time - _equipped_start_time)

	if elapsed > 0:
		stats.add_equipped_time(elapsed)
		_equipped_start_time = current_time

func _auto_save_all() -> void:
	"""Auto-save all dirty stats"""
	_update_equipped_time()
	save_all_stats()

# ========================================
# BACKEND SYNC
# ========================================

func _process_sync_queue() -> void:
	"""Process pending syncs to backend"""
	if _is_syncing or _pending_syncs.is_empty():
		return

	_is_syncing = true
	var forged_id = _pending_syncs.pop_front()

	if not forged_id in _stats_cache:
		_is_syncing = false
		_process_sync_queue()
		return

	var stats = _stats_cache[forged_id]
	_sync_stats_to_backend(forged_id, stats)

func _sync_stats_to_backend(forged_id: String, stats: WeaponStats) -> void:
	"""Sync stats to backend API"""
	# Get auth token
	var auth_manager = get_node_or_null("/root/AuthManager")
	if not auth_manager or not auth_manager.get("auth_token"):
		_on_sync_complete(forged_id, false, "Not authenticated")
		return

	var token = auth_manager.auth_token

	# Prepare request
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_sync_request_completed.bind(forged_id, http))

	var url = "%s/api/weapon-stats/%s" % [_get_backend_url(), forged_id]
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % token
	]
	var body = JSON.stringify(stats.to_dict())

	var error = http.request(url, headers, HTTPClient.METHOD_PUT, body)
	if error != OK:
		http.queue_free()
		_on_sync_complete(forged_id, false, "Request failed: %d" % error)

func _on_sync_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, forged_id: String, http: HTTPRequest) -> void:
	"""Handle sync response"""
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		_on_sync_complete(forged_id, false, "HTTP error: %d" % result)
		return

	if response_code != 200:
		_on_sync_complete(forged_id, false, "Server error: %d" % response_code)
		return

	_on_sync_complete(forged_id, true, "")

func _on_sync_complete(forged_id: String, success: bool, error: String) -> void:
	"""Handle sync completion"""
	_is_syncing = false

	if not success:
		push_warning("Failed to sync weapon stats for %s: %s" % [forged_id, error])
		stats_sync_failed.emit(forged_id, error)
		# Re-queue for retry later
		if not forged_id in _pending_syncs:
			_pending_syncs.append(forged_id)

	# Process next in queue
	_process_sync_queue()

func _get_backend_url() -> String:
	"""Get backend API URL"""
	# Check for environment override
	if OS.has_environment("BACKEND_URL"):
		return OS.get_environment("BACKEND_URL")
	# Default to localhost for development
	return "http://localhost:8000"

# ========================================
# SIGNAL HANDLERS
# ========================================

func _on_weapon_changed(weapon: Weapon) -> void:
	"""Handle weapon change from CharacterStats"""
	if weapon and weapon.is_forged:
		on_weapon_equipped(weapon)
	else:
		on_weapon_unequipped()

# ========================================
# CLEANUP
# ========================================

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		# Final save on exit
		_auto_save_all()
