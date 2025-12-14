extends Node
## UITheme.gd - Centralized UI color constants and styling
## Use this singleton for consistent colors across all UI elements

# ═══════════════════════════════════════════════════════════════════════════
# PANEL & BACKGROUND COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Main panel background - dark stone gray
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.95)
const BG_COLOR_TRANSPARENT = Color(0.12, 0.12, 0.14, 0.75)
const BG_COLOR_SOLID = Color(0.12, 0.12, 0.14, 1.0)

## Slot/input backgrounds - darker inset
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)
const INPUT_BG = Color(0.08, 0.08, 0.10, 0.9)

# ═══════════════════════════════════════════════════════════════════════════
# BORDER COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Steel gray border
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)
## Dark inner shadow
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# TEXT COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Primary text - clean white
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)
## Headers - silver
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)
## Accent text - light steel
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)
## Muted/secondary text
const TEXT_MUTED = Color(0.6, 0.6, 0.6, 0.8)
## Disabled text
const TEXT_DISABLED = Color(0.5, 0.5, 0.5, 0.6)

# ═══════════════════════════════════════════════════════════════════════════
# STATUS COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Success/positive - green
const SUCCESS_COLOR = Color(0.3, 1.0, 0.3, 1.0)
const BUFF_COLOR = Color(0.3, 0.8, 0.3, 1.0)
## Warning - orange/gold
const WARNING_COLOR = Color(1.0, 0.7, 0.3, 1.0)
const HIGHLIGHT_COLOR = Color(1.0, 0.9, 0.3, 1.0)
## Error/negative - red
const ERROR_COLOR = Color(1.0, 0.5, 0.5, 1.0)
const DEBUFF_COLOR = Color(0.8, 0.3, 0.2, 1.0)
## Info - blue
const INFO_COLOR = Color(0.6, 0.7, 0.9, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# HEALTH & RESOURCE COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Health bar colors
const HP_COLOR = Color(0.85, 0.20, 0.15, 1.0)
const HP_HEALTHY = Color(0.3, 1.35, 0.45, 1.0)
const HP_GOOD = Color(0.9, 1.35, 0.3, 1.0)
const HP_WARNING = Color(1.4, 1.05, 0.15, 1.0)
const HP_CRITICAL = Color(1.4, 0.3, 0.2, 1.0)

## XP bar
const XP_COLOR = Color(0.40, 0.55, 0.70, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# RARITY COLORS
# ═══════════════════════════════════════════════════════════════════════════

const RARITY_COMMON = Color(0.6, 0.6, 0.6, 0.9)
const RARITY_UNCOMMON = Color(0.4, 0.8, 0.4, 1.0)
const RARITY_RARE = Color(0.4, 0.5, 0.9, 1.0)
const RARITY_EPIC = Color(0.7, 0.4, 0.9, 1.0)
const RARITY_LEGENDARY = Color(0.9, 0.6, 0.2, 1.0)
const RARITY_MYTHIC = Color(0.9, 0.8, 0.3, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# CHAT COLORS
# ═══════════════════════════════════════════════════════════════════════════

const CHAT_SYSTEM = Color(0.6, 0.7, 0.9, 1.0)
const CHAT_LOCAL = Color(0.9, 0.85, 0.5, 1.0)
const CHAT_WHISPER = Color(0.9, 0.5, 0.9, 1.0)
const CHAT_GROUP = Color(0.5, 0.9, 0.5, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# BUTTON COLORS
# ═══════════════════════════════════════════════════════════════════════════

const BTN_NORMAL = Color(0.25, 0.26, 0.30, 0.8)
const BTN_HOVER = Color(0.32, 0.34, 0.40, 0.9)
const BTN_PRESSED = Color(0.18, 0.19, 0.22, 0.9)
const BTN_DISABLED = Color(0.2, 0.2, 0.22, 0.5)

const BTN_SUCCESS = Color(0.3, 0.5, 0.3, 1.0)
const BTN_SUCCESS_HOVER = Color(0.35, 0.55, 0.35, 1.0)
const BTN_DANGER = Color(0.6, 0.3, 0.3, 0.7)
const BTN_DANGER_HOVER = Color(0.7, 0.4, 0.4, 0.9)

# ═══════════════════════════════════════════════════════════════════════════
# TOOLTIP COLORS
# ═══════════════════════════════════════════════════════════════════════════

## Tooltip background - very opaque dark panel for readability
const TOOLTIP_BG = Color(0.08, 0.08, 0.10, 0.98)
const TOOLTIP_BORDER = Color(0.45, 0.48, 0.52, 1.0)

# ═══════════════════════════════════════════════════════════════════════════
# TYPOGRAPHY SCALE
# ═══════════════════════════════════════════════════════════════════════════

## Font sizes for consistent typography hierarchy
const FONT_H1 = 24       # Panel titles, major headings
const FONT_H2 = 20       # Section headers
const FONT_H3 = 18       # Subsection headers
const FONT_BODY = 14     # Body text, labels (MINIMUM for readability)
const FONT_CAPTION = 12  # Small labels, tooltips
const FONT_TINY = 10     # Absolute minimum (use sparingly)

# ═══════════════════════════════════════════════════════════════════════════
# ANIMATION TIMINGS
# ═══════════════════════════════════════════════════════════════════════════

## Standard animation durations for consistent UX feel
const ANIM_INSTANT = 0.05   # Instant feedback (flash effects, immediate response)
const ANIM_FAST = 0.1       # Fast interactions (button clicks, toggles, hover)
const ANIM_NORMAL = 0.2     # Normal transitions (panel open/close, slides)
const ANIM_SLOW = 0.3       # Emphasis animations (celebrations, important events)
const ANIM_VERY_SLOW = 0.5  # Dramatic effects (level up, achievements)

# ═══════════════════════════════════════════════════════════════════════════
# UI MEASUREMENTS
# ═══════════════════════════════════════════════════════════════════════════

## Standard slot size for inventory/equipment (matches existing implementations)
const SLOT_SIZE = 54
const ICON_SIZE = 46  # SLOT_SIZE - 8 (padding)

## Corner radius scale
const CORNER_RADIUS_LARGE = 8   # Panels, major containers
const CORNER_RADIUS_MEDIUM = 6  # Cards, medium elements
const CORNER_RADIUS_SMALL = 4   # Buttons, slots, small elements

# ═══════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

## Get rarity color by rarity level (0-5)
static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		0: return RARITY_COMMON
		1: return RARITY_UNCOMMON
		2: return RARITY_RARE
		3: return RARITY_EPIC
		4: return RARITY_LEGENDARY
		5: return RARITY_MYTHIC
		_: return RARITY_COMMON

## Get rarity color by rarity name string ("COMMON", "LEGENDARY", etc.)
static func get_rarity_color_by_name(rarity_name: String) -> Color:
	match rarity_name.to_upper():
		"COMMON": return RARITY_COMMON
		"UNCOMMON": return RARITY_UNCOMMON
		"RARE": return RARITY_RARE
		"EPIC": return RARITY_EPIC
		"LEGENDARY": return RARITY_LEGENDARY
		"MYTHIC", "ARTIFACT": return RARITY_MYTHIC
		_: return RARITY_COMMON

## Create a standard panel StyleBoxFlat
static func create_panel_style(transparent: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR_TRANSPARENT if transparent else BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	return style

## Create a slot/input StyleBoxFlat
static func create_slot_style(use_glow: bool = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_color = BORDER_INNER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	if use_glow:
		style.shadow_size = 4
		style.shadow_color = Color(0.3, 0.5, 0.3, 0.5)
	return style

## Create a standard button StyleBoxFlat
static func create_button_style(type: String = "normal") -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	match type:
		"normal":
			style.bg_color = BTN_NORMAL
		"hover":
			style.bg_color = BTN_HOVER
		"pressed":
			style.bg_color = BTN_PRESSED
		"disabled":
			style.bg_color = BTN_DISABLED
		"success":
			style.bg_color = BTN_SUCCESS
		"danger":
			style.bg_color = BTN_DANGER
	style.set_corner_radius_all(4)
	return style

## Create tooltip StyleBoxFlat - opaque for readability
static func create_tooltip_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = TOOLTIP_BG
	style.border_color = TOOLTIP_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	# Add subtle shadow for depth
	style.shadow_size = 4
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_offset = Vector2(2, 2)
	return style

# ═══════════════════════════════════════════════════════════════════════════
# BUTTON FACTORY METHODS
# ═══════════════════════════════════════════════════════════════════════════

## Apply 3-state button styling (normal, hover, pressed) with consistent appearance
static func style_button_3_state(button: Button, type: String = "normal", custom_color: Color = Color.TRANSPARENT) -> void:
	"""Apply consistent 3-state styling to a button

	Args:
		button: The Button node to style
		type: Button type - "normal", "success", "danger", or "custom"
		custom_color: Base color for "custom" type
	"""
	var base_color: Color

	# Determine base color
	if type == "custom" and custom_color != Color.TRANSPARENT:
		base_color = custom_color
	else:
		match type:
			"success": base_color = BTN_SUCCESS
			"danger": base_color = BTN_DANGER
			_: base_color = BTN_NORMAL

	# Normal state
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = base_color
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)

	# Hover state (20% lighter)
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = base_color.lightened(0.2)

	# Pressed state (20% darker)
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = base_color.darkened(0.2)

	# Disabled state (semi-transparent)
	var disabled_style = normal_style.duplicate()
	disabled_style.bg_color = BTN_DISABLED

	# Apply styles
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled_style)

	# Apply text color
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	button.add_theme_font_size_override("font_size", 14)

## Create a fully-configured button with consistent styling and optional sounds
static func create_button(text: String, type: String = "normal", enable_sounds: bool = true, custom_color: Color = Color.TRANSPARENT) -> Button:
	"""Create a button with consistent styling and optional audio feedback

	Args:
		text: Button text
		type: Button type - "normal", "success", "danger", or "custom"
		enable_sounds: Whether to connect hover/click sounds
		custom_color: Base color for "custom" type buttons

	Returns:
		Fully configured Button node
	"""
	var button = Button.new()
	button.text = text

	# Apply styling
	style_button_3_state(button, type, custom_color)

	# Connect sounds and hover animations
	if enable_sounds:
		# Hover effects (sound + scale animation)
		button.mouse_entered.connect(func():
			if SoundManager:
				SoundManager.play_button_hover_sound()
			# Subtle scale up on hover
			var tween = button.create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_BACK)
			tween.tween_property(button, "scale", Vector2(1.05, 1.05), ANIM_FAST)
		)

		# Mouse exit (scale back to normal)
		button.mouse_exited.connect(func():
			var tween = button.create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(button, "scale", Vector2(1.0, 1.0), ANIM_FAST)
		)

		# Click sound
		button.pressed.connect(func():
			if SoundManager:
				SoundManager.play_button_click_sound()
		)

	return button

## Create a close button (square X button for panels)
static func create_close_button(enable_sounds: bool = true) -> Button:
	"""Create a standardized close button (red X)

	Args:
		enable_sounds: Whether to connect hover/click sounds

	Returns:
		Configured close Button node
	"""
	var button = Button.new()
	button.text = "X"
	button.custom_minimum_size = Vector2(28, 28)

	# Custom red styling for close buttons
	style_button_3_state(button, "danger")

	# Override content margins to be square
	var normal_style = button.get_theme_stylebox("normal").duplicate()
	normal_style.set_content_margin_all(0)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style = button.get_theme_stylebox("hover").duplicate()
	hover_style.set_content_margin_all(0)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = button.get_theme_stylebox("pressed").duplicate()
	pressed_style.set_content_margin_all(0)
	button.add_theme_stylebox_override("pressed", pressed_style)

	# Connect sounds and hover animations if enabled
	if enable_sounds:
		# Hover effects (sound + scale animation)
		button.mouse_entered.connect(func():
			if SoundManager:
				SoundManager.play_button_hover_sound()
			# Subtle scale up on hover
			var tween = button.create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_BACK)
			tween.tween_property(button, "scale", Vector2(1.05, 1.05), ANIM_FAST)
		)

		# Mouse exit (scale back to normal)
		button.mouse_exited.connect(func():
			var tween = button.create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.tween_property(button, "scale", Vector2(1.0, 1.0), ANIM_FAST)
		)

		# Click sound
		button.pressed.connect(func():
			if SoundManager:
				SoundManager.play_button_click_sound()
		)

	return button

var default_font: Font = null

func _ready() -> void:
	# Load the Inter font
	_load_default_font()
	# Defer tooltip styling until tree is ready
	call_deferred("_apply_tooltip_theme")

func _load_default_font() -> void:
	"""Load and configure the default Inter font"""
	var font_path = "res://assets/fonts/Inter-Regular.ttf"
	if ResourceLoader.exists(font_path):
		default_font = load(font_path)
		if default_font:
			print("[UITheme] ✅ Loaded Inter font: %s" % font_path)
		else:
			push_warning("[UITheme] Failed to load font: %s" % font_path)
	else:
		push_warning("[UITheme] Font file not found: %s" % font_path)

func _apply_tooltip_theme() -> void:
	"""Apply opaque tooltip styling to the project theme"""
	var tooltip_style = create_tooltip_style()

	# Create a theme and apply to root viewport
	var root = get_tree().root if get_tree() else null
	if root:
		if root.theme == null:
			root.theme = Theme.new()

		# Set default font for the entire UI
		if default_font:
			root.theme.default_font = default_font
			print("[UITheme] ✅ Applied Inter font to root theme")

		# Set tooltip panel style
		root.theme.set_stylebox("panel", "TooltipPanel", tooltip_style)

		# Set tooltip label colors for better readability
		root.theme.set_color("font_color", "TooltipLabel", TEXT_COLOR)
		root.theme.set_font_size("font_size", "TooltipLabel", 12)
