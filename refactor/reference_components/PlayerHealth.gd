extends Node
class_name PlayerHealth

## Handles player health, damage, healing, death, and respawn
## Separated from Player.gd for modularity

signal health_changed(current: float, maximum: float)
signal died()
signal respawned()

@export var respawn_position: Vector2 = Vector2(400, 0)

var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false

var player_body: CharacterBody2D
var health_bar: Control
var player_sprite: AnimatedSprite2D

func _ready() -> void:
	player_body = get_parent() as CharacterBody2D
	if not player_body:
		push_error("PlayerHealth must be a child of CharacterBody2D")
		return

	# Find health bar and sprite
	health_bar = player_body.get_node_or_null("HealthBar")
	player_sprite = player_body.get_node_or_null("PlayerSprite")

	# Initialize to max health
	current_health = max_health
	if health_bar:
		health_bar.update_health(current_health, max_health)

func set_max_health(value: float) -> void:
	"""Set maximum health and update current if needed"""
	max_health = value
	if current_health > max_health:
		current_health = max_health
	_update_health_bar()

func take_damage(amount: float) -> void:
	"""Apply damage to player"""
	if is_dead:
		return

	print("Player taking %.1f damage (current: %.1f)" % [amount, current_health])
	current_health -= amount

	# Ensure health doesn't go below 0
	if current_health < 0:
		current_health = 0

	_update_health_bar()

	# Spawn damage number at player position
	CombatText.create_damage(amount, player_body.global_position, player_body.get_tree().root)

	print("Player health now: %.1f / %.1f" % [current_health, max_health])

	# Flash player sprite red when hit
	flash_sprite()

	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		print("💀 Player death triggered!")
		die()

func heal(amount: float) -> void:
	"""Heal the player by the given amount"""
	if current_health >= max_health:
		return  # Already at full health

	var actual_heal: float = min(amount, max_health - current_health)
	current_health += actual_heal

	_update_health_bar()

	# Spawn heal number at player position
	CombatText.create_heal(actual_heal, player_body.global_position, player_body.get_tree().root)

	print("Player healed %.1f HP (now %.1f / %.1f)" % [actual_heal, current_health, max_health])

	health_changed.emit(current_health, max_health)

func flash_sprite() -> void:
	"""Flash the player sprite red when taking damage"""
	if not player_sprite:
		player_sprite = player_body.get_node_or_null("PlayerSprite")
		if not player_sprite:
			return

	# Flash red
	player_sprite.modulate = Color(2.0, 0.5, 0.5, 1.0)

	# Restore to white after short delay
	await player_body.get_tree().create_timer(0.1).timeout

	if player_sprite and is_instance_valid(player_sprite):
		player_sprite.modulate = Color.WHITE

func die() -> void:
	"""Handle player death"""
	if is_dead:
		print("⚠️  Already dead, ignoring duplicate die() call")
		return

	is_dead = true
	print("\n💀 ===== PLAYER DEATH =====")
	print("Position: ", player_body.global_position)
	print("Remaining health: ", current_health)

	# Disable player controls during death
	player_body.set_physics_process(false)

	# Play death animation (hurt animation) and wait for it to complete
	if player_sprite and player_sprite.sprite_frames:
		if player_sprite.sprite_frames.has_animation("hurt"):
			print("   🎬 Playing death (hurt) animation...")
			player_sprite.stop()
			player_sprite.play("hurt")

			# Wait for animation to finish OR timeout after 1 second
			await player_sprite.animation_finished
			print("   ✅ Death animation complete")
		else:
			print("   ⚠️ No 'hurt' animation found")
			await player_body.get_tree().create_timer(0.5).timeout
	else:
		print("   ⚠️ No AnimatedSprite2D found, waiting 0.5s...")
		await player_body.get_tree().create_timer(0.5).timeout

	# Deaggro ALL enemies
	var all_enemies: Array = player_body.get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in all_enemies:
		if enemy.has_node("EnemyAI"):
			var ai: Node = enemy.get_node("EnemyAI")
			if ai.has_method("reset_to_patrol"):
				ai.reset_to_patrol()

	print("🔄 All enemies deaggroed")

	# Reset player position to spawn point
	player_body.global_position = respawn_position
	player_body.velocity = Vector2.ZERO

	# Restore health (but keep XP, level, stats, weapons)
	current_health = max_health
	_update_health_bar()

	# Re-enable player controls
	player_body.set_physics_process(true)

	# Reset death flag
	is_dead = false

	print("✨ Player respawned at ", respawn_position)
	print("   Stats preserved: Level %d, XP: %d" % [CharacterStats.level, CharacterStats.experience])
	print("==================\n")

	died.emit()
	respawned.emit()

func get_health_percent() -> float:
	"""Get health as percentage (0.0 to 1.0)"""
	if max_health <= 0:
		return 0.0
	return current_health / max_health

func is_at_full_health() -> bool:
	"""Check if at maximum health"""
	return current_health >= max_health

func _update_health_bar() -> void:
	"""Update health bar display"""
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
