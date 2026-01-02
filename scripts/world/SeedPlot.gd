extends Area2D
class_name SeedPlot
## SeedPlot - An unclaimed location where players can plant World Trees
## When a player with a World Tree Seed interacts, they can plant their guild's tree

signal plot_claimed(tree_data: WorldTreeData)

# Plot state
var chunk_id: int = 0
var is_claimed: bool = false

# Visual references
var glow_effect: PointLight2D = null
var particles: GPUParticles2D = null
var ground_sprite: Sprite2D = null
var rune_sprites: Array[Sprite2D] = []

# Interaction
var player_in_range: bool = false
var interaction_prompt: Label = null
var current_player: Node = null

# Animation
var glow_pulse_time: float = 0.0
const GLOW_PULSE_SPEED: float = 1.5
const GLOW_MIN_ENERGY: float = 0.3
const GLOW_MAX_ENERGY: float = 0.7


func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Skip visuals on dedicated server
	if "--server" in OS.get_cmdline_user_args():
		set_process(false)
		return

	# Create visuals
	_create_visuals()

	# Create interaction prompt
	_create_interaction_prompt()


func _process(delta: float) -> void:
	if is_claimed:
		return

	# Animate glow pulse
	glow_pulse_time += delta * GLOW_PULSE_SPEED
	if glow_effect:
		var pulse = (sin(glow_pulse_time) + 1.0) * 0.5  # 0 to 1
		glow_effect.energy = lerp(GLOW_MIN_ENERGY, GLOW_MAX_ENERGY, pulse)

	# Animate rune rotation
	for i in range(rune_sprites.size()):
		var rune = rune_sprites[i]
		if rune:
			rune.rotation += delta * 0.2 * (1 if i % 2 == 0 else -1)

	# Handle interaction input
	if player_in_range and Input.is_action_just_pressed("interact"):
		_try_interact()


func set_chunk_id(id: int) -> void:
	chunk_id = id


func _create_visuals() -> void:
	# Ground circle (fertile soil patch)
	ground_sprite = Sprite2D.new()
	ground_sprite.name = "GroundSprite"
	# Create a simple colored circle texture programmatically
	var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var center = Vector2(64, 64)
	for x in range(128):
		for y in range(128):
			var dist = Vector2(x, y).distance_to(center)
			if dist < 60:
				var alpha = 1.0 - (dist / 60.0) * 0.3
				img.set_pixel(x, y, Color(0.2, 0.4, 0.15, alpha * 0.6))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	var tex = ImageTexture.create_from_image(img)
	ground_sprite.texture = tex
	ground_sprite.scale = Vector2(5, 5)
	ground_sprite.z_index = -10
	add_child(ground_sprite)

	# Glowing light effect
	glow_effect = PointLight2D.new()
	glow_effect.name = "GlowLight"
	glow_effect.color = Color(0.3, 0.8, 0.3, 1.0)  # Green glow
	glow_effect.energy = 0.5
	glow_effect.texture = _create_radial_gradient()
	glow_effect.texture_scale = 2.0
	add_child(glow_effect)

	# Particles (magical sparkles rising)
	particles = GPUParticles2D.new()
	particles.name = "MagicParticles"
	particles.amount = 20
	particles.lifetime = 2.0
	particles.explosiveness = 0.0
	particles.randomness = 0.5

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 150.0
	material.direction = Vector3(0, -1, 0)
	material.spread = 15.0
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.gravity = Vector3(0, -20, 0)
	material.scale_min = 2.0
	material.scale_max = 4.0
	material.color = Color(0.4, 1.0, 0.4, 0.8)
	particles.process_material = material
	particles.z_index = 5
	add_child(particles)

	# Create ancient rune circles
	_create_rune_circles()


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


func _create_rune_circles() -> void:
	# Create 3 rotating rune circles at different radii
	var radii = [80.0, 120.0, 160.0]
	var colors = [
		Color(0.3, 0.7, 0.3, 0.4),
		Color(0.2, 0.6, 0.2, 0.3),
		Color(0.1, 0.5, 0.1, 0.2)
	]

	for i in range(3):
		var rune = Sprite2D.new()
		rune.name = "RuneCircle%d" % i

		# Create dashed circle texture
		var img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
		var center = Vector2(64, 64)
		var radius = 56.0
		for angle in range(0, 360, 10):
			var rad = deg_to_rad(angle)
			var pos = center + Vector2(cos(rad), sin(rad)) * radius
			# Draw small segment
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var px = int(pos.x + dx)
					var py = int(pos.y + dy)
					if px >= 0 and px < 128 and py >= 0 and py < 128:
						if angle % 20 < 10:  # Dashed effect
							img.set_pixel(px, py, colors[i])

		var tex = ImageTexture.create_from_image(img)
		rune.texture = tex
		rune.scale = Vector2(radii[i] / 56.0, radii[i] / 56.0)
		rune.z_index = -5
		add_child(rune)
		rune_sprites.append(rune)


