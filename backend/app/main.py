from fastapi import FastAPI, Depends, HTTPException, Request, Response, Form
from sqlalchemy.orm import Session as DbSession
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from app.models import User, ProviderAccount, Game, UserAchievement, Achievement, AchievementCredit, Session as SessionModel, WalletAccount, ForgedAchievement
import uuid
from urllib.parse import urlencode
import os
from authlib.integrations.starlette_client import OAuth
from starlette.middleware.sessions import SessionMiddleware
from dotenv import load_dotenv
load_dotenv()
from app.logging_config import setup_logging
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
import httpx
import logging
from starlette.staticfiles import StaticFiles
from app.services.steam_api import fetch_steam_profile, get_steam_unlocked_achievements_async, \
    get_global_percentages_for_game_async
from app.services.effort_scoring import categorize_steam_achievement
from collections import Counter
from typing import List, Optional
from app.database import engine, SessionLocal, Base
from datetime import datetime, timedelta
import secrets
from sqlalchemy import inspect, func
from sqlalchemy.exc import IntegrityError
from collections import defaultdict
from app.services.battlenet_services import sync_battlenet_achievements
from app.services.xbox_services import sync_xbox_achievements
from app.services.steam_services import sync_steam_achievements
from app.services.psn_services import sync_psn_achievements
from app.services.discord_services import sync_discord_badges
from app.services.github_services import sync_github_achievements
from app.services.item_forge_service import (
    get_catalog_summary, get_items, get_items_by_type, get_items_by_theme,
    get_available_items, get_themes, compute_forged_item, get_mappings_with_items,
    get_achievement_mappings
)
from app.providers import PROVIDERS, get_enabled_providers, AchievementSupport
from app.providers.oauth_handler import init_oauth_providers, create_oauth_routes, router as oauth_router
from app.routes.wallet_routes import router as wallet_router, init_wallet_routes
from app.routes.friend_routes import router as friend_router, init_friend_routes
from app.routes.chat_routes import router as chat_router, init_chat_routes, seed_mock_global_feed, post_user_joined_announcement, post_sync_announcement, start_mock_activity, stop_mock_activity
from app.routes.trading_routes import router as trading_router, init_trading_routes
from app.routes.weapon_stats_routes import router as weapon_stats_router, init_weapon_stats_routes
import time
import asyncio

Base.metadata.create_all(bind=engine)

logger = logging.getLogger(__name__)
setup_logging()

app = FastAPI(title="SocialAuth", description="Gaming achievement aggregator for Godot games")
templates = Jinja2Templates(directory="templates")


@app.on_event("startup")
async def startup_event():
    """Initialize OAuth providers and wallet routes on startup"""
    init_oauth_providers()
    init_wallet_routes(get_db, get_current_user)
    init_friend_routes(get_current_user, calculate_mantle_tier)
    init_chat_routes(get_current_user, calculate_mantle_tier)
    init_trading_routes(get_current_user)
    init_weapon_stats_routes(get_current_user)
    seed_mock_global_feed()  # Add demo activity to global feed
    start_mock_activity(min_interval=20, max_interval=60)  # Live mock activity every 20-60 seconds

    # Start chain batching service for trade provenance
    try:
        from app.services.chain_batching_service import chain_batching_service
        chain_batching_service.start()
    except Exception as e:
        logger.warning(f"Chain batching service not started: {e}")

    # Start transfer indexer for bridge system (detects OpenSea sales, etc)
    try:
        from app.services.transfer_indexer_service import transfer_indexer_service
        transfer_indexer_service.start()
    except Exception as e:
        logger.warning(f"Transfer indexer not started: {e}")

    logger.info(f"Enabled providers: {list(get_enabled_providers().keys())}")
    if BETA_ACCESS_CODE:
        logger.info(f"Beta gate ENABLED (code: {BETA_ACCESS_CODE[:4]}...)")
    else:
        logger.info("Beta gate DISABLED (no BETA_ACCESS_CODE set)")


@app.on_event("shutdown")
async def shutdown_event():
    """Clean up on shutdown"""
    stop_mock_activity()

    # Stop chain batching service
    try:
        from app.services.chain_batching_service import chain_batching_service
        chain_batching_service.stop()
    except Exception:
        pass

    # Stop transfer indexer
    try:
        from app.services.transfer_indexer_service import transfer_indexer_service
        transfer_indexer_service.stop()
    except Exception:
        pass


@app.get("/")
async def root():
    """Redirect root to login page"""
    return RedirectResponse(url="/login", status_code=302)


@app.get("/api/health")
async def health_check():
    """Health check endpoint for Godot client to verify backend connectivity"""
    return {"status": "ok", "service": "mantle"}


@app.get("/index.html")
@app.get("/index")
async def index_redirect():
    """Redirect index.html to login page"""
    return RedirectResponse(url="/login", status_code=302)


@app.get("/favicon.ico")
async def favicon():
    """Return empty response for favicon to suppress 404s"""
    return Response(status_code=204)


SESSION_SECRET = os.environ.get("SESSION_SECRET")
if not SESSION_SECRET:
    raise RuntimeError("SESSION_SECRET environment variable is required")
app.add_middleware(SessionMiddleware, secret_key=SESSION_SECRET)
app.mount("/static", StaticFiles(directory="static"), name="static")

# Build provider list from registry (only enabled providers)
def get_all_providers_list():
    """Get list of enabled providers for templates"""
    return [
        {
            "name": name,
            "display_name": config.display_name,
            "enabled": config.enabled,
            "color": config.color,
            "achievement_support": config.achievement_support.value,
        }
        for name, config in get_enabled_providers().items()
    ]

all_providers = get_all_providers_list()

STEAM_API_KEY = os.getenv("STEAM_API_KEY")
BATTLENET_API_KEY = os.environ.get("BATTLENET_API_KEY")
APP_URL = os.environ.get("APP_URL", "http://localhost:8000")
# Admin secret - required in production, has dev fallback for local testing
ADMIN_SECRET = os.environ.get("ADMIN_SECRET")
if not ADMIN_SECRET:
    if os.environ.get("ENV") == "production":
        raise RuntimeError("ADMIN_SECRET environment variable is required in production")
    ADMIN_SECRET = "dev-only-admin-secret"
    print("⚠️  WARNING: Using default ADMIN_SECRET - do not use in production!")
BETA_ACCESS_CODE = os.environ.get("BETA_ACCESS_CODE")  # Set to enable beta gate (e.g., "mantle-beta-2024")

# In-memory device code storage (for Godot auth flow)
# Format: {device_code: {"user_id": int|None, "username": str|None, "session_token": str|None, "created_at": datetime, "expires_at": datetime}}
device_codes: dict = {}

def cleanup_expired_device_codes():
    """Remove expired device codes"""
    now = datetime.utcnow()
    expired = [code for code, data in device_codes.items() if data["expires_at"] < now]
    for code in expired:
        del device_codes[code]


def complete_device_auth(device_code: str, user_id: int, username: str, session_token: str):
    """Associate a device code with an authenticated user and their session token"""
    if device_code and device_code in device_codes:
        device_codes[device_code]["user_id"] = user_id
        device_codes[device_code]["username"] = username
        device_codes[device_code]["session_token"] = session_token
        return True
    return False


def make_auth_response(request: Request, user, device_code: Optional[str], provider: str, db: DbSession):
    """Create appropriate response after auth - either device success page or dashboard redirect"""
    if device_code and device_code in device_codes:
        # Device auth flow - create session token for Godot to use
        token = create_session(db, user)
        complete_device_auth(device_code, user.id, user.username, token)
        return templates.TemplateResponse(
            "auth_success.html",
            {
                "request": request,
                "username": user.username,
                "provider": provider,
            }
        )
    else:
        # Normal web flow - redirect to dashboard with secure session token
        response = RedirectResponse(url="/dashboard", status_code=303)
        token = create_session(db, user)
        set_session_cookie(response, token)
        return response


# Mapping of country codes to flag emojis
COUNTRY_FLAGS = {
    "US": "🇺🇸",
    "GB": "🇬🇧",
    "DE": "🇩🇪",
    "FR": "🇫🇷",
    "ES": "🇪🇸",
    "IT": "🇮🇹",
    "CA": "🇨🇦",
    "AU": "🇦🇺",
    # Add more country codes and flags as needed
}

# =============================================================================
# MANTLE TIER SYSTEM
# =============================================================================
# Tier thresholds and colors for in-game badge display

MANTLE_TIERS = {
    "initiate":  {"min_score": 0,    "color": "#666666", "glow": "#444444", "name": "Initiate"},
    "bronze":    {"min_score": 100,  "color": "#CD7F32", "glow": "#8B4513", "name": "Bronze"},
    "silver":    {"min_score": 500,  "color": "#C0C0C0", "glow": "#808080", "name": "Silver"},
    "gold":      {"min_score": 1000, "color": "#FFD700", "glow": "#DAA520", "name": "Gold"},
    "platinum":  {"min_score": 2000, "color": "#E5E4E2", "glow": "#A0D8EF", "name": "Platinum"},
    "diamond":   {"min_score": 3000, "color": "#B9F2FF", "glow": "#40E0D0", "name": "Diamond"},
    "legendary": {"min_score": 5000, "color": "#FF6600", "glow": "#FF4500", "name": "Legendary"},
    "mythic":    {"min_score": 7500, "color": "#FF00FF", "glow": "#00FFFF", "name": "Mythic"},
}

# Ordered list for tier lookup (highest first)
TIER_ORDER = ["mythic", "legendary", "diamond", "platinum", "gold", "silver", "bronze", "initiate"]


def calculate_mantle_tier(total_achievements: int, provider_count: int) -> dict:
    """
    Calculate Mantle tier based on achievements and linked providers.

    Provider bonus: each provider beyond 1 adds 15% to effective score.

    Returns dict with: tier, name, color, glow, effective_score
    """
    # Calculate provider bonus multiplier
    bonus_multiplier = 1 + (provider_count - 1) * 0.15 if provider_count > 1 else 1
    effective_score = int(total_achievements * bonus_multiplier)

    # Find matching tier (check highest first)
    for tier_key in TIER_ORDER:
        tier_data = MANTLE_TIERS[tier_key]
        if effective_score >= tier_data["min_score"]:
            return {
                "tier": tier_key,
                "name": tier_data["name"],
                "color": tier_data["color"],
                "glow": tier_data["glow"],
                "effective_score": effective_score,
                "total_achievements": total_achievements,
                "provider_count": provider_count,
            }

    # Fallback (shouldn't happen)
    return {
        "tier": "initiate",
        "name": "Initiate",
        "color": "#666666",
        "glow": "#444444",
        "effective_score": 0,
        "total_achievements": 0,
        "provider_count": 0,
    }

# Provider sync map - db will be passed at call time
def get_provider_sync_map(db):
    return {
        "steam": lambda user, acc: sync_steam_achievements(user, acc, db, STEAM_API_KEY),
        "battlenet": lambda user, acc: sync_battlenet_achievements(user, acc, db),
        "xbox": lambda user, acc: sync_xbox_achievements(user, acc, db),
        # PSN uses sync library (psnawp), so wrap in thread pool
        "psn": lambda user, acc: asyncio.to_thread(sync_psn_achievements, user, acc, db),
        "discord": lambda user, acc: sync_discord_badges(user, acc, db),
        "github": lambda user, acc: sync_github_achievements(user, acc, db),
    }


# Define the custom filter
def country_flag_filter(country_code: str):
    return COUNTRY_FLAGS.get(country_code.upper(), "")


# Register the filter with Jinja2 environment from templates
templates.env.filters["country_flag"] = country_flag_filter


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_session_token(request: Request) -> Optional[str]:
    """Get the session token from cookie or Authorization header.

    Supports both:
    - Cookie: session_id=<token> (for web browser)
    - Header: Authorization: Bearer <token> (for Godot/API clients)
    """
    # First check Authorization header (for Godot/API clients)
    auth_header = request.headers.get("Authorization")
    if auth_header and auth_header.startswith("Bearer "):
        return auth_header[7:]  # Strip "Bearer " prefix

    # Fall back to cookie (for web browser)
    return request.cookies.get("session_id")


def create_session(db: DbSession, user: User) -> str:
    """Create a new secure session token for the user"""
    # Generate a cryptographically secure token
    token = secrets.token_urlsafe(48)  # 64 chars when encoded

    # Set expiry to 24 hours from now
    expires_at = datetime.utcnow() + timedelta(hours=24)

    # Create session record
    session = SessionModel(
        token=token,
        user_id=user.id,
        expires_at=expires_at
    )
    db.add(session)
    db.commit()

    logger.info(f"Created new session for user {user.username}")
    return token


def set_session_cookie(response: Response, token: str):
    """Set the session cookie with the secure token"""
    # Auto-detect HTTPS from APP_URL for secure cookie flag
    is_https = APP_URL.startswith("https://")
    response.set_cookie(
        "session_id",
        token,
        httponly=True,
        secure=is_https,
        samesite="Lax",
        max_age=60 * 60 * 24  # 24 hours
    )


def cleanup_expired_sessions(db: DbSession):
    """Remove expired sessions from database"""
    db.query(SessionModel).filter(SessionModel.expires_at < datetime.utcnow()).delete()
    db.commit()


def get_user_from_session(db: DbSession, token: str) -> Optional[User]:
    """Look up user by session token"""
    if not token:
        return None

    session = db.query(SessionModel).filter(
        SessionModel.token == token,
        SessionModel.expires_at > datetime.utcnow()
    ).first()

    if not session:
        return None

    return session.user


def get_current_user(
        request: Request,
        db: DbSession = Depends(get_db),
) -> User:
    """Get current user or raise 401 if not authenticated."""
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated: No session cookie.")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated: Invalid or expired session.")

    return user


def get_current_user_optional(
        request: Request,
        db: DbSession = Depends(get_db),
) -> Optional[User]:
    """Get current user or None if not authenticated (no exception)."""
    token = get_session_token(request)
    if not token:
        return None

    return get_user_from_session(db, token)


def generate_app_username(db: DbSession):
    base = "mantle-"
    while True:
        username = base + str(uuid.uuid4())[:8]
        if not db.query(User).filter(User.username == username).first():
            return username


def get_user_by_provider(db: DbSession, provider_name: str, provider_user_id: str):
    provider_account = db.query(ProviderAccount).filter(
        ProviderAccount.provider_name == provider_name,
        ProviderAccount.provider_user_id == provider_user_id
    ).first()
    return provider_account.user if provider_account else None


def create_new_user_with_provider(db: DbSession, provider_name: str, provider_user_id: str, profile_data=None, access_token=None, provider_username=None):
    """Create a new user with a provider account in a single transaction."""
    app_username = generate_app_username(db)
    user = User(username=app_username)
    db.add(user)
    db.flush()  # Get the user.id without committing

    new_provider_account = ProviderAccount(
        provider_name=provider_name,
        provider_user_id=provider_user_id,
        provider_username=provider_username,
        user_id=user.id,
        profile_data=profile_data or {},
        is_active=True,
        access_token=access_token
    )
    db.add(new_provider_account)

    try:
        db.commit()
        logger.info(f"Created new user {user.username} with provider {provider_name}:{provider_user_id}")

        # Announce new user in global feed
        post_user_joined_announcement(db, user, provider_name)
    except Exception as e:
        logger.error(f"Failed to create user with provider: {e}")
        db.rollback()
        raise

    return user


