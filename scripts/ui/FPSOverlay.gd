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

	# Count enemies by LOD level
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var lod_counts = {
		"full": 0,
		"medium": 0,
		"low": 0,
		"placeholder": 0,
		"culled": 0
	}

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		if enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			match ai.current_lod:
				0: lod_counts["full"] += 1  # FULL
				1: lod_counts["medium"] += 1  # MEDIUM
				2: lod_counts["low"] += 1  # LOW
				3: lod_counts["placeholder"] += 1  # PLACEHOLDER
				4: lod_counts["culled"] += 1  # CULLED

	stats_label.text = "Enemies: %d | Full:%d Med:%d Low:%d Place:%d Cull:%d" % [
		enemies.size(),
		lod_counts["full"],
		lod_counts["medium"],
		lod_counts["low"],
		lod_counts["placeholder"],
		lod_counts["culled"]
	]
