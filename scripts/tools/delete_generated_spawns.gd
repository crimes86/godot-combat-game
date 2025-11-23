@tool
extends EditorScript

## Delete Generated L4-10 Spawns Only
##
## Removes all Level 4+ spawns (the ones auto-generated)
## Keeps your manual Level 1-3 spawns safe
##
## RUN THIS TO UNDO THE BAD GENERATION

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("🧹 DELETING GENERATED L4-10 SPAWNS")
	print("=".repeat(60))

	var editor_interface = get_editor_interface()
	var edited_scene = editor_interface.get_edited_scene_root()

	if not edited_scene:
		print("❌ ERROR: No scene is currently open!")
		return

	print("📂 Scene: %s" % edited_scene.name)
	print("\n🎯 Will DELETE: Level 4-10 spawns (generated)")
	print("✅ Will KEEP: Level 1-3 spawns (your manual placements)")

	# Find all spawns
	var all_spawns = []
	find_spawn_markers(edited_scene, all_spawns)

	if all_spawns.is_empty():
		print("\n✅ No spawn markers found!")
		return

	print("\n📍 Found %d total spawns" % all_spawns.size())
	print("🔍 Filtering for L4+ to delete...")

	var deleted = 0
	var kept = 0
	var deleted_nodes = []

	for spawn_node in all_spawns:
		var level = extract_level(spawn_node)

		# Delete if level 4 or higher
		if level >= 4:
			print("   ❌ DELETE: %s (Level %d)" % [spawn_node.name, level])
			deleted_nodes.append(spawn_node)
			deleted += 1
		else:
			# Keep L1-3
			kept += 1

	# Actually delete the nodes
	if deleted > 0:
		print("\n🗑️  Deleting %d generated spawns..." % deleted)
		for node in deleted_nodes:
			node.queue_free()
	else:
		print("\n✅ No L4+ spawns found to delete!")

	print("\n📊 CLEANUP SUMMARY:")
	print("   Deleted: %d spawns (Level 4-10)" % deleted)
	print("   Kept: %d spawns (Level 1-3 manual placements)" % kept)
	print("\n✅ CLEANUP COMPLETE!")
	print("   Your L1-3 manual spawns are safe and ready!")
	print("=".repeat(60) + "\n")

func find_spawn_markers(node: Node, results: Array) -> void:
	"""Recursively find all spawn markers"""
	if node is Marker2D:
		if node.name.begins_with("EnemySpawn") or node.has_meta("enemy_level"):
			results.append(node)

	for child in node.get_children():
		find_spawn_markers(child, results)

func extract_level(spawn_node: Node) -> int:
	"""Extract level from spawn node"""
	if spawn_node.has_meta("enemy_level"):
		return spawn_node.get_meta("enemy_level")
	if spawn_node.has_method("get") and "enemy_level" in spawn_node:
		return spawn_node.get("enemy_level")

	# Parse from name
	var regex = RegEx.new()
	regex.compile("l(\\d+)|level\\s*(\\d+)")
	var result = regex.search(spawn_node.name.to_lower())
	if result:
		var level_str = result.get_string(1) if result.get_string(1) else result.get_string(2)
		if level_str:
			return level_str.to_int()

	return 1
