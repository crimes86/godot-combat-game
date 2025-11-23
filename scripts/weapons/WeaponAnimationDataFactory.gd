extends Node
class_name WeaponAnimationDataFactory

## Factory for creating weapon-specific animation data
## Maps weapon types to their animation configurations

static func get_animation_data_for_weapon_type(weapon_type: String) -> Resource:
	"""
	Returns animation data resource for the given weapon type.
	Falls back to sword data if weapon type not found.

	Supported weapon types:
	- sword (balanced)
	- axe (heavy, slow)
	- mace (heavy, crushing - slightly faster than axe)
	- spear (medium speed, thrusting attacks)
	- rapier (very fast, precise)
	- dagger (fastest, nimble)
	"""
	match weapon_type.to_lower():
		"sword":
			return SwordAnimationData.new()
		"axe":
			return AxeAnimationData.new()
		"mace", "club", "hammer":  # Maces, clubs, and hammers use same data
			return MaceAnimationData.new()
		"spear":
			return SpearAnimationData.new()
		"rapier":
			return RapierAnimationData.new()
		"dagger":
			return DaggerAnimationData.new()
		_:
			# Default to sword for unknown weapon types
			push_warning("Unknown weapon type '%s', defaulting to sword animation data" % weapon_type)
			return SwordAnimationData.new()

static func get_slash_fps(weapon_type: String) -> float:
	"""Quick accessor for slash FPS"""
	var data = get_animation_data_for_weapon_type(weapon_type)
	return data.get_slash_fps()

static func get_walk_fps(weapon_type: String) -> float:
	"""Quick accessor for walk FPS"""
	var data = get_animation_data_for_weapon_type(weapon_type)
	return data.get_walk_fps()

static func get_idle_fps(weapon_type: String) -> float:
	"""Quick accessor for idle FPS"""
	var data = get_animation_data_for_weapon_type(weapon_type)
	return data.get_idle_fps()
