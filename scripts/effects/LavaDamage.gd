extends Area2D

## Handles lava pool damage for players who step too close to the center
## Only damages players within 60% of the pool radius (safe on edges)

@export var damage_per_second: float = 15.0  # Lava damage rate
@export var damage_interval: float = 0.5  # Apply damage every 0.5 seconds

var player_in_lava = false
var damage_timer: float = 0.0

func _ready():
	# Set collision layers
	collision_layer = 0  # Don't exist on any layer
	collision_mask = 1  # Detect layer 1 (player)

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta):
	if player_in_lava:
		damage_timer += delta

		# Apply damage at intervals
		if damage_timer >= damage_interval:
			damage_timer = 0.0
			apply_lava_damage()

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_lava = true
		damage_timer = 0.0  # Start damage immediately

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_lava = false
		damage_timer = 0.0

func apply_lava_damage():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("take_damage"):
		var damage = damage_per_second * damage_interval
		player.take_damage(damage)
		print("🔥 Player taking %.1f lava damage" % damage)
