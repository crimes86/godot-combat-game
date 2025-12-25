extends Node

## Sound Manager - Generates placeholder sounds and manages audio playback
## Replace placeholder sounds with real audio files later by updating the respective AudioStream resources
##
## REFACTOR NOTE (Dec 2024): Audio paths reorganized
## - All sounds moved from assets/sounds/ to assets/audio/sfx/
## - Music remains at assets/audio/music/
## - If sounds fail to load, verify files exist at new paths in assets/audio/sfx/

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
	CORPSE_LOOT,  # Rummaging through corpse when opening loot UI
	BLACKSMITH_OPEN,  # Opening blacksmith/vendor UI
	QUEST_ACCEPT,  # Accepting a new quest
	QUEST_TURN_IN,  # Turning in completed quest
	INVENTORY_MOVE,  # Moving items around inventory slots
	EQUIP_ITEM,  # Equipping/unequipping gear
	BUTTON_CLICK,  # UI button click sound

	# Environment sounds
	FIRE_FUEL_ADD,  # Fire magic sound when adding fuel to campfire

	# Movement sounds
	DODGE,  # Dodge/dash whoosh sound

	# Combat defense sounds
	SHIELD_BLOCK  # Shield blocking an attack
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
var skeleton_hurt_sounds: Array[AudioStream] = []  # Skeleton hurt sounds (multiple variations)
var skeleton_attack_sound: AudioStream = null  # Skeleton's menacing cackle
var skeleton_aggro_sounds: Array[AudioStream] = []  # Skeleton aggro sounds (2 variations)
var skeleton_death_sounds: Array[AudioStream] = []  # Skeleton bones collapsing (2 variations)
var gold_loot_sound: AudioStream = null  # Gold coin jingling
var item_pickup_sound: AudioStream = null  # Satisfying item pickup sound
var chest_open_sound: AudioStream = null  # Treasure chest opening sound
var corpse_loot_sound: AudioStream = null  # Rummaging through corpse
var blacksmith_open_sound: AudioStream = null  # Blacksmith/vendor UI open
var quest_accept_sound: AudioStream = null  # Quest accept sound
var quest_turn_in_sound: AudioStream = null  # Quest turn in sound
var inventory_move_sound: AudioStream = null  # Moving items in inventory
var equip_item_sound: AudioStream = null  # Equipping/unequipping gear
var button_click_sound: AudioStream = null  # UI button click sound
var button_hover_sound: AudioStream = null  # UI button hover sound
var inventory_open_sound: AudioStream = null  # Inventory bag open/close sound
var character_sheet_sound: AudioStream = null  # Character sheet open/close sound
var crit_window_open_sound: AudioStream = null  # Crystalline chime when crit window opens
var fire_fuel_add_sound: AudioStream = null  # Fire magic sound when adding fuel

# Weapon swing sounds (whoosh sounds when swinging weapons)
var sword_swing_sounds: Array[AudioStream] = []  # Sword whoosh (2 variations)
var unarmed_swing_sounds: Array[AudioStream] = []  # Unarmed/fist whoosh
var gunshot_sounds: Array[AudioStream] = []  # Gunshot sounds (for gun weapons)
var battle_rifle_sounds: Array[AudioStream] = []  # Battle rifle sounds (Halo-style burst)
var bullet_flesh_sounds: Array[AudioStream] = []  # Bullet impact on flesh (unarmored)
var bullet_armor_sounds: Array[AudioStream] = []  # Bullet ricochet off armor
var bow_shot_sounds: Array[AudioStream] = []  # Bow release/twang sounds

# Player sounds
var player_hurt_sounds: Array[AudioStream] = []  # Player hurt/death grunts (2 variations)
var player_footstep_sounds: Array[AudioStream] = []  # Player footsteps (cloth/leather)
var player_death_male_sound: AudioStream = null  # Male death sound
var player_death_female_sound: AudioStream = null  # Female death sound

# Enemy footstep sounds
var skeleton_footstep_sounds: Array[AudioStream] = []  # Skeleton bone clacking footsteps

# Wolf sounds
var wolf_aggro_sounds: Array[AudioStream] = []  # Wolf growl/snarl when spotting player
var wolf_attack_sounds: Array[AudioStream] = []  # Wolf bite attack sounds
var wolf_hurt_sounds: Array[AudioStream] = []  # Wolf pain yelp/whimper
var wolf_death_sounds: Array[AudioStream] = []  # Wolf death whimper
var wolf_footstep_sounds: Array[AudioStream] = []  # Wolf paw footsteps (walk)
var wolf_run_sounds: Array[AudioStream] = []  # Wolf running footsteps
var wolf_howl_distant_sound: AudioStream = null  # Single wolf howl
var wolf_howl_pack_sound: AudioStream = null  # Pack howl chorus
var wolf_howl_alpha_sound: AudioStream = null  # Alpha wolf howl

# Wolf howl cooldown system (prevents spam, creates atmosphere)
var _last_howl_time: float = -999.0
var _recent_howl_times: Array[float] = []
const HOWL_GLOBAL_COOLDOWN: float = 45.0  # Min seconds between ANY wolf howl
const HOWL_DIMINISHING_WINDOW: float = 120.0  # Window for tracking recent howls
const HOWL_MAX_IN_WINDOW: int = 3  # Max howls allowed in window

# Active wolf sound player (only one wolf vocalization at a time)
var active_wolf_sound_player: AudioStreamPlayer2D = null

# Dodge/dash sounds
var dodge_sounds: Array[AudioStream] = []  # Dodge whoosh sounds (2 variations)

# Healing staff sounds
var healing_staff_cast_sound: AudioStream = null  # Initial cast (spawns aura + fires projectile)
var healing_staff_impact_sound: AudioStream = null  # Projectile landing explosion (second pulse)

# Environment damage sounds
var lava_burn_sound: AudioStream = null  # Fire damage when player stands in lava

# Player progression sounds
var level_up_sound: AudioStream = null  # Celebratory level up fanfare

# Tree chopping/falling sounds (from TreeAudioManager)
var tree_chop_sounds: Array[AudioStream] = []
var tree_fall_sounds: Array[AudioStream] = []

# Weapon-specific hit sounds (organized by weapon type)
var weapon_hit_sounds: Dictionary = {
	"sword": [],
	"mace": [],
	"spear": [],
	"dagger": [],
	"unarmed": []
}

# Background music playlist
var music_tracks: Array[AudioStream] = []
var current_track_index: int = 0
var music_player: AudioStreamPlayer = null
var music_volume_db: float = -15.0  # Store target volume for playlist
const MUSIC_FADE_DURATION: float = 2.0  # Seconds to fade in/out

# Special music tracks (for transitions and events)
var transition_music: AudioStream = null  # Scene transition music
var claimsequence_music: AudioStream = null  # Reward claim sequence music
var special_music_player: AudioStreamPlayer = null  # Player for special music

# Trading Hub music playlist (separate from zone music)
var trading_hub_tracks: Array[AudioStream] = []
var trading_hub_track_index: int = 0
var _playing_hub_music: bool = false  # Flag to track if playing hub or zone music
var _music_fade_tween: Tween = null  # Store fade tween so we can cancel it

# Menu music (plays on MainMenu and Armory, stops when entering game world)
var menu_music: AudioStream = null
var menu_music_player: AudioStreamPlayer = null
var _playing_menu_music: bool = false

# Mute state
var sfx_muted: bool = false
var music_muted: bool = false

# Volume control (in dB, 0 = full volume, -80 = silent)
var sfx_volume_db: float = 0.0  # SFX volume offset applied to all sound effects

func _ready() -> void:
	# Create audio buses if they don't exist
	_setup_audio_buses()

	# Load real sound files first
	print("🔊 Loading real sound files...")
	_load_real_sounds()

	# Pre-generate all placeholder sounds (uses real sounds if loaded)
	print("🔊 Generating sound cache...")
	_generate_all_sounds()
	print("✅ Sound system ready!")


func _setup_audio_buses() -> void:
	"""Create Music and SFX audio buses if they don't exist"""
	# Check if Music bus exists
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx < 0:
		# Create Music bus as child of Master
		var new_idx = AudioServer.bus_count
		AudioServer.add_bus(new_idx)
		AudioServer.set_bus_name(new_idx, "Music")
		AudioServer.set_bus_send(new_idx, "Master")
		print("🔊 Created 'Music' audio bus")

	# Check if SFX bus exists
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx < 0:
		# Create SFX bus as child of Master
		var new_idx = AudioServer.bus_count
		AudioServer.add_bus(new_idx)
		AudioServer.set_bus_name(new_idx, "SFX")
		AudioServer.set_bus_send(new_idx, "Master")
		print("🔊 Created 'SFX' audio bus")

	# Load saved volume settings
	_load_volume_settings()


