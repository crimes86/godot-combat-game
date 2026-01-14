extends Node
## WeaponSkillManager - Tracks weapon proficiency for each weapon category
## Skill affects hit chance and damage. Unlocks titles, passives, and abilities.

# Signals
signal skill_gained(category: String, amount: float, new_total: float)
signal skill_level_up(category: String, new_level: int, title: String)
signal title_earned(category: String, title: String)

# Weapon categories (map weapon types to these)
const CATEGORIES = [
	"swords", "daggers", "axes", "maces", "hammers",
	"spears", "bows", "healing", "arcane", "guns", "blocking"
]

# Skill data per category
var skills: Dictionary = {}  # category -> float (0.0 to 300.0)

# Skill gain constants (from spec)
const SKILL_GAIN_HIT: float = 0.5
const SKILL_GAIN_MISS: float = 0.2
const SKILL_GAIN_KILL: float = 2.0
const SKILL_GAIN_CRIT: float = 0.5  # Bonus on top of hit

# Block skill gain constants
const SKILL_GAIN_BLOCK: float = 1.0  # Full block
const SKILL_GAIN_PARTIAL_BLOCK: float = 0.5  # Partial block
const SKILL_GAIN_HIT_WITH_SHIELD: float = 0.1  # Hit taken while shield equipped

# Title thresholds - absolute skill values
# 0=Untrained (0 skill), 1+ skill gets first title, then 50, 100, 150, 200, 250 for higher tiers
const TITLE_THRESHOLDS = [0, 1, 50, 100, 150, 200, 250]

# Title names per category - index 0 is "Untrained" (0 skill only)
const TITLES = {
	"swords": ["Untrained", "Squire", "Swordsman", "Bladesman", "Blademaster", "Sword Saint", "Kensei"],
	"daggers": ["Untrained", "Footpad", "Cutthroat", "Assassin", "Shadowblade", "Phantom", "Reaper"],
	"axes": ["Untrained", "Woodsman", "Hewer", "Cleaver", "Headsman", "Warlord", "Berserker"],
	"maces": ["Untrained", "Initiate", "Enforcer", "Crusher", "Demolisher", "Juggernaut", "Titan"],
	"hammers": ["Untrained", "Striker", "Smasher", "Breaker", "Earthshaker", "Worldbreaker", "Godhand"],
	"spears": ["Untrained", "Militia", "Pikeman", "Hoplite", "Lancer", "Dragoon", "Valkyrie"],
	"bows": ["Untrained", "Fletcher", "Archer", "Marksman", "Sharpshooter", "Deadeye", "Hawkeye"],
	"healing": ["Untrained", "Acolyte", "Healer", "Priest", "Bishop", "Cardinal", "Saint"],
	"arcane": ["Untrained", "Apprentice", "Conjurer", "Mage", "Sorcerer", "Archmage", "Archon"],
	"guns": ["Untrained", "Recruit", "Gunner", "Marksman", "Sharpshooter", "Ace", "Deadshot"],
	"blocking": ["Untrained", "Defender", "Guardian", "Bulwark", "Shieldmaster", "Aegis", "Invincible"]
}

# Weapon type to category mapping
const WEAPON_TYPE_MAP = {
	"sword": "swords",
	"longsword": "swords",
	"katana": "swords",
	"saber": "swords",
	"scimitar": "swords",
	"rapier": "swords",
	"dagger": "daggers",
	"stiletto": "daggers",
	"axe": "axes",
	"greataxe": "axes",
	"hatchet": "axes",
	"mace": "maces",
	"morningstar": "maces",
	"club": "maces",
	"hammer": "hammers",
	"warhammer": "hammers",
	"maul": "hammers",
	"spear": "spears",
	"pike": "spears",
	"halberd": "spears",
	"bow": "bows",
	"shortbow": "bows",
	"longbow": "bows",
	"staff": "arcane",  # Default staff to arcane
	"healing_staff": "healing",
	"gun": "guns",
	"pistol": "guns",
	"rifle": "guns"
}

func _ready() -> void:
	# Initialize all skills to 0
	for category in CATEGORIES:
		skills[category] = 0.0

## Get the category for a weapon type
func get_category_for_weapon(weapon_type: String) -> String:
	var type_lower = weapon_type.to_lower()
	return WEAPON_TYPE_MAP.get(type_lower, "swords")  # Default to swords

## Get current skill for a category
func get_skill(category: String) -> float:
	return skills.get(category.to_lower(), 0.0)

## Get skill cap based on player level
func get_skill_cap() -> int:
	var cap = CharacterStats.level * 10
	return mini(cap, 300)

## Get skill as percentage of cap (0.0 to 1.0)
func get_skill_percent(category: String) -> float:
	var cap = get_skill_cap()
	if cap <= 0:
		return 0.0
	return clampf(get_skill(category) / float(cap), 0.0, 1.0)

## Get miss chance for current skill level (0.0 to 0.15)
func get_miss_chance(category: String) -> float:
	var percent = get_skill_percent(category)
	# 0-10%: 15% miss, 11-25%: 12%, 26-50%: 8%, 51-75%: 4%, 76-99%: 2%, 100%: 0%
	if percent >= 1.0:
		return 0.0
	elif percent >= 0.76:
		return 0.02
	elif percent >= 0.51:
		return 0.04
	elif percent >= 0.26:
		return 0.08
	elif percent >= 0.11:
		return 0.12
	else:
		return 0.15

