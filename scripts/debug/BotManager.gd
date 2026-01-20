extends Node

## BotManager - Server-side stress testing bot system
##
## Spawns lightweight simulated players for stress testing.
## Unlike PlaytestBot (client-side), these bots run directly on the server
## and exercise the same code paths as real networked players.
##
## MCP Commands (via MCPBridge):
##   {"action": "bots_spawn", "count": 50, "behavior": "cluster", "x": 0, "y": 0}
##   {"action": "bots_despawn", "count": 10}  or "all"
##   {"action": "bots_behavior", "behavior": "combat"}
##   {"action": "bots_ramp", "target": 200, "seconds": 60}
##   {"action": "bots_status"}
##   {"action": "bots_metrics"}

signal bot_spawned(bot_id: int)
signal bot_despawned(bot_id: int)
signal metrics_updated(metrics: Dictionary)
signal ramp_complete(final_count: int)

# TCP Control Server (for external control via CLI/scripts)
const CONTROL_PORT = 9051  # Different from MCPBridge (9050)
var control_server := TCPServer.new()
var control_clients: Array[StreamPeerTCP] = []

# Bot storage
var bots: Dictionary = {}  # bot_id -> StressTestBot (invisible stress bots)
var visible_bots: Dictionary = {}  # bot_id -> Node (actual player entities)
var next_bot_id: int = 10000  # Start high to avoid collision with real peer IDs
var next_visible_bot_id: int = 20000  # Different range for visible bots

# Game world reference for spawning visible bots
var game_world: Node = null

# Behavior modes
enum BotBehavior {
	IDLE,       # Just connected, minimal load
	WANDER,     # Random movement, tests position sync
	CLUSTER,    # Move toward a point, tests AOI worst-case
	COMBAT,     # Fight each other, tests damage/state packets
	REINFORCE   # Stream toward a point over time, tests battle scenario
}
var current_behavior: BotBehavior = BotBehavior.IDLE
var cluster_target: Vector2 = Vector2.ZERO
var combat_enabled: bool = false

# Ramping
var ramp_active: bool = false
var ramp_target: int = 0
var ramp_per_second: float = 0.0
var ramp_accumulated: float = 0.0

# Metrics tracking
var metrics_history: Array = []
var metrics_timer: float = 0.0
const METRICS_INTERVAL: float = 1.0
const METRICS_HISTORY_SIZE: int = 60  # Keep 60 seconds of history

# References
var network_manager: Node = null
var spatial_grid: Node = null
var tick_rate_manager: Node = null

# Bot configuration
const BOT_MOVE_SPEED: float = 150.0
const BOT_WANDER_RADIUS: float = 500.0
const BOT_COMBAT_RANGE: float = 80.0
const BOT_SYNC_INTERVAL: float = 0.033  # 30Hz like real players

func _ready():
	print("[BotManager] _ready() called")

	# Get references first
	network_manager = get_node_or_null("/root/NetworkManager")
	spatial_grid = get_node_or_null("/root/SpatialGrid")
	tick_rate_manager = get_node_or_null("/root/DynamicTickRateManager")

	print("[BotManager] Got references: NetworkManager=%s, SpatialGrid=%s" % [network_manager != null, spatial_grid != null])

	# Check if we should run - defer the check since multiplayer may not be ready
	call_deferred("_deferred_init")

	# Find game world once the scene tree is ready
	get_tree().process_frame.connect(_find_game_world, CONNECT_ONE_SHOT)

func _find_game_world():
	# Find the game world node (needed for visible bot spawning)
	# Server scene structure: /root/main/GameWorld
	game_world = get_node_or_null("/root/main/GameWorld")
	if game_world and game_world.has_method("spawn_player"):
		print("[BotManager] Found game_world at /root/main/GameWorld")
		return

	# Fallback: check current scene
	game_world = get_tree().current_scene
	if game_world and game_world.has_method("spawn_player"):
		print("[BotManager] Found game_world at current_scene")
		return

	# Search children of current scene
	if get_tree().current_scene:
		for child in get_tree().current_scene.get_children():
			if child.has_method("spawn_player"):
				game_world = child
				print("[BotManager] Found game_world: %s" % child.name)
				return

	# Search root children
	for child in get_tree().root.get_children():
		if child.has_method("spawn_player"):
			game_world = child
			print("[BotManager] Found game_world in root: %s" % child.name)
			return

	print("[BotManager] Warning: game_world not found (visible bots unavailable)")

