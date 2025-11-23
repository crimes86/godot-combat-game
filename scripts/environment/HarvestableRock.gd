extends StaticBody2D
class_name HarvestableRock

## Harvestable Rock - Can be mined for ore/stone
## Press F when near to mine the rock
## Drops ore/stone that can be sold for gold
## Rock respawns after 180 seconds (3 minutes)

# Harvesting
var player_in_range: bool = false
var is_harvested: bool = false
var interaction_prompt: Label = null
var interaction_area: Area2D = null

# Hold-to-mine system
var is_mining: bool = false
var mine_progress: float = 0.0  # 0.0 to 1.0
var mine_time_required: float = 4.0  # 4 seconds to mine rock (slower than tree)
var progress_circle: Node2D = null
var cancel_grace_timer: float = 0.0  # Prevent immediate cancellation
var cancel_grace_period: float = 0.15  # 0.15 second grace period

# Cache for performance - only check when player is in range
var current_prompt_text: String = ""

# Respawn
var respawn_time: float = 180.0  # 3 minutes to respawn
var respawn_timer: float = 0.0

# Visual references (set by game_world.gd)
var rock_sprite: Sprite2D = null
var rock_shadow: Node = null
var original_modulate: Color = Color.WHITE
var original_scale: Vector2 = Vector2.ONE

# Resource yield
var ore_amount: int = 0  # Set based on rock size (1-3 ore/stone)

# Audio
var mine_audio_player: AudioStreamPlayer = null
var break_audio_player: AudioStreamPlayer = null
var mine_sounds: Array[AudioStream] = []  # TODO: Add mining sounds
var break_sounds: Array[AudioStream] = []  # TODO: Add rock break sounds
var last_mine_sound_time: float = 0.0
var mine_sound_interval: float = 0.8  # Play mine sound every 0.8 seconds

func _ready() -> void:
	# Find sprite and shadow from children (created by game_world.gd)
	rock_sprite = get_node_or_null("Sprite")
	rock_shadow = get_node_or_null("Shadow")

	if rock_sprite:
		original_modulate = rock_sprite.modulate
		original_scale = rock_sprite.scale

		# Determine ore amount based on rock size
		var rock_scale_avg = (rock_sprite.scale.x + rock_sprite.scale.y) / 2.0
		if rock_scale_avg < 2.5:
			ore_amount = 1  # Small rocks
		elif rock_scale_avg < 4.0:
			ore_amount = 2  # Medium rocks
		else:
			ore_amount = 3  # Large rocks

	# Create interaction area
	create_interaction_area()

	# Create interaction prompt
	create_interaction_prompt()

	# Create radial progress circle
	create_progress_circle()

	# TODO: Load audio files when sounds are ready
	# load_audio_files()

func _physics_process(delta: float) -> void:
	# Handle respawn timer
	if is_harvested:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn_rock()
		return

	# Only do expensive checks when player is actually in range
	if not player_in_range:
		return

	# Check if player has pickaxe ONLY when in range (not when far away)
	var has_pickaxe = InventorySystem.has_pickaxe_equipped()

	# Update interaction prompt visibility and position
	if interaction_prompt and not is_harvested and not is_mining:
		var new_prompt_text = ""
		if has_pickaxe:
			new_prompt_text = "Hold [F] Mine Rock"
		else:
			new_prompt_text = "Need Pickaxe"

		# Only update text and color if it actually changed
		if new_prompt_text != current_prompt_text:
			current_prompt_text = new_prompt_text
			interaction_prompt.text = new_prompt_text
			if has_pickaxe:
				interaction_prompt.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Light green
			else:
				interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))  # Light red

		# Show/hide prompt
		var should_show = has_pickaxe  # Only show if has pickaxe
		if not has_pickaxe:
			should_show = true  # Show "Need Pickaxe" message too

		if should_show != interaction_prompt.visible:
			interaction_prompt.visible = should_show

		# Update position every frame when visible
		if interaction_prompt.visible:
			update_prompt_position()

	# Handle hold-to-mine mechanic
	if not is_harvested:
		# Check pickaxe one more time before allowing mine
		if not has_pickaxe:
			# Cancel any ongoing mining if pickaxe was unequipped mid-mine
			if is_mining:
				cancel_mining()
			return

		var f_is_pressed = Input.is_physical_key_pressed(KEY_F)

		if f_is_pressed:
			# F is being held - reset grace timer and mine
			cancel_grace_timer = 0.0

			if not is_mining:
				start_mining()
			else:
				# Increase progress while F is held
				mine_progress += delta / mine_time_required

				# Track time for periodic mine sounds
				last_mine_sound_time += delta

				# Play mine sound periodically during mining
				if last_mine_sound_time >= mine_sound_interval:
					play_random_mine_sound()
					last_mine_sound_time = 0.0

				# Update progress circle
				if progress_circle:
					progress_circle.queue_redraw()

				# Complete mine when progress reaches 100%
				if mine_progress >= 1.0:
					complete_mine()
		else:
			# F is not pressed - use grace period before cancelling
			if is_mining:
				cancel_grace_timer += delta

				# Only cancel if grace period has elapsed
				if cancel_grace_timer >= cancel_grace_period:
					cancel_mining()
	else:
		# Player left range - cancel immediately (no grace period)
		if is_mining:
			cancel_mining()

