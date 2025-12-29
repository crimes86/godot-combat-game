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
signal bridge_in_approval_required()  # Emitted when platform needs approval for bridge-in

# Cached forged items from API
var _forged_items: Array = []
var _forged_items_by_id: Dictionary = {}  # item_id -> forged item
var _is_fetching: bool = false
var _is_loaded: bool = false
var _synced_to_inventory: bool = false

# Forge status - achievements that CAN be forged but haven't been yet
var _forgeable_achievements: Array = []  # Achievements user can forge (Rare+, original claim)
var _forge_status_loaded: bool = false
var _debug_forge_mode: bool = false  # When true, backend won't overwrite debug-injected forgeable list
var _debug_claims_cleared: bool = false  # When true, sync_to_inventory will skip re-adding items

# Wallet and bridge status
var _wallet_connected: bool = false
var _wallet_address: String = ""
var _bridge_in_available: Array = []  # Items in external wallet that can be bridged in

# ═══════════════════════════════════════════════════════════════════════════════
# FORGED ITEM RARITY SCALING
# ═══════════════════════════════════════════════════════════════════════════════
# Forged items are ONLY Rare/Epic/Legendary (no Common/Uncommon)
# Common/Uncommon are for in-game drops and shop items only
#
# Designed to align with in-game tier progression:
#   Rare → Zone 2 early, falls off late (12-16 dmg)
#   Epic → Zone 2-3, competitive mid-late (18-24 dmg)
#   Legendary → Zone 4, equals max tier drops (26-32 dmg)
#
# In-game items (Common/Uncommon) fill the early game gap:
#   Common → Zone 1 (2-6 dmg)
#   Uncommon → Zone 1-2 transition (8-12 dmg)
# ═══════════════════════════════════════════════════════════════════════════════

const RARITY_BASE_DAMAGE = {
	"rare": 14,
	"epic": 21,
	"legendary": 29
}

# Variance range per rarity (final damage = base ± variance)
const RARITY_DAMAGE_VARIANCE = {
	"rare": 2,        # 12-16
	"epic": 3,        # 18-24
	"legendary": 3    # 26-32
}

# Rarity-based defense scaling for forged armor (per piece)
const RARITY_BASE_DEFENSE = {
	"rare": 4,        # Full set = 20 defense
	"epic": 5,        # Full set = 25 defense
	"legendary": 7    # Full set = 35 defense
}

# Shield base block chance by rarity
const RARITY_BLOCK_CHANCE = {
	"rare": 0.16,
	"epic": 0.20,
	"legendary": 0.25
}

# Legacy multiplier (kept for sell value calculation)
const RARITY_DAMAGE_BONUS = {
	"common": 1,
	"uncommon": 2,
	"rare": 3,
	"epic": 4,
	"legendary": 5
}

func _ready() -> void:
	if AshbaneAuth:
		AshbaneAuth.auth_completed.connect(_on_auth_completed)
		AshbaneAuth.logout_completed.connect(_on_logout)

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
	_debug_forge_mode = false
	_debug_claims_cleared = false

# ═══════════════════════════════════════════════════════════════════════════════
# DEBUG - Remove after testing
# ═══════════════════════════════════════════════════════════════════════════════

func debug_reset_all_claims() -> void:
	"""DEBUG: Reset ALL forge claims so items can be reclaimed for testing.
	This clears: inventory forged items, claimed_in_game flags, and playtest claims."""

	# 1. Clear forged items from inventory
	var inv_cleared = 0
	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item and item.get("is_forged", false):
			InventorySystem.inventory_items[i] = null
			inv_cleared += 1

	# 2. Reset claimed_in_game flags on all forged items
	var flags_reset = 0
	for item in _forged_items:
		if item.get("claimed_in_game", false):
			item["claimed_in_game"] = false
			flags_reset += 1
	for item_id in _forged_items_by_id:
		if _forged_items_by_id[item_id].get("claimed_in_game", false):
			_forged_items_by_id[item_id]["claimed_in_game"] = false

	# 3. Clear playtest claims
	var playtest_count = CharacterStats.get_playtest_claimed_count()
	CharacterStats.clear_playtest_claims()

	# 4. Set debug flag to prevent sync_to_inventory from re-adding items
	_debug_claims_cleared = true

	print("═══════════════════════════════════════════════════════════")
	print("🔄 FORGE CLAIMS RESET")
	print("   Inventory cleared: %d forged items" % inv_cleared)
	print("   Claim flags reset: %d items" % flags_reset)
	print("   Playtest claims cleared: %d" % playtest_count)
	print("   Debug claims cleared flag: SET (sync will skip)")
	print("═══════════════════════════════════════════════════════════")

	InventorySystem.inventory_changed.emit()

