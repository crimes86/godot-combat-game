extends Resource
class_name MaceAnimationData

## Animation data for mace/club weapons
## Similar to axe but slightly faster - crushing blows

# Animation FPS values
var slash_fps: float = 25.0  # Slower than sword for heavy crushing feel (9 frames = 0.36s)
var walk_fps: float = 9.5    # Moderate walk speed
var idle_fps: float = 3.5    # Steady idle

# Visual feel
var weapon_type_name: String = "Mace"
var animation_style: String = "crushing"  # Heavy but slightly faster than axe

func get_slash_fps() -> float:
	return slash_fps

func get_walk_fps() -> float:
	return walk_fps

func get_idle_fps() -> float:
	return idle_fps
