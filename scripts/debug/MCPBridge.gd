extends Node

## MCPBridge - Experimental AI control interface
##
## USAGE: Add to autoload as "MCPBridge" to enable
## Only active in debug builds, listens on port 9050
##
## Commands (JSON over TCP):
##
## CONTROL:
##   {"action": "take_control"}           - Take AI control of the player
##   {"action": "release_control"}        - Release control back to human
##
## MOVEMENT:
##   {"action": "move", "x": -1..1, "y": -1..1}  - Directional move (like WASD)
##   {"action": "move_to", "x": 1000, "y": 500}  - Move to world position
##   {"action": "stop"}                          - Stop all movement and facing
##
## FACING (controls attack direction):
##   {"action": "face", "x": 1000, "y": 500}     - Face a world position
##
## COMBAT:
##   {"action": "attack"}                        - Attack in current facing direction
##   {"action": "attack", "target_x": X, "target_y": Y}  - Face target & attack
##   {"action": "attack_target", "id": 12345}    - Face enemy by ID & attack
##   {"action": "auto_combat"}                   - Auto-target nearest enemy
##   {"action": "stop_combat"}                   - Stop auto-combat
##   {"action": "dodge"}                         - Dodge roll
##
## STATE QUERIES:
##   {"action": "get_state"}                     - Player position, HP, facing
##   {"action": "get_nearby_enemies", "radius": 500}  - Returns enemies with IDs
##   {"action": "get_nearby_items", "radius": 300}
##   {"action": "get_weakpoints"}                - Get active weakpoints on enemies
##   {"action": "click_weakpoint", "id": 12345}  - Click a weakpoint by ID
##   {"action": "get_inventory"}
##   {"action": "get_quests"}
##   {"action": "get_npcs", "radius": 500}
##
## OTHER:
##   {"action": "teleport", "x": 0, "y": 0}
##   {"action": "move_to_npc", "name": "Wanderer"}
##   {"action": "interact"}
##   {"action": "screenshot"}
##   {"action": "ping"}
##   {"action": "wait", "ms": 1000}
##
## MENU AUTOMATION:
##   {"action": "click_play_guest"}    - Click "Play as Guest" on main menu
##   {"action": "click_enter_world"}   - Click "Enter World" on Armory
##   {"action": "get_menu_state"}      - Get current menu/scene state
##
## CAMPFIRE/HEALING:
##   {"action": "find_campfire", "radius": 500}  - Find nearest campfire
##   {"action": "goto_campfire"}                 - Walk to nearest campfire for healing
##
## FORGE ITEMS:
##   {"action": "get_forge_items", "type": "shield"}  - Get forge items by type

const PORT = 9050
const BehaviorTreeAIScript = preload("res://scripts/debug/BehaviorTreeAI.gd")
var server := TCPServer.new()
var clients: Array[StreamPeerTCP] = []

var ai_controlled := false
var player: Node2D = null
var _move_target := Vector2.ZERO
var _is_pathing := false

# Facing direction state
var _face_target := Vector2.ZERO  # World position to face
var _is_facing := false  # Whether we have a face target

# Auto-combat state
var _auto_combat := false
var _combat_target: Node2D = null
const COMBAT_RANGE := 60.0
const ATTACK_COOLDOWN := 0.4
var _attack_timer := 0.0

# Campfire/healing state
var _campfire_target: Node2D = null
var _is_healing := false  # True when at campfire healing
const HEAL_RETREAT_THRESHOLD := 0.75  # Retreat at 75% HP (earlier to avoid death)
const HEAL_RESUME_THRESHOLD := 0.95  # Resume combat at 95% HP

# Looting state
var _loot_target: Node2D = null
var _is_looting := false
const LOOT_PICKUP_RANGE := 30.0

# Post-kill loot timing
var _post_kill_loot_timer := 0.0
const POST_KILL_LOOT_DELAY := 1.0  # Pause after kill to loot (was 0.5, increased for better looting)
var _is_looting_pause := false  # True when pausing to loot after a kill

# Corpse tracking for reliable looting
var _pending_corpse_position := Vector2.ZERO  # Position where enemy died
var _pending_corpse_timer := 0.0  # Time spent waiting for corpse to appear
const CORPSE_WAIT_TIME := 0.5  # Max time to wait for corpse transition
const CORPSE_LOOT_RANGE := 80.0  # Must be this close to loot corpse
var _moving_to_corpse := false  # True when walking to corpse location

# Death tracking - return to corpse for gear
var _last_death_position := Vector2.ZERO
var _had_gear_on_death := false
var _death_time := 0

# Aggro/threat detection
const AGGRO_DETECTION_RADIUS := 250.0  # Check for active threats this close
const SAFE_LOOT_RADIUS := 180.0  # Only loot if no enemies this close (increased for more looting)

# Obstacle avoidance / stuck detection
var _last_position := Vector2.ZERO
var _stuck_counter := 0
var _avoidance_direction := 0  # -1 = left/up, 1 = right/down, 0 = none
var _avoidance_timer := 0.0
const STUCK_THRESHOLD := 3  # Frames of no movement to consider stuck
const AVOIDANCE_DURATION := 0.4  # Time to move in avoidance direction

# Threat awareness during pathing
const THREAT_DETECTION_RANGE := 150.0  # Detect enemies within this range
const THREAT_RESPONSE_RANGE := 80.0  # Engage if enemies this close

# Human-like looting state machine
enum LootState { NONE, WALKING_TO_CORPSE, WAITING_FOR_UI, LOOTING, CLOSING }
var _human_loot_state := LootState.NONE
var _human_loot_target: Node2D = null  # Current corpse we're looting
var _human_loot_timer := 0.0
const HUMAN_LOOT_WALK_RANGE := 60.0  # How close to walk before pressing F
const HUMAN_LOOT_UI_WAIT := 0.3  # Wait for LootUI to open
const HUMAN_LOOT_CLOSE_WAIT := 0.2  # Wait after taking all

# Loot-aware combat mode (pauses after each kill to loot)
var _loot_aware_combat := false

# Behavior Tree AI system - runs at 60fps for reactive gameplay
var behavior_tree: Node = null  # BehaviorTreeAI instance
var _bt_last_status: Dictionary = {}

# BotManager for stress testing (server-side)
var bot_manager: Node = null

func _ready():
	# Only run in debug builds
	if not OS.is_debug_build():
		set_process(false)
		return

	var err = server.listen(PORT)
	if err == OK:
		print("[MCPBridge] AI control server listening on port %d" % PORT)
	else:
		print("[MCPBridge] Failed to start server: %s" % err)
	
	# Initialize Behavior Tree AI
	behavior_tree = BehaviorTreeAIScript.new()
	behavior_tree.name = "BehaviorTreeAI"
	add_child(behavior_tree)
	behavior_tree.setup(self)
	print("[MCPBridge] Behavior Tree AI initialized")

	# Get BotManager reference (only exists on server)
	bot_manager = get_node_or_null("/root/BotManager")

func _process(delta):
	_accept_connections()
	_read_commands()
	_check_hp_emergency()  # ALWAYS check HP - retreat if too low
	_check_immediate_threats()  # ALWAYS check for attacks on us
	_update_pathing(delta)
	_update_human_loot(delta)  # Human-like looting state machine
	_update_auto_combat(delta)
	_update_behavior_tree(delta)  # Behavior Tree AI tick

func _update_behavior_tree(delta: float) -> void:
	"""Tick the Behavior Tree AI if enabled"""
	if behavior_tree and behavior_tree.bt_enabled:
		_bt_last_status = behavior_tree.tick(delta)

func _check_hp_emergency():
	"""Emergency HP check - retreat to campfire if too low, regardless of current activity"""
	if not ai_controlled:
		return

	player = _find_player()
	if not player:
		return

	# Already heading to campfire
	if _is_healing:
		return

	var hp_percent = _get_player_hp_percent()
	if hp_percent < HEAL_RETREAT_THRESHOLD:
		print("[MCPBridge] EMERGENCY! HP at %.0f%% - retreating to campfire!" % (hp_percent * 100))
		# Stop EVERYTHING
		_auto_combat = false
		_is_looting_pause = false
		_moving_to_corpse = false
		_pending_corpse_position = Vector2.ZERO
		_release_inputs()

		# Find campfire with VERY large radius - always find it!
		var campfire_result = _find_campfire(10000.0)  # 10000 unit radius - covers most of the world
		if campfire_result.has("campfires") and campfire_result.campfires.size() > 0:
			var cf = campfire_result.campfires[0]
			_campfire_target = instance_from_id(cf.id)
			_move_target = Vector2(cf.x, cf.y)
			_is_pathing = true
			_is_healing = true  # Only set healing if we found a campfire
			print("[MCPBridge] Heading to campfire at %.0f, %.0f (dist: %.0f)" % [cf.x, cf.y, cf.dist])
		else:
			# No campfire found - just stop fighting and wait/kite
			print("[MCPBridge] WARNING: No campfire found! Stopping combat to avoid death.")
			_is_healing = false  # Can't heal, but stop fighting

func _check_immediate_threats():
	"""Check if we're being attacked and react immediately"""
	if not ai_controlled:
		return

	player = _find_player()
	if not player:
		return

	# Check for enemies very close that might be attacking us
	var pos = player.global_position
	var immediate_threat: Node2D = null
	var threat_dist := 999999.0

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip Training Dummies - they're not real threats
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		if _get_enemy_hp(e) <= 0:
			continue

		var d = e.global_position.distance_to(pos)

		# Check if this enemy is targeting us (very close = probably attacking)
		if d < 100.0:  # Very close threat
			var is_targeting := false
			if "current_target" in e and e.current_target == player:
				is_targeting = true
			elif "target" in e and e.target == player:
				is_targeting = true
			elif "aggro_target" in e and e.aggro_target == player:
				is_targeting = true

			# If enemy is close AND targeting us, that's immediate danger
			if is_targeting or d < 60.0:
				if d < threat_dist:
					threat_dist = d
					immediate_threat = e

	# If there's an immediate threat and we're NOT already in combat, engage!
	if immediate_threat and not _auto_combat and not _is_healing:
		print("[MCPBridge] IMMEDIATE THREAT! Enemy at %.0f range - engaging!" % threat_dist)
		_combat_target = immediate_threat
		_auto_combat = true
		_is_pathing = false
		_release_inputs()

func _physics_process(_delta):
	# Run facing update in physics_process to override player's mouse-based facing
	_update_facing()

func _accept_connections():
	while server.is_connection_available():
		var client = server.take_connection()
		clients.append(client)
		print("[MCPBridge] Client connected")

func _read_commands():
	for i in range(clients.size() - 1, -1, -1):
		var client = clients[i]
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(i)
			continue

		if client.get_available_bytes() > 0:
			var data = client.get_utf8_string(client.get_available_bytes())
			for line in data.split("\n", false):
				var cmd = JSON.parse_string(line)
				if cmd:
					var result = _handle_command(cmd)
					client.put_data((JSON.stringify(result) + "\n").to_utf8_buffer())

