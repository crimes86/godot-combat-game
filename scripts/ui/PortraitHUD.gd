extends CanvasLayer
## WoW-style portrait HUD with color-coded health bar
## Classic layout: Name above, portrait left, HP bar right, level badge on portrait corner

# Health color thresholds
const HP_HEALTHY := Color(0.3, 0.85, 0.3)    # Green >60%
const HP_GOOD := Color(0.7, 0.85, 0.2)       # Yellow 40-60%
const HP_WARNING := Color(0.9, 0.6, 0.1)     # Orange 25-40%
const HP_CRITICAL := Color(0.9, 0.2, 0.2)    # Red <25%

# Layout constants (scaled 125%)
const SHIELD_WIDTH := 54.0   # Shield portrait dimensions (3x AllegianceShield)
const SHIELD_HEIGHT := 72.0
const SHIELD_BORDER := 2.5   # Slightly thicker border for visibility
const ICON_SIZE := 40.0      # Tree icon size inside shield
const HEALTH_BAR_WIDTH := 125.0
const HEALTH_BAR_HEIGHT := 18.0  # Slightly thinner for refinement
const BORDER_WIDTH := 2.5
const MARGIN := 15.0
const LEVEL_BADGE_SIZE := 28.0

# UI elements
var _container: Control
var _portrait_frame: Control
var _portrait_icon: TextureRect  # Allegiance icon (Ashbane tree)
var _health_bar_bg: ColorRect
var _health_bar_fill: ColorRect
var _health_bar_glow: ColorRect
var _health_text: Label  # HP percentage text
var _name_label: Label
var _level_badge: Control
var _level_label: Label
var _allegiance: String = "ashbane"  # Current allegiance (future: could be other factions)

# State
var _current_health: float = 100.0
var _max_health: float = 100.0
var _health_tween: Tween
var _is_critical: bool = false
var _pulse_tween: Tween
var _tier_color: Color = Color(0.35, 0.38, 0.42)  # Default steel gray


func _ready() -> void:
	layer = 105  # Above game elements, below character sheet
	_build_ui()
	_connect_signals()
	_update_from_character_stats()

func _build_ui() -> void:
	# Main container anchored to top-left
	# Layout: Name on top, Shield portrait left with level badge, HP bar right
	_container = Control.new()
	_container.name = "PortraitContainer"
	_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_container.position = Vector2(MARGIN, MARGIN)
	_container.size = Vector2(SHIELD_WIDTH + HEALTH_BAR_WIDTH + 20, SHIELD_HEIGHT + 30)
	add_child(_container)

	# Name label (above everything)
	_create_name_label()

	# Portrait frame (shield shape with tier-colored border)
	_create_portrait_frame()

	# Level badge (overlaps portrait bottom corner)
	_create_level_badge()

	# Health bar (right of portrait)
	_create_health_bar()

func _create_name_label() -> void:
	# Name positioned right above the health bar (not above shield)
	var bar_x = SHIELD_WIDTH + 10
	var bar_y = (SHIELD_HEIGHT - HEALTH_BAR_HEIGHT) / 2 + 8  # Align with upper portion of shield

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.position = Vector2(bar_x, bar_y - 20)  # Just above health bar
	_name_label.size = Vector2(HEALTH_BAR_WIDTH, 20)
	_name_label.text = "Player"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_name_label)

func _create_portrait_frame() -> void:
	# Shield starts at top (name is now above health bar, not shield)
	_portrait_frame = Control.new()
	_portrait_frame.name = "PortraitFrame"
	_portrait_frame.position = Vector2(0, 0)
	_portrait_frame.size = Vector2(SHIELD_WIDTH, SHIELD_HEIGHT)
	_portrait_frame.draw.connect(_draw_shield_frame)
	_container.add_child(_portrait_frame)

	# Allegiance icon (Ashbane tree - centered in shield)
	_portrait_icon = TextureRect.new()
	_portrait_icon.name = "AllegianceIcon"
	_portrait_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_portrait_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	# Center icon in shield (offset up slightly like AllegianceShield)
	_portrait_icon.position = Vector2((SHIELD_WIDTH - ICON_SIZE) / 2, (SHIELD_HEIGHT - ICON_SIZE) / 2 - 4)
	_portrait_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load Ashbane tree texture
	var tree_tex = load("res://assets/ui/logo/ashbane_tree_64.png")
	if tree_tex:
		_portrait_icon.texture = tree_tex
		_portrait_icon.modulate = Color(0.85, 0.9, 0.85, 1.0)  # Light gray-green
	_portrait_frame.add_child(_portrait_icon)