func debug_clear_claimed_items() -> void:
	"""DEBUG: Alias for debug_reset_all_claims()"""
	debug_reset_all_claims()

func debug_inject_all_as_forgeable() -> void:
	"""DEBUG: Inject ALL items from ForgeItemDB as forgeable achievements.
	This gives the user forge opportunities for every item in the catalog.
	Skips items that are already forged (owned)."""
	# Set debug mode flag to prevent backend from overwriting our injected list
	_debug_forge_mode = true

	# Clear existing forgeable list to avoid duplicates on re-inject
	_forgeable_achievements.clear()

	var count = 0
	var skipped = 0
	for achievement_key in ForgeItemDB.FORGE_ITEMS.keys():
		var forge_db = ForgeItemDB.FORGE_ITEMS[achievement_key]
		var item_id = forge_db.get("item_id", "")
		var item_name = forge_db.get("item_name", "Unknown")
		var achievement_name = forge_db.get("achievement_name", "")

		# Skip items that are already forged (owned by user)
		if item_id in _forged_items_by_id:
			skipped += 1
			continue

		# Create mock forgeable achievement matching backend format
		# Include item_id for direct matching (more reliable than achievement name)
		var mock_achievement = {
			"id": 90000 + count,  # Fake IDs for testing
			"achievement_id": 90000 + count,  # Armory looks for this field
			"achievement_key": achievement_key,
			"display_name": achievement_name,  # Use achievement_name for Armory matching
			"item_name": item_name,
			"item_id": item_id,  # Key field for matching
			"rarity": _rarity_enum_to_string(forge_db.get("rarity", 0)),
			"provider": "debug",
			"app_id": "debug",
			"api_name": achievement_key,
			"unlock_percent": forge_db.get("unlock_percent", 5.0),
			"description": forge_db.get("description", "Debug achievement"),
			"is_original_claim": true
		}

		_forgeable_achievements.append(mock_achievement)
		count += 1

	_forge_status_loaded = true
	print("[ForgeItemManager] DEBUG: Injected %d items as forgeable (skipped %d already forged)" % [count, skipped])
	forge_status_loaded.emit({"forgeable": _forgeable_achievements, "forged": [], "unforgeable": []})

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
		"achievement_id": 99999,  # Armory looks for this field
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

	# Determine item_type from forge_db (armor_head, weapon, etc.)
	var db_item_type = forge_db.get("item_type", ForgeItemDB.ItemType.WEAPON)
	var item_type_str = ForgeItemDB.ItemType.keys()[db_item_type].to_lower() if db_item_type is int else "weapon"

	# Create forged item matching what backend would return
	var forged_item = {
		"id": 99999,
		"item_id": forge_db.get("item_id", "test_item"),
		"item_name": forge_db.get("item_name", "Test Item"),
		"item_type": item_type_str,
		"weapon_type": _weapon_class_to_string(forge_db.get("weapon_class", 0)) if item_type_str == "weapon" else null,
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

	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		LogManager.warning("Cannot fetch forged items - not authenticated", "forge")
		return

	_is_fetching = true
	var url = AshbaneAuth.get_api_base() + "/api/me/forged-items"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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

	# Preserve bridge_cooldown_ends_at timestamps before replacing data
	# (these are client-computed and not stored on backend)
	var preserved_cooldowns: Dictionary = {}
	for old_item in _forged_items:
		var item_id = old_item.get("item_id", "")
		if item_id != "" and old_item.has("bridge_cooldown_ends_at"):
			preserved_cooldowns[item_id] = old_item["bridge_cooldown_ends_at"]

	_forged_items = data.get("forged_items", [])

	# Restore preserved cooldown timestamps
	for item in _forged_items:
		var item_id = item.get("item_id", "")
		if item_id in preserved_cooldowns:
			item["bridge_cooldown_ends_at"] = preserved_cooldowns[item_id]

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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return

	var url = AshbaneAuth.get_api_base() + "/api/me/forge-status"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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
		# Endpoint doesn't exist yet - use empty list (unless debug mode)
		LogManager.info("Forge status endpoint not implemented yet", "forge")
		if _debug_forge_mode:
			# In debug mode, keep our injected list
			LogManager.info("Debug mode active: keeping %d injected forgeable items" % _forgeable_achievements.size(), "forge")
			forge_status_loaded.emit({"forgeable": _forgeable_achievements, "forged": [], "unforgeable": []})
			return
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

	# In debug forge mode, don't let backend overwrite our injected forgeable list
	if _debug_forge_mode:
		LogManager.info("Forge status loaded: %d from backend (ignored - debug mode active, keeping %d injected)" % [data.get("forgeable", []).size(), _forgeable_achievements.size()], "forge")
		# Still emit signal but with our debug data, not backend data
		forge_status_loaded.emit({"forgeable": _forgeable_achievements, "forged": [], "unforgeable": []})
		return

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

func remove_from_forgeable(item_id: String) -> void:
	"""Remove an item from the forgeable list by item_id (used after forging in debug mode)"""
	if item_id == "":
		return
	var new_list = []
	for ach in _forgeable_achievements:
		if ach.get("item_id", "") != item_id:
			new_list.append(ach)
	var removed = _forgeable_achievements.size() - new_list.size()
	if removed > 0:
		_forgeable_achievements = new_list
		LogManager.info("Removed '%s' from forgeable list (%d items remaining)" % [item_id, _forgeable_achievements.size()], "forge")

func claim_forge(credit_id: int, callback: Callable = Callable(), item_id: String = "", _debug_bypass: bool = false) -> void:
	"""Forge an achievement into an item using the wallet/forge endpoint.
	credit_id: The AchievementCredit ID (not achievement_id) from forgeable achievements."""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/forge"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
		"Content-Type: application/json"
	]
	# The wallet/forge endpoint expects achievement_credit_ids array
	var request_data = {"achievement_credit_ids": [credit_id]}
	var body = JSON.stringify(request_data)

	LogManager.info("Forging credit_id: %d (item: %s)" % [credit_id, item_id], "forge")

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_claim_response.bind(request, callback, item_id))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to claim forge: %s" % error, "forge")
		forge_error.emit("Failed to connect to server")
		request.queue_free()

