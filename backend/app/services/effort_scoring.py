# app/services/effort_scoring.py
"""
Unified Effort Scoring System

All achievements across all providers are normalized to a 0-100 effort_score.
This allows fair comparison: a 1-hour achievement in WoW equals a 1-hour achievement in CS.

Tiers (computed from effort_score):
├── Common     (0-19)   → Gray
├── Uncommon   (20-39)  → Green
├── Rare       (40-59)  → Blue
├── Epic       (60-79)  → Purple
└── Legendary  (80-100) → Gold
"""

# =============================================================================
# CORE FUNCTIONS
# =============================================================================

def compute_rarity_from_effort(effort_score: float) -> str:
    """Convert effort_score (0-100) to rarity tier name."""
    if effort_score is None:
        return "Common"
    if effort_score >= 80:
        return "Legendary"
    if effort_score >= 60:
        return "Epic"
    if effort_score >= 40:
        return "Rare"
    if effort_score >= 20:
        return "Uncommon"
    return "Common"


def compute_effort_from_percent(global_percent: float) -> float:
    """
    Convert global unlock percentage to effort_score.
    Used for Steam, Xbox, PlayStation (platforms with global % data).

    Formula: effort_score = 100 - global_percent

    Examples:
    - 2% unlock rate  → effort_score = 98 → Legendary
    - 15% unlock rate → effort_score = 85 → Legendary
    - 35% unlock rate → effort_score = 65 → Epic
    - 60% unlock rate → effort_score = 40 → Rare
    - 85% unlock rate → effort_score = 15 → Common
    """
    if global_percent is None:
        return 30.0  # Default to Uncommon if no data

    try:
        percent = float(global_percent)
    except (ValueError, TypeError):
        return 30.0

    # Clamp to valid range
    percent = max(0.0, min(100.0, percent))

    return 100.0 - percent


# =============================================================================
# PROVIDER-SPECIFIC EFFORT CALCULATION
# =============================================================================

# Steam prestige achievements (always Legendary regardless of %)
STEAM_PRESTIGE_ACHIEVEMENTS = {
    # Dark Souls III
    "374320": ["THE_DARK_SOUL"],
    # Elden Ring
    "1245620": ["ELDEN_LORD"],
    # Sekiro
    "814380": ["ALL_SKILLS"],
}


def compute_steam_effort(app_id: str, api_name: str, global_percent: float) -> float:
    """
    Compute effort_score for a Steam achievement.

    - Prestige achievements → 95 (Legendary)
    - Otherwise → 100 - global_percent
    """
    # Check for hardcoded prestige achievements
    prestige_list = STEAM_PRESTIGE_ACHIEVEMENTS.get(str(app_id), [])
    if api_name in prestige_list:
        return 95.0  # Legendary

    return compute_effort_from_percent(global_percent)


def categorize_steam_achievement(app_id: str, api_name: str, global_percent: float) -> str:
    """
    Get rarity tier for a Steam achievement.
    Convenience wrapper that combines compute_steam_effort + compute_rarity_from_effort.
    """
    effort = compute_steam_effort(app_id, api_name, global_percent)
    return compute_rarity_from_effort(effort)


def compute_battlenet_effort(achievement_data: dict) -> float:
    """
    Compute effort_score for a Battle.net (WoW) achievement.

    - Feat of Strength → 90 (Legendary)
    - Legacy/removed → 95 (Legendary)
    - 50+ points → 70 (Epic)
    - 30+ points → 50 (Rare)
    - 10+ points → 30 (Uncommon)
    - Otherwise → 15 (Common)
    """
    points = achievement_data.get("points", 0)
    is_fos = (
        achievement_data.get("is_feat_of_strength", False) or
        achievement_data.get("category") == "Feats of Strength"
    )
    is_legacy = achievement_data.get("is_legacy", False)

    if is_legacy:
        return 95.0  # Legendary (unobtainable)
    if is_fos:
        return 90.0  # Legendary
    if points >= 50:
        return 70.0  # Epic
    if points >= 30:
        return 50.0  # Rare
    if points >= 10:
        return 30.0  # Uncommon
    return 15.0  # Common


def compute_xbox_effort(gamerscore: int, global_percent: float = None) -> float:
    """
    Compute effort_score for an Xbox achievement.

    - If global % available, use it (like Steam/PlayStation)
    - Otherwise fall back to Gamerscore tiers

    Gamerscore fallback tiers:
    - 100+ gamerscore → 85 (Legendary) - rare high-value achievements
    - 50+ gamerscore  → 65 (Epic)
    - 25+ gamerscore  → 45 (Rare)
    - 10+ gamerscore  → 25 (Uncommon) - standard achievements
    - <10 gamerscore  → 15 (Common) - easy/tutorial achievements
    """
    # Prefer global percent if available (more accurate than gamerscore)
    if global_percent is not None:
        return compute_effort_from_percent(global_percent)

    # Fallback to gamerscore tiers when no rarity data
    if gamerscore >= 100:
        return 85.0  # Legendary
    if gamerscore >= 50:
        return 65.0  # Epic
    if gamerscore >= 25:
        return 45.0  # Rare
    if gamerscore >= 10:
        return 25.0  # Uncommon
    return 15.0  # Common


def compute_playstation_effort(trophy_type: str, global_percent: float = None) -> float:
    """
    Compute effort_score for a PlayStation trophy.

    - If global % available, use it (like Steam)
    - Otherwise fall back to trophy grade
    """
    # Prefer global percent if available
    if global_percent is not None:
        return compute_effort_from_percent(global_percent)

    # Fallback to trophy type
    trophy_type = (trophy_type or "").lower()
    if trophy_type == "platinum":
        return 95.0  # Legendary
    if trophy_type == "gold":
        return 60.0  # Epic
    if trophy_type == "silver":
        return 40.0  # Rare
    if trophy_type == "bronze":
        return 20.0  # Uncommon
    return 15.0  # Common


