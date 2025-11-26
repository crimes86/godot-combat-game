extends StaticBody2D
class_name HarvestableTree

## Harvestable Tree - Can be chopped for wood
## Press E when near to chop down the tree
## Drops wood that can be sold for gold
## Tree respawns after 120 seconds

# Harvesting
var player_in_range: bool = false
var is_harvested: bool = false
var interaction_prompt: Label = null
var interaction_area: Area2D = null
var e_key_was_pressed: bool = false  # Track key state to prevent auto-chop

# Hold-to-chop system
var is_chopping: bool = false
var chop_progress: float = 0.0  # 0.0 to 1.0
var chop_time_required: float = 3.0  # 3 seconds to chop tree
var progress_circle: Node2D = null
var cancel_grace_timer: float = 0.0  # Prevent immediate cancellation
var cancel_grace_period: float = 0.15  # 0.15 second grace period

# Cache for performance - only check when player is in range
var current_prompt_text: String = ""
var prompt_fade_timer: float = 0.0  # Timer to fade out "Requires Axe" message
var prompt_fade_duration: float = 3.0  # Show message for 3 seconds

# Respawn
var respawn_time: float = 120.0  # 2 minutes to respawn
var respawn_timer: float = 0.0

# Visual references (set by game_world.gd)
var tree_sprite: Sprite2D = null
var tree_shadow: Node = null
var original_modulate: Color = Color.WHITE
var original_scale: Vector2 = Vector2.ONE

# Resource yield
var wood_amount: int = 0  # Set based on tree size (1-3 wood)

# Loot system for fallen tree
var tree_loot: Array = []  # Wood items to loot from fallen tree
var is_fallen: bool = false  # Tree has fallen and can be looted
var loot_indicator: Node2D = null  # Sparkle effect
var loot_ui: HarvestLootUI = null  # Mini harvest loot UI
var fade_timer_started: bool = false  # Track if fade timer has started

# Shake effect
var shake_tween: Tween = null
var original_sprite_position: Vector2 = Vector2.ZERO

# Audio - uses TreeAudioManager for shared sounds
var chop_audio_player: AudioStreamPlayer = null
var fall_audio_player: AudioStreamPlayer = null
var last_chop_sound_time: float = 0.0
var chop_sound_interval: float = 0.75  # Play chop sound every 0.75 seconds (4 total sounds over 3 seconds)

# Performance caching
var cached_has_axe: bool = false
var axe_check_timer: float = 0.0
const AXE_CHECK_INTERVAL: float = 0.5  # Only check axe every 0.5 seconds
var last_drawn_progress: float = -1.0  # Track last drawn progress to avoid unnecessary redraws

