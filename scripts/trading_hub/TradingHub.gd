# TradingHub.gd - Incremental test scene for debugging
extends Node2D

# Layer 2: Player spawning
var PLAYER_SCENE: PackedScene = null
var local_player: Node = null

# Layer 3: Hub manager integration
var _origin_chunk: int = 0
var _frame_count: int = 0

# Time of day / lighting sync
var _canvas_modulate: CanvasModulate = null
var _north_entrance_light: PointLight2D = null
var _zone2_sunlight: PointLight2D = null
const CAVE_DARKNESS_FACTOR: float = 0.6  # Cave is 60% as bright as outside

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

# Fire pit ambient audio
var _fire_ambient_player: AudioStreamPlayer2D = null

# Spawn positions for each entry corridor
const SPAWN_SOUTH: Vector2 = Vector2(0, 200)          # Near hub hearth
const SPAWN_WEST: Vector2 = Vector2(-200, 0)          # Near hub hearth (west side)
const SPAWN_EAST: Vector2 = Vector2(200, 0)           # Near hub hearth (east side)

func _get_player_scene() -> PackedScene:
	if PLAYER_SCENE == null:
		print("[TradingHub] Loading player scene...")
		PLAYER_SCENE = load("res://scenes/player/player.tscn")
		print("[TradingHub] Player scene loaded: %s" % str(PLAYER_SCENE))
	return PLAYER_SCENE

func _ready() -> void:
	print("=" .repeat(60))
	print("[TradingHub] ===== TEST SCENE LOADED =====")
	print("[TradingHub] Layer 3: Hub manager + exit detection")
	print("=" .repeat(60))

	# Layer 3: Integrate with TradingHubManager
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_in_hub(true)
		_origin_chunk = hub_manager.get_player_origin_chunk()
		print("[TradingHub] Origin chunk: %d" % _origin_chunk)
	else:
		print("[TradingHub] WARNING: TradingHubManager not found!")

	# Setup time-synced lighting
	_setup_time_lighting()

	# Add performance profiler (press F3 to toggle)
	var profiler_scene = load("res://scenes/ui/performance_profiler.tscn")
	if profiler_scene:
		var profiler = profiler_scene.instantiate()
		add_child(profiler)
		print("[TradingHub] Performance profiler added (F3 to toggle)")

	# Apply ground shaders to walkable areas
	_apply_ground_shaders()

	# Spawn central hearth
	_spawn_hearth()

	# Spawn wall torches along cave perimeter
	_spawn_wall_torches()

	# Create north entrance light bleed (daylight from Zone 2)
	_create_north_entrance_light()

	# Create Zone 2 outdoor sunlight (full outdoor lighting for grass area)
	_create_zone2_sunlight()

	# Spawn grassland details (grass tufts, flowers, pebbles)
	_spawn_grassland_details()

	# Spawn Zone 2 trees (dense forest coverage)
	_spawn_zone2_trees()

	# Create horizon atmosphere (sky, distant hills, fog)
	_create_horizon_atmosphere()

	# Soften hard edges (cliff debris, shadows, transitions)
	_create_edge_softening(PackedVector2Array())

	# Spawn player
	_spawn_player()

	# Start Trading Hub music
	_start_hub_music()

	# Setup fire pit ambient audio
	_setup_fire_ambient()

