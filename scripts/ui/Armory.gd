extends Control
## Armory - Staging area between authentication and game world
## Shows player's character, equipped cosmetics, achievements, and forged items

signal entered_world
signal back_to_menu

enum ArmoryState { GUEST, NEW_PLAYER, CASUAL, VETERAN, PENDING_UNLOCKS }

# Animation state
var _shimmer_tween: Tween = null
var _badge_tween: Tween = null
var _progress_tween: Tween = null
var _count_tween: Tween = null
var _target_achievement_count: int = 0
var _load_complete: bool = false

# UI References
var character_preview: Control = null
var stats_panel: Control = null
var cosmetics_panel: Control = null
var achievements_panel: Control = null
var forged_panel: Control = null
var enter_world_button: Button = null
var logout_button: Button = null
var settings_panel: Control = null

# Settings panel controls
var master_volume_slider: HSlider = null
var music_volume_slider: HSlider = null
var sfx_volume_slider: HSlider = null
var fullscreen_check: CheckBox = null

# Labels
var title_label: Label = null
var subtitle_label: Label = null
var username_label: Label = null
var tier_badge: Control = null
var tier_label: Label = null
var total_label: Label = null

# State
var current_state: ArmoryState = ArmoryState.GUEST
var profile: Dictionary = {}

# Forge detail panel
var _forge_detail_panel: Control = null
var _forge_selected_item: Dictionary = {}
var _forge_selected_card: PanelContainer = null  # Currently selected card in forge grid

# Theme colors - Simplified palette for consistency
# Background layers
const BG_DARK = Color(0.02, 0.02, 0.025)       # Darkest background
const CARD_BG = Color(0.06, 0.08, 0.10, 0.95)  # Panel background - matches MainMenu
const CARD_BORDER = Color(0.10, 0.11, 0.12)    # Subtle borders (internal use)
const BORDER_GLOW = Color(0.0, 0.6, 0.7, 0.6)  # Cyan glow border - matches MainMenu
const SHADOW_GLOW = Color(0, 0.5, 0.6, 0.25)   # Cyan shadow for panels

# Text hierarchy (high contrast for readability)
const TEXT_PRIMARY = Color(0.95, 0.95, 0.97)   # Main text - almost white
const TEXT_SECONDARY = Color(0.70, 0.72, 0.75) # Secondary info
const TEXT_DIM = Color(0.45, 0.47, 0.50)       # Labels, hints

# Typography scale (standardized sizes) - scaled up for readability
const FONT_H1 = 42        # Page title (MANTLE ARMORY)
const FONT_H2 = 28        # Column headers (THE FORGE, DREADLAND)
const FONT_H3 = 22        # Section headers (CONNECTED PLATFORMS)
const FONT_BODY_LG = 24   # Large body text, important values
const FONT_BODY = 20      # Normal body text
const FONT_CAPTION = 18   # Captions, small labels
const FONT_TINY = 16      # Smallest text (tooltips, hints)

# Brand colors (use sparingly)
const MANTLE_RED = Color(0.95, 0.25, 0.25)     # Primary accent - titles, important numbers
const MANTLE_CYAN = Color(0.0, 0.75, 0.85)     # Secondary accent - headers, interactive

# Font
var default_font: Font = null

# Tier colors
const TIER_COLORS = {
	"initiate": Color("#666666"),
	"bronze": Color("#cd7f32"),
	"silver": Color("#c0c0c0"),
	"gold": Color("#ffd700"),
	"platinum": Color("#e5e4e2"),
	"diamond": Color("#b9f2ff"),
	"legendary": Color("#ff6600"),
	"mythic": Color("#ff00ff")
}

# Rarity colors
const RARITY_COLORS = {
	"Common": Color("#9d9d9d"),
	"Uncommon": Color("#1eff00"),
	"Rare": Color("#0070dd"),
	"Epic": Color("#a335ee"),
	"Legendary": Color("#ff8000")
}

# Provider colors
const PROVIDER_COLORS = {
	"steam": Color("#1b5579"),  # Darker Steam blue
	"battlenet": Color("#ffb932"),
	"xbox": Color("#107C10"),  # Xbox green (official)
	"playstation": Color("#006FCD"),  # PlayStation blue (official)
	"psn": Color("#006FCD"),  # PSN alias
	"discord": Color("#5865F2"),
	"epic": Color("#2a2a2a"),  # Epic Games dark
	"gog": Color("#a033b8"),  # GOG purple
	"facebook": Color("#1877F2"),  # Facebook blue (official)
	"roblox": Color("#E2231A")  # Roblox red (official)
}

# Forge Catalog - All available forge items with real asset data
# Icons at: res://assets/icons/forged/[category]/[name].png
# NOTE: IDs must match backend items.json item_id values exactly
const FORGE_CATALOG = [
	# === WEAPONS (14) - Matching backend items.json ===
	{"id": "coiled_sword", "name": "Coiled Sword", "game": "Dark Souls III", "achievement": "The Dark Soul",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/coiled_sword.png",
	 "lore": "A twisted blade born from the First Flame. Its embers still smolder with primordial fire."},
	{"id": "farron_greatsword", "name": "Farron Greatsword", "game": "Dark Souls III", "achievement": "Abyss Watchers",
	 "rarity": "Epic", "category": "weapons", "icon": "res://assets/icons/forged/weapons/farron_greatsword.png",
	 "lore": "Wielded by those who linked the fire long ago. Paired with a dagger for acrobatic combat."},
	{"id": "dragonslayer_swordspear", "name": "Dragonslayer Swordspear", "game": "Dark Souls III", "achievement": "Nameless King",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/dragonslayer_swordspear.png",
	 "lore": "Cross-spear of the exiled god who betrayed his kin to ally with dragons."},
	{"id": "grafted_blade", "name": "Grafted Blade Greatsword", "game": "Elden Ring", "achievement": "Godrick the Grafted",
	 "rarity": "Rare", "category": "weapons", "icon": "res://assets/icons/forged/weapons/grafted_blade.png",
	 "lore": "A greatsword made of many weapons grafted together. Symbol of Godrick's obsession."},
	{"id": "hand_of_malenia", "name": "Hand of Malenia", "game": "Elden Ring", "achievement": "Malenia, Blade of Miquella",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/hand_of_malenia.png",
	 "lore": "Prosthetic blade arm of the Scarlet Valkyrie. I am Malenia, and I have never known defeat."},
	{"id": "radahns_greatswords", "name": "Starscourge Greatswords", "game": "Elden Ring", "achievement": "Starscourge Radahn",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/radahns_greatswords.png",
	 "lore": "Twin colossal swords of the Starscourge. He held back the stars for Miquella's sake."},
	{"id": "moonveil", "name": "Moonveil", "game": "Elden Ring", "achievement": "Legend",
	 "rarity": "Epic", "category": "weapons", "icon": "res://assets/icons/forged/weapons/moonveil.png",
	 "lore": "A katana that channels moonlight magic. Imbued with Carian sorcery."},
	{"id": "pure_nail", "name": "Pure Nail", "game": "Hollow Knight", "achievement": "Completion",
	 "rarity": "Rare", "category": "weapons", "icon": "res://assets/icons/forged/weapons/pure_nail.png",
	 "lore": "A perfectly honed nail, forged in Hallownest's pale light."},
	{"id": "stygian_blade", "name": "Stygian Blade", "game": "Hades", "achievement": "Complete",
	 "rarity": "Rare", "category": "weapons", "icon": "res://assets/icons/forged/weapons/stygian_blade.png",
	 "lore": "First weapon of Prince Zagreus. Forged in the River Styx itself."},
	{"id": "adamant_rail", "name": "Adamant Rail", "game": "Hades", "achievement": "Speed Run",
	 "rarity": "Rare", "category": "weapons", "icon": "res://assets/icons/forged/weapons/adamant_rail.png",
	 "lore": "An exalted weapon of unknown origin. Its mechanisms are beyond mortal understanding."},
	{"id": "terra_blade", "name": "Terra Blade", "game": "Terraria", "achievement": "Champion of Terraria",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/terra_blade.png",
	 "lore": "Fused from blades of light and dark. Its projectiles cut through the void itself."},
	{"id": "mortal_blade", "name": "Mortal Blade", "game": "Sekiro", "achievement": "Immortal Severance",
	 "rarity": "Legendary", "category": "weapons", "icon": "res://assets/icons/forged/weapons/mortal_blade.png",
	 "lore": "The crimson blade that can sever immortality itself. Its edge cuts even the divine."},
	{"id": "gyoubu_spear", "name": "Gyoubu's Broken Horn", "game": "Sekiro", "achievement": "Shura",
	 "rarity": "Epic", "category": "weapons", "icon": "res://assets/icons/forged/weapons/gyoubu_spear.png",
	 "lore": "AS I BREATHE, YOU WILL NOT PASS THE CASTLE GATE! The demon general's polearm."},
	{"id": "witcher_silver_sword", "name": "Witcher's Silver Sword", "game": "The Witcher 3", "achievement": "Geralt the Professional",
	 "rarity": "Rare", "category": "weapons", "icon": "res://assets/icons/forged/weapons/witcher_silver_sword.png",
	 "lore": "Silver for monsters. A witcher's specialized tool against the supernatural."},
	# === ARMOR (3) ===
	{"id": "elden_lord_crown", "name": "Elden Lord's Crown", "game": "Elden Ring", "achievement": "Elden Lord",
	 "rarity": "Legendary", "category": "armor", "icon": "res://assets/icons/forged/armor/elden_lord.png",
	 "lore": "Crown of the one who claimed the Elden Ring and became Lord of the Lands Between."},
	{"id": "carian_crown", "name": "Carian Royal Crown", "game": "Elden Ring", "achievement": "Rennala, Queen of the Full Moon",
	 "rarity": "Epic", "category": "armor", "icon": "res://assets/icons/forged/armor/carian_crown.png",
	 "lore": "Crown of Carian royalty, enchanted by the moon's sorcery."},
	{"id": "straw_hat", "name": "Farmer's Straw Hat", "game": "Stardew Valley", "achievement": "Legend",
	 "rarity": "Rare", "category": "armor", "icon": "res://assets/icons/forged/armor/straw_hat.png",
	 "lore": "Simple hat for a simple life. Grandpa would be proud."},
	# === SHIELDS (1) ===
	{"id": "eye_shield", "name": "Fingerprint Stone Shield", "game": "Elden Ring", "achievement": "Mohg, the Omen",
	 "rarity": "Epic", "category": "shields", "icon": "res://assets/icons/forged/shields/eye_shield.png",
	 "lore": "A greatshield bearing a mysterious eye. It watches all who would challenge its bearer."},
	# === CAPES (1) ===
	{"id": "shade_cloak", "name": "Shade Cloak", "game": "Hollow Knight", "achievement": "Void",
	 "rarity": "Epic", "category": "capes", "icon": "res://assets/icons/forged/capes/shade_cloak.png",
	 "lore": "A cloak woven from pure void. Allows passage through shadow."},
	# === ACCESSORIES (4) ===
	{"id": "coiled_sword_fragment", "name": "Coiled Sword Fragment", "game": "Dark Souls III", "achievement": "Iudex Gundyr",
	 "rarity": "Epic", "category": "accessories", "icon": "res://assets/icons/forged/accessories/coiled_sword_fragment.png",
	 "lore": "A shard from the First Flame's bonfire. Warps back to the last checkpoint."},
	{"id": "margits_shackle", "name": "Margit's Shackle", "game": "Elden Ring", "achievement": "Margit, the Fell Omen",
	 "rarity": "Rare", "category": "accessories", "icon": "res://assets/icons/forged/accessories/margits_shackle.png",
	 "lore": "Put these foolish ambitions to rest. A shackle that binds the omen."},
	{"id": "discord_nitro_badge", "name": "Nitro Supporter Badge", "game": "Discord", "achievement": "Nitro Subscriber",
	 "rarity": "Rare", "category": "accessories", "icon": "res://assets/icons/forged/accessories/discord_nitro_badge.png",
	 "lore": "A badge showing Nitro support. Granted to Discord Nitro subscribers."},
	{"id": "github_star_badge", "name": "Stargazer Badge", "game": "GitHub", "achievement": "Starstruck",
	 "rarity": "Rare", "category": "accessories", "icon": "res://assets/icons/forged/accessories/github_star_badge.png",
	 "lore": "A badge for repository stargazers. Earned by starring many repositories."},
]

# Current forge tab
var _forge_current_tab: String = "all"
var _forge_tab_buttons: Dictionary = {}
var _forge_content_container: Control = null

# Forge filter/sort state
var _forge_sort_by: String = "rarity"  # rarity, game, type
var _forge_filter_buttons: Dictionary = {}


func _ready() -> void:
	_setup_font()
	_build_ui()
	_apply_font_to_all(self)  # Apply font to all Labels and Buttons
	_determine_state()
	_setup_ui_for_state()
	_apply_font_to_all(self)  # Re-apply after dynamic content is created

	# Debug: Check actual colors after everything is set up
	call_deferred("_debug_check_colors")

	# Listen for profile updates (important for restored sessions)
	if MantleAuth:
		if not MantleAuth.profile_updated.is_connected(_on_profile_updated):
			MantleAuth.profile_updated.connect(_on_profile_updated)
		if not MantleAuth.auth_completed.is_connected(_on_profile_updated):
			MantleAuth.auth_completed.connect(_on_profile_updated)

		# If profile data already loaded, refresh immediately
		if MantleAuth.providers.size() > 0:
			print("[Armory] Profile data already available, refreshing...")
			call_deferred("_on_profile_updated", {})

	# Listen for forged items loaded to refresh forge display
	if ForgeItemManager:
		if not ForgeItemManager.forged_items_loaded.is_connected(_on_forged_items_loaded):
			ForgeItemManager.forged_items_loaded.connect(_on_forged_items_loaded)
		# If already loaded, refresh now
		if ForgeItemManager.is_loaded():
			print("[Armory] Forged items already loaded, refreshing forge...")
			call_deferred("_refresh_forge_content")

	# Start entrance animations after a brief delay
	await get_tree().create_timer(0.1).timeout
	_play_entrance_animations()


func _on_profile_updated(_data: Dictionary) -> void:
	"""Called when MantleAuth receives profile data - refresh the UI"""
	print("[Armory] Profile updated signal received!")
	print("[Armory] Providers from MantleAuth: ", MantleAuth.providers)
	print("[Armory] Total achievements: ", MantleAuth.total_achievements)
	_determine_state()
	_setup_ui_for_state()
	_apply_font_to_all(self)
	print("[Armory] UI refreshed with new profile data")

func _on_forged_items_loaded(items: Array) -> void:
	"""Called when ForgeItemManager finishes loading forged items"""
	print("[Armory] ═══════════════════════════════════════")
	print("[Armory] Forged items loaded: %d total" % items.size())
	_refresh_forge_content()
	print("[Armory] ═══════════════════════════════════════")

func _on_forge_data_changed() -> void:
	"""Called when forge data changes (from ForgeItemManager) to update the grid"""
	if _forge_content_container:
		print("[Forge] Refreshing forge content")
		_refresh_forge_content()

func _setup_font() -> void:
	# Use SystemFont which works on all platforms
	default_font = SystemFont.new()
	default_font.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "sans-serif"])
	default_font.antialiasing = TextServer.FONT_ANTIALIASING_LCD

func _create_label(text_content: String, font_size: int = 14, color: Color = TEXT_PRIMARY) -> Label:
	var label = Label.new()
	label.text = text_content
	label.add_theme_font_override("font", default_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _create_section_divider() -> Control:
	"""Create a visible horizontal divider line for separating sections"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(0, 20)

	var line = ColorRect.new()
	line.color = Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.2)  # Cyan tinted, more visible
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.anchor_top = 0.0
	line.anchor_bottom = 0.0
	line.anchor_left = 0.05  # 5% margin on each side (wider line)
	line.anchor_right = 0.95
	line.offset_top = 2
	line.offset_bottom = 3
	container.add_child(line)

	return container

# ═══════════════════════════════════════════════════════════════════════════════
# GAMEY UI POLISH - Enhanced visual effects for left column
# ═══════════════════════════════════════════════════════════════════════════════

func _create_animated_grid_bg() -> Control:
	"""Create a subtle grid pattern overlay matching the web app aesthetic"""
	var container = Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Grid settings (matching web app: 80px spacing, cyan at 0.05 opacity)
	var grid_spacing = 60  # Slightly smaller for the panel size
	var line_color = Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.04)
	var line_thickness = 1

	# We'll add the grid lines when the container is ready
	container.ready.connect(func():
		var panel_size = container.size
		if panel_size.x <= 0 or panel_size.y <= 0:
			return

		# Vertical lines
		var x = grid_spacing
		while x < panel_size.x:
			var vline = ColorRect.new()
			vline.color = line_color
			vline.position = Vector2(x, 0)
			vline.size = Vector2(line_thickness, panel_size.y)
			vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(vline)
			x += grid_spacing

		# Horizontal lines
		var y = grid_spacing
		while y < panel_size.y:
			var hline = ColorRect.new()
			hline.color = line_color
			hline.position = Vector2(0, y)
			hline.size = Vector2(panel_size.x, line_thickness)
			hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(hline)
			y += grid_spacing
	)

	return container

func _create_glowing_divider() -> Control:
	"""Create a subtle horizontal divider - simplified"""
	var container = Control.new()
	container.custom_minimum_size = Vector2(0, 12)

	# Simple thin line
	var line = ColorRect.new()
	line.color = Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.15)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.anchor_left = 0.1
	line.anchor_right = 0.9
	line.offset_top = -0.5
	line.offset_bottom = 0.5
	container.add_child(line)

	return container

func _create_player_identity_frame() -> Control:
	"""Create clean player identity section"""
	var frame = VBoxContainer.new()
	frame.name = "IdentityFrame"
	frame.add_theme_constant_override("separation", 8)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 6)
	frame.add_child(inner_vbox)

	# Player ID (prominent)
	username_label = Label.new()
	username_label.name = "UsernameLabel"
	username_label.text = "Player"
	username_label.add_theme_font_override("font", default_font)
	username_label.add_theme_font_size_override("font_size", FONT_H2)
	username_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	username_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(username_label)

	# Tier Badge with pulsing glow
	var badge_center = CenterContainer.new()
	inner_vbox.add_child(badge_center)
	tier_badge = _create_enhanced_tier_badge("initiate")
	badge_center.add_child(tier_badge)

	return frame

func _create_enhanced_tier_badge(tier_key: String) -> Control:
	"""Create tier badge with pulsing glow effect"""
	var container = Control.new()
	container.name = "TierBadgeContainer"
	container.custom_minimum_size = Vector2(120, 36)

	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	# Outer glow layer (animated)
	var glow_panel = PanelContainer.new()
	glow_panel.name = "BadgeGlow"
	glow_panel.set_anchors_preset(Control.PRESET_CENTER)
	glow_panel.offset_left = -60
	glow_panel.offset_right = 60
	glow_panel.offset_top = -18
	glow_panel.offset_bottom = 18
	var glow_style = StyleBoxFlat.new()
	glow_style.bg_color = Color(color.r, color.g, color.b, 0.2)
	glow_style.set_corner_radius_all(8)
	glow_style.shadow_color = Color(color.r, color.g, color.b, 0.5)
	glow_style.shadow_size = 16
	glow_panel.add_theme_stylebox_override("panel", glow_style)
	container.add_child(glow_panel)

	# Main badge
	var badge = PanelContainer.new()
	badge.name = "TierBadgePanel"
	badge.set_anchors_preset(Control.PRESET_CENTER)
	badge.offset_left = -55
	badge.offset_right = 55
	badge.offset_top = -14
	badge.offset_bottom = 14

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	# Metallic highlight on top edge
	style.border_color = color.lightened(0.4)
	style.border_width_top = 2
	style.border_width_bottom = 0
	style.border_width_left = 1
	style.border_width_right = 1
	badge.add_theme_stylebox_override("panel", style)
	badge.set_meta("style", style)
	badge.set_meta("glow_style", glow_style)
	badge.set_meta("base_color", color)
	container.add_child(badge)

	tier_label = Label.new()
	tier_label.name = "TierLabel"
	tier_label.text = tier_key.to_upper()
	tier_label.add_theme_font_override("font", default_font)
	tier_label.add_theme_font_size_override("font_size", FONT_BODY)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Dark text for light tiers
	if tier_key in ["gold", "silver", "platinum", "diamond"]:
		tier_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	else:
		tier_label.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(tier_label)

	# Start pulsing animation
	_start_badge_pulse(container, color)

	return container

func _start_badge_pulse(badge_container: Control, color: Color) -> void:
	"""Start subtle pulsing glow animation on tier badge"""
	var tween = create_tween()
	tween.set_loops()

	var glow_panel = badge_container.find_child("BadgeGlow", false, false)
	if glow_panel:
		# Pulse the shadow size
		tween.tween_method(func(val: float):
			var style = glow_panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.shadow_size = int(val)
				style.shadow_color = Color(color.r, color.g, color.b, 0.3 + (val - 12) * 0.02)
		, 12.0, 20.0, 1.5)
		tween.tween_method(func(val: float):
			var style = glow_panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style:
				style.shadow_size = int(val)
				style.shadow_color = Color(color.r, color.g, color.b, 0.3 + (val - 12) * 0.02)
		, 20.0, 12.0, 1.5)

func _create_trophy_plaque() -> Control:
	"""Create achievement score display - clean version"""
	var plaque = VBoxContainer.new()
	plaque.add_theme_constant_override("separation", 4)

	var inner_content = VBoxContainer.new()
	inner_content.add_theme_constant_override("separation", 0)
	plaque.add_child(inner_content)

	# Hero number with glow effect container
	var number_container = CenterContainer.new()
	number_container.name = "NumberContainer"
	inner_content.add_child(number_container)

	var number_stack = Control.new()
	number_stack.custom_minimum_size = Vector2(180, 70)
	number_container.add_child(number_stack)

	# Glow layer behind number
	var glow_label = Label.new()
	glow_label.name = "NumberGlow"
	glow_label.text = "0"
	glow_label.add_theme_font_override("font", default_font)
	glow_label.add_theme_font_size_override("font_size", 64)
	glow_label.add_theme_color_override("font_color", Color(MANTLE_RED.r, MANTLE_RED.g, MANTLE_RED.b, 0.3))
	glow_label.set_anchors_preset(Control.PRESET_CENTER)
	glow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glow_label.offset_left = -90
	glow_label.offset_right = 90
	glow_label.offset_top = -35
	glow_label.offset_bottom = 35
	number_stack.add_child(glow_label)

	# Main number
	total_label = Label.new()
	total_label.name = "TotalLabel"
	total_label.text = "0"
	total_label.add_theme_font_override("font", default_font)
	total_label.add_theme_font_size_override("font_size", 64)
	total_label.add_theme_color_override("font_color", MANTLE_RED)
	total_label.set_anchors_preset(Control.PRESET_CENTER)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_label.offset_left = -90
	total_label.offset_right = 90
	total_label.offset_top = -35
	total_label.offset_bottom = 35
	number_stack.add_child(total_label)

	# "ACHIEVEMENTS" suffix
	var suffix_center = CenterContainer.new()
	inner_content.add_child(suffix_center)
	var ach_suffix = Label.new()
	ach_suffix.name = "TotalSuffix"
	ach_suffix.text = "ACHIEVEMENTS"
	ach_suffix.add_theme_font_override("font", default_font)
	ach_suffix.add_theme_font_size_override("font_size", FONT_TINY)
	ach_suffix.add_theme_color_override("font_color", TEXT_DIM)
	suffix_center.add_child(ach_suffix)

	return plaque

func _create_enhanced_progress_section() -> Control:
	"""Enhanced progress bar with tier emblems and glow effects"""
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	# Tier transition row with emblems
	var tier_row = HBoxContainer.new()
	tier_row.name = "TierTransitionRow"
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_theme_constant_override("separation", 8)
	section.add_child(tier_row)

	# Current tier emblem
	var current_emblem = _create_tier_emblem("initiate", true)
	current_emblem.name = "CurrentTierEmblem"
	tier_row.add_child(current_emblem)

	# Arrow with animation potential
	var arrow_container = CenterContainer.new()
	tier_row.add_child(arrow_container)
	var arrow = Label.new()
	arrow.name = "ProgressArrow"
	arrow.text = "→"
	arrow.add_theme_font_override("font", default_font)
	arrow.add_theme_font_size_override("font_size", FONT_H3)
	arrow.add_theme_color_override("font_color", Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.6))
	arrow_container.add_child(arrow)

	# Next tier emblem
	var next_emblem = _create_tier_emblem("bronze", false)
	next_emblem.name = "NextTierEmblem"
	tier_row.add_child(next_emblem)

	# Progress bar - clean version
	var bar_container = Control.new()
	bar_container.name = "ProgressBarContainer"
	bar_container.custom_minimum_size = Vector2(0, 16)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(bar_container)

	# Simple dark background for progress bar
	var bar_bg = ColorRect.new()
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.color = Color(0.05, 0.06, 0.08)
	bar_container.add_child(bar_bg)

	# Progress bar
	var progress_bar = ProgressBar.new()
	progress_bar.name = "TierProgressBar"
	progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_bar.offset_left = 2
	progress_bar.offset_right = -2
	progress_bar.offset_top = 2
	progress_bar.offset_bottom = -2
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false

	# Transparent background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	progress_bar.add_theme_stylebox_override("background", bg_style)

	# Clean fill style
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = TIER_COLORS["initiate"]
	fill_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	progress_bar.set_meta("fill_style", fill_style)

	bar_container.add_child(progress_bar)

	# Progress text - simple label
	var progress_center = CenterContainer.new()
	section.add_child(progress_center)

	var progress_text = Label.new()
	progress_text.name = "ProgressText"
	progress_text.text = "0 / 100 to Bronze"
	progress_text.add_theme_font_override("font", default_font)
	progress_text.add_theme_font_size_override("font_size", FONT_CAPTION)
	progress_text.add_theme_color_override("font_color", TEXT_SECONDARY)
	progress_center.add_child(progress_text)

	return section

func _create_tier_emblem(tier_key: String, is_current: bool) -> Control:
	"""Create a simple tier label"""
	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	var label = Label.new()
	label.name = "EmblemLabel"
	label.text = tier_key.capitalize()
	label.add_theme_font_override("font", default_font)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color", color if is_current else color.darkened(0.3))
	label.set_meta("tier_key", tier_key)

	return label

func _update_tier_emblem(emblem: Control, tier_key: String, is_current: bool) -> void:
	"""Update an existing tier emblem with new tier data"""
	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	# Emblem is now just a Label directly
	if emblem is Label:
		emblem.text = tier_key.capitalize()
		emblem.add_theme_color_override("font_color", color if is_current else color.darkened(0.3))
		emblem.set_meta("tier_key", tier_key)

func _apply_font_to_all(node: Node) -> void:
	"""Recursively apply font to all Labels and Buttons"""
	if node is Label:
		node.add_theme_font_override("font", default_font)
	elif node is Button:
		node.add_theme_font_override("font", default_font)
	for child in node.get_children():
		_apply_font_to_all(child)

func _debug_check_colors() -> void:
	"""Debug: Check actual ColorRect colors after UI is built"""
	print("[Armory] ═══════════════════════════════════════")
	print("[Armory] DEFERRED COLOR CHECK (actual values):")

	var left_bg = find_child("LeftColumnBG", true, false)
	if left_bg and left_bg is ColorRect:
		print("[Armory]   LEFT column ColorRect: ", left_bg.color)
	else:
		print("[Armory]   LEFT column ColorRect: NOT FOUND")

	var middle_bg = find_child("ForgeBG", true, false)
	if middle_bg and middle_bg is ColorRect:
		print("[Armory]   MIDDLE column ColorRect: ", middle_bg.color)
	else:
		print("[Armory]   MIDDLE column ColorRect: NOT FOUND")

	var right_bg = find_child("RightColumnBG", true, false)
	if right_bg and right_bg is ColorRect:
		print("[Armory]   RIGHT column ColorRect: ", right_bg.color)
	else:
		print("[Armory]   RIGHT column ColorRect: NOT FOUND")

	print("[Armory] ═══════════════════════════════════════")

# ═══════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	print("[Armory] ═══════════════════════════════════════")
	print("[Armory] Building UI with colors:")
	print("[Armory]   BG_DARK: ", BG_DARK)
	print("[Armory]   CARD_BG: ", CARD_BG)
	print("[Armory]   CARD_BORDER: ", CARD_BORDER)
	print("[Armory] ═══════════════════════════════════════")

	# Dark background
	var bg = ColorRect.new()
	bg.color = BG_DARK
	print("[Armory] Main background set to BG_DARK: ", bg.color)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# Header (title only)
	_build_header(main_vbox)

	# Content area (fills available space)
	var content_margin = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 40)
	content_margin.add_theme_constant_override("margin_right", 40)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_bottom", 20)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_margin)

	# Three-column layout - all columns expand proportionally
	var columns = HBoxContainer.new()
	columns.name = "ColumnsContainer"
	columns.add_theme_constant_override("separation", 30)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(columns)

	# LEFT column: MANTLE STATS - expands proportionally
	var left_column = _build_mantle_stats_column()
	left_column.name = "LeftColumn"
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.size_flags_stretch_ratio = 1.0  # Equal ratio
	columns.add_child(left_column)

	# MIDDLE column: DREADLAND - expands proportionally (slightly larger)
	var middle_column = _build_dreadland_column()
	middle_column.name = "MiddleColumn"
	middle_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle_column.size_flags_stretch_ratio = 1.3  # Slightly wider
	columns.add_child(middle_column)

	# RIGHT column: THE FORGE - expands proportionally
	var right_column = _build_forge_column()
	right_column.name = "RightColumn"
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.size_flags_stretch_ratio = 1.0  # Equal ratio
	columns.add_child(right_column)

	# Footer spacer
	_build_footer(main_vbox)

	# Settings panel overlay (hidden by default)
	_build_settings_panel()

# ═══════════════════════════════════════════════════════════════════════════════
# THREE-COLUMN LAYOUT
# ═══════════════════════════════════════════════════════════════════════════════

func _build_mantle_stats_column() -> Control:
	"""LEFT COLUMN: Mantle Stats - providers, rarity, achievements, tier, progress"""
	print("[Armory] Building LEFT column with CARD_BG: ", CARD_BG)
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(220, 0)

	# Background with subtle gradient
	var bg = ColorRect.new()
	bg.name = "LeftColumnBG"
	bg.color = CARD_BG
	print("[Armory] LEFT column bg.color set to: ", bg.color)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(bg)

	# Animated grid background effect
	var grid_overlay = _create_animated_grid_bg()
	grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(grid_overlay)

	# Border overlay with cyan glow (matches MainMenu)
	var border = PanelContainer.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = BORDER_GLOW
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(8)
	border_style.shadow_size = 20
	border_style.shadow_color = SHADOW_GLOW
	border.add_theme_stylebox_override("panel", border_style)
	wrapper.add_child(border)

	# Content margin - tighter spacing
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	wrapper.add_child(margin)

	# Main vertical container - spread content evenly
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)  # We'll use spacers instead
	margin.add_child(vbox)

	# ═══════════════════════════════════════════════════════════════════════════
	# PLAYER IDENTITY FRAME - Decorative rank frame around player ID + badge
	# ═══════════════════════════════════════════════════════════════════════════
	var identity_frame = _create_player_identity_frame()
	vbox.add_child(identity_frame)

	# ═══════════════════════════════════════════════════════════════════════════
	# ACHIEVEMENT TROPHY PLAQUE - Hero number with metallic frame
	# ═══════════════════════════════════════════════════════════════════════════
	var trophy_plaque = _create_trophy_plaque()
	trophy_plaque.name = "TrophyPlaque"
	vbox.add_child(trophy_plaque)

	# ═══════════════════════════════════════════════════════════════════════════
	# TIER PROGRESS - Enhanced progress bar with emblems
	# ═══════════════════════════════════════════════════════════════════════════
	var progress_section = _create_enhanced_progress_section()
	progress_section.name = "ProgressSection"
	vbox.add_child(progress_section)

	# Flexible spacer to distribute sections evenly
	var spacer1 = Control.new()
	spacer1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer1)

	# Connected Providers with names
	var providers_section = VBoxContainer.new()
	providers_section.add_theme_constant_override("separation", 8)
	vbox.add_child(providers_section)

	var providers_header = Label.new()
	providers_header.text = "CONNECTED PLATFORMS"
	providers_header.add_theme_font_override("font", default_font)
	providers_header.add_theme_font_size_override("font_size", FONT_TINY)
	providers_header.add_theme_color_override("font_color", TEXT_DIM)
	providers_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	providers_section.add_child(providers_header)

	var platforms_row = HBoxContainer.new()
	platforms_row.name = "PlatformsRow"
	platforms_row.add_theme_constant_override("separation", 16)
	platforms_row.alignment = BoxContainer.ALIGNMENT_CENTER
	providers_section.add_child(platforms_row)

	var no_platforms = Label.new()
	no_platforms.name = "NoPlatformsLabel"
	no_platforms.text = "No platforms linked"
	no_platforms.add_theme_font_override("font", default_font)
	no_platforms.add_theme_font_size_override("font_size", FONT_CAPTION)
	no_platforms.add_theme_color_override("font_color", TEXT_SECONDARY)
	platforms_row.add_child(no_platforms)

	# Flexible spacer between platforms and rarity
	var spacer2 = Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)

	# Rarity Breakdown (larger, with labels)
	var rarity_section = VBoxContainer.new()
	rarity_section.add_theme_constant_override("separation", 10)
	vbox.add_child(rarity_section)

	var rarity_header = Label.new()
	rarity_header.text = "ACHIEVEMENTS BY RARITY"
	rarity_header.add_theme_font_override("font", default_font)
	rarity_header.add_theme_font_size_override("font_size", FONT_TINY)
	rarity_header.add_theme_color_override("font_color", TEXT_DIM)
	rarity_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_section.add_child(rarity_header)

	var rarity_row = HBoxContainer.new()
	rarity_row.name = "RarityRow"
	rarity_row.add_theme_constant_override("separation", 6)  # Tighter spacing for pill chips
	rarity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rarity_section.add_child(rarity_row)

	# Flexible spacer between rarity and recent unlocks
	var spacer3 = Control.new()
	spacer3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer3)

	# === RECENT ACHIEVEMENTS SECTION ===
	var recent_section = VBoxContainer.new()
	recent_section.name = "RecentAchievementsSection"
	recent_section.add_theme_constant_override("separation", 6)
	vbox.add_child(recent_section)

	var recent_header = Label.new()
	recent_header.text = "RECENT UNLOCKS"
	recent_header.add_theme_font_override("font", default_font)
	recent_header.add_theme_font_size_override("font_size", FONT_TINY)
	recent_header.add_theme_color_override("font_color", TEXT_DIM)
	recent_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recent_section.add_child(recent_header)

	var recent_list = VBoxContainer.new()
	recent_list.name = "RecentAchievementsList"
	recent_list.add_theme_constant_override("separation", 4)
	recent_section.add_child(recent_list)

	# Placeholder for recent achievements (will be populated by _update_recent_achievements)
	for i in range(3):
		var ach_row = _create_recent_achievement_row("---", "---", "Common")
		ach_row.name = "RecentAch_%d" % i
		ach_row.visible = false  # Hidden until populated
		recent_list.add_child(ach_row)

	# Bottom spacer to balance vertical distribution
	var spacer4 = Control.new()
	spacer4.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer4)

	# Store reference for tier styling
	stats_panel = wrapper

	return wrapper

func _create_recent_achievement_row(title: String, game: String, rarity: String, timestamp: String = "") -> Control:
	"""Create a compact row for a recent achievement"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.tooltip_text = "%s rarity" % rarity  # Tooltip shows rarity name

	# Left spacer for centering
	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_spacer)

	# Rarity indicator dot - 2x bigger
	var dot = Label.new()
	dot.name = "RarityDot"
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 24)  # 2x bigger (was 14)
	var rarity_color = RARITY_COLORS.get(rarity, Color.GRAY)
	dot.add_theme_color_override("font_color", rarity_color)
	row.add_child(dot)

	# Achievement info
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)

	# Title row with timestamp
	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	info.add_child(title_row)

	var title_label = Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", FONT_TINY)
	title_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	title_row.add_child(title_label)

	if timestamp != "":
		var time_label = Label.new()
		time_label.name = "Timestamp"
		time_label.text = timestamp
		time_label.add_theme_font_size_override("font_size", 11)
		time_label.add_theme_color_override("font_color", TEXT_DIM.darkened(0.2))
		title_row.add_child(time_label)

	var game_label = Label.new()
	game_label.name = "Game"
	game_label.text = game
	game_label.add_theme_font_size_override("font_size", 12)
	game_label.add_theme_color_override("font_color", TEXT_DIM)
	info.add_child(game_label)

	# Right spacer for centering
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_spacer)

	return row

