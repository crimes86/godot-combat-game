extends CharacterBody2D

# Network ID for multiplayer sync
var network_id: int = -1  # Unique ID assigned by server

# Enemy stats
@export var max_health: float = 500.0
@export var current_health: float = 500.0
@export var base_damage: float = 10.0

# Enemy level and progression
@export var enemy_level: int = 1
@export var xp_reward_base: int = 10  # Base XP, scales with level
var xp_reward: int = 10  # Actual XP granted
@export var gold_drop_base: int = 5  # Base gold drop, scales with level
var gold_drop: int = 5  # Actual gold dropped

# LOD tracking for performance optimization
var current_lod: int = 0  # 0 = full detail, 1 = reduced, 2 = minimal
var lod_update_timer: float = 0.0
const LOD_UPDATE_INTERVAL: float = 0.5  # Check LOD every 0.5s
const LOD_NEAR_DISTANCE: float = 1200.0  # Full detail within this range
const LOD_FAR_DISTANCE: float = 2500.0  # Minimal detail beyond this range
const LOOT_BODY_UI_SCENE: PackedScene = preload("res://scenes/ui/loot_body_ui.tscn")

# Performance: cache player reference (set once at ready, not refreshed every second)
var cached_player: Node = null
var ui_update_timer: float = 0.0
const UI_UPDATE_INTERVAL: float = 0.2  # Update UI visibility 5 times per second

func _get_local_player() -> Node:
	"""Get the local player (handles both single and multiplayer)."""
	# If cached player is still valid and is the local player, use it
	if cached_player and is_instance_valid(cached_player):
		if not multiplayer.has_multiplayer_peer():
			return cached_player
		if cached_player.is_multiplayer_authority():
			return cached_player

	# Find the local player
	var players = get_tree().get_nodes_in_group(Constants.GROUP_PLAYER)
	for player in players:
		if not multiplayer.has_multiplayer_peer():
			# Single player - just use first player
			cached_player = player
			return player
		if player.is_multiplayer_authority():
			# Multiplayer - find the one we control
			cached_player = player
			return player

	# Fallback to first player
	if players.size() > 0:
		cached_player = players[0]
		return players[0]

	return null

# References
@onready var health_bar: Control = $HealthBar
@onready var sprite: CanvasItem = $Sprite2D  # Can be Sprite2D or AnimatedSprite2D
@onready var click_area: Area2D = $Area2D
var level_label: Label = null  # Created dynamically in show_level()
var shadow_sprite: AnimatedSprite2D = null  # Shadow layer
var equipment_sprites: Array[AnimatedSprite2D] = []  # Equipment layers (boots, gloves, helmet)

# Crit window state (minimal - manager owns lifecycle)
var in_crit_window: bool = false  # Simple flag set by grow/shrink methods
var _crit_window_transitioning: bool = false  # Lock during grow/shrink async operations
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE  # Store original difficulty color
var weakpoints: Array = []  # Just for visual rendering
var _grow_tween: Tween = null  # Track grow tween so shrink can wait for it
var is_dying: bool = false

# Tutorial: show red arrow pointing at weakpoints for first 3 crit windows on skeletons
static var skeleton_crit_windows_triggered: int = 0  # Global count of crit windows triggered on skeletons
const TUTORIAL_ARROW_CRIT_WINDOWS: int = 3  # Show arrow for first N crit windows
var tutorial_arrow: Node2D = null  # Arrow indicator for this enemy
var arrow_tween: Tween = null
var arrow_flash_tween: Tween = null

# Corpse state (lootable body system)
var is_corpse: bool = false
var corpse_loot: Array = []  # Generated items for this corpse
var corpse_gold: int = 0  # Gold that can be looted from this corpse
var corpse_creation_time: float = 0.0
var corpse_state: CorpseState.State = CorpseState.State.FRESH
var loot_indicator: Node2D = null  # Visual glow for lootable corpses
var player_in_loot_range: bool = false  # Is player close enough to loot?
var loot_prompt: Label = null  # [F] Loot prompt
var loot_ui_open: bool = false  # Is the loot UI currently open for this corpse?

# Signals for CritWindowManager
signal weakpoint_spawned(weakpoint: Node)  # Emitted when a weakpoint is created
signal weakpoint_destroyed(weakpoint: Node)  # Emitted when a weakpoint is destroyed
signal died()  # Emitted when enemy dies
signal damage_taken(damage: float, is_crit: bool)  # For unified feedback

# Corpse signals
signal corpse_clicked(corpse)  # Emitted when corpse is clicked for looting
signal corpse_looted_empty(corpse)  # Emitted when all items taken from corpse

func _exit_tree() -> void:
	# Unregister from NetworkEnemyManager when freed to prevent "freed instance" crashes
	if network_id > 0:
		var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
		if network_enemy_mgr:
			network_enemy_mgr.unregister_enemy(network_id)

# ============================================
# TTK FRAMEWORK HELPERS
# ============================================

func _calculate_window_damage_for_level(level: int) -> float:
	"""Calculate expected damage from a perfect weakpoint window at a given player level.
	This mirrors CharacterStats.get_window_damage() but without needing the player instance."""

	# Calculate base damage at this level
	# Player stats at level N: STR = 10 + (N-1)*2, starting weapon ~2 damage
	var str_at_level = 10 + (level - 1) * 2
	var stat_damage = 5.0 + (str_at_level - 10) * 0.5
	var weapon_damage = 2.0 + level * 1.5  # Estimated weapon damage scaling

	var base_damage = stat_damage + weapon_damage

	# Crit multiplier
	var crit_mult = Constants.CRIT_DAMAGE_MULTIPLIER if "CRIT_DAMAGE_MULTIPLIER" in Constants else 2.0

	# Weakpoint count scales with level
	var weakpoint_count = 1
	if level >= 21:
		weakpoint_count = 3
	elif level >= 11:
		weakpoint_count = 2

	return base_damage * crit_mult * weakpoint_count

