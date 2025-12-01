class_name WorldPathManager
extends RefCounted
## Manages world path generation: paths, torches, terrain spots
## Used by game_world.gd for chunk-based path loading
##
## INTEGRATION GUIDE:
## -----------------
## To use this manager in game_world.gd:
##
## 1. Add to game_world.gd variables:
##    var path_manager: WorldPathManager = null
##
## 2. In _ready():
##    path_manager = WorldPathManager.new(self, CAMPFIRE_POS)
##    path_manager.create_path_system()
##    path_manager.create_torches_along_path()
##
## 3. For chunk loading:
##    path_manager.spawn_path_for_chunk(chunk_id, RUINS_POSITIONS)
##    path_manager.despawn_path_for_chunk(chunk_id)
##
## 4. For path queries:
##    if path_manager.is_position_on_path(pos, 100.0):
##        # Position is on the path
##
## 5. Get path points for other systems:
##    var points = path_manager.get_chunk_path_points(chunk_id)

var world: Node2D

# Store generated path points for reuse (torch placement, etc.)
var chunk_path_points: Dictionary = {}  # {chunk_id: Array of points}

# Campfire position
var campfire_pos: Vector2 = Vector2(Constants.CHUNK_SIZE / 2, 0)

func _init(world_ref: Node2D, campfire_position: Vector2 = Vector2.ZERO) -> void:
	world = world_ref
	if campfire_position != Vector2.ZERO:
		campfire_pos = campfire_position

func create_path_system() -> void:
	"""Initialize path system container. Actual paths are spawned per-chunk."""
	var path_layer = world.get_node_or_null("PathSystem")
	if not path_layer:
		path_layer = Node2D.new()
		path_layer.name = "PathSystem"
		path_layer.z_index = -8
		world.add_child(path_layer)

	print("🛤️ Path system container initialized (paths spawn per-chunk)")

func spawn_path_for_chunk(chunk_id: int, ruins_positions: Dictionary) -> void:
	"""Spawn path segment and torches for a specific chunk"""
	var path_layer = world.get_node_or_null("PathSystem")
	if not path_layer:
		path_layer = Node2D.new()
		path_layer.name = "PathSystem"
		path_layer.z_index = -8
		world.add_child(path_layer)

	# Check if path already exists for this chunk
	var chunk_path_name = "PathChunk_%d" % chunk_id
	if path_layer.get_node_or_null(chunk_path_name):
		return  # Already loaded

	var rng = RandomNumberGenerator.new()
	rng.seed = 77777 + chunk_id  # Different but deterministic seed per chunk

	# Create path container for this chunk
	var chunk_path = Node2D.new()
	chunk_path.name = chunk_path_name
	path_layer.add_child(chunk_path)

	# Calculate chunk boundaries
	var cs = Constants.CHUNK_SIZE
	var chunk_start_x = chunk_id * cs
	var chunk_end_x = (chunk_id + 1) * cs

	# Clamp to world boundaries
	chunk_start_x = clamp(chunk_start_x, -cs, cs * 2)
	chunk_end_x = clamp(chunk_end_x, -cs, cs * 2)

	# Create main path through this chunk
	var path_start = Vector2(chunk_start_x, 0)
	var path_end = Vector2(chunk_end_x, 0)
	var main_path = create_zigzag_path(path_start, path_end, 8, 350, rng)

	# For chunk 0, skip drawing path spots within campfire circle radius
	var campfire_radius = 500.0
	if chunk_id == 0:
		draw_path_from_points_avoiding_area(chunk_path, main_path, 175, rng, campfire_pos, campfire_radius)
		create_campfire_circle(chunk_path, campfire_pos, rng)
	else:
		draw_path_from_points(chunk_path, main_path, 175, rng)

	# Store path points for torch/enemy systems
	chunk_path_points[chunk_id] = main_path

	# Create branch paths to ruins in this chunk
	for ruins_key in ruins_positions.keys():
		var ruins_data = ruins_positions[ruins_key]
		if ruins_data.chunk_id != chunk_id:
			continue

		var ruins_pos = ruins_data.position
		var branch_x = clamp(ruins_pos.x + (400 if chunk_id < 0 else -400), chunk_start_x + 200, chunk_end_x - 200)
		var branch_point = Vector2(branch_x, get_path_y_at_x(main_path, branch_x))
		var ruins_path = create_zigzag_path(branch_point, ruins_pos, 4, 200, rng)
		draw_path_from_points(chunk_path, ruins_path, 130, rng)

	# Spawn torches along this chunk's path
	spawn_torches_for_chunk(chunk_id, main_path, chunk_path)

	print("🛤️ Path spawned for chunk %d (X: %.0f to %.0f)" % [chunk_id, chunk_start_x, chunk_end_x])

