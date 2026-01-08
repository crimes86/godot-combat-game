extends Node

## ItemIconGenerator - Extracts inventory icons from LPC sprite sheets
## Uses the south-facing idle frame (row 2, frame 0) for equipment icons

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_FORGED_ICONS: bool = false  # Debug forged item icon loading
const DEBUG_ICON_LOADING: bool = false  # Debug all icon loading (enable to trace failures)

# ============================================
# ENHANCED ICONS - 256x256 upscaled versions
# ============================================
const USE_ENHANCED_ICONS: bool = true  # Use enhanced 256x256 icons when available
const ENHANCED_ICONS_PATH: String = "res://assets/icons/enhanced/"

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

# Weapon type fallbacks for icon generation (same as Player.gd uses)
const WEAPON_TYPE_FALLBACKS = {
	"greatsword": "sword",
	"longsword": "sword",
	"shortsword": "sword",
	"broadsword": "sword",
	"claymore": "sword",
	"rapier": "sword",
	"saber": "sword",
	"scimitar": "sword",
	"crossbow": "bow",
	"wand": "staff",
	"halberd": "spear",
	"lance": "spear",
	"pike": "spear",
	"glaive": "spear",
	"hammer": "mace",
	"club": "mace",
	"flail": "mace",
	"morningstar": "mace",
}

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

	# Check if this is a forged item first - they have dedicated icons
	if item.get("is_forged", false):
		var forged_icon = _get_forged_item_icon(item)
		if forged_icon:
			return forged_icon

	var item_type = item.get("type", "")
	var item_name = item.get("name", "")
	var sprite_name = item.get("sprite_name", "")
	var slot = item.get("slot", "")

	# Infer type from other fields if missing
	if item_type == "" and item.has("weapon_type"):
		item_type = "weapon"
	elif item_type == "" and item.has("tool_type"):
		item_type = "tool"
	elif item_type == "" and slot in ["chest", "legs", "feet", "head", "hands", "arms"]:
		item_type = "armor"

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

	# Handle consumables with icon files
	if item_type == "consumable":
		var consumable_type = item.get("consumable_type", "")
		var cache_key = "consumable:%s" % consumable_type
		if icon_cache.has(cache_key):
			return icon_cache[cache_key]
		var icon = _get_consumable_icon(consumable_type, item)
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
		if DEBUG_ICON_LOADING:
			print("⚠️ [IconGen] No sprite path for: %s (type=%s, sprite_name=%s, slot=%s)" % [item_name, item_type, sprite_name, slot])
		return null

	# Determine best facing direction for this item
	var direction = _get_direction_for_item(item_type, slot)

	# Create cache key including direction and slot (for half-crop variants)
	var cache_key = "%s:%d:%s" % [sprite_path, direction, slot]

	# Check cache first
	if icon_cache.has(cache_key):
		return icon_cache[cache_key]

	# Try to load enhanced icon first (256x256 pre-generated versions)
	if USE_ENHANCED_ICONS:
		var enhanced_icon = _try_load_enhanced_equipment_icon(item_type, sprite_name, slot, item)
		if enhanced_icon:
			if DEBUG_ICON_LOADING:
				print("✅ [IconGen] Enhanced icon loaded for: %s" % item_name)
			icon_cache[cache_key] = enhanced_icon
			return enhanced_icon
		elif DEBUG_ICON_LOADING:
			print("⚠️ [IconGen] No enhanced icon for: %s (type=%s, sprite=%s, slot=%s)" % [item_name, item_type, sprite_name, slot])

	# Generate the icon from sprite sheet (fallback)
	var icon = _generate_icon_from_sprite(sprite_path, direction, slot)
	if icon:
		if DEBUG_ICON_LOADING:
			print("✅ [IconGen] Generated icon from sprite: %s" % item_name)
		icon_cache[cache_key] = icon
	elif DEBUG_ICON_LOADING:
		print("❌ [IconGen] Failed to generate icon for: %s from %s" % [item_name, sprite_path])

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
			var slot = item.get("slot", "")
			# If sprite_name is missing, try to infer from item name
			var effective_sprite_name = sprite_name
			if effective_sprite_name.is_empty():
				effective_sprite_name = _infer_sprite_name_from_item(item, slot)
			if effective_sprite_name.is_empty():
				return ""
			match slot:
				"chest":
					return "res://assets/characters/shirt/%s_walk.png" % effective_sprite_name
				"legs":
					return "res://assets/characters/pants/%s_walk.png" % effective_sprite_name
				"feet":
					return "res://assets/characters/boots/%s_walk.png" % effective_sprite_name
				"head":
					return "res://assets/characters/head/%s_walk.png" % effective_sprite_name
				"hands":
					return "res://assets/characters/hands/%s_walk.png" % effective_sprite_name
				"arms":
					return "res://assets/characters/arms/%s_walk.png" % effective_sprite_name
		"weapon":
			# Weapons use walk.png for cleaner icons (consistent 64x64 tiles)
			var weapon_type = item.get("weapon_type", "sword")
			# Apply fallback mapping for weapon types without dedicated sprites
			var actual_type = WEAPON_TYPE_FALLBACKS.get(weapon_type, weapon_type)
			# For daggers with "standard" subfolder
			if actual_type == "dagger":
				return "res://assets/equipment/weapons/dagger/standard/walk.png"
			# All weapons use walk sprite for consistent icon extraction
			return "res://assets/equipment/weapons/%s/walk.png" % actual_type
		"tool":
			# Tools use the format: assets/tools/{tool_type}/walk.png
			var tool_type = item.get("tool_type", "")
			if tool_type == "axe":
				return "res://assets/equipment/tools/axe/walk.png"
			elif tool_type == "pickaxe":
				return "res://assets/equipment/tools/pickaxe/walk.png"
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

