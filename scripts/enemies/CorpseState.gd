extends Node
class_name CorpseState

## Corpse State System
## Defines states and constants for the lootable corpse system

enum State {
	FRESH,      # 0-60s: Full loot, visible indicator
	DECAYING,   # 60s-5min: Loot available, visual decay
	ROTTED      # 5min+: Despawn, loot lost
}

# Timing constants
const CORPSE_DECAY_TIME: float = 300.0  # 5 minutes in seconds
const CORPSE_FRESH_TIME: float = 60.0   # First minute is "fresh"

# Loot constants
const AOE_LOOT_RADIUS: float = 300.0  # AOE loot collection radius in pixels

# Visual constants
const CORPSE_LOOT_GLOW_COLOR: Color = Color(0.8, 1.0, 0.8, 0.5)  # Pale green glow
const DECAY_ALPHA_MULTIPLIER: float = 0.7  # Transparency in decaying state

# Loot drop chances (must sum to 1.0)
const LOOT_DROP_CHANCES = {
	0: 0.40,  # 40% chance for 0 items
	1: 0.45,  # 45% chance for 1 item
	2: 0.15   # 15% chance for 2 items
}

# Skeleton-specific loot table
const SKELETON_LOOT_TABLE = [
	{
		"name": "Bone Ember",
		"description": "dreadland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 70,
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"  # Used for campfire crit buff
	},
	{
		"name": "Ancient Skull",
		"description": "A weathered skull from an ancient warrior. Radiates faint energy.",
		"value": 15,
		"rarity": "Common",
		"drop_weight": 25,
		"type": "material",
		"stackable": true,
		"max_stack": 99
	},
	{
		"name": "Cursed Femur",
		"description": "This bone hums with dark magic. Handle with care.",
		"value": 35,
		"rarity": "Common",
		"drop_weight": 4,
		"type": "material",
		"stackable": true,
		"max_stack": 99
	},
	{
		"name": "Lich's Finger Bone",
		"description": "The preserved digit of a powerful undead mage. Very rare.",
		"value": 100,
		"rarity": "Common",
		"drop_weight": 1,
		"type": "material",
		"stackable": false
	}
]

# Guardian-specific loot table (Level 7-9 ruins guardians)
# Drops: Iron Short Sword, Boots (plate/leather/cloth), Arms (plate/leather/cloth)
# Low drop rates - intended to be a grind
const GUARDIAN_LOOT_TABLE = [
	{
		"id": "iron_short_sword",
		"name": "Iron Short Sword",
		"description": "A reliable iron blade. Standard issue for dreadland survivors.",
		"weapon_type": "sword",
		"base_damage": 12,
		"attack_speed": "medium",
		"crit_chance": 0.071,
		"required_level": 1,
		"value": 150,
		"rarity": "Common",
		"sprite_path": "res://assets/equipment/weapons/longsword.png",
		"drop_weight": 8,
		"type": "weapon",
		"slot": "mainhand",
		"stackable": false
	},
	# Feet - Plate
	{
		"id": "copper_plate_boots",
		"name": "Copper Plate Boots",
		"description": "Tier 1 copper-plated boots. Basic protection for your feet.",
		"slot": "feet",
		"armor_type": "plate",
		"defense": 5,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 4,
		"stackable": false
	},
	# Feet - Leather
	{
		"id": "rawhide_boots",
		"name": "Rawhide Boots",
		"description": "Light leather boots. Quiet and nimble.",
		"slot": "feet",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 4,
		"stackable": false
	},
	# Feet - Cloth
	{
		"id": "linen_sandals",
		"name": "Linen Sandals",
		"description": "Open sandals wrapped with cloth. Light and airy.",
		"slot": "feet",
		"armor_type": "cloth",
		"defense": 1,
		"type": "armor",
		"value": 30,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 4,
		"stackable": false
	},
	# Arms - Plate
	{
		"id": "copper_plate_bracers",
		"name": "Copper Plate Bracers",
		"description": "Reinforced arm guards. Protects your forearms in combat.",
		"slot": "arms",
		"armor_type": "plate",
		"defense": 6,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 4,
		"stackable": false
	},
	# Arms - Leather
	{
		"id": "rawhide_wraps",
		"name": "Rawhide Wraps",
		"description": "Leather strips wrapped around the forearms. Light protection.",
		"slot": "arms",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 4,
		"stackable": false
	},
	# Arms - Cloth
	{
		"id": "linen_wrappings",
		"name": "Linen Wrappings",
		"description": "Cloth bindings for the arms. Offers minimal protection.",
		"slot": "arms",
		"armor_type": "cloth",
		"defense": 1,
		"type": "armor",
		"value": 30,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 4,
		"stackable": false
	},
	{
		"name": "Bone Ember",
		"description": "dreadland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 68,
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"
	}
]

