extends Node2D
class_name HubHearth

## 🔥 HubHearth - Central cave hearth with glowing coals
## A low-smoke rectangular coal hearth for enclosed cave spaces
## - Rectangular stone-lined pit containing hot coals
## - Glowing embers as primary light/heat source
## - Subtle low flames rising from coals (not a roaring bonfire)
## - Safe for enclosed spaces - no choking smoke

# Visual settings - RECTANGULAR hearth
const HEARTH_WIDTH: float = 180.0   # Width of the rectangular pit
const HEARTH_HEIGHT: float = 120.0  # Height (depth in top-down view)
const COAL_COUNT: int = 75          # Number of coal pieces (dense pile)
const STONE_SIZE: float = 18.0      # Size of border stones

# Light settings
const BASE_LIGHT_ENERGY: float = 2.8
const LIGHT_TEXTURE_SCALE: float = 12.0

# Node references
var hearth_sprite: Node2D = null
var hearth_light: PointLight2D = null
var coal_nodes: Array = []
var flame_nodes: Array = []

# Animation
var animation_timer: float = 0.0
const ANIMATION_INTERVAL: float = 0.04  # 25fps for smooth coal pulsing

func _ready() -> void:
	create_hearth()
	create_hearth_light()
	create_subtle_flames()
	create_ember_particles()

	# Cache nodes for animation
	await get_tree().process_frame
	_cache_animated_nodes()

func _physics_process(delta: float) -> void:
	animation_timer += delta
	if animation_timer < ANIMATION_INTERVAL:
		return
	animation_timer = 0.0
	animate_hearth()