func _ready() -> void:
	# Set collision layers: enemies on layer 1, detect layers 1 (other entities) and 2 (obstacles like trees)
	collision_layer = 1
	collision_mask = 3  # Bitmask: 1 (layer 1) + 2 (layer 2) = 3

	# Determine enemy type for TTK framework
	var is_guardian = get_meta("is_guardian", false)
	var is_boss = is_in_group("boss")

	# ============================================
	# TTK-BASED HP SCALING
	# ============================================
	# HP is calculated to require X weakpoint windows to kill, ensuring
	# consistent TTK regardless of player damage scaling.
	#
	# Formula: HP = window_damage × expected_windows × type_multiplier
	# window_damage scales with enemy level (matching player progression)

	# Calculate expected window damage at this enemy's level
	# This simulates a same-level player fighting this enemy
	var window_damage = _calculate_window_damage_for_level(enemy_level)

	# Determine expected windows and type multiplier
	var expected_windows: int
	var type_mult: float

	if is_boss:
		expected_windows = Constants.TTK_WINDOWS_BOSS if "TTK_WINDOWS_BOSS" in Constants else 7
		type_mult = Constants.TTK_MULT_BOSS if "TTK_MULT_BOSS" in Constants else 4.0
	elif is_guardian:
		expected_windows = Constants.TTK_WINDOWS_ELITE if "TTK_WINDOWS_ELITE" in Constants else 3
		type_mult = Constants.TTK_MULT_ELITE if "TTK_MULT_ELITE" in Constants else 1.75
	else:
		expected_windows = Constants.TTK_WINDOWS_TRASH if "TTK_WINDOWS_TRASH" in Constants else 1
		type_mult = Constants.TTK_MULT_TRASH if "TTK_MULT_TRASH" in Constants else 1.0

	# Calculate HP based on TTK framework
	max_health = window_damage * expected_windows * type_mult

	# Scale damage by enemy level (original formula)
	base_damage = Constants.ENEMY_BASE_DAMAGE * pow(Constants.ENEMY_DAMAGE_SCALING, enemy_level - 1)
	xp_reward = int(xp_reward_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))
	gold_drop = int(gold_drop_base * pow(Constants.ENEMY_XP_GOLD_SCALING, enemy_level - 1))

	# Guardian/Elite buffs (damage, XP, gold - HP already handled by TTK)
	if is_guardian:
		base_damage *= 1.5  # 50% more damage - pressures tank, rewards having a healer
		xp_reward = int(xp_reward * 1.5)  # 50% more XP - worth the challenge
		gold_drop = int(gold_drop * 1.5)  # 50% more gold
		# Note: Guardians also have faster attacks and movement (set in EnemyAI.gd)

	current_health = max_health
	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)
		health_bar.visible = false  # Start hidden, show when player is within 375px
	original_scale = scale  # For general reference

	# ✨ Store original difficulty color (set by GameWorld)
	await get_tree().process_frame  # Wait one frame for GameWorld to set color
	original_modulate = self.modulate

	# ✨ Store sprite's original scale (for crit window scaling)
	# Sprite always starts at Vector2.ONE, but store it just in case
	if sprite:
		sprite.scale = Vector2.ONE  # Ensure sprite starts at base scale

	# Debug: Check what sprite node we have
	if not sprite:
		push_error("❌ Enemy sprite is null! Cannot load skeleton animation.")
		return

	# MULTIPLAYER FIX: Ensure sprite setup runs on all peers
	# Wait a frame to ensure the node is properly in the scene tree
	if multiplayer.has_multiplayer_peer():
		await get_tree().process_frame

	# Create animated skeleton sprite
	if sprite:
		# Check if this is a guardian (uses special armored sprites)
		# Note: is_guardian already declared above for stat buffs

		# Load sprite sheets based on enemy type
		var walk_path: String
		var slash_path: String
		var hurt_path: String

		if is_guardian and enemy_level >= 10:
			# Level 10 guardians: Full copper plate armor (pre-baked sprite)
			walk_path = "res://assets/characters/skeletal_guardian/walk_guardian.png"
			slash_path = "res://assets/characters/skeletal_guardian/slash_guardian.png"
			hurt_path = "res://assets/characters/BODY_skeleton_hurt.png"
		else:
			# Regular skeleton body (level 7-9 guardians use equipment layers)
			walk_path = "res://assets/characters/BODY_skeleton_walk.png"
			slash_path = "res://assets/characters/BODY_skeleton_slash.png"
			hurt_path = "res://assets/characters/BODY_skeleton_hurt.png"

		var walk_tex: Texture2D = null
		var slash_tex: Texture2D = null
		var hurt_tex: Texture2D = null

		# Try to load walking sprite
		if ResourceLoader.exists(walk_path):
			walk_tex = ResourceLoader.load(walk_path, "Texture2D")
			if not walk_tex:
				push_error("❌ Failed to load walk texture: %s" % walk_path)
		else:
			push_error("❌ Walk texture doesn't exist: %s" % walk_path)

		# Try to load attack sprite
		if ResourceLoader.exists(slash_path):
			slash_tex = ResourceLoader.load(slash_path, "Texture2D")
			if not slash_tex:
				push_error("❌ Failed to load slash texture: %s" % slash_path)
		else:
			push_error("❌ Slash texture doesn't exist: %s" % slash_path)

		# Try to load hurt sprite (optional)
		if hurt_path != "" and ResourceLoader.exists(hurt_path):
			hurt_tex = ResourceLoader.load(hurt_path, "Texture2D")
		
		if walk_tex:
			# Store old sprite properties
			var old_position = sprite.position
			var old_scale = sprite.scale
			var old_z_index = sprite.z_index
			
			# Create new AnimatedSprite2D
			var anim_sprite = AnimatedSprite2D.new()
			anim_sprite.name = "Sprite"
			anim_sprite.centered = true
			anim_sprite.position = old_position
			anim_sprite.scale = old_scale
			anim_sprite.modulate = Color.WHITE  # ✨ WHITE, not red!
			anim_sprite.z_index = old_z_index
			anim_sprite.visible = true
			
			# Setup skeleton animations from ALL sprite sheets
			setup_skeleton_animations(anim_sprite, walk_tex, slash_tex, hurt_tex)

			# Verify sprite_frames was set
			if not anim_sprite.sprite_frames:
				push_error("❌ Failed to setup sprite_frames!")
				return

			# Remove old sprite and add animated one
			var old_sprite = sprite
			remove_child(old_sprite)
			old_sprite.queue_free()

			# Create shadow layer (before adding main sprite)
			create_shadow_layer()

			add_child(anim_sprite)
			sprite = anim_sprite

			# Create equipment layers based on enemy level
			create_equipment_layers()

			# Play random idle direction for natural look
			var idle_directions = ["idle_up", "idle_down", "idle_left", "idle_right"]
			var random_idle = idle_directions[randi() % idle_directions.size()]
			if anim_sprite.sprite_frames.has_animation(random_idle):
				anim_sprite.play(random_idle)
			elif anim_sprite.sprite_frames.has_animation("idle_down"):
				anim_sprite.play("idle_down")
			else:
				push_error("❌ idle animations not found!")

			# ✨ FIX: Refresh HitFlash sprite reference after conversion
			if has_node("HitFlash"):
				await get_tree().process_frame  # Wait for scene tree to update
				var hit_flash = get_node("HitFlash")
				hit_flash.sprite = anim_sprite  # Directly set the new sprite
		else:
			# Fallback to red square if texture fails to load
			push_error("⚠️ Failed to load skeleton texture, using RED fallback")
			if sprite is Sprite2D:
				var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
				img.fill(Color.RED)
				sprite.texture = ImageTexture.create_from_image(img)
				sprite.visible = true
				print("   ✅ Red fallback texture set")
			else:
				push_error("   ❌ Sprite is not Sprite2D, cannot set fallback texture")

	
	# Ensure collision shape matches visual
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			# Match collision to sprite size
			collision.shape.size = Vector2(32, 56)
	
	# Add to group
	add_to_group(Constants.GROUP_ENEMIES)
	
	# Add level display
	update_level_display()

	# Connect click area
	if click_area:
		click_area.input_event.connect(_on_click_area_input)

	# FORCE VISIBILITY - Always ensure enemy is visible after initialization
	visible = true
	if sprite:
		sprite.visible = true
	if shadow_sprite:
		shadow_sprite.visible = true

	# Cache local player reference (handles multiplayer correctly)
	cached_player = _get_local_player()

	# VISIBILITY DEBUG: Only log enemies near player spawn (within 500px of origin)
	var dist_from_origin = global_position.length()
	if dist_from_origin < 500:
		print("👁️ [VISIBILITY] %s at (%d, %d) dist=%.0f | enemy.visible=%s, sprite=%s, sprite.visible=%s, z=%d" % [
			name, int(global_position.x), int(global_position.y), dist_from_origin,
			visible,
			sprite.get_class() if sprite else "NONE",
			sprite.visible if sprite else "N/A",
			z_index
		])

func setup_skeleton_animations(anim_sprite: AnimatedSprite2D, walk_tex: Texture2D, slash_tex: Texture2D, hurt_tex: Texture2D = null) -> void:
	"""Setup skeleton animations from separate walk, attack, and hurt sprite sheets"""
	var sprite_frames = SpriteFrames.new()
	
	# Setup WALKING animations from walk texture (9 frames per row)
	if walk_tex:
		var walk_img = walk_tex.get_image()

		# Walk animations - 4 rows (UP, LEFT, DOWN, RIGHT), 9 frames each
		create_skeleton_animation(sprite_frames, walk_img, "walk_up", 0, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_left", 1, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_down", 2, 9, 8.0)
		create_skeleton_animation(sprite_frames, walk_img, "walk_right", 3, 9, 8.0)

		# Idle animations - frame 0 for all directions (neutral standing pose)
		create_skeleton_animation(sprite_frames, walk_img, "idle_up", 0, 1, 1.0, true, 0)
		create_skeleton_animation(sprite_frames, walk_img, "idle_left", 1, 1, 1.0, true, 0)
		create_skeleton_animation(sprite_frames, walk_img, "idle_down", 2, 1, 1.0, true, 0)
		create_skeleton_animation(sprite_frames, walk_img, "idle_right", 3, 1, 1.0, true, 0)

	# Setup ATTACK animations from slash texture (6 frames per row)
	if slash_tex:
		var slash_img = slash_tex.get_image()

		# Attack animations - 4 rows (UP, LEFT, DOWN, RIGHT), 6 frames each
		create_skeleton_animation(sprite_frames, slash_img, "attack_up", 0, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_left", 1, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_down", 2, 6, 12.0, false)
		create_skeleton_animation(sprite_frames, slash_img, "attack_right", 3, 6, 12.0, false)

	# Setup HURT animation from hurt texture (6 frames, single row)
	if hurt_tex:
		var hurt_img = hurt_tex.get_image()

		# Hurt animation - 1 row, 6 frames (getting hit and falling)
		create_skeleton_animation(sprite_frames, hurt_img, "hurt", 0, 6, 10.0, false)

		# Dead animation - last frame of hurt (lying on ground)
		create_skeleton_animation(sprite_frames, hurt_img, "dead", 0, 1, 1.0, true, 5)  # Frame 5 = final fallen pose

	anim_sprite.sprite_frames = sprite_frames

