extends Node2D

## Wave Spawner System
## Periodically spawns waves of skeletons that path toward the campfire.
## Uses existing EnemyAI CAMPFIRE_ATTRACTED state for pathfinding.
## Server-authoritative: only the host spawns enemies.

# ═══════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════

signal wave_starting(wave_number: int)
signal wave_spawned(wave_number: int, enemy_count: int)
signal wave_cleared(wave_number: int)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Wave timing (randomized between min and max)
const WAVE_INTERVAL_MIN: float = 180.0  # 3 minutes
const WAVE_INTERVAL_MAX: float = 300.0  # 5 minutes
const WARNING_TIME: float = 10.0        # Seconds before wave spawns

## Wave composition
const BASE_WAVE_SIZE: int = 4           # Base skeleton count per wave
const PLAYER_SCALING: float = 1.5       # Extra skeletons per additional player
const MAX_WAVE_ENEMIES: int = 20        # Hard cap regardless of player count
const MAX_WAVE_ENEMY_LEVEL: int = 8     # Starter zone cap

## Spatial
const CAMPFIRE_POS: Vector2 = Vector2(-6000, 0)
const SPAWN_RADIUS: float = 1200.0      # Distance from campfire to spawn enemies
const PLAYER_DETECT_RADIUS: float = 2000.0  # Players within this radius count for scaling
const STRAGGLER_DESPAWN_TIME: float = 300.0  # 5 minutes max lifetime for wave enemies
const STRAGGLER_MAX_DISTANCE: float = 3000.0  # Force-despawn if too far from campfire

## Wave boss
const WAVE_BOSS_FREQUENCY: int = 5      # Boss every Nth wave

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

var wave_number: int = 0
var wave_timer: float = 0.0
var next_wave_interval: float = 0.0
var warning_sent: bool = false
var is_active: bool = false

var active_wave_enemies: Array = []
var campfire_node: Node2D = null
var game_world: Node = null

# Scenes
var enemy_scene: PackedScene = null
var guardian_scene: PackedScene = null

# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	enemy_scene = load("res://scenes/enemies/enemy.tscn")
	guardian_scene = load("res://scenes/enemies/guardian_skeleton.tscn")

	# Find campfire node (sibling or nearby)
	campfire_node = _find_campfire()

	# Find game_world (parent chain)
	game_world = _find_game_world()

	# Randomize first wave interval
	_reset_wave_timer()
	is_active = true
	print("[WaveSpawner] Initialized. First wave in %.0fs" % next_wave_interval)

func _process(delta: float) -> void:
	if not is_active:
		return

	# Only server spawns waves
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Tick straggler cleanup
	_cleanup_stragglers()

	# Tick wave timer
	wave_timer += delta

	# Send warning before wave
	if not warning_sent and wave_timer >= next_wave_interval - WARNING_TIME:
		var nearby_players = _count_nearby_players()
		if nearby_players > 0:
			_send_wave_warning()
			warning_sent = true

	# Spawn wave
	if wave_timer >= next_wave_interval:
		var nearby_players = _count_nearby_players()
		if nearby_players > 0:
			_spawn_wave(nearby_players)
		else:
			# No players near campfire, skip and reset timer
			print("[WaveSpawner] No players near campfire, skipping wave")
		_reset_wave_timer()

# ═══════════════════════════════════════════════════════════════════════════
# WAVE SPAWNING
# ═══════════════════════════════════════════════════════════════════════════

