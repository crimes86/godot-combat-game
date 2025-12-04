extends CanvasLayer

## DuelRequestPopup - Shows accept/decline UI when receiving a duel request

@onready var panel: Panel = $Panel
@onready var challenge_label: Label = $Panel/VBoxContainer/ChallengeLabel
@onready var timer_label: Label = $Panel/VBoxContainer/TimerLabel
@onready var accept_button: Button = $Panel/VBoxContainer/ButtonContainer/AcceptButton
@onready var decline_button: Button = $Panel/VBoxContainer/ButtonContainer/DeclineButton

var challenger_id: int = -1
var challenger_name: String = ""
var time_remaining: float = 30.0

func _ready() -> void:
	panel.visible = false
	accept_button.pressed.connect(_on_accept_pressed)
	decline_button.pressed.connect(_on_decline_pressed)

	# Connect to DuelManager signals
	if DuelManager:
		DuelManager.request_received.connect(_on_request_received)
		DuelManager.request_expired.connect(_on_request_expired)
		DuelManager.duel_accepted.connect(_on_duel_accepted)
		DuelManager.duel_declined.connect(_on_duel_declined)

func _process(delta: float) -> void:
	if not panel.visible:
		return

	time_remaining -= delta
	if time_remaining <= 0:
		_hide_popup()
		return

	timer_label.text = "Expires in %ds" % int(time_remaining)

func _on_request_received(from_id: int, from_name: String) -> void:
	challenger_id = from_id
	challenger_name = from_name
	time_remaining = DuelManager.DUEL_REQUEST_TIMEOUT

	challenge_label.text = "%s challenges you!" % challenger_name
	timer_label.text = "Expires in %ds" % int(time_remaining)
	panel.visible = true

func _on_request_expired(_name: String) -> void:
	if panel.visible:
		_hide_popup()

func _on_duel_accepted(_p1: int, _p2: int) -> void:
	_hide_popup()

func _on_duel_declined(_challenger: int, _target: int) -> void:
	_hide_popup()

func _on_accept_pressed() -> void:
	if DuelManager:
		var result = DuelManager.accept_duel()
		if result.success:
			if NotificationManager:
				NotificationManager.show_notification(result.message, "SUCCESS")
		else:
			if NotificationManager:
				NotificationManager.show_notification(result.message, "WARNING")
	_hide_popup()

func _on_decline_pressed() -> void:
	if DuelManager:
		DuelManager.decline_duel()
	_hide_popup()

func _hide_popup() -> void:
	panel.visible = false
	challenger_id = -1
	challenger_name = ""
