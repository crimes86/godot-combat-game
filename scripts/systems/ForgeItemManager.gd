extends Node
## ForgeItemManager - Fetches and caches forged items from backend
## Items come pre-computed with stats, effects, and visual data
## Syncs forged items to InventorySystem for in-game use

signal forged_items_loaded(items: Array)
signal forge_status_loaded(status: Dictionary)
signal forge_claimed(item: Dictionary)
signal forge_error(error: String)
signal item_synced_to_inventory(item: Dictionary)
signal bridge_status_updated(item_id: String, status: String)
signal bridge_out_requested(item: Dictionary)
signal bridge_out_cancelled(item_id: String)
signal wallet_status_updated(connected: bool, wallet_address: String)
signal bridge_in_available_updated(items: Array)
signal bridge_in_completed(items: Array)

# Cached forged items from API
var _forged_items: Array = []
var _forged_items_by_id: Dictionary = {}  # item_id -> forged item
var _is_fetching: bool = false
var _is_loaded: bool = false
var _synced_to_inventory: bool = false

# Forge status - achievements that CAN be forged but haven't been yet
var _forgeable_achievements: Array = []  # Achievements user can forge (Rare+, original claim)
var _forge_status_loaded: bool = false

# Wallet and bridge status
var _wallet_connected: bool = false
var _wallet_address: String = ""
var _bridge_in_available: Array = []  # Items in external wallet that can be bridged in

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
	fetch_forge_status()

func _on_logout() -> void:
	_forged_items.clear()
	_forged_items_by_id.clear()
	_forgeable_achievements.clear()
	_is_loaded = false
	_forge_status_loaded = false
	_synced_to_inventory = false

# ═══════════════════════════════════════════════════════════════════════════════
# DEBUG - Remove after testing
# ═══════════════════════════════════════════════════════════════════════════════

func debug_clear_claimed_items() -> void:
	"""DEBUG: Clear all forged items from inventory so they can be reclaimed"""
	var cleared = 0
	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item and item.get("is_forged", false):
			InventorySystem.inventory_items[i] = null
			cleared += 1
	print("[ForgeItemManager] DEBUG: Cleared %d forged items from inventory" % cleared)
	InventorySystem.inventory_changed.emit()

func debug_inject_test_achievement(achievement_key: String = "steam_1145360_SLAYER") -> void:
	"""DEBUG: Inject a test achievement as forgeable (simulates backend sync)
	Use ForgeItemDB keys like 'steam_1145360_SLAYER' for Adamant Rail"""
	var forge_db = ForgeItemDB.FORGE_ITEMS.get(achievement_key)
	if not forge_db:
		print("[ForgeItemManager] DEBUG: Unknown achievement key: %s" % achievement_key)
		print("[ForgeItemManager] DEBUG: Available keys: %s" % ForgeItemDB.FORGE_ITEMS.keys())
		return

	# Create mock forgeable achievement matching backend format
	var mock_achievement = {
		"id": 99999,  # Fake ID for testing
		"achievement_key": achievement_key,
		"display_name": forge_db.get("achievement_name", "Test Achievement"),
		"item_name": forge_db.get("item_name", "Test Item"),
		"item_id": forge_db.get("item_id", "test_item"),
		"rarity": _rarity_enum_to_string(forge_db.get("rarity", 0)),
		"provider": "steam",
		"app_id": "1145360",  # Hades
		"api_name": "SLAYER",
		"unlock_percent": forge_db.get("unlock_percent", 28.5),
		"description": forge_db.get("description", "Test description"),
		"is_original_claim": true
	}

	_forgeable_achievements.append(mock_achievement)
	_forge_status_loaded = true

	print("[ForgeItemManager] DEBUG: Injected test achievement '%s' as forgeable" % forge_db.get("item_name"))
	print("[ForgeItemManager] DEBUG: Now have %d forgeable achievements" % _forgeable_achievements.size())
	forge_status_loaded.emit({"forgeable": _forgeable_achievements, "forged": [], "unforgeable": []})