func _populate_recent_unlocks() -> void:
	"""Populate the Recent Unlocks section with demo achievement data"""
	var recent_list = stats_panel.find_child("RecentAchievementsList", true, false)
	if not recent_list:
		return

	# Clear existing placeholder rows
	for child in recent_list.get_children():
		child.queue_free()

	# Demo achievements to display - mix of rarities, games, and timestamps
	var demo_achievements = [
		{"title": "Dragon Slayer", "game": "Skyrim", "rarity": "Legendary", "time": "2h ago"},
		{"title": "First Blood", "game": "Counter-Strike 2", "rarity": "Rare", "time": "1d ago"},
		{"title": "Speed Demon", "game": "Portal 2", "rarity": "Epic", "time": "3d ago"},
	]

	# Create fresh rows with all data including timestamps
	for ach in demo_achievements:
		var row = _create_recent_achievement_row(ach.title, ach.game, ach.rarity, ach.time)
		recent_list.add_child(row)

func _create_compact_progress_section() -> Control:
	"""Progress bar for tier advancement - prominent version"""
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)

	# Current tier → Next tier label (removed redundant "TIER PROGRESS" header)
	var tier_row = HBoxContainer.new()
	tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tier_row.add_theme_constant_override("separation", 12)
	section.add_child(tier_row)

	var current_tier = Label.new()
	current_tier.name = "CurrentTierLabel"
	current_tier.text = "Initiate"
	current_tier.add_theme_font_override("font", default_font)
	current_tier.add_theme_font_size_override("font_size", FONT_BODY)
	current_tier.add_theme_color_override("font_color", TIER_COLORS["initiate"])
	tier_row.add_child(current_tier)

	var arrow = Label.new()
	arrow.text = "→"
	arrow.add_theme_font_override("font", default_font)
	arrow.add_theme_font_size_override("font_size", FONT_BODY)
	arrow.add_theme_color_override("font_color", TEXT_DIM)
	tier_row.add_child(arrow)

	var next_tier = Label.new()
	next_tier.name = "NextTierLabel"
	next_tier.text = "Bronze"
	next_tier.add_theme_font_override("font", default_font)
	next_tier.add_theme_font_size_override("font_size", FONT_BODY)
	next_tier.add_theme_color_override("font_color", TIER_COLORS["bronze"])
	tier_row.add_child(next_tier)

	# Progress bar (taller, more prominent)
	var bar_bg = Control.new()
	bar_bg.name = "ProgressBarBG"
	bar_bg.custom_minimum_size = Vector2(0, 16)  # Taller bar
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(bar_bg)

	# Background panel with subtle border
	var bar_panel = PanelContainer.new()
	bar_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = BG_DARK
	bar_style.set_corner_radius_all(8)
	bar_style.border_color = CARD_BORDER
	bar_style.set_border_width_all(1)
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	bar_bg.add_child(bar_panel)

	# Use Godot's built-in ProgressBar for reliable fill rendering
	var progress_bar = ProgressBar.new()
	progress_bar.name = "TierProgressBar"
	progress_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	progress_bar.offset_left = 2
	progress_bar.offset_right = -2
	progress_bar.offset_top = 2
	progress_bar.offset_bottom = -2
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.show_percentage = false

	# Style the background (transparent since bar_panel already has bg)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)  # Transparent
	progress_bar.add_theme_stylebox_override("background", bg_style)

	# Style the fill
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = TIER_COLORS["initiate"]
	fill_style.set_corner_radius_all(6)
	progress_bar.add_theme_stylebox_override("fill", fill_style)

	bar_bg.add_child(progress_bar)

	# Progress text (e.g., "0 / 100")
	var progress_text = Label.new()
	progress_text.name = "ProgressText"
	progress_text.text = "0 / 100 to Bronze"
	progress_text.add_theme_font_override("font", default_font)
	progress_text.add_theme_font_size_override("font_size", FONT_CAPTION)
	progress_text.add_theme_color_override("font_color", TEXT_SECONDARY)
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(progress_text)

	return section

func _build_forge_column() -> Control:
	"""RIGHT COLUMN: The Forge - Tabbed view (Catalog/Owned/Equipped)"""
	print("[Armory] Building RIGHT column (Forge) with tabs")
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(320, 0)

	# Background
	var bg = ColorRect.new()
	bg.name = "ForgeBG"
	bg.color = CARD_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(bg)

	# Border overlay with cyan glow (matches MainMenu)
	var border = PanelContainer.new()
	border.name = "ForgeBorder"
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = BORDER_GLOW
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(8)
	border_style.shadow_size = 20
	border_style.shadow_color = SHADOW_GLOW
	border.add_theme_stylebox_override("panel", border_style)
	wrapper.add_child(border)

	# Content
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	wrapper.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)  # Tighter spacing
	margin.add_child(vbox)

	# === HEADER ===
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_row)

	var forge_icon = Label.new()
	forge_icon.text = "⚒"
	forge_icon.add_theme_font_size_override("font_size", FONT_H2)
	forge_icon.add_theme_color_override("font_color", MANTLE_CYAN)
	header_row.add_child(forge_icon)

	var header = Label.new()
	header.text = "THE FORGE"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_H2)
	header.add_theme_color_override("font_color", TEXT_PRIMARY)
	header_row.add_child(header)

	# === PROGRESS HEADER ===
	var owned_count = _get_owned_forge_items().size()
	var total_count = FORGE_CATALOG.size()
	var progress_percent = float(owned_count) / float(total_count) if total_count > 0 else 0.0

	var progress_container = VBoxContainer.new()
	progress_container.name = "ForgeProgressContainer"
	progress_container.add_theme_constant_override("separation", 4)
	vbox.add_child(progress_container)

	# Progress text row
	var progress_row = HBoxContainer.new()
	progress_row.alignment = BoxContainer.ALIGNMENT_CENTER
	progress_row.add_theme_constant_override("separation", 8)
	progress_container.add_child(progress_row)

	var progress_label = Label.new()
	progress_label.name = "ForgeProgressLabel"
	progress_label.text = "%d / %d UNLOCKED" % [owned_count, total_count]
	progress_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	progress_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	progress_row.add_child(progress_label)

	var progress_pct = Label.new()
	progress_pct.text = "(%d%%)" % int(progress_percent * 100)
	progress_pct.add_theme_font_size_override("font_size", FONT_CAPTION)
	progress_pct.add_theme_color_override("font_color", MANTLE_CYAN)
	progress_row.add_child(progress_pct)

	# Progress bar using ProgressBar control (simpler and more reliable)
	var progress_bar = ProgressBar.new()
	progress_bar.name = "ForgeProgressBar"
	progress_bar.custom_minimum_size = Vector2(0, 10)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.max_value = 100
	progress_bar.value = 0  # Start at 0 for animation
	progress_bar.show_percentage = false

	# Style the progress bar
	var bar_bg_style = StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.08, 0.08, 0.10)
	bar_bg_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("background", bar_bg_style)

	var bar_fill_style = StyleBoxFlat.new()
	bar_fill_style.bg_color = MANTLE_CYAN
	bar_fill_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("fill", bar_fill_style)

	progress_container.add_child(progress_bar)

	# Animate progress bar fill on load
	var bar_tween = create_tween()
	bar_tween.set_ease(Tween.EASE_OUT)
	bar_tween.set_trans(Tween.TRANS_CUBIC)
	bar_tween.tween_property(progress_bar, "value", progress_percent * 100, 0.8)

	# === SORT OPTIONS (centered, clean) ===
	var sort_row = HBoxContainer.new()
	sort_row.name = "ForgeSortBar"
	sort_row.add_theme_constant_override("separation", 6)
	sort_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(sort_row)

	var sort_label = Label.new()
	sort_label.text = "SORT:"
	sort_label.add_theme_font_size_override("font_size", FONT_TINY)
	sort_label.add_theme_color_override("font_color", TEXT_DIM)
	sort_row.add_child(sort_label)

	var sort_options = {"rarity": "Rarity", "game": "Game", "type": "Type"}
	for sort_id in sort_options:
		var sort_btn = Button.new()
		sort_btn.name = "Sort_" + sort_id
		sort_btn.text = sort_options[sort_id]
		sort_btn.custom_minimum_size = Vector2(65, 26)
		sort_btn.pressed.connect(_on_forge_sort_pressed.bind(sort_id))
		sort_btn.mouse_entered.connect(_play_button_hover_sound)
		_style_filter_button(sort_btn, sort_id == _forge_sort_by)
		sort_row.add_child(sort_btn)
		_forge_filter_buttons[sort_id] = sort_btn

	# === CLAIM ALL ROW (only if items to claim) ===
	var unclaimed_count = _get_unclaimed_count()
	if unclaimed_count > 0:
		var claim_row = HBoxContainer.new()
		claim_row.name = "ForgeClaimRow"
		claim_row.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(claim_row)

		var claim_all_btn = Button.new()
		claim_all_btn.name = "ClaimAllButton"
		claim_all_btn.text = "CLAIM ALL (%d)" % unclaimed_count
		claim_all_btn.custom_minimum_size = Vector2(160, 32)
		claim_all_btn.pressed.connect(_on_claim_all_pressed)
		claim_all_btn.mouse_entered.connect(_play_button_hover_sound)
		_style_claim_all_button(claim_all_btn)
		claim_row.add_child(claim_all_btn)

	# Divider before grid
	vbox.add_child(_create_section_divider())

	# === CONTENT CONTAINER (switches based on tab) ===
	_forge_content_container = PanelContainer.new()
	_forge_content_container.name = "ForgeContent"
	_forge_content_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # Fit content, don't expand
	_forge_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_forge_content_container.custom_minimum_size = Vector2(0, 336)  # Height for 4 rows (4×70 + 3×8 spacing + 16 margins)
	var content_style = StyleBoxFlat.new()
	content_style.bg_color = BG_DARK
	content_style.set_corner_radius_all(6)
	content_style.border_color = BORDER_GLOW
	content_style.set_border_width_all(2)
	content_style.shadow_size = 12
	content_style.shadow_color = SHADOW_GLOW
	_forge_content_container.add_theme_stylebox_override("panel", content_style)
	vbox.add_child(_forge_content_container)

	# Divider after content
	vbox.add_child(_create_section_divider())

	# === ITEM DETAIL PANEL ===
	var detail_panel = _build_forge_detail_panel()
	detail_panel.name = "ForgeDetailPanel"
	vbox.add_child(detail_panel)

	# Build initial forge content (unified view)
	_refresh_forge_content()

	# Store references
	character_preview = wrapper
	cosmetics_panel = border
	forged_panel = wrapper

	return wrapper

func _style_forge_tab(btn: Button, active: bool) -> void:
	"""Style a forge tab button"""
	var style = StyleBoxFlat.new()
	if active:
		style.bg_color = MANTLE_CYAN.darkened(0.6)
		style.border_color = MANTLE_CYAN
		btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	else:
		style.bg_color = Color(0.08, 0.08, 0.10)
		style.border_color = CARD_BORDER
		btn.add_theme_color_override("font_color", TEXT_DIM)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_font_size_override("font_size", FONT_TINY)

func _style_filter_button(btn: Button, active: bool) -> void:
	"""Style a filter/sort button"""
	var style = StyleBoxFlat.new()
	if active:
		style.bg_color = MANTLE_RED.darkened(0.5)
		style.border_color = MANTLE_RED
		btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	else:
		style.bg_color = Color(0.06, 0.06, 0.08)
		style.border_color = Color(0.12, 0.12, 0.14)
		btn.add_theme_color_override("font_color", TEXT_DIM)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_font_size_override("font_size", FONT_TINY - 2)

func _on_forge_sort_pressed(sort_id: String) -> void:
	"""Handle sort button press"""
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	if sort_id == _forge_sort_by:
		return
	_forge_sort_by = sort_id
	# Update button styles
	for sid in _forge_filter_buttons:
		_style_filter_button(_forge_filter_buttons[sid], sid == sort_id)
	# Refresh forge content
	_refresh_forge_content()

func _build_forge_detail_panel() -> Control:
	"""Build the item detail panel at bottom of forge - Enhanced with effect metadata"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 120)  # Taller to fit new content
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.05, 0.95)
	style.border_color = BORDER_GLOW.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# Item icon placeholder - fixed square size
	var icon_container = PanelContainer.new()
	icon_container.name = "DetailIcon"
	icon_container.custom_minimum_size = Vector2(80, 80)  # Larger square preview
	icon_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Don't stretch horizontally
	icon_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER    # Don't stretch vertically
	var icon_style = StyleBoxFlat.new()
	icon_style.bg_color = BG_DARK
	icon_style.border_color = CARD_BORDER
	icon_style.set_border_width_all(1)
	icon_style.set_corner_radius_all(4)
	icon_container.add_theme_stylebox_override("panel", icon_style)
	hbox.add_child(icon_container)

	var icon_center = CenterContainer.new()
	icon_container.add_child(icon_center)

	# TextureRect for actual item icon
	var icon_texture = TextureRect.new()
	icon_texture.name = "IconTexture"
	icon_texture.custom_minimum_size = Vector2(72, 72)  # Slightly smaller than container for padding
	icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # Don't auto-expand, use custom_minimum_size
	icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_texture.visible = false
	icon_center.add_child(icon_texture)

	# Fallback label for when no icon is loaded
	var icon_placeholder = Label.new()
	icon_placeholder.name = "IconLabel"
	icon_placeholder.text = "?"
	icon_placeholder.add_theme_font_size_override("font_size", 28)
	icon_placeholder.add_theme_color_override("font_color", TEXT_DIM)
	icon_center.add_child(icon_placeholder)

	# Item details - main info column
	var details_vbox = VBoxContainer.new()
	details_vbox.name = "DetailInfo"
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(details_vbox)

	var name_label = Label.new()
	name_label.name = "ItemName"
	name_label.text = "Click an item to select"
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	details_vbox.add_child(name_label)

	var rarity_label = Label.new()
	rarity_label.name = "ItemRarity"
	rarity_label.text = ""
	rarity_label.add_theme_font_size_override("font_size", FONT_TINY)
	rarity_label.add_theme_color_override("font_color", TEXT_DIM)
	details_vbox.add_child(rarity_label)

	var unlock_label = Label.new()
	unlock_label.name = "ItemUnlock"
	unlock_label.text = "Select an item to see details"
	unlock_label.add_theme_font_size_override("font_size", FONT_TINY)
	unlock_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	unlock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_vbox.add_child(unlock_label)

	# Lore text - italic style for flavor
	var lore_label = Label.new()
	lore_label.name = "ItemLore"
	lore_label.text = ""
	lore_label.add_theme_font_size_override("font_size", FONT_TINY)
	lore_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	lore_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore_label.visible = false
	details_vbox.add_child(lore_label)

	# === NEW: Unique Modifiers Section ===
	var modifiers_section = VBoxContainer.new()
	modifiers_section.name = "ModifiersSection"
	modifiers_section.add_theme_constant_override("separation", 4)
	modifiers_section.visible = false
	hbox.add_child(modifiers_section)

	# Effort Score with progress bar
	var effort_container = VBoxContainer.new()
	effort_container.name = "EffortContainer"
	effort_container.add_theme_constant_override("separation", 2)
	modifiers_section.add_child(effort_container)

	var effort_header = HBoxContainer.new()
	effort_header.add_theme_constant_override("separation", 4)
	effort_container.add_child(effort_header)

	var effort_label = Label.new()
	effort_label.name = "EffortLabel"
	effort_label.text = "EFFORT"
	effort_label.add_theme_font_size_override("font_size", FONT_TINY - 2)
	effort_label.add_theme_color_override("font_color", TEXT_DIM)
	effort_header.add_child(effort_label)

	var effort_value = Label.new()
	effort_value.name = "EffortValue"
	effort_value.text = ""
	effort_value.add_theme_font_size_override("font_size", FONT_TINY - 2)
	effort_value.add_theme_color_override("font_color", MANTLE_CYAN)
	effort_header.add_child(effort_value)

	var effort_bar = ProgressBar.new()
	effort_bar.name = "EffortBar"
	effort_bar.custom_minimum_size = Vector2(80, 8)
	effort_bar.max_value = 100
	effort_bar.value = 0
	effort_bar.show_percentage = false
	var effort_bar_style = StyleBoxFlat.new()
	effort_bar_style.bg_color = Color(0.1, 0.1, 0.12)
	effort_bar_style.set_corner_radius_all(2)
	effort_bar.add_theme_stylebox_override("background", effort_bar_style)
	var effort_fill_style = StyleBoxFlat.new()
	effort_fill_style.bg_color = MANTLE_CYAN
	effort_fill_style.set_corner_radius_all(2)
	effort_bar.add_theme_stylebox_override("fill", effort_fill_style)
	effort_container.add_child(effort_bar)

	# Badges row (Vintage, Secret, Ultra-Rare)
	var badges_row = HBoxContainer.new()
	badges_row.name = "BadgesRow"
	badges_row.add_theme_constant_override("separation", 6)
	modifiers_section.add_child(badges_row)

	# Vintage badge
	var vintage_badge = _create_modifier_badge("VintageBadge", "VETERAN", Color(0.8, 0.6, 0.2))
	badges_row.add_child(vintage_badge)

	# Secret badge
	var secret_badge = _create_modifier_badge("SecretBadge", "SECRET", Color(0.6, 0.3, 0.8))
	badges_row.add_child(secret_badge)

	# Ultra-rare badge
	var rare_badge = _create_modifier_badge("UltraRareBadge", "RARE", Color(0.9, 0.4, 0.1))
	badges_row.add_child(rare_badge)

	# Damage bonus display
	var bonus_label = Label.new()
	bonus_label.name = "BonusLabel"
	bonus_label.text = ""
	bonus_label.add_theme_font_size_override("font_size", FONT_TINY - 2)
	bonus_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	modifiers_section.add_child(bonus_label)

	# === NEW: Trading Info Section ===
	var trading_section = VBoxContainer.new()
	trading_section.name = "TradingSection"
	trading_section.add_theme_constant_override("separation", 4)
	trading_section.visible = false
	hbox.add_child(trading_section)

	# Census label ("Only X exist")
	var census_label = Label.new()
	census_label.name = "CensusLabel"
	census_label.text = ""
	census_label.add_theme_font_size_override("font_size", FONT_TINY - 2)
	census_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))  # Gold color
	trading_section.add_child(census_label)

	# Trade status (cooldown indicator)
	var trade_status_container = HBoxContainer.new()
	trade_status_container.name = "TradeStatusContainer"
	trade_status_container.add_theme_constant_override("separation", 4)
	trading_section.add_child(trade_status_container)

	var trade_icon = Label.new()
	trade_icon.name = "TradeIcon"
	trade_icon.text = ""
	trade_icon.add_theme_font_size_override("font_size", FONT_TINY)
	trade_status_container.add_child(trade_icon)

	var trade_status = Label.new()
	trade_status.name = "TradeStatus"
	trade_status.text = ""
	trade_status.add_theme_font_size_override("font_size", FONT_TINY - 2)
	trade_status.add_theme_color_override("font_color", TEXT_SECONDARY)
	trade_status_container.add_child(trade_status)

	# Trade cooldown badge
	var cooldown_badge = _create_modifier_badge("CooldownBadge", "ON COOLDOWN", Color(0.8, 0.3, 0.3))
	cooldown_badge.visible = false
	trading_section.add_child(cooldown_badge)

	# Preview button container (right side)
	var preview_vbox = VBoxContainer.new()
	preview_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(preview_vbox)

	var preview_btn = Button.new()
	preview_btn.name = "PreviewButton"
	preview_btn.text = "PREVIEW"
	preview_btn.custom_minimum_size = Vector2(70, 32)
	preview_btn.visible = false  # Hidden until item selected
	preview_btn.pressed.connect(_on_preview_pressed)
	preview_btn.mouse_entered.connect(_play_button_hover_sound)
	_style_preview_button(preview_btn)
	preview_vbox.add_child(preview_btn)

	var preview_hint = Label.new()
	preview_hint.name = "PreviewHint"
	preview_hint.text = ""
	preview_hint.add_theme_font_size_override("font_size", FONT_TINY)
	preview_hint.add_theme_color_override("font_color", TEXT_DIM)
	preview_hint.visible = false
	preview_vbox.add_child(preview_hint)

	_forge_detail_panel = panel
	return panel

func _create_modifier_badge(badge_name: String, text: String, color: Color) -> PanelContainer:
	"""Create a small badge for displaying modifiers"""
	var badge = PanelContainer.new()
	badge.name = badge_name
	badge.visible = false  # Hidden by default
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(color.r, color.g, color.b, 0.2)
	badge_style.border_color = color.darkened(0.2)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(3)
	badge_style.set_content_margin_all(2)
	badge.add_theme_stylebox_override("panel", badge_style)

	var label = Label.new()
	label.name = "BadgeText"
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_TINY - 4)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)

	return badge

func _style_preview_button(btn: Button) -> void:
	"""Style the preview button"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10)
	style.border_color = MANTLE_CYAN.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = MANTLE_CYAN.darkened(0.6)
	hover_style.border_color = MANTLE_CYAN
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", hover_style)

	btn.add_theme_font_size_override("font_size", FONT_TINY - 2)
	btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)

