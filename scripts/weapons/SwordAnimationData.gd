extends Resource
class_name SwordAnimationData

## Animation data for sword weapons
## Balanced attack speed - standard baseline

# Animation FPS values
var slash_fps: float = 30.0  # Smooth and readable (9 frames with duplicates = 0.3s)
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
