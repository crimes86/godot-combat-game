extends CanvasLayer

## Quest Tracker UI - Right-side HUD showing active quest objectives
## WoW Questie style - compact, real-time updates

# Stone Gray UI Palette (matching CharacterUI/ShopUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.75)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)
const OBJECTIVE_COLOR = Color(0.7, 0.7, 0.72, 1.0)
const COMPLETE_COLOR = Color(1.0, 0.85, 0.2, 1.0)  # Gold for complete
const PROGRESS_BG = Color(0.08, 0.08, 0.10, 0.8)
const PROGRESS_FILL = Color(0.4, 0.6, 0.3, 1.0)

const TRACKER_WIDTH = 320  # Wider to fit larger tutorial text
const QUEST_ENTRY_HEIGHT = 60
const OBJECTIVE_HEIGHT = 24
const IDLE_ALPHA = 0.3  # Transparency when not hovered
const HOVER_ALPHA = 1.0  # Full opacity when hovered
const TUTORIAL_COLOR = Color(0.4, 0.8, 1.0, 1.0)  # Light blue for tutorial

# Font sizes
const HEADER_FONT_SIZE = 18
const QUEST_NAME_FONT_SIZE = 16
const OBJECTIVE_FONT_SIZE = 14
const TUTORIAL_FONT_SIZE = 16  # Larger for readability

var main_panel: PanelContainer
var quest_container: VBoxContainer
var header_label: Label
var quest_entries: Array = []  # Array of quest entry nodes
var _fade_tween: Tween = null

# Tutorial tracking
var tutorial_entry: VBoxContainer = null
var tutorial_steps: Array = [
	{"name": "Learn Movement", "desc": "Press W, A, S, D keys"},
	{"name": "Find Dummy", "desc": "Walk to Training Dummy"},
	{"name": "Attack", "desc": "Click to attack dummy"},
	{"name": "Crit Window", "desc": "Keep attacking..."},
	{"name": "Hit Weakpoint", "desc": "Destroy weakpoints (0/3)"},
	{"name": "Visit Blacksmith", "desc": "Talk to Blacksmith"},
	{"name": "Accept Quest", "desc": "Accept a quest"},
	{"name": "Kill Skeleton", "desc": "Defeat a skeleton"},
]

func _ready() -> void:
	layer = 5  # Above game, below inventory (105) and other menus
	_create_ui()

	# Connect to QuestManager signals
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	if QuestManager:
		QuestManager.active_quests_changed.connect(_refresh_tracker)
		QuestManager.quest_progress_updated.connect(_on_progress_updated)
		QuestManager.quests_loaded.connect(_refresh_tracker)
		print("📋 QuestTrackerUI connected to QuestManager")

	# Connect to TutorialManager for tutorial tracking
	if TutorialManager:
		TutorialManager.tutorial_step_completed.connect(_on_tutorial_step_completed)
		TutorialManager.tutorial_completed.connect(_on_tutorial_completed)
		print("📋 QuestTrackerUI connected to TutorialManager")

	# Initial refresh
	_refresh_tracker()

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	if QuestManager:
		if QuestManager.active_quests_changed.is_connected(_refresh_tracker):
			QuestManager.active_quests_changed.disconnect(_refresh_tracker)
		if QuestManager.quest_progress_updated.is_connected(_on_progress_updated):
			QuestManager.quest_progress_updated.disconnect(_on_progress_updated)
		if QuestManager.quests_loaded.is_connected(_refresh_tracker):
			QuestManager.quests_loaded.disconnect(_refresh_tracker)
	if TutorialManager:
		if TutorialManager.tutorial_step_completed.is_connected(_on_tutorial_step_completed):
			TutorialManager.tutorial_step_completed.disconnect(_on_tutorial_step_completed)
		if TutorialManager.tutorial_completed.is_connected(_on_tutorial_completed):
			TutorialManager.tutorial_completed.disconnect(_on_tutorial_completed)

