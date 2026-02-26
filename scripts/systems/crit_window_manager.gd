extends Node
class_name CritWindowManager

## Manages crit windows for multiple enemies concurrently
## Owns all timers, lifecycle, and state - enemies just provide visual hooks
##
## WEAKPOINT TRIGGER SYSTEM (v2.1):
## Windows are triggered by HIT COUNT and HEALTH THRESHOLDS, not random crits.
## This ensures consistent, skill-based combat rather than RNG coinflips.
##
## CRITICAL: Weakpoint damage does NOT count toward threshold triggers.
## Only normal attack damage decrements "threshold HP" - this prevents
## chain-killing where one weakpoint burst skips multiple thresholds.

# State - track MULTIPLE concurrent windows (one per enemy)
var active_windows: Dictionary = {}  # {enemy_instance: WindowData}

# Hit tracking per enemy (for hit-count-based triggers)
var enemy_hit_counts: Dictionary = {}  # {enemy_instance: int}

# Health threshold tracking (which thresholds have been triggered)
var enemy_triggered_thresholds: Dictionary = {}  # {enemy_instance: Array[float]]

# Threshold HP tracking - only decremented by normal attacks, not weakpoint damage
# This prevents weakpoint burst from skipping HP thresholds
var enemy_threshold_hp: Dictionary = {}  # {enemy_instance: {current: float, max: float}}

# Window data for each enemy
class WindowData:
	var target: Node
	var timer: Timer
	var weakpoints_spawned: int = 0
	var weakpoints_destroyed: int = 0
	var total_damage_dealt: int = 0  # Track for server validation
	var difficulty: float = 1.0
	var damage_per_hit: int = 0  # Calculated at window start
	var weakpoint_refs: Array = []  # Track weakpoint references for damage collection

	func _init(t: Node, d: float):
		target = t
		difficulty = d

signal window_completed(success_ratio: float, total_destroyed: int)

# ============================================
# WEAKPOINT TRIGGER SYSTEM (v2.1)
# ============================================

func register_hit(target: Node, damage: float, target_health_before: float, target_max_health: float) -> bool:
	"""
	Register a NORMAL hit on an enemy and check if it should trigger a weakpoint window.
	Returns true if a window was triggered.

	Call this from PlayerCombat INSTEAD of directly calling start_window on crits.

	IMPORTANT: Only call this for NORMAL attacks, not weakpoint damage.
	Weakpoint damage should go directly to take_damage() without calling this.
	This ensures weakpoint burst doesn't skip HP thresholds.
	"""
	if not is_instance_valid(target):
		return false

	# Don't trigger new window if one is already active
	if active_windows.has(target):
		return false

	var triggered = false

	# Initialize tracking for this enemy if needed
	if not enemy_hit_counts.has(target):
		enemy_hit_counts[target] = 0
	if not enemy_triggered_thresholds.has(target):
		enemy_triggered_thresholds[target] = []

	# Initialize threshold HP tracking on first hit
	# Threshold HP is separate from actual HP - only decremented by normal attacks
	if not enemy_threshold_hp.has(target):
		enemy_threshold_hp[target] = {
			"current": target_health_before,
			"max": target_max_health
		}

	# Increment hit count
	enemy_hit_counts[target] += 1
	var current_hits = enemy_hit_counts[target]

	# Check hit count trigger
	var hit_threshold = Constants.WEAKPOINT_TRIGGER_HIT_COUNT if "WEAKPOINT_TRIGGER_HIT_COUNT" in Constants else 8
	if current_hits >= hit_threshold:
		print("🎯 [WeakpointTrigger] Hit count threshold reached (%d hits) - triggering window!" % current_hits)
		enemy_hit_counts[target] = 0  # Reset counter
		triggered = true

	# Check health threshold triggers (only if not already triggered by hit count)
	if not triggered:
		# Use THRESHOLD HP, not actual HP - this prevents weakpoint burst from skipping thresholds
		var threshold_data = enemy_threshold_hp[target]
		var threshold_hp_before = threshold_data["current"]
		var threshold_hp_after = threshold_hp_before - damage
		var threshold_max = threshold_data["max"]

		# Update threshold HP (only normal damage decrements this)
		threshold_data["current"] = threshold_hp_after

		var threshold_pct_before = threshold_hp_before / threshold_max
		var threshold_pct_after = threshold_hp_after / threshold_max

		var thresholds = Constants.WEAKPOINT_TRIGGER_HEALTH_THRESHOLDS if "WEAKPOINT_TRIGGER_HEALTH_THRESHOLDS" in Constants else [0.75, 0.50, 0.25]
		var already_triggered = enemy_triggered_thresholds[target]

		for threshold in thresholds:
			# Check if we crossed this threshold with this hit (using threshold HP, not actual HP)
			if threshold_pct_before > threshold and threshold_pct_after <= threshold:
				# Check if this threshold was already triggered
				if threshold not in already_triggered:
					print("🎯 [WeakpointTrigger] Threshold HP crossed (%.0f%%) - triggering window! (Threshold HP: %.1f/%.1f)" % [threshold * 100, threshold_hp_after, threshold_max])
					already_triggered.append(threshold)
					triggered = true
					break  # Only trigger one window per hit

	# Start the window if triggered
	if triggered:
		start_window(target)

	return triggered

