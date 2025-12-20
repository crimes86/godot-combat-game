extends Node

## TutorialManager - Guides new players through game basics
## Steps:
## 1. WASD movement
## 2. Walk to training dummy
## 3. Click to attack dummy until crit window
## 4. Click weakpoint during crit window
## 5. Talk to blacksmith
## 6. Accept first quest
## 7. Kill a skeleton (final step)

signal tutorial_completed
signal tutorial_step_completed(step: int)

enum TutorialStep {
	INACTIVE = -1,
	MOVEMENT = 0,        # Learn WASD
	FIND_DUMMY = 1,      # Walk to training dummy
	ATTACK_DUMMY = 2,    # Click to attack
	CRIT_WINDOW = 3,     # Wait for crit window
	HIT_WEAKPOINT = 4,   # Click the weakpoint
	VISIT_BLACKSMITH = 5, # Talk to blacksmith to gear up
	ACCEPT_QUEST = 6,    # Accept first quest from blacksmith
	KILL_SKELETON = 7,   # Find and kill a real skeleton (final combat step)
	COMPLETE = 8
}

var current_step: TutorialStep = TutorialStep.INACTIVE
var tutorial_ui: CanvasLayer = null
var prompt_label: Label = null
var arrow_indicator: Node2D = null
var key_prompts: Dictionary = {}  # Track which keys are shown
var player: Node = null

# Tracking for step completion
var keys_pressed: Dictionary = {"w": false, "a": false, "s": false, "d": false, "space": false}
var dummy_hits: int = 0
var crit_window_seen: bool = false
var weakpoint_hit: bool = false
var weakpoints_destroyed: int = 0  # Track total weakpoints destroyed on dummy (need 3)
const REQUIRED_WEAKPOINTS: int = 3  # Must destroy this many weakpoints before advancing
var skeleton_killed: bool = false
var blacksmith_visited: bool = false
var quest_accepted: bool = false
var step_transitioning: bool = false  # Prevent multiple transitions
var healing_hint_shown: bool = false  # Track if we've shown the campfire healing hint
var skeleton_engaged: bool = false  # Track if player has engaged with a skeleton

# UI arrow indicators (for pointing at UI elements like tabs/buttons)
var ui_arrow: Control = null
var ui_arrow_tween: Tween = null
var waiting_for_quests_tab: bool = false
var waiting_for_accept_button: bool = false

# Mini-tutorial: Equip item helper
var equip_mini_tutorial_active: bool = false
var equip_mini_tutorial_shown: bool = false  # Only show once per session
var equip_hint_label: Label = null
var equip_hint_tween: Tween = null
var equip_arrow: Control = null
var equip_arrow_tween: Tween = null
var pending_equip_item: Dictionary = {}  # The item we're waiting for them to equip
var waiting_for_bag_open: bool = false
var waiting_for_item_equip: bool = false

# UI colors - use UITheme singleton
var BG_COLOR: Color:
	get: return Color(0.0, 0.0, 0.0, 0.85)  # Tutorial uses solid black bg
var TEXT_COLOR: Color:
	get: return UITheme.TEXT_COLOR
var HIGHLIGHT_COLOR: Color:
	get: return UITheme.HIGHLIGHT_COLOR
var SUCCESS_COLOR: Color:
	get: return UITheme.SUCCESS_COLOR

func _ready() -> void:
	# Don't auto-start - wait for start_tutorial() call
	# Connect to inventory system to detect equippable items
	call_deferred("_connect_inventory_signals")

func _connect_inventory_signals() -> void:
	"""Connect to inventory system for equip mini-tutorial"""
	if InventorySystem and not InventorySystem.item_added.is_connected(_on_inventory_item_added):
		InventorySystem.item_added.connect(_on_inventory_item_added)
		print("📚 [Tutorial] Connected to InventorySystem.item_added")

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	if InventorySystem and InventorySystem.item_added.is_connected(_on_inventory_item_added):
		InventorySystem.item_added.disconnect(_on_inventory_item_added)

func _on_inventory_item_added(item: Dictionary) -> void:
	"""Called when any item is added to inventory"""
	on_equippable_item_received(item)

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
		TutorialStep.ACCEPT_QUEST:
			check_quest_accepted()

func _input(event: InputEvent) -> void:
	if current_step != TutorialStep.MOVEMENT:
		return

	# Track WASD + SPACE presses
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
			KEY_SPACE:
				keys_pressed["space"] = true
				update_key_prompt("SPACE", true)

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
	"""Skip the entire tutorial - clean up ALL tutorial elements"""
	current_step = TutorialStep.COMPLETE

	# Clear all tutorial visual elements
	clear_key_prompts()        # WASD display
	clear_arrow()              # World arrow indicator
	clear_click_indicator()    # LEFT CLICK indicator
	clear_feedback_label()     # GOOD!/CRITICAL feedback
	clear_ui_arrow()           # UI arrow pointing to tabs/buttons
	stop_prompt_flash()        # Stop any flashing animations
	clear_vendor_tutorial_arrow()  # Vendor/Wanderer arrow

	# Clear equip mini-tutorial if active
	end_equip_mini_tutorial()

	# Clear the main tutorial UI
	cleanup_tutorial_ui()

	# Reset tracking flags
	waiting_for_quests_tab = false
	waiting_for_accept_button = false

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
		TutorialStep.ACCEPT_QUEST:
			show_accept_quest_tutorial()
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

	set_prompt_text("Use WASD to move around!")

