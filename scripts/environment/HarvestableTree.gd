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

# Audio - uses TreeAudioManager for shared sounds
var chop_audio_player: AudioStreamPlayer = null
var fall_audio_player: AudioStreamPlayer = null
var last_chop_sound_time: float = 0.0
var chop_sound_interval: float = 0.75  # Play chop sound every 0.75 seconds (4 total sounds over 3 seconds)

func _ready() -> void:
	# Find sprite and shadow from children (created by game_world.gd)
	tree_sprite = get_node_or_null("Sprite")
	tree_shadow = get_node_or_null("Shadow")

	if tree_sprite:
		original_modulate = tree_sprite.modulate
		original_scale = tree_sprite.scale

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

func _physics_process(delta: float) -> void:
	# Handle respawn timer
	if is_harvested:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn_tree()
		return

	# Only do expensive checks when player is actually in range
	if not player_in_range:
		return

	# Check if player has axe ONLY when in range (not when far away - major performance improvement)
	var has_axe = InventorySystem.has_axe_equipped()

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

				# Update progress circle
				if progress_circle:
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
		progress_circle.queue_redraw()

	print("🪓 Started chopping tree - WITH ANIMATION SUPPORT!")
	print("🎬 About to trigger axe animation...")

	# Trigger player axe animation
	trigger_player_harvest_animation("axe")

	# Play first chop sound immediately
	play_random_chop_sound()

func cancel_chopping() -> void:
	"""Cancel chopping (F released or player moved away)"""
	is_chopping = false
	chop_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	print("🛑 Cancelled chopping")

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

	print("✅ Tree chopped!")

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
	"""Spawn wood items at tree base"""
	var wood_item_data = {
		"name": "Dry Log",
		"description": "Dry wood from a dead wasteland tree. Burns well.",
		"value": 12,
		"stackable": true,
		"max_stack": 1000,
		"quantity": 1
	}

	# Try to add wood to inventory
	for i in range(wood_amount):
		if not InventorySystem.add_item(wood_item_data.duplicate()):
			break

func animate_tree_chop() -> void:
	"""Animate tree being chopped down and create stump"""
	if not tree_sprite:
		return

	# Create stump from bottom portion of tree before fading out main tree
	create_tree_stump()

	# Fade out the main tree (top portion)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(tree_sprite, "modulate:a", 0.0, 1.0)  # Fully transparent
	tween.tween_property(tree_sprite, "position:y", tree_sprite.position.y - 100, 1.0)  # Fall upward (tree falls away)

	# Keep shadow visible for the stump
	# Don't fade the shadow anymore - it stays for the stump

func create_tree_stump() -> void:
	"""Create a tree stump from the bottom section of the tree sprite"""
	if not tree_sprite or not tree_sprite.texture:
		return

	# Get the tree texture
	var tree_texture = tree_sprite.texture
	var source_img = tree_texture.get_image()

	# Extract bottom 12% of tree image as stump (cut off top 88%)
	var stump_height = int(source_img.get_height() * 0.12)
	var stump_img = Image.create(source_img.get_width(), stump_height, false, Image.FORMAT_RGBA8)
	stump_img.fill(Color(0, 0, 0, 0))  # Start with transparent background

	# Copy bottom 12% from source image
	var src_y = source_img.get_height() - stump_height
	stump_img.blit_rect(source_img, Rect2i(0, src_y, source_img.get_width(), stump_height), Vector2i(0, 0))

	# Add jagged, imperfect cut effect to top edge (make it look naturally chopped/splintered)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position)  # Use position as seed for consistency

	# Create more imperfect edge with larger chunks and variation
	for x in range(stump_img.get_width()):
		# Much more random variation - some areas cut deep, others shallow
		# Use noise-like pattern for natural wood grain effect
		var base_depth = rng.randi_range(2, 12)  # Wider range for more imperfection

		# Add wave pattern to simulate axe swing angle variation
		var wave_offset = int(sin(float(x) / 8.0) * 4.0)
		var cut_depth = base_depth + wave_offset

		# Random chance for extra deep splinters or chunks
		if rng.randf() < 0.15:  # 15% chance for big chunk missing
			cut_depth += rng.randi_range(5, 10)

		cut_depth = clampi(cut_depth, 2, stump_img.get_height() - 1)

		for y in range(cut_depth):
			if y < stump_img.get_height():
				var pixel = stump_img.get_pixel(x, y)
				if pixel.a > 0:
					# More aggressive alpha variation for ragged edge
					var fade = 1.0 - (float(y) / float(cut_depth))
					# Add extra randomness to create torn wood fiber effect
					var random_tear = rng.randf_range(0.0, 1.0)
					if random_tear < 0.4:  # 40% chance to fully remove pixel (torn off)
						pixel.a = 0.0
					else:
						pixel.a *= fade * rng.randf_range(0.2, 0.9)
					stump_img.set_pixel(x, y, pixel)

	# Create stump sprite at same scale as original tree
	var stump_sprite = Sprite2D.new()
	stump_sprite.name = "TreeStump"
	stump_sprite.texture = ImageTexture.create_from_image(stump_img)
	stump_sprite.centered = true
	stump_sprite.scale = tree_sprite.scale  # Keep same scale as original tree
	stump_sprite.modulate = Color(0.7, 0.6, 0.5, 1.0)  # Brownish/darker color for dead stump

	# Position stump at base of tree (offset downward since we're only showing bottom portion)
	var stump_offset = (source_img.get_height() - stump_height) / 2.0 * tree_sprite.scale.y
	stump_sprite.position = Vector2(0, stump_offset)
	stump_sprite.z_index = 0  # Same z-index as tree for proper sorting

	add_child(stump_sprite)

