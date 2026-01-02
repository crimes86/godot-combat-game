extends Node
## ForgeVisualEffects - Visual effects for forged items based on generated modifiers
## Creates particle effects, glows, and trails for equipped forge items

# Effect definitions - maps effect names to their visual properties
const EFFECT_CONFIGS = {
	# === EFFORT TIER EFFECTS ===
	"exceptional_aura": {
		"type": "aura",
		"color": Color(1.0, 0.5, 0.0, 0.6),
		"intensity": 1.5,
		"pulse": true,
		"particle_count": 20
	},
	"superior_trail": {
		"type": "trail",
		"color": Color(0.7, 0.3, 0.9, 0.5),
		"intensity": 1.3,
		"length": 8
	},
	"enhanced_glow": {
		"type": "glow",
		"color": Color(0.2, 0.6, 1.0, 0.4),
		"intensity": 1.15,
		"radius": 12
	},
	"standard_particles": {
		"type": "particles",
		"color": Color(0.2, 0.8, 0.2, 0.3),
		"intensity": 1.0,
		"particle_count": 5
	},

	# === THE TAPESTRY - Provider Accent Effects ===
	# These create subtle rim glows based on source provider color
	"provider_rim_glow": {
		"type": "rim_glow",
		"color": Color(0.1, 0.5, 0.9, 0.4),  # Default blue, overridden by provider
		"intensity": 0.3,
		"radius": 16
	},

	# === HIDDEN/SECRET EFFECTS ===
	"secrets_keeper_aura": {
		"type": "aura",
		"color": Color(0.6, 0.3, 0.8, 0.5),
		"intensity": 1.1,
		"pulse": true,
		"particle_count": 10
	},

	# === VINTAGE EFFECTS ===
	"ancient_aura": {
		"type": "aura",
		"color": Color(0.8, 0.6, 0.2, 0.5),
		"intensity": 1.3,
		"pulse": false,
		"particle_count": 15
	},
	"vintage_glow": {
		"type": "glow",
		"color": Color(0.9, 0.7, 0.3, 0.4),
		"intensity": 1.2,
		"radius": 10
	},
	"aged_shimmer": {
		"type": "particles",
		"color": Color(0.8, 0.7, 0.4, 0.3),
		"intensity": 1.1,
		"particle_count": 8
	},

	# === PRESTIGE EFFECTS ===
	"prestige_glow": {
		"type": "glow",
		"color": Color(1.0, 0.8, 0.0, 0.6),
		"intensity": 1.5,
		"radius": 16,
		"pulse": true
	},

	# === GAME THEME EFFECTS ===
	# FromSoftware
	"erdtree_blessing": {
		"type": "particles",
		"color": Color(1.0, 0.85, 0.0, 0.6),
		"secondary_color": Color(0.4, 0.8, 0.2, 0.4),
		"intensity": 1.3,
		"particle_count": 12,
		"particle_texture": "leaf"
	},
	"ember_trail": {
		"type": "trail",
		"color": Color(1.0, 0.4, 0.0, 0.7),
		"secondary_color": Color(1.0, 0.2, 0.0, 0.5),
		"intensity": 1.4,
		"length": 10,
		"particle_texture": "ember"
	},
	"crimson_slash": {
		"type": "slash",
		"color": Color(0.9, 0.1, 0.1, 0.8),
		"intensity": 1.5,
		"length": 6
	},

	# Hollow Knight
	"void_particles": {
		"type": "particles",
		"color": Color(0.1, 0.0, 0.2, 0.8),
		"secondary_color": Color(0.3, 0.1, 0.5, 0.6),
		"intensity": 1.2,
		"particle_count": 15,
		"gravity": -20  # Float upward
	},
	"void_trail": {
		"type": "trail",
		"color": Color(0.2, 0.0, 0.3, 0.6),
		"intensity": 1.3,
		"length": 12
	},
	"void_aura": {
		"type": "aura",
		"color": Color(0.15, 0.0, 0.25, 0.5),
		"intensity": 1.4,
		"pulse": true,
		"particle_count": 10
	},
	"shadow_tendrils": {
		"type": "tendrils",
		"color": Color(0.1, 0.0, 0.15, 0.7),
		"intensity": 1.2,
		"count": 4
	},
	"dark_burst": {
		"type": "burst",
		"color": Color(0.2, 0.0, 0.3, 0.8),
		"intensity": 1.5,
		"trigger": "on_attack"
	},
	"shadow_dash": {
		"type": "blur",
		"color": Color(0.1, 0.0, 0.2, 0.4),
		"intensity": 1.3,
		"trigger": "on_move"
	},

	# Hades
	"underworld_flame": {
		"type": "particles",
		"color": Color(1.0, 0.3, 0.0, 0.7),
		"secondary_color": Color(0.8, 0.1, 0.0, 0.5),
		"intensity": 1.3,
		"particle_count": 10,
		"gravity": -30
	},
	"blood_red_glow": {
		"type": "glow",
		"color": Color(0.8, 0.1, 0.1, 0.5),
		"intensity": 1.2,
		"radius": 14
	},
	"infernal_glow": {
		"type": "glow",
		"color": Color(1.0, 0.4, 0.0, 0.5),
		"intensity": 1.25,
		"radius": 12
	},
	"divine_glow": {
		"type": "glow",
		"color": Color(1.0, 0.9, 0.4, 0.6),
		"intensity": 1.4,
		"radius": 16
	},
	"laurel_particles": {
		"type": "particles",
		"color": Color(0.3, 0.7, 0.2, 0.5),
		"intensity": 1.1,
		"particle_count": 6,
		"particle_texture": "leaf"
	},

	# Stardew Valley
	"nature_sparkle": {
		"type": "particles",
		"color": Color(0.2, 0.9, 0.3, 0.5),
		"secondary_color": Color(1.0, 1.0, 0.5, 0.4),
		"intensity": 1.0,
		"particle_count": 8
	},
	"golden_sparkle": {
		"type": "particles",
		"color": Color(1.0, 0.85, 0.0, 0.6),
		"intensity": 1.1,
		"particle_count": 10
	},
	"stone_glow": {
		"type": "glow",
		"color": Color(0.5, 0.5, 0.5, 0.4),  # Grey stone glow
		"secondary_color": Color(0.6, 0.55, 0.5, 0.3),  # Slight warm tint
		"intensity": 0.8,
		"pulse": false
	},
	"stardust_trail": {
		"type": "trail",
		"color": Color(0.8, 0.6, 1.0, 0.5),
		"secondary_color": Color(1.0, 0.8, 0.4, 0.4),
		"intensity": 1.2,
		"length": 8
	},
	"healing_aura": {
		"type": "aura",
		"color": Color(0.3, 0.9, 0.4, 0.4),
		"intensity": 1.0,
		"pulse": true,
		"particle_count": 6
	},
	"pixel_sparkle": {
		"type": "particles",
		"color": Color(1.0, 1.0, 1.0, 0.7),
		"intensity": 1.2,
		"particle_count": 8,
		"pixel_style": true
	},
	"retro_trail": {
		"type": "trail",
		"color": Color(0.5, 0.8, 1.0, 0.4),
		"intensity": 1.0,
		"length": 6,
		"pixel_style": true
	},

	# Terraria
	"terra_beam": {
		"type": "projectile",
		"color": Color(0.0, 1.0, 0.5, 0.8),
		"intensity": 1.4,
		"trigger": "on_attack"
	},
	"green_glow": {
		"type": "glow",
		"color": Color(0.2, 0.9, 0.3, 0.5),
		"intensity": 1.2,
		"radius": 14
	},
	"sword_projectile": {
		"type": "projectile",
		"color": Color(0.3, 1.0, 0.5, 0.7),
		"intensity": 1.3,
		"trigger": "on_attack"
	},
	"eerie_glow": {
		"type": "glow",
		"color": Color(0.7, 0.2, 0.3, 0.5),
		"intensity": 1.1,
		"radius": 10,
		"pulse": true
	},

	# Dark Souls
	"ember_glow": {
		"type": "glow",
		"color": Color(1.0, 0.5, 0.0, 0.5),
		"intensity": 1.2,
		"radius": 12,
		"pulse": true
	},
	"wolf_blood_aura": {
		"type": "aura",
		"color": Color(0.4, 0.5, 0.7, 0.4),
		"intensity": 1.1,
		"pulse": false,
		"particle_count": 8
	},
	"lightning_crackle": {
		"type": "particles",
		"color": Color(1.0, 1.0, 0.5, 0.8),
		"secondary_color": Color(0.8, 0.9, 1.0, 0.6),
		"intensity": 1.4,
		"particle_count": 6,
		"particle_texture": "lightning"
	},
	"storm_particles": {
		"type": "particles",
		"color": Color(0.7, 0.8, 0.9, 0.5),
		"intensity": 1.2,
		"particle_count": 12,
		"gravity": 10  # Wind effect
	},
	"flame_idle_glow": {
		"type": "glow",
		"color": Color(1.0, 0.4, 0.1, 0.6),
		"intensity": 1.3,
		"radius": 14,
		"pulse": true
	},
	"heat_distortion": {
		"type": "shader",
		"effect": "distortion",
		"intensity": 0.3
	},

	# Witcher
	"silver_gleam": {
		"type": "glow",
		"color": Color(0.85, 0.9, 1.0, 0.5),
		"intensity": 1.1,
		"radius": 8
	},
	"wolf_school_glow": {
		"type": "glow",
		"color": Color(0.9, 0.7, 0.2, 0.5),
		"intensity": 1.2,
		"radius": 10
	},
	"danger_sense": {
		"type": "pulse",
		"color": Color(1.0, 0.3, 0.3, 0.4),
		"intensity": 1.0,
		"trigger": "on_enemy_near"
	},

	# Sekiro
	"death_kanji": {
		"type": "overlay",
		"texture": "kanji_death",
		"color": Color(0.8, 0.0, 0.0, 0.8),
		"trigger": "on_kill"
	},
	"blood_mist": {
		"type": "particles",
		"color": Color(0.7, 0.0, 0.0, 0.5),
		"intensity": 1.2,
		"particle_count": 15,
		"trigger": "on_attack"
	},
	# Bloodborne hunter's weapon - dripping blood particles
	"blood_particles": {
		"type": "particles",
		"color": Color(0.55, 0.0, 0.0, 0.7),  # Dark blood red (#8B0000)
		"secondary_color": Color(0.3, 0.0, 0.0, 0.5),
		"intensity": 1.3,
		"particle_count": 10,
		"gravity": 50  # Dripping downward
	},
	# Dead Cells - floating green cell particles
	"cell_particles": {
		"type": "particles",
		"color": Color(0.0, 1.0, 0.0, 0.7),  # Bright green (#00FF00)
		"secondary_color": Color(0.2, 0.8, 0.2, 0.5),
		"intensity": 1.4,
		"particle_count": 12,
		"gravity": -20  # Float upward like cells
	},

	# Discord/Social
	"discord_sparkle": {
		"type": "particles",
		"color": Color(0.35, 0.4, 0.95, 0.6),
		"intensity": 1.0,
		"particle_count": 6
	},

	# Generic Effects
	"moonlight_aura": {
		"type": "aura",
		"color": Color(0.6, 0.7, 1.0, 0.4),
		"intensity": 1.2,
		"pulse": true,
		"particle_count": 8
	},
	"gravity_particles": {
		"type": "particles",
		"color": Color(0.5, 0.3, 0.8, 0.6),
		"intensity": 1.3,
		"particle_count": 10,
		"gravity": 0  # Float in place
	},
	"purple_glow": {
		"type": "glow",
		"color": Color(0.6, 0.2, 0.8, 0.5),
		"intensity": 1.2,
		"radius": 12
	},
	"scarlet_rot_trail": {
		"type": "trail",
		"color": Color(0.8, 0.2, 0.2, 0.5),
		"secondary_color": Color(0.6, 0.1, 0.1, 0.3),
		"intensity": 1.3,
		"length": 10
	},
	"flower_petals": {
		"type": "particles",
		"color": Color(1.0, 0.6, 0.7, 0.6),
		"intensity": 1.1,
		"particle_count": 8,
		"particle_texture": "petal",
		"gravity": 15
	},
	"golden_leaves": {
		"type": "particles",
		"color": Color(1.0, 0.85, 0.0, 0.5),
		"secondary_color": Color(0.8, 0.6, 0.0, 0.4),
		"intensity": 1.2,
		"particle_count": 6,
		"particle_texture": "leaf",
		"gravity": 20
	},
	"light_rays": {
		"type": "rays",
		"color": Color(1.0, 0.95, 0.7, 0.4),
		"intensity": 1.3,
		"count": 5
	},
	"arcane_burst": {
		"type": "burst",
		"color": Color(0.0, 0.7, 1.0, 0.7),
		"intensity": 1.4,
		"trigger": "on_ability"
	},
	"tactical_glow": {
		"type": "glow",
		"color": Color(1.0, 0.6, 0.0, 0.4),
		"intensity": 1.0,
		"radius": 8
	},

	# === ACHIEVEMENT EFFECTS (Unlocked by per-weapon achievements) ===

	# Blood drip for FIRST_BLOOD achievement
	"blood_drip": {
		"type": "particles",
		"color": Color(0.5, 0.0, 0.0, 0.8),
		"intensity": 0.8,
		"particle_count": 2,
		"gravity": 30
	},

	# Centurion flash for 100 kills
	"centurion_flash": {
		"type": "glow",
		"color": Color(0.8, 0.6, 0.0, 0.6),
		"intensity": 1.2,
		"radius": 10,
		"pulse": true
	},

	# Tiny skull orbit for SLAYER achievement (1000 kills)
	"skull_orbit": {
		"type": "particles",
		"color": Color(0.9, 0.9, 0.9, 0.7),
		"intensity": 1.0,
		"particle_count": 3,
		"gravity": 0
	},

	# Crown/halo for LEGEND achievement (10000 kills)
	"legend_crown": {
		"type": "glow",
		"color": Color(1.0, 0.85, 0.0, 0.7),
		"intensity": 1.5,
		"radius": 20,
		"pulse": true
	},

	# Pristine sparkle for PERFECTIONIST (100 kills, 0 deaths)
	"pristine_sparkle": {
		"type": "particles",
		"color": Color(1.0, 1.0, 1.0, 0.8),
		"secondary_color": Color(0.9, 0.95, 1.0, 0.6),
		"intensity": 1.3,
		"particle_count": 6,
		"gravity": -5
	},

	# Lightning crackle for CRIT_MASTER (50% crit rate)
	"crit_lightning": {
		"type": "particles",
		"color": Color(1.0, 1.0, 0.5, 0.9),
		"secondary_color": Color(0.8, 0.9, 1.0, 0.7),
		"intensity": 1.4,
		"particle_count": 4,
		"particle_texture": "lightning"
	},

	# Chain links for CHAIN_KING achievement
	"chain_orbit": {
		"type": "particles",
		"color": Color(0.7, 0.7, 0.8, 0.6),
		"intensity": 1.0,
		"particle_count": 5,
		"gravity": 0
	},

	# Explosion particles for OVERKILL achievement
	"overkill_explosion": {
		"type": "burst",
		"color": Color(1.0, 0.5, 0.0, 0.8),
		"secondary_color": Color(1.0, 0.2, 0.0, 0.6),
		"intensity": 1.5,
		"trigger": "on_kill"
	},

	# Time-worn patina for VETERAN (100+ hours equipped)
	"veteran_patina": {
		"type": "glow",
		"color": Color(0.6, 0.5, 0.4, 0.3),
		"intensity": 0.8,
		"radius": 6
	},

	# === LEGENDARY/MYTHIC TIER EFFECTS ===

	# Floating ember particles for Mythic dark souls weapons
	"floating_embers": {
		"type": "particles",
		"color": Color(1.0, 0.5, 0.1, 0.7),
		"secondary_color": Color(1.0, 0.3, 0.0, 0.5),
		"intensity": 1.3,
		"particle_count": 15,
		"gravity": -15
	},

	# Reaching void tendrils for Legendary Hollow Knight weapons
	"reaching_tendrils": {
		"type": "particles",
		"color": Color(0.1, 0.0, 0.2, 0.8),
		"secondary_color": Color(0.2, 0.0, 0.3, 0.6),
		"intensity": 1.4,
		"particle_count": 8,
		"gravity": -5
	},

	# Divine golden overlay for Legendary Hades weapons
	"divine_overlay": {
		"type": "glow",
		"color": Color(1.0, 0.9, 0.4, 0.5),
		"secondary_color": Color(1.0, 0.7, 0.0, 0.3),
		"intensity": 1.4,
		"radius": 18,
		"pulse": true
	},
}

