extends Node

## Automated Playtest Bot
## Simulates a real player: equips gear, follows quests, fights, gathers, loots
## Toggle with F4 in-game, or launch with --bot flag for headless client

signal bot_error(message: String, context: Dictionary)
signal bot_action(action: String, details: String)
signal bot_connected()
signal bot_spawned()

# References
var player: Node = null
var quest_manager: Node = null
var inventory_system: Node = null
var character_stats: Node = null
var network_manager: Node = null

# State machine
enum BotState {
	IDLE,
	CONNECTING,
	WAITING_FOR_SPAWN,
	EQUIPPING,
	SEEKING_QUEST,
	DOING_QUEST,
	COMBAT,
	LOOTING,
	GATHERING,
	EXPLORING,
	STUCK_RECOVERY
}
var state: BotState = BotState.IDLE
var previous_state: BotState = BotState.IDLE

# Bot control
var enabled := false
var action_timer := 0.0
var state_timer := 0.0
var stuck_timer := 0.0
var last_position := Vector2.ZERO

# Headless/network mode
var headless_mode := false
var server_address := "127.0.0.1"
var server_port := 7000
var bot_name := "TestBot"
var connection_timeout := 10.0
var spawn_wait_timer := 0.0

# Quest tracking
var current_quest_id: String = ""
var current_objective_index: int = 0

# Targets
var target_enemy: Node = null
var target_loot: Node = null
var target_resource: Node = null
var target_position: Vector2 = Vector2.ZERO

# Configuration
const ACTION_INTERVAL := 0.15
const STUCK_THRESHOLD := 4.0
const COMBAT_RANGE := 80.0
const LOOT_RANGE := 100.0
const GATHER_RANGE := 60.0
const WANDER_RADIUS := 300.0

# Error tracking
var error_log: Array = []
var action_log: Array = []
const MAX_LOG_SIZE := 500

func _ready():
	# Check for command line args
	_parse_command_line()

	if headless_mode:
		print("[PlaytestBot] HEADLESS MODE - Connecting to %s:%d as %s" % [server_address, server_port, bot_name])
		call_deferred("_start_headless_connection")
	else:
		print("[PlaytestBot] Initialized - Press F4 to toggle")

	set_process(false)

func _parse_command_line():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--bot":
			headless_mode = true
			enabled = true
		elif arg == "--bot-server" and i + 1 < args.size():
			server_address = args[i + 1]
		elif arg == "--bot-port" and i + 1 < args.size():
			server_port = int(args[i + 1])
		elif arg == "--bot-name" and i + 1 < args.size():
			bot_name = args[i + 1]

func _start_headless_connection():
	network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		_log_error("NetworkManager not found", {})
		return

	# Connect signals
	network_manager.connected_to_server.connect(_on_connected_to_server)
	network_manager.connection_failed.connect(_on_connection_failed)
	network_manager.login_success.connect(_on_login_success)
	network_manager.login_failed.connect(_on_login_failed)

	# Start connection
	_enter_state(BotState.CONNECTING)
	set_process(true)

	var success = network_manager.join_game(server_address, server_port)
	if not success:
		_log_error("Failed to initiate connection", {"address": server_address, "port": server_port})

func _on_connected_to_server():
	_log_action("NETWORK", "Connected to server, sending guest login...")
	network_manager.send_guest_login(bot_name)

func _on_connection_failed():
	_log_error("Connection failed", {"address": server_address, "port": server_port})
	_enter_state(BotState.IDLE)
	enabled = false

func _on_login_success(player_data: Dictionary):
	_log_action("NETWORK", "Logged in as %s" % player_data.get("character_name", bot_name))
	bot_connected.emit()
	_enter_state(BotState.WAITING_FOR_SPAWN)
	spawn_wait_timer = 0.0

func _on_login_failed(error: String):
	_log_error("Login failed", {"error": error})
	_enter_state(BotState.IDLE)
	enabled = false

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		toggle_bot()

func toggle_bot():
	enabled = !enabled
	set_process(enabled)

	if enabled:
		_initialize_references()
		if player:
			print("[PlaytestBot] ENABLED - Beginning automated playtest")
			_log_action("BOT_START", "Playtest bot activated")
			state = BotState.EQUIPPING
		else:
			print("[PlaytestBot] ERROR - Could not find player node")
			enabled = false
	else:
		print("[PlaytestBot] DISABLED")
		_log_action("BOT_STOP", "Playtest bot deactivated")

