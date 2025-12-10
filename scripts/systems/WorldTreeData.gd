extends RefCounted
class_name WorldTreeData
## Data structures for World Tree system
## Inspired by Shadowbane's Tree of Life mechanics

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

const RANK_DATA = {
	1: {"name": "Sapling", "gold_cost": 0, "health": 10000, "upgrade_hours": 0, "protection_slots": 2, "mine_limit": 1},
	2: {"name": "Young Tree", "gold_cost": 10000, "health": 20000, "upgrade_hours": 1, "protection_slots": 4, "mine_limit": 1},
	3: {"name": "Growing Tree", "gold_cost": 25000, "health": 35000, "upgrade_hours": 4, "protection_slots": 6, "mine_limit": 2},
	4: {"name": "Mature Tree", "gold_cost": 50000, "health": 55000, "upgrade_hours": 12, "protection_slots": 8, "mine_limit": 2},
	5: {"name": "Ancient Tree", "gold_cost": 100000, "health": 80000, "upgrade_hours": 24, "protection_slots": 10, "mine_limit": 3},
	6: {"name": "Elder Tree", "gold_cost": 200000, "health": 110000, "upgrade_hours": 48, "protection_slots": 12, "mine_limit": 4},
	7: {"name": "World Tree", "gold_cost": 500000, "health": 150000, "upgrade_hours": 72, "protection_slots": 15, "mine_limit": 5},
}

const MAX_RANK = 7

# Watering bonuses
const DAILY_WATER_GROWTH_BONUS = 0.10  # +10% growth speed
const BLESSED_WATER_BONUS = 0.25  # +25% one-time boost
const WATER_NEGLECT_DAYS = 7  # Days without watering before growth pauses

# Maintenance costs (weekly)
const MAINTENANCE_COSTS = {
	"tree": 1000,
	"warehouse": 500,
	"vendor": 200,
	"shrine": 500,
	"storage": 100,
	"crafting": 300,
}

# Building placement slots around tree
const BUILDING_SLOTS = ["A", "B", "C", "D", "E", "F"]


# ═══════════════════════════════════════════════════════════════════════════════
# WORLD TREE DATA CLASS
# ═══════════════════════════════════════════════════════════════════════════════

var tree_id: String = ""
var guild_id: String = ""
var guild_name: String = ""
var owner_player_id: String = ""  # Guild leader who planted
var chunk_id: int = 0
var position: Vector2 = Vector2.ZERO

# Rank and health
var rank: int = 1
var health: int = 10000
var max_health: int = 10000

# Timestamps
var planted_at: float = 0.0  # Unix timestamp
var last_maintenance: float = 0.0
var last_watered: float = 0.0
var upgrade_started_at: float = 0.0  # 0 if not upgrading

# Protection
var runekeeper_slots: int = 2
var protected_building_ids: Array = []  # Building IDs in protection slots

# Buildings and economy
var buildings: Array = []  # Array of BuildingData
var claimed_mine_ids: Array = []
var warehouse_gold: int = 0
var warehouse_resources: Dictionary = {"stone": 0, "lumber": 0, "iron": 0}

# Bane status (null if not under siege)
var bane_status: BaneStatusData = null

# Watering
var times_watered: int = 0
var growth_bonus_accumulated: float = 0.0  # From watering


func _init(id: String = "") -> void:
	if id.is_empty():
		tree_id = _generate_tree_id()
	else:
		tree_id = id


func _generate_tree_id() -> String:
	return "tree_%d_%s" % [Time.get_unix_time_from_system(), str(randi() % 10000).pad_zeros(4)]


# ═══════════════════════════════════════════════════════════════════════════════
# RANK METHODS
# ═══════════════════════════════════════════════════════════════════════════════

func get_rank_name() -> String:
	return RANK_DATA[rank]["name"]


func get_max_health_for_rank() -> int:
	return RANK_DATA[rank]["health"]


func get_protection_slots_for_rank() -> int:
	return RANK_DATA[rank]["protection_slots"]


func get_mine_limit_for_rank() -> int:
	return RANK_DATA[rank]["mine_limit"]


func can_upgrade() -> bool:
	if rank >= MAX_RANK:
		return false
	if is_upgrading():
		return false
	return true


func is_upgrading() -> bool:
	return upgrade_started_at > 0


func get_upgrade_cost() -> int:
	if rank >= MAX_RANK:
		return 0
	return RANK_DATA[rank + 1]["gold_cost"]


func get_upgrade_time_hours() -> float:
	if rank >= MAX_RANK:
		return 0
	var base_hours = RANK_DATA[rank + 1]["upgrade_hours"]
	# Apply watering bonus (reduces time)
	var bonus = min(growth_bonus_accumulated, 0.5)  # Cap at 50% reduction
	return base_hours * (1.0 - bonus)


