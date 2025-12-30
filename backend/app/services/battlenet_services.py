
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

# Load D3 achievement database (may be empty if API not available)
D3_ACHIEVEMENT_DB = {}
try:
    db_path = os.path.join(os.path.dirname(__file__), "..", "data", "d3_achievements.json")
    if os.path.exists(db_path):
        with open(db_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            D3_ACHIEVEMENT_DB = data.get("achievements", {})
            logger.info(f"[BNET] Loaded {len(D3_ACHIEVEMENT_DB)} D3 achievements from database")
except Exception as e:
    logger.warning(f"[BNET] Failed to load D3 achievement database: {e}")


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
    to prevent duplicate Ashbane credits when users unlink/relink accounts.
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
    from app.services.crypto_service import decrypt_token
    effective_token = token or decrypt_token(provider_account.access_token)
    characters_data = await get_bnet_characters(effective_token)
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
            raw_achievements = await get_character_achievements(realm, name, effective_token)
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
                    # Always update icon from database (ensures existing achievements get icons)
                    if ach_icon:
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


# ============================================================================
# DIABLO 3 SYNC
# ============================================================================


def get_d3_achievement_info(ach_id: int) -> dict:
    """Look up D3 achievement info from static database."""
    return D3_ACHIEVEMENT_DB.get(str(ach_id), {})


async def get_d3_career_profile(battletag: str, token: str) -> dict:
    """
    Fetch D3 career profile for a BattleTag.
    The battletag format is Name#1234, converted to Name-1234 for the URL.
    """
    # Convert battletag format: Name#1234 -> Name-1234
    battletag_url = battletag.replace("#", "-")
    headers = {"Authorization": f"Bearer {token}"}
    url = f"{BNET_API_BASE}/d3/profile/{battletag_url}/"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=headers)

            if resp.status_code == 404:
                logger.info(f"[BNET-D3] No D3 profile for {battletag}")
                return {}

            if resp.status_code != 200:
                logger.warning(f"[BNET-D3] API error {resp.status_code}: {resp.text[:200]}")
                return {}

            return resp.json()
    except httpx.TimeoutException:
        logger.warning(f"[BNET-D3] Request timed out for {battletag}")
        return {}
    except Exception as e:
        logger.warning(f"[BNET-D3] Error fetching profile: {e}")
        return {}


def compute_d3_effort(ach_data: dict) -> float:
    """
    Compute effort score for a Diablo 3 achievement.
    D3 achievements have point values: 10-50 typically.
    """
    points = ach_data.get("points", 10)
    category = ach_data.get("category", "").lower()

    # Base score from points (D3 achievements: 10-50 points typically)
    if points >= 50:
        base = 80
    elif points >= 30:
        base = 60
    elif points >= 20:
        base = 45
    elif points >= 10:
        base = 30
    else:
        base = 20

    # Category bonuses
    if "hardcore" in category:
        base += 20  # Hardcore achievements are harder
    if "conquest" in category:
        base += 15  # Season conquests are challenging
    if "boss" in category or "greater rift" in category:
        base += 10

    return min(100.0, base)


