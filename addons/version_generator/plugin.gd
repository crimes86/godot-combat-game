@tool
extends EditorPlugin

var export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	export_plugin = preload("res://scripts/export/generate_version.gd").new()
	add_export_plugin(export_plugin)
	print("VersionGenerator plugin loaded")

func _exit_tree() -> void:
	remove_export_plugin(export_plugin)
	export_plugin = null