func create_skeleton_animation(sprite_frames: SpriteFrames, skeleton_img: Image, anim_name: String, row: int, frame_count: int, fps: float, loop: bool = true, start_frame: int = 0) -> void:
	"""Create animation from skeleton spritesheet
	start_frame: which frame to start extracting from (useful for idle = middle frame)
	"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	for i in range(frame_count):
		var frame_idx = start_frame + i
		var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(skeleton_img, Rect2i(frame_idx * 64, row * 64, 64, 64), Vector2i(0, 0))

		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

func create_shadow_layer() -> void:
	"""Create animated shadow layer for skeleton"""
	# Load shadow textures
	var shadow_walk_path = "res://assets/characters/shadow/standard/walk.png"
	var shadow_slash_path = "res://assets/characters/shadow/standard/slash.png"

	if not ResourceLoader.exists(shadow_walk_path):
		print("⚠️ Shadow sprites not found, skipping shadow layer")
		return

	var shadow_walk_tex: Texture2D = ResourceLoader.load(shadow_walk_path, "Texture2D")
	var shadow_slash_tex: Texture2D = null
	if ResourceLoader.exists(shadow_slash_path):
		shadow_slash_tex = ResourceLoader.load(shadow_slash_path, "Texture2D")

	# Create shadow sprite
	shadow_sprite = AnimatedSprite2D.new()
	shadow_sprite.name = "ShadowLayer"
	shadow_sprite.centered = true
	shadow_sprite.z_index = -10  # Below skeleton body
	shadow_sprite.modulate = Color(1, 1, 1, 0.6)  # Semi-transparent

	# Create sprite frames for shadow
	var shadow_frames = SpriteFrames.new()

	# Walk animations - 4 rows (UP, LEFT, DOWN, RIGHT), 9 frames each
	if shadow_walk_tex:
		var shadow_walk_img = shadow_walk_tex.get_image()
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_up", 0, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_left", 1, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_down", 2, 9, 8.0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "walk_right", 3, 9, 8.0)

		# Idle animations - frame 0 for all directions (neutral standing pose)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_up", 0, 1, 1.0, true, 0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_left", 1, 1, 1.0, true, 0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_down", 2, 1, 1.0, true, 0)
		create_skeleton_animation(shadow_frames, shadow_walk_img, "idle_right", 3, 1, 1.0, true, 0)

	# Attack animations - 6 frames each
	if shadow_slash_tex:
		var shadow_slash_img = shadow_slash_tex.get_image()
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_up", 0, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_left", 1, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_down", 2, 6, 12.0, false)
		create_skeleton_animation(shadow_frames, shadow_slash_img, "attack_right", 3, 6, 12.0, false)

	shadow_sprite.sprite_frames = shadow_frames
	add_child(shadow_sprite)

	# Start with idle animation
	if shadow_sprite.sprite_frames.has_animation("idle_down"):
		shadow_sprite.play("idle_down")

func create_equipment_layers() -> void:
	"""Create equipment layers based on enemy level"""
	equipment_sprites.clear()

	var is_guardian = get_meta("is_guardian", false)

	# Equipment config based on enemy type and level
	var equipment_to_add: Array[String] = []
	var always_has_weapon: bool = false

	if is_guardian:
		# Guardian equipment varies by level
		if enemy_level >= 10:
			# Level 10: Full copper plate (pre-baked in sprite), just add weapon
			always_has_weapon = true
		elif enemy_level >= 9:
			# Level 9: boots + gloves + helmet + weapon
			equipment_to_add.append("boots")
			equipment_to_add.append("gloves")
			equipment_to_add.append("helmet")
			always_has_weapon = true
		else:
			# Level 7-8: boots + gloves + weapon
			equipment_to_add.append("boots")
			equipment_to_add.append("gloves")
			always_has_weapon = true
	else:
		# Regular skeleton equipment (level 1-6)
		if enemy_level >= 4:
			equipment_to_add.append("boots")
		if enemy_level >= 5:
			equipment_to_add.append("helmet")
		if enemy_level >= 6:
			equipment_to_add.append("gloves")

	# Create each equipment layer
	for equip_name in equipment_to_add:
		var equip_sprite = create_equipment_sprite(equip_name)
		if equip_sprite:
			equipment_sprites.append(equip_sprite)
			add_child(equip_sprite)

	# Weapon handling
	if always_has_weapon or randf() < 0.25:
		# Guardians always have weapon, regular skeletons 25% chance
		var weapons = ["sword", "mace"]
		var weapon_name = weapons[randi() % weapons.size()]
		var weapon_sprite = create_weapon_sprite(weapon_name)
		if weapon_sprite:
			equipment_sprites.append(weapon_sprite)
			add_child(weapon_sprite)

func create_equipment_sprite(equip_name: String) -> AnimatedSprite2D:
	"""Create an animated sprite for a piece of equipment"""
	var walk_path = "res://assets/characters/equipment/%s_walk.png" % equip_name
	var slash_path = "res://assets/characters/equipment/%s_slash.png" % equip_name

	if not ResourceLoader.exists(walk_path):
		return null

	var walk_tex: Texture2D = ResourceLoader.load(walk_path, "Texture2D")
	var slash_tex: Texture2D = null
	if ResourceLoader.exists(slash_path):
		slash_tex = ResourceLoader.load(slash_path, "Texture2D")

	if not walk_tex:
		return null

	var equip_sprite = AnimatedSprite2D.new()
	equip_sprite.name = "Equipment_" + equip_name
	equip_sprite.centered = true
	equip_sprite.z_index = 1  # Above skeleton body

	# Create sprite frames
	var equip_frames = SpriteFrames.new()
	var walk_img = walk_tex.get_image()

	# Walk animations - 4 rows, 9 frames each
	create_skeleton_animation(equip_frames, walk_img, "walk_up", 0, 9, 8.0)
	create_skeleton_animation(equip_frames, walk_img, "walk_left", 1, 9, 8.0)
	create_skeleton_animation(equip_frames, walk_img, "walk_down", 2, 9, 8.0)
	create_skeleton_animation(equip_frames, walk_img, "walk_right", 3, 9, 8.0)

	# Idle animations - frame 0 for all directions (neutral standing pose)
	create_skeleton_animation(equip_frames, walk_img, "idle_up", 0, 1, 1.0, true, 0)
	create_skeleton_animation(equip_frames, walk_img, "idle_left", 1, 1, 1.0, true, 0)
	create_skeleton_animation(equip_frames, walk_img, "idle_down", 2, 1, 1.0, true, 0)
	create_skeleton_animation(equip_frames, walk_img, "idle_right", 3, 1, 1.0, true, 0)

	# Attack animations - 6 frames each
	if slash_tex:
		var slash_img = slash_tex.get_image()
		create_skeleton_animation(equip_frames, slash_img, "attack_up", 0, 6, 12.0, false)
		create_skeleton_animation(equip_frames, slash_img, "attack_left", 1, 6, 12.0, false)
		create_skeleton_animation(equip_frames, slash_img, "attack_down", 2, 6, 12.0, false)
		create_skeleton_animation(equip_frames, slash_img, "attack_right", 3, 6, 12.0, false)

	equip_sprite.sprite_frames = equip_frames
	return equip_sprite

func create_weapon_sprite(weapon_name: String) -> AnimatedSprite2D:
	"""Create an animated sprite for a weapon"""
	var walk_path = "res://assets/equipment/weapons/%s/walk.png" % weapon_name
	var slash_path = "res://assets/equipment/weapons/%s/slash.png" % weapon_name

	if not ResourceLoader.exists(walk_path):
		return null

	var walk_tex: Texture2D = ResourceLoader.load(walk_path, "Texture2D")
	var slash_tex: Texture2D = null
	if ResourceLoader.exists(slash_path):
		slash_tex = ResourceLoader.load(slash_path, "Texture2D")

	if not walk_tex:
		return null

	var weapon_sprite = AnimatedSprite2D.new()
	weapon_sprite.name = "Weapon_" + weapon_name
	weapon_sprite.centered = true
	weapon_sprite.z_index = 2  # Above equipment and skeleton body

	# Create sprite frames
	var weapon_frames = SpriteFrames.new()
	var walk_img = walk_tex.get_image()

	# Walk animations - 4 rows, 9 frames each (64x64)
	create_skeleton_animation(weapon_frames, walk_img, "walk_up", 0, 9, 8.0)
	create_skeleton_animation(weapon_frames, walk_img, "walk_left", 1, 9, 8.0)
	create_skeleton_animation(weapon_frames, walk_img, "walk_down", 2, 9, 8.0)
	create_skeleton_animation(weapon_frames, walk_img, "walk_right", 3, 9, 8.0)

	# Idle animations - frame 0 for all directions (64x64, neutral standing pose)
	create_skeleton_animation(weapon_frames, walk_img, "idle_up", 0, 1, 1.0, true, 0)
	create_skeleton_animation(weapon_frames, walk_img, "idle_left", 1, 1, 1.0, true, 0)
	create_skeleton_animation(weapon_frames, walk_img, "idle_down", 2, 1, 1.0, true, 0)
	create_skeleton_animation(weapon_frames, walk_img, "idle_right", 3, 1, 1.0, true, 0)

	# Attack animations - 6 frames each (192x192 oversize, scaled down)
	if slash_tex:
		var slash_img = slash_tex.get_image()
		create_oversize_weapon_animation(weapon_frames, slash_img, "attack_up", 0, 6, 12.0, false)
		create_oversize_weapon_animation(weapon_frames, slash_img, "attack_left", 1, 6, 12.0, false)
		create_oversize_weapon_animation(weapon_frames, slash_img, "attack_down", 2, 6, 12.0, false)
		create_oversize_weapon_animation(weapon_frames, slash_img, "attack_right", 3, 6, 12.0, false)

	weapon_sprite.sprite_frames = weapon_frames
	return weapon_sprite

func create_oversize_weapon_animation(sprite_frames: SpriteFrames, img: Image, anim_name: String, row: int, frame_count: int, fps: float, loop: bool = true) -> void:
	"""Create animation from oversize weapon spritesheet (192x192 frames)

	LPC oversize weapon sprites are designed to overlay on the character at full size.
	The weapon swings wide beyond the 64x64 body frame, so we keep 192x192 dimensions.
	Since both body and weapon sprites use centered=true, they align correctly.
	"""
	sprite_frames.add_animation(anim_name)
	sprite_frames.set_animation_loop(anim_name, loop)
	sprite_frames.set_animation_speed(anim_name, fps)

	const OVERSIZE_FRAME = 192

	for i in range(frame_count):
		var frame_img = Image.create(OVERSIZE_FRAME, OVERSIZE_FRAME, false, Image.FORMAT_RGBA8)
		frame_img.blit_rect(img, Rect2i(i * OVERSIZE_FRAME, row * OVERSIZE_FRAME, OVERSIZE_FRAME, OVERSIZE_FRAME), Vector2i(0, 0))

		# Keep at 192x192 - LPC oversize weapons are designed to overlay at full size
		var frame_texture = ImageTexture.create_from_image(frame_img)
		sprite_frames.add_frame(anim_name, frame_texture)

func sync_equipment_animations() -> void:
	"""Sync all equipment layers to match the main sprite's animation"""
	if not sprite or not sprite is AnimatedSprite2D:
		return

	var main_sprite = sprite as AnimatedSprite2D
	var current_anim = main_sprite.animation
	var current_frame = main_sprite.frame

	for equip_sprite in equipment_sprites:
		if is_instance_valid(equip_sprite) and equip_sprite.sprite_frames:
			if equip_sprite.sprite_frames.has_animation(current_anim):
				if equip_sprite.animation != current_anim:
					equip_sprite.play(current_anim)
				equip_sprite.frame = current_frame

