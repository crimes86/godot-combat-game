extends Node

## Sound Manager - Generates placeholder sounds and manages audio playback
## Replace placeholder sounds with real audio files later by updating the respective AudioStream resources

# Sound Types
enum SoundType {
	# Player sounds
	SWING,
	MISS,
	FOOTSTEP_PLAYER,  # Player footsteps (cloth/leather)

	# Enemy sounds
	HIT_NORMAL,
	HIT_CRIT,
	HIT_WEAKPOINT,
	ENEMY_DEATH,
	ENEMY_SPAWN,
	SKELETON_ATTACK,  # Skeleton's menacing cackle when attacking
	SKELETON_AGGRO,   # Skeleton's menacing cackle when spotting player
	SKELETON_DEATH,   # Skeleton bones collapsing (random between 2 variations)
	FOOTSTEP_SKELETON,  # Skeleton footsteps (bone clacking)

	# System sounds
	CRIT_WINDOW_OPEN,
	WEAKPOINT_DESTROYED,
	ALL_WEAKPOINTS_CLEARED,
	CHAIN_MILESTONE,
	CHAIN_BROKEN,

	# UI/Loot sounds
	GOLD_LOOT,  # Gold coin jingling (looting corpses, shop transactions)
	ITEM_PICKUP,  # Satisfying item pickup sound (inventory notification)
	CHEST_OPEN,  # Treasure chest opening sound
	INVENTORY_MOVE,  # Moving items around inventory slots
	EQUIP_ITEM,  # Equipping/unequipping gear

	# Environment sounds
	FIRE_FUEL_ADD  # Fire magic sound when adding fuel to campfire
}

# Cache for generated sounds
var sound_cache: Dictionary = {}

# Active skeleton sound player (only one skeleton sound at a time - attack OR aggro)
var active_skeleton_sound_player: AudioStreamPlayer2D = null

# Real sound file variations (for randomization)
var weakpoint_sounds: Array[AudioStream] = []
var weakpoint_destroyed_sound: AudioStream = null
var critical_hit_sound: AudioStream = null
var normal_hit_sounds: Array[AudioStream] = []  # Generic fallback
var skeleton_hurt_sound: AudioStream = null
var skeleton_attack_sound: AudioStream = null  # Skeleton's menacing cackle
var skeleton_death_sounds: Array[AudioStream] = []  # Skeleton bones collapsing (2 variations)
var gold_loot_sound: AudioStream = null  # Gold coin jingling
var item_pickup_sound: AudioStream = null  # Satisfying item pickup sound
var chest_open_sound: AudioStream = null  # Treasure chest opening sound
var inventory_move_sound: AudioStream = null  # Moving items in inventory
var equip_item_sound: AudioStream = null  # Equipping/unequipping gear
var crit_window_open_sound: AudioStream = null  # Crystalline chime when crit window opens
var fire_fuel_add_sound: AudioStream = null  # Fire magic sound when adding fuel

# Weapon swing sounds (whoosh sounds when swinging weapons)
var sword_swing_sounds: Array[AudioStream] = []  # Sword whoosh (2 variations)
var unarmed_swing_sounds: Array[AudioStream] = []  # Unarmed/fist whoosh

# Player sounds
var player_hurt_sounds: Array[AudioStream] = []  # Player hurt/death grunts (2 variations)
var player_footstep_sounds: Array[AudioStream] = []  # Player footsteps (cloth/leather)

# Enemy footstep sounds
var skeleton_footstep_sounds: Array[AudioStream] = []  # Skeleton bone clacking footsteps

# Weapon-specific hit sounds (organized by weapon type)
var weapon_hit_sounds: Dictionary = {
	"sword": [],
	"mace": [],
	"spear": [],
	"dagger": []
}

