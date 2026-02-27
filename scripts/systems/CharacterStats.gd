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

# ============================================
# ALLEGIANCE SYSTEM (PvP Factions)
# ============================================
# null = Rogue (no allegiance, hostile to all, gray shield)
# "ashbane" = Default faction (Ashbane tree icon)
# Other strings = Player-created allegiances (future)

var ossuary_reputation: float = 0.0  # Permanent Ossuary faction reputation (0-100)

var allegiance_id: String = "ashbane"  # Default to Ashbane faction
var allegiance_last_change: float = 0.0  # Unix timestamp of last allegiance change
const ALLEGIANCE_CHANGE_COOLDOWN: float = 86400.0  # 1 day in seconds between player allegiance switches
const ROGUE_REJOIN_COOLDOWN: float = 3600.0  # 1 hour cooldown to rejoin Ashbane after going rogue

# Built-in allegiances
const ALLEGIANCE_ASHBANE: String = "ashbane"
const ALLEGIANCE_ROGUE: String = ""  # Empty string = rogue/no allegiance

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
signal allegiance_changed(old_allegiance: String, new_allegiance: String)

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	Constants.debug_log("═══════════════════════════════════════")
	Constants.debug_log("CharacterStats System Initialized")
	Constants.debug_log("Level: %d" % level)
	Constants.debug_log("Stats: STR:%d AGI:%d DEX:%d INT:%d WIS:%d VIT:%d" % [strength, agility, dexterity, intelligence, wisdom, vitality])
	Constants.debug_log("═══════════════════════════════════════")

	# Start unarmed - player must buy/equip weapons
	equipped_weapon = null
	print("👊 Player starts UNARMED - buy weapons from vendor!")

	# Equip default starting clothes (non-removable)
	_equip_starting_clothes()

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
	"""Calculate attack cooldown based on weapon type AND player level.

	Attack speed uses a BACK-LOADED curve for progression feel:
	- Levels 1-10: Slow, deliberate attacks (~3% speed gain)
	- Levels 11-19: Speed ramping up (~15% speed gain)
	- Levels 20-30: Full speed unlocked (~60% total reduction)

	Weapon type defines a speed multiplier:
	- Very Fast (dagger): 0.50x
	- Fast (katana, rapier, saber): 0.65x
	- Medium (sword, scimitar, bow): 0.80x
	- Slow (mace, spear, axe, staff): 0.95x
	- Very Slow (hammer, halberd, greatsword): 1.10x
	"""

	# Back-loaded curve: pow((level-1)/29, exponent) gives minimal early gains
	# Exponent of 2.5 means: L10=3%, L15=10%, L20=21%, L30=60% reduction
	var max_reduction = Constants.ATTACK_SPEED_BASE_COOLDOWN - Constants.ATTACK_SPEED_MIN_COOLDOWN  # 0.6
	var progress = float(level - 1) / float(Constants.MAX_LEVEL - 1)  # 0.0 to 1.0
	var curve_factor = pow(progress, Constants.ATTACK_SPEED_CURVE_EXPONENT)  # Back-loaded
	var level_factor = Constants.ATTACK_SPEED_BASE_COOLDOWN - (curve_factor * max_reduction)
	level_factor = clamp(level_factor, Constants.ATTACK_SPEED_MIN_COOLDOWN, Constants.ATTACK_SPEED_BASE_COOLDOWN)

	# Weapon speed multiplier
	var weapon_mult = Constants.WEAPON_SPEED_MEDIUM  # Default medium speed

	if equipped_weapon:
		var weapon_type = equipped_weapon.weapon_type.to_lower()

		# Very fast weapons
		if weapon_type in ["dagger"]:
			weapon_mult = Constants.WEAPON_SPEED_VERY_FAST
		# Fast weapons
		elif weapon_type in ["katana", "rapier", "saber", "gun"]:
			weapon_mult = Constants.WEAPON_SPEED_FAST
		# Medium weapons
		elif weapon_type in ["sword", "scimitar", "bow"]:
			weapon_mult = Constants.WEAPON_SPEED_MEDIUM
		# Slow weapons
		elif weapon_type in ["staff", "damage_staff", "healing_staff", "support_staff", "axe", "mace", "spear"]:
			weapon_mult = Constants.WEAPON_SPEED_SLOW
		# Very slow weapons
		elif weapon_type in ["greatsword", "hammer", "halberd"]:
			weapon_mult = Constants.WEAPON_SPEED_VERY_SLOW

		# Apply weapon-specific bonus (for unique weapons that break the mold)
		var weapon_bonus = equipped_weapon.attack_speed_bonus
		weapon_mult = weapon_mult * (1.0 + weapon_bonus)

	var final_cooldown = level_factor * weapon_mult
	return clamp(final_cooldown, 0.20, 1.2)  # Min 0.20s (fast!), max 1.2s (slow)