func _load_volume_settings() -> void:
	"""Load and apply saved volume settings from user config"""
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return  # No saved settings, use defaults

	# Load saved values (0-100 scale)
	var master_vol = config.get_value("audio", "master_volume", 80.0)
	var music_vol = config.get_value("audio", "music_volume", 70.0)
	var sfx_vol = config.get_value("audio", "sfx_volume", 80.0)

	# Convert to dB and apply to buses
	var master_db = lerp(-40.0, 0.0, master_vol / 100.0)
	var music_db = lerp(-40.0, 0.0, music_vol / 100.0)
	var sfx_db = lerp(-40.0, 0.0, sfx_vol / 100.0)

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_db)

	var music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, music_db)

	var sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, sfx_db)
		# NOTE: sfx_volume_db stays at 0.0 - the bus handles volume now
		# Don't set sfx_volume_db here to avoid double volume reduction

	print("🔊 Loaded volume settings - Master: %.0f%%, Music: %.0f%%, SFX: %.0f%%" % [master_vol, music_vol, sfx_vol])

func _load_real_sounds() -> void:
	"""Load real sound files for combat effects"""
	# Load weakpoint hit sounds (devastating bone crunch sounds)
	for i in range(1, 7):
		var weakpoint = load("res://assets/audio/sfx/combat/hits/weakpoint_hit_%d.wav" % i)
		if weakpoint:
			weakpoint_sounds.append(weakpoint)
			print("  ✅ Loaded weakpoint_hit_%d.wav" % i)
		else:
			push_warning("  ⚠️ Failed to load weakpoint_hit_%d.wav" % i)

	print("  📊 Loaded %d weakpoint sound variations" % weakpoint_sounds.size())

	# Load weakpoint destruction sound
	weakpoint_destroyed_sound = load("res://assets/audio/sfx/combat/hits/weakpoint_destroyed.wav")
	if weakpoint_destroyed_sound:
		print("  ✅ Loaded weakpoint_destroyed.wav")
	else:
		push_warning("  ⚠️ Failed to load weakpoint_destroyed.wav")

	# Load critical hit sound (for non-weakpoint crits)
	critical_hit_sound = load("res://assets/audio/sfx/combat/hits/critical_hit.wav")
	if critical_hit_sound:
		print("  ✅ Loaded critical_hit.wav")
	else:
		push_warning("  ⚠️ Failed to load critical_hit.wav")

	# Load normal hit sounds
	var normal_hit_1 = load("res://assets/audio/sfx/combat/hits/normal_hit_1.wav")
	var normal_hit_2 = load("res://assets/audio/sfx/combat/hits/normal_hit_2.wav")

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

	# Load skeleton hurt sounds (multiple variations)
	for i in range(1, 5):
		var skeleton_hurt = load("res://assets/audio/sfx/combat/reactions/skeleton_hurt_%d.wav" % i)
		if skeleton_hurt:
			skeleton_hurt_sounds.append(skeleton_hurt)
			print("  ✅ Loaded skeleton_hurt_%d.wav" % i)
		else:
			push_warning("  ⚠️ Failed to load skeleton_hurt_%d.wav" % i)

	print("  📊 Loaded %d skeleton hurt sound variations" % skeleton_hurt_sounds.size())

	# Load skeleton attack sound (menacing cackle)
	skeleton_attack_sound = load("res://assets/audio/sfx/combat/reactions/skeleton_attack.wav")
	if skeleton_attack_sound:
		print("  ✅ Loaded skeleton_attack.wav")
	else:
		push_warning("  ⚠️ Failed to load skeleton_attack.wav")

	# Load skeleton aggro sounds (when skeleton spots player - 3 variations)
	for i in range(1, 4):
		var skeleton_aggro = load("res://assets/audio/sfx/combat/reactions/skeleton_aggro_%d.wav" % i)
		if skeleton_aggro:
			skeleton_aggro_sounds.append(skeleton_aggro)
			print("  ✅ Loaded skeleton_aggro_%d.wav" % i)
		else:
			push_warning("  ⚠️ Failed to load skeleton_aggro_%d.wav" % i)

	print("  📊 Loaded %d skeleton aggro sound variations" % skeleton_aggro_sounds.size())

	# Load skeleton death sounds (bones collapsing - 3 variations)
	for i in range(1, 4):
		var skeleton_death = load("res://assets/audio/sfx/combat/reactions/skeleton_death_%d.wav" % i)
		if skeleton_death:
			skeleton_death_sounds.append(skeleton_death)
			print("  ✅ Loaded skeleton_death_%d.wav" % i)
		else:
			push_warning("  ⚠️ Failed to load skeleton_death_%d.wav" % i)

	print("  📊 Loaded %d skeleton death sound variations" % skeleton_death_sounds.size())

	# Load gold loot sound (coin jingling)
	gold_loot_sound = load("res://assets/audio/sfx/ui/gold_loot.wav")
	if gold_loot_sound:
		print("  ✅ Loaded gold_loot.wav")
	else:
		push_warning("  ⚠️ Failed to load gold_loot.wav")

	# Load item pickup sound (satisfying pickup)
	item_pickup_sound = load("res://assets/audio/sfx/ui/item_pickup.wav")
	if item_pickup_sound:
		print("  ✅ Loaded item_pickup.wav")
	else:
		push_warning("  ⚠️ Failed to load item_pickup.wav")

	# Load chest open sound
	chest_open_sound = load("res://assets/audio/sfx/ui/chest_open.wav")
	if chest_open_sound:
		print("  ✅ Loaded chest_open.wav")
	else:
		push_warning("  ⚠️ Failed to load chest_open.wav")

	# Load corpse loot sound (rummaging through dead enemy)
	corpse_loot_sound = load("res://assets/audio/sfx/ui/corpse_loot.wav")
	if corpse_loot_sound:
		print("  ✅ Loaded corpse_loot.wav")
	else:
		push_warning("  ⚠️ Failed to load corpse_loot.wav")

	# Load blacksmith open sound (vendor UI)
	blacksmith_open_sound = load("res://assets/audio/sfx/ui/blacksmith_open.wav")
	if blacksmith_open_sound:
		print("  ✅ Loaded blacksmith_open.wav")
	else:
		push_warning("  ⚠️ Failed to load blacksmith_open.wav")

	# Load quest sounds
	quest_accept_sound = load("res://assets/audio/sfx/ui/quest_accept.wav")
	if quest_accept_sound:
		print("  ✅ Loaded quest_accept.wav")
	else:
		push_warning("  ⚠️ Failed to load quest_accept.wav")

	quest_turn_in_sound = load("res://assets/audio/sfx/ui/quest_turn_in.wav")
	if quest_turn_in_sound:
		print("  ✅ Loaded quest_turn_in.wav")
	else:
		push_warning("  ⚠️ Failed to load quest_turn_in.wav")

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

	# Load button click sound (UI interactions)
	button_click_sound = load("res://assets/audio/sfx/ui/button_click.wav")
	if button_click_sound:
		print("  ✅ Loaded button_click.wav")
	else:
		push_warning("  ⚠️ Failed to load button_click.wav")

	# Load button hover sound (UI interactions)
	button_hover_sound = load("res://assets/audio/sfx/ui/button_hover.wav")
	if button_hover_sound:
		print("  ✅ Loaded button_hover.wav")
	else:
		push_warning("  ⚠️ Failed to load button_hover.wav")

	# Load inventory open sound (bag open/close)
	inventory_open_sound = load("res://assets/audio/sfx/ui/inventory_open.wav")
	if inventory_open_sound:
		print("  ✅ Loaded inventory_open.wav")
	else:
		push_warning("  ⚠️ Failed to load inventory_open.wav")

	# Load character sheet sound (paper rustling)
	character_sheet_sound = load("res://assets/audio/sfx/ui/character_sheet_open.wav")
	if character_sheet_sound:
		print("  ✅ Loaded character_sheet_open.wav")
	else:
		push_warning("  ⚠️ Failed to load character_sheet_open.wav")

	# Load crit window open sound (crystalline chime)
	crit_window_open_sound = load("res://assets/audio/sfx/combat/crit_window_open.wav")
	if crit_window_open_sound:
		print("  ✅ Loaded crit_window_open.wav")
	else:
		push_warning("  ⚠️ Failed to load crit_window_open.wav")

	# Load fire fuel add sound (fire magic)
	fire_fuel_add_sound = load("res://assets/audio/sfx/ambient/fire_fuel_add.mp3")
	if fire_fuel_add_sound:
		print("  ✅ Loaded fire_fuel_add.mp3")
	else:
		push_warning("  ⚠️ Failed to load fire_fuel_add.mp3")

	# Load sword swing sounds (whoosh variations)
	var sword_swing_1 = load("res://assets/audio/sfx/combat/weapon_swings/sword_swing_1.wav")
	var sword_swing_2 = load("res://assets/audio/sfx/combat/weapon_swings/sword_swing_2.wav")

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

	# Load unarmed swing sounds (fist whoosh variations)
	for i in range(1, 4):
		var unarmed_swing = load("res://assets/audio/sfx/combat/weapon_swings/unarmed_swing_%d.wav" % i)
		if unarmed_swing:
			unarmed_swing_sounds.append(unarmed_swing)
			print("  ✅ Loaded unarmed_swing_%d.wav" % i)
		else:
			push_warning("  ⚠️ Failed to load unarmed_swing_%d.wav" % i)

	print("  📊 Loaded %d unarmed swing sound variations" % unarmed_swing_sounds.size())

	# Load gunshot/railgun sounds
	var railgun_fire = load("res://assets/audio/sfx/combat/weapons/railgun_fire.wav")
	if railgun_fire:
		gunshot_sounds.append(railgun_fire)
		print("  ✅ Loaded railgun_fire.wav")
	else:
		push_warning("  ⚠️ Failed to load railgun_fire.wav")

	print("  📊 Loaded %d gunshot sound variations" % gunshot_sounds.size())

	# Load battle rifle sounds (Halo-style 3-round burst) - 3 variations
	for i in range(1, 4):
		var br_path = "res://assets/audio/sfx/combat/weapons/battle_rifle_fire_%d.wav" % i
		var br_sound = load(br_path)
		if br_sound:
			battle_rifle_sounds.append(br_sound)
			print("  ✅ Loaded battle_rifle_fire_%d.wav" % i)
		else:
			print("  ℹ️ battle_rifle_fire_%d.wav not found" % i)
	print("  📊 Loaded %d battle rifle sound variations" % battle_rifle_sounds.size())

	# Load bullet flesh impact sounds - 4 variations
	for i in range(1, 5):
		var bf_path = "res://assets/audio/sfx/combat/hits/bullet_flesh_%d.wav" % i
		var bf_sound = load(bf_path)
		if bf_sound:
			bullet_flesh_sounds.append(bf_sound)
			print("  ✅ Loaded bullet_flesh_%d.wav" % i)
		else:
			print("  ℹ️ bullet_flesh_%d.wav not found" % i)
	print("  📊 Loaded %d bullet flesh impact variations" % bullet_flesh_sounds.size())

	# Load bullet armor ricochet sounds - 4 variations
	for i in range(1, 5):
		var ba_path = "res://assets/audio/sfx/combat/hits/bullet_armor_%d.wav" % i
		var ba_sound = load(ba_path)
		if ba_sound:
			bullet_armor_sounds.append(ba_sound)
			print("  ✅ Loaded bullet_armor_%d.wav" % i)
		else:
			print("  ℹ️ bullet_armor_%d.wav not found" % i)
	print("  📊 Loaded %d bullet armor ricochet variations" % bullet_armor_sounds.size())

	# Load bow shot sounds - 3 variations
	for i in range(1, 4):
		var bow_path = "res://assets/audio/sfx/combat/weapons/bow_shot_%d.wav" % i
		var bow_sound = load(bow_path)
		if bow_sound:
			bow_shot_sounds.append(bow_sound)
			print("  ✅ Loaded bow_shot_%d.wav" % i)
		else:
			print("  ℹ️ bow_shot_%d.wav not found" % i)
	print("  📊 Loaded %d bow shot sound variations" % bow_shot_sounds.size())

	# Load player hurt sounds (grunt/pain sounds)
	var player_hurt_1 = load("res://assets/audio/sfx/player/player_hurt_1.wav")
	var player_hurt_2 = load("res://assets/audio/sfx/player/player_hurt_2.wav")

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

	# Load player death sounds (gender-specific)
	player_death_male_sound = load("res://assets/audio/sfx/player/player_death_male.wav")
	if player_death_male_sound:
		print("  ✅ Loaded player_death_male.wav")
	else:
		push_warning("  ⚠️ Failed to load player_death_male.wav")

	player_death_female_sound = load("res://assets/audio/sfx/player/player_death_female.wav")
	if player_death_female_sound:
		print("  ✅ Loaded player_death_female.wav")
	else:
		push_warning("  ⚠️ Failed to load player_death_female.wav")

	# Load player footstep sounds
	var player_step_1 = load("res://assets/audio/sfx/footsteps/player_step_1.wav")
	var player_step_2 = load("res://assets/audio/sfx/footsteps/player_step_2.wav")
	var player_step_3 = load("res://assets/audio/sfx/footsteps/player_step_3.wav")

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
	var skeleton_step_1 = load("res://assets/audio/sfx/footsteps/skeleton_step_1.wav")
	var skeleton_step_2 = load("res://assets/audio/sfx/footsteps/skeleton_step_2.wav")
	var skeleton_step_3 = load("res://assets/audio/sfx/footsteps/skeleton_step_3.wav")

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

	# Load wolf sounds
	print("  🐺 Loading wolf sounds...")

	# Wolf aggro sounds (growl/snarl when spotting player)
	for i in range(1, 4):
		var wolf_aggro = load("res://assets/audio/sfx/combat/reactions/wolf_aggro_%d.wav" % i)
		if wolf_aggro:
			wolf_aggro_sounds.append(wolf_aggro)
			print("    ✅ Loaded wolf_aggro_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_aggro_%d.wav" % i)

	# Wolf attack sounds (bite)
	for i in range(1, 4):
		var wolf_attack = load("res://assets/audio/sfx/combat/reactions/wolf_attack_%d.wav" % i)
		if wolf_attack:
			wolf_attack_sounds.append(wolf_attack)
			print("    ✅ Loaded wolf_attack_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_attack_%d.wav" % i)

	# Wolf hurt sounds (yelp/whimper)
	for i in range(1, 6):
		var wolf_hurt = load("res://assets/audio/sfx/combat/reactions/wolf_hurt_%d.wav" % i)
		if wolf_hurt:
			wolf_hurt_sounds.append(wolf_hurt)
			print("    ✅ Loaded wolf_hurt_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_hurt_%d.wav" % i)

	# Wolf death sounds
	for i in range(1, 3):
		var wolf_death = load("res://assets/audio/sfx/combat/reactions/wolf_death_%d.wav" % i)
		if wolf_death:
			wolf_death_sounds.append(wolf_death)
			print("    ✅ Loaded wolf_death_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_death_%d.wav" % i)

	# Wolf footstep sounds (walk/trot)
	for i in range(1, 4):
		var wolf_step = load("res://assets/audio/sfx/footsteps/wolf_step_%d.wav" % i)
		if wolf_step:
			wolf_footstep_sounds.append(wolf_step)
			print("    ✅ Loaded wolf_step_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_step_%d.wav" % i)

	# Wolf running footstep sounds
	for i in range(1, 3):
		var wolf_run = load("res://assets/audio/sfx/footsteps/wolf_run_%d.wav" % i)
		if wolf_run:
			wolf_run_sounds.append(wolf_run)
			print("    ✅ Loaded wolf_run_%d.wav" % i)
		else:
			push_warning("    ⚠️ Failed to load wolf_run_%d.wav" % i)

	# Wolf howl sounds (ambient)
	wolf_howl_distant_sound = load("res://assets/audio/sfx/ambient/wolf_howl_distant.wav")
	if wolf_howl_distant_sound:
		print("    ✅ Loaded wolf_howl_distant.wav")
	else:
		push_warning("    ⚠️ Failed to load wolf_howl_distant.wav")

	wolf_howl_pack_sound = load("res://assets/audio/sfx/ambient/wolf_howl_pack.wav")
	if wolf_howl_pack_sound:
		print("    ✅ Loaded wolf_howl_pack.wav")
	else:
		push_warning("    ⚠️ Failed to load wolf_howl_pack.wav")

	wolf_howl_alpha_sound = load("res://assets/audio/sfx/ambient/wolf_howl_alpha.wav")
	if wolf_howl_alpha_sound:
		print("    ✅ Loaded wolf_howl_alpha.wav")
	else:
		push_warning("    ⚠️ Failed to load wolf_howl_alpha.wav")

	print("  📊 Loaded wolf sounds: aggro=%d, attack=%d, hurt=%d, death=%d, steps=%d, run=%d" % [
		wolf_aggro_sounds.size(), wolf_attack_sounds.size(), wolf_hurt_sounds.size(),
		wolf_death_sounds.size(), wolf_footstep_sounds.size(), wolf_run_sounds.size()
	])

	# Load dodge/dash sounds
	var dodge_1 = load("res://assets/audio/sfx/dodge_1.wav")
	var dodge_2 = load("res://assets/audio/sfx/dodge_2.wav")

	if dodge_1:
		dodge_sounds.append(dodge_1)
		print("  ✅ Loaded dodge_1.wav")
	else:
		push_warning("  ⚠️ Failed to load dodge_1.wav")

	if dodge_2:
		dodge_sounds.append(dodge_2)
		print("  ✅ Loaded dodge_2.wav")
	else:
		push_warning("  ⚠️ Failed to load dodge_2.wav")

	print("  📊 Loaded %d dodge sound variations" % dodge_sounds.size())

	# Load weapon-specific hit sounds
	print("  🗡️ Loading weapon hit sounds...")
	_load_weapon_sounds("sword", 4)
	_load_weapon_sounds("unarmed", 3)
	# More weapon types can be added here later:
	# _load_weapon_sounds("mace", 4)
	# _load_weapon_sounds("spear", 4)
	print("  📊 Loaded weapon sounds: sword=%d, unarmed=%d" % [weapon_hit_sounds["sword"].size(), weapon_hit_sounds["unarmed"].size()])

	# Load background music playlist
	print("  🎵 Loading background music playlist...")
	var track1 = load("res://assets/audio/music/game_loop.ogg")
	if track1:
		music_tracks.append(track1)
		print("  ✅ Loaded game_loop.ogg (Track 1: The Raven's Shadow)")

	var track2 = load("res://assets/audio/music/game_loop_2.ogg")
	if track2:
		music_tracks.append(track2)
		print("  ✅ Loaded game_loop_2.ogg (Track 2: The dreadland's Whisper)")

	print("  📊 Loaded %d music tracks" % music_tracks.size())

	# Load Trading Hub music playlist
	print("  🏠 Loading Trading Hub music...")
	var hub_track1 = load("res://assets/audio/music/trading_hub_1.mp3")
	if hub_track1:
		trading_hub_tracks.append(hub_track1)
		print("  ✅ Loaded trading_hub_1.mp3 (The Cavern's Embrace)")

	var hub_track2 = load("res://assets/audio/music/trading_hub_2.mp3")
	if hub_track2:
		trading_hub_tracks.append(hub_track2)
		print("  ✅ Loaded trading_hub_2.mp3 (The Ember's Glow)")

	print("  📊 Loaded %d trading hub tracks" % trading_hub_tracks.size())

	# Load special music tracks (transitions, events)
	print("  🎬 Loading special music tracks...")
	transition_music = load("res://assets/audio/music/transition.ogg")
	if transition_music:
		print("  ✅ Loaded transition.ogg (Call to the Horizon)")
	else:
		push_warning("  ⚠️ Failed to load transition.ogg")

	claimsequence_music = load("res://assets/audio/music/claimsequence.ogg")
	if claimsequence_music:
		print("  ✅ Loaded claimsequence.ogg (Treasure Unveiled)")
	else:
		push_warning("  ⚠️ Failed to load claimsequence.ogg")

	# Load menu music (main menu and armory screens)
	print("  🏠 Loading menu music...")
	menu_music = load("res://assets/audio/music/thorns_and_shadows.mp3")
	if menu_music:
		print("  ✅ Loaded thorns_and_shadows.mp3 (Thorns and Shadows)")
	else:
		push_warning("  ⚠️ Failed to load thorns_and_shadows.mp3")

	# Load healing staff sounds
	print("  💚 Loading healing staff sounds...")
	healing_staff_cast_sound = load("res://assets/audio/sfx/player/healing_staff_cast.wav")
	if healing_staff_cast_sound:
		print("  ✅ Loaded healing_staff_cast.wav")
	else:
		push_warning("  ⚠️ Failed to load healing_staff_cast.wav")

	healing_staff_impact_sound = load("res://assets/audio/sfx/player/healing_staff_impact.wav")
	if healing_staff_impact_sound:
		print("  ✅ Loaded healing_staff_impact.wav")
	else:
		push_warning("  ⚠️ Failed to load healing_staff_impact.wav")

	# Load environment damage sounds
	print("  🔥 Loading environment damage sounds...")
	lava_burn_sound = load("res://assets/audio/sfx/combat/lava_burn.wav")
	if lava_burn_sound:
		print("  ✅ Loaded lava_burn.wav")
	else:
		push_warning("  ⚠️ Failed to load lava_burn.wav")

	# Load player progression sounds
	print("  🎉 Loading player progression sounds...")
	level_up_sound = load("res://assets/audio/sfx/player/level_up.wav")
	if level_up_sound:
		print("  ✅ Loaded level_up.wav")
	else:
		push_warning("  ⚠️ Failed to load level_up.wav")

	# Load tree chopping/falling sounds (shared by all trees)
	print("  🌲 Loading tree sounds...")
	var chop_paths = [
		"res://assets/audio/sfx/tree/chop_1.wav",
		"res://assets/audio/sfx/tree/chop_2.wav",
		"res://assets/audio/sfx/tree/chop_3.wav"
	]
	for path in chop_paths:
		var stream = load(path)
		if stream:
			tree_chop_sounds.append(stream)
			print("  ✅ Loaded %s" % path.get_file())
		else:
			push_warning("  ⚠️ Failed to load %s" % path)

	var fall_paths = [
		"res://assets/audio/sfx/tree/tree_fall_1.wav",
		"res://assets/audio/sfx/tree/tree_fall_2.wav",
		"res://assets/audio/sfx/tree/tree_fall_3.wav"
	]
	for path in fall_paths:
		var stream = load(path)
		if stream:
			tree_fall_sounds.append(stream)
			print("  ✅ Loaded %s" % path.get_file())
		else:
			push_warning("  ⚠️ Failed to load %s" % path)

	print("  📊 Loaded %d tree chop sounds and %d tree fall sounds (shared by all trees)" % [tree_chop_sounds.size(), tree_fall_sounds.size()])

