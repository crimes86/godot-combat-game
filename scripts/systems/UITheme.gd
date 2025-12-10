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

func _ready() -> void:
	# Defer tooltip styling until tree is ready
	call_deferred("_apply_tooltip_theme")

func _apply_tooltip_theme() -> void:
	"""Apply opaque tooltip styling to the project theme"""
	var tooltip_style = create_tooltip_style()

	# Create a theme and apply to root viewport
	var root = get_tree().root if get_tree() else null
	if root:
		if root.theme == null:
			root.theme = Theme.new()

		# Set tooltip panel style
		root.theme.set_stylebox("panel", "TooltipPanel", tooltip_style)

		# Set tooltip label colors for better readability
		root.theme.set_color("font_color", "TooltipLabel", TEXT_COLOR)
		root.theme.set_font_size("font_size", "TooltipLabel", 12)