## Get damage multiplier for current skill level (0.70 to 1.0)
func get_damage_multiplier(category: String) -> float:
	var percent = get_skill_percent(category)
	# 0-10%: 70%, 11-25%: 75%, 26-50%: 82%, 51-75%: 90%, 76-99%: 96%, 100%: 100%
	if percent >= 1.0:
		return 1.0
	elif percent >= 0.76:
		return 0.96
	elif percent >= 0.51:
		return 0.90
	elif percent >= 0.26:
		return 0.82
	elif percent >= 0.11:
		return 0.75
	else:
		return 0.70

## Roll for hit (returns true if hit, false if miss)
func roll_hit(category: String) -> bool:
	var miss_chance = get_miss_chance(category)
	return randf() >= miss_chance

## Get title index for skill level (0-6) based on absolute thresholds
func get_title_index(skill: float) -> int:
	# Absolute thresholds: 0=Untrained, 1+=First title, 50+=Second, etc.
	if skill <= 0:
		return 0  # Untrained
	elif skill >= 250:
		return 6  # Grandmaster tier
	elif skill >= 200:
		return 5
	elif skill >= 150:
		return 4
	elif skill >= 100:
		return 3
	elif skill >= 50:
		return 2
	else:
		return 1  # 1-49 skill = first real title (Militia, Squire, etc.)

## Get current title for category
func get_title(category: String) -> String:
	var cat = category.to_lower()
	var skill = get_skill(cat)
	var index = get_title_index(skill)
	var titles = TITLES.get(cat, ["Untrained", "Novice", "Apprentice", "Journeyman", "Expert", "Master", "Grandmaster"])
	return titles[index] if index < titles.size() else titles[-1]


## Get the next title the player is working toward (or empty if maxed)
func get_next_title(category: String) -> String:
	var cat = category.to_lower()
	var skill = get_skill(cat)
	var index = get_title_index(skill)
	var titles = TITLES.get(cat, ["Untrained", "Novice", "Apprentice", "Journeyman", "Expert", "Master", "Grandmaster"])
	var next_index = index + 1
	if next_index >= titles.size():
		return ""  # Already at max
	return titles[next_index]


## Get skill needed for next title (returns -1 if already maxed)
func get_skill_for_next_title(category: String) -> int:
	var cat = category.to_lower()
	var skill = get_skill(cat)
	var index = get_title_index(skill)

	if index >= 6:
		return -1  # Already at max title

	# Absolute thresholds matching get_title_index
	var thresholds = [0, 1, 50, 100, 150, 200, 250]
	return thresholds[index + 1] if index + 1 < thresholds.size() else 250

## Add skill points (linear progression, no catch-up)
func add_skill(category: String, amount: float) -> float:
	var cat = category.to_lower()
	if cat not in skills:
		return 0.0

	var cap = get_skill_cap()
	var current = skills[cat]

	# Already at cap
	if current >= cap:
		return 0.0

	var old_skill = current
	var old_title_index = get_title_index(old_skill)

	# Apply gain (capped at current level cap)
	var actual_gain = minf(amount, float(cap) - current)
	skills[cat] = current + actual_gain
	var new_skill = skills[cat]
	var new_title_index = get_title_index(new_skill)

	# Emit skill gained signal
	skill_gained.emit(cat, actual_gain, new_skill)

	# Check for title advancement
	if new_title_index > old_title_index:
		var new_title = get_title(cat)
		title_earned.emit(cat, new_title)
		skill_level_up.emit(cat, new_title_index, new_title)

	return actual_gain

## Called when player lands a hit
func on_hit(weapon_type: String, is_crit: bool = false) -> float:
	var category = get_category_for_weapon(weapon_type)
	var gain = SKILL_GAIN_HIT
	if is_crit:
		gain += SKILL_GAIN_CRIT
	return add_skill(category, gain)

## Called when player misses
func on_miss(weapon_type: String) -> float:
	var category = get_category_for_weapon(weapon_type)
	return add_skill(category, SKILL_GAIN_MISS)

## Called when player kills an enemy
func on_kill(weapon_type: String) -> float:
	var category = get_category_for_weapon(weapon_type)
	return add_skill(category, SKILL_GAIN_KILL)

## Called when player fully blocks an attack with shield
func on_block() -> float:
	return add_skill("blocking", SKILL_GAIN_BLOCK)

## Called when player partially blocks an attack with shield
func on_partial_block() -> float:
	return add_skill("blocking", SKILL_GAIN_PARTIAL_BLOCK)

## Called when player takes a hit while shield equipped (even if not blocked)
func on_hit_with_shield() -> float:
	return add_skill("blocking", SKILL_GAIN_HIT_WITH_SHIELD)

## Get block chance bonus from blocking skill (0.0 to 0.20)
func get_block_skill_bonus() -> float:
	var skill = get_skill("blocking")
	var cap = float(get_skill_cap())
	if cap <= 0:
		return 0.0
	# Up to +20% block chance at max skill
	return (skill / cap) * 0.20

## Get save data
func get_save_data() -> Dictionary:
	return {
		"weapon_skills": skills.duplicate()
	}

## Load save data
func load_save_data(data: Dictionary) -> void:
	var saved_skills = data.get("weapon_skills", {})
	for category in CATEGORIES:
		skills[category] = saved_skills.get(category, 0.0)

## Reset all skills (for new character)
func reset() -> void:
	for category in CATEGORIES:
		skills[category] = 0.0