func _load_weapon_sounds(weapon_type: String, count: int) -> void:
	"""Load weapon-specific hit sounds"""
	for i in range(1, count + 1):
		var sound_path = "res://assets/audio/sfx/combat/weapons/%s/%s_hit_%d.wav" % [weapon_type, weapon_type, i]
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
	sound_cache[SoundType.CORPSE_LOOT] = corpse_loot_sound if corpse_loot_sound else _generate_chest_open()  # Fallback to chest sound
	sound_cache[SoundType.BLACKSMITH_OPEN] = blacksmith_open_sound if blacksmith_open_sound else _generate_chest_open()  # Fallback to chest sound
	sound_cache[SoundType.QUEST_ACCEPT] = quest_accept_sound if quest_accept_sound else _generate_gold_loot()  # Fallback
	sound_cache[SoundType.QUEST_TURN_IN] = quest_turn_in_sound if quest_turn_in_sound else _generate_gold_loot()  # Fallback
	sound_cache[SoundType.INVENTORY_MOVE] = inventory_move_sound if inventory_move_sound else _generate_inventory_move()
	sound_cache[SoundType.EQUIP_ITEM] = equip_item_sound if equip_item_sound else _generate_equip_item()

	# Environment sounds
	sound_cache[SoundType.FIRE_FUEL_ADD] = fire_fuel_add_sound if fire_fuel_add_sound else _generate_fire_fuel_add()

	# Combat defense sounds
	sound_cache[SoundType.SHIELD_BLOCK] = _generate_shield_block()

	# Footstep sounds (use real sounds if loaded, otherwise generate placeholders)
	sound_cache[SoundType.FOOTSTEP_PLAYER] = player_footstep_sounds[0] if not player_footstep_sounds.is_empty() else _generate_footstep_soft()
	sound_cache[SoundType.FOOTSTEP_SKELETON] = skeleton_footstep_sounds[0] if not skeleton_footstep_sounds.is_empty() else _generate_footstep_hard()

