extends Node
## MantleCosmetics - Maps Mantle achievements to in-game cosmetics
## Core principle: Cosmetic only, NO combat advantage

signal cosmetics_calculated(cosmetics: Dictionary)
signal transformation_started(player: Node)
signal transformation_completed(player: Node)

# ═══════════════════════════════════════════════════════════════════════════
# TIER-BASED COSMETICS (Automatic based on Mantle tier)
# ═══════════════════════════════════════════════════════════════════════════

const TIER_COSMETICS = {
	"initiate": {
		"armor_set": "cloth_basic",
		"effects": [],
		"title_prefix": "",
		"glow_color": Color(0.4, 0.4, 0.4, 0.0),  # No glow
		"badge_color": Color(0.4, 0.4, 0.4)  # #666666
	},
	"bronze": {
		"armor_set": "leather_bronze_trim",
		"effects": ["bronze_accent"],
		"title_prefix": "",
		"glow_color": Color(0.545, 0.271, 0.075, 0.3),  # #8B4513
		"badge_color": Color(0.804, 0.498, 0.196)  # #CD7F32
	},
	"silver": {
		"armor_set": "chainmail_silver",
		"effects": ["silver_trim"],
		"title_prefix": "",
		"glow_color": Color(0.502, 0.502, 0.502, 0.4),  # #808080
		"badge_color": Color(0.753, 0.753, 0.753)  # #C0C0C0
	},
	"gold": {
		"armor_set": "plate_gold",
		"effects": ["gold_trim", "subtle_glow"],
		"title_prefix": "Honored ",
		"glow_color": Color(0.855, 0.647, 0.125, 0.5),  # #DAA520
		"badge_color": Color(1.0, 0.843, 0.0)  # #FFD700
	},
	"platinum": {
		"armor_set": "plate_platinum",
		"effects": ["platinum_trim", "blue_glow"],
		"title_prefix": "Elite ",
		"glow_color": Color(0.627, 0.847, 0.937, 0.6),  # #A0D8EF
		"badge_color": Color(0.898, 0.894, 0.886)  # #E5E4E2
	},
	"diamond": {
		"armor_set": "crystal_armor",
		"effects": ["crystal_sparkle", "light_refraction"],
		"title_prefix": "Illustrious ",
		"glow_color": Color(0.251, 0.878, 0.816, 0.7),  # #40E0D0
		"badge_color": Color(0.725, 0.949, 1.0)  # #B9F2FF
	},
	"legendary": {
		"armor_set": "infernal_plate",
		"effects": ["ember_particles", "heat_distortion"],
		"title_prefix": "Legendary ",
		"glow_color": Color(1.0, 0.271, 0.0, 0.8),  # #FF4500
		"badge_color": Color(1.0, 0.4, 0.0)  # #FF6600
	},
	"mythic": {
		"armor_set": "ethereal_mythic",
		"effects": ["mythic_aura", "particle_trail", "ground_runes"],
		"title_prefix": "Mythic ",
		"glow_color": Color(0.0, 1.0, 1.0, 0.9),  # #00FFFF
		"badge_color": Color(1.0, 0.0, 1.0)  # #FF00FF
	}
}

# ═══════════════════════════════════════════════════════════════════════════
# PROVIDER-SPECIFIC COSMETICS (Linking platforms unlocks themed items)
# ═══════════════════════════════════════════════════════════════════════════

const PROVIDER_COSMETICS = {
	"steam": {
		"badge": "steam_verified_badge",
		"accent_color": Color(0.1, 0.1, 0.1),
		"cape_trim": "steam_gray"
	},
	"battlenet": {
		"badge": "blizzard_verified_badge",
		"accent_color": Color(0.0, 0.68, 0.94),
		"shoulder_effect": "ice_crystals"
	},
	"xbox": {
		"badge": "xbox_verified_badge",
		"accent_color": Color(0.0, 0.5, 0.0),
		"aura_tint": Color(0.0, 0.8, 0.0, 0.3)
	},
	"playstation": {
		"badge": "psn_verified_badge",
		"accent_color": Color(0.0, 0.2, 0.6),
		"aura_tint": Color(0.0, 0.3, 0.8, 0.3)
	},
	"discord": {
		"badge": "discord_verified_badge",
		"accent_color": Color(0.34, 0.4, 0.95)
	}
}

