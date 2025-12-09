# TradingHub.gd - Main trading hub scene controller
extends Node2D

const PLAYER_SCENE = preload("res://scenes/player/player.tscn")

# Hub dimensions
const HUB_WIDTH: float = 3000.0
const HUB_HEIGHT: float = 2500.0
const CORRIDOR_LENGTH: float = 600.0

# Spawn points
const ENTRY_SPAWN_Y: float = 1000.0  # South side where players enter from Zone 1
const EXIT_NORTH_Y: float = -1100.0  # North exit to Zone 2

var local_player: Node = null
var _ambient_audio_player: AudioStreamPlayer = null

func _ready() -> void:
	print("[TradingHub] Scene loaded")

	# Mark player as in hub
	if has_node("/root/TradingHubManager"):
		get_node("/root/TradingHubManager").set_player_in_hub(true)

	# Spawn the local player
	_spawn_local_player()

	# Setup camera limits
	_setup_camera()

	# Start ambient audio
	_setup_ambient_audio()

	# Restore UI autoloads
	_restore_ui_autoloads()

func _spawn_local_player() -> void:
	local_player = PLAYER_SCENE.instantiate()

	# Spawn at south entry point
	local_player.position = Vector2(0, ENTRY_SPAWN_Y)

	# Add to scene
	$Players.add_child(local_player)

	# Add to player group
	local_player.add_to_group("player")

	print("[TradingHub] Player spawned at entry point")

func _setup_camera() -> void:
	# Wait for player camera to be ready
	await get_tree().process_frame

	if local_player and is_instance_valid(local_player):
		var camera = local_player.get_node_or_null("Camera2D")
		if camera:
			camera.limit_left = int(-HUB_WIDTH / 2) - 100
			camera.limit_right = int(HUB_WIDTH / 2) + 100
			camera.limit_top = int(-HUB_HEIGHT / 2) - 100
			camera.limit_bottom = int(HUB_HEIGHT / 2) + 100

func _setup_ambient_audio() -> void:
	# Create ambient dripping/echo sounds
	_ambient_audio_player = AudioStreamPlayer.new()
	_ambient_audio_player.volume_db = -15.0
	# TODO: Add actual ambient audio file
	add_child(_ambient_audio_player)

func _restore_ui_autoloads() -> void:
	# Restore any hidden UI autoloads (like inventory, etc)
	var autoloads = ["InventoryUI", "CharacterSheet", "QuestUI"]
	for autoload_name in autoloads:
		var autoload = get_node_or_null("/root/" + autoload_name)
		if autoload and autoload is CanvasLayer:
			autoload.visible = true

func _process(_delta: float) -> void:
	# Check for exit triggers
	if local_player and is_instance_valid(local_player):
		_check_exit_zones()

func _check_exit_zones() -> void:
	var player_y = local_player.position.y

	# South exit - return to Zone 1
	if player_y > ENTRY_SPAWN_Y + 100:
		_exit_to_zone1()

	# North exit - go to Zone 2 (placeholder)
	if player_y < EXIT_NORTH_Y:
		_exit_to_zone2()

func _exit_to_zone1() -> void:
	print("[TradingHub] Player exiting to Zone 1")

	if has_node("/root/TradingHubManager"):
		get_node("/root/TradingHubManager").set_player_in_hub(false)

	# Fade and transition
	var tween = create_tween()
	var canvas_mod = $CanvasModulate
	if canvas_mod:
		tween.tween_property(canvas_mod, "color", Color(0, 0, 0, 1), 0.5)
		tween.tween_callback(_load_zone1)
	else:
		_load_zone1()

func _load_zone1() -> void:
	# TODO: Set player spawn position based on origin chunk
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")

func _exit_to_zone2() -> void:
	print("[TradingHub] Player attempting to exit to Zone 2 (not implemented)")
	# Push player back - Zone 2 not implemented yet
	if local_player and is_instance_valid(local_player):
		local_player.position.y = EXIT_NORTH_Y + 50
		_spawn_floating_text("Zone 2 coming soon...", Color(0.7, 0.8, 0.9))

func _spawn_floating_text(text: String, color: Color) -> void:
	var combat_text_scene = load("res://scenes/ui/combat_text.tscn")
	if combat_text_scene and local_player:
		var combat_text = combat_text_scene.instantiate()
		add_child(combat_text)
		combat_text.global_position = local_player.global_position + Vector2(0, -50)
		if combat_text.has_method("setup"):
			combat_text.setup(text, color, false)

func _exit_tree() -> void:
	# Cleanup when leaving hub
	if has_node("/root/TradingHubManager"):
		get_node("/root/TradingHubManager").set_player_in_hub(false)
