extends CanvasLayer

## Minimap UI - Circular minimap in top-right corner
## Shows player position, detected enemies, and POIs

# Minimap dimensions
const MINIMAP_DIAMETER: int = 220
const MINIMAP_RADIUS: float = MINIMAP_DIAMETER / 2.0
const MINIMAP_MARGIN: int = 15
const BORDER_WIDTH: float = 4.0

# Zoom levels (world units radius) - limited zoom out for better usability
const ZOOM_LEVELS: Array[float] = [750.0, 1250.0, 2000.0, 3000.0]
var current_zoom_index: int = 2  # Start at Normal (2000)

# Colors - Ashbane medieval theme (Neutral Stone Gray)
const BG_COLOR = Color(0.05, 0.05, 0.06, 0.9)
const BORDER_COLOR = Color(0.40, 0.40, 0.42, 1.0)
const BORDER_INNER_COLOR = Color(0.25, 0.25, 0.27, 1.0)
const GRID_COLOR = Color(0.25, 0.25, 0.27, 0.15)

# Marker colors
const PLAYER_COLOR = Color(1.0, 1.0, 1.0, 1.0)
const PLAYER_OUTLINE = Color(0.0, 0.0, 0.0, 0.8)  # Black outline for visibility
const OTHER_PLAYER_COLOR = Color(0.3, 0.8, 0.4, 1.0)
const ENEMY_COLOR = Color(0.9, 0.2, 0.2, 0.9)
const ENEMY_ELITE_COLOR = Color(1.0, 0.5, 0.0, 0.9)

# Ground/terrain colors
const GROUND_COLOR = Color(0.14, 0.14, 0.16, 1.0)  # Dark neutral terrain
const GROUND_ACCENT = Color(0.18, 0.18, 0.20, 1.0)  # Slightly lighter neutral accent

# POI colors
const POI_CAMPFIRE_COLOR = Color(1.0, 0.6, 0.2, 1.0)
const POI_FORGE_COLOR = Color(0.9, 0.75, 0.3, 1.0)
const POI_VENDOR_COLOR = Color(0.3, 0.85, 0.4, 1.0)  # Green for friendly NPCs
const POI_TREE_COLOR = Color(0.3, 0.8, 0.3, 1.0)
const POI_LAVA_COLOR = Color(0.9, 0.3, 0.1, 0.85)  # Red-orange for lava pools

# Update intervals
const ENEMY_UPDATE_INTERVAL: float = 0.1  # 10 Hz
const POI_UPDATE_INTERVAL: float = 1.0    # 1 Hz

# References
var local_player: Node2D = null
var game_world: Node2D = null

# UI components
var main_control: Control
var map_draw: Control  # Custom drawing control
var is_mouse_over: bool = false

# State
var view_radius: float = ZOOM_LEVELS[1]
var _enemy_update_timer: float = 0.0
var _poi_update_timer: float = 0.0

# Cached data
var _poi_positions: Array[Dictionary] = []
var _enemy_positions: Array[Dictionary] = []
var _other_player_positions: Array[Dictionary] = []
var _path_points: Array[Array] = []  # Array of path segment arrays

# Path colors
const PATH_COLOR = Color(0.25, 0.22, 0.20, 0.6)  # Dark worn path color
const PATH_WIDTH_WORLD: float = 175.0  # World units width of path

# Detection tracking for enemies
var _detected_enemies: Dictionary = {}  # instance_id -> {position, last_seen, alpha}
const ENEMY_FADE_TIME: float = 5.0
const PLAYER_DETECTION_RANGE: float = 1500.0  # Show enemies within this range on minimap

# Debug flags
var _debug_printed_once: bool = false

# Fog of War system
const FOG_CELL_SIZE: float = 400.0  # World units per fog cell
const REVEAL_RADIUS: float = 600.0  # How far player reveals around them
const FOG_COLOR = Color(0.02, 0.02, 0.03, 0.92)  # Near black fog
var revealed_cells: Dictionary = {}  # Vector2i -> true
var _last_fog_update_pos: Vector2 = Vector2.ZERO
const FOG_UPDATE_DISTANCE: float = 100.0  # Only update fog when moved this far


func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	layer = 5  # Same as QuestTrackerUI
	_create_ui()

	# Start hidden - show when game world loads
	visible = false

	print("[Minimap] _ready() called - minimap initialized")

	# Defer player/world connection until scene is ready
	call_deferred("_connect_to_game")


func show_minimap() -> void:
	"""Show the minimap (call from game world)"""
	visible = true


func hide_minimap() -> void:
	"""Hide the minimap (call from menus/armory)"""
	visible = false