# ═══════════════════════════════════════════════════════════════════════════
# SPECIFIC ACHIEVEMENT COSMETICS (Individual achievements unlock items)
# ═══════════════════════════════════════════════════════════════════════════

const ACHIEVEMENT_COSMETICS = {
	# Dark Souls 3 - 100% completion
	"steam_374320_THE_DARK_SOUL": {
		"cape": "ashen_one_cape",
		"weapon_skin": "coiled_sword",
		"walk_effect": "ember_footsteps",
		"emote": "praise_the_sun"
	},

	# Elden Ring - Elden Lord ending
	"steam_1245620_ELDEN_LORD": {
		"crown": "elden_crown",
		"aura": "erdtree_blessing",
		"idle_particles": "golden_leaves"
	},

	# Sekiro - All skills
	"steam_814380_ALL_SKILLS": {
		"weapon_skin": "mortal_blade",
		"dash_effect": "mist_raven"
	},

	# WoW - Thunderfury (Battle.net)
	"battlenet_wow_thunderfury": {
		"weapon_skin": "thunderfury_blessed_blade",
		"idle_emote": "did_someone_say",
		"attack_effect": "chain_lightning"
	},

	# WoW - Sulfuras
	"battlenet_wow_sulfuras": {
		"weapon_skin": "sulfuras_hand_of_ragnaros",
		"attack_effect": "fire_burst"
	}
}

# ═══════════════════════════════════════════════════════════════════════════
# ACHIEVEMENT COUNT MILESTONES
# ═══════════════════════════════════════════════════════════════════════════

const MILESTONE_COSMETICS = {
	100: {
		"title": "Achiever",
		"unlock_message": "100 achievements - you're getting started"
	},
	500: {
		"title": "Dedicated",
		"cape_trim": "silver_thread",
		"unlock_message": "500 achievements - serious gamer"
	},
	1000: {
		"title": "Veteran",
		"portrait_frame": "veteran_frame",
		"unlock_message": "1000 achievements - respect earned"
	},
	2500: {
		"title": "Legend",
		"aura": "legendary_aura",
		"unlock_message": "2500 achievements - walking history"
	},
	5000: {
		"title": "Mythic Hunter",
		"ground_effect": "mythic_footsteps",
		"unlock_message": "5000 achievements - the dedication is real"
	},
	10000: {
		"title": "The Completionist",
		"full_transformation": true,
		"unlock_message": "10000 achievements - you ARE the game"
	}
}

# ═══════════════════════════════════════════════════════════════════════════
# LPC LAYER MAPPING
# Maps Mantle cosmetics to LPC sprite layers
# ═══════════════════════════════════════════════════════════════════════════

# Layer indices matching SimpleLPCSprite
const LPC_LAYERS = {
	"shadow": 0,
	"body": 1,
	"head": 2,
	"hair": 3,
	"pants": 4,
	"shirt": 5,
	"arms": 6,
	"boots": 7,
	"hands": 8,
	"weapon": 9
	# Layer 10+ reserved for effects (auras, particles, trails)
}

