extends Node

## TutorialManager - Guides new players through game basics
## Steps:
## 1. WASD movement
## 2. Walk to training dummy
## 3. Click to attack dummy until crit window
## 4. Click weakpoint during crit window
## 5. Kill a skeleton
## 6. Talk to blacksmith

signal tutorial_completed
signal tutorial_step_completed(step: int)

enum TutorialStep {
	INACTIVE = -1,
	MOVEMENT = 0,        # Learn WASD
	FIND_DUMMY = 1,      # Walk to training dummy
	ATTACK_DUMMY = 2,    # Click to attack
	CRIT_WINDOW = 3,     # Wait for crit window
	HIT_WEAKPOINT = 4,   # Click the weakpoint
	KILL_SKELETON = 5,   # Find and kill a real skeleton
	VISIT_BLACKSMITH = 6, # Talk to blacksmith to gear up
	COMPLETE = 7
}

var current_step: TutorialStep = TutorialStep.INACTIVE
var tutorial_ui: CanvasLayer = null
var prompt_label: Label = null
var arrow_indicator: Node2D = null
var key_prompts: Dictionary = {}  # Track which keys are shown
var player: Node = null

# Tracking for step completion
var keys_pressed: Dictionary = {"w": false, "a": false, "s": false, "d": false}
var dummy_hits: int = 0
var crit_window_seen: bool = false
var weakpoint_hit: bool = false
var skeleton_killed: bool = false
var blacksmith_visited: bool = false
var step_transitioning: bool = false  # Prevent multiple transitions
var healing_hint_shown: bool = false  # Track if we've shown the campfire healing hint
var skeleton_engaged: bool = false  # Track if player has engaged with a skeleton

# UI colors
const BG_COLOR = Color(0.0, 0.0, 0.0, 0.85)
const TEXT_COLOR = Color(1.0, 1.0, 1.0, 1.0)
const HIGHLIGHT_COLOR = Color(1.0, 0.9, 0.3, 1.0)  # Gold/yellow
const SUCCESS_COLOR = Color(0.3, 1.0, 0.3, 1.0)  # Green

func _ready() -> void:
	# Don't auto-start - wait for start_tutorial() call
	pass

func _process(delta: float) -> void:
	if current_step == TutorialStep.INACTIVE or current_step == TutorialStep.COMPLETE:
		return

	# Update arrow indicator position
	update_arrow_indicator()

	# Check step completion conditions
	match current_step:
		TutorialStep.MOVEMENT:
			check_movement_complete()
		TutorialStep.FIND_DUMMY:
			check_dummy_reached()
		TutorialStep.ATTACK_DUMMY:
			check_dummy_attacked()
		TutorialStep.CRIT_WINDOW:
			check_crit_window()
		TutorialStep.HIT_WEAKPOINT:
			check_weakpoint_hit()
		TutorialStep.KILL_SKELETON:
			check_skeleton_killed()
			check_player_needs_healing()
		TutorialStep.VISIT_BLACKSMITH:
			check_blacksmith_visited()

func _input(event: InputEvent) -> void:
	if current_step != TutorialStep.MOVEMENT:
		return

	# Track WASD presses
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_W:
				keys_pressed["w"] = true
				update_key_prompt("W", true)
			KEY_A:
				keys_pressed["a"] = true
				update_key_prompt("A", true)
			KEY_S:
				keys_pressed["s"] = true
				update_key_prompt("S", true)
			KEY_D:
				keys_pressed["d"] = true
				update_key_prompt("D", true)

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func start_tutorial(player_node: Node) -> void:
	"""Start the tutorial for a new player"""
	player = player_node
	print("📚 Tutorial starting for player")

	# Create tutorial UI
	create_tutorial_ui()

	# Start with movement step
	advance_to_step(TutorialStep.MOVEMENT)

func skip_tutorial() -> void:
	"""Skip the entire tutorial"""
	current_step = TutorialStep.COMPLETE
	cleanup_tutorial_ui()
	tutorial_completed.emit()
	print("📚 Tutorial skipped")

func is_tutorial_active() -> bool:
	return current_step != TutorialStep.INACTIVE and current_step != TutorialStep.COMPLETE

func get_current_step() -> TutorialStep:
	return current_step

