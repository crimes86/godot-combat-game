extends Node

## Ossuary Influence & Corruption System
## Two meters that track the skeleton faction's grip on the world:
##   - Influence (0-100): Per-player, rises when that player kills skeletons, decays after idle.
##   - Corruption (0-100): Community-shared, grows passively, decays when any player kills skeletons.
##
## Server-authoritative: the host runs the simulation.
##   - Corruption is broadcast to all clients.
##   - Influence is sent per-player via targeted RPC.
## In single-player, runs locally.

# ═══════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════

signal influence_changed(new_value: float)
signal threshold_crossed(tier: int, rising: bool)
signal corruption_changed(new_value: float)
signal corruption_threshold_crossed(tier: int, rising: bool)

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Timing
const TICK_INTERVAL: float = 5.0      # Seconds between ticks
const SYNC_INTERVAL: float = 10.0     # Seconds between client sync broadcasts

## Influence — rises on kills, decays after idle
const INFLUENCE_BASE_GAIN: float = 1.0       # Influence gained per regular skeleton kill
const INFLUENCE_LEVEL_BONUS: float = 0.15    # Extra gain per enemy level above 1
const INFLUENCE_GUARDIAN_BONUS: float = 2.0  # Extra gain for guardian kills (added to base)
const INFLUENCE_DECAY_DELAY: float = 60.0    # Seconds of no kills before decay starts
const INFLUENCE_DECAY_RATE: float = 0.0167   # Influence lost per second during decay (~1.0/min)

## Corruption — grows passively, decays on kills
const CORRUPTION_GROWTH_RATE: float = 0.04   # Corruption gained per tick (~0.5/min)
const CORRUPTION_KILL_DECAY: float = 0.5     # Corruption lost per regular skeleton kill
const CORRUPTION_LEVEL_BONUS: float = 0.05   # Extra decay per enemy level above 1

## Bounds
const MIN_INFLUENCE: float = 0.0
const MAX_INFLUENCE: float = 100.0
const MIN_CORRUPTION: float = 0.0
const MAX_CORRUPTION: float = 100.0

## Tier thresholds (same breakpoints for both meters)
const TIER_THRESHOLDS: Array[float] = [0.0, 25.0, 50.0, 75.0]
const INFLUENCE_TIER_NAMES: Array[String] = ["Quiet", "Stirring", "Rising", "Surging"]
const CORRUPTION_TIER_NAMES: Array[String] = ["Clean", "Tainted", "Blighted", "Cursed"]

# ═══════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════

## Per-player influence (server-side): peer_id → float
var _player_influence: Dictionary = {}
## Per-player idle timer (server-side): peer_id → seconds since last kill
var _player_last_kill: Dictionary = {}

## Local player's influence (set by targeted RPC or directly in single-player)
var _local_influence: float = 0.0

## Shared corruption (community-wide)
var corruption: float = MAX_CORRUPTION  # Start fully corrupted — players must clear it

var _tick_timer: float = 0.0
var _sync_timer: float = 0.0
var _is_authority: bool = false  # True if we run the simulation (host or single-player)
var _previous_influence_tier: int = -1
var _previous_corruption_tier: int = -1
var _active: bool = false       # Only active during gameplay (not menus)

# HUD references
var _hud_layer: CanvasLayer = null
var _hud_container: MarginContainer = null
# Influence row
var _progress_bar: ProgressBar = null
var _tier_label: Label = null

# Flash tweens
var _flash_tween_influence: Tween = null

# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_hud()
	_set_hud_visible(false)
	# Clean up per-player data on disconnect
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	LogManager.info("OssuaryManager initialized (corruption: %.1f)" % [corruption], "ossuary")

