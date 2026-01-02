extends CharacterBody2D
class_name PlayerCorpse

## Player Corpse - EverQuest-style corpse that holds player's items on death
## Players must return to their corpse to retrieve their belongings
## Corpse decays over time - items lost forever if not retrieved

signal corpse_looted(corpse: PlayerCorpse)
signal corpse_decayed(corpse: PlayerCorpse)
signal drag_requested(requester_id: int, requester_name: String)
signal drag_started()
signal drag_stopped()

# Owner info
var owner_player_id: int = -1  # Network ID of player who died
var owner_player_name: String = ""
var death_timestamp: float = 0.0

# Stored loot (snapshot at death)
var stored_inventory: Array = []  # Full inventory array
var stored_equipped_armor: Dictionary = {}  # All armor slots
var stored_equipped_weapon: Dictionary = {}  # Weapon as dictionary
var stored_gold: int = 0

# Visual appearance (to render corpse with armor)
var stored_appearance: Dictionary = {}

# Equipment sprite names at death (for visual rendering)
var stored_sprite_names: Dictionary = {
	"feet": "",
	"legs": "",
	"chest": "",
	"arms": "",
	"hands": "",
	"head": "",
	"weapon": ""
}

# Visual layer references (for stripping when looted)
var equipment_layers: Dictionary = {}  # slot -> AnimatedSprite2D

# Decay timing
const CORPSE_FRESH_TIME: float = 300.0    # 5 minutes - full loot, clear indicator
const CORPSE_DECAY_TIME: float = 1800.0   # 30 minutes - corpse despawns, loot lost
const CORPSE_WARNING_TIME: float = 1500.0 # 25 minutes - warning before decay

# State
enum State { FRESH, DECAYING, ROTTED }
var current_state: State = State.FRESH

# Interaction
var loot_prompt: Label = null
var is_player_nearby: bool = false
var loot_ui_open: bool = false

# Dragging
var is_being_dragged: bool = false
var dragger_player: Node = null
var dragger_name: String = ""
var drag_consent_granted: Dictionary = {}  # player_id -> bool
const DRAG_SPEED_MULTIPLIER: float = 0.5
const DRAG_DISTANCE: float = 40.0

# Visual
var corpse_sprite: AnimatedSprite2D = null
var decay_particles: GPUParticles2D = null

# Server mode flag - skip all visual/texture creation on dedicated server
var _is_server_mode: bool = false

func _ready() -> void:
	_is_server_mode = "--server" in OS.get_cmdline_user_args()
	add_to_group("player_corpses")

	# Set up collision (don't block movement, just for interaction detection)
	collision_layer = 0
	collision_mask = 0

	# DEDICATED SERVER: Skip visual elements
	if _is_server_mode:
		return

	# Create interaction area (client-only)
	_create_interaction_area()

	# Create loot prompt label (client-only)
	_create_loot_prompt()

func initialize(player: Node, death_pos: Vector2) -> void:
	"""Called when corpse is created - snapshot all player data"""
	owner_player_id = player.get_multiplayer_authority() if player.has_method("get_multiplayer_authority") else 1

	# Get player name from NetworkManager (where it's stored)
	var network_manager = player.get_node_or_null("/root/NetworkManager")
	if network_manager and "player_name" in network_manager and network_manager.player_name != "":
		owner_player_name = network_manager.player_name
	else:
		owner_player_name = "Player"

	global_position = death_pos
	death_timestamp = Time.get_unix_time_from_system()

	print("💀 Creating player corpse for %s at %s" % [owner_player_name, death_pos])

	# Snapshot inventory (deep copy)
	stored_inventory = InventorySystem.get_full_snapshot()

	# Snapshot equipped armor (deep copy)
	stored_equipped_armor = CharacterStats.get_armor_snapshot()

	# Snapshot weapon as dictionary
	if CharacterStats.equipped_weapon:
		stored_equipped_weapon = CharacterStats.get_weapon_as_dict()
	else:
		stored_equipped_weapon = {}

	# Snapshot gold
	stored_gold = CharacterStats.gold

	# Snapshot appearance for visual
	stored_appearance = {
		"gender": player.selected_gender if "selected_gender" in player else 0,
		"hair_style": player.selected_hair_style if "selected_hair_style" in player else 0,
		"hair_color": player.selected_hair_color if "selected_hair_color" in player else Color.BROWN,
		"skin_color": player.selected_skin_color if "selected_skin_color" in player else Color(0.96, 0.80, 0.69),
	}

	# Snapshot equipment sprite names for visual rendering
	for slot in ["feet", "legs", "chest", "arms", "hands", "head"]:
		if stored_equipped_armor.has(slot) and stored_equipped_armor[slot]:
			stored_sprite_names[slot] = stored_equipped_armor[slot].get("sprite_name", "")

	# Weapon type
	if not stored_equipped_weapon.is_empty():
		stored_sprite_names["weapon"] = stored_equipped_weapon.get("weapon_type", "")

	# Setup corpse visual with armor layers (client-only)
	if not _is_server_mode:
		_setup_corpse_visual()

	print("   Stored: %d inventory items, %d gold, weapon=%s" % [
		_count_items(stored_inventory),
		stored_gold,
		stored_equipped_weapon.get("name", "none")
	])

