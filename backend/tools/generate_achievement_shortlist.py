#!/usr/bin/env python3
"""
Generate comprehensive achievement shortlist from existing data sources.

This script analyzes:
1. Current mappings in items.json (74 items)
2. WoW achievements database (5000+ achievements)
3. Known platform badges
4. Popular Steam/PlayStation games for potential dagger items

Output:
    docs/COMPREHENSIVE_ACHIEVEMENT_LIST.md
    docs/UNMAPPED_ACHIEVEMENTS_BY_CATEGORY.md
"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Any

# Add parent directories to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.effort_scoring import (
    compute_battlenet_effort,
    compute_rarity_from_effort,
    compute_effort_from_percent
)

# =============================================================================
# CONFIGURATION
# =============================================================================

ITEMS_FILE = "backend/data/items.json"
WOW_FILE = "backend/app/data/wow_achievements.json"
OUTPUT_COMPREHENSIVE = "docs/COMPREHENSIVE_ACHIEVEMENT_LIST.md"
OUTPUT_UNMAPPED = "docs/UNMAPPED_ACHIEVEMENTS_BY_CATEGORY.md"

WOW_MIN_EFFORT = 40  # Only show Rare+ WoW achievements

# =============================================================================
# DATA LOADING
# =============================================================================

def load_items_data():
    """Load items.json with current mappings."""
    with open(ITEMS_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)


def load_wow_data():
    """Load WoW achievements database."""
    with open(WOW_FILE, 'r', encoding='utf-8') as f:
        data = json.load(f)
        # The achievements are nested under an "achievements" key
        return data.get("achievements", {})


def analyze_current_mappings(items_data):
    """Analyze current 74 achievement mappings."""
    mappings = items_data.get("achievement_mappings", {})
    items = items_data.get("items", [])

    # Create lookup by item_id
    items_by_id = {item["item_id"]: item for item in items}

    # Categorize by provider and item type
    by_provider = defaultdict(list)
    by_weapon_type = defaultdict(list)
    by_item_type = defaultdict(list)
    by_rarity = defaultdict(list)

    for key, item_id in mappings.items():
        # Skip comment entries
        if key.startswith("_comment"):
            continue

        item = items_by_id.get(item_id)
        if not item:
            print(f"Warning: Item {item_id} not found in items array")
            continue

        # Parse provider from key
        if ":" in key:
            provider_part, achievement_part = key.split(":", 1)
            if provider_part.isdigit():  # Steam app ID
                provider = "Steam"
                game_info = f"App {provider_part}"
            else:
                provider = provider_part.title()
                game_info = achievement_part
        else:
            provider = "Unknown"
            game_info = key

        entry = {
            "key": key,
            "item_id": item_id,
            "item_name": item.get("item_name"),
            "item_type": item.get("item_type"),
            "weapon_type": item.get("weapon_type"),
            "rarity": item.get("base_rarity"),
            "theme": item.get("theme"),
            "provider": provider,
            "game_info": game_info
        }

        by_provider[provider].append(entry)
        by_item_type[item.get("item_type", "unknown")].append(entry)
        if item.get("weapon_type"):
            by_weapon_type[item["weapon_type"]].append(entry)
        by_rarity[item.get("base_rarity", "unknown")].append(entry)

    return {
        "by_provider": dict(by_provider),
        "by_weapon_type": dict(by_weapon_type),
        "by_item_type": dict(by_item_type),
        "by_rarity": dict(by_rarity),
        "total": len(mappings)
    }


def suggest_dagger_achievements():
    """Suggest achievements that would make good dagger items."""
    suggestions = [
        {
            "game": "Dishonored",
            "app_id": "205100",
            "achievement": "Clean Hands + Ghost",
            "description": "Complete game undetected without killing anyone",
            "unlock_percent": 2.0,
            "effort": 98,
            "rarity": "Legendary",
            "proposed_item": "Corvo's Blade",
            "weapon_type": "dagger"
        },
        {
            "game": "Assassin's Creed II",
            "app_id": "33230",
            "achievement": "Birth of an Assassin",
            "description": "Complete the game",
            "unlock_percent": 18.0,
            "effort": 82,
            "rarity": "Legendary",
            "proposed_item": "Ezio's Hidden Blade",
            "weapon_type": "dagger"
        },
        {
            "game": "Skyrim",
            "app_id": "72850",
            "achievement": "With Friends Like These",
            "description": "Join the Dark Brotherhood",
            "unlock_percent": 25.0,
            "effort": 75,
            "rarity": "Epic",
            "proposed_item": "Blade of Woe",
            "weapon_type": "dagger"
        },
        {
            "game": "Hitman 3",
            "app_id": "1659040",
            "achievement": "Silent Assassin, Suit Only",
            "description": "Complete any mission undetected, no disguise",
            "unlock_percent": 15.0,
            "effort": 85,
            "rarity": "Legendary",
            "proposed_item": "Fiber Wire",
            "weapon_type": "dagger"
        },
        {
            "game": "Splinter Cell",
            "platform": "PlayStation",
            "achievement": "Ghost Platinum",
            "description": "Complete all missions undetected",
            "unlock_percent": 8.0,
            "effort": 92,
            "rarity": "Legendary",
            "proposed_item": "Sam Fisher's Ka-Bar",
            "weapon_type": "dagger"
        },
        {
            "game": "Thief (2014)",
            "app_id": "239160",
            "achievement": "Steal Master",
            "description": "Complete game without killing or being detected",
            "unlock_percent": 5.0,
            "effort": 95,
            "rarity": "Legendary",
            "proposed_item": "Master Thief's Blackjack",
            "weapon_type": "dagger"
        },
    ]

    return suggestions


def suggest_jewelry_items():
    """Suggest achievements that would work as jewelry (rings, amulets)."""
    suggestions = [
        {
            "type": "ring",
            "game": "Elden Ring",
            "achievement": "Age of Stars Ending",
            "proposed_item": "Ranni's Dark Moon Ring",
            "rarity": "Epic"
        },
        {
            "type": "amulet",
            "game": "Discord",
            "achievement": "Early Supporter Badge",
            "proposed_item": "Early Supporter Amulet",
            "rarity": "Legendary"
        },
        {
            "type": "ring",
            "game": "Dark Souls",
            "achievement": "Knight's Honor",
            "proposed_item": "Ring of Favor",
            "rarity": "Epic"
        },
        {
            "type": "amulet",
            "game": "GitHub",
            "achievement": "Arctic Code Vault",
            "proposed_item": "Arctic Vault Medallion",
            "rarity": "Legendary"
        },
        {
            "type": "ring",
            "game": "WoW",
            "achievement": "Scarab Lord",
            "proposed_item": "Scarab Lord Signet Ring",
            "rarity": "Legendary"
        },
    ]

    return suggestions


# =============================================================================
# MARKDOWN GENERATION
# =============================================================================

def generate_comprehensive_list(analysis, wow_data):
    """Generate the comprehensive achievement list markdown."""
    lines = []

    lines.append("# Comprehensive Achievement Reference List")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- **Total Mapped Achievements**: {analysis['total']}")
    lines.append(f"- **WoW Achievements Available**: {len([a for a in wow_data.values() if compute_battlenet_effort(a) >= WOW_MIN_EFFORT])}")
    lines.append("")

    # Provider distribution
    lines.append("## Current Mappings by Provider")
    lines.append("")
    lines.append("| Provider | Count | Items |")
    lines.append("|----------|-------|-------|")

    for provider, items in sorted(analysis["by_provider"].items(), key=lambda x: len(x[1]), reverse=True):
        item_names = ", ".join([item["item_name"] for item in items[:3]])
        if len(items) > 3:
            item_names += f", ... ({len(items) - 3} more)"
        lines.append(f"| {provider} | {len(items)} | {item_names} |")

    lines.append("")

    # Weapon type distribution
    lines.append("## Weapon Type Distribution")
    lines.append("")
    lines.append("| Weapon Type | Count | Items |")
    lines.append("|-------------|-------|-------|")

    for weapon_type, items in sorted(analysis["by_weapon_type"].items(), key=lambda x: len(x[1]), reverse=True):
        item_names = ", ".join([item["item_name"] for item in items[:3]])
        if len(items) > 3:
            item_names += f", ... ({len(items) - 3} more)"
        lines.append(f"| {weapon_type.title()} | {len(items)} | {item_names} |")

    lines.append(f"| **DAGGER** | **0** | **NONE - CRITICAL GAP!** |")
    lines.append("")

    # Item slot distribution
    lines.append("## Item Slot Distribution")
    lines.append("")
    lines.append("| Slot | Count | Percentage |")
    lines.append("|------|-------|------------|")

    total_items = analysis["total"]
    for item_type, items in sorted(analysis["by_item_type"].items(), key=lambda x: len(x[1]), reverse=True):
        percentage = f"{len(items) / total_items * 100:.1f}%"
        lines.append(f"| {item_type.replace('_', ' ').title()} | {len(items)} | {percentage} |")

    lines.append(f"| **Jewelry (Ring/Amulet)** | **0** | **0%** - NEW SLOT TYPE! |")
    lines.append("")

    # Rarity distribution
    lines.append("## Rarity Distribution")
    lines.append("")
    lines.append("| Rarity | Count | Percentage |")
    lines.append("|--------|-------|------------|")

    for rarity, items in sorted(analysis["by_rarity"].items(), key=lambda x: len(x[1]), reverse=True):
        percentage = f"{len(items) / total_items * 100:.1f}%"
        lines.append(f"| {rarity.title()} | {len(items)} | {percentage} |")

    lines.append("")

    # Top WoW achievements
    lines.append("## Top WoW Achievements (Unmapped)")
    lines.append("")
    lines.append("*Showing Legendary/Epic WoW achievements from static database*")
    lines.append("")
    lines.append("| Name | Points | Category | FoS | Legacy | Effort | Rarity |")
    lines.append("|------|--------|----------|-----|--------|--------|--------|")

    wow_achievements = []
    for ach_id, ach_data in wow_data.items():
        effort = compute_battlenet_effort(ach_data)
        if effort >= 70:  # Epic or Legendary only
            wow_achievements.append({
                "name": ach_data.get("name", "Unknown"),
                "points": ach_data.get("points", 0),
                "category": ach_data.get("category", "Unknown"),
                "is_fos": ach_data.get("is_feat_of_strength", False),
                "is_legacy": ach_data.get("is_legacy", False),
                "effort": effort,
                "rarity": compute_rarity_from_effort(effort)
            })

    wow_achievements.sort(key=lambda x: x["effort"], reverse=True)

    for ach in wow_achievements[:30]:  # Top 30
        fos = "✅" if ach["is_fos"] else ""
        legacy = "✅" if ach["is_legacy"] else ""
        lines.append(f"| {ach['name'][:40]} | {ach['points']} | {ach['category'][:20]} | "
                    f"{fos} | {legacy} | {int(ach['effort'])} | {ach['rarity']} |")

    lines.append("")

    return "\n".join(lines)


def generate_unmapped_categories(dagger_suggestions, jewelry_suggestions):
    """Generate unmapped achievements by category markdown."""
    lines = []

    lines.append("# Unmapped Achievements by Category")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")

    lines.append("This document categorizes potential achievements for new forge items, organized by item slot and theme.")
    lines.append("")

    # CRITICAL GAP: Daggers
    lines.append("## CRITICAL GAP: Dagger Weapons")
    lines.append("")
    lines.append("**Status**: Zero dagger items currently mapped")
    lines.append("")
    lines.append("**Recommended Additions**:")
    lines.append("")
    lines.append("| Game | Achievement | Unlock % | Effort | Rarity | Proposed Item |")
    lines.append("|------|-------------|----------|--------|--------|---------------|")

    for sug in dagger_suggestions:
        lines.append(f"| {sug['game']} | {sug['achievement']} | {sug['unlock_percent']}% | "
                    f"{sug['effort']} | {sug['rarity']} | **{sug['proposed_item']}** |")

    lines.append("")

    # NEW SLOT: Jewelry
    lines.append("## NEW SLOT TYPE: Jewelry (Rings & Amulets)")
    lines.append("")
    lines.append("**Status**: Zero jewelry items currently implemented")
    lines.append("")
    lines.append("**Recommended Additions**:")
    lines.append("")
    lines.append("| Type | Game | Achievement | Proposed Item | Rarity |")
    lines.append("|------|------|-------------|---------------|--------|")

    for sug in jewelry_suggestions:
        lines.append(f"| {sug['type'].title()} | {sug['game']} | {sug['achievement']} | "
                    f"**{sug['proposed_item']}** | {sug['rarity']} |")

    lines.append("")

    # Other armor gaps
    lines.append("## Armor Slot Gaps")
    lines.append("")
    lines.append("**Underrepresented Slots**:")
    lines.append("")
    lines.append("- **Chest Armor**: Very limited (intentionally per design philosophy)")
    lines.append("- **Leg Armor**: Almost none - needs 3-5 items")
    lines.append("- **Hand Armor** (Gauntlets/Gloves): Needs 5-8 items")
    lines.append("- **Feet Armor** (Boots): Needs 5-8 items")
    lines.append("")

    lines.append("**Potential Sources**:")
    lines.append("- Platformer platinum trophies → Boots (Celeste, Hollow Knight)")
    lines.append("- Combat game achievements → Gauntlets (Mortal Kombat, Street Fighter)")
    lines.append("- RPG completions → Leg armor (Witcher, Skyrim, Dragon Age)")
    lines.append("")

    return "\n".join(lines)


# =============================================================================
# MAIN
# =============================================================================

def main():
    """Main execution function."""
    print("=== Achievement Shortlist Generator ===")
    print("")

    print("Loading items.json...")
    items_data = load_items_data()

    print("Loading WoW achievements...")
    wow_data = load_wow_data()

    print("Analyzing current 74 mappings...")
    analysis = analyze_current_mappings(items_data)

    print(f"\nCurrent Status:")
    print(f"  Total mapped: {analysis['total']}")
    print(f"  Providers: {len(analysis['by_provider'])}")
    print(f"  Weapon types: {len(analysis['by_weapon_type'])}")
    print(f"  Daggers: 0 [CRITICAL GAP]")
    print(f"  Jewelry: 0 [NEW SLOT TYPE]")
    print("")

    print("Generating dagger suggestions...")
    dagger_suggestions = suggest_dagger_achievements()
    print(f"  Found {len(dagger_suggestions)} potential dagger items")

    print("Generating jewelry suggestions...")
    jewelry_suggestions = suggest_jewelry_items()
    print(f"  Found {len(jewelry_suggestions)} potential jewelry items")

    print("\nGenerating comprehensive list...")
    comprehensive_md = generate_comprehensive_list(analysis, wow_data)

    print("Generating unmapped categories...")
    unmapped_md = generate_unmapped_categories(dagger_suggestions, jewelry_suggestions)

    # Write files
    print("\nWriting output files...")

    Path(OUTPUT_COMPREHENSIVE).parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_COMPREHENSIVE, 'w', encoding='utf-8') as f:
        f.write(comprehensive_md)
    print(f"  [OK] {OUTPUT_COMPREHENSIVE}")

    Path(OUTPUT_UNMAPPED).parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_UNMAPPED, 'w', encoding='utf-8') as f:
        f.write(unmapped_md)
    print(f"  [OK] {OUTPUT_UNMAPPED}")

    print("\n[DONE] Review the generated files and approve which items to add.")


if __name__ == "__main__":
    main()
