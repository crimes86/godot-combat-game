extends StaticBody2D
class_name HarvestableRock

## Harvestable Rock - Can be mined for ore/stone
## Press F when near to mine the rock
## Drops ore/stone that can be sold for gold
## Rock respawns after 180 seconds (3 minutes)
## Supports tiered mining system (Tier 1-3)

# === TIER SYSTEM ===
var rock_tier: int = 1  # 1 = Zone 1 (basic), 2 = Zone 2 (iron), 3 = Zone 3 (steel)
var rock_size: String = "medium"  # small, medium, large, cluster, standing
var tier_data: Dictionary = {}  # Cached tier data from ROCK_TIERS

# Tier names for display
const TIER_NAMES = {
	1: "dreadland Rock",
	2: "Highland Rock",
	3: "Ancient Stone"
}

# Pickaxe tier names for requirement messages
const PICKAXE_TIER_NAMES = {
	0: "Basic Pickaxe",
	1: "Iron Pickaxe",
	2: "Steel Pickaxe"
}

# Harvesting
var player_in_range: bool = false
var is_harvested: bool = false
var interaction_prompt: Label = null
var interaction_area: Area2D = null

# Hold-to-mine system
var is_mining: bool = false
var mine_progress: float = 0.0  # 0.0 to 1.0
var mine_time_required: float = 3.0  # Base time, overridden by tier
var progress_circle: Node2D = null
var cancel_grace_timer: float = 0.0  # Prevent immediate cancellation
var cancel_grace_period: float = 0.15  # 0.15 second grace period

# Cache for performance - only check when player is in range
var current_prompt_text: String = ""
var prompt_fade_timer: float = 0.0  # Timer to fade out "Requires Pickaxe" message
var prompt_fade_duration: float = 3.0  # Show message for 3 seconds

# Respawn
var respawn_time: float = 180.0  # 3 minutes to respawn
var respawn_timer: float = 0.0

# Visual references (set by game_world.gd)
var rock_sprite: Sprite2D = null
var rock_shadow: Node = null
var original_modulate: Color = Color.WHITE
var original_scale: Vector2 = Vector2.ONE

# Resource yield (now determined by tier_data drops)
var ore_amount: int = 0  # Legacy, kept for compatibility

# Loot system for mined rock pile
var rock_loot: Array = []  # Ore items to loot from rock pile
var is_mined: bool = false  # Rock has been mined and is now a rock pile
var loot_indicator: Node2D = null  # Sparkle effect
var loot_ui: HarvestLootUI = null  # Mini harvest loot UI
var fade_timer_started: bool = false  # Track if fade timer has started
var rock_pile_sprite: Sprite2D = null  # The rubble/rock pile after mining

# Shake effect
var shake_tween: Tween = null
var original_sprite_position: Vector2 = Vector2.ZERO

# Audio
var mine_audio_player: AudioStreamPlayer = null
var break_audio_player: AudioStreamPlayer = null
var mine_sounds: Array[AudioStream] = []
var break_sounds: Array[AudioStream] = []
var last_mine_sound_time: float = 0.0
var mine_sound_interval: float = 0.8  # Play mine sound every 0.8 seconds (slower, deliberate mining strikes)

# Performance caching
var cached_has_pickaxe: bool = false
var cached_pickaxe_tier: int = -1  # -1 = no pickaxe, 0+ = pickaxe tier
var pickaxe_check_timer: float = 0.0
const PICKAXE_CHECK_INTERVAL: float = 0.5  # Only check pickaxe every 0.5 seconds
var last_drawn_progress: float = -1.0  # Track last drawn progress

# Network sync
var network_mine_progress_timer: float = 0.0
const NETWORK_PROGRESS_SYNC_INTERVAL: float = 0.25  # Sync progress every 0.25s

func _ready() -> void:
	# Find sprite and shadow from children (created by game_world.gd)
	rock_sprite = get_node_or_null("Sprite")
	rock_shadow = get_node_or_null("Shadow")

	if rock_sprite:
		original_modulate = rock_sprite.modulate
		original_scale = rock_sprite.scale
		original_sprite_position = rock_sprite.position

		# Legacy ore amount based on rock size (kept for compatibility)
		var rock_scale_avg = (rock_sprite.scale.x + rock_sprite.scale.y) / 2.0
		if rock_scale_avg < 2.5:
			ore_amount = 1  # Small rocks
		elif rock_scale_avg < 4.0:
			ore_amount = 2  # Medium rocks
		else:
			ore_amount = 3  # Large rocks

	# Initialize tier data
	_setup_tier_data()

	# Create interaction area
	create_interaction_area()

	# Create interaction prompt
	create_interaction_prompt()

	# Create radial progress circle
	create_progress_circle()

	# Load audio files
	load_audio_files()