func _count_items(arr: Array) -> int:
	var count = 0
	for item in arr:
		if item != null:
			count += 1
	return count

func can_loot(player_id: int) -> bool:
	"""Check if player can loot this corpse"""
	# Owner can always loot their own corpse
	return player_id == owner_player_id

func get_all_loot() -> Dictionary:
	"""Return all loot for UI display"""
	return {
		"inventory": stored_inventory,
		"equipped_armor": stored_equipped_armor,
		"equipped_weapon": stored_equipped_weapon,
		"gold": stored_gold
	}

func remove_inventory_item(index: int) -> Dictionary:
	"""Remove item from corpse inventory when looted"""
	if index < 0 or index >= stored_inventory.size():
		return {}

	var item = stored_inventory[index]
	stored_inventory[index] = null

	if _is_empty():
		_despawn()

	return item if item else {}

func remove_equipped_armor(slot: String) -> Dictionary:
	"""Remove armor from specific slot"""
	if not stored_equipped_armor.has(slot):
		return {}

	var armor = stored_equipped_armor[slot]
	stored_equipped_armor[slot] = null

	# Strip the visual layer from corpse
	_strip_equipment_layer(slot)

	if _is_empty():
		_despawn()

	return armor if armor else {}

func remove_weapon() -> Dictionary:
	"""Remove weapon from corpse"""
	var weapon = stored_equipped_weapon
	stored_equipped_weapon = {}

	# Strip the visual layer from corpse (if we had weapon visual)
	_strip_equipment_layer("weapon")

	if _is_empty():
		_despawn()

	return weapon

func take_gold() -> int:
	"""Take all gold from corpse"""
	var gold = stored_gold
	stored_gold = 0

	if _is_empty():
		_despawn()

	return gold

func _is_empty() -> bool:
	"""Check if corpse has no more loot"""
	if stored_gold > 0:
		return false
	if not stored_equipped_weapon.is_empty():
		return false

	for slot in stored_equipped_armor:
		if stored_equipped_armor[slot] != null:
			return false

	for item in stored_inventory:
		if item != null:
			return false

	return true

func _process(delta: float) -> void:
	var time_since_death = Time.get_unix_time_from_system() - death_timestamp

	# Update decay state
	if time_since_death >= CORPSE_DECAY_TIME:
		_decay_corpse()
	elif time_since_death >= CORPSE_WARNING_TIME:
		if current_state != State.DECAYING:
			current_state = State.DECAYING
			_apply_decay_visual()
			# Notify owner their corpse is about to decay
			_notify_owner_decay_warning()
	elif time_since_death >= CORPSE_FRESH_TIME:
		if current_state == State.FRESH:
			current_state = State.DECAYING
			_apply_decay_visual()

	# Update loot prompt visibility
	_update_loot_prompt()

func _physics_process(delta: float) -> void:
	if is_being_dragged and is_instance_valid(dragger_player):
		# Corpse follows behind dragger
		var dir = dragger_player.velocity.normalized() if dragger_player.velocity.length() > 0 else Vector2.DOWN
		var target_pos = dragger_player.global_position - (dir * DRAG_DISTANCE)

		# Smooth follow
		global_position = global_position.lerp(target_pos, 5.0 * delta)

		# Cancel if dragger gets too far (teleport/disconnect)
		if global_position.distance_to(dragger_player.global_position) > 200:
			stop_drag()

