extends Node

## Quest Manager - Autoload singleton managing quest state and progression
## Handles quest loading, tracking, completion, and persistence

# ═══════════════════════════════════════════════════════════════════════════
# QUEST STATES
# ═══════════════════════════════════════════════════════════════════════════

enum QuestState {
	LOCKED,      # Level req not met or prereq incomplete
	AVAILABLE,   # Can accept from giver
	ACTIVE,      # In progress
	COMPLETE,    # Objectives done, awaiting turn-in
	TURNED_IN    # Done
}

# ═══════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════

signal quest_accepted(quest_id: String)
signal quest_progress_updated(quest_id: String, obj_index: int, current: int, required: int)
signal quest_completed(quest_id: String)  # Ready for turn-in
signal quest_turned_in(quest_id: String)
signal active_quests_changed()
signal quests_loaded()
signal quest_reward_choice_needed(quest_id: String, quest_name: String, options: Array)  # For item reward selection

# ═══════════════════════════════════════════════════════════════════════════
# DATA STORAGE
# ═══════════════════════════════════════════════════════════════════════════

var all_quests: Dictionary = {}         # quest_id -> quest data (from JSON)
var quest_states: Dictionary = {}       # quest_id -> QuestState
var quest_progress: Dictionary = {}     # quest_id -> {obj_index -> current_count}
var active_quest_ids: Array = []        # Currently tracked quests (max 5)

const MAX_ACTIVE_QUESTS = 5
const QUESTS_FILE = "res://data/quests.json"

# ═══════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	print("📜 QuestManager initializing...")
	load_quests_from_json()

	# Connect to game events for objective tracking
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	"""Connect to game systems for objective tracking"""
	# Item collection tracking
	if InventorySystem:
		if not InventorySystem.item_added.is_connected(_on_item_added):
			InventorySystem.item_added.connect(_on_item_added)
		print("   ✅ Connected to InventorySystem.item_added")

	# Level up tracking (unlocks level-gated quests)
	if CharacterStats:
		if not CharacterStats.level_up.is_connected(_on_level_up):
			CharacterStats.level_up.connect(_on_level_up)
		print("   ✅ Connected to CharacterStats.level_up")

	print("📜 QuestManager ready with %d quests" % all_quests.size())