# ═══════════════════════════════════════════════════════════════════════════
# STEP MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

func advance_to_step(step: TutorialStep) -> void:
	"""Advance to the next tutorial step"""
	current_step = step
	tutorial_step_completed.emit(step - 1)  # Emit completion of previous step

	# Note: keys() index doesn't match enum values since INACTIVE = -1
	# Use step + 1 to get correct key name
	print("📚 Tutorial step: %s" % TutorialStep.keys()[step + 1])

	match step:
		TutorialStep.MOVEMENT:
			show_movement_tutorial()
		TutorialStep.FIND_DUMMY:
			show_find_dummy_tutorial()
		TutorialStep.ATTACK_DUMMY:
			show_attack_dummy_tutorial()
		TutorialStep.CRIT_WINDOW:
			show_crit_window_tutorial()
		TutorialStep.HIT_WEAKPOINT:
			show_weakpoint_tutorial()
		TutorialStep.KILL_SKELETON:
			show_kill_skeleton_tutorial()
		TutorialStep.VISIT_BLACKSMITH:
			show_blacksmith_tutorial()
		TutorialStep.COMPLETE:
			complete_tutorial()

func complete_tutorial() -> void:
	"""Tutorial completed!"""
	show_completion_message()

	# Wait then cleanup
	await get_tree().create_timer(3.0).timeout
	cleanup_tutorial_ui()
	tutorial_completed.emit()
	print("📚 Tutorial completed!")

# ═══════════════════════════════════════════════════════════════════════════
# STEP DISPLAYS
# ═══════════════════════════════════════════════════════════════════════════

func show_movement_tutorial() -> void:
	"""Step 1: Teach WASD movement"""
	clear_prompt()

	# Show big WASD keys on screen
	create_wasd_display()

	prompt_label.text = "Use WASD to move around!"
	prompt_label.visible = true

func show_find_dummy_tutorial() -> void:
	"""Step 2: Guide to training dummy"""
	clear_prompt()
	clear_key_prompts()

	prompt_label.text = "Walk to the Training Dummy!"
	prompt_label.visible = true

	# Show arrow pointing to dummy
	show_arrow_to_target(get_training_dummy_position())

func show_attack_dummy_tutorial() -> void:
	"""Step 3: Teach clicking to attack"""
	clear_prompt()
	clear_arrow()

	prompt_label.text = "Aim ON your enemies and LEFT-CLICK to ATTACK!"
	prompt_label.visible = true

	# Make the prompt flash slowly
	start_prompt_flash()

	# Show click indicator
	show_click_indicator()

	# Create feedback label for GOOD!/CRITICAL STRIKE!
	create_feedback_label()

func show_crit_window_tutorial() -> void:
	"""Step 4: Wait for crit window"""
	clear_prompt()

	prompt_label.text = "Keep attacking! Watch for it to GLOW..."
	prompt_label.visible = true

	# Keep showing click indicator and feedback
	show_click_indicator()

func show_weakpoint_tutorial() -> void:
	"""Step 5: Click the weakpoint"""
	clear_prompt()
	clear_feedback_label()

	prompt_label.text = "DESTROY THE WEAKPOINT!"
	prompt_label.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	prompt_label.visible = true

	# Show arrow pointing to dummy (where weakpoint is)
	show_arrow_to_target(get_training_dummy_position())

func show_kill_skeleton_tutorial() -> void:
	"""Step 6: Kill a real skeleton"""
	clear_prompt()
	prompt_label.add_theme_color_override("font_color", TEXT_COLOR)

	prompt_label.text = "Now find and defeat a Skeleton!"
	prompt_label.visible = true

	# Show arrow to nearest skeleton
	show_arrow_to_target(get_nearest_skeleton_position())

func show_blacksmith_tutorial() -> void:
	"""Step 7: Visit the blacksmith"""
	clear_prompt()

	prompt_label.text = "Talk to the Blacksmith to get gear!"
	prompt_label.visible = true

	# Show arrow to blacksmith
	show_arrow_to_target(get_blacksmith_position())

func show_completion_message() -> void:
	"""Show tutorial complete message"""
	clear_prompt()
	clear_arrow()

	prompt_label.text = "Tutorial Complete! Good luck, adventurer!"
	prompt_label.add_theme_color_override("font_color", SUCCESS_COLOR)
	prompt_label.visible = true

