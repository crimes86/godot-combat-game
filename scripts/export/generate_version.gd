@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "VersionGenerator"

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	"""Generate version.txt with git commit hash before export"""
	var output = []
	var exit_code = OS.execute("git", ["rev-parse", "--short", "HEAD"], output, true)

	var version = "unknown"
	if exit_code == 0 and output.size() > 0:
		version = output[0].strip_edges()

	# Write to res://version.txt
	var file = FileAccess.open("res://version.txt", FileAccess.WRITE)
	if file:
		file.store_string(version)
		file.close()
		print("VersionGenerator: Created version.txt with version: %s" % version)
	else:
		push_error("VersionGenerator: Failed to create version.txt")

func _export_end() -> void:
	pass