func _start_hub_music() -> void:
	"""Start playing Trading Hub ambient music"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Stop any game music first
		if sound_manager.has_method("stop_game_music"):
			sound_manager.stop_game_music()
		# Start hub music
		if sound_manager.has_method("play_trading_hub_music"):
			sound_manager.play_trading_hub_music(-12.0)
			print("[TradingHub] 🎵 Started Trading Hub music")
		else:
			push_warning("[TradingHub] SoundManager missing play_trading_hub_music method")
	else:
		push_warning("[TradingHub] SoundManager not found")

func _setup_fire_ambient() -> void:
	"""Setup spatial audio for fire pit area (covers hearth and forge)"""
	var fire_sound = load("res://assets/audio/sfx/ambient/fire_pit_ambient.mp3")
	if not fire_sound:
		push_warning("[TradingHub] Could not load fire_pit_ambient.mp3")
		return

	# Create spatial audio player
	_fire_ambient_player = AudioStreamPlayer2D.new()
	_fire_ambient_player.name = "FireAmbientAudio"
	_fire_ambient_player.stream = fire_sound

	# Position between hearth (0,0) and forge (-2,-406) to cover both
	_fire_ambient_player.position = Vector2(0, -150)

	# Spatial audio settings
	_fire_ambient_player.max_distance = 800.0  # Audible within 800px
	_fire_ambient_player.attenuation = 1.5  # Gradual falloff
	_fire_ambient_player.volume_db = -6.0  # Comfortable ambient level
	_fire_ambient_player.autoplay = true

	# Enable looping for MP3
	if fire_sound is AudioStreamMP3:
		(fire_sound as AudioStreamMP3).loop = true

	add_child(_fire_ambient_player)
	_fire_ambient_player.play()
	print("[TradingHub] 🔥 Fire pit ambient audio started")

func _spawn_player() -> void:
	var player_scene = _get_player_scene()
	if not player_scene:
		push_error("[TradingHub] Failed to load player scene!")
		return

	print("[TradingHub] Instantiating player...")
	local_player = player_scene.instantiate()

	# Spawn based on which chunk they entered from
	match _origin_chunk:
		-1:
			local_player.position = SPAWN_WEST
			print("[TradingHub] Player entered from West (chunk -1)")
		1:
			local_player.position = SPAWN_EAST
			print("[TradingHub] Player entered from East (chunk +1)")
		_:
			local_player.position = SPAWN_SOUTH
			print("[TradingHub] Player entered from South (chunk 0)")

	add_child(local_player)
	local_player.add_to_group("player")

	# Restore preserved player state (health, etc.)
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		if hub_manager.has_preserved_state():
			hub_manager.restore_player_state(local_player)

	print("[TradingHub] Player spawned at %s" % local_player.position)
	print("[TradingHub] Walk NORTH to reach the hub, SOUTH to exit")

	# Setup camera limits and snap to player
	_setup_camera()

	# Set initial zoom limits (player starts in cave)
	_set_zoom_limits(CAVE_ZOOM_MIN, CAVE_ZOOM_MAX)
	print("[TradingHub] Initial zoom set to cave mode (%.1fx - %.1fx)" % [CAVE_ZOOM_MIN, CAVE_ZOOM_MAX])

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

			print("[TradingHub] Camera limits set: L=%d R=%d T=%d B=%d" % [
				camera.limit_left, camera.limit_right, camera.limit_top, camera.limit_bottom
			])
			print("[TradingHub] Player at: %s, Camera at: %s" % [player.global_position, camera.global_position])

			# Re-enable smoothing after a frame
			await get_tree().process_frame
			camera.position_smoothing_enabled = original_smoothing
		else:
			push_warning("[TradingHub] Camera2D not found on player!")
	else:
		push_warning("[TradingHub] No player found for camera setup!")

func _process(delta: float) -> void:
	_frame_count += 1

	# Wait a few frames before checking exits
	if _frame_count < 10:
		return

	if local_player and is_instance_valid(local_player):
		_check_exit()
		_update_zoom_limits()

		# Update tree proximity loading (throttled)
		_tree_proximity_timer += delta
		if _tree_proximity_timer >= TREE_PROXIMITY_CHECK_INTERVAL:
			_tree_proximity_timer = 0.0
			_update_tree_proximity()

func _check_exit() -> void:
	var pos = local_player.position

	# South corridor exit (chunk 0) - direct path down the middle
	if pos.y > EXIT_SOUTH_Y and abs(pos.x) < 600:
		print("[TradingHub] EXIT: South corridor -> Zone 1 chunk 0")
		_exit_to_zone1(0)
		return

	# West winding passage exit (chunk -1) - at far west end
	# Passage winds from hub (~X=-2600) to exit (~X=-5300)
	if pos.x < EXIT_WEST_X and pos.y > 2000 and pos.y < 3500:
		print("[TradingHub] EXIT: West passage -> Zone 1 chunk -1")
		_exit_to_zone1(-1)
		return

	# East winding passage exit (chunk +1) - at far east end
	# Passage winds from hub (~X=+2600) to exit (~X=+5300)
	if pos.x > EXIT_EAST_X and pos.y > 2000 and pos.y < 3500:
		print("[TradingHub] EXIT: East passage -> Zone 1 chunk +1")
		_exit_to_zone1(1)
		return

	# Zone 2 deep boundary check - block full Zone 2 transition
	if pos.y < ZONE2_DEEP_BLOCKED:
		print("[TradingHub] Full Zone 2 not yet implemented!")
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
			print("[TradingHub] Entered Zone 2 preview - zoom unlocked (%.1fx - %.1fx)" % [ZONE2_ZOOM_MIN, ZONE2_ZOOM_MAX])
		else:
			# Entering cave - restrict zoom
			_set_zoom_limits(CAVE_ZOOM_MIN, CAVE_ZOOM_MAX)
			print("[TradingHub] Entered cave - zoom restricted (%.1fx - %.1fx)" % [CAVE_ZOOM_MIN, CAVE_ZOOM_MAX])

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
	print("[TradingHub] Spawned central hearth")

func _spawn_wall_torches() -> void:
	"""Spawn wall-mounted torches on the cave wall edges

	Torches are staggered (alternating sides) and spaced ~1000px apart.
	facing_left=true means torch faces LEFT (mounted on RIGHT/EAST wall)
	facing_left=false means torch faces RIGHT (mounted on LEFT/WEST wall)
	All positions match exact collision polygon vertices from TradingHub.tscn
	"""
	var torch_container = Node2D.new()
	torch_container.name = "WallTorches"
	add_child(torch_container)

	# === CAVE MOUTH AREA (near Zone 2 exit) ===
	# Polygon vertices: (-1050, -3600), (1050, -3600)
	_spawn_torch(torch_container, Vector2(-1050, -3600), false)
	_spawn_torch(torch_container, Vector2(1100, -3200), true)

	# === HUB NORTH WALL ===
	# Polygon vertices: (-1400, -2200), (1400, -2200)
	_spawn_torch(torch_container, Vector2(-1400, -2200), false)
	_spawn_torch(torch_container, Vector2(1600, -2000), true)

	# === HUB WEST WALL (9 o'clock berth) ===
	# Polygon vertices: (-2850, -1350), (-4400, -200), (-4250, 1000)
	_spawn_torch(torch_container, Vector2(-2850, -1350), false)
	_spawn_torch(torch_container, Vector2(-4400, -200), false)
	_spawn_torch(torch_container, Vector2(-4250, 1000), false)

	# === HUB EAST WALL (3 o'clock berth) ===
	# Mirrored from west wall
	_spawn_torch(torch_container, Vector2(2850, -1350), true)
	_spawn_torch(torch_container, Vector2(4400, -200), true)
	_spawn_torch(torch_container, Vector2(4250, 1000), true)

	# === SOUTH CORRIDOR ENTRANCE (framing the opening) ===
	_spawn_torch(torch_container, Vector2(-1647, 2035), true, 90.0)   # Left pillar, base rotated 90°
	_spawn_torch(torch_container, Vector2(1800, 2016), false)         # Right pillar, faces right toward hub

	# === SOUTH CORRIDOR (middle exit) ===
	# Left wall - exact polygon vertices:
	# (-600, 2400), (-520, 3900), (-540, 5400), (-550, 6900)
	_spawn_torch(torch_container, Vector2(-600, 2400), false)
	_spawn_torch(torch_container, Vector2(-520, 3900), false)
	_spawn_torch(torch_container, Vector2(-540, 5400), false)
	_spawn_torch(torch_container, Vector2(-550, 6900), false)

	# Right wall - exact polygon vertices (staggered Y):
	# (480, 3150), (500, 4650), (470, 6150)
	_spawn_torch(torch_container, Vector2(480, 3150), true)
	_spawn_torch(torch_container, Vector2(500, 4650), true)
	_spawn_torch(torch_container, Vector2(470, 6150), true)

	# === OUTER PERIMETER (SW passage outer wall) ===
	# Polygon vertices: (-4300, 2500), (-5050, 4300), (-5250, 6100)
	_spawn_torch(torch_container, Vector2(-4300, 2500), false)
	_spawn_torch(torch_container, Vector2(-5050, 4300), false)
	_spawn_torch(torch_container, Vector2(-5250, 6100), false)

	# === OUTER PERIMETER (SE passage outer wall) ===
	# Mirrored polygon vertices (staggered Y)
	_spawn_torch(torch_container, Vector2(4450, 2800), true)
	_spawn_torch(torch_container, Vector2(5150, 4600), true)
	_spawn_torch(torch_container, Vector2(5200, 6700), true)

	# === INNER PASSAGE WALLS (between corridors) ===
	# SW inner wall - polygon vertices: (-2850, 2400), (-3650, 4200), (-4200, 6000)
	_spawn_torch(torch_container, Vector2(-2850, 2400), true)
	_spawn_torch(torch_container, Vector2(-3650, 4200), true)
	_spawn_torch(torch_container, Vector2(-4200, 6000), true)

	# SE inner wall - mirrored (staggered Y)
	_spawn_torch(torch_container, Vector2(3100, 3000), false)
	_spawn_torch(torch_container, Vector2(3950, 5100), false)
	_spawn_torch(torch_container, Vector2(4200, 6900), false)

	print("[TradingHub] Spawned %d wall torches" % torch_container.get_child_count())

func _spawn_torch(container: Node2D, pos: Vector2, facing_left: bool, base_rotation: float = 0.0) -> void:
	"""Spawn a single wall torch at the given position"""
	var torch = WallTorch.new()
	torch.position = pos
	torch.facing_left = facing_left
	torch.base_rotation_deg = base_rotation  # Rotates mount only, flames stay upright
	container.add_child(torch)

func _apply_ground_shaders() -> void:
	"""Ground shaders are now applied via the scene file (ColorRect with ShaderMaterial)"""
	print("[TradingHub] Ground shader applied via scene (ColorRect CaveFloor)")

# ========================================
# TIME OF DAY LIGHTING SYSTEM
# ========================================

func _setup_time_lighting() -> void:
	"""Connect to TimeManager for day/night sync with cave dampening"""
	_canvas_modulate = get_node_or_null("CanvasModulate")

	if _canvas_modulate and has_node("/root/TimeManager"):
		var time_manager = get_node("/root/TimeManager")
		# Don't let TimeManager directly control our CanvasModulate
		# We'll handle it ourselves with cave dampening
		time_manager.time_changed.connect(_on_time_changed)
		# Initialize with current time
		_update_cave_lighting(time_manager.current_time)
		print("[TradingHub] Time sync enabled - cave lighting active")
	else:
		# Fallback to static cave lighting if no TimeManager
		if _canvas_modulate:
			_canvas_modulate.color = Color(0.6, 0.58, 0.55, 1.0)
		print("[TradingHub] TimeManager not found - using static cave lighting")

func _on_time_changed(hour: float) -> void:
	"""Called when TimeManager updates the time"""
	_update_cave_lighting(hour)
	_update_north_entrance_light(hour)
	_update_zone2_sunlight(hour)

func _update_cave_lighting(hour: float) -> void:
	"""Update cave ambient lighting based on time of day with dampening"""
	if not _canvas_modulate:
		return

	# Get the outdoor color from TimeManager constants
	var outdoor_color: Color
	var TimeManagerRef = get_node_or_null("/root/TimeManager")
	if not TimeManagerRef:
		return

	# Calculate outdoor color based on time (matching TimeManager logic)
	const DAWN_START := 5.0
	const DAY_START := 7.0
	const DUSK_START := 18.0
	const NIGHT_START := 20.0

	const DAY_COLOR := Color(1.0, 1.0, 0.98, 1.0)
	const NIGHT_COLOR := Color(0.45, 0.48, 0.6, 1.0)
	const DAWN_COLOR := Color(0.95, 0.8, 0.7, 1.0)
	const DUSK_COLOR := Color(0.9, 0.65, 0.55, 1.0)

	if hour >= NIGHT_START or hour < DAWN_START:
		outdoor_color = NIGHT_COLOR
	elif hour >= DAWN_START and hour < DAY_START:
		var t = (hour - DAWN_START) / (DAY_START - DAWN_START)
		t = t * t * (3.0 - 2.0 * t)  # ease in-out
		outdoor_color = NIGHT_COLOR.lerp(DAY_COLOR, t)
	elif hour >= DAY_START and hour < DUSK_START:
		outdoor_color = DAY_COLOR
	elif hour >= DUSK_START and hour < NIGHT_START:
		var t = (hour - DUSK_START) / (NIGHT_START - DUSK_START)
		t = t * t * (3.0 - 2.0 * t)  # ease in-out
		outdoor_color = DAY_COLOR.lerp(NIGHT_COLOR, t)
	else:
		outdoor_color = DAY_COLOR

	# Apply cave dampening - caves are darker than outside
	# Also add slight warm tint from torches
	var cave_color = Color(
		outdoor_color.r * CAVE_DARKNESS_FACTOR + 0.05,  # Slight torch warmth
		outdoor_color.g * CAVE_DARKNESS_FACTOR + 0.02,
		outdoor_color.b * CAVE_DARKNESS_FACTOR,
		1.0
	)

	_canvas_modulate.color = cave_color

func _create_north_entrance_light() -> void:
	"""Create a light at the north cave entrance that simulates daylight bleed"""
	_north_entrance_light = PointLight2D.new()
	_north_entrance_light.name = "NorthEntranceLight"
	_north_entrance_light.position = Vector2(0, -3800)  # At cave mouth

	# Large soft light for daylight bleed
	_north_entrance_light.energy = 1.5
	_north_entrance_light.texture_scale = 25.0  # Very large coverage

	# Create soft radial texture
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center = Vector2(64, 64)
	var max_radius = 64.0

	for x in range(128):
		for y in range(128):
			var dist = Vector2(x, y).distance_to(center)
			var normalized_dist = clamp(dist / max_radius, 0.0, 1.0)
			# Soft falloff biased downward (into cave)
			var y_bias = 1.0 + (float(y) / 128.0 - 0.5) * 0.5  # Stronger toward bottom
			var alpha = pow(1.0 - normalized_dist, 2.0) * y_bias
			alpha = clamp(alpha, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture = ImageTexture.create_from_image(img)
	_north_entrance_light.texture = texture
	_north_entrance_light.blend_mode = Light2D.BLEND_MODE_ADD

	# Initial color based on time
	var TimeManagerRef = get_node_or_null("/root/TimeManager")
	if TimeManagerRef:
		_update_north_entrance_light(TimeManagerRef.current_time)
	else:
		_north_entrance_light.color = Color(0.9, 0.85, 0.7)  # Warm daylight default
		_north_entrance_light.energy = 1.5

	add_child(_north_entrance_light)
	print("[TradingHub] North entrance daylight bleed created")

func _update_north_entrance_light(hour: float) -> void:
	"""Update north entrance light based on time - bright during day, dim at night"""
	if not _north_entrance_light:
		return

	const DAWN_START := 5.0
	const DAY_START := 7.0
	const DUSK_START := 18.0
	const NIGHT_START := 20.0

	var intensity: float
	var color: Color

	if hour >= NIGHT_START or hour < DAWN_START:
		# Night - very dim moonlight
		intensity = 0.3
		color = Color(0.5, 0.55, 0.7)  # Cool blue moonlight
	elif hour >= DAWN_START and hour < DAY_START:
		# Dawn - warm orange growing brighter
		var t = (hour - DAWN_START) / (DAY_START - DAWN_START)
		intensity = lerp(0.3, 1.8, t)
		color = Color(0.95, 0.75, 0.5).lerp(Color(1.0, 0.95, 0.85), t)
	elif hour >= DAY_START and hour < DUSK_START:
		# Day - full bright warm daylight
		intensity = 1.8
		color = Color(1.0, 0.95, 0.85)  # Warm white daylight
	elif hour >= DUSK_START and hour < NIGHT_START:
		# Dusk - warm orange fading
		var t = (hour - DUSK_START) / (NIGHT_START - DUSK_START)
		intensity = lerp(1.8, 0.3, t)
		color = Color(1.0, 0.95, 0.85).lerp(Color(0.9, 0.6, 0.4), t * 0.7)
	else:
		intensity = 1.5
		color = Color(1.0, 0.95, 0.85)

	_north_entrance_light.energy = intensity
	_north_entrance_light.color = color

func _create_zone2_sunlight() -> void:
	"""Create outdoor sunlight for Zone 2 grass area - matches Zone 1 outdoor lighting
	Light covers outdoor grass and fades before cave entrance (~Y=-4500)."""
	_zone2_sunlight = PointLight2D.new()
	_zone2_sunlight.name = "Zone2Sunlight"
	_zone2_sunlight.position = Vector2(0, -7000)  # Positioned for grass area coverage

	# Wider coverage, extends further south
	_zone2_sunlight.energy = 1.0
	_zone2_sunlight.texture_scale = 220.0  # ~14000px radius - full width coverage

	# Create texture: full coverage north, cutoff at south before cave
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)

	for x in range(128):
		for y in range(128):
			var alpha = 1.0

			# Soft horizontal fade at far edges only
			var x_dist = abs(x - 64) / 64.0
			if x_dist > 0.92:
				alpha *= 1.0 - ((x_dist - 0.92) / 0.08)

			# Cutoff on south side - pulled up to stay out of cave
			var y_normalized = float(y) / 128.0
			if y_normalized > 0.52:
				# Fade from 52% to 68% of texture height
				var fade = (y_normalized - 0.52) / 0.16
				alpha *= 1.0 - clamp(fade, 0.0, 1.0)

			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	var texture = ImageTexture.create_from_image(img)
	_zone2_sunlight.texture = texture
	_zone2_sunlight.blend_mode = Light2D.BLEND_MODE_ADD

	# Initial update based on time
	var TimeManagerRef = get_node_or_null("/root/TimeManager")
	if TimeManagerRef:
		_update_zone2_sunlight(TimeManagerRef.current_time)
	else:
		_zone2_sunlight.color = Color(1.0, 1.0, 0.95)
		_zone2_sunlight.energy = 0.8

	add_child(_zone2_sunlight)
	print("[TradingHub] Zone 2 outdoor sunlight created")

func _update_zone2_sunlight(hour: float) -> void:
	"""Update Zone 2 sunlight based on time - full outdoor lighting matching Zone 1"""
	if not _zone2_sunlight:
		return

	const DAWN_START := 5.0
	const DAY_START := 7.0
	const DUSK_START := 18.0
	const NIGHT_START := 20.0

	var intensity: float
	var color: Color

	if hour >= NIGHT_START or hour < DAWN_START:
		# Night - very dark
		intensity = 0.0
		color = Color(0.4, 0.45, 0.6)  # Cool blue moonlight
	elif hour >= DAWN_START and hour < DAY_START:
		# Dawn - warm sunrise
		var t = (hour - DAWN_START) / (DAY_START - DAWN_START)
		intensity = lerp(0.0, 1.2, t)
		color = Color(1.0, 0.8, 0.5).lerp(Color(1.0, 1.0, 0.95), t)
	elif hour >= DAY_START and hour < DUSK_START:
		# Day - full bright sunlight
		intensity = 1.2
		color = Color(1.0, 1.0, 0.95)  # Warm white sunlight
	elif hour >= DUSK_START and hour < NIGHT_START:
		# Dusk - warm sunset fading
		var t = (hour - DUSK_START) / (NIGHT_START - DUSK_START)
		intensity = lerp(1.2, 0.0, t)
		color = Color(1.0, 1.0, 0.95).lerp(Color(1.0, 0.6, 0.4), t)
	else:
		intensity = 1.2
		color = Color(1.0, 1.0, 0.95)

	_zone2_sunlight.energy = intensity
	_zone2_sunlight.color = color
	print("[TradingHub] Zone2 sunlight updated: hour=%.1f energy=%.2f" % [hour, intensity])

# ========================================
# GRASSLAND DETAIL SYSTEM
# ========================================

func _spawn_grassland_details() -> void:
	"""Spawn procedural grass details - tufts, flowers, pebbles for texture and depth"""
	var grass_container = Node2D.new()
	grass_container.name = "GrassDetails"
	grass_container.z_index = -1  # Above grass base, below cliffs
	add_child(grass_container)

	# Zone 2 grass area: Full extent from Y=-12000 to Y=-4500
	var grass_bounds = Rect2(-7500, -12000, 15000, 7500)

	# Seed RNG for consistent placement
	var rng = RandomNumberGenerator.new()
	rng.seed = 42069  # Consistent seed for deterministic placement

	# === GRASS TUFTS - Dense near cave, sparse in distance ===
	var tuft_count = 200  # Reduced for performance
	for i in range(tuft_count):
		var pos = Vector2(
			rng.randf_range(grass_bounds.position.x, grass_bounds.position.x + grass_bounds.size.x),
			rng.randf_range(grass_bounds.position.y, grass_bounds.position.y + grass_bounds.size.y)
		)
		# Denser near cave mouth (Y > -5500)
		var density_factor = 1.0 - clamp((pos.y + 5500) / -2500, 0.0, 0.7)
		if rng.randf() > density_factor:
			_spawn_grass_tuft(grass_container, pos, rng)

	# === FLOWERS - Scattered colorful accents ===
	var flower_count = 75  # Reduced for performance
	for i in range(flower_count):
		var pos = Vector2(
			rng.randf_range(grass_bounds.position.x, grass_bounds.position.x + grass_bounds.size.x),
			rng.randf_range(grass_bounds.position.y, grass_bounds.position.y + grass_bounds.size.y)
		)
		if rng.randf() < 0.7:  # 70% chance to spawn
			_spawn_flower(grass_container, pos, rng)

	# === PEBBLES/SMALL ROCKS - Scattered ground detail ===
	var pebble_count = 100  # Reduced for performance
	for i in range(pebble_count):
		var pos = Vector2(
			rng.randf_range(grass_bounds.position.x, grass_bounds.position.x + grass_bounds.size.x),
			rng.randf_range(grass_bounds.position.y, grass_bounds.position.y + grass_bounds.size.y)
		)
		if rng.randf() < 0.6:  # 60% chance to spawn
			_spawn_pebble(grass_container, pos, rng)

	# === TRANSITION ZONE DETAILS - Dirt patches, rocks near cliff edge ===
	var transition_y_start = -4500
	var transition_y_end = -5200
	var transition_details = 100
	for i in range(transition_details):
		var pos = Vector2(
			rng.randf_range(-7000, 7000),
			rng.randf_range(transition_y_start, transition_y_end)
		)
		if rng.randf() < 0.5:
			_spawn_dirt_patch(grass_container, pos, rng)
		else:
			_spawn_transition_rock(grass_container, pos, rng)

	print("[TradingHub] Spawned grassland details: %d children" % grass_container.get_child_count())

func _spawn_grass_tuft(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a small grass tuft (cluster of blades)"""
	var tuft = Node2D.new()
	tuft.position = pos

	# Random number of blades (3-7)
	var blade_count = rng.randi_range(3, 7)

	for i in range(blade_count):
		var blade = Polygon2D.new()

		# Blade dimensions
		var height = rng.randf_range(8, 20)
		var width = rng.randf_range(1.5, 3.0)
		var lean = rng.randf_range(-3, 3)
		var offset_x = rng.randf_range(-4, 4)

		# Grass blade shape (triangle with slight curve)
		blade.polygon = PackedVector2Array([
			Vector2(offset_x - width/2, 0),
			Vector2(offset_x + lean - width/4, -height * 0.6),
			Vector2(offset_x + lean, -height),
			Vector2(offset_x + lean + width/4, -height * 0.6),
			Vector2(offset_x + width/2, 0)
		])

		# Varied green colors
		var green_variation = rng.randf_range(-0.05, 0.05)
		var shade = rng.randf_range(0.8, 1.2)
		blade.color = Color(
			(0.15 + green_variation) * shade,
			(0.35 + green_variation) * shade,
			(0.10 + green_variation * 0.5) * shade,
			0.9
		)

		tuft.add_child(blade)

	container.add_child(tuft)

