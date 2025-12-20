extends Control

# ✨ NEW JUICY HEALTH BAR SYSTEM
@onready var background: Control = null
@onready var fill: Control = null
@onready var damage_flash: Control = null
@onready var glow: Control = null
var name_label: Label = null
var ashbane_badge_left: Control = null   # Left tier badge
var ashbane_badge_right: Control = null  # Right tier badge
var ashbane_tier: String = ""  # Current Ashbane tier

var ready_to_position: bool = false
var has_positioned_once: bool = false
var current_health: float = 100.0
var max_health: float = 100.0
var is_pulsing: bool = false
var player_name: String = ""
var custom_offset_y: float = -1.0  # Custom offset override (-1 = use default)

# Performance: throttle position updates
var position_update_timer: float = 0.0
const POSITION_UPDATE_INTERVAL: float = 0.05  # Update position 20 times per second

# 🎨 Health color thresholds - use UITheme singleton
var COLOR_HEALTHY: Color:
	get: return UITheme.HP_HEALTHY
var COLOR_GOOD: Color:
	get: return UITheme.HP_GOOD
var COLOR_WARNING: Color:
	get: return UITheme.HP_WARNING
var COLOR_CRITICAL: Color:
	get: return UITheme.HP_CRITICAL
const COLOR_BACKGROUND = Color(0.15, 0.15, 0.15, 0.9)  # Dark gray (stays same for contrast)
const COLOR_FLASH = Color(2.0, 2.0, 2.0, 1.0)          # Even brighter white flash!

# 💊 Pill capsule dimensions (thin bar)
const BAR_WIDTH = 50.0
const BAR_HEIGHT = 6.0

func _ready() -> void:
	# Create the pill capsule health bar
	create_pill_capsule_bar()

	# Make healthbar use world space positioning
	top_level = true

	# Ensure health bar renders above player sprites
	z_index = 100

	# Hide initially to prevent flashing at wrong position
	visible = false
	
	# Wait for parent to be fully initialized and in scene tree
	await get_tree().process_frame
	
	# Additional safety: wait for parent to have valid position
	if get_parent() and is_instance_valid(get_parent()):
		# Wait until parent is properly in tree with valid position
		while not get_parent().is_inside_tree() or get_parent().global_position == Vector2.ZERO:
			await get_tree().process_frame
	
	ready_to_position = true

