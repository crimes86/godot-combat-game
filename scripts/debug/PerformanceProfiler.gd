extends CanvasLayer

## Deep Performance Profiler
## Shows exactly what's eating CPU time

var label: Label
var update_timer: float = 0.0

# Performance tracking
var frame_times: Dictionary = {}
var sample_count: int = 0

# Debug visualization containers
var debug_draw_container: Node2D = null
var chunk_boundary_lines: Array = []
var enemy_debug_circles: Array = []

func _ready() -> void:
	layer = 1001
	visible = false  # Hidden by default, toggle with F3

	label = Label.new()
	label.add_theme_font_size_override("font_size", 12)  # Smaller font for better fit
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(label)

	# Connect to Constants debug signal
	if Constants:
		Constants.debug_display_toggled.connect(_on_debug_toggled)

func _process(delta: float) -> void:
	# Only update profiler when visible (F3 toggled on)
	if not visible:
		return

	update_timer += delta
	if update_timer >= 0.5:
		update_timer = 0.0
		update_profile()

		# Refresh enemy debug visualizations (enemies move!)
		refresh_enemy_debug()

func update_profile() -> void:
	var fps = Engine.get_frames_per_second()
	var frame_time_ms = 1000.0 / max(fps, 1)

	# Count scene nodes
	var root = get_tree().root
	var total_nodes = count_nodes_recursive(root)

	# Count by type
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var campfires = get_tree().get_nodes_in_group("campfire")

	# Count particles (both CPU and GPU)
	var particle_count = 0
	var cpu_particles = get_all_nodes_of_type(root, CPUParticles2D)
	var gpu_particles = get_all_nodes_of_type(root, GPUParticles2D)
	for p in cpu_particles:
		if p.emitting:
			particle_count += p.amount
	for p in gpu_particles:
		if p.emitting:
			particle_count += p.amount

	# Count polygons
	var polygon_count = get_all_nodes_of_type(root, Polygon2D).size()

	# Count sprites
	var sprite_count = 0
	sprite_count += get_all_nodes_of_type(root, Sprite2D).size()
	sprite_count += get_all_nodes_of_type(root, AnimatedSprite2D).size()

	# Count lights
	var light_count = get_all_nodes_of_type(root, PointLight2D).size()

	# Memory usage (simplified - avoid API version issues)
	var static_mem = OS.get_static_memory_usage() / 1024.0 / 1024.0

	# Get chunk-based enemy counts
	var chunk_enemy_info = get_chunk_enemy_info()

	# Get system node breakdown
	var system_info = get_system_node_breakdown()

	# Get prop stats (trees, rocks)
	var prop_info = get_prop_stats_info()

	# Get wolf pack info
	var wolf_pack_info = get_wolf_pack_info()

	var color = Color.GREEN
	if fps < 30:
		color = Color.RED
	elif fps < 50:
		color = Color.YELLOW
	label.add_theme_color_override("font_color", color)

	# Get chunk info
	var chunk_info = get_chunk_debug_info()

	# Get time info
	var time_info = get_time_debug_info()

	# Get cursor/player position info
	var cursor_info = get_cursor_debug_info()

	# Build compact debug display
	label.text = """[F3] %d FPS (%.1fms) | %s | %.1fMB
─────────────────────────
%s | %s
%s
─────────────────────────
SCENE: %d nodes, %d sprites, %d polys
       %d particles, %d lights
─────────────────────────
PROPS:
%s
─────────────────────────
ENEMIES:
%s
─────────────────────────
CHUNKS:
%s
─────────────────────────
WOLF PACKS:
%s
─────────────────────────
SYSTEMS:
%s
""" % [
		fps, frame_time_ms, get_scene_name(), static_mem,
		time_info, "F4=time",
		cursor_info,
		total_nodes, sprite_count, polygon_count, particle_count, light_count,
		prop_info,
		chunk_enemy_info,
		chunk_info,
		wolf_pack_info,
		system_info
	]

	# Position label on right side of screen with proper bounds
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		# Use narrower width for compact display
		label.position = Vector2(viewport_size.x - 280, 5)

func get_scene_name() -> String:
	"""Get current scene name"""
	var current = get_tree().current_scene
	return current.name if current else "Unknown"

