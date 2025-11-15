extends LPCAnimationDataBase
class_name WeaponAnimationData

## Custom animation data for weapons with limited sprite sets
## Only includes walk and slash_oversize animations

func _init():
	resource_name = "WeaponAnimationData"
	_setup_data()

func _setup_data() -> void:
	base_animation_size = 64

	# Only the animations we actually have sprite files for
	available_animations = [
		"walk",
		"idle",
		"slash_oversize"
	]

	required_spritesheets = {
		"walk": "standard/walk",
		"idle": "standard/walk",  # Idle uses walk sprite
		"slash_oversize": "custom/slash_oversize"
	}

	available_directions = {
		"walk": {"north": 0, "west": 1, "south": 2, "east": 3},
		"idle": {"north": 0, "west": 1, "south": 2, "east": 3},
		"slash_oversize": {"north": 0, "west": 1, "south": 2, "east": 3}
	}

	animation_frame_counts = {
		"walk": 9,
		"idle": 1,  # Just one frame (standing pose)
		"slash_oversize": 6
	}

	initial_sprite_indices = {
		"walk": 1,  # Walk starts at frame 1
		"idle": 0,  # Idle starts at frame 0
		"slash_oversize": 0
	}

	animation_loops = {
		"walk": true,
		"idle": true,
		"slash_oversize": false
	}

	animation_speeds = {
		"walk": 8,
		"idle": 4,  # Slower for idle
		"slash_oversize": 12
	}

	animation_rows = {
		"walk": 0,
		"idle": 0,
		"slash_oversize": 0
	}

	frame_sizes = {
		"walk": 64,
		"idle": 64,
		"slash_oversize": 192  # Oversize weapon frames
	}

	custom_frames = {
		"walk": [1, 2, 3, 4, 5, 6, 7, 8],  # Skip frame 0
		"idle": [0]  # Just standing pose, no stepping!
	}
