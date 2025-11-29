extends Node

## Loot Spawn Manager
## Handles random spawning of chests and pickable items across the map
## Maintains a pool of possible spawn locations and only spawns a fraction at a time
## When items are looted, they respawn at different random locations after a delay
##
## MULTIPLAYER: Server-authoritative spawning and state sync
## - Server spawns all chests/items and assigns unique IDs
## - Clients receive spawn commands via RPC
## - When client interacts, server validates and broadcasts state change

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

# Network ID tracking for multiplayer sync
var chest_id_counter: int = 0
var item_id_counter: int = 0
var chests_by_id: Dictionary = {}  # network_id -> TreasureChest
var items_by_id: Dictionary = {}   # network_id -> PickableItem

# Pending respawns
var pending_chest_respawns: Array = []  # Array of {timer: float, max_time: float}
var pending_item_respawns: Array = []   # Array of {timer: float, max_time: float}

# Reference to game world
var game_world: Node2D = null

func _ready() -> void:
	print("📦 LootSpawnManager initialized")
	# Listen for new peer connections to sync world state
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(peer_id: int) -> void:
	"""When a new peer connects, send them all existing chests and items."""
	if not multiplayer.is_server():
		return

	# Wait longer to let the client fully initialize game_world
	# (needs to load terrain, generate elements, etc.)
	# Increased from 2.0s to 3.0s for slower clients
	await get_tree().create_timer(3.0).timeout
	sync_world_state_to_peer(peer_id)

func _process(delta: float) -> void:
	# Only server handles respawn timers
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

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
	"""Spawn initial batch of chests and items (server only in multiplayer)"""
	# In multiplayer, only server spawns initially
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		print("📦 Client waiting for server to sync world state...")
		return

	print("📦 Initial spawn: Creating %d chests and %d items" % [MAX_ACTIVE_CHESTS, MAX_ACTIVE_ITEMS])

	# Spawn initial chests
	for i in range(MAX_ACTIVE_CHESTS):
		spawn_random_chest()

	# Spawn initial items
	for i in range(MAX_ACTIVE_ITEMS):
		spawn_random_item()

func spawn_random_chest() -> void:
	"""Spawn a chest at a random available location (server-authoritative)"""
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

	# Assign network ID
	chest_id_counter += 1
	var network_id = chest_id_counter

	# Create chest locally
	_create_chest_at(network_id, spawn_pos)

	# In multiplayer, broadcast to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_spawn_chest_on_clients.rpc(network_id, spawn_pos)

	print("📦 Spawned chest #%d at %s (active: %d/%d)" % [network_id, spawn_pos, active_chests.size(), MAX_ACTIVE_CHESTS])

func _create_chest_at(network_id: int, spawn_pos: Vector2) -> void:
	"""Create a chest locally (called own server and clients)"""
	# Ensure we have a reference to game_world
	if not game_world:
		game_world = get_tree().get_first_node_in_group("game_world")
	if not game_world:
		push_error("LootSpawnManager: Cannot spawn chest #%d - game_world not found!" % network_id)
		return

	# Check if we already have this chest (avoid duplicates)
	if chests_by_id.has(network_id):
		print("📦 Chest #%d already exists, skipping" % network_id)
		return

	var TreasureChestScript = preload("res://scripts/items/TreasureChest.gd")
	var chest = TreasureChestScript.new()
	chest.name = "TreasureChest_%d" % network_id
	chest.global_position = spawn_pos
	chest.set_meta("network_id", network_id)

	# Track it
	active_chests.append(chest)
	chests_by_id[network_id] = chest

	# Add to world
	game_world.add_child(chest)

@rpc("authority", "call_remote", "reliable")
func _spawn_chest_on_clients(network_id: int, spawn_pos: Vector2) -> void:
	"""Client receives chest spawn from server"""
	print("📦 [Client] Spawning chest #%d at %s" % [network_id, spawn_pos])

	# Ensure game_world is available
	if not game_world:
		game_world = get_tree().get_first_node_in_group("game_world")
	if not game_world:
		# Try waiting a bit for game_world to be ready
		print("📦 [Client] game_world not found, waiting...")
		await get_tree().create_timer(0.5).timeout
		game_world = get_tree().get_first_node_in_group("game_world")
		if not game_world:
			push_error("📦 [Client] game_world still not found after wait!")
			return

	_create_chest_at(network_id, spawn_pos)

