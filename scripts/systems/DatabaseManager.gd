extends Node
## DatabaseManager - Handles player account storage and authentication
## Uses JSON file storage for simplicity (no external SQLite plugin required)

signal database_ready

const PLAYERS_FILE = "user://players.json"
const SALT_LENGTH = 32

var players_data: Dictionary = {}  # username -> player data
var is_initialized: bool = false

func _ready() -> void:
	# Only initialize on server/host
	pass

func initialize_database() -> bool:
	"""Initialize the database - call this when hosting a game"""
	if is_initialized:
		return true

	# Load existing player data
	if FileAccess.file_exists(PLAYERS_FILE):
		var file = FileAccess.open(PLAYERS_FILE, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			var parse_result = json.parse(json_string)
			if parse_result == OK:
				players_data = json.data
				print("[DatabaseManager] Loaded %d player accounts" % players_data.size())
			else:
				push_error("[DatabaseManager] Failed to parse players file")
				players_data = {}
	else:
		players_data = {}
		print("[DatabaseManager] Created new players database")

	is_initialized = true
	database_ready.emit()
	return true

func save_database() -> bool:
	"""Save all player data to disk"""
	var file = FileAccess.open(PLAYERS_FILE, FileAccess.WRITE)
	if not file:
		push_error("[DatabaseManager] Failed to open players file for writing")
		return false

	var json_string = JSON.stringify(players_data, "\t")
	file.store_string(json_string)
	file.close()
	return true

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
		"strength": 10,
		"agility": 10,
		"vitality": 10,
		"luck": 10,

		# Current state
		"current_hp": 100.0,
		"max_hp": 100.0,
		"position_x": -2000.0,
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
		"is_banned": false
	}

	# Store in database
	players_data[username] = player_data

	# Save to disk
	if save_database():
		print("[DatabaseManager] Created account: %s (ID: %d)" % [username, player_id])
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

	print("[DatabaseManager] Player authenticated: %s" % found_username)

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
		print("[DatabaseManager] Player logged out: %s" % username)

func save_player_data(username: String, data: Dictionary) -> bool:
	"""Save player's current game state"""
	if not players_data.has(username):
		push_error("[DatabaseManager] Cannot save - player not found: %s" % username)
		return false

	# Update allowed fields
	var allowed_fields = [
		"level", "xp", "gold",
		"strength", "agility", "vitality", "luck",
		"current_hp", "max_hp",
		"position_x", "position_y", "current_phase",
		"inventory", "equipment", "appearance",
		"total_playtime_seconds"
	]

	for field in allowed_fields:
		if data.has(field):
			players_data[username][field] = data[field]

	return save_database()

func get_player_data(username: String) -> Dictionary:
	"""Get player data (without sensitive fields)"""
	if not players_data.has(username):
		return {}

	var safe_data = players_data[username].duplicate(true)
	safe_data.erase("password_hash")
	safe_data.erase("salt")
	return safe_data

func reset_all_online_status() -> void:
	"""Reset online status for all players (call on server startup to clean crashed sessions)"""
	for username in players_data.keys():
		players_data[username]["is_online"] = false
	save_database()
	print("[DatabaseManager] Reset online status for all players")

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
		# Reset on successful login
		login_attempts[peer_id].count = 0
	else:
		login_attempts[peer_id].count += 1

func clear_rate_limit(peer_id: int) -> void:
	"""Clear rate limit for a peer (call on disconnect)"""
	login_attempts.erase(peer_id)
