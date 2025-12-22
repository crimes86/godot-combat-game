extends CanvasLayer
## BugReportUI.gd - In-game bug reporting system
## Press F1 to open bug report dialog
## Reports are saved to server and can be viewed via admin CLI

var panel: PanelContainer
var title_input: LineEdit
var description_input: TextEdit
var category_dropdown: OptionButton
var submit_button: Button
var cancel_button: Button
var status_label: Label

var is_visible: bool = false

# Static indicator in upper left
var indicator_container: Control = null

# Bug categories
const CATEGORIES = [
	"Gameplay",
	"Combat",
	"UI/Menus",
	"Networking/Multiplayer",
	"Graphics/Visual",
	"Audio",
	"Performance",
	"Crash",
	"Other"
]

func _ready() -> void:
	layer = 100
	visible = false
	_create_ui()
	_create_indicator()

func _input(event: InputEvent) -> void:
	# Only handle keyboard events
	if not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return

	# F1 toggles bug report panel
	if event.keycode == KEY_F1:
		toggle_panel()
		get_viewport().set_input_as_handled()
		return

	# ESC closes panel (only if visible)
	if is_visible and event.keycode == KEY_ESCAPE:
		is_visible = false
		visible = false
		get_viewport().set_input_as_handled()
		return

func toggle_panel() -> void:
	is_visible = not is_visible
	visible = is_visible

	if is_visible:
		_clear_form()
		title_input.grab_focus()
	else:
		var focused = get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()

func _create_ui() -> void:
	# Main panel
	panel = PanelContainer.new()
	panel.name = "BugReportPanel"

	# Style - dark theme
	var style = StyleBoxFlat.new()
	style.bg_color = UITheme.BG_COLOR
	style.border_color = Color(0.8, 0.4, 0.4)  # Reddish border for bug report
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)

	# Center on screen
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(500, 400)
	panel.position = Vector2(-250, -200)  # Offset to center

	add_child(panel)

	# Main layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Title row with close button
	var title_row = HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)

	# Spacer to center title
	var left_spacer = Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(left_spacer)

	# Title
	var title = Label.new()
	title.text = "🐛 Bug Report"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	title_row.add_child(title)

	# Spacer to push X button to right
	var right_spacer = Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(right_spacer)

	# Close button (X)
	var close_button = Button.new()
	close_button.text = "✕"
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.focus_mode = Control.FOCUS_NONE  # Don't steal focus, just click
	close_button.pressed.connect(_on_cancel_pressed)
	# Style the X button
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.5, 0.2, 0.2, 0.8)
	close_style.set_corner_radius_all(4)
	close_button.add_theme_stylebox_override("normal", close_style)
	var close_hover = StyleBoxFlat.new()
	close_hover.bg_color = Color(0.7, 0.3, 0.3, 0.9)
	close_hover.set_corner_radius_all(4)
	close_button.add_theme_stylebox_override("hover", close_hover)
	title_row.add_child(close_button)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Help us improve the game!"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	vbox.add_child(spacer)

	# Category dropdown
	var cat_hbox = HBoxContainer.new()
	vbox.add_child(cat_hbox)

	var cat_label = Label.new()
	cat_label.text = "Category:"
	cat_label.custom_minimum_size.x = 80
	cat_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	cat_hbox.add_child(cat_label)

	category_dropdown = OptionButton.new()
	category_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for cat in CATEGORIES:
		category_dropdown.add_item(cat)
	cat_hbox.add_child(category_dropdown)

	# Bug title input
	var title_hbox = HBoxContainer.new()
	vbox.add_child(title_hbox)

	var title_label = Label.new()
	title_label.text = "Title:"
	title_label.custom_minimum_size.x = 80
	title_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	title_hbox.add_child(title_label)

	title_input = LineEdit.new()
	title_input.placeholder_text = "Brief description of the bug"
	title_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_input)

	# Description
	var desc_label = Label.new()
	desc_label.text = "Description (what happened, steps to reproduce):"
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(desc_label)

	description_input = TextEdit.new()
	description_input.placeholder_text = "Describe the bug in detail...\n\nInclude:\n- What you were doing\n- What you expected\n- What actually happened"
	description_input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_input.custom_minimum_size.y = 150
	vbox.add_child(description_input)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	vbox.add_child(status_label)

	# Buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 10)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(100, 35)
	cancel_button.focus_mode = Control.FOCUS_NONE  # Don't steal focus, just click
	cancel_button.pressed.connect(_on_cancel_pressed)
	btn_hbox.add_child(cancel_button)

	submit_button = Button.new()
	submit_button.text = "Submit Report"
	submit_button.custom_minimum_size = Vector2(140, 35)
	submit_button.focus_mode = Control.FOCUS_NONE  # Don't steal focus, just click
	submit_button.pressed.connect(_on_submit_pressed)
	btn_hbox.add_child(submit_button)

	# Style submit button
	var submit_style = StyleBoxFlat.new()
	submit_style.bg_color = Color(0.3, 0.5, 0.3)
	submit_style.set_corner_radius_all(4)
	submit_button.add_theme_stylebox_override("normal", submit_style)

