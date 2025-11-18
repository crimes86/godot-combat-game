@tool
extends EditorScript

## Extend Radial Ring Enemy Spawn Pattern
##
## Analyzes your L1-3 radial placement and extends it to L4-10
## maintaining the expanding ring design
##
## HOW TO USE:
## 1. Make sure you've placed your L1-3 enemies in rings around campfire
## 2. Open this script in Godot editor
## 3. Run: File > Run (Ctrl+Shift+X)
## 4. New L4-10 spawns will be generated following your pattern

const CAMPFIRE_POS = Vector2(-2000, 0)
const RUINS1_POS = Vector2(1200, -2000)
const RUINS_EXCLUSION = 450.0

# WORLD BOUNDARIES - Zone 1 extends in all directions from campfire
const WORLD_MIN_X = -5000.0  # Western edge (actual game world boundary)
const WORLD_MAX_X = RUINS1_POS.x + RUINS_EXCLUSION  # Eastern edge at far side of Ruins 1 = 1200 + 450 = 1650
const WORLD_MIN_Y = -2500.0  # Northern edge
const WORLD_MAX_Y = 2500.0   # Southern edge

func _run() -> void:
	print("\n" + "=".repeat(80))
	print("🎯 ANALYZING RADIAL RING PATTERN AND EXTENDING TO LEVEL 10")
	print("=".repeat(80))

	var editor_interface = get_editor_interface()
	var edited_scene = editor_interface.get_edited_scene_root()

	if not edited_scene:
		print("❌ ERROR: No scene is currently open!")
		return

	print("📂 Scene: %s" % edited_scene.name)
	print("\n🗺️  World Boundaries (spawns in ALL directions, cut off at edges):")
	print("   X: %.0f to %.0f (%.0fpx west, %.0fpx east from campfire)" % [WORLD_MIN_X, WORLD_MAX_X, abs(WORLD_MIN_X - CAMPFIRE_POS.x), WORLD_MAX_X - CAMPFIRE_POS.x])
	print("   Y: %.0f to %.0f" % [WORLD_MIN_Y, WORLD_MAX_Y])
	print("   West will naturally cut off earlier than east")
	print("   (Edit lines 20-23 in script to adjust boundaries)")

	# Find all existing manual spawns
	var all_spawns = []
	find_spawn_markers(edited_scene, all_spawns)

	if all_spawns.is_empty():
		print("❌ No spawn markers found! Place some L1-3 enemies first.")
		return

	print("📍 Found %d existing spawns" % all_spawns.size())

	# Analyze the radial pattern
	var pattern = analyze_radial_pattern(all_spawns)

	if pattern["levels"].is_empty():
		print("❌ No valid spawns found with level data!")
		return

	print_pattern_analysis(pattern)

	# Validate we have L1-3 data
	var has_l1 = pattern["levels"].has(1)
	var has_l2 = pattern["levels"].has(2)
	var has_l3 = pattern["levels"].has(3)

	if not (has_l1 or has_l2 or has_l3):
		print("❌ Need at least some L1-3 spawns to analyze pattern!")
		return

	# Calculate expansion rate and density
	var expansion_data = calculate_expansion_pattern(pattern)
	print_expansion_data(expansion_data)

	# Generate L4-10 spawns
	print("\n🎲 Generating Level 4-10 spawns...")
	var new_spawns = generate_extended_rings(pattern, expansion_data, edited_scene)

	print("\n✅ PATTERN EXTENSION COMPLETE!")
	print("   Generated %d new spawns (L4-10)" % new_spawns)
	print("   Total spawns: %d" % (all_spawns.size() + new_spawns))
	print("=".repeat(80) + "\n")

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

func analyze_radial_pattern(spawns: Array) -> Dictionary:
	"""Analyze the radial ring pattern from existing spawns"""
	var pattern = {
		"levels": {},  # level -> {distances: [], positions: [], count: int}
		"total_count": 0,
		"min_level": 999,
		"max_level": 0
	}

	# Collect data per level
	for spawn_node in spawns:
		var level = extract_level(spawn_node)
		var pos = spawn_node.global_position
		var dist = pos.distance_to(CAMPFIRE_POS)

		if not pattern["levels"].has(level):
			pattern["levels"][level] = {
				"distances": [],
				"positions": [],
				"count": 0,
				"min_dist": 999999.0,
				"max_dist": 0.0,
				"avg_dist": 0.0
			}

		var level_data = pattern["levels"][level]
		level_data["distances"].append(dist)
		level_data["positions"].append(pos)
		level_data["count"] += 1
		level_data["min_dist"] = min(level_data["min_dist"], dist)
		level_data["max_dist"] = max(level_data["max_dist"], dist)

		pattern["min_level"] = min(pattern["min_level"], level)
		pattern["max_level"] = max(pattern["max_level"], level)
		pattern["total_count"] += 1

	# Calculate averages
	for level in pattern["levels"].keys():
		var level_data = pattern["levels"][level]
		var sum = 0.0
		for dist in level_data["distances"]:
			sum += dist
		level_data["avg_dist"] = sum / level_data["count"]

	return pattern

