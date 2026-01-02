extends Control

# ✨ NEW JUICY HEALTH BAR SYSTEM
@onready var background: Control = null
@onready var fill: Control = null
@onready var damage_flash: Control = null
@onready var glow: Control = null
var name_label: Label = null
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

# Rectangle bar dimensions (modern look)
const BAR_WIDTH = 50.0
const BAR_HEIGHT = 6.0

func _ready() -> void:
	# Skip all visual creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args():
		ready_to_position = false
		set_process(false)
		visible = false
		return

	# Create the modern rectangle health bar
	create_rectangle_bar()

	# Make healthbar use world space positioning
	top_level = true

	# Ensure health bar renders above player sprites
	z_index = 100
	light_mask = 0  # Ignore scene lighting (fire glow, etc.)

	# Hide initially to prevent flashing at wrong position
	visible = false

	# Wait for parent to be fully initialized and in scene tree
	if not is_inside_tree():
		await ready  # Wait until we're in the tree

	await get_tree().process_frame

	# Additional safety: wait for parent to have valid position
	if get_parent() and is_instance_valid(get_parent()):
		# Wait until parent is properly in tree with valid position (max 60 frames to prevent infinite loop)
		var wait_frames = 0
		while wait_frames < 60 and (not get_parent().is_inside_tree() or get_parent().global_position == Vector2.ZERO):
			await get_tree().process_frame
			wait_frames += 1

	ready_to_position = true

func create_rectangle_bar() -> void:
	"""Create the modern rectangle health bar from scratch"""

	# Set control size
	custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	# 🌟 GLOW LAYER (bottom, slightly larger) - hard rectangle edges
	var glow_panel = Panel.new()
	glow_panel.name = "GlowPanel"
	glow_panel.size = Vector2(BAR_WIDTH + 2, BAR_HEIGHT + 2)
	glow_panel.position = Vector2(-1, -1)

	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(0.45, 1.35, 0.6, 0.4)  # Brighter green glow to match!
	# Hard rectangle edges - no corner radius
	glow_panel.add_theme_stylebox_override("panel", glow_style)

	add_child(glow_panel)
	glow = glow_panel  # Store reference

	# 🎯 BACKGROUND (dark rectangle) - hard edges
	var bg_panel = Panel.new()
	bg_panel.name = "Background"
	bg_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = COLOR_BACKGROUND
	# Hard rectangle edges - no corner radius
	# Set borders individually
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.05, 0.05, 0.05, 1.0)
	bg_panel.add_theme_stylebox_override("panel", bg_style)

	add_child(bg_panel)
	background = bg_panel  # Store reference

	# 💚 FILL (colored health bar) - hard rectangle edges
	var fill_panel = Panel.new()
	fill_panel.name = "Fill"
	fill_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	fill_panel.clip_contents = true

	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = COLOR_HEALTHY
	# Hard rectangle edges - no corner radius
	fill_panel.add_theme_stylebox_override("panel", fill_style)

	add_child(fill_panel)
	fill = fill_panel  # Store reference

	# ✨ DAMAGE FLASH (white overlay) - hard rectangle edges
	var flash_panel = Panel.new()
	flash_panel.name = "DamageFlash"
	flash_panel.size = Vector2(BAR_WIDTH, BAR_HEIGHT)

	var flash_style = StyleBoxFlat.new()
	flash_style.bg_color = Color(1.5, 1.5, 1.5, 0.0)
	# Hard rectangle edges - no corner radius
	flash_panel.add_theme_stylebox_override("panel", flash_style)

	add_child(flash_panel)
	damage_flash = flash_panel  # Store reference

	# 📛 NAME LABEL (centered above health bar)
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = ""
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.visible = false  # Hidden until name is set
	# Position centered above health bar
	name_label.position = Vector2(-50, -18)
	name_label.custom_minimum_size = Vector2(150, 16)
	add_child(name_label)

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
	# DEDICATED SERVER: Skip all visual updates
	if not fill:
		current_health = current
		max_health = maximum
		return

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
	# Strip "ashbane-" prefix if present for cleaner display
	var display_name = new_name
	if display_name.begins_with("ashbane-"):
		display_name = display_name.substr(8)  # Remove "ashbane-" (8 chars)

	player_name = display_name
	if name_label:
		name_label.text = display_name
		name_label.visible = not display_name.is_empty()
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
# ASHBANE TIER SYSTEM
# ═══════════════════════════════════════════════════════════════════════════

func set_ashbane_tier(tier: String) -> void:
	"""Set the Ashbane tier - updates name color based on tier"""
	ashbane_tier = tier.to_lower()

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
