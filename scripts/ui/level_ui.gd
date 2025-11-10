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

func _ready() -> void:
	# Connect to CharacterStats signals
	CharacterStats.level_up.connect(_on_level_up)
	CharacterStats.experience_gained.connect(_on_xp_gained)
	
	# Initial update
	update_display()
	
	# Hide stats panel by default
	if stats_panel:
		stats_panel.visible = false

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
