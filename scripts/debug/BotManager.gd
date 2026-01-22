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
	REINFORCE,  # Stream toward a point over time, tests battle scenario
	PATROL,     # Walk between waypoints in sequence
	FOLLOW      # Follow a real player
}
var current_behavior: BotBehavior = BotBehavior.IDLE
var cluster_target: Vector2 = Vector2.ZERO
var combat_enabled: bool = false

# ═══════════════════════════════════════════════════════════════════════════
# BOT ROLE SYSTEM - RPG class archetypes with appropriate tier 1 gear
# ═══════════════════════════════════════════════════════════════════════════
enum BotRole {
	DPS,      # Damage dealers - light armor, offensive weapons
	TANK,     # Defenders - heavy armor, defensive weapons
	HEALER,   # Healers - cloth armor, staff
	SUPPORT   # Buffers - mixed armor, utility focus
}

# Role distribution weights (total should = 100 for easy percentage)
const ROLE_WEIGHTS = {
	BotRole.DPS: 40,      # 40% DPS
	BotRole.TANK: 25,     # 25% Tanks
	BotRole.HEALER: 20,   # 20% Healers
	BotRole.SUPPORT: 15   # 15% Support
}

# Role-specific name colors (for healthbar display)
const ROLE_COLORS = {
	BotRole.DPS: Color(1.0, 0.3, 0.3, 1.0),      # Red - damage dealers
	BotRole.TANK: Color(0.3, 0.5, 1.0, 1.0),     # Blue - tanks
	BotRole.HEALER: Color(0.3, 1.0, 0.4, 1.0),   # Green - healers
	BotRole.SUPPORT: Color(0.9, 0.7, 0.2, 1.0)   # Gold - support
}

# Role-specific name prefixes
const ROLE_PREFIXES = {
	BotRole.DPS: "DPS",
	BotRole.TANK: "Tank",
	BotRole.HEALER: "Healer",
	BotRole.SUPPORT: "Support"
}

# Role-specific tier 1 loadouts
# Each role has multiple loadout variants for visual diversity
const ROLE_LOADOUTS = {
	BotRole.DPS: [
		# Melee DPS - Sword fighter (light armor for agility)
		{"weapon": "sword", "chest": "rawhide", "legs": "rawhide", "boots": "rawhide", "head": ""},
		# Melee DPS - Axe berserker (minimal armor)
		{"weapon": "axe", "chest": "linen", "legs": "linen", "boots": "", "head": ""},
		# Ranged DPS - Archer (leather for mobility)
		{"weapon": "bow", "chest": "rawhide", "legs": "rawhide", "boots": "rawhide", "head": "rawhide"},
		# Melee DPS - Spear fighter (balanced)
		{"weapon": "spear", "chest": "linen", "legs": "rawhide", "boots": "linen", "head": ""},
	],
	BotRole.TANK: [
		# Heavy Tank - Full plate with sword
		{"weapon": "sword", "chest": "copper_plate", "legs": "copper_plate", "boots": "copper_plate", "head": "copper_plate"},
		# Armored Tank - Plate with axe
		{"weapon": "axe", "chest": "copper_plate", "legs": "copper_plate", "boots": "copper_plate", "head": "copper_plate"},
		# Off-tank - Mixed heavy armor
		{"weapon": "sword", "chest": "copper_plate", "legs": "rawhide", "boots": "copper_plate", "head": "rawhide"},
		# Spear Tank - Reach weapon with armor
		{"weapon": "spear", "chest": "copper_plate", "legs": "copper_plate", "boots": "rawhide", "head": "copper_plate"},
	],
	BotRole.HEALER: [
		# Cloth Healer - Traditional robes
		{"weapon": "staff", "chest": "linen", "legs": "linen", "boots": "linen", "head": ""},
		# Acolyte Healer - White robes
		{"weapon": "staff", "chest": "white_shirt", "legs": "green_pants", "boots": "", "head": ""},
		# Nature Healer - Hide and cloth mix
		{"weapon": "staff", "chest": "linen", "legs": "rawhide", "boots": "", "head": "linen"},
		# Mystic Healer - Full cloth
		{"weapon": "staff", "chest": "linen", "legs": "linen", "boots": "linen", "head": "linen"},
	],
	BotRole.SUPPORT: [
		# Buffer - Light mixed armor
		{"weapon": "staff", "chest": "rawhide", "legs": "linen", "boots": "rawhide", "head": ""},
		# Enchanter - Cloth with accents
		{"weapon": "staff", "chest": "linen", "legs": "rawhide", "boots": "linen", "head": "rawhide"},
		# Bard (unarmed) - Performer attire
		{"weapon": "unarmed", "chest": "white_shirt", "legs": "green_pants", "boots": "linen", "head": ""},
		# Tactician - Light plate support
		{"weapon": "spear", "chest": "linen", "legs": "copper_plate", "boots": "rawhide", "head": "linen"},
	]
}

# ═══════════════════════════════════════════════════════════════════════════
# TEAM SYSTEM - Organized groups of bots that work together
# ═══════════════════════════════════════════════════════════════════════════
enum TeamState {
	FORMING,    # Members moving to rally point
	READY,      # All members at rally point, waiting
	GRINDING,   # Team actively fighting enemies
	RETURNING   # Team returning to rally point after grinding
}

# Team rally points - closer to grinding zones (skeleton spawns)
# Skeletons spawn ~1100 units from campfire (-6000, 0)
const TEAM_RALLY_POINTS = [
	Vector2(-5100, 0),     # Team 1: East (near eastern skeletons at -4900)
	Vector2(-6900, 0),     # Team 2: West (near western skeletons at -7100)
	Vector2(-6000, -900),  # Team 3: North (near northern skeleton at -6000, -1100)
	Vector2(-6000, 900),   # Team 4: South (near southern skeletons at -6000, 1100)
	Vector2(-5100, -200),  # Team 5: East-north
	Vector2(-5100, 200),   # Team 6: East-south
]

# Standard team composition (total 5 members)
const TEAM_COMPOSITION = {
	BotRole.TANK: 1,     # 1 tank to hold aggro
	BotRole.HEALER: 1,   # 1 healer to keep team alive
	BotRole.DPS: 2,      # 2 DPS for damage
	BotRole.SUPPORT: 1   # 1 support for buffs
}

# Formation offsets from rally point (classic MMO formation)
# Tank front, healer back, DPS flanks, support middle
const TEAM_FORMATION = {
	BotRole.TANK: [Vector2(0, -40)],           # Front (1 tank)
	BotRole.HEALER: [Vector2(0, 50)],          # Back center (1 healer)
	BotRole.DPS: [Vector2(-45, 0), Vector2(45, 0)],  # Left and right flanks (2 DPS)
	BotRole.SUPPORT: [Vector2(0, 15)]          # Center-back (1 support)
}

# Grinding zones - areas where teams go to fight enemies
# These should be near enemy spawn areas
# Grinding zones - directly at skeleton spawn locations (campfire at -6000, 0)
# Same as rally points since we want teams to grind where they spawn
const GRINDING_ZONES = [
	Vector2(-4900, 0),     # East - skeletons here
	Vector2(-7100, 0),     # West - skeletons here
	Vector2(-6000, -1100), # North - skeleton here
	Vector2(-6000, 1100),  # South - skeletons here
]

# Grinding session settings
const GRINDING_DURATION: float = 60.0  # Seconds to grind before returning
const GRINDING_RETREAT_HEALTH: float = 0.15  # Return when team avg health below 15%
const TEAM_MOVE_SPEED: float = 100.0  # Speed when moving as a team

# Team storage: team_id -> team data
var teams: Dictionary = {}
var next_team_id: int = 1

