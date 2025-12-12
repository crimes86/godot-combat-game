extends Node
## Manages the day/night cycle with smooth lighting transitions
## 1 hour real time = 1 full day cycle (24 in-game hours)
## Server authoritative - server advances time and syncs to clients

signal time_changed(hour: float)
signal period_changed(period: String)  # "dawn", "day", "dusk", "night"

# Cycle configuration
const CYCLE_DURATION: float = 3600.0  # 1 hour (3600 seconds) = full day
var current_time: float = 12.0  # Start at noon (0-24 scale)
var cycle_paused: bool = false

# Multiplayer sync
const TIME_SYNC_INTERVAL: float = 5.0  # Sync time to clients every 5 seconds
var time_sync_timer: float = 0.0

# Lighting color presets
# Daytime (bright) - neutral white, not too washed out
const DAY_CANVAS_MODULATE := Color(1.0, 1.0, 0.98, 1.0)
# Nighttime (dark) - darker and more blue for moonlit feel
const NIGHT_CANVAS_MODULATE := Color(0.45, 0.48, 0.6, 1.0)
# Dawn (warm orange sunrise)
const DAWN_CANVAS_MODULATE := Color(0.95, 0.8, 0.7, 1.0)
# Dusk (warm orange/red sunset)
const DUSK_CANVAS_MODULATE := Color(0.9, 0.65, 0.55, 1.0)

# Time periods (in 24-hour format)
const DAWN_START := 5.0
const DAY_START := 7.0
const DUSK_START := 18.0
const NIGHT_START := 20.0

# Reference to the CanvasModulate node (set by GameWorld)
var canvas_modulate: CanvasModulate = null

var _last_period: String = ""

func _ready():
	print("TimeManager: Day/night cycle initialized (1 hour = full day)")
	print("TimeManager: Starting at noon (12:00)")
	print("TimeManager: Press F4 to advance time by 1 hour (debug)")

func _input(event: InputEvent):
	# F4 advances time by 1 hour for testing day/night cycle (dev builds only, server only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F4:
		# Only allow in editor or debug builds
		if not (OS.has_feature("editor") or OS.is_debug_build()):
			return
		if _is_server_or_singleplayer():
			advance_time(1.0)  # Advance 1 hour
			print("TimeManager: Time advanced to %s (%s)" % [get_time_string(), get_period()])
			# Sync to clients immediately
			_sync_time_to_clients()
		else:
			print("TimeManager: Only server can advance time")

func _process(delta: float):
	if cycle_paused or canvas_modulate == null:
		return

	# Only server advances time; clients receive synced time
	if _is_server_or_singleplayer():
		# Advance time: delta seconds of real time
		# CYCLE_DURATION seconds = 24 in-game hours
		var hours_per_second = 24.0 / CYCLE_DURATION
		current_time += delta * hours_per_second

		# Wrap around at 24 hours
		if current_time >= 24.0:
			current_time -= 24.0

		# Periodically sync time to clients
		time_sync_timer += delta
		if time_sync_timer >= TIME_SYNC_INTERVAL:
			time_sync_timer = 0.0
			_sync_time_to_clients()

	# Update lighting (all clients do this based on their current_time)
	update_lighting()

	# Emit signals
	emit_signal("time_changed", current_time)

	var current_period = get_period()
	if current_period != _last_period:
		_last_period = current_period
		emit_signal("period_changed", current_period)
		print("TimeManager: Period changed to %s (%s)" % [current_period, get_time_string()])

func _is_server_or_singleplayer() -> bool:
	"""Returns true if we're the server or playing singleplayer"""
	if not multiplayer.has_multiplayer_peer():
		return true  # Singleplayer
	return multiplayer.is_server()

func _sync_time_to_clients():
	"""Server syncs current time to all clients"""
	if not multiplayer.has_multiplayer_peer():
		return  # Singleplayer, no need to sync
	if not multiplayer.is_server():
		return  # Only server syncs

	# Call RPC to sync time to all clients
	_receive_time_sync.rpc(current_time)

@rpc("authority", "call_remote", "reliable")
func _receive_time_sync(server_time: float):
	"""Client receives time sync from server"""
	current_time = server_time
	update_lighting()

func update_lighting():
	if canvas_modulate == null:
		return

	var target_color: Color

	# Determine which transition we're in and interpolate
	if current_time >= NIGHT_START or current_time < DAWN_START:
		# Full night (20:00 - 5:00)
		target_color = NIGHT_CANVAS_MODULATE
	elif current_time >= DAWN_START and current_time < DAY_START:
		# Dawn transition (5:00 - 7:00)
		var t = (current_time - DAWN_START) / (DAY_START - DAWN_START)
		target_color = NIGHT_CANVAS_MODULATE.lerp(DAY_CANVAS_MODULATE, ease_in_out(t))
	elif current_time >= DAY_START and current_time < DUSK_START:
		# Full day (7:00 - 18:00)
		target_color = DAY_CANVAS_MODULATE
	elif current_time >= DUSK_START and current_time < NIGHT_START:
		# Dusk transition (18:00 - 20:00)
		var t = (current_time - DUSK_START) / (NIGHT_START - DUSK_START)
		target_color = DAY_CANVAS_MODULATE.lerp(NIGHT_CANVAS_MODULATE, ease_in_out(t))
	else:
		target_color = DAY_CANVAS_MODULATE

	canvas_modulate.color = target_color

func ease_in_out(t: float) -> float:
	# Smooth ease-in-out curve for natural transitions
	return t * t * (3.0 - 2.0 * t)

func get_period() -> String:
	if current_time >= NIGHT_START or current_time < DAWN_START:
		return "night"
	elif current_time >= DAWN_START and current_time < DAY_START:
		return "dawn"
	elif current_time >= DAY_START and current_time < DUSK_START:
		return "day"
	else:
		return "dusk"

func get_time_string() -> String:
	var hour = int(current_time)
	var minute = int((current_time - hour) * 60)
	return "%02d:%02d" % [hour, minute]

func get_brightness() -> float:
	# Returns 0.0 (darkest) to 1.0 (brightest)
	var color = canvas_modulate.color if canvas_modulate else DAY_CANVAS_MODULATE
	return (color.r + color.g + color.b) / 3.0

func set_time(hour: float):
	current_time = fmod(hour, 24.0)
	if current_time < 0:
		current_time += 24.0
	update_lighting()
	# Sync to clients if server
	if _is_server_or_singleplayer():
		_sync_time_to_clients()

func pause_cycle():
	cycle_paused = true
	print("TimeManager: Cycle paused at %s" % get_time_string())

func resume_cycle():
	cycle_paused = false
	print("TimeManager: Cycle resumed at %s" % get_time_string())

func set_canvas_modulate(node: CanvasModulate):
	canvas_modulate = node
	update_lighting()
	print("TimeManager: CanvasModulate connected")

func advance_time(hours: float):
	"""Advance time by specified hours (for debugging)"""
	current_time += hours
	if current_time >= 24.0:
		current_time -= 24.0
	elif current_time < 0:
		current_time += 24.0
	update_lighting()
	emit_signal("time_changed", current_time)  # Notify listeners (like TestHub)