func spawn_random_item() -> void:
	"""Spawn a pickable item at a random available location (server-authoritative)"""
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

	# Assign network ID
	item_id_counter += 1
	var network_id = item_id_counter

	# Item data (for now, just wood - can be randomized later)
	var item_data = {
		"name": "Dry Log",
		"description": "Dry wood from a dead wasteland tree. Burns well.",
		"value": 12,
		"stackable": true,
		"max_stack": 1000,
		"quantity": 1
	}

	# Create item locally
	_create_item_at(network_id, spawn_pos, item_data)

	# In multiplayer, broadcast to clients
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_spawn_item_on_clients.rpc(network_id, spawn_pos, item_data)

	print("💎 Spawned item #%d at %s (active: %d/%d)" % [network_id, spawn_pos, active_items.size(), MAX_ACTIVE_ITEMS])

func _create_item_at(network_id: int, spawn_pos: Vector2, item_data: Dictionary) -> void:
	"""Create a pickable item locally (called on server and clients)"""
	# Ensure we have a reference to game_world
	if not game_world:
		game_world = get_tree().get_first_node_in_group("game_world")
	if not game_world:
		push_error("LootSpawnManager: Cannot spawn item #%d - game_world not found!" % network_id)
		return

	# Check if we already have this item (avoid duplicates)
	if items_by_id.has(network_id):
		print("💎 Item #%d already exists, skipping" % network_id)
		return

	var PickableItemScript = preload("res://scripts/items/PickableItem.gd")
	var item = PickableItemScript.new()
	item.name = "PickableItem_%d" % network_id
	item.global_position = spawn_pos
	item.set_meta("network_id", network_id)

	# Set item properties
	item.item_name = item_data.get("name", "Unknown")
	item.item_description = item_data.get("description", "")
	item.item_value = item_data.get("value", 0)
	item.item_stackable = item_data.get("stackable", false)
	item.item_max_stack = item_data.get("max_stack", 1)
	item.item_quantity = item_data.get("quantity", 1)

	# Track it
	active_items.append(item)
	items_by_id[network_id] = item

	# Add to world
	game_world.add_child(item)

@rpc("authority", "call_remote", "reliable")
func _spawn_item_on_clients(network_id: int, spawn_pos: Vector2, item_data: Dictionary) -> void:
	"""Client receives item spawn from server"""
	print("💎 [Client] Spawning item #%d at %s" % [network_id, spawn_pos])
	_create_item_at(network_id, spawn_pos, item_data)

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
	"""Called when a chest is looted - schedule a respawn (server only)"""
	# Only server handles respawn scheduling
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var respawn_time = randf_range(CHEST_RESPAWN_MIN, CHEST_RESPAWN_MAX)
	pending_chest_respawns.append({
		"timer": 0.0,
		"max_time": respawn_time
	})
	print("📦 Chest looted, will respawn in %.1fs at new location" % respawn_time)

func on_item_looted() -> void:
	"""Called when an item is picked up - schedule a respawn (server only)"""
	# Only server handles respawn scheduling
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var respawn_time = randf_range(ITEM_RESPAWN_MIN, ITEM_RESPAWN_MAX)
	pending_item_respawns.append({
		"timer": 0.0,
		"max_time": respawn_time
	})
	print("💎 Item looted, will respawn in %.1fs at new location" % respawn_time)

# ═══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER: Chest/Item interaction sync
# ═══════════════════════════════════════════════════════════════════════════════

func request_open_chest(chest: Node) -> void:
	"""Client requests to open a chest - server validates and broadcasts"""
	var network_id = chest.get_meta("network_id", -1)
	if network_id == -1:
		# Single player or no network ID - just open locally
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client sends request to server
		_request_open_chest_rpc.rpc_id(1, network_id)
	else:
		# Server opens directly and broadcasts
		_broadcast_chest_opened(network_id)

@rpc("any_peer", "reliable")
func _request_open_chest_rpc(network_id: int) -> void:
	"""Server receives chest open request from client"""
	if not multiplayer.is_server():
		return

	var chest = chests_by_id.get(network_id)
	if not chest or not is_instance_valid(chest):
		print("⚠️ Server: Chest #%d not found" % network_id)
		return

	if chest.is_opened:
		print("⚠️ Server: Chest #%d already opened" % network_id)
		return

	print("📦 Server: Opening chest #%d (requested by peer %d)" % [network_id, multiplayer.get_remote_sender_id()])
	_broadcast_chest_opened(network_id)

