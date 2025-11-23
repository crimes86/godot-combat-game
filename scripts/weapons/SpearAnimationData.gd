extends Resource
class_name SpearAnimationData

## Animation data for spear weapons
## Medium speed with longer reach - thrust attacks

# Animation FPS values
var slash_fps: float = 55.0  # Between sword and dagger (6 frames = 0.109s)
var walk_fps: float = 10.5   # Slightly faster walk
var idle_fps: float = 4.5    # Alert stance with ready spear

# Visual feel
var weapon_type_name: String = "Spear"
var animation_style: String = "thrusting"  # Quick thrusts, good reach

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
