extends Node

## ItemIconGenerator - Extracts inventory icons from LPC sprite sheets
## Uses the south-facing idle frame (row 2, frame 0) for equipment icons

# Cache for generated icons
var icon_cache: Dictionary = {}  # sprite_path -> ImageTexture

# LPC sprite sheet layout
const FRAME_SIZE = 64
const IDLE_FRAME = 0  # First frame is idle/standing pose

# Direction rows in LPC walk sprite sheets (9 columns, 4 rows)
const DIR_UP = 0     # North/back-facing
const DIR_LEFT = 1   # West-facing
const DIR_DOWN = 2   # South/front-facing
const DIR_RIGHT = 3  # East-facing

# Best facing direction per equipment slot for clearest icon visibility
const SLOT_DIRECTIONS = {
	"chest": DIR_DOWN,    # Front shows the shirt design
	"legs": DIR_DOWN,     # Front shows pants
	"feet": DIR_DOWN,     # Front shows boots
	"head": DIR_RIGHT,    # Side profile shows helmet shape better
	"hands": DIR_DOWN,    # Front shows gloves
	"arms": DIR_RIGHT,    # Side shows arm guards/bracers better
	"weapon": DIR_RIGHT,  # Side shows weapon shape clearly
	"tool": DIR_RIGHT,    # Side shows tool shape
	"default": DIR_DOWN   # Fallback to front-facing
}

# Icon display settings
const ICON_SIZE = 48  # Size to display in inventory slots
const ICON_PADDING = 8  # Crop padding from edges to focus on the item

func _ready() -> void:
	print("🖼️ ItemIconGenerator initialized")

func get_item_icon(item: Dictionary) -> Texture2D:
	"""Get or generate an icon for an inventory item"""
	if item.is_empty():
		return null

	var item_type = item.get("type", "")
	var item_name = item.get("name", "")
	var sprite_name = item.get("sprite_name", "")
	var slot = item.get("slot", "")

	# Handle materials with procedural icons
	# Also check for known material names even if type isn't set
	var known_materials = ["Bone Ember", "Dry Log", "Ancient Skull", "Cursed Femur", "Lich's Finger Bone",
		"Old Bones", "Broken Sword", "Tarnished Ring", "Dusty Gem", "Ancient Coin"]
	if item_type == "material" or item_name in known_materials:
		var cache_key = "material:%s" % item_name
		if icon_cache.has(cache_key):
			return icon_cache[cache_key]
		var icon = _generate_material_icon(item_name, item)
		if icon:
			icon_cache[cache_key] = icon
		return icon

	# Handle placeables with procedural icons
	if item_type == "placeable":
		var placeable_type = item.get("placeable_type", "")
		var cache_key = "placeable:%s" % placeable_type
		if icon_cache.has(cache_key):
			return icon_cache[cache_key]
		var icon = _generate_placeable_icon(placeable_type, item)
		if icon:
			icon_cache[cache_key] = icon
		return icon

	# Determine the sprite path based on item type
	var sprite_path = _get_sprite_path(item_type, sprite_name, item)
	if sprite_path.is_empty():
		return null

	# Determine best facing direction for this item
	var direction = _get_direction_for_item(item_type, slot)

	# Create cache key including direction and slot (for half-crop variants)
	var cache_key = "%s:%d:%s" % [sprite_path, direction, slot]

	# Check cache first
	if icon_cache.has(cache_key):
		return icon_cache[cache_key]

	# Generate the icon
	var icon = _generate_icon_from_sprite(sprite_path, direction, slot)
	if icon:
		icon_cache[cache_key] = icon

	return icon

func _get_direction_for_item(item_type: String, slot: String) -> int:
	"""Determine the best facing direction for an item's icon"""
	# Check slot first (more specific)
	if SLOT_DIRECTIONS.has(slot):
		return SLOT_DIRECTIONS[slot]

	# Check item type
	if item_type == "weapon":
		return SLOT_DIRECTIONS["weapon"]
	elif item_type == "tool":
		return SLOT_DIRECTIONS["tool"]

	# Default to front-facing
	return SLOT_DIRECTIONS["default"]

