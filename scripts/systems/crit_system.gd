extends Node
class_name CritSystem

# Crit settings
@export var pity_increment: float = 0.01    # +1% per non-crit
@export var pity_threshold: int = 20        # Guaranteed crit after 20 non-crits

# Tracking
var non_crit_streak: int = 0
var current_crit_chance: float = 0.0

func _ready() -> void:
	# Initialize with player's actual crit chance (includes weapon bonus)
	current_crit_chance = get_player_base_crit()
	print("CritSystem initialized: Base %.1f%%, Pity +%.1f%%, Threshold: %d" %
		[current_crit_chance * 100, pity_increment * 100, pity_threshold])

func get_player_base_crit() -> float:
	"""Get the player's base crit chance from stats + weapon"""
	if CharacterStats:
		return CharacterStats.get_base_crit_chance()
	return 0.05  # Fallback if CharacterStats not available

# Call this when the player attacks
func roll_for_crit() -> bool:
	# Generate random number between 0 and 1
	var roll = randf()
	
	print("Crit roll: %.4f vs chance: %.2f%%" % [roll, current_crit_chance * 100])
	
	# Check if we crit
	if roll < current_crit_chance:
		# CRIT!
		on_crit_success()
		return true
	else:
		# No crit
		on_crit_fail()
		return false

func on_crit_success() -> void:
	print("★ CRITICAL HIT! ★")
	# Reset pity system to weapon's base crit chance
	non_crit_streak = 0
	current_crit_chance = get_player_base_crit()

func on_crit_fail() -> void:
	# Increase pity counter
	non_crit_streak += 1

	# Increase crit chance for next attack (using weapon's actual base)
	var base_crit = get_player_base_crit()
	current_crit_chance = base_crit + (pity_increment * non_crit_streak)

	# Cap at 100% (guaranteed crit after threshold)
	if non_crit_streak >= pity_threshold:
		current_crit_chance = 1.0
		print("! PITY ACTIVATED - Next hit guaranteed crit !")
	else:
		print("Non-crit streak: %d | Next chance: %.1f%% (base: %.1f%%)" %
			[non_crit_streak, current_crit_chance * 100, base_crit * 100])

# Get the crit damage multiplier
func get_crit_multiplier() -> float:
	return 2.0  # 2x damage for crits
	
	
func get_next_crit_chance() -> float:
	return current_crit_chance

func get_non_crit_streak() -> int:
	return non_crit_streak

func on_weapon_changed() -> void:
	"""Call this when player changes weapons to update base crit chance"""
	var new_base_crit = get_player_base_crit()

	# Update current crit chance while maintaining pity progress
	current_crit_chance = new_base_crit + (pity_increment * non_crit_streak)

	print("Weapon changed! New base crit: %.1f%%, Current chance: %.1f%%" %
		[new_base_crit * 100, current_crit_chance * 100])
