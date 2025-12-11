extends Node2D
class_name WallTorch

## 🔥 WallTorch - Wall-mounted Cave Lighting
## - Mounted to cave walls with bracket/sconce
## - Similar visual style to Torch but horizontal mount
## - Can face left or right depending on which wall

# Visual configuration
@export var fire_color_inner: Color = Color(1.0, 0.8, 0.2)  # Bright yellow-orange
@export var fire_color_outer: Color = Color(1.0, 0.3, 0.0)  # Deep orange-red
@export var facing_left: bool = false  # If true, torch faces left (mounted on right wall)

# References
var fire_sprite: Node2D = null
var fire_audio: AudioStreamPlayer2D = null

# Performance: throttle animation updates and cache flame nodes
var animation_timer: float = 0.0
const ANIMATION_UPDATE_INTERVAL: float = 0.05  # Update 20 times per second
var flame_nodes: Array = []  # Cache flame children
var torch_light: PointLight2D = null  # Cache light reference

# Cave torch light settings - bright for dark caves
const BASE_LIGHT_ENERGY: float = 4.5
const MIN_LIGHT_ENERGY: float = 4.0
const MAX_LIGHT_ENERGY: float = 5.0

func _ready() -> void:
	# Create visual representation
	create_torch_visual()

	# Create lighting
	create_torch_light()

	# Create looping fire sound (very quiet for torches)
	create_fire_audio()

	# Cache flame nodes for performance
	await get_tree().process_frame
	if fire_sprite:
		for child in fire_sprite.get_children():
			if child.name.begins_with("Flame_"):
				flame_nodes.append(child)
	torch_light = get_node_or_null("TorchLight")

func _physics_process(delta: float) -> void:
	# Throttle animation updates for performance
	animation_timer += delta
	if animation_timer < ANIMATION_UPDATE_INTERVAL:
		return
	animation_timer = 0.0

	# Animate fire
	animate_fire(delta)

