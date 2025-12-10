extends Node2D
class_name GuildWorldTree
## GuildWorldTree - A guild's planted World Tree
## Central hub for guild activities: respawn point, buildings, vendors

signal tree_interacted(tree_data: WorldTreeData)
signal tree_damaged(current_health: int, max_health: int)

# Tree data
var tree_data: WorldTreeData = null
var guild_id: String = ""
var guild_name: String = ""

# Visual components
var trunk_sprite: Sprite2D = null
var canopy_sprite: Sprite2D = null
var glow_effect: PointLight2D = null
var particles: GPUParticles2D = null
var health_bar: ProgressBar = null
var name_label: Label = null

# Interaction
var interaction_area: Area2D = null
var player_in_range: bool = false
var interaction_prompt: Label = null
var current_player: Node = null

# Animation
var sway_time: float = 0.0
var glow_pulse_time: float = 0.0
const SWAY_SPEED: float = 0.5
const SWAY_AMOUNT: float = 2.0  # Degrees
const GLOW_PULSE_SPEED: float = 1.2


func _ready() -> void:
	_create_visuals()
	_create_interaction_area()
	_create_ui_elements()


func initialize(data: WorldTreeData) -> void:
	"""Initialize tree with data from WorldTreeManager"""
	tree_data = data
	guild_id = data.guild_id
	guild_name = data.guild_name

	# Update visuals for rank
	update_rank_visual(data.rank)

	# Update name label
	if name_label:
		name_label.text = "%s\n%s" % [guild_name, data.get_rank_name()]


func _process(delta: float) -> void:
	# Gentle sway animation
	sway_time += delta * SWAY_SPEED
	if canopy_sprite:
		canopy_sprite.rotation_degrees = sin(sway_time) * SWAY_AMOUNT

	# Glow pulse
	glow_pulse_time += delta * GLOW_PULSE_SPEED
	if glow_effect:
		var pulse = (sin(glow_pulse_time) + 1.0) * 0.5
		glow_effect.energy = lerp(0.3, 0.6, pulse)

	# Handle interaction input
	if player_in_range and Input.is_action_just_pressed("interact"):
		_on_interact()


func _create_visuals() -> void:
	"""Create tree visual elements programmatically"""
	# Trunk
	trunk_sprite = Sprite2D.new()
	trunk_sprite.name = "Trunk"
	trunk_sprite.texture = _create_trunk_texture()
	trunk_sprite.z_index = 0
	add_child(trunk_sprite)

	# Canopy (leaves)
	canopy_sprite = Sprite2D.new()
	canopy_sprite.name = "Canopy"
	canopy_sprite.texture = _create_canopy_texture(1)  # Default rank 1
	canopy_sprite.position = Vector2(0, -120)
	canopy_sprite.z_index = 1
	add_child(canopy_sprite)

	# Glow effect
	glow_effect = PointLight2D.new()
	glow_effect.name = "TreeGlow"
	glow_effect.color = Color(0.3, 0.8, 0.3, 1.0)  # Green glow
	glow_effect.energy = 0.5
	glow_effect.texture = _create_radial_gradient()
	glow_effect.texture_scale = 3.0
	glow_effect.position = Vector2(0, -80)
	add_child(glow_effect)

	# Particles (leaves falling, magical sparkles)
	particles = GPUParticles2D.new()
	particles.name = "LeafParticles"
	particles.amount = 15
	particles.lifetime = 3.0
	particles.explosiveness = 0.0
	particles.randomness = 0.5
	particles.position = Vector2(0, -100)

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 60.0
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 10.0
	material.initial_velocity_max = 25.0
	material.gravity = Vector3(0, 30, 0)
	material.scale_min = 2.0
	material.scale_max = 4.0
	material.color = Color(0.3, 0.7, 0.3, 0.6)
	particles.process_material = material
	particles.z_index = 2
	add_child(particles)


func _create_trunk_texture() -> ImageTexture:
	"""Create a simple trunk texture"""
	var img = Image.create(40, 160, false, Image.FORMAT_RGBA8)
	var trunk_color = Color(0.35, 0.25, 0.15)
	var bark_color = Color(0.3, 0.2, 0.1)

	for y in range(160):
		for x in range(40):
			# Tapered trunk
			var width_at_y = lerp(40.0, 20.0, float(y) / 160.0)
			var center = 20.0
			if abs(x - center) <= width_at_y / 2:
				# Add bark texture variation
				var noise = (sin(x * 0.5 + y * 0.1) + sin(y * 0.3)) * 0.1
				var color = trunk_color.lerp(bark_color, noise + 0.5)
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(img)


