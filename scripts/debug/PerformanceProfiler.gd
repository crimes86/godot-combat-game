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
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(label)

	# Connect to DebugConfig signal
	if DebugConfig:
		DebugConfig.debug_display_toggled.connect(_on_debug_toggled)

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

	label.text = """FPS: %d (%.1f ms/frame)
━━━━━━━━━━━━━━━━━━━━━━
TIME: %s
━━━━━━━━━━━━━━━━━━━━━━
SCENE TOTALS:
  Nodes: %d
  Sprites: %d
  Polygons: %d
  Particles: %d
  Lights: %d
━━━━━━━━━━━━━━━━━━━━━━
SYSTEMS:
%s
━━━━━━━━━━━━━━━━━━━━━━
CHUNKS:
%s
━━━━━━━━━━━━━━━━━━━━━━
ENEMIES:
%s
━━━━━━━━━━━━━━━━━━━━━━
MEMORY: %.1f MB
Press F3 to toggle | F4 advance time
""" % [
		fps, frame_time_ms,
		time_info,
		total_nodes, sprite_count, polygon_count, particle_count, light_count,
		system_info,
		chunk_info,
		chunk_enemy_info,
		static_mem
	]

	# Position label on right side of screen
	var viewport = get_viewport()
	if viewport:
		var viewport_size = viewport.get_visible_rect().size
		label.position = Vector2(viewport_size.x - 320, 10)

func get_system_node_breakdown() -> String:
	"""Get node counts per major system"""
	var game_world = find_game_world()
	if not game_world:
		return "  GameWorld not found"

	var info = ""
	var accounted_total = 0

	# Collect ALL children with their node counts, sorted by size
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

	# Show top 12 largest children
	var shown = 0
	for data in child_counts:
		if shown >= 12:
			break
		if data.count >= 10:  # Only show if 10+ nodes
			var display_name = data.name
			if display_name.length() > 14:
				display_name = display_name.substr(0, 14)
			info += "  %s: %d\n" % [display_name, data.count]
			accounted_total += data.count
			shown += 1

	# Count remaining small children
	var remaining_count = 0
	for i in range(shown, child_counts.size()):
		remaining_count += child_counts[i].count
	if remaining_count > 0:
		info += "  (other x%d): %d\n" % [child_counts.size() - shown, remaining_count]
		accounted_total += remaining_count

	# Enemies (spawned directly under GameWorld)
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var enemy_nodes = 0
	for enemy in enemies:
		enemy_nodes += count_nodes_recursive(enemy)
	info += "  Enemies(%d): %d\n" % [enemies.size(), enemy_nodes]
	accounted_total += enemy_nodes

	# Player (may be child of GameWorld in multiplayer)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var player_count = count_nodes_recursive(player)
		# Only add if not already counted as GameWorld child
		if player.get_parent() != game_world:
			info += "  Player: %d\n" % player_count
			accounted_total += player_count

	# Calculate totals
	var root = get_tree().root
	var total_nodes = count_nodes_recursive(root)
	var game_world_total = count_nodes_recursive(game_world)
	var outside_gw = total_nodes - game_world_total

	info += "  ─────────────\n"
	info += "  GW Total: %d\n" % game_world_total
	info += "  Outside GW: %d\n" % outside_gw

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
	"""Get chunk system debug information"""
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return "  No player found"

	# Find GameWorld first, then get ChunkBasedPropSystem
	var chunk_system = null

	# GameWorld should be in the main scene
	var root = get_tree().root
	for child in root.get_children():
		var game_world = child.get_node_or_null("GameWorld")
		if game_world:
			chunk_system = game_world.get_node_or_null("ChunkBasedPropSystem")
			if chunk_system:
				break

	if not chunk_system:
		# Try accessing through the game_world variable if it has chunk_prop_system
		for child in root.get_children():
			var game_world = child.get_node_or_null("GameWorld")
			if not game_world:
				# Maybe GameWorld IS the child
				if child.name == "GameWorld":
					game_world = child

			if game_world and game_world.has_method("get") and game_world.get("chunk_prop_system"):
				chunk_system = game_world.chunk_prop_system
				break

	if not chunk_system:
		return "  Chunk system not found (searched all paths)"

	var CHUNK_SIZE = Constants.CHUNK_SIZE
	var player_pos = player.global_position
	var chunk_x = int(floor(player_pos.x / CHUNK_SIZE))
	var chunk_key = "%d" % chunk_x

	# Calculate distances to chunk edges
	var chunk_origin_x = chunk_x * CHUNK_SIZE
	var chunk_end_x = chunk_origin_x + CHUNK_SIZE
	var dist_to_west = player_pos.x - chunk_origin_x
	var dist_to_east = chunk_end_x - player_pos.x

	# Check loaded chunks
	var loaded_chunks = []
	if chunk_system.has_method("get") and chunk_system.get("loaded_chunks"):
		loaded_chunks = chunk_system.loaded_chunks.keys()

	var info = "  Current: [%s] X=%.0f\n" % [chunk_key, player_pos.x]
	info += "  West Edge: %.0fpx %s\n" % [dist_to_west, "⚠️" if dist_to_west < 1000 else ""]
	info += "  East Edge: %.0fpx %s\n" % [dist_to_east, "⚠️" if dist_to_east < 1000 else ""]
	info += "  Loaded: %s" % str(loaded_chunks)

	return info

func get_chunk_enemy_info() -> String:
	"""Get enemy count per chunk from spawn manager with LOD stats"""
	# Find spawn manager
	var game_world = find_game_world()
	if not game_world:
		return "  No GameWorld found"

	var spawn_manager = game_world.get_node_or_null("ChunkAwareSpawnManager")
	if not spawn_manager:
		return "  No SpawnManager found"

	# Get stats from spawn manager
	if not spawn_manager.has_method("get_stats"):
		return "  SpawnManager missing get_stats()"

	var stats = spawn_manager.get_stats()
	var info = ""

	# Sort chunk keys for consistent display
	var chunk_keys = stats.enemies_per_chunk.keys()
	chunk_keys.sort()

	for chunk_key in chunk_keys:
		var count = stats.enemies_per_chunk[chunk_key]
		var target = spawn_manager.ENEMIES_PER_CHUNK if "ENEMIES_PER_CHUNK" in spawn_manager else 60
		info += "  [%s]: %d/%d\n" % [chunk_key, count, target]

	if info.is_empty():
		info = "  No chunks loaded"
	else:
		info += "  Total: %d enemies\n" % stats.total_enemies

		# Add LOD stats
		var lod_stats = get_enemy_lod_stats()
		info += "  LOD: %d full, %d reduced, %d minimal" % [lod_stats.lod_0, lod_stats.lod_1, lod_stats.lod_2]

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
	"""Find the GameWorld node"""
	var root = get_tree().root
	for child in root.get_children():
		var game_world = child.get_node_or_null("GameWorld")
		if game_world:
			return game_world
		if child.name == "GameWorld":
			return child
	return null

func get_time_debug_info() -> String:
	"""Get current game time and period from TimeManager"""
	if not TimeManager:
		return "TimeManager not found"

	var time_str = TimeManager.get_time_string()
	var period = TimeManager.get_period().to_upper()
	var brightness = TimeManager.get_brightness()

	return "%s (%s) | Brightness: %.0f%%" % [time_str, period, brightness * 100]

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
