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

func _ready() -> void:
	# Create visual representation
	create_torch_visual()

	# Create lighting
	create_torch_light()

	# Create looping fire sound (very quiet for torches)
	create_fire_audio()

func _physics_process(delta: float) -> void:
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

	# Main pole body
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

	# Pole highlight
	var pole_highlight = Line2D.new()
	pole_highlight.width = 1.5
	pole_highlight.default_color = pole_color_light
	pole_highlight.add_point(Vector2(-2, 40))
	pole_highlight.add_point(Vector2(-2, -10))
	pole_highlight.z_index = -1
	fire_sprite.add_child(pole_highlight)

	# Pole shadow
	var pole_shadow = Line2D.new()
	pole_shadow.width = 1.0
	pole_shadow.default_color = pole_color_dark
	pole_shadow.add_point(Vector2(2, 40))
	pole_shadow.add_point(Vector2(2, -10))
	pole_shadow.z_index = -1
	fire_sprite.add_child(pole_shadow)

	# === FLAMES === (small layered flames on top)
	create_fire_particles()

	# === BASE GLOW === (subtle glow at base of flames)
	var base_glow = Polygon2D.new()
	var base_points = PackedVector2Array()
	for i in range(12):
		var angle = (i * TAU) / 12.0
		var radius = 12.0 + randf() * 2.0
		base_points.append(Vector2(cos(angle), sin(angle)) * radius)
	base_glow.polygon = base_points
	base_glow.color = Color(1.0, 0.5, 0.1, 0.1)  # Very faint
	base_glow.z_index = 0
	fire_sprite.add_child(base_glow)

func create_fire_particles() -> void:
	"""Create small layered polygon flames for torch"""
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

			# Color by layer - bright, vibrant flames for visibility
			var colors = PackedColorArray()
			if layer == 0:  # Bottom - bright red/orange
				colors.append(Color(1.0, 0.3, 0.0, 0.9))
				colors.append(Color(1.0, 0.5, 0.1, 0.85))
				colors.append(Color(1.0, 0.65, 0.2, 0.8))
				colors.append(Color(1.0, 0.8, 0.3, 0.7))
				colors.append(Color(1.0, 0.65, 0.2, 0.8))
				colors.append(Color(1.0, 0.5, 0.1, 0.85))
				colors.append(Color(1.0, 0.3, 0.0, 0.9))
			else:  # Top - bright yellow/white
				colors.append(Color(1.0, 0.85, 0.4, 0.85))
				colors.append(Color(1.0, 0.9, 0.5, 0.8))
				colors.append(Color(1.0, 0.95, 0.7, 0.75))
				colors.append(Color(1.0, 1.0, 0.9, 0.7))
				colors.append(Color(1.0, 0.95, 0.7, 0.75))
				colors.append(Color(1.0, 0.9, 0.5, 0.8))
				colors.append(Color(1.0, 0.85, 0.4, 0.85))

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
	torch_light.energy = 1.4  # Brighter than before
	torch_light.texture_scale = 2.0  # Larger radius for better coverage

	# Warm orange-yellow fire color
	torch_light.color = Color(1.0, 0.7, 0.3)

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
	fire_audio.volume_db = -18.0  # Much quieter than campfire (-8.0)
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

	# Randomize volume slightly
	fire_audio.volume_db = randf_range(-19.5, -16.5)

func _on_fire_audio_loop() -> void:
	"""Called when fire audio finishes"""
	if fire_audio:
		randomize_fire_audio()
		fire_audio.play()

func animate_fire(delta: float) -> void:
	"""Animate torch flames"""
	if not fire_sprite:
		return

	var time = Time.get_ticks_msec() / 1000.0

	# Animate flames (flicker and sway)
	for child in fire_sprite.get_children():
		if child.name.begins_with("Flame_"):
			var idx = child.get_index()
			var speed = 1.2 + idx * 0.18  # Slightly faster than campfire
			var flicker = sin(time * speed + idx * 1.5)
			var sway = cos(time * speed * 0.6 + idx * 0.8)

			# Vertical flicker
			child.scale.y = 1.0 + flicker * 0.25
			# Horizontal sway
			child.scale.x = 1.0 + sway * 0.12
			# Opacity flicker
			child.modulate.a = 0.85 + flicker * 0.15
			# Position wobble
			child.position.x = sway * 0.5

	# Animate torch light (subtle flickering)
	if has_node("TorchLight"):
		var torch_light = get_node("TorchLight")
		var flicker = sin(time * 2.8) * 0.5 + cos(time * 4.2) * 0.3
		torch_light.energy = 0.8 + flicker * 0.2  # Flicker between 0.6 and 1.0