func _decay_corpse() -> void:
	"""Corpse has fully decayed - all loot lost"""
	current_state = State.ROTTED
	InteractionManager.unregister_interactable(self)
	corpse_decayed.emit(self)

	print("💀 Corpse of %s has decayed - all loot lost!" % owner_player_name)

	# Notify owner their corpse decayed
	_notify_owner_corpse_decayed()

	queue_free()

func _despawn() -> void:
	"""Corpse is empty - remove it"""
	print("💀 Corpse of %s is empty - despawning" % owner_player_name)
	InteractionManager.unregister_interactable(self)
	corpse_looted.emit(self)
	queue_free()

func _apply_decay_visual() -> void:
	"""Apply visual effect for decaying corpse"""
	if corpse_sprite:
		# Fade and desaturate
		corpse_sprite.modulate = Color(0.7, 0.7, 0.6, 0.8)

	# Could add flies/particles here

func _notify_owner_decay_warning() -> void:
	"""Notify corpse owner that their corpse is about to decay"""
	# TODO: Network RPC to owner
	print("⚠️ Corpse decay warning for %s" % owner_player_name)

func _notify_owner_corpse_decayed() -> void:
	"""Notify corpse owner that their corpse has decayed"""
	# TODO: Network RPC to owner
	pass

func _create_interaction_area() -> void:
	"""Create Area2D for detecting nearby players"""
	var area = Area2D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0  # Corpse interaction area doesn't block anything
	area.collision_mask = 1   # Detect player on layer 1
	area.monitoring = true
	area.monitorable = false
	add_child(area)

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 80.0  # Interaction range (slightly larger for easier detection)
	shape.shape = circle
	area.add_child(shape)

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

	print("   🔍 Corpse interaction area created (radius: 80, mask: 1)")

func _create_loot_prompt() -> void:
	"""Create [F] Loot prompt label"""
	loot_prompt = Label.new()
	loot_prompt.name = "LootPrompt"
	loot_prompt.text = "[F] Loot Corpse"
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_prompt.position = Vector2(-50, -70)
	loot_prompt.add_theme_font_size_override("font_size", 12)
	loot_prompt.add_theme_color_override("font_color", Color.WHITE)
	loot_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	loot_prompt.add_theme_constant_override("outline_size", 2)
	loot_prompt.visible = false
	add_child(loot_prompt)

func _setup_corpse_visual() -> void:
	"""Setup the corpse sprite with equipment layers matching what player was wearing"""
	var is_female = stored_appearance.get("gender", 0) == 1

	# Create main body sprite (base layer)
	corpse_sprite = AnimatedSprite2D.new()
	corpse_sprite.name = "CorpseSprite"
	corpse_sprite.centered = true
	corpse_sprite.z_index = 0
	add_child(corpse_sprite)

	var body_path = "res://assets/characters/body_female/standard/hurt.png" if is_female else "res://assets/characters/body_male/standard/hurt.png"
	_setup_layer_from_hurt(corpse_sprite, body_path)

	# Create head layer
	var head_layer = AnimatedSprite2D.new()
	head_layer.name = "HeadLayer"
	head_layer.centered = true
	head_layer.z_index = 1
	add_child(head_layer)
	var head_path = "res://assets/characters/head_female/standard/hurt.png" if is_female else "res://assets/characters/head_male/standard/hurt.png"
	_setup_layer_from_hurt(head_layer, head_path)

	# Equipment layers in z-order
	var layer_config = [
		{"slot": "feet", "z": 2, "folder": "feet"},
		{"slot": "legs", "z": 3, "folder": "legs"},
		{"slot": "chest", "z": 4, "folder": "torso"},
		{"slot": "arms", "z": 5, "folder": "arms"},
		{"slot": "hands", "z": 6, "folder": "hands"},
		{"slot": "head", "z": 8, "folder": "head"}
	]

	# Map slots to folder names
	var slot_to_folder = {
		"feet": "boots",
		"legs": "pants",
		"chest": "shirt",
		"arms": "arms",
		"hands": "hands",
		"head": "head"
	}

	for config in layer_config:
		var slot = config["slot"]
		var sprite_name = stored_sprite_names.get(slot, "")
		if sprite_name != "":
			var layer = AnimatedSprite2D.new()
			layer.name = slot.capitalize() + "Layer"
			layer.centered = true
			layer.z_index = config["z"]
			add_child(layer)

			var folder = slot_to_folder.get(slot, config["folder"])

			# Try to load hurt sprite for equipment (matches lying body pose)
			# First try LPC-style path: assets/characters/{sprite_name}/standard/hurt.png
			var hurt_path_lpc = "res://assets/characters/%s/standard/hurt.png" % sprite_name
			# Then try flat structure: assets/characters/{folder}/{sprite_name}_hurt.png
			var hurt_path_flat = "res://assets/characters/%s/%s_hurt.png" % [folder, sprite_name]

			var loaded = false
			if ResourceLoader.exists(hurt_path_lpc):
				loaded = _setup_layer_from_hurt(layer, hurt_path_lpc)
			elif ResourceLoader.exists(hurt_path_flat):
				loaded = _setup_layer_from_hurt(layer, hurt_path_flat)

			if loaded:
				equipment_layers[slot] = layer
				print("   ✅ Corpse equipment: %s loaded hurt sprite" % slot)
			else:
				# No hurt sprite available - hide this equipment on corpse
				print("   ⚠️ Corpse equipment: %s has no hurt sprite, hiding layer" % slot)
				layer.queue_free()

	# Hair layer (always show)
	var hair_layer = AnimatedSprite2D.new()
	hair_layer.name = "HairLayer"
	hair_layer.centered = true
	hair_layer.z_index = 7
	add_child(hair_layer)
	var hair_path = "res://assets/characters/hair_female/standard/hurt.png" if is_female else "res://assets/characters/hair_male/standard/hurt.png"
	_setup_layer_from_hurt(hair_layer, hair_path)

	# Add name label above corpse
	var name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = owner_player_name + "'s Corpse"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-60, -50)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)
	add_child(name_label)

	print("   Corpse visual: %d equipment layers" % equipment_layers.size())

