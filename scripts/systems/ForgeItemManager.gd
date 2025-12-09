extends Node
## ForgeItemManager - Fetches and caches forged items from backend
## Items come pre-computed with stats, effects, and visual data
## Syncs forged items to InventorySystem for in-game use

signal forged_items_loaded(items: Array)
signal forge_claimed(item: Dictionary)
signal forge_error(error: String)
signal item_synced_to_inventory(item: Dictionary)

# Cached forged items from API
var _forged_items: Array = []
var _forged_items_by_id: Dictionary = {}  # item_id -> forged item
var _is_fetching: bool = false
var _is_loaded: bool = false
var _synced_to_inventory: bool = false

# Rarity multipliers for forged item stats
const RARITY_DAMAGE_BONUS = {
	"common": 1,
	"uncommon": 2,
	"rare": 3,
	"epic": 4,
	"legendary": 5
}

func _ready() -> void:
	if MantleAuth:
		MantleAuth.auth_completed.connect(_on_auth_completed)
		MantleAuth.logout_completed.connect(_on_logout)

func _on_auth_completed(_data: Dictionary) -> void:
	fetch_forged_items()

func _on_logout() -> void:
	_forged_items.clear()
	_forged_items_by_id.clear()
	_is_loaded = false
	_synced_to_inventory = false

# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func fetch_forged_items() -> void:
	"""Fetch all forged items for the current user"""
	if _is_fetching:
		return

	if not MantleAuth or not MantleAuth.is_logged_in():
		LogManager.warning("Cannot fetch forged items - not authenticated", "forge")
		return

	_is_fetching = true
	var url = MantleAuth.get_api_base() + "/api/me/forged-items"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_forged_items_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch forged items: %s" % error, "forge")
		_is_fetching = false
		request.queue_free()

func _on_forged_items_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_is_fetching = false

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Forged items fetch failed: %d" % result, "forge")
		forge_error.emit("Failed to load forged items")
		return

	if response_code == 404:
		# Endpoint doesn't exist yet - use empty list
		LogManager.info("Forged items endpoint not implemented yet", "forge")
		_forged_items = []
		_is_loaded = true
		forged_items_loaded.emit(_forged_items)
		return

	if response_code != 200:
		LogManager.error("Forged items fetch returned %d" % response_code, "forge")
		forge_error.emit("Server error loading forged items")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse forged items response", "forge")
		forge_error.emit("Invalid server response")
		return

	var data = json.data
	_forged_items = data.get("forged_items", [])

	# Build lookup dictionary
	_forged_items_by_id.clear()
	for item in _forged_items:
		var item_id = item.get("item_id", "")
		if item_id != "":
			_forged_items_by_id[item_id] = item

	_is_loaded = true
	LogManager.info("Loaded %d forged items" % _forged_items.size(), "forge")
	forged_items_loaded.emit(_forged_items)

func claim_forge(achievement_id: int, callback: Callable = Callable()) -> void:
	"""Claim/forge an achievement into an item"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = MantleAuth.get_api_base() + "/api/forge/claim"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"achievement_id": achievement_id})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_claim_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to claim forge: %s" % error, "forge")
		forge_error.emit("Failed to connect to server")
		request.queue_free()

func _on_claim_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Forge claim failed: %d / %d" % [result, response_code], "forge")
		forge_error.emit("Failed to forge item")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		forge_error.emit("Invalid server response")
		return

	var data = json.data
	var forged_item = data.get("forged_item", {})

	if not forged_item.is_empty():
		# Add to cache
		_forged_items.append(forged_item)
		var item_id = forged_item.get("item_id", "")
		if item_id != "":
			_forged_items_by_id[item_id] = forged_item

		LogManager.info("Forged new item: %s" % forged_item.get("item_name", "Unknown"), "forge")
		forge_claimed.emit(forged_item)

	if callback.is_valid():
		callback.call(forged_item)

# ═══════════════════════════════════════════════════════════════════════════════
# GETTERS
# ═══════════════════════════════════════════════════════════════════════════════

func is_loaded() -> bool:
	return _is_loaded

func get_all_forged_items() -> Array:
	return _forged_items.duplicate()

func get_forged_item(item_id: String) -> Dictionary:
	"""Get a specific forged item by item_id"""
	return _forged_items_by_id.get(item_id, {})

func has_forged_item(item_id: String) -> bool:
	"""Check if user has forged a specific item"""
	return item_id in _forged_items_by_id

func get_forged_items_by_type(item_type: String) -> Array:
	"""Get all forged items of a specific type"""
	var results = []
	for item in _forged_items:
		if item.get("item_type", "") == item_type:
			results.append(item)
	return results

func get_forged_count() -> int:
	return _forged_items.size()

# ═══════════════════════════════════════════════════════════════════════════════
# INVENTORY SYNC
# ═══════════════════════════════════════════════════════════════════════════════

func sync_to_inventory() -> int:
	"""Sync all forged items to player's inventory. Returns count of items added."""
	if not _is_loaded:
		LogManager.warning("Cannot sync - forged items not loaded yet", "forge")
		return 0

	if _synced_to_inventory:
		LogManager.info("Forged items already synced to inventory", "forge")
		return 0

	var added_count = 0
	for forged in _forged_items:
		var inventory_item = _convert_to_inventory_format(forged)
		if inventory_item.is_empty():
			continue

		# Check if already in inventory (by forged_id)
		var forged_id = forged.get("token_id", forged.get("item_id", ""))
		if _is_item_in_inventory(forged_id):
			continue

		if InventorySystem.add_item(inventory_item):
			added_count += 1
			item_synced_to_inventory.emit(inventory_item)

	_synced_to_inventory = true
	LogManager.info("Synced %d forged items to inventory" % added_count, "forge")
	return added_count