func create_interaction_area() -> void:
	"""Create Area2D to detect player proximity"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1  # Detect player on layer 1
	add_child(interaction_area)

	# Create interaction area around rock
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 60.0  # Reasonable range around rock
	collision.shape = shape

	# Position at BASE of rock (where player sees it)
	if rock_sprite:
		collision.position = Vector2(0, 50 * rock_sprite.scale.y)
	else:
		collision.position = Vector2(0, 100)  # Fallback

	interaction_area.add_child(collision)

	# Connect signals
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func create_interaction_prompt() -> void:
	"""Create floating [F] prompt above rock"""
	# Use CanvasLayer like PickableItem does (Labels need to be in UI tree)
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "Hold [F] Mine Rock"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Light green
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

func update_prompt_position() -> void:
	"""Update prompt position to 10 pixels below player's feet"""
	if not interaction_prompt:
		return

	# Find the player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Get player position in screen space, then add 30 pixels below feet
	var player_world_pos = player.global_position + Vector2(0, 30)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var player_screen_pos = (player_world_pos - camera_pos) * camera.zoom.x + screen_center

	# Center the prompt horizontally on player (wait for size to be calculated)
	var screen_x = player_screen_pos.x
	if interaction_prompt.size.x > 0:
		screen_x -= interaction_prompt.size.x / 2
	var screen_y = player_screen_pos.y

	interaction_prompt.position = Vector2(screen_x, screen_y)

func create_progress_circle() -> void:
	"""Create radial progress indicator for hold-to-mine"""
	var canvas = CanvasLayer.new()
	canvas.name = "ProgressCanvas"
	canvas.layer = 51  # Above interaction prompt
	add_child(canvas)

	# Create custom drawable node for radial progress
	progress_circle = Node2D.new()
	progress_circle.name = "ProgressCircle"
	progress_circle.visible = false
	canvas.add_child(progress_circle)

	# Connect draw function
	progress_circle.draw.connect(_draw_progress_circle)

func _draw_progress_circle() -> void:
	"""Draw the radial progress circle with wasteland theme"""
	if not progress_circle or not is_mining:
		return

	# Get player to position circle in front of them
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	# Position circle in front of player based on facing direction
	var circle_world_pos = player.global_position

	# Get player's facing direction from their sprite animation
	var player_sprite = player.get_node_or_null("Sprite")
	if player_sprite and player_sprite is AnimatedSprite2D:
		var current_anim = player_sprite.animation

		# Determine facing direction from animation name
		if "up" in current_anim:
			circle_world_pos.y -= 50  # Facing up: -50 Y
		elif "down" in current_anim:
			circle_world_pos.y += 50  # Facing down: +50 Y
		elif "left" in current_anim:
			circle_world_pos.x -= 50  # Facing left: -50 X
		elif "right" in current_anim:
			circle_world_pos.x += 50  # Facing right: +50 X
		else:
			# Default: place slightly in front (down)
			circle_world_pos.y += 50
	else:
		# Fallback: place in front of player (down)
		circle_world_pos.y += 50

	# Convert world position to screen position (CanvasLayer uses screen coordinates)
	var canvas_transform = get_viewport().get_canvas_transform()
	var rock_screen_pos = canvas_transform * circle_world_pos

	# === DARK FANTASY WASTELAND THEME ===
	var radius = 22.5  # Reduced by 25% (same as tree)
	var thickness = 3.4  # Proportionally reduced

	# Color palette - darker/grittier for rocks/mining
	var bg_color = Color(0.12, 0.10, 0.08, 0.85)  # Dark weathered leather
	var border_outer = Color(0.50, 0.40, 0.30, 1.0)  # Stone/earth tone
	var border_inner = Color(0.08, 0.06, 0.05, 1.0)  # Dark inner shadow
	var progress_stone = Color(0.60, 0.55, 0.50, 0.95)  # Stone/mineral tone
	var progress_glow = Color(0.75, 0.70, 0.60, 0.4)  # Dusty glow

	# Draw outer shadow (depth effect)
	progress_circle.draw_circle(rock_screen_pos, radius + 4, Color(0.0, 0.0, 0.0, 0.6))

	# Draw background circle (dark leather texture)
	progress_circle.draw_circle(rock_screen_pos, radius, bg_color)

	# Draw inner shadow ring
	progress_circle.draw_arc(rock_screen_pos, radius - 2, 0, TAU, 48, border_inner, 3.0)

	# Draw progress arc (stone/mineral tone with glow)
	if mine_progress > 0.0:
		var angle_from = -PI / 2  # Start from top
		var angle_to = angle_from + (mine_progress * TAU)  # Sweep clockwise

		# Draw glow layer first (underneath)
		var glow_points = 64
		var glow_arc = PackedVector2Array()
		glow_arc.append(rock_screen_pos)  # Center point
		for i in range(glow_points + 1):
			var t = float(i) / float(glow_points)
			var angle = lerp(angle_from, angle_to, t)
			var point = rock_screen_pos + Vector2(cos(angle), sin(angle)) * (radius - 3)
			glow_arc.append(point)
		progress_circle.draw_colored_polygon(glow_arc, progress_glow)

		# Draw main progress arc (thicker, stone colored)
		progress_circle.draw_arc(rock_screen_pos, radius - thickness / 2, angle_from, angle_to, 48, progress_stone, thickness)

		# Add inner bright edge for definition
		var highlight_color = Color(0.85, 0.80, 0.75, 0.8)  # Bright mineral highlight
		progress_circle.draw_arc(rock_screen_pos, radius - thickness - 1, angle_from, angle_to, 48, highlight_color, 1.5)

	# Draw outer border ring (stone)
	progress_circle.draw_arc(rock_screen_pos, radius + 1, 0, TAU, 48, border_outer, 3.0)

	# Draw inner border ring (darker, for depth)
	progress_circle.draw_arc(rock_screen_pos, radius - thickness - 3, 0, TAU, 48, border_inner, 2.0)

	# Add subtle notches/segments for texture (8 segments like a wheel)
	for i in range(8):
		var notch_angle = (i * TAU) / 8
		var notch_start = rock_screen_pos + Vector2(cos(notch_angle), sin(notch_angle)) * (radius - thickness - 3)
		var notch_end = rock_screen_pos + Vector2(cos(notch_angle), sin(notch_angle)) * (radius + 1)
		progress_circle.draw_line(notch_start, notch_end, Color(0.2, 0.15, 0.10, 0.6), 1.5)