func calculate_expansion_pattern(pattern: Dictionary) -> Dictionary:
	"""Calculate how the rings expand and what density to use"""
	var levels = pattern["levels"]

	# Calculate ring width and spacing per level
	var ring_data = []
	var sorted_levels = levels.keys()
	sorted_levels.sort()

	for level in sorted_levels:
		var data = levels[level]
		ring_data.append({
			"level": level,
			"min_radius": data["min_dist"],
			"max_radius": data["max_dist"],
			"avg_radius": data["avg_dist"],
			"count": data["count"],
			"positions": data["positions"]
		})

	# Calculate average ring width and expansion rate
	var total_width = 0.0
	var total_expansion = 0.0
	var expansion_samples = 0

	for i in range(ring_data.size()):
		var ring = ring_data[i]
		var width = ring["max_radius"] - ring["min_radius"]
		total_width += width

		if i > 0:
			var prev_ring = ring_data[i - 1]
			var expansion = ring["avg_radius"] - prev_ring["avg_radius"]
			total_expansion += expansion
			expansion_samples += 1

	var avg_width = total_width / ring_data.size()
	var avg_expansion = total_expansion / max(expansion_samples, 1) if expansion_samples > 0 else 300.0

	# Calculate density (spawns per unit area)
	var total_density = 0.0
	for ring in ring_data:
		# Area of ring annulus
		var inner_r = ring["min_radius"]
		var outer_r = ring["max_radius"]
		var area = PI * (outer_r * outer_r - inner_r * inner_r)
		if area > 0:
			var density = ring["count"] / area
			total_density += density

	var avg_density = total_density / ring_data.size()

	# Calculate spacing between spawns
	var all_positions = []
	for level in levels.keys():
		all_positions.append_array(levels[level]["positions"])

	var min_spacing = 999999.0
	for i in range(all_positions.size()):
		for j in range(i + 1, all_positions.size()):
			var dist = all_positions[i].distance_to(all_positions[j])
			if dist > 0:
				min_spacing = min(min_spacing, dist)

	return {
		"ring_data": ring_data,
		"avg_width": avg_width,
		"avg_expansion": avg_expansion,
		"avg_density": avg_density,
		"min_spacing": max(min_spacing, 100.0),  # At least 100px
		"last_level": sorted_levels[-1],
		"last_avg_radius": ring_data[-1]["avg_radius"],
		"last_max_radius": ring_data[-1]["max_radius"]
	}

