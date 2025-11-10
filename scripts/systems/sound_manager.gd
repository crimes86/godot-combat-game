extends Node

## Sound Manager - Generates placeholder sounds and manages audio playback
## Replace placeholder sounds with real audio files later by updating the respective AudioStream resources

# Sound Types
enum SoundType {
	# Player sounds
	SWING,
	MISS,
	
	# Enemy sounds  
	HIT_NORMAL,
	HIT_CRIT,
	HIT_WEAKPOINT,
	ENEMY_DEATH,
	ENEMY_SPAWN,
	
	# System sounds
	CRIT_WINDOW_OPEN,
	WEAKPOINT_DESTROYED,
	ALL_WEAKPOINTS_CLEARED,
	CHAIN_MILESTONE,
	CHAIN_BROKEN
}

# Cache for generated sounds
var sound_cache: Dictionary = {}

func _ready() -> void:
	# Pre-generate all placeholder sounds
	print("🔊 Generating placeholder sounds...")
	_generate_all_sounds()
	print("✅ Sound system ready!")

func _generate_all_sounds() -> void:
	# Player sounds
	sound_cache[SoundType.SWING] = _generate_swing()
	sound_cache[SoundType.MISS] = _generate_miss()
	
	# Enemy sounds
	sound_cache[SoundType.HIT_NORMAL] = _generate_hit_normal()
	sound_cache[SoundType.HIT_CRIT] = _generate_hit_crit()
	sound_cache[SoundType.HIT_WEAKPOINT] = _generate_hit_weakpoint()
	sound_cache[SoundType.ENEMY_DEATH] = _generate_enemy_death()
	sound_cache[SoundType.ENEMY_SPAWN] = _generate_enemy_spawn()
	
	# System sounds
	sound_cache[SoundType.CRIT_WINDOW_OPEN] = _generate_crit_window_open()
	sound_cache[SoundType.WEAKPOINT_DESTROYED] = _generate_weakpoint_destroyed()
	sound_cache[SoundType.ALL_WEAKPOINTS_CLEARED] = _generate_all_weakpoints_cleared()
	sound_cache[SoundType.CHAIN_MILESTONE] = _generate_chain_milestone()
	sound_cache[SoundType.CHAIN_BROKEN] = _generate_chain_broken()