func claim_single_item(item_id: String) -> Dictionary:
	"""Claim a single forged item and add it to inventory. Returns the inventory item or empty dict on failure."""
	if not _is_loaded:
		LogManager.warning("Cannot claim - forged items not loaded yet", "forge")
		return {}

	# Find the forged item by item_id
	var forged = _forged_items_by_id.get(item_id, {})
	if forged.is_empty():
		LogManager.warning("Item not found in forged items: %s" % item_id, "forge")
		return {}

	# Check if already claimed (in inventory)
	var forged_id = str(forged.get("token_id", forged.get("item_id", "")))
	if _is_item_in_inventory(forged_id):
		LogManager.info("Item already claimed: %s" % item_id, "forge")
		return {}  # Already claimed

	# Convert to inventory format and add
	var inventory_item = _convert_to_inventory_format(forged)
	if inventory_item.is_empty():
		LogManager.error("Failed to convert forged item: %s" % item_id, "forge")
		return {}

	if InventorySystem.add_item(inventory_item):
		LogManager.info("Claimed forged item: %s" % inventory_item.get("name", item_id), "forge")
		item_synced_to_inventory.emit(inventory_item)
		return inventory_item
	else:
		LogManager.error("Failed to add item to inventory (full?): %s" % item_id, "forge")
		return {}

func is_item_claimed(item_id: String) -> bool:
	"""Check if a forged item has already been claimed (is in inventory)"""
	var forged = _forged_items_by_id.get(item_id, {})
	if forged.is_empty():
		return false
	var forged_id = str(forged.get("token_id", forged.get("item_id", "")))
	return _is_item_in_inventory(forged_id)

func _is_item_in_inventory(forged_id: String) -> bool:
	"""Check if a forged item is already in inventory"""
	for slot in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[slot]
		if item and item.get("forged_id", "") == str(forged_id):
			return true
	return false

func _convert_to_inventory_format(forged: Dictionary) -> Dictionary:
	"""Convert forged item from API format to inventory format"""
	var item_type = forged.get("item_type", "weapon")
	var rarity = forged.get("item_rarity", "common").to_lower()
	var damage_bonus = RARITY_DAMAGE_BONUS.get(rarity, 1)

	var base_item = {
		"name": forged.get("item_name", "Forged Item"),
		"description": forged.get("description", "A forged item from an achievement."),
		"stackable": false,
		"quantity": 1,
		"is_forged": true,
		"forged_id": str(forged.get("token_id", forged.get("item_id", ""))),
		"item_id": forged.get("item_id", ""),
		"rarity": rarity.capitalize(),
		"effect_name": forged.get("effect_name", ""),
		"effect_intensity": forged.get("effect_intensity", 0.5),
		"glow_color": forged.get("glow_color", "#ffffff"),
		"effort_tier": forged.get("effort_tier", ""),
		"vintage_years": forged.get("vintage_years", 0),
		"is_secret": forged.get("is_secret", false),
		"can_trade": true,
		"value": damage_bonus * 100,  # Base sell value
	}

	match item_type:
		"weapon":
			base_item["type"] = "weapon"
			base_item["slot"] = "mainhand"
			base_item["weapon_type"] = forged.get("weapon_type", "sword")
			base_item["base_damage"] = 5 + (damage_bonus * 3)  # 8-20 damage based on rarity
			base_item["attack_speed"] = "Normal"
			base_item["crit_chance"] = 0.05 + (damage_bonus * 0.02)  # 7-15% crit
			base_item["required_level"] = 1  # Forged items have no level req (twinking!)

		"armor_head", "armor_chest", "armor_legs", "armor_hands", "armor_feet":
			base_item["type"] = "armor"
			base_item["slot"] = item_type.replace("armor_", "")
			base_item["defense"] = 2 + damage_bonus  # 3-7 defense

		"shield":
			base_item["type"] = "shield"
			base_item["slot"] = "offhand"
			base_item["block_chance"] = 0.1 + (damage_bonus * 0.03)  # 13-25% block

		"cape":
			base_item["type"] = "cape"
			base_item["slot"] = "back"

		"accessory":
			base_item["type"] = "accessory"
			base_item["slot"] = "accessory"

		_:
			# Unknown type - still add as generic item
			base_item["type"] = "misc"

	return base_item

func get_forged_weapons_for_inventory() -> Array:
	"""Get all forged weapons formatted for inventory use"""
	var weapons = []
	for item in get_forged_items_by_type("weapon"):
		var inv_item = _convert_to_inventory_format(item)
		if not inv_item.is_empty():
			weapons.append(inv_item)
	return weapons