func clear_enemy_tracking(target: Node) -> void:
	"""Clear all tracking data for an enemy (call when enemy dies)"""
	enemy_hit_counts.erase(target)
	enemy_triggered_thresholds.erase(target)
	enemy_threshold_hp.erase(target)

func has_active_window_for(target: Node) -> bool:
	"""Check if target has an active weakpoint window"""
	return active_windows.has(target)

func get_threshold_hp_info(target: Node) -> Dictionary:
	"""Get threshold HP tracking info for debugging/UI (separate from actual HP)"""
	if enemy_threshold_hp.has(target):
		var data = enemy_threshold_hp[target]
		return {
			"current": data["current"],
			"max": data["max"],
			"percent": data["current"] / data["max"] if data["max"] > 0 else 0.0
		}
	return {"current": 0.0, "max": 0.0, "percent": 0.0}

# ============================================
# ORIGINAL WINDOW MANAGEMENT
# ============================================

func start_window(target: Node, difficulty: float = 1.0) -> void:
	"""Start a crit window on the target enemy"""
	if not is_instance_valid(target):
		push_error("CritWindowManager: Invalid target for crit window")
		return

	# Check if target already has an active window
	if active_windows.has(target):
		return

	# Create window data
	var window_data = WindowData.new(target, difficulty)
	active_windows[target] = window_data

	# Start the growing sprite crit window
	_start_growing_sprite_window(target, window_data)

func _start_growing_sprite_window(target: Node, window_data: WindowData) -> void:
	"""Start growing sprite mode with weakpoints"""

	# Calculate damage per hit for this window (used for client tracking)
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player:
		var base_damage = player.get("attack_damage") if player.get("attack_damage") != null else 10
		var crit_mult = Constants.CRIT_DAMAGE_MULTIPLIER if "CRIT_DAMAGE_MULTIPLIER" in Constants else 2.0
		window_data.damage_per_hit = int(base_damage * crit_mult)

	# ✨ FIX: Connect signals BEFORE calling grow_for_crit_window()
	# This prevents race condition where weakpoints spawn before signals are connected
	if target.has_signal("weakpoint_spawned"):
		if not target.weakpoint_spawned.is_connected(_on_weakpoint_spawned):
			target.weakpoint_spawned.connect(_on_weakpoint_spawned.bind(target, window_data))

	if target.has_signal("weakpoint_destroyed"):
		if not target.weakpoint_destroyed.is_connected(_on_weakpoint_destroyed):
			target.weakpoint_destroyed.connect(_on_weakpoint_destroyed.bind(target))

	if target.has_signal("died"):
		if not target.died.is_connected(_on_target_died):
			target.died.connect(_on_target_died.bind(target))

	# Create and start timer (owned by manager) BEFORE grow starts
	# Scale duration by corruption tier: Clean=longer, Cursed=shorter
	var base_duration = Constants.CRIT_WINDOW_DURATION
	var corruption_scale = 1.0
	if OssuaryManager:
		var c_tier = OssuaryManager.get_corruption_tier()
		match c_tier:
			0: corruption_scale = 1.5   # Clean: 6.0s — more time
			1: corruption_scale = 1.25  # Tainted: 5.0s
			2: corruption_scale = 1.0   # Blighted: 4.0s — no change
			3: corruption_scale = 0.85  # Cursed: 3.4s — shorter, harder

	var timer = Timer.new()
	timer.wait_time = base_duration * corruption_scale
	timer.one_shot = true
	timer.timeout.connect(_on_window_timeout.bind(target))
	add_child(timer)
	timer.start()
	window_data.timer = timer

	# Tell target to grow (visual only) - signals already connected
	if target.has_method("grow_for_crit_window"):
		target.grow_for_crit_window(window_data.difficulty)
	else:
		push_error("Target missing grow_for_crit_window() method!")
		end_window(target, 0)
		return

	# SERVER SYNC: Request validation from server for weakpoint window
	# Weakpoints start in "charging" state - server confirmation activates them
	# This hides 200ms network latency behind the charging animation
	_request_window_validation(target, window_data)