func get_enemy_name() -> String:
	"""Generate enemy name based on level and type"""
	var is_guardian = get_meta("is_guardian", false)

	# Name prefixes based on level ranges
	var prefix = ""
	if enemy_level <= 3:
		prefix = "Skeleton"
	elif enemy_level <= 5:
		prefix = "Restless Skeleton"
	elif enemy_level <= 7:
		prefix = "Cursed Skeleton"
	elif enemy_level <= 9:
		prefix = "Dark Skeleton"
	else:
		prefix = "Ancient Skeleton"

	# Guardian modifier
	if is_guardian:
		prefix = "Guardian " + prefix

	return prefix

func get_con_color(player_level: int) -> Color:
	"""Get con (consider) color based on level difference with player
	Classic MMO con system:
	- Gray: 6+ levels below (trivial, no XP)
	- Green: 3-5 levels below (easy)
	- Blue: 1-2 levels below (moderate)
	- White: Same level (even match)
	- Yellow: 1-2 levels above (challenging)
	- Orange: 3-4 levels above (difficult)
	- Red: 5+ levels above (deadly)
	"""
	var level_diff = enemy_level - player_level

	if level_diff <= -6:
		return Color(0.6, 0.6, 0.6)  # Gray (trivial)
	elif level_diff <= -3:
		return Color(0.2, 1.0, 0.2)  # Green (easy)
	elif level_diff <= -1:
		return Color(0.4, 0.6, 1.0)  # Blue (moderate)
	elif level_diff == 0:
		return Color(1.0, 1.0, 1.0)  # White (even)
	elif level_diff <= 2:
		return Color(1.0, 1.0, 0.0)  # Yellow (challenging)
	elif level_diff <= 4:
		return Color(1.0, 0.6, 0.0)  # Orange (difficult)
	else:
		return Color(1.0, 0.2, 0.2)  # Red (deadly)

func update_level_display() -> void:
	"""Show enemy level on sprite"""
	if enemy_level >= 1:  # Show for all enemies including level 1
		# Create name label (shows enemy name with con color)
		level_label = Label.new()
		level_label.text = get_enemy_name()
		level_label.add_theme_font_size_override("font_size", 12)
		# Color will be set dynamically in _process based on player level
		level_label.add_theme_color_override("font_color", Color.WHITE)  # Default white
		level_label.add_theme_color_override("font_outline_color", Color.BLACK)
		level_label.add_theme_constant_override("outline_size", 2)
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER  # Center the text
		level_label.position = Vector2(-50, -42)  # Directly above enemy head (close to head)
		level_label.custom_minimum_size = Vector2(100, 0)  # Set label width for centering
		level_label.z_index = 500
		level_label.visible = false  # Start hidden, show when player is within 800px
		add_child(level_label)

func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# If this is a corpse, handle right-click for looting
	if is_corpse and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click on corpse - trigger loot UI
			corpse_clicked.emit(self)
			get_viewport().set_input_as_handled()
			return

	# Let Player handle ALL clicks for living enemies (including crit window)
	# This prevents double-damage bugs where both Player and Enemy handle the same click
	return

func take_damage(amount: float, is_crit: bool = false, is_weakpoint_hit: bool = false) -> void:
	if is_dying:
		return

	# Validate amount
	if is_nan(amount) or is_inf(amount) or amount < 0:
		print("ERROR: Invalid damage amount: ", amount)
		return

	if current_health <= 0:
		return

	current_health -= amount
	current_health = max(current_health, 0.0)

	Constants.log_combat("Enemy hit! Damage: %d (Crit: %s, Weakpoint: %s) | Health: %d/%d" % [amount, is_crit, is_weakpoint_hit, current_health, max_health])

	# ✨ NEW: Emit signal for player to handle feedback
	damage_taken.emit(amount, is_crit)

	# ✨ NEW: Trigger hit flash visual feedback
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("flash"):
			hit_flash.flash(is_crit)

	if health_bar and health_bar.has_method("update_health"):
		health_bar.update_health(current_health, max_health)

	# ✨ NEW: Spawn combat text centered at 70% of sprite height
	var combat_text_scene = preload("res://scenes/ui/combat_text.tscn")
	var combat_text = combat_text_scene.instantiate()

	# Set damage text
	combat_text.text = str(int(amount))

	# Determine text type based on parameters
	if is_weakpoint_hit:
		combat_text.type = 2  # TextType.WEAKPOINT (orange)
	elif is_crit:
		combat_text.type = 1  # TextType.CRIT (yellow)
		# NOTE: Critical hit sound is now handled by NetworkEnemyManager._play_hit_sounds()
		# in multiplayer, or in the else branch below for single player
	else:
		combat_text.type = 0  # TextType.NORMAL (white)

	# Calculate spawn position at 70% of sprite height (accounting for scale)
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_height = 64.0 * sprite_scale.y  # LPC sprites are 64px tall
	var sprite_pos = sprite.position if sprite else Vector2.ZERO

	# Spawn at 70% height from bottom (30% from top)
	# Sprite is centered, so top is at -height/2
	var spawn_y_offset = -(sprite_height * 0.3)  # 30% from top = 70% from bottom

	# Horizontal and vertical offset based on hit type
	# NORMAL/CRIT: Centered above enemy (x=0)
	# WEAKPOINT: Flanking on left/right sides
	var spawn_x_offset = 0.0  # Normal/crit damage centered
	if is_weakpoint_hit:
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

	# Final spawn position: enemy center + sprite offset + calculated offset
	var spawn_pos = global_position + sprite_pos + Vector2(spawn_x_offset, spawn_y_offset)

	combat_text.global_position = spawn_pos
	get_tree().root.add_child(combat_text)
	
	# ✨ Play hit sound
	# NOTE: In multiplayer, NetworkEnemyManager._client_enemy_damaged() handles ALL hit sounds
	# via _play_hit_sounds(). We only play sounds here in single player to avoid duplicates.
	# Weakpoint sounds are handled in weakpoint.gd directly (separate system).
	var has_peer = multiplayer.has_multiplayer_peer()
	if not is_weakpoint_hit and not has_peer:
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			# Get player's weapon type for weapon-specific sounds
			var weapon_type = ""
			if CharacterStats.equipped_weapon:
				weapon_type = CharacterStats.equipped_weapon.weapon_type

			if is_crit:
				sound_manager.play_critical_hit_sound(global_position, -6.0)
			else:
				sound_manager.play_normal_hit_sound(global_position, -10.0, weapon_type)

			# Play skeleton hurt reaction sound (for all hit types)
			sound_manager.play_skeleton_hurt_sound(global_position, -12.0)
	
	# ✨ NEW: Trigger hit flash locally (always works)
	if has_node("HitFlash"):
		get_node("HitFlash").flash(is_crit)

	if current_health <= 0:
		die()

