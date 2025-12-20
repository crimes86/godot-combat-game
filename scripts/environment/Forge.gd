extends Area2D
## Interactive Forge Station for Trading Hub
## Click to open the forge UI for claiming playtest items

signal forge_opened

# Animation settings
const ANIMATION_FPS: float = 6.0  # Fire flicker speed

# Interaction
var _player_in_range: bool = false
var _is_highlighted: bool = false
var _is_lit: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var light: PointLight2D = $ForgeLight
@onready var interaction_label: Label = $InteractionLabel
@onready var smoke_particles: GPUParticles2D = $SmokeParticles
var _light_tween: Tween = null
var _base_modulate: Color = Color(0.75, 0.8, 0.85, 1)  # Gray stone tint

func _ready() -> void:
	add_to_group("forge")

	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Start unlit
	_set_lit_state(false)

	# Hide interaction label initially
	if interaction_label:
		interaction_label.visible = false

func _start_light_flicker() -> void:
	"""Animate the forge light for realistic fire effect"""
	if not light:
		return

	if _light_tween and _light_tween.is_valid():
		_light_tween.kill()

	light.energy = 0.8

	_light_tween = create_tween()
	_light_tween.set_loops()
	_light_tween.tween_property(light, "energy", 1.0, 0.15).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(light, "energy", 0.7, 0.1).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(light, "energy", 0.9, 0.2).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(light, "energy", 0.6, 0.15).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(light, "energy", 0.85, 0.12).set_trans(Tween.TRANS_SINE)

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
		interaction_label.text = "[F] Light Forge" if not _is_lit else "[F] Use Forge"

	# Brighten forge slightly when player nearby (keep gray tint)
	if sprite:
		sprite.modulate = Color(_base_modulate.r * 1.15, _base_modulate.g * 1.15, _base_modulate.b * 1.1, 1)

func _hide_interaction_prompt() -> void:
	if interaction_label:
		interaction_label.visible = false

	# Return to base gray stone tint
	if sprite:
		sprite.modulate = _base_modulate

func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return

	# Check for interaction key (F or interact action)
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_F):
		if not _is_lit:
			_light_forge()
		else:
			_open_forge()
		get_viewport().set_input_as_handled()

func _light_forge() -> void:
	_is_lit = true
	_set_lit_state(true)
	if interaction_label:
		interaction_label.text = "[F] Use Forge"

	# Play fire lighting sound
	if SoundManager and SoundManager.has_method("play_fire_fuel_sound"):
		SoundManager.play_fire_fuel_sound(global_position, -8.0)

func _open_forge() -> void:
	"""Open the forge UI"""
	if not _is_lit:
		return
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

func _set_lit_state(lit: bool) -> void:
	_is_lit = lit
	if sprite:
		sprite.play("lit" if lit else "unlit")
	if light:
		light.visible = lit
		light.energy = 0.0 if not lit else light.energy
	if smoke_particles:
		smoke_particles.emitting = lit
	if lit:
		_start_light_flicker()
	elif _light_tween and _light_tween.is_valid():
		_light_tween.kill()
