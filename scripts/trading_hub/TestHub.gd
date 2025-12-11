# TestHub.gd - Incremental test scene for debugging
extends Node2D

# Layer 2: Player spawning
var PLAYER_SCENE: PackedScene = null
var local_player: Node = null

# Layer 3: Hub manager integration
var _origin_chunk: int = 0
var _frame_count: int = 0

# Layout constants - matching the expanded tunnel system
# Central hub at Y=0 (radius ~2600), winding passages extend to Y=7000
# South corridor is direct, East/West passages are winding and 50% longer
const EXIT_SOUTH_Y: float = 6800.0  # Exit when near end of south corridor
const EXIT_WEST_X: float = -5300.0  # Exit when near west end of winding passage
const EXIT_EAST_X: float = 5300.0   # Exit when near east end of winding passage

# Zone 2 preview area: Y=-2800 to Y=-8000 (massive 16,000 wide area)
# The cliff wall with cave mouth is at Y=-2000 to Y=-2800
# Deep Zone 2 transition: Y < -7800 (blocked until full Zone 2 implemented)
const ZONE2_CLIFF_Y: float = -2000.0        # Where cliff wall begins
const ZONE2_GRASS_Y: float = -2800.0        # Where grass starts (above cliff)
const ZONE2_DEEP_BLOCKED: float = -7800.0   # Blocked transition to full Zone 2
const ZONE2_WIDTH: float = 8000.0           # Half-width (-8000 to 8000)

# Zoom limits - restricted in cave, open in Zone 2
const CAVE_ZOOM_MIN: float = 1.0            # Can't zoom out much in cave (tight corridors)
const CAVE_ZOOM_MAX: float = 2.0            # Normal zoom in
const ZONE2_ZOOM_MIN: float = 0.5           # Can zoom out more in open Zone 2
const ZONE2_ZOOM_MAX: float = 2.0           # Normal zoom in
var _player_in_zone2: bool = false          # Track zone for zoom changes
var _original_zoom_min: float = 0.75        # Store original to restore on exit

# Spawn positions for each entry corridor
const SPAWN_SOUTH: Vector2 = Vector2(0, 200)          # Near hub hearth
const SPAWN_WEST: Vector2 = Vector2(-200, 0)          # Near hub hearth (west side)
const SPAWN_EAST: Vector2 = Vector2(200, 0)           # Near hub hearth (east side)

func _get_player_scene() -> PackedScene:
	if PLAYER_SCENE == null:
		print("[TestHub] Loading player scene...")
		PLAYER_SCENE = load("res://scenes/player/player.tscn")
		print("[TestHub] Player scene loaded: %s" % str(PLAYER_SCENE))
	return PLAYER_SCENE

func _ready() -> void:
	print("=" .repeat(60))
	print("[TestHub] ===== TEST SCENE LOADED =====")
	print("[TestHub] Layer 3: Hub manager + exit detection")
	print("=" .repeat(60))

	# Layer 3: Integrate with TradingHubManager
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_in_hub(true)
		_origin_chunk = hub_manager.get_player_origin_chunk()
		print("[TestHub] Origin chunk: %d" % _origin_chunk)
	else:
		print("[TestHub] WARNING: TradingHubManager not found!")

	# Apply ground shaders to walkable areas
	_apply_ground_shaders()

	# Spawn central hearth
	_spawn_hearth()

	# Wall torches disabled during layout testing
	# _spawn_wall_torches()

	# Spawn player
	_spawn_player()

func _spawn_player() -> void:
	var player_scene = _get_player_scene()
	if not player_scene:
		push_error("[TestHub] Failed to load player scene!")
		return

	print("[TestHub] Instantiating player...")
	local_player = player_scene.instantiate()

	# Spawn based on which chunk they entered from
	match _origin_chunk:
		-1:
			local_player.position = SPAWN_WEST
			print("[TestHub] Player entered from West (chunk -1)")
		1:
			local_player.position = SPAWN_EAST
			print("[TestHub] Player entered from East (chunk +1)")
		_:
			local_player.position = SPAWN_SOUTH
			print("[TestHub] Player entered from South (chunk 0)")

	add_child(local_player)
	local_player.add_to_group("player")

	# Restore preserved player state (health, etc.)
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		if hub_manager.has_preserved_state():
			hub_manager.restore_player_state(local_player)

	print("[TestHub] Player spawned at %s" % local_player.position)
	print("[TestHub] Walk NORTH to reach the hub, SOUTH to exit")

	# Setup camera limits and snap to player
	_setup_camera()

	# Set initial zoom limits (player starts in cave)
	_set_zoom_limits(CAVE_ZOOM_MIN, CAVE_ZOOM_MAX)
	print("[TestHub] Initial zoom set to cave mode (%.1fx - %.1fx)" % [CAVE_ZOOM_MIN, CAVE_ZOOM_MAX])

