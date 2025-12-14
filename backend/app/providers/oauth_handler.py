"""
Generic OAuth Handler

Handles OAuth2 login/callback for any provider in the registry.
Steam (OpenID) still needs special handling, but all OAuth2 providers
can use these generic routes.
"""

import os
import logging
from typing import Optional
from fastapi import APIRouter, Request, Depends, HTTPException
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session as DbSession
from authlib.integrations.starlette_client import OAuth
from sqlalchemy.exc import IntegrityError

from app.providers import (
    PROVIDERS,
    ProviderConfig,
    ProviderType,
    AchievementSupport,
    get_enabled_providers,
)

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/auth", tags=["auth"])

# OAuth instance - will be configured on startup
oauth = OAuth()

# Track which providers are registered
_registered_providers = set()


def init_oauth_providers():
    """
    Initialize OAuth clients for all enabled OAuth2 providers.
    Call this on app startup.
    """
    for name, config in get_enabled_providers().items():
        if config.type != ProviderType.OAUTH2:
            continue  # Skip non-OAuth2 (Steam is OpenID)

        if name in _registered_providers:
            continue  # Already registered

        client_id = os.getenv(config.client_id_env)
        client_secret = os.getenv(config.client_secret_env)

        if not client_id or not client_secret:
            logger.warning(f"Provider {name} enabled but missing credentials, skipping")
            continue

        # Register with authlib
        register_kwargs = {
            "name": name,
            "client_id": client_id,
            "client_secret": client_secret,
            "authorize_url": config.authorize_url,
            "access_token_url": config.token_url,
            "userinfo_endpoint": config.userinfo_url,
            "client_kwargs": {"scope": " ".join(config.scopes or [])},
        }

        # Add OIDC discovery URL if provided (needed for ID token verification)
        if hasattr(config, 'server_metadata_url') and config.server_metadata_url:
            register_kwargs["server_metadata_url"] = config.server_metadata_url

        oauth.register(**register_kwargs)

        _registered_providers.add(name)
        logger.info(f"Registered OAuth provider: {name}")


def get_provider_user_id(provider_name: str, token: dict, userinfo: dict) -> Optional[str]:
    """
    Extract the unique user ID from OAuth response.
    Different providers return ID in different fields.
    """
    # Common patterns for user ID field
    id_fields = ["sub", "id", "user_id", "account_id", "uid"]

    # Provider-specific overrides
    provider_id_map = {
        "discord": lambda t, u: str(u.get("id")),
        "twitch": lambda t, u: str(u.get("data", [{}])[0].get("id")) if u.get("data") else None,
        "google": lambda t, u: u.get("sub") or u.get("id"),
        "github": lambda t, u: str(u.get("id")),
        "twitter": lambda t, u: u.get("data", {}).get("id"),
        "reddit": lambda t, u: u.get("id"),
        "spotify": lambda t, u: u.get("id"),
        "facebook": lambda t, u: str(u.get("id")),
        "roblox": lambda t, u: str(u.get("sub") or u.get("id")),
        "battlenet": lambda t, u: str(token.get("sub") or u.get("sub") or u.get("id")),
        "xbox": lambda t, u: u.get("xuid") or u.get("sub"),
        "playstation": lambda t, u: u.get("account_id") or u.get("sub"),
        "epic": lambda t, u: u.get("sub") or u.get("account_id"),
        "gog": lambda t, u: u.get("sub") or u.get("user_id"),
    }

    # Try provider-specific extraction first
    if provider_name in provider_id_map:
        try:
            user_id = provider_id_map[provider_name](token, userinfo)
            if user_id:
                return str(user_id)
        except Exception as e:
            logger.warning(f"Provider-specific ID extraction failed for {provider_name}: {e}")

    # Fallback: try common field names
    for field in id_fields:
        if field in userinfo and userinfo[field]:
            return str(userinfo[field])
        if field in token and token[field]:
            return str(token[field])

    logger.error(f"Could not extract user ID for {provider_name}. Token: {token}, Userinfo: {userinfo}")
    return None


