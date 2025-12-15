#!/usr/bin/env python3
"""
Add 4 new dagger items to items.json:
1. Ezio's Hidden Blade (AC II)
2. Sam Fisher's Ka-Bar (Splinter Cell)
3. Fiber Wire (Hitman 3)
4. CS:GO Karambit (Counter-Strike)
"""

import json
from pathlib import Path

ITEMS_FILE = "backend/data/items.json"

# New dagger items
NEW_DAGGERS = [
    {
        "item_id": "ezios_hidden_blade",
        "item_name": "Ezio's Hidden Blade",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "The iconic weapon of the Master Assassin.",
        "lore": "Nothing is true, everything is permitted. Ezio Auditore's signature weapon.",
        "base_rarity": "legendary",
        "theme": "assassins_creed",
        "visuals": {
            "icon_url": "/static/items/icons/ezios_hidden_blade.png",
            "sprite_folder": "weapons/ezios_hidden_blade",
            "effect": "assassin_shimmer",
            "glow_color": "#FFFFFF"
        },
        "effects": {
            "passive": [
                "backstab_damage",
                "stealth_move_speed"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "sam_fishers_kabar",
        "item_name": "Sam Fisher's Ka-Bar",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "Combat knife of the legendary Splinter Cell operative.",
        "lore": "Silent. Precise. Lethal. Sam Fisher's trusted blade for close quarters.",
        "base_rarity": "legendary",
        "theme": "splinter_cell",
        "visuals": {
            "icon_url": "/static/items/icons/sam_fishers_kabar.png",
            "sprite_folder": "weapons/sam_fishers_kabar",
            "effect": "stealth_blur",
            "glow_color": "#2F4F4F"
        },
        "effects": {
            "passive": [
                "stealth_damage",
                "night_vision"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "fiber_wire",
        "item_name": "Agent 47's Fiber Wire",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "The signature silent elimination tool.",
        "lore": "Silent Assassin. Suit Only. No witnesses. Agent 47's preferred method.",
        "base_rarity": "legendary",
        "theme": "hitman",
        "visuals": {
            "icon_url": "/static/items/icons/fiber_wire.png",
            "sprite_folder": "weapons/fiber_wire",
            "effect": "shadow_fade",
            "glow_color": "#8B0000"
        },
        "effects": {
            "passive": [
                "silent_kill",
                "disguise_bonus"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    },
    {
        "item_id": "csgo_karambit",
        "item_name": "StatTrak™ Karambit",
        "item_type": "weapon",
        "weapon_type": "dagger",
        "description": "Counter-Strike's most iconic knife.",
        "lore": "The ultimate flex. Every competitive player's dream knife.",
        "base_rarity": "epic",
        "theme": "counter_strike",
        "visuals": {
            "icon_url": "/static/items/icons/csgo_karambit.png",
            "sprite_folder": "weapons/csgo_karambit",
            "effect": "stattrak_glow",
            "glow_color": "#FF4500"
        },
        "effects": {
            "passive": [
                "backstab_instakill",
                "movement_speed"
            ],
            "active": None
        },
        "has_sprites": False,
        "has_icon": False
    }
]

# New achievement mappings
NEW_MAPPINGS = {
    "33230:ACH_FINISH_GAME": "ezios_hidden_blade",  # AC II - Finish the game
    "209870:ACH_COMPLETE_GAME_PERFECTIONIST": "sam_fishers_kabar",  # Splinter Cell Blacklist - Perfectionist difficulty
    "1659040:SILENT_ASSASSIN_SUIT_ONLY": "fiber_wire",  # Hitman 3 - Silent Assassin Suit Only
    "730:WIN_KNIFE_FIGHTS_LOW": "csgo_karambit"  # CS:GO - Knife kills achievement
}

def main():
    print("Loading items.json...")
    with open(ITEMS_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"Current items: {len(data['items'])}")
    print(f"Current mappings: {len([k for k in data['achievement_mappings'].keys() if not k.startswith('_')])}")

    # Add new items
    print("\nAdding 4 new dagger items...")
    for item in NEW_DAGGERS:
        data['items'].append(item)
        print(f"  Added: {item['item_name']} ({item['item_id']})")

    # Add new achievement mappings
    print("\nAdding 4 new achievement mappings...")
    for key, item_id in NEW_MAPPINGS.items():
        data['achievement_mappings'][key] = item_id
        print(f"  Mapped: {key} -> {item_id}")

    # Update version
    old_version = data.get('version', '1.7.0')
    new_version = '1.8.0'
    data['version'] = new_version

    # Update changelog
    changelog = data.get('_changelog', '')
    new_changelog = f"v{new_version}: Added 4 dagger weapons (Ezio's Hidden Blade, Sam Fisher's Ka-Bar, Fiber Wire, CS:GO Karambit). {changelog}"
    data['_changelog'] = new_changelog

    # Save back to file
    print("\nSaving items.json...")
    with open(ITEMS_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"\n✓ Successfully updated items.json!")
    print(f"  Version: {old_version} -> {new_version}")
    print(f"  Total items: {len(data['items'])}")
    print(f"  Total mappings: {len([k for k in data['achievement_mappings'].keys() if not k.startswith('_')])}")
    print("\nNext steps:")
    print("  1. Test in Godot to verify ForgeItemDB loads correctly")
    print("  2. Create 64x64 icons for the 4 daggers")
    print("  3. Create LPC sprite sheets for the 4 daggers")
    print("  4. Update FORGE_ACHIEVEMENT_SHORTLIST.md")

if __name__ == "__main__":
    main()