func _spawn_flower(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a small wildflower"""
	var flower = Node2D.new()
	flower.position = pos

	# Stem
	var stem = Polygon2D.new()
	var stem_height = rng.randf_range(6, 12)
	stem.polygon = PackedVector2Array([
		Vector2(-0.5, 0),
		Vector2(-0.3, -stem_height),
		Vector2(0.3, -stem_height),
		Vector2(0.5, 0)
	])
	stem.color = Color(0.15, 0.30, 0.10)
	flower.add_child(stem)

	# Flower head - simple circle of petals
	var petal_count = rng.randi_range(4, 6)
	var petal_size = rng.randf_range(2, 4)

	# Flower colors - various wildflower colors
	var flower_colors = [
		Color(1.0, 1.0, 0.3),   # Yellow (dandelion)
		Color(0.9, 0.4, 0.8),   # Pink
		Color(0.4, 0.4, 0.9),   # Blue
		Color(1.0, 0.5, 0.2),   # Orange
		Color(1.0, 1.0, 1.0),   # White (daisy)
		Color(0.8, 0.2, 0.3),   # Red
	]
	var petal_color = flower_colors[rng.randi() % flower_colors.size()]

	for i in range(petal_count):
		var petal = Polygon2D.new()
		var angle = (TAU / petal_count) * i
		var petal_pos = Vector2(cos(angle), sin(angle)) * petal_size * 0.5
		petal.polygon = PackedVector2Array([
			Vector2(0, -petal_size * 0.3),
			Vector2(-petal_size * 0.4, 0),
			Vector2(0, petal_size * 0.3),
			Vector2(petal_size * 0.4, 0)
		])
		petal.position = Vector2(0, -stem_height) + petal_pos
		petal.rotation = angle
		petal.color = petal_color
		flower.add_child(petal)

	# Center dot
	var center = Polygon2D.new()
	center.polygon = PackedVector2Array([
		Vector2(-1.5, -1.5), Vector2(1.5, -1.5),
		Vector2(1.5, 1.5), Vector2(-1.5, 1.5)
	])
	center.position = Vector2(0, -stem_height)
	center.color = Color(0.9, 0.7, 0.2) if petal_color != Color(1.0, 1.0, 0.3) else Color(0.4, 0.25, 0.1)
	flower.add_child(center)

	container.add_child(flower)

func _spawn_pebble(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a small pebble/stone"""
	var pebble = Polygon2D.new()
	pebble.position = pos

	# Random pebble shape (irregular oval)
	var size = rng.randf_range(2, 6)
	var squash = rng.randf_range(0.5, 1.0)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(5, 8)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.2, 0.2)
		var dist = size * (0.7 + rng.randf() * 0.3)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * squash))

	pebble.polygon = points

	# Grey-brown stone colors
	var grey = rng.randf_range(0.25, 0.45)
	var warm = rng.randf_range(0.0, 0.05)
	pebble.color = Color(grey + warm, grey, grey - warm * 0.5, 0.9)

	container.add_child(pebble)

