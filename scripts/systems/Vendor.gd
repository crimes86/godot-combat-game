extends Area2D
class_name Vendor

## Vendor NPC that sells items to the player
## Place near campfire for easy access

signal shop_opened()
signal shop_closed()

@export var vendor_name: String = "Blacksmith"
@export var greeting_text: String = "Need some quality steel?"
@export var vendor_zone: int = 1  # Only sell items for this zone (0 = all zones)

var weapons_for_sale: Array = []
var weapon_prices: Array = []  # Parallel array for weapon prices
var armor_for_sale: Array = []
var tools_for_sale: Array = []  # Gathering tools (axe, pickaxe, etc)
var player_in_range: bool = false
var shop_ui: CanvasLayer = null
var animated_sprite: AnimatedSprite2D = null
var interaction_prompt: Label = null
var quest_indicator: Label = null  # Floating "!" above head
var has_talked_to_player: bool = false  # Track if player has interacted

# Tutorial arrow indicator
var tutorial_arrow: Polygon2D = null
var tutorial_arrow_tween: Tween = null
var tutorial_arrow_flash_tween: Tween = null

func _ready() -> void:
	print("🏪 Vendor '%s' starting initialization..." % vendor_name)

	# Add to vendor group for tutorial system
	add_to_group("vendor")

	# Create animated blacksmith sprite
	setup_blacksmith_sprite()

	# Add physical collision so player can't walk through
	add_collision_body()

	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	print("   Signals connected")

	# Load shop inventory
	load_shop_data()

	# Create interaction prompt
	create_interaction_prompt()

	# Create quest indicator (floating "!")
	create_quest_indicator()

	print("🏪 Vendor '%s' initialized with %d weapons, %d armor pieces, and %d tools" % [vendor_name, weapons_for_sale.size(), armor_for_sale.size(), tools_for_sale.size()])
	print("   Position: ", global_position)
	print("   Monitoring: ", monitoring)

func add_collision_body() -> void:
	"""Add StaticBody2D collision so player can't walk through vendor"""
	var collision_body = StaticBody2D.new()
	collision_body.name = "CollisionBody"
	collision_body.collision_layer = 2  # Layer 2 for obstacles
	collision_body.collision_mask = 0
	add_child(collision_body)

	# Add circular collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 20.0  # Tight collision around vendor
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)

	print("   Added collision body to vendor")

func create_interaction_prompt() -> void:
	"""Create floating [F] Talk prompt above blacksmith"""
	print("   Creating interaction prompt...")

	# Use CanvasLayer like other interaction prompts
	var canvas = CanvasLayer.new()
	canvas.name = "InteractionCanvas"
	canvas.layer = 50
	add_child(canvas)

	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Talk"
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))  # Golden color
	interaction_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.visible = false
	canvas.add_child(interaction_prompt)

	print("   Interaction prompt created")

func create_quest_indicator() -> void:
	"""Create floating '!' or '?' indicator above blacksmith name tag to attract attention"""
	quest_indicator = Label.new()
	quest_indicator.name = "QuestIndicator"
	quest_indicator.text = "!"
	quest_indicator.add_theme_font_size_override("font_size", 28)
	quest_indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))  # Golden yellow
	quest_indicator.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.0))
	quest_indicator.add_theme_constant_override("outline_size", 3)
	quest_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quest_indicator.position = Vector2(-8, -85)  # Above the name tag
	quest_indicator.z_index = 100
	add_child(quest_indicator)

	# Start bobbing animation
	_start_quest_indicator_animation()

	# Connect to QuestManager signals for indicator updates
	call_deferred("_connect_quest_signals")

func _connect_quest_signals() -> void:
	"""Connect to QuestManager and TutorialManager for indicator updates"""
	if has_node("/root/QuestManager"):
		var qm = get_node("/root/QuestManager")
		qm.active_quests_changed.connect(_update_quest_indicator)
		qm.quests_loaded.connect(_update_quest_indicator)

	# Connect to TutorialManager to refresh indicator when tutorial steps change
	if TutorialManager:
		TutorialManager.tutorial_step_completed.connect(_on_tutorial_step_changed)

	# Initial update
	_update_quest_indicator()