# Tier to armor asset mapping
const TIER_ARMOR_PATHS = {
	"initiate": {
		"pants": "res://assets/characters/pants/brown_pants",
		"shirt": "res://assets/characters/shirt/brown_shirt",
		"boots": "res://assets/characters/boots/brown_boots"
	},
	"bronze": {
		"pants": "res://assets/equipment/armor/tier1/legs/leather_bronze",
		"shirt": "res://assets/equipment/armor/tier1/chest/leather_bronze",
		"boots": "res://assets/equipment/armor/tier1/feet/leather_bronze"
	},
	"silver": {
		"pants": "res://assets/equipment/armor/tier1/legs/chainmail_silver",
		"shirt": "res://assets/equipment/armor/tier1/chest/chainmail_silver",
		"boots": "res://assets/equipment/armor/tier1/feet/chainmail_silver"
	},
	"gold": {
		"pants": "res://assets/equipment/armor/tier1/legs/plate_gold",
		"shirt": "res://assets/equipment/armor/tier1/chest/plate_gold",
		"boots": "res://assets/equipment/armor/tier1/feet/plate_gold"
	},
	"platinum": {
		"pants": "res://assets/equipment/armor/tier2/legs/plate_platinum",
		"shirt": "res://assets/equipment/armor/tier2/chest/plate_platinum",
		"boots": "res://assets/equipment/armor/tier2/feet/plate_platinum"
	},
	"diamond": {
		"pants": "res://assets/equipment/armor/tier2/legs/crystal",
		"shirt": "res://assets/equipment/armor/tier2/chest/crystal",
		"boots": "res://assets/equipment/armor/tier2/feet/crystal"
	},
	"legendary": {
		"pants": "res://assets/equipment/armor/tier3/legs/infernal",
		"shirt": "res://assets/equipment/armor/tier3/chest/infernal",
		"boots": "res://assets/equipment/armor/tier3/feet/infernal"
	},
	"mythic": {
		"pants": "res://assets/equipment/armor/tier3/legs/ethereal",
		"shirt": "res://assets/equipment/armor/tier3/chest/ethereal",
		"boots": "res://assets/equipment/armor/tier3/feet/ethereal"
	}
}

# Current player cosmetics cache
var _player_cosmetics: Dictionary = {}
var _is_transforming: bool = false

func _ready() -> void:
	# Connect to MantleAuth profile updates
	if MantleAuth:
		MantleAuth.profile_updated.connect(_on_profile_updated)

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func calculate_cosmetics(profile: Dictionary) -> Dictionary:
	"""Calculate all cosmetics a player should have based on their Mantle profile"""
	var result = {
		"tier": "initiate",
		"armor_set": "",
		"effects": [],
		"title_prefix": "",
		"glow_color": Color.TRANSPARENT,
		"badge_color": Color.GRAY,
		"provider_badges": [],
		"achievement_unlocks": [],
		"milestone_title": "",
		"total_achievements": 0
	}

	# 1. Tier-based cosmetics
	var mantle = profile.get("mantle", {})
	var tier = mantle.get("tier", "initiate").to_lower()

	if TIER_COSMETICS.has(tier):
		var tier_data = TIER_COSMETICS[tier]
		result["tier"] = tier
		result["armor_set"] = tier_data.get("armor_set", "")
		result["effects"] = tier_data.get("effects", []).duplicate()
		result["title_prefix"] = tier_data.get("title_prefix", "")
		result["glow_color"] = tier_data.get("glow_color", Color.TRANSPARENT)
		result["badge_color"] = tier_data.get("badge_color", Color.GRAY)

	# 2. Provider cosmetics
	var providers = profile.get("providers", [])
	for provider in providers:
		var provider_name = provider.get("provider_name", "")
		if PROVIDER_COSMETICS.has(provider_name):
			result["provider_badges"].append(PROVIDER_COSMETICS[provider_name])

	# 3. Specific achievement cosmetics
	var achievements = profile.get("achievements", [])
	for achievement in achievements:
		var key = "%s_%s_%s" % [
			achievement.get("provider", ""),
			achievement.get("app_id", ""),
			achievement.get("api_name", "")
		]
		if ACHIEVEMENT_COSMETICS.has(key):
			result["achievement_unlocks"].append(ACHIEVEMENT_COSMETICS[key])

	# 4. Milestone cosmetics
	var count = profile.get("total_achievements", 0)
	result["total_achievements"] = count

	var highest_milestone = 0
	for threshold in MILESTONE_COSMETICS:
		if count >= threshold and threshold > highest_milestone:
			highest_milestone = threshold

	if highest_milestone > 0 and MILESTONE_COSMETICS.has(highest_milestone):
		var milestone_data = MILESTONE_COSMETICS[highest_milestone]
		result["milestone_title"] = milestone_data.get("title", "")
		# Merge milestone effects
		if milestone_data.has("aura"):
			result["effects"].append(milestone_data["aura"])
		if milestone_data.has("ground_effect"):
			result["effects"].append(milestone_data["ground_effect"])

	return result

