extends StaticBody2D
class_name TrainingDummy

## Training Dummy - Hittable target that spins when hit
## Can be attacked by player for combat practice
## Displays damage numbers and tracks DPS
## Updated: 2025-01-17 - Remote PC sync fix

# Network ID for multiplayer sync (same as Enemy.gd)
var network_id: int = -1

# Flags for Enemy-like compatibility (not actually used but needed for NetworkEnemyManager)
var is_dying: bool = false
var is_corpse: bool = false

# Stats - Training dummy has more health than regular skeletons but regenerates
var max_health: float = 2000.0  # More than a skeleton (~500) so players can practice
var current_health: float = 2000.0
var regen_threshold: float = 0.15  # Start fighting back when below 15% health
var is_regenerating: bool = false

# "Fighting back" regeneration - dramatic comeback when low HP
var fightback_active: bool = false
var fightback_pulse_count: int = 0
const FIGHTBACK_PULSES: int = 5  # Number of "struggle" pulses before full regen
const MIN_HEALTH_PERCENT: float = 0.05  # Never drop below 5% health

# Enemy-like properties to prevent crashes (dummy can't actually die)
var gold_drop: int = 0  # No gold from training dummy
var corpse_loot: Array = []  # No loot from training dummy
var corpse_gold: int = 0  # No gold from training dummy corpse
var enemy_level: int = 1  # Dummy is level 1

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

# Crit window support (minimal - manager owns lifecycle)
var in_crit_window: bool = false  # Simple flag set by grow/shrink methods
var _crit_window_transitioning: bool = false  # Lock during grow/shrink async operations
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var weakpoints: Array = []  # Just for visual rendering
var _grow_tween: Tween = null  # Track grow tween so shrink can wait for it

# Tutorial arrow indicator
var tutorial_arrow: Node2D = null
var arrow_visible: bool = false
var arrow_tween: Tween = null
var arrow_flash_tween: Tween = null

# Name label (like enemies)
var name_label: Label = null

# Signals for CritWindowManager
signal damage_taken(damage: float, is_crit: bool)
signal weakpoint_spawned(weakpoint: Node)  # Emitted when a weakpoint is created
signal weakpoint_destroyed(weakpoint: Node)  # Emitted when a weakpoint is destroyed
signal died()  # Note: Dummy never actually dies

func _ready() -> void:

	# Add to enemies group so player can target it
	add_to_group(Constants.GROUP_ENEMIES)

	# Add to training_dummy group for tutorial system
	add_to_group("training_dummy")

	# Set collision layers (same as enemies)
	collision_layer = 1
	collision_mask = 0  # Doesn't need to detect anything

	# Create shadow first (so it's behind everything)
	create_shadow()

	# Create sprite
	create_dummy_sprite()

	# Create clickable area
	create_click_area()

	# Create health bar (optional - could just show damage numbers)
	create_health_bar()

	# Create hit flash for visual feedback
	create_hit_flash()

	# Create name label
	create_name_label()

	# Store original scale and modulate for crit window
	original_scale = scale
	await get_tree().process_frame
	original_modulate = self.modulate

	# Create tutorial arrow indicator (shown during ATTACK_DUMMY step)
	create_tutorial_arrow()

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
	"""Create health bar for the training dummy"""
	var health_bar_scene = load("res://scenes/ui/health_bar.tscn")
	if health_bar_scene:
		health_bar = health_bar_scene.instantiate()
		health_bar.name = "HealthBar"
		add_child(health_bar)

		# Set custom offset for training dummy (taller than skeletons)
		# HealthBar uses offset_y of 52 for non-players, but dummy needs ~85
		if health_bar.has_method("set_custom_offset"):
			health_bar.set_custom_offset(85.0)

		# Initialize health display
		if health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

		print("🎯 Training Dummy health bar created")

func create_name_label() -> void:
	"""Create name label above the dummy (like enemies have)"""
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Training Dummy"
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-50, -73)  # Below health bar with spacing (moved up 5px)
	name_label.custom_minimum_size = Vector2(100, 0)  # Set label width for centering
	name_label.z_index = 500
	add_child(name_label)

