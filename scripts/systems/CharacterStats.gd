extends Node

## Character Stats System
## Autoload singleton managing player progression
## Add to project.godot as "CharacterStats"

# ============================================
# LEVEL & EXPERIENCE
# ============================================

var level: int = 1
var experience: int = 0
var experience_to_next_level: int = 100

# ============================================
# CURRENCY
# ============================================

var gold: int = 500         # Currency for purchasing equipment (starting gold for testing)

# ============================================
# BASE ATTRIBUTES
# ============================================

var strength: int = 10      # Affects base damage
var agility: int = 10       # Affects attack speed
var vitality: int = 10      # Affects max HP
var luck: int = 10          # Affects crit chance

# Starting stats (for reset/new character)
const STARTING_STRENGTH: int = 10
const STARTING_AGILITY: int = 10
const STARTING_VITALITY: int = 10
const STARTING_LUCK: int = 10

# ============================================
# EQUIPPED WEAPON
# ============================================

var equipped_weapon = null  # Type: Weapon (untyped to avoid circular dependency)

# ============================================
# SIGNALS
# ============================================

signal level_up(new_level: int)
signal experience_gained(amount: int, total: int)
signal stat_changed(stat_name: String, old_value: int, new_value: int)
signal weapon_equipped(weapon)  # weapon is Weapon type
signal weapon_unequipped()
signal gold_changed(amount: int, total: int)  # amount can be positive (gain) or negative (spend)

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	print("═══════════════════════════════════════")
	print("CharacterStats System Initialized")
	print("Level: ", level)
	print("Stats: STR:", strength, " AGI:", agility, " VIT:", vitality, " LUCK:", luck)
	print("═══════════════════════════════════════")
	
	# Create default starter weapon
	equipped_weapon = create_starter_weapon()

# ============================================
# DERIVED STATS (Combat Calculations)
# ============================================

func get_attack_cooldown() -> float:
	"""Calculate attack cooldown based on agility + weapon bonuses"""
	# 🔧 BALANCED: Good progression curve
	# Level 1 (AGI 10): 1.0s
	# Level 10 (AGI 28): 0.48s  
	# Level 25 (AGI 58): 0.24s
	# Level 50 (AGI 108): 0.14s
	var base_cooldown = 1.0 / (1.0 + (agility - 10) * 0.06)
	
	# Apply weapon bonus
	var weapon_bonus = 0.0
	if equipped_weapon:
		weapon_bonus = equipped_weapon.attack_speed_bonus
	
	var final_cooldown = base_cooldown * (1.0 + weapon_bonus)
	return clamp(final_cooldown, 0.05, 2.0)  # Min 0.05s, max 2.0s

func get_base_damage() -> float:
	"""Calculate base damage from strength + weapon"""
	# Base formula: 5 damage at 10 STR, +0.5 per point
	var stat_damage = 5.0 + (strength - 10) * 0.5
	
	# Add weapon damage
	var weapon_damage = 0.0
	if equipped_weapon:
		weapon_damage = equipped_weapon.base_damage
	
	return stat_damage + weapon_damage

func get_max_health() -> float:
	"""Calculate max HP from vitality"""
	# Base formula: 100 HP at 10 VIT, +10 per point
	return 100.0 + (vitality - 10) * 10.0

func get_base_crit_chance() -> float:
	"""Calculate crit chance from luck + weapon"""
	# Base formula: 1% at 10 LUCK, +0.2% per point
	var stat_crit = 0.01 + (luck - 10) * 0.002  # 5% at 30 LUCK, 9% at 50 LUCK
	
	# Add weapon bonus
	var weapon_crit = 0.0
	if equipped_weapon:
		weapon_crit = equipped_weapon.crit_chance_bonus
	
	return clamp(stat_crit + weapon_crit, 0.01, 0.50)  # Min 1%, max 50%