func get_cursor_debug_info() -> String:
	"""Get cursor and player position info (compact)"""
	var player_pos = Vector2.ZERO

	var player = get_tree().get_first_node_in_group("player")
	if player:
		player_pos = player.global_position

	return "Pos: (%.0f, %.0f)" % [player_pos.x, player_pos.y]

func get_system_node_breakdown() -> String:
	"""Get node counts per major system (compact)"""
	var game_world = find_game_world()
	if not game_world:
		return "  GameWorld not found"

	var info = ""

	# Collect children with their node counts, sorted by size
	var child_counts: Array = []
	for child in game_world.get_children():
		var child_count = count_nodes_recursive(child)
		var child_name = child.name

		# Skip enemies (we count them separately by group)
		if child.is_in_group(Constants.GROUP_ENEMIES):
			continue

		child_counts.append({"name": child_name, "count": child_count, "node": child})

	# Sort by count descending
	child_counts.sort_custom(func(a, b): return a.count > b.count)

	# Show top 6 largest children only
	var shown = 0
	for data in child_counts:
		if shown >= 6:
			break
		if data.count >= 20:  # Only show if 20+ nodes
			var display_name = data.name
			if display_name.length() > 12:
				display_name = display_name.substr(0, 12)
			info += "  %s: %d\n" % [display_name, data.count]
			shown += 1

	# Enemies (spawned directly under GameWorld)
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var enemy_nodes = 0
	for enemy in enemies:
		enemy_nodes += count_nodes_recursive(enemy)
	info += "  Enemies(%d): %d nodes" % [enemies.size(), enemy_nodes]

	return info