func create_shadow() -> void:
	"""Create simple dark oval shadow at base of dummy (similar to trees)"""
	var shadow = ColorRect.new()
	shadow.name = "Shadow"
	var shadow_width = 40.0
	var shadow_height = shadow_width * 0.4  # Oval shape
	shadow.size = Vector2(shadow_width, shadow_height)
	# Position at bottom of dummy sprite (sprite center at y=-32, feet at y=0)
	shadow.position = Vector2(-shadow_width / 2, -15)  # At feet level, moved up 10px
	shadow.color = Color(0, 0, 0, 0.5)  # Semi-transparent shadow
	shadow.z_index = -4  # Below dummy

	# Apply oval shader with soft gradient falloff
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
shader_type canvas_item;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;  // Convert to -1 to 1 range
	float dist = length(uv);  // Distance from center
	if (dist > 1.0) {
		discard;  // Make it circular
	}
	// Soft gradient falloff at edges
	float alpha = 1.0 - smoothstep(0.5, 1.0, dist);
	COLOR.a *= alpha;
}
"""
	shader_material.shader = shader
	shadow.material = shader_material

	add_child(shadow)

func create_hit_flash() -> void:
	"""Create HitFlash node for visual feedback"""
	const HIT_FLASH_SCRIPT = preload("res://scripts/enemies/hitflash.gd")

	var hit_flash = Node.new()
	hit_flash.name = "HitFlash"
	hit_flash.set_script(HIT_FLASH_SCRIPT)
	add_child(hit_flash)

func create_tutorial_arrow() -> void:
	"""Create flashing arrow indicator above dummy for tutorial"""
	tutorial_arrow = Node2D.new()
	tutorial_arrow.name = "TutorialArrow"
	tutorial_arrow.position = Vector2(0, -110)  # Above the dummy sprite
	tutorial_arrow.z_index = 200
	tutorial_arrow.visible = false
	tutorial_arrow.scale = Vector2(1.5, 1.5)  # 50% larger
	add_child(tutorial_arrow)

	# Create arrow shape using a Polygon2D (downward pointing arrow)
	var arrow_polygon = Polygon2D.new()
	arrow_polygon.name = "ArrowShape"
	# Arrow pointing down: triangle with a stem
	arrow_polygon.polygon = PackedVector2Array([
		Vector2(0, 20),      # Bottom point (arrow tip)
		Vector2(-15, 0),     # Left wing
		Vector2(-6, 0),      # Left inner
		Vector2(-6, -20),    # Left stem top
		Vector2(6, -20),     # Right stem top
		Vector2(6, 0),       # Right inner
		Vector2(15, 0),      # Right wing
	])
	arrow_polygon.color = Color(0.2, 1.0, 0.2, 1.0)  # Bright green (default)
	tutorial_arrow.add_child(arrow_polygon)

	# Add outline for visibility
	var outline = Line2D.new()
	outline.name = "ArrowOutline"
	outline.points = PackedVector2Array([
		Vector2(0, 20),
		Vector2(-15, 0),
		Vector2(-6, 0),
		Vector2(-6, -20),
		Vector2(6, -20),
		Vector2(6, 0),
		Vector2(15, 0),
		Vector2(0, 20),  # Close the shape
	])
	outline.width = 3.0
	outline.default_color = Color(0.0, 0.3, 0.0, 1.0)  # Dark green outline
	tutorial_arrow.add_child(outline)

	# Connect to TutorialManager signals to show/hide arrow
	if TutorialManager:
		TutorialManager.tutorial_step_completed.connect(_on_tutorial_step_changed)
		TutorialManager.tutorial_completed.connect(hide_tutorial_arrow)
		# Check if already in a tutorial step that shows arrow when spawned
		if TutorialManager.is_tutorial_active():
			var step = TutorialManager.current_step
			if step == TutorialManager.TutorialStep.FIND_DUMMY:
				call_deferred("show_tutorial_arrow_green")
			elif step == TutorialManager.TutorialStep.ATTACK_DUMMY or step == TutorialManager.TutorialStep.CRIT_WINDOW:
				call_deferred("show_tutorial_arrow_red")

func _exit_tree() -> void:
	# Disconnect signals to prevent memory leaks
	if TutorialManager:
		if TutorialManager.tutorial_step_completed.is_connected(_on_tutorial_step_changed):
			TutorialManager.tutorial_step_completed.disconnect(_on_tutorial_step_changed)
		if TutorialManager.tutorial_completed.is_connected(hide_tutorial_arrow):
			TutorialManager.tutorial_completed.disconnect(hide_tutorial_arrow)

func _on_tutorial_step_changed(completed_step: int) -> void:
	"""Handle tutorial step changes to show/hide arrow"""
	if not TutorialManager:
		return

	var current_step = TutorialManager.current_step

	# Show green arrow during FIND_DUMMY step
	if current_step == TutorialManager.TutorialStep.FIND_DUMMY:
		show_tutorial_arrow_green()
	# Show red arrow during ATTACK_DUMMY and CRIT_WINDOW steps
	elif current_step == TutorialManager.TutorialStep.ATTACK_DUMMY or current_step == TutorialManager.TutorialStep.CRIT_WINDOW:
		show_tutorial_arrow_red()
	# HIT_WEAKPOINT step - arrow will be moved to weakpoint by spawn_weakpoints()
	elif current_step == TutorialManager.TutorialStep.HIT_WEAKPOINT:
		# Arrow is already pointing at weakpoint, keep it visible
		pass
	else:
		hide_tutorial_arrow()

func show_tutorial_arrow_green() -> void:
	"""Show bright green flashing arrow (FIND_DUMMY step)"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	# Set arrow color to bright green
	var arrow_shape = tutorial_arrow.get_node_or_null("ArrowShape")
	var arrow_outline = tutorial_arrow.get_node_or_null("ArrowOutline")
	if arrow_shape:
		arrow_shape.color = Color(0.2, 1.0, 0.2, 1.0)  # Bright green
	if arrow_outline:
		arrow_outline.default_color = Color(0.0, 0.4, 0.0, 1.0)  # Dark green outline

	tutorial_arrow.visible = true
	arrow_visible = true

	# Start bobbing and flashing animation
	_start_arrow_animation()

