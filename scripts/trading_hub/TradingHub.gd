# TradingHub.gd - Main trading hub scene controller
# Underground cavern with 3 entry corridors from Zone 1 and north exit to Zone 2
extends Node2D

# Use load() instead of preload() to avoid ERR_LOCKED when changing scenes
# while player instances are already active
var PLAYER_SCENE: PackedScene = null

func _get_player_scene() -> PackedScene:
	if PLAYER_SCENE == null:
		PLAYER_SCENE = load("res://scenes/player/player.tscn")
	return PLAYER_SCENE

# Hub dimensions - much larger for longer walks
const HUB_WIDTH: float = 5200.0   # Includes all corridors
const HUB_HEIGHT: float = 6500.0  # From south entries to Zone 2 north

# Hub center is at Y=-2500
# Spawn points for different entry corridors
const ENTRY_SPAWN_SOUTH: Vector2 = Vector2(0, 2100)       # Center corridor (chunk 0) - straight shot
const ENTRY_SPAWN_WEST: Vector2 = Vector2(-2200, 2100)    # West corridor (chunk -1) - curves to hub
const ENTRY_SPAWN_EAST: Vector2 = Vector2(2200, 2100)     # East corridor (chunk +1) - curves to hub

# Exit zones - walk back out the way you came
const EXIT_ZONE1_SOUTH_Y: float = 2200.0     # Walk south in center corridor -> Zone 1
const EXIT_ZONE1_WEST_Y: float = 2200.0      # Walk south in west corridor -> Zone 1 (check X too)
const EXIT_ZONE1_EAST_Y: float = 2200.0      # Walk south in east corridor -> Zone 1 (check X too)
const EXIT_ZONE2_NORTH_Y: float = -4100.0    # Walk north past portal -> Zone 2

var local_player: Node = null
var _ambient_audio_player: AudioStreamPlayer = null
var _origin_chunk: int = 0  # Which chunk player entered from

func _ready() -> void:
	print("=" .repeat(60))
	print("[TradingHub] ===== SCENE LOADED - The Passage =====")
	print("=" .repeat(60))

	# Mark player as in hub
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_in_hub(true)
		_origin_chunk = hub_manager.get_player_origin_chunk()
		print("[TradingHub] Origin chunk: %d" % _origin_chunk)
	else:
		print("[TradingHub] WARNING: TradingHubManager not found!")

	# Spawn the local player at the appropriate entry point
	print("[TradingHub] Spawning local player...")
	_spawn_local_player()

	# Setup camera limits
	print("[TradingHub] Setting up camera...")
	_setup_camera()

	# Start ambient audio
	print("[TradingHub] Setting up ambient audio...")
	_setup_ambient_audio()

	# Restore UI autoloads
	print("[TradingHub] Restoring UI autoloads...")
	_restore_ui_autoloads()

	# Start fire flicker animation
	print("[TradingHub] Starting fire animation...")
	_start_fire_animation()

	print("[TradingHub] ===== READY COMPLETE =====")
	print("=" .repeat(60))

func _spawn_local_player() -> void:
	local_player = _get_player_scene().instantiate()

	# Spawn at entry point based on origin chunk
	match _origin_chunk:
		-1:
			local_player.position = ENTRY_SPAWN_WEST
			print("[TradingHub] Player entered from West (chunk -1)")
		0:
			local_player.position = ENTRY_SPAWN_SOUTH
			print("[TradingHub] Player entered from South/Center (chunk 0)")
		1:
			local_player.position = ENTRY_SPAWN_EAST
			print("[TradingHub] Player entered from East (chunk +1)")
		_:
			local_player.position = ENTRY_SPAWN_SOUTH
			print("[TradingHub] Player entered from unknown chunk, defaulting to South")

	# Add to scene - ensure Players node exists
	var players_node = get_node_or_null("Players")
	if players_node:
		players_node.add_child(local_player)
	else:
		# Fallback: add directly to scene
		push_warning("[TradingHub] Players node not found, adding player directly to scene")
		add_child(local_player)

	# Add to player group
	local_player.add_to_group("player")

	print("[TradingHub] Player spawned at %s" % local_player.position)

func _setup_camera() -> void:
	# Wait for player camera to be ready
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame for safety

	# Find any player in the scene (handles both normal spawn and /tp command)
	var player = local_player
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player and is_instance_valid(player):
		var camera = player.get_node_or_null("Camera2D")
		if camera:
			# IMPORTANT: Disable smoothing temporarily to teleport camera instantly
			var original_smoothing = camera.position_smoothing_enabled
			camera.position_smoothing_enabled = false

			# Camera limits based on actual hub layout
			# X: from west corridor (-2600) to east corridor (+2600)
			# Y: from Zone 2 portal (-4300) to south entries (+2300)
			camera.limit_left = -2700
			camera.limit_right = 2700
			camera.limit_top = -4400
			camera.limit_bottom = 2400

			# Force camera to snap to player position immediately
			camera.reset_smoothing()
			camera.force_update_scroll()

			# Also explicitly set camera global position to player
			camera.global_position = player.global_position

			print("[TradingHub] Camera limits set: L=%d R=%d T=%d B=%d" % [
				camera.limit_left, camera.limit_right, camera.limit_top, camera.limit_bottom
			])
			print("[TradingHub] Player at: %s, Camera at: %s" % [player.global_position, camera.global_position])

			# Re-enable smoothing after a frame so future movement is smooth
			await get_tree().process_frame
			camera.position_smoothing_enabled = original_smoothing
		else:
			push_warning("[TradingHub] Camera2D not found on player!")
	else:
		push_warning("[TradingHub] No player found for camera setup!")

