extends Area2D
class_name Weakpoint

var max_hits: int = 3
var current_hits: int = 0
var is_destroyed: bool = false
var sprite: Polygon2D
var glow_sprite: Polygon2D
var sparkle_particles: CPUParticles2D
var shine_layers: Array = []  # Store shine polygons for brightness animation

# Color theme: "blood" for training dummy, "bone" for skeletons
var color_theme: String = "blood"

# Theme colors
var theme_colors = {
	"blood": {
		"base": Color(0.9, 0.12, 0.12, 1.0),  # Dark blood red
		"glow": Color(1.4, 0.2, 0.2, 0.85),  # Bright blood glow
		"shine": Color(2.0, 0.6, 0.6, 0.5),  # Red-white shine
		"flash": Color(1.2, 0.15, 0.15, 1.0),  # Bright blood flash
		"particle_base": Color(1.5, 0.15, 0.15, 1.0),  # Particle red
		"particle_dark": Color(1.2, 0.1, 0.1, 1.0),  # Dark blood
		"wave": Color(1.8, 0.2, 0.2, 1.0)  # Shockwave red
	},
	"bone": {
		"base": Color(0.92, 0.88, 0.78, 1.0),  # Cream/bone white
		"glow": Color(1.0, 0.95, 0.75, 0.85),  # Pale yellow glow
		"shine": Color(1.2, 1.15, 0.95, 0.6),  # Bright bone shine
		"flash": Color(1.1, 1.05, 0.9, 1.0),  # Bright bone flash
		"particle_base": Color(1.1, 1.05, 0.9, 1.0),  # Particle cream
		"particle_dark": Color(0.9, 0.85, 0.7, 1.0),  # Dark bone
		"wave": Color(1.0, 0.95, 0.8, 1.0)  # Shockwave cream
	},
	"poison": {
		"base": Color(0.2, 0.8, 0.3, 1.0),  # Toxic green
		"glow": Color(0.3, 1.2, 0.4, 0.85),  # Bright green glow
		"shine": Color(0.5, 1.5, 0.6, 0.5),  # Green-white shine
		"flash": Color(0.4, 1.4, 0.5, 1.0),  # Bright green flash
		"particle_base": Color(0.3, 1.3, 0.4, 1.0),  # Particle green
		"particle_dark": Color(0.15, 0.9, 0.2, 1.0),  # Dark toxic green
		"wave": Color(0.4, 1.5, 0.5, 1.0)  # Shockwave green
	},
	"pvp": {
		"base": Color(0.6, 0.2, 0.9, 1.0),  # Purple/violet
		"glow": Color(0.8, 0.3, 1.2, 0.85),  # Bright purple glow
		"shine": Color(0.9, 0.6, 1.5, 0.5),  # Purple-white shine
		"flash": Color(0.7, 0.3, 1.3, 1.0),  # Bright purple flash
		"particle_base": Color(0.7, 0.3, 1.2, 1.0),  # Particle purple
		"particle_dark": Color(0.5, 0.15, 0.8, 1.0),  # Dark purple
		"wave": Color(0.8, 0.4, 1.4, 1.0)  # Shockwave purple
	}
}

signal weakpoint_hit(weakpoint)
signal weakpoint_destroyed(weakpoint)
signal weakpoint_destroyed_local(weakpoint)  # Client-side tracking for crit window

# Track damage dealt for server validation
var damage_per_hit: int = 0  # Set by crit_window_manager
var total_damage_dealt: int = 0