func _deferred_init():
	print("[BotManager] _deferred_init() called")
	print("[BotManager] Command line args: %s" % str(OS.get_cmdline_args()))
	print("[BotManager] dedicated_server feature: %s" % OS.has_feature("dedicated_server"))
	print("[BotManager] Server feature: %s" % OS.has_feature("Server"))
	print("[BotManager] _is_server() = %s" % _is_server())

	# Only run on server (check after multiplayer is set up)
	if not _is_server():
		print("[BotManager] Not running on server, disabling")
		set_process(false)
		queue_free()
		return

	# Start TCP control server
	var err = control_server.listen(CONTROL_PORT)
	if err == OK:
		print("[BotManager] Control server listening on port %d" % CONTROL_PORT)
	else:
		print("[BotManager] Failed to start control server: %s" % err)

	print("[BotManager] Initialized - stress testing system ready")

func _is_server() -> bool:
	# Check export features first (most reliable for exported builds)
	if OS.has_feature("dedicated_server") or OS.has_feature("Server"):
		return true
	# Check if NetworkManager says we're the server
	if network_manager and network_manager.has_method("is_server"):
		return network_manager.is_server()
	if network_manager and network_manager.multiplayer and network_manager.multiplayer.get_unique_id() == 1:
		return true
	# Fallback: check command line for server indicators
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg == "--server" or arg == "--headless":
			return true
	# Last resort: check if running headless (no display)
	return DisplayServer.get_name() == "headless"

func _process(delta: float):
	_accept_control_connections()
	_read_control_commands()
	_update_ramp(delta)
	_update_bots(delta)
	_update_visible_bots(delta)
	_update_metrics(delta)

func _accept_control_connections():
	while control_server.is_connection_available():
		var client = control_server.take_connection()
		control_clients.append(client)
		print("[BotManager] Control client connected")

func _read_control_commands():
	for i in range(control_clients.size() - 1, -1, -1):
		var client = control_clients[i]
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			control_clients.remove_at(i)
			continue

		if client.get_available_bytes() > 0:
			var data = client.get_utf8_string(client.get_available_bytes())
			for line in data.split("\n", false):
				var cmd = JSON.parse_string(line)
				if cmd:
					var result = handle_mcp_command(cmd)
					client.put_data((JSON.stringify(result) + "\n").to_utf8_buffer())

# ═══════════════════════════════════════════════════════════════════
# BOT SPAWNING / DESPAWNING
# ═══════════════════════════════════════════════════════════════════

func spawn_bots(count: int, behavior: String = "idle", position: Vector2 = Vector2.ZERO) -> Dictionary:
	"""Spawn multiple stress test bots"""
	var spawned = []
	var behavior_enum = _parse_behavior(behavior)

	for i in range(count):
		var bot_id = next_bot_id
		next_bot_id += 1

		# Randomize spawn position slightly
		var spawn_pos = position + Vector2(
			randf_range(-200, 200),
			randf_range(-200, 200)
		)

		var bot = StressTestBot.new()
		bot.bot_id = bot_id
		bot.bot_name = "StressBot_%d" % bot_id
		bot.position = spawn_pos
		bot.behavior = behavior_enum
		bot.manager = self

		bots[bot_id] = bot
		add_child(bot)

		# Register with SpatialGrid
		if spatial_grid:
			spatial_grid.update_player(bot_id, spawn_pos)

		spawned.append(bot_id)
		bot_spawned.emit(bot_id)

	# Update DynamicTickRateManager
	_notify_player_count_changed()

	print("[BotManager] Spawned %d bots (total: %d)" % [count, bots.size()])
	return {ok = true, spawned = spawned, total = bots.size()}

func despawn_bots(count_or_all) -> Dictionary:
	"""Despawn bots. Pass 'all' or a number."""
	var to_remove: int

	if count_or_all is String and count_or_all == "all":
		to_remove = bots.size()
	else:
		to_remove = min(int(count_or_all), bots.size())

	var removed = []
	var bot_ids = bots.keys()

	for i in range(to_remove):
		if bot_ids.size() == 0:
			break
		var bot_id = bot_ids.pop_back()
		var bot = bots.get(bot_id)

		if bot:
			# Unregister from SpatialGrid
			if spatial_grid:
				spatial_grid.remove_player(bot_id)

			bot.queue_free()
			bots.erase(bot_id)
			removed.append(bot_id)
			bot_despawned.emit(bot_id)

	_notify_player_count_changed()

	print("[BotManager] Despawned %d bots (remaining: %d)" % [removed.size(), bots.size()])
	return {ok = true, removed = removed.size(), remaining = bots.size()}