func get_movement_speed() -> float:
	"""Calculate movement speed (slight AGI bonus)"""
	# Base: 200, +1 per AGI point above 10
	return 200.0 + (agility - 10) * 1.0

# ============================================
# EXPERIENCE & LEVELING
# ============================================

func gain_experience(amount: int) -> void:
	"""Grant experience points and check for level ups"""
	if amount <= 0:
		return
	
	experience += amount
	experience_gained.emit(amount, experience)
	
	print("💰 Gained ", amount, " XP (Total: ", experience, "/", experience_to_next_level, ")")
	
	# Check for level up (can level multiple times from one XP gain)
	while experience >= experience_to_next_level:
		level_up_character()

func level_up_character() -> void:
	"""Level up the character and grant stat increases"""
	# Deduct XP
	experience -= experience_to_next_level
	level += 1
	
	# Calculate next level XP requirement (exponential curve)
	experience_to_next_level = int(100 * pow(1.15, level - 1))
	
	# Grant stat points (balanced increases)
	strength += 2
	agility += 2
	vitality += 2
	luck += 1
	
	# Emit signal
	level_up.emit(level)
	
	# Celebratory print
	print("\n╔══════════════════════════════════════╗")
	print("║      🎉 LEVEL UP! Level ", level, "         ║")
	print("╚══════════════════════════════════════╝")
	print("  STR: ", strength, " (+2)")
	print("  AGI: ", agility, " (+2)")
	print("  VIT: ", vitality, " (+2)")
	print("  LUCK: ", luck, " (+1)")
	print("  Next Level: ", experience_to_next_level, " XP")
	print("════════════════════════════════════════\n")

func get_experience_progress() -> float:
	"""Returns XP progress as 0-1 value for UI bars"""
	if experience_to_next_level <= 0:
		return 1.0
	return float(experience) / float(experience_to_next_level)

# ============================================
# GOLD / CURRENCY
# ============================================

func add_gold(amount: int) -> void:
	"""Add gold (from enemy drops, quest rewards, etc)"""
	if amount <= 0:
		return

	gold += amount
	gold_changed.emit(amount, gold)

	print("💰 Gained ", amount, " gold (Total: ", gold, ")")

func spend_gold(amount: int) -> bool:
	"""Spend gold (returns false if not enough gold)"""
	if amount <= 0:
		return false

	if gold < amount:
		print("❌ Not enough gold! Need ", amount, " but only have ", gold)
		return false

	gold -= amount
	gold_changed.emit(-amount, gold)

	print("💸 Spent ", amount, " gold (Remaining: ", gold, ")")
	return true

func can_afford(amount: int) -> bool:
	"""Check if player can afford something"""
	return gold >= amount

# ============================================
# STAT MODIFICATION
# ============================================

func increase_stat(stat_name: String, amount: int) -> void:
	"""Increase a stat by amount (for items, buffs, etc)"""
	var old_value: int
	
	match stat_name.to_lower():
		"strength", "str":
			old_value = strength
			strength += amount
			stat_changed.emit("strength", old_value, strength)
		"agility", "agi":
			old_value = agility
			agility += amount
			stat_changed.emit("agility", old_value, agility)
		"vitality", "vit":
			old_value = vitality
			vitality += amount
			stat_changed.emit("vitality", old_value, vitality)
		"luck":
			old_value = luck
			luck += amount
			stat_changed.emit("luck", old_value, luck)

# ============================================
# WEAPON SYSTEM
# ============================================

func equip_weapon(weapon) -> void:  # weapon: Weapon
	"""Equip a weapon"""
	if not weapon:
		push_error("Trying to equip null weapon")
		return
	
	equipped_weapon = weapon
	weapon_equipped.emit(weapon)
	
	print("⚔️  Equipped: ", weapon.weapon_name)
	print("   Damage: +", weapon.base_damage)
	print("   Attack Speed: ", weapon.attack_speed_bonus * 100, "%")
	print("   Crit Chance: +", weapon.crit_chance_bonus * 100, "%")

