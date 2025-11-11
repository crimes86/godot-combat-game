@tool
extends EditorScript

## Generates a stonehenge-style ruins sprite matching the wasteland aesthetic
## Run this script from the editor: File > Run

func _run() -> void:
	print("🏛️ Generating ruins sprite...")

	# Create image (larger than props since it's a landmark)
	var width = 256
	var height = 192
	var img = Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)

	# Stone colors (dark gray, weathered)
	var stone_dark = Color(0.2, 0.2, 0.22, 1.0)
	var stone_base = Color(0.28, 0.28, 0.30, 1.0)
	var stone_light = Color(0.35, 0.35, 0.38, 1.0)
	var moss_color = Color(0.2, 0.3, 0.2, 0.6)  # Subtle green moss

	# Center position for stonehenge circle
	var center_x = width / 2
	var base_y = height - 20

	# === BACK STONES (smaller, in background) ===
	# Left back stone
	draw_standing_stone(img, center_x - 70, base_y - 15, 30, 50, stone_dark)
	# Right back stone
	draw_standing_stone(img, center_x + 70, base_y - 15, 30, 50, stone_dark)

	# === SIDE STONES (medium distance) ===
	# Far left stone
	draw_standing_stone(img, center_x - 90, base_y, 35, 70, stone_base)
	# Far right stone
	draw_standing_stone(img, center_x + 90, base_y, 35, 70, stone_base)

	# === FRONT STONES (tallest, most prominent) ===
	# Left pillar
	draw_standing_stone(img, center_x - 50, base_y, 40, 85, stone_light)
	add_moss_texture(img, center_x - 50, base_y - 85, 40, 85, moss_color)

	# Right pillar
	draw_standing_stone(img, center_x + 50, base_y, 40, 85, stone_light)
	add_moss_texture(img, center_x + 50, base_y - 85, 40, 85, moss_color)

	# === LINTEL STONE (horizontal capstone connecting front pillars) ===
	draw_lintel_stone(img, center_x - 50, base_y - 85, 100, 20, stone_light)

	# === FALLEN STONES (broken pieces on ground) ===
	# Left fallen stone
	draw_fallen_stone(img, center_x - 100, base_y + 10, 45, 18, stone_base)
	# Right fallen stone
	draw_fallen_stone(img, center_x + 60, base_y + 15, 50, 16, stone_base)

	# === CENTER ALTAR (sacrificial stone) ===
	draw_altar(img, center_x, base_y - 5, 60, 25, stone_dark)
	add_altar_bloodstain(img, center_x, base_y - 5, 60, 25)

	# === GROUND RUBBLE (scattered small stones) ===
	for i in range(20):
		var rubble_x = center_x + randi_range(-110, 110)
		var rubble_y = base_y + randi_range(-10, 20)
		var rubble_size = randi_range(3, 8)
		draw_rubble(img, rubble_x, rubble_y, rubble_size, stone_dark)

	# Save
	var output_path = "res://assets/environment/wasteland/ruins.png"
	var err = img.save_png(output_path)

	if err == OK:
		print("✅ Ruins sprite saved to: ", output_path)
		print("   Size: %dx%d" % [width, height])
	else:
		print("❌ Failed to save ruins sprite: ", err)

func draw_standing_stone(img: Image, center_x: int, base_y: int, width: int, height: int, color: Color) -> void:
	"""Draw a vertical standing stone pillar"""
	var half_w = width / 2
	var top_y = base_y - height

	# Tapered pillar (slightly narrower at top)
	var top_width = width * 0.85
	var half_top = int(top_width / 2)

	for y in range(top_y, base_y):
		var progress = float(y - top_y) / float(height)
		var current_half_w = lerp(half_top, half_w, progress)

		for x in range(-int(current_half_w), int(current_half_w)):
			var px = center_x + x
			var py = y

			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Add slight shading variation
				var shade_offset = sin(float(y) * 0.3) * 0.05
				var pixel_color = color.lerp(Color.BLACK, shade_offset)
				img.set_pixel(px, py, pixel_color)

	# Add highlights on left edge
	for y in range(top_y, base_y):
		var px = center_x - half_w
		if px >= 0 and px < img.get_width() and y >= 0 and y < img.get_height():
			var highlight = color.lightened(0.15)
			img.set_pixel(px, y, highlight)

func draw_lintel_stone(img: Image, left_x: int, y: int, width: int, height: int, color: Color) -> void:
	"""Draw horizontal capstone connecting two pillars"""
	for dy in range(height):
		for dx in range(width):
			var px = left_x + dx
			var py = y + dy

			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Slightly darker on bottom edge
				var shade = 1.0 if dy < height / 2 else 0.85
				img.set_pixel(px, py, color * shade)

func draw_fallen_stone(img: Image, center_x: int, center_y: int, width: int, height: int, color: Color) -> void:
	"""Draw a fallen/broken stone on the ground"""
	var half_w = width / 2
	var half_h = height / 2

	for y in range(-half_h, half_h):
		for x in range(-half_w, half_w):
			var px = center_x + x
			var py = center_y + y

			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Add jagged edges for broken appearance
				if abs(x) < half_w - 2 or randf() > 0.3:
					var shade = color.darkened(randf() * 0.2)
					img.set_pixel(px, py, shade)

func draw_altar(img: Image, center_x: int, center_y: int, width: int, height: int, color: Color) -> void:
	"""Draw central sacrificial altar stone"""
	var half_w = width / 2
	var half_h = height / 2

	# Flat table-like stone
	for y in range(-half_h, half_h):
		for x in range(-half_w, half_w):
			var px = center_x + x
			var py = center_y + y

			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Top surface lighter, sides darker
				var shade = 1.0 if y < 0 else 0.7
				img.set_pixel(px, py, color * shade)

func add_altar_bloodstain(img: Image, center_x: int, center_y: int, width: int, height: int) -> void:
	"""Add dark bloodstain on altar"""
	var blood_color = Color(0.15, 0.05, 0.05, 0.7)
	var stain_w = width / 3
	var stain_h = height / 3

	for y in range(-stain_h / 2, stain_h / 2):
		for x in range(-stain_w / 2, stain_w / 2):
			var px = center_x + x
			var py = center_y - height / 4 + y

			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				# Irregular stain shape
				var dist = sqrt(float(x * x + y * y))
				if dist < stain_w / 2 and randf() > 0.2:
					var existing = img.get_pixel(px, py)
					img.set_pixel(px, py, existing.lerp(blood_color, 0.6))

func add_moss_texture(img: Image, center_x: int, base_y: int, width: int, height: int, moss_color: Color) -> void:
	"""Add subtle moss/weathering to stone"""
	var half_w = width / 2
	var top_y = base_y

	# Random moss patches
	for i in range(40):
		var mx = center_x + randi_range(-half_w, half_w)
		var my = base_y + randi_range(-height, 0)

		if mx >= 0 and mx < img.get_width() and my >= 0 and my < img.get_height():
			var existing = img.get_pixel(mx, my)
			if existing.a > 0.5:  # Only add moss to stone
				img.set_pixel(mx, my, existing.lerp(moss_color, 0.3))

func draw_rubble(img: Image, x: int, y: int, size: int, color: Color) -> void:
	"""Draw small rubble stone"""
	for dy in range(-size / 2, size / 2):
		for dx in range(-size / 2, size / 2):
			if dx * dx + dy * dy < (size * size) / 4:
				var px = x + dx
				var py = y + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, color.darkened(randf() * 0.2))
