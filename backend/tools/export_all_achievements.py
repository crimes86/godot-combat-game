#!/usr/bin/env python3
"""
Export all achievements across all providers to markdown format.

This script generates a comprehensive achievement reference list showing:
1. Steam achievements (from synced user data)
2. Xbox achievements (from synced user data)
3. Battle.net WoW achievements (from static database)
4. PlayStation trophies (known platinums)
5. Discord badges
6. GitHub badges
7. Roblox tenure badges

Usage:
    python backend/tools/export_all_achievements.py

Output:
    docs/COMPREHENSIVE_ACHIEVEMENT_LIST.md
"""

import sys
import os
import json
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any
from collections import defaultdict

# Add parent directories to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.models import Achievement, AchievementCredit, User, ProviderAccount
from app.services.effort_scoring import (
    compute_steam_effort,
    compute_battlenet_effort,
    compute_xbox_effort,
    compute_rarity_from_effort,
    compute_effort_from_percent
)
# =============================================================================
# CONFIGURATION
# =============================================================================

OUTPUT_FILE = "docs/COMPREHENSIVE_ACHIEVEMENT_LIST.md"
WOW_ACHIEVEMENTS_FILE = "backend/app/data/wow_achievements.json"
ITEMS_FILE = "backend/data/items.json"

# Filter WoW achievements by minimum prestige level
WOW_MIN_EFFORT_SCORE = 40  # Only include Rare+ (40+) WoW achievements

# Known PlayStation Platinum trophies from major games
PLAYSTATION_PLATINUMS = [
    {"game": "Bloodborne", "trophy": "Platinum Trophy", "earn_rate": 6.0, "mapped": True},
    {"game": "Demon's Souls", "trophy": "Platinum Trophy", "earn_rate": 8.0, "mapped": True},
    {"game": "Dark Souls III", "trophy": "The Dark Soul", "earn_rate": 5.3, "mapped": False},
    {"game": "Elden Ring", "trophy": "Elden Lord", "earn_rate": 10.5, "mapped": True},
    {"game": "God of War (2018)", "trophy": "Father and Son", "earn_rate": 15.0, "mapped": True},
    {"game": "Ghost of Tsushima", "trophy": "Mono no Aware", "earn_rate": 12.0, "mapped": True},
    {"game": "Returnal", "trophy": "Helios", "earn_rate": 4.5, "mapped": True},
    {"game": "Spider-Man", "trophy": "Be Greater", "earn_rate": 18.0, "mapped": True},
    {"game": "Horizon Zero Dawn", "trophy": "All Trophies Obtained", "earn_rate": 14.0, "mapped": False},
    {"game": "The Last of Us Part II", "trophy": "It Can't Be for Nothing", "earn_rate": 20.0, "mapped": False},
    {"game": "Sekiro", "trophy": "Immortal Severance", "earn_rate": 6.8, "mapped": True},
    {"game": "Hollow Knight", "trophy": "Embrace the Void", "earn_rate": 3.2, "mapped": False},
]

# Discord badges
DISCORD_BADGES = [
    {"name": "Early Supporter", "description": "Pre-Oct 2018 Nitro (unobtainable)", "effort": 90, "mapped": True},
    {"name": "Discord Nitro", "description": "Active Nitro subscriber", "effort": 25, "mapped": True},
    {"name": "HypeSquad Events", "description": "Event attendance", "effort": 35, "mapped": True},
    {"name": "Bug Hunter Level 2", "description": "Many bugs reported", "effort": 70, "mapped": True},
    {"name": "Partnered Server Owner", "description": "Owns partnered server", "effort": 60, "mapped": True},
    {"name": "Discord Employee", "description": "Current/former staff", "effort": 95, "mapped": False},
    {"name": "Verified Bot Developer", "description": "Owns verified bot", "effort": 50, "mapped": False},
]

# GitHub badges
GITHUB_BADGES = [
    {"name": "Starstruck", "tier": "Gold", "description": "Created project with 1000+ stars", "effort": 75, "mapped": True},
    {"name": "Arctic Code Vault Contributor", "tier": "N/A", "description": "2020 Arctic preservation (legacy)", "effort": 95, "mapped": True},
    {"name": "Mars 2020 Contributor", "tier": "N/A", "description": "Code on Mars rover (legacy)", "effort": 95, "mapped": True},
    {"name": "Pull Shark", "tier": "Gold", "description": "Many merged PRs", "effort": 50, "mapped": True},
    {"name": "Galaxy Brain", "tier": "Gold", "description": "Helpful Q&A answers", "effort": 60, "mapped": True},
    {"name": "YOLO", "tier": "Bronze", "description": "Merged without review", "effort": 30, "mapped": True},
    {"name": "Quickdraw", "tier": "Silver", "description": "Fast issue resolution", "effort": 45, "mapped": False},
    {"name": "Pair Extraordinaire", "tier": "Silver", "description": "Co-authored commits", "effort": 40, "mapped": False},
]