# Level 10 Guardian loot table - can drop full armor sets (plate/leather/cloth)
# These are the elite guardians with full armor, higher chance for gear
const GUARDIAN_ELITE_LOOT_TABLE = [
	{
		"id": "iron_short_sword",
		"name": "Iron Short Sword",
		"description": "A reliable iron blade. Standard issue for dreadland survivors.",
		"weapon_type": "sword",
		"base_damage": 12,
		"attack_speed": "medium",
		"crit_chance": 0.071,
		"required_level": 1,
		"value": 150,
		"rarity": "Common",
		"sprite_path": "res://assets/equipment/weapons/longsword.png",
		"drop_weight": 6,
		"type": "weapon",
		"slot": "mainhand",
		"stackable": false
	},
	# Feet - Plate
	{
		"id": "copper_plate_boots",
		"name": "Copper Plate Boots",
		"description": "Tier 1 copper-plated boots. Basic protection for your feet.",
		"slot": "feet",
		"armor_type": "plate",
		"defense": 5,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 3,
		"stackable": false
	},
	# Feet - Leather
	{
		"id": "rawhide_boots",
		"name": "Rawhide Boots",
		"description": "Light leather boots. Quiet and nimble.",
		"slot": "feet",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 3,
		"stackable": false
	},
	# Feet - Cloth
	{
		"id": "linen_sandals",
		"name": "Linen Sandals",
		"description": "Open sandals wrapped with cloth. Light and airy.",
		"slot": "feet",
		"armor_type": "cloth",
		"defense": 1,
		"type": "armor",
		"value": 30,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 3,
		"stackable": false
	},
	# Arms - Plate
	{
		"id": "copper_plate_bracers",
		"name": "Copper Plate Bracers",
		"description": "Reinforced arm guards. Protects your forearms in combat.",
		"slot": "arms",
		"armor_type": "plate",
		"defense": 6,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 3,
		"stackable": false
	},
	# Arms - Leather
	{
		"id": "rawhide_wraps",
		"name": "Rawhide Wraps",
		"description": "Leather strips wrapped around the forearms. Light protection.",
		"slot": "arms",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 3,
		"stackable": false
	},
	# Arms - Cloth
	{
		"id": "linen_wrappings",
		"name": "Linen Wrappings",
		"description": "Cloth bindings for the arms. Offers minimal protection.",
		"slot": "arms",
		"armor_type": "cloth",
		"defense": 1,
		"type": "armor",
		"value": 30,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 3,
		"stackable": false
	},
	# Legs - Plate
	{
		"id": "copper_plate_greaves",
		"name": "Copper Plate Greaves",
		"description": "Heavy leg armor. Protects from knee to ankle.",
		"slot": "legs",
		"armor_type": "plate",
		"defense": 8,
		"type": "armor",
		"value": 75,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 2,
		"stackable": false
	},
	# Legs - Leather
	{
		"id": "rawhide_leggings",
		"name": "Rawhide Leggings",
		"description": "Flexible leather pants. Good for quick movement.",
		"slot": "legs",
		"armor_type": "leather",
		"defense": 5,
		"type": "armor",
		"value": 60,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 2,
		"stackable": false
	},
	# Legs - Cloth
	{
		"id": "linen_trousers",
		"name": "Linen Trousers",
		"description": "Simple cloth pants. Comfortable for long journeys.",
		"slot": "legs",
		"armor_type": "cloth",
		"defense": 2,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 2,
		"stackable": false
	},
	# Head - Plate
	{
		"id": "copper_plate_helm",
		"name": "Copper Plate Helm",
		"description": "A sturdy copper helm. Essential head protection for warriors.",
		"slot": "head",
		"armor_type": "plate",
		"defense": 7,
		"type": "armor",
		"value": 75,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 2,
		"stackable": false
	},
	# Head - Leather
	{
		"id": "rawhide_hood",
		"name": "Rawhide Hood",
		"description": "A hood of treated animal hide. Light and flexible.",
		"slot": "head",
		"armor_type": "leather",
		"defense": 4,
		"type": "armor",
		"value": 60,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 2,
		"stackable": false
	},
	# Head - Cloth
	{
		"id": "linen_hood",
		"name": "Linen Hood",
		"description": "A simple cloth hood. Favored by wandering scholars.",
		"slot": "head",
		"armor_type": "cloth",
		"defense": 2,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "linen",
		"drop_weight": 2,
		"stackable": false
	},
	{
		"name": "Bone Ember",
		"description": "dreadland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 57,
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"
	}
]

