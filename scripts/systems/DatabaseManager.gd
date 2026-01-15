extends Node
## DatabaseManager - Handles player account storage and authentication
## Uses JSON file storage for simplicity (no external SQLite plugin required)
##
## SHARD SUPPORT:
## Each shard stores its data in a separate directory:
##   user://shards/{shard_id}/players.json
##
## Set shard_id BEFORE calling initialize_database():
##   DatabaseManager.set_shard_id("001")
##   DatabaseManager.initialize_database()
##
## Default shard is "default" for backwards compatibility (single-server mode)

signal database_ready
signal player_data_saved(username: String)
signal auto_save_triggered

# ═══════════════════════════════════════════════════════════════════════════
# SHARD CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Shard identifier - set via set_shard_id() before initialize_database()
## Use "default" for single-server mode (backwards compatible)
var shard_id: String = "default"

## Returns the shard-specific players file path
var players_file_path: String:
	get:
		if shard_id == "default":
			# Backwards compatibility: single server uses root user:// directory
			return "user://players.json"
		else:
			return "user://shards/%s/players.json" % shard_id

## Returns the shard data directory
var shard_directory: String:
	get:
		if shard_id == "default":
			return "user://"
		else:
			return "user://shards/%s" % shard_id

const SALT_LENGTH = 32
const AUTO_SAVE_INTERVAL: float = 120.0  # 2 minutes

# Schema validation bounds
const MAX_LEVEL: int = 30
const MAX_GOLD: int = 999999999
const MAX_STAT: int = 999
const MAX_POSITION: float = 50000.0
const MAX_XP: int = 999999999
const MAX_PLAYTIME: int = 999999999  # ~31 years in seconds

var players_data: Dictionary = {}  # username -> player data
var is_initialized: bool = false

# Auto-save system
var auto_save_timer: Timer = null
var current_username: String = ""  # Username of currently logged-in local player

func _ready() -> void:
	# Only initialize on server/host
	pass

# ═══════════════════════════════════════════════════════════════════════════
# SHARD MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func set_shard_id(id: String) -> void:
	"""Set the shard ID. Must be called BEFORE initialize_database().

	Args:
		id: Shard identifier (e.g., "001", "us-west-1", "beta")
			Use "default" for single-server mode (backwards compatible)
	"""
	if is_initialized:
		push_error("[DatabaseManager] Cannot change shard_id after initialization!")
		return

	# Sanitize shard ID (alphanumeric, hyphens, underscores only)
	var sanitized = ""
	for c in id:
		if c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
			sanitized += c

	if sanitized.is_empty():
		push_error("[DatabaseManager] Invalid shard_id: %s" % id)
		return

	shard_id = sanitized
	LogManager.info("[Shard:%s] Shard ID configured" % shard_id, "database")

func get_shard_id() -> String:
	"""Returns the current shard ID."""
	return shard_id

func _ensure_shard_directory() -> bool:
	"""Create shard directory if it doesn't exist. Returns true on success."""
	if shard_id == "default":
		return true  # Default uses user://, always exists

	var dir = DirAccess.open("user://")
	if not dir:
		push_error("[DatabaseManager] Cannot access user:// directory")
		return false

	# Create shards/ directory if needed
	if not dir.dir_exists("shards"):
		var err = dir.make_dir("shards")
		if err != OK:
			push_error("[DatabaseManager] Failed to create shards/ directory: %s" % err)
			return false

	# Create shard-specific directory if needed
	var shard_path = "shards/%s" % shard_id
	if not dir.dir_exists(shard_path):
		var err = dir.make_dir_recursive(shard_path)
		if err != OK:
			push_error("[DatabaseManager] Failed to create shard directory: %s" % shard_path)
			return false
		LogManager.info("[Shard:%s] Created shard directory: %s" % [shard_id, shard_path], "database")

	return true