# Active effects on entities
var _active_effects: Dictionary = {}  # entity_id -> [effect_nodes]

var _is_server_mode: bool = false

func _ready() -> void:
	# Check if running on dedicated server
	_is_server_mode = "--server" in OS.get_cmdline_user_args()
	# Effects are now pre-computed by backend - no runtime generation needed
	pass

# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func apply_effects_to_entity(entity: Node2D, effects: Array, modifiers: Dictionary = {}) -> void:
	"""Apply visual effects to an entity (player, weapon, etc.)

	Modifiers:
	- effect_intensity: Multiplier for glow/effect intensity (default 1.0)
	- particle_multiplier: Multiplier for particle counts (default 1.0)
	- theme_color: Override color for effects (optional)

	DEDICATED SERVER: Skip all visual effects
	"""
	if _is_server_mode:
		return

	var entity_id = entity.get_instance_id()

	# Clear existing effects
	clear_effects_from_entity(entity)

	var effect_nodes = []
	var intensity_multiplier = modifiers.get("effect_intensity", 1.0)
	var particle_multiplier = modifiers.get("particle_multiplier", 1.0)

	for effect_name in effects:
		if effect_name in EFFECT_CONFIGS:
			var config = EFFECT_CONFIGS[effect_name].duplicate()
			config["intensity"] = config.get("intensity", 1.0) * intensity_multiplier

			# Apply particle multiplier for particle-based effects
			if config.has("particle_count"):
				config["particle_count"] = int(config["particle_count"] * particle_multiplier)
				# Ensure at least 1 particle if multiplier is > 0
				if particle_multiplier > 0 and config["particle_count"] < 1:
					config["particle_count"] = 1

			# Apply theme color override if provided (but not for provider rim glow)
			if modifiers.has("theme_color") and effect_name != "provider_rim_glow":
				config["color"] = modifiers.theme_color

			# The Tapestry: Use provider accent color for rim glow effect
			if effect_name == "provider_rim_glow" and modifiers.has("provider_accent_color"):
				config["color"] = modifiers.provider_accent_color

			var effect_node = _create_effect_node(effect_name, config)
			if effect_node:
				entity.add_child(effect_node)
				effect_nodes.append(effect_node)

	_active_effects[entity_id] = effect_nodes