func _on_preview_pressed() -> void:
	"""Claim the selected forged item and add it to player's inventory bag"""
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)

	if _forge_selected_item.is_empty():
		return

	var item_id = _forge_selected_item.get("id", _forge_selected_item.get("item_id", ""))
	if item_id == "":
		print("[Armory] No item_id found for selected item")
		return

	var preview_btn = _forge_detail_panel.find_child("PreviewButton", true, false) if _forge_detail_panel else null

	# Check if already claimed
	if ForgeItemManager.is_item_claimed(item_id):
		print("[Armory] Item already claimed: %s" % item_id)
		if preview_btn:
			preview_btn.text = "CLAIMED"
			preview_btn.disabled = true
		return

	# Claim the item - adds to inventory
	var claimed_item = ForgeItemManager.claim_single_item(item_id)
	if not claimed_item.is_empty():
		print("[Armory] Successfully claimed: %s -> added to inventory" % claimed_item.get("name", item_id))

		# Visual feedback - green flash
		if preview_btn:
			preview_btn.text = "CLAIMED!"
			preview_btn.disabled = true
			var tween = create_tween()
			tween.tween_property(preview_btn, "modulate", Color(0.3, 1.0, 0.4), 0.15)
			tween.tween_property(preview_btn, "modulate", Color.WHITE, 0.3)

		# Play success sound
		if SoundManager:
			SoundManager.play_equip_sound(-6.0)

		# Show notification
		if NotificationManager:
			NotificationManager.show_item_notification(
				claimed_item.get("name", "Forged Item"),
				claimed_item.get("rarity", "Common")
			)

		# Refresh the forge grid to update claimed status
		_refresh_forge_content()
	else:
		print("[Armory] Failed to claim item: %s (already claimed or inventory full)" % item_id)
		# Flash red to indicate failure
		if preview_btn:
			var tween = create_tween()
			tween.tween_property(preview_btn, "modulate", Color(1.0, 0.3, 0.3), 0.15)
			tween.tween_property(preview_btn, "modulate", Color.WHITE, 0.3)

func _update_forge_detail(item: Dictionary, is_owned: bool) -> void:
	"""Update the forge detail panel with item info (pre-computed from backend)"""
	if not _forge_detail_panel:
		return

	var name_label = _forge_detail_panel.find_child("ItemName", true, false)
	var rarity_label = _forge_detail_panel.find_child("ItemRarity", true, false)
	var unlock_label = _forge_detail_panel.find_child("ItemUnlock", true, false)
	var lore_label = _forge_detail_panel.find_child("ItemLore", true, false)
	var icon_label = _forge_detail_panel.find_child("IconLabel", true, false)
	var icon_texture = _forge_detail_panel.find_child("IconTexture", true, false)
	var icon_container = _forge_detail_panel.find_child("DetailIcon", true, false)
	var preview_btn = _forge_detail_panel.find_child("PreviewButton", true, false)

	# Modifier UI elements (display pre-computed data)
	var modifiers_section = _forge_detail_panel.find_child("ModifiersSection", true, false)
	var effort_bar = _forge_detail_panel.find_child("EffortBar", true, false)
	var effort_value = _forge_detail_panel.find_child("EffortValue", true, false)
	var vintage_badge = _forge_detail_panel.find_child("VintageBadge", true, false)
	var secret_badge = _forge_detail_panel.find_child("SecretBadge", true, false)
	var rare_badge = _forge_detail_panel.find_child("UltraRareBadge", true, false)
	var bonus_label = _forge_detail_panel.find_child("BonusLabel", true, false)

	if item.is_empty():
		_forge_selected_item = {}
		if name_label: name_label.text = "Click an item to select"
		if rarity_label: rarity_label.text = ""
		if unlock_label: unlock_label.text = "Select an item to see details"
		if lore_label: lore_label.visible = false
		if preview_btn: preview_btn.visible = false
		if modifiers_section: modifiers_section.visible = false
		if icon_label:
			icon_label.text = "?"
			icon_label.add_theme_color_override("font_color", TEXT_DIM)
			icon_label.visible = true
		if icon_texture:
			icon_texture.visible = false
		return

	_forge_selected_item = item

	# Get item properties (works with both catalog items and forged items)
	var item_name = item.get("item_name", item.get("name", "Unknown"))
	var rarity = item.get("item_rarity", item.get("rarity", "Common"))
	var game_name = item.get("game", "???")
	var rarity_color = RARITY_COLORS.get(rarity, Color.GRAY)

	if name_label:
		name_label.text = item_name
		name_label.add_theme_color_override("font_color", rarity_color if is_owned else rarity_color.darkened(0.3))

	if rarity_label:
		rarity_label.text = "%s • %s" % [rarity, game_name]
		rarity_label.add_theme_color_override("font_color", rarity_color.darkened(0.2))

	if unlock_label:
		if is_owned:
			var item_id = item.get("id", item.get("item_id", ""))
			var already_claimed = ForgeItemManager.is_item_claimed(item_id)
			if already_claimed:
				unlock_label.text = "✓ CLAIMED - Check your inventory!"
				unlock_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			else:
				unlock_label.text = "✓ UNLOCKED - Click CLAIM to add to inventory"
				unlock_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))  # Brighter green for action
		else:
			unlock_label.text = "🔒 HOW TO UNLOCK: Link %s → Complete \"%s\"" % [item.get("game", "???"), item.get("achievement", "???")]
			unlock_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))  # Orange for attention

	# Show lore text
	if lore_label:
		var lore = item.get("lore", "")
		if lore != "":
			lore_label.text = "\"%s\"" % lore
			lore_label.visible = true
		else:
			lore_label.visible = false

	# Load actual item icon
	var icon_path = item.get("icon", "")
	var icon_loaded = false
	if icon_texture and icon_path != "" and ResourceLoader.exists(icon_path):
		var texture = load(icon_path)
		if texture:
			icon_texture.texture = texture
			icon_texture.visible = true
			icon_loaded = true
			if icon_label:
				icon_label.visible = false

	if not icon_loaded and icon_label:
		# Fallback to category emoji
		var category = item.get("category", "weapons")
		match category:
			"weapons": icon_label.text = "⚔"
			"armor": icon_label.text = "👑"
			"shields": icon_label.text = "🛡"
			"accessories": icon_label.text = "💎"
			_: icon_label.text = "?"
		icon_label.add_theme_color_override("font_color", rarity_color if is_owned else rarity_color.darkened(0.4))
		icon_label.visible = true
		if icon_texture:
			icon_texture.visible = false

	if icon_container:
		var style = icon_container.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat:
			style.border_color = rarity_color.darkened(0.3) if is_owned else CARD_BORDER
			icon_container.add_theme_stylebox_override("panel", style)

	# Show claim button for owned items (check if already claimed)
	if preview_btn:
		preview_btn.visible = is_owned
		if is_owned:
			var item_id = item.get("id", item.get("item_id", ""))
			var already_claimed = ForgeItemManager.is_item_claimed(item_id)
			if already_claimed:
				preview_btn.text = "CLAIMED"
				preview_btn.disabled = true
			else:
				preview_btn.text = "CLAIM"
				preview_btn.disabled = false
		else:
			preview_btn.text = ""

	# === Update Modifiers Section (pre-computed from backend) ===
	_update_modifiers_display(item, modifiers_section, effort_bar, effort_value,
		vintage_badge, secret_badge, rare_badge, bonus_label, is_owned)

	# === Update Trading Section ===
	var trading_section = _forge_detail_panel.find_child("TradingSection", true, false)
	var census_label = _forge_detail_panel.find_child("CensusLabel", true, false)
	var trade_icon = _forge_detail_panel.find_child("TradeIcon", true, false)
	var trade_status = _forge_detail_panel.find_child("TradeStatus", true, false)
	var cooldown_badge = _forge_detail_panel.find_child("CooldownBadge", true, false)
	_update_trading_display(item, trading_section, census_label, trade_icon, trade_status, cooldown_badge, is_owned)

func _update_modifiers_display(item: Dictionary, modifiers_section: Control,
		effort_bar: ProgressBar, effort_value: Label, vintage_badge: PanelContainer,
		secret_badge: PanelContainer, rare_badge: PanelContainer, bonus_label: Label,
		is_owned: bool) -> void:
	"""Update the modifiers display section using pre-computed item data from backend"""
	# Hide section if not owned (forged items have pre-computed stats)
	if not is_owned:
		if modifiers_section: modifiers_section.visible = false
		return

	# Check if item has pre-computed stats (from backend)
	var has_stats = item.has("effect_intensity") or item.has("effort_tier")
	if not has_stats:
		if modifiers_section: modifiers_section.visible = false
		return

	if modifiers_section: modifiers_section.visible = true

	# Update effort/intensity display (from backend's effect_intensity)
	var intensity = item.get("effect_intensity", 0.0) * 100  # Convert 0-1 to 0-100
	var effort_tier = item.get("effort_tier", "")
	if effort_bar:
		effort_bar.value = intensity
		var fill_color = _get_effort_color(intensity)
		var fill_style = effort_bar.get_theme_stylebox("fill").duplicate()
		if fill_style is StyleBoxFlat:
			fill_style.bg_color = fill_color
			effort_bar.add_theme_stylebox_override("fill", fill_style)

	if effort_value:
		effort_value.text = "%d%% (%s)" % [int(intensity), effort_tier] if effort_tier else "%d%%" % int(intensity)
		effort_value.add_theme_color_override("font_color", _get_effort_color(intensity))

	# Update vintage badge (from backend's vintage_years)
	if vintage_badge:
		var vintage_years = item.get("vintage_years", 0)
		if vintage_years >= 3:
			vintage_badge.visible = true
			var badge_text = vintage_badge.find_child("BadgeText", true, false)
			var prefix = "ANCIENT" if vintage_years >= 7 else "VETERAN"
			if badge_text:
				badge_text.text = "%s (%dy)" % [prefix, vintage_years]
		else:
			vintage_badge.visible = false

	# Update secret badge (from backend's is_secret)
	if secret_badge:
		secret_badge.visible = item.get("is_secret", false)

	# Update ultra-rare badge (item_rarity == "Legendary" or "Epic")
	if rare_badge:
		var rarity = item.get("item_rarity", item.get("rarity", ""))
		rare_badge.visible = rarity in ["Legendary", "Epic"]

	# Update stat bonus label (from backend's stat_primary)
	if bonus_label:
		var stat_primary = item.get("stat_primary", 0.0)
		var effect_name = item.get("effect_name", "")

		if stat_primary > 0 or effect_name != "":
			var parts = []
			if stat_primary > 0:
				parts.append("+%.0f%% intensity" % (stat_primary * 100))
			if effect_name != "":
				parts.append(effect_name.replace("_", " ").capitalize())
			bonus_label.text = " | ".join(parts)
			bonus_label.visible = true
		else:
			bonus_label.visible = false

func _get_effort_color(score: float) -> Color:
	"""Get color based on effort/intensity score"""
	if score >= 81:
		return Color(1.0, 0.5, 0.0)  # Orange - Exceptional
	elif score >= 61:
		return Color(0.7, 0.3, 0.9)  # Purple - Superior
	elif score >= 41:
		return Color(0.2, 0.6, 1.0)  # Blue - Enhanced
	elif score >= 21:
		return Color(0.2, 0.8, 0.2)  # Green - Standard
	else:
		return Color(0.6, 0.6, 0.6)  # Gray - Minor

func _update_trading_display(item: Dictionary, trading_section: Control,
		census_label: Label, trade_icon: Label, trade_status: Label,
		cooldown_badge: PanelContainer, is_owned: bool) -> void:
	"""Update the trading info section for forged items"""
	# Always show trading section for forged items (even unowned - shows census)
	var item_id = item.get("item_id", item.get("id", ""))
	if item_id == "":
		if trading_section: trading_section.visible = false
		return

	if trading_section: trading_section.visible = true

	# Update census count ("Only X exist")
	if census_label:
		if TradingManager and TradingManager.is_census_loaded():
			var count = TradingManager.get_item_count(item_id)
			if count > 0:
				if count == 1:
					census_label.text = "Only 1 exists!"
					census_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0))  # Orange for unique
				elif count <= 5:
					census_label.text = "Only %d exist!" % count
					census_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))  # Gold
				elif count <= 20:
					census_label.text = "%d in circulation" % count
					census_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
				else:
					census_label.text = "%d forged" % count
					census_label.add_theme_color_override("font_color", TEXT_DIM)
				census_label.visible = true
			else:
				census_label.text = "None forged yet"
				census_label.add_theme_color_override("font_color", TEXT_DIM)
				census_label.visible = true
		else:
			census_label.visible = false
			# Fetch census if not loaded
			if TradingManager:
				TradingManager.fetch_census()

	# Trade status (only for owned items)
	if is_owned:
		var token_id = item.get("token_id", 0)
		if token_id > 0 and TradingManager:
			# Check cooldown
			TradingManager.check_cooldown_with_cache(token_id, func(data: Dictionary):
				_update_cooldown_display(data, trade_icon, trade_status, cooldown_badge)
			)
		else:
			if trade_icon: trade_icon.text = ""
			if trade_status: trade_status.text = "Tradeable"
			if trade_status: trade_status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			if cooldown_badge: cooldown_badge.visible = false
	else:
		if trade_icon: trade_icon.text = ""
		if trade_status: trade_status.text = ""
		if cooldown_badge: cooldown_badge.visible = false

func _update_cooldown_display(data: Dictionary, trade_icon: Label, trade_status: Label, cooldown_badge: PanelContainer) -> void:
	"""Update cooldown display based on API response"""
	var is_tradeable = data.get("tradeable", true)

	if is_tradeable:
		if trade_icon: trade_icon.text = ""
		if trade_status:
			trade_status.text = "Tradeable"
			trade_status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		if cooldown_badge: cooldown_badge.visible = false
	else:
		var seconds = data.get("seconds_remaining", 0)
		var hours = int(seconds / 3600)
		var mins = int((seconds % 3600) / 60)

		if trade_icon: trade_icon.text = ""
		if trade_status:
			if hours > 0:
				trade_status.text = "Cooldown: %dh %dm" % [hours, mins]
			else:
				trade_status.text = "Cooldown: %dm" % mins
			trade_status.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))

		if cooldown_badge:
			cooldown_badge.visible = true
			var badge_text = cooldown_badge.find_child("BadgeText", true, false)
			if badge_text:
				if hours > 0:
					badge_text.text = "%dh %dm" % [hours, mins]
				else:
					badge_text.text = "%dm remaining" % mins

func _refresh_forge_content() -> void:
	"""Refresh the forge grid content"""
	if not _forge_content_container:
		return

	# Clear existing content
	for child in _forge_content_container.get_children():
		child.queue_free()

	# Build unified content (owned items first, then locked)
	var content = _build_forge_unified_content()
	_forge_content_container.add_child(content)

func _switch_forge_tab(_tab_id: String = "") -> void:
	"""Legacy wrapper - now just refreshes unified content"""
	_refresh_forge_content()

func _build_forge_unified_content() -> Control:
	"""Build unified forge view - unlocked items at top, locked items below"""
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var grid = GridContainer.new()
	grid.name = "CatalogGrid"
	grid.columns = 6  # Fixed 6-column layout
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(grid)

	# Get owned items for ownership check (backend uses item_id)
	var owned_items = _get_owned_forge_items()
	var owned_ids = []
	for owned in owned_items:
		# Backend forged items use "item_id", FORGE_CATALOG uses "id"
		var oid = owned.get("item_id", owned.get("id", ""))
		if oid != "":
			owned_ids.append(oid)

	# Sort catalog based on current sort setting
	var sorted_items = _sort_items(FORGE_CATALOG.duplicate())

	# Separate into owned and locked items
	var owned_list = []
	var locked_list = []
	for item in sorted_items:
		var item_id = item.get("id", "")
		if item_id in owned_ids:
			owned_list.append(item)
		else:
			locked_list.append(item)

	# Add owned items first (with checkmarks)
	for item in owned_list:
		var item_card = _create_forge_item_card(item, true)
		grid.add_child(item_card)

	# Add locked items after
	for item in locked_list:
		var item_card = _create_forge_item_card(item, false)
		grid.add_child(item_card)

	return scroll

func _build_forge_all_content() -> Control:
	"""Legacy wrapper - calls unified content"""
	return _build_forge_unified_content()

func _build_forge_unlocked_content() -> Control:
	"""Build the UNLOCKED tab - shows items player has unlocked (claimable at blacksmith)"""
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# Get owned items (for now, simulate with some unlocked)
	var owned_items = _get_owned_forge_items()

	if owned_items.size() == 0:
		# Enhanced empty state with illustration
		var empty_container = VBoxContainer.new()
		empty_container.add_theme_constant_override("separation", 16)
		empty_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(empty_container)

		# Spacer to center vertically
		var top_spacer = Control.new()
		top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_container.add_child(top_spacer)

		# Icon illustration
		var icon_label = Label.new()
		icon_label.text = "🔨"
		icon_label.add_theme_font_size_override("font_size", 48)
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.modulate = Color(1, 1, 1, 0.4)
		empty_container.add_child(icon_label)

		# Title
		var title_label = Label.new()
		title_label.text = "Your Forge is Empty"
		title_label.add_theme_font_size_override("font_size", FONT_H3)
		title_label.add_theme_color_override("font_color", TEXT_SECONDARY)
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_container.add_child(title_label)

		# Description
		var desc_label = Label.new()
		desc_label.text = "Link your gaming accounts and earn achievements\nto unlock exclusive cosmetic items!\n\nUnlocked items can be claimed and added to your inventory."
		desc_label.add_theme_font_size_override("font_size", FONT_CAPTION)
		desc_label.add_theme_color_override("font_color", TEXT_DIM)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_container.add_child(desc_label)

		# Bottom spacer
		var bottom_spacer = Control.new()
		bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_container.add_child(bottom_spacer)
	else:
		var grid = GridContainer.new()
		grid.columns = 6  # Fixed 6-column layout
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(grid)

		# Sort based on current setting
		var sorted_owned = _sort_items(owned_items)

		for item in sorted_owned:
			var item_card = _create_forge_item_card(item, true)  # true = owned
			grid.add_child(item_card)

	return scroll

func _create_forge_item_card(item: Dictionary, is_owned: bool) -> Control:
	"""Create a single forge item card for the grid"""
	var card = PanelContainer.new()
	card.name = "ForgeCard_" + item.get("id", "unknown")
	card.custom_minimum_size = Vector2(70, 70)  # Fixed size cards
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Expand to fill grid cell width
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER  # Don't expand height
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # Capture mouse events

	var rarity_color = RARITY_COLORS.get(item.get("rarity", "Common"), Color.GRAY)

	# Card style - minimal padding, rarity hint even when locked
	var style = StyleBoxFlat.new()
	var rarity = item.get("rarity", "Common")
	var is_high_rarity = rarity in ["Legendary", "Epic"]

	if is_owned:
		style.bg_color = Color(0.08, 0.08, 0.10)
		style.border_color = rarity_color.darkened(0.2)
		# Add glow for high-rarity owned items
		if is_high_rarity:
			style.shadow_size = 6
			style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.5)
	else:
		style.bg_color = Color(0.03, 0.03, 0.04)
		style.border_color = rarity_color.darkened(0.6)  # Subtle rarity hint when locked
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(1)  # Tight padding
	card.add_theme_stylebox_override("panel", style)

	# Store item data and style for hover effects
	card.set_meta("item_data", item)
	card.set_meta("is_owned", is_owned)
	card.set_meta("normal_style", style)
	card.set_meta("rarity_color", rarity_color)
	card.set_meta("is_high_rarity", is_high_rarity and is_owned)

	# Connect hover signals (visual feedback only)
	card.mouse_entered.connect(_on_forge_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_forge_card_hover.bind(card, false))
	# Connect click signal for selection
	card.gui_input.connect(_on_forge_card_clicked.bind(card))

	# Animated glow for high-rarity owned items
	if is_high_rarity and is_owned:
		var glow_tween = create_tween()
		glow_tween.set_loops()
		glow_tween.tween_property(style, "shadow_size", 10, 1.5).set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property(style, "shadow_size", 6, 1.5).set_ease(Tween.EASE_IN_OUT)

	# Set pivot for centered scaling (will be updated on hover based on actual size)
	card.pivot_offset = Vector2(35, 35)  # Half of 70x70

	# Icon container centered in card
	var icon_container = CenterContainer.new()
	icon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(icon_container)

	# Try to load actual icon
	var icon_path = item.get("icon", "")
	if ResourceLoader.exists(icon_path):
		var texture = load(icon_path)
		if texture:
			var icon_rect = TextureRect.new()
			icon_rect.texture = texture
			icon_rect.custom_minimum_size = Vector2(70, 70)  # Fill the card
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if not is_owned:
				icon_rect.modulate = Color(0.5, 0.5, 0.5, 0.85)  # Slightly grayed
			icon_container.add_child(icon_rect)
		else:
			_add_fallback_icon(icon_container, item, is_owned)
	else:
		_add_fallback_icon(icon_container, item, is_owned)

	# Badge overlay layer - Control node won't auto-resize like PanelContainer children
	# This sits on top of the icon_container and allows absolute positioning
	var badge_layer = Control.new()
	badge_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Pass clicks through to card
	card.add_child(badge_layer)

	# Lock overlay for unowned items - bottom right corner
	if not is_owned:
		var lock_bg = ColorRect.new()
		lock_bg.color = Color(0, 0, 0, 0.7)
		lock_bg.custom_minimum_size = Vector2(18, 18)
		lock_bg.size = Vector2(18, 18)
		lock_bg.position = Vector2(50, 50)  # Bottom-right of 70x70 card
		badge_layer.add_child(lock_bg)

		var lock_label = Label.new()
		lock_label.text = "🔒"
		lock_label.add_theme_font_size_override("font_size", 12)
		lock_label.position = Vector2(51, 48)  # Centered in lock_bg
		badge_layer.add_child(lock_label)
	elif item.get("is_new", false):
		# NEW badge for recently forged items - top right corner
		var badge_bg = ColorRect.new()
		badge_bg.color = MANTLE_CYAN
		badge_bg.custom_minimum_size = Vector2(28, 14)
		badge_bg.size = Vector2(28, 14)
		badge_bg.position = Vector2(40, 2)  # Top-right of 70x70 card
		badge_layer.add_child(badge_bg)

		var new_badge = Label.new()
		new_badge.name = "NewBadge"
		new_badge.text = "NEW"
		new_badge.add_theme_font_size_override("font_size", 10)
		new_badge.add_theme_color_override("font_color", Color.WHITE)
		new_badge.position = Vector2(42, 2)  # Inside badge_bg
		badge_layer.add_child(new_badge)

		# Pulsing animation for NEW badge
		var pulse_tween = create_tween()
		pulse_tween.set_loops()
		pulse_tween.tween_property(new_badge, "modulate:a", 0.5, 0.5).set_ease(Tween.EASE_IN_OUT)
		pulse_tween.tween_property(new_badge, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	else:
		# Checkmark badge for owned items - bottom LEFT corner
		var check_bg = ColorRect.new()
		check_bg.color = Color(0.1, 0.3, 0.1, 0.9)
		check_bg.custom_minimum_size = Vector2(16, 16)
		check_bg.size = Vector2(16, 16)
		check_bg.position = Vector2(2, 52)  # Bottom-left of 70x70 card
		badge_layer.add_child(check_bg)

		var claim_badge = Label.new()
		claim_badge.name = "ClaimBadge"
		claim_badge.text = "✓"
		claim_badge.add_theme_font_size_override("font_size", 11)
		claim_badge.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))  # Green checkmark
		claim_badge.position = Vector2(4, 50)  # Inside check_bg
		badge_layer.add_child(claim_badge)

	# Rich tooltip with lore
	var lore = item.get("lore", "")
	var tooltip = "%s  (%s)\n━━━━━━━━━━━━━━━━\n\"%s\"\n\n🎮 %s\n🏆 %s" % [
		item.get("name", "Unknown"),
		item.get("rarity", "Common"),
		lore if lore != "" else "A mysterious item from another world.",
		item.get("game", "???"),
		item.get("achievement", "???")
	]
	if not is_owned:
		tooltip += "\n\n🔒 HOW TO UNLOCK:\nLink %s and complete \"%s\"" % [item.get("game", "this game"), item.get("achievement", "achievement")]
	else:
		var item_id = item.get("id", item.get("item_id", ""))
		var already_claimed = ForgeItemManager.is_item_claimed(item_id)
		if already_claimed:
			tooltip += "\n\n✓ CLAIMED - Check your inventory!"
		else:
			tooltip += "\n\n✓ UNLOCKED - Click to claim"
	card.tooltip_text = tooltip

	return card

