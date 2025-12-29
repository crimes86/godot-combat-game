# app/services/google_play_services.py
"""
Google Play Games achievement sync via REST API.

Syncs achievements from Android games played via Google Play Games.
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, ProviderAccount, User
from app.services.effort_scoring import compute_rarity_from_effort
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

GOOGLE_PLAY_GAMES_API = "https://games.googleapis.com/games/v1"


async def get_player_profile(access_token: str) -> dict:
    """
    Fetch player profile from Google Play Games.
    Returns player info including displayName (gamertag).
    """
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(
            f"{GOOGLE_PLAY_GAMES_API}/players/me",
            headers=headers,
        )

        if resp.status_code != 200:
            logger.warning(f"[GOOGLE_PLAY] Player profile API returned {resp.status_code}")
            return {}

        return resp.json()


async def get_player_achievements(access_token: str) -> list:
    """
    Fetch all unlocked achievements for the authenticated player.
    Returns list of PlayerAchievement objects.
    """
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    all_achievements = []
    page_token = None

    async with httpx.AsyncClient(timeout=30.0) as client:
        while True:
            params = {
                "state": "UNLOCKED",
                "maxResults": 100,
            }
            if page_token:
                params["pageToken"] = page_token

            resp = await client.get(
                f"{GOOGLE_PLAY_GAMES_API}/players/me/achievements",
                headers=headers,
                params=params,
            )

            logger.info(f"[GOOGLE_PLAY] Achievements API status: {resp.status_code}")

            if resp.status_code == 401:
                raise Exception("Google Play Games token expired or invalid")

            if resp.status_code == 403:
                raise Exception("Google Play Games access denied - user may not have Play Games enabled")

            if resp.status_code != 200:
                logger.error(f"[GOOGLE_PLAY] API error: {resp.text[:500]}")
                raise Exception(f"Google Play Games API error: {resp.status_code}")

            data = resp.json()
            items = data.get("items", [])
            all_achievements.extend(items)

            page_token = data.get("nextPageToken")
            if not page_token:
                break

            # Safety limit
            if len(all_achievements) > 5000:
                logger.warning("[GOOGLE_PLAY] Hit 5000 achievement limit")
                break

    return all_achievements


async def get_achievement_definitions(access_token: str) -> dict:
    """
    Fetch achievement definitions (names, descriptions, icons).
    Returns dict keyed by achievement ID.
    """
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    definitions = {}
    page_token = None

    async with httpx.AsyncClient(timeout=30.0) as client:
        while True:
            params = {"maxResults": 100}
            if page_token:
                params["pageToken"] = page_token

            resp = await client.get(
                f"{GOOGLE_PLAY_GAMES_API}/achievements",
                headers=headers,
                params=params,
            )

            if resp.status_code != 200:
                logger.warning(f"[GOOGLE_PLAY] Definitions API returned {resp.status_code}")
                break

            data = resp.json()
            for item in data.get("items", []):
                definitions[item["id"]] = item

            page_token = data.get("nextPageToken")
            if not page_token:
                break

            if len(definitions) > 5000:
                break

    return definitions


def estimate_effort_from_xp(xp: int, is_incremental: bool = False) -> int:
    """
    Estimate effort score based on XP reward.

    Google Play Games uses XP as a rough indicator of difficulty.
    XP typically ranges from 5 (easy) to 200+ (hard).

    Incremental achievements (multi-step) are generally harder.
    """
    base_effort = 0

    # XP-based effort mapping
    if xp >= 200:
        base_effort = 85
    elif xp >= 100:
        base_effort = 70
    elif xp >= 50:
        base_effort = 55
    elif xp >= 25:
        base_effort = 40
    elif xp >= 10:
        base_effort = 25
    else:
        base_effort = 15

    # Incremental achievements typically require more sustained effort
    if is_incremental:
        base_effort = min(95, base_effort + 10)

    return base_effort


async def sync_google_play_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
) -> dict:
    """
    Sync Google Play Games achievements.

    Returns summary of credited achievements.
    """
    from app.services.crypto_service import decrypt_token
    token = decrypt_token(provider_account.access_token)
    if not token:
        raise Exception("No Google Play Games access token available")

    logger.info(f"[GOOGLE_PLAY] Starting achievement sync for user {user.id}")

    google_id = provider_account.provider_user_id

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch player profile (for gamertag)
    try:
        player_profile = await get_player_profile(token)
        gamertag = player_profile.get("displayName")
        if gamertag:
            provider_account.provider_username = gamertag
            provider_account.profile_data["gamertag"] = gamertag
            logger.info(f"[GOOGLE_PLAY] Player gamertag: {gamertag}")
    except Exception as e:
        logger.warning(f"[GOOGLE_PLAY] Could not fetch player profile: {e}")

    # Fetch unlocked achievements
    try:
        player_achievements = await get_player_achievements(token)
    except Exception as e:
        logger.error(f"[GOOGLE_PLAY] Failed to fetch achievements: {e}")
        raise

    logger.info(f"[GOOGLE_PLAY] Found {len(player_achievements)} unlocked achievements")

    if not player_achievements:
        provider_account.last_sync_at = datetime.utcnow()
        db.commit()
        return {
            "credited": 0,
            "details": {
                "total_achievements": 0,
                "by_rarity": {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0},
            }
        }

    # Fetch achievement definitions for names/descriptions
    try:
        definitions = await get_achievement_definitions(token)
    except Exception as e:
        logger.warning(f"[GOOGLE_PLAY] Could not fetch definitions: {e}")
        definitions = {}

    # Track stats
    total_found = len(player_achievements)
    total_credited = 0
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    for ach in player_achievements:
        ach_id = ach.get("id")
        xp = ach.get("experiencePoints", 0)
        current_steps = ach.get("currentSteps")
        is_incremental = current_steps is not None

        # Get definition if available
        definition = definitions.get(ach_id, {})
        ach_name = definition.get("name", f"Achievement {ach_id[:8]}")
        ach_desc = definition.get("description", "")
        icon_url = definition.get("unlockedIconUrl") or definition.get("revealedIconUrl")

        # Calculate effort and rarity
        effort_score = estimate_effort_from_xp(xp, is_incremental)
        rarity_tier = compute_rarity_from_effort(effort_score)

        # Track rarity
        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1

        logger.debug(f"[GOOGLE_PLAY] {ach_name} → XP={xp}, effort={effort_score} → {rarity_tier}")

        # Upsert achievement
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id="google_play", api_name=ach_id)
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id="google_play",
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
        else:
            # Update if auto-calculated
            if getattr(db_ach, "effort_auto", True):
                db_ach.effort_score = effort_score
                db_ach.rarity_tier = rarity_tier
                db_ach.name = ach_name
                db_ach.display_name = ach_name
                db_ach.description = ach_desc
                if icon_url:
                    db_ach.icon_url = icon_url
            db.commit()

        # Check for existing credit (global uniqueness check)
        existing_global = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name="google_play",
                provider_user_id=google_id,
                achievement_id=db_ach.id
            )
            .first()
        )

        if existing_global and existing_global.user_id != user.id:
            # Already claimed by different user - give display-only credit
            existing_for_user = (
                db.query(AchievementCredit)
                .filter_by(
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id
                )
                .first()
            )
            if not existing_for_user:
                credit = AchievementCredit(
                    user_id=user.id,
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id,
                    provider_name="google_play",
                    provider_user_id=google_id,
                    is_original_claim=False,
                    unlocked_at=datetime.utcnow(),
                )
                db.add(credit)
                db.commit()
                logger.info(f"[GOOGLE_PLAY] Achievement '{ach_name}' credited (display-only)")
        elif not existing_global:
            # First claim globally
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="google_play",
                provider_user_id=google_id,
                is_original_claim=True,
                unlocked_at=datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1
            logger.info(f"[GOOGLE_PLAY] Achievement '{ach_name}' credited (original claim)")
        else:
            # Already credited to this user
            logger.debug(f"[GOOGLE_PLAY] Achievement '{ach_name}' already credited")

    # Update profile data with summary
    provider_account.profile_data.update({
        "total_achievements": total_found,
        "last_sync": datetime.utcnow().isoformat(),
    })
    flag_modified(provider_account, "profile_data")

    # Update last sync time
    provider_account.last_sync_at = datetime.utcnow()
    db.commit()

    logger.info(f"[GOOGLE_PLAY] Sync complete: {total_credited} new credits from {total_found} achievements")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "by_rarity": rarity_counts,
        }
    }