func get_base_damage() -> float:
	"""Calculate base damage from primary stat + weapon + level.

	REBALANCED for smaller, meaningful numbers at early levels:
	- Level 1 with starter weapon: ~6-8 total damage
	- Level 30 with legendary: ~40-50 total damage

	Weapon type determines which stat is used:
	- Heavy weapons (sword, axe, mace, hammer, spear, halberd, greatsword, gun): STR
	- Light weapons (dagger, katana, rapier, scimitar, saber, bow): AGI
	- Staff weapons (staff, damage_staff, healing_staff, support_staff): INT
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

	# REBALANCED stat damage formula:
	# - Base damage from level: 1.0 + 0.3 per level (1 at L1, 9.7 at L30)
	# - Stat bonus: +0.15 per point above 10, scaled by weapon speed
	# - This keeps early game numbers small but scales meaningfully

	var level_damage = 1.0 + (level - 1) * 0.3

	# Speed-adjusted stat scaling (slower weapons get more per stat point)
	# Reference: 0.50s = 1.0x multiplier (adjusted for new attack speed range)
	var attack_time = get_attack_cooldown()
	var stat_multiplier = attack_time / 0.50  # Normalized to 0.50s baseline

	# Stat bonus: each point above 10 adds damage, scaled by weapon speed
	var stat_bonus = (primary_stat - 10) * 0.15 * stat_multiplier

	var stat_damage = level_damage + stat_bonus

	# Add weapon damage (not multiplied - weapon damage is already balanced per type)
	var weapon_damage = 0.0
	if equipped_weapon:
		weapon_damage = equipped_weapon.base_damage

	# Apply forged weapon level multiplier (percentage-based scaling)
	# This multiplies the weapon's base damage, preserving balance between weapons
	var weapon_level_multiplier = 1.0
	if equipped_weapon and equipped_weapon.is_forged and equipped_weapon.weapon_stats:
		weapon_level_multiplier = equipped_weapon.weapon_stats.get_damage_multiplier()

	return stat_damage + (weapon_damage * weapon_level_multiplier)

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

	# Sync to server immediately so XP isn't lost on disconnect
	_sync_to_server()

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

	# Sync to server immediately so gold isn't lost on disconnect
	_sync_to_server()

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

	# Sync to server immediately so gold change persists
	_sync_to_server()
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

	# If equipping a 2h weapon, auto-unequip offhand first
	if weapon.is_two_handed and equipped_armor.get("offhand") != null:
		print("🛡️  Unequipping offhand (2H weapon equipped)")
		unequip_armor("offhand")

	equipped_weapon = weapon
	equipped_weapon_data = item_data.duplicate(true) if not item_data.is_empty() else {}
	weapon_equipped.emit(weapon)

	print("⚔️  Equipped: ", weapon.weapon_name)
	print("   Damage: +", weapon.base_damage)
	print("   Attack Speed: ", weapon.attack_speed_bonus * 100, "%")
	print("   Crit Chance: +", weapon.crit_chance_bonus * 100, "%")
	if weapon.is_two_handed:
		print("   [2-Handed - offhand blocked]")
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
			"quantity": 1,
			# Include forged properties from weapon resource
			"is_forged": equipped_weapon.is_forged,
			"forged_id": equipped_weapon.forged_id,
			"item_id": equipped_weapon.forged_id,
			"forged_item_id": equipped_weapon.forged_id
		}

		# Add healing weapon properties if applicable
		if equipped_weapon.attack_mode != "melee":
			weapon_dict["attack_mode"] = equipped_weapon.attack_mode
			weapon_dict["healing_power"] = equipped_weapon.healing_power
			weapon_dict["heal_radius"] = equipped_weapon.heal_radius

		# Add gun weapon properties
		if equipped_weapon.is_gun_weapon():
			weapon_dict["gun_radius"] = equipped_weapon.gun_radius
			weapon_dict["gun_range"] = equipped_weapon.gun_range
			weapon_dict["gun_subtype"] = equipped_weapon.gun_subtype
			weapon_dict["burst_count"] = equipped_weapon.burst_count
			weapon_dict["burst_delay"] = equipped_weapon.burst_delay

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
		var fallback = {
			"name": equipped_weapon.weapon_name,
			"description": equipped_weapon.description,
			"type": "weapon",
			"slot": "mainhand",
			"weapon_type": equipped_weapon.weapon_type,
			"base_damage": equipped_weapon.base_damage,
			"attack_speed_bonus": equipped_weapon.attack_speed_bonus,
			"crit_chance_bonus": equipped_weapon.crit_chance_bonus,
			"rarity": Weapon.Rarity.keys()[equipped_weapon.rarity],
			# Include forged properties from weapon resource
			"is_forged": equipped_weapon.is_forged,
			"forged_id": equipped_weapon.forged_id,
			"item_id": equipped_weapon.forged_id  # item_id is same as forged_id
		}
		return fallback
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

	# Block offhand equipping when 2h weapon is equipped
	if slot == "offhand" and equipped_weapon and equipped_weapon.is_two_handed:
		push_error("Cannot equip offhand - 2-handed weapon is equipped")
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

func get_equipped_shield() -> Dictionary:
	"""Return the equipped shield (offhand item) or empty dict if none"""
	var offhand = equipped_armor.get("offhand")
	if offhand and offhand.get("type") == "shield":
		return offhand
	return {}

func get_plate_armor_count() -> int:
	"""Return number of plate armor pieces equipped (for block efficiency bonus)"""
	var count = 0
	var armor_slots = ["head", "chest", "hands", "legs", "feet"]
	for slot in armor_slots:
		var armor_item = equipped_armor.get(slot)
		if armor_item and armor_item.get("armor_type", "").to_lower() == "plate":
			count += 1
	return count

func get_block_efficiency() -> float:
	"""Get block efficiency (partial block damage reduction) based on plate armor
	Base: 50% damage reduction on partial block
	Each plate piece: +5% (max +30% with 6 pieces)
	Returns value like 0.50 to 0.80"""
	var base_efficiency = 0.50
	var plate_bonus = get_plate_armor_count() * 0.05
	return base_efficiency + plate_bonus

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

	# Add gun weapon properties
	if equipped_weapon.is_gun_weapon():
		weapon_dict["gun_radius"] = equipped_weapon.gun_radius
		weapon_dict["gun_range"] = equipped_weapon.gun_range
		weapon_dict["gun_subtype"] = equipped_weapon.gun_subtype
		weapon_dict["burst_count"] = equipped_weapon.burst_count
		weapon_dict["burst_delay"] = equipped_weapon.burst_delay

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
			"description": equipped_weapon.description,
			# Forged weapon properties
			"is_forged": equipped_weapon.is_forged,
			"forged_id": equipped_weapon.forged_id
		}
		# Add gun weapon properties
		if equipped_weapon.is_gun_weapon():
			weapon_data["gun_radius"] = equipped_weapon.gun_radius
			weapon_data["gun_range"] = equipped_weapon.gun_range
			weapon_data["gun_subtype"] = equipped_weapon.gun_subtype
			weapon_data["burst_count"] = equipped_weapon.burst_count
			weapon_data["burst_delay"] = equipped_weapon.burst_delay
		# Add healing weapon properties
		if equipped_weapon.attack_mode != "melee":
			weapon_data["attack_mode"] = equipped_weapon.attack_mode
			weapon_data["healing_power"] = equipped_weapon.healing_power
			weapon_data["heal_radius"] = equipped_weapon.heal_radius

	# Also save equipped_weapon_data (original item dict with forged metadata)
	var equipped_weapon_dict = equipped_weapon_data.duplicate() if equipped_weapon_data else {}

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
		"equipped_weapon_data": equipped_weapon_dict,  # Original item dict with forged metadata
		"equipped_armor": equipped_armor.duplicate(true),

		# Tracking stats
		"kill_counts": kill_counts.duplicate(),
		"achievements": achievements.duplicate(),
		"total_playtime": total_playtime,
		"playtest_claimed_items": playtest_claimed_items.duplicate(),

		# Allegiance
		"allegiance_id": allegiance_id,
		"allegiance_last_change": allegiance_last_change,

		# Ossuary reputation
		"ossuary_reputation": ossuary_reputation,

		# Quest progress
		"quests": quest_data,

		"version": 7  # Added persistent ossuary reputation
	}

func load_save_data(data: Dictionary) -> void:
	"""Load character data from saved dictionary"""
	# Core progression
	level = data.get("level", Constants.STARTING_LEVEL)
	experience = data.get("experience", Constants.STARTING_XP)
	gold = data.get("gold", Constants.STARTING_GOLD)

	# Always recalculate experience_to_next_level from level
	# The backend doesn't store this field, so the saved value may be stale/default
	var level_exponent = min(level - 1, 50)
	experience_to_next_level = int(Constants.BASE_XP_REQUIREMENT * pow(Constants.XP_SCALING_EXPONENT, level_exponent))

	# Clamp experience to current level range (fixes bloated values from old bug)
	if experience >= experience_to_next_level:
		experience = experience_to_next_level - 1

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

	# Allegiance
	allegiance_id = data.get("allegiance_id", ALLEGIANCE_ASHBANE)  # Default to Ashbane
	allegiance_last_change = data.get("allegiance_last_change", 0.0)

	# Ossuary reputation (permanent, persisted via backend)
	ossuary_reputation = data.get("ossuary_reputation", 0.0)
	if ossuary_reputation > 0.0:
		var ossuary_mgr = get_node_or_null("/root/OssuaryManager")
		if ossuary_mgr:
			ossuary_mgr.set_local_influence(ossuary_reputation)

	# Equipped weapon (recreate Weapon resource from saved data)
	var weapon_data = data.get("equipped_weapon", {})
	if not weapon_data.is_empty():
		var Weapon = load("res://scripts/resources/Weapon.gd")
		var weapon = Weapon.new()
		weapon.weapon_name = weapon_data.get("weapon_name", "Unknown")
		weapon.weapon_type = weapon_data.get("weapon_type", "sword")

		# Handle base_damage - can be a number or a Dictionary with min/max
		var base_damage = weapon_data.get("base_damage", 1.0)
		if base_damage is Dictionary:
			var dmg_min = base_damage.get("min", 5)
			var dmg_max = base_damage.get("max", 5)
			weapon.base_damage = (dmg_min + dmg_max) / 2.0
		elif base_damage is float or base_damage is int:
			weapon.base_damage = float(base_damage)
		else:
			weapon.base_damage = 5.0

		weapon.attack_speed_bonus = weapon_data.get("attack_speed_bonus", 0.0)
		weapon.crit_chance_bonus = weapon_data.get("crit_chance_bonus", 0.0)
		weapon.required_level = weapon_data.get("required_level", 1)
		weapon.rarity = weapon_data.get("rarity", 0)
		weapon.can_trade = weapon_data.get("can_trade", true)
		weapon.description = weapon_data.get("description", "")
		# Load gun weapon properties (use explicit null checks since .get() returns null if key exists with null value)
		weapon.gun_radius = weapon_data.get("gun_radius") if weapon_data.get("gun_radius") != null else 28.0
		weapon.gun_range = weapon_data.get("gun_range") if weapon_data.get("gun_range") != null else 550.0
		weapon.gun_subtype = weapon_data.get("gun_subtype") if weapon_data.get("gun_subtype") != null else "railgun"
		weapon.burst_count = weapon_data.get("burst_count") if weapon_data.get("burst_count") != null else 1
		weapon.burst_delay = weapon_data.get("burst_delay") if weapon_data.get("burst_delay") != null else 0.10
		# Load healing weapon properties
		weapon.attack_mode = weapon_data.get("attack_mode", "melee")
		weapon.healing_power = weapon_data.get("healing_power", 0.0)
		weapon.heal_radius = weapon_data.get("heal_radius", 80.0)
		# Two-handed property - guns and bows are always two-handed (blocks offhand slot)
		var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
		weapon.is_two_handed = weapon_data.get("is_two_handed", is_two_handed_type)
		# Forged weapon properties
		weapon.is_forged = weapon_data.get("is_forged", false)
		weapon.forged_id = weapon_data.get("forged_id", "")
		equipped_weapon = weapon
	else:
		equipped_weapon = null

	# Restore equipped_weapon_data (original item dict with forged metadata)
	equipped_weapon_data = data.get("equipped_weapon_data", {})

	# Migration: Fix forged weapons with missing/incorrect item_id
	if equipped_weapon:
		var ForgeItemDB_ref = Engine.get_singleton("ForgeItemDB") if Engine.has_singleton("ForgeItemDB") else null
		if ForgeItemDB_ref == null and has_node("/root/ForgeItemDB"):
			ForgeItemDB_ref = get_node("/root/ForgeItemDB")
		if ForgeItemDB_ref and ForgeItemDB_ref.has_method("get_item_by_name"):
			# Check if migration needed: empty data, or data exists but item_id doesn't resolve
			var needs_migration = equipped_weapon_data.is_empty()
			if not needs_migration:
				var current_item_id = equipped_weapon_data.get("item_id", "")
				if current_item_id == "":
					needs_migration = true
				elif ForgeItemDB_ref.has_method("get_item_by_id"):
					var resolved = ForgeItemDB_ref.get_item_by_id(current_item_id)
					if resolved.is_empty():
						# Current item_id doesn't resolve - try by name
						needs_migration = true

			if needs_migration:
				var forged_data = ForgeItemDB_ref.get_item_by_name(equipped_weapon.weapon_name)
				if forged_data and not forged_data.is_empty():
					# Found the weapon in ForgeItemDB - it's a forged weapon
					var item_id = forged_data.get("item_id", "")
					equipped_weapon.is_forged = true
					equipped_weapon.forged_id = item_id
					# Preserve existing data but update forged fields
					if equipped_weapon_data.is_empty():
						equipped_weapon_data = {
							"name": equipped_weapon.weapon_name,
							"type": "weapon",
							"slot": "mainhand",
							"weapon_type": equipped_weapon.weapon_type,
						}
					equipped_weapon_data["is_forged"] = true
					equipped_weapon_data["forged_id"] = item_id
					equipped_weapon_data["item_id"] = item_id
					equipped_weapon_data["forged_item_id"] = item_id
					equipped_weapon_data["glow_color"] = forged_data.get("visuals", {}).get("glow_color", "")
					equipped_weapon_data["effect_name"] = forged_data.get("visuals", {}).get("effect", "")
					equipped_weapon_data["theme"] = forged_data.get("theme", "")
					equipped_weapon_data["sprites"] = forged_data.get("sprites", {})
					print("[CharacterStats] Migrated forged weapon: %s -> item_id=%s" % [equipped_weapon.weapon_name, item_id])

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

var _last_backend_sync_time: float = 0.0
const BACKEND_SYNC_COOLDOWN: float = 30.0  # Minimum 30 seconds between backend syncs

func _sync_to_server() -> void:
	"""Sync current state to game server immediately (for XP/level changes)"""
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.is_authenticated and not network_manager.is_host and not network_manager.is_guest:
		network_manager.client_sync_state()

func sync_to_backend() -> void:
	"""Sync current state to backend API (with rate limiting)"""
	var current_time = Time.get_unix_time_from_system()
	if current_time - _last_backend_sync_time < BACKEND_SYNC_COOLDOWN:
		return  # Rate limited

	var ashbane_auth = get_node_or_null("/root/AshbaneAuth")
	if not ashbane_auth or not ashbane_auth.is_authenticated:
		return

	_last_backend_sync_time = current_time

	# Build inventory data
	var inventory_system = get_node_or_null("/root/InventorySystem")
	var inventory_data = []
	if inventory_system:
		for item in inventory_system.inventory_items:
			if item != null:
				inventory_data.append(item)

	# Build equipped armor data
	var equipped_armor_data = {}
	for slot in equipped_armor:
		var armor_item = equipped_armor[slot]
		if armor_item != null:
			equipped_armor_data[slot] = armor_item

	# Get equipped weapon ID
	var equipped_weapon_id = ""
	if equipped_weapon_data and not equipped_weapon_data.is_empty():
		equipped_weapon_id = equipped_weapon_data.get("id", equipped_weapon_data.get("name", ""))

	# Get weapon skills
	var weapon_skills_data = {}
	var weapon_skill_mgr = get_node_or_null("/root/WeaponSkillManager")
	if weapon_skill_mgr:
		weapon_skills_data = weapon_skill_mgr.get_save_data().get("weapon_skills", {})

	# Get quest data
	var quest_data = {}
	var quest_mgr = get_node_or_null("/root/QuestManager")
	if quest_mgr:
		quest_data = quest_mgr.get_save_data()

	# Get tutorial completion state
	var tutorial_done = false
	var db_mgr = get_node_or_null("/root/DatabaseManager")
	var network_mgr = get_node_or_null("/root/NetworkManager")
	if db_mgr and network_mgr and network_mgr.local_player_data:
		var storage_key = network_mgr.local_player_data.get("username", "")
		if not storage_key.is_empty():
			tutorial_done = db_mgr.has_completed_tutorial(storage_key)

	# Get deleted forged items (prevents re-sync on login)
	var deleted_forged = {}
	var forge_mgr = get_node_or_null("/root/ForgeItemManager")
	if forge_mgr:
		deleted_forged = forge_mgr.get_locally_deleted_items()

	print("[CharacterStats] Syncing to backend: level=%d, xp=%d, gold=%d" % [level, experience, gold])
	ashbane_auth.sync_character_to_backend(
		level,
		experience,
		gold,
		inventory_data,
		equipped_weapon_id,
		equipped_armor_data,
		weapon_skills_data,
		quest_data,
		tutorial_done,
		deleted_forged
	)

func _initial_server_sync() -> void:
	"""Called shortly after session start to sync initial state to server"""
	print("[CharacterStats] Initial server sync: level=%d, xp=%d/%d (%.1f%%)" % [level, experience, experience_to_next_level, get_experience_progress() * 100])
	_sync_to_server()

# ============================================
# PLAYTIME & KILL TRACKING
# ============================================

func start_session() -> void:
	"""Start tracking playtime for this session"""
	session_start_time = Time.get_unix_time_from_system()
	# Do an initial sync to server after a short delay (let world finish loading)
	if not Engine.is_editor_hint():
		get_tree().create_timer(2.0).timeout.connect(_initial_server_sync)

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
# ALLEGIANCE SYSTEM
# ============================================

func is_rogue() -> bool:
	"""Check if player has no allegiance (rogue status)"""
	return allegiance_id.is_empty()

func is_ashbane() -> bool:
	"""Check if player is in the default Ashbane faction"""
	return allegiance_id == ALLEGIANCE_ASHBANE

func get_allegiance() -> String:
	"""Get current allegiance ID (empty string = rogue)"""
	return allegiance_id

func get_allegiance_display_name() -> String:
	"""Get display name for current allegiance"""
	if allegiance_id.is_empty():
		return "Rogue"
	elif allegiance_id == ALLEGIANCE_ASHBANE:
		return "Ashbane"
	else:
		return allegiance_id.capitalize()

func is_same_allegiance(other_allegiance: String) -> bool:
	"""Check if another allegiance matches ours (rogues never match anyone)"""
	if allegiance_id.is_empty() or other_allegiance.is_empty():
		return false  # Rogues don't match anyone, including other rogues
	return allegiance_id == other_allegiance

func can_damage_player(target_allegiance: String, is_in_party: bool, is_dueling_target: bool) -> bool:
	"""Check if we can damage another player based on allegiance rules.

	Rules:
	- Same party = no damage (unless dueling that player)
	- Dueling target = yes damage
	- Same allegiance = no damage
	- Different allegiance = yes damage
	- Rogue attacker = yes damage to everyone
	- Rogue target = yes, can be damaged by everyone
	"""
	# Dueling overrides all other rules
	if is_dueling_target:
		return true

	# Party protection overrides allegiance
	if is_in_party:
		return false

	# Rogues can damage and be damaged by everyone
	if allegiance_id.is_empty() or target_allegiance.is_empty():
		return true

	# Same allegiance = no damage
	if allegiance_id == target_allegiance:
		return false

	# Different allegiance = can damage
	return true

func can_heal_player(target_allegiance: String, is_in_party: bool) -> bool:
	"""Check if we can heal another player based on allegiance rules.

	Rules:
	- Same party = yes heal (regardless of allegiance)
	- Same allegiance = yes heal
	- Different allegiance (not in party) = no heal
	- Rogue target (not in party) = no heal
	"""
	# Party allows healing regardless of allegiance
	if is_in_party:
		return true

	# Rogues can only be healed by party members
	if target_allegiance.is_empty():
		return false

	# If we're rogue, we can only heal party members (handled above)
	if allegiance_id.is_empty():
		return false

	# Same allegiance = can heal
	return allegiance_id == target_allegiance

func set_allegiance(new_allegiance: String, force: bool = false) -> bool:
	"""Change allegiance. Returns false if on cooldown.

	Rules:
	- Going rogue = immediate (no cooldown)
	- Rejoining Ashbane after being rogue = 1 hour cooldown
	- Switching between player allegiances = 1 day cooldown
	"""
	if new_allegiance == allegiance_id:
		return true  # Already in this allegiance

	var current_time = Time.get_unix_time_from_system()
	var time_since_change = current_time - allegiance_last_change

	# Check cooldowns based on transition type
	if not force:
		# Rejoining Ashbane from rogue = 1 hour cooldown
		if allegiance_id.is_empty() and new_allegiance == ALLEGIANCE_ASHBANE:
			if time_since_change < ROGUE_REJOIN_COOLDOWN:
				var remaining = ROGUE_REJOIN_COOLDOWN - time_since_change
				var minutes = int(remaining / 60)
				print("⚠️ Cannot rejoin Ashbane yet. %d minutes remaining." % minutes)
				return false
		# Switching between player allegiances = 1 day cooldown
		elif not new_allegiance.is_empty() and new_allegiance != ALLEGIANCE_ASHBANE:
			if time_since_change < ALLEGIANCE_CHANGE_COOLDOWN:
				var remaining = ALLEGIANCE_CHANGE_COOLDOWN - time_since_change
				var hours = int(remaining / 3600)
				print("⚠️ Cannot change allegiance yet. %d hours remaining." % hours)
				return false
		# Going rogue = no cooldown (always allowed)

	var old_allegiance = allegiance_id
	allegiance_id = new_allegiance
	allegiance_last_change = current_time

	allegiance_changed.emit(old_allegiance, new_allegiance)

	if new_allegiance.is_empty():
		print("⚔️ You are now ROGUE - hostile to all factions!")
	elif new_allegiance == ALLEGIANCE_ASHBANE:
		print("🌳 You have joined the Ashbane faction.")
	else:
		print("🛡️ You have joined allegiance: %s" % new_allegiance)

	return true

func go_rogue() -> bool:
	"""Leave current allegiance and become rogue"""
	return set_allegiance(ALLEGIANCE_ROGUE)

func join_ashbane() -> bool:
	"""Join or return to the Ashbane faction"""
	return set_allegiance(ALLEGIANCE_ASHBANE)