func _ready() -> void:
	z_index = 300
	input_pickable = true

	# Add to weakpoints group for cursor detection
	add_to_group("weakpoints")

	# Make weakpoints unaffected by scene lights (always show true colors)
	var unshaded_material = CanvasItemMaterial.new()
	unshaded_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = unshaded_material

	var colors = theme_colors[color_theme]

	# 💎 HIGH-FIDELITY GEM/GLASS - Starts visible, brightens as it cracks
	sprite = Polygon2D.new()
	# ✨ START VISIBLE - 60% brightness (easier to see, still gets brighter)
	var dull_base = colors["base"] * 0.6
	dull_base.a = colors["base"].a
	sprite.color = dull_base
	sprite.antialiased = true  # Smooth edges

	# Perfect circle for gem-like appearance
	var points = PackedVector2Array()
	var size = 18.0
	var segments = 64  # Many segments for smooth circle

	for i in range(segments):
		var angle = (i * TAU) / segments
		var x = cos(angle) * size
		var y = sin(angle) * size
		points.append(Vector2(x, y))

	sprite.polygon = points
	add_child(sprite)

	# 💫 OUTER GLOW - Soft radiant aura (starts visible, grows with damage)
	glow_sprite = Polygon2D.new()
	var outer_glow = colors["glow"]
	outer_glow.a = 0.3  # ✨ START VISIBLE - 30% glow, grows to 80%
	glow_sprite.color = outer_glow
	glow_sprite.z_index = -1
	glow_sprite.antialiased = true

	var glow_points = PackedVector2Array()
	var glow_scale = 1.1  # Tight glow close to the gem
	for point in points:
		glow_points.append(point * glow_scale)
	glow_sprite.polygon = glow_points
	sprite.add_child(glow_sprite)

	# ✨ MULTIPLE SHINE HIGHLIGHTS - Glass-like reflections (start visible)
	# Large curved highlight (top)
	var shine1 = Polygon2D.new()
	shine1.color = Color(2.5, 2.5, 2.5, 0.3)  # ✨ START VISIBLE - 0.3 alpha, grows to 0.7
	shine1.z_index = 2
	shine1.antialiased = true
	var shine1_points = PackedVector2Array()
	shine1_points.append(Vector2(-8, -12))
	shine1_points.append(Vector2(6, -14))
	shine1_points.append(Vector2(8, -8))
	shine1_points.append(Vector2(0, -6))
	shine1_points.append(Vector2(-6, -8))
	shine1.polygon = shine1_points
	sprite.add_child(shine1)
	shine_layers.append(shine1)

	# Small bright spot (top-left)
	var shine2 = Polygon2D.new()
	shine2.color = Color(3.0, 3.0, 3.0, 0.35)  # ✨ START VISIBLE - grows to 0.9
	shine2.z_index = 3
	shine2.antialiased = true
	var shine2_points = PackedVector2Array()
	shine2_points.append(Vector2(-5, -10))
	shine2_points.append(Vector2(-2, -11))
	shine2_points.append(Vector2(-1, -8))
	shine2_points.append(Vector2(-4, -7))
	shine2.polygon = shine2_points
	sprite.add_child(shine2)
	shine_layers.append(shine2)

	# Bottom reflection (subtle)
	var shine3 = Polygon2D.new()
	shine3.color = Color(1.8, 1.8, 1.8, 0.15)  # ✨ START VISIBLE - grows to 0.3
	shine3.z_index = 1
	shine3.antialiased = true
	var shine3_points = PackedVector2Array()
	shine3_points.append(Vector2(-4, 8))
	shine3_points.append(Vector2(4, 8))
	shine3_points.append(Vector2(2, 4))
	shine3_points.append(Vector2(-2, 4))
	shine3.polygon = shine3_points
	sprite.add_child(shine3)
	shine_layers.append(shine3)

	# ✨ NO HEARTBEAT - let the click feedback be the main animation

	# Smooth dark outline for gem definition
	var outline = Line2D.new()
	outline.width = 1.5
	outline.antialiased = true  # Smooth outline
	# Darker version of base color for outline
	var outline_color = colors["base"] * 0.2
	outline_color.a = 0.8
	outline.default_color = outline_color
	outline.closed = true
	# Only use every 4th point for cleaner look (still smooth due to many segments)
	for i in range(0, points.size(), 4):
		outline.add_point(points[i])
	sprite.add_child(outline)

	# NO SPARKLES - clean anatomical look

	# Level-based forgiving hitbox (degrades with player level)
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = calculate_hitbox_radius()
	col.shape = shape
	add_child(col)

	input_event.connect(_on_input)
	max_hits = randi_range(3, 5)