func debug_forge_test_item(achievement_key: String = "steam_1145360_SLAYER") -> void:
	"""DEBUG: Directly forge a test item into inventory (skip backend)"""
	var forge_db = ForgeItemDB.FORGE_ITEMS.get(achievement_key)
	if not forge_db:
		print("[ForgeItemManager] DEBUG: Unknown achievement key: %s" % achievement_key)
		return

	# Create forged item matching what backend would return
	var forged_item = {
		"id": 99999,
		"item_id": forge_db.get("item_id", "test_item"),
		"item_name": forge_db.get("item_name", "Test Item"),
		"item_type": "weapon",
		"weapon_type": _weapon_class_to_string(forge_db.get("weapon_class", 0)),
		"rarity": _rarity_enum_to_string(forge_db.get("rarity", 0)),
		"is_forged": true,
		"description": forge_db.get("description", ""),
		"lore": forge_db.get("lore", ""),
		"achievement_name": forge_db.get("achievement_name", ""),
		"glow_color": _get_effect_color(forge_db.get("effects", [])),
		"effect_name": forge_db.get("effects", ["standard_particles"])[0] if forge_db.get("effects", []).size() > 0 else "standard_particles",
		"stats": forge_db.get("stats", {}),
		"sprites": forge_db.get("sprites", {}),
		"gun_config": forge_db.get("gun_config", {})  # Burst fire config for battle rifles
	}

	_forged_items.append(forged_item)
	_forged_items_by_id[forged_item.item_id] = forged_item
	_is_loaded = true

	# Convert to inventory format and add to inventory
	var inventory_item = _convert_to_inventory_format(forged_item)
	if not inventory_item.is_empty():
		InventorySystem.add_item(inventory_item)
		item_synced_to_inventory.emit(inventory_item)

	print("[ForgeItemManager] DEBUG: Forged test item '%s' directly to inventory" % forged_item.item_name)
	forge_claimed.emit(forged_item)

func _rarity_enum_to_string(rarity_enum: int) -> String:
	match rarity_enum:
		0: return "common"
		1: return "uncommon"
		2: return "rare"
		3: return "epic"
		4: return "legendary"
		_: return "common"

func _weapon_class_to_string(weapon_class_enum: int) -> String:
	# Match ForgeItemDB.WeaponClass enum order
	var classes = ["sword", "dagger", "mace", "spear", "staff", "axe", "rapier",
				   "greatsword", "katana", "saber", "scimitar", "halberd", "pike",
				   "trident", "flail", "scythe", "bow", "crossbow", "gun", "battle_rifle"]
	if weapon_class_enum >= 0 and weapon_class_enum < classes.size():
		return classes[weapon_class_enum]
	return "sword"

func _get_effect_color(effects: Array) -> String:
	# Map effect names to glow colors
	var effect_colors = {
		"infernal_glow": "#FF6347",
		"blood_red_glow": "#8B0000",
		"ember_trail": "#FF4500",
		"erdtree_blessing": "#DAA520",
		"moonlight_glow": "#4169E1",
		"void_particles": "#1A0033",
		"halo_green_glow": "#00CED1",
		"standard_particles": "#FFFFFF"
	}
	if effects.size() > 0:
		return effect_colors.get(effects[0], "#FFFFFF")
	return "#FFFFFF"

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

	# Debug: Log bridge status of each item
	for item in _forged_items:
		var bridge_status = item.get("bridge_status", "unknown")
		var item_name = item.get("item_name", "?")
		if bridge_status != "in_game":
			LogManager.info("  Item '%s' bridge_status: %s" % [item_name, bridge_status], "forge")

	forged_items_loaded.emit(_forged_items)

	# Sync claimed items to inventory (for items claimed on other devices or via scripts)
	var synced = sync_to_inventory()
	if synced > 0:
		LogManager.info("Synced %d claimed forged items to inventory" % synced, "forge")

	# Also fetch forge status to know which achievements can be forged
	fetch_forge_status()

	# Fetch bridge status to get cooldown times for items being bridged out
	fetch_bridge_status()

# ═══════════════════════════════════════════════════════════════════════════════
# FORGE STATUS - Forgeable achievements (not yet forged)
# ═══════════════════════════════════════════════════════════════════════════════