func _connect_to_game() -> void:
	# Try to find game world - check current_scene first (Godot 4 pattern)
	var current = get_tree().current_scene
	if current and current.name == "GameWorld":
		game_world = current
	else:
		# Fallback: search root children
		var root = get_tree().root
		game_world = root.get_node_or_null("GameWorld")
		if not game_world:
			# Try finding by script or class
			for child in root.get_children():
				if child.name == "GameWorld" or child.get_script() and "game_world" in str(child.get_script().resource_path).to_lower():
					game_world = child
					break
	print("[Minimap] _connect_to_game: game_world=%s (current_scene=%s)" % [game_world, current])
	_try_find_player()


func _try_find_player() -> void:
	"""Try to find the local player - called periodically until found"""
	if local_player:
		return

	# Method 1: Check game_world.local_player
	if game_world and game_world.get("local_player"):
		local_player = game_world.local_player
		print("[Minimap] Found player via game_world.local_player: %s" % [local_player])
		_cache_pois()
		return

	# Method 2: Find player in group
	var players = get_tree().get_nodes_in_group("player")
	for player in players:
		# Check if this is the local player (has active camera or is_local flag)
		if player.get("is_local") == true:
			local_player = player
			_cache_pois()
			return
		elif player.has_node("Camera2D") and player.get_node("Camera2D").enabled:
			local_player = player
			_cache_pois()
			return


func _create_ui() -> void:
	# Main control container - anchored to top-right
	main_control = Control.new()
	main_control.name = "MinimapControl"
	main_control.custom_minimum_size = Vector2(MINIMAP_DIAMETER, MINIMAP_DIAMETER)
	main_control.anchor_left = 1.0
	main_control.anchor_right = 1.0
	main_control.anchor_top = 0.0
	main_control.anchor_bottom = 0.0
	main_control.offset_left = -MINIMAP_DIAMETER - MINIMAP_MARGIN
	main_control.offset_right = -MINIMAP_MARGIN
	main_control.offset_top = MINIMAP_MARGIN
	main_control.offset_bottom = MINIMAP_MARGIN + MINIMAP_DIAMETER
	add_child(main_control)

	# Custom draw control for the minimap content
	map_draw = Control.new()
	map_draw.name = "MapDraw"
	map_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_draw.mouse_filter = Control.MOUSE_FILTER_STOP
	main_control.add_child(map_draw)

	# Connect signals for hover detection
	map_draw.mouse_entered.connect(_on_mouse_entered)
	map_draw.mouse_exited.connect(_on_mouse_exited)
	map_draw.draw.connect(_on_draw)

	# Connect gui_input for click handling
	map_draw.gui_input.connect(_on_gui_input)


func _process(delta: float) -> void:
	if not visible:
		return

	# Keep trying to find player if not found yet
	if not local_player:
		_try_find_player()
		map_draw.queue_redraw()
		return

	# Update enemy positions periodically
	_enemy_update_timer += delta
	if _enemy_update_timer >= ENEMY_UPDATE_INTERVAL:
		_enemy_update_timer = 0.0
		_update_enemy_positions()
		_update_other_players()

	# Update POI positions less frequently
	_poi_update_timer += delta
	if _poi_update_timer >= POI_UPDATE_INTERVAL:
		_poi_update_timer = 0.0
		_cache_pois()

	# Update detected enemy fade
	_update_enemy_fade(delta)

	# Update fog of war when player moves
	_update_fog_of_war()

	# Request redraw
	map_draw.queue_redraw()


func _input(event: InputEvent) -> void:
	# Handle zoom when mouse is over minimap
	if is_mouse_over and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_in()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_out()
			get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	is_mouse_over = true


func _on_mouse_exited() -> void:
	is_mouse_over = false


func _on_gui_input(event: InputEvent) -> void:
	# Click to open full map (future feature)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# TODO: Open full map overlay
			pass


func _zoom_in() -> void:
	current_zoom_index = max(0, current_zoom_index - 1)
	view_radius = ZOOM_LEVELS[current_zoom_index]


func _zoom_out() -> void:
	current_zoom_index = min(ZOOM_LEVELS.size() - 1, current_zoom_index + 1)
	view_radius = ZOOM_LEVELS[current_zoom_index]


func _on_draw() -> void:
	if not local_player:
		_draw_empty_state()
		return

	var center = Vector2(MINIMAP_RADIUS, MINIMAP_RADIUS)

	# Draw background frame
	map_draw.draw_circle(center, MINIMAP_RADIUS, BG_COLOR)

	# Draw ground/terrain
	_draw_ground(center)

	# Draw chunk grid (subtle overlay on ground)
	_draw_chunk_grid(center)

	# Draw fog of war (covers unexplored areas)
	_draw_fog_of_war(center)

	# Draw paths/roads (on top of revealed terrain, visible through fog)
	_draw_paths(center)

	# Draw POIs (on top of fog - always visible POIs show through)
	_draw_pois(center)

	# Draw other players
	_draw_other_players(center)

	# Draw detected enemies
	_draw_enemies(center)

	# Draw player marker (always centered)
	_draw_player_marker(center)

	# Draw border (on top)
	_draw_border(center)


