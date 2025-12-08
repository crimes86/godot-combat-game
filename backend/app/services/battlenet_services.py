
# app/services/battlenet_service.py

import httpx
import logging
import json
from sqlalchemy.orm import Session
from app.models import AchievementCredit, Game, Achievement
from app.models import ProviderAccount
from app.models import User
from app.database import SessionLocal
from datetime import datetime
import os
from app.services.effort_scoring import compute_battlenet_effort, compute_rarity_from_effort

logger = logging.getLogger(__name__)

BATTLENET_API_KEY = os.environ.get("BATTLENET_API_KEY")

# Load WoW achievement database for accurate point/category lookup
WOW_ACHIEVEMENT_DB = {}
try:
    db_path = os.path.join(os.path.dirname(__file__), "..", "data", "wow_achievements.json")
    if os.path.exists(db_path):
        with open(db_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            WOW_ACHIEVEMENT_DB = data.get("achievements", {})
            logger.info(f"[BNET] Loaded {len(WOW_ACHIEVEMENT_DB)} WoW achievements from database")
except Exception as e:
    logger.warning(f"[BNET] Failed to load WoW achievement database: {e}")


def get_wow_achievement_info(ach_id: int) -> dict:
    """Look up achievement info from static database."""
    return WOW_ACHIEVEMENT_DB.get(str(ach_id), {})


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
    """
    Credit an achievement with anti-exploit global claim tracking.

    Uses (provider_name, provider_user_id, achievement_id) as global key
    to prevent duplicate Mantle credits when users unlink/relink accounts.
    """
    # Check for GLOBAL claim (same provider identity + achievement)
    existing_global = (
        db.query(AchievementCredit)
        .filter_by(
            provider_name=provider_account.provider_name,
            provider_user_id=provider_account.provider_user_id,
            achievement_id=achievement.id
        )
        .first()
    )

    if existing_global:
        if existing_global.provider_account_id == provider_account.id:
            return False  # Already credited to this exact provider_account
        else:
            # Reclaim scenario: update to new owner but mark as display-only
            existing_global.provider_account_id = provider_account.id
            existing_global.user_id = user.id
            existing_global.is_original_claim = False
            db.commit()
            return 'reclaimed'

    # First-time claim: create new credit with anti-exploit fields
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

BNET_API_BASE = "https://us.api.blizzard.com"


# classify_achievement_effort moved to app/services/effort_scoring.py
# Use compute_battlenet_effort() instead


async def get_bnet_characters(token):
    headers = {"Authorization": f"Bearer {token}"}
    url = "https://us.api.blizzard.com/profile/user/wow?namespace=profile-us&locale=en_US"
  # Use your actual endpoint!
    print("Using Battle.net access token:", token)
    async with httpx.AsyncClient() as client:
        resp = await client.get(url, headers=headers)
        print("Battle.net Characters API status:", resp.status_code)
        print("Battle.net Characters API response:", resp.text[:500])
        print("Headers sent:", headers)

        if resp.status_code != 200:
            raise Exception(f"Battle.net API error: {resp.status_code} - {resp.text[:200]}")
        try:
            data = resp.json()
        except Exception:
            print("Failed to parse JSON from Battle.net API response:", resp.text[:500])
            raise
        return data.get("wow_accounts", [])


async def get_character_achievements(realm_slug, character_name, token):
    """Fetch character's completed achievements."""
    url = f"{BNET_API_BASE}/profile/wow/character/{realm_slug}/{character_name.lower()}/achievements"
    headers = {"Authorization": f"Bearer {token}"}
    params = {"namespace": "profile-us", "locale": "en_US"}

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=headers, params=params)

            # Handle 404 (character not found or no achievements) gracefully
            if resp.status_code == 404:
                logger.info(f"[BNET] {character_name}: No achievement data (404)")
                return []

            if resp.status_code != 200:
                logger.warning(f"[BNET] {character_name}: API error {resp.status_code}")
                return []

            raw_achievements = resp.json().get("achievements", [])
    except httpx.TimeoutException:
        logger.warning(f"[BNET] {character_name}: Request timed out")
        return []
    except Exception as e:
        logger.warning(f"[BNET] {character_name}: Error fetching achievements: {e}")
        return []

    logger.info(f"[BNET] {character_name}: {len(raw_achievements)} achievements found")

    # Return achievements with basic data (no per-achievement API calls for speed)
    # Points will be estimated based on achievement ID ranges or default values
    enriched = []
    for ach in raw_achievements:
        ach_id = ach.get("id")
        if not ach_id:
            continue

        # Get name from nested achievement object
        ach_name = ach.get("achievement", {}).get("name", f"Achievement {ach_id}")

        # Estimate points based on achievement - most WoW achievements are 10 points
        # We'll use a default and let manual overrides handle special cases
        default_points = 10

        enriched.append({
            "id": ach_id,
            "name": ach_name,
            "description": "",  # Not available without extra API call
            "points": default_points,
            "category": "",
            "is_feat_of_strength": False,  # Can't determine without extra API call
            "is_legacy": False,
            "icon": None,
            "completed_timestamp": ach.get("completed_timestamp"),
        })

    return enriched