func calculate_hitbox_radius() -> float:
	"""Calculate hitbox radius based on player level (degrades for tighter precision at higher levels)"""
	var level = CharacterStats.level

	# Forgiving at low levels, tighter at high levels
	# Level 1: 38px (very forgiving for new players)
	# Level 10: 28px (moderate)
	# Level 20: 23px (tighter)
	# Level 30: 22px (minimum - still clickable at edges)
	var base_radius = 38.0
	var min_radius = 22.0
	var level_scaling = 0.55  # How much radius reduces per level

	var radius = base_radius - (level - 1) * level_scaling
	return clamp(radius, min_radius, base_radius)

func start_heartbeat_pulse() -> void:
	"""Heartbeat pulse - thump-thump pattern like a vital organ"""
	if not sprite or not glow_sprite:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_CIRC)  # More organic curve
	tween.set_ease(Tween.EASE_IN_OUT)

	# THUMP (quick expand)
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.15)
	tween.parallel().tween_property(glow_sprite, "color:a", 1.0, 0.15)

	# Release (quick contract)
	tween.tween_property(sprite, "scale", Vector2(0.95, 0.95), 0.15)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.6, 0.15)

	# THUMP (second beat)
	tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.12)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.95, 0.12)

	# Release and rest
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)
	tween.parallel().tween_property(glow_sprite, "color:a", 0.7, 0.2)

	# Pause before next heartbeat
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.4)