func _draw_empty_state() -> void:
	var center = Vector2(MINIMAP_RADIUS, MINIMAP_RADIUS)
	map_draw.draw_circle(center, MINIMAP_RADIUS, BG_COLOR)
	_draw_border(center)


func _draw_border(center: Vector2) -> void:
	# Outer border
	map_draw.draw_arc(center, MINIMAP_RADIUS - 1, 0, TAU, 64, BORDER_COLOR, BORDER_WIDTH)
	# Inner border accent
	map_draw.draw_arc(center, MINIMAP_RADIUS - BORDER_WIDTH - 1, 0, TAU, 64, BORDER_INNER_COLOR, 2.0)


func _draw_ground(center: Vector2) -> void:
	"""Draw the terrain/ground layer"""
	var inner_radius = MINIMAP_RADIUS - BORDER_WIDTH - 2

	# Draw solid ground color
	map_draw.draw_circle(center, inner_radius, GROUND_COLOR)

	# Add subtle terrain variation with noise-like pattern
	# Draw some accent patches to break up the solid color
	var player_pos = local_player.global_position
	var chunk_size = Constants.CHUNK_SIZE

	# Calculate which chunks are visible
	var chunks_in_view = int(view_radius / chunk_size) + 1

	# Draw chunk-based terrain variation
	var current_chunk_x = int(player_pos.x / chunk_size)
	var current_chunk_y = int(player_pos.y / chunk_size)

	for cx in range(current_chunk_x - chunks_in_view, current_chunk_x + chunks_in_view + 1):
		for cy in range(current_chunk_y - chunks_in_view, current_chunk_y + chunks_in_view + 1):
			# Use chunk coordinates as seed for consistent variation
			var chunk_hash = (cx * 73856093) ^ (cy * 19349663)
			var accent_strength = (chunk_hash % 100) / 100.0

			if accent_strength > 0.7:  # Only some chunks get accent
				var chunk_center_world = Vector2(
					(cx + 0.5) * chunk_size,
					(cy + 0.5) * chunk_size
				)
				var screen_pos = world_to_minimap(chunk_center_world, center)

				# Only draw if within the minimap circle
				if center.distance_to(screen_pos) < inner_radius - 5:
					var patch_radius = (chunk_size * 0.3 * MINIMAP_RADIUS) / view_radius
					patch_radius = clamp(patch_radius, 3.0, 20.0)
					var accent_color = GROUND_ACCENT
					accent_color.a = 0.3 + (accent_strength - 0.7) * 0.5
					map_draw.draw_circle(screen_pos, patch_radius, accent_color)


func _draw_paths(center: Vector2) -> void:
	"""Draw paths/roads on the minimap (only in revealed areas)"""
	if _path_points.is_empty():
		return

	var scale_factor = MINIMAP_RADIUS / view_radius
	var path_width = PATH_WIDTH_WORLD * scale_factor
	path_width = clamp(path_width, 2.0, 15.0)  # Min 2px, max 15px

	var clip_radius = MINIMAP_RADIUS - BORDER_WIDTH - 2

	for path in _path_points:
		if path.size() < 2:
			continue

		# Draw path segments
		for i in range(path.size() - 1):
			var start_world = path[i]
			var end_world = path[i + 1]

			# Only draw if at least one endpoint is in a revealed cell
			var start_revealed = _is_position_revealed(start_world)
			var end_revealed = _is_position_revealed(end_world)
			if not start_revealed and not end_revealed:
				continue

			var start_screen = world_to_minimap(start_world, center)
			var end_screen = world_to_minimap(end_world, center)

			# Clip line segment to circle
			var clipped = _clip_line_to_circle(start_screen, end_screen, center, clip_radius)
			if clipped.size() == 2:
				map_draw.draw_line(clipped[0], clipped[1], PATH_COLOR, path_width)


func _is_position_revealed(world_pos: Vector2) -> bool:
	"""Check if a world position is in a revealed fog cell"""
	var cell = Vector2i(
		int(floor(world_pos.x / FOG_CELL_SIZE)),
		int(floor(world_pos.y / FOG_CELL_SIZE))
	)
	return revealed_cells.has(cell)


func _update_fog_of_war() -> void:
	"""Reveal fog cells around player position"""
	if not local_player:
		return

	var player_pos = local_player.global_position

	# Only update if player moved significantly
	if _last_fog_update_pos.distance_to(player_pos) < FOG_UPDATE_DISTANCE:
		return

	_last_fog_update_pos = player_pos

	# Calculate player's cell position
	var player_cell = Vector2i(
		int(floor(player_pos.x / FOG_CELL_SIZE)),
		int(floor(player_pos.y / FOG_CELL_SIZE))
	)

	# Reveal cells in radius around player
	var cells_radius = int(ceil(REVEAL_RADIUS / FOG_CELL_SIZE)) + 1

	for dx in range(-cells_radius, cells_radius + 1):
		for dy in range(-cells_radius, cells_radius + 1):
			var cell = Vector2i(player_cell.x + dx, player_cell.y + dy)
			var cell_center = Vector2(
				(cell.x + 0.5) * FOG_CELL_SIZE,
				(cell.y + 0.5) * FOG_CELL_SIZE
			)

			# Check if cell center is within reveal radius
			if player_pos.distance_to(cell_center) <= REVEAL_RADIUS:
				revealed_cells[cell] = true


