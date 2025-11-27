extends Node
class_name CritWindowManager

## Manages crit windows for multiple enemies concurrently
## Owns all timers, lifecycle, and state - enemies just provide visual hooks

# Which prototype to use
enum WindowType { ORBITAL_RING, GROWING_SPRITE }
@export var window_type: WindowType = WindowType.GROWING_SPRITE

# Settings - use Constants for authoritative values
@export var time_slow_amount: float = 0.7

# State - track MULTIPLE concurrent windows (one per enemy)
var active_windows: Dictionary = {}  # {enemy_instance: WindowData}
var original_time_scale: float = 1.0

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

func _ready() -> void:
	original_time_scale = Engine.time_scale

func start_window(target: Node, difficulty: float = 1.0) -> void:
	"""Start a crit window on the target enemy"""
	if not is_instance_valid(target):
		push_error("CritWindowManager: Invalid target for crit window")
		return

	# Check if target already has an active window
	if active_windows.has(target):
		return

	# NOTE: Time scaling disabled for multiplayer compatibility
	# Engine.time_scale is local to each machine and causes desync
	# if Engine.time_scale == original_time_scale:
	#     Engine.time_scale = time_slow_amount

	# Create window data
	var window_data = WindowData.new(target, difficulty)
	active_windows[target] = window_data

	# Start the appropriate window type
	if window_type == WindowType.ORBITAL_RING:
		_start_orbital_ring_window(target, window_data)
	else:
		_start_growing_sprite_window(target, window_data)

func _start_orbital_ring_window(target: Node, window_data: WindowData) -> void:
	"""Legacy orbital ring mode - not currently used"""
	push_warning("Orbital ring mode not fully supported in refactored version")

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
	# Use authoritative duration from Constants
	var timer = Timer.new()
	timer.wait_time = Constants.CRIT_WINDOW_DURATION
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

	# Check if all weakpoints destroyed
	if window_data.weakpoints_destroyed >= window_data.weakpoints_spawned:
		# Spawn success ring effect at player's feet IMMEDIATELY (buff effect!)
		var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player:
			_spawn_success_ring_at_position(player.global_position)

		# End window immediately (shrink enemy) - all happens at once!
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
	"""Target died - end window immediately"""
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

	# NOTE: Time scaling disabled for multiplayer compatibility
	# if active_windows.is_empty():
	#     Engine.time_scale = original_time_scale

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

func _spawn_success_ring_at_position(position: Vector2) -> void:
	"""Spawn a golden success ring effect at specified position"""
	# Load and instantiate the success ring script
	const SuccessRingScript = preload("res://scripts/vfx/success_ring.gd")
	var ring = Node2D.new()
	ring.set_script(SuccessRingScript)
	ring.global_position = position

	# Add to scene tree at root level
	get_tree().root.add_child(ring)