func _create_canopy_texture(rank: int) -> ImageTexture:
	"""Create canopy texture based on tree rank"""
	var size = 80 + rank * 20  # Canopy grows with rank
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)

	# Color varies by rank
	var base_green = Color(0.2, 0.5, 0.2)
	var bright_green = Color(0.3, 0.7, 0.3)

	# Higher ranks get more golden/magical tint
	if rank >= 5:
		base_green = Color(0.3, 0.6, 0.25)
		bright_green = Color(0.5, 0.8, 0.3)
	if rank >= 7:
		base_green = Color(0.4, 0.65, 0.3)
		bright_green = Color(0.6, 0.9, 0.4)

	for y in range(size):
		for x in range(size):
			var dist = Vector2(x, y).distance_to(center)
			var radius = size / 2.0 - 5

			if dist < radius:
				# Create layered canopy look
				var layer_noise = sin(dist * 0.2 + x * 0.1) * 0.2
				var alpha = 1.0 - (dist / radius) * 0.3 + layer_noise
				alpha = clamp(alpha, 0.0, 1.0)

				var color = base_green.lerp(bright_green, sin(x * 0.15 + y * 0.1) * 0.5 + 0.5)
				color.a = alpha * 0.9
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
	grad_tex.width = 256
	grad_tex.height = 256
	grad_tex.fill = GradientTexture2D.FILL_RADIAL
	grad_tex.fill_from = Vector2(0.5, 0.5)
	grad_tex.fill_to = Vector2(1.0, 0.5)

	return grad_tex


func _create_interaction_area() -> void:
	"""Create Area2D for player interaction"""
	interaction_area = Area2D.new()
	interaction_area.name = "InteractionArea"
	interaction_area.collision_layer = 4
	interaction_area.collision_mask = 1

	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 150.0
	collision.shape = shape
	interaction_area.add_child(collision)

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

	add_child(interaction_area)


func _create_ui_elements() -> void:
	"""Create UI elements (name label, health bar, prompt)"""
	# Name label
	name_label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = "World Tree"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-60, -220)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.z_index = 100
	add_child(name_label)

	# Health bar (only visible when damaged or in combat)
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.min_value = 0
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.size = Vector2(100, 10)
	health_bar.position = Vector2(-50, -200)
	health_bar.visible = false  # Hidden by default
	health_bar.z_index = 100
	add_child(health_bar)

	# Interaction prompt
	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] World Tree"
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.position = Vector2(-60, -180)
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	interaction_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	interaction_prompt.add_theme_constant_override("outline_size", 3)
	interaction_prompt.visible = false
	interaction_prompt.z_index = 100
	add_child(interaction_prompt)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = true
		current_player = body
		interaction_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") or body.name == "Player":
		player_in_range = false
		current_player = null
		interaction_prompt.visible = false


func _on_interact() -> void:
	"""Handle player interaction with tree"""
	if not tree_data:
		return

	# Check if we have a pending water action
	if has_meta("pending_water") and get_meta("pending_water"):
		remove_meta("pending_water")
		_try_water_tree()
		return

	# Emit signal for UI to handle
	tree_interacted.emit(tree_data)

	# Check if player is part of the guild
	var player_guild = _get_player_guild_id()
	if player_guild == guild_id:
		_open_tree_ui()
	else:
		_show_visitor_info()


func _open_tree_ui() -> void:
	"""Open the World Tree management UI for guild members"""
	# Check if player has purified water - offer to water tree
	if _player_has_purified_water():
		_show_water_tree_option()
	else:
		_show_tree_status()


func _show_water_tree_option() -> void:
	"""Show option to water the tree with purified water"""
	if not tree_data:
		return

	# Check if tree can be watered today
	if tree_data.can_water():
		var message = "%s\nGrowth Bonus: +%.0f%%\n\nYou have Purified Water!\nPress [F] again to water your tree." % [
			tree_data.get_rank_name(),
			tree_data.growth_bonus_accumulated * 100
		]
		if NotificationManager:
			NotificationManager.show_notification("World Tree", message)

		# Set flag to water on next interact
		set_meta("pending_water", true)
	else:
		var message = "Already watered today!\nReturn tomorrow for more growth bonus."
		if NotificationManager:
			NotificationManager.show_notification("World Tree", message)


func _show_tree_status() -> void:
	"""Show tree status when player has no water"""
	if not tree_data:
		return

	var status = "%s - Rank %d\n" % [tree_data.get_rank_name(), tree_data.rank]
	status += "Health: %d/%d\n" % [tree_data.health, tree_data.max_health]
	status += "Growth Bonus: +%.0f%%\n" % [tree_data.growth_bonus_accumulated * 100]

	if tree_data.can_water():
		status += "\nBring Purified Water to boost growth!"
	else:
		status += "\nWatered today!"

	if NotificationManager:
		NotificationManager.show_notification("World Tree", status)


