# app/services/github_services.py
"""
GitHub achievement sync via GitHub REST API.

Creates achievements based on GitHub activity metrics:
- Account tenure
- Public repos
- Stars received
- Followers
- Contributions
"""

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from app.models import Achievement, AchievementCredit, ProviderAccount, User
from app.services.effort_scoring import compute_rarity_from_effort
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

GITHUB_API_BASE = "https://api.github.com"

# GitHub activity-based achievements
# Thresholds and effort scores for each metric
GITHUB_ACHIEVEMENTS = {
    # Account Tenure (years)
    "tenure": {
        "name": "GitHub Veteran",
        "description": "Years on GitHub",
        "tiers": [
            {"threshold": 10, "tier": "gold", "effort": 80, "suffix": "10+ Years"},
            {"threshold": 5, "tier": "silver", "effort": 55, "suffix": "5+ Years"},
            {"threshold": 2, "tier": "bronze", "effort": 30, "suffix": "2+ Years"},
            {"threshold": 1, "tier": "default", "effort": 15, "suffix": "1+ Year"},
        ]
    },
    # Public Repositories
    "repos": {
        "name": "Repository Creator",
        "description": "Public repositories created",
        "tiers": [
            {"threshold": 100, "tier": "gold", "effort": 75, "suffix": "100+ Repos"},
            {"threshold": 50, "tier": "silver", "effort": 55, "suffix": "50+ Repos"},
            {"threshold": 20, "tier": "bronze", "effort": 35, "suffix": "20+ Repos"},
            {"threshold": 5, "tier": "default", "effort": 20, "suffix": "5+ Repos"},
        ]
    },
    # Stars Received (across all repos)
    "stars": {
        "name": "Starstruck",
        "description": "Stars received on repositories",
        "tiers": [
            {"threshold": 1000, "tier": "gold", "effort": 90, "suffix": "1000+ Stars"},
            {"threshold": 100, "tier": "silver", "effort": 65, "suffix": "100+ Stars"},
            {"threshold": 25, "tier": "bronze", "effort": 45, "suffix": "25+ Stars"},
            {"threshold": 5, "tier": "default", "effort": 25, "suffix": "5+ Stars"},
        ]
    },
    # Followers
    "followers": {
        "name": "Influencer",
        "description": "GitHub followers",
        "tiers": [
            {"threshold": 500, "tier": "gold", "effort": 85, "suffix": "500+ Followers"},
            {"threshold": 100, "tier": "silver", "effort": 60, "suffix": "100+ Followers"},
            {"threshold": 25, "tier": "bronze", "effort": 40, "suffix": "25+ Followers"},
            {"threshold": 5, "tier": "default", "effort": 20, "suffix": "5+ Followers"},
        ]
    },
    # Public Gists
    "gists": {
        "name": "Code Sharer",
        "description": "Public gists created",
        "tiers": [
            {"threshold": 50, "tier": "gold", "effort": 70, "suffix": "50+ Gists"},
            {"threshold": 20, "tier": "silver", "effort": 50, "suffix": "20+ Gists"},
            {"threshold": 10, "tier": "bronze", "effort": 35, "suffix": "10+ Gists"},
            {"threshold": 3, "tier": "default", "effort": 20, "suffix": "3+ Gists"},
        ]
    },
}


async def get_github_user(access_token: str) -> dict:
    """Fetch GitHub user info via REST API."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    async with httpx.AsyncClient() as client:
        resp = await client.get(f"{GITHUB_API_BASE}/user", headers=headers)
        logger.info(f"[GITHUB] User API status: {resp.status_code}")

        if resp.status_code == 401:
            raise Exception("GitHub token expired or invalid")

        if resp.status_code != 200:
            raise Exception(f"GitHub API error: {resp.status_code} - {resp.text[:200]}")

        return resp.json()


async def get_github_repos(access_token: str, username: str) -> list:
    """Fetch user's public repositories to calculate total stars."""
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    all_repos = []
    page = 1

    async with httpx.AsyncClient() as client:
        while True:
            resp = await client.get(
                f"{GITHUB_API_BASE}/users/{username}/repos",
                headers=headers,
                params={"per_page": 100, "page": page, "type": "owner"},
            )

            if resp.status_code != 200:
                break

            repos = resp.json()
            if not repos:
                break

            all_repos.extend(repos)
            page += 1

            # Safety limit
            if page > 10:
                break

    return all_repos