# ═══════════════════════════════════════════════════════════════════
# VISIBLE BOTS (actual player entities visible to clients)
# ═══════════════════════════════════════════════════════════════════

func spawn_visible_bots(count: int, behavior: String = "wander", position: Vector2 = Vector2.ZERO) -> Dictionary:
	"""Spawn visible bot players that clients can see."""
	if not game_world:
		_find_game_world()
	if not game_world or not game_world.has_method("spawn_player"):
		return {error = "Game world not found or doesn't support spawn_player"}

	var spawned = []
	var behavior_enum = _parse_behavior(behavior)

	# Random appearance options for variety
	var genders = [0, 1]  # 0 = male, 1 = female
	var weapon_types = ["unarmed", "sword", "axe", "bow"]

	for i in range(count):
		var bot_id = next_visible_bot_id
		next_visible_bot_id += 1

		# Randomize spawn position
		var spawn_pos = position
		if spawn_pos == Vector2.ZERO:
			spawn_pos = Vector2(randf_range(-500, 500), randf_range(-500, 500))
		else:
			spawn_pos += Vector2(randf_range(-100, 100), randf_range(-100, 100))

		# Random appearance
		var gender = genders[randi() % genders.size()]
		var weapon = weapon_types[randi() % weapon_types.size()]

		# Pre-register bot data (player reference will be set in deferred callback)
		visible_bots[bot_id] = {
			"player": null,  # Will be set after spawn completes
			"behavior": behavior_enum,
			"target_position": position if behavior_enum == BotBehavior.CLUSTER else Vector2.ZERO,
			"wander_target": spawn_pos,
			"attack_cooldown": 0.0,
			"sync_timer": 0.0
		}

		# Call game_world's spawn_player with our fake bot ID
		game_world.spawn_player(
			bot_id,
			spawn_pos,
			gender,
			weapon,
			"", "", "", "", "", "",  # sprite paths (default)
			"", "", "", "", "", "",  # forged IDs
			"", "", "",  # weapon glow/effect/theme
			false,  # weapon_is_forged
			"",  # weapon_item_id
			"Bot_%d" % bot_id,  # display_name
			false,  # is_guest
			"initiate"  # ashbane_tier
		)

		# Defer finding the player to next frame when it's ready
		call_deferred("_link_visible_bot_player", bot_id)

		spawned.append(bot_id)
		print("[BotManager] Spawning visible bot %d at %s" % [bot_id, spawn_pos])

	_notify_player_count_changed()
	print("[BotManager] Spawning %d visible bots (total: %d)" % [count, visible_bots.size()])
	return {ok = true, spawned = spawned, total = visible_bots.size()}

func _link_visible_bot_player(bot_id: int):
	"""Deferred callback to link the player node after spawn completes."""
	if not visible_bots.has(bot_id):
		return

	var player = game_world.players.get(bot_id) if game_world and "players" in game_world else null
	if player:
		# Set server as multiplayer authority so we can control it
		player.set_multiplayer_authority(1)
		visible_bots[bot_id]["player"] = player
		print("[BotManager] Linked visible bot %d to player node" % bot_id)
	else:
		push_warning("[BotManager] Could not find player for visible bot %d" % bot_id)

func despawn_visible_bots(count_or_all) -> Dictionary:
	"""Despawn visible bots."""
	if not game_world:
		return {error = "Game world not found"}

	var to_remove: int
	if count_or_all is String and count_or_all == "all":
		to_remove = visible_bots.size()
	else:
		to_remove = min(int(count_or_all), visible_bots.size())

	var removed = []
	var bot_ids = visible_bots.keys()

	for i in range(to_remove):
		if bot_ids.size() == 0:
			break
		var bot_id = bot_ids.pop_back()
		var bot_data = visible_bots.get(bot_id)

		if bot_data:
			# Remove player via game_world
			if game_world.has_method("despawn_player"):
				game_world.despawn_player(bot_id)
			elif bot_data.player and is_instance_valid(bot_data.player):
				bot_data.player.queue_free()

			visible_bots.erase(bot_id)
			removed.append(bot_id)

	_notify_player_count_changed()
	print("[BotManager] Despawned %d visible bots (remaining: %d)" % [removed.size(), visible_bots.size()])
	return {ok = true, removed = removed.size(), remaining = visible_bots.size()}