async def sync_d3_achievements(
    user: User, provider_account: ProviderAccount, db: Session,
    token: str = None
) -> dict:
    """
    Sync Diablo 3 achievements for a Battle.net account.
    """
    from app.services.crypto_service import decrypt_token
    token = token or decrypt_token(provider_account.access_token)

    # BattleTag is stored in provider_username (e.g., "Player#1234"), not provider_user_id (numeric)
    battletag = provider_account.provider_username
    if not battletag or "#" not in battletag:
        # Try profile_data as fallback
        profile_data = provider_account.profile_data or {}
        battletag = profile_data.get("battletag")

    if not battletag or "#" not in battletag:
        logger.warning(f"[BNET-D3] No valid battletag found (provider_username={provider_account.provider_username})")
        return {"credited": 0, "details": {"total_achievements": 0, "per_game": []}}

    profile = await get_d3_career_profile(battletag, token)

    if not profile:
        return {"credited": 0, "details": {"total_achievements": 0, "per_game": []}}

    # Check if player has D3 data
    if not profile.get("heroes") and not profile.get("paragonLevel"):
        logger.info(f"[BNET-D3] {battletag}: No D3 data found")
        return {"credited": 0, "details": {"total_achievements": 0, "per_game": []}}

    # Ensure D3 game record exists for this provider account
    d3_game = db.query(Game).filter_by(
        provider_account_id=provider_account.id,
        app_id="d3"
    ).first()
    if not d3_game:
        d3_game = Game(
            provider_account_id=provider_account.id,
            app_id="d3",
            name="Diablo III",
            box_art_url="https://blz-contentstack-images.akamaized.net/v3/assets/blt0e00eb71333df64e/blt92aa75a9e8eb3227/64f06f3fa4e5a04a45a38c42/d3-icon.png"
        )
        db.add(d3_game)
        db.commit()
        logger.info(f"[BNET-D3] Created D3 game record for {battletag}")

    # D3 career profile returns achievements as nested structure
    # achievements: { code: "123", name: "...", ... }
    achievements_data = profile.get("achievements", {})
    completed = achievements_data.get("complete", [])

    total_found = len(completed)
    total_credited = 0
    achievements = []

    for ach in completed:
        ach_id = ach.get("id")
        if not ach_id:
            continue

        ext_ach_id = f"d3_{ach_id}"  # Prefix to avoid collision with WoW

        # Look up from static database
        d3_info = get_d3_achievement_info(ach_id)

        ach_data = {
            "points": d3_info.get("points", ach.get("points", 10)),
            "category": d3_info.get("category", ach.get("category", "")),
        }

        effort = compute_d3_effort(ach_data)
        rarity_tier = compute_rarity_from_effort(effort)

        ach_name = d3_info.get("name") or ach.get("name", f"D3 Achievement {ach_id}")
        ach_desc = d3_info.get("description") or ach.get("description", "")

        # Upsert achievement
        db_ach = db.query(Achievement).filter_by(app_id="d3", api_name=str(ach_id)).first()
        if not db_ach:
            db_ach = Achievement(
                app_id="d3",
                api_name=str(ach_id),
                name=ach_name,
                display_name=ach_name,
                description=ach_desc,
                icon_url="/static/icons/battlenet.svg",  # D3 data API unavailable for icons
                effort_score=effort,
                effort_auto=True,
                rarity_tier=rarity_tier,
            )
            db.add(db_ach)
            db.commit()
            db.refresh(db_ach)
        else:
            if getattr(db_ach, "effort_auto", True):
                db_ach.effort_score = effort
                db_ach.rarity_tier = rarity_tier
                db_ach.effort_auto = True
            if d3_info.get("name") and db_ach.name != d3_info["name"]:
                db_ach.name = d3_info["name"]
                db_ach.display_name = d3_info["name"]
            if d3_info.get("description") and not db_ach.description:
                db_ach.description = d3_info["description"]

        # Credit
        already = db.query(AchievementCredit).filter_by(
            user_id=user.id,
            provider_account_id=provider_account.id,
            achievement_id=db_ach.id
        ).first()
        if not already:
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name=provider_account.provider_name,
                provider_user_id=provider_account.provider_user_id,
                is_original_claim=True,
            )
            db.add(credit)
            total_credited += 1

        achievements.append({
            "id": ach_id,
            "display_name": ach_name,
            "description": ach_desc,
            "icon_url": "/static/icons/battlenet.svg",  # D3 data API unavailable for icons
            "unlocked": True,
            "effort_score": effort,
            "effort_auto": getattr(db_ach, "effort_auto", True),
            "rarity_tier": rarity_tier,
        })

    db.commit()

    logger.info(f"[BNET-D3] {battletag}: Found {total_found} achievements, credited {total_credited}")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": [{
                "game": "Diablo III",
                "battletag": battletag,
                "paragon_level": profile.get("paragonLevel", 0),
                "heroes_count": len(profile.get("heroes", [])),
                "total_found": total_found,
                "credited": total_credited,
                "achievements": achievements,
            }],
        }
    }


# ============================================================================
# STARCRAFT 2 SYNC
# ============================================================================

# SC2 region IDs
SC2_REGIONS = {
    "us": 1,
    "eu": 2,
    "kr": 3,
    "tw": 3,  # Taiwan uses KR region
    "cn": 5,
}