func _ready() -> void:
	# Find sprite and shadow from children (created by game_world.gd)
	tree_sprite = get_node_or_null("Sprite")
	tree_shadow = get_node_or_null("Shadow")

	if tree_sprite:
		original_modulate = tree_sprite.modulate
		original_scale = tree_sprite.scale
		original_sprite_position = tree_sprite.position

		# Determine wood amount based on tree size
		var tree_scale_avg = (tree_sprite.scale.x + tree_sprite.scale.y) / 2.0
		if tree_scale_avg < 2.5:
			wood_amount = 1  # Small trees
		elif tree_scale_avg < 4.0:
			wood_amount = 2  # Medium trees
		else:
			wood_amount = 3  # Large trees

	# Create interaction area
	create_interaction_area()

	# Create interaction prompt
	create_interaction_prompt()
	
	# Create radial progress circle
	create_progress_circle()

	# Create audio players (sounds are loaded by TreeAudioManager)
	create_audio_players()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle F-key input for looting fallen tree"""
	# Only process F key events
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F):
		return

	if not is_fallen:
		return

	if tree_loot.size() == 0:
		return

	if not player_in_range:
		return

	open_loot_ui()
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	# Handle respawn timer (only after tree is fully looted and fading)
	if is_harvested and fade_timer_started:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn_tree()
		return

	# Only do expensive checks when player is actually in range
	if not player_in_range:
		return

	# FALLEN TREE STATE - Player can loot
	if is_fallen and tree_loot.size() > 0:
		# Show loot prompt for fallen tree
		if interaction_prompt and not is_chopping:
			var new_prompt_text = "[F] Loot Wood"
			if new_prompt_text != current_prompt_text:
				current_prompt_text = new_prompt_text
				interaction_prompt.text = new_prompt_text
				interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
			interaction_prompt.visible = true
			interaction_prompt.modulate.a = 1.0
			update_prompt_position()
		return

	# STANDING TREE STATE - Player can chop
	if is_harvested or is_fallen:
		# Tree is down but no loot - hide prompt
		if interaction_prompt:
			interaction_prompt.visible = false
		return

	# Check if player has axe - CACHED for performance (only check every 0.5s)
	axe_check_timer += delta
	if axe_check_timer >= AXE_CHECK_INTERVAL:
		axe_check_timer = 0.0
		cached_has_axe = InventorySystem.has_axe_equipped()
	var has_axe = cached_has_axe

	# Update interaction prompt visibility and position
	if interaction_prompt and not is_harvested and not is_chopping:
		var new_prompt_text = ""
		if has_axe:
			new_prompt_text = "Hold [F] Chop Tree"
		else:
			new_prompt_text = "Requires Axe"  # Changed from "Need Axe"

		# Only update text and color if it actually changed (avoid expensive theme override calls)
		if new_prompt_text != current_prompt_text:
			current_prompt_text = new_prompt_text
			interaction_prompt.text = new_prompt_text
			if has_axe:
				interaction_prompt.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Light green
				prompt_fade_timer = 0.0  # Reset fade timer when showing action prompt
			else:
				interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))  # Light red
				prompt_fade_timer = 0.0  # Start fade timer for "Requires Axe"

		# Handle fade-out for "Requires Axe" message
		if not has_axe and interaction_prompt.visible:
			prompt_fade_timer += delta
			if prompt_fade_timer >= prompt_fade_duration:
				# Fade out the message
				var alpha = 1.0 - ((prompt_fade_timer - prompt_fade_duration) / 1.0)
				alpha = clamp(alpha, 0.0, 1.0)
				interaction_prompt.modulate.a = alpha

				# Hide completely after fade
				if alpha <= 0.0:
					interaction_prompt.visible = false
					prompt_fade_timer = 0.0
			else:
				interaction_prompt.modulate.a = 1.0  # Full opacity during display time
		else:
			interaction_prompt.modulate.a = 1.0  # Reset opacity for action prompts

		# Show/hide prompt logic
		var should_show = has_axe  # Show if has axe
		if not has_axe and prompt_fade_timer < (prompt_fade_duration + 1.0):
			should_show = true  # Show "Requires Axe" until fade complete

		if should_show != interaction_prompt.visible:
			interaction_prompt.visible = should_show
			if should_show and not has_axe:
				prompt_fade_timer = 0.0  # Reset timer when reshowing

		# Update position every frame when visible
		if interaction_prompt.visible:
			update_prompt_position()

	# Handle hold-to-chop mechanic
	if not is_harvested:
		# Check axe one more time before allowing chop
		if not has_axe:
			# Cancel any ongoing chop if axe was unequipped mid-chop
			if is_chopping:
				cancel_chopping()
			return

		var f_is_pressed = Input.is_physical_key_pressed(KEY_F)

		if f_is_pressed:
			# F is being held - reset grace timer and chop
			cancel_grace_timer = 0.0

			if not is_chopping:
				start_chopping()
			else:
				# Increase progress while F is held
				chop_progress += delta / chop_time_required

				# Track time for periodic chop sounds
				last_chop_sound_time += delta

				# Play chop sound periodically during chopping
				if last_chop_sound_time >= chop_sound_interval:
					play_random_chop_sound()
					trigger_player_harvest_animation("axe")  # Play animation with each chop
					last_chop_sound_time = 0.0

				# Update progress circle - only redraw if progress changed significantly (every 2%)
				if progress_circle and abs(chop_progress - last_drawn_progress) >= 0.02:
					last_drawn_progress = chop_progress
					progress_circle.queue_redraw()

				# Complete chop when progress reaches 100%
				if chop_progress >= 1.0:
					complete_chop()
		else:
			# F is not pressed - use grace period before cancelling
			if is_chopping:
				cancel_grace_timer += delta

				# Only cancel if grace period has elapsed
				if cancel_grace_timer >= cancel_grace_period:
					cancel_chopping()
	else:
		# Player left range - cancel immediately (no grace period)
		if is_chopping:
			cancel_chopping()

func create_interaction_area() -> void:
	"""Create Area2D to detect player proximity"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1  # Detect player on layer 1
	add_child(interaction_area)

	# Create interaction area around tree base/trunk
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 60.0  # Reasonable range around trunk
	collision.shape = shape

	# Position at BASE of tree trunk (where player sees it)
	if tree_sprite:
		collision.position = Vector2(0, 50 * tree_sprite.scale.y)
	else:
		collision.position = Vector2(0, 100)  # Fallback

	interaction_area.add_child(collision)

	# Connect signals
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func create_interaction_prompt() -> void:
	"""Create floating [F] prompt above tree"""
	# Use CanvasLayer like PickableItem does (Labels need to be in UI tree)
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "Hold [F] Chop Tree"
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
	"""Create radial progress indicator for hold-to-chop"""
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
	if not progress_circle or not is_chopping:
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
	var tree_screen_pos = canvas_transform * circle_world_pos
	
	# === DARK FANTASY WASTELAND THEME ===
	var radius = 22.5  # Reduced by another 25% (was 30.0)
	var thickness = 3.4  # Proportionally reduced (was 4.5)
	
	# Color palette matching the game's UI
	var bg_color = Color(0.12, 0.10, 0.08, 0.85)  # Dark weathered leather
	var border_outer = Color(0.45, 0.30, 0.18, 1.0)  # Rusted bronze/copper
	var border_inner = Color(0.08, 0.06, 0.05, 1.0)  # Dark inner shadow
	var progress_wood = Color(0.65, 0.45, 0.25, 0.95)  # Wood/earth tone
	var progress_glow = Color(0.85, 0.70, 0.45, 0.4)  # Faded gold glow
	
	# Draw outer shadow (depth effect)
	progress_circle.draw_circle(tree_screen_pos, radius + 4, Color(0.0, 0.0, 0.0, 0.6))
	
	# Draw background circle (dark leather texture)
	progress_circle.draw_circle(tree_screen_pos, radius, bg_color)
	
	# Draw inner shadow ring
	progress_circle.draw_arc(tree_screen_pos, radius - 2, 0, TAU, 48, border_inner, 3.0)
	
	# Draw progress arc (wood/earth tone with glow)
	if chop_progress > 0.0:
		var angle_from = -PI / 2  # Start from top
		var angle_to = angle_from + (chop_progress * TAU)  # Sweep clockwise
		
		# Draw glow layer first (underneath)
		var glow_points = 64
		var glow_arc = PackedVector2Array()
		glow_arc.append(tree_screen_pos)  # Center point
		for i in range(glow_points + 1):
			var t = float(i) / float(glow_points)
			var angle = lerp(angle_from, angle_to, t)
			var point = tree_screen_pos + Vector2(cos(angle), sin(angle)) * (radius - 3)
			glow_arc.append(point)
		progress_circle.draw_colored_polygon(glow_arc, progress_glow)
		
		# Draw main progress arc (thicker, wood colored)
		progress_circle.draw_arc(tree_screen_pos, radius - thickness / 2, angle_from, angle_to, 48, progress_wood, thickness)
		
		# Add inner bright edge for definition
		var highlight_color = Color(0.95, 0.85, 0.65, 0.8)  # Bright wood highlight
		progress_circle.draw_arc(tree_screen_pos, radius - thickness - 1, angle_from, angle_to, 48, highlight_color, 1.5)
	
	# Draw outer border ring (rusted bronze)
	progress_circle.draw_arc(tree_screen_pos, radius + 1, 0, TAU, 48, border_outer, 3.0)
	
	# Draw inner border ring (darker, for depth)
	progress_circle.draw_arc(tree_screen_pos, radius - thickness - 3, 0, TAU, 48, border_inner, 2.0)
	
	# Add subtle notches/segments for texture (8 segments like a wheel)
	for i in range(8):
		var notch_angle = (i * TAU) / 8
		var notch_start = tree_screen_pos + Vector2(cos(notch_angle), sin(notch_angle)) * (radius - thickness - 3)
		var notch_end = tree_screen_pos + Vector2(cos(notch_angle), sin(notch_angle)) * (radius + 1)
		progress_circle.draw_line(notch_start, notch_end, Color(0.2, 0.15, 0.10, 0.6), 1.5)

