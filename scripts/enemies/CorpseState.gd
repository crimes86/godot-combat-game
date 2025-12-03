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
		"description": "Wasteland bones infused with supernatural heat. Burns with ghostly fire.",
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
		"rarity": "Uncommon",
		"drop_weight": 25,
		"type": "material",
		"stackable": false
	},
	{
		"name": "Cursed Femur",
		"description": "This bone hums with dark magic. Handle with care.",
		"value": 35,
		"rarity": "Rare",
		"drop_weight": 4,
		"type": "material",
		"stackable": false
	},
	{
		"name": "Lich's Finger Bone",
		"description": "The preserved digit of a powerful undead mage. Very rare.",
		"value": 100,
		"rarity": "Epic",
		"drop_weight": 1,
		"type": "material",
		"stackable": false
	}
]

# Guardian-specific loot table (Level 7-9 ruins guardians)
# Drops: Iron Short Sword, Copper Boots, Copper Armguards
# Low drop rates - intended to be a grind
const GUARDIAN_LOOT_TABLE = [
	{
		"id": "iron_short_sword",
		"name": "Iron Short Sword",
		"description": "A reliable iron blade. Standard issue for wasteland survivors.",
		"weapon_type": "sword",
		"base_damage": 12,
		"attack_speed": "medium",
		"crit_chance": 0.071,
		"required_level": 1,
		"value": 150,
		"rarity": "Common",
		"sprite_path": "res://assets/weapons/longsword.png",
		"drop_weight": 8,  # 8% chance (low drop rate - grind required)
		"type": "weapon",
		"slot": "mainhand",  # Required for equipping weapons
		"stackable": false
	},
	{
		"id": "copper_plate_boots",
		"name": "Copper Plate Boots",
		"description": "Tier 1 copper-plated boots. Basic protection for your feet.",
		"slot": "feet",
		"defense": 5,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 12,  # 12% chance
		"stackable": false
	},
	{
		"id": "copper_plate_armguards",
		"name": "Copper Plate Armguards",
		"description": "Tier 1 copper-plated arm guards. Protects your forearms in combat.",
		"slot": "arms",
		"defense": 6,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 12,  # 12% chance
		"stackable": false
	},
	{
		"name": "Bone Ember",
		"description": "Wasteland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 68,  # Fill remaining weight (common drop)
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"  # Used for campfire crit buff
	}
]

# Level 10 Guardian loot table - can drop full copper plate set
# These are the elite guardians with full armor, higher chance for gear
const GUARDIAN_ELITE_LOOT_TABLE = [
	{
		"id": "iron_short_sword",
		"name": "Iron Short Sword",
		"description": "A reliable iron blade. Standard issue for wasteland survivors.",
		"weapon_type": "sword",
		"base_damage": 12,
		"attack_speed": "medium",
		"crit_chance": 0.071,
		"required_level": 1,
		"value": 150,
		"rarity": "Common",
		"sprite_path": "res://assets/weapons/longsword.png",
		"drop_weight": 6,
		"type": "weapon",
		"slot": "mainhand",
		"stackable": false
	},
	{
		"id": "copper_plate_boots",
		"name": "Copper Plate Boots",
		"description": "Tier 1 copper-plated boots. Basic protection for your feet.",
		"slot": "feet",
		"defense": 5,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"id": "copper_plate_armguards",
		"name": "Copper Plate Armguards",
		"description": "Tier 1 copper-plated arm guards. Protects your forearms in combat.",
		"slot": "arms",
		"defense": 6,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 8,
		"stackable": false
	},
	{
		"id": "copper_plate_greaves",
		"name": "Copper Plate Greaves",
		"description": "Tier 1 copper-plated leg armor. Solid leg protection.",
		"slot": "legs",
		"defense": 8,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 6,  # Rarer - only level 10 drops
		"stackable": false
	},
	{
		"id": "copper_plate_helmet",
		"name": "Copper Plate Helmet",
		"description": "Tier 1 copper-plated helmet. Essential head protection.",
		"slot": "head",
		"defense": 7,
		"type": "armor",
		"value": 0,
		"rarity": "Common",
		"sprite_name": "copper_plate",
		"drop_weight": 6,  # Rarer - only level 10 drops
		"stackable": false
	},
	{
		"name": "Bone Ember",
		"description": "Wasteland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 66,  # Fill remaining weight
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"fuel_type": "bone_ember"
	}
]

static func roll_loot_count() -> int:
	"""Roll how many items this corpse should drop (0-2)"""
	var roll = randf()
	var cumulative = 0.0

	for count in [0, 1, 2]:
		cumulative += LOOT_DROP_CHANCES[count]
		if roll <= cumulative:
			return count

	return 0  # Fallback

static func roll_loot_item(is_guardian: bool = false, enemy_level: int = 1) -> Dictionary:
	"""Roll a random item from the appropriate loot table"""
	var loot_table: Array

	if is_guardian:
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
