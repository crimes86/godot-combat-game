extends Node
class_name WeaponAnimationDataFactory

## Factory for weapon animation data
## Now uses consolidated WeaponAnimationData instead of individual files

static func get_slash_fps(weapon_type: String) -> float:
	"""Get slash animation FPS for weapon type"""
	return WeaponAnimationData.get_slash_fps(weapon_type)

static func get_walk_fps(weapon_type: String) -> float:
	"""Get walk animation FPS for weapon type"""
	return WeaponAnimationData.get_walk_fps(weapon_type)

static func get_idle_fps(weapon_type: String) -> float:
	"""Get idle animation FPS for weapon type"""
	return WeaponAnimationData.get_idle_fps(weapon_type)

static func get_style(weapon_type: String) -> String:
	"""Get animation style for weapon type"""
	return WeaponAnimationData.get_style(weapon_type)

# Legacy method for backwards compatibility
static func get_animation_data_for_weapon_type(weapon_type: String) -> Dictionary:
	"""Returns animation data dictionary for the given weapon type."""
	return WeaponAnimationData.get_data(weapon_type)
