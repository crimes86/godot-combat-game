extends Node
## TradingManager - Handles trading API calls to Ashbane backend
## Live trading system with chat auctions and proximity-based trades

signal listing_created(listing: Dictionary)
signal listing_cancelled()
signal listings_loaded(listings: Array)
signal trade_completed(trade: Dictionary)
signal trading_error(error: String)

# Cached listings for "Recently Advertised" panel
var _active_listings: Array = []
var _is_fetching_listings: bool = false
var _last_listings_fetch: float = 0.0

# Constants matching backend
const LISTING_REFRESH_INTERVAL: float = 30.0  # Refresh every 30 seconds
const TRADE_PROXIMITY_TILES: float = 5.0  # Must be within 5 tiles to trade
const TILE_SIZE: float = 32.0  # Pixels per tile

func _ready() -> void:
	# Auto-refresh listings periodically
	var timer = Timer.new()
	timer.wait_time = LISTING_REFRESH_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_on_refresh_timer)
	add_child(timer)

func _on_refresh_timer() -> void:
	if AshbaneAuth and AshbaneAuth.is_logged_in():
		fetch_listings()

# ═══════════════════════════════════════════════════════════════════════════════
# CREATE LISTING (/sell command)
# ═══════════════════════════════════════════════════════════════════════════════

func create_listing(token_id: int, price_gold: int, message: String = "") -> void:
	"""Create a trade listing (chat auction) for a forged item"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		trading_error.emit("Not authenticated with Ashbane")
		return

	if price_gold <= 0:
		trading_error.emit("Price must be greater than 0")
		return

	var url = AshbaneAuth.get_api_base() + "/api/trades/listing"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
		"Content-Type: application/json"
	]

	# Get player position for location-based listing
	var position_data = _get_player_position()

	var body_dict = {
		"token_id": token_id,
		"listing_type": "sell",
		"price_gold": price_gold,
		"message": message if message != "" else null,
		"zone_id": position_data.get("zone_id"),
		"position_x": position_data.get("x"),
		"position_y": position_data.get("y")
	}
	var body = JSON.stringify(body_dict)

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_create_listing_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to create listing: %s" % error, "trading")
		trading_error.emit("Failed to connect to server")
		request.queue_free()

func _on_create_listing_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		LogManager.error("Create listing request failed: %d" % result, "trading")
		trading_error.emit("Network error")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		trading_error.emit("Invalid server response")
		return

	var data = json.data

	if response_code == 200:
		LogManager.info("Listing created: %s" % str(data), "trading")
		listing_created.emit(data)
		# Refresh listings to include our new one
		fetch_listings()
	elif response_code == 403:
		trading_error.emit("You don't own this item")
	elif response_code == 404:
		trading_error.emit("Item not found")
	elif response_code == 400:
		var detail = data.get("detail", "Item may be on trade cooldown")
		trading_error.emit(detail)
	else:
		trading_error.emit("Server error: %d" % response_code)

# ═══════════════════════════════════════════════════════════════════════════════
# FETCH LISTINGS (Recently Advertised)
# ═══════════════════════════════════════════════════════════════════════════════

func fetch_listings(zone_id: String = "") -> void:
	"""Fetch active trade listings (Recently Advertised)"""
	if _is_fetching_listings:
		return

	_is_fetching_listings = true
	var url = AshbaneAuth.get_api_base() + "/api/trades/listings"
	if zone_id != "":
		url += "?zone_id=" + zone_id.uri_encode()

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_listings_response.bind(request))

	# Public endpoint - no auth needed
	var error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch listings: %s" % error, "trading")
		_is_fetching_listings = false
		request.queue_free()

func _on_listings_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_is_fetching_listings = false
	_last_listings_fetch = Time.get_unix_time_from_system()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Listings fetch failed: %d / %d" % [result, response_code], "trading")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.data
	_active_listings = data.get("listings", [])
	LogManager.info("Loaded %d active listings" % _active_listings.size(), "trading")
	listings_loaded.emit(_active_listings)

# ═══════════════════════════════════════════════════════════════════════════════
# CANCEL LISTING
# ═══════════════════════════════════════════════════════════════════════════════

func cancel_listing(listing_id: int) -> void:
	"""Cancel an active trade listing"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		trading_error.emit("Not authenticated")
		return

	var url = AshbaneAuth.get_api_base() + "/api/trades/listing/%d" % listing_id
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_cancel_listing_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_DELETE)
	if error != OK:
		LogManager.error("Failed to cancel listing: %s" % error, "trading")
		trading_error.emit("Failed to connect to server")
		request.queue_free()

