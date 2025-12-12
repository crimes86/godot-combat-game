extends RefCounted
class_name WeaponVisualEvolution

## Calculates visual effects based on weapon stats and theme.
## Weapons visually evolve as they level up and earn achievements.
## Virgin weapons have subtle effects; mythic weapons have dramatic presence.

# ============================================
# EVOLUTION TIERS
# ============================================

enum EvolutionTier {
	VIRGIN,      # Level 0, 0 kills - minimal effects
	BLOODED,     # Level 1-10, 1+ kills - first awakening
	VETERAN,     # Level 11-25, 100+ kills - growing power
	BATTLE_WORN, # Level 26-40, 1000+ kills - significant presence
	LEGENDARY,   # Level 41-60, 10000+ kills - unmistakable power
	MYTHIC       # Level 61+, 50000+ kills - godlike presence
}

# ============================================
# THEME-SPECIFIC EFFECT PATHS
# ============================================

# Each theme has a progression of effects from tier 0 to tier 5
const THEME_EFFECTS = {
	"dark_souls": {
		EvolutionTier.VIRGIN: ["ember_glow"],
		EvolutionTier.BLOODED: ["ember_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["ember_glow", "ember_trail", "heat_distortion"],
		EvolutionTier.BATTLE_WORN: ["flame_idle_glow", "ember_trail", "standard_particles"],
		EvolutionTier.LEGENDARY: ["flame_idle_glow", "ember_trail", "heat_distortion", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["flame_idle_glow", "ember_trail", "heat_distortion", "exceptional_aura", "storm_particles"]
	},
	"elden_ring": {
		EvolutionTier.VIRGIN: ["golden_sparkle"],
		EvolutionTier.BLOODED: ["golden_sparkle", "standard_particles"],
		EvolutionTier.VETERAN: ["erdtree_blessing", "stardust_trail"],
		EvolutionTier.BATTLE_WORN: ["erdtree_blessing", "moonlight_aura", "golden_leaves"],
		EvolutionTier.LEGENDARY: ["erdtree_blessing", "moonlight_aura", "gravity_particles", "light_rays"],
		EvolutionTier.MYTHIC: ["erdtree_blessing", "moonlight_aura", "gravity_particles", "light_rays", "exceptional_aura"]
	},
	"hollow_knight": {
		EvolutionTier.VIRGIN: ["void_aura"],
		EvolutionTier.BLOODED: ["void_particles"],
		EvolutionTier.VETERAN: ["void_trail", "void_particles"],
		EvolutionTier.BATTLE_WORN: ["void_aura", "shadow_tendrils", "void_trail"],
		EvolutionTier.LEGENDARY: ["void_aura", "shadow_tendrils", "dark_burst", "shadow_dash"],
		EvolutionTier.MYTHIC: ["void_aura", "shadow_tendrils", "dark_burst", "shadow_dash", "exceptional_aura"]
	},
	"hades": {
		EvolutionTier.VIRGIN: ["blood_red_glow"],
		EvolutionTier.BLOODED: ["blood_red_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["infernal_glow", "underworld_flame"],
		EvolutionTier.BATTLE_WORN: ["infernal_glow", "underworld_flame", "laurel_particles"],
		EvolutionTier.LEGENDARY: ["divine_glow", "underworld_flame", "laurel_particles", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["divine_glow", "underworld_flame", "laurel_particles", "exceptional_aura", "arcane_burst"]
	},
	"stardew": {
		EvolutionTier.VIRGIN: ["pixel_sparkle"],
		EvolutionTier.BLOODED: ["nature_sparkle"],
		EvolutionTier.VETERAN: ["nature_sparkle", "retro_trail"],
		EvolutionTier.BATTLE_WORN: ["nature_sparkle", "stardust_trail", "healing_aura"],
		EvolutionTier.LEGENDARY: ["golden_sparkle", "stardust_trail", "healing_aura", "flower_petals"],
		EvolutionTier.MYTHIC: ["golden_sparkle", "stardust_trail", "healing_aura", "flower_petals", "light_rays"]
	},
	"terraria": {
		EvolutionTier.VIRGIN: ["green_glow"],
		EvolutionTier.BLOODED: ["green_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["green_glow", "terra_beam"],
		EvolutionTier.BATTLE_WORN: ["terra_beam", "sword_projectile", "eerie_glow"],
		EvolutionTier.LEGENDARY: ["terra_beam", "sword_projectile", "eerie_glow", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["terra_beam", "sword_projectile", "eerie_glow", "exceptional_aura", "light_rays"]
	},
	"sekiro": {
		EvolutionTier.VIRGIN: ["blood_red_glow"],
		EvolutionTier.BLOODED: ["crimson_slash"],
		EvolutionTier.VETERAN: ["crimson_slash", "blood_mist"],
		EvolutionTier.BATTLE_WORN: ["crimson_slash", "blood_mist", "death_kanji"],
		EvolutionTier.LEGENDARY: ["crimson_slash", "blood_mist", "death_kanji", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["crimson_slash", "blood_mist", "death_kanji", "exceptional_aura", "scarlet_rot_trail"]
	},
	"witcher": {
		EvolutionTier.VIRGIN: ["silver_gleam"],
		EvolutionTier.BLOODED: ["silver_gleam", "standard_particles"],
		EvolutionTier.VETERAN: ["wolf_school_glow", "standard_particles"],
		EvolutionTier.BATTLE_WORN: ["wolf_school_glow", "danger_sense", "superior_trail"],
		EvolutionTier.LEGENDARY: ["wolf_school_glow", "danger_sense", "superior_trail", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["wolf_school_glow", "danger_sense", "superior_trail", "exceptional_aura", "moonlight_aura"]
	},
	"halo": {
		EvolutionTier.VIRGIN: ["tactical_glow"],
		EvolutionTier.BLOODED: ["tactical_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["enhanced_glow", "standard_particles"],
		EvolutionTier.BATTLE_WORN: ["enhanced_glow", "superior_trail", "standard_particles"],
		EvolutionTier.LEGENDARY: ["enhanced_glow", "superior_trail", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["enhanced_glow", "superior_trail", "exceptional_aura", "light_rays"]
	},
	"discord": {
		EvolutionTier.VIRGIN: ["purple_glow"],
		EvolutionTier.BLOODED: ["discord_sparkle"],
		EvolutionTier.VETERAN: ["discord_sparkle", "purple_glow"],
		EvolutionTier.BATTLE_WORN: ["discord_sparkle", "purple_glow", "superior_trail"],
		EvolutionTier.LEGENDARY: ["discord_sparkle", "purple_glow", "superior_trail", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["discord_sparkle", "purple_glow", "superior_trail", "exceptional_aura", "arcane_burst"]
	},
	"github": {
		EvolutionTier.VIRGIN: ["green_glow"],
		EvolutionTier.BLOODED: ["green_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["green_glow", "nature_sparkle"],
		EvolutionTier.BATTLE_WORN: ["green_glow", "nature_sparkle", "superior_trail"],
		EvolutionTier.LEGENDARY: ["green_glow", "nature_sparkle", "superior_trail", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["green_glow", "nature_sparkle", "superior_trail", "exceptional_aura", "light_rays"]
	},
	"generic": {
		EvolutionTier.VIRGIN: ["enhanced_glow"],
		EvolutionTier.BLOODED: ["enhanced_glow", "standard_particles"],
		EvolutionTier.VETERAN: ["enhanced_glow", "superior_trail"],
		EvolutionTier.BATTLE_WORN: ["enhanced_glow", "superior_trail", "standard_particles"],
		EvolutionTier.LEGENDARY: ["enhanced_glow", "superior_trail", "exceptional_aura"],
		EvolutionTier.MYTHIC: ["enhanced_glow", "superior_trail", "exceptional_aura", "light_rays"]
	}
}

# ============================================
# INTENSITY SCALING
# ============================================

const TIER_INTENSITY = {
	EvolutionTier.VIRGIN: 0.2,      # Barely visible
	EvolutionTier.BLOODED: 0.5,     # Subtle
	EvolutionTier.VETERAN: 0.75,    # Noticeable
	EvolutionTier.BATTLE_WORN: 1.0, # Full
	EvolutionTier.LEGENDARY: 1.25,  # Enhanced
	EvolutionTier.MYTHIC: 1.5       # Maximum
}

const TIER_PARTICLE_MULTIPLIER = {
	EvolutionTier.VIRGIN: 0.0,      # No particles
	EvolutionTier.BLOODED: 0.3,     # Sparse
	EvolutionTier.VETERAN: 0.6,     # Moderate
	EvolutionTier.BATTLE_WORN: 1.0, # Full
	EvolutionTier.LEGENDARY: 1.5,   # Dense
	EvolutionTier.MYTHIC: 2.0       # Overwhelming
}

# ============================================
# ACHIEVEMENT EFFECTS
# ============================================

# Special effects unlocked by per-weapon achievements
const ACHIEVEMENT_EFFECTS = {
	"FIRST_BLOOD": {
		"effect": "blood_drip",
		"description": "Blood drip idle animation"
	},
	"CENTURION": {
		"effect": "centurion_flash",
		"description": "Roman numeral 'C' flash on 100th kill"
	},
	"SLAYER": {
		"effect": "skull_orbit",
		"description": "Tiny skull orbits weapon"
	},
	"LEGEND": {
		"effect": "legend_crown",
		"description": "Crown/halo above weapon"
	},
	"PERFECTIONIST": {
		"effect": "pristine_sparkle",
		"description": "Pristine sparkle overlay"
	},
	"CRIT_MASTER": {
		"effect": "crit_lightning",
		"description": "Lightning crackle on crits"
	},
	"CHAIN_KING": {
		"effect": "chain_orbit",
		"description": "Chain links orbit weapon"
	},
	"OVERKILL": {
		"effect": "overkill_explosion",
		"description": "Explosion particles on kills"
	},
	"VETERAN": {
		"effect": "veteran_patina",
		"description": "Time-worn patina shader"
	}
}

# ============================================
# PUBLIC API
# ============================================

## Calculate evolution tier based on weapon stats
static func get_evolution_tier(stats: WeaponStats) -> EvolutionTier:
	if stats == null or stats.is_virgin():
		return EvolutionTier.VIRGIN

	# Use both level AND kills - whichever gives higher tier
	var level_tier = _tier_from_level(stats.level)
	var kill_tier = _tier_from_kills(stats.kills_total)

	# Return the higher of the two
	return level_tier if level_tier > kill_tier else kill_tier

## Get evolution tier name for display
static func get_tier_name(tier: EvolutionTier) -> String:
	match tier:
		EvolutionTier.VIRGIN: return "VIRGIN"
		EvolutionTier.BLOODED: return "BLOODED"
		EvolutionTier.VETERAN: return "VETERAN"
		EvolutionTier.BATTLE_WORN: return "BATTLE-WORN"
		EvolutionTier.LEGENDARY: return "LEGENDARY"
		EvolutionTier.MYTHIC: return "MYTHIC"
		_: return "UNKNOWN"

## Get complete effect configuration for a weapon
## Returns a dictionary with all visual parameters
static func get_effects_for_weapon(
	weapon_stats: WeaponStats,
	theme: String,
	base_effect: String = ""
) -> Dictionary:
	var result = {
		"effects": [],              # Effect names to apply
		"intensity": 1.0,           # Global intensity multiplier
		"particle_multiplier": 1.0, # Particle count multiplier
		"trail_enabled": false,     # Whether to show trail
		"aura_enabled": false,      # Whether to show aura
		"special_effects": [],      # Achievement-unlocked effects
		"tier": EvolutionTier.VIRGIN,
		"tier_name": "VIRGIN"
	}

	# Handle non-forged or stat-less weapons
	if weapon_stats == null:
		# Return minimal effects based on base_effect if provided
		if base_effect != "":
			result["effects"] = [base_effect]
			result["intensity"] = 0.5
		return result

	var tier = get_evolution_tier(weapon_stats)
	result["tier"] = tier
	result["tier_name"] = get_tier_name(tier)

	# Get theme-specific effects for this tier
	var safe_theme = theme if theme in THEME_EFFECTS else "generic"
	if THEME_EFFECTS[safe_theme].has(tier):
		result["effects"] = THEME_EFFECTS[safe_theme][tier].duplicate()

	# Always include base effect if not already present
	if base_effect != "" and not base_effect in result["effects"]:
		result["effects"].insert(0, base_effect)

	# Set intensity and particle scaling
	result["intensity"] = TIER_INTENSITY.get(tier, 1.0)
	result["particle_multiplier"] = TIER_PARTICLE_MULTIPLIER.get(tier, 1.0)

	# Trail unlocks at tier 2+ (VETERAN)
	result["trail_enabled"] = tier >= EvolutionTier.VETERAN

	# Aura unlocks at tier 3+ (BATTLE_WORN)
	result["aura_enabled"] = tier >= EvolutionTier.BATTLE_WORN

	# Add achievement-based special effects
	result["special_effects"] = _get_achievement_effects(weapon_stats)

	return result

## Get just the intensity multiplier for a tier
static func get_intensity_for_tier(tier: EvolutionTier) -> float:
	return TIER_INTENSITY.get(tier, 1.0)

## Get particle multiplier for a tier
static func get_particle_multiplier_for_tier(tier: EvolutionTier) -> float:
	return TIER_PARTICLE_MULTIPLIER.get(tier, 1.0)

# ============================================
# PRIVATE HELPERS
# ============================================

static func _tier_from_level(level: int) -> EvolutionTier:
	if level <= 0:
		return EvolutionTier.VIRGIN
	elif level <= 10:
		return EvolutionTier.BLOODED
	elif level <= 25:
		return EvolutionTier.VETERAN
	elif level <= 40:
		return EvolutionTier.BATTLE_WORN
	elif level <= 60:
		return EvolutionTier.LEGENDARY
	else:
		return EvolutionTier.MYTHIC

static func _tier_from_kills(kills: int) -> EvolutionTier:
	if kills <= 0:
		return EvolutionTier.VIRGIN
	elif kills < 100:
		return EvolutionTier.BLOODED
	elif kills < 1000:
		return EvolutionTier.VETERAN
	elif kills < 10000:
		return EvolutionTier.BATTLE_WORN
	elif kills < 50000:
		return EvolutionTier.LEGENDARY
	else:
		return EvolutionTier.MYTHIC

static func _get_achievement_effects(stats: WeaponStats) -> Array:
	var effects = []

	if stats.achievements == null:
		return effects

	for achievement in stats.achievements:
		if achievement in ACHIEVEMENT_EFFECTS:
			effects.append(ACHIEVEMENT_EFFECTS[achievement])

	return effects

# ============================================
# DISPLAY HELPERS
# ============================================

## Get a short description of the weapon's evolution state
static func get_evolution_summary(stats: WeaponStats) -> String:
	if stats == null:
		return "Not Forged"

	var tier = get_evolution_tier(stats)
	var tier_name = get_tier_name(tier)

	match tier:
		EvolutionTier.VIRGIN:
			return "PRISTINE - Never used"
		EvolutionTier.BLOODED:
			return "BLOODED - First awakening"
		EvolutionTier.VETERAN:
			return "VETERAN - Battle-tested"
		EvolutionTier.BATTLE_WORN:
			return "BATTLE-WORN - Feared by enemies"
		EvolutionTier.LEGENDARY:
			return "LEGENDARY - Songs sung of this blade"
		EvolutionTier.MYTHIC:
			return "MYTHIC - A weapon that shaped history"
		_:
			return tier_name

## Get color for the evolution tier (for UI)
static func get_tier_color(tier: EvolutionTier) -> Color:
	match tier:
		EvolutionTier.VIRGIN:
			return Color(1.0, 1.0, 1.0, 0.8)  # White/pristine
		EvolutionTier.BLOODED:
			return Color(0.8, 0.2, 0.2, 0.9)  # Blood red
		EvolutionTier.VETERAN:
			return Color(0.6, 0.6, 0.7, 0.9)  # Steel gray
		EvolutionTier.BATTLE_WORN:
			return Color(0.7, 0.5, 0.2, 0.9)  # Battle bronze
		EvolutionTier.LEGENDARY:
			return Color(1.0, 0.8, 0.0, 0.9)  # Golden
		EvolutionTier.MYTHIC:
			return Color(0.8, 0.4, 1.0, 0.9)  # Purple/divine
		_:
			return Color.WHITE
