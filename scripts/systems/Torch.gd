extends Node2D
class_name Torch

## 🔥 Torch - Path Lighting
## - Provides ambient light along the path
## - Similar visual style to campfire but smaller
## - No gameplay mechanics (no healing/deterrent)

# Visual configuration
@export var fire_color_inner: Color = Color(1.0, 0.8, 0.2)  # Bright yellow-orange
@export var fire_color_outer: Color = Color(1.0, 0.3, 0.0)  # Deep orange-red

# References
var fire_sprite: Node2D = null
var fire_audio: AudioStreamPlayer2D = null

# Performance: throttle animation updates and cache flame nodes
var animation_timer: float = 0.0
const ANIMATION_UPDATE_INTERVAL: float = 0.05  # Update 20 times per second
var flame_nodes: Array = []  # Cache flame children
var torch_light: PointLight2D = null  # Cache light reference

# Day/night light scaling
const BASE_LIGHT_ENERGY: float = 1.2
const MIN_LIGHT_ENERGY: float = 0.1  # Subtle glow during bright day
const MAX_LIGHT_ENERGY: float = 1.6  # Moderate glow at night

func _ready() -> void:
	# Create visual representation
	create_torch_visual()

	# Create lighting
	create_torch_light()

	# Create looping fire sound (very quiet for torches)
	create_fire_audio()

	# Cache flame nodes for performance (avoid iterating children every frame)
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
	"""Create torch with wooden pole and flames"""
	fire_sprite = Node2D.new()
	fire_sprite.name = "FireSprite"
	fire_sprite.position = Vector2(0, -15)  # Raise flames above pole
	fire_sprite.scale = Vector2(0.8, 0.8)  # Smaller than campfire
	add_child(fire_sprite)

	# === WOODEN POLE === (vertical stick holding fire)
	var pole_color_dark = Color(0.25, 0.18, 0.12, 1.0)
	var pole_color = Color(0.35, 0.25, 0.18, 1.0)
	var pole_color_light = Color(0.45, 0.32, 0.22, 1.0)

	# Main pole body (simplified - removed highlight/shadow Line2Ds)
	var pole = Polygon2D.new()
	pole.polygon = PackedVector2Array([
		Vector2(-3, 40),    # Bottom left
		Vector2(3, 40),     # Bottom right
		Vector2(2, -10),    # Top right
		Vector2(-2, -10)    # Top left
	])
	pole.color = pole_color
	pole.z_index = -1
	fire_sprite.add_child(pole)

	# === FLAMES === (small layered flames on top)
	create_fire_particles()

func create_fire_particles() -> void:
	"""Create small layered polygon flames for torch - bright like campfire"""
	# Create 2 flame layers (simpler than campfire)
	for layer in range(2):
		for i in range(2 + layer * 2):  # 2, 4 flames per layer
			var flame = Polygon2D.new()
			var offset = (i - (0.5 + layer)) * (6 - layer * 2)
			var height = (12 - layer * 4) + randf() * 2
			var base_width = (4.0 - layer * 1.0)

			# Vary base Y
			var base_y = 5 - layer * 2 + abs(offset) * 0.1

			# Gentle sway
			var lean = offset * 0.25
			var sway = randf_range(-0.3, 0.3)

			# Simple flame shape
			flame.polygon = PackedVector2Array([
				Vector2(offset - base_width, base_y),
				Vector2(offset - base_width * 0.7 + lean * 0.4 + sway, -height * 0.5),
				Vector2(offset - base_width * 0.4 + lean * 0.7 + sway, -height * 0.85),
				Vector2(offset + lean + sway, -height),
				Vector2(offset + base_width * 0.4 + lean * 0.7 + sway, -height * 0.85),
				Vector2(offset + base_width * 0.7 + lean * 0.4 + sway, -height * 0.5),
				Vector2(offset + base_width, base_y)
			])

			# Color by layer - BRIGHT flames matching campfire intensity
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - bright red/orange core (campfire style)
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.8, 0.2, 0.85))
				colors.append(Color(1.0, 0.65, 0.1, 0.88))
				colors.append(Color(1.0, 0.5, 0.0, 0.92))
				colors.append(Color(1.0, 0.3, 0.0, 0.95))
			else:  # Top - bright yellow/white tips (campfire style)
				colors.append(Color(1.0, 0.75, 0.15, 0.9))
				colors.append(Color(1.0, 0.9, 0.3, 0.85))
				colors.append(Color(1.0, 1.0, 0.5, 0.8))
				colors.append(Color(1.0, 1.0, 0.75, 0.75))
				colors.append(Color(1.0, 1.0, 0.5, 0.8))
				colors.append(Color(1.0, 0.9, 0.3, 0.85))
				colors.append(Color(1.0, 0.75, 0.15, 0.9))

			flame.vertex_colors = colors
			flame.name = "Flame_L" + str(layer) + "_" + str(i)
			flame.z_index = layer + 1
			fire_sprite.add_child(flame)

