# app/services/xbox_services.py
"""
Xbox achievement sync via OpenXBL (xbl.io) third-party API.

OpenXBL handles Microsoft OAuth and provides Xbox Live data access
without requiring ID@Xbox program membership.

API Docs: https://xbl.io/docs
Rate Limit: 150 requests/hour (free tier)
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, Game, ProviderAccount, User
from app.services.effort_scoring import compute_xbox_effort, compute_rarity_from_effort
from app.services.game_discovery_service import check_and_log_game_discovery
import logging

logger = logging.getLogger(__name__)

OPENXBL_API_BASE = "https://xbl.io/api/v2"


async def get_xbox_profile(api_key: str) -> dict:
    """Get the authenticated user's Xbox profile."""
    headers = {
        "X-Authorization": api_key,
        "X-Contract": "100",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{OPENXBL_API_BASE}/account", headers=headers)
        logger.info(f"[XBOX] Profile API status: {resp.status_code}")

        if resp.status_code != 200:
            raise Exception(f"OpenXBL API error: {resp.status_code} - {resp.text[:200]}")

        return resp.json()


async def get_xbox_player_summary(api_key: str, xuid: str = None) -> dict:
    """Get player summary including gamerscore."""
    headers = {
        "X-Authorization": api_key,
        "X-Contract": "100",
        "Accept": "application/json",
    }

    url = f"{OPENXBL_API_BASE}/player/summary"
    if xuid:
        url = f"{OPENXBL_API_BASE}/player/summary/{xuid}"

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers)
        if resp.status_code != 200:
            logger.warning(f"[XBOX] Player summary failed: {resp.status_code}")
            return {}
        return resp.json()


async def get_xbox_achievements(api_key: str, xuid: str = None) -> list:
    """Get achievement list for the user."""
    headers = {
        "X-Authorization": api_key,
        "X-Contract": "100",
        "Accept": "application/json",
    }

    url = f"{OPENXBL_API_BASE}/achievements"
    if xuid:
        url = f"{OPENXBL_API_BASE}/achievements/player/{xuid}"

    logger.info(f"[XBOX] Fetching achievements from: {url}")

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, timeout=30.0)
        logger.info(f"[XBOX] Achievements API status: {resp.status_code}")

        if resp.status_code != 200:
            logger.warning(f"[XBOX] Achievements failed: {resp.text[:500]}")
            return []

        data = resp.json()
        logger.info(f"[XBOX] Raw response keys: {list(data.keys())}")
        logger.info(f"[XBOX] Titles count: {len(data.get('titles', []))}")

        # Debug: log first title if exists
        titles = data.get("titles", [])
        if titles:
            logger.info(f"[XBOX] First title: {titles[0].get('name', 'unknown')}")
        else:
            logger.warning(f"[XBOX] No titles in response. Full response: {str(data)[:500]}")

        return titles


async def get_xbox_title_achievements(api_key: str, xuid: str, title_id: str) -> list:
    """Get individual achievements for a specific title."""
    headers = {
        "X-Authorization": api_key,
        "X-Contract": "100",
        "Accept": "application/json",
    }

    url = f"{OPENXBL_API_BASE}/achievements/player/{xuid}/{title_id}"

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, timeout=30.0)

        if resp.status_code != 200:
            logger.warning(f"[XBOX] Title achievements failed for {title_id}: {resp.status_code}")
            return []

        data = resp.json()
        # Response contains "achievements" array
        achievements = data.get("achievements", [])
        return achievements


async def get_xbox_title_history(api_key: str, xuid: str = None) -> list:
    """Get the user's game/title history."""
    headers = {
        "X-Authorization": api_key,
        "X-Contract": "100",
        "Accept": "application/json",
    }

    url = f"{OPENXBL_API_BASE}/player/titleHistory"
    if xuid:
        url = f"{OPENXBL_API_BASE}/player/titleHistory/{xuid}"

    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers, timeout=30.0)
        if resp.status_code != 200:
            return []
        return resp.json().get("titles", [])


def upsert_xbox_game(db: Session, provider_account: ProviderAccount, title_data: dict) -> Game:
    """Create or update a game record from Xbox title data."""
    title_id = str(title_data.get("titleId"))
    title_name = title_data.get("name", f"Xbox Game {title_id}")

    # Xbox box art from title data
    box_art = None
    if "displayImage" in title_data:
        box_art = title_data["displayImage"]

    db_game = (
        db.query(Game)
        .filter_by(provider_account_id=provider_account.id, app_id=title_id)
        .first()
    )

    if db_game:
        db_game.name = title_name
        if box_art:
            db_game.box_art_url = box_art
    else:
        db_game = Game(
            provider_account_id=provider_account.id,
            app_id=title_id,
            name=title_name,
            box_art_url=box_art,
        )
        db.add(db_game)

    db.commit()
    db.refresh(db_game)
    return db_game