func despawn_path_for_chunk(chunk_id: int) -> void:
	"""Despawn path segment and torches for a specific chunk"""
	var path_layer = world.get_node_or_null("PathSystem")
	if not path_layer:
		return

	var chunk_path_name = "PathChunk_%d" % chunk_id
	var chunk_path = path_layer.get_node_or_null(chunk_path_name)
	if chunk_path:
		print("🗑️ Despawning path for chunk %d" % chunk_id)
		chunk_path.queue_free()

	# Also despawn torches
	despawn_torches_for_chunk(chunk_id)

	# Clear stored path points
	chunk_path_points.erase(chunk_id)

func get_path_y_at_x(path_points: Array, target_x: float) -> float:
	"""Find the Y coordinate on a path at a given X position (interpolated)"""
	for i in range(path_points.size() - 1):
		var p1 = path_points[i]
		var p2 = path_points[i + 1]

		var min_x = min(p1.x, p2.x)
		var max_x = max(p1.x, p2.x)

		if target_x >= min_x and target_x <= max_x:
			if abs(p2.x - p1.x) < 0.001:
				return p1.y
			var t = (target_x - p1.x) / (p2.x - p1.x)
			return lerp(p1.y, p2.y, t)

	return 0.0

func create_zigzag_path(start: Vector2, end: Vector2, num_zigs: int, zig_amplitude: float, rng: RandomNumberGenerator) -> Array:
	"""Generate a zigzag path between two points"""
	var points = [start]
	var direction = (end - start).normalized()
	var perpendicular = Vector2(-direction.y, direction.x)
	var total_distance = start.distance_to(end)

	for i in range(1, num_zigs + 1):
		var t = float(i) / float(num_zigs + 1)
		var base_pos = start.lerp(end, t)
		var zig_direction = 1 if i % 2 == 0 else -1
		var offset = perpendicular * zig_amplitude * zig_direction * rng.randf_range(0.7, 1.0)
		points.append(base_pos + offset)

	points.append(end)
	return points

func draw_path_from_points(parent: Node2D, points: Array, width: float, rng: RandomNumberGenerator) -> void:
	"""Draw path segments between all points in array"""
	for i in range(points.size() - 1):
		var start = points[i]
		var end = points[i + 1]
		create_path_segment(parent, start, end, width, rng)

func draw_path_from_points_avoiding_area(parent: Node2D, points: Array, width: float, rng: RandomNumberGenerator, avoid_center: Vector2, avoid_radius: float) -> void:
	"""Draw path segments between all points, skipping spots within avoid area"""
	for i in range(points.size() - 1):
		var start = points[i]
		var end = points[i + 1]
		create_path_segment_avoiding_area(parent, start, end, width, rng, avoid_center, avoid_radius)

func create_path_segment(parent: Node2D, start: Vector2, end: Vector2, width: float, rng: RandomNumberGenerator) -> void:
	"""Create worn dirt path with visible beaten trail"""
	create_path_segment_avoiding_area(parent, start, end, width, rng, Vector2.ZERO, 0.0)