func show_find_dummy_tutorial() -> void:
	"""Step 2: Guide to training dummy"""
	clear_prompt()
	clear_key_prompts()

	set_prompt_text("Walk to the Training Dummy!")

	# Show arrow pointing to dummy
	show_arrow_to_target(get_training_dummy_position())

func show_attack_dummy_tutorial() -> void:
	"""Step 3: Teach clicking to attack"""
	clear_prompt()
	clear_arrow()

	set_prompt_text("Aim ON your enemies and LEFT-CLICK to ATTACK!")

	# Make the prompt flash slowly
	start_prompt_flash()

	# Show click indicator
	show_click_indicator()

	# Create feedback label for GOOD!/CRITICAL STRIKE!
	create_feedback_label()

func show_crit_window_tutorial() -> void:
	"""Step 4: Wait for crit window"""
	clear_prompt()

	# Show progress toward 3 weakpoints
	var progress_text = "(%d/%d) " % [weakpoints_destroyed, REQUIRED_WEAKPOINTS]
	set_prompt_text(progress_text + "Keep attacking! Watch for it to GLOW...")

	# Keep showing click indicator and feedback
	show_click_indicator()

func show_weakpoint_tutorial() -> void:
	"""Step 5: Click the weakpoint - crit window started, no more click spam"""
	clear_prompt()
	clear_click_indicator()  # Explicitly clear LEFT CLICK indicator when entering crit window
	clear_feedback_label()

	# Show which weakpoint this is
	var next_weakpoint = weakpoints_destroyed + 1
	set_prompt_text("DESTROY THE WEAKPOINT! (%d/%d)" % [next_weakpoint, REQUIRED_WEAKPOINTS], HIGHLIGHT_COLOR)

	# Show arrow pointing to dummy (where weakpoint is)
	show_arrow_to_target(get_training_dummy_position())

func show_kill_skeleton_tutorial() -> void:
	"""Step 6: Kill a real skeleton"""
	clear_prompt()
	clear_click_indicator()  # Explicitly clear click indicator from attack steps
	clear_feedback_label()   # Clear any remaining feedback

	set_prompt_text("Now find and defeat a Skeleton!")

	# Show arrow to nearest skeleton
	show_arrow_to_target(get_nearest_skeleton_position())

func show_blacksmith_tutorial() -> void:
	"""Step 7: Visit the blacksmith"""
	# If player already talked to blacksmith, skip this step
	if blacksmith_visited:
		print("📚 [Tutorial] Blacksmith already visited, skipping to ACCEPT_QUEST")
		advance_to_step(TutorialStep.ACCEPT_QUEST)
		return

	clear_prompt()
	clear_click_indicator()  # Explicitly clear LEFT CLICK from earlier steps
	clear_feedback_label()   # Clear any remaining feedback

	set_prompt_text("Press [F] to talk to the Wanderer!")

	# Show arrow to blacksmith
	show_arrow_to_target(get_blacksmith_position())

	# Show big green arrow on the blacksmith itself
	var blacksmith = get_tree().get_first_node_in_group("vendor")
	if blacksmith and blacksmith.has_method("show_tutorial_arrow"):
		blacksmith.show_tutorial_arrow()

func show_accept_quest_tutorial() -> void:
	"""Step 8: Accept first quest from blacksmith"""
	# If player already accepted a quest, skip this step
	if quest_accepted:
		print("📚 [Tutorial] Quest already accepted, skipping to KILL_SKELETON")
		advance_to_step(TutorialStep.KILL_SKELETON)
		return

	clear_prompt()
	clear_arrow()

	# Hide the blacksmith tutorial arrow
	var blacksmith = get_tree().get_first_node_in_group("vendor")
	if blacksmith and blacksmith.has_method("hide_tutorial_arrow"):
		blacksmith.hide_tutorial_arrow()

	set_prompt_text("Accept a quest from the Quests tab!", HIGHLIGHT_COLOR)

	# Flash the prompt for attention
	start_prompt_flash()

	# Show arrow pointing to Quests tab (delay to let shop UI fully render)
	await get_tree().create_timer(0.15).timeout
	if not is_instance_valid(self):
		return
	show_ui_arrow_to_quests_tab()

func show_completion_message() -> void:
	"""Show tutorial complete message"""
	clear_prompt()
	clear_arrow()
	clear_ui_arrow()
	clear_vendor_tutorial_arrow()  # Hide Wanderer arrow immediately
	waiting_for_quests_tab = false
	waiting_for_accept_button = false

	set_prompt_text("Tutorial Complete! Good luck, adventurer!", SUCCESS_COLOR)

