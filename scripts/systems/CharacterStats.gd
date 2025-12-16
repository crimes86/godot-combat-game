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
# BASE ATTRIBUTES (6-stat system)
# ============================================
# Each archetype focuses on different primary stats:
# - Tank: VIT > STR
# - Plate DPS (2H): STR > DEX > VIT
# - Leather DPS: AGI > DEX > VIT
# - Caster DPS: INT > WIS > VIT
# - Healer: INT > VIT

var strength: int = Constants.STARTING_STRENGTH      # Heavy/2H weapon damage (Plate DPS)
var agility: int = Constants.STARTING_AGILITY        # Light weapon damage (Leather DPS)
var dexterity: int = Constants.STARTING_DEXTERITY    # Melee crit chance (all melee)
var intelligence: int = Constants.STARTING_INTELLIGENCE  # Staff damage + healing power (Caster)
var wisdom: int = Constants.STARTING_WISDOM          # Caster crit chance
var vitality: int = Constants.STARTING_VITALITY      # Max HP (Tank)

# Temporary buffs (from campfires, potions, etc.)
var campfire_crit_buff: float = 0.0  # Bonus crit chance from campfire bone embers

# ============================================
# PERSISTENT TRACKING (for Database)
# ============================================

var kill_counts: Dictionary = {}  # enemy_type -> count
var achievements: Array = []  # List of unlocked achievement IDs
var total_playtime: float = 0.0  # Total seconds played (persisted)
var session_start_time: float = 0.0  # Start of current session (not persisted)

# Playtest forge system - isolated from real NFT system
var playtest_claimed_items: Array = []  # item_ids of forged items claimed in playtest mode

# Starting stats (for reset/new character)
const STARTING_STRENGTH: int = Constants.STARTING_STRENGTH
const STARTING_AGILITY: int = Constants.STARTING_AGILITY
const STARTING_DEXTERITY: int = Constants.STARTING_DEXTERITY
const STARTING_INTELLIGENCE: int = Constants.STARTING_INTELLIGENCE
const STARTING_WISDOM: int = Constants.STARTING_WISDOM
const STARTING_VITALITY: int = Constants.STARTING_VITALITY

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
	"feet": null,      # Boots
	"back": null,      # Cape/cloak
	"ring1": null,     # Left ring (jewelry)
	"ring2": null,     # Right ring (jewelry)
	"amulet": null     # Neck amulet (jewelry)
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
	Constants.debug_log("Stats: STR:%d AGI:%d DEX:%d INT:%d WIS:%d VIT:%d" % [strength, agility, dexterity, intelligence, wisdom, vitality])
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
	"""Calculate attack cooldown based on weapon type only.
	Attack speed is a weapon property, not a stat - balanced per weapon type:
	- Very Fast (dagger): 0.25s - reaches uncapped speed
	- Fast (katana, rapier, sword): 0.40s
	- Medium (staff, axe, mace): 0.60s
	- Slow (greatsword, hammer, halberd): 0.85s
	DPS is balanced across types through damage per hit."""

	# Base cooldown from weapon type
	var base_cooldown = 0.60  # Default medium speed

	if equipped_weapon:
		var weapon_type = equipped_weapon.weapon_type.to_lower()

		# Very fast weapons
		if weapon_type in ["dagger"]:
			base_cooldown = 0.25
		# Fast weapons
		elif weapon_type in ["katana", "rapier", "sword"]:
			base_cooldown = 0.40
		# Medium weapons
		elif weapon_type in ["staff", "damage_staff", "healing_staff", "support_staff", "axe", "mace", "spear"]:
			base_cooldown = 0.60
		# Slow weapons
		elif weapon_type in ["greatsword", "hammer", "halberd"]:
			base_cooldown = 0.85

		# Apply weapon-specific bonus (for unique weapons that break the mold)
		var weapon_bonus = equipped_weapon.attack_speed_bonus
		base_cooldown = base_cooldown * (1.0 + weapon_bonus)

	return clamp(base_cooldown, 0.15, 2.0)  # Min 0.15s, max 2.0s

