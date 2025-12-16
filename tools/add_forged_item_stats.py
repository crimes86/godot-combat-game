#!/usr/bin/env python3
"""
Add combat stats to forged items in items.json.

Forged items should have T3-equivalent stats since they're endgame-viable from level 1.
This implements the "twinking" system from NATIVE_ITEMIZATION.md.
"""

import json
from pathlib import Path

# Base stats by weapon type (T3 equivalent)
# Format: (min_damage, max_damage, attack_speed, primary_stat, secondary_stat, primary_bonus, secondary_bonus)
# Speed is weapon-based (no stat scaling): "very_fast" < "fast" < "medium" < "slow"
# Crit chance is purely stat-based: DEX for melee, WIS for caster (removed from weapons)
# 6-STAT SYSTEM: STR (plate dmg), AGI (leather dmg), DEX (melee crit), INT (caster dmg), WIS (caster crit), VIT (tank HP)
#
# BALANCE: Weapon base damage is balanced for equal DPS across speed tiers.
# Reference: ~108 base weapon DPS at T3 (very_fast benchmark)
# - very_fast (0.25s): 27 avg damage -> 108 DPS
# - fast (0.40s): 43 avg damage -> 107.5 DPS
# - medium (0.60s): 65 avg damage -> 108.3 DPS
# - slow (0.85s): 92 avg damage -> 108.2 DPS
# Stat scaling is also speed-adjusted in CharacterStats.gd so +1 stat = same DPS regardless of weapon.
WEAPON_STATS = {
    # Heavy weapons (STR scaling) - Used by Plate Tank and Plate DPS
    # Slow/medium weapons have higher per-hit damage, equal DPS to fast weapons
    "greatsword": (82, 102, "slow", "str", "dex", 15, 8),      # Highest per-hit, Plate DPS
    "sword": (58, 72, "medium", "str", "vit", 10, 10),         # Balanced, Tank
    "axe": (78, 98, "slow", "str", "dex", 12, 8),              # Bleed weapon, Plate DPS
    "mace": (75, 95, "slow", "str", "vit", 10, 12),            # Armor pen, Tank
    "hammer": (80, 100, "slow", "str", "vit", 14, 10),         # Knockback, Tank
    "spear": (58, 72, "medium", "str", "dex", 10, 8),          # Reach, Versatile
    "halberd": (78, 98, "slow", "str", "dex", 12, 8),          # Reach + damage, Plate DPS
    "pike": (60, 74, "medium", "str", "dex", 10, 8),
    "trident": (60, 74, "medium", "str", "dex", 10, 8),
    "flail": (62, 76, "medium", "str", "vit", 11, 9),

    # Light weapons (AGI scaling) - Used by Leather DPS (Assassin)
    # Fast weapons: more hits, lower per-hit, same DPS
    "dagger": (22, 32, "very_fast", "agi", "dex", 12, 10),     # Many small hits, on-hit procs
    "rapier": (38, 48, "fast", "agi", "dex", 12, 8),           # Armor pen identity
    "katana": (40, 50, "fast", "agi", "dex", 10, 10),          # Balanced, weakpoint bonus
    "scimitar": (38, 48, "fast", "agi", "dex", 10, 8),         # Bleed on crit
    "saber": (40, 50, "fast", "agi", "dex", 10, 8),            # Parry/riposte
    "bow": (60, 74, "medium", "agi", "dex", 10, 8),            # Ranged
    "claws": (22, 32, "very_fast", "agi", "dex", 12, 10),      # Fast strikes (same as dagger)

    # Staff weapons (INT scaling) - Used by Caster and Healer
    "staff": (60, 74, "medium", "int", "wis", 12, 8),          # Generic staff
    "damage_staff": (62, 76, "medium", "int", "wis", 14, 8),   # Caster DPS
    "healing_staff": (55, 68, "medium", "int", "vit", 10, 12), # Healer (VIT for survivability)
    "support_staff": (58, 72, "medium", "int", "wis", 12, 10), # Support

    # Psi weapons (INT scaling - melee caster hybrid)
    "psi_blade": (38, 48, "fast", "int", "wis", 12, 8),
    "warp_blade": (40, 50, "fast", "int", "wis", 10, 10),

    # Gun weapons (AGI/STR scaling depending on type)
    "rifle": (60, 74, "medium", "agi", "dex", 10, 8),          # Precision = AGI
    "shotgun": (78, 98, "slow", "str", "dex", 12, 8),          # Power = STR
    "cannon": (82, 102, "slow", "str", "vit", 14, 12),         # Heavy = STR + Tank

    # Fist weapons (STR/AGI hybrid)
    "gauntlet": (40, 50, "fast", "str", "dex", 10, 8),         # STR brawler
}