func _setup_layer_from_hurt(sprite: AnimatedSprite2D, texture_path: String) -> bool:
	"""Setup an AnimatedSprite2D layer from a hurt spritesheet. Returns true if successful."""
	if not ResourceLoader.exists(texture_path):
		return false

	var tex = ResourceLoader.load(texture_path, "Texture2D")
	if not tex:
		return false

	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("death")
	sprite_frames.set_animation_loop("death", false)
	sprite_frames.set_animation_speed("death", 1.0)

	# Extract frame 5 from hurt spritesheet (lying down pose)
	# LPC standard: hurt animation has lying-down pose at frame 5 (0-indexed)
	var img = tex.get_image()
	var frame_width = 64
	var frame_height = 64

	# Always use frame 5 for the lying down death pose (LPC standard)
	var death_frame = 5

	var frame_img = Image.create(frame_width, frame_height, false, Image.FORMAT_RGBA8)
	frame_img.blit_rect(img, Rect2i(death_frame * frame_width, 0, frame_width, frame_height), Vector2i(0, 0))

	var frame_tex = ImageTexture.create_from_image(frame_img)
	sprite_frames.add_frame("death", frame_tex)

	sprite.sprite_frames = sprite_frames
	sprite.play("death")
	return true

func _setup_layer_from_walk(sprite: AnimatedSprite2D, texture_path: String) -> bool:
	"""Setup an AnimatedSprite2D layer from a walk spritesheet. Uses first frame (idle, facing down)."""
	if not ResourceLoader.exists(texture_path):
		return false

	var tex = ResourceLoader.load(texture_path, "Texture2D")
	if not tex:
		return false

	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("death")
	sprite_frames.set_animation_loop("death", false)
	sprite_frames.set_animation_speed("death", 1.0)

	# Walk spritesheets are 9 columns × 4 rows (576x256 for 64x64 frames)
	# Extract first frame (row 0, column 0 = facing down, idle)
	var img = tex.get_image()
	var frame_width = 64
	var frame_height = 64

	var frame_img = Image.create(frame_width, frame_height, false, Image.FORMAT_RGBA8)
	frame_img.blit_rect(img, Rect2i(0, 0, frame_width, frame_height), Vector2i(0, 0))

	var frame_tex = ImageTexture.create_from_image(frame_img)
	sprite_frames.add_frame("death", frame_tex)

	sprite.sprite_frames = sprite_frames
	sprite.play("death")
	return true

