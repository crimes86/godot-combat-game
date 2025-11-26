@tool
extends EditorScript

## SAFE VERSION: Rename spawns only, don't move them
##
## This version:
## - Renames your spawns with proper naming
## - Does NOT move them to a new parent
## - Does NOT change their positions
## - Safe to run!

func _run() -> void:
	print("\n" + "=".repeat(60))
	print("✏️  RENAMING ENEMY SPAWNS (positions unchanged)")
	print("=".repeat(60))

	var editor_interface = get_editor_interface()
	var edited_scene = editor_interface.get_edited_scene_root()

	if not edited_scene:
		print("❌ ERROR: No scene is currently open!")
		return

	print("📂 Working on scene: %s" % edited_scene.name)

	# Find all spawn markers
	var found_spawns = []
	find_spawn_markers(edited_scene, found_spawns)

	if found_spawns.is_empty():
		print("⚠️ No spawn markers found!")
		return

	print("\n📍 Found %d spawn markers to rename..." % found_spawns.size())

	# Collect spawn data
	var spawn_data = []
	for spawn_node in found_spawns:
		var level = extract_level(spawn_node)
		var pos = spawn_node.global_position

		spawn_data.append({
			"node": spawn_node,
			"level": level,
			"pos": pos,
			"old_name": spawn_node.name
		})

	# Sort by level, then by x position
	spawn_data.sort_custom(func(a, b):
		if a["level"] != b["level"]:
			return a["level"] < b["level"]
		return a["pos"].x < b["pos"].x
	)

	# Track counts per level for naming
	var level_counts = {}
	var campfire_pos = Vector2(-2000, 0)

	# Rename each spawn (NO MOVING!)
	print("\n✏️  Renaming spawns (keeping original positions)...")
	for data in spawn_data:
		var spawn_node = data["node"]
		var level = data["level"]
		var pos = data["pos"]

		# Track count for this level
		if not level_counts.has(level):
			level_counts[level] = 0
		level_counts[level] += 1

		# Determine direction/area from campfire
		var offset = pos - campfire_pos
		var area = get_area_name(offset)

		# Generate proper name
		var new_name = "L%d_Patrol_%s_%d" % [level, area, level_counts[level]]

		# Just rename - DON'T MOVE
		spawn_node.name = new_name

		# Ensure metadata is set
		if not spawn_node.has_meta("enemy_level"):
			spawn_node.set_meta("enemy_level", level)
		if not spawn_node.has_meta("enemy_type"):
			spawn_node.set_meta("enemy_type", "skeleton")
		if not spawn_node.has_meta("aggro_range"):
			spawn_node.set_meta("aggro_range", 150.0)

		print("   ✅ %s -> %s (L%d)" % [data["old_name"], new_name, level])

	# Summary
	print("\n📊 RENAME SUMMARY:")
	print("   Total spawns renamed: %d" % spawn_data.size())
	print("   Level distribution:")
	var sorted_levels = level_counts.keys()
	sorted_levels.sort()
	for level in sorted_levels:
		print("      Level %d: %d spawns" % [level, level_counts[level]])

	print("\n✅ RENAME COMPLETE!")
	print("   All spawns renamed (positions unchanged)")
	print("   Ready to use!")
	print("=".repeat(60) + "\n")

func find_spawn_markers(node: Node, results: Array) -> void:
	"""Recursively find all spawn marker nodes"""
	if node is Marker2D:
		if node.name.begins_with("EnemySpawn") or node.has_meta("enemy_level"):
			results.append(node)

	for child in node.get_children():
		find_spawn_markers(child, results)

func extract_level(spawn_node: Node) -> int:
	"""Extract level from node"""
	if spawn_node.has_meta("enemy_level"):
		return spawn_node.get_meta("enemy_level")
	if spawn_node.has_method("get") and "enemy_level" in spawn_node:
		return spawn_node.get("enemy_level")

	# Try parsing from name
	var name_lower = spawn_node.name.to_lower()
	if "l" in name_lower or "level" in name_lower:
		var regex = RegEx.new()
		regex.compile("l(\\d+)|level\\s*(\\d+)")
		var result = regex.search(name_lower)
		if result:
			var level_str = result.get_string(1) if result.get_string(1) else result.get_string(2)
			if level_str:
				return level_str.to_int()

	return 1

func get_area_name(offset: Vector2) -> String:
	"""Get area name based on offset"""
	var angle = offset.angle()
	var deg = rad_to_deg(angle)
	if deg < 0:
		deg += 360

	if deg < 22.5 or deg >= 337.5:
		return "East"
	elif deg < 67.5:
		return "SouthEast"
	elif deg < 112.5:
		return "South"
	elif deg < 157.5:
		return "SouthWest"
	elif deg < 202.5:
		return "West"
	elif deg < 247.5:
		return "NorthWest"
	elif deg < 292.5:
		return "North"
	else:
		return "NorthEast"