func _try_load_enhanced_equipment_icon(item_type: String, sprite_name: String, slot: String, item: Dictionary) -> Texture2D:
	"""Try to load a pre-generated enhanced icon for equipment items."""
	var paths_to_try: Array[String] = []

	match item_type:
		"armor":
			# Map slot to directory name used by icon_enhancer.py
			var slot_dir = slot
			match slot:
				"chest":
					slot_dir = "shirt"
				"legs":
					slot_dir = "pants"
				"feet":
					slot_dir = "boots"
			paths_to_try.append(ENHANCED_ICONS_PATH + "equipment/%s/%s.png" % [slot_dir, sprite_name])
			# Also try the original slot name
			if slot_dir != slot:
				paths_to_try.append(ENHANCED_ICONS_PATH + "equipment/%s/%s.png" % [slot, sprite_name])
		"weapon":
			var weapon_type = item.get("weapon_type", "sword")
			var actual_type = WEAPON_TYPE_FALLBACKS.get(weapon_type, weapon_type)
			paths_to_try.append(ENHANCED_ICONS_PATH + "equipment/weapon/%s.png" % actual_type)
		"tool":
			var tool_type = item.get("tool_type", "")
			if tool_type != "":
				paths_to_try.append(ENHANCED_ICONS_PATH + "equipment/tool/%s.png" % tool_type)

	# Try each path
	for icon_path in paths_to_try:
		if ResourceLoader.exists(icon_path):
			var texture = load(icon_path) as Texture2D
			if texture:
				return texture

	return null

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

	# Make the result square by padding to the larger dimension
	# This prevents stretching when displayed in square UI slots
	var final_size = max(crop_width, crop_height)
	if crop_width != crop_height:
		var square_img = Image.create(final_size, final_size, false, Image.FORMAT_RGBA8)
		# Center the cropped content in the square
		var offset_x = (final_size - crop_width) / 2
		var offset_y = (final_size - crop_height) / 2
		square_img.blit_rect(cropped, Rect2i(0, 0, crop_width, crop_height), Vector2i(offset_x, offset_y))
		return square_img

	return cropped

func clear_cache() -> void:
	"""Clear the icon cache (call when sprites change)"""
	icon_cache.clear()

