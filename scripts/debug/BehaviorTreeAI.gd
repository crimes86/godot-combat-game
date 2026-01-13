extends Node
class_name BehaviorTreeAI

## Behavior Tree AI System
## Runs at 60fps for reactive gameplay, receives strategic goals from Claude
##
## Architecture:
##   Claude (seconds) -> Sets goals, responds to events
##   BehaviorTree (60fps) -> Executes tactics, handles combat, interrupts
##
## Priority System (higher = more urgent):
##   P0: CRITICAL - Flee when HP critical, respond to attacks
##   P1: REACTIVE - Player nearby, new threat detected
##   P2: TACTICAL - Active combat, looting, healing
##   P3: STRATEGIC - Quest grinding, farming, exploring

signal event_for_claude(event_type: String, data: Dictionary)

# ═══════════════════════════════════════════════════════════════════════════════
# BEHAVIOR TREE NODE TYPES
# ═══════════════════════════════════════════════════════════════════════════════

enum BTStatus { SUCCESS, FAILURE, RUNNING }
enum Priority { CRITICAL = 0, REACTIVE = 1, TACTICAL = 2, STRATEGIC = 3 }

# Current active behavior and state
var current_goal: String = "idle"
var current_priority: Priority = Priority.STRATEGIC
var bt_enabled: bool = false
var bt_paused: bool = false

# References
var player: Node2D = null
var mcp_bridge: Node = null  # Reference to MCPBridge for shared state

# State tracking
var _last_hp_percent: float = 1.0
var _combat_target: Node2D = null
var _loot_target: Node2D = null
var _goal_data: Dictionary = {}

# Timing
var _action_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO

# Death detection and recovery
var _last_max_hp: float = 100.0
# Note: _last_hp_percent is declared above in State tracking section
var _had_player_last_frame: bool = true  # Start as true to avoid false death on first tick
var _ever_had_player: bool = false  # Track if we've ever had a player
var _just_died: bool = false
var _death_recovery_timer: float = 0.0
const DEATH_RECOVERY_TIME := 3.0  # Wait 3 seconds after respawn before acting

# Event queue for Claude
var _pending_events: Array[Dictionary] = []

# Combat constants
const MELEE_RANGE := 55.0
const ATTACK_COOLDOWN := 0.35
const THREAT_RANGE := 200.0
const CRITICAL_HP := 0.25
const LOW_HP := 0.5
const SAFE_HP := 0.9

# Looting constants
const LOOT_RANGE := 50.0
const CORPSE_SEARCH_RADIUS := 300.0

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE METRICS - Track everything for improvement analysis
# ═══════════════════════════════════════════════════════════════════════════════

var metrics: Dictionary = {
	# Session info
	"session_start": 0,
	"total_runtime_sec": 0.0,
	
	# Combat metrics
	"kills": 0,
	"kill_times": [],  # Array of kill durations in seconds
	"avg_kill_time": 0.0,
	"fastest_kill": 999.0,
	"slowest_kill": 0.0,
	"damage_dealt": 0,
	"attacks_made": 0,
	
	# Survival metrics
	"deaths": 0,
	"damage_taken": 0,
	"heals_performed": 0,
	"hp_healed": 0,
	"flee_count": 0,
	"critical_hp_events": 0,
	
	# Loot metrics
	"loot_attempts": 0,
	"loot_successes": 0,
	"loot_failures": 0,
	"items_looted": 0,
	"gold_earned": 0,
	"corpses_missed": 0,  # Corpses that despawned before looting
	
	# Quest metrics
	"quests_accepted": 0,
	"quests_completed": 0,
	"quest_objectives_completed": 0,
	
	# Gear metrics
	"gear_upgrades": 0,
	"gold_spent": 0,
	
	# Behavior metrics
	"goal_changes": 0,
	"time_in_combat": 0.0,
	"time_in_loot": 0.0,
	"time_in_heal": 0.0,
	"time_idle": 0.0,
	"interrupts_handled": 0,
	
	# Efficiency metrics (calculated)
	"gold_per_minute": 0.0,
	"kills_per_minute": 0.0,
	"loot_success_rate": 0.0,
	"survival_rate": 0.0,  # Time alive / total time
}

# Combat tracking
var _combat_start_time: int = 0
var _current_target_hp_start: float = 0.0
var _last_gold: int = 0
var _last_hp: float = 100.0
var _time_alive: float = 0.0
var _goal_start_time: int = 0

