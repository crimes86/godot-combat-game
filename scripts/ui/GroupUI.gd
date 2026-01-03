extends CanvasLayer

## GroupUI - WoW-style raid frames showing group members
## Displays on the left side of screen with player names and health bars
## Updates in real-time as group membership and health changes
## Also handles invite popup (merged from GroupInvitePopup)

# Signals for invite popup
signal invite_accepted(from_id: int)
signal invite_declined(from_id: int)

# UI References
var group_container: VBoxContainer = null
var member_frames: Dictionary = {}  # peer_id -> MemberFrame

# Invite popup references
var popup_panel: PanelContainer = null
var popup_container: Control = null  # Separate container for popup
var from_peer_id: int = -1
var from_player_name: String = ""
var expire_timer: float = 0.0
var expire_duration: float = 60.0  # Match GroupManager.INVITE_TIMEOUT

# Styling constants - compact frames
const FRAME_WIDTH: float = 120.0
const FRAME_HEIGHT: float = 40.0
const FRAME_SPACING: float = 2.0
const HEALTH_BAR_HEIGHT: float = 8.0
const MARGIN_LEFT: float = 10.0
const MARGIN_TOP: float = 100.0  # Below Level/XP display

# Stone Gray UI Palette (matching ChatUI/CharacterUI)
const COLOR_BACKGROUND: Color = Color(0.12, 0.12, 0.14, 0.9)  # Dark stone gray
const COLOR_BORDER: Color = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const COLOR_BORDER_LEADER: Color = Color(1.0, 0.85, 0.3, 1.0)  # Gold for leader
const COLOR_BORDER_SELF: Color = Color(0.4, 0.8, 1.0, 1.0)  # Cyan for self
const COLOR_NAME: Color = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const COLOR_NAME_LEADER: Color = Color(1.0, 0.85, 0.3, 1.0)  # Gold for leader star
const COLOR_HEALTH_HIGH: Color = Color(0.3, 0.75, 0.35, 1.0)  # Green
const COLOR_HEALTH_MID: Color = Color(0.85, 0.75, 0.2, 1.0)  # Yellow
const COLOR_HEALTH_LOW: Color = Color(0.85, 0.25, 0.2, 1.0)  # Red
const COLOR_HEALTH_BG: Color = Color(0.06, 0.06, 0.08, 1.0)  # Dark inset

# Invite popup colors
const COLOR_POPUP_BG: Color = Color(0.12, 0.12, 0.14, 0.95)
const COLOR_POPUP_TEXT: Color = Color(0.8, 0.8, 0.82, 1.0)
const COLOR_ACCEPT: Color = Color(0.25, 0.5, 0.25, 1.0)
const COLOR_ACCEPT_HOVER: Color = Color(0.3, 0.6, 0.3, 1.0)
const COLOR_DECLINE: Color = Color(0.5, 0.25, 0.25, 1.0)
const COLOR_DECLINE_HOVER: Color = Color(0.6, 0.3, 0.3, 1.0)
const COLOR_BUTTON_TEXT: Color = Color(0.95, 0.95, 0.95, 1.0)

func _ready() -> void:
	# Skip UI creation in headless mode (dedicated server)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return

	layer = 100  # Above game, below menus
	_create_ui()
	_create_invite_popup()
	_connect_signals()
	visible = false  # Hidden until in a group

func _create_ui() -> void:
	"""Create the group UI container."""
	# Main container positioned on left side
	var control = Control.new()
	control.name = "GroupUIControl"
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.offset_left = MARGIN_LEFT
	control.offset_top = MARGIN_TOP
	control.offset_right = MARGIN_LEFT + FRAME_WIDTH
	control.offset_bottom = MARGIN_TOP + 400  # Max height
	add_child(control)

	# VBox for stacking member frames
	group_container = VBoxContainer.new()
	group_container.name = "GroupContainer"
	group_container.add_theme_constant_override("separation", int(FRAME_SPACING))
	control.add_child(group_container)