# Background music playlist
var music_tracks: Array[AudioStream] = []
var current_track_index: int = 0
var music_player: AudioStreamPlayer = null
var music_volume_db: float = -15.0  # Store target volume for playlist
const MUSIC_FADE_DURATION: float = 2.0  # Seconds to fade in/out

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

	# Load skeleton attack sound (menacing cackle)
	skeleton_attack_sound = load("res://assets/sounds/combat/reactions/skeleton_attack.wav")
	if skeleton_attack_sound:
		print("  ✅ Loaded skeleton_attack.wav")
	else:
		push_warning("  ⚠️ Failed to load skeleton_attack.wav")

	# Load skeleton death sounds (bones collapsing - 2 variations)
	var skeleton_death_1 = load("res://assets/sounds/combat/reactions/skeleton_death_1.wav")
	var skeleton_death_2 = load("res://assets/sounds/combat/reactions/skeleton_death_2.wav")

	if skeleton_death_1:
		skeleton_death_sounds.append(skeleton_death_1)
		print("  ✅ Loaded skeleton_death_1.wav")
	else:
		push_warning("  ⚠️ Failed to load skeleton_death_1.wav")

	if skeleton_death_2:
		skeleton_death_sounds.append(skeleton_death_2)
		print("  ✅ Loaded skeleton_death_2.wav")
	else:
		push_warning("  ⚠️ Failed to load skeleton_death_2.wav")

	print("  📊 Loaded %d skeleton death sound variations" % skeleton_death_sounds.size())

	# Load gold loot sound (coin jingling)
	gold_loot_sound = load("res://assets/sounds/ui/gold_loot.wav")
	if gold_loot_sound:
		print("  ✅ Loaded gold_loot.wav")
	else:
		push_warning("  ⚠️ Failed to load gold_loot.wav")

	# Load item pickup sound (satisfying pickup)
	item_pickup_sound = load("res://assets/sounds/ui/item_pickup.wav")
	if item_pickup_sound:
		print("  ✅ Loaded item_pickup.wav")
	else:
		push_warning("  ⚠️ Failed to load item_pickup.wav")

	# Load chest open sound
	chest_open_sound = load("res://assets/sounds/ui/chest_open.wav")
	if chest_open_sound:
		print("  ✅ Loaded chest_open.wav")
	else:
		push_warning("  ⚠️ Failed to load chest_open.wav")

	# Load inventory move sound (dragging items between slots)
	inventory_move_sound = load("res://assets/audio/sfx/inventory_move.wav")
	if inventory_move_sound:
		print("  ✅ Loaded inventory_move.wav")
	else:
		push_warning("  ⚠️ Failed to load inventory_move.wav")

	# Load equip item sound (equipping/unequipping gear)
	equip_item_sound = load("res://assets/audio/sfx/equip_item.wav")
	if equip_item_sound:
		print("  ✅ Loaded equip_item.wav")
	else:
		push_warning("  ⚠️ Failed to load equip_item.wav")

	# Load crit window open sound (crystalline chime)
	crit_window_open_sound = load("res://assets/sounds/combat/crit_window_open.wav")
	if crit_window_open_sound:
		print("  ✅ Loaded crit_window_open.wav")
	else:
		push_warning("  ⚠️ Failed to load crit_window_open.wav")

	# Load fire fuel add sound (fire magic)
	fire_fuel_add_sound = load("res://assets/sounds/ambient/fire_fuel_add.mp3")
	if fire_fuel_add_sound:
		print("  ✅ Loaded fire_fuel_add.mp3")
	else:
		push_warning("  ⚠️ Failed to load fire_fuel_add.mp3")

	# Load sword swing sounds (whoosh variations)
	var sword_swing_1 = load("res://assets/sounds/combat/weapon_swings/sword_swing_1.wav")
	var sword_swing_2 = load("res://assets/sounds/combat/weapon_swings/sword_swing_2.wav")

	if sword_swing_1:
		sword_swing_sounds.append(sword_swing_1)
		print("  ✅ Loaded sword_swing_1.wav")
	else:
		push_warning("  ⚠️ Failed to load sword_swing_1.wav")

	if sword_swing_2:
		sword_swing_sounds.append(sword_swing_2)
		print("  ✅ Loaded sword_swing_2.wav")
	else:
		push_warning("  ⚠️ Failed to load sword_swing_2.wav")

	print("  📊 Loaded %d sword swing sound variations" % sword_swing_sounds.size())

	# Load unarmed swing sound (fist whoosh)
	var unarmed_swing = load("res://assets/sounds/combat/unarmed_slash.mp3")
	if unarmed_swing:
		unarmed_swing_sounds.append(unarmed_swing)
		print("  ✅ Loaded unarmed_slash.mp3")
	else:
		push_warning("  ⚠️ Failed to load unarmed_slash.mp3")

	print("  📊 Loaded %d unarmed swing sound variations" % unarmed_swing_sounds.size())

	# Load player hurt sounds (grunt/pain sounds)
	var player_hurt_1 = load("res://assets/sounds/player/player_hurt_1.wav")
	var player_hurt_2 = load("res://assets/sounds/player/player_hurt_2.wav")

	if player_hurt_1:
		player_hurt_sounds.append(player_hurt_1)
		print("  ✅ Loaded player_hurt_1.wav")
	else:
		push_warning("  ⚠️ Failed to load player_hurt_1.wav")

	if player_hurt_2:
		player_hurt_sounds.append(player_hurt_2)
		print("  ✅ Loaded player_hurt_2.wav")
	else:
		push_warning("  ⚠️ Failed to load player_hurt_2.wav")

	print("  📊 Loaded %d player hurt sound variations" % player_hurt_sounds.size())

	# Load player footstep sounds
	var player_step_1 = load("res://assets/sounds/footsteps/player_step_1.wav")
	var player_step_2 = load("res://assets/sounds/footsteps/player_step_2.wav")
	var player_step_3 = load("res://assets/sounds/footsteps/player_step_3.wav")

	if player_step_1:
		player_footstep_sounds.append(player_step_1)
		print("  ✅ Loaded player_step_1.wav")
	if player_step_2:
		player_footstep_sounds.append(player_step_2)
		print("  ✅ Loaded player_step_2.wav")
	if player_step_3:
		player_footstep_sounds.append(player_step_3)
		print("  ✅ Loaded player_step_3.wav")

	print("  📊 Loaded %d player footstep sound variations" % player_footstep_sounds.size())

	# Load skeleton footstep sounds (same files, will sound different with pitch variation)
	var skeleton_step_1 = load("res://assets/sounds/footsteps/skeleton_step_1.wav")
	var skeleton_step_2 = load("res://assets/sounds/footsteps/skeleton_step_2.wav")
	var skeleton_step_3 = load("res://assets/sounds/footsteps/skeleton_step_3.wav")

	if skeleton_step_1:
		skeleton_footstep_sounds.append(skeleton_step_1)
		print("  ✅ Loaded skeleton_step_1.wav")
	if skeleton_step_2:
		skeleton_footstep_sounds.append(skeleton_step_2)
		print("  ✅ Loaded skeleton_step_2.wav")
	if skeleton_step_3:
		skeleton_footstep_sounds.append(skeleton_step_3)
		print("  ✅ Loaded skeleton_step_3.wav")

	print("  📊 Loaded %d skeleton footstep sound variations" % skeleton_footstep_sounds.size())

	# Load weapon-specific hit sounds
	print("  🗡️ Loading weapon hit sounds...")
	_load_weapon_sounds("sword", 4)
	# More weapon types can be added here later:
	# _load_weapon_sounds("mace", 4)
	# _load_weapon_sounds("spear", 4)
	print("  📊 Loaded weapon sounds: sword=%d" % weapon_hit_sounds["sword"].size())

	# Load background music playlist
	print("  🎵 Loading background music playlist...")
	var track1 = load("res://assets/audio/music/game_loop.mp3")
	if track1:
		music_tracks.append(track1)
		print("  ✅ Loaded game_loop.mp3 (Track 1: The Raven's Shadow)")

	var track2 = load("res://assets/audio/music/game_loop_2.mp3")
	if track2:
		music_tracks.append(track2)
		print("  ✅ Loaded game_loop_2.mp3 (Track 2: The Wasteland's Whisper)")

	print("  📊 Loaded %d music tracks" % music_tracks.size())

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

	# Skeleton sounds (use real sound if loaded, otherwise generate placeholder)
	sound_cache[SoundType.SKELETON_ATTACK] = skeleton_attack_sound if skeleton_attack_sound else _generate_skeleton_sound()
	sound_cache[SoundType.SKELETON_AGGRO] = skeleton_attack_sound if skeleton_attack_sound else _generate_skeleton_sound()
	sound_cache[SoundType.SKELETON_DEATH] = skeleton_death_sounds[0] if not skeleton_death_sounds.is_empty() else _generate_enemy_death()

	# System sounds (use real sound if loaded, otherwise generate placeholder)
	sound_cache[SoundType.CRIT_WINDOW_OPEN] = crit_window_open_sound if crit_window_open_sound else _generate_crit_window_open()
	sound_cache[SoundType.WEAKPOINT_DESTROYED] = _generate_weakpoint_destroyed()
	sound_cache[SoundType.ALL_WEAKPOINTS_CLEARED] = _generate_all_weakpoints_cleared()
	sound_cache[SoundType.CHAIN_MILESTONE] = _generate_chain_milestone()
	sound_cache[SoundType.CHAIN_BROKEN] = _generate_chain_broken()

	# UI/Loot sounds (use real sound if loaded, otherwise generate placeholder)
	sound_cache[SoundType.GOLD_LOOT] = gold_loot_sound if gold_loot_sound else _generate_gold_loot()
	sound_cache[SoundType.ITEM_PICKUP] = item_pickup_sound if item_pickup_sound else _generate_item_pickup()
	sound_cache[SoundType.CHEST_OPEN] = chest_open_sound if chest_open_sound else _generate_chest_open()
	sound_cache[SoundType.INVENTORY_MOVE] = inventory_move_sound if inventory_move_sound else _generate_inventory_move()
	sound_cache[SoundType.EQUIP_ITEM] = equip_item_sound if equip_item_sound else _generate_equip_item()

	# Environment sounds
	sound_cache[SoundType.FIRE_FUEL_ADD] = fire_fuel_add_sound if fire_fuel_add_sound else _generate_fire_fuel_add()

	# Footstep sounds (use real sounds if loaded, otherwise generate placeholders)
	sound_cache[SoundType.FOOTSTEP_PLAYER] = player_footstep_sounds[0] if not player_footstep_sounds.is_empty() else _generate_footstep_soft()
	sound_cache[SoundType.FOOTSTEP_SKELETON] = skeleton_footstep_sounds[0] if not skeleton_footstep_sounds.is_empty() else _generate_footstep_hard()

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
	# Fallback to sword hit sounds if we have them (better than generic)
	elif not weapon_hit_sounds["sword"].is_empty():
		sounds_to_use = weapon_hit_sounds["sword"]
	# Fallback to generic normal hit sounds
	elif not normal_hit_sounds.is_empty():
		sounds_to_use = normal_hit_sounds
	# Last resort: don't play anything (no placeholder boop)
	else:
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

