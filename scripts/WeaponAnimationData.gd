extends LPCAnimationDataBase
class_name WeaponAnimationData

## Custom animation data for weapons with limited sprite sets
## Only includes idle and slash_oversize (no walk - sprite incomplete)

func _init():
	resource_name = "WeaponAnimationData"
	_setup_data()

func _setup_data() -> void:
	base_animation_size = 64

	# Only idle and slash - walk sprite only has 1 row, not 4!
	# TODO: Get proper 4-row walk sprite from LPC generator
	available_animations = [
		"idle",
		"slash_oversize"
	]

	required_spritesheets = {
		"idle": "custom/slash_oversize",  # Use first frame of slash for idle
		"slash_oversize": "custom/slash_oversize"
	}

	available_directions = {
		"idle": {"north": 0, "west": 1, "south": 2, "east": 3},
		"slash_oversize": {"north": 0, "west": 1, "south": 2, "east": 3}
	}

	animation_frame_counts = {
		"idle": 1,  # Just one frame (standing pose)
		"slash_oversize": 6
	}

	initial_sprite_indices = {
		"idle": 0,  # Idle starts at frame 0
		"slash_oversize": 0
	}

	animation_loops = {
		"idle": true,
		"slash_oversize": false
	}

	animation_speeds = {
		"idle": 4,
		"slash_oversize": 60  # Ultra-fast for max AGI spam (6 frames = 0.1s)
	}

	animation_rows = {
		"idle": 0,
		"slash_oversize": 0
	}

	frame_sizes = {
		"idle": 192,  # Use slash sprite (192px frames)
		"slash_oversize": 192
	}

	custom_frames = {
		"idle": [0]  # Just standing pose from slash sprite
	}