func _add_fallback_icon(container: Control, item: Dictionary, is_owned: bool) -> void:
	"""Add fallback emoji icon when texture not found"""
	var fallback = Label.new()
	var category = item.get("category", "weapons")
	match category:
		"weapons": fallback.text = "⚔"
		"armor": fallback.text = "👑"
		"shields": fallback.text = "🛡"
		"accessories": fallback.text = "💎"
		_: fallback.text = "?"
	fallback.add_theme_font_size_override("font_size", 44)  # Sized for 70x70 cards
	if is_owned:
		fallback.add_theme_color_override("font_color", RARITY_COLORS.get(item.get("rarity", "Common"), Color.GRAY))
	else:
		fallback.add_theme_color_override("font_color", TEXT_DIM)
	container.add_child(fallback)

func _on_forge_card_hover(card: PanelContainer, is_hovering: bool) -> void:
	"""Handle hover visual effects on forge item cards (visual only, no selection)"""
	var rarity_color: Color = card.get_meta("rarity_color", Color.GRAY)
	var is_owned: bool = card.get_meta("is_owned", false)

	if is_hovering:
		# Play hover sound
		if SoundManager:
			SoundManager.play_button_hover_sound(-12.0)

		# Set pivot to center based on actual size for proper scaling
		card.pivot_offset = card.size / 2.0

		# Create hover style with glow
		var hover_style = StyleBoxFlat.new()
		if is_owned:
			hover_style.bg_color = Color(0.12, 0.12, 0.14)
			hover_style.border_color = rarity_color
		else:
			hover_style.bg_color = Color(0.06, 0.06, 0.08)
			hover_style.border_color = rarity_color.darkened(0.3)
		hover_style.set_border_width_all(2)
		hover_style.set_corner_radius_all(4)
		hover_style.set_content_margin_all(1)
		hover_style.shadow_size = 8
		hover_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.4)
		card.add_theme_stylebox_override("panel", hover_style)

		# Scale up slightly
		var tween = create_tween()
		tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.1).set_ease(Tween.EASE_OUT)
	else:
		# Restore normal style (unless this is the selected card)
		var normal_style: StyleBoxFlat = card.get_meta("normal_style")
		if normal_style and card != _forge_selected_card:
			card.add_theme_stylebox_override("panel", normal_style)

		# Scale back
		var tween = create_tween()
		tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)

func _on_forge_card_clicked(event: InputEvent, card: PanelContainer) -> void:
	"""Handle click to select a forge item card"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var is_owned: bool = card.get_meta("is_owned", false)
		var item_data: Dictionary = card.get_meta("item_data", {})
		var rarity_color: Color = card.get_meta("rarity_color", Color.GRAY)

		# Play click sound
		if SoundManager:
			SoundManager.play_button_click_sound(-6.0)

		# Deselect previous card
		if _forge_selected_card and _forge_selected_card != card:
			var old_style: StyleBoxFlat = _forge_selected_card.get_meta("normal_style")
			if old_style:
				_forge_selected_card.add_theme_stylebox_override("panel", old_style)

		# Mark this card as selected
		_forge_selected_card = card

		# Apply selected style (bright border)
		var selected_style = StyleBoxFlat.new()
		selected_style.bg_color = Color(0.15, 0.15, 0.18) if is_owned else Color(0.08, 0.08, 0.10)
		selected_style.border_color = rarity_color.lightened(0.2)
		selected_style.set_border_width_all(3)
		selected_style.set_corner_radius_all(4)
		selected_style.set_content_margin_all(1)
		selected_style.shadow_size = 12
		selected_style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.5)
		card.add_theme_stylebox_override("panel", selected_style)

		# Update detail panel with selected item
		_update_forge_detail(item_data, is_owned)

func _sort_by_rarity(a: Dictionary, b: Dictionary) -> bool:
	"""Sort items by rarity (highest first): Legendary > Epic > Rare > Uncommon > Common"""
	var rarity_order = {
		"Legendary": 0,
		"Epic": 1,
		"Rare": 2,
		"Uncommon": 3,
		"Common": 4
	}
	var a_order = rarity_order.get(a.get("rarity", "Common"), 5)
	var b_order = rarity_order.get(b.get("rarity", "Common"), 5)
	return a_order < b_order

func _sort_by_game(a: Dictionary, b: Dictionary) -> bool:
	"""Sort items alphabetically by game name"""
	return a.get("game", "").to_lower() < b.get("game", "").to_lower()

func _sort_by_type(a: Dictionary, b: Dictionary) -> bool:
	"""Sort items by category/type"""
	var type_order = {
		"weapons": 0,
		"armor": 1,
		"shields": 2,
		"accessories": 3
	}
	var a_order = type_order.get(a.get("category", "accessories"), 4)
	var b_order = type_order.get(b.get("category", "accessories"), 4)
	if a_order == b_order:
		return _sort_by_rarity(a, b)  # Secondary sort by rarity
	return a_order < b_order

func _sort_items(items: Array) -> Array:
	"""Sort items based on current _forge_sort_by setting"""
	var sorted_items = items.duplicate()
	match _forge_sort_by:
		"rarity":
			sorted_items.sort_custom(_sort_by_rarity)
		"game":
			sorted_items.sort_custom(_sort_by_game)
		"type":
			sorted_items.sort_custom(_sort_by_type)
		_:
			sorted_items.sort_custom(_sort_by_rarity)
	return sorted_items

func _get_owned_forge_items() -> Array:
	"""Get list of forge items the player owns (from backend)"""
	# Get forged items from ForgeItemManager (pre-computed by backend)
	if ForgeItemManager and ForgeItemManager.is_loaded():
		var forged = ForgeItemManager.get_all_forged_items()
		print("[Forge] Owned items from backend: %d" % forged.size())

		# Enrich with catalog data (icon paths, lore, etc.)
		var enriched = []
		for item in forged:
			var item_id = item.get("item_id", "")
			var catalog_data = _get_catalog_item_by_id(item_id)
			if catalog_data.size() > 0:
				# Merge catalog data with backend data (backend takes precedence)
				var merged = catalog_data.duplicate()
				merged.merge(item, true)  # Backend overwrites catalog
				enriched.append(merged)
			else:
				# No catalog match - use backend data as-is
				enriched.append(item)

		return enriched

	# Not loaded yet - return empty
	print("[Forge] Forged items not loaded yet")
	return []

func _get_catalog_item_by_id(item_id: String) -> Dictionary:
	"""Look up an item in FORGE_CATALOG by its id"""
	for item in FORGE_CATALOG:
		if item.get("id", "") == item_id:
			return item
	return {}

func _get_unclaimed_count() -> int:
	"""Count how many owned forge items haven't been claimed yet"""
	var owned = _get_owned_forge_items()
	var unclaimed = 0
	for item in owned:
		var item_id = item.get("id", item.get("item_id", ""))
		if not ForgeItemManager.is_item_claimed(item_id):
			unclaimed += 1
	return unclaimed

func _on_claim_all_pressed() -> void:
	"""Claim all unclaimed forged items at once"""
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)

	var owned = _get_owned_forge_items()
	var claimed_count = 0

	for item in owned:
		var item_id = item.get("id", item.get("item_id", ""))
		if item_id == "" or ForgeItemManager.is_item_claimed(item_id):
			continue

		var claimed_item = ForgeItemManager.claim_single_item(item_id)
		if not claimed_item.is_empty():
			claimed_count += 1
			print("[Armory] Claimed: %s" % claimed_item.get("name", item_id))

	if claimed_count > 0:
		print("[Armory] Claimed %d items!" % claimed_count)
		# Play success sound
		if SoundManager:
			SoundManager.play_equip_sound(-6.0)
		# Show notification
		if NotificationManager:
			NotificationManager.show_notification("Claimed %d forged items!" % claimed_count)
		# Refresh forge UI
		_refresh_forge_content()
		# Update claim row - hide it or update count
		_update_claim_all_button()
	else:
		print("[Armory] No items to claim")

func _update_claim_all_button() -> void:
	"""Update or hide the CLAIM ALL button based on remaining unclaimed items"""
	var claim_row = find_child("ForgeClaimRow", true, false)
	var claim_btn = find_child("ClaimAllButton", true, false)
	var unclaimed_count = _get_unclaimed_count()

	if unclaimed_count <= 0:
		# All claimed - hide the row entirely
		if claim_row:
			claim_row.visible = false
	else:
		# Still items to claim - update the count
		if claim_btn:
			claim_btn.text = "CLAIM ALL (%d)" % unclaimed_count
		if claim_row:
			claim_row.visible = true

func _style_claim_all_button(btn: Button) -> void:
	"""Style the CLAIM ALL button with green accent"""
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.4, 0.2, 0.9)  # Dark green
	style.border_color = Color(0.3, 0.8, 0.4)  # Bright green border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.2, 0.5, 0.25, 0.95)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.3, 0.15)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(0.9, 1.0, 0.9))
	btn.add_theme_font_size_override("font_size", FONT_TINY)

func _get_current_tier_name() -> String:
	"""Get current tier name from profile"""
	if profile.has("mantle") and profile.mantle.has("tier"):
		return profile.mantle.tier.capitalize()
	return "Initiate"

func _build_dreadland_column() -> Control:
	"""MIDDLE COLUMN: Dreadland game info + action buttons (simplified)"""
	print("[Armory] Building MIDDLE column (Dreadland)")
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(220, 0)

	# Background
	var bg = ColorRect.new()
	bg.name = "MiddleColumnBG"
	bg.color = CARD_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(bg)

	# Border overlay with cyan glow (matches MainMenu)
	var border = PanelContainer.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = BORDER_GLOW
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(8)
	border_style.shadow_size = 20
	border_style.shadow_color = SHADOW_GLOW
	border.add_theme_stylebox_override("panel", border_style)
	wrapper.add_child(border)

	# Content - tighter margins
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	wrapper.add_child(margin)

	# Main vertical container - spread content evenly
	var vbox = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 0)  # Use spacers instead
	margin.add_child(vbox)

	# === GAME TITLE SECTION (compact) ===
	var title_section = VBoxContainer.new()
	title_section.add_theme_constant_override("separation", 2)
	vbox.add_child(title_section)

	var game_icon = Label.new()
	game_icon.text = "☠"
	game_icon.add_theme_font_size_override("font_size", 56)  # Smaller skull
	game_icon.add_theme_color_override("font_color", MANTLE_CYAN)
	game_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_section.add_child(game_icon)

	var game_title = Label.new()
	game_title.text = "DREADLAND"
	game_title.add_theme_font_override("font", default_font)
	game_title.add_theme_font_size_override("font_size", FONT_H2)  # Smaller title
	game_title.add_theme_color_override("font_color", TEXT_PRIMARY)
	game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_section.add_child(game_title)

	var game_subtitle = Label.new()
	game_subtitle.text = "Wasteland Survival"
	game_subtitle.add_theme_font_override("font", default_font)
	game_subtitle.add_theme_font_size_override("font_size", FONT_TINY)
	game_subtitle.add_theme_color_override("font_color", TEXT_DIM)
	game_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_section.add_child(game_subtitle)

	# Divider after title
	vbox.add_child(_create_section_divider())

	# === CHARACTER PREVIEW SECTION (vertically centered) ===
	var spacer1a = Control.new()
	spacer1a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer1a)

	var char_center = CenterContainer.new()
	vbox.add_child(char_center)
	var char_preview_section = _build_character_preview_section()
	char_preview_section.name = "CharPreviewSection"
	char_preview_section.custom_minimum_size = Vector2(220, 0)
	char_center.add_child(char_preview_section)

	var spacer1b = Control.new()
	spacer1b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer1b)

	# Divider after character preview
	vbox.add_child(_create_section_divider())

	# === ACTION BUTTONS SECTION (vertically centered, SWAPPED with game stats) ===
	var spacer2a = Control.new()
	spacer2a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2a)

	var buttons_center = CenterContainer.new()
	vbox.add_child(buttons_center)
	var buttons_vbox = VBoxContainer.new()
	buttons_vbox.add_theme_constant_override("separation", 10)
	buttons_vbox.custom_minimum_size = Vector2(280, 0)
	buttons_center.add_child(buttons_vbox)

	# Enter World button - PRIMARY, prominent with pulse
	enter_world_button = Button.new()
	enter_world_button.name = "EnterWorldBtn"
	enter_world_button.text = "ENTER WORLD"
	enter_world_button.custom_minimum_size = Vector2(0, 56)
	enter_world_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_enter_world_button(enter_world_button)
	enter_world_button.pressed.connect(_on_enter_world_pressed)
	enter_world_button.mouse_entered.connect(_on_enter_button_hover.bind(true))
	enter_world_button.mouse_exited.connect(_on_enter_button_hover.bind(false))
	buttons_vbox.add_child(enter_world_button)
	_start_button_pulse(enter_world_button)

	# Link Accounts button
	var link_button = Button.new()
	link_button.name = "LinkAccountsBtn"
	link_button.text = "LINK ACCOUNTS"
	link_button.custom_minimum_size = Vector2(0, 44)
	link_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_secondary_button(link_button)
	link_button.pressed.connect(_on_link_accounts_pressed)
	buttons_vbox.add_child(link_button)

	# Settings button
	var settings_button = Button.new()
	settings_button.name = "SettingsBtn"
	settings_button.text = "SETTINGS"
	settings_button.custom_minimum_size = Vector2(0, 44)
	settings_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_secondary_button(settings_button)
	settings_button.pressed.connect(_on_settings_pressed)
	buttons_vbox.add_child(settings_button)

	# Logout button - subtle
	logout_button = Button.new()
	logout_button.text = "LOGOUT"
	logout_button.custom_minimum_size = Vector2(0, 36)
	logout_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_logout_button(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)
	logout_button.visible = false
	buttons_vbox.add_child(logout_button)

	var spacer2b = Control.new()
	spacer2b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2b)

	# Divider after buttons
	vbox.add_child(_create_section_divider())

	# === GAME STATS SECTION (vertically centered, SWAPPED from above) ===
	var spacer3a = Control.new()
	spacer3a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer3a)

	var stats_section = _build_game_stats_section()
	stats_section.name = "GameStatsSection"
	vbox.add_child(stats_section)

	# Tagline below stats
	var tagline = Label.new()
	tagline.text = "Achievements unlock cosmetics."
	tagline.add_theme_font_override("font", default_font)
	tagline.add_theme_font_size_override("font_size", FONT_TINY)
	tagline.add_theme_color_override("font_color", TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)

	var spacer3b = Control.new()
	spacer3b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer3b)

	achievements_panel = wrapper
	return wrapper

func _build_character_preview_section() -> Control:
	"""Build a character preview area with animated sprite"""
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	# Character preview container with border
	var preview_container = PanelContainer.new()
	preview_container.name = "CharPreviewContainer"
	preview_container.custom_minimum_size = Vector2(0, 140)
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = BG_DARK
	preview_style.border_color = BORDER_GLOW.darkened(0.3)
	preview_style.set_border_width_all(1)
	preview_style.set_corner_radius_all(6)
	preview_container.add_theme_stylebox_override("panel", preview_style)
	section.add_child(preview_container)

	var preview_center = CenterContainer.new()
	preview_container.add_child(preview_center)

	# Placeholder text (will be replaced with actual sprite)
	var placeholder = VBoxContainer.new()
	placeholder.add_theme_constant_override("separation", 4)
	preview_center.add_child(placeholder)

	var char_icon = Label.new()
	char_icon.name = "CharIcon"
	char_icon.text = "⚔"  # Sword icon as placeholder
	char_icon.add_theme_font_size_override("font_size", 48)
	char_icon.add_theme_color_override("font_color", MANTLE_CYAN.darkened(0.3))
	char_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_child(char_icon)

	var char_text = Label.new()
	char_text.name = "CharText"
	char_text.text = "Your Character"
	char_text.add_theme_font_size_override("font_size", FONT_TINY)
	char_text.add_theme_color_override("font_color", TEXT_DIM)
	char_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_child(char_text)

	return section

func _build_game_stats_section() -> Control:
	"""Build game stats display (playtime, sessions, etc.)"""
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)

	var header = Label.new()
	header.text = "GAME STATS"
	header.add_theme_font_size_override("font_size", FONT_TINY)
	header.add_theme_color_override("font_color", TEXT_DIM)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(header)

	# Center container for the grid
	var center = CenterContainer.new()
	section.add_child(center)

	# Stats grid
	var grid = GridContainer.new()
	grid.name = "StatsGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	center.add_child(grid)

	# Add stat rows
	_add_stat_row(grid, "Time Played", "0h")
	_add_stat_row(grid, "Sessions", "0")
	_add_stat_row(grid, "Last Played", "Never")

	return section

func _add_stat_row(grid: GridContainer, label_text: String, value_text: String) -> void:
	"""Add a stat row to the grid"""
	var label = Label.new()
	label.text = label_text + ":"
	label.add_theme_font_size_override("font_size", FONT_TINY)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	grid.add_child(label)

	var value = Label.new()
	value.name = label_text.replace(" ", "") + "Value"
	value.text = value_text
	value.add_theme_font_size_override("font_size", FONT_TINY)
	value.add_theme_color_override("font_color", TEXT_PRIMARY)
	grid.add_child(value)

func _start_button_pulse(button: Button) -> void:
	"""Add subtle pulse animation to draw attention"""
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(button, "modulate", Color(1.1, 1.1, 1.1), 1.0).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "modulate", Color(1.0, 1.0, 1.0), 1.0).set_ease(Tween.EASE_IN_OUT)

func _on_link_accounts_pressed() -> void:
	"""Open account linking - redirect to Mantle"""
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	if MantleAuth:
		MantleAuth.start_login()
	else:
		OS.shell_open("https://mantle.gg/link")

func _create_mini_teaser(teaser: Dictionary) -> Control:
	"""Create a mini teaser item for the right column"""
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var rarity_color = RARITY_COLORS.get(teaser.get("rarity", "Common"), Color.GRAY)

	# Icon
	var icon = Label.new()
	icon.text = teaser.get("icon", "?")
	icon.add_theme_font_size_override("font_size", 54)
	container.add_child(icon)

	# Text
	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 0)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(text_vbox)

	var item_name = Label.new()
	item_name.text = teaser.get("item", "Unknown")
	item_name.add_theme_font_override("font", default_font)
	item_name.add_theme_font_size_override("font_size", FONT_BODY)
	item_name.add_theme_color_override("font_color", rarity_color)
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_vbox.add_child(item_name)

	var game_label = Label.new()
	game_label.text = teaser.get("game", "")
	game_label.add_theme_font_override("font", default_font)
	game_label.add_theme_font_size_override("font_size", FONT_TINY)
	game_label.add_theme_color_override("font_color", TEXT_DIM)
	game_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_vbox.add_child(game_label)

	container.tooltip_text = "%s\nFrom: %s" % [teaser.get("item", ""), teaser.get("game", "")]

	return container

func _build_left_column() -> Control:
	# Use Control with ColorRect - this approach rendered correctly before
	var wrapper = Control.new()
	wrapper.name = "LeftColumnWrapper"
	wrapper.custom_minimum_size = Vector2(320, 400)  # Compact width

	# Background ColorRect - guaranteed to render
	var bg = ColorRect.new()
	bg.name = "LeftColumnBG"
	bg.color = CARD_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(bg)

	# Content MarginContainer directly in wrapper
	var content = _build_character_preview_content()
	content.name = "CharacterPreviewContent"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(content)

	# Border Panel overlay (on top of content for tier glow effect)
	# Uses BORDER_GLOW as default, will be updated by _apply_tier_border_to_panel for authenticated users
	var border_panel = PanelContainer.new()
	border_panel.name = "LeftColumnBorderPanel"
	border_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	border_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Click through
	var border_style = StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)  # Transparent background
	border_style.border_color = BORDER_GLOW
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(8)
	border_style.shadow_size = 20
	border_style.shadow_color = SHADOW_GLOW
	border_panel.add_theme_stylebox_override("panel", border_style)
	wrapper.add_child(border_panel)

	# Point character_preview to wrapper so find_child can locate all children
	# Point cosmetics_panel to border_panel for tier styling
	character_preview = wrapper
	cosmetics_panel = border_panel

	return wrapper

func _build_character_preview_content() -> Control:
	"""Build the inner content of the character preview (without outer panel)"""
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 20)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	margin.add_child(content)

	# ═══ CHARACTER DISPLAY (compact) ═══
	var char_section = VBoxContainer.new()
	char_section.add_theme_constant_override("separation", 8)
	content.add_child(char_section)

	# Character display area - COMPACT, fixed height
	var char_area = PanelContainer.new()
	char_area.custom_minimum_size = Vector2(0, 180)  # Fixed compact height
	char_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# NO vertical expand - stays at minimum size
	var char_style = StyleBoxFlat.new()
	char_style.bg_color = Color(0.03, 0.03, 0.04)
	char_style.set_corner_radius_all(8)
	char_style.border_color = Color(0.15, 0.15, 0.18)
	char_style.set_border_width_all(1)
	char_area.add_theme_stylebox_override("panel", char_style)
	char_section.add_child(char_area)

	# Placeholder for character sprite
	var char_center = CenterContainer.new()
	char_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	char_area.add_child(char_center)

	var char_placeholder = VBoxContainer.new()
	char_placeholder.add_theme_constant_override("separation", 6)
	char_center.add_child(char_placeholder)

	var char_icon = Label.new()
	char_icon.text = "⚔"
	char_icon.add_theme_font_size_override("font_size", 84)  # Smaller icon
	char_icon.add_theme_color_override("font_color", TEXT_DIM)
	char_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_placeholder.add_child(char_icon)

	var char_text = Label.new()
	char_text.name = "CharacterTierText"
	char_text.text = "Initiate Gear"
	char_text.add_theme_font_size_override("font_size", FONT_BODY_LG)
	char_text.add_theme_color_override("font_color", TEXT_SECONDARY)
	char_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_placeholder.add_child(char_text)

	# Add ambient glow container for tier effects
	var glow_container = Control.new()
	glow_container.name = "TierGlowContainer"
	glow_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_area.add_child(glow_container)

	# Tier effects indicator - below character area
	var effects_label = Label.new()
	effects_label.name = "EffectsLabel"
	effects_label.text = ""
	effects_label.add_theme_font_override("font", default_font)
	effects_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	effects_label.add_theme_color_override("font_color", MANTLE_CYAN)
	effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_section.add_child(effects_label)

	# ═══ EQUIPMENT SECTION (prominent) ═══
	var equip_section = VBoxContainer.new()
	equip_section.add_theme_constant_override("separation", 12)
	equip_section.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Equipment expands
	content.add_child(equip_section)

	var equip_header = Label.new()
	equip_header.text = "EQUIPMENT"
	equip_header.add_theme_font_override("font", default_font)
	equip_header.add_theme_font_size_override("font_size", FONT_BODY)
	equip_header.add_theme_color_override("font_color", MANTLE_CYAN)
	equip_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_section.add_child(equip_header)

	# 2x3 Equipment Grid - centered and prominent
	var grid_center = CenterContainer.new()
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_section.add_child(grid_center)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid_center.add_child(grid)

	var slot_names = ["Head", "Chest", "Weapon", "Legs", "Boots", "Arms"]
	for slot_name in slot_names:
		var slot = _create_cosmetic_slot(slot_name)
		grid.add_child(slot)

	return margin