func create_hearth() -> void:
	"""Create the rectangular hearth pit with stones and glowing coals"""
	hearth_sprite = Node2D.new()
	hearth_sprite.name = "HearthSprite"
	add_child(hearth_sprite)

	var half_w = HEARTH_WIDTH / 2.0
	var half_h = HEARTH_HEIGHT / 2.0

	# === OUTER STONE BORDER === (rectangular frame)
	var stone_colors = [
		Color(0.14, 0.12, 0.11, 1.0),  # Dark grey
		Color(0.16, 0.14, 0.13, 1.0),  # Medium grey
		Color(0.12, 0.10, 0.09, 1.0),  # Darker grey
	]

	# Place stones along rectangle edges
	var stone_positions: Array = []

	# Top edge stones
	var stones_horizontal = int(HEARTH_WIDTH / (STONE_SIZE * 1.1))
	for i in range(stones_horizontal):
		var x = -half_w + STONE_SIZE/2 + i * (HEARTH_WIDTH / stones_horizontal)
		stone_positions.append(Vector2(x, -half_h))

	# Bottom edge stones
	for i in range(stones_horizontal):
		var x = -half_w + STONE_SIZE/2 + i * (HEARTH_WIDTH / stones_horizontal)
		stone_positions.append(Vector2(x, half_h))

	# Left edge stones (excluding corners)
	var stones_vertical = int(HEARTH_HEIGHT / (STONE_SIZE * 1.1)) - 1
	for i in range(stones_vertical):
		var y = -half_h + STONE_SIZE + i * ((HEARTH_HEIGHT - STONE_SIZE) / max(stones_vertical, 1))
		stone_positions.append(Vector2(-half_w, y))

	# Right edge stones (excluding corners)
	for i in range(stones_vertical):
		var y = -half_h + STONE_SIZE + i * ((HEARTH_HEIGHT - STONE_SIZE) / max(stones_vertical, 1))
		stone_positions.append(Vector2(half_w, y))

	# Create each stone
	for i in range(stone_positions.size()):
		var stone_pos = stone_positions[i]
		var stone = Polygon2D.new()
		stone.name = "Stone" + str(i)
		stone.z_index = 2  # Above coals

		# Irregular stone shape
		var size = STONE_SIZE * randf_range(0.8, 1.1)
		var points = PackedVector2Array()
		var num_points = randi_range(5, 7)
		for j in range(num_points):
			var pt_angle = (float(j) / num_points) * TAU + randf_range(-0.25, 0.25)
			var pt_radius = size * randf_range(0.6, 0.9)
			points.append(stone_pos + Vector2(cos(pt_angle), sin(pt_angle)) * pt_radius)
		stone.polygon = points
		stone.color = stone_colors[i % stone_colors.size()]
		hearth_sprite.add_child(stone)

	# === ASH BED === (feathered edges to blend with stones)
	# Create multiple layers for soft edge effect
	var inset = STONE_SIZE * 0.6

	# Outer feather layer (most transparent, largest)
	var ash_outer = Polygon2D.new()
	ash_outer.name = "AshBedOuter"
	ash_outer.z_index = -3
	var outer_inset = inset * 0.3
	ash_outer.polygon = PackedVector2Array([
		Vector2(-half_w + outer_inset, -half_h + outer_inset),
		Vector2(half_w - outer_inset, -half_h + outer_inset),
		Vector2(half_w - outer_inset, half_h - outer_inset),
		Vector2(-half_w + outer_inset, half_h - outer_inset),
	])
	ash_outer.color = Color(0.025, 0.02, 0.015, 0.3)  # Very faint outer edge
	hearth_sprite.add_child(ash_outer)

	# Middle feather layer
	var ash_mid = Polygon2D.new()
	ash_mid.name = "AshBedMid"
	ash_mid.z_index = -2
	var mid_inset = inset * 0.65
	ash_mid.polygon = PackedVector2Array([
		Vector2(-half_w + mid_inset, -half_h + mid_inset),
		Vector2(half_w - mid_inset, -half_h + mid_inset),
		Vector2(half_w - mid_inset, half_h - mid_inset),
		Vector2(-half_w + mid_inset, half_h - mid_inset),
	])
	ash_mid.color = Color(0.022, 0.017, 0.013, 0.6)  # Mid opacity
	hearth_sprite.add_child(ash_mid)

	# Core ash bed (full opacity, smallest)
	var ash_bed = Polygon2D.new()
	ash_bed.name = "AshBed"
	ash_bed.z_index = -1
	ash_bed.polygon = PackedVector2Array([
		Vector2(-half_w + inset, -half_h + inset),
		Vector2(half_w - inset, -half_h + inset),
		Vector2(half_w - inset, half_h - inset),
		Vector2(-half_w + inset, half_h - inset),
	])
	ash_bed.color = Color(0.02, 0.015, 0.012, 1.0)  # Very dark ash/charcoal
	hearth_sprite.add_child(ash_bed)

	# === COAL GLOW LAYER === (very subtle, smaller, lower opacity)
	var glow = Polygon2D.new()
	glow.name = "CoalGlow"
	glow.z_index = -1
	# Tiny center hotspot only
	var glow_size_x = HEARTH_WIDTH * 0.15
	var glow_size_y = HEARTH_HEIGHT * 0.12
	glow.polygon = PackedVector2Array([
		Vector2(-glow_size_x, -glow_size_y),
		Vector2(glow_size_x, -glow_size_y),
		Vector2(glow_size_x, glow_size_y),
		Vector2(-glow_size_x, glow_size_y),
	])
	glow.color = Color(1.0, 0.3, 0.05, 0.12)  # Very subtle center glow
	hearth_sprite.add_child(glow)

	# === STONE SHADOWS === (ground the stones)
	_create_stone_shadows(stone_positions)

	# === GLOWING COALS === (the main heat/light source)
	create_coals()

