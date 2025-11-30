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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# F1 toggles bug report panel
		if event.keycode == KEY_F1:
			toggle_panel()
			get_viewport().set_input_as_handled()
			return

		# ESC closes panel
		if is_visible and event.keycode == KEY_ESCAPE:
			toggle_panel()
			get_viewport().set_input_as_handled()
			return

func toggle_panel() -> void:
	is_visible = not is_visible
	visible = is_visible

	if is_visible:
		_clear_form()
		title_input.grab_focus()
		# Pause game input while reporting
		get_tree().paused = false  # Don't pause, just capture input

func _create_ui() -> void:
	# Main panel
	panel = PanelContainer.new()
	panel.name = "BugReportPanel"

	# Style - dark theme
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
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

	# Title
	var title = Label.new()
	title.text = "🐛 Bug Report (F1 to close)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

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
	cancel_button.pressed.connect(_on_cancel_pressed)
	btn_hbox.add_child(cancel_button)

	submit_button = Button.new()
	submit_button.text = "Submit Report"
	submit_button.custom_minimum_size = Vector2(140, 35)
	submit_button.pressed.connect(_on_submit_pressed)
	btn_hbox.add_child(submit_button)

	# Style submit button
	var submit_style = StyleBoxFlat.new()
	submit_style.bg_color = Color(0.3, 0.5, 0.3)
	submit_style.set_corner_radius_all(4)
	submit_button.add_theme_stylebox_override("normal", submit_style)

func _clear_form() -> void:
	title_input.text = ""
	description_input.text = ""
	category_dropdown.selected = 0
	status_label.text = ""
	submit_button.disabled = false

func _on_cancel_pressed() -> void:
	toggle_panel()

func _on_submit_pressed() -> void:
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