# ═══════════════════════════════════════════════════════════════════════════
# STEP COMPLETION CHECKS
# ═══════════════════════════════════════════════════════════════════════════

func check_movement_complete() -> void:
	"""Check if player has pressed all WASD keys and SPACE"""
	if step_transitioning:
		return
	if keys_pressed["w"] and keys_pressed["a"] and keys_pressed["s"] and keys_pressed["d"] and keys_pressed["space"]:
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
	set_prompt_text("Heal near the Campfire!", Color(1.0, 0.4, 0.4, 1.0))  # Red-ish for urgency

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

func check_quest_accepted() -> void:
	"""Check if player accepted a quest"""
	# This is triggered externally via on_quest_accepted()
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

	weakpoints_destroyed += 1
	weakpoint_hit = true

	# Show progress feedback
	if weakpoints_destroyed < REQUIRED_WEAKPOINTS:
		show_hit_feedback("WEAKPOINT %d/%d!" % [weakpoints_destroyed, REQUIRED_WEAKPOINTS], HIGHLIGHT_COLOR)
		# Small delay then go back to fishing for another crit
		await get_tree().create_timer(1.0).timeout
		# Reset for next crit window cycle
		dummy_hits = 0
		crit_window_seen = false
		advance_to_step(TutorialStep.CRIT_WINDOW)
	else:
		# All 3 weakpoints destroyed!
		show_hit_feedback("WEAKPOINTS COMPLETE!", SUCCESS_COLOR)
		await get_tree().create_timer(1.5).timeout
		advance_to_step(TutorialStep.VISIT_BLACKSMITH)

func on_blacksmith_visited() -> void:
	"""Called when player talks to blacksmith"""
	print("📚 [Tutorial] on_blacksmith_visited() called, current_step: %s" % TutorialStep.keys()[current_step + 1])

	# Only set the flag if we're on or past the VISIT_BLACKSMITH step
	# This prevents early shop visits from skipping the blacksmith tutorial step
	if current_step >= TutorialStep.VISIT_BLACKSMITH:
		blacksmith_visited = true
		print("📚 [Tutorial] Setting blacksmith_visited = true")

	# If we're past this step already, ignore
	if current_step > TutorialStep.VISIT_BLACKSMITH:
		print("📚 [Tutorial] Already past VISIT_BLACKSMITH, ignoring")
		return

	# If we're on this step, advance
	if current_step == TutorialStep.VISIT_BLACKSMITH:
		print("📚 [Tutorial] On VISIT_BLACKSMITH step, advancing to ACCEPT_QUEST")
		advance_to_step(TutorialStep.ACCEPT_QUEST)

func on_quest_accepted() -> void:
	"""Called when player accepts their first quest"""
	quest_accepted = true

	# Clear UI arrow and flags regardless of step
	clear_ui_arrow()
	waiting_for_quests_tab = false
	waiting_for_accept_button = false

	# If we're past this step already, ignore
	if current_step > TutorialStep.ACCEPT_QUEST:
		return

	# If we're on this step, advance
	if current_step == TutorialStep.ACCEPT_QUEST:
		advance_to_step(TutorialStep.KILL_SKELETON)

func on_skeleton_killed() -> void:
	"""Called when player kills a skeleton"""
	if current_step != TutorialStep.KILL_SKELETON:
		return

	skeleton_killed = true
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
	"""Create visual WASD key display with SPACE for dodge"""
	var wasd_container = Control.new()
	wasd_container.name = "WASDDisplay"
	wasd_container.anchor_left = 0.5
	wasd_container.anchor_right = 0.5
	wasd_container.anchor_top = 0.5
	wasd_container.anchor_bottom = 0.5
	wasd_container.offset_left = -100
	wasd_container.offset_right = 100
	wasd_container.offset_top = -80
	wasd_container.offset_bottom = 120
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

	# SPACE bar for dodge (below WASD, wider key)
	var space_y = (key_size + key_gap) * 2 + 10  # Below the ASD row with extra gap
	create_space_key_display(wasd_container, Vector2(0, space_y), key_size)

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

func create_space_key_display(parent: Control, pos: Vector2, key_size: int) -> void:
	"""Create the SPACE bar display for dash"""
	var space_width = key_size * 3 + 10  # Wide space bar spanning all 3 columns
	var space_height = 40

	var panel = Panel.new()
	panel.name = "Key_SPACE"
	panel.position = pos
	panel.size = Vector2(space_width, space_height)

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

	# Label showing "SPACE - Dash"
	var label = Label.new()
	label.text = "SPACE - Dash"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.anchor_left = 0
	label.anchor_right = 1
	label.anchor_top = 0
	label.anchor_bottom = 1
	panel.add_child(label)

	parent.add_child(panel)
	key_prompts["SPACE"] = panel

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
	if tutorial_ui and is_instance_valid(tutorial_ui):
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

	# For KILL_SKELETON step, continuously update target to nearest skeleton
	if current_step == TutorialStep.KILL_SKELETON and not healing_hint_shown:
		var nearest_skeleton = get_nearest_skeleton_position()
		if nearest_skeleton != Vector2.ZERO:
			arrow_indicator.set("target_position", nearest_skeleton)