func spawn_team(rally_point_index: int = -1) -> Dictionary:
	"""Spawn a balanced team at a rally point.

	Args:
		rally_point_index: Which rally point to use (0-5), or -1 for auto-assign

	Returns:
		Dictionary with team info
	"""
	if not game_world:
		_find_game_world()
	if not game_world or not game_world.has_method("spawn_player"):
		return {error = "Game world not found or doesn't support spawn_player"}

	# Auto-assign rally point if not specified
	if rally_point_index < 0 or rally_point_index >= TEAM_RALLY_POINTS.size():
		rally_point_index = (next_team_id - 1) % TEAM_RALLY_POINTS.size()

	var rally_point = TEAM_RALLY_POINTS[rally_point_index]
	var team_id = next_team_id
	next_team_id += 1

	# Create team data
	var team_data = {
		"id": team_id,
		"state": TeamState.FORMING,
		"rally_point": rally_point,
		"rally_index": rally_point_index,
		"members": [],  # List of bot_ids
		"spawn_time": Time.get_unix_time_from_system()
	}

	var spawned_ids = []

	# Track role spawn counts for formation positioning
	var role_spawn_counts = {}
	for role in TEAM_COMPOSITION:
		role_spawn_counts[role] = 0

	# Spawn bots according to composition
	for role in TEAM_COMPOSITION:
		var count = TEAM_COMPOSITION[role]
		for i in range(count):
			var bot_id = next_visible_bot_id
			next_visible_bot_id += 1

			var loadout = _get_role_loadout(role)

			# Get formation offset for this role instance
			var formation_offsets = TEAM_FORMATION.get(role, [Vector2.ZERO])
			var role_index = role_spawn_counts[role]
			var formation_offset = formation_offsets[role_index % formation_offsets.size()]
			role_spawn_counts[role] += 1

			# Calculate formation position (rally point + formation offset)
			var formation_pos = rally_point + formation_offset

			# Spawn near formation position with tiny scatter for visual variety
			var spawn_pos = formation_pos + Vector2(
				randf_range(-8, 8),
				randf_range(-8, 8)
			)

			# Random gender
			var gender = randi() % 2

			# Loadout details
			var weapon = loadout.get("weapon", "unarmed")
			var chest = loadout.get("chest", "white_shirt")
			var pants = loadout.get("legs", "green_pants")
			var boots = loadout.get("boots", "")
			var head = loadout.get("head", "")

			# Display name with role prefix
			var role_prefix = ROLE_PREFIXES[role]
			var display_name = "%s_%d" % [role_prefix, bot_id]

			# Debug: log loadout being applied
			print("[BotManager] Spawning %s at formation %s: weapon=%s chest=%s" % [
				display_name, formation_offset, weapon, chest
			])

			# Register bot data with team info - target is their formation position
			visible_bots[bot_id] = {
				"player": null,
				"behavior": BotBehavior.CLUSTER,  # Start with cluster to formation position
				"role": role,
				"weapon": weapon,  # Store weapon for combat behavior
				"team_id": team_id,
				"target_position": formation_pos,  # Their specific formation spot
				"formation_offset": formation_offset,  # Store for reference
				"wander_target": spawn_pos,
				"attack_cooldown": 0.0,
				"sync_timer": 0.0,
				"wander_timer": 0.0
			}

			# Spawn the player entity
			game_world.spawn_player.rpc(
				bot_id,
				spawn_pos,
				gender,
				weapon,
				boots,
				pants,
				chest,
				"",     # arms
				"",     # hands
				head,
				"", "", "", "", "", "",  # forged IDs
				"", "", "",              # weapon glow/effect/theme
				false,                   # weapon_is_forged
				"",                      # weapon_item_id
				display_name,
				false,                   # is_guest
				"initiate"               # ashbane_tier
			)

			call_deferred("_link_visible_bot_player", bot_id)
			spawned_ids.append(bot_id)
			team_data.members.append(bot_id)

	# Store team
	teams[team_id] = team_data

	_notify_player_count_changed()

	# Role breakdown for logging
	var role_counts = {}
	for role in TEAM_COMPOSITION:
		role_counts[ROLE_PREFIXES[role].to_lower()] = TEAM_COMPOSITION[role]

	print("[BotManager] Spawned Team %d at rally point %d (%s) with %d members" % [
		team_id, rally_point_index, rally_point, spawned_ids.size()
	])

	return {
		ok = true,
		team_id = team_id,
		rally_point_index = rally_point_index,
		rally_point = {"x": rally_point.x, "y": rally_point.y},
		members = spawned_ids,
		composition = role_counts
	}

func spawn_teams(count: int) -> Dictionary:
	"""Spawn multiple teams at different rally points."""
	var results = []
	var total_bots = 0

	for i in range(count):
		var result = spawn_team(i % TEAM_RALLY_POINTS.size())
		if result.has("ok") and result.ok:
			results.append(result)
			total_bots += result.members.size()
		else:
			results.append(result)

	print("[BotManager] Spawned %d teams with %d total bots" % [results.size(), total_bots])

	return {
		ok = true,
		teams_spawned = results.size(),
		total_bots = total_bots,
		teams = results
	}

func despawn_team(team_id: int) -> Dictionary:
	"""Despawn all members of a team."""
	if not teams.has(team_id):
		return {error = "Team %d not found" % team_id}

	var team_data = teams[team_id]
	var removed = []

	for bot_id in team_data.members:
		if visible_bots.has(bot_id):
			var bot_data = visible_bots[bot_id]
			if bot_data.player and is_instance_valid(bot_data.player):
				if game_world and game_world.has_method("despawn_player"):
					game_world.despawn_player(bot_id)
				else:
					bot_data.player.queue_free()
			visible_bots.erase(bot_id)
			removed.append(bot_id)

	teams.erase(team_id)
	_notify_player_count_changed()

	print("[BotManager] Despawned Team %d (%d members)" % [team_id, removed.size()])

	return {ok = true, team_id = team_id, removed = removed.size()}

func despawn_all_teams() -> Dictionary:
	"""Despawn all teams."""
	var team_ids = teams.keys().duplicate()
	var total_removed = 0

	for team_id in team_ids:
		var result = despawn_team(team_id)
		if result.has("removed"):
			total_removed += result.removed

	return {ok = true, teams_removed = team_ids.size(), bots_removed = total_removed}

func get_team_status(team_id: int) -> Dictionary:
	"""Get status of a specific team."""
	if not teams.has(team_id):
		return {error = "Team %d not found" % team_id}

	var team_data = teams[team_id]
	var members_info = []
	var members_at_rally = 0

	for bot_id in team_data.members:
		if visible_bots.has(bot_id):
			var bot_data = visible_bots[bot_id]
			var player = bot_data.get("player")
			var at_rally = false
			var pos = Vector2.ZERO

			if player and is_instance_valid(player):
				pos = player.global_position
				at_rally = pos.distance_to(team_data.rally_point) < 50
				if at_rally:
					members_at_rally += 1

			members_info.append({
				"bot_id": bot_id,
				"role": ROLE_PREFIXES.get(bot_data.get("role"), "Unknown"),
				"position": {"x": pos.x, "y": pos.y},
				"at_rally": at_rally
			})

	return {
		ok = true,
		team_id = team_id,
		state = TeamState.keys()[team_data.state],
		rally_point = {"x": team_data.rally_point.x, "y": team_data.rally_point.y},
		members_at_rally = members_at_rally,
		total_members = team_data.members.size(),
		ready = members_at_rally == team_data.members.size(),
		members = members_info
	}

func list_teams() -> Dictionary:
	"""List all active teams."""
	var team_list = []

	for team_id in teams:
		var status = get_team_status(team_id)
		if status.has("ok"):
			team_list.append({
				"team_id": team_id,
				"state": status.state,
				"members": status.total_members,
				"at_rally": status.members_at_rally,
				"ready": status.ready
			})

	return {
		ok = true,
		team_count = teams.size(),
		teams = team_list
	}

