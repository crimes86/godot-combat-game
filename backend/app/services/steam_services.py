
# app/services/steam_service.py

from sqlalchemy.orm import Session
from app.models import Achievement, Game
from app.models import ProviderAccount
from app.models import AchievementCredit
from app.services.steam_api import get_steam_unlocked_achievements_async  # your Steam API helper
from app.database import SessionLocal
import os

STEAM_API_KEY = os.getenv("STEAM_API_KEY")

def upsert_achievement(
    db,
    app_id,
    api_name,
    display_name,
    description,
    icon_url,
    icon_gray_url,
    hidden,
    default_value,
    percent,
    rarity_tier=None
):
    db_ach = (
        db.query(Achievement)
        .filter_by(app_id=app_id, api_name=api_name)
        .first()
    )
    if db_ach:
        db_ach.display_name = display_name
        db_ach.description = description
        db_ach.icon_url = icon_url
        db_ach.icon_gray_url = icon_gray_url
        db_ach.hidden = hidden
        db_ach.default_value = default_value
        db_ach.percent = percent
        if rarity_tier is not None:
            db_ach.rarity_tier = rarity_tier
    else:
        db_ach = Achievement(
            app_id=app_id,
            api_name=api_name,
            display_name=display_name,
            description=description,
            icon_url=icon_url,
            icon_gray_url=icon_gray_url,
            hidden=hidden,
            default_value=default_value,
            percent=percent,
            rarity_tier=rarity_tier or "Common",
        )
        db.add(db_ach)
    db.commit()
    db.refresh(db_ach)
    return db_ach

def upsert_game(db, provider_account, game_data):
    """
    game_data: dict with at least app_id, game_name, box_art_url
    """
    db_game = (
        db.query(Game)
        .filter_by(provider_account_id=provider_account.id, app_id=game_data["app_id"])
        .first()
    )
    if db_game:
        db_game.name = game_data.get("game_name", db_game.name)
        db_game.box_art_url = game_data.get("box_art_url", db_game.box_art_url)
    else:
        db_game = Game(
            provider_account_id=provider_account.id,
            app_id=game_data["app_id"],
            name=game_data.get("game_name"),
            box_art_url=game_data.get("box_art_url")
        )
        db.add(db_game)
    db.commit()
    db.refresh(db_game)
    return db_game

def upsert_user_achievement(
    db,
    user,
    provider_account,
    game,
    achievement,
    is_unlocked,
    unlock_time
):
    # This unique filter ensures no duplicate credits for same achievement/provider_account/user
    db_user_ach = (
        db.query(UserAchievement)
        .filter_by(
            user_id=user.id,
            provider_account_id=provider_account.id,
            game_id=game.id,
            achievement_id=achievement.id
        )
        .first()
    )
    # Only credit if not already exists AND unlocked!
    if not db_user_ach and is_unlocked:
        db_user_ach = UserAchievement(
            user_id=user.id,
            provider_account_id=provider_account.id,
            game_id=game.id,
            achievement_id=achievement.id,
            is_unlocked=is_unlocked,
            unlock_time=unlock_time,
        )
        db.add(db_user_ach)
        db.commit()
        db.refresh(db_user_ach)
        return True  # This was a new credit
    elif db_user_ach:
        # Already credited; never re-credit (safe!)
        # Optionally update unlock_time or is_unlocked if you want to handle edge cases
        return False
    else:
        return False

def upsert_achievement_credit(
    db,
    user,
    provider_account,
    achievement,
    unlocked_at=None,
):
    # Check if this credit already exists for this provider_account + achievement
    existing = (
        db.query(AchievementCredit)
        .filter_by(
            provider_account_id=provider_account.id,
            achievement_id=achievement.id
        )
        .first()
    )
    if existing:
        # Update unlocked_at if we have it now but didn't before
        if unlocked_at and not existing.unlocked_at:
            existing.unlocked_at = unlocked_at
            db.commit()
        return False  # Already credited, skip
    # Not credited yet, create new credit
    new_credit = AchievementCredit(
        user_id=user.id,
        provider_account_id=provider_account.id,
        achievement_id=achievement.id,
        provider_name=provider_account.provider_name,
        provider_user_id=provider_account.provider_user_id,
        is_original_claim=True,
        unlocked_at=unlocked_at,
    )
    db.add(new_credit)
    db.commit()
    db.refresh(new_credit)
    return True  # This was a new credit

async def sync_steam_achievements(user, provider_account: ProviderAccount, db: Session, steam_api_key: str) -> dict:
    grouped_games = await get_steam_unlocked_achievements_async(provider_account, steam_api_key)

    total_found = 0
    total_credited = 0
    per_game = []

    for game in grouped_games:
        upsert_game(db, provider_account, {
            "app_id": game["app_id"],
            "game_name": game["game_name"],
            "box_art_url": game["box_art_url"],
        })

        found = 0
        credited = 0
        ignored = 0

        for ach in game["achievements"]:
            # Count only UNLOCKED
            is_unlocked = ach.get("achieved", 0) == 1 or ach.get("unlocked", False)
            if is_unlocked:
                found += 1

                db_ach = (
                    db.query(Achievement)
                    .filter_by(app_id=game["app_id"], api_name=ach["api_name"])
                    .first()
                )
                if not db_ach:
                    db_ach = Achievement(
                        app_id=game["app_id"],
                        api_name=ach["api_name"],
                        name=ach.get("display_name"),
                        display_name=ach.get("display_name"),
                        description=ach.get("description"),
                        icon_url=ach.get("icon_url"),
                        icon_gray_url=ach.get("icon_gray_url"),
                        hidden=ach.get("hidden", False),
                        default_value=ach.get("default_value", 0),
                        percent=ach.get("percent"),
                        effort_score=ach.get("effort_score", 30.0),
                        effort_auto=True,
                        rarity_tier=ach.get("rarity_tier"),
                    )
                    db.add(db_ach)
                    db.commit()
                    db.refresh(db_ach)
                else:
                    # Update existing achievement with latest data
                    db_ach.percent = ach.get("percent", db_ach.percent)
                    # Only update effort_score if still auto-calculated
                    if getattr(db_ach, "effort_auto", True):
                        db_ach.effort_score = ach.get("effort_score", db_ach.effort_score)
                    db_ach.rarity_tier = ach.get("rarity_tier", db_ach.rarity_tier)
                    db.commit()

                # Get unlock time from Steam (Unix timestamp)
                unlock_time_unix = ach.get("unlock_time")
                unlocked_at = None
                if unlock_time_unix:
                    from datetime import datetime
                    unlocked_at = datetime.utcfromtimestamp(unlock_time_unix)

                was_new = upsert_achievement_credit(db, user, provider_account, db_ach, unlocked_at=unlocked_at)
                if was_new:
                    credited += 1
                else:
                    ignored += 1

        per_game.append({
            "app_id": game["app_id"],
            "game_name": game["game_name"],
            "total_found": found,
            "credited": credited,
            "ignored": ignored,
        })
        total_found += found
        total_credited += credited

    db.commit()

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": per_game,
        }
    }