func _draw_shield_frame() -> void:
	if not _portrait_frame:
		return

	var points = _get_shield_points(Vector2.ZERO, SHIELD_WIDTH, SHIELD_HEIGHT)

	# Draw dark fill
	_portrait_frame.draw_colored_polygon(points, Color(0.06, 0.06, 0.08, 0.95))

	# Draw tier-colored border
	var border_points = points.duplicate()
	border_points.append(points[0])  # Close the shape
	_portrait_frame.draw_polyline(border_points, _tier_color, SHIELD_BORDER, true)

func _get_shield_points(offset: Vector2, width: float, height: float) -> PackedVector2Array:
	# Shadowbane-style heater shield: smooth rounded top, straight sides, pointed bottom
	var points = PackedVector2Array()

	var left = offset.x
	var right = offset.x + width
	var top = offset.y
	var bottom = offset.y + height
	var cx = offset.x + width / 2

	# Use proportional values for smooth scaling
	var curve_inset = width * 0.12  # How far in the curve starts
	var top_curve_height = height * 0.08  # Height of the top curve area

	# Rounded top - smoother curves using proportional offsets
	points.append(Vector2(left, top + height * 0.12))                    # Left side start
	points.append(Vector2(left + curve_inset * 0.3, top + height * 0.06))  # Gentle curve up
	points.append(Vector2(left + curve_inset * 0.7, top + top_curve_height * 0.5))  # Top-left curve
	points.append(Vector2(left + curve_inset * 1.2, top + top_curve_height * 0.15)) # Near top-left
	points.append(Vector2(cx, top))                                      # Top center (highest point)
	points.append(Vector2(right - curve_inset * 1.2, top + top_curve_height * 0.15)) # Near top-right
	points.append(Vector2(right - curve_inset * 0.7, top + top_curve_height * 0.5))  # Top-right curve
	points.append(Vector2(right - curve_inset * 0.3, top + height * 0.06)) # Gentle curve down
	points.append(Vector2(right, top + height * 0.12))                   # Right side start

	# Right side going down - straight then angles to point
	points.append(Vector2(right, top + height * 0.55))                   # Straight down
	points.append(Vector2(right - width * 0.08, top + height * 0.72))    # Start angling in

	# Bottom point
	points.append(Vector2(cx, bottom))

	# Left side going up - mirror of right
	points.append(Vector2(left + width * 0.08, top + height * 0.72))     # Angle out
	points.append(Vector2(left, top + height * 0.55))                    # Straight up

	return points

func _create_level_badge() -> void:
	# Circular level badge overlapping bottom of shield (near the point)
	var badge_x = (SHIELD_WIDTH - LEVEL_BADGE_SIZE) / 2  # Centered horizontally
	var badge_y = SHIELD_HEIGHT - LEVEL_BADGE_SIZE + 6  # Move down ~10px from before

	_level_badge = Control.new()
	_level_badge.name = "LevelBadge"
	_level_badge.position = Vector2(badge_x, badge_y)
	_level_badge.size = Vector2(LEVEL_BADGE_SIZE, LEVEL_BADGE_SIZE)
	_level_badge.z_index = 1  # Above portrait
	_container.add_child(_level_badge)

	# Circular background
	var badge_bg = _create_circle(LEVEL_BADGE_SIZE / 2, Color(0.12, 0.12, 0.15, 0.95))
	badge_bg.position = Vector2(LEVEL_BADGE_SIZE / 2, LEVEL_BADGE_SIZE / 2)
	_level_badge.add_child(badge_bg)

	# Border ring (gold/tier colored)
	var badge_ring = _create_ring(LEVEL_BADGE_SIZE / 2, 2.5, Color(0.75, 0.65, 0.35))
	badge_ring.position = Vector2(LEVEL_BADGE_SIZE / 2, LEVEL_BADGE_SIZE / 2)
	_level_badge.add_child(badge_ring)

	# Level text
	_level_label = Label.new()
	_level_label.position = Vector2(0, 0)
	_level_label.size = Vector2(LEVEL_BADGE_SIZE, LEVEL_BADGE_SIZE)
	_level_label.text = "1"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	_level_badge.add_child(_level_label)