func clear_arrow() -> void:
	"""Hide the arrow indicator"""
	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.visible = false

# ═══════════════════════════════════════════════════════════════════════════
# UI ARROW INDICATOR (for pointing at UI elements)
# ═══════════════════════════════════════════════════════════════════════════

var ui_arrow_canvas: CanvasLayer = null  # Separate canvas for UI arrow

func create_ui_arrow() -> void:
	"""Create a UI arrow indicator that points at UI elements"""
	if ui_arrow and is_instance_valid(ui_arrow):
		return  # Already exists

	# Create dedicated canvas layer for UI arrow (above ShopUI which is ~100)
	if not ui_arrow_canvas or not is_instance_valid(ui_arrow_canvas):
		ui_arrow_canvas = CanvasLayer.new()
		ui_arrow_canvas.name = "UIArrowCanvas"
		ui_arrow_canvas.layer = 200  # Above all other UI
		get_tree().root.add_child(ui_arrow_canvas)

	ui_arrow = Control.new()
	ui_arrow.name = "UIArrow"
	ui_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create arrow polygon (pointing down)
	var arrow_poly = Polygon2D.new()
	arrow_poly.name = "ArrowPoly"
	# Arrow shape pointing DOWN (will be positioned above target)
	arrow_poly.polygon = PackedVector2Array([
		Vector2(0, 20),    # Tip (bottom)
		Vector2(-12, 0),   # Top left
		Vector2(-5, 0),    # Inner top left
		Vector2(-5, -15),  # Tail top left
		Vector2(5, -15),   # Tail top right
		Vector2(5, 0),     # Inner top right
		Vector2(12, 0)     # Top right
	])
	arrow_poly.color = HIGHLIGHT_COLOR
	arrow_poly.position = Vector2(0, 0)
	ui_arrow.add_child(arrow_poly)

	# Add outline for visibility
	var outline = Line2D.new()
	outline.name = "Outline"
	outline.points = PackedVector2Array([
		Vector2(0, 20), Vector2(-12, 0), Vector2(-5, 0),
		Vector2(-5, -15), Vector2(5, -15), Vector2(5, 0),
		Vector2(12, 0), Vector2(0, 20)
	])
	outline.width = 2.0
	outline.default_color = Color.BLACK
	ui_arrow.add_child(outline)

	ui_arrow.visible = false
	ui_arrow_canvas.add_child(ui_arrow)

func show_ui_arrow_to_quests_tab() -> void:
	"""Show UI arrow pointing to the Quests tab in ShopUI"""
	create_ui_arrow()

	# Find the ShopUI and its tab container
	var shop_ui = get_tree().get_first_node_in_group("shop_ui")
	if not shop_ui:
		# Try finding by class
		for node in get_tree().root.get_children():
			if node is CanvasLayer and node.name == "ShopUI":
				shop_ui = node
				break

	if not shop_ui:
		print("📚 [Tutorial] ShopUI not found for arrow")
		return

	var tab_container = shop_ui.get_node_or_null("Control/Panel/MarginContainer/VBoxContainer/TabContainer")
	if not tab_container:
		print("📚 [Tutorial] TabContainer not found")
		return

	# Find the Quests tab index
	var quests_tab_idx = -1
	for i in range(tab_container.get_tab_count()):
		var title = tab_container.get_tab_title(i)
		if title.begins_with("Quests"):
			quests_tab_idx = i
			break

	if quests_tab_idx == -1:
		print("📚 [Tutorial] Quests tab not found")
		return

	# Get the tab bar and find the tab button position
	var tab_bar = tab_container.get_tab_bar()
	if tab_bar:
		var tab_rect = tab_bar.get_tab_rect(quests_tab_idx)

		# Use get_screen_position() which accounts for CanvasLayer transforms
		var tab_bar_screen_pos = tab_bar.get_screen_position()
		var tab_center = tab_bar_screen_pos + tab_rect.position + Vector2(tab_rect.size.x / 2, 0)

		# Position arrow above the tab
		# The arrow tip points down at y=20, so offset to place tip just above tab
		ui_arrow.position = tab_center + Vector2(0, -25)
		ui_arrow.visible = true

		# Start bouncing animation
		start_ui_arrow_bounce()

		print("📚 [Tutorial] Showing arrow to Quests tab at %s (tab_bar_screen_pos=%s, tab_rect=%s)" % [ui_arrow.position, tab_bar_screen_pos, tab_rect])