func _on_claim_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable, item_id: String) -> void:
	request.queue_free()
	# Clear debug claims flag when a forge completes (user is actively claiming)
	_debug_claims_cleared = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var body_text = body.get_string_from_utf8()
		LogManager.error("Forge claim failed: %d / %d - %s" % [result, response_code, body_text], "forge")
		forge_error.emit("Failed to forge item")
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

	# Check for failures first
	var failed = data.get("failed", [])
	if failed.size() > 0:
		var error_msg = failed[0].get("error", "Unknown error")
		LogManager.error("Forge failed: %s" % error_msg, "forge")
		forge_error.emit(error_msg)
		if callback.is_valid():
			callback.call({})
		return

	# Get the forged item from the response
	var forged_list = data.get("forged", [])
	if forged_list.size() == 0:
		LogManager.error("Forge returned empty forged list", "forge")
		forge_error.emit("No item forged")
		if callback.is_valid():
			callback.call({})
		return

	var forged_data = forged_list[0]
	var item_props = forged_data.get("item", {})

	# Build forged_item structure for cache and inventory
	var forged_item_id = item_props.get("item_id", item_id)

	# Get forger name - this is the current user who just forged
	var forger_name_value = ""
	if AshbaneAuth and AshbaneAuth.is_logged_in():
		forger_name_value = AshbaneAuth.username if AshbaneAuth.username else "Unknown"

	# Get current timestamp for forged_at (backend may also provide this)
	var forged_at_value = forged_data.get("forged_at", forged_data.get("created_at", ""))
	if forged_at_value == "":
		# Use current ISO timestamp if backend didn't provide one
		var datetime = Time.get_datetime_dict_from_system(true)  # UTC
		forged_at_value = "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second
		]

	var forged_item = {
		"id": forged_item_id,  # String item_id for consistency with catalog
		"item_id": forged_item_id,
		"forged_id": forged_data.get("forged_achievement_id", 0),  # Database ID for bridge-out
		"credit_id": forged_data.get("credit_id", 0),  # Numeric credit ID
		"item_name": item_props.get("item_name", ""),
		"item_type": item_props.get("item_type", ""),
		"weapon_type": item_props.get("weapon_type", ""),
		"item_rarity": item_props.get("item_rarity", "common"),
		"effect_name": item_props.get("effect_name", ""),
		"effect_intensity": item_props.get("effect_intensity", 0),
		"glow_color": item_props.get("glow_color", ""),
		"token_id": forged_data.get("token_id"),
		"tx_hash": forged_data.get("tx_hash", ""),
		"claimed_in_game": true,  # Auto-claimed on forge
		# Provenance info for display
		"game": forged_data.get("game_name", ""),
		"achievement": forged_data.get("achievement_name", ""),
		"source_provider": item_props.get("source_provider", ""),
		# Provenance fields for ItemInspectionUI
		"forger_name": forger_name_value,
		"original_forger": forger_name_value,
		"forged_at": forged_at_value,
		"trade_count": 0,  # New items haven't been traded
	}

	# Add to cache
	_forged_items.append(forged_item)
	if forged_item_id != "":
		_forged_items_by_id[forged_item_id] = forged_item

	LogManager.info("Forged new item: %s (token_id: %s)" % [forged_item.get("item_name", "Unknown"), str(forged_item.get("token_id", ""))], "forge")

	# Add to inventory immediately (auto-claim on forge)
	var inventory_item = _convert_to_inventory_format(forged_item)
	if not inventory_item.is_empty():
		if InventorySystem.add_item(inventory_item):
			LogManager.info("Added forged item to inventory: %s" % forged_item.get("item_name", "Unknown"), "forge")
			item_synced_to_inventory.emit(inventory_item)
		else:
			LogManager.error("Failed to add forged item to inventory (full?): %s" % forged_item_id, "forge")

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

	# Skip sync if debug claims were cleared (prevents items coming back after deletion)
	if _debug_claims_cleared:
		LogManager.info("Skipping sync_to_inventory - debug claims cleared flag is set", "forge")
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
		# NOTE: token_id can be float from JSON (e.g., 134.0), must convert to int first
		var token_id = forged.get("token_id", 0)
		if token_id is float:
			token_id = int(token_id)
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
	# Clear debug claims flag when user explicitly claims an item
	_debug_claims_cleared = false

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
	if token_id is float:
		token_id = int(token_id)
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

	# Immediately sync to server to persist the claimed item (don't wait for auto-save timer)
	if NetworkManager and NetworkManager.is_authenticated and not NetworkManager.is_host and not NetworkManager.is_guest:
		NetworkManager.client_sync_state()
		LogManager.debug("Synced inventory to server after forge claim", "forge")

	return inventory_item

