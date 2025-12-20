extends Control
class_name AllegianceShield

## Allegiance Shield - Shadowbane-style faction indicator
## Floats above player head, displays faction emblem with tier-based styling

# Shield dimensions
const SHIELD_WIDTH: float = 18.0
const SHIELD_HEIGHT: float = 22.0
const BORDER_WIDTH: float = 0.5
const ICON_SIZE: float = 11.0

# Positioning
const OFFSET_Y: float = 50.0  # Distance above player center
const OFFSET_X: float = -40.0  # Offset to the left of player

var current_tier: String = "initiate"
var player_ref: Node = null
var ready_to_position: bool = false

# Visual components
var shield_bg: Control = null
var shield_icon: TextureRect = null
var glow_effect: Control = null
var particle_effect: CPUParticles2D = null

# Colors (cached from tier)
var border_color: Color = Color(0.6, 0.5, 0.3)  # Default bronze-ish border
var glow_color: Color = Color.TRANSPARENT
var fill_color: Color = Color(0.15, 0.12, 0.1, 0.95)  # Dark brown fill

# Glow animation
var glow_tween: Tween = null
var glow_alpha: float = 0.3
var glow_pulse_enabled: bool = false

func _ready() -> void:
	# Use world-space positioning (doesn't rotate with player)
	top_level = true
	z_index = 99  # Just below health bar

	# Set size
	custom_minimum_size = Vector2(SHIELD_WIDTH, SHIELD_HEIGHT)
	size = Vector2(SHIELD_WIDTH, SHIELD_HEIGHT)

	# Create shield visuals
	_create_shield()

	# Hide until positioned
	visible = false

	# Wait for parent initialization
	await get_tree().process_frame
	player_ref = get_parent()

	if player_ref and is_instance_valid(player_ref):
		while not player_ref.is_inside_tree() or player_ref.global_position == Vector2.ZERO:
			await get_tree().process_frame

	ready_to_position = true

func _create_shield() -> void:
	# Glow layer (behind shield) - animated glow
	glow_effect = Control.new()
	glow_effect.name = "GlowEffect"
	glow_effect.custom_minimum_size = Vector2(SHIELD_WIDTH + 6, SHIELD_HEIGHT + 6)
	glow_effect.size = Vector2(SHIELD_WIDTH + 6, SHIELD_HEIGHT + 6)
	glow_effect.position = Vector2(-3, -3)
	glow_effect.draw.connect(_draw_glow)
	glow_effect.visible = true
	add_child(glow_effect)

	# Shield background with custom draw
	shield_bg = Control.new()
	shield_bg.name = "ShieldBG"
	shield_bg.custom_minimum_size = Vector2(SHIELD_WIDTH, SHIELD_HEIGHT)
	shield_bg.size = Vector2(SHIELD_WIDTH, SHIELD_HEIGHT)
	shield_bg.draw.connect(_draw_shield)
	add_child(shield_bg)

	# Ashbane tree icon - centered in shield
	shield_icon = TextureRect.new()
	shield_icon.name = "ShieldIcon"
	shield_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	shield_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	# Center icon, slightly up since shield tapers at bottom
	shield_icon.position = Vector2((SHIELD_WIDTH - ICON_SIZE) / 2, (SHIELD_HEIGHT - ICON_SIZE) / 2 - 2)
	shield_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	shield_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load Ashbane tree texture
	var tree_tex = load("res://assets/ui/logo/ashbane_tree_64.png")
	if tree_tex:
		shield_icon.texture = tree_tex

	add_child(shield_icon)

func _draw_shield() -> void:
	if not shield_bg:
		return

	var points = _get_shield_points(Vector2.ZERO, SHIELD_WIDTH, SHIELD_HEIGHT)

	# Draw fill
	shield_bg.draw_colored_polygon(points, fill_color)

	# Draw border (tier-colored)
	var border_points = points.duplicate()
	border_points.append(points[0])  # Close the shape
	shield_bg.draw_polyline(border_points, border_color, BORDER_WIDTH, true)