func _build_middle_column() -> Control:
	# Outer container - align to TOP like other columns
	var outer = VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN  # Top aligned

	stats_panel = PanelContainer.new()
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(stats_panel, CARD_BG)
	outer.add_child(stats_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 25)
	stats_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)  # More separation between rows
	margin.add_child(vbox)

	# ═══ TOP ROW: Achievement number centered, username top-right ═══
	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(top_row)

	# Tier badge on left (wrapped to prevent vertical stretching)
	var badge_wrapper = VBoxContainer.new()
	badge_wrapper.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_child(badge_wrapper)
	tier_badge = _create_tier_badge("initiate")
	badge_wrapper.add_child(tier_badge)

	# Center spacer + achievement number
	var center_section = VBoxContainer.new()
	center_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_section.add_theme_constant_override("separation", 2)
	top_row.add_child(center_section)

	# Centered number
	total_label = Label.new()
	total_label.text = "0"
	total_label.add_theme_font_override("font", default_font)
	total_label.add_theme_font_size_override("font_size", 84)
	total_label.add_theme_color_override("font_color", MANTLE_RED)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_section.add_child(total_label)

	var total_suffix = Label.new()
	total_suffix.name = "TotalSuffix"
	total_suffix.text = "TOTAL ACHIEVEMENTS"
	total_suffix.add_theme_font_override("font", default_font)
	total_suffix.add_theme_font_size_override("font_size", FONT_TINY)
	total_suffix.add_theme_color_override("font_color", MANTLE_RED)
	total_suffix.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_section.add_child(total_suffix)

	# Username on right - wrapped to anchor to top-right corner
	var username_wrapper = VBoxContainer.new()
	username_wrapper.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_child(username_wrapper)

	username_label = Label.new()
	username_label.text = "Guest"
	username_label.add_theme_font_override("font", default_font)
	username_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	username_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	username_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	username_wrapper.add_child(username_label)

	# Separator
	vbox.add_child(_create_separator())

	# ═══ PROVIDER ACHIEVEMENT COUNTS (big badges) ═══
	var platforms_row = HBoxContainer.new()
	platforms_row.name = "PlatformsRow"
	platforms_row.add_theme_constant_override("separation", 12)
	platforms_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(platforms_row)

	var no_platforms = Label.new()
	no_platforms.name = "NoPlatformsLabel"
	no_platforms.text = "No platforms linked"
	no_platforms.add_theme_font_size_override("font_size", FONT_BODY_LG)
	no_platforms.add_theme_color_override("font_color", TEXT_SECONDARY)
	platforms_row.add_child(no_platforms)

	# Separator
	vbox.add_child(_create_separator())

	# ═══ RARITY GEMS ═══
	var rarity_row = HBoxContainer.new()
	rarity_row.name = "RarityRow"
	rarity_row.add_theme_constant_override("separation", 28)  # Much more spacing between gems
	rarity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(rarity_row)

	# Separator
	vbox.add_child(_create_separator())

	# ═══ PROGRESS BAR ═══
	var progress_section = _create_progress_section()
	progress_section.name = "ProgressSection"
	vbox.add_child(progress_section)

	# ═══ ACTION BUTTONS (below stats panel) ═══
	var buttons_row = HBoxContainer.new()
	buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_row.add_theme_constant_override("separation", 20)
	outer.add_child(buttons_row)

	# Spacer above buttons
	var button_spacer = Control.new()
	button_spacer.custom_minimum_size = Vector2(0, 15)
	outer.move_child(button_spacer, 1)
	outer.add_child(button_spacer)
	outer.move_child(button_spacer, outer.get_child_count() - 2)

	# Enter World button - GREEN
	enter_world_button = Button.new()
	enter_world_button.text = "ENTER WORLD"
	enter_world_button.custom_minimum_size = Vector2(180, 44)
	enter_world_button.pivot_offset = Vector2(90, 22)
	_style_enter_world_button(enter_world_button)
	enter_world_button.pressed.connect(_on_enter_world_pressed)
	enter_world_button.mouse_entered.connect(_on_enter_button_hover.bind(true))
	enter_world_button.mouse_exited.connect(_on_enter_button_hover.bind(false))
	buttons_row.add_child(enter_world_button)

	# Logout button - RED (same size/style as Enter World)
	logout_button = Button.new()
	logout_button.text = "LOGOUT"
	logout_button.custom_minimum_size = Vector2(120, 44)
	_style_logout_button(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)
	logout_button.visible = false
	buttons_row.add_child(logout_button)

	return outer

func _create_quick_stats_section() -> Control:
	var section = VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)

	# Stats grid - 2 columns, no header like web
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	grid.name = "QuickStatsGrid"
	section.add_child(grid)

	# Compact stats
	var stats = [
		{"label": "Games", "value": "0", "icon": "🎮"},
		{"label": "Rarest", "value": "-", "icon": "💎"},
		{"label": "Level", "value": "-", "icon": "📊"},
		{"label": "Rank", "value": "-", "icon": "🏆"},
	]

	for stat in stats:
		var stat_item = _create_stat_item(stat)
		grid.add_child(stat_item)

	return section

func _create_stat_item(stat: Dictionary) -> Control:
	var container = HBoxContainer.new()
	container.name = "Stat_" + stat.get("label", "").replace(" ", "")
	container.add_theme_constant_override("separation", 6)

	var icon = Label.new()
	icon.text = stat.get("icon", "")
	icon.add_theme_font_size_override("font_size", FONT_BODY_LG)
	container.add_child(icon)

	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	container.add_child(info)

	var value_label = Label.new()
	value_label.name = "Value"
	value_label.text = stat.get("value", "-")
	value_label.add_theme_font_override("font", default_font)
	value_label.add_theme_font_size_override("font_size", FONT_BODY)
	value_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	info.add_child(value_label)

	var name_label = Label.new()
	name_label.text = stat.get("label", "")
	name_label.add_theme_font_override("font", default_font)
	name_label.add_theme_font_size_override("font_size", FONT_TINY)
	name_label.add_theme_color_override("font_color", TEXT_DIM)
	info.add_child(name_label)

	return container

func _build_right_column() -> Control:
	# Outer container to align content to top
	var outer = VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	# Don't expand - let content determine size
	column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	outer.add_child(column)

	# THE FORGE - Primary action area
	forged_panel = _build_forge_section()
	forged_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(forged_panel)

	# Notable Achievements - Shows what's unlockable (auto-shrink to content)
	achievements_panel = _build_achievements_panel()
	achievements_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Don't expand vertically - shrink to fit content
	column.add_child(achievements_panel)

	return outer

func _build_right_column_combined() -> Control:
	"""Combined right column: Stats panel (top) + Forge + Achievements, with buttons at bottom"""
	var outer = VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 15)  # Tighter spacing

	# ═══ STATS PANEL (Achievement counts, providers, rarity, progress) ═══
	stats_panel = PanelContainer.new()
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(stats_panel, CARD_BG)
	outer.add_child(stats_panel)

	var stats_margin = MarginContainer.new()
	stats_margin.add_theme_constant_override("margin_left", 20)
	stats_margin.add_theme_constant_override("margin_right", 20)
	stats_margin.add_theme_constant_override("margin_top", 15)
	stats_margin.add_theme_constant_override("margin_bottom", 18)
	stats_panel.add_child(stats_margin)

	var stats_vbox = VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 12)  # Tighter
	stats_margin.add_child(stats_vbox)

	# TOP ROW: Tier badge left, total achievements center, username right
	var top_row = HBoxContainer.new()
	top_row.name = "TopRow"
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	stats_vbox.add_child(top_row)

	# Tier badge on left (wrapped to prevent vertical stretching)
	var badge_wrapper = VBoxContainer.new()
	badge_wrapper.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_child(badge_wrapper)
	tier_badge = _create_tier_badge("initiate")
	badge_wrapper.add_child(tier_badge)

	# Center spacer + achievement number
	var center_section = VBoxContainer.new()
	center_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_section.add_theme_constant_override("separation", 2)
	top_row.add_child(center_section)

	# Centered number
	total_label = Label.new()
	total_label.text = "0"
	total_label.add_theme_font_override("font", default_font)
	total_label.add_theme_font_size_override("font_size", 64)  # Slightly smaller
	total_label.add_theme_color_override("font_color", MANTLE_RED)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_section.add_child(total_label)

	var total_suffix = Label.new()
	total_suffix.name = "TotalSuffix"
	total_suffix.text = "TOTAL ACHIEVEMENTS"
	total_suffix.add_theme_font_override("font", default_font)
	total_suffix.add_theme_font_size_override("font_size", FONT_TINY)
	total_suffix.add_theme_color_override("font_color", MANTLE_RED)
	total_suffix.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_section.add_child(total_suffix)

	# Username on right - wrapped to anchor to top-right corner
	var username_wrapper = VBoxContainer.new()
	username_wrapper.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.add_child(username_wrapper)

	username_label = Label.new()
	username_label.text = "Guest"
	username_label.add_theme_font_override("font", default_font)
	username_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	username_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	username_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	username_wrapper.add_child(username_label)

	# Separator
	stats_vbox.add_child(_create_separator())

	# PROVIDER ACHIEVEMENT COUNTS (big badges)
	var platforms_row = HBoxContainer.new()
	platforms_row.name = "PlatformsRow"
	platforms_row.add_theme_constant_override("separation", 12)
	platforms_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_vbox.add_child(platforms_row)

	var no_platforms = Label.new()
	no_platforms.name = "NoPlatformsLabel"
	no_platforms.text = "No platforms linked"
	no_platforms.add_theme_font_size_override("font_size", FONT_BODY_LG)
	no_platforms.add_theme_color_override("font_color", TEXT_SECONDARY)
	platforms_row.add_child(no_platforms)

	# Separator
	stats_vbox.add_child(_create_separator())

	# RARITY GEMS
	var rarity_row = HBoxContainer.new()
	rarity_row.name = "RarityRow"
	rarity_row.add_theme_constant_override("separation", 28)
	rarity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_vbox.add_child(rarity_row)

	# Separator
	stats_vbox.add_child(_create_separator())

	# PROGRESS BAR
	var progress_section = _create_progress_section()
	progress_section.name = "ProgressSection"
	stats_vbox.add_child(progress_section)

	# ═══ ACTION BUTTONS (below stats) ═══
	var buttons_row = HBoxContainer.new()
	buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_row.add_theme_constant_override("separation", 20)
	outer.add_child(buttons_row)

	# Enter World button - GREEN
	enter_world_button = Button.new()
	enter_world_button.text = "ENTER WORLD"
	enter_world_button.custom_minimum_size = Vector2(180, 44)
	enter_world_button.pivot_offset = Vector2(90, 22)
	_style_enter_world_button(enter_world_button)
	enter_world_button.pressed.connect(_on_enter_world_pressed)
	enter_world_button.mouse_entered.connect(_on_enter_button_hover.bind(true))
	enter_world_button.mouse_exited.connect(_on_enter_button_hover.bind(false))
	buttons_row.add_child(enter_world_button)

	# Logout button - RED (same size/style as Enter World)
	logout_button = Button.new()
	logout_button.text = "LOGOUT"
	logout_button.custom_minimum_size = Vector2(120, 44)
	_style_logout_button(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)
	logout_button.visible = false
	buttons_row.add_child(logout_button)

	# ═══ THE FORGE ═══
	forged_panel = _build_forge_section()
	forged_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(forged_panel)

	# ═══ UNLOCK WITH ACHIEVEMENTS ═══
	achievements_panel = _build_achievements_panel()
	achievements_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievements_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(achievements_panel)

	return outer

func _build_forge_section() -> Control:
	var panel = PanelContainer.new()
	_style_panel(panel, CARD_BG)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header with large icon - centered
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header_row)

	var forge_icon = Label.new()
	forge_icon.text = "⚒"
	forge_icon.add_theme_font_size_override("font_size", FONT_H1)
	forge_icon.add_theme_color_override("font_color", MANTLE_CYAN)
	header_row.add_child(forge_icon)

	var header = Label.new()
	header.text = "THE FORGE"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_H2)
	header.add_theme_color_override("font_color", MANTLE_CYAN)
	header_row.add_child(header)


	# Visual: Anvil/forge area with glow
	var forge_visual = PanelContainer.new()
	forge_visual.custom_minimum_size = Vector2(0, 60)
	var forge_style = StyleBoxFlat.new()
	forge_style.bg_color = Color(0.08, 0.04, 0.02, 0.5)  # Warm, forge-like color
	forge_style.border_color = Color(1.0, 0.5, 0.2, 0.3)  # Orange glow border
	forge_style.set_border_width_all(1)
	forge_style.set_corner_radius_all(8)
	forge_visual.add_theme_stylebox_override("panel", forge_style)
	vbox.add_child(forge_visual)

	var forge_center = CenterContainer.new()
	forge_visual.add_child(forge_center)

	var forge_content = HBoxContainer.new()
	forge_content.add_theme_constant_override("separation", 15)
	forge_center.add_child(forge_content)

	# Large fire/anvil icon
	var anvil_icon = Label.new()
	anvil_icon.text = "🔥"
	anvil_icon.add_theme_font_size_override("font_size", 54)
	forge_content.add_child(anvil_icon)

	# Pending count
	var pending_vbox = VBoxContainer.new()
	pending_vbox.add_theme_constant_override("separation", 2)
	forge_content.add_child(pending_vbox)

	var pending_label = Label.new()
	pending_label.name = "PendingLabel"
	pending_label.text = "0"
	pending_label.add_theme_font_override("font", default_font)
	pending_label.add_theme_font_size_override("font_size", FONT_H1)
	pending_label.add_theme_color_override("font_color", Color.ORANGE)
	pending_vbox.add_child(pending_label)

	var pending_sub = Label.new()
	pending_sub.name = "PendingSub"
	pending_sub.text = "items ready to claim"
	pending_sub.add_theme_font_override("font", default_font)
	pending_sub.add_theme_font_size_override("font_size", FONT_TINY)
	pending_sub.add_theme_color_override("font_color", TEXT_SECONDARY)
	pending_vbox.add_child(pending_sub)

	# Open Forge button
	var open_forge_btn = Button.new()
	open_forge_btn.name = "OpenForgeBtn"
	open_forge_btn.text = "OPEN FORGE"
	open_forge_btn.custom_minimum_size = Vector2(0, 38)
	open_forge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_forge_button(open_forge_btn)
	open_forge_btn.pressed.connect(_on_open_forge_pressed)
	vbox.add_child(open_forge_btn)

	# Browse forgeable link - CYAN for visibility
	var browse_btn = Button.new()
	browse_btn.name = "BrowseForgeableBtn"
	browse_btn.text = "Browse Forgeable Achievements →"
	browse_btn.add_theme_font_override("font", default_font)
	browse_btn.add_theme_font_size_override("font_size", FONT_BODY)
	browse_btn.add_theme_color_override("font_color", MANTLE_CYAN)  # Cyan for readability
	browse_btn.add_theme_color_override("font_hover_color", MANTLE_CYAN.lightened(0.3))
	var empty_style = StyleBoxEmpty.new()
	browse_btn.add_theme_stylebox_override("normal", empty_style)
	browse_btn.add_theme_stylebox_override("hover", empty_style)
	browse_btn.add_theme_stylebox_override("pressed", empty_style)
	browse_btn.pressed.connect(_on_browse_forgeable_pressed)
	browse_btn.mouse_entered.connect(_play_button_hover_sound)  # Add hover sound
	vbox.add_child(browse_btn)

	return panel

func _style_forge_button(button: Button) -> void:
	button.add_theme_font_override("font", default_font)
	button.add_theme_font_size_override("font_size", FONT_BODY_LG)
	button.add_theme_color_override("font_color", Color.WHITE)
	# Connect hover sound
	button.mouse_entered.connect(_play_button_hover_sound)

	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.12, 0.08)
	normal.border_color = Color(0.8, 0.5, 0.2)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.18, 0.1)
	hover.border_color = Color(1.0, 0.6, 0.2)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.shadow_color = Color(1.0, 0.5, 0.1, 0.3)
	hover.shadow_size = 4
	button.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = Color(0.1, 0.08, 0.05)
	pressed.border_color = Color(0.6, 0.4, 0.15)
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	button.add_theme_stylebox_override("pressed", pressed)

func _create_separator() -> Control:
	# Subtle spacer instead of visible line
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	return spacer

func _build_cosmetics_grid() -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, CARD_BG)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header = Label.new()
	header.text = "EQUIPPED"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_BODY)
	header.add_theme_color_override("font_color", TEXT_SECONDARY)  # Brighter
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# 2x3 Grid
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	var slot_names = ["Head", "Chest", "Weapon", "Legs", "Boots", "Arms"]
	for slot_name in slot_names:
		var slot = _create_cosmetic_slot(slot_name)
		grid.add_child(slot)

	return panel

func _build_header(parent: Control) -> void:
	var header_panel = PanelContainer.new()
	_style_panel(header_panel, CARD_BG)
	parent.add_child(header_panel)

	var header_margin = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 40)
	header_margin.add_theme_constant_override("margin_right", 40)
	header_margin.add_theme_constant_override("margin_top", 12)
	header_margin.add_theme_constant_override("margin_bottom", 12)
	header_panel.add_child(header_margin)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 4)
	header_margin.add_child(header_vbox)

	title_label = Label.new()
	title_label.text = "MANTLE ARMORY"
	title_label.add_theme_font_size_override("font_size", FONT_H1)
	title_label.add_theme_color_override("font_color", MANTLE_CYAN)
	title_label.add_theme_color_override("font_outline_color", Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.3))
	title_label.add_theme_constant_override("outline_size", 2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_vbox.add_child(title_label)

	# Add subtle glow behind title
	var title_glow = Label.new()
	title_glow.text = "MANTLE ARMORY"
	title_glow.add_theme_font_size_override("font_size", FONT_H1)
	title_glow.add_theme_color_override("font_color", Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.15))
	title_glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_glow.position = Vector2(2, 2)
	title_glow.z_index = -1
	title_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_vbox.add_child(title_glow)
	header_vbox.move_child(title_glow, 0)

	subtitle_label = Label.new()
	subtitle_label.text = "Your Gaming Legacy"
	subtitle_label.add_theme_font_size_override("font_size", FONT_BODY)
	subtitle_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_vbox.add_child(subtitle_label)

func _build_stats_bar(parent: Control) -> void:
	"""Horizontal stats bar: badge | count | providers | rarity | progress | username"""
	stats_panel = PanelContainer.new()
	_style_panel(stats_panel, CARD_BG)
	parent.add_child(stats_panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	stats_panel.add_child(margin)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 25)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(hbox)

	# Tier badge
	tier_badge = _create_tier_badge("initiate")
	hbox.add_child(tier_badge)

	# Total achievements (compact)
	var total_section = VBoxContainer.new()
	total_section.add_theme_constant_override("separation", 0)
	hbox.add_child(total_section)

	total_label = Label.new()
	total_label.text = "0"
	total_label.add_theme_font_override("font", default_font)
	total_label.add_theme_font_size_override("font_size", 72)
	total_label.add_theme_color_override("font_color", MANTLE_RED)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_section.add_child(total_label)

	var total_suffix = Label.new()
	total_suffix.name = "TotalSuffix"
	total_suffix.text = "achievements"
	total_suffix.add_theme_font_override("font", default_font)
	total_suffix.add_theme_font_size_override("font_size", FONT_TINY)
	total_suffix.add_theme_color_override("font_color", TEXT_DIM)
	total_suffix.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_section.add_child(total_suffix)

	# Separator
	hbox.add_child(_create_vertical_separator())

	# Provider badges (horizontal)
	var platforms_row = HBoxContainer.new()
	platforms_row.name = "PlatformsRow"
	platforms_row.add_theme_constant_override("separation", 8)
	hbox.add_child(platforms_row)

	var no_platforms = Label.new()
	no_platforms.name = "NoPlatformsLabel"
	no_platforms.text = "No platforms"
	no_platforms.add_theme_font_size_override("font_size", FONT_CAPTION)
	no_platforms.add_theme_color_override("font_color", TEXT_DIM)
	platforms_row.add_child(no_platforms)

	# Separator
	hbox.add_child(_create_vertical_separator())

	# Rarity gems (horizontal, compact)
	var rarity_row = HBoxContainer.new()
	rarity_row.name = "RarityRow"
	rarity_row.add_theme_constant_override("separation", 12)
	hbox.add_child(rarity_row)

	# Separator
	hbox.add_child(_create_vertical_separator())

	# Progress to next tier (compact)
	var progress_section = HBoxContainer.new()
	progress_section.add_theme_constant_override("separation", 8)
	hbox.add_child(progress_section)

	var progress_bar = ProgressBar.new()
	progress_bar.name = "TierProgressBar"
	progress_bar.custom_minimum_size = Vector2(120, 8)
	progress_bar.value = 0
	progress_bar.show_percentage = false
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.15, 0.15, 0.18)
	bar_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("background", bar_style)
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = TIER_COLORS["initiate"]
	fill_style.set_corner_radius_all(4)
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	progress_section.add_child(progress_bar)

	var next_tier_label = Label.new()
	next_tier_label.name = "NextTierLabel"
	next_tier_label.text = "→ Bronze"
	next_tier_label.add_theme_font_override("font", default_font)
	next_tier_label.add_theme_font_size_override("font_size", FONT_TINY)
	next_tier_label.add_theme_color_override("font_color", TIER_COLORS["bronze"])
	progress_section.add_child(next_tier_label)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Username (right side)
	username_label = Label.new()
	username_label.text = "Guest"
	username_label.add_theme_font_override("font", default_font)
	username_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	username_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	hbox.add_child(username_label)

func _create_vertical_separator() -> Control:
	var sep = ColorRect.new()
	sep.custom_minimum_size = Vector2(1, 30)
	sep.color = Color(0.3, 0.3, 0.35, 0.5)
	return sep

func _build_right_column_widescreen() -> Control:
	"""Widescreen right column: Achievements grid + Buttons"""
	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 20)

	# Achievement unlocks panel
	achievements_panel = PanelContainer.new()
	achievements_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	achievements_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_panel(achievements_panel, CARD_BG)
	outer.add_child(achievements_panel)

	var ach_margin = MarginContainer.new()
	ach_margin.add_theme_constant_override("margin_left", 25)
	ach_margin.add_theme_constant_override("margin_right", 25)
	ach_margin.add_theme_constant_override("margin_top", 20)
	ach_margin.add_theme_constant_override("margin_bottom", 20)
	achievements_panel.add_child(ach_margin)

	var ach_vbox = VBoxContainer.new()
	ach_vbox.add_theme_constant_override("separation", 15)
	ach_margin.add_child(ach_vbox)

	var header = Label.new()
	header.text = "UNLOCK WITH ACHIEVEMENTS"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_BODY_LG)
	header.add_theme_color_override("font_color", MANTLE_CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ach_vbox.add_child(header)

	var subheader = Label.new()
	subheader.name = "AchievementsSubheader"
	subheader.text = "Legendary achievements become legendary gear"
	subheader.add_theme_font_override("font", default_font)
	subheader.add_theme_font_size_override("font_size", FONT_CAPTION)
	subheader.add_theme_color_override("font_color", TEXT_DIM)
	subheader.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ach_vbox.add_child(subheader)

	# Horizontal achievement teasers - 6 items in 2 rows of 3
	var teaser_container = GridContainer.new()
	teaser_container.name = "TeaserContainer"
	teaser_container.columns = 3  # 3 columns for widescreen
	teaser_container.add_theme_constant_override("h_separation", 15)
	teaser_container.add_theme_constant_override("v_separation", 12)
	teaser_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_vbox.add_child(teaser_container)

	# 6 well-known achievements
	var teasers = [
		{"item": "Coiled Sword", "game": "Dark Souls III", "rarity": "Legendary", "icon": "🗡"},
		{"item": "Elden Crown", "game": "Elden Ring", "rarity": "Legendary", "icon": "👑"},
		{"item": "Thunderfury", "game": "WoW", "rarity": "Legendary", "icon": "⚡"},
		{"item": "Master Sword", "game": "Zelda", "rarity": "Legendary", "icon": "⚔"},
		{"item": "Keyblade", "game": "Kingdom Hearts", "rarity": "Legendary", "icon": "🗝"},
		{"item": "Buster Sword", "game": "FF VII", "rarity": "Legendary", "icon": "⚔"},
	]

	for teaser in teasers:
		var item = _create_compact_teaser(teaser)
		teaser_container.add_child(item)

	# Buttons row at bottom
	var buttons_row = HBoxContainer.new()
	buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_row.add_theme_constant_override("separation", 20)
	outer.add_child(buttons_row)

	# Enter World button - GREEN
	enter_world_button = Button.new()
	enter_world_button.text = "ENTER WORLD"
	enter_world_button.custom_minimum_size = Vector2(200, 50)
	enter_world_button.pivot_offset = Vector2(100, 25)
	_style_enter_world_button(enter_world_button)
	enter_world_button.pressed.connect(_on_enter_world_pressed)
	enter_world_button.mouse_entered.connect(_on_enter_button_hover.bind(true))
	enter_world_button.mouse_exited.connect(_on_enter_button_hover.bind(false))
	buttons_row.add_child(enter_world_button)

	# Logout button
	logout_button = Button.new()
	logout_button.text = "LOGOUT"
	logout_button.custom_minimum_size = Vector2(140, 50)
	_style_logout_button(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)
	logout_button.visible = false
	buttons_row.add_child(logout_button)

	return outer

func _apply_tier_accents(tier_key: String) -> void:
	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])
	print("[Armory] _apply_tier_accents called with tier: ", tier_key)

	# Only apply accents for gold tier and above
	if tier_key not in ["gold", "platinum", "diamond", "legendary", "mythic"]:
		print("[Armory]   Skipping accents - tier not high enough")
		return

	# Accent intensity based on tier - subtle borders only, minimal glow
	var border_alpha = 0.25
	var glow_intensity = 0.0  # No glow by default
	match tier_key:
		"gold":
			border_alpha = 0.25
			glow_intensity = 0.0
		"platinum":
			border_alpha = 0.30
			glow_intensity = 0.0
		"diamond":
			border_alpha = 0.35
			glow_intensity = 0.0
		"legendary":
			border_alpha = 0.45
			glow_intensity = 0.05  # Very subtle glow
		"mythic":
			border_alpha = 0.55
			glow_intensity = 0.08  # Subtle glow

	print("[Armory]   Applying tier accents with glow_intensity: ", glow_intensity)

	# Apply tier accent to stats panel (find child PanelContainer if wrapper is Control)
	if stats_panel:
		var panel = _find_border_panel(stats_panel)
		if panel:
			print("[Armory]   ✓ Found stats_panel (LEFT), applying glow")
			_apply_tier_border_to_panel(panel, color, border_alpha, glow_intensity)
		else:
			print("[Armory]   ✗ stats_panel exists but no border panel found")
	else:
		print("[Armory]   ✗ stats_panel is null")

	# Apply tier accent to character preview border panel
	if cosmetics_panel:
		var panel = _find_border_panel(cosmetics_panel)
		if panel:
			print("[Armory]   ✓ Found cosmetics_panel (MIDDLE), applying glow")
			_apply_tier_border_to_panel(panel, color, border_alpha, glow_intensity)
		else:
			print("[Armory]   ✗ cosmetics_panel exists but no border panel found")
	else:
		print("[Armory]   ✗ cosmetics_panel is null")

	# Apply tier accent to achievements panel - SAME intensity as others for consistency
	if achievements_panel:
		var panel = _find_border_panel(achievements_panel)
		if panel:
			print("[Armory]   ✓ Found achievements_panel (RIGHT), applying glow")
			_apply_tier_border_to_panel(panel, color, border_alpha, glow_intensity)
		else:
			print("[Armory]   ✗ achievements_panel exists but no border panel found")
	else:
		print("[Armory]   ✗ achievements_panel is null")

	# Update equipment slot borders to tier color
	_update_equipment_slot_tier_accents(tier_key, color)

func _find_border_panel(control: Control) -> PanelContainer:
	"""Find a PanelContainer for border styling - either the control itself or a child"""
	if control is PanelContainer:
		return control as PanelContainer
	# Look for child PanelContainer (border overlay)
	for child in control.get_children():
		if child is PanelContainer:
			return child as PanelContainer
	return null