func initialize_database() -> bool:
	"""Initialize the database - call this when hosting a game.

	For multi-shard setups, call set_shard_id() first:
		DatabaseManager.set_shard_id("001")
		DatabaseManager.initialize_database()
	"""
	if is_initialized:
		return true

	# Ensure shard directory exists
	if not _ensure_shard_directory():
		return false

	var db_path = players_file_path
	LogManager.info("[Shard:%s] Initializing database: %s" % [shard_id, db_path], "database")

	# Load existing player data
	if FileAccess.file_exists(db_path):
		var file = FileAccess.open(db_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			var parse_result = json.parse(json_string)
			if parse_result == OK:
				players_data = json.data
				LogManager.info("[Shard:%s] Loaded %d player accounts" % [shard_id, players_data.size()], "database")
			else:
				push_error("[DatabaseManager] Failed to parse players file")
				players_data = {}
	else:
		players_data = {}
		LogManager.info("[Shard:%s] Created new players database" % shard_id, "database")

	is_initialized = true
	database_ready.emit()
	return true

func save_database() -> bool:
	"""Save all player data to disk (shard-aware)"""
	var db_path = players_file_path
	var file = FileAccess.open(db_path, FileAccess.WRITE)
	if not file:
		push_error("[DatabaseManager] [Shard:%s] Failed to open players file for writing: %s" % [shard_id, db_path])
		return false

	var json_string = JSON.stringify(players_data, "\t")
	file.store_string(json_string)
	file.close()
	return true

# ═══════════════════════════════════════════════════════════════════════════
# SCHEMA VALIDATION
# ═══════════════════════════════════════════════════════════════════════════

func validate_player_data(data: Dictionary) -> Dictionary:
	"""Validate and sanitize player data. Returns sanitized data with valid values."""
	var sanitized = data.duplicate(true)  # Deep copy
	var issues: Array[String] = []

	# Validate level (1-30)
	if sanitized.has("level"):
		var level = sanitized["level"]
		if not (level is int or level is float) or level < 1 or level > MAX_LEVEL:
			issues.append("Invalid level %s, clamping to valid range" % str(level))
			sanitized["level"] = clampi(int(level) if level is int or level is float else 1, 1, MAX_LEVEL)

	# Validate gold (0 - MAX_GOLD)
	if sanitized.has("gold"):
		var gold = sanitized["gold"]
		if not (gold is int or gold is float) or gold < 0 or gold > MAX_GOLD:
			issues.append("Invalid gold %s, clamping to valid range" % str(gold))
			sanitized["gold"] = clampi(int(gold) if gold is int or gold is float else 0, 0, MAX_GOLD)

	# Validate stats (1 - MAX_STAT) - 6-stat system
	for stat_name in ["strength", "agility", "dexterity", "intelligence", "wisdom", "vitality"]:
		if sanitized.has(stat_name):
			var stat = sanitized[stat_name]
			if not (stat is int or stat is float) or stat < 1 or stat > MAX_STAT:
				issues.append("Invalid %s %s, clamping to valid range" % [stat_name, str(stat)])
				sanitized[stat_name] = clampi(int(stat) if stat is int or stat is float else 10, 1, MAX_STAT)

	# Validate position (-MAX_POSITION to MAX_POSITION)
	for pos_name in ["position_x", "position_y"]:
		if sanitized.has(pos_name):
			var pos = sanitized[pos_name]
			if not (pos is int or pos is float) or absf(float(pos)) > MAX_POSITION:
				issues.append("Invalid %s %s, clamping to valid range" % [pos_name, str(pos)])
				sanitized[pos_name] = clampf(float(pos) if pos is int or pos is float else 0.0, -MAX_POSITION, MAX_POSITION)

	# Validate XP (0 - MAX_XP)
	if sanitized.has("xp"):
		var xp = sanitized["xp"]
		if not (xp is int or xp is float) or xp < 0 or xp > MAX_XP:
			issues.append("Invalid xp %s, clamping to valid range" % str(xp))
			sanitized["xp"] = clampi(int(xp) if xp is int or xp is float else 0, 0, MAX_XP)

	# Validate playtime (0 - MAX_PLAYTIME)
	if sanitized.has("total_playtime_seconds"):
		var playtime = sanitized["total_playtime_seconds"]
		if not (playtime is int or playtime is float) or playtime < 0 or playtime > MAX_PLAYTIME:
			issues.append("Invalid playtime %s, clamping to valid range" % str(playtime))
			sanitized["total_playtime_seconds"] = clampi(int(playtime) if playtime is int or playtime is float else 0, 0, MAX_PLAYTIME)

	# Validate HP (0 - reasonable max based on level)
	if sanitized.has("current_hp"):
		var hp = sanitized["current_hp"]
		var max_reasonable_hp = 500.0 + (sanitized.get("level", 1) * 50) + (sanitized.get("vitality", 10) * 20)
		if not (hp is int or hp is float) or hp < 0 or hp > max_reasonable_hp:
			issues.append("Invalid HP %s, clamping to valid range" % str(hp))
			sanitized["current_hp"] = clampf(float(hp) if hp is int or hp is float else max_reasonable_hp, 0, max_reasonable_hp)

	# Validate boolean fields
	for bool_field in ["is_online", "is_banned", "tutorial_completed"]:
		if sanitized.has(bool_field) and not sanitized[bool_field] is bool:
			issues.append("Invalid %s type, converting to bool" % bool_field)
			sanitized[bool_field] = bool(sanitized[bool_field])

	# Log validation issues if any
	if issues.size() > 0:
		push_warning("[DatabaseManager] Data validation issues: %s" % ", ".join(issues))

	return sanitized

func validate_inventory_data(inv_data) -> Variant:
	"""Validate inventory data structure. Returns null if invalid, sanitized data otherwise."""
	if not inv_data is Dictionary:
		push_warning("[DatabaseManager] Invalid inventory data type: %s" % typeof(inv_data))
		return null

	# Check for required structure
	if not inv_data.has("items"):
		push_warning("[DatabaseManager] Inventory missing 'items' array")
		return null

	if not inv_data["items"] is Array:
		push_warning("[DatabaseManager] Inventory 'items' is not an array")
		return null

	# Validate each item has minimum required fields
	var valid_items: Array = []
	for item in inv_data["items"]:
		if item == null:
			valid_items.append(null)  # Empty slot
			continue
		if not item is Dictionary:
			push_warning("[DatabaseManager] Invalid item in inventory, skipping")
			valid_items.append(null)
			continue
		# Item looks valid, keep it
		valid_items.append(item)

	inv_data["items"] = valid_items
	return inv_data


func _validate_weapon_skills(ws_data: Dictionary) -> Dictionary:
	"""Validate weapon skill values - cap based on player level, max 300."""
	var validated = {}
	var valid_categories = [
		"swords", "daggers", "axes", "maces", "hammers",
		"spears", "bows", "healing", "arcane", "guns", "blocking"
	]

	# Calculate skill cap (level * 10, max 300)
	var skill_cap = mini(CharacterStats.level * 10, 300)

	for category in valid_categories:
		if ws_data.has(category):
			var skill_value = ws_data[category]
			if skill_value is float or skill_value is int:
				# Clamp to valid range (0 to cap)
				validated[category] = clampf(float(skill_value), 0.0, float(skill_cap))
			else:
				validated[category] = 0.0
		else:
			validated[category] = 0.0

	return validated


# ═══════════════════════════════════════════════════════════════════════════
# AUTHENTICATION
# ═══════════════════════════════════════════════════════════════════════════

func generate_salt() -> String:
	"""Generate a random salt for password hashing"""
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var salt = ""
	for i in range(SALT_LENGTH):
		salt += chars[randi() % chars.length()]
	return salt

func hash_password(password: String, salt: String) -> String:
	"""Hash password with SHA-256 and salt"""
	var salted = password + salt
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(salted.to_utf8_buffer())
	var hash_bytes = ctx.finish()
	return hash_bytes.hex_encode()

func validate_username(username: String) -> Dictionary:
	"""Validate username format. Returns {valid: bool, error: String}"""
	if username.length() < 3:
		return {"valid": false, "error": "Username must be at least 3 characters"}
	if username.length() > 16:
		return {"valid": false, "error": "Username must be 16 characters or less"}

	# Check alphanumeric + underscore only
	var valid_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	for c in username:
		if c not in valid_chars:
			return {"valid": false, "error": "Username can only contain letters, numbers, and underscores"}

	return {"valid": true, "error": ""}

func validate_password(password: String) -> Dictionary:
	"""Validate password format. Returns {valid: bool, error: String}"""
	if password.length() < 4:
		return {"valid": false, "error": "Password must be at least 4 characters"}
	if password.length() > 64:
		return {"valid": false, "error": "Password must be 64 characters or less"}

	return {"valid": true, "error": ""}

func create_account(username: String, password: String) -> Dictionary:
	"""Create a new player account. Returns {success: bool, error: String, player_id: int}"""
	# Validate username
	var username_check = validate_username(username)
	if not username_check.valid:
		return {"success": false, "error": username_check.error, "player_id": -1}

	# Validate password
	var password_check = validate_password(password)
	if not password_check.valid:
		return {"success": false, "error": password_check.error, "player_id": -1}

	# Check if username already exists (case-insensitive)
	var username_lower = username.to_lower()
	for existing_user in players_data.keys():
		if existing_user.to_lower() == username_lower:
			return {"success": false, "error": "Username already taken", "player_id": -1}

	# Generate salt and hash password
	var salt = generate_salt()
	var password_hash = hash_password(password, salt)

	# Create player data with defaults from schema
	var player_id = Time.get_unix_time_from_system()  # Use timestamp as unique ID
	var now = int(Time.get_unix_time_from_system())

	var player_data = {
		"id": player_id,
		"username": username,
		"password_hash": password_hash,
		"salt": salt,
		"created_at": now,
		"last_login": now,

		# Character data (defaults)
		"character_name": username,
		"gender": "male",
		"level": 1,
		"xp": 0,
		"gold": 100,

		# Stats
		# 6-stat system
		"strength": 10,
		"agility": 10,
		"dexterity": 10,
		"intelligence": 10,
		"wisdom": 10,
		"vitality": 10,

		# Current state
		"current_hp": 100.0,
		"max_hp": 100.0,
		"position_x": 0.0,  # 0,0 = use default spawn point near campfire
		"position_y": 0.0,
		"current_phase": 1,

		# Inventory & Equipment (JSON arrays/objects stored as strings)
		"inventory": [],
		"equipment": {},

		# Appearance (LPC sprite data)
		"appearance": {
			"skin_tone": 0,
			"hair_style": 0,
			"hair_color": 0
		},

		# Playtime tracking
		"total_playtime_seconds": 0,

		# Flags
		"is_online": false,
		"is_banned": false,
		"tutorial_completed": false
	}

	# Store in database
	players_data[username] = player_data

	# Save to disk
	if save_database():
		LogManager.info("Created account: %s (ID: %d)" % [username, player_id], "database")
		return {"success": true, "error": "", "player_id": player_id}
	else:
		# Rollback
		players_data.erase(username)
		return {"success": false, "error": "Failed to save account", "player_id": -1}

func authenticate(username: String, password: String) -> Dictionary:
	"""Authenticate a player. Returns {success: bool, error: String, player_data: Dictionary}"""
	# Find player (case-insensitive username lookup)
	var username_lower = username.to_lower()
	var found_username = ""

	for existing_user in players_data.keys():
		if existing_user.to_lower() == username_lower:
			found_username = existing_user
			break

	if found_username.is_empty():
		return {"success": false, "error": "Invalid username or password", "player_data": {}}

	var player_data = players_data[found_username]

	# Check if banned
	if player_data.get("is_banned", false):
		return {"success": false, "error": "Account is banned", "player_data": {}}

	# Check if already online
	if player_data.get("is_online", false):
		return {"success": false, "error": "Account is already logged in", "player_data": {}}

	# Verify password
	var salt = player_data.get("salt", "")
	var stored_hash = player_data.get("password_hash", "")
	var provided_hash = hash_password(password, salt)

	if provided_hash != stored_hash:
		return {"success": false, "error": "Invalid username or password", "player_data": {}}

	# Update last login
	player_data["last_login"] = int(Time.get_unix_time_from_system())
	player_data["is_online"] = true
	save_database()

	LogManager.info("Player authenticated: %s" % found_username, "database")

	# Return copy without sensitive data
	var safe_data = player_data.duplicate(true)
	safe_data.erase("password_hash")
	safe_data.erase("salt")

	return {"success": true, "error": "", "player_data": safe_data}

func logout_player(username: String) -> void:
	"""Mark player as offline"""
	if players_data.has(username):
		players_data[username]["is_online"] = false
		save_database()
		LogManager.info("Player logged out: %s" % username, "database")

func save_player_data(username: String, data: Dictionary) -> bool:
	"""Save player's current game state"""
	if not players_data.has(username):
		push_error("[DatabaseManager] Cannot save - player not found: %s" % username)
		return false

	# Update allowed fields - 6-stat system
	var allowed_fields = [
		"level", "xp", "gold",
		"strength", "agility", "dexterity", "intelligence", "wisdom", "vitality",
		"current_hp", "max_hp",
		"position_x", "position_y", "current_phase",
		"inventory", "equipment", "appearance",
		"total_playtime_seconds",
		"quests",
		# Full character stats (includes equipped weapon, kill counts, etc.)
		"character_stats",
		# Weapon skill mastery
		"weapon_skills",
		# Equipped weapon ID for restoration on login
		"equipped_weapon",
		# Equipped armor
		"equipped_armor",
		# Duel statistics
		"duel_wins", "duel_losses", "duel_daily_opponents",
		# Allegiance/PvP state
		"allegiance_id", "allegiance_last_change",
		# Open-world PvP statistics
		"pvp_kills", "pvp_kill_credits", "pvp_assists", "pvp_damage_dealt", "pvp_deaths"
	]

	for field in allowed_fields:
		if data.has(field):
			players_data[username][field] = data[field]

	# Debug: log equipped_weapon save
	if data.has("equipped_weapon"):
		print("[DatabaseManager] Saved equipped_weapon for %s: '%s'" % [username, data.get("equipped_weapon", "")])

	return save_database()

func get_player_data(username: String) -> Dictionary:
	"""Get player data (without sensitive fields)"""
	if not players_data.has(username):
		return {}

	var safe_data = players_data[username].duplicate(true)
	safe_data.erase("password_hash")
	safe_data.erase("salt")
	return safe_data

func player_exists(username: String) -> bool:
	"""Check if a player exists in the database"""
	return players_data.has(username)

func reset_all_online_status() -> void:
	"""Reset online status for all players (call on server startup to clean crashed sessions)"""
	for username in players_data.keys():
		players_data[username]["is_online"] = false
	save_database()
	LogManager.info("Reset online status for all players", "database")

# ═══════════════════════════════════════════════════════════════════════════
# DUEL STATISTICS
# ═══════════════════════════════════════════════════════════════════════════

func record_duel_result(winner_username: String, loser_username: String) -> bool:
	"""Record a duel result. Returns true if this was a valid (countable) duel."""
	var today = Time.get_date_string_from_system()

	# Check if winner already dueled loser today (anti-abuse)
	if _has_dueled_today(winner_username, loser_username):
		LogManager.info("Duel not counted (already dueled today): %s vs %s" % [winner_username, loser_username], "duel")
		return false

	# Update winner stats
	if players_data.has(winner_username):
		var winner = players_data[winner_username]
		winner["duel_wins"] = winner.get("duel_wins", 0) + 1
		_add_daily_opponent(winner_username, loser_username, today)

	# Update loser stats
	if players_data.has(loser_username):
		var loser = players_data[loser_username]
		loser["duel_losses"] = loser.get("duel_losses", 0) + 1
		_add_daily_opponent(loser_username, winner_username, today)

	save_database()
	LogManager.info("Duel recorded: %s defeated %s" % [winner_username, loser_username], "duel")
	return true

func _has_dueled_today(username: String, opponent: String) -> bool:
	"""Check if player has already dueled this opponent today"""
	if not players_data.has(username):
		return false

	var today = Time.get_date_string_from_system()
	var daily = players_data[username].get("duel_daily_opponents", {})
	var today_opponents = daily.get(today, [])
	return opponent in today_opponents

func _add_daily_opponent(username: String, opponent: String, today: String) -> void:
	"""Add opponent to today's dueled list and clean up old entries"""
	if not players_data.has(username):
		return

	var player = players_data[username]
	if not player.has("duel_daily_opponents"):
		player["duel_daily_opponents"] = {}

	# Clean up entries older than today
	var daily = player["duel_daily_opponents"]
	var to_remove = []
	for date_key in daily.keys():
		if date_key != today:
			to_remove.append(date_key)
	for old_date in to_remove:
		daily.erase(old_date)

	# Add today's opponent
	if not daily.has(today):
		daily[today] = []
	if opponent not in daily[today]:
		daily[today].append(opponent)

func get_duel_stats(username: String) -> Dictionary:
	"""Get duel statistics for a player"""
	if not players_data.has(username):
		return {"wins": 0, "losses": 0, "win_rate": 0.0}

	var player = players_data[username]
	var wins = player.get("duel_wins", 0)
	var losses = player.get("duel_losses", 0)
	var total = wins + losses
	var win_rate = 0.0
	if total > 0:
		win_rate = float(wins) / float(total) * 100.0

	return {"wins": wins, "losses": losses, "win_rate": win_rate}

# ═══════════════════════════════════════════════════════════════════════════
# OPEN-WORLD PVP STATISTICS
# ═══════════════════════════════════════════════════════════════════════════

func record_pvp_kill(killer_username: String, victim_username: String, damage_dealt: int, is_killing_blow: bool, is_kill_credit: bool) -> void:
	"""Record a PvP kill. Called when a player kills another in open-world PvP.
	is_killing_blow: True if this player dealt the final hit
	is_kill_credit: True if this player dealt the most damage overall"""
	if not players_data.has(killer_username):
		return

	var killer = players_data[killer_username]

	# Always add damage dealt
	killer["pvp_damage_dealt"] = killer.get("pvp_damage_dealt", 0) + damage_dealt

	# Killing blow (final hit)
	if is_killing_blow:
		killer["pvp_kills"] = killer.get("pvp_kills", 0) + 1
		LogManager.info("PVP_KILL %s killed %s (killing blow)" % [killer_username, victim_username], "pvp")

	# Kill credit (most damage)
	if is_kill_credit and not is_killing_blow:
		# Only count as separate credit if not also the killing blow
		killer["pvp_kill_credits"] = killer.get("pvp_kill_credits", 0) + 1
		LogManager.info("PVP_CREDIT %s credited for kill on %s (most damage)" % [killer_username, victim_username], "pvp")

	save_database()

func record_pvp_death(victim_username: String) -> void:
	"""Record a PvP death for the victim"""
	if not players_data.has(victim_username):
		return

	var victim = players_data[victim_username]
	victim["pvp_deaths"] = victim.get("pvp_deaths", 0) + 1
	save_database()
	LogManager.info("PVP_DEATH %s died in PvP" % victim_username, "pvp")

func record_pvp_assist(healer_username: String, killer_username: String) -> void:
	"""Record a PvP assist for a healer whose target got a kill"""
	if not players_data.has(healer_username):
		return

	var healer = players_data[healer_username]
	healer["pvp_assists"] = healer.get("pvp_assists", 0) + 1
	save_database()
	LogManager.info("PVP_ASSIST %s assisted %s's kill" % [healer_username, killer_username], "pvp")

func get_pvp_stats(username: String) -> Dictionary:
	"""Get PvP statistics for a player"""
	if not players_data.has(username):
		return {"kills": 0, "kill_credits": 0, "assists": 0, "damage_dealt": 0, "deaths": 0, "kd_ratio": 0.0}

	var player = players_data[username]
	var kills = player.get("pvp_kills", 0)
	var kill_credits = player.get("pvp_kill_credits", 0)
	var assists = player.get("pvp_assists", 0)
	var damage = player.get("pvp_damage_dealt", 0)
	var deaths = player.get("pvp_deaths", 0)

	var kd_ratio = 0.0
	if deaths > 0:
		kd_ratio = float(kills) / float(deaths)
	elif kills > 0:
		kd_ratio = float(kills)  # Infinite K/D shown as kill count

	return {
		"kills": kills,
		"kill_credits": kill_credits,
		"assists": assists,
		"damage_dealt": damage,
		"deaths": deaths,
		"kd_ratio": kd_ratio
	}

# ═══════════════════════════════════════════════════════════════════════════
# RATE LIMITING (prevent brute force)
# ═══════════════════════════════════════════════════════════════════════════

var login_attempts: Dictionary = {}  # IP/peer_id -> {count: int, last_attempt: int}
const MAX_ATTEMPTS = 5
const LOCKOUT_SECONDS = 60

func check_rate_limit(peer_id: int) -> Dictionary:
	"""Check if peer is rate limited. Returns {allowed: bool, wait_seconds: int}"""
	var now = int(Time.get_unix_time_from_system())

	if not login_attempts.has(peer_id):
		login_attempts[peer_id] = {"count": 0, "last_attempt": now}
		return {"allowed": true, "wait_seconds": 0}

	var attempt_data = login_attempts[peer_id]
	var time_since_last = now - attempt_data.last_attempt

	# Reset if lockout period passed
	if time_since_last >= LOCKOUT_SECONDS:
		login_attempts[peer_id] = {"count": 0, "last_attempt": now}
		return {"allowed": true, "wait_seconds": 0}

	# Check if locked out
	if attempt_data.count >= MAX_ATTEMPTS:
		var wait_time = LOCKOUT_SECONDS - time_since_last
		return {"allowed": false, "wait_seconds": wait_time}

	return {"allowed": true, "wait_seconds": 0}

func record_login_attempt(peer_id: int, success: bool) -> void:
	"""Record a login attempt for rate limiting"""
	var now = int(Time.get_unix_time_from_system())

	if not login_attempts.has(peer_id):
		login_attempts[peer_id] = {"count": 0, "last_attempt": now}

	login_attempts[peer_id].last_attempt = now

	if success:
		# SECURITY FIX: Clear entry entirely on success to prevent memory leak
		login_attempts.erase(peer_id)
	else:
		login_attempts[peer_id].count += 1

func clear_rate_limit(peer_id: int) -> void:
	"""Clear rate limit for a peer (call on disconnect)"""
	login_attempts.erase(peer_id)

# ═══════════════════════════════════════════════════════════════════════════
# AUTO-SAVE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func start_auto_save(username: String) -> void:
	"""Start auto-save timer for the current player session"""
	current_username = username

	if not auto_save_timer:
		auto_save_timer = Timer.new()
		auto_save_timer.name = "AutoSaveTimer"
		auto_save_timer.one_shot = false
		auto_save_timer.timeout.connect(_on_auto_save_timeout)
		add_child(auto_save_timer)

	auto_save_timer.start(AUTO_SAVE_INTERVAL)
	LogManager.info("Auto-save started (every %.0fs) for: %s" % [AUTO_SAVE_INTERVAL, username], "database")

func stop_auto_save() -> void:
	"""Stop auto-save timer"""
	if auto_save_timer:
		auto_save_timer.stop()

	# Final save before stopping
	if current_username != "":
		LogManager.info("Final save before stopping auto-save for: %s" % current_username, "database")
		save_current_player_state()

	current_username = ""

func _on_auto_save_timeout() -> void:
	"""Called every AUTO_SAVE_INTERVAL seconds"""
	if current_username != "":
		# Check if we're a client - sync to server instead of local save
		if NetworkManager and NetworkManager.is_authenticated and not NetworkManager.is_host and not NetworkManager.is_guest:
			# Client: sync state to server for persistence
			NetworkManager.client_sync_state()
			auto_save_triggered.emit()
			LogManager.debug("Synced state to server", "database")

			# Also sync to backend (authoritative persistent save)
			if CharacterStats:
				CharacterStats.sync_to_backend()
		else:
			# Host or single player: save locally
			LogManager.debug("Auto-save triggered...", "database")
			if save_current_player_state():
				auto_save_triggered.emit()

func save_current_player_state() -> bool:
	"""Save the current player's full game state using serialization from systems"""
	if current_username.is_empty():
		push_warning("[DatabaseManager] Cannot save - no current user")
		return false

	if not players_data.has(current_username):
		push_error("[DatabaseManager] Cannot save - player not found: %s" % current_username)
		return false

	# Get current player node for position
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)

	# Build save data from systems
	var save_data = {}

	# Position (from player node)
	if player and is_instance_valid(player):
		save_data["position_x"] = player.global_position.x
		save_data["position_y"] = player.global_position.y
		save_data["current_hp"] = player.current_health if player.has_method("get") else player.get("current_health")

	# Character stats (level, xp, gold, attributes, equipment, kills, achievements, playtime)
	# 6-stat system: STR, AGI, DEX, INT, WIS, VIT
	var stats_data = CharacterStats.get_save_data()
	save_data["level"] = stats_data.get("level", 1)
	save_data["xp"] = stats_data.get("experience", 0)
	save_data["gold"] = stats_data.get("gold", 0)
	save_data["strength"] = stats_data.get("strength", 10)
	save_data["agility"] = stats_data.get("agility", 10)
	save_data["dexterity"] = stats_data.get("dexterity", 10)
	save_data["intelligence"] = stats_data.get("intelligence", 10)
	save_data["wisdom"] = stats_data.get("wisdom", 10)
	save_data["vitality"] = stats_data.get("vitality", 10)
	save_data["character_stats"] = JSON.stringify(stats_data)  # Full blob for complex data

	# Inventory
	var inv_data = InventorySystem.get_save_data()
	save_data["inventory"] = JSON.stringify(inv_data)

	# Locally deleted forged items (prevents re-sync of items user deleted)
	if ForgeItemManager:
		var deleted_items = ForgeItemManager.get_locally_deleted_items()
		if deleted_items.size() > 0:
			save_data["deleted_forged_items"] = JSON.stringify(deleted_items)

	# Playtime
	save_data["total_playtime_seconds"] = stats_data.get("total_playtime", 0)

	# Update database entry
	for key in save_data:
		players_data[current_username][key] = save_data[key]

	# Save to disk
	if save_database():
		player_data_saved.emit(current_username)
		LogManager.debug("Saved player state: %s (Level %d, Gold %d)" % [
			current_username,
			save_data.get("level", 1),
			save_data.get("gold", 0)
		], "database")
		return true

	return false

