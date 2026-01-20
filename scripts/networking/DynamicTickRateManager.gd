extends Node
# DynamicTickRateManager.gd - Dynamic scaling for "limitless" battles
#
# Monitors player density and adjusts sync rates to maintain playability
# as battles grow. Creates a "fog of war" feel at high player counts
# rather than hard caps or disconnections.
#
# Battle Intensity Levels:
#   NORMAL (1-50):    30Hz players, 20Hz enemies, full AOI
#   INTENSE (50-100): 25Hz players, 15Hz enemies, reduced AOI
#   MASSIVE (100-200): 20Hz players, 10Hz enemies, combat-only AOI
#   LEGENDARY (200+): 15Hz players, 8Hz enemies, squad-focus AOI

signal tick_rate_changed(new_rate: float, intensity_level: int)
signal aoi_radius_changed(new_radius: float)
signal intensity_level_changed(level: int, level_name: String)

# Intensity levels
enum IntensityLevel {
	NORMAL = 0,      # Standard gameplay
	INTENSE = 1,     # Battle heating up
	MASSIVE = 2,     # Large scale combat
	LEGENDARY = 3    # Historic battle
}

# Current state
var current_intensity: IntensityLevel = IntensityLevel.NORMAL
var current_player_tick_rate: float = 30.0  # Hz
var current_enemy_tick_rate: float = 20.0   # Hz
var current_aoi_radius: float = 2000.0      # pixels

# Configuration per intensity level
const INTENSITY_CONFIG = {
	IntensityLevel.NORMAL: {
		"name": "Normal",
		"player_threshold": 0,
		"player_tick_rate": 30.0,
		"enemy_tick_rate": 20.0,
		"aoi_radius": 2000.0,
		"enemy_sync_radius_full": 1500.0,
		"enemy_sync_radius_reduced": 3000.0,
	},
	IntensityLevel.INTENSE: {
		"name": "Intense",
		"player_threshold": 50,
		"player_tick_rate": 25.0,
		"enemy_tick_rate": 15.0,
		"aoi_radius": 1600.0,
		"enemy_sync_radius_full": 1200.0,
		"enemy_sync_radius_reduced": 2400.0,
	},
	IntensityLevel.MASSIVE: {
		"name": "Massive",
		"player_threshold": 100,
		"player_tick_rate": 20.0,
		"enemy_tick_rate": 10.0,
		"aoi_radius": 1200.0,
		"enemy_sync_radius_full": 1000.0,
		"enemy_sync_radius_reduced": 2000.0,
	},
	IntensityLevel.LEGENDARY: {
		"name": "Legendary",
		"player_threshold": 200,
		"player_tick_rate": 15.0,
		"enemy_tick_rate": 8.0,
		"aoi_radius": 1000.0,
		"enemy_sync_radius_full": 800.0,
		"enemy_sync_radius_reduced": 1500.0,
	}
}

# Monitoring
var check_interval: float = 2.0  # Check density every 2 seconds
var check_timer: float = 0.0
var _network_manager: Node = null

# Hysteresis to prevent rapid oscillation
var intensity_change_cooldown: float = 5.0  # Don't change more than every 5s
var last_intensity_change_time: float = 0.0
const DOWNGRADE_BUFFER: int = 10  # Need 10 fewer players to downgrade (prevents flapping)

# Battle density tracking (for hotspot detection)
var hotspot_positions: Array = []  # Array of Vector2 where battles are happening
const HOTSPOT_RADIUS: float = 3000.0  # Consider players within this as "same battle"
const HOTSPOT_MIN_PLAYERS: int = 10   # Minimum players to consider a hotspot

# Stress testing override - allows BotManager to inject simulated player count
var simulated_player_count: int = 0

func _ready():
	# Get reference to NetworkManager
	_network_manager = get_node_or_null("/root/NetworkManager")
	if not _network_manager:
		push_warning("DynamicTickRateManager: NetworkManager not found")

func set_simulated_player_count(count: int) -> void:
	"""For stress testing: add simulated players to the count."""
	simulated_player_count = count
	print("[DynamicTickRateManager] Simulated player count set to %d" % count)

func _process(delta: float):
	if not multiplayer.is_server():
		return

	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		_evaluate_intensity()

