extends Node

## SpatialGrid - O(1) spatial lookup for massive battle optimization
##
## Divides the world into cells for efficient "who's nearby?" queries.
## Used by networking to only sync position updates to nearby players.
##
## See docs/MASSIVE_BATTLE_OPTIMIZATION.md for full spec.

const CELL_SIZE: float = 400.0  # Pixels per cell

var cells: Dictionary = {}  # Vector2i -> Array[int] (peer IDs)
var player_cells: Dictionary = {}  # peer_id -> Vector2i (current cell)
var player_positions: Dictionary = {}  # peer_id -> Vector2 (for distance checks)

# Debug stats
var _debug_enabled: bool = false


func update_player(peer_id: int, position: Vector2) -> void:
	"""Update a player's position in the grid. Call this every frame from movement."""
	var new_cell = Vector2i(int(position.x / CELL_SIZE), int(position.y / CELL_SIZE))
	var old_cell = player_cells.get(peer_id, Vector2i(-99999, -99999))

	# Always update position for distance checks
	player_positions[peer_id] = position

	if new_cell == old_cell:
		return

	# Remove from old cell
	if cells.has(old_cell):
		cells[old_cell].erase(peer_id)
		if cells[old_cell].is_empty():
			cells.erase(old_cell)

	# Add to new cell
	if not cells.has(new_cell):
		cells[new_cell] = []
	cells[new_cell].append(peer_id)
	player_cells[peer_id] = new_cell


func remove_player(peer_id: int) -> void:
	"""Remove a player from the grid (on disconnect)."""
	var cell = player_cells.get(peer_id)
	if cell and cells.has(cell):
		cells[cell].erase(peer_id)
		if cells[cell].is_empty():
			cells.erase(cell)
	player_cells.erase(peer_id)
	player_positions.erase(peer_id)


func get_nearby_peers(position: Vector2, radius: float) -> Array[int]:
	"""Get all peer IDs within radius of position. O(cells) not O(players)."""
	var results: Array[int] = []
	var center_cell = Vector2i(int(position.x / CELL_SIZE), int(position.y / CELL_SIZE))
	var cell_radius = int(ceil(radius / CELL_SIZE))

	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var check_cell = center_cell + Vector2i(dx, dy)
			if cells.has(check_cell):
				for peer_id in cells[check_cell]:
					# Fine-grained distance check for accuracy
					var peer_pos = player_positions.get(peer_id, Vector2.ZERO)
					if position.distance_to(peer_pos) <= radius:
						results.append(peer_id)

	return results


func get_nearby_peers_fast(position: Vector2, radius: float) -> Array[int]:
	"""Get all peer IDs in cells near position. No distance check - faster but less accurate."""
	var results: Array[int] = []
	var center_cell = Vector2i(int(position.x / CELL_SIZE), int(position.y / CELL_SIZE))
	var cell_radius = int(ceil(radius / CELL_SIZE))

	for dx in range(-cell_radius, cell_radius + 1):
		for dy in range(-cell_radius, cell_radius + 1):
			var check_cell = center_cell + Vector2i(dx, dy)
			if cells.has(check_cell):
				results.append_array(cells[check_cell])

	return results


func get_player_position(peer_id: int) -> Vector2:
	"""Get cached position for a peer. Returns Vector2.ZERO if not found."""
	return player_positions.get(peer_id, Vector2.ZERO)


func get_player_count() -> int:
	"""Get total number of tracked players."""
	return player_cells.size()


func get_cell_count() -> int:
	"""Get number of active cells."""
	return cells.size()


# ============================================
# DEBUG
# ============================================

func enable_debug(enabled: bool = true) -> void:
	"""Enable periodic debug logging."""
	_debug_enabled = enabled


func _process(_delta: float) -> void:
	if _debug_enabled and Engine.get_process_frames() % 60 == 0:
		print("[SpatialGrid] %d players in %d cells" % [player_cells.size(), cells.size()])


func get_stats() -> Dictionary:
	"""Get debug statistics."""
	var players_per_cell: Dictionary = {}
	for cell in cells:
		var count = cells[cell].size()
		if not players_per_cell.has(count):
			players_per_cell[count] = 0
		players_per_cell[count] += 1

	return {
		"total_players": player_cells.size(),
		"total_cells": cells.size(),
		"players_per_cell_distribution": players_per_cell
	}
