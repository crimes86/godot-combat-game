"""
Tapestry visualization routes.

The Tapestry is a living visualization of cross-platform achievement parity.
It shows which games have complete mappings across platforms, and where
community contributions are needed to strengthen the weave.
"""
from fastapi import APIRouter, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session as DbSession
from typing import Callable, Optional
import json
import os
import logging

from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/tapestry", tags=["tapestry"])
templates = Jinja2Templates(directory="templates")

# Dependencies set by init_tapestry_routes()
_get_current_user_func: Callable = None

# Provider display configuration
PROVIDER_CONFIG = {
    "steam": {
        "name": "Steam",
        "color": "#1B9BD7",
        "glow": "#66D9FF",
        "icon": "🎮"
    },
    "xbox": {
        "name": "Xbox",
        "color": "#107C10",
        "glow": "#4CAF50",
        "icon": "🎯"
    },
    "psn": {
        "name": "PlayStation",
        "color": "#003791",
        "glow": "#5C7CFA",
        "icon": "🏆"
    },
    "battlenet": {
        "name": "Battle.net",
        "color": "#00AEFF",
        "glow": "#64D2FF",
        "icon": "⚔️"
    },
    "gog": {
        "name": "GOG",
        "color": "#86328A",
        "glow": "#BA68C8",
        "icon": "🌌"
    },
    "epic": {
        "name": "Epic Games",
        "color": "#2A2A2A",
        "glow": "#757575",
        "icon": "🎪"
    },
    "nintendo": {
        "name": "Nintendo",
        "color": "#E60012",
        "glow": "#FF5252",
        "icon": "🍄"
    },
    "roblox": {
        "name": "Roblox",
        "color": "#00A2FF",
        "glow": "#64D2FF",
        "icon": "🧱"
    },
    "google_play": {
        "name": "Google Play",
        "color": "#4CAF50",
        "glow": "#81C784",
        "icon": "📱"
    }
}