func show_tutorial_arrow_red() -> void:
	"""Show bright red flashing arrow (ATTACK_DUMMY step)"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	# Set arrow color to bright red
	var arrow_shape = tutorial_arrow.get_node_or_null("ArrowShape")
	var arrow_outline = tutorial_arrow.get_node_or_null("ArrowOutline")
	if arrow_shape:
		arrow_shape.color = Color(1.0, 0.2, 0.2, 1.0)  # Bright red
	if arrow_outline:
		arrow_outline.default_color = Color(0.4, 0.0, 0.0, 1.0)  # Dark red outline

	tutorial_arrow.visible = true
	arrow_visible = true

	# Start bobbing and flashing animation
	_start_arrow_animation()

func hide_tutorial_arrow() -> void:
	"""Hide the tutorial arrow"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	tutorial_arrow.visible = false
	arrow_visible = false

	# Stop animations
	if arrow_tween and arrow_tween.is_valid():
		arrow_tween.kill()
		arrow_tween = null
	if arrow_flash_tween and arrow_flash_tween.is_valid():
		arrow_flash_tween.kill()
		arrow_flash_tween = null

func point_arrow_at_weakpoint(weakpoint_pos: Vector2) -> void:
	"""Move and rotate arrow to point at a weakpoint (for HIT_WEAKPOINT tutorial step)"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	# Stop existing animations
	if arrow_tween and arrow_tween.is_valid():
		arrow_tween.kill()
	if arrow_flash_tween and arrow_flash_tween.is_valid():
		arrow_flash_tween.kill()

	# Set arrow color to bright red for weakpoint
	var arrow_shape = tutorial_arrow.get_node_or_null("ArrowShape")
	var arrow_outline = tutorial_arrow.get_node_or_null("ArrowOutline")
	if arrow_shape:
		arrow_shape.color = Color(1.0, 0.2, 0.2, 1.0)  # Bright red
	if arrow_outline:
		arrow_outline.default_color = Color(0.4, 0.0, 0.0, 1.0)  # Dark red outline

	# Position arrow to the right of the weakpoint, pointing left at it
	# Weakpoint pos is in local space (relative to dummy)
	tutorial_arrow.position = Vector2(weakpoint_pos.x + 50, weakpoint_pos.y)
	tutorial_arrow.rotation = PI / 2  # Rotate 90 degrees to point left (arrow tip faces left)

	tutorial_arrow.visible = true
	arrow_visible = true

	# Start a side-to-side bob animation instead of up-down
	arrow_tween = create_tween().set_loops()
	arrow_tween.tween_property(tutorial_arrow, "position:x", weakpoint_pos.x + 40, 0.3).set_ease(Tween.EASE_IN_OUT)
	arrow_tween.tween_property(tutorial_arrow, "position:x", weakpoint_pos.x + 55, 0.3).set_ease(Tween.EASE_IN_OUT)

	# Flash animation
	arrow_flash_tween = create_tween().set_loops()
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 0.3, 0.2)
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 1.0, 0.2)

func reset_arrow_position() -> void:
	"""Reset arrow to default position above dummy"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	tutorial_arrow.position = Vector2(0, -110)
	tutorial_arrow.rotation = 0

func _start_arrow_animation() -> void:
	"""Start the bobbing and flashing animation for the arrow"""
	if arrow_tween and arrow_tween.is_valid():
		arrow_tween.kill()
	if arrow_flash_tween and arrow_flash_tween.is_valid():
		arrow_flash_tween.kill()

	# Create looping tween for bob
	arrow_tween = create_tween().set_loops()

	# Bob up and down
	arrow_tween.tween_property(tutorial_arrow, "position:y", -100.0, 0.4).set_ease(Tween.EASE_IN_OUT)
	arrow_tween.tween_property(tutorial_arrow, "position:y", -120.0, 0.4).set_ease(Tween.EASE_IN_OUT)

	# Create separate tween for the flash effect
	arrow_flash_tween = create_tween().set_loops()
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 0.3, 0.25)
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 1.0, 0.25)