func fetch_forge_status() -> void:
	"""Fetch forge status - shows which achievements can be forged but haven't been yet"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		return

	var url = MantleAuth.get_api_base() + "/api/me/forge-status"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_forge_status_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch forge status: %s" % error, "forge")
		request.queue_free()

func _on_forge_status_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Forge status fetch failed: %d" % result, "forge")
		return

	if response_code == 404:
		# Endpoint doesn't exist yet - use empty list
		LogManager.info("Forge status endpoint not implemented yet", "forge")
		_forgeable_achievements = []
		_forge_status_loaded = true
		forge_status_loaded.emit({"forgeable": [], "forged": [], "unforgeable": []})
		return

	if response_code != 200:
		LogManager.error("Forge status fetch returned %d" % response_code, "forge")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		LogManager.error("Failed to parse forge status response", "forge")
		return

	var data = json.data
	_forgeable_achievements = data.get("forgeable", [])
	_forge_status_loaded = true

	LogManager.info("Forge status loaded: %d forgeable achievements" % _forgeable_achievements.size(), "forge")
	forge_status_loaded.emit(data)

func get_forgeable_achievements() -> Array:
	"""Get achievements that can be forged but haven't been yet"""
	return _forgeable_achievements.duplicate()

func is_achievement_forgeable(achievement_name: String) -> bool:
	"""Check if an achievement is forgeable (unlocked but not forged)"""
	for ach in _forgeable_achievements:
		if ach.get("display_name", "") == achievement_name:
			return true
	return false

func is_forge_status_loaded() -> bool:
	return _forge_status_loaded

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
	"""Sync CLAIMED forged items to player's inventory. Returns count of items added.
	NOTE: This is now a fallback - items are normally added immediately when claimed."""
	if not _is_loaded:
		LogManager.warning("Cannot sync - forged items not loaded yet", "forge")
		return 0

	var added_count = 0
	for forged in _forged_items:
		# Only sync items that have been claimed on server
		if not forged.get("claimed_in_game", false):
			continue

		var inventory_item = _convert_to_inventory_format(forged)
		if inventory_item.is_empty():
			continue

		# Check if already in inventory (by forged_id)
		var token_id = forged.get("token_id", 0)
		var forged_id = str(token_id) if token_id else forged.get("item_id", "")
		if _is_item_in_inventory(forged_id):
			continue

		if InventorySystem.add_item(inventory_item):
			added_count += 1
			item_synced_to_inventory.emit(inventory_item)

	if added_count > 0:
		LogManager.info("Synced %d forged items to inventory (fallback)" % added_count, "forge")
	return added_count

func claim_single_item(item_id: String) -> Dictionary:
	"""Claim a forged item: marks on server AND adds to inventory. Returns inventory item or empty dict."""
	if not _is_loaded:
		LogManager.warning("Cannot claim - forged items not loaded yet", "forge")
		return {}

	# Find the forged item by item_id
	var forged = _forged_items_by_id.get(item_id, {})
	if forged.is_empty():
		LogManager.warning("Item not found in forged items: %s" % item_id, "forge")
		return {}

	# Check server-side claim status (authoritative - prevents duping)
	if forged.get("claimed_in_game", false):
		LogManager.info("Item already claimed (server): %s" % item_id, "forge")
		return {}

	# Claim on server (authoritative)
	var token_id = forged.get("token_id", 0)
	if token_id:
		var claim_result = await _claim_on_server(token_id)
		if not claim_result:
			LogManager.error("Server rejected claim for item: %s" % item_id, "forge")
			return {}

	# Mark as claimed in local cache
	forged["claimed_in_game"] = true

	# Convert to inventory format and add to inventory
	var inventory_item = _convert_to_inventory_format(forged)
	if inventory_item.is_empty():
		LogManager.error("Failed to convert forged item to inventory format: %s" % item_id, "forge")
		return {}

	if not InventorySystem.add_item(inventory_item):
		LogManager.error("Failed to add forged item to inventory (full?): %s" % item_id, "forge")
		return {}

	LogManager.info("Claimed and added to inventory: %s" % forged.get("item_name", item_id), "forge")
	forge_claimed.emit(forged)
	item_synced_to_inventory.emit(inventory_item)
	return inventory_item