func _update_metrics(delta: float) -> void:
	"""Update time-based metrics each tick"""
	metrics["total_runtime_sec"] += delta
	
	# Track time in current goal
	match current_goal:
		"combat":
			metrics["time_in_combat"] += delta
		"loot_corpse":
			metrics["time_in_loot"] += delta
		"heal_at_campfire", "flee_to_campfire":
			metrics["time_in_heal"] += delta
		"idle":
			metrics["time_idle"] += delta
	
	# Track survival time
	if _get_hp_percent() > 0:
		_time_alive += delta
	
	# Update efficiency metrics every 10 seconds
	if int(metrics["total_runtime_sec"]) % 10 == 0 and delta > 0:
		_calculate_efficiency_metrics()

func _calculate_efficiency_metrics() -> void:
	"""Calculate derived efficiency metrics"""
	var minutes = metrics["total_runtime_sec"] / 60.0
	if minutes > 0:
		metrics["gold_per_minute"] = metrics["gold_earned"] / minutes
		metrics["kills_per_minute"] = metrics["kills"] / minutes
	
	if metrics["loot_attempts"] > 0:
		metrics["loot_success_rate"] = float(metrics["loot_successes"]) / metrics["loot_attempts"] * 100.0
	
	if metrics["total_runtime_sec"] > 0:
		metrics["survival_rate"] = _time_alive / metrics["total_runtime_sec"] * 100.0
	
	# Calculate average kill time
	if metrics["kill_times"].size() > 0:
		var total = 0.0
		for t in metrics["kill_times"]:
			total += t
		metrics["avg_kill_time"] = total / metrics["kill_times"].size()

func record_kill(kill_time: float) -> void:
	"""Record a kill with timing"""
	metrics["kills"] += 1
	metrics["kill_times"].append(kill_time)
	
	if kill_time < metrics["fastest_kill"]:
		metrics["fastest_kill"] = kill_time
	if kill_time > metrics["slowest_kill"]:
		metrics["slowest_kill"] = kill_time
	
	_queue_event("kill_recorded", {
		kill_time = kill_time,
		total_kills = metrics["kills"],
		avg_time = metrics["avg_kill_time"]
	})

func record_loot(success: bool, items: int = 0, gold: int = 0) -> void:
	"""Record loot attempt"""
	metrics["loot_attempts"] += 1
	if success:
		metrics["loot_successes"] += 1
		metrics["items_looted"] += items
		metrics["gold_earned"] += gold
	else:
		metrics["loot_failures"] += 1

func record_death() -> void:
	"""Record player death"""
	metrics["deaths"] += 1
	_time_alive = 0.0
	_queue_event("death_recorded", {
		total_deaths = metrics["deaths"],
		survival_rate = metrics["survival_rate"]
	})

func record_damage_taken(amount: float) -> void:
	"""Record damage taken"""
	metrics["damage_taken"] += int(amount)

func record_heal(amount: float) -> void:
	"""Record healing"""
	metrics["heals_performed"] += 1
	metrics["hp_healed"] += int(amount)

func get_metrics() -> Dictionary:
	"""Get current metrics snapshot"""
	_calculate_efficiency_metrics()
	return metrics.duplicate()

func get_metrics_summary() -> String:
	"""Get human-readable metrics summary"""
	_calculate_efficiency_metrics()
	return """
=== BT PERFORMANCE METRICS ===
Runtime: %.1f min | Kills: %d (%.1f/min) | Deaths: %d
Avg Kill: %.1fs | Best: %.1fs | Worst: %.1fs
Loot: %d/%d (%.0f%%) | Gold: %d (%.0f/min)
Combat: %.0fs | Looting: %.0fs | Healing: %.0fs
Survival Rate: %.0f%%
""" % [
		metrics["total_runtime_sec"] / 60.0,
		metrics["kills"],
		metrics["kills_per_minute"],
		metrics["deaths"],
		metrics["avg_kill_time"],
		metrics["fastest_kill"] if metrics["fastest_kill"] < 999 else 0,
		metrics["slowest_kill"],
		metrics["loot_successes"],
		metrics["loot_attempts"],
		metrics["loot_success_rate"],
		metrics["gold_earned"],
		metrics["gold_per_minute"],
		metrics["time_in_combat"],
		metrics["time_in_loot"],
		metrics["time_in_heal"],
		metrics["survival_rate"]
	]

