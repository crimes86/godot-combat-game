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
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
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

	# Count particles
	var particle_count = 0
	var particles = get_all_nodes_of_type(root, CPUParticles2D)
	for p in particles:
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
	var total_mem = OS.get_static_memory_usage() / 1024.0 / 1024.0

	# Physics bodies
	var physics_2d_active = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES).size()

	# Draw calls (objects rendered)
	var draw_calls = total_nodes  # Approximate

	# Get chunk-based enemy counts
	var chunk_enemy_info = get_chunk_enemy_info()

	var color = Color.GREEN
	if fps < 30:
		color = Color.RED
	elif fps < 50:
		color = Color.YELLOW
	label.add_theme_color_override("font_color", color)

	# Get chunk info
	var chunk_info = get_chunk_debug_info()

	label.text = """FPS: %d (%.1f ms/frame)
━━━━━━━━━━━━━━━━━━━━━━
SCENE:
  Total Nodes: %d
  Enemies: %d
  Campfires: %d
━━━━━━━━━━━━━━━━━━━━━━
RENDERING:
  Sprites: %d
  Polygons: %d
  Particles: %d (active)
  Lights: %d
━━━━━━━━━━━━━━━━━━━━━━
MEMORY:
  Usage: %.1f MB
━━━━━━━━━━━━━━━━━━━━━━
CHUNKS:
%s
━━━━━━━━━━━━━━━━━━━━━━
ENEMIES PER CHUNK:
%s
━━━━━━━━━━━━━━━━━━━━━━
Press F3 to toggle
""" % [
		fps, frame_time_ms,
		total_nodes, enemies.size(), campfires.size(),
		sprite_count, polygon_count, particle_count, light_count,
		static_mem,
		chunk_info,
		chunk_enemy_info
	]

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

	const CHUNK_SIZE = 3000.0
	var player_pos = player.global_position
	var chunk_x = int(floor(player_pos.x / CHUNK_SIZE))
	var chunk_key = "%d,0" % chunk_x

	# Calculate distances
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
	"""Get enemy count per chunk from spawn manager"""
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
		info += "  Total: %d enemies" % stats.total_enemies

	return info

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
	if debug_draw_container and is_instance_valid(debug_draw_container):
		debug_draw_container.queue_free()
		debug_draw_container = null
	chunk_boundary_lines.clear()
	enemy_debug_circles.clear()

func draw_chunk_boundaries() -> void:
	"""Draw vertical lines at chunk boundaries"""
	if not debug_draw_container:
		return

	const CHUNK_SIZE = 3000.0
	const WORLD_MIN_X = -5000.0
	const WORLD_MAX_X = 13000.0
	const WORLD_MIN_Y = -3000.0
	const WORLD_MAX_Y = 3000.0

	# Calculate chunk boundaries
	var start_chunk = int(floor(WORLD_MIN_X / CHUNK_SIZE))
	var end_chunk = int(ceil(WORLD_MAX_X / CHUNK_SIZE))

	for chunk_x in range(start_chunk, end_chunk + 1):
		var boundary_x = chunk_x * CHUNK_SIZE

		# Create vertical line at chunk boundary
		var line = Line2D.new()
		line.name = "ChunkBoundary_%d" % chunk_x
		line.width = 4.0
		line.default_color = Color(1, 0, 1, 0.7)  # Magenta for visibility
		line.add_point(Vector2(boundary_x, WORLD_MIN_Y))
		line.add_point(Vector2(boundary_x, WORLD_MAX_Y))
		line.z_index = 999
		debug_draw_container.add_child(line)
		chunk_boundary_lines.append(line)

		# Add label showing chunk ID
		var chunk_label = Label.new()
		chunk_label.text = "Chunk %d,0" % chunk_x
		chunk_label.position = Vector2(boundary_x + 50, -2900)
		chunk_label.add_theme_font_size_override("font_size", 24)
		chunk_label.add_theme_color_override("font_color", Color(1, 0, 1, 1))
		chunk_label.add_theme_color_override("font_outline_color", Color.BLACK)
		chunk_label.add_theme_constant_override("outline_size", 4)
		chunk_label.z_index = 999
		debug_draw_container.add_child(chunk_label)

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