func _physics_process(delta: float) -> void:
	# Handle spin animation timing
	if is_spinning:
		spin_timer += delta
		if spin_timer >= spin_duration:
			is_spinning = false
			spin_timer = 0.0

func take_damage(amount: float, is_crit: bool = false, is_weakpoint_hit: bool = false) -> void:
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

	# Actually reduce health (dummy has real HP but regenerates)
	# Clamp to minimum health - dummy can NEVER die
	var min_health = max_health * MIN_HEALTH_PERCENT
	current_health -= amount
	current_health = max(current_health, min_health)

	# Update health bar
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# Check for "fighting back" trigger (below 15% health)
	if not fightback_active and not is_regenerating and current_health <= max_health * regen_threshold:
		trigger_fightback()

	# Emit signal for player feedback (damage numbers)
	damage_taken.emit(amount, is_crit)

	# Tutorial: notify TutorialManager of dummy hit
	if TutorialManager:
		# Note: keys() index offset by 1 since INACTIVE = -1
		var step_name = TutorialManager.TutorialStep.keys()[TutorialManager.current_step + 1] if TutorialManager.current_step >= -1 else "UNKNOWN"
		print("📚 [Dummy] TutorialManager exists, is_tutorial_active: %s, current_step: %s" % [TutorialManager.is_tutorial_active(), step_name])
		if TutorialManager.is_tutorial_active():
			TutorialManager.on_dummy_hit(is_crit)
			# Check if this was a weakpoint hit during tutorial
			if is_weakpoint_hit:
				TutorialManager.on_weakpoint_hit()
	else:
		print("📚 [Dummy] TutorialManager is null!")

	# Play sounds for dummy hits (dummy is not managed by NetworkEnemyManager, so always play locally)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		# Determine if this is a weakpoint hit (use passed parameter or check crit window)
		var is_weakpoint = is_weakpoint_hit or (is_crit and in_crit_window)

		# Get player's weapon type for weapon-specific sounds
		var weapon_type = "unarmed"
		if CharacterStats.equipped_weapon:
			weapon_type = CharacterStats.equipped_weapon.weapon_type

		# Play hit + hurt sounds (delayed to let swing sound play first)
		var hit_pos = global_position
		get_tree().create_timer(0.1).timeout.connect(func():
			if not is_weakpoint:
				if is_crit:
					sound_manager.play_critical_hit_sound(hit_pos, -6.0)
				else:
					sound_manager.play_normal_hit_sound(hit_pos, -10.0, weapon_type)
			# Hurt sound plays with the hit
			sound_manager.play_skeleton_hurt_sound(hit_pos, -12.0)
		)

	# Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	# Spawn combat text centered at 70% of sprite height (same as Enemy)
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

	# Calculate spawn position at 70% of sprite height (accounting for scale)
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_height = 64.0 * sprite_scale.y  # LPC sprites are 64px tall
	var sprite_pos = sprite.position if sprite else Vector2.ZERO

	# Spawn at 70% height from bottom (30% from top)
	# Sprite is centered, so top is at -height/2
	var spawn_y_offset = -(sprite_height * 0.3)  # 30% from top = 70% from bottom

	# Horizontal and vertical offset based on hit type
	# NORMAL/CRIT: Centered above dummy (x=0)
	# WEAKPOINT: Flanking on left/right sides
	var spawn_x_offset = 0.0  # Normal/crit damage centered
	if is_weakpoint:
		# Weakpoints: offset to sides (flanking the main column)
		# Alternate between left and right sides
		if not has_meta("weakpoint_side"):
			set_meta("weakpoint_side", 1)  # Start with right side

		var side = get_meta("weakpoint_side")
		if side > 0:
			# Right side: +40px
			spawn_x_offset = 40.0
		else:
			# Left side: -40px
			spawn_x_offset = -40.0
		spawn_y_offset -= 15.0  # Slightly higher than main column
		set_meta("weakpoint_side", -side)  # Flip for next hit

	# Final spawn position: dummy center + sprite offset + calculated offset
	var spawn_pos = global_position + sprite_pos + Vector2(spawn_x_offset, spawn_y_offset)

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