func get_upgrade_progress() -> float:
	if not is_upgrading():
		return 0.0
	var elapsed = Time.get_unix_time_from_system() - upgrade_started_at
	var total_seconds = get_upgrade_time_hours() * 3600
	if total_seconds <= 0:
		return 1.0
	return clamp(elapsed / total_seconds, 0.0, 1.0)


func check_upgrade_complete() -> bool:
	if not is_upgrading():
		return false
	return get_upgrade_progress() >= 1.0


# ═══════════════════════════════════════════════════════════════════════════════
# WATERING METHODS
# ═══════════════════════════════════════════════════════════════════════════════

func can_water() -> bool:
	# Can water once per day
	var now = Time.get_unix_time_from_system()
	var seconds_since_watered = now - last_watered
	return seconds_since_watered >= 86400  # 24 hours


func water_tree(is_blessed: bool = false) -> bool:
	if not can_water() and not is_blessed:
		return false

	last_watered = Time.get_unix_time_from_system()
	times_watered += 1

	if is_blessed:
		growth_bonus_accumulated += BLESSED_WATER_BONUS
	else:
		growth_bonus_accumulated += DAILY_WATER_GROWTH_BONUS

	return true


func is_growth_paused() -> bool:
	# Growth pauses if not watered for WATER_NEGLECT_DAYS
	var now = Time.get_unix_time_from_system()
	var days_since_watered = (now - last_watered) / 86400.0
	return days_since_watered >= WATER_NEGLECT_DAYS


# ═══════════════════════════════════════════════════════════════════════════════
# SERIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var data = {
		"tree_id": tree_id,
		"guild_id": guild_id,
		"guild_name": guild_name,
		"owner_player_id": owner_player_id,
		"chunk_id": chunk_id,
		"position": {"x": position.x, "y": position.y},
		"rank": rank,
		"health": health,
		"max_health": max_health,
		"planted_at": planted_at,
		"last_maintenance": last_maintenance,
		"last_watered": last_watered,
		"upgrade_started_at": upgrade_started_at,
		"runekeeper_slots": runekeeper_slots,
		"protected_building_ids": protected_building_ids,
		"claimed_mine_ids": claimed_mine_ids,
		"warehouse_gold": warehouse_gold,
		"warehouse_resources": warehouse_resources,
		"times_watered": times_watered,
		"growth_bonus_accumulated": growth_bonus_accumulated,
	}

	# Serialize buildings
	var buildings_data = []
	for building in buildings:
		if building is TreeBuildingData:
			buildings_data.append(building.to_dict())
	data["buildings"] = buildings_data

	# Serialize bane status
	if bane_status:
		data["bane_status"] = bane_status.to_dict()
	else:
		data["bane_status"] = null

	return data


static func from_dict(data: Dictionary) -> WorldTreeData:
	var tree = WorldTreeData.new(data.get("tree_id", ""))
	tree.guild_id = data.get("guild_id", "")
	tree.guild_name = data.get("guild_name", "")
	tree.owner_player_id = data.get("owner_player_id", "")
	tree.chunk_id = data.get("chunk_id", 0)

	var pos = data.get("position", {})
	tree.position = Vector2(pos.get("x", 0), pos.get("y", 0))

	tree.rank = data.get("rank", 1)
	tree.health = data.get("health", 10000)
	tree.max_health = data.get("max_health", 10000)
	tree.planted_at = data.get("planted_at", 0.0)
	tree.last_maintenance = data.get("last_maintenance", 0.0)
	tree.last_watered = data.get("last_watered", 0.0)
	tree.upgrade_started_at = data.get("upgrade_started_at", 0.0)
	tree.runekeeper_slots = data.get("runekeeper_slots", 2)
	tree.protected_building_ids = data.get("protected_building_ids", [])
	tree.claimed_mine_ids = data.get("claimed_mine_ids", [])
	tree.warehouse_gold = data.get("warehouse_gold", 0)
	tree.warehouse_resources = data.get("warehouse_resources", {"stone": 0, "lumber": 0, "iron": 0})
	tree.times_watered = data.get("times_watered", 0)
	tree.growth_bonus_accumulated = data.get("growth_bonus_accumulated", 0.0)

	# Deserialize buildings
	for building_data in data.get("buildings", []):
		tree.buildings.append(TreeBuildingData.from_dict(building_data))

	# Deserialize bane status
	var bane_data = data.get("bane_status")
	if bane_data:
		tree.bane_status = BaneStatusData.from_dict(bane_data)

	return tree