func _initialize_references():
	player = get_tree().get_first_node_in_group("player")
	if not player:
		_log_error("No player found in 'player' group", {})
		return

	# Try to get systems from player or autoloads
	quest_manager = _find_system("QuestManager")
	inventory_system = _find_system("InventorySystem")
	character_stats = _find_system("CharacterStats")

	if not quest_manager:
		_log_error("QuestManager not found", {})
	if not inventory_system:
		_log_error("InventorySystem not found", {})
	if not character_stats:
		_log_error("CharacterStats not found", {})

func _find_system(system_name: String) -> Node:
	# Try autoload first
	if has_node("/root/" + system_name):
		return get_node("/root/" + system_name)
	# Try player child
	if player and player.has_node(system_name):
		return player.get_node(system_name)
	# Try player property
	if player and system_name.to_snake_case() in player:
		return player.get(system_name.to_snake_case())
	return null

func _process(delta):
	if not enabled or not player:
		return

	action_timer -= delta
	state_timer += delta

	_check_stuck(delta)

	if action_timer <= 0:
		action_timer = ACTION_INTERVAL
		_update_state()
		_execute_state()

func _check_stuck(delta):
	var current_pos = player.global_position
	if current_pos.distance_to(last_position) < 3:
		stuck_timer += delta
		if stuck_timer > STUCK_THRESHOLD:
			_log_error("Bot stuck", {"position": current_pos, "state": BotState.keys()[state]})
			_enter_state(BotState.STUCK_RECOVERY)
			stuck_timer = 0
	else:
		stuck_timer = 0
		last_position = current_pos

func _enter_state(new_state: BotState):
	previous_state = state
	state = new_state
	state_timer = 0
	_log_action("STATE_CHANGE", "%s -> %s" % [BotState.keys()[previous_state], BotState.keys()[new_state]])

func _update_state():
	# Handle network states first
	match state:
		BotState.CONNECTING:
			if state_timer > connection_timeout:
				_log_error("Connection timeout", {})
				enabled = false
			return

		BotState.WAITING_FOR_SPAWN:
			spawn_wait_timer += ACTION_INTERVAL
			# Try to find our player
			player = _find_local_player()
			if player:
				_log_action("SPAWN", "Player spawned, initializing systems...")
				_initialize_references()
				bot_spawned.emit()
				_enter_state(BotState.EQUIPPING)
			elif spawn_wait_timer > 30.0:
				_log_error("Spawn timeout - player not found", {})
				enabled = false
			return

	# Need player for gameplay states
	if not player or not is_instance_valid(player):
		player = _find_local_player()
		if not player:
			return

	# Priority-based state transitions

	# 1. Check for nearby enemies (combat priority)
	var nearby_enemy = _find_nearest_enemy()
	if nearby_enemy and state != BotState.COMBAT:
		target_enemy = nearby_enemy
		_enter_state(BotState.COMBAT)
		return

	# 2. Check for lootable corpses
	var nearby_loot = _find_nearest_loot()
	if nearby_loot and state != BotState.LOOTING and state != BotState.COMBAT:
		target_loot = nearby_loot
		_enter_state(BotState.LOOTING)
		return

	# 3. State-specific updates
	match state:
		BotState.EQUIPPING:
			if state_timer > 2.0:  # Done equipping
				_enter_state(BotState.SEEKING_QUEST)

		BotState.COMBAT:
			if not is_instance_valid(target_enemy) or not target_enemy.is_inside_tree():
				target_enemy = null
				_enter_state(previous_state if previous_state != BotState.COMBAT else BotState.DOING_QUEST)

		BotState.LOOTING:
			if not is_instance_valid(target_loot):
				target_loot = null
				_enter_state(BotState.DOING_QUEST)

		BotState.STUCK_RECOVERY:
			if state_timer > 1.5:
				_enter_state(BotState.EXPLORING)

		BotState.EXPLORING:
			if state_timer > 5.0:
				_enter_state(BotState.SEEKING_QUEST)

func _find_local_player() -> Node:
	"""Find the local player node (works for both host and client)"""
	# In multiplayer, find the player with our peer ID
	if network_manager and network_manager.multiplayer:
		var my_id = network_manager.multiplayer.get_unique_id()
		var players = get_tree().get_nodes_in_group("player")
		for p in players:
			if "peer_id" in p and p.peer_id == my_id:
				return p
			# Also check name pattern
			if p.name.ends_with(str(my_id)):
				return p

	# Fallback: single player or first player
	return get_tree().get_first_node_in_group("player")

