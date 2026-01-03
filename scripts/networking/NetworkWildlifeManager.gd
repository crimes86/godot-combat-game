extends Node
## NetworkWildlifeManager.gd - Server-authoritative wildlife management
##
## Handles:
## - Wildlife ID assignment and tracking (server only)
## - Server-side damage validation
## - Position sync to clients
## - Loot/carcass drops (server validated)
##
## Similar pattern to NetworkEnemyManager but for huntable wildlife

# Wildlife registry: network_id -> WildlifeAnimal node
var wildlife: Dictionary = {}  # Dictionary[int, WildlifeAnimal]
var next_wildlife_id: int = 1

# Position sync
const POSITION_SYNC_RATE: float = 0.1  # 10Hz (wildlife moves slower than enemies)
var position_sync_timer: float = 0.0

# Interest management - only sync wildlife near players
const SYNC_RADIUS: float = 3000.0  # Sync wildlife within this radius
const SPAWN_RADIUS: float = 3500.0  # Spawn wildlife within this radius
const DESPAWN_RADIUS: float = 4500.0  # Despawn beyond this

# Track which wildlife each client knows about: peer_id -> {network_id: true}
var client_known_wildlife: Dictionary = {}

# Client-side interpolation
var wildlife_target_positions: Dictionary = {}  # network_id -> Vector2
var wildlife_target_states: Dictionary = {}  # network_id -> state enum value

# Preloaded scenes
var RABBIT_SCENE: PackedScene = null
var FOX_SCENE: PackedScene = null


func _ready() -> void:
	# Preload wildlife scenes
	RABBIT_SCENE = load("res://scenes/wildlife/Rabbit.tscn")
	FOX_SCENE = load("res://scenes/wildlife/Fox.tscn")

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	# Initialize tracking for new client
	client_known_wildlife[peer_id] = {}


func _on_peer_disconnected(peer_id: int) -> void:
	client_known_wildlife.erase(peer_id)


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return

	if multiplayer.is_server():
		# Server: sync wildlife positions to clients
		position_sync_timer += delta
		if position_sync_timer >= POSITION_SYNC_RATE:
			position_sync_timer = 0.0
			_sync_wildlife_positions()
	else:
		# Client: interpolate wildlife positions
		_interpolate_wildlife_positions(delta)


# ═══════════════════════════════════════════════════════════════════════════
# SERVER: WILDLIFE REGISTRATION & SPAWNING
# ═══════════════════════════════════════════════════════════════════════════

func register_wildlife(animal: Node) -> int:
	"""Register wildlife and assign network ID. Server only."""
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return -1

	var id = next_wildlife_id
	next_wildlife_id += 1

	animal.set_meta("network_id", id)
	wildlife[id] = animal

	# Connect to death signal
	if animal.has_signal("animal_died"):
		animal.animal_died.connect(_on_wildlife_died.bind(id))

	return id


func unregister_wildlife(network_id: int) -> void:
	"""Remove wildlife from registry."""
	wildlife.erase(network_id)


func get_wildlife(network_id: int) -> Node:
	"""Get wildlife by network ID."""
	if not wildlife.has(network_id):
		return null
	var animal = wildlife[network_id]
	if not is_instance_valid(animal):
		wildlife.erase(network_id)
		return null
	return animal


func spawn_wildlife_server(animal_type: String, position: Vector2, parent: Node) -> Node:
	"""Server spawns wildlife and syncs to clients. Returns the spawned animal."""
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		push_error("spawn_wildlife_server called on client!")
		return null

	var scene: PackedScene = null
	match animal_type:
		"rabbit":
			scene = RABBIT_SCENE
		"fox":
			scene = FOX_SCENE
		_:
			push_warning("Unknown wildlife type: %s" % animal_type)
			return null

	if not scene:
		return null

	var animal = scene.instantiate()
	animal.global_position = position
	parent.add_child(animal)

	var network_id = register_wildlife(animal)

	# Notify nearby clients to spawn this animal
	_notify_clients_spawn(network_id, animal_type, position)

	return animal


func _notify_clients_spawn(network_id: int, animal_type: String, position: Vector2) -> void:
	"""Tell clients near this position to spawn the wildlife."""
	if not multiplayer.is_server():
		return

	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		if not is_instance_valid(player):
			continue

		var peer_id = player.get_multiplayer_authority()
		if peer_id == 1:  # Server's own player
			continue

		if player.global_position.distance_to(position) <= SPAWN_RADIUS:
			_client_spawn_wildlife.rpc_id(peer_id, network_id, animal_type, position)
			if not client_known_wildlife.has(peer_id):
				client_known_wildlife[peer_id] = {}
			client_known_wildlife[peer_id][network_id] = true