func _process(delta: float) -> void:
	if not _active:
		return

	if not _is_authority:
		return

	# Tick-based updates (corruption growth)
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer -= TICK_INTERVAL
		_apply_corruption_growth()

	# Per-player influence decay after idle delay
	for peer_id in _player_influence.keys():
		_player_last_kill[peer_id] = _player_last_kill.get(peer_id, 0.0) + delta
		if _player_last_kill[peer_id] >= INFLUENCE_DECAY_DELAY and _player_influence[peer_id] > 0.0:
			var old_val = _player_influence[peer_id]
			_player_influence[peer_id] = clampf(old_val - INFLUENCE_DECAY_RATE * delta, MIN_INFLUENCE, MAX_INFLUENCE)
			# Update local display if this is our own influence (single-player / host)
			if _is_local_peer(peer_id):
				_local_influence = _player_influence[peer_id]
				if _local_influence != old_val:
					influence_changed.emit(_local_influence)
					_check_influence_threshold()
					_update_hud()

	# Sync to clients (multiplayer only)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer -= SYNC_INTERVAL
			_broadcast_corruption.rpc(corruption)
			# Send each player their own influence value
			for peer_id in _player_influence:
				_send_player_influence.rpc_id(peer_id, _player_influence[peer_id])

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func activate() -> void:
	"""Call when entering gameplay (after joining a game world)."""
	_active = true
	_is_authority = not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	_previous_influence_tier = get_influence_tier()
	_previous_corruption_tier = get_corruption_tier()
	_set_hud_visible(true)
	_update_hud()
	LogManager.info("Ossuary system activated (authority: %s, influence: %.1f, corruption: %.1f)" % [_is_authority, _local_influence, corruption], "ossuary")

func deactivate() -> void:
	"""Call when leaving gameplay (returning to menu, armory, etc.)."""
	_active = false
	_set_hud_visible(false)

func reset() -> void:
	"""Reset both meters (new game/session)."""
	_player_influence.clear()
	_player_last_kill.clear()
	_local_influence = 0.0
	corruption = MAX_CORRUPTION  # Start fully corrupted
	_previous_influence_tier = get_influence_tier()
	_previous_corruption_tier = get_corruption_tier()
	_tick_timer = 0.0
	_sync_timer = 0.0
	influence_changed.emit(_local_influence)
	corruption_changed.emit(corruption)
	_update_hud()

func get_influence() -> float:
	return _local_influence

func get_corruption() -> float:
	return corruption

func get_influence_tier() -> int:
	"""Returns 0-3 tier based on current influence."""
	if _local_influence >= 75.0:
		return Constants.OSSUARY_TIER_SURGING
	elif _local_influence >= 50.0:
		return Constants.OSSUARY_TIER_RISING
	elif _local_influence >= 25.0:
		return Constants.OSSUARY_TIER_STIRRING
	else:
		return Constants.OSSUARY_TIER_QUIET

func get_corruption_tier() -> int:
	"""Returns 0-3 tier based on current corruption."""
	if corruption >= 75.0:
		return Constants.OSSUARY_CORRUPTION_CURSED
	elif corruption >= 50.0:
		return Constants.OSSUARY_CORRUPTION_BLIGHTED
	elif corruption >= 25.0:
		return Constants.OSSUARY_CORRUPTION_TAINTED
	else:
		return Constants.OSSUARY_CORRUPTION_CLEAN

func get_influence_tier_name() -> String:
	var tier = get_influence_tier()
	if tier >= 0 and tier < INFLUENCE_TIER_NAMES.size():
		return INFLUENCE_TIER_NAMES[tier]
	return "Unknown"

func get_corruption_tier_name() -> String:
	var tier = get_corruption_tier()
	if tier >= 0 and tier < CORRUPTION_TIER_NAMES.size():
		return CORRUPTION_TIER_NAMES[tier]
	return "Unknown"

# Keep old name for compatibility
func get_tier_name() -> String:
	return get_influence_tier_name()

func get_corruption_display() -> Dictionary:
	"""Returns corruption display data (value, tier, colors) for world-space UI."""
	var tier = get_corruption_tier()
	var fill_color: Color
	var label_color: Color
	if corruption < 25.0:
		fill_color = Color(0.4, 0.45, 0.35)
		label_color = Color(0.55, 0.6, 0.5)
	elif corruption < 50.0:
		fill_color = Color(0.5, 0.55, 0.25)
		label_color = Color(0.6, 0.65, 0.35)
	elif corruption < 75.0:
		fill_color = Color(0.35, 0.6, 0.2)
		label_color = Color(0.45, 0.7, 0.25)
	else:
		fill_color = Color(0.2, 0.7, 0.15)
		label_color = Color(0.3, 0.8, 0.2)
	return {
		"value": corruption,
		"tier": tier,
		"tier_name": get_corruption_tier_name(),
		"fill_color": fill_color,
		"label_color": label_color
	}