## Play skeleton sound (attack or aggro) - only one at a time, no overlap
func play_skeleton_attack_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	_play_skeleton_sound(global_pos, volume_db)

## Play skeleton aggro sound - uses same single-player system as attack
func play_skeleton_aggro_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	_play_skeleton_sound(global_pos, volume_db)

func _play_skeleton_sound(global_pos: Vector2, volume_db: float) -> void:
	# If a skeleton sound is already playing, don't play another
	if is_instance_valid(active_skeleton_sound_player) and active_skeleton_sound_player.playing:
		return

	if not skeleton_attack_sound:
		return

	# Create or reuse the sound player
	if not is_instance_valid(active_skeleton_sound_player):
		active_skeleton_sound_player = AudioStreamPlayer2D.new()
		active_skeleton_sound_player.stream = skeleton_attack_sound
		get_tree().root.add_child(active_skeleton_sound_player)

	active_skeleton_sound_player.volume_db = volume_db
	active_skeleton_sound_player.global_position = global_pos
	active_skeleton_sound_player.pitch_scale = randf_range(0.95, 1.05)
	active_skeleton_sound_player.play()

## Play skeleton death sound (random between 2 bone collapse variations)
func play_skeleton_death_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if skeleton_death_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.SKELETON_DEATH, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = skeleton_death_sounds[randi() % skeleton_death_sounds.size()]

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play sword swing sound (random whoosh variation)
func play_sword_swing_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if sword_swing_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.SWING, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = sword_swing_sounds[randi() % sword_swing_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play unarmed swing sound (whoosh when punching/kicking)
func play_unarmed_swing_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if unarmed_swing_sounds.is_empty():
		# Fallback to sword swing if no unarmed sounds loaded
		play_sword_swing_sound(global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = unarmed_swing_sounds[randi() % unarmed_swing_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play player hurt sound (random grunt/pain variation)
func play_player_hurt_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if player_hurt_sounds.is_empty():
		# No real sounds loaded, skip (no placeholder for player hurt)
		return

	# Pick random sound variation
	var sound_stream = player_hurt_sounds[randi() % player_hurt_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play player footstep sound with distance culling
func play_player_footstep(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -18.0) -> void:
	if player_footstep_sounds.is_empty():
		# Fallback to placeholder
		play_sound(SoundType.FOOTSTEP_PLAYER, global_pos, volume_db)
		return

	# Pick random variation
	var sound_stream = player_footstep_sounds[randi() % player_footstep_sounds.size()]

	# Create player with slight pitch variation
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.max_polyphony = 2  # Allow slight overlap
	player.max_distance = 1500.0  # Distance attenuation
	player.attenuation = 1.5  # Smooth falloff
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)

	# Add tiny delay before play to avoid click/pop at start
	await get_tree().create_timer(0.001).timeout
	if is_instance_valid(player):
		player.play()

## Play skeleton footstep sound with distance culling
func play_skeleton_footstep(global_pos: Vector2, camera_pos: Vector2, volume_db: float = -20.0) -> void:
	# Distance culling: only play if within 1000px of camera
	var distance = global_pos.distance_to(camera_pos)
	if distance > 1000.0:
		return

	if skeleton_footstep_sounds.is_empty():
		# Fallback to placeholder
		play_sound(SoundType.FOOTSTEP_SKELETON, global_pos, volume_db)
		return

	# Pick random variation
	var sound_stream = skeleton_footstep_sounds[randi() % skeleton_footstep_sounds.size()]

	# Create player with pitch variation
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.93, 1.07)  # More variation for bone clacking
	player.max_polyphony = 4  # Allow more overlap for multiple skeletons
	player.max_distance = 1500.0  # Distance attenuation
	player.attenuation = 1.5  # Smooth falloff
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)

	# Add tiny delay before play to avoid click/pop at start
	await get_tree().create_timer(0.001).timeout
	if is_instance_valid(player):
		player.play()

## Play fire fuel add sound (spammable magic whoosh when adding fuel to campfire)
## enhanced = true for slightly louder/higher pitch when holding F
func play_fire_fuel_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -12.0, enhanced: bool = false) -> void:
	if not fire_fuel_add_sound:
		# Fallback to placeholder
		play_sound(SoundType.FIRE_FUEL_ADD, global_pos, volume_db)
		return

	# Create player with pitch randomization for spammable variety
	var player = AudioStreamPlayer2D.new()
	player.stream = fire_fuel_add_sound
	player.global_position = global_pos
	player.max_polyphony = 8  # Allow many overlapping sounds for spam clicking

	if enhanced:
		# Enhanced version: slightly louder and higher pitch
		player.volume_db = volume_db + 3.0
		player.pitch_scale = randf_range(1.05, 1.15)
	else:
		# Normal version: subtle pitch variation
		player.volume_db = volume_db
		player.pitch_scale = randf_range(0.95, 1.05)

	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play inventory move sound (dragging items between slots)