# ═══════════════════════════════════════════════════════════════════════════════
# BUILDING DATA CLASS
# ═══════════════════════════════════════════════════════════════════════════════

class TreeBuildingData extends RefCounted:
	var building_id: String = ""
	var building_type: String = ""  # "warehouse", "vendor_weapons", "shrine_warfare", etc.
	var position_slot: String = ""  # "A" through "F"
	var health: int = 1000
	var max_health: int = 1000
	var is_protected: bool = false
	var created_at: float = 0.0

	# Vendor-specific
	var vendor_inventory: Array = []  # Items for sale
	var vendor_prices: Dictionary = {}  # item_id -> price
	var pending_gold: int = 0
	var total_sales: int = 0

	# Shrine-specific
	var shrine_buff_type: String = ""  # "warfare", "vitality", etc.


	func _init(id: String = "") -> void:
		if id.is_empty():
			building_id = "bld_%d_%s" % [Time.get_unix_time_from_system(), str(randi() % 10000).pad_zeros(4)]
		else:
			building_id = id
		created_at = Time.get_unix_time_from_system()


	func is_vendor() -> bool:
		return building_type.begins_with("vendor_")


	func is_shrine() -> bool:
		return building_type.begins_with("shrine_")


	func to_dict() -> Dictionary:
		return {
			"building_id": building_id,
			"building_type": building_type,
			"position_slot": position_slot,
			"health": health,
			"max_health": max_health,
			"is_protected": is_protected,
			"created_at": created_at,
			"vendor_inventory": vendor_inventory,
			"vendor_prices": vendor_prices,
			"pending_gold": pending_gold,
			"total_sales": total_sales,
			"shrine_buff_type": shrine_buff_type,
		}


	static func from_dict(data: Dictionary) -> TreeBuildingData:
		var building = TreeBuildingData.new(data.get("building_id", ""))
		building.building_type = data.get("building_type", "")
		building.position_slot = data.get("position_slot", "")
		building.health = data.get("health", 1000)
		building.max_health = data.get("max_health", 1000)
		building.is_protected = data.get("is_protected", false)
		building.created_at = data.get("created_at", 0.0)
		building.vendor_inventory = data.get("vendor_inventory", [])
		building.vendor_prices = data.get("vendor_prices", {})
		building.pending_gold = data.get("pending_gold", 0)
		building.total_sales = data.get("total_sales", 0)
		building.shrine_buff_type = data.get("shrine_buff_type", "")
		return building


# ═══════════════════════════════════════════════════════════════════════════════
# BANE STATUS DATA CLASS
# ═══════════════════════════════════════════════════════════════════════════════

class BaneStatusData extends RefCounted:
	var bane_id: String = ""
	var attacker_guild_id: String = ""
	var attacker_guild_name: String = ""
	var stone_planted_at: float = 0.0
	var window_start: float = 0.0  # Unix timestamp when bane window opens
	var window_end: float = 0.0  # Unix timestamp when bane window closes
	var stone_health: int = 50000
	var stone_max_health: int = 50000
	var is_active: bool = false  # True during the 2-hour window


	func _init(id: String = "") -> void:
		if id.is_empty():
			bane_id = "bane_%d_%s" % [Time.get_unix_time_from_system(), str(randi() % 10000).pad_zeros(4)]
		else:
			bane_id = id


	func get_days_until_bane() -> float:
		var now = Time.get_unix_time_from_system()
		if now >= window_start:
			return 0.0
		return (window_start - now) / 86400.0


	func get_hours_remaining() -> float:
		if not is_active:
			return 0.0
		var now = Time.get_unix_time_from_system()
		if now >= window_end:
			return 0.0
		return (window_end - now) / 3600.0


	func to_dict() -> Dictionary:
		return {
			"bane_id": bane_id,
			"attacker_guild_id": attacker_guild_id,
			"attacker_guild_name": attacker_guild_name,
			"stone_planted_at": stone_planted_at,
			"window_start": window_start,
			"window_end": window_end,
			"stone_health": stone_health,
			"stone_max_health": stone_max_health,
			"is_active": is_active,
		}


	static func from_dict(data: Dictionary) -> BaneStatusData:
		var bane = BaneStatusData.new(data.get("bane_id", ""))
		bane.attacker_guild_id = data.get("attacker_guild_id", "")
		bane.attacker_guild_name = data.get("attacker_guild_name", "")
		bane.stone_planted_at = data.get("stone_planted_at", 0.0)
		bane.window_start = data.get("window_start", 0.0)
		bane.window_end = data.get("window_end", 0.0)
		bane.stone_health = data.get("stone_health", 50000)
		bane.stone_max_health = data.get("stone_max_health", 50000)
		bane.is_active = data.get("is_active", false)
		return bane
