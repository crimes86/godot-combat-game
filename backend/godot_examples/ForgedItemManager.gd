# ForgedItemManager.gd
# Manages forged achievement items in Godot
#
# This script checks the Ashbane API for achievement tokens owned by the player
# and grants corresponding in-game items.

extends Node

signal items_loaded(items: Array)
signal item_granted(item_id: String, achievement_name: String)

const API_BASE = "https://your-Ashbane-api.com"  # Replace with your API URL

# Map achievement IDs to in-game items
# Format: "provider_appid_apiname" -> ItemData
var ACHIEVEMENT_ITEM_MAP = {
	# WoW Legendaries
	"battlenet_wow_thunderfury": {
		"item_id": "weapon_thunderfury",
		"display_name": "Thunderfury, Blessed Blade of the Windseeker",
		"type": "weapon",
		"rarity": "legendary",
		"model_path": "res://items/weapons/thunderfury.tscn",
		"effects": ["lightning_proc", "nature_damage"]
	},
	"battlenet_wow_sulfuras": {
		"item_id": "weapon_sulfuras",
		"display_name": "Sulfuras, Hand of Ragnaros",
		"type": "weapon",
		"rarity": "legendary",
		"model_path": "res://items/weapons/sulfuras.tscn",
		"effects": ["fire_proc", "knockback"]
	},
	"battlenet_wow_warglaives": {
		"item_id": "weapon_warglaives",
		"display_name": "Warglaives of Azzinoth",
		"type": "weapon",
		"rarity": "legendary",
		"model_path": "res://items/weapons/warglaives.tscn",
		"effects": ["dual_wield", "demon_slayer"]
	},
	# Steam achievements
	"steam_440_tf2_golden_wrench": {
		"item_id": "weapon_golden_wrench",
		"display_name": "Golden Wrench",
		"type": "weapon",
		"rarity": "legendary",
		"model_path": "res://items/weapons/golden_wrench.tscn",
		"effects": ["gold_touch"]
	},
	"steam_570_dota2_aegis": {
		"item_id": "cosmetic_aegis",
		"display_name": "Aegis of Champions",
		"type": "cosmetic",
		"rarity": "legendary",
		"model_path": "res://items/cosmetics/aegis.tscn",
		"effects": ["immortal_glow"]
	},
}

var _http_request: HTTPRequest
var _auth_token: String = ""
var _player_wallet: String = ""
var _owned_items: Array = []


func _ready():
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


# =============================================================================
# PUBLIC API
# =============================================================================

func set_auth_token(token: String):
	"""Set the Ashbane auth token (from device auth flow)"""
	_auth_token = token


func set_player_wallet(wallet_address: String):
	"""Set the player's connected wallet address"""
	_player_wallet = wallet_address


func load_forged_items():
	"""
	Load all forged items for the current player.
	Call this after authentication.
	"""
	if _auth_token.is_empty():
		push_error("ForgedItemManager: No auth token set")
		return

	var headers = ["Authorization: Bearer " + _auth_token]
	var url = API_BASE + "/api/wallet/forged"

	_http_request.request(url, headers, HTTPClient.METHOD_GET)


func check_item_ownership(achievement_ids: Array) -> void:
	"""
	Check if wallet owns specific achievement tokens.
	Used for real-time verification (e.g., in multiplayer).
	"""
	if _player_wallet.is_empty():
		push_error("ForgedItemManager: No wallet address set")
		return

	var body = JSON.stringify({
		"wallet_address": _player_wallet,
		"achievement_ids": achievement_ids
	})

	var headers = ["Content-Type: application/json"]
	var url = API_BASE + "/api/wallet/check-ownership"

	_http_request.request(url, headers, HTTPClient.METHOD_POST, body)


func get_owned_items() -> Array:
	"""Get the list of forged items the player owns"""
	return _owned_items


func has_item(item_id: String) -> bool:
	"""Check if player owns a specific item"""
	for item in _owned_items:
		if item.item_id == item_id:
			return true
	return false


func get_item_data(item_id: String) -> Dictionary:
	"""Get item data for a specific item"""
	for item in _owned_items:
		if item.item_id == item_id:
			return item
	return {}


# =============================================================================
# ITEM GRANTING
# =============================================================================

func grant_items_to_player(player: Node):
	"""
	Grant all owned forged items to the player.
	Call this after items are loaded.
	"""
	for item in _owned_items:
		_grant_single_item(player, item)


func _grant_single_item(player: Node, item: Dictionary):
	"""Grant a single forged item to the player"""
	match item.type:
		"weapon":
			_grant_weapon(player, item)
		"cosmetic":
			_grant_cosmetic(player, item)
		"mount":
			_grant_mount(player, item)
		_:
			push_warning("Unknown item type: " + item.type)

	item_granted.emit(item.item_id, item.display_name)


