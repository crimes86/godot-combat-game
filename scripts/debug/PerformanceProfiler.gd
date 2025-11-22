extends CanvasLayer

## Deep Performance Profiler
## Shows exactly what's eating CPU time

var label: Label
var update_timer: float = 0.0

# Performance tracking
var frame_times: Dictionary = {}
var sample_count: int = 0

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

	var color = Color.GREEN
	if fps < 30:
		color = Color.RED
	elif fps < 50:
		color = Color.YELLOW
	label.add_theme_color_override("font_color", color)

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
Press F3 to toggle
""" % [
		fps, frame_time_ms,
		total_nodes, enemies.size(), campfires.size(),
		sprite_count, polygon_count, particle_count, light_count,
		static_mem
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

func _on_debug_toggled(is_visible: bool) -> void:
	"""Called when F3 debug display is toggled"""
	visible = is_visible