# Rarity multipliers
RARITY_MULT = {
    "common": 0.7,
    "uncommon": 0.85,
    "rare": 1.0,
    "epic": 1.15,
    "legendary": 1.3,
}

# Armor stats by type (defense, primary_stat, secondary_stat, primary_bonus, secondary_bonus)
ARMOR_STATS = {
    "armor_head": (15, 3, 5),   # defense, stat1_bonus, stat2_bonus
    "armor_chest": (25, 5, 8),
    "armor_hands": (10, 2, 3),
    "armor_legs": (20, 4, 6),
    "armor_feet": (12, 2, 4),
    "shield": (30, 4, 6),  # Higher defense for shields
    "cape": (5, 2, 3),     # Low defense, mostly cosmetic
}

# Accessory effects by theme
ACCESSORY_STATS = {
    "default": {"hp_bonus": 20, "stat_bonus": 5},
    "souls": {"hp_bonus": 30, "stat_bonus": 6},
    "starcraft": {"hp_bonus": 25, "cooldown_reduction": 0.05},
    "overwatch": {"movement_speed": 0.08, "stat_bonus": 5},
    "diablo": {"lifesteal": 0.03, "stat_bonus": 6},
}

# Heavy weapons that should have lifesteal (Tank sustain)
HEAVY_WEAPON_TYPES = ["sword", "greatsword", "axe", "mace", "hammer", "spear", "halberd", "pike", "trident", "flail", "gauntlet"]
# Light weapons that should have DPS effects (NOT lifesteal)
LIGHT_WEAPON_TYPES = ["dagger", "rapier", "katana", "scimitar", "saber", "bow", "claws"]
# Staff weapons (INT scaling)
STAFF_WEAPON_TYPES = ["staff", "damage_staff", "healing_staff", "support_staff", "psi_blade", "warp_blade"]

# Effect reassignment rules
# Lifesteal should be on HEAVY weapons (tank sustain), NOT on light weapons
# Light weapons get: bleed, armor_pen, crit_damage, execute, backstab
TANK_EFFECTS = ["lifesteal", "regen", "poise", "armor_plating"]
DPS_EFFECTS = ["bleed", "armor_pen", "crit_damage", "execute", "backstab", "dot_on_hit", "chain_bonus"]


def fix_weapon_effects(item):
    """Reassign effects based on weapon type - lifesteal goes to tank weapons only."""
    weapon_type = item.get("weapon_type", "sword").lower()
    item_id = item.get("item_id", "").lower()

    # Determine actual weapon category
    is_heavy = weapon_type in HEAVY_WEAPON_TYPES
    is_light = weapon_type in LIGHT_WEAPON_TYPES
    is_staff = weapon_type in STAFF_WEAPON_TYPES

    # Special handling for psi weapons
    if "psi" in item_id or "warp" in item_id:
        is_staff = True
        is_light = False

    effects = item.get("effects", {})
    if not effects or not isinstance(effects, dict):
        return item

    passive = effects.get("passive", [])
    if not passive or not isinstance(passive, list):
        return item

    # Track if we made changes
    original_passive = passive.copy()

    # If light weapon has lifesteal, replace with appropriate DPS effect
    if is_light and "lifesteal" in passive:
        passive.remove("lifesteal")
        # Add a DPS effect based on weapon type
        if weapon_type == "dagger":
            if "backstab" not in passive:
                passive.append("backstab")
        elif weapon_type == "katana":
            if "execute" not in passive:
                passive.append("execute")
        elif weapon_type == "rapier":
            if "armor_pen" not in passive:
                passive.append("armor_pen")
        elif weapon_type == "scimitar":
            if "bleed" not in passive:
                passive.append("bleed")
        else:
            if "crit_damage" not in passive:
                passive.append("crit_damage")

    # If heavy weapon doesn't have lifesteal and has room, consider adding it
    # (Only for weapons that would benefit - tanks)
    # Don't auto-add, just fix misplaced effects

    if passive != original_passive:
        effects["passive"] = passive
        item["effects"] = effects
        print(f"  Fixed effects for {item.get('item_name', 'Unknown')}: {original_passive} -> {passive}")

    return item