func _evaluate_intensity():
	"""Evaluate current player density and adjust intensity level if needed."""
	if not _network_manager:
		return

	# Include both real and simulated players
	var real_players = _network_manager.authenticated_players.size()
	var total_players = real_players + simulated_player_count
	var current_time = Time.get_ticks_msec() / 1000.0

	# Determine target intensity based on player count
	var target_intensity = _get_target_intensity(total_players)

	# Check if we should change intensity (with hysteresis)
	if target_intensity != current_intensity:
		if current_time - last_intensity_change_time >= intensity_change_cooldown:
			# Additional check for downgrade: require buffer
			if target_intensity < current_intensity:
				var threshold = INTENSITY_CONFIG[current_intensity]["player_threshold"]
				if total_players > threshold - DOWNGRADE_BUFFER:
					return  # Don't downgrade yet, still too close to threshold

			_set_intensity(target_intensity)
			last_intensity_change_time = current_time

func _get_target_intensity(player_count: int) -> IntensityLevel:
	"""Determine the appropriate intensity level for given player count."""
	if player_count >= INTENSITY_CONFIG[IntensityLevel.LEGENDARY]["player_threshold"]:
		return IntensityLevel.LEGENDARY
	elif player_count >= INTENSITY_CONFIG[IntensityLevel.MASSIVE]["player_threshold"]:
		return IntensityLevel.MASSIVE
	elif player_count >= INTENSITY_CONFIG[IntensityLevel.INTENSE]["player_threshold"]:
		return IntensityLevel.INTENSE
	else:
		return IntensityLevel.NORMAL

func _set_intensity(new_intensity: IntensityLevel):
	"""Apply a new intensity level and notify all systems."""
	var old_intensity = current_intensity
	current_intensity = new_intensity

	var config = INTENSITY_CONFIG[new_intensity]
	var old_tick_rate = current_player_tick_rate
	var old_aoi = current_aoi_radius

	current_player_tick_rate = config["player_tick_rate"]
	current_enemy_tick_rate = config["enemy_tick_rate"]
	current_aoi_radius = config["aoi_radius"]

	# Log the change
	var level_name = config["name"]
	LogManager.info(
		"[BATTLE INTENSITY] %s -> %s (players: %d, tick: %.0fHz -> %.0fHz, AOI: %.0f -> %.0f)" % [
			INTENSITY_CONFIG[old_intensity]["name"],
			level_name,
			_network_manager.authenticated_players.size() if _network_manager else 0,
			old_tick_rate,
			current_player_tick_rate,
			old_aoi,
			current_aoi_radius
		],
		"network"
	)

	# Emit signals for other systems to react
	intensity_level_changed.emit(new_intensity, level_name)
	tick_rate_changed.emit(current_player_tick_rate, new_intensity)
	aoi_radius_changed.emit(current_aoi_radius)

	# Notify all connected clients
	_broadcast_intensity_change(new_intensity, config)

func _broadcast_intensity_change(intensity: IntensityLevel, config: Dictionary):
	"""Notify all clients of the intensity change so they can adjust interpolation."""
	if not multiplayer.is_server():
		return

	var intensity_data = {
		"level": intensity,
		"name": config["name"],
		"player_tick_rate": config["player_tick_rate"],
		"enemy_tick_rate": config["enemy_tick_rate"],
		"aoi_radius": config["aoi_radius"],
	}

	# Broadcast to all peers
	rpc("_client_receive_intensity_change", intensity_data)

@rpc("authority", "reliable", "call_remote")
func _client_receive_intensity_change(intensity_data: Dictionary):
	"""Client receives intensity change from server."""
	var level = intensity_data.get("level", 0)
	var level_name = intensity_data.get("name", "Normal")

	current_intensity = level
	current_player_tick_rate = intensity_data.get("player_tick_rate", 30.0)
	current_enemy_tick_rate = intensity_data.get("enemy_tick_rate", 20.0)
	current_aoi_radius = intensity_data.get("aoi_radius", 2000.0)

	# Emit signals for client-side systems (interpolation adjustment)
	intensity_level_changed.emit(level, level_name)
	tick_rate_changed.emit(current_player_tick_rate, level)
	aoi_radius_changed.emit(current_aoi_radius)

	# Log on client
	LogManager.info("[BATTLE] Intensity: %s (tick: %.0fHz)" % [level_name, current_player_tick_rate], "network")