func _claim_on_server(token_id: int) -> bool:
	"""Mark item as claimed on server. Returns true on success."""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		LogManager.warning("Cannot claim on server - not authenticated", "forge")
		return true  # Allow claim anyway if not authenticated (offline mode)

	var url = AshbaneAuth.get_api_base() + "/api/forge/claim-to-game"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
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
	# NOTE: token_id can be float from JSON (e.g., 134.0), must convert to int first
	var token_id = forged.get("token_id", 0)
	if token_id is float:
		token_id = int(token_id)
	var forged_id = str(token_id) if token_id else forged.get("item_id", "")
	return _is_item_in_inventory(forged_id)

func _is_item_in_inventory(forged_id: String) -> bool:
	"""Check if a forged item is already in inventory (local check)"""
	for slot in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[slot]
		if item:
			# Check by forged_id first, then by item_id as fallback
			if item.get("forged_id", "") == str(forged_id):
				return true
			if item.get("item_id", "") == forged_id:
				return true
	return false

# ═══════════════════════════════════════════════════════════════════════════════
# ITEM DESTRUCTION / UNCLAIM - Game server authoritative actions
# ═══════════════════════════════════════════════════════════════════════════════

signal item_destroyed(token_id: int, reason: String)
signal item_unclaimed(token_id: int)

