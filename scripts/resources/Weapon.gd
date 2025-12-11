extends Resource
class_name Weapon

## Weapon Resource
## Defines all properties of an equippable weapon
## Can be saved as .tres files for data-driven weapon creation

# ============================================
# BASIC PROPERTIES
# ============================================

@export var weapon_name: String = "Unnamed Weapon"
@export var weapon_type: String = "sword"  # sword, axe, staff, dagger, etc (visual/flavor)
@export var damage_type: String = "slash"  # blunt, slash, pierce (for crit window mechanics)
@export_multiline var description: String = ""

# ============================================
# COMBAT STATS
# ============================================

@export var base_damage: float = 5.0
@export var attack_speed_bonus: float = 0.0  # -0.2 = 20% faster, 0.2 = 20% slower
@export var crit_chance_bonus: float = 0.0   # 0.10 = +10% crit chance

# ============================================
# ATTACK MODE (melee vs ranged/healing)
# ============================================

@export var attack_mode: String = "melee"  # "melee", "ranged_heal", "ranged_damage"
@export var healing_power: float = 0.0  # Base healing for support weapons
@export var heal_radius: float = 80.0  # Radius of healing circle for ranged_heal weapons

# ============================================
# GUN PROPERTIES (for ranged_damage weapons)
# ============================================

@export var gun_radius: float = 28.0  # Targeting reticle radius (smaller = more precision required)
@export var gun_range: float = 350.0  # Maximum shooting distance from player
@export var gun_subtype: String = "railgun"  # "railgun", "battle_rifle", "pistol", "shotgun"
@export var burst_count: int = 1  # Shots per burst (1 = single shot, 3 = battle rifle burst)
@export var burst_delay: float = 0.10  # Delay between burst shots in seconds

# ============================================
# REQUIREMENTS & VALUE
# ============================================

@export var required_level: int = 1
@export var can_trade: bool = true
@export var sell_value: int = 0  # Gold value when selling (typically 50% of purchase price)

# ============================================
# ARTIFACT PROPERTIES
# ============================================

@export var is_artifact: bool = false
@export var artifact_level: int = 0
@export var artifact_max_level: int = 50
@export var artifact_experience: int = 0

# Social login properties
@export var social_provider: String = ""  # "battlenet", "steam", "psn", "xbox"
@export var achievement_score: int = 0    # Total achievement points used to generate weapon

# Artifact traits/abilities
@export var artifact_traits: Array = []

# ============================================
# VISUAL PROPERTIES
# ============================================

@export var weapon_color: Color = Color.WHITE
@export var glow_intensity: float = 0.0  # For artifact visuals
@export var particle_effect: String = ""  # Path to particle effect scene

# ============================================
# RARITY
# ============================================

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, ARTIFACT }
@export var rarity: Rarity = Rarity.COMMON

# ============================================
# METHODS
# ============================================

func get_rarity_name() -> String:
	"""Returns the rarity as a readable string"""
	return Rarity.keys()[rarity]

func get_rarity_color() -> Color:
	"""Returns color associated with rarity"""
	match rarity:
		Rarity.COMMON:
			return Color.WHITE
		Rarity.UNCOMMON:
			return Color.GREEN
		Rarity.RARE:
			return Color.BLUE
		Rarity.EPIC:
			return Color.PURPLE
		Rarity.LEGENDARY:
			return Color.ORANGE
		Rarity.ARTIFACT:
			return Color.GOLD
		_:
			return Color.WHITE

func get_total_damage() -> float:
	"""Returns total damage including artifact bonuses"""
	var damage = base_damage

	# Artifact scaling
	if is_artifact:
		damage += artifact_level * 2.0

	return damage

func get_total_healing() -> float:
	"""Returns total healing power including artifact bonuses"""
	var heal = healing_power

	# Artifact scaling for healing
	if is_artifact:
		heal += artifact_level * 1.5

	return heal

func is_healing_weapon() -> bool:
	"""Check if this weapon heals allies instead of damaging enemies"""
	return attack_mode == "ranged_heal"

func is_ranged_weapon() -> bool:
	"""Check if this weapon uses ranged targeting (cursor-based)"""
	return attack_mode in ["ranged_heal", "ranged_damage"]

