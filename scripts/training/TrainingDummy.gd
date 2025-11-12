extends StaticBody2D
class_name TrainingDummy

## Training Dummy - Hittable target that spins when hit
## Can be attacked by player for combat practice
## Displays damage numbers and tracks DPS

# Stats
var max_health: float = 999999.0  # Essentially infinite
var current_health: float = 999999.0

# References
var sprite: AnimatedSprite2D = null
var click_area: Area2D = null
var health_bar: Control = null

# Spin animation state
var is_spinning: bool = false
var spin_duration: float = 0.5  # How long the spin lasts
var spin_timer: float = 0.0

# Damage tracking (for training feedback)
var total_damage_dealt: float = 0.0
var last_damage_time: float = 0.0
var damage_window: float = 3.0  # DPS calculation window

# Crit window support (same as Enemy)
var in_crit_window: bool = false
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var weakpoints: Array = []

# Signals
signal damage_taken(damage: float, is_crit: bool)
signal weakpoint_hit_success()
signal crit_window_complete(weakpoints_destroyed: int)
signal died()

func _ready() -> void:

	# Add to enemies group so player can target it
	add_to_group(Constants.GROUP_ENEMIES)

	# Set collision layers (same as enemies)
	collision_layer = 1
	collision_mask = 0  # Doesn't need to detect anything

	# Create sprite
	create_dummy_sprite()

	# Create clickable area
	create_click_area()

	# Create health bar (optional - could just show damage numbers)
	create_health_bar()

	# Create hit flash for visual feedback
	create_hit_flash()

	# Store original scale and modulate for crit window
	original_scale = scale
	await get_tree().process_frame
	original_modulate = self.modulate

func create_dummy_sprite() -> void:
	"""Create animated sprite from dummy spritesheet"""
	const DUMMY_PATH = "res://assets/characters/BODY_Dummy_animation.png"

	if not ResourceLoader.exists(DUMMY_PATH):
		push_error("❌ Dummy texture not found at: " + DUMMY_PATH)
		return

	var dummy_tex: Texture2D = ResourceLoader.load(DUMMY_PATH, "Texture2D")
	if not dummy_tex:
		push_error("❌ Failed to load dummy texture")
		return

	var dummy_img = dummy_tex.get_image()

	# Create animated sprite
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"  # Name it "Sprite" so HitFlash can find it
	sprite.centered = true
	sprite.position = Vector2(0, -32)  # Offset up like player/enemies
	add_child(sprite)

	# Create sprite frames for spin animation
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("idle")
	sprite_frames.add_animation("spin")

	# Idle: Just the first frame
	var idle_frame = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	idle_frame.blit_rect(dummy_img, Rect2i(0, 0, 64, 64), Vector2i(0, 0))
	sprite_frames.add_frame("idle", ImageTexture.create_from_image(idle_frame))
	sprite_frames.set_animation_loop("idle", true)
	sprite_frames.set_animation_speed("idle", 1.0)

	# Spin: All 8 frames
	sprite_frames.set_animation_loop("spin", false)
	sprite_frames.set_animation_speed("spin", 16.0)  # Fast spin

	for i in range(8):
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(dummy_img, Rect2i(i * 64, 0, 64, 64), Vector2i(0, 0))
		sprite_frames.add_frame("spin", ImageTexture.create_from_image(frame_img))

	sprite.sprite_frames = sprite_frames
	sprite.play("idle")

	# Connect animation finished signal
	sprite.animation_finished.connect(_on_animation_finished)

func create_click_area() -> void:
	"""Create Area2D for clicking detection"""
	click_area = Area2D.new()
	click_area.name = "ClickArea"
	click_area.collision_layer = 0
	click_area.collision_mask = 0
	click_area.input_pickable = true
	add_child(click_area)

	# Create circular collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 40.0  # Match enemy size
	collision.shape = shape
	collision.position = Vector2(0, -32)  # Match sprite position
	click_area.add_child(collision)

func create_health_bar() -> void:
	"""Create simple health bar (optional for dummy)"""
	# For now, skip health bar - just show damage numbers
	# Could add a DPS display here later
	pass

func create_hit_flash() -> void:
	"""Create HitFlash node for visual feedback"""
	const HIT_FLASH_SCRIPT = preload("res://scripts/enemies/hitflash.gd")

	var hit_flash = Node.new()
	hit_flash.name = "HitFlash"
	hit_flash.set_script(HIT_FLASH_SCRIPT)
	add_child(hit_flash)

