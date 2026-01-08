#!/usr/bin/env python3
"""Add Wave 2-3 items to items.json"""

import json
import os

ITEMS_PATH = os.path.join(os.path.dirname(__file__), '..', 'backend', 'data', 'items.json')

# Wave 2: Arms (8)
WAVE2_ARMS = [
    {
        "item_id": "abyss_watcher_vambraces",
        "item_name": "Abyss Watcher Vambraces",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Arm guards of the wolf blood legion.",
        "lore": "The wolf blood burns within.",
        "base_rarity": "epic",
        "theme": "dark_souls",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/abyss_watcher_vambraces.png",
            "sprite_folder": "armor/arms/abyss_watcher",
            "effect": "wolf_blood_aura",
            "glow_color": "#4A6B8A"
        },
        "effects": {"passive": ["damage_reduction"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 12,
        "stat_bonuses": {"str": 3, "agi": 0, "dex": 3, "int": 0, "wis": 0, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/armor/abyss_watcher_vambraces.png"}
    },
    {
        "item_id": "grass_crest_vambraces",
        "item_name": "Grass Crest Vambraces",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Arm guards blessed with stamina recovery.",
        "lore": "Praise the grass!",
        "base_rarity": "rare",
        "theme": "dark_souls",
        "material_type": "leather",
        "visuals": {
            "icon_url": "/static/items/icons/grass_crest_vambraces.png",
            "sprite_folder": "armor/arms/grass_crest",
            "effect": "stamina_aura",
            "glow_color": "#228B22"
        },
        "effects": {"passive": ["stamina_regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 10,
        "stat_bonuses": {"str": 0, "agi": 3, "dex": 0, "int": 0, "wis": 0, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/armor/grass_crest_vambraces.png"}
    },
    {
        "item_id": "hunter_forearm_guards",
        "item_name": "Hunter's Forearm Guards",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Leather guards stained with old blood.",
        "lore": "Fear the old blood.",
        "base_rarity": "epic",
        "theme": "bloodborne",
        "material_type": "leather",
        "visuals": {
            "icon_url": "/static/items/icons/hunter_forearm_guards.png",
            "sprite_folder": "armor/arms/hunter",
            "effect": "blood_splatter",
            "glow_color": "#8B0000"
        },
        "effects": {"passive": ["lifesteal"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 11,
        "stat_bonuses": {"str": 2, "agi": 3, "dex": 2, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/armor/hunter_forearm_guards.png"}
    },
    {
        "item_id": "leviathan_vambraces",
        "item_name": "Leviathan Vambraces",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Frost-touched arm guards.",
        "lore": "The axe remembers.",
        "base_rarity": "epic",
        "theme": "god_of_war",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/leviathan_vambraces.png",
            "sprite_folder": "armor/arms/leviathan",
            "effect": "frost_particles",
            "glow_color": "#87CEEB"
        },
        "effects": {"passive": ["damage_reduction", "boss_damage"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 14,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/armor/leviathan_vambraces.png"}
    },
    {
        "item_id": "atropos_bracers",
        "item_name": "Atropos Bracers",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Alien-touched arm guards.",
        "lore": "The cycle continues.",
        "base_rarity": "rare",
        "theme": "returnal",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/atropos_bracers.png",
            "sprite_folder": "armor/arms/atropos",
            "effect": "adrenaline_pulse",
            "glow_color": "#00CED1"
        },
        "effects": {"passive": ["regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 10,
        "stat_bonuses": {"str": 0, "agi": 2, "dex": 2, "int": 0, "wis": 0, "vit": 3},
        "sprites": {"icon": "res://assets/icons/forged/armor/atropos_bracers.png"}
    },
    {
        "item_id": "mjolnir_bracers",
        "item_name": "MJOLNIR Bracers",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Spartan forearm armor.",
        "lore": "Spartans never die.",
        "base_rarity": "legendary",
        "theme": "halo",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/mjolnir_bracers.png",
            "sprite_folder": "armor/arms/mjolnir",
            "effect": "shield_recharge",
            "glow_color": "#00FF00"
        },
        "effects": {"passive": ["damage_reduction", "poise"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 15,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/armor/mjolnir_bracers.png"}
    },
    {
        "item_id": "pilot_bracers",
        "item_name": "Pilot's Bracers",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Reinforced jump kit arm mounts.",
        "lore": "Protocol 3: Protect the Pilot.",
        "base_rarity": "rare",
        "theme": "titanfall",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/pilot_bracers.png",
            "sprite_folder": "armor/arms/pilot",
            "effect": "pilot_boost",
            "glow_color": "#FF6600"
        },
        "effects": {"passive": ["move_speed"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 9,
        "stat_bonuses": {"str": 0, "agi": 4, "dex": 2, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/armor/pilot_bracers.png"}
    },
    {
        "item_id": "crusader_bracers",
        "item_name": "Crusader Bracers",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Holy warrior arm guards.",
        "lore": "Akarat's Champion.",
        "base_rarity": "epic",
        "theme": "diablo",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/crusader_bracers.png",
            "sprite_folder": "armor/arms/crusader",
            "effect": "holy_light",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["damage_reduction"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 13,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/armor/crusader_bracers.png"}
    },
    {
        "item_id": "immortal_bracers",
        "item_name": "Immortal Bracers",
        "item_type": "armor_arms",
        "weapon_type": None,
        "description": "Bracers from the Immortal raid.",
        "lore": "A tribute to perfection.",
        "base_rarity": "legendary",
        "theme": "wow",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/immortal_bracers.png",
            "sprite_folder": "armor/arms/immortal",
            "effect": "golden_glow",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["death_prevention"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 14,
        "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 3, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/armor/immortal_bracers.png"}
    }
]

# Wave 2: Hands (7)
WAVE2_HANDS = [
    {
        "item_id": "blacksmith_gloves",
        "item_name": "Blacksmith's Gloves",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Sturdy gloves worn at the forge.",
        "lore": "Every item shipped, every tool crafted.",
        "base_rarity": "rare",
        "theme": "stardew",
        "material_type": "leather",
        "visuals": {
            "icon_url": "/static/items/icons/blacksmith_gloves.png",
            "sprite_folder": "armor/hands/blacksmith",
            "effect": "forge_sparks",
            "glow_color": "#8B4513"
        },
        "effects": {"passive": ["regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 8,
        "stat_bonuses": {"str": 2, "agi": 0, "dex": 3, "int": 0, "wis": 0, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/armor/blacksmith_gloves.png"}
    },
    {
        "item_id": "marksman_gloves",
        "item_name": "Marksman's Gloves",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Precision shooting gloves.",
        "lore": "A thousand headshots, one pair of gloves.",
        "base_rarity": "epic",
        "theme": "counter_strike",
        "material_type": "leather",
        "visuals": {
            "icon_url": "/static/items/icons/marksman_gloves.png",
            "sprite_folder": "armor/hands/marksman",
            "effect": "precision_glow",
            "glow_color": "#FF4500"
        },
        "effects": {"passive": ["crit_chance"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 6,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 6, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/armor/marksman_gloves.png"}
    },
    {
        "item_id": "thief_gloves",
        "item_name": "Thief's Handwraps",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Wraps that silence your touch.",
        "lore": "Light fingers, heavy pockets.",
        "base_rarity": "rare",
        "theme": "skyrim",
        "material_type": "cloth",
        "visuals": {
            "icon_url": "/static/items/icons/thief_gloves.png",
            "sprite_folder": "armor/hands/thief",
            "effect": "shadow_touch",
            "glow_color": "#2F4F4F"
        },
        "effects": {"passive": ["crit_chance"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 5,
        "stat_bonuses": {"str": 0, "agi": 4, "dex": 3, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/armor/thief_gloves.png"}
    },
    {
        "item_id": "samurai_kote",
        "item_name": "Samurai Kote",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Armored gloves of the Ghost.",
        "lore": "The way of the Ghost.",
        "base_rarity": "epic",
        "theme": "ghost_of_tsushima",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/samurai_kote.png",
            "sprite_folder": "armor/hands/samurai",
            "effect": "ghost_stance",
            "glow_color": "#1A1A2E"
        },
        "effects": {"passive": ["crit_chance", "armor_pierce"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 9,
        "stat_bonuses": {"str": 0, "agi": 3, "dex": 4, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/armor/samurai_kote.png"}
    },
    {
        "item_id": "cog_gauntlets",
        "item_name": "COG Gauntlets",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Heavy armored gloves for chainsaw grip.",
        "lore": "Rev it up.",
        "base_rarity": "epic",
        "theme": "gears",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/cog_gauntlets.png",
            "sprite_folder": "armor/hands/cog",
            "effect": "chainsaw_rev",
            "glow_color": "#990000"
        },
        "effects": {"passive": ["lifesteal"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 10,
        "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/armor/cog_gauntlets.png"}
    },
    {
        "item_id": "netherite_gauntlets",
        "item_name": "Netherite Gauntlets",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Gloves forged in the Nether.",
        "lore": "Ancient debris reforged.",
        "base_rarity": "rare",
        "theme": "minecraft",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/netherite_gauntlets.png",
            "sprite_folder": "armor/hands/netherite",
            "effect": "block_particles",
            "glow_color": "#4A4A4A"
        },
        "effects": {"passive": ["damage_reduction"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 11,
        "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/armor/netherite_gauntlets.png"}
    },
    {
        "item_id": "medic_gloves",
        "item_name": "Medic's Gloves",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Field medic surgical gloves.",
        "lore": "Heal your allies, harm your enemies.",
        "base_rarity": "rare",
        "theme": "starcraft",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/medic_gloves.png",
            "sprite_folder": "armor/hands/medic",
            "effect": "heal_aura",
            "glow_color": "#00FF00"
        },
        "effects": {"passive": ["regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 7,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 2, "int": 0, "wis": 4, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/armor/medic_gloves.png"}
    }
]

# Wave 2: Shields (6)
WAVE2_SHIELDS = [
    {
        "item_id": "aegis_of_champions",
        "item_name": "Aegis of Champions",
        "item_type": "shield",
        "weapon_type": None,
        "description": "The shield of esports legends.",
        "lore": "The International awaits.",
        "base_rarity": "legendary",
        "theme": "dota",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/aegis_champion.png",
            "sprite_folder": "shields/aegis/standard",
            "effect": "aegis_glow",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["death_prevention"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 25,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 6},
        "sprites": {"icon": "res://assets/icons/forged/shields/aegis_champion.png"}
    },
    {
        "item_id": "guardian_shield",
        "item_name": "Guardian Shield",
        "item_type": "shield",
        "weapon_type": None,
        "description": "A shield forged from machine parts.",
        "lore": "Override protocol engaged.",
        "base_rarity": "epic",
        "theme": "horizon",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/guardian_shield.png",
            "sprite_folder": "shields/guardian/standard",
            "effect": "machine_glow",
            "glow_color": "#4169E1"
        },
        "effects": {"passive": ["damage_reduction"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 22,
        "stat_bonuses": {"str": 3, "agi": 0, "dex": 0, "int": 0, "wis": 2, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/shields/guardian_shield.png"}
    },
    {
        "item_id": "captain_buckler",
        "item_name": "Captain's Buckler",
        "item_type": "shield",
        "weapon_type": None,
        "description": "A small shield for swift pirates.",
        "lore": "Every captain needs a backup plan.",
        "base_rarity": "rare",
        "theme": "sea_of_thieves",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/captain_buckler.png",
            "sprite_folder": "shields/captain/standard",
            "effect": "ocean_particles",
            "glow_color": "#1E90FF"
        },
        "effects": {"passive": ["stamina_regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 16,
        "stat_bonuses": {"str": 2, "agi": 2, "dex": 2, "int": 0, "wis": 0, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/shields/captain_buckler.png"}
    },
    {
        "item_id": "paladin_bulwark",
        "item_name": "Paladin's Bulwark",
        "item_type": "shield",
        "weapon_type": None,
        "description": "A holy shield blessed by the Light.",
        "lore": "The Light protects.",
        "base_rarity": "legendary",
        "theme": "wow",
        "material_type": "plate",
        "visuals": {
            "icon_url": "/static/items/icons/paladin_bulwark.png",
            "sprite_folder": "shields/paladin/standard",
            "effect": "holy_light",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["damage_reduction", "regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 28,
        "stat_bonuses": {"str": 5, "agi": 0, "dex": 0, "int": 0, "wis": 3, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/shields/paladin_bulwark.png"}
    },
    {
        "item_id": "reinhardt_barrier",
        "item_name": "Reinhardt's Barrier Fragment",
        "item_type": "shield",
        "weapon_type": None,
        "description": "A piece of the legendary barrier.",
        "lore": "BARRIER IS HOLDING!",
        "base_rarity": "epic",
        "theme": "overwatch",
        "material_type": "tech",
        "visuals": {
            "icon_url": "/static/items/icons/reinhardt_barrier.png",
            "sprite_folder": "shields/reinhardt/standard",
            "effect": "barrier_shimmer",
            "glow_color": "#4169E1"
        },
        "effects": {"passive": ["damage_reduction", "poise"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 24,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/shields/reinhardt_barrier.png"}
    }
]

# Wave 3: Rings (10)
WAVE3_RINGS = [
    {
        "item_id": "band_of_scholar",
        "item_name": "Band of the Scholar",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring worn by those who seek knowledge.",
        "lore": "The more you know, the more you forget.",
        "base_rarity": "rare",
        "theme": "hollow_knight",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/band_of_scholar.png",
            "sprite_folder": None,
            "effect": "void_particles",
            "glow_color": "#4A4A6A"
        },
        "effects": {"passive": ["int_bonus"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 5, "wis": 3, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/band_of_scholar.png"}
    },
    {
        "item_id": "gravity_ring",
        "item_name": "Gravity Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring that bends space around the wearer.",
        "lore": "Up is a suggestion.",
        "base_rarity": "epic",
        "theme": "celeste",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/gravity_ring.png",
            "sprite_folder": None,
            "effect": "gravity_distortion",
            "glow_color": "#E85D8C"
        },
        "effects": {"passive": ["move_speed", "stamina_regen"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 5, "dex": 3, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/gravity_ring.png"}
    },
    {
        "item_id": "covenant_ring",
        "item_name": "Covenant Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring marking membership in a sacred covenant.",
        "lore": "Praise the Sun!",
        "base_rarity": "legendary",
        "theme": "dark_souls",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/covenant_ring.png",
            "sprite_folder": None,
            "effect": "sunlight_glow",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["regen", "wis_bonus"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 6, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/accessories/covenant_ring.png"}
    },
    {
        "item_id": "merchant_signet",
        "item_name": "Merchant's Signet",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A signet ring of a successful merchant.",
        "lore": "Buy low, sell high.",
        "base_rarity": "rare",
        "theme": "stardew",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/merchant_signet.png",
            "sprite_folder": None,
            "effect": "coin_sparkle",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["gold_bonus"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 2, "wis": 3, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/accessories/merchant_signet.png"}
    },
    {
        "item_id": "blood_gem_ring",
        "item_name": "Blood Gem Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring set with a blood-red gem.",
        "lore": "The old blood courses through.",
        "base_rarity": "epic",
        "theme": "bloodborne",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/blood_gem_ring.png",
            "sprite_folder": None,
            "effect": "blood_drip",
            "glow_color": "#8B0000"
        },
        "effects": {"passive": ["lifesteal", "crit_chance"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 3, "agi": 0, "dex": 4, "int": 0, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/blood_gem_ring.png"}
    },
    {
        "item_id": "valkyrie_band",
        "item_name": "Valkyrie's Band",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring forged from Valkyrie metal.",
        "lore": "Worthy of Valhalla.",
        "base_rarity": "epic",
        "theme": "god_of_war",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/valkyrie_band.png",
            "sprite_folder": None,
            "effect": "wings_shimmer",
            "glow_color": "#C0C0C0"
        },
        "effects": {"passive": ["boss_damage", "damage_reduction"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 4},
        "sprites": {"icon": "res://assets/icons/forged/accessories/valkyrie_band.png"}
    },
    {
        "item_id": "legendary_ring_halo",
        "item_name": "Legendary Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring forged in the fires of Legendary difficulty.",
        "lore": "Were it so easy.",
        "base_rarity": "legendary",
        "theme": "halo",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/legendary_ring_halo.png",
            "sprite_folder": None,
            "effect": "energy_sword_glow",
            "glow_color": "#00FF00"
        },
        "effects": {"passive": ["damage_reduction", "boss_damage"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 4, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/accessories/legendary_ring_halo.png"}
    },
    {
        "item_id": "athena_favor",
        "item_name": "Athena's Favor",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring blessed by the goddess of wisdom.",
        "lore": "My aid is given freely.",
        "base_rarity": "epic",
        "theme": "hades",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/athena_favor.png",
            "sprite_folder": None,
            "effect": "aegis_shimmer",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["damage_reduction", "poise"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 4, "wis": 4, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/athena_favor.png"}
    },
    {
        "item_id": "sigil_of_mage",
        "item_name": "Sigil of the Mage",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring crackling with arcane power.",
        "lore": "Knowledge is power.",
        "base_rarity": "epic",
        "theme": "wow",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/sigil_of_mage.png",
            "sprite_folder": None,
            "effect": "arcane_sparks",
            "glow_color": "#8A2BE2"
        },
        "effects": {"passive": ["int_bonus", "crit_chance"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 6, "wis": 2, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/sigil_of_mage.png"}
    },
    {
        "item_id": "xelnaga_ring",
        "item_name": "Xel'Naga Artifact Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A ring containing Xel'Naga energy.",
        "lore": "The cycle must be broken.",
        "base_rarity": "rare",
        "theme": "starcraft",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/xelnaga_ring.png",
            "sprite_folder": None,
            "effect": "void_energy",
            "glow_color": "#9400D3"
        },
        "effects": {"passive": ["armor_pierce"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 3, "int": 4, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/xelnaga_ring.png"}
    }
]

# Wave 3: Amulets (4)
WAVE3_AMULETS = [
    {
        "item_id": "focus_lens_amulet",
        "item_name": "Focus Lens Amulet",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "An amulet containing a Focus device lens.",
        "lore": "See what others cannot.",
        "base_rarity": "epic",
        "theme": "horizon",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/focus_lens_amulet.png",
            "sprite_folder": None,
            "effect": "scan_pulse",
            "glow_color": "#4169E1"
        },
        "effects": {"passive": ["crit_chance", "armor_pierce"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 4, "int": 3, "wis": 0, "vit": 0},
        "sprites": {"icon": "res://assets/icons/forged/accessories/focus_lens_amulet.png"}
    },
    {
        "item_id": "astronaut_charm",
        "item_name": "Astronaut Figurine Charm",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "A small astronaut figurine on a chain.",
        "lore": "Helios. Returner.",
        "base_rarity": "rare",
        "theme": "returnal",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/astronaut_charm.png",
            "sprite_folder": None,
            "effect": "loop_shimmer",
            "glow_color": "#00CED1"
        },
        "effects": {"passive": ["death_prevention"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 2, "vit": 5},
        "sprites": {"icon": "res://assets/icons/forged/accessories/astronaut_charm.png"}
    },
    {
        "item_id": "ancient_core_amulet",
        "item_name": "Ancient Core Amulet",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "An amulet powered by ancient Sheikah technology.",
        "lore": "The Calamity has been sealed.",
        "base_rarity": "rare",
        "theme": "zelda",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/ancient_core_amulet.png",
            "sprite_folder": None,
            "effect": "sheikah_glow",
            "glow_color": "#00BFFF"
        },
        "effects": {"passive": ["stamina_regen", "int_bonus"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 4, "wis": 2, "vit": 2},
        "sprites": {"icon": "res://assets/icons/forged/accessories/ancient_core_amulet.png"}
    },
    {
        "item_id": "horadric_charm",
        "item_name": "Horadric Charm",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "An ancient charm from the Horadric order.",
        "lore": "Stay awhile and listen.",
        "base_rarity": "rare",
        "theme": "diablo",
        "material_type": None,
        "visuals": {
            "icon_url": "/static/items/icons/horadric_charm.png",
            "sprite_folder": None,
            "effect": "cube_glow",
            "glow_color": "#FFD700"
        },
        "effects": {"passive": ["regen", "gold_bonus"], "active": None},
        "has_sprites": False,
        "has_icon": True,
        "defense": 0,
        "stat_bonuses": {"str": 0, "agi": 0, "dex": 0, "int": 2, "wis": 3, "vit": 3},
        "sprites": {"icon": "res://assets/icons/forged/accessories/horadric_charm.png"}
    }
]


def main():
    print(f"Loading items.json from: {ITEMS_PATH}")

    with open(ITEMS_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    original_count = len(data['items'])
    print(f"Original item count: {original_count}")

    # Combine all new items
    new_items = WAVE2_ARMS + WAVE2_HANDS + WAVE2_SHIELDS + WAVE3_RINGS + WAVE3_AMULETS

    # Check for duplicates
    existing_ids = {item['item_id'] for item in data['items']}
    items_to_add = []
    skipped = []

    for item in new_items:
        if item['item_id'] in existing_ids:
            skipped.append(item['item_id'])
        else:
            items_to_add.append(item)

    if skipped:
        print(f"Skipping {len(skipped)} items that already exist: {skipped}")

    # Add new items
    data['items'].extend(items_to_add)

    # Update changelog
    old_changelog = data.get('_changelog', '')
    new_changelog = f"v2.3.0: Added Wave 2-3 items ({len(items_to_add)} new): armor_arms, armor_hands, shields, rings, amulets. " + old_changelog
    data['_changelog'] = new_changelog

    # Save
    with open(ITEMS_PATH, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"Added {len(items_to_add)} new items")
    print(f"New total: {len(data['items'])} items")
    print("\nBreakdown:")
    print(f"  - Armor Arms: {len(WAVE2_ARMS)}")
    print(f"  - Armor Hands: {len(WAVE2_HANDS)}")
    print(f"  - Shields: {len(WAVE2_SHIELDS)}")
    print(f"  - Rings: {len(WAVE3_RINGS)}")
    print(f"  - Amulets: {len(WAVE3_AMULETS)}")


if __name__ == '__main__':
    main()
