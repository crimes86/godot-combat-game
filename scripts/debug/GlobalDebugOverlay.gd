extends CanvasLayer
## Global debug overlay - central hub for all debug info across all scenes
## Toggled with F3 via Constants.debug_display_toggled signal
## Other systems can register data providers via register_section()

var debug_label: Label
var is_visible: bool = false

# Registered debug sections from other systems
# Key: section_name, Value: Callable that returns String
var _debug_sections: Dictionary = {}

func _ready() -> void:
	# High layer so it's always on top
	layer = 100

	# Create the debug label
	debug_label = Label.new()
	debug_label.name = "DebugLabel"

	# Position at top-right corner
	debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	debug_label.anchor_left = 1.0
	debug_label.anchor_right = 1.0
	debug_label.offset_left = -400
	debug_label.offset_right = -10
	debug_label.offset_top = 10
	debug_label.offset_bottom = 600

	# Styling
	debug_label.add_theme_font_size_override("font_size", 12)
	debug_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.5, 0.9))
	debug_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	debug_label.add_theme_constant_override("shadow_offset_x", 1)
	debug_label.add_theme_constant_override("shadow_offset_y", 1)
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	add_child(debug_label)

	# Start hidden
	debug_label.visible = false

	# Connect to F3 toggle
	if Constants:
		Constants.debug_display_toggled.connect(_on_debug_toggled)
		# Sync with current state
		is_visible = Constants.debug_display_visible
		debug_label.visible = is_visible

	print("[GlobalDebugOverlay] Initialized - F3 to toggle")

func _on_debug_toggled(visible: bool) -> void:
	is_visible = visible
	debug_label.visible = visible

## Register a debug section that will be displayed when F3 is active
## section_name: Unique identifier for this section
## data_provider: Callable that returns a String with the debug info
func register_section(section_name: String, data_provider: Callable) -> void:
	_debug_sections[section_name] = data_provider
	print("[GlobalDebugOverlay] Registered section: %s" % section_name)

## Unregister a debug section
func unregister_section(section_name: String) -> void:
	_debug_sections.erase(section_name)

func _process(_delta: float) -> void:
	if not is_visible:
		return

	# Check if PerformanceProfiler is active - if so, hide ourselves to avoid overlap
	var profiler = _find_performance_profiler()
	if profiler and profiler.visible:
		debug_label.visible = false
		return
	else:
		debug_label.visible = true

	# Build debug text starting with core info
	var text = _build_core_debug_info()

	# Add registered sections
	for section_name in _debug_sections:
		var provider = _debug_sections[section_name]
		if provider.is_valid():
			var section_text = provider.call()
			if section_text and section_text.length() > 0:
				text += "\n" + section_text

	debug_label.text = text

func _find_performance_profiler() -> Node:
	"""Find PerformanceProfiler if it exists in the scene"""
	var root = get_tree().root
	for child in root.get_children():
		var profiler = child.get_node_or_null("PerformanceProfiler")
		if profiler:
			return profiler
		# Check if child itself is the profiler's parent scene
		for grandchild in child.get_children():
			if grandchild.name == "PerformanceProfiler" or grandchild.get_script() and "PerformanceProfiler" in str(grandchild.get_script().resource_path):
				return grandchild
	return null

func _build_core_debug_info() -> String:
	# Get cursor world position
	var mouse_screen = get_viewport().get_mouse_position()
	var mouse_world = Vector2.ZERO

	# Find camera to convert screen to world coords
	var camera = get_viewport().get_camera_2d()
	if camera:
		mouse_world = camera.get_global_mouse_position()
	else:
		# Fallback: try to find player's camera
		var player = get_tree().get_first_node_in_group("player")
		if player:
			var player_camera = player.get_node_or_null("Camera2D")
			if player_camera:
				mouse_world = player_camera.get_global_mouse_position()

	# Get player position
	var player_pos = Vector2.ZERO
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player_pos = player.global_position

	# Get current scene name
	var scene_name = "Unknown"
	var current_scene = get_tree().current_scene
	if current_scene:
		scene_name = current_scene.name

	# Calculate chunk (if in game world)
	var chunk_x = int(floor(player_pos.x / 8000.0))
	var chunk_y = int(floor(player_pos.y / 8000.0))

	# Build core debug text
	var text = ""
	text += "═══ DEBUG [F3] ═══\n"
	text += "Scene: %s\n" % scene_name
	text += "FPS: %d\n" % Engine.get_frames_per_second()
	text += "─────────────────\n"
	text += "Player: (%.0f, %.0f)\n" % [player_pos.x, player_pos.y]
	text += "Chunk: (%d, %d)\n" % [chunk_x, chunk_y]
	text += "─────────────────\n"
	text += "Cursor World: (%.0f, %.0f)\n" % [mouse_world.x, mouse_world.y]
	text += "Cursor Screen: (%.0f, %.0f)\n" % [mouse_screen.x, mouse_screen.y]

	return text
