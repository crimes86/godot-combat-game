"""
Weapon Stats Routes - Sync forged weapon combat biographies.

These endpoints allow Godot clients to:
1. Fetch weapon stats for a forged item
2. Sync updated stats (increment-only validation)
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session as DbSession
from pydantic import BaseModel
from typing import Optional, Dict, Any, Callable
from datetime import datetime
import logging

from app.models import User, ForgedAchievement, WeaponStats
from app.database import SessionLocal
from app.services import weapon_stats_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/weapon-stats", tags=["weapon-stats"])

# Will be set by init_weapon_stats_routes()
_get_current_user_func: Callable = None


def get_db():
    """Database session dependency."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user_dep(request: Request, db: DbSession = Depends(get_db)):
    """Get current user - wraps the main app's auth logic."""
    if _get_current_user_func is None:
        raise HTTPException(status_code=500, detail="Weapon stats routes not initialized")
    return _get_current_user_func(request, db)


def init_weapon_stats_routes(get_current_user: Callable):
    """Initialize weapon stats routes with dependencies from main app."""
    global _get_current_user_func
    _get_current_user_func = get_current_user
    logger.info("Weapon stats routes initialized")


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class WeaponStatsUpdate(BaseModel):
    """Stats update from Godot client - all fields optional."""
    # Kill stats
    kills_total: Optional[int] = None
    kills_by_type: Optional[Dict[str, int]] = None
    kills_elite: Optional[int] = None
    kills_boss: Optional[int] = None
    kills_pvp: Optional[int] = None

    # Damage stats
    damage_total: Optional[int] = None
    damage_max_hit: Optional[int] = None
    damage_overkill: Optional[int] = None

    # Crit stats
    crits_landed: Optional[int] = None
    hits_total: Optional[int] = None
    weakpoints_destroyed: Optional[int] = None
    chain_max_reached: Optional[int] = None

    # Usage stats
    swings_total: Optional[int] = None
    shots_fired: Optional[int] = None
    bursts_fired: Optional[int] = None
    time_equipped_seconds: Optional[int] = None
    sessions_equipped: Optional[int] = None

    # Negative stats
    deaths_equipped: Optional[int] = None
    misses_total: Optional[int] = None
    battles_lost: Optional[int] = None
    show_negative_stats: Optional[bool] = None

    # Milestones (ISO datetime strings)
    first_equipped_at: Optional[str] = None
    first_kill_at: Optional[str] = None
    first_crit_at: Optional[str] = None
    milestone_100_kills_at: Optional[str] = None
    milestone_1000_kills_at: Optional[str] = None
    milestone_10000_kills_at: Optional[str] = None

    # Level
    level: Optional[int] = None
    experience: Optional[int] = None

    # Achievements
    achievements: Optional[list] = None


class WeaponStatsResponse(BaseModel):
    """Full weapon stats response."""
    forged_achievement_id: int
    # Kill stats
    kills_total: int
    kills_by_type: Dict[str, int]
    kills_elite: int
    kills_boss: int
    kills_pvp: int
    # Damage stats
    damage_total: int
    damage_max_hit: int
    damage_overkill: int
    # Crit stats
    crits_landed: int
    hits_total: int
    weakpoints_destroyed: int
    chain_max_reached: int
    # Usage stats
    swings_total: int
    shots_fired: int
    bursts_fired: int
    time_equipped_seconds: int
    sessions_equipped: int
    # Negative stats
    deaths_equipped: int
    misses_total: int
    battles_lost: int
    show_negative_stats: bool
    # Milestones
    first_equipped_at: Optional[str]
    first_kill_at: Optional[str]
    first_crit_at: Optional[str]
    milestone_100_kills_at: Optional[str]
    milestone_1000_kills_at: Optional[str]
    milestone_10000_kills_at: Optional[str]
    # Level
    level: int
    experience: int
    # Achievements
    achievements: list
    # Computed
    is_virgin: bool
    visual_tier: str
    crit_rate_lifetime: float


# =============================================================================
# ENDPOINTS
# =============================================================================

@router.get("/{item_id}", response_model=WeaponStatsResponse)
async def get_weapon_stats(
    item_id: str,
    request: Request,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get weapon stats for a forged item.

    Returns the full combat biography including kills, damage, crits,
    usage stats, achievements, and level.
    """
    # Find the forged item
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.item_id == item_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Forged item not found")

    # Verify ownership (current owner or wallet owner)
    is_owner = (
        forged.current_owner_id == current_user.id or
        (forged.wallet_account and forged.wallet_account.user_id == current_user.id)
    )

    if not is_owner:
        raise HTTPException(status_code=403, detail="Not authorized to view this weapon's stats")

    # Get or create stats
    stats = weapon_stats_service.get_weapon_stats(db, forged.id)
    return weapon_stats_service.stats_to_dict(stats)


@router.put("/{item_id}", response_model=WeaponStatsResponse)
async def update_weapon_stats(
    item_id: str,
    stats_update: WeaponStatsUpdate,
    request: Request,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Sync weapon stats from Godot client.

    Only allows incrementing stats (no decrements) to prevent cheating.
    Milestones can only be set once.
    """
    # Find the forged item
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.item_id == item_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Forged item not found")

    # Verify ownership
    is_owner = (
        forged.current_owner_id == current_user.id or
        (forged.wallet_account and forged.wallet_account.user_id == current_user.id)
    )

    if not is_owner:
        raise HTTPException(status_code=403, detail="Not authorized to update this weapon's stats")

    # Get client IP for audit
    client_ip = request.client.host if request.client else None

    # Convert pydantic model to dict, excluding None values
    stats_data = stats_update.model_dump(exclude_none=True)

    # Update stats (service handles increment-only validation)
    updated_stats = weapon_stats_service.update_weapon_stats(
        db, forged.id, stats_data, client_ip
    )

    if not updated_stats:
        raise HTTPException(status_code=500, detail="Failed to update weapon stats")

    logger.info(f"Weapon stats synced: item_id={item_id}, user_id={current_user.id}, kills={updated_stats.kills_total}")

    return weapon_stats_service.stats_to_dict(updated_stats)


@router.get("/{item_id}/summary")
async def get_weapon_stats_summary(
    item_id: str,
    request: Request,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get a quick summary of weapon stats for tooltips.

    Returns minimal data for UI display without full stats.
    """
    # Find the forged item
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.item_id == item_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Forged item not found")

    # Get stats (creates if not exists)
    stats = weapon_stats_service.get_weapon_stats(db, forged.id)

    return {
        "item_id": item_id,
        "level": stats.level,
        "kills_total": stats.kills_total,
        "is_virgin": weapon_stats_service.is_virgin(stats),
        "visual_tier": weapon_stats_service.get_visual_tier(stats),
        "crit_rate": weapon_stats_service.get_crit_rate(stats),
        "damage_bonus": weapon_stats_service.get_damage_bonus(stats),
        "crit_bonus": weapon_stats_service.get_crit_bonus(stats),
        "achievement_count": len(stats.achievements or [])
    }
