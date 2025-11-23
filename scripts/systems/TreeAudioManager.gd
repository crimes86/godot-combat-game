extends Node

## Tree Audio Manager - Singleton for tree chopping sounds
## Loads audio files ONCE and shares them with all trees
## Prevents 300+ trees from each loading the same 6 files

# Shared audio streams
var chop_sounds: Array[AudioStream] = []
var fall_sounds: Array[AudioStream] = []
var audio_loaded: bool = false

func _ready() -> void:
	load_audio_files()

func load_audio_files() -> void:
	"""Load tree audio files once for all trees to share"""
	if audio_loaded:
		return  # Already loaded

	# Load chop sounds
	var chop_paths = [
		"res://assets/sounds/tree/chop_1.wav",
		"res://assets/sounds/tree/chop_2.wav",
		"res://assets/sounds/tree/chop_3.wav"
	]

	for path in chop_paths:
		var stream = load(path)
		if stream:
			chop_sounds.append(stream)

	# Load fall sounds
	var fall_paths = [
		"res://assets/sounds/tree/tree_fall_1.wav",
		"res://assets/sounds/tree/tree_fall_2.wav",
		"res://assets/sounds/tree/tree_fall_3.wav"
	]

	for path in fall_paths:
		var stream = load(path)
		if stream:
			fall_sounds.append(stream)

	audio_loaded = true
	print("🔊 TreeAudioManager: Loaded %d chop sounds and %d fall sounds (shared by all trees)" % [chop_sounds.size(), fall_sounds.size()])

func get_random_chop_sound() -> AudioStream:
	"""Get a random chopping sound"""
	if chop_sounds.is_empty():
		return null
	return chop_sounds[randi() % chop_sounds.size()]

func get_random_fall_sound() -> AudioStream:
	"""Get a random tree falling sound"""
	if fall_sounds.is_empty():
		return null
	return fall_sounds[randi() % fall_sounds.size()]