# ═══════════════════════════════════════════════════════════════════════════
# STEP COMPLETION CHECKS
# ═══════════════════════════════════════════════════════════════════════════

func check_movement_complete() -> void:
	"""Check if player has pressed all WASD keys"""
	if step_transitioning:
		return
	if keys_pressed["w"] and keys_pressed["a"] and keys_pressed["s"] and keys_pressed["d"]:
		step_transitioning = true
		# Small delay to let them see success
		await get_tree().create_timer(0.5).timeout
		advance_to_step(TutorialStep.FIND_DUMMY)
		step_transitioning = false

func check_dummy_reached() -> void:
	"""Check if player is near the training dummy"""
	# Only check during FIND_DUMMY step
	if current_step != TutorialStep.FIND_DUMMY:
		return
	if step_transitioning:
		return
	if not player or not is_instance_valid(player):
		return

	var dummy_pos = get_training_dummy_position()
	if dummy_pos == Vector2.ZERO:
		return

	var distance = player.global_position.distance_to(dummy_pos)
	if distance < 150:  # Within attack range
		print("📚 [Tutorial] Player reached dummy (distance: %.1f), advancing to ATTACK_DUMMY" % distance)
		step_transitioning = true
		advance_to_step(TutorialStep.ATTACK_DUMMY)
		step_transitioning = false

func check_dummy_attacked() -> void:
	"""Check if player has attacked the dummy enough"""
	# This is triggered externally via on_dummy_hit()
	pass

func check_crit_window() -> void:
	"""Check if crit window has appeared"""
	# This is triggered externally via on_crit_window_opened()
	pass

func check_weakpoint_hit() -> void:
	"""Check if player hit the weakpoint"""
	# This is triggered externally via on_weakpoint_hit()
	pass

func check_skeleton_killed() -> void:
	"""Check if player killed a skeleton"""
	# This is triggered externally via on_skeleton_killed()
	pass

func check_player_needs_healing() -> void:
	"""Check if player health dropped below 75% and show healing hint"""
	if not player or not is_instance_valid(player):
		return

	var current_health = player.get("current_health")
	var max_health = player.get("max_health")
	if current_health == null or max_health == null:
		return

	var health_percent = current_health / max_health

	# Show healing hint when health drops below 75%
	if not healing_hint_shown and health_percent < 0.75:
		healing_hint_shown = true
		show_healing_hint()
	# Revert to skeleton hint when healed above 90%
	elif healing_hint_shown and health_percent > 0.90:
		healing_hint_shown = false
		show_kill_skeleton_tutorial()  # Restore the skeleton prompt

func show_healing_hint() -> void:
	"""Show hint to heal at campfire"""
	# Update prompt text
	prompt_label.text = "Heal near the Campfire!"
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))  # Red-ish for urgency

	# Point arrow to campfire
	var campfire_pos = Vector2(Constants.CHUNK_SIZE / 2, 0)  # CAMPFIRE_POS
	show_arrow_to_target(campfire_pos)

	# Flash the prompt for attention
	start_prompt_flash()

	print("📚 [Tutorial] Showing healing hint - player health below 75%")

func check_blacksmith_visited() -> void:
	"""Check if player talked to blacksmith"""
	# This is triggered externally via on_blacksmith_visited()
	pass

# ═══════════════════════════════════════════════════════════════════════════
# EXTERNAL EVENT HANDLERS (called by other systems)
# ═══════════════════════════════════════════════════════════════════════════

func on_dummy_hit(is_crit: bool = false) -> void:
	"""Called when player hits the training dummy"""
	print("📚 [Tutorial] on_dummy_hit called - current_step: %s, is_crit: %s" % [TutorialStep.keys()[current_step], is_crit])

	# Show feedback during attack and crit window steps
	if current_step == TutorialStep.ATTACK_DUMMY or current_step == TutorialStep.CRIT_WINDOW:
		dummy_hits += 1
		print("📚 [Tutorial] dummy_hits: %d" % dummy_hits)

		# Show feedback based on hit type
		if is_crit:
			show_hit_feedback("CRITICAL STRIKE!", Color(1.0, 0.6, 0.2, 1.0))  # Orange
		else:
			show_hit_feedback("GOOD!", SUCCESS_COLOR)  # Green

		# Progress after enough hits
		if current_step == TutorialStep.ATTACK_DUMMY and dummy_hits >= 3:
			advance_to_step(TutorialStep.CRIT_WINDOW)