func generate_extended_rings(pattern: Dictionary, expansion: Dictionary, scene_root: Node) -> int:
	"""Generate L4-10 spawns continuing the radial pattern to fill gap to eastern boundary"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777  # Consistent generation

	var generated = 0
	var existing_positions = []

	# Collect all existing positions
	for level in pattern["levels"].keys():
		existing_positions.append_array(pattern["levels"][level]["positions"])

	var start_level = expansion["last_level"] + 1
	var current_radius = expansion["last_max_radius"]  # Where L3 ends

	# Calculate maximum radius to eastern boundary
	var max_radius_to_fill = CAMPFIRE_POS.distance_to(Vector2(WORLD_MAX_X, 0))

	# Calculate how much gap to fill
	var gap_to_fill = max_radius_to_fill - current_radius
	var levels_to_generate = 10 - start_level + 1  # e.g., if start_level = 4, then 7 levels (4-10)

	# Distribute the gap evenly across levels 4-10
	var ring_width_calculated = gap_to_fill / float(levels_to_generate)

	# Find or create container
	var container = scene_root.get_node_or_null("ManualEnemySpawns")
	if not container:
		container = scene_root

	# Track level counts for naming
	var level_counts = {}

	print("\n📏 Gap Filling Calculation:")
	print("   L3 ends at radius: %.0fpx" % current_radius)
	print("   Eastern boundary at: %.0fpx from campfire" % max_radius_to_fill)
	print("   Gap to fill: %.0fpx" % gap_to_fill)
	print("   Levels to generate: %d (L%d to L10)" % [levels_to_generate, start_level])
	print("   Ring width (calculated): %.0fpx per level" % ring_width_calculated)
	print("   Min spacing: %.0fpx" % expansion["min_spacing"])
	print("   Density: %.6f spawns/px²" % expansion["avg_density"])

	# Generate each level ring
	for level in range(start_level, 11):  # 4 to 10
		print("\n⚙️  Generating Level %d ring..." % level)

		# Calculate this ring's dimensions using calculated width to fill the gap
		var ring_inner = current_radius  # No gap!
		var ring_outer = ring_inner + ring_width_calculated  # Use calculated width, not avg_width
		var ring_avg = (ring_inner + ring_outer) / 2.0

		# Calculate target spawn count based on density
		var ring_area = PI * (ring_outer * ring_outer - ring_inner * ring_inner)
		var target_count = int(ring_area * expansion["avg_density"])
		target_count = max(target_count, 8)  # At least 8 per ring

		print("   Ring: %.0f - %.0fpx (avg: %.0f)" % [ring_inner, ring_outer, ring_avg])
		print("   Target spawns: %d" % target_count)

		var spawned_this_level = 0
		var attempts = 0
		var failed_attempts = 0
		# IMPORTANT: Keep trying until we've exhausted placement opportunities
		# This fills all directions including west, cutting off naturally at boundaries
		var max_attempts = target_count * 200  # Many attempts to fill all directions
		var max_failed_in_row = 500  # Stop if 500 failed attempts in a row

		while attempts < max_attempts and failed_attempts < max_failed_in_row:
			attempts += 1

			# Generate random position in ring
			var angle = rng.randf() * TAU
			var radius = rng.randf_range(ring_inner, ring_outer)
			var spawn_pos = CAMPFIRE_POS + Vector2(cos(angle), sin(angle)) * radius

			# Validate position
			var valid = true

			# CRITICAL: Check world boundaries first!
			if spawn_pos.x < WORLD_MIN_X or spawn_pos.x > WORLD_MAX_X or spawn_pos.y < WORLD_MIN_Y or spawn_pos.y > WORLD_MAX_Y:
				valid = false
				continue

			# Check ruins exclusion
			if spawn_pos.distance_to(RUINS1_POS) < RUINS_EXCLUSION:
				valid = false
				continue

			# Check spacing from existing spawns
			if valid:
				for existing_pos in existing_positions:
					if spawn_pos.distance_to(existing_pos) < expansion["min_spacing"]:
						valid = false
						break

			# Spawn if valid
			if valid:
				create_spawn_marker(spawn_pos, level, container, scene_root, level_counts)
				existing_positions.append(spawn_pos)
				spawned_this_level += 1
				generated += 1
				failed_attempts = 0  # Reset failed counter on success
			else:
				failed_attempts += 1  # Track consecutive failures

		print("   ✅ Generated %d spawns for Level %d (attempted: %d, target: %d)" % [spawned_this_level, level, attempts, target_count])

		# Move to next ring - NO GAP between rings!
		current_radius = ring_outer  # Next ring starts exactly where this one ends

	return generated

func create_spawn_marker(pos: Vector2, level: int, parent: Node, scene_root: Node, level_counts: Dictionary) -> void:
	"""Create a spawn marker node"""
	# Track count for naming
	if not level_counts.has(level):
		level_counts[level] = 0
	level_counts[level] += 1

	# Determine area
	var offset = pos - CAMPFIRE_POS
	var area = get_area_name(offset)

	# Create marker
	var marker = Marker2D.new()
	marker.global_position = pos
	marker.name = "L%d_Patrol_%s_%d" % [level, area, level_counts[level]]

	# Set metadata
	marker.set_meta("enemy_level", level)
	marker.set_meta("enemy_type", "skeleton")
	marker.set_meta("aggro_range", 150.0)

	# Try to apply script
	var spawn_script = load("res://scripts/tools/manual_enemy_spawn.gd")
	if spawn_script:
		marker.set_script(spawn_script)
		marker.set("enemy_level", level)
		marker.set("enemy_type", "skeleton")
		marker.set("aggro_range", 150.0)

	# Add to scene
	parent.add_child(marker)
	marker.owner = scene_root

func get_area_name(offset: Vector2) -> String:
	"""Get area name based on angle"""
	var angle = offset.angle()
	var deg = rad_to_deg(angle)
	if deg < 0:
		deg += 360

	if deg < 22.5 or deg >= 337.5:
		return "East"
	elif deg < 67.5:
		return "SE"
	elif deg < 112.5:
		return "South"
	elif deg < 157.5:
		return "SW"
	elif deg < 202.5:
		return "West"
	elif deg < 247.5:
		return "NW"
	elif deg < 292.5:
		return "North"
	else:
		return "NE"

func print_pattern_analysis(pattern: Dictionary) -> void:
	"""Print analysis of existing pattern"""
	print("\n📊 EXISTING PATTERN ANALYSIS:")
	print("   Total spawns: %d" % pattern["total_count"])
	print("   Level range: %d - %d" % [pattern["min_level"], pattern["max_level"]])
	print("\n   Ring structure:")

	var sorted_levels = pattern["levels"].keys()
	sorted_levels.sort()

	for level in sorted_levels:
		var data = pattern["levels"][level]
		print("      Level %d: %d spawns | Radius: %.0f - %.0f (avg: %.0f)" % [
			level,
			data["count"],
			data["min_dist"],
			data["max_dist"],
			data["avg_dist"]
		])

func print_expansion_data(expansion: Dictionary) -> void:
	"""Print expansion calculation results"""
	print("\n🔍 EXPANSION PATTERN DETECTED:")
	print("   Avg ring width: %.0fpx" % expansion["avg_width"])
	print("   Avg expansion per level: %.0fpx" % expansion["avg_expansion"])
	print("   Spawn density: %.6f per px²" % expansion["avg_density"])
	print("   Min spacing: %.0fpx" % expansion["min_spacing"])
	print("   Last ring (L%d): %.0fpx avg radius" % [expansion["last_level"], expansion["last_avg_radius"]])