func load_quests_from_json() -> void:
	"""Load quest definitions from JSON file"""
	if not FileAccess.file_exists(QUESTS_FILE):
		push_error("[QuestManager] Quests file not found: %s" % QUESTS_FILE)
		return

	var file = FileAccess.open(QUESTS_FILE, FileAccess.READ)
	if not file:
		push_error("[QuestManager] Failed to open quests file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		push_error("[QuestManager] Failed to parse quests JSON: %s" % json.get_error_message())
		return

	var data = json.data
	if not data.has("quests") or not data["quests"] is Array:
		push_error("[QuestManager] Invalid quests JSON format - missing 'quests' array")
		return

	# Load each quest
	for quest_data in data["quests"]:
		if quest_data is Dictionary and quest_data.has("id"):
			var quest_id = quest_data["id"]
			all_quests[quest_id] = quest_data

			# Initialize state if not already set (new quest)
			if not quest_states.has(quest_id):
				quest_states[quest_id] = QuestState.LOCKED

			# Initialize progress tracking
			if not quest_progress.has(quest_id):
				quest_progress[quest_id] = {}

	# Update quest availability based on current level
	_update_quest_availability()

	quests_loaded.emit()
	print("📜 Loaded %d quests from JSON" % all_quests.size())

# ═══════════════════════════════════════════════════════════════════════════
# QUEST STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func get_quest_state(quest_id: String) -> QuestState:
	"""Get current state of a quest"""
	return quest_states.get(quest_id, QuestState.LOCKED)

func get_quest(quest_id: String) -> Dictionary:
	"""Get quest data by ID"""
	return all_quests.get(quest_id, {})

func accept_quest(quest_id: String) -> bool:
	"""Accept a quest (move from AVAILABLE to ACTIVE)"""
	if not all_quests.has(quest_id):
		return false

	var current_state = get_quest_state(quest_id)
	if current_state != QuestState.AVAILABLE:
		print("📜 Cannot accept quest %s - not available (state: %d)" % [quest_id, current_state])
		return false

	# Check max active quests
	if active_quest_ids.size() >= MAX_ACTIVE_QUESTS:
		print("📜 Cannot accept quest %s - max active quests reached (%d)" % [quest_id, MAX_ACTIVE_QUESTS])
		return false

	# Accept the quest
	quest_states[quest_id] = QuestState.ACTIVE
	active_quest_ids.append(quest_id)

	# Initialize progress for each objective
	var quest = all_quests[quest_id]
	var objectives = quest.get("objectives", [])
	quest_progress[quest_id] = {}
	for i in range(objectives.size()):
		quest_progress[quest_id][i] = 0

	# Check existing inventory for collect objectives
	_check_inventory_for_quest(quest_id)

	quest_accepted.emit(quest_id)
	active_quests_changed.emit()

	# Notify tutorial system
	if TutorialManager and TutorialManager.is_tutorial_active():
		TutorialManager.on_quest_accepted()

	print("📜 Quest accepted: %s" % quest.get("name", quest_id))
	return true

func _check_inventory_for_quest(quest_id: String) -> void:
	"""Check existing inventory items for collect objectives"""
	var quest = all_quests.get(quest_id)
	if not quest:
		return

	var objectives = quest.get("objectives", [])
	for i in range(objectives.size()):
		var obj = objectives[i]
		if obj.get("type") != "collect":
			continue

		var target_item = obj.get("target", "")
		if target_item.is_empty():
			continue

		# Count items in inventory
		var count = _count_inventory_item(target_item)
		if count > 0:
			update_objective_progress(quest_id, i, count)
			print("📜 Found %d %s in inventory for quest %s" % [count, target_item, quest_id])

func _count_inventory_item(item_name: String) -> int:
	"""Count how many of an item the player has in inventory"""
	if not InventorySystem:
		return 0

	var count = 0
	for item in InventorySystem.inventory_items:
		if item and item.get("name", "") == item_name:
			count += item.get("quantity", 1)

	return count

func abandon_quest(quest_id: String) -> bool:
	"""Abandon an active quest"""
	if not active_quest_ids.has(quest_id):
		return false

	quest_states[quest_id] = QuestState.AVAILABLE
	active_quest_ids.erase(quest_id)
	quest_progress[quest_id] = {}

	active_quests_changed.emit()
	print("📜 Quest abandoned: %s" % quest_id)
	return true

func turn_in_quest(quest_id: String) -> bool:
	"""Turn in a completed quest and receive rewards"""
	if get_quest_state(quest_id) != QuestState.COMPLETE:
		print("📜 Cannot turn in quest %s - not complete" % quest_id)
		return false

	var quest = all_quests[quest_id]

	# Check if quest has item reward with choice
	var item_reward = quest.get("item_reward", {})
	if item_reward.get("choice", false):
		# Emit signal for UI to show reward choice popup
		var options = item_reward.get("options", [])
		quest_reward_choice_needed.emit(quest_id, quest.get("name", ""), options)
		print("📜 Quest %s requires item reward choice - waiting for selection" % quest_id)
		return true  # Return true but don't complete yet - waiting for choice

	# No item choice needed - grant rewards immediately
	return _complete_quest_turnin(quest_id)

func _complete_quest_turnin(quest_id: String, chosen_item_id: String = "") -> bool:
	"""Complete the quest turn-in after any choices are made"""
	var quest = all_quests[quest_id]

	# Grant XP and gold rewards
	var xp_reward = quest.get("xp_reward", 0)
	var gold_reward = quest.get("gold_reward", 0)

	if xp_reward > 0:
		CharacterStats.gain_experience(xp_reward)

	if gold_reward > 0:
		CharacterStats.add_gold(gold_reward)

	# Grant chosen item reward if any
	var item_granted = ""
	if not chosen_item_id.is_empty():
		var item = _create_armor_item(chosen_item_id, quest)
		if item and InventorySystem:
			InventorySystem.add_item(item)
			item_granted = item.get("name", chosen_item_id)
			print("📜 Granted item reward: %s" % item_granted)

	# Update state
	quest_states[quest_id] = QuestState.TURNED_IN
	active_quest_ids.erase(quest_id)

	# Show notification
	if NotificationManager:
		var msg = "Quest Complete: %s\n+%d XP, +%d Gold" % [quest.get("name", ""), xp_reward, gold_reward]
		if not item_granted.is_empty():
			msg += "\n+%s" % item_granted
		NotificationManager.show_notification(msg, "SUCCESS")

	quest_turned_in.emit(quest_id)
	active_quests_changed.emit()

	# Check if any new quests are now available (prerequisites met)
	_update_quest_availability()

	print("📜 Quest turned in: %s (+%d XP, +%d Gold)" % [quest.get("name", quest_id), xp_reward, gold_reward])
	return true

func grant_item_reward(quest_id: String, item_id: String) -> bool:
	"""Called by UI after player selects their item reward choice"""
	if get_quest_state(quest_id) != QuestState.COMPLETE:
		print("📜 Cannot grant item reward for quest %s - not complete" % quest_id)
		return false

	return _complete_quest_turnin(quest_id, item_id)

func _create_armor_item(item_id: String, quest: Dictionary) -> Dictionary:
	"""Create armor item dictionary from item_id using quest reward options"""
	var item_reward = quest.get("item_reward", {})
	var options = item_reward.get("options", [])
	var slot = item_reward.get("slot", "")

	# Find the selected option
	var selected_option = {}
	for option in options:
		if option.get("id") == item_id:
			selected_option = option
			break

	if selected_option.is_empty():
		push_error("[QuestManager] Item ID not found in quest options: %s" % item_id)
		return {}

	# Build the armor item dictionary
	var item = {
		"id": item_id,
		"name": selected_option.get("name", item_id),
		"type": "armor",
		"slot": slot,
		"armor_type": selected_option.get("armor_type", "plate"),
		"sprite_name": _get_sprite_name_for_armor(selected_option.get("armor_type", "plate")),
		"stackable": false,
		"quantity": 1,
		"rarity": "Common"
	}

	return item

func _get_sprite_name_for_armor(armor_type: String) -> String:
	"""Get sprite name based on armor type"""
	match armor_type:
		"plate":
			return "copper_plate"
		"leather":
			return "rawhide"
		"cloth":
			return "linen"
		_:
			return "copper_plate"

func _update_quest_availability() -> void:
	"""Update which quests are available based on level and prerequisites"""
	var player_level = CharacterStats.level if CharacterStats else 1

	for quest_id in all_quests.keys():
		var current_state = get_quest_state(quest_id)

		# Skip quests already in progress or completed
		if current_state in [QuestState.ACTIVE, QuestState.COMPLETE, QuestState.TURNED_IN]:
			continue

		var quest = all_quests[quest_id]
		var level_req = quest.get("level_req", 1)
		var prereq = quest.get("prereq", null)

		# Check prerequisites
		var prereq_met = true
		if prereq and prereq is String and not prereq.is_empty():
			prereq_met = get_quest_state(prereq) == QuestState.TURNED_IN

		# Check level requirement
		var level_met = player_level >= level_req

		# Update state
		if prereq_met and level_met:
			if current_state == QuestState.LOCKED:
				quest_states[quest_id] = QuestState.AVAILABLE
				print("📜 Quest now available: %s" % quest.get("name", quest_id))
		else:
			quest_states[quest_id] = QuestState.LOCKED

# ═══════════════════════════════════════════════════════════════════════════
# OBJECTIVE TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func update_objective_progress(quest_id: String, obj_index: int, amount: int = 1) -> void:
	"""Update progress on a specific objective"""
	if get_quest_state(quest_id) != QuestState.ACTIVE:
		return

	var quest = all_quests.get(quest_id)
	if not quest:
		return

	var objectives = quest.get("objectives", [])
	if obj_index >= objectives.size():
		return

	var objective = objectives[obj_index]
	var required = objective.get("count", 1)

	# Update progress
	if not quest_progress.has(quest_id):
		quest_progress[quest_id] = {}

	var current = quest_progress[quest_id].get(obj_index, 0)
	var new_value = min(current + amount, required)
	quest_progress[quest_id][obj_index] = new_value

	quest_progress_updated.emit(quest_id, obj_index, new_value, required)

	# Check if all objectives complete
	_check_quest_completion(quest_id)

func get_objective_progress(quest_id: String, obj_index: int) -> int:
	"""Get current progress for an objective"""
	if not quest_progress.has(quest_id):
		return 0
	return quest_progress[quest_id].get(obj_index, 0)

func _check_quest_completion(quest_id: String) -> void:
	"""Check if all objectives are complete and update state"""
	if get_quest_state(quest_id) != QuestState.ACTIVE:
		return

	var quest = all_quests.get(quest_id)
	if not quest:
		return

	var objectives = quest.get("objectives", [])
	var all_complete = true

	for i in range(objectives.size()):
		var objective = objectives[i]
		var required = objective.get("count", 1)
		var current = get_objective_progress(quest_id, i)

		if current < required:
			all_complete = false
			break

	if all_complete:
		quest_states[quest_id] = QuestState.COMPLETE
		quest_completed.emit(quest_id)
		active_quests_changed.emit()

		if NotificationManager:
			NotificationManager.show_notification("Quest Ready: %s" % quest.get("name", ""), "INFO")

		print("📜 Quest complete (ready for turn-in): %s" % quest.get("name", quest_id))

# ═══════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS (Objective Tracking)
# ═══════════════════════════════════════════════════════════════════════════

func _on_item_added(item: Dictionary) -> void:
	"""Track item collection for 'collect' objectives"""
	var item_name = item.get("name", "")
	if item_name.is_empty():
		return

	var quantity = item.get("quantity", 1)
	print("📜 Item added to inventory: %s x%d" % [item_name, quantity])

	# Check all active quests for matching collect objectives
	for quest_id in active_quest_ids:
		var quest = all_quests.get(quest_id)
		if not quest:
			continue

		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			if obj.get("type") == "collect" and obj.get("target") == item_name:
				update_objective_progress(quest_id, i, quantity)

func _on_level_up(_new_level: int) -> void:
	"""Update quest availability when player levels up"""
	_update_quest_availability()

func on_enemy_killed(enemy_type: String, enemy_level: int, is_guardian: bool) -> void:
	"""Track enemy kills for 'kill' objectives - call from NetworkEnemyManager"""
	# Check all active quests for matching kill objectives
	for quest_id in active_quest_ids:
		var quest = all_quests.get(quest_id)
		if not quest:
			continue

		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			if obj.get("type") != "kill":
				continue

			# Check filters
			var target_type = obj.get("target", "")
			var min_level = obj.get("min_level", 0)
			var req_guardian = obj.get("is_guardian", false)

			# Match enemy type (empty target = any)
			if not target_type.is_empty() and target_type != enemy_type:
				continue

			# Match level requirement
			if enemy_level < min_level:
				continue

			# Match guardian requirement
			if req_guardian and not is_guardian:
				continue

			# All filters passed - count the kill
			update_objective_progress(quest_id, i, 1)

func on_campfire_fueled(fuel_amount: int) -> void:
	"""Track campfire fuel for 'fuel_campfire' objectives - call from Campfire"""
	for quest_id in active_quest_ids:
		var quest = all_quests.get(quest_id)
		if not quest:
			continue

		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			if obj.get("type") == "fuel_campfire":
				update_objective_progress(quest_id, i, fuel_amount)

func on_location_discovered(location_id: String) -> void:
	"""Track location discovery for 'explore' objectives"""
	for quest_id in active_quest_ids:
		var quest = all_quests.get(quest_id)
		if not quest:
			continue

		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			if obj.get("type") == "explore" and obj.get("target") == location_id:
				# Exploration is binary - complete immediately
				var required = obj.get("count", 1)
				quest_progress[quest_id][i] = required
				quest_progress_updated.emit(quest_id, i, required, required)
				_check_quest_completion(quest_id)

func on_ruins_converted() -> void:
	"""Track ruins conversion for 'convert_ruins' objectives"""
	for quest_id in active_quest_ids:
		var quest = all_quests.get(quest_id)
		if not quest:
			continue

		var objectives = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj = objectives[i]
			if obj.get("type") == "convert_ruins":
				update_objective_progress(quest_id, i, 1)

# ═══════════════════════════════════════════════════════════════════════════
# QUERY HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func get_available_quests(giver: String = "blacksmith") -> Array:
	"""Get all available quests from a specific giver"""
	var result = []
	for quest_id in all_quests.keys():
		if get_quest_state(quest_id) == QuestState.AVAILABLE:
			var quest = all_quests[quest_id]
			if quest.get("giver", "") == giver:
				result.append(quest)
	return result

func get_completed_quests(giver: String = "blacksmith") -> Array:
	"""Get all quests ready for turn-in at a specific giver"""
	var result = []
	for quest_id in all_quests.keys():
		if get_quest_state(quest_id) == QuestState.COMPLETE:
			var quest = all_quests[quest_id]
			if quest.get("giver", "") == giver:
				result.append(quest)
	return result

func get_active_quests() -> Array:
	"""Get all active quest data"""
	var result = []
	for quest_id in active_quest_ids:
		if all_quests.has(quest_id):
			result.append(all_quests[quest_id])
	return result

func has_available_quests(giver: String = "blacksmith") -> bool:
	"""Check if giver has available quests"""
	return get_available_quests(giver).size() > 0

func has_completed_quests(giver: String = "blacksmith") -> bool:
	"""Check if giver has quests ready for turn-in"""
	return get_completed_quests(giver).size() > 0

# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD
# ═══════════════════════════════════════════════════════════════════════════

func get_save_data() -> Dictionary:
	"""Get quest data for saving"""
	return {
		"states": quest_states.duplicate(),
		"progress": quest_progress.duplicate(true),
		"active": active_quest_ids.duplicate()
	}

func load_save_data(data: Dictionary) -> void:
	"""Load quest data from save"""
	if data.is_empty():
		return

	# Load states
	var saved_states = data.get("states", {})
	for quest_id in saved_states:
		if all_quests.has(quest_id):
			quest_states[quest_id] = saved_states[quest_id]

	# Load progress
	var saved_progress = data.get("progress", {})
	for quest_id in saved_progress:
		if all_quests.has(quest_id):
			quest_progress[quest_id] = saved_progress[quest_id]

	# Load active quests
	var saved_active = data.get("active", [])
	active_quest_ids.clear()
	for quest_id in saved_active:
		if all_quests.has(quest_id):
			active_quest_ids.append(quest_id)

	# Update availability for any new quests added since last save
	_update_quest_availability()

	active_quests_changed.emit()
	print("📜 Loaded quest progress: %d active quests" % active_quest_ids.size())

func reset_quests() -> void:
	"""Reset all quest progress (for new character)"""
	quest_states.clear()
	quest_progress.clear()
	active_quest_ids.clear()

	# Re-initialize all quests as locked
	for quest_id in all_quests.keys():
		quest_states[quest_id] = QuestState.LOCKED
		quest_progress[quest_id] = {}

	# Update availability based on current level
	_update_quest_availability()

	active_quests_changed.emit()
	print("📜 Quest progress reset")