func apply_player_data_to_systems(username: String, player: Node = null) -> void:
	"""Load saved data and apply it to game systems (InventorySystem, CharacterStats, player position)"""
	print("[DatabaseManager] apply_player_data_to_systems called for user: '%s', player valid: %s" % [username, player != null])

	# Create default player entry if it doesn't exist (for new Ashbane-authenticated users)
	if not players_data.has(username):
		print("[DatabaseManager] Creating new player entry for: %s" % username)
		players_data[username] = {
			"username": username,
			"tutorial_completed": false,
			"created_at": Time.get_unix_time_from_system(),
			"inventory": "",
			"character_stats": "",
			"position_x": 0.0,
			"position_y": 0.0
		}
		save_database()

	# Validate and sanitize player data before applying
	var raw_data = players_data[username]
	var data = validate_player_data(raw_data)

	# Update stored data with sanitized version if different
	if data != raw_data:
		players_data[username] = data
		LogManager.info("Sanitized data for: %s" % username, "database")

	# Apply inventory (with validation)
	# SKIP if authenticated user already loaded inventory from backend (prevents duplicates)
	var backend_already_loaded = AshbaneAuth and AshbaneAuth.is_authenticated and InventorySystem.get_item_count() > 0
	if backend_already_loaded:
		LogManager.info("Skipping local inventory load - already loaded %d items from backend" % InventorySystem.get_item_count(), "inventory")
	else:
		var inv_json = data.get("inventory", "")
		if inv_json is String and not inv_json.is_empty():
			var inv_data = JSON.parse_string(inv_json)
			if inv_data:
				var validated_inv = validate_inventory_data(inv_data)
				if validated_inv:
					InventorySystem.load_save_data(validated_inv)
					LogManager.debug("Loaded inventory for: %s" % username, "inventory")
				else:
					push_warning("[DatabaseManager] Invalid inventory data for: %s, starting fresh" % username)

	# Load locally deleted forged items BEFORE sync (prevents re-sync of deleted items)
	var deleted_json = data.get("deleted_forged_items", "")
	if deleted_json is String and not deleted_json.is_empty():
		var deleted_data = JSON.parse_string(deleted_json)
		if deleted_data and deleted_data is Dictionary:
			if ForgeItemManager:
				ForgeItemManager.set_locally_deleted_items(deleted_data)
				LogManager.info("Loaded %d locally deleted forged items" % deleted_data.size(), "forge")

	# Sync forged items to inventory AFTER loading saved inventory
	# This merges any forged items that aren't already in the save
	if ForgeItemManager and ForgeItemManager.is_loaded():
		var synced = ForgeItemManager.sync_to_inventory()
		if synced > 0:
			LogManager.info("Synced %d forged items to inventory after load" % synced, "forge")

	# Cleanup any corrupted items with nested {"item": {...}} structure
	var cleaned = InventorySystem.cleanup_corrupted_items()
	if cleaned > 0:
		LogManager.info("Cleaned up %d corrupted inventory items" % cleaned, "inventory")

	# Restore equipped weapon from saved data
	# Can be either:
	# - String ID (from backend API): forged_id or weapon name
	# - Dictionary (from server local JSON): full weapon data from CharacterStats.get_save_data()
	var equipped_weapon_value = data.get("equipped_weapon", "")
	print("[DatabaseManager] Checking equipped_weapon in data: '%s' (type: %s)" % [str(equipped_weapon_value).substr(0, 100), typeof(equipped_weapon_value)])

	if equipped_weapon_value is String and not equipped_weapon_value.is_empty():
		# String ID - use the restoration function
		_restore_equipped_weapon(equipped_weapon_value)
	elif equipped_weapon_value is Dictionary and not equipped_weapon_value.is_empty():
		# Dictionary from server - can directly restore via CharacterStats
		print("[DatabaseManager] Restoring equipped_weapon from dictionary data")
		_restore_equipped_weapon_from_dict(equipped_weapon_value, data.get("equipped_weapon_data", {}))
	else:
		print("[DatabaseManager] No equipped_weapon to restore (empty or wrong type)")

	# Apply character stats (full blob first, then individual fields as fallback)
	# IMPORTANT: For Ashbane-authenticated users, the backend is authoritative for level/XP/gold.
	# Skip local stats load entirely - backend values were already set in Armory._load_character_from_backend()
	var backend_is_authoritative = AshbaneAuth and AshbaneAuth.is_authenticated
	if backend_is_authoritative:
		LogManager.info("Skipping local stats load - backend is authoritative (level=%d, gold=%d, xp=%d)" % [CharacterStats.level, CharacterStats.gold, CharacterStats.experience], "database")

		# However, if backend didn't have quests, try loading from local save as fallback
		# This handles the transition period where user hasn't logged out with new code yet
		var has_backend_quests = QuestManager and not QuestManager.quest_states.is_empty()
		if not has_backend_quests:
			var stats_json = data.get("character_stats", "")
			if stats_json is String and not stats_json.is_empty():
				var stats_data = JSON.parse_string(stats_json)
				if stats_data and stats_data.has("quests") and not stats_data.get("quests", {}).is_empty():
					QuestManager.load_save_data(stats_data.get("quests", {}))
					LogManager.info("Loaded quest progress from local save (backend had none)", "database")
	else:
		var stats_json = data.get("character_stats", "")
		if stats_json is String and not stats_json.is_empty():
			var stats_data = JSON.parse_string(stats_json)
			if stats_data:
				CharacterStats.load_save_data(stats_data)
				LogManager.debug("Loaded character stats for: %s" % username, "database")
		else:
			# Fallback: load individual fields if full blob not available (already validated)
			# 6-stat system: STR, AGI, DEX, INT, WIS, VIT
			var fallback_stats = {
				"level": data.get("level", 1),
				"experience": data.get("xp", 0),
				"gold": data.get("gold", 100),
				"strength": data.get("strength", 10),
				"agility": data.get("agility", 10),
				"dexterity": data.get("dexterity", 10),
				"intelligence": data.get("intelligence", 10),
				"wisdom": data.get("wisdom", 10),
				"vitality": data.get("vitality", 10),
				"total_playtime": data.get("total_playtime_seconds", 0)
			}
			CharacterStats.load_save_data(fallback_stats)

	# Load weapon skills
	var ws_json = data.get("weapon_skills", "")
	if ws_json is String and not ws_json.is_empty():
		var ws_data = JSON.parse_string(ws_json)
		if ws_data and ws_data is Dictionary and WeaponSkillManager:
			# Validate skill values against cap before loading
			var validated_ws = _validate_weapon_skills(ws_data)
			WeaponSkillManager.load_save_data({"weapon_skills": validated_ws})
			LogManager.debug("Loaded weapon skills for: %s" % username, "database")

	# NOTE: Position is NOT restored here - game_world.gd handles spawn position correctly
	# before calling this function (it uses hub return position or saved position as appropriate)

	# Apply HP and other player state if player node is valid
	if player and is_instance_valid(player):
		# Apply HP if player has health
		var saved_hp = data.get("current_hp", -1)
		if saved_hp > 0 and player.has_method("set_health"):
			player.set_health(saved_hp)
		elif saved_hp > 0 and "current_health" in player:
			player.current_health = saved_hp

		# Refresh player sprite to show loaded equipment
		if player.has_method("create_player_sprite"):
			LogManager.debug("Refreshing player sprite with loaded equipment", "player")
			player.create_player_sprite()

		# Refresh player stats (attack speed, damage, etc.) from loaded equipment
		if player.has_method("update_stats_from_character"):
			LogManager.debug("Refreshing player stats with loaded equipment", "player")
			player.update_stats_from_character()

	LogManager.info("Applied saved data for: %s" % username, "database")

