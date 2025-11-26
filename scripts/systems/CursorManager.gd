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

var cursor_image: Image
var cursor_texture: ImageTexture
var cursor_pressed_texture: ImageTexture
var is_pressed: bool = false

func _ready():
	create_arrowhead_cursor()
	create_pressed_cursor()
	apply_cursor()

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not is_pressed:
				is_pressed = true
				apply_pressed_cursor()
			elif not event.pressed and is_pressed:
				is_pressed = false
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

func reset_cursor():
	Input.set_custom_mouse_cursor(null)