# ═══════════════════════════════════════════════════════════════════════════
# GRINDING SESSION MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func _update_teams(delta: float) -> void:
	"""Update all teams - handle state transitions and coordination."""
	for team_id in teams:
		var team_data = teams[team_id]
		_update_team_state(team_id, team_data, delta)

func _update_team_state(team_id: int, team_data: Dictionary, delta: float) -> void:
	"""Update a single team's state machine."""
	match team_data.state:
		TeamState.FORMING:
			# Check if all members are at their formation positions
			var all_ready = true
			for bot_id in team_data.members:
				if visible_bots.has(bot_id):
					var bot_data = visible_bots[bot_id]
					var player = bot_data.get("player")
					if player and is_instance_valid(player):
						var dist = player.global_position.distance_to(bot_data.target_position)
						if dist > 50:  # Not yet at formation position
							all_ready = false
							break

			if all_ready:
				team_data.state = TeamState.READY
				print("[BotManager] Team %d is READY (all members in formation)" % team_id)

		TeamState.READY:
			# Team is ready, waiting for grinding command
			# Could add auto-grind logic here later
			pass

		TeamState.GRINDING:
			# Update grinding timer
			var grind_time = team_data.get("grind_timer", 0.0) + delta
			team_data["grind_timer"] = grind_time

			# Check for retreat conditions
			var avg_health = _get_team_avg_health(team_id)
			var should_retreat = false

			if grind_time >= GRINDING_DURATION:
				should_retreat = true
				print("[BotManager] Team %d returning (grind time complete)" % team_id)
			elif avg_health < GRINDING_RETREAT_HEALTH:
				should_retreat = true
				print("[BotManager] Team %d retreating (low health: %.0f%%)" % [team_id, avg_health * 100])

			if should_retreat:
				_start_team_return(team_id)

		TeamState.RETURNING:
			# Check if all members are back at rally
			var all_home = true
			for bot_id in team_data.members:
				if visible_bots.has(bot_id):
					var bot_data = visible_bots[bot_id]
					var player = bot_data.get("player")
					if player and is_instance_valid(player):
						var dist = player.global_position.distance_to(bot_data.target_position)
						if dist > 50:
							all_home = false
							break

			if all_home:
				team_data.state = TeamState.READY
				print("[BotManager] Team %d returned to rally and is READY" % team_id)

func _get_team_avg_health(team_id: int) -> float:
	"""Get average health percentage of team members."""
	if not teams.has(team_id):
		return 1.0

	var team_data = teams[team_id]
	var total_health = 0.0
	var count = 0

	for bot_id in team_data.members:
		if visible_bots.has(bot_id):
			var bot_data = visible_bots[bot_id]
			var player = bot_data.get("player")
			if player and is_instance_valid(player):
				var current = player.get("current_health") if "current_health" in player else 100.0
				var maximum = player.get("max_health") if "max_health" in player else 100.0
				if maximum > 0:
					total_health += current / maximum
					count += 1

	return total_health / count if count > 0 else 1.0

func start_grinding_session(team_id: int, zone_index: int = -1) -> Dictionary:
	"""Start a grinding session for a team.

	Args:
		team_id: The team to send grinding
		zone_index: Which grinding zone (0-3), or -1 for auto-select
	"""
	if not teams.has(team_id):
		return {error = "Team %d not found" % team_id}

	var team_data = teams[team_id]

	if team_data.state != TeamState.READY:
		return {error = "Team %d is not ready (state: %s)" % [team_id, TeamState.keys()[team_data.state]]}

	# Select grinding zone
	if zone_index < 0 or zone_index >= GRINDING_ZONES.size():
		zone_index = randi() % GRINDING_ZONES.size()

	var grind_target = GRINDING_ZONES[zone_index]

	# Update team state
	team_data.state = TeamState.GRINDING
	team_data["grind_target"] = grind_target
	team_data["grind_zone"] = zone_index
	team_data["grind_timer"] = 0.0

	# Update all team members to move toward grind zone (maintaining formation)
	for bot_id in team_data.members:
		if visible_bots.has(bot_id):
			var bot_data = visible_bots[bot_id]
			var formation_offset = bot_data.get("formation_offset", Vector2.ZERO)
			bot_data["target_position"] = grind_target + formation_offset
			bot_data["behavior"] = BotBehavior.COMBAT  # Switch to combat mode

	print("[BotManager] Team %d started grinding at zone %d (%s)" % [team_id, zone_index, grind_target])

	return {
		ok = true,
		team_id = team_id,
		zone_index = zone_index,
		target = {"x": grind_target.x, "y": grind_target.y}
	}

func _start_team_return(team_id: int) -> void:
	"""Internal: Start team return to rally point."""
	if not teams.has(team_id):
		return

	var team_data = teams[team_id]
	team_data.state = TeamState.RETURNING

	# Update all members to return to rally formation
	for bot_id in team_data.members:
		if visible_bots.has(bot_id):
			var bot_data = visible_bots[bot_id]
			var formation_offset = bot_data.get("formation_offset", Vector2.ZERO)
			bot_data["target_position"] = team_data.rally_point + formation_offset
			bot_data["behavior"] = BotBehavior.CLUSTER  # Switch back to cluster (move to position)

func stop_grinding_session(team_id: int) -> Dictionary:
	"""Force a team to stop grinding and return to rally."""
	if not teams.has(team_id):
		return {error = "Team %d not found" % team_id}

	var team_data = teams[team_id]

	if team_data.state != TeamState.GRINDING:
		return {error = "Team %d is not grinding" % team_id}

	_start_team_return(team_id)

	return {ok = true, team_id = team_id, message = "Team returning to rally"}

func start_all_grinding() -> Dictionary:
	"""Start grinding sessions for all ready teams."""
	var started = []

	for team_id in teams:
		var team_data = teams[team_id]
		if team_data.state == TeamState.READY:
			var result = start_grinding_session(team_id)
			if result.has("ok") and result.ok:
				started.append(team_id)

	return {ok = true, teams_started = started, count = started.size()}

func stop_all_grinding() -> Dictionary:
	"""Stop all grinding sessions and return teams to rally."""
	var stopped = []

	for team_id in teams:
		var team_data = teams[team_id]
		if team_data.state == TeamState.GRINDING:
			_start_team_return(team_id)
			stopped.append(team_id)

	return {ok = true, teams_stopped = stopped, count = stopped.size()}

# Patrol waypoints (shared across bots, or per-bot)
var patrol_waypoints: Array[Vector2] = []
var default_patrol_route: Array[Vector2] = [
	Vector2(-400, -400),
	Vector2(400, -400),
	Vector2(400, 400),
	Vector2(-400, 400)
]  # Square patrol by default

# Follow target (peer ID of player to follow)
var follow_target_peer_id: int = 0

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
	_update_teams(delta)  # Team state machine updates
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

func _select_weighted_role() -> BotRole:
	"""Select a role based on configured weights."""
	var total_weight = 0
	for weight in ROLE_WEIGHTS.values():
		total_weight += weight

	var roll = randi() % total_weight
	var cumulative = 0

	for role in ROLE_WEIGHTS:
		cumulative += ROLE_WEIGHTS[role]
		if roll < cumulative:
			return role

	return BotRole.DPS  # Fallback

func _get_role_loadout(role: BotRole) -> Dictionary:
	"""Get a random loadout for the specified role."""
	var loadouts = ROLE_LOADOUTS[role]
	return loadouts[randi() % loadouts.size()]

