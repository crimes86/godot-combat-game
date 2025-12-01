class_name WeaponAnimationData
extends RefCounted
## Consolidated weapon animation data
## Add new weapon types by adding an entry to WEAPON_DATA

# Animation data for all weapon types
# Format: { "slash_fps": float, "walk_fps": float, "idle_fps": float, "style": String }
const WEAPON_DATA = {
	"sword": {
		"slash_fps": 30.0,  # Balanced (9 frames = 0.3s)
		"walk_fps": 10.0,
		"idle_fps": 4.0,
		"style": "balanced"
	},
	"dagger": {
		"slash_fps": 80.0,  # Ultra-fast (6 frames = 0.075s)
		"walk_fps": 12.0,
		"idle_fps": 5.0,
		"style": "fast"
	},
	"axe": {
		"slash_fps": 40.0,  # Heavy, slow (6 frames = 0.15s)
		"walk_fps": 9.0,
		"idle_fps": 3.0,
		"style": "heavy"
	},
	"mace": {
		"slash_fps": 25.0,  # Crushing (9 frames = 0.36s)
		"walk_fps": 9.5,
		"idle_fps": 3.5,
		"style": "crushing"
	},
	"spear": {
		"slash_fps": 55.0,  # Thrusting (6 frames = 0.109s)
		"walk_fps": 10.5,
		"idle_fps": 4.5,
		"style": "thrusting"
	},
	"rapier": {
		"slash_fps": 75.0,  # Precise, fast (6 frames = 0.08s)
		"walk_fps": 11.5,
		"idle_fps": 5.5,
		"style": "precise"
	},
	"staff": {
		"slash_fps": 14.0,  # Casting (8 frames = 0.57s)
		"walk_fps": 10.0,
		"idle_fps": 4.0,
		"style": "casting"
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
