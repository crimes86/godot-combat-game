# app/services/roblox_services.py
"""
Roblox badge sync via Roblox Open Cloud API.

Syncs user badges with full rarity data (winRatePercentage).
Also creates tenure achievements based on account age.

Roblox OAuth 2.0 docs: https://create.roblox.com/docs/cloud/open-cloud/oauth2-overview
Badges API docs: https://create.roblox.com/docs/cloud/legacy/badges/v1
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, ProviderAccount, User, Game
from app.services.effort_scoring import (
    compute_roblox_effort,
    compute_roblox_tenure_effort,
    compute_rarity_from_effort,
)
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

ROBLOX_API_BASE = "https://apis.roblox.com"
ROBLOX_BADGES_API = "https://badges.roblox.com"
ROBLOX_USERS_API = "https://users.roblox.com"
ROBLOX_GAMES_API = "https://games.roblox.com"
ROBLOX_THUMBNAILS_API = "https://thumbnails.roblox.com"

# Tenure achievements (derived from account age)
ROBLOX_TENURE_ACHIEVEMENTS = {
    "tenure": {
        "name": "Roblox Veteran",
        "description": "Years on Roblox",
        "tiers": [
            {"threshold": 10, "tier": "legendary", "effort": 85, "suffix": "10+ Years (OG)"},
            {"threshold": 7, "tier": "epic", "effort": 65, "suffix": "7+ Years"},
            {"threshold": 5, "tier": "rare", "effort": 45, "suffix": "5+ Years"},
            {"threshold": 3, "tier": "uncommon", "effort": 30, "suffix": "3+ Years"},
            {"threshold": 1, "tier": "common", "effort": 15, "suffix": "1+ Year"},
        ]
    },
}


async def get_roblox_user_info(access_token: str) -> dict:
    """Fetch Roblox user info via OAuth userinfo endpoint."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{ROBLOX_API_BASE}/oauth/v1/userinfo",
            headers=headers,
        )
        logger.info(f"[ROBLOX] UserInfo API status: {resp.status_code}")

        if resp.status_code == 401:
            raise Exception("Roblox token expired or invalid")

        if resp.status_code != 200:
            raise Exception(f"Roblox API error: {resp.status_code} - {resp.text[:200]}")

        return resp.json()


async def get_roblox_user_badges(user_id: str, limit: int = 100) -> list:
    """
    Fetch all badges for a Roblox user.

    Uses the public badges API (no auth required for public profiles).
    Paginates through all results.
    """
    all_badges = []
    cursor = None

    async with httpx.AsyncClient() as client:
        while True:
            params = {"limit": limit, "sortOrder": "Asc"}
            if cursor:
                params["cursor"] = cursor

            resp = await client.get(
                f"{ROBLOX_BADGES_API}/v1/users/{user_id}/badges",
                params=params,
            )

            if resp.status_code != 200:
                logger.warning(f"[ROBLOX] Badges API error: {resp.status_code}")
                break

            data = resp.json()
            badges = data.get("data", [])
            all_badges.extend(badges)

            cursor = data.get("nextPageCursor")
            if not cursor:
                break

            # Safety limit
            if len(all_badges) >= 1000:
                logger.info(f"[ROBLOX] Reached 1000 badge limit, stopping pagination")
                break

    return all_badges


async def get_badge_details(badge_id: int) -> dict:
    """Fetch detailed badge info including statistics."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{ROBLOX_BADGES_API}/v1/badges/{badge_id}")

        if resp.status_code != 200:
            return None

        return resp.json()


async def get_badge_awarded_dates(user_id: str, badge_ids: list) -> dict:
    """Fetch awarded dates for a list of badges."""
    if not badge_ids:
        return {}

    async with httpx.AsyncClient() as client:
        # API accepts comma-separated badge IDs
        badge_ids_str = ",".join(str(bid) for bid in badge_ids[:100])  # Limit to 100
        resp = await client.get(
            f"{ROBLOX_BADGES_API}/v1/users/{user_id}/badges/awarded-dates",
            params={"badgeIds": badge_ids_str},
        )

        if resp.status_code != 200:
            return {}

        data = resp.json().get("data", [])
        return {item["badgeId"]: item["awardedDate"] for item in data}


async def get_universe_info(universe_id: int) -> dict:
    """Fetch game/universe info."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{ROBLOX_GAMES_API}/v1/games",
            params={"universeIds": str(universe_id)},
        )

        if resp.status_code != 200:
            return None

        data = resp.json().get("data", [])
        return data[0] if data else None