func _create_stone_shadows(stone_positions: Array) -> void:
	"""Add shadows under stones to ground them"""
	for i in range(stone_positions.size()):
		var stone_pos = stone_positions[i]
		var shadow = Polygon2D.new()
		shadow.name = "StoneShadow" + str(i)
		shadow.z_index = -3  # Below everything

		# Shadow offset down and slightly right (light from hearth center)
		var shadow_offset = Vector2(2, 4)
		var shadow_pos = stone_pos + shadow_offset

		# Slightly larger, irregular shadow shape
		var size = STONE_SIZE * randf_range(0.9, 1.15)
		var points = PackedVector2Array()
		var num_points = randi_range(5, 7)
		for j in range(num_points):
			var pt_angle = (float(j) / num_points) * TAU + randf_range(-0.2, 0.2)
			var pt_radius = size * randf_range(0.65, 0.95)
			points.append(shadow_pos + Vector2(cos(pt_angle), sin(pt_angle)) * pt_radius)
		shadow.polygon = points
		shadow.color = Color(0.02, 0.015, 0.01, 0.6)  # Dark shadow
		hearth_sprite.add_child(shadow)

func create_coals() -> void:
	"""Create the bed of glowing coals in rectangular area"""
	var half_w = HEARTH_WIDTH / 2.0
	var half_h = HEARTH_HEIGHT / 2.0
	var coal_area_inset = STONE_SIZE * 0.9  # Keep coals inside stone border

	for i in range(COAL_COUNT):
		# Position coals in rectangular grid with randomization
		# Denser in center (hotter)
		var raw_x = randf_range(-1.0, 1.0)
		var raw_y = randf_range(-1.0, 1.0)

		# Bias toward center for hotter coal distribution
		raw_x = raw_x * abs(raw_x)  # Cubic distribution - more in center
		raw_y = raw_y * abs(raw_y)

		var coal_x = raw_x * (half_w - coal_area_inset)
		var coal_y = raw_y * (half_h - coal_area_inset)
		var coal_pos = Vector2(coal_x, coal_y)

		var coal = Polygon2D.new()
		coal.name = "Coal" + str(i)
		coal.z_index = 0  # Base layer

		# Irregular coal shape
		var coal_size = randf_range(8.0, 14.0)
		var points = PackedVector2Array()
		var num_points = randi_range(5, 7)
		for j in range(num_points):
			var pt_angle = (float(j) / num_points) * TAU + randf_range(-0.3, 0.3)
			var pt_radius = coal_size * randf_range(0.5, 1.0)
			points.append(coal_pos + Vector2(cos(pt_angle), sin(pt_angle)) * pt_radius)
		coal.polygon = points

		# Heat based on distance from center (center = hotter)
		var distance_from_center = coal_pos.length()
		var max_distance = Vector2(half_w - coal_area_inset, half_h - coal_area_inset).length()
		var heat = 1.0 - clamp(distance_from_center / max_distance, 0.0, 1.0)
		heat = heat * heat  # Make center much hotter
		coal.color = _get_coal_color(heat)

		# Store heat value and assign to one of 3 glow groups
		coal.set_meta("heat", heat)
		coal.set_meta("base_pos", coal_pos)
		coal.set_meta("glow_group", i % 3)  # Assign to group 0, 1, or 2

		hearth_sprite.add_child(coal)
		coal_nodes.append(coal)

func _get_coal_color(heat: float) -> Color:
	"""Get coal color based on heat level (0-1)"""
	if heat < 0.25:
		# Cool coal - dark red/black
		return Color(0.25 + heat * 0.6, 0.06, 0.02, 1.0)
	elif heat < 0.5:
		# Warming coal - red
		var t = (heat - 0.25) / 0.25
		return Color(0.55 + t * 0.35, 0.08 + t * 0.15, 0.02, 1.0)
	elif heat < 0.75:
		# Hot coal - orange
		var t = (heat - 0.5) / 0.25
		return Color(0.9 + t * 0.1, 0.23 + t * 0.27, 0.02 + t * 0.08, 1.0)
	else:
		# White-hot coal - yellow/white center
		var t = (heat - 0.75) / 0.25
		return Color(1.0, 0.5 + t * 0.4, 0.1 + t * 0.35, 1.0)

