extends Node
# CursorManager.gd - Custom cursor system

# Stone gray color palette (matching UI theme)
const CURSOR_COLOR_DARK = Color(0.35, 0.35, 0.38, 1.0)    # Dark stone gray
const CURSOR_COLOR_LIGHT = Color(0.55, 0.55, 0.58, 1.0)   # Light stone gray
const CURSOR_COLOR_OUTLINE = Color(0.15, 0.15, 0.18, 1.0) # Dark outline

# Pressed variant - darker
const CURSOR_COLOR_PRESSED = Color(0.2, 0.2, 0.22, 1.0)   # Darker stone gray
const CURSOR_COLOR_PRESSED_HIGHLIGHT = Color(0.35, 0.35, 0.38, 1.0)  # Darker highlight
const CURSOR_COLOR_PRESSED_OUTLINE = Color(0.08, 0.08, 0.1, 1.0)     # Darker outline

# Sword cursor colors - reddish tint for combat
const SWORD_COLOR_BLADE = Color(0.7, 0.7, 0.75, 1.0)      # Steel blade
const SWORD_COLOR_EDGE = Color(0.85, 0.85, 0.9, 1.0)      # Bright edge highlight
const SWORD_COLOR_HANDLE = Color(0.4, 0.25, 0.15, 1.0)    # Brown handle
const SWORD_COLOR_GUARD = Color(0.6, 0.55, 0.3, 1.0)      # Gold guard
const SWORD_COLOR_OUTLINE = Color(0.1, 0.1, 0.12, 1.0)    # Dark outline

var cursor_image: Image
var cursor_texture: ImageTexture
var cursor_pressed_texture: ImageTexture
var sword_cursor_texture: ImageTexture
var is_pressed: bool = false

# Enemy detection for sword cursor
var current_cursor_mode: String = "arrow"  # "arrow" or "sword"
var check_timer: float = 0.0
const CHECK_INTERVAL: float = 0.05  # Check 20 times per second (performant)

func _ready():
	# Skip all cursor operations in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return

	create_arrowhead_cursor()
	create_pressed_cursor()
	create_sword_cursor()
	apply_cursor()

func _process(delta: float) -> void:
	# Throttle enemy detection checks for performance
	check_timer += delta
	if check_timer < CHECK_INTERVAL:
		return
	check_timer = 0.0

	# Check if mouse is over an attackable enemy
	var is_over_enemy = check_enemy_under_cursor()

	# Update cursor if mode changed
	if is_over_enemy and current_cursor_mode != "sword":
		current_cursor_mode = "sword"
		apply_sword_cursor()
	elif not is_over_enemy and current_cursor_mode != "arrow":
		current_cursor_mode = "arrow"
		if is_pressed:
			apply_pressed_cursor()
		else:
			apply_cursor()

func check_enemy_under_cursor() -> bool:
	"""Check if there's an attackable enemy under the mouse cursor"""
	# Get the current viewport and camera
	var viewport = get_viewport()
	if not viewport:
		return false

	var camera = viewport.get_camera_2d()
	if not camera:
		return false

	# Convert screen position to world position
	var mouse_screen_pos = viewport.get_mouse_position()
	# Simpler conversion: screen pos relative to camera
	var camera_offset = mouse_screen_pos - viewport.get_visible_rect().size / 2
	var mouse_world_pos = camera.global_position + camera_offset / camera.zoom

	# Check enemies group
	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		# Skip dead/corpse enemies
		if enemy.get("is_corpse") or enemy.get("is_dying"):
			continue

		# Check if mouse is within enemy's clickable area (roughly 40px radius)
		var distance = mouse_world_pos.distance_to(enemy.global_position)
		if distance < 40.0:
			return true

	# Also check training dummy (separate group)
	var training_dummies = get_tree().get_nodes_in_group("training_dummy")
	for dummy in training_dummies:
		if not is_instance_valid(dummy):
			continue

		# Training dummy click area is offset by -32 on Y (to center on sprite)
		# Use a larger vertical hitbox to cover the full dummy (head to feet)
		var dummy_center = dummy.global_position + Vector2(0, -32)  # Match click area offset
		var distance = mouse_world_pos.distance_to(dummy_center)
		if distance < 55.0:  # Larger radius to cover full dummy height
			return true

	# Check for active weakpoints (crit window targets) - these have larger hitboxes
	var weakpoints = get_tree().get_nodes_in_group("weakpoints")
	for wp in weakpoints:
		if not is_instance_valid(wp):
			continue
		# Skip destroyed weakpoints
		if wp.get("is_destroyed"):
			continue

		# Weakpoints have forgiving hitboxes (35px at level 1, smaller at higher levels)
		var distance = mouse_world_pos.distance_to(wp.global_position)
		if distance < 40.0:
			return true

	return false

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not is_pressed:
				is_pressed = true
				if current_cursor_mode == "arrow":
					apply_pressed_cursor()
			elif not event.pressed and is_pressed:
				is_pressed = false
				if current_cursor_mode == "arrow":
					apply_cursor()