func _claim_on_server(token_id: int) -> bool:
	"""Mark item as claimed on server. Returns true on success."""
	if not MantleAuth or not MantleAuth.is_logged_in():
		LogManager.warning("Cannot claim on server - not authenticated", "forge")
		return true  # Allow claim anyway if not authenticated (offline mode)

	var url = MantleAuth.get_api_base() + "/api/forge/claim-to-game"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"token_id": token_id})

	var http = HTTPRequest.new()
	add_child(http)

	var error = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		LogManager.error("Failed to send claim request: %s" % error, "forge")
		return false

	# Wait for response (blocking for simplicity)
	var result = await http.request_completed
	http.queue_free()

	var response_code = result[1]
	if response_code == 200:
		LogManager.info("Server confirmed claim for token_id: %d" % token_id, "forge")
		return true
	elif response_code == 409:
		LogManager.warning("Item already claimed on server (token_id: %d)" % token_id, "forge")
		return false
	else:
		LogManager.error("Server claim failed with code %d" % response_code, "forge")
		return false

func is_item_claimed(item_id: String) -> bool:
	"""Check if a forged item has already been claimed (server-authoritative)"""
	var forged = _forged_items_by_id.get(item_id, {})
	if forged.is_empty():
		return false
	# Check server-side status first (authoritative)
	if forged.get("claimed_in_game", false):
		return true
	# Fallback: check local inventory
	var token_id = forged.get("token_id", 0)
	var forged_id = str(token_id) if token_id else forged.get("item_id", "")
	return _is_item_in_inventory(forged_id)

func _is_item_in_inventory(forged_id: String) -> bool:
	"""Check if a forged item is already in inventory (local check)"""
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
			# Gun weapons need ranged_damage attack mode for cursor-based targeting
			if base_item["weapon_type"] in ["gun", "battle_rifle"]:
				base_item["attack_mode"] = "ranged_damage"
				base_item["gun_radius"] = 28.0  # Precision targeting radius
				base_item["gun_range"] = 350.0  # Max shooting distance
				# Apply gun_config for burst weapons (battle rifle, etc.)
				var gun_config = forged.get("gun_config", {})
				if not gun_config.is_empty():
					base_item["gun_subtype"] = gun_config.get("gun_subtype", "railgun")
					base_item["burst_count"] = gun_config.get("burst_count", 1)
					base_item["burst_delay"] = gun_config.get("burst_delay", 0.10)

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

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE SYSTEM - Move items between in-game and external wallets
# ═══════════════════════════════════════════════════════════════════════════════

func get_bridge_status(item_id: String) -> String:
	"""Get bridge status for a forged item: in_game, bridging_out, bridged, bridging_in"""
	var forged = _forged_items_by_id.get(item_id, {})
	return forged.get("bridge_status", "in_game")

func is_item_bridgeable(item_id: String) -> bool:
	"""Check if item can be bridged out (must be claimed and in_game)"""
	var forged = _forged_items_by_id.get(item_id, {})
	if forged.is_empty():
		return false
	var bridge_status = forged.get("bridge_status", "in_game")
	var claimed = forged.get("claimed_in_game", false)
	return claimed and bridge_status == "in_game"

func get_bridge_cooldown_remaining(item_id: String) -> float:
	"""Get hours remaining on bridge cooldown (0 if complete or not bridging)"""
	var forged = _forged_items_by_id.get(item_id, {})
	var hours = forged.get("bridge_hours_remaining", 0.0)
	return hours

