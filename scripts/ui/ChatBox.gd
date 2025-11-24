extends Control
# Simple in-game chat system

@onready var chat_display = $VBoxContainer/ChatDisplay
@onready var chat_input = $VBoxContainer/ChatInput

var max_messages = 50
var messages = []

func _ready():
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)

	# Make chat semi-transparent
	modulate.a = 0.8

func _input(event):
	# Press Enter to open chat
	if event.is_action_pressed("chat"):
		if not chat_input.visible:
			chat_input.visible = true
			chat_input.grab_focus()
			chat_input.text = ""
		else:
			if chat_input.text.length() > 0:
				_send_message(chat_input.text)
			chat_input.visible = false
			chat_input.release_focus()

	# Press Escape to close chat
	if event.is_action_pressed("escape") and chat_input.visible:
		chat_input.visible = false
		chat_input.release_focus()

func _on_chat_submitted(text: String):
	if text.length() > 0:
		_send_message(text)
	chat_input.visible = false
	chat_input.release_focus()

func _send_message(text: String):
	# Sanitize message
	text = text.substr(0, 100).strip_edges()
	if text.length() == 0:
		return

	# Get player name
	var player_name = NetworkManager.player_name

	# Send via network
	rpc("receive_message", player_name, text)

@rpc("any_peer", "call_local", "reliable")
func receive_message(player_name: String, text: String):
	add_message("[%s]: %s" % [player_name, text])

func add_message(text: String):
	messages.append(text)

	# Limit message history
	if messages.size() > max_messages:
		messages.pop_front()

	# Update display
	chat_display.text = ""
	for msg in messages:
		chat_display.text += msg + "\n"

	# Auto-scroll to bottom
	chat_display.scroll_vertical = chat_display.get_v_scroll_bar().max_value

func add_system_message(text: String, color: Color = Color.YELLOW):
	add_message("[color=#%s]%s[/color]" % [color.to_html(), text])