# app/services/psn_services.py
"""
PlayStation Network trophy sync via psnawp library.

Uses unofficial PSN API - user provides NPSSO token from their browser session.
Rate Limit: 300 requests per 15 minutes (library self-enforced)

Docs: https://github.com/isFakeAccount/psnawp
"""

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, Game, ProviderAccount, User
from app.services.effort_scoring import compute_psn_effort, compute_rarity_from_effort
from app.services.game_discovery_service import check_and_log_game_discovery
import logging
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)


def get_psn_client(npsso: str):
    """Create authenticated PSN client from NPSSO token."""
    from psnawp_api import PSNAWP
    return PSNAWP(npsso)


def get_psn_profile(npsso: str) -> dict:
    """Get the authenticated user's PSN profile."""
    try:
        psnawp = get_psn_client(npsso)
        client = psnawp.me()

        profile = {
            "online_id": client.online_id,
            "account_id": client.account_id,
            "avatar_url": None,
            "about_me": None,
            "plus_status": False,
        }

        # Try to get additional profile info
        try:
            profile_data = client.profile()
            profile["avatar_url"] = profile_data.get("avatarUrls", [{}])[0].get("avatarUrl") if profile_data.get("avatarUrls") else None
            profile["about_me"] = profile_data.get("aboutMe", "")
            profile["plus_status"] = profile_data.get("isPlus", False)
        except Exception as e:
            logger.warning(f"[PSN] Could not fetch extended profile: {e}")

        logger.info(f"[PSN] Profile: {profile['online_id']} (ID: {profile['account_id']})")
        return profile
    except Exception as e:
        logger.error(f"[PSN] Failed to get profile: {e}")
        raise Exception(f"PSN authentication failed: {e}")


def get_psn_trophy_titles(npsso: str) -> list:
    """Get list of games with trophies."""
    psnawp = get_psn_client(npsso)
    client = psnawp.me()

    titles = []
    try:
        # Get trophy titles (games)
        for title in client.trophy_titles():
            titles.append({
                "np_communication_id": title.np_communication_id,
                "title_name": title.title_name,
                "title_icon_url": title.title_icon_url,
                "platform": title.title_platform,
                "defined_trophies": {
                    "bronze": title.defined_trophies.bronze,
                    "silver": title.defined_trophies.silver,
                    "gold": title.defined_trophies.gold,
                    "platinum": title.defined_trophies.platinum,
                },
                "earned_trophies": {
                    "bronze": title.earned_trophies.bronze,
                    "silver": title.earned_trophies.silver,
                    "gold": title.earned_trophies.gold,
                    "platinum": title.earned_trophies.platinum,
                },
                "progress": title.progress,
            })
    except Exception as e:
        logger.error(f"[PSN] Failed to get trophy titles: {e}")
        raise

    logger.info(f"[PSN] Found {len(titles)} games with trophies")
    return titles


def get_psn_trophies_for_title(npsso: str, np_communication_id: str, platform: str) -> list:
    """Get individual trophies for a specific game."""
    psnawp = get_psn_client(npsso)
    client = psnawp.me()

    trophies = []
    try:
        # Get trophies for this title
        for trophy in client.trophies(np_communication_id=np_communication_id, platform=platform):
            trophies.append({
                "trophy_id": trophy.trophy_id,
                "trophy_name": trophy.trophy_name,
                "trophy_detail": trophy.trophy_detail,
                "trophy_type": trophy.trophy_type.name if trophy.trophy_type else "bronze",  # bronze, silver, gold, platinum
                "trophy_icon_url": trophy.trophy_icon_url,
                "earned": trophy.earned,
                "earned_date_time": trophy.earned_date_time,
                "trophy_rare": trophy.trophy_rare,  # Rarity percentage (0-100)
                "trophy_earn_rate": trophy.trophy_earn_rate,  # Percentage of players who earned it
            })
    except Exception as e:
        logger.warning(f"[PSN] Failed to get trophies for {np_communication_id}: {e}")
        return []

    return trophies


def upsert_psn_game(db: Session, provider_account: ProviderAccount, title_data: dict) -> Game:
    """Create or update a game record from PSN title data."""
    np_id = title_data["np_communication_id"]
    title_name = title_data["title_name"]
    icon_url = title_data.get("title_icon_url")

    db_game = (
        db.query(Game)
        .filter_by(provider_account_id=provider_account.id, app_id=np_id)
        .first()
    )

    if db_game:
        db_game.name = title_name
        if icon_url:
            db_game.box_art_url = icon_url
    else:
        db_game = Game(
            provider_account_id=provider_account.id,
            app_id=np_id,
            name=title_name,
            box_art_url=icon_url,
        )
        db.add(db_game)

    db.commit()
    db.refresh(db_game)
    return db_game