func _spawn_dirt_patch(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a small exposed dirt patch in transition zone"""
	var patch = Polygon2D.new()
	patch.position = pos

	# Irregular dirt patch shape
	var size = rng.randf_range(15, 40)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(6, 10)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.3, 0.3)
		var dist = size * (0.6 + rng.randf() * 0.4)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.7))

	patch.polygon = points

	# Dirt brown color
	var brown = rng.randf_range(0.12, 0.20)
	patch.color = Color(brown + 0.05, brown, brown - 0.03, 0.85)
	patch.z_index = -3  # Below grass tufts

	container.add_child(patch)

func _spawn_transition_rock(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a small rock in transition zone"""
	var rock = Polygon2D.new()
	rock.position = pos

	# Angular rock shape
	var size = rng.randf_range(8, 25)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(4, 7)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.4, 0.4)
		var dist = size * (0.5 + rng.randf() * 0.5)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.6))

	rock.polygon = points

	# Dark grey stone
	var grey = rng.randf_range(0.08, 0.18)
	rock.color = Color(grey, grey * 0.95, grey * 0.9)

	container.add_child(rock)

# ========================================
# HORIZON AND ATMOSPHERE
# ========================================

func _create_horizon_atmosphere() -> void:
	"""Create distant horizon effects - sky gradient, distant hills, atmosphere"""
	var horizon_container = Node2D.new()
	horizon_container.name = "HorizonAtmosphere"
	horizon_container.z_index = -5  # Behind everything
	add_child(horizon_container)

	# === SKY GRADIENT - Visible at far north edge ===
	# Creates sense of open sky beyond the grassland
	_create_sky_gradient(horizon_container)

	# === DISTANT HILLS - Disabled (caused polygon artifacts in grass area) ===
	# _create_distant_hills(horizon_container)

	# === ATMOSPHERE FOG GRADIENT - Fades distant terrain ===
	_create_atmosphere_fog(horizon_container)

	print("[TradingHub] Created horizon atmosphere effects")