func _handle_command(cmd: Dictionary) -> Dictionary:
	match cmd.get("action", ""):
		"take_control":
			ai_controlled = true
			player = _find_player()
			# Enable AI facing override on player
			if player and "ai_facing_override" in player:
				player.ai_facing_override = true
			return {ok = true, has_player = player != null}

		"release_control":
			ai_controlled = false
			# Disable AI facing override on player
			if player and "ai_facing_override" in player:
				player.ai_facing_override = false
			_release_inputs()
			return {ok = true}

		"move":
			return _cmd_move(cmd.get("x", 0.0), cmd.get("y", 0.0))

		"move_to":
			return _cmd_move_to(Vector2(cmd.get("x", 0.0), cmd.get("y", 0.0)))

		"stop":
			_is_pathing = false
			_is_facing = false
			_release_inputs()
			return {ok = true}

		"face":
			return _cmd_face(Vector2(cmd.get("x", 0.0), cmd.get("y", 0.0)))

		"attack":
			# Optional: face target before attacking
			var target_x = cmd.get("target_x", null)
			var target_y = cmd.get("target_y", null)
			if target_x != null and target_y != null:
				_set_face_target(Vector2(target_x, target_y))
			return _cmd_attack()

		"attack_target":
			# Attack a specific enemy by instance ID
			return _cmd_attack_target(cmd.get("id", 0))

		"dodge":
			return _cmd_dodge()

		"interact":
			return _cmd_interact()

		"get_state":
			return _get_state()

		"get_nearby_enemies":
			return _get_nearby_enemies(cmd.get("radius", 500.0))

		"get_nearby_items":
			return _get_nearby_items(cmd.get("radius", 300.0))

		"get_weakpoints":
			return _get_weakpoints()

		"click_weakpoint":
			return _cmd_click_weakpoint(cmd.get("id", 0))

		"teleport":
			return _cmd_teleport(Vector2(cmd.get("x", 0.0), cmd.get("y", 0.0)))

		"screenshot":
			return _cmd_screenshot()

		"ping":
			return {pong = true, time = Time.get_ticks_msec()}

		"get_inventory":
			return _get_inventory()

		"get_quests":
			return _get_quests()

		"accept_quest":
			return _cmd_accept_quest(cmd.get("quest_id", ""))

		"turn_in_quest":
			return _cmd_turn_in_quest(cmd.get("quest_id", ""))

		"quest_progress":
			return _get_quest_progress()

		"loot_items":
			return _cmd_loot_items(cmd.get("radius", 100.0))

		"get_shop":
			return _get_shop_inventory()

		"buy_item":
			return _cmd_buy_item(cmd.get("item_id", ""), cmd.get("item_type", "weapon"))

		"equip_item":
			return _cmd_equip_item(cmd.get("slot", -1), cmd.get("item_id", ""))

		"equip_best":
			return _cmd_equip_best_gear()

		"give_gold":
			return _cmd_give_gold(cmd.get("amount", 100))

		"get_npcs":
			return _get_nearby_npcs(cmd.get("radius", 500.0))

		"move_to_npc":
			return _cmd_move_to_npc(cmd.get("name", ""))

		"auto_combat":
			return _cmd_auto_combat()

		"stop_combat":
			_auto_combat = false
			_combat_target = null
			_moving_to_corpse = false
			_pending_corpse_position = Vector2.ZERO
			_is_looting_pause = false
			return {ok = true}

		"wait":
			# Client-side wait, just acknowledge
			return {ok = true, ms = cmd.get("ms", 0)}

		# Menu automation
		"click_play_guest":
			return _cmd_click_play_guest()

		"click_enter_world":
			return _cmd_click_enter_world()

		"get_menu_state":
			return _get_menu_state()

		# Campfire/healing
		"find_campfire":
			return _find_campfire(cmd.get("radius", 500.0))

		"goto_campfire":
			return _cmd_goto_campfire()

		"fuel_campfire":
			return _cmd_fuel_campfire(cmd.get("amount", 1))

		# Forge items
		"get_forge_items":
			return _get_forge_items(cmd.get("type", ""))

		# Debug: Get nearby corpses
		"get_corpses":
			return _get_nearby_corpses(cmd.get("radius", 300.0))

		# Manual loot command
		"loot_all":
			return _cmd_loot_all(cmd.get("radius", 150.0))

		# Return to death location
		"return_to_corpse":
			return _cmd_return_to_corpse()

		# Get aggro/threat status
		"get_threats":
			return _get_threat_status()

		# Skip tutorial
		"skip_tutorial":
			return _cmd_skip_tutorial()

		# Close bug report indicator
		"close_bug_report":
			return _cmd_close_bug_report()

		# TACTICAL - Full situational awareness
		"tactical":
			return _get_tactical_status()

		# Smart engage - pull single enemy
		"engage":
			return _cmd_smart_engage(cmd.get("id", 0))

		# Loot phase - safely loot all nearby corpses/bones/items
		"loot_phase":
			return _cmd_loot_phase()


		# Human-like looting commands
		"human_loot":
			return _cmd_human_loot()
		
		"walk_to_corpse":
			return _cmd_walk_to_corpse()
		
		"open_loot_ui":
			return _cmd_open_loot_ui()
		
		"take_all_loot":
			return _cmd_take_all_loot()
		
		"loot_aware_combat":
			_loot_aware_combat = cmd.get("enabled", true)
			return {ok = true, loot_aware = _loot_aware_combat}
		
		# ═══════════════════════════════════════════════════════════════════
		# BEHAVIOR TREE COMMANDS
		# ═══════════════════════════════════════════════════════════════════
		
		"bt_enable":
			if behavior_tree:
				behavior_tree.bt_enabled = true
				ai_controlled = true
				player = _find_player()
				if player and "ai_facing_override" in player:
					player.ai_facing_override = true
				return {ok = true, enabled = true}
			return {error = "Behavior tree not initialized"}
		
		"bt_disable":
			if behavior_tree:
				behavior_tree.bt_enabled = false
				_release_inputs()
				return {ok = true, enabled = false}
			return {error = "Behavior tree not initialized"}
		
		"bt_status":
			if behavior_tree:
				var status = behavior_tree.get_status()
				status["last_tick"] = _bt_last_status
				return status
			return {error = "Behavior tree not initialized"}
		
		"bt_goal":
			if behavior_tree:
				var goal = cmd.get("goal", "idle")
				var priority = cmd.get("priority", 3)  # STRATEGIC by default
				var data = cmd.get("data", {})
				behavior_tree.set_goal(goal, priority, data)
				return {ok = true, goal = goal, priority = priority}
			return {error = "Behavior tree not initialized"}
		
		"bt_events":
			if behavior_tree:
				return {events = behavior_tree.get_pending_events()}
			return {error = "Behavior tree not initialized"}
		
		"bt_pause":
			if behavior_tree:
				behavior_tree.bt_paused = cmd.get("paused", true)
				return {ok = true, paused = behavior_tree.bt_paused}
			return {error = "Behavior tree not initialized"}
		
		# Convenience commands that set goals
		"bt_gear_up":
			if behavior_tree:
				behavior_tree.bt_enabled = true
				ai_controlled = true
				player = _find_player()
				behavior_tree.set_goal("gear_up", 2, {})  # TACTICAL priority
				return {ok = true, goal = "gear_up"}
			return {error = "Behavior tree not initialized"}
		
		"bt_grind":
			if behavior_tree:
				behavior_tree.bt_enabled = true
				ai_controlled = true
				player = _find_player()
				behavior_tree.set_goal("quest_grind", 3, {})  # STRATEGIC priority
				return {ok = true, goal = "quest_grind"}
			return {error = "Behavior tree not initialized"}
		
		"bt_combat":
			if behavior_tree:
				behavior_tree.bt_enabled = true
				ai_controlled = true
				player = _find_player()
				behavior_tree.set_goal("combat", 2, {})  # TACTICAL priority
				return {ok = true, goal = "combat"}
			return {error = "Behavior tree not initialized"}
		
		"bt_heal":
			if behavior_tree:
				behavior_tree.bt_enabled = true
				ai_controlled = true
				player = _find_player()
				behavior_tree.set_goal("flee_to_campfire", 0, {})  # CRITICAL priority
				return {ok = true, goal = "flee_to_campfire"}
			return {error = "Behavior tree not initialized"}
		
		"bt_metrics":
			if behavior_tree:
				return behavior_tree.get_metrics()
			return {error = "Behavior tree not initialized"}
		
		"bt_analyze":
			if behavior_tree:
				return behavior_tree.analyze_performance()
			return {error = "Behavior tree not initialized"}

		# ═══════════════════════════════════════════════════════════════════
		# BOT MANAGER COMMANDS (stress testing)
		# ═══════════════════════════════════════════════════════════════════

		"bots_spawn", "bots_despawn", "bots_behavior", "bots_ramp", "bots_stop_ramp", "bots_status", "bots_metrics":
			return _forward_to_bot_manager(cmd)

		_:
			return {error = "Unknown action: %s" % cmd.get("action", "")}

# ═══════════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════════

func _cmd_move(x: float, y: float) -> Dictionary:
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	_is_pathing = false
	_release_inputs()

	if x < -0.3: Input.action_press("move_left")
	elif x > 0.3: Input.action_press("move_right")
	if y < -0.3: Input.action_press("move_up")
	elif y > 0.3: Input.action_press("move_down")

	return {ok = true}

func _cmd_move_to(target: Vector2) -> Dictionary:
	if not ai_controlled:
		return {error = "Not in AI control mode"}
	if not player:
		return {error = "No player found"}

	_move_target = target
	_is_pathing = true
	return {ok = true, target = {x = target.x, y = target.y}}

func _update_pathing(delta: float):
	if not _is_pathing or not player:
		# If we're in healing mode but not pathing, we're at the campfire - wait to heal
		if _is_healing and not _is_pathing:
			var hp_percent = _get_player_hp_percent()
			if hp_percent >= HEAL_RESUME_THRESHOLD:
				print("[MCPBridge] Healed to %.0f%%, resuming combat!" % (hp_percent * 100))
				_is_healing = false
				# Resume auto-combat
				_auto_combat = true
				_combat_target = _find_nearest_alive_enemy()
		return

	# CRITICAL: Check for environmental hazards (lava) during pathing
	if _check_lava_hazard():
		print("[MCPBridge] IN LAVA during pathing! Moving to safety!")
		_move_out_of_hazard()
		return

	# THREAT DETECTION: Check for nearby enemies while pathing (not healing)
	if not _is_healing and not _auto_combat:
		var nearest_enemy = _find_nearest_alive_enemy()
		if nearest_enemy:
			var enemy_dist = player.global_position.distance_to(nearest_enemy.global_position)
			if enemy_dist < THREAT_RESPONSE_RANGE:
				# Enemy very close - engage immediately!
				print("[MCPBridge] THREAT! Enemy at %.0f range - engaging!" % enemy_dist)
				_is_pathing = false
				_release_inputs()
				_combat_target = nearest_enemy
				_auto_combat = true
				return

	var dist = player.global_position.distance_to(_move_target)

	# For campfire healing, use larger arrival radius (don't need to stand ON the fire)
	var arrival_threshold := 20.0
	if _is_healing and _campfire_target and is_instance_valid(_campfire_target):
		arrival_threshold = 80.0  # Campfire healing radius is ~100, stop at 80

	if dist < arrival_threshold:
		_is_pathing = false
		_release_inputs()
		_stuck_counter = 0
		_avoidance_direction = 0
		# If we reached campfire while healing, stay in healing mode
		if _is_healing:
			print("[MCPBridge] Within campfire healing range (%.0f), waiting to heal..." % dist)
		return

	var dir = player.global_position.direction_to(_move_target)

	# Stuck detection - check if we haven't moved much since last frame
	var moved_dist = player.global_position.distance_to(_last_position)
	_last_position = player.global_position

	# Handle avoidance timer (currently trying to go around an obstacle)
	if _avoidance_timer > 0:
		_avoidance_timer -= delta
		_apply_avoidance_movement(dir)
		return

	# Check if stuck (trying to move but not moving much)
	if moved_dist < 1.0:  # Less than 1 pixel of movement
		_stuck_counter += 1
		if _stuck_counter >= STUCK_THRESHOLD:
			# We're stuck! Try to go around the obstacle
			_start_avoidance(dir)
			return
	else:
		_stuck_counter = 0
		_avoidance_direction = 0  # Reset if we're moving normally

	# Normal movement toward target
	_release_inputs()

	# FACE THE DIRECTION WE'RE MOVING (fixes backwards walking)
	if not _auto_combat:  # Don't override combat facing
		_set_face_target(_move_target)

	if dir.x < -0.3: Input.action_press("move_left")
	elif dir.x > 0.3: Input.action_press("move_right")
	if dir.y < -0.3: Input.action_press("move_up")
	elif dir.y > 0.3: Input.action_press("move_down")

func _start_avoidance(dir: Vector2):
	"""Start obstacle avoidance - move perpendicular to the blocked direction"""
	_stuck_counter = 0
	_avoidance_timer = AVOIDANCE_DURATION

	# Alternate avoidance direction each time we get stuck
	if _avoidance_direction == 0:
		_avoidance_direction = 1 if randf() > 0.5 else -1
	else:
		_avoidance_direction = -_avoidance_direction  # Try the other way

	print("[MCPBridge] Stuck! Trying avoidance direction: %d" % _avoidance_direction)
	_apply_avoidance_movement(dir)

func _apply_avoidance_movement(dir: Vector2):
	"""Move perpendicular to the intended direction to get around obstacles"""
	_release_inputs()

	# Determine perpendicular direction based on which axis has more movement
	if abs(dir.x) > abs(dir.y):
		# Moving mostly horizontally - try vertical avoidance
		if _avoidance_direction > 0:
			Input.action_press("move_down")
		else:
			Input.action_press("move_up")
		# Also continue moving in the original horizontal direction
		if dir.x < 0: Input.action_press("move_left")
		elif dir.x > 0: Input.action_press("move_right")
	else:
		# Moving mostly vertically - try horizontal avoidance
		if _avoidance_direction > 0:
			Input.action_press("move_right")
		else:
			Input.action_press("move_left")
		# Also continue moving in the original vertical direction
		if dir.y < 0: Input.action_press("move_up")
		elif dir.y > 0: Input.action_press("move_down")

# ═══════════════════════════════════════════════════════════════════
# FACING DIRECTION CONTROL
# ═══════════════════════════════════════════════════════════════════

func _cmd_face(target: Vector2) -> Dictionary:
	"""Face towards a world position. This controls attack direction."""
	if not ai_controlled:
		return {error = "Not in AI control mode"}
	if not player:
		return {error = "No player found"}

	_set_face_target(target)
	return {ok = true, facing = {x = target.x, y = target.y}}

func _set_face_target(target: Vector2) -> void:
	"""Set the face target and enable facing override."""
	_face_target = target
	_is_facing = true
	# Immediately update player's attack direction
	if player and is_instance_valid(player) and "attack_direction" in player:
		var dir = player.global_position.direction_to(target)
		if dir.length() > 0.1:
			player.attack_direction = dir.normalized()

func _update_facing():
	"""Continuously update player facing direction when AI controlled."""
	if not ai_controlled or not player:
		return

	# During auto-combat, face the combat target
	if _auto_combat and is_instance_valid(_combat_target):
		var dir = player.global_position.direction_to(_combat_target.global_position)
		if dir.length() > 0.1 and "attack_direction" in player:
			player.attack_direction = dir.normalized()
		return

	# Otherwise face the explicit face target if set
	if _is_facing and "attack_direction" in player:
		var dir = player.global_position.direction_to(_face_target)
		if dir.length() > 0.1:
			player.attack_direction = dir.normalized()