func create_pill_capsule_bar() -> void:
	"""Create the juicy pill capsule health bar from scratch"""
	
	# Set control size
	custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	
	# 🌟 GLOW LAYER (bottom, slightly larger) - Using Panel for rounded corners
	var glow_panel = Panel.new()
	glow_panel.name = "GlowPanel"
	glow_panel.size = Vector2(BAR_WIDTH + 2, BAR_HEIGHT + 2)
	glow_panel.position = Vector2(-1, -1)
	
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0.45, 1.35, 0.6, 0.4)  # Brighter green glow to match!
	glow_style.corner_radius_top_left = int(BAR_HEIGHT / 2) + 1
	glow_style.corner_radius_top_right = int(BAR_HEIGHT / 2) + 1
	glow_style.corner_radius_bottom_left = int(BAR_HEIGHT / 2) + 1
	glow_style.corner_radius_bottom_right = int(BAR_HEIGHT / 2) + 1
	glow_panel.add_theme_stylebox_override("panel", glow_style)
	
	add_child(glow_panel)
	glow = glow_panel  # Store reference
	
	# 🎯 BACKGROUND (dark pill shape) - Using Panel for rounded corners
	var bg_panel = Panel.new()
	bg_panel.name = "Background"
	bg_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = COLOR_BACKGROUND
	bg_style.corner_radius_top_left = int(BAR_HEIGHT / 2)
	bg_style.corner_radius_top_right = int(BAR_HEIGHT / 2)
	bg_style.corner_radius_bottom_left = int(BAR_HEIGHT / 2)
	bg_style.corner_radius_bottom_right = int(BAR_HEIGHT / 2)
	# Set borders individually (border_width_all not available in all versions)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.05, 0.05, 0.05, 1.0)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	
	add_child(bg_panel)
	background = bg_panel  # Store reference
	
	# 💚 FILL (colored health bar) - Using Panel for rounded corners
	var fill_panel = Panel.new()
	fill_panel.name = "Fill"
	fill_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill_panel.clip_contents = true
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = COLOR_HEALTHY
	fill_style.corner_radius_top_left = int(BAR_HEIGHT / 2)
	fill_style.corner_radius_top_right = int(BAR_HEIGHT / 2)
	fill_style.corner_radius_bottom_left = int(BAR_HEIGHT / 2)
	fill_style.corner_radius_bottom_right = int(BAR_HEIGHT / 2)
	fill_panel.add_theme_stylebox_override("panel", fill_style)
	
	add_child(fill_panel)
	fill = fill_panel  # Store reference
	
	# ✨ DAMAGE FLASH (white overlay) - Using Panel for rounded corners
	var flash_panel = Panel.new()
	flash_panel.name = "DamageFlash"
	flash_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	
	var flash_style = StyleBoxFlat.new()
	flash_style.bg_color = Color(1.5, 1.5, 1.5, 0.0)
	flash_style.corner_radius_top_left = int(BAR_HEIGHT / 2)
	flash_style.corner_radius_top_right = int(BAR_HEIGHT / 2)
	flash_style.corner_radius_bottom_left = int(BAR_HEIGHT / 2)
	flash_style.corner_radius_bottom_right = int(BAR_HEIGHT / 2)
	flash_panel.add_theme_stylebox_override("panel", flash_style)
	
	add_child(flash_panel)
	damage_flash = flash_panel  # Store reference

	# 📛 NAME ROW (HBox container for badge + name + badge above health bar)
	var name_row = HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 3)  # Gap between elements
	# Position centered above the health bar (bar is 50px wide, center at x=25)
	# Row is 150px wide, so left edge at 25 - 75 = -50
	name_row.position = Vector2(-50, -18)
	name_row.custom_minimum_size = Vector2(150, 16)
	add_child(name_row)

	# 🏆 LEFT BADGE (tier indicator)
	ashbane_badge_left = _create_badge_diamond()
	ashbane_badge_left.name = "AshbaneBadgeLeft"
	ashbane_badge_left.visible = false
	name_row.add_child(ashbane_badge_left)

	# Name label inside the row (centered between badges)
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = ""
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.visible = false  # Hidden until name is set
	name_row.add_child(name_label)

	# 🏆 RIGHT BADGE (tier indicator)
	ashbane_badge_right = _create_badge_diamond()
	ashbane_badge_right.name = "AshbaneBadgeRight"
	ashbane_badge_right.visible = false
	name_row.add_child(ashbane_badge_right)

func _process(delta: float) -> void:
	# Only position once parent is ready
	if not ready_to_position:
		return

	# Check if this is the player's healthbar - no throttling for player (causes jitter)
	var is_player = get_parent() and get_parent().is_in_group("player")

	# Throttle position updates for enemies only (75 health bars * 60 FPS = 4500 updates/sec)
	if not is_player:
		position_update_timer += delta
		if position_update_timer < POSITION_UPDATE_INTERVAL:
			return
		position_update_timer = 0.0

	# Position healthbar in world space (doesn't rotate with player)
	if get_parent() and is_instance_valid(get_parent()):
		var parent_scale = get_parent().scale.x  # Assume uniform scaling

		# Offset scales with parent - hovering right over character head!
		# For enemies: position above name label (name at -42, healthbar above it)
		# For players: position closer to head
		var offset_y: float
		if custom_offset_y > 0:
			offset_y = custom_offset_y * parent_scale  # Use custom offset if set
		elif is_player:
			offset_y = (35 + 4) * parent_scale  # 39 pixels for players
		else:
			offset_y = 52 * parent_scale  # 52 pixels for enemies (above name label at -42)

		# Center healthbar above parent
		global_position = get_parent().global_position - Vector2(size.x / 2, offset_y)

		# Scale healthbar to match parent (optional - makes it bigger/smaller with enemy)
		scale = Vector2(parent_scale, parent_scale)

		# Always horizontal
		rotation = 0.0

		# Show the health bar after first successful positioning
		if not has_positioned_once:
			visible = true
			has_positioned_once = true

