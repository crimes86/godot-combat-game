extends CanvasLayer

## Campfire Direction Indicator
## Shows a subtle arrow pointing toward the campfire when player is far away
## Fades in at 500+ units, fully visible at 1000+ units

const CAMPFIRE_POSITION: Vector2 = Vector2(2230, -1351)  # Ruins campfire location
const MIN_DISTANCE: float = 500.0   # Start showing indicator
const MAX_DISTANCE: float = 1000.0  # Fully opaque at this distance

var arrow: Polygon2D = null
var player: CharacterBody2D = null

func _ready() -> void:
	print("🧭 CampfireIndicator._ready() started")

	# Set layer for UI
	layer = 90  # Below inventory (100) but above game

	# Create arrow indicator
	create_arrow_indicator()

	print("🧭 CampfireIndicator._ready() COMPLETED")

func create_arrow_indicator() -> void:
	"""Create a simple arrow shape pointing toward campfire"""

	# Control container to position arrow
	var control = Control.new()
	control.name = "ArrowControl"
	control.set_anchors_preset(Control.PRESET_CENTER)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control)

	# Create arrow polygon (pointing right by default)
	arrow = Polygon2D.new()
	arrow.name = "Arrow"

	# Arrow shape (triangle pointing right)
	var arrow_points = PackedVector2Array([
		Vector2(0, -12),      # Top point
		Vector2(20, 0),       # Right tip
		Vector2(0, 12),       # Bottom point
		Vector2(4, 0)         # Left indent (to make it arrow-like)
	])
	arrow.polygon = arrow_points

	# Subtle orange/gold color (campfire-like)
	arrow.color = Color(1.0, 0.7, 0.3, 0.0)  # Start invisible

	# Add outline for visibility
	# Note: Polygon2D doesn't have outline, so we'll just use solid color

	control.add_child(arrow)

	print("  🧭 Arrow indicator created")

func _physics_process(_delta: float) -> void:
	"""Update arrow position and rotation to point toward campfire"""

	if not arrow:
		return

	# Find player if needed
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if not player:
			arrow.color.a = 0.0  # Hide if no player
			return

	# Calculate distance to campfire
	var player_pos = player.global_position
	var direction_to_campfire = (CAMPFIRE_POSITION - player_pos).normalized()
	var distance = player_pos.distance_to(CAMPFIRE_POSITION)

	# Determine visibility based on distance
	var alpha = 0.0
	if distance > MIN_DISTANCE:
		# Fade in between MIN_DISTANCE and MAX_DISTANCE
		var fade_progress = clamp((distance - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE), 0.0, 1.0)
		alpha = lerp(0.0, 0.7, fade_progress)  # Max 70% opacity for subtlety

	# Update arrow opacity
	arrow.color.a = alpha

	# Only update position/rotation if visible
	if alpha > 0.0:
		# Calculate angle to campfire
		var angle = direction_to_campfire.angle()
		arrow.rotation = angle

		# Position arrow at edge of screen pointing toward campfire
		var viewport_size = get_viewport().get_visible_rect().size
		var screen_center = viewport_size / 2

		# Get camera zoom to adjust position
		var camera = get_viewport().get_camera_2d()
		var zoom_factor = 1.0
		if camera:
			zoom_factor = camera.zoom.x

		# Place arrow at screen edge (adjusted for zoom)
		var edge_distance = 80.0  # Distance from screen edge
		var arrow_screen_pos = screen_center + direction_to_campfire * (min(viewport_size.x, viewport_size.y) / 2 - edge_distance)

		# Update arrow control position
		var control = arrow.get_parent() as Control
		if control:
			control.position = arrow_screen_pos