func _cmd_attack() -> Dictionary:
	"""Trigger a melee attack via the combat system."""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	# Get the combat system from player
	var combat_system = player.get("combat_system")
	if combat_system and combat_system.has_method("attempt_attack"):
		# Sync attack direction before attacking
		if "attack_direction" in combat_system and "attack_direction" in player:
			combat_system.attack_direction = player.attack_direction
		# Reset can_attack to allow attack (in case cooldown was blocking)
		if "can_attack" in combat_system:
			combat_system.can_attack = true
		if "can_attack" in player:
			player.can_attack = true
		# Trigger the attack
		combat_system.attempt_attack()
		return {ok = true, method = "combat_system"}
	else:
		# Fallback: try direct player method
		if player.has_method("attempt_attack"):
			player.attempt_attack()
			return {ok = true, method = "player_direct"}
		else:
			# Last resort: input action (may not work)
			Input.action_press("attack")
			get_tree().create_timer(0.15).timeout.connect(_release_attack)
			return {ok = true, method = "input_action"}

func _cmd_attack_target(enemy_id: int) -> Dictionary:
	"""Face and attack a specific enemy by instance ID."""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}
	if enemy_id == 0:
		return {error = "Enemy ID required"}

	# Find the enemy by instance ID
	var target: Node2D = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get_instance_id() == enemy_id:
			target = e
			break

	if not target:
		return {error = "Enemy not found with ID: %d" % enemy_id}

	# Face the enemy
	_set_face_target(target.global_position)

	# Attack using the combat system
	var attack_result = _cmd_attack()

	return {
		ok = attack_result.get("ok", false),
		method = attack_result.get("method", "unknown"),
		target = {
			id = enemy_id,
			x = target.global_position.x,
			y = target.global_position.y,
			dist = player.global_position.distance_to(target.global_position)
		}
	}

func _release_attack():
	Input.action_release("attack")

func _cmd_dodge() -> Dictionary:
	Input.action_press("dodge")
	get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("dodge"))
	return {ok = true}

func _cmd_interact() -> Dictionary:
	Input.action_press("interact")
	get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("interact"))
	return {ok = true}

func _cmd_teleport(pos: Vector2) -> Dictionary:
	if not player:
		return {error = "No player"}
	player.global_position = pos
	return {ok = true}

func _cmd_screenshot() -> Dictionary:
	var image = get_viewport().get_texture().get_image()
	var path = "user://mcp_screenshot_%d.png" % Time.get_ticks_msec()
	image.save_png(path)
	return {ok = true, path = ProjectSettings.globalize_path(path)}

# ═══════════════════════════════════════════════════════════════════
# STATE QUERIES
# ═══════════════════════════════════════════════════════════════════

func _get_state() -> Dictionary:
	var state := {
		ai_controlled = ai_controlled,
		timestamp = Time.get_ticks_msec()
	}

	player = _find_player()
	if player:
		# Get current health - try current_health first (new), then current_hp (old)
		var hp = 100
		var max_hp = 100
		if "current_health" in player:
			hp = player.current_health
			max_hp = player.max_health if "max_health" in player else 100
		elif "current_hp" in player:
			hp = player.current_hp
			max_hp = player.max_hp if "max_hp" in player else 100

		state.player = {
			x = player.global_position.x,
			y = player.global_position.y,
			hp = hp,
			max_hp = max_hp
		}

		# Add facing direction
		if "attack_direction" in player:
			var dir = player.attack_direction
			state.player.facing = {
				x = dir.x,
				y = dir.y,
				angle = rad_to_deg(dir.angle())
			}

		if CharacterStats:
			state.player.level = CharacterStats.level
			state.player.gold = CharacterStats.gold

	return state

func _get_nearby_enemies(radius: float) -> Dictionary:
	var enemies := []
	var pos = player.global_position if player else Vector2.ZERO

	for e in get_tree().get_nodes_in_group("enemies"):
		# Skip Training Dummies - they're not real enemies
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue

		var d = e.global_position.distance_to(pos)
		if d <= radius:
			# Get enemy type - try method first, then property, then node name
			var etype = "enemy"
			if e.has_method("get_enemy_type"):
				etype = e.get_enemy_type()
			elif "enemy_type" in e:
				etype = e.enemy_type
			else:
				etype = e.name.to_lower()

			# Get HP - use current_health (not current_hp)
			var hp = 0
			var max_hp = 0
			if "current_health" in e:
				hp = e.current_health
				max_hp = e.max_health if "max_health" in e else hp
			elif "current_hp" in e:
				hp = e.current_hp
				max_hp = e.max_hp if "max_hp" in e else hp

			enemies.append({
				id = e.get_instance_id(),
				type = etype,
				name = e.name,
				x = e.global_position.x,
				y = e.global_position.y,
				dist = d,
				hp = hp,
				max_hp = max_hp
			})

	enemies.sort_custom(func(a, b): return a.dist < b.dist)
	return {enemies = enemies}

func _get_nearby_items(radius: float) -> Dictionary:
	var items := []
	var pos = player.global_position if player else Vector2.ZERO

	for item in get_tree().get_nodes_in_group("loot"):
		var d = item.global_position.distance_to(pos)
		if d <= radius:
			items.append({
				id = item.get_instance_id(),
				name = item.item_name if "item_name" in item else "item",
				x = item.global_position.x,
				y = item.global_position.y,
				dist = d
			})

	items.sort_custom(func(a, b): return a.dist < b.dist)
	return {items = items}

func _get_weakpoints() -> Dictionary:
	"""Get all active weakpoints on nearby enemies."""
	var weakpoints := []
	var pos = player.global_position if player else Vector2.ZERO

	for wp in get_tree().get_nodes_in_group("weakpoints"):
		if not is_instance_valid(wp):
			continue
		if wp.get("is_destroyed"):
			continue

		var d = wp.global_position.distance_to(pos)
		var parent_name = ""
		var parent = wp.get_parent()
		if parent:
			parent_name = parent.name

		weakpoints.append({
			id = wp.get_instance_id(),
			x = wp.global_position.x,
			y = wp.global_position.y,
			dist = d,
			hits_remaining = wp.max_hits - wp.current_hits if "max_hits" in wp else 0,
			parent = parent_name,
			theme = wp.color_theme if "color_theme" in wp else "unknown"
		})

	weakpoints.sort_custom(func(a, b): return a.dist < b.dist)
	return {weakpoints = weakpoints, count = weakpoints.size()}

func _cmd_click_weakpoint(wp_id: int) -> Dictionary:
	"""Simulate clicking on a weakpoint."""
	if wp_id == 0:
		return {error = "Weakpoint ID required"}

	# Find the weakpoint
	var target_wp: Node = null
	for wp in get_tree().get_nodes_in_group("weakpoints"):
		if wp.get_instance_id() == wp_id:
			target_wp = wp
			break

	if not target_wp:
		return {error = "Weakpoint not found with ID: %d" % wp_id}

	if target_wp.get("is_destroyed"):
		return {error = "Weakpoint already destroyed"}

	# Call the hit() method directly (simulates a click)
	if target_wp.has_method("hit"):
		target_wp.hit()
		return {
			ok = true,
			weakpoint = {
				id = wp_id,
				x = target_wp.global_position.x,
				y = target_wp.global_position.y,
				hits_remaining = target_wp.max_hits - target_wp.current_hits if "max_hits" in target_wp else 0,
				destroyed = target_wp.get("is_destroyed")
			}
		}
	else:
		return {error = "Weakpoint has no hit() method"}

# ═══════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════

func _try_click_any_weakpoint() -> bool:
	"""Check for active weakpoints and click the nearest one. Returns true if clicked."""
	var nearest_wp: Node = null
	var nearest_dist := 999999.0
	var pos = player.global_position if player else Vector2.ZERO

	for wp in get_tree().get_nodes_in_group("weakpoints"):
		if not is_instance_valid(wp):
			continue
		if wp.get("is_destroyed"):
			continue

		var d = wp.global_position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest_wp = wp

	if nearest_wp and nearest_wp.has_method("hit"):
		# Face the weakpoint before clicking
		_set_face_target(nearest_wp.global_position)
		nearest_wp.hit()
		print("[MCPBridge] Auto-combat: Clicked weakpoint at (%.0f, %.0f)" % [nearest_wp.global_position.x, nearest_wp.global_position.y])
		return true

	return false

func _find_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	return players[0] if players.size() > 0 else null

func _release_inputs():
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

# ═══════════════════════════════════════════════════════════════════
# INVENTORY & QUESTS
# ═══════════════════════════════════════════════════════════════════

func _get_inventory() -> Dictionary:
	var items := []
	if InventorySystem and "inventory_items" in InventorySystem:
		for i in range(InventorySystem.inventory_items.size()):
			var item = InventorySystem.inventory_items[i]
			if item:
				items.append({
					slot = i,
					id = item.get("id", ""),
					name = item.get("name", "Unknown"),
					type = item.get("type", ""),
					quantity = item.get("quantity", 1),
					rarity = item.get("rarity", "common")
				})
	return {inventory = items, count = items.size()}

func _get_quests() -> Dictionary:
	var result := {active = [], available = [], completed = []}

	if QuestManager:
		# Active quests
		if "active_quest_ids" in QuestManager:
			for qid in QuestManager.active_quest_ids:
				var qdata = _get_quest_info(qid)
				if qdata:
					result.active.append(qdata)

		# Quest states
		if "quest_states" in QuestManager:
			for qid in QuestManager.quest_states:
				var state = QuestManager.quest_states[qid]
				if state == 1:  # AVAILABLE
					var qdata = _get_quest_info(qid)
					if qdata:
						result.available.append(qdata)
				elif state == 3:  # COMPLETE
					result.completed.append(qid)

	return result

func _get_quest_info(quest_id: String) -> Dictionary:
	if QuestManager and "all_quests" in QuestManager:
		var q = QuestManager.all_quests.get(quest_id, {})
		if q:
			return {
				id = quest_id,
				name = q.get("name", quest_id),
				description = q.get("description", ""),
				objectives = q.get("objectives", [])
			}
	return {}

func _cmd_accept_quest(quest_id: String) -> Dictionary:
	"""Accept an available quest"""
	if not QuestManager:
		return {error = "QuestManager not found"}
	if quest_id.is_empty():
		return {error = "Quest ID required"}

	# Check if quest exists
	if not QuestManager.all_quests.has(quest_id):
		return {error = "Quest not found: %s" % quest_id}

	# Try to accept
	if QuestManager.accept_quest(quest_id):
		var quest = QuestManager.all_quests.get(quest_id, {})
		return {
			ok = true,
			quest_id = quest_id,
			name = quest.get("name", quest_id),
			objectives = quest.get("objectives", [])
		}
	else:
		var state = QuestManager.get_quest_state(quest_id)
		return {error = "Cannot accept quest (state: %d)" % state}

func _cmd_turn_in_quest(quest_id: String) -> Dictionary:
	"""Turn in a completed quest"""
	if not QuestManager:
		return {error = "QuestManager not found"}
	if quest_id.is_empty():
		return {error = "Quest ID required"}

	# Check if quest is complete
	var state = QuestManager.get_quest_state(quest_id)
	if state != 3:  # QuestState.COMPLETE
		return {error = "Quest not complete (state: %d)" % state}

	# Turn in
	if QuestManager.turn_in_quest(quest_id):
		return {ok = true, quest_id = quest_id, turned_in = true}
	else:
		return {error = "Failed to turn in quest"}

func _get_quest_progress() -> Dictionary:
	"""Get detailed progress on active quests"""
	if not QuestManager:
		return {error = "QuestManager not found"}

	var quests := []
	for qid in QuestManager.active_quest_ids:
		var quest = QuestManager.all_quests.get(qid, {})
		var progress = QuestManager.quest_progress.get(qid, {})
		var state = QuestManager.get_quest_state(qid)

		var obj_progress := []
		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			var current = progress.get(i, 0)
			var required = obj.get("count", 1)
			obj_progress.append({
				index = i,
				type = obj.get("type", ""),
				target = obj.get("target", ""),
				description = obj.get("desc", ""),
				current = current,
				required = required,
				complete = current >= required
			})

		quests.append({
			id = qid,
			name = quest.get("name", qid),
			state = state,
			state_name = ["LOCKED", "AVAILABLE", "ACTIVE", "COMPLETE", "TURNED_IN"][state] if state < 5 else "UNKNOWN",
			objectives = obj_progress
		})

	return {quests = quests, count = quests.size()}

func _cmd_loot_items(radius: float) -> Dictionary:
	"""Loot all nearby items within radius"""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	var looted := []
	var pos = player.global_position

	# Find items in "items" group (dropped loot)
	for item in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(item):
			continue
		var d = item.global_position.distance_to(pos)
		if d <= radius:
			# Try to pick up the item
			if item.has_method("pickup") or item.has_method("_on_pickup"):
				var item_name = item.name
				if "item_data" in item:
					item_name = item.item_data.get("name", item.name)
				elif "item_name" in item:
					item_name = item.item_name

				# Try pickup methods
				if item.has_method("pickup"):
					item.pickup(player)
				elif item.has_method("_on_pickup"):
					item._on_pickup(player)

				looted.append({name = item_name, distance = d})

	# Also check for "loot" group
	for item in get_tree().get_nodes_in_group("loot"):
		if not is_instance_valid(item):
			continue
		var d = item.global_position.distance_to(pos)
		if d <= radius:
			if item.has_method("collect") or item.has_method("pickup"):
				var item_name = item.name
				if item.has_method("collect"):
					item.collect()
				elif item.has_method("pickup"):
					item.pickup(player)
				looted.append({name = item_name, distance = d})

	return {ok = true, looted = looted, count = looted.size()}