func create_sparkle_particles() -> void:
	"""Subtle sparkle particles"""
	sparkle_particles = CPUParticles2D.new()
	sparkle_particles.emitting = true
	sparkle_particles.amount = 6  # Reduced for less clutter
	sparkle_particles.lifetime = 1.0
	sparkle_particles.preprocess = 0.5
	sparkle_particles.local_coords = true
	
	sparkle_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	sparkle_particles.emission_sphere_radius = 28.0
	
	# Red sparkle texture
	var img = Image.create(7, 7, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for x in range(2, 5):
		for y in range(2, 5):
			img.set_pixel(x, y, Color(2.0, 0.3, 0.3, 1.0))
	var tex = ImageTexture.create_from_image(img)
	sparkle_particles.texture = tex

	sparkle_particles.direction = Vector2(0, -1)
	sparkle_particles.spread = 180.0
	sparkle_particles.initial_velocity_min = 12.0
	sparkle_particles.initial_velocity_max = 25.0
	sparkle_particles.gravity = Vector2(0, -12)

	sparkle_particles.scale_amount_min = 2.0
	sparkle_particles.scale_amount_max = 4.0

	# Red sparkles
	sparkle_particles.color = Color(2.0, 0.3, 0.3, 1.0)
	
	# Twinkle fade
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 0))
	gradient.add_point(0.2, Color(1, 1, 1, 1))
	gradient.add_point(0.8, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	sparkle_particles.color_ramp = gradient
	
	add_child(sparkle_particles)

func add_crack(progress: float) -> void:
	"""Add cracks that get denser as damage increases"""
	if not sprite:
		return

	var colors = theme_colors[color_theme]
	var crack_color = colors["base"] * 0.2  # Darker cracks
	crack_color.a = 0.8

	# Number of cracks increases with damage (1-3 cracks per hit)
	var num_cracks = int(progress * 3) + 1

	for i in range(num_cracks):
		var crack = Line2D.new()
		crack.width = randf_range(0.8, 1.5)
		crack.default_color = crack_color
		crack.z_index = 2

		# Random crack from center outward
		var start_angle = randf_range(0, TAU)
		var start_dist = randf_range(0, 6)
		var end_dist = randf_range(12, 18)

		var start_point = Vector2(cos(start_angle), sin(start_angle)) * start_dist
		var end_point = Vector2(cos(start_angle), sin(start_angle)) * end_dist

		# Add slight randomness to make it look more natural
		var mid_point = (start_point + end_point) / 2.0
		mid_point += Vector2(randf_range(-3, 3), randf_range(-3, 3))

		crack.add_point(start_point)
		crack.add_point(mid_point)
		crack.add_point(end_point)

		sprite.add_child(crack)

func start_damage_pulse(progress: float) -> void:
	"""Pulsing glow that gets stronger and grows larger with damage"""
	if not glow_sprite:
		return

	var colors = theme_colors[color_theme]

	# Pulse intensity increases with damage
	var base_alpha = 0.3 + (progress * 0.5)  # 0.3 to 0.8
	var pulse_alpha = base_alpha + 0.2  # Pulse peak

	# Glow size grows with damage
	var base_scale = 1.0 + (progress * 0.15)  # 1.0 to 1.15
	var pulse_scale = base_scale + 0.1  # 1.1 to 1.25

	# Create pulsing animation
	var pulse_tween = create_tween()
	pulse_tween.set_loops(3)  # Pulse a few times
	pulse_tween.set_trans(Tween.TRANS_SINE)
	pulse_tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse glow alpha
	var glow_bright = colors["glow"]
	glow_bright.a = pulse_alpha
	var glow_dim = colors["glow"]
	glow_dim.a = base_alpha

	pulse_tween.tween_property(glow_sprite, "color", glow_bright, 0.3)
	pulse_tween.tween_property(glow_sprite, "color", glow_dim, 0.3)

	# Pulse glow scale in parallel
	pulse_tween.parallel().tween_property(glow_sprite, "scale", Vector2(pulse_scale, pulse_scale), 0.3)
	pulse_tween.tween_property(glow_sprite, "scale", Vector2(base_scale, base_scale), 0.3)

func get_damage_dealt() -> int:
	"""Returns total damage dealt to this weakpoint (for server validation)"""
	return total_damage_dealt

func set_damage_per_hit(damage: int) -> void:
	"""Set the damage value per hit (called by crit_window_manager)"""
	damage_per_hit = damage

func _on_input(_vp: Node, event: InputEvent, _idx: int) -> void:
	if is_destroyed:
		return

	# Don't allow hits if parent enemy is dying or a corpse
	var parent = get_parent()
	if parent and parent.has_method("get"):
		if parent.get("is_dying") or parent.get("is_corpse"):
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("[Weakpoint] _on_input received click! theme=%s, parent=%s" % [color_theme, parent.name if parent else "null"])
		# CLIENT-PREDICTED: All weakpoint interaction is local for instant feedback
		# Server validates total damage at crit window end
		hit()

func hit() -> void:
	if is_destroyed:
		return

	# Don't allow hits if parent enemy is dying or a corpse
	var parent = get_parent()
	if parent and parent.has_method("get"):
		if parent.get("is_dying") or parent.get("is_corpse"):
			return

	current_hits += 1

	# Track damage dealt for server validation at window end
	if damage_per_hit > 0:
		total_damage_dealt += damage_per_hit

	weakpoint_hit.emit(self)

	# PvP: Send damage to the owner player when clicking PvP weakpoints
	if color_theme == "pvp":
		print("[PvP Weakpoint] hit() called, calling _apply_pvp_weakpoint_damage()")
		_apply_pvp_weakpoint_damage()

	# 🔊 Play satisfying bone-crack sound (randomized with pitch variation)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_weakpoint_sound(global_position, -8.0)
		# Layer skeleton hurt sound for extra impact
		sound_manager.play_skeleton_hurt_sound(global_position, -14.0)

	# 🎮 Combat juice - hitstop + screen shake on every weakpoint hit
	var combat_juice = get_node_or_null("/root/CombatJuice")
	if combat_juice:
		combat_juice.on_weakpoint()

	# 🩸 IMPACT feedback - shake with progressive brightening
	if sprite:
		var colors = theme_colors[color_theme]
		var progress = float(current_hits) / float(max_hits)

		# ✨ PROGRESSIVE BRIGHTENING - get brighter with each hit
		# Progress from 60% brightness to 100% brightness
		var brightness = 0.6 + (progress * 0.4)  # 0.6 to 1.0
		var target_color = colors["base"] * brightness
		target_color.a = colors["base"].a

		# Flash effect (extra bright)
		var flash_color = colors["flash"] * (1.0 + progress * 0.5)  # Get brighter each hit
		sprite.color = flash_color

		# ✨ SHAKE on hit - intensity increases with damage
		var shake_intensity = 2.0 + (progress * 3.0)  # 2-5 pixels based on damage
		var shake_tween = create_tween()
		shake_tween.set_trans(Tween.TRANS_SINE)

		# Quick shake sequence (6 shakes, ~0.12s total)
		shake_tween.tween_property(sprite, "position", Vector2(shake_intensity, 0), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(-shake_intensity, 0), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(0, shake_intensity * 0.7), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(0, -shake_intensity * 0.7), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(shake_intensity * 0.5, 0), 0.02)
		shake_tween.tween_property(sprite, "position", Vector2(0, 0), 0.02)  # Return to center

		# Color flash back to target (parallel with shake)
		var color_tween = create_tween()
		color_tween.tween_property(sprite, "color", target_color, 0.1)

		# ✨ GLOW GROWS - increases with damage (30% to 80%)
		if glow_sprite:
			var bright_glow = colors["glow"]
			bright_glow.a = 1.0
			glow_sprite.color = bright_glow
			# Target glow alpha increases with progress
			var target_glow = colors["glow"]
			target_glow.a = 0.3 + (progress * 0.5)  # 0.3 to 0.8
			color_tween.tween_property(glow_sprite, "color", target_glow, 0.1)

		# ✨ SHINE LAYERS GET BRIGHTER (start at 30-35%, grow to target)
		for i in range(shine_layers.size()):
			var shine = shine_layers[i]
			var start_alphas = [0.3, 0.35, 0.15]  # Starting alphas for each layer
			var target_alphas = [0.7, 0.9, 0.3]  # Target alphas for each shine layer
			var target_alpha = start_alphas[i] + (progress * (target_alphas[i] - start_alphas[i]))
			var shine_color = shine.color
			shine_color.a = target_alpha
			color_tween.tween_property(shine, "color", shine_color, 0.1)

		# ✨ ADD CRACKS - increasingly dense as hits increase
		add_crack(progress)

		# 💫 PULSING GLOW - grows stronger with more damage
		start_damage_pulse(progress)

	if current_hits >= max_hits:
		# CLIENT-PREDICTED: Destroy locally for instant feedback
		# Server validates total damage at crit window end
		destroy()

func spawn_hit_number() -> void:
	"""Show HIT indicator"""
	var label = Label.new()
	label.text = "CRACK!"
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(2.2, 0.5, 0.3, 1.0))  # Red-orange
	label.add_theme_color_override("font_outline_color", Color(0.15, 0.15, 0.15, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.position = Vector2(-32, -42)
	label.z_index = 500
	add_child(label)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 32, 0.55)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.08).set_delay(0.08)
	tween.tween_property(label, "modulate:a", 0.0, 0.55).set_delay(0.2)
	tween.finished.connect(func(): label.queue_free())