func _execute_state():
	match state:
		BotState.IDLE:
			_do_idle()
		BotState.EQUIPPING:
			_do_equip_best_gear()
		BotState.SEEKING_QUEST:
			_do_seek_quest()
		BotState.DOING_QUEST:
			_do_quest_objective()
		BotState.COMBAT:
			_do_combat()
		BotState.LOOTING:
			_do_loot()
		BotState.GATHERING:
			_do_gather()
		BotState.EXPLORING:
			_do_explore()
		BotState.STUCK_RECOVERY:
			_do_unstuck()

# ============ STATE IMPLEMENTATIONS ============

func _do_idle():
	# Brief pause, then start doing something
	if state_timer > 1.0:
		_enter_state(BotState.EQUIPPING)

func _do_equip_best_gear():
	if not inventory_system or not character_stats:
		_enter_state(BotState.SEEKING_QUEST)
		return

	# Find and equip best gear from inventory
	var inventory = _get_inventory_items()
	for item in inventory:
		if item.get("type") == "armor":
			var slot = item.get("slot", "")
			var current = _get_equipped_armor(slot)
			if not current or item.get("defense", 0) > current.get("defense", 0):
				_equip_item(item)
				_log_action("EQUIP", "Equipped %s" % item.get("name", "unknown"))

		elif item.get("type") == "weapon":
			# Equip if no weapon or better damage
			var current_weapon = _get_equipped_armor("mainhand")
			if not current_weapon or item.get("base_damage", 0) > current_weapon.get("base_damage", 0):
				_equip_item(item)
				_log_action("EQUIP", "Equipped weapon %s" % item.get("name", "unknown"))

		elif item.get("tool_type") == "axe":
			if inventory_system.has_method("equip_axe"):
				inventory_system.equip_axe(item)
				_log_action("EQUIP", "Equipped axe %s" % item.get("name", "unknown"))

		elif item.get("tool_type") == "pickaxe":
			if inventory_system.has_method("equip_pickaxe"):
				inventory_system.equip_pickaxe(item)
				_log_action("EQUIP", "Equipped pickaxe %s" % item.get("name", "unknown"))

func _do_seek_quest():
	if not quest_manager:
		_enter_state(BotState.EXPLORING)
		return

	# Check for active quests first
	var active_quests = _get_active_quests()
	if active_quests.size() > 0:
		current_quest_id = active_quests[0]
		_log_action("QUEST", "Continuing quest: %s" % current_quest_id)
		_enter_state(BotState.DOING_QUEST)
		return

	# Try to accept available quest
	var available = _get_available_quests()
	if available.size() > 0:
		var quest_id = available[0]
		if quest_manager.has_method("accept_quest"):
			var accepted = quest_manager.accept_quest(quest_id)
			if accepted:
				current_quest_id = quest_id
				_log_action("QUEST", "Accepted quest: %s" % quest_id)
				_enter_state(BotState.DOING_QUEST)
				return

	# No quests available - explore
	_log_action("QUEST", "No quests available, exploring")
	_enter_state(BotState.EXPLORING)

func _do_quest_objective():
	if not quest_manager or current_quest_id.is_empty():
		_enter_state(BotState.SEEKING_QUEST)
		return

	var quest_data = _get_quest_data(current_quest_id)
	if not quest_data:
		_enter_state(BotState.SEEKING_QUEST)
		return

	# Check if quest is complete
	var quest_state = _get_quest_state(current_quest_id)
	if quest_state == 3:  # COMPLETE
		# Try to turn in
		if quest_manager.has_method("turn_in_quest"):
			quest_manager.turn_in_quest(current_quest_id)
			_log_action("QUEST", "Turned in quest: %s" % current_quest_id)
		current_quest_id = ""
		_enter_state(BotState.SEEKING_QUEST)
		return

	# Get current objective
	var objectives = quest_data.get("objectives", [])
	if current_objective_index >= objectives.size():
		current_objective_index = 0

	var objective = objectives[current_objective_index]
	var obj_type = objective.get("type", "")

	match obj_type:
		"kill":
			# Find and attack enemies
			var target_type = objective.get("target", "")
			var enemy = _find_enemy_by_type(target_type)
			if enemy:
				target_enemy = enemy
				_enter_state(BotState.COMBAT)
			else:
				_move_randomly()  # Wander to find enemies

		"collect":
			# Look for resource nodes or kill enemies for drops
			var target_item = objective.get("item", "")
			var resource = _find_resource_node(target_item)
			if resource:
				target_resource = resource
				_enter_state(BotState.GATHERING)
			else:
				_move_randomly()

		"explore", "enter_zone":
			var target_loc = objective.get("target", "")
			_move_toward_location(target_loc)

		"speak_to_npc":
			var npc_id = objective.get("target", "")
			var npc = _find_npc(npc_id)
			if npc:
				_move_toward(npc.global_position)
				if player.global_position.distance_to(npc.global_position) < 50:
					_interact()
			else:
				_move_randomly()

		"fuel_campfire", "convert_ruins":
			# Find campfire/ruins
			var target = _find_interactable(obj_type)
			if target:
				_move_toward(target.global_position)
				if player.global_position.distance_to(target.global_position) < 50:
					_interact()
			else:
				_move_randomly()

		_:
			_move_randomly()