func trigger_fightback() -> void:
	"""Dramatic 'fighting back' sequence - dummy struggles then regenerates"""
	fightback_active = true
	is_regenerating = true
	fightback_pulse_count = 0
	print("🎯 Training Dummy fighting back!")

	# Phase 1: Struggle pulses - red flashes with small health gains
	for i in range(FIGHTBACK_PULSES):
		if not is_instance_valid(self):
			return

		fightback_pulse_count = i + 1

		# Red angry flash
		if sprite:
			var pulse_tween = create_tween()
			pulse_tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3, 1.0), 0.1)
			pulse_tween.tween_property(sprite, "modulate", Color(1.0, 0.6, 0.6, 1.0), 0.15)
			await pulse_tween.finished

		# Small health bump during struggle (fighting back!)
		var heal_amount = max_health * 0.08  # 8% per pulse
		current_health = min(current_health + heal_amount, max_health * 0.5)  # Cap at 50% during struggle

		# Update health bar
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

		# Spin on each pulse
		trigger_spin()

		# Wait between pulses
		await get_tree().create_timer(0.25).timeout

	# Phase 2: Victory surge - rapid full regeneration with green glow
	if sprite and is_instance_valid(self):
		print("🎯 Training Dummy surging to full health!")

		# Bright green victory glow
		var surge_tween = create_tween()
		surge_tween.tween_property(sprite, "modulate", Color(0.3, 1.0, 0.3, 1.0), 0.2)

		# Rapidly restore health with visual ticks
		var health_steps = 10
		var health_per_step = (max_health - current_health) / health_steps
		for j in range(health_steps):
			if not is_instance_valid(self):
				return
			current_health = min(current_health + health_per_step, max_health)
			if health_bar and health_bar.has_method("update_health"):
				health_bar.update_health(current_health, max_health)
			await get_tree().create_timer(0.05).timeout

		# Ensure full health
		current_health = max_health
		if health_bar and health_bar.has_method("update_health"):
			health_bar.update_health(current_health, max_health)

		# Fade back to normal
		var fade_tween = create_tween()
		fade_tween.tween_property(sprite, "modulate", Color.WHITE, 0.4)
		await fade_tween.finished

	fightback_active = false
	is_regenerating = false
	print("🎯 Training Dummy regenerated to full health!")

func die() -> void:
	"""Training dummy can't die - trigger fightback instead"""
	print("🎯 Training Dummy refuses to die! Triggering fightback...")
	# Reset to minimum health and trigger fightback
	var min_health = max_health * MIN_HEALTH_PERCENT
	current_health = min_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
	if not fightback_active and not is_regenerating:
		trigger_fightback()

func _on_animation_finished() -> void:
	"""When spin animation completes, return to idle"""
	if sprite and sprite.animation == "spin":
		sprite.play("idle")

func grow_for_crit_window(_difficulty: float = 1.0) -> void:
	"""Visual effect: grow sprite and spawn weakpoints (called by CritWindowManager)"""
	# Guard: Don't start if already in window or currently transitioning
	if in_crit_window or _crit_window_transitioning:
		return

	_crit_window_transitioning = true  # Lock during async grow
	in_crit_window = true  # Set flag for local checks

	# Change to subtle white for crit window
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)
		# Tell HitFlash the new base color
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(Color(1.0, 1.0, 1.05, 1.0))

	# Scale up animation - ONLY SPRITE, not collision box!
	var base_sprite_scale = Vector2.ONE
	var target_sprite_scale = base_sprite_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER
	if sprite:
		_grow_tween = create_tween()
		_grow_tween.set_parallel(true)  # Run all tweens in parallel
		_grow_tween.tween_property(sprite, "scale", target_sprite_scale, Constants.CRIT_WINDOW_SCALE_DURATION)

		# Adjust health bar and name label positions to stay above the growing sprite
		# Sprite center is at y=-32, grows from 64px to 64*2.8=179px
		# Top of grown sprite: -32 - (179/2) = -122
		# Need health bar and label to move up proportionally
		var scale_factor = Constants.CRIT_WINDOW_SCALE_MULTIPLIER
		var base_health_offset = 85.0
		var grown_health_offset = base_health_offset + (64.0 * (scale_factor - 1.0) * 0.5)  # ~142

		if health_bar and health_bar.has_method("set_custom_offset"):
			health_bar.set_custom_offset(grown_health_offset)

		if name_label:
			var base_label_y = -73.0
			var grown_label_y = base_label_y - (64.0 * (scale_factor - 1.0) * 0.5)  # Move up
			_grow_tween.tween_property(name_label, "position:y", grown_label_y, Constants.CRIT_WINDOW_SCALE_DURATION)

		z_index = Constants.CRIT_WINDOW_Z_INDEX

		await _grow_tween.finished
		_grow_tween = null

	# Spawn weakpoints (check we weren't interrupted)
	if in_crit_window and is_instance_valid(self):
		spawn_weakpoints()

		# Tutorial: notify TutorialManager of crit window opening
		if TutorialManager and TutorialManager.is_tutorial_active():
			TutorialManager.on_crit_window_opened()

	_crit_window_transitioning = false  # Unlock after grow complete