## Play a sound at a specific position in the world
func play_sound(sound_type: SoundType, global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if not sound_cache.has(sound_type):
		push_error("Sound type not found: ", sound_type)
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_cache[sound_type]
	player.volume_db = volume_db + sfx_volume_db  # Apply SFX volume setting
	player.bus = "SFX"
	player.global_position = global_pos
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play a sound without 2D positioning (UI sounds, etc)
func play_sound_2d(sound_type: SoundType, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if not sound_cache.has(sound_type):
		push_error("Sound type not found: ", sound_type)
		return

	var stream = sound_cache[sound_type]
	if not stream:
		push_warning("Sound stream is null for type: ", sound_type)
		return

	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db + sfx_volume_db  # Apply SFX volume setting
	player.bus = "SFX"  # Use SFX bus for UI sounds (affected by SFX slider)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Get a sound stream for attaching to existing AudioStreamPlayer nodes
func get_sound(sound_type: SoundType) -> AudioStream:
	return sound_cache.get(sound_type, null)

## Play a random weakpoint hit sound with pitch variation (for satisfying spam-clicking)
func play_weakpoint_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if weakpoint_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.HIT_WEAKPOINT, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = weakpoint_sounds[randi() % weakpoint_sounds.size()]

	# Create player with subtle pitch randomization (±3% for variety)
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation to avoid distortion
	player.max_polyphony = 8  # Allow multiple instances for spam clicking
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play critical hit sound (for non-weakpoint critical hits)
func play_critical_hit_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if not critical_hit_sound:
		# Fallback to placeholder sound if no real sound loaded
		play_sound(SoundType.HIT_CRIT, global_pos, volume_db)
		return

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = critical_hit_sound
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.max_polyphony = 4  # Allow some overlap but less than weakpoints
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play normal hit sound (for regular non-crit hits)
func play_normal_hit_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0, weapon_type: String = "") -> void:
	if sfx_muted:
		return
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
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.max_polyphony = 4  # Allow some overlap
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play skeleton hurt sound (when skeleton takes damage)
func play_skeleton_hurt_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if skeleton_hurt_sounds.is_empty():
		# No fallback - just don't play if not loaded
		return

	# Pick random hurt sound variation
	var sound_stream = skeleton_hurt_sounds[randi() % skeleton_hurt_sounds.size()]

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.max_polyphony = 3  # Allow some overlap but not too much
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play skeleton attack sound - only one skeleton sound at a time, no overlap
func play_skeleton_attack_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	_play_skeleton_sound(skeleton_attack_sound, global_pos, volume_db)

## Play skeleton aggro sound (when skeleton spots player) - uses dedicated aggro sounds
func play_skeleton_aggro_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if skeleton_aggro_sounds.is_empty():
		# Fallback to attack sound if no aggro sounds loaded
		_play_skeleton_sound(skeleton_attack_sound, global_pos, volume_db)
		return

	# Pick random aggro sound variation
	var sound = skeleton_aggro_sounds[randi() % skeleton_aggro_sounds.size()]
	_play_skeleton_sound(sound, global_pos, volume_db)

func _play_skeleton_sound(sound: AudioStream, global_pos: Vector2, volume_db: float) -> void:
	# If a skeleton sound is already playing, don't play another
	if is_instance_valid(active_skeleton_sound_player) and active_skeleton_sound_player.playing:
		return

	if not sound:
		return

	# Create or reuse the sound player
	if not is_instance_valid(active_skeleton_sound_player):
		active_skeleton_sound_player = AudioStreamPlayer2D.new()
		get_tree().root.add_child(active_skeleton_sound_player)

	active_skeleton_sound_player.stream = sound
	active_skeleton_sound_player.volume_db = volume_db + sfx_volume_db
	active_skeleton_sound_player.bus = "SFX"
	active_skeleton_sound_player.global_position = global_pos
	active_skeleton_sound_player.pitch_scale = randf_range(0.95, 1.05)
	active_skeleton_sound_player.play()

## Play skeleton death sound (random between 2 bone collapse variations)
func play_skeleton_death_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if skeleton_death_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.SKELETON_DEATH, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = skeleton_death_sounds[randi() % skeleton_death_sounds.size()]

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

# ============================================
# WOLF SOUNDS
# ============================================

## Play wolf hurt sound (when wolf takes damage)
func play_wolf_hurt_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return
	if wolf_hurt_sounds.is_empty():
		return

	var sound_stream = wolf_hurt_sounds[randi() % wolf_hurt_sounds.size()]

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.max_polyphony = 3
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play wolf attack sound (bite) - only one wolf vocalization at a time
func play_wolf_attack_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	if wolf_attack_sounds.is_empty():
		return

	var sound = wolf_attack_sounds[randi() % wolf_attack_sounds.size()]
	_play_wolf_vocalization(sound, global_pos, volume_db)

## Play wolf aggro sound (when wolf spots player) - only one wolf vocalization at a time
func play_wolf_aggro_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	if wolf_aggro_sounds.is_empty():
		return

	var sound = wolf_aggro_sounds[randi() % wolf_aggro_sounds.size()]
	_play_wolf_vocalization(sound, global_pos, volume_db)

## Play wolf death sound
func play_wolf_death_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -4.0) -> void:
	if sfx_muted:
		return
	if wolf_death_sounds.is_empty():
		return

	var sound_stream = wolf_death_sounds[randi() % wolf_death_sounds.size()]

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Internal: Play wolf vocalization (ensures only one at a time)
func _play_wolf_vocalization(sound: AudioStream, global_pos: Vector2, volume_db: float) -> void:
	if is_instance_valid(active_wolf_sound_player) and active_wolf_sound_player.playing:
		return

	if not sound:
		return

	if not is_instance_valid(active_wolf_sound_player):
		active_wolf_sound_player = AudioStreamPlayer2D.new()
		get_tree().root.add_child(active_wolf_sound_player)

	active_wolf_sound_player.stream = sound
	active_wolf_sound_player.volume_db = volume_db + sfx_volume_db
	active_wolf_sound_player.bus = "SFX"
	active_wolf_sound_player.global_position = global_pos
	active_wolf_sound_player.pitch_scale = randf_range(0.93, 1.07)
	active_wolf_sound_player.play()

