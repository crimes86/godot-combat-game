extends Node

## Ossuary Influence System
## Tracks the skeleton faction's grip on the world via a 0-100 influence meter.
## Influence passively grows over time and decays when players kill skeletons.
##
## Server-authoritative: the host runs the simulation, clients receive updates via RPC.
## In single-player, runs locally.

# ═══════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════

signal influence_changed(new_value: float)
signal threshold_crossed(tier: int, rising: bool)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Timing
const TICK_INTERVAL: float = 5.0      # Seconds between passive growth ticks
const SYNC_INTERVAL: float = 10.0     # Seconds between client sync broadcasts

## Growth & Decay
const PASSIVE_GROWTH_RATE: float = 0.15   # Influence gained per tick (~1.8/min)
const BASE_KILL_DECAY: float = 1.5        # Influence lost per regular skeleton kill
const GUARDIAN_KILL_DECAY: float = 4.0    # Influence lost per guardian skeleton kill
const LEVEL_DECAY_BONUS: float = 0.1      # Extra decay per enemy level above 1

## Bounds
const MIN_INFLUENCE: float = 0.0
const MAX_INFLUENCE: float = 100.0
const STARTING_INFLUENCE: float = 25.0    # Start at 25% — skeletons have a foothold

## Tier thresholds
const TIER_THRESHOLDS: Array[float] = [0.0, 25.0, 50.0, 75.0]
const TIER_NAMES: Array[String] = ["Quiet", "Stirring", "Rising", "Surging"]

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

var influence: float = STARTING_INFLUENCE
var _tick_timer: float = 0.0
var _sync_timer: float = 0.0
var _is_authority: bool = false  # True if we run the simulation (host or single-player)
var _previous_tier: int = -1
var _active: bool = false       # Only active during gameplay (not menus)

# HUD references
var _hud_layer: CanvasLayer = null
var _progress_bar: ProgressBar = null
var _tier_label: Label = null
var _hud_container: MarginContainer = null

# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_hud()
	_set_hud_visible(false)
	LogManager.info("OssuaryManager initialized (influence: %.1f)" % influence, "ossuary")

func _process(delta: float) -> void:
	if not _active:
		return

	if not _is_authority:
		return

	# Passive growth tick
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_passive_growth()

	# Sync to clients (multiplayer only)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer -= SYNC_INTERVAL
			_broadcast_influence.rpc(influence)

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func activate() -> void:
	"""Call when entering gameplay (after joining a game world)."""
	_active = true
	_is_authority = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	_previous_tier = get_influence_tier()
	_set_hud_visible(true)
	_update_hud()
	LogManager.info("Ossuary system activated (authority: %s, influence: %.1f)" % [_is_authority, influence], "ossuary")

func deactivate() -> void:
	"""Call when leaving gameplay (returning to menu, armory, etc.)."""
	_active = false
	_set_hud_visible(false)

func reset() -> void:
	"""Reset influence to starting value (new game/session)."""
	influence = STARTING_INFLUENCE
	_previous_tier = get_influence_tier()
	_tick_timer = 0.0
	_sync_timer = 0.0
	influence_changed.emit(influence)
	_update_hud()

func get_influence() -> float:
	return influence

func get_influence_tier() -> int:
	"""Returns 0-3 tier based on current influence."""
	if influence >= 75.0:
		return Constants.OSSUARY_TIER_SURGING
	elif influence >= 50.0:
		return Constants.OSSUARY_TIER_RISING
	elif influence >= 25.0:
		return Constants.OSSUARY_TIER_STIRRING
	else:
		return Constants.OSSUARY_TIER_QUIET

func get_tier_name() -> String:
	var tier = get_influence_tier()
	if tier >= 0 and tier < TIER_NAMES.size():
		return TIER_NAMES[tier]
	return "Unknown"

func on_skeleton_killed(enemy_level: int, is_guardian: bool, _position: Vector2) -> void:
	"""Called when a skeleton-type enemy dies. Reduces influence."""
	if not _is_authority:
		return

	var decay = GUARDIAN_KILL_DECAY if is_guardian else BASE_KILL_DECAY
	# Bonus decay for higher-level skeletons
	decay += max(0, enemy_level - 1) * LEVEL_DECAY_BONUS

	var old_influence = influence
	influence = clampf(influence - decay, MIN_INFLUENCE, MAX_INFLUENCE)

	if influence != old_influence:
		influence_changed.emit(influence)
		_check_threshold_crossing()
		_update_hud()

	if is_guardian:
		LogManager.debug("Guardian skeleton killed (L%d) — influence %.1f → %.1f (decay: %.1f)" % [enemy_level, old_influence, influence, decay], "ossuary")

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════════

