"""
Community Contribution API Routes

Endpoints for submitting and voting on cross-platform achievement mappings
and rarity disputes, with rewards for approved contributions.
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List

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

    session = db.query(SessionModel).filter(SessionModel.token == token).first()
    if not session:
        raise HTTPException(status_code=401, detail="Invalid session")

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
    contribution_type: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    """Get pending contributions available for voting."""
    # Run expiration check
    expire_old_contributions(db)

    contributions = get_pending_contributions(
        db=db,
        contribution_type=contribution_type,
        limit=min(limit, 100),
        offset=offset,
    )
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
    right_provider: str
    right_app_id: str
    right_achievement_id: int
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
    from app.models import Achievement

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
        steam_api_name = left_ach.api_name
        steam_app_id = left_ach.app_id
        target_platform = request.right_provider
        target_api_name = right_ach.api_name
        game_key = f"game_{steam_app_id}"
        achievement_name = left_ach.name or left_ach.api_name
    elif request.right_provider == "steam":
        steam_api_name = right_ach.api_name
        steam_app_id = right_ach.app_id
        target_platform = request.left_provider
        target_api_name = left_ach.api_name
        game_key = f"game_{steam_app_id}"
        achievement_name = right_ach.name or right_ach.api_name
    else:
        # Neither is Steam - use left as canonical
        steam_api_name = left_ach.api_name
        steam_app_id = left_ach.app_id
        target_platform = request.right_provider
        target_api_name = right_ach.api_name
        game_key = f"game_{left_ach.app_id}_{right_ach.app_id}"
        achievement_name = left_ach.name or left_ach.api_name

    # Create the contribution using existing service
    try:
        contribution, chat_message = submit_platform_mapping(
            db=db,
            user_id=current_user_id,
            game_key=game_key,
            steam_api_name=steam_api_name,
            target_platform=target_platform,
            target_api_name=target_api_name,
            game_name=f"Game {steam_app_id}",
            achievement_name=achievement_name,
            reason=request.reason,
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
    current_user_id: int = Depends(get_current_user_id),
    db: Session = Depends(get_db),
):
    """
    Get unmapped achievements for a specific game/platform combo.

    Shows:
    - Canonical (Steam) achievements that need mapping to target platform
    - Target platform achievements (if available in DB) for matching
    - User's unlock status on both sides
    """
    result = get_unmapped_achievements_for_game(
        db=db,
        user_id=current_user_id,
        game_key=game_key,
        target_platform=target_platform,
    )

    if "error" in result:
        raise HTTPException(status_code=404, detail=result["error"])

    return result