func create_subtle_flames() -> void:
	"""Create small, subtle flames rising from the hottest coals"""
	var half_w = HEARTH_WIDTH / 2.0
	var half_h = HEARTH_HEIGHT / 2.0

	# Flames in a row along the center of the hearth
	var num_flames = 6
	var flame_spread_x = HEARTH_WIDTH * 0.5
	var flame_spread_y = HEARTH_HEIGHT * 0.3

	for i in range(num_flames):
		# Position flames in central hot zone
		var fx = randf_range(-flame_spread_x / 2, flame_spread_x / 2)
		var fy = randf_range(-flame_spread_y / 2, flame_spread_y / 2)
		var flame_pos = Vector2(fx, fy)

		var flame = Polygon2D.new()
		flame.name = "Flame" + str(i)
		flame.z_index = 3  # Above coals and stones

		# Small flame shape
		var flame_height = randf_range(20, 35)
		var flame_width = randf_range(5, 8)

		flame.polygon = PackedVector2Array([
			flame_pos + Vector2(-flame_width, 0),
			flame_pos + Vector2(-flame_width * 0.6, -flame_height * 0.4),
			flame_pos + Vector2(-flame_width * 0.3, -flame_height * 0.7),
			flame_pos + Vector2(0, -flame_height),
			flame_pos + Vector2(flame_width * 0.3, -flame_height * 0.7),
			flame_pos + Vector2(flame_width * 0.6, -flame_height * 0.4),
			flame_pos + Vector2(flame_width, 0),
		])

		# Flame colors - gradient from base to tip
		flame.vertex_colors = PackedColorArray([
			Color(1.0, 0.35, 0.0, 0.9),   # Base - deep orange
			Color(1.0, 0.5, 0.0, 0.85),
			Color(1.0, 0.65, 0.1, 0.8),
			Color(1.0, 0.85, 0.3, 0.55),  # Tip - yellow, fading
			Color(1.0, 0.65, 0.1, 0.8),
			Color(1.0, 0.5, 0.0, 0.85),
			Color(1.0, 0.35, 0.0, 0.9),
		])

		flame.set_meta("base_pos", flame_pos)
		flame.set_meta("base_height", flame_height)
		flame.set_meta("base_width", flame_width)
		flame.set_meta("phase", randf() * TAU)

		hearth_sprite.add_child(flame)
		flame_nodes.append(flame)

func create_hearth_light() -> void:
	"""Create the warm light emanating from the coals"""
	hearth_light = PointLight2D.new()
	hearth_light.name = "HearthLight"
	hearth_light.position = Vector2.ZERO

	hearth_light.energy = BASE_LIGHT_ENERGY
	hearth_light.texture_scale = LIGHT_TEXTURE_SCALE
	hearth_light.color = Color(1.0, 0.5, 0.18)  # Warm coal glow
	hearth_light.blend_mode = Light2D.BLEND_MODE_ADD

	# Create soft radial gradient
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center = Vector2(128, 128)
	var max_radius = 128.0

	for x in range(256):
		for y in range(256):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			alpha = alpha * alpha * alpha  # Cubic falloff
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture = ImageTexture.create_from_image(img)
	hearth_light.texture = texture

	add_child(hearth_light)

func create_ember_particles() -> void:
	"""Create subtle rising ember particles"""
	var embers = CPUParticles2D.new()
	embers.name = "EmberParticles"
	embers.emitting = true
	embers.amount = 12
	embers.lifetime = 2.0
	embers.z_index = 5

	# Emission shape - rectangular to match hearth
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(HEARTH_WIDTH * 0.35, HEARTH_HEIGHT * 0.25)

	# Movement - slow rise with slight drift
	embers.direction = Vector2(0, -1)
	embers.spread = 20.0
	embers.initial_velocity_min = 12.0
	embers.initial_velocity_max = 25.0
	embers.gravity = Vector2(0, -8)  # Upward drift

	# Size - tiny glowing dots
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 2.5

	# Color ramp - ember orange fading out
	var color_ramp = Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.55, 0.15, 1.0))
	color_ramp.set_color(1, Color(1.0, 0.3, 0.0, 0.0))
	embers.color_ramp = color_ramp

	add_child(embers)