func is_gun_weapon() -> bool:
	"""Check if this weapon is a gun (ranged damage with precision targeting)"""
	return weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"] or attack_mode == "ranged_damage"

func is_burst_weapon() -> bool:
	"""Check if this weapon fires in bursts (e.g., battle rifle 3-round burst)"""
	return burst_count > 1

func get_display_name() -> String:
	"""Returns formatted display name with rarity color"""
	if is_artifact and artifact_level > 0:
		return "%s [Lvl %d]" % [weapon_name, artifact_level]
	return weapon_name

func can_equip(player_level: int) -> bool:
	"""Check if player can equip this weapon"""
	return player_level >= required_level

func get_tooltip_text() -> String:
	"""Generate tooltip text for UI"""
	var text = "[b]%s[/b]\n" % weapon_name
	text += "[color=#888888]%s[/color]\n\n" % get_rarity_name()

	if is_healing_weapon():
		text += "Healing: +%.1f\n" % get_total_healing()
		text += "Heal Radius: %.0f\n" % heal_radius
	else:
		text += "Damage: +%.1f\n" % get_total_damage()
	
	if attack_speed_bonus != 0:
		var speed_text = "faster" if attack_speed_bonus < 0 else "slower"
		text += "Attack Speed: %.0f%% %s\n" % [abs(attack_speed_bonus) * 100, speed_text]
	
	if crit_chance_bonus != 0:
		text += "Crit Chance: +%.1f%%\n" % (crit_chance_bonus * 100)
	
	if is_artifact:
		text += "\n[color=gold]⚡ ARTIFACT WEAPON ⚡[/color]\n"
		text += "Artifact Level: %d/%d\n" % [artifact_level, artifact_max_level]
		if not artifact_traits.is_empty():
			text += "\nTraits:\n"
			var trait_count = artifact_traits.size()
			for i in range(trait_count):
				text += "  • %s\n" % artifact_traits[i]
	
	if required_level > 1:
		text += "\nRequired Level: %d\n" % required_level
	
	if not can_trade:
		text += "\n[color=red]Soulbound[/color]"
	
	if description:
		text += "\n[i]%s[/i]" % description
	
	return text

# ============================================
# ARTIFACT PROGRESSION
# ============================================

func gain_artifact_experience(amount: int) -> bool:
	"""
	Grant artifact experience. Returns true if leveled up.
	Only works for artifact weapons.
	"""
	if not is_artifact:
		return false
	
	if artifact_level >= artifact_max_level:
		return false
	
	artifact_experience += amount
	var xp_needed = get_artifact_xp_for_next_level()
	
	if artifact_experience >= xp_needed:
		artifact_experience -= xp_needed
		artifact_level += 1
		print("⚡ %s leveled up to %d!" % [weapon_name, artifact_level])
		return true
	
	return false

func get_artifact_xp_for_next_level() -> int:
	"""Calculate XP needed for next artifact level"""
	return int(1000 * pow(1.1, artifact_level))

func get_artifact_progress() -> float:
	"""Returns artifact XP progress as 0-1 value"""
	if artifact_level >= artifact_max_level:
		return 1.0
	var xp_needed = get_artifact_xp_for_next_level()
	return float(artifact_experience) / float(xp_needed)

# ============================================
# FACTORY METHODS
# ============================================

static func create_starter_weapon() -> Weapon:
	"""Create the default starting weapon"""
	var weapon = Weapon.new()
	weapon.weapon_name = "Rusty Sword"
	weapon.weapon_type = "sword"
	weapon.description = "A well-worn blade. Seen better days."
	weapon.base_damage = 0.0  # Player stats provide damage
	weapon.attack_speed_bonus = 0.0
	weapon.crit_chance_bonus = 0.0
	weapon.rarity = Rarity.COMMON
	weapon.can_trade = false
	weapon.required_level = 1
	return weapon