func _setup_tier_data() -> void:
	"""Initialize tier-specific settings from ChunkBasedPropSystem.ROCK_TIERS"""
	# Try to get tier data from ChunkBasedPropSystem
	var prop_system = get_node_or_null("/root/ChunkBasedPropSystem")
	if prop_system and "ROCK_TIERS" in prop_system:
		if prop_system.ROCK_TIERS.has(rock_tier):
			tier_data = prop_system.ROCK_TIERS[rock_tier]
			mine_time_required = tier_data.get("mine_time", 3.0)
	else:
		# Fallback tier data if prop system not available
		tier_data = {
			"name": TIER_NAMES.get(rock_tier, "Rock"),
			"pickaxe_tier": rock_tier - 1,
			"mine_time": 3.0 + (rock_tier - 1),
			"xp": 10 * rock_tier,
			"drops": {"stone": {"min": 1, "max": 3}}
		}
		mine_time_required = tier_data.mine_time

func set_rock_tier(tier: int, size: String = "medium") -> void:
	"""Set rock tier and size (called by spawner)"""
	rock_tier = clamp(tier, 1, 3)
	rock_size = size
	_setup_tier_data()

func get_required_pickaxe_tier() -> int:
	"""Get the minimum pickaxe tier required to mine this rock"""
	return tier_data.get("pickaxe_tier", rock_tier - 1)

func _exit_tree() -> void:
	"""Clean up when rock is removed from scene tree"""
	# Cancel mining to hide progress circle and restore player state
	if is_mining:
		is_mining = false
		mine_progress = 0.0
		if progress_circle:
			progress_circle.visible = false
		stop_player_harvest_animation()

	# Unregister from InteractionManager
	InteractionManager.unregister_interactable(self)

	# Close loot UI if open
	if loot_ui and is_instance_valid(loot_ui):
		loot_ui.close_ui()
		loot_ui = null