func _apply_passive_growth() -> void:
	"""Server-side: increase influence passively."""
	var old_influence = influence
	influence = clampf(influence + PASSIVE_GROWTH_RATE, MIN_INFLUENCE, MAX_INFLUENCE)

	if influence != old_influence:
		influence_changed.emit(influence)
		_check_threshold_crossing()
		_update_hud()

func _check_threshold_crossing() -> void:
	"""Detect when influence crosses a tier boundary."""
	var current_tier = get_influence_tier()
	if current_tier != _previous_tier:
		var rising = current_tier > _previous_tier
		LogManager.info("Ossuary tier changed: %s → %s (%s)" % [
			TIER_NAMES[_previous_tier] if _previous_tier >= 0 else "None",
			TIER_NAMES[current_tier],
			"rising" if rising else "falling"
		], "ossuary")
		threshold_crossed.emit(current_tier, rising)
		_previous_tier = current_tier

@rpc("authority", "call_remote", "reliable")
func _broadcast_influence(value: float) -> void:
	"""Client-side: receive authoritative influence value from server."""
	influence = value
	influence_changed.emit(influence)
	_check_threshold_crossing()
	_update_hud()

# ═══════════════════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════════════════

func _create_hud() -> void:
	"""Build a small influence indicator in the top-right corner."""
	# Skip HUD on dedicated server
	if "--server" in OS.get_cmdline_user_args():
		return

	# CanvasLayer above PortraitHUD (105)
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "OssuaryHUD"
	_hud_layer.layer = 106
	add_child(_hud_layer)

	# Position below minimap (minimap: 220px diameter + 15px margin = bottom at 235px)
	# Quest tracker starts at 280, this sits in the gap between
	_hud_container = MarginContainer.new()
	_hud_container.name = "OssuaryContainer"
	_hud_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hud_container.offset_left = -200
	_hud_container.offset_right = -15
	_hud_container.offset_top = 240
	_hud_container.offset_bottom = 270
	_hud_layer.add_child(_hud_container)

	# Background panel for readability
	var panel = PanelContainer.new()
	panel.name = "BgPanel"

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	_hud_container.add_child(panel)

	# HBox: skull icon + bar + tier label
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	panel.add_child(hbox)

	# Skull label (using unicode skull)
	var skull_label = Label.new()
	skull_label.text = "\u2620"  # Skull and crossbones
	skull_label.add_theme_font_size_override("font_size", 14)
	skull_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(skull_label)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = influence
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(70, 12)
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# Style the bar background
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	# Style the bar fill
	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.7, 0.4)  # Will be updated dynamically
	bar_fill.corner_radius_top_left = 2
	bar_fill.corner_radius_top_right = 2
	bar_fill.corner_radius_bottom_left = 2
	bar_fill.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	hbox.add_child(_progress_bar)

	# Tier name label
	_tier_label = Label.new()
	_tier_label.text = "Quiet"
	_tier_label.add_theme_font_size_override("font_size", 11)
	_tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	_tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(_tier_label)

func _update_hud() -> void:
	"""Update HUD visuals to reflect current influence."""
	if not _progress_bar or not _tier_label:
		return

	_progress_bar.value = influence
	_tier_label.text = get_tier_name()

	# Color the fill bar based on influence level
	var fill_color: Color
	var label_color: Color

	if influence < 25.0:
		# Quiet — muted green
		fill_color = Color(0.3, 0.55, 0.35)
		label_color = Color(0.5, 0.6, 0.5)
	elif influence < 50.0:
		# Stirring — yellow-green
		fill_color = Color(0.55, 0.7, 0.3)
		label_color = Color(0.7, 0.75, 0.5)
	elif influence < 75.0:
		# Rising — orange
		fill_color = Color(0.8, 0.55, 0.2)
		label_color = Color(0.85, 0.65, 0.3)
	else:
		# Surging — red with pulse
		fill_color = Color(0.85, 0.2, 0.15)
		label_color = Color(0.9, 0.3, 0.2)

	# Update fill stylebox color
	var fill_style = _progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		fill_style.bg_color = fill_color

	_tier_label.add_theme_color_override("font_color", label_color)

func _set_hud_visible(visible: bool) -> void:
	"""Show/hide the HUD indicator."""
	if _hud_layer:
		_hud_layer.visible = visible