func spawn_impact_wave() -> void:
	"""Expanding ring effect"""
	var ring = Line2D.new()
	ring.width = 3.5
	ring.default_color = Color(2.0, 0.3, 0.3, 1.0)  # Bright red
	ring.z_index = 299
	
	var segments = 32
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = Vector2(cos(angle), sin(angle)) * 16
		ring.add_point(point)
	
	ring.global_position = global_position
	get_parent().add_child(ring)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "width", 0.5, 0.32)
	tween.tween_property(ring, "modulate:a", 0.0, 0.32)
	
	for i in range(ring.get_point_count()):
		var point = ring.get_point_position(i)
		tween.tween_method(
			func(scale_val): ring.set_point_position(i, point * scale_val),
			1.0, 3.2, 0.32
		)
	
	tween.finished.connect(func(): ring.queue_free())

func destroy() -> void:
	if is_destroyed:
		return

	is_destroyed = true

	# Immediately disable interaction to prevent further clicks
	input_pickable = false
	monitoring = false
	monitorable = false

	if sparkle_particles:
		sparkle_particles.emitting = false

	weakpoint_destroyed.emit(self)
	weakpoint_destroyed_local.emit(self)  # For crit window client-side tracking

	# 💥 GEM SHAKE FIRST (building tension)
	if sprite:
		var shake_tween = create_tween()
		shake_tween.set_loops(4)  # Half as long (was 8)
		shake_tween.tween_property(sprite, "position", Vector2(3, 0), 0.025)
		shake_tween.tween_property(sprite, "position", Vector2(-3, 0), 0.025)
		shake_tween.tween_property(sprite, "position", Vector2(0, 0), 0.025)
		await shake_tween.finished

		# Brief pause before explosion
		await get_tree().create_timer(0.05).timeout

	# 💥 Sound + shake + particles ALL AT ONCE
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_weakpoint_destroyed_sound(global_position, -6.0)

	var combat_juice = get_node_or_null("/root/CombatJuice")
	if combat_juice:
		combat_juice.on_kill()

	spawn_destruction_particles()
	spawn_destruction_wave()

	# 💥 EXPLODE (dramatic release)
	if sprite:

		var explode_tween = create_tween()
		explode_tween.set_parallel(true)
		explode_tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.16)
		explode_tween.tween_property(sprite, "modulate:a", 0.0, 0.16)
		await explode_tween.finished

	queue_free()

