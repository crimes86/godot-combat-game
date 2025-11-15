extends LPCAnimationDataBase
class_name CharacterAnimationData

## Custom animation data for character body parts with standard LPC sprite sets
## Includes walk, idle (from walk), slash, and hurt animations

func _init():
	resource_name = "CharacterAnimationData"
	_setup_data()

func _setup_data() -> void:
	base_animation_size = 64

	# Only the animations we actually have sprite files for
	available_animations = [
		"walk",
		"idle",
		"slash",
		"hurt"
	]

	required_spritesheets = {
		"walk": "standard/walk",
		"idle": "standard/walk",  # Idle uses walk sprite
		"slash": "standard/slash",
		"hurt": "standard/hurt"
	}

	available_directions = {
		"walk": {"north": 0, "west": 1, "south": 2, "east": 3},
		"idle": {"north": 0, "west": 1, "south": 2, "east": 3},
		"slash": {"north": 0, "west": 1, "south": 2, "east": 3},
		"hurt": {"north": 0, "west": 1, "south": 2, "east": 3}
	}

	animation_frame_counts = {
		"walk": 9,
		"idle": 2,  # Use first 2 frames of walk
		"slash": 6,
		"hurt": 6
	}

	initial_sprite_indices = {
		"walk": 1,  # Walk starts at frame 1
		"idle": 0,  # Idle starts at frame 0
		"slash": 0,
		"hurt": 0
	}

	animation_loops = {
		"walk": true,
		"idle": true,
		"slash": false,  # Don't loop attacks
		"hurt": false   # Don't loop hurt
	}

	animation_speeds = {
		"walk": 8,
		"idle": 4,  # Slower for idle
		"slash": 12,
		"hurt": 10
	}

	animation_rows = {
		"walk": 0,
		"idle": 0,
		"slash": 0,
		"hurt": 0
	}

	frame_sizes = {
		"walk": 64,
		"idle": 64,
		"slash": 64,
		"hurt": 64
	}

	custom_frames = {
		"walk": [1, 2, 3, 4, 5, 6, 7, 8],  # Skip frame 0
		"idle": [0, 0, 1]  # Hold first frame, then second
	}