func update_health(current: float, maximum: float) -> void:
	"""✨ JUICY health update with smooth animation and color transitions"""

	var previous_health = current_health
	current_health = current
	max_health = maximum

	# Safety: ensure max_health is valid
	if max_health <= 0:
		max_health = 100.0

	# Calculate health percentage (clamped 0-100)
	var health_percent = clampf((current_health / max_health) * 100.0, 0.0, 100.0)

	# 🎨 Determine color based on health percentage
	var target_color: Color
	if health_percent > 60.0:
		target_color = COLOR_HEALTHY  # Green
	elif health_percent > 40.0:
		target_color = COLOR_GOOD  # Yellow-green
	elif health_percent > 25.0:
		target_color = COLOR_WARNING  # Orange
	else:
		target_color = COLOR_CRITICAL  # Red

	# 📏 Calculate fill width (clamped to BAR_WIDTH to prevent overflow)
	var target_width = (current_health / max_health) * BAR_WIDTH
	target_width = clampf(target_width, 0.0, BAR_WIDTH)  # Never exceed bar bounds
	
	# ✨ Smooth tween for bar width
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	
	# Animate width
	tween.tween_property(fill, "size:x", target_width, 0.3)
	
	# Animate fill color transition (update the StyleBox)
	if fill:
		var fill_style = fill.get_theme_stylebox("panel")
		if fill_style:
			tween.tween_property(fill_style, "bg_color", target_color, 0.3)
	
	# Animate glow color transition
	if glow:
		var glow_style = glow.get_theme_stylebox("panel")
		if glow_style:
			var glow_color = Color(target_color.r, target_color.g, target_color.b, 0.3)
			tween.tween_property(glow_style, "bg_color", glow_color, 0.3)
	
	# 💥 DAMAGE FLASH if health decreased
	if current < previous_health:
		flash_damage()
	
	# 🎯 Start pulsing if critical health
	if health_percent <= 25.0 and not is_pulsing:
		start_critical_pulse()
	elif health_percent > 25.0 and is_pulsing:
		stop_critical_pulse()

func flash_damage() -> void:
	"""✨ White flash when taking damage"""
	if not damage_flash:
		return
	
	var flash_style = damage_flash.get_theme_stylebox("panel")
	if flash_style:
		flash_style.bg_color = COLOR_FLASH
		
		var flash_tween = create_tween()
		flash_tween.tween_property(flash_style, "bg_color", Color(1.5, 1.5, 1.5, 0.0), 0.2)

func start_critical_pulse() -> void:
	"""🎯 Pulsing glow effect when health is critical"""
	if is_pulsing:
		return
	
	is_pulsing = true
	pulse_critical()

func pulse_critical() -> void:
	"""Recursive pulse animation"""
	if not is_pulsing or not is_instance_valid(self) or not glow:
		return
	
	var glow_style = glow.get_theme_stylebox("panel")
	if not glow_style:
		return
	
	var pulse_tween = create_tween()
	pulse_tween.set_ease(Tween.EASE_IN_OUT)
	pulse_tween.set_trans(Tween.TRANS_SINE)
	
	# Get current color to preserve RGB, just animate alpha
	var current_color = glow_style.bg_color
	var bright_color = Color(current_color.r, current_color.g, current_color.b, 0.6)
	var dim_color = Color(current_color.r, current_color.g, current_color.b, 0.2)
	
	# Pulse glow opacity
	pulse_tween.tween_property(glow_style, "bg_color", bright_color, 0.5)
	pulse_tween.tween_property(glow_style, "bg_color", dim_color, 0.5)
	
	# Pulse scale slightly
	pulse_tween.parallel().tween_property(glow, "scale", Vector2(1.1, 1.1), 0.5)
	pulse_tween.tween_property(glow, "scale", Vector2(1.0, 1.0), 0.5)
	
	await pulse_tween.finished
	
	# Continue pulsing
	if is_pulsing:
		pulse_critical()

func stop_critical_pulse() -> void:
	"""Stop the critical health pulse"""
	is_pulsing = false

	if glow:
		var glow_style = glow.get_theme_stylebox("panel")
		if glow_style:
			var stop_tween = create_tween()
			var current_color = glow_style.bg_color
			var normal_color = Color(current_color.r, current_color.g, current_color.b, 0.3)
			stop_tween.tween_property(glow_style, "bg_color", normal_color, 0.3)
			stop_tween.parallel().tween_property(glow, "scale", Vector2(1.0, 1.0), 0.3)

func set_player_name(new_name: String) -> void:
	"""Set the player name to display above the health bar"""
	print("🏷️ [HEALTHBAR] set_player_name('%s') called, name_label=%s" % [new_name, name_label])
	player_name = new_name
	if name_label:
		name_label.text = new_name
		name_label.visible = not new_name.is_empty()
		print("🏷️ [HEALTHBAR] Label set: text='%s', visible=%s, position=%s, size=%s" % [
			name_label.text, name_label.visible, name_label.position, name_label.size
		])
	else:
		print("❌ [HEALTHBAR] name_label is null!")

