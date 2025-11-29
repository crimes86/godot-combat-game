extends CanvasLayer

## GroupUI - WoW-style raid frames showing group members
## Displays on the left side of screen with player names and health bars
## Updates in real-time as group membership and health changes

# UI References
var group_container: VBoxContainer = null
var member_frames: Dictionary = {}  # peer_id -> MemberFrame

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

func _ready() -> void:
	layer = 100  # Above game, below menus
	_create_ui()
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

func _process(_delta: float) -> void:
	"""Update health bars for all group members."""
	if not visible:
		return

	_update_member_health()

func _on_group_updated() -> void:
	"""Called when group membership changes."""
	var group_manager = get_node_or_null("/root/GroupManager")
	if not group_manager:
		return

	if group_manager.has_group():
		visible = true
		_rebuild_frames()
	else:
		visible = false
		_clear_frames()

func _on_group_disbanded() -> void:
	"""Called when the group is disbanded."""
	visible = false
	_clear_frames()

func _on_invite_received(from_id: int, from_name: String) -> void:
	"""Show invite notification in chat."""
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui and chat_ui.has_method("add_system_message"):
		chat_ui.add_system_message("Group invite from %s - type /accept or /decline" % from_name)

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

	# Health bar background - dark inset
	var health_bg = Panel.new()
	health_bg.name = "HealthBG"
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = COLOR_HEALTH_BG
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	health_bg.add_theme_stylebox_override("panel", bg_style)
	health_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	health_container.add_child(health_bg)

	# Health bar fill - starts at full
	var health_fill = Panel.new()
	health_fill.name = "HealthFill"
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = COLOR_HEALTH_HIGH
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
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