async def get_sc2_account(account_id: str, token: str) -> list:
    """
    Get SC2 account info for a Battle.net account.
    Returns list of SC2 profiles with region/realm/profileId.

    The account_id is the numeric Battle.net account ID from OAuth.
    """
    headers = {"Authorization": f"Bearer {token}"}

    # Try multiple regions since SC2 APIs have intermittent issues
    regions = ["us", "eu"]

    for region in regions:
        url = f"https://{region}.api.blizzard.com/sc2/player/{account_id}"

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, headers=headers)

                if resp.status_code == 200:
                    data = resp.json()
                    logger.info(f"[BNET-SC2] Found {len(data)} profiles via {region} region")
                    return data
                elif resp.status_code == 503:
                    logger.warning(f"[BNET-SC2] {region} region returned 503 (API issues)")
                    continue
                elif resp.status_code == 404:
                    logger.info(f"[BNET-SC2] No SC2 profiles in {region} region")
                    continue
                else:
                    logger.warning(f"[BNET-SC2] {region} returned {resp.status_code}")
                    continue

        except httpx.TimeoutException:
            logger.warning(f"[BNET-SC2] Request timed out for {region}")
            continue
        except Exception as e:
            logger.warning(f"[BNET-SC2] Error getting SC2 account from {region}: {e}")
            continue

    logger.info(f"[BNET-SC2] No SC2 profiles found for account {account_id}")
    return []


async def get_sc2_profile(region_id: int, realm_id: int, profile_id: int, token: str) -> dict:
    """
    Fetch SC2 profile with achievements.
    """
    # Try multiple region hosts
    region_hosts = ["us", "eu"]
    headers = {"Authorization": f"Bearer {token}"}

    for region in region_hosts:
        url = f"https://{region}.api.blizzard.com/sc2/profile/{region_id}/{realm_id}/{profile_id}"

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(url, headers=headers)

                if resp.status_code == 200:
                    return resp.json()
                elif resp.status_code == 503:
                    logger.warning(f"[BNET-SC2] {region} region returned 503 (API issues)")
                    continue
                elif resp.status_code == 404:
                    continue

        except httpx.TimeoutException:
            logger.warning(f"[BNET-SC2] Request timed out for {region}")
            continue
        except Exception as e:
            logger.warning(f"[BNET-SC2] Error: {e}")
            continue

    return {}


async def get_sc2_static_data(region: str, token: str) -> dict:
    """
    Get static SC2 data including achievement definitions.
    """
    headers = {"Authorization": f"Bearer {token}"}
    region_id = SC2_REGIONS.get(region, 1)
    url = f"https://{region}.api.blizzard.com/sc2/static/profile/{region_id}"

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logger.warning(f"[BNET-SC2] Error fetching static data: {e}")

    return {}


def compute_sc2_effort(ach_data: dict) -> float:
    """
    Compute effort score for a StarCraft 2 achievement.
    SC2 achievements range from 5-30 points typically.
    """
    points = ach_data.get("points", 10)
    category_name = ach_data.get("category_name", "").lower()
    title = ach_data.get("title", "").lower()

    # Base score from points (SC2 uses 5, 10, 15, 20, 25, 30 point values)
    if points >= 30:
        base = 75  # Legendary territory
    elif points >= 25:
        base = 65  # Epic
    elif points >= 20:
        base = 55  # Rare-Epic
    elif points >= 15:
        base = 45  # Rare
    elif points >= 10:
        base = 30  # Uncommon
    else:
        base = 20  # Common

    # Category bonuses based on difficulty/type
    category_lower = category_name.lower() if category_name else ""

    # Campaign difficulty achievements
    if "brutal" in category_lower or "brutal" in title:
        base += 25
    elif "hard" in category_lower or "hard" in title:
        base += 15
    elif "normal" in category_lower:
        base += 5

    # Multiplayer/competitive achievements are harder
    if "versus" in category_lower or "1v1" in title or "ladder" in title:
        base += 20
    elif "unranked" in category_lower or "co-op" in category_lower:
        base += 10

    # Mastery and challenge achievements
    if "mastery" in category_lower or "master" in title:
        base += 20
    if "challenge" in category_lower:
        base += 10

    # Special achievements
    if "feat of strength" in category_lower or "legacy" in title:
        base = max(base, 85)  # Minimum Legendary for FoS

    return min(100.0, max(15.0, base))


