class_name WeaponAnimationData
extends RefCounted
## Consolidated weapon animation and combat data
## Add new weapon types by adding an entry to WEAPON_DATA

# Base attack range (default for unarmed/sword)
const BASE_ATTACK_RANGE: float = 100.0

# Animation and combat data for all weapon types
# Format: { "slash_fps": float, "walk_fps": float, "idle_fps": float, "style": String, "range_mult": float }
# range_mult: Multiplier for attack range (1.0 = base 100px)
const WEAPON_DATA = {
	"unarmed": {
		"slash_fps": 30.0,
		"walk_fps": 10.0,
		"idle_fps": 4.0,
		"style": "brawling",
		"range_mult": 0.7  # Short range (70px)
	},
	"sword": {
		"slash_fps": 30.0,  # Balanced (9 frames = 0.3s)
		"walk_fps": 10.0,
		"idle_fps": 4.0,
		"style": "balanced",
		"range_mult": 1.0  # Standard range (100px)
	},
	"dagger": {
		"slash_fps": 80.0,  # Ultra-fast (6 frames = 0.075s)
		"walk_fps": 12.0,
		"idle_fps": 5.0,
		"style": "fast",
		"range_mult": 0.75  # Short range (75px)
	},
	"axe": {
		"slash_fps": 40.0,  # Heavy, slow (6 frames = 0.15s)
		"walk_fps": 9.0,
		"idle_fps": 3.0,
		"style": "heavy",
		"range_mult": 1.1  # Slightly longer (110px)
	},
	"mace": {
		"slash_fps": 25.0,  # Crushing (9 frames = 0.36s)
		"walk_fps": 9.5,
		"idle_fps": 3.5,
		"style": "crushing",
		"range_mult": 1.0  # Standard range (100px)
	},
	"spear": {
		"slash_fps": 15.0,  # Thrusting (8 frames = 0.53s)
		"walk_fps": 10.5,
		"idle_fps": 4.5,
		"style": "thrusting",
		"range_mult": 1.4  # Long reach (140px)
	},
	"rapier": {
		"slash_fps": 75.0,  # Precise, fast (6 frames = 0.08s)
		"walk_fps": 11.5,
		"idle_fps": 5.5,
		"style": "precise",
		"range_mult": 1.15  # Slightly longer (115px)
	},
	"staff": {
		"slash_fps": 14.0,  # Casting (8 frames = 0.57s)
		"walk_fps": 10.0,
		"idle_fps": 4.0,
		"style": "casting",
		"range_mult": 1.25  # Medium-long reach (125px)
	},
}

# Aliases for weapon types that share animation data
const WEAPON_ALIASES = {
	"club": "mace",
	"hammer": "mace",
}

static func get_data(weapon_type: String) -> Dictionary:
	"""Get animation data for a weapon type"""
	var type_lower = weapon_type.to_lower()

	# Check aliases first
	if WEAPON_ALIASES.has(type_lower):
		type_lower = WEAPON_ALIASES[type_lower]

	if WEAPON_DATA.has(type_lower):
		return WEAPON_DATA[type_lower]

	# Default to sword
	push_warning("Unknown weapon type '%s', defaulting to sword animation data" % weapon_type)
	return WEAPON_DATA["sword"]

static func get_slash_fps(weapon_type: String) -> float:
	return get_data(weapon_type).get("slash_fps", 30.0)

static func get_walk_fps(weapon_type: String) -> float:
	return get_data(weapon_type).get("walk_fps", 10.0)

static func get_idle_fps(weapon_type: String) -> float:
	return get_data(weapon_type).get("idle_fps", 4.0)

static func get_style(weapon_type: String) -> String:
	return get_data(weapon_type).get("style", "balanced")

static func get_attack_range(weapon_type: String) -> float:
	"""Get effective attack range for a weapon type"""
	var range_mult = get_data(weapon_type).get("range_mult", 1.0)
	return BASE_ATTACK_RANGE * range_mult

static func get_range_multiplier(weapon_type: String) -> float:
	"""Get range multiplier for a weapon type (useful for UI display)"""
	return get_data(weapon_type).get("range_mult", 1.0)