func _setup_ambient_audio() -> void:
	# Create ambient dripping/echo sounds
	_ambient_audio_player = AudioStreamPlayer.new()
	_ambient_audio_player.volume_db = -15.0
	# TODO: Add actual ambient audio file (cave drips, distant echoes)
	add_child(_ambient_audio_player)

func _restore_ui_autoloads() -> void:
	# Restore any hidden UI autoloads (like inventory, etc)
	var autoloads = ["InventoryUI", "CharacterSheet", "QuestUI"]
	for autoload_name in autoloads:
		var autoload = get_node_or_null("/root/" + autoload_name)
		if autoload and autoload is CanvasLayer:
			autoload.visible = true

func _start_fire_animation() -> void:
	"""Animate the central fire pit light"""
	var fire_light = $Lighting/CentralFirePit if has_node("Lighting/CentralFirePit") else null
	if fire_light:
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(fire_light, "energy", 1.7, 0.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(fire_light, "energy", 1.3, 0.3).set_trans(Tween.TRANS_SINE)
		tween.tween_property(fire_light, "energy", 1.6, 0.4).set_trans(Tween.TRANS_SINE)
		tween.tween_property(fire_light, "energy", 1.4, 0.6).set_trans(Tween.TRANS_SINE)

var _frame_count: int = 0  # Track frames since spawn

func _process(_delta: float) -> void:
	_frame_count += 1

	# Wait a few frames before checking exits (let player settle)
	if _frame_count < 10:
		return

	# Check for exit triggers
	if local_player and is_instance_valid(local_player):
		_check_exit_zones()

func _check_exit_zones() -> void:
	var pos = local_player.position

	# Debug: print position every 60 frames
	if _frame_count % 60 == 0:
		print("[TradingHub] Player pos: (%.1f, %.1f)" % [pos.x, pos.y])

	# South exit (center corridor) - return to Zone 1 chunk 0
	# Player must be in center corridor (X near 0) and walk past Y threshold
	if pos.y > EXIT_ZONE1_SOUTH_Y and abs(pos.x) < 250:
		print("[TradingHub] EXIT TRIGGERED: South corridor (Y: %.1f > %.1f, X: %.1f)" % [pos.y, EXIT_ZONE1_SOUTH_Y, pos.x])
		_exit_to_zone1(0)
		return

	# West exit (west corridor) - return to Zone 1 chunk -1
	# Player must be in west corridor (X around -2200) and walk past Y threshold
	if pos.y > EXIT_ZONE1_WEST_Y and pos.x < -1900 and pos.x > -2500:
		_exit_to_zone1(-1)
		return

	# East exit (east corridor) - return to Zone 1 chunk +1
	# Player must be in east corridor (X around +2200) and walk past Y threshold
	if pos.y > EXIT_ZONE1_EAST_Y and pos.x > 1900 and pos.x < 2500:
		_exit_to_zone1(1)
		return

	# North exit - go to Zone 2 (placeholder)
	if pos.y < EXIT_ZONE2_NORTH_Y and abs(pos.x) < 250:
		_exit_to_zone2()
		return

func _exit_to_zone1(chunk_id: int) -> void:
	print("[TradingHub] Player exiting to Zone 1 (chunk %d)" % chunk_id)

	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_in_hub(false)
		hub_manager.set_player_origin_chunk(chunk_id)  # Remember which exit they used

	# Fade and transition
	var tween = create_tween()
	var canvas_mod = $CanvasModulate
	if canvas_mod:
		tween.tween_property(canvas_mod, "color", Color(0, 0, 0, 1), 0.5)
		tween.tween_callback(_load_zone1)
	else:
		_load_zone1()

func _load_zone1() -> void:
	# Use TradingHubManager for scene transition (same pattern as tunnel entry)
	var hub_manager = get_node_or_null("/root/TradingHubManager")
	if hub_manager:
		hub_manager.transition_to_zone1()
	else:
		# Fallback to direct call if manager not available
		get_tree().change_scene_to_file("res://main.tscn")

func _exit_to_zone2() -> void:
	print("[TradingHub] Player attempting to exit to Zone 2 (not implemented)")
	# Push player back - Zone 2 not implemented yet
	if local_player and is_instance_valid(local_player):
		local_player.position.y = EXIT_ZONE2_NORTH_Y + 100
		_spawn_floating_text("The Depths await... (Coming Soon)", Color(0.5, 0.7, 0.9))

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
