extends Node

## Character Stats System
## Autoload singleton managing player progression
## Add to project.godot as "CharacterStats"

# ============================================
# LEVEL & EXPERIENCE
# ============================================

var level: int = Constants.STARTING_LEVEL
var experience: int = Constants.STARTING_XP
var experience_to_next_level: int = Constants.BASE_XP_REQUIREMENT

# ============================================
# CURRENCY
# ============================================

var gold: int = Constants.STARTING_GOLD  # Currency for purchasing equipment (starting gold for testing)

# ============================================
# BASE ATTRIBUTES
# ============================================

var strength: int = Constants.STARTING_STRENGTH  # Affects base damage
var agility: int = Constants.STARTING_AGILITY    # Affects attack speed
var vitality: int = Constants.STARTING_VITALITY  # Affects max HP
var luck: int = Constants.STARTING_LUCK          # Affects crit chance

# Temporary buffs (from campfires, potions, etc.)
var campfire_crit_buff: float = 0.0  # Bonus crit chance from campfire bone embers

# Starting stats (for reset/new character)
const STARTING_STRENGTH: int = Constants.STARTING_STRENGTH
const STARTING_AGILITY: int = Constants.STARTING_AGILITY
const STARTING_VITALITY: int = Constants.STARTING_VITALITY
const STARTING_LUCK: int = Constants.STARTING_LUCK

# ============================================
# EQUIPPED WEAPON
# ============================================

var equipped_weapon = null  # Type: Weapon (untyped to avoid circular dependency)

# ============================================
# EQUIPPED ARMOR
# ============================================

var equipped_armor = {
	"mainhand": null,  # Primary weapon (right hand)
	"offhand": null,   # Secondary weapon/shield (left hand)
	"head": null,      # Helmet/helm
	"chest": null,     # Body armor/vest
	"arms": null,      # Armguards/bracers
	"hands": null,     # Gloves
	"legs": null,      # Pants/greaves
	"feet": null       # Boots
}

# ============================================
# SIGNALS
# ============================================

signal level_up(new_level: int)
signal experience_gained(amount: int, total: int)
signal stat_changed(stat_name: String, old_value: int, new_value: int)
signal weapon_equipped(weapon)  # weapon is Weapon type
signal weapon_unequipped()
signal armor_equipped(slot: String, armor_item: Dictionary)
signal armor_unequipped(slot: String, armor_item: Dictionary)
signal gold_changed(amount: int, total: int)  # amount can be positive (gain) or negative (spend)

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	DebugConfig.debug_log("═══════════════════════════════════════")
	DebugConfig.debug_log("CharacterStats System Initialized")
	DebugConfig.debug_log("Level: %d" % level)
	DebugConfig.debug_log("Stats: STR:%d AGI:%d VIT:%d LUCK:%d" % [strength, agility, vitality, luck])
	DebugConfig.debug_log("═══════════════════════════════════════")

	# Start unarmed - player must buy/equip weapons
	equipped_weapon = null
	print("👊 Player starts UNARMED - buy weapons from vendor!")

	# Equip default starting clothes (non-removable)
	_equip_starting_clothes()

func _equip_starting_clothes() -> void:
	"""Equip default shirt and pants - minimal value, no stats"""
	# Default white shirt (chest slot)
	equipped_armor["chest"] = {
		"name": "Tattered Shirt",
		"description": "A worn white shirt. Better than nothing.",
		"type": "armor",
		"slot": "chest",
		"armor": 0,
		"value": 1,
		"rarity": "COMMON",
		"can_trade": true,  # Can be sold/destroyed/unequipped
		"stackable": false,
		"quantity": 1,
		"sprite_name": "white_shirt"  # Sprite to use for rendering
	}

	# Default green pants (legs slot)
	equipped_armor["legs"] = {
		"name": "Tattered Pants",
		"description": "Worn pants. At least you're not naked.",
		"type": "armor",
		"slot": "legs",
		"armor": 0,
		"value": 1,
		"rarity": "COMMON",
		"can_trade": true,  # Can be sold/destroyed/unequipped
		"stackable": false,
		"quantity": 1,
		"sprite_name": "green_pants"  # Sprite to use for rendering
	}

	print("👕 Equipped starting clothes: Tattered Shirt, Tattered Pants")

# ============================================
# DERIVED STATS (Combat Calculations)
# ============================================