func destroy_item(token_id: int, reason: String = "player_delete", callback: Callable = Callable()) -> Dictionary:
	"""Permanently destroy a forged item (vendor sale, player delete, etc).
	Item is transferred to treasury wallet and soft-deleted for potential recovery.
	Returns: { "success": bool, "gold_received": int, "error": String }"""

	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		LogManager.warning("Cannot destroy item - not authenticated", "forge")
		# Allow destruction anyway in offline mode (local only)
		_remove_from_local_cache(token_id)
		if callback.is_valid():
			callback.call({"success": true, "gold_received": 0, "offline": true})
		return {"success": true, "gold_received": 0, "offline": true}

	var url = AshbaneAuth.get_api_base() + "/api/forge/destroy"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({
		"token_id": token_id,
		"reason": reason  # "vendor_sale", "player_delete", "dropped_decay"
	})

	var http = HTTPRequest.new()
	add_child(http)

	var error = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		LogManager.error("Failed to send destroy request: %s" % error, "forge")
		if callback.is_valid():
			callback.call({"success": false, "error": "Request failed"})
		return {"success": false, "error": "Request failed"}

	# Wait for response
	var result = await http.request_completed
	http.queue_free()

	var response_code = result[1]
	var response_body = result[3].get_string_from_utf8()

	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(response_body)
		var data = json.data if parse_result == OK else {}

		var gold_received = data.get("gold_received", 0)
		LogManager.info("Item destroyed (token_id: %d, reason: %s, gold: %d)" % [token_id, reason, gold_received], "forge")

		# Remove from local cache
		_remove_from_local_cache(token_id)

		item_destroyed.emit(token_id, reason)

		var response = {"success": true, "gold_received": gold_received}
		if callback.is_valid():
			callback.call(response)
		return response
	else:
		LogManager.error("Destroy item failed with code %d: %s" % [response_code, response_body], "forge")
		var response = {"success": false, "error": "Server rejected destruction"}
		if callback.is_valid():
			callback.call(response)
		return response

func unclaim_from_game(token_id: int, callback: Callable = Callable()) -> bool:
	"""Unclaim item from game - still exists in user's forge, can be re-claimed.
	Use this for 'stash' functionality or temporary removal."""

	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		LogManager.warning("Cannot unclaim item - not authenticated", "forge")
		if callback.is_valid():
			callback.call(false)
		return false

	var url = AshbaneAuth.get_api_base() + "/api/forge/unclaim-from-game"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
		"Content-Type: application/json"
	]
	var body = JSON.stringify({"token_id": token_id})

	var http = HTTPRequest.new()
	add_child(http)

	var error = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		LogManager.error("Failed to send unclaim request: %s" % error, "forge")
		if callback.is_valid():
			callback.call(false)
		return false

	# Wait for response
	var result = await http.request_completed
	http.queue_free()

	var response_code = result[1]

	if response_code == 200:
		LogManager.info("Item unclaimed from game (token_id: %d)" % token_id, "forge")

		# Update local cache - mark as unclaimed
		_mark_unclaimed_in_cache(token_id)

		item_unclaimed.emit(token_id)

		if callback.is_valid():
			callback.call(true)
		return true
	else:
		LogManager.error("Unclaim item failed with code %d" % response_code, "forge")
		if callback.is_valid():
			callback.call(false)
		return false

func _remove_from_local_cache(token_id: int) -> void:
	"""Remove item from local forged items cache after destruction"""
	# Remove from array
	for i in range(_forged_items.size() - 1, -1, -1):
		var item = _forged_items[i]
		var item_token = item.get("token_id", 0)
		if item_token is float:
			item_token = int(item_token)
		if item_token == token_id:
			var item_id = item.get("item_id", "")
			_forged_items.remove_at(i)
			# Also remove from dict
			if item_id in _forged_items_by_id:
				_forged_items_by_id.erase(item_id)
			LogManager.debug("Removed token_id %d from local cache" % token_id, "forge")
			break