func on_skeleton_killed(killer_peer_id: int, enemy_level: int, is_guardian: bool, _position: Vector2) -> void:
	"""Called when a skeleton-type enemy dies. Increases killer's influence, decreases shared corruption."""
	if not _is_authority:
		return

	# --- Per-player influence gain ---
	if not _player_influence.has(killer_peer_id):
		_player_influence[killer_peer_id] = 0.0
	_player_last_kill[killer_peer_id] = 0.0

	var gain = INFLUENCE_BASE_GAIN
	if is_guardian:
		gain += INFLUENCE_GUARDIAN_BONUS
	gain += max(0, enemy_level - 1) * INFLUENCE_LEVEL_BONUS

	var old_influence = _player_influence[killer_peer_id]
	_player_influence[killer_peer_id] = clampf(old_influence + gain, MIN_INFLUENCE, MAX_INFLUENCE)
	var new_influence = _player_influence[killer_peer_id]

	# --- Corruption decay (any kill counts for shared corruption) ---
	var corruption_decay = CORRUPTION_KILL_DECAY
	corruption_decay += max(0, enemy_level - 1) * CORRUPTION_LEVEL_BONUS

	var old_corruption = corruption
	corruption = clampf(corruption - corruption_decay, MIN_CORRUPTION, MAX_CORRUPTION)

	if corruption != old_corruption:
		corruption_changed.emit(corruption)
		_check_corruption_threshold()

	# --- Distribute updates ---
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		# Targeted influence RPC to killer
		_send_player_influence.rpc_id(killer_peer_id, new_influence)
		# Broadcast corruption to all clients
		_broadcast_corruption.rpc(corruption)
		# Update local display if server is also the killer
		if _is_local_peer(killer_peer_id):
			_local_influence = new_influence
			influence_changed.emit(_local_influence)
			_check_influence_threshold()
			_update_hud()
			_flash_bar(_progress_bar)
	else:
		# Single-player: update directly
		_local_influence = new_influence
		influence_changed.emit(_local_influence)
		_check_influence_threshold()
		_update_hud()
		_flash_bar(_progress_bar)

	if is_guardian:
		LogManager.debug("Guardian skeleton killed by peer %d (L%d) — influence %.1f → %.1f (+%.1f), corruption %.1f → %.1f (-%.1f)" % [
			killer_peer_id, enemy_level, old_influence, new_influence, gain, old_corruption, corruption, corruption_decay
		], "ossuary")

# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════════

func _is_local_peer(peer_id: int) -> bool:
	"""Check if a peer_id represents the local player."""
	if not multiplayer.has_multiplayer_peer():
		return true  # Single-player: peer 1 is always local
	return peer_id == multiplayer.get_unique_id()

func _on_peer_disconnected(peer_id: int) -> void:
	"""Clean up per-player data when a player disconnects."""
	if _player_influence.has(peer_id):
		_player_influence.erase(peer_id)
	if _player_last_kill.has(peer_id):
		_player_last_kill.erase(peer_id)
	LogManager.info("Ossuary: cleaned up data for disconnected peer %d" % peer_id, "ossuary")

func _apply_corruption_growth() -> void:
	"""Server-side: increase corruption passively each tick."""
	var old_corruption = corruption
	corruption = clampf(corruption + CORRUPTION_GROWTH_RATE, MIN_CORRUPTION, MAX_CORRUPTION)

	if corruption != old_corruption:
		corruption_changed.emit(corruption)
		_check_corruption_threshold()
		_update_hud()

func _check_influence_threshold() -> void:
	"""Detect when influence crosses a tier boundary."""
	var current_tier = get_influence_tier()
	if current_tier != _previous_influence_tier:
		var rising = current_tier > _previous_influence_tier
		LogManager.info("Ossuary influence tier changed: %s → %s (%s)" % [
			INFLUENCE_TIER_NAMES[_previous_influence_tier] if _previous_influence_tier >= 0 else "None",
			INFLUENCE_TIER_NAMES[current_tier],
			"rising" if rising else "falling"
		], "ossuary")
		threshold_crossed.emit(current_tier, rising)
		_previous_influence_tier = current_tier

func _check_corruption_threshold() -> void:
	"""Detect when corruption crosses a tier boundary."""
	var current_tier = get_corruption_tier()
	if current_tier != _previous_corruption_tier:
		var rising = current_tier > _previous_corruption_tier
		LogManager.info("Ossuary corruption tier changed: %s → %s (%s)" % [
			CORRUPTION_TIER_NAMES[_previous_corruption_tier] if _previous_corruption_tier >= 0 else "None",
			CORRUPTION_TIER_NAMES[current_tier],
			"rising" if rising else "falling"
		], "ossuary")
		corruption_threshold_crossed.emit(current_tier, rising)
		_previous_corruption_tier = current_tier