# ═══════════════════════════════════════════════════════════════════════════
# SERVER: POSITION SYNC
# ═══════════════════════════════════════════════════════════════════════════

func _sync_wildlife_positions() -> void:
	"""Server sends wildlife positions to nearby clients."""
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)

	for peer_id in client_known_wildlife:
		if peer_id == 1:
			continue

		# Find this peer's player
		var player: Node2D = null
		for p in players:
			if p.get_multiplayer_authority() == peer_id:
				player = p
				break

		if not player or not is_instance_valid(player):
			continue

		# Build position update for wildlife this client knows about
		var updates: Array = []
		var to_despawn: Array = []

		for network_id in client_known_wildlife[peer_id]:
			var animal = get_wildlife(network_id)
			if not animal:
				to_despawn.append(network_id)
				continue

			var distance = player.global_position.distance_to(animal.global_position)

			if distance > DESPAWN_RADIUS:
				to_despawn.append(network_id)
				continue

			if distance <= SYNC_RADIUS:
				updates.append({
					"id": network_id,
					"pos": animal.global_position,
					"state": animal.current_state,
					"facing": animal.facing_right
				})

		# Send position updates
		if updates.size() > 0:
			_client_sync_wildlife.rpc_id(peer_id, updates)

		# Send despawn commands
		for network_id in to_despawn:
			_client_despawn_wildlife.rpc_id(peer_id, network_id)
			client_known_wildlife[peer_id].erase(network_id)

	# Check for new wildlife to spawn for each client
	_check_spawn_new_wildlife_for_clients(players)


func _check_spawn_new_wildlife_for_clients(players: Array) -> void:
	"""Check if any wildlife should be spawned for clients that don't know about them."""
	for network_id in wildlife:
		var animal = wildlife[network_id]
		if not is_instance_valid(animal):
			continue

		for player in players:
			if not is_instance_valid(player):
				continue

			var peer_id = player.get_multiplayer_authority()
			if peer_id == 1:
				continue

			if not client_known_wildlife.has(peer_id):
				client_known_wildlife[peer_id] = {}

			# Already knows about this wildlife?
			if client_known_wildlife[peer_id].has(network_id):
				continue

			# Close enough to spawn?
			if player.global_position.distance_to(animal.global_position) <= SPAWN_RADIUS:
				_client_spawn_wildlife.rpc_id(peer_id, network_id, animal.animal_type, animal.global_position)
				client_known_wildlife[peer_id][network_id] = true


# ═══════════════════════════════════════════════════════════════════════════
# SERVER: DAMAGE & DEATH
# ═══════════════════════════════════════════════════════════════════════════

