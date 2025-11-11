extends Node

# Chain System Manager
# Tracks successful crit windows and applies damage multipliers

# Chain settings
@export var damage_per_chain_level: float = Constants.CHAIN_DAMAGE_PER_LEVEL
@export var max_chain_level: int = Constants.CHAIN_MAX_LEVEL
@export var chain_timeout: float = Constants.CHAIN_TIMEOUT

# Reset reasons enum
enum ResetReason {
	MANUAL,          # Player manually reset
	FAILED_WINDOW,   # Failed a crit window
	TIMEOUT,         # Chain timeout expired
	PLAYER_DEATH,    # Player died
	STAGE_END        # Level/stage ended
}

# State
var current_chain: int = 0
var last_attack_time: float = 0.0

# Signals - MUST be defined before _ready()
signal chain_increased(new_level: int)
signal chain_reset(reason: String)
signal overdrive_activated()

func _ready() -> void:
	print("ChainManager initialized")
	print("ChainManager has signals: chain_increased, chain_reset, overdrive_activated")

func _process(delta: float) -> void:
	if current_chain > 0:
		var time_since_attack = Time.get_ticks_msec() / 1000.0 - last_attack_time
		if time_since_attack >= chain_timeout:
			reset_chain(ResetReason.TIMEOUT)

func register_attack() -> void:
	last_attack_time = Time.get_ticks_msec() / 1000.0

func on_crit_window_completed(all_weakpoints_destroyed: bool) -> void:
	if all_weakpoints_destroyed:
		increase_chain()
	else:
		reset_chain(ResetReason.FAILED_WINDOW)

func increase_chain() -> void:
	if current_chain < max_chain_level:
		current_chain += 1
		print("⚡ Chain increased to ", current_chain, "x")
		chain_increased.emit(current_chain)
		
		# ✨ NEW: Play milestone sound at every 5 chain levels or at max
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager and (current_chain % Constants.CHAIN_MILESTONE_INTERVAL == 0 or current_chain == max_chain_level):
			sound_manager.play_sound_2d(sound_manager.SoundType.CHAIN_MILESTONE, -6.0)
		
		if current_chain == max_chain_level:
			print("🔥 OVERDRIVE! Maximum chain reached! 🔥")
			overdrive_activated.emit()
	else:
		print("⚡ Chain at maximum (", max_chain_level, "x)")

func reset_chain(reason: ResetReason = ResetReason.MANUAL) -> void:
	if current_chain > 0:
		print("💔 Chain reset from ", current_chain, "x (", ResetReason.keys()[reason], ")")
		
		# ✨ NEW: Play chain broken sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.CHAIN_BROKEN, -4.0)
		
		current_chain = 0
		chain_reset.emit(ResetReason.keys()[reason])

func get_damage_multiplier() -> float:
	return 1.0 + (current_chain * (damage_per_chain_level / 100.0))

func get_chain_level() -> int:
	return current_chain

func is_overdrive() -> bool:
	return current_chain >= max_chain_level