func _do_combat():
	if not is_instance_valid(target_enemy):
		target_enemy = null
		_enter_state(BotState.DOING_QUEST)
		return

	var distance = player.global_position.distance_to(target_enemy.global_position)

	if distance > COMBAT_RANGE:
		# Move toward enemy
		_move_toward(target_enemy.global_position)
	else:
		# Attack!
		_face_target(target_enemy.global_position)
		_attack()

		# Random dodge/strafe
		if randf() < 0.1:
			_dash_away()

func _do_loot():
	if not is_instance_valid(target_loot):
		target_loot = null
		_enter_state(BotState.DOING_QUEST)
		return

	var distance = player.global_position.distance_to(target_loot.global_position)

	if distance > LOOT_RANGE:
		_move_toward(target_loot.global_position)
	else:
		_interact()
		# Try to loot all
		if target_loot.has_method("loot_all"):
			target_loot.loot_all()
		target_loot = null
		_enter_state(BotState.DOING_QUEST)

func _do_gather():
	if not is_instance_valid(target_resource):
		target_resource = null
		_enter_state(BotState.DOING_QUEST)
		return

	var distance = player.global_position.distance_to(target_resource.global_position)

	if distance > GATHER_RANGE:
		_move_toward(target_resource.global_position)
	else:
		_face_target(target_resource.global_position)
		_attack()  # Harvest uses attack

func _do_explore():
	# Random exploration
	if target_position == Vector2.ZERO or player.global_position.distance_to(target_position) < 30:
		target_position = player.global_position + Vector2(
			randf_range(-WANDER_RADIUS, WANDER_RADIUS),
			randf_range(-WANDER_RADIUS, WANDER_RADIUS)
		)
	_move_toward(target_position)

func _do_unstuck():
	# Move in random direction to get unstuck
	var escape_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_set_velocity(escape_dir * 200)

	# Try dashing out
	if randf() < 0.3:
		_dash_direction(escape_dir)

# ============ HELPER FUNCTIONS ============

func _find_nearest_enemy() -> Node:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node = null
	var nearest_dist := 500.0  # Aggro range

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest

func _find_enemy_by_type(enemy_type: String) -> Node:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		var type = enemy.get("enemy_type") if "enemy_type" in enemy else ""
		if enemy_type.is_empty() or type.to_lower().contains(enemy_type.to_lower()):
			return enemy
	return null

