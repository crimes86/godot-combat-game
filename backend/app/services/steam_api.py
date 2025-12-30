import httpx
import os
import logging
import requests
import asyncio
from datetime import datetime
from app.services.effort_scoring import compute_steam_effort, compute_rarity_from_effort

logger = logging.getLogger(__name__)

# Shorter timeout per attempt, but with retries
STEAM_TIMEOUT = httpx.Timeout(15.0, connect=5.0)
STEAM_MAX_RETRIES = 3

STEAM_API_KEY = os.getenv("STEAM_API_KEY")

async def fetch_steam_profile(steam_id: str):
    url = f"https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key={STEAM_API_KEY}&steamids={steam_id}"

    for attempt in range(STEAM_MAX_RETRIES):
        try:
            async with httpx.AsyncClient(timeout=STEAM_TIMEOUT) as client:
                resp = await client.get(url)
                logger.debug(f"Steam API status: {resp.status_code} (attempt {attempt + 1})")

                if resp.status_code != 200:
                    logger.error(f"Steam API returned {resp.status_code}: {resp.text[:200]}")
                    return {}

                try:
                    data = resp.json()
                except Exception as e:
                    logger.error(f"Failed to parse Steam profile JSON: {e}")
                    return {}

                players = data.get("response", {}).get("players", [])
                if players:
                    player = players[0]
                    logger.debug(f"Steam player parsed: {player.get('personaname')}")
                    return {
                        "steam_id": player.get("steamid"),
                        "personaname": player.get("personaname"),
                        "avatarfull": player.get("avatarfull"),
                        "lastlogoff": player.get("lastlogoff"),
                        "timecreated": player.get("timecreated"),
                        "loccountrycode": player.get("loccountrycode"),
                    }
                logger.warning("No players found in Steam API response")
                return {}

        except (httpx.ReadTimeout, httpx.ConnectTimeout) as e:
            logger.warning(f"Steam API timeout (attempt {attempt + 1}/{STEAM_MAX_RETRIES}): {e}")
            if attempt < STEAM_MAX_RETRIES - 1:
                await asyncio.sleep(1)  # Brief pause before retry
            continue
        except Exception as e:
            logger.error(f"Steam API error: {e}")
            return {}

    logger.error(f"Steam API failed after {STEAM_MAX_RETRIES} attempts")
    return {}


async def get_steam_unlocked_achievements_async(provider_account, steam_api_key):
    steamid = provider_account.provider_user_id
    url_games = (
        f"https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
        f"?key={steam_api_key}&steamid={steamid}&include_appinfo=1"
    )

    results = []

    async with httpx.AsyncClient(timeout=STEAM_TIMEOUT) as client:
        resp = await client.get(url_games)
        logger.debug(f"Steam GetOwnedGames status: {resp.status_code}")
        games = resp.json().get("response", {}).get("games", [])
        for game in games:
            appid = str(game["appid"])
            game_name = game.get("name", "")
            logo_hash = game.get("img_logo_url", "")
            box_art_url = (
                f"https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{appid}/{logo_hash}.jpg"
                if logo_hash else ""
            )

            # 1. Get player achievement unlock status for this game
            url_achievements = (
                f"https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/"
                f"?appid={appid}&key={steam_api_key}&steamid={steamid}"
            )
            try:
                resp_ach = await client.get(url_achievements)
                if resp_ach.status_code != 200:
                    logger.info(f"[SYNC] Skipping appid={appid} ({game_name}), GetPlayerAchievements failed: {resp_ach.status_code}")
                    continue  # Skip this game
                ach_data = resp_ach.json().get("playerstats", {})
                player_achievements = {a["apiname"]: a for a in ach_data.get("achievements", [])}
            except Exception as e:
                logger.warning(f"[SYNC] Exception for appid={appid} ({game_name}) GetPlayerAchievements: {e}")
                continue

            # 2. Get schema (display info) for this game
            url_schema = (
                f"https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/"
                f"?key={steam_api_key}&appid={appid}"
            )
            try:
                resp_schema = await client.get(url_schema)
                if resp_schema.status_code != 200:
                    logger.info(f"[SYNC] Skipping appid={appid} ({game_name}), GetSchemaForGame failed: {resp_schema.status_code}")
                    continue
                schema_achs = (
                    resp_schema.json().get("game", {})
                    .get("availableGameStats", {})
                    .get("achievements", [])
                )
                schema_map = {a["name"]: a for a in schema_achs}
            except Exception as e:
                logger.warning(f"[SYNC] Exception for appid={appid} ({game_name}) GetSchemaForGame: {e}")
                continue

            # 3. Get global percent for this game
            try:
                percent_map = await get_global_percentages_for_game_async(appid, steam_api_key)
            except Exception as e:
                logger.info(f"[SYNC] Skipping percent for appid={appid} ({game_name}): {e}")
                percent_map = {}

            # 4. Merge ALL achievements (schema is source of truth, merge in player unlock + percent)
            game_achievements = []
            for api_name, schema in schema_map.items():
                player_ach = player_achievements.get(api_name, {})
                is_unlocked = player_ach.get("achieved", 0) == 1
                unlock_time = player_ach.get("unlocktime") if is_unlocked else None
                percent = percent_map.get(api_name)
                # Calculate effort_score and derive rarity_tier from it
                effort_score = compute_steam_effort(appid, api_name, percent)
                rarity_tier = compute_rarity_from_effort(effort_score)
                # Debug: log non-common achievements
                if rarity_tier != "Common" and is_unlocked:
                    logger.debug(f"[EFFORT] {game_name}: {api_name} = {percent}% -> effort={effort_score} -> {rarity_tier}")
                game_achievements.append({
                    "api_name": api_name,
                    "display_name": schema.get("displayName") if schema else api_name,
                    "description": schema.get("description") if schema else "",
                    "icon_url": schema.get("icon") if schema else "",
                    "icon_gray_url": schema.get("icon_gray") if schema else "",
                    "hidden": bool(int(schema.get("hidden", 0))) if schema else False,
                    "default_value": int(schema.get("defaultvalue", 0)) if schema else 0,
                    "percent": percent,
                    "effort_score": effort_score,
                    "rarity_tier": rarity_tier,
                    "unlocked": is_unlocked,
                    "unlock_time": unlock_time,
                })

            results.append({
                "app_id": appid,
                "game_name": game_name,
                "box_art_url": box_art_url,
                "achievements": game_achievements,
            })
    return results


