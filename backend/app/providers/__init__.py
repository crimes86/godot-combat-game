# Provider Registry System
# Add new OAuth providers by adding to PROVIDERS dict - no code changes needed for basic login

from enum import Enum
from typing import Optional, Callable
from dataclasses import dataclass


class ProviderType(Enum):
    OAUTH2 = "oauth2"
    OPENID = "openid"  # Steam uses this
    LOCAL = "local"    # Email/password


class AchievementSupport(Enum):
    NONE = "none"           # Login only (Discord, Google, etc.)
    BASIC = "basic"         # Has achievements, simple API
    FULL = "full"           # Rich achievement data with rarity
    CUSTOM = "custom"       # Needs custom sync logic


@dataclass
class ProviderConfig:
    """Configuration for an OAuth provider"""
    name: str
    display_name: str
    type: ProviderType

    # OAuth settings
    client_id_env: str              # Environment variable name
    client_secret_env: str          # Environment variable name
    authorize_url: str
    token_url: str
    userinfo_url: Optional[str] = None
    server_metadata_url: Optional[str] = None  # OIDC discovery URL
    scopes: list = None

    # Achievement support
    achievement_support: AchievementSupport = AchievementSupport.NONE
    achievement_sync_fn: Optional[str] = None  # Function name for custom sync

    # Display
    icon: str = ""                  # Icon filename
    color: str = "#666666"          # Brand color
    enabled: bool = True            # Can disable without removing

    # Rate limiting
    rate_limit_per_minute: int = 60


# =============================================================================
# PROVIDER REGISTRY
# =============================================================================
# Add new providers here - the system will auto-generate routes