func _create_ui() -> void:
	"""Build the quest tracker UI"""
	# Main container - anchored to top-right, extends to bottom of screen
	# Positioned below minimap (minimap is 220px tall at y=15, ends at y=235)
	var control = Control.new()
	control.name = "TrackerControl"
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 1.0  # Extend to bottom of screen
	control.offset_left = -TRACKER_WIDTH - 10
	control.offset_right = -10
	control.offset_top = 250  # Below minimap (220px + 15px margin + 15px gap)
	control.offset_bottom = -10  # Small margin from bottom
	add_child(control)

	# Main panel with styling
	main_panel = PanelContainer.new()
	main_panel.name = "MainPanel"
	main_panel.custom_minimum_size = Vector2(TRACKER_WIDTH, 0)
	main_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	main_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	main_panel.add_theme_stylebox_override("panel", panel_style)
	control.add_child(main_panel)

	# Content VBox
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	main_panel.add_child(vbox)

	# Header
	header_label = Label.new()
	header_label.name = "Header"
	header_label.text = "QUESTS"
	header_label.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	header_label.add_theme_color_override("font_color", HEADER_COLOR)
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Quest entries container
	quest_container = VBoxContainer.new()
	quest_container.name = "QuestContainer"
	quest_container.add_theme_constant_override("separation", 6)
	vbox.add_child(quest_container)

	# Initially hidden until quests are active
	main_panel.visible = false

	# Start semi-transparent (like ChatUI)
	main_panel.modulate.a = IDLE_ALPHA

	# Connect mouse hover for fade in/out
	main_panel.mouse_entered.connect(_on_mouse_entered)
	main_panel.mouse_exited.connect(_on_mouse_exited)

func _refresh_tracker() -> void:
	"""Refresh the entire tracker display"""
	# Clear existing entries
	for entry in quest_entries:
		if is_instance_valid(entry):
			entry.queue_free()
	quest_entries.clear()

	# Clear tutorial entry
	if tutorial_entry and is_instance_valid(tutorial_entry):
		tutorial_entry.queue_free()
		tutorial_entry = null

	var has_content = false

	# Show tutorial progress if tutorial is active
	if TutorialManager and TutorialManager.is_tutorial_active():
		_create_tutorial_entry()
		has_content = true

	# Show quests from QuestManager - show ALL active quests
	if QuestManager:
		var active_quests = QuestManager.get_active_quests()
		if active_quests.size() > 0:
			print("📋 QuestTracker: Found %d active quests" % active_quests.size())

		if not active_quests.is_empty():
			has_content = true
			# Create entries for ALL active quests
			for quest in active_quests:
				var entry = _create_quest_entry(quest)
				quest_container.add_child(entry)
				quest_entries.append(entry)

	# Show/hide panel based on content
	main_panel.visible = has_content

func _create_quest_entry(quest: Dictionary) -> VBoxContainer:
	"""Create a single quest entry with objectives"""
	var quest_id = quest.get("id", "")
	var quest_state = QuestManager.get_quest_state(quest_id)
	var is_complete = quest_state == QuestManager.QuestState.COMPLETE

	var entry = VBoxContainer.new()
	entry.name = "Quest_%s" % quest_id
	entry.add_theme_constant_override("separation", 2)
	entry.set_meta("quest_id", quest_id)

	# Quest name
	var name_label = Label.new()
	name_label.name = "QuestName"
	name_label.text = quest.get("name", "Unknown Quest")
	name_label.add_theme_font_size_override("font_size", QUEST_NAME_FONT_SIZE)

	if is_complete:
		name_label.add_theme_color_override("font_color", COMPLETE_COLOR)
		name_label.text += " [COMPLETE]"
	else:
		name_label.add_theme_color_override("font_color", TEXT_COLOR)

	entry.add_child(name_label)

	# Objectives
	var objectives = quest.get("objectives", [])
	for i in range(objectives.size()):
		var obj = objectives[i]
		var obj_entry = _create_objective_entry(quest_id, i, obj)
		entry.add_child(obj_entry)

	return entry