def calculate_account_age_years(created_at: str) -> float:
    """Calculate account age in years from ISO date string."""
    try:
        created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        now = datetime.now(created.tzinfo)
        delta = now - created
        return delta.days / 365.25
    except (ValueError, AttributeError):
        return 0


def get_achievement_tier(metric_name: str, value: float) -> dict:
    """Get the highest tier achieved for a given metric."""
    achievement_def = GITHUB_ACHIEVEMENTS.get(metric_name)
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


async def sync_github_achievements(
    user: User,
    provider_account: ProviderAccount,
    db: Session,
) -> dict:
    """
    Sync GitHub activity-based achievements.

    Returns summary of credited achievements.
    """
    from app.services.crypto_service import decrypt_token
    token = decrypt_token(provider_account.access_token)
    if not token:
        raise Exception("No GitHub access token available")

    logger.info(f"[GITHUB] Starting achievement sync for user {user.id}")

    # Initialize profile_data if needed
    if not provider_account.profile_data:
        provider_account.profile_data = {}

    # Fetch user info
    user_info = await get_github_user(token)

    github_id = str(user_info.get("id"))
    username = user_info.get("login")
    name = user_info.get("name") or username
    avatar_url = user_info.get("avatar_url")
    bio = user_info.get("bio")
    public_repos = user_info.get("public_repos", 0)
    public_gists = user_info.get("public_gists", 0)
    followers = user_info.get("followers", 0)
    following = user_info.get("following", 0)
    created_at = user_info.get("created_at")

    # Calculate account age
    account_age_years = calculate_account_age_years(created_at)

    # Fetch repos to calculate total stars
    repos = await get_github_repos(token, username)
    total_stars = sum(r.get("stargazers_count", 0) for r in repos)

    logger.info(f"[GITHUB] Profile: {username} ({name})")
    logger.info(f"[GITHUB] Stats: Repos={public_repos}, Stars={total_stars}, Followers={followers}, Gists={public_gists}, Age={account_age_years:.1f}yr")

    # Update profile data
    provider_account.profile_data.update({
        "username": username,
        "name": name,
        "avatar_url": avatar_url,
        "bio": bio,
        "public_repos": public_repos,
        "public_gists": public_gists,
        "followers": followers,
        "following": following,
        "total_stars": total_stars,
        "account_age_years": round(account_age_years, 1),
        "created_at": created_at,
    })
    flag_modified(provider_account, "profile_data")

    # Calculate achievements based on metrics
    metrics = {
        "tenure": account_age_years,
        "repos": public_repos,
        "stars": total_stars,
        "followers": followers,
        "gists": public_gists,
    }

    achievements = []
    for metric_name, value in metrics.items():
        tier_info = get_achievement_tier(metric_name, value)
        if tier_info:
            achievements.append(tier_info)
            logger.info(f"[GITHUB] Achievement: {tier_info['display_name']} (value={value})")

    logger.info(f"[GITHUB] Found {len(achievements)} achievements based on activity")

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

        logger.info(f"[GITHUB] {display_name} → effort={effort_score} → {rarity_tier}")

        # Track rarity
        if rarity_tier in rarity_counts:
            rarity_counts[rarity_tier] += 1

        # Upsert achievement (use "github" as app_id)
        db_ach = (
            db.query(Achievement)
            .filter_by(app_id="github", api_name=identifier)
            .first()
        )

        if not db_ach:
            db_ach = Achievement(
                app_id="github",
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
                provider_name="github",
                provider_user_id=github_id,
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
                    provider_name="github",
                    provider_user_id=github_id,
                    is_original_claim=False,
                    unlocked_at=datetime.utcnow(),
                )
                db.add(credit)
                db.commit()
                logger.info(f"[GITHUB] Achievement '{display_name}' credited (display-only)")
        elif not existing_global:
            # First claim globally
            credit = AchievementCredit(
                user_id=user.id,
                provider_account_id=provider_account.id,
                achievement_id=db_ach.id,
                provider_name="github",
                provider_user_id=github_id,
                is_original_claim=True,
                unlocked_at=datetime.utcnow(),
            )
            db.add(credit)
            db.commit()
            total_credited += 1
            logger.info(f"[GITHUB] Achievement '{display_name}' credited (original claim)")
        else:
            # Already credited to this user
            logger.debug(f"[GITHUB] Achievement '{display_name}' already credited")

    # Update last sync time
    provider_account.last_sync_at = datetime.utcnow()
    db.commit()

    return {
        "credited": total_credited,
        "details": {
            "total_achievements": total_found,
            "by_rarity": rarity_counts,
        }
    }