func get_tier_badge_color(tier: String) -> Color:
	"""Get the badge color for a tier"""
	if TIER_COSMETICS.has(tier.to_lower()):
		return TIER_COSMETICS[tier.to_lower()].get("badge_color", Color.GRAY)
	return Color.GRAY

func get_tier_glow_color(tier: String) -> Color:
	"""Get the glow color for a tier"""
	if TIER_COSMETICS.has(tier.to_lower()):
		return TIER_COSMETICS[tier.to_lower()].get("glow_color", Color.TRANSPARENT)
	return Color.TRANSPARENT

func get_display_title(profile: Dictionary, base_name: String) -> String:
	"""Get the full display name with title prefix"""
	var cosmetics = calculate_cosmetics(profile)
	var prefix = cosmetics.get("title_prefix", "")
	return prefix + base_name

# ═══════════════════════════════════════════════════════════════════════════
# CHARACTER APPLICATION
# ═══════════════════════════════════════════════════════════════════════════

func apply_to_character(character: Node, cosmetics: Dictionary, instant: bool = false) -> void:
	"""Apply cosmetic layers to a character's LPC sprite system"""
	if not character:
		return

	var sprite = character.get_node_or_null("CharacterSprite")
	if not sprite:
		LogManager.warning("No CharacterSprite found on character", "mantle")
		return

	if instant:
		_apply_cosmetics_instant(character, sprite, cosmetics)
	else:
		_apply_cosmetics_animated(character, sprite, cosmetics)

func _apply_cosmetics_instant(character: Node, sprite: Node, cosmetics: Dictionary) -> void:
	"""Apply all cosmetics immediately (no animation)"""
	var tier = cosmetics.get("tier", "initiate")

	# Apply tier-based armor if paths exist
	if TIER_ARMOR_PATHS.has(tier):
		var armor_paths = TIER_ARMOR_PATHS[tier]
		# These would need to interface with SimpleLPCSprite
		# For now, store in character for later use
		if character.has_method("set_mantle_cosmetics"):
			character.set_mantle_cosmetics(cosmetics)

	# Apply glow effect
	var glow_color = cosmetics.get("glow_color", Color.TRANSPARENT)
	if glow_color.a > 0:
		_apply_glow_effect(character, glow_color)

	# Apply particle effects for high tiers
	var effects = cosmetics.get("effects", [])
	for effect in effects:
		_apply_particle_effect(character, effect)

	_player_cosmetics[character.get_instance_id()] = cosmetics
	cosmetics_calculated.emit(cosmetics)

func _apply_cosmetics_animated(character: Node, sprite: Node, cosmetics: Dictionary) -> void:
	"""Apply cosmetics with transformation sequence"""
	if _is_transforming:
		return

	_is_transforming = true
	transformation_started.emit(character)

	# Create transformation sequence
	var tween = character.create_tween()
	tween.set_parallel(false)

	# Phase 1: Gather particles
	tween.tween_callback(_start_gather_particles.bind(character))
	tween.tween_interval(0.5)

	# Phase 2: Flash
	tween.tween_callback(_flash_character.bind(character))
	tween.tween_interval(0.2)

	# Phase 3: Apply cosmetics
	tween.tween_callback(_apply_cosmetics_instant.bind(character, sprite, cosmetics))
	tween.tween_interval(0.3)

	# Phase 4: Burst effect
	tween.tween_callback(_burst_effect.bind(character, cosmetics))
	tween.tween_interval(0.5)

	# Phase 5: Complete
	tween.tween_callback(_complete_transformation.bind(character))

func _start_gather_particles(character: Node) -> void:
	"""Start swirling particle effect"""
	# TODO: Add particle gathering effect
	pass

func _flash_character(character: Node) -> void:
	"""Flash the character white"""
	var sprite = character.get_node_or_null("CharacterSprite")
	if sprite and sprite.material:
		# Would need shader for flash effect
		pass

func _burst_effect(character: Node, cosmetics: Dictionary) -> void:
	"""Burst particle effect based on tier"""
	var tier = cosmetics.get("tier", "initiate")
	var glow_color = cosmetics.get("glow_color", Color.WHITE)

	# TODO: Spawn burst particles colored by tier
	pass