func _create_health_bar() -> void:
	var bar_x = SHIELD_WIDTH + 10
	var bar_y = (SHIELD_HEIGHT - HEALTH_BAR_HEIGHT) / 2 + 8  # Align with upper portion of shield

	# Glow layer (subtle)
	_health_bar_glow = ColorRect.new()
	_health_bar_glow.name = "HealthGlow"
	_health_bar_glow.position = Vector2(bar_x - 2, bar_y - 2)
	_health_bar_glow.size = Vector2(HEALTH_BAR_WIDTH + 4, HEALTH_BAR_HEIGHT + 4)
	_health_bar_glow.color = Color(HP_HEALTHY.r, HP_HEALTHY.g, HP_HEALTHY.b, 0.25)
	_container.add_child(_health_bar_glow)

	# Background (dark)
	_health_bar_bg = ColorRect.new()
	_health_bar_bg.name = "HealthBarBG"
	_health_bar_bg.position = Vector2(bar_x, bar_y)
	_health_bar_bg.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_bg.color = Color(0.04, 0.04, 0.06, 0.9)
	_container.add_child(_health_bar_bg)

	# Fill (colored based on health %)
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.name = "HealthBarFill"
	_health_bar_fill.position = Vector2(bar_x + 1, bar_y + 1)
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH - 2, HEALTH_BAR_HEIGHT - 2)
	_health_bar_fill.color = HP_HEALTHY
	_container.add_child(_health_bar_fill)

	# HP percentage text (right-aligned on bar)
	_health_text = Label.new()
	_health_text.name = "HealthText"
	_health_text.position = Vector2(bar_x, bar_y)
	_health_text.size = Vector2(HEALTH_BAR_WIDTH - 6, HEALTH_BAR_HEIGHT)
	_health_text.text = "100%"
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_text.add_theme_font_size_override("font_size", 12)
	_health_text.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_health_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_health_text.add_theme_constant_override("shadow_offset_x", 1)
	_health_text.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_health_text)

func _create_circle(radius: float, color: Color) -> Polygon2D:
	var circle = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 32

	for i in range(segments):
		var angle = (TAU / segments) * i
		points.append(Vector2(cos(angle), sin(angle)) * radius)

	circle.polygon = points
	circle.color = color
	return circle

func _create_ring(radius: float, thickness: float, color: Color) -> Node2D:
	var ring = Node2D.new()

	# Draw ring as multiple segments
	var segments = 32
	for i in range(segments):
		var segment = Polygon2D.new()
		var angle1 = (TAU / segments) * i
		var angle2 = (TAU / segments) * (i + 1)

		var inner1 = Vector2(cos(angle1), sin(angle1)) * (radius - thickness)
		var outer1 = Vector2(cos(angle1), sin(angle1)) * radius
		var inner2 = Vector2(cos(angle2), sin(angle2)) * (radius - thickness)
		var outer2 = Vector2(cos(angle2), sin(angle2)) * radius

		segment.polygon = PackedVector2Array([inner1, outer1, outer2, inner2])
		segment.color = color
		ring.add_child(segment)

	return ring

func set_allegiance(allegiance_name: String) -> void:
	"""Set the player's allegiance - updates portrait icon"""
	_allegiance = allegiance_name.to_lower()

	if not _portrait_icon:
		return

	# Load appropriate allegiance icon
	var icon_path: String
	match _allegiance:
		"ashbane":
			icon_path = "res://assets/ui/logo/ashbane_tree_64.png"
		_:
			# Default to Ashbane
			icon_path = "res://assets/ui/logo/ashbane_tree_64.png"

	var tex = load(icon_path)
	if tex:
		_portrait_icon.texture = tex