func _unhandled_input(event: InputEvent) -> void:
	"""Handle F-key input for looting mined rock pile"""
	# Only process F key events
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F):
		return

	if not is_mined:
		return

	if rock_loot.size() == 0:
		return

	if not player_in_range:
		return

	open_loot_ui()
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	# Handle respawn timer (only after rock pile is looted and fading)
	if is_harvested and fade_timer_started:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			respawn_rock()
		return

	# Only do expensive checks when player is actually in range
	if not player_in_range:
		return

	# Check if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)

	# MINED ROCK PILE STATE - Player can loot
	if is_mined and rock_loot.size() > 0:
		# Show loot prompt for rock pile (only if active)
		if interaction_prompt and not is_mining:
			if is_active:
				var new_prompt_text = "[F] Loot Ore"
				if new_prompt_text != current_prompt_text:
					current_prompt_text = new_prompt_text
					interaction_prompt.text = new_prompt_text
					interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
				interaction_prompt.visible = true
				interaction_prompt.modulate.a = 1.0
				update_prompt_position()
			else:
				interaction_prompt.visible = false
		return

	# STANDING ROCK STATE - already mined but no loot
	if is_harvested or is_mined:
		if interaction_prompt:
			interaction_prompt.visible = false
		return

	# Check if player has pickaxe and tier - CACHED for performance (only check every 0.5s)
	pickaxe_check_timer += delta
	if pickaxe_check_timer >= PICKAXE_CHECK_INTERVAL:
		pickaxe_check_timer = 0.0
		cached_has_pickaxe = InventorySystem.has_pickaxe_equipped()
		cached_pickaxe_tier = InventorySystem.get_equipped_pickaxe_tier()
	var has_pickaxe = cached_has_pickaxe
	var required_tier = get_required_pickaxe_tier()
	var has_sufficient_tier = cached_pickaxe_tier >= required_tier
	var can_mine = has_pickaxe and has_sufficient_tier

	# Update interaction prompt visibility and position (only if active interactable)
	if interaction_prompt and not is_harvested and not is_mining:
		if not is_active:
			interaction_prompt.visible = false
		else:
			var new_prompt_text = ""
			if can_mine:
				new_prompt_text = "Hold [F] Mine " + tier_data.get("name", "Rock")
			elif has_pickaxe and not has_sufficient_tier:
				# Player has pickaxe but wrong tier
				var required_pickaxe = PICKAXE_TIER_NAMES.get(required_tier, "Better Pickaxe")
				new_prompt_text = "Requires " + required_pickaxe
			else:
				new_prompt_text = "Requires Pickaxe Equipped"

			# Only update text and color if it actually changed
			if new_prompt_text != current_prompt_text:
				current_prompt_text = new_prompt_text
				interaction_prompt.text = new_prompt_text
				if can_mine:
					interaction_prompt.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Light green
					prompt_fade_timer = 0.0  # Reset fade timer when showing action prompt
				else:
					interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))  # Light red
					prompt_fade_timer = 0.0  # Start fade timer for requirement message

		# Handle fade-out for requirement messages
		if not can_mine and interaction_prompt.visible:
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
		var should_show = can_mine  # Show if can mine
		if not can_mine and prompt_fade_timer < (prompt_fade_duration + 1.0):
			should_show = true  # Show requirement message until fade complete

		if should_show != interaction_prompt.visible:
			interaction_prompt.visible = should_show
			if should_show and not can_mine:
				prompt_fade_timer = 0.0  # Reset timer when reshowing

		# Update position every frame when visible
		if interaction_prompt.visible:
			update_prompt_position()

	# Handle hold-to-mine mechanic
	if not is_harvested:
		# Check pickaxe and tier before allowing mine
		if not can_mine:
			# Cancel any ongoing mining if pickaxe was unequipped mid-mine
			if is_mining:
				cancel_mining()
			return

		var f_is_pressed = Input.is_physical_key_pressed(KEY_F) or GameInput.is_interact_just_pressed()

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
					trigger_player_harvest_animation("pickaxe")  # Play animation with each strike
					last_mine_sound_time = 0.0

				# Update progress circle - only redraw if progress changed significantly (every 2%)
				if progress_circle and abs(mine_progress - last_drawn_progress) >= 0.02:
					last_drawn_progress = mine_progress
					progress_circle.queue_redraw()

				# Network sync - periodically send progress to other players
				sync_mine_progress_network()

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
	"""Create Area2D to detect player proximity from any direction (360 degrees)"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1  # Detect player on layer 1
	add_child(interaction_area)

	# Create interaction area centered on rock sprite
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()

	# Scale radius based on rock size for proper 360-degree coverage
	if rock_sprite:
		var rock_scale_avg = (rock_sprite.scale.x + rock_sprite.scale.y) / 2.0
		shape.radius = 80.0 + (rock_scale_avg * 15.0)  # Larger rocks get bigger interaction radius
	else:
		shape.radius = 100.0  # Fallback

	collision.shape = shape

	# Center the collision on the rock's visual center (slight offset down for sprite anchor)
	if rock_sprite:
		collision.position = Vector2(0, 20 * rock_sprite.scale.y)  # Smaller offset, more centered
	else:
		collision.position = Vector2(0, 30)  # Fallback

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
	"""Draw the radial progress circle with dreadland theme"""
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

	# === DARK FANTASY dreadland THEME ===
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
	network_mine_progress_timer = 0.0  # Reset network timer

	if progress_circle:
		progress_circle.visible = true
		last_drawn_progress = 0.0
		progress_circle.queue_redraw()

	# Trigger player pickaxe animation
	trigger_player_harvest_animation("pickaxe")

	# Play first mine sound immediately
	play_random_mine_sound()

	# Network sync - notify other players we started mining
	request_start_mining()

func cancel_mining() -> void:
	"""Cancel mining (F released or player moved away)"""
	is_mining = false
	mine_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Stop any playing mine sound
	if mine_audio_player and mine_audio_player.playing:
		mine_audio_player.stop()

	# Return player to idle animation
	stop_player_harvest_animation()

func complete_mine() -> void:
	"""Complete the mine after progress reaches 100%"""
	is_mining = false
	mine_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Stop mining sound and play rock break sound
	if mine_audio_player and mine_audio_player.playing:
		mine_audio_player.stop()

	play_random_break_sound()

	# Return player to idle animation
	stop_player_harvest_animation()

	# Network sync - notify other players the mine is complete
	request_complete_mine()

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

	# Grant XP for mining (from tier data, scaled by rock size)
	var base_xp = tier_data.get("xp", 10)
	var xp_gain = base_xp + (ore_amount * 2)  # Tier XP + bonus for larger rocks
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("gain_experience"):
		player.gain_experience(xp_gain)
		# Show world-space XP text floating up from rock
		var game_world = get_tree().get_first_node_in_group("game_world")
		if game_world:
			CombatText.create_xp(xp_gain, global_position, game_world)

	# Animate rock breaking/fading
	animate_rock_break()

func spawn_ore_drops() -> void:
	"""Generate ore loot for the rock pile based on tier drops table"""
	rock_loot.clear()

	var drops = tier_data.get("drops", {})
	if drops.is_empty():
		# Fallback to basic stone drop
		drops = {"stone": {"min": 1, "max": 3}}

	# Item templates for each drop type
	var item_templates = {
		"stone": {
			"name": "Stone",
			"description": "A chunk of rough stone.",
			"value": 5,
			"type": "material",
			"rarity": "COMMON",
			"stackable": true,
			"max_stack": 1000
		},
		"copper_ore": {
			"name": "Copper Ore",
			"description": "Raw copper ore. Can be smelted into copper bars.",
			"value": 15,
			"type": "material",
			"rarity": "COMMON",
			"stackable": true,
			"max_stack": 1000
		},
		"iron_ore": {
			"name": "Iron Ore",
			"description": "Dense iron ore. Can be smelted into iron bars.",
			"value": 25,
			"type": "material",
			"rarity": "UNCOMMON",
			"stackable": true,
			"max_stack": 1000
		},
		"gold_ore": {
			"name": "Gold Ore",
			"description": "Precious gold ore. Highly valuable when smelted.",
			"value": 75,
			"type": "material",
			"rarity": "RARE",
			"stackable": true,
			"max_stack": 1000
		},
		"gem_shard": {
			"name": "Gem Shard",
			"description": "A sparkling gem fragment. Used in jewelry and enchanting.",
			"value": 50,
			"type": "material",
			"rarity": "UNCOMMON",
			"stackable": true,
			"max_stack": 100
		},
		"ancient_fragment": {
			"name": "Ancient Fragment",
			"description": "A mysterious fragment pulsing with ancient energy.",
			"value": 150,
			"type": "material",
			"rarity": "RARE",
			"stackable": true,
			"max_stack": 50
		}
	}

	# Process each drop type from tier data
	for drop_type in drops:
		var drop_data = drops[drop_type]
		var min_amount = drop_data.get("min", 0)
		var max_amount = drop_data.get("max", 1)
		var drop_chance = drop_data.get("chance", 1.0)  # Default to 100% if not specified

		# Check chance roll
		if drop_chance < 1.0 and randf() > drop_chance:
			continue  # Failed chance roll, skip this drop

		# Determine amount to drop
		var amount = randi_range(min_amount, max_amount)
		if amount <= 0:
			continue

		# Get item template or create generic one
		var template = item_templates.get(drop_type, {
			"name": drop_type.capitalize().replace("_", " "),
			"description": "A mining resource.",
			"value": 10,
			"type": "material",
			"rarity": "COMMON",
			"stackable": true,
			"max_stack": 1000
		})

		# Create item entries (one per unit for looting UI)
		for i in range(amount):
			var item = template.duplicate()
			item["quantity"] = 1
			rock_loot.append(item)


func animate_rock_break() -> void:
	"""Animate rock imploding into a rock pile with fragment burst"""
	if not rock_sprite:
		return

	# Create the rock pile first (starts invisible, will appear after implode)
	create_rock_pile()

	# Spawn rock fragment particles bursting outward
	spawn_rock_fragments()

	# Quick shake before breaking
	var shake_tween = create_tween()
	shake_tween.tween_property(rock_sprite, "position", rock_sprite.position + Vector2(3, 0), 0.03)
	shake_tween.tween_property(rock_sprite, "position", rock_sprite.position + Vector2(-3, 0), 0.03)
	shake_tween.tween_property(rock_sprite, "position", rock_sprite.position + Vector2(2, -2), 0.03)
	shake_tween.tween_property(rock_sprite, "position", rock_sprite.position, 0.03)

	# Implode animation - rock shrinks quickly to center
	var tween = create_tween()
	tween.tween_interval(0.1)  # Brief delay for shake
	tween.set_parallel(true)
	tween.tween_property(rock_sprite, "scale", rock_sprite.scale * 0.05, 0.2).set_ease(Tween.EASE_IN)
	tween.tween_property(rock_sprite, "modulate:a", 0.0, 0.2)

	# Fade shadow quickly
	if rock_shadow:
		var shadow_tween = create_tween()
		shadow_tween.tween_property(rock_shadow, "modulate:a", 0.2, 0.25)

	# After implode completes, show rock pile and sparkles
	tween.set_parallel(false)
	tween.tween_callback(_on_rock_imploded)

func spawn_rock_fragments() -> void:
	"""Spawn rock fragments that burst outward from the rock"""
	var rock_center = rock_sprite.global_position + Vector2(0, original_scale.y * 15)
	var rock_color = Color(0.5, 0.45, 0.4)  # Grayish brown rock color

	# Create 12-18 fragments
	var fragment_count = randi_range(12, 18)

	for i in range(fragment_count):
		var fragment = create_rock_fragment(rock_color)
		fragment.global_position = rock_center + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		get_parent().add_child(fragment)

		# Random outward direction
		var angle = randf() * TAU
		var speed = randf_range(80, 180)
		var direction = Vector2(cos(angle), sin(angle))

		# Some fragments go more upward
		if randf() < 0.4:
			direction.y = -abs(direction.y) * randf_range(1.2, 2.0)

		# Animate fragment flying out and fading
		var flight_time = randf_range(0.3, 0.5)
		var end_pos = fragment.global_position + direction * speed

		var frag_tween = create_tween()
		frag_tween.set_parallel(true)

		# Move outward with slight arc (gravity)
		frag_tween.tween_property(fragment, "global_position", end_pos, flight_time).set_ease(Tween.EASE_OUT)
		frag_tween.tween_property(fragment, "global_position:y", end_pos.y + 30, flight_time).set_ease(Tween.EASE_IN).set_delay(flight_time * 0.5)

		# Rotate while flying
		var spin = randf_range(-720, 720)
		frag_tween.tween_property(fragment, "rotation_degrees", spin, flight_time)

		# Scale down and fade out
		frag_tween.tween_property(fragment, "scale", Vector2(0.3, 0.3), flight_time).set_ease(Tween.EASE_IN)
		frag_tween.tween_property(fragment, "modulate:a", 0.0, flight_time * 0.8).set_delay(flight_time * 0.2)

		# Clean up
		frag_tween.set_parallel(false)
		frag_tween.tween_callback(fragment.queue_free)

func create_rock_fragment(base_color: Color) -> Polygon2D:
	"""Create a small rock fragment polygon"""
	var fragment = Polygon2D.new()

	# Random irregular polygon shape (3-5 vertices)
	var vertex_count = randi_range(3, 5)
	var points = PackedVector2Array()
	var size = randf_range(4, 10)

	for i in range(vertex_count):
		var angle = (float(i) / vertex_count) * TAU + randf_range(-0.3, 0.3)
		var dist = size * randf_range(0.6, 1.0)
		points.append(Vector2(cos(angle) * dist, sin(angle) * dist))

	fragment.polygon = points

	# Slightly vary the color
	fragment.color = Color(
		base_color.r + randf_range(-0.1, 0.1),
		base_color.g + randf_range(-0.1, 0.1),
		base_color.b + randf_range(-0.1, 0.1),
		1.0
	)

	fragment.z_index = 5  # Above most things during flight

	return fragment

func create_rock_pile() -> void:
	"""Create a rock pile/rubble sprite from the original rock"""
	if not rock_sprite or not rock_sprite.texture:
		return

	# Create rock pile sprite - smaller, darker version of original
	rock_pile_sprite = Sprite2D.new()
	rock_pile_sprite.name = "RockPile"
	rock_pile_sprite.texture = rock_sprite.texture
	rock_pile_sprite.centered = true

	# Make it smaller (30-40% of original) and squashed to look like rubble
	var pile_scale = original_scale * randf_range(0.3, 0.4)
	pile_scale.y *= 0.6  # Squash vertically to look like a pile
	rock_pile_sprite.scale = pile_scale

	# Position at base of where rock was
	rock_pile_sprite.position = Vector2(0, original_scale.y * 20)

	# Slightly darker/grayer to look like rubble
	rock_pile_sprite.modulate = Color(0.7, 0.65, 0.6, 0.0)  # Start invisible

	rock_pile_sprite.z_index = rock_sprite.z_index

	add_child(rock_pile_sprite)

func _on_rock_imploded() -> void:
	"""Called when rock implode animation completes"""
	is_mined = true
	fade_timer_started = false

	# Shrink collision to minimal for the rock pile
	for child in get_children():
		if child is CollisionShape2D and child.shape is CircleShape2D:
			child.shape.radius = 4.0  # Minimal collision for pile

	# Fade in the rock pile
	if rock_pile_sprite:
		var pile_tween = create_tween()
		pile_tween.tween_property(rock_pile_sprite, "modulate:a", 1.0, 0.2)

	# Add sparkle effect on the rock pile
	add_loot_indicator()


func add_loot_indicator() -> void:
	"""Add shiny glimmer effect to indicate rock pile has loot"""
	if loot_indicator:
		return  # Already has indicator

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10  # Draw on top

	# Position sparkles on the rock pile
	var pile_pos = Vector2(0, original_scale.y * 20)
	loot_indicator.position = pile_pos

	# Create 4 small sparkle points
	var sparkle_positions = [
		Vector2(-10, -15),
		Vector2(10, -15),
		Vector2(-6, -10),
		Vector2(6, -10)
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

func respawn_rock() -> void:
	"""Respawn the rock after timer completes"""
	if not is_harvested:
		return

	is_harvested = false
	is_mined = false
	fade_timer_started = false
	respawn_timer = 0.0
	rock_loot.clear()

	# Remove rock pile if it exists
	if rock_pile_sprite:
		rock_pile_sprite.queue_free()
		rock_pile_sprite = null

	# Remove loot indicator if it exists
	remove_loot_indicator()

	# Restore rock visual
	if rock_sprite:
		# Reset position and scale
		rock_sprite.position = original_sprite_position
		rock_sprite.modulate = original_modulate
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
		prompt_fade_timer = 0.0  # Reset fade timer when entering range

		# Register with InteractionManager
		var distance = global_position.distance_to(body.global_position)
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.HARVESTABLE, distance)

		# Immediately check pickaxe status when entering range (don't wait for cache timer)
		cached_has_pickaxe = InventorySystem.has_pickaxe_equipped()
		cached_pickaxe_tier = InventorySystem.get_equipped_pickaxe_tier()
		pickaxe_check_timer = 0.0  # Reset cache timer

		# Auto-open loot UI if rock is mined and has loot
		if is_mined and rock_loot.size() > 0:
			open_loot_ui()

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		prompt_fade_timer = 0.0  # Reset fade timer when leaving

		# Cancel mining if in progress
		if is_mining:
			is_mining = false
			mine_progress = 0.0
			if progress_circle:
				progress_circle.visible = false
			stop_player_harvest_animation()

		# Unregister from InteractionManager
		InteractionManager.unregister_interactable(self)

		if interaction_prompt:
			interaction_prompt.visible = false
			interaction_prompt.modulate.a = 1.0  # Reset opacity

		# Close loot UI if open
		if loot_ui and is_instance_valid(loot_ui):
			loot_ui.close_ui()

func load_audio_files() -> void:
	"""Load mining and break sound effects"""
	# Create audio players
	mine_audio_player = AudioStreamPlayer.new()
	mine_audio_player.name = "MineAudioPlayer"
	mine_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(mine_audio_player)

	break_audio_player = AudioStreamPlayer.new()
	break_audio_player.name = "BreakAudioPlayer"
	break_audio_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(break_audio_player)

	# Load strike sounds
	var strike_paths = [
		"res://assets/audio/sfx/rock_strike_1.wav",
		"res://assets/audio/sfx/rock_strike_2.wav",
		"res://assets/audio/sfx/rock_strike_3.wav",
		"res://assets/audio/sfx/rock_strike_4.wav"
	]
	for path in strike_paths:
		if ResourceLoader.exists(path):
			var sound = load(path)
			if sound:
				mine_sounds.append(sound)

	# Load break sounds
	var break_paths = [
		"res://assets/audio/sfx/rock_break_1.wav",
		"res://assets/audio/sfx/rock_break_2.wav",
		"res://assets/audio/sfx/rock_break_3.wav"
	]
	for path in break_paths:
		if ResourceLoader.exists(path):
			var sound = load(path)
			if sound:
				break_sounds.append(sound)


func play_random_mine_sound() -> void:
	"""Play a random mining strike sound and shake the rock"""
	if mine_sounds.is_empty() or not mine_audio_player:
		return

	var sound = mine_sounds[randi() % mine_sounds.size()]
	mine_audio_player.stream = sound
	mine_audio_player.pitch_scale = randf_range(0.9, 1.1)  # Slight pitch variation
	mine_audio_player.volume_db = -8.0  # Match tree chop volume
	mine_audio_player.play()

	# Shake the rock on impact
	shake_rock()

func shake_rock() -> void:
	"""Apply a quick shake/jitter effect to the rock sprite"""
	if not rock_sprite:
		return

	# Kill any existing shake tween
	if shake_tween and shake_tween.is_valid():
		shake_tween.kill()

	# Reset to original position first
	rock_sprite.position = original_sprite_position

	# Create shake tween - quick jitter effect
	shake_tween = create_tween()
	shake_tween.set_trans(Tween.TRANS_SINE)
	shake_tween.set_ease(Tween.EASE_OUT)

	var shake_intensity = 3.0  # Pixels to shake
	var shake_duration = 0.08  # Duration per shake

	# Shake sequence: right, left, right, center
	shake_tween.tween_property(rock_sprite, "position",
		original_sprite_position + Vector2(shake_intensity, -shake_intensity * 0.5), shake_duration)
	shake_tween.tween_property(rock_sprite, "position",
		original_sprite_position + Vector2(-shake_intensity, shake_intensity * 0.3), shake_duration)
	shake_tween.tween_property(rock_sprite, "position",
		original_sprite_position + Vector2(shake_intensity * 0.5, 0), shake_duration * 0.5)
	shake_tween.tween_property(rock_sprite, "position",
		original_sprite_position, shake_duration * 0.5)

func play_random_break_sound() -> void:
	"""Play a random rock breaking/crumbling sound"""
	if break_sounds.is_empty() or not break_audio_player:
		return

	var sound = break_sounds[randi() % break_sounds.size()]
	break_audio_player.stream = sound
	break_audio_player.pitch_scale = randf_range(0.95, 1.05)  # Slight pitch variation
	break_audio_player.volume_db = -6.0  # Louder for important feedback
	break_audio_player.play()

func trigger_player_harvest_animation(tool_type: String) -> void:
	"""Trigger the player's tool animation for harvesting"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	# Get the player's character sprite
	var character_sprite = player.get_node_or_null("CharacterSprite")
	if not character_sprite:
		return

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

	# Play the slash animation with the tool
	if character_sprite.has_method("play_harvest_animation"):
		character_sprite.play_harvest_animation(tool_type, anim_direction)
	elif character_sprite.has_method("play"):
		# Fallback to standard slash animation
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
	"""Open the mini loot UI to let player take ore from rock pile"""
	if rock_loot.size() == 0:
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

	# Open with rock loot
	loot_ui.open_harvest_ui(rock_loot.duplicate(), "Ore")

