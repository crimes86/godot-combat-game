extends Label

## Chain UI Display
## Shows current chain level with color-coded tiers

func _ready() -> void:
	# Hide chain UI until system is fully implemented
	visible = false
	return

	# Connect to ChainManager signals
	ChainManager.chain_increased.connect(_on_chain_increased)
	ChainManager.chain_reset.connect(_on_chain_reset)
	ChainManager.overdrive_activated.connect(_on_overdrive_activated)

	# Initial display
	update_display()

func _on_chain_increased(new_level: int) -> void:
	update_display()
	# Optional: Add scale animation or particle effect here

func _on_chain_reset(reason: String) -> void:
	update_display()

func _on_overdrive_activated() -> void:
	update_display()
	# Optional: Add special OVERDRIVE animation/effects

func update_display() -> void:
	var level = ChainManager.get_chain_level()
	
	if level == 0:
		text = "Chain: 0x"
		modulate = Color(0.5, 0.5, 0.5)  # Gray
	else:
		text = "Chain: %dx" % level
		modulate = get_chain_color(level)

func get_chain_color(level: int) -> Color:
	# Color tiers based on chain level
	if level >= 10:
		return Color(1.0, 0.0, 1.0)  # Magenta (OVERDRIVE)
	elif level >= 7:
		return Color(1.0, 0.5, 0.0)  # Orange (High)
	elif level >= 4:
		return Color(1.0, 1.0, 0.0)  # Yellow (Medium)
	else:
		return Color(1.0, 1.0, 1.0)  # White (Low)