func _get_shop_inventory() -> Dictionary:
	"""Get available items from shop JSON files"""
	var result := {weapons = [], armor = [], tools = []}

	# Load weapons
	var weapons_file = FileAccess.open("res://data/shop_weapons.json", FileAccess.READ)
	if weapons_file:
		var json = JSON.new()
		if json.parse(weapons_file.get_as_text()) == OK:
			var data = json.data
			if data.has("weapons"):
				for w in data["weapons"]:
					# Skip pure comment entries (no id field), but keep items with _comment as header
					if not w.has("id") or w.get("id", "").is_empty():
						continue
					result.weapons.append({
						id = w.get("id", ""),
						name = w.get("name", ""),
						type = w.get("weapon_type", ""),
						damage = w.get("base_damage", 0),
						speed = w.get("attack_speed", "medium"),
						price = w.get("price", 0),
						level = w.get("required_level", 1),
						rarity = w.get("rarity", "Common"),
						zone = w.get("zone", 1)
					})
		weapons_file.close()

	# Load armor
	var armor_file = FileAccess.open("res://data/shop_armor.json", FileAccess.READ)
	if armor_file:
		var json = JSON.new()
		if json.parse(armor_file.get_as_text()) == OK:
			var data = json.data
			if data.has("armor"):
				for a in data["armor"]:
					# Skip pure comment entries (no id field), but keep items with _comment as header
					if not a.has("id") or a.get("id", "").is_empty():
						continue
					result.armor.append({
						id = a.get("id", ""),
						name = a.get("name", ""),
						slot = a.get("slot", ""),
						armor_type = a.get("armor_type", ""),
						defense = a.get("defense", 0),
						price = a.get("price", 0),
						level = a.get("required_level", 1),
						rarity = a.get("rarity", "Common"),
						stats = a.get("stat_bonuses", {})
					})
		armor_file.close()

	return result

func _cmd_buy_item(item_id: String, item_type: String) -> Dictionary:
	"""Buy an item and add to inventory"""
	if item_id.is_empty():
		return {error = "Item ID required"}

	# Find item in shop data
	var item_data: Dictionary = {}
	var file_path = ""

	if item_type == "weapon":
		file_path = "res://data/shop_weapons.json"
	elif item_type == "armor":
		file_path = "res://data/shop_armor.json"
	else:
		return {error = "Invalid item type: %s" % item_type}

	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {error = "Cannot open shop file"}

	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {error = "Invalid shop JSON"}

	var data = json.data
	var items_key = "weapons" if item_type == "weapon" else "armor"

	for item in data.get(items_key, []):
		if item.get("id") == item_id:
			item_data = item.duplicate()
			break
	file.close()

	if item_data.is_empty():
		return {error = "Item not found: %s" % item_id}

	# Check gold (if price > 0)
	var price = item_data.get("price", 0)
	if price > 0 and CharacterStats:
		var gold = CharacterStats.gold if "gold" in CharacterStats else 0
		if gold < price:
			return {error = "Not enough gold (%d/%d)" % [gold, price]}
		CharacterStats.gold -= price

	# Add to inventory
	if InventorySystem and InventorySystem.has_method("add_item"):
		item_data["type"] = item_type
		var added = InventorySystem.add_item(item_data)
		if added:
			return {ok = true, item = item_data.get("name", item_id), price = price}
		else:
			# Refund gold
			if price > 0 and CharacterStats:
				CharacterStats.gold += price
			return {error = "Inventory full"}

	return {error = "InventorySystem not available"}

func _cmd_equip_item(slot: int, item_id: String) -> Dictionary:
	"""Equip an item from inventory by slot index or item_id"""
	if not InventorySystem:
		return {error = "InventorySystem not available"}

	var item: Dictionary = {}

	# Find item by slot or id
	if slot >= 0:
		if "inventory_items" in InventorySystem and slot < InventorySystem.inventory_items.size():
			item = InventorySystem.inventory_items[slot]
	elif not item_id.is_empty():
		if "inventory_items" in InventorySystem:
			for i in range(InventorySystem.inventory_items.size()):
				var inv_item = InventorySystem.inventory_items[i]
				if inv_item and inv_item.get("id", "") == item_id:
					item = inv_item
					slot = i
					break

	if item.is_empty():
		return {error = "Item not found"}

	var item_type = item.get("type", "")
	var item_name = item.get("name", "unknown")

	# Equip based on type
	if item_type == "weapon" or item.has("weapon_type"):
		if CharacterStats and CharacterStats.has_method("equip_weapon"):
			# Create weapon resource
			var weapon = _create_weapon_from_data(item)
			if weapon:
				CharacterStats.equip_weapon(weapon, item)
				return {ok = true, equipped = item_name, type = "weapon"}
		return {error = "Cannot equip weapon"}

	elif item_type == "armor" or item.has("slot"):
		if CharacterStats and CharacterStats.has_method("equip_armor"):
			if CharacterStats.equip_armor(item):
				return {ok = true, equipped = item_name, type = "armor", slot = item.get("slot", "")}
		return {error = "Cannot equip armor"}

	elif item.get("tool_type") == "axe":
		if InventorySystem.has_method("equip_axe"):
			InventorySystem.equip_axe(item)
			return {ok = true, equipped = item_name, type = "tool"}

	elif item.get("tool_type") == "pickaxe":
		if InventorySystem.has_method("equip_pickaxe"):
			InventorySystem.equip_pickaxe(item)
			return {ok = true, equipped = item_name, type = "tool"}

	return {error = "Unknown item type: %s" % item_type}

func _create_weapon_from_data(item_data: Dictionary):
	"""Create a Weapon resource from item data"""
	var weapon = Weapon.new()
	weapon.weapon_name = item_data.get("name", "Unknown")
	weapon.weapon_type = item_data.get("weapon_type", "sword")
	weapon.base_damage = item_data.get("base_damage", 1)
	weapon.required_level = item_data.get("required_level", 1)

	# Handle attack speed (convert string to bonus)
	var speed = item_data.get("attack_speed", "medium")
	if speed == "fast":
		weapon.attack_speed_bonus = -0.2  # 20% faster
	elif speed == "slow":
		weapon.attack_speed_bonus = 0.2   # 20% slower
	else:
		weapon.attack_speed_bonus = 0.0   # medium

	# Handle rarity (convert string to enum)
	var rarity_str = item_data.get("rarity", "Common")
	match rarity_str.to_lower():
		"common":
			weapon.rarity = Weapon.Rarity.COMMON
		"uncommon":
			weapon.rarity = Weapon.Rarity.UNCOMMON
		"rare":
			weapon.rarity = Weapon.Rarity.RARE
		"epic":
			weapon.rarity = Weapon.Rarity.EPIC
		"legendary":
			weapon.rarity = Weapon.Rarity.LEGENDARY
		"artifact":
			weapon.rarity = Weapon.Rarity.ARTIFACT
		_:
			weapon.rarity = Weapon.Rarity.COMMON

	return weapon

func _cmd_give_gold(amount: int) -> Dictionary:
	"""Debug: Give gold to player"""
	if not CharacterStats:
		return {error = "CharacterStats not available"}
	CharacterStats.gold += amount
	return {ok = true, gold = CharacterStats.gold, added = amount}

func _cmd_equip_best_gear() -> Dictionary:
	"""Auto-equip best gear from inventory"""
	if not InventorySystem or not CharacterStats:
		return {error = "Systems not available"}

	var equipped := []

	# Get inventory items
	var inventory = InventorySystem.inventory_items if "inventory_items" in InventorySystem else []

	# Track best items by slot
	var best_weapon: Dictionary = {}
	var best_armor := {}  # slot -> item

	for item in inventory:
		if not item:
			continue

		# Check weapons
		if item.get("type") == "weapon" or item.has("weapon_type"):
			var damage = item.get("base_damage", 0)
			if damage > best_weapon.get("base_damage", 0):
				best_weapon = item

		# Check armor
		elif item.get("type") == "armor" or item.has("slot"):
			var slot = item.get("slot", "")
			if slot.is_empty():
				continue
			var defense = item.get("defense", 0)
			if defense > best_armor.get(slot, {}).get("defense", 0):
				best_armor[slot] = item

	# Equip best weapon
	if not best_weapon.is_empty():
		var weapon = _create_weapon_from_data(best_weapon)
		if weapon:
			CharacterStats.equip_weapon(weapon, best_weapon)
			equipped.append({type = "weapon", name = best_weapon.get("name", ""), damage = best_weapon.get("base_damage", 0)})

	# Equip best armor for each slot
	for slot in best_armor:
		var armor = best_armor[slot]
		if CharacterStats.equip_armor(armor):
			equipped.append({type = "armor", slot = slot, name = armor.get("name", ""), defense = armor.get("defense", 0)})

	return {ok = true, equipped = equipped, count = equipped.size()}

func _get_nearby_npcs(radius: float) -> Dictionary:
	var npcs := []
	var pos = player.global_position if player else Vector2.ZERO

	for npc in get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(npc):
			continue
		var d = npc.global_position.distance_to(pos)
		if d <= radius:
			npcs.append({
				name = npc.name,
				id = npc.npc_id if "npc_id" in npc else npc.name,
				x = npc.global_position.x,
				y = npc.global_position.y,
				dist = d
			})

	# Also check for interactables like Wanderer
	for node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		var d = node.global_position.distance_to(pos)
		if d <= radius:
			var already_added = false
			for n in npcs:
				if n.name == node.name:
					already_added = true
					break
			if not already_added:
				npcs.append({
					name = node.name,
					id = node.name,
					x = node.global_position.x,
					y = node.global_position.y,
					dist = d
				})

	npcs.sort_custom(func(a, b): return a.dist < b.dist)
	return {npcs = npcs}

func _cmd_move_to_npc(npc_name: String) -> Dictionary:
	if not ai_controlled:
		return {error = "Not in AI control mode"}
	if npc_name.is_empty():
		return {error = "NPC name required"}

	# Search in npcs and interactables
	var target_pos: Vector2 = Vector2.ZERO
	var found := false

	for npc in get_tree().get_nodes_in_group("npcs"):
		if npc.name.to_lower().contains(npc_name.to_lower()):
			target_pos = npc.global_position
			found = true
			break

	if not found:
		for node in get_tree().get_nodes_in_group("interactable"):
			if node.name.to_lower().contains(npc_name.to_lower()):
				target_pos = node.global_position
				found = true
				break

	if not found:
		return {error = "NPC not found: %s" % npc_name}

	_move_target = target_pos
	_is_pathing = true
	return {ok = true, target = {x = target_pos.x, y = target_pos.y}, npc = npc_name}

# ═══════════════════════════════════════════════════════════════════
# AUTO-COMBAT
# ═══════════════════════════════════════════════════════════════════

func _cmd_auto_combat() -> Dictionary:
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	# Find nearest alive enemy
	_combat_target = _find_nearest_alive_enemy()
	if not _combat_target:
		return {error = "No enemies nearby", enemies_found = 0}

	_auto_combat = true
	_is_pathing = false

	# Get enemy type properly
	var etype = "enemy"
	if _combat_target.has_method("get_enemy_type"):
		etype = _combat_target.get_enemy_type()
	elif "enemy_type" in _combat_target:
		etype = _combat_target.enemy_type
	else:
		etype = _combat_target.name

	return {
		ok = true,
		target = {
			type = etype,
			name = _combat_target.name,
			x = _combat_target.global_position.x,
			y = _combat_target.global_position.y,
			hp = _get_enemy_hp(_combat_target)
		}
	}

