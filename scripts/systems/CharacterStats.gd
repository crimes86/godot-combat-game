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

# ============================================
# PERSISTENT TRACKING (for Database)
# ============================================

var kill_counts: Dictionary = {}  # enemy_type -> count
var achievements: Array = []  # List of unlocked achievement IDs
var total_playtime: float = 0.0  # Total seconds played (persisted)
var session_start_time: float = 0.0  # Start of current session (not persisted)

# Starting stats (for reset/new character)
const STARTING_STRENGTH: int = Constants.STARTING_STRENGTH
const STARTING_AGILITY: int = Constants.STARTING_AGILITY
const STARTING_VITALITY: int = Constants.STARTING_VITALITY
const STARTING_LUCK: int = Constants.STARTING_LUCK

# ============================================
# EQUIPPED WEAPON
# ============================================

var equipped_weapon = null  # Type: Weapon (untyped to avoid circular dependency)
var equipped_weapon_data: Dictionary = {}  # Original item dict (preserves forged metadata)

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

# Chain system signals (merged from ChainManager)
signal chain_increased(new_level: int)
signal chain_reset(reason: String)
signal overdrive_activated()

# ============================================
# CHAIN SYSTEM (merged from ChainManager)
# ============================================

# Chain settings
var chain_damage_per_level: float = Constants.CHAIN_DAMAGE_PER_LEVEL
var chain_max_level: int = Constants.CHAIN_MAX_LEVEL
var chain_timeout: float = Constants.CHAIN_TIMEOUT

# Chain reset reasons
enum ChainResetReason {
	MANUAL,          # Player manually reset
	FAILED_WINDOW,   # Failed a crit window
	TIMEOUT,         # Chain timeout expired
	PLAYER_DEATH,    # Player died
	STAGE_END        # Level/stage ended
}

# Chain state
var current_chain: int = 0
var last_attack_time: float = 0.0

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	Constants.debug_log("═══════════════════════════════════════")
	Constants.debug_log("CharacterStats System Initialized")
	Constants.debug_log("Level: %d" % level)
	Constants.debug_log("Stats: STR:%d AGI:%d VIT:%d LUCK:%d" % [strength, agility, vitality, luck])
	Constants.debug_log("Chain system: signals chain_increased, chain_reset, overdrive_activated")
	Constants.debug_log("═══════════════════════════════════════")

	# Start unarmed - player must buy/equip weapons
	equipped_weapon = null
	print("👊 Player starts UNARMED - buy weapons from vendor!")

	# Equip default starting clothes (non-removable)
	_equip_starting_clothes()

func _process(delta: float) -> void:
	# Chain timeout check
	if current_chain > 0:
		var time_since_attack = Time.get_ticks_msec() / 1000.0 - last_attack_time
		if time_since_attack >= chain_timeout:
			reset_chain(ChainResetReason.TIMEOUT)

