"""
Gameplay telemetry routes for kill/loot/combat event logging.

Provides audit trail for anti-cheat detection without blocking gameplay.
Events are logged asynchronously and analyzed for anomalies.

See docs/VENDOR_PURCHASE_SPEC.md for related security context.
"""
import logging
from datetime import datetime, timedelta
from typing import Callable, Optional, List

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import func, and_

from app.database import SessionLocal
from app.models import User, Character, GameEventLog
from app.routes.vendor_routes import get_active_character

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/telemetry", tags=["telemetry"])

# Will be set by init_telemetry_routes()
_get_current_user_func: Callable = None
_limiter = None

# Anti-cheat thresholds
MAX_KILLS_PER_MINUTE = 60  # More than 1 kill/second is suspicious
MAX_GOLD_PER_KILL = 10000  # Sanity check on gold drops
MAX_XP_PER_KILL = 50000    # Sanity check on XP grants
MAX_BATCH_SIZE = 50        # Limit batch submissions


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
        raise HTTPException(status_code=500, detail="Telemetry routes not initialized")
    return _get_current_user_func(request, db)


def init_telemetry_routes(get_current_user: Callable, limiter=None):
    """Initialize telemetry routes with dependencies from main app."""
    global _get_current_user_func, _limiter
    _get_current_user_func = get_current_user
    _limiter = limiter
    logger.info("Telemetry routes initialized")


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class KillEvent(BaseModel):
    """Kill event data."""
    enemy_type: str = Field(..., max_length=64)
    enemy_level: int = Field(ge=1, le=100)
    enemy_network_id: Optional[int] = None
    xp_granted: int = Field(ge=0, le=MAX_XP_PER_KILL)
    gold_dropped: int = Field(ge=0, le=MAX_GOLD_PER_KILL)
    weapon_used: Optional[str] = Field(None, max_length=64)
    was_critical: bool = False
    overkill_damage: int = Field(default=0, ge=0)


class LootEvent(BaseModel):
    """Loot pickup event data."""
    loot_type: str = Field(..., pattern="^(gold|item)$")
    source_type: str = Field(..., pattern="^(enemy_corpse|chest|tree|rock|ground)$")
    source_id: Optional[str] = Field(None, max_length=64)  # enemy_network_id or chest_id
    gold_amount: int = Field(default=0, ge=0, le=1000000)
    item_id: Optional[str] = Field(None, max_length=64)
    item_name: Optional[str] = Field(None, max_length=128)
    item_rarity: Optional[str] = Field(None, max_length=32)
    quantity: int = Field(default=1, ge=1, le=1000)


class ResourceEvent(BaseModel):
    """Resource gathering event."""
    resource_type: str = Field(..., pattern="^(wood|stone|ore|herb)$")
    source_type: str = Field(..., pattern="^(tree|rock|node|bush)$")
    amount: int = Field(ge=1, le=100)


class TelemetryEventRequest(BaseModel):
    """Single telemetry event submission."""
    event_type: str = Field(..., pattern="^(kill|loot|resource|damage)$")
    event_data: dict
    session_id: Optional[str] = Field(None, max_length=64)
    is_multiplayer: bool = False
    zone_id: Optional[str] = Field(None, max_length=32)
    position_x: Optional[float] = None
    position_y: Optional[float] = None
    client_timestamp: Optional[float] = None  # Unix timestamp
    client_version: Optional[str] = Field(None, max_length=16)


class BatchTelemetryRequest(BaseModel):
    """Batch telemetry event submission."""
    events: List[TelemetryEventRequest] = Field(..., max_length=MAX_BATCH_SIZE)
    session_id: Optional[str] = Field(None, max_length=64)
    client_version: Optional[str] = Field(None, max_length=16)


class TelemetryResponse(BaseModel):
    """Response for telemetry submission."""
    success: bool
    events_logged: int = 0
    events_flagged: int = 0
    message: Optional[str] = None


class SessionStatsResponse(BaseModel):
    """Session statistics summary."""
    session_id: str
    total_events: int
    kills: int
    gold_looted: int
    items_looted: int
    suspicious_events: int
    first_event: Optional[str] = None
    last_event: Optional[str] = None


