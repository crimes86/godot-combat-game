extends CanvasLayer

## GroupInvitePopup - Themed popup for accepting/declining group invites
## Matches the game's dark fantasy stone gray UI style

signal invite_accepted(from_id: int)
signal invite_declined(from_id: int)

var popup_panel: PanelContainer = null
var from_peer_id: int = -1
var from_player_name: String = ""
var expire_timer: float = 0.0
var expire_duration: float = 60.0  # Match GroupManager.INVITE_TIMEOUT

# Styling constants (matching game UI theme)
const COLOR_BG: Color = Color(0.12, 0.12, 0.14, 0.95)
const COLOR_BORDER: Color = Color(0.35, 0.38, 0.42, 1.0)
const COLOR_TITLE: Color = Color(0.92, 0.92, 0.94, 1.0)
const COLOR_TEXT: Color = Color(0.8, 0.8, 0.82, 1.0)
const COLOR_ACCEPT: Color = Color(0.25, 0.5, 0.25, 1.0)
const COLOR_ACCEPT_HOVER: Color = Color(0.3, 0.6, 0.3, 1.0)
const COLOR_DECLINE: Color = Color(0.5, 0.25, 0.25, 1.0)
const COLOR_DECLINE_HOVER: Color = Color(0.6, 0.3, 0.3, 1.0)
const COLOR_BUTTON_TEXT: Color = Color(0.95, 0.95, 0.95, 1.0)

func _ready() -> void:
	layer = 120  # Above most UI
	_create_popup()
	visible = false

	# Connect to GroupManager signals
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager:
		group_manager.invite_received.connect(_on_invite_received)
		group_manager.invite_expired.connect(_on_invite_expired)
		group_manager.group_updated.connect(_on_group_updated)

func _process(delta: float) -> void:
	if not visible:
		return

	# Update expire timer
	expire_timer -= delta
	if expire_timer <= 0:
		_hide_popup()
		return

	# Update timer display
	var timer_label = popup_panel.get_node_or_null("Margin/VBox/TimerLabel")
	if timer_label:
		timer_label.text = "Expires in %d seconds" % int(expire_timer)

func _create_popup() -> void:
	"""Create the themed invite popup."""
	# Center container
	var center = Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -150
	center.offset_right = 150
	center.offset_top = -80
	center.offset_bottom = 80
	add_child(center)

	# Main panel
	popup_panel = PanelContainer.new()
	popup_panel.name = "InvitePanel"
	popup_panel.custom_minimum_size = Vector2(300, 160)
	center.add_child(popup_panel)

	# Panel style
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 8
	popup_panel.add_theme_stylebox_override("panel", style)

	# Margin container
	var margin = MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	popup_panel.add_child(margin)

	# VBox layout
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Title
	var title = Label.new()
	title.name = "TitleLabel"
	title.text = "GROUP INVITE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 2)
	vbox.add_child(title)

	# Invite message
	var message = Label.new()
	message.name = "MessageLabel"
	message.text = "PlayerName wants to invite you to their group."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(message)

	# Timer label
	var timer_label = Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "Expires in 60 seconds"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 11)
	timer_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	vbox.add_child(timer_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 5)
	vbox.add_child(spacer)

	# Button container
	var button_box = HBoxContainer.new()
	button_box.name = "ButtonBox"
	button_box.add_theme_constant_override("separation", 20)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_box)

	# Accept button
	var accept_btn = Button.new()
	accept_btn.name = "AcceptButton"
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(100, 36)
	accept_btn.pressed.connect(_on_accept_pressed)
	_style_button(accept_btn, COLOR_ACCEPT, COLOR_ACCEPT_HOVER)
	button_box.add_child(accept_btn)

	# Decline button
	var decline_btn = Button.new()
	decline_btn.name = "DeclineButton"
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(100, 36)
	decline_btn.pressed.connect(_on_decline_pressed)
	_style_button(decline_btn, COLOR_DECLINE, COLOR_DECLINE_HOVER)
	button_box.add_child(decline_btn)