func _track_gold_and_hp() -> void:
	"""Track gold earned and HP changes for metrics"""
	if not player:
		return
	
	# Track gold changes
	var current_gold = player.gold if "gold" in player else 0
	if current_gold > _last_gold:
		var gained = current_gold - _last_gold
		metrics["gold_earned"] += gained
	_last_gold = current_gold
	
	# Track HP for damage/heal detection
	var current_hp = player.hp if "hp" in player else 100.0
	if current_hp < _last_hp:
		record_damage_taken(_last_hp - current_hp)
	elif current_hp > _last_hp and current_goal in ["heal_at_campfire", "flee_to_campfire"]:
		record_heal(current_hp - _last_hp)
	_last_hp = current_hp

func analyze_performance() -> Dictionary:
	"""Analyze metrics and generate improvement suggestions for Claude"""
	_calculate_efficiency_metrics()
	
	var issues: Array = []
	var suggestions: Array = []
	var analysis: Dictionary = {}
	
	# Analyze kill efficiency
	if metrics["avg_kill_time"] > 5.0 and metrics["kills"] > 3:
		issues.append("slow_kills")
		suggestions.append("Average kill time is %.1fs - consider better weapon or attack patterns" % metrics["avg_kill_time"])
		analysis["kill_efficiency"] = "poor"
	elif metrics["avg_kill_time"] > 3.0 and metrics["kills"] > 3:
		analysis["kill_efficiency"] = "moderate"
	else:
		analysis["kill_efficiency"] = "good"
	
	# Analyze loot efficiency
	if metrics["loot_attempts"] > 5 and metrics["loot_success_rate"] < 70:
		issues.append("low_loot_rate")
		suggestions.append("Loot success rate is %.0f%% - corpses may be despawning, loot faster after kills" % metrics["loot_success_rate"])
		analysis["loot_efficiency"] = "poor"
	elif metrics["loot_success_rate"] < 90:
		analysis["loot_efficiency"] = "moderate"
	else:
		analysis["loot_efficiency"] = "good"
	
	# Analyze survival
	if metrics["deaths"] > 0 and metrics["kills"] > 0:
		var kd_ratio = float(metrics["kills"]) / metrics["deaths"]
		analysis["kd_ratio"] = kd_ratio
		if kd_ratio < 5:
			issues.append("high_death_rate")
			suggestions.append("K/D ratio is %.1f - flee to campfire earlier or avoid multi-pulls" % kd_ratio)
			analysis["survival"] = "poor"
		elif kd_ratio < 10:
			analysis["survival"] = "moderate"
		else:
			analysis["survival"] = "good"
	
	# Analyze time efficiency
	var total_active = metrics["time_in_combat"] + metrics["time_in_loot"]
	if metrics["total_runtime_sec"] > 60:
		var active_percent = (total_active / metrics["total_runtime_sec"]) * 100
		analysis["uptime_percent"] = active_percent
		if active_percent < 50:
			issues.append("low_uptime")
			suggestions.append("Only %.0f%% active time - reduce idle/travel time" % active_percent)
	
	# Analyze gold efficiency
	if metrics["total_runtime_sec"] > 120:  # After 2 mins
		if metrics["gold_per_minute"] < 5:
			issues.append("low_gold_rate")
			suggestions.append("Gold rate is %.1f/min - ensure looting all corpses" % metrics["gold_per_minute"])
	
	# Check gear status
	if metrics["kills"] > 5 and metrics["gear_upgrades"] == 0:
		var max_hp = _get_max_hp()
		if max_hp <= 100:
			issues.append("no_gear")
			suggestions.append("Still at base 100 HP after %d kills - buy and equip gear!" % metrics["kills"])
	
	return {
		"metrics": get_metrics(),
		"issues": issues,
		"suggestions": suggestions,
		"analysis": analysis,
		"summary": get_metrics_summary()
	}

# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

func _ready():
	# Find MCPBridge
	mcp_bridge = get_node_or_null("/root/MCPBridge")
	if not mcp_bridge:
		push_warning("[BehaviorTreeAI] MCPBridge not found")