func _update_auto_combat(delta: float):
	if not _auto_combat or not ai_controlled:
		return

	_attack_timer -= delta
	_post_kill_loot_timer -= delta
	player = _find_player()

	if not player:
		# Player died - track death position for return
		if _last_death_position == Vector2.ZERO or _death_time == 0:
			# This might be first check after death - position already reset
			pass
		_auto_combat = false
		return

	# Track player position for death tracking
	_track_player_for_death()

	# CRITICAL: Check for environmental hazards (lava) - move out immediately!
	if _check_lava_hazard():
		print("[MCPBridge] IN LAVA! Moving to safety!")
		_move_out_of_hazard()
		return

	# Check player HP - retreat to campfire if below threshold
	var hp_percent = _get_player_hp_percent()
	if hp_percent < HEAL_RETREAT_THRESHOLD:
		print("[MCPBridge] Auto-combat: Low HP (%.0f%%), retreating to campfire!" % (hp_percent * 100))
		_auto_combat = false
		_release_inputs()
		# Start moving to campfire (use large radius to always find it)
		var campfire_result = _find_campfire(10000.0)
		if campfire_result.count > 0:
			var nearest = campfire_result.campfires[0]
			_campfire_target = instance_from_id(nearest.id)
			if is_instance_valid(_campfire_target):
				_is_healing = true
				_move_target = _campfire_target.global_position
				_is_pathing = true
				print("[MCPBridge] Moving to campfire at (%.0f, %.0f) - dist: %.0f" % [_move_target.x, _move_target.y, nearest.dist])
			else:
				print("[MCPBridge] WARNING: Campfire instance not valid!")
		else:
			print("[MCPBridge] WARNING: No campfire found in auto-combat retreat!")
		return

	# PRIORITY: Click any active weakpoints first!
	var clicked_weakpoint = _try_click_any_weakpoint()
	if clicked_weakpoint:
		# Weakpoint clicked - reset attack timer to allow quick follow-up
		_attack_timer = 0.1
		return

	# Check if target is still valid
	if not is_instance_valid(_combat_target) or not _combat_target.is_inside_tree():
		_combat_target = _find_nearest_alive_enemy()
		if not _combat_target:
			# No more enemies - safe to loot!
			_try_loot_if_safe()
			_auto_combat = false
			_release_inputs()
			print("[MCPBridge] Auto-combat: No more enemies")
			return

	# Check if target is TRULY dead (must pass multiple checks)
	var target_dead = false
	var hp = _get_enemy_hp(_combat_target)

	# Method 1: is_dead() method
	if _combat_target.has_method("is_dead") and _combat_target.is_dead():
		target_dead = true
	# Method 2: HP at exactly 0 or below
	elif hp <= 0:
		target_dead = true
	# Method 3: Enemy removed from scene tree
	elif not _combat_target.is_inside_tree():
		target_dead = true

	# SAFETY CHECK: If HP is very low but not 0, KEEP ATTACKING - don't loot!
	if hp > 0 and hp < 20:
		print("[MCPBridge] Enemy at %.1f HP - FINISHING OFF!" % hp)
		target_dead = false  # Override - keep attacking!

	if target_dead:
		print("[MCPBridge] Auto-combat: Enemy defeated!")

		# CRITICAL FIX: Save corpse position BEFORE clearing target
		# The corpse will appear at this location after death transition
		_pending_corpse_position = _combat_target.global_position
		_pending_corpse_timer = 0.0
		_moving_to_corpse = true
		print("[MCPBridge] Corpse expected at (%.0f, %.0f) - moving to loot" % [_pending_corpse_position.x, _pending_corpse_position.y])

		# Clear combat target - we'll find a new one after looting
		_combat_target = null
		return  # Exit to enter looting phase

	# Handle corpse looting phase - move to corpse and loot it
	if _moving_to_corpse:
		var dist_to_corpse = player.global_position.distance_to(_pending_corpse_position)

		# Check if we're close enough to loot
		if dist_to_corpse <= CORPSE_LOOT_RANGE:
			# Wait a moment for corpse transition to complete
			_pending_corpse_timer += delta
			_release_inputs()  # Stop moving

			# Try to loot
			var looted_count = _try_loot_nearby()
			if looted_count > 0:
				print("[MCPBridge] LOOTED %d items from corpse!" % looted_count)
				_moving_to_corpse = false
				_pending_corpse_position = Vector2.ZERO
				# Find next target
				_combat_target = _find_nearest_alive_enemy()
				if not _combat_target:
					_auto_combat = false
					print("[MCPBridge] Auto-combat: All enemies defeated!")
				return

			# If waited too long, give up and continue
			if _pending_corpse_timer >= CORPSE_WAIT_TIME:
				print("[MCPBridge] Corpse timeout - no loot found, continuing")
				_moving_to_corpse = false
				_pending_corpse_position = Vector2.ZERO
				_combat_target = _find_nearest_alive_enemy()
				if not _combat_target:
					_auto_combat = false
					print("[MCPBridge] Auto-combat: All enemies defeated!")
				return

			# Still waiting for corpse
			return
		else:
			# Move toward corpse location
			var dir = player.global_position.direction_to(_pending_corpse_position)
			_set_face_target(_pending_corpse_position)

			# Release all movement first
			Input.action_release("move_up")
			Input.action_release("move_down")
			Input.action_release("move_left")
			Input.action_release("move_right")

			# Press appropriate movement keys
			if dir.x > 0.3:
				Input.action_press("move_right")
			elif dir.x < -0.3:
				Input.action_press("move_left")
			if dir.y > 0.3:
				Input.action_press("move_down")
			elif dir.y < -0.3:
				Input.action_press("move_up")

			# Check for threats while moving to loot
			var threat_count = _count_nearby_threats(AGGRO_DETECTION_RADIUS)
			if threat_count > 0:
				print("[MCPBridge] Threat detected while looting - engaging!")
				_moving_to_corpse = false
				_pending_corpse_position = Vector2.ZERO
				_combat_target = _find_nearest_alive_enemy()
			return

	# Handle looting pause - stay still briefly after looting
	if _is_looting_pause:
		if _post_kill_loot_timer > 0:
			_release_inputs()  # Stay still during loot pause
			return
		else:
			print("[MCPBridge] Loot pause complete - resuming combat")
			_is_looting_pause = false

	var dist = player.global_position.distance_to(_combat_target.global_position)

	# ALWAYS face the target when moving toward it (fixes backwards walking)
	_set_face_target(_combat_target.global_position)

	if dist > COMBAT_RANGE:
		# Move toward enemy - face first!
		var dir = player.global_position.direction_to(_combat_target.global_position)

		# CRITICAL: Check if moving toward enemy would put us in lava!
		var next_pos = player.global_position + dir * 50.0  # Check 50 pixels ahead
		if _is_position_in_lava(next_pos):
			print("[MCPBridge] PATH BLOCKED BY LAVA! Finding different target...")
			# Current target leads into lava - find a different one
			var alt_target = _find_nearest_alive_enemy()
			if alt_target and alt_target != _combat_target:
				_combat_target = alt_target
				return
			else:
				# No safe targets - stop and wait
				_release_inputs()
				print("[MCPBridge] All paths blocked by lava - waiting")
				return

		# Stuck detection during combat movement
		var moved_dist = player.global_position.distance_to(_last_position)
		_last_position = player.global_position

		# Handle avoidance timer
		if _avoidance_timer > 0:
			_avoidance_timer -= delta
			_apply_avoidance_movement(dir)
			return

		# Check if stuck
		if moved_dist < 1.0:
			_stuck_counter += 1
			if _stuck_counter >= STUCK_THRESHOLD:
				_start_avoidance(dir)
				return
		else:
			_stuck_counter = 0
			_avoidance_direction = 0

		_release_inputs()
		if dir.x < -0.3: Input.action_press("move_left")
		elif dir.x > 0.3: Input.action_press("move_right")
		if dir.y < -0.3: Input.action_press("move_up")
		elif dir.y > 0.3: Input.action_press("move_down")
	else:
		# In range - stop and attack!
		_stuck_counter = 0
		_avoidance_direction = 0
		_release_inputs()
		if _attack_timer <= 0:
			# Use combat system to attack (facing is handled by _update_facing)
			_cmd_attack()
			_attack_timer = ATTACK_COOLDOWN

func _try_loot_nearby() -> int:
	"""Try to loot any nearby corpses after a kill. Returns count of items looted."""
	if not player:
		return 0

	var pos = player.global_position
	var loot_range := 200.0  # Corpses often end up 170+ units away after combat
	var total_looted := 0

	# Check for corpses (enemy bodies with loot)
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d <= loot_range:
			# Check if corpse has loot
			var has_gold = "corpse_gold" in corpse and corpse.corpse_gold > 0
			var has_items = "corpse_loot" in corpse and corpse.corpse_loot.size() > 0

			if has_gold or has_items:
				# Collect gold directly
				if has_gold:
					var gold_amt = corpse.corpse_gold
					CharacterStats.gold += gold_amt
					print("[MCPBridge] LOOTED %d gold from %s (total: %d)" % [gold_amt, corpse.name, CharacterStats.gold])
					corpse.corpse_gold = 0
					total_looted += 1

				# Collect items directly to inventory
				if has_items:
					for item in corpse.corpse_loot:
						if InventorySystem and InventorySystem.has_method("add_item"):
							var added = InventorySystem.add_item(item)
							if added:
								print("[MCPBridge] LOOTED item: %s" % item.get("name", "Unknown"))
								total_looted += 1
							else:
								print("[MCPBridge] Inventory full - couldn't loot %s" % item.get("name", "Unknown"))
					corpse.corpse_loot.clear()

				# Mark corpse as looted (triggers despawn)
				if corpse.has_method("check_if_looted_empty"):
					corpse.check_if_looted_empty()

	# Also check for pickable bones (separate from corpses)
	for item in get_tree().get_nodes_in_group("pickable_bones"):
		if not is_instance_valid(item):
			continue
		var d = item.global_position.distance_to(pos)
		if d <= loot_range:
			if item.has_method("pick_up_item"):
				item.pick_up_item()
				print("[MCPBridge] LOOTED bone: %s" % item.name)
				total_looted += 1

	# Also try "items" and "loot" groups for dropped items
	for group_name in ["items", "loot"]:
		for item in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(item):
				continue
			var d = item.global_position.distance_to(pos)
			if d <= loot_range:
				# Try various pickup methods
				if item.has_method("collect"):
					item.collect()
					print("[MCPBridge] LOOTED (collect): %s" % item.name)
					total_looted += 1
				elif item.has_method("pickup"):
					item.pickup(player)
					print("[MCPBridge] LOOTED (pickup): %s" % item.name)
					total_looted += 1
				elif item.has_method("_on_body_entered"):
					# Simulate collision pickup
					item._on_body_entered(player)
					print("[MCPBridge] LOOTED (body_entered): %s" % item.name)
					total_looted += 1

	if total_looted > 0:
		print("[MCPBridge] *** Looted %d items total ***" % total_looted)

	return total_looted

func _is_position_in_lava(pos: Vector2) -> bool:
	"""Check if a given position is inside a lava pool"""
	var lava_range := 70.0  # Slightly smaller than pool radius

	# Check for lava pools by group (primary method)
	for lava in get_tree().get_nodes_in_group("lava_pools"):
		if not is_instance_valid(lava):
			continue
		if lava.global_position.distance_to(pos) < lava_range:
			return true

	# Check for CleanseableLavaPool class in interactable group
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is CleanseableLavaPool:
			if node.global_position.distance_to(pos) < lava_range:
				return true

	# Search ALL nodes in scene tree (covers chunked/nested lava pools)
	var all_nodes = _get_all_tree_nodes(get_tree().current_scene)
	for node in all_nodes:
		if not is_instance_valid(node):
			continue
		if node is CleanseableLavaPool:
			if node.global_position.distance_to(pos) < lava_range:
				return true
		elif node is Node2D and ("lava" in node.name.to_lower() or "Lava" in node.name):
			if node.global_position.distance_to(pos) < lava_range:
				return true

	return false

func _find_nearest_alive_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := 800.0  # Max search range
	var pos = player.global_position if player else Vector2.ZERO

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		# Check HP using current_health (primary) or current_hp (fallback)
		if "current_health" in e and e.current_health <= 0:
			continue
		if "current_hp" in e and e.current_hp <= 0:
			continue

		# Skip Training Dummies - they're not real enemies
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue

		# CRITICAL: Skip enemies that are standing in lava - don't chase them!
		if _is_position_in_lava(e.global_position):
			print("[MCPBridge] Skipping enemy in lava: %s" % e.name)
			continue

		var d = e.global_position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e

	return nearest

func _get_enemy_hp(enemy: Node2D) -> float:
	if "current_health" in enemy:
		return enemy.current_health
	elif "current_hp" in enemy:
		return enemy.current_hp
	return 0.0

# ═══════════════════════════════════════════════════════════════════
# MENU AUTOMATION
# ═══════════════════════════════════════════════════════════════════

func _get_menu_state() -> Dictionary:
	"""Get current menu/scene state for navigation"""
	var current_scene = get_tree().current_scene
	var scene_name = current_scene.name if current_scene else "unknown"

	var result := {
		scene = scene_name,
		is_in_game = false,
		is_in_menu = false,
		is_in_armory = false
	}

	# Check for MainMenu
	if scene_name == "MainMenu" or current_scene is Control:
		result.is_in_menu = true
		# Check for Ashbane panel visibility
		var ashbane_panel = current_scene.get_node_or_null("AshbanePanel")
		if ashbane_panel and ashbane_panel.visible:
			result.menu_panel = "ashbane"
		var auth_panel = current_scene.get_node_or_null("AuthPanel")
		if auth_panel and auth_panel.visible:
			result.menu_panel = "auth"

	# Check for Armory
	if scene_name == "Armory":
		result.is_in_armory = true

	# Check for game world
	if scene_name == "GameWorld" or scene_name == "World":
		result.is_in_game = true

	# Check for player
	player = _find_player()
	result.has_player = player != null

	return result

func _cmd_click_play_guest() -> Dictionary:
	"""Click the 'Play as Guest' / 'Skip' button on the Ashbane screen"""
	var current_scene = get_tree().current_scene
	if not current_scene:
		return {error = "No current scene"}

	# Look for MainMenu script with _on_ashbane_skip_pressed method
	if current_scene.has_method("_on_ashbane_skip_pressed"):
		current_scene._on_ashbane_skip_pressed()
		return {ok = true, action = "ashbane_skip"}

	# Alternative: Look for the skip button directly
	var skip_button = _find_node_by_text(current_scene, "Play as Guest")
	if not skip_button:
		skip_button = _find_node_by_text(current_scene, "Skip")
	if not skip_button:
		skip_button = _find_node_by_text(current_scene, "Continue as Guest")

	if skip_button and skip_button is Button:
		skip_button.emit_signal("pressed")
		return {ok = true, action = "button_click", button = skip_button.text}

	# Check if already in Armory
	if current_scene.name == "Armory":
		return {ok = true, already_in = "armory"}

	return {error = "Cannot find Play as Guest button - scene: %s" % current_scene.name}

func _cmd_click_enter_world() -> Dictionary:
	"""Click the 'Enter World' button in the Armory"""
	var current_scene = get_tree().current_scene
	if not current_scene:
		return {error = "No current scene"}

	# Look for Armory script with _on_enter_world_pressed method
	if current_scene.has_method("_on_enter_world_pressed"):
		current_scene._on_enter_world_pressed()
		return {ok = true, action = "enter_world"}

	# Look for enter_world_button property
	if "enter_world_button" in current_scene:
		var button = current_scene.enter_world_button
		if button and button is Button:
			button.emit_signal("pressed")
			return {ok = true, action = "button_click"}

	# Alternative: Find button by text
	var enter_button = _find_node_by_text(current_scene, "ENTER WORLD")
	if not enter_button:
		enter_button = _find_node_by_text(current_scene, "Enter World")

	if enter_button and enter_button is Button:
		enter_button.emit_signal("pressed")
		return {ok = true, action = "button_click", button = enter_button.text}

	# Check if already in game
	player = _find_player()
	if player:
		return {ok = true, already_in = "game"}

	return {error = "Cannot find Enter World button - scene: %s" % current_scene.name}