## Play a sound at a specific position in the world
func play_sound(sound_type: SoundType, global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if not sound_cache.has(sound_type):
		push_error("Sound type not found: ", sound_type)
		return
	
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_cache[sound_type]
	player.volume_db = volume_db
	player.global_position = global_pos
	player.finished.connect(player.queue_free)
	
	get_tree().root.add_child(player)
	player.play()

## Play a sound without 2D positioning (UI sounds, etc)
func play_sound_2d(sound_type: SoundType, volume_db: float = 0.0) -> void:
	if not sound_cache.has(sound_type):
		push_error("Sound type not found: ", sound_type)
		return
	
	var player = AudioStreamPlayer.new()
	player.stream = sound_cache[sound_type]
	player.volume_db = volume_db
	player.finished.connect(player.queue_free)
	
	get_tree().root.add_child(player)
	player.play()

## Get a sound stream for attaching to existing AudioStreamPlayer nodes
func get_sound(sound_type: SoundType) -> AudioStream:
	return sound_cache.get(sound_type, null)

# ============================================
# PLACEHOLDER SOUND GENERATORS
# ============================================

func _generate_swing() -> AudioStreamWAV:
	# Whoosh sound - descending frequency
	return _create_wav_sweep(300.0, 150.0, 0.15, 0.3)

func _generate_miss() -> AudioStreamWAV:
	# Low "whiff" - quick descending tone
	return _create_wav_sweep(200.0, 100.0, 0.1, 0.2)

func _generate_hit_normal() -> AudioStreamWAV:
	# Light impact - short mid-range tone
	return _create_wav_tone(400.0, 0.08, 0.5)

func _generate_hit_crit() -> AudioStreamWAV:
	# Powerful hit - ascending pitch with punch
	return _create_wav_sweep(300.0, 600.0, 0.12, 0.7)

func _generate_hit_weakpoint() -> AudioStreamWAV:
	# Explosive hit - complex tone with harmonics
	return _create_wav_sweep(200.0, 800.0, 0.18, 0.8)

func _generate_enemy_death() -> AudioStreamWAV:
	# Dramatic descending sweep
	return _create_wav_sweep(600.0, 100.0, 0.4, 0.6)

func _generate_enemy_spawn() -> AudioStreamWAV:
	# Ascending "materialize" sound
	return _create_wav_sweep(200.0, 500.0, 0.3, 0.4)

func _generate_crit_window_open() -> AudioStreamWAV:
	# Shimmering ascending chime
	return _create_wav_sweep(400.0, 800.0, 0.25, 0.5)

func _generate_weakpoint_destroyed() -> AudioStreamWAV:
	# Satisfying crunch/pop
	return _create_wav_tone(300.0, 0.1, 0.6)

func _generate_all_weakpoints_cleared() -> AudioStreamWAV:
	# Victory fanfare - ascending arpeggio
	return _create_wav_sweep(400.0, 1000.0, 0.5, 0.7)

func _generate_chain_milestone() -> AudioStreamWAV:
	# Bright "ding"
	return _create_wav_tone(800.0, 0.08, 0.5)

func _generate_chain_broken() -> AudioStreamWAV:
	# Sad descending tone
	return _create_wav_sweep(400.0, 200.0, 0.3, 0.4)

# ============================================
# AUDIO GENERATION UTILITIES
# ============================================

func _create_wav_tone(frequency: float, duration: float, volume: float = 0.5) -> AudioStreamWAV:
	var sample_rate = 22050
	var samples = PackedVector2Array()
	var sample_count = int(duration * sample_rate)
	
	for i in range(sample_count):
		var t = float(i) / sample_rate
		# Add envelope (fade in/out)
		var envelope = 1.0
		if i < sample_rate * 0.01:  # 10ms fade in
			envelope = float(i) / (sample_rate * 0.01)
		elif i > sample_count - sample_rate * 0.05:  # 50ms fade out
			envelope = float(sample_count - i) / (sample_rate * 0.05)
		
		var value = sin(t * frequency * TAU) * volume * envelope
		samples.append(Vector2(value, value))
	
	var wav = AudioStreamWAV.new()
	wav.data = _pack_samples(samples)
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	
	return wav

func _create_wav_sweep(start_freq: float, end_freq: float, duration: float, volume: float = 0.5) -> AudioStreamWAV:
	var sample_rate = 22050
	var samples = PackedVector2Array()
	var sample_count = int(duration * sample_rate)
	
	for i in range(sample_count):
		var t = float(i) / sample_rate
		var progress = float(i) / sample_count
		
		# Frequency sweep
		var frequency = lerp(start_freq, end_freq, progress)
		
		# Add envelope
		var envelope = 1.0
		if i < sample_rate * 0.01:
			envelope = float(i) / (sample_rate * 0.01)
		elif i > sample_count - sample_rate * 0.05:
			envelope = float(sample_count - i) / (sample_rate * 0.05)
		
		var value = sin(t * frequency * TAU) * volume * envelope
		samples.append(Vector2(value, value))
	
	var wav = AudioStreamWAV.new()
	wav.data = _pack_samples(samples)
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	
	return wav

func _pack_samples(samples: PackedVector2Array) -> PackedByteArray:
	var bytes = PackedByteArray()
	
	for sample in samples:
		# Convert -1.0 to 1.0 range to 16-bit integer
		var left = int(clamp(sample.x, -1.0, 1.0) * 32767)
		var right = int(clamp(sample.y, -1.0, 1.0) * 32767)
		
		# Pack as 16-bit little-endian
		bytes.append(left & 0xFF)
		bytes.append((left >> 8) & 0xFF)
		bytes.append(right & 0xFF)
		bytes.append((right >> 8) & 0xFF)
	
	return bytes