func _draw_fog_of_war(center: Vector2) -> void:
	"""Draw fog overlay - solid circle with revealed areas punched out"""
	if not local_player:
		return

	var player_pos = local_player.global_position
	var clip_radius = MINIMAP_RADIUS - BORDER_WIDTH - 2

	# Step 1: Draw solid fog covering entire minimap
	map_draw.draw_circle(center, clip_radius, FOG_COLOR)

	# Step 2: Punch out revealed cells by drawing ground color on top
	var cell_screen_radius = (FOG_CELL_SIZE / view_radius) * MINIMAP_RADIUS
	cell_screen_radius = max(cell_screen_radius, 8.0)  # Minimum size for visibility

	# Only process cells that could be visible on screen
	var cells_in_view = int(ceil(view_radius / FOG_CELL_SIZE)) + 2
	var player_cell_x = int(floor(player_pos.x / FOG_CELL_SIZE))
	var player_cell_y = int(floor(player_pos.y / FOG_CELL_SIZE))

	for dx in range(-cells_in_view, cells_in_view + 1):
		for dy in range(-cells_in_view, cells_in_view + 1):
			var cell = Vector2i(player_cell_x + dx, player_cell_y + dy)

			if not revealed_cells.has(cell):
				continue

			# Get cell center in world coords
			var cell_center_world = Vector2(
				(cell.x + 0.5) * FOG_CELL_SIZE,
				(cell.y + 0.5) * FOG_CELL_SIZE
			)

			var screen_pos = world_to_minimap(cell_center_world, center)
			var dist_to_center = center.distance_to(screen_pos)

			# Draw revealed area (punch through fog)
			if dist_to_center < clip_radius + cell_screen_radius:
				# Clip the revealed circle to stay within minimap bounds
				if dist_to_center + cell_screen_radius <= clip_radius:
					# Fully inside - draw full circle
					map_draw.draw_circle(screen_pos, cell_screen_radius * 1.1, GROUND_COLOR)
				elif dist_to_center < clip_radius:
					# Partially inside - draw smaller circle
					var visible_radius = min(cell_screen_radius, clip_radius - dist_to_center + cell_screen_radius * 0.3)
					map_draw.draw_circle(screen_pos, visible_radius, GROUND_COLOR)


func _draw_chunk_grid(center: Vector2) -> void:
	# Draw chunk boundary lines
	var player_pos = local_player.global_position
	var chunk_size = Constants.CHUNK_SIZE

	# Find chunk boundaries visible in current view
	var left_bound = player_pos.x - view_radius
	var right_bound = player_pos.x + view_radius
	var top_bound = player_pos.y - view_radius
	var bottom_bound = player_pos.y + view_radius

	# Vertical chunk lines
	var first_chunk_x = floor(left_bound / chunk_size) * chunk_size
	var x = first_chunk_x
	while x <= right_bound:
		var screen_pos = world_to_minimap(Vector2(x, player_pos.y), center)
		# Only draw if within circle
		if center.distance_to(screen_pos) < MINIMAP_RADIUS - BORDER_WIDTH:
			var top_screen = world_to_minimap(Vector2(x, top_bound), center)
			var bottom_screen = world_to_minimap(Vector2(x, bottom_bound), center)
			_draw_line_clipped(top_screen, bottom_screen, center, GRID_COLOR, 1.0)
		x += chunk_size

	# Horizontal chunk lines
	var first_chunk_y = floor(top_bound / chunk_size) * chunk_size
	var y = first_chunk_y
	while y <= bottom_bound:
		var screen_pos = world_to_minimap(Vector2(player_pos.x, y), center)
		if center.distance_to(screen_pos) < MINIMAP_RADIUS - BORDER_WIDTH:
			var left_screen = world_to_minimap(Vector2(left_bound, y), center)
			var right_screen = world_to_minimap(Vector2(right_bound, y), center)
			_draw_line_clipped(left_screen, right_screen, center, GRID_COLOR, 1.0)
		y += chunk_size


func _draw_line_clipped(from: Vector2, to: Vector2, center: Vector2, color: Color, width: float) -> void:
	# Properly clip line to circle boundary
	var clip_radius = MINIMAP_RADIUS - BORDER_WIDTH - 2
	var clipped = _clip_line_to_circle(from, to, center, clip_radius)
	if clipped.size() == 2:
		map_draw.draw_line(clipped[0], clipped[1], color, width)