func _apply_tier_border_to_panel(panel: PanelContainer, color: Color, border_alpha: float, glow_intensity: float) -> void:
	# Check if this panel should have transparent background (border overlay panels)
	var current_style = panel.get_theme_stylebox("panel")
	var keep_transparent = false
	if current_style is StyleBoxFlat and current_style.bg_color.a < 0.1:
		keep_transparent = true

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0) if keep_transparent else CARD_BG
	style.border_color = Color(color.r, color.g, color.b, border_alpha)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)

	# Add subtle glow for higher tiers
	if glow_intensity > 0.1:
		style.shadow_color = Color(color.r, color.g, color.b, glow_intensity)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 0)

	panel.add_theme_stylebox_override("panel", style)

func _update_equipment_slot_tier_accents(tier_key: String, color: Color) -> void:
	if not character_preview:
		return

	# Find all slot backgrounds and update their hover styles (search in wrapper)
	var slot_names = ["Head", "Chest", "Weapon", "Legs", "Boots", "Arms"]
	for slot_name in slot_names:
		var slot_bg = character_preview.find_child("SlotBG_" + slot_name, true, false)
		if slot_bg and slot_bg is PanelContainer:
			# Update hover style to use tier color
			var hover_style = StyleBoxFlat.new()
			hover_style.bg_color = Color(0.08, 0.085, 0.10)
			hover_style.border_color = Color(color.r, color.g, color.b, 0.6)
			hover_style.set_border_width_all(2)
			hover_style.set_corner_radius_all(6)
			hover_style.shadow_color = Color(color.r, color.g, color.b, 0.35)
			hover_style.shadow_size = 4
			slot_bg.set_meta("hover_style", hover_style)

			# Update tooltip to reflect tier
			slot_bg.tooltip_text = "%s - %s tier gear equipped" % [slot_name, tier_key.capitalize()]

func _add_tier_glow_effect(tier_key: String) -> void:
	if not character_preview:
		return

	var glow_container = character_preview.find_child("TierGlowContainer", true, false)
	if not glow_container:
		return

	# Clear existing effects
	for child in glow_container.get_children():
		child.queue_free()

	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	# Only add subtle ambient glow for gold tier and above
	if tier_key in ["gold", "platinum", "diamond", "legendary", "mythic"]:
		# Create subtle ambient glow overlay
		var glow = ColorRect.new()
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.color = Color(color.r, color.g, color.b, 0.0)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow_container.add_child(glow)

		# Animate with subtle breathing effect
		var tween = create_tween()
		tween.set_loops()
		var base_alpha = 0.03 if tier_key == "gold" else 0.05 if tier_key == "platinum" else 0.06 if tier_key == "diamond" else 0.08
		var peak_alpha = base_alpha + 0.03
		tween.tween_property(glow, "color:a", peak_alpha, 2.0).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(glow, "color:a", base_alpha, 2.0).set_ease(Tween.EASE_IN_OUT)

func _create_tier_badge(tier_key: String) -> Control:
	var badge = PanelContainer.new()
	badge.name = "TierBadgePanel"
	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	# Enhanced glow effect for premium feel
	style.shadow_color = Color(color.r, color.g, color.b, 0.6)
	style.shadow_size = 12
	style.border_color = color.lightened(0.3)
	style.set_border_width_all(1)
	badge.add_theme_stylebox_override("panel", style)
	badge.set_meta("style", style)

	tier_label = Label.new()
	tier_label.text = tier_key.to_upper()
	tier_label.add_theme_font_size_override("font_size", FONT_BODY)
	# Dark text for light tiers
	if tier_key in ["gold", "silver", "platinum", "diamond"]:
		tier_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	else:
		tier_label.add_theme_color_override("font_color", Color.WHITE)
	badge.add_child(tier_label)

	return badge

func _create_progress_section() -> Control:
	var section = VBoxContainer.new()
	section.name = "ProgressSection"
	section.add_theme_constant_override("separation", 8)

	# Tier thresholds for marker positions (logarithmic scale for better UX)
	# We'll use relative positions along the bar
	var tier_thresholds = {
		"initiate": 0,
		"bronze": 100,
		"silver": 500,
		"gold": 1000,
		"platinum": 2500,
		"diamond": 5000,
		"legendary": 10000,
		"mythic": 25000
	}

	# Progress bar with current/target values
	var bar_row = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	section.add_child(bar_row)

	var progress_current = Label.new()
	progress_current.name = "ProgressCurrent"
	progress_current.text = "0"
	progress_current.add_theme_font_override("font", default_font)
	progress_current.add_theme_font_size_override("font_size", FONT_TINY)
	progress_current.add_theme_color_override("font_color", TEXT_DIM)
	bar_row.add_child(progress_current)

	# Progress bar container with tier markers
	var bar_wrapper = VBoxContainer.new()
	bar_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_wrapper.add_theme_constant_override("separation", 4)
	bar_row.add_child(bar_wrapper)

	# Main progress bar
	var bar_bg = PanelContainer.new()
	bar_bg.name = "ProgressBarBG"
	bar_bg.custom_minimum_size = Vector2(0, 12)
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = BG_DARK
	bar_style.set_corner_radius_all(6)
	bar_bg.add_theme_stylebox_override("panel", bar_style)
	bar_wrapper.add_child(bar_bg)

	# Progress fill
	var bar_fill = ColorRect.new()
	bar_fill.name = "ProgressFill"
	bar_fill.color = TIER_COLORS["initiate"]
	bar_fill.custom_minimum_size = Vector2(0, 10)
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.offset_top = 1
	bar_fill.offset_bottom = -1
	bar_fill.offset_left = 1
	bar_bg.add_child(bar_fill)

	# Tier markers row (dots below the bar)
	var markers_row = HBoxContainer.new()
	markers_row.name = "TierMarkersRow"
	markers_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_wrapper.add_child(markers_row)

	# Create tier marker dots
	var tier_order = ["initiate", "bronze", "silver", "gold", "platinum", "diamond", "legendary", "mythic"]
	for i in range(tier_order.size()):
		var tier_key = tier_order[i]
		var marker = _create_tier_marker(tier_key, tier_key.capitalize())
		markers_row.add_child(marker)

		# Add spacer between markers (except after last)
		if i < tier_order.size() - 1:
			var spacer = Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			markers_row.add_child(spacer)

	# Target/max value
	var progress_target = Label.new()
	progress_target.name = "ProgressTarget"
	progress_target.text = "100"
	progress_target.add_theme_font_override("font", default_font)
	progress_target.add_theme_font_size_override("font_size", FONT_TINY)
	progress_target.add_theme_color_override("font_color", TEXT_DIM)
	bar_row.add_child(progress_target)

	# Next tier info row
	var next_tier_row = HBoxContainer.new()
	next_tier_row.alignment = BoxContainer.ALIGNMENT_END
	section.add_child(next_tier_row)

	var next_tier_label = Label.new()
	next_tier_label.name = "NextTierLabel"
	next_tier_label.text = "Bronze"
	next_tier_label.add_theme_font_override("font", default_font)
	next_tier_label.add_theme_font_size_override("font_size", FONT_TINY)
	next_tier_label.add_theme_color_override("font_color", TIER_COLORS["bronze"])
	next_tier_row.add_child(next_tier_label)

	# Description below
	var progress_text = Label.new()
	progress_text.name = "ProgressText"
	progress_text.text = "Reach 100 achievements to unlock Bronze tier"
	progress_text.add_theme_font_override("font", default_font)
	progress_text.add_theme_font_size_override("font_size", FONT_TINY)
	progress_text.add_theme_color_override("font_color", TEXT_DIM)
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(progress_text)

	return section

func _create_tier_marker(tier_key: String, tier_name: String) -> Control:
	"""Create a small tier marker dot with tooltip"""
	var container = VBoxContainer.new()
	container.name = "TierMarker_" + tier_key
	container.add_theme_constant_override("separation", 2)

	# Colored dot
	var dot = ColorRect.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(8, 8)
	dot.color = TIER_COLORS.get(tier_key, Color.GRAY)
	container.add_child(dot)

	# Make it round using a shader or just keep as square for simplicity
	# For now, keep square - it still looks good

	container.tooltip_text = tier_name

	return container

func _create_cosmetic_slot(slot_name: String) -> Control:
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var slot_bg = PanelContainer.new()
	slot_bg.name = "SlotBG_" + slot_name
	slot_bg.custom_minimum_size = Vector2(80, 80)  # Balanced size
	var style = StyleBoxFlat.new()
	style.bg_color = BG_DARK
	style.border_color = CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	slot_bg.add_theme_stylebox_override("panel", style)
	slot_bg.set_meta("normal_style", style)
	container.add_child(slot_bg)

	# Create hover style
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.08, 0.085, 0.10)
	hover_style.border_color = MANTLE_CYAN.darkened(0.3)
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(6)
	hover_style.shadow_color = Color(MANTLE_CYAN.r, MANTLE_CYAN.g, MANTLE_CYAN.b, 0.3)
	hover_style.shadow_size = 4
	slot_bg.set_meta("hover_style", hover_style)

	# Make slot interactive
	slot_bg.mouse_entered.connect(_on_slot_hover_enter.bind(slot_bg))
	slot_bg.mouse_exited.connect(_on_slot_hover_exit.bind(slot_bg))

	var center = CenterContainer.new()
	slot_bg.add_child(center)

	var icon = Label.new()
	icon.name = "SlotIcon"
	match slot_name:
		"Head": icon.text = "👤"
		"Chest": icon.text = "👕"
		"Arms": icon.text = "💪"
		"Legs": icon.text = "👖"
		"Boots": icon.text = "👢"
		"Weapon": icon.text = "⚔"
		_: icon.text = "?"
	icon.add_theme_font_size_override("font_size", 54)  # Balanced icon size
	center.add_child(icon)

	var label = Label.new()
	label.text = slot_name
	label.add_theme_font_size_override("font_size", FONT_CAPTION)
	label.add_theme_color_override("font_color", TEXT_SECONDARY)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	# Add tooltip
	slot_bg.tooltip_text = "%s - Tier armor equipped" % slot_name

	return container

func _on_slot_hover_enter(slot: PanelContainer) -> void:
	var hover_style = slot.get_meta("hover_style") as StyleBoxFlat
	if hover_style:
		slot.add_theme_stylebox_override("panel", hover_style)

func _on_slot_hover_exit(slot: PanelContainer) -> void:
	var normal_style = slot.get_meta("normal_style") as StyleBoxFlat
	if normal_style:
		slot.add_theme_stylebox_override("panel", normal_style)

func _on_enter_button_hover(is_hovering: bool) -> void:
	if not enter_world_button:
		return

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	if is_hovering:
		# Play hover sound
		if SoundManager:
			SoundManager.play_button_hover_sound(-12.0)
		tween.tween_property(enter_world_button, "scale", Vector2(1.05, 1.05), 0.15)
	else:
		tween.tween_property(enter_world_button, "scale", Vector2(1.0, 1.0), 0.1)

func _build_achievements_panel() -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, CARD_BG)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header = Label.new()
	header.text = "UNLOCK WITH ACHIEVEMENTS"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_H2)
	header.add_theme_color_override("font_color", MANTLE_CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var subheader = Label.new()
	subheader.name = "AchievementsSubheader"
	subheader.text = "Legendary achievements become legendary gear"
	subheader.add_theme_font_override("font", default_font)
	subheader.add_theme_font_size_override("font_size", FONT_BODY)
	subheader.add_theme_color_override("font_color", MANTLE_CYAN)
	vbox.add_child(subheader)

	# Show teaser unlock examples as a grid (always visible)
	var teaser_container = GridContainer.new()
	teaser_container.name = "TeaserContainer"
	teaser_container.columns = 3
	teaser_container.add_theme_constant_override("h_separation", 12)
	teaser_container.add_theme_constant_override("v_separation", 12)
	vbox.add_child(teaser_container)

	# 15 well-known achievements that players can unlock
	var teasers = [
		{"item": "Coiled Sword", "game": "Dark Souls III", "rarity": "Legendary", "icon": "🗡"},
		{"item": "Elden Crown", "game": "Elden Ring", "rarity": "Legendary", "icon": "👑"},
		{"item": "Thunderfury", "game": "WoW", "rarity": "Legendary", "icon": "⚡"},
		{"item": "Dragonbone Helm", "game": "Skyrim", "rarity": "Epic", "icon": "🐉"},
		{"item": "Master Sword", "game": "Zelda", "rarity": "Legendary", "icon": "⚔"},
		{"item": "Keyblade", "game": "Kingdom Hearts", "rarity": "Legendary", "icon": "🗝"},
		{"item": "Daedric Armor", "game": "Skyrim", "rarity": "Epic", "icon": "🛡"},
		{"item": "Blades of Chaos", "game": "God of War", "rarity": "Legendary", "icon": "🔥"},
		{"item": "Moonlight Sword", "game": "Bloodborne", "rarity": "Legendary", "icon": "🌙"},
		{"item": "Buster Sword", "game": "FF VII", "rarity": "Legendary", "icon": "⚔"},
		{"item": "Ashbringer", "game": "WoW", "rarity": "Legendary", "icon": "✝"},
		{"item": "Diamond Armor", "game": "Minecraft", "rarity": "Rare", "icon": "💎"},
		{"item": "Golden Gun", "game": "007", "rarity": "Epic", "icon": "🔫"},
		{"item": "Infinity Gauntlet", "game": "Marvel", "rarity": "Legendary", "icon": "🧤"},
		{"item": "Soul Edge", "game": "Soulcalibur", "rarity": "Legendary", "icon": "👁"},
	]

	for teaser in teasers:
		var item = _create_compact_teaser(teaser)
		teaser_container.add_child(item)

	# "Your achievements" section appears when accounts linked
	var your_section = VBoxContainer.new()
	your_section.name = "YourAchievementsSection"
	your_section.add_theme_constant_override("separation", 8)
	your_section.visible = false
	vbox.add_child(your_section)

	var your_header = Label.new()
	your_header.name = "YourAchievementsHeader"
	your_header.text = "YOUR NOTABLE ACHIEVEMENTS"
	your_header.add_theme_font_override("font", default_font)
	your_header.add_theme_font_size_override("font_size", FONT_BODY)
	your_header.add_theme_color_override("font_color", MANTLE_CYAN)
	your_section.add_child(your_header)

	var your_list = VBoxContainer.new()
	your_list.name = "YourAchievementsList"
	your_list.add_theme_constant_override("separation", 6)
	your_section.add_child(your_list)

	return panel

func _create_teaser_item(teaser: Dictionary) -> Control:
	var container = PanelContainer.new()
	var style = StyleBoxFlat.new()
	var rarity_color = RARITY_COLORS.get(teaser.get("rarity", "Common"), Color.GRAY)
	style.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.08)
	style.border_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	container.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	container.add_child(hbox)

	# Item icon - larger size (32-40px equivalent)
	var icon = Label.new()
	icon.text = teaser.get("icon", "?")
	icon.add_theme_font_size_override("font_size", 72)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon)

	# Text info
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 2)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	# Item name row
	var item_row = HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(item_row)

	var item_name = Label.new()
	item_name.text = teaser.get("item", "Unknown")
	item_name.add_theme_font_override("font", default_font)
	item_name.add_theme_font_size_override("font_size", FONT_BODY)
	item_name.add_theme_color_override("font_color", rarity_color)
	item_row.add_child(item_name)

	# Achievement source
	var source = Label.new()
	source.text = "%s - %s" % [teaser.get("game", ""), teaser.get("achievement", "")]
	source.add_theme_font_override("font", default_font)
	source.add_theme_font_size_override("font_size", FONT_CAPTION)
	source.add_theme_color_override("font_color", TEXT_DIM)
	info_vbox.add_child(source)

	# Arrow indicator
	var arrow = Label.new()
	arrow.text = ">"
	arrow.add_theme_font_size_override("font_size", FONT_BODY_LG)
	arrow.add_theme_color_override("font_color", TEXT_DIM)
	hbox.add_child(arrow)

	container.tooltip_text = "Earn \"%s\" in %s to unlock the %s" % [
		teaser.get("achievement", ""),
		teaser.get("game", ""),
		teaser.get("item", "")
	]

	return container

func _create_compact_teaser(teaser: Dictionary) -> Control:
	"""Create a compact teaser item for the grid layout"""
	var container = PanelContainer.new()
	var rarity_color = RARITY_COLORS.get(teaser.get("rarity", "Common"), Color.GRAY)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.1)
	style.border_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	container.add_theme_stylebox_override("panel", style)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	container.add_child(hbox)

	# Icon - 2x bigger
	var icon = Label.new()
	icon.text = teaser.get("icon", "?")
	icon.add_theme_font_size_override("font_size", 72)
	hbox.add_child(icon)

	# Item name and game
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var item_name = Label.new()
	item_name.text = teaser.get("item", "Unknown")
	item_name.add_theme_font_override("font", default_font)
	item_name.add_theme_font_size_override("font_size", FONT_H2)
	item_name.add_theme_color_override("font_color", rarity_color)
	item_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(item_name)

	var game_label = Label.new()
	game_label.text = teaser.get("game", "")
	game_label.add_theme_font_override("font", default_font)
	game_label.add_theme_font_size_override("font_size", FONT_BODY)
	game_label.add_theme_color_override("font_color", TEXT_DIM)
	game_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(game_label)

	container.tooltip_text = "%s\nFrom: %s\nRarity: %s" % [
		teaser.get("item", ""),
		teaser.get("game", ""),
		teaser.get("rarity", "")
	]

	return container

func _build_forged_panel() -> Control:
	var panel = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_panel(panel, CARD_BG)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header = Label.new()
	header.text = "THE FORGE"
	header.add_theme_font_size_override("font_size", FONT_BODY)
	header.add_theme_color_override("font_color", MANTLE_CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var forged_list = VBoxContainer.new()
	forged_list.name = "ForgedList"
	forged_list.add_theme_constant_override("separation", 10)
	vbox.add_child(forged_list)

	# Placeholder
	var placeholder = Label.new()
	placeholder.name = "ForgedPlaceholder"
	placeholder.text = "No forged items yet"
	placeholder.add_theme_font_size_override("font_size", FONT_CAPTION)
	placeholder.add_theme_color_override("font_color", TEXT_SECONDARY)
	forged_list.add_child(placeholder)

	return panel

func _build_footer(parent: Control) -> void:
	# Footer is now minimal - buttons moved to middle column
	# Just a thin bottom bar for visual balance
	var footer_panel = Control.new()
	footer_panel.custom_minimum_size = Vector2(0, 10)
	parent.add_child(footer_panel)

# ═══════════════════════════════════════════════════════════════════════════════
# STYLING HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _style_panel(panel: PanelContainer, bg_color: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = BORDER_GLOW
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_size = 20
	style.shadow_color = SHADOW_GLOW
	panel.add_theme_stylebox_override("panel", style)

func _play_button_hover_sound() -> void:
	"""Helper function to play button hover sound"""
	if SoundManager:
		SoundManager.play_button_hover_sound(-12.0)

func _style_primary_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", FONT_H2)
	button.add_theme_color_override("font_color", Color.WHITE)
	# Connect hover sound
	button.mouse_entered.connect(_play_button_hover_sound)

	var normal = StyleBoxFlat.new()
	normal.bg_color = MANTLE_CYAN.darkened(0.3)
	normal.border_color = MANTLE_CYAN
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)

	var hover = StyleBoxFlat.new()
	hover.bg_color = MANTLE_CYAN.darkened(0.1)
	hover.border_color = MANTLE_CYAN.lightened(0.2)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	button.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = MANTLE_CYAN.darkened(0.4)
	pressed.border_color = MANTLE_CYAN
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(8)
	button.add_theme_stylebox_override("pressed", pressed)

func _style_enter_world_button(button: Button) -> void:
	"""Style Enter World button - GREEN"""
	var green = Color(0.2, 0.7, 0.3)
	var green_dark = Color(0.1, 0.5, 0.15)
	var green_light = Color(0.3, 0.85, 0.4)

	button.add_theme_font_override("font", default_font)
	button.add_theme_font_size_override("font_size", FONT_BODY_LG)
	button.add_theme_color_override("font_color", Color.WHITE)
	# Connect hover sound
	button.mouse_entered.connect(_play_button_hover_sound)

	# Normal state
	var normal = StyleBoxFlat.new()
	normal.bg_color = green_dark
	normal.border_color = green
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	button.set_meta("normal_style", normal)

	# Hover state
	var hover = StyleBoxFlat.new()
	hover.bg_color = green
	hover.border_color = green_light
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover)

	# Pressed state
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = green_dark.darkened(0.2)
	pressed.border_color = green
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	button.add_theme_stylebox_override("pressed", pressed)

func _style_secondary_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", FONT_BODY)
	button.add_theme_color_override("font_color", TEXT_SECONDARY)
	button.add_theme_color_override("font_hover_color", MANTLE_CYAN)
	# Connect hover sound
	button.mouse_entered.connect(_play_button_hover_sound)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.border_color = Color(0.25, 0.25, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", style)

	var hover = StyleBoxFlat.new()
	hover.bg_color = Color(0.15, 0.15, 0.18)
	hover.border_color = MANTLE_CYAN.darkened(0.3)
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover)

func _style_logout_button(button: Button) -> void:
	"""Style Logout button - RED (similar to Enter World)"""
	var red = Color(0.7, 0.25, 0.25)
	var red_dark = Color(0.5, 0.15, 0.15)
	var red_light = Color(0.85, 0.35, 0.35)

	button.add_theme_font_override("font", default_font)
	button.add_theme_font_size_override("font_size", FONT_BODY_LG)
	button.add_theme_color_override("font_color", Color.WHITE)
	# Connect hover sound
	button.mouse_entered.connect(_play_button_hover_sound)

	# Normal state
	var normal = StyleBoxFlat.new()
	normal.bg_color = red_dark
	normal.border_color = red
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)

	# Hover state
	var hover = StyleBoxFlat.new()
	hover.bg_color = red
	hover.border_color = red_light
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover)

	# Pressed state
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = red_dark.darkened(0.2)
	pressed.border_color = red
	pressed.set_border_width_all(2)
	pressed.set_corner_radius_all(6)
	button.add_theme_stylebox_override("pressed", pressed)

# ═══════════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

func _determine_state() -> void:
	if not MantleAuth or not MantleAuth.is_logged_in():
		current_state = ArmoryState.GUEST
		return

	profile = {
		"user_id": MantleAuth.user_id,
		"username": MantleAuth.username,
		"mantle": MantleAuth.mantle_tier,
		"providers": MantleAuth.providers,
		"total_achievements": MantleAuth.total_achievements,
		"achievements": MantleAuth.achievements,
		"by_rarity": MantleAuth.by_rarity
	}

	var providers_data = profile.get("providers", [])
	var provider_count = providers_data.size() if providers_data else 0
	var total = profile.get("total_achievements", 0)
	if total == null:
		total = 0

	if provider_count == 0:
		current_state = ArmoryState.NEW_PLAYER
	elif total < 1000:
		current_state = ArmoryState.CASUAL
	else:
		current_state = ArmoryState.VETERAN

func _setup_ui_for_state() -> void:
	match current_state:
		ArmoryState.GUEST:
			_show_guest_ui()
		ArmoryState.NEW_PLAYER:
			_show_new_player_ui()
		ArmoryState.CASUAL, ArmoryState.VETERAN:
			_show_authenticated_ui()

func _show_guest_ui() -> void:
	subtitle_label.text = "Your Gaming Legacy Awaits"
	username_label.text = "Guest"
	total_label.text = "0"
	logout_button.visible = false
	_populate_recent_unlocks()

func _show_new_player_ui() -> void:
	var user_id = profile.get("user_id", 0)
	subtitle_label.text = "Welcome, Player #%d" % user_id
	username_label.text = "Player #%d" % user_id
	logout_button.visible = true
	_update_stats_display()

func _show_authenticated_ui() -> void:
	var user_id = profile.get("user_id", 0)
	var mantle = profile.get("mantle", {})
	var tier = mantle.get("name", "Initiate")
	subtitle_label.text = "%s Champion" % tier
	username_label.text = "Player #%d" % user_id
	logout_button.visible = true
	_update_stats_display()

func _update_stats_display() -> void:
	var mantle = profile.get("mantle", {})
	var tier_name = mantle.get("name", "Initiate")
	var tier_key = mantle.get("tier", "initiate").to_lower()
	var total = profile.get("total_achievements", 0)
	# Use effective_score for progress calculation if available (weighted scoring)
	var effective_score = int(mantle.get("effective_score", total))
	print("[Armory] Stats display: total_achievements=%d, effective_score=%d, tier=%s" % [total, effective_score, tier_key])

	# Update tier badge
	_update_tier_badge(tier_key, tier_name)

	# Store target for animated count (keep label at "0" until animation)
	_target_achievement_count = total
	total_label.text = "0"

	# Update character preview
	var char_text = character_preview.find_child("CharacterTierText", true, false)
	if char_text:
		char_text.text = "%s Gear" % tier_name

	var effects_label = character_preview.find_child("EffectsLabel", true, false)
	if effects_label:
		match tier_key:
			"mythic": effects_label.text = "✦ Ethereal Aura + Particle Trail"
			"legendary": effects_label.text = "🔥 Fire/Ember Effects"
			"diamond": effects_label.text = "💎 Crystal Sparkles"
			"platinum": effects_label.text = "✨ Soft Blue Glow"
			"gold": effects_label.text = "⭐ Gold Trim + Subtle Glow"
			_: effects_label.text = ""

	# Update platforms
	_update_platforms_display()

	# Update rarity breakdown
	_update_rarity_display()

	# Update progress bar (use effective_score for accurate tier progress)
	_update_progress_display(effective_score, tier_key)

	# Update notable achievements
	_update_achievements_display()

	# Update quick stats (if present)
	_update_quick_stats()

	# Add tier glow effect to character preview
	_add_tier_glow_effect(tier_key)

	# Apply tier-colored accents to UI panels
	_apply_tier_accents(tier_key)

	# Populate recent unlocks with demo data
	_populate_recent_unlocks()

