extends Resource
class_name DaggerAnimationData

## Animation data for dagger weapons
## Fastest attacks - emphasis on speed and agility

# Animation FPS values
var slash_fps: float = 80.0  # Ultra-fast (6 frames = 0.075s)
var walk_fps: float = 12.0   # Quick movements
var idle_fps: float = 5.0    # Alert idle stance

# Visual feel
var weapon_type_name: String = "Dagger"
var animation_style: String = "fast"  # Quick, nimble strikes

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