def get_display_name(provider_name: str, userinfo: dict) -> Optional[str]:
    """Extract display name from userinfo"""
    name_fields = {
        "discord": ["username", "global_name"],
        "twitch": ["data.0.display_name", "data.0.login"],
        "google": ["name", "email"],
        "github": ["login", "name"],
        "twitter": ["data.username", "data.name"],
        "reddit": ["name"],
        "spotify": ["display_name"],
        "facebook": ["name"],
        "roblox": ["preferred_username", "name", "nickname"],
        "battlenet": ["battletag"],
        "xbox": ["gamertag"],
        "playstation": ["online_id"],
        "epic": ["displayName", "preferred_username"],
        "gog": ["username"],
    }

    fields = name_fields.get(provider_name, ["name", "username", "login", "display_name", "email"])

    for field in fields:
        if "." in field:
            # Handle nested fields like "data.0.display_name"
            parts = field.split(".")
            value = userinfo
            try:
                for part in parts:
                    if part.isdigit():
                        value = value[int(part)]
                    else:
                        value = value.get(part)
                    if value is None:
                        break
                if value:
                    return str(value)
            except (KeyError, IndexError, TypeError):
                continue
        elif field in userinfo and userinfo[field]:
            return str(userinfo[field])

    return None


def get_avatar_url(provider_name: str, userinfo: dict) -> Optional[str]:
    """Extract avatar URL from userinfo"""
    avatar_fields = {
        "discord": lambda u: f"https://cdn.discordapp.com/avatars/{u['id']}/{u['avatar']}.png" if u.get("avatar") else None,
        "twitch": lambda u: u.get("data", [{}])[0].get("profile_image_url"),
        "google": lambda u: u.get("picture"),
        "github": lambda u: u.get("avatar_url"),
        "twitter": lambda u: u.get("data", {}).get("profile_image_url"),
        "reddit": lambda u: u.get("icon_img", "").split("?")[0] if u.get("icon_img") else None,
        "spotify": lambda u: u.get("images", [{}])[0].get("url") if u.get("images") else None,
        "facebook": lambda u: f"https://graph.facebook.com/{u['id']}/picture?type=large" if u.get("id") else None,
        "roblox": lambda u: f"https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={u.get('sub') or u.get('id')}&size=150x150&format=Png" if (u.get("sub") or u.get("id")) else None,
    }

    if provider_name in avatar_fields:
        try:
            return avatar_fields[provider_name](userinfo)
        except Exception:
            pass

    # Fallback
    for field in ["avatar_url", "picture", "avatar", "image", "profile_image_url"]:
        if field in userinfo and userinfo[field]:
            return userinfo[field]

    return None


# =============================================================================
# ROUTE FACTORY
# =============================================================================

