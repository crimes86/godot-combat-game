@tool
extends EditorScript

## Fix audio popping by adding 5ms fade-in and fade-out to footstep sounds
## This prevents click/pop artifacts at the start and end of audio playback

func _run() -> void:
	print("🔧 Fixing footstep audio pops...")

	var files = [
		"res://assets/audio/sfx/footsteps/player_step_1.wav",
		"res://assets/audio/sfx/footsteps/player_step_2.wav",
		"res://assets/audio/sfx/footsteps/player_step_3.wav",
		"res://assets/audio/sfx/footsteps/skeleton_step_1.wav",
		"res://assets/audio/sfx/footsteps/skeleton_step_2.wav",
		"res://assets/audio/sfx/footsteps/skeleton_step_3.wav",
	]

	for file_path in files:
		if not ResourceLoader.exists(file_path):
			print("  ⚠️ File not found: %s" % file_path)
			continue

		var audio_stream: AudioStreamWAV = load(file_path)
		if not audio_stream:
			print("  ❌ Failed to load: %s" % file_path)
			continue

		print("  Processing: %s" % file_path)

		# Get the raw audio data
		var data = audio_stream.data
		var format = audio_stream.format
		var mix_rate = audio_stream.mix_rate
		var stereo = audio_stream.stereo

		# Calculate fade length (5ms)
		var fade_samples = int(mix_rate * 0.005)  # 5ms

		# Apply fades
		var modified_data = apply_fades(data, fade_samples, stereo)

		# Create new audio stream with faded data
		var new_stream = AudioStreamWAV.new()
		new_stream.data = modified_data
		new_stream.format = format
		new_stream.mix_rate = mix_rate
		new_stream.stereo = stereo
		new_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED

		# Save the fixed audio
		var save_path = file_path.replace(".wav", "_fixed.wav")
		var err = ResourceSaver.save(new_stream, save_path)

		if err == OK:
			print("    ✅ Saved fixed audio: %s" % save_path)
		else:
			print("    ❌ Failed to save: %s (error %d)" % [save_path, err])

	print("✅ Done! Replace the original files with the _fixed versions if they sound better.")

func apply_fades(data: PackedByteArray, fade_samples: int, stereo: bool) -> PackedByteArray:
	"""Apply linear fade-in and fade-out to audio data"""
	var bytes_per_sample = 2  # 16-bit audio
	var channels = 2 if stereo else 1
	var bytes_per_frame = bytes_per_sample * channels

	var total_frames = data.size() / bytes_per_frame
	var modified_data = data.duplicate()

	# Apply fade-in
	for i in range(fade_samples):
		if i >= total_frames:
			break

		var fade_factor = float(i) / float(fade_samples)
		var byte_offset = i * bytes_per_frame

		# Process left channel (or mono)
		var sample_left = get_sample_16bit(modified_data, byte_offset)
		sample_left = int(sample_left * fade_factor)
		set_sample_16bit(modified_data, byte_offset, sample_left)

		# Process right channel if stereo
		if stereo:
			var sample_right = get_sample_16bit(modified_data, byte_offset + 2)
			sample_right = int(sample_right * fade_factor)
			set_sample_16bit(modified_data, byte_offset + 2, sample_right)

	# Apply fade-out
	var fade_out_start = total_frames - fade_samples
	for i in range(fade_samples):
		var frame_idx = fade_out_start + i
		if frame_idx >= total_frames:
			break

		var fade_factor = 1.0 - (float(i) / float(fade_samples))
		var byte_offset = frame_idx * bytes_per_frame

		# Process left channel (or mono)
		var sample_left = get_sample_16bit(modified_data, byte_offset)
		sample_left = int(sample_left * fade_factor)
		set_sample_16bit(modified_data, byte_offset, sample_left)

		# Process right channel if stereo
		if stereo:
			var sample_right = get_sample_16bit(modified_data, byte_offset + 2)
			sample_right = int(sample_right * fade_factor)
			set_sample_16bit(modified_data, byte_offset + 2, sample_right)

	return modified_data

func get_sample_16bit(data: PackedByteArray, offset: int) -> int:
	"""Read 16-bit signed sample from byte array"""
	var low = data[offset]
	var high = data[offset + 1]
	var value = low | (high << 8)

	# Convert to signed
	if value >= 32768:
		value -= 65536

	return value

func set_sample_16bit(data: PackedByteArray, offset: int, value: int) -> void:
	"""Write 16-bit signed sample to byte array"""
	# Convert to unsigned
	if value < 0:
		value += 65536

	data[offset] = value & 0xFF
	data[offset + 1] = (value >> 8) & 0xFF