def get_db():
    """Database session dependency."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_tapestry_routes(get_current_user: Callable = None):
    """Initialize tapestry routes with dependencies from main app."""
    global _get_current_user_func
    _get_current_user_func = get_current_user
    logger.info("Tapestry routes initialized")


def load_platform_mappings():
    """Load the platform mappings JSON file."""
    mappings_path = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json')
    try:
        with open(mappings_path, 'r') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load platform mappings: {e}")
        return {"games": {}, "provider_colors": {}}


def calculate_tapestry_health():
    """
    Calculate the health/parity of the Tapestry.

    Returns detailed statistics about cross-platform achievement mapping coverage.
    """
    mappings = load_platform_mappings()
    games_data = mappings.get("games", {})

    # Track overall stats
    total_achievements = 0
    total_mappings = 0
    mapped_count = 0

    # Track per-provider stats
    provider_stats = {}

    # Track per-game stats
    games_list = []

    # Get all providers we care about (from game platforms + canonical)
    all_providers = set()
    for game in games_data.values():
        all_providers.add(game.get("canonical", {}).get("platform", "steam"))
        all_providers.update(game.get("platforms", {}).keys())

    for provider in all_providers:
        provider_stats[provider] = {
            "total": 0,
            "mapped": 0,
            "config": PROVIDER_CONFIG.get(provider, {
                "name": provider.title(),
                "color": "#666666",
                "glow": "#999999",
                "icon": "🎮"
            })
        }

    for game_key, game in games_data.items():
        game_name = game.get("_display_name", game_key.replace("_", " ").title())
        canonical = game.get("canonical", {})
        canonical_platform = canonical.get("platform", "steam")
        canonical_app_id = canonical.get("app_id", "")

        achievements = game.get("achievements", {})
        platforms = game.get("platforms", {})

        game_achievements = len(achievements)
        total_achievements += game_achievements

        # For each achievement, check mappings to other platforms
        game_mappings = 0
        game_mapped = 0
        game_gaps = []

        platform_coverage = {}

        for platform in platforms.keys():
            platform_coverage[platform] = {"total": 0, "mapped": 0}

            for ach_key, ach in achievements.items():
                platform_mapping = ach.get(platform, {})

                if platform_mapping:
                    game_mappings += 1
                    total_mappings += 1
                    provider_stats[platform]["total"] += 1
                    platform_coverage[platform]["total"] += 1

                    # Check if it's actually mapped (not TO_RESEARCH)
                    if isinstance(platform_mapping, dict):
                        mapping_value = list(platform_mapping.values())[0] if platform_mapping else ""
                        if mapping_value and mapping_value != "TO_RESEARCH":
                            game_mapped += 1
                            mapped_count += 1
                            provider_stats[platform]["mapped"] += 1
                            platform_coverage[platform]["mapped"] += 1
                        else:
                            game_gaps.append({
                                "achievement": ach.get("_display_name", ach_key),
                                "platform": platform
                            })

        # Calculate game parity
        game_parity = (game_mapped / game_mappings * 100) if game_mappings > 0 else 0

        # Determine game "weave strength"
        if game_parity >= 100:
            weave_strength = "radiant"  # Fully mapped
        elif game_parity >= 75:
            weave_strength = "strong"
        elif game_parity >= 50:
            weave_strength = "partial"
        elif game_parity >= 25:
            weave_strength = "weak"
        elif game_parity > 0:
            weave_strength = "frayed"
        else:
            weave_strength = "torn"  # No mappings at all

        games_list.append({
            "key": game_key,
            "name": game_name,
            "canonical_platform": canonical_platform,
            "canonical_app_id": canonical_app_id,
            "achievement_count": game_achievements,
            "platforms": list(platforms.keys()),
            "platform_coverage": platform_coverage,
            "total_mappings": game_mappings,
            "mapped_count": game_mapped,
            "parity": round(game_parity, 1),
            "weave_strength": weave_strength,
            "gaps": game_gaps[:5],  # Top 5 gaps
            "gap_count": len(game_gaps)
        })

    # Calculate overall parity
    overall_parity = (mapped_count / total_mappings * 100) if total_mappings > 0 else 0

    # Sort games by parity (lowest first = biggest opportunities)
    games_list.sort(key=lambda g: (g["parity"], -g["gap_count"]))

    # Calculate provider parity
    providers_list = []
    for provider, stats in provider_stats.items():
        parity = (stats["mapped"] / stats["total"] * 100) if stats["total"] > 0 else 0
        providers_list.append({
            "key": provider,
            "name": stats["config"]["name"],
            "color": stats["config"]["color"],
            "glow": stats["config"]["glow"],
            "icon": stats["config"]["icon"],
            "total": stats["total"],
            "mapped": stats["mapped"],
            "parity": round(parity, 1)
        })

    providers_list.sort(key=lambda p: -p["parity"])  # Highest parity first

    # Determine overall tapestry state
    if overall_parity >= 100:
        tapestry_state = "complete"
        tapestry_message = "The Tapestry is whole. All threads are woven."
    elif overall_parity >= 80:
        tapestry_state = "radiant"
        tapestry_message = "The Tapestry glows with near-completion. Few threads remain loose."
    elif overall_parity >= 60:
        tapestry_state = "strong"
        tapestry_message = "The Tapestry holds firm. Many patterns are woven."
    elif overall_parity >= 40:
        tapestry_state = "partial"
        tapestry_message = "The Tapestry takes shape. More threads seek their place."
    elif overall_parity >= 20:
        tapestry_state = "weak"
        tapestry_message = "The Tapestry yearns for completion. Many gaps remain."
    elif overall_parity > 0:
        tapestry_state = "frayed"
        tapestry_message = "The Tapestry is frayed. Community weavers are needed."
    else:
        tapestry_state = "unwoven"
        tapestry_message = "The Tapestry awaits its first threads. Begin the weaving."

    # Top gaps (games with most missing mappings)
    top_gaps = [g for g in games_list if g["gap_count"] > 0][:10]

    return {
        "overall": {
            "parity": round(overall_parity, 1),
            "state": tapestry_state,
            "message": tapestry_message,
            "total_games": len(games_data),
            "total_achievements": total_achievements,
            "total_mappings": total_mappings,
            "mapped_count": mapped_count,
            "gap_count": total_mappings - mapped_count
        },
        "providers": providers_list,
        "games": games_list,
        "top_gaps": top_gaps,
        "lore": mappings.get("tapestry_lore", {})
    }


# =============================================================================
# API ENDPOINTS
# =============================================================================

@router.get("/status")
async def get_tapestry_status():
    """
    Get the current health and status of the Tapestry.

    Returns detailed statistics about cross-platform achievement mapping coverage,
    including per-game and per-provider breakdowns.
    """
    return calculate_tapestry_health()


@router.get("/games/{game_key}")
async def get_game_details(game_key: str):
    """
    Get detailed tapestry information for a specific game.
    """
    mappings = load_platform_mappings()
    games_data = mappings.get("games", {})

    if game_key not in games_data:
        return {"error": "Game not found in Tapestry"}

    game = games_data[game_key]
    game_name = game.get("_display_name", game_key.replace("_", " ").title())
    canonical = game.get("canonical", {})
    achievements = game.get("achievements", {})
    platforms = game.get("platforms", {})

    # Build detailed achievement mapping info
    achievement_details = []
    for ach_key, ach in achievements.items():
        ach_name = ach.get("_display_name", ach_key.replace("_", " ").title())

        platform_mappings = {}
        for platform in platforms.keys():
            mapping = ach.get(platform, {})
            if mapping:
                mapping_value = list(mapping.values())[0] if mapping else ""
                platform_mappings[platform] = {
                    "mapped": mapping_value and mapping_value != "TO_RESEARCH",
                    "value": mapping_value
                }

        achievement_details.append({
            "key": ach_key,
            "name": ach_name,
            "platforms": platform_mappings
        })

    return {
        "key": game_key,
        "name": game_name,
        "canonical": canonical,
        "platforms": list(platforms.keys()),
        "achievement_count": len(achievements),
        "achievements": achievement_details
    }


@router.get("/contribute/opportunities")
async def get_contribution_opportunities():
    """
    Get a prioritized list of contribution opportunities.

    Returns games and achievements that need mapping, sorted by impact
    (popular games with the most gaps first).
    """
    health = calculate_tapestry_health()

    opportunities = []
    for game in health["games"]:
        if game["gap_count"] > 0:
            opportunities.append({
                "game_key": game["key"],
                "game_name": game["name"],
                "platforms_needed": [
                    p for p, cov in game["platform_coverage"].items()
                    if cov["mapped"] < cov["total"]
                ],
                "gaps_count": game["gap_count"],
                "current_parity": game["parity"],
                "weave_strength": game["weave_strength"],
                "sample_gaps": game["gaps"]
            })

    return {
        "total_opportunities": len(opportunities),
        "opportunities": opportunities
    }
