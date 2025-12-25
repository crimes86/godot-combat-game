extends Node

## CombatJuice - Global combat feedback effects
## Add to project.godot autoloads as "CombatJuice"
##
## Provides:
## - Hit stop (freeze frames on impact)
## - Slow-mo on kill
## - Chromatic aberration pulses
## - Vignette effects

# ============================================
# HIT STOP (Freeze Frames)
# ============================================
# Brief pause on impact - sells the weight of hits

var _hitstop_end_time: float = 0.0  # Real time when hitstop should end
var _is_hitsopped: bool = false
var _original_time_scale: float = 1.0

## Duration of hit stop in seconds (2-4 frames at 60fps = 0.033-0.066s)
const HITSTOP_NORMAL: float = 0.04      # Normal hits: ~2 frames
const HITSTOP_CRIT: float = 0.06        # Crits: ~4 frames
const HITSTOP_WEAKPOINT: float = 0.08   # Weakpoint: ~5 frames
const HITSTOP_KILL: float = 0.10        # Killing blow: ~6 frames

# ============================================
# SLOW-MO (Kill Cam)
# ============================================

var _slowmo_end_time: float = 0.0  # Real time when slowmo should end
var _slowmo_target_scale: float = 1.0
var _is_in_slowmo: bool = false

const SLOWMO_KILL_DURATION: float = 0.15   # How long slowmo lasts
const SLOWMO_KILL_SCALE: float = 0.3       # Time scale during slowmo (0.3 = 30% speed)
const SLOWMO_RAMP_UP: float = 0.05         # Time to ramp back to normal

# ============================================
# VISUAL EFFECTS
# ============================================

var _vignette_intensity: float = 0.0
var _chromatic_intensity: float = 0.0
var _effect_decay_rate: float = 5.0

# Canvas modulate for screen effects (optional - if present in scene)
var _canvas_modulate: CanvasModulate = null
var _world_environment: WorldEnvironment = null

func _ready() -> void:
	print("✅ CombatJuice autoload initialized")
	process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when time_scale is 0

func _process(delta: float) -> void:
	# Use REAL time (not affected by Engine.time_scale)
	var real_time = Time.get_ticks_msec() / 1000.0

	# Handle hit stop using real time
	if _is_hitsopped:
		if real_time >= _hitstop_end_time:
			_end_hitstop()

	# Handle slow-mo using real time
	if _is_in_slowmo and not _is_hitsopped:
		if real_time >= _slowmo_end_time:
			# Ramp back to normal
			_is_in_slowmo = false
			var tween = create_tween()
			tween.tween_property(Engine, "time_scale", 1.0, SLOWMO_RAMP_UP)

	# Decay visual effects (use real delta when time is frozen)
	var real_delta = delta if Engine.time_scale > 0 else 0.016  # ~60fps fallback
	if _vignette_intensity > 0:
		_vignette_intensity = max(0, _vignette_intensity - _effect_decay_rate * real_delta)
	if _chromatic_intensity > 0:
		_chromatic_intensity = max(0, _chromatic_intensity - _effect_decay_rate * real_delta)

# ============================================
# HIT STOP API
# ============================================

## Trigger hit stop for normal hit
func hitstop_normal() -> void:
	_start_hitstop(HITSTOP_NORMAL)

## Trigger hit stop for critical hit
func hitstop_crit() -> void:
	_start_hitstop(HITSTOP_CRIT)

## Trigger hit stop for weakpoint hit
func hitstop_weakpoint() -> void:
	_start_hitstop(HITSTOP_WEAKPOINT)

## Trigger hit stop for killing blow
func hitstop_kill() -> void:
	_start_hitstop(HITSTOP_KILL)

## Generic hit stop with custom duration
func hitstop(duration: float) -> void:
	_start_hitstop(duration)

func _start_hitstop(duration: float) -> void:
	var real_time = Time.get_ticks_msec() / 1000.0
	var new_end_time = real_time + duration

	# Don't interrupt longer hit stops with shorter ones
	if _is_hitsopped and _hitstop_end_time > new_end_time:
		return

	_original_time_scale = Engine.time_scale if not _is_hitsopped else _original_time_scale
	_hitstop_end_time = new_end_time
	_is_hitsopped = true
	Engine.time_scale = 0.0  # Complete freeze

func _end_hitstop() -> void:
	_is_hitsopped = false
	# Restore to slowmo scale if in slowmo, otherwise normal
	if _is_in_slowmo:
		Engine.time_scale = _slowmo_target_scale
	else:
		Engine.time_scale = _original_time_scale

# ============================================
# SLOW-MO API
# ============================================

## Trigger slow-mo for kill (brief dramatic pause)
func slowmo_kill() -> void:
	_start_slowmo(SLOWMO_KILL_DURATION, SLOWMO_KILL_SCALE)

## Generic slow-mo with custom duration and scale
func slowmo(duration: float, time_scale: float = 0.3) -> void:
	_start_slowmo(duration, time_scale)

func _start_slowmo(duration: float, target_scale: float) -> void:
	var real_time = Time.get_ticks_msec() / 1000.0
	_slowmo_end_time = real_time + duration
	_slowmo_target_scale = target_scale
	_is_in_slowmo = true

	# Only set time scale if not in hitstop
	if not _is_hitsopped:
		Engine.time_scale = target_scale

# ============================================
# VISUAL EFFECTS API
# ============================================

## Pulse vignette (screen edge darkening)
func vignette_pulse(intensity: float = 0.3) -> void:
	_vignette_intensity = min(_vignette_intensity + intensity, 1.0)
	# TODO: Hook up to shader when implemented

## Pulse chromatic aberration (RGB split)
func chromatic_pulse(intensity: float = 0.3) -> void:
	_chromatic_intensity = min(_chromatic_intensity + intensity, 1.0)
	# TODO: Hook up to shader when implemented

## Get current vignette intensity (for shaders to read)
func get_vignette_intensity() -> float:
	return _vignette_intensity

## Get current chromatic intensity (for shaders to read)
func get_chromatic_intensity() -> float:
	return _chromatic_intensity

# ============================================
# CONVENIENCE COMBOS
# ============================================

## All effects for a normal hit
func on_hit() -> void:
	# No effects on normal hits - keep combat smooth
	pass

## All effects for a critical hit
func on_crit() -> void:
	# No effects on crits - keep combat smooth
	pass

## All effects for a weakpoint hit
func on_weakpoint() -> void:
	# Quick punch for rapid clicking - noticeable but not overwhelming
	trigger_screen_shake(0.4)  # Medium punch per click (was 0.2 - too subtle)

## All effects for a killing blow
func on_kill() -> void:
	# BIG shake on weakpoint destruction - the payoff
	trigger_screen_shake(0.85)  # Big satisfying explosion

## Trigger screen shake via the LOCAL player's ScreenShake node
func trigger_screen_shake(trauma_amount: float) -> void:
	# Find the LOCAL player (the one we control), not just any player in multiplayer
	var local_player: Node = null
	var my_peer_id = get_tree().get_multiplayer().get_unique_id() if get_tree().get_multiplayer().has_multiplayer_peer() else 1

	for player in get_tree().get_nodes_in_group("player"):
		if player.get_multiplayer_authority() == my_peer_id:
			local_player = player
			break

	# Fallback to first player in single-player
	if not local_player:
		local_player = get_tree().get_first_node_in_group("player")

	if local_player and local_player.has_node("ScreenShake"):
		var screen_shake = local_player.get_node("ScreenShake")
		screen_shake.add_trauma(trauma_amount)