func respawn_tree() -> void:
	"""Respawn the tree after timer completes"""
	if not is_harvested:
		return

	is_harvested = false
	respawn_timer = 0.0

	# Remove stump if it exists
	var stump = get_node_or_null("TreeStump")
	if stump:
		stump.queue_free()

	# Restore tree visual
	if tree_sprite:
		# Reset position in case it was animated
		tree_sprite.position = Vector2.ZERO
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(tree_sprite, "modulate:a", original_modulate.a, 0.5)
		tween.tween_property(tree_sprite, "scale", original_scale, 0.5)

	# Restore shadow
	if tree_shadow:
		var tween2 = create_tween()
		tween2.tween_property(tree_shadow, "modulate:a", 0.6, 0.5)

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		prompt_fade_timer = 0.0  # Reset fade timer when entering range

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		prompt_fade_timer = 0.0  # Reset fade timer when leaving
		if interaction_prompt:
			interaction_prompt.visible = false
			interaction_prompt.modulate.a = 1.0  # Reset opacity

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
	"""Play a random chopping sound from TreeAudioManager"""
	if not chop_audio_player:
		return

	var sound = TreeAudioManager.get_random_chop_sound()
	if sound:
		chop_audio_player.stream = sound
		chop_audio_player.play()

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
	print("🌲 Tree triggering harvest animation for tool: %s" % tool_type)
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		print("   ❌ No player found!")
		return

	# Get the player's character sprite
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if not character_sprite:
		print("   ❌ No CharacterSprite found on player!")
		return
	print("   ✅ Found CharacterSprite: %s" % character_sprite)

	# Get the player's current facing direction from their animation
	var current_anim = character_sprite.animation
	var anim_direction = "down"  # Default

	# Extract direction from current animation (e.g., "idle_south" -> "south", "walk_east" -> "east")
	if current_anim:
		var parts = current_anim.split("_")
		if parts.size() >= 2:
			var lpc_dir = parts[1]  # Get the direction part
			# Convert from LPC format (north/south/east/west) to simple format (up/down/right/left)
			match lpc_dir:
				"north": anim_direction = "up"
				"south": anim_direction = "down"
				"east": anim_direction = "right"
				"west": anim_direction = "left"
				_: anim_direction = "down"
			print("   Using player's current facing: %s (from animation: %s)" % [anim_direction, current_anim])
		else:
			print("   Could not parse direction from animation: %s" % current_anim)
	else:
		print("   No current animation, using default: down")

	# Play the slash animation with the tool
	if character_sprite.has_method("play_harvest_animation"):
		print("   ➡️ Calling play_harvest_animation(%s, %s)" % [tool_type, anim_direction])
		character_sprite.play_harvest_animation(tool_type, anim_direction)
	elif character_sprite.has_method("play"):
		# Fallback to standard slash animation
		print("   ➡️ Fallback: Calling play(%s)" % ("slash_" + anim_direction))
		character_sprite.play("slash_" + anim_direction)
	else:
		print("   ❌ CharacterSprite has no play methods!")

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