func _mark_unclaimed_in_cache(token_id: int) -> void:
	"""Mark item as unclaimed in local cache"""
	for item in _forged_items:
		var item_token = item.get("token_id", 0)
		if item_token is float:
			item_token = int(item_token)
		if item_token == token_id:
			item["claimed_in_game"] = false
			LogManager.debug("Marked token_id %d as unclaimed in cache" % token_id, "forge")
			break

func _convert_to_inventory_format(forged: Dictionary) -> Dictionary:
	"""Convert forged item from API format to inventory format"""
	var item_type = forged.get("item_type", "weapon")
	var rarity = forged.get("item_rarity", "common").to_lower()
	var damage_bonus = RARITY_DAMAGE_BONUS.get(rarity, 1)

	# Look up full item data from ForgeItemDB if we have an item_id
	var item_id = forged.get("item_id", "")
	var forge_db_item = {}
	if item_id != "":
		forge_db_item = ForgeItemDB.get_item_by_id(item_id)

	# Get forger name from AshbaneAuth if this is our item
	var forger_name = forged.get("forger_name", forged.get("original_forger", ""))
	if forger_name == "" and AshbaneAuth and AshbaneAuth.is_logged_in():
		forger_name = AshbaneAuth.username if AshbaneAuth.username else "Unknown"

	# Get token_id (can be int or float from JSON)
	var token_id = forged.get("token_id", 0)
	if token_id is float:
		token_id = int(token_id)

	var base_item = {
		"name": forged.get("item_name", "Forged Item"),
		"description": forged.get("description", "A forged item from an achievement."),
		"stackable": false,
		"quantity": 1,
		"is_forged": true,
		"forged_id": str(token_id if token_id else forged.get("item_id", "")),
		"forged_item_id": forged.get("item_id", ""),  # Used by Player.gd for sprite lookup
		"item_id": forged.get("item_id", ""),
		"rarity": rarity.capitalize(),
		"effect_name": forged.get("effect_name", ""),
		"effect_intensity": forged.get("effect_intensity", 0.5),
		"glow_color": forged.get("glow_color", "#ffffff"),
		"effort_tier": forged.get("effort_tier", ""),
		"vintage_years": forged.get("vintage_years", 0),
		"is_secret": forged.get("is_secret", false),
		# The Tapestry provenance (cross-platform identity)
		"source_provider": forged.get("source_provider", "steam"),
		"provider_accent_color": forged.get("provider_accent_color", "#1B9BD7"),
		"can_trade": true,
		"value": damage_bonus * 100,  # Base sell value
		# Provenance fields for ItemInspectionUI
		"token_id": token_id,
		"forger_name": forger_name,
		"original_forger": forger_name,
		"forged_at": forged.get("forged_at", forged.get("created_at", "")),
		"tx_hash": forged.get("tx_hash", ""),
		"trade_count": forged.get("trade_count", 0),
	}

	match item_type:
		"weapon":
			base_item["type"] = "weapon"
			base_item["slot"] = "mainhand"
			# Get weapon_type from ForgeItemDB if available, otherwise from forged param, fallback to sword
			base_item["weapon_type"] = forge_db_item.get("weapon_type", forged.get("weapon_type", "sword"))

			# Calculate damage using rarity-based scaling system
			# Forged items are only Rare/Epic/Legendary (fallback to Rare if invalid)
			var rarity_base = RARITY_BASE_DAMAGE.get(rarity, 14)  # Fallback to Rare
			var rarity_variance = RARITY_DAMAGE_VARIANCE.get(rarity, 2)

			# Use item's individual base_damage as a variance seed (normalized to -1 to +1 range)
			# This gives each weapon some personality while keeping rarity as the primary factor
			var item_base = forge_db_item.get("base_damage", 5.0)
			if item_base is Dictionary:
				item_base = (item_base.get("min", 5) + item_base.get("max", 5)) / 2.0
			var variance_modifier = clampf((float(item_base) - 7.0) / 5.0, -1.0, 1.0)  # Normalize around 7
			var final_damage = rarity_base + int(variance_modifier * rarity_variance)

			base_item["base_damage"] = final_damage
			base_item["attack_speed"] = forge_db_item.get("attack_speed", "medium")
			base_item["crit_chance_bonus"] = forge_db_item.get("crit_chance_bonus", forge_db_item.get("crit_chance", 0.05))
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")
			base_item["required_level"] = 1  # Forged items have no level req (twinking!)
			# Gun weapons need ranged_damage attack mode for cursor-based targeting
			if base_item["weapon_type"] == "gun":
				base_item["attack_mode"] = "ranged_damage"
				base_item["gun_radius"] = 28.0  # Precision targeting radius
				base_item["gun_range"] = 550.0  # Max shooting distance
				# Apply gun properties from ForgeItemDB first, then check forged param
				var gun_subtype = forge_db_item.get("gun_subtype", forged.get("gun_subtype", "railgun"))
				var burst_count = forge_db_item.get("burst_count", forged.get("burst_count", 1))
				var burst_delay = forge_db_item.get("burst_delay", forged.get("burst_delay", 0.10))

				base_item["gun_subtype"] = gun_subtype
				base_item["burst_count"] = burst_count
				base_item["burst_delay"] = burst_delay

		"armor_head", "armor_chest", "armor_legs", "armor_hands", "armor_feet":
			base_item["type"] = "armor"
			base_item["slot"] = item_type.replace("armor_", "")
			# Use rarity-based defense scaling (aligns with weapon damage progression)
			var base_defense = RARITY_BASE_DEFENSE.get(rarity, 2)
			# Chest pieces get +1 defense bonus, head gets standard
			if item_type == "armor_chest":
				base_defense += 1
			base_item["defense"] = forge_db_item.get("defense", base_defense)
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")

		"shield":
			base_item["type"] = "shield"
			base_item["slot"] = "offhand"
			# Shields get higher defense than armor pieces + block chance
			var shield_defense = RARITY_BASE_DEFENSE.get(rarity, 2) + 3
			base_item["defense"] = forge_db_item.get("defense", shield_defense)
			base_item["block_chance"] = RARITY_BLOCK_CHANCE.get(rarity, 0.10)
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")

		"cape":
			base_item["type"] = "cape"
			base_item["slot"] = "back"
			if forge_db_item.has("defense"):
				base_item["defense"] = forge_db_item.get("defense")
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")

		"ring":
			base_item["type"] = "ring"
			# Rings can go to either ring1 or ring2 slot - UI handles placement
			base_item["slot"] = "ring"
			# Copy stat bonuses and special effects from ForgeItemDB
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")
			if forge_db_item.has("hp_bonus"):
				base_item["hp_bonus"] = forge_db_item.get("hp_bonus")
			if forge_db_item.has("lifesteal"):
				base_item["lifesteal"] = forge_db_item.get("lifesteal")
			if forge_db_item.has("cooldown_reduction"):
				base_item["cooldown_reduction"] = forge_db_item.get("cooldown_reduction")
			if forge_db_item.has("movement_speed"):
				base_item["movement_speed"] = forge_db_item.get("movement_speed")

		"amulet":
			base_item["type"] = "amulet"
			base_item["slot"] = "amulet"
			# Copy stat bonuses and special effects from ForgeItemDB
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")
			if forge_db_item.has("hp_bonus"):
				base_item["hp_bonus"] = forge_db_item.get("hp_bonus")
			if forge_db_item.has("lifesteal"):
				base_item["lifesteal"] = forge_db_item.get("lifesteal")
			if forge_db_item.has("cooldown_reduction"):
				base_item["cooldown_reduction"] = forge_db_item.get("cooldown_reduction")
			if forge_db_item.has("movement_speed"):
				base_item["movement_speed"] = forge_db_item.get("movement_speed")

		"accessory":
			# Accessories are inventory-only items (badges, fragments, etc.)
			# They do NOT have a slot - cannot be equipped to character paperdoll
			base_item["type"] = "accessory"
			# Copy stat bonuses if any (passive effects while in inventory)
			if forge_db_item.has("stat_bonuses"):
				base_item["stat_bonuses"] = forge_db_item.get("stat_bonuses")
			if forge_db_item.has("hp_bonus"):
				base_item["hp_bonus"] = forge_db_item.get("hp_bonus")

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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out/cancel"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out/status"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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
		var hours_remaining = bridge_item.get("hours_remaining", -1.0)
		var can_confirm = bridge_item.get("can_confirm", false)

		# Default to 2 minutes if API doesn't provide hours_remaining or returns 0 but not confirmable
		if hours_remaining <= 0 and not can_confirm:
			hours_remaining = 0.0333  # 2 minutes default

		# Calculate end timestamp so countdown survives UI refreshes
		var cooldown_ends_at = Time.get_unix_time_from_system() + (hours_remaining * 3600.0)

		LogManager.info("Bridge item %s: hours=%.4f, can_confirm=%s, ends_at=%.0f" % [item_id, hours_remaining, str(can_confirm), cooldown_ends_at], "forge")

		# Update in _forged_items array
		for item in _forged_items:
			if int(item.get("forged_id", -1)) == forged_id or item.get("item_id", "") == item_id:
				# Only update cooldown_ends_at if not already set (preserve existing countdown)
				if not item.has("bridge_cooldown_ends_at"):
					item["bridge_cooldown_ends_at"] = cooldown_ends_at
				item["bridge_hours_remaining"] = hours_remaining
				item["can_confirm"] = can_confirm
				item["bridge_status"] = "bridging_out"
				break

		# Also update in _forged_items_by_id dict
		if item_id in _forged_items_by_id:
			# Only update cooldown_ends_at if not already set (preserve existing countdown)
			if not _forged_items_by_id[item_id].has("bridge_cooldown_ends_at"):
				_forged_items_by_id[item_id]["bridge_cooldown_ends_at"] = cooldown_ends_at
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
			# Set default hours for bridging_out until API responds with actual time
			if status == "bridging_out" and not item.has("bridge_hours_remaining"):
				item["bridge_hours_remaining"] = 0.0333  # 2 minutes default
				item["can_confirm"] = false
			var item_id = item.get("item_id", "")
			bridge_status_updated.emit(item_id, status)
			break

	# Also update in _forged_items_by_id dict
	for item_id in _forged_items_by_id:
		var item = _forged_items_by_id[item_id]
		if int(item.get("forged_id", -1)) == forged_id:
			item["bridge_status"] = status
			# Set default hours for bridging_out until API responds with actual time
			if status == "bridging_out" and not item.has("bridge_hours_remaining"):
				item["bridge_hours_remaining"] = 0.0333  # 2 minutes default
				item["can_confirm"] = false
			break