func spawn_visible_bots_with_roles(count: int, behavior: String = "wander", position: Vector2 = Vector2.ZERO) -> Dictionary:
	"""Spawn visible bot players with balanced RPG roles."""
	if not game_world:
		_find_game_world()
	if not game_world or not game_world.has_method("spawn_player"):
		return {error = "Game world not found or doesn't support spawn_player"}

	var spawned = []
	var behavior_enum = _parse_behavior(behavior)
	var role_counts = {BotRole.DPS: 0, BotRole.TANK: 0, BotRole.HEALER: 0, BotRole.SUPPORT: 0}

	for i in range(count):
		var bot_id = next_visible_bot_id
		next_visible_bot_id += 1

		# Select role and loadout
		var role = _select_weighted_role()
		var loadout = _get_role_loadout(role)
		role_counts[role] += 1

		# Randomize spawn position
		var spawn_pos = position
		if spawn_pos == Vector2.ZERO:
			spawn_pos = Vector2(randf_range(-500, 500), randf_range(-500, 500))
		else:
			spawn_pos += Vector2(randf_range(-100, 100), randf_range(-100, 100))

		# Random gender
		var gender = randi() % 2

		# Get loadout details
		var weapon = loadout.get("weapon", "unarmed")
		var chest = loadout.get("chest", "white_shirt")
		var pants = loadout.get("legs", "green_pants")
		var boots = loadout.get("boots", "")
		var head = loadout.get("head", "")

		# Create display name with role prefix
		var role_prefix = ROLE_PREFIXES[role]
		var display_name = "%s_%d" % [role_prefix, bot_id]

		# Pre-register bot data with role info
		visible_bots[bot_id] = {
			"player": null,
			"behavior": behavior_enum,
			"role": role,
			"weapon": weapon,  # Store weapon for combat behavior
			"target_position": position if behavior_enum == BotBehavior.CLUSTER else Vector2.ZERO,
			"wander_target": spawn_pos,
			"attack_cooldown": 0.0,
			"sync_timer": 0.0,
			"wander_timer": 0.0
		}

		# Spawn with role-appropriate gear
		game_world.spawn_player.rpc(
			bot_id,
			spawn_pos,
			gender,
			weapon,
			boots,   # feet_sprite
			pants,   # legs_sprite
			chest,   # chest_sprite
			"",      # arms_sprite
			"",      # hands_sprite
			head,    # head_sprite
			"", "", "", "", "", "",  # forged IDs
			"", "", "",              # weapon glow/effect/theme
			false,                   # weapon_is_forged
			"",                      # weapon_item_id
			display_name,            # display_name
			false,                   # is_guest
			"initiate"               # ashbane_tier
		)

		call_deferred("_link_visible_bot_player", bot_id)
		spawned.append(bot_id)

	_notify_player_count_changed()

	# Log role distribution
	print("[BotManager] Spawned %d role-based bots: DPS=%d Tank=%d Healer=%d Support=%d" % [
		count, role_counts[BotRole.DPS], role_counts[BotRole.TANK],
		role_counts[BotRole.HEALER], role_counts[BotRole.SUPPORT]
	])

	return {
		ok = true,
		spawned = spawned,
		total = visible_bots.size(),
		roles = {
			"dps": role_counts[BotRole.DPS],
			"tank": role_counts[BotRole.TANK],
			"healer": role_counts[BotRole.HEALER],
			"support": role_counts[BotRole.SUPPORT]
		}
	}

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
	var weapon_types = ["unarmed", "sword", "axe", "bow", "spear", "staff"]
	var chest_options = ["white_shirt", "copper_plate", "linen", "rawhide"]
	var pants_options = ["green_pants", "copper_plate", "linen", "rawhide"]
	var boots_options = ["", "copper_plate", "linen", "rawhide"]  # "" = barefoot
	var head_options = ["", "copper_plate", "linen", "rawhide"]  # "" = no helmet

	for i in range(count):
		var bot_id = next_visible_bot_id
		next_visible_bot_id += 1

		# Randomize spawn position
		var spawn_pos = position
		if spawn_pos == Vector2.ZERO:
			spawn_pos = Vector2(randf_range(-500, 500), randf_range(-500, 500))
		else:
			spawn_pos += Vector2(randf_range(-100, 100), randf_range(-100, 100))

		# Random appearance - full variety
		var gender = genders[randi() % genders.size()]
		var weapon = weapon_types[randi() % weapon_types.size()]
		var chest = chest_options[randi() % chest_options.size()]
		var pants = pants_options[randi() % pants_options.size()]
		var boots = boots_options[randi() % boots_options.size()]
		var head = head_options[randi() % head_options.size()]

		# Pre-register bot data (player reference will be set in deferred callback)
		visible_bots[bot_id] = {
			"player": null,  # Will be set after spawn completes
			"behavior": behavior_enum,
			"target_position": position if behavior_enum == BotBehavior.CLUSTER else Vector2.ZERO,
			"wander_target": spawn_pos,
			"attack_cooldown": 0.0,
			"sync_timer": 0.0,
			"wander_timer": 0.0  # Separate timer for wander behavior
		}

		# Call game_world's spawn_player via RPC to broadcast to all clients
		game_world.spawn_player.rpc(
			bot_id,
			spawn_pos,
			gender,
			weapon,
			boots,  # feet_sprite
			pants,  # legs_sprite
			chest,  # chest_sprite
			"",     # arms_sprite
			"",     # hands_sprite
			head,   # head_sprite
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

	var bot_data = visible_bots[bot_id]
	var player = game_world.players.get(bot_id) if game_world and "players" in game_world else null
	if player:
		# Set server as multiplayer authority so we can control it
		player.set_multiplayer_authority(1)
		bot_data["player"] = player

		# Set role-appropriate health values
		var role = bot_data.get("role", null)
		var bot_max_health = 100.0  # Default
		if role != null:
			match role:
				BotRole.DPS:
					bot_max_health = 80.0    # Glass cannon
				BotRole.TANK:
					bot_max_health = 150.0   # Durable
				BotRole.HEALER:
					bot_max_health = 70.0    # Squishy
				BotRole.SUPPORT:
					bot_max_health = 90.0    # Moderate

		if "max_health" in player:
			player.max_health = bot_max_health
		if "current_health" in player:
			player.current_health = bot_max_health

		# Setup health bar display with role-based colors
		var health_bar = player.get_node_or_null("HealthBar")
		if health_bar:
			health_bar.visible = true

			# Use role from above for name and color
			var display_name: String
			var name_color: Color

			if role != null:
				# Role-based name and color
				var role_prefix = ROLE_PREFIXES.get(role, "Bot")
				display_name = "%s_%d" % [role_prefix, bot_id]
				name_color = ROLE_COLORS.get(role, Color(1.0, 0.6, 0.2, 1.0))
			else:
				# Default for non-role bots
				display_name = "Bot_%d" % bot_id
				name_color = Color(1.0, 0.6, 0.2, 1.0)  # Orange

			if health_bar.has_method("set_player_name"):
				health_bar.set_player_name(display_name)
			if health_bar.has_method("set_name_color"):
				health_bar.set_name_color(name_color)
			if health_bar.has_method("update_health"):
				health_bar.update_health(bot_max_health, bot_max_health)

		var role_str = BotRole.keys()[bot_data.get("role", BotRole.DPS)] if bot_data.has("role") else "none"
		print("[BotManager] Linked bot %d (role=%s) to player node" % [bot_id, role_str])
	else:
		push_warning("[BotManager] Could not find player for visible bot %d" % bot_id)

func _despawn_dead_bot(bot_id: int):
	"""Remove a bot that has died."""
	if not visible_bots.has(bot_id):
		return

	print("[BotManager] Despawning dead bot %d" % bot_id)

	var bot_data = visible_bots[bot_id]
	if bot_data.player and is_instance_valid(bot_data.player):
		# Remove via game_world
		if game_world and game_world.has_method("despawn_player"):
			game_world.despawn_player(bot_id)
		else:
			bot_data.player.queue_free()

	visible_bots.erase(bot_id)
	_notify_player_count_changed()

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

var _debug_update_counter: int = 0

func _update_visible_bots(delta: float):
	"""Update AI for visible bots."""
	_debug_update_counter += 1
	# Log once per second (assuming ~60fps)
	if _debug_update_counter >= 60:
		_debug_update_counter = 0
		print("[BotManager] _update_visible_bots: %d visible bots" % visible_bots.size())

	for bot_id in visible_bots:
		var bot_data = visible_bots[bot_id]
		var player = bot_data.player

		if not player or not is_instance_valid(player):
			# Debug: try to re-link if player is missing
			if not bot_data.get("link_warned", false):
				print("[BotManager] Bot %d has no valid player reference, attempting re-link" % bot_id)
				_link_visible_bot_player(bot_id)
				bot_data["link_warned"] = true
			continue

		bot_data.attack_cooldown -= delta
		bot_data.sync_timer += delta
		bot_data.wander_timer += delta

		var velocity = Vector2.ZERO
		var animation = "idle_down"

		# Track position jumps for debugging teleport issue
		var last_pos = bot_data.get("last_server_pos", player.global_position)
		var jump_dist = player.global_position.distance_to(last_pos)
		if jump_dist > 100:  # Log any jump > 100 units
			print("[BotManager] JUMP DETECTED: bot=%d jumped %.0f units from %s to %s" % [bot_id, jump_dist, last_pos, player.global_position])
		bot_data["last_server_pos"] = player.global_position

		# Debug log behavior once per bot
		if not bot_data.get("behavior_logged", false):
			print("[BotManager] Bot %d behavior=%d player_pos=%s" % [bot_id, bot_data.behavior, player.global_position])
			bot_data["behavior_logged"] = true

		match bot_data.behavior:
			BotBehavior.IDLE:
				velocity = Vector2.ZERO

			BotBehavior.WANDER:
				# Wander randomly - pick new target when reaching destination or after timeout
				var dist_to_target = player.global_position.distance_to(bot_data.wander_target)
				var time_limit = bot_data.get("wander_time_limit", 5.0)

				if dist_to_target < 50 or bot_data.wander_timer > time_limit:
					# Pick a new target within wander radius of current position
					var wander_radius = 200.0
					bot_data.wander_target = player.global_position + Vector2(
						randf_range(-wander_radius, wander_radius),
						randf_range(-wander_radius, wander_radius)
					)
					bot_data.wander_timer = 0.0
					# Randomize time limit for natural feel (4-8 seconds)
					bot_data["wander_time_limit"] = randf_range(4.0, 8.0)
					# Maybe pause briefly (20% chance)
					bot_data["wander_pause"] = randf() < 0.2
					bot_data["wander_pause_time"] = randf_range(0.5, 1.5)

				# Handle pause behavior
				if bot_data.get("wander_pause", false):
					bot_data["wander_pause_time"] = bot_data.get("wander_pause_time", 0) - delta
					if bot_data["wander_pause_time"] <= 0:
						bot_data["wander_pause"] = false
					velocity = Vector2.ZERO
				else:
					var dir = (bot_data.wander_target - player.global_position).normalized()
					# Vary speed slightly per bot for natural movement
					var speed_mult = bot_data.get("speed_mult", randf_range(0.4, 0.6))
					if not bot_data.has("speed_mult"):
						bot_data["speed_mult"] = speed_mult
					velocity = dir * BOT_MOVE_SPEED * speed_mult

			BotBehavior.CLUSTER:
				if bot_data.target_position != Vector2.ZERO:
					var dist = player.global_position.distance_to(bot_data.target_position)
					if dist > 80:
						# Move toward cluster point
						var dir = (bot_data.target_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * 0.6
					elif dist > 30:
						# Slow approach to final position
						var dir = (bot_data.target_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * 0.2
					else:
						# At cluster point - stand still with rare small shifts
						var idle_timer = bot_data.get("cluster_idle_timer", 0.0) + delta
						bot_data["cluster_idle_timer"] = idle_timer
						if idle_timer > randf_range(3.0, 6.0):  # Shift every 3-6 seconds
							bot_data["cluster_idle_timer"] = 0.0
							velocity = Vector2(randf_range(-10, 10), randf_range(-10, 10))
						else:
							velocity = Vector2.ZERO  # Stand still

			BotBehavior.COMBAT:
				var role = bot_data.get("role", null)
				var weapon = bot_data.get("weapon", "unarmed")
				var is_ranged = weapon == "bow" or weapon == "crossbow"
				var is_healer = role == BotRole.HEALER

				# Debug: Log combat state every 2 seconds
				var combat_log_timer = bot_data.get("combat_log_timer", 0.0) + delta
				bot_data["combat_log_timer"] = combat_log_timer
				if combat_log_timer > 2.0:
					bot_data["combat_log_timer"] = 0.0
					print("[BotManager] ⚔️ Bot %d COMBAT: role=%s weapon=%s ranged=%s healer=%s cooldown=%.2f pos=%s" % [
						bot_id, role, weapon, is_ranged, is_healer, bot_data.attack_cooldown, player.global_position])

				# Healers prioritize healing hurt teammates - STAY AT FORMATION
				if is_healer:
					var formation_pos = bot_data.get("target_position", Vector2.ZERO)
					var dist_to_formation = player.global_position.distance_to(formation_pos)
					var heal_range = 200.0  # Increased heal range so healer can reach team

					# First: Stay at or return to formation position
					if dist_to_formation > 30:
						var dir = (formation_pos - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * 0.7
					else:
						# At formation - look for hurt teammates to heal
						var hurt_teammate = _find_hurt_teammate(bot_id, player.global_position)
						if hurt_teammate:
							var dist = player.global_position.distance_to(hurt_teammate.global_position)
							if dist <= heal_range:
								velocity = Vector2.ZERO
								if bot_data.attack_cooldown <= 0:
									bot_data.attack_cooldown = 1.5  # Heal cooldown
									_make_bot_heal(player, hurt_teammate, bot_data)
							else:
								# Teammate out of range - stay at formation, small idle movement
								velocity = Vector2(randf_range(-5, 5), randf_range(-5, 5))
						else:
							# No one to heal - idle at formation
							velocity = Vector2(randf_range(-5, 5), randf_range(-5, 5))
				else:
					# Combat roles: find enemies to attack
					var nearest_enemy = _find_nearest_enemy(player.global_position)
					var attack_range = 200.0 if is_ranged else BOT_COMBAT_RANGE  # Bow has longer range

					if nearest_enemy:
						var dist = player.global_position.distance_to(nearest_enemy.global_position)
						# Debug: Log enemy found and attack conditions
						if combat_log_timer < 0.1:  # Log right after reset
							print("[BotManager] 🎯 Bot %d found %s at dist=%.0f (range=%.0f) cooldown=%.2f" % [
								bot_id, nearest_enemy.name, dist, attack_range, bot_data.attack_cooldown])

						if is_ranged:
							# RANGED: Stay at formation position, attack enemies in range
							var formation_pos = bot_data.get("target_position", Vector2.ZERO)
							var dist_to_formation = player.global_position.distance_to(formation_pos)

							if dist_to_formation > 30:
								# Move back to formation
								var dir = (formation_pos - player.global_position).normalized()
								velocity = dir * BOT_MOVE_SPEED * 0.7
								if combat_log_timer < 0.1:
									print("[BotManager] 🏹 Bot %d (ranged) returning to formation (dist=%.0f)" % [bot_id, dist_to_formation])
							elif dist <= attack_range:
								# In formation and enemy in range - attack!
								velocity = Vector2.ZERO
								if bot_data.attack_cooldown <= 0:
									print("[BotManager] 🏹 Bot %d SHOOTING %s!" % [bot_id, nearest_enemy.name])
									bot_data.attack_cooldown = 0.8
									_make_bot_attack(player, nearest_enemy, bot_data)
								elif combat_log_timer < 0.1:
									print("[BotManager] 🏹 Bot %d waiting to shoot (cooldown=%.2f)" % [bot_id, bot_data.attack_cooldown])
							else:
								# In formation but enemy out of range - hold position
								velocity = Vector2(randf_range(-5, 5), randf_range(-5, 5))
								if combat_log_timer < 0.1:
									print("[BotManager] 🏹 Bot %d holding (enemy at dist=%.0f > range=%.0f)" % [bot_id, dist, attack_range])
						else:
							# MELEE: Chase enemies
							if dist > attack_range:
								var dir = (nearest_enemy.global_position - player.global_position).normalized()
								velocity = dir * BOT_MOVE_SPEED
								if combat_log_timer < 0.1:
									print("[BotManager] 🏃 Bot %d CHASING (dist=%.0f > range=%.0f)" % [bot_id, dist, attack_range])
							else:
								velocity = Vector2.ZERO
								if bot_data.attack_cooldown <= 0:
									print("[BotManager] ⚔️ Bot %d ATTACKING %s!" % [bot_id, nearest_enemy.name])
									bot_data.attack_cooldown = 0.5
									_make_bot_attack(player, nearest_enemy, bot_data)
								elif combat_log_timer < 0.1:
									print("[BotManager] ⏳ Bot %d waiting (cooldown=%.2f)" % [bot_id, bot_data.attack_cooldown])
					else:
						# No enemies nearby - move toward target position (grind zone)
						var target = bot_data.get("target_position", Vector2.ZERO)
						if target != Vector2.ZERO:
							var dist_to_target = player.global_position.distance_to(target)
							if dist_to_target > 50:
								var dir = (target - player.global_position).normalized()
								velocity = dir * BOT_MOVE_SPEED
							else:
								velocity = Vector2(randf_range(-10, 10), randf_range(-10, 10))
						else:
							velocity = Vector2.ZERO

			BotBehavior.REINFORCE:
				if bot_data.target_position != Vector2.ZERO:
					var dist = player.global_position.distance_to(bot_data.target_position)
					if dist > 100:
						var dir = (bot_data.target_position - player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * randf_range(0.6, 1.0)
					else:
						velocity = Vector2(randf_range(-30, 30), randf_range(-30, 30))

			BotBehavior.PATROL:
				# Walk between waypoints in sequence
				var waypoints = bot_data.get("patrol_waypoints", patrol_waypoints if patrol_waypoints.size() > 0 else default_patrol_route)
				if waypoints.size() == 0:
					velocity = Vector2.ZERO
				else:
					var waypoint_idx = bot_data.get("patrol_index", 0)
					var target_waypoint = waypoints[waypoint_idx]
					var dist_to_waypoint = player.global_position.distance_to(target_waypoint)

					if dist_to_waypoint < 30:
						# Reached waypoint, move to next
						waypoint_idx = (waypoint_idx + 1) % waypoints.size()
						bot_data["patrol_index"] = waypoint_idx
						# Brief pause at waypoint (optional)
						bot_data["patrol_pause"] = randf() < 0.3  # 30% chance to pause
						bot_data["patrol_pause_time"] = randf_range(0.5, 1.5)

					# Handle pause
					if bot_data.get("patrol_pause", false):
						bot_data["patrol_pause_time"] = bot_data.get("patrol_pause_time", 0) - delta
						if bot_data["patrol_pause_time"] <= 0:
							bot_data["patrol_pause"] = false
						velocity = Vector2.ZERO
					else:
						var dir = (target_waypoint - player.global_position).normalized()
						var speed_mult = bot_data.get("speed_mult", randf_range(0.5, 0.7))
						if not bot_data.has("speed_mult"):
							bot_data["speed_mult"] = speed_mult
						velocity = dir * BOT_MOVE_SPEED * speed_mult

			BotBehavior.FOLLOW:
				# Follow a real player
				var target_peer = bot_data.get("follow_target", follow_target_peer_id)
				var target_player: Node = null

				# Find the target player
				if target_peer > 0 and game_world and "players" in game_world:
					target_player = game_world.players.get(target_peer)

				# Fallback: follow nearest real player
				if not target_player:
					target_player = _find_nearest_real_player(player.global_position)

				if target_player and is_instance_valid(target_player):
					var dist = player.global_position.distance_to(target_player.global_position)
					var follow_distance = bot_data.get("follow_distance", randf_range(80, 150))
					if not bot_data.has("follow_distance"):
						bot_data["follow_distance"] = follow_distance

					if dist > follow_distance + 30:
						# Move toward player
						var dir = (target_player.global_position - player.global_position).normalized()
						# Speed based on distance (faster when further away)
						var speed_mult = clampf(dist / 300.0, 0.5, 1.2)
						velocity = dir * BOT_MOVE_SPEED * speed_mult
					elif dist < follow_distance - 20:
						# Too close, back up a bit
						var dir = (player.global_position - target_player.global_position).normalized()
						velocity = dir * BOT_MOVE_SPEED * 0.3
					else:
						# At good distance, slight wander
						velocity = Vector2(randf_range(-15, 15), randf_range(-15, 15))
				else:
					# No player to follow, wander instead
					velocity = Vector2(randf_range(-30, 30), randf_range(-30, 30))

		# Check if bot is dead (is_dead property or low health)
		var bot_is_dead = false
		if "is_dead" in player:
			bot_is_dead = player.is_dead
		elif "current_health" in player and player.current_health <= 0:
			bot_is_dead = true

		if bot_is_dead:
			# Bot died, despawn it
			if not bot_data.get("death_handled", false):
				bot_data["death_handled"] = true
				print("[BotManager] Bot %d died (is_dead=%s), will despawn" % [bot_id, bot_is_dead])
				call_deferred("_despawn_dead_bot", bot_id)
			continue

		# Move bot directly (server-side)
		var character_sprite = player.get_node_or_null("CharacterSprite")

		if velocity.length() > 1:  # Moving (threshold to avoid jitter)
			var new_pos = player.global_position + velocity * delta
			player.global_position = new_pos

			# Determine animation based on movement direction (LPC-style: north/south/east/west)
			if abs(velocity.x) > abs(velocity.y):
				animation = "walk_east" if velocity.x > 0 else "walk_west"
			else:
				animation = "walk_south" if velocity.y > 0 else "walk_north"

			# Play walk animation on bot
			if character_sprite and character_sprite.has_method("play_lpc_animation"):
				var parts = animation.split("_")
				if parts.size() >= 2:
					character_sprite.play_lpc_animation(parts[0], parts[1])
		else:
			# Standing still - play idle animation
			# Get last direction from bot_data or default to south
			var last_dir = bot_data.get("last_direction", "south")
			animation = "idle_" + last_dir

			# Play idle animation (only update if not already idle)
			if not bot_data.get("is_idle", false):
				bot_data["is_idle"] = true
				if character_sprite and character_sprite.has_method("play_lpc_animation"):
					character_sprite.play_lpc_animation("idle", last_dir)

		# Track last movement direction for idle facing
		if velocity.length() > 1:
			bot_data["is_idle"] = false
			if abs(velocity.x) > abs(velocity.y):
				bot_data["last_direction"] = "east" if velocity.x > 0 else "west"
			else:
				bot_data["last_direction"] = "south" if velocity.y > 0 else "north"

		# Sync position to clients using dynamic tick rate from DynamicTickRateManager
		var sync_rate = 20.0  # Default 20Hz
		if tick_rate_manager and "current_player_tick_rate" in tick_rate_manager:
			sync_rate = tick_rate_manager.current_player_tick_rate
		var sync_interval = 1.0 / sync_rate if sync_rate > 0 else 0.05

		if bot_data.sync_timer >= sync_interval:
			bot_data.sync_timer = 0.0
			# Debug: log periodically (roughly 1Hz)
			if not bot_data.has("log_counter"):
				bot_data["log_counter"] = 0
			bot_data["log_counter"] += 1
			if bot_data["log_counter"] >= int(sync_rate):
				bot_data["log_counter"] = 0
			_broadcast_bot_position(bot_id, player.global_position, animation)
		elif player.has_method("set_velocity"):
			player.set_velocity(velocity)

var _broadcast_debug_counter: int = 0

func _broadcast_bot_position(bot_id: int, pos: Vector2, animation: String):
	"""Broadcast bot position to all connected clients."""
	if not game_world:
		return

	# Update SpatialGrid for AOI queries
	if spatial_grid:
		spatial_grid.update_player(bot_id, pos)

	# Get real connected client peer IDs (not bot IDs)
	# Bot IDs are in range 20000-29999, real peer IDs are large random numbers
	var real_peer_ids = []
	var all_peer_ids = []

	# Try multiplayer.get_peers() first (most reliable)
	var mp = get_tree().get_multiplayer()
	if mp and mp.has_multiplayer_peer():
		all_peer_ids = mp.get_peers()
		for pid in all_peer_ids:
			if pid < 20000 or pid >= 30000:  # Real peers (not in bot range 20000-29999)
				real_peer_ids.append(pid)
	# Fallback to connected_players
	elif network_manager and "connected_players" in network_manager:
		all_peer_ids = network_manager.connected_players.keys()
		for pid in all_peer_ids:
			if pid < 20000 or pid >= 30000:
				real_peer_ids.append(pid)

	# Debug: log peer info periodically
	_broadcast_debug_counter += 1
	if _broadcast_debug_counter >= 50:
		_broadcast_debug_counter = 0
		print("[BotManager] PEERS: all=%s real=%s" % [all_peer_ids, real_peer_ids])

	if real_peer_ids.is_empty():
		# No real clients to broadcast to
		return

	# Bot health defaults (full health)
	var health = 100
	var max_health = 100
	var dashing = false

	# Log when we're actually broadcasting (with position for debugging teleport issue)
	if _broadcast_debug_counter == 0:  # Just reset, so this is our periodic log
		print("[BotManager] BROADCAST: bot=%d pos=%s to peers=%s" % [bot_id, pos, real_peer_ids])

	# Use game_world's _receive_player_position RPC for position sync
	# Server (peer 1) is explicitly allowed to relay positions for any player
	var has_rpc = game_world.has_method("_receive_player_position")
	if _broadcast_debug_counter == 0:
		print("[BotManager] RPC CHECK: has_method=%s game_world=%s" % [has_rpc, game_world.name if game_world else "null"])

	if has_rpc:
		# Broadcast to all real peers using RPC
		for peer_id in real_peer_ids:
			if peer_id == 1:  # Skip server
				continue
			game_world._receive_player_position.rpc_id(peer_id, bot_id, pos, animation, health, false)
	else:
		# Try calling the method directly as fallback (it might be a Callable)
		if _broadcast_debug_counter == 0:
			print("[BotManager] Trying direct call to _receive_player_position")
		for peer_id in real_peer_ids:
			if peer_id == 1:
				continue
			game_world.call("_receive_player_position", bot_id, pos, animation, health, false)

func _find_nearest_enemy(pos: Vector2) -> Node:
	"""Find nearest enemy to position."""
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node = null
	var nearest_dist = 800.0  # Max aggro range (increased for grinding)

	if enemies.size() == 0:
		print("[BotManager] ⚠️ No enemies in 'enemies' group!")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		# Skip training dummy - it's for player practice, not bot targets
		if enemy.is_in_group("training_dummy"):
			continue

		var dist = pos.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	if nearest:
		print("[BotManager] 🎯 Found enemy %s at dist %.0f from (%.0f, %.0f)" % [nearest.name, nearest_dist, pos.x, pos.y])

	return nearest

func _find_nearest_real_player(pos: Vector2) -> Node:
	"""Find nearest real player (not a bot) to position."""
	if not game_world or not "players" in game_world:
		return null

	var nearest: Node = null
	var nearest_dist = 2000.0  # Max follow range

	for peer_id in game_world.players:
		# Skip bots (IDs 20000-29999)
		if peer_id >= 20000 and peer_id < 30000:
			continue

		var player = game_world.players[peer_id]
		if not is_instance_valid(player):
			continue

		var dist = pos.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = player

	return nearest

func _find_hurt_teammate(healer_bot_id: int, pos: Vector2) -> Node:
	"""Find a hurt teammate in the same team that needs healing."""
	# Get healer's team
	if not visible_bots.has(healer_bot_id):
		return null
	var healer_data = visible_bots[healer_bot_id]
	var team_id = healer_data.get("team_id", -1)

	if team_id < 0 or not teams.has(team_id):
		return null

	var team_data = teams[team_id]
	var most_hurt: Node = null
	var lowest_health_pct = 0.9  # Only heal if below 90% health

	for bot_id in team_data.members:
		if bot_id == healer_bot_id:  # Don't heal self
			continue
		if not visible_bots.has(bot_id):
			continue

		var teammate_data = visible_bots[bot_id]
		var teammate_player = teammate_data.get("player")
		if not teammate_player or not is_instance_valid(teammate_player):
			continue

		# Check if teammate is hurt
		if "current_health" in teammate_player and "max_health" in teammate_player:
			var health_pct = teammate_player.current_health / teammate_player.max_health
			if health_pct < lowest_health_pct:
				# Check range (healers have limited range)
				var dist = pos.distance_to(teammate_player.global_position)
				if dist < 300:  # Max heal target range
					lowest_health_pct = health_pct
					most_hurt = teammate_player

	return most_hurt

func _make_bot_attack(player: Node, target: Node, bot_data: Dictionary = {}):
	"""Make a bot player attack a target."""
	if not is_instance_valid(target):
		return

	# Get weapon type from bot_data
	var weapon = bot_data.get("weapon", "unarmed")
	var is_ranged = weapon == "bow" or weapon == "crossbow"

	# Calculate direction to target
	var dir = (target.global_position - player.global_position).normalized()
	var lpc_direction = "south"
	if abs(dir.x) > abs(dir.y):
		lpc_direction = "east" if dir.x > 0 else "west"
	else:
		lpc_direction = "south" if dir.y > 0 else "north"

	# Choose animation based on weapon type
	var attack_anim = "shoot" if is_ranged else "slash"

	# Play attack animation on bot
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation(attack_anim, lpc_direction)

	# Deal damage to target (base damage + some variance)
	var base_damage = 15.0 if not is_ranged else 12.0  # Ranged does slightly less per hit
	var damage = base_damage * randf_range(0.8, 1.2)
	var is_crit = randf() < 0.1  # 10% crit chance
	if is_crit:
		damage *= 2.0

	if target.has_method("take_damage"):
		var old_health = target.current_health if "current_health" in target else -1
		target.take_damage(damage, is_crit, false)
		var new_health = target.current_health if "current_health" in target else -1
		print("[BotManager] 💥 Bot attacked %s: damage=%.1f old_hp=%.1f new_hp=%.1f" % [target.name, damage, old_health, new_health])

	# Broadcast attack animation to clients
	if game_world:
		var bot_id = player.name.get_slice("_", 1).to_int()
		_broadcast_bot_position(bot_id, player.global_position, attack_anim + "_" + lpc_direction)

func _make_bot_heal(player: Node, target: Node, bot_data: Dictionary = {}):
	"""Make a healer bot heal a teammate."""
	if not is_instance_valid(target):
		return

	# Calculate direction to target
	var dir = (target.global_position - player.global_position).normalized()
	var lpc_direction = "south"
	if abs(dir.x) > abs(dir.y):
		lpc_direction = "east" if dir.x > 0 else "west"
	else:
		lpc_direction = "south" if dir.y > 0 else "north"

	# Play staff cast animation (use thrust for healing staff)
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if character_sprite and character_sprite.has_method("play_lpc_animation"):
		character_sprite.play_lpc_animation("thrust", lpc_direction)

	# Heal the target
	var heal_amount = 20.0 * randf_range(0.9, 1.1)

	# Apply healing
	if "current_health" in target and "max_health" in target:
		target.current_health = min(target.current_health + heal_amount, target.max_health)
		# Update healthbar if present
		var health_bar = target.get_node_or_null("HealthBar")
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(target.current_health, target.max_health)

	# Broadcast heal animation to clients
	if game_world:
		var bot_id = player.name.get_slice("_", 1).to_int()
		_broadcast_bot_position(bot_id, player.global_position, "thrust_" + lpc_direction)

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
		"patrol": return BotBehavior.PATROL
		"follow": return BotBehavior.FOLLOW
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
	# Count enemies in the world
	var enemy_count = get_tree().get_nodes_in_group("enemies").size()

	# Get connected peer count more reliably
	var mp = get_tree().get_multiplayer()
	if mp and mp.has_multiplayer_peer():
		var peers = mp.get_peers()
		for pid in peers:
			if pid < 20000 or pid >= 30000:  # Real peers only
				real_players += 1

	return {
		timestamp = Time.get_unix_time_from_system(),
		fps = fps,
		physics_fps = physics_fps,
		invisible_bot_count = bots.size(),
		visible_bot_count = visible_bots.size(),
		bot_count = total_bots,
		real_players = real_players,
		total_players = real_players + total_bots,
		enemy_count = enemy_count,
		player_tick_rate = player_tick_rate,
		enemy_tick_rate = enemy_tick_rate,
		aoi_radius = aoi_radius,
		intensity_level = intensity_level,
		intensity_name = intensity_name,
		behavior = BotBehavior.keys()[current_behavior],
		ramp_active = ramp_active,
		ramp_target = ramp_target if ramp_active else 0,
		memory_mb = OS.get_static_memory_usage() / 1048576.0,
		process_time_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
		physics_time_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000
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

		"vbots_spawn_roles":
			# Spawn bots with balanced RPG roles (DPS/Tank/Healer/Support)
			var count = cmd.get("count", 10)
			var behavior = cmd.get("behavior", "wander")
			var x = cmd.get("x", 0.0)
			var y = cmd.get("y", 0.0)
			return spawn_visible_bots_with_roles(count, behavior, Vector2(x, y))

		"vbots_roles_info":
			# Get info about the role system
			return {
				ok = true,
				roles = ["DPS", "TANK", "HEALER", "SUPPORT"],
				weights = {
					"dps": ROLE_WEIGHTS[BotRole.DPS],
					"tank": ROLE_WEIGHTS[BotRole.TANK],
					"healer": ROLE_WEIGHTS[BotRole.HEALER],
					"support": ROLE_WEIGHTS[BotRole.SUPPORT]
				},
				colors = {
					"dps": "red (damage dealers)",
					"tank": "blue (defenders)",
					"healer": "green (healers)",
					"support": "gold (buffers)"
				}
			}

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

		"vbots_patrol":
			# Set patrol waypoints: {"action": "vbots_patrol", "waypoints": [[x1,y1], [x2,y2], ...]}
			var waypoints_raw = cmd.get("waypoints", [])
			var waypoints: Array[Vector2] = []
			for wp in waypoints_raw:
				if wp is Array and wp.size() >= 2:
					waypoints.append(Vector2(wp[0], wp[1]))
			if waypoints.size() > 0:
				patrol_waypoints = waypoints
			else:
				patrol_waypoints = default_patrol_route
			# Set behavior to patrol
			return set_visible_bot_behavior("patrol")

		"vbots_follow":
			# Set bots to follow a player: {"action": "vbots_follow", "target": peer_id}
			# target = 0 means follow nearest real player
			var target_id = cmd.get("target", 0)
			follow_target_peer_id = target_id
			# Update all bots with the follow target
			for bot_id in visible_bots:
				visible_bots[bot_id]["follow_target"] = target_id
			return set_visible_bot_behavior("follow")

		"vbots_list_players":
			# List real players that bots can follow
			var players = []
			if game_world and "players" in game_world:
				for peer_id in game_world.players:
					if peer_id >= 20000 and peer_id < 30000:
						continue  # Skip bots
					var p = game_world.players[peer_id]
					if is_instance_valid(p):
						players.append({
							"peer_id": peer_id,
							"position": {"x": p.global_position.x, "y": p.global_position.y}
						})
			return {ok = true, players = players}

		# ═══════════════════════════════════════════════════════════════
		# TEAM COMMANDS
		# ═══════════════════════════════════════════════════════════════
		"team_spawn":
			# Spawn a single team: {"action": "team_spawn", "rally_point": 0}
			var rally_idx = cmd.get("rally_point", -1)
			return spawn_team(rally_idx)

		"teams_spawn":
			# Spawn multiple teams: {"action": "teams_spawn", "count": 3}
			var count = cmd.get("count", 1)
			return spawn_teams(count)

		"team_despawn":
			# Despawn a specific team: {"action": "team_despawn", "team_id": 1}
			var team_id = cmd.get("team_id", 0)
			return despawn_team(team_id)

		"teams_despawn_all":
			# Despawn all teams
			return despawn_all_teams()

		"team_status":
			# Get status of a team: {"action": "team_status", "team_id": 1}
			var team_id = cmd.get("team_id", 0)
			return get_team_status(team_id)

		"teams_list":
			# List all teams
			return list_teams()

		"teams_info":
			# Get info about team system configuration
			return {
				ok = true,
				max_teams = TEAM_RALLY_POINTS.size(),
				team_size = TEAM_COMPOSITION.values().reduce(func(a, b): return a + b, 0),
				composition = {
					"tank": TEAM_COMPOSITION[BotRole.TANK],
					"healer": TEAM_COMPOSITION[BotRole.HEALER],
					"dps": TEAM_COMPOSITION[BotRole.DPS],
					"support": TEAM_COMPOSITION[BotRole.SUPPORT]
				},
				rally_points = TEAM_RALLY_POINTS.map(func(p): return {"x": p.x, "y": p.y}),
				grinding_zones = GRINDING_ZONES.map(func(p): return {"x": p.x, "y": p.y}),
				grinding_duration = GRINDING_DURATION
			}

		# ═══════════════════════════════════════════════════════════════
		# GRINDING SESSION COMMANDS
		# ═══════════════════════════════════════════════════════════════
		"grind_start":
			# Start grinding for a team: {"action": "grind_start", "team_id": 1, "zone": 0}
			var team_id = cmd.get("team_id", 0)
			var zone = cmd.get("zone", -1)
			return start_grinding_session(team_id, zone)

		"grind_stop":
			# Stop grinding for a team: {"action": "grind_stop", "team_id": 1}
			var team_id = cmd.get("team_id", 0)
			return stop_grinding_session(team_id)

		"grind_start_all":
			# Start grinding for all ready teams
			return start_all_grinding()

		"grind_stop_all":
			# Stop all grinding sessions
			return stop_all_grinding()

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