func _connect_signals() -> void:
	# Connect to CharacterStats for level updates
	if has_node("/root/CharacterStats"):
		var stats = get_node("/root/CharacterStats")
		if stats.has_signal("level_up"):
			stats.level_up.connect(_on_level_up)

	# Connect to AshbaneCosmetics for tier color
	if has_node("/root/AshbaneCosmetics"):
		var ashbane_cosmetics = get_node("/root/AshbaneCosmetics")
		if ashbane_cosmetics.has_method("get_tier_color"):
			_tier_color = ashbane_cosmetics.get_tier_color()
			_update_frame_color()


func _update_from_character_stats() -> void:
	# Get initial values from CharacterStats
	if has_node("/root/CharacterStats"):
		var stats = get_node("/root/CharacterStats")
		if "level" in stats:
			_level_label.text = "%d" % stats.level
		if "max_health" in stats:
			_max_health = stats.get_max_health() if stats.has_method("get_max_health") else stats.max_health

	# Get player name
	if has_node("/root/NetworkManager"):
		var network = get_node("/root/NetworkManager")
		if network.has_method("get_display_name"):
			_name_label.text = network.get_display_name()
		elif "player_name" in network:
			_name_label.text = network.player_name

	# Get tier color
	if has_node("/root/AshbaneCosmetics"):
		var ashbane_cosmetics = get_node("/root/AshbaneCosmetics")
		if ashbane_cosmetics.has_method("get_tier_color"):
			_tier_color = ashbane_cosmetics.get_tier_color()
			_update_frame_color()

func update_health(current: float, maximum: float) -> void:
	"""Called by Player when health changes"""
	_current_health = current
	_max_health = maximum

	var health_percent = current / maximum if maximum > 0 else 0.0
	var target_width = (HEALTH_BAR_WIDTH - 2) * health_percent
	var target_color = _get_health_color(health_percent)

	# Update percentage text
	if _health_text:
		_health_text.text = "%d%%" % int(health_percent * 100)

	# Kill existing tween
	if _health_tween and _health_tween.is_valid():
		_health_tween.kill()

	# Animate health bar
	_health_tween = create_tween()
	_health_tween.set_parallel(true)
	_health_tween.tween_property(_health_bar_fill, "size:x", target_width, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_health_tween.tween_property(_health_bar_fill, "color", target_color, 0.3)
	_health_tween.tween_property(_health_bar_glow, "color", Color(target_color.r, target_color.g, target_color.b, 0.25), 0.3)

	# Handle critical state
	var was_critical = _is_critical
	_is_critical = health_percent < 0.25

	if _is_critical and not was_critical:
		_start_critical_pulse()
	elif not _is_critical and was_critical:
		_stop_critical_pulse()

func _get_health_color(percent: float) -> Color:
	if percent > 0.6:
		return HP_HEALTHY
	elif percent > 0.4:
		return HP_GOOD
	elif percent > 0.25:
		return HP_WARNING
	else:
		return HP_CRITICAL

func _start_critical_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_health_bar_glow, "color:a", 0.6, 0.4).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_health_bar_glow, "color:a", 0.2, 0.4).set_trans(Tween.TRANS_SINE)

func _stop_critical_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_health_bar_glow.color.a = 0.3

func _update_frame_color() -> void:
	# Redraw shield with new tier color
	if _portrait_frame:
		_portrait_frame.queue_redraw()

func _on_level_up(new_level: int) -> void:
	_level_label.text = "%d" % new_level

	# Flash effect on level up - gold pulse
	var original_color = _level_label.get_theme_color("font_color")
	_level_label.add_theme_color_override("font_color", Color(1, 1, 0.5))

	var tween = create_tween()
	tween.tween_property(_level_label, "theme_override_colors/font_color", original_color, 0.8)

func set_player_name(player_name: String) -> void:
	_name_label.text = player_name

func set_tier_color(color: Color) -> void:
	_tier_color = color
	_update_frame_color()