func start_mining() -> void:
	"""Start the mining process"""
	is_mining = true
	mine_progress = 0.0
	cancel_grace_timer = 0.0  # Reset grace timer
	last_mine_sound_time = 0.0  # Reset sound timer

	if progress_circle:
		progress_circle.visible = true
		progress_circle.queue_redraw()

	print("⛏️ Started mining rock")

	# Play first mine sound immediately
	play_random_mine_sound()

func cancel_mining() -> void:
	"""Cancel mining (F released or player moved away)"""
	is_mining = false
	mine_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	print("🛑 Cancelled mining")

	# Stop any playing mine sound
	if mine_audio_player and mine_audio_player.playing:
		mine_audio_player.stop()

func complete_mine() -> void:
	"""Complete the mine after progress reaches 100%"""
	is_mining = false
	mine_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	print("✅ Rock mined!")

	# Stop mining sound and play rock break sound
	if mine_audio_player and mine_audio_player.playing:
		mine_audio_player.stop()

	play_random_break_sound()

	# Now actually mine the rock
	mine_rock()

func mine_rock() -> void:
	"""Mine the rock and drop ore/stone"""
	if is_harvested:
		return

	is_harvested = true
	respawn_timer = 0.0

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Spawn ore/stone drops
	spawn_ore_drops()

	# Animate rock breaking/fading
	animate_rock_break()

func spawn_ore_drops() -> void:
	"""Spawn ore/stone items"""
	var ore_item_data = {
		"name": "Wasteland Ore",
		"description": "Rough ore from wasteland rocks. Can be refined or sold.",
		"value": 15,
		"type": "material",
		"rarity": "COMMON",
		"stackable": true,
		"max_stack": 1000,
		"quantity": 1
	}

	# Try to add ore to inventory
	for i in range(ore_amount):
		if not InventorySystem.add_item(ore_item_data.duplicate()):
			break

func animate_rock_break() -> void:
	"""Animate rock breaking and create rubble"""
	if not rock_sprite:
		return

	# Fade out the rock
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(rock_sprite, "modulate:a", 0.0, 1.0)  # Fully transparent
	tween.tween_property(rock_sprite, "scale", rock_sprite.scale * 0.5, 1.0)  # Shrink

	# Fade shadow too
	if rock_shadow:
		var tween2 = create_tween()
		tween2.tween_property(rock_shadow, "modulate:a", 0.0, 1.0)

func respawn_rock() -> void:
	"""Respawn the rock after timer completes"""
	if not is_harvested:
		return

	is_harvested = false
	respawn_timer = 0.0

	# Restore rock visual
	if rock_sprite:
		# Reset position and scale
		rock_sprite.position = Vector2.ZERO
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(rock_sprite, "modulate:a", original_modulate.a, 0.5)
		tween.tween_property(rock_sprite, "scale", original_scale, 0.5)

	# Restore shadow
	if rock_shadow:
		var tween2 = create_tween()
		tween2.tween_property(rock_shadow, "modulate:a", 0.6, 0.5)

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false

# TODO: Implement when mining sounds are ready
func play_random_mine_sound() -> void:
	"""Play a random mining sound"""
	pass  # Placeholder for future audio

func play_random_break_sound() -> void:
	"""Play a random rock breaking sound"""
	pass  # Placeholder for future audio