func start_chopping() -> void:
	"""Start the chopping process"""
	is_chopping = true
	chop_progress = 0.0
	cancel_grace_timer = 0.0  # Reset grace timer
	last_chop_sound_time = 0.0  # Reset sound timer

	# Start harvest animation immediately
	trigger_player_harvest_animation("axe")

	if progress_circle:
		progress_circle.visible = true
		last_drawn_progress = 0.0
		progress_circle.queue_redraw()

	# Play first chop sound immediately
	play_random_chop_sound()

func cancel_chopping() -> void:
	"""Cancel chopping (F released or player moved away)"""
	is_chopping = false
	chop_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Stop any playing chop sound
	if chop_audio_player and chop_audio_player.playing:
		chop_audio_player.stop()

	# Return player to idle animation
	stop_player_harvest_animation()

func complete_chop() -> void:
	"""Complete the chop after progress reaches 100%"""
	is_chopping = false
	chop_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Stop chopping sound and play tree fall sound
	if chop_audio_player and chop_audio_player.playing:
		chop_audio_player.stop()

	play_random_fall_sound()

	# Return player to idle animation
	stop_player_harvest_animation()

	# Now actually chop the tree
	chop_tree()

func chop_tree() -> void:
	"""Chop down the tree and drop wood"""
	if is_harvested:
		return

	is_harvested = true
	respawn_timer = 0.0

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Spawn wood items
	spawn_wood_drops()

	# Animate tree falling/fading
	animate_tree_chop()