## Play wolf footstep sound with distance culling
func play_wolf_footstep(global_pos: Vector2, camera_pos: Vector2, is_running: bool = false, volume_db: float = -18.0) -> void:
	if sfx_muted:
		return
	# Distance culling
	var distance = global_pos.distance_to(camera_pos)
	if distance > 800.0:
		return

	var sounds_to_use = wolf_run_sounds if is_running else wolf_footstep_sounds
	if sounds_to_use.is_empty():
		return

	var sound_stream = sounds_to_use[randi() % sounds_to_use.size()]

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.93, 1.07)
	player.max_polyphony = 4
	player.max_distance = 1200.0
	player.attenuation = 1.5
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)

	await get_tree().create_timer(0.001).timeout
	if is_instance_valid(player):
		player.play()

## Try to play ambient wolf howl (respects cooldown/diminishing returns)
## howl_type: "distant", "pack", or "alpha"
## Returns true if howl was played, false if on cooldown
## Uses spatial audio from closest alpha wolf to player for directional effect
func try_play_wolf_howl(_global_pos: Vector2 = Vector2.ZERO, howl_type: String = "distant", volume_db: float = -10.0) -> bool:
	if sfx_muted:
		return false

	var current_time = Time.get_ticks_msec() / 1000.0

	# Check global cooldown
	if current_time - _last_howl_time < HOWL_GLOBAL_COOLDOWN:
		print("🐺 Howl blocked by cooldown (%.1fs remaining)" % (HOWL_GLOBAL_COOLDOWN - (current_time - _last_howl_time)))
		return false

	# Clean old entries and check diminishing returns
	var new_times: Array[float] = []
	for t in _recent_howl_times:
		if current_time - t < HOWL_DIMINISHING_WINDOW:
			new_times.append(t)
	_recent_howl_times = new_times

	if _recent_howl_times.size() >= HOWL_MAX_IN_WINDOW:
		print("🐺 Howl blocked by diminishing returns (%d/%d in window)" % [_recent_howl_times.size(), HOWL_MAX_IN_WINDOW])
		return false

	# Select howl sound
	var howl_sound: AudioStream = null
	match howl_type:
		"pack":
			howl_sound = wolf_howl_pack_sound
		"alpha":
			howl_sound = wolf_howl_alpha_sound
		_:
			howl_sound = wolf_howl_distant_sound

	if not howl_sound:
		print("🐺 Howl sound not loaded for type: %s" % howl_type)
		return false

	# Record howl time
	_last_howl_time = current_time
	_recent_howl_times.append(current_time)

	# Find closest alpha wolf to player for spatial positioning
	var howl_pos = _find_closest_alpha_wolf_position()
	var distance_to_player = 0.0

	if howl_pos != Vector2.ZERO:
		var player_node = get_tree().get_first_node_in_group("player")
		if player_node:
			distance_to_player = howl_pos.distance_to(player_node.global_position)

	# Play the howl with spatial audio (very large range for atmosphere)
	var player = AudioStreamPlayer2D.new()
	player.stream = howl_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.95, 1.05)
	player.max_distance = 8000.0  # Huge range - heard across the map
	player.attenuation = 0.3  # Very slow falloff
	player.global_position = howl_pos if howl_pos != Vector2.ZERO else _global_pos
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

	print("🐺🌙 Wolf howl played (%s) from pos %s (%.0fpx from player) - cooldown: %.0fs" % [howl_type, howl_pos, distance_to_player, HOWL_GLOBAL_COOLDOWN])
	return true