func get_saved_position(username: String) -> Vector2:
	"""Get saved position for a player (for spawn location)"""
	if not players_data.has(username):
		return Vector2.ZERO

	var data = players_data[username]
	var pos_x = data.get("position_x", 0.0)
	var pos_y = data.get("position_y", 0.0)
	return Vector2(pos_x, pos_y)

# ═══════════════════════════════════════════════════════════════════════════
# INVENTORY SAVE (for Armory)
# ═══════════════════════════════════════════════════════════════════════════

func save_inventory_for_user(username: String) -> bool:
	"""Save just the inventory for a specific user (used by Armory before entering game)"""
	if username.is_empty():
		push_warning("[DatabaseManager] Cannot save inventory - no username")
		return false

	if not players_data.has(username):
		push_warning("[DatabaseManager] Cannot save inventory - user not found: %s" % username)
		return false

	# Get inventory data and save
	var inv_data = InventorySystem.get_save_data()
	players_data[username]["inventory"] = JSON.stringify(inv_data)

	if save_database():
		LogManager.info("Saved inventory for: %s (%d items)" % [username, inv_data.get("items", []).size()], "database")
		return true

	return false

func save_character_stats_for_user(username: String) -> bool:
	"""Save character stats (equipment, level, etc.) for a specific user"""
	if username.is_empty():
		push_warning("[DatabaseManager] Cannot save character stats - no username")
		return false

	if not players_data.has(username):
		push_warning("[DatabaseManager] Cannot save character stats - user not found: %s" % username)
		return false

	# Get character stats data and save
	var stats_data = CharacterStats.get_save_data()
	players_data[username]["character_stats"] = JSON.stringify(stats_data)

	if save_database():
		LogManager.info("Saved character stats for: %s (level %d)" % [username, stats_data.get("level", 1)], "database")
		return true

	return false