func _create_objective_entry(quest_id: String, obj_index: int, objective: Dictionary) -> HBoxContainer:
	"""Create a single objective line"""
	var current = QuestManager.get_objective_progress(quest_id, obj_index)
	var required = objective.get("count", 1)
	var is_complete = current >= required

	var hbox = HBoxContainer.new()
	hbox.name = "Objective_%d" % obj_index
	hbox.set_meta("quest_id", quest_id)
	hbox.set_meta("obj_index", obj_index)

	# Bullet/checkmark
	var bullet = Label.new()
	bullet.text = "  \u2713 " if is_complete else "  \u2022 "  # ✓ or •
	bullet.add_theme_font_size_override("font_size", OBJECTIVE_FONT_SIZE)
	bullet.add_theme_color_override("font_color", COMPLETE_COLOR if is_complete else OBJECTIVE_COLOR)
	hbox.add_child(bullet)

	# Description with progress
	var desc_label = Label.new()
	desc_label.name = "Description"
	desc_label.text = "%s: %d/%d" % [objective.get("desc", ""), current, required]
	desc_label.add_theme_font_size_override("font_size", OBJECTIVE_FONT_SIZE)
	desc_label.add_theme_color_override("font_color", COMPLETE_COLOR if is_complete else OBJECTIVE_COLOR)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.clip_text = true
	hbox.add_child(desc_label)

	return hbox

func _on_progress_updated(quest_id: String, obj_index: int, current: int, required: int) -> void:
	"""Update a specific objective's display"""
	# Find the quest entry
	for entry in quest_entries:
		if not is_instance_valid(entry):
			continue
		if not entry.has_meta("quest_id"):
			continue
		if entry.get_meta("quest_id") != quest_id:
			continue

		# Find the objective entry
		for child in entry.get_children():
			if not child.has_meta("obj_index"):
				continue
			if child.get_meta("obj_index") != obj_index:
				continue

			# Update the description
			var desc_label = child.get_node_or_null("Description")
			if desc_label:
				var quest = QuestManager.get_quest(quest_id)
				var objectives = quest.get("objectives", [])
				if obj_index < objectives.size():
					var obj = objectives[obj_index]
					var is_complete = current >= required
					desc_label.text = "%s: %d/%d" % [obj.get("desc", ""), current, required]
					desc_label.add_theme_color_override("font_color", COMPLETE_COLOR if is_complete else OBJECTIVE_COLOR)

					# Update bullet
					var bullet = child.get_child(0)
					if bullet is Label:
						bullet.text = "  \u2713 " if is_complete else "  \u2022 "
						bullet.add_theme_color_override("font_color", COMPLETE_COLOR if is_complete else OBJECTIVE_COLOR)

			break

		# Check if quest is now complete and update header
		var quest_state = QuestManager.get_quest_state(quest_id)
		if quest_state == QuestManager.QuestState.COMPLETE:
			var name_label = entry.get_node_or_null("QuestName")
			if name_label and not "[COMPLETE]" in name_label.text:
				name_label.add_theme_color_override("font_color", COMPLETE_COLOR)
				name_label.text += " [COMPLETE]"

		break

func show_tracker() -> void:
	"""Show the quest tracker"""
	main_panel.visible = true

func hide_tracker() -> void:
	"""Hide the quest tracker"""
	main_panel.visible = false

# ═══════════════════════════════════════════════════════════════════════════
# HOVER FADE (like ChatUI)
# ═══════════════════════════════════════════════════════════════════════════

func _on_mouse_entered() -> void:
	"""Fade in when mouse hovers over tracker"""
	_fade_to(HOVER_ALPHA)

func _on_mouse_exited() -> void:
	"""Fade out when mouse leaves tracker"""
	_fade_to(IDLE_ALPHA)

