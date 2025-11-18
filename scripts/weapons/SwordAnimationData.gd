extends Resource
class_name SwordAnimationData

## Animation data for sword weapons
## Balanced attack speed - standard baseline

# Animation FPS values
var slash_fps: float = 60.0  # Ultra-fast for max AGI spam (6 frames = 0.1s)
var walk_fps: float = 10.0   # Normal walk speed
var idle_fps: float = 4.0    # Slow idle

# Visual feel
var weapon_type_name: String = "Sword"
var animation_style: String = "balanced"  # balanced, fast, heavy

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