func create_arrowhead_cursor():
	# Create a 32x32 cursor image
	var size = 32
	cursor_image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Clean, simple arrowhead pointer shape - elongated tip
	# Standard cursor arrow - longer pointed tip
	var arrow_points = [
		Vector2(1, 1),    # Tip (at top-left)
		Vector2(6, 24),   # Bottom of left edge (pulled down/back from tip)
		Vector2(10, 18),  # Left notch
		Vector2(14, 26),  # Tail left
		Vector2(18, 20),  # Tail right
		Vector2(13, 15),  # Right notch
		Vector2(18, 6),   # Top right edge (pulled back from tip)
	]

	# Draw outline first (slightly thicker for definition)
	_draw_polygon_outline(arrow_points, CURSOR_COLOR_OUTLINE, 2)

	# Draw the main cursor body
	_draw_filled_polygon(arrow_points, CURSOR_COLOR_DARK)

	# Add subtle inner highlight along left edge for depth
	var highlight_points = [
		Vector2(4, 6),
		Vector2(7, 17),
		Vector2(9, 14),
		Vector2(8, 6),
	]
	_draw_filled_polygon(highlight_points, CURSOR_COLOR_LIGHT)

	# Create texture from image
	cursor_texture = ImageTexture.create_from_image(cursor_image)

func create_pressed_cursor():
	# Create a 32x32 cursor image for pressed state
	var size = 32
	cursor_image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Same shape as normal cursor
	var arrow_points = [
		Vector2(1, 1),    # Tip (at top-left)
		Vector2(6, 24),   # Bottom of left edge
		Vector2(10, 18),  # Left notch
		Vector2(14, 26),  # Tail left
		Vector2(18, 20),  # Tail right
		Vector2(13, 15),  # Right notch
		Vector2(18, 6),   # Top right edge
	]

	# Draw outline first (darker)
	_draw_polygon_outline(arrow_points, CURSOR_COLOR_PRESSED_OUTLINE, 2)

	# Draw the main cursor body (darker)
	_draw_filled_polygon(arrow_points, CURSOR_COLOR_PRESSED)

	# Add subtle inner highlight (darker)
	var highlight_points = [
		Vector2(4, 6),
		Vector2(7, 17),
		Vector2(9, 14),
		Vector2(8, 6),
	]
	_draw_filled_polygon(highlight_points, CURSOR_COLOR_PRESSED_HIGHLIGHT)

	# Create texture from image
	cursor_pressed_texture = ImageTexture.create_from_image(cursor_image)

