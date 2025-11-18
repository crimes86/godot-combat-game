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
		"name": "Bone Shard",
		"description": "Sharp fragment of bone. Could be useful for crafting.",
		"value": 5,
		"rarity": "Common",
		"drop_weight": 70,
		"type": "material",
		"stackable": true,
		"max_stack": 100
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

static func roll_loot_count() -> int:
	"""Roll how many items this corpse should drop (0-2)"""
	var roll = randf()
	var cumulative = 0.0

	for count in [0, 1, 2]:
		cumulative += LOOT_DROP_CHANCES[count]
		if roll <= cumulative:
			return count

	return 0  # Fallback

static func roll_loot_item() -> Dictionary:
	"""Roll a random item from the skeleton loot table"""
	if SKELETON_LOOT_TABLE.is_empty():
		return {}

	# Calculate total weight
	var total_weight = 0
	for item in SKELETON_LOOT_TABLE:
		total_weight += item.get("drop_weight", 1)

	# Roll for item
	var roll = randi() % total_weight
	var cumulative = 0

	for item in SKELETON_LOOT_TABLE:
		cumulative += item.get("drop_weight", 1)
		if roll < cumulative:
			return item.duplicate()

	# Fallback to first item
	return SKELETON_LOOT_TABLE[0].duplicate()