func request_damage_wildlife(network_id: int, damage: float, attacker_peer_id: int) -> void:
	"""Client requests to damage wildlife. Server validates and applies."""
	if not multiplayer.is_server():
		# Forward to server
		_server_damage_wildlife.rpc_id(1, network_id, damage)
		return

	_apply_damage_wildlife(network_id, damage, attacker_peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _server_damage_wildlife(network_id: int, damage: float) -> void:
	"""Server RPC: Client requests damage on wildlife."""
	var peer_id = multiplayer.get_remote_sender_id()
	_apply_damage_wildlife(network_id, damage, peer_id)


func _apply_damage_wildlife(network_id: int, damage: float, attacker_peer_id: int) -> void:
	"""Server applies damage to wildlife."""
	var animal = get_wildlife(network_id)
	if not animal:
		return

	# Validate damage is reasonable
	damage = clampf(damage, 0.0, 500.0)

	# Apply damage
	animal.take_damage(damage, null)

	# Sync to all clients who know about this wildlife
	for peer_id in client_known_wildlife:
		if peer_id == 1:
			continue
		if client_known_wildlife[peer_id].has(network_id):
			_client_wildlife_damaged.rpc_id(peer_id, network_id, animal.current_health)


func _on_wildlife_died(animal: WildlifeAnimal, _killer: Node, network_id: int) -> void:
	"""Server handles wildlife death - awards loot to killer."""
	if not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		return

	# Calculate loot
	var carcass_item = {
		"id": animal.carcass_item_id,
		"name": animal.animal_type.capitalize() + " Carcass",
		"type": "material",
		"quantity": 1,
		"quality": animal._calculate_pelt_quality()
	}

	# TODO: Award carcass to killer's inventory via backend
	print("[Server] Wildlife %d (%s) died. Carcass: %s" % [network_id, animal.animal_type, carcass_item])

	# Notify all clients to despawn
	for peer_id in client_known_wildlife:
		if peer_id == 1:
			continue
		if client_known_wildlife[peer_id].has(network_id):
			_client_wildlife_died.rpc_id(peer_id, network_id)
			client_known_wildlife[peer_id].erase(network_id)

	# Unregister
	unregister_wildlife(network_id)


# ═══════════════════════════════════════════════════════════════════════════
# CLIENT: SPAWN & SYNC RPCs
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_remote", "reliable")
func _client_spawn_wildlife(network_id: int, animal_type: String, position: Vector2) -> void:
	"""Client receives command to spawn wildlife."""
	if multiplayer.is_server():
		return

	# Don't spawn if we already have it
	if wildlife.has(network_id):
		return

	var scene: PackedScene = null
	match animal_type:
		"rabbit":
			scene = RABBIT_SCENE
		"fox":
			scene = FOX_SCENE

	if not scene:
		return

	var animal = scene.instantiate()
	animal.global_position = position
	animal.set_meta("network_id", network_id)
	animal.set_meta("is_client_copy", true)  # Mark as client-side copy

	# Add to current scene
	var game_world = get_tree().current_scene
	if game_world:
		game_world.add_child(animal)
		wildlife[network_id] = animal


@rpc("authority", "call_remote", "unreliable")
func _client_sync_wildlife(updates: Array) -> void:
	"""Client receives position updates for wildlife."""
	if multiplayer.is_server():
		return

	for update in updates:
		var network_id = update.get("id", -1)
		var pos = update.get("pos", Vector2.ZERO)
		var state = update.get("state", 0)
		var facing = update.get("facing", true)

		wildlife_target_positions[network_id] = pos
		wildlife_target_states[network_id] = state

		var animal = get_wildlife(network_id)
		if animal:
			animal.facing_right = facing
			# Update state if changed
			if animal.current_state != state:
				animal.current_state = state
				animal._play_animation(_state_to_animation(state))


@rpc("authority", "call_remote", "reliable")
func _client_despawn_wildlife(network_id: int) -> void:
	"""Client removes wildlife."""
	if multiplayer.is_server():
		return

	var animal = get_wildlife(network_id)
	if animal and is_instance_valid(animal):
		animal.queue_free()

	wildlife.erase(network_id)
	wildlife_target_positions.erase(network_id)
	wildlife_target_states.erase(network_id)


@rpc("authority", "call_remote", "reliable")
func _client_wildlife_damaged(network_id: int, new_health: float) -> void:
	"""Client updates wildlife health after server-validated damage."""
	if multiplayer.is_server():
		return

	var animal = get_wildlife(network_id)
	if animal:
		animal.current_health = new_health
		# Visual feedback
		animal._set_all_sprites_modulate(Color.RED)
		get_tree().create_timer(0.1).timeout.connect(animal._reset_sprite_modulate)


@rpc("authority", "call_remote", "reliable")
func _client_wildlife_died(network_id: int) -> void:
	"""Client plays death animation and removes wildlife."""
	if multiplayer.is_server():
		return

	var animal = get_wildlife(network_id)
	if animal and is_instance_valid(animal):
		animal.current_state = animal.State.DEAD
		# Fade out
		if animal.current_sprite:
			var tween = animal.create_tween()
			tween.tween_property(animal.current_sprite, "modulate:a", 0.0, 0.5)
			tween.tween_callback(animal.queue_free)
		else:
			animal.queue_free()

	wildlife.erase(network_id)
	wildlife_target_positions.erase(network_id)


# ═══════════════════════════════════════════════════════════════════════════
# CLIENT: INTERPOLATION
# ═══════════════════════════════════════════════════════════════════════════

func _interpolate_wildlife_positions(delta: float) -> void:
	"""Client smoothly interpolates wildlife toward server positions."""
	const LERP_SPEED: float = 8.0

	for network_id in wildlife_target_positions:
		var animal = get_wildlife(network_id)
		if not animal:
			continue

		var target_pos = wildlife_target_positions[network_id]
		var current_pos = animal.global_position
		var distance = current_pos.distance_to(target_pos)

		if distance < 1.0:
			animal.global_position = target_pos
			continue

		if distance > 300.0:
			animal.global_position = target_pos
			continue

		var t = clampf(delta * LERP_SPEED, 0.0, 1.0)
		animal.global_position = current_pos.lerp(target_pos, t)


func _state_to_animation(state: int) -> String:
	"""Convert state enum to animation name."""
	match state:
		0:  # IDLE
			return "idle"
		1:  # ROAMING
			return "walk"
		2:  # ALERT
			return "idle"
		3:  # FLEEING
			return "run"
		_:
			return "idle"