func create_sword_cursor():
	# Create a 32x32 cursor image for sword/attack cursor
	var size = 32
	cursor_image = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Sword pointing diagonally (top-left to bottom-right) - tip at top-left for hotspot
	# Blade shape - elongated diamond pointing to top-left
	var blade_points = [
		Vector2(2, 2),    # Tip (hotspot)
		Vector2(6, 10),   # Left edge of blade
		Vector2(18, 22),  # Base of blade (near guard)
		Vector2(22, 18),  # Right edge of blade
	]

	# Guard (crossguard) - perpendicular to blade at the base
	var guard_points = [
		Vector2(14, 24),  # Left end of guard
		Vector2(16, 20),  # Left inner
		Vector2(24, 16),  # Right inner
		Vector2(26, 20),  # Right end of guard
		Vector2(24, 22),  # Right outer
		Vector2(16, 26),  # Left outer
	]

	# Handle/grip
	var handle_points = [
		Vector2(20, 24),  # Top of handle
		Vector2(22, 22),  # Top right
		Vector2(28, 28),  # Bottom right
		Vector2(26, 30),  # Bottom
		Vector2(24, 28),  # Bottom left
		Vector2(18, 26),  # Top left
	]

	# Draw outline first
	_draw_polygon_outline(blade_points, SWORD_COLOR_OUTLINE, 2)
	_draw_polygon_outline(guard_points, SWORD_COLOR_OUTLINE, 1)
	_draw_polygon_outline(handle_points, SWORD_COLOR_OUTLINE, 1)

	# Draw handle (back layer)
	_draw_filled_polygon(handle_points, SWORD_COLOR_HANDLE)

	# Draw guard
	_draw_filled_polygon(guard_points, SWORD_COLOR_GUARD)

	# Draw blade
	_draw_filled_polygon(blade_points, SWORD_COLOR_BLADE)

	# Add edge highlight along the blade
	var edge_points = [
		Vector2(3, 3),
		Vector2(5, 8),
		Vector2(16, 19),
		Vector2(19, 16),
		Vector2(8, 5),
	]
	_draw_filled_polygon(edge_points, SWORD_COLOR_EDGE)

	# Create texture from image
	sword_cursor_texture = ImageTexture.create_from_image(cursor_image)

func _draw_filled_polygon(points: Array, color: Color):
	if points.size() < 3:
		return

	# Simple scanline fill algorithm
	var min_y = 999
	var max_y = 0
	for p in points:
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))

	for y in range(min_y, max_y + 1):
		var intersections = []
		var n = points.size()
		for i in range(n):
			var p1 = points[i]
			var p2 = points[(i + 1) % n]

			if (p1.y <= y and p2.y > y) or (p2.y <= y and p1.y > y):
				var x = p1.x + (y - p1.y) / (p2.y - p1.y) * (p2.x - p1.x)
				intersections.append(x)

		intersections.sort()

		for i in range(0, intersections.size() - 1, 2):
			var x_start = int(intersections[i])
			var x_end = int(intersections[i + 1])
			for x in range(x_start, x_end + 1):
				if x >= 0 and x < cursor_image.get_width() and y >= 0 and y < cursor_image.get_height():
					cursor_image.set_pixel(x, y, color)

func _draw_polygon_outline(points: Array, color: Color, thickness: int = 1):
	var n = points.size()
	for i in range(n):
		var p1 = points[i]
		var p2 = points[(i + 1) % n]
		_draw_line(p1, p2, color, thickness)

func _draw_line(from: Vector2, to: Vector2, color: Color, thickness: int = 1):
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var sx = 1 if from.x < to.x else -1
	var sy = 1 if from.y < to.y else -1
	var err = dx - dy

	var x = int(from.x)
	var y = int(from.y)
	var end_x = int(to.x)
	var end_y = int(to.y)

	while true:
		# Draw pixel with thickness
		for tx in range(-thickness + 1, thickness):
			for ty in range(-thickness + 1, thickness):
				var px = x + tx
				var py = y + ty
				if px >= 0 and px < cursor_image.get_width() and py >= 0 and py < cursor_image.get_height():
					cursor_image.set_pixel(px, py, color)

		if x == end_x and y == end_y:
			break

		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

func apply_cursor():
	if cursor_texture:
		# Hotspot at top-left (tip of the arrow)
		Input.set_custom_mouse_cursor(cursor_texture, Input.CURSOR_ARROW, Vector2(0, 0))

func apply_pressed_cursor():
	if cursor_pressed_texture:
		Input.set_custom_mouse_cursor(cursor_pressed_texture, Input.CURSOR_ARROW, Vector2(0, 0))

func apply_sword_cursor():
	if sword_cursor_texture:
		# Hotspot at top-left (tip of the sword blade)
		Input.set_custom_mouse_cursor(sword_cursor_texture, Input.CURSOR_ARROW, Vector2(2, 2))

func reset_cursor():
	Input.set_custom_mouse_cursor(null)