func count_nodes_recursive(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += count_nodes_recursive(child)
	return count

func get_all_nodes_of_type(node: Node, type) -> Array:
	var result = []
	if is_instance_of(node, type):
		result.append(node)
	for child in node.get_children():
		result.append_array(get_all_nodes_of_type(child, type))
	return result

func get_chunk_debug_info() -> String:
	"""Get chunk system debug information (compact)"""
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return "  No player"

	var CHUNK_SIZE = Constants.CHUNK_SIZE
	var player_pos = player.global_position
	var chunk_x = int(floor(player_pos.x / CHUNK_SIZE))

	# Calculate distances to chunk edges
	var chunk_origin_x = chunk_x * CHUNK_SIZE
	var chunk_end_x = chunk_origin_x + CHUNK_SIZE
	var dist_to_west = player_pos.x - chunk_origin_x
	var dist_to_east = chunk_end_x - player_pos.x

	var warn_west = " !" if dist_to_west < 1000 else ""
	var warn_east = " !" if dist_to_east < 1000 else ""

	var info = "  Chunk [%d] W:%.0f%s E:%.0f%s" % [chunk_x, dist_to_west, warn_west, dist_to_east, warn_east]

	return info

func get_chunk_enemy_info() -> String:
	"""Get enemy count per chunk from spawn manager with LOD stats (compact)"""
	var game_world = find_game_world()
	if not game_world:
		return "  No GameWorld"

	# Try multiple ways to find spawn_manager
	var spawn_manager = null

	# Method 1: Property access
	if "spawn_manager" in game_world:
		spawn_manager = game_world.spawn_manager

	# Method 2: Child node
	if not spawn_manager:
		spawn_manager = game_world.get_node_or_null("ChunkAwareSpawnManager")

	# Method 3: Search all children
	if not spawn_manager:
		for child in game_world.get_children():
			if child.get_class() == "Node" and child.name == "ChunkAwareSpawnManager":
				spawn_manager = child
				break
			if child.has_method("get_stats"):
				spawn_manager = child
				break

	if not spawn_manager:
		# Just show enemy count from group instead
		var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
		var lod_stats = get_enemy_lod_stats()
		return "  Total: %d | LOD: %d/%d/%d" % [enemies.size(), lod_stats.lod_0, lod_stats.lod_1, lod_stats.lod_2]

	if not spawn_manager.has_method("get_stats"):
		var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
		return "  Total: %d (no stats)" % enemies.size()

	var stats = spawn_manager.get_stats()

	# Compact chunk display on one line
	var chunk_keys = stats.enemies_per_chunk.keys()
	chunk_keys.sort()

	var chunk_parts = []
	for chunk_key in chunk_keys:
		var count = stats.enemies_per_chunk[chunk_key]
		chunk_parts.append("[%s]:%d" % [chunk_key, count])

	var info = "  " + " ".join(chunk_parts) + "\n" if chunk_parts.size() > 0 else "  No chunks\n"
	info += "  Total: %d | " % stats.total_enemies

	# Add LOD stats on same line
	var lod_stats = get_enemy_lod_stats()
	info += "LOD: %d/%d/%d" % [lod_stats.lod_0, lod_stats.lod_1, lod_stats.lod_2]

	return info

func get_enemy_lod_stats() -> Dictionary:
	"""Count enemies by LOD level"""
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	var lod_0 = 0  # Full detail
	var lod_1 = 0  # Reduced
	var lod_2 = 0  # Minimal

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		# Check the enemy's current_lod if it exists
		if "current_lod" in enemy:
			match enemy.current_lod:
				0: lod_0 += 1
				1: lod_1 += 1
				2: lod_2 += 1
		else:
			lod_0 += 1  # Default to full if no LOD

	return {"lod_0": lod_0, "lod_1": lod_1, "lod_2": lod_2}

func _on_debug_toggled(is_visible: bool) -> void:
	"""Called when F3 debug display is toggled"""
	visible = is_visible

	# Show/hide debug visualizations
	if is_visible:
		create_debug_visualizations()
	else:
		clear_debug_visualizations()

func create_debug_visualizations() -> void:
	"""Create debug visualization overlays for chunks and enemies"""
	# Find GameWorld to add debug container
	var game_world = find_game_world()
	if not game_world:
		print("⚠️ Cannot create debug visualizations - GameWorld not found")
		return

	# Create or clear container
	if debug_draw_container and is_instance_valid(debug_draw_container):
		clear_debug_visualizations()

	debug_draw_container = Node2D.new()
	debug_draw_container.name = "DebugDrawContainer"
	debug_draw_container.z_index = 1000  # Draw on top
	game_world.add_child(debug_draw_container)

	# Draw chunk boundaries
	draw_chunk_boundaries()

	# Draw POI quadrants and markers
	draw_poi_debug()

	# Draw enemy debug info
	draw_enemy_debug()

func clear_debug_visualizations() -> void:
	"""Remove debug visualization overlays"""
	# Clear chunk boundary lines first
	for line in chunk_boundary_lines:
		if is_instance_valid(line):
			line.queue_free()
	chunk_boundary_lines.clear()

	# Clear enemy debug circles
	for circle in enemy_debug_circles:
		if is_instance_valid(circle):
			circle.queue_free()
	enemy_debug_circles.clear()

	# Clear the main debug container and ALL its children
	if debug_draw_container and is_instance_valid(debug_draw_container):
		# Explicitly free all children first to avoid orphans
		for child in debug_draw_container.get_children():
			if is_instance_valid(child):
				child.queue_free()
		debug_draw_container.queue_free()
		debug_draw_container = null

	# Also clean up any stray debug nodes that might be in GameWorld
	var game_world = find_game_world()
	if game_world:
		for child in game_world.get_children():
			if child.name == "DebugDrawContainer" or child.name.begins_with("EnemyDebug_"):
				child.queue_free()

func draw_chunk_boundaries() -> void:
	"""Draw chunk boundaries (both vertical and horizontal for square chunks)"""
	if not debug_draw_container:
		return

	var CHUNK_SIZE = Constants.CHUNK_SIZE
	var WORLD_MIN_X = -Constants.CHUNK_SIZE
	var WORLD_MAX_X = Constants.CHUNK_SIZE * 2
	var WORLD_MIN_Y = -Constants.CHUNK_SIZE / 2
	var WORLD_MAX_Y = Constants.CHUNK_SIZE / 2

	# Draw vertical chunk boundaries
	var start_chunk_x = int(floor(WORLD_MIN_X / CHUNK_SIZE))
	var end_chunk_x = int(ceil(WORLD_MAX_X / CHUNK_SIZE))

	for chunk_x in range(start_chunk_x, end_chunk_x + 1):
		var boundary_x = chunk_x * CHUNK_SIZE

		# Create vertical line at chunk boundary
		var line = Line2D.new()
		line.name = "ChunkBoundaryV_%d" % chunk_x
		line.width = 4.0
		line.default_color = Color(1, 0, 1, 0.7)  # Magenta for visibility
		line.add_point(Vector2(boundary_x, WORLD_MIN_Y))
		line.add_point(Vector2(boundary_x, WORLD_MAX_Y))
		line.z_index = 999
		debug_draw_container.add_child(line)
		chunk_boundary_lines.append(line)

		# Add label showing chunk ID
		var chunk_label = Label.new()
		chunk_label.text = "Chunk %d" % chunk_x
		chunk_label.position = Vector2(boundary_x + 50, WORLD_MIN_Y + 50)
		chunk_label.add_theme_font_size_override("font_size", 24)
		chunk_label.add_theme_color_override("font_color", Color(1, 0, 1, 1))
		chunk_label.add_theme_color_override("font_outline_color", Color.BLACK)
		chunk_label.add_theme_constant_override("outline_size", 4)
		chunk_label.z_index = 999
		debug_draw_container.add_child(chunk_label)

	# Draw horizontal world boundaries (top and bottom of world)
	for boundary_y in [WORLD_MIN_Y, WORLD_MAX_Y]:
		var line = Line2D.new()
		line.name = "WorldBoundaryH_%d" % int(boundary_y)
		line.width = 4.0
		line.default_color = Color(1, 0.5, 0, 0.7)  # Orange for world bounds
		line.add_point(Vector2(WORLD_MIN_X, boundary_y))
		line.add_point(Vector2(WORLD_MAX_X, boundary_y))
		line.z_index = 999
		debug_draw_container.add_child(line)
		chunk_boundary_lines.append(line)

func draw_poi_debug() -> void:
	"""Draw POI quadrant boundaries and POI markers for edge chunks"""
	if not debug_draw_container:
		return

	var game_world = find_game_world()
	if not game_world or not game_world.get("poi_manager"):
		return

	var CHUNK_SIZE = Constants.CHUNK_SIZE
	var HALF_CHUNK = CHUNK_SIZE / 2.0
	var QUARTER_CHUNK = CHUNK_SIZE / 4.0

	# Edge chunks: -1 and +1
	var edge_chunks = [-1, 1]

	for chunk_id in edge_chunks:
		var chunk_start_x = chunk_id * CHUNK_SIZE

		# Draw quadrant divider lines (cyan, dashed effect)
		# Vertical divider (splits NW/SW from NE/SE)
		var v_line = Line2D.new()
		v_line.name = "QuadrantV_Chunk%d" % chunk_id
		v_line.width = 2.0
		v_line.default_color = Color(0, 1, 1, 0.5)  # Cyan
		v_line.add_point(Vector2(chunk_start_x + HALF_CHUNK, -HALF_CHUNK))
		v_line.add_point(Vector2(chunk_start_x + HALF_CHUNK, HALF_CHUNK))
		v_line.z_index = 998
		debug_draw_container.add_child(v_line)

		# Horizontal divider (splits NW/NE from SW/SE)
		var h_line = Line2D.new()
		h_line.name = "QuadrantH_Chunk%d" % chunk_id
		h_line.width = 2.0
		h_line.default_color = Color(0, 1, 1, 0.5)  # Cyan
		h_line.add_point(Vector2(chunk_start_x, 0))
		h_line.add_point(Vector2(chunk_start_x + CHUNK_SIZE, 0))
		h_line.z_index = 998
		debug_draw_container.add_child(h_line)

		# Add quadrant labels
		var quadrant_positions = {
			"NW": Vector2(chunk_start_x + QUARTER_CHUNK, -QUARTER_CHUNK),
			"NE": Vector2(chunk_start_x + QUARTER_CHUNK * 3, -QUARTER_CHUNK),
			"SW": Vector2(chunk_start_x + QUARTER_CHUNK, QUARTER_CHUNK),
			"SE": Vector2(chunk_start_x + QUARTER_CHUNK * 3, QUARTER_CHUNK),
		}

		for quad_name in quadrant_positions:
			var pos = quadrant_positions[quad_name]
			var label = Label.new()
			label.text = quad_name
			label.position = pos + Vector2(-15, -300)  # Offset to top of quadrant
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_color", Color(0, 1, 1, 0.7))
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
			label.z_index = 999
			debug_draw_container.add_child(label)

	# Draw POI markers
	var pois_by_type_color = {
		"settlement_plot": Color(0, 1, 0, 0.8),      # Green
		"ruins": Color(0.8, 0.5, 0, 0.8),            # Orange
		"monster_lava_lake": Color(1, 0, 0, 0.8),   # Red
		"resource_node": Color(0, 0.7, 1, 0.8),     # Light blue
		"monster_den": Color(0.8, 0, 0.8, 0.8),     # Purple
		"ancient_shrine": Color(1, 1, 0, 0.8),      # Yellow
	}

	for chunk_id in edge_chunks:
		var pois = game_world.poi_manager.get_pois_for_chunk(chunk_id)
		for poi in pois:
			var color = pois_by_type_color.get(poi.type, Color.WHITE)

			# Draw circle for POI
			draw_circle_outline(poi.position, poi.radius, color, "POI_%s_%d" % [poi.type, poi.quadrant])

			# Draw POI label
			var label = Label.new()
			label.text = poi.type.replace("_", " ").capitalize()
			label.position = poi.position + Vector2(-60, -poi.radius - 25)
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", color)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
			label.z_index = 999
			debug_draw_container.add_child(label)

			# Draw center dot
			var dot = ColorRect.new()
			dot.size = Vector2(10, 10)
			dot.position = poi.position - Vector2(5, 5)
			dot.color = color
			dot.z_index = 999
			debug_draw_container.add_child(dot)


func draw_enemy_debug() -> void:
	"""Draw debug info around enemies - DISABLED (too spammy with many enemies)"""
	# Enemy debug labels disabled - with 100+ enemies it creates too much visual noise
	# To re-enable: uncomment the code below
	pass
	#if not debug_draw_container:
	#	return
	#var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	#for enemy in enemies:
	#	... (enemy debug drawing code)

func draw_circle_outline(center: Vector2, radius: float, color: Color, node_name: String) -> void:
	"""Draw a circle outline using Line2D"""
	if not debug_draw_container:
		return

	var line = Line2D.new()
	line.name = node_name
	line.width = 2.0
	line.default_color = color
	line.z_index = 998

	# Create circle points
	var num_points = 32
	for i in range(num_points + 1):
		var angle = (float(i) / num_points) * TAU
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)

	debug_draw_container.add_child(line)
	enemy_debug_circles.append(line)

