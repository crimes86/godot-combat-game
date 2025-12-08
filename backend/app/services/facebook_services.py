# app/services/facebook_services.py
"""
Facebook achievement sync via Facebook Graph API.

Creates achievements based on Facebook social metrics:
- Friend count (only reliable metric available)

Note: Facebook has very limited data available via Graph API:
- Account creation date: NOT exposed
- Follower count: Deprecated since API v2.0 (2014)
- Gaming achievements: Facebook Gaming shut down Oct 2024

This provider is primarily a "login gateway" for frictionless onboarding.
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, ProviderAccount, User
from app.services.effort_scoring import compute_facebook_effort, compute_rarity_from_effort
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

FACEBOOK_API_BASE = "https://graph.facebook.com/v19.0"

# Facebook activity-based achievements
# Based on friend count (only reliable metric available)
FACEBOOK_ACHIEVEMENTS = {
    "friends": {
        "name": "Social Network",
        "description": "Facebook friends connected",
        "tiers": [
            {"threshold": 4000, "tier": "gold", "effort": 70, "suffix": "4000+ Friends"},
            {"threshold": 2000, "tier": "silver", "effort": 55, "suffix": "2000+ Friends"},
            {"threshold": 1000, "tier": "bronze", "effort": 40, "suffix": "1000+ Friends"},
            {"threshold": 500, "tier": "default", "effort": 30, "suffix": "500+ Friends"},
            {"threshold": 200, "tier": "starter", "effort": 20, "suffix": "200+ Friends"},
        ]
    },
}


async def get_facebook_user(access_token: str) -> dict:
    """Fetch Facebook user info including friend count."""
    params = {
        "fields": "id,name,first_name,last_name,picture,email,friends.summary(true)",
        "access_token": access_token,
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{FACEBOOK_API_BASE}/me", params=params)
        logger.info(f"[FACEBOOK] User API status: {resp.status_code}")

        if resp.status_code == 401:
            raise Exception("Facebook token expired or invalid")

        if resp.status_code != 200:
            error_data = resp.json() if resp.text else {}
            error_msg = error_data.get("error", {}).get("message", resp.text[:200])
            raise Exception(f"Facebook API error: {resp.status_code} - {error_msg}")

        return resp.json()


def get_achievement_tier(metric_name: str, value: float) -> dict:
    """Get the highest tier achieved for a given metric."""
    achievement_def = FACEBOOK_ACHIEVEMENTS.get(metric_name)
    if not achievement_def:
        return None

    for tier in achievement_def["tiers"]:
        if value >= tier["threshold"]:
            return {
                "identifier": f"{metric_name}_{tier['tier']}",
                "name": achievement_def["name"],
                "display_name": f"{achievement_def['name']} ({tier['suffix']})",
                "description": f"{achievement_def['description']}: {tier['suffix']}",
                "tier": tier["tier"],
                "effort": tier["effort"],
                "value": value,
            }

    return None


async def sync_facebook_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
) -> dict:
    """
    Sync Facebook activity-based achievements.

    Returns summary of credited achievements.
    """
    token = provider_account.access_token
    if not token:
        raise Exception("No Facebook access token available")

    logger.info(f"[FACEBOOK] Starting achievement sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch user info
    user_info = await get_facebook_user(token)

    facebook_id = str(user_info.get("id"))
    name = user_info.get("name")
    first_name = user_info.get("first_name")
    last_name = user_info.get("last_name")
    email = user_info.get("email")

    # Extract picture URL
    picture_data = user_info.get("picture", {}).get("data", {})
    avatar_url = picture_data.get("url")

    # Extract friend count from summary
    # The friends.summary(true) field returns: {"data": [...], "summary": {"total_count": N}}
    friends_data = user_info.get("friends", {})
    friend_count = friends_data.get("summary", {}).get("total_count", 0)

    logger.info(f"[FACEBOOK] Profile: {name} (ID: {facebook_id})")
    logger.info(f"[FACEBOOK] Stats: Friends={friend_count}")

    # Update profile data
    provider_account.profile_data.update({
        "name": name,
        "first_name": first_name,
        "last_name": last_name,
        "email": email,
        "avatar_url": avatar_url,
        "friend_count": friend_count,
    })
    flag_modified(provider_account, "profile_data")

    # Calculate achievements based on metrics
    metrics = {
        "friends": friend_count,
    }

    achievements = []
    for metric_name, value in metrics.items():
        tier_info = get_achievement_tier(metric_name, value)
        if tier_info:
            achievements.append(tier_info)
            logger.info(f"[FACEBOOK] Achievement: {tier_info['display_name']} (value={value})")

    logger.info(f"[FACEBOOK] Found {len(achievements)} achievements based on activity")

    # Track stats
    total_found = len(achievements)
    total_credited = 0
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    for ach in achievements:
        identifier = ach["identifier"]
        ach_name = ach["name"]
        display_name = ach["display_name"]
        ach_desc = ach["description"]
        effort_score = ach["effort"]

        rarity_tier = compute_rarity_from_effort(effort_score)

        logger.info(f"[FACEBOOK] {display_name} -> effort={effort_score} -> {rarity_tier}")

        # Track rarity
        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1

        # Upsert achievement (use "facebook" as app_id)
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id="facebook", api_name=identifier)
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id="facebook",
                api_name=identifier,
                name=ach_name,
                display_name=display_name,
                description=ach_desc,
                icon_url=None,
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
                db_ach.display_name = display_name
                db_ach.description = ach_desc
            db.commit()

        # Check for existing credit (global uniqueness check)
        existing_global = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name="facebook",
                provider_user_id=facebook_id,
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
                    provider_name="facebook",
                    provider_user_id=facebook_id,
                    is_original_claim=False,
                    unlocked_at=datetime.utcnow(),
                )
                db.add(credit)
                db.commit()
                logger.info(f"[FACEBOOK] Achievement '{display_name}' credited (display-only)")
        elif not existing_global:
            # First claim globally
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="facebook",
                provider_user_id=facebook_id,
                is_original_claim=True,
                unlocked_at=datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1
            logger.info(f"[FACEBOOK] Achievement '{display_name}' credited (original claim)")
        else:
            # Already credited to this user
            logger.debug(f"[FACEBOOK] Achievement '{display_name}' already credited")

    # Update last sync time
    provider_account.last_sync_at = datetime.utcnow()
    db.commit()

    return {
        "provider": "facebook",
        "total_found": total_found,
        "total_credited": total_credited,
        "by_rarity": rarity_counts,
    }