func spawn_wood_drops() -> void:
	"""Generate wood loot for the fallen tree (not added to inventory yet)"""
	tree_loot.clear()

	var wood_item_data = {
		"name": "Dry Log",
		"description": "Dry wood from a dead wasteland tree. Burns well.",
		"value": 12,
		"stackable": true,
		"max_stack": 1000,
		"quantity": 1
	}

	# Generate wood items as loot (player must loot them)
	for i in range(wood_amount):
		tree_loot.append(wood_item_data.duplicate())

func animate_tree_chop() -> void:
	"""Animate tree being chopped down - shake, fall to side, wait for loot"""
	if not tree_sprite:
		return

	# Create stump from bottom portion of tree before fading out main tree
	create_tree_stump()

	# Kill any existing shake tween
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()

	# Randomly choose fall direction (left or right)
	var fall_direction = 1.0 if randf() > 0.5 else -1.0
	var fall_rotation = fall_direction * deg_to_rad(85)  # Almost 90 degrees

	# Get tree texture height (unscaled)
	var tex_height = 0.0
	if tree_sprite.texture:
		tex_height = tree_sprite.texture.get_height()

	# Move pivot to bottom of tree using offset
	# offset is in local/unscaled coordinates
	var pivot_shift = tex_height * 0.5  # Half height to move pivot from center to bottom
	tree_sprite.offset = Vector2(0, -pivot_shift)  # Shift texture UP so pivot is at bottom

	# Compensate position so tree visually stays in same place
	# Position needs to move DOWN by the scaled pivot shift amount
	tree_sprite.position = original_sprite_position + Vector2(0, pivot_shift * tree_sprite.scale.y)

	# For sparkle/interaction positioning after fall
	var tree_height = tex_height * tree_sprite.scale.y
	var fall_offset = Vector2(fall_direction * tree_height * 0.4, 0)
	var start_position = tree_sprite.position

	# Create fall animation tween - ONLY rotate (pivot is now at base)
	var tween = create_tween()

	# Phase 1: Small creak/tilt in fall direction (0.12s)
	tween.tween_property(tree_sprite, "rotation", fall_direction * deg_to_rad(6), 0.12).set_ease(Tween.EASE_OUT)

	# Phase 2: Tree falls - just rotation around base
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(tree_sprite, "rotation", fall_rotation, 0.35)

	# Phase 3: Brief settle after hitting ground
	tween.tween_interval(0.08)

	# After tree lands, mark as fallen and add sparkle effect (no color fade yet)
	tween.tween_callback(_on_tree_landed.bind(fall_direction, fall_offset, start_position))

	# Create fallen tree shadow after it hits the ground
	create_fallen_tree_shadow(fall_direction, fall_offset, start_position)

	# Fade original shadow for stump
	if tree_shadow:
		var shadow_tween = create_tween()
		shadow_tween.tween_interval(0.8)  # Wait for tree to fall
		shadow_tween.tween_property(tree_shadow, "modulate:a", 0.3, 0.5)  # Partial fade for stump shadow

func _on_tree_landed(fall_direction: float, fall_offset: Vector2, start_position: Vector2) -> void:
	"""Called when tree has finished falling - enable looting"""
	is_fallen = true
	fade_timer_started = false

	# Get tree height for positioning
	var tree_height = 200.0
	if tree_sprite and tree_sprite.texture:
		tree_height = tree_sprite.texture.get_height() * tree_sprite.scale.y

	# Expand the interaction area to cover the fallen trunk
	expand_interaction_area_for_fallen_tree(fall_direction, fall_offset)

	# Add sparkle effect at the CENTER of the fallen trunk
	# Tree rotates around base, so trunk center is offset horizontally
	var sparkle_position = Vector2(
		fall_direction * tree_height * 0.35,  # Trunk center in fall direction
		tree_height * 0.5  # Match interaction area Y position
	)
	add_loot_indicator(sparkle_position)

