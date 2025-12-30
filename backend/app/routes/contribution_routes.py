"""
Community Contribution API Routes

Endpoints for submitting and voting on cross-platform achievement mappings
and rarity disputes, with rewards for approved contributions.
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List
import logging

logger = logging.getLogger(__name__)

from app.database import SessionLocal
from app.services.contribution_service import (
    submit_platform_mapping,
    submit_rarity_dispute,
    vote_on_contribution,
    claim_reward,
    get_pending_contributions,
    get_contribution,
    get_contributor_profile,
    get_leaderboard,
    get_user_contributions,
    expire_old_contributions,
    REWARD_TIERS,
    calculate_description_similarity,
)

router = APIRouter(prefix="/api/contributions", tags=["contributions"])


def get_db():
    """Database session dependency."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# Request models
class PlatformMappingRequest(BaseModel):
    game_key: str
    steam_api_name: str
    target_platform: str
    target_api_name: str
    game_name: str
    achievement_name: str
    reason: str


class RarityDisputeRequest(BaseModel):
    achievement_id: int
    suggested_rarity: str
    reason: str


class VoteRequest(BaseModel):
    vote: int  # 1 = agree, -1 = disagree


class ClaimRewardRequest(BaseModel):
    reward_id: str


async def get_current_user_id(request: Request, db: Session = Depends(get_db)) -> int:
    """Get current user ID from session."""
    from app.models import Session as SessionModel, User

    # Check for Bearer token
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
    else:
        # Check for session cookie
        token = request.cookies.get("session_id")

    if not token:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Hash token to compare against stored hash
    token_hash = SessionModel.hash_token(token)
    session = db.query(SessionModel).filter(SessionModel.token_hash == token_hash).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")

    return session.user_id


async def get_optional_user_id(request: Request, db: Session = Depends(get_db)) -> Optional[int]:
    """Get current user ID from session, or None if not authenticated."""
    from app.models import Session as SessionModel

    # Check for Bearer token
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[7:]
    else:
        # Check for session cookie
        token = request.cookies.get("session_id")

    if not token:
        return None

    # Hash token to compare against stored hash
    token_hash = SessionModel.hash_token(token)
    session = db.query(SessionModel).filter(SessionModel.token_hash == token_hash).first()
    if not session:
        return None

    return session.user_id