# Wave boss loot table - guaranteed gear drops (higher equipment weights, lower material weights)
const WAVE_BOSS_LOOT_TABLE = [
	{
		"id": "iron_short_sword",
		"name": "Iron Short Sword",
		"description": "A reliable iron blade. Standard issue for dreadland survivors.",
		"weapon_type": "sword",
		"base_damage": 12,
		"attack_speed": "medium",
		"crit_chance": 0.071,
		"required_level": 1,
		"value": 150,
		"rarity": "Common",
		"sprite_path": "res://assets/equipment/weapons/longsword.png",
		"drop_weight": 12,
		"type": "weapon",
		"slot": "mainhand",
		"stackable": false
	},
	{
		"id": "copper_plate_boots",
		"name": "Copper Plate Boots",
		"description": "Tier 1 copper-plated boots. Basic protection for your feet.",
		"slot": "feet",
		"armor_type": "plate",
		"defense": 5,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"id": "rawhide_boots",
		"name": "Rawhide Boots",
		"description": "Light leather boots. Quiet and nimble.",
		"slot": "feet",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"id": "copper_plate_bracers",
		"name": "Copper Plate Bracers",
		"description": "Reinforced arm guards. Protects your forearms in combat.",
		"slot": "arms",
		"armor_type": "plate",
		"defense": 6,
		"type": "armor",
		"value": 50,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"id": "rawhide_wraps",
		"name": "Rawhide Wraps",
		"description": "Leather strips wrapped around the forearms. Light protection.",
		"slot": "arms",
		"armor_type": "leather",
		"defense": 3,
		"type": "armor",
		"value": 40,
		"rarity": "Common",
		"sprite_name": "rawhide",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"name": "Bone Ember",
		"description": "dreadland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 20,
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"
	}
]

# Wave boss drop chances - guaranteed at least 1 item
const WAVE_BOSS_DROP_CHANCES = {
	0: 0.0,   # 0% chance for 0 items (guaranteed drops)
	1: 0.50,  # 50% chance for 1 item
	2: 0.50   # 50% chance for 2 items
}

static func roll_loot_count(is_wave_boss: bool = false) -> int:
	"""Roll how many items this corpse should drop (0-2)"""
	var drop_chances = WAVE_BOSS_DROP_CHANCES if is_wave_boss else LOOT_DROP_CHANCES
	var roll = randf()
	var cumulative = 0.0

	for count in [0, 1, 2]:
		cumulative += drop_chances[count]
		if roll <= cumulative:
			return count

	return 0  # Fallback

static func roll_loot_item(is_guardian: bool = false, enemy_level: int = 1, is_wave_boss: bool = false) -> Dictionary:
	"""Roll a random item from the appropriate loot table"""
	var loot_table: Array

	if is_wave_boss:
		loot_table = WAVE_BOSS_LOOT_TABLE
	elif is_guardian:
		# Level 10 guardians use elite table with full copper plate drops
		if enemy_level >= 10:
			loot_table = GUARDIAN_ELITE_LOOT_TABLE
		else:
			loot_table = GUARDIAN_LOOT_TABLE
	else:
		loot_table = SKELETON_LOOT_TABLE

	if loot_table.is_empty():
		return {}

	# Calculate total weight
	var total_weight = 0
	for item in loot_table:
		total_weight += item.get("drop_weight", 1)

	# Roll for item
	var roll = randi() % total_weight
	var cumulative = 0

	for item in loot_table:
		cumulative += item.get("drop_weight", 1)
		if roll < cumulative:
			return item.duplicate()

	# Fallback to first item (should never reach here, but safety check)
	if loot_table.size() > 0:
		return loot_table[0].duplicate()
	return {}