func _find_node_by_text(root: Node, text: String) -> Node:
	"""Recursively find a node with matching text property"""
	if root is Button and root.text.to_lower().contains(text.to_lower()):
		return root
	if root is Label and root.text.to_lower().contains(text.to_lower()):
		return root

	for child in root.get_children():
		var found = _find_node_by_text(child, text)
		if found:
			return found

	return null

# ═══════════════════════════════════════════════════════════════════
# CAMPFIRE / HEALING
# ═══════════════════════════════════════════════════════════════════

func _find_campfire(radius: float) -> Dictionary:
	"""Find the nearest campfire within radius"""
	var campfires := []
	var pos = player.global_position if player else Vector2.ZERO

	for node in get_tree().get_nodes_in_group("campfire"):
		if not is_instance_valid(node):
			continue
		var d = node.global_position.distance_to(pos)
		if d <= radius:
			campfires.append({
				id = node.get_instance_id(),
				name = node.name,
				x = node.global_position.x,
				y = node.global_position.y,
				dist = d,
				is_lit = not node.get("is_unlit") if "is_unlit" in node else true
			})

	# Also check for Campfire class directly
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is Campfire or node.name.to_lower().contains("campfire"):
			if not is_instance_valid(node):
				continue
			var d = node.global_position.distance_to(pos)
			if d <= radius:
				# Check if already added
				var already_added = false
				for c in campfires:
					if c.id == node.get_instance_id():
						already_added = true
						break
				if not already_added:
					campfires.append({
						id = node.get_instance_id(),
						name = node.name,
						x = node.global_position.x,
						y = node.global_position.y,
						dist = d,
						is_lit = not node.get("is_unlit") if "is_unlit" in node else true
					})

	campfires.sort_custom(func(a, b): return a.dist < b.dist)
	return {campfires = campfires, count = campfires.size()}

func _cmd_goto_campfire() -> Dictionary:
	"""Walk to nearest campfire for healing"""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	# Find nearest campfire
	var campfire_result = _find_campfire(1000.0)
	if campfire_result.count == 0:
		return {error = "No campfire found nearby"}

	var nearest = campfire_result.campfires[0]
	_campfire_target = instance_from_id(nearest.id)
	if not is_instance_valid(_campfire_target):
		return {error = "Campfire no longer valid"}

	# Stop combat and start walking to campfire
	_auto_combat = false
	_combat_target = null
	_is_healing = true
	_move_target = _campfire_target.global_position
	_is_pathing = true

	return {
		ok = true,
		campfire = {
			name = nearest.name,
			x = nearest.x,
			y = nearest.y,
			dist = nearest.dist
		}
	}

func _cmd_fuel_campfire(amount: int = 1) -> Dictionary:
	"""Add bone embers to the nearest campfire as fuel"""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	# Find nearest campfire
	var campfire_result = _find_campfire(200.0)  # Must be close to fuel
	if campfire_result.count == 0:
		return {error = "No campfire nearby (must be within 200 units)"}

	var nearest = campfire_result.campfires[0]
	var campfire = instance_from_id(nearest.id)
	if not is_instance_valid(campfire):
		return {error = "Campfire no longer valid"}

	# Check if campfire has fuel method
	if not campfire.has_method("add_bone_ember_fuel"):
		return {error = "Campfire does not support fueling"}

	# Check inventory for bone embers
	var bone_embers = 0
	if InventorySystem:
		for item in InventorySystem.inventory:
			if item.get("name") == "Bone Ember":
				bone_embers = item.get("quantity", 0)
				break

	if bone_embers < amount:
		return {error = "Not enough Bone Embers (have %d, need %d)" % [bone_embers, amount]}

	# Add fuel to campfire
	var added = 0
	for i in range(amount):
		if campfire.add_bone_ember_fuel(1):
			added += 1
			# Remove from inventory
			if InventorySystem and InventorySystem.has_method("remove_item_by_name"):
				InventorySystem.remove_item_by_name("Bone Ember", 1)
		else:
			break

	return {
		ok = true,
		fuel_added = added,
		campfire = nearest.name
	}

func _get_player_hp_percent() -> float:
	"""Get player HP as a percentage (0.0 to 1.0)"""
	if not player:
		player = _find_player()
	if not player:
		return 1.0

	var hp = 100.0
	var max_hp = 100.0

	if "current_health" in player:
		hp = player.current_health
		max_hp = player.max_health if "max_health" in player else 100.0
	elif "current_hp" in player:
		hp = player.current_hp
		max_hp = player.max_hp if "max_hp" in player else 100.0

	return hp / max_hp if max_hp > 0 else 1.0

# ═══════════════════════════════════════════════════════════════════
# FORGE ITEMS
# ═══════════════════════════════════════════════════════════════════

func _get_forge_items(item_type: String) -> Dictionary:
	"""Get forge items from ForgeItemDB, optionally filtered by type"""
	if not has_node("/root/ForgeItemDB"):
		return {error = "ForgeItemDB not available"}

	var db = get_node("/root/ForgeItemDB")
	var items := []

	# Get items by type if specified
	if not item_type.is_empty():
		var type_enum = -1
		match item_type.to_lower():
			"weapon":
				type_enum = db.ItemType.WEAPON
			"shield":
				type_enum = db.ItemType.SHIELD
			"armor_head", "head", "helmet":
				type_enum = db.ItemType.ARMOR_HEAD
			"armor_chest", "chest":
				type_enum = db.ItemType.ARMOR_CHEST
			"armor_arms", "arms":
				type_enum = db.ItemType.ARMOR_ARMS
			"armor_legs", "legs":
				type_enum = db.ItemType.ARMOR_LEGS
			"armor_hands", "hands", "gloves":
				type_enum = db.ItemType.ARMOR_HANDS
			"armor_feet", "feet", "boots":
				type_enum = db.ItemType.ARMOR_FEET
			"cape":
				type_enum = db.ItemType.CAPE
			"accessory":
				type_enum = db.ItemType.ACCESSORY
			"ring":
				type_enum = db.ItemType.RING
			"amulet":
				type_enum = db.ItemType.AMULET

		if type_enum >= 0 and db.has_method("get_items_by_type"):
			var type_items = db.get_items_by_type(type_enum)
			for item in type_items:
				items.append(_format_forge_item(item))
	else:
		# Return all items
		if "_items_by_id" in db:
			for item_id in db._items_by_id:
				var item = db._items_by_id[item_id]
				items.append(_format_forge_item(item))

	return {items = items, count = items.size(), filter = item_type}

func _format_forge_item(item: Dictionary) -> Dictionary:
	"""Format a forge item for API response"""
	return {
		id = item.get("item_id", ""),
		name = item.get("item_name", "Unknown"),
		description = item.get("description", ""),
		type = item.get("item_type", 0),
		rarity = item.get("rarity", 0),
		weapon_type = item.get("weapon_type", ""),
		cosmetic_only = item.get("cosmetic_only", true)
	}

# ═══════════════════════════════════════════════════════════════════════════
# CORPSE / LOOT DEBUG
# ═══════════════════════════════════════════════════════════════════════════

func _get_nearby_corpses(radius: float) -> Dictionary:
	"""Get nearby corpses and their loot state for debugging"""
	var corpses := []
	var bones := []
	var pos = player.global_position if player else Vector2.ZERO

	# Check corpses group
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d <= radius:
			var loot_count = 0
			var gold = 0
			if "corpse_loot" in corpse:
				loot_count = corpse.corpse_loot.size()
			if "corpse_gold" in corpse:
				gold = corpse.corpse_gold
			corpses.append({
				name = corpse.name,
				x = corpse.global_position.x,
				y = corpse.global_position.y,
				dist = d,
				gold = gold,
				loot_count = loot_count,
				is_corpse = corpse.get("is_corpse") if "is_corpse" in corpse else true
			})

	# Check pickable bones
	for bone in get_tree().get_nodes_in_group("pickable_bones"):
		if not is_instance_valid(bone):
			continue
		var d = bone.global_position.distance_to(pos)
		if d <= radius:
			bones.append({
				name = bone.name,
				x = bone.global_position.x,
				y = bone.global_position.y,
				dist = d
			})

	corpses.sort_custom(func(a, b): return a.dist < b.dist)
	bones.sort_custom(func(a, b): return a.dist < b.dist)
	return {corpses = corpses, bones = bones, corpse_count = corpses.size(), bone_count = bones.size()}

func _cmd_loot_all(radius: float) -> Dictionary:
	"""Manually loot all nearby corpses and bones"""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	var pos = player.global_position
	var looted_gold := 0
	var looted_items := []

	# Loot corpses
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d <= radius:
			# Get gold
			if "corpse_gold" in corpse and corpse.corpse_gold > 0:
				looted_gold += corpse.corpse_gold
				CharacterStats.gold += corpse.corpse_gold
				corpse.corpse_gold = 0

			# Get items
			if "corpse_loot" in corpse:
				while corpse.corpse_loot.size() > 0:
					var item = corpse.corpse_loot[0]
					if InventorySystem and InventorySystem.has_method("add_item"):
						if InventorySystem.add_item(item):
							looted_items.append(item.get("name", "Unknown"))
							corpse.corpse_loot.remove_at(0)
						else:
							break  # Inventory full
					else:
						break

			# Check if empty
			if corpse.has_method("check_if_looted_empty"):
				corpse.check_if_looted_empty()

	# Loot bones
	for bone in get_tree().get_nodes_in_group("pickable_bones"):
		if not is_instance_valid(bone):
			continue
		var d = bone.global_position.distance_to(pos)
		if d <= radius:
			if bone.has_method("pick_up_item"):
				bone.pick_up_item()
				looted_items.append("Bone Ember")

	return {
		ok = true,
		gold = looted_gold,
		items = looted_items,
		item_count = looted_items.size()
	}

# ═══════════════════════════════════════════════════════════════════════════
# TUTORIAL SKIP
# ═══════════════════════════════════════════════════════════════════════════

func _cmd_skip_tutorial() -> Dictionary:
	"""Skip the tutorial via TutorialManager"""
	var tutorial_mgr = get_node_or_null("/root/TutorialManager")
	if not tutorial_mgr:
		# Try finding it in the scene tree
		for node in get_tree().get_nodes_in_group("tutorial"):
			if node.has_method("skip_tutorial"):
				tutorial_mgr = node
				break

	if not tutorial_mgr:
		# Try to find it as autoload
		if has_node("/root/TutorialManager"):
			tutorial_mgr = get_node("/root/TutorialManager")

	if tutorial_mgr and tutorial_mgr.has_method("skip_tutorial"):
		tutorial_mgr.skip_tutorial()
		return {ok = true, skipped = true}

	return {error = "TutorialManager not found"}

func _cmd_close_bug_report() -> Dictionary:
	"""Close/hide the bug report indicator"""
	var bug_report = get_node_or_null("/root/BugReportUI")
	if bug_report:
		# Hide the indicator container if it exists
		if "indicator_container" in bug_report and bug_report.indicator_container:
			bug_report.indicator_container.visible = false
		# Also hide the main layer
		bug_report.visible = false
		return {ok = true, closed = true}

	return {error = "BugReportUI not found"}

# ═══════════════════════════════════════════════════════════════════════════
# DEATH TRACKING & RETURN TO CORPSE
# ═══════════════════════════════════════════════════════════════════════════

func _track_player_for_death():
	"""Track player position continuously so we know where they died"""
	if not player or not is_instance_valid(player):
		return

	# Only update if player has gear equipped (worth returning for)
	var has_gear = false
	if CharacterStats:
		# Check if wearing armor or weapon
		if "equipped_weapon" in CharacterStats and CharacterStats.equipped_weapon:
			has_gear = true
		if "equipped_armor" in CharacterStats:
			for slot in CharacterStats.equipped_armor:
				if CharacterStats.equipped_armor[slot]:
					has_gear = true
					break

	# Track position if we're away from spawn and have gear
	var spawn_pos = Vector2(-6000, 0)  # Default spawn
	var dist_from_spawn = player.global_position.distance_to(spawn_pos)
	if dist_from_spawn > 100 and has_gear:
		_last_death_position = player.global_position
		_had_gear_on_death = has_gear
		_death_time = Time.get_ticks_msec()

func _cmd_return_to_corpse() -> Dictionary:
	"""Return to last death position to recover gear/loot"""
	if not ai_controlled:
		return {error = "Not in AI control mode"}

	player = _find_player()
	if not player:
		return {error = "No player found"}

	# Check if we have a valid death position
	if _last_death_position == Vector2.ZERO:
		return {error = "No death position recorded"}

	# Check if death was recent (within 5 minutes)
	var time_since_death = Time.get_ticks_msec() - _death_time
	if time_since_death > 300000:  # 5 minutes
		return {error = "Death too long ago (%.0f seconds)" % (time_since_death / 1000.0)}

	# Start moving to death position WITH auto-combat for self-defense!
	# This is safer than just running blindly
	_move_target = _last_death_position
	_is_pathing = true
	# ENABLE combat - we need to defend ourselves during corpse run
	# But we prioritize pathing, not hunting enemies
	_auto_combat = false  # Start with no aggro, but threat detection in _update_pathing will engage

	return {
		ok = true,
		target = {
			x = _last_death_position.x,
			y = _last_death_position.y
		},
		had_gear = _had_gear_on_death,
		time_since_death = time_since_death / 1000.0,
		note = "THREAT_DETECTION_ENABLED - will engage enemies within 80 range"
	}