func _draw_player_marker(center: Vector2) -> void:
	# Player is always at center
	var marker_size = 7.0

	# Get player facing direction - use mouse position (player faces mouse cursor)
	var rotation = 0.0
	var mouse_world_pos = _get_mouse_world_position()
	if mouse_world_pos != Vector2.ZERO:
		var dir = (mouse_world_pos - local_player.global_position).normalized()
		rotation = dir.angle() + PI/2  # Adjust so arrow points toward mouse
	elif local_player.velocity.length() > 10:
		# Fallback to velocity if can't get mouse position
		rotation = local_player.velocity.angle() + PI/2

	# Draw arrow pointing in direction
	var points = PackedVector2Array([
		center + Vector2(0, -marker_size).rotated(rotation),      # Tip
		center + Vector2(-marker_size * 0.6, marker_size * 0.6).rotated(rotation),  # Bottom left
		center + Vector2(0, marker_size * 0.2).rotated(rotation),  # Inner notch
		center + Vector2(marker_size * 0.6, marker_size * 0.6).rotated(rotation),   # Bottom right
	])

	# Draw black outline first (slightly larger)
	var outline_points = PackedVector2Array([
		center + Vector2(0, -marker_size - 1.5).rotated(rotation),
		center + Vector2(-marker_size * 0.7, marker_size * 0.7 + 1).rotated(rotation),
		center + Vector2(0, marker_size * 0.3 + 1).rotated(rotation),
		center + Vector2(marker_size * 0.7, marker_size * 0.7 + 1).rotated(rotation),
	])
	map_draw.draw_colored_polygon(outline_points, PLAYER_OUTLINE)

	# Draw white arrow on top
	map_draw.draw_colored_polygon(points, PLAYER_COLOR)


func _get_mouse_world_position() -> Vector2:
	"""Get the mouse position in world coordinates"""
	if not local_player:
		return Vector2.ZERO

	# Get mouse position in viewport
	var viewport = get_viewport()
	if not viewport:
		return Vector2.ZERO

	var mouse_screen_pos = viewport.get_mouse_position()

	# Get the camera to convert screen to world
	var camera = viewport.get_camera_2d()
	if camera:
		# Convert screen position to world position
		var canvas_transform = viewport.get_canvas_transform()
		return canvas_transform.affine_inverse() * mouse_screen_pos

	return Vector2.ZERO


func _draw_enemies(center: Vector2) -> void:
	for enemy_id in _detected_enemies:
		var data = _detected_enemies[enemy_id]
		var screen_pos = world_to_minimap(data.position, center)

		# Check if within minimap circle
		if center.distance_to(screen_pos) < MINIMAP_RADIUS - BORDER_WIDTH - 3:
			var color = data.get("color", ENEMY_COLOR)
			color.a = data.alpha
			var size = data.get("size", 4.0)
			map_draw.draw_circle(screen_pos, size, color)


func _draw_other_players(center: Vector2) -> void:
	for data in _other_player_positions:
		var screen_pos = world_to_minimap(data.position, center)

		if center.distance_to(screen_pos) < MINIMAP_RADIUS - BORDER_WIDTH - 3:
			map_draw.draw_circle(screen_pos, 5.0, OTHER_PLAYER_COLOR)


func _draw_pois(center: Vector2) -> void:
	var scale_factor = MINIMAP_RADIUS / view_radius
	var clip_radius = MINIMAP_RADIUS - BORDER_WIDTH - 2

	for poi in _poi_positions:
		var screen_pos = world_to_minimap(poi.position, center)
		var dist_from_center = center.distance_to(screen_pos)

		var color = poi.color
		var size = poi.get("size", 6.0)

		# For lava pools, scale based on actual world radius
		if poi.get("type") == "lava" and poi.has("world_radius"):
			var world_radius = poi.world_radius
			size = world_radius * scale_factor
			size = clamp(size, 4.0, 60.0)  # Min 4px, max 60px display size

		# Check if POI is fully or partially inside the circle
		if dist_from_center + size <= clip_radius:
			# Fully inside - draw normally
			map_draw.draw_circle(screen_pos, size + 1, Color(0, 0, 0, 0.5))  # Shadow
			map_draw.draw_circle(screen_pos, size, color)
		elif dist_from_center - size < clip_radius:
			# Partially inside - draw clipped (move toward center and reduce size)
			var dir_to_center = (center - screen_pos).normalized()
			var overlap = dist_from_center + size - clip_radius
			var clipped_pos = screen_pos + dir_to_center * (overlap * 0.5)
			var clipped_size = max(size - overlap * 0.5, 2.0)

			# Only draw if still reasonably visible
			if clipped_size > 2.0:
				map_draw.draw_circle(clipped_pos, clipped_size + 1, Color(0, 0, 0, 0.5))
				map_draw.draw_circle(clipped_pos, clipped_size, color)


func world_to_minimap(world_pos: Vector2, center: Vector2) -> Vector2:
	"""Convert world position to minimap screen coordinates"""
	if not local_player:
		return center

	var player_pos = local_player.global_position
	var relative = world_pos - player_pos
	var scale = MINIMAP_RADIUS / view_radius
	return center + (relative * scale)


