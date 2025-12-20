extends CanvasLayer
## WoW-style portrait HUD with color-coded health bar
## Displays in upper-left corner for combat visibility

# Health color thresholds
const HP_HEALTHY := Color(0.3, 0.85, 0.3)    # Green >60%
const HP_GOOD := Color(0.7, 0.85, 0.2)       # Yellow 40-60%
const HP_WARNING := Color(0.9, 0.6, 0.1)     # Orange 25-40%
const HP_CRITICAL := Color(0.9, 0.2, 0.2)    # Red <25%

# Layout constants
const PORTRAIT_SIZE := 56.0
const HEALTH_BAR_WIDTH := 90.0
const HEALTH_BAR_HEIGHT := 10.0
const FRAME_THICKNESS := 4.0
const MARGIN := 16.0

# UI elements
var _container: Control
var _portrait_frame: Control
var _portrait_icon: Polygon2D
var _health_bar_bg: ColorRect
var _health_bar_fill: ColorRect
var _health_bar_glow: ColorRect
var _name_label: Label
var _level_badge: Control
var _level_label: Label

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
	_container = Control.new()
	_container.name = "PortraitContainer"
	_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_container.position = Vector2(MARGIN, MARGIN)
	_container.size = Vector2(PORTRAIT_SIZE + HEALTH_BAR_WIDTH + 20, PORTRAIT_SIZE + 30)
	add_child(_container)

	# Portrait frame (circular with tier-colored border)
	_create_portrait_frame()

	# Health bar
	_create_health_bar()

	# Name label
	_create_name_label()

	# Level badge
	_create_level_badge()

func _create_portrait_frame() -> void:
	_portrait_frame = Control.new()
	_portrait_frame.name = "PortraitFrame"
	_portrait_frame.position = Vector2(0, 0)
	_portrait_frame.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_container.add_child(_portrait_frame)

	# Background circle (dark)
	var bg_circle = _create_circle(PORTRAIT_SIZE / 2, Color(0.08, 0.08, 0.10, 0.95))
	bg_circle.position = Vector2(PORTRAIT_SIZE / 2, PORTRAIT_SIZE / 2)
	_portrait_frame.add_child(bg_circle)

	# Portrait icon (warrior silhouette)
	_portrait_icon = _create_warrior_icon()
	_portrait_icon.position = Vector2(PORTRAIT_SIZE / 2, PORTRAIT_SIZE / 2)
	_portrait_frame.add_child(_portrait_icon)

	# Frame border (tier-colored ring)
	var frame_ring = _create_ring(PORTRAIT_SIZE / 2, FRAME_THICKNESS, _tier_color)
	frame_ring.name = "FrameRing"
	frame_ring.position = Vector2(PORTRAIT_SIZE / 2, PORTRAIT_SIZE / 2)
	_portrait_frame.add_child(frame_ring)

func _create_health_bar() -> void:
	var bar_x = PORTRAIT_SIZE + 8
	var bar_y = PORTRAIT_SIZE - HEALTH_BAR_HEIGHT - 4

	# Glow layer (subtle)
	_health_bar_glow = ColorRect.new()
	_health_bar_glow.name = "HealthGlow"
	_health_bar_glow.position = Vector2(bar_x - 2, bar_y - 2)
	_health_bar_glow.size = Vector2(HEALTH_BAR_WIDTH + 4, HEALTH_BAR_HEIGHT + 4)
	_health_bar_glow.color = Color(HP_HEALTHY.r, HP_HEALTHY.g, HP_HEALTHY.b, 0.3)
	_container.add_child(_health_bar_glow)

	# Background (dark rounded)
	_health_bar_bg = ColorRect.new()
	_health_bar_bg.name = "HealthBarBG"
	_health_bar_bg.position = Vector2(bar_x, bar_y)
	_health_bar_bg.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_health_bar_bg.color = Color(0.05, 0.05, 0.07, 0.9)
	_container.add_child(_health_bar_bg)

	# Fill (colored based on health %)
	_health_bar_fill = ColorRect.new()
	_health_bar_fill.name = "HealthBarFill"
	_health_bar_fill.position = Vector2(bar_x + 1, bar_y + 1)
	_health_bar_fill.size = Vector2(HEALTH_BAR_WIDTH - 2, HEALTH_BAR_HEIGHT - 2)
	_health_bar_fill.color = HP_HEALTHY
	_container.add_child(_health_bar_fill)