func get_crit_window_weakpoint_count() -> int:
	"""Returns the number of weakpoints for this crit window (used for server validation)"""
	# If weakpoints already spawned, return actual count
	if weakpoints.size() > 0:
		return weakpoints.size()

	# Otherwise calculate based on player level
	var player_level = CharacterStats.level
	if player_level >= 21:
		return 3  # Level 21+: All 3 weakpoints
	elif player_level >= 11:
		return 2  # Level 11-20: 2 weakpoints
	else:
		return 1  # Level 1-10: 1 weakpoint

func spawn_weakpoints() -> void:
	"""Spawn weakpoints based on player level (1-3 weakpoints, sectioned)"""

	# Get player level to determine number of weakpoints
	var player_level = CharacterStats.level
	var num_weakpoints = 1

	# Level cap is 30, no stat gains past 25
	# Breakpoints: 1-10 = 1 WP, 11-20 = 2 WP, 21+ = 3 WP
	if player_level >= 21:
		num_weakpoints = 3
	elif player_level >= 11:
		num_weakpoints = 2
	else:
		num_weakpoints = 1

	print("🎯 Training Dummy: Player level %d → spawning %d weakpoint(s)" % [player_level, num_weakpoints])

	# Calculate sprite bounds for random positioning within sections
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_pos = sprite.position  # Local position relative to dummy root

	# LPC sprites are 64x64, sprite is CENTERED (centered = true)
	# Character occupies roughly 32x64 in center of the sprite
	var sprite_width = 32.0 * sprite_scale.x
	var sprite_height = 64.0 * sprite_scale.y

	# Divide into 3 equal sections (in local space)
	var section_height = sprite_height / 3.0
	var sprite_top = sprite_pos.y - (sprite_height / 2.0)

	# Define the 3 sections with their bounds
	var sections = [
		{
			"name": "upper",
			"y_min": sprite_top,
			"y_max": sprite_top + section_height
		},
		{
			"name": "mid",
			"y_min": sprite_top + section_height,
			"y_max": sprite_top + 2.0 * section_height
		},
		{
			"name": "lower",
			"y_min": sprite_top + 2.0 * section_height,
			"y_max": sprite_top + 3.0 * section_height
		}
	]

	# Shuffle sections so we pick random ones
	sections.shuffle()

	var chosen_positions = []

	# Pick exactly 1 weakpoint from each of the first N sections
	for i in range(min(num_weakpoints, sections.size())):
		var section = sections[i]

		# Generate random position within this section's bounds
		# Use 60% of width to avoid edges (20% margin on each side) - increased for better clickability
		var margin_x = sprite_width * 0.2
		var random_x = randf_range(-sprite_width / 2.0 + margin_x, sprite_width / 2.0 - margin_x)

		# Different margins for different sections - increased for better clickability
		var random_y = 0.0
		if section["name"] == "upper":
			# Upper section: 30% margin on top, 15% on bottom (keep away from head edge)
			var margin_top = section_height * 0.30
			var margin_bottom = section_height * 0.15
			random_y = randf_range(section["y_min"] + margin_top, section["y_max"] - margin_bottom)
		elif section["name"] == "lower":
			# Lower section: 15% margin on top, 30% on bottom (keep away from feet edge)
			var margin_top = section_height * 0.15
			var margin_bottom = section_height * 0.30
			random_y = randf_range(section["y_min"] + margin_top, section["y_max"] - margin_bottom)
		else:
			# Middle section: 10% margin on both sides
			var margin_y = section_height * 0.10
			random_y = randf_range(section["y_min"] + margin_y, section["y_max"] - margin_y)

		var random_pos = Vector2(random_x, random_y)

		chosen_positions.append(random_pos)

		print("   🎯 Picked weakpoint in %s section at %s" % [section["name"], random_pos])

	# Spawn weakpoints at chosen positions
	_spawn_weakpoints_internal(chosen_positions)

	# During tutorial, point arrow at first weakpoint
	if TutorialManager and TutorialManager.is_tutorial_active():
		if chosen_positions.size() > 0:
			point_arrow_at_weakpoint(chosen_positions[0])

	# CLIENT-INDEPENDENT: Each player's crit window is LOCAL
	# No broadcasting needed - NetworkEnemyManager notifies specific player to start their local window
	if multiplayer.has_multiplayer_peer():
		print("🌐 Crit window spawned locally (network_id=%d, is_server=%s, %d weakpoints)" % [network_id, multiplayer.is_server(), chosen_positions.size()])

