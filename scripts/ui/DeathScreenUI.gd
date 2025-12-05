extends CanvasLayer
class_name DeathScreenUI

## Death Screen - Minimalist banner shown when player dies
## Shows XP lost, timer, and respawn button

signal respawn_requested

# UI elements
var panel: PanelContainer
var title_label: Label
var info_label: Label
var timer_label: Label
var respawn_button: Button

# Death info
var xp_lost: int = 0
var corpse_position: Vector2 = Vector2.ZERO

# Auto-respawn timer
const AUTO_RESPAWN_TIME: float = 10.0
var time_remaining: float = AUTO_RESPAWN_TIME

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func _build_ui() -> void:
	# Bottom-center anchor container (below player's feet)
	var anchor = Control.new()
	anchor.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor.anchor_top = 0.65
	anchor.anchor_bottom = 0.75
	anchor.anchor_left = 0.0
	anchor.anchor_right = 1.0
	anchor.offset_top = 0
	anchor.offset_bottom = 0
	add_child(anchor)

	# Center the panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.add_child(center)

	# Main panel - dark with red accent
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 90)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.02, 0.02, 0.9)
	style.border_color = Color(0.6, 0.15, 0.15)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 0
	style.border_width_right = 0
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	# Horizontal layout
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)

	# Left side - death info
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# "YOU DIED" title
	title_label = Label.new()
	title_label.text = "YOU DIED"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	vbox.add_child(title_label)

	# XP lost / corpse info
	info_label = Label.new()
	info_label.text = "Your corpse holds your belongings"
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.6, 0.6))
	vbox.add_child(info_label)

	# Separator
	var sep = VSeparator.new()
	sep.custom_minimum_size.x = 2
	hbox.add_child(sep)

	# Right side - timer and button
	var right_vbox = VBoxContainer.new()
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(right_vbox)

	# Timer
	timer_label = Label.new()
	timer_label.text = "10s"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 11)
	timer_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	right_vbox.add_child(timer_label)

	# Respawn button
	respawn_button = Button.new()
	respawn_button.text = "Respawn"
	respawn_button.custom_minimum_size = Vector2(100, 32)
	respawn_button.add_theme_font_size_override("font_size", 14)
	respawn_button.pressed.connect(_on_respawn_pressed)
	right_vbox.add_child(respawn_button)

func show_death_screen(p_xp_lost: int, p_corpse_position: Vector2) -> void:
	xp_lost = p_xp_lost
	corpse_position = p_corpse_position
	time_remaining = AUTO_RESPAWN_TIME

	# Update info text
	if xp_lost > 0:
		info_label.text = "Lost %d XP - Corpse at (%.0f, %.0f)" % [xp_lost, corpse_position.x, corpse_position.y]
	else:
		info_label.text = "Corpse at (%.0f, %.0f)" % [corpse_position.x, corpse_position.y]

	timer_label.text = "%.0fs" % time_remaining

	visible = true
	set_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return

	time_remaining -= delta
	timer_label.text = "%.0fs" % max(0, time_remaining)

	if time_remaining <= 0:
		_on_respawn_pressed()

func _on_respawn_pressed() -> void:
	visible = false
	set_process(false)
	respawn_requested.emit()

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_on_respawn_pressed()
			get_viewport().set_input_as_handled()