func _setup_camera() -> void:
	"""Configure camera limits for the hub and snap camera to player position"""
	await get_tree().process_frame
	await get_tree().process_frame

	var player = local_player
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	if player and is_instance_valid(player):
		var camera = player.get_node_or_null("Camera2D")
		if camera:
			# Disable smoothing temporarily to teleport camera instantly
			var original_smoothing = camera.position_smoothing_enabled
			camera.position_smoothing_enabled = false

			# Camera limits for the full hub + Zone 2 preview layout:
			# X: -8500 to +8500 (Zone 2 is 16,000 wide, cave extends to ±5500)
			# Y: -8500 (Zone 2 deep) to +7000 (south corridor end)
			camera.limit_left = -8500
			camera.limit_right = 8500
			camera.limit_top = -8500
			camera.limit_bottom = 7000

			# Force camera to snap to player position immediately
			camera.reset_smoothing()
			camera.force_update_scroll()
			camera.global_position = player.global_position

			print("[TestHub] Camera limits set: L=%d R=%d T=%d B=%d" % [
				camera.limit_left, camera.limit_right, camera.limit_top, camera.limit_bottom
			])
			print("[TestHub] Player at: %s, Camera at: %s" % [player.global_position, camera.global_position])

			# Re-enable smoothing after a frame
			await get_tree().process_frame
			camera.position_smoothing_enabled = original_smoothing
		else:
			push_warning("[TestHub] Camera2D not found on player!")
	else:
		push_warning("[TestHub] No player found for camera setup!")

func _process(_delta: float) -> void:
	_frame_count += 1

	# Wait a few frames before checking exits
	if _frame_count < 10:
		return

	if local_player and is_instance_valid(local_player):
		_check_exit()
		_update_zoom_limits()

func _check_exit() -> void:
	var pos = local_player.position

	# South corridor exit (chunk 0) - direct path down the middle
	if pos.y > EXIT_SOUTH_Y and abs(pos.x) < 600:
		print("[TestHub] EXIT: South corridor -> Zone 1 chunk 0")
		_exit_to_zone1(0)
		return

	# West winding passage exit (chunk -1) - at far west end
	# Passage winds from hub (~X=-2600) to exit (~X=-5300)
	if pos.x < EXIT_WEST_X and pos.y > 2000 and pos.y < 3500:
		print("[TestHub] EXIT: West passage -> Zone 1 chunk -1")
		_exit_to_zone1(-1)
		return

	# East winding passage exit (chunk +1) - at far east end
	# Passage winds from hub (~X=+2600) to exit (~X=+5300)
	if pos.x > EXIT_EAST_X and pos.y > 2000 and pos.y < 3500:
		print("[TestHub] EXIT: East passage -> Zone 1 chunk +1")
		_exit_to_zone1(1)
		return

	# Zone 2 deep boundary check - block full Zone 2 transition
	if pos.y < ZONE2_DEEP_BLOCKED:
		print("[TestHub] Full Zone 2 not yet implemented!")
		local_player.position.y = ZONE2_DEEP_BLOCKED + 50  # Push back

	# Zone 2 preview area boundaries (massive 16,000 wide area)
	if pos.y < ZONE2_GRASS_Y:
		# In Zone 2 preview - X limit is ±8000
		if abs(pos.x) > ZONE2_WIDTH:
			local_player.position.x = sign(pos.x) * ZONE2_WIDTH

	# Cave mouth check - only allow through the opening in the cliff
	elif pos.y < ZONE2_CLIFF_Y and pos.y > ZONE2_GRASS_Y:
		# In the cliff wall zone - only the mouth opening allows passage
		# Mouth is roughly X: -1800 to 1800
		if abs(pos.x) > 1700:
			# Push back into hub or into Zone 2 depending on which side they're on
			if pos.y > -2400:
				local_player.position.y = ZONE2_CLIFF_Y + 50  # Push back to hub
			else:
				local_player.position.y = ZONE2_GRASS_Y - 50  # Push into Zone 2

func _exit_to_zone1(chunk_id: int) -> void:
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_origin_chunk(chunk_id)  # Set which chunk to spawn at
		hub_manager.save_player_state(local_player)  # Preserve health, etc.
		hub_manager.set_player_in_hub(false)
		hub_manager.transition_to_zone1()
	else:
		get_tree().change_scene_to_file("res://main.tscn")