PROVIDERS = {
    # =========================================================================
    # GAMING PLATFORMS (with achievements)
    # =========================================================================
    "steam": ProviderConfig(
        name="steam",
        display_name="Steam",
        type=ProviderType.OPENID,
        client_id_env="STEAM_API_KEY",  # Steam uses API key, not OAuth
        client_secret_env="STEAM_API_KEY",
        authorize_url="https://steamcommunity.com/openid/login",
        token_url="",  # OpenID doesn't use token endpoint
        achievement_support=AchievementSupport.FULL,
        achievement_sync_fn="sync_steam_achievements",
        icon="steam.svg",
        color="#1b9bd7",
    ),

    "battlenet": ProviderConfig(
        name="battlenet",
        display_name="Battle.net",
        type=ProviderType.OAUTH2,
        client_id_env="BATTLENET_CLIENT_ID",
        client_secret_env="BATTLENET_CLIENT_SECRET",
        authorize_url="https://oauth.battle.net/authorize",
        token_url="https://oauth.battle.net/token",
        userinfo_url="https://oauth.battle.net/userinfo",
        scopes=["openid"],
        achievement_support=AchievementSupport.FULL,
        achievement_sync_fn="sync_all_battlenet_achievements",  # Syncs WoW, D3, SC2
        icon="battlenet.svg",
        color="#ffb932",
    ),

    "xbox": ProviderConfig(
        name="xbox",
        display_name="Xbox",
        type=ProviderType.OAUTH2,
        client_id_env="OPENXBL_API_KEY",  # OpenXBL app key
        client_secret_env="OPENXBL_API_KEY",  # Same key used for API calls
        authorize_url="https://xbl.io/app/auth",  # OpenXBL handles Microsoft OAuth
        token_url="https://xbl.io/app/claim",  # Exchange code for app key
        scopes=[],  # OpenXBL handles scopes
        achievement_support=AchievementSupport.FULL,
        achievement_sync_fn="sync_xbox_achievements",
        icon="xbox.svg",
        color="#107c10",
        enabled=True,  # Enabled via OpenXBL
    ),

    "psn": ProviderConfig(
        name="psn",
        display_name="PlayStation",
        type=ProviderType.LOCAL,  # User provides NPSSO token manually
        client_id_env="PSN_NPSSO",  # User's NPSSO token (not a real client ID)
        client_secret_env="PSN_NPSSO",
        authorize_url="",  # No OAuth - user gets NPSSO from browser
        token_url="",
        scopes=[],
        achievement_support=AchievementSupport.FULL,
        achievement_sync_fn="sync_psn_achievements",
        icon="playstation.svg",
        color="#003791",
        enabled=True,  # Enabled via NPSSO token
    ),

    "roblox": ProviderConfig(
        name="roblox",
        display_name="Roblox",
        type=ProviderType.OAUTH2,
        client_id_env="ROBLOX_CLIENT_ID",
        client_secret_env="ROBLOX_CLIENT_SECRET",
        authorize_url="https://apis.roblox.com/oauth/v1/authorize",
        token_url="https://apis.roblox.com/oauth/v1/token",
        userinfo_url="https://apis.roblox.com/oauth/v1/userinfo",
        server_metadata_url="https://apis.roblox.com/oauth/.well-known/openid-configuration",
        scopes=["openid", "profile"],
        achievement_support=AchievementSupport.FULL,
        achievement_sync_fn="sync_roblox_achievements",
        icon="roblox.svg",
        color="#00A2FF",
        enabled=True,
    ),

    "epic": ProviderConfig(
        name="epic",
        display_name="Epic Games",
        type=ProviderType.OAUTH2,
        client_id_env="EPIC_CLIENT_ID",
        client_secret_env="EPIC_CLIENT_SECRET",
        authorize_url="https://www.epicgames.com/id/authorize",
        token_url="https://api.epicgames.dev/epic/oauth/v1/token",
        scopes=["basic_profile"],
        achievement_support=AchievementSupport.BASIC,
        icon="epic.svg",
        color="#313131",
        enabled=False,
    ),

    "gog": ProviderConfig(
        name="gog",
        display_name="GOG Galaxy",
        type=ProviderType.OAUTH2,
        client_id_env="GOG_CLIENT_ID",
        client_secret_env="GOG_CLIENT_SECRET",
        authorize_url="https://auth.gog.com/auth",
        token_url="https://auth.gog.com/token",
        scopes=["openid"],
        achievement_support=AchievementSupport.BASIC,
        icon="gog.svg",
        color="#a453ff",
        enabled=False,
    ),

    "google_play": ProviderConfig(
        name="google_play",
        display_name="Google Play Games",
        type=ProviderType.OAUTH2,
        client_id_env="GOOGLE_PLAY_CLIENT_ID",
        client_secret_env="GOOGLE_PLAY_CLIENT_SECRET",
        authorize_url="https://accounts.google.com/o/oauth2/v2/auth",
        token_url="https://oauth2.googleapis.com/token",
        userinfo_url="https://www.googleapis.com/oauth2/v2/userinfo",
        server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
        scopes=["openid", "email", "profile"],
        achievement_support=AchievementSupport.NONE,  # Login only - Google doesn't expose cross-game achievements
        icon="google_play.svg",
        color="#34A853",
        enabled=True,
    ),

    # =========================================================================
    # SOCIAL PLATFORMS (login only - no achievements)
    # =========================================================================
    "discord": ProviderConfig(
        name="discord",
        display_name="Discord",
        type=ProviderType.OAUTH2,
        client_id_env="DISCORD_CLIENT_ID",
        client_secret_env="DISCORD_CLIENT_SECRET",
        authorize_url="https://discord.com/api/oauth2/authorize",
        token_url="https://discord.com/api/oauth2/token",
        userinfo_url="https://discord.com/api/users/@me",
        scopes=["identify", "connections"],
        achievement_support=AchievementSupport.BASIC,  # Has connections data
        icon="discord.svg",
        color="#5865F2",
        enabled=True,
    ),

    "twitch": ProviderConfig(
        name="twitch",
        display_name="Twitch",
        type=ProviderType.OAUTH2,
        client_id_env="TWITCH_CLIENT_ID",
        client_secret_env="TWITCH_CLIENT_SECRET",
        authorize_url="https://id.twitch.tv/oauth2/authorize",
        token_url="https://id.twitch.tv/oauth2/token",
        userinfo_url="https://api.twitch.tv/helix/users",
        scopes=["user:read:email"],
        achievement_support=AchievementSupport.NONE,
        icon="twitch.svg",
        color="#9146FF",
        enabled=False,
    ),

    "google": ProviderConfig(
        name="google",
        display_name="Google",
        type=ProviderType.OAUTH2,
        client_id_env="GOOGLE_CLIENT_ID",
        client_secret_env="GOOGLE_CLIENT_SECRET",
        authorize_url="https://accounts.google.com/o/oauth2/v2/auth",
        token_url="https://oauth2.googleapis.com/token",
        userinfo_url="https://www.googleapis.com/oauth2/v2/userinfo",
        scopes=["openid", "email", "profile"],
        achievement_support=AchievementSupport.NONE,
        icon="google.svg",
        color="#4285F4",
        enabled=False,
    ),

    "github": ProviderConfig(
        name="github",
        display_name="GitHub",
        type=ProviderType.OAUTH2,
        client_id_env="GITHUB_CLIENT_ID",
        client_secret_env="GITHUB_CLIENT_SECRET",
        authorize_url="https://github.com/login/oauth/authorize",
        token_url="https://github.com/login/oauth/access_token",
        userinfo_url="https://api.github.com/user",
        scopes=["read:user"],
        achievement_support=AchievementSupport.BASIC,  # Has profile achievements
        icon="github.svg",
        color="#333333",
        enabled=True,
    ),

    "twitter": ProviderConfig(
        name="twitter",
        display_name="X (Twitter)",
        type=ProviderType.OAUTH2,
        client_id_env="TWITTER_CLIENT_ID",
        client_secret_env="TWITTER_CLIENT_SECRET",
        authorize_url="https://twitter.com/i/oauth2/authorize",
        token_url="https://api.twitter.com/2/oauth2/token",
        userinfo_url="https://api.twitter.com/2/users/me",
        scopes=["users.read", "tweet.read"],
        achievement_support=AchievementSupport.NONE,
        icon="twitter.svg",
        color="#1DA1F2",
        enabled=False,
    ),

    "reddit": ProviderConfig(
        name="reddit",
        display_name="Reddit",
        type=ProviderType.OAUTH2,
        client_id_env="REDDIT_CLIENT_ID",
        client_secret_env="REDDIT_CLIENT_SECRET",
        authorize_url="https://www.reddit.com/api/v1/authorize",
        token_url="https://www.reddit.com/api/v1/access_token",
        userinfo_url="https://oauth.reddit.com/api/v1/me",
        scopes=["identity"],
        achievement_support=AchievementSupport.NONE,
        icon="reddit.svg",
        color="#FF4500",
        enabled=False,
    ),

    "facebook": ProviderConfig(
        name="facebook",
        display_name="Facebook",
        type=ProviderType.OAUTH2,
        client_id_env="FACEBOOK_APP_ID",
        client_secret_env="FACEBOOK_APP_SECRET",
        authorize_url="https://www.facebook.com/v19.0/dialog/oauth",
        token_url="https://graph.facebook.com/v19.0/oauth/access_token",
        userinfo_url="https://graph.facebook.com/v19.0/me",
        scopes=["public_profile"],
        achievement_support=AchievementSupport.NONE,  # Login only - no achievements
        icon="facebook.svg",
        color="#1877F2",
        enabled=False,  # Requires business verification
    ),

    "spotify": ProviderConfig(
        name="spotify",
        display_name="Spotify",
        type=ProviderType.OAUTH2,
        client_id_env="SPOTIFY_CLIENT_ID",
        client_secret_env="SPOTIFY_CLIENT_SECRET",
        authorize_url="https://accounts.spotify.com/authorize",
        token_url="https://accounts.spotify.com/api/token",
        userinfo_url="https://api.spotify.com/v1/me",
        scopes=["user-read-private"],
        achievement_support=AchievementSupport.NONE,
        icon="spotify.svg",
        color="#1DB954",
        enabled=False,
    ),
}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_enabled_providers() -> dict:
    """Get all enabled providers"""
    return {k: v for k, v in PROVIDERS.items() if v.enabled}


def get_providers_with_achievements() -> dict:
    """Get providers that have achievement support"""
    return {
        k: v for k, v in PROVIDERS.items()
        if v.enabled and v.achievement_support != AchievementSupport.NONE
    }


def get_login_only_providers() -> dict:
    """Get providers that are login-only (no achievements)"""
    return {
        k: v for k, v in PROVIDERS.items()
        if v.enabled and v.achievement_support == AchievementSupport.NONE
    }


def get_provider(name: str) -> Optional[ProviderConfig]:
    """Get a provider by name"""
    return PROVIDERS.get(name)
