extends Node2D

## Animates lava pool gradient layers to create pulsing/flowing effect
## Attach to lava pool nodes to make them look alive

var layer_nodes = []  # Store references to polygon layers
var layer_speeds = []  # Pulse speed for each layer
var layer_offsets = []  # Phase offset for each layer
var time_offset = 0.0  # Random offset so pools don't sync

# Performance: throttle updates
var update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.1  # Update 10 times per second instead of 60

func _ready():
	# Add random time offset so each pool flows differently
	time_offset = randf() * TAU

	# Find all Polygon2D children (borders + gradient layers)
	# NEW ORDER:
	# Borders: 0 (outer), 1 (middle), 2 (inner)
	# Gradient layers: 3-12 (10 layers)
	var polygon_children = []
	for child in get_children():
		if child is Polygon2D:
			polygon_children.append(child)

	# Animate the 10 gradient layers with pulsing effect
	if polygon_children.size() >= 13:  # 3 borders + 10 gradient layers
		for i in range(3, 13):  # Indices 3-12 are the gradient layers
			layer_nodes.append(polygon_children[i])

			# Inner (hotter) layers pulse faster than outer (cooler) layers
			# Layer 0 (outermost) = slowest, Layer 9 (innermost) = fastest
			var layer_index = i - 3  # 0-9
			var base_speed = 0.5 + (layer_index * 0.08)  # 0.5 to 1.22 Hz

			# Add randomness ±20% to make each pool unique
			var speed = base_speed * randf_range(0.8, 1.2)
			layer_speeds.append(speed)

			# Random phase offset so layers don't pulse in sync
			layer_offsets.append(randf() * TAU)

func _process(delta):
	# Throttle updates - lava animation doesn't need 60 FPS
	update_timer += delta
	if update_timer < UPDATE_INTERVAL:
		return
	update_timer = 0.0

	var time = Time.get_ticks_msec() / 1000.0 + time_offset

	# Pulse each gradient layer by scaling it slightly
	for i in range(layer_nodes.size()):
		if layer_nodes[i]:
			# Create a sine wave pulse between 0.97 and 1.03 (subtle 3% variation)
			var pulse = 1.0 + sin(time * layer_speeds[i] + layer_offsets[i]) * 0.03
			layer_nodes[i].scale = Vector2(pulse, pulse)