func _update_quick_stats() -> void:
	var quick_stats = stats_panel.find_child("QuickStatsSection", true, false)
	if not quick_stats:
		return

	var providers = profile.get("providers", [])
	var mantle = profile.get("mantle", {})

	# Games (count of providers)
	var games_stat = stats_panel.find_child("Stat_Games", true, false)
	if games_stat:
		var value_label = games_stat.find_child("Value", true, false)
		if value_label:
			var game_count = providers.size() if providers else 0
			value_label.text = str(game_count) if game_count > 0 else "-"

	# Rarest Achievement
	var rarest_stat = stats_panel.find_child("Stat_Rarest", true, false)
	if rarest_stat:
		var value_label = rarest_stat.find_child("Value", true, false)
		if value_label:
			var by_rarity = mantle.get("by_rarity", {})
			if by_rarity == null:
				by_rarity = {}
			var legendary_count = by_rarity.get("Legendary", 0)
			var epic_count = by_rarity.get("Epic", 0)
			if legendary_count != null and legendary_count > 0:
				value_label.text = "Legend"
				value_label.add_theme_color_override("font_color", RARITY_COLORS["Legendary"])
			elif epic_count != null and epic_count > 0:
				value_label.text = "Epic"
				value_label.add_theme_color_override("font_color", RARITY_COLORS["Epic"])
			else:
				value_label.text = "-"
				value_label.add_theme_color_override("font_color", TEXT_PRIMARY)

	# Level (based on tier)
	var level_stat = stats_panel.find_child("Stat_Level", true, false)
	if level_stat:
		var value_label = level_stat.find_child("Value", true, false)
		if value_label:
			var tier_key = mantle.get("tier", "initiate").to_lower()
			match tier_key:
				"mythic": value_label.text = "8"
				"legendary": value_label.text = "7"
				"diamond": value_label.text = "6"
				"platinum": value_label.text = "5"
				"gold": value_label.text = "4"
				"silver": value_label.text = "3"
				"bronze": value_label.text = "2"
				_: value_label.text = "1"

	# Rank (placeholder - would need global rank from API)
	var rank_stat = stats_panel.find_child("Stat_Rank", true, false)
	if rank_stat:
		var value_label = rank_stat.find_child("Value", true, false)
		if value_label:
			var total_ach = profile.get("total_achievements", 0)
			if total_ach != null and total_ach > 0:
				if total_ach > 5000:
					value_label.text = "1%"
					value_label.add_theme_color_override("font_color", TIER_COLORS["legendary"])
				elif total_ach > 3000:
					value_label.text = "5%"
					value_label.add_theme_color_override("font_color", TIER_COLORS["diamond"])
				elif total_ach > 1000:
					value_label.text = "20%"
					value_label.add_theme_color_override("font_color", TIER_COLORS["gold"])
				else:
					value_label.text = "50%"
			else:
				value_label.text = "-"

func _update_tier_badge(tier_key: String, tier_name: String) -> void:
	tier_label.text = tier_name.to_upper()
	var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])

	# Update tier label text color
	if tier_key in ["gold", "silver", "platinum", "diamond"]:
		tier_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	else:
		tier_label.add_theme_color_override("font_color", Color.WHITE)

	# Update enhanced badge (new structure with glow)
	if tier_badge:
		# Update the main badge panel
		var badge_panel = tier_badge.find_child("TierBadgePanel", false, false)
		if badge_panel:
			var style = StyleBoxFlat.new()
			style.bg_color = color
			style.set_corner_radius_all(4)
			style.content_margin_left = 12
			style.content_margin_right = 12
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			# Metallic highlight on top edge
			style.border_color = color.lightened(0.4)
			style.border_width_top = 2
			style.border_width_bottom = 0
			style.border_width_left = 1
			style.border_width_right = 1
			badge_panel.add_theme_stylebox_override("panel", style)

		# Update the glow panel
		var glow_panel = tier_badge.find_child("BadgeGlow", false, false)
		if glow_panel:
			var glow_style = StyleBoxFlat.new()
			glow_style.bg_color = Color(color.r, color.g, color.b, 0.2)
			glow_style.set_corner_radius_all(8)
			glow_style.shadow_color = Color(color.r, color.g, color.b, 0.5)
			glow_style.shadow_size = 16
			glow_panel.add_theme_stylebox_override("panel", glow_style)

		# Restart the pulse animation with new color
		_start_badge_pulse(tier_badge, color)

	# Fallback: Old badge structure
	elif tier_badge and tier_badge.has_meta("style"):
		var style = tier_badge.get_meta("style") as StyleBoxFlat
		style.bg_color = color
		style.shadow_color = Color(color.r, color.g, color.b, 0.4)

func _update_platforms_display() -> void:
	var platforms_row = stats_panel.find_child("PlatformsRow", true, false)

	# Clear existing content
	if platforms_row:
		for child in platforms_row.get_children():
			child.queue_free()

	var providers = profile.get("providers", [])
	if providers == null:
		providers = []

	if providers.is_empty():
		if platforms_row:
			var label = Label.new()
			label.text = "No platforms linked"
			label.add_theme_font_override("font", default_font)
			label.add_theme_font_size_override("font_size", FONT_CAPTION)
			label.add_theme_color_override("font_color", TEXT_SECONDARY)
			platforms_row.add_child(label)
		return

	for provider in providers:
		var prov_name: String = ""
		var prov_count: int = 0
		var prov_icon_url: String = ""

		# If provider is just a string, it means we only have the name
		if typeof(provider) == TYPE_STRING:
			prov_name = provider
			prov_count = 0
		elif typeof(provider) == TYPE_DICTIONARY:
			# Handle multiple possible API formats for provider name
			prov_name = str(provider.get("provider_name", provider.get("name", "unknown")))

			# Debug: print all keys to see what's available
			print("[Armory] Provider %s data: %s" % [prov_name, provider])

			# Check for icon URL from backend
			prov_icon_url = str(provider.get("icon_url", provider.get("logo_url", provider.get("image_url", ""))))

			# Handle multiple possible API formats for count - try all common field names
			var count_fields = ["tap_contribution", "total_achievements", "total", "count",
							   "achievement_count", "achievements", "num_achievements"]
			for field in count_fields:
				if provider.has(field):
					var val = provider.get(field, 0)
					if val != null:
						prov_count = int(val)
						print("[Armory] Provider %s count from '%s': %d" % [prov_name, field, prov_count])
						break
		else:
			print("[Armory] Unknown provider type: ", typeof(provider))
			continue

		# Add provider badge to platforms row
		if platforms_row:
			var badge = _create_provider_badge(prov_name, prov_count, prov_icon_url)
			platforms_row.add_child(badge)

func _create_provider_badge(provider_name: String, count: int, icon_url: String = "") -> Control:
	var prov_lower = provider_name.to_lower()
	var color = PROVIDER_COLORS.get(prov_lower, MANTLE_CYAN)
	# Handle PSN alias
	if prov_lower == "psn":
		color = PROVIDER_COLORS.get("playstation", MANTLE_CYAN)
	elif prov_lower == "github":
		color = Color(0.9, 0.9, 0.9)  # GitHub white/gray

	# Vertical layout: icon on top, count below
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	# Icon wrapper for centering
	var icon_wrapper = CenterContainer.new()
	container.add_child(icon_wrapper)

	# Try to load platform icon texture - local paths
	# Facebook and Roblox load from backend URL (no local icons)
	var icon_path = ""
	match prov_lower:
		"steam": icon_path = "res://assets/ui/icons/steam.png"
		"battlenet", "blizzard": icon_path = "res://assets/ui/icons/battlenet.png"
		"xbox": icon_path = "res://assets/ui/icons/xbox.png"
		"playstation", "psn": icon_path = "res://assets/ui/icons/playstation.svg"
		"discord": icon_path = "res://assets/ui/icons/discord.svg"
		"github": icon_path = "res://assets/ui/icons/github.svg"
		"epic": icon_path = "res://assets/ui/icons/epic.svg"
		"gog": icon_path = "res://assets/ui/icons/gog.svg"

	# Always create a consistent badge container with background
	var badge_panel = PanelContainer.new()
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = color.darkened(0.6)
	badge_style.bg_color.a = 0.4
	badge_style.set_corner_radius_all(8)
	badge_style.border_color = color.darkened(0.2)
	badge_style.set_border_width_all(1)
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 6
	badge_style.content_margin_bottom = 6
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	icon_wrapper.add_child(badge_panel)

	var badge_content = CenterContainer.new()
	badge_panel.add_child(badge_content)

	var icon_loaded = false

	# Debug: check local icon path
	if icon_path != "":
		var exists = ResourceLoader.exists(icon_path)
		print("[Armory] Provider %s local icon path: %s (exists: %s)" % [prov_lower, icon_path, exists])
		if exists:
			var texture = load(icon_path)
			if texture:
				icon_loaded = true
				var icon_tex = TextureRect.new()
				icon_tex.texture = texture
				icon_tex.custom_minimum_size = Vector2(24, 24)
				icon_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_tex.modulate = color
				badge_content.add_child(icon_tex)
				print("[Armory] Provider %s loaded local icon successfully" % prov_lower)

	if not icon_loaded:
		# Try loading from backend URL if provided (PNG/JPG only, not SVG)
		var can_load_from_url = icon_url != "" and not icon_url.ends_with(".svg") and not ".svg" in icon_url

		if can_load_from_url:
			# Create placeholder TextureRect that will be updated when URL loads
			var icon_tex = TextureRect.new()
			icon_tex.name = "ProviderIcon"
			icon_tex.custom_minimum_size = Vector2(24, 24)
			icon_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_tex.modulate = color
			badge_content.add_child(icon_tex)
			_load_provider_icon_from_url(icon_url, icon_tex, color, badge_content, prov_lower)
		else:
			# Use letter fallback (no local icon and URL is SVG or missing)
			var icon_label = Label.new()
			match prov_lower:
				"steam": icon_label.text = "S"
				"battlenet", "blizzard": icon_label.text = "B"
				"xbox": icon_label.text = "X"
				"playstation", "psn": icon_label.text = "P"
				"discord": icon_label.text = "D"
				"github": icon_label.text = "G"
				"epic": icon_label.text = "E"
				"gog": icon_label.text = "G"
				"facebook": icon_label.text = "F"
				"roblox": icon_label.text = "R"
				_: icon_label.text = "?"
			icon_label.add_theme_font_override("font", default_font)
			icon_label.add_theme_font_size_override("font_size", 18)
			icon_label.add_theme_color_override("font_color", color)
			badge_content.add_child(icon_label)

	# Count below icon - formatted consistently
	var count_label = Label.new()
	count_label.text = _format_number(count) if count >= 0 else "-"
	count_label.add_theme_font_override("font", default_font)
	count_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	count_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(count_label)

	# Provider name below count
	var name_label = Label.new()
	match provider_name.to_lower():
		"steam": name_label.text = "Steam"
		"battlenet", "blizzard": name_label.text = "Blizzard"
		"xbox": name_label.text = "Xbox"
		"playstation", "psn": name_label.text = "PSN"
		"discord": name_label.text = "Discord"
		"github": name_label.text = "GitHub"
		"epic": name_label.text = "Epic"
		"gog": name_label.text = "GOG"
		"facebook": name_label.text = "Facebook"
		"roblox": name_label.text = "Roblox"
		_: name_label.text = provider_name.capitalize()
	name_label.add_theme_font_override("font", default_font)
	name_label.add_theme_font_size_override("font_size", FONT_TINY)
	name_label.add_theme_color_override("font_color", TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(name_label)

	# Rich tooltip with connection status
	var display_name = name_label.text  # Use the formatted name
	var is_connected = count >= 0
	var tooltip_lines = []

	tooltip_lines.append("%s" % display_name)
	tooltip_lines.append("━━━━━━━━━━━━━━")

	if is_connected:
		tooltip_lines.append("✓ Connected")
		tooltip_lines.append("")
		tooltip_lines.append("🏆 %s achievements" % _format_number(count))
		# Could add account name here when available from API
		# tooltip_lines.append("👤 Username")
	else:
		tooltip_lines.append("✗ Not connected")
		tooltip_lines.append("")
		tooltip_lines.append("Link your %s account to" % display_name)
		tooltip_lines.append("sync achievements and unlock rewards!")

	container.tooltip_text = "\n".join(tooltip_lines)

	return container

func _load_provider_icon_from_url(url: String, icon_rect: TextureRect, tint_color: Color, badge_content: CenterContainer, provider_name: String) -> void:
	"""Asynchronously load a provider icon from a backend URL with letter fallback"""
	if url == "" or not is_instance_valid(icon_rect):
		return

	print("[Armory] Loading provider icon from URL: %s" % url)

	var http_request = HTTPRequest.new()
	http_request.timeout = 10.0
	add_child(http_request)

	http_request.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
			http_request.queue_free()

			var load_failed = false

			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				print("[Armory] Failed to load icon from URL: %s (result=%d, code=%d)" % [url, result, response_code])
				load_failed = true

			if not load_failed and not is_instance_valid(icon_rect):
				return

			if not load_failed:
				# Try to create an image from the downloaded data
				var image = Image.new()
				var err = ERR_INVALID_DATA

				# Try different image formats
				if url.ends_with(".png") or "png" in url:
					err = image.load_png_from_buffer(body)
				elif url.ends_with(".jpg") or url.ends_with(".jpeg") or "jpg" in url:
					err = image.load_jpg_from_buffer(body)
				else:
					# Try PNG first, then JPG
					err = image.load_png_from_buffer(body)
					if err != OK:
						err = image.load_jpg_from_buffer(body)

				if err != OK:
					print("[Armory] Failed to parse icon image from URL: %s" % url)
					load_failed = true
				else:
					# Create texture and apply to the TextureRect
					var texture = ImageTexture.create_from_image(image)
					icon_rect.texture = texture
					icon_rect.modulate = tint_color
					print("[Armory] Successfully loaded provider icon from URL: %s" % url)

			# Fallback to letter if loading failed
			if load_failed and is_instance_valid(icon_rect) and is_instance_valid(badge_content):
				icon_rect.queue_free()
				var icon_label = Label.new()
				var prov_lower = provider_name.to_lower()
				match prov_lower:
					"steam": icon_label.text = "S"
					"battlenet", "blizzard": icon_label.text = "B"
					"xbox": icon_label.text = "X"
					"playstation", "psn": icon_label.text = "P"
					"discord": icon_label.text = "D"
					"github": icon_label.text = "G"
					"epic": icon_label.text = "E"
					"gog": icon_label.text = "G"
					_: icon_label.text = "?"
				icon_label.add_theme_font_override("font", default_font)
				icon_label.add_theme_font_size_override("font_size", 18)
				icon_label.add_theme_color_override("font_color", tint_color)
				badge_content.add_child(icon_label)
	)

	var err = http_request.request(url)
	if err != OK:
		print("[Armory] Failed to start HTTP request for icon: %s" % url)
		http_request.queue_free()
		# Add letter fallback immediately
		if is_instance_valid(icon_rect) and is_instance_valid(badge_content):
			icon_rect.queue_free()
			var icon_label = Label.new()
			var prov_lower = provider_name.to_lower()
			match prov_lower:
				"steam": icon_label.text = "S"
				"battlenet", "blizzard": icon_label.text = "B"
				"xbox": icon_label.text = "X"
				"playstation", "psn": icon_label.text = "P"
				"discord": icon_label.text = "D"
				"github": icon_label.text = "G"
				"epic": icon_label.text = "E"
				"gog": icon_label.text = "G"
				_: icon_label.text = "?"
			icon_label.add_theme_font_override("font", default_font)
			icon_label.add_theme_font_size_override("font_size", 18)
			icon_label.add_theme_color_override("font_color", tint_color)
			badge_content.add_child(icon_label)

func _add_fallback_letter(icon_container: Control, provider_name: String, color: Color) -> void:
	"""Add a fallback letter icon when platform image not available"""
	var icon_label = Label.new()
	match provider_name.to_lower():
		"steam": icon_label.text = "S"
		"battlenet", "blizzard": icon_label.text = "B"
		"xbox": icon_label.text = "X"
		"playstation", "psn": icon_label.text = "P"
		"discord": icon_label.text = "D"
		"epic": icon_label.text = "E"
		"gog": icon_label.text = "G"
		_: icon_label.text = "?"
	icon_label.add_theme_font_override("font", default_font)
	icon_label.add_theme_font_size_override("font_size", FONT_BODY)
	# Use dark text for light-colored providers
	if provider_name.to_lower() in ["battlenet", "xbox"]:
		icon_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	else:
		icon_label.add_theme_color_override("font_color", Color.WHITE)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_container.add_child(icon_label)

func _update_rarity_display() -> void:
	var rarity_row = stats_panel.find_child("RarityRow", true, false)
	if not rarity_row:
		return

	for child in rarity_row.get_children():
		child.queue_free()

	# Get rarity data - check multiple sources
	var by_rarity = {}
	var has_rarity_data = false

	# Source 1: Direct from profile (set in _determine_state from MantleAuth.by_rarity)
	if profile.has("by_rarity") and profile.get("by_rarity") != null:
		var data = profile.get("by_rarity", {})
		if data is Dictionary and not data.is_empty():
			by_rarity = data
			has_rarity_data = true

	# Source 2: Direct from MantleAuth autoload
	if not has_rarity_data and MantleAuth:
		var data = MantleAuth.by_rarity
		if data is Dictionary and not data.is_empty():
			by_rarity = data
			has_rarity_data = true

	# Source 3: Try nested in mantle tier object
	if not has_rarity_data:
		var mantle = profile.get("mantle", {})
		if mantle != null and mantle is Dictionary and mantle.has("by_rarity"):
			var data = mantle.get("by_rarity", {})
			if data is Dictionary and not data.is_empty():
				by_rarity = data
				has_rarity_data = true

	# Source 4: Aggregate from providers if they have per-provider rarity data
	if not has_rarity_data:
		var providers = profile.get("providers", [])
		if providers != null and providers is Array and not providers.is_empty():
			var found_provider_rarity = false
			by_rarity = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}
			for provider in providers:
				if typeof(provider) == TYPE_DICTIONARY:
					var prov_rarity = provider.get("by_rarity", {})
					if prov_rarity != null and prov_rarity is Dictionary and not prov_rarity.is_empty():
						found_provider_rarity = true
						for rarity_name in by_rarity.keys():
							by_rarity[rarity_name] += int(prov_rarity.get(rarity_name, 0))
			if found_provider_rarity:
				has_rarity_data = true
			else:
				by_rarity = {}

	# Debug output
	print("[Armory] Rarity data available: ", has_rarity_data, " Data: ", by_rarity)

	# Always show the 5 rarity gems
	var rarity_order = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
	for rarity_name in rarity_order:
		var count = -1  # -1 means "no data"
		if has_rarity_data:
			count = by_rarity.get(rarity_name, 0)
			# Ensure count is a valid integer
			if count == null:
				count = 0
			elif typeof(count) == TYPE_STRING:
				count = int(count)
			elif typeof(count) == TYPE_FLOAT:
				count = int(count)
		var color = RARITY_COLORS.get(rarity_name, Color.GRAY)
		var gem = _create_rarity_gem(rarity_name, color, count)
		rarity_row.add_child(gem)

func _create_rarity_gem(rarity_name: String, color: Color, count: int) -> Control:
	# Pill/chip style: icon + count in a cohesive rounded container
	var pill = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = color.darkened(0.7)
	style.bg_color.a = 0.4
	style.border_color = color.darkened(0.3)
	style.border_color.a = 0.6
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	pill.add_child(hbox)

	# Rarity symbol/dot - larger size
	var symbol = Label.new()
	match rarity_name:
		"Common":
			symbol.text = "●"
		"Uncommon":
			symbol.text = "◆"
		"Rare":
			symbol.text = "★"
		"Epic":
			symbol.text = "✦"
		"Legendary":
			symbol.text = "✧"
		_:
			symbol.text = "●"
	symbol.add_theme_font_size_override("font_size", 20)
	symbol.add_theme_color_override("font_color", color)
	hbox.add_child(symbol)

	# Count label - larger size
	var label = Label.new()
	if count < 0:
		label.text = "—"
		label.add_theme_color_override("font_color", TEXT_DIM)
	elif count > 0:
		label.text = _format_number(count)
		label.add_theme_color_override("font_color", TEXT_PRIMARY)
	else:
		label.text = "0"
		label.add_theme_color_override("font_color", TEXT_DIM)
	label.add_theme_font_override("font", default_font)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(label)

	if count < 0:
		pill.tooltip_text = "%s: Data unavailable" % rarity_name
	else:
		pill.tooltip_text = "%s: %s" % [rarity_name, _format_number(count) if count > 0 else "None"]
	return pill

func _create_round_gem(parent: Control, color: Color, rarity_name: String) -> void:
	var center = Vector2(16, 16)
	var radius = 12.0

	# Outer glow (subtle)
	var glow = _create_circle_polygon(center, radius + 4, color * 0.3)
	glow.color.a = 0.25
	parent.add_child(glow)

	# Main gem body
	var gem = _create_circle_polygon(center, radius, color)
	parent.add_child(gem)

	# Inner lighter core (3D effect)
	var core = _create_circle_polygon(center - Vector2(2, 2), radius * 0.6, color.lightened(0.4))
	core.color.a = 0.6
	parent.add_child(core)

	# Bright highlight spot
	var highlight = _create_circle_polygon(center - Vector2(4, 4), radius * 0.25, Color.WHITE)
	highlight.color.a = 0.7
	parent.add_child(highlight)

func _create_diamond_gem(parent: Control, color: Color, is_legendary: bool) -> void:
	var cx = 16.0
	var cy = 16.0

	# Outer glow for high-tier gems
	var glow_size = 18.0 if is_legendary else 15.0
	var glow = Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(cx, cy - glow_size),      # Top
		Vector2(cx + glow_size, cy),      # Right
		Vector2(cx, cy + glow_size),      # Bottom
		Vector2(cx - glow_size, cy)       # Left
	])
	glow.color = Color(color.r, color.g, color.b, 0.3)
	parent.add_child(glow)

	# Main diamond shape
	var size = 13.0
	var gem = Polygon2D.new()
	gem.polygon = PackedVector2Array([
		Vector2(cx, cy - size),           # Top point
		Vector2(cx + size, cy),           # Right point
		Vector2(cx, cy + size),           # Bottom point
		Vector2(cx - size, cy)            # Left point
	])
	gem.color = color
	parent.add_child(gem)

	# Inner facet (top-right bright)
	var facet1 = Polygon2D.new()
	facet1.polygon = PackedVector2Array([
		Vector2(cx, cy - size + 3),
		Vector2(cx + size - 3, cy),
		Vector2(cx, cy)
	])
	facet1.color = color.lightened(0.3)
	parent.add_child(facet1)

	# Inner facet (bottom-left darker)
	var facet2 = Polygon2D.new()
	facet2.polygon = PackedVector2Array([
		Vector2(cx, cy),
		Vector2(cx - size + 3, cy),
		Vector2(cx, cy + size - 3)
	])
	facet2.color = color.darkened(0.2)
	parent.add_child(facet2)

	# Bright highlight
	var highlight = Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(cx - 2, cy - size + 5),
		Vector2(cx + 3, cy - 3),
		Vector2(cx - 1, cy - 2)
	])
	highlight.color = Color(1, 1, 1, 0.6)
	parent.add_child(highlight)

	# Extra sparkle for Legendary
	if is_legendary:
		var sparkle = Polygon2D.new()
		sparkle.polygon = PackedVector2Array([
			Vector2(cx, cy - 2),
			Vector2(cx + 2, cy),
			Vector2(cx, cy + 2),
			Vector2(cx - 2, cy)
		])
		sparkle.color = Color(1, 1, 1, 0.8)
		parent.add_child(sparkle)

func _create_circle_gem(parent: Control, color: Color) -> void:
	"""Common rarity - simple round circle (softest shape)"""
	var cx = 16.0
	var cy = 16.0
	var radius = 11.0

	# Outer glow
	var glow = _create_circle_polygon(Vector2(cx, cy), radius + 3, Color(color.r, color.g, color.b, 0.3))
	parent.add_child(glow)

	# Main circle body
	var gem = _create_circle_polygon(Vector2(cx, cy), radius, color)
	parent.add_child(gem)

	# Inner lighter core (3D effect) - offset up-left
	var core = _create_circle_polygon(Vector2(cx - 2, cy - 2), radius * 0.5, color.lightened(0.3))
	core.color.a = 0.6
	parent.add_child(core)

	# Bright highlight spot
	var highlight = _create_circle_polygon(Vector2(cx - 4, cy - 4), radius * 0.2, Color.WHITE)
	highlight.color.a = 0.7
	parent.add_child(highlight)

func _create_hexagon_gem(parent: Control, color: Color) -> void:
	"""Uncommon rarity - hexagon (6 sides, slightly angular)"""
	var cx = 16.0
	var cy = 16.0
	var radius = 12.0

	# Create hexagon points
	var hex_points = PackedVector2Array()
	var glow_points = PackedVector2Array()
	for i in range(6):
		var angle = i * TAU / 6 - PI / 6  # Rotate so flat side is at bottom
		hex_points.append(Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius))
		glow_points.append(Vector2(cx + cos(angle) * (radius + 3), cy + sin(angle) * (radius + 3)))

	# Outer glow
	var glow = Polygon2D.new()
	glow.polygon = glow_points
	glow.color = Color(color.r, color.g, color.b, 0.3)
	parent.add_child(glow)

	# Main hexagon
	var gem = Polygon2D.new()
	gem.polygon = hex_points
	gem.color = color
	parent.add_child(gem)

	# Top-right facet (lighter)
	var facet1 = Polygon2D.new()
	facet1.polygon = PackedVector2Array([
		Vector2(cx, cy),
		hex_points[0],
		hex_points[1],
		hex_points[2]
	])
	facet1.color = color.lightened(0.25)
	parent.add_child(facet1)

	# Highlight
	var highlight = _create_circle_polygon(Vector2(cx - 3, cy - 4), 3, Color.WHITE)
	highlight.color.a = 0.5
	parent.add_child(highlight)

func _create_pentagon_gem(parent: Control, color: Color) -> void:
	"""Rare rarity - pentagon (5 sides, more angular than hexagon)"""
	var cx = 16.0
	var cy = 16.0
	var radius = 12.0

	# Create pentagon points (point at top)
	var pent_points = PackedVector2Array()
	var glow_points = PackedVector2Array()
	for i in range(5):
		var angle = i * TAU / 5 - PI / 2  # Point at top
		pent_points.append(Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius))
		glow_points.append(Vector2(cx + cos(angle) * (radius + 3), cy + sin(angle) * (radius + 3)))

	# Outer glow
	var glow = Polygon2D.new()
	glow.polygon = glow_points
	glow.color = Color(color.r, color.g, color.b, 0.3)
	parent.add_child(glow)

	# Main pentagon
	var gem = Polygon2D.new()
	gem.polygon = pent_points
	gem.color = color
	parent.add_child(gem)

	# Top facet (lighter) - from center to top two points
	var facet1 = Polygon2D.new()
	facet1.polygon = PackedVector2Array([
		Vector2(cx, cy),
		pent_points[0],  # Top point
		pent_points[1]   # Top-right
	])
	facet1.color = color.lightened(0.3)
	parent.add_child(facet1)

	# Bottom-left facet (darker)
	var facet2 = Polygon2D.new()
	facet2.polygon = PackedVector2Array([
		Vector2(cx, cy),
		pent_points[3],
		pent_points[4]
	])
	facet2.color = color.darkened(0.15)
	parent.add_child(facet2)

	# Bright highlight at top
	var highlight = Polygon2D.new()
	highlight.polygon = PackedVector2Array([
		Vector2(cx - 2, cy - 6),
		Vector2(cx + 2, cy - 3),
		Vector2(cx - 1, cy - 2)
	])
	highlight.color = Color(1, 1, 1, 0.6)
	parent.add_child(highlight)