## Find the closest pack alpha or alpha dire wolf to the player
func _find_closest_alpha_wolf_position() -> Vector2:
	var player_node = get_tree().get_first_node_in_group("player")
	if not player_node:
		return Vector2.ZERO

	var player_pos = player_node.global_position
	var closest_pos = Vector2.ZERO
	var closest_dist = INF

	# Search for wolves
	for wolf in get_tree().get_nodes_in_group("wolves"):
		if not is_instance_valid(wolf):
			continue
		# Check if pack_alpha or is_alpha_dire_wolf
		if wolf.get("pack_alpha") == true or wolf.get("is_alpha_dire_wolf") == true:
			var dist = player_pos.distance_to(wolf.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_pos = wolf.global_position

	return closest_pos

## Force play wolf howl (ignores cooldown - use sparingly for special events)
## Uses spatial audio from closest alpha wolf
func force_play_wolf_howl(_global_pos: Vector2 = Vector2.ZERO, howl_type: String = "distant", volume_db: float = -10.0) -> void:
	if sfx_muted:
		return

	var howl_sound: AudioStream = null
	match howl_type:
		"pack":
			howl_sound = wolf_howl_pack_sound
		"alpha":
			howl_sound = wolf_howl_alpha_sound
		_:
			howl_sound = wolf_howl_distant_sound

	if not howl_sound:
		return

	var howl_pos = _find_closest_alpha_wolf_position()

	var player = AudioStreamPlayer2D.new()
	player.stream = howl_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.95, 1.05)
	player.max_distance = 8000.0
	player.attenuation = 0.3
	player.global_position = howl_pos if howl_pos != Vector2.ZERO else _global_pos
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()
	print("🐺🌙 Wolf howl FORCED (%s) from %s" % [howl_type, howl_pos])