func _create_sky_gradient(container: Node2D) -> void:
	"""Create sky gradient at far north"""
	# Sky starts at Y=-8000 and goes to Y=-12000
	var sky_rect = ColorRect.new()
	sky_rect.name = "SkyGradient"
	sky_rect.position = Vector2(-12000, -12000)
	sky_rect.size = Vector2(24000, 4000)  # Y=-12000 to Y=-8000
	sky_rect.z_index = -10

	# Create a simple gradient shader for the sky
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 sky_top : source_color = vec4(0.45, 0.65, 0.85, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.75, 0.85, 0.92, 1.0);
uniform vec4 horizon_haze : source_color = vec4(0.85, 0.88, 0.82, 1.0);

void fragment() {
	float t = UV.y;
	// Gradient from sky blue at top to hazy horizon at bottom
	vec3 color;
	if (t < 0.7) {
		color = mix(sky_top.rgb, sky_bottom.rgb, t / 0.7);
	} else {
		color = mix(sky_bottom.rgb, horizon_haze.rgb, (t - 0.7) / 0.3);
	}
	COLOR = vec4(color, 1.0);
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("sky_top", Color(0.45, 0.65, 0.85, 1.0))
	material.set_shader_parameter("sky_bottom", Color(0.70, 0.80, 0.88, 1.0))
	material.set_shader_parameter("horizon_haze", Color(0.80, 0.85, 0.75, 1.0))  # Slight green tint from grass

	sky_rect.material = material
	container.add_child(sky_rect)

func _create_distant_hills(container: Node2D) -> void:
	"""Create silhouette of distant rolling hills on horizon"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	# Multiple layers of hills for depth
	var hill_layers = [
		{"y": -8200, "height": 400, "color": Color(0.25, 0.35, 0.20, 0.8), "segments": 20},  # Closest
		{"y": -8800, "height": 600, "color": Color(0.35, 0.45, 0.30, 0.6), "segments": 15},  # Mid
		{"y": -9500, "height": 800, "color": Color(0.50, 0.55, 0.45, 0.4), "segments": 12},  # Far (hazier)
	]

	for layer in hill_layers:
		var hills = Polygon2D.new()
		hills.name = "Hills_%d" % int(-layer["y"])
		hills.z_index = -6 + hill_layers.find(layer)

		var points = PackedVector2Array()

		# Start bottom-left
		points.append(Vector2(-12000, layer["y"]))

		# Generate rolling hill profile
		var x = -12000.0
		var segment_width = 24000.0 / layer["segments"]

		for i in range(layer["segments"] + 1):
			# Perlin-like rolling hills
			var base_height = layer["height"]
			var variation = sin(x * 0.001 + rng.randf() * TAU) * base_height * 0.4
			variation += sin(x * 0.0003) * base_height * 0.3
			variation += rng.randf_range(-base_height * 0.1, base_height * 0.1)

			var hill_y = layer["y"] - base_height - variation
			points.append(Vector2(x, hill_y))
			x += segment_width

		# Close bottom-right and back
		points.append(Vector2(12000, layer["y"]))

		hills.polygon = points
		hills.color = layer["color"]
		container.add_child(hills)

func _create_atmosphere_fog(container: Node2D) -> void:
	"""Create subtle fog gradient that fades distant objects"""
	var fog = ColorRect.new()
	fog.name = "AtmosphereFog"
	fog.position = Vector2(-12000, -12000)
	fog.size = Vector2(24000, 7500)  # Covers Y=-12000 to Y=-4500 (full grass area)
	fog.z_index = -2  # Above ground, below cliffs

	# Fog shader - transparent at bottom, slightly hazy at top
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.75, 0.80, 0.70, 0.15);

void fragment() {
	float t = 1.0 - UV.y;  // Stronger at top (distant)
	float fog_strength = pow(t, 2.0) * fog_color.a;
	COLOR = vec4(fog_color.rgb, fog_strength);
}
"""
	var material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("fog_color", Color(0.75, 0.80, 0.70, 0.12))

	fog.material = material
	container.add_child(fog)

# ========================================
# EDGE SOFTENING SYSTEM
# ========================================

func _create_edge_softening(_grass_edge_vertices: PackedVector2Array) -> void:
	"""Soften hard edges between zones with debris, shadows, and transitions"""
	var edge_container = Node2D.new()
	edge_container.name = "EdgeSoftening"
	add_child(edge_container)

	# 1. Rock debris along cliff bases (inside cave walls)
	_spawn_cliff_debris(edge_container)

	# 2. Shadow gradients at cliff wall bases
	_create_cliff_shadows(edge_container)

	# 3. Grass-to-cave transition is now handled by _create_jagged_grass_edge()
	# which creates the mask polygon AND the transition layer in one pass

	# 4. Sparse dead grass creeping into cave mouth
	_spawn_cave_mouth_vegetation(edge_container)

	print("[TradingHub] Created edge softening effects")

func _spawn_cliff_debris(container: Node2D) -> void:
	"""Spawn rock debris along cliff walls using EXACT collision polygon vertices"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777

	# Use EXACT collision polygon vertices from TradingHub.tscn
	# These are the inner edges of the cave walls (the walkable side)

	# Left cave mouth wall - exact vertices from CaveWallsLeft polygon
	var left_wall_vertices = [
		Vector2(-1100, -4500),
		Vector2(-1000, -4000),
		Vector2(-950, -3800),
		Vector2(-1050, -3600),
		Vector2(-980, -3400),
		Vector2(-1100, -3200),
		Vector2(-1000, -3000),
		Vector2(-1150, -2800),
		Vector2(-1050, -2600),
		Vector2(-1200, -2400),
		Vector2(-1400, -2200),
		Vector2(-1600, -2000),
		Vector2(-1900, -1850),
		Vector2(-2200, -1650),
		Vector2(-2500, -1500),
		Vector2(-2850, -1350),
		Vector2(-3200, -1150),
		Vector2(-3550, -950),
		Vector2(-3900, -750),
		Vector2(-4200, -500),
		Vector2(-4400, -200),
		Vector2(-4550, 100),
		Vector2(-4500, 400),
		Vector2(-4400, 700),
		Vector2(-4250, 1000),
	]

	# Right cave mouth wall - mirrored vertices
	var right_wall_vertices = [
		Vector2(1100, -4500),
		Vector2(1000, -4000),
		Vector2(950, -3800),
		Vector2(1050, -3600),
		Vector2(980, -3400),
		Vector2(1100, -3200),
		Vector2(1000, -3000),
		Vector2(1150, -2800),
		Vector2(1050, -2600),
		Vector2(1200, -2400),
		Vector2(1400, -2200),
		Vector2(1600, -2000),
		Vector2(1900, -1850),
		Vector2(2200, -1650),
		Vector2(2500, -1500),
		Vector2(2850, -1350),
		Vector2(3200, -1150),
		Vector2(3550, -950),
		Vector2(3900, -750),
		Vector2(4200, -500),
		Vector2(4400, -200),
		Vector2(4550, 100),
		Vector2(4500, 400),
		Vector2(4400, 700),
		Vector2(4250, 1000),
	]

	# Spawn debris along left wall (rocks go to the RIGHT of wall = into walkable area)
	_spawn_debris_along_vertices(container, left_wall_vertices, "right", rng)

	# Spawn debris along right wall (rocks go to the LEFT of wall = into walkable area)
	_spawn_debris_along_vertices(container, right_wall_vertices, "left", rng)

func _spawn_debris_along_vertices(container: Node2D, vertices: Array, side: String, rng: RandomNumberGenerator) -> void:
	"""Spawn rock debris along a path defined by vertices"""
	for i in range(vertices.size() - 1):
		var start = vertices[i]
		var end = vertices[i + 1]
		var length = start.distance_to(end)
		var dir = (end - start).normalized()

		# Get perpendicular direction pointing into walkable area
		var normal: Vector2
		if side == "right":
			normal = Vector2(dir.y, -dir.x)  # 90° clockwise
		else:
			normal = Vector2(-dir.y, dir.x)  # 90° counter-clockwise

		# Spawn debris every 30px along this edge segment
		var debris_count = max(int(length / 30), 1)
		for j in range(debris_count):
			var t = float(j) / max(debris_count, 1)
			var base_pos = start.lerp(end, t)

			# Place rocks RIGHT AT the wall (5-25px offset into walkable area)
			var offset = normal * rng.randf_range(5, 25)
			var pos = base_pos + offset

			_spawn_wall_base_rocks(container, pos, rng, normal)

func _spawn_wall_base_rocks(container: Node2D, pos: Vector2, rng: RandomNumberGenerator, normal: Vector2) -> void:
	"""Spawn rocks right at the wall base to break up the hard edge"""
	# Create 1-3 rocks at this position
	var rock_count = rng.randi_range(1, 3)

	for i in range(rock_count):
		var rock = Polygon2D.new()

		# Small offset along the wall
		var along_wall = Vector2(-normal.y, normal.x)
		var offset = along_wall * rng.randf_range(-15, 15) + normal * rng.randf_range(0, 20)

		rock.position = pos + offset
		rock.z_index = 0

		# Rock size - mostly small rubble with occasional larger rocks
		var size = rng.randf_range(8, 20)
		if rng.randf() < 0.15:
			size = rng.randf_range(20, 35)

		# Generate rock shape
		var points = PackedVector2Array()
		var point_count = rng.randi_range(5, 7)
		for j in range(point_count):
			var angle = (TAU / point_count) * j + rng.randf_range(-0.3, 0.3)
			var dist = size * (0.6 + rng.randf() * 0.4)
			points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.65))

		rock.polygon = points

		# Dark rock colors matching cliff wall - FULLY OPAQUE
		var grey = rng.randf_range(0.05, 0.12)
		rock.color = Color(grey + 0.01, grey, grey - 0.005, 1.0)

		container.add_child(rock)

func _spawn_debris_cluster(container: Node2D, pos: Vector2, rng: RandomNumberGenerator, facing: Vector2) -> void:
	"""Spawn a cluster of rocks/debris at position"""
	var cluster = Node2D.new()
	cluster.position = pos
	cluster.z_index = 0  # On top of floor, below player

	# 2-5 rocks per cluster
	var rock_count = rng.randi_range(2, 5)

	for i in range(rock_count):
		var rock = Polygon2D.new()

		# Position within cluster
		var offset = Vector2(
			rng.randf_range(-30, 30),
			rng.randf_range(-20, 20)
		)

		# Rock size - mix of small rubble and larger rocks
		var size = rng.randf_range(5, 25)
		if rng.randf() < 0.2:  # 20% chance of bigger boulder
			size = rng.randf_range(25, 45)

		# Generate irregular rock shape
		var points = PackedVector2Array()
		var point_count = rng.randi_range(5, 8)
		for j in range(point_count):
			var angle = (TAU / point_count) * j + rng.randf_range(-0.3, 0.3)
			var dist = size * (0.6 + rng.randf() * 0.4)
			# Squash vertically for more natural rock look
			points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.6))

		rock.polygon = points
		rock.position = offset

		# Dark grey/brown rock colors matching cliff
		var base_grey = rng.randf_range(0.06, 0.14)
		var warm = rng.randf_range(-0.01, 0.02)
		rock.color = Color(base_grey + warm, base_grey, base_grey - warm * 0.5)

		cluster.add_child(rock)

	container.add_child(cluster)

func _create_cliff_shadows(container: Node2D) -> void:
	"""Create shadow gradients at the base of cliff walls"""
	# Shadow strips along major cliff edges
	# NOTE: Disabled cave mouth shadows - they were causing V artifacts in transition zone
	var shadow_edges = [
		# Cave mouth shadows disabled - caused artifacts
		# {"points": [Vector2(-1100, -4500), Vector2(-1050, -3600), Vector2(-1400, -2200), Vector2(-1600, -2000)],
		#  "width": 120, "side": "right"},
		# {"points": [Vector2(1100, -4500), Vector2(1050, -3600), Vector2(1400, -2200), Vector2(-1600, -2000)],
		#  "width": 120, "side": "left"},
		# Grass-to-cliff transition shadows disabled - handled by gradient system now
		# {"points": [Vector2(-8000, -4000), Vector2(-1100, -4000)],
		#  "width": 200, "side": "down"},
		# {"points": [Vector2(1100, -4000), Vector2(8000, -4000)],
		#  "width": 200, "side": "down"},
	]

	for edge_data in shadow_edges:
		_create_shadow_strip(container, edge_data)

func _create_shadow_strip(container: Node2D, edge_data: Dictionary) -> void:
	"""Create a gradient shadow strip along an edge"""
	var points = edge_data["points"]
	var width = edge_data["width"]
	var side = edge_data["side"]

	if points.size() < 2:
		return

	# Build polygon for shadow area
	var shadow_poly = Polygon2D.new()
	shadow_poly.name = "CliffShadow"
	shadow_poly.z_index = -1  # Below debris, above floor

	var poly_points = PackedVector2Array()
	var colors = PackedColorArray()

	# First pass: inner edge (dark)
	for point in points:
		poly_points.append(point)
		colors.append(Color(0.0, 0.0, 0.0, 0.4))

	# Second pass: outer edge (transparent) - in reverse
	for i in range(points.size() - 1, -1, -1):
		var point = points[i]
		var offset: Vector2

		if i == 0:
			var dir = (points[1] - points[0]).normalized()
			offset = _get_perpendicular(dir, side) * width
		elif i == points.size() - 1:
			var dir = (points[i] - points[i-1]).normalized()
			offset = _get_perpendicular(dir, side) * width
		else:
			var dir1 = (points[i] - points[i-1]).normalized()
			var dir2 = (points[i+1] - points[i]).normalized()
			var avg_dir = (dir1 + dir2).normalized()
			offset = _get_perpendicular(avg_dir, side) * width

		poly_points.append(point + offset)
		colors.append(Color(0.0, 0.0, 0.0, 0.0))

	shadow_poly.polygon = poly_points
	shadow_poly.vertex_colors = colors

	container.add_child(shadow_poly)

func _get_perpendicular(dir: Vector2, side: String) -> Vector2:
	"""Get perpendicular direction based on side"""
	match side:
		"left":
			return Vector2(-dir.y, dir.x)
		"right":
			return Vector2(dir.y, -dir.x)
		"up":
			return Vector2(0, -1)
		"down":
			return Vector2(0, 1)
		_:
			return Vector2(dir.y, -dir.x)

func _create_grass_transition_patches(container: Node2D, jagged_vertices: PackedVector2Array) -> void:
	"""Create grass-style transition patches along the jagged grass edge at Y≈-5000.

	Uses the jagged vertex coordinates as center points for patches, creating
	a natural grass-to-cave transition that follows the irregular edge.
	"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 88888

	print("[TradingHub] Creating grass transition patches along %d jagged vertices" % jagged_vertices.size())

	# Spawn grass-style patches at each jagged vertex
	for vertex in jagged_vertices:
		# Main grass transition patch at vertex
		_spawn_grass_transition_patch(container, vertex, rng)

		# Additional smaller patches near each vertex for denser coverage
		for i in range(2):
			var offset = Vector2(
				rng.randf_range(-40, 40),
				rng.randf_range(-30, 30)
			)
			_spawn_small_grass_patch(container, vertex + offset, rng)

		# Scattered dirt/pebbles to break up the grass edge
		if rng.randf() < 0.5:
			var pebble_offset = Vector2(
				rng.randf_range(-50, 50),
				rng.randf_range(-20, 40)  # More toward cave side
			)
			_spawn_transition_pebble(container, vertex + pebble_offset, rng)

func _spawn_grass_transition_patch(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a grass-colored patch to blend the jagged grass edge."""
	var patch = Polygon2D.new()
	patch.position = pos
	patch.z_index = 2  # On top of the jagged grass polygon

	# Irregular grass clump shape
	var width = rng.randf_range(50, 90)
	var height = rng.randf_range(60, 100)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(8, 12)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.3, 0.3)
		var dist_x = width * 0.5 * (0.6 + rng.randf() * 0.4)
		var dist_y = height * 0.5 * (0.6 + rng.randf() * 0.4)
		points.append(Vector2(cos(angle) * dist_x, sin(angle) * dist_y))

	patch.polygon = points

	# Gradient from grass green (top/north) to dirt brown (bottom/south)
	var colors = PackedColorArray()
	for i in range(point_count):
		var point = points[i]
		var blend = clamp((point.y + height * 0.5) / height, 0.0, 1.0)
		var grass_color = Color(0.14, 0.28, 0.10, 1.0)  # Grass green
		var dirt_color = Color(0.15, 0.12, 0.09, 1.0)    # Brown dirt
		colors.append(grass_color.lerp(dirt_color, blend))

	patch.vertex_colors = colors
	container.add_child(patch)

func _spawn_small_grass_patch(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a smaller grass patch for additional detail."""
	var patch = Polygon2D.new()
	patch.position = pos
	patch.z_index = 2

	var size = rng.randf_range(20, 40)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(5, 8)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.4, 0.4)
		var dist = size * (0.5 + rng.randf() * 0.5)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.7))

	patch.polygon = points

	# Grass-like color with slight variation
	var green = rng.randf_range(0.24, 0.32)
	patch.color = Color(0.13, green, 0.09, 1.0)

	container.add_child(patch)

