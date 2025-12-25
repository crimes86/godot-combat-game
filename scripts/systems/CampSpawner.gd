extends Node2D
class_name CampSpawner

## Camp Spawner - Manages enemy spawns for camp grinding
## Creates the core EQ-style "find a camp, grind for hours" gameplay loop.
##
## Camp Types:
## - chill: 120s respawn, low danger, solo-friendly
## - standard: 90s respawn, medium danger, small groups
## - intense: 45s respawn, high danger, full parties

signal enemy_spawned(enemy: Node, spawn_index: int)
signal enemy_died(enemy: Node, spawn_index: int)
signal camp_cleared()  # All enemies killed (briefly)

@export var camp_name: String = "Unnamed Camp"
@export_enum("chill", "standard", "intense") var camp_type: String = "standard"
@export var enemy_level_min: int = 1
@export var enemy_level_max: int = 5
@export var max_enemies: int = 6
@export var elite_chance: float = 0.1
@export var enemy_scene: PackedScene = null  # If null, uses default skeleton

# Respawn timers by camp type
const RESPAWN_TIMERS = {
	"chill": 120.0,
	"standard": 90.0,
	"intense": 45.0
}

var spawn_points: Array[Marker2D] = []
var active_enemies: Dictionary = {}  # spawn_point_index -> enemy
var respawn_timers: Dictionary = {}  # spawn_point_index -> time_remaining

# Kill rate tracking for dynamic respawns
var kill_timestamps: Array[float] = []

# Default enemy scene path
const DEFAULT_ENEMY_SCENE = "res://scenes/enemies/enemy.tscn"

func _ready() -> void:
	# Find all Marker2D children as spawn points
	for child in get_children():
		if child is Marker2D:
			spawn_points.append(child)

	# Load default enemy scene if none specified
	if enemy_scene == null:
		enemy_scene = load(DEFAULT_ENEMY_SCENE)

	# Initial spawn after a short delay to let world initialize
	call_deferred("_initial_spawn")

	print("[CampSpawner] %s initialized: %d spawn points, type=%s, levels %d-%d" % [
		camp_name, spawn_points.size(), camp_type, enemy_level_min, enemy_level_max
	])


func _initial_spawn() -> void:
	"""Spawn initial enemies at all spawn points"""
	for i in spawn_points.size():
		_spawn_at_point(i)


func _process(delta: float) -> void:
	# Process respawn timers
	var to_spawn: Array[int] = []
	for idx in respawn_timers.keys():
		respawn_timers[idx] -= delta
		if respawn_timers[idx] <= 0:
			to_spawn.append(idx)

	for idx in to_spawn:
		respawn_timers.erase(idx)
		_spawn_at_point(idx)

	# Clean up old kill timestamps (keep last 60 seconds)
	_cleanup_old_timestamps()


func _spawn_at_point(index: int) -> void:
	"""Spawn an enemy at the given spawn point index"""
	if index >= spawn_points.size():
		return

	if not enemy_scene:
		push_error("[CampSpawner] No enemy scene loaded!")
		return

	var spawn_pos = spawn_points[index].global_position
	var enemy_level = randi_range(enemy_level_min, enemy_level_max)
	var is_elite = randf() < elite_chance

	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_pos

	# Configure enemy
	if enemy.has_method("set") or "enemy_level" in enemy:
		enemy.enemy_level = enemy_level
	if is_elite and enemy.has_method("set_meta"):
		enemy.set_meta("is_guardian", true)

	# Connect to death signal
	if enemy.has_signal("died"):
		enemy.died.connect(_on_enemy_died.bind(index, enemy))

	active_enemies[index] = enemy

	# Add to scene tree
	var world = get_tree().current_scene
	if world:
		world.add_child(enemy)
		enemy_spawned.emit(enemy, index)

	if is_elite:
		print("[CampSpawner] Spawned ELITE enemy L%d at %s point %d" % [enemy_level, camp_name, index])


func _on_enemy_died(index: int, enemy: Node) -> void:
	"""Called when a spawned enemy dies"""
	active_enemies.erase(index)
	enemy_died.emit(enemy, index)

	# Track kill timestamp for dynamic respawns
	kill_timestamps.append(Time.get_ticks_msec() / 1000.0)

	# Calculate respawn timer
	var base_timer = RESPAWN_TIMERS.get(camp_type, 90.0)
	var adjusted_timer = _calculate_adjusted_respawn(base_timer)
	respawn_timers[index] = adjusted_timer

	# Check if camp is cleared
	if active_enemies.is_empty():
		camp_cleared.emit()

	print("[CampSpawner] Enemy died at %s point %d, respawn in %.1fs" % [camp_name, index, adjusted_timer])


func _calculate_adjusted_respawn(base_timer: float) -> float:
	"""Adjust respawn timer based on kill rate.
	If players are killing faster than spawns, speed up respawns."""
	var kills_per_minute = kill_timestamps.size()
	var expected_kills = max_enemies * (60.0 / base_timer)

	# If killing more than 80% of expected rate, speed up respawns
	if kills_per_minute > expected_kills * 0.8:
		return base_timer * 0.8  # 20% faster respawns

	return base_timer


func _cleanup_old_timestamps() -> void:
	"""Remove kill timestamps older than 60 seconds"""
	var now = Time.get_ticks_msec() / 1000.0
	var new_timestamps: Array[float] = []
	for t in kill_timestamps:
		if now - t < 60.0:
			new_timestamps.append(t)
	kill_timestamps = new_timestamps


# ============================================
# PUBLIC API
# ============================================

func get_active_enemy_count() -> int:
	"""Get number of currently alive enemies"""
	return active_enemies.size()


func get_pending_respawn_count() -> int:
	"""Get number of enemies waiting to respawn"""
	return respawn_timers.size()


func get_camp_info() -> Dictionary:
	"""Get camp information for UI display"""
	return {
		"name": camp_name,
		"type": camp_type,
		"level_range": "%d-%d" % [enemy_level_min, enemy_level_max],
		"active_enemies": get_active_enemy_count(),
		"pending_respawns": get_pending_respawn_count(),
		"total_spawn_points": spawn_points.size()
	}


func force_respawn_all() -> void:
	"""Force immediate respawn of all dead enemies (debug/GM command)"""
	respawn_timers.clear()
	for i in spawn_points.size():
		if i not in active_enemies:
			_spawn_at_point(i)


func despawn_all() -> void:
	"""Despawn all active enemies"""
	for enemy in active_enemies.values():
		if is_instance_valid(enemy):
			enemy.queue_free()
	active_enemies.clear()
	respawn_timers.clear()