func expand_interaction_area_for_fallen_tree(fall_direction: float, fall_offset: Vector2) -> void:
	"""Expand the interaction area to cover the entire fallen trunk"""
	if not interaction_area:
		return

	# Remove old collision shape
	for child in interaction_area.get_children():
		if child is CollisionShape2D:
			child.queue_free()

	# Create larger collision area that covers both stump and fallen trunk
	var collision = CollisionShape2D.new()
	var shape = CapsuleShape2D.new()

	# Make capsule long enough to cover the fallen tree
	var tree_height = 200.0  # Default
	if tree_sprite and tree_sprite.texture:
		tree_height = tree_sprite.texture.get_height() * tree_sprite.scale.y

	shape.radius = 100.0  # Wide enough to easily interact
	shape.height = tree_height * 0.7  # Cover most of the trunk length

	collision.shape = shape
	# Rotate capsule to align with fallen tree direction (horizontal)
	collision.rotation = deg_to_rad(90)
	# Position at center of fallen trunk - tree fell from its base position
	# The trunk center is half the tree height away in the fall direction
	collision.position = Vector2(fall_direction * tree_height * 0.35, tree_height * 0.5)

	interaction_area.add_child(collision)

func add_loot_indicator(fallen_position: Vector2) -> void:
	"""Add shiny glimmer effect to indicate this fallen tree has loot"""
	if loot_indicator:
		return  # Already has indicator

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10  # Draw on top
	loot_indicator.position = fallen_position

	# Create 4 small sparkle points positioned above the fallen tree
	var sparkle_positions = [
		Vector2(-15, -20),
		Vector2(15, -20),
		Vector2(-10, -15),
		Vector2(10, -15)
	]

	for i in range(sparkle_positions.size()):
		var sparkle = create_sparkle()
		sparkle.position = sparkle_positions[i]
		loot_indicator.add_child(sparkle)

		# Stagger animation start times for shimmer effect
		animate_sparkle(sparkle, i * 0.2)

	add_child(loot_indicator)

func create_sparkle() -> Polygon2D:
	"""Create a single sparkle (4-pointed star)"""
	var sparkle = Polygon2D.new()

	# Create 4-pointed star shape
	var size = 6.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Top point
		Vector2(1, -1),         # Inner top-right
		Vector2(size, 0),       # Right point
		Vector2(1, 1),          # Inner bottom-right
		Vector2(0, size),       # Bottom point
		Vector2(-1, 1),         # Inner bottom-left
		Vector2(-size, 0),      # Left point
		Vector2(-1, -1)         # Inner top-left
	])

	sparkle.polygon = points
	sparkle.color = Color(1.0, 1.0, 0.8, 0.9)  # Bright yellow-white

	return sparkle

func animate_sparkle(sparkle: Polygon2D, delay: float) -> void:
	"""Animate sparkle floating upward and fading out"""
	# Wait for delay
	await get_tree().create_timer(delay).timeout

	if not is_instance_valid(sparkle):
		return

	# Store initial position
	var start_pos = sparkle.position

	# Create looping animation
	var tween = create_tween()
	tween.set_loops()

	# Float up and fade out, then reset
	tween.tween_property(sparkle, "position:y", start_pos.y - 20, 1.5).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sparkle, "rotation", TAU * 0.5, 1.5)

	# Reset instantly and wait before next cycle
	tween.tween_property(sparkle, "position:y", start_pos.y, 0.0)
	tween.parallel().tween_property(sparkle, "modulate:a", 0.9, 0.0)
	tween.parallel().tween_property(sparkle, "rotation", 0.0, 0.0)
	tween.tween_interval(0.5)  # Pause before next shimmer

func remove_loot_indicator() -> void:
	"""Remove the sparkle effect when loot is taken"""
	if loot_indicator:
		loot_indicator.queue_free()
		loot_indicator = null