func unequip_weapon() -> void:
	"""Remove equipped weapon (revert to fists or starter weapon)"""
	equipped_weapon = create_starter_weapon()
	weapon_unequipped.emit()
	print("Weapon unequipped")

func create_starter_weapon():  # Returns Weapon
	"""Create the default starter weapon"""
	var Weapon = load("res://scripts/resources/Weapon.gd")
	var weapon = Weapon.new()
	weapon.weapon_name = "Rusty Sword"
	weapon.weapon_type = "sword"
	weapon.base_damage = 0.0  # Stats provide base damage
	weapon.attack_speed_bonus = 0.0
	weapon.crit_chance_bonus = 0.0
	weapon.can_trade = false
	weapon.required_level = 1
	return weapon

# ============================================
# CHARACTER RESET / NEW GAME
# ============================================

func reset_character() -> void:
	"""Reset character to level 1 (for testing or new game)"""
	level = 1
	experience = 0
	experience_to_next_level = 100
	
	strength = STARTING_STRENGTH
	agility = STARTING_AGILITY
	vitality = STARTING_VITALITY
	luck = STARTING_LUCK
	
	equipped_weapon = create_starter_weapon()
	
	print("Character reset to level 1")

# ============================================
# SAVE / LOAD (Future)
# ============================================

func get_save_data() -> Dictionary:
	"""Returns dictionary of all character data for saving"""
	return {
		"level": level,
		"experience": experience,
		"experience_to_next_level": experience_to_next_level,
		"strength": strength,
		"agility": agility,
		"vitality": vitality,
		"luck": luck,
		# Weapon data would go here
	}

func load_save_data(data: Dictionary) -> void:
	"""Load character data from saved dictionary"""
	level = data.get("level", 1)
	experience = data.get("experience", 0)
	experience_to_next_level = data.get("experience_to_next_level", 100)
	strength = data.get("strength", STARTING_STRENGTH)
	agility = data.get("agility", STARTING_AGILITY)
	vitality = data.get("vitality", STARTING_VITALITY)
	luck = data.get("luck", STARTING_LUCK)
	
	print("Character data loaded: Level ", level)

# ============================================
# DEBUG / TESTING
# ============================================

func debug_add_levels(count: int) -> void:
	"""Add levels instantly for testing (without XP penalties)"""
	for i in range(count):
		# 🔧 FIX: Grant enough XP to level up cleanly (prevents negative XP)
		var xp_needed = experience_to_next_level - experience
		if xp_needed > 0:
			experience += xp_needed
		level_up_character()

func debug_set_level(target_level: int) -> void:
	"""Set character to specific level"""
	reset_character()
	while level < target_level:
		level_up_character()

func debug_fix_negative_xp() -> void:
	"""Fix negative XP from old debug leveling"""
	if experience < 0:
		print("⚠️ Fixing negative XP: was ", experience)
		experience = 0
		print("✅ Reset XP to 0")
	else:
		print("✅ XP is positive: ", experience)

func print_stats() -> void:
	"""Print all current stats to console"""
	print("\n═══ CHARACTER STATS ═══")
	print("Level: ", level)
	print("XP: ", experience, "/", experience_to_next_level)
	print("\n--- Attributes ---")
	print("Strength: ", strength)
	print("Agility: ", agility)
	print("Vitality: ", vitality)
	print("Luck: ", luck)
	print("\n--- Combat Stats ---")
	print("Attack Speed: ", "%.3f" % get_attack_cooldown(), "s")
	print("Base Damage: ", "%.1f" % get_base_damage())
	print("Max Health: ", "%.0f" % get_max_health())
	print("Crit Chance: ", "%.1f" % (get_base_crit_chance() * 100), "%")
	print("Movement Speed: ", "%.0f" % get_movement_speed())
	print("\n--- Weapon ---")
	if equipped_weapon:
		print("Equipped: ", equipped_weapon.weapon_name)
	print("═══════════════════════\n")