func setup(mcp: Node) -> void:
	mcp_bridge = mcp
	print("[BT] Behavior Tree AI initialized")

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN TICK - Runs every frame when enabled
# ═══════════════════════════════════════════════════════════════════════════════

func tick(delta: float) -> Dictionary:
	if not bt_enabled or bt_paused:
		return {status = "disabled"}

	player = _find_player()

	# Track player validity transitions for death detection
	var has_player_now = player != null
	if not has_player_now:
		# No player - mark that we lost them (they probably died)
		if _ever_had_player:
			_had_player_last_frame = false
		return {status = "no_player"}

	# Check if we just regained a player after not having one (respawn detected!)
	# Only trigger if we've had a player before (avoid false positive on first load)
	if _ever_had_player and not _had_player_last_frame and not _just_died:
		# We have a player now but didn't before - this is a respawn
		_just_died = true
		_death_recovery_timer = 0.0
		metrics["deaths"] += 1

		# Clear stale targets
		_combat_target = null
		_loot_target = null
		_goal_data = {}

		# Stop movement
		_stop_movement()

		_queue_event("player_died", {
			deaths = metrics["deaths"]
		})
		print("[BT] DEATH DETECTED (player respawned) - Entering recovery mode. Deaths: %d" % metrics["deaths"])

	_had_player_last_frame = true
	_ever_had_player = true

	# DEATH RECOVERY - Handle the recovery period after respawn
	var death_result = _check_death_and_recovery(delta)
	if death_result.handled:
		return death_result

	# Update performance metrics
	_update_metrics(delta)
	_track_gold_and_hp()

	# Priority 0: CRITICAL - Always check first
	var critical_result = _check_critical_interrupts()
	if critical_result.handled:
		return critical_result

	# Priority 1: REACTIVE - Player detection, new threats
	var reactive_result = _check_reactive_interrupts()
	if reactive_result.handled:
		return reactive_result

	# Priority 2-3: Execute current goal
	var goal_result = _execute_current_goal(delta)
	return goal_result

# ═══════════════════════════════════════════════════════════════════════════════
# DEATH DETECTION AND RECOVERY
# ═══════════════════════════════════════════════════════════════════════════════

func _check_death_and_recovery(delta: float) -> Dictionary:
	# Handle recovery period after death was detected in tick()
	if _just_died:
		_death_recovery_timer += delta

		# Stay still during recovery
		_stop_movement()

		if _death_recovery_timer < DEATH_RECOVERY_TIME:
			# Still in recovery - don't do anything aggressive
			return {
				handled = true,
				status = "death_recovery",
				timer = _death_recovery_timer,
				remaining = DEATH_RECOVERY_TIME - _death_recovery_timer
			}
		else:
			# Recovery complete - switch to gear_up mode
			_just_died = false
			_death_recovery_timer = 0.0
			set_goal("gear_up", Priority.CRITICAL)
			print("[BT] Recovery complete - Entering gear_up mode")
			return {
				handled = true,
				status = "recovery_complete",
				next_goal = "gear_up"
			}

	# Update tracking for other metrics
	_last_max_hp = _get_max_hp()
	_last_hp_percent = _get_hp_percent()

	return {handled = false}

# ═══════════════════════════════════════════════════════════════════════════════
# PRIORITY 0: CRITICAL INTERRUPTS
# ═══════════════════════════════════════════════════════════════════════════════

func _check_critical_interrupts() -> Dictionary:
	var hp_percent = _get_hp_percent()

	# Critical HP - must flee immediately
	if hp_percent < CRITICAL_HP and current_goal != "flee_to_campfire":
		_queue_event("critical_hp", {hp_percent = hp_percent})
		set_goal("flee_to_campfire", Priority.CRITICAL)
		return {handled = true, action = "fleeing", reason = "critical_hp"}

	# Being attacked while not in combat - notify but don't block goal execution
	# The goal (e.g., quest_grind) should handle combat priority
	if current_goal != "combat" and _is_being_attacked():
		var attacker = _get_attacker()
		if attacker:
			_queue_event("under_attack", {attacker_id = attacker.get_instance_id()})
			# Fall through to let the goal handle it

	return {handled = false}

# ═══════════════════════════════════════════════════════════════════════════════
# PRIORITY 1: REACTIVE INTERRUPTS
# ═══════════════════════════════════════════════════════════════════════════════

