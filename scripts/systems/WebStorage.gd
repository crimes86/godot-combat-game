extends Node
class_name WebStorage

## Cross-platform storage utility that works on both desktop and web
##
## Desktop: Uses Godot's user:// file system
## Web: Uses browser's LocalStorage via JavaScriptBridge
##
## Usage:
##   WebStorage.save_string("session_token", "abc123")
##   var token = WebStorage.load_string("session_token", "")
##   WebStorage.save_json("settings", {"volume": 0.8, "fullscreen": true})
##   var settings = WebStorage.load_json("settings", {})

const STORAGE_PREFIX = "ashbane_"  # Prefix for all keys to avoid collisions

static func is_web() -> bool:
	"""Check if running in a web browser."""
	return OS.has_feature("web")

# ═══════════════════════════════════════════════════════════════════════════
# STRING STORAGE
# ═══════════════════════════════════════════════════════════════════════════

static func save_string(key: String, value: String) -> bool:
	"""Save a string value. Returns true on success."""
	var prefixed_key = STORAGE_PREFIX + key

	if is_web():
		# Web: Use localStorage
		var escaped_value = value.c_escape()
		var js_code = "localStorage.setItem('%s', '%s')" % [prefixed_key, escaped_value]
		JavaScriptBridge.eval(js_code)
		return true
	else:
		# Desktop: Use file system
		var file = FileAccess.open("user://%s.dat" % key, FileAccess.WRITE)
		if file:
			file.store_string(value)
			file.close()
			return true
		return false

static func load_string(key: String, default: String = "") -> String:
	"""Load a string value. Returns default if not found."""
	var prefixed_key = STORAGE_PREFIX + key

	if is_web():
		# Web: Use localStorage
		var js_code = "localStorage.getItem('%s')" % prefixed_key
		var result = JavaScriptBridge.eval(js_code)
		if result == null or result == "null":
			return default
		return str(result).c_unescape()
	else:
		# Desktop: Use file system
		var path = "user://%s.dat" % key
		if not FileAccess.file_exists(path):
			return default
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			return content
		return default

static func delete_string(key: String) -> void:
	"""Delete a stored string value."""
	var prefixed_key = STORAGE_PREFIX + key

	if is_web():
		JavaScriptBridge.eval("localStorage.removeItem('%s')" % prefixed_key)
	else:
		var path = "user://%s.dat" % key
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func has_key(key: String) -> bool:
	"""Check if a key exists in storage."""
	var prefixed_key = STORAGE_PREFIX + key

	if is_web():
		var result = JavaScriptBridge.eval("localStorage.getItem('%s') !== null" % prefixed_key)
		return result == true
	else:
		return FileAccess.file_exists("user://%s.dat" % key)

# ═══════════════════════════════════════════════════════════════════════════
# JSON STORAGE
# ═══════════════════════════════════════════════════════════════════════════

static func save_json(key: String, data: Variant) -> bool:
	"""Save a JSON-serializable value (Dictionary, Array, etc.)."""
	var json_string = JSON.stringify(data)
	return save_string(key, json_string)

static func load_json(key: String, default: Variant = null) -> Variant:
	"""Load a JSON value. Returns default if not found or invalid."""
	var json_string = load_string(key, "")
	if json_string.is_empty():
		return default

	var result = JSON.parse_string(json_string)
	if result == null:
		return default
	return result

# ═══════════════════════════════════════════════════════════════════════════
# BATCH OPERATIONS
# ═══════════════════════════════════════════════════════════════════════════

static func clear_all() -> void:
	"""Clear all stored data (with our prefix only)."""
	if is_web():
		# Web: Remove only our prefixed keys
		var js_code = """
		for (var i = localStorage.length - 1; i >= 0; i--) {
			var key = localStorage.key(i);
			if (key && key.startsWith('%s')) {
				localStorage.removeItem(key);
			}
		}
		""" % STORAGE_PREFIX
		JavaScriptBridge.eval(js_code)
	else:
		# Desktop: Remove all .dat files in user://
		var dir = DirAccess.open("user://")
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".dat"):
					dir.remove(file_name)
				file_name = dir.get_next()
			dir.list_dir_end()

static func get_all_keys() -> Array:
	"""Get all stored keys (without prefix)."""
	var keys: Array = []

	if is_web():
		var js_code = """
		(function() {
			var keys = [];
			var prefix = '%s';
			for (var i = 0; i < localStorage.length; i++) {
				var key = localStorage.key(i);
				if (key && key.startsWith(prefix)) {
					keys.push(key.substring(prefix.length));
				}
			}
			return JSON.stringify(keys);
		})()
		""" % STORAGE_PREFIX
		var result = JavaScriptBridge.eval(js_code)
		if result:
			var parsed = JSON.parse_string(str(result))
			if parsed is Array:
				keys = parsed
	else:
		var dir = DirAccess.open("user://")
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".dat"):
					keys.append(file_name.trim_suffix(".dat"))
				file_name = dir.get_next()
			dir.list_dir_end()

	return keys

# ═══════════════════════════════════════════════════════════════════════════
# STORAGE INFO
# ═══════════════════════════════════════════════════════════════════════════

static func get_storage_type() -> String:
	"""Get the storage backend type as a string."""
	return "LocalStorage" if is_web() else "FileSystem"

static func get_storage_usage_bytes() -> int:
	"""Get approximate storage usage in bytes. Returns -1 if unknown."""
	if is_web():
		# Web: Estimate from localStorage
		var js_code = """
		(function() {
			var total = 0;
			var prefix = '%s';
			for (var i = 0; i < localStorage.length; i++) {
				var key = localStorage.key(i);
				if (key && key.startsWith(prefix)) {
					total += localStorage.getItem(key).length * 2; // UTF-16
				}
			}
			return total;
		})()
		""" % STORAGE_PREFIX
		var result = JavaScriptBridge.eval(js_code)
		if result != null:
			return int(result)
		return -1
	else:
		# Desktop: Sum file sizes
		var total: int = 0
		var dir = DirAccess.open("user://")
		if dir:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".dat"):
					var file = FileAccess.open("user://" + file_name, FileAccess.READ)
					if file:
						total += file.get_length()
						file.close()
				file_name = dir.get_next()
			dir.list_dir_end()
		return total