func _on_cancel_listing_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		trading_error.emit("Network error")
		return

	if response_code == 200:
		LogManager.info("Listing cancelled", "trading")
		listing_cancelled.emit()
		fetch_listings()
	elif response_code == 403:
		trading_error.emit("Not your listing")
	elif response_code == 404:
		trading_error.emit("Listing not found")
	else:
		trading_error.emit("Server error: %d" % response_code)

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK TRADE COOLDOWN
# ═══════════════════════════════════════════════════════════════════════════════

func check_cooldown(token_id: int, callback: Callable) -> void:
	"""Check if an item is on trade cooldown"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		callback.call({"tradeable": false, "error": "Not authenticated"})
		return

	var url = AshbaneAuth.get_api_base() + "/api/trades/cooldown/%d" % token_id
	var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_cooldown_response.bind(request, callback))

	var error = request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		callback.call({"tradeable": false, "error": "Network error"})
		request.queue_free()

func _on_cooldown_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		callback.call({"tradeable": false, "error": "Server error"})
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		callback.call({"tradeable": false, "error": "Invalid response"})
		return

	callback.call(json.data)

# ═══════════════════════════════════════════════════════════════════════════════
# DIRECT TRADE (proximity-based)
# ═══════════════════════════════════════════════════════════════════════════════

func execute_direct_trade(token_id: int, to_user_id: int, price_gold: int) -> void:
	"""Execute a direct trade (Godot validates proximity first)"""
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		trading_error.emit("Not authenticated")
		return

	var url = AshbaneAuth.get_api_base() + "/api/trades/direct"
	var headers = [
		"Authorization: Bearer " + AshbaneAuth.auth_token,
		"Content-Type: application/json"
	]

	var body = JSON.stringify({
		"token_id": token_id,
		"to_user_id": to_user_id,
		"price_gold": price_gold
	})

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_direct_trade_response.bind(request))

	var error = request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		LogManager.error("Failed to execute trade: %s" % error, "trading")
		trading_error.emit("Failed to connect to server")
		request.queue_free()

func _on_direct_trade_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS:
		trading_error.emit("Network error")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		trading_error.emit("Invalid server response")
		return

	var data = json.data

	if response_code == 200:
		LogManager.info("Trade completed: %s" % str(data), "trading")
		trade_completed.emit(data)
		# Refresh forged items to update ownership
		if ForgeItemManager:
			ForgeItemManager.fetch_forged_items()
	elif response_code == 403:
		trading_error.emit("You don't own this item")
	elif response_code == 404:
		var detail = data.get("detail", "Item or recipient not found")
		trading_error.emit(detail)
	elif response_code == 400:
		var detail = data.get("detail", "Trade failed")
		trading_error.emit(detail)
	else:
		trading_error.emit("Server error: %d" % response_code)

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _get_player_position() -> Dictionary:
	"""Get current player position for listing location"""
	var player = get_tree().get_first_node_in_group("player")
	if player:
		return {
			"x": player.global_position.x,
			"y": player.global_position.y,
			"zone_id": "dreadland"  # TODO: Get actual zone from ZoneManager
		}
	return {"x": 0, "y": 0, "zone_id": "dreadland"}

func is_within_trade_distance(target_position: Vector2) -> bool:
	"""Check if player is close enough to trade with target"""
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return false

	var distance = player.global_position.distance_to(target_position)
	var max_distance = TRADE_PROXIMITY_TILES * TILE_SIZE
	return distance <= max_distance

func get_active_listings() -> Array:
	"""Get cached active listings"""
	return _active_listings.duplicate()

func get_listing_count() -> int:
	return _active_listings.size()

# ═══════════════════════════════════════════════════════════════════════════════
# CENSUS (Item supply counts)
# ═══════════════════════════════════════════════════════════════════════════════

signal census_loaded(census: Dictionary)

var _census_data: Dictionary = {}  # item_id -> {total_forged, in_game, first_forged}
var _is_fetching_census: bool = false
var _last_census_fetch: float = 0.0

const CENSUS_REFRESH_INTERVAL: float = 300.0  # Refresh every 5 minutes

func fetch_census() -> void:
	"""Fetch item census (how many of each item exist)"""
	if _is_fetching_census:
		return

	# Don't fetch too often
	var now = Time.get_unix_time_from_system()
	if now - _last_census_fetch < 60.0 and not _census_data.is_empty():
		return

	_is_fetching_census = true
	var url = AshbaneAuth.get_api_base() + "/api/trades/census"

	var request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_census_response.bind(request))

	var error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		LogManager.error("Failed to fetch census: %s" % error, "trading")
		_is_fetching_census = false
		request.queue_free()

func _on_census_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	request.queue_free()
	_is_fetching_census = false
	_last_census_fetch = Time.get_unix_time_from_system()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		LogManager.warning("Census fetch failed: %d / %d" % [result, response_code], "trading")
		return

	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	if parse_result != OK:
		return

	var data = json.data
	var items = data.get("items", [])

	_census_data.clear()
	for item in items:
		var item_id = item.get("item_id", "")
		if item_id != "":
			_census_data[item_id] = {
				"total_forged": item.get("total_forged", 0),
				"in_game": item.get("in_game", 0),
				"first_forged": item.get("first_forged", "")
			}

	LogManager.info("Census loaded: %d item types" % _census_data.size(), "trading")
	census_loaded.emit(_census_data)

func get_census_for_item(item_id: String) -> Dictionary:
	"""Get census data for a specific item"""
	return _census_data.get(item_id, {})

func get_item_count(item_id: String) -> int:
	"""Get total count of a specific item (how many exist)"""
	var census = _census_data.get(item_id, {})
	return census.get("total_forged", 0)

func is_census_loaded() -> bool:
	return not _census_data.is_empty()

# ═══════════════════════════════════════════════════════════════════════════════
# COOLDOWN CACHE
# ═══════════════════════════════════════════════════════════════════════════════

var _cooldown_cache: Dictionary = {}  # token_id -> {tradeable, cooldown_ends, cached_at}

func get_cached_cooldown(token_id: int) -> Dictionary:
	"""Get cached cooldown data if available and fresh (< 60s old)"""
	if token_id in _cooldown_cache:
		var cached = _cooldown_cache[token_id]
		var age = Time.get_unix_time_from_system() - cached.get("cached_at", 0)
		if age < 60.0:
			return cached
	return {}

func cache_cooldown(token_id: int, data: Dictionary) -> void:
	"""Cache cooldown data"""
	data["cached_at"] = Time.get_unix_time_from_system()
	_cooldown_cache[token_id] = data

func check_cooldown_with_cache(token_id: int, callback: Callable) -> void:
	"""Check cooldown with caching - returns cached if fresh, otherwise fetches"""
	var cached = get_cached_cooldown(token_id)
	if not cached.is_empty():
		callback.call(cached)
		return

	# Fetch fresh data
	check_cooldown(token_id, func(data: Dictionary):
		cache_cooldown(token_id, data)
		callback.call(data)
	)