func grow_for_crit_window(_difficulty: float = 1.0) -> void:
	"""Visual effect: grow sprite and spawn weakpoints (called by CritWindowManager)"""
	# Guard: Don't start if dying, already in window, or currently transitioning
	if is_dying or in_crit_window or _crit_window_transitioning:
		return

	_crit_window_transitioning = true  # Lock during async grow
	in_crit_window = true  # Set flag for local checks

	# Reset parent to neutral and change sprite to subtle white for crit window
	self.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 1.05, 1.0)  # Barely brighter than normal
		if has_node("HitFlash"):
			get_node("HitFlash").set_base_color(Color(1.0, 1.0, 1.05, 1.0))

	# Sprite always starts at Vector2.ONE (base scale)
	var base_sprite_scale = Vector2.ONE
	var target_sprite_scale = base_sprite_scale * Constants.CRIT_WINDOW_SCALE_MULTIPLIER

	# Check sprite scale, not root node scale (since we only scale sprite now)
	var current_sprite_scale = sprite.scale if sprite else Vector2.ONE
	if current_sprite_scale.x >= target_sprite_scale.x * Constants.CRIT_WINDOW_SCALE_THRESHOLD:
		# Already at target scale, spawn weakpoints immediately
		spawn_weakpoints()
	else:
		# Scale the sprite (not collision box) for visual growth
		if sprite:
			_grow_tween = create_tween()
			_grow_tween.set_parallel(false)
			_grow_tween.tween_property(sprite, "scale", target_sprite_scale, Constants.CRIT_WINDOW_SCALE_DURATION)
			z_index = Constants.CRIT_WINDOW_Z_INDEX
			await _grow_tween.finished
			_grow_tween = null

		# Spawn weakpoints AFTER growth (check we weren't interrupted)
		if in_crit_window and is_instance_valid(self):
			spawn_weakpoints()

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
	# Don't spawn weakpoints if enemy is already dying/dead
	if is_dying or is_corpse:
		return

	# Calculate weakpoint count based on CURRENT PLAYER level (when crit triggers, not when enemy spawned)
	# Level cap is 30, no stat gains past 25
	var player_level = CharacterStats.level
	var num_weakpoints = 1  # Default to 1
	if player_level >= 21:
		num_weakpoints = 3  # Level 21+: All 3 weakpoints
	elif player_level >= 11:
		num_weakpoints = 2  # Level 11-20: 2 weakpoints
	else:
		num_weakpoints = 1  # Level 1-10: 1 weakpoint

	# print("🎯 Calculating weakpoints: Player level %d → %d weakpoints" % [player_level, num_weakpoints])

	# Calculate sprite bounds for random positioning within sections
	var sprite_scale = sprite.scale if sprite else Vector2.ONE
	var sprite_pos = sprite.position  # Local position relative to enemy root

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

	# Slightly smaller scale for better fit
	var counter_scale = 1.0 / Constants.WEAKPOINT_COUNTER_SCALE_DIVISOR

	for i in range(chosen_positions.size()):
		var weakpoint_scene = preload("res://scenes/enemies/weakpoint.tscn")
		var weakpoint = weakpoint_scene.instantiate()

		# Set bone theme for skeletons (no blood!)
		weakpoint.color_theme = "bone"

		# ✨ Weakpoints are children of ROOT, positions are in root's local space
		weakpoint.position = chosen_positions[i]
		# ✨ Make weakpoints 3x larger (300% bigger)
		weakpoint.scale = Vector2(counter_scale, counter_scale) * 3.0

		# ✨ RANDOM ROTATION for dynamic look!
		weakpoint.rotation = randf_range(-PI, PI)

		# Connect weakpoint signals - handle damage and forward to manager
		weakpoint.weakpoint_hit.connect(_on_weakpoint_hit)
		weakpoint.weakpoint_destroyed.connect(_on_weakpoint_destroyed_local)

		add_child(weakpoint)
		weakpoints.append(weakpoint)

		# Emit signal so CritWindowManager can track it
		weakpoint_spawned.emit(weakpoint)

	# Tutorial: Show red arrow pointing at first weakpoint for the first N crit windows
	skeleton_crit_windows_triggered += 1
	if skeleton_crit_windows_triggered <= TUTORIAL_ARROW_CRIT_WINDOWS and chosen_positions.size() > 0:
		create_and_show_weakpoint_arrow(chosen_positions[0])

	# CLIENT-INDEPENDENT: Each player's crit window is LOCAL
	# No broadcasting needed - NetworkEnemyManager notifies specific player to start their local window

# NOTE: grow_for_crit_window_client() and spawn_weakpoints_at_positions() were removed
# Client-independent crit windows now use the regular grow_for_crit_window() via CritWindowManager

# 🔍 DEBUG VISUALIZATION - Shows where all 17 positions are!
func _draw() -> void:
	pass
	# Only draw if we have weakpoints spawned
	# if weakpoints.is_empty():
	# 	return

	# print("🔍 DEBUG: Drawing position circles (17 red dots + 3 green dots)")

	# Draw circles at ALL 17 possible positions (optimized spread)
	# var position_pool = [
	# 	# Upper (5)
	# 	Vector2(0, -14), Vector2(-6, -11), Vector2(6, -11),
	# 	Vector2(-8, -6), Vector2(8, -6),
	# 	# Mid (9)
	# 	Vector2(0, -3), Vector2(-6, -2), Vector2(6, -2),
	# 	Vector2(-5, 1), Vector2(5, 1), Vector2(0, 3),
	# 	Vector2(-5, 5), Vector2(5, 5), Vector2(0, 7),
	# 	# Lower (3)
	# 	Vector2(-4, 10), Vector2(4, 10), Vector2(0, 12)
	# ]

	# Draw small red circles at each possible position
	# for pos in position_pool:
	# 	draw_circle(pos, 3, Color(1, 0, 0, 0.7))  # Red

	# Draw larger green circles at the 3 chosen positions
	# for weakpoint in weakpoints:
	# 	if is_instance_valid(weakpoint):
	# 		draw_circle(weakpoint.position, 5, Color(0, 1, 0, 0.9))  # Bright green

	# print("🔍 DEBUG: Drew %d red circles and %d green circles" % [position_pool.size(), weakpoints.size()])

# Keep redrawing while in crit window
func _process(delta: float) -> void:
	if in_crit_window and not weakpoints.is_empty():
		queue_redraw()  # Continuously redraw while weakpoints are active

	# Sync equipment animations with main sprite
	if equipment_sprites.size() > 0:
		sync_equipment_animations()

	# Toggle UI based on player distance (visibility handled by LOD system)
	if not is_corpse:  # Only for living enemies
		# Throttle UI updates - don't need 60 FPS for visibility checks
		ui_update_timer += delta
		if ui_update_timer < UI_UPDATE_INTERVAL:
			return
		ui_update_timer = 0.0

		# Refresh cached_player if null or invalid (needed for multiplayer clients)
		if not cached_player or not is_instance_valid(cached_player):
			cached_player = _get_local_player()

		if cached_player and is_instance_valid(cached_player):
			var distance = global_position.distance_to(cached_player.global_position)

			# === LOD SYSTEM ===
			lod_update_timer += delta
			if lod_update_timer >= LOD_UPDATE_INTERVAL:
				lod_update_timer = 0.0
				update_lod(distance)

			# Decoupled UI visibility thresholds
			var show_level_label = distance <= 800.0  # Level shows at 800px
			var show_healthbar = distance <= 400.0    # Healthbar shows at 400px

			# Update level label visibility and con color
			# Name stays close to head (-48), healthbar appears above it (-58 in HealthBar.gd)
			if level_label:
				level_label.visible = show_level_label

				# Update con color based on player level (only when visible)
				if show_level_label:
					var player_level = CharacterStats.level
					var con_color = get_con_color(player_level)
					level_label.add_theme_color_override("font_color", con_color)

			# Update healthbar visibility (position is handled by HealthBar.gd)
			if health_bar:
				health_bar.visible = show_healthbar
		return

	# Handle corpse decay and interaction
	if is_corpse:
		process_corpse_decay(delta)
		update_loot_proximity()

func update_lod(distance: float) -> void:
	"""Update LOD level based on distance to player"""
	var new_lod: int
	if distance < LOD_NEAR_DISTANCE:
		new_lod = 0  # Full detail
	elif distance < LOD_FAR_DISTANCE:
		new_lod = 1  # Reduced detail
	else:
		new_lod = 2  # Minimal detail

	# Only update if LOD changed
	if new_lod != current_lod:
		current_lod = new_lod
		apply_lod_settings()

