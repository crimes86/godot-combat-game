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

# Real sound file variations (for randomization)
var weakpoint_sounds: Array[AudioStream] = []
var weakpoint_destroyed_sound: AudioStream = null
var critical_hit_sound: AudioStream = null
var normal_hit_sounds: Array[AudioStream] = []  # Generic fallback
var skeleton_hurt_sound: AudioStream = null

# Weapon-specific hit sounds (organized by weapon type)
var weapon_hit_sounds: Dictionary = {
	"sword": [],
	"mace": [],
	"spear": [],
	"dagger": []
}

func _ready() -> void:
	# Load real sound files first
	print("🔊 Loading real sound files...")
	_load_real_sounds()

	# Pre-generate all placeholder sounds
	print("🔊 Generating placeholder sounds...")
	_generate_all_sounds()
	print("✅ Sound system ready!")

func _load_real_sounds() -> void:
	"""Load real sound files for combat effects"""
	# Load weakpoint hit sounds (devastating bone crunch sounds)
	var weakpoint_1 = load("res://assets/sounds/combat/hits/weakpoint_hit_1.wav")
	var weakpoint_2 = load("res://assets/sounds/combat/hits/weakpoint_hit_2.wav")
	var weakpoint_3 = load("res://assets/sounds/combat/hits/weakpoint_hit_3.wav")

	if weakpoint_1:
		weakpoint_sounds.append(weakpoint_1)
		print("  ✅ Loaded weakpoint_hit_1.wav")
	else:
		push_warning("  ⚠️ Failed to load weakpoint_hit_1.wav")

	if weakpoint_2:
		weakpoint_sounds.append(weakpoint_2)
		print("  ✅ Loaded weakpoint_hit_2.wav")
	else:
		push_warning("  ⚠️ Failed to load weakpoint_hit_2.wav")

	if weakpoint_3:
		weakpoint_sounds.append(weakpoint_3)
		print("  ✅ Loaded weakpoint_hit_3.wav")
	else:
		push_warning("  ⚠️ Failed to load weakpoint_hit_3.wav")

	print("  📊 Loaded %d weakpoint sound variations" % weakpoint_sounds.size())

	# Load weakpoint destruction sound
	weakpoint_destroyed_sound = load("res://assets/sounds/combat/hits/weakpoint_destroyed.wav")
	if weakpoint_destroyed_sound:
		print("  ✅ Loaded weakpoint_destroyed.wav")
	else:
		push_warning("  ⚠️ Failed to load weakpoint_destroyed.wav")

	# Load critical hit sound (for non-weakpoint crits)
	critical_hit_sound = load("res://assets/sounds/combat/hits/critical_hit.wav")
	if critical_hit_sound:
		print("  ✅ Loaded critical_hit.wav")
	else:
		push_warning("  ⚠️ Failed to load critical_hit.wav")

	# Load normal hit sounds
	var normal_hit_1 = load("res://assets/sounds/combat/hits/normal_hit_1.wav")
	var normal_hit_2 = load("res://assets/sounds/combat/hits/normal_hit_2.wav")

	if normal_hit_1:
		normal_hit_sounds.append(normal_hit_1)
		print("  ✅ Loaded normal_hit_1.wav")
	else:
		push_warning("  ⚠️ Failed to load normal_hit_1.wav")

	if normal_hit_2:
		normal_hit_sounds.append(normal_hit_2)
		print("  ✅ Loaded normal_hit_2.wav")
	else:
		push_warning("  ⚠️ Failed to load normal_hit_2.wav")

	print("  📊 Loaded %d normal hit sound variations" % normal_hit_sounds.size())

	# Load skeleton hurt sound
	skeleton_hurt_sound = load("res://assets/sounds/combat/reactions/skeleton_hurt.wav")
	if skeleton_hurt_sound:
		print("  ✅ Loaded skeleton_hurt.wav")
	else:
		push_warning("  ⚠️ Failed to load skeleton_hurt.wav")

	# Load weapon-specific hit sounds
	print("  🗡️ Loading weapon hit sounds...")
	_load_weapon_sounds("sword", 4)
	# More weapon types can be added here later:
	# _load_weapon_sounds("mace", 4)
	# _load_weapon_sounds("spear", 4)
	print("  📊 Loaded weapon sounds: sword=%d" % weapon_hit_sounds["sword"].size())

func _load_weapon_sounds(weapon_type: String, count: int) -> void:
	"""Load weapon-specific hit sounds"""
	for i in range(1, count + 1):
		var sound_path = "res://assets/sounds/combat/weapons/%s/%s_hit_%d.wav" % [weapon_type, weapon_type, i]
		var sound = load(sound_path)
		if sound:
			weapon_hit_sounds[weapon_type].append(sound)
			print("    ✅ Loaded %s_hit_%d.wav" % [weapon_type, i])
		else:
			push_warning("    ⚠️ Failed to load %s" % sound_path)

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

## Play a random weakpoint hit sound with pitch variation (for satisfying spam-clicking)
func play_weakpoint_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if weakpoint_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.HIT_WEAKPOINT, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = weakpoint_sounds[randi() % weakpoint_sounds.size()]

	# Create player with subtle pitch randomization (±3% for variety)
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation to avoid distortion
	player.max_polyphony = 8  # Allow multiple instances for spam clicking
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play critical hit sound (for non-weakpoint critical hits)
func play_critical_hit_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if not critical_hit_sound:
		# Fallback to placeholder sound if no real sound loaded
		play_sound(SoundType.HIT_CRIT, global_pos, volume_db)
		return

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = critical_hit_sound
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.max_polyphony = 4  # Allow some overlap but less than weakpoints
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play normal hit sound (for regular non-crit hits)
func play_normal_hit_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0, weapon_type: String = "") -> void:
	var sounds_to_use = []  # Untyped to avoid type mismatch with Dictionary values

	# Try weapon-specific sounds first
	if weapon_type != "" and weapon_hit_sounds.has(weapon_type) and not weapon_hit_sounds[weapon_type].is_empty():
		sounds_to_use = weapon_hit_sounds[weapon_type]
	# Fallback to generic normal hit sounds
	elif not normal_hit_sounds.is_empty():
		sounds_to_use = normal_hit_sounds
	# Last resort: placeholder
	else:
		play_sound(SoundType.HIT_NORMAL, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream: AudioStream = sounds_to_use[randi() % sounds_to_use.size()]

	# Create player with pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.max_polyphony = 4  # Allow some overlap
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play skeleton hurt sound (when skeleton takes damage)
func play_skeleton_hurt_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if not skeleton_hurt_sound:
		# No fallback - just don't play if not loaded
		return

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = skeleton_hurt_sound
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.max_polyphony = 3  # Allow some overlap but not too much
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play weakpoint destruction sound (explosive glass/bone shatter finale)
func play_weakpoint_destroyed_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if not weakpoint_destroyed_sound:
		# Fallback to placeholder sound if no real sound loaded
		play_sound(SoundType.WEAKPOINT_DESTROYED, global_pos, volume_db)
		return

	# Create player - no pitch randomization for this dramatic finale
	var player = AudioStreamPlayer2D.new()
	player.stream = weakpoint_destroyed_sound
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = 1.0  # Keep original pitch for maximum impact
	player.max_polyphony = 2  # Allow slight overlap in case of rapid weakpoint destruction
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

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