func _check_reactive_interrupts() -> Dictionary:
	# Check for other players nearby (social/PvP awareness)
	var nearby_players = _get_nearby_players(300.0)
	if nearby_players.size() > 0 and not _goal_data.get("players_notified", false):
		_goal_data["players_notified"] = true
		_queue_event("players_nearby", {
			count = nearby_players.size(),
			players = nearby_players
		})
		# Don't interrupt, just notify Claude

	# Reset notification flag if players leave
	if nearby_players.size() == 0:
		_goal_data["players_notified"] = false

	return {handled = false}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

func _execute_current_goal(delta: float) -> Dictionary:
	match current_goal:
		"idle":
			return _goal_idle(delta)
		"gear_up":
			return _goal_gear_up(delta)
		"combat":
			return _goal_combat(delta)
		"loot_corpse":
			return _goal_loot_corpse(delta)
		"flee_to_campfire":
			return _goal_flee_to_campfire(delta)
		"heal_at_campfire":
			return _goal_heal_at_campfire(delta)
		"quest_grind":
			return _goal_quest_grind(delta)
		_:
			return {status = "unknown_goal", goal = current_goal}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: IDLE - Do nothing, wait for commands
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_idle(_delta: float) -> Dictionary:
	return {status = "idle", goal = "idle"}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: GEAR UP - Check and equip gear automatically
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_gear_up(delta: float) -> Dictionary:
	var state = _goal_data.get("gear_state", "check")

	match state:
		"check":
			# Check what gear we're missing
			var missing = _get_missing_gear()
			if missing.size() == 0:
				_queue_event("gear_complete", {})
				set_goal("idle", Priority.STRATEGIC)
				return {status = "success", message = "fully_geared"}

			_goal_data["missing_gear"] = missing
			_goal_data["gear_state"] = "buy"
			return {status = "running", missing = missing}

		"buy":
			# Buy missing gear (one piece at a time)
			var missing = _goal_data.get("missing_gear", [])
			if missing.size() == 0:
				_goal_data["gear_state"] = "equip"
				return {status = "running", state = "moving_to_equip"}

			var slot = missing[0]
			var bought = _buy_gear_for_slot(slot)
			if bought:
				missing.remove_at(0)
				_goal_data["missing_gear"] = missing
				return {status = "running", bought = slot}
			else:
				# Can't afford or not available, skip
				missing.remove_at(0)
				_goal_data["missing_gear"] = missing
				return {status = "running", skipped = slot}

		"equip":
			# Equip best gear
			_equip_best_gear()
			_goal_data["gear_state"] = "verify"
			return {status = "running", state = "equipping"}

		"verify":
			# Verify gear is equipped
			var max_hp = _get_max_hp()
			if max_hp > 100:  # Got stat bonuses
				_queue_event("gear_complete", {max_hp = max_hp})
				set_goal("idle", Priority.STRATEGIC)
				return {status = "success", max_hp = max_hp}
			else:
				# Still no gear bonuses, might need more
				set_goal("idle", Priority.STRATEGIC)
				return {status = "partial", max_hp = max_hp}

	return {status = "running", state = state}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: COMBAT - Fight current target
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_combat(delta: float) -> Dictionary:
	_action_timer -= delta

	# Check if target is valid and alive
	var target_dead := false
	if not is_instance_valid(_combat_target):
		target_dead = true
	elif _combat_target.has_method("is_dead") and _combat_target.is_dead():
		target_dead = true
	elif "hp" in _combat_target and _combat_target.hp <= 0:
		target_dead = true

	if target_dead:
		# Target dead - check for corpse to loot
		var corpse = _find_nearest_corpse()
		if corpse:
			_loot_target = corpse
			set_goal("loot_corpse", Priority.TACTICAL)
			return {status = "target_dead", next = "loot"}

		# No corpse, find new target or go idle
		var new_target = _find_nearest_enemy()
		if new_target:
			_combat_target = new_target
			return {status = "new_target", target = new_target.name}

		set_goal("idle", Priority.STRATEGIC)
		return {status = "no_targets"}

	# Check HP - retreat if low
	var hp_percent = _get_hp_percent()
	if hp_percent < LOW_HP:
		set_goal("flee_to_campfire", Priority.CRITICAL)
		return {status = "retreating", hp = hp_percent}

	var dist = player.global_position.distance_to(_combat_target.global_position)

	# Move toward target if too far
	if dist > MELEE_RANGE:
		_move_toward(_combat_target.global_position)
		return {status = "approaching", distance = dist, target = _combat_target.name}

	# In range - attack
	if _action_timer <= 0:
		_face_target(_combat_target.global_position)
		_do_attack()
		_action_timer = ATTACK_COOLDOWN
		return {status = "attacking", target = _combat_target.name}

	# Waiting for cooldown
	_face_target(_combat_target.global_position)
	return {status = "combat", target = _combat_target.name, cooldown = _action_timer}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: LOOT CORPSE - Human-like looting sequence
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_loot_corpse(delta: float) -> Dictionary:
	var state = _goal_data.get("loot_state", "approach")

	if not is_instance_valid(_loot_target):
		# Corpse gone, find another or return to combat
		var corpse = _find_nearest_corpse()
		if corpse:
			_loot_target = corpse
			_goal_data["loot_state"] = "approach"
			return {status = "new_corpse"}

		# No more corpses, back to combat or idle
		var enemy = _find_nearest_enemy()
		if enemy:
			_combat_target = enemy
			set_goal("combat", Priority.TACTICAL)
			return {status = "done_looting", next = "combat"}

		set_goal("idle", Priority.STRATEGIC)
		return {status = "done_looting", next = "idle"}

	match state:
		"approach":
			var dist = player.global_position.distance_to(_loot_target.global_position)
			if dist > LOOT_RANGE:
				_move_toward(_loot_target.global_position)
				return {status = "approaching_corpse", distance = dist}

			# Close enough, press F to open loot UI
			_stop_movement()
			_goal_data["loot_state"] = "open_ui"
			_goal_data["loot_timer"] = 0.0
			_simulate_interact()
			return {status = "opening_loot_ui"}

		"open_ui":
			_goal_data["loot_timer"] = _goal_data.get("loot_timer", 0.0) + delta
			if _goal_data["loot_timer"] > 0.3:
				# UI should be open, press F again to take all
				_goal_data["loot_state"] = "take_all"
				_goal_data["loot_timer"] = 0.0
				_simulate_interact()
				return {status = "taking_all"}
			return {status = "waiting_for_ui"}

		"take_all":
			_goal_data["loot_timer"] = _goal_data.get("loot_timer", 0.0) + delta
			if _goal_data["loot_timer"] > 0.3:
				# Done looting this corpse
				_loot_target = null
				_goal_data["loot_state"] = "approach"

				# Check for more corpses or continue
				var corpse = _find_nearest_corpse()
				if corpse:
					_loot_target = corpse
					return {status = "next_corpse"}

				var enemy = _find_nearest_enemy()
				if enemy:
					_combat_target = enemy
					set_goal("combat", Priority.TACTICAL)
					return {status = "done_looting", next = "combat"}

				set_goal("idle", Priority.STRATEGIC)
				return {status = "done_looting", next = "idle"}

			return {status = "looting"}

	return {status = "running", state = state}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: FLEE TO CAMPFIRE
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_flee_to_campfire(delta: float) -> Dictionary:
	var campfire = _find_campfire()
	if not campfire:
		_queue_event("no_campfire", {})
		set_goal("idle", Priority.STRATEGIC)
		return {status = "failure", reason = "no_campfire"}

	var dist = player.global_position.distance_to(campfire.global_position)

	if dist > 80.0:
		_move_toward(campfire.global_position)
		return {status = "fleeing", distance = dist}

	# Arrived at campfire
	_stop_movement()
	set_goal("heal_at_campfire", Priority.TACTICAL)
	return {status = "arrived", next = "healing"}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: HEAL AT CAMPFIRE
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_heal_at_campfire(_delta: float) -> Dictionary:
	var hp_percent = _get_hp_percent()

	if hp_percent >= SAFE_HP:
		_queue_event("healed", {hp_percent = hp_percent})
		set_goal("idle", Priority.STRATEGIC)
		return {status = "healed", hp = hp_percent}

	# Stay at campfire
	return {status = "healing", hp = hp_percent}

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL: QUEST GRIND - Combat + Loot loop
# ═══════════════════════════════════════════════════════════════════════════════