func _on_tutorial_step_changed(_completed_step: int) -> void:
	"""Refresh quest indicator when tutorial progresses"""
	_update_quest_indicator()

func _update_quest_indicator() -> void:
	"""Update quest indicator based on quest state: ? for turn-in, ! for available
	During tutorial: Only show ! when it's actually the VISIT_BLACKSMITH step"""
	if not quest_indicator or not is_instance_valid(quest_indicator):
		return

	if not has_node("/root/QuestManager"):
		return

	var qm = get_node("/root/QuestManager")
	var giver = vendor_name.to_lower()

	# Check for quests ready to turn in first (priority) - always show
	if qm.has_completed_quests(giver):
		quest_indicator.text = "?"
		quest_indicator.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))  # Bright gold
		quest_indicator.visible = true
		quest_indicator.modulate.a = 1.0
		return

	# Check for available quests
	if qm.has_available_quests(giver):
		# During tutorial, only show ! when it's the VISIT_BLACKSMITH step
		if TutorialManager and TutorialManager.is_tutorial_active():
			var tutorial_step = TutorialManager.current_step
			# TutorialStep.VISIT_BLACKSMITH = 6
			if tutorial_step < 6:
				# Tutorial is active but not yet at blacksmith step - hide indicator
				quest_indicator.visible = false
				return

		# Show available quest indicator
		quest_indicator.text = "!"
		quest_indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))  # Gold
		quest_indicator.visible = true
		quest_indicator.modulate.a = 1.0
		return

	# No quests - hide indicator
	quest_indicator.visible = false