func save_all_player_data_for_user(username: String) -> bool:
	"""Save both inventory and character stats for a user (use when transitioning from Armory to game)"""
	if username.is_empty():
		push_warning("[DatabaseManager] Cannot save player data - no username")
		return false

	if not players_data.has(username):
		push_warning("[DatabaseManager] Cannot save player data - user not found: %s" % username)
		return false

	# Save inventory
	var inv_data = InventorySystem.get_save_data()
	players_data[username]["inventory"] = JSON.stringify(inv_data)

	# Save character stats (includes equipped weapon, armor, level, gold, etc.)
	var stats_data = CharacterStats.get_save_data()
	players_data[username]["character_stats"] = JSON.stringify(stats_data)

	if save_database():
		LogManager.info("Saved all player data for: %s (level %d, %d items)" % [
			username,
			stats_data.get("level", 1),
			inv_data.get("items", []).size()
		], "database")
		return true

	return false


# ═══════════════════════════════════════════════════════════════════════════
# EQUIPPED WEAPON RESTORATION
# ═══════════════════════════════════════════════════════════════════════════

func _restore_equipped_weapon(weapon_id: String) -> void:
	"""Restore equipped weapon from saved ID after inventory is loaded.
	The backend saves equipped_weapon as a string ID (forged_id or weapon name).
	We need to find the weapon in ForgeItemDB (for forged items) or inventory."""
	if weapon_id.is_empty():
		return

	print("[DatabaseManager] Restoring equipped weapon: %s" % weapon_id)

	var weapon_item: Dictionary = {}

	# FIRST: Check ForgeItemDB for forged items (they may not be in inventory because equipping removes them)
	var forge_item_db = Engine.get_singleton("ForgeItemDB") if Engine.has_singleton("ForgeItemDB") else null
	if forge_item_db == null and has_node("/root/ForgeItemDB"):
		forge_item_db = get_node("/root/ForgeItemDB")

	if forge_item_db:
		var forge_data = forge_item_db.get_item_by_id(weapon_id)
		if not forge_data.is_empty():
			print("[DatabaseManager] Found forged weapon in ForgeItemDB: %s" % forge_data.get("item_name", weapon_id))
			# Check if user owns this forged item via ForgeItemManager
			var forge_manager = Engine.get_singleton("ForgeItemManager") if Engine.has_singleton("ForgeItemManager") else null
			if forge_manager == null and has_node("/root/ForgeItemManager"):
				forge_manager = get_node("/root/ForgeItemManager")

			if forge_manager and forge_manager.has_method("get_forged_item"):
				var owned_item = forge_manager.get_forged_item(weapon_id)
				if not owned_item.is_empty():
					print("[DatabaseManager] User owns forged weapon: %s" % weapon_id)
					# Convert forged item to inventory format
					if forge_manager.has_method("_convert_to_inventory_format"):
						weapon_item = forge_manager._convert_to_inventory_format(owned_item)
					else:
						# Manual conversion fallback
						weapon_item = _convert_forge_data_to_weapon_item(forge_data, owned_item)
				else:
					# ForgeItemManager doesn't have it (playtest items, etc) - use ForgeItemDB data directly
					print("[DatabaseManager] ForgeItemManager doesn't have '%s' - using ForgeItemDB data" % weapon_id)
					weapon_item = _convert_forge_data_to_weapon_item(forge_data, {})
			else:
				# No ForgeItemManager - try manual conversion from ForgeItemDB data
				weapon_item = _convert_forge_data_to_weapon_item(forge_data, {})
				print("[DatabaseManager] Converted ForgeItemDB data to weapon_item for: %s" % weapon_id)

	# SECOND: If not found in ForgeItemDB, search inventory (for regular weapons)
	if weapon_item.is_empty():
		weapon_item = InventorySystem.find_weapon_by_id(weapon_id)

	if weapon_item.is_empty():
		print("[DatabaseManager] Could not find weapon '%s' in ForgeItemDB or inventory" % weapon_id)
		return

	# Create Weapon resource from item data
	var Weapon = load("res://scripts/resources/Weapon.gd")
	var weapon = Weapon.new()
	weapon.weapon_name = weapon_item.get("name", "Unknown")
	weapon.weapon_type = weapon_item.get("weapon_type", "sword")

	# Handle base_damage - can be a number or a Dictionary with min/max
	var base_damage = weapon_item.get("base_damage", 5.0)
	if base_damage is Dictionary:
		var dmg_min = base_damage.get("min", 5)
		var dmg_max = base_damage.get("max", 5)
		weapon.base_damage = (dmg_min + dmg_max) / 2.0
	elif base_damage is float or base_damage is int:
		weapon.base_damage = float(base_damage)
	else:
		weapon.base_damage = 5.0

	weapon.required_level = weapon_item.get("required_level", 1)
	weapon.description = weapon_item.get("description", "")
	weapon.can_trade = weapon_item.get("can_trade", true)

	# Handle attack speed (convert string to bonus)
	var speed = weapon_item.get("attack_speed", "medium")
	if speed is String:
		match speed.to_lower():
			"very_fast":
				weapon.attack_speed_bonus = -0.3
			"fast":
				weapon.attack_speed_bonus = -0.2
			"slow":
				weapon.attack_speed_bonus = 0.2
			"very_slow":
				weapon.attack_speed_bonus = 0.3
			_:
				weapon.attack_speed_bonus = 0.0
	elif speed is float or speed is int:
		weapon.attack_speed_bonus = float(speed)

	# Handle crit chance
	weapon.crit_chance_bonus = weapon_item.get("crit_chance", weapon_item.get("crit_chance_bonus", 0.0))

	# Handle rarity (convert string to enum)
	var rarity_str = weapon_item.get("rarity", "Common")
	if rarity_str is String:
		match rarity_str.to_lower():
			"common":
				weapon.rarity = 0
			"uncommon":
				weapon.rarity = 1
			"rare":
				weapon.rarity = 2
			"epic":
				weapon.rarity = 3
			"legendary":
				weapon.rarity = 4
			"artifact":
				weapon.rarity = 5
			_:
				weapon.rarity = 0
	elif rarity_str is int:
		weapon.rarity = rarity_str

	# Gun weapon properties
	weapon.gun_radius = weapon_item.get("gun_radius", 28.0)
	weapon.gun_range = weapon_item.get("gun_range", 550.0)
	weapon.gun_subtype = weapon_item.get("gun_subtype", "railgun")
	weapon.burst_count = weapon_item.get("burst_count", 1)
	weapon.burst_delay = weapon_item.get("burst_delay", 0.10)

	# Healing weapon properties
	weapon.attack_mode = weapon_item.get("attack_mode", "melee")
	weapon.healing_power = weapon_item.get("healing_power", 0.0)
	weapon.heal_radius = weapon_item.get("heal_radius", 80.0)

	# Two-handed property
	var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
	weapon.is_two_handed = weapon_item.get("is_two_handed", is_two_handed_type)

	# Forged weapon properties
	weapon.is_forged = weapon_item.get("is_forged", false)
	weapon.forged_id = weapon_item.get("forged_id", weapon_item.get("item_id", ""))

	# Equip the weapon
	CharacterStats.equip_weapon(weapon, weapon_item)
	print("[DatabaseManager] Successfully equipped weapon: %s (forged=%s)" % [weapon.weapon_name, weapon.is_forged])