func _goal_quest_grind(delta: float) -> Dictionary:
	var hp_percent = _get_hp_percent()

	# Check HP first
	if hp_percent < LOW_HP:
		set_goal("flee_to_campfire", Priority.CRITICAL)
		return {status = "low_hp", action = "retreating"}

	# If being attacked, prioritize combat over looting
	if _is_being_attacked():
		var attacker = _get_attacker()
		if attacker:
			_combat_target = attacker
			_loot_target = null  # Cancel any pending loot
			var combat_result = _goal_combat(delta)
			combat_result["mode"] = "quest_grind"
			combat_result["reason"] = "under_attack"
			return combat_result

	# Check for corpses to loot (only when safe)
	var corpse = _find_nearest_corpse()
	if corpse:
		# Only reset loot_state if this is a NEW corpse target
		var is_new_corpse = _loot_target != corpse
		if is_new_corpse:
			_loot_target = corpse
			_goal_data["loot_state"] = "approach"
		# Handle looting inline
		var loot_result = _goal_loot_corpse(delta)
		loot_result["mode"] = "quest_grind"
		loot_result["loot_state"] = _goal_data.get("loot_state", "unknown")
		loot_result["is_new_corpse"] = is_new_corpse
		return loot_result

	# Find enemy to fight
	var enemy = _find_nearest_enemy()
	if not enemy:
		return {status = "searching", message = "no_enemies_nearby"}

	_combat_target = enemy
	var combat_result = _goal_combat(delta)
	combat_result["mode"] = "quest_grind"
	return combat_result