def handle_provider_login(
    db: DbSession,
    request: Request,
    provider_name: str,
    provider_user_id: str,
    device_code: Optional[str] = None,
    access_token: Optional[str] = None,
    profile_data: dict = None,
    provider_username: Optional[str] = None
):
    """
    Unified login flow for all providers. Handles:
    1. Active provider → Log into existing account
    2. Inactive provider → Delete orphan link, create fresh account
    3. No provider → Create new account

    Philosophy: Provider accounts can move freely between Mantle accounts.
    Anti-exploit is handled by AchievementCredit.is_original_claim, not provider binding.
    """
    # 1. Check for ACTIVE provider account
    existing_active = (
        db.query(ProviderAccount)
        .filter(
            ProviderAccount.provider_name == provider_name,
            ProviderAccount.provider_user_id == provider_user_id,
            ProviderAccount.is_active == True
        )
        .first()
    )

    if existing_active:
        user = db.query(User).filter(User.id == existing_active.user_id).first()
        if user:
            # Update OAuth token
            existing_active.access_token = access_token
            if provider_username:
                existing_active.provider_username = provider_username
            db.commit()
            logger.info(f"{provider_name.upper()} LOGIN: User {user.username} logged in via active provider")
            return make_auth_response(request, user, device_code, provider_name, db)
        else:
            # Orphan - user was deleted
            logger.info(f"{provider_name.upper()} LOGIN: Found orphan active provider (user deleted), removing")
            db.delete(existing_active)
            db.commit()

    # 2. Check for INACTIVE provider account (was unlinked)
    existing_inactive = (
        db.query(ProviderAccount)
        .filter(
            ProviderAccount.provider_name == provider_name,
            ProviderAccount.provider_user_id == provider_user_id,
            ProviderAccount.is_active == False
        )
        .first()
    )

    if existing_inactive:
        # User intentionally unlinked this provider - allow fresh start
        # Delete the orphaned link so they can create a new Mantle account
        # (Achievement credits stay with original account via is_original_claim)
        logger.info(f"{provider_name.upper()} LOGIN: Inactive provider found (was unlinked), deleting for fresh account")
        db.delete(existing_inactive)
        db.commit()

    # 3. No provider account exists (or was just cleaned up) → Create new user
    logger.info(f"{provider_name.upper()} LOGIN: Creating new user for {provider_name}:{provider_user_id}")
    new_user = create_new_user_with_provider(
        db,
        provider_name,
        provider_user_id,
        profile_data=profile_data,
        access_token=access_token,
        provider_username=provider_username
    )
    return make_auth_response(request, new_user, device_code, provider_name, db)


# =============================================================================
# GENERIC OAUTH ROUTER
# =============================================================================
# Configure and include the generic OAuth handler for all registry-based providers

generic_oauth_router = create_oauth_routes(
    get_db=get_db,
    get_session_token=get_session_token,
    get_user_from_session=get_user_from_session,
    create_session=create_session,
    set_session_cookie=set_session_cookie,
    create_new_user_with_provider=create_new_user_with_provider,
    get_user_by_provider=get_user_by_provider,
    templates=templates,
    app_url=APP_URL,
)
# NOTE: Router inclusion moved to end of file (after Steam routes) to ensure specific routes match first
# app.include_router(generic_oauth_router)  # Moved below
# app.include_router(wallet_router)  # Moved below


def credit_new_achievements(
        db, user, provider_account, unlocked_achievements: list
):
    """
    Credit new achievements for a given provider account.

    ANTI-EXPLOIT: Uses global claim tracking (provider_name + provider_user_id)
    to prevent duplicate Mantle credits when users unlink/relink accounts.

    - First claim: is_original_claim=True (counts toward Mantle tier, can forge)
    - Reclaim after orphan: is_original_claim=False (display only on provider card)
    """
    new_credits = []
    reclaimed_count = 0

    for ach in unlocked_achievements:
        # 1. Ensure Achievement exists in global table
        achievement = (
            db.query(Achievement)
            .filter_by(app_id=ach["app_id"], api_name=ach["api_name"])
            .first()
        )
        if not achievement:
            achievement = Achievement(
                app_id=ach["app_id"],
                api_name=ach["api_name"],
                name=ach.get("display_name", "") or ach.get("name", ""),
                display_name=ach.get("display_name", ""),
                description=ach.get("description", ""),
                icon_url=ach.get("icon_url", ""),
                icon_gray_url=ach.get("icon_gray_url", ""),
                hidden=ach.get("hidden", False),
                default_value=ach.get("default_value", 0),
                percent=ach.get("percent"),
                rarity_tier=ach.get("rarity_tier", "Common"),
            )
            db.add(achievement)
            db.flush()  # To get .id
        else:
            # Always update these fields
            achievement.display_name = ach.get("display_name", achievement.display_name)
            achievement.description = ach.get("description", achievement.description)
            achievement.icon_url = ach.get("icon_url", achievement.icon_url)
            achievement.icon_gray_url = ach.get("icon_gray_url", achievement.icon_gray_url)
            achievement.hidden = ach.get("hidden", achievement.hidden)
            achievement.default_value = ach.get("default_value", achievement.default_value)
            achievement.percent = ach.get("percent", achievement.percent)
            achievement.rarity_tier = ach.get("rarity_tier", achievement.rarity_tier)

        # 2. Check for GLOBAL claim (by provider identity, not provider_account_id)
        existing_global_claim = (
            db.query(AchievementCredit)
            .filter_by(
                provider_name=provider_account.provider_name,
                provider_user_id=provider_account.provider_user_id,
                achievement_id=achievement.id,
            )
            .first()
        )

        if existing_global_claim:
            # Already claimed globally by this provider identity
            if existing_global_claim.provider_account_id == provider_account.id:
                # Same provider_account, already credited
                continue
            else:
                # Provider account changed (orphan/relink scenario)
                # Update to new provider_account but mark as NOT original claim
                existing_global_claim.provider_account_id = provider_account.id
                existing_global_claim.user_id = user.id
                existing_global_claim.is_original_claim = False  # Display only!
                reclaimed_count += 1
                continue

        # 3. First-time claim: credit the achievement
        credit = AchievementCredit(
            user_id=user.id,
            provider_account_id=provider_account.id,
            achievement_id=achievement.id,
            provider_name=provider_account.provider_name,
            provider_user_id=provider_account.provider_user_id,
            is_original_claim=True,  # First claim!
        )
        db.add(credit)
        new_credits.append(credit)

    db.commit()

    if reclaimed_count > 0:
        logger.info(f"Reclaimed {reclaimed_count} previously-credited achievements (display only)")

    return new_credits


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
):
    """
    Upsert achievement credit with global claim tracking.
    Returns: True if new original claim, False if already claimed, 'reclaimed' if display-only
    """
    # Check for GLOBAL claim (by provider identity)
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
            return False  # Already credited to this provider_account
        else:
            # Reclaim scenario: update to new owner but mark as display-only
            existing_global.provider_account_id = provider_account.id
            existing_global.user_id = user.id
            existing_global.is_original_claim = False
            db.commit()
            return 'reclaimed'

    # First-time claim
    new_credit = AchievementCredit(
        user_id=user.id,
        provider_account_id=provider_account.id,
        achievement_id=achievement.id,
        provider_name=provider_account.provider_name,
        provider_user_id=provider_account.provider_user_id,
        is_original_claim=True,
    )
    db.add(new_credit)
    db.commit()
    db.refresh(new_credit)
    return True


async def process_achievements_by_rarity_async(unlocked_achievements, steam_api_key):
    from collections import Counter

    result = {
        "total_achievements": len(unlocked_achievements),
        "by_rarity": Counter(),
    }
    global_percent_cache = {}

    for ach in unlocked_achievements:
        app_id = ach["app_id"]
        api_name = ach["api_name"]
        # Only fetch each app's global stats once per session
        if app_id not in global_percent_cache:
            global_percent_cache[app_id] = await get_global_percentages_for_game_async(app_id, steam_api_key)
        percent = global_percent_cache[app_id].get(api_name, 100.0)  # just retrieve, no await
        tier = categorize_steam_achievement(app_id, api_name, percent)
        result["by_rarity"][tier] += 1

    return result


oauth = OAuth()
oauth.register(
    name='battlenet',
    client_id=os.environ.get('BATTLENET_CLIENT_ID'),
    client_secret=os.environ.get('BATTLENET_CLIENT_SECRET'),
    access_token_url='https://oauth.battle.net/token',
    authorize_url='https://oauth.battle.net/authorize',
    api_base_url='https://us.battle.net/',
    client_kwargs={'scope': 'openid wow.profile'},  # <--- PATCHED HERE
    server_metadata_url='https://oauth.battle.net/.well-known/openid-configuration'
)

oauth.register(
    name='discord',
    client_id=os.environ.get('DISCORD_CLIENT_ID'),
    client_secret=os.environ.get('DISCORD_CLIENT_SECRET'),
    access_token_url='https://discord.com/api/oauth2/token',
    authorize_url='https://discord.com/api/oauth2/authorize',
    api_base_url='https://discord.com/api/',
    client_kwargs={'scope': 'identify connections'},
)

oauth.register(
    name='github',
    client_id=os.environ.get('GITHUB_CLIENT_ID'),
    client_secret=os.environ.get('GITHUB_CLIENT_SECRET'),
    access_token_url='https://github.com/login/oauth/access_token',
    authorize_url='https://github.com/login/oauth/authorize',
    api_base_url='https://api.github.com/',
    client_kwargs={'scope': 'read:user'},
)