@router.post("/mapping")
async def submit_mapping(
    request: PlatformMappingRequest,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Submit a cross-platform achievement mapping.

    Expert-gating: Must have achievements from Steam or target platform.
    Curators can submit any mapping.
    """
    try:
        contribution, chat_message = submit_platform_mapping(
            db=db,
            user_id=current_user_id,
            game_key=request.game_key,
            steam_api_name=request.steam_api_name,
            target_platform=request.target_platform,
            target_api_name=request.target_api_name,
            game_name=request.game_name,
            achievement_name=request.achievement_name,
            reason=request.reason,
        )
        return {
            "success": True,
            "contribution_id": contribution.id,
            "status": contribution.status,
            "chat_message_id": chat_message.id if chat_message else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/dispute")
async def submit_dispute(
    request: RarityDisputeRequest,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Submit a rarity dispute for an achievement.

    Expert-gating: Must have the achievement.
    Curators can dispute any achievement.
    """
    try:
        contribution, chat_message = submit_rarity_dispute(
            db=db,
            user_id=current_user_id,
            achievement_id=request.achievement_id,
            suggested_rarity=request.suggested_rarity,
            reason=request.reason,
        )
        return {
            "success": True,
            "contribution_id": contribution.id,
            "status": contribution.status,
            "chat_message_id": chat_message.id if chat_message else None,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/pending")
async def list_pending(
    request: Request,
    contribution_type: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    """Get pending contributions available for voting."""
    from app.models import ContributionVote

    # Run expiration check
    expire_old_contributions(db)

    # Get current user if logged in
    current_user_id = None
    try:
        current_user_id = await get_current_user_id(request, db)
    except:
        pass

    contributions = get_pending_contributions(
        db=db,
        contribution_type=contribution_type,
        limit=min(limit, 100),
        offset=offset,
    )

    # Add user-specific info to each contribution
    if current_user_id:
        for c in contributions:
            c["is_own"] = c.get("user_id") == current_user_id
            # Check if user has already voted
            vote = db.query(ContributionVote).filter(
                ContributionVote.contribution_id == c["id"],
                ContributionVote.user_id == current_user_id
            ).first()
            c["user_vote"] = vote.vote if vote else None
    else:
        for c in contributions:
            c["is_own"] = False
            c["user_vote"] = None

    return {
        "contributions": contributions,
        "count": len(contributions),
    }


@router.get("/contribution/{contribution_id}")
async def get_single_contribution(
    contribution_id: int,
    db: Session = Depends(get_db),
):
    """Get a single contribution by ID."""
    contribution = get_contribution(db, contribution_id)
    if not contribution:
        raise HTTPException(status_code=404, detail="Contribution not found")
    return contribution


@router.post("/{contribution_id}/vote")
async def vote(
    contribution_id: int,
    request: VoteRequest,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Vote on a contribution.

    Expert-gating applies:
    - Platform mappings: Must have achievements from Steam or target platform
    - Rarity disputes: Must have the achievement
    - Curators: Can vote on anything with 3x weight
    """
    if request.vote not in [1, -1]:
        raise HTTPException(status_code=400, detail="Vote must be 1 (agree) or -1 (disagree)")

    try:
        vote_record, was_approved = vote_on_contribution(
            db=db,
            user_id=current_user_id,
            contribution_id=contribution_id,
            vote=request.vote,
        )
        return {
            "success": True,
            "vote_id": vote_record.id,
            "weight": vote_record.weight,
            "was_approved": was_approved,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/rewards/claim")
async def claim_reward_endpoint(
    request: ClaimRewardRequest,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Claim an earned reward (title, badge, cape, aura)."""
    try:
        result = claim_reward(db, current_user_id, request.reward_id)
        return {
            "success": True,
            "claimed": result,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/profile")
async def get_profile(
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Get current user's contributor profile and stats."""
    return get_contributor_profile(db, current_user_id)


@router.get("/profile/{user_id}")
async def get_user_profile(
    user_id: int,
    db: Session = Depends(get_db),
):
    """Get a user's public contributor profile."""
    profile = get_contributor_profile(db, user_id)
    # Remove private fields for public view
    public_profile = {
        "user_id": profile["user_id"],
        "username": profile["username"],
        "total_approved": profile["total_approved"],
        "mappings_approved": profile["mappings_approved"],
        "disputes_approved": profile["disputes_approved"],
        "contributor_role": profile["contributor_role"],
        "leaderboard_rank": profile["leaderboard_rank"],
        "active_title": profile["active_title"],
        "active_badges": profile["active_badges"],
    }
    return public_profile


@router.get("/leaderboard")
async def leaderboard(
    limit: int = 25,
    db: Session = Depends(get_db),
):
    """Get top contributors leaderboard."""
    leaders = get_leaderboard(db, min(limit, 100))
    return {
        "leaderboard": leaders,
        "count": len(leaders),
    }


@router.get("/my-contributions")
async def my_contributions(
    status: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Get current user's submitted contributions."""
    contributions = get_user_contributions(
        db=db,
        user_id=current_user_id,
        status=status,
        limit=min(limit, 100),
        offset=offset,
    )
    return {
        "contributions": contributions,
        "count": len(contributions),
    }


@router.get("/my-approvals")
async def my_recent_approvals(
    since_minutes: int = 60,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """Get user's recently approved contributions for notifications."""
    from datetime import datetime, timedelta
    from app.models import CommunityContribution

    cutoff = datetime.utcnow() - timedelta(minutes=since_minutes)

    recent = db.query(CommunityContribution).filter(
        CommunityContribution.user_id == current_user_id,
        CommunityContribution.status == "approved",
        CommunityContribution.resolved_at >= cutoff,
    ).order_by(CommunityContribution.resolved_at.desc()).all()

    return {
        "approvals": [
            {
                "id": c.id,
                "type": c.contribution_type,
                "game_name": c.data.get("game_name", "Unknown") if c.data else "Unknown",
                "achievement_name": c.data.get("achievement_name", "Unknown") if c.data else "Unknown",
                "resolved_at": c.resolved_at.isoformat() if c.resolved_at else None,
            }
            for c in recent
        ],
        "count": len(recent),
    }


@router.get("/rewards")
async def list_rewards():
    """Get available reward tiers and their requirements."""
    rewards = []
    for tier_id, tier_info in REWARD_TIERS.items():
        rewards.append({
            "id": tier_id,
            "threshold": tier_info["threshold"],
            "title": tier_info["title"],
            "title_color": tier_info["title_color"],
            "badge": tier_info["badge"],
            "cape": tier_info["cape"],
            "aura": tier_info["aura"],
            "role": tier_info["role"],
        })
    return {
        "rewards": sorted(rewards, key=lambda x: x["threshold"]),
    }


# =============================================================================
# Visual Mapping Tool Endpoints
# =============================================================================

from app.services.mapping_tool_service import (
    get_user_games_by_provider,
    get_achievements_for_game,
    validate_mapping_submission,
    get_provider_color,
    get_provider_display_name,
    get_user_mapping_opportunities,
    get_unmapped_achievements_for_game,
    get_crossplatform_games_needing_mappings,
)


@router.get("/mapping-tool/my-games")
async def get_my_games(
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get all games the current user has achievements for, grouped by provider.

    Used by the visual mapping tool to populate the game selectors.
    """
    games = get_user_games_by_provider(db, current_user_id)

    # Add provider metadata
    providers = {}
    for provider_name in games.keys():
        providers[provider_name] = {
            "display_name": get_provider_display_name(provider_name),
            "color": get_provider_color(provider_name),
            "games": games[provider_name],
        }

    return {
        "providers": providers,
        "total_providers": len(providers),
    }


@router.get("/mapping-tool/achievements")
async def get_game_achievements(
    provider: str,
    app_id: str,
    search: Optional[str] = None,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get all achievements for a specific game/provider.

    Returns achievements with user's unlock status.
    Used by the visual mapping tool to show side-by-side achievements.
    """
    achievements = get_achievements_for_game(
        db=db,
        user_id=current_user_id,
        provider=provider,
        app_id=app_id,
        search=search,
    )

    return {
        "provider": provider,
        "app_id": app_id,
        "achievements": achievements,
        "count": len(achievements),
        "unlocked_count": sum(1 for a in achievements if a["unlocked"]),
    }


class VisualMappingRequest(BaseModel):
    """Request for submitting a visual mapping from the tool."""
    left_provider: str
    left_app_id: str
    left_achievement_id: int
    left_api_name: Optional[str] = None  # For discovered games with fake IDs
    right_provider: str
    right_app_id: str
    right_achievement_id: int
    right_api_name: Optional[str] = None  # For discovered games with fake IDs
    reason: str


@router.post("/mapping-tool/submit")
async def submit_visual_mapping(
    request: VisualMappingRequest,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Submit a mapping from the visual mapping tool.

    Validates the mapping and creates a contribution for community voting.
    """
    from app.models import Achievement, Game

    # Validate the mapping
    validation = validate_mapping_submission(
        db=db,
        user_id=current_user_id,
        left_achievement_id=request.left_achievement_id,
        right_achievement_id=request.right_achievement_id,
    )

    if not validation["valid"]:
        raise HTTPException(status_code=400, detail=validation["error"])

    # Get achievement details
    left_ach = db.query(Achievement).filter(Achievement.id == request.left_achievement_id).first()
    right_ach = db.query(Achievement).filter(Achievement.id == request.right_achievement_id).first()

    if not left_ach or not right_ach:
        raise HTTPException(status_code=404, detail="Achievement not found")

    # Determine which is canonical (Steam preferred)
    if request.left_provider == "steam":
        source_platform = "steam"
        steam_api_name = left_ach.api_name
        steam_app_id = left_ach.app_id
        target_platform = request.right_provider
        target_api_name = right_ach.api_name
        game_key = f"game_{steam_app_id}"
        achievement_name = left_ach.name or left_ach.api_name
        target_achievement_name = right_ach.name or right_ach.api_name
        source_icon = left_ach.icon_url
        target_icon = right_ach.icon_url
        source_description = left_ach.description
        target_description = right_ach.description
        source_ach_id = left_ach.id
        target_ach_id = right_ach.id
    elif request.right_provider == "steam":
        source_platform = "steam"
        steam_api_name = right_ach.api_name
        steam_app_id = right_ach.app_id
        target_platform = request.left_provider
        target_api_name = left_ach.api_name
        game_key = f"game_{steam_app_id}"
        achievement_name = right_ach.name or right_ach.api_name
        target_achievement_name = left_ach.name or left_ach.api_name
        source_icon = right_ach.icon_url
        target_icon = left_ach.icon_url
        source_description = right_ach.description
        target_description = left_ach.description
        source_ach_id = right_ach.id
        target_ach_id = left_ach.id
    else:
        # Neither is Steam - use left as canonical
        source_platform = request.left_provider
        steam_api_name = left_ach.api_name
        steam_app_id = left_ach.app_id
        target_platform = request.right_provider
        target_api_name = right_ach.api_name
        game_key = f"game_{left_ach.app_id}_{right_ach.app_id}"
        achievement_name = left_ach.name or left_ach.api_name
        target_achievement_name = right_ach.name or right_ach.api_name
        source_icon = left_ach.icon_url
        target_icon = right_ach.icon_url
        source_description = left_ach.description
        target_description = right_ach.description
        source_ach_id = left_ach.id
        target_ach_id = right_ach.id

    # Look up game name from Game table, fallback to platform_mappings.json
    game = db.query(Game).filter(Game.app_id == str(steam_app_id)).first()
    game_name = None
    if game:
        game_name = game.name
    else:
        # Fallback: check platform_mappings.json
        import json
        import os
        mappings_path = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'platform_mappings.json')
        try:
            with open(mappings_path, 'r') as f:
                mappings = json.load(f)
            for gkey, gdata in mappings.get('games', {}).items():
                if gkey.startswith('_') or not isinstance(gdata, dict):
                    continue
                # Check canonical app_id
                canonical = gdata.get('canonical', {})
                if str(canonical.get('app_id', '')) == str(steam_app_id):
                    game_name = gdata.get('_display_name', gkey.replace('_', ' ').title())
                    break
                # Check platforms
                for plat, plat_data in gdata.get('platforms', {}).items():
                    if isinstance(plat_data, dict) and str(plat_data.get('app_id', '')) == str(steam_app_id):
                        game_name = gdata.get('_display_name', gkey.replace('_', ' ').title())
                        break
                if game_name:
                    break
        except Exception:
            pass
    if not game_name:
        game_name = f"Game {steam_app_id}"

    # Create the contribution using existing service
    try:
        contribution, chat_message = submit_platform_mapping(
            db=db,
            user_id=current_user_id,
            game_key=game_key,
            steam_api_name=steam_api_name,
            target_platform=target_platform,
            target_api_name=target_api_name,
            game_name=game_name,
            achievement_name=achievement_name,
            reason=request.reason,
            target_achievement_name=target_achievement_name,
            source_platform=source_platform,
            source_icon=source_icon,
            target_icon=target_icon,
            steam_app_id=steam_app_id,
            source_description=source_description,
            target_description=target_description,
            source_ach_id=source_ach_id,
            target_ach_id=target_ach_id,
        )
        return {
            "success": True,
            "contribution_id": contribution.id,
            "status": contribution.status,
            "message": "Mapping submitted for community review!",
            "left": {
                "provider": request.left_provider,
                "name": left_ach.name,
            },
            "right": {
                "provider": request.right_provider,
                "name": right_ach.name,
            },
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/mapping-tool/validate")
async def validate_mapping(
    left_achievement_id: int,
    right_achievement_id: int,
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Pre-validate a mapping before submission.

    Returns whether the mapping is valid and any issues.
    """
    validation = validate_mapping_submission(
        db=db,
        user_id=current_user_id,
        left_achievement_id=left_achievement_id,
        right_achievement_id=right_achievement_id,
    )
    return validation


@router.get("/mapping-tool/opportunities")
async def get_opportunities(
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get mapping opportunities for the current user.

    Returns games where:
    1. User has achievements (qualifies them to contribute)
    2. Game has unmapped cross-platform achievements
    3. Sorted by user's qualification (more achievements = higher priority)
    """
    opportunities = get_user_mapping_opportunities(db, current_user_id)
    return {
        "opportunities": opportunities,
        "count": len(opportunities),
    }


@router.get("/mapping-tool/games-needing-work")
async def get_games_needing_work():
    """
    Get all cross-platform games that have unmapped achievements.

    Public endpoint - shows where community help is needed.
    """
    games = get_crossplatform_games_needing_mappings()
    return {
        "games": games,
        "count": len(games),
        "total_unmapped": sum(g['total_unmapped'] for g in games),
    }


@router.get("/mapping-tool/game/{game_key}/unmapped")
async def get_game_unmapped(
    game_key: str,
    target_platform: str,
    current_user_id: Optional[int] = Depends(get_optional_user_id),
    db: Session = Depends(get_db),
):
    """
    Get unmapped achievements for a specific game/platform combo.

    Shows:
    - Canonical (Steam) achievements that need mapping to target platform
    - Target platform achievements (if available in DB) for matching
    - User's unlock status on both sides (if authenticated)
    """
    result = get_unmapped_achievements_for_game(
        db=db,
        user_id=current_user_id or 0,  # Use 0 for unauthenticated users
        game_key=game_key,
        target_platform=target_platform,
    )

    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])

    # Get source platform info
    source_platform = result.get("source_platform", result.get("canonical_platform", "steam"))
    canonical_app_id = result.get("canonical_app_id")
    unmapped = result.get("unmapped_achievements", [])
    canonical = result.get("canonical_achievements", [])

    # If no achievements in DB but source is Steam, fetch from Steam API
    if not unmapped and source_platform == "steam" and canonical_app_id:
        try:
            from app.services.steam_api import get_steam_achievement_schema
            schema = await get_steam_achievement_schema(canonical_app_id)

            if schema:
                # Create achievement entries from Steam schema
                # All are "unmapped" since we don't have DB records
                fake_id = -1
                for api_name, ach_data in schema.items():
                    unmapped.append({
                        "id": fake_id,
                        "api_name": api_name,
                        "name": ach_data.get("display_name", api_name),
                        "description": ach_data.get("description", ""),
                        "icon_url": ach_data.get("icon_url", ""),
                        "rarity_tier": "Common",
                        "unlocked": False,
                        "from_api": True,  # Flag that this came from API, not DB
                    })
                    fake_id -= 1

                result["unmapped_achievements"] = unmapped
                result["canonical_achievements"] = unmapped
                logger.info(f"Fetched {len(unmapped)} achievements from Steam API for {game_key}")

        except Exception as e:
            logger.warning(f"Failed to fetch Steam achievements from API: {e}")

    # Check if achievements are missing icons - if so, fetch from Steam API
    elif unmapped or canonical:
        needs_icons = any(not ach.get("icon_url") for ach in canonical + unmapped)

        if needs_icons and canonical_app_id and source_platform == "steam":
            try:
                from app.services.steam_api import get_steam_achievement_schema
                schema = await get_steam_achievement_schema(canonical_app_id)

                if schema:
                    # Merge icon URLs into canonical achievements
                    for ach in canonical:
                        api_name = ach.get("api_name", "")
                        if api_name in schema and not ach.get("icon_url"):
                            ach["icon_url"] = schema[api_name].get("icon_url", "")
                            if not ach.get("name") or ach["name"] == api_name:
                                ach["name"] = schema[api_name].get("display_name", api_name)
                            if not ach.get("description"):
                                ach["description"] = schema[api_name].get("description", "")

                    # Also update unmapped_achievements list
                    for ach in unmapped:
                        api_name = ach.get("api_name", "")
                        if api_name in schema and not ach.get("icon_url"):
                            ach["icon_url"] = schema[api_name].get("icon_url", "")
                            if not ach.get("name") or ach["name"] == api_name:
                                ach["name"] = schema[api_name].get("display_name", api_name)
                            if not ach.get("description"):
                                ach["description"] = schema[api_name].get("description", "")

            except Exception as e:
                logger.warning(f"Failed to fetch Steam schema for icons: {e}")

    # Calculate suggested matches based on name + description similarity
    # Limit to avoid slow O(n*m) for games with 700+ achievements
    MAX_ACHIEVEMENTS_TO_COMPARE = 150
    MAX_SUGGESTED_MATCHES = 50

    target_achs = result.get("target_achievements", [])
    unmapped_achs = result.get("unmapped_achievements", [])

    if target_achs and unmapped_achs:
        suggested_matches = []
        used_target_ids = set()  # Prevent same target being suggested multiple times

        # Sort unmapped so user's unlocked achievements come first, then limit
        sorted_unmapped = sorted(unmapped_achs, key=lambda x: (0 if x.get("unlocked") else 1, x.get("name", "").lower()))
        limited_unmapped = sorted_unmapped[:MAX_ACHIEVEMENTS_TO_COMPARE]
        limited_targets = target_achs[:MAX_ACHIEVEMENTS_TO_COMPARE]

        # Build lookup for fast name matching
        target_by_name = {}
        for t in limited_targets:
            name_key = (t.get("name") or "").lower().strip()
            if name_key and name_key not in target_by_name:
                target_by_name[name_key] = t

        # PASS 1: Exact name matches first (prevents "Just a Taste" matching wrong target)
        remaining_sources = []
        for source_ach in limited_unmapped:
            if len(suggested_matches) >= MAX_SUGGESTED_MATCHES:
                remaining_sources.append(source_ach)
                continue

            source_name = (source_ach.get("name") or "").lower().strip()
            exact_match = target_by_name.get(source_name)

            if exact_match and exact_match.get("id") not in used_target_ids:
                used_target_ids.add(exact_match.get("id"))
                source_desc = (source_ach.get("description") or "").lower().strip()
                target_desc = (exact_match.get("description") or "").lower().strip()
                desc_sim = calculate_description_similarity(source_desc, target_desc) if source_desc and target_desc else 1.0

                suggested_matches.append({
                    "source": source_ach,
                    "target": exact_match,
                    "confidence": round((1.0 * 0.4 + desc_sim * 0.6) * 100, 1) if source_desc and target_desc else 100.0,
                    "source_unlocked": source_ach.get("unlocked", False),
                    "target_unlocked": exact_match.get("unlocked", False),
                    "either_unlocked": source_ach.get("unlocked", False) or exact_match.get("unlocked", False),
                    "name_match": 100.0,
                    "desc_match": round(desc_sim * 100, 1) if source_desc and target_desc else 100.0,
                })
            else:
                remaining_sources.append(source_ach)

        # PASS 2: Fuzzy matching for remaining achievements
        for source_ach in remaining_sources:
            if len(suggested_matches) >= MAX_SUGGESTED_MATCHES:
                break
            best_match = None
            best_score = 0

            source_name = (source_ach.get("name") or "").lower().strip()
            source_desc = (source_ach.get("description") or "").lower().strip()

            for target_ach in limited_targets:
                target_id = target_ach.get("id")
                if target_id in used_target_ids:
                    continue

                target_name = (target_ach.get("name") or "").lower().strip()
                target_desc = (target_ach.get("description") or "").lower().strip()

                # Calculate combined similarity (weighted: 40% name, 60% description)
                name_sim = calculate_description_similarity(source_name, target_name)
                desc_sim = calculate_description_similarity(source_desc, target_desc)

                # If descriptions are empty, rely more on name
                if not source_desc or not target_desc:
                    combined_score = name_sim
                else:
                    combined_score = (name_sim * 0.4) + (desc_sim * 0.6)

                if combined_score > best_score:
                    best_score = combined_score
                    best_match = target_ach

            # Only suggest matches above 70% confidence
            if best_match and best_score >= 0.70:
                used_target_ids.add(best_match.get("id"))
                src_unlocked = source_ach.get("unlocked", False)
                tgt_unlocked = best_match.get("unlocked", False)
                suggested_matches.append({
                    "source": source_ach,
                    "target": best_match,
                    "confidence": round(best_score * 100, 1),
                    "source_unlocked": src_unlocked,
                    "target_unlocked": tgt_unlocked,
                    "either_unlocked": src_unlocked or tgt_unlocked,
                    "name_match": round(calculate_description_similarity(
                        (source_ach.get("name") or "").lower(),
                        (best_match.get("name") or "").lower()
                    ) * 100, 1),
                    "desc_match": round(calculate_description_similarity(
                        (source_ach.get("description") or "").lower(),
                        (best_match.get("description") or "").lower()
                    ) * 100, 1),
                })

        # Sort by: either unlocked first, then by confidence (highest first)
        suggested_matches.sort(key=lambda x: (
            0 if x.get("either_unlocked") else 1,  # Either side unlocked = top
            -x["confidence"]  # Then by confidence descending
        ))
        result["suggested_matches"] = suggested_matches
        result["match_stats"] = {
            "total_unmapped": len(unmapped_achs),
            "total_target": len(target_achs),
            "suggested_count": len(suggested_matches),
            "high_confidence": len([m for m in suggested_matches if m["confidence"] >= 90]),
            "medium_confidence": len([m for m in suggested_matches if 80 <= m["confidence"] < 90]),
            "low_confidence": len([m for m in suggested_matches if m["confidence"] < 80]),
        }
    else:
        result["suggested_matches"] = []
        result["match_stats"] = {
            "total_unmapped": len(unmapped_achs),
            "total_target": len(target_achs),
            "suggested_count": 0,
            "high_confidence": 0,
            "medium_confidence": 0,
            "low_confidence": 0,
        }

    return result
