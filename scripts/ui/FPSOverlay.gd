extends CanvasLayer
class_name FPSOverlay

## Simple FPS and performance monitoring overlay
## Shows FPS, enemy count, and LOD statistics

var fps_label: Label
var stats_label: Label
var update_timer: float = 0.0
var update_interval: float = 0.5  # Update twice per second

func _ready() -> void:
	layer = 1000  # Draw on top

	# Create FPS label
	fps_label = Label.new()
	fps_label.position = Vector2(10, 10)
	fps_label.add_theme_font_size_override("font_size", 16)
	fps_label.add_theme_color_override("font_color", Color.GREEN)
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 2)
	add_child(fps_label)

	# Create stats label
	stats_label = Label.new()
	stats_label.position = Vector2(10, 35)
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color.YELLOW)
	stats_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stats_label.add_theme_constant_override("outline_size", 2)
	add_child(stats_label)

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_fps_display()

func update_fps_display() -> void:
	var fps = Engine.get_frames_per_second()

	# Color-code FPS
	if fps >= 55:
		fps_label.add_theme_color_override("font_color", Color.GREEN)
	elif fps >= 30:
		fps_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		fps_label.add_theme_color_override("font_color", Color.RED)

	fps_label.text = "FPS: %d" % fps

	# Count total enemies
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)

	# Get chunk count from spawn manager
	var chunk_count = 0
	var root = get_tree().root
	for child in root.get_children():
		var game_world = child.get_node_or_null("GameWorld")
		if game_world:
			var spawn_manager = game_world.get_node_or_null("ChunkAwareSpawnManager")
			if spawn_manager and spawn_manager.has_method("get_stats"):
				var stats = spawn_manager.get_stats()
				chunk_count = stats.total_chunks
			break

	stats_label.text = "Enemies: %d | Chunks: %d" % [enemies.size(), chunk_count]