func _restore_equipped_weapon_from_dict(weapon_data: Dictionary, weapon_item_data: Dictionary) -> void:
	"""Restore equipped weapon from dictionary data (from CharacterStats.get_save_data()).
	This handles the case where the server stores the full weapon dict instead of just the ID."""
	if weapon_data.is_empty():
		print("[DatabaseManager] Empty weapon_data dict - nothing to restore")
		return

	# weapon_data comes from CharacterStats.get_save_data()["equipped_weapon"]
	# It has format: weapon_name, weapon_type, base_damage, attack_speed_bonus, etc.
	var weapon_name = weapon_data.get("weapon_name", "")
	if weapon_name.is_empty():
		print("[DatabaseManager] No weapon_name in dict - nothing to restore")
		return

	print("[DatabaseManager] Restoring equipped weapon from dict: %s" % weapon_name)

	# Create Weapon resource
	var Weapon = load("res://scripts/resources/Weapon.gd")
	var weapon = Weapon.new()
	weapon.weapon_name = weapon_name
	weapon.weapon_type = weapon_data.get("weapon_type", "sword")
	weapon.base_damage = float(weapon_data.get("base_damage", 5.0))
	weapon.attack_speed_bonus = float(weapon_data.get("attack_speed_bonus", 0.0))
	weapon.crit_chance_bonus = float(weapon_data.get("crit_chance_bonus", 0.0))
	weapon.required_level = weapon_data.get("required_level", 1)
	weapon.description = weapon_data.get("description", "")
	weapon.can_trade = weapon_data.get("can_trade", true)

	# Rarity is stored as int enum value
	var rarity = weapon_data.get("rarity", 0)
	if rarity is int:
		weapon.rarity = rarity
	elif rarity is String:
		match rarity.to_lower():
			"common": weapon.rarity = 0
			"uncommon": weapon.rarity = 1
			"rare": weapon.rarity = 2
			"epic": weapon.rarity = 3
			"legendary": weapon.rarity = 4
			"artifact": weapon.rarity = 5
			_: weapon.rarity = 0

	# Gun weapon properties
	weapon.gun_radius = weapon_data.get("gun_radius", 28.0)
	weapon.gun_range = weapon_data.get("gun_range", 550.0)
	weapon.gun_subtype = weapon_data.get("gun_subtype", "railgun")
	weapon.burst_count = weapon_data.get("burst_count", 1)
	weapon.burst_delay = weapon_data.get("burst_delay", 0.10)

	# Healing weapon properties
	weapon.attack_mode = weapon_data.get("attack_mode", "melee")
	weapon.healing_power = weapon_data.get("healing_power", 0.0)
	weapon.heal_radius = weapon_data.get("heal_radius", 80.0)

	# Two-handed property
	var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
	weapon.is_two_handed = weapon_data.get("is_two_handed", is_two_handed_type)

	# Forged weapon properties
	weapon.is_forged = weapon_data.get("is_forged", false)
	weapon.forged_id = weapon_data.get("forged_id", "")

	# Use weapon_item_data (the original inventory item dict) if available, otherwise convert weapon_data to item format
	var item_data: Dictionary = {}
	if not weapon_item_data.is_empty():
		item_data = weapon_item_data.duplicate(true)
	else:
		# Convert weapon_data format to inventory item format
		item_data = {
			"name": weapon_name,
			"type": "weapon",
			"slot": "mainhand",
			"weapon_type": weapon.weapon_type,
			"base_damage": weapon.base_damage,
			"attack_speed_bonus": weapon.attack_speed_bonus,
			"crit_chance_bonus": weapon.crit_chance_bonus,
			"required_level": weapon.required_level,
			"description": weapon.description,
			"can_trade": weapon.can_trade,
			"is_forged": weapon.is_forged,
			"forged_id": weapon.forged_id,
			"item_id": weapon.forged_id,
			"forged_item_id": weapon.forged_id
		}
		# Add gun properties if applicable
		if weapon.is_gun_weapon():
			item_data["gun_radius"] = weapon.gun_radius
			item_data["gun_range"] = weapon.gun_range
			item_data["gun_subtype"] = weapon.gun_subtype
			item_data["burst_count"] = weapon.burst_count
			item_data["burst_delay"] = weapon.burst_delay

	# Equip the weapon
	CharacterStats.equip_weapon(weapon, item_data)
	print("[DatabaseManager] Successfully equipped weapon from dict: %s (forged=%s)" % [weapon.weapon_name, weapon.is_forged])