func spawn_destruction_wave() -> void:
	"""💥 EXPLOSIVE SHOCKWAVES (blood or bone)"""
	# Get world container to avoid parent scaling issues
	var world = get_tree().current_scene
	if not world:
		return

	var colors = theme_colors[color_theme]

	for i in range(2):  # Just 2 waves
		# Check if weakpoint still exists before continuing
		if not is_instance_valid(self):
			return

		await get_tree().create_timer(i * 0.05).timeout

		var ring = Line2D.new()
		ring.width = 3.0 - (i * 0.5)  # Thin waves
		ring.default_color = colors["wave"]
		ring.z_index = 400  # High z-index to render above enemy/dummy sprites

		var segments = 32  # Simpler circles
		for j in range(segments + 1):
			var angle = (j * TAU) / segments
			var point = Vector2(cos(angle), sin(angle)) * 12  # Start small
			ring.add_point(point)

		ring.global_position = global_position
		world.add_child(ring)

		# ✨ FIX: Create a SceneTreeTween on the world instead of the weakpoint
		# This ensures the tween survives even if the weakpoint is destroyed
		var tween = world.create_tween()
		tween.set_parallel(true)
		tween.tween_property(ring, "width", 0.5, 0.3)
		tween.tween_property(ring, "modulate:a", 0.0, 0.3)

		for j in range(ring.get_point_count()):
			var point = ring.get_point_position(j)
			tween.tween_method(
				func(scale_val):
					if is_instance_valid(ring):
						ring.set_point_position(j, point * scale_val),
				1.0, 2.2, 0.3  # Compact expansion (2.2x)
			)

		# ✨ FIX: Add failsafe cleanup in case tween fails
		tween.finished.connect(func():
			if is_instance_valid(ring):
				ring.queue_free()
		)

		# Failsafe timer - ensure ring is ALWAYS cleaned up after max duration
		var cleanup_timer = world.get_tree().create_timer(0.5)
		cleanup_timer.timeout.connect(func():
			if is_instance_valid(ring):
				ring.queue_free()
		)