func _draw_glow() -> void:
	if not glow_effect:
		return

	# Only draw glow if we have a glow color with alpha
	if glow_color.a < 0.1:
		return

	# Draw multiple glow layers for soft effect - tight and bright
	for i in range(3):
		var expansion = (3 - i) * 0.8  # Tighter glow layers
		var alpha = glow_alpha * (0.6 - i * 0.12)  # Brighter glow
		var col = Color(glow_color.r, glow_color.g, glow_color.b, alpha)

		var glow_width = SHIELD_WIDTH + expansion * 2
		var glow_height = SHIELD_HEIGHT + expansion * 2
		var offset = Vector2(3 - expansion, 3 - expansion)

		var points = _get_shield_points(offset, glow_width, glow_height)
		glow_effect.draw_colored_polygon(points, col)

func _get_shield_points(offset: Vector2, width: float, height: float) -> PackedVector2Array:
	# Shadowbane-style heater shield: flat top, angled sides, pointed bottom
	var points = PackedVector2Array()

	var left = offset.x
	var right = offset.x + width
	var top = offset.y
	var bottom = offset.y + height
	var cx = offset.x + width / 2

	# Top edge (flat)
	points.append(Vector2(left + 2, top))      # Top-left corner (slightly rounded)
	points.append(Vector2(right - 2, top))     # Top-right corner

	# Right side going down
	points.append(Vector2(right, top + 2))     # Corner
	points.append(Vector2(right, top + height * 0.45))  # Side

	# Bottom point
	points.append(Vector2(cx, bottom))

	# Left side going up
	points.append(Vector2(left, top + height * 0.45))
	points.append(Vector2(left, top + 2))      # Corner

	return points

func _process(_delta: float) -> void:
	if not ready_to_position:
		return

	if player_ref and is_instance_valid(player_ref):
		var parent_scale = player_ref.scale.x
		var offset_y = OFFSET_Y * parent_scale
		var offset_x = OFFSET_X * parent_scale

		# Position shield to the left of player, above head
		global_position = player_ref.global_position + Vector2(offset_x - size.x / 2, -offset_y)
		scale = Vector2(parent_scale, parent_scale)
		rotation = 0.0

		if not visible:
			visible = true

func set_tier(tier: String) -> void:
	current_tier = tier.to_lower()

	# Get colors from AshbaneCosmetics
	if AshbaneCosmetics:
		var badge_col = AshbaneCosmetics.get_tier_badge_color(current_tier)
		glow_color = AshbaneCosmetics.get_tier_glow_color(current_tier)

		# Border color - use badge color but make it more prominent
		border_color = badge_col

	# Set tier-specific visuals
	match current_tier:
		"initiate":
			border_color = Color(0.5, 0.5, 0.5)  # Gray
			glow_color = Color.TRANSPARENT
			glow_pulse_enabled = false
		"bronze":
			border_color = Color(0.8, 0.5, 0.2)  # Bronze
			glow_pulse_enabled = false
		"silver":
			border_color = Color(0.75, 0.75, 0.8)  # Silver
			glow_pulse_enabled = false
		"gold":
			border_color = Color(1.0, 0.84, 0.0)  # Gold
			glow_pulse_enabled = true
		"platinum":
			border_color = Color(0.9, 0.9, 0.95)  # Platinum white
			glow_pulse_enabled = true
		"diamond":
			border_color = Color(0.7, 0.95, 1.0)  # Diamond cyan
			glow_pulse_enabled = true
		"legendary":
			border_color = Color(1.0, 0.5, 0.0)  # Orange
			glow_pulse_enabled = true
		"mythic":
			border_color = Color(1.0, 0.3, 1.0)  # Magenta
			glow_pulse_enabled = true

	# Update shield visuals
	_update_tier_visuals()

func _update_tier_visuals() -> void:
	# Redraw shield with new colors
	if shield_bg:
		shield_bg.queue_redraw()

	# Update glow
	if glow_effect:
		glow_effect.visible = glow_color.a > 0.1
		glow_effect.queue_redraw()

		# Start/stop glow pulse animation
		if glow_pulse_enabled and glow_color.a > 0.1:
			_start_glow_pulse()
		else:
			_stop_glow_pulse()

	# Handle particle effects for high tiers
	_update_particle_effects()