func request_bridge_out(forged_id: int, callback: Callable = Callable()) -> void:
	"""Request to bridge an item out to external wallet (48h cooldown starts)"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-out"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"forged_achievement_ids": [forged_id]})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_bridge_out_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to request bridge-out: %s" % error, "forge")
		forge_error.emit("Failed to connect to server")
		request.queue_free()

func _on_bridge_out_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Bridge-out request failed: %d / %d" % [result, response_code], "forge")
		forge_error.emit("Failed to start bridge-out")
		if callback.is_valid():
			callback.call({})
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		forge_error.emit("Invalid server response")
		if callback.is_valid():
			callback.call({})
		return

	var data = json.data
	var bridge_requests = data.get("bridge_requests", [])
	var failed = data.get("failed", [])

	# Log any failures with reasons
	if failed.size() > 0:
		for fail in failed:
			var fail_id = fail.get("forged_achievement_id", "?")
			var fail_reason = fail.get("error", "Unknown error")
			LogManager.warning("Bridge-out failed for item %s: %s" % [str(fail_id), fail_reason], "forge")

	if bridge_requests.size() > 0:
		var bridge_info = bridge_requests[0]
		LogManager.info("Bridge-out started for item: %s" % bridge_info.get("item_name", "Unknown"), "forge")
		bridge_out_requested.emit(bridge_info)

		# Update local cache
		var forged_id = bridge_info.get("forged_achievement_id", -1)
		_update_local_bridge_status(forged_id, "bridging_out")
	elif failed.size() == 0:
		LogManager.warning("Bridge-out returned no requests and no failures - check forged_id", "forge")

	if callback.is_valid():
		callback.call(data)

	# Refresh forge status and forged items to get updated data
	fetch_forge_status()
	fetch_forged_items()

func cancel_bridge_out(forged_id: int, callback: Callable = Callable()) -> void:
	"""Cancel a pending bridge-out request"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-out/cancel"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"forged_achievement_ids": [forged_id]})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_cancel_bridge_response.bind(request, forged_id, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to cancel bridge-out: %s" % error, "forge")
		forge_error.emit("Failed to connect to server")
		request.queue_free()

func _on_cancel_bridge_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, forged_id: int, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Cancel bridge-out failed: %d / %d" % [result, response_code], "forge")
		forge_error.emit("Failed to cancel bridge-out")
		if callback.is_valid():
			callback.call(false)
		return

	LogManager.info("Bridge-out cancelled for forged_id: %d" % forged_id, "forge")
	bridge_out_cancelled.emit(str(forged_id))

	# Update local cache
	_update_local_bridge_status(forged_id, "in_game")

	if callback.is_valid():
		callback.call(true)

	# Refresh forge status
	fetch_forge_status()

func fetch_bridge_status(callback: Callable = Callable()) -> void:
	"""Fetch current bridge-out status for all pending items"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-out/status"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_bridge_status_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch bridge status: %s" % error, "forge")
		request.queue_free()

func _on_bridge_status_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Bridge status fetch failed: %d / %d" % [result, response_code], "forge")
		if callback.is_valid():
			callback.call([])
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		if callback.is_valid():
			callback.call([])
		return

	var data = json.data
	var pending_bridges = data.get("pending_bridges", [])

	LogManager.info("Bridge status: %d items pending" % pending_bridges.size(), "forge")

	# Merge bridge status data (hours_remaining, can_confirm) into local cache
	var items_ready_to_confirm = []

	for bridge_item in pending_bridges:
		var forged_id = int(bridge_item.get("forged_achievement_id", -1))
		var item_id = bridge_item.get("item_id", "")
		var hours_remaining = bridge_item.get("hours_remaining", 0.0)
		var can_confirm = bridge_item.get("can_confirm", false)

		# Update in _forged_items array
		for item in _forged_items:
			if int(item.get("forged_id", -1)) == forged_id or item.get("item_id", "") == item_id:
				item["bridge_hours_remaining"] = hours_remaining
				item["can_confirm"] = can_confirm
				item["bridge_status"] = "bridging_out"
				break

		# Also update in _forged_items_by_id dict
		if item_id in _forged_items_by_id:
			_forged_items_by_id[item_id]["bridge_hours_remaining"] = hours_remaining
			_forged_items_by_id[item_id]["can_confirm"] = can_confirm
			_forged_items_by_id[item_id]["bridge_status"] = "bridging_out"

		# Emit signal so UI can refresh
		if item_id != "":
			bridge_status_updated.emit(item_id, "bridging_out")

		# Track items ready for auto-confirm
		if can_confirm and forged_id > 0:
			items_ready_to_confirm.append(forged_id)

	if callback.is_valid():
		callback.call(pending_bridges)

	# Auto-confirm any items that have passed their cooldown
	if items_ready_to_confirm.size() > 0:
		LogManager.info("Auto-confirming %d items ready for transfer" % items_ready_to_confirm.size(), "forge")
		_auto_confirm_bridge_out(items_ready_to_confirm)

func _update_local_bridge_status(forged_id: int, status: String) -> void:
	"""Update bridge status in local cache (both _forged_items and _forged_items_by_id)"""
	# Update in _forged_items array
	for item in _forged_items:
		if int(item.get("forged_id", -1)) == forged_id:
			item["bridge_status"] = status
			var item_id = item.get("item_id", "")
			bridge_status_updated.emit(item_id, status)
			break

	# Also update in _forged_items_by_id dict
	for item_id in _forged_items_by_id:
		var item = _forged_items_by_id[item_id]
		if int(item.get("forged_id", -1)) == forged_id:
			item["bridge_status"] = status
			break

func _auto_confirm_bridge_out(forged_ids: Array) -> void:
	"""Auto-confirm bridge-out for items that have passed their cooldown"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-out/confirm"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"forged_achievement_ids": forged_ids})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_auto_confirm_response.bind(request, forged_ids))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to auto-confirm bridge-out: %s" % error, "forge")
		request.queue_free()

