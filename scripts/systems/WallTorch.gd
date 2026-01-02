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
@export var base_rotation_deg: float = 0.0  # Rotation of mount only (flames stay upright)

# References
var fire_sprite: Node2D = null
var fire_audio: AudioStreamPlayer2D = null

# Performance: throttle animation updates and cache flame nodes
var animation_timer: float = 0.0
const ANIMATION_UPDATE_INTERVAL: float = 0.05  # Update 20 times per second
var flame_nodes: Array = []  # Cache flame children
var torch_light: PointLight2D = null  # Cache light reference

# Cave torch light settings - localized glow with extended bleed
const BASE_LIGHT_ENERGY: float = 2.5
const BASE_TEXTURE_SCALE: float = 15.0  # Extended radius for coverage bleed

func _ready() -> void:
	# Skip all visuals on dedicated server - wall torches are purely decorative
	if "--server" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		return

	# Create visual representation
	create_torch_visual()

	# Create lighting
	create_torch_light()

	# Create looping fire sound (very quiet for torches)
	create_fire_audio()

	# Cache flame nodes for performance (may be nested in containers)
	await get_tree().process_frame
	if fire_sprite:
		_cache_flames_recursive(fire_sprite)
	torch_light = get_node_or_null("TorchLight")

func _cache_flames_recursive(node: Node) -> void:
	"""Recursively find and cache all flame nodes"""
	for child in node.get_children():
		if child.name.begins_with("Flame_"):
			flame_nodes.append(child)
		elif child.get_child_count() > 0:
			_cache_flames_recursive(child)

func _physics_process(delta: float) -> void:
	# Throttle animation updates for performance
	animation_timer += delta
	if animation_timer < ANIMATION_UPDATE_INTERVAL:
		return
	animation_timer = 0.0

	# Animate fire
	animate_fire(delta)