func on_crit_window_opened() -> void:
	"""Called when a crit window opens on the training dummy"""
	if current_step != TutorialStep.CRIT_WINDOW:
		return

	crit_window_seen = true
	advance_to_step(TutorialStep.HIT_WEAKPOINT)

func on_weakpoint_hit() -> void:
	"""Called when player hits a weakpoint"""
	if current_step != TutorialStep.HIT_WEAKPOINT:
		return

	# Show big feedback for weakpoint destruction
	show_hit_feedback("WEAKPOINT DESTROYED!", HIGHLIGHT_COLOR)

	weakpoint_hit = true
	# Small delay to let them see the feedback
	await get_tree().create_timer(1.0).timeout
	advance_to_step(TutorialStep.KILL_SKELETON)

func on_skeleton_killed() -> void:
	"""Called when player kills a skeleton"""
	if current_step != TutorialStep.KILL_SKELETON:
		return

	skeleton_killed = true
	advance_to_step(TutorialStep.VISIT_BLACKSMITH)

func on_blacksmith_visited() -> void:
	"""Called when player talks to blacksmith"""
	if current_step != TutorialStep.VISIT_BLACKSMITH:
		return

	blacksmith_visited = true
	advance_to_step(TutorialStep.COMPLETE)

# ═══════════════════════════════════════════════════════════════════════════
# UI CREATION
# ═══════════════════════════════════════════════════════════════════════════

func create_tutorial_ui() -> void:
	"""Create the tutorial UI overlay"""
	# Canvas layer for UI
	tutorial_ui = CanvasLayer.new()
	tutorial_ui.name = "TutorialUI"
	tutorial_ui.layer = 50  # Above game, below menus
	add_child(tutorial_ui)

	# Main prompt label at top of screen
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 32)
	prompt_label.add_theme_color_override("font_color", TEXT_COLOR)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 4)

	# Position closer to center (above player's head area)
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 0.0
	prompt_label.anchor_bottom = 0.0
	prompt_label.offset_top = 180
	prompt_label.offset_bottom = 230

	tutorial_ui.add_child(prompt_label)

	# Skip button in corner
	var skip_button = Button.new()
	skip_button.name = "SkipButton"
	skip_button.text = "Skip Tutorial"
	skip_button.anchor_left = 1.0
	skip_button.anchor_right = 1.0
	skip_button.anchor_top = 0.0
	skip_button.offset_left = -150
	skip_button.offset_right = -10
	skip_button.offset_top = 10
	skip_button.offset_bottom = 40
	skip_button.pressed.connect(skip_tutorial)
	tutorial_ui.add_child(skip_button)

	# Arrow indicator (world space, not UI)
	create_arrow_indicator()

func create_wasd_display() -> void:
	"""Create visual WASD key display"""
	var wasd_container = Control.new()
	wasd_container.name = "WASDDisplay"
	wasd_container.anchor_left = 0.5
	wasd_container.anchor_right = 0.5
	wasd_container.anchor_top = 0.5
	wasd_container.anchor_bottom = 0.5
	wasd_container.offset_left = -100
	wasd_container.offset_right = 100
	wasd_container.offset_top = -80
	wasd_container.offset_bottom = 80
	tutorial_ui.add_child(wasd_container)

	# Create individual key displays
	var key_size = 60
	var key_gap = 5

	# W key (top center)
	create_key_display(wasd_container, "W", Vector2(key_size + key_gap, 0), key_size)
	# A key (left)
	create_key_display(wasd_container, "A", Vector2(0, key_size + key_gap), key_size)
	# S key (center)
	create_key_display(wasd_container, "S", Vector2(key_size + key_gap, key_size + key_gap), key_size)
	# D key (right)
	create_key_display(wasd_container, "D", Vector2((key_size + key_gap) * 2, key_size + key_gap), key_size)