func _create_indicator() -> void:
	"""Create static indicator in upper left corner showing alpha build + F1 hint"""
	# Create a separate CanvasLayer for the indicator so it's always visible
	var indicator_layer = CanvasLayer.new()
	indicator_layer.name = "IndicatorLayer"
	indicator_layer.layer = 90  # Below bug report panel but above game
	add_child(indicator_layer)

	# Container for the indicator - must fill screen for anchors to work
	indicator_container = Control.new()
	indicator_container.name = "IndicatorContainer"
	indicator_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	indicator_layer.add_child(indicator_container)

	# Background panel - positioned at top-center
	var bg_panel = PanelContainer.new()
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	bg_style.set_corner_radius_all(4)
	bg_style.set_content_margin_all(6)
	bg_panel.add_theme_stylebox_override("panel", bg_style)

	# Position halfway between top-right and top-center (75% from left)
	bg_panel.anchor_left = 0.75
	bg_panel.anchor_right = 0.75
	bg_panel.anchor_top = 0.0
	bg_panel.anchor_bottom = 0.0
	bg_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bg_panel.position = Vector2(0, 10)
	indicator_container.add_child(bg_panel)

	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	bg_panel.add_child(vbox)

	# Alpha build label
	var alpha_label = Label.new()
	alpha_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	alpha_label.text = "ALPHA BUILD"
	alpha_label.add_theme_font_size_override("font_size", 15)
	alpha_label.add_theme_color_override("font_color", UITheme.WARNING_COLOR)
	vbox.add_child(alpha_label)

	# Version label
	var version_label = Label.new()
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var version_str = "v???"
	if NetworkManager and NetworkManager.NETWORK_VERSION != "":
		version_str = NetworkManager.NETWORK_VERSION
		# Truncate long git hashes
		if version_str.length() > 8:
			version_str = version_str.substr(0, 7)
	version_label.text = version_str
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	vbox.add_child(version_label)

	# F1 bug report button/hint
	var f1_btn = Button.new()
	f1_btn.name = "F1Button"
	f1_btn.text = "F1 - Report Bug"
	f1_btn.add_theme_font_size_override("font_size", 14)
	f1_btn.custom_minimum_size = Vector2(120, 28)
	f1_btn.pressed.connect(toggle_panel)
	# Style the button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = UITheme.BTN_DANGER
	btn_style.set_corner_radius_all(3)
	f1_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = UITheme.BTN_DANGER_HOVER
	btn_hover.set_corner_radius_all(3)
	f1_btn.add_theme_stylebox_override("hover", btn_hover)
	vbox.add_child(f1_btn)

func _clear_form() -> void:
	title_input.text = ""
	description_input.text = ""
	category_dropdown.selected = 0
	status_label.text = ""
	submit_button.disabled = false

func _on_cancel_pressed() -> void:
	_play_click_sound()
	is_visible = false
	visible = false
	var focused = get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()

func _on_submit_pressed() -> void:
	_play_click_sound()
	var bug_title = title_input.text.strip_edges()
	var bug_desc = description_input.text.strip_edges()
	var bug_category = CATEGORIES[category_dropdown.selected]

	# Validation
	if bug_title.is_empty():
		status_label.text = "Please enter a title"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		return

	if bug_desc.length() < 10:
		status_label.text = "Please provide more detail in the description"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		return

	# Gather context
	var report = {
		"title": bug_title,
		"description": bug_desc,
		"category": bug_category,
		"timestamp": Time.get_unix_time_from_system(),
		"player_name": NetworkManager.player_name,
		"version": NetworkManager.NETWORK_VERSION,
		"position": _get_player_position(),
		"is_guest": NetworkManager.is_guest
	}

	# Send to server
	submit_button.disabled = true
	status_label.text = "Submitting..."
	status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		# Send to server
		_submit_bug_report.rpc_id(1, report)
	else:
		# Local/host - save directly
		_save_bug_report(report)

	# Show success after short delay
	await get_tree().create_timer(0.5).timeout
	status_label.text = "✅ Report submitted! Thank you!"
	status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))

	# Close after delay
	await get_tree().create_timer(1.5).timeout
	toggle_panel()

func _get_player_position() -> String:
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and is_instance_valid(player):
		return "(%d, %d)" % [int(player.global_position.x), int(player.global_position.y)]
	return "unknown"

@rpc("any_peer", "reliable")
func _submit_bug_report(report: Dictionary) -> void:
	"""Server receives bug report from client."""
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	report["peer_id"] = sender_id

	_save_bug_report(report)
	print("🐛 Bug report received from peer %d: %s" % [sender_id, report.title])

func _save_bug_report(report: Dictionary) -> void:
	"""Save bug report to file."""
	var reports_file = "user://bug_reports.json"

	# Load existing reports
	var reports: Array = []
	if FileAccess.file_exists(reports_file):
		var file = FileAccess.open(reports_file, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Array:
				reports = json.data
			file.close()

	# Add new report with ID
	report["id"] = reports.size() + 1
	reports.append(report)

	# Save
	var file = FileAccess.open(reports_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(reports, "\t"))
		file.close()
		print("🐛 Bug report #%d saved: %s" % [report.id, report.title])

func _play_click_sound() -> void:
	"""Play button click sound"""
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager and sound_manager.has_method("play_button_click_sound"):
		sound_manager.play_button_click_sound()