func create_path_segment_avoiding_area(parent: Node2D, start: Vector2, end: Vector2, width: float, rng: RandomNumberGenerator, avoid_center: Vector2, avoid_radius: float) -> void:
	"""Create worn dirt path with visible beaten trail, skipping spots within avoid area"""
	var segment_length = start.distance_to(end)
	var actual_width = width * 1.5
	var num_spots = int(segment_length / 35) + 1

	for i in range(num_spots):
		var t = float(i) / float(max(1, num_spots - 1))
		var pos = start.lerp(end, t)

		var direction = (end - start).normalized()
		var perpendicular = Vector2(-direction.y, direction.x)
		var offset = rng.randf_range(-actual_width * 0.35, actual_width * 0.35)
		pos += perpendicular * offset

		# Skip spots within avoid area (campfire circle)
		if avoid_radius > 0 and pos.distance_to(avoid_center) < avoid_radius:
			continue

		var spot_size = rng.randf_range(actual_width * 0.9, actual_width * 1.1)

		var layers = [
			{"size_mult": 1.6, "alpha": 0.15, "color": Color(0.11, 0.11, 0.12)},
			{"size_mult": 1.0, "alpha": 0.25, "color": Color(0.10, 0.10, 0.11)},
			{"size_mult": 1.0, "alpha": 0.40, "color": Color(0.09, 0.09, 0.10)}
		]

		for layer in layers:
			var patch = ColorRect.new()
			var size = spot_size * layer.size_mult
			patch.size = Vector2(size, size)
			patch.position = pos - patch.size / 2
			patch.color = Color(layer.color.r, layer.color.g, layer.color.b, layer.alpha)
			patch.rotation = rng.randf() * TAU
			parent.add_child(patch)

func create_campfire_circle(parent: Node2D, center: Vector2, rng: RandomNumberGenerator) -> void:
	"""Create a heavily-visited circular area around campfire"""
	var rings = [
		{"radius": 60, "spots": 4},
		{"radius": 120, "spots": 8},
		{"radius": 180, "spots": 12},
		{"radius": 240, "spots": 16},
		{"radius": 300, "spots": 20},
		{"radius": 360, "spots": 24},
		{"radius": 420, "spots": 28},
	]

	for ring_data in rings:
		var ring_radius = ring_data.radius
		var num_spots = ring_data.spots
		var angle_offset = rng.randf() * TAU

		for i in range(num_spots):
			var angle = (float(i) / float(num_spots)) * TAU + angle_offset
			var dist = ring_radius + rng.randf_range(-20, 20)
			var pos = center + Vector2(cos(angle), sin(angle)) * dist
			pos += Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15))

			var spot_size = rng.randf_range(140, 200)

			var layers = [
				{"size_mult": 1.6, "alpha": 0.15, "color": Color(0.11, 0.11, 0.12)},
				{"size_mult": 1.0, "alpha": 0.25, "color": Color(0.10, 0.10, 0.11)},
				{"size_mult": 1.0, "alpha": 0.40, "color": Color(0.09, 0.09, 0.10)}
			]

			for layer in layers:
				var patch = ColorRect.new()
				var size = spot_size * layer.size_mult
				patch.size = Vector2(size, size)
				patch.position = pos - patch.size / 2
				patch.color = Color(layer.color.r, layer.color.g, layer.color.b, layer.alpha)
				patch.rotation = rng.randf() * TAU
				parent.add_child(patch)

# ========================================
# TORCH SYSTEM
# ========================================

func create_torches_along_path() -> void:
	"""Initialize torches container. Actual torches are spawned per-chunk."""
	var torches_node = world.get_node_or_null("Torches")
	if not torches_node:
		torches_node = Node2D.new()
		torches_node.name = "Torches"
		torches_node.z_index = 5
		world.add_child(torches_node)

	print("🔥 Torches container initialized (torches spawn per-chunk)")

