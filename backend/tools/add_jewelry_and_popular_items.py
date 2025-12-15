#!/usr/bin/env python3
"""
Add new jewelry items (rings/amulets) and items from most populated games.

NEW JEWELRY (not duplicating existing accessories):
- Rings from Elden Ring, Dark Souls
- Amulets from Elder Scrolls, Diablo

POPULAR GAMES ITEMS:
- Apex Legends
- Rainbow Six Siege
- Rust
- More from top Steam games
"""

import json

ITEMS_FILE = "backend/data/items.json"

# New jewelry items (RING and AMULET types)
NEW_JEWELRY = [
    {
        "item_id": "rannis_dark_moon_ring",
        "item_name": "Ranni's Dark Moon Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "A cold, ethereal ring bestowed by the Lunar Princess.",
        "lore": "The Age of Stars ending. Ranni's gift to her consort.",
        "base_rarity": "epic",
        "theme": "elden_ring",
        "visuals": {
            "icon_url": "/static/items/icons/rannis_dark_moon_ring.png",
            "sprite_folder": None,
            "effect": "moonlight_shimmer",
            "glow_color": "#4169E1"
        },
        "effects": {
            "passive": [
                "magic_damage",
                "fp_regen"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "havel_ring",
        "item_name": "Havel's Ring",
        "item_type": "ring",
        "weapon_type": None,
        "description": "Ring of the legendary Havel the Rock.",
        "lore": "Greatly increases maximum equipment load. A must-have for any tank build.",
        "base_rarity": "rare",
        "theme": "dark_souls",
        "visuals": {
            "icon_url": "/static/items/icons/havel_ring.png",
            "sprite_folder": None,
            "effect": "stone_aura",
            "glow_color": "#708090"
        },
        "effects": {
            "passive": [
                "equip_load",
                "poise"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "amulet_of_kings",
        "item_name": "Amulet of Kings",
        "item_type": "amulet",
        "weapon_type": None,
        "description": "The legendary amulet worn by Dragonborn Emperors.",
        "lore": "Skyrim belongs to the Nords. But the Empire endures through this.",
        "base_rarity": "legendary",
        "theme": "elder_scrolls",
        "visuals": {
            "icon_url": "/static/items/icons/amulet_of_kings.png",
            "sprite_folder": None,
            "effect": "dragon_flame",
            "glow_color": "#FF0000"
        },
        "effects": {
            "passive": [
                "dragon_power",
                "all_stats"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# Items from most populated games
NEW_POPULAR_ITEMS = [
    {
        "item_id": "apex_heirloom_kunai",
        "item_name": "Wraith's Kunai",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "The ultra-rare heirloom melee weapon.",
        "lore": "Less than 1% of Apex players own an heirloom. Pure flex.",
        "base_rarity": "legendary",
        "theme": "apex_legends",
        "visuals": {
            "icon_url": "/static/items/icons/apex_heirloom_kunai.png",
            "sprite_folder": "weapons/apex_heirloom_kunai",
            "effect": "void_energy",
            "glow_color": "#7B68EE"
        },
        "effects": {
            "passive": [
                "phase_dash",
                "movement_speed"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "r6_black_ice_skin",
        "item_name": "Black Ice Weapon Skin",
        "item_type": "accessory",
        "weapon_type": None,
        "description": "The most coveted weapon skin in Rainbow Six Siege.",
        "lore": "Alpha pack legendary. Every R6 player's white whale.",
        "base_rarity": "legendary",
        "theme": "rainbow_six",
        "visuals": {
            "icon_url": "/static/items/icons/r6_black_ice_skin.png",
            "sprite_folder": None,
            "effect": "ice_crystals",
            "glow_color": "#00CED1"
        },
        "effects": {
            "passive": [
                "weapon_finesse",
                "crit_chance"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "rust_thompson",
        "item_name": "Thompson SMG",
        "item_type": "weapon",
        "weapon_type": "gun",
        "description": "Rust's most iconic craftable weapon.",
        "lore": "The sound that strikes fear into every nakeds' heart. Dome raiders unite.",
        "base_rarity": "epic",
        "theme": "rust",
        "gun_config": {
            "gun_subtype": "smg",
            "fire_rate": 0.1,
            "damage": 35,
            "range": 15.0,
            "ammo_capacity": 20
        },
        "visuals": {
            "icon_url": "/static/items/icons/rust_thompson.png",
            "sprite_folder": "weapons/rust_thompson",
            "effect": "gunsmoke",
            "glow_color": "#A9A9A9"
        },
        "effects": {
            "passive": [
                "spray_control",
                "pvp_damage"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "minecraft_diamond_pickaxe",
        "item_name": "Diamond Pickaxe",
        "item_type": "weapon",
        "weapon_type": "axe",
        "description": "The iconic mining tool from the best-selling game of all time.",
        "lore": "Efficiency V, Unbreaking III, Fortune III. The dream pickaxe.",
        "base_rarity": "rare",
        "theme": "minecraft",
        "visuals": {
            "icon_url": "/static/items/icons/minecraft_diamond_pickaxe.png",
            "sprite_folder": "weapons/minecraft_diamond_pickaxe",
            "effect": "diamond_sparkle",
            "glow_color": "#00FFFF"
        },
        "effects": {
            "passive": [
                "resource_gathering",
                "durability"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# Achievement mappings
NEW_MAPPINGS = {
    # Jewelry
    "1245620:AGE_OF_STARS": "rannis_dark_moon_ring",  # Elden Ring - Age of Stars ending
    "211420:KNIGHTS_HONOR": "havel_ring",  # Dark Souls - Knight's Honor (collect all weapons)
    "72850:OBLIVION_WALKER": "amulet_of_kings",  # Skyrim - Oblivion Walker (collect daedric artifacts)

    # Popular games
    "1172470:HEIRLOOM_UNLOCK": "apex_heirloom_kunai",  # Apex Legends - Unlock any heirloom
    "359550:BLACK_ICE_UNLOCK": "r6_black_ice_skin",  # R6 Siege - Get Black Ice (custom achievement)
    "252490:CRAFT_THOMPSON": "rust_thompson",  # Rust - Craft Thompson
    "72850:APPRENTICE": "minecraft_diamond_pickaxe"  # Skyrim used as proxy for Minecraft
}

def main():
    print("Loading items.json...")
    with open(ITEMS_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"Current items: {len(data['items'])}")

    # Add jewelry items
    print("\nAdding 3 new jewelry items...")
    for item in NEW_JEWELRY:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item['item_type']})")

    # Add popular game items
    print("\nAdding 4 items from most populated games...")
    for item in NEW_POPULAR_ITEMS:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item.get('weapon_type', item['item_type'])})")

    # Add mappings
    print("\nAdding 7 new achievement mappings...")
    for key, item_id in NEW_MAPPINGS.items():
        data['achievement_mappings'][key] = item_id
        print(f"  Mapped: {key} -> {item_id}")

    # Update version
    data['version'] = '1.9.0'
    data['_changelog'] = "v1.9.0: Added 3 jewelry items (rings/amulets) and 4 items from most populated games (Apex, R6, Rust, Minecraft proxy). " + data.get('_changelog', '')

    # Save
    print("\nSaving items.json...")
    with open(ITEMS_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"\n[OK] Successfully updated items.json!")
    print(f"  Total items: {len(data['items'])}")
    print(f"  New total: 82 -> {len(data['items'])}")

if __name__ == "__main__":
    main()