func show_ui_arrow_to_accept_button() -> void:
	"""Show UI arrow pointing to the first Accept button in the Quests tab"""
	create_ui_arrow()

	var shop_ui = get_tree().get_first_node_in_group("shop_ui")
	if not shop_ui:
		for node in get_tree().root.get_children():
			if node is CanvasLayer and node.name == "ShopUI":
				shop_ui = node
				break

	if not shop_ui:
		return

	var quests_list = shop_ui.get_node_or_null("Control/Panel/MarginContainer/VBoxContainer/TabContainer/Quests/ScrollContainer/QuestsList")
	if not quests_list:
		print("📚 [Tutorial] QuestsList not found")
		return

	# Find the first Accept button
	for child in quests_list.get_children():
		if child is PanelContainer:
			var accept_btn = find_accept_button(child)
			if accept_btn and accept_btn.visible and accept_btn.text == "ACCEPT":
				# Use get_screen_position() which accounts for CanvasLayer transforms
				var btn_screen_pos = accept_btn.get_screen_position()
				var btn_center = btn_screen_pos + accept_btn.size / 2
				ui_arrow.position = btn_center + Vector2(0, -40)
				ui_arrow.visible = true
				start_ui_arrow_bounce()
				print("📚 [Tutorial] Showing arrow to Accept button at %s" % ui_arrow.position)
				return

	print("📚 [Tutorial] No Accept button found")

func find_accept_button(node: Node) -> Button:
	"""Recursively find an Accept button in the node tree"""
	if node is Button and node.text == "ACCEPT":
		return node
	for child in node.get_children():
		var result = find_accept_button(child)
		if result:
			return result
	return null

func start_ui_arrow_bounce() -> void:
	"""Start bouncing animation for UI arrow"""
	if ui_arrow_tween and ui_arrow_tween.is_valid():
		ui_arrow_tween.kill()

	if not ui_arrow or not is_instance_valid(ui_arrow):
		return

	var start_y = ui_arrow.position.y
	ui_arrow_tween = create_tween().set_loops()
	ui_arrow_tween.tween_property(ui_arrow, "position:y", start_y + 8, 0.4).set_ease(Tween.EASE_IN_OUT)
	ui_arrow_tween.tween_property(ui_arrow, "position:y", start_y, 0.4).set_ease(Tween.EASE_IN_OUT)

func clear_ui_arrow() -> void:
	"""Hide and clean up UI arrow"""
	if ui_arrow_tween and ui_arrow_tween.is_valid():
		ui_arrow_tween.kill()
		ui_arrow_tween = null

	if ui_arrow and is_instance_valid(ui_arrow):
		ui_arrow.queue_free()
		ui_arrow = null

	if ui_arrow_canvas and is_instance_valid(ui_arrow_canvas):
		ui_arrow_canvas.queue_free()
		ui_arrow_canvas = null

func on_quests_tab_selected() -> void:
	"""Called when user clicks on the Quests tab during tutorial"""
	if current_step != TutorialStep.ACCEPT_QUEST:
		return
	if not waiting_for_quests_tab:
		return

	waiting_for_quests_tab = false
	waiting_for_accept_button = true

	# Update prompt
	set_prompt_text("Click ACCEPT on a quest!")

	# Move arrow to Accept button (with small delay for tab to render)
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return
	show_ui_arrow_to_accept_button()

	print("📚 [Tutorial] Quests tab selected, now pointing to Accept button")

func on_shop_opened() -> void:
	"""Called when player opens the shop UI - re-show tutorial guidance if needed"""
	if current_step != TutorialStep.ACCEPT_QUEST:
		return

	print("📚 [Tutorial] Shop opened during ACCEPT_QUEST step")

	# Small delay for shop UI to render
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(self):
		return

	# Show arrow pointing to Quests tab
	set_prompt_text("Accept a quest from the Quests tab!")
	start_prompt_flash()
	show_ui_arrow_to_quests_tab()

func on_shop_closed() -> void:
	"""Called when player closes the shop UI"""
	if current_step != TutorialStep.ACCEPT_QUEST:
		return

	# Hide the UI arrow when shop closes
	clear_ui_arrow()
	print("📚 [Tutorial] Shop closed during ACCEPT_QUEST step")

func _is_quests_tab_selected() -> bool:
	"""Check if the Quests tab is currently selected in the ShopUI"""
	var shop_ui = get_tree().get_first_node_in_group("shop_ui")
	if not shop_ui:
		for node in get_tree().root.get_children():
			if node is CanvasLayer and node.name == "ShopUI":
				shop_ui = node
				break

	if not shop_ui:
		return false

	var tab_container = shop_ui.get_node_or_null("Control/Panel/MarginContainer/VBoxContainer/TabContainer")
	if not tab_container:
		return false

	var current_tab_idx = tab_container.current_tab
	var current_tab_title = tab_container.get_tab_title(current_tab_idx)
	return current_tab_title.begins_with("Quests")

var click_indicator_tween: Tween = null
var click_indicator_world: Node2D = null  # World-space click indicator

