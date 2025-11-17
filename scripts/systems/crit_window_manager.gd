extends Node
class_name CritWindowManager

## Manages crit windows for multiple enemies concurrently
## Owns all timers, lifecycle, and state - enemies just provide visual hooks

# Which prototype to use
enum WindowType { ORBITAL_RING, GROWING_SPRITE }
@export var window_type: WindowType = WindowType.GROWING_SPRITE

# Settings
@export var window_duration: float = 4.0  # Match Constants.CRIT_WINDOW_DURATION
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
	var difficulty: float = 1.0

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
		print("⚠️ CritWindowManager: Target already has active window - ignoring")
		return

	print("=== CRIT WINDOW STARTED on ", target.name, " (", WindowType.keys()[window_type], ", difficulty: ", difficulty, ") ===")

	# Slow time if not already slowed
	if Engine.time_scale == original_time_scale:
		Engine.time_scale = time_slow_amount

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

	# Tell target to grow (visual only)
	if target.has_method("grow_for_crit_window"):
		target.grow_for_crit_window(window_data.difficulty)
	else:
		push_error("Target missing grow_for_crit_window() method!")
		end_window(target, 0)
		return

	# Connect to target's signals
	if target.has_signal("weakpoint_spawned"):
		if not target.weakpoint_spawned.is_connected(_on_weakpoint_spawned):
			target.weakpoint_spawned.connect(_on_weakpoint_spawned.bind(target))

	if target.has_signal("weakpoint_destroyed"):
		if not target.weakpoint_destroyed.is_connected(_on_weakpoint_destroyed):
			target.weakpoint_destroyed.connect(_on_weakpoint_destroyed.bind(target))

	if target.has_signal("died"):
		if not target.died.is_connected(_on_target_died):
			target.died.connect(_on_target_died.bind(target))

	# Create and start timer (owned by manager)
	var timer = Timer.new()
	timer.wait_time = window_duration
	timer.one_shot = true
	timer.timeout.connect(_on_window_timeout.bind(target))
	add_child(timer)
	timer.start()
	window_data.timer = timer

	print("⏱️ CritWindowManager: Window timer started (%.1fs)" % window_duration)

func _on_weakpoint_spawned(target: Node) -> void:
	"""Track when a weakpoint is spawned"""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]
	window_data.weakpoints_spawned += 1
	print("🎯 CritWindowManager: Weakpoint spawned (%d total)" % window_data.weakpoints_spawned)

func _on_weakpoint_destroyed(weakpoint: Node, target: Node) -> void:
	"""Track when a weakpoint is destroyed"""
	if not active_windows.has(target):
		return

	var window_data = active_windows[target]
	window_data.weakpoints_destroyed += 1

	print("🔍 CritWindowManager: Weakpoint destroyed (%d/%d)" % [window_data.weakpoints_destroyed, window_data.weakpoints_spawned])

	# Check if all weakpoints destroyed
	if window_data.weakpoints_destroyed >= window_data.weakpoints_spawned:
		print("🎯 CritWindowManager: ALL WEAKPOINTS CLEARED - ending window")
		# Small delay to let explosion animation play
		await get_tree().create_timer(0.55).timeout
		end_window(target, window_data.weakpoints_destroyed)

func _on_window_timeout(target: Node) -> void:
	"""Window timer expired - but we don't auto-close, just log"""
	if not active_windows.has(target):
		return

	print("⏱️ CritWindowManager: 4-second timer expired for %s - window continues" % target.name)
	# NOTE: Window only closes when all weakpoints destroyed or enemy dies

func _on_target_died(target: Node) -> void:
	"""Target died - end window immediately"""
	if not active_windows.has(target):
		return

	print("💀 CritWindowManager: Target died - ending window")
	end_window(target, 0)

func end_window(target: Node, weakpoints_destroyed: int) -> void:
	"""End a crit window (called when weakpoints cleared or enemy dies)"""
	if not active_windows.has(target):
		print("⚠️ CritWindowManager: end_window() called but no active window for target")
		return

	var window_data = active_windows[target]

	print("🔚 CritWindowManager: ENDING window for %s (%d/%d weakpoints)" % [target.name, weakpoints_destroyed, window_data.weakpoints_spawned])

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

	# Remove from active windows
	active_windows.erase(target)

	# Restore time scale if no more active windows
	if active_windows.is_empty():
		Engine.time_scale = original_time_scale
		print("All crit windows closed - time scale restored")

	# Emit completion signal
	var success_ratio = float(weakpoints_destroyed) / float(max(1, window_data.weakpoints_spawned))
	window_completed.emit(success_ratio, weakpoints_destroyed)

	print("=== WINDOW COMPLETE on ", target.name if is_instance_valid(target) else "destroyed target", ": ", weakpoints_destroyed, "/", window_data.weakpoints_spawned, " weakpoints destroyed ===")