async def get_game_icon(universe_id: int) -> str:
    """Fetch game icon URL."""
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{ROBLOX_THUMBNAILS_API}/v1/games/icons",
            params={
                "universeIds": str(universe_id),
                "size": "150x150",
                "format": "Png",
                "isCircular": "false",
            },
        )

        if resp.status_code != 200:
            return None

        data = resp.json().get("data", [])
        if data and data[0].get("state") == "Completed":
            return data[0].get("imageUrl")
        return None


def calculate_account_age_years(created_at_timestamp: int) -> float:
    """Calculate account age in years from Unix timestamp."""
    if not created_at_timestamp:
        return 0

    try:
        created = datetime.fromtimestamp(created_at_timestamp)
        now = datetime.now()
        delta = now - created
        return delta.days / 365.25
    except (ValueError, OSError):
        return 0


def get_tenure_achievement(account_age_years: float) -> dict:
    """Get tenure achievement tier based on account age."""
    achievement_def = ROBLOX_TENURE_ACHIEVEMENTS["tenure"]

    for tier in achievement_def["tiers"]:
        if account_age_years >= tier["threshold"]:
            return {
                "identifier": f"tenure_{tier['tier']}",
                "name": achievement_def["name"],
                "display_name": f"{achievement_def['name']} ({tier['suffix']})",
                "description": f"{achievement_def['description']}: {tier['suffix']}",
                "tier": tier["tier"],
                "effort": tier["effort"],
                "value": account_age_years,
            }

    return None