func show_click_indicator() -> void:
	"""Show a click/mouse indicator above the training dummy (world space)"""
	# Clear existing first
	clear_click_indicator()

	# Get dummy position to place indicator above it
	var dummy_pos = get_training_dummy_position()
	if dummy_pos == Vector2.ZERO:
		return

	# Create world-space container
	click_indicator_world = Node2D.new()
	click_indicator_world.name = "ClickIndicatorWorld"
	click_indicator_world.global_position = dummy_pos + Vector2(0, -170)  # Above the arrow (which is above dummy)
	click_indicator_world.z_index = 100

	# Create the label as a child
	var click_label = Label.new()
	click_label.name = "ClickIndicator"
	click_label.text = "🖱️ LEFT CLICK"
	click_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	click_label.add_theme_font_size_override("font_size", 28)
	click_label.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	click_label.add_theme_color_override("font_outline_color", Color.BLACK)
	click_label.add_theme_constant_override("outline_size", 3)

	# Center the label on the position
	click_label.position = Vector2(-100, -20)
	click_label.size = Vector2(200, 40)

	click_indicator_world.add_child(click_label)

	# Add to game world (not UI layer)
	get_tree().root.add_child(click_indicator_world)

	# Pulse animation - store the tween so we can kill it later
	click_indicator_tween = create_tween().set_loops()
	click_indicator_tween.tween_property(click_label, "modulate:a", 0.5, 0.5)
	click_indicator_tween.tween_property(click_label, "modulate:a", 1.0, 0.5)

func clear_click_indicator() -> void:
	"""Clear the click indicator and its tween"""
	# Clean up world-space indicator
	if click_indicator_world and is_instance_valid(click_indicator_world):
		click_indicator_world.queue_free()
		click_indicator_world = null

	# Kill the tween first
	if click_indicator_tween and click_indicator_tween.is_valid():
		click_indicator_tween.kill()
	click_indicator_tween = null

	# Remove all click indicators immediately (not queue_free to avoid race conditions)
	if tutorial_ui and is_instance_valid(tutorial_ui):
		var to_remove = []
		for child in tutorial_ui.get_children():
			if child.name == "ClickIndicator":
				to_remove.append(child)
		for child in to_remove:
			child.get_parent().remove_child(child)
			child.queue_free()
			print("📚 [Tutorial] Cleared ClickIndicator")

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
	clear_click_indicator()  # Properly kill tween and free node


func set_prompt_text(text: String, color: Color = TEXT_COLOR) -> void:
	"""Safely set prompt label text with null check"""
	if not prompt_label or not is_instance_valid(prompt_label):
		return
	prompt_label.text = text
	prompt_label.add_theme_color_override("font_color", color)
	prompt_label.visible = true


func cleanup_tutorial_ui() -> void:
	"""Remove all tutorial UI"""
	clear_ui_arrow()
	clear_vendor_tutorial_arrow()  # Clean up vendor/Wanderer arrow

	if ui_arrow and is_instance_valid(ui_arrow):
		ui_arrow.queue_free()
		ui_arrow = null

	if tutorial_ui and is_instance_valid(tutorial_ui):
		tutorial_ui.queue_free()
		tutorial_ui = null
		prompt_label = null  # Child of tutorial_ui, now invalid

	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.queue_free()
		arrow_indicator = null

func hide_tutorial_ui() -> void:
	"""Hide tutorial UI (when entering trading hub)"""
	if tutorial_ui and is_instance_valid(tutorial_ui):
		tutorial_ui.visible = false
		print("📚 [Tutorial] UI hidden (trading hub)")
	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.visible = false

func show_tutorial_ui() -> void:
	"""Show tutorial UI (when returning to zone 1)"""
	if tutorial_ui and is_instance_valid(tutorial_ui):
		tutorial_ui.visible = true
		print("📚 [Tutorial] UI shown (zone 1)")
	if arrow_indicator and is_instance_valid(arrow_indicator):
		arrow_indicator.visible = true

func clear_vendor_tutorial_arrow() -> void:
	"""Hide tutorial arrow on vendor/Wanderer NPC"""
	var vendor = get_tree().get_first_node_in_group("vendor")
	if vendor and vendor.has_method("hide_tutorial_arrow"):
		vendor.hide_tutorial_arrow()
		print("📚 [Tutorial] Cleared vendor tutorial arrow")

# ═══════════════════════════════════════════════════════════════════════════
# MINI-TUTORIAL: EQUIP ITEM HELPER
# ═══════════════════════════════════════════════════════════════════════════

func on_equippable_item_received(item: Dictionary) -> void:
	"""Called when player receives an equippable item (weapon/armor)"""
	# Only show if player is in the game world (not in Armory/menus)
	var game_world = get_tree().root.get_node_or_null("main/GameWorld")
	if not game_world:
		game_world = get_tree().root.get_node_or_null("GameWorld")
	if not game_world:
		return  # Not in game world yet

	# Only show once per session and if not already active
	if equip_mini_tutorial_shown or equip_mini_tutorial_active:
		return

	# Check if item is equippable
	var item_type = item.get("type", "")
	if item_type not in ["weapon", "armor", "helmet", "boots", "gloves", "legs", "chest"]:
		return

	print("📚 [MiniTutorial] Equippable item received: %s" % item.get("name", "Unknown"))

	pending_equip_item = item
	equip_mini_tutorial_active = true
	waiting_for_bag_open = true
	waiting_for_item_equip = false

	# Show "Press B to Open Bag!" hint in bottom right
	show_open_bag_hint()

