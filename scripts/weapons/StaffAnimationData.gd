extends Resource
class_name StaffAnimationData

## Animation data for staff/healing weapons
## Uses thrust animation (8 frames) - slightly slower casting feel

# Animation FPS values
# Thrust has 8 frames - slower casting feel for staff
var slash_fps: float = 14.0  # 8 frames at 14 FPS = ~0.57s cast time (smooth spell feel)
var walk_fps: float = 10.0   # Normal walk speed
var idle_fps: float = 4.0    # Slow idle

# Visual feel
var weapon_type_name: String = "Staff"
var animation_style: String = "casting"

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