func _find_nearest_loot() -> Node:
	var corpses = get_tree().get_nodes_in_group("corpses")
	corpses.append_array(get_tree().get_nodes_in_group("loot"))

	var nearest: Node = null
	var nearest_dist := 200.0

	for corpse in corpses:
		if not is_instance_valid(corpse):
			continue
		var dist = player.global_position.distance_to(corpse.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = corpse

	return nearest

func _find_resource_node(item_type: String) -> Node:
	var resources = get_tree().get_nodes_in_group("resources")
	resources.append_array(get_tree().get_nodes_in_group("trees"))
	resources.append_array(get_tree().get_nodes_in_group("rocks"))

	for resource in resources:
		if not is_instance_valid(resource):
			continue
		var dist = player.global_position.distance_to(resource.global_position)
		if dist < 400:
			return resource

	return null

func _find_npc(npc_id: String) -> Node:
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if npc.name.to_lower().contains(npc_id.to_lower()):
			return npc
		if "npc_id" in npc and npc.npc_id == npc_id:
			return npc
	return null

func _find_interactable(obj_type: String) -> Node:
	var group = "campfires" if "campfire" in obj_type else "ruins"
	var nodes = get_tree().get_nodes_in_group(group)
	for node in nodes:
		if is_instance_valid(node):
			return node
	return null

func _get_inventory_items() -> Array:
	if inventory_system and "inventory_items" in inventory_system:
		return inventory_system.inventory_items
	return []

func _get_equipped_armor(slot: String) -> Dictionary:
	if character_stats and "equipped_armor" in character_stats:
		return character_stats.equipped_armor.get(slot, {})
	return {}

func _equip_item(item: Dictionary):
	if character_stats and character_stats.has_method("equip_armor"):
		character_stats.equip_armor(item)

func _get_active_quests() -> Array:
	if quest_manager and "active_quest_ids" in quest_manager:
		return quest_manager.active_quest_ids
	return []

func _get_available_quests() -> Array:
	if quest_manager and quest_manager.has_method("get_available_quests"):
		return quest_manager.get_available_quests()
	# Fallback: check quest_states
	if quest_manager and "quest_states" in quest_manager:
		var available = []
		for quest_id in quest_manager.quest_states:
			if quest_manager.quest_states[quest_id] == 1:  # AVAILABLE
				available.append(quest_id)
		return available
	return []

func _get_quest_data(quest_id: String) -> Dictionary:
	if quest_manager and "all_quests" in quest_manager:
		return quest_manager.all_quests.get(quest_id, {})
	return {}

func _get_quest_state(quest_id: String) -> int:
	if quest_manager and "quest_states" in quest_manager:
		return quest_manager.quest_states.get(quest_id, 0)
	return 0

# ============ MOVEMENT & ACTIONS ============

func _move_toward(target: Vector2):
	var direction = (target - player.global_position).normalized()
	_set_velocity(direction * 180)

func _move_toward_location(location_id: String):
	# Simple: move in a direction based on location name
	# Could be expanded with actual waypoints
	_move_randomly()

func _move_randomly():
	var direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_set_velocity(direction * 150)

func _set_velocity(vel: Vector2):
	if player and "velocity" in player:
		player.velocity = vel

func _face_target(target: Vector2):
	if not player:
		return
	var dir = (target - player.global_position).normalized()
	var facing = "down"
	if abs(dir.x) > abs(dir.y):
		facing = "right" if dir.x > 0 else "left"
	else:
		facing = "down" if dir.y > 0 else "up"
	if "facing_direction" in player:
		player.facing_direction = facing

func _attack():
	if player and player.has_method("start_attack"):
		player.start_attack()
	else:
		Input.action_press("attack")
		await get_tree().create_timer(0.1).timeout
		Input.action_release("attack")

func _interact():
	Input.action_press("interact")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("interact")

func _dash_away():
	if not target_enemy:
		return
	var away = (player.global_position - target_enemy.global_position).normalized()
	_dash_direction(away)

func _dash_direction(dir: Vector2):
	if player and player.has_method("start_dash"):
		player.start_dash(dir, player.global_position + dir * 100)
	else:
		Input.action_press("dash")
		await get_tree().create_timer(0.1).timeout
		Input.action_release("dash")

# ============ LOGGING ============

func _log_action(action: String, details: String):
	var entry = {
		"time": Time.get_unix_time_from_system(),
		"action": action,
		"details": details,
		"position": player.global_position if player else Vector2.ZERO,
		"state": BotState.keys()[state]
	}
	action_log.append(entry)
	if action_log.size() > MAX_LOG_SIZE:
		action_log.pop_front()

	print("[PlaytestBot] %s: %s" % [action, details])
	bot_action.emit(action, details)

func _log_error(message: String, context: Dictionary):
	var entry = {
		"time": Time.get_unix_time_from_system(),
		"message": message,
		"context": context,
		"position": player.global_position if player else Vector2.ZERO,
		"state": BotState.keys()[state]
	}
	error_log.append(entry)
	if error_log.size() > MAX_LOG_SIZE:
		error_log.pop_front()

	push_warning("[PlaytestBot ERROR] %s | %s" % [message, context])
	bot_error.emit(message, context)

func get_error_report() -> String:
	var report = "=== PlaytestBot Error Report ===\n"
	report += "Total errors: %d\n\n" % error_log.size()
	for entry in error_log:
		report += "[%s] %s at %s\n" % [
			Time.get_datetime_string_from_unix_time(entry.time),
			entry.message,
			entry.position
		]
		report += "  State: %s\n" % entry.state
		report += "  Context: %s\n\n" % str(entry.context)
	return report

func get_action_summary() -> Dictionary:
	var summary = {}
	for entry in action_log:
		var action = entry.action
		summary[action] = summary.get(action, 0) + 1
	return summary
