extends Resource
class_name RapierAnimationData

## Animation data for rapier weapons
## Very fast, precise strikes - emphasis on finesse

# Animation FPS values
var slash_fps: float = 75.0  # Faster than sword, close to dagger (6 frames = 0.08s)
var walk_fps: float = 11.5   # Quick, agile movements
var idle_fps: float = 5.5    # Poised, ready stance

# Visual feel
var weapon_type_name: String = "Rapier"
var animation_style: String = "precise"  # Fast, precise thrusts

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
