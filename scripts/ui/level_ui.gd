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
var combat_indicator: Label = null  # IN COMBAT indicator
var combat_tween: Tween = null  # Store tween for cleanup
var fps_label: Label = null  # FPS counter for debugging
var fps_update_timer: float = 0.0

func _ready() -> void:
	# Connect to CharacterStats signals
	CharacterStats.level_up.connect(_on_level_up)
	CharacterStats.experience_gained.connect(_on_xp_gained)

	# Create combat indicator
	create_combat_indicator()

	# Create FPS counter
	create_fps_counter()

	# Initial update
	update_display()

	# Hide stats panel by default
	if stats_panel:
		stats_panel.visible = false

func create_combat_indicator() -> void:
	"""Create the IN COMBAT indicator label"""
	combat_indicator = Label.new()
	combat_indicator.name = "CombatIndicator"
	combat_indicator.text = "⚔️ IN COMBAT"
	combat_indicator.add_theme_font_size_override("font_size", 24)
	combat_indicator.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))  # Red
	combat_indicator.add_theme_color_override("font_outline_color", Color.BLACK)
	combat_indicator.add_theme_constant_override("outline_size", 3)
	combat_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Position below XP bar
	combat_indicator.position = Vector2(20, 120)
	combat_indicator.size = Vector2(300, 40)
	combat_indicator.visible = false  # Hidden by default

	# Add to Control node
	$Control.add_child(combat_indicator)

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
	if not combat_indicator or not is_instance_valid(combat_indicator):
		return

	# Performance: Only check combat status every 0.2s, not every frame
	combat_check_timer += delta
	if combat_check_timer < COMBAT_CHECK_INTERVAL:
		return
	combat_check_timer = 0.0

	var in_combat = is_player_in_combat()
	if in_combat != combat_indicator.visible:
		combat_indicator.visible = in_combat

		# Pulse effect when entering combat
		if in_combat:
			# Kill previous tween if it exists
			if combat_tween and combat_tween.is_valid():
				combat_tween.kill()

			combat_tween = create_tween()
			combat_tween.set_loops(0)  # Infinite
			combat_tween.tween_property(combat_indicator, "modulate:a", 0.5, 0.5)
			combat_tween.tween_property(combat_indicator, "modulate:a", 1.0, 0.5)
		else:
			# Exiting combat - kill tween
			if combat_tween and combat_tween.is_valid():
				combat_tween.kill()
				combat_tween = null
			combat_indicator.modulate.a = 1.0  # Reset alpha

func is_player_in_combat() -> bool:
	"""Check if any enemy is in combat with the player"""
	# Safety check - don't run during tree exit
	if not is_inside_tree():
		return false

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player or not is_instance_valid(player):
		return false

	var enemies = get_tree().get_nodes_in_group(Constants.GROUP_ENEMIES)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Check if enemy has AI and is in combat
		if enemy.has_node("EnemyAI"):
			var ai = enemy.get_node("EnemyAI")
			if is_instance_valid(ai) and ai.get("is_in_combat"):
				return true

	return false

func _input(event: InputEvent) -> void:
	# Toggle stats panel with F8
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
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
	text += "═══ STATS ═══\n"
	text += "STR: %d\n" % CharacterStats.strength
	text += "AGI: %d\n" % CharacterStats.agility
	text += "VIT: %d\n" % CharacterStats.vitality
	text += "LUCK: %d\n" % CharacterStats.luck
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
