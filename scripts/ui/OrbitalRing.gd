extends Node2D

signal beat_hit(success: bool)
signal window_ended

# Settings
var num_beats: int = 3
var duration: float = 3.0
var ring_radius: float = 100.0

# Beat tracking
var current_beat: int = 0
var beat_interval: float = 0.0
var marker_angle: float = 0.0  # In radians now for consistency
var target_angle: float = -PI / 2  # -90 degrees = 12 o'clock (top) in radians
var timing_tolerance: float = 0.5  # In radians (about 28 degrees)

# Timer
var elapsed_time: float = 0.0

# Feedback tracking
var beat_results: Array = []
var feedback_label: Label = null

func _ready() -> void:
	# Create feedback label
	feedback_label = Label.new()
	feedback_label.position = Vector2(-50, ring_radius + 30)
	feedback_label.add_theme_font_size_override("font_size", 20)
	add_child(feedback_label)

func setup(beats: int, window_duration: float) -> void:
	num_beats = beats
	duration = window_duration
	beat_interval = duration / num_beats
	beat_results.clear()
	marker_angle = 0  # Start at 3 o'clock
	queue_redraw()

func _process(delta: float) -> void:
	elapsed_time += delta
	
	# Move marker around the ring (full circle per beat interval)
	var progress = fmod(elapsed_time, beat_interval) / beat_interval
	marker_angle = progress * TAU  # TAU = 2*PI = full circle
	
	# Check if we completed this beat's cycle
	if elapsed_time > (current_beat + 1) * beat_interval:
		# Beat window passed without input
		if current_beat < num_beats and beat_results.size() <= current_beat:
			print("Beat ", current_beat + 1, " MISSED (no input)")
			beat_results.append(false)
			beat_hit.emit(false)
			show_feedback(false)
		current_beat += 1
	
	# Check if window is over
	if elapsed_time >= duration:
		window_ended.emit()
		return
	
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible or current_beat >= num_beats:
		return
	
	# Don't allow input if we already recorded this beat
	if beat_results.size() > current_beat:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			check_timing()

func check_timing() -> void:
	# PROTECTION: Ignore clicks on first beat until marker is close to target
	if current_beat == 0 and beat_results.size() == 0:
		# Calculate how far the marker is from the target
		var normalized_marker = fmod(marker_angle, TAU)
		var normalized_target = fmod(target_angle, TAU)
		var angle_diff = abs(normalized_marker - normalized_target)
		if angle_diff > PI:
			angle_diff = TAU - angle_diff
		
		# If marker hasn't reached the target zone yet, ignore the click
		# We'll use a larger "approach zone" for this check
		var approach_tolerance = timing_tolerance * 3.0  # 3x larger protection zone
		if angle_diff > approach_tolerance:
			print("First beat protection: Ignoring early click (marker not close yet)")
			return
	
	# Normal timing check
	var normalized_marker = fmod(marker_angle, TAU)
	var normalized_target = fmod(target_angle, TAU)
	
	# Calculate shortest angular distance
	var angle_diff = abs(normalized_marker - normalized_target)
	if angle_diff > PI:
		angle_diff = TAU - angle_diff
	
	var success = angle_diff < timing_tolerance
	
	# Record result
	beat_results.append(success)
	
	# Show feedback
	show_feedback(success)
	
	var degrees_off = rad_to_deg(angle_diff)
	print("Beat ", current_beat + 1, ": ", "SUCCESS!" if success else "MISSED", " (", snappedf(degrees_off, 0.1), "° off)")
	
	beat_hit.emit(success)
func show_feedback(success: bool) -> void:
	if success:
		modulate = Color(0, 1, 0, 1)  # Flash green
		feedback_label.text = "✓ HIT!"
		feedback_label.modulate = Color(0, 1, 0, 1)
	else:
		modulate = Color(1, 0, 0, 1)  # Flash red
		feedback_label.text = "✗ MISS"
		feedback_label.modulate = Color(1, 0, 0, 1)
	
	await get_tree().create_timer(0.2).timeout
	modulate = Color(1, 1, 1, 1)
	feedback_label.text = ""

func _draw() -> void:
	# Draw main ring
	draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, Color(1, 1, 0, 0.5), 3.0)
	
	# Draw target zone at 12 o'clock - MUCH MORE VISIBLE
	var target_start = target_angle - timing_tolerance
	var target_end = target_angle + timing_tolerance
	
	# Draw thick green arc
	draw_arc(Vector2.ZERO, ring_radius, target_start, target_end, 32, Color(0, 1, 0, 1), 12.0)
	
	# Draw filled green sector for clarity
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(33):
		var angle = lerp(target_start, target_end, float(i) / 32.0)
		points.append(Vector2(cos(angle), sin(angle)) * ring_radius)
	points.append(Vector2.ZERO)
	draw_colored_polygon(points, Color(0, 1, 0, 0.3))
	
	# Draw traveling marker
	var marker_pos = Vector2(cos(marker_angle), sin(marker_angle)) * ring_radius
	draw_circle(marker_pos, 15, Color(1, 1, 1, 1))  # White outer ring
	draw_circle(marker_pos, 12, Color(1, 0.5, 0, 1))  # Orange center
	
	# Draw beat counter
	var counter_text = str(current_beat, "/", num_beats)
	draw_string(ThemeDB.fallback_font, Vector2(-20, -ring_radius - 20), 
		counter_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)
	
	# Draw beat result indicators
	var result_x = -30
	for i in range(beat_results.size()):
		var color = Color(0, 1, 0) if beat_results[i] else Color(1, 0, 0)
		var symbol = "✓" if beat_results[i] else "✗"
		draw_string(ThemeDB.fallback_font, Vector2(result_x, -ring_radius - 5),
			symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)
		result_x += 20