func _on_weakpoint_spawned(weakpoint: Node, target: Node, window_data: WindowData) -> void:
	"""Track when a weakpoint is spawned and configure it for client-predicted hits"""
	if not active_windows.has(target):
		return

	window_data.weakpoints_spawned += 1
	window_data.weakpoint_refs.append(weakpoint)

	# Set damage per hit on the weakpoint for client-side tracking
	if weakpoint.has_method("set_damage_per_hit"):
		weakpoint.set_damage_per_hit(window_data.damage_per_hit)

func _on_weakpoint_destroyed(weakpoint: Node, target: Node) -> void:
	"""Track when a weakpoint is destroyed"""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]
	window_data.weakpoints_destroyed += 1

	# Track weakpoint for forged weapon stats
	var local_player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if local_player and local_player.get("combat_system") and local_player.combat_system.has_method("_track_weakpoint_destroyed"):
		local_player.combat_system._track_weakpoint_destroyed()

	# Check if all weakpoints destroyed
	if window_data.weakpoints_destroyed >= window_data.weakpoints_spawned:
		# End window immediately (shrink enemy)
		end_window(target, window_data.weakpoints_destroyed)

		# Small delay to let explosion animation complete before cleanup
		await get_tree().create_timer(0.55).timeout

func _on_window_timeout(target: Node) -> void:
	"""Window timer expired - force close the window and cleanup remaining weakpoints"""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]

	# Force-destroy any remaining weakpoints before ending window
	_cleanup_remaining_weakpoints(target, window_data)

	# End the window with however many weakpoints were destroyed
	end_window(target, window_data.weakpoints_destroyed)

func _cleanup_remaining_weakpoints(target: Node, window_data: WindowData) -> void:
	"""Force cleanup any remaining weakpoints when window times out"""
	if not is_instance_valid(target):
		return

	# Clear weakpoints from the target's array
	if "weakpoints" in target:
		for wp in target.weakpoints:
			if is_instance_valid(wp):
				# Disable interaction immediately
				if wp.has_method("set") and "input_pickable" in wp:
					wp.input_pickable = false
				# Queue for deletion
				wp.queue_free()
		target.weakpoints.clear()

	# Also clear our refs
	window_data.weakpoint_refs.clear()

func _on_target_died(target: Node) -> void:
	"""Target died - end window immediately and clear tracking"""
	# Clear hit/threshold tracking for this enemy
	clear_enemy_tracking(target)

	if not active_windows.has(target):
		return
	end_window(target, 0)

func end_window(target: Node, weakpoints_destroyed: int) -> void:
	"""End a crit window (called when weakpoints cleared or enemy dies)"""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]

	# Collect total damage from all weakpoints (client-side tracking)
	var total_damage = _collect_total_damage(window_data)

	# Stop and cleanup timer
	if window_data.timer and is_instance_valid(window_data.timer):
		window_data.timer.stop()
		window_data.timer.queue_free()
		window_data.timer = null

	# Disconnect signals
	if is_instance_valid(target):
		if target.has_signal("weakpoint_spawned") and target.weakpoint_spawned.is_connected(_on_weakpoint_spawned):
			target.weakpoint_spawned.disconnect(_on_weakpoint_spawned)

		if target.has_signal("weakpoint_destroyed") and target.weakpoint_destroyed.is_connected(_on_weakpoint_destroyed):
			target.weakpoint_destroyed.disconnect(_on_weakpoint_destroyed)

		if target.has_signal("died") and target.died.is_connected(_on_target_died):
			target.died.disconnect(_on_target_died)

		# Tell target to shrink back (visual only)
		if target.has_method("shrink_after_crit_window"):
			target.shrink_after_crit_window()

	# Report results to server (client-predicted system)
	_report_window_results(target, weakpoints_destroyed, total_damage)

	# Remove from active windows
	active_windows.erase(target)

	# Emit completion signal
	var success_ratio = float(weakpoints_destroyed) / float(max(1, window_data.weakpoints_spawned))
	window_completed.emit(success_ratio, weakpoints_destroyed)