func get_base_damage() -> float:
	"""Calculate base damage from primary stat + weapon.
	Weapon type determines which stat is used:
	- Heavy weapons (sword, axe, mace, hammer, spear, halberd, greatsword): STR
	- Light weapons (dagger, katana, rapier): AGI
	- Staff weapons (staff, damage_staff, healing_staff, support_staff): INT

	Stat scaling is adjusted by weapon speed so that equal stat investment
	gives equal DPS regardless of weapon type. This allows Plate DPS (STR)
	to keep pace with Leather DPS (AGI) when both invest equally in their
	primary stat.
	"""
	# Determine which stat to use based on weapon type
	var primary_stat = get_effective_strength()  # Default to STR

	if equipped_weapon:
		var weapon_type = equipped_weapon.weapon_type.to_lower()
		var light_weapons = ["dagger", "katana", "rapier", "scimitar", "saber", "bow", "claws"]
		var staff_weapons = ["staff", "damage_staff", "healing_staff", "support_staff", "psi_blade", "warp_blade"]

		if weapon_type in light_weapons:
			primary_stat = get_effective_agility()  # Leather DPS uses AGI
		elif weapon_type in staff_weapons:
			primary_stat = get_effective_intelligence()  # Caster uses INT
		else:
			# Heavy weapons use STR (Plate DPS)
			primary_stat = get_effective_strength()

	# Speed-adjusted stat scaling: slower weapons get more damage per stat point
	# so that +1 stat = same DPS gain regardless of weapon speed
	# Reference: 0.25s (very fast) = 1.0x multiplier
	var attack_time = get_attack_cooldown()
	var stat_multiplier = attack_time / 0.25  # 0.25s=1x, 0.40s=1.6x, 0.60s=2.4x, 0.85s=3.4x

	# Base formula: 5 damage at 10 stat, +0.5 per point * speed multiplier
	var stat_damage = 5.0 * stat_multiplier + (primary_stat - 10) * 0.5 * stat_multiplier

	# Add weapon damage (not multiplied - weapon damage is already balanced per type)
	var weapon_damage = 0.0
	if equipped_weapon:
		weapon_damage = equipped_weapon.base_damage

	return stat_damage + weapon_damage

func get_effective_strength() -> int:
	"""Get total STR including equipment bonuses"""
	return strength + get_equipment_stat_bonus("str")

func get_effective_agility() -> int:
	"""Get total AGI including equipment bonuses"""
	return agility + get_equipment_stat_bonus("agi")

func get_effective_dexterity() -> int:
	"""Get total DEX including equipment bonuses"""
	return dexterity + get_equipment_stat_bonus("dex")

func get_effective_intelligence() -> int:
	"""Get total INT including equipment bonuses"""
	return intelligence + get_equipment_stat_bonus("int")

func get_effective_wisdom() -> int:
	"""Get total WIS including equipment bonuses"""
	return wisdom + get_equipment_stat_bonus("wis")

func get_effective_vitality() -> int:
	"""Get total VIT including equipment bonuses"""
	return vitality + get_equipment_stat_bonus("vit")

func get_equipment_stat_bonus(stat_key: String) -> int:
	"""Calculate total bonus for a stat from all equipped items"""
	var total_bonus = 0

	# Check weapon stat bonuses
	if not equipped_weapon_data.is_empty():
		var bonuses = equipped_weapon_data.get("stat_bonuses", {})
		total_bonus += bonuses.get(stat_key, 0)

	# Check all armor slot stat bonuses
	for slot in equipped_armor:
		var armor_item = equipped_armor[slot]
		if armor_item and armor_item is Dictionary:
			var bonuses = armor_item.get("stat_bonuses", {})
			total_bonus += bonuses.get(stat_key, 0)

	return total_bonus

func get_max_health() -> float:
	"""Calculate max HP from vitality (PvE)"""
	# Base formula: 100 HP at 10 VIT, +10 per point
	var effective_vit = get_effective_vitality()
	return 100.0 + (effective_vit - 10) * 10.0

func get_pvp_max_health() -> float:
	"""Calculate max HP for PvP duels (separate scaling for balance)"""
	# PvP uses higher base HP and stronger VIT scaling for longer fights
	# Target: 3-5 weakpoint windows to kill
	var base_hp = Constants.PLAYER_PVP_BASE_HP if "PLAYER_PVP_BASE_HP" in Constants else 800.0
	var hp_per_vit = Constants.PLAYER_PVP_HP_PER_VIT if "PLAYER_PVP_HP_PER_VIT" in Constants else 15.0
	var effective_vit = get_effective_vitality()
	return base_hp + (effective_vit - 10) * hp_per_vit