def add_weapon_stats(item):
    """Add combat stats to a weapon item."""
    weapon_type = item.get("weapon_type", "sword")
    rarity = item.get("base_rarity", "rare").lower()

    # Handle special weapon types
    if "psi" in item.get("item_id", "").lower() or "psi" in weapon_type.lower():
        if "blade" in item.get("item_id", "").lower():
            weapon_type = "psi_blade"
    elif "warp" in item.get("item_id", "").lower():
        weapon_type = "warp_blade"
    elif "shotgun" in item.get("item_id", "").lower() or "hellfire" in item.get("item_id", "").lower():
        weapon_type = "shotgun"
    elif "rifle" in item.get("item_id", "").lower() or "battle_rifle" in item.get("item_id", "").lower():
        weapon_type = "rifle"
    elif "cannon" in item.get("item_id", "").lower():
        weapon_type = "cannon"
    elif "gauntlet" in item.get("item_id", "").lower() or "fist" in weapon_type.lower():
        weapon_type = "gauntlet"
    elif "claw" in item.get("item_id", "").lower():
        weapon_type = "claws"

    # Get base stats
    stats = WEAPON_STATS.get(weapon_type, WEAPON_STATS["sword"])
    min_dmg, max_dmg, speed, p_stat, s_stat, p_bonus, s_bonus = stats

    # Apply rarity multiplier
    mult = RARITY_MULT.get(rarity, 1.0)
    min_dmg = int(min_dmg * mult)
    max_dmg = int(max_dmg * mult)
    p_bonus = int(p_bonus * mult)
    s_bonus = int(s_bonus * mult)

    # Add stats to item (crit is purely stat-based now - DEX for melee, WIS for caster)
    item["base_damage"] = {"min": min_dmg, "max": max_dmg}
    item["attack_speed"] = speed
    # Remove legacy crit_chance from weapons (now stat-based only)
    if "crit_chance" in item:
        del item["crit_chance"]
    # 6-STAT SYSTEM: STR, AGI, DEX, INT, WIS, VIT
    item["stat_bonuses"] = {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 0}
    item["stat_bonuses"][p_stat] = p_bonus
    item["stat_bonuses"][s_stat] = s_bonus

    return item


def add_armor_stats(item):
    """Add defense and stat bonuses to armor items."""
    item_type = item.get("item_type", "armor_chest")
    rarity = item.get("base_rarity", "rare").lower()
    theme = item.get("theme", "default").lower()

    # Get base stats
    base_defense, stat1, stat2 = ARMOR_STATS.get(item_type, (15, 3, 4))

    # Apply rarity multiplier
    mult = RARITY_MULT.get(rarity, 1.0)
    defense = int(base_defense * mult)
    stat1 = int(stat1 * mult)
    stat2 = int(stat2 * mult)

    # Determine stat focus based on theme/name
    # 6-STAT SYSTEM: STR, AGI, DEX, INT, WIS, VIT
    item_name = item.get("item_name", "").lower()
    item_id = item.get("item_id", "").lower()

    # Plate-themed (Tank/Plate DPS) - VIT/STR
    if any(x in item_name or x in item_id for x in ["plate", "steel", "iron", "helm", "crusader", "marine", "armor"]):
        p_stat, s_stat = "vit", "str"
    # Leather-themed (AGI DPS) - AGI/DEX for melee crit
    elif any(x in item_name or x in item_id for x in ["leather", "hood", "cloak", "shadow", "ghost", "ninja"]):
        p_stat, s_stat = "agi", "dex"
    # Cloth-themed (Caster) - INT/WIS for caster crit
    elif any(x in item_name or x in item_id for x in ["robe", "weave", "cloth", "mage", "wizard", "crown"]):
        p_stat, s_stat = "int", "wis"
    else:
        # Default based on theme
        if theme in ["dark_souls", "elden_ring", "halo"]:
            p_stat, s_stat = "vit", "str"
        elif theme in ["hollow_knight", "hades", "sekiro"]:
            p_stat, s_stat = "agi", "dex"
        else:
            p_stat, s_stat = "vit", "str"

    # Add stats
    item["defense"] = defense
    item["stat_bonuses"] = {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 0}
    item["stat_bonuses"][p_stat] = stat1
    item["stat_bonuses"][s_stat] = stat2

    return item


