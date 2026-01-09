extends CanvasLayer

## Level & XP Display UI
## Shows current level and progress to next level
## Locked to screen (doesn't move with camera)

@onready var level_label: Label = $Control/VBoxContainer/LevelLabel
@onready var xp_bar: ProgressBar = $Control/VBoxContainer/XPBar
@onready var xp_text: Label = $Control/VBoxContainer/XPBar/XPText
@onready var stats_panel: PanelContainer = $Control/StatsPanel
@onready var stats_label: Label = $Control/StatsPanel/MarginContainer/StatsLabel

var show_stats: bool = false
var combat_border: Control = null  # Red pulsing border for combat
var combat_tween: Tween = null  # Store tween for cleanup
var fps_label: Label = null  # FPS counter for debugging
var fps_update_timer: float = 0.0
var is_in_combat: bool = false  # Track combat state

func _ready() -> void:
	# Connect to CharacterStats signals
	CharacterStats.level_up.connect(_on_level_up)
	CharacterStats.experience_gained.connect(_on_xp_gained)

	# Create combat border effect
	create_combat_border()

	# NOTE: FPS counter removed - use F3 debug overlay instead
	# create_fps_counter()

	# Initial update
	update_display()

	# Hide stats panel by default
	if stats_panel:
		stats_panel.visible = false

func create_combat_border() -> void:
	"""Create a red pulsing border around the screen for combat state"""
	combat_border = Control.new()
	combat_border.name = "CombatBorder"
	combat_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_border.visible = false  # Hidden by default

	# Custom drawing for the border
	combat_border.set_script(CombatBorderScript)

	# Add to Control node
	$Control.add_child(combat_border)

# Inner class for combat border drawing
class CombatBorderScript extends Control:
	var border_alpha: float = 0.6
	var border_thickness: float = 4.0
	var border_color: Color = Color(0.9, 0.15, 0.1, 1.0)  # Deep red

	func _draw() -> void:
		var rect = get_rect()
		var color = Color(border_color.r, border_color.g, border_color.b, border_alpha)

		# Draw 4 rectangles for the border (top, bottom, left, right)
		# Top border
		draw_rect(Rect2(0, 0, rect.size.x, border_thickness), color)
		# Bottom border
		draw_rect(Rect2(0, rect.size.y - border_thickness, rect.size.x, border_thickness), color)
		# Left border
		draw_rect(Rect2(0, 0, border_thickness, rect.size.y), color)
		# Right border
		draw_rect(Rect2(rect.size.x - border_thickness, 0, border_thickness, rect.size.y), color)

		# Add subtle inner glow (second thinner border, slightly transparent)
		var glow_thickness = 8.0
		var glow_color = Color(border_color.r, border_color.g, border_color.b, border_alpha * 0.3)
		# Top glow
		draw_rect(Rect2(0, border_thickness, rect.size.x, glow_thickness), glow_color)
		# Bottom glow
		draw_rect(Rect2(0, rect.size.y - border_thickness - glow_thickness, rect.size.x, glow_thickness), glow_color)
		# Left glow
		draw_rect(Rect2(border_thickness, 0, glow_thickness, rect.size.y), glow_color)
		# Right glow
		draw_rect(Rect2(rect.size.x - border_thickness - glow_thickness, 0, glow_thickness, rect.size.y), glow_color)

	func set_pulse_alpha(alpha: float) -> void:
		border_alpha = alpha
		queue_redraw()

func create_fps_counter() -> void:
	"""Create FPS counter for performance debugging"""
	fps_label = Label.new()
	fps_label.name = "FPSCounter"
	fps_label.text = "FPS: 60"
	fps_label.add_theme_font_size_override("font_size", 20)
	fps_label.add_theme_color_override("font_color", Color.YELLOW)
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 2)

	# Position top-right
	fps_label.position = Vector2(1100, 20)
	fps_label.size = Vector2(150, 30)

	$Control.add_child(fps_label)

func _exit_tree() -> void:
	"""Clean up tweens on exit to prevent crashes"""
	if combat_tween and combat_tween.is_valid():
		combat_tween.kill()
		combat_tween = null

var combat_check_timer: float = 0.0
const COMBAT_CHECK_INTERVAL: float = 0.2  # Only check every 0.2s instead of every frame

func _process(delta: float) -> void:
	"""Update UI and check combat status"""
	# Update FPS counter
	fps_update_timer += delta
	if fps_update_timer >= 0.5 and fps_label:  # Update FPS twice per second
		var fps = Engine.get_frames_per_second()
		var color = Color.GREEN if fps >= 50 else (Color.YELLOW if fps >= 30 else Color.RED)
		fps_label.text = "FPS: %d" % fps
		fps_label.add_theme_color_override("font_color", color)
		fps_update_timer = 0.0

	# Check combat status
	if not combat_border or not is_instance_valid(combat_border):
		return

	# Performance: Only check combat status every 0.2s, not every frame
	combat_check_timer += delta
	if combat_check_timer < COMBAT_CHECK_INTERVAL:
		return
	combat_check_timer = 0.0

	var now_in_combat = is_player_in_combat()
	if now_in_combat != is_in_combat:
		is_in_combat = now_in_combat
		combat_border.visible = is_in_combat

		# Heartbeat pulse effect when in combat
		if is_in_combat:
			start_combat_heartbeat()
		else:
			stop_combat_heartbeat()

