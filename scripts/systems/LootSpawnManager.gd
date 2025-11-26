extends Node

## Loot Spawn Manager
## Handles random spawning of chests and pickable items across the map
## Maintains a pool of possible spawn locations and only spawns a fraction at a time
## When items are looted, they respawn at different random locations after a delay

# Spawn configuration
const MAX_ACTIVE_CHESTS: int = 5  # How many chests can exist at once (reduced from 10)
const MAX_ACTIVE_ITEMS: int = 15   # How many items can exist at once

# Respawn timers (in seconds)
const CHEST_RESPAWN_MIN: float = 60.0   # 1 minute
const CHEST_RESPAWN_MAX: float = 300.0  # 5 minutes
const ITEM_RESPAWN_MIN: float = 45.0    # 45 seconds
const ITEM_RESPAWN_MAX: float = 180.0   # 3 minutes

# Spawn point pools (populated by game_world.gd)
var chest_spawn_points: Array = []  # Array of Vector2 positions
var item_spawn_points: Array = []   # Array of Vector2 positions

# Active spawns tracking
var active_chests: Array = []  # Array of TreasureChest nodes
var active_items: Array = []   # Array of PickableItem nodes

# Pending respawns
var pending_chest_respawns: Array = []  # Array of {timer: float, max_time: float}
var pending_item_respawns: Array = []   # Array of {timer: float, max_time: float}

# Reference to game world
var game_world: Node2D = null

func _ready() -> void:
	print("📦 LootSpawnManager initialized")

func _process(delta: float) -> void:
	# Update pending chest respawns
	for i in range(pending_chest_respawns.size() - 1, -1, -1):
		var respawn = pending_chest_respawns[i]
		respawn.timer += delta
		if respawn.timer >= respawn.max_time:
			spawn_random_chest()
			pending_chest_respawns.remove_at(i)

	# Update pending item respawns
	for i in range(pending_item_respawns.size() - 1, -1, -1):
		var respawn = pending_item_respawns[i]
		respawn.timer += delta
		if respawn.timer >= respawn.max_time:
			spawn_random_item()
			pending_item_respawns.remove_at(i)

	# Clean up null references (items/chests that were destroyed)
	active_chests = active_chests.filter(func(chest): return is_instance_valid(chest))
	active_items = active_items.filter(func(item): return is_instance_valid(item))

func register_game_world(world: Node2D) -> void:
	"""Called by game_world.gd to register itself"""
	game_world = world
	print("📦 Game world registered with LootSpawnManager")

func add_chest_spawn_point(position: Vector2) -> void:
	"""Add a possible chest spawn location"""
	chest_spawn_points.append(position)

func add_item_spawn_point(position: Vector2) -> void:
	"""Add a possible item spawn location"""
	item_spawn_points.append(position)

func initial_spawn() -> void:
	"""Spawn initial batch of chests and items"""
	print("📦 Initial spawn: Creating %d chests and %d items" % [MAX_ACTIVE_CHESTS, MAX_ACTIVE_ITEMS])

	# Spawn initial chests
	for i in range(MAX_ACTIVE_CHESTS):
		spawn_random_chest()

	# Spawn initial items
	for i in range(MAX_ACTIVE_ITEMS):
		spawn_random_item()

func spawn_random_chest() -> void:
	"""Spawn a chest at a random available location"""
	if not game_world:
		push_error("Cannot spawn chest: game_world not registered!")
		return

	if chest_spawn_points.is_empty():
		push_warning("No chest spawn points available!")
		return

	if active_chests.size() >= MAX_ACTIVE_CHESTS:
		print("⚠️ Max chests reached, not spawning")
		return

	# Pick a random spawn point not currently occupied
	var available_points = get_available_chest_spawn_points()
	if available_points.is_empty():
		print("⚠️ All chest spawn points occupied!")
		return

	var spawn_pos = available_points[randi() % available_points.size()]

	# Create chest
	var TreasureChestScript = preload("res://scripts/items/TreasureChest.gd")
	var chest = TreasureChestScript.new()
	chest.name = "TreasureChest_at_%.0f_%.0f" % [spawn_pos.x, spawn_pos.y]
	chest.global_position = spawn_pos

	# Track it
	active_chests.append(chest)

	# Add to world
	game_world.add_child(chest)

	print("📦 Spawned chest at %s (active: %d/%d)" % [spawn_pos, active_chests.size(), MAX_ACTIVE_CHESTS])

func spawn_random_item() -> void:
	"""Spawn a pickable item at a random available location"""
	if not game_world:
		push_error("Cannot spawn item: game_world not registered!")
		return

	if item_spawn_points.is_empty():
		push_warning("No item spawn points available!")
		return

	if active_items.size() >= MAX_ACTIVE_ITEMS:
		print("⚠️ Max items reached, not spawning")
		return

	# Pick a random spawn point not currently occupied
	var available_points = get_available_item_spawn_points()
	if available_points.is_empty():
		print("⚠️ All item spawn points occupied!")
		return

	var spawn_pos = available_points[randi() % available_points.size()]

	# Create item (for now, just wood - can be randomized later)
	var PickableItemScript = preload("res://scripts/items/PickableItem.gd")
	var item = PickableItemScript.new()
	item.name = "PickableItem_at_%.0f_%.0f" % [spawn_pos.x, spawn_pos.y]
	item.global_position = spawn_pos

	# Set item properties
	item.item_name = "Dry Log"
	item.item_description = "Dry wood from a dead wasteland tree. Burns well."
	item.item_value = 12
	item.item_stackable = true
	item.item_max_stack = 1000
	item.item_quantity = 1

	# Track it
	active_items.append(item)

	# Add to world
	game_world.add_child(item)

	print("💎 Spawned item at %s (active: %d/%d)" % [spawn_pos, active_items.size(), MAX_ACTIVE_ITEMS])

func get_available_chest_spawn_points() -> Array:
	"""Get spawn points that don't have chests nearby"""
	var available = []
	for point in chest_spawn_points:
		var occupied = false
		for chest in active_chests:
			if is_instance_valid(chest) and chest.global_position.distance_to(point) < 50:
				occupied = true
				break
		if not occupied:
			available.append(point)
	return available

func get_available_item_spawn_points() -> Array:
	"""Get spawn points that don't have items nearby"""
	var available = []
	for point in item_spawn_points:
		var occupied = false
		for item in active_items:
			if is_instance_valid(item) and item.global_position.distance_to(point) < 50:
				occupied = true
				break
		if not occupied:
			available.append(point)
	return available

func on_chest_looted() -> void:
	"""Called when a chest is looted - schedule a respawn"""
	var respawn_time = randf_range(CHEST_RESPAWN_MIN, CHEST_RESPAWN_MAX)
	pending_chest_respawns.append({
		"timer": 0.0,
		"max_time": respawn_time
	})
	print("📦 Chest looted, will respawn in %.1fs at new location" % respawn_time)

func on_item_looted() -> void:
	"""Called when an item is picked up - schedule a respawn"""
	var respawn_time = randf_range(ITEM_RESPAWN_MIN, ITEM_RESPAWN_MAX)
	pending_item_respawns.append({
		"timer": 0.0,
		"max_time": respawn_time
	})
	print("💎 Item looted, will respawn in %.1fs at new location" % respawn_time)