func _spawn_weakpoints_internal(positions: Array) -> void:
	"""Internal helper to spawn weakpoints at given positions."""
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(positions.size()):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		# Set blood theme for training dummy (has blood!)
		weakpoint.color_theme = "blood"

		# ✨ Weakpoints are children of ROOT, positions are in root's local space
		weakpoint.position = positions[i]
		weakpoint.z_index = 150
		# ✨ Make weakpoints 3x larger (300% bigger)
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 3.0

		# Random rotation for dynamic look
		weakpoint.rotation = randf_range(-PI, PI)

		# Connect weakpoint signals to LOCAL handler (not manager)
		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed_local)

		add_child(weakpoint)
		weakpoints.append(weakpoint)

		# Emit signal so CritWindowManager can track it
		weakpoint_spawned.emit(weakpoint)

# NOTE: grow_for_crit_window_client() and spawn_weakpoints_at_positions() were removed
# Client-independent crit windows now use the regular grow_for_crit_window() via CritWindowManager

func _on_weakpoint_hit(weakpoint) -> void:
	"""Handle weakpoint being hit - deal damage and show combat text"""
	# Calculate crit damage using player's base damage
	var base_damage = CharacterStats.get_base_damage()
	var crit_damage = base_damage * Constants.CRIT_DAMAGE_MULTIPLIER

	# CLIENT-PREDICTED: In multiplayer, weakpoint damage is tracked locally during
	# the crit window and reported to server at window end via CritWindowManager.
	# Visual feedback (combat text, sounds) happens immediately for responsiveness.
	var has_peer = multiplayer.has_multiplayer_peer()
	if has_peer and network_id >= 0:
		# Don't apply damage to dummy directly in multiplayer - CritWindowManager handles
		# reporting to server at window end. But DO show visual feedback locally!
		_spawn_weakpoint_combat_text(weakpoint, crit_damage)

		# ✨ FIX: Trigger hit flash for weakpoint hits in multiplayer (was missing!)
		if has_node("HitFlash"):
			get_node("HitFlash").flash(true)  # true = crit/weakpoint flash (red)
		return

	# Single player: deal damage directly with crit flag
	take_damage(crit_damage, true, true)

func _spawn_weakpoint_combat_text(weakpoint, damage: float) -> void:
	"""Spawn combat text for weakpoint hit (used in multiplayer for instant feedback)"""
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	combat_text.text = str(int(damage))
	combat_text.type = 2  # TextType.WEAKPOINT (orange/red)

	# Position at weakpoint location
	var spawn_pos = weakpoint.global_position if is_instance_valid(weakpoint) else global_position
	combat_text.global_position = spawn_pos + Vector2(randf_range(-10, 10), randf_range(-20, 0))
	get_tree().root.add_child(combat_text)

func _on_weakpoint_destroyed_local(weakpoint) -> void:
	"""Local handler - just forward to manager"""
	# Emit signal for manager to handle
	weakpoint_destroyed.emit(weakpoint)

func _clear_weakpoints_delayed() -> void:
	"""Client-side: Clear weakpoints array after a delay to allow destruction RPCs to arrive"""
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		weakpoints.clear()

func shrink_after_crit_window() -> void:
	"""Visual effect: shrink sprite and cleanup weakpoints (called by CritWindowManager)"""
	# Guard: Don't shrink if not in crit window
	if not in_crit_window:
		return

	# Reset tutorial arrow to default position (above dummy) and hide it
	reset_arrow_position()
	hide_tutorial_arrow()

	# Mark as transitioning during async shrink
	_crit_window_transitioning = true
	in_crit_window = false  # Clear flag

	# On CLIENT: Don't clear weakpoints array immediately - the destruction RPC may still be
	# in transit. Let weakpoints free themselves after their destruction animations.
	# On SERVER: Clear array since we've already processed all destruction locally.
	if multiplayer.is_server():
		weakpoints.clear()
	else:
		# Client: Clear array after a delay to allow destruction RPCs to arrive
		_clear_weakpoints_delayed()

	# Reset HitFlash and colors
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("reset"):
			hit_flash.reset()
		hit_flash.set_base_color(Color.WHITE)

	self.modulate = original_modulate
	if sprite:
		sprite.modulate = Color.WHITE

	# Kill grow tween if still running (we're ending the window)
	if _grow_tween and _grow_tween.is_valid():
		_grow_tween.kill()
		_grow_tween = null

	# Wait for weakpoint explosion animation to complete (~0.5s shake + explosion)
	await get_tree().create_timer(0.55).timeout

	# Scale SPRITE back to base and reset health bar/label positions (check we're still valid)
	if is_instance_valid(self) and sprite:
		var base_sprite_scale = Vector2.ONE
		var tween = create_tween()
		tween.set_parallel(true)  # Run all tweens in parallel
		tween.tween_property(sprite, "scale", base_sprite_scale, 0.25)

		# Reset health bar and name label to original positions
		if health_bar and health_bar.has_method("set_custom_offset"):
			health_bar.set_custom_offset(85.0)  # Original offset

		if name_label:
			tween.tween_property(name_label, "position:y", -73.0, 0.25)  # Original position

		await tween.finished

		if is_instance_valid(self) and sprite:
			sprite.scale = base_sprite_scale
			z_index = 0
			sprite.modulate = Color.WHITE

	_crit_window_transitioning = false  # Unlock after shrink complete