func _on_item_looted(item: Dictionary) -> void:
	"""Handle individual item being looted"""
	# Find and remove the item from rock_loot
	for i in range(rock_loot.size()):
		if rock_loot[i] == item:
			rock_loot[i] = null
			break

	# Check if all loot is taken
	var has_loot = false
	for loot_item in rock_loot:
		if loot_item != null:
			has_loot = true
			break

	if not has_loot:
		_on_all_items_looted()

func _on_all_items_looted() -> void:
	"""Handle all items being looted from rock pile"""

	# Network sync - notify other players loot was taken
	request_loot_taken()

	# Clear the loot array
	rock_loot.clear()

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
	for loot_item in rock_loot:
		if loot_item != null:
			has_loot = true
			break

	if not has_loot:
		_on_all_items_looted()

func start_fade_out() -> void:
	"""Start the fade out animation after rock pile has been looted"""
	if fade_timer_started:
		return

	fade_timer_started = true

	# Random time before fading (15-45 seconds)
	var fade_delay = randf_range(15.0, 45.0)


	# Create tween for fade out
	var fade_tween = create_tween()

	# First: immediately darken/mute the rock pile now that it's looted
	if rock_pile_sprite:
		fade_tween.tween_property(rock_pile_sprite, "modulate", Color(0.4, 0.38, 0.35, 0.6), 1.0)  # Muted color

	# Then wait the random delay
	fade_tween.tween_interval(fade_delay)

	# Finally: fade out completely
	if rock_pile_sprite:
		fade_tween.tween_property(rock_pile_sprite, "modulate:a", 0.0, 1.5)

	# Fade shadow too
	if rock_shadow:
		var shadow_tween = create_tween()
		shadow_tween.tween_property(rock_shadow, "modulate:a", 0.1, 1.0)
		shadow_tween.tween_interval(fade_delay)
		shadow_tween.tween_property(rock_shadow, "modulate:a", 0.0, 1.5)

	# Start respawn timer after fade completes
	fade_tween.tween_callback(func(): respawn_timer = 0.0)