func _create_interaction_prompt() -> void:
	interaction_prompt = Label.new()
	interaction_prompt.name = "InteractionPrompt"
	interaction_prompt.text = "[F] Examine Plot"
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.position = Vector2(-80, -200)
	interaction_prompt.add_theme_font_size_override("font_size", 16)
	interaction_prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	interaction_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	interaction_prompt.add_theme_constant_override("outline_size", 3)
	interaction_prompt.visible = false
	interaction_prompt.z_index = 100
	add_child(interaction_prompt)


func _on_body_entered(body: Node2D) -> void:
	if is_claimed:
		return

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


func _update_prompt() -> void:
	if not current_player:
		return

	# World Tree v2.1 - Check if plot is claimed
	var manager = get_node_or_null("/root/ChunkExpansionManager")
	if manager:
		var plot_data = manager.get_seed_plot(chunk_id)
		if plot_data.has("owner_id") and plot_data.owner_id != "":
			is_claimed = true
			var rank = plot_data.get("tree_rank", 0)
			interaction_prompt.text = "[F] Manage Tree (Rank %d)" % rank
			interaction_prompt.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		else:
			is_claimed = false

			# Check if player has World Tree Seed in inventory
			var has_seed = _player_has_seed()

			if has_seed:
				interaction_prompt.text = "[F] Plant Seed"
				interaction_prompt.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
			else:
				interaction_prompt.text = "[F] Seed Plot (No Seed)"
				interaction_prompt.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	else:
		interaction_prompt.text = "[F] Examine Plot"
		interaction_prompt.add_theme_color_override("font_color", Color(1, 0.9, 0.5))


func _try_interact() -> void:
	if not current_player:
		return

	# Check if plot is already claimed
	if is_claimed:
		# Already claimed - open UI for management
		_open_world_tree_ui()
		return

	# Unclaimed plot - always open UI (it will show seed requirement)
	print("🌳 Opening World Tree UI for chunk %d" % chunk_id)
	_open_world_tree_ui()


func _open_world_tree_ui() -> void:
	# Find WorldTreeUI in the scene tree
	var world_tree_ui = get_tree().get_first_node_in_group("world_tree_ui")

	if world_tree_ui:
		world_tree_ui.open_for_plot(chunk_id, current_player)
	else:
		push_warning("⚠️ WorldTreeUI not found in scene tree!")
		_show_message("World Tree UI not available. Add WorldTreeUI to your scene!")


# Legacy function - no longer used but kept for compatibility
func _plant_tree(player_id: String, guild_id: String, guild_name: String) -> void:
	_show_message("Use the World Tree UI to claim this plot!")


func _hide_plot() -> void:
	# Fade out plot visuals
	var tween = create_tween()
	tween.set_parallel(true)

	if ground_sprite:
		tween.tween_property(ground_sprite, "modulate:a", 0.0, 1.0)
	if glow_effect:
		tween.tween_property(glow_effect, "energy", 0.0, 1.0)
	if particles:
		particles.emitting = false
	for rune in rune_sprites:
		if rune:
			tween.tween_property(rune, "modulate:a", 0.0, 1.0)

	interaction_prompt.visible = false

	# Queue free after fade
	tween.chain().tween_callback(queue_free)


func _show_message(text: String) -> void:
	if NotificationManager:
		NotificationManager.show_notification("Seed Plot", text)
	else:
		print("[SeedPlot] %s" % text)


func _get_player_id() -> String:
	# Get player's Ashbane account ID
	if AshbaneAuth and AshbaneAuth.is_logged_in():
		return str(AshbaneAuth.user_id)
	return "local_player"


func _get_guild_id() -> String:
	# TODO: Get from GroupManager or guild system
	# For now, use a placeholder
	if GroupManager and GroupManager.has_group():
		return "guild_%d" % GroupManager.group_leader
	return "solo_guild_%s" % _get_player_id()


func _get_guild_name() -> String:
	# TODO: Get from GroupManager or guild system
	if GroupManager and GroupManager.has_group():
		# Use leader's name as guild name for now
		return "%s's Guild" % GroupManager.get_member_name(GroupManager.group_leader)
	return "The Wanderers"


func _player_has_seed() -> bool:
	# Check if player has a World Tree Seed in their inventory
	if not current_player:
		return false

	# Try to get InventorySystem from player
	var inventory = current_player.get_node_or_null("InventorySystem")
	if not inventory:
		# Fallback: try to get global inventory system
		inventory = get_node_or_null("/root/InventorySystem")

	if inventory and inventory.has_method("has_item"):
		return inventory.has_item("world_tree_seed")

	return false


func _consume_seed() -> bool:
	# Remove World Tree Seed from player's inventory
	if not current_player:
		return false

	# Try to get InventorySystem from player
	var inventory = current_player.get_node_or_null("InventorySystem")
	if not inventory:
		# Fallback: try to get global inventory system
		inventory = get_node_or_null("/root/InventorySystem")

	if inventory and inventory.has_method("remove_item"):
		return inventory.remove_item("world_tree_seed", 1)

	return false