## Debug Visualization (F3)
func draw_debug_shapes_world(world_container: Node2D) -> Node2D:
	"""Draw debug shapes for training dummy in world space"""

	# Create temporary container for this dummy's debug shapes
	var dummy_debug = Node2D.new()
	dummy_debug.name = "DummyDebug_" + name
	world_container.add_child(dummy_debug)

	# Draw static collision shape (green - physics body)
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			var rect_shape = collision.shape as RectangleShape2D
			var rect_pos = collision.global_position
			var rect = draw_debug_rect_world(rect_pos, rect_shape.size * scale, Color.GREEN)
			dummy_debug.add_child(rect)

	# Draw click area (cyan - clickable area for attacks)
	# This is just for mouse click detection, NOT the actual attack hitbox!
	# Actual attacks use the player's attack cone which is shown in red on the player
	if has_node("ClickArea"):
		var click_area_node = get_node("ClickArea")
		# Look for CollisionShape2D child
		for child in click_area_node.get_children():
			if child is CollisionShape2D:
				var area_collision = child as CollisionShape2D
				if area_collision.shape is CircleShape2D:
					var circle_shape = area_collision.shape as CircleShape2D
					var circle_pos = area_collision.global_position
					var circle = draw_debug_circle_world(circle_pos, circle_shape.radius * scale.x, Color.CYAN)
					dummy_debug.add_child(circle)
					break

	# ✨ Draw PURPLE boxes - 3 equal sections for weakpoint placement visualization
	if sprite:
		var sprite_scale = sprite.scale
		var sprite_pos = sprite.global_position

		# LPC sprites are 64x64, sprite is CENTERED (centered = true)
		# Character occupies roughly 32x64 in center of the sprite
		var sprite_width = 32.0 * sprite_scale.x
		var sprite_height = 64.0 * sprite_scale.y

		# Divide into 3 equal sections
		var section_height = sprite_height / 3.0

		# Calculate the top of the sprite (sprite is centered)
		var sprite_top = sprite_pos.y - (sprite_height / 2.0)

		# Draw 3 boxes: upper, mid, lower
		var sections = [
			{"name": "upper", "y": sprite_top + section_height / 2.0},
			{"name": "mid", "y": sprite_top + section_height * 1.5},
			{"name": "lower", "y": sprite_top + section_height * 2.5}
		]

		for section in sections:
			var section_center = Vector2(sprite_pos.x, section["y"])
			var section_size = Vector2(sprite_width, section_height)
			var purple_box = draw_debug_rect_world(section_center, section_size, Color.MAGENTA)
			dummy_debug.add_child(purple_box)

	# Draw weakpoint hitboxes (red - if in crit window)
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint) and not weakpoint.is_destroyed:
			if weakpoint.has_node("CollisionShape2D"):
				var wp_collision = weakpoint.get_node("CollisionShape2D")
				if wp_collision.shape is CircleShape2D:
					var wp_shape = wp_collision.shape as CircleShape2D
					var wp_pos = weakpoint.global_position
					var wp_circle = draw_debug_circle_world(wp_pos, wp_shape.radius, Color.RED)
					dummy_debug.add_child(wp_circle)

	return dummy_debug

func draw_debug_circle_world(center: Vector2, radius: float, color: Color) -> Line2D:
	"""Draw a circle in world space for debug visualization"""
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color

	var segments = 32
	for i in range(segments + 1):
		var angle = (i * TAU) / segments
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		line.add_point(point)

	return line

func draw_debug_rect_world(center: Vector2, size: Vector2, color: Color) -> Line2D:
	"""Draw a rectangle in world space for debug visualization"""
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color

	# Draw rectangle outline
	var half_size = size / 2.0
	line.add_point(center + Vector2(-half_size.x, -half_size.y))  # Top-left
	line.add_point(center + Vector2(half_size.x, -half_size.y))   # Top-right
	line.add_point(center + Vector2(half_size.x, half_size.y))    # Bottom-right
	line.add_point(center + Vector2(-half_size.x, half_size.y))   # Bottom-left
	line.add_point(center + Vector2(-half_size.x, -half_size.y))  # Back to top-left

	return line
