extends Node
class_name CritSystem

# Crit settings
@export var base_crit_chance: float = 0.05  # 5% base chance
@export var pity_increment: float = 0.01    # +1% per non-crit
@export var pity_threshold: int = 20        # Guaranteed crit after 20 non-crits

# Tracking
var non_crit_streak: int = 0
var current_crit_chance: float = 0.05  # ✅ FIX: Match base_crit_chance!

func _ready() -> void:
	current_crit_chance = base_crit_chance
	print("CritSystem initialized: Base %.1f%%, Pity +%.1f%%, Threshold: %d" % 
		[base_crit_chance * 100, pity_increment * 100, pity_threshold])

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
	# Reset pity system
	non_crit_streak = 0
	current_crit_chance = base_crit_chance

func on_crit_fail() -> void:
	# Increase pity counter
	non_crit_streak += 1
	
	# Increase crit chance for next attack
	current_crit_chance = base_crit_chance + (pity_increment * non_crit_streak)
	
	# Cap at 100% (guaranteed crit after threshold)
	if non_crit_streak >= pity_threshold:
		current_crit_chance = 1.0
		print("! PITY ACTIVATED - Next hit guaranteed crit !")
	else:
		print("Non-crit streak: %d | Next chance: %.1f%%" % [non_crit_streak, current_crit_chance * 100])

# Get the crit damage multiplier
func get_crit_multiplier() -> float:
	return 2.0  # 2x damage for crits
	
	
func get_next_crit_chance() -> float:
	return current_crit_chance

func get_non_crit_streak() -> int:
	return non_crit_streak