func spawn_crack_particles() -> void:
	"""Subtle crack particles"""
	var particles = CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8  # Reduced for less clutter
	particles.lifetime = 0.4
	particles.local_coords = false
	particles.global_position = global_position
	
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 8.0
	
	var img = Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(2.0, 0.3, 0.3, 1.0))
	var tex = ImageTexture.create_from_image(img)
	particles.texture = tex

	particles.direction = Vector2(0, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 55.0
	particles.initial_velocity_max = 100.0
	particles.gravity = Vector2(0, 85)

	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0

	particles.color = Color(2.0, 0.3, 0.3, 1.0)
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 1, 1))
	gradient.add_point(1.0, Color(1, 1, 1, 0))
	particles.color_ramp = gradient
	
	get_parent().add_child(particles)
	particles.emitting = true
	
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(particles):
		particles.queue_free()

func spawn_destruction_particles() -> void:
	"""💥 DRAMATIC EXPLOSION when weakpoint destroyed (blood or bone fragments)"""
	# Get world container to avoid parent scaling issues
	var world = get_tree().current_scene
	if not world:
		return

	var colors = theme_colors[color_theme]

	# 🩸 SPRAY/FRAGMENTS - dramatic explosive burst
	var blood_spray = CPUParticles2D.new()
	blood_spray.emitting = false
	blood_spray.one_shot = true
	blood_spray.explosiveness = 1.0  # All at once
	blood_spray.amount = 50  # Reduced 30%
	blood_spray.randomness = 0.4  # More chaos for mist effect
	blood_spray.lifetime = 0.4  # Quick dissipation like mist
	blood_spray.local_coords = false
	blood_spray.global_position = global_position

	blood_spray.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT  # Spawn from exact center

	# ✨ TINY SHARP PARTICLES - single pixel dots
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var particle_color = colors["particle_base"]
	img.fill(particle_color)

	var tex = ImageTexture.create_from_image(img)
	blood_spray.texture = tex

	blood_spray.direction = Vector2(0, 0)
	blood_spray.spread = 180.0
	# ✨ VIOLENT BURST - explode out then stop
	blood_spray.initial_velocity_min = 150.0
	blood_spray.initial_velocity_max = 220.0
	blood_spray.gravity = Vector2(0, 0)
	blood_spray.damping_min = 8.0  # Heavy damping - stops quickly
	blood_spray.damping_max = 12.0

	blood_spray.scale_amount_min = 1.0  # Bigger
	blood_spray.scale_amount_max = 1.8

	# Scale variation - stay visible then fade at the end
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 1.0))  # Start full size
	scale_curve.add_point(Vector2(0.7, 0.8))  # Stay mostly visible
	scale_curve.add_point(Vector2(1, 0.0))  # Shrink to nothing at end
	blood_spray.scale_amount_curve = scale_curve

	# Color variation based on theme
	blood_spray.color = colors["particle_base"]

	# Mist-like fade - bright flash then quick dissipation
	var spray_gradient = Gradient.new()
	var bright_color = colors["particle_base"]
	var mid_color = colors["particle_dark"]
	mid_color.a = 0.6  # Start fading earlier
	var fade_color = colors["particle_dark"] * 0.3
	fade_color.a = 0  # Fully transparent
	spray_gradient.add_point(0.0, bright_color)  # Bright burst
	spray_gradient.add_point(0.15, mid_color)  # Quick fade
	spray_gradient.add_point(1.0, fade_color)  # Dissipate into nothing
	blood_spray.color_ramp = spray_gradient

	# HIGH Z-INDEX to render in front of enemy/dummy sprites
	blood_spray.z_index = 400

	world.add_child(blood_spray)
	blood_spray.emitting = true

	# 💀 DARK BLOOD CHUNKS - slower, heavier pieces
	var chunks = CPUParticles2D.new()
	chunks.emitting = false
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 7  # Reduced 30%
	chunks.lifetime = 0.5
	chunks.local_coords = false
	chunks.global_position = global_position

	chunks.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT  # Spawn from exact center

	# Create tiny chunk texture
	var chunk_img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var chunk_color = colors["particle_dark"]
	chunk_img.fill(chunk_color)
	var chunk_tex = ImageTexture.create_from_image(chunk_img)
	chunks.texture = chunk_tex

	chunks.direction = Vector2(0, 0)
	chunks.spread = 180.0
	# ✨ VIOLENT BURST - explode out then stop
	chunks.initial_velocity_min = 100.0
	chunks.initial_velocity_max = 160.0
	chunks.gravity = Vector2(0, 0)
	chunks.damping_min = 6.0  # Heavy damping - stops quickly
	chunks.damping_max = 10.0

	chunks.scale_amount_min = 1.5  # Bigger chunks
	chunks.scale_amount_max = 2.5

	# Color gradient: darker chunks/fragments that fade
	var chunk_gradient = Gradient.new()
	var chunk_bright = colors["particle_dark"]
	var chunk_mid = colors["particle_dark"] * 0.8
	chunk_mid.a = 0.7
	var chunk_fade = colors["particle_dark"] * 0.5
	chunk_fade.a = 0
	chunk_gradient.add_point(0.0, chunk_bright)
	chunk_gradient.add_point(0.6, chunk_mid)  # Stay visible longer
	chunk_gradient.add_point(1.0, chunk_fade)
	chunks.color_ramp = chunk_gradient

	# Fast rotation for violent explosion
	chunks.angular_velocity_min = -360.0
	chunks.angular_velocity_max = 360.0

	# HIGH Z-INDEX to render in front of enemy/dummy sprites
	chunks.z_index = 400

	world.add_child(chunks)
	chunks.emitting = true

	await get_tree().create_timer(0.5).timeout  # Quick cleanup for mist effect
	if is_instance_valid(blood_spray):
		blood_spray.queue_free()
	if is_instance_valid(chunks):
		chunks.queue_free()