func _auto_confirm_bridge_out(forged_ids: Array) -> void:
	"""Auto-confirm bridge-out for items that have passed their cooldown"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-out/confirm"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		if callback.is_valid():
			callback.call(false, "")
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/status"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		if callback.is_valid():
			callback.call(false)
		return

	var url = AshbaneAuth.get_api_base() + "/api/wallet/disconnect"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
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

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in/available"
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

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
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		forge_error.emit("Not authenticated")
		return

	if not _wallet_connected:
		forge_error.emit("Wallet not connected")
		return

	LogManager.info("Requesting bridge-in for token_ids: %s" % str(token_ids), "forge")

	var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
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

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Bridge-in request failed: result=%d" % result, "forge")
		forge_error.emit("Failed to connect to server")
		if callback.is_valid():
			callback.call([])
		return

	# Handle 403 - approval required
	if response_code == 403:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.data
			var detail = data.get("detail", {})
			if typeof(detail) == TYPE_DICTIONARY and detail.get("requires_approval", false):
				LogManager.warning("Bridge-in requires platform approval", "forge")
				bridge_in_approval_required.emit()
				if callback.is_valid():
					callback.call([])
				return
		LogManager.error("Bridge-in forbidden: %s" % body.get_string_from_utf8(), "forge")
		forge_error.emit("Permission denied for bridge-in")
		if callback.is_valid():
			callback.call([])
		return

	if response_code != 200:
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