func apply_lod_settings() -> void:
	"""Apply visual settings based on current LOD level"""
	match current_lod:
		0:  # Full detail - everything visible and animating
			if shadow_sprite:
				shadow_sprite.visible = true
			if sprite and sprite is AnimatedSprite2D:
				sprite.speed_scale = 1.0
			# Enable processing for animations
			set_process(true)
		1:  # Reduced detail - hide shadow, slower animations
			if shadow_sprite:
				shadow_sprite.visible = false
			if sprite and sprite is AnimatedSprite2D:
				sprite.speed_scale = 0.5  # Half speed animations
		2:  # Minimal detail - no shadow, pause animations
			if shadow_sprite:
				shadow_sprite.visible = false
			if sprite and sprite is AnimatedSprite2D:
				sprite.speed_scale = 0.0  # Pause animations (shows idle frame)

func set_lod_level(lod_level: int) -> void:
	"""Set LOD level directly (for external calls)"""
	current_lod = lod_level
	apply_lod_settings()

func update_loot_proximity() -> void:
	"""Check if player is close enough to loot and show/hide prompt"""
	# Use local player (handles multiplayer correctly)
	var player = _get_local_player()
	if not player:
		player_in_loot_range = false
		if loot_prompt:
			loot_prompt.visible = false
		# Unregister if we were in range
		InteractionManager.unregister_interactable(self)
		return

	# Check distance to player
	var distance = global_position.distance_to(player.global_position)
	var was_in_range = player_in_loot_range
	player_in_loot_range = distance <= 80.0  # Same range as chest interaction

	# Register/unregister with InteractionManager
	if player_in_loot_range and (corpse_gold > 0 or corpse_loot.size() > 0):
		if not was_in_range:
			InteractionManager.register_interactable(self, InteractionManager.InteractionType.LOOT_BODY, distance)
		else:
			# Update distance
			InteractionManager.register_interactable(self, InteractionManager.InteractionType.LOOT_BODY, distance)
	elif was_in_range:
		InteractionManager.unregister_interactable(self)

	# Check if we're the active interactable
	var is_active = InteractionManager.is_active_interactable(self)

	# Update prompt visibility (show if has gold OR items, UI not open, AND we're active)
	if player_in_loot_range and (corpse_gold > 0 or corpse_loot.size() > 0) and not loot_ui_open and is_active:
		if not loot_prompt:
			create_loot_prompt()
		loot_prompt.visible = true
		update_loot_prompt_position()
	else:
		if loot_prompt:
			loot_prompt.visible = false

func _unhandled_input(event: InputEvent) -> void:
	"""Handle F-key input for looting (only if not handled by other nodes)"""
	if not is_corpse:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		if player_in_loot_range and (corpse_gold > 0 or corpse_loot.size() > 0):
			print("💀 Corpse handling F-key (unhandled input)")
			open_loot_ui()
			get_viewport().set_input_as_handled()

func create_loot_prompt() -> void:
	"""Create [F] Loot prompt above corpse"""
	if loot_prompt:
		return

	var canvas = CanvasLayer.new()
	canvas.name = "LootPromptCanvas"
	canvas.layer = 50
	add_child(canvas)

	loot_prompt = Label.new()
	loot_prompt.name = "LootPrompt"
	loot_prompt.text = "[F] Loot"
	loot_prompt.add_theme_font_size_override("font_size", 16)
	loot_prompt.add_theme_color_override("font_color", Color(1.0, 1.0, 0.8))  # Yellow-white
	loot_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	loot_prompt.add_theme_constant_override("outline_size", 2)
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_prompt.visible = false
	canvas.add_child(loot_prompt)

func update_loot_prompt_position() -> void:
	"""Update prompt position to stay above corpse"""
	if not loot_prompt:
		return

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return

	# Position prompt above corpse
	var prompt_world_pos = global_position + Vector2(0, -40)
	var camera_pos = camera.global_position
	var screen_center = viewport_size / 2
	var prompt_screen_pos = (prompt_world_pos - camera_pos) * camera.zoom.x + screen_center

	# Center horizontally
	var screen_x = prompt_screen_pos.x
	if loot_prompt.size.x > 0:
		screen_x -= loot_prompt.size.x / 2
	var screen_y = prompt_screen_pos.y

	loot_prompt.position = Vector2(screen_x, screen_y)

func open_loot_ui() -> void:
	"""Open loot UI for this corpse (called when F is pressed)"""
	if corpse_gold == 0 and corpse_loot.is_empty():
		print("💀 No loot or gold, not opening UI")
		return

	print("💀 Opening loot UI via F-key for corpse at %s (Gold: %d, Items: %d)" % [global_position, corpse_gold, corpse_loot.size()])

	# Check if signal is connected
	var connection_count = corpse_clicked.get_connections().size()
	print("💀 Signal connections: %d" % connection_count)

	if connection_count > 0:
		corpse_clicked.emit(self)
		print("💀 Signal emitted!")
	else:
		# Fallback: directly create loot UI if signal not connected
		print("💀 No signal connections - creating loot UI directly")
		_create_loot_ui_fallback()

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
		# Don't apply damage to enemy directly in multiplayer - CritWindowManager handles
		# reporting to server at window end. But DO show visual feedback locally!
		_spawn_weakpoint_combat_text(weakpoint, crit_damage)

		# ✨ FIX: Trigger hit flash for weakpoint hits in multiplayer (was missing!)
		if has_node("HitFlash"):
			get_node("HitFlash").flash(true)  # true = crit/weakpoint flash (red)
		return

	# Single player: deal damage directly with crit flag and weakpoint flag for orange text
	take_damage(crit_damage, true, true)  # damage, is_crit, is_weakpoint

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
	weakpoint_destroyed.emit(weakpoint)

func _clear_weakpoints_delayed() -> void:
	"""Client-side: Clear weakpoints array after a delay to allow destruction RPCs to arrive"""
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		weakpoints.clear()

func shrink_after_crit_window() -> void:
	"""Visual effect: shrink sprite and cleanup weakpoints (called by CritWindowManager)"""
	# Guard: Don't shrink if not in crit window or already shrinking
	if not in_crit_window:
		return

	# Mark as transitioning during async shrink
	_crit_window_transitioning = true
	in_crit_window = false

	# On CLIENT: Don't clear weakpoints array immediately - the destruction RPC may still be
	# in transit. Let weakpoints free themselves after their destruction animations.
	# On SERVER: Clear array since we've already processed all destruction locally.
	if multiplayer.is_server():
		weakpoints.clear()
	else:
		# Client: Clear array after a delay to allow destruction RPCs to arrive
		_clear_weakpoints_delayed()

	# Reset HitFlash
	if has_node("HitFlash"):
		var hit_flash = get_node("HitFlash")
		if hit_flash.has_method("reset"):
			hit_flash.reset()
		hit_flash.set_base_color(Color.WHITE)

	# Restore original difficulty color
	self.modulate = original_modulate
	if sprite:
		sprite.modulate = Color.WHITE

	# Wait for grow tween to finish first (client may receive shrink before grow completes)
	if _grow_tween and _grow_tween.is_valid():
		_grow_tween.kill()  # Kill instead of waiting - we're ending the window
		_grow_tween = null

	# Wait for weakpoint explosion animation to complete (~0.5s shake + explosion)
	await get_tree().create_timer(0.55).timeout

	# Scale sprite back to base (check we're still valid)
	if is_instance_valid(self) and sprite and not is_dying:
		var base_sprite_scale = Vector2.ONE
		var tween = create_tween()
		tween.tween_property(sprite, "scale", base_sprite_scale, 0.25)
		await tween.finished

		if is_instance_valid(self) and sprite:
			sprite.scale = base_sprite_scale
			z_index = 0
			sprite.modulate = Color.WHITE

	_crit_window_transitioning = false  # Unlock after shrink complete

	# Clean up tutorial arrow when crit window ends
	clear_tutorial_arrow()

# ═══════════════════════════════════════════════════════════════════════════
# TUTORIAL WEAKPOINT ARROW (for first 3 crit windows on skeletons)
# ═══════════════════════════════════════════════════════════════════════════