func play_inventory_move_sound(volume_db: float = -10.0) -> void:
	if not inventory_move_sound:
		# Fallback to placeholder
		play_sound_2d(SoundType.INVENTORY_MOVE, volume_db)
		return

	var player = AudioStreamPlayer.new()
	player.stream = inventory_move_sound
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play equip item sound (equipping/unequipping gear)
func play_equip_sound(volume_db: float = -10.0) -> void:
	if not equip_item_sound:
		# Fallback to placeholder
		play_sound_2d(SoundType.EQUIP_ITEM, volume_db)
		return

	var player = AudioStreamPlayer.new()
	player.stream = equip_item_sound
	player.volume_db = volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
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

func _generate_skeleton_sound() -> AudioStreamWAV:
	# Rattling, dry cackle placeholder (high pitched rattle)
	return _create_wav_sweep(800.0, 1200.0, 0.3, 0.3)

func _generate_gold_loot() -> AudioStreamWAV:
	# Bright coin jingling placeholder (high metallic chime)
	return _create_wav_tone(1200.0, 0.15, 0.4)

func _generate_item_pickup() -> AudioStreamWAV:
	# Satisfying pickup placeholder (soft pouch thud with shimmer)
	return _create_wav_sweep(400.0, 600.0, 0.2, 0.3)