# ═══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER: Network Sync for Mining
# ═══════════════════════════════════════════════════════════════════════════════

func _get_network_id() -> String:
	"""Get the network ID for this rock"""
	return get_meta("network_id", "")

func _is_multiplayer_active() -> bool:
	"""Check if multiplayer is active"""
	return multiplayer.has_multiplayer_peer()

func _is_server() -> bool:
	"""Check if this is the server"""
	return multiplayer.is_server()

# === REQUEST METHODS (Client -> Server) ===

func request_start_mining() -> void:
	"""Client requests to start mining - server validates and broadcasts"""
	var network_id = _get_network_id()
	if network_id.is_empty():
		return

	if _is_multiplayer_active() and not _is_server():
		# Client sends request to server
		_request_start_mining_rpc.rpc_id(1, network_id)
	else:
		# Server or single player - start directly and broadcast
		_broadcast_start_mining(network_id)

func request_complete_mine() -> void:
	"""Client requests to complete mining - server validates and broadcasts"""
	var network_id = _get_network_id()
	if network_id.is_empty():
		return

	if _is_multiplayer_active() and not _is_server():
		_request_complete_mine_rpc.rpc_id(1, network_id)
	else:
		_broadcast_complete_mine(network_id)

func request_loot_taken() -> void:
	"""Client requests loot taken - server validates and broadcasts"""
	var network_id = _get_network_id()
	if network_id.is_empty():
		return

	if _is_multiplayer_active() and not _is_server():
		_request_loot_taken_rpc.rpc_id(1, network_id)
	else:
		_broadcast_loot_taken(network_id)

