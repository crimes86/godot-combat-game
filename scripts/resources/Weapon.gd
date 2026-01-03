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
@export var is_two_handed: bool = false  # If true, blocks off-hand slot (shields, etc)

# ============================================
# COMBAT STATS
# ============================================

@export var base_damage: float = 5.0  # Average damage (for backwards compatibility)
@export var damage_min: float = 0.0  # Minimum damage (0 = use base_damage)
@export var damage_max: float = 0.0  # Maximum damage (0 = use base_damage)
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
@export var gun_range: float = 550.0  # Maximum shooting distance from player
@export var gun_subtype: String = "railgun"  # "railgun", "battle_rifle", "pistol", "shotgun"
@export var burst_count: int = 1  # Shots per burst (1 = single shot, 3 = battle rifle burst)
@export var burst_delay: float = 0.10  # Delay between burst shots in seconds

# ============================================
# BOW PROPERTIES (for bow/crossbow weapons)
# ============================================

@export var bow_radius: float = 32.0  # Targeting reticle radius (slightly larger than gun)
@export var bow_range: float = 450.0  # Maximum arrow travel distance
@export var arrow_speed: float = 600.0  # Arrow travel speed in pixels/second

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
# FORGED WEAPON STATS (Combat Biography)
# ============================================

@export var is_forged: bool = false  # True for forged weapons from achievements
@export var forged_id: String = ""   # Unique ID for forged item (token_id or item_id)
var weapon_stats: WeaponStats = null  # Combat stats tracker (loaded separately)

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
	"""Returns total damage including artifact and forged weapon bonuses"""
	var damage = base_damage

	# Artifact scaling (legacy)
	if is_artifact:
		damage += artifact_level * 2.0

	# Forged weapon level multiplier (percentage-based scaling)
	if is_forged and weapon_stats:
		damage = damage * weapon_stats.get_damage_multiplier()

	return damage

func get_damage_range() -> Dictionary:
	"""Returns damage min/max as a dictionary. Uses base_damage as fallback if range not set."""
	var dmg_min = damage_min if damage_min > 0 else base_damage
	var dmg_max = damage_max if damage_max > 0 else base_damage

	# Apply forged weapon level multiplier if applicable
	if is_forged and weapon_stats:
		var mult = weapon_stats.get_damage_multiplier()
		dmg_min = dmg_min * mult
		dmg_max = dmg_max * mult

	# Artifact scaling
	if is_artifact:
		dmg_min += artifact_level * 2.0
		dmg_max += artifact_level * 2.0

	return {"min": dmg_min, "max": dmg_max}

func get_damage_display() -> String:
	"""Returns formatted damage string for tooltips (e.g., '18-21' or '5.0' if no range)"""
	var range_data = get_damage_range()
	if range_data.min == range_data.max:
		return "%.1f" % range_data.min
	else:
		# Show as integers if both are whole numbers, otherwise show decimals
		if range_data.min == int(range_data.min) and range_data.max == int(range_data.max):
			return "%d-%d" % [int(range_data.min), int(range_data.max)]
		else:
			return "%.1f-%.1f" % [range_data.min, range_data.max]

func get_forged_crit_bonus() -> float:
	"""DEPRECATED: Crit chance now comes purely from Luck stat, not weapons.
	Returns 0.0 for backwards compatibility."""
	return 0.0

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
	return attack_mode in ["ranged_heal", "ranged_damage"] or is_bow_weapon() or is_gun_weapon()

func is_gun_weapon() -> bool:
	"""Check if this weapon is a gun (ranged damage with precision targeting)"""
	# Exclude bows from gun check even if they have ranged_damage attack_mode
	if is_bow_weapon():
		return false
	return weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle"] or attack_mode == "ranged_damage"

func is_bow_weapon() -> bool:
	"""Check if this weapon is a bow or crossbow"""
	return weapon_type in ["bow", "crossbow"]

func is_burst_weapon() -> bool:
	"""Check if this weapon fires in bursts (e.g., battle rifle 3-round burst)"""
	return burst_count > 1

func get_display_name() -> String:
	"""Returns formatted display name with level"""
	if is_forged and weapon_stats and weapon_stats.level > 0:
		return "%s [Lv. %d]" % [weapon_name, weapon_stats.level]
	if is_artifact and artifact_level > 0:
		return "%s [Lvl %d]" % [weapon_name, artifact_level]
	return weapon_name

func can_equip(player_level: int) -> bool:
	"""Check if player can equip this weapon"""
	return player_level >= required_level

func get_tooltip_text() -> String:
	"""Generate tooltip text for UI"""
	var text = "[b]%s[/b]\n" % get_display_name()
	text += "[color=#888888]%s[/color]" % get_rarity_name()

	# Forged weapon visual tier
	if is_forged and weapon_stats:
		text += " · %s" % weapon_stats.get_visual_tier_name()
	text += "\n\n"

	if is_healing_weapon():
		text += "Healing: +%.1f\n" % get_total_healing()
		text += "Heal Radius: %.0f\n" % heal_radius
	else:
		text += "Damage: +%s\n" % get_damage_display()

	if attack_speed_bonus != 0:
		var speed_text = "faster" if attack_speed_bonus < 0 else "slower"
		text += "Attack Speed: %.0f%% %s\n" % [abs(attack_speed_bonus) * 100, speed_text]

	# Crit chance removed from weapons - now comes purely from Luck stat

	# Forged weapon stats (quick tooltip version)
	if is_forged and weapon_stats:
		if weapon_stats.is_virgin():
			text += "\n[color=gold]✧ PRISTINE ✧[/color]\n"
			text += "[i]Never drawn in battle[/i]\n"
		else:
			text += "\n%s kills" % _format_number(weapon_stats.kills_total)
			if weapon_stats.get_crit_rate_lifetime() > 0:
				text += " · %.1f%% crit" % weapon_stats.get_crit_rate_lifetime()
			text += "\n"
			# Show top 2 achievement icons
			if weapon_stats.achievements.size() > 0:
				var icons = ""
				var count = mini(weapon_stats.achievements.size(), 2)
				for i in range(count):
					icons += weapon_stats.get_achievement_icon(weapon_stats.achievements[i])
				text += icons + "\n"
		text += "\n[color=#666666][Right-click to inspect][/color]\n"

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

func _format_number(num: int) -> String:
	"""Format large numbers with commas"""
	var s = str(num)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

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
			weapon.artifact_traits = ["Chain Master", "Thunder Strike", "Lightning Speed"]
		"steam":
			weapon.weapon_name = "Achievement Hunter's Blade"
			weapon.description = "For those who've seen it all."
			weapon.base_damage = 20.0
			weapon.attack_speed_bonus = -0.20
			weapon.artifact_traits = ["Completionist", "Boss Slayer", "Speed Runner"]
		"psn":
			weapon.weapon_name = "Trophy Collector's Edge"
			weapon.description = "Platinum-forged excellence."
			weapon.base_damage = 22.0
			weapon.attack_speed_bonus = -0.25
			weapon.artifact_traits = ["Trophy Master", "Platinum Touch"]
		"xbox":
			weapon.weapon_name = "Gamerscore Legend"
			weapon.description = "Achievement unlocked: Ultimate Warrior."
			weapon.base_damage = 23.0
			weapon.attack_speed_bonus = -0.22
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
	# Crit chance removed - comes purely from Luck stat

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
