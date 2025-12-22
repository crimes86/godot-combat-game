# app/services/discord_services.py
"""
Discord badge sync via Discord OAuth API.

Fetches user flags (badges) and creates achievement records.

Discord User Flags (bitfield):
https://discord.com/developers/docs/resources/user#user-object-user-flags
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, ProviderAccount, User
from app.services.effort_scoring import compute_discord_effort, compute_rarity_from_effort
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

DISCORD_API_BASE = "https://discord.com/api/v10"

# Discord User Flags (bit positions)
# https://discord.com/developers/docs/resources/user#user-object-user-flags
DISCORD_FLAGS = {
    0: {"name": "Discord Employee", "api_name": "STAFF", "icon": "staff"},
    1: {"name": "Partnered Server Owner", "api_name": "PARTNER", "icon": "partner"},
    2: {"name": "HypeSquad Events", "api_name": "HYPESQUAD", "icon": "hypesquad_events"},
    3: {"name": "Bug Hunter Level 1", "api_name": "BUG_HUNTER_LEVEL_1", "icon": "bug_hunter_1"},
    6: {"name": "HypeSquad Bravery", "api_name": "HYPESQUAD_BRAVERY", "icon": "hypesquad_bravery"},
    7: {"name": "HypeSquad Brilliance", "api_name": "HYPESQUAD_BRILLIANCE", "icon": "hypesquad_brilliance"},
    8: {"name": "HypeSquad Balance", "api_name": "HYPESQUAD_BALANCE", "icon": "hypesquad_balance"},
    9: {"name": "Early Supporter", "api_name": "EARLY_SUPPORTER", "icon": "early_supporter"},
    14: {"name": "Bug Hunter Level 2", "api_name": "BUG_HUNTER_LEVEL_2", "icon": "bug_hunter_2"},
    17: {"name": "Early Verified Bot Developer", "api_name": "VERIFIED_BOT_DEVELOPER", "icon": "verified_bot_dev"},
    18: {"name": "Discord Certified Moderator", "api_name": "CERTIFIED_MODERATOR", "icon": "certified_moderator"},
    22: {"name": "Active Developer", "api_name": "ACTIVE_DEVELOPER", "icon": "active_developer"},
}

# Nitro types
NITRO_TYPES = {
    0: None,  # No Nitro
    1: {"name": "Nitro Classic", "api_name": "NITRO_CLASSIC"},
    2: {"name": "Nitro", "api_name": "NITRO"},
    3: {"name": "Nitro Basic", "api_name": "NITRO_BASIC"},
}


def parse_discord_flags(flags: int) -> list:
    """Parse Discord flags bitfield into list of badge dicts."""
    badges = []
    if not flags:
        return badges

    for bit, badge_info in DISCORD_FLAGS.items():
        if flags & (1 << bit):
            badges.append(badge_info)

    return badges


async def get_discord_user(access_token: str) -> dict:
    """Fetch Discord user info including flags."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{DISCORD_API_BASE}/users/@me", headers=headers)
        logger.info(f"[DISCORD] User API status: {resp.status_code}")

        if resp.status_code == 401:
            raise Exception("Discord token expired or invalid")

        if resp.status_code != 200:
            raise Exception(f"Discord API error: {resp.status_code} - {resp.text[:200]}")

        return resp.json()


async def get_discord_connections(access_token: str) -> list:
    """Fetch user's connected accounts (Twitch, YouTube, etc.)."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{DISCORD_API_BASE}/users/@me/connections", headers=headers)
        logger.info(f"[DISCORD] Connections API status: {resp.status_code}")

        if resp.status_code != 200:
            logger.warning(f"[DISCORD] Connections failed: {resp.text[:200]}")
            return []

        return resp.json()


async def sync_discord_badges(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
) -> dict:
    """
    Sync Discord badges (user flags) as achievements.

    Returns summary of credited badges.
    """
    from app.services.crypto_service import decrypt_token
    token = decrypt_token(provider_account.access_token)
    if not token:
        raise Exception("No Discord access token available")

    logger.info(f"[DISCORD] Starting badge sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch user info
    user_info = await get_discord_user(token)

    discord_id = user_info.get("id")
    username = user_info.get("username")
    discriminator = user_info.get("discriminator", "0")
    avatar_hash = user_info.get("avatar")
    public_flags = user_info.get("public_flags", 0)
    flags = user_info.get("flags", 0)  # May include more flags
    premium_type = user_info.get("premium_type", 0)

    # Build avatar URL
    avatar_url = None
    if avatar_hash:
        avatar_url = f"https://cdn.discordapp.com/avatars/{discord_id}/{avatar_hash}.png"

    # Build display name
    if discriminator and discriminator != "0":
        display_name = f"{username}#{discriminator}"
    else:
        display_name = username

    # Update profile data
    provider_account.profile_data.update({
        "username": username,
        "discriminator": discriminator,
        "display_name": display_name,
        "avatar_url": avatar_url,
        "premium_type": premium_type,
        "public_flags": public_flags,
    })
    flag_modified(provider_account, "profile_data")

    logger.info(f"[DISCORD] Profile: {display_name}, Flags: {public_flags}, Premium: {premium_type}")

    # Fetch connections (for reference, not achievements)
    try:
        connections = await get_discord_connections(token)
        connection_types = [c.get("type") for c in connections]
        provider_account.profile_data["connections"] = connection_types
        flag_modified(provider_account, "profile_data")
        logger.info(f"[DISCORD] Connections: {connection_types}")
    except Exception as e:
        logger.warning(f"[DISCORD] Failed to fetch connections: {e}")

    # Parse badges from flags (use the larger of public_flags or flags)
    all_flags = public_flags | flags
    badges = parse_discord_flags(all_flags)

    logger.info(f"[DISCORD] Found {len(badges)} badges from flags")

    # Track stats
    total_found = len(badges)
    total_credited = 0
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    for badge in badges:
        badge_name = badge["name"]
        api_name = badge["api_name"]

        # Compute effort score
        effort_score = compute_discord_effort(badge_name)
        rarity_tier = compute_rarity_from_effort(effort_score)

        logger.info(f"[DISCORD] Badge: {badge_name} → effort={effort_score} → {rarity_tier}")

        # Track rarity
        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1

        # Upsert achievement (use "discord" as app_id for all Discord badges)
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id="discord", api_name=api_name)
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id="discord",
                api_name=api_name,
                name=badge_name,
                display_name=badge_name,
                description=f"Discord {badge_name} badge",
                icon_url=None,  # Discord doesn't provide badge icons via API
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
            db.commit()

        # Check for existing credit (global uniqueness check)
        existing_global = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name="discord",
                provider_user_id=discord_id,
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
                    provider_name="discord",
                    provider_user_id=discord_id,
                    is_original_claim=False,  # Not original - display only
                    unlocked_at=datetime.utcnow(),
                )
                db.add(credit)
                db.commit()
                logger.info(f"[DISCORD] Badge '{badge_name}' credited (display-only)")
        elif not existing_global:
            # First claim globally - this user gets original credit
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="discord",
                provider_user_id=discord_id,
                is_original_claim=True,  # Original claim!
                unlocked_at=datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1
            logger.info(f"[DISCORD] Badge '{badge_name}' credited (original claim)")
        else:
            # Already credited to this user
            logger.debug(f"[DISCORD] Badge '{badge_name}' already credited")

    # Update last sync time
    provider_account.last_sync_at = datetime.utcnow()
    db.commit()

    return {
        "provider": "discord",
        "total_found": total_found,
        "total_credited": total_credited,
        "by_rarity": rarity_counts,
    }
