extends Area2D
class_name CleanseableLavaPool
## CleanseableLavaPool - A lava pool that can be cleansed to collect purified water
## Players with Empty Vials can cleanse the pool (3-sec channel) to get Purified Water

signal cleanse_started(player: Node)
signal cleanse_completed(player: Node)
signal cleanse_cancelled(player: Node)
signal cooldown_started()
signal cooldown_ended()

# Pool state
enum PoolState { CORRUPTED, CLEANSING, PURIFIED, COOLDOWN }
var state: PoolState = PoolState.CORRUPTED

# Cleansing
const CLEANSE_DURATION: float = 3.0  # 3 second channel
const COOLDOWN_DURATION: float = 300.0  # 5 minutes
var cleanse_progress: float = 0.0
var cleansing_player: Node = null
var cooldown_remaining: float = 0.0

# Interaction
var player_in_range: bool = false
var current_player: Node = null
var interaction_prompt: Label = null
var progress_bar: ProgressBar = null

# Visual elements
var base_color: Color = Color(0.8, 0.3, 0.1)  # Orange/red lava
var purified_color: Color = Color(0.3, 0.6, 0.9)  # Blue purified
var glow_light: PointLight2D = null
var pool_sprite: Sprite2D = null


func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Setup collision
	collision_layer = 4  # Interactable layer
	collision_mask = 1  # Player layer

	# Create visuals
	_create_visuals()
	_create_ui_elements()


func _process(delta: float) -> void:
	match state:
		PoolState.CLEANSING:
			_process_cleansing(delta)
		PoolState.COOLDOWN:
			_process_cooldown(delta)

	# Handle interaction input
	if player_in_range and Input.is_action_just_pressed("interact"):
		_try_interact()

	# Cancel cleanse if player moves or takes damage
	if state == PoolState.CLEANSING and cleansing_player:
		if not _is_player_still_channeling(cleansing_player):
			_cancel_cleanse()


func _process_cleansing(delta: float) -> void:
	cleanse_progress += delta

	# Update progress bar
	if progress_bar:
		progress_bar.value = (cleanse_progress / CLEANSE_DURATION) * 100

	# Check if cleanse complete
	if cleanse_progress >= CLEANSE_DURATION:
		_complete_cleanse()


func _process_cooldown(delta: float) -> void:
	cooldown_remaining -= delta

	if cooldown_remaining <= 0:
		_end_cooldown()


func _try_interact() -> void:
	if not current_player:
		return

	match state:
		PoolState.CORRUPTED:
			_start_cleanse()
		PoolState.PURIFIED:
			_collect_water()
		PoolState.CLEANSING:
			# Already cleansing, ignore
			pass
		PoolState.COOLDOWN:
			_show_message("This pool is recovering. Wait %d seconds." % int(cooldown_remaining))


func _start_cleanse() -> void:
	if not current_player:
		return

	# Check if player has Empty Vial
	if not _player_has_empty_vial(current_player):
		_show_message("You need an Empty Vial to cleanse this pool.")
		return

	state = PoolState.CLEANSING
	cleansing_player = current_player
	cleanse_progress = 0.0

	# Show progress bar
	if progress_bar:
		progress_bar.visible = true
		progress_bar.value = 0

	# Update prompt
	if interaction_prompt:
		interaction_prompt.text = "Cleansing..."
		interaction_prompt.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))

	cleanse_started.emit(current_player)
	print("[CleanseableLavaPool] Cleanse started by player")


func _complete_cleanse() -> void:
	state = PoolState.PURIFIED

	# Hide progress bar
	if progress_bar:
		progress_bar.visible = false

	# Visual transformation
	_transform_to_purified()

	# Update prompt
	_update_prompt()

	cleanse_completed.emit(cleansing_player)
	cleansing_player = null

	print("[CleanseableLavaPool] Pool cleansed! Now purified.")


func _cancel_cleanse() -> void:
	state = PoolState.CORRUPTED
	cleanse_progress = 0.0

	# Hide progress bar
	if progress_bar:
		progress_bar.visible = false

	# Update prompt
	_update_prompt()

	cleanse_cancelled.emit(cleansing_player)
	cleansing_player = null

	_show_message("Cleanse interrupted!")
	print("[CleanseableLavaPool] Cleanse cancelled")


func _collect_water() -> void:
	if not current_player:
		return

	# Check if player has Empty Vial
	if not _player_has_empty_vial(current_player):
		_show_message("You need an Empty Vial to collect water.")
		return

	# Consume Empty Vial and give Purified Water
	if _consume_empty_vial_give_water(current_player):
		_show_message("Collected Purified Water!")

		# Start cooldown
		_start_cooldown()

		print("[CleanseableLavaPool] Water collected, entering cooldown")
	else:
		_show_message("Your inventory is full!")


func _start_cooldown() -> void:
	state = PoolState.COOLDOWN
	cooldown_remaining = COOLDOWN_DURATION

	# Visual transformation back to corrupted
	_transform_to_corrupted()

	# Update prompt
	_update_prompt()

	cooldown_started.emit()


func _end_cooldown() -> void:
	state = PoolState.CORRUPTED
	cooldown_remaining = 0.0

	# Already in corrupted visual state
	_update_prompt()

	cooldown_ended.emit()
	print("[CleanseableLavaPool] Cooldown ended, pool ready again")


func _is_player_still_channeling(player: Node) -> bool:
	"""Check if player can continue channeling (not moving, not in combat)"""
	if not is_instance_valid(player):
		return false

	# Check if player is still in range
	if not player_in_range:
		return false

	# Check if player is holding interact key (optional - could require holding)
	# For now, just check they're in range

	return true


# ═══════════════════════════════════════════════════════════════════════════════
# VISUALS
# ═══════════════════════════════════════════════════════════════════════════════

