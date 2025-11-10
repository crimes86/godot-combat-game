extends Node2D

## Simple Enemy Spawner
## Spawns and maintains a set number of enemies with auto-respawn

# Settings
@export var respawn_delay: float = 3.0
@export var enemy_scene: PackedScene
@export var max_enemies: int = 4  # Total number of enemies to maintain

# Tracking
var spawn_positions: Array[Vector2] = []
var enemy_at_position: Dictionary = {}  # spawn_index -> enemy node
var respawn_queue: Array[int] = []  # Positions waiting to respawn

func _ready() -> void:
	print("\n🔄 Enemy Spawner Ready")
	
	if not enemy_scene:
		push_error("❌ No enemy scene! Drag enemy.tscn to Enemy Scene property")
		return
	
	print("✅ Enemy Scene: ", enemy_scene.resource_path)
	
	# Collect spawn positions from Marker2D children
	for child in get_children():
		if child is Marker2D:
			spawn_positions.append(child.global_position)
	
	# Use default positions if no markers
	if spawn_positions.is_empty():
		print("⚠️  No Marker2D children, using grid layout")
		# Create a 2x2 grid
		spawn_positions = [
			global_position + Vector2(150, 100),
			global_position + Vector2(350, 100),
			global_position + Vector2(150, 300),
			global_position + Vector2(350, 300)
		]
	
	max_enemies = min(max_enemies, spawn_positions.size())
	print("🎯 Spawning ", max_enemies, " enemies\n")
	
	# Spawn initial enemies
	for i in max_enemies:
		spawn_enemy_at(i)

func spawn_enemy_at(spawn_index: int, is_respawn: bool = false) -> void:
	if spawn_index >= spawn_positions.size():
		return
	
	# Don't spawn if position already occupied
	if enemy_at_position.has(spawn_index) and is_instance_valid(enemy_at_position[spawn_index]):
		print("⚠️  Position ", spawn_index, " already occupied, skipping")
		return
	
	if is_respawn:
		print("✨ Respawning enemy at position ", spawn_index)
	else:
		print("✨ Spawning enemy at position ", spawn_index)
	
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_positions[spawn_index]
	
	# Store spawn index on enemy for tracking
	enemy.set_meta("spawn_index", spawn_index)
	
	# Use call_deferred to ensure proper scene tree addition
	get_parent().call_deferred("add_child", enemy)
	
	# Wait for enemy to be added to tree before connecting signals
	await get_tree().process_frame
	
	if is_instance_valid(enemy) and enemy.is_inside_tree():
		# Connect to died signal (preferred) or tree_exited
		if enemy.has_signal("died"):
			enemy.died.connect(func(): _on_enemy_died(spawn_index))
		else:
			enemy.tree_exited.connect(func(): _on_enemy_died(spawn_index))
		
		enemy_at_position[spawn_index] = enemy
		print("  Enemy: ", enemy.name, " at ", enemy.global_position, " [TRACKED]")
		
		# Only reset AI on respawn (not initial spawn)
		if is_respawn and enemy.has_node("EnemyAI"):
			# Wait another frame for EnemyAI._ready() to complete
			await get_tree().process_frame
			var ai = enemy.get_node("EnemyAI")
			if ai and ai.has_method("reset_to_patrol"):
				ai.reset_to_patrol()
		
		# Play spawn sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound(sound_manager.SoundType.ENEMY_SPAWN, enemy.global_position, -5.0)
	else:
		print("  ⚠️ Enemy not in tree, spawn failed")

func _on_enemy_died(spawn_index: int) -> void:
	# Check if spawner is still in tree
	if not is_inside_tree():
		return
	
	# Check if already queued for respawn
	if respawn_queue.has(spawn_index):
		return
	
	print("\n☠️  Enemy died at position ", spawn_index)
	print("⏱️  Respawning in ", respawn_delay, " seconds...")
	
	# Remove from tracking
	if enemy_at_position.has(spawn_index):
		enemy_at_position.erase(spawn_index)
	
	respawn_queue.append(spawn_index)
	
	# Wait and respawn (with safety check)
	if is_inside_tree():
		await get_tree().create_timer(respawn_delay).timeout
	else:
		return
	
	# Double-check we're still in tree after await
	if not is_inside_tree():
		return
	
	print("✅ Respawning at position ", spawn_index)
	respawn_queue.erase(spawn_index)
	spawn_enemy_at(spawn_index, true)  # is_respawn = true

func deaggro_all_enemies() -> void:
	"""Called when player dies - reset all enemies to patrol"""
	print("💤 Deaggroing all enemies...")
	for enemy in enemy_at_position.values():
		if is_instance_valid(enemy) and enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			if ai.has_method("reset_to_patrol"):
				ai.reset_to_patrol()