func _exit_tree() -> void:
	# Restore original zoom limits when leaving hub
	if local_player and is_instance_valid(local_player):
		_restore_zoom_limits()
	if has_node("/root/TradingHubManager"):
		get_node("/root/TradingHubManager").set_player_in_hub(false)

func _update_zoom_limits() -> void:
	"""Update camera zoom limits based on whether player is in cave or Zone 2"""
	var pos = local_player.position
	var in_zone2 = pos.y < ZONE2_GRASS_Y

	# Only update if zone changed
	if in_zone2 != _player_in_zone2:
		_player_in_zone2 = in_zone2

		if in_zone2:
			# Entering Zone 2 - allow more zoom out
			_set_zoom_limits(ZONE2_ZOOM_MIN, ZONE2_ZOOM_MAX)
			print("[TestHub] Entered Zone 2 preview - zoom unlocked (%.1fx - %.1fx)" % [ZONE2_ZOOM_MIN, ZONE2_ZOOM_MAX])
		else:
			# Entering cave - restrict zoom
			_set_zoom_limits(CAVE_ZOOM_MIN, CAVE_ZOOM_MAX)
			print("[TestHub] Entered cave - zoom restricted (%.1fx - %.1fx)" % [CAVE_ZOOM_MIN, CAVE_ZOOM_MAX])

func _set_zoom_limits(min_zoom: float, max_zoom: float) -> void:
	"""Set player camera zoom limits"""
	if not local_player or not is_instance_valid(local_player):
		return

	# Store original on first call
	if _original_zoom_min == 0.75 and "zoom_min" in local_player:
		_original_zoom_min = local_player.zoom_min

	# Set new limits
	if "zoom_min" in local_player:
		local_player.zoom_min = min_zoom
	if "zoom_max" in local_player:
		local_player.zoom_max = max_zoom

	# Clamp current zoom if outside new limits
	if "target_zoom" in local_player:
		local_player.target_zoom = clamp(local_player.target_zoom, min_zoom, max_zoom)
		var camera = local_player.get_node_or_null("Camera2D")
		if camera:
			camera.zoom = Vector2(local_player.target_zoom, local_player.target_zoom)

func _restore_zoom_limits() -> void:
	"""Restore original zoom limits when leaving hub"""
	if not local_player or not is_instance_valid(local_player):
		return

	if "zoom_min" in local_player:
		local_player.zoom_min = _original_zoom_min
	if "zoom_max" in local_player:
		local_player.zoom_max = 2.0  # Default max

func _spawn_hearth() -> void:
	"""Spawn the central coal hearth"""
	var hearth = HubHearth.new()
	hearth.position = Vector2(0, 0)  # Center of hub
	hearth.name = "CentralHearth"
	add_child(hearth)
	print("[TestHub] Spawned central hearth")