func _spawn_edge_dirt_patch(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a large dirt patch designed to straddle and obscure the edge line"""
	var patch = Polygon2D.new()
	patch.position = pos
	patch.z_index = -1  # Above the grass/cave floor to cover the line

	# Larger patches that span the edge - wide horizontally, tall enough to cover line
	var width = rng.randf_range(80, 140)
	var height = rng.randf_range(100, 160)  # Tall enough to span across the edge
	var points = PackedVector2Array()
	var point_count = rng.randi_range(10, 16)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.3, 0.3)
		var dist_x = width * 0.5 * (0.6 + rng.randf() * 0.4)
		var dist_y = height * 0.5 * (0.6 + rng.randf() * 0.4)
		points.append(Vector2(cos(angle) * dist_x, sin(angle) * dist_y))

	patch.polygon = points

	# Gradient colors using vertex colors - FULLY OPAQUE
	# Top (negative Y = grass side) blends from grass colors
	# Bottom (positive Y = cliff side) matches TransitionCliff Color(0.12, 0.10, 0.08)
	var colors = PackedColorArray()
	for i in range(point_count):
		var point = points[i]
		var blend = clamp((point.y + height * 0.5) / height, 0.0, 1.0)
		var grass_edge = Color(0.16, 0.25, 0.11, 1.0)  # Darker grass green, OPAQUE
		var cliff_edge = Color(0.12, 0.10, 0.08, 1.0)  # Match TransitionCliff exactly
		colors.append(grass_edge.lerp(cliff_edge, blend))

	patch.vertex_colors = colors
	container.add_child(patch)

func _spawn_edge_rock(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a rock right on the edge line"""
	var rock = Polygon2D.new()
	rock.position = pos
	rock.z_index = 0  # On top to break up the line

	var size = rng.randf_range(15, 35)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(5, 8)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.4, 0.4)
		var dist = size * (0.5 + rng.randf() * 0.5)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.6))

	rock.polygon = points

	# Grey-brown rock colors - FULLY OPAQUE
	var grey = rng.randf_range(0.12, 0.22)
	rock.color = Color(grey + 0.02, grey, grey - 0.01, 1.0)

	container.add_child(rock)