func _equip_starting_clothes() -> void:
	"""Equip default shirt and pants - minimal value, no stats"""
	# Default white shirt (chest slot)
	var shirt = {
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
	equipped_armor["chest"] = shirt
	armor_equipped.emit("chest", shirt)

	# Default green pants (legs slot)
	var pants = {
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
	equipped_armor["legs"] = pants
	armor_equipped.emit("legs", pants)

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
	# Base formula: 1% at 10 LUCK, +0.6% per point (for fast-paced combat)
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

func equip_weapon(weapon, item_data: Dictionary = {}) -> void:  # weapon: Weapon
	"""Equip a weapon. Pass item_data to preserve forged metadata."""
	if not weapon:
		push_error("Trying to equip null weapon")
		return

	equipped_weapon = weapon
	equipped_weapon_data = item_data.duplicate(true) if not item_data.is_empty() else {}
	weapon_equipped.emit(weapon)

	print("⚔️  Equipped: ", weapon.weapon_name)
	print("   Damage: +", weapon.base_damage)
	print("   Attack Speed: ", weapon.attack_speed_bonus * 100, "%")
	print("   Crit Chance: +", weapon.crit_chance_bonus * 100, "%")
	if equipped_weapon_data.get("is_forged", false):
		print("   [Forged item - metadata preserved]")

func unequip_weapon() -> bool:
	"""Remove equipped weapon and return to inventory"""
	if not equipped_weapon:
		print("No weapon equipped")
		return false

	# Use stored item data if available (preserves forged metadata), otherwise reconstruct
	var weapon_dict: Dictionary
	if not equipped_weapon_data.is_empty():
		weapon_dict = equipped_weapon_data.duplicate(true)
	else:
		# Fallback: Convert Weapon resource to dict for inventory
		weapon_dict = {
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
			"value": equipped_weapon.sell_value,
			"can_trade": equipped_weapon.can_trade,
			"stackable": false,
			"quantity": 1
		}

		# Add healing weapon properties if applicable
		if equipped_weapon.attack_mode != "melee":
			weapon_dict["attack_mode"] = equipped_weapon.attack_mode
			weapon_dict["healing_power"] = equipped_weapon.healing_power
			weapon_dict["heal_radius"] = equipped_weapon.heal_radius

	# Add back to inventory
	if InventorySystem.add_item(weapon_dict):
		equipped_weapon = null
		equipped_weapon_data = {}
		weapon_unequipped.emit()
		print("🛡️  Unequipped weapon: %s" % weapon_dict.get("name", "Unknown"))
		return true
	else:
		print("❌ Inventory full! Cannot unequip weapon")
		return false

func get_equipped_weapon_data() -> Dictionary:
	"""Get the stored weapon item data (includes forged metadata)"""
	if equipped_weapon_data.is_empty() and equipped_weapon:
		# Fallback: construct basic dict if no stored data
		return {
			"name": equipped_weapon.weapon_name,
			"description": equipped_weapon.description,
			"type": "weapon",
			"slot": "mainhand",
			"weapon_type": equipped_weapon.weapon_type,
			"base_damage": equipped_weapon.base_damage,
			"attack_speed_bonus": equipped_weapon.attack_speed_bonus,
			"crit_chance_bonus": equipped_weapon.crit_chance_bonus,
			"rarity": Weapon.Rarity.keys()[equipped_weapon.rarity]
		}
	return equipped_weapon_data

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
# CORPSE SYSTEM HELPERS
# ============================================

func get_armor_snapshot() -> Dictionary:
	"""Get deep copy of all equipped armor for corpse system"""
	var snapshot = {}
	for slot in equipped_armor:
		if equipped_armor[slot]:
			snapshot[slot] = equipped_armor[slot].duplicate(true)
		else:
			snapshot[slot] = null
	return snapshot

func get_weapon_as_dict() -> Dictionary:
	"""Convert equipped weapon to dictionary for corpse storage"""
	if not equipped_weapon:
		return {}

	var weapon_dict = {
		"name": equipped_weapon.weapon_name,
		"description": equipped_weapon.description,
		"type": "weapon",
		"slot": "mainhand",
		"weapon_type": equipped_weapon.weapon_type,
		"base_damage": equipped_weapon.base_damage,
		"attack_speed": _speed_bonus_to_category(equipped_weapon.attack_speed_bonus),
		"attack_speed_bonus": equipped_weapon.attack_speed_bonus,
		"crit_chance": equipped_weapon.crit_chance_bonus,
		"crit_chance_bonus": equipped_weapon.crit_chance_bonus,
		"required_level": equipped_weapon.required_level,
		"rarity": Weapon.Rarity.keys()[equipped_weapon.rarity],
		"value": equipped_weapon.sell_value,
		"can_trade": equipped_weapon.can_trade,
		"stackable": false,
		"quantity": 1
	}

	# Add healing weapon properties if applicable
	if equipped_weapon.attack_mode != "melee":
		weapon_dict["attack_mode"] = equipped_weapon.attack_mode
		weapon_dict["healing_power"] = equipped_weapon.healing_power
		weapon_dict["heal_radius"] = equipped_weapon.heal_radius

	return weapon_dict

func reset_equipment_to_default() -> void:
	"""Reset all armor slots to default clothes (death/reset)"""
	# Clear all slots first
	for slot in equipped_armor:
		equipped_armor[slot] = null

	# Clear weapon
	equipped_weapon = null

	# Re-equip starting clothes
	_equip_starting_clothes()

	print("🔄 Equipment reset to default clothes")

func clear_all_equipment() -> void:
	"""Remove all equipment without re-equipping defaults (for corpse snapshot)"""
	for slot in equipped_armor:
		if equipped_armor[slot] != null:
			armor_unequipped.emit(slot, equipped_armor[slot])
			equipped_armor[slot] = null

	if equipped_weapon:
		weapon_unequipped.emit()
		equipped_weapon = null

	# Reset gold
	gold = 0

	print("💀 All equipment cleared (death)")

func apply_death_xp_penalty() -> int:
	"""Apply XP penalty on death. Returns amount of XP lost."""
	const DEATH_XP_PENALTY_PERCENT: float = 0.10  # 10% of current level XP

	# Calculate XP needed for current level range
	var xp_for_current_level = get_xp_for_level(level)
	var xp_for_next_level = get_xp_for_level(level + 1)
	var level_xp_range = xp_for_next_level - xp_for_current_level

	# Calculate penalty (10% of level range)
	var xp_penalty = int(level_xp_range * DEATH_XP_PENALTY_PERCENT)

	# Apply penalty (can't go below current level threshold)
	var new_xp = max(xp_for_current_level, experience - xp_penalty)
	var actual_loss = experience - new_xp
	experience = new_xp

	print("💀 Death XP penalty: lost %d XP (now at %d)" % [actual_loss, experience])
	return actual_loss

func get_xp_for_level(target_level: int) -> int:
	"""Get total XP required to reach a specific level"""
	if target_level <= 1:
		return 0
	# Same formula used in add_experience
	var total_xp = 0
	for lvl in range(1, target_level):
		total_xp += int(Constants.BASE_XP_REQUIREMENT * pow(Constants.XP_SCALING_EXPONENT, lvl - 1))
	return total_xp

# ============================================
# SAVE / LOAD (Database Persistence)
# ============================================

func get_save_data() -> Dictionary:
	"""Returns dictionary of all character data for saving"""
	# Update playtime before saving
	update_total_playtime()

	# Serialize equipped weapon if exists
	var weapon_data = {}
	if equipped_weapon:
		weapon_data = {
			"weapon_name": equipped_weapon.weapon_name,
			"weapon_type": equipped_weapon.weapon_type,
			"base_damage": equipped_weapon.base_damage,
			"attack_speed_bonus": equipped_weapon.attack_speed_bonus,
			"crit_chance_bonus": equipped_weapon.crit_chance_bonus,
			"required_level": equipped_weapon.required_level,
			"rarity": equipped_weapon.rarity,
			"can_trade": equipped_weapon.can_trade,
			"description": equipped_weapon.description
		}

	# Get quest data if QuestManager exists
	var quest_data = {}
	if has_node("/root/QuestManager"):
		var quest_manager = get_node("/root/QuestManager")
		quest_data = quest_manager.get_save_data()

	return {
		# Core progression
		"level": level,
		"experience": experience,
		"experience_to_next_level": experience_to_next_level,
		"gold": gold,

		# Attributes
		"strength": strength,
		"agility": agility,
		"vitality": vitality,
		"luck": luck,

		# Equipment
		"equipped_weapon": weapon_data,
		"equipped_armor": equipped_armor.duplicate(true),

		# Tracking stats
		"kill_counts": kill_counts.duplicate(),
		"achievements": achievements.duplicate(),
		"total_playtime": total_playtime,

		# Quest progress
		"quests": quest_data,

		"version": 1  # For future migration
	}

func load_save_data(data: Dictionary) -> void:
	"""Load character data from saved dictionary"""
	# Core progression
	level = data.get("level", Constants.STARTING_LEVEL)
	experience = data.get("experience", Constants.STARTING_XP)
	experience_to_next_level = data.get("experience_to_next_level", Constants.BASE_XP_REQUIREMENT)
	gold = data.get("gold", Constants.STARTING_GOLD)

	# Attributes
	strength = data.get("strength", STARTING_STRENGTH)
	agility = data.get("agility", STARTING_AGILITY)
	vitality = data.get("vitality", STARTING_VITALITY)
	luck = data.get("luck", STARTING_LUCK)

	# Tracking stats
	kill_counts = data.get("kill_counts", {})
	achievements = data.get("achievements", [])
	total_playtime = data.get("total_playtime", 0.0)

	# Equipped weapon (recreate Weapon resource from saved data)
	var weapon_data = data.get("equipped_weapon", {})
	if not weapon_data.is_empty():
		var Weapon = load("res://scripts/resources/Weapon.gd")
		var weapon = Weapon.new()
		weapon.weapon_name = weapon_data.get("weapon_name", "Unknown")
		weapon.weapon_type = weapon_data.get("weapon_type", "sword")
		weapon.base_damage = weapon_data.get("base_damage", 1.0)
		weapon.attack_speed_bonus = weapon_data.get("attack_speed_bonus", 0.0)
		weapon.crit_chance_bonus = weapon_data.get("crit_chance_bonus", 0.0)
		weapon.required_level = weapon_data.get("required_level", 1)
		weapon.rarity = weapon_data.get("rarity", 0)
		weapon.can_trade = weapon_data.get("can_trade", true)
		weapon.description = weapon_data.get("description", "")
		equipped_weapon = weapon
	else:
		equipped_weapon = null

	# Equipped armor
	var armor_data = data.get("equipped_armor", {})
	if not armor_data.is_empty():
		for slot in armor_data:
			if slot in equipped_armor and armor_data[slot] != null:
				equipped_armor[slot] = armor_data[slot].duplicate() if armor_data[slot] is Dictionary else armor_data[slot]
			else:
				equipped_armor[slot] = null
	else:
		# Reset to starting clothes if no armor saved
		_equip_starting_clothes()

	# Start session timer
	start_session()

	# Load quest progress if QuestManager exists
	var quest_data = data.get("quests", {})
	if not quest_data.is_empty() and has_node("/root/QuestManager"):
		var quest_manager = get_node("/root/QuestManager")
		quest_manager.load_save_data(quest_data)

	print("📊 Character data loaded: Level %d, Gold %d, Playtime %.0fs" % [level, gold, total_playtime])

# ============================================
# PLAYTIME & KILL TRACKING
# ============================================

func start_session() -> void:
	"""Start tracking playtime for this session"""
	session_start_time = Time.get_unix_time_from_system()

func get_session_playtime() -> float:
	"""Get seconds played in current session"""
	if session_start_time <= 0:
		return 0.0
	return Time.get_unix_time_from_system() - session_start_time

func update_total_playtime() -> void:
	"""Add current session time to total (call before saving)"""
	if session_start_time > 0:
		total_playtime += get_session_playtime()
		session_start_time = Time.get_unix_time_from_system()  # Reset for next save

func record_kill(enemy_type: String) -> void:
	"""Record a kill of specific enemy type"""
	kill_counts[enemy_type] = kill_counts.get(enemy_type, 0) + 1

func get_kill_count(enemy_type: String) -> int:
	"""Get kill count for specific enemy type"""
	return kill_counts.get(enemy_type, 0)

func get_total_kills() -> int:
	"""Get total kills across all enemy types"""
	var total = 0
	for count in kill_counts.values():
		total += count
	return total

func unlock_achievement(achievement_id: String) -> bool:
	"""Unlock an achievement (returns false if already unlocked)"""
	if achievement_id in achievements:
		return false
	achievements.append(achievement_id)
	print("🏆 Achievement unlocked: %s" % achievement_id)
	return true

func has_achievement(achievement_id: String) -> bool:
	"""Check if achievement is unlocked"""
	return achievement_id in achievements

# ============================================
# DEBUG / TESTING
# ============================================

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

# ============================================
# CHAIN SYSTEM METHODS (merged from ChainManager)
# ============================================

func register_attack() -> void:
	"""Register an attack for chain timeout tracking"""
	last_attack_time = Time.get_ticks_msec() / 1000.0

func on_crit_window_completed(all_weakpoints_destroyed: bool) -> void:
	"""Called when a crit window ends"""
	if all_weakpoints_destroyed:
		increase_chain()
	else:
		reset_chain(ChainResetReason.FAILED_WINDOW)

func increase_chain() -> void:
	"""Increase the chain level"""
	if current_chain < chain_max_level:
		current_chain += 1
		Constants.log_combat("⚡ Chain increased to %dx" % current_chain)
		chain_increased.emit(current_chain)

		# Play milestone sound at every 5 chain levels or at max
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager and (current_chain % Constants.CHAIN_MILESTONE_INTERVAL == 0 or current_chain == chain_max_level):
			sound_manager.play_sound_2d(sound_manager.SoundType.CHAIN_MILESTONE, -8.0)

		if current_chain == chain_max_level:
			Constants.log_combat("🔥 OVERDRIVE! Maximum chain reached! 🔥")
			overdrive_activated.emit()
	else:
		Constants.log_combat("⚡ Chain at maximum (%dx)" % chain_max_level)

func reset_chain(reason: ChainResetReason = ChainResetReason.MANUAL) -> void:
	"""Reset the chain to zero"""
	if current_chain > 0:
		Constants.log_combat("💔 Chain reset from %dx (%s)" % [current_chain, ChainResetReason.keys()[reason]])

		# Play chain broken sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.CHAIN_BROKEN, -8.0)

		current_chain = 0
		chain_reset.emit(ChainResetReason.keys()[reason])

func get_damage_multiplier() -> float:
	"""Get damage multiplier from current chain level"""
	return 1.0 + (current_chain * (chain_damage_per_level / 100.0))

func get_chain_level() -> int:
	"""Get current chain level"""
	return current_chain

func is_overdrive() -> bool:
	"""Check if at max chain (overdrive mode)"""
	return current_chain >= chain_max_level