func _fade_to(target_alpha: float) -> void:
	"""Smoothly fade tracker panel to target alpha"""
	if _fade_tween:
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(main_panel, "modulate:a", target_alpha, 0.2)

# ═══════════════════════════════════════════════════════════════════════════
# TUTORIAL TRACKING
# ═══════════════════════════════════════════════════════════════════════════

func _create_tutorial_entry() -> void:
	"""Create tutorial progress entry"""
	if not TutorialManager:
		return

	var current_step = TutorialManager.current_step

	tutorial_entry = VBoxContainer.new()
	tutorial_entry.name = "TutorialEntry"
	tutorial_entry.add_theme_constant_override("separation", 2)

	# Tutorial header with light blue color
	var name_label = Label.new()
	name_label.name = "TutorialName"
	name_label.text = "TUTORIAL"
	name_label.add_theme_font_size_override("font_size", QUEST_NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", TUTORIAL_COLOR)
	tutorial_entry.add_child(name_label)

	# Show steps - completed ones with checkmarks, current one highlighted
	for i in range(tutorial_steps.size()):
		var step_data = tutorial_steps[i].duplicate()  # Copy so we can modify
		var step_enum_value = i  # TutorialStep enum starts at 0 for MOVEMENT
		var is_complete = current_step > step_enum_value
		var is_current = current_step == step_enum_value

		# Dynamically update weakpoint step description with current progress
		if step_enum_value == TutorialManager.TutorialStep.HIT_WEAKPOINT:
			var destroyed = TutorialManager.weakpoints_destroyed
			var required = TutorialManager.REQUIRED_WEAKPOINTS
			step_data["desc"] = "Destroy weakpoints (%d/%d)" % [destroyed, required]

		var step_entry = _create_tutorial_step_entry(step_data, is_complete, is_current)
		tutorial_entry.add_child(step_entry)

	# Add separator after tutorial before quests
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	tutorial_entry.add_child(sep)

	# Add to container at the top
	quest_container.add_child(tutorial_entry)
	quest_container.move_child(tutorial_entry, 0)

func _create_tutorial_step_entry(step_data: Dictionary, is_complete: bool, is_current: bool) -> HBoxContainer:
	"""Create a single tutorial step line"""
	var hbox = HBoxContainer.new()

	# Bullet/checkmark
	var bullet = Label.new()
	if is_complete:
		bullet.text = "  \u2713 "  # ✓
		bullet.add_theme_color_override("font_color", COMPLETE_COLOR)
	elif is_current:
		bullet.text = "  \u25B6 "  # ▶ (arrow for current)
		bullet.add_theme_color_override("font_color", TUTORIAL_COLOR)
	else:
		bullet.text = "  \u2022 "  # •
		bullet.add_theme_color_override("font_color", OBJECTIVE_COLOR)
	bullet.add_theme_font_size_override("font_size", TUTORIAL_FONT_SIZE)
	hbox.add_child(bullet)

	# Description
	var desc_label = Label.new()
	desc_label.name = "Description"
	desc_label.text = step_data.get("desc", "")
	desc_label.add_theme_font_size_override("font_size", TUTORIAL_FONT_SIZE)

	if is_complete:
		desc_label.add_theme_color_override("font_color", COMPLETE_COLOR)
	elif is_current:
		desc_label.add_theme_color_override("font_color", TUTORIAL_COLOR)
	else:
		desc_label.add_theme_color_override("font_color", OBJECTIVE_COLOR)

	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.clip_text = true
	hbox.add_child(desc_label)

	return hbox

func _on_tutorial_step_completed(completed_step: int) -> void:
	"""Handle tutorial step completion - refresh tracker"""
	_refresh_tracker()

func _on_tutorial_completed() -> void:
	"""Handle tutorial completion - refresh tracker to remove tutorial entry"""
	_refresh_tracker()
