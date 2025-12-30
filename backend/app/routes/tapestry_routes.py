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
from app.models import Achievement, PendingGameDiscovery

logger = logging.getLogger(__name__)


def check_platform_achievements_exist(platforms: dict, canonical_platform: str) -> dict:
    """
    Check which platforms have achievements in the database.
    Returns dict of {platform: bool} indicating if achievements exist.
    """
    db = SessionLocal()
    try:
        result = {}
        for platform, platform_data in platforms.items():
            if platform == canonical_platform:
                # Canonical platform - assume we have achievements
                result[platform] = True
                continue

            if not isinstance(platform_data, dict):
                result[platform] = False
                continue

            # Get the app_id/title_id for this platform
            app_id = platform_data.get("app_id") or platform_data.get("title_id")
            if not app_id or app_id == "TO_RESEARCH":
                result[platform] = False
                continue

            # Check if we have any achievements for this app_id
            count = db.query(Achievement).filter(Achievement.app_id == str(app_id)).limit(1).count()
            result[platform] = count > 0

        return result
    finally:
        db.close()

async def get_ready_discoveries_from_db(db, fetch_schemas: bool = True) -> list:
    """
    Get cross-platform game discoveries that are ready to map.

    These are games that:
    1. Have been detected on multiple platforms (is_cross_platform=True)
    2. Have achievements in the database from at least 2 platforms

    If fetch_schemas=True, will fetch full Steam achievement schemas for discovered games.

    Returns a list of game entries formatted like JSON games for the Tapestry.
    """
    from collections import defaultdict
    from app.services.steam_api import fetch_and_store_steam_schema

    # Get all cross-platform discoveries
    discoveries = db.query(PendingGameDiscovery).filter(
        PendingGameDiscovery.is_cross_platform == True,
        PendingGameDiscovery.status == 'pending'
    ).all()

    if not discoveries:
        return []

    # Group by cross_platform_match_id
    by_match = defaultdict(list)
    for d in discoveries:
        match_id = d.cross_platform_match_id or d.id
        by_match[match_id].append(d)

    ready_games = []

    for match_id, group in by_match.items():
        # Check if we have achievements from each platform
        platforms_with_achievements = {}
        primary_name = None
        steam_app_id = ""

        for discovery in group:
            provider = discovery.source_provider
            game_id = discovery.provider_game_id

            # Count achievements for this platform's game
            ach_count = db.query(Achievement).filter(
                Achievement.app_id == str(game_id)
            ).count()

            # Get UNLOCKED achievement api_names (ones with credits - these are mappable by users)
            from app.models import AchievementCredit
            unlocked_achievements = db.query(Achievement.api_name).join(
                AchievementCredit, Achievement.id == AchievementCredit.achievement_id
            ).filter(
                Achievement.app_id == str(game_id)
            ).distinct(Achievement.api_name).all()
            unlocked_api_names = {a.api_name for a in unlocked_achievements}

            if ach_count > 0:
                platforms_with_achievements[provider] = {
                    "game_id": game_id,
                    "game_name": discovery.game_name,
                    "achievement_count": ach_count,
                    "unlocked_api_names": unlocked_api_names,  # Set of api_names users have unlocked
                }

                # Use first name as primary
                if primary_name is None:
                    primary_name = discovery.game_name

                # Track Steam app_id for icon
                if provider == "steam":
                    steam_app_id = game_id

        # Need at least 2 platforms with achievements to be "ready"
        if len(platforms_with_achievements) < 2:
            continue

        # Determine canonical platform (prefer Steam, then Xbox, then PSN)
        canonical_platform = None
        for pref in ["steam", "xbox", "psn", "battlenet"]:
            if pref in platforms_with_achievements:
                canonical_platform = pref
                break

        if not canonical_platform:
            canonical_platform = list(platforms_with_achievements.keys())[0]

        canonical_info = platforms_with_achievements[canonical_platform]
        canonical_app_id = canonical_info["game_id"]
        canonical_achievements = canonical_info["achievement_count"]

        # Get set of unlocked api_names for canonical platform
        canonical_unlocked = canonical_info.get("unlocked_api_names", set())

        # Fetch full Steam schema if Steam is involved (to get real totals)
        schema_fetched = False
        if fetch_schemas:
            # Try to fetch Steam schema if Steam is canonical or a target
            steam_id_to_fetch = None
            if canonical_platform == "steam":
                steam_id_to_fetch = canonical_app_id
            elif "steam" in platforms_with_achievements:
                steam_id_to_fetch = platforms_with_achievements["steam"]["game_id"]
            elif steam_app_id:
                steam_id_to_fetch = steam_app_id

            if steam_id_to_fetch:
                try:
                    real_count = await fetch_and_store_steam_schema(db, steam_id_to_fetch)
                    if real_count > 0:
                        # Update canonical achievements if Steam is canonical
                        if canonical_platform == "steam":
                            canonical_achievements = real_count
                            canonical_info["achievement_count"] = real_count
                        # Update Steam platform info if it's a target
                        if "steam" in platforms_with_achievements:
                            platforms_with_achievements["steam"]["achievement_count"] = real_count
                        schema_fetched = True
                        logger.debug(f"Fetched Steam schema for {primary_name}: {real_count} achievements")
                except Exception as e:
                    logger.warning(f"Failed to fetch Steam schema for {primary_name}: {e}")

        # Build target platforms (non-canonical ones)
        target_platforms = {
            p: info for p, info in platforms_with_achievements.items()
            if p != canonical_platform
        }

        # Generate a unique key for this discovered game
        game_key = f"discovered_{match_id}"

        # Build the game entry
        game_entry = {
            "key": game_key,
            "name": primary_name,
            "canonical_platform": canonical_platform,
            "canonical_app_id": canonical_app_id,
            "steam_app_id": steam_app_id,
            "achievement_count": canonical_achievements,
            "platforms": list(target_platforms.keys()),
            "platform_coverage": {},
            "platform_has_achievements": {p: True for p in target_platforms.keys()},
            "total_mappings": 0,
            "mapped_count": 0,
            "parity": 0.0,
            "weave_strength": "torn",
            "gaps": [],
            "gap_count": 0,
            "mappable": 0,  # Will be calculated after checking existing mappings
            "total_unlocked": 0,  # Total achievements unlocked by any user
            "gap_count_is_minimum": not schema_fetched,  # True if we only have synced achievements
            "ready_to_map": True,
            "is_discovered": True,  # Flag to indicate this came from discoveries
            "discovery_match_id": match_id,
        }

        # Check for existing mappings under game_{steam_app_id} key
        mappings = load_platform_mappings()
        alt_game_key = f"game_{steam_app_id}" if steam_app_id else None
        existing_mappings = {}  # platform -> count
        mapped_api_names = set()  # Track which api_names are already mapped
        if alt_game_key:
            alt_game_data = mappings.get('games', {}).get(alt_game_key, {})
            achievements_map = alt_game_data.get('achievements', {})
            # Track mappings per platform and which api_names are mapped
            for ach_key, ach_data in achievements_map.items():
                for plat in target_platforms.keys():
                    mapping = ach_data.get(plat)
                    if mapping and mapping != "TO_RESEARCH":
                        if isinstance(mapping, str):
                            existing_mappings[plat] = existing_mappings.get(plat, 0) + 1
                            mapped_api_names.add(ach_key)
                        elif isinstance(mapping, dict):
                            for v in mapping.values():
                                if v and v != "TO_RESEARCH":
                                    existing_mappings[plat] = existing_mappings.get(plat, 0) + 1
                                    mapped_api_names.add(ach_key)
                                    break

        # Calculate mapping stats
        total_possible = 0
        total_mapped = 0
        for platform, info in target_platforms.items():
            mapped_count = existing_mappings.get(platform, 0)
            total_mapped += mapped_count
            game_entry["platform_coverage"][platform] = {
                "total": canonical_achievements,
                "mapped": mapped_count
            }
            total_possible += canonical_achievements
            unmapped = canonical_achievements - mapped_count
            if unmapped > 0:
                game_entry["gaps"].append({
                    "platform": platform,
                    "count": unmapped
                })

        game_entry["total_mappings"] = total_possible
        game_entry["mapped_count"] = total_mapped
        game_entry["gap_count"] = total_possible - total_mapped
        game_entry["parity"] = round((total_mapped / total_possible * 100) if total_possible > 0 else 0, 1)

        # Calculate mappable: unlocked achievements that are NOT yet mapped
        # These are achievements users have earned and can contribute mappings for
        unmapped_unlocked = canonical_unlocked - mapped_api_names
        game_entry["mappable"] = len(unmapped_unlocked)
        game_entry["total_unlocked"] = len(canonical_unlocked)  # Total unlocked by any user

        ready_games.append(game_entry)
        logger.info(f"Auto-added discovered game to Tapestry: {primary_name} ({list(platforms_with_achievements.keys())})")

    return ready_games


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


