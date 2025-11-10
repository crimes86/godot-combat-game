extends Node
class_name CritWindowManager

# Which prototype to use
enum WindowType { ORBITAL_RING, GROWING_SPRITE }
@export var window_type: WindowType = WindowType.GROWING_SPRITE

# Settings
@export var window_duration: float = 3.0
@export var num_beats: int = 3
@export var time_slow_amount: float = 0.7

# State
var is_active: bool = false
var current_target: Node = null
var beats_hit: int = 0
var beats_total: int = 0
var difficulty_multiplier: float = 1.0

# Visuals
var orbital_ring: Node2D = null
var original_time_scale: float = 1.0

signal window_completed(success_ratio: float, total_destroyed: int)

func _ready() -> void:
	original_time_scale = Engine.time_scale

func start_window(target: Node, difficulty: float = 1.0) -> void:
	# REMOVED: Don't check is_active - allow multiple concurrent windows
	# Each enemy manages its own window state
	
	print("=== CRIT WINDOW STARTED on ", target.name, " (", WindowType.keys()[window_type], ", difficulty: ", difficulty, ") ===")
	
	# Slow time (client-side) - only do this once if not already slowed
	if Engine.time_scale == original_time_scale:
		Engine.time_scale = time_slow_amount
	
	# Start the appropriate visual system
	if window_type == WindowType.ORBITAL_RING:
		start_orbital_ring_window(target, difficulty)
	else:
		start_growing_sprite_window(target, difficulty)

func start_orbital_ring_window(target: Node, difficulty: float) -> void:
	# Create orbital ring visual
	var ring = preload("res://scenes/ui/orbital_ring.tscn").instantiate()
	target.add_child(ring)
	ring.setup(num_beats, window_duration)
	ring.beat_hit.connect(_on_beat_hit)
	ring.window_ended.connect(_on_window_ended)

func start_growing_sprite_window(target: Node, difficulty: float) -> void:
	# Tell enemy to start growing sprite mode with weakpoints
	if target.has_method("start_crit_window"):
		target.start_crit_window(difficulty)
		# Connect to THIS specific enemy's signals
		if not target.weakpoint_hit_success.is_connected(_on_weakpoint_hit):
			target.weakpoint_hit_success.connect(_on_weakpoint_hit)
		if not target.crit_window_complete.is_connected(_on_window_ended_weakpoints):
			target.crit_window_complete.connect(_on_window_ended_weakpoints.bind(target))
	else:
		print("ERROR: Target doesn't have start_crit_window method!")

func _on_beat_hit(success: bool) -> void:
	if success:
		beats_hit += 1
		print("✓ Beat hit! (", beats_hit, "/", beats_total, ")")
	else:
		print("✗ Beat missed!")

func _on_weakpoint_hit() -> void:
	beats_hit += 1
	print("✓ Weakpoint hit! (", beats_hit, " total hits)")

func _on_window_ended() -> void:
	# For orbital ring
	var success_ratio = float(beats_hit) / float(beats_total)
	print("=== WINDOW COMPLETE: ", beats_hit, "/", beats_total, " ===")
	
	cleanup()
	window_completed.emit(success_ratio, beats_hit)

func _on_window_ended_weakpoints(destroyed_count: int, target: Node) -> void:
	print("=== WINDOW COMPLETE on ", target.name if is_instance_valid(target) else "destroyed target", ": ", destroyed_count, "/", beats_total, " weakpoints destroyed ===")
	
	# Check if any other enemies still have crit windows active
	# If not, restore time scale
	var other_windows_active = false
	for node in get_tree().get_nodes_in_group("enemies"):
		if node != target and is_instance_valid(node) and node.in_crit_window:
			other_windows_active = true
			break
	
	if not other_windows_active:
		Engine.time_scale = original_time_scale
		print("All crit windows closed - time scale restored")
	
	window_completed.emit(float(destroyed_count) / float(beats_total), destroyed_count)

func cleanup() -> void:
	print("CritWindowManager: Starting cleanup...")
	
	# Reset time
	Engine.time_scale = original_time_scale
	
	# Clean up orbital ring
	if orbital_ring:
		orbital_ring.queue_free()
		orbital_ring = null
	
	# Disconnect signals
	if current_target and is_instance_valid(current_target):
		if current_target.has_signal("beat_hit") and current_target.beat_hit.is_connected(_on_beat_hit):
			current_target.beat_hit.disconnect(_on_beat_hit)
		if current_target.has_signal("window_ended") and current_target.window_ended.is_connected(_on_window_ended):
			current_target.window_ended.disconnect(_on_window_ended)
		if current_target.has_signal("weakpoint_hit_success") and current_target.weakpoint_hit_success.is_connected(_on_weakpoint_hit):
			current_target.weakpoint_hit_success.disconnect(_on_weakpoint_hit)
		if current_target.has_signal("crit_window_complete") and current_target.crit_window_complete.is_connected(_on_window_ended_weakpoints):
			current_target.crit_window_complete.disconnect(_on_window_ended_weakpoints)
	
	# CRITICAL: Reset state
	current_target = null
	is_active = false
	
	print("CritWindowManager: Cleanup complete! is_active = ", is_active)