func spawn_torches_for_chunk(chunk_id: int, path_points: Array, parent: Node2D) -> void:
	"""Spawn torches along a chunk's path"""
	var torches_node = world.get_node_or_null("Torches")
	if not torches_node:
		torches_node = Node2D.new()
		torches_node.name = "Torches"
		torches_node.z_index = 5
		world.add_child(torches_node)

	var chunk_torches_name = "TorchesChunk_%d" % chunk_id
	if torches_node.get_node_or_null(chunk_torches_name):
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = 77777 + chunk_id

	var chunk_torches = Node2D.new()
	chunk_torches.name = chunk_torches_name
	torches_node.add_child(chunk_torches)

	var torch_count = place_torches_along_path(path_points, chunk_torches, rng)
	print("🔥 Spawned %d torches for chunk %d" % [torch_count, chunk_id])

func despawn_torches_for_chunk(chunk_id: int) -> void:
	"""Despawn torches for a specific chunk"""
	var torches_node = world.get_node_or_null("Torches")
	if not torches_node:
		return

	var chunk_torches_name = "TorchesChunk_%d" % chunk_id
	var chunk_torches = torches_node.get_node_or_null(chunk_torches_name)
	if chunk_torches:
		chunk_torches.queue_free()

func place_torches_along_path(path_positions: Array, parent: Node2D, rng: RandomNumberGenerator) -> int:
	"""Place torches along a path, returns count placed"""
	if path_positions.size() < 2:
		return 0

	var total_path_length = 0.0
	for i in range(path_positions.size() - 1):
		total_path_length += path_positions[i].distance_to(path_positions[i + 1])

	var base_spacing = 1700.0
	var torch_count = 0
	var current_distance = 0.0
	var next_torch_at = base_spacing
	var segment_index = 0

	while next_torch_at < total_path_length and segment_index < path_positions.size() - 1:
		var start_pos = path_positions[segment_index]
		var end_pos = path_positions[segment_index + 1]
		var segment_length = start_pos.distance_to(end_pos)
		var segment_end_distance = current_distance + segment_length

		while next_torch_at <= segment_end_distance and next_torch_at < total_path_length:
			var distance_into_segment = next_torch_at - current_distance
			var t = distance_into_segment / segment_length
			var torch_pos = start_pos.lerp(end_pos, t)

			var direction = (end_pos - start_pos).normalized()
			var perpendicular = Vector2(-direction.y, direction.x)
			var offset = rng.randf_range(-180.0, 180.0)
			torch_pos += perpendicular * offset

			var torch_script = load("res://scripts/systems/Torch.gd")
			if torch_script:
				var torch = Node2D.new()
				torch.set_script(torch_script)
				torch.name = "Torch_" + str(torch_count)
				torch.position = torch_pos
				parent.add_child(torch)
				torch_count += 1

			next_torch_at += rng.randf_range(1400.0, 2000.0)

		current_distance = segment_end_distance
		segment_index += 1

	return torch_count

# ========================================
# UTILITY FUNCTIONS
# ========================================

func is_position_on_path(pos: Vector2, path_width: float = 100.0) -> bool:
	"""Check if a position is on the main path"""
	var castle_pos = Vector2(11000, -300)

	if pos.x >= campfire_pos.x and pos.x <= castle_pos.x:
		var path_length = castle_pos.x - campfire_pos.x
		var t = (pos.x - campfire_pos.x) / path_length
		var path_y = lerp(campfire_pos.y, castle_pos.y, t)
		if t > 0 and t < 1:
			var curve_amount = sin(t * PI) * 250
			path_y += sin(t * PI * 2.5) * curve_amount

		var distance_from_path = abs(pos.y - path_y)
		if distance_from_path <= path_width:
			return true

	return false

func get_chunk_path_points(chunk_id: int) -> Array:
	"""Get stored path points for a chunk"""
	return chunk_path_points.get(chunk_id, [])