func _collect_total_damage(window_data: WindowData) -> int:
	"""Collect total damage dealt from all weakpoints in this window"""
	var total = 0
	for wp in window_data.weakpoint_refs:
		if is_instance_valid(wp) and wp.has_method("get_damage_dealt"):
			total += wp.get_damage_dealt()
	return total

func _report_window_results(target: Node, weakpoints_destroyed: int, total_damage: int) -> void:
	"""Report crit window results to server for validation"""
	if not multiplayer.has_multiplayer_peer():
		# Single player - apply damage directly
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(total_damage)
		return

	var enemy_net_id = -1
	if is_instance_valid(target):
		enemy_net_id = target.get("network_id") if target.get("network_id") != null else -1

	if enemy_net_id < 0:
		return

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if not network_enemy_mgr:
		return

	if multiplayer.is_server():
		# Server processes directly (no RPC needed)
		network_enemy_mgr.process_crit_window_result(enemy_net_id, weakpoints_destroyed, total_damage, multiplayer.get_unique_id())
	else:
		# Client reports to server
		network_enemy_mgr.report_crit_window_result.rpc_id(1, enemy_net_id, weakpoints_destroyed, total_damage)

# ============================================
# SERVER-SYNCED WEAKPOINT ACTIVATION
# ============================================
# Weakpoints spawn in "charging" state and are activated after server confirms.
# This hides 200ms network latency behind a charging animation.

func _request_window_validation(target: Node, window_data: WindowData) -> void:
	"""Request server validation for weakpoint window.
	In single-player or as server, immediately activate weakpoints.
	As client, request confirmation from server."""
	if not multiplayer.has_multiplayer_peer():
		# Single player - immediately activate weakpoints after a brief moment
		# (let the spawn animation start first)
		get_tree().create_timer(0.1).timeout.connect(_activate_weakpoints.bind(target))
		return

	var enemy_net_id = target.get("network_id") if target.get("network_id") != null else -1

	if multiplayer.is_server():
		# We are the server - immediately activate weakpoints after brief delay
		get_tree().create_timer(0.1).timeout.connect(_activate_weakpoints.bind(target))
	else:
		# Client - request validation from server
		var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
		if network_enemy_mgr and enemy_net_id >= 0:
			print("[CritWindow] Client requesting weakpoint validation for enemy %d" % enemy_net_id)
			network_enemy_mgr.request_weakpoint_window_validation.rpc_id(1, enemy_net_id)
			# FAILSAFE: If server doesn't respond within 500ms, activate anyway
			# This prevents weakpoints from being stuck in charging state on web/high latency
			get_tree().create_timer(0.5).timeout.connect(_activate_weakpoints_if_still_charging.bind(target))
		else:
			# Fallback: activate after timeout if no network manager
			print("[CritWindow] No network manager or invalid enemy_net_id (%d), using fallback" % enemy_net_id)
			get_tree().create_timer(0.25).timeout.connect(_activate_weakpoints.bind(target))

func _activate_weakpoints(target: Node) -> void:
	"""Activate all weakpoints for target - called when server confirms or in single-player."""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]

	for weakpoint in window_data.weakpoint_refs:
		if is_instance_valid(weakpoint) and weakpoint.has_method("activate"):
			weakpoint.activate()

func _activate_weakpoints_if_still_charging(target: Node) -> void:
	"""Failsafe: Activate weakpoints only if they're still in charging state.
	Called after timeout in case server confirmation never arrived."""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]
	var any_still_charging = false

	for weakpoint in window_data.weakpoint_refs:
		if is_instance_valid(weakpoint) and weakpoint.get("is_charging") == true:
			any_still_charging = true
			break

	if any_still_charging:
		print("[CritWindow] FAILSAFE: Server confirmation timeout, activating weakpoints anyway")
		_activate_weakpoints(target)

func on_server_confirm_window(enemy_network_id: int) -> void:
	"""Called when server confirms our weakpoint window is valid.
	Activates the weakpoints so player can click them."""
	# Find the target by network_id
	for target in active_windows:
		if is_instance_valid(target):
			var net_id = target.get("network_id") if target.get("network_id") != null else -1
			if net_id == enemy_network_id:
				_activate_weakpoints(target)
				return