func find_game_world() -> Node:
	"""Find the GameWorld node (or TestHub/TradingHub as fallback)"""
	var root = get_tree().root
	for child in root.get_children():
		var game_world = child.get_node_or_null("GameWorld")
		if game_world:
			return game_world
		if child.name == "GameWorld":
			return child
		# Also check for TestHub/TradingHub scenes
		if child.name in ["TestHub", "TradingHub"]:
			return child
	# Check current scene directly
	var current = get_tree().current_scene
	if current and current.name in ["GameWorld", "TestHub", "TradingHub"]:
		return current
	return null

func get_time_debug_info() -> String:
	"""Get current game time and period from TimeManager"""
	if not TimeManager:
		return "TimeManager not found"

	var time_str = TimeManager.get_time_string()
	var period = TimeManager.get_period().to_upper()
	var brightness = TimeManager.get_brightness()

	return "%s (%s) | Brightness: %.0f%%" % [time_str, period, brightness * 100]

func get_prop_stats_info() -> String:
	"""Get prop statistics from CellStreamingManager (if active) or ChunkBasedPropSystem"""
	var game_world = find_game_world()
	if not game_world:
		return "  GameWorld not found"

	var stats: Dictionary

	# Check for cell streaming manager first (smoother prop loading)
	var cell_streaming = game_world.get("cell_streaming_manager")
	if cell_streaming and is_instance_valid(cell_streaming) and cell_streaming.has_method("get_prop_stats"):
		stats = cell_streaming.get_prop_stats()
		var info = "  Trees: %d (%d nodes)\n" % [stats.trees, stats.tree_nodes]
		info += "  Rocks: %dL %dM %dS (%d nodes)\n" % [
			stats.rocks_large, stats.rocks_medium, stats.rocks_small, stats.rock_nodes
		]
		info += "  Lava: %d | Bones: %d | Other: %d\n" % [stats.lava_pools, stats.bones, stats.other]
		info += "  Cells: %d loaded, %d cached\n" % [stats.cells_loaded, stats.cells_cached]
		info += "  Total: %d props, %d nodes" % [stats.total_props, stats.total_nodes]
		return info

	# Fall back to chunk-based system
	var chunk_system = game_world.get_node_or_null("ChunkBasedPropSystem")
	if not chunk_system:
		if game_world.get("chunk_prop_system"):
			chunk_system = game_world.chunk_prop_system

	if not chunk_system or not chunk_system.has_method("get_prop_stats"):
		return "  PropSystem not found"

	stats = chunk_system.get_prop_stats()

	var info = "  Trees: %d (%d nodes)\n" % [stats.trees, stats.tree_nodes]
	info += "  Rocks: %dL %dM %dS (%d nodes)\n" % [
		stats.rocks_large, stats.rocks_medium, stats.rocks_small, stats.rock_nodes
	]
	info += "  Lava: %d | Bones: %d | Other: %d\n" % [stats.lava_pools, stats.bones, stats.other]
	info += "  Total: %d props, %d nodes" % [stats.total_props, stats.total_nodes]

	return info