func create_and_show_weakpoint_arrow(weakpoint_pos: Vector2) -> void:
	"""Create and show a red flashing arrow pointing at the weakpoint"""
	# Clear any existing arrow first
	clear_tutorial_arrow()

	# Create arrow container
	tutorial_arrow = Node2D.new()
	tutorial_arrow.name = "WeakpointArrow"
	tutorial_arrow.z_index = 200

	# Create arrow shape using a Polygon2D (pointing left)
	var arrow_polygon = Polygon2D.new()
	arrow_polygon.name = "ArrowShape"
	# Arrow pointing left (will be positioned to the right of weakpoint)
	arrow_polygon.polygon = PackedVector2Array([
		Vector2(-20, 0),     # Left point (arrow tip)
		Vector2(0, -15),     # Top wing
		Vector2(0, -6),      # Top inner
		Vector2(20, -6),     # Right stem top
		Vector2(20, 6),      # Right stem bottom
		Vector2(0, 6),       # Bottom inner
		Vector2(0, 15),      # Bottom wing
	])
	arrow_polygon.color = Color(1.0, 0.2, 0.2, 1.0)  # Bright red
	tutorial_arrow.add_child(arrow_polygon)

	# Add outline for visibility
	var outline = Line2D.new()
	outline.name = "ArrowOutline"
	outline.points = PackedVector2Array([
		Vector2(-20, 0),
		Vector2(0, -15),
		Vector2(0, -6),
		Vector2(20, -6),
		Vector2(20, 6),
		Vector2(0, 6),
		Vector2(0, 15),
		Vector2(-20, 0),  # Close the shape
	])
	outline.width = 3.0
	outline.default_color = Color(0.4, 0.0, 0.0, 1.0)  # Dark red outline
	tutorial_arrow.add_child(outline)

	# Position arrow to the right of the weakpoint
	tutorial_arrow.position = Vector2(weakpoint_pos.x + 50, weakpoint_pos.y)
	tutorial_arrow.scale = Vector2(1.2, 1.2)  # Slightly larger

	add_child(tutorial_arrow)

	# Start side-to-side bob animation
	arrow_tween = create_tween().set_loops()
	arrow_tween.tween_property(tutorial_arrow, "position:x", weakpoint_pos.x + 40, 0.3).set_ease(Tween.EASE_IN_OUT)
	arrow_tween.tween_property(tutorial_arrow, "position:x", weakpoint_pos.x + 55, 0.3).set_ease(Tween.EASE_IN_OUT)

	# Flash animation
	arrow_flash_tween = create_tween().set_loops()
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 0.3, 0.2)
	arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 1.0, 0.2)

func clear_tutorial_arrow() -> void:
	"""Remove the tutorial arrow"""
	# Kill tweens
	if arrow_tween and arrow_tween.is_valid():
		arrow_tween.kill()
	arrow_tween = null

	if arrow_flash_tween and arrow_flash_tween.is_valid():
		arrow_flash_tween.kill()
	arrow_flash_tween = null

	# Remove arrow
	if tutorial_arrow and is_instance_valid(tutorial_arrow):
		tutorial_arrow.queue_free()
		tutorial_arrow = null

func die() -> void:
	if is_dying:
		return

	is_dying = true

	# If dying during crit window, reset sprite scale immediately
	if in_crit_window or _crit_window_transitioning:
		in_crit_window = false
		_crit_window_transitioning = false
		# Kill any active grow tween
		if _grow_tween and _grow_tween.is_valid():
			_grow_tween.kill()
			_grow_tween = null
		# Reset sprite to normal scale
		if sprite:
			sprite.scale = Vector2.ONE
			sprite.modulate = Color.WHITE
		# Reset z_index
		z_index = 0
		self.modulate = Color.WHITE
		# Reset HitFlash base color
		if has_node("HitFlash"):
			var hit_flash = get_node("HitFlash")
			if hit_flash.has_method("set_base_color"):
				hit_flash.set_base_color(Color.WHITE)

	# Clean up any active weakpoints
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint):
			weakpoint.visible = false
			weakpoint.input_pickable = false
			weakpoint.monitoring = false
			weakpoint.monitorable = false
			weakpoint.queue_free()
	weakpoints.clear()

	# Also check children for any missed weakpoints
	for child in get_children():
		if child is Weakpoint:
			child.visible = false
			child.input_pickable = false
			child.monitoring = false
			child.monitorable = false
			child.queue_free()

	# Grant XP to player - in multiplayer, only to the killer
	var should_grant_xp = true
	if multiplayer.has_multiplayer_peer():
		# In multiplayer, only grant XP if we're the killer
		var killer_id = get_meta("killer_peer_id", -1)
		var my_peer_id = multiplayer.get_unique_id()
		should_grant_xp = (killer_id == my_peer_id)

	if should_grant_xp:
		var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player and player.has_method("gain_experience"):
			player.gain_experience(xp_reward)
			# Show world-space XP text floating up from mob
			var game_world = get_tree().get_first_node_in_group("game_world")
			if game_world:
				CombatText.create_xp(xp_reward, global_position, game_world)

	# Store gold in corpse for looting (skip if already set by server in multiplayer)
	if corpse_gold == 0:
		corpse_gold = gold_drop

	# Play death sound (skeleton-specific bone collapse)
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_skeleton_death_sound(global_position, -8.0)

	# Play death animation (hurt animation) and wait for it to complete
	var anim_sprite = sprite as AnimatedSprite2D
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("hurt"):
		anim_sprite.play("hurt")
		# Wait for the full animation to finish
		await anim_sprite.animation_finished
		if not is_instance_valid(self):
			return

		# FREEZE on last frame
		anim_sprite.stop()
		var frame_count = anim_sprite.sprite_frames.get_frame_count("hurt")
		anim_sprite.frame = frame_count - 1
	else:
		# Fallback if animation doesn't exist (e.g., guardians have no hurt animation)
		# Stop any playing animation and freeze on last frame
		if anim_sprite:
			anim_sprite.stop()
			# Freeze on the last frame of current animation
			if anim_sprite.sprite_frames and anim_sprite.animation:
				var frame_count = anim_sprite.sprite_frames.get_frame_count(anim_sprite.animation)
				if frame_count > 0:
					anim_sprite.frame = frame_count - 1
		await get_tree().create_timer(0.6).timeout
		if not is_instance_valid(self):
			return

	# Generate loot for this corpse (skip if already set by server in multiplayer)
	var has_peer = multiplayer.has_multiplayer_peer()
	if corpse_loot.is_empty():
		if has_peer:
			print("⚠️ [%s] Enemy %s corpse_loot is EMPTY in multiplayer - generating local loot (this may cause desync!)" % [
				"Server" if multiplayer.is_server() else "Client", name
			])
		corpse_loot = generate_corpse_loot()
	else:
		print("✅ [%s] Enemy %s corpse_loot already has %d items (from server)" % [
			"Server" if multiplayer.is_server() else "Client", name, corpse_loot.size()
		])

	# Emit died signal - spawner will respawn immediately
	died.emit()

	# Tutorial: notify TutorialManager of skeleton kill
	if TutorialManager and TutorialManager.is_tutorial_active():
		TutorialManager.on_skeleton_killed()

	# Quest: notify QuestManager of enemy kill
	if QuestManager:
		var is_guardian = get_meta("is_guardian", false)
		QuestManager.on_enemy_killed("skeleton", enemy_level, is_guardian)

	# Forged weapon stats: track kill for equipped forged weapons
	if should_grant_xp:
		var player_for_stats = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
		if player_for_stats and player_for_stats.has_node("PlayerCombat"):
			var combat_system = player_for_stats.get_node("PlayerCombat")
			if combat_system.has_method("track_enemy_killed"):
				var is_elite_enemy = get_meta("is_guardian", false)
				var is_boss_enemy = is_in_group("boss")
				combat_system.track_enemy_killed("skeleton", is_elite_enemy, is_boss_enemy)

	# Transition to corpse state (don't despawn)
	become_corpse()

## Debug Visualization
func draw_debug_shapes_world(world_container: Node2D) -> Node2D:
	# NEW VERSION - draws in world space (doesn't rotate)
	# RETURNS the container node for proper cleanup tracking
	
	# Create temporary container for this enemy's debug shapes
	var enemy_debug = Node2D.new()
	enemy_debug.name = "EnemyDebug_" + name
	world_container.add_child(enemy_debug)
	
	# Draw collision shape
	if has_node("CollisionShape2D"):
		var collision = get_node("CollisionShape2D")
		if collision.shape is RectangleShape2D:
			var rect_shape = collision.shape as RectangleShape2D
			var rect = draw_debug_rect_world(global_position, rect_shape.size * scale, rotation, Color.GREEN)
			enemy_debug.add_child(rect)
	
	# Draw click area
	if has_node("Area2D/CollisionShape2D"):
		var area_collision = get_node("Area2D/CollisionShape2D")
		if area_collision.shape is RectangleShape2D:
			var rect_shape = area_collision.shape as RectangleShape2D
			var rect = draw_debug_rect_world(area_collision.global_position, rect_shape.size * scale, rotation, Color.CYAN)
			enemy_debug.add_child(rect)

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
			var purple_box = draw_debug_rect_world(section_center, section_size, 0.0, Color.MAGENTA)
			enemy_debug.add_child(purple_box)

	# Draw weakpoint hitboxes
	for weakpoint in weakpoints:
		if is_instance_valid(weakpoint) and weakpoint.has_method("draw_debug_hitbox_world"):
			weakpoint.draw_debug_hitbox_world(enemy_debug)
	
	return enemy_debug  # Return for tracking