def add_accessory_stats(item):
    """Add effect values and stat bonuses to accessories."""
    rarity = item.get("base_rarity", "rare").lower()
    theme = item.get("theme", "default").lower()
    item_name = item.get("item_name", "").lower()
    item_id = item.get("item_id", "").lower()

    mult = RARITY_MULT.get(rarity, 1.0)

    # Get base accessory stats for theme
    base_stats = ACCESSORY_STATS.get(theme, ACCESSORY_STATS["default"])

    # Determine stat focus based on name
    # 6-STAT SYSTEM: STR, AGI, DEX, INT, WIS, VIT
    if any(x in item_name or x in item_id for x in ["ring", "band", "signet"]):
        # Rings tend toward specific stats
        if any(x in item_id for x in ["havel", "strength", "iron"]):
            p_stat, s_stat = "str", "vit"
        elif any(x in item_id for x in ["jordan", "mage", "arcane"]):
            p_stat, s_stat = "int", "wis"
        else:
            p_stat, s_stat = "agi", "dex"  # Default ring = assassin stats
    elif any(x in item_name or x in item_id for x in ["amulet", "necklace", "pendant", "medallion"]):
        # Necklaces tend toward HP/defense
        p_stat, s_stat = "vit", "str"
    elif any(x in item_name or x in item_id for x in ["accelerator", "device", "prism", "cube"]):
        # Tech items tend toward caster stats
        p_stat, s_stat = "int", "wis"
    else:
        # Default
        p_stat, s_stat = "vit", "str"

    # Calculate bonuses
    stat_bonus = int(base_stats.get("stat_bonus", 5) * mult)

    item["stat_bonuses"] = {"str": 0, "agi": 0, "dex": 0, "int": 0, "wis": 0, "vit": 0}
    item["stat_bonuses"][p_stat] = stat_bonus
    item["stat_bonuses"][s_stat] = int(stat_bonus * 0.6)

    # Add special bonuses based on accessory type
    if "hp_bonus" in base_stats:
        item["hp_bonus"] = int(base_stats["hp_bonus"] * mult)
    if "lifesteal" in base_stats:
        item["lifesteal"] = round(base_stats["lifesteal"] * mult, 3)
    if "cooldown_reduction" in base_stats:
        item["cooldown_reduction"] = round(base_stats["cooldown_reduction"] * mult, 3)
    if "movement_speed" in base_stats:
        item["movement_speed"] = round(base_stats["movement_speed"] * mult, 3)

    return item


def main():
    # Find items.json
    script_dir = Path(__file__).parent
    items_path = script_dir.parent / "backend" / "data" / "items.json"

    if not items_path.exists():
        print(f"Error: {items_path} not found")
        return

    # Load items
    with open(items_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    items = data.get("items", [])
    weapons_updated = 0
    armor_updated = 0
    accessories_updated = 0

    effects_fixed = 0
    for item in items:
        item_type = item.get("item_type", "")

        if item_type == "weapon":
            add_weapon_stats(item)
            # Fix effects (move lifesteal from light to heavy weapons)
            original_effects = str(item.get("effects", {}))
            fix_weapon_effects(item)
            if str(item.get("effects", {})) != original_effects:
                effects_fixed += 1
            weapons_updated += 1
        elif item_type in ["armor_head", "armor_chest", "armor_hands", "armor_legs", "armor_feet", "shield", "cape"]:
            add_armor_stats(item)
            armor_updated += 1
        elif item_type == "accessory":
            add_accessory_stats(item)
            accessories_updated += 1

    # Update changelog
    changelog = data.get("_changelog", "")
    changelog = f"v2.2.0: Differentiated weapon types (dagger/katana/rapier), added staff scaling, fixed lifesteal on tank weapons. {changelog}"
    data["_changelog"] = changelog

    # Write back
    with open(items_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"Updated {items_path}")
    print(f"  Weapons: {weapons_updated}")
    print(f"  Armor: {armor_updated}")
    print(f"  Accessories: {accessories_updated}")
    print(f"  Effects fixed: {effects_fixed}")
    print(f"  Total: {weapons_updated + armor_updated + accessories_updated}")


if __name__ == "__main__":
    main()