# Roblox tenure badges
ROBLOX_BADGES = [
    {"years": "10+", "name": "Veteran Badge", "effort": 85, "mapped": True},
    {"years": "7+", "name": "Classic Badge", "effort": 65, "mapped": True},
    {"years": "5+", "name": "Builder Badge", "effort": 45, "mapped": True},
    {"years": "3+", "name": "Established Badge", "effort": 30, "mapped": False},
]

# =============================================================================
# DATABASE QUERY FUNCTIONS
# =============================================================================

def get_db_session():
    """Create database session."""
    import os
    from dotenv import load_dotenv
    load_dotenv()

    db_url = os.getenv("DATABASE_URL", "sqlite:///./socialauth.db")
    connect_args = {"check_same_thread": False} if db_url.startswith("sqlite") else {}
    engine = create_engine(db_url, connect_args=connect_args)
    SessionLocal = sessionmaker(bind=engine)
    return SessionLocal()


def export_steam_achievements(session) -> List[Dict[str, Any]]:
    """Export Steam achievements from database."""
    results = []

    # Query all Steam achievements
    steam_achievements = session.query(Achievement).filter(
        Achievement.app_id.isnot(None),
        Achievement.api_name.isnot(None)
    ).all()

    for ach in steam_achievements:
        effort = compute_steam_effort(ach.app_id, ach.api_name, ach.percent or 50.0)
        rarity = compute_rarity_from_effort(effort)

        results.append({
            "game": ach.name or f"App {ach.app_id}",
            "app_id": ach.app_id,
            "achievement": ach.display_name or ach.api_name,
            "api_name": ach.api_name,
            "unlock_percent": f"{ach.percent:.1f}%" if ach.percent else "Unknown",
            "effort_score": int(effort),
            "rarity": rarity,
            "mapped": False  # Will be updated in audit phase
        })

    # Sort by effort score descending
    results.sort(key=lambda x: x["effort_score"], reverse=True)
    return results


def export_xbox_achievements(session) -> List[Dict[str, Any]]:
    """Export Xbox achievements from database."""
    results = []

    # Query Xbox achievement credits with achievement data
    xbox_credits = session.query(AchievementCredit, Achievement).join(
        Achievement, AchievementCredit.achievement_id == Achievement.id
    ).filter(
        AchievementCredit.provider_name == "xbox",
        AchievementCredit.is_original_claim == True
    ).all()

    for credit, ach in xbox_credits:
        # Xbox achievements don't have app_id in the same way, use display name
        # Gamerscore would be in profile_data if we had it; default to 25 for now
        gamerscore = 25  # Default
        effort = compute_xbox_effort(gamerscore, ach.percent)
        rarity = compute_rarity_from_effort(effort)

        results.append({
            "game": ach.name or "Xbox Game",
            "achievement": ach.display_name or ach.api_name,
            "gamerscore": gamerscore,
            "unlock_percent": f"{ach.percent:.1f}%" if ach.percent else "Unknown",
            "effort_score": int(effort),
            "rarity": rarity,
            "mapped": False
        })

    results.sort(key=lambda x: x["effort_score"], reverse=True)
    return results


def load_wow_achievements() -> List[Dict[str, Any]]:
    """Load WoW achievements from static JSON database."""
    results = []

    if not os.path.exists(WOW_ACHIEVEMENTS_FILE):
        print(f"Warning: WoW achievements file not found: {WOW_ACHIEVEMENTS_FILE}")
        return results

    with open(WOW_ACHIEVEMENTS_FILE, 'r', encoding='utf-8') as f:
        wow_data = json.load(f)

    # wow_data is a dict of achievement_id -> achievement_data
    for ach_id, ach_data in wow_data.items():
        effort = compute_battlenet_effort(ach_data)

        # Filter: only include achievements with effort >= 40 (Rare+)
        if effort < WOW_MIN_EFFORT_SCORE:
            continue

        rarity = compute_rarity_from_effort(effort)

        results.append({
            "achievement_id": ach_id,
            "name": ach_data.get("name", "Unknown"),
            "points": ach_data.get("points", 0),
            "category": ach_data.get("category", "Unknown"),
            "is_fos": ach_data.get("is_feat_of_strength", False),
            "is_legacy": ach_data.get("is_legacy", False),
            "effort_score": int(effort),
            "rarity": rarity,
            "mapped": False
        })

    # Sort by effort score descending
    results.sort(key=lambda x: x["effort_score"], reverse=True)
    return results