func _connect_signals() -> void:
	"""Connect to GroupManager signals."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if group_manager:
		group_manager.group_updated.connect(_on_group_updated)
		group_manager.group_disbanded.connect(_on_group_disbanded)
		group_manager.invite_received.connect(_on_invite_received)
		group_manager.invite_expired.connect(_on_invite_expired)

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	# Use Engine.get_main_loop() to safely access autoloads even if node is outside scene tree
	var scene_tree = Engine.get_main_loop() as SceneTree
	var group_manager = null
	if scene_tree and scene_tree.root:
		group_manager = scene_tree.root.get_node_or_null("GroupManager")
	if group_manager:
		if group_manager.group_updated.is_connected(_on_group_updated):
			group_manager.group_updated.disconnect(_on_group_updated)
		if group_manager.group_disbanded.is_connected(_on_group_disbanded):
			group_manager.group_disbanded.disconnect(_on_group_disbanded)
		if group_manager.invite_received.is_connected(_on_invite_received):
			group_manager.invite_received.disconnect(_on_invite_received)
		if group_manager.invite_expired.is_connected(_on_invite_expired):
			group_manager.invite_expired.disconnect(_on_invite_expired)

func _process(delta: float) -> void:
	"""Update health bars and invite popup timer."""
	# Update member health if group frames visible
	if visible:
		_update_member_health()

	# Update invite popup timer
	if popup_container and popup_container.visible:
		expire_timer -= delta
		if expire_timer <= 0:
			_hide_popup()
		else:
			# Update timer display
			var timer_label = popup_panel.get_node_or_null("Margin/VBox/TimerLabel")
			if timer_label:
				timer_label.text = "Expires in %d seconds" % int(expire_timer)

func _on_group_updated() -> void:
	"""Called when group membership changes."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		return

	if group_manager.has_group():
		visible = true
		_rebuild_frames()
		_hide_popup()  # Hide invite popup when we join a group
	else:
		visible = false
		_clear_frames()

func _on_group_disbanded() -> void:
	"""Called when the group is disbanded."""
	visible = false
	_clear_frames()

func _on_invite_received(from_id: int, from_name: String) -> void:
	"""Show invite popup and chat notification."""
	# Show chat notification as fallback
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("Group invite from %s - type /accept or /decline" % from_name)

	# Show popup
	show_invite(from_id, from_name)

func _on_invite_expired(_from_name: String) -> void:
	"""Called when an invite expires."""
	_hide_popup()

func _rebuild_frames() -> void:
	"""Rebuild all member frames based on current group."""
	_clear_frames()

	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		return

	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1

	for member_id in group_manager.group_members:
		var member_name = group_manager.get_member_name(member_id)
		var is_leader = member_id == group_manager.group_leader
		var is_self = member_id == my_id

		var frame = _create_member_frame(member_id, member_name, is_leader, is_self)
		group_container.add_child(frame)
		member_frames[member_id] = frame

func _clear_frames() -> void:
	"""Remove all member frames."""
	for child in group_container.get_children():
		child.queue_free()
	member_frames.clear()

func _create_member_frame(peer_id: int, player_name: String, is_leader: bool, is_self: bool) -> PanelContainer:
	"""Create a single member frame with name and health bar."""
	var frame = PanelContainer.new()
	frame.name = "MemberFrame_%d" % peer_id
	frame.custom_minimum_size = Vector2(FRAME_WIDTH, FRAME_HEIGHT)

	# Panel style - matching stone gray theme
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_BACKGROUND
	style.border_width_left = 2
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1

	# Border color based on role - self gets cyan highlight, leader gets gold
	if is_self and is_leader:
		style.border_color = COLOR_BORDER_LEADER  # Gold takes priority for leader
		style.border_width_left = 3
	elif is_self:
		style.border_color = COLOR_BORDER_SELF
		style.border_width_left = 3
	elif is_leader:
		style.border_color = COLOR_BORDER_LEADER
	else:
		style.border_color = COLOR_BORDER

	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	frame.add_theme_stylebox_override("panel", style)

	# Content container - tighter margins
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	frame.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# Name row - use HBoxContainer for colored star
	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 2)
	vbox.add_child(name_row)

	if is_leader:
		# Gold star for leader
		var star_label = Label.new()
		star_label.text = "★"
		star_label.add_theme_font_size_override("font_size", 11)
		star_label.add_theme_color_override("font_color", COLOR_NAME_LEADER)
		star_label.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.0, 1.0))
		star_label.add_theme_constant_override("outline_size", 1)
		name_row.add_child(star_label)

	# Name label
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = player_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", COLOR_NAME)
	name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	name_label.add_theme_constant_override("outline_size", 1)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	# Health bar container with rounded corners
	var health_container = Control.new()
	health_container.name = "HealthContainer"
	health_container.custom_minimum_size = Vector2(0, HEALTH_BAR_HEIGHT)
	vbox.add_child(health_container)

	# Health bar background - dark inset (hard rectangle edges)
	var health_bg = Panel.new()
	health_bg.name = "HealthBG"
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = COLOR_HEALTH_BG
	# Hard rectangle edges - no corner radius
	health_bg.add_theme_stylebox_override("panel", bg_style)
	health_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_container.add_child(health_bg)

	# Health bar fill - starts at full (hard rectangle edges)
	var health_fill = Panel.new()
	health_fill.name = "HealthFill"
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = COLOR_HEALTH_HIGH
	# Hard rectangle edges - no corner radius
	health_fill.add_theme_stylebox_override("panel", fill_style)
	health_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_fill.anchor_right = 1.0  # Full width initially
	health_container.add_child(health_fill)

	# Store peer_id in metadata for health updates
	frame.set_meta("peer_id", peer_id)

	return frame