async def sync_sc2_achievements(
    user: User, provider_account: ProviderAccount, db: Session,
    token: str = None
) -> dict:
    """
    Sync StarCraft 2 achievements for a Battle.net account.
    Note: SC2 API may return 503 in some regions (known issue as of late 2024).
    """
    from app.services.crypto_service import decrypt_token
    token = token or decrypt_token(provider_account.access_token)
    account_id = provider_account.provider_user_id  # Numeric Battle.net account ID

    if not account_id:
        logger.warning(f"[BNET-SC2] No account ID available")
        return {"credited": 0, "details": {"total_achievements": 0, "per_game": []}}

    # Get user's SC2 profiles
    profiles = await get_sc2_account(account_id, token)

    if not profiles:
        logger.info(f"[BNET-SC2] No SC2 profiles found")
        return {"credited": 0, "details": {"total_achievements": 0, "per_game": []}}

    # Fetch static achievement data to get names/descriptions
    static_data = await get_sc2_static_data("us", token)
    achievement_lookup = {}
    category_lookup = {}

    # Build category lookup first
    if static_data and static_data.get("categories"):
        for cat in static_data["categories"]:
            cat_id = str(cat.get("id"))
            category_lookup[cat_id] = cat.get("name", "")
            # Also process child categories
            for child in cat.get("children", []):
                child_id = str(child.get("id"))
                category_lookup[child_id] = child.get("name", "")
        logger.info(f"[BNET-SC2] Loaded {len(category_lookup)} category definitions")

    # Build achievement lookup with category names
    if static_data and static_data.get("achievements"):
        for ach in static_data["achievements"]:
            ach_id = str(ach.get("id"))
            cat_id = str(ach.get("categoryId", ""))
            category_name = category_lookup.get(cat_id, "")

            achievement_lookup[ach_id] = {
                "name": ach.get("title", f"SC2 Achievement {ach_id}"),
                "description": ach.get("description", ""),
                "points": ach.get("points", 10),
                "category_id": cat_id,
                "category_name": category_name,
                "icon_url": ach.get("imageUrl"),
            }
        logger.info(f"[BNET-SC2] Loaded {len(achievement_lookup)} achievement definitions from static data")

    # Ensure SC2 game record exists
    sc2_game = db.query(Game).filter_by(
        provider_account_id=provider_account.id,
        app_id="sc2"
    ).first()
    if not sc2_game:
        sc2_game = Game(
            provider_account_id=provider_account.id,
            app_id="sc2",
            name="StarCraft II",
            box_art_url="https://blz-contentstack-images.akamaized.net/v3/assets/blt0e00eb71333df64e/blt17f559c77b54f7e0/64f06f3ce6e27d5b67d5c7b4/sc2-icon.png"
        )
        db.add(sc2_game)
        db.commit()
        logger.info(f"[BNET-SC2] Created SC2 game record")

    total_found = 0
    total_credited = 0
    per_profile = []

    for profile_info in profiles:
        region_id = profile_info.get("regionId", 1)
        realm_id = profile_info.get("realmId", 1)
        profile_id = profile_info.get("profileId")
        profile_name = profile_info.get("name", "Unknown")

        if not profile_id:
            continue

        profile = await get_sc2_profile(region_id, realm_id, profile_id, token)

        if not profile:
            logger.warning(f"[BNET-SC2] Could not fetch profile {profile_name} (API may be down)")
            continue

        # SC2 profile has achievements in earnedAchievements
        earned = profile.get("earnedAchievements", [])
        achievements = []

        for ach in earned:
            ach_id = ach.get("achievementId")
            if not ach_id:
                continue

            total_found += 1
            ach_id_str = str(ach_id)

            # Look up achievement details from static data
            static_info = achievement_lookup.get(ach_id_str, {})

            ach_name = static_info.get("name", f"SC2 Achievement {ach_id}")
            ach_desc = static_info.get("description", "")
            category_name = static_info.get("category_name", "")
            ach_icon = static_info.get("icon_url") or "/static/icons/sc2.svg"

            ach_data = {
                "points": static_info.get("points", 10),
                "category_name": category_name,
                "title": ach_name,  # Pass title for keyword matching
            }

            effort = compute_sc2_effort(ach_data)
            rarity_tier = compute_rarity_from_effort(effort)

            # Upsert achievement
            db_ach = db.query(Achievement).filter_by(app_id="sc2", api_name=ach_id_str).first()
            if not db_ach:
                db_ach = Achievement(
                    app_id="sc2",
                    api_name=ach_id_str,
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
                # Update name/description/icon from static data if we have it
                if static_info.get("name") and db_ach.name.startswith("SC2 Achievement"):
                    db_ach.name = static_info["name"]
                    db_ach.display_name = static_info["name"]
                if static_info.get("description") and not db_ach.description:
                    db_ach.description = static_info["description"]
                if static_info.get("icon_url") and (not db_ach.icon_url or db_ach.icon_url.startswith("/static")):
                    db_ach.icon_url = static_info["icon_url"]
                if getattr(db_ach, "effort_auto", True):
                    db_ach.effort_score = effort
                    db_ach.rarity_tier = rarity_tier

            # Credit
            already = db.query(AchievementCredit).filter_by(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id
            ).first()
            if not already:
                credit = AchievementCredit(
                    user_id=user.id,
                    provider_account_id=provider_account.id,
                    achievement_id=db_ach.id,
                    provider_name=provider_account.provider_name,
                    provider_user_id=provider_account.provider_user_id,
                    is_original_claim=True,
                )
                db.add(credit)
                total_credited += 1

            achievements.append({
                "id": ach_id,
                "display_name": ach_name,
                "description": ach_desc,
                "icon_url": ach_icon,
                "unlocked": True,
                "effort_score": effort,
                "effort_auto": True,
                "rarity_tier": rarity_tier,
            })

        if achievements:
            per_profile.append({
                "game": "StarCraft II",
                "profile_name": profile_name,
                "region_id": region_id,
                "total_found": len(achievements),
                "credited": total_credited,
                "achievements": achievements,
            })

    db.commit()

    logger.info(f"[BNET-SC2] Found {total_found} achievements, credited {total_credited}")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "per_game": per_profile,
        }
    }