func _create_visuals() -> void:
	# Create pool sprite
	pool_sprite = Sprite2D.new()
	pool_sprite.name = "PoolSprite"
	pool_sprite.texture = _create_pool_texture()
	pool_sprite.z_index = -5
	add_child(pool_sprite)

	# Glow light
	glow_light = PointLight2D.new()
	glow_light.name = "PoolGlow"
	glow_light.color = Color(1.0, 0.5, 0.2)
	glow_light.energy = 0.6
	glow_light.texture = _create_radial_gradient()
	glow_light.texture_scale = 2.0
	add_child(glow_light)


func _create_pool_texture() -> ImageTexture:
	"""Create a small lava pool texture"""
	var size = 80
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)

	for y in range(size):
		for x in range(size):
			var dist = Vector2(x, y).distance_to(center)
			var radius = size / 2.0 - 5

			if dist < radius:
				var t = dist / radius
				var color = base_color.lerp(Color(1.0, 0.6, 0.2), 1.0 - t)
				color.a = 1.0 - t * 0.3
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)


func _create_radial_gradient() -> Texture2D:
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.3, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.6),
		Color(1, 1, 1, 0.2),
		Color(1, 1, 1, 0)
	])

	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = gradient
	grad_tex.width = 128
	grad_tex.height = 128
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)

	return grad_tex


func _transform_to_purified() -> void:
	"""Visual transition to purified state"""
	var tween = create_tween()

	if pool_sprite:
		tween.tween_property(pool_sprite, "modulate", purified_color, 1.0)

	if glow_light:
		tween.parallel().tween_property(glow_light, "color", Color(0.3, 0.6, 1.0), 1.0)


func _transform_to_corrupted() -> void:
	"""Visual transition back to corrupted state"""
	var tween = create_tween()

	if pool_sprite:
		tween.tween_property(pool_sprite, "modulate", Color.WHITE, 1.0)

	if glow_light:
		tween.parallel().tween_property(glow_light, "color", Color(1.0, 0.5, 0.2), 1.0)


# ═══════════════════════════════════════════════════════════════════════════════
# UI ELEMENTS
# ═══════════════════════════════════════════════════════════════════════════════

func _create_ui_elements() -> void:
	# Interaction prompt
	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Cleanse Pool"
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.position = Vector2(-60, -60)
	interaction_prompt.add_theme_font_size_override("font_size", 14)
	interaction_prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	interaction_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	interaction_prompt.add_theme_constant_override("outline_size", 2)
	interaction_prompt.visible = false
	interaction_prompt.z_index = 100
	add_child(interaction_prompt)

	# Progress bar for channeling
	progress_bar = ProgressBar.new()
	progress_bar.name = "CleanseProgress"
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	progress_bar.size = Vector2(80, 8)
	progress_bar.position = Vector2(-40, -80)
	progress_bar.visible = false
	progress_bar.z_index = 100
	add_child(progress_bar)


func _update_prompt() -> void:
	if not interaction_prompt:
		return

	match state:
		PoolState.CORRUPTED:
			interaction_prompt.text = "[F] Cleanse Pool"
			interaction_prompt.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
		PoolState.PURIFIED:
			interaction_prompt.text = "[F] Collect Water"
			interaction_prompt.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
		PoolState.COOLDOWN:
			var mins = int(cooldown_remaining / 60)
			var secs = int(cooldown_remaining) % 60
			interaction_prompt.text = "Recovering... %d:%02d" % [mins, secs]
			interaction_prompt.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		PoolState.CLEANSING:
			interaction_prompt.text = "Cleansing..."
			interaction_prompt.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))


# ═══════════════════════════════════════════════════════════════════════════════
# INTERACTION
# ═══════════════════════════════════════════════════════════════════════════════

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = true
		current_player = body
		_update_prompt()
		interaction_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = false
		current_player = null
		interaction_prompt.visible = false

		# Cancel cleanse if player leaves
		if state == PoolState.CLEANSING:
			_cancel_cleanse()


func _show_message(text: String) -> void:
	if NotificationManager:
		NotificationManager.show_notification("Lava Pool", text)
	else:
		print("[CleanseableLavaPool] %s" % text)


# ═══════════════════════════════════════════════════════════════════════════════
# INVENTORY HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _player_has_empty_vial(_player: Node) -> bool:
	if not InventorySystem:
		return false

	for item in InventorySystem.inventory_items:
		if item and _is_empty_vial(item):
			return true

	return false


func _is_empty_vial(item: Dictionary) -> bool:
	if item.get("consumable_type") == "empty_vial":
		return true
	if item.get("name") == "Empty Vial":
		return true
	return false


func _consume_empty_vial_give_water(_player: Node) -> bool:
	if not InventorySystem:
		return false

	# Find and consume Empty Vial
	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item and _is_empty_vial(item):
			# Handle stacks
			var quantity = item.get("quantity", 1)
			if quantity > 1:
				item["quantity"] = quantity - 1
			else:
				InventorySystem.inventory_items[i] = null

			# Create Purified Water item
			var purified_water = {
				"name": "Purified Water",
				"description": "Crystal clear water from a cleansed lava pool. Use to water your World Tree for a growth bonus.",
				"type": "consumable",
				"consumable_type": "purified_water",
				"value": 100,
				"rarity": "UNCOMMON",
				"stackable": true,
				"max_stack": 10,
				"quantity": 1,
			}

			# Add to inventory
			if InventorySystem.add_item(purified_water):
				InventorySystem.inventory_changed.emit()
				return true
			else:
				# Refund the vial if inventory is full
				if quantity > 1:
					item["quantity"] = quantity
				else:
					InventorySystem.inventory_items[i] = item
				return false

	return false