func _try_water_tree() -> void:
	"""Attempt to water the tree with purified water"""
	if not tree_data or not current_player:
		return

	var player_id = _get_player_id()

	# Use WorldTreeManager to water
	if WorldTreeManager and WorldTreeManager.water_tree(tree_data.tree_id, player_id, false):
		_show_water_success()
		_play_water_effect()
	else:
		if NotificationManager:
			NotificationManager.show_notification("World Tree", "Cannot water tree right now.")


func _show_water_success() -> void:
	"""Show success message after watering"""
	if not tree_data:
		return

	var message = "Tree watered!\nGrowth bonus now: +%.0f%%" % [tree_data.growth_bonus_accumulated * 100]
	if NotificationManager:
		NotificationManager.show_notification("World Tree", message)


func _play_water_effect() -> void:
	"""Play visual effect when tree is watered"""
	if glow_effect:
		# Bright blue pulse
		var tween = create_tween()
		tween.tween_property(glow_effect, "color", Color(0.3, 0.6, 1.0), 0.3)
		tween.tween_property(glow_effect, "energy", 1.5, 0.3)
		tween.tween_property(glow_effect, "color", Color(0.3, 0.8, 0.3), 1.0)
		tween.tween_property(glow_effect, "energy", 0.5, 1.0)


func _player_has_purified_water() -> bool:
	"""Check if player has Purified Water in inventory"""
	if not InventorySystem:
		return false

	for item in InventorySystem.inventory_items:
		if item and _is_purified_water(item):
			return true
	return false


func _is_purified_water(item: Dictionary) -> bool:
	if item.get("consumable_type") == "purified_water":
		return true
	if item.get("name") == "Purified Water":
		return true
	return false


func _get_player_id() -> String:
	if MantleAuth and MantleAuth.is_logged_in():
		return MantleAuth.get_user_id()
	return "local_player"


func _show_visitor_info() -> void:
	"""Show tree info to non-guild visitors"""
	if not tree_data:
		return

	var message = "%s's %s\nRank %d - %d/%d HP" % [
		guild_name,
		tree_data.get_rank_name(),
		tree_data.rank,
		tree_data.health,
		tree_data.max_health
	]

	if NotificationManager:
		NotificationManager.show_notification("World Tree", message)


func update_rank_visual(rank: int) -> void:
	"""Update tree appearance for new rank"""
	if canopy_sprite:
		canopy_sprite.texture = _create_canopy_texture(rank)
		# Scale up slightly with rank
		var scale_factor = 1.0 + (rank - 1) * 0.15
		canopy_sprite.scale = Vector2(scale_factor, scale_factor)

	# Update glow intensity
	if glow_effect:
		glow_effect.energy = 0.3 + rank * 0.1
		# Higher ranks get more golden glow
		if rank >= 5:
			glow_effect.color = Color(0.5, 0.8, 0.3)
		if rank >= 7:
			glow_effect.color = Color(0.7, 0.9, 0.4)

	# Update particle count
	if particles:
		particles.amount = 10 + rank * 5


func take_damage(amount: int, attacker_id: String = "") -> void:
	"""Handle damage to the tree"""
	if not tree_data:
		return

	tree_data.health = max(0, tree_data.health - amount)

	# Update health bar
	if health_bar:
		health_bar.visible = true
		health_bar.max_value = tree_data.max_health
		health_bar.value = tree_data.health

	tree_damaged.emit(tree_data.health, tree_data.max_health)

	# Check for destruction
	if tree_data.health <= 0:
		_on_tree_destroyed(attacker_id)


func _on_tree_destroyed(attacker_id: String) -> void:
	"""Handle tree destruction"""
	print("[WorldTree] Tree destroyed! Attacker: %s" % attacker_id)

	# Notify WorldTreeManager
	if WorldTreeManager:
		WorldTreeManager.tree_destroyed.emit(tree_data.tree_id, attacker_id)

	# Play destruction effect
	_play_destruction_effect()


func _play_destruction_effect() -> void:
	"""Visual effect when tree is destroyed"""
	var tween = create_tween()
	tween.set_parallel(true)

	if trunk_sprite:
		tween.tween_property(trunk_sprite, "modulate:a", 0.0, 2.0)
	if canopy_sprite:
		tween.tween_property(canopy_sprite, "modulate:a", 0.0, 2.0)
		tween.tween_property(canopy_sprite, "position:y", 0.0, 2.0)
	if glow_effect:
		tween.tween_property(glow_effect, "energy", 0.0, 1.0)

	tween.chain().tween_callback(queue_free)


func _get_player_guild_id() -> String:
	"""Get the current player's guild ID"""
	if GroupManager and GroupManager.has_group():
		return "guild_%d" % GroupManager.group_leader

	# Solo players have their own "guild"
	if MantleAuth and MantleAuth.is_logged_in():
		return "solo_guild_%s" % MantleAuth.get_user_id()

	return "solo_guild_local_player"