async def get_global_percentages_for_game_async(app_id, steam_api_key):
    url = (
        f"https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/?gameid={app_id}"
    )
    async with httpx.AsyncClient(timeout=STEAM_TIMEOUT) as client:
        resp = await client.get(url)
        if resp.status_code != 200:
            # Log and return empty if forbidden or bad request
            logger.debug(f"GlobalPercent failed for app_id={app_id}: {resp.status_code}")
            return {}
        data = resp.json()
        achievements = data.get("achievementpercentages", {}).get("achievements", [])
        return {a["name"]: a["percent"] for a in achievements}


# categorize_steam_achievement moved to app/services/effort_scoring.py
# Use compute_steam_effort() and compute_rarity_from_effort() instead


async def fetch_and_store_steam_schema(db, app_id: str) -> int:
    """
    Fetch achievement schema from Steam and store in DB if not already present.

    Returns the total number of achievements for the game.
    """
    from app.models import Achievement

    # Check current count
    current_count = db.query(Achievement).filter(Achievement.app_id == str(app_id)).count()

    # Fetch schema from Steam
    schema = await get_steam_achievement_schema(str(app_id))

    if not schema:
        return current_count

    # If we already have more achievements than schema, something's off - return current
    if current_count >= len(schema):
        return current_count

    # Get existing api_names
    existing = set(
        a.api_name for a in
        db.query(Achievement.api_name).filter(Achievement.app_id == str(app_id)).all()
    )

    # Add missing achievements
    added = 0
    for api_name, data in schema.items():
        if api_name not in existing:
            ach = Achievement(
                app_id=str(app_id),
                api_name=api_name,
                name=data.get("display_name", api_name),
                display_name=data.get("display_name", api_name),
                description=data.get("description", ""),
                icon_url=data.get("icon_url", ""),
                rarity_tier="Common",  # Default, will be updated when someone unlocks
            )
            db.add(ach)
            added += 1

    if added > 0:
        db.commit()
        logger.info(f"[Steam] Added {added} achievements for app_id={app_id} (total: {len(schema)})")

    return len(schema)


async def get_steam_achievement_schema(app_id: str) -> dict:
    """
    Fetch achievement schema (names, descriptions, icons) for a Steam game.

    Returns dict mapping api_name -> {display_name, description, icon_url, icon_gray_url}
    """
    if not STEAM_API_KEY:
        logger.warning("STEAM_API_KEY not set, cannot fetch achievement schema")
        return {}

    url = (
        f"https://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/"
        f"?key={STEAM_API_KEY}&appid={app_id}"
    )

    try:
        async with httpx.AsyncClient(timeout=STEAM_TIMEOUT) as client:
            resp = await client.get(url)
            if resp.status_code != 200:
                logger.debug(f"GetSchemaForGame failed for app_id={app_id}: {resp.status_code}")
                return {}

            schema_achs = (
                resp.json().get("game", {})
                .get("availableGameStats", {})
                .get("achievements", [])
            )

            result = {}
            for ach in schema_achs:
                api_name = ach.get("name", "")
                result[api_name] = {
                    "display_name": ach.get("displayName", api_name),
                    "description": ach.get("description", ""),
                    "icon_url": ach.get("icon", ""),
                    "icon_gray_url": ach.get("icongray", ""),
                }

            logger.info(f"[Steam] Fetched schema for app_id={app_id}: {len(result)} achievements")
            return result

    except Exception as e:
        logger.warning(f"Failed to fetch Steam schema for app_id={app_id}: {e}")
        return {}