func _get_sprite_path(item_type: String, sprite_name: String, item: Dictionary) -> String:
	"""Determine the sprite sheet path for an item"""
	match item_type:
		"armor":
			# Armor requires sprite_name
			if sprite_name.is_empty():
				return ""
			var slot = item.get("slot", "")
			match slot:
				"chest":
					return "res://assets/characters/shirt/%s_walk.png" % sprite_name
				"legs":
					return "res://assets/characters/pants/%s_walk.png" % sprite_name
				"feet":
					return "res://assets/characters/boots/%s_walk.png" % sprite_name
				"head":
					return "res://assets/characters/head/%s_walk.png" % sprite_name
				"hands":
					return "res://assets/characters/hands/%s_walk.png" % sprite_name
				"arms":
					return "res://assets/characters/arms/%s_walk.png" % sprite_name
		"weapon":
			# Weapons use walk.png for cleaner icons (consistent 64x64 tiles)
			var weapon_type = item.get("weapon_type", "sword")
			# For daggers with "standard" subfolder
			if weapon_type == "dagger":
				return "res://assets/weapons/dagger/standard/walk.png"
			# All weapons use walk sprite for consistent icon extraction
			return "res://assets/weapons/%s/walk.png" % weapon_type
		"tool":
			# Tools use the format: assets/tools/{tool_type}/walk.png
			var tool_type = item.get("tool_type", "")
			if tool_type == "axe":
				return "res://assets/tools/axe/walk.png"
			elif tool_type == "pickaxe":
				return "res://assets/tools/pickaxe/walk.png"
		"placeable":
			# Placeables use direct sprite_path or have a specific icon
			var sprite_path = item.get("sprite_path", "")
			if sprite_path != "":
				return sprite_path
			# Fallback for known placeables
			var placeable_type = item.get("placeable_type", "")
			if placeable_type == "campfire":
				return "res://assets/ui/icons/campfire_kit.png"

	return ""

func _generate_icon_from_sprite(sprite_path: String, direction: int = DIR_DOWN, slot: String = "") -> ImageTexture:
	"""Extract a single frame from sprite sheet and create an icon texture"""
	# Load the sprite sheet
	var texture = load(sprite_path) as Texture2D
	if not texture:
		print("⚠️ ItemIconGenerator: Could not load sprite: %s" % sprite_path)
		return null

	var img = texture.get_image()
	if not img:
		return null

	# Determine frame size based on sprite sheet layout
	var sheet_width = img.get_width()
	var sheet_height = img.get_height()
	var frame_width = FRAME_SIZE
	var frame_height = FRAME_SIZE

	# LPC sprites always use 64x64 tiles regardless of sheet dimensions
	# Some exports may have extra blank columns but tiles are always 64x64
	frame_width = 64
	frame_height = 64

	# Use idle frame (frame 0) for all weapons
	var frame_col = IDLE_FRAME

	# Extract frame at specified direction row
	var src_x = frame_col * frame_width
	var src_y = direction * frame_height

	# Make sure we don't go out of bounds
	if src_x + frame_width > sheet_width or src_y + frame_height > sheet_height:
		print("⚠️ ItemIconGenerator: Frame out of bounds for %s" % sprite_path)
		return null

	# Create new image for the icon
	var icon_img = Image.create(frame_width, frame_height, false, Image.FORMAT_RGBA8)
	icon_img.blit_rect(img, Rect2i(src_x, src_y, frame_width, frame_height), Vector2i(0, 0))

	# Staff uses walk sprite which is already correctly oriented, no rotation needed

	# For hands and feet, crop to just the right side (single glove/boot looks cleaner)
	if slot in ["hands", "feet"]:
		var half_width = frame_width / 2
		var half_img = Image.create(half_width, frame_height, false, Image.FORMAT_RGBA8)
		# Take the right half of the image (character's left side = our right)
		half_img.blit_rect(icon_img, Rect2i(half_width, 0, half_width, frame_height), Vector2i(0, 0))
		icon_img = half_img

	# Optionally crop to focus on the item (remove empty space)
	var cropped = _auto_crop_image(icon_img)
	if cropped:
		icon_img = cropped

	# Create texture from image
	var icon_texture = ImageTexture.create_from_image(icon_img)
	return icon_texture

