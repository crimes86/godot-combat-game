extends Area2D
## Interactive Forge Station for Trading Hub
## Click to open the forge UI for claiming playtest items

signal forge_opened

# Animation settings
const ANIMATION_FPS: float = 6.0  # Fire flicker speed

# Interaction
var _player_in_range: bool = false
var _is_highlighted: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var light: PointLight2D = $ForgeLight
@onready var interaction_label: Label = $InteractionLabel

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Start fire animation
	if sprite:
		sprite.play("burn")

	# Start light flicker
	_start_light_flicker()

	# Hide interaction label initially
	if interaction_label:
		interaction_label.visible = false

func _start_light_flicker() -> void:
	"""Animate the forge light for realistic fire effect"""
	if not light:
		return

	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(light, "energy", 1.8, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "energy", 1.4, 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "energy", 1.7, 0.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "energy", 1.3, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "energy", 1.6, 0.12).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_show_interaction_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_hide_interaction_prompt()

func _show_interaction_prompt() -> void:
	if interaction_label:
		interaction_label.visible = true
		interaction_label.text = "[F] Use Forge"

	# Brighten forge slightly when player nearby
	if sprite:
		sprite.modulate = Color(1.1, 1.1, 1.0)

func _hide_interaction_prompt() -> void:
	if interaction_label:
		interaction_label.visible = false

	# Return to normal brightness
	if sprite:
		sprite.modulate = Color.WHITE

func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return

	# Check for interaction key (F or interact action)
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_F):
		_open_forge()
		get_viewport().set_input_as_handled()

func _open_forge() -> void:
	"""Open the forge UI"""
	print("[Forge] Opening forge UI...")

	# Play sound effect
	if SoundManager:
		SoundManager.play_sound_2d(SoundManager.SoundType.BLACKSMITH_OPEN)

	# Emit signal for any listeners
	forge_opened.emit()

	# Open the BlacksmithForgeUI
	var forge_ui_script = load("res://scripts/ui/BlacksmithForgeUI.gd")
	if forge_ui_script:
		var forge_ui = CanvasLayer.new()
		forge_ui.set_script(forge_ui_script)
		get_tree().root.add_child(forge_ui)
		forge_ui.closed.connect(_on_forge_ui_closed)
	else:
		push_error("[Forge] Could not load BlacksmithForgeUI")

func _on_forge_ui_closed() -> void:
	"""Handle forge UI closing"""
	print("[Forge] Forge UI closed")