func set_name_color(color: Color) -> void:
	"""Set the name label color (e.g., different for guests vs authenticated)"""
	if name_label:
		name_label.add_theme_color_override("font_color", color)

func set_custom_offset(offset: float) -> void:
	"""Set a custom Y offset for positioning (for non-standard entities like Training Dummy)"""
	custom_offset_y = offset

# ═══════════════════════════════════════════════════════════════════════════
# ASHBANE TIER BADGE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func _create_badge_diamond() -> Control:
	"""Create a diamond-shaped tier badge and return it"""
	var badge = Control.new()
	badge.custom_minimum_size = Vector2(12, 12)
	badge.size = Vector2(12, 12)

	# Create badge background (diamond shape using a rotated square)
	var badge_bg = Panel.new()
	badge_bg.name = "BadgeBG"
	badge_bg.size = Vector2(8, 8)
	badge_bg.position = Vector2(2, 2)  # Center in the 12x12 container
	badge_bg.rotation = deg_to_rad(45)
	badge_bg.pivot_offset = Vector2(4, 4)

	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.4, 0.4, 0.4, 0.9)  # Default gray
	badge_style.corner_radius_top_left = 1
	badge_style.corner_radius_top_right = 1
	badge_style.corner_radius_bottom_left = 1
	badge_style.corner_radius_bottom_right = 1
	badge_style.border_width_left = 1
	badge_style.border_width_right = 1
	badge_style.border_width_top = 1
	badge_style.border_width_bottom = 1
	badge_style.border_color = Color(0.2, 0.2, 0.2, 1.0)
	badge_bg.add_theme_stylebox_override("panel", badge_style)

	badge.add_child(badge_bg)
	return badge

func _update_badge_style(badge: Control, badge_color: Color, glow_color: Color) -> void:
	"""Update a badge's color and glow"""
	if not badge:
		return
	var badge_bg = badge.get_node_or_null("BadgeBG")
	if badge_bg:
		var style = badge_bg.get_theme_stylebox("panel")
		if style:
			style.bg_color = badge_color
			# Add border glow for higher tiers
			if glow_color.a > 0.3:
				style.border_color = glow_color
				style.border_width_left = 2
				style.border_width_right = 2
				style.border_width_top = 2
				style.border_width_bottom = 2
			else:
				style.border_color = Color(0.2, 0.2, 0.2, 1.0)
				style.border_width_left = 1
				style.border_width_right = 1
				style.border_width_top = 1
				style.border_width_bottom = 1

func set_ashbane_tier(tier: String) -> void:
	"""Set the Ashbane tier badge color and visibility"""
	ashbane_tier = tier.to_lower()

	# Get tier color from AshbaneCosmetics
	var badge_color = Color(0.4, 0.4, 0.4)  # Default gray
	var glow_color = Color.TRANSPARENT

	if AshbaneCosmetics:
		badge_color = AshbaneCosmetics.get_tier_badge_color(ashbane_tier)
		glow_color = AshbaneCosmetics.get_tier_glow_color(ashbane_tier)

	# Update both badges
	_update_badge_style(ashbane_badge_left, badge_color, glow_color)
	_update_badge_style(ashbane_badge_right, badge_color, glow_color)

	# Show badges if tier is set (hide for guests/initiate)
	var show_badges = ashbane_tier != "" and ashbane_tier != "initiate"
	if ashbane_badge_left:
		ashbane_badge_left.visible = show_badges
	if ashbane_badge_right:
		ashbane_badge_right.visible = show_badges

	# Update name color based on tier
	if name_label and AshbaneCosmetics and AshbaneCosmetics.TIER_COSMETICS.has(ashbane_tier):
		var tier_data = AshbaneCosmetics.TIER_COSMETICS[ashbane_tier]
		var name_color = tier_data.get("badge_color", Color(0.9, 0.9, 0.9))
		# Slightly desaturate for readability
		name_color = name_color.lerp(Color.WHITE, 0.3)
		name_label.add_theme_color_override("font_color", name_color)

func get_ashbane_tier() -> String:
	"""Get the current Ashbane tier"""
	return ashbane_tier