func _clip_line_to_circle(p1: Vector2, p2: Vector2, center: Vector2, radius: float) -> Array:
	"""Clip a line segment to a circle. Returns empty array if fully outside, or [start, end] if visible."""
	var d1 = center.distance_to(p1)
	var d2 = center.distance_to(p2)

	# Both inside - draw as-is
	if d1 <= radius and d2 <= radius:
		return [p1, p2]

	# Both outside and line doesn't intersect circle
	if d1 > radius and d2 > radius:
		# Check if line passes through circle
		var closest = _closest_point_on_line(p1, p2, center)
		if center.distance_to(closest) > radius:
			return []  # Line doesn't intersect circle

	# Find intersection points
	var intersections = _line_circle_intersections(p1, p2, center, radius)

	if intersections.size() == 0:
		return []

	# Determine clipped segment
	var start = p1 if d1 <= radius else intersections[0]
	var end = p2 if d2 <= radius else intersections[-1]

	return [start, end]


func _closest_point_on_line(p1: Vector2, p2: Vector2, point: Vector2) -> Vector2:
	"""Find closest point on line segment to a given point"""
	var line_vec = p2 - p1
	var point_vec = point - p1
	var line_len = line_vec.length()
	if line_len < 0.001:
		return p1
	var line_unit = line_vec / line_len
	var proj_length = point_vec.dot(line_unit)
	proj_length = clamp(proj_length, 0, line_len)
	return p1 + line_unit * proj_length


func _line_circle_intersections(p1: Vector2, p2: Vector2, center: Vector2, radius: float) -> Array:
	"""Find intersection points between a line segment and a circle"""
	var d = p2 - p1
	var f = p1 - center

	var a = d.dot(d)
	var b = 2 * f.dot(d)
	var c = f.dot(f) - radius * radius

	var discriminant = b * b - 4 * a * c
	if discriminant < 0:
		return []

	var sqrt_disc = sqrt(discriminant)
	var t1 = (-b - sqrt_disc) / (2 * a)
	var t2 = (-b + sqrt_disc) / (2 * a)

	var results = []
	if t1 >= 0 and t1 <= 1:
		results.append(p1 + d * t1)
	if t2 >= 0 and t2 <= 1 and abs(t2 - t1) > 0.001:
		results.append(p1 + d * t2)

	return results


func _cache_pois() -> void:
	"""Cache POI positions - called periodically"""
	# Try to find game_world if not set
	if not game_world:
		var current = get_tree().current_scene
		if current and current.name == "GameWorld":
			game_world = current
		else:
			# Fallback: search root children
			var root = get_tree().root
			for child in root.get_children():
				if child.name == "GameWorld":
					game_world = child
					break

	if not _debug_printed_once:
		print("[Minimap] _cache_pois called - game_world=%s, local_player=%s" % [game_world, local_player])
	_poi_positions.clear()

	# Campfires
	for campfire in get_tree().get_nodes_in_group("campfire"):
		_poi_positions.append({
			"position": campfire.global_position,
			"color": POI_CAMPFIRE_COLOR,
			"size": 8.0,
			"name": "Campfire"
		})

	# Vendors
	for vendor in get_tree().get_nodes_in_group("vendor"):
		_poi_positions.append({
			"position": vendor.global_position,
			"color": POI_VENDOR_COLOR,
			"size": 6.0,
			"name": "Vendor"
		})

	# Forge stations
	for forge in get_tree().get_nodes_in_group("forge"):
		_poi_positions.append({
			"position": forge.global_position,
			"color": POI_FORGE_COLOR,
			"size": 7.0,
			"name": "Forge"
		})

	# World trees
	for tree in get_tree().get_nodes_in_group("world_tree"):
		_poi_positions.append({
			"position": tree.global_position,
			"color": POI_TREE_COLOR,
			"size": 8.0,
			"name": "World Tree"
		})

	# Lava pools - search by class or name pattern
	_cache_lava_pools()

	# Paths/roads
	_cache_paths()

	# Debug summary (print once)
	if not _debug_printed_once:
		var lava_count = 0
		for poi in _poi_positions:
			if poi.get("type") == "lava":
				lava_count += 1
		print("[Minimap] POI summary: %d total POIs (%d lava pools), %d path segments" % [_poi_positions.size(), lava_count, _path_points.size()])
		_debug_printed_once = true