func get_window_damage() -> float:
	"""Calculate damage dealt by a perfect weakpoint window at current level.
	Used for TTK calculations and enemy HP scaling."""
	var base_damage = get_base_damage()
	var crit_mult = Constants.CRIT_DAMAGE_MULTIPLIER if "CRIT_DAMAGE_MULTIPLIER" in Constants else 2.0

	# Perfect window = all weakpoints destroyed
	# Weakpoint count scales with level: 1 at low, 2 at mid, 3 at high
	var weakpoint_count = 3  # Assume max for "perfect" window calculation
	if level < 11:
		weakpoint_count = 1
	elif level < 21:
		weakpoint_count = 2

	# Each weakpoint takes 3-5 hits to destroy (average 4), and EACH hit deals damage
	var hits_per_weakpoint = 4

	return base_damage * crit_mult * weakpoint_count * hits_per_weakpoint

func get_base_crit_chance() -> float:
	"""Calculate crit chance based on weapon type:
	- Melee weapons (STR/AGI): Use DEX for crit
	- Caster weapons (INT): Use WIS for crit
	Base formula: 1% at 10 stat, +0.5% per point"""
	var crit_stat = get_effective_dexterity()  # Default to DEX for melee

	# Check if using a caster weapon
	if equipped_weapon:
		var weapon_type = equipped_weapon.weapon_type.to_lower()
		var staff_weapons = ["staff", "damage_staff", "healing_staff", "support_staff", "psi_blade", "warp_blade"]
		if weapon_type in staff_weapons:
			crit_stat = get_effective_wisdom()  # Casters use WIS for crit

	var stat_crit = 0.01 + (crit_stat - 10) * 0.005

	# Add campfire buff (from bone embers)
	var total_crit = stat_crit + campfire_crit_buff

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
	# All 6 stats increase equally - player differentiates through equipment
	var stat_gain = 0

	if level <= Constants.STAT_GAIN_CAP_LEVEL:
		stat_gain = 2  # +2 to each stat per level

		strength += stat_gain
		agility += stat_gain
		dexterity += stat_gain
		intelligence += stat_gain
		wisdom += stat_gain
		vitality += stat_gain

	# Emit signal
	level_up.emit(level)

	# Celebratory print
	print("\n╔══════════════════════════════════════╗")
	print("║      🎉 LEVEL UP! Level ", level, "         ║")
	print("╚══════════════════════════════════════╝")
	if level <= Constants.STAT_GAIN_CAP_LEVEL:
		print("  STR: ", strength, " (+", stat_gain, ") | AGI: ", agility, " (+", stat_gain, ")")
		print("  DEX: ", dexterity, " (+", stat_gain, ") | INT: ", intelligence, " (+", stat_gain, ")")
		print("  WIS: ", wisdom, " (+", stat_gain, ") | VIT: ", vitality, " (+", stat_gain, ")")
	else:
		print("  ⚠️  MAX STAT LEVEL (", Constants.STAT_GAIN_CAP_LEVEL, ") - No stat gains")
		print("  STR: ", strength, " | AGI: ", agility, " | DEX: ", dexterity)
		print("  INT: ", intelligence, " | WIS: ", wisdom, " | VIT: ", vitality)
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
		"dexterity", "dex":
			old_value = dexterity
			dexterity += amount
			stat_changed.emit("dexterity", old_value, dexterity)
		"intelligence", "int":
			old_value = intelligence
			intelligence += amount
			stat_changed.emit("intelligence", old_value, intelligence)
		"wisdom", "wis":
			old_value = wisdom
			wisdom += amount
			stat_changed.emit("wisdom", old_value, wisdom)
		"vitality", "vit":
			old_value = vitality
			vitality += amount
			stat_changed.emit("vitality", old_value, vitality)

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

func get_equipped_item(slot: String) -> Dictionary:
	"""Get equipped item data for a specific slot (head, chest, back, etc.)"""
	if slot in equipped_armor and equipped_armor[slot]:
		return equipped_armor[slot]
	return {}

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
	dexterity = STARTING_DEXTERITY
	intelligence = STARTING_INTELLIGENCE
	wisdom = STARTING_WISDOM
	vitality = STARTING_VITALITY

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

		# 6-Stat System
		"strength": strength,
		"agility": agility,
		"dexterity": dexterity,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"vitality": vitality,

		# Equipment
		"equipped_weapon": weapon_data,
		"equipped_armor": equipped_armor.duplicate(true),

		# Tracking stats
		"kill_counts": kill_counts.duplicate(),
		"achievements": achievements.duplicate(),
		"total_playtime": total_playtime,
		"playtest_claimed_items": playtest_claimed_items.duplicate(),

		# Quest progress
		"quests": quest_data,

		"version": 4  # 6-stat system
	}

