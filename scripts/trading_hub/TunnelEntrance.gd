# TunnelEntrance.gd - Entry point to Trading Hub from Zone 1
extends Area2D

signal player_entered_tunnel(player: Node, origin_chunk: int)

const LEVEL_REQUIREMENT: int = 0  # No level requirement - open to all players
const TRIGGER_DISTANCE: float = 80.0  # How close player needs to be to enter

@export var chunk_id: int = 0  # Which Zone 1 chunk this entrance belongs to

var _player_in_range: Node = null
var _can_enter: bool = false
var _denial_cooldown: float = 0.0

# Static flag shared by all instances to prevent multiple transitions
static var _any_transitioning: bool = false

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var entrance_sprite: Sprite2D = $EntranceSprite
@onready var glow_light: PointLight2D = $GlowLight
@onready var interaction_label: Label = $InteractionLabel

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Set collision layer/mask for player detection
	collision_layer = 0
	collision_mask = 1  # Player layer

	# Hide interaction label initially
	if interaction_label:
		interaction_label.visible = false

	# Add subtle pulsing animation to the glow
	if glow_light:
		_start_glow_animation()

func _process(delta: float) -> void:
	# Don't process anything if ANY entrance is transitioning
	if _transitioning or _any_transitioning:
		return

	if _denial_cooldown > 0:
		_denial_cooldown -= delta

	# Check if player should enter (player walks into trigger zone near the entrance)
	if _player_in_range and _can_enter:
		var player = _player_in_range
		if is_instance_valid(player):
			var player_y = player.global_position.y
			var entrance_y = global_position.y
			# Trigger when player is within 20 pixels of entrance (or north of it)
			var trigger_threshold = entrance_y + 20

			# Trigger when player reaches the entrance area
			if player_y <= trigger_threshold:
				print("[TunnelEntrance] TRIGGERED! Player reached entrance (Y: %.1f <= %.1f)" % [player_y, trigger_threshold])
				_enter_tunnel(player)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	_player_in_range = body

	# Check level requirement
	var player_level = 1
	if body.has_method("get"):
		player_level = body.get("level") if body.get("level") else 1
	elif "level" in body:
		player_level = body.level

	if player_level >= LEVEL_REQUIREMENT:
		_can_enter = true
		_show_enter_prompt()
	else:
		_can_enter = false
		if _denial_cooldown <= 0:
			_show_level_requirement(player_level)
			_denial_cooldown = 3.0  # Don't spam the message

func _on_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null
		_can_enter = false
		_hide_prompt()

func _show_enter_prompt() -> void:
	if interaction_label:
		interaction_label.text = "Walk north to enter the tunnel..."
		interaction_label.visible = true
		interaction_label.modulate = Color(0.8, 0.9, 0.8, 1.0)

func _show_level_requirement(current_level: int) -> void:
	if interaction_label:
		interaction_label.text = "The darkness repels you...\nReturn when stronger (Lv %d required)" % LEVEL_REQUIREMENT
		interaction_label.visible = true
		interaction_label.modulate = Color(0.9, 0.6, 0.5, 1.0)

	# Also show floating text if available
	_spawn_denial_text("Level %d Required" % LEVEL_REQUIREMENT)

func _hide_prompt() -> void:
	if interaction_label:
		interaction_label.visible = false

func _spawn_denial_text(text: String) -> void:
	# Try to spawn combat text style floating message
	var combat_text_scene = load("res://scenes/ui/combat_text.tscn")
	if combat_text_scene:
		var combat_text = combat_text_scene.instantiate()
		get_tree().root.add_child(combat_text)
		combat_text.global_position = global_position + Vector2(0, -50)
		if combat_text.has_method("setup"):
			combat_text.setup(text, Color(0.9, 0.5, 0.4), false)

var _transitioning: bool = false  # Prevent multiple transitions

func _enter_tunnel(player: Node) -> void:
	if _transitioning or _any_transitioning:
		return  # Already transitioning

	_transitioning = true
	_any_transitioning = true  # Set static flag for all instances
	_can_enter = false  # Prevent re-entry while transitioning
	_hide_prompt()

	print("[TunnelEntrance] Player entering tunnel from chunk %d" % chunk_id)

	# Emit signal for any listeners
	player_entered_tunnel.emit(player, chunk_id)

	# Store the origin chunk and save player state for return trip
	if has_node("/root/TradingHubManager"):
		var hub_manager = get_node("/root/TradingHubManager")
		hub_manager.set_player_origin_chunk(chunk_id)
		hub_manager.save_player_state(player)  # Preserve health, etc.

	# Transition to trading hub scene
	_transition_to_hub()

func _transition_to_hub() -> void:
	print("[TunnelEntrance] Starting transition to hub...")

	# Use TradingHubManager autoload for scene change
	# The manager handles call_deferred internally
	var hub_manager = get_node_or_null("/root/TradingHubManager")
	if hub_manager:
		print("[TunnelEntrance] Delegating scene change to TradingHubManager...")
		hub_manager.transition_to_hub()
	else:
		push_error("[TunnelEntrance] TradingHubManager not found! Cannot transition.")

func _start_glow_animation() -> void:
	if not glow_light:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(glow_light, "energy", 0.6, 2.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow_light, "energy", 0.4, 2.0).set_trans(Tween.TRANS_SINE)

func _exit_tree() -> void:
	# Reset static flag when scene is destroyed (important for scene changes)
	_any_transitioning = false

# Called by game_world when spawning entrances dynamically
func setup(p_chunk_id: int) -> void:
	chunk_id = p_chunk_id