func _complete_transformation(character: Node) -> void:
	"""Finish transformation sequence"""
	_is_transforming = false
	transformation_completed.emit(character)

# ═══════════════════════════════════════════════════════════════════════════
# VISUAL EFFECTS
# ═══════════════════════════════════════════════════════════════════════════

func _apply_glow_effect(character: Node, color: Color) -> void:
	"""Add glow/aura effect to character"""
	# Check if glow already exists
	var existing_glow = character.get_node_or_null("MantleGlow")
	if existing_glow:
		existing_glow.queue_free()

	if color.a <= 0:
		return

	# Create glow sprite
	var glow = Sprite2D.new()
	glow.name = "MantleGlow"
	glow.modulate = color
	glow.z_index = -1  # Behind character

	# Use a simple circle texture or create one
	var texture = _create_glow_texture(64)
	glow.texture = texture
	glow.position = Vector2(0, 0)

	character.add_child(glow)

func _create_glow_texture(size: int) -> ImageTexture:
	"""Create a radial gradient texture for glow effect"""
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var radius = size / 2.0

	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = clamp(1.0 - (dist / radius), 0.0, 1.0)
			alpha = alpha * alpha  # Quadratic falloff
			image.set_pixel(x, y, Color(1, 1, 1, alpha))

	return ImageTexture.create_from_image(image)

func _apply_particle_effect(character: Node, effect_name: String) -> void:
	"""Add particle effect to character"""
	# TODO: Load and apply particle effects based on effect_name
	match effect_name:
		"ember_particles":
			_add_ember_particles(character)
		"mythic_aura":
			_add_mythic_aura(character)
		"crystal_sparkle":
			_add_sparkle_particles(character)
		_:
			pass

func _add_ember_particles(character: Node) -> void:
	"""Add rising ember particles for Legendary tier"""
	var existing = character.get_node_or_null("EmberParticles")
	if existing:
		return

	var particles = GPUParticles2D.new()
	particles.name = "EmberParticles"
	particles.amount = 8
	particles.lifetime = 1.5
	particles.z_index = 10

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 16.0
	material.direction = Vector3(0, -1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.gravity = Vector3(0, -20, 0)
	material.scale_min = 0.5
	material.scale_max = 1.5
	material.color = Color(1.0, 0.4, 0.1, 0.8)

	particles.process_material = material
	particles.position = Vector2(0, 0)

	character.add_child(particles)

func _add_mythic_aura(character: Node) -> void:
	"""Add ethereal aura for Mythic tier"""
	var existing = character.get_node_or_null("MythicAura")
	if existing:
		return

	var particles = GPUParticles2D.new()
	particles.name = "MythicAura"
	particles.amount = 16
	particles.lifetime = 2.0
	particles.z_index = -1

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_radius = 24.0
	material.emission_ring_inner_radius = 20.0
	material.direction = Vector3(0, -1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, 0, 0)
	material.orbit_velocity_min = 0.5
	material.orbit_velocity_max = 1.0
	material.scale_min = 0.3
	material.scale_max = 0.8
	material.color = Color(0.8, 0.2, 1.0, 0.6)

	particles.process_material = material
	particles.position = Vector2(0, 0)

	character.add_child(particles)

func _add_sparkle_particles(character: Node) -> void:
	"""Add sparkle effect for Diamond tier"""
	var existing = character.get_node_or_null("SparkleParticles")
	if existing:
		return

	var particles = GPUParticles2D.new()
	particles.name = "SparkleParticles"
	particles.amount = 6
	particles.lifetime = 1.0
	particles.z_index = 10

	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(16, 24, 0)
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, 0, 0)
	material.scale_min = 0.2
	material.scale_max = 0.6
	material.color = Color(0.7, 0.95, 1.0, 0.9)

	particles.process_material = material
	particles.position = Vector2(0, -16)

	character.add_child(particles)

# ═══════════════════════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_profile_updated(profile: Dictionary) -> void:
	"""Handle profile update from MantleAuth"""
	var cosmetics = calculate_cosmetics(profile)
	LogManager.info("Calculated cosmetics for tier: %s" % cosmetics.get("tier", "unknown"), "mantle")
	cosmetics_calculated.emit(cosmetics)