func _spawn_wall_torches() -> void:
	"""Spawn wall-mounted torches on the natural jagged cave wall edges

	Torches mount exactly on the collision line between walkable floor and walls.
	facing_left=true means torch faces LEFT (mounted on RIGHT/EAST wall)
	facing_left=false means torch faces RIGHT (mounted on LEFT/WEST wall)
	"""
	var torch_container = Node2D.new()
	torch_container.name = "WallTorches"
	add_child(torch_container)

	# === NORTH WALL - jagged cave mouth edge ===
	# Points from WallNorth polygon inner edge
	_spawn_torch(torch_container, Vector2(-2100, -1850), false)
	_spawn_torch(torch_container, Vector2(-1500, -1650), false)
	_spawn_torch(torch_container, Vector2(-700, -1550), false)
	_spawn_torch(torch_container, Vector2(100, -1500), false)
	_spawn_torch(torch_container, Vector2(900, -1600), true)
	_spawn_torch(torch_container, Vector2(1700, -1700), true)
	_spawn_torch(torch_container, Vector2(2300, -1850), true)

	# === WEST WALL - Hub section (jagged) ===
	# Points from WallWest polygon inner edge
	_spawn_torch(torch_container, Vector2(-2650, -1500), false)
	_spawn_torch(torch_container, Vector2(-2700, -900), false)
	_spawn_torch(torch_container, Vector2(-2750, -300), false)
	_spawn_torch(torch_container, Vector2(-2700, 300), false)
	_spawn_torch(torch_container, Vector2(-2650, 900), false)

	# === EAST WALL - Hub section (jagged) ===
	# Points from WallEast polygon inner edge
	_spawn_torch(torch_container, Vector2(2650, -1500), true)
	_spawn_torch(torch_container, Vector2(2700, -900), true)
	_spawn_torch(torch_container, Vector2(2750, -300), true)
	_spawn_torch(torch_container, Vector2(2700, 300), true)
	_spawn_torch(torch_container, Vector2(2650, 900), true)

	# === SOUTH CORRIDOR - jagged edges ===
	# Left wall (SouthCorridorWest) ~X=-350 to -500
	_spawn_torch(torch_container, Vector2(-500, 2400), false)
	_spawn_torch(torch_container, Vector2(-450, 3300), false)
	_spawn_torch(torch_container, Vector2(-400, 4200), false)
	_spawn_torch(torch_container, Vector2(-450, 5100), false)
	_spawn_torch(torch_container, Vector2(-400, 6000), false)
	_spawn_torch(torch_container, Vector2(-400, 6900), false)

	# Right wall (SouthCorridorEast) ~X=+350 to +500
	_spawn_torch(torch_container, Vector2(500, 2700), true)
	_spawn_torch(torch_container, Vector2(450, 3600), true)
	_spawn_torch(torch_container, Vector2(400, 4500), true)
	_spawn_torch(torch_container, Vector2(450, 5400), true)
	_spawn_torch(torch_container, Vector2(400, 6300), true)
	_spawn_torch(torch_container, Vector2(400, 7200), true)

	# === WEST WINDING PASSAGE - natural S-curve ===
	# Outer wall (WallWest) - follows the winding curve from hub to exit
	_spawn_torch(torch_container, Vector2(-2100, 1550), false)
	_spawn_torch(torch_container, Vector2(-1600, 1900), false)
	_spawn_torch(torch_container, Vector2(-1550, 2400), false)
	_spawn_torch(torch_container, Vector2(-2000, 2850), false)
	_spawn_torch(torch_container, Vector2(-2750, 3350), false)
	_spawn_torch(torch_container, Vector2(-3550, 3800), false)
	_spawn_torch(torch_container, Vector2(-4350, 4250), false)
	_spawn_torch(torch_container, Vector2(-5100, 4700), false)
	_spawn_torch(torch_container, Vector2(-5750, 5150), false)

	# Inner wall (PassageInnerWest) - the dividing wall
	_spawn_torch(torch_container, Vector2(-1550, 2150), true)
	_spawn_torch(torch_container, Vector2(-1950, 2550), true)
	_spawn_torch(torch_container, Vector2(-2650, 3050), true)
	_spawn_torch(torch_container, Vector2(-3400, 3500), true)
	_spawn_torch(torch_container, Vector2(-4150, 3950), true)
	_spawn_torch(torch_container, Vector2(-4900, 4400), true)
	_spawn_torch(torch_container, Vector2(-5650, 4850), true)

	# === EAST WINDING PASSAGE - natural S-curve (mirror) ===
	# Outer wall (WallEast) - follows the winding curve from hub to exit
	_spawn_torch(torch_container, Vector2(2100, 1550), true)
	_spawn_torch(torch_container, Vector2(1600, 1900), true)
	_spawn_torch(torch_container, Vector2(1550, 2400), true)
	_spawn_torch(torch_container, Vector2(2000, 2850), true)
	_spawn_torch(torch_container, Vector2(2750, 3350), true)
	_spawn_torch(torch_container, Vector2(3550, 3800), true)
	_spawn_torch(torch_container, Vector2(4350, 4250), true)
	_spawn_torch(torch_container, Vector2(5100, 4700), true)
	_spawn_torch(torch_container, Vector2(5750, 5150), true)

	# Inner wall (PassageInnerEast) - the dividing wall
	_spawn_torch(torch_container, Vector2(1550, 2150), false)
	_spawn_torch(torch_container, Vector2(1950, 2550), false)
	_spawn_torch(torch_container, Vector2(2650, 3050), false)
	_spawn_torch(torch_container, Vector2(3400, 3500), false)
	_spawn_torch(torch_container, Vector2(4150, 3950), false)
	_spawn_torch(torch_container, Vector2(4900, 4400), false)
	_spawn_torch(torch_container, Vector2(5650, 4850), false)

	print("[TestHub] Spawned %d wall torches" % torch_container.get_child_count())

func _spawn_torch(container: Node2D, pos: Vector2, facing_left: bool) -> void:
	"""Spawn a single wall torch at the given position"""
	var torch = WallTorch.new()
	torch.position = pos
	torch.facing_left = facing_left
	container.add_child(torch)

func _apply_ground_shaders() -> void:
	"""Ground shaders are now applied via the scene file (ColorRect with ShaderMaterial)"""
	print("[TestHub] Ground shader applied via scene (ColorRect CaveFloor)")