func get_attack_cooldown() -> float:
	"""Calculate attack cooldown based on agility + weapon bonuses"""
	# 🔧 BALANCED: Progression curve for level 30 cap
	# Level 1 (AGI 10): 1.0s (1 attack/sec)
	# Level 10 (AGI 28): 0.27s (3.7 attacks/sec)
	# Level 15 (AGI 38): 0.19s (5.3 attacks/sec)
	# Level 20 (AGI 48): 0.15s (6.7 attacks/sec)
	# Level 25 (AGI 58): 0.12s (8.2 attacks/sec) - Near uncapped feel, needs gear to hit 0.05s cap
	var base_cooldown = 1.0 / (1.0 + (agility - 10) * 0.15)
	
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
	# Base formula: 1% at 10 LUCK, +0.6% per point (for rhythm combat)
	var stat_crit = 0.01 + (luck - 10) * 0.006  # 16% at 35 LUCK (level 25+)

	# Add weapon bonus
	var weapon_crit = 0.0
	if equipped_weapon:
		weapon_crit = equipped_weapon.crit_chance_bonus

	# Add campfire buff (from bone embers)
	var total_crit = stat_crit + weapon_crit + campfire_crit_buff

	# Debug logging for crit calculation
	if campfire_crit_buff > 0:
		print("🎯 CRIT CALCULATION:")
		print("   Luck: %d → Stat Crit: %.1f%%" % [luck, stat_crit * 100])
		print("   Weapon Crit: %.1f%%" % (weapon_crit * 100))
		print("   Campfire Buff: %.1f%%" % (campfire_crit_buff * 100))
		print("   Total (unclamped): %.1f%%" % (total_crit * 100))
		print("   Total (clamped): %.1f%%" % (clamp(total_crit, 0.01, 0.50) * 100))

	return clamp(total_crit, 0.01, 0.50)  # Min 1%, max 50%

func get_movement_speed() -> float:
	"""Calculate movement speed (fixed for all levels)"""
	# Fixed: 200 for all levels (equipment may add bonuses later)
	return 200.0

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
	# Check max level cap
	if level >= Constants.MAX_LEVEL:
		print("⚠️  MAX LEVEL REACHED: ", Constants.MAX_LEVEL)
		experience = 0
		experience_to_next_level = 999999999  # Prevent further leveling
		return

	# Deduct XP
	experience -= experience_to_next_level
	level += 1

	# Calculate next level XP requirement (exponential curve)
	# Clamp to prevent overflow at high levels
	var level_exponent = min(level - 1, 50)  # Cap exponent to prevent overflow
	experience_to_next_level = int(Constants.BASE_XP_REQUIREMENT * pow(Constants.XP_SCALING_EXPONENT, level_exponent))

	# Grant stat points (balanced increases) - ONLY up to level 25
	var stat_gain_str = 0
	var stat_gain_agi = 0
	var stat_gain_vit = 0
	var stat_gain_luck = 0

	if level <= Constants.STAT_GAIN_CAP_LEVEL:
		stat_gain_str = 2
		stat_gain_agi = 2
		stat_gain_vit = 2
		stat_gain_luck = 1

		strength += stat_gain_str
		agility += stat_gain_agi
		vitality += stat_gain_vit
		luck += stat_gain_luck
	
	# Emit signal
	level_up.emit(level)
	
	# Celebratory print
	print("\n╔══════════════════════════════════════╗")
	print("║      🎉 LEVEL UP! Level ", level, "         ║")
	print("╚══════════════════════════════════════╝")
	if level <= Constants.STAT_GAIN_CAP_LEVEL:
		print("  STR: ", strength, " (+", stat_gain_str, ")")
		print("  AGI: ", agility, " (+", stat_gain_agi, ")")
		print("  VIT: ", vitality, " (+", stat_gain_vit, ")")
		print("  LUCK: ", luck, " (+", stat_gain_luck, ")")
	else:
		print("  ⚠️  MAX STAT LEVEL (", Constants.STAT_GAIN_CAP_LEVEL, ") - No stat gains")
		print("  STR: ", strength, " | AGI: ", agility, " | VIT: ", vitality, " | LUCK: ", luck)
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
	if amount < 0:
		return false

	# Allow free items (amount == 0)
	if amount == 0:
		return true

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

func unequip_weapon() -> bool:
	"""Remove equipped weapon and return to inventory"""
	if not equipped_weapon:
		print("No weapon equipped")
		return false

	# Convert Weapon resource to dict for inventory
	var weapon_dict = {
		"name": equipped_weapon.weapon_name,
		"description": equipped_weapon.description,
		"type": "weapon",
		"slot": "mainhand",
		"weapon_type": equipped_weapon.weapon_type,
		"base_damage": equipped_weapon.base_damage,
		"attack_speed": _speed_bonus_to_category(equipped_weapon.attack_speed_bonus),
		"crit_chance": equipped_weapon.crit_chance_bonus,
		"required_level": equipped_weapon.required_level,
		"rarity": Weapon.Rarity.keys()[equipped_weapon.rarity],
		"value": 0,  # TODO: Store original purchase price
		"can_trade": equipped_weapon.can_trade,
		"stackable": false,
		"quantity": 1
	}

	# Add back to inventory
	if InventorySystem.add_item(weapon_dict):
		equipped_weapon = null
		weapon_unequipped.emit()
		print("🛡️  Unequipped weapon: %s" % weapon_dict.get("name", "Unknown"))
		return true
	else:
		print("❌ Inventory full! Cannot unequip weapon")
		return false