func clear_effects_from_entity(entity: Node2D) -> void:
	"""Remove all visual effects from an entity"""
	var entity_id = entity.get_instance_id()

	if entity_id in _active_effects:
		for effect_node in _active_effects[entity_id]:
			if is_instance_valid(effect_node):
				effect_node.queue_free()
		_active_effects.erase(entity_id)

func get_effect_config(effect_name: String) -> Dictionary:
	"""Get the configuration for a specific effect"""
	return EFFECT_CONFIGS.get(effect_name, {})

func has_effect(effect_name: String) -> bool:
	"""Check if an effect is defined"""
	return effect_name in EFFECT_CONFIGS

# ═══════════════════════════════════════════════════════════════════════════════
# EFFECT CREATION
# ═══════════════════════════════════════════════════════════════════════════════

func _create_effect_node(effect_name: String, config: Dictionary) -> Node2D:
	"""Create a visual effect node based on configuration"""
	var effect_type = config.get("type", "")

	match effect_type:
		"glow":
			return _create_glow_effect(effect_name, config)
		"particles":
			return _create_particle_effect(effect_name, config)
		"trail":
			return _create_trail_effect(effect_name, config)
		"aura":
			return _create_aura_effect(effect_name, config)
		"rim_glow":
			return _create_rim_glow_effect(effect_name, config)
		_:
			# Fallback to simple glow for unsupported types
			return _create_glow_effect(effect_name, config)