func _rotate_image_90_cw(img: Image) -> Image:
	"""Rotate an image 90 degrees clockwise"""
	var width = img.get_width()
	var height = img.get_height()
	var rotated = Image.create(height, width, false, Image.FORMAT_RGBA8)

	for y in range(height):
		for x in range(width):
			var pixel = img.get_pixel(x, y)
			# 90 degrees clockwise: (x, y) -> (height - 1 - y, x)
			rotated.set_pixel(height - 1 - y, x, pixel)

	return rotated

func _auto_crop_image(img: Image) -> Image:
	"""Crop transparent edges from image to focus on the actual content"""
	var width = img.get_width()
	var height = img.get_height()

	var min_x = width
	var min_y = height
	var max_x = 0
	var max_y = 0

	# Find bounding box of non-transparent pixels
	for y in range(height):
		for x in range(width):
			var pixel = img.get_pixel(x, y)
			if pixel.a > 0.1:  # Not fully transparent
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)

	# If no content found, return original
	if max_x <= min_x or max_y <= min_y:
		return null

	# Add small padding
	var padding = 2
	min_x = max(0, min_x - padding)
	min_y = max(0, min_y - padding)
	max_x = min(width - 1, max_x + padding)
	max_y = min(height - 1, max_y + padding)

	var crop_width = max_x - min_x + 1
	var crop_height = max_y - min_y + 1

	# Create cropped image
	var cropped = Image.create(crop_width, crop_height, false, Image.FORMAT_RGBA8)
	cropped.blit_rect(img, Rect2i(min_x, min_y, crop_width, crop_height), Vector2i(0, 0))

	return cropped

func clear_cache() -> void:
	"""Clear the icon cache (call when sprites change)"""
	icon_cache.clear()

func _generate_material_icon(item_name: String, item: Dictionary) -> ImageTexture:
	"""Generate a simple procedural icon for material items"""
	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	# Define colors and shapes based on item name
	match item_name:
		"Bone Ember":
			_draw_bone_ember(img, size)
		"Dry Log":
			_draw_log(img, size)
		"Ancient Skull":
			_draw_skull(img, size)
		"Cursed Femur":
			_draw_bone(img, size, Color(0.6, 0.3, 0.5))  # Purple tint
		"Lich's Finger Bone":
			_draw_finger_bone(img, size)
		"Old Bones":
			_draw_bone(img, size, Color(1.0, 1.0, 1.0))  # White/grey bones
		"Broken Sword":
			_draw_broken_sword(img, size)
		"Tarnished Ring":
			_draw_ring(img, size)
		"Dusty Gem":
			_draw_gem(img, size, Color(0.4, 0.6, 0.9))  # Blue gem
		"Ancient Coin":
			_draw_coin(img, size)
		_:
			# Generic material icon
			_draw_generic_material(img, size, item)

	return ImageTexture.create_from_image(img)

func _draw_bone_ember(img: Image, size: int) -> void:
	"""Draw a glowing bone ember icon"""
	var center = size / 2
	var bone_color = Color(0.9, 0.85, 0.75, 1.0)
	var ember_color = Color(1.0, 0.5, 0.1, 1.0)
	var dark = Color(0.3, 0.25, 0.2, 1.0)

	# Outer glow (orange)
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < 14:
				var alpha = (1.0 - dist / 14.0) * 0.35
				img.set_pixel(x, y, Color(1.0, 0.4, 0.1, alpha))

	# Bone shape - simple vertical bone
	_draw_ellipse(img, center, center - 5, 4, 3, bone_color)  # Top knob
	_draw_ellipse(img, center, center + 5, 4, 3, bone_color)  # Bottom knob
	# Shaft
	for y in range(center - 4, center + 5):
		for x in range(center - 2, center + 3):
			img.set_pixel(x, y, bone_color)

	# Ember glow cracks
	img.set_pixel(center - 1, center - 2, ember_color)
	img.set_pixel(center, center, ember_color)
	img.set_pixel(center + 1, center + 2, ember_color)
	img.set_pixel(center, center + 3, ember_color)

