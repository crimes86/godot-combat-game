extends Node
## WorldTreeManager - Global manager for World Tree system
## Handles tree creation, tracking, persistence, and network sync
## Inspired by Shadowbane's Tree of Life

# ═══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════════

signal tree_planted(tree_data: WorldTreeData)
signal tree_rank_changed(tree_id: String, old_rank: int, new_rank: int)
signal tree_destroyed(tree_id: String, destroyer_guild_id: String)
signal tree_watered(tree_id: String, is_blessed: bool)
signal tree_upgrade_started(tree_id: String)
signal tree_upgrade_completed(tree_id: String, new_rank: int)

signal building_placed(tree_id: String, building_data)
signal building_destroyed(tree_id: String, building_id: String)
signal vendor_sale(tree_id: String, vendor_id: String, item_id: String, price: int, buyer_id: String)

signal bane_declared(tree_id: String, attacker_guild_id: String)
signal bane_window_started(tree_id: String)
signal bane_window_ended(tree_id: String, attacker_won: bool)

signal mine_claimed(tree_id: String, mine_id: String)
signal mine_lost(tree_id: String, mine_id: String)


# ═══════════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════════

# All world trees indexed by tree_id
var trees: Dictionary = {}

# Quick lookup tables
var _trees_by_guild: Dictionary = {}  # guild_id -> tree_id
var _trees_by_chunk: Dictionary = {}  # chunk_id -> tree_id
var _trees_by_owner: Dictionary = {}  # owner_player_id -> tree_id

# Active tree scenes in the world
var _tree_scenes: Dictionary = {}  # tree_id -> WorldTree node

# Tree scene to instantiate
var _tree_scene: PackedScene = null
var _seed_plot_scene: PackedScene = null

# Update timer for growth/upgrades
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 60.0  # Check every minute


# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Preload scenes
	if ResourceLoader.exists("res://scenes/world/WorldTree.tscn"):
		_tree_scene = load("res://scenes/world/WorldTree.tscn")
	if ResourceLoader.exists("res://scenes/world/SeedPlot.tscn"):
		_seed_plot_scene = load("res://scenes/world/SeedPlot.tscn")

	# Connect to auth for loading player's guild tree
	if MantleAuth:
		MantleAuth.auth_completed.connect(_on_auth_completed)
		MantleAuth.logout_completed.connect(_on_logout)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_check_upgrades()
		_check_bane_windows()


func _on_auth_completed(_data: Dictionary) -> void:
	# TODO: Fetch player's guild tree from backend
	pass


func _on_logout() -> void:
	# Clear local state on logout
	trees.clear()
	_trees_by_guild.clear()
	_trees_by_chunk.clear()
	_trees_by_owner.clear()


# ═══════════════════════════════════════════════════════════════════════════════
# TREE PLANTING
# ═══════════════════════════════════════════════════════════════════════════════

func can_plant_tree(player_id: String, guild_id: String) -> Dictionary:
	"""Check if player can plant a tree. Returns {can_plant: bool, reason: String}"""

	# Must have a guild
	if guild_id.is_empty():
		return {"can_plant": false, "reason": "You must be in a guild to plant a World Tree."}

	# Guild must not already have a tree
	if _trees_by_guild.has(guild_id):
		return {"can_plant": false, "reason": "Your guild already has a World Tree."}

	# Player must be guild leader or officer
	# TODO: Check with GroupManager or backend for guild rank
	# For now, allow any guild member

	# Check if player has seed in inventory
	if not _player_has_tree_seed(player_id):
		return {"can_plant": false, "reason": "You need a World Tree Seed to plant."}

	return {"can_plant": true, "reason": ""}