func create_fallen_tree_shadow(fall_direction: float, fall_offset: Vector2, tree_start_pos: Vector2) -> void:
	"""Create a simple shadow under the fallen tree trunk"""
	if not tree_sprite or not tree_sprite.texture:
		return

	# Create a simple ellipse shadow using a ColorRect with shader or just a dark sprite
	var shadow_sprite = Sprite2D.new()
	shadow_sprite.name = "FallenTreeShadow"

	# Create a simple gradient ellipse shadow image
	var shadow_width = 120
	var shadow_height = 30
	var shadow_img = Image.create(shadow_width, shadow_height, false, Image.FORMAT_RGBA8)
	shadow_img.fill(Color(0, 0, 0, 0))

	# Draw a soft ellipse shadow
	var center_x = shadow_width / 2.0
	var center_y = shadow_height / 2.0
	for x in range(shadow_width):
		for y in range(shadow_height):
			# Ellipse distance calculation
			var dx = (float(x) - center_x) / (shadow_width / 2.0)
			var dy = (float(y) - center_y) / (shadow_height / 2.0)
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 1.0:
				# Soft falloff from center
				var alpha = (1.0 - dist) * 0.25  # Max 25% opacity
				shadow_img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))

	shadow_sprite.texture = ImageTexture.create_from_image(shadow_img)
	shadow_sprite.centered = true
	shadow_sprite.scale = tree_sprite.scale * Vector2(1.5, 1.0)  # Scale with tree
	shadow_sprite.rotation = fall_direction * deg_to_rad(85)  # Match fallen tree rotation
	shadow_sprite.position = tree_start_pos + fall_offset + Vector2(fall_direction * 20, 25)  # Under the fallen trunk
	shadow_sprite.z_index = -1  # Behind everything
	shadow_sprite.modulate = Color(1, 1, 1, 0)  # Start invisible

	add_child(shadow_sprite)

	# Animate shadow appearing after tree lands (stays until tree fades)
	var shadow_tween = create_tween()
	shadow_tween.tween_interval(0.8)  # Wait for tree to land
	shadow_tween.tween_property(shadow_sprite, "modulate:a", 1.0, 0.3)  # Fade in shadow

func create_tree_stump() -> void:
	"""Create a tree stump from the bottom section of the tree sprite with collision"""
	if not tree_sprite or not tree_sprite.texture:
		return

	# Get the tree texture
	var tree_texture = tree_sprite.texture
	var source_img = tree_texture.get_image()

	# Extract bottom 12% of tree image as stump (cut off top 88%)
	var stump_height = int(source_img.get_height() * 0.12)
	var stump_img = Image.create(source_img.get_width(), stump_height, false, Image.FORMAT_RGBA8)

	# Copy bottom 12% from source image
	var src_y = source_img.get_height() - stump_height
	stump_img.blit_rect(source_img, Rect2i(0, src_y, source_img.get_width(), stump_height), Vector2i(0, 0))

	# Make ALL pixels fully opaque (no transparency at all)
	for x in range(stump_img.get_width()):
		for y in range(stump_img.get_height()):
			var pixel = stump_img.get_pixel(x, y)
			if pixel.a > 0.1:  # If pixel has any content, make it fully opaque
				pixel.a = 1.0
				stump_img.set_pixel(x, y, pixel)

	# Add simple jagged top edge (just remove some pixels at very top)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	for x in range(stump_img.get_width()):
		var cut_depth = rng.randi_range(0, 3)  # Only 0-3 pixels deep
		for y in range(cut_depth):
			if y < stump_img.get_height():
				stump_img.set_pixel(x, y, Color(0, 0, 0, 0))  # Make transparent

	# Create stump container with collision
	var stump_node = StaticBody2D.new()
	stump_node.name = "TreeStump"

	# Create stump sprite
	var stump_sprite = Sprite2D.new()
	stump_sprite.name = "StumpSprite"
	stump_sprite.texture = ImageTexture.create_from_image(stump_img)
	stump_sprite.centered = true
	stump_sprite.scale = tree_sprite.scale
	stump_sprite.modulate = Color(0.75, 0.65, 0.55, 1.0)  # Solid brownish color, fully opaque

	# Position stump at base of tree
	var stump_offset = (source_img.get_height() - stump_height) / 2.0 * tree_sprite.scale.y
	stump_node.position = Vector2(0, stump_offset)

	# Add tiny collision shape for the stump
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 4.0  # Minimal collision radius
	collision.shape = shape
	collision.position = Vector2(0, 5)  # Slightly below center

	stump_node.add_child(stump_sprite)
	stump_node.add_child(collision)

	add_child(stump_node)