## Play sword swing sound (random whoosh variation)
func play_sword_swing_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if sword_swing_sounds.is_empty():
		# Fallback to placeholder sound if no real sounds loaded
		play_sound(SoundType.SWING, global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = sword_swing_sounds[randi() % sword_swing_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play unarmed swing sound (whoosh when punching/kicking)
func play_unarmed_swing_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if unarmed_swing_sounds.is_empty():
		# Fallback to sword swing if no unarmed sounds loaded
		play_sword_swing_sound(global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = unarmed_swing_sounds[randi() % unarmed_swing_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play gunshot sound (for gun weapons)
func play_gunshot_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return
	if gunshot_sounds.is_empty():
		# No gunshot sounds loaded - use sword swing as placeholder with higher pitch
		if not sword_swing_sounds.is_empty():
			var sound_stream = sword_swing_sounds[randi() % sword_swing_sounds.size()]
			var player = AudioStreamPlayer2D.new()
			player.stream = sound_stream
			player.volume_db = volume_db + sfx_volume_db
			player.global_position = global_pos
			player.pitch_scale = 1.5  # Higher pitch for "snap" sound
			player.finished.connect(player.queue_free)
			get_tree().root.add_child(player)
			player.play()
		return

	# Pick random gunshot variation
	var sound_stream = gunshot_sounds[randi() % gunshot_sounds.size()]

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play battle rifle sound (Halo-style burst fire - lighter, higher pitch than railgun)
func play_battle_rifle_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return

	var sound_stream: AudioStream = null
	var pitch: float = randf_range(0.97, 1.03)

	if not battle_rifle_sounds.is_empty():
		# Use dedicated battle rifle sound
		sound_stream = battle_rifle_sounds[randi() % battle_rifle_sounds.size()]
	elif not gunshot_sounds.is_empty():
		# Fallback: pitch-shifted gunshot for lighter report
		sound_stream = gunshot_sounds[randi() % gunshot_sounds.size()]
		pitch = randf_range(1.25, 1.35)  # Higher pitch for lighter, snappier sound
	else:
		# Last resort: sword swing with very high pitch
		if not sword_swing_sounds.is_empty():
			sound_stream = sword_swing_sounds[randi() % sword_swing_sounds.size()]
			pitch = 1.8

	if sound_stream == null:
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db - 3.0  # Slightly quieter than railgun
	player.global_position = global_pos
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play bullet impact sound (automatically chooses flesh or armor based on enemy type)
## is_armored: true for armored targets (training dummy), false for flesh (skeletons, wolves)
func play_bullet_impact_sound(global_pos: Vector2 = Vector2.ZERO, is_armored: bool = false, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return

	var sounds_to_use: Array[AudioStream]
	if is_armored and not bullet_armor_sounds.is_empty():
		sounds_to_use = bullet_armor_sounds
	elif not bullet_flesh_sounds.is_empty():
		sounds_to_use = bullet_flesh_sounds
	else:
		# Fallback to normal hit sound
		play_normal_hit_sound(global_pos, volume_db)
		return

	# Pick random sound variation
	var sound_stream = sounds_to_use[randi() % sounds_to_use.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play bow shot sound (string release/twang)
func play_bow_shot_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -12.0) -> void:
	if sfx_muted:
		return

	if bow_shot_sounds.is_empty():
		# Fallback: use sword swing with higher pitch for twang-like sound
		if not sword_swing_sounds.is_empty():
			var sound_stream = sword_swing_sounds[randi() % sword_swing_sounds.size()]
			var player = AudioStreamPlayer2D.new()
			player.stream = sound_stream
			player.volume_db = volume_db + sfx_volume_db
			player.global_position = global_pos
			player.pitch_scale = 1.3  # Higher pitch for snap/twang
			player.finished.connect(player.queue_free)
			get_tree().root.add_child(player)
			player.play()
		return

	# Pick random bow shot variation
	var sound_stream = bow_shot_sounds[randi() % bow_shot_sounds.size()]

	# Create player with slight pitch randomization
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play bow impact sound (reuses bullet flesh sounds for satisfying thud)
func play_bow_impact_sound(global_pos: Vector2 = Vector2.ZERO, hit: bool = true, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return

	if not hit:
		# Miss sound - skip for now (arrow hitting ground silently)
		# Could add a subtle ground thud sound here later
		return

	# Hit sound - use bullet flesh impact
	if bullet_flesh_sounds.is_empty():
		play_normal_hit_sound(global_pos, volume_db)
		return

	var sound_stream = bullet_flesh_sounds[randi() % bullet_flesh_sounds.size()]

	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.85, 0.95)  # Slightly lower pitch than bullets for heavier arrow
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play player hurt sound (random grunt/pain variation)
func play_player_hurt_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return
	if player_hurt_sounds.is_empty():
		# No real sounds loaded, skip (no placeholder for player hurt)
		return

	# Pick random sound variation
	var sound_stream = player_hurt_sounds[randi() % player_hurt_sounds.size()]

	# Create player with slight pitch randomization for variety
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play player death sound (gender-specific)
## is_female: true for female character, false for male
func play_player_death_sound(global_pos: Vector2 = Vector2.ZERO, is_female: bool = false, volume_db: float = -4.0) -> void:
	if sfx_muted:
		return
	var sound_stream = player_death_female_sound if is_female else player_death_male_sound

	if not sound_stream:
		# Fallback to hurt sound if death sound not loaded
		play_player_hurt_sound(global_pos, volume_db)
		return

	# Create player - no pitch randomization for dramatic death sound
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = 1.0  # Keep original pitch for impact
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play player footstep sound with distance culling
func play_player_footstep(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -18.0) -> void:
	if sfx_muted:
		return
	if player_footstep_sounds.is_empty():
		# Fallback to placeholder
		play_sound(SoundType.FOOTSTEP_PLAYER, global_pos, volume_db)
		return

	# Pick random variation
	var sound_stream = player_footstep_sounds[randi() % player_footstep_sounds.size()]

	# Create player with slight pitch variation
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
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
	if sfx_muted:
		return
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
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
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
	if sfx_muted:
		return
	if not fire_fuel_add_sound:
		# Fallback to placeholder
		play_sound(SoundType.FIRE_FUEL_ADD, global_pos, volume_db)
		return

	# Create player with pitch randomization for spammable variety
	var player = AudioStreamPlayer2D.new()
	player.stream = fire_fuel_add_sound
	player.bus = "SFX"
	player.global_position = global_pos
	player.max_polyphony = 8  # Allow many overlapping sounds for spam clicking

	if enhanced:
		# Enhanced version: slightly louder and higher pitch
		player.volume_db = volume_db + sfx_volume_db + 3.0
		player.pitch_scale = randf_range(1.05, 1.15)
	else:
		# Normal version: subtle pitch variation
		player.volume_db = volume_db + sfx_volume_db
		player.pitch_scale = randf_range(0.95, 1.05)

	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play dodge/dash sound (whoosh when evading)
## dodge_2.wav is a 3-second clip so we speed it up with pitch_scale
func play_dodge_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	if dodge_sounds.is_empty():
		# Fallback to unarmed swing if no dodge sounds loaded
		play_unarmed_swing_sound(global_pos, volume_db)
		return

	# Pick random variation
	var sound_index = randi() % dodge_sounds.size()
	var sound_stream = dodge_sounds[sound_index]

	# Create player with pitch variation
	var player = AudioStreamPlayer2D.new()
	player.stream = sound_stream
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos

	# dodge_2.wav (index 1) is a 3-second clip - speed it up to ~0.5 seconds
	# dodge_1.wav (index 0) is already quick - use normal pitch with slight variation
	if sound_index == 1:
		# Speed up the long clip: pitch_scale 2.5-3.0 makes it ~1 second
		player.pitch_scale = randf_range(2.5, 3.0)
	else:
		# Normal pitch with subtle variation
		player.pitch_scale = randf_range(0.95, 1.05)

	player.max_polyphony = 2  # Allow slight overlap
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play inventory move sound (dragging items between slots)
func play_inventory_move_sound(volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if not inventory_move_sound:
		# Fallback to placeholder
		play_sound_2d(SoundType.INVENTORY_MOVE, volume_db)
		return

	var player = AudioStreamPlayer.new()
	player.stream = inventory_move_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play equip item sound (equipping/unequipping gear)
func play_equip_sound(volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if not equip_item_sound:
		# Fallback to placeholder
		play_sound_2d(SoundType.EQUIP_ITEM, volume_db)
		return

	var player = AudioStreamPlayer.new()
	player.stream = equip_item_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play button click sound (UI interactions)
func play_button_click_sound(volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	if not button_click_sound:
		# No fallback - just skip if not loaded
		return

	var player = AudioStreamPlayer.new()
	player.stream = button_click_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play button hover sound (UI interactions)
func play_button_hover_sound(volume_db: float = -15.0) -> void:
	if sfx_muted:
		return
	if not button_hover_sound:
		# No fallback - just skip if not loaded
		return

	var player = AudioStreamPlayer.new()
	player.stream = button_hover_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)  # Subtle pitch variation
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play inventory open/close sound (leather pouch)
func play_inventory_open_sound(volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if not inventory_open_sound:
		return

	var player = AudioStreamPlayer.new()
	player.stream = inventory_open_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play character sheet open/close sound (paper rustling)
func play_character_sheet_sound(volume_db: float = -10.0) -> void:
	if sfx_muted:
		return
	if not character_sheet_sound:
		return

	var player = AudioStreamPlayer.new()
	player.stream = character_sheet_sound
	player.volume_db = volume_db + sfx_volume_db
	player.pitch_scale = randf_range(0.97, 1.03)
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play weakpoint destruction sound (explosive glass/bone shatter finale)
func play_weakpoint_destroyed_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = 0.0) -> void:
	if sfx_muted:
		return
	if not weakpoint_destroyed_sound:
		# Fallback to placeholder sound if no real sound loaded
		play_sound(SoundType.WEAKPOINT_DESTROYED, global_pos, volume_db)
		return

	# Create player - no pitch randomization for this dramatic finale
	var player = AudioStreamPlayer2D.new()
	player.stream = weakpoint_destroyed_sound
	player.volume_db = volume_db + sfx_volume_db
	player.bus = "SFX"
	player.global_position = global_pos
	player.pitch_scale = 1.0  # Keep original pitch for maximum impact
	player.max_polyphony = 2  # Allow slight overlap in case of rapid weakpoint destruction
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play healing staff cast sound (initial click - spawns aura + fires projectile)
func play_healing_cast_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -5.0) -> void:
	if sfx_muted:
		return
	if not healing_staff_cast_sound:
		push_warning("Healing staff cast sound not loaded")
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = healing_staff_cast_sound
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Slight variation
	player.max_distance = 800.0
	player.attenuation = 1.0
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play healing staff impact sound (projectile landing - second pulse explosion)
func play_healing_impact_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -3.0) -> void:
	if sfx_muted:
		return
	if not healing_staff_impact_sound:
		push_warning("Healing staff impact sound not loaded")
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = healing_staff_impact_sound
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)  # Slight variation
	player.max_distance = 800.0
	player.attenuation = 1.0
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play lava burn damage sound (fire damage when stepping in lava)
func play_lava_burn_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -6.0) -> void:
	if sfx_muted:
		return
	if not lava_burn_sound:
		push_warning("Lava burn sound not loaded")
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = lava_burn_sound
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.9, 1.1)  # Slight variation for variety
	player.max_distance = 600.0
	player.attenuation = 1.2
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play level up sound (celebratory fanfare when player levels up)
func play_level_up_sound(volume_db: float = -4.0) -> void:
	if sfx_muted:
		return
	if not level_up_sound:
		push_warning("Level up sound not loaded")
		return

	# Use non-positional audio so it plays at full volume regardless of camera position
	var player = AudioStreamPlayer.new()
	player.stream = level_up_sound
	player.volume_db = volume_db + sfx_volume_db
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

func _generate_shield_block() -> AudioStreamWAV:
	# Metallic clang/thud for shield blocking
	# Mix of low thud (wood impact) and higher metallic ring
	var sample_rate = 22050
	var duration = 0.25
	var samples = PackedVector2Array()
	var sample_count = int(duration * sample_rate)

	for i in range(sample_count):
		var t = float(i) / sample_rate
		# Envelope: quick attack, moderate decay
		var envelope = 1.0
		if i < sample_rate * 0.005:  # 5ms attack
			envelope = float(i) / (sample_rate * 0.005)
		else:
			envelope = exp(-t * 12.0)  # Fast decay

		# Low thud component (wood/shield body)
		var thud = sin(t * 120.0 * TAU) * 0.6

		# Metallic ring component (shield rim)
		var ring = sin(t * 800.0 * TAU) * 0.3 * exp(-t * 20.0)

		# Higher harmonic for bite
		var bite = sin(t * 1600.0 * TAU) * 0.1 * exp(-t * 30.0)

		var sample = (thud + ring + bite) * envelope * 0.5
		samples.append(Vector2(sample, sample))

	var wav = AudioStreamWAV.new()
	wav.data = _pack_samples(samples)
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = true
	return wav

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
	_playing_hub_music = false  # Mark that we're playing zone music, not hub

	# Create music player if needed
	if not music_player:
		music_player = AudioStreamPlayer.new()
		music_player.bus = "Music"
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
	# Respect mute state when changing tracks
	music_player.volume_db = -80.0 if music_muted else music_volume_db

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
	if _playing_hub_music:
		# Playing trading hub music - use hub playlist
		trading_hub_track_index = (trading_hub_track_index + 1) % trading_hub_tracks.size()
		_play_trading_hub_track()
	else:
		# Playing zone music - use zone playlist
		current_track_index = (current_track_index + 1) % music_tracks.size()
		_play_current_track()

## Stop the game music with fade-out
func stop_game_music() -> void:
	if not music_player or not music_player.playing:
		return

	# Kill any existing fade tween first
	if _music_fade_tween and _music_fade_tween.is_valid():
		_music_fade_tween.kill()

	_music_fade_tween = create_tween()
	_music_fade_tween.tween_property(music_player, "volume_db", -40.0, MUSIC_FADE_DURATION)
	_music_fade_tween.tween_callback(music_player.stop)

## Check if game music is currently playing
func is_game_music_playing() -> bool:
	return music_player and music_player.playing

# ============================================
# MENU MUSIC (Main Menu / Armory)
# ============================================

## Start playing menu music (persists across MainMenu and Armory scenes)
func play_menu_music(volume_db: float = -10.0) -> void:
	if not menu_music:
		push_warning("Menu music not loaded!")
		return

	# Don't restart if already playing
	if _playing_menu_music and menu_music_player and menu_music_player.playing:
		return

	_playing_menu_music = true

	# Create menu music player if needed
	if not menu_music_player:
		menu_music_player = AudioStreamPlayer.new()
		menu_music_player.name = "MenuMusicPlayer"
		menu_music_player.bus = "Music"
		add_child(menu_music_player)

	menu_music_player.stream = menu_music
	menu_music_player.volume_db = -80.0 if music_muted else volume_db

	# Loop the menu music
	if menu_music is AudioStreamMP3:
		(menu_music as AudioStreamMP3).loop = true
	elif menu_music is AudioStreamOggVorbis:
		(menu_music as AudioStreamOggVorbis).loop = true

	menu_music_player.play()
	print("🏠 Menu music started (Thorns and Shadows)")

## Stop menu music with fade-out (called when entering game world)
func stop_menu_music(fade_duration: float = 0.8) -> void:
	if not menu_music_player or not menu_music_player.playing:
		_playing_menu_music = false
		return

	_playing_menu_music = false

	if fade_duration > 0:
		var tween = create_tween()
		tween.tween_property(menu_music_player, "volume_db", -40.0, fade_duration)
		tween.tween_callback(menu_music_player.stop)
	else:
		menu_music_player.stop()

	print("🏠 Menu music stopped")

## Check if menu music is currently playing
func is_menu_music_playing() -> bool:
	return _playing_menu_music and menu_music_player and menu_music_player.playing

## Start playing Trading Hub music playlist
func play_trading_hub_music(volume_db: float = -15.0) -> void:
	if trading_hub_tracks.is_empty():
		push_warning("No trading hub music tracks loaded!")
		return

	music_volume_db = volume_db
	trading_hub_track_index = 0
	_playing_hub_music = true  # Mark that we're playing hub music

	# Create music player if needed
	if not music_player:
		music_player = AudioStreamPlayer.new()
		music_player.bus = "Music"
		add_child(music_player)
		music_player.finished.connect(_on_music_track_finished)

	# Stop current music if playing something else
	if music_player.playing:
		music_player.stop()

	# Kill any running fade-out tween that might interfere
	if _music_fade_tween and _music_fade_tween.is_valid():
		_music_fade_tween.kill()
		_music_fade_tween = null

	_play_trading_hub_track()

func _play_trading_hub_track() -> void:
	"""Play the current trading hub track"""
	if trading_hub_tracks.is_empty() or not music_player:
		return

	var track = trading_hub_tracks[trading_hub_track_index]
	music_player.stream = track
	music_player.volume_db = -80.0 if music_muted else music_volume_db

	# Don't loop individual tracks
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = false
	elif track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = false

	print("🏠 Now playing hub track %d/%d (%.0fs)" % [trading_hub_track_index + 1, trading_hub_tracks.size(), track.get_length()])
	music_player.play()

func _on_trading_hub_track_finished() -> void:
	"""Called when a trading hub track finishes"""
	trading_hub_track_index = (trading_hub_track_index + 1) % trading_hub_tracks.size()
	_play_trading_hub_track()

## Set game music volume (for settings)
func set_music_volume(volume_db: float) -> void:
	music_volume_db = volume_db
	if music_player:
		music_player.volume_db = volume_db

## Get current music volume (for other music players to sync)
func get_music_volume_db() -> float:
	return music_volume_db

## Skip to next track in playlist
func skip_music_track() -> void:
	if music_tracks.size() <= 1:
		return
	current_track_index = (current_track_index + 1) % music_tracks.size()
	_play_current_track()

# ============================================
# MUTE CONTROLS
# ============================================

## Toggle SFX mute state
func toggle_sfx_mute() -> void:
	sfx_muted = not sfx_muted
	print("🔊 SFX %s" % ("MUTED" if sfx_muted else "ON"))

## Toggle music mute state
func toggle_music_mute() -> void:
	music_muted = not music_muted
	if music_player:
		if music_muted:
			music_player.volume_db = -80.0  # Effectively silent
		else:
			music_player.volume_db = music_volume_db
	print("🎵 Music %s" % ("MUTED" if music_muted else "ON"))

# ============================================
# SPECIAL MUSIC (transitions, events)
# ============================================

## Ensure special music player exists
func _ensure_special_music_player() -> void:
	if not special_music_player:
		special_music_player = AudioStreamPlayer.new()
		special_music_player.bus = "Music"
		add_child(special_music_player)

## Play transition music (for scene changes)
## Optionally fades out current game music first
func play_transition_music(volume_db: float = -10.0, fade_out_game_music: bool = true) -> void:
	if not transition_music:
		push_warning("Transition music not loaded")
		return

	_ensure_special_music_player()

	# Fade out game music if playing
	if fade_out_game_music and music_player and music_player.playing:
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, 0.5)
		tween.tween_callback(music_player.stop)

	# Play transition music
	special_music_player.stream = transition_music
	special_music_player.volume_db = volume_db if not music_muted else -80.0
	special_music_player.play()
	print("🎬 Playing transition music")

## Play claim sequence music (for rewards, unlocks)
func play_claimsequence_music(volume_db: float = -10.0, fade_out_game_music: bool = true) -> void:
	if not claimsequence_music:
		push_warning("Claim sequence music not loaded")
		return

	_ensure_special_music_player()

	# Fade out game music if playing
	if fade_out_game_music and music_player and music_player.playing:
		var tween = create_tween()
		tween.tween_property(music_player, "volume_db", -40.0, 0.5)
		tween.tween_callback(music_player.stop)

	# Play claim sequence music
	special_music_player.stream = claimsequence_music
	special_music_player.volume_db = volume_db if not music_muted else -80.0
	special_music_player.play()
	print("🎁 Playing claim sequence music")

## Stop special music with optional fade
func stop_special_music(fade_duration: float = 1.0) -> void:
	if not special_music_player or not special_music_player.playing:
		return

	if fade_duration > 0:
		var tween = create_tween()
		tween.tween_property(special_music_player, "volume_db", -40.0, fade_duration)
		tween.tween_callback(special_music_player.stop)
	else:
		special_music_player.stop()

## Check if special music is playing
func is_special_music_playing() -> bool:
	return special_music_player and special_music_player.playing

# ============================================
# TREE SOUNDS (from TreeAudioManager)
# ============================================

## Get a random tree chopping sound
func get_random_chop_sound() -> AudioStream:
	if tree_chop_sounds.is_empty():
		return null
	return tree_chop_sounds[randi() % tree_chop_sounds.size()]

## Get a random tree falling sound
func get_random_fall_sound() -> AudioStream:
	if tree_fall_sounds.is_empty():
		return null
	return tree_fall_sounds[randi() % tree_fall_sounds.size()]

## Play tree chop sound at position (uses pooled audio - no per-tree AudioStreamPlayers needed)
func play_tree_chop_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	var sound = get_random_chop_sound()
	if not sound:
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = sound
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.95, 1.05)
	player.max_polyphony = 4
	player.bus = "SFX"
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()

## Play tree fall sound at position (uses pooled audio - no per-tree AudioStreamPlayers needed)
func play_tree_fall_sound(global_pos: Vector2 = Vector2.ZERO, volume_db: float = -8.0) -> void:
	if sfx_muted:
		return
	var sound = get_random_fall_sound()
	if not sound:
		return

	var player = AudioStreamPlayer2D.new()
	player.stream = sound
	player.volume_db = volume_db + sfx_volume_db
	player.global_position = global_pos
	player.pitch_scale = randf_range(0.97, 1.03)
	player.bus = "SFX"
	player.finished.connect(player.queue_free)

	get_tree().root.add_child(player)
	player.play()
