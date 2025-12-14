extends Node
class_name CritSystem

## Simple crit system - crits are based purely on Luck stat
## No pity system, no weapon bonuses - just gear and stats

func _ready() -> void:
	print("CritSystem initialized: Crit chance from Luck stat only")

func get_player_crit_chance() -> float:
	"""Get the player's crit chance from stats only (no weapon bonus)"""
	if CharacterStats:
		return CharacterStats.get_base_crit_chance()
	return 0.05  # Fallback 5% if CharacterStats not available

func roll_for_crit() -> bool:
	"""Roll for a critical hit based on current crit chance"""
	var crit_chance = get_player_crit_chance()
	var roll = randf()

	if roll < crit_chance:
		print("★ CRITICAL HIT! (%.1f%% chance)" % [crit_chance * 100])
		return true
	return false

func get_crit_multiplier() -> float:
	"""Get the damage multiplier for critical hits"""
	return Constants.CRIT_DAMAGE_MULTIPLIER if "CRIT_DAMAGE_MULTIPLIER" in Constants else 2.0

func get_current_crit_chance() -> float:
	"""Get current crit chance for UI display"""
	return get_player_crit_chance()