def create_oauth_routes(
    get_db,
    get_session_token,
    get_user_from_session,
    create_session,
    set_session_cookie,
    create_new_user_with_provider,
    get_user_by_provider,
    templates,
    app_url: str,
):
    """
    Factory function to create OAuth routes with access to app dependencies.
    Returns a configured router.
    """

    @router.get("/{provider}/login")
    async def generic_oauth_login(
        provider: str,
        request: Request,
        db: DbSession = Depends(get_db),
        device_code: Optional[str] = None,
    ):
        """Generic OAuth2 login handler for any registered provider"""

        # Check provider exists and is enabled
        config = PROVIDERS.get(provider)
        if not config or not config.enabled:
            raise HTTPException(status_code=404, detail=f"Provider '{provider}' not found or not enabled")

        # Steam uses OpenID, not OAuth2 - has dedicated routes in main.py
        # Return 404 to let the specific route handle it (shouldn't reach here anyway)
        if config.type == ProviderType.OPENID:
            raise HTTPException(status_code=404, detail=f"Use dedicated /auth/{provider}/login route")

        # Check if provider is registered with authlib
        if provider not in _registered_providers:
            raise HTTPException(status_code=503, detail=f"Provider '{provider}' not configured (missing credentials)")

        # Check if user already has this provider linked
        token = get_session_token(request)
        if token:
            current_user = get_user_from_session(db, token)
            if current_user:
                from app.models import ProviderAccount
                existing = (
                    db.query(ProviderAccount)
                    .filter_by(user_id=current_user.id, provider_name=provider, is_active=True)
                    .first()
                )
                if existing:
                    return templates.TemplateResponse(
                        "merge_failed.html",
                        {"request": request, "message": f"You already have a {config.display_name} account linked."}
                    )

        # Build callback URL (do NOT include device_code in URL - causes double-encoding issues)
        # Device code is stored in session instead and retrieved in callback
        callback_url = f"{app_url}/auth/{provider}/callback"

        # Store device_code in session for callback
        if device_code:
            request.session["device_code"] = device_code
            logger.info(f"[{provider.upper()}] Stored device_code {device_code[:8]}... in session")

        logger.info(f"Initiating {provider} login flow")

        # Redirect to OAuth provider
        client = getattr(oauth, provider)
        return await client.authorize_redirect(request, callback_url)

    @router.get("/{provider}/callback")
    async def generic_oauth_callback(
        provider: str,
        request: Request,
        db: DbSession = Depends(get_db),
    ):
        """Generic OAuth2 callback handler"""
        from app.models import ProviderAccount, User

        config = PROVIDERS.get(provider)
        if not config or not config.enabled:
            raise HTTPException(status_code=404, detail=f"Provider '{provider}' not found")

        # Steam uses OpenID - should have been redirected
        if config.type == ProviderType.OPENID:
            raise HTTPException(status_code=400, detail="Use /auth/steam/callback for Steam")

        if provider not in _registered_providers:
            raise HTTPException(status_code=503, detail=f"Provider '{provider}' not configured")

        try:
            client = getattr(oauth, provider)
            token = await client.authorize_access_token(request)

            # Get user info
            userinfo = {}
            if config.userinfo_url:
                resp = await client.get(config.userinfo_url, token=token)
                userinfo = resp.json()

            # Extract provider user ID
            provider_user_id = get_provider_user_id(provider, token, userinfo)
            if not provider_user_id:
                logger.error(f"Failed to get user ID from {provider}")
                return templates.TemplateResponse(
                    "merge_failed.html",
                    {"request": request, "message": f"{config.display_name} login failed: Could not retrieve user ID."}
                )

            # Build profile data
            profile_data = {
                "display_name": get_display_name(provider, userinfo),
                "avatar_url": get_avatar_url(provider, userinfo),
                "raw_userinfo": userinfo,  # Store full response for debugging
            }

            # Get device_code from session if present
            device_code = request.session.pop("device_code", None) or request.query_params.get("device_code")

            # Check if user is logged in (claim flow)
            session_token = get_session_token(request)
            current_user = get_user_from_session(db, session_token) if session_token else None

            if current_user:
                # === CLAIM FLOW ===
                logger.info(f"{provider} callback: claim flow for user {current_user.username}")

                # Check if provider is already claimed by someone
                existing_account = db.query(ProviderAccount).filter_by(
                    provider_name=provider,
                    provider_user_id=provider_user_id,
                    is_active=True
                ).first()

                if existing_account:
                    if existing_account.user_id == current_user.id:
                        # Same user, same account - just update token and redirect
                        existing_account.access_token = token.get("access_token")
                        existing_account.profile_data = profile_data
                        db.commit()
                        return RedirectResponse(url="/dashboard", status_code=303)
                    else:
                        # Different user owns this account - offer merge
                        other_user = db.query(User).filter_by(id=existing_account.user_id).first()
                        return templates.TemplateResponse(
                            "merge_confirm.html",
                            {
                                "request": request,
                                "target_provider": provider,
                                "other_username": other_user.username if other_user else "Unknown",
                                "other_user_id": existing_account.user_id,
                                "current_user_id": current_user.id,
                            }
                        )

                # Check for inactive (unclaimed) account
                inactive_account = db.query(ProviderAccount).filter_by(
                    provider_name=provider,
                    provider_user_id=provider_user_id,
                    is_active=False
                ).first()

                if inactive_account:
                    # Reactivate and assign to current user
                    inactive_account.user_id = current_user.id
                    inactive_account.is_active = True
                    inactive_account.unclaimed_at = None
                    inactive_account.access_token = token.get("access_token")
                    inactive_account.profile_data = profile_data
                    db.commit()
                    logger.info(f"User {current_user.username} reclaimed {provider} {provider_user_id}")
                    return RedirectResponse(url="/dashboard", status_code=303)

                # Create new provider account
                new_account = ProviderAccount(
                    provider_name=provider,
                    provider_user_id=provider_user_id,
                    user_id=current_user.id,
                    is_active=True,
                    access_token=token.get("access_token"),
                    profile_data=profile_data,
                )
                db.add(new_account)
                try:
                    db.commit()
                    logger.info(f"User {current_user.username} linked {provider} {provider_user_id}")
                    return RedirectResponse(url="/dashboard", status_code=303)
                except IntegrityError:
                    db.rollback()
                    logger.warning(f"Race condition: {provider} {provider_user_id} claimed by another request")
                    return RedirectResponse(url="/dashboard", status_code=303)

            else:
                # === LOGIN FLOW ===
                logger.info(f"{provider} callback: login flow")

                # Check for existing active account
                existing_user = get_user_by_provider(db, provider, provider_user_id)
                if existing_user:
                    # Update token and login
                    account = db.query(ProviderAccount).filter_by(
                        provider_name=provider,
                        provider_user_id=provider_user_id,
                        is_active=True
                    ).first()
                    if account:
                        account.access_token = token.get("access_token")
                        account.profile_data = profile_data
                        db.commit()

                    # Create session
                    if device_code:
                        from app.main import complete_device_auth
                        session_token = create_session(db, existing_user)
                        complete_device_auth(device_code, existing_user.id, existing_user.username, session_token)
                        return templates.TemplateResponse(
                            "auth_success.html",
                            {"request": request, "username": existing_user.username, "provider": provider}
                        )
                    else:
                        response = RedirectResponse(url="/dashboard", status_code=303)
                        session_token = create_session(db, existing_user)
                        set_session_cookie(response, session_token)
                        return response

                # Check for inactive account (was unlinked)
                # Philosophy: Provider accounts can move freely between Mantle accounts.
                # Anti-exploit is handled by AchievementCredit.is_original_claim, not provider binding.
                inactive_account = db.query(ProviderAccount).filter_by(
                    provider_name=provider,
                    provider_user_id=provider_user_id,
                    is_active=False
                ).first()

                if inactive_account:
                    # User intentionally unlinked - delete orphan and allow fresh account
                    logger.info(f"{provider} LOGIN: Inactive provider found (was unlinked), deleting for fresh account")
                    db.delete(inactive_account)
                    db.commit()

                # Create new user
                new_user = create_new_user_with_provider(
                    db, provider, provider_user_id,
                    profile_data=profile_data,
                    access_token=token.get("access_token")
                )

                if device_code:
                    from app.main import complete_device_auth
                    session_token = create_session(db, new_user)
                    complete_device_auth(device_code, new_user.id, new_user.username, session_token)
                    return templates.TemplateResponse(
                        "auth_success.html",
                        {"request": request, "username": new_user.username, "provider": provider}
                    )
                else:
                    response = RedirectResponse(url="/dashboard", status_code=303)
                    session_token = create_session(db, new_user)
                    set_session_cookie(response, session_token)
                    return response

        except Exception as e:
            logger.error(f"{provider} OAuth callback error: {e}", exc_info=True)
            return templates.TemplateResponse(
                "merge_failed.html",
                {"request": request, "message": f"{config.display_name} login error. Please try again later."}
            )

    return router