# Alias for consistent naming
def compute_psn_effort(trophy_type: str = None, earn_rate: float = None) -> float:
    """Alias for compute_playstation_effort with named parameters."""
    return compute_playstation_effort(trophy_type=trophy_type, global_percent=earn_rate)


def compute_github_effort(badge_name: str, badge_tier: str = None) -> float:
    """
    Compute effort_score for a GitHub achievement badge.
    """
    badge_name = (badge_name or "").lower()
    badge_tier = (badge_tier or "").lower()

    # Legacy unobtainable badges
    if badge_name in ["arctic_code_vault", "mars_2020_mission", "arctic-code-vault", "mars-2020"]:
        return 95.0  # Legendary

    # Tiered badges
    if badge_tier == "gold":
        return 75.0  # Epic
    if badge_tier == "silver":
        return 50.0  # Rare
    if badge_tier == "bronze":
        return 30.0  # Uncommon

    return 20.0  # Uncommon (default badge)


def compute_reddit_effort(trophy_name: str) -> float:
    """
    Compute effort_score for a Reddit trophy.
    """
    trophy_name = (trophy_name or "").lower()

    # Legacy event trophies (unobtainable)
    legacy_events = [
        "team orangered", "team periwinkle",  # April Fools 2013
        "sequence",  # r/place 2023
        "the button", "pressiah",  # The Button
    ]
    if any(event in trophy_name for event in legacy_events):
        return 90.0  # Legendary

    # High-tier gilding
    if "gilding" in trophy_name and any(x in trophy_name for x in ["xi", "x", "ix"]):
        return 70.0  # Epic

    # Notable achievements
    if trophy_name in ["inciteful comment", "bellwether"]:
        return 60.0  # Epic

    # Common trophies
    if trophy_name in ["verified email", "new user"]:
        return 10.0  # Common

    return 30.0  # Uncommon (default)


def compute_discord_effort(badge_name: str) -> float:
    """
    Compute effort_score for a Discord badge.
    """
    badge_name = (badge_name or "").lower()

    # Staff/Partner (very rare)
    if badge_name in ["discord employee", "partnered server owner"]:
        return 95.0  # Legendary

    # Legacy badges (unobtainable)
    if badge_name in ["early supporter", "early verified bot dev"]:
        return 90.0  # Legendary

    # Bug hunters
    if "bug hunter level 2" in badge_name:
        return 70.0  # Epic
    if "bug hunter" in badge_name:
        return 50.0  # Rare

    # HypeSquad
    if "hypesquad" in badge_name:
        return 30.0  # Uncommon

    return 20.0  # Uncommon (default)


def compute_facebook_effort(friend_count: int) -> float:
    """
    Compute effort_score for Facebook based on friend count.

    Facebook has very limited data available via Graph API:
    - Account creation date: NOT exposed
    - Follower count: Deprecated since API v2.0 (2014)
    - Gaming achievements: Facebook Gaming shut down Oct 2024

    Friend count is the only reliable social metric available.

    Friend count distribution (approximate):
    - Median user: ~200 friends
    - 75th percentile: ~400 friends
    - 90th percentile: ~800 friends
    - Heavy users: 1000+ friends
    - Platform limit: 5000 friends
    """
    if friend_count is None:
        return 20.0  # Uncommon default

    if friend_count >= 4000:
        return 70.0  # Epic - approaching platform limit
    if friend_count >= 2000:
        return 55.0  # Rare - very social
    if friend_count >= 1000:
        return 40.0  # Rare - above average
    if friend_count >= 500:
        return 30.0  # Uncommon - engaged user
    if friend_count >= 200:
        return 20.0  # Uncommon - typical user

    return 15.0  # Common - light user


def compute_roblox_effort(win_rate_percentage: float) -> float:
    """
    Compute effort_score for a Roblox badge.

    Roblox badges have winRatePercentage which represents the percentage
    of players who visited the game and earned the badge. This is equivalent
    to Steam's global unlock percentage.

    Formula: effort_score = 100 - win_rate_percentage

    Examples:
    - 2% win rate   -> effort_score = 98 -> Legendary
    - 15% win rate  -> effort_score = 85 -> Legendary
    - 35% win rate  -> effort_score = 65 -> Epic
    - 60% win rate  -> effort_score = 40 -> Rare
    - 85% win rate  -> effort_score = 15 -> Common
    """
    if win_rate_percentage is None:
        return 30.0  # Uncommon default

    try:
        percent = float(win_rate_percentage)
    except (ValueError, TypeError):
        return 30.0

    # Clamp to valid range
    percent = max(0.0, min(100.0, percent))

    return 100.0 - percent


def compute_roblox_tenure_effort(account_age_years: float) -> float:
    """
    Compute effort_score for Roblox account tenure.

    Roblox launched in 2006, so accounts from 2006-2015 are OG status.

    - 10+ years (2015 or earlier): Legendary - OG player
    - 7+ years: Epic - veteran
    - 5+ years: Rare
    - 3+ years: Uncommon
    - 1+ years: Common
    """
    if account_age_years is None:
        return 15.0  # Common default

    if account_age_years >= 10:
        return 85.0  # Legendary - OG player
    if account_age_years >= 7:
        return 65.0  # Epic - veteran
    if account_age_years >= 5:
        return 45.0  # Rare
    if account_age_years >= 3:
        return 30.0  # Uncommon

    return 15.0  # Common