# =============================================================================
# ANTI-CHEAT HELPERS
# =============================================================================

def check_kill_rate(db: DbSession, user_id: int, session_id: str) -> tuple[bool, str]:
    """
    Check if user is killing enemies at an impossible rate.
    Returns (is_suspicious, reason).
    """
    one_minute_ago = datetime.utcnow() - timedelta(minutes=1)

    recent_kills = db.query(func.count(GameEventLog.id)).filter(
        and_(
            GameEventLog.user_id == user_id,
            GameEventLog.event_type == 'kill',
            GameEventLog.session_id == session_id,
            GameEventLog.created_at >= one_minute_ago
        )
    ).scalar()

    if recent_kills >= MAX_KILLS_PER_MINUTE:
        return True, f"Kill rate exceeded: {recent_kills}/min"

    return False, ""


def check_event_anomalies(event: TelemetryEventRequest) -> tuple[bool, str]:
    """
    Check for obvious anomalies in event data.
    Returns (is_suspicious, reason).
    """
    if event.event_type == "kill":
        data = event.event_data

        # Check for impossible XP/gold values
        xp = data.get("xp_granted", 0)
        gold = data.get("gold_dropped", 0)
        enemy_level = data.get("enemy_level", 1)

        # XP should roughly scale with level
        expected_max_xp = enemy_level * 100
        if xp > expected_max_xp * 2:
            return True, f"XP too high for enemy level: {xp} > {expected_max_xp * 2}"

        # Gold should roughly scale with level
        expected_max_gold = enemy_level * 50
        if gold > expected_max_gold * 2:
            return True, f"Gold too high for enemy level: {gold} > {expected_max_gold * 2}"

    elif event.event_type == "loot":
        data = event.event_data

        # Check for impossible loot amounts
        gold = data.get("gold_amount", 0)
        if gold > 100000:
            return True, f"Loot gold amount suspicious: {gold}"

    return False, ""


# =============================================================================
# ENDPOINTS
# =============================================================================