func _cache_paths() -> void:
	"""Cache path points from game_world.chunk_path_points"""
	_path_points.clear()

	if not game_world:
		if not _debug_printed_once:
			print("[Minimap] _cache_paths: game_world is null!")
		return

	# Get path points directly from game_world
	var chunk_path_points = game_world.get("chunk_path_points")
	if not _debug_printed_once:
		print("[Minimap] _cache_paths: chunk_path_points has %d entries" % [chunk_path_points.size() if chunk_path_points else 0])
	if chunk_path_points and chunk_path_points.size() > 0:
		for chunk_id in chunk_path_points:
			var points = chunk_path_points[chunk_id]
			if points is Array and points.size() >= 2:
				_path_points.append(points)
		# Debug: Print path info (only first call)
		if not _debug_printed_once and _path_points.size() > 0:
			print("[Minimap] Cached %d path segments from chunk_path_points" % _path_points.size())
		return

	# Fallback: Look for PathSystem node and extract positions from ColorRects
	var path_system = game_world.get_node_or_null("PathSystem")
	if path_system:
		for child in path_system.get_children():
			if child.name.begins_with("PathChunk_"):
				# Collect ColorRect positions as approximate path
				var path_positions: Array = []
				for patch in child.get_children():
					if patch is ColorRect:
						path_positions.append(patch.global_position + patch.size / 2)
				# Sort by x position for rough path
				if path_positions.size() > 2:
					path_positions.sort_custom(func(a, b): return a.x < b.x)
					# Sample every few points to reduce density
					var sampled: Array = []
					for i in range(0, path_positions.size(), 5):
						sampled.append(path_positions[i])
					if sampled.size() >= 2:
						_path_points.append(sampled)


func _cache_lava_pools() -> void:
	"""Find and cache lava pool positions with proper sizes"""
	var added_positions: Array[Vector2] = []  # Track to avoid duplicates

	if not game_world:
		if not _debug_printed_once:
			print("[Minimap] _cache_lava_pools: game_world is null!")
		return

	# Method 1: Get data from ChunkBasedPropSystem's loaded_chunks
	var prop_system = game_world.get("chunk_prop_system")
	if not _debug_printed_once:
		print("[Minimap] _cache_lava_pools: prop_system=%s" % [prop_system])
	if prop_system:
		var loaded_chunks = prop_system.loaded_chunks  # Direct access for class property
		if not _debug_printed_once:
			print("[Minimap] loaded_chunks has %d entries" % [loaded_chunks.size() if loaded_chunks else 0])
		if loaded_chunks and loaded_chunks is Dictionary:
			for chunk_key in loaded_chunks.keys():
				var chunk_data = loaded_chunks[chunk_key]
				if chunk_data:
					# Access typed arrays directly (ChunkData is a class)
					var monster_count = chunk_data.monster_lava_positions.size() if chunk_data.monster_lava_positions else 0
					var lava_count = chunk_data.lava_pool_positions.size() if chunk_data.lava_pool_positions else 0
					if not _debug_printed_once:
						print("[Minimap] Chunk %s: %d monster lava, %d lava pools" % [chunk_key, monster_count, lava_count])

					for pool_data in chunk_data.monster_lava_positions:
						if pool_data is Dictionary and pool_data.has("pos"):
							_add_lava_poi(pool_data.pos, pool_data.get("radius", 150.0), added_positions)

					for pool_data in chunk_data.lava_pool_positions:
						if pool_data is Dictionary and pool_data.has("pos"):
							_add_lava_poi(pool_data.pos, pool_data.get("radius", 75.0), added_positions)

					# Also check props_container for actual lava pool nodes
					if chunk_data.props_container and is_instance_valid(chunk_data.props_container):
						_find_lava_pools_in_container(chunk_data.props_container, added_positions)

	# Method 2: Search all children of game_world recursively
	_find_lava_pools_in_container(game_world, added_positions, 0)


func _find_lava_pools_in_container(container: Node, added_positions: Array[Vector2], depth: int = 0) -> void:
	"""Find lava pools in a props container (recursive)"""
	if depth > 5:  # Prevent infinite recursion
		return

	for child in container.get_children():
		if child is Node2D:
			# Check if this is a lava pool
			var child_name = child.name as String
			if child_name.begins_with("LavaPool") or child_name.begins_with("MonsterLava"):
				var pool_radius = _get_lava_pool_radius(child)
				_add_lava_poi(child.global_position, pool_radius, added_positions)
			# Recurse into containers that might have lava pools
			elif child.get_child_count() > 0:
				_find_lava_pools_in_container(child, added_positions, depth + 1)


func _get_lava_pool_radius(node: Node2D) -> float:
	"""Get the actual radius of a lava pool from its collision shape or scale"""
	# Check for collision shapes in the node or its children
	for child in node.get_children():
		if child is Area2D:
			for area_child in child.get_children():
				if area_child is CollisionShape2D and area_child.shape:
					if area_child.shape is CircleShape2D:
						return area_child.shape.radius
					elif area_child.shape is RectangleShape2D:
						return max(area_child.shape.size.x, area_child.shape.size.y) / 2.0

	# Check node scale as fallback
	var scale_factor = max(node.scale.x, node.scale.y)
	if scale_factor > 1.0:
		return 100.0 * scale_factor  # Base size * scale

	# Default sizes based on name
	if "Monster" in node.name:
		return 175.0  # Monster pools are 200-350, average ~275
	else:
		return 75.0  # Regular pools are 80-150, average ~115