@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error at {request.url}: {exc}", exc_info=True)
    return templates.TemplateResponse(
        "error.html",
        {"request": request, "message": "An unexpected error occurred."},
        status_code=500
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    logger.warning(f"HTTPException at {request.url}: {exc.status_code} {exc.detail}")
    return templates.TemplateResponse(
        "error.html",
        {"request": request, "message": exc.detail},
        status_code=exc.status_code
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning(f"Validation error at {request.url}: {exc}")
    return templates.TemplateResponse(
        "error.html",
        {"request": request, "message": "Invalid input or missing fields."},
        status_code=422
    )


@app.exception_handler(StarletteHTTPException)
async def custom_starlette_http_exception_handler(request: Request, exc: StarletteHTTPException):
    # 404 Not Found
    if exc.status_code == 404:
        logger.warning(f"404 Not Found at {request.url}")
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": "The page or resource was not found."},
            status_code=404
        )
    # Other HTTP errors
    logger.warning(f"HTTPException at {request.url}: {exc.status_code} {exc.detail}")
    return templates.TemplateResponse(
        "error.html",
        {"request": request, "message": exc.detail or 'An unexpected error occurred.'},
        status_code=exc.status_code
    )


# --- STEAM OAUTH (OpenID) LOGIN/CLAIM FLOW ---
@app.get("/auth/steam/login")
async def steam_combined_login_claim(
    request: Request,
    db: DbSession = Depends(get_db),
    device_code: Optional[str] = None,
):
    token = get_session_token(request)
    user = get_user_from_session(db, token) if token else None

    # If user is logged in and already has Steam linked, just proceed to Steam
    # (they're re-authenticating with the same account - we'll verify in callback)
    # Only block if we could detect they're trying to link a DIFFERENT Steam

    # Build callback URL with optional device_code
    callback_url = f"{APP_URL}/auth/steam/callback"
    if device_code:
        callback_url += f"?device_code={device_code}"

    # Proceed to normal OpenID login flow (for both new and returning users)
    params = {
        "openid.ns": "http://specs.openid.net/auth/2.0",
        "openid.mode": "checkid_setup",
        "openid.return_to": callback_url,
        "openid.realm": f"{APP_URL}/",
        "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
        "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
    }
    url = f"https://steamcommunity.com/openid/login?{urlencode(params)}"
    logger.info("Initiating Steam login/claim flow%s", f" for user {user.username}" if user else "")
    return RedirectResponse(url)


@app.get("/auth/steam/callback")
async def steam_callback(
    request: Request,
    db: DbSession = Depends(get_db),
    device_code: Optional[str] = None,
):
    steam_url = request.query_params.get("openid.claimed_id")
    logger.info(f"STEAM CALLBACK: steam_url={steam_url}")

    steam_id = steam_url.rsplit("/", 1)[-1] if steam_url else None
    token = get_session_token(request)
    current_user = get_user_from_session(db, token) if token else None
    logger.info(f"STEAM CALLBACK: has_token={bool(token)}, steam_id={steam_id}, device_code={device_code}")

    if current_user:
        logger.info("STEAM CALLBACK: Claim/Merge flow (already logged in)")
        logger.info(f"STEAM CALLBACK: current_user={current_user.username}")

        # ENFORCE: Only 1 active Steam per user (in callback)
        existing_active = (
            db.query(ProviderAccount)
            .filter_by(user_id=current_user.id, provider_name="steam", is_active=True)
            .first()
        )
        logger.info(f"STEAM CALLBACK: existing_active={existing_active}")
        if existing_active:
            # If it's the SAME Steam account, just log them in (redirect to dashboard)
            if existing_active.provider_user_id == steam_id:
                logger.info("STEAM CALLBACK: Same Steam account, redirecting to dashboard.")
                return make_auth_response(request, current_user, device_code, "steam", db)
            # Different Steam account - can't link another
            logger.warning("STEAM CALLBACK: User already has active Steam, trying to link different one.")
            return templates.TemplateResponse(
                "error.html",
                {
                    "request": request,
                    "message": (
                        "You already have a Steam account linked. Unlink it before claiming another."
                    ),
                },
                status_code=400,
            )

        # Check if a ProviderAccount exists for this external Steam ID
        acct = (
            db.query(ProviderAccount)
            .filter_by(provider_name="steam", provider_user_id=steam_id)
            .first()
        )
        count = db.query(ProviderAccount).filter_by(provider_name="steam", provider_user_id=steam_id).count()
        logger.info(f"STEAM CALLBACK: acct={acct}, count={count}")

        if acct:
            if acct.is_active:
                if acct.user_id == current_user.id:
                    logger.info("STEAM CALLBACK: Steam already linked to current user.")
                    return RedirectResponse(url="/dashboard", status_code=303)
                else:
                    logger.info("STEAM CALLBACK: Steam linked to another user. Prompt merge.")
                    return templates.TemplateResponse(
                        "merge_confirm.html",
                        {
                            "request": request,
                            "target_provider": "steam",
                            "other_username": acct.user.username,
                            "other_user_id": acct.user.id,
                            "current_user_id": current_user.id,
                        }
                    )
            else:
                # Row exists but is inactive - check if it belongs to a DIFFERENT user
                if acct.user_id != current_user.id:
                    # Different user's orphaned provider - show warning
                    other_user = db.query(User).filter(User.id == acct.user_id).first()
                    if other_user:
                        logger.info(f"STEAM CALLBACK: Inactive provider belongs to {other_user.username}, prompting reclaim confirmation")
                        return templates.TemplateResponse(
                            "reclaim_confirm.html",
                            {
                                "request": request,
                                "provider_name": "steam",
                                "provider_display": "Steam",
                                "provider_user_id": steam_id,
                                "other_username": other_user.username,
                                "current_user_id": current_user.id,
                            }
                        )
                    # Other user was deleted - just take it
                    acct.user_id = current_user.id
                # Same user reclaiming their own provider, or orphan cleanup
                acct.is_active = True
                acct.unclaimed_at = None
                db.commit()
                logger.info(f"STEAM CALLBACK: User {current_user.username} re-claimed Steam {steam_id}")
                return RedirectResponse(url="/dashboard", status_code=303)
        else:
            # No existing row -- try to create new ProviderAccount
            profile = await fetch_steam_profile(steam_id)
            logger.info(f"STEAM CALLBACK: About to insert new ProviderAccount for steam_id {steam_id}")
            new_acct = ProviderAccount(
                provider_name="steam",
                provider_user_id=steam_id,
                user_id=current_user.id,
                profile_data=profile,
                is_active=True
            )
            db.add(new_acct)
            try:
                db.commit()
                logger.info(f"STEAM CALLBACK: User {current_user.username} linked new Steam {steam_id}")
                return RedirectResponse(url="/dashboard", status_code=303)
            except IntegrityError:
                db.rollback()
                logger.warning(f"STEAM CALLBACK: Race condition - Steam {steam_id} was claimed by another request")
                # Re-fetch the account that was just created by another request
                acct = db.query(ProviderAccount).filter_by(
                    provider_name="steam", provider_user_id=steam_id
                ).first()
                if acct and acct.user_id != current_user.id:
                    return templates.TemplateResponse(
                        "merge_confirm.html",
                        {
                            "request": request,
                            "target_provider": "steam",
                            "other_username": acct.user.username,
                            "other_user_id": acct.user.id,
                            "current_user_id": current_user.id,
                        }
                    )
                return RedirectResponse(url="/dashboard", status_code=303)

    # --------------- LOGIN FLOW (NOT LOGGED IN) ---------------
    logger.info("STEAM CALLBACK: Login flow (not logged in)")
    profile = await fetch_steam_profile(steam_id)
    return handle_provider_login(
        db=db,
        request=request,
        provider_name="steam",
        provider_user_id=steam_id,
        device_code=device_code,
        profile_data=profile
    )


@app.get("/navbar", response_class=HTMLResponse)
async def navbar(request: Request, db: DbSession = Depends(get_db)):
    # grab session -> user (if any)
    token = get_session_token(request)
    user = get_user_from_session(db, token) if token else None

    # user_linked_providers: list of provider names actually linked
    if user:
        linked = (
            db.query(ProviderAccount.provider_name)
            .filter(ProviderAccount.user_id == user.id)
            .all()
        )
        user_linked_providers = [row[0] for row in linked]
    else:
        user_linked_providers = []

    return templates.TemplateResponse(
        "_navbar.html",
        {
            "request": request,
            "local_user_id": user.id if user else None,
            "country_code": getattr(user, "country", None),
            "all_providers": all_providers,  # Use global dynamic list
            "user_linked_providers": user_linked_providers,
        },
    )


# --- BATTLE.NET OAUTH2 LOGIN/CLAIM FLOW ---
@app.get("/auth/battlenet/login")
async def battlenet_login(request: Request, db: DbSession = Depends(get_db)):
    # Single-link-per-provider protection if already logged in
    token = get_session_token(request)
    current_user = get_user_from_session(db, token) if token else None
    if current_user:
            existing_active = (
                db.query(ProviderAccount)
                .filter_by(user_id=current_user.id, provider_name="battlenet", is_active=True)
                .first()
            )
            if existing_active:
                return templates.TemplateResponse(
                    "error.html",
                    {
                        "request": request,
                        "message": (
                            "You already have a Battle.net account linked. Unlink it before claiming another."
                        ),
                    },
                    status_code=400,
                )
    redirect_uri = f"{APP_URL}/auth/battlenet/callback"
    logger.info("Initiating Battle.net login flow")
    return await oauth.battlenet.authorize_redirect(request, redirect_uri)


@app.get("/auth/battlenet/callback")
async def battlenet_callback(request: Request, db: DbSession = Depends(get_db)):
    try:
        oauth_token = await oauth.battlenet.authorize_access_token(request)
        battlenet_id = oauth_token.get("sub")
        if not battlenet_id:
            resp = await oauth.battlenet.get("oauth/userinfo", token=oauth_token)
            battlenet_id = resp.json().get("sub")
        if not battlenet_id:
            logger.error(f"Battle.net login failed: Could not retrieve user ID. Token: {oauth_token}")
            return templates.TemplateResponse(
                "merge_failed.html",
                {"request": request, "message": "Battle.net login failed: Could not retrieve user ID."}
            )

        session_token = get_session_token(request)
        current_user = get_user_from_session(db, session_token) if session_token else None
        if current_user:
            # — Claim flow for logged-in user —

            # ENFORCE single-link rule for claim
            existing_active = (
                db.query(ProviderAccount)
                .filter_by(user_id=current_user.id, provider_name="battlenet", is_active=True)
                .first()
            )
            if existing_active:
                return templates.TemplateResponse(
                    "error.html",
                    {
                        "request": request,
                        "message": (
                            "You already have a Battle.net account linked. Unlink it before claiming another."
                        ),
                    },
                    status_code=400,
                )

            # Lookup existing ProviderAccount for this external ID
            acct = (
                db.query(ProviderAccount)
                .filter_by(provider_name="battlenet", provider_user_id=battlenet_id)
                .first()
            )

            if acct:
                # Check if the linked user still exists (handle orphans)
                other_user = db.query(User).filter(User.id == acct.user_id).first()

                if not other_user:
                    # Orphan provider_account - user was deleted, clean up and reassign
                    logger.info(f"BATTLENET CALLBACK: Found orphan provider_account (user deleted), reassigning to {current_user.username}")
                    acct.user_id = current_user.id
                    acct.is_active = True
                    acct.unclaimed_at = None
                    acct.access_token = oauth_token["access_token"]
                    db.commit()
                    return RedirectResponse(url="/dashboard", status_code=303)

                if acct.is_active:
                    if acct.user_id == current_user.id:
                        # same user → no-op
                        return RedirectResponse(url="/dashboard", status_code=303)
                    # different user → prompt for merge
                    return templates.TemplateResponse(
                        "merge_confirm.html",
                        {
                            "request": request,
                            "target_provider": "battlenet",
                            "other_username": other_user.username,
                            "other_user_id": other_user.id,
                            "current_user_id": current_user.id,
                        }
                    )
                else:
                    # Provider is inactive - check if it belongs to a DIFFERENT user
                    if acct.user_id != current_user.id:
                        # Different user's orphaned provider - show warning
                        logger.info(f"BATTLENET CALLBACK: Inactive provider belongs to {other_user.username}, prompting reclaim confirmation")
                        return templates.TemplateResponse(
                            "reclaim_confirm.html",
                            {
                                "request": request,
                                "provider_name": "battlenet",
                                "provider_display": "Battle.net",
                                "provider_user_id": battlenet_id,
                                "other_username": other_user.username,
                                "current_user_id": current_user.id,
                                "access_token": oauth_token["access_token"],
                            }
                        )
                    # Same user reclaiming their own provider
                    acct.is_active = True
                    acct.unclaimed_at = None
                    acct.access_token = oauth_token["access_token"]
                    db.commit()
                    logger.info(f"User {current_user.username} re-claimed their own Battle.net {battlenet_id}")
                    return RedirectResponse(url="/dashboard", status_code=303)
            else:
                # no existing link → try to create new
                new_acct = ProviderAccount(
                    provider_name="battlenet",
                    provider_user_id=battlenet_id,
                    user_id=current_user.id,
                    is_active=True,
                    access_token=oauth_token["access_token"],
                )
                db.add(new_acct)
                try:
                    db.commit()
                    logger.info(f"User {current_user.username} linked new Battle.net {battlenet_id}")
                    return RedirectResponse(url="/dashboard", status_code=303)
                except IntegrityError:
                    db.rollback()
                    logger.warning(f"BATTLENET CALLBACK: Race condition - Battle.net {battlenet_id} was claimed by another request")
                    # Re-fetch the account that was just created by another request
                    acct = db.query(ProviderAccount).filter_by(
                        provider_name="battlenet", provider_user_id=battlenet_id
                    ).first()
                    if acct and acct.user_id != current_user.id:
                        return templates.TemplateResponse(
                            "merge_confirm.html",
                            {
                                "request": request,
                                "target_provider": "battlenet",
                                "other_username": acct.user.username,
                                "other_user_id": acct.user.id,
                                "current_user_id": current_user.id,
                            }
                        )
                    return RedirectResponse(url="/dashboard", status_code=303)

        # — Login flow for visitors —
        logger.info("BATTLENET CALLBACK: Login flow (not logged in)")
        return handle_provider_login(
            db=db,
            request=request,
            provider_name="battlenet",
            provider_user_id=battlenet_id,
            device_code=device_code,
            access_token=oauth_token["access_token"]
        )

    except Exception as e:
        logger.error(f"Battle.net callback failed: {e}", exc_info=True)
        return templates.TemplateResponse(
            "merge_failed.html",
            {"request": request, "message": "Battle.net login error. Please try again later."}
        )


# =============================================================================
# XBOX AUTHENTICATION (via OpenXBL)
# =============================================================================

OPENXBL_API_KEY = os.environ.get("OPENXBL_API_KEY")


@app.get("/auth/xbox/login")
async def xbox_login(request: Request, db: DbSession = Depends(get_db)):
    """Initiate Xbox login via OpenXBL."""
    if not OPENXBL_API_KEY:
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": "Xbox login not configured. Missing OPENXBL_API_KEY."},
            status_code=500,
        )

    # Single-link-per-provider protection
    token = get_session_token(request)
    current_user = get_user_from_session(db, token) if token else None
    if current_user:
        existing_active = (
            db.query(ProviderAccount)
            .filter_by(user_id=current_user.id, provider_name="xbox", is_active=True)
            .first()
        )
        if existing_active:
            return templates.TemplateResponse(
                "error.html",
                {
                    "request": request,
                    "message": "You already have an Xbox account linked. Unlink it before claiming another.",
                },
                status_code=400,
            )

    # Store device_code in session if present (for Godot flow)
    device_code = request.query_params.get("device_code")

    # OpenXBL auth URL - redirect_uri is configured in OpenXBL app settings
    # Format: https://xbl.io/app/auth/{public_key}
    auth_url = f"https://xbl.io/app/auth/{OPENXBL_API_KEY}"

    # Store device_code in state parameter if present
    if device_code:
        auth_url += f"?state={device_code}"

    logger.info(f"[XBOX] Redirecting to OpenXBL auth: {auth_url}")
    return RedirectResponse(url=auth_url)


@app.get("/auth/xbox/callback")
async def xbox_callback(request: Request, db: DbSession = Depends(get_db)):
    """Handle OpenXBL callback after Microsoft auth."""
    try:
        # OpenXBL returns a 'code' parameter
        code = request.query_params.get("code")
        device_code = request.query_params.get("device_code")

        if not code:
            error = request.query_params.get("error", "No authorization code received")
            logger.error(f"[XBOX] Callback error: {error}")
            return templates.TemplateResponse(
                "merge_failed.html",
                {"request": request, "message": f"Xbox login failed: {error}"}
            )

        # Exchange code for user's API key via OpenXBL
        async with httpx.AsyncClient() as client:
            claim_resp = await client.post(
                "https://xbl.io/app/claim",
                json={"code": code, "app_key": OPENXBL_API_KEY},
                headers={"Content-Type": "application/json"},
            )

            if claim_resp.status_code != 200:
                logger.error(f"[XBOX] Claim failed: {claim_resp.status_code} - {claim_resp.text}")
                return templates.TemplateResponse(
                    "merge_failed.html",
                    {"request": request, "message": "Xbox login failed: Could not verify authorization."}
                )

            claim_data = claim_resp.json()
            user_api_key = claim_data.get("app_key")
            xuid = claim_data.get("xuid")

            if not user_api_key or not xuid:
                logger.error(f"[XBOX] Missing data in claim response: {claim_data}")
                return templates.TemplateResponse(
                    "merge_failed.html",
                    {"request": request, "message": "Xbox login failed: Invalid response from Xbox."}
                )

        logger.info(f"[XBOX] Successfully authenticated XUID: {xuid}")

        # Get gamertag from profile
        gamertag = None
        try:
            from app.services.xbox_services import get_xbox_profile
            profile = await get_xbox_profile(user_api_key)
            # Profile contains profileUsers array
            if profile.get("profileUsers"):
                settings = profile["profileUsers"][0].get("settings", [])
                for s in settings:
                    if s.get("id") == "Gamertag":
                        gamertag = s.get("value")
                        break
        except Exception as e:
            logger.warning(f"[XBOX] Could not fetch gamertag: {e}")

        # Check for existing session (claim flow)
        session_token = get_session_token(request)
        current_user = get_user_from_session(db, session_token) if session_token else None

        if current_user:
            # === CLAIM FLOW: User is logged in, linking Xbox account ===

            # Check single-link rule
            existing_active = (
                db.query(ProviderAccount)
                .filter_by(user_id=current_user.id, provider_name="xbox", is_active=True)
                .first()
            )
            if existing_active:
                return templates.TemplateResponse(
                    "error.html",
                    {"request": request, "message": "You already have an Xbox account linked."},
                    status_code=400,
                )

            # Check if this Xbox account is already linked to another user
            acct = (
                db.query(ProviderAccount)
                .filter_by(provider_name="xbox", provider_user_id=xuid)
                .first()
            )

            if acct:
                other_user = db.query(User).filter(User.id == acct.user_id).first()

                if not other_user:
                    # Orphan - reassign
                    acct.user_id = current_user.id
                    acct.is_active = True
                    acct.unclaimed_at = None
                    acct.access_token = user_api_key
                    if gamertag:
                        acct.profile_data = acct.profile_data or {}
                        acct.profile_data["gamertag"] = gamertag
                    db.commit()
                    return RedirectResponse(url="/dashboard", status_code=303)

                if acct.is_active:
                    if acct.user_id == current_user.id:
                        return RedirectResponse(url="/dashboard", status_code=303)
                    # Different user - prompt merge
                    return templates.TemplateResponse(
                        "merge_confirm.html",
                        {
                            "request": request,
                            "target_provider": "xbox",
                            "other_username": other_user.username,
                            "other_user_id": other_user.id,
                            "current_user_id": current_user.id,
                        }
                    )
                else:
                    # Inactive - reclaim
                    acct.user_id = current_user.id
                    acct.is_active = True
                    acct.unclaimed_at = None
                    acct.access_token = user_api_key
                    if gamertag:
                        acct.profile_data = acct.profile_data or {}
                        acct.profile_data["gamertag"] = gamertag
                    db.commit()
                    return RedirectResponse(url="/dashboard", status_code=303)

            # New link for existing user
            new_provider = ProviderAccount(
                user_id=current_user.id,
                provider_name="xbox",
                provider_user_id=xuid,
                access_token=user_api_key,
                is_active=True,
                profile_data={"gamertag": gamertag} if gamertag else {},
            )
            db.add(new_provider)
            db.commit()

            # Handle device code flow
            if device_code:
                complete_device_auth(device_code, current_user.id, current_user.username, session_token)

            return RedirectResponse(url="/dashboard", status_code=303)

        else:
            # === LOGIN FLOW: No session, creating/finding user ===
            return handle_provider_login(
                db=db,
                request=request,
                provider_name="xbox",
                provider_user_id=xuid,
                device_code=device_code,
                access_token=user_api_key,
                profile_data={"gamertag": gamertag} if gamertag else {},
                provider_username=gamertag
            )

    except Exception as e:
        logger.error(f"[XBOX] Callback failed: {e}", exc_info=True)
        return templates.TemplateResponse(
            "merge_failed.html",
            {"request": request, "message": "Xbox login error. Please try again later."}
        )