func _generate_chest_open() -> AudioStreamWAV:
	# Chest opening placeholder (creaky wood sound)
	return _create_wav_sweep(150.0, 300.0, 0.5, 0.4)

func _generate_inventory_move() -> AudioStreamWAV:
	# Inventory move placeholder (soft cloth/leather rustle)
	return _create_wav_tone(250.0, 0.1, 0.25)

func _generate_equip_item() -> AudioStreamWAV:
	# Equip item placeholder (leather strap with metal click)
	return _create_wav_sweep(200.0, 400.0, 0.2, 0.35)

func _generate_footstep_soft() -> AudioStreamWAV:
	# Soft cloth/leather footstep (low thud)
	return _create_wav_tone(120.0, 0.08, 0.15)

func _generate_footstep_hard() -> AudioStreamWAV:
	# Hard bone clacking footstep (higher pitch click)
	return _create_wav_tone(300.0, 0.06, 0.2)

func _generate_fire_fuel_add() -> AudioStreamWAV:
	# Fire whoosh placeholder (ascending sweep)
	return _create_wav_sweep(200.0, 600.0, 0.3, 0.4)

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

# ============================================
# BACKGROUND MUSIC
# ============================================

## Start playing the game music playlist
func play_game_music(volume_db: float = -15.0) -> void:
	if music_tracks.is_empty():
		push_warning("No music tracks loaded!")
		return

	music_volume_db = volume_db
	current_track_index = 0

	# Create music player if needed
	if not music_player:
		music_player = AudioStreamPlayer.new()
		add_child(music_player)
		# Connect finished signal to play next track
		music_player.finished.connect(_on_music_track_finished)

	# Don't restart if already playing
	if music_player.playing:
		return

	_play_current_track()