func is_player_in_combat() -> bool:
	"""Check if player is in combat (being attacked or attacking)"""
	# Safety check - don't run during tree exit
	if not is_inside_tree():
		return false

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player or not is_instance_valid(player):
		return false

	# Primary check: Player's own combat state (set when taking damage)
	# This is the main indicator - player was recently hit
	if player.get("is_in_combat"):
		return true

	# Secondary check: Any NEARBY enemy actively targeting the player
	# Only check enemies within combat range - distant enemies don't matter
	const COMBAT_CHECK_RADIUS := 400.0  # Only consider enemies within this distance
	var player_pos = player.global_position

	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Skip dying or corpse enemies - they're not in combat
		if enemy.get("is_dying") or enemy.get("is_corpse"):
			continue

		# CRITICAL: Only check enemies that are actually nearby
		var dist = enemy.global_position.distance_to(player_pos)
		if dist > COMBAT_CHECK_RADIUS:
			continue

		# Check if enemy has AI and is in combat AND targeting this player
		if enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			if is_instance_valid(ai) and ai.get("is_in_combat"):
				# Additional check: is this enemy actually targeting the player?
				var enemy_target = ai.get("player")
				if enemy_target == player:
					return true

	return false

func start_combat_heartbeat() -> void:
	"""Start the heartbeat pulsing effect on the combat border"""
	stop_combat_heartbeat()  # Clear any existing

	if not combat_border or not is_instance_valid(combat_border):
		return

	# Heartbeat pattern: quick pulse, pause, quick pulse, longer pause
	combat_tween = create_tween()
	combat_tween.set_loops(0)  # Infinite

	# First beat (strong)
	combat_tween.tween_method(_set_border_alpha, 0.4, 0.8, 0.15)
	combat_tween.tween_method(_set_border_alpha, 0.8, 0.4, 0.15)
	# Short pause
	combat_tween.tween_interval(0.1)
	# Second beat (slightly weaker)
	combat_tween.tween_method(_set_border_alpha, 0.4, 0.65, 0.12)
	combat_tween.tween_method(_set_border_alpha, 0.65, 0.4, 0.12)
	# Longer pause before next heartbeat
	combat_tween.tween_interval(0.6)

func stop_combat_heartbeat() -> void:
	"""Stop the heartbeat effect"""
	if combat_tween and combat_tween.is_valid():
		combat_tween.kill()
		combat_tween = null

	# Reset border alpha
	if combat_border and is_instance_valid(combat_border):
		_set_border_alpha(0.6)

func _set_border_alpha(alpha: float) -> void:
	"""Set the combat border alpha for pulsing effect"""
	if combat_border and is_instance_valid(combat_border) and combat_border.has_method("set_pulse_alpha"):
		combat_border.set_pulse_alpha(alpha)

func _input(event: InputEvent) -> void:
	# Toggle stats panel with F8 (dev builds only)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		# Only allow in editor or debug builds
		if not (OS.has_feature("editor") or OS.is_debug_build()):
			return
		show_stats = !show_stats
		if stats_panel:
			stats_panel.visible = show_stats
			if show_stats:
				update_stats_display()

func update_display() -> void:
	"""Update level label and XP bar"""
	if level_label:
		level_label.text = "Level %d" % CharacterStats.level
	
	if xp_bar:
		var progress = CharacterStats.get_experience_progress()
		xp_bar.value = progress * 100  # ProgressBar uses 0-100
	
	if xp_text:
		var current_xp = max(0, CharacterStats.experience)  # Ensure positive
		var needed_xp = max(1, CharacterStats.experience_to_next_level)  # Prevent division by zero
		xp_text.text = "%d / %d XP" % [current_xp, needed_xp]

func update_stats_display() -> void:
	"""Update the detailed stats panel"""
	if not stats_label:
		return
	
	var text = ""
	text += "═══ STATS (6-stat) ═══\n"
	text += "STR: %d  AGI: %d\n" % [CharacterStats.get_effective_strength(), CharacterStats.get_effective_agility()]
	text += "DEX: %d  INT: %d\n" % [CharacterStats.get_effective_dexterity(), CharacterStats.get_effective_intelligence()]
	text += "WIS: %d  VIT: %d\n" % [CharacterStats.get_effective_wisdom(), CharacterStats.get_effective_vitality()]
	text += "\n"
	text += "Attack Speed: %.2fs\n" % CharacterStats.get_attack_cooldown()
	text += "Base Damage: %.1f\n" % CharacterStats.get_base_damage()
	text += "Max HP: %.0f\n" % CharacterStats.get_max_health()
	text += "Crit Chance: %.1f%%\n" % (CharacterStats.get_base_crit_chance() * 100)
	text += "Move Speed: %.0f" % CharacterStats.get_movement_speed()
	
	stats_label.text = text

func _on_level_up(new_level: int) -> void:
	"""Called when player levels up"""
	update_display()
	
	# Flash effect
	if level_label:
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(level_label, "scale", Vector2(1.5, 1.5), 0.2).set_ease(Tween.EASE_OUT)
		tween.tween_property(level_label, "modulate", Color.GOLD, 0.2)
		tween.chain().tween_property(level_label, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(level_label, "modulate", Color.WHITE, 0.3)
	
	# Update stats if visible
	if show_stats:
		update_stats_display()

func _on_xp_gained(amount: int, total: int) -> void:
	"""Called when player gains XP"""
	update_display()
	
	# Pulse effect on XP bar
	if xp_bar:
		var tween = create_tween()
		tween.tween_property(xp_bar, "modulate", Color(1.2, 1.2, 0.5), 0.1)
		tween.tween_property(xp_bar, "modulate", Color.WHITE, 0.2)