func _spawn_transition_dirt_patch(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn an irregular dirt/earth patch"""
	var patch = Polygon2D.new()
	patch.position = pos
	patch.z_index = -3

	var size = rng.randf_range(30, 80)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(7, 12)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.4, 0.4)
		var dist = size * (0.5 + rng.randf() * 0.5)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.6))

	patch.polygon = points

	# Blend between grass-dirt and cave-floor colors - FULLY OPAQUE
	var blend = clamp((pos.y + 4800) / 800, 0.0, 1.0)
	var dirt_color = Color(0.18, 0.14, 0.10)  # Brown dirt
	var cave_color = Color(0.10, 0.09, 0.08)  # Dark cave floor
	var final_color = dirt_color.lerp(cave_color, blend)
	final_color.a = 1.0  # FULLY OPAQUE

	patch.color = final_color
	container.add_child(patch)

func _spawn_transition_pebble(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn gravel/pebbles in transition zone"""
	var pebble = Polygon2D.new()
	pebble.position = pos
	pebble.z_index = -2

	var size = rng.randf_range(3, 10)
	var points = PackedVector2Array()
	var point_count = rng.randi_range(4, 7)

	for i in range(point_count):
		var angle = (TAU / point_count) * i + rng.randf_range(-0.3, 0.3)
		var dist = size * (0.6 + rng.randf() * 0.4)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist * 0.7))

	pebble.polygon = points

	# FULLY OPAQUE
	var grey = rng.randf_range(0.15, 0.30)
	pebble.color = Color(grey, grey * 0.95, grey * 0.9, 1.0)

	container.add_child(pebble)