func _strip_equipment_layer(slot: String) -> void:
	"""Remove the visual layer for an equipment slot (called when item is looted)"""
	if equipment_layers.has(slot):
		var layer = equipment_layers[slot]
		if is_instance_valid(layer):
			layer.queue_free()
		equipment_layers.erase(slot)

func _on_body_entered(body: Node2D) -> void:
	"""Player entered interaction range"""
	if body.is_in_group("player"):
		var player_id = body.get_multiplayer_authority()
		print("💀 Corpse: Player %d entered range (owner: %d)" % [player_id, owner_player_id])
		if can_loot(player_id):
			is_player_nearby = true
			# Register with InteractionManager for priority handling
			var distance = body.global_position.distance_to(global_position)
			InteractionManager.register_interactable(self, InteractionManager.InteractionType.LOOT_BODY, distance)
			print("   ✅ Registered with InteractionManager")

func _on_body_exited(body: Node2D) -> void:
	"""Player left interaction range"""
	if body.is_in_group("player"):
		print("💀 Corpse: Player left range")
		is_player_nearby = false
		InteractionManager.unregister_interactable(self)

func _update_loot_prompt() -> void:
	"""Update loot prompt visibility"""
	if loot_prompt:
		var is_active = InteractionManager.is_active_interactable(self)
		loot_prompt.visible = is_player_nearby and is_active and not loot_ui_open and not _is_empty()

func _input(event: InputEvent) -> void:
	# F to loot corpse when nearby and we're the active interactable
	if not is_player_nearby or loot_ui_open:
		return

	if not InteractionManager.is_active_interactable(self):
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			# UI F key has priority - don't open loot if any UI is open
			if GameInput.is_any_ui_open():
				return

			print("💀 Corpse: F pressed - opening loot UI!")
			_open_loot_ui()
			get_viewport().set_input_as_handled()

func _open_loot_ui() -> void:
	"""Open the corpse loot UI"""
	loot_ui_open = true

	# Find or create PlayerCorpseLootUI
	var loot_ui = get_tree().root.get_node_or_null("PlayerCorpseLootUI")
	if not loot_ui:
		var loot_ui_scene = load("res://scenes/ui/PlayerCorpseLootUI.tscn")
		if loot_ui_scene:
			loot_ui = loot_ui_scene.instantiate()
			get_tree().root.add_child(loot_ui)

	if loot_ui and loot_ui.has_method("open_corpse_ui"):
		loot_ui.open_corpse_ui(self)
		loot_ui.loot_ui_closed.connect(_on_loot_ui_closed, CONNECT_ONE_SHOT)

func _on_loot_ui_closed() -> void:
	"""Called when loot UI is closed"""
	loot_ui_open = false

# === DRAGGING SYSTEM ===

func request_drag(requester: Node) -> void:
	"""Player requests to drag this corpse"""
	var requester_id = requester.get_multiplayer_authority() if requester.has_method("get_multiplayer_authority") else 1
	var requester_name = requester.player_name if "player_name" in requester else "Unknown"

	# Check if consent already granted
	if drag_consent_granted.get(requester_id, false):
		start_drag(requester)
		return

	# Send consent request to corpse owner
	drag_requested.emit(requester_id, requester_name)

func grant_drag_consent(player_id: int) -> void:
	"""Owner grants drag permission to player"""
	drag_consent_granted[player_id] = true

func deny_drag_consent(player_id: int) -> void:
	"""Owner denies drag permission"""
	drag_consent_granted[player_id] = false

func start_drag(dragger: Node) -> void:
	"""Begin dragging corpse"""
	is_being_dragged = true
	dragger_player = dragger
	dragger_name = dragger.player_name if "player_name" in dragger else "Unknown"

	# Slow down dragger
	if dragger.has_method("apply_speed_modifier"):
		dragger.apply_speed_modifier("corpse_drag", DRAG_SPEED_MULTIPLIER)

	drag_started.emit()

func stop_drag() -> void:
	"""Stop dragging"""
	if dragger_player and dragger_player.has_method("remove_speed_modifier"):
		dragger_player.remove_speed_modifier("corpse_drag")

	is_being_dragged = false
	dragger_player = null
	dragger_name = ""

	drag_stopped.emit()

func get_dragger_name() -> String:
	"""Get name of player dragging this corpse"""
	return dragger_name