# ============================================================================
# PUBLIC API - Other systems use these to get current rates
# ============================================================================

func get_player_sync_interval() -> float:
	"""Get current player position sync interval in seconds."""
	return 1.0 / current_player_tick_rate

func get_player_sync_interval_ms() -> int:
	"""Get current player position sync interval in milliseconds."""
	return int(1000.0 / current_player_tick_rate)

func get_enemy_sync_interval() -> float:
	"""Get current enemy position sync interval in seconds."""
	return 1.0 / current_enemy_tick_rate

func get_aoi_radius() -> float:
	"""Get current Area of Interest radius for player sync."""
	return current_aoi_radius

func get_enemy_sync_radius_full() -> float:
	"""Get radius for full-rate enemy sync."""
	return INTENSITY_CONFIG[current_intensity]["enemy_sync_radius_full"]

func get_enemy_sync_radius_reduced() -> float:
	"""Get radius for reduced-rate enemy sync."""
	return INTENSITY_CONFIG[current_intensity]["enemy_sync_radius_reduced"]

func get_intensity_level() -> IntensityLevel:
	"""Get current intensity level."""
	return current_intensity

func get_intensity_name() -> String:
	"""Get current intensity level name."""
	return INTENSITY_CONFIG[current_intensity]["name"]

func is_legendary_battle() -> bool:
	"""Check if we're in a legendary battle (for special effects/announcements)."""
	return current_intensity == IntensityLevel.LEGENDARY

func is_massive_battle() -> bool:
	"""Check if we're in at least a massive battle."""
	return current_intensity >= IntensityLevel.MASSIVE

# ============================================================================
# BATTLE HOTSPOT DETECTION (for future zone sharding)
# ============================================================================

func detect_battle_hotspots(player_positions: Array) -> Array:
	"""
	Detect clusters of players (battle hotspots).
	Returns array of {position: Vector2, player_count: int}

	This is useful for:
	- Spinning up additional zone servers for hot areas
	- Adjusting sync rates per-region instead of globally
	- Analytics on where battles happen
	"""
	var hotspots: Array = []
	var assigned: Dictionary = {}  # player_index -> hotspot_index

	for i in range(player_positions.size()):
		if i in assigned:
			continue

		var pos = player_positions[i]
		var cluster_positions: Array = [pos]
		var cluster_center = pos

		# Find all players within HOTSPOT_RADIUS
		for j in range(i + 1, player_positions.size()):
			if j in assigned:
				continue
			var other_pos = player_positions[j]
			if pos.distance_to(other_pos) <= HOTSPOT_RADIUS:
				cluster_positions.append(other_pos)
				assigned[j] = hotspots.size()

		# Only count as hotspot if enough players
		if cluster_positions.size() >= HOTSPOT_MIN_PLAYERS:
			# Calculate center of cluster
			var center = Vector2.ZERO
			for p in cluster_positions:
				center += p
			center /= cluster_positions.size()

			hotspots.append({
				"position": center,
				"player_count": cluster_positions.size(),
				"radius": HOTSPOT_RADIUS
			})

		assigned[i] = hotspots.size() - 1 if cluster_positions.size() >= HOTSPOT_MIN_PLAYERS else -1

	hotspot_positions = hotspots
	return hotspots

# ============================================================================
# DEBUG / ADMIN
# ============================================================================

func force_intensity(level: IntensityLevel):
	"""Admin command to force a specific intensity level (for testing)."""
	if multiplayer.is_server():
		_set_intensity(level)
		LogManager.info("[ADMIN] Forced intensity to %s" % INTENSITY_CONFIG[level]["name"], "network")

func get_status_report() -> Dictionary:
	"""Get current status for monitoring/debugging."""
	return {
		"intensity_level": current_intensity,
		"intensity_name": INTENSITY_CONFIG[current_intensity]["name"],
		"player_tick_rate_hz": current_player_tick_rate,
		"enemy_tick_rate_hz": current_enemy_tick_rate,
		"aoi_radius": current_aoi_radius,
		"player_count": _network_manager.authenticated_players.size() if _network_manager else 0,
		"hotspots": hotspot_positions.size(),
	}