func _spawn_wave(player_count: int) -> void:
	wave_number += 1

	# Get difficulty from corruption (inverted - low corruption = harder)
	var difficulty = _get_wave_difficulty()

	# Calculate wave size
	var wave_size = int(BASE_WAVE_SIZE + (player_count - 1) * PLAYER_SCALING)
	wave_size = int(wave_size * difficulty.size_multiplier)
	wave_size = mini(wave_size, MAX_WAVE_ENEMIES)
	wave_size = maxi(wave_size, 2)  # Minimum 2 enemies per wave

	print("[WaveSpawner] === WAVE %d ===" % wave_number)
	print("  Players: %d, Size: %d, Levels: %d-%d, Elite chance: %.0f%%" % [
		player_count, wave_size, difficulty.min_level, difficulty.max_level, difficulty.elite_chance * 100
	])

	wave_starting.emit(wave_number)

	# Spawn enemies at distributed angles around the campfire
	var spawned_count = 0
	for i in range(wave_size):
		var angle = (float(i) / wave_size) * TAU + randf_range(-0.2, 0.2)
		var spawn_pos = CAMPFIRE_POS + Vector2(cos(angle), sin(angle)) * SPAWN_RADIUS

		# Determine if this is an elite
		var is_elite = randf() < difficulty.elite_chance
		var level = randi_range(difficulty.min_level, difficulty.max_level)

		var enemy = _spawn_wave_enemy(spawn_pos, level, is_elite)
		if enemy:
			spawned_count += 1

	# Spawn wave boss on milestone waves
	var is_boss_wave = wave_number % WAVE_BOSS_FREQUENCY == 0
	if is_boss_wave:
		var boss_angle = randf() * TAU
		var boss_pos = CAMPFIRE_POS + Vector2(cos(boss_angle), sin(boss_angle)) * SPAWN_RADIUS
		var boss_level = mini(difficulty.max_level + 1, MAX_WAVE_ENEMY_LEVEL)
		var boss = _spawn_wave_enemy(boss_pos, boss_level, true, true)
		if boss:
			spawned_count += 1
			_announce_wave_boss()

	wave_spawned.emit(wave_number, spawned_count)
	_announce_wave_spawned(spawned_count)
	print("  Spawned: %d enemies (boss wave: %s)" % [spawned_count, is_boss_wave])

func _spawn_wave_enemy(pos: Vector2, level: int, is_elite: bool = false, is_boss: bool = false) -> Node:
	var scene = guardian_scene if (is_elite or is_boss) else enemy_scene
	if not scene:
		return null

	var enemy = scene.instantiate()
	enemy.global_position = pos
	enemy.enemy_level = level
	enemy.name = "WaveEnemy_%d_%d" % [wave_number, Time.get_ticks_msec()]

	# Set campfire attraction metadata (EnemyAI reads these in _ready)
	enemy.set_meta("is_campfire_skeleton", true)
	enemy.set_meta("campfire_target", campfire_node)
	enemy.set_meta("is_wave_enemy", true)
	if is_boss:
		enemy.set_meta("is_wave_boss", true)

	# Add to world
	if game_world:
		game_world.add_child(enemy)
	else:
		get_tree().current_scene.add_child(enemy)

	# Connect death signal
	if enemy.has_signal("died"):
		enemy.died.connect(_on_wave_enemy_died.bind(enemy))

	# Connect corpse click
	if enemy.has_signal("corpse_clicked"):
		var gw = game_world if game_world else get_tree().current_scene
		if gw and gw.has_method("_on_corpse_clicked"):
			enemy.corpse_clicked.connect(gw._on_corpse_clicked)

	# Register with NetworkEnemyManager for multiplayer sync
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	if network_enemy_mgr:
		var network_id = network_enemy_mgr.register_enemy(enemy)
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			network_enemy_mgr.spawn_enemy_for_nearby_clients(network_id, enemy)

	# Track for wave management
	active_wave_enemies.append({
		"enemy": enemy,
		"spawn_time": Time.get_ticks_msec() / 1000.0,
	})

	return enemy

# ═══════════════════════════════════════════════════════════════════════════
# WAVE TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func _on_wave_enemy_died(enemy: Node) -> void:
	# Remove from active tracking
	for i in range(active_wave_enemies.size() - 1, -1, -1):
		if active_wave_enemies[i].enemy == enemy:
			active_wave_enemies.remove_at(i)
			break

	# Check if wave is cleared (no living wave enemies)
	if active_wave_enemies.is_empty():
		_on_wave_cleared()

func _on_wave_cleared() -> void:
	print("[WaveSpawner] Wave %d cleared!" % wave_number)
	wave_cleared.emit(wave_number)
	_announce_wave_cleared()

	# Notify quest system
	var quest_mgr = get_node_or_null("/root/QuestManager")
	if quest_mgr and quest_mgr.has_method("on_wave_survived"):
		var corruption_tier = 0
		if OssuaryManager:
			corruption_tier = OssuaryManager.get_corruption_tier()
		quest_mgr.on_wave_survived(wave_number, corruption_tier)