func _spawn_cave_mouth_vegetation(container: Node2D) -> void:
	"""Spawn sparse dead grass and weeds creeping into cave mouth area"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 99999

	# Cave mouth opening: X = -1100 to 1100, Y = -4500 to -3600
	# Vegetation creeps in from the grass side (Y around -4000 to -4500)

	# Dead/brown grass tufts near cave entrance
	var tuft_count = 40
	for i in range(tuft_count):
		# Position near the cave mouth edges
		var x: float
		var y: float

		if rng.randf() < 0.5:
			# Near left edge of mouth
			x = rng.randf_range(-1300, -900)
		else:
			# Near right edge of mouth
			x = rng.randf_range(900, 1300)

		y = rng.randf_range(-4600, -4000)

		_spawn_dead_grass_tuft(container, Vector2(x, y), rng)

	# Also spawn some along the transition cliff edges
	for i in range(30):
		var x = rng.randf_range(-6000, 6000)
		var y = rng.randf_range(-4300, -3900)

		# Skip cave mouth center
		if abs(x) < 1000:
			continue

		_spawn_dead_grass_tuft(container, Vector2(x, y), rng)

func _spawn_dead_grass_tuft(container: Node2D, pos: Vector2, rng: RandomNumberGenerator) -> void:
	"""Spawn a sparse tuft of dead/brown grass"""
	var tuft = Node2D.new()
	tuft.position = pos
	tuft.z_index = 0

	var blade_count = rng.randi_range(2, 5)  # Sparse

	for i in range(blade_count):
		var blade = Polygon2D.new()

		var height = rng.randf_range(6, 14)  # Shorter than healthy grass
		var width = rng.randf_range(1.0, 2.0)
		var lean = rng.randf_range(-4, 4)  # More lean (droopy)
		var offset_x = rng.randf_range(-5, 5)

		blade.polygon = PackedVector2Array([
			Vector2(offset_x - width/2, 0),
			Vector2(offset_x + lean * 0.3 - width/4, -height * 0.5),
			Vector2(offset_x + lean, -height),
			Vector2(offset_x + lean * 0.3 + width/4, -height * 0.5),
			Vector2(offset_x + width/2, 0)
		])

		# Dead grass colors - browns, yellows, tans
		var dead_colors = [
			Color(0.35, 0.28, 0.15),  # Brown
			Color(0.40, 0.35, 0.20),  # Tan
			Color(0.30, 0.25, 0.12),  # Dark brown
			Color(0.45, 0.38, 0.18),  # Light tan
		]
		blade.color = dead_colors[rng.randi() % dead_colors.size()]
		blade.color.a = rng.randf_range(0.7, 0.9)

		tuft.add_child(blade)

	container.add_child(tuft)

# =============================================================================
# ZONE 2 TREE SYSTEM - Proximity-based loading for performance
# =============================================================================

# Tree texture paths - variety of tree types for natural forest look
const ZONE2_TREE_TEXTURES: Array[String] = [
	"res://assets/environment/zone2/trees/_tree_02/_tree_02_00000.png",
	"res://assets/environment/zone2/trees/_tree_05/_tree_05_00000.png",
	"res://assets/environment/zone2/trees/_tree_06/_tree_06_00000.png",
	"res://assets/environment/zone2/trees/_tree_07/_tree_07_00000.png",
	"res://assets/environment/zone2/trees/_tree_08/_tree_08_00000.png",
	"res://assets/environment/zone2/trees/_tree_09/_tree_09_00000.png",
	"res://assets/environment/zone2/trees/_tree_12/_tree_12_00000.png",
	"res://assets/environment/zone2/trees/_tree_13/_tree_13_00000.png",
	"res://assets/environment/zone2/trees/_tree_14/_tree_14_00000.png",
]

# Tree spawning parameters
const ZONE2_TREE_COUNT: int = 1200  # Can be much higher now with proximity loading
const ZONE2_TREE_MIN_SPACING: float = 100.0  # Tighter spacing for denser forest
const ZONE2_TREE_BOUNDS: Rect2 = Rect2(-7000, -11500, 14000, 6500)  # X, Y, width, height (stops at Y=-5000)
const ZONE2_TREE_SCALE_MIN: float = 0.25
const ZONE2_TREE_SCALE_MAX: float = 0.55

# Proximity loading settings
const TREE_LOAD_DISTANCE: float = 2000.0  # Load trees within this distance
const TREE_UNLOAD_DISTANCE: float = 2500.0  # Unload trees beyond this (hysteresis)
const TREE_PROXIMITY_CHECK_INTERVAL: float = 0.3  # Check every 0.3 seconds

var _zone2_tree_container: Node2D = null
var _zone2_tree_data: Array[Dictionary] = []  # All tree definitions (not nodes)
var _zone2_active_trees: Dictionary = {}  # {index: Sprite2D} currently loaded trees
var _zone2_tree_textures_loaded: Array[Texture2D] = []  # Preloaded textures
var _tree_proximity_timer: float = 0.0

func _spawn_zone2_trees() -> void:
	"""Generate tree data and setup proximity-based loading system"""
	print("[TradingHub] Initializing Zone 2 tree system (proximity-based)...")

	# Preload all tree textures once
	for path in ZONE2_TREE_TEXTURES:
		var tex = load(path) as Texture2D
		if tex:
			_zone2_tree_textures_loaded.append(tex)
		else:
			print("[TradingHub] WARNING: Failed to load tree texture: %s" % path)

	if _zone2_tree_textures_loaded.is_empty():
		print("[TradingHub] ERROR: No tree textures loaded!")
		return

	# Create container for active trees
	_zone2_tree_container = Node2D.new()
	_zone2_tree_container.name = "Zone2Trees"
	_zone2_tree_container.z_index = 5
	add_child(_zone2_tree_container)

	# Generate all tree DATA (positions, properties) without creating nodes
	var rng = RandomNumberGenerator.new()
	rng.seed = 54321  # Consistent forest layout

	var positions: Array[Vector2] = []
	var attempts = 0
	var max_attempts = ZONE2_TREE_COUNT * 10

	while _zone2_tree_data.size() < ZONE2_TREE_COUNT and attempts < max_attempts:
		attempts += 1

		var pos = Vector2(
			rng.randf_range(ZONE2_TREE_BOUNDS.position.x, ZONE2_TREE_BOUNDS.position.x + ZONE2_TREE_BOUNDS.size.x),
			rng.randf_range(ZONE2_TREE_BOUNDS.position.y, ZONE2_TREE_BOUNDS.position.y + ZONE2_TREE_BOUNDS.size.y)
		)

		# Skip area near cave entrance
		if pos.y > -3500 and abs(pos.x) < 2500:
			continue

		# Check minimum spacing
		var too_close = false
		for existing_pos in positions:
			if pos.distance_to(existing_pos) < ZONE2_TREE_MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue

		# Store tree data (NOT a node yet)
		var tree_data = {
			"pos": pos,
			"texture_index": rng.randi() % _zone2_tree_textures_loaded.size(),
			"scale": rng.randf_range(ZONE2_TREE_SCALE_MIN, ZONE2_TREE_SCALE_MAX),
			"flip_h": rng.randf() < 0.5,
			"z_index": int((pos.y + 12000) / 100)
		}
		_zone2_tree_data.append(tree_data)
		positions.append(pos)

	print("[TradingHub] Zone 2 tree data generated: %d trees (0 nodes until player nearby)" % _zone2_tree_data.size())

func _update_tree_proximity() -> void:
	"""Load/unload trees based on player proximity - called periodically"""
	if not local_player or not is_instance_valid(local_player):
		return
	if _zone2_tree_textures_loaded.is_empty():
		return

	var player_pos = local_player.global_position

	# Check each tree definition
	for i in range(_zone2_tree_data.size()):
		var tree_data = _zone2_tree_data[i]
		var dist = player_pos.distance_to(tree_data["pos"])

		var is_loaded = _zone2_active_trees.has(i)

		if not is_loaded and dist < TREE_LOAD_DISTANCE:
			# Load this tree
			_load_tree(i, tree_data)
		elif is_loaded and dist > TREE_UNLOAD_DISTANCE:
			# Unload this tree
			_unload_tree(i)

func _load_tree(index: int, tree_data: Dictionary) -> void:
	"""Create a Sprite2D node for this tree with undergrowth"""
	var tree = Sprite2D.new()
	tree.texture = _zone2_tree_textures_loaded[tree_data["texture_index"]]
	tree.position = tree_data["pos"]
	tree.scale = Vector2(tree_data["scale"], tree_data["scale"])
	tree.flip_h = tree_data["flip_h"]
	tree.centered = true
	tree.offset.y = -tree.texture.get_height() * 0.5
	tree.z_index = tree_data["z_index"]

	# Darken trees slightly + lower opacity to blend shadows
	tree.modulate = Color(0.7, 0.75, 0.7, 0.55)

	_zone2_tree_container.add_child(tree)
	_zone2_active_trees[index] = tree

	# Undergrowth disabled - was causing visual "square" artifacts
	# _spawn_undergrowth_at_tree(tree_data["pos"], tree_data["z_index"], index)

func _spawn_undergrowth_at_tree(tree_pos: Vector2, tree_z: int, tree_index: int) -> void:
	"""Spawn small bushes/shrubs around tree base to hide floating effect"""
	var rng = RandomNumberGenerator.new()
	rng.seed = tree_index * 7919  # Consistent per tree

	# 2-4 bush clusters per tree
	var bush_count = rng.randi_range(2, 4)

	for i in range(bush_count):
		var bush = Node2D.new()
		bush.name = "Bush_%d_%d" % [tree_index, i]

		# Position around tree base (offset from trunk)
		var angle = rng.randf() * TAU
		var dist = rng.randf_range(15, 45)
		bush.position = tree_pos + Vector2(cos(angle) * dist, sin(angle) * dist * 0.5 + 10)
		bush.z_index = tree_z - 1  # Just behind tree

		# Create bush shape (cluster of overlapping ovals)
		var leaf_count = rng.randi_range(5, 9)
		for j in range(leaf_count):
			var leaf = Polygon2D.new()

			# Leaf blob shape
			var size = rng.randf_range(6, 14)
			var points = PackedVector2Array()
			for k in range(8):
				var a = (TAU / 8.0) * k
				var r = size * (0.7 + rng.randf() * 0.3)
				points.append(Vector2(cos(a) * r, sin(a) * r * 0.6))
			leaf.polygon = points

			# Position within bush cluster
			var leaf_offset = Vector2(
				rng.randf_range(-12, 12),
				rng.randf_range(-8, 4)
			)
			leaf.position = leaf_offset

			# Dark green colors matching forest floor
			var green_colors = [
				Color(0.035, 0.07, 0.025, 0.85),   # Dark forest green
				Color(0.04, 0.08, 0.03, 0.85),    # Slightly lighter
				Color(0.03, 0.06, 0.02, 0.85),    # Darker
				Color(0.045, 0.075, 0.028, 0.85), # Medium
			]
			leaf.color = green_colors[rng.randi() % green_colors.size()]

			bush.add_child(leaf)

		_zone2_tree_container.add_child(bush)

func _unload_tree(index: int) -> void:
	"""Remove a tree node and its undergrowth to free resources"""
	if _zone2_active_trees.has(index):
		var tree = _zone2_active_trees[index]
		if is_instance_valid(tree):
			tree.queue_free()
		_zone2_active_trees.erase(index)

		# Also remove associated bushes
		for i in range(4):  # Max 4 bushes per tree
			var bush_name = "Bush_%d_%d" % [index, i]
			var bush = _zone2_tree_container.get_node_or_null(bush_name)
			if bush:
				bush.queue_free()