# === SERVER RPC HANDLERS (Client -> Server) ===

@rpc("any_peer", "reliable")
func _request_start_mining_rpc(network_id: String) -> void:
	"""Server receives start mining request from client"""
	if not _is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Security: Validate the requesting player exists
	var game_world = get_node_or_null("/root/GameWorld")
	if not game_world or not game_world.players.has(peer_id):
		push_warning("Rock mine rejected - unknown peer %d" % peer_id)
		return

	if OS.is_debug_build():
		print("⛏️ Server: Rock %s mine started (requested by peer %d)" % [network_id, peer_id])
	_broadcast_start_mining(network_id)

@rpc("any_peer", "reliable")
func _request_complete_mine_rpc(network_id: String) -> void:
	"""Server receives complete mine request from client"""
	if not _is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Security: Validate the requesting player exists
	var game_world = get_node_or_null("/root/GameWorld")
	if not game_world or not game_world.players.has(peer_id):
		push_warning("Rock mine complete rejected - unknown peer %d" % peer_id)
		return

	if OS.is_debug_build():
		print("⛏️ Server: Rock %s mine completed (requested by peer %d)" % [network_id, peer_id])
	_broadcast_complete_mine(network_id)

@rpc("any_peer", "reliable")
func _request_loot_taken_rpc(network_id: String) -> void:
	"""Server receives loot taken request from client"""
	if not _is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()

	# Security: Validate the requesting player exists
	var game_world = get_node_or_null("/root/GameWorld")
	if not game_world or not game_world.players.has(peer_id):
		push_warning("Rock loot rejected - unknown peer %d" % peer_id)
		return

	if OS.is_debug_build():
		print("⛏️ Server: Rock %s loot taken (requested by peer %d)" % [network_id, peer_id])
	_broadcast_loot_taken(network_id)

