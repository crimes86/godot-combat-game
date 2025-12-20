extends Area2D

## Handles lava pool damage and movement debuff for players
## Damages players within the collision area and slows movement by 50%

@export var damage_per_second: float = 15.0  # Lava damage rate
@export var damage_interval: float = 0.5  # Apply damage every 0.5 seconds
@export var movement_debuff: float = 0.5  # 50% movement speed reduction

var players_in_lava: Dictionary = {}  # player -> damage_timer

func _ready():
	# Set collision layers
	collision_layer = 0  # Don't exist on any layer
	collision_mask = 1  # Detect layer 1 (player)

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta):
	# Process damage for all players in lava
	for player in players_in_lava.keys():
		if not is_instance_valid(player):
			players_in_lava.erase(player)
			continue

		players_in_lava[player] += delta

		# Apply damage at intervals
		if players_in_lava[player] >= damage_interval:
			players_in_lava[player] = 0.0
			apply_lava_damage(player)

func _on_body_entered(body):
	if body.is_in_group("player"):
		players_in_lava[body] = 0.0  # Start damage timer

		# Apply movement debuff
		if body.has_method("apply_movement_modifier"):
			body.apply_movement_modifier("lava", movement_debuff)
			print("🔥 Player entered lava - 50%% movement slow applied")

		# Visual feedback - tint player orange
		if body.has_node("CharacterSprite"):
			var sprite = body.get_node("CharacterSprite")
			sprite.modulate = Color(1.0, 0.7, 0.5, 1.0)

		# Notify QuestManager - "explore lava_pool" objective
		var quest_manager = get_node_or_null("/root/QuestManager")
		if quest_manager and quest_manager.has_method("on_location_discovered"):
			quest_manager.on_location_discovered("lava_pool")

func _on_body_exited(body):
	if body.is_in_group("player"):
		players_in_lava.erase(body)

		# Remove movement debuff
		if body.has_method("remove_movement_modifier"):
			body.remove_movement_modifier("lava")
			print("🔥 Player exited lava - movement restored")

		# Remove visual tint
		if body.has_node("CharacterSprite"):
			var sprite = body.get_node("CharacterSprite")
			sprite.modulate = Color.WHITE

func apply_lava_damage(player: Node):
	if player and player.has_method("take_damage"):
		var damage = damage_per_second * damage_interval
		player.take_damage(damage)
		print("🔥 Player taking %.1f lava damage" % damage)

		# Play lava burn sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager and sound_manager.has_method("play_lava_burn_sound"):
			sound_manager.play_lava_burn_sound(player.global_position, -8.0)