func set_visible_bot_behavior(behavior: String, target_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	"""Set behavior for all visible bots."""
	var behavior_enum = _parse_behavior(behavior)

	for bot_id in visible_bots:
		var bot_data = visible_bots[bot_id]
		bot_data.behavior = behavior_enum
		if behavior_enum == BotBehavior.CLUSTER or behavior_enum == BotBehavior.REINFORCE:
			bot_data.target_position = target_pos

	print("[BotManager] Set visible bot behavior to %s for %d bots" % [behavior, visible_bots.size()])
	return {ok = true, behavior = behavior, bot_count = visible_bots.size()}

func _update_visible_bots(delta: float):
	"""Update AI for visible bots."""
	for bot_id in visible_bots:
		var bot_data = visible_bots[bot_id]
		var player = bot_data.player

		if not player or not is_instance_valid(player):
			continue

		bot_data.attack_cooldown -= delta
		bot_data.sync_timer += delta

		var velocity = Vector2.ZERO

		match bot_data.behavior:
			BotBehavior.IDLE:
				velocity = Vector2.ZERO

			BotBehavior.WANDER:
				# Wander randomly
				if player.global_position.distance_to(bot_data.wander_target) < 30 or bot_data.sync_timer > 3.0:
					bot_data.wander_target = player.global_position + Vector2(
						randf_range(-300, 300),
						randf_range(-300, 300)
					)
					bot_data.sync_timer = 0.0

				var dir = (bot_data.wander_target - player.global_position).normalized()
				velocity = dir * BOT_MOVE_SPEED * 0.5

			BotBehavior.CLUSTER:
				if bot_data.target_position != Vector2.ZERO:
					var dist = player.global_position.distance_to(bot_data.target_position)
					if dist > 50:
						var dir = (bot_data.target_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED
					else:
						velocity = Vector2(randf_range(-20, 20), randf_range(-20, 20))

			BotBehavior.COMBAT:
				# Find nearest enemy to fight
				var nearest_enemy = _find_nearest_enemy(player.global_position)
				if nearest_enemy:
					var dist = player.global_position.distance_to(nearest_enemy.global_position)
					if dist > BOT_COMBAT_RANGE:
						var dir = (nearest_enemy.global_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED
					else:
						velocity = Vector2.ZERO
						if bot_data.attack_cooldown <= 0:
							bot_data.attack_cooldown = 0.5
							_make_bot_attack(player, nearest_enemy)
				else:
					# No enemies, wander
					bot_data.behavior = BotBehavior.WANDER

			BotBehavior.REINFORCE:
				if bot_data.target_position != Vector2.ZERO:
					var dist = player.global_position.distance_to(bot_data.target_position)
					if dist > 100:
						var dir = (bot_data.target_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * randf_range(0.6, 1.0)
					else:
						velocity = Vector2(randf_range(-30, 30), randf_range(-30, 30))

		# Apply movement to player
		if "velocity" in player:
			player.velocity = velocity
		elif player.has_method("set_velocity"):
			player.set_velocity(velocity)

func _find_nearest_enemy(pos: Vector2) -> Node:
	"""Find nearest enemy to position."""
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node = null
	var nearest_dist = 500.0  # Max aggro range

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue

		var dist = pos.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

func _make_bot_attack(player: Node, target: Node):
	"""Make a bot player attack a target."""
	# Face the target
	if "facing_direction" in player:
		var dir = (target.global_position - player.global_position).normalized()
		if abs(dir.x) > abs(dir.y):
			player.facing_direction = "right" if dir.x > 0 else "left"
		else:
			player.facing_direction = "down" if dir.y > 0 else "up"

	# Trigger attack
	if player.has_method("start_attack"):
		player.start_attack()

# ═══════════════════════════════════════════════════════════════════
# BEHAVIOR CONTROL
# ═══════════════════════════════════════════════════════════════════

func set_behavior(behavior: String, target_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	"""Set behavior for all bots"""
	current_behavior = _parse_behavior(behavior)
	cluster_target = target_pos
	combat_enabled = (current_behavior == BotBehavior.COMBAT)

	for bot in bots.values():
		bot.behavior = current_behavior
		if current_behavior == BotBehavior.CLUSTER or current_behavior == BotBehavior.REINFORCE:
			bot.target_position = target_pos

	print("[BotManager] Set behavior to %s for %d bots" % [behavior, bots.size()])
	return {ok = true, behavior = behavior, bot_count = bots.size()}

func _parse_behavior(behavior: String) -> BotBehavior:
	match behavior.to_lower():
		"idle": return BotBehavior.IDLE
		"wander": return BotBehavior.WANDER
		"cluster": return BotBehavior.CLUSTER
		"combat": return BotBehavior.COMBAT
		"reinforce": return BotBehavior.REINFORCE
		_: return BotBehavior.IDLE

# ═══════════════════════════════════════════════════════════════════
# RAMPING
# ═══════════════════════════════════════════════════════════════════

func start_ramp(target_count: int, duration_seconds: float) -> Dictionary:
	"""Gradually ramp bot count to target over duration"""
	if duration_seconds <= 0:
		return spawn_bots(target_count - bots.size())

	ramp_target = target_count
	ramp_per_second = (target_count - bots.size()) / duration_seconds
	ramp_active = true
	ramp_accumulated = 0.0

	print("[BotManager] Starting ramp: %d -> %d over %.0fs (%.1f bots/sec)" % [
		bots.size(), target_count, duration_seconds, ramp_per_second
	])

	return {
		ok = true,
		current = bots.size(),
		target = target_count,
		duration = duration_seconds,
		rate = ramp_per_second
	}

func stop_ramp() -> Dictionary:
	"""Stop active ramp"""
	ramp_active = false
	return {ok = true, final_count = bots.size()}

func _update_ramp(delta: float):
	if not ramp_active:
		return

	ramp_accumulated += abs(ramp_per_second) * delta

	while ramp_accumulated >= 1.0:
		ramp_accumulated -= 1.0

		if ramp_per_second > 0 and bots.size() < ramp_target:
			spawn_bots(1, BotBehavior.keys()[current_behavior].to_lower(), cluster_target)
		elif ramp_per_second < 0 and bots.size() > ramp_target:
			despawn_bots(1)

	# Check if complete
	if (ramp_per_second > 0 and bots.size() >= ramp_target) or \
	   (ramp_per_second < 0 and bots.size() <= ramp_target):
		ramp_active = false
		print("[BotManager] Ramp complete: %d bots" % bots.size())
		ramp_complete.emit(bots.size())

# ═══════════════════════════════════════════════════════════════════
# BOT UPDATES
# ═══════════════════════════════════════════════════════════════════

func _update_bots(delta: float):
	for bot in bots.values():
		bot.update(delta)

func _notify_player_count_changed():
	"""Notify systems about player count change"""
	var total_bots = bots.size() + visible_bots.size()
	if tick_rate_manager and tick_rate_manager.has_method("set_simulated_player_count"):
		# Set simulated player count (invisible + visible bots)
		tick_rate_manager.set_simulated_player_count(total_bots)
		print("[BotManager] Updated simulated player count to %d (invisible: %d, visible: %d)" % [total_bots, bots.size(), visible_bots.size()])

# ═══════════════════════════════════════════════════════════════════
# METRICS
# ═══════════════════════════════════════════════════════════════════

func _update_metrics(delta: float):
	metrics_timer += delta
	if metrics_timer < METRICS_INTERVAL:
		return
	metrics_timer = 0.0

	var metrics = get_current_metrics()
	metrics_history.append(metrics)

	# Trim history
	while metrics_history.size() > METRICS_HISTORY_SIZE:
		metrics_history.pop_front()

	metrics_updated.emit(metrics)

func get_current_metrics() -> Dictionary:
	"""Get current performance metrics"""
	var fps = Engine.get_frames_per_second()
	var physics_fps = Engine.physics_ticks_per_second

	# Get tick rate from DynamicTickRateManager
	var player_tick_rate = 30.0
	var enemy_tick_rate = 20.0
	var aoi_radius = 2000.0
	var intensity_level = 0
	var intensity_name = "Normal"

	if tick_rate_manager:
		if "current_player_tick_rate" in tick_rate_manager:
			player_tick_rate = tick_rate_manager.current_player_tick_rate
		if "current_enemy_tick_rate" in tick_rate_manager:
			enemy_tick_rate = tick_rate_manager.current_enemy_tick_rate
		if "current_aoi_radius" in tick_rate_manager:
			aoi_radius = tick_rate_manager.current_aoi_radius
		if "current_intensity" in tick_rate_manager:
			intensity_level = tick_rate_manager.current_intensity
		if tick_rate_manager.has_method("get_intensity_name"):
			intensity_name = tick_rate_manager.get_intensity_name()

	# Real player count
	var real_players = 0
	if network_manager and "connected_peer_ids" in network_manager:
		real_players = network_manager.connected_peer_ids.size()

	var total_bots = bots.size() + visible_bots.size()
	return {
		timestamp = Time.get_unix_time_from_system(),
		fps = fps,
		physics_fps = physics_fps,
		invisible_bot_count = bots.size(),
		visible_bot_count = visible_bots.size(),
		bot_count = total_bots,
		real_players = real_players,
		total_players = real_players + total_bots,
		player_tick_rate = player_tick_rate,
		enemy_tick_rate = enemy_tick_rate,
		aoi_radius = aoi_radius,
		intensity_level = intensity_level,
		intensity_name = intensity_name,
		behavior = BotBehavior.keys()[current_behavior],
		ramp_active = ramp_active,
		ramp_target = ramp_target if ramp_active else 0,
		memory_mb = OS.get_static_memory_usage() / 1048576.0
	}

func get_status() -> Dictionary:
	"""Get current bot manager status"""
	var metrics = get_current_metrics()

	# Add bot position summary
	var positions = []
	var count = 0
	for bot in bots.values():
		if count < 10:  # Only first 10 for brevity
			positions.append({id = bot.bot_id, x = bot.position.x, y = bot.position.y})
		count += 1

	metrics["sample_positions"] = positions
	metrics["behaviors"] = _get_behavior_breakdown()

	return metrics

func _get_behavior_breakdown() -> Dictionary:
	var breakdown = {}
	for behavior in BotBehavior.keys():
		breakdown[behavior] = 0

	for bot in bots.values():
		var name = BotBehavior.keys()[bot.behavior]
		breakdown[name] = breakdown.get(name, 0) + 1

	return breakdown

func get_metrics_history() -> Array:
	"""Get historical metrics for graphing"""
	return metrics_history

# ═══════════════════════════════════════════════════════════════════
# MCP COMMAND INTERFACE
# ═══════════════════════════════════════════════════════════════════

func handle_mcp_command(cmd: Dictionary) -> Dictionary:
	"""Handle MCP commands for bot control"""
	var action = cmd.get("action", "")

	match action:
		"bots_spawn":
			var count = cmd.get("count", 10)
			var behavior = cmd.get("behavior", "idle")
			var x = cmd.get("x", 0.0)
			var y = cmd.get("y", 0.0)
			return spawn_bots(count, behavior, Vector2(x, y))

		"bots_despawn":
			var count = cmd.get("count", "all")
			return despawn_bots(count)

		"bots_behavior":
			var behavior = cmd.get("behavior", "idle")
			var x = cmd.get("x", 0.0)
			var y = cmd.get("y", 0.0)
			return set_behavior(behavior, Vector2(x, y))

		"bots_ramp":
			var target = cmd.get("target", 100)
			var seconds = cmd.get("seconds", 60.0)
			return start_ramp(target, seconds)

		"bots_stop_ramp":
			return stop_ramp()

		"bots_status":
			return get_status()

		"bots_metrics":
			return {
				current = get_current_metrics(),
				history = metrics_history.slice(-10)  # Last 10 entries
			}

		# Visible bot commands
		"vbots_spawn":
			var count = cmd.get("count", 5)
			var behavior = cmd.get("behavior", "wander")
			var x = cmd.get("x", 0.0)
			var y = cmd.get("y", 0.0)
			return spawn_visible_bots(count, behavior, Vector2(x, y))

		"vbots_despawn":
			var count = cmd.get("count", "all")
			return despawn_visible_bots(count)

		"vbots_behavior":
			var behavior = cmd.get("behavior", "wander")
			var x = cmd.get("x", 0.0)
			var y = cmd.get("y", 0.0)
			return set_visible_bot_behavior(behavior, Vector2(x, y))

		"vbots_status":
			return {
				ok = true,
				visible_bot_count = visible_bots.size(),
				invisible_bot_count = bots.size(),
				total_bots = bots.size() + visible_bots.size(),
				game_world_found = game_world != null
			}

		_:
			return {error = "Unknown bot command: %s" % action}


# ═══════════════════════════════════════════════════════════════════
# STRESS TEST BOT (inner class)
# ═══════════════════════════════════════════════════════════════════

class StressTestBot extends Node:
	var bot_id: int = 0
	var bot_name: String = ""
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var behavior: int = 0  # BotBehavior enum
	var target_position: Vector2 = Vector2.ZERO
	var manager: Node = null

	# Timers
	var sync_timer: float = 0.0
	var behavior_timer: float = 0.0
	var wander_target: Vector2 = Vector2.ZERO

	# Combat (for COMBAT mode)
	var combat_target_id: int = 0
	var attack_cooldown: float = 0.0
	var health: float = 100.0

	const SYNC_INTERVAL: float = 0.033  # 30Hz
	const WANDER_INTERVAL: float = 2.0
	const MOVE_SPEED: float = 150.0
	const COMBAT_RANGE: float = 80.0
	const ATTACK_COOLDOWN: float = 0.5

	func update(delta: float):
		sync_timer += delta
		behavior_timer += delta
		attack_cooldown -= delta

		# Update behavior
		match behavior:
			0:  # IDLE
				velocity = Vector2.ZERO

			1:  # WANDER
				_update_wander(delta)

			2:  # CLUSTER
				_update_cluster(delta)

			3:  # COMBAT
				_update_combat(delta)

			4:  # REINFORCE
				_update_reinforce(delta)

		# Apply movement
		position += velocity * delta

		# Sync position to SpatialGrid
		if sync_timer >= SYNC_INTERVAL:
			sync_timer = 0.0
			_sync_position()

	func _update_wander(delta: float):
		if behavior_timer >= WANDER_INTERVAL or position.distance_to(wander_target) < 20:
			behavior_timer = 0.0
			wander_target = position + Vector2(
				randf_range(-300, 300),
				randf_range(-300, 300)
			)

		var dir = (wander_target - position).normalized()
		velocity = dir * MOVE_SPEED * 0.5

	func _update_cluster(delta: float):
		if target_position == Vector2.ZERO:
			return

		var dist = position.distance_to(target_position)
		if dist > 50:
			var dir = (target_position - position).normalized()
			velocity = dir * MOVE_SPEED
		else:
			# At target, small random movement
			velocity = Vector2(randf_range(-20, 20), randf_range(-20, 20))

	func _update_combat(delta: float):
		# Find nearest other bot to fight
		if not manager:
			return

		var nearest_dist = 999999.0
		var nearest_bot: Node = null

		for other in manager.bots.values():
			if other.bot_id == bot_id:
				continue
			var dist = position.distance_to(other.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_bot = other

		if not nearest_bot:
			return

		if nearest_dist > COMBAT_RANGE:
			# Move toward target
			var dir = (nearest_bot.position - position).normalized()
			velocity = dir * MOVE_SPEED
		else:
			# In range, attack
			velocity = Vector2.ZERO
			if attack_cooldown <= 0:
				attack_cooldown = ATTACK_COOLDOWN
				# Simulate damage (for network load testing)
				nearest_bot.take_damage(10)

	func _update_reinforce(delta: float):
		# Like cluster but with staggered arrival
		if target_position == Vector2.ZERO:
			return

		var dist = position.distance_to(target_position)
		if dist > 100:
			var dir = (target_position - position).normalized()
			# Vary speed for staggered arrival
			var speed_mult = randf_range(0.6, 1.0)
			velocity = dir * MOVE_SPEED * speed_mult
		else:
			# Arrived, switch to combat-like behavior
			velocity = Vector2(randf_range(-30, 30), randf_range(-30, 30))

	func take_damage(amount: float):
		health -= amount
		if health <= 0:
			health = 100  # Respawn instantly for stress test
			# Could track deaths for metrics

	func _sync_position():
		if not manager or not manager.spatial_grid:
			return

		# Update position in SpatialGrid
		manager.spatial_grid.update_player(bot_id, position)