func _cleanup_stragglers() -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	for i in range(active_wave_enemies.size() - 1, -1, -1):
		var data = active_wave_enemies[i]
		var enemy = data.enemy

		if not is_instance_valid(enemy):
			active_wave_enemies.remove_at(i)
			continue

		# Force-despawn if too old or too far
		var age = current_time - data.spawn_time
		var distance = enemy.global_position.distance_to(CAMPFIRE_POS)

		if age > STRAGGLER_DESPAWN_TIME or distance > STRAGGLER_MAX_DISTANCE:
			active_wave_enemies.remove_at(i)
			enemy.queue_free()

	# If all enemies removed by cleanup, trigger wave cleared
	if active_wave_enemies.is_empty() and wave_number > 0:
		# Only trigger if we haven't already (check via a simple flag)
		pass  # wave_cleared already handled by _on_wave_enemy_died

# ═══════════════════════════════════════════════════════════════════════════
# DIFFICULTY
# ═══════════════════════════════════════════════════════════════════════════

func _get_wave_difficulty() -> Dictionary:
	"""Get wave difficulty based on corruption (INVERTED - low corruption = harder).
	The force pushes back when players are winning."""
	var tier = 0
	if OssuaryManager:
		tier = OssuaryManager.get_corruption_tier()

	# INVERTED: low corruption (players winning) = hardest waves
	var inverted = 3 - tier

	# Wave number adds gradual escalation (every 5 waves = +1 level, capped)
	var wave_bonus = mini(wave_number / WAVE_BOSS_FREQUENCY, 2)

	return {
		"min_level": mini([1, 2, 4, 6][inverted] + wave_bonus, MAX_WAVE_ENEMY_LEVEL),
		"max_level": mini([2, 4, 6, 8][inverted] + wave_bonus, MAX_WAVE_ENEMY_LEVEL),
		"size_multiplier": [1.0, 1.25, 1.5, 2.0][inverted],
		"elite_chance": [0.0, 0.05, 0.1, 0.2][inverted],
	}

# ═══════════════════════════════════════════════════════════════════════════
# ANNOUNCEMENTS
# ═══════════════════════════════════════════════════════════════════════════

func _send_wave_warning() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_show_wave_warning.rpc()
	else:
		_show_wave_warning()

@rpc("authority", "call_local", "reliable")
func _show_wave_warning() -> void:
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("The ground trembles... a horde approaches!")

func _announce_wave_spawned(count: int) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_show_wave_spawned.rpc(wave_number, count)
	else:
		_show_wave_spawned(wave_number, count)

@rpc("authority", "call_local", "reliable")
func _show_wave_spawned(wn: int, count: int) -> void:
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("Wave %d - %d skeletons assault the campfire!" % [wn, count])

func _announce_wave_cleared() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_show_wave_cleared.rpc(wave_number)
	else:
		_show_wave_cleared(wave_number)

@rpc("authority", "call_local", "reliable")
func _show_wave_cleared(wn: int) -> void:
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("Wave %d cleared! The campfire holds." % wn)

func _announce_wave_boss() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_show_wave_boss.rpc()
	else:
		_show_wave_boss()

@rpc("authority", "call_local", "reliable")
func _show_wave_boss() -> void:
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("A champion of the cursed emerges!")

# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _reset_wave_timer() -> void:
	wave_timer = 0.0
	next_wave_interval = randf_range(WAVE_INTERVAL_MIN, WAVE_INTERVAL_MAX)
	warning_sent = false

func _count_nearby_players() -> int:
	var count = 0
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.global_position.distance_to(CAMPFIRE_POS) < PLAYER_DETECT_RADIUS:
			# Skip dead players
			if "is_dead" in player and player.is_dead:
				continue
			count += 1
	return count

func _find_campfire() -> Node2D:
	# WaveSpawner is a sibling of the Campfire instance inside the Campfire container
	var parent = get_parent()
	if parent:
		for child in parent.get_children():
			if child != self and child.is_in_group("campfire"):
				return child
	# Fallback: search all campfires in scene
	var campfires = get_tree().get_nodes_in_group("campfire")
	for cf in campfires:
		if "is_community_campfire" in cf and cf.is_community_campfire:
			return cf
	if campfires.size() > 0:
		return campfires[0]
	return null

func _find_game_world() -> Node:
	var node = get_parent()
	while node:
		if node.is_in_group("game_world"):
			return node
		node = node.get_parent()
	return get_tree().current_scene
