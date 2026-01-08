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
const HEAL_RETREAT_THRESHOLD := 0.30  # Retreat at 30% HP
const HEAL_RESUME_THRESHOLD := 0.90  # Resume combat at 90% HP

# Looting state
var _loot_target: Node2D = null
var _is_looting := false
const LOOT_PICKUP_RANGE := 30.0

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

func _process(delta):
	_accept_connections()
	_read_commands()
	_update_pathing(delta)
	_update_auto_combat(delta)

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

		# Forge items
		"get_forge_items":
			return _get_forge_items(cmd.get("type", ""))

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

func _update_pathing(_delta: float):
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

	var dist = player.global_position.distance_to(_move_target)
	if dist < 20:
		_is_pathing = false
		_release_inputs()
		# If we reached campfire while healing, stay in healing mode
		if _is_healing:
			print("[MCPBridge] Reached campfire, waiting to heal...")
		return

	var dir = player.global_position.direction_to(_move_target)
	_release_inputs()
	if dir.x < -0.3: Input.action_press("move_left")
	elif dir.x > 0.3: Input.action_press("move_right")
	if dir.y < -0.3: Input.action_press("move_up")
	elif dir.y > 0.3: Input.action_press("move_down")

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
					if w.get("_comment"):
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
					if a.get("_comment"):
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
	player = _find_player()

	if not player:
		_auto_combat = false
		return

	# Check player HP - retreat to campfire if below threshold
	var hp_percent = _get_player_hp_percent()
	if hp_percent < HEAL_RETREAT_THRESHOLD:
		print("[MCPBridge] Auto-combat: Low HP (%.0f%%), retreating to campfire!" % (hp_percent * 100))
		_auto_combat = false
		_release_inputs()
		# Start moving to campfire
		var campfire_result = _find_campfire(1000.0)
		if campfire_result.count > 0:
			var nearest = campfire_result.campfires[0]
			_campfire_target = instance_from_id(nearest.id)
			if is_instance_valid(_campfire_target):
				_is_healing = true
				_move_target = _campfire_target.global_position
				_is_pathing = true
				print("[MCPBridge] Moving to campfire at (%.0f, %.0f)" % [_move_target.x, _move_target.y])
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
			_auto_combat = false
			_release_inputs()
			print("[MCPBridge] Auto-combat: No more enemies")
			return

	# Check if target is dead (method or HP check)
	var target_dead = false
	if _combat_target.has_method("is_dead") and _combat_target.is_dead():
		target_dead = true
	elif _get_enemy_hp(_combat_target) <= 0:
		target_dead = true

	if target_dead:
		print("[MCPBridge] Auto-combat: Enemy defeated! Finding next target...")
		# Try to loot nearby items after kill
		_try_loot_nearby()
		_combat_target = _find_nearest_alive_enemy()
		if not _combat_target:
			_auto_combat = false
			_release_inputs()
			print("[MCPBridge] Auto-combat: All enemies defeated!")
			return

	var dist = player.global_position.distance_to(_combat_target.global_position)

	# ALWAYS face the target when moving toward it (fixes backwards walking)
	_set_face_target(_combat_target.global_position)

	if dist > COMBAT_RANGE:
		# Move toward enemy - face first!
		var dir = player.global_position.direction_to(_combat_target.global_position)
		_release_inputs()
		if dir.x < -0.3: Input.action_press("move_left")
		elif dir.x > 0.3: Input.action_press("move_right")
		if dir.y < -0.3: Input.action_press("move_up")
		elif dir.y > 0.3: Input.action_press("move_down")
	else:
		# In range - stop and attack!
		_release_inputs()
		if _attack_timer <= 0:
			# Use combat system to attack (facing is handled by _update_facing)
			_cmd_attack()
			_attack_timer = ATTACK_COOLDOWN

func _try_loot_nearby() -> void:
	"""Try to loot any nearby corpses after a kill"""
	if not player:
		return

	var pos = player.global_position
	var loot_range := 120.0  # Range to check for corpses

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
					CharacterStats.gold += corpse.corpse_gold
					print("[MCPBridge] Auto-looted %d gold from %s" % [corpse.corpse_gold, corpse.name])
					corpse.corpse_gold = 0

				# Collect items directly to inventory
				if has_items:
					for item in corpse.corpse_loot:
						if InventorySystem and InventorySystem.has_method("add_item"):
							InventorySystem.add_item(item)
							print("[MCPBridge] Auto-looted item: %s" % item.get("name", "Unknown"))
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
				print("[MCPBridge] Auto-looted bone: %s" % item.name)

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