func show_open_bag_hint() -> void:
	"""Show flashing hint to open bag in bottom right corner"""
	# Create hint label if needed
	if equip_hint_label and is_instance_valid(equip_hint_label):
		equip_hint_label.queue_free()

	equip_hint_label = Label.new()
	equip_hint_label.name = "EquipHintLabel"
	equip_hint_label.text = "Press [B] to Open Bag!"
	equip_hint_label.add_theme_font_size_override("font_size", 24)
	equip_hint_label.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
	equip_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	equip_hint_label.add_theme_constant_override("outline_size", 3)
	equip_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Position in bottom right (where inventory UI is)
	equip_hint_label.anchor_left = 1.0
	equip_hint_label.anchor_right = 1.0
	equip_hint_label.anchor_top = 1.0
	equip_hint_label.anchor_bottom = 1.0
	equip_hint_label.offset_left = -300
	equip_hint_label.offset_right = -20
	equip_hint_label.offset_top = -120
	equip_hint_label.offset_bottom = -90

	# Add to a canvas layer so it's always visible
	var canvas = CanvasLayer.new()
	canvas.name = "EquipHintCanvas"
	canvas.layer = 60
	get_tree().root.add_child(canvas)
	canvas.add_child(equip_hint_label)

	# Start flashing animation
	if equip_hint_tween and equip_hint_tween.is_valid():
		equip_hint_tween.kill()
	equip_hint_tween = create_tween().set_loops()
	equip_hint_tween.tween_property(equip_hint_label, "modulate:a", 0.3, 0.5)
	equip_hint_tween.tween_property(equip_hint_label, "modulate:a", 1.0, 0.5)

	print("📚 [MiniTutorial] Showing 'Press B to Open Bag!' hint")

func on_inventory_opened() -> void:
	"""Called when player opens their inventory/bag"""
	if not equip_mini_tutorial_active or not waiting_for_bag_open:
		return

	waiting_for_bag_open = false
	waiting_for_item_equip = true

	# Hide the bag hint
	clear_equip_hint_label()

	# Show arrow pointing to the item in inventory
	# Small delay to let inventory UI render
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	show_equip_item_arrow()

func show_equip_item_arrow() -> void:
	"""Show arrow pointing to the equippable item in inventory"""
	# Find InventoryUI
	var inventory_ui = get_tree().get_first_node_in_group("inventory_ui")
	if not inventory_ui:
		for node in get_tree().root.get_children():
			if node.name == "InventoryUI" or (node is CanvasLayer and node.get_node_or_null("Panel")):
				inventory_ui = node
				break

	if not inventory_ui:
		print("📚 [MiniTutorial] InventoryUI not found")
		end_equip_mini_tutorial()
		return

	# Create equip arrow if needed
	if equip_arrow and is_instance_valid(equip_arrow):
		equip_arrow.queue_free()

	# Create arrow canvas layer
	var canvas = CanvasLayer.new()
	canvas.name = "EquipArrowCanvas"
	canvas.layer = 150  # Above inventory UI (105) and other game UI
	get_tree().root.add_child(canvas)

	equip_arrow = Control.new()
	equip_arrow.name = "EquipArrow"
	equip_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create arrow polygon (pointing right towards item)
	var arrow_poly = Polygon2D.new()
	arrow_poly.name = "ArrowPoly"
	# Arrow shape pointing RIGHT
	arrow_poly.polygon = PackedVector2Array([
		Vector2(20, 0),    # Tip (right)
		Vector2(0, -12),   # Top left
		Vector2(0, -5),    # Inner top
		Vector2(-15, -5),  # Tail top
		Vector2(-15, 5),   # Tail bottom
		Vector2(0, 5),     # Inner bottom
		Vector2(0, 12)     # Bottom left
	])
	arrow_poly.color = SUCCESS_COLOR  # Green arrow
	equip_arrow.add_child(arrow_poly)

	# Add outline
	var outline = Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(20, 0), Vector2(0, -12), Vector2(0, -5),
		Vector2(-15, -5), Vector2(-15, 5), Vector2(0, 5),
		Vector2(0, 12), Vector2(20, 0)
	])
	outline.width = 2.0
	outline.default_color = Color.BLACK
	equip_arrow.add_child(outline)

	# Add label above arrow (centered)
	var label = Label.new()
	label.name = "EquipLabel"
	var item_name = pending_equip_item.get("name", "item")
	label.text = "Right-click to equip!"
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", SUCCESS_COLOR)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-70, -30)  # Above the arrow, roughly centered
	equip_arrow.add_child(label)

	canvas.add_child(equip_arrow)

	# Find the item slot in inventory
	var item_slot_pos = find_item_slot_position(inventory_ui, pending_equip_item)
	if item_slot_pos != Vector2.ZERO:
		equip_arrow.global_position = item_slot_pos + Vector2(-45, 0)  # Left of the slot
		print("📚 [MiniTutorial] Arrow positioned at: %s (slot was at %s)" % [equip_arrow.global_position, item_slot_pos])
	else:
		# Fallback position - right side of screen where inventory is
		equip_arrow.global_position = Vector2(1350, 450)
		print("📚 [MiniTutorial] Using fallback arrow position")

	equip_arrow.visible = true

	# Start bounce animation
	if equip_arrow_tween and equip_arrow_tween.is_valid():
		equip_arrow_tween.kill()
	var start_x = equip_arrow.position.x
	equip_arrow_tween = create_tween().set_loops()
	equip_arrow_tween.tween_property(equip_arrow, "position:x", start_x + 8, 0.4).set_ease(Tween.EASE_IN_OUT)
	equip_arrow_tween.tween_property(equip_arrow, "position:x", start_x, 0.4).set_ease(Tween.EASE_IN_OUT)

	print("📚 [MiniTutorial] Showing equip arrow for: %s" % item_name)