func _flash_bar(bar: ProgressBar) -> void:
	"""Quick white flash on a progress bar to highlight a change."""
	if not bar:
		return
	if _flash_tween_influence:
		_flash_tween_influence.kill()

	var tween = create_tween()
	tween.tween_property(bar, "modulate", Color(2, 2, 2), 0.05)
	tween.tween_property(bar, "modulate", Color(1, 1, 1), 0.25)
	_flash_tween_influence = tween

# ═══════════════════════════════════════════════════════════════════════════
# NETWORKING
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_remote", "reliable")
func _broadcast_corruption(corr_value: float) -> void:
	"""Client-side: receive authoritative corruption value from server."""
	var old_corruption = corruption
	corruption = corr_value
	if corruption != old_corruption:
		corruption_changed.emit(corruption)
		_check_corruption_threshold()
	_update_hud()

@rpc("authority", "call_remote", "reliable")
func _send_player_influence(inf_value: float) -> void:
	"""Client-side: receive your personal influence value from server."""
	var old_influence = _local_influence
	_local_influence = inf_value
	if _local_influence != old_influence:
		influence_changed.emit(_local_influence)
		_check_influence_threshold()
	_update_hud()
	# Flash on influence increase (kill happened)
	if _local_influence > old_influence:
		_flash_bar(_progress_bar)

# ═══════════════════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════════════════

func _create_hud() -> void:
	"""Build an influence indicator in the top-right corner."""
	# Skip HUD on dedicated server
	if "--server" in OS.get_cmdline_user_args():
		return

	# CanvasLayer above PortraitHUD (105)
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "OssuaryHUD"
	_hud_layer.layer = 106
	add_child(_hud_layer)

	# Position below minimap — single row for influence only
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

	# --- Influence row (skull icon + bar + tier label) ---
	var influence_row = HBoxContainer.new()
	influence_row.add_theme_constant_override("separation", 6)
	panel.add_child(influence_row)

	var skull_label = Label.new()
	skull_label.text = "\u2620"  # Skull and crossbones
	skull_label.add_theme_font_size_override("font_size", 14)
	skull_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	skull_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	influence_row.add_child(skull_label)

	_progress_bar = _create_bar(_local_influence)
	influence_row.add_child(_progress_bar)

	_tier_label = Label.new()
	_tier_label.text = "Quiet"
	_tier_label.add_theme_font_size_override("font_size", 11)
	_tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	_tier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	influence_row.add_child(_tier_label)

func _create_bar(initial_value: float) -> ProgressBar:
	"""Create a styled progress bar for either meter."""
	var bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = initial_value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(70, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.18, 0.9)
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.7, 0.4)  # Default green, updated dynamically
	bar_fill.corner_radius_top_left = 2
	bar_fill.corner_radius_top_right = 2
	bar_fill.corner_radius_bottom_left = 2
	bar_fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", bar_fill)

	return bar

func _update_hud() -> void:
	"""Update HUD visuals to reflect current influence and corruption."""
	if not _progress_bar or not _tier_label:
		return

	# --- Influence bar ---
	_progress_bar.value = _local_influence
	_tier_label.text = get_influence_tier_name()

	var inf_fill_color: Color
	var inf_label_color: Color

	if _local_influence < 25.0:
		inf_fill_color = Color(0.3, 0.55, 0.35)
		inf_label_color = Color(0.5, 0.6, 0.5)
	elif _local_influence < 50.0:
		inf_fill_color = Color(0.55, 0.7, 0.3)
		inf_label_color = Color(0.7, 0.75, 0.5)
	elif _local_influence < 75.0:
		inf_fill_color = Color(0.8, 0.55, 0.2)
		inf_label_color = Color(0.85, 0.65, 0.3)
	else:
		inf_fill_color = Color(0.85, 0.2, 0.15)
		inf_label_color = Color(0.9, 0.3, 0.2)

	var inf_fill = _progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if inf_fill:
		inf_fill.bg_color = inf_fill_color
	_tier_label.add_theme_color_override("font_color", inf_label_color)

func _set_hud_visible(visible: bool) -> void:
	"""Show/hide the HUD indicator."""
	if _hud_layer:
		_hud_layer.visible = visible