@router.post("/kill", response_model=TelemetryResponse)
async def log_kill(
    request: Request,
    kill: KillEvent,
    session_id: Optional[str] = None,
    is_multiplayer: bool = False,
    zone_id: Optional[str] = None,
    position_x: Optional[float] = None,
    position_y: Optional[float] = None,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Log an enemy kill event.

    Called by Godot when an enemy dies and XP/gold is granted.
    """
    character = get_active_character(user, db)

    # Check kill rate
    is_suspicious, reason = check_kill_rate(db, user.id, session_id or "")

    # Create event
    event = GameEventLog(
        user_id=user.id,
        character_id=character.id,
        event_type="kill",
        event_data=kill.dict(),
        session_id=session_id,
        is_multiplayer=is_multiplayer,
        zone_id=zone_id,
        position_x=position_x,
        position_y=position_y,
        ip_address=request.client.host if request.client else None,
        is_suspicious=is_suspicious,
        suspicious_reason=reason if is_suspicious else None
    )

    db.add(event)
    db.commit()

    if is_suspicious:
        logger.warning(f"Suspicious kill from user {user.id}: {reason}")

    return TelemetryResponse(
        success=True,
        events_logged=1,
        events_flagged=1 if is_suspicious else 0
    )


@router.post("/loot", response_model=TelemetryResponse)
async def log_loot(
    request: Request,
    loot: LootEvent,
    session_id: Optional[str] = None,
    is_multiplayer: bool = False,
    zone_id: Optional[str] = None,
    position_x: Optional[float] = None,
    position_y: Optional[float] = None,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Log a loot pickup event.

    Called by Godot when player picks up gold or items.
    """
    character = get_active_character(user, db)

    # Basic anomaly check
    is_suspicious = False
    reason = None

    if loot.loot_type == "gold" and loot.gold_amount > 50000:
        is_suspicious = True
        reason = f"Large gold pickup: {loot.gold_amount}"

    # Create event
    event = GameEventLog(
        user_id=user.id,
        character_id=character.id,
        event_type=f"loot_{loot.loot_type}",
        event_data=loot.dict(),
        session_id=session_id,
        is_multiplayer=is_multiplayer,
        zone_id=zone_id,
        position_x=position_x,
        position_y=position_y,
        ip_address=request.client.host if request.client else None,
        is_suspicious=is_suspicious,
        suspicious_reason=reason
    )

    db.add(event)
    db.commit()

    if is_suspicious:
        logger.warning(f"Suspicious loot from user {user.id}: {reason}")

    return TelemetryResponse(
        success=True,
        events_logged=1,
        events_flagged=1 if is_suspicious else 0
    )


@router.post("/batch", response_model=TelemetryResponse)
async def log_batch(
    request: Request,
    batch: BatchTelemetryRequest,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Log multiple telemetry events in a single request.

    More efficient for high-frequency events. Events are processed
    and flagged individually.
    """
    character = get_active_character(user, db)
    client_ip = request.client.host if request.client else None

    events_logged = 0
    events_flagged = 0

    for event_req in batch.events:
        # Check for anomalies
        is_suspicious, reason = check_event_anomalies(event_req)

        # Parse timestamp
        client_ts = None
        if event_req.client_timestamp:
            try:
                client_ts = datetime.fromtimestamp(event_req.client_timestamp)
            except (ValueError, OSError):
                pass

        # Create event
        event = GameEventLog(
            user_id=user.id,
            character_id=character.id,
            event_type=event_req.event_type,
            event_data=event_req.event_data,
            session_id=event_req.session_id or batch.session_id,
            is_multiplayer=event_req.is_multiplayer,
            zone_id=event_req.zone_id,
            position_x=event_req.position_x,
            position_y=event_req.position_y,
            client_timestamp=client_ts,
            client_version=event_req.client_version or batch.client_version,
            ip_address=client_ip,
            is_suspicious=is_suspicious,
            suspicious_reason=reason if is_suspicious else None
        )

        db.add(event)
        events_logged += 1
        if is_suspicious:
            events_flagged += 1
            logger.warning(f"Suspicious event from user {user.id}: {reason}")

    db.commit()

    return TelemetryResponse(
        success=True,
        events_logged=events_logged,
        events_flagged=events_flagged
    )


@router.get("/session/{session_id}", response_model=SessionStatsResponse)
async def get_session_stats(
    session_id: str,
    request: Request,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Get statistics for a game session.

    Players can only view their own sessions.
    """
    # Get all events for this session owned by user
    events = db.query(GameEventLog).filter(
        and_(
            GameEventLog.session_id == session_id,
            GameEventLog.user_id == user.id
        )
    ).all()

    if not events:
        raise HTTPException(status_code=404, detail="Session not found")

    # Calculate stats
    kills = sum(1 for e in events if e.event_type == "kill")
    gold_looted = sum(
        e.event_data.get("gold_amount", 0)
        for e in events
        if e.event_type == "loot_gold"
    )
    items_looted = sum(1 for e in events if e.event_type == "loot_item")
    suspicious = sum(1 for e in events if e.is_suspicious)

    # Get time range
    timestamps = [e.created_at for e in events if e.created_at]
    first_event = min(timestamps).isoformat() if timestamps else None
    last_event = max(timestamps).isoformat() if timestamps else None

    return SessionStatsResponse(
        session_id=session_id,
        total_events=len(events),
        kills=kills,
        gold_looted=gold_looted,
        items_looted=items_looted,
        suspicious_events=suspicious,
        first_event=first_event,
        last_event=last_event
    )


@router.get("/recent")
async def get_recent_events(
    request: Request,
    limit: int = 50,
    event_type: Optional[str] = None,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Get recent telemetry events for the current user.

    Useful for debugging and reviewing activity.
    """
    query = db.query(GameEventLog).filter(
        GameEventLog.user_id == user.id
    )

    if event_type:
        query = query.filter(GameEventLog.event_type == event_type)

    events = query.order_by(GameEventLog.created_at.desc()).limit(min(limit, 100)).all()

    return {
        "events": [
            {
                "id": e.id,
                "event_type": e.event_type,
                "event_data": e.event_data,
                "session_id": e.session_id,
                "zone_id": e.zone_id,
                "is_suspicious": e.is_suspicious,
                "created_at": e.created_at.isoformat() if e.created_at else None
            }
            for e in events
        ],
        "count": len(events)
    }
