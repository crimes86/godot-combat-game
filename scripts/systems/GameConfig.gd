extends Node
## GameConfig - Fetches hotfixable balance constants from backend API
##
## This allows balance changes (damage, cooldowns, HP, etc.) without
## redeploying the game server. Values are fetched on startup and cached.
##
## Usage:
##   var damage = GameConfig.get_combat("player_base_damage", 2.0)
##   var duel_timeout = GameConfig.get_duel("request_timeout", 30.0)
##
## Backend endpoint: GET /api/game/config (no auth required)

signal config_ready
signal config_updated

# Cached config from backend
var config: Dictionary = {}
var config_loaded: bool = false
var _http_request: HTTPRequest = null

# Fallback defaults - used if API fails or for values not in remote config
# These MUST match the hardcoded values in the codebase for consistency
const DEFAULTS = {
	"combat": {
		"player_base_damage": 2.0,
		"player_attack_cooldown": 0.70,
		"player_attack_range": 100.0,
		"player_attack_cone_angle": 90.0,
		"crit_damage_multiplier": 1.5,
		"defense_constant": 100.0,
	},
	"weapon_speeds": {
		"very_fast": 0.50,
		"fast": 0.65,
		"medium": 0.80,
		"slow": 0.95,
		"very_slow": 1.10,
	},
	"duel": {
		"request_timeout": 30.0,
		"safe_aura_duration": 10.0,
		"max_distance": 100.0,
		"cancel_distance": 500.0,
		"countdown_duration": 3,
	},
	"pvp_weakpoint": {
		"hp_thresholds": [0.70, 0.35],
		"window_duration": 3.5,
		"damage_per_hit": 3,
		"scale": 0.5,
	},
	"enemies": {
		"base_health": 120.0,
		"health_scaling": 1.12,
		"base_damage": 7.0,
		"damage_scaling": 1.08,
		"respawn_time": 60.0,
	},
	"ttk": {
		"trash_window": 4.0,
		"elite_window": 12.0,
		"boss_window": 45.0,
		"base_window_damage": 25.0,
	},
	"economy": {
		"trade_tax_percent": 5.0,
		"trade_cooldown_hours": 24.0,
	},
	"player": {
		"base_health": 100.0,
		"base_stamina": 100.0,
		"stamina_regen_rate": 15.0,
		"dash_stamina_cost": 25.0,
		"dash_cooldown": 0.5,
		"dash_duration": 0.2,
		"dash_speed": 400.0,
	},
}


func _ready() -> void:
	# Start with defaults
	config = DEFAULTS.duplicate(true)

	# Fetch remote config (non-blocking)
	fetch_config()


func fetch_config() -> void:
	"""Fetch config from backend API. Non-blocking - emits config_ready when done."""
	if _http_request:
		_http_request.queue_free()

	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_config_received)

	var url = _get_api_url()
	var error = _http_request.request(url)

	if error != OK:
		push_warning("[GameConfig] Failed to start config request: %s" % error)
		config_loaded = true
		config_ready.emit()


func _get_api_url() -> String:
	"""Get the config API URL."""
	if AshbaneAuth and AshbaneAuth.has_method("get_api_base"):
		return AshbaneAuth.get_api_base() + "/api/game/config"
	return "https://api.ashbane.net/api/game/config"


func _on_config_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http_request:
		_http_request.queue_free()
		_http_request = null

	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data = json.get_data()
			if data is Dictionary:
				_merge_config(data)
				print("[GameConfig] Loaded %d categories from backend" % data.size())
			else:
				push_warning("[GameConfig] Invalid response format (expected Dictionary)")
		else:
			push_warning("[GameConfig] Failed to parse JSON: %s" % json.get_error_message())
	else:
		push_warning("[GameConfig] API request failed (code: %d, result: %d) - using defaults" % [code, result])

	config_loaded = true
	config_ready.emit()


func _merge_config(remote: Dictionary) -> void:
	"""Deep merge remote config into local config, preserving defaults for missing keys."""
	for category in remote:
		if not remote[category] is Dictionary:
			config[category] = remote[category]
			continue

		# Ensure category exists in config
		if not config.has(category):
			config[category] = {}

		# Merge individual values within category
		for key in remote[category]:
			config[category][key] = remote[category][key]

	config_updated.emit()


func refresh() -> void:
	"""Re-fetch config from backend. Useful for admin commands or periodic refresh."""
	fetch_config()


# ═══════════════════════════════════════════════════════════════════════════
# HELPER GETTERS - Use these instead of accessing config directly
# ═══════════════════════════════════════════════════════════════════════════

func get_combat(key: String, default = null):
	"""Get a combat config value. Example: get_combat('player_base_damage', 2.0)"""
	if default == null and DEFAULTS.get("combat", {}).has(key):
		default = DEFAULTS["combat"][key]
	return config.get("combat", {}).get(key, default)


func get_weapon_speed(speed_class: String) -> float:
	"""Get weapon speed multiplier by class. Example: get_weapon_speed('fast')"""
	return config.get("weapon_speeds", {}).get(speed_class, 0.80)


func get_duel(key: String, default = null):
	"""Get a duel config value. Example: get_duel('request_timeout', 30.0)"""
	if default == null and DEFAULTS.get("duel", {}).has(key):
		default = DEFAULTS["duel"][key]
	return config.get("duel", {}).get(key, default)


func get_pvp_weakpoint(key: String, default = null):
	"""Get a PvP weakpoint config value. Example: get_pvp_weakpoint('damage_per_hit', 3)"""
	if default == null and DEFAULTS.get("pvp_weakpoint", {}).has(key):
		default = DEFAULTS["pvp_weakpoint"][key]
	return config.get("pvp_weakpoint", {}).get(key, default)


func get_enemy(key: String, default = null):
	"""Get an enemy config value. Example: get_enemy('base_health', 120.0)"""
	if default == null and DEFAULTS.get("enemies", {}).has(key):
		default = DEFAULTS["enemies"][key]
	return config.get("enemies", {}).get(key, default)


func get_ttk(key: String, default = null):
	"""Get a TTK (time-to-kill) config value. Example: get_ttk('windows_trash', 2)"""
	if default == null and DEFAULTS.get("ttk", {}).has(key):
		default = DEFAULTS["ttk"][key]
	return config.get("ttk", {}).get(key, default)


func get_economy(key: String, default = null):
	"""Get an economy config value. Example: get_economy('trade_tax_percent', 5.0)"""
	if default == null and DEFAULTS.get("economy", {}).has(key):
		default = DEFAULTS["economy"][key]
	return config.get("economy", {}).get(key, default)


func get_player(key: String, default = null):
	"""Get a player config value. Example: get_player('base_health', 100.0)"""
	if default == null and DEFAULTS.get("player", {}).has(key):
		default = DEFAULTS["player"][key]
	return config.get("player", {}).get(key, default)


func get_raw(category: String, key: String, default = null):
	"""Get any config value by category and key."""
	return config.get(category, {}).get(key, default)


# ═══════════════════════════════════════════════════════════════════════════
# DEBUG / ADMIN
# ═══════════════════════════════════════════════════════════════════════════

func print_config() -> void:
	"""Print current config to console (for debugging)."""
	print("[GameConfig] Current configuration:")
	for category in config:
		print("  %s:" % category)
		if config[category] is Dictionary:
			for key in config[category]:
				print("    %s: %s" % [key, config[category][key]])
		else:
			print("    %s" % config[category])


func get_all() -> Dictionary:
	"""Get the entire config dictionary (for debugging/admin UI)."""
	return config.duplicate(true)