def load_mapped_achievements() -> Dict[str, str]:
    """Load achievement mappings from items.json."""
    if not os.path.exists(ITEMS_FILE):
        print(f"Warning: items.json not found: {ITEMS_FILE}")
        return {}

    with open(ITEMS_FILE, 'r', encoding='utf-8') as f:
        items_data = json.load(f)

    mappings = items_data.get("achievement_mappings", {})
    return mappings


def mark_mapped_achievements(achievements_by_provider: Dict[str, List], mappings: Dict[str, str]):
    """Mark achievements that are already mapped to items."""
    for key, item_id in mappings.items():
        provider, achievement = key.split(":", 1) if ":" in key else (key, "")

        # Handle Steam achievements (format: app_id:api_name)
        if provider.isdigit():  # Steam app ID
            for ach in achievements_by_provider.get("steam", []):
                if ach["app_id"] == provider and ach["api_name"] == achievement:
                    ach["mapped"] = True
                    ach["item_id"] = item_id
                    break

        # Handle Xbox
        elif provider == "xbox":
            for ach in achievements_by_provider.get("xbox", []):
                if achievement.upper() in ach["achievement"].upper():
                    ach["mapped"] = True
                    ach["item_id"] = item_id
                    break

        # Handle Battle.net (WoW)
        elif provider == "battlenet":
            for ach in achievements_by_provider.get("battlenet", []):
                if achievement.upper() in ach["name"].upper():
                    ach["mapped"] = True
                    ach["item_id"] = item_id
                    break

        # Handle platform badges
        elif provider in ["discord", "github", "roblox", "psn"]:
            if provider in achievements_by_provider:
                for ach in achievements_by_provider[provider]:
                    if "mapped" in ach:
                        # Already set from static data
                        pass

# =============================================================================
# MARKDOWN GENERATION
# =============================================================================