# ═══════════════════════════════════════════════════════════════════════════════
# GOAL SETTER
# ═══════════════════════════════════════════════════════════════════════════════

func set_goal(goal_name: String, priority: Priority = Priority.STRATEGIC, data: Dictionary = {}) -> void:
	# Only interrupt if higher priority (lower number)
	if priority > current_priority and current_goal != "idle":
		print("[BT] Goal '%s' blocked by higher priority '%s'" % [goal_name, current_goal])
		return

	print("[BT] Setting goal: %s (priority %d)" % [goal_name, priority])
	current_goal = goal_name
	current_priority = priority
	_goal_data = data
	_action_timer = 0.0

# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

func _find_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _get_hp_percent() -> float:
	if not player or not "hp" in player:
		return 1.0
	var hp = player.hp
	var max_hp = player.max_hp if "max_hp" in player else 100.0
	return hp / max_hp if max_hp > 0 else 1.0

func _get_max_hp() -> float:
	if not player:
		return 100.0
	return player.max_hp if "max_hp" in player else 100.0

func _find_nearest_enemy() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest: Node2D = null
	var nearest_dist := 999999.0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		# Skip training dummies - prefer real enemies
		if "TrainingDummy" in enemy.name or "training" in enemy.name.to_lower():
			continue
		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist

	return nearest

func _find_nearest_corpse() -> Node2D:
	var corpses = get_tree().get_nodes_in_group("corpses")
	var nearest: Node2D = null
	var nearest_dist := CORPSE_SEARCH_RADIUS

	for corpse in corpses:
		if not is_instance_valid(corpse):
			continue
		var dist = player.global_position.distance_to(corpse.global_position)
		if dist < nearest_dist:
			nearest = corpse
			nearest_dist = dist

	return nearest

func _find_campfire() -> Node2D:
	var campfires = get_tree().get_nodes_in_group("campfires")
	if campfires.size() > 0:
		return campfires[0]
	return null

func _is_being_attacked() -> bool:
	# Check if any enemy is targeting us
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("get_target") and enemy.get_target() == player:
			return true
		# Also check distance - if very close, assume attacking
		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < 80.0:
			return true
	return false

func _get_attacker() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var closest_dist := 999999.0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest = enemy
			closest_dist = dist

	return closest if closest_dist < THREAT_RANGE else null

func _get_nearby_players(radius: float) -> Array:
	var result = []
	var all_players = get_tree().get_nodes_in_group("player")
	for p in all_players:
		if p == player:
			continue
		if not is_instance_valid(p):
			continue
		var dist = player.global_position.distance_to(p.global_position)
		if dist < radius:
			result.append({
				name = p.name,
				distance = dist,
				position = {x = p.global_position.x, y = p.global_position.y}
			})
	return result