func _convert_forge_data_to_weapon_item(forge_db_data: Dictionary, owned_data: Dictionary) -> Dictionary:
	"""Convert ForgeItemDB data + owned item data to inventory item format for weapons."""
	var item_id = forge_db_data.get("item_id", "")
	var item_name = forge_db_data.get("item_name", "Unknown Weapon")
	var weapon_type = forge_db_data.get("weapon_type", "sword")
	var rarity = forge_db_data.get("rarity", 0)

	# Map rarity enum to string
	var rarity_names = ["common", "uncommon", "rare", "epic", "legendary", "artifact"]
	var rarity_str = rarity_names[rarity] if rarity >= 0 and rarity < rarity_names.size() else "common"

	# Get damage from forge_db_data or default
	var base_damage = forge_db_data.get("base_damage", 5.0)
	if base_damage is Dictionary:
		var dmg_min = base_damage.get("min", 5)
		var dmg_max = base_damage.get("max", 5)
		base_damage = (dmg_min + dmg_max) / 2.0

	var weapon_item = {
		"name": item_name,
		"type": "weapon",
		"slot": "mainhand",
		"weapon_type": weapon_type,
		"base_damage": base_damage,
		"attack_speed": "medium",
		"crit_chance": 0.0,
		"rarity": rarity_str,
		"required_level": 1,
		"description": forge_db_data.get("description", ""),
		"can_trade": true,
		"stackable": false,
		"quantity": 1,
		"is_forged": true,
		"forged_id": item_id,
		"item_id": item_id,
		"forged_item_id": item_id
	}

	# Add gun weapon properties if it's a gun
	if weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"]:
		weapon_item["gun_radius"] = forge_db_data.get("gun_radius", 28.0)
		weapon_item["gun_range"] = forge_db_data.get("gun_range", 550.0)
		weapon_item["gun_subtype"] = forge_db_data.get("gun_subtype", "railgun")
		weapon_item["burst_count"] = forge_db_data.get("burst_count", 1)
		weapon_item["burst_delay"] = forge_db_data.get("burst_delay", 0.10)
		weapon_item["is_two_handed"] = true

	# Add visuals from forge_db_data
	var visuals = forge_db_data.get("visuals", {})
	if not visuals.is_empty():
		weapon_item["glow_color"] = visuals.get("glow_color", "")
		weapon_item["effect_name"] = visuals.get("effect", "")

	weapon_item["theme"] = forge_db_data.get("theme", "")
	weapon_item["sprites"] = forge_db_data.get("sprites", {})

	# Merge any owned_data fields
	if not owned_data.is_empty():
		weapon_item["id"] = owned_data.get("id", 0)
		weapon_item["item_rarity"] = owned_data.get("item_rarity", rarity_str)

	return weapon_item


