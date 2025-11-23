extends Control

# ✨ NEW JUICY HEALTH BAR SYSTEM
@onready var background: Control = null
@onready var fill: Control = null
@onready var damage_flash: Control = null
@onready var glow: Control = null

var ready_to_position: bool = false
var has_positioned_once: bool = false
var current_health: float = 100.0
var max_health: float = 100.0
var is_pulsing: bool = false

# 🎨 Health color thresholds - BRIGHT & VIBRANT!
const COLOR_HEALTHY = Color(0.3, 1.35, 0.45, 1.0)      # Bright vibrant green (50% brighter)
const COLOR_GOOD = Color(0.9, 1.35, 0.3, 1.0)          # Bright yellow-green (50% brighter)
const COLOR_WARNING = Color(1.4, 1.05, 0.15, 1.0)      # Bright orange (50% brighter)
const COLOR_CRITICAL = Color(1.4, 0.3, 0.2, 1.0)       # Bright red (50% brighter)
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

func _process(_delta: float) -> void:
	# Only position once parent is ready
	if not ready_to_position:
		return
	
	# Position healthbar in world space (doesn't rotate with player)
	if get_parent() and is_instance_valid(get_parent()):
		var parent_scale = get_parent().scale.x  # Assume uniform scaling
		
		# Offset scales with parent - hovering right over character head!
		# Reduced offset for closer positioning
		var offset_y = (35 + 4) * parent_scale  # 39 pixels total (was 54)
		
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
	
	# Calculate health percentage
	var health_percent = (current_health / max_health) * 100.0
	
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
	
	# 📏 Calculate fill width
	var target_width = (current_health / max_health) * BAR_WIDTH
	target_width = max(0.0, target_width)  # Ensure never negative
	
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