async def calculate_tapestry_health():
    """
    Calculate the health/parity of the Tapestry.

    Returns detailed statistics about cross-platform achievement mapping coverage.
    Now counts ALL achievements from the database, not just forge-eligible ones.
    """
    from app.models import CommunityContribution

    mappings = load_platform_mappings()
    games_data = mappings.get("games", {})

    # Track overall stats
    total_achievements = 0
    total_mappings_possible = 0
    mapped_count = 0

    # Track per-provider stats
    provider_stats = {}

    # Track per-game stats
    games_list = []

    # Get all providers we care about (from game platforms + canonical)
    all_providers = set()
    for game_key, game in games_data.items():
        # Skip comment entries
        if game_key.startswith("_") or not isinstance(game, dict):
            continue
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

    # Open a single DB session for all queries
    db = SessionLocal()
    try:
        # Get all approved mappings for quick lookup
        approved_mappings = db.query(CommunityContribution).filter(
            CommunityContribution.contribution_type == "platform_mapping",
            CommunityContribution.status == "approved"
        ).all()

        # Build lookup: game_key -> {target_platform -> set of source_api_names}
        approved_lookup = {}
        for contrib in approved_mappings:
            data = contrib.data or {}
            gk = data.get("game_key", "")
            target_platform = data.get("target_platform", "")
            source_api = data.get("steam_api_name") or data.get("source_api_name", "")

            if gk and target_platform and source_api:
                if gk not in approved_lookup:
                    approved_lookup[gk] = {}
                if target_platform not in approved_lookup[gk]:
                    approved_lookup[gk][target_platform] = set()
                approved_lookup[gk][target_platform].add(source_api)

        for game_key, game in games_data.items():
            # Skip comment entries
            if game_key.startswith("_") or not isinstance(game, dict):
                continue

            # Skip malformed entries (must have canonical section with platform)
            canonical = game.get("canonical", {})
            if not canonical or not canonical.get("platform"):
                logger.debug(f"Skipping malformed game entry: {game_key}")
                continue

            game_name = game.get("_display_name", game_key.replace("_", " ").title())
            canonical_platform = canonical.get("platform", "steam")

            # Get canonical app_id based on platform type
            if canonical_platform == "xbox":
                canonical_app_id = canonical.get("title_id", "")
            elif canonical_platform == "psn":
                canonical_app_id = canonical.get("np_communication_id", "")
            else:
                canonical_app_id = canonical.get("app_id", "")

            # Skip games with TO_RESEARCH or empty app_ids - they're placeholders
            if not canonical_app_id or canonical_app_id == "TO_RESEARCH":
                logger.debug(f"Skipping placeholder game: {game_key} (app_id: {canonical_app_id})")
                continue

            platforms = game.get("platforms", {})

            # Get Steam app_id for icon - either from canonical or from platforms
            steam_app_id = ""
            if canonical_platform == "steam" and canonical_app_id and canonical_app_id != "TO_RESEARCH":
                steam_app_id = canonical_app_id
            elif "steam" in platforms:
                steam_platform_data = platforms.get("steam", {})
                if isinstance(steam_platform_data, dict):
                    steam_app_id = steam_platform_data.get("app_id", "")

            # Query ACTUAL achievement count from database
            if canonical_app_id and canonical_app_id != "TO_RESEARCH":
                db_achievement_count = db.query(Achievement).filter(
                    Achievement.app_id == str(canonical_app_id)
                ).count()
            else:
                db_achievement_count = 0

            # Get all achievement api_names for this game from DB
            if canonical_app_id and canonical_app_id != "TO_RESEARCH":
                db_achievements = db.query(Achievement.api_name).filter(
                    Achievement.app_id == str(canonical_app_id)
                ).all()
                all_api_names = {a.api_name for a in db_achievements}
            else:
                all_api_names = set()

            game_achievements = db_achievement_count
            total_achievements += game_achievements

            # For each target platform, count how many achievements are mapped
            game_mappings_possible = 0
            game_mapped = 0
            game_gaps = []

            platform_coverage = {}
            game_approved = approved_lookup.get(game_key, {})

            for platform in platforms.keys():
                # Each achievement needs mapping to this platform
                platform_coverage[platform] = {"total": game_achievements, "mapped": 0}
                game_mappings_possible += game_achievements
                total_mappings_possible += game_achievements
                provider_stats[platform]["total"] += game_achievements

                # Count how many are approved for this platform
                platform_mapped_apis = game_approved.get(platform, set())
                # Only count mappings for achievements that actually exist in DB
                valid_mappings = platform_mapped_apis & all_api_names
                mapped_for_platform = len(valid_mappings)

                platform_coverage[platform]["mapped"] = mapped_for_platform
                game_mapped += mapped_for_platform
                mapped_count += mapped_for_platform
                provider_stats[platform]["mapped"] += mapped_for_platform

                # Track gaps (unmapped achievements)
                unmapped_count = game_achievements - mapped_for_platform
                if unmapped_count > 0:
                    game_gaps.append({
                        "platform": platform,
                        "count": unmapped_count
                    })

            # Calculate game parity
            game_parity = (game_mapped / game_mappings_possible * 100) if game_mappings_possible > 0 else 0

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

            # Check if we have achievements in DB for target platforms
            platform_has_achievements = check_platform_achievements_exist(platforms, canonical_platform)

            # Also check if canonical platform has achievements
            canonical_has_achievements = db_achievement_count > 0

            # Game is ready to map if:
            # 1. Canonical platform has achievements
            # 2. At least one non-canonical platform has achievements
            target_platforms = [p for p in platforms.keys() if p != canonical_platform]
            has_target_achievements = any(platform_has_achievements.get(p, False) for p in target_platforms)
            ready_to_map = canonical_has_achievements and has_target_achievements

            # Only show games that are ready to map (have achievements from both sides)
            if not ready_to_map:
                logger.debug(f"Skipping {game_key}: not ready to map (canonical={canonical_has_achievements}, target={has_target_achievements})")
                continue

            # Calculate gap count (total unmapped across all platforms)
            total_gap_count = game_mappings_possible - game_mapped

            games_list.append({
                "key": game_key,
                "name": game_name,
                "canonical_platform": canonical_platform,
                "canonical_app_id": canonical_app_id,
                "steam_app_id": steam_app_id,
                "achievement_count": game_achievements,
                "platforms": list(platforms.keys()),
                "platform_coverage": platform_coverage,
                "platform_has_achievements": platform_has_achievements,
                "total_mappings": game_mappings_possible,
                "mapped_count": game_mapped,
                "parity": round(game_parity, 1),
                "weave_strength": weave_strength,
                "gaps": game_gaps[:5],  # Top 5 gaps by platform
                "gap_count": total_gap_count,
                "ready_to_map": ready_to_map,
            })

        # Auto-populate from cross-platform discoveries
        # These are games detected on multiple platforms with achievements from both sides
        discovered_games = await get_ready_discoveries_from_db(db)
        existing_keys = {g["key"] for g in games_list}

        for game in discovered_games:
            # Skip if already in the list (from JSON)
            if game["key"] in existing_keys:
                continue

            # Add to games list
            games_list.append(game)

            # Update totals (including mapped count from discovered games)
            total_achievements += game["achievement_count"]
            total_mappings_possible += game["total_mappings"]
            mapped_count += game.get("mapped_count", 0)

            # Update provider stats
            for platform in game["platforms"]:
                if platform not in provider_stats:
                    provider_stats[platform] = {
                        "total": 0,
                        "mapped": 0,
                        "config": PROVIDER_CONFIG.get(platform, {
                            "name": platform.title(),
                            "color": "#666666",
                            "glow": "#999999",
                            "icon": "🎮"
                        })
                    }
                provider_stats[platform]["total"] += game["achievement_count"]
                # Add mapped count for this platform
                platform_cov = game.get("platform_coverage", {}).get(platform, {})
                provider_stats[platform]["mapped"] += platform_cov.get("mapped", 0)

    finally:
        db.close()

    # Calculate overall parity
    overall_parity = (mapped_count / total_mappings_possible * 100) if total_mappings_possible > 0 else 0

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
            "total_games": len(games_list),
            "total_achievements": total_achievements,
            "total_mappings": total_mappings_possible,
            "mapped_count": mapped_count,
            "gap_count": total_mappings_possible - mapped_count
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
    return await calculate_tapestry_health()


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
    health = await calculate_tapestry_health()

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


@router.get("/image-proxy")
async def proxy_achievement_image(url: str):
    """
    Proxy achievement images to avoid CORS issues with Xbox Live, etc.
    """
    import httpx
    from fastapi.responses import Response

    # Only allow specific domains for security
    allowed_domains = [
        "images-eds-ssl.xboxlive.com",
        "steamcdn-a.akamaihd.net",
        "cdn.cloudflare.steamstatic.com",
    ]

    try:
        from urllib.parse import urlparse
        parsed = urlparse(url)
        if parsed.netloc not in allowed_domains:
            return Response(content=b"", status_code=403)

        async with httpx.AsyncClient() as client:
            resp = await client.get(url, timeout=10.0, follow_redirects=True)
            return Response(
                content=resp.content,
                media_type=resp.headers.get("content-type", "image/png"),
                headers={"Cache-Control": "public, max-age=86400"}
            )
    except Exception as e:
        logger.error(f"Image proxy error: {e}")
        return Response(content=b"", status_code=404)