def sync_psn_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
    npsso: str = None,
) -> dict:
    """
    Sync PSN trophies.

    Note: This is synchronous because psnawp is a sync library.
    FastAPI will run it in a thread pool automatically.
    """
    from app.services.crypto_service import decrypt_token
    token = npsso or decrypt_token(provider_account.access_token)
    if not token:
        raise Exception("No NPSSO token available")

    logger.info(f"[PSN] Starting trophy sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch profile info
    try:
        profile = get_psn_profile(token)
        provider_account.profile_data.update({
            "online_id": profile["online_id"],
            "avatar_url": profile.get("avatar_url"),
            "about_me": profile.get("about_me"),
            "plus_status": profile.get("plus_status", False),
        })
        flag_modified(provider_account, "profile_data")
        logger.info(f"[PSN] Profile: {profile['online_id']}, PS Plus: {profile.get('plus_status')}")
    except Exception as e:
        logger.warning(f"[PSN] Failed to fetch profile: {e}")

    # Get trophy titles (games)
    try:
        titles = get_psn_trophy_titles(token)
    except Exception as e:
        logger.error(f"[PSN] Failed to get trophy titles: {e}")
        raise

    # Track total games
    provider_account.profile_data["total_games"] = len(titles)
    flag_modified(provider_account, "profile_data")

    total_found = 0
    total_credited = 0
    per_game = []
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}

    # Track trophy type totals
    trophy_totals = {"bronze": 0, "silver": 0, "gold": 0, "platinum": 0}

    for title in titles:
        np_id = title["np_communication_id"]
        title_name = title["title_name"]
        platform = title.get("platform", "PS5")

        # Check if user has any earned trophies
        earned = title.get("earned_trophies", {})
        total_earned = sum(earned.values())

        if total_earned == 0:
            continue

        # Upsert game record
        db_game = upsert_psn_game(db, provider_account, title)

        # Check if this game should be added to the Tapestry
        defined_trophies = title.get("defined_trophies", {})
        total_defined = sum(defined_trophies.values()) if isinstance(defined_trophies, dict) else 0
        check_and_log_game_discovery(
            db=db,
            provider="psn",
            game_id=np_id,
            game_name=title_name,
            achievement_count=total_defined,
            sample_achievements=None,  # Will be populated on later syncs
            user_id=user.id if user else None
        )

        # Fetch individual trophies
        logger.info(f"[PSN] Fetching {total_earned} trophies for: {title_name}")
        trophies = get_psn_trophies_for_title(token, np_id, platform)

        if not trophies:
            logger.warning(f"[PSN] No trophy details returned for {title_name}")
            continue

        found = 0
        credited = 0
        ignored = 0
        stored = 0

        for trophy in trophies:
            trophy_id = str(trophy["trophy_id"])
            trophy_name = trophy.get("trophy_name", f"Trophy {trophy_id}")
            trophy_desc = trophy.get("trophy_detail", "")
            trophy_type = trophy.get("trophy_type", "bronze").lower()
            trophy_icon = trophy.get("trophy_icon_url")
            earn_rate = trophy.get("trophy_earn_rate")  # Percentage
            is_earned = trophy.get("earned", False)

            # Compute effort score based on trophy type and rarity
            effort_score = compute_psn_effort(trophy_type=trophy_type, earn_rate=earn_rate)
            rarity_tier = compute_rarity_from_effort(effort_score)

            # Upsert achievement (store ALL trophies, not just earned)
            db_ach = (
                db.query(Achievement)
                .filter_by(app_id=np_id, api_name=trophy_id)
                .first()
            )

            if not db_ach:
                db_ach = Achievement(
                    app_id=np_id,
                    api_name=trophy_id,
                    name=trophy_name,
                    display_name=trophy_name,
                    description=trophy_desc,
                    icon_url=trophy_icon,
                    percent=earn_rate,
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
                    db_ach.percent = earn_rate
                # Update icon if we have one now
                if trophy_icon and not db_ach.icon_url:
                    db_ach.icon_url = trophy_icon
                db.commit()

            # Only credit EARNED trophies
            if not is_earned:
                continue

            found += 1

            # Track trophy type for earned only
            if trophy_type in trophy_totals:
                trophy_totals[trophy_type] += 1

            # Track rarity distribution for earned only
            if rarity_tier in rarity_counts:
                rarity_counts[rarity_tier] += 1

            # Get unlock time
            unlock_time = None
            earned_dt = trophy.get("earned_date_time")
            if earned_dt:
                try:
                    if isinstance(earned_dt, datetime):
                        unlock_time = earned_dt
                    else:
                        unlock_time = datetime.fromisoformat(str(earned_dt).replace("Z", "+00:00"))
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
                    provider_name="psn",
                    provider_user_id=provider_account.provider_user_id,
                    is_original_claim=True,
                    unlocked_at=unlock_time,
                )
                db.add(new_credit)
                credited += 1

        db.commit()

        if found > 0 or stored > 0:
            per_game.append({
                "app_id": np_id,
                "game_name": title_name,
                "total_found": found,
                "credited": credited,
                "ignored": ignored,
                "stored": stored,
            })

        total_found += found
        total_credited += credited

    # Update profile stats
    provider_account.profile_data["trophy_counts"] = trophy_totals
    flag_modified(provider_account, "profile_data")
    db.commit()

    logger.info(f"[PSN] Sync complete: {total_credited} new credits from {total_found} trophies")
    logger.info(f"[PSN] Rarity distribution: {rarity_counts}")
    logger.info(f"[PSN] Trophy types: {trophy_totals}")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": per_game,
        },
        "profile": {
            "online_id": provider_account.profile_data.get("online_id"),
            "trophy_counts": trophy_totals,
            "total_games": provider_account.profile_data.get("total_games", 0),
        }
    }