func _create_glow_effect(effect_name: String, config: Dictionary) -> Node2D:
	"""Create a simple glow effect - tuned for weapon-sized effects"""
	var container = Node2D.new()
	container.name = "ForgeEffect_" + effect_name

	var color: Color = config.get("color", Color.WHITE)
	var intensity: float = config.get("intensity", 1.0)
	var radius: float = config.get("radius", 12.0) * 0.6  # Scale down for weapon size
	var pulse: bool = config.get("pulse", false)

	# Create a simple colored sprite for glow effect
	var glow = Sprite2D.new()
	glow.name = "GlowSprite"
	glow.modulate = Color(color.r, color.g, color.b, color.a * 0.5)
	glow.scale = Vector2(radius / 8.0, radius / 8.0) * intensity

	# Use a simple white circle texture (or create procedurally)
	var texture = _get_or_create_glow_texture()
	glow.texture = texture
	container.add_child(glow)

	# Add pulse animation if enabled
	if pulse:
		var tween = container.create_tween()
		tween.set_loops()
		tween.tween_property(glow, "modulate:a", color.a * 0.3, 1.0).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(glow, "modulate:a", color.a * 0.7, 1.0).set_ease(Tween.EASE_IN_OUT)

	return container


func _create_rim_glow_effect(effect_name: String, config: Dictionary) -> Node2D:
	"""
	Create a rim glow effect for provider accent colors (The Tapestry system).

	This creates an outer glow ring that appears behind the primary glow,
	giving forged items a subtle colored accent based on their source provider.

	Config expects:
	- color: The provider accent color
	- intensity: Effect strength (0.0-1.0)
	"""
	var container = Node2D.new()
	container.name = "ForgeEffect_" + effect_name

	var color: Color = config.get("color", Color.WHITE)
	var intensity: float = config.get("intensity", 0.3)  # Subtle by default
	var radius: float = config.get("radius", 16.0) * 0.6  # Slightly larger than primary

	# Create the rim glow sprite (appears behind primary glow)
	var rim = Sprite2D.new()
	rim.name = "RimGlowSprite"
	rim.modulate = Color(color.r, color.g, color.b, intensity * 0.4)
	rim.scale = Vector2(radius / 6.0, radius / 6.0)  # 1.4x larger than normal glow
	rim.z_index = -1  # Render behind primary effects

	var texture = _get_or_create_glow_texture()
	rim.texture = texture
	container.add_child(rim)

	# Subtle pulse for the rim
	var tween = container.create_tween()
	tween.set_loops()
	tween.tween_property(rim, "modulate:a", intensity * 0.2, 2.0).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(rim, "modulate:a", intensity * 0.5, 2.0).set_ease(Tween.EASE_IN_OUT)

	return container