# ═══════════════════════════════════════════════════════════════════════════
# TUTORIAL TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func has_completed_tutorial(username: String = "") -> bool:
	"""Check if player has completed the tutorial"""
	var user = username if not username.is_empty() else current_username
	print("[DatabaseManager] has_completed_tutorial check for user: '%s' (arg: '%s')" % [user, username])
	if user.is_empty():
		print("[DatabaseManager] has_completed_tutorial: user is empty, returning false")
		return false
	if not players_data.has(user):
		print("[DatabaseManager] has_completed_tutorial: user '%s' not in players_data, returning false" % user)
		return false
	var completed = players_data[user].get("tutorial_completed", false)
	print("[DatabaseManager] has_completed_tutorial: user '%s' tutorial_completed = %s" % [user, completed])
	return completed

func set_tutorial_completed(username: String = "") -> void:
	"""Mark tutorial as completed for a player"""
	var user = username if not username.is_empty() else current_username
	print("[DatabaseManager] set_tutorial_completed called - username arg: '%s', current_username: '%s', resolved user: '%s'" % [username, current_username, user])

	if user.is_empty():
		print("[DatabaseManager] ERROR: Cannot set tutorial complete - user is empty!")
		return

	# Create player entry if it doesn't exist (for Ashbane-authenticated users)
	if not players_data.has(user):
		print("[DatabaseManager] Creating new player entry for user '%s'" % user)
		players_data[user] = {
			"username": user,
			"tutorial_completed": false,
			"created_at": Time.get_unix_time_from_system()
		}

	players_data[user]["tutorial_completed"] = true
	print("[DatabaseManager] Set tutorial_completed=true for user '%s'" % user)
	save_database()
	LogManager.info("Tutorial completed for: %s" % user, "tutorial")