func create_torch_visual() -> void:
	"""Create wall-mounted sconce torch - bracket below, fire above"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.scale = Vector2(0.85, 0.85)
	add_child(fire_sprite)

	# Direction: -1 = mounted on right wall (faces left), 1 = mounted on left wall (faces right)
	var dir = -1 if facing_left else 1

	# === DARK IRON === (visible against dark backgrounds)
	var iron = Color(0.18, 0.16, 0.14, 1.0)  # Dark iron with slight warmth for visibility
	var iron_dark = Color(0.08, 0.07, 0.06, 1.0)  # Darker accent

	# Mount container - can be rotated independently
	var mount_container = Node2D.new()
	mount_container.name = "MountContainer"
	mount_container.rotation_degrees = base_rotation_deg
	fire_sprite.add_child(mount_container)

	# Wall plate - vertical rectangle flush against wall
	var wall_plate = Polygon2D.new()
	wall_plate.polygon = PackedVector2Array([
		Vector2(0, -8),
		Vector2(dir * 6, -8),
		Vector2(dir * 6, 12),
		Vector2(0, 12)
	])
	wall_plate.color = iron
	wall_plate.z_index = 0
	mount_container.add_child(wall_plate)

	# Bracket arm - extends out and curves up to hold bowl
	var bracket = Polygon2D.new()
	bracket.polygon = PackedVector2Array([
		Vector2(dir * 4, 8),      # Start at wall plate
		Vector2(dir * 4, 4),
		Vector2(dir * 12, -2),    # Curve outward and up
		Vector2(dir * 16, -6),
		Vector2(dir * 18, -6),    # Top of bracket
		Vector2(dir * 14, 0),
		Vector2(dir * 6, 8)       # Back to wall
	])
	bracket.color = iron
	bracket.z_index = 0
	mount_container.add_child(bracket)

	# Bowl/cup that holds the fire - sits on top of bracket
	var bowl = Polygon2D.new()
	bowl.polygon = PackedVector2Array([
		Vector2(dir * 10, -4),
		Vector2(dir * 12, -8),
		Vector2(dir * 16, -10),
		Vector2(dir * 20, -10),
		Vector2(dir * 24, -8),
		Vector2(dir * 26, -4),
		Vector2(dir * 25, 0),
		Vector2(dir * 11, 0)
	])
	bowl.color = iron
	bowl.z_index = 1
	mount_container.add_child(bowl)

	# Bowl interior - where coals/fire sits
	var inner = Polygon2D.new()
	inner.polygon = PackedVector2Array([
		Vector2(dir * 13, -5),
		Vector2(dir * 15, -7),
		Vector2(dir * 21, -7),
		Vector2(dir * 23, -5),
		Vector2(dir * 22, -2),
		Vector2(dir * 14, -2)
	])
	inner.color = iron_dark
	inner.z_index = 2
	mount_container.add_child(inner)

	# === FLAMES === (in mount container but counter-rotated to stay upright)
	var flame_container = Node2D.new()
	flame_container.name = "FlameContainer"
	flame_container.position = Vector2(dir * 18, -6)  # Position at bowl center
	flame_container.rotation_degrees = -base_rotation_deg  # Counter-rotate to stay upright
	mount_container.add_child(flame_container)

	create_fire_particles_in_container(flame_container)

func create_fire_particles_in_container(container: Node2D) -> void:
	"""Create layered polygon flames at container origin (for rotated mounts)"""
	# Create 2 flame layers - flames are centered at (0, 0) of container
	for layer in range(2):
		for i in range(2 + layer * 2):  # 2, 4 flames per layer
			var flame = Polygon2D.new()
			var offset = (i - (0.5 + layer)) * (3 - layer * 1.0)
			var height = (14 - layer * 4) + randf() * 3
			var base_width = (4.0 - layer * 1.0)

			# Base at container origin
			var base_y = 0 - layer * 2

			var lean = offset * 0.2
			var sway = randf_range(-0.3, 0.3)

			flame.polygon = PackedVector2Array([
				Vector2(offset - base_width, base_y),
				Vector2(offset - base_width * 0.7 + lean * 0.4 + sway, base_y - height * 0.5),
				Vector2(offset - base_width * 0.4 + lean * 0.7 + sway, base_y - height * 0.85),
				Vector2(offset + lean + sway, base_y - height),
				Vector2(offset + base_width * 0.4 + lean * 0.7 + sway, base_y - height * 0.85),
				Vector2(offset + base_width * 0.7 + lean * 0.4 + sway, base_y - height * 0.5),
				Vector2(offset + base_width, base_y)
			])

			var colors = PackedColorArray()
			if layer == 0:
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.8, 0.2, 0.85))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
			else:
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
			container.add_child(flame)

func create_fire_particles(dir: int) -> void:
	"""Create layered polygon flames rising from torch bowl (legacy, for non-rotated)"""
	var flame_center_x = dir * 18  # Center of bowl

	# Create 2 flame layers
	for layer in range(2):
		for i in range(2 + layer * 2):  # 2, 4 flames per layer
			var flame = Polygon2D.new()
			# Tighter horizontal spread
			var offset = (i - (0.5 + layer)) * (3 - layer * 1.0)
			var height = (14 - layer * 4) + randf() * 3
			var base_width = (4.0 - layer * 1.0)

			# Base position (sitting in bowl) - raised to match new bowl position
			var base_y = -6 - layer * 2

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
	"""Create soft radial torch light"""
	var light = PointLight2D.new()
	light.name = "TorchLight"

	# Direction torch faces
	var dir = -1 if facing_left else 1

	# Position at flame location
	light.position = Vector2(dir * 20, 0)

	# Localized torch lighting
	light.energy = BASE_LIGHT_ENERGY
	light.texture_scale = BASE_TEXTURE_SCALE

	# Warm orange-yellow fire color
	light.color = Color(1.0, 0.6, 0.25)

	# Create radial gradient with extended bleed coverage
	# Strong core (inner 30%) + gradual bleed (outer 70%)
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center = Vector2(64, 64)
	var max_radius = 64.0

	for x in range(128):
		for y in range(128):
			var dist = Vector2(x, y).distance_to(center)
			var normalized_dist = clamp(dist / max_radius, 0.0, 1.0)

			# Two-zone falloff: bright core + extended bleed
			var alpha: float
			if normalized_dist < 0.3:
				# Inner core - strong light (cubic falloff from 1.0)
				var core_dist = normalized_dist / 0.3
				alpha = 1.0 - pow(core_dist, 2.0) * 0.4  # 1.0 to 0.6
			else:
				# Outer bleed - gradual extended coverage
				var bleed_dist = (normalized_dist - 0.3) / 0.7
				alpha = 0.6 * pow(1.0 - bleed_dist, 1.5)  # 0.6 to 0.0 gradual

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
		torch_light.texture_scale = BASE_TEXTURE_SCALE + flicker * 0.15