func respawn_tree() -> void:
	"""Respawn the tree after timer completes"""
	if not is_harvested:
		return

	is_harvested = false
	is_fallen = false
	fade_timer_started = false
	respawn_timer = 0.0
	tree_loot.clear()

	# Remove stump if it exists
	var stump = get_node_or_null("TreeStump")
	if stump:
		stump.queue_free()

	# Remove fallen tree shadow if it exists
	var fallen_shadow = get_node_or_null("FallenTreeShadow")
	if fallen_shadow:
		fallen_shadow.queue_free()

	# Remove loot indicator if it exists
	remove_loot_indicator()

	# Restore original interaction area (small circle at trunk base)
	restore_interaction_area()

	# Restore tree visual
	if tree_sprite:
		# Reset position and rotation in case it was animated
		tree_sprite.position = original_sprite_position
		tree_sprite.rotation = 0.0
		tree_sprite.modulate = original_modulate
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(tree_sprite, "modulate:a", original_modulate.a, 0.5)
		tween.tween_property(tree_sprite, "scale", original_scale, 0.5)

	# Restore shadow
	if tree_shadow:
		var tween2 = create_tween()
		tween2.tween_property(tree_shadow, "modulate:a", 0.6, 0.5)

func restore_interaction_area() -> void:
	"""Restore the original small interaction area for standing tree"""
	if not interaction_area:
		return

	# Remove expanded collision shape
	for child in interaction_area.get_children():
		if child is CollisionShape2D:
			child.queue_free()

	# Create original small circle at trunk base
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 60.0

	collision.shape = shape
	# Position at BASE of tree trunk
	if tree_sprite:
		collision.position = Vector2(0, 50 * tree_sprite.scale.y)
	else:
		collision.position = Vector2(0, 100)

	interaction_area.add_child(collision)


func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		prompt_fade_timer = 0.0  # Reset fade timer when entering range

		# Immediately check axe status when entering range (don't wait for cache timer)
		cached_has_axe = InventorySystem.has_axe_equipped()
		axe_check_timer = 0.0  # Reset cache timer

		# Auto-open loot UI if tree is fallen and has loot
		if is_fallen and tree_loot.size() > 0:
			open_loot_ui()

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		prompt_fade_timer = 0.0  # Reset fade timer when leaving
		if interaction_prompt:
			interaction_prompt.visible = false
			interaction_prompt.modulate.a = 1.0  # Reset opacity

		# Close loot UI if open
		if loot_ui and is_instance_valid(loot_ui):
			loot_ui.close_ui()

func create_audio_players() -> void:
	"""Create audio players (sounds loaded by TreeAudioManager singleton)"""
	chop_audio_player = AudioStreamPlayer.new()
	chop_audio_player.name = "ChopAudioPlayer"
	chop_audio_player.bus = "SFX"
	add_child(chop_audio_player)

	fall_audio_player = AudioStreamPlayer.new()
	fall_audio_player.name = "FallAudioPlayer"
	fall_audio_player.bus = "SFX"
	add_child(fall_audio_player)

func play_random_chop_sound() -> void:
	"""Play a random chopping sound from TreeAudioManager and shake the tree"""
	if not chop_audio_player:
		return

	var sound = TreeAudioManager.get_random_chop_sound()
	if sound:
		chop_audio_player.stream = sound
		chop_audio_player.play()

	# Shake the tree on impact
	shake_tree()

func shake_tree() -> void:
	"""Apply a quick shake/jitter effect to the tree sprite"""
	if not tree_sprite:
		return

	# Kill any existing shake tween
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()

	# Reset to original position first
	tree_sprite.position = original_sprite_position

	# Create shake tween - trees sway more horizontally (like being hit)
	shake_tween = create_tween()
	shake_tween.set_trans(Tween.TRANS_ELASTIC)
	shake_tween.set_ease(Tween.EASE_OUT)

	var shake_intensity = 4.0  # Pixels to shake (trees shake more than rocks)
	var shake_duration = 0.1  # Duration per shake

	# Shake sequence: sway right, left, settle (more horizontal for trees)
	shake_tween.tween_property(tree_sprite, "position",
		original_sprite_position + Vector2(shake_intensity, -1), shake_duration)
	shake_tween.tween_property(tree_sprite, "position",
		original_sprite_position + Vector2(-shake_intensity * 0.7, 0), shake_duration)
	shake_tween.tween_property(tree_sprite, "position",
		original_sprite_position + Vector2(shake_intensity * 0.3, 0), shake_duration * 0.7)
	shake_tween.tween_property(tree_sprite, "position",
		original_sprite_position, shake_duration * 0.5)

func play_random_fall_sound() -> void:
	"""Play a random tree falling sound from TreeAudioManager"""
	if not fall_audio_player:
		return

	var sound = TreeAudioManager.get_random_fall_sound()
	if sound:
		fall_audio_player.stream = sound
		fall_audio_player.play()