func _style_button(button: Button, bg_color: Color, hover_color: Color) -> void:
	"""Apply themed style to a button."""
	# Normal style
	var normal = StyleBoxFlat.new()
	normal.bg_color = bg_color
	normal.border_color = bg_color.lightened(0.2)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal)

	# Hover style
	var hover = StyleBoxFlat.new()
	hover.bg_color = hover_color
	hover.border_color = hover_color.lightened(0.3)
	hover.border_width_left = 1
	hover.border_width_right = 1
	hover.border_width_top = 1
	hover.border_width_bottom = 1
	hover.corner_radius_top_left = 4
	hover.corner_radius_top_right = 4
	hover.corner_radius_bottom_left = 4
	hover.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("hover", hover)

	# Pressed style
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = bg_color.darkened(0.1)
	pressed.border_color = bg_color.lightened(0.1)
	pressed.border_width_left = 1
	pressed.border_width_right = 1
	pressed.border_width_top = 1
	pressed.border_width_bottom = 1
	pressed.corner_radius_top_left = 4
	pressed.corner_radius_top_right = 4
	pressed.corner_radius_bottom_left = 4
	pressed.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("pressed", pressed)

	# Text color
	button.add_theme_color_override("font_color", COLOR_BUTTON_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_BUTTON_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_BUTTON_TEXT.darkened(0.1))
	button.add_theme_font_size_override("font_size", 14)

func show_invite(from_id: int, from_name: String) -> void:
	"""Show the invite popup for a specific player."""
	from_peer_id = from_id
	from_player_name = from_name
	expire_timer = expire_duration

	# Update message text
	var message_label = popup_panel.get_node_or_null("Margin/VBox/MessageLabel")
	if message_label:
		message_label.text = "%s wants to invite you to their group." % from_name

	visible = true

	# Play a notification sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_sound_2d"):
		sound_manager.play_sound_2d(sound_manager.SoundType.ITEM_PICKUP, -5.0)

func _hide_popup() -> void:
	"""Hide the popup."""
	visible = false
	from_peer_id = -1
	from_player_name = ""

func _on_invite_received(from_id: int, from_name: String) -> void:
	"""Called when GroupManager receives an invite."""
	show_invite(from_id, from_name)

func _on_invite_expired(_from_name: String) -> void:
	"""Called when an invite expires."""
	_hide_popup()

func _on_group_updated() -> void:
	"""Called when group state changes - hide popup if we joined a group."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager and group_manager.has_group():
		_hide_popup()

func _on_accept_pressed() -> void:
	"""Handle accept button press."""
	if from_peer_id == -1:
		return

	# Use GroupManager to accept
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager:
		var result = group_manager.cmd_accept()
		# Show result in chat
		var chat_ui = get_node_or_null("/root/ChatUI")
		if chat_ui and chat_ui.has_method("add_system_message"):
			chat_ui.add_system_message(result)

	invite_accepted.emit(from_peer_id)
	_hide_popup()

func _on_decline_pressed() -> void:
	"""Handle decline button press."""
	if from_peer_id == -1:
		return

	# Use GroupManager to decline
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager:
		var result = group_manager.cmd_decline()
		# Show result in chat
		var chat_ui = get_node_or_null("/root/ChatUI")
		if chat_ui and chat_ui.has_method("add_system_message"):
			chat_ui.add_system_message(result)

	invite_declined.emit(from_peer_id)
	_hide_popup()

func _input(event: InputEvent) -> void:
	"""Handle keyboard shortcuts."""
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Y, KEY_ENTER:
				_on_accept_pressed()
				get_viewport().set_input_as_handled()
			KEY_N, KEY_ESCAPE:
				_on_decline_pressed()
				get_viewport().set_input_as_handled()