func _on_auto_confirm_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, forged_ids: Array) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Auto-confirm bridge-out failed: %d / %d" % [result, response_code], "forge")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.data
	var transferred = data.get("transferred", [])

	LogManager.info("Auto-confirmed %d bridge-out transfers" % transferred.size(), "forge")

	# Update local cache for transferred items
	for item in transferred:
		var forged_id = int(item.get("forged_achievement_id", -1))
		if forged_id > 0:
			_update_local_bridge_status(forged_id, "bridged")

	# Refresh forged items to get final state
	if transferred.size() > 0:
		fetch_forged_items()

# ═══════════════════════════════════════════════════════════════════════════════
# WALLET STATUS - Check if external wallet is connected
# ═══════════════════════════════════════════════════════════════════════════════

func is_wallet_connected() -> bool:
	return _wallet_connected

func get_wallet_address() -> String:
	return _wallet_address

func get_wallet_address_short() -> String:
	"""Get shortened wallet address like 0x1234...5678"""
	if _wallet_address.length() < 10:
		return _wallet_address
	return _wallet_address.substr(0, 6) + "..." + _wallet_address.substr(-4)

func fetch_wallet_status(callback: Callable = Callable()) -> void:
	"""Fetch wallet connection status from backend"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		if callback.is_valid():
			callback.call(false, "")
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/status"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_wallet_status_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch wallet status: %s" % error, "forge")
		request.queue_free()
		if callback.is_valid():
			callback.call(false, "")

func _on_wallet_status_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Wallet status fetch failed: %d / %d" % [result, response_code], "forge")
		_wallet_connected = false
		_wallet_address = ""
		wallet_status_updated.emit(false, "")
		if callback.is_valid():
			callback.call(false, "")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		if callback.is_valid():
			callback.call(false, "")
		return

	var data = json.data
	_wallet_connected = data.get("connected", false)
	_wallet_address = data.get("wallet_address", "")

	LogManager.info("Wallet status: %s (%s)" % [str(_wallet_connected), get_wallet_address_short()], "forge")
	wallet_status_updated.emit(_wallet_connected, _wallet_address)

	if callback.is_valid():
		callback.call(_wallet_connected, _wallet_address)

func disconnect_wallet(callback: Callable = Callable()) -> void:
	"""Disconnect the external wallet from the user's account"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		if callback.is_valid():
			callback.call(false)
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/disconnect"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_wallet_disconnect_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_DELETE)
	if error != OK:
		LogManager.error("Failed to disconnect wallet: %s" % error, "forge")
		request.queue_free()
		if callback.is_valid():
			callback.call(false)