func draw_debug_rect_world(center: Vector2, size: Vector2, angle: float, color: Color) -> Line2D:
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = color
	line.z_index = 1000

	var half_size = size / 2.0

	# Create corners
	var corners = [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y)
	]

	# Rotate and translate corners
	for i in range(4):
		var rotated = corners[i].rotated(angle)
		line.add_point(center + rotated)

	# Close the rectangle
	var rotated = corners[0].rotated(angle)
	line.add_point(center + rotated)

	return line

## ============================================
## CORPSE SYSTEM
## ============================================

func generate_corpse_loot() -> Array:
	"""Generate loot items for this corpse using CorpseState loot tables"""
	var loot = []

	# Check if this is a guardian (Ruins skeleton with special loot)
	var is_guardian = get_meta("is_guardian", false)

	# Roll for number of items (0-2)
	var num_items = CorpseState.roll_loot_count()

	# Generate each item
	for i in range(num_items):
		var item = CorpseState.roll_loot_item(is_guardian, enemy_level)
		if not item.is_empty():
			if item.get("stackable", false):
				item["quantity"] = 1
			loot.append(item)

	return loot

func become_corpse() -> void:
	"""Transition enemy from living to corpse state"""
	is_corpse = true
	corpse_creation_time = Time.get_ticks_msec() / 1000.0
	corpse_state = CorpseState.State.FRESH

	# Clean up any active weakpoints (if enemy died during crit window)
	if not weakpoints.is_empty():
		for wp in weakpoints:
			if is_instance_valid(wp):
				wp.queue_free()
		weakpoints.clear()
		in_crit_window = false

	# Ensure sprite is reset to normal scale (in case died during crit window)
	if sprite:
		sprite.scale = Vector2.ONE
	z_index = 0

	# Disable AI
	if has_node("EnemyAI"):
		var ai = get_node("EnemyAI")
		ai.set_process(false)
		ai.set_physics_process(false)

	# Disable health bar
	if health_bar:
		health_bar.visible = false

	# Keep collision for clicking, but change layers
	# Layer 4 = corpses (separate from living enemies)
	collision_layer = 8  # 2^3 = layer 4
	collision_mask = 0   # Don't detect anything

	# Change groups
	remove_from_group(Constants.GROUP_ENEMIES)
	add_to_group("corpses")

	# Add loot indicator if has gold OR items
	if corpse_gold > 0 or corpse_loot.size() > 0:
		print("   ✨ Adding loot indicator (sparkles) - Gold: %d, Items: %d" % [corpse_gold, corpse_loot.size()])
		add_loot_indicator()
	else:
		print("   ⚫ No loot - no indicator")

	# Play dead animation and darken sprite
	if sprite and sprite is AnimatedSprite2D:
		var anim_sprite = sprite as AnimatedSprite2D
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("dead"):
			anim_sprite.play("dead")
		sprite.modulate = Color(0.7, 0.7, 0.7, 1.0)  # Darken corpse

	# Hide equipment on corpse (they fall off / look messy)
	for equip in equipment_sprites:
		if is_instance_valid(equip):
			equip.visible = false

	# Hide shadow for corpse
	if shadow_sprite:
		shadow_sprite.visible = false

func add_loot_indicator() -> void:
	"""Add shiny glimmer effect to indicate this corpse has loot (WoW-style)"""
	if loot_indicator:
		return  # Already has indicator

	loot_indicator = Node2D.new()
	loot_indicator.name = "LootIndicator"
	loot_indicator.z_index = 10  # Draw on top

	# Create 3-4 small sparkle points clustered tightly on the corpse
	var sparkle_positions = [
		Vector2(-3, -5),  # Upper left (tight cluster)
		Vector2(3, -5),   # Upper right (tight cluster)
		Vector2(-2, 0),   # Lower left (tight cluster)
		Vector2(2, 0)     # Lower right (tight cluster)
	]

	for i in range(sparkle_positions.size()):
		var sparkle = create_sparkle()
		sparkle.position = sparkle_positions[i]
		loot_indicator.add_child(sparkle)

		# Stagger animation start times for shimmer effect
		var delay = i * 0.2
		animate_sparkle(sparkle, delay)

	add_child(loot_indicator)

func create_sparkle() -> Polygon2D:
	"""Create a single sparkle (4-pointed star)"""
	var sparkle = Polygon2D.new()

	# Create 4-pointed star shape
	var size = 6.0
	var points = PackedVector2Array([
		Vector2(0, -size),      # Top point
		Vector2(-1, -1),        # Inner top-left
		Vector2(-size, 0),      # Left point
		Vector2(-1, 1),         # Inner bottom-left
		Vector2(0, size),       # Bottom point
		Vector2(1, 1),          # Inner bottom-right
		Vector2(size, 0),       # Right point
		Vector2(1, -1)          # Inner top-right
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

func process_corpse_decay(delta: float) -> void:
	"""Handle corpse decay over time"""
	var elapsed = (Time.get_ticks_msec() / 1000.0) - corpse_creation_time

	# Check if fully rotted (5 minutes)
	if elapsed >= CorpseState.CORPSE_DECAY_TIME:
		rot_and_despawn()
		return

	# Check if transitioned to decaying state (after 1 minute)
	if elapsed >= CorpseState.CORPSE_FRESH_TIME:
		if corpse_state == CorpseState.State.FRESH:
			corpse_state = CorpseState.State.DECAYING
			update_decay_visual()

func update_decay_visual() -> void:
	"""Update visual appearance for decaying state"""
	if sprite:
		# Make more transparent
		var current_color = sprite.modulate
		sprite.modulate = Color(
			current_color.r * CorpseState.DECAY_ALPHA_MULTIPLIER,
			current_color.g * CorpseState.DECAY_ALPHA_MULTIPLIER,
			current_color.b * CorpseState.DECAY_ALPHA_MULTIPLIER,
			0.8  # More transparent
		)

func rot_and_despawn() -> void:
	"""Corpse has rotted - fade out and remove"""
	if corpse_state == CorpseState.State.ROTTED:
		return  # Already rotting

	corpse_state = CorpseState.State.ROTTED

	# Fade out animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 2.0)
	tween.tween_property(self, "scale", Vector2(0.8, 0.8), 2.0)
	await tween.finished

	if is_instance_valid(self):
		queue_free()

func check_if_looted_empty() -> void:
	"""Called when items are taken - check if corpse is now empty"""
	# Corpse is empty when BOTH gold is 0 AND items are gone
	if corpse_loot.is_empty() and corpse_gold == 0:
		# Remove loot indicator
		if loot_indicator:
			loot_indicator.queue_free()
			loot_indicator = null

		# Hide loot prompt
		if loot_prompt:
			loot_prompt.queue_free()
			loot_prompt = null

		# Emit signal
		corpse_looted_empty.emit(self)

		# Quick fade out
		graceful_despawn()

func graceful_despawn() -> void:
	"""Gradual fade out for fully looted corpses - smooth UX for mass looting"""
	# Disable any remaining interactions
	if has_node("Area2D"):
		var area = get_node("Area2D")
		area.monitoring = false
		area.monitorable = false

	# Fade out over 1.5 seconds with easing for smooth feel
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 1.5)
	tween.tween_property(self, "scale", Vector2(0.7, 0.7), 1.5)
	# Sink slightly into the ground
	tween.tween_property(self, "position:y", position.y + 10, 1.5)
	await tween.finished

	if is_instance_valid(self):
		queue_free()

func has_corpse_loot() -> bool:
	"""Check if corpse has any lootable items or gold remaining (used by SpawnManager)"""
	return not corpse_loot.is_empty() or corpse_gold > 0

func get_nearby_corpses(radius: float) -> Array:
	"""Find all corpses within radius for AOE looting"""
	var nearby = []
	var all_corpses = get_tree().get_nodes_in_group("corpses")

	for node in all_corpses:
		if node == self:
			continue  # Skip self

		# Check if valid corpse and within radius
		if is_instance_valid(node) and node.global_position.distance_to(global_position) <= radius:
			nearby.append(node)

	return nearby

func _create_loot_ui_fallback() -> void:
	"""Create loot UI directly when corpse_clicked signal isn't connected.
	This handles edge cases where enemies die before signal connection happens."""
	var nearby_corpses = get_nearby_corpses(CorpseState.AOE_LOOT_RADIUS)

	# Create loot UI from preloaded scene
	var loot_ui = LOOT_BODY_UI_SCENE.instantiate()
	if not loot_ui:
		push_error("Failed to instantiate loot UI")
		return

	get_tree().root.add_child(loot_ui)
	loot_ui.loot_ui_closed.connect(func(): loot_ui.queue_free())
	loot_ui.open_loot_ui(self, nearby_corpses)