func create_torch_visual() -> void:
	"""Create wall-mounted torch - simple dark iron bracket with fire bowl"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.scale = Vector2(0.85, 0.85)
	add_child(fire_sprite)

	# Direction: -1 = torch extends left, 1 = torch extends right
	var dir = -1 if facing_left else 1

	# === ALL DARK IRON === (neutral gray, no warm tint)
	var iron = Color(0.12, 0.12, 0.12, 1.0)  # Dark iron - neutral gray, almost black

	# Simple wall mount - small square
	var mount = Polygon2D.new()
	mount.polygon = PackedVector2Array([
		Vector2(0, -5),
		Vector2(dir * 4, -5),
		Vector2(dir * 4, 5),
		Vector2(0, 5)
	])
	mount.color = iron
	mount.z_index = -1
	fire_sprite.add_child(mount)

	# Arm - simple tapered bar
	var arm = Polygon2D.new()
	arm.polygon = PackedVector2Array([
		Vector2(dir * 3, -3),
		Vector2(dir * 18, -2),
		Vector2(dir * 18, 2),
		Vector2(dir * 3, 3)
	])
	arm.color = iron
	arm.z_index = -1
	fire_sprite.add_child(arm)

	# Bowl - simple oval seen from above
	var bowl = Polygon2D.new()
	bowl.polygon = PackedVector2Array([
		Vector2(dir * 14, -5),
		Vector2(dir * 20, -6),
		Vector2(dir * 26, -5),
		Vector2(dir * 28, 0),
		Vector2(dir * 26, 5),
		Vector2(dir * 20, 6),
		Vector2(dir * 14, 5),
		Vector2(dir * 12, 0)
	])
	bowl.color = iron
	bowl.z_index = 0
	fire_sprite.add_child(bowl)

	# Bowl interior - dark hole where fire sits
	var inner = Polygon2D.new()
	inner.polygon = PackedVector2Array([
		Vector2(dir * 16, -3),
		Vector2(dir * 20, -4),
		Vector2(dir * 24, -3),
		Vector2(dir * 25, 0),
		Vector2(dir * 24, 3),
		Vector2(dir * 20, 4),
		Vector2(dir * 16, 3),
		Vector2(dir * 15, 0)
	])
	inner.color = Color(0.04, 0.04, 0.04, 1.0)  # Very dark, neutral
	inner.z_index = 1
	fire_sprite.add_child(inner)

	# === FLAMES === (rising from bowl)
	create_fire_particles(dir)

func create_fire_particles(dir: int) -> void:
	"""Create layered polygon flames rising from torch bowl"""
	var flame_center_x = dir * 20  # Center of bowl

	# Create 2 flame layers
	for layer in range(2):
		for i in range(2 + layer * 2):  # 2, 4 flames per layer
			var flame = Polygon2D.new()
			# Tighter horizontal spread - reduced from (5 - layer * 1.5) to (3 - layer * 1.0)
			var offset = (i - (0.5 + layer)) * (3 - layer * 1.0)
			var height = (14 - layer * 4) + randf() * 3
			var base_width = (4.0 - layer * 1.0)

			# Base position (sitting in bowl) - lowered 10px
			var base_y = 2 - layer * 2

			# Gentle sway
			var lean = offset * 0.2
			var sway = randf_range(-0.3, 0.3)

			# Flame shape pointing upward
			flame.polygon = PackedVector2Array([
				Vector2(flame_center_x + offset - base_width, base_y),
				Vector2(flame_center_x + offset - base_width * 0.7 + lean * 0.4 + sway, base_y - height * 0.5),
				Vector2(flame_center_x + offset - base_width * 0.4 + lean * 0.7 + sway, base_y - height * 0.85),
				Vector2(flame_center_x + offset + lean + sway, base_y - height),
				Vector2(flame_center_x + offset + base_width * 0.4 + lean * 0.7 + sway, base_y - height * 0.85),
				Vector2(flame_center_x + offset + base_width * 0.7 + lean * 0.4 + sway, base_y - height * 0.5),
				Vector2(flame_center_x + offset + base_width, base_y)
			])

			# Color by layer - BRIGHT flames
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - bright red/orange core
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.8, 0.2, 0.85))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
			else:  # Top - bright yellow/white tips
				colors.append(Color(1.0, 0.75, 0.15, 0.9))
				colors.append(Color(1.0, 0.9, 0.3, 0.85))
				colors.append(Color(1.0, 1.0, 0.5, 0.8))
				colors.append(Color(1.0, 1.0, 0.75, 0.75))
				colors.append(Color(1.0, 1.0, 0.5, 0.8))
				colors.append(Color(1.0, 0.9, 0.3, 0.85))
				colors.append(Color(1.0, 0.75, 0.15, 0.9))

			flame.vertex_colors = colors
			flame.name = "Flame_L" + str(layer) + "_" + str(i)
			flame.z_index = layer + 2
			fire_sprite.add_child(flame)

func create_torch_light() -> void:
	"""Create directional cone light pointing into the corridor"""
	var light = PointLight2D.new()
	light.name = "TorchLight"

	# Direction torch faces
	var dir = -1 if facing_left else 1

	# Position at flame location
	light.position = Vector2(dir * 20, 0)

	# Bright lighting for cave visibility
	light.energy = BASE_LIGHT_ENERGY
	light.texture_scale = 14.0  # Large radius for cave corridors

	# Warm orange-yellow fire color
	light.color = Color(1.0, 0.6, 0.25)

	# Create procedural CONE texture pointing in torch direction
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center = Vector2(128, 128)
	var max_radius = 128.0

	for x in range(256):
		for y in range(256):
			var pos = Vector2(x, y)
			var to_point = pos - center
			var dist = to_point.length()

			# Base radial falloff
			var radial_falloff = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			radial_falloff = radial_falloff * radial_falloff

			# Directional cone factor
			# Light spreads in the direction the torch faces (dir)
			# For facing_left (dir=-1), light goes left (-X)
			# For facing_right (dir=1), light goes right (+X)
			var cone_factor = 1.0
			if dist > 5:  # Avoid division issues at center
				var normalized = to_point.normalized()
				# Cone direction: torch faces +X (dir=1) or -X (dir=-1)
				var cone_dir = Vector2(dir, 0)
				var dot = normalized.dot(cone_dir)
				# Wider cone (120 degrees each side) - but stronger in torch direction
				# dot = 1 means pointing same direction, -1 means opposite
				# Map: -1 to 1 -> 0.3 to 1.0 (back still gets some light, front gets most)
				cone_factor = lerp(0.2, 1.0, (dot + 1.0) / 2.0)
				# Boost the front hemisphere more
				if dot > 0:
					cone_factor = lerp(0.6, 1.0, dot)
				else:
					cone_factor = lerp(0.1, 0.6, (dot + 1.0))

			var alpha = radial_falloff * cone_factor
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture = ImageTexture.create_from_image(img)
	light.texture = texture

	# Blend mode
	light.blend_mode = Light2D.BLEND_MODE_ADD

	add_child(light)
	torch_light = light

func create_fire_audio() -> void:
	"""Create very quiet looping fire sound for torch"""
	var campfire_sound = load("res://assets/audio/sfx/ambient/campfire_loop.wav")
	if not campfire_sound:
		return

	# Use AudioStreamPlayer2D for spatial audio
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.name = "FireAudio"
	fire_audio.stream = campfire_sound
	fire_audio.volume_db = -26.0  # Very quiet for wall torches
	fire_audio.bus = "Master"
	fire_audio.autoplay = false

	# Spatial audio settings - shorter range
	fire_audio.max_distance = 150.0
	fire_audio.attenuation = 3.0  # Fast falloff
	fire_audio.panning_strength = 0.5

	add_child(fire_audio)

	# Connect finished signal for randomization
	fire_audio.finished.connect(_on_fire_audio_loop)

	# Wait a frame then play
	await get_tree().process_frame
	randomize_fire_audio()
	fire_audio.play()

func randomize_fire_audio() -> void:
	"""Randomly vary pitch and volume"""
	if not fire_audio:
		return

	fire_audio.pitch_scale = randf_range(0.92, 1.08)
	fire_audio.volume_db = randf_range(-28.0, -24.0)

func _on_fire_audio_loop() -> void:
	"""Called when fire audio finishes"""
	if fire_audio:
		randomize_fire_audio()
		fire_audio.play()

func animate_fire(_delta: float) -> void:
	"""Animate torch flames with flickering"""
	if flame_nodes.is_empty():
		return

	var time = Time.get_ticks_msec() / 1000.0

	# Animate flames using cached nodes
	for i in range(flame_nodes.size()):
		var child = flame_nodes[i]
		if not is_instance_valid(child):
			continue
		var speed = 1.3 + i * 0.15
		var flicker = sin(time * speed + i * 1.5)
		var sway = cos(time * speed * 0.6 + i * 0.8)

		# Vertical flicker
		child.scale.y = 1.0 + flicker * 0.2
		# Horizontal sway
		child.scale.x = 1.0 + sway * 0.1
		# Opacity flicker
		child.modulate.a = 1.0 + flicker * 0.08
		# Position wobble
		child.position.y = sway * 0.4

	# Animate torch light (subtle flickering)
	if torch_light and is_instance_valid(torch_light):
		var flicker = sin(time * 3.0) * 0.5 + cos(time * 4.5) * 0.3
		torch_light.energy = BASE_LIGHT_ENERGY + flicker * 0.2
		torch_light.texture_scale = 3.0 + flicker * 0.15