static func create_healing_staff(player_level: int = 1) -> Weapon:
	"""Create a basic healing staff"""
	var weapon = Weapon.new()
	weapon.weapon_name = "Healing Staff"
	weapon.weapon_type = "staff"
	weapon.damage_type = "magic"
	weapon.description = "Channel restorative energy to heal allies."
	weapon.attack_mode = "ranged_heal"
	weapon.healing_power = 10.0 + player_level * 0.5
	weapon.heal_radius = 80.0
	weapon.base_damage = 0.0  # Healing weapons don't deal damage
	weapon.attack_speed_bonus = 0.0
	weapon.crit_chance_bonus = 0.0
	weapon.rarity = Rarity.COMMON
	weapon.can_trade = true
	weapon.required_level = 1
	weapon.weapon_color = Color(0.4, 1.0, 0.5)  # Green tint
	return weapon

static func create_mock_artifact(provider: String = "battlenet") -> Weapon:
	"""Create a mock artifact weapon for testing"""
	var weapon = Weapon.new()
	
	match provider:
		"battlenet":
			weapon.weapon_name = "Thunderfury, Blessed Blade of the Windseeker"
			weapon.description = "Forged from countless mythic raids."
			weapon.base_damage = 25.0
			weapon.attack_speed_bonus = -0.30  # 30% faster
			weapon.crit_chance_bonus = 0.15    # +15% crit
			weapon.artifact_traits = ["Chain Master", "Thunder Strike", "Lightning Speed"]
		"steam":
			weapon.weapon_name = "Achievement Hunter's Blade"
			weapon.description = "For those who've seen it all."
			weapon.base_damage = 20.0
			weapon.attack_speed_bonus = -0.20
			weapon.crit_chance_bonus = 0.10
			weapon.artifact_traits = ["Completionist", "Boss Slayer", "Speed Runner"]
		"psn":
			weapon.weapon_name = "Trophy Collector's Edge"
			weapon.description = "Platinum-forged excellence."
			weapon.base_damage = 22.0
			weapon.attack_speed_bonus = -0.25
			weapon.crit_chance_bonus = 0.12
			weapon.artifact_traits = ["Trophy Master", "Platinum Touch"]
		"xbox":
			weapon.weapon_name = "Gamerscore Legend"
			weapon.description = "Achievement unlocked: Ultimate Warrior."
			weapon.base_damage = 23.0
			weapon.attack_speed_bonus = -0.22
			weapon.crit_chance_bonus = 0.13
			weapon.artifact_traits = ["Score Multiplier", "Achievement Boost"]
	
	weapon.weapon_type = "sword"
	weapon.is_artifact = true
	weapon.artifact_level = 1
	weapon.artifact_max_level = 50
	weapon.social_provider = provider
	weapon.achievement_score = 10000
	weapon.rarity = Rarity.ARTIFACT
	weapon.weapon_color = Color.GOLD
	weapon.glow_intensity = 1.0
	weapon.can_trade = true
	weapon.required_level = 1
	
	return weapon

static func create_random_drop(player_level: int) -> Weapon:
	"""Create a random weapon drop appropriate for player level"""
	var weapon = Weapon.new()

	# Random weapon type and name
	var weapon_types = ["sword", "axe", "mace", "spear", "rapier", "dagger"]
	var type_names = ["Sword", "Axe", "Mace", "Spear", "Rapier", "Dagger"]
	var type_index = randi() % weapon_types.size()

	weapon.weapon_type = weapon_types[type_index]

	var prefixes = ["Sharp", "Keen", "Heavy", "Light", "Ancient", "Rusty"]
	weapon.weapon_name = prefixes[randi() % prefixes.size()] + " " + type_names[type_index]

	# Scale with player level
	weapon.base_damage = 5.0 + player_level * 0.8
	weapon.attack_speed_bonus = randf_range(-0.1, 0.1)
	weapon.crit_chance_bonus = randf_range(0, 0.05)

	# Random rarity
	var rarity_roll = randf()
	if rarity_roll < 0.5:
		weapon.rarity = Rarity.COMMON
	elif rarity_roll < 0.8:
		weapon.rarity = Rarity.UNCOMMON
	elif rarity_roll < 0.95:
		weapon.rarity = Rarity.RARE
	else:
		weapon.rarity = Rarity.EPIC

	weapon.required_level = max(1, player_level - 2)
	weapon.can_trade = true

	return weapon