func plant_tree(player_id: String, guild_id: String, guild_name: String, chunk_id: int, position: Vector2) -> WorldTreeData:
	"""Plant a new World Tree. Returns tree data or null on failure."""

	var check = can_plant_tree(player_id, guild_id)
	if not check["can_plant"]:
		push_error("[WorldTreeManager] Cannot plant: %s" % check["reason"])
		return null

	# Create tree data
	var tree = WorldTreeData.new()
	tree.guild_id = guild_id
	tree.guild_name = guild_name
	tree.owner_player_id = player_id
	tree.chunk_id = chunk_id
	tree.position = position
	tree.rank = 1
	tree.health = WorldTreeData.RANK_DATA[1]["health"]
	tree.max_health = tree.health
	tree.planted_at = Time.get_unix_time_from_system()
	tree.last_maintenance = tree.planted_at
	tree.runekeeper_slots = WorldTreeData.RANK_DATA[1]["protection_slots"]

	# Register tree
	_register_tree(tree)

	# Consume seed from inventory
	_consume_tree_seed(player_id)

	# Spawn tree scene
	_spawn_tree_scene(tree)

	# Emit signal
	tree_planted.emit(tree)

	# Broadcast to server
	if NetworkManager and NetworkManager.is_server():
		_broadcast_tree_planted(tree)

	print("[WorldTreeManager] Tree planted: %s by guild %s at chunk %d" % [tree.tree_id, guild_name, chunk_id])

	return tree


func _register_tree(tree: WorldTreeData) -> void:
	trees[tree.tree_id] = tree
	_trees_by_guild[tree.guild_id] = tree.tree_id
	_trees_by_chunk[tree.chunk_id] = tree.tree_id
	_trees_by_owner[tree.owner_player_id] = tree.tree_id


func _unregister_tree(tree_id: String) -> void:
	var tree = trees.get(tree_id)
	if not tree:
		return

	trees.erase(tree_id)
	_trees_by_guild.erase(tree.guild_id)
	_trees_by_chunk.erase(tree.chunk_id)
	_trees_by_owner.erase(tree.owner_player_id)

	# Remove scene
	if _tree_scenes.has(tree_id):
		var scene = _tree_scenes[tree_id]
		if is_instance_valid(scene):
			scene.queue_free()
		_tree_scenes.erase(tree_id)


# ═══════════════════════════════════════════════════════════════════════════════
# TREE LOOKUP
# ═══════════════════════════════════════════════════════════════════════════════

func get_world_tree(tree_id: String) -> WorldTreeData:
	return trees.get(tree_id)


func get_tree_by_guild(guild_id: String) -> WorldTreeData:
	var tree_id = _trees_by_guild.get(guild_id)
	if tree_id:
		return trees.get(tree_id)
	return null


func get_tree_by_chunk(chunk_id: int) -> WorldTreeData:
	var tree_id = _trees_by_chunk.get(chunk_id)
	if tree_id:
		return trees.get(tree_id)
	return null


func get_tree_in_chunk(chunk_id: int) -> WorldTreeData:
	"""Alias for get_tree_by_chunk for clarity"""
	return get_tree_by_chunk(chunk_id)


func get_tree_by_owner(player_id: String) -> WorldTreeData:
	var tree_id = _trees_by_owner.get(player_id)
	if tree_id:
		return trees.get(tree_id)
	return null


func get_all_trees() -> Array:
	return trees.values()


func get_trees_for_map() -> Array:
	"""Get tree data formatted for world map display"""
	var map_data = []
	for tree in trees.values():
		map_data.append({
			"tree_id": tree.tree_id,
			"guild_name": tree.guild_name,
			"rank": tree.rank,
			"rank_name": tree.get_rank_name(),
			"position": tree.position,
			"chunk_id": tree.chunk_id,
			"is_under_siege": tree.bane_status != null,
		})
	return map_data


# ═══════════════════════════════════════════════════════════════════════════════
# TREE UPGRADES
# ═══════════════════════════════════════════════════════════════════════════════

func start_upgrade(tree_id: String) -> bool:
	"""Start upgrading a tree to the next rank. Returns true on success."""
	var tree = trees.get(tree_id)
	if not tree:
		return false

	if not tree.can_upgrade():
		return false

	var cost = tree.get_upgrade_cost()
	if tree.warehouse_gold < cost:
		push_error("[WorldTreeManager] Not enough gold for upgrade. Need %d, have %d" % [cost, tree.warehouse_gold])
		return false

	# Deduct gold
	tree.warehouse_gold -= cost

	# Start upgrade timer
	tree.upgrade_started_at = Time.get_unix_time_from_system()

	tree_upgrade_started.emit(tree_id)
	print("[WorldTreeManager] Upgrade started for tree %s (Rank %d -> %d)" % [tree_id, tree.rank, tree.rank + 1])

	return true