func _create_particle_effect(effect_name: String, config: Dictionary) -> Node2D:
	"""Create a GPUParticles2D effect - tuned for weapon-sized spawning"""
	var particles = GPUParticles2D.new()
	particles.name = "ForgeEffect_" + effect_name

	var color: Color = config.get("color", Color.WHITE)
	var intensity: float = config.get("intensity", 1.0)
	var count: int = int(config.get("particle_count", 10) * intensity)
	var gravity: float = config.get("gravity", 0.0)

	particles.amount = count
	particles.lifetime = 1.2  # Slightly shorter for weapon effects
	particles.speed_scale = 1.0
	particles.explosiveness = 0.0
	particles.randomness = 0.5

	# Create process material - tuned for weapon sprite size
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 4.0  # Smaller radius for weapon-sized effects
	material.direction = Vector3(0, -1, 0)
	material.spread = 30.0  # Tighter spread around weapon
	material.initial_velocity_min = 5.0  # Slower particles stay closer to weapon
	material.initial_velocity_max = 12.0
	material.gravity = Vector3(0, gravity, 0)
	material.scale_min = 0.3 * intensity  # Smaller particles
	material.scale_max = 1.0 * intensity
	material.color = color

	# Add secondary color gradient if available
	if config.has("secondary_color"):
		var gradient = Gradient.new()
		gradient.add_point(0.0, color)
		gradient.add_point(1.0, config.secondary_color)
		var gradient_tex = GradientTexture1D.new()
		gradient_tex.gradient = gradient
		material.color_ramp = gradient_tex

	particles.process_material = material

	return particles

