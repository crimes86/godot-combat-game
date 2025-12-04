extends CanvasLayer

## DuelResultUI - Shows VICTORY/DEFEAT announcement after duel ends

@onready var background: ColorRect = $Background
@onready var result_label: Label = $Background/VBoxContainer/ResultLabel
@onready var sub_label: Label = $Background/VBoxContainer/SubLabel
@onready var aura_label: Label = $Background/VBoxContainer/AuraLabel

var display_timer: float = 0.0
const DISPLAY_DURATION: float = 3.0

func _ready() -> void:
	background.visible = false

	# Connect to DuelManager signals
	if DuelManager:
		DuelManager.duel_ended.connect(_on_duel_ended)

func _process(delta: float) -> void:
	if display_timer > 0:
		display_timer -= delta
		if display_timer <= 0:
			_hide_result()

func _on_duel_ended(winner_id: int, loser_id: int) -> void:
	var my_id = -1
	if multiplayer.has_multiplayer_peer():
		my_id = multiplayer.get_unique_id()

	var is_winner = (my_id == winner_id)
	var opponent_id = loser_id if is_winner else winner_id
	var opponent_name = _get_player_name(opponent_id)

	if is_winner:
		result_label.text = "VICTORY!"
		result_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3, 1))
		sub_label.text = "You defeated %s" % opponent_name
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		sub_label.text = "%s won the duel" % opponent_name

	aura_label.text = "Safe aura active for %d seconds" % int(DuelManager.SAFE_AURA_DURATION)

	_show_result()

func _show_result() -> void:
	background.visible = true
	display_timer = DISPLAY_DURATION

	# Animate result label
	var tween = create_tween()
	result_label.scale = Vector2(0.5, 0.5)
	result_label.pivot_offset = result_label.size / 2
	tween.tween_property(result_label, "scale", Vector2(1, 1), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_result() -> void:
	background.visible = false

func _get_player_name(player_id: int) -> String:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.connected_players.has(player_id):
		return network_manager.connected_players[player_id].get("name", "Player%d" % player_id)
	return "Player%d" % player_id