async def sync_battlenet_achievements(
    user: User, provider_account: ProviderAccount, db: Session,
    bnet_api_key: str = None, token: str = None
) -> dict:
    characters_data = await get_bnet_characters(token or provider_account.access_token)
    total_credited = 0
    total_found = 0
    per_character = []

    # Ensure WoW game record exists for this provider account
    wow_game = db.query(Game).filter_by(
        provider_account_id=provider_account.id,
        app_id="wow"
    ).first()
    if not wow_game:
        wow_game = Game(
            provider_account_id=provider_account.id,
            app_id="wow",
            name="World of Warcraft",
            box_art_url="https://blz-contentstack-images.akamaized.net/v3/assets/blt3452e3b114fab0cd/bltc669be1d4fc93f53/651c05bf6f5af95e6db4e0a3/WoW_Anniversary_Editions_Cover_Art.png"
        )
        db.add(wow_game)
        db.commit()
        logger.info(f"[BNET] Created WoW game record for provider_account {provider_account.id}")

    for account in characters_data:
        for char in account.get("characters", []):
            realm = char.get("realm", {}).get("slug")
            name = char.get("name")
            avatar_url = char.get("avatar_url") or char.get("thumb_url") or None

            # Fetch and normalize this character's achievements
            raw_achievements = await get_character_achievements(realm, name, token or provider_account.access_token)
            achievements = []
            found = 0
            credited = 0
            ignored = 0

            for ach in raw_achievements:
                found += 1
                ext_ach_id = str(ach.get("id"))
                ach_id_int = ach.get("id")

                # Look up achievement details from our static database
                wow_info = get_wow_achievement_info(ach_id_int)

                # Build achievement data for effort calculation
                ach_data = {
                    "points": wow_info.get("points", ach.get("points", 10)),
                    "is_feat_of_strength": wow_info.get("is_feat_of_strength", False),
                    "is_legacy": wow_info.get("is_legacy", False),
                    "category": wow_info.get("category", ""),
                }

                effort = compute_battlenet_effort(ach_data)
                rarity_tier = compute_rarity_from_effort(effort)

                # Use name/description/icon from lookup if available
                ach_name = wow_info.get("name") or ach.get("name", f"Achievement {ext_ach_id}")
                ach_desc = wow_info.get("description") or ach.get("description", "")
                ach_icon = wow_info.get("icon_url") or ach.get("icon")

                # Upsert local Achievement in your DB with effort logic
                # First check for existing achievement (with or without app_id for backwards compat)
                db_ach = db.query(Achievement).filter_by(app_id="wow", api_name=ext_ach_id).first()
                if not db_ach:
                    # Check for legacy achievement without app_id
                    db_ach = db.query(Achievement).filter_by(api_name=ext_ach_id).filter(
                        (Achievement.app_id == None) | (Achievement.app_id == "")
                    ).first()
                    if db_ach:
                        # Migrate legacy achievement to have app_id
                        db_ach.app_id = "wow"
                        logger.info(f"[BNET] Migrated legacy achievement {ext_ach_id} to app_id='wow'")

                if not db_ach:
                    db_ach = Achievement(
                        app_id="wow",
                        api_name=ext_ach_id,
                        name=ach_name,
                        display_name=ach_name,
                        description=ach_desc,
                        icon_url=ach_icon,
                        effort_score=effort,
                        effort_auto=True,
                        rarity_tier=rarity_tier,
                    )
                    db.add(db_ach)
                    db.commit()
                    db.refresh(db_ach)
                else:
                    # Only update effort if still auto
                    if getattr(db_ach, "effort_auto", True):
                        db_ach.effort_score = effort
                        db_ach.rarity_tier = rarity_tier
                        db_ach.effort_auto = True
                    # Update name/description from lookup if we have better data
                    if wow_info.get("name") and db_ach.name != wow_info["name"]:
                        db_ach.name = wow_info["name"]
                        db_ach.display_name = wow_info["name"]
                    if wow_info.get("description") and not db_ach.description:
                        db_ach.description = wow_info["description"]
                    # Always update icon if we have one from database
                    if ach_icon and not db_ach.icon_url:
                        db_ach.icon_url = ach_icon

                # Get unlock time from WoW API (timestamp in milliseconds)
                unlocked_at = None
                completed_timestamp = ach.get("completed_timestamp")
                if completed_timestamp:
                    from datetime import datetime
                    # WoW API returns milliseconds since epoch
                    unlocked_at = datetime.utcfromtimestamp(completed_timestamp / 1000)

                # Credit
                already = db.query(AchievementCredit).filter_by(
                    user_id=user.id,
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id
                ).first()
                if already:
                    # Update unlocked_at if we have it now but didn't before
                    if unlocked_at and not already.unlocked_at:
                        already.unlocked_at = unlocked_at
                        db.commit()
                    ignored += 1
                else:
                    credit = AchievementCredit(
                        user_id=user.id,
                        provider_account_id=provider_account.id,
                        character_name=name,  # Optionally, store which char first unlocked it
                        achievement_id=db_ach.id,
                        provider_name=provider_account.provider_name,
                        provider_user_id=provider_account.provider_user_id,
                        is_original_claim=True,
                        unlocked_at=unlocked_at,
                    )
                    db.add(credit)
                    credited += 1

                # Normalize for frontend modal
                achievements.append({
                    "id": ach.get("id"),
                    "display_name": ach.get("name", f"Achievement {ach.get('id')}"),
                    "description": ach.get("description", ""),
                    "icon_url": ach.get("icon") or "/static/icons/trophy.png",
                    "percent": ach.get("percent"),
                    "unlocked": True,
                    "effort_score": effort,
                    "effort_auto": getattr(db_ach, "effort_auto", True),
                    "unlocked_at": unlocked_at.isoformat() if unlocked_at else None,
                    "rarity_tier": rarity_tier,
                })

            # PATCH: skip any character with no achievements
            if not achievements:
                continue

            per_character.append({
                "character_name": name,
                "realm": realm,
                "avatar_url": avatar_url,
                "total_found": found,
                "credited": credited,
                "ignored": ignored,
                "achievements": achievements,
            })

            total_found += found
            total_credited += credited

    # Set top character in provider profile data
    if per_character:
        top_char = max(per_character, key=lambda c: c["credited"], default=None)
        if top_char:
            provider_account.profile_data = provider_account.profile_data or {}
            provider_account.profile_data["top_character"] = {
                "name": top_char["character_name"],
                "realm": top_char["realm"],
                "avatar_url": top_char.get("avatar_url"),
                "credited": top_char["credited"],
            }

    db.commit()
    # Note: Don't close db here - caller owns the session

    # The return format for the frontend route should be just `per_character`
    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": per_character,
        }
    }