func _get_missing_gear() -> Array:
	var missing = []
	if not player:
		return missing

	# Check equipped gear
	var equipment = player.equipped if "equipped" in player else {}

	if not equipment.get("weapon"):
		missing.append("weapon")
	if not equipment.get("head"):
		missing.append("head")
	if not equipment.get("chest"):
		missing.append("chest")
	if not equipment.get("legs"):
		missing.append("legs")
	if not equipment.get("feet"):
		missing.append("feet")
	if not equipment.get("hands"):
		missing.append("hands")
	if not equipment.get("offhand"):
		missing.append("offhand")

	return missing

func _buy_gear_for_slot(slot: String) -> bool:
	# Use MCPBridge's shop buying logic
	if not mcp_bridge:
		return false

	# Map slot to item type for shop
	var item_id = ""
	var item_type = "armor"

	match slot:
		"weapon":
			item_id = "test_longsword"  # Free test weapon
			item_type = "weapon"
		"head":
			item_id = "copper_plate_helm"
			item_type = "armor"
		"chest":
			item_id = "copper_plate_cuirass"
			item_type = "armor"
		"legs":
			item_id = "copper_plate_greaves"
			item_type = "armor"
		"feet":
			item_id = "copper_plate_boots"
			item_type = "armor"
		"hands":
			item_id = "copper_plate_gloves"
			item_type = "armor"
		"offhand":
			item_id = "starter_shield"
			item_type = "armor"

	if item_id == "":
		return false

	# Try to buy (mcp_bridge handles shop interaction)
	var result = mcp_bridge._cmd_buy_item(item_id, item_type)
	return result.get("ok", false)

func _equip_best_gear() -> void:
	if mcp_bridge and mcp_bridge.has_method("_cmd_equip_best"):
		mcp_bridge._cmd_equip_best()

func _move_toward(target_pos: Vector2) -> void:
	if not player:
		return

	var direction = (target_pos - player.global_position).normalized()

	# Set movement input on player
	if "velocity" in player:
		var move_speed = player.move_speed if "move_speed" in player else 100.0
		player.velocity = direction * move_speed

	# Or use input simulation
	if mcp_bridge:
		mcp_bridge._move_target = target_pos
		mcp_bridge._is_pathing = true

func _stop_movement() -> void:
	if player and "velocity" in player:
		player.velocity = Vector2.ZERO
	if mcp_bridge:
		mcp_bridge._is_pathing = false
		mcp_bridge._release_inputs()

func _face_target(target_pos: Vector2) -> void:
	if not player:
		return

	if mcp_bridge:
		mcp_bridge._face_target = target_pos
		mcp_bridge._is_facing = true

	# Also update player facing if it has facing direction
	if "facing_direction" in player:
		player.facing_direction = (target_pos - player.global_position).normalized()

func _do_attack() -> void:
	if not player:
		return

	# Trigger attack via combat system
	var combat_system = get_node_or_null("/root/CombatSystem")
	if combat_system and combat_system.has_method("do_player_attack"):
		combat_system.do_player_attack()
	elif player.has_method("attack"):
		player.attack()
	elif player.has_method("start_attack"):
		player.start_attack()

func _simulate_interact() -> void:
	# Simulate F key press for interactions
	var event = InputEventKey.new()
	event.keycode = KEY_F
	event.pressed = true
	Input.parse_input_event(event)

	# Release after short delay
	await get_tree().create_timer(0.05).timeout
	event.pressed = false
	Input.parse_input_event(event)

# ═══════════════════════════════════════════════════════════════════════════════
# EVENT QUEUE FOR CLAUDE
# ═══════════════════════════════════════════════════════════════════════════════

func _queue_event(event_type: String, data: Dictionary) -> void:
	_pending_events.append({
		type = event_type,
		data = data,
		timestamp = Time.get_ticks_msec()
	})
	event_for_claude.emit(event_type, data)

func get_pending_events() -> Array:
	var events = _pending_events.duplicate()
	_pending_events.clear()
	return events

func has_pending_events() -> bool:
	return _pending_events.size() > 0

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS REPORTING
# ═══════════════════════════════════════════════════════════════════════════════

func get_status() -> Dictionary:
	return {
		enabled = bt_enabled,
		paused = bt_paused,
		goal = current_goal,
		priority = current_priority,
		has_player = player != null,
		hp_percent = _get_hp_percent(),
		combat_target = _combat_target.name if is_instance_valid(_combat_target) else null,
		loot_target = _loot_target.name if is_instance_valid(_loot_target) else null,
		pending_events = _pending_events.size()
	}