func trigger_player_harvest_animation(tool_type: String) -> void:
	"""Trigger the player's tool animation for harvesting"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var character_sprite = player.get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Get the player's current facing direction from their animation
	var current_anim = character_sprite.animation
	var anim_direction = "down"  # Default

	if current_anim:
		var parts = current_anim.split("_")
		if parts.size() >= 2:
			var lpc_dir = parts[1]
			match lpc_dir:
				"north": anim_direction = "up"
				"south": anim_direction = "down"
				"east": anim_direction = "right"
				"west": anim_direction = "left"
				_: anim_direction = "down"

	# Play the slash animation with the tool
	if character_sprite.has_method("play_harvest_animation"):
		character_sprite.play_harvest_animation(tool_type, anim_direction)
	elif character_sprite.has_method("play"):
		character_sprite.play("slash_" + anim_direction)

func stop_player_harvest_animation() -> void:
	"""Stop the player's harvest animation and return to idle"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	# Get the player's character sprite
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

	# Return to idle animation
	if character_sprite.has_method("stop_harvest_animation"):
		character_sprite.stop_harvest_animation()
	elif character_sprite.has_method("play"):
		# Get current direction from animation name
		var current_anim = character_sprite.animation
		var direction = "down"  # Default
		if "up" in current_anim:
			direction = "up"
		elif "left" in current_anim:
			direction = "left"
		elif "right" in current_anim:
			direction = "right"

		character_sprite.play("idle_" + direction)

func open_loot_ui() -> void:
	"""Open the mini loot UI to let player take wood from fallen tree"""
	if tree_loot.size() == 0:
		return

	# Don't open if already open
	if loot_ui and is_instance_valid(loot_ui):
		return

	# Create the mini harvest loot UI
	loot_ui = HarvestLootUI.new()
	get_tree().root.add_child(loot_ui)

	# Connect signals
	loot_ui.loot_ui_closed.connect(_on_loot_ui_closed)
	loot_ui.item_looted.connect(_on_item_looted)
	loot_ui.all_items_looted.connect(_on_all_items_looted)

	# Open with tree loot
	loot_ui.open_harvest_ui(tree_loot.duplicate(), "Wood")

func _on_item_looted(item: Dictionary) -> void:
	"""Handle individual item being looted"""
	# Find and remove the item from tree_loot
	for i in range(tree_loot.size()):
		if tree_loot[i] == item:
			tree_loot[i] = null
			break

	# Check if all loot is taken
	var has_loot = false
	for loot_item in tree_loot:
		if loot_item != null:
			has_loot = true
			break

	if not has_loot:
		_on_all_items_looted()

func _on_all_items_looted() -> void:
	"""Handle all items being looted from tree"""

	# Clear the loot array
	tree_loot.clear()

	# Remove sparkle effect
	remove_loot_indicator()

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Start the fade out timer
	start_fade_out()

func _on_loot_ui_closed() -> void:
	"""Handle loot UI closing"""

	# Clean up loot UI reference
	if loot_ui:
		loot_ui.queue_free()
		loot_ui = null

	# Check if all loot was taken
	var has_loot = false
	for loot_item in tree_loot:
		if loot_item != null:
			has_loot = true
			break

	if not has_loot:
		_on_all_items_looted()

func start_fade_out() -> void:
	"""Start the fade out animation after tree has been looted"""
	if fade_timer_started:
		return

	fade_timer_started = true

	# Random time before fading (15-45 seconds)
	var fade_delay = randf_range(15.0, 45.0)


	# Create tween for fade out
	var fade_tween = create_tween()

	# First: immediately darken/mute the tree now that it's looted
	if tree_sprite:
		fade_tween.tween_property(tree_sprite, "modulate", Color(0.5, 0.45, 0.4, 0.7), 1.0)  # Muted color

	# Then wait the random delay
	fade_tween.tween_interval(fade_delay)

	# Finally: fade out completely
	if tree_sprite:
		fade_tween.tween_property(tree_sprite, "modulate:a", 0.0, 1.5)

	# Fade fallen tree shadow
	var fallen_shadow = get_node_or_null("FallenTreeShadow")
	if fallen_shadow:
		var shadow_tween = create_tween()
		# Darken shadow immediately too
		shadow_tween.tween_property(fallen_shadow, "modulate:a", 0.5, 1.0)
		shadow_tween.tween_interval(fade_delay)
		shadow_tween.tween_property(fallen_shadow, "modulate:a", 0.0, 1.5)
		shadow_tween.tween_callback(fallen_shadow.queue_free)

	# Start respawn timer after fade completes
	fade_tween.tween_callback(func(): respawn_timer = 0.0)