func find_item_slot_position(inventory_ui: Node, item: Dictionary) -> Vector2:
	"""Find the position of an item slot in the inventory UI"""
	var item_name = item.get("name", "")

	# InventoryUI has a public inventory_slots array we can use directly
	if "inventory_slots" in inventory_ui:
		var slots = inventory_ui.inventory_slots
		if slots and slots.size() > 0:
			# Search for our specific item using InventorySystem
			for i in range(slots.size()):
				var slot = slots[i]
				var slot_item = InventorySystem.get_item(i) if InventorySystem else null
				if slot_item and slot_item.get("name", "") == item_name:
					print("📚 [MiniTutorial] Found item '%s' at slot %d" % [item_name, i])
					# Get global position - slot is a Control inside the CanvasLayer
					var slot_rect = slot.get_global_rect()
					return slot_rect.position + slot_rect.size / 2

			# If no exact match, find first occupied slot
			for i in range(slots.size()):
				var slot = slots[i]
				var slot_item = InventorySystem.get_item(i) if InventorySystem else null
				if slot_item and slot_item.size() > 0:
					print("📚 [MiniTutorial] Using first occupied slot %d" % i)
					var slot_rect = slot.get_global_rect()
					return slot_rect.position + slot_rect.size / 2

			# Fallback to first slot
			var first_slot = slots[0]
			print("📚 [MiniTutorial] Using first slot as fallback")
			var slot_rect = first_slot.get_global_rect()
			return slot_rect.position + slot_rect.size / 2

	print("📚 [MiniTutorial] Could not access inventory_slots")
	return Vector2.ZERO

func find_grid_container(node: Node) -> GridContainer:
	"""Recursively find a GridContainer"""
	if node is GridContainer:
		return node
	for child in node.get_children():
		var result = find_grid_container(child)
		if result:
			return result
	return null

func on_item_equipped(item: Dictionary) -> void:
	"""Called when player equips an item"""
	if not equip_mini_tutorial_active:
		return

	print("📚 [MiniTutorial] Item equipped: %s" % item.get("name", "Unknown"))
	end_equip_mini_tutorial()

func on_inventory_closed() -> void:
	"""Called when player closes inventory without equipping"""
	if not equip_mini_tutorial_active:
		return

	# If they closed without equipping, clear arrow but keep mini-tutorial ready
	clear_equip_arrow()
	waiting_for_bag_open = true
	waiting_for_item_equip = false

	# Show the bag hint again
	show_open_bag_hint()

func end_equip_mini_tutorial() -> void:
	"""End the equip mini-tutorial"""
	equip_mini_tutorial_active = false
	equip_mini_tutorial_shown = true
	waiting_for_bag_open = false
	waiting_for_item_equip = false
	pending_equip_item = {}

	clear_equip_hint_label()
	clear_equip_arrow()

	print("📚 [MiniTutorial] Equip tutorial complete!")

func clear_equip_hint_label() -> void:
	"""Clear the 'Press B' hint label"""
	if equip_hint_tween and equip_hint_tween.is_valid():
		equip_hint_tween.kill()
		equip_hint_tween = null

	if equip_hint_label and is_instance_valid(equip_hint_label):
		var canvas = equip_hint_label.get_parent()
		equip_hint_label.queue_free()
		equip_hint_label = null
		if canvas and canvas.name == "EquipHintCanvas":
			canvas.queue_free()

func clear_equip_arrow() -> void:
	"""Clear the equip arrow"""
	if equip_arrow_tween and equip_arrow_tween.is_valid():
		equip_arrow_tween.kill()
		equip_arrow_tween = null

	if equip_arrow and is_instance_valid(equip_arrow):
		var canvas = equip_arrow.get_parent()
		equip_arrow.queue_free()
		equip_arrow = null
		if canvas and canvas.name == "EquipArrowCanvas":
			canvas.queue_free()

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