func _cache_animated_nodes() -> void:
	"""Cache references to animated nodes"""
	coal_nodes.clear()
	flame_nodes.clear()

	if hearth_sprite:
		for child in hearth_sprite.get_children():
			if child.name.begins_with("Coal") and child is Polygon2D:
				coal_nodes.append(child)
			elif child.name.begins_with("Flame") and child is Polygon2D:
				flame_nodes.append(child)

func animate_hearth() -> void:
	"""Animate coals pulsing and flames flickering"""
	var time = Time.get_ticks_msec() / 1000.0

	# Pre-calculate group pulse values (3 groups with different timings)
	# Group 0: Fast, strong pulse (most intense)
	# Group 1: Medium speed, medium intensity
	# Group 2: Slow, subtle pulse (least intense)
	var group_pulses = [
		sin(time * 2.8) * 0.22 + sin(time * 4.5) * 0.12,  # Group 0: fast & bright
		sin(time * 1.8 + 2.1) * 0.16 + sin(time * 3.2 + 1.0) * 0.08,  # Group 1: medium
		sin(time * 1.2 + 4.2) * 0.10 + sin(time * 2.0 + 3.0) * 0.06,  # Group 2: slow & subtle
	]

	# Animate coals - grouped pulsing glow
	for coal in coal_nodes:
		if not is_instance_valid(coal):
			continue

		var heat = coal.get_meta("heat", 0.5)
		var glow_group = coal.get_meta("glow_group", 0)

		# Get pulse for this coal's group
		var pulse = group_pulses[glow_group]

		# Hotter coals pulse more dramatically
		var brightness = 1.0 + pulse * (0.5 + heat * 0.5)

		coal.modulate = Color(brightness, brightness * 0.92, brightness * 0.85, 1.0)

	# Animate flames - flicker and sway
	for flame in flame_nodes:
		if not is_instance_valid(flame):
			continue

		var phase = flame.get_meta("phase", 0.0)
		var base_pos = flame.get_meta("base_pos", Vector2.ZERO)
		var base_height = flame.get_meta("base_height", 25.0)
		var base_width = flame.get_meta("base_width", 6.0)

		# Flicker intensity
		var flicker = sin(time * 4.5 + phase) * 0.18 + sin(time * 7.5 + phase * 1.5) * 0.12
		var sway = sin(time * 2.0 + phase) * 1.5

		var height = base_height * (1.0 + flicker)
		var width = base_width * (1.0 + flicker * 0.4)

		flame.polygon = PackedVector2Array([
			base_pos + Vector2(-width + sway * 0.25, 0),
			base_pos + Vector2(-width * 0.6 + sway * 0.4, -height * 0.4),
			base_pos + Vector2(-width * 0.3 + sway * 0.6, -height * 0.7),
			base_pos + Vector2(sway * 0.8, -height),
			base_pos + Vector2(width * 0.3 + sway * 0.6, -height * 0.7),
			base_pos + Vector2(width * 0.6 + sway * 0.4, -height * 0.4),
			base_pos + Vector2(width + sway * 0.25, 0),
		])

		# Opacity flicker
		flame.modulate.a = 0.88 + flicker * 0.12

	# Animate light - subtle flicker
	if hearth_light and is_instance_valid(hearth_light):
		var light_flicker = sin(time * 3.0) * 0.08 + sin(time * 5.5) * 0.05
		hearth_light.energy = BASE_LIGHT_ENERGY + light_flicker
