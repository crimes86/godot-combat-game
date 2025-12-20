#!/usr/bin/env python3
"""
Add 27 Blizzard items (9 each for Diablo, Overwatch, StarCraft) to items.json.
This brings Blizzard representation to equal distribution across 4 franchises.

Phase 1 Approach: Design items with placeholder achievement IDs.
API integration and real achievement IDs will be added in future phases.
"""

import json

ITEMS_FILE = "backend/data/items.json"

# === DIABLO ITEMS (9 total: 4 Legendary, 3 Epic, 2 Rare) ===
DIABLO_ITEMS = [
    # Legendary (4 items)
    {
        "item_id": "tyraels_might",
        "item_name": "Tyrael's Might",
        "item_type": "armor_chest",
        "weapon_type": None,
        "description": "Sacred armor worn by the Archangel of Justice.",
        "lore": "Forged in the High Heavens. Obtaining a Primal Ancient requires both skill and divine favor.",
        "base_rarity": "legendary",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/tyraels_might.png",
            "sprite_folder": None,
            "effect": "holy_radiance",
            "glow_color": "#FFD700"
        },
        "effects": {
            "passive": ["holy_damage", "damage_reduction"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "stone_of_jordan",
        "item_name": "Stone of Jordan",
        "item_type": "ring",
        "weapon_type": None,
        "description": "The most legendary ring in Sanctuary's history.",
        "lore": "Currency of the ancients. Complete Set Dungeon Mastery to prove your worth.",
        "base_rarity": "legendary",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/stone_of_jordan.png",
            "sprite_folder": None,
            "effect": "mana_glow",
            "glow_color": "#4169E1"
        },
        "effects": {
            "passive": ["elemental_damage", "resource_cost_reduction"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "butchers_cleaver",
        "item_name": "The Butcher's Cleaver",
        "item_type": "weapon",
        "weapon_type": "axe",
        "description": "Fresh meat! The demonic weapon of the infamous Butcher.",
        "lore": "Defeating the Butcher in Hardcore Hell mode is a rite of passage for true nephalem.",
        "base_rarity": "legendary",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/butchers_cleaver.png",
            "sprite_folder": "weapons/butchers_cleaver",
            "effect": "blood_drip",
            "glow_color": "#8B0000"
        },
        "effects": {
            "passive": ["fire_damage", "life_on_hit"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "horadric_cube",
        "item_name": "Horadric Cube",
        "item_type": "accessory",
        "weapon_type": None,
        "description": "An artifact of immense transmutation power.",
        "lore": "Reaching Greater Rift 150 requires mastery of build optimization and perfect execution.",
        "base_rarity": "legendary",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/horadric_cube.png",
            "sprite_folder": None,
            "effect": "transmutation_spark",
            "glow_color": "#FF8C00"
        },
        "effects": {
            "passive": ["item_find", "transmutation_bonus"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Epic (3 items)
    {
        "item_id": "el_druins_sword",
        "item_name": "El'druin, the Sword of Justice",
        "item_type": "weapon",
        "weapon_type": "sword",
        "description": "Tyrael's legendary blade, forged by the Archangel himself.",
        "lore": "Complete the Season Journey to wield the weapon that severed Tyrael from the Angiris Council.",
        "base_rarity": "epic",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/el_druins_sword.png",
            "sprite_folder": "weapons/el_druins_sword",
            "effect": "angelic_light",
            "glow_color": "#87CEEB"
        },
        "effects": {
            "passive": ["holy_damage", "attack_speed"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "natalyas_shadow_Ashbane",
        "item_name": "Natalya's Shadow Ashbane",
        "item_type": "cape",
        "weapon_type": None,
        "description": "Cloak of the legendary assassin Natalya.",
        "lore": "Master all class achievements to claim the Ashbane of Sanctuary's deadliest hunter.",
        "base_rarity": "epic",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/natalyas_shadow_Ashbane.png",
            "sprite_folder": None,
            "effect": "shadow_shroud",
            "glow_color": "#2F4F4F"
        },
        "effects": {
            "passive": ["critical_chance", "stealth_bonus"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "echoing_fury",
        "item_name": "Echoing Fury",
        "item_type": "weapon",
        "weapon_type": "mace",
        "description": "A weapon that screams with the fury of countless demons.",
        "lore": "Reach Paragon 1000 to harness the echoing power of this demonic mace.",
        "base_rarity": "epic",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/echoing_fury.png",
            "sprite_folder": "weapons/echoing_fury",
            "effect": "demonic_echo",
            "glow_color": "#9400D3"
        },
        "effects": {
            "passive": ["attack_speed", "fear_on_hit"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Rare (2 items)
    {
        "item_id": "black_soulstone",
        "item_name": "Black Soulstone",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "Contains the essence of the Seven Evils.",
        "lore": "Complete the campaign on Torment XVI to claim this corrupted artifact.",
        "base_rarity": "rare",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/black_soulstone.png",
            "sprite_folder": None,
            "effect": "soul_corruption",
            "glow_color": "#000000"
        },
        "effects": {
            "passive": ["all_stats", "absorb_souls"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "andariel_visage",
        "item_name": "Andariel's Visage",
        "item_type": "armor_head",
        "weapon_type": None,
        "description": "The helm of the Maiden of Anguish.",
        "lore": "Defeat all Act bosses on Expert difficulty to claim this poisonous crown.",
        "base_rarity": "rare",
        "theme": "diablo",
        "visuals": {
            "icon_url": "/static/items/icons/andariel_visage.png",
            "sprite_folder": None,
            "effect": "poison_aura",
            "glow_color": "#00FF00"
        },
        "effects": {
            "passive": ["poison_damage", "life_steal"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# === OVERWATCH ITEMS (9 total: 4 Legendary, 3 Epic, 2 Rare) ===
OVERWATCH_ITEMS = [
    # Legendary (4 items)
    {
        "item_id": "genji_dragonblade",
        "item_name": "Genji's Dragon Blade",
        "item_type": "weapon",
        "weapon_type": "katana",
        "description": "The blade that channels the dragon spirit.",
        "lore": "Reach Top 500 Competitive ranking to wield the weapon of Overwatch's legendary cyborg ninja.",
        "base_rarity": "legendary",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/genji_dragonblade.png",
            "sprite_folder": "weapons/genji_dragonblade",
            "effect": "dragon_energy",
            "glow_color": "#00FF00"
        },
        "effects": {
            "passive": ["swift_strike", "deflect"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "tracer_chronal_accelerator",
        "item_name": "Tracer's Chronal Accelerator",
        "item_type": "accessory",
        "weapon_type": None,
        "description": "Time-manipulation device keeping Tracer anchored to the present.",
        "lore": "Unlock all Overwatch 1 Anniversary event skins to claim this legendary tech.",
        "base_rarity": "legendary",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/tracer_chronal_accelerator.png",
            "sprite_folder": None,
            "effect": "time_distortion",
            "glow_color": "#FF8C00"
        },
        "effects": {
            "passive": ["blink", "recall"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "reaper_hellfire_shotguns",
        "item_name": "Reaper's Hellfire Shotguns",
        "item_type": "weapon",
        "weapon_type": "gun",
        "description": "Twin shotguns wielded by Overwatch's most feared agent.",
        "lore": "Achieve Grandmaster rank in 5 competitive seasons to claim Death's arsenal.",
        "base_rarity": "legendary",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/reaper_hellfire_shotguns.png",
            "sprite_folder": "weapons/reaper_hellfire_shotguns",
            "effect": "wraith_smoke",
            "glow_color": "#000000"
        },
        "effects": {
            "passive": ["wraith_form", "soul_harvest"],
            "active": None
        },
        "gun_config": {
            "gun_subtype": "shotgun",
            "fire_rate": 0.5,
            "damage": 140,
            "range": 8.0,
            "ammo_capacity": 8
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "doomfist_gauntlet",
        "item_name": "Doomfist's Gauntlet",
        "item_type": "armor_hands",
        "weapon_type": None,
        "description": "Legendary power gauntlet of the Talon leader.",
        "lore": "Complete all hero mastery challenges to earn the right to wield this devastatin weapon.",
        "base_rarity": "legendary",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/doomfist_gauntlet.png",
            "sprite_folder": None,
            "effect": "seismic_slam",
            "glow_color": "#FF4500"
        },
        "effects": {
            "passive": ["rocket_punch", "meteor_strike"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Epic (3 items)
    {
        "item_id": "reinhardt_crusader_armor",
        "item_name": "Reinhardt's Crusader Armor",
        "item_type": "armor_chest",
        "weapon_type": None,
        "description": "Powered armor of Overwatch's steadfast defender.",
        "lore": "Reach Grandmaster rank to don the armor of the legendary Crusader.",
        "base_rarity": "epic",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/reinhardt_crusader_armor.png",
            "sprite_folder": None,
            "effect": "barrier_field",
            "glow_color": "#4682B4"
        },
        "effects": {
            "passive": ["barrier_shield", "charge"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "mercy_caduceus_staff",
        "item_name": "Mercy's Caduceus Staff",
        "item_type": "weapon",
        "weapon_type": "staff",
        "description": "Medical device that can heal allies or boost their damage.",
        "lore": "Resurrect 1000 heroes to master the Valkyrie's iconic weapon.",
        "base_rarity": "epic",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/mercy_caduceus_staff.png",
            "sprite_folder": "weapons/mercy_caduceus_staff",
            "effect": "healing_beam",
            "glow_color": "#FFD700"
        },
        "effects": {
            "passive": ["healing", "damage_boost"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "winston_jump_pack",
        "item_name": "Winston's Jump Pack",
        "item_type": "cape",
        "weapon_type": None,
        "description": "Experimental jetpack designed by the genius gorilla scientist.",
        "lore": "Score 20 environmental eliminations with Winston to earn his signature mobility tech.",
        "base_rarity": "epic",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/winston_jump_pack.png",
            "sprite_folder": None,
            "effect": "jet_thrust",
            "glow_color": "#87CEEB"
        },
        "effects": {
            "passive": ["leap", "primal_rage"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Rare (2 items)
    {
        "item_id": "widowmaker_kiss",
        "item_name": "Widowmaker's Kiss",
        "item_type": "weapon",
        "weapon_type": "gun",
        "description": "Precision sniper rifle of Talon's deadliest assassin.",
        "lore": "Land 100 critical hits with Widowmaker to claim her legendary weapon.",
        "base_rarity": "rare",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/widowmaker_kiss.png",
            "sprite_folder": "weapons/widowmaker_kiss",
            "effect": "venom_mine",
            "glow_color": "#9400D3"
        },
        "effects": {
            "passive": ["grappling_hook", "infra_sight"],
            "active": None
        },
        "gun_config": {
            "gun_subtype": "sniper",
            "fire_rate": 1.2,
            "damage": 120,
            "range": 40.0,
            "ammo_capacity": 30
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "orisa_halt_projector",
        "item_name": "Orisa's Halt Projector",
        "item_type": "accessory",
        "weapon_type": None,
        "description": "Graviton charge launcher designed by Efi Oladele.",
        "lore": "Reach Platinum rank to unlock this crowd-control masterpiece.",
        "base_rarity": "rare",
        "theme": "overwatch",
        "visuals": {
            "icon_url": "/static/items/icons/orisa_halt_projector.png",
            "sprite_folder": None,
            "effect": "graviton_pull",
            "glow_color": "#00FF00"
        },
        "effects": {
            "passive": ["fortify", "protective_barrier"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# === STARCRAFT ITEMS (9 total: 4 Legendary, 3 Epic, 2 Rare) ===
STARCRAFT_ITEMS = [
    # Legendary (4 items)
    {
        "item_id": "raynor_marine_armor",
        "item_name": "Raynor's Marine Armor",
        "item_type": "armor_chest",
        "weapon_type": None,
        "description": "Iconic CMC combat suit of the legendary Jim Raynor.",
        "lore": "Complete all StarCraft II campaigns on Brutal difficulty to earn this heroic armor.",
        "base_rarity": "legendary",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/raynor_marine_armor.png",
            "sprite_folder": None,
            "effect": "terran_steel",
            "glow_color": "#4682B4"
        },
        "effects": {
            "passive": ["armor_plating", "stim_pack"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "kerrigan_psi_blade",
        "item_name": "Kerrigan's Psi-Blade",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "Psionic wing-blades of the Queen of Blades.",
        "lore": "Master all Zerg campaign achievements to wield the power of the Swarm.",
        "base_rarity": "legendary",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/kerrigan_psi_blade.png",
            "sprite_folder": "weapons/kerrigan_psi_blade",
            "effect": "psionic_energy",
            "glow_color": "#9400D3"
        },
        "effects": {
            "passive": ["kinetic_blast", "primal_grasp"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "protoss_warp_prism",
        "item_name": "Protoss Warp Prism",
        "item_type": "accessory",
        "weapon_type": None,
        "description": "Warp technology device from the Khalai.",
        "lore": "Achieve Mastery 90+ with all Co-op commanders to master this Protoss tech.",
        "base_rarity": "legendary",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/protoss_warp_prism.png",
            "sprite_folder": None,
            "effect": "warp_field",
            "glow_color": "#FFD700"
        },
        "effects": {
            "passive": ["phase_shift", "transport"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "zeratul_warp_blade",
        "item_name": "Zeratul's Warp Blade",
        "item_type": "weapon",
        "weapon_type": "sword",
        "description": "Psionic blade of the Dark Templar prelate.",
        "lore": "Complete Legacy of the Void mastery achievements to wield Zeratul's legendary weapon.",
        "base_rarity": "legendary",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/zeratul_warp_blade.png",
            "sprite_folder": "weapons/zeratul_warp_blade",
            "effect": "void_energy",
            "glow_color": "#00CED1"
        },
        "effects": {
            "passive": ["permanent_cloak", "void_prison"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Epic (3 items)
    {
        "item_id": "artanis_psi_blades",
        "item_name": "Artanis's Psi Blades",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "Twin psionic blades of the Hierarch of the Daelaam.",
        "lore": "Master all Protoss campaign achievements to claim the blades of the Hierarch.",
        "base_rarity": "epic",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/artanis_psi_blades.png",
            "sprite_folder": "weapons/artanis_psi_blades",
            "effect": "psionic_storm",
            "glow_color": "#FFD700"
        },
        "effects": {
            "passive": ["psionic_storm", "guardian_shell"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "siege_tank_cannon",
        "item_name": "Siege Tank Cannon",
        "item_type": "weapon",
        "weapon_type": "gun",
        "description": "120mm cannon from the Terran Crucio Siege Tank.",
        "lore": "Reach Grandmaster ladder rank as Terran to command this devastating firepower.",
        "base_rarity": "epic",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/siege_tank_cannon.png",
            "sprite_folder": "weapons/siege_tank_cannon",
            "effect": "siege_blast",
            "glow_color": "#FF4500"
        },
        "effects": {
            "passive": ["siege_mode", "explosive_rounds"],
            "active": None
        },
        "gun_config": {
            "gun_subtype": "cannon",
            "fire_rate": 2.0,
            "damage": 200,
            "range": 30.0,
            "ammo_capacity": 4
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "dark_templar_armor",
        "item_name": "Dark Templar Shroud",
        "item_type": "cape",
        "weapon_type": None,
        "description": "Ceremonial shroud of the Nerazim warriors.",
        "lore": "Complete Heart of the Swarm campaign on Hard to claim the Ashbane of shadow.",
        "base_rarity": "epic",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/dark_templar_armor.png",
            "sprite_folder": None,
            "effect": "shadow_walk",
            "glow_color": "#2F4F4F"
        },
        "effects": {
            "passive": ["permanent_cloak", "shadow_strike"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },

    # Rare (2 items)
    {
        "item_id": "zergling_claws",
        "item_name": "Zergling Claws",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "Bio-weapon claws from the Zerg's fastest unit.",
        "lore": "Reach Diamond ladder rank as Zerg to harness the speed of the Swarm.",
        "base_rarity": "rare",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/zergling_claws.png",
            "sprite_folder": "weapons/zergling_claws",
            "effect": "metabolic_boost",
            "glow_color": "#9400D3"
        },
        "effects": {
            "passive": ["adrenal_glands", "rapid_strike"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "khala_amulet",
        "item_name": "Khala Amulet",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "Sacred talisman connecting to the Protoss psionic link.",
        "lore": "Complete Wings of Liberty campaign to commune with the Khala.",
        "base_rarity": "rare",
        "theme": "starcraft",
        "visuals": {
            "icon_url": "/static/items/icons/khala_amulet.png",
            "sprite_folder": None,
            "effect": "psionic_link",
            "glow_color": "#00CED1"
        },
        "effects": {
            "passive": ["psionic_link", "shield_regen"],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# Achievement mappings (placeholder IDs for Phase 1)
BLIZZARD_MAPPINGS = {
    # Diablo mappings
    "battlenet:diablo4:PRIMAL_ANCIENT": "tyraels_might",
    "battlenet:diablo3:SET_DUNGEON_MASTERY": "stone_of_jordan",
    "battlenet:diablo3:BUTCHER_HARDCORE_HELL": "butchers_cleaver",
    "battlenet:diablo4:GREATER_RIFT_150": "horadric_cube",
    "battlenet:diablo4:SEASON_JOURNEY_GUARDIAN": "el_druins_sword",
    "battlenet:diablo3:ALL_CLASS_MASTERY": "natalyas_shadow_Ashbane",
    "battlenet:diablo3:PARAGON_1000": "echoing_fury",
    "battlenet:diablo4:CAMPAIGN_TORMENT_XVI": "black_soulstone",
    "battlenet:diablo3:ALL_ACTS_EXPERT": "andariel_visage",

    # Overwatch mappings
    "battlenet:overwatch2:TOP_500_COMPETITIVE": "genji_dragonblade",
    "battlenet:overwatch:ANNIVERSARY_SKINS_ALL": "tracer_chronal_accelerator",
    "battlenet:overwatch2:GRANDMASTER_5_SEASONS": "reaper_hellfire_shotguns",
    "battlenet:overwatch2:ALL_HERO_MASTERY": "doomfist_gauntlet",
    "battlenet:overwatch2:GRANDMASTER_RANK": "reinhardt_crusader_armor",
    "battlenet:overwatch2:RESURRECT_1000": "mercy_caduceus_staff",
    "battlenet:overwatch2:WINSTON_ENVIRONMENTAL_20": "winston_jump_pack",
    "battlenet:overwatch2:WIDOWMAKER_CRITS_100": "widowmaker_kiss",
    "battlenet:overwatch2:PLATINUM_RANK": "orisa_halt_projector",

    # StarCraft mappings
    "battlenet:starcraft2:ALL_CAMPAIGNS_BRUTAL": "raynor_marine_armor",
    "battlenet:starcraft2:ZERG_MASTERY_ALL": "kerrigan_psi_blade",
    "battlenet:starcraft2:COOP_MASTERY_90_ALL": "protoss_warp_prism",
    "battlenet:starcraft2:LOTV_MASTERY_ALL": "zeratul_warp_blade",
    "battlenet:starcraft2:PROTOSS_MASTERY_ALL": "artanis_psi_blades",
    "battlenet:starcraft2:GRANDMASTER_TERRAN": "siege_tank_cannon",
    "battlenet:starcraft2:HOTS_CAMPAIGN_HARD": "dark_templar_armor",
    "battlenet:starcraft2:DIAMOND_ZERG": "zergling_claws",
    "battlenet:starcraft2:WOL_CAMPAIGN": "khala_amulet"
}

def main():
    print("Loading items.json...")
    with open(ITEMS_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"Current items: {len(data['items'])}")
    print(f"Current mappings: {len(data['achievement_mappings'])}")

    # Add Diablo items
    print("\nAdding 9 Diablo items...")
    for item in DIABLO_ITEMS:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item.get('weapon_type', item['item_type'])}, {item['base_rarity']})")

    # Add Overwatch items
    print("\nAdding 9 Overwatch items...")
    for item in OVERWATCH_ITEMS:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item.get('weapon_type', item['item_type'])}, {item['base_rarity']})")

    # Add StarCraft items
    print("\nAdding 9 StarCraft items...")
    for item in STARCRAFT_ITEMS:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item.get('weapon_type', item['item_type'])}, {item['base_rarity']})")

    # Add achievement mappings
    print("\nAdding 27 Blizzard achievement mappings...")
    for key, item_id in BLIZZARD_MAPPINGS.items():
        data['achievement_mappings'][key] = item_id
        print(f"  Mapped: {key} -> {item_id}")

    # Update version
    old_version = data.get('version', '1.9.0')
    new_version = '2.0.0'
    data['version'] = new_version

    # Update changelog
    changelog = data.get('_changelog', '')
    new_changelog = f"v{new_version}: Added 27 Blizzard items (9 Diablo, 9 Overwatch, 9 StarCraft) for ecosystem standardization. Equal distribution across all Blizzard franchises. {changelog}"
    data['_changelog'] = new_changelog

    # Save
    print("\nSaving items.json...")
    with open(ITEMS_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"\n[OK] Successfully added 27 Blizzard items!")
    print(f"  Version: {old_version} -> {new_version}")
    print(f"  Total items: {len(data['items'])}")
    print(f"  Total mappings: {len(data['achievement_mappings'])}")
    print(f"  Blizzard total: 9 (WoW only) -> 36 (WoW + Diablo + Overwatch + StarCraft)")
    print("\nNext steps:")
    print("  1. Verify items.json is valid JSON")
    print("  2. Test in Godot (should show 116 forged items loaded)")
    print("  3. Create icons for 27 new items (64x64 PNG)")
    print("  4. Create sprites for weapons as needed")
    print("  5. Update documentation (FORGE_ACHIEVEMENT_SHORTLIST_V3.md, etc.)")

if __name__ == "__main__":
    main()