func _try_loot_if_safe() -> int:
	"""Loot nearby corpses ONLY if no enemies are close. Returns count looted."""
	if not player:
		return 0

	# Check for nearby threats first
	var threat_count = _count_nearby_threats(SAFE_LOOT_RADIUS)
	if threat_count > 0:
		print("[MCPBridge] %d threats within %.0f - skipping loot" % [threat_count, SAFE_LOOT_RADIUS])
		return 0

	# Safe to loot!
	return _try_loot_nearby()

func _count_nearby_threats(radius: float) -> int:
	"""Count living enemies within radius"""
	var count := 0
	var pos = player.global_position if player else Vector2.ZERO

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip Training Dummies - they're not real threats
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		if "current_health" in e and e.current_health <= 0:
			continue
		if "current_hp" in e and e.current_hp <= 0:
			continue

		var d = e.global_position.distance_to(pos)
		if d <= radius:
			count += 1

	return count

func _get_threat_status() -> Dictionary:
	"""Get current threat/aggro status for AI decision making"""
	player = _find_player()
	if not player:
		return {error = "No player found"}

	var pos = player.global_position
	var threats := []
	var total_threat := 0

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip Training Dummies - they're not real threats
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue

		var hp = _get_enemy_hp(e)
		if hp <= 0:
			continue

		var d = e.global_position.distance_to(pos)
		if d <= AGGRO_DETECTION_RADIUS:
			# Check if enemy is targeting us
			var is_targeting := false
			if "current_target" in e and e.current_target == player:
				is_targeting = true
			elif "target" in e and e.target == player:
				is_targeting = true
			elif "aggro_target" in e and e.aggro_target == player:
				is_targeting = true

			threats.append({
				name = e.name,
				dist = d,
				hp = hp,
				is_targeting = is_targeting,
				x = e.global_position.x,
				y = e.global_position.y
			})
			total_threat += 1

	threats.sort_custom(func(a, b): return a.dist < b.dist)

	var safe_to_loot = total_threat == 0 or (threats.size() > 0 and threats[0].dist > SAFE_LOOT_RADIUS)

	# Check for lava hazards
	var in_lava = _check_lava_hazard()

	return {
		threats = threats,
		threat_count = total_threat,
		safe_to_loot = safe_to_loot,
		nearest_dist = threats[0].dist if threats.size() > 0 else -1,
		player_hp_percent = _get_player_hp_percent() * 100,
		in_lava = in_lava
	}

# ═══════════════════════════════════════════════════════════════════
# TACTICAL AWARENESS SYSTEM
# ═══════════════════════════════════════════════════════════════════

func _get_tactical_status() -> Dictionary:
	"""Full situational awareness - everything needed to make smart combat decisions"""
	player = _find_player()
	if not player:
		return {error = "No player found"}

	var pos = player.global_position
	var hp_percent = _get_player_hp_percent()

	# ═══ PLAYER STATUS ═══
	var player_hp = 0.0
	var player_max_hp = 100.0
	if "current_health" in player:
		player_hp = player.current_health
		player_max_hp = player.max_health if "max_health" in player else 100.0

	# ═══ GEAR STATUS ═══
	var gear_slots := {
		weapon = null,
		head = null,
		chest = null,
		arms = null,
		legs = null,
		feet = null,
		hands = null,
		offhand = null
	}
	var empty_slots := []

	# Check equipped weapon (stored in CharacterStats autoload)
	if CharacterStats.equipped_weapon:
		var w = CharacterStats.equipped_weapon
		gear_slots.weapon = w.name if "name" in w else (w.weapon_type if "weapon_type" in w else "equipped")
	else:
		empty_slots.append("weapon")

	# Check armor slots (stored in CharacterStats autoload)
	if CharacterStats.equipped_armor:
		for slot in ["head", "chest", "arms", "legs", "feet", "hands", "offhand"]:
			if CharacterStats.equipped_armor.has(slot) and CharacterStats.equipped_armor[slot]:
				var a = CharacterStats.equipped_armor[slot]
				gear_slots[slot] = a.name if "name" in a else "equipped"
			else:
				empty_slots.append(slot)
	else:
		empty_slots = ["head", "chest", "arms", "legs", "feet", "hands", "offhand"]

	var player_status := {
		hp = player_hp,
		max_hp = player_max_hp,
		hp_percent = hp_percent * 100,
		x = pos.x,
		y = pos.y,
		gold = player.gold if "gold" in player else 0,
		gear = gear_slots,
		empty_slots = empty_slots
	}

	# ═══ ENEMY ANALYSIS ═══
	var enemies_in_range := []  # All enemies within engagement range
	var enemies_targeting := []  # Enemies actively targeting player (aggro)
	var enemy_clusters := []  # Groups of enemies close together

	const SCAN_RADIUS := 600.0  # How far to scan for enemies
	const CLUSTER_RADIUS := 150.0  # Enemies within this distance are "grouped"
	const AGGRO_CHECK_RADIUS := 300.0  # Check for active aggro within this range

	var all_enemies := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		# Skip Training Dummies
		if "trainingdummy" in e.name.to_lower() or "training" in e.name.to_lower():
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var hp = _get_enemy_hp(e)
		if hp <= 0:
			continue

		var d = e.global_position.distance_to(pos)
		if d > SCAN_RADIUS:
			continue

		var is_targeting := _is_enemy_targeting_player(e)
		var enemy_data := {
			id = e.get_instance_id(),
			name = e.name,
			hp = hp,
			dist = d,
			x = e.global_position.x,
			y = e.global_position.y,
			is_targeting = is_targeting
		}

		all_enemies.append(enemy_data)
		if is_targeting:
			enemies_targeting.append(enemy_data)

	# Sort by distance
	all_enemies.sort_custom(func(a, b): return a.dist < b.dist)

	# ═══ CLUSTER ANALYSIS ═══
	# Find groups of enemies that are close together (dangerous to engage)
	var processed := {}
	for i in range(all_enemies.size()):
		if processed.has(i):
			continue
		var cluster := [all_enemies[i]]
		processed[i] = true

		for j in range(i + 1, all_enemies.size()):
			if processed.has(j):
				continue
			# Check if enemy j is close to any enemy in the cluster
			var e_pos = Vector2(all_enemies[j].x, all_enemies[j].y)
			for c in cluster:
				var c_pos = Vector2(c.x, c.y)
				if e_pos.distance_to(c_pos) < CLUSTER_RADIUS:
					cluster.append(all_enemies[j])
					processed[j] = true
					break

		if cluster.size() >= 2:
			var center = Vector2.ZERO
			for c in cluster:
				center += Vector2(c.x, c.y)
			center /= cluster.size()

			enemy_clusters.append({
				count = cluster.size(),
				center_x = center.x,
				center_y = center.y,
				dist = center.distance_to(pos),
				members = cluster.map(func(c): return c.name)
			})

	# ═══ ISOLATED TARGETS ═══
	# Find enemies that are alone (safe to engage)
	var isolated_targets := []
	for e in all_enemies:
		var e_pos = Vector2(e.x, e.y)
		var nearby_count := 0
		for other in all_enemies:
			if other.id == e.id:
				continue
			var other_pos = Vector2(other.x, other.y)
			if e_pos.distance_to(other_pos) < CLUSTER_RADIUS:
				nearby_count += 1

		if nearby_count == 0:
			isolated_targets.append(e)

	# ═══ LOOT ON GROUND ═══
	var loot_nearby := []
	for item in get_tree().get_nodes_in_group("loot"):
		if not is_instance_valid(item):
			continue
		var d = item.global_position.distance_to(pos)
		if d <= 200.0:
			loot_nearby.append({
				name = item.item_name if "item_name" in item else "item",
				dist = d,
				x = item.global_position.x,
				y = item.global_position.y
			})
	loot_nearby.sort_custom(func(a, b): return a.dist < b.dist)

	# ═══ CORPSES TO LOOT ═══
	var corpses_nearby := []
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d <= 300.0:  # Check wider range for corpses
			var loot_count = 0
			var gold = 0
			if "corpse_loot" in corpse:
				loot_count = corpse.corpse_loot.size()
			if "corpse_gold" in corpse:
				gold = corpse.corpse_gold
			# Only include if has loot or gold
			if loot_count > 0 or gold > 0:
				corpses_nearby.append({
					name = corpse.name,
					dist = d,
					x = corpse.global_position.x,
					y = corpse.global_position.y,
					gold = gold,
					loot_count = loot_count
				})
	corpses_nearby.sort_custom(func(a, b): return a.dist < b.dist)

	# ═══ PICKABLE BONES (Bone Embers for quest) ═══
	var bones_nearby := []
	for bone in get_tree().get_nodes_in_group("pickable_bones"):
		if not is_instance_valid(bone):
			continue
		var d = bone.global_position.distance_to(pos)
		if d <= 300.0:
			bones_nearby.append({
				name = bone.name,
				dist = d,
				x = bone.global_position.x,
				y = bone.global_position.y
			})
	bones_nearby.sort_custom(func(a, b): return a.dist < b.dist)

	# ═══ CAMPFIRE STATUS ═══
	var campfire_info := {found = false, dist = -1, x = 0, y = 0, is_lit = false}
	var campfire_result = _find_campfire(800.0)
	if campfire_result.count > 0:
		var c = campfire_result.campfires[0]
		campfire_info = {
			found = true,
			dist = c.dist,
			x = c.x,
			y = c.y,
			is_lit = c.is_lit
		}

	# ═══ HAZARDS (LAVA) ═══
	var hazards_nearby := []
	var in_lava := _check_lava_hazard()
	var nearest_lava = _find_nearest_lava()
	if nearest_lava:
		var lava_dist = nearest_lava.global_position.distance_to(pos)
		if lava_dist < 300.0:  # Show hazards within 300 units
			hazards_nearby.append({
				type = "lava",
				dist = lava_dist,
				x = nearest_lava.global_position.x,
				y = nearest_lava.global_position.y
			})

	# ═══ THREAT ASSESSMENT ═══
	var threat_level := "safe"
	var aggro_count = enemies_targeting.size()
	var nearest_enemy_dist = all_enemies[0].dist if all_enemies.size() > 0 else 999

	if hp_percent < 0.3:
		threat_level = "critical"
	elif aggro_count >= 3:
		threat_level = "danger"
	elif aggro_count >= 2 or (aggro_count >= 1 and hp_percent < 0.5):
		threat_level = "caution"
	elif aggro_count >= 1 or nearest_enemy_dist < 150:
		threat_level = "combat"
	else:
		threat_level = "safe"

	# ═══ RECOMMENDED ACTION ═══
	var recommendation := "explore"
	var rec_target = null
	var has_lootables = corpses_nearby.size() > 0 or bones_nearby.size() > 0 or loot_nearby.size() > 0

	# PRIORITY: Escape hazards first!
	if in_lava:
		recommendation = "escape_hazard"  # GET OUT OF LAVA NOW!
	elif threat_level == "critical":
		recommendation = "retreat"  # Run to campfire NOW
	elif threat_level == "danger":
		recommendation = "kite"  # Back away while fighting, reduce aggro
	elif aggro_count > 0:
		recommendation = "fight"  # Finish current fight
	elif has_lootables and threat_level == "safe":
		recommendation = "loot"  # Safe to loot corpses/bones/items
	elif isolated_targets.size() > 0:
		recommendation = "engage"
		rec_target = isolated_targets[0]  # Suggest engaging isolated enemy
	elif hp_percent < 0.9 and campfire_info.found and campfire_info.is_lit:
		recommendation = "heal"
	else:
		recommendation = "explore"

	return {
		player = player_status,
		threat_level = threat_level,
		aggro_count = aggro_count,
		enemies_targeting = enemies_targeting,
		enemies_nearby = all_enemies.slice(0, 5),  # Top 5 nearest
		total_enemies_in_range = all_enemies.size(),
		clusters = enemy_clusters,
		isolated_targets = isolated_targets.slice(0, 3),  # Top 3 safe targets
		corpses = corpses_nearby,  # Corpses with loot/gold
		bones = bones_nearby,  # Pickable bones (quest items)
		loot = loot_nearby,  # Dropped items
		hazards = hazards_nearby,  # Lava pools and other hazards
		in_hazard = in_lava,  # Currently standing in hazard?
		campfire = campfire_info,
		recommendation = recommendation,
		recommended_target = rec_target
	}

func _is_enemy_targeting_player(enemy: Node2D) -> bool:
	"""Check if an enemy is actively targeting the player"""
	if not player:
		return false

	# Check various targeting properties
	if "current_target" in enemy and enemy.current_target == player:
		return true
	if "target" in enemy and enemy.target == player:
		return true
	if "aggro_target" in enemy and enemy.aggro_target == player:
		return true

	# Check AI node if exists
	if enemy.has_node("EnemyAI"):
		var ai = enemy.get_node("EnemyAI")
		if is_instance_valid(ai):
			if ai.get("player") == player and ai.get("is_in_combat"):
				return true

	return false