async def sync_xbox_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
    api_key: str = None,
) -> dict:
    """
    Sync Xbox achievements via OpenXBL API.

    Returns summary of credited achievements.
    """
    from app.services.crypto_service import decrypt_token
    token = api_key or decrypt_token(provider_account.access_token)
    if not token:
        raise Exception("No OpenXBL API key available")

    logger.info(f"[XBOX] Starting achievement sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Also fetch account info for additional profile data (settings array format)
    account_settings = {}
    try:
        account_info = await get_xbox_profile(token)
        # Parse settings array from profileUsers[0].settings
        if "profileUsers" in account_info and account_info["profileUsers"]:
            settings_list = account_info["profileUsers"][0].get("settings", [])
            for setting in settings_list:
                account_settings[setting.get("id")] = setting.get("value")
            logger.info(f"[XBOX] Account settings parsed: {list(account_settings.keys())}")
    except Exception as e:
        logger.warning(f"[XBOX] Failed to fetch account info: {e}")

    # Fetch player summary for gamerscore and profile info (people array format)
    try:
        summary = await get_xbox_player_summary(token)

        # Extract from people[0] object
        person = {}
        if summary and "people" in summary and summary["people"]:
            person = summary["people"][0]

        # Get data from player summary (preferred) or fall back to account settings
        gamer_tag = (
            person.get("gamertag")
            or account_settings.get("Gamertag")
            or provider_account.profile_data.get("gamertag")
        )

        # gamerScore is a string in the API response
        gamerscore_str = person.get("gamerScore") or account_settings.get("Gamerscore") or "0"
        try:
            gamerscore = int(gamerscore_str)
        except (ValueError, TypeError):
            gamerscore = 0

        account_tier = account_settings.get("AccountTier", "")
        tenure_level = person.get("tenureLevel", 0)  # May not be in this endpoint

        # Avatar URL - try multiple sources
        avatar_url = (
            person.get("displayPicRaw")
            or account_settings.get("GameDisplayPicRaw")
        )

        provider_account.profile_data.update({
            "gamertag": gamer_tag,
            "gamerscore": gamerscore,
            "account_tier": account_tier,
            "tenure_level": tenure_level,
            "avatar_url": avatar_url,
        })
        # Flag JSON column as modified so SQLAlchemy persists the change
        flag_modified(provider_account, "profile_data")
        logger.info(f"[XBOX] Profile: {gamer_tag}, Gamerscore: {gamerscore}, Tier: {account_tier}")
    except Exception as e:
        logger.warning(f"[XBOX] Failed to fetch player summary: {e}")

    # Fetch title history for games played
    try:
        title_history = await get_xbox_title_history(token)
        if title_history:
            games_count = len(title_history)
            provider_account.profile_data["total_games"] = games_count
            flag_modified(provider_account, "profile_data")
            logger.info(f"[XBOX] Title history: {games_count} games")
    except Exception as e:
        logger.warning(f"[XBOX] Failed to fetch title history: {e}")

    # Get achievements grouped by title
    titles_data = await get_xbox_achievements(token)

    # Get XUID for per-title achievement fetching
    xuid = provider_account.provider_user_id

    total_found = 0
    total_credited = 0
    per_game = []
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    for title in titles_data:
        title_id = str(title.get("titleId", ""))
        title_name = title.get("name", f"Xbox Game {title_id}")

        # Upsert game record
        db_game = upsert_xbox_game(db, provider_account, title)

        # Check if this game should be added to the Tapestry
        achievement_summary = title.get("achievement", {})
        total_achs = achievement_summary.get("totalAchievements", 0) if isinstance(achievement_summary, dict) else 0
        check_and_log_game_discovery(
            db=db,
            provider="xbox",
            game_id=title_id,
            game_name=title_name,
            achievement_count=total_achs,
            sample_achievements=None,  # Will be populated on later syncs
            user_id=user.id if user else None
        )

        # Check if user has any achievements in this title
        current_achievements = achievement_summary.get("currentAchievements", 0) if isinstance(achievement_summary, dict) else 0

        if current_achievements == 0:
            # Skip titles with no achievements earned
            continue

        # Fetch individual achievements for this title
        logger.info(f"[XBOX] Fetching {current_achievements} achievements for: {title_name}")
        achievements = await get_xbox_title_achievements(token, xuid, title_id)

        if not achievements:
            logger.warning(f"[XBOX] No achievement details returned for {title_name}")
            continue

        # Debug: log first achievement structure
        if achievements and total_found == 0:
            logger.info(f"[XBOX] First achievement keys: {list(achievements[0].keys()) if isinstance(achievements[0], dict) else type(achievements[0])}")
            logger.info(f"[XBOX] First achievement sample: {str(achievements[0])[:800]}")

        found = 0
        credited = 0
        ignored = 0
        stored = 0

        for ach in achievements:
            ach_id = str(ach.get("id", ""))
            ach_name = ach.get("name", f"Achievement {ach_id}")
            ach_desc = ach.get("description", "")
            progress_state = ach.get("progressState", "")
            is_unlocked = progress_state == "Achieved"

            # Get gamerscore value - it's in rewards[0].value as a string
            try:
                gamerscore = int(ach.get("rewards", [{}])[0].get("value", 0)) if ach.get("rewards") else 0
            except (ValueError, TypeError):
                gamerscore = 0

            # Extract rarity percentage from OpenXBL data
            rarity_data = ach.get("rarity", {})
            rarity_percent = None
            if isinstance(rarity_data, dict):
                try:
                    rarity_percent = float(rarity_data.get("currentPercentage", 0))
                    if rarity_percent == 0:
                        rarity_percent = None
                except (ValueError, TypeError):
                    rarity_percent = None

            # Compute effort score
            effort_score = compute_xbox_effort(gamerscore=gamerscore, global_percent=rarity_percent)
            rarity_tier = compute_rarity_from_effort(effort_score)

            # Icon URL
            icon_url = None
            media_assets = ach.get("mediaAssets", [])
            if media_assets:
                icon_url = media_assets[0].get("url")

            # Upsert achievement (store ALL achievements, not just unlocked)
            db_ach = (
                db.query(Achievement)
                .filter_by(app_id=title_id, api_name=ach_id)
                .first()
            )

            if not db_ach:
                db_ach = Achievement(
                    app_id=title_id,
                    api_name=ach_id,
                    name=ach_name,
                    display_name=ach_name,
                    description=ach_desc,
                    icon_url=icon_url,
                    effort_score=effort_score,
                    effort_auto=True,
                    rarity_tier=rarity_tier,
                )
                db.add(db_ach)
                db.commit()
                db.refresh(db_ach)
                stored += 1
            else:
                # Update if auto-calculated
                if getattr(db_ach, "effort_auto", True):
                    db_ach.effort_score = effort_score
                    db_ach.rarity_tier = rarity_tier
                # Update icon if we have one now
                if icon_url and not db_ach.icon_url:
                    db_ach.icon_url = icon_url
                db.commit()

            # Only credit UNLOCKED achievements
            if not is_unlocked:
                continue

            found += 1

            # Track rarity distribution for unlocked achievements
            if rarity_tier in rarity_counts:
                rarity_counts[rarity_tier] += 1

            # Get unlock time from progression data
            unlock_time = None
            progression = ach.get("progression", {})
            time_unlocked = progression.get("timeUnlocked") if isinstance(progression, dict) else None
            if time_unlocked:
                try:
                    from datetime import datetime
                    unlock_time = datetime.fromisoformat(time_unlocked.replace("Z", "+00:00"))
                except (ValueError, AttributeError):
                    pass

            # Credit achievement
            existing = (
                db.query(AchievementCredit)
                .filter_by(
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id
                )
                .first()
            )

            if existing:
                # Update unlocked_at if we have it now but didn't before
                if unlock_time and not existing.unlocked_at:
                    existing.unlocked_at = unlock_time
                    db.commit()
                ignored += 1
            else:
                new_credit = AchievementCredit(
                    user_id=user.id,
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id,
                    provider_name="xbox",
                    provider_user_id=provider_account.provider_user_id,
                    is_original_claim=True,
                    unlocked_at=unlock_time,
                )
                db.add(new_credit)
                credited += 1

        db.commit()

        if found > 0 or stored > 0:
            per_game.append({
                "app_id": title_id,
                "game_name": title_name,
                "total_found": found,
                "credited": credited,
                "ignored": ignored,
            })

        total_found += found
        total_credited += credited

    db.commit()

    logger.info(f"[XBOX] Sync complete: {total_credited} new credits from {total_found} achievements")
    logger.info(f"[XBOX] Rarity distribution: {rarity_counts}")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": per_game,
        },
        "profile": {
            "gamertag": provider_account.profile_data.get("gamertag"),
            "gamerscore": provider_account.profile_data.get("gamerscore", 0),
            "tenure_level": provider_account.profile_data.get("tenure_level", 0),
            "total_games": provider_account.profile_data.get("total_games", 0),
        }
    }