# ============================================================================
# COMBINED BATTLE.NET SYNC (WoW + D3 + SC2)
# ============================================================================


async def sync_all_battlenet_achievements(
    user: User, provider_account: ProviderAccount, db: Session,
    token: str = None
) -> dict:
    """
    Sync all Battle.net game achievements: WoW, Diablo 3, and StarCraft 2.
    """
    from app.services.crypto_service import decrypt_token
    token = token or decrypt_token(provider_account.access_token)
    total_credited = 0
    all_per_game = []

    # Sync WoW
    try:
        wow_result = await sync_battlenet_achievements(user, provider_account, db, token=token)
        total_credited += wow_result.get("credited", 0)
        all_per_game.extend(wow_result.get("details", {}).get("per_game", []))
        logger.info(f"[BNET] WoW sync: {wow_result.get('credited', 0)} credited")
    except Exception as e:
        logger.error(f"[BNET] WoW sync error: {e}")

    # Sync Diablo 3
    try:
        d3_result = await sync_d3_achievements(user, provider_account, db, token=token)
        total_credited += d3_result.get("credited", 0)
        all_per_game.extend(d3_result.get("details", {}).get("per_game", []))
        logger.info(f"[BNET] D3 sync: {d3_result.get('credited', 0)} credited")
    except Exception as e:
        logger.error(f"[BNET] D3 sync error: {e}")

    # Sync StarCraft 2
    try:
        sc2_result = await sync_sc2_achievements(user, provider_account, db, token=token)
        total_credited += sc2_result.get("credited", 0)
        all_per_game.extend(sc2_result.get("details", {}).get("per_game", []))
        logger.info(f"[BNET] SC2 sync: {sc2_result.get('credited', 0)} credited")
    except Exception as e:
        logger.error(f"[BNET] SC2 sync error: {e}")

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": sum(g.get("total_found", 0) for g in all_per_game),
            "per_game": all_per_game,
        }
    }