func _physics_process(delta: float) -> void:
	# Handle spin animation timing
	if is_spinning:
		spin_timer += delta
		if spin_timer >= spin_duration:
			is_spinning = false
			spin_timer = 0.0

func take_damage(amount: float, is_crit: bool = false) -> void:
	"""Handle being hit - spin and show damage"""

	# Validate damage
	if is_nan(amount) or is_inf(amount) or amount < 0:
		return

	# Track damage for DPS calculation
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_damage_time > damage_window:
		# Reset tracking if no damage for a while
		total_damage_dealt = amount
	else:
		total_damage_dealt += amount
	last_damage_time = current_time

	# Don't actually reduce health (infinite HP)
	# current_health stays at max

	# Emit signal for player feedback (damage numbers)
	damage_taken.emit(amount, is_crit)

	# Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	# Spawn combat text (same as Enemy)
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	# Set damage text
	combat_text.text = str(int(amount))

	# Determine text type - check if this is a weakpoint hit during crit window
	var is_weakpoint = is_crit and in_crit_window
	if is_weakpoint:
		combat_text.type = 2  # TextType.WEAKPOINT
	elif is_crit:
		combat_text.type = 1  # TextType.CRIT
	else:
		combat_text.type = 0  # TextType.NORMAL

	# Position: spawn in front of player, between player and dummy
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	var spawn_pos = global_position
	if player:
		var direction_to_dummy = (global_position - player.global_position).normalized()
		var distance = player.global_position.distance_to(global_position)
		# Spawn 40% of the way toward dummy (closer to player, in front of player)
		spawn_pos = player.global_position + direction_to_dummy * min(distance * 0.4, 60)

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)

	# Trigger spin animation
	trigger_spin()

func trigger_spin() -> void:
	"""Start spin animation"""
	if not sprite:
		return

	is_spinning = true
	spin_timer = 0.0
	sprite.play("spin")

func _on_animation_finished() -> void:
	"""When spin animation completes, return to idle"""
	if sprite and sprite.animation == "spin":
		sprite.play("idle")

func start_crit_window(difficulty: float = 1.0) -> void:
	"""Start crit window - dummy version (simpler than Enemy)"""
	if in_crit_window:
		return

	in_crit_window = true

	# Change to subtle white for crit window
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)
		# Tell HitFlash the new base color
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(Color(1.0, 1.0, 1.05, 1.0))

	# Scale up animation
	var target_scale = original_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER
	var scale_tween = create_tween()
	scale_tween.tween_property(self, "scale", target_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
	z_index = Constants.CRIT_WINDOW_Z_INDEX

	await scale_tween.finished

	# Spawn weakpoints (simplified - just spawn 1 for practice)
	spawn_weakpoints()

	# Start window timer (4 seconds default)
	var timer = Timer.new()
	timer.wait_time = 4.0 / difficulty
	timer.one_shot = true
	timer.timeout.connect(_on_crit_window_timeout)
	add_child(timer)
	timer.start()

func spawn_weakpoints() -> void:
	"""Spawn a single weakpoint on the dummy for practice"""
	const WEAKPOINT_SCRIPT = preload("res://scripts/enemies/weakpoint.gd")

	# Simple position - center of dummy
	var weakpoint_pos = Vector2(0, -32)

	var weakpoint = Area2D.new()
	weakpoint.set_script(WEAKPOINT_SCRIPT)
	weakpoint.position = weakpoint_pos
	weakpoint.z_index = 150

	# Counter-scale weakpoint to compensate for parent scaling during crit window
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR
	weakpoint.scale = Vector2(counter_scale, counter_scale)

	# Connect weakpoint signal
	weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed)

	add_child(weakpoint)
	weakpoints.append(weakpoint)

func _on_weakpoint_destroyed() -> void:
	"""Handle weakpoint destruction"""
	emit_signal("weakpoint_hit_success")

func _on_crit_window_timeout() -> void:
	"""Crit window expired - return to normal"""
	if not in_crit_window:
		return

	in_crit_window = false

	# Remove any remaining weakpoints
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			weakpoint.queue_free()
	weakpoints.clear()

	# Return to normal size and color
	if sprite:
		sprite.modulate = original_modulate
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(original_modulate)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", original_scale, 0.3)
	tween.tween_property(self, "z_index", 0, 0.3)

	# Emit completion signal
	emit_signal("crit_window_complete", weakpoints.size())