def generate_markdown(achievements_by_provider: Dict[str, List], mappings: Dict) -> str:
    """Generate markdown document."""
    lines = []

    lines.append("# Comprehensive Achievement Reference List")
    lines.append("")
    lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    lines.append("This document lists all achievements across all providers with their effort scores and mapping status.")
    lines.append("")

    # Summary statistics
    total_achievements = sum(len(achs) for achs in achievements_by_provider.values())
    total_mapped = len(mappings)

    lines.append("## Summary Statistics")
    lines.append("")
    lines.append(f"- **Total Achievements**: {total_achievements}")
    lines.append(f"- **Total Mapped**: {total_mapped}")
    lines.append(f"- **Unmapped**: {total_achievements - total_mapped}")
    lines.append(f"- **Coverage**: {total_mapped / total_achievements * 100:.1f}%" if total_achievements > 0 else "0%")
    lines.append("")

    # Provider breakdown
    lines.append("### Provider Breakdown")
    lines.append("")
    lines.append("| Provider | Total | Mapped | Unmapped | Coverage |")
    lines.append("|----------|-------|--------|----------|----------|")

    for provider, achs in achievements_by_provider.items():
        total = len(achs)
        mapped = sum(1 for a in achs if a.get("mapped", False))
        unmapped = total - mapped
        coverage = f"{mapped / total * 100:.1f}%" if total > 0 else "0%"
        lines.append(f"| {provider.title()} | {total} | {mapped} | {unmapped} | {coverage} |")

    lines.append("")

    # =============================================================================
    # STEAM ACHIEVEMENTS
    # =============================================================================
    if "steam" in achievements_by_provider and achievements_by_provider["steam"]:
        lines.append("## Steam Achievements")
        lines.append("")
        lines.append("| Game | App ID | Achievement | API Name | Unlock % | Effort | Rarity | Status |")
        lines.append("|------|--------|-------------|----------|----------|--------|--------|--------|")

        for ach in achievements_by_provider["steam"][:100]:  # Limit to top 100
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"
            item_id = f" ({ach.get('item_id', '')})" if ach.get("mapped") else ""

            lines.append(f"| {ach['game'][:30]} | {ach['app_id']} | {ach['achievement'][:40]} | "
                        f"`{ach['api_name']}` | {ach['unlock_percent']} | {ach['effort_score']} | "
                        f"{ach['rarity']} | {status}{item_id} |")

        if len(achievements_by_provider["steam"]) > 100:
            lines.append(f"| ... | ... | ... | ... | ... | ... | ... | *({len(achievements_by_provider['steam']) - 100} more)* |")

        lines.append("")

    # =============================================================================
    # XBOX ACHIEVEMENTS
    # =============================================================================
    if "xbox" in achievements_by_provider and achievements_by_provider["xbox"]:
        lines.append("## Xbox Achievements")
        lines.append("")
        lines.append("| Game | Achievement | Gamerscore | Unlock % | Effort | Rarity | Status |")
        lines.append("|------|-------------|------------|----------|--------|--------|--------|")

        for ach in achievements_by_provider["xbox"]:
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"
            item_id = f" ({ach.get('item_id', '')})" if ach.get("mapped") else ""

            lines.append(f"| {ach['game'][:30]} | {ach['achievement'][:40]} | {ach['gamerscore']} | "
                        f"{ach['unlock_percent']} | {ach['effort_score']} | {ach['rarity']} | {status}{item_id} |")

        lines.append("")

    # =============================================================================
    # BATTLE.NET (WoW) ACHIEVEMENTS
    # =============================================================================
    if "battlenet" in achievements_by_provider and achievements_by_provider["battlenet"]:
        lines.append("## Battle.net (World of Warcraft) Achievements")
        lines.append("")
        lines.append(f"*Filtered to show only Rare+ achievements (effort ≥ {WOW_MIN_EFFORT_SCORE})*")
        lines.append("")
        lines.append("| Achievement Name | ID | Points | Category | FoS | Legacy | Effort | Rarity | Status |")
        lines.append("|------------------|----|----|----------|-----|--------|--------|--------|--------|")

        for ach in achievements_by_provider["battlenet"][:50]:  # Limit to top 50
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"
            item_id = f" ({ach.get('item_id', '')})" if ach.get("mapped") else ""
            fos = "✅" if ach["is_fos"] else ""
            legacy = "✅" if ach["is_legacy"] else ""

            lines.append(f"| {ach['name'][:40]} | {ach['achievement_id']} | {ach['points']} | "
                        f"{ach['category'][:20]} | {fos} | {legacy} | {ach['effort_score']} | "
                        f"{ach['rarity']} | {status}{item_id} |")

        if len(achievements_by_provider["battlenet"]) > 50:
            lines.append(f"| ... | ... | ... | ... | ... | ... | ... | ... | *({len(achievements_by_provider['battlenet']) - 50} more)* |")

        lines.append("")

    # =============================================================================
    # PLAYSTATION TROPHIES
    # =============================================================================
    if "playstation" in achievements_by_provider:
        lines.append("## PlayStation Trophies (Known Platinums)")
        lines.append("")
        lines.append("| Game | Trophy | Type | Earn Rate | Effort | Rarity | Status |")
        lines.append("|------|--------|------|-----------|--------|--------|--------|")

        for ach in achievements_by_provider["playstation"]:
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"

            lines.append(f"| {ach['game']} | {ach['trophy']} | Platinum | "
                        f"{ach['earn_rate']:.1f}% | {ach['effort_score']} | {ach['rarity']} | {status} |")

        lines.append("")

    # =============================================================================
    # DISCORD BADGES
    # =============================================================================
    if "discord" in achievements_by_provider:
        lines.append("## Discord Badges")
        lines.append("")
        lines.append("| Badge | Description | Effort | Rarity | Status |")
        lines.append("|-------|-------------|--------|--------|--------|")

        for ach in achievements_by_provider["discord"]:
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"

            lines.append(f"| {ach['name']} | {ach['description']} | {ach['effort_score']} | "
                        f"{ach['rarity']} | {status} |")

        lines.append("")

    # =============================================================================
    # GITHUB BADGES
    # =============================================================================
    if "github" in achievements_by_provider:
        lines.append("## GitHub Badges")
        lines.append("")
        lines.append("| Badge | Tier | Description | Effort | Rarity | Status |")
        lines.append("|-------|------|-------------|--------|--------|--------|")

        for ach in achievements_by_provider["github"]:
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"

            lines.append(f"| {ach['name']} | {ach['tier']} | {ach['description'][:40]} | "
                        f"{ach['effort_score']} | {ach['rarity']} | {status} |")

        lines.append("")

    # =============================================================================
    # ROBLOX TENURE BADGES
    # =============================================================================
    if "roblox" in achievements_by_provider:
        lines.append("## Roblox Tenure Badges")
        lines.append("")
        lines.append("| Tenure | Badge | Effort | Rarity | Status |")
        lines.append("|--------|-------|--------|--------|--------|")

        for ach in achievements_by_provider["roblox"]:
            status = "✅ MAPPED" if ach.get("mapped") else "❌ NOT MAPPED"

            lines.append(f"| {ach['years']} years | {ach['name']} | {ach['effort_score']} | "
                        f"{ach['rarity']} | {status} |")

        lines.append("")

    return "\n".join(lines)