func _update_member_health() -> void:
	"""Update health bars for all group members."""
	for peer_id in member_frames:
		var frame = member_frames[peer_id]
		if not is_instance_valid(frame):
			continue

		var health_data = _get_player_health(peer_id)
		if health_data.max_health <= 0:
			continue

		var health_percent = float(health_data.current) / float(health_data.max_health)
		health_percent = clampf(health_percent, 0.0, 1.0)

		# Update health fill width and color
		var health_fill = frame.get_node_or_null("MarginContainer/VBoxContainer/HealthContainer/HealthFill")
		if health_fill:
			health_fill.anchor_right = health_percent

			# Update color based on health percentage via StyleBox
			var fill_style = health_fill.get_theme_stylebox("panel")
			if fill_style:
				var target_color: Color
				if health_percent > 0.6:
					target_color = COLOR_HEALTH_HIGH
				elif health_percent > 0.3:
					target_color = COLOR_HEALTH_MID
				else:
					target_color = COLOR_HEALTH_LOW
				fill_style.bg_color = target_color

func _get_player_health(peer_id: int) -> Dictionary:
	"""Get health data for a player by peer ID."""
	var result = {"current": 100, "max_health": 100}

	# Find the player node
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		var player_peer_id = 1
		if player.has_method("get_multiplayer_authority"):
			player_peer_id = player.get_multiplayer_authority()

		if player_peer_id == peer_id:
			if player.get("current_health") != null:
				result.current = int(player.current_health)
			if player.get("max_health") != null:
				result.max_health = int(player.max_health)
			break

	return result

# ============================================
# INVITE POPUP (merged from GroupInvitePopup)
# ============================================

func _create_invite_popup() -> void:
	"""Create the themed invite popup."""
	# Separate container for popup (independent of group frames visibility)
	popup_container = Control.new()
	popup_container.name = "InvitePopupContainer"
	popup_container.set_anchors_preset(Control.PRESET_CENTER)
	popup_container.offset_left = -150
	popup_container.offset_right = 150
	popup_container.offset_top = -80
	popup_container.offset_bottom = 80
	popup_container.visible = false
	add_child(popup_container)

	# Main panel
	popup_panel = PanelContainer.new()
	popup_panel.name = "InvitePanel"
	popup_panel.custom_minimum_size = Vector2(300, 160)
	popup_container.add_child(popup_panel)

	# Panel style
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_BG
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
	title.add_theme_color_override("font_color", COLOR_NAME)
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
	message.add_theme_color_override("font_color", COLOR_POPUP_TEXT)
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
	_style_popup_button(accept_btn, COLOR_ACCEPT, COLOR_ACCEPT_HOVER)
	button_box.add_child(accept_btn)

	# Decline button
	var decline_btn = Button.new()
	decline_btn.name = "DeclineButton"
	decline_btn.text = "Decline"
	decline_btn.custom_minimum_size = Vector2(100, 36)
	decline_btn.pressed.connect(_on_decline_pressed)
	_style_popup_button(decline_btn, COLOR_DECLINE, COLOR_DECLINE_HOVER)
	button_box.add_child(decline_btn)

func _style_popup_button(button: Button, bg_color: Color, hover_color: Color) -> void:
	"""Apply themed style to a popup button."""
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

	popup_container.visible = true

	# Play a notification sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_sound_2d"):
		sound_manager.play_sound_2d(sound_manager.SoundType.ITEM_PICKUP, -10.0)

func _hide_popup() -> void:
	"""Hide the popup."""
	if popup_container:
		popup_container.visible = false
	from_peer_id = -1
	from_player_name = ""

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
	"""Handle keyboard shortcuts for invite popup."""
	if not popup_container or not popup_container.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Y, KEY_ENTER:
				_on_accept_pressed()
				get_viewport().set_input_as_handled()
			KEY_N, KEY_ESCAPE:
				_on_decline_pressed()
				get_viewport().set_input_as_handled()