# === BROADCAST METHODS (Server -> All Clients) ===

func _broadcast_start_mining(network_id: String) -> void:
	"""Server broadcasts start mining to all clients"""
	if _is_multiplayer_active():
		_sync_start_mining.rpc(network_id)

func _broadcast_complete_mine(network_id: String) -> void:
	"""Server broadcasts mine completion to all clients"""
	if _is_multiplayer_active():
		_sync_complete_mine.rpc(network_id)

func _broadcast_loot_taken(network_id: String) -> void:
	"""Server broadcasts loot taken to all clients"""
	if _is_multiplayer_active():
		_sync_loot_taken.rpc(network_id)

# === SYNC RPC HANDLERS (Server -> All Clients) ===

@rpc("authority", "call_local", "reliable")
func _sync_start_mining(network_id: String) -> void:
	"""All clients receive start mining notification"""
	# Only apply if this is NOT the rock being mined locally by us
	if is_mining:
		return  # Already mining locally, don't double-apply

	print("⛏️ [Sync] Rock %s mine started (remote)" % network_id)

	# Visual feedback for remote player mining
	is_mining = true
	mine_progress = 0.0
	play_random_mine_sound()

@rpc("authority", "call_local", "reliable")
func _sync_complete_mine(network_id: String) -> void:
	"""All clients receive mine completion notification"""
	print("⛏️ [Sync] Rock %s mine completed" % network_id)

	# Stop local mining state
	is_mining = false
	mine_progress = 0.0

	if progress_circle:
		progress_circle.visible = false

	# Play break sound
	play_random_break_sound()

	# Skip if already harvested
	if is_harvested:
		return

	# Perform the rock mine (visual effects, loot generation)
	mine_rock()

	# Update harvested state in ChunkBasedPropSystem
	var prop_system = get_node_or_null("/root/ChunkBasedPropSystem")
	if prop_system:
		prop_system.harvestable_states[network_id] = {
			"is_harvested": true,
			"is_mined": true,
			"has_loot": rock_loot.size() > 0
		}