async def sync_roblox_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
) -> dict:
    """
    Sync Roblox badges as achievements.

    - Fetches user profile via OAuth
    - Fetches all badges via public API
    - Uses winRatePercentage for rarity scoring
    - Creates tenure achievement from account age

    Returns summary of credited achievements.
    """
    token = provider_account.access_token
    if not token:
        raise Exception("No Roblox access token available")

    logger.info(f"[ROBLOX] Starting achievement sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch user info via OAuth
    user_info = await get_roblox_user_info(token)

    roblox_id = str(user_info.get("sub"))
    display_name = user_info.get("name") or user_info.get("nickname")
    username = user_info.get("preferred_username")
    created_at = user_info.get("created_at")  # Unix timestamp
    profile_url = user_info.get("profile")
    avatar_url = user_info.get("picture")

    # Calculate account age
    account_age_years = calculate_account_age_years(created_at)

    logger.info(f"[ROBLOX] Profile: {display_name} (@{username}), ID: {roblox_id}")
    logger.info(f"[ROBLOX] Account age: {account_age_years:.1f} years")

    # Update profile data
    provider_account.profile_data.update({
        "roblox_id": roblox_id,
        "display_name": display_name,
        "username": username,
        "avatar_url": avatar_url,
        "profile_url": profile_url,
        "created_at": created_at,
        "account_age_years": round(account_age_years, 1),
    })
    flag_modified(provider_account, "profile_data")

    # Fetch user badges
    badges = await get_roblox_user_badges(roblox_id)
    logger.info(f"[ROBLOX] Found {len(badges)} badges")

    # Get awarded dates for badges
    badge_ids = [b.get("id") for b in badges if b.get("id")]
    awarded_dates = {}

    # Fetch in batches of 100
    for i in range(0, len(badge_ids), 100):
        batch = badge_ids[i:i+100]
        batch_dates = await get_badge_awarded_dates(roblox_id, batch)
        awarded_dates.update(batch_dates)

    # Track stats
    total_found = len(badges)
    total_credited = 0
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    # Track games we've seen for Game records
    seen_universes = {}

    for badge in badges:
        badge_id = badge.get("id")
        badge_name = badge.get("name", "")
        badge_display_name = badge.get("displayName", badge_name)
        badge_description = badge.get("description", "")
        icon_image_id = badge.get("iconImageId")

        # Get awarding universe (game) info
        awarding_universe = badge.get("awardingUniverse", {})
        universe_id = awarding_universe.get("id")
        universe_name = awarding_universe.get("name", "Unknown Game")

        # Get statistics (contains rarity!)
        statistics = badge.get("statistics", {})
        win_rate = statistics.get("winRatePercentage")
        awarded_count = statistics.get("awardedCount", 0)

        # Get awarded date
        awarded_date_str = awarded_dates.get(badge_id)
        unlocked_at = None
        if awarded_date_str:
            try:
                unlocked_at = datetime.fromisoformat(awarded_date_str.replace("Z", "+00:00"))
            except ValueError:
                pass

        # Compute effort score from win rate (like Steam's global %)
        effort_score = compute_roblox_effort(win_rate)
        rarity_tier = compute_rarity_from_effort(effort_score)

        logger.debug(f"[ROBLOX] Badge: {badge_display_name} | win_rate={win_rate}% -> effort={effort_score} -> {rarity_tier}")

        # Track rarity
        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1

        # Build icon URL
        icon_url = None
        if icon_image_id:
            icon_url = f"https://www.roblox.com/asset-thumbnail/image?assetId={icon_image_id}&width=150&height=150&format=png"

        # Create/update Game record for the universe
        if universe_id and universe_id not in seen_universes:
            db_game = (
                db.query(Game)
                .filter_by(provider_account_id=provider_account.id, app_id=str(universe_id))
                .first()
            )
            if not db_game:
                # Fetch game icon
                game_icon = await get_game_icon(universe_id)
                db_game = Game(
                    provider_account_id=provider_account.id,
                    app_id=str(universe_id),
                    name=universe_name,
                    box_art_url=game_icon,
                )
                db.add(db_game)
                db.commit()
                db.refresh(db_game)
            seen_universes[universe_id] = db_game

        # Upsert achievement
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id=str(universe_id) if universe_id else "roblox", api_name=str(badge_id))
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id=str(universe_id) if universe_id else "roblox",
                api_name=str(badge_id),
                name=badge_name,
                display_name=badge_display_name,
                description=badge_description,
                icon_url=icon_url,
                percent=win_rate,
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
                db_ach.percent = win_rate
                db_ach.effort_score = effort_score
                db_ach.rarity_tier = rarity_tier
                db_ach.icon_url = icon_url
            db.commit()

        # Check for existing credit (anti-exploit)
        existing_global = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name="roblox",
                provider_user_id=roblox_id,
                achievement_id=db_ach.id
            )
            .first()
        )

        if existing_global and existing_global.user_id != user.id:
            # Already claimed by different user - display only
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
                    provider_name="roblox",
                    provider_user_id=roblox_id,
                    is_original_claim=False,
                    unlocked_at=unlocked_at or datetime.utcnow(),
                )
                db.add(credit)
                db.commit()
        elif not existing_global:
            # First claim globally
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="roblox",
                provider_user_id=roblox_id,
                is_original_claim=True,
                unlocked_at=unlocked_at or datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1

    # Add tenure achievement
    tenure_ach = get_tenure_achievement(account_age_years)
    if tenure_ach:
        logger.info(f"[ROBLOX] Tenure achievement: {tenure_ach['display_name']}")

        effort_score = tenure_ach["effort"]
        rarity_tier = compute_rarity_from_effort(effort_score)

        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1
        total_found += 1

        # Upsert tenure achievement
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id="roblox", api_name=tenure_ach["identifier"])
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id="roblox",
                api_name=tenure_ach["identifier"],
                name=tenure_ach["name"],
                display_name=tenure_ach["display_name"],
                description=tenure_ach["description"],
                icon_url=None,
                effort_score=effort_score,
                effort_auto=True,
                rarity_tier=rarity_tier,
            )
            db.add(db_ach)
            db.commit()
            db.refresh(db_ach)

        # Credit tenure achievement
        existing_global = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name="roblox",
                provider_user_id=roblox_id,
                achievement_id=db_ach.id
            )
            .first()
        )

        if not existing_global:
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="roblox",
                provider_user_id=roblox_id,
                is_original_claim=True,
                unlocked_at=datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1

    # Update last sync time
    provider_account.last_sync_at = datetime.utcnow()
    db.commit()

    logger.info(f"[ROBLOX] Sync complete: {total_found} found, {total_credited} credited")
    logger.info(f"[ROBLOX] By rarity: {rarity_counts}")

    return {
        "provider": "roblox",
        "total_found": total_found,
        "total_credited": total_credited,
        "by_rarity": rarity_counts,
    }