func create_key_display(parent: Control, key: String, pos: Vector2, size: int) -> void:
	"""Create a single key display"""
	var panel = Panel.new()
	panel.name = "Key_" + key
	panel.position = pos
	panel.size = Vector2(size, size)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	style.border_color = Color(0.5, 0.5, 0.5, 1.0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	# Key letter
	var label = Label.new()
	label.text = key
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.anchor_left = 0
	label.anchor_right = 1
	label.anchor_top = 0
	label.anchor_bottom = 1
	panel.add_child(label)

	parent.add_child(panel)
	key_prompts[key] = panel

func update_key_prompt(key: String, pressed: bool) -> void:
	"""Update a key display to show it was pressed"""
	if not key_prompts.has(key):
		return

	var panel = key_prompts[key] as Panel
	if not panel:
		return

	# Change to green when pressed
	var style = StyleBoxFlat.new()
	style.bg_color = SUCCESS_COLOR if pressed else Color(0.2, 0.2, 0.2, 0.9)
	style.border_color = SUCCESS_COLOR if pressed else Color(0.5, 0.5, 0.5, 1.0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

func clear_key_prompts() -> void:
	"""Remove WASD display"""
	var wasd_display = tutorial_ui.get_node_or_null("WASDDisplay")
	if wasd_display:
		wasd_display.queue_free()
	key_prompts.clear()

func create_arrow_indicator() -> void:
	"""Create arrow that points to targets in world space"""
	arrow_indicator = Node2D.new()
	arrow_indicator.name = "ArrowIndicator"
	arrow_indicator.visible = false
	arrow_indicator.z_index = 100

	# Add script for drawing
	arrow_indicator.set_script(preload("res://scripts/ui/TutorialArrow.gd"))

	# Add to world root, not UI
	get_tree().root.call_deferred("add_child", arrow_indicator)

func show_arrow_to_target(target_pos: Vector2) -> void:
	"""Show arrow pointing to a world position"""
	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.visible = true
		arrow_indicator.set("target_position", target_pos)

func update_arrow_indicator() -> void:
	"""Update arrow to point from player to target"""
	if not arrow_indicator or not is_instance_valid(arrow_indicator):
		return
	if not player or not is_instance_valid(player):
		return

	arrow_indicator.set("player_position", player.global_position)

func clear_arrow() -> void:
	"""Hide the arrow indicator"""
	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.visible = false

func show_click_indicator() -> void:
	"""Show a click/mouse indicator"""
	var click_label = Label.new()
	click_label.name = "ClickIndicator"
	click_label.text = "🖱️ LEFT CLICK"
	click_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	click_label.add_theme_font_size_override("font_size", 28)
	click_label.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	click_label.add_theme_color_override("font_outline_color", Color.BLACK)
	click_label.add_theme_constant_override("outline_size", 3)

	click_label.anchor_left = 0.5
	click_label.anchor_right = 0.5
	click_label.anchor_top = 0.5
	click_label.offset_left = -100
	click_label.offset_right = 100
	click_label.offset_top = 50
	click_label.offset_bottom = 90

	tutorial_ui.add_child(click_label)

	# Pulse animation
	var tween = create_tween().set_loops()
	tween.tween_property(click_label, "modulate:a", 0.5, 0.5)
	tween.tween_property(click_label, "modulate:a", 1.0, 0.5)

var feedback_label: Label = null
var prompt_flash_tween: Tween = null

func start_prompt_flash() -> void:
	"""Start slow flashing on the prompt label"""
	stop_prompt_flash()
	if prompt_label and is_instance_valid(prompt_label):
		prompt_flash_tween = create_tween().set_loops()
		prompt_flash_tween.tween_property(prompt_label, "modulate:a", 0.4, 0.8)
		prompt_flash_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.8)

func stop_prompt_flash() -> void:
	"""Stop flashing on the prompt label"""
	if prompt_flash_tween and prompt_flash_tween.is_valid():
		prompt_flash_tween.kill()
		prompt_flash_tween = null
	if prompt_label and is_instance_valid(prompt_label):
		prompt_label.modulate.a = 1.0

func create_feedback_label() -> void:
	"""Create the feedback label for GOOD!/CRITICAL STRIKE! messages"""
	if not tutorial_ui or not is_instance_valid(tutorial_ui):
		print("📚 [Tutorial] ERROR: tutorial_ui not valid in create_feedback_label")
		return

	if feedback_label and is_instance_valid(feedback_label):
		return  # Already exists

	feedback_label = Label.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 56)
	feedback_label.add_theme_color_override("font_outline_color", Color.BLACK)
	feedback_label.add_theme_constant_override("outline_size", 6)

	# Position in center of screen
	feedback_label.anchor_left = 0.0
	feedback_label.anchor_right = 1.0
	feedback_label.anchor_top = 0.5
	feedback_label.anchor_bottom = 0.5
	feedback_label.offset_top = -40
	feedback_label.offset_bottom = 40

	feedback_label.visible = false
	tutorial_ui.add_child(feedback_label)
	print("📚 [Tutorial] Created feedback label")