func _check_upgrades() -> void:
	"""Called periodically to check if any upgrades have completed"""
	for tree_id in trees:
		var tree = trees[tree_id]
		if tree.is_upgrading() and tree.check_upgrade_complete():
			_complete_upgrade(tree)


func _complete_upgrade(tree: WorldTreeData) -> void:
	var old_rank = tree.rank
	tree.rank += 1
	tree.upgrade_started_at = 0.0
	tree.max_health = tree.get_max_health_for_rank()
	tree.health = tree.max_health
	tree.runekeeper_slots = tree.get_protection_slots_for_rank()

	# Reset watering bonus after upgrade completes
	tree.growth_bonus_accumulated = 0.0

	tree_rank_changed.emit(tree.tree_id, old_rank, tree.rank)
	tree_upgrade_completed.emit(tree.tree_id, tree.rank)

	print("[WorldTreeManager] Tree %s upgraded to Rank %d (%s)" % [tree.tree_id, tree.rank, tree.get_rank_name()])

	# Update visual
	if _tree_scenes.has(tree.tree_id):
		var scene = _tree_scenes[tree.tree_id]
		if scene.has_method("update_rank_visual"):
			scene.update_rank_visual(tree.rank)


# ═══════════════════════════════════════════════════════════════════════════════
# WATERING
# ═══════════════════════════════════════════════════════════════════════════════

func water_tree(tree_id: String, player_id: String, is_blessed: bool = false) -> bool:
	"""Water a tree with purified or blessed water. Returns true on success."""
	var tree = trees.get(tree_id)
	if not tree:
		return false

	# Check player has water in inventory
	var water_item = "blessed_water" if is_blessed else "purified_water"
	if not _player_has_item(player_id, water_item):
		return false

	# Try to water
	if not tree.water_tree(is_blessed):
		return false

	# Consume water from inventory
	_consume_item(player_id, water_item)

	tree_watered.emit(tree_id, is_blessed)
	print("[WorldTreeManager] Tree %s watered%s" % [tree_id, " with blessed water" if is_blessed else ""])

	return true


# ═══════════════════════════════════════════════════════════════════════════════
# BANE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

func _check_bane_windows() -> void:
	"""Check if any bane windows should start or end"""
	var now = Time.get_unix_time_from_system()

	for tree_id in trees:
		var tree = trees[tree_id]
		if not tree.bane_status:
			continue

		var bane = tree.bane_status

		# Check if window should start
		if not bane.is_active and now >= bane.window_start and now < bane.window_end:
			bane.is_active = true
			bane_window_started.emit(tree_id)
			print("[WorldTreeManager] BANE WINDOW STARTED for tree %s!" % tree_id)

		# Check if window should end
		elif bane.is_active and now >= bane.window_end:
			_end_bane_window(tree, false)  # Defender wins by default (stalemate)


func _end_bane_window(tree: WorldTreeData, attacker_won: bool) -> void:
	var tree_id = tree.tree_id
	var bane = tree.bane_status

	if attacker_won:
		# Tree destroyed
		tree_destroyed.emit(tree_id, bane.attacker_guild_id)
		_unregister_tree(tree_id)
		print("[WorldTreeManager] Tree %s DESTROYED by %s!" % [tree_id, bane.attacker_guild_name])
	else:
		# Defenders win - clear bane status
		tree.bane_status = null
		print("[WorldTreeManager] Tree %s defended successfully!" % tree_id)

	bane_window_ended.emit(tree_id, attacker_won)


# ═══════════════════════════════════════════════════════════════════════════════
# SCENE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

func _spawn_tree_scene(tree: WorldTreeData) -> void:
	if not _tree_scene:
		push_warning("[WorldTreeManager] Tree scene not loaded")
		return

	var scene = _tree_scene.instantiate()
	scene.global_position = tree.position
	scene.name = "WorldTree_%s" % tree.tree_id

	if scene.has_method("initialize"):
		scene.initialize(tree)

	# Add to world
	var world = get_tree().current_scene
	if world:
		world.add_child(scene)
		_tree_scenes[tree.tree_id] = scene


