extends CanvasLayer

## DuelCountdownUI - Shows 3-2-1-FIGHT countdown before duel starts

@onready var background: ColorRect = $Background
@onready var vs_label: Label = $Background/VBoxContainer/VsLabel
@onready var countdown_label: Label = $Background/VBoxContainer/CountdownLabel
@onready var sub_label: Label = $Background/VBoxContainer/SubLabel

var is_showing: bool = false
var fight_display_timer: float = 0.0

func _ready() -> void:
	background.visible = false

	# Connect to DuelManager signals
	if DuelManager:
		DuelManager.countdown_tick.connect(_on_countdown_tick)
		DuelManager.duel_started.connect(_on_duel_started)
		DuelManager.duel_cancelled.connect(_on_duel_cancelled)

func _process(delta: float) -> void:
	if fight_display_timer > 0:
		fight_display_timer -= delta
		if fight_display_timer <= 0:
			_hide_countdown()

func _on_countdown_tick(player1_id: int, player2_id: int, seconds: int) -> void:
	if not is_showing:
		_show_countdown(player1_id, player2_id)

	countdown_label.text = str(seconds)

	# Scale animation for countdown numbers
	_animate_countdown_number()

func _on_duel_started(_player1_id: int, _player2_id: int) -> void:
	countdown_label.text = "FIGHT!"
	countdown_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
	sub_label.text = "First to 1 HP loses!"
	_animate_countdown_number()

	# Show "FIGHT!" for 1.5 seconds then hide
	fight_display_timer = 1.5

func _on_duel_cancelled(_p1: int, _p2: int, _reason: String) -> void:
	_hide_countdown()

func _show_countdown(player1_id: int, player2_id: int) -> void:
	is_showing = true
	background.visible = true

	# Get player names
	var p1_name = _get_player_name(player1_id)
	var p2_name = _get_player_name(player2_id)
	vs_label.text = "%s vs %s" % [p1_name, p2_name]
	sub_label.text = "Prepare for battle!"

	# Reset countdown label color
	countdown_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))

func _hide_countdown() -> void:
	is_showing = false
	background.visible = false
	fight_display_timer = 0.0

func _animate_countdown_number() -> void:
	# Simple scale punch animation
	var tween = create_tween()
	countdown_label.scale = Vector2(1.3, 1.3)
	countdown_label.pivot_offset = countdown_label.size / 2
	tween.tween_property(countdown_label, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _get_player_name(player_id: int) -> String:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.connected_players.has(player_id):
		return network_manager.connected_players[player_id].get("name", "Player%d" % player_id)
	return "Player%d" % player_id