func _add_lava_poi(pos: Vector2, world_radius: float, added_positions: Array[Vector2]) -> void:
	"""Add a lava pool POI if not already added"""
	# Check for duplicates
	for existing_pos in added_positions:
		if existing_pos.distance_to(pos) < 50:
			return

	added_positions.append(pos)

	# Store the world radius for proper scaling during draw
	_poi_positions.append({
		"position": pos,
		"color": POI_LAVA_COLOR,
		"world_radius": world_radius,  # Actual world size for scaling
		"size": 6.0,  # Minimum display size
		"name": "Lava Pool",
		"type": "lava"
	})

	# Debug: Print when lava pool is added (only first call)
	if not _debug_printed_once and added_positions.size() <= 3:  # Only print first few
		print("[Minimap] Added lava pool at %s with radius %.1f" % [pos, world_radius])


func _update_enemy_positions() -> void:
	"""Update detected enemy positions"""
	if not local_player:
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var player_pos = local_player.global_position

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue

		var enemy_id = enemy.get_instance_id()
		var enemy_pos = enemy.global_position
		var distance = player_pos.distance_to(enemy_pos)

		# Check if enemy is detected
		if _is_enemy_detected(enemy, distance):
			var is_elite = enemy.get("is_elite") or enemy.get("enemy_type") == "guardian"
			_detected_enemies[enemy_id] = {
				"position": enemy_pos,
				"last_seen": current_time,
				"alpha": 1.0,
				"color": ENEMY_ELITE_COLOR if is_elite else ENEMY_COLOR,
				"size": 5.0 if is_elite else 4.0
			}
		elif _detected_enemies.has(enemy_id):
			# Update position but start fading
			_detected_enemies[enemy_id].position = enemy_pos


func _is_enemy_detected(enemy: Node2D, distance: float) -> bool:
	"""Check if enemy should be shown on minimap"""
	# Always show enemies within detection range
	if distance < PLAYER_DETECTION_RANGE:
		return true

	# Show enemies that have aggro on player (regardless of distance)
	if enemy.get("target_player") != null:
		if enemy.get("target_player") == local_player:
			return true

	# Show enemies that are chasing/running toward player
	if enemy.get("is_running") == true:
		return true

	# Enemy was recently damaged - show for 10 seconds
	if enemy.has_meta("last_damage_time"):
		var time_since_damage = Time.get_ticks_msec() / 1000.0 - enemy.get_meta("last_damage_time")
		if time_since_damage < 10.0:
			return true

	return false


func _update_enemy_fade(delta: float) -> void:
	"""Fade out enemies that are no longer detected"""
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []

	for enemy_id in _detected_enemies:
		var data = _detected_enemies[enemy_id]
		var time_since_seen = current_time - data.last_seen

		if time_since_seen > ENEMY_FADE_TIME:
			to_remove.append(enemy_id)
		elif time_since_seen > 0.1:  # Start fading after brief delay
			data.alpha = 1.0 - (time_since_seen / ENEMY_FADE_TIME)

	for enemy_id in to_remove:
		_detected_enemies.erase(enemy_id)


func _update_other_players() -> void:
	"""Update other player positions for multiplayer"""
	_other_player_positions.clear()

	if not game_world:
		return

	for player in get_tree().get_nodes_in_group("player"):
		if player != local_player and is_instance_valid(player):
			_other_player_positions.append({
				"position": player.global_position
			})


# Public API

func set_player(player: Node2D) -> void:
	"""Set the local player reference"""
	local_player = player
	_cache_pois()


func set_game_world(world: Node2D) -> void:
	"""Set the game world reference"""
	game_world = world
	_debug_printed_once = false  # Reset to print fresh debug info
	print("[Minimap] set_game_world called with: %s" % [world])
	_cache_pois()


func get_current_zoom_name() -> String:
	"""Get the name of current zoom level"""
	match current_zoom_index:
		0: return "Combat"
		1: return "Close"
		2: return "Normal"
		3: return "Far"
		_: return "Unknown"


# Fog of War Persistence

func get_fog_data() -> Dictionary:
	"""Get fog of war data for saving"""
	var cells_array = []
	for cell in revealed_cells.keys():
		cells_array.append([cell.x, cell.y])
	return {"revealed_cells": cells_array}


func load_fog_data(data: Dictionary) -> void:
	"""Load fog of war data from save"""
	revealed_cells.clear()
	var cells_array = data.get("revealed_cells", [])
	for cell_data in cells_array:
		if cell_data is Array and cell_data.size() == 2:
			var cell = Vector2i(int(cell_data[0]), int(cell_data[1]))
			revealed_cells[cell] = true
	print("[Minimap] Loaded %d revealed fog cells" % revealed_cells.size())


func clear_fog_data() -> void:
	"""Clear all fog of war data (for new game)"""
	revealed_cells.clear()
	_last_fog_update_pos = Vector2.ZERO