# =============================================================================
# MAIN
# =============================================================================

def main():
    """Main execution function."""
    print("=== Comprehensive Achievement Export ===")
    print("")

    # Create database session
    print("Connecting to database...")
    session = get_db_session()

    # Export achievements by provider
    achievements_by_provider = {}

    print("Exporting Steam achievements...")
    steam_achs = export_steam_achievements(session)
    if steam_achs:
        achievements_by_provider["steam"] = steam_achs
        print(f"  Found {len(steam_achs)} Steam achievements")

    print("Exporting Xbox achievements...")
    xbox_achs = export_xbox_achievements(session)
    if xbox_achs:
        achievements_by_provider["xbox"] = xbox_achs
        print(f"  Found {len(xbox_achs)} Xbox achievements")

    print("Loading Battle.net (WoW) achievements...")
    wow_achs = load_wow_achievements()
    if wow_achs:
        achievements_by_provider["battlenet"] = wow_achs
        print(f"  Found {len(wow_achs)} WoW achievements (Rare+)")

    print("Loading platform badges...")

    # PlayStation
    psn_achs = []
    for trophy in PLAYSTATION_PLATINUMS:
        effort = compute_effort_from_percent(trophy["earn_rate"])
        psn_achs.append({
            "game": trophy["game"],
            "trophy": trophy["trophy"],
            "earn_rate": trophy["earn_rate"],
            "effort_score": int(effort),
            "rarity": compute_rarity_from_effort(effort),
            "mapped": trophy["mapped"]
        })
    achievements_by_provider["playstation"] = psn_achs
    print(f"  Found {len(psn_achs)} PlayStation platinums")

    # Discord
    discord_achs = []
    for badge in DISCORD_BADGES:
        discord_achs.append({
            "name": badge["name"],
            "description": badge["description"],
            "effort_score": badge["effort"],
            "rarity": compute_rarity_from_effort(badge["effort"]),
            "mapped": badge["mapped"]
        })
    achievements_by_provider["discord"] = discord_achs
    print(f"  Found {len(discord_achs)} Discord badges")

    # GitHub
    github_achs = []
    for badge in GITHUB_BADGES:
        github_achs.append({
            "name": badge["name"],
            "tier": badge["tier"],
            "description": badge["description"],
            "effort_score": badge["effort"],
            "rarity": compute_rarity_from_effort(badge["effort"]),
            "mapped": badge["mapped"]
        })
    achievements_by_provider["github"] = github_achs
    print(f"  Found {len(github_achs)} GitHub badges")

    # Roblox
    roblox_achs = []
    for badge in ROBLOX_BADGES:
        roblox_achs.append({
            "years": badge["years"],
            "name": badge["name"],
            "effort_score": badge["effort"],
            "rarity": compute_rarity_from_effort(badge["effort"]),
            "mapped": badge["mapped"]
        })
    achievements_by_provider["roblox"] = roblox_achs
    print(f"  Found {len(roblox_achs)} Roblox tenure badges")

    # Load mapped achievements
    print("\nLoading achievement mappings from items.json...")
    mappings = load_mapped_achievements()
    print(f"  Found {len(mappings)} mapped achievements")

    # Mark mapped achievements
    print("Marking mapped achievements...")
    mark_mapped_achievements(achievements_by_provider, mappings)

    # Generate markdown
    print("\nGenerating markdown document...")
    markdown_content = generate_markdown(achievements_by_provider, mappings)

    # Write to file
    output_path = Path(OUTPUT_FILE)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(markdown_content)

    print(f"\n✅ Successfully exported to: {OUTPUT_FILE}")
    print("")

    # Print summary
    total_achievements = sum(len(achs) for achs in achievements_by_provider.values())
    total_mapped = len(mappings)

    print("Summary:")
    print(f"  Total achievements: {total_achievements}")
    print(f"  Mapped: {total_mapped}")
    print(f"  Unmapped: {total_achievements - total_mapped}")
    print(f"  Coverage: {total_mapped / total_achievements * 100:.1f}%" if total_achievements > 0 else "0%")
    print("")

    session.close()


if __name__ == "__main__":
    main()