func _draw_log(img: Image, size: int) -> void:
	"""Draw a wooden log icon"""
	var brown = Color(0.55, 0.35, 0.2, 1.0)
	var dark_brown = Color(0.35, 0.22, 0.12, 1.0)
	var light_brown = Color(0.7, 0.5, 0.3, 1.0)

	# Main log body (horizontal)
	for y in range(10, 22):
		for x in range(4, 28):
			var dist_from_center = abs(y - 16)
			if dist_from_center < 6:
				img.set_pixel(x, y, brown)

	# Log end (circle on right)
	_draw_ellipse(img, 24, 16, 6, 6, light_brown)
	_draw_ellipse(img, 24, 16, 4, 4, dark_brown)  # Tree rings
	_draw_ellipse(img, 24, 16, 2, 2, light_brown)

	# Wood grain lines
	for x in range(6, 24, 4):
		img.set_pixel(x, 14, dark_brown)
		img.set_pixel(x + 1, 14, dark_brown)
		img.set_pixel(x, 18, dark_brown)

func _draw_skull(img: Image, size: int) -> void:
	"""Draw a skull icon"""
	var bone = Color(0.9, 0.88, 0.8, 1.0)
	var dark = Color(0.2, 0.15, 0.1, 1.0)
	var center = size / 2

	# Skull shape (rounded top)
	_draw_ellipse(img, center, center - 2, 10, 10, bone)
	# Jaw (smaller ellipse below)
	_draw_ellipse(img, center, center + 6, 7, 4, bone)

	# Eye sockets
	_draw_ellipse(img, center - 4, center - 2, 3, 3, dark)
	_draw_ellipse(img, center + 4, center - 2, 3, 3, dark)

	# Nose hole
	img.set_pixel(center, center + 2, dark)
	img.set_pixel(center, center + 3, dark)

	# Teeth line
	for x in range(center - 4, center + 5):
		img.set_pixel(x, center + 5, dark)

func _draw_bone(img: Image, size: int, tint: Color) -> void:
	"""Draw a femur bone icon with color tint"""
	var bone = Color(0.9 * tint.r + 0.1, 0.88 * tint.g + 0.1, 0.8 * tint.b + 0.2, 1.0)
	var center = size / 2

	# Main bone shaft (diagonal)
	for i in range(20):
		var x = 6 + i
		var y = 6 + i
		if x < size and y < size:
			img.set_pixel(x, y, bone)
			img.set_pixel(x + 1, y, bone)
			img.set_pixel(x, y + 1, bone)

	# Bone ends (knobs)
	_draw_ellipse(img, 8, 8, 4, 4, bone)
	_draw_ellipse(img, 24, 24, 4, 4, bone)

func _draw_finger_bone(img: Image, size: int) -> void:
	"""Draw a small finger bone with magical glow"""
	var bone = Color(0.85, 0.8, 0.9, 1.0)  # Slightly purple bone
	var glow = Color(0.6, 0.3, 0.8, 0.3)  # Purple glow
	var center = size / 2

	# Magical glow aura
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < 14 and dist > 6:
				var alpha = (1.0 - (dist - 6) / 8.0) * 0.25
				img.set_pixel(x, y, Color(0.6, 0.3, 0.8, alpha))

	# Finger bone segments (vertical)
	_draw_ellipse(img, center, center - 6, 3, 4, bone)  # Top segment
	_draw_ellipse(img, center, center, 3, 4, bone)      # Middle segment
	_draw_ellipse(img, center, center + 6, 3, 4, bone)  # Bottom segment

	# Joint lines
	img.set_pixel(center, center - 3, Color(0.6, 0.55, 0.65, 1.0))
	img.set_pixel(center, center + 3, Color(0.6, 0.55, 0.65, 1.0))