func _create_circle_polygon(center: Vector2, radius: float, color: Color) -> Polygon2D:
	var polygon = Polygon2D.new()
	var points = PackedVector2Array()
	var segments = 16

	for i in range(segments):
		var angle = i * TAU / segments
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	polygon.polygon = points
	polygon.color = color
	return polygon

func _update_progress_display(total: int, tier_key: String) -> void:
	if not stats_panel:
		return

	# Use backend-provided tier thresholds if available
	var backend_thresholds = MantleAuth.tier_thresholds
	var tiers_data = backend_thresholds.get("tiers", {})
	var tier_order = backend_thresholds.get("order", [])

	# Fallback to hardcoded if backend doesn't provide thresholds
	var thresholds = {
		"initiate": [0, 100, "Bronze", "bronze"],
		"bronze": [100, 500, "Silver", "silver"],
		"silver": [500, 1000, "Gold", "gold"],
		"gold": [1000, 2000, "Platinum", "platinum"],
		"platinum": [2000, 3000, "Diamond", "diamond"],
		"diamond": [3000, 5000, "Legendary", "legendary"],
		"legendary": [5000, 7500, "Mythic", "mythic"],
		"mythic": [7500, 7500, "", "mythic"]
	}

	var tier_start = 0
	var tier_end = 100
	var next_tier = "Bronze"
	var next_tier_key = "bronze"

	# Try to use backend thresholds
	if tiers_data.size() > 0 and tier_order.size() > 0:
		# Reverse order since backend sends highest first
		var ordered_tiers = tier_order.duplicate()
		ordered_tiers.reverse()  # Now: initiate, bronze, silver, ...

		var current_tier_data = tiers_data.get(tier_key, {})
		tier_start = int(current_tier_data.get("min_score", 0))

		# Find the next tier in order
		var current_idx = ordered_tiers.find(tier_key)
		if current_idx >= 0 and current_idx < ordered_tiers.size() - 1:
			next_tier_key = ordered_tiers[current_idx + 1]
			var next_tier_data = tiers_data.get(next_tier_key, {})
			tier_end = int(next_tier_data.get("min_score", tier_start + 100))
			next_tier = next_tier_data.get("name", next_tier_key.capitalize())
		else:
			# At max tier
			tier_end = tier_start
			next_tier = ""
			next_tier_key = tier_key

		print("[Armory] Using backend thresholds: %s (%d) -> %s (%d)" % [tier_key, tier_start, next_tier_key, tier_end])
	else:
		# Use fallback hardcoded thresholds
		var threshold = thresholds.get(tier_key, [0, 100, "Bronze", "bronze"])
		tier_start = threshold[0]
		tier_end = threshold[1]
		next_tier = threshold[2]
		next_tier_key = threshold[3]
		print("[Armory] Using fallback thresholds (no backend data)")

	var progress_pct = 0.0
	if tier_end > tier_start:
		progress_pct = clampf(float(total - tier_start) / float(tier_end - tier_start), 0.0, 1.0)

	# Update compact progress section (new 3-column layout)
	var progress_section = stats_panel.find_child("ProgressSection", true, false)
	if progress_section:
		# Update current tier emblem (enhanced version)
		var current_emblem = progress_section.find_child("CurrentTierEmblem", true, false)
		if current_emblem:
			_update_tier_emblem(current_emblem, tier_key, true)
		# Fallback: old label style
		var current_tier_label = progress_section.find_child("CurrentTierLabel", true, false)
		if current_tier_label:
			current_tier_label.text = tier_key.capitalize()
			current_tier_label.add_theme_color_override("font_color", TIER_COLORS.get(tier_key, Color.GRAY))

		# Update next tier emblem (enhanced version)
		var next_emblem = progress_section.find_child("NextTierEmblem", true, false)
		if next_emblem:
			if tier_key == "mythic":
				_update_tier_emblem(next_emblem, "mythic", false)
			else:
				_update_tier_emblem(next_emblem, next_tier_key, false)
		# Fallback: old label style
		var next_tier_label = progress_section.find_child("NextTierLabel", true, false)
		if next_tier_label:
			if tier_key == "mythic":
				next_tier_label.text = "MAX"
				next_tier_label.add_theme_color_override("font_color", TIER_COLORS["mythic"])
			else:
				next_tier_label.text = next_tier
				next_tier_label.add_theme_color_override("font_color", TIER_COLORS.get(next_tier_key, Color.GRAY))

		# Update progress bar fill (TierProgressBar) with enhanced glow
		var tier_progress_bar = progress_section.find_child("TierProgressBar", true, false)
		if tier_progress_bar and tier_progress_bar is ProgressBar:
			tier_progress_bar.value = progress_pct * 100
			var tier_color = TIER_COLORS.get(tier_key, Color.GRAY)
			var fill_style = StyleBoxFlat.new()
			fill_style.bg_color = tier_color
			fill_style.set_corner_radius_all(8)
			# Enhanced: Add glow effect
			fill_style.border_color = tier_color.lightened(0.3)
			fill_style.border_width_top = 2
			fill_style.shadow_color = Color(tier_color.r, tier_color.g, tier_color.b, 0.5)
			fill_style.shadow_size = 6
			tier_progress_bar.add_theme_stylebox_override("fill", fill_style)
			print("[Armory] Progress bar updated: %d%% [%d in %s tier, range %d-%d]" % [int(progress_pct * 100), total, tier_key, tier_start, tier_end])

		# Update progress text
		var progress_text = progress_section.find_child("ProgressText", true, false)
		if progress_text:
			if tier_key == "mythic":
				progress_text.text = "Maximum tier achieved!"
			else:
				# Show progress within tier: "27 / 2,500 to Mythic"
				var progress_in_tier = total - tier_start
				var tier_range = tier_end - tier_start
				progress_text.text = "%s / %s to %s" % [_format_number(progress_in_tier), _format_number(tier_range), next_tier]

	# Fallback: Update ProgressBar widget if present (old style)
	var progress_bar = stats_panel.find_child("TierProgressBar", true, false)
	if progress_bar and progress_bar is ProgressBar:
		progress_bar.value = progress_pct * 100
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = TIER_COLORS.get(tier_key, Color.GRAY)
		fill_style.set_corner_radius_all(4)
		progress_bar.add_theme_stylebox_override("fill", fill_style)

func _update_achievements_display() -> void:
	if not achievements_panel:
		return

	var your_section = achievements_panel.find_child("YourAchievementsSection", true, false)
	var your_list = achievements_panel.find_child("YourAchievementsList", true, false)
	var teaser_container = achievements_panel.find_child("TeaserContainer", true, false)

	var mantle = profile.get("mantle", {})
	var notable = mantle.get("notable_achievements", [])

	if notable == null or notable.is_empty():
		# No notable achievements - show only teasers
		if your_section:
			your_section.visible = false
		if teaser_container:
			teaser_container.visible = true
		return

	# Player has notable achievements - show their section
	if your_section:
		your_section.visible = true

	# Clear existing items
	if your_list:
		for child in your_list.get_children():
			child.queue_free()

		# Add player's notable achievements
		for ach in notable.slice(0, 4):  # Show max 4
			var item = _create_achievement_item(ach)
			your_list.add_child(item)

	# Optionally hide teasers when player has their own achievements
	# (or keep them visible for discovery - let's keep them for now but dimmer)
	if teaser_container and notable.size() >= 3:
		teaser_container.visible = false

func _create_achievement_item(ach: Dictionary) -> Control:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	# Larger icon (32-40px equivalent)
	var icon = Label.new()
	icon.text = "🏆"
	icon.add_theme_font_override("font", default_font)
	icon.add_theme_font_size_override("font_size", 72)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(icon)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	container.add_child(vbox)

	var name_label = Label.new()
	name_label.text = ach.get("display_name", ach.get("api_name", "Unknown"))
	name_label.add_theme_font_override("font", default_font)
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(name_label)

	var rarity = ach.get("rarity_tier", "Common")
	var rarity_color = RARITY_COLORS.get(rarity, Color.GRAY)
	var sub_label = Label.new()
	sub_label.text = "%s • %s" % [ach.get("provider", "").capitalize(), rarity]
	sub_label.add_theme_font_override("font", default_font)
	sub_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	sub_label.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(sub_label)

	return container

func _update_forged_display() -> void:
	# Forged items now shown in ForgeUI, not main Armory
	if not forged_panel:
		return
	var forged_list = forged_panel.find_child("ForgedList", true, false)
	if not forged_list:
		return

	for child in forged_list.get_children():
		child.queue_free()

	var mantle = profile.get("mantle", {})
	var forged = mantle.get("forged_items", [])

	if forged == null or forged.is_empty():
		var placeholder = Label.new()
		placeholder.text = "No forged items yet"
		placeholder.add_theme_font_override("font", default_font)
		placeholder.add_theme_font_size_override("font_size", FONT_CAPTION)
		placeholder.add_theme_color_override("font_color", TEXT_SECONDARY)
		forged_list.add_child(placeholder)
		return

	for item in forged.slice(0, 3):  # Show max 3
		var forged_item = _create_forged_item(item)
		forged_list.add_child(forged_item)

func _create_forged_item(item: Dictionary) -> Control:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 10)

	var is_earned = item.get("is_earned", false)

	var icon = Label.new()
	icon.text = "⭐" if is_earned else "◇"
	icon.add_theme_font_override("font", default_font)
	icon.add_theme_font_size_override("font_size", FONT_H2)
	icon.add_theme_color_override("font_color", Color("#ffd700") if is_earned else Color("#c0c0c0"))
	container.add_child(icon)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	container.add_child(vbox)

	var name_label = Label.new()
	name_label.text = item.get("achievement_api_name", "Unknown")
	name_label.add_theme_font_override("font", default_font)
	name_label.add_theme_font_size_override("font_size", FONT_CAPTION)
	name_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	vbox.add_child(name_label)

	var provenance = Label.new()
	provenance.text = "EARNED - Original holder" if is_earned else "TRADED - Acquired"
	provenance.add_theme_font_override("font", default_font)
	provenance.add_theme_font_size_override("font_size", FONT_TINY)
	provenance.add_theme_color_override("font_color", Color("#ffd700") if is_earned else Color("#c0c0c0"))
	vbox.add_child(provenance)

	return container

# ═══════════════════════════════════════════════════════════════════════════════
# ANIMATIONS
# ═══════════════════════════════════════════════════════════════════════════════

func _play_entrance_animations() -> void:
	_load_complete = true

	# Staggered panel entrance animations
	_animate_panel_entrances()

	# Animate progress bar
	_animate_progress_bar()

	# Start tier badge pulse
	if tier_badge:
		var mantle = profile.get("mantle", {})
		var tier_key = mantle.get("tier", "initiate").to_lower()
		var color = TIER_COLORS.get(tier_key, TIER_COLORS["initiate"])
		_start_badge_pulse(tier_badge, color)

	# Add shimmer effect to stats panel
	_play_shimmer_effect()

	# Start ENTER WORLD button pulse
	_start_enter_button_pulse()

	# Animate achievement count up
	_animate_achievement_count()

	# Animate forge grid items with stagger
	_animate_forge_grid_stagger()

func _animate_achievement_count() -> void:
	"""Animate the achievement count from 0 to target with satisfying count-up effect"""
	if not total_label or _target_achievement_count <= 0:
		return

	if _count_tween:
		_count_tween.kill()

	var duration = min(1.5, 0.5 + (_target_achievement_count / 5000.0))  # Scale duration with count
	var current_count = {"value": 0}

	_count_tween = create_tween()
	_count_tween.set_ease(Tween.EASE_OUT)
	_count_tween.set_trans(Tween.TRANS_CUBIC)

	# Animate the count using a method call
	_count_tween.tween_method(
		func(val: float):
			var count = int(val)
			var formatted = _format_number(count)
			total_label.text = formatted
			# Also update the glow label if present (enhanced trophy plaque)
			var glow_label = stats_panel.find_child("NumberGlow", true, false) if stats_panel else null
			if glow_label:
				glow_label.text = formatted
			# Add subtle scale pop at milestones
			if count > 0 and count % 500 == 0:
				var pop_tween = create_tween()
				pop_tween.tween_property(total_label, "scale", Vector2(1.05, 1.05), 0.05)
				pop_tween.tween_property(total_label, "scale", Vector2(1.0, 1.0), 0.1),
		0.0,
		float(_target_achievement_count),
		duration
	)

	# Final pop when complete
	_count_tween.tween_callback(func():
		var final_tween = create_tween()
		final_tween.tween_property(total_label, "scale", Vector2(1.08, 1.08), 0.08)
		final_tween.tween_property(total_label, "scale", Vector2(1.0, 1.0), 0.15)
	)

func _animate_forge_grid_stagger() -> void:
	"""Animate forge grid items with staggered fade-in effect"""
	if not _forge_content_container:
		return

	# Find the flow container with items
	var flow: HFlowContainer = null
	for child in _forge_content_container.get_children():
		if child is MarginContainer:
			for subchild in child.get_children():
				if subchild is HFlowContainer:
					flow = subchild
					break

	if not flow:
		return

	# Get all item cards
	var items = flow.get_children()
	if items.is_empty():
		return

	# Set all items invisible initially
	for item in items:
		item.modulate = Color(1, 1, 1, 0)
		item.scale = Vector2(0.9, 0.9)

	# Animate each item with stagger
	for i in range(items.size()):
		var item = items[i]
		var delay = i * 0.03  # 30ms stagger per item

		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)

		if delay > 0:
			tween.tween_interval(delay)

		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.25)
		tween.tween_property(item, "scale", Vector2(1.0, 1.0), 0.3)

func _animate_panel_entrances() -> void:
	# Collect all panels in order for staggered animation
	var panels_to_animate: Array[Control] = []

	# Left column: character preview, then cosmetics
	if character_preview:
		panels_to_animate.append(character_preview)
	if cosmetics_panel:
		panels_to_animate.append(cosmetics_panel)

	# Middle column: stats panel
	if stats_panel:
		panels_to_animate.append(stats_panel)

	# Right column: forge section (find it), then achievements
	var forge_section = find_child("OpenForgeBtn", true, false)
	if forge_section:
		var forge_panel = forge_section.get_parent().get_parent().get_parent()  # Navigate up to PanelContainer
		if forge_panel and forge_panel is PanelContainer:
			panels_to_animate.append(forge_panel)
	if achievements_panel:
		panels_to_animate.append(achievements_panel)

	# Animate each panel with staggered timing
	for i in range(panels_to_animate.size()):
		var panel = panels_to_animate[i]
		_animate_single_panel_entrance(panel, i * 0.08)  # 80ms stagger

func _animate_single_panel_entrance(panel: Control, delay: float) -> void:
	if not panel:
		return

	# Store original position and make invisible initially
	var original_position = panel.position
	var original_modulate = panel.modulate

	# Start state: slightly below and transparent
	panel.modulate = Color(1, 1, 1, 0)
	panel.position.y += 20

	# Create entrance tween after delay
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Wait for stagger delay
	if delay > 0:
		tween.tween_interval(delay)

	# Animate in: fade + slide up
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", original_modulate.a, 0.35)
	tween.tween_property(panel, "position:y", original_position.y, 0.4)

func _animate_progress_bar() -> void:
	var progress_section = stats_panel.find_child("ProgressSection", true, false)
	if not progress_section:
		return

	var progress_fill = progress_section.find_child("ProgressFill", true, false)
	if not progress_fill:
		return

	# Store target width and animate from 0
	var target_width = progress_fill.custom_minimum_size.x
	progress_fill.custom_minimum_size.x = 0

	if _progress_tween:
		_progress_tween.kill()
	_progress_tween = create_tween()
	_progress_tween.set_ease(Tween.EASE_OUT)
	_progress_tween.set_trans(Tween.TRANS_CUBIC)
	_progress_tween.tween_property(progress_fill, "custom_minimum_size:x", target_width, 0.8)

var _badge_shimmer_tween: Tween = null

func _start_badge_shimmer() -> void:
	"""Add a periodic horizontal shimmer sweep across the tier badge"""
	if not tier_badge:
		return

	# Enable clipping on badge
	tier_badge.clip_contents = true

	# Create shimmer overlay
	var shimmer = ColorRect.new()
	shimmer.name = "BadgeShimmer"
	shimmer.color = Color(1, 1, 1, 0.3)
	shimmer.size = Vector2(20, 50)  # Narrow vertical bar
	shimmer.position = Vector2(-30, -5)  # Start off-screen left
	shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shimmer.rotation_degrees = -15  # Slight angle for polish
	tier_badge.add_child(shimmer)

	# Create looping shimmer animation
	_badge_shimmer_tween = create_tween()
	_badge_shimmer_tween.set_loops()

	# Wait 3 seconds, then sweep across
	_badge_shimmer_tween.tween_interval(3.0)
	_badge_shimmer_tween.tween_property(shimmer, "position:x", 120.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	_badge_shimmer_tween.tween_property(shimmer, "position:x", -30.0, 0.0)  # Reset instantly

var _enter_button_tween: Tween = null

func _start_enter_button_pulse() -> void:
	if not enter_world_button:
		return

	var normal_style = enter_world_button.get_meta("normal_style") as StyleBoxFlat
	if not normal_style:
		return

	# Create subtle breathing pulse on the button's glow
	if _enter_button_tween:
		_enter_button_tween.kill()

	_enter_button_tween = create_tween()
	_enter_button_tween.set_loops()
	_enter_button_tween.set_ease(Tween.EASE_IN_OUT)
	_enter_button_tween.set_trans(Tween.TRANS_SINE)

	# Pulse the shadow size for a breathing effect
	_enter_button_tween.tween_property(normal_style, "shadow_size", 12, 1.2)
	_enter_button_tween.tween_property(normal_style, "shadow_size", 8, 1.2)

	# Also subtly pulse the shadow alpha
	var base_alpha = 0.4
	var pulse_alpha = 0.55
	_enter_button_tween.parallel().tween_property(normal_style, "shadow_color:a", pulse_alpha, 1.2)
	_enter_button_tween.tween_property(normal_style, "shadow_color:a", base_alpha, 1.2)

func _play_shimmer_effect() -> void:
	if not stats_panel:
		return

	# Create a shimmer overlay
	var shimmer = ColorRect.new()
	shimmer.name = "ShimmerEffect"
	shimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	shimmer.color = Color(1, 1, 1, 0)
	shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.add_child(shimmer)

	# Animate shimmer
	if _shimmer_tween:
		_shimmer_tween.kill()
	_shimmer_tween = create_tween()
	_shimmer_tween.tween_property(shimmer, "color:a", 0.08, 0.3)
	_shimmer_tween.tween_property(shimmer, "color:a", 0.0, 0.5)
	_shimmer_tween.tween_callback(shimmer.queue_free)

# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _format_number(num: int) -> String:
	var s = str(num)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

# ═══════════════════════════════════════════════════════════════════════════════
# BUTTON HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_enter_world_pressed() -> void:
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	LogManager.info("Entering game world from Armory", "mantle")
	entered_world.emit()
	enter_world_button.disabled = true
	enter_world_button.text = "Loading..."
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file("res://main.tscn")

func _on_logout_pressed() -> void:
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	LogManager.info("Logging out from Armory", "mantle")
	if MantleAuth:
		MantleAuth.logout()
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

func _on_settings_pressed() -> void:
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	LogManager.info("Opening settings from Armory", "ui")
	if settings_panel:
		settings_panel.visible = true

func _on_open_forge_pressed() -> void:
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	LogManager.info("Opening Forge UI", "mantle")
	# TODO: Open ForgeUI overlay
	# For now, show a placeholder message
	var pending = _get_pending_forge_count()
	if pending > 0:
		print("[Armory] Opening forge with %d pending items" % pending)
	else:
		print("[Armory] Forge opened - no pending items")

func _on_browse_forgeable_pressed() -> void:
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	LogManager.info("Opening web forge browser", "mantle")
	# Open the web forge in browser
	var forge_url = MantleAuth.get_api_base().replace("/api", "") + "/forge"
	OS.shell_open(forge_url)

func _get_pending_forge_count() -> int:
	# TODO: Get from MantleAuth.pending_forges when API supports it
	return 0

func _update_forge_section() -> void:
	var pending_label = find_child("PendingLabel", true, false)
	if pending_label:
		var pending_count = _get_pending_forge_count()
		if pending_count > 0:
			pending_label.text = "%d item%s ready to claim" % [pending_count, "s" if pending_count > 1 else ""]
			pending_label.add_theme_color_override("font_color", MANTLE_CYAN)
		else:
			pending_label.text = "No items waiting"
			pending_label.add_theme_color_override("font_color", TEXT_SECONDARY)

# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func refresh() -> void:
	_determine_state()
	_setup_ui_for_state()
	_apply_font_to_all(self)  # Re-apply fonts to new dynamic content

# ═══════════════════════════════════════════════════════════════════════════════
# SETTINGS PANEL
# ═══════════════════════════════════════════════════════════════════════════════

func _build_settings_panel() -> void:
	"""Build settings overlay panel"""
	# Full-screen overlay
	settings_panel = Control.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	add_child(settings_panel)

	# Dark overlay background (click to close)
	var overlay_bg = ColorRect.new()
	overlay_bg.name = "OverlayBG"
	overlay_bg.color = Color(0, 0, 0, 0.7)
	overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_bg.gui_input.connect(_on_settings_overlay_click)
	settings_panel.add_child(overlay_bg)

	# Centered panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = CARD_BG
	panel_style.border_color = MANTLE_CYAN
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Header
	var header = Label.new()
	header.text = "SETTINGS"
	header.add_theme_font_override("font", default_font)
	header.add_theme_font_size_override("font_size", FONT_H2)
	header.add_theme_color_override("font_color", MANTLE_CYAN)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Audio Section
	var audio_header = Label.new()
	audio_header.text = "AUDIO"
	audio_header.add_theme_font_override("font", default_font)
	audio_header.add_theme_font_size_override("font_size", FONT_CAPTION)
	audio_header.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(audio_header)

	# Master Volume
	var master_row = _create_slider_row("Master Volume", 0, 100, 80)
	master_volume_slider = master_row.get_node("Slider")
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	vbox.add_child(master_row)

	# Music Volume
	var music_row = _create_slider_row("Music Volume", 0, 100, 70)
	music_volume_slider = music_row.get_node("Slider")
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	vbox.add_child(music_row)

	# SFX Volume
	var sfx_row = _create_slider_row("SFX Volume", 0, 100, 80)
	sfx_volume_slider = sfx_row.get_node("Slider")
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	vbox.add_child(sfx_row)

	# Display Section
	var display_header = Label.new()
	display_header.text = "DISPLAY"
	display_header.add_theme_font_override("font", default_font)
	display_header.add_theme_font_size_override("font_size", FONT_CAPTION)
	display_header.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(display_header)

	# Fullscreen
	var fullscreen_row = HBoxContainer.new()
	fullscreen_row.add_theme_constant_override("separation", 12)
	vbox.add_child(fullscreen_row)

	var fullscreen_label = Label.new()
	fullscreen_label.text = "Fullscreen"
	fullscreen_label.add_theme_font_override("font", default_font)
	fullscreen_label.add_theme_font_size_override("font_size", FONT_BODY)
	fullscreen_label.add_theme_color_override("font_color", TEXT_PRIMARY)
	fullscreen_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fullscreen_row.add_child(fullscreen_label)

	fullscreen_check = CheckBox.new()
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	fullscreen_row.add_child(fullscreen_check)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# Close button
	var close_button = Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_secondary_button(close_button)
	close_button.pressed.connect(_on_settings_close_pressed)
	vbox.add_child(close_button)

	# Load saved settings
	_load_settings()

func _create_slider_row(label_text: String, min_val: float, max_val: float, default_val: float) -> Control:
	"""Create a labeled slider row for settings"""
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 6)

	var header_row = HBoxContainer.new()
	container.add_child(header_row)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_override("font", default_font)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(label)

	var value_label = Label.new()
	value_label.name = "ValueLabel"
	value_label.text = "%d%%" % int(default_val)
	value_label.add_theme_font_override("font", default_font)
	value_label.add_theme_font_size_override("font_size", FONT_BODY)
	value_label.add_theme_color_override("font_color", MANTLE_CYAN)
	value_label.custom_minimum_size = Vector2(50, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_row.add_child(value_label)

	var slider = HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.custom_minimum_size = Vector2(0, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(slider)

	# Update value label when slider changes
	slider.value_changed.connect(func(val): value_label.text = "%d%%" % int(val))

	return container

func _on_settings_overlay_click(event: InputEvent) -> void:
	"""Close settings when clicking outside the panel"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_settings_close_pressed()

func _on_settings_close_pressed() -> void:
	"""Close settings panel and save"""
	# Play click sound
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	if settings_panel:
		settings_panel.visible = false
	_save_settings()

func _on_master_volume_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0) if value > 0 else -80.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

func _on_music_volume_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0) if value > 0 else -80.0
	var music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, db)

func _on_sfx_volume_changed(value: float) -> void:
	var db = linear_to_db(value / 100.0) if value > 0 else -80.0
	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, db)
	# Also update SoundManager if available
	if SoundManager and SoundManager.has_method("set_sfx_volume"):
		SoundManager.set_sfx_volume(value / 100.0)

func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _load_settings() -> void:
	"""Load settings from config file"""
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")

	if err == OK:
		if master_volume_slider:
			master_volume_slider.value = config.get_value("audio", "master_volume", 80.0)
		if music_volume_slider:
			music_volume_slider.value = config.get_value("audio", "music_volume", 70.0)
		if sfx_volume_slider:
			sfx_volume_slider.value = config.get_value("audio", "sfx_volume", 80.0)
		if fullscreen_check:
			fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)

		# Apply loaded values
		if master_volume_slider:
			_on_master_volume_changed(master_volume_slider.value)
		if music_volume_slider:
			_on_music_volume_changed(music_volume_slider.value)
		if sfx_volume_slider:
			_on_sfx_volume_changed(sfx_volume_slider.value)

func _save_settings() -> void:
	"""Save settings to config file"""
	var config = ConfigFile.new()

	if master_volume_slider:
		config.set_value("audio", "master_volume", master_volume_slider.value)
	if music_volume_slider:
		config.set_value("audio", "music_volume", music_volume_slider.value)
	if sfx_volume_slider:
		config.set_value("audio", "sfx_volume", sfx_volume_slider.value)
	if fullscreen_check:
		config.set_value("display", "fullscreen", fullscreen_check.button_pressed)

	config.save("user://settings.cfg")