func _play_current_track() -> void:
	"""Play the current track in the playlist"""
	if music_tracks.is_empty() or not music_player:
		return

	var track = music_tracks[current_track_index]
	music_player.stream = track
	music_player.volume_db = music_volume_db

	# Don't loop individual tracks - let playlist handle advancement
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = false
	elif track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = false
	elif track is AudioStreamWAV:
		(track as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED

	print("🎵 Now playing track %d/%d (%.0fs)" % [current_track_index + 1, music_tracks.size(), track.get_length()])
	music_player.play()

func _on_music_track_finished() -> void:
	"""Called when a track finishes - advance to next track"""
	current_track_index = (current_track_index + 1) % music_tracks.size()
	_play_current_track()

## Stop the game music with fade-out
func stop_game_music() -> void:
	if not music_player or not music_player.playing:
		return

	var tween = create_tween()
	tween.tween_property(music_player, "volume_db", -40.0, MUSIC_FADE_DURATION)
	tween.tween_callback(music_player.stop)

## Check if game music is currently playing
func is_game_music_playing() -> bool:
	return music_player and music_player.playing

## Set game music volume (for settings)
func set_music_volume(volume_db: float) -> void:
	music_volume_db = volume_db
	if music_player:
		music_player.volume_db = volume_db

## Skip to next track in playlist
func skip_music_track() -> void:
	if music_tracks.size() <= 1:
		return
	current_track_index = (current_track_index + 1) % music_tracks.size()
	_play_current_track()
