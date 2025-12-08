extends Node
## ForgeItemManager - Fetches and caches forged items from backend
## Items come pre-computed with stats, effects, and visual data

signal forged_items_loaded(items: Array)
signal forge_claimed(item: Dictionary)
signal forge_error(error: String)

# Cached forged items from API
var _forged_items: Array = []
var _forged_items_by_id: Dictionary = {}  # item_id -> forged item
var _is_fetching: bool = false
var _is_loaded: bool = false

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