func _draw_broken_sword(img: Image, size: int) -> void:
	"""Draw a broken sword icon"""
	var blade = Color(0.7, 0.7, 0.75, 1.0)  # Steel color
	var dark = Color(0.4, 0.4, 0.45, 1.0)
	var handle = Color(0.5, 0.35, 0.2, 1.0)  # Brown handle

	# Handle (bottom)
	for y in range(22, 28):
		for x in range(14, 18):
			img.set_pixel(x, y, handle)

	# Guard (crosspiece)
	for x in range(10, 22):
		img.set_pixel(x, 21, blade)
		img.set_pixel(x, 22, dark)

	# Blade (broken, jagged top)
	for y in range(8, 21):
		for x in range(14, 18):
			img.set_pixel(x, y, blade)
	# Jagged break at top
	img.set_pixel(15, 7, blade)
	img.set_pixel(16, 6, blade)
	img.set_pixel(17, 8, blade)
	img.set_pixel(14, 9, dark)

func _draw_ring(img: Image, size: int) -> void:
	"""Draw a tarnished ring icon"""
	var gold = Color(0.7, 0.6, 0.3, 1.0)  # Tarnished gold
	var dark = Color(0.5, 0.4, 0.2, 1.0)
	var center = size / 2

	# Outer ring
	for angle in range(360):
		var rad = deg_to_rad(angle)
		var x = int(center + cos(rad) * 8)
		var y = int(center + sin(rad) * 8)
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, gold)
		x = int(center + cos(rad) * 9)
		y = int(center + sin(rad) * 9)
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, gold)

	# Inner edge
	for angle in range(360):
		var rad = deg_to_rad(angle)
		var x = int(center + cos(rad) * 5)
		var y = int(center + sin(rad) * 5)
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, dark)

func _draw_gem(img: Image, size: int, color: Color) -> void:
	"""Draw a gemstone icon"""
	var center = size / 2
	var highlight = Color(1, 1, 1, 0.6)

	# Diamond shape
	for y in range(6, size - 6):
		var half_width = 0
		if y < center:
			half_width = int((y - 6) * 8.0 / (center - 6))
		else:
			half_width = int((size - 6 - y) * 8.0 / (size - 6 - center))
		for x in range(center - half_width, center + half_width + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, color)

	# Facet lines
	var dark = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 1.0)
	for i in range(6):
		var y = 6 + i
		img.set_pixel(center, y, dark)
	# Highlight
	img.set_pixel(center - 2, center - 3, highlight)
	img.set_pixel(center - 1, center - 2, highlight)

func _draw_coin(img: Image, size: int) -> void:
	"""Draw an ancient coin icon"""
	var gold = Color(0.8, 0.7, 0.3, 1.0)
	var dark = Color(0.5, 0.45, 0.2, 1.0)
	var center = size / 2

	# Coin circle
	_draw_ellipse(img, center, center, 10, 10, gold)
	# Inner circle (embossed detail)
	_draw_ellipse(img, center, center, 7, 7, dark)
	_draw_ellipse(img, center, center, 6, 6, gold)

	# Simple symbol in center (like a cross or star)
	for i in range(-3, 4):
		img.set_pixel(center + i, center, dark)
		img.set_pixel(center, center + i, dark)

	# Highlight
	img.set_pixel(center - 4, center - 4, Color(1, 1, 0.8, 0.5))

func _draw_generic_material(img: Image, size: int, item: Dictionary) -> void:
	"""Draw a generic material icon (colored gem/ore shape)"""
	var rarity = item.get("rarity", "Common")
	var color = _get_rarity_color(rarity)
	var center = size / 2

	# Diamond/crystal shape
	var points = [
		Vector2i(center, 4),       # Top
		Vector2i(center + 8, center),  # Right
		Vector2i(center, size - 4),    # Bottom
		Vector2i(center - 8, center)   # Left
	]

	# Fill diamond
	for y in range(4, size - 4):
		var half_width = 0
		if y < center:
			half_width = int((y - 4) * 8.0 / (center - 4))
		else:
			half_width = int((size - 4 - y) * 8.0 / (size - 4 - center))
		for x in range(center - half_width, center + half_width + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, color)

	# Highlight
	img.set_pixel(center - 2, center - 4, Color(1, 1, 1, 0.5))
	img.set_pixel(center - 1, center - 3, Color(1, 1, 1, 0.3))