func create_torch_light() -> void:
	"""Create torch light (smaller and dimmer than campfire)"""
	var torch_light = PointLight2D.new()
	torch_light.name = "TorchLight"
	torch_light.position = Vector2(0, -15)

	# Bright lighting for path visibility
	torch_light.energy = 1.2  # Warm ambient glow
	torch_light.texture_scale = 2.5  # Larger radius for better path coverage

	# Warm orange-yellow fire color
	torch_light.color = Color(1.0, 0.7, 0.3)

	# Create procedural radial gradient texture
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var center = Vector2(128, 128)
	var max_radius = 128.0

	for x in range(256):
		for y in range(256):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			# Smooth falloff curve
			alpha = alpha * alpha
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture = ImageTexture.create_from_image(img)
	torch_light.texture = texture

	# Enable shadows
	torch_light.shadow_enabled = true
	torch_light.shadow_color = Color(0.0, 0.0, 0.0, 0.6)

	# Blend mode
	torch_light.blend_mode = Light2D.BLEND_MODE_ADD

	add_child(torch_light)

func create_fire_audio() -> void:
	"""Create very quiet looping fire sound for torch"""
	var campfire_sound = load("res://assets/sounds/ambient/campfire_loop.wav")
	if not campfire_sound:
		return

	# Use AudioStreamPlayer2D for spatial audio
	fire_audio = AudioStreamPlayer2D.new()
	fire_audio.name = "FireAudio"
	fire_audio.stream = campfire_sound
	fire_audio.volume_db = -22.0  # Quieter ambient level for torches
	fire_audio.bus = "Master"
	fire_audio.autoplay = false

	# Spatial audio settings - shorter range
	fire_audio.max_distance = 200.0  # Hear up to 200 units away
	fire_audio.attenuation = 2.5  # Faster falloff
	fire_audio.panning_strength = 0.6

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

	# Randomize pitch (±5%)
	fire_audio.pitch_scale = randf_range(0.95, 1.05)

	# Randomize volume slightly - ambient level
	fire_audio.volume_db = randf_range(-24.0, -20.0)

func _on_fire_audio_loop() -> void:
	"""Called when fire audio finishes"""
	if fire_audio:
		randomize_fire_audio()
		fire_audio.play()

func animate_fire(_delta: float) -> void:
	"""Animate torch flames - bright like campfire"""
	if flame_nodes.is_empty():
		return

	var time = Time.get_ticks_msec() / 1000.0

	# Get day/night brightness factor from TimeManager
	var time_brightness = 1.0  # Default to full brightness
	if TimeManager and TimeManager.canvas_modulate:
		time_brightness = TimeManager.get_brightness()

	# Calculate light energy based on time of day
	# At night (brightness ~0.51), lights should be bright
	# At day (brightness ~0.99), lights should be dim
	# Map: 0.51 -> MAX, 0.99 -> MIN
	var day_factor = inverse_lerp(0.51, 0.99, time_brightness)
	day_factor = clamp(day_factor, 0.0, 1.0)
	var target_energy = lerp(MAX_LIGHT_ENERGY, MIN_LIGHT_ENERGY, day_factor)

	# Animate flames using cached nodes (flicker and sway)
	# Keep flames consistently bright (like campfire) - only boost slightly at night
	var flame_brightness_mult = lerp(1.3, 1.0, day_factor)  # 1.3x at night, 1.0x at day (subtle)

	for i in range(flame_nodes.size()):
		var child = flame_nodes[i]
		if not is_instance_valid(child):
			continue
		var speed = 1.2 + i * 0.18  # Slightly faster than campfire
		var flicker = sin(time * speed + i * 1.5)
		var sway = cos(time * speed * 0.6 + i * 0.8)

		# Vertical flicker
		child.scale.y = 1.0 + flicker * 0.25
		# Horizontal sway
		child.scale.x = 1.0 + sway * 0.12
		# Keep flames bright at all times (like campfire) - no day dimming
		# Subtle flicker in opacity only
		child.modulate.a = 1.0 + flicker * 0.1
		# Flame color stays bright - slight boost at night
		child.modulate.r = flame_brightness_mult
		child.modulate.g = flame_brightness_mult
		child.modulate.b = flame_brightness_mult * 0.85  # Keep warm tint
		# Position wobble
		child.position.x = sway * 0.5

	# Animate torch light using cached reference (subtle flickering + day/night scaling)
	if torch_light and is_instance_valid(torch_light):
		var flicker = sin(time * 2.8) * 0.5 + cos(time * 4.2) * 0.3
		var flicker_amount = target_energy * 0.15  # Flicker proportional to base energy
		torch_light.energy = target_energy + flicker * flicker_amount
		# Scale light radius based on time - moderate glow aura at night
		var base_scale = lerp(2.8, 1.8, day_factor)  # 2.8x at night, 1.8x at day
		torch_light.texture_scale = base_scale + flicker * 0.15