func _create_name_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.position = Vector2(PORTRAIT_SIZE + 8, 4)
	_name_label.size = Vector2(HEALTH_BAR_WIDTH, 20)
	_name_label.text = "Player"
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_container.add_child(_name_label)

func _create_level_badge() -> void:
	_level_badge = Control.new()
	_level_badge.name = "LevelBadge"
	_level_badge.position = Vector2(PORTRAIT_SIZE + 8, 22)
	_level_badge.size = Vector2(40, 18)
	_container.add_child(_level_badge)

	# Badge background
	var badge_bg = ColorRect.new()
	badge_bg.size = Vector2(40, 18)
	badge_bg.color = Color(0.15, 0.15, 0.18, 0.9)
	_level_badge.add_child(badge_bg)

	# Level text
	_level_label = Label.new()
	_level_label.position = Vector2(0, 0)
	_level_label.size = Vector2(40, 18)
	_level_label.text = "Lv. 1"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_level_badge.add_child(_level_label)

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

func _create_warrior_icon() -> Polygon2D:
	# Simple warrior/sword silhouette
	var icon = Polygon2D.new()
	var scale = 0.8

	# Sword shape pointing up
	icon.polygon = PackedVector2Array([
		Vector2(0, -18) * scale,    # Blade tip
		Vector2(3, -12) * scale,    # Blade right
		Vector2(3, 2) * scale,      # Guard right
		Vector2(8, 2) * scale,      # Guard end right
		Vector2(8, 5) * scale,      # Guard bottom right
		Vector2(2, 5) * scale,      # Handle top right
		Vector2(2, 14) * scale,     # Handle bottom right
		Vector2(4, 16) * scale,     # Pommel right
		Vector2(0, 18) * scale,     # Pommel bottom
		Vector2(-4, 16) * scale,    # Pommel left
		Vector2(-2, 14) * scale,    # Handle bottom left
		Vector2(-2, 5) * scale,     # Handle top left
		Vector2(-8, 5) * scale,     # Guard bottom left
		Vector2(-8, 2) * scale,     # Guard end left
		Vector2(-3, 2) * scale,     # Guard left
		Vector2(-3, -12) * scale,   # Blade left
	])
	icon.color = Color(0.7, 0.7, 0.75, 0.9)  # Silver/steel color
	return icon

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
			_level_label.text = "Lv. %d" % stats.level
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

	# Kill existing tween
	if _health_tween and _health_tween.is_valid():
		_health_tween.kill()

	# Animate health bar
	_health_tween = create_tween()
	_health_tween.set_parallel(true)
	_health_tween.tween_property(_health_bar_fill, "size:x", target_width, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_health_tween.tween_property(_health_bar_fill, "color", target_color, 0.3)
	_health_tween.tween_property(_health_bar_glow, "color", Color(target_color.r, target_color.g, target_color.b, 0.3), 0.3)

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
	# Update the ring color to match tier
	var frame_ring = _portrait_frame.get_node_or_null("FrameRing")
	if frame_ring:
		for child in frame_ring.get_children():
			if child is Polygon2D:
				child.color = _tier_color

func _on_level_up(new_level: int) -> void:
	_level_label.text = "Lv. %d" % new_level

	# Flash effect on level up
	var original_color = _level_label.get_theme_color("font_color")
	_level_label.add_theme_color_override("font_color", Color(1, 1, 0.5))

	var tween = create_tween()
	tween.tween_property(_level_label, "theme_override_colors/font_color", original_color, 0.5)

func set_player_name(player_name: String) -> void:
	_name_label.text = player_name

func set_tier_color(color: Color) -> void:
	_tier_color = color
	_update_frame_color()