func _speed_bonus_to_category(bonus: float) -> String:
	"""Convert attack_speed_bonus back to category string"""
	if bonus < -0.15:
		return "fast"
	elif bonus > 0.15:
		return "slow"
	else:
		return "medium"

# ============================================
# ARMOR EQUIPPING
# ============================================

func equip_armor(armor_item: Dictionary) -> bool:
	"""Equip an armor piece to the appropriate slot"""
	if not armor_item or armor_item.is_empty():
		push_error("Trying to equip null or empty armor")
		return false

	var slot = armor_item.get("slot", "")
	if slot not in equipped_armor:
		push_error("Invalid armor slot: " + slot)
		return false

	# Unequip existing armor in that slot (return to inventory)
	if equipped_armor[slot]:
		var old_armor = equipped_armor[slot]
		InventorySystem.add_item(old_armor)

	# Equip new armor
	equipped_armor[slot] = armor_item
	armor_equipped.emit(slot, armor_item)

	print("🛡️  Equipped %s: %s (+%d Defense)" % [slot.capitalize(), armor_item.get("name", "Unknown"), armor_item.get("defense", 0)])
	return true

func unequip_armor(slot: String) -> bool:
	"""Unequip armor from a slot and return to inventory"""
	if slot not in equipped_armor:
		push_error("Invalid armor slot: " + slot)
		return false

	var armor_item = equipped_armor[slot]
	if not armor_item:
		print("No armor equipped in %s slot" % slot)
		return false

	# Add back to inventory
	if InventorySystem.add_item(armor_item):
		equipped_armor[slot] = null
		armor_unequipped.emit(slot, armor_item)
		print("🛡️  Unequipped %s: %s" % [slot.capitalize(), armor_item.get("name", "Unknown")])
		return true
	else:
		print("❌ Inventory full! Cannot unequip armor")
		return false

func get_total_defense() -> int:
	"""Calculate total defense from all equipped armor"""
	var total = 0
	for slot in equipped_armor:
		var armor_item = equipped_armor[slot]
		if armor_item:
			total += armor_item.get("defense", 0)
	return total

func get_equipped_armor_count() -> int:
	"""Return number of armor pieces equipped (excludes weapons)"""
	var count = 0
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		if equipped_armor.get(slot):
			count += 1
	return count

func create_starter_weapon():  # Returns Weapon
	"""Create the default starter weapon"""
	var Weapon = load("res://scripts/resources/Weapon.gd")
	var weapon = Weapon.new()
	weapon.weapon_name = "Rusty Sword"
	weapon.weapon_type = "sword"
	weapon.base_damage = 2.0  # Basic starter damage (total 7 damage at level 1)
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
	level = Constants.STARTING_LEVEL
	experience = Constants.STARTING_XP
	experience_to_next_level = Constants.BASE_XP_REQUIREMENT
	
	strength = STARTING_STRENGTH
	agility = STARTING_AGILITY
	vitality = STARTING_VITALITY
	luck = STARTING_LUCK

	# Reset to unarmed
	equipped_weapon = null

	print("Character reset to level 1 (unarmed)")

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
	level = data.get("level", Constants.STARTING_LEVEL)
	experience = data.get("experience", Constants.STARTING_XP)
	experience_to_next_level = data.get("experience_to_next_level", Constants.BASE_XP_REQUIREMENT)
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
		# Check if we're at max level
		if level >= Constants.MAX_LEVEL:
			print("⚠️  Cannot add more levels - MAX LEVEL ", Constants.MAX_LEVEL, " reached!")
			return

		# Grant enough XP to level up cleanly (prevents negative XP)
		var xp_needed = experience_to_next_level - experience
		if xp_needed > 0:
			experience += xp_needed
		level_up_character()

func debug_set_level(target_level: int) -> void:
	"""Set character to specific level"""
	# Clamp target level to max
	var clamped_level = min(target_level, Constants.MAX_LEVEL)
	if target_level > Constants.MAX_LEVEL:
		print("⚠️  Target level ", target_level, " exceeds MAX_LEVEL ", Constants.MAX_LEVEL)
		print("   Setting to MAX_LEVEL instead")

	reset_character()
	while level < clamped_level:
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
