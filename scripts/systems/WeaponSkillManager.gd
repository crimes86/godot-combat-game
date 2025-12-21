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

# Title thresholds
const TITLE_THRESHOLDS = [0, 50, 100, 150, 200, 250, 300]

# Title names per category
const TITLES = {
	"swords": ["", "Squire", "Swordsman", "Bladesman", "Blademaster", "Sword Saint", "Kensei"],
	"daggers": ["", "Footpad", "Cutthroat", "Assassin", "Shadowblade", "Phantom", "Reaper"],
	"axes": ["", "Woodsman", "Hewer", "Cleaver", "Headsman", "Warlord", "Berserker"],
	"maces": ["", "Initiate", "Enforcer", "Crusher", "Demolisher", "Juggernaut", "Titan"],
	"hammers": ["", "Striker", "Smasher", "Breaker", "Earthshaker", "Worldbreaker", "Godhand"],
	"spears": ["", "Militia", "Pikeman", "Hoplite", "Lancer", "Dragoon", "Valkyrie"],
	"bows": ["", "Fletcher", "Archer", "Marksman", "Sharpshooter", "Deadeye", "Hawkeye"],
	"healing": ["", "Acolyte", "Healer", "Priest", "Bishop", "Cardinal", "Saint"],
	"arcane": ["", "Apprentice", "Conjurer", "Mage", "Sorcerer", "Archmage", "Archon"],
	"guns": ["", "Recruit", "Gunner", "Marksman", "Sharpshooter", "Ace", "Deadshot"],
	"blocking": ["", "Defender", "Guardian", "Bulwark", "Shieldmaster", "Aegis", "Invincible"]
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

## Get title index for skill level (0-6)
func get_title_index(skill: float) -> int:
	if skill >= 300:
		return 6
	elif skill >= 250:
		return 5
	elif skill >= 200:
		return 4
	elif skill >= 150:
		return 3
	elif skill >= 100:
		return 2
	elif skill >= 50:
		return 1
	else:
		return 0

## Get current title for category
func get_title(category: String) -> String:
	var cat = category.to_lower()
	var skill = get_skill(cat)
	var index = get_title_index(skill)
	var titles = TITLES.get(cat, ["", "Novice", "Apprentice", "Journeyman", "Expert", "Master", "Grandmaster"])
	return titles[index] if index < titles.size() else titles[-1]

## Add skill points with catch-up mechanic
func add_skill(category: String, base_amount: float) -> float:
	var cat = category.to_lower()
	if cat not in skills:
		return 0.0

	var cap = get_skill_cap()
	var current = skills[cat]

	# Already at cap
	if current >= cap:
		return 0.0

	# Catch-up multiplier: 3x at empty, 0.5x near cap
	var fill_ratio = current / float(cap) if cap > 0 else 0.0
	var catch_up_mult = lerpf(3.0, 0.5, fill_ratio)

	var final_gain = base_amount * catch_up_mult
	var old_skill = current
	var old_title_index = get_title_index(old_skill)

	# Apply gain (capped)
	skills[cat] = minf(current + final_gain, float(cap))
	var new_skill = skills[cat]
	var new_title_index = get_title_index(new_skill)

	# Emit skill gained signal
	skill_gained.emit(cat, final_gain, new_skill)

	# Check for title advancement
	if new_title_index > old_title_index:
		var new_title = get_title(cat)
		title_earned.emit(cat, new_title)
		skill_level_up.emit(cat, new_title_index, new_title)

	return final_gain

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
