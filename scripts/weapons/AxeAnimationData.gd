extends Resource
class_name AxeAnimationData

## Animation data for axe weapons
## Slower, heavier attacks - emphasis on power over speed

# Animation FPS values
var slash_fps: float = 40.0  # Slower than sword (6 frames = 0.15s)
var walk_fps: float = 9.0    # Slightly slower walk
var idle_fps: float = 3.0    # Slower idle for heavy weapon

# Visual feel
var weapon_type_name: String = "Axe"
var animation_style: String = "heavy"  # Heavy, deliberate strikes

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