# Known item name to sprite_name mappings for armor/clothes
const ITEM_NAME_TO_SPRITE = {
	# Starting clothes
	"Tattered Shirt": "white_shirt",
	"Tattered Pants": "green_pants",
	# Common armor (add more as needed)
	"White Shirt": "white_shirt",
	"Green Pants": "green_pants",
	"Leather Boots": "leather_boots",
	"Leather Gloves": "leather_gloves",
	"Leather Cap": "leather_cap",
}

func _infer_sprite_name_from_item(item: Dictionary, slot: String) -> String:
	"""Infer sprite_name from item name or other properties"""
	var item_name = item.get("name", "")

	# Check direct mapping first
	if ITEM_NAME_TO_SPRITE.has(item_name):
		return ITEM_NAME_TO_SPRITE[item_name]

	# Try to generate sprite name from item name
	# e.g., "Leather Boots" -> "leather_boots"
	if item_name != "":
		var snake_name = item_name.to_lower().replace(" ", "_").replace("'", "")
		# Check if the file might exist with this name
		var test_paths = []
		match slot:
			"chest":
				test_paths.append("res://assets/characters/shirt/%s_walk.png" % snake_name)
			"legs":
				test_paths.append("res://assets/characters/pants/%s_walk.png" % snake_name)
			"feet":
				test_paths.append("res://assets/characters/boots/%s_walk.png" % snake_name)
			"head":
				test_paths.append("res://assets/characters/head/%s_walk.png" % snake_name)
			"hands":
				test_paths.append("res://assets/characters/hands/%s_walk.png" % snake_name)
			"arms":
				test_paths.append("res://assets/characters/arms/%s_walk.png" % snake_name)

		for path in test_paths:
			if ResourceLoader.exists(path):
				return snake_name

	return ""

func _generate_material_icon(item_name: String, item: Dictionary) -> Texture2D:
	"""Load or generate material icon - tries file first, falls back to procedural"""

	# Convert item name to filename (lowercase, underscores, no apostrophes)
	var filename = item_name.to_lower().replace(" ", "_").replace("'", "")

	# Try loading from enhanced icons first (256x256)
	if USE_ENHANCED_ICONS:
		var enhanced_path = "res://assets/icons/enhanced/materials/%s.png" % filename
		if FileAccess.file_exists(enhanced_path):
			var texture = load(enhanced_path)
			if texture:
				return texture

	# Try loading from standard materials icons (64x64)
	var standard_path = "res://assets/icons/materials/%s.png" % filename
	if FileAccess.file_exists(standard_path):
		var texture = load(standard_path)
		if texture:
			return texture

	# File not found - fall back to procedural generation
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