func load_save_data(data: Dictionary) -> void:
	"""Load character data from saved dictionary"""
	# Core progression
	level = data.get("level", Constants.STARTING_LEVEL)
	experience = data.get("experience", Constants.STARTING_XP)
	experience_to_next_level = data.get("experience_to_next_level", Constants.BASE_XP_REQUIREMENT)
	gold = data.get("gold", Constants.STARTING_GOLD)

	# 6-Stat System
	strength = data.get("strength", STARTING_STRENGTH)
	agility = data.get("agility", STARTING_AGILITY)
	dexterity = data.get("dexterity", STARTING_DEXTERITY)
	intelligence = data.get("intelligence", STARTING_INTELLIGENCE)
	wisdom = data.get("wisdom", STARTING_WISDOM)
	vitality = data.get("vitality", STARTING_VITALITY)

	# Tracking stats
	kill_counts = data.get("kill_counts", {})
	achievements = data.get("achievements", [])
	total_playtime = data.get("total_playtime", 0.0)
	playtest_claimed_items = data.get("playtest_claimed_items", [])

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
	print("\n--- Attributes (6-stat system) ---")
	print("STR: ", get_effective_strength(), " (base: ", strength, " + equip: ", get_equipment_stat_bonus("str"), ") - Plate DPS")
	print("AGI: ", get_effective_agility(), " (base: ", agility, " + equip: ", get_equipment_stat_bonus("agi"), ") - Leather DPS")
	print("DEX: ", get_effective_dexterity(), " (base: ", dexterity, " + equip: ", get_equipment_stat_bonus("dex"), ") - Melee Crit")
	print("INT: ", get_effective_intelligence(), " (base: ", intelligence, " + equip: ", get_equipment_stat_bonus("int"), ") - Caster")
	print("WIS: ", get_effective_wisdom(), " (base: ", wisdom, " + equip: ", get_equipment_stat_bonus("wis"), ") - Caster Crit")
	print("VIT: ", get_effective_vitality(), " (base: ", vitality, " + equip: ", get_equipment_stat_bonus("vit"), ") - Tank HP")
	print("\n--- Combat Stats ---")
	print("Attack Speed: ", "%.3f" % get_attack_cooldown(), "s (weapon-based)")
	print("Base Damage: ", "%.1f" % get_base_damage(), " (scales with ", _get_weapon_scaling_stat(), ")")
	print("Max Health: ", "%.0f" % get_max_health())
	print("Crit Chance: ", "%.1f" % (get_base_crit_chance() * 100), "% (scales with ", _get_crit_scaling_stat(), ")")
	print("Movement Speed: ", "%.0f" % get_movement_speed())
	print("\n--- Weapon ---")
	if equipped_weapon:
		print("Equipped: ", equipped_weapon.weapon_name)
		print("Type: ", equipped_weapon.weapon_type)
	else:
		print("Unarmed")
	print("═══════════════════════\n")

func _get_weapon_scaling_stat() -> String:
	"""Get the stat name that the current weapon scales with for damage"""
	if not equipped_weapon:
		return "STR"
	var weapon_type = equipped_weapon.weapon_type.to_lower()
	if weapon_type in ["dagger", "katana", "rapier", "scimitar", "saber", "bow", "claws"]:
		return "AGI"
	elif weapon_type in ["staff", "damage_staff", "healing_staff", "support_staff", "psi_blade", "warp_blade"]:
		return "INT"
	return "STR"

func _get_crit_scaling_stat() -> String:
	"""Get the stat name that the current weapon scales with for crit"""
	if not equipped_weapon:
		return "DEX"
	var weapon_type = equipped_weapon.weapon_type.to_lower()
	if weapon_type in ["staff", "damage_staff", "healing_staff", "support_staff", "psi_blade", "warp_blade"]:
		return "WIS"
	return "DEX"

# ============================================
# PLAYTEST FORGE SYSTEM
# ============================================

func claim_playtest_item(item_id: String) -> bool:
	"""Claim a playtest forge item (one-time only). Returns false if already claimed."""
	if item_id in playtest_claimed_items:
		print("⚠️  Item already claimed: %s" % item_id)
		return false
	playtest_claimed_items.append(item_id)
	print("✅ Playtest item claimed: %s" % item_id)
	return true

func has_claimed_playtest_item(item_id: String) -> bool:
	"""Check if a playtest item has been claimed"""
	return item_id in playtest_claimed_items

func clear_playtest_claims() -> void:
	"""Reset all playtest claims (for testing)"""
	var count = playtest_claimed_items.size()
	playtest_claimed_items.clear()
	print("🔄 Cleared %d playtest claims" % count)

func get_playtest_claimed_count() -> int:
	"""Get number of playtest items claimed"""
	return playtest_claimed_items.size()

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