func _draw_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	"""Draw a filled ellipse"""
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
				var dx = float(x - cx) / rx if rx > 0 else 0
				var dy = float(y - cy) / ry if ry > 0 else 0
				if dx * dx + dy * dy <= 1.0:
					img.set_pixel(x, y, color)

func _get_rarity_color(rarity: String) -> Color:
	"""Get color for item rarity"""
	match rarity.to_lower():
		"common":
			return Color(0.7, 0.7, 0.7, 1.0)
		"uncommon":
			return Color(0.3, 0.8, 0.3, 1.0)
		"rare":
			return Color(0.3, 0.5, 0.9, 1.0)
		"epic":
			return Color(0.7, 0.3, 0.9, 1.0)
		"legendary":
			return Color(1.0, 0.6, 0.1, 1.0)
		_:
			return Color(0.6, 0.6, 0.6, 1.0)

func _generate_placeable_icon(placeable_type: String, item: Dictionary) -> ImageTexture:
	"""Generate a procedural icon for placeable items"""
	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	match placeable_type:
		"campfire":
			_draw_campfire_kit(img, size)
		_:
			# Generic placeable icon
			_draw_generic_placeable(img, size)

	return ImageTexture.create_from_image(img)

func _draw_campfire_kit(img: Image, size: int) -> void:
	"""Draw a campfire kit icon - logs and flames"""
	var brown = Color(0.55, 0.35, 0.2, 1.0)
	var dark_brown = Color(0.35, 0.22, 0.12, 1.0)
	var orange = Color(1.0, 0.5, 0.1, 1.0)
	var yellow = Color(1.0, 0.8, 0.2, 1.0)
	var red = Color(0.9, 0.2, 0.1, 1.0)
	var center = size / 2

	# Draw crossed logs at bottom
	# Log 1 (diagonal left-to-right)
	for i in range(-8, 9):
		var x = center + i
		var y = size - 10 + abs(i) / 3
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, brown)
			if y + 1 < size:
				img.set_pixel(x, y + 1, dark_brown)

	# Log 2 (diagonal right-to-left)
	for i in range(-8, 9):
		var x = center + i
		var y = size - 10 - abs(i) / 3 + 4
		if x >= 0 and x < size and y >= 0 and y < size:
			img.set_pixel(x, y, brown)
			if y + 1 < size:
				img.set_pixel(x, y + 1, dark_brown)

	# Draw flames (triangular flame shapes)
	# Outer orange glow
	for y in range(4, size - 10):
		for x in range(center - 6, center + 7):
			var dist_y = float(y - 4) / (size - 14)
			var width = int(6 * (1.0 - dist_y))
			if abs(x - center) <= width:
				var flame_intensity = 1.0 - dist_y * 0.7
				img.set_pixel(x, y, Color(orange.r, orange.g * flame_intensity, orange.b * flame_intensity * 0.5, 1.0))

	# Inner yellow core
	for y in range(8, size - 12):
		for x in range(center - 3, center + 4):
			var dist_y = float(y - 8) / (size - 20)
			var width = int(3 * (1.0 - dist_y))
			if abs(x - center) <= width:
				img.set_pixel(x, y, yellow)

	# Red tips at top
	img.set_pixel(center, 4, red)
	img.set_pixel(center, 5, red)
	img.set_pixel(center - 2, 7, red)
	img.set_pixel(center + 2, 7, red)

func _draw_generic_placeable(img: Image, size: int) -> void:
	"""Draw a generic placeable icon (box shape)"""
	var brown = Color(0.5, 0.4, 0.3, 1.0)
	var dark = Color(0.3, 0.25, 0.2, 1.0)
	var center = size / 2

	# Simple box/crate shape
	for y in range(8, size - 6):
		for x in range(6, size - 6):
			img.set_pixel(x, y, brown)

	# Border
	for x in range(6, size - 6):
		img.set_pixel(x, 8, dark)
		img.set_pixel(x, size - 7, dark)
	for y in range(8, size - 6):
		img.set_pixel(6, y, dark)
		img.set_pixel(size - 7, y, dark)