func _cmd_smart_engage(enemy_id: int) -> Dictionary:
	"""Smart engagement - approach enemy carefully, check for adds"""
	player = _find_player()
	if not player:
		return {error = "No player found"}

	if enemy_id == 0:
		return {error = "No enemy ID provided"}

	# Find the target
	var target: Node2D = instance_from_id(enemy_id)
	if not is_instance_valid(target):
		return {error = "Enemy not found"}

	var target_pos = target.global_position
	var player_pos = player.global_position

	# Check for nearby enemies that might aggro
	const AGGRO_RANGE := 200.0
	var potential_adds := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e == target:
			continue
		if "trainingdummy" in e.name.to_lower():
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		if _get_enemy_hp(e) <= 0:
			continue

		var d = e.global_position.distance_to(target_pos)
		if d < AGGRO_RANGE:
			potential_adds.append({
				name = e.name,
				dist_to_target = d
			})

	# Calculate approach position (stop before reaching, to pull)
	var direction = (target_pos - player_pos).normalized()
	var approach_dist = 100.0  # Stop 100 units away from target
	var approach_pos = target_pos - direction * approach_dist

	# Start moving to approach position
	_move_target = approach_pos
	_is_pathing = true

	# Set up combat after reaching position
	_combat_target = target
	_auto_combat = true

	return {
		ok = true,
		target = {
			name = target.name,
			hp = _get_enemy_hp(target),
			dist = player_pos.distance_to(target_pos)
		},
		approach_position = {
			x = approach_pos.x,
			y = approach_pos.y
		},
		potential_adds = potential_adds,
		warning = "Careful! %d enemies nearby" % potential_adds.size() if potential_adds.size() > 0 else null
	}

func _cmd_loot_phase() -> Dictionary:
	"""Safe loot phase - loot all nearby corpses, bones, and items if safe"""
	player = _find_player()
	if not player:
		return {error = "No player found"}

	var pos = player.global_position
	var looted := {corpses = 0, bones = 0, items = 0, gold = 0}

	# First check for threats
	var threat_count = _count_nearby_threats(SAFE_LOOT_RADIUS)
	if threat_count > 0:
		return {
			error = "Not safe to loot",
			threat_count = threat_count,
			safe_radius = SAFE_LOOT_RADIUS
		}

	# Loot corpses
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d > 150.0:  # Must be close to loot
			continue

		# Try to interact with corpse
		if corpse.has_method("interact"):
			var gold_before = player.gold if "gold" in player else 0
			corpse.interact(player)
			var gold_after = player.gold if "gold" in player else 0
			looted.corpses += 1
			looted.gold += (gold_after - gold_before)
		elif corpse.has_method("loot"):
			corpse.loot(player)
			looted.corpses += 1

	# Pick up bones (quest items like Bone Embers)
	for bone in get_tree().get_nodes_in_group("pickable_bones"):
		if not is_instance_valid(bone):
			continue
		var d = bone.global_position.distance_to(pos)
		if d > 100.0:
			continue

		if bone.has_method("pickup"):
			bone.pickup(player)
			looted.bones += 1
		elif bone.has_method("_on_body_entered"):
			bone._on_body_entered(player)
			looted.bones += 1

	# Collect dropped items
	for item in get_tree().get_nodes_in_group("loot"):
		if not is_instance_valid(item):
			continue
		var d = item.global_position.distance_to(pos)
		if d > 80.0:
			continue

		if item.has_method("pickup"):
			item.pickup(player)
			looted.items += 1
		elif item.has_method("_on_pickup_area_body_entered"):
			item._on_pickup_area_body_entered(player)
			looted.items += 1

	var total = looted.corpses + looted.bones + looted.items
	return {
		ok = true,
		looted = looted,
		total_looted = total,
		gold_gained = looted.gold
	}

func _check_lava_hazard() -> bool:
	"""Check if player is standing in or near a lava pool"""
	if not player:
		return false

	var pos = player.global_position
	var lava_range := 80.0  # Distance to consider "in lava"

	# Check for lava pools by group (primary method)
	for lava in get_tree().get_nodes_in_group("lava_pools"):
		if not is_instance_valid(lava):
			continue
		var d = lava.global_position.distance_to(pos)
		if d < lava_range:
			return true

	# Check for CleanseableLavaPool class in interactable group
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is CleanseableLavaPool:
			var d = node.global_position.distance_to(pos)
			if d < lava_range:
				return true

	# Search ALL nodes in scene tree for lava (covers chunked/nested lava pools)
	var all_nodes = _get_all_tree_nodes(get_tree().current_scene)
	for node in all_nodes:
		if not is_instance_valid(node):
			continue
		if node is CleanseableLavaPool:
			var d = node.global_position.distance_to(pos)
			if d < lava_range:
				return true
		elif node is Node2D and ("lava" in node.name.to_lower() or "Lava" in node.name):
			var d = node.global_position.distance_to(pos)
			if d < lava_range:
				return true

	return false

func _get_all_tree_nodes(root: Node) -> Array:
	"""Recursively get all nodes in the tree"""
	var nodes := []
	if not root:
		return nodes
	nodes.append(root)
	for child in root.get_children():
		nodes.append_array(_get_all_tree_nodes(child))
	return nodes

func _find_nearest_lava() -> Node2D:
	"""Find the nearest lava pool to the player"""
	if not player:
		return null

	var pos = player.global_position
	var nearest: Node2D = null
	var nearest_dist := 999999.0

	# Check for lava pools by group (primary method)
	for lava in get_tree().get_nodes_in_group("lava_pools"):
		if not is_instance_valid(lava):
			continue
		var d = lava.global_position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = lava

	# Check for CleanseableLavaPool class in interactable group
	for node in get_tree().get_nodes_in_group("interactable"):
		if node is CleanseableLavaPool:
			var d = node.global_position.distance_to(pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = node

	# Search ALL nodes in scene tree (covers chunked/nested lava pools)
	var all_nodes = _get_all_tree_nodes(get_tree().current_scene)
	for node in all_nodes:
		if not is_instance_valid(node):
			continue
		if node is CleanseableLavaPool:
			var d = node.global_position.distance_to(pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = node
		elif node is Node2D and ("lava" in node.name.to_lower() or "Lava" in node.name):
			var d = node.global_position.distance_to(pos)
			if d < nearest_dist:
				nearest_dist = d
				nearest = node

	return nearest

func _move_out_of_hazard():
	"""Move away from lava/hazard immediately"""
	if not player:
		return

	var lava = _find_nearest_lava()
	if not lava:
		return

	# Calculate escape direction - move AWAY from lava
	var escape_dir = lava.global_position.direction_to(player.global_position)
	if escape_dir.length() < 0.1:
		# We're right on top of it - pick a random direction
		escape_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

	# Move in escape direction
	_release_inputs()
	if escape_dir.x < -0.3: Input.action_press("move_left")
	elif escape_dir.x > 0.3: Input.action_press("move_right")
	if escape_dir.y < -0.3: Input.action_press("move_up")
	elif escape_dir.y > 0.3: Input.action_press("move_down")


# ═══════════════════════════════════════════════════════════════════════════════
# HUMAN-LIKE LOOTING SYSTEM
# These commands create a more natural-looking loot flow:
# walk to corpse -> press F -> wait for UI -> press F (take all) -> wait -> done
# ═══════════════════════════════════════════════════════════════════════════════

func _cmd_human_loot() -> Dictionary:
	"""Start human-like looting: find nearest corpse, walk to it, open UI, take all"""
	if not player:
		return {error = "No player"}
	
	# Find nearest corpse with loot
	var best_corpse: Node2D = null
	var best_dist := 999999.0
	var pos = player.global_position
	
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var has_gold = "corpse_gold" in corpse and corpse.corpse_gold > 0
		var has_items = "corpse_loot" in corpse and corpse.corpse_loot.size() > 0
		if not has_gold and not has_items:
			continue
		var d = corpse.global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_corpse = corpse
	
	if not best_corpse:
		return {error = "No corpses with loot nearby"}
	
	# Start human loot state machine
	_human_loot_state = LootState.WALKING_TO_CORPSE
	_human_loot_target = best_corpse
	_human_loot_timer = 0.0
	
	# Start walking to corpse
	_move_target = best_corpse.global_position
	_is_pathing = true
	
	print("[MCPBridge] Human loot: walking to corpse at (%.0f, %.0f)" % [best_corpse.global_position.x, best_corpse.global_position.y])
	
	return {
		ok = true,
		state = "walking_to_corpse",
		corpse_name = best_corpse.name,
		distance = best_dist
	}

func _cmd_walk_to_corpse() -> Dictionary:
	"""Walk to nearest corpse position (does not open loot UI)"""
	if not player:
		return {error = "No player"}
	
	var best_corpse: Node2D = null
	var best_dist := 999999.0
	var pos = player.global_position
	
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_corpse = corpse
	
	if not best_corpse:
		return {error = "No corpses nearby"}
	
	# Start pathing to corpse
	_move_target = best_corpse.global_position
	_is_pathing = true
	
	return {
		ok = true,
		corpse_name = best_corpse.name,
		corpse_x = best_corpse.global_position.x,
		corpse_y = best_corpse.global_position.y,
		distance = best_dist
	}

func _cmd_open_loot_ui() -> Dictionary:
	"""Simulate pressing F to open loot UI (must be near corpse)"""
	if not player:
		return {error = "No player"}
	
	# Check if LootBodyUI is already open
	var loot_ui = get_node_or_null("/root/LootBodyUI")
	if loot_ui and loot_ui.visible:
		return {ok = true, already_open = true}
	
	# Check if we are near a corpse
	var pos = player.global_position
	var nearest_corpse: Node2D = null
	var nearest_dist := 999999.0
	
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if not is_instance_valid(corpse):
			continue
		var d = corpse.global_position.distance_to(pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest_corpse = corpse
	
	if not nearest_corpse or nearest_dist > 100.0:
		return {error = "Not near any corpse (nearest: %.0f)" % nearest_dist}
	
	# Simulate F key press (interact action)
	Input.action_press("interact")
	get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("interact"))
	
	print("[MCPBridge] Opening loot UI for %s" % nearest_corpse.name)
	
	return {
		ok = true,
		corpse_name = nearest_corpse.name,
		distance = nearest_dist
	}

func _cmd_take_all_loot() -> Dictionary:
	"""Simulate pressing F to take all loot (LootUI must be open)"""
	# Find the LootBodyUI
	var loot_ui = get_node_or_null("/root/LootBodyUI")
	if not loot_ui:
		# Try finding it in the scene tree
		for node in get_tree().get_nodes_in_group("ui"):
			if node.name == "LootBodyUI" or node is LootBodyUI:
				loot_ui = node
				break
	
	if not loot_ui:
		# Last resort: search entire tree
		var root = get_tree().root
		loot_ui = _find_node_by_class(root, "LootBodyUI")
	
	if not loot_ui or not loot_ui.visible:
		return {error = "LootUI not open"}
	
	# Simulate F key press (triggers take_all in LootBodyUI)
	Input.action_press("interact")
	get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("interact"))
	
	print("[MCPBridge] Taking all loot")
	
	return {ok = true, action = "take_all"}

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	"""Recursively find a node by class name"""
	if node.get_class() == class_name_str or node.name == class_name_str:
		return node
	for child in node.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null

func _update_human_loot(delta: float) -> void:
	"""Update human-like loot state machine"""
	if _human_loot_state == LootState.NONE:
		return
	
	if not player:
		_human_loot_state = LootState.NONE
		return
	
	var pos = player.global_position
	
	match _human_loot_state:
		LootState.WALKING_TO_CORPSE:
			# Check if we reached the corpse
			if not is_instance_valid(_human_loot_target):
				print("[MCPBridge] Human loot: corpse despawned")
				_human_loot_state = LootState.NONE
				_is_pathing = false
				return
			
			var dist = pos.distance_to(_human_loot_target.global_position)
			if dist <= HUMAN_LOOT_WALK_RANGE:
				# Arrived! Stop moving and open loot UI
				_is_pathing = false
				_release_inputs()
				print("[MCPBridge] Human loot: arrived at corpse, pressing F")
				
				# Press F to open loot UI
				Input.action_press("interact")
				get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("interact"))
				
				_human_loot_state = LootState.WAITING_FOR_UI
				_human_loot_timer = 0.0
		
		LootState.WAITING_FOR_UI:
			_human_loot_timer += delta
			if _human_loot_timer >= HUMAN_LOOT_UI_WAIT:
				# Check if UI opened
				var loot_ui = _find_node_by_class(get_tree().root, "LootBodyUI")
				if loot_ui and loot_ui.visible:
					print("[MCPBridge] Human loot: UI open, pressing F for Take All")
					# Press F again to take all
					Input.action_press("interact")
					get_tree().create_timer(0.1).timeout.connect(func(): Input.action_release("interact"))
					_human_loot_state = LootState.LOOTING
					_human_loot_timer = 0.0
				else:
					# UI didn't open, maybe corpse was empty
					print("[MCPBridge] Human loot: UI didn't open (corpse empty?)")
					_human_loot_state = LootState.NONE
		
		LootState.LOOTING:
			_human_loot_timer += delta
			if _human_loot_timer >= HUMAN_LOOT_CLOSE_WAIT:
				print("[MCPBridge] Human loot: complete")
				_human_loot_state = LootState.NONE
				_human_loot_target = null

func is_human_looting() -> bool:
	"""Check if currently in human loot process"""
	return _human_loot_state != LootState.NONE

# ═══════════════════════════════════════════════════════════════════
# BOT MANAGER INTEGRATION (stress testing)
# ═══════════════════════════════════════════════════════════════════

func _forward_to_bot_manager(cmd: Dictionary) -> Dictionary:
	"""Forward commands to BotManager for stress testing"""
	# Try to get BotManager if we don't have it
	if not bot_manager:
		bot_manager = get_node_or_null("/root/BotManager")

	if not bot_manager:
		return {error = "BotManager not available (only runs on server)"}

	if not bot_manager.has_method("handle_mcp_command"):
		return {error = "BotManager does not support MCP commands"}

	return bot_manager.handle_mcp_command(cmd)