func _on_wallet_disconnect_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Wallet disconnect failed: %d / %d" % [result, response_code], "forge")
		if callback.is_valid():
			callback.call(false)
		return

	LogManager.info("Wallet disconnected successfully", "forge")

	# Clear local state
	_wallet_connected = false
	_wallet_address = ""
	_bridge_in_available = []

	wallet_status_updated.emit(false, "")
	bridge_in_available_updated.emit([])

	if callback.is_valid():
		callback.call(true)

# ═══════════════════════════════════════════════════════════════════════════════
# BRIDGE IN - Import items from external wallet back into game
# ═══════════════════════════════════════════════════════════════════════════════

func get_bridge_in_available() -> Array:
	"""Get items available to bridge in from external wallet"""
	return _bridge_in_available

func fetch_bridge_in_available(callback: Callable = Callable()) -> void:
	"""Fetch items available to bridge in from external wallet"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		if callback.is_valid():
			callback.call([])
		return

	if not _wallet_connected:
		LogManager.info("No wallet connected, skipping bridge-in fetch", "forge")
		_bridge_in_available = []
		bridge_in_available_updated.emit([])
		if callback.is_valid():
			callback.call([])
		return

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-in/available"
	var headers = ["Authorization: Bearer " + MantleAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_bridge_in_available_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch bridge-in available: %s" % error, "forge")
		request.queue_free()
		if callback.is_valid():
			callback.call([])

func _on_bridge_in_available_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Bridge-in available fetch failed: %d / %d" % [result, response_code], "forge")
		if callback.is_valid():
			callback.call([])
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		if callback.is_valid():
			callback.call([])
		return

	var data = json.data
	_bridge_in_available = data.get("available_items", [])

	LogManager.info("Bridge-in available: %d items" % _bridge_in_available.size(), "forge")

	# Log each available item for debugging
	for item in _bridge_in_available:
		LogManager.info("  - Bridge-in item: token_id=%s, name=%s, status=%s" % [
			str(item.get("token_id", "?")),
			item.get("item_name", "?"),
			item.get("bridge_status", "?")
		], "forge")

	bridge_in_available_updated.emit(_bridge_in_available)

	if callback.is_valid():
		callback.call(_bridge_in_available)

func request_bridge_in(token_ids: Array, callback: Callable = Callable()) -> void:
	"""Request to bridge items back into the game from external wallet"""
	if not MantleAuth or not MantleAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	if not _wallet_connected:
		forge_error.emit("Wallet not connected")
		return

	LogManager.info("Requesting bridge-in for token_ids: %s" % str(token_ids), "forge")

	var url = MantleAuth.get_api_base() + "/api/wallet/bridge-in"
	var headers = [
		"Authorization: Bearer " + MantleAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"token_ids": token_ids})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_bridge_in_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to request bridge-in: %s" % error, "forge")
		forge_error.emit("Failed to connect to server")
		request.queue_free()

func _on_bridge_in_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.error("Bridge-in request failed: %d / %d" % [result, response_code], "forge")
		forge_error.emit("Failed to bridge items in")
		if callback.is_valid():
			callback.call([])
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		forge_error.emit("Invalid server response")
		if callback.is_valid():
			callback.call([])
		return

	var data = json.data
	var bridged_in = data.get("bridged_in", [])
	var failed = data.get("failed", [])

	LogManager.info("Bridge-in complete: %d items succeeded, %d failed" % [bridged_in.size(), failed.size()], "forge")

	# Log failure details for debugging
	if failed.size() > 0:
		for fail_item in failed:
			var token_id = fail_item.get("token_id", "unknown")
			var reason = fail_item.get("error", "unknown reason")  # Backend uses "error" key
			LogManager.error("Bridge-in FAILED for token %s: %s" % [str(token_id), reason], "forge")
	bridge_in_completed.emit(bridged_in)

	if callback.is_valid():
		callback.call(bridged_in)

	# Refresh forged items to get updated status
	fetch_forged_items()
	fetch_bridge_in_available()

func get_items_bridging_out() -> Array:
	"""Get all items currently in bridging_out status"""
	var bridging = []
	for item in _forged_items:
		if item.get("bridge_status", "in_game") == "bridging_out":
			bridging.append(item)
	return bridging