func spawn_seed_plot(chunk_id: int, position: Vector2) -> Node:
	"""Spawn a seed plot at the given position. Called by POI system."""
	if not _seed_plot_scene:
		push_warning("[WorldTreeManager] Seed plot scene not loaded")
		return null

	# Check if chunk already has a tree
	if _trees_by_chunk.has(chunk_id):
		push_warning("[WorldTreeManager] Chunk %d already has a tree" % chunk_id)
		return null

	var plot = _seed_plot_scene.instantiate()
	plot.global_position = position
	plot.name = "SeedPlot_Chunk%d" % chunk_id

	if plot.has_method("set_chunk_id"):
		plot.set_chunk_id(chunk_id)

	return plot


# ═══════════════════════════════════════════════════════════════════════════════
# INVENTORY HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _player_has_tree_seed(_player_id: String) -> bool:
	# Check InventorySystem for World Tree Seed
	if not InventorySystem:
		return false

	for item in InventorySystem.inventory_items:
		if item and _is_tree_seed(item):
			return true

	return false


func _consume_tree_seed(_player_id: String) -> bool:
	if not InventorySystem:
		return false

	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item and _is_tree_seed(item):
			InventorySystem.inventory_items[i] = null
			InventorySystem.inventory_changed.emit()
			return true

	return false


func _is_tree_seed(item: Dictionary) -> bool:
	"""Check if an item is a World Tree Seed"""
	# Check consumable_type first (shop format)
	if item.get("consumable_type") == "world_tree_seed":
		return true
	# Fallback to name check
	if item.get("name") == "World Tree Seed":
		return true
	# Legacy check for id field
	if item.get("id") == "world_tree_seed":
		return true
	return false


func _player_has_item(_player_id: String, item_id: String) -> bool:
	if not InventorySystem:
		return false

	for item in InventorySystem.inventory_items:
		if item and _is_item_type(item, item_id):
			return true

	return false


func _consume_item(_player_id: String, item_id: String) -> bool:
	if not InventorySystem:
		return false

	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item and _is_item_type(item, item_id):
			# Handle stacks
			var quantity = item.get("quantity", 1)
			if quantity > 1:
				item["quantity"] = quantity - 1
			else:
				InventorySystem.inventory_items[i] = null
			InventorySystem.inventory_changed.emit()
			return true

	return false


func _is_item_type(item: Dictionary, item_type: String) -> bool:
	"""Check if an item matches the given type identifier"""
	# Check consumable_type (shop format)
	if item.get("consumable_type") == item_type:
		return true
	# Check by item name (fallback)
	var name_map = {
		"purified_water": "Purified Water",
		"blessed_water": "Blessed Water",
		"world_tree_seed": "World Tree Seed",
		"empty_vial": "Empty Vial"
	}
	if name_map.has(item_type) and item.get("name") == name_map[item_type]:
		return true
	# Legacy check for id field
	if item.get("id") == item_type:
		return true
	return false


# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK SYNC
# ═══════════════════════════════════════════════════════════════════════════════

func _broadcast_tree_planted(tree: WorldTreeData) -> void:
	# TODO: Implement RPC to broadcast to all clients
	pass


# ═══════════════════════════════════════════════════════════════════════════════
# PERSISTENCE
# ═══════════════════════════════════════════════════════════════════════════════

func save_trees_to_dict() -> Dictionary:
	"""Serialize all trees for saving"""
	var data = {}
	for tree_id in trees:
		data[tree_id] = trees[tree_id].to_dict()
	return data


func load_trees_from_dict(data: Dictionary) -> void:
	"""Load trees from saved data"""
	trees.clear()
	_trees_by_guild.clear()
	_trees_by_chunk.clear()
	_trees_by_owner.clear()

	for tree_id in data:
		var tree = WorldTreeData.from_dict(data[tree_id])
		_register_tree(tree)
		_spawn_tree_scene(tree)

	print("[WorldTreeManager] Loaded %d trees" % trees.size())