@rpc("authority", "call_local", "reliable")
func _sync_loot_taken(network_id: String) -> void:
	"""All clients receive loot taken notification"""
	print("⛏️ [Sync] Rock %s loot taken" % network_id)

	# Clear loot
	rock_loot.clear()

	# Remove sparkle effect
	remove_loot_indicator()

	# Hide interaction prompt
	if interaction_prompt:
		interaction_prompt.visible = false

	# Start fade out
	start_fade_out()

	# Update harvested state
	var prop_system = get_node_or_null("/root/ChunkBasedPropSystem")
	if prop_system:
		prop_system.harvestable_states[network_id] = {
			"is_harvested": true,
			"is_mined": true,
			"has_loot": false
		}
		# Also mark in harvested_items so it doesn't respawn on chunk reload
		prop_system.mark_as_harvested(network_id)

# === SYNC PROGRESS (For visual feedback) ===

func sync_mine_progress_network() -> void:
	"""Periodically sync mine progress to other players for visual feedback"""
	if not _is_multiplayer_active():
		return

	network_mine_progress_timer += get_physics_process_delta_time()
	if network_mine_progress_timer >= NETWORK_PROGRESS_SYNC_INTERVAL:
		network_mine_progress_timer = 0.0

		var network_id = _get_network_id()
		if not network_id.is_empty() and is_mining:
			if _is_server():
				_sync_mine_progress.rpc(network_id, mine_progress)
			else:
				_send_mine_progress_to_server.rpc_id(1, network_id, mine_progress)

@rpc("any_peer", "unreliable")
func _send_mine_progress_to_server(network_id: String, progress: float) -> void:
	"""Client sends progress to server, server relays to others"""
	if not _is_server():
		return
	# Relay to all clients except sender
	var sender = multiplayer.get_remote_sender_id()
	for peer_id in multiplayer.get_peers():
		if peer_id != sender:
			_sync_mine_progress.rpc_id(peer_id, network_id, progress)

@rpc("authority", "call_remote", "unreliable")
func _sync_mine_progress(network_id: String, progress: float) -> void:
	"""Receive mine progress from another player"""
	# Only update if we're not the one mining
	if is_mining:
		return

	# Visual feedback - shake rock and play sound
	if progress > mine_progress + 0.1:
		play_random_mine_sound()

	mine_progress = progress