func _grant_weapon(player: Node, item: Dictionary):
	"""Add weapon to player's inventory"""
	if player.has_method("add_weapon"):
		var weapon_scene = load(item.model_path)
		if weapon_scene:
			var weapon_instance = weapon_scene.instantiate()
			weapon_instance.set_meta("forged", true)  # Mark as forged item
			weapon_instance.set_meta("achievement_id", item.achievement_id)
			player.add_weapon(weapon_instance)
			print("Granted forged weapon: ", item.display_name)


func _grant_cosmetic(player: Node, item: Dictionary):
	"""Add cosmetic to player"""
	if player.has_method("add_cosmetic"):
		player.add_cosmetic(item.item_id, item.model_path)
		print("Granted forged cosmetic: ", item.display_name)


func _grant_mount(player: Node, item: Dictionary):
	"""Add mount to player's collection"""
	if player.has_method("unlock_mount"):
		player.unlock_mount(item.item_id)
		print("Granted forged mount: ", item.display_name)


# =============================================================================
# HTTP RESPONSE HANDLING
# =============================================================================

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("ForgedItemManager: Request failed with result " + str(result))
		return

	if response_code != 200:
		push_error("ForgedItemManager: Request failed with code " + str(response_code))
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())

	if parse_result != OK:
		push_error("ForgedItemManager: Failed to parse response")
		return

	var data = json.get_data()

	# Handle forged items response
	if data.has("forged"):
		_process_forged_items(data.forged)

	# Handle ownership check response
	if data.has("ownership"):
		_process_ownership_check(data.ownership)


func _process_forged_items(forged_list: Array):
	"""Process the list of forged achievements from API"""
	_owned_items.clear()

	for forged in forged_list:
		var achievement = forged.achievement

		# Build achievement ID to look up in our map
		# This would need the provider and app_id from the API response
		# For now, using a simplified lookup
		var achievement_id = _find_achievement_id(achievement.display_name)

		if achievement_id.is_empty():
			continue

		if ACHIEVEMENT_ITEM_MAP.has(achievement_id):
			var item_data = ACHIEVEMENT_ITEM_MAP[achievement_id].duplicate()
			item_data.achievement_id = achievement_id
			item_data.token_id = forged.token_id
			item_data.forged_at = forged.forged_at
			_owned_items.append(item_data)

	print("Loaded ", _owned_items.size(), " forged items")
	items_loaded.emit(_owned_items)


func _process_ownership_check(ownership: Dictionary):
	"""Process ownership verification response"""
	for achievement_id in ownership:
		var owns = ownership[achievement_id]
		if owns and ACHIEVEMENT_ITEM_MAP.has(achievement_id):
			var item = ACHIEVEMENT_ITEM_MAP[achievement_id]
			print("Verified ownership: ", item.display_name)


func _find_achievement_id(display_name: String) -> String:
	"""Find achievement ID by display name (simplified lookup)"""
	for id in ACHIEVEMENT_ITEM_MAP:
		if ACHIEVEMENT_ITEM_MAP[id].display_name == display_name:
			return id
	return ""


# =============================================================================
# PROVENANCE CHECK (earned vs traded)
# =============================================================================

signal provenance_checked(token_id: int, is_original: bool, acquisition_type: String)

func check_item_provenance(token_id: int) -> void:
	"""
	Check if an item was earned or traded.

	Emits provenance_checked signal with results.
	Use this to show different effects/badges for earned vs traded items.
	"""
	var url = API_BASE + "/api/wallet/provenance/" + str(token_id)
	_http_request.request(url, [], HTTPClient.METHOD_GET)


func get_item_badge(item: Dictionary) -> String:
	"""
	Get display badge based on how item was acquired.

	Returns:
	- "EARNED" - Player grinded for this achievement
	- "TRADED" - Player bought/received this from someone else
	"""
	if item.has("is_original") and item.is_original:
		return "EARNED"
	else:
		return "TRADED"


func get_item_badge_color(item: Dictionary) -> Color:
	"""Get badge color - gold for earned, silver for traded."""
	if item.has("is_original") and item.is_original:
		return Color(1.0, 0.84, 0.0)  # Gold
	else:
		return Color(0.75, 0.75, 0.75)  # Silver


# =============================================================================
# MULTIPLAYER VERIFICATION
# =============================================================================

func verify_player_item(player_wallet: String, item_id: String) -> void:
	"""
	Verify another player owns an item they're displaying.
	Used in multiplayer to prevent spoofing.
	"""
	# Find the achievement ID for this item
	var achievement_id = ""
	for id in ACHIEVEMENT_ITEM_MAP:
		if ACHIEVEMENT_ITEM_MAP[id].item_id == item_id:
			achievement_id = id
			break

	if achievement_id.is_empty():
		push_warning("Unknown item for verification: " + item_id)
		return

	# Check on-chain ownership
	var body = JSON.stringify({
		"wallet_address": player_wallet,
		"achievement_ids": [achievement_id]
	})

	var headers = ["Content-Type: application/json"]
	var url = API_BASE + "/api/wallet/check-ownership"

	# This would need a separate HTTPRequest to avoid conflicts
	# In production, use a request queue or multiple HTTPRequest nodes
	_http_request.request(url, headers, HTTPClient.METHOD_POST, body)