func show_hit_feedback(text: String, color: Color) -> void:
	"""Show feedback text with animation"""
	print("📚 [Tutorial] show_hit_feedback called: %s" % text)

	if not tutorial_ui or not is_instance_valid(tutorial_ui):
		print("📚 [Tutorial] ERROR: tutorial_ui not valid")
		return

	if not feedback_label or not is_instance_valid(feedback_label):
		create_feedback_label()

	if not feedback_label or not is_instance_valid(feedback_label):
		print("📚 [Tutorial] ERROR: Could not create feedback_label")
		return

	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.visible = true
	feedback_label.modulate = Color.WHITE
	feedback_label.pivot_offset = feedback_label.size / 2  # Center pivot for scaling

	# Pop and fade animation
	var tween = create_tween()
	# Scale up then back
	tween.tween_property(feedback_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.15)
	# Fade out after a moment
	tween.tween_property(feedback_label, "modulate:a", 0.0, 0.5).set_delay(0.3)

func clear_feedback_label() -> void:
	"""Remove the feedback label"""
	if feedback_label and is_instance_valid(feedback_label):
		feedback_label.queue_free()
		feedback_label = null

func clear_prompt() -> void:
	"""Clear click indicator and other temporary UI"""
	stop_prompt_flash()
	var click_indicator = tutorial_ui.get_node_or_null("ClickIndicator")
	if click_indicator:
		click_indicator.queue_free()

func cleanup_tutorial_ui() -> void:
	"""Remove all tutorial UI"""
	if tutorial_ui and is_instance_valid(tutorial_ui):
		tutorial_ui.queue_free()
		tutorial_ui = null

	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.queue_free()
		arrow_indicator = null

# ═══════════════════════════════════════════════════════════════════════════
# WORLD POSITION HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func get_training_dummy_position() -> Vector2:
	"""Get position of training dummy"""
	var dummy = get_tree().get_first_node_in_group("training_dummy")
	if dummy:
		return dummy.global_position

	# Fallback to known position
	return Vector2(4000, -180)  # CAMPFIRE_POS + Vector2(0, -180)

func get_blacksmith_position() -> Vector2:
	"""Get position of blacksmith"""
	var blacksmith = get_tree().get_first_node_in_group("vendor")
	if blacksmith:
		return blacksmith.global_position

	# Fallback to known position
	return Vector2(4150, 0)  # CAMPFIRE_POS + Vector2(150, 0)

func get_nearest_skeleton_position() -> Vector2:
	"""Get position of nearest level 1-2 skeleton to player (excludes training dummy)"""
	if not player or not is_instance_valid(player):
		return Vector2.ZERO

	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	var nearest_pos = Vector2.ZERO
	var nearest_dist = INF

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		# Skip training dummy
		if enemy.is_in_group("training_dummy"):
			continue
		# Skip dead/corpse enemies
		if enemy.get("is_corpse") or enemy.get("is_dying"):
			continue
		# Prefer level 1-2 skeletons for tutorial
		var enemy_lvl = enemy.get("enemy_level") if enemy.get("enemy_level") != null else 1
		if enemy_lvl > 2:
			continue

		var dist = player.global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_pos = enemy.global_position

	# If no level 1-2 found, find any skeleton
	if nearest_pos == Vector2.ZERO:
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			if enemy.is_in_group("training_dummy"):
				continue
			if enemy.get("is_corpse") or enemy.get("is_dying"):
				continue

			var dist = player.global_position.distance_to(enemy.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_pos = enemy.global_position

	return nearest_pos
