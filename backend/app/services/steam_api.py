import httpx
import os
import logging
import requests
from datetime import datetime
from app.services.effort_scoring import compute_steam_effort, compute_rarity_from_effort

logger = logging.getLogger(__name__)


STEAM_API_KEY = os.getenv("STEAM_API_KEY")

async def fetch_steam_profile(steam_id: str):
    url = f"http://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key={STEAM_API_KEY}&steamids={steam_id}"
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        print("STEAM API STATUS:", resp.status_code)
        print("STEAM API RESPONSE:", resp.text)
        if resp.status_code != 200:
            logger.error(f"Steam API returned {resp.status_code}: {resp.text}")
            return {}
        try:
            data = resp.json()
        except Exception as e:
            logger.error(f"Failed to parse Steam profile JSON: {e}")
            return {}
        players = data.get("response", {}).get("players", [])
        if players:
            player = players[0]
            print("STEAM PLAYER PARSED:", player)
            return {
                "steam_id": player.get("steamid"),
                "personaname": player.get("personaname"),
                "avatarfull": player.get("avatarfull"),
                "lastlogoff": player.get("lastlogoff"),
                "timecreated": player.get("timecreated"),
                "loccountrycode": player.get("loccountrycode"),
            }
        print("NO PLAYERS FOUND IN RESPONSE")
        return {}


async def get_steam_unlocked_achievements_async(provider_account, steam_api_key):
    steamid = provider_account.provider_user_id
    url_games = (
        f"http://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
        f"?key={steam_api_key}&steamid={steamid}&include_appinfo=1"
    )

    results = []

    async with httpx.AsyncClient() as client:
        resp = await client.get(url_games)
        print("[Steam API] Status:", resp.status_code)
        print("[Steam API] Raw response:", resp.text)
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
                f"http://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/"
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
                f"http://api.steampowered.com/ISteamUserStats/GetSchemaForGame/v2/"
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
                    print(f"[EFFORT] {game_name}: {api_name} = {percent}% -> effort={effort_score} -> {rarity_tier}")
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
    async with httpx.AsyncClient() as client:
        resp = await client.get(url)
        if resp.status_code != 200:
            # Log and return empty if forbidden or bad request
            print(f"[SYNC] GlobalPercent failed for app_id={app_id}: {resp.status_code}")
            return {}
        data = resp.json()
        achievements = data.get("achievementpercentages", {}).get("achievements", [])
        return {a["name"]: a["percent"] for a in achievements}


# categorize_steam_achievement moved to app/services/effort_scoring.py
# Use compute_steam_effort() and compute_rarity_from_effort() instead