func _start_quest_indicator_animation() -> void:
	"""Animate the quest indicator with a gentle bob"""
	if not quest_indicator or not is_instance_valid(quest_indicator):
		return

	var tween = create_tween()
	tween.set_loops()  # Loop forever
	tween.tween_property(quest_indicator, "position:y", -90.0, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(quest_indicator, "position:y", -80.0, 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func hide_quest_indicator() -> void:
	"""Hide the quest indicator after player has talked to blacksmith"""
	if quest_indicator and is_instance_valid(quest_indicator):
		var tween = create_tween()
		tween.tween_property(quest_indicator, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			if quest_indicator:
				quest_indicator.visible = false
		)

func update_prompt_position() -> void:
	"""Update prompt position to 30 pixels below player's feet"""
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

func setup_blacksmith_sprite() -> void:
	# Create animated sprite for blacksmith
	animated_sprite = AnimatedSprite2D.new()
	animated_sprite.name = "BlacksmithSprite"
	animated_sprite.centered = true
	animated_sprite.z_index = 1
	animated_sprite.scale.x = -1  # Flip to face left (toward campfire)
	add_child(animated_sprite)

	# Load blacksmith walk animation (4 frames, 64x64 each)
	var sprite_path = "res://assets/characters/lpc/blacksmith/blacksmith_walk.png"

	if not ResourceLoader.exists(sprite_path):
		DebugConfig.log_warning("Blacksmith sprite not found: %s" % sprite_path)
		return

	var texture = ResourceLoader.load(sprite_path, "Texture2D")
	if not texture:
		DebugConfig.log_error("Failed to load blacksmith sprite")
		return

	# Create sprite frames with single frame (stationary blacksmith)
	var sprite_frames = SpriteFrames.new()
	sprite_frames.add_animation("idle")
	sprite_frames.set_animation_loop("idle", false)
	sprite_frames.set_animation_speed("idle", 1.0)

	# Extract frame 3 (facing right) - 256x64 = 4 frames of 64x64 (down, left, up, right)
	var source_img = texture.get_image()
	var frame_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	frame_img.blit_rect(source_img, Rect2i(192, 0, 64, 64), Vector2i(0, 0))  # Frame 3 (right-facing)

	var frame_texture = ImageTexture.create_from_image(frame_img)
	sprite_frames.add_frame("idle", frame_texture)

	# Apply to sprite
	animated_sprite.sprite_frames = sprite_frames
	animated_sprite.play("idle")

	DebugConfig.debug_log("🔨 Blacksmith sprite loaded and animating")

func _physics_process(delta: float) -> void:
	# Face the campfire when idle (no shop open, no player in range)
	if animated_sprite and not player_in_range and (not shop_ui or not shop_ui.visible):
		# Find campfire and face it
		var campfire = get_tree().get_first_node_in_group("campfire")
		if campfire:
			var direction_to_fire = campfire.global_position - global_position
			# Face the fire based on its position relative to blacksmith
			if abs(direction_to_fire.x) > 10:  # Only update if significantly offset
				if direction_to_fire.x > 0:
					animated_sprite.scale.x = abs(animated_sprite.scale.x)  # Face right
				else:
					animated_sprite.scale.x = -abs(animated_sprite.scale.x)  # Face left

	# Subtle idle breathing animation
	if animated_sprite and (not shop_ui or not shop_ui.visible):
		var time = Time.get_ticks_msec() / 1000.0
		var breathe = sin(time * 1.2) * 0.03  # Very subtle breathing
		animated_sprite.scale.y = 1.0 + breathe
		# Maintain horizontal flip for facing direction
		var current_flip = sign(animated_sprite.scale.x)
		animated_sprite.scale.x = current_flip * (1.0 + breathe * 0.5)  # Slight horizontal breathe too

	# Update interaction prompt visibility and position with fade-in
	if interaction_prompt:
		# Only show if we're the active interactable AND player is in range AND shop is closed
		var is_active = InteractionManager.is_active_interactable(self)
		var should_show = player_in_range and is_active and (not shop_ui or not shop_ui.visible)

		# Fade in/out smoothly
		if should_show:
			interaction_prompt.modulate.a = min(1.0, interaction_prompt.modulate.a + delta * 3.0)  # Fade in over ~0.33s
			if not interaction_prompt.visible:
				interaction_prompt.visible = true
				interaction_prompt.modulate.a = 0.0  # Start fully transparent
		else:
			interaction_prompt.modulate.a = max(0.0, interaction_prompt.modulate.a - delta * 5.0)  # Fade out faster
			if interaction_prompt.modulate.a <= 0.0 and interaction_prompt.visible:
				interaction_prompt.visible = false

		# Update position every frame when visible
		if interaction_prompt.visible:
			update_prompt_position()

func _input(event: InputEvent) -> void:
	# Handle F key press when player is in range (edge-triggered, not polling)
	# Only respond if we're the active interactable
	if player_in_range and InteractionManager.is_active_interactable(self) and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:

			# Only open if shop is not already visible (close is handled by ShopUI)
			if not shop_ui or not shop_ui.visible:
				toggle_shop()
				get_viewport().set_input_as_handled()

func load_shop_data() -> void:
	# Load weapons with validation
	var weapons_result = JSONValidator.load_json_file("res://data/shop_weapons.json")
	if weapons_result.success:
		var data = weapons_result.data
		if data.has("weapons") and data["weapons"] is Array:
			for weapon_data in data["weapons"]:
				if weapon_data is Dictionary:
					# Skip weapons not matching vendor's zone (unless vendor_zone is 0 = all zones)
					var weapon_zone = weapon_data.get("zone", 1)
					if vendor_zone > 0 and weapon_zone != vendor_zone:
						continue

					# Skip drop-only items
					if weapon_data.get("drop_only", false):
						continue

					# Validate required weapon fields (removed "type" - now using unified damage)
					if JSONValidator.validate_required_fields(weapon_data, ["name", "weapon_type", "base_damage"], "weapon"):
						var weapon = create_weapon_from_data(weapon_data)
						if weapon:
							weapons_for_sale.append(weapon)
							# Store price alongside weapon
							var price = weapon_data.get("price", 0)
							weapon_prices.append(price)
							print("   Loaded weapon: %s (zone %d, price: %d)" % [weapon.weapon_name, weapon_zone, price])
				else:
					DebugConfig.log_warning("Invalid weapon entry in shop_weapons.json (not a Dictionary)")
		else:
			DebugConfig.log_error("shop_weapons.json missing 'weapons' array")
	else:
		DebugConfig.log_error("Failed to load shop_weapons.json: %s" % weapons_result.error)

	# Load armor with validation
	var armor_result = JSONValidator.load_json_file("res://data/shop_armor.json")
	if armor_result.success:
		var data = armor_result.data
		if data.has("armor") and data["armor"] is Array:
			for armor_data in data["armor"]:
				if armor_data is Dictionary:
					# Validate required armor fields
					if JSONValidator.validate_required_fields(armor_data, ["name", "slot"], "armor"):
						armor_for_sale.append(armor_data)
				else:
					DebugConfig.log_warning("Invalid armor entry in shop_armor.json (not a Dictionary)")
		else:
			DebugConfig.log_error("shop_armor.json missing 'armor' array")
	else:
		DebugConfig.log_error("Failed to load shop_armor.json: %s" % armor_result.error)

	# Add starter gathering tools (free for testing)
	load_starter_tools()

func load_starter_tools() -> void:
	"""Load starter gathering tools (free for testing, like copper armor)"""
	var rusty_axe = {
		"name": "Rusty Axe",
		"description": "An old, weathered axe. Still sharp enough to chop dead wasteland trees.",
		"type": "tool",
		"tool_type": "axe",
		"value": 10,
		"price": 0,  # Free for testing
		"rarity": "COMMON",
		"stackable": false,
		"quantity": 1,
		"efficiency": 1.0,
		"durability": 100
	}

	var rusty_pickaxe = {
		"name": "Rusty Pickaxe",
		"description": "A worn mining pick. Good for breaking rocks and gathering ore.",
		"type": "tool",
		"tool_type": "pickaxe",
		"value": 10,
		"price": 0,  # Free for testing
		"rarity": "COMMON",
		"stackable": false,
		"quantity": 1,
		"efficiency": 1.0,
		"durability": 100
	}

	tools_for_sale.append(rusty_axe)
	tools_for_sale.append(rusty_pickaxe)
	print("   Loaded 2 starter tools (free for testing)")

func create_weapon_from_data(data: Dictionary) -> Weapon:
	"""Create a Weapon resource from JSON data"""
	var weapon = Weapon.new()

	weapon.weapon_name = data.get("name", "Unknown")
	weapon.weapon_type = data.get("weapon_type", "sword")  # Visual type (club, sword, dagger, etc)
	weapon.damage_type = "unified"  # Unified damage system (no slash/pierce/blunt)
	weapon.description = data.get("description", "")
	weapon.base_damage = data.get("base_damage", 5.0)

	# Healing weapon properties
	weapon.attack_mode = data.get("attack_mode", "melee")
	weapon.healing_power = data.get("healing_power", 0.0)
	weapon.heal_radius = data.get("heal_radius", 80.0)

	# Convert attack_speed category to numeric multiplier
	# fast = -0.30 (30% faster), medium = 0.0, slow = +0.30 (30% slower)
	var attack_speed_category = data.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30  # 30% faster (1.5x attack rate)
		"slow":
			weapon.attack_speed_bonus = 0.30   # 30% slower (0.7x attack rate)
		_:  # "medium" or any other value
			weapon.attack_speed_bonus = 0.0

	# Crit chance is already in the right format
	weapon.crit_chance_bonus = data.get("crit_chance", 0.0)
	weapon.required_level = data.get("required_level", 1)
	weapon.can_trade = true

	# Set rarity (support both "Common" and "COMMON" formats)
	var rarity_str = data.get("rarity", "COMMON").to_upper()
	match rarity_str:
		"COMMON":
			weapon.rarity = Weapon.Rarity.COMMON
		"UNCOMMON":
			weapon.rarity = Weapon.Rarity.UNCOMMON
		"RARE":
			weapon.rarity = Weapon.Rarity.RARE
		"EPIC":
			weapon.rarity = Weapon.Rarity.EPIC
		"LEGENDARY":
			weapon.rarity = Weapon.Rarity.LEGENDARY

	return weapon

func toggle_shop() -> void:
	"""Open or close the shop UI"""
	if not shop_ui:
		# Create shop UI if it doesn't exist
		create_shop_ui()
		# Face the player when opening shop
		face_player()
		shop_ui.open_shop(self)
		_on_first_interaction()
	else:
		# Toggle visibility
		if shop_ui.visible:
			shop_ui.close_shop()
		else:
			# Face the player when opening shop
			face_player()
			shop_ui.open_shop(self)
			_on_first_interaction()

func _on_first_interaction() -> void:
	"""Handle first-time player interaction with blacksmith"""
	if has_talked_to_player:
		return

	has_talked_to_player = true

	# Hide the quest indicator "!"
	hide_quest_indicator()

	# Dismiss spawn hints on the player
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if player and player.has_method("dismiss_spawn_hints"):
		player.dismiss_spawn_hints()

	# Tutorial: notify TutorialManager of blacksmith visit
	if TutorialManager and TutorialManager.is_tutorial_active():
		TutorialManager.on_blacksmith_visited()

func create_shop_ui() -> void:
	"""Create the shop UI dynamically"""
	print("🏪 Creating shop UI...")

	# Load the shop UI scene
	var shop_scene = load("res://scenes/ui/shop_ui.tscn")
	if not shop_scene:
		push_error("Failed to load shop UI scene!")
		return

	shop_ui = shop_scene.instantiate()

	# Add to the scene tree (as a child of the root)
	get_tree().root.add_child(shop_ui)

	# Connect signals
	shop_ui.shop_closed.connect(_on_shop_closed)
	shop_ui.item_purchased.connect(_on_item_purchased)

	print("✅ Shop UI created and added to scene tree")

func _on_shop_closed() -> void:
	"""Handle shop closed signal"""
	shop_closed.emit()
	# Face left (default direction toward campfire) after shop closes
	face_left()

func _on_item_purchased(item_name: String, price: int) -> void:
	"""Handle item purchased signal"""
	print("✅ Purchased: %s for %d gold" % [item_name, price])

func get_weapon_price_data(index: int) -> int:
	# Get weapon price from stored array (loaded at startup)
	if index >= 0 and index < weapon_prices.size():
		return weapon_prices[index]
	return 0

func weapon_to_dict(weapon: Weapon, price: int) -> Dictionary:
	"""Convert a Weapon resource to a dictionary for inventory storage"""
	# Convert attack_speed_bonus back to category for display
	var attack_speed_category = "medium"
	if weapon.attack_speed_bonus < -0.15:
		attack_speed_category = "fast"
	elif weapon.attack_speed_bonus > 0.15:
		attack_speed_category = "slow"

	var result = {
		"name": weapon.weapon_name,
		"description": weapon.description,
		"type": "weapon",
		"weapon_type": weapon.weapon_type,  # Visual type (club, sword, staff, etc)
		"base_damage": weapon.base_damage,
		"attack_speed": attack_speed_category,  # Converted from numeric to category
		"crit_chance": weapon.crit_chance_bonus,  # Renamed for consistency
		"required_level": weapon.required_level,
		"rarity": Weapon.Rarity.keys()[weapon.rarity],
		"value": max(1, int(price * 0.5)),  # Sell for 50% of purchase price
		"slot": "mainhand",  # Weapons go in mainhand slot
		"can_trade": weapon.can_trade,
		"stackable": false,
		"quantity": 1
	}

	# Add healing weapon properties if applicable
	if weapon.attack_mode != "melee":
		result["attack_mode"] = weapon.attack_mode
		result["healing_power"] = weapon.healing_power
		result["heal_radius"] = weapon.heal_radius

	return result

func purchase_weapon(index: int) -> bool:
	"""Attempt to purchase a weapon by index"""
	if index < 0 or index >= weapons_for_sale.size():
		return false

	var weapon: Weapon = weapons_for_sale[index]
	var price = get_weapon_price_data(index)

	# Check gold (skip check if item is free)
	if price > 0 and not CharacterStats.can_afford(price):
		print("❌ Not enough gold! Need %d gold" % price)
		return false

	# Purchase successful
	if price == 0 or CharacterStats.spend_gold(price):
		# Convert weapon to dictionary and add to inventory
		var weapon_dict = weapon_to_dict(weapon, price)
		if InventorySystem.add_item(weapon_dict):
			if price == 0:
				print("✅ Took %s (free item)!" % weapon.weapon_name)
			else:
				print("✅ Purchased %s for %d gold!" % [weapon.weapon_name, price])
			return true
		else:
			# Inventory full - refund the gold
			if price > 0:
				CharacterStats.add_gold(price)
			print("❌ Inventory full! Cannot purchase %s" % weapon.weapon_name)
			return false

	return false

func face_player() -> void:
	"""Turn blacksmith to face the player"""
	if not animated_sprite:
		return

	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return

	# Calculate direction to player
	var direction_to_player = player.global_position - global_position

	# Flip sprite based on player's X position relative to blacksmith
	if direction_to_player.x > 0:
		# Player is to the right - face right (positive scale)
		animated_sprite.scale.x = 1
	else:
		# Player is to the left - face left (negative scale, flipped)
		animated_sprite.scale.x = -1

func face_left() -> void:
	"""Reset blacksmith to face left (default direction toward campfire)"""
	if animated_sprite:
		animated_sprite.scale.x = -1  # Flipped = facing left

func has_nearby_lootable_corpse() -> bool:
	"""Check if there's a lootable corpse near the player (within interaction range)"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		return false

	# Get all corpses (enemies that are dead)
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		# Skip non-Enemy nodes (like TrainingDummy) - check if it has the required properties
		if not "is_alive" in enemy:
			continue

		# Check if enemy is a lootable corpse (dead with loot or gold)
		if not enemy.is_alive:
			# Verify corpse has loot properties
			if not "corpse_loot" in enemy or not "corpse_gold" in enemy:
				continue

			if enemy.corpse_loot.size() > 0 or enemy.corpse_gold > 0:
				# Check if corpse is within loot range of player
				var distance_to_player = enemy.global_position.distance_to(player.global_position)
				var loot_range = enemy.corpse_loot_range if "corpse_loot_range" in enemy else 80.0
				if distance_to_player <= loot_range:
					print("💀 Found lootable corpse at distance %.1f (range: %.1f)" % [distance_to_player, loot_range])
					return true

	return false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = true
		# Register with InteractionManager
		var distance = global_position.distance_to(body.global_position)
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.NPC, distance)
		print("💬 %s: %s (Press F to shop)" % [vendor_name, greeting_text])

func _on_body_exited(body: Node) -> void:
	if body.is_in_group(Constants.GROUP_PLAYER):
		player_in_range = false
		# Unregister from InteractionManager
		InteractionManager.unregister_interactable(self)
		print("👋 Player left vendor area")

		# Close shop if player leaves
		if shop_ui and shop_ui.visible:
			shop_ui.close_shop()

# ═══════════════════════════════════════════════════════════════════════════
# TUTORIAL ARROW INDICATOR
# ═══════════════════════════════════════════════════════════════════════════

func create_tutorial_arrow() -> void:
	"""Create flashing arrow indicator above blacksmith for tutorial"""
	if tutorial_arrow and is_instance_valid(tutorial_arrow):
		return  # Already exists

	tutorial_arrow = Polygon2D.new()
	tutorial_arrow.name = "TutorialArrow"

	# Big downward-pointing arrow
	var arrow_size = 20.0
	tutorial_arrow.polygon = PackedVector2Array([
		Vector2(0, arrow_size),           # Tip (bottom, pointing down)
		Vector2(-arrow_size * 0.7, 0),    # Top left
		Vector2(-arrow_size * 0.25, 0),   # Inner top left
		Vector2(-arrow_size * 0.25, -arrow_size * 0.6),  # Tail top left
		Vector2(arrow_size * 0.25, -arrow_size * 0.6),   # Tail top right
		Vector2(arrow_size * 0.25, 0),    # Inner top right
		Vector2(arrow_size * 0.7, 0),     # Top right
	])

	# Bright green color
	tutorial_arrow.color = Color(0.2, 1.0, 0.3, 1.0)

	# Position above blacksmith (above the quest indicator)
	tutorial_arrow.position = Vector2(0, -110)
	tutorial_arrow.z_index = 150

	# Add outline for visibility
	var outline = Line2D.new()
	outline.name = "Outline"
	outline.points = PackedVector2Array([
		Vector2(0, arrow_size),
		Vector2(-arrow_size * 0.7, 0),
		Vector2(-arrow_size * 0.25, 0),
		Vector2(-arrow_size * 0.25, -arrow_size * 0.6),
		Vector2(arrow_size * 0.25, -arrow_size * 0.6),
		Vector2(arrow_size * 0.25, 0),
		Vector2(arrow_size * 0.7, 0),
		Vector2(0, arrow_size)
	])
	outline.width = 3.0
	outline.default_color = Color(0.0, 0.3, 0.0, 1.0)  # Dark green outline
	tutorial_arrow.add_child(outline)

	tutorial_arrow.visible = false
	add_child(tutorial_arrow)

func show_tutorial_arrow() -> void:
	"""Show the big green flashing arrow above blacksmith"""
	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		create_tutorial_arrow()

	if not tutorial_arrow:
		return

	tutorial_arrow.visible = true
	tutorial_arrow.color = Color(0.2, 1.0, 0.3, 1.0)  # Bright green

	# Start bobbing animation
	_start_tutorial_arrow_bob()

	# Start flashing animation
	_start_tutorial_arrow_flash()

	print("🏪 [Vendor] Showing tutorial arrow")

func hide_tutorial_arrow() -> void:
	"""Hide the tutorial arrow"""
	# Stop tweens
	if tutorial_arrow_tween and tutorial_arrow_tween.is_valid():
		tutorial_arrow_tween.kill()
		tutorial_arrow_tween = null

	if tutorial_arrow_flash_tween and tutorial_arrow_flash_tween.is_valid():
		tutorial_arrow_flash_tween.kill()
		tutorial_arrow_flash_tween = null

	if tutorial_arrow and is_instance_valid(tutorial_arrow):
		tutorial_arrow.visible = false

	print("🏪 [Vendor] Hiding tutorial arrow")

func _start_tutorial_arrow_bob() -> void:
	"""Start bobbing animation for tutorial arrow"""
	if tutorial_arrow_tween and tutorial_arrow_tween.is_valid():
		tutorial_arrow_tween.kill()

	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	var base_y = -110.0
	tutorial_arrow_tween = create_tween().set_loops()
	tutorial_arrow_tween.tween_property(tutorial_arrow, "position:y", base_y + 10, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tutorial_arrow_tween.tween_property(tutorial_arrow, "position:y", base_y, 0.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _start_tutorial_arrow_flash() -> void:
	"""Start flashing animation for tutorial arrow"""
	if tutorial_arrow_flash_tween and tutorial_arrow_flash_tween.is_valid():
		tutorial_arrow_flash_tween.kill()

	if not tutorial_arrow or not is_instance_valid(tutorial_arrow):
		return

	tutorial_arrow_flash_tween = create_tween().set_loops()
	tutorial_arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 0.3, 0.25)
	tutorial_arrow_flash_tween.tween_property(tutorial_arrow, "modulate:a", 1.0, 0.25)