func _create_trail_effect(effect_name: String, config: Dictionary) -> Node2D:
	"""Create a trail effect using Line2D"""
	var container = Node2D.new()
	container.name = "ForgeEffect_" + effect_name

	var color: Color = config.get("color", Color.WHITE)
	var intensity: float = config.get("intensity", 1.0)
	var length: int = int(config.get("length", 8) * intensity)

	var trail = Line2D.new()
	trail.name = "Trail"
	trail.width = 4.0 * intensity
	trail.default_color = color
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND

	# Gradient for fade-out
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(color.r, color.g, color.b, color.a))
	gradient.add_point(1.0, Color(color.r, color.g, color.b, 0.0))
	trail.gradient = gradient

	# Initialize with empty points
	for i in range(length):
		trail.add_point(Vector2.ZERO)

	container.add_child(trail)
	container.set_meta("trail_length", length)
	container.set_meta("trail_line", trail)

	return container

func _create_aura_effect(effect_name: String, config: Dictionary) -> Node2D:
	"""Create an aura effect (glow + particles combined)"""
	var container = Node2D.new()
	container.name = "ForgeEffect_" + effect_name

	# Add glow component
	var glow_config = config.duplicate()
	glow_config["radius"] = config.get("radius", 16.0)
	var glow = _create_glow_effect(effect_name + "_glow", glow_config)
	container.add_child(glow)

	# Add particle component
	var particle_config = config.duplicate()
	particle_config["particle_count"] = config.get("particle_count", 8)
	particle_config["gravity"] = -10  # Float upward for aura
	var particles = _create_particle_effect(effect_name + "_particles", particle_config)
	container.add_child(particles)

	return container

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

var _glow_texture: Texture2D = null

func _get_or_create_glow_texture() -> Texture2D:
	"""Get or create a simple radial gradient texture for glow effects"""
	if _glow_texture:
		return _glow_texture

	# Create a simple gradient texture
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center = Vector2(16, 16)

	for x in range(32):
		for y in range(32):
			var dist = Vector2(x, y).distance_to(center)
			var alpha = clampf(1.0 - (dist / 16.0), 0.0, 1.0)
			alpha = alpha * alpha  # Quadratic falloff
			image.set_pixel(x, y, Color(1, 1, 1, alpha))

	_glow_texture = ImageTexture.create_from_image(image)
	return _glow_texture

func update_trail(trail_container: Node2D, position: Vector2) -> void:
	"""Update a trail effect with new position (call from _process)"""
	if not trail_container.has_meta("trail_line"):
		return

	var trail: Line2D = trail_container.get_meta("trail_line")
	var length: int = trail_container.get_meta("trail_length", 8)

	# Shift points and add new position
	for i in range(length - 1, 0, -1):
		trail.set_point_position(i, trail.get_point_position(i - 1))
	trail.set_point_position(0, trail_container.to_local(position))