func _broadcast_chest_opened(network_id: int) -> void:
	"""Server broadcasts chest opened to all clients"""
	var chest = chests_by_id.get(network_id)
	if not chest or not is_instance_valid(chest):
		return

	# Generate loot on server
	chest.generate_loot()
	var loot_data = []
	for item in chest.generated_loot:
		loot_data.append(item.duplicate())

	# Mark as opened on server
	chest.is_opened = true

	# Broadcast to all clients
	if multiplayer.has_multiplayer_peer():
		_sync_chest_opened.rpc(network_id, loot_data)

@rpc("authority", "call_local", "reliable")
func _sync_chest_opened(network_id: int, loot_data: Array) -> void:
	"""All clients receive chest opened notification"""
	var chest = chests_by_id.get(network_id)
	if not chest or not is_instance_valid(chest):
		print("⚠️ [Client] Chest #%d not found for sync" % network_id)
		return

	print("📦 [Sync] Chest #%d opened with %d items" % [network_id, loot_data.size()])

	# Set loot data and mark as opened
	chest.generated_loot = loot_data
	chest.is_opened = true

	# Play open animation and effects (but don't regenerate loot)
	chest._on_chest_opened_synced()

func request_pickup_item(item: Node) -> void:
	"""Client requests to pick up an item - server validates and broadcasts"""
	var network_id = item.get_meta("network_id", -1)
	if network_id == -1:
		# Single player or no network ID - just pick up locally
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Client sends request to server
		_request_pickup_item_rpc.rpc_id(1, network_id)
	else:
		# Server picks up directly and broadcasts
		_broadcast_item_picked_up(network_id)

@rpc("any_peer", "reliable")
func _request_pickup_item_rpc(network_id: int) -> void:
	"""Server receives item pickup request from client"""
	if not multiplayer.is_server():
		return

	var item = items_by_id.get(network_id)
	if not item or not is_instance_valid(item):
		print("⚠️ Server: Item #%d not found" % network_id)
		return

	print("💎 Server: Item #%d picked up (requested by peer %d)" % [network_id, multiplayer.get_remote_sender_id()])
	_broadcast_item_picked_up(network_id)

func _broadcast_item_picked_up(network_id: int) -> void:
	"""Server broadcasts item picked up to all clients"""
	# Broadcast to all clients to remove the item
	if multiplayer.has_multiplayer_peer():
		_sync_item_picked_up.rpc(network_id)

	# Schedule respawn on server
	on_item_looted()

@rpc("authority", "call_local", "reliable")
func _sync_item_picked_up(network_id: int) -> void:
	"""All clients receive item picked up notification"""
	var item = items_by_id.get(network_id)
	if not item or not is_instance_valid(item):
		print("⚠️ [Client] Item #%d not found for sync" % network_id)
		return

	print("💎 [Sync] Item #%d picked up, removing" % network_id)

	# Remove from tracking
	items_by_id.erase(network_id)
	var idx = active_items.find(item)
	if idx >= 0:
		active_items.remove_at(idx)

	# Remove from world
	item.queue_free()

# ═══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER: Sync world state to new clients
# ═══════════════════════════════════════════════════════════════════════════════

func sync_world_state_to_peer(peer_id: int) -> void:
	"""Send all current chests and items to a newly connected client"""
	if not multiplayer.is_server():
		return

	print("📦 Syncing world state to peer %d (%d chests, %d items)" % [peer_id, active_chests.size(), active_items.size()])

	# Sync all active chests
	for chest in active_chests:
		if not is_instance_valid(chest):
			continue
		var network_id = chest.get_meta("network_id", -1)
		if network_id == -1:
			continue
		_spawn_chest_on_clients.rpc_id(peer_id, network_id, chest.global_position)

		# If chest is already opened, sync that state too
		if chest.is_opened:
			var loot_data = []
			for item in chest.generated_loot:
				loot_data.append(item.duplicate())
			_sync_chest_opened.rpc_id(peer_id, network_id, loot_data)

	# Sync all active items
	for item in active_items:
		if not is_instance_valid(item):
			continue
		var network_id = item.get_meta("network_id", -1)
		if network_id == -1:
			continue
		var item_data = {
			"name": item.item_name,
			"description": item.item_description,
			"value": item.item_value,
			"stackable": item.item_stackable,
			"max_stack": item.item_max_stack,
			"quantity": item.item_quantity
		}
		_spawn_item_on_clients.rpc_id(peer_id, network_id, item.global_position, item_data)
