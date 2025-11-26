extends Node
class_name JSONValidator

## JSON Validation Utility
## Provides safe JSON loading with error handling and validation

## Load and parse a JSON file with validation
static func load_json_file(file_path: String) -> Dictionary:
	# Check if file exists
	if not FileAccess.file_exists(file_path):
		DebugConfig.log_error("JSON file not found: %s" % file_path)
		return {"success": false, "error": "FILE_NOT_FOUND", "data": null}

	# Open file
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		DebugConfig.log_error("Failed to open JSON file: %s (Error: %d)" % [file_path, FileAccess.get_open_error()])
		return {"success": false, "error": "FILE_OPEN_FAILED", "data": null}

	# Read content
	var content = file.get_as_text()
	file.close()

	# Check if empty
	if content.is_empty():
		DebugConfig.log_error("JSON file is empty: %s" % file_path)
		return {"success": false, "error": "FILE_EMPTY", "data": null}

	# Parse JSON
	var json = JSON.new()
	var parse_result = json.parse(content)

	if parse_result != OK:
		var error_line = json.get_error_line()
		var error_msg = json.get_error_message()
		DebugConfig.log_error("JSON parse error in %s at line %d: %s" % [file_path, error_line, error_msg])
		return {"success": false, "error": "PARSE_ERROR", "error_line": error_line, "error_message": error_msg, "data": null}

	# Success
	return {"success": true, "error": null, "data": json.data}

## Validate that required fields exist in a dictionary
static func validate_required_fields(data: Dictionary, required_fields: Array, context: String = "data") -> bool:
	for field in required_fields:
		if not data.has(field):
			DebugConfig.log_error("Missing required field '%s' in %s" % [field, context])
			return false
	return true

## Validate field types in a dictionary
static func validate_field_types(data: Dictionary, field_types: Dictionary, context: String = "data") -> bool:
	for field_name in field_types.keys():
		if data.has(field_name):
			var expected_type = field_types[field_name]
			var actual_value = data[field_name]

			# Check type
			var type_matches = false
			match expected_type:
				TYPE_STRING:
					type_matches = actual_value is String
				TYPE_INT:
					type_matches = actual_value is int or actual_value is float
				TYPE_FLOAT:
					type_matches = actual_value is float or actual_value is int
				TYPE_BOOL:
					type_matches = actual_value is bool
				TYPE_ARRAY:
					type_matches = actual_value is Array
				TYPE_DICTIONARY:
					type_matches = actual_value is Dictionary

			if not type_matches:
				DebugConfig.log_error("Field '%s' in %s has wrong type (expected: %s)" % [field_name, context, type_string(expected_type)])
				return false

	return true

## Get a safe value from dictionary with default fallback
static func get_safe_value(data: Dictionary, key: String, default_value):
	if data.has(key):
		var value = data[key]
		# Type check
		if typeof(value) == typeof(default_value):
			return value
		else:
			DebugConfig.log_warning("Field '%s' has wrong type, using default: %s" % [key, str(default_value)])
			return default_value
	return default_value

## Convert TYPE_* constant to string for error messages
static func type_string(type_enum: int) -> String:
	match type_enum:
		TYPE_NIL: return "null"
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_VECTOR2: return "Vector2"
		TYPE_RECT2: return "Rect2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_TRANSFORM2D: return "Transform2D"
		TYPE_PLANE: return "Plane"
		TYPE_QUATERNION: return "Quaternion"
		TYPE_AABB: return "AABB"
		TYPE_BASIS: return "Basis"
		TYPE_TRANSFORM3D: return "Transform3D"
		TYPE_COLOR: return "Color"
		TYPE_NODE_PATH: return "NodePath"
		TYPE_RID: return "RID"
		TYPE_OBJECT: return "Object"
		TYPE_DICTIONARY: return "Dictionary"
		TYPE_ARRAY: return "Array"
		_: return "Unknown"