## Debug
func draw_debug_hitbox(debug_container: Node2D) -> void:
	pass

func draw_debug_hitbox_world(world_container: Node2D) -> void:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color.CYAN
	line.z_index = 1000

	var segments = 24
	var radius = 25 * scale.x
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = global_position + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)

	world_container.add_child(line)

# ============================================
# PVP WEAKPOINT DAMAGE
# ============================================

func _apply_pvp_weakpoint_damage() -> void:
	"""Apply damage when clicking a PvP weakpoint. Called locally by the attacker."""
	# Get the defender (the player this weakpoint is attached to)
	var defender = get_parent()
	if not defender or not defender.is_in_group("player"):
		print("[PvP Weakpoint] No valid defender parent")
		return

	# Get the local player (the attacker doing the clicking) - must find the one WE control
	var local_player: Node = null
	var my_peer_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for player in get_tree().get_nodes_in_group("player"):
		if player.get_multiplayer_authority() == my_peer_id:
			local_player = player
			break

	if not local_player:
		print("[PvP Weakpoint] Could not find local player for peer %d" % my_peer_id)
		return

	# Don't damage yourself (defender clicking their own weakpoints)
	if local_player == defender:
		print("[PvP Weakpoint] Ignoring self-click (defender can't click own weakpoints)")
		return

	# Check that we're in a duel
	if not local_player.get("is_dueling"):
		return

	# Send PvP damage via the DuelManager
	var duel_manager = get_node_or_null("/root/DuelManager")
	if not duel_manager:
		return

	# Get defender's peer ID
	var defender_peer_id = -1
	if defender.get_multiplayer_authority() > 0:
		defender_peer_id = defender.get_multiplayer_authority()

	if defender_peer_id < 0:
		# Try alternative methods to get peer ID
		var game_world = get_node_or_null("/root/GameWorld")
		if game_world and game_world.has_method("get_peer_id_for_player"):
			defender_peer_id = game_world.get_peer_id_for_player(defender)

	if defender_peer_id < 0:
		print("[PvP Weakpoint] Could not find defender peer ID")
		return

	# Send damage through DuelManager
	var multiplayer_api = get_tree().get_multiplayer()
	if multiplayer_api.is_server():
		duel_manager.request_pvp_damage(defender_peer_id, damage_per_hit)
	else:
		duel_manager.request_pvp_damage.rpc_id(1, defender_peer_id, damage_per_hit)

	print("[PvP Weakpoint] Hit! Sent %d damage to player %d" % [damage_per_hit, defender_peer_id])