func _start_glow_pulse() -> void:
	if glow_tween and glow_tween.is_valid():
		return  # Already pulsing

	_pulse_glow()

func _pulse_glow() -> void:
	if not glow_pulse_enabled or not is_instance_valid(self):
		return

	glow_tween = create_tween()
	glow_tween.set_loops()
	glow_tween.tween_method(_set_glow_alpha, 0.2, 0.5, 0.8)
	glow_tween.tween_method(_set_glow_alpha, 0.5, 0.2, 0.8)

func _set_glow_alpha(alpha: float) -> void:
	glow_alpha = alpha
	if glow_effect:
		glow_effect.queue_redraw()

func _stop_glow_pulse() -> void:
	if glow_tween and glow_tween.is_valid():
		glow_tween.kill()
		glow_tween = null
	glow_alpha = 0.3

func _update_particle_effects() -> void:
	# Remove existing particles
	if particle_effect:
		particle_effect.queue_free()
		particle_effect = null

	# Add particles for legendary/mythic tiers
	match current_tier:
		"legendary":
			_add_ember_particles()
		"mythic":
			_add_mythic_particles()
		"diamond":
			_add_sparkle_particles()

func _add_ember_particles() -> void:
	particle_effect = CPUParticles2D.new()
	particle_effect.name = "EmberParticles"
	particle_effect.amount = 3
	particle_effect.lifetime = 0.8
	particle_effect.z_index = 1

	particle_effect.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particle_effect.emission_rect_extents = Vector2(SHIELD_WIDTH / 2 - 2, SHIELD_HEIGHT / 2 - 2)

	particle_effect.direction = Vector2(0, -1)
	particle_effect.spread = 30.0
	particle_effect.initial_velocity_min = 6.0
	particle_effect.initial_velocity_max = 12.0
	particle_effect.gravity = Vector2(0, -3)

	particle_effect.scale_amount_min = 0.3
	particle_effect.scale_amount_max = 0.6
	particle_effect.color = Color(1.0, 0.5, 0.1, 0.8)

	particle_effect.position = Vector2(SHIELD_WIDTH / 2, SHIELD_HEIGHT / 2)
	add_child(particle_effect)

func _add_mythic_particles() -> void:
	particle_effect = CPUParticles2D.new()
	particle_effect.name = "MythicParticles"
	particle_effect.amount = 4
	particle_effect.lifetime = 1.2
	particle_effect.z_index = 1

	particle_effect.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	particle_effect.emission_sphere_radius = SHIELD_WIDTH / 2

	particle_effect.direction = Vector2(0, 0)
	particle_effect.spread = 180.0
	particle_effect.initial_velocity_min = 2.0
	particle_effect.initial_velocity_max = 5.0
	particle_effect.gravity = Vector2.ZERO

	particle_effect.scale_amount_min = 0.2
	particle_effect.scale_amount_max = 0.5
	particle_effect.color = Color(0.8, 0.3, 1.0, 0.7)

	particle_effect.position = Vector2(SHIELD_WIDTH / 2, SHIELD_HEIGHT / 2)
	add_child(particle_effect)

func _add_sparkle_particles() -> void:
	particle_effect = CPUParticles2D.new()
	particle_effect.name = "SparkleParticles"
	particle_effect.amount = 2
	particle_effect.lifetime = 0.6
	particle_effect.z_index = 1

	particle_effect.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particle_effect.emission_rect_extents = Vector2(SHIELD_WIDTH / 2, SHIELD_HEIGHT / 2)

	particle_effect.direction = Vector2(0, -1)
	particle_effect.spread = 45.0
	particle_effect.initial_velocity_min = 4.0
	particle_effect.initial_velocity_max = 8.0
	particle_effect.gravity = Vector2.ZERO

	particle_effect.scale_amount_min = 0.15
	particle_effect.scale_amount_max = 0.35
	particle_effect.color = Color(0.7, 0.95, 1.0, 0.9)

	particle_effect.position = Vector2(SHIELD_WIDTH / 2, SHIELD_HEIGHT / 2)
	add_child(particle_effect)