func refresh_enemy_debug() -> void:
	"""Update enemy debug info without recreating chunk boundaries"""
	if not debug_draw_container or not is_instance_valid(debug_draw_container):
		return

	# Remove old enemy debug nodes
	for node in debug_draw_container.get_children():
		if node.name.begins_with("EnemyLabel_") or node.name.begins_with("AggroRange_"):
			node.queue_free()

	enemy_debug_circles.clear()

	# Redraw enemy debug info at new positions
	draw_enemy_debug()

	# Redraw wolf pack patrol paths
	draw_wolf_pack_patrol_paths()


func get_wolf_pack_info() -> String:
	"""Get wolf pack patrol/roaming debug info (compact)"""
	var wolves = get_tree().get_nodes_in_group("wolves")
	if wolves.is_empty():
		return "  No wolves"

	# Count pack alphas
	var packs: Dictionary = {}
	for wolf in wolves:
		if not is_instance_valid(wolf):
			continue
		var pack_id = wolf.get("pack_id")
		if not pack_id:
			continue
		if not packs.has(pack_id):
			packs[pack_id] = 0
		packs[pack_id] += 1

	return "  %d packs, %d wolves" % [packs.size(), wolves.size()]


func draw_wolf_pack_patrol_paths() -> void:
	"""Draw patrol paths for roaming wolf packs"""
	if not debug_draw_container or not is_instance_valid(debug_draw_container):
		return

	# Remove old patrol path nodes
	for node in debug_draw_container.get_children():
		if node.name.begins_with("WolfPatrol_"):
			node.queue_free()

	var wolves = get_tree().get_nodes_in_group("wolves")

	for wolf in wolves:
		if not is_instance_valid(wolf):
			continue

		# Only draw for moving pack alphas
		if not wolf.get("pack_alpha"):
			continue

		var is_moving = wolf.get("_pack_is_moving")
		if not is_moving:
			continue

		var move_dir = wolf.get("_pack_move_direction")
		if move_dir == null or move_dir == Vector2.ZERO:
			continue

		var wolf_pos = wolf.global_position
		var pack_id = wolf.get("pack_id")
		if pack_id == null:
			pack_id = "unknown"

		# Single line with arrow built-in (reduces node count)
		var direction_end = wolf_pos + move_dir * 80.0
		var arrow_angle = move_dir.angle()
		var arrow_size = 12.0

		var line = Line2D.new()
		line.name = "WolfPatrol_%s" % pack_id
		line.width = 3.0
		line.default_color = Color(0.7, 0.4, 0.1, 0.8)
		line.add_point(wolf_pos)
		line.add_point(direction_end)
		# Arrow head points
		line.add_point(direction_end + Vector2.from_angle(arrow_angle + PI * 0.75) * arrow_size)
		line.add_point(direction_end)
		line.add_point(direction_end + Vector2.from_angle(arrow_angle - PI * 0.75) * arrow_size)
		line.z_index = 997
		debug_draw_container.add_child(line)