func _get_consumable_icon(consumable_type: String, item: Dictionary) -> Texture2D:
	"""Load consumable icon from assets/icons/consumables/ or return null"""

	# First check if item has a direct icon_path specified
	var icon_path = item.get("icon_path", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var texture = load(icon_path)
		if texture:
			return texture

	# Convert consumable_type to filename (e.g., "empty_vial" -> "empty_vial.png")
	var filename = consumable_type.to_lower().replace(" ", "_").replace("'", "")

	# Try loading from enhanced icons first (256x256)
	if USE_ENHANCED_ICONS:
		var enhanced_path = "res://assets/icons/enhanced/consumables/%s.png" % filename
		if FileAccess.file_exists(enhanced_path):
			var texture = load(enhanced_path)
			if texture:
				return texture

	# Try loading from standard consumables icons (64x64)
	var standard_path = "res://assets/icons/consumables/%s.png" % filename
	if FileAccess.file_exists(standard_path):
		var texture = load(standard_path)
		if texture:
			return texture

	# No icon found - return null (consumables without icons won't show in inventory)
	print("⚠️ No consumable icon found for: %s (type: %s)" % [item.get("name", "Unknown"), consumable_type])
	return null

func _generate_placeable_icon(placeable_type: String, item: Dictionary) -> Texture2D:
	"""Generate a procedural icon for placeable items"""

	# First check if item has a direct icon_path specified
	var icon_path = item.get("icon_path", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var texture = load(icon_path)
		if texture:
			return texture

	# Generate procedural icon
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

# ============================================
# FORGED ITEM ICONS
# ============================================

# Icon scale overrides for specific items (1.0 = normal, 2.0 = 2x larger)
# Note: Prefer scaling the actual icon asset with scripts/tools/scale_icon_content.py
const ICON_SCALE_OVERRIDES = {
	# (empty) - rely on asset-level sizing; use tools/scale_icon_content.py if needed
}

func _scale_texture(texture: Texture2D, scale_factor: float) -> Texture2D:
	"""Scale a texture by a factor (e.g., 1.25 = 25% larger)"""
	if scale_factor == 1.0 or not texture:
		return texture

	var img = texture.get_image()
	if not img:
		return texture

	var new_width = int(img.get_width() * scale_factor)
	var new_height = int(img.get_height() * scale_factor)

	# Resize the image (uses bilinear interpolation)
	img.resize(new_width, new_height, Image.INTERPOLATE_BILINEAR)

	return ImageTexture.create_from_image(img)

func _get_icon_scale(item_id: String, item_name: String) -> float:
	"""Get the scale factor for an item icon"""
	# Check by item_id first
	var id_lower = item_id.to_lower()
	if ICON_SCALE_OVERRIDES.has(id_lower):
		return ICON_SCALE_OVERRIDES[id_lower]

	# Check by snake_case name
	var name_snake = _name_to_snake_case(item_name)
	if ICON_SCALE_OVERRIDES.has(name_snake):
		return ICON_SCALE_OVERRIDES[name_snake]

	return 1.0

func _get_forged_item_icon(item: Dictionary) -> Texture2D:
	"""Load icon for a forged item from assets/icons/forged/"""
	var item_name = item.get("name", "")
	var item_type = item.get("type", "weapon")
	var item_id = item.get("item_id", "")

	if DEBUG_FORGED_ICONS:
		print("[ForgedIcon] ════════════════════════════════════════")
		print("[ForgedIcon] Processing item: '%s'" % item_name)
		print("[ForgedIcon]   type: '%s', item_id: '%s'" % [item_type, item_id])
		print("[ForgedIcon]   Full item data: %s" % str(item).substr(0, 200))

	# Convert item name to snake_case filename
	# e.g. "Coiled Sword" -> "coiled_sword"
	var filename_from_name = _name_to_snake_case(item_name)

	if DEBUG_FORGED_ICONS:
		print("[ForgedIcon]   Filename from name: '%s'" % filename_from_name)

	# Start with filename derived from name
	var filename = filename_from_name

	# Also try the item_id if provided (might already be snake_case)
	var filename_from_id = ""
	if item_id != "":
		filename_from_id = item_id.to_lower().replace(" ", "_").replace("-", "_").replace("'", "")
		if DEBUG_FORGED_ICONS:
			print("[ForgedIcon]   Filename from item_id: '%s'" % filename_from_id)

	# Determine subdirectory based on item type
	var subdir = _get_forged_subdir(item_type, item)

	if DEBUG_FORGED_ICONS:
		print("[ForgedIcon]   Subdirectory: '%s'" % subdir)

	# Get scale factor for this item
	var scale_factor = _get_icon_scale(item_id, item_name)
	if DEBUG_FORGED_ICONS and scale_factor != 1.0:
		print("[ForgedIcon]   Scale factor: %.2f" % scale_factor)

	# Check cache first (include scale in key)
	var cache_key = "forged:%s/%s:%.2f" % [subdir, filename, scale_factor]
	if icon_cache.has(cache_key):
		if DEBUG_FORGED_ICONS:
			print("[ForgedIcon]   ✅ Found in cache: %s" % cache_key)
		return icon_cache[cache_key]

	# Build list of paths to try
	var paths_to_try: Array[String] = []

	# Try enhanced icons first (256x256 upscaled versions)
	if USE_ENHANCED_ICONS:
		paths_to_try.append(ENHANCED_ICONS_PATH + "forged/%s/%s.png" % [subdir, filename_from_name])
		if filename_from_id != "" and filename_from_id != filename_from_name:
			paths_to_try.append(ENHANCED_ICONS_PATH + "forged/%s/%s.png" % [subdir, filename_from_id])

	# Primary path from name (original 64x64)
	paths_to_try.append("res://assets/icons/forged/%s/%s.png" % [subdir, filename_from_name])

	# Path from item_id if different
	if filename_from_id != "" and filename_from_id != filename_from_name:
		paths_to_try.append("res://assets/icons/forged/%s/%s.png" % [subdir, filename_from_id])

	# Try alternative subdirectories (enhanced first, then original)
	var alt_subdirs = ["weapons", "armor", "shields", "accessories", "capes"]
	for alt_subdir in alt_subdirs:
		if alt_subdir != subdir:
			if USE_ENHANCED_ICONS:
				paths_to_try.append(ENHANCED_ICONS_PATH + "forged/%s/%s.png" % [alt_subdir, filename_from_name])
			paths_to_try.append("res://assets/icons/forged/%s/%s.png" % [alt_subdir, filename_from_name])
			if filename_from_id != "" and filename_from_id != filename_from_name:
				if USE_ENHANCED_ICONS:
					paths_to_try.append(ENHANCED_ICONS_PATH + "forged/%s/%s.png" % [alt_subdir, filename_from_id])
				paths_to_try.append("res://assets/icons/forged/%s/%s.png" % [alt_subdir, filename_from_id])

	# Try all paths
	for icon_path in paths_to_try:
		if DEBUG_FORGED_ICONS:
			print("[ForgedIcon]   Trying: %s" % icon_path)
		if ResourceLoader.exists(icon_path):
			var texture = load(icon_path) as Texture2D
			if texture:
				if DEBUG_FORGED_ICONS:
					print("[ForgedIcon]   ✅ LOADED: %s" % icon_path)
				# Apply scale if needed
				if scale_factor != 1.0:
					texture = _scale_texture(texture, scale_factor)
				icon_cache[cache_key] = texture
				return texture
		else:
			if DEBUG_FORGED_ICONS:
				print("[ForgedIcon]   ❌ Not found")

	# No forged icon found - generate a placeholder based on item type and rarity
	if DEBUG_FORGED_ICONS:
		print("[ForgedIcon]   ⚠️ No icon found - generating placeholder")
		print("[ForgedIcon]     glow_color: %s, rarity: %s" % [item.get("glow_color", "none"), item.get("rarity", "Common")])
	print("⚠️ No forged icon found for: %s (tried %d paths) - generating placeholder" % [item_name, paths_to_try.size()])
	var placeholder = _generate_forged_placeholder(item)
	if placeholder:
		icon_cache[cache_key] = placeholder
	return placeholder

func _name_to_snake_case(name: String) -> String:
	"""Convert item name to snake_case filename format"""
	# "Coiled Sword" -> "coiled_sword"
	# "Hand of Malenia" -> "hand_of_malenia"
	return name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")

func _get_forged_subdir(item_type: String, item: Dictionary) -> String:
	"""Determine the subdirectory for a forged item icon"""
	match item_type:
		"weapon":
			return "weapons"
		"armor":
			return "armor"
		"shield":
			return "shields"
		"accessory":
			return "accessories"
		"cape":
			return "armor"  # Capes stored with armor
		_:
			# Try to infer from slot
			var slot = item.get("slot", "")
			match slot:
				"mainhand":
					return "weapons"
				"offhand":
					return "shields"
				"head", "chest", "legs", "feet", "hands", "back":
					return "armor"
				"accessory":
					return "accessories"
				_:
					return "weapons"  # Default to weapons

func _generate_forged_placeholder(item: Dictionary) -> ImageTexture:
	"""Generate a placeholder icon for forged items without dedicated icons"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)

	var item_type = item.get("type", "weapon")
	var rarity = item.get("rarity", "Common").to_lower()

	# Get glow color from item or use rarity color
	var glow_color: Color
	var glow_str = item.get("glow_color", "")
	if glow_str.begins_with("#"):
		glow_color = Color.from_string(glow_str, _get_rarity_color(rarity))
	else:
		glow_color = _get_rarity_color(rarity)

	var center = size / 2

	# Draw glow background
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < 28:
				var alpha = (1.0 - dist / 28.0) * 0.4
				img.set_pixel(x, y, Color(glow_color.r, glow_color.g, glow_color.b, alpha))

	# Draw item shape based on type
	match item_type:
		"weapon":
			_draw_forged_weapon_shape(img, size, glow_color)
		"armor", "armor_head", "armor_chest", "armor_legs", "armor_hands", "armor_feet":
			_draw_forged_armor_shape(img, size, glow_color)
		"shield":
			_draw_forged_shield_shape(img, size, glow_color)
		"cape":
			_draw_forged_cape_shape(img, size, glow_color)
		"accessory":
			_draw_forged_accessory_shape(img, size, glow_color)
		_:
			_draw_forged_weapon_shape(img, size, glow_color)

	return ImageTexture.create_from_image(img)

func _draw_forged_weapon_shape(img: Image, size: int, color: Color) -> void:
	"""Draw a sword silhouette for weapon placeholder"""
	var center = size / 2
	var bright = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0).clamp()
	var dark = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 1.0)

	# Diagonal sword blade
	for i in range(35):
		var x = 10 + i
		var y = 54 - i
		if x < size and y >= 0:
			for w in range(-2, 3):
				var px = x + w
				var py = y - w
				if px >= 0 and px < size and py >= 0 and py < size:
					img.set_pixel(px, py, bright if w == 0 else color)

	# Handle/hilt
	for i in range(-3, 4):
		img.set_pixel(center - 12 + i, center + 12, dark)
	for i in range(6):
		img.set_pixel(center - 14, center + 14 + i, dark)
		img.set_pixel(center - 13, center + 14 + i, color)

func _draw_forged_armor_shape(img: Image, size: int, color: Color) -> void:
	"""Draw a helm/armor silhouette"""
	var center = size / 2
	var bright = Color(color.r * 1.3, color.g * 1.3, color.b * 1.3, 1.0).clamp()

	# Helmet dome
	_draw_ellipse(img, center, center - 5, 18, 20, color)
	# Face opening
	_draw_ellipse(img, center, center + 2, 8, 12, Color(0.1, 0.1, 0.1, 1.0))
	# Highlight
	_draw_ellipse(img, center - 8, center - 12, 4, 3, bright)

func _draw_forged_shield_shape(img: Image, size: int, color: Color) -> void:
	"""Draw a shield silhouette"""
	var center = size / 2
	var dark = Color(color.r * 0.6, color.g * 0.6, color.b * 0.6, 1.0)

	# Shield body (pointed bottom)
	for y in range(8, size - 8):
		var width = 20 if y < center else int(20 * (1.0 - float(y - center) / (size - 8 - center)))
		for x in range(center - width, center + width + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, color)

	# Border
	for y in range(8, size - 8):
		var width = 20 if y < center else int(20 * (1.0 - float(y - center) / (size - 8 - center)))
		if center - width >= 0:
			img.set_pixel(center - width, y, dark)
		if center + width < size:
			img.set_pixel(center + width, y, dark)

func _draw_forged_cape_shape(img: Image, size: int, color: Color) -> void:
	"""Draw a cape/cloak silhouette"""
	var center = size / 2
	var dark = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 1.0)

	# Flowing cape shape
	for y in range(6, size - 4):
		var wave = int(sin(float(y) * 0.3) * 3)
		var width = 8 + int(float(y - 6) / (size - 10) * 14)
		for x in range(center - width + wave, center + width + wave + 1):
			if x >= 0 and x < size:
				img.set_pixel(x, y, color if abs(x - center - wave) < width - 2 else dark)

func _draw_forged_accessory_shape(img: Image, size: int, color: Color) -> void:
	"""Draw a ring/gem silhouette"""
	var center = size / 2
	var bright = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 1.0).clamp()

	# Outer ring
	for angle in range(360):
		var rad = deg_to_rad(angle)
		for r in range(14, 20):
			var x = int(center + cos(rad) * r)
			var y = int(center + sin(rad) * r)
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, color)

	# Gem in center
	_draw_ellipse(img, center, center, 8, 8, bright)