# =============================================================================
# PSN AUTHENTICATION (via NPSSO token)
# =============================================================================

@app.post("/auth/psn/link")
async def psn_link(
    request: Request,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Link PSN account using NPSSO token.

    User gets NPSSO by:
    1. Logging into PlayStation.com
    2. Navigating to https://ca.account.sony.com/api/v1/ssocookie
    3. Copying the 64-character token
    """
    try:
        form = await request.form()
        npsso = form.get("npsso", "").strip()

        if not npsso:
            return JSONResponse(
                {"success": False, "message": "NPSSO token is required"},
                status_code=400
            )

        if len(npsso) != 64:
            return JSONResponse(
                {"success": False, "message": "Invalid NPSSO token format (should be 64 characters)"},
                status_code=400
            )

        # Check if user already has PSN linked
        existing = (
            db.query(ProviderAccount)
            .filter_by(user_id=current_user.id, provider_name="psn", is_active=True)
            .first()
        )
        if existing:
            return JSONResponse(
                {"success": False, "message": "You already have a PlayStation account linked. Unlink it first."},
                status_code=400
            )

        # Validate token by fetching profile
        from app.services.psn_services import get_psn_profile
        try:
            profile = get_psn_profile(npsso)
        except Exception as e:
            logger.error(f"[PSN] Token validation failed: {e}")
            return JSONResponse(
                {"success": False, "message": f"Invalid NPSSO token: {str(e)}"},
                status_code=400
            )

        psn_id = profile.get("account_id")
        online_id = profile.get("online_id")

        if not psn_id:
            return JSONResponse(
                {"success": False, "message": "Could not retrieve PSN account ID"},
                status_code=400
            )

        # Check if this PSN account is already linked to another user
        existing_psn = (
            db.query(ProviderAccount)
            .filter_by(provider_name="psn", provider_user_id=str(psn_id))
            .first()
        )

        if existing_psn and existing_psn.user_id != current_user.id:
            return JSONResponse(
                {"success": False, "message": "This PlayStation account is linked to another user"},
                status_code=400
            )

        # Create or update provider account
        if existing_psn:
            # Reactivate existing account
            existing_psn.user_id = current_user.id
            existing_psn.is_active = True
            existing_psn.access_token = npsso
            existing_psn.profile_data = {
                "online_id": online_id,
                "avatar_url": profile.get("avatar_url"),
            }
            provider_account = existing_psn
        else:
            # Create new provider account
            provider_account = ProviderAccount(
                user_id=current_user.id,
                provider_name="psn",
                provider_user_id=str(psn_id),
                access_token=npsso,
                is_active=True,
                profile_data={
                    "online_id": online_id,
                    "avatar_url": profile.get("avatar_url"),
                },
            )
            db.add(provider_account)

        db.commit()
        db.refresh(provider_account)

        logger.info(f"[PSN] Linked account {online_id} (ID: {psn_id}) to user {current_user.id}")

        return JSONResponse({
            "success": True,
            "message": f"PlayStation account '{online_id}' linked successfully!",
            "provider_account_id": provider_account.id,
            "online_id": online_id,
        })

    except Exception as e:
        logger.error(f"[PSN] Link error: {e}")
        return JSONResponse(
            {"success": False, "message": f"Error linking PlayStation: {str(e)}"},
            status_code=500
        )


# =============================================================================
# DISCORD AUTHENTICATION
# =============================================================================

@app.get("/auth/discord/login")
async def discord_login(request: Request, db: DbSession = Depends(get_db), device_code: Optional[str] = None):
    """Initiate Discord OAuth flow"""
    token = get_session_token(request)
    current_user = get_user_from_session(db, token) if token else None
    if current_user:
        existing_active = (
            db.query(ProviderAccount)
            .filter_by(user_id=current_user.id, provider_name="discord", is_active=True)
            .first()
        )
        if existing_active:
            return templates.TemplateResponse(
                "error.html",
                {"request": request, "message": "You already have a Discord account linked. Unlink it before claiming another."},
                status_code=400,
            )

    # Store device_code in session for callback (Godot auth flow)
    if device_code:
        request.session["device_code"] = device_code
        logger.info(f"[DISCORD] Stored device_code {device_code[:8]}... in session")

    redirect_uri = f"{APP_URL}/auth/discord/callback"
    logger.info("Initiating Discord login flow")
    return await oauth.discord.authorize_redirect(request, redirect_uri)


@app.get("/auth/discord/callback")
async def discord_callback(request: Request, db: DbSession = Depends(get_db)):
    """Handle Discord OAuth callback"""
    try:
        oauth_token = await oauth.discord.authorize_access_token(request)

        # Get user info from Discord
        resp = await oauth.discord.get("users/@me", token=oauth_token)
        user_info = resp.json()
        discord_id = user_info.get("id")
        discord_username = user_info.get("username")
        discord_discriminator = user_info.get("discriminator", "0")
        discord_avatar = user_info.get("avatar")

        if not discord_id:
            logger.error(f"Discord login failed: Could not retrieve user ID")
            return templates.TemplateResponse(
                "error.html",
                {"request": request, "message": "Discord login failed: Could not retrieve user ID."}
            )

        # Build avatar URL
        avatar_url = None
        if discord_avatar:
            avatar_url = f"https://cdn.discordapp.com/avatars/{discord_id}/{discord_avatar}.png"

        # Build display name
        if discord_discriminator and discord_discriminator != "0":
            display_name = f"{discord_username}#{discord_discriminator}"
        else:
            display_name = discord_username

        logger.info(f"[DISCORD] User authenticated: {display_name} (ID: {discord_id})")

        session_token = get_session_token(request)
        current_user = get_user_from_session(db, session_token) if session_token else None

        if current_user:
            # Logged in user - link Discord to their account
            existing_active = (
                db.query(ProviderAccount)
                .filter_by(user_id=current_user.id, provider_name="discord", is_active=True)
                .first()
            )
            if existing_active:
                return templates.TemplateResponse(
                    "error.html",
                    {"request": request, "message": "You already have a Discord account linked."},
                    status_code=400,
                )

            # Check if this Discord is linked to another user
            existing_discord = (
                db.query(ProviderAccount)
                .filter_by(provider_name="discord", provider_user_id=discord_id, is_active=True)
                .first()
            )
            if existing_discord and existing_discord.user_id != current_user.id:
                return templates.TemplateResponse(
                    "error.html",
                    {"request": request, "message": "This Discord account is already linked to another user."},
                    status_code=400,
                )

            # Create or update provider account
            provider_account = (
                db.query(ProviderAccount)
                .filter_by(provider_name="discord", provider_user_id=discord_id)
                .first()
            )
            if provider_account:
                provider_account.user_id = current_user.id
                provider_account.is_active = True
                provider_account.access_token = oauth_token.get("access_token")
                provider_account.profile_data = {
                    "username": discord_username,
                    "discriminator": discord_discriminator,
                    "display_name": display_name,
                    "avatar_url": avatar_url,
                }
            else:
                provider_account = ProviderAccount(
                    user_id=current_user.id,
                    provider_name="discord",
                    provider_user_id=discord_id,
                    access_token=oauth_token.get("access_token"),
                    is_active=True,
                    profile_data={
                        "username": discord_username,
                        "discriminator": discord_discriminator,
                        "display_name": display_name,
                        "avatar_url": avatar_url,
                    },
                )
                db.add(provider_account)

            db.commit()
            logger.info(f"[DISCORD] Linked {display_name} to user {current_user.id}")
            return RedirectResponse(url="/dashboard", status_code=303)

        else:
            # Not logged in - use unified login flow
            device_code = request.session.get("device_code")
            return handle_provider_login(
                db=db,
                request=request,
                provider_name="discord",
                provider_user_id=discord_id,
                device_code=device_code,
                access_token=oauth_token.get("access_token"),
                profile_data={
                    "username": discord_username,
                    "discriminator": discord_discriminator,
                    "display_name": display_name,
                    "avatar_url": avatar_url,
                },
                provider_username=display_name
            )

    except Exception as e:
        logger.error(f"[DISCORD] Callback error: {e}", exc_info=True)
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": f"Discord login failed: {str(e)}"},
            status_code=500
        )


# =============================================================================
# GITHUB AUTHENTICATION
# =============================================================================

@app.get("/auth/github/login")
async def github_login(request: Request, db: DbSession = Depends(get_db)):
    """Initiate GitHub OAuth flow"""
    token = get_session_token(request)
    current_user = get_user_from_session(db, token) if token else None
    if current_user:
        existing_active = (
            db.query(ProviderAccount)
            .filter_by(user_id=current_user.id, provider_name="github", is_active=True)
            .first()
        )
        if existing_active:
            return templates.TemplateResponse(
                "error.html",
                {"request": request, "message": "You already have a GitHub account linked. Unlink it before claiming another."},
                status_code=400,
            )
    redirect_uri = f"{APP_URL}/auth/github/callback"
    logger.info("Initiating GitHub login flow")
    return await oauth.github.authorize_redirect(request, redirect_uri)


@app.get("/auth/github/callback")
async def github_callback(request: Request, db: DbSession = Depends(get_db)):
    """Handle GitHub OAuth callback"""
    try:
        oauth_token = await oauth.github.authorize_access_token(request)

        # Get user info from GitHub
        resp = await oauth.github.get("user", token=oauth_token)
        user_info = resp.json()
        github_id = str(user_info.get("id"))
        github_username = user_info.get("login")
        github_name = user_info.get("name") or github_username
        github_avatar = user_info.get("avatar_url")
        github_bio = user_info.get("bio")
        github_public_repos = user_info.get("public_repos", 0)
        github_followers = user_info.get("followers", 0)

        if not github_id:
            logger.error(f"GitHub login failed: Could not retrieve user ID")
            return templates.TemplateResponse(
                "error.html",
                {"request": request, "message": "GitHub login failed: Could not retrieve user ID."}
            )

        logger.info(f"[GITHUB] User authenticated: {github_username} (ID: {github_id})")

        session_token = get_session_token(request)
        current_user = get_user_from_session(db, session_token) if session_token else None

        if current_user:
            # Logged in user - link GitHub to their account
            existing_active = (
                db.query(ProviderAccount)
                .filter_by(user_id=current_user.id, provider_name="github", is_active=True)
                .first()
            )
            if existing_active:
                return templates.TemplateResponse(
                    "error.html",
                    {"request": request, "message": "You already have a GitHub account linked."},
                    status_code=400,
                )

            # Check if this GitHub is linked to another user
            existing_github = (
                db.query(ProviderAccount)
                .filter_by(provider_name="github", provider_user_id=github_id, is_active=True)
                .first()
            )
            if existing_github and existing_github.user_id != current_user.id:
                return templates.TemplateResponse(
                    "error.html",
                    {"request": request, "message": "This GitHub account is already linked to another user."},
                    status_code=400,
                )

            # Create or update provider account
            provider_account = (
                db.query(ProviderAccount)
                .filter_by(provider_name="github", provider_user_id=github_id)
                .first()
            )
            if provider_account:
                provider_account.user_id = current_user.id
                provider_account.is_active = True
                provider_account.access_token = oauth_token.get("access_token")
                provider_account.profile_data = {
                    "username": github_username,
                    "name": github_name,
                    "avatar_url": github_avatar,
                    "bio": github_bio,
                    "public_repos": github_public_repos,
                    "followers": github_followers,
                }
            else:
                provider_account = ProviderAccount(
                    user_id=current_user.id,
                    provider_name="github",
                    provider_user_id=github_id,
                    access_token=oauth_token.get("access_token"),
                    is_active=True,
                    profile_data={
                        "username": github_username,
                        "name": github_name,
                        "avatar_url": github_avatar,
                        "bio": github_bio,
                        "public_repos": github_public_repos,
                        "followers": github_followers,
                    },
                )
                db.add(provider_account)

            db.commit()
            logger.info(f"[GITHUB] Linked {github_username} to user {current_user.id}")
            return RedirectResponse(url="/dashboard", status_code=303)

        else:
            # Not logged in - use unified login flow
            device_code = request.session.get("device_code")
            return handle_provider_login(
                db=db,
                request=request,
                provider_name="github",
                provider_user_id=github_id,
                device_code=device_code,
                access_token=oauth_token.get("access_token"),
                profile_data={
                    "username": github_username,
                    "name": github_name,
                    "avatar_url": github_avatar,
                    "bio": github_bio,
                    "public_repos": github_public_repos,
                    "followers": github_followers,
                },
                provider_username=github_username
            )

    except Exception as e:
        logger.error(f"[GITHUB] Callback error: {e}", exc_info=True)
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": f"GitHub login failed: {str(e)}"},
            status_code=500
        )


# --- Merge Handler ---
@app.post("/merge-confirm", response_class=HTMLResponse)
async def merge_confirm(
        request: Request,
        db: DbSession = Depends(get_db),
        other_user_id: int = Form(),
        target_provider: str = Form(),
        current_user_id: int = Form()
):
    current_user = db.query(User).filter(User.id == current_user_id).first()
    other_user = db.query(User).filter(User.id == other_user_id).first()
    if not (current_user and other_user):
        logger.warning("Merge failed: one or both user IDs not found")
        return RedirectResponse(url="/dashboard", status_code=303)

    # Always keep the OLDER account (lower ID = created first)
    # Merge newer account INTO older account, then delete newer
    if current_user.id < other_user.id:
        keeper = current_user
        to_merge = other_user
    else:
        keeper = other_user
        to_merge = current_user

    logger.info(f"Merge: keeping older account {keeper.id} ({keeper.username}), merging away {to_merge.id} ({to_merge.username})")

    # Find provider names linked to both users
    keeper_provider_names = set(
        p.provider_name for p in db.query(ProviderAccount).filter(ProviderAccount.user_id == keeper.id)
    )
    to_merge_provider_names = set(
        p.provider_name for p in db.query(ProviderAccount).filter(ProviderAccount.user_id == to_merge.id)
    )
    conflicts = keeper_provider_names & to_merge_provider_names

    if conflicts:
        msg = (
                "Cannot merge: the older account already has these provider(s): " +
                ", ".join(conflicts) +
                ". Unclaim them first before merging."
        )
        logger.warning(f"Merge conflict: providers {conflicts}")
        # Show merge_confirm.html again, with clear warning
        return templates.TemplateResponse("merge_confirm.html", {
            "request": request,
            "target_provider": target_provider,
            "other_username": other_user.username,
            "other_user_id": other_user.id,
            "current_user_id": current_user.id,
            "conflicts": conflicts,
            "message": msg,
        }, status_code=409)

    # No conflicts: do the merge in a single transaction
    try:
        # Transfer all provider accounts from newer to older
        transferred_providers = []
        for provider in db.query(ProviderAccount).filter(ProviderAccount.user_id == to_merge.id).all():
            provider.user_id = keeper.id
            transferred_providers.append(provider.provider_name)

        # Transfer all achievement credits (important for dashboard queries)
        credits_transferred = 0
        for credit in db.query(AchievementCredit).filter(AchievementCredit.user_id == to_merge.id).all():
            credit.user_id = keeper.id
            credits_transferred += 1

        # Transfer any user achievements
        for ua in db.query(UserAchievement).filter(UserAchievement.user_id == to_merge.id).all():
            ua.user_id = keeper.id

        # Transfer wallet accounts (if any)
        for wallet in db.query(WalletAccount).filter(WalletAccount.user_id == to_merge.id).all():
            wallet.user_id = keeper.id

        # Flush to ensure all changes are written before delete
        db.flush()

        db.delete(to_merge)
        db.commit()

        logger.info(f"Accounts merged: {to_merge.username} (id={to_merge.id}) into {keeper.username} (id={keeper.id})")
        logger.info(f"  Transferred providers: {transferred_providers}")
        logger.info(f"  Transferred credits: {credits_transferred}")

        # Create new session for the keeper account and set cookie
        response = RedirectResponse(url="/dashboard", status_code=303)
        session_token = create_session(db, keeper)
        set_session_cookie(response, session_token)
        return response

    except Exception as e:
        db.rollback()
        logger.error(f"Merge failed: {e}")
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": "Account merge failed. Please try again."},
            status_code=500
        )


# --- Reclaim Handler (for claiming orphaned/unlinked providers) ---
@app.post("/reclaim-confirm", response_class=HTMLResponse)
async def reclaim_confirm(
    request: Request,
    db: DbSession = Depends(get_db),
    provider_name: str = Form(),
    provider_user_id: str = Form(),
    current_user_id: int = Form(),
    access_token: Optional[str] = Form(None)
):
    """
    Handle reclaiming an orphaned/unlinked provider.
    The original owner keeps their achievements - new owner links fresh.
    """
    current_user = db.query(User).filter(User.id == current_user_id).first()
    if not current_user:
        logger.warning(f"Reclaim failed: user {current_user_id} not found")
        return RedirectResponse(url="/dashboard", status_code=303)

    # Find the provider account
    provider_account = db.query(ProviderAccount).filter_by(
        provider_name=provider_name,
        provider_user_id=provider_user_id
    ).first()

    if not provider_account:
        logger.warning(f"Reclaim failed: provider {provider_name}/{provider_user_id} not found")
        return RedirectResponse(url="/dashboard", status_code=303)

    # Reassign to current user
    old_user_id = provider_account.user_id
    provider_account.user_id = current_user.id
    provider_account.is_active = True
    provider_account.unclaimed_at = None
    if access_token:
        provider_account.access_token = access_token

    try:
        db.commit()
        logger.info(f"Provider {provider_name}/{provider_user_id} reclaimed by {current_user.username} (was user {old_user_id})")
    except Exception as e:
        db.rollback()
        logger.error(f"Reclaim failed: {e}")
        return templates.TemplateResponse(
            "error.html",
            {"request": request, "message": "Provider claim failed. Please try again."},
            status_code=500
        )

    return RedirectResponse(url="/dashboard", status_code=303)


# --- Login Page (clears existing session cookies) ---
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request, device_code: Optional[str] = None):
    # Check beta gate if enabled
    if BETA_ACCESS_CODE:
        beta_cookie = request.cookies.get("beta_access")
        if beta_cookie != BETA_ACCESS_CODE:
            # Show beta access page instead
            return templates.TemplateResponse(
                "login.html",
                {
                    "request": request,
                    "all_providers": all_providers,
                    "user": None,
                    "user_linked_providers": [],
                    "device_code": device_code,
                    "beta_gate": True,  # Flag to show access code form
                },
            )

    # Render login page and clear any existing session/auth cookies
    response = templates.TemplateResponse(
        "login.html",
        {
            "request": request,
            "all_providers": all_providers,
            "user": None,
            "user_linked_providers": [],
            "device_code": device_code,
            "beta_gate": False,
        },
    )
    # Delete session cookie if present (forces re-login)
    if request.cookies.get("session_id"):
        response.delete_cookie("session_id", path="/")
    return response


@app.post("/beta-access")
async def verify_beta_access(request: Request, access_code: str = Form(...)):
    """Verify beta access code and set cookie."""
    if not BETA_ACCESS_CODE:
        # Beta gate not enabled
        return RedirectResponse(url="/login", status_code=303)

    if access_code == BETA_ACCESS_CODE:
        # Correct code - set cookie and redirect to login
        response = RedirectResponse(url="/login", status_code=303)
        response.set_cookie(
            key="beta_access",
            value=BETA_ACCESS_CODE,
            httponly=True,
            max_age=60 * 60 * 24 * 30,  # 30 days
            samesite="lax",
        )
        return response
    else:
        # Wrong code - redirect back with error
        return templates.TemplateResponse(
            "login.html",
            {
                "request": request,
                "all_providers": all_providers,
                "user": None,
                "user_linked_providers": [],
                "device_code": None,
                "beta_gate": True,
                "beta_error": "Invalid access code",
            },
        )


@app.get("/achievements/battlenet/{user_id}")
async def get_battlenet_achievements(user_id: int):
    # --- Get DB/session, user and provider as needed
    db = SessionLocal()
    user = db.query(User).filter_by(id=user_id).first()
    if not user:
        db.close()
        raise HTTPException(status_code=404, detail="User not found")
    provider_account = db.query(ProviderAccount).filter_by(user_id=user_id, provider_name="battlenet", is_active=True).first()
    if not provider_account:
        db.close()
        raise HTTPException(status_code=404, detail="Battle.net provider account not found")

    # --- Run the sync (or fetch cached data if desired)
    result = await sync_battlenet_achievements(user, provider_account, db)

    db.close()
    print("PER_CHARACTER (to frontend):", result["details"]["per_game"])

    # --- Return just the character array
    return JSONResponse(content=result["details"]["per_game"])

@app.get("/wallet/connect", response_class=HTMLResponse)
async def wallet_connect_page(
        request: Request,
        db: DbSession = Depends(get_db),
        user: Optional[User] = Depends(get_current_user_optional),
):
    """Wallet connection page for SIWE (Sign-In With Ethereum) flow.
    Users are redirected here from Godot to connect their crypto wallet."""
    # Redirect to login if not authenticated
    if not user:
        return RedirectResponse(url="/login?next=/wallet/connect", status_code=302)

    return templates.TemplateResponse(
        "wallet_connect.html",
        {"request": request, "user": user}
    )


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(
        request: Request,
        db: DbSession = Depends(get_db),
        user: Optional[User] = Depends(get_current_user_optional),
):
    # Redirect to login if not authenticated
    if not user:
        return RedirectResponse(url="/login", status_code=302)

    # 1) Use global all_providers list (dynamically built from provider registry)

    # Only providers with active link
    active_linked = []
    if user:
        rows = (
            db.query(ProviderAccount.provider_name)
            .filter(
                ProviderAccount.user_id == user.id,
                ProviderAccount.is_active == True
            )
            .all()
        )
        active_linked = [r[0].lower() for r in rows]

    local_user_id = user.id if user else None
    country_code = getattr(user, "country", None) if user else None

    # Build the list of provider-cards (ONLY active accounts)
    providers: List[dict] = []
    if user:
        for p in all_providers:
            # fetch only ACTIVE accounts for provider card rendering
            accounts = (
                db.query(ProviderAccount)
                .filter_by(user_id=user.id, provider_name=p["name"], is_active=True)
                .all()
            )
            if not accounts:
                continue  # never linked or only inactive → no card

            # pick avatar and display name from the first active account
            source = accounts[0]
            avatar_url = "/static/icons/placeholder-avatar.svg"
            profile_display_name = None

            if source.profile_data:
                avatar_url = (
                    source.profile_data.get("avatarfull")
                    or source.profile_data.get("avatar")
                    or avatar_url
                )
                # Get display name based on provider
                if p["name"] == "steam":
                    profile_display_name = source.profile_data.get("personaname")
                elif p["name"] == "battlenet":
                    profile_display_name = source.profile_data.get("battletag")
                elif p["name"] == "xbox":
                    profile_display_name = source.profile_data.get("gamertag")
                    # Xbox avatar from OpenXBL (if stored)
                    xbox_avatar = source.profile_data.get("avatar_url") or source.profile_data.get("displayPicRaw")
                    if xbox_avatar:
                        avatar_url = xbox_avatar
                elif p["name"] == "psn":
                    profile_display_name = source.profile_data.get("online_id")
                    psn_avatar = source.profile_data.get("avatar_url")
                    if psn_avatar:
                        avatar_url = psn_avatar
                elif p["name"] == "discord":
                    # Discord stores username and display_name
                    profile_display_name = source.profile_data.get("display_name") or source.profile_data.get("username")
                    discord_avatar = source.profile_data.get("avatar_url")
                    if discord_avatar:
                        avatar_url = discord_avatar
                elif p["name"] == "github":
                    # GitHub stores username and name (display name)
                    profile_display_name = source.profile_data.get("name") or source.profile_data.get("username")
                    github_avatar = source.profile_data.get("avatar_url")
                    if github_avatar:
                        avatar_url = github_avatar
                elif p["name"] == "facebook":
                    # Facebook stores name and id
                    profile_display_name = source.profile_data.get("name")
                    fb_avatar = source.profile_data.get("avatar_url")
                    if fb_avatar:
                        avatar_url = fb_avatar

            # sum credits across all active accounts for this provider
            total_achievements = 0
            rarity_counts = Counter()
            for acct in accounts:
                credits = (
                    db.query(AchievementCredit)
                    .join(Achievement)
                    .filter(AchievementCredit.provider_account_id == acct.id)
                    .all()
                )
                total_achievements += len(credits)
                for credit in credits:
                    rarity = getattr(credit.achievement, "rarity_tier", "Common")
                    rarity_counts[rarity] += 1

            # Calculate cooldown remaining (if any) - DISABLED FOR TESTING
            cooldown_remaining = 0
            # if source.last_sync_at and not getattr(user, 'is_admin', False):
            #     from datetime import timedelta
            #     cooldown_end = source.last_sync_at + timedelta(minutes=SYNC_COOLDOWN_MINUTES)
            #     if datetime.utcnow() < cooldown_end:
            #         cooldown_remaining = int((cooldown_end - datetime.utcnow()).total_seconds())

            providers.append({
                "name": p["name"],
                "display_name": p["display_name"],
                "icon_url": f"/static/icons/{p['name']}.png",
                "avatar_url": avatar_url,
                "user_id": source.provider_user_id,
                "profile_display_name": profile_display_name,
                "profile_data": source.profile_data,
                "total_achievements": total_achievements,
                "by_rarity": dict(rarity_counts),
                "cooldown_remaining": cooldown_remaining,  # Seconds until sync available
                "is_synced": source.last_sync_at is not None,  # Has been synced at least once
            })

    # Calculate MANTLE AGGREGATE (all original claims, regardless of provider status)
    # This is your permanent gaming history - doesn't change when you unlink providers
    mantle_data = None
    if user:
        # Count ALL original claims for this user
        mantle_credits = (
            db.query(AchievementCredit)
            .join(Achievement)
            .filter(
                AchievementCredit.user_id == user.id,
                AchievementCredit.is_original_claim == True
            )
            .all()
        )

        mantle_total = len(mantle_credits)
        mantle_rarity = Counter()
        for credit in mantle_credits:
            rarity = getattr(credit.achievement, "rarity_tier", "Common")
            mantle_rarity[rarity] += 1

        # Count total providers ever linked (active or not)
        total_providers_linked = (
            db.query(ProviderAccount)
            .filter(ProviderAccount.user_id == user.id)
            .count()
        )

        # Calculate tier
        tier_info = calculate_mantle_tier(mantle_total, total_providers_linked)

        mantle_data = {
            "total_achievements": mantle_total,
            "by_rarity": dict(mantle_rarity),
            "tier": tier_info["tier"],
            "tier_name": tier_info["name"],
            "tier_color": tier_info["color"],
            "tier_glow": tier_info["glow"],
            "effective_score": tier_info["effective_score"],
        }

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "local_user_id": local_user_id,
            "country_code": country_code,
            "all_providers": all_providers,
            "user_linked_providers": active_linked,
            "providers": providers,
            "mantle": mantle_data,
        },
    )



@app.post("/unclaim/{provider_name}")
async def unclaim_provider(
        provider_name: str,
        request: Request,
        db: DbSession = Depends(get_db)
):
    token = get_session_token(request)
    if not token:
        return RedirectResponse(url="/login", status_code=303)

    user = get_user_from_session(db, token)
    if not user:
        return RedirectResponse(url="/login", status_code=303)

    # Use FOR UPDATE to lock active provider rows and prevent race conditions
    # This ensures two concurrent unclaim requests can't both succeed
    active_accounts = (
        db.query(ProviderAccount)
        .filter(
            ProviderAccount.user_id == user.id,
            ProviderAccount.is_active == True
        )
        .with_for_update()  # Lock rows to prevent concurrent modifications
        .all()
    )
    active_count = len(active_accounts)
    logger.info(
        f"User {user.username} has {active_count} active providers: {[a.provider_name for a in active_accounts]}")

    if active_count <= 1:
        logger.warning(f"User {user.username} attempted to unclaim their last provider ({provider_name})")
        db.rollback()  # Release the lock
        response = RedirectResponse(url="/dashboard", status_code=303)
        response.set_cookie(
            "message",
            "You must have at least one provider linked to your account.",
            max_age=3
        )
        return response

    # Find the account to unclaim from our locked set
    account = next((a for a in active_accounts if a.provider_name == provider_name), None)

    if account:
        account.is_active = False
        account.unclaimed_at = datetime.utcnow()
        db.commit()
        logger.info(f"User {user.username} unclaimed provider {provider_name}")
    else:
        db.rollback()  # Release the lock
        logger.warning(
            f"User {user.username} attempted to unclaim non-linked or already unclaimed provider {provider_name}")

    return RedirectResponse(url="/dashboard", status_code=303)


# SYNC_COOLDOWN_MINUTES = 15  # Cooldown between syncs per provider (disabled for testing)

@app.post("/sync_achievements/{provider_name}/{provider_user_id}")
async def sync_achievements(
    provider_name: str,
    provider_user_id: str,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    import time
    start_time = time.time()
    provider_account = db.query(ProviderAccount).filter_by(
        provider_name=provider_name,
        provider_user_id=provider_user_id,
        user_id=current_user.id,
        is_active=True
    ).first()

    if not provider_account:
        print(
            f"[SYNC REPORT] Provider: {provider_name} | User: {current_user.id} | "
            f"Status: FAIL | Duration: 0.00s | Reason: Active provider account not found."
        )
        raise HTTPException(status_code=404, detail="Active provider account not found.")

    # Sync cooldown check (admins bypass) - DISABLED FOR TESTING
    # if not getattr(current_user, 'is_admin', False):
    #     if provider_account.last_sync_at:
    #         from datetime import timedelta
    #         cooldown_end = provider_account.last_sync_at + timedelta(minutes=SYNC_COOLDOWN_MINUTES)
    #         if datetime.utcnow() < cooldown_end:
    #             remaining = (cooldown_end - datetime.utcnow()).total_seconds()
    #             remaining_min = int(remaining // 60)
    #             remaining_sec = int(remaining % 60)
    #             print(
    #                 f"[SYNC REPORT] Provider: {provider_name} | User: {current_user.id} | "
    #                 f"Status: COOLDOWN | Remaining: {remaining_min}m {remaining_sec}s"
    #             )
    #             raise HTTPException(
    #                 status_code=429,
    #                 detail=f"Sync cooldown active. Try again in {remaining_min}m {remaining_sec}s."
    #             )

    sync_function = get_provider_sync_map(db).get(provider_name.lower())
    if not sync_function:
        print(
            f"[SYNC REPORT] Provider: {provider_name} | User: {current_user.id} | "
            f"Status: FAIL | Duration: 0.00s | Reason: Unsupported provider"
        )
        raise HTTPException(status_code=400, detail="Unsupported provider")

    try:
        result = await sync_function(current_user, provider_account)
        elapsed = round(time.time() - start_time, 2)

        total_found = result.get("details", {}).get("total_achievements", 0)
        credited = result.get("credited", 0)
        ignored = total_found - credited

        # --- New Debug Output ---
        per_game = result.get("details", {}).get("per_game", [])
        print(f"\n=== [SYNC DEBUG: PER-GAME DETAIL] ===")
        for g in per_game:
            print(
                f"appid={g.get('app_id')} | {g.get('game_name', '(Unknown Game)')} | "
                f"Found={g.get('total_found', 0)} | Credited={g.get('credited', 0)} | Ignored={g.get('ignored', 0)}"
            )
        print(f"=== [END SYNC DEBUG] ===\n")

        print(
            f"[SYNC REPORT] Provider: {provider_name} | User: {current_user.id} | "
            f"Status: SUCCESS | Duration: {elapsed}s | "
            f"Total Found: {total_found} | New Credited: {credited} | Ignored (Already Claimed): {ignored}"
        )

        # Update last_sync_at for cooldown tracking
        provider_account.last_sync_at = datetime.utcnow()
        db.commit()

        # Announce sync in global feed if there were new achievements
        if credited > 0:
            post_sync_announcement(db, current_user, provider_name, credited)

        return {
            "provider": provider_name,
            "credited": credited,
            "details": result.get("details", {}),
        }

    except Exception as e:
        elapsed = round(time.time() - start_time, 2)
        error_str = str(e)
        print(
            f"[SYNC REPORT] Provider: {provider_name} | User: {current_user.id} | "
            f"Status: FAIL | Duration: {elapsed}s | Reason: {error_str}"
        )
        raise





@app.get("/achievements/by-rarity/{rarity_tier}")
async def get_achievements_by_rarity(
    rarity_tier: str,
    provider_name: str = None,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get achievements filtered by rarity tier.

    Args:
        rarity_tier: One of Common, Uncommon, Rare, Epic, Legendary
        provider_name: Optional - filter to specific provider (steam, battlenet, etc.)
                      If not provided, returns achievements from all providers.

    Returns:
        List of achievements matching the rarity tier.
    """
    valid_tiers = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
    if rarity_tier not in valid_tiers:
        raise HTTPException(status_code=400, detail=f"Invalid rarity tier. Must be one of: {valid_tiers}")

    # Build query for achievement credits
    query = (
        db.query(Achievement, AchievementCredit, ProviderAccount, Game)
        .join(AchievementCredit, Achievement.id == AchievementCredit.achievement_id)
        .join(ProviderAccount, ProviderAccount.id == AchievementCredit.provider_account_id)
        .outerjoin(
            Game,
            (Game.app_id == Achievement.app_id) & (Game.provider_account_id == ProviderAccount.id)
        )
        .filter(
            AchievementCredit.user_id == current_user.id,
            Achievement.rarity_tier == rarity_tier
        )
    )

    # Filter by provider if specified
    if provider_name:
        query = query.filter(ProviderAccount.provider_name == provider_name)

    credits = query.all()

    # Build response
    achievements = []
    for achievement, credit, provider_account, game in credits:
        achievements.append({
            "id": achievement.id,
            "api_name": achievement.api_name,
            "display_name": achievement.display_name,
            "description": achievement.description,
            "icon_url": achievement.icon_url,
            "percent": achievement.percent,
            "rarity_tier": achievement.rarity_tier,
            "game_name": game.name if game and game.name else "(Unknown Game)",
            "app_id": achievement.app_id,
            "provider_name": provider_account.provider_name,
            "unlocked_at": credit.unlocked_at.isoformat() if credit.unlocked_at else None,  # Original unlock
            "date_credited": credit.date_credited.isoformat() if credit.date_credited else None,  # Added to Mantle
            "is_original_claim": credit.is_original_claim,
        })

    # Sort by percent (rarest first within tier)
    achievements.sort(key=lambda x: x["percent"] if x["percent"] else 100)

    return {
        "rarity_tier": rarity_tier,
        "count": len(achievements),
        "achievements": achievements
    }


@app.get("/achievements/{provider_name}/{user_id}")
async def get_achievements(
    provider_name: str,
    user_id: int,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Check access (ensure current_user.id == user_id, unless you want public)
    if current_user.id != int(user_id):
        raise HTTPException(status_code=403, detail="Forbidden")

    # 1. Get all achievement credits for this user for this provider (any account ever linked)
    credits = (
        db.query(Achievement, AchievementCredit, ProviderAccount, Game)
        .join(AchievementCredit, Achievement.id == AchievementCredit.achievement_id)
        .join(ProviderAccount, ProviderAccount.id == AchievementCredit.provider_account_id)
        .outerjoin(
            Game,
            (Game.app_id == Achievement.app_id) & (Game.provider_account_id == ProviderAccount.id)
        )
        .filter(
            AchievementCredit.user_id == user_id,
            ProviderAccount.provider_name == provider_name
        )
        .all()
    )

    # 2. Group by game/app_id

    games_dict = defaultdict(lambda: {
        "game_name": "",
        "box_art_url": "",
        "achievements": []
    })
    for achievement, credit, provider_account, game in credits:
        app_id = achievement.app_id
        # Use Game.name if available; fallback to "(Unknown Game)" if not
        games_dict[app_id]["game_name"] = game.name if game and game.name else "(Unknown Game)"
        games_dict[app_id]["box_art_url"] = game.box_art_url if game and game.box_art_url else ""
        games_dict[app_id]["achievements"].append({
            "api_name": achievement.api_name,
            "display_name": achievement.display_name,
            "description": achievement.description,
            "icon_url": achievement.icon_url,
            "icon_gray_url": achievement.icon_gray_url,
            "hidden": achievement.hidden,
            "default_value": achievement.default_value,
            "percent": achievement.percent,
            "rarity_tier": achievement.rarity_tier,
            "unlocked_at": credit.unlocked_at.isoformat() if credit.unlocked_at else None,  # Original unlock time
            "date_credited": credit.date_credited.isoformat() if credit.date_credited else None,  # When added to Mantle
            "unlocked": True,  # Always unlocked for credits!
            "provider_account_id": credit.provider_account_id,
        })
    games = []
    for app_id, data in games_dict.items():
        games.append({
            "app_id": app_id,
            "game_name": data["game_name"],
            "box_art_url": f"https://cdn.cloudflare.steamstatic.com/steam/apps/{app_id}/library_hero.jpg",
            "achievements": data["achievements"],
        })
    return {"games": games}


    # --- Logout ---
@app.post("/logout", response_class=HTMLResponse)
async def logout(request: Request, db: DbSession = Depends(get_db)):
    # Log the logout event and invalidate the session
    token = get_session_token(request)
    if token:
        # Get user info for logging before deleting session
        user = get_user_from_session(db, token)
        if user:
            logger.info(f"User {user.username} logged out")
        # Delete the session from database
        db.query(SessionModel).filter(SessionModel.token == token).delete()
        db.commit()

    # Redirect back to login and delete cookies
    response = RedirectResponse(url="/login", status_code=303)
    response.delete_cookie("session_id", path="/")
    return response


# =============================================================================
# GODOT GAME CLIENT API ENDPOINTS
# =============================================================================

@app.get("/api/auth/device")
async def create_device_code(request: Request):
    """
    Generate a device code for Godot auth flow.

    Godot calls this to get a device_code, then opens browser to:
    {APP_URL}/auth/steam/login?device_code={device_code}

    Then polls /api/auth/status?device_code={device_code} until authenticated.
    """
    logger.info(f"[DEVICE AUTH] Request received from {request.client.host}")
    cleanup_expired_device_codes()

    device_code = secrets.token_urlsafe(32)
    logger.info(f"[DEVICE AUTH] Generated code: {device_code[:8]}...")
    device_codes[device_code] = {
        "user_id": None,
        "username": None,
        "session_token": None,
        "created_at": datetime.utcnow(),
        "expires_at": datetime.utcnow() + timedelta(minutes=10),
    }

    return {
        "device_code": device_code,
        "auth_url": f"{APP_URL}/login?device_code={device_code}",
        "poll_url": f"{APP_URL}/api/auth/status",
        "expires_in": 600,  # 10 minutes
    }


@app.get("/api/auth/status")
async def check_device_auth_status(device_code: str):
    """
    Check if a device code has been authenticated.

    Returns:
    - pending: User hasn't completed auth yet
    - success: User authenticated, includes user data and session token
    - expired: Device code expired or not found

    On success, the response includes a `token` field that Godot should store
    and send with subsequent API requests via the Authorization header:
        Authorization: Bearer <token>
    """
    cleanup_expired_device_codes()

    if device_code not in device_codes:
        return {"status": "expired", "message": "Device code not found or expired"}

    data = device_codes[device_code]

    if data["user_id"] is None:
        return {"status": "pending", "message": "Waiting for user authentication"}

    # Auth complete - return user data with session token and clean up
    result = {
        "status": "success",
        "user_id": data["user_id"],
        "username": data["username"],
        "token": data["session_token"],  # Godot stores this for API calls
    }
    del device_codes[device_code]
    return result


@app.get("/api/me")
async def get_current_user_api(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Get current authenticated user info for Godot client.
    Uses secure session token authentication.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Get linked providers with their profile data
    provider_accounts = (
        db.query(ProviderAccount)
        .filter(ProviderAccount.user_id == user.id, ProviderAccount.is_active == True)
        .all()
    )

    providers = []
    for acct in provider_accounts:
        # Count achievements for this specific provider account
        achievement_count = (
            db.query(AchievementCredit)
            .filter(
                AchievementCredit.provider_account_id == acct.id,
                AchievementCredit.is_original_claim == True
            )
            .count()
        )

        provider_info = {
            "provider_name": acct.provider_name,
            "provider_user_id": acct.provider_user_id,
            "achievement_count": achievement_count,
            "icon_url": f"{APP_URL}/static/icons/{acct.provider_name}.png",
        }

        # Add profile data based on provider
        if acct.profile_data:
            if acct.provider_name == "steam":
                provider_info["display_name"] = acct.profile_data.get("personaname")
                provider_info["avatar_url"] = acct.profile_data.get("avatarfull")
            elif acct.provider_name == "battlenet":
                provider_info["display_name"] = acct.profile_data.get("battletag")
                provider_info["avatar_url"] = acct.profile_data.get("top_character", {}).get("avatar_url") if acct.profile_data.get("top_character") else None
                if acct.profile_data.get("top_character"):
                    provider_info["top_character"] = acct.profile_data["top_character"]
            elif acct.provider_name == "xbox":
                provider_info["display_name"] = acct.profile_data.get("gamertag")
                provider_info["avatar_url"] = acct.profile_data.get("avatar_url") or acct.profile_data.get("displayPicRaw")
            elif acct.provider_name == "psn":
                provider_info["display_name"] = acct.profile_data.get("online_id")
                provider_info["avatar_url"] = acct.profile_data.get("avatar_url")
            elif acct.provider_name == "discord":
                provider_info["display_name"] = acct.profile_data.get("display_name") or acct.profile_data.get("username")
                provider_info["avatar_url"] = acct.profile_data.get("avatar_url")
            elif acct.provider_name == "github":
                provider_info["display_name"] = acct.profile_data.get("name") or acct.profile_data.get("username")
                provider_info["avatar_url"] = acct.profile_data.get("avatar_url")

        providers.append(provider_info)

    # Count total achievements for Mantle tier (ONLY original claims count!)
    total_achievements = (
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user.id,
            AchievementCredit.is_original_claim == True
        )
        .count()
    )

    # Get rarity counts for Godot gems display
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}
    rarity_query = (
        db.query(Achievement.rarity_tier, func.count(AchievementCredit.id))
        .join(AchievementCredit, AchievementCredit.achievement_id == Achievement.id)
        .filter(
            AchievementCredit.user_id == user.id,
            AchievementCredit.is_original_claim == True
        )
        .group_by(Achievement.rarity_tier)
        .all()
    )
    for tier, count in rarity_query:
        if tier in rarity_counts:
            rarity_counts[tier] = count

    # Calculate Mantle tier
    mantle = calculate_mantle_tier(total_achievements, len(providers))

    return {
        "user_id": user.id,
        "username": user.username,
        "total_achievements": total_achievements,
        "by_rarity": rarity_counts,
        "mantle": {
            "tier": mantle["tier"],
            "name": mantle["name"],
            "color": mantle["color"],
            "glow": mantle["glow"],
            "effective_score": mantle["effective_score"],
        },
        "providers": providers,
        "tier_thresholds": {
            "tiers": MANTLE_TIERS,
            "order": TIER_ORDER,
        },
        "appearance": user.appearance_data,
    }


@app.post("/api/me/appearance")
async def save_appearance(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Save character appearance data for Armory preview.
    Called when player logs out to persist their current look.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    body = await request.json()

    # Extract and validate appearance fields
    appearance = {
        "gender": body.get("gender", 0),
        "weapon_type": body.get("weapon_type", ""),
        "feet_sprite": body.get("feet_sprite", ""),
        "legs_sprite": body.get("legs_sprite", ""),
        "chest_sprite": body.get("chest_sprite", ""),
        "arms_sprite": body.get("arms_sprite", ""),
        "hands_sprite": body.get("hands_sprite", ""),
        "head_sprite": body.get("head_sprite", ""),
    }

    # Normalize gender to int (0=male, 1=female)
    if isinstance(appearance["gender"], str):
        appearance["gender"] = 0 if appearance["gender"].lower() == "male" else 1

    user.appearance_data = appearance
    db.commit()

    return {"status": "ok", "appearance": appearance}


@app.get("/api/achievements")
async def get_all_achievements_api(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Get all achievements for the current user across all providers.
    Useful for Godot to display the flex profile.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Get all achievement credits with optional game info
    credits = (
        db.query(AchievementCredit, Achievement, ProviderAccount, Game)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .join(ProviderAccount, AchievementCredit.provider_account_id == ProviderAccount.id)
        .outerjoin(Game, (Game.app_id == Achievement.app_id) & (Game.provider_account_id == ProviderAccount.id))
        .filter(AchievementCredit.user_id == user.id)
        .all()
    )

    # Non-game provider display names
    PROVIDER_DISPLAY_NAMES = {
        "discord": "Discord",
        "github": "GitHub",
        "battlenet": "Battle.net",  # For account-level achievements
    }

    # Group by rarity for summary (ONLY original claims count toward Mantle)
    rarity_counts = Counter()  # Only original claims
    achievements = []
    total_original = 0

    for credit, achievement, provider_account, game in credits:
        is_original = credit.is_original_claim if credit.is_original_claim is not None else True
        if is_original:
            rarity_counts[achievement.rarity_tier or "Common"] += 1
            total_original += 1

        # Determine game name: from Game table, or provider display name, or app_id
        if game and game.name:
            game_name = game.name
        elif provider_account.provider_name in PROVIDER_DISPLAY_NAMES:
            game_name = PROVIDER_DISPLAY_NAMES[provider_account.provider_name]
        else:
            game_name = achievement.app_id  # Fallback to app_id

        achievements.append({
            "id": achievement.id,
            "api_name": achievement.api_name,
            "app_id": achievement.app_id,
            "game_name": game_name,
            "display_name": achievement.display_name,
            "description": achievement.description,
            "icon_url": achievement.icon_url,
            "rarity_tier": achievement.rarity_tier,
            "effort_score": achievement.effort_score,
            "percent": achievement.percent,
            "hidden": achievement.hidden,
            "provider": provider_account.provider_name,
            "date_credited": credit.date_credited.isoformat() if credit.date_credited else None,
            "unlocked_at": credit.unlocked_at.isoformat() if credit.unlocked_at else None,
            "is_original_claim": is_original,  # For UI to show display-only badge
        })

    return {
        "total": total_original,  # Only original claims count
        "total_display": len(achievements),  # Total including reclaimed
        "by_rarity": dict(rarity_counts),  # Only original claims
        "achievements": achievements,
    }


@app.get("/api/me/forged-items")
async def get_forged_items_api(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Get all forged items for the current user.

    Returns pre-computed item data for Godot to render directly.
    No client-side calculation needed.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Get all forged items for this user (via wallet ownership or current_owner)
    # Also includes test-granted items (which have no achievement_credit_id)
    from sqlalchemy import select
    user_wallets = select(WalletAccount.id).where(WalletAccount.user_id == user.id)

    forged_items = (
        db.query(ForgedAchievement)
        .outerjoin(AchievementCredit, ForgedAchievement.achievement_credit_id == AchievementCredit.id)
        .outerjoin(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .filter(
            # User owns via wallet OR is current owner (from trading) OR owns via credit
            (ForgedAchievement.wallet_account_id.in_(user_wallets)) |
            (ForgedAchievement.current_owner_id == user.id) |
            (AchievementCredit.user_id == user.id)
        )
        .all()
    )

    items = []
    for forged in forged_items:
        # Get linked achievement info if available
        achievement = None
        if forged.achievement_credit and forged.achievement_credit.achievement:
            achievement = forged.achievement_credit.achievement

        items.append({
            # Item identity
            "forged_id": forged.id,  # ForgedAchievement.id - needed for bridge-out API
            "token_id": forged.token_id,
            "item_id": forged.item_id,
            "item_name": forged.item_name,
            "item_type": forged.item_type,
            "weapon_type": forged.weapon_type,  # Only for weapons (null for armor/shield/accessory)
            "item_rarity": forged.item_rarity,

            # Visual properties
            "effect_name": forged.effect_name,
            "effect_intensity": forged.effect_intensity,
            "glow_color": forged.glow_color,

            # Metadata
            "effort_tier": forged.effort_tier,
            "vintage_years": forged.vintage_years,
            "is_secret": forged.is_secret,
            "forged_at": forged.forged_at.isoformat() if forged.forged_at else None,

            # Source achievement (for tooltip/details) - may be null for test items
            "source": {
                "achievement_name": achievement.display_name if achievement else forged.item_name,
                "achievement_icon": achievement.icon_url if achievement else None,
                "app_id": achievement.app_id if achievement else None,
            } if achievement else None,

            # In-game claim status (prevents duping)
            "claimed_in_game": forged.claimed_in_game_at is not None,
            "claimed_in_game_at": forged.claimed_in_game_at.isoformat() if forged.claimed_in_game_at else None,

            # Bridge status for external wallet transfers
            "bridge_status": forged.bridge_status or "in_game",
        })

    return {
        "total": len(items),
        "forged_items": items,
    }


@app.post("/api/forge/claim-to-game")
async def claim_forged_item_to_game(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Claim a forged item to in-game inventory.

    This marks the item as claimed server-side to prevent duping.
    Once claimed, the item cannot be claimed again (until traded to another player
    who hasn't claimed it yet).

    Request body: {"token_id": int}
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    body = await request.json()
    token_id = body.get("token_id")
    if not token_id:
        raise HTTPException(status_code=400, detail="token_id required")

    # Find the forged item
    user_wallets = db.query(WalletAccount.id).filter(WalletAccount.user_id == user.id).subquery()
    forged = (
        db.query(ForgedAchievement)
        .outerjoin(AchievementCredit, ForgedAchievement.achievement_credit_id == AchievementCredit.id)
        .filter(
            ForgedAchievement.token_id == token_id,
            # Must own the item
            (ForgedAchievement.wallet_account_id.in_(user_wallets)) |
            (ForgedAchievement.current_owner_id == user.id) |
            (AchievementCredit.user_id == user.id)
        )
        .first()
    )

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found or not owned by you")

    # Check if already claimed
    if forged.claimed_in_game_at:
        raise HTTPException(status_code=409, detail="Item already claimed to game")

    # Mark as claimed
    from datetime import datetime
    forged.claimed_in_game_at = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "token_id": token_id,
        "claimed_at": forged.claimed_in_game_at.isoformat(),
    }


@app.post("/api/forge/unclaim-from-game")
async def unclaim_forged_item_from_game(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    DEBUG/ADMIN: Unclaim a forged item (reset claimed_in_game_at).
    Used for testing or if item is lost due to bugs.

    Request body: {"token_id": int}
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Only admins can unclaim (prevents exploit)
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    body = await request.json()
    token_id = body.get("token_id")
    if not token_id:
        raise HTTPException(status_code=400, detail="token_id required")

    forged = db.query(ForgedAchievement).filter(ForgedAchievement.token_id == token_id).first()
    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    forged.claimed_in_game_at = None
    db.commit()

    return {"success": True, "token_id": token_id, "message": "Item unclaimed from game"}


@app.get("/api/player/{user_id}/badge")
async def get_player_badge(
    user_id: int,
    db: DbSession = Depends(get_db),
):
    """
    PUBLIC endpoint for multiplayer badge lookup.

    Returns the player's Mantle tier badge info for display in-game.
    This is lightweight and cached-friendly for multiplayer use.

    Response:
    {
        "user_id": 123,
        "tier": "gold",
        "name": "Gold",
        "color": "#FFD700",
        "glow": "#DAA520",
        "effective_score": 1247
    }

    Returns 404 if user doesn't exist, or guest badge if no achievements.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Player not found")

    # Count achievements and providers
    provider_accounts = (
        db.query(ProviderAccount)
        .filter(ProviderAccount.user_id == user_id, ProviderAccount.is_active == True)
        .all()
    )

    provider_count = len(provider_accounts)
    total_achievements = (
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user_id,
            AchievementCredit.is_original_claim == True  # Only original claims!
        )
        .count()
    )

    # Calculate tier
    tier_info = calculate_mantle_tier(total_achievements, provider_count)

    return {
        "user_id": user_id,
        "tier": tier_info["tier"],
        "name": tier_info["name"],
        "color": tier_info["color"],
        "glow": tier_info["glow"],
        "effective_score": tier_info["effective_score"],
    }


@app.get("/api/tiers")
async def get_all_tiers():
    """
    Get all Mantle tier definitions.

    Useful for Godot to cache tier colors/thresholds locally.
    """
    return {
        "tiers": MANTLE_TIERS,
        "order": TIER_ORDER,
    }


# =============================================================================
# ITEM CATALOG & FORGE PREVIEW ENDPOINTS
# =============================================================================

@app.get("/api/catalog/items")
async def get_item_catalog(
    item_type: str = None,
    theme: str = None,
    available_only: bool = False,
):
    """
    Get item catalog for web dashboard browsing.

    Query params:
    - item_type: Filter by type (weapon, armor, shield, accessory)
    - theme: Filter by theme (dark_souls, steam, etc.)
    - available_only: Only show items with sprites ready
    """
    if available_only:
        items = get_available_items()
    elif item_type:
        items = get_items_by_type(item_type)
    elif theme:
        items = get_items_by_theme(theme)
    else:
        items = get_items()

    # Apply additional filters if multiple specified
    if item_type and not available_only:
        items = [i for i in items if i.get("item_type") == item_type]
    if theme:
        items = [i for i in items if i.get("theme") == theme]

    return {
        "total": len(items),
        "items": items,
        "summary": get_catalog_summary(),
    }


@app.get("/api/catalog/themes")
async def get_item_themes():
    """Get all available themes with their colors and effects."""
    return {
        "themes": get_themes(),
    }


@app.get("/api/catalog/mappings")
async def get_achievement_item_mappings():
    """
    Get all achievement→item mappings with full item details.

    This is the source of truth for Godot asset generation.
    Shows exactly which achievements map to which items,
    and which items still need sprites created.

    Response includes:
    - achievement_key: "app_id:api_name"
    - item_id: The mapped item
    - item: Full item definition (weapon_type, theme, visuals, etc.)
    - needs_sprites: True if item.has_sprites is false
    """
    mappings = get_mappings_with_items()

    # Summary stats
    total = len(mappings)
    needs_sprites = sum(1 for m in mappings if m.get("needs_sprites"))
    by_theme = {}
    by_weapon_type = {}

    for m in mappings:
        item = m.get("item")
        if item:
            theme = item.get("theme", "unknown")
            by_theme[theme] = by_theme.get(theme, 0) + 1

            if item.get("item_type") == "weapon":
                wtype = item.get("weapon_type", "unknown")
                by_weapon_type[wtype] = by_weapon_type.get(wtype, 0) + 1

    return {
        "total_mappings": total,
        "needs_sprites": needs_sprites,
        "ready": total - needs_sprites,
        "by_theme": by_theme,
        "by_weapon_type": by_weapon_type,
        "mappings": mappings,
    }


@app.post("/api/forge/preview")
async def preview_forge(
    achievement_id: int,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Preview what item an achievement would forge into.

    Useful for web dashboard to show "If you forge this, you'll get..."
    Does not require wallet connection or actually forge.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Get the achievement credit
    credit = (
        db.query(AchievementCredit, Achievement, ProviderAccount)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .join(ProviderAccount, AchievementCredit.provider_account_id == ProviderAccount.id)
        .filter(
            AchievementCredit.user_id == user.id,
            Achievement.id == achievement_id,
        )
        .first()
    )

    if not credit:
        raise HTTPException(status_code=404, detail="Achievement not found or not owned")

    credit_obj, achievement, provider_account = credit

    # Check if already forged
    existing_forge = db.query(ForgedAchievement).filter(
        ForgedAchievement.achievement_credit_id == credit_obj.id
    ).first()

    if existing_forge:
        return {
            "already_forged": True,
            "forged_at": existing_forge.forged_at.isoformat() if existing_forge.forged_at else None,
            "item": {
                "item_id": existing_forge.item_id,
                "item_name": existing_forge.item_name,
                "item_type": existing_forge.item_type,
                "weapon_type": existing_forge.weapon_type,
                "item_rarity": existing_forge.item_rarity,
                "effect_name": existing_forge.effect_name,
                "effect_intensity": existing_forge.effect_intensity,
                "glow_color": existing_forge.glow_color,
                "effort_tier": existing_forge.effort_tier,
                "vintage_years": existing_forge.vintage_years,
                "is_secret": existing_forge.is_secret,
            },
        }

    # Look up game name
    game = db.query(Game).filter(
        Game.app_id == achievement.app_id,
        Game.provider_account_id == provider_account.id
    ).first()
    game_name = game.name if game else achievement.app_id

    # Compute preview
    item_props = compute_forged_item(
        achievement_id=achievement.id,
        api_name=achievement.api_name,
        app_id=achievement.app_id,
        game_name=game_name,
        provider=provider_account.provider_name,
        rarity_tier=achievement.rarity_tier,
        effort_score=achievement.effort_score,
        hidden=achievement.hidden,
        unlocked_at=credit_obj.unlocked_at,
    )

    # Check forgeable requirements
    forgeable_tiers = ["Legendary", "Epic", "Rare"]
    can_forge = (
        achievement.rarity_tier in forgeable_tiers and
        credit_obj.is_original_claim
    )

    return {
        "already_forged": False,
        "can_forge": can_forge,
        "forge_blocked_reason": None if can_forge else (
            "Achievement must be Rare or higher" if achievement.rarity_tier not in forgeable_tiers
            else "Only original claims can be forged (reclaimed achievements are display-only)"
        ),
        "achievement": {
            "id": achievement.id,
            "display_name": achievement.display_name,
            "rarity_tier": achievement.rarity_tier,
            "is_original_claim": credit_obj.is_original_claim,
        },
        "preview_item": item_props,
    }


@app.get("/api/me/forge-status")
async def get_forge_status(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Get forge status summary for current user.

    Returns counts and lists of:
    - Already forged achievements (with bridge status)
    - Forgeable achievements (Rare+, original claims, not yet forged)
    - Unforgeable achievements (Common/Uncommon or reclaimed)

    Bridge status on forged items indicates:
    - in_game: Item usable in-game
    - bridging_out: 48h cooldown, item locked
    - bridged: Item in external wallet, not usable in-game
    - bridging_in: Being transferred back to platform
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    forgeable_tiers = ["Legendary", "Epic", "Rare"]

    # Get all achievement credits with forged data
    credits = (
        db.query(AchievementCredit, Achievement, ProviderAccount, ForgedAchievement)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .join(ProviderAccount, AchievementCredit.provider_account_id == ProviderAccount.id)
        .outerjoin(ForgedAchievement, ForgedAchievement.achievement_credit_id == AchievementCredit.id)
        .filter(AchievementCredit.user_id == user.id)
        .all()
    )

    forged = []
    forgeable = []
    unforgeable = []

    for credit, achievement, provider_account, forged_item in credits:
        is_forged = forged_item is not None
        can_forge = (
            achievement.rarity_tier in forgeable_tiers and
            credit.is_original_claim and
            not is_forged
        )

        item = {
            "credit_id": credit.id,
            "achievement_id": achievement.id,
            "display_name": achievement.display_name,
            "rarity_tier": achievement.rarity_tier,
            "provider": provider_account.provider_name,
            "is_original_claim": credit.is_original_claim,
        }

        if is_forged:
            # Include bridge status and item details for forged items
            item["forged_id"] = forged_item.id
            item["item_id"] = forged_item.item_id
            item["item_name"] = forged_item.item_name
            item["bridge_status"] = forged_item.bridge_status or "in_game"
            item["claimed_in_game"] = forged_item.claimed_in_game_at is not None
            item["usable_in_game"] = (
                forged_item.bridge_status in (None, "in_game") and
                forged_item.claimed_in_game_at is not None
            )
            forged.append(item)
        elif can_forge:
            forgeable.append(item)
        else:
            item["blocked_reason"] = (
                "Rarity too low" if achievement.rarity_tier not in forgeable_tiers
                else "Reclaimed achievement (display-only)"
            )
            unforgeable.append(item)

    # Count items by bridge status
    in_game_count = sum(1 for f in forged if f.get("bridge_status") == "in_game")
    bridging_out_count = sum(1 for f in forged if f.get("bridge_status") == "bridging_out")
    bridged_count = sum(1 for f in forged if f.get("bridge_status") == "bridged")

    # Check wallet status
    from app.routes.wallet_routes import _wallet_service
    chain_id = _wallet_service.CHAIN_ID if _wallet_service else 8453
    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == user.id,
        WalletAccount.chain_id == chain_id,
        WalletAccount.current_nonce.is_(None),
    ).first()

    return {
        "wallet_connected": wallet is not None,
        "wallet_address": wallet.wallet_address if wallet else None,
        "summary": {
            "forged": len(forged),
            "forgeable": len(forgeable),
            "unforgeable": len(unforgeable),
            "total": len(credits),
            # Bridge status breakdown
            "in_game": in_game_count,
            "bridging_out": bridging_out_count,
            "bridged": bridged_count,
        },
        "forged": forged,
        "forgeable": forgeable,
        "unforgeable": unforgeable,
    }


@app.post("/api/forge/claim")
async def forge_claim(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Forge an achievement into an item (TEST MODE - no blockchain required).

    This endpoint allows forging without wallet connection for testing.
    Creates a ForgedAchievement record with dummy chain data.

    Request body: {"achievement_id": int}

    For production, use /api/wallet/forge which requires real blockchain tx.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Parse achievement_id from request body
    try:
        body = await request.json()
        achievement_id = body.get("achievement_id")
    except:
        achievement_id = None

    if not achievement_id:
        raise HTTPException(status_code=400, detail="achievement_id is required")

    # Get the achievement credit
    credit_query = (
        db.query(AchievementCredit, Achievement, ProviderAccount)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .join(ProviderAccount, AchievementCredit.provider_account_id == ProviderAccount.id)
        .filter(AchievementCredit.user_id == user.id)
        .filter(Achievement.id == achievement_id)
    )

    credit_result = credit_query.first()

    if not credit_result:
        raise HTTPException(status_code=404, detail="Achievement not found or not owned")

    credit, achievement, provider_account = credit_result

    # Check if already forged
    existing = db.query(ForgedAchievement).filter(
        ForgedAchievement.achievement_credit_id == credit.id
    ).first()

    if existing:
        return {
            "success": False,
            "error": "Already forged",
            "forged_item": {
                "item_id": existing.item_id,
                "item_name": existing.item_name,
                "item_type": existing.item_type,
                "weapon_type": existing.weapon_type,
                "item_rarity": existing.item_rarity,
                "effect_name": existing.effect_name,
                "glow_color": existing.glow_color,
            }
        }

    # Look up game name
    game = db.query(Game).filter(
        Game.app_id == achievement.app_id,
        Game.provider_account_id == provider_account.id
    ).first()
    game_name = game.name if game else achievement.app_id

    # Compute item properties
    item_props = compute_forged_item(
        achievement_id=achievement.id,
        api_name=achievement.api_name,
        app_id=achievement.app_id,
        game_name=game_name,
        provider=provider_account.provider_name,
        rarity_tier=achievement.rarity_tier,
        effort_score=achievement.effort_score,
        hidden=achievement.hidden,
        unlocked_at=credit.unlocked_at,
    )

    # Get or create a test wallet for the user
    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == user.id
    ).first()

    if not wallet:
        # Create a dummy wallet for test forging
        wallet = WalletAccount(
            user_id=user.id,
            wallet_address=f"0x{'0' * 38}{user.id:02d}",  # Dummy address
            chain_id=137,  # Polygon
            linked_at=datetime.utcnow(),
        )
        db.add(wallet)
        db.flush()

    # Generate test token_id based on user and achievement
    import hashlib
    token_hash = hashlib.md5(f"{user.id}:{achievement.id}".encode()).hexdigest()
    test_token_id = int(token_hash[:8], 16)

    # Create the forged achievement record
    forge_record = ForgedAchievement(
        achievement_credit_id=credit.id,
        wallet_account_id=wallet.id,
        token_id=test_token_id,
        contract_address="0x0000000000000000000000000000000000000000",  # Test contract
        chain_id=137,
        tx_hash=f"0x{'0' * 62}test",  # Dummy tx hash
        item_type=item_props["item_type"],
        weapon_type=item_props.get("weapon_type"),
        item_id=item_props["item_id"],
        item_name=item_props["item_name"],
        item_rarity=item_props["item_rarity"],
        effect_intensity=item_props["effect_intensity"],
        effect_name=item_props["effect_name"],
        glow_color=item_props["glow_color"],
        effort_tier=item_props["effort_tier"],
        vintage_years=item_props["vintage_years"],
        is_secret=item_props["is_secret"],
    )
    db.add(forge_record)
    db.commit()

    logger.info(f"User {user.username} test-forged {achievement.display_name} -> {item_props['item_name']}")

    return {
        "success": True,
        "forged_item": item_props,
        "token_id": test_token_id,
        "achievement": {
            "id": achievement.id,
            "display_name": achievement.display_name,
            "rarity_tier": achievement.rarity_tier,
        }
    }


@app.post("/api/forge/test-grant-all")
async def test_grant_all_items(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    ADMIN/TESTER ONLY: Grant all catalog items to user for testing.

    Creates ForgedAchievement records for every item in items.json
    without requiring actual achievements. Used for testing the
    armory, trading, and equipment systems.
    """
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    # Only allow admins or users with specific test flag
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required for test grants")

    # Get or create test wallet
    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == user.id
    ).first()

    if not wallet:
        wallet = WalletAccount(
            user_id=user.id,
            wallet_address=f"0xtest{'0' * 34}{user.id:04d}",
            chain_id=137,
            linked_at=datetime.utcnow(),
        )
        db.add(wallet)
        db.flush()

    # Load items catalog
    from app.services.item_forge_service import get_items
    items = get_items()

    granted = []
    skipped = []

    for idx, item in enumerate(items):
        item_id = item.get("item_id", f"item_{idx}")

        # Check if already granted (by item_id)
        existing = db.query(ForgedAchievement).filter(
            ForgedAchievement.wallet_account_id == wallet.id,
            ForgedAchievement.item_id == item_id
        ).first()

        if existing:
            skipped.append(item_id)
            continue

        # Generate unique token_id
        import hashlib
        token_hash = hashlib.md5(f"test:{user.id}:{item_id}".encode()).hexdigest()
        test_token_id = int(token_hash[:8], 16)

        # Create a dummy achievement credit for this item
        # (or find existing one with matching item theme)

        # Create forged record
        forge_record = ForgedAchievement(
            achievement_credit_id=None,  # No real achievement
            wallet_account_id=wallet.id,
            token_id=test_token_id,
            contract_address="0x0000000000000000000000000000000000000000",
            chain_id=137,
            tx_hash=f"0xtest{idx:060d}",
            item_type=item.get("item_type", "weapon"),
            weapon_type=item.get("weapon_type"),
            item_id=item_id,
            item_name=item.get("item_name", item_id.replace("_", " ").title()),
            item_rarity=item.get("base_rarity", "common"),
            effect_intensity=0.7,
            effect_name=item.get("visuals", {}).get("effect", "standard_particles"),
            glow_color=item.get("visuals", {}).get("glow_color", "#888888"),
            effort_tier="Notable",
            vintage_years=0,
            is_secret=False,
        )
        db.add(forge_record)
        granted.append({
            "item_id": item_id,
            "item_name": item.get("item_name", item_id),
            "item_type": item.get("item_type"),
            "rarity": item.get("base_rarity"),
        })

    db.commit()

    logger.info(f"Admin {user.username} test-granted {len(granted)} items")

    return {
        "success": True,
        "granted_count": len(granted),
        "skipped_count": len(skipped),
        "granted": granted,
        "skipped": skipped,
    }


@app.get("/api/forge/catalog")
async def get_forge_catalog():
    """
    Get the full forge item catalog.

    Returns all items that can potentially be forged, with their
    visual data and effects. Used by Godot Armory to show available items.
    """
    from app.services.item_forge_service import get_items, get_themes, get_catalog_summary

    items = get_items()
    themes = get_themes()
    summary = get_catalog_summary()

    return {
        "items": items,
        "themes": themes,
        "summary": summary,
    }


@app.get("/api/providers")
async def get_available_providers():
    """
    Get list of available authentication providers.

    Returns providers grouped by capability:
    - gaming: Providers with achievement sync (Steam, Battle.net, Xbox, etc.)
    - social: Login-only providers (Discord, Twitch, Google, etc.)

    Useful for Godot to show available login options.
    """
    gaming = []
    social = []

    for name, config in get_enabled_providers().items():
        provider_info = {
            "name": name,
            "display_name": config.display_name,
            "color": config.color,
            "icon": f"/static/icons/{config.icon}",
            "has_achievements": config.achievement_support != AchievementSupport.NONE,
        }

        if config.achievement_support != AchievementSupport.NONE:
            gaming.append(provider_info)
        else:
            social.append(provider_info)

    return {
        "gaming": gaming,
        "social": social,
        "all": gaming + social,
    }


@app.get("/demo", response_class=HTMLResponse)
async def demo_dashboard(request: Request):
    """
    Demo dashboard with mock data showing all providers and achievements.
    Useful for UI development without needing real account connections.
    """
    # Mock providers with sample data (only implemented providers)
    mock_providers = [
        {
            "name": "steam",
            "display_name": "Steam",
            "icon_url": "/static/icons/steam.png",
            "avatar_url": "/static/icons/placeholder-avatar.svg",
            "user_id": "76561198012345678",
            "profile_display_name": "ProGamer_2024",
            "profile_data": {"personaname": "ProGamer_2024"},
            "total_achievements": 847,
            "by_rarity": {
                "Common": 412,
                "Uncommon": 203,
                "Rare": 156,
                "Epic": 64,
                "Legendary": 12
            },
        },
        {
            "name": "battlenet",
            "display_name": "Battle.net",
            "icon_url": "/static/icons/battlenet.png",
            "avatar_url": "/static/icons/placeholder-avatar.svg",
            "user_id": "Blizzard#1234",
            "profile_display_name": "Blizzard#1234",
            "profile_data": {
                "battletag": "Blizzard#1234",
                "top_character": {
                    "character_name": "Thrall",
                    "realm": "Area 52",
                    "avatar_url": "/static/icons/placeholder-avatar.svg"
                }
            },
            "total_achievements": 523,
            "by_rarity": {
                "Common": 245,
                "Uncommon": 134,
                "Rare": 89,
                "Epic": 42,
                "Legendary": 13
            },
        },
    ]

    all_providers = [
        {"name": "steam", "display_name": "Steam"},
        {"name": "battlenet", "display_name": "Battle.net"},
    ]

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "local_user_id": 999,  # Fake user ID for demo
            "country_code": "US",
            "all_providers": all_providers,
            "user_linked_providers": ["steam", "battlenet"],
            "providers": mock_providers,
            "is_demo": True,  # Flag to indicate demo mode
        },
    )


# =============================================================================
# ADMIN UTILITIES
# =============================================================================

@app.post("/api/admin/grant")
async def grant_admin(
    secret: str,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Grant admin status to the current user.
    Requires ADMIN_SECRET to be provided.
    Admins can bypass sync cooldowns for testing.
    """
    if secret != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail="Invalid admin secret")

    current_user.is_admin = True
    db.commit()
    logger.info(f"Admin granted to user {current_user.username} (ID: {current_user.id})")

    return {"status": "success", "message": f"Admin granted to {current_user.username}", "is_admin": True}


@app.post("/api/admin/revoke")
async def revoke_admin(
    secret: str,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Revoke admin status from the current user."""
    if secret != ADMIN_SECRET:
        raise HTTPException(status_code=403, detail="Invalid admin secret")

    current_user.is_admin = False
    db.commit()
    logger.info(f"Admin revoked from user {current_user.username} (ID: {current_user.id})")

    return {"status": "success", "message": f"Admin revoked from {current_user.username}", "is_admin": False}


@app.get("/api/admin/indexer-status")
async def get_indexer_status(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get transfer indexer status (admin only)."""
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    try:
        from app.services.transfer_indexer_service import get_indexer_status
        status = get_indexer_status()

        # Add pending bridge transactions count
        from app.models import BridgeTransaction
        pending_bridges = db.query(BridgeTransaction).filter(
            BridgeTransaction.status == "pending"
        ).count()
        status["pending_bridge_transactions"] = pending_bridges

        return status
    except ImportError:
        return {
            "running": False,
            "error": "Indexer service not available"
        }


@app.post("/api/admin/indexer-poll")
async def trigger_indexer_poll(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Manually trigger indexer poll (admin only)."""
    token = get_session_token(request)
    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user = get_user_from_session(db, token)
    if not user or not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")

    try:
        from app.services.transfer_indexer_service import manual_poll
        processed = await manual_poll()
        return {
            "success": True,
            "transfers_processed": processed
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }


# =============================================================================
# ROUTER INCLUSION (must be after specific routes like Steam to avoid conflicts)
# =============================================================================
app.include_router(generic_oauth_router)
app.include_router(wallet_router)
app.include_router(friend_router)
app.include_router(chat_router)
app.include_router(trading_router)
app.include_router(weapon_stats_router)
