"""
Gameplay telemetry routes for kill/loot/combat event logging.

Provides audit trail for anti-cheat detection without blocking gameplay.
Events are logged asynchronously and analyzed for anomalies.

See docs/VENDOR_PURCHASE_SPEC.md for related security context.
"""
import logging
from datetime import datetime, timedelta
from typing import Callable, Optional, List

from fastapi import APIRouter, Depends, HTTPException, Request, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import func, and_

from app.database import SessionLocal
from app.models import (
    User, Character, GameEventLog, ForgedAchievement, ItemTrade,
    TradeListing, AchievementCredit, WalletAccount, BridgeTransaction, Achievement
)
from app.services.item_forge_service import get_achievement_mappings
from app.services.relayer_service import relayer_service
from app.services.transfer_indexer_service import get_indexer_status
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

        # Normalize event_type for loot events to match individual endpoint format
        # Client sends event_type="loot" with loot_type in event_data
        # Stats queries expect "loot_gold" or "loot_item"
        event_type = event_req.event_type
        if event_type == "loot" and isinstance(event_req.event_data, dict):
            loot_type = event_req.event_data.get("loot_type")
            if loot_type in ("gold", "item"):
                event_type = f"loot_{loot_type}"

        # Create event
        event = GameEventLog(
            user_id=user.id,
            character_id=character.id,
            event_type=event_type,
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


@router.get("/stats")
async def get_telemetry_stats(
    request: Request,
    hours: int = 24,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Get gameplay telemetry statistics (Admin only for full stats).

    Returns aggregate stats for kills, loot, and suspicious activity.
    """
    from datetime import timedelta

    cutoff = datetime.utcnow() - timedelta(hours=hours)

    # Total events (all time)
    total_all = db.query(func.count(GameEventLog.id)).scalar() or 0

    # Events in time window
    total = db.query(func.count(GameEventLog.id)).filter(
        GameEventLog.created_at >= cutoff
    ).scalar() or 0

    # Count by event type
    type_counts = dict(
        db.query(GameEventLog.event_type, func.count(GameEventLog.id))
        .filter(GameEventLog.created_at >= cutoff)
        .group_by(GameEventLog.event_type)
        .all()
    )

    # Suspicious events
    suspicious_count = db.query(func.count(GameEventLog.id)).filter(
        and_(
            GameEventLog.created_at >= cutoff,
            GameEventLog.is_suspicious == True
        )
    ).scalar() or 0

    # Top suspicious reasons
    suspicious_reasons = dict(
        db.query(GameEventLog.suspicious_reason, func.count(GameEventLog.id))
        .filter(
            and_(
                GameEventLog.created_at >= cutoff,
                GameEventLog.is_suspicious == True,
                GameEventLog.suspicious_reason.isnot(None)
            )
        )
        .group_by(GameEventLog.suspicious_reason)
        .order_by(func.count(GameEventLog.id).desc())
        .limit(5)
        .all()
    )

    # Unique users and sessions
    unique_users = db.query(func.count(func.distinct(GameEventLog.user_id))).filter(
        GameEventLog.created_at >= cutoff
    ).scalar() or 0

    unique_sessions = db.query(func.count(func.distinct(GameEventLog.session_id))).filter(
        GameEventLog.created_at >= cutoff
    ).scalar() or 0

    # Top zones
    zone_counts = dict(
        db.query(GameEventLog.zone_id, func.count(GameEventLog.id))
        .filter(
            and_(
                GameEventLog.created_at >= cutoff,
                GameEventLog.zone_id.isnot(None)
            )
        )
        .group_by(GameEventLog.zone_id)
        .order_by(func.count(GameEventLog.id).desc())
        .limit(5)
        .all()
    )

    # Calculate gold and XP totals from kill events
    kill_events = db.query(GameEventLog).filter(
        and_(
            GameEventLog.created_at >= cutoff,
            GameEventLog.event_type == "kill"
        )
    ).all()

    total_kills = len(kill_events)
    total_xp = sum(e.event_data.get("xp_granted", 0) for e in kill_events)
    total_gold_dropped = sum(e.event_data.get("gold_dropped", 0) for e in kill_events)

    # Gold looted
    loot_gold_events = db.query(GameEventLog).filter(
        and_(
            GameEventLog.created_at >= cutoff,
            GameEventLog.event_type == "loot_gold"
        )
    ).all()
    total_gold_looted = sum(e.event_data.get("gold_amount", 0) for e in loot_gold_events)

    # Items looted count
    items_looted = type_counts.get("loot_item", 0)

    return {
        "hours": hours,
        "total_events_all": total_all,
        "total_events": total,
        "by_type": {
            "kills": type_counts.get("kill", 0),
            "loot_gold": type_counts.get("loot_gold", 0),
            "loot_item": type_counts.get("loot_item", 0),
            "resource": type_counts.get("resource", 0),
            "damage": type_counts.get("damage", 0)
        },
        "totals": {
            "kills": total_kills,
            "xp_granted": total_xp,
            "gold_dropped": total_gold_dropped,
            "gold_looted": total_gold_looted,
            "items_looted": items_looted
        },
        "suspicious": {
            "count": suspicious_count,
            "by_reason": suspicious_reasons
        },
        "unique_users": unique_users,
        "unique_sessions": unique_sessions,
        "top_zones": zone_counts,
        "backend_ops": _get_backend_ops_stats(db, cutoff)
    }


def _get_backend_ops_stats(db: DbSession, cutoff: datetime) -> dict:
    """Get backend operation stats for the given time window."""
    # Count backend operations by type
    backend_types = ["vendor_purchase", "vendor_sell", "character_save", "character_load"]

    type_counts = dict(
        db.query(GameEventLog.event_type, func.count(GameEventLog.id))
        .filter(
            and_(
                GameEventLog.created_at >= cutoff,
                GameEventLog.event_type.in_(backend_types)
            )
        )
        .group_by(GameEventLog.event_type)
        .all()
    )

    # Calculate totals from event data
    purchase_events = db.query(GameEventLog).filter(
        and_(
            GameEventLog.created_at >= cutoff,
            GameEventLog.event_type == "vendor_purchase"
        )
    ).all()

    sell_events = db.query(GameEventLog).filter(
        and_(
            GameEventLog.created_at >= cutoff,
            GameEventLog.event_type == "vendor_sell"
        )
    ).all()

    total_gold_spent = sum(e.event_data.get("gold_spent", 0) for e in purchase_events)
    total_gold_earned = sum(e.event_data.get("gold_earned", 0) for e in sell_events)

    return {
        "purchases": type_counts.get("vendor_purchase", 0),
        "sells": type_counts.get("vendor_sell", 0),
        "saves": type_counts.get("character_save", 0),
        "loads": type_counts.get("character_load", 0),
        "gold_spent": total_gold_spent,
        "gold_earned": total_gold_earned,
    }


# =============================================================================
# FORGE ECONOMY STATISTICS
# =============================================================================

@router.get("/economy")
async def get_forge_economy_stats(
    hours: int = Query(default=24, ge=1, le=720),  # Up to 30 days
    db: DbSession = Depends(get_db)
):
    """
    Get comprehensive forge economy statistics.

    Includes:
    - Forge item circulation (in-game, bridged, destroyed)
    - Trading activity (forged items, gold volume)
    - User forge credits
    - Suspicious economy activity
    """
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    # === FORGED ITEM CIRCULATION ===
    total_forged = db.query(ForgedAchievement).count()

    # By bridge status
    in_game = db.query(ForgedAchievement).filter(
        ForgedAchievement.bridge_status == "in_game",
        ForgedAchievement.destroyed_at.is_(None)
    ).count()

    bridged_out = db.query(ForgedAchievement).filter(
        ForgedAchievement.bridge_status == "bridged",
        ForgedAchievement.destroyed_at.is_(None)
    ).count()

    bridging = db.query(ForgedAchievement).filter(
        ForgedAchievement.bridge_status.in_(["bridging_out", "bridging_in"]),
        ForgedAchievement.destroyed_at.is_(None)
    ).count()

    destroyed = db.query(ForgedAchievement).filter(
        ForgedAchievement.destroyed_at.isnot(None)
    ).count()

    # By rarity
    rarity_counts = dict(
        db.query(ForgedAchievement.item_rarity, func.count(ForgedAchievement.id))
        .filter(ForgedAchievement.destroyed_at.is_(None))
        .group_by(ForgedAchievement.item_rarity)
        .all()
    )

    # Recent forges
    recent_forges = db.query(ForgedAchievement).filter(
        ForgedAchievement.forged_at >= cutoff
    ).count()

    # === TRADING ACTIVITY ===
    # Total trades in period
    total_trades = db.query(ItemTrade).filter(
        ItemTrade.traded_at >= cutoff
    ).count()

    # Trades with gold (not gifts)
    paid_trades = db.query(ItemTrade).filter(
        ItemTrade.traded_at >= cutoff,
        ItemTrade.price_gold > 0
    ).count()

    gift_trades = total_trades - paid_trades

    # Gold volume
    gold_volume_result = db.query(func.sum(ItemTrade.price_gold)).filter(
        ItemTrade.traded_at >= cutoff
    ).scalar()
    gold_volume = gold_volume_result or 0

    # Tax collected
    tax_collected_result = db.query(func.sum(ItemTrade.tax_applied)).filter(
        ItemTrade.traded_at >= cutoff
    ).scalar()
    tax_collected = tax_collected_result or 0

    # Average trade price
    avg_price_result = db.query(func.avg(ItemTrade.price_gold)).filter(
        ItemTrade.traded_at >= cutoff,
        ItemTrade.price_gold > 0
    ).scalar()
    avg_trade_price = int(avg_price_result) if avg_price_result else 0

    # Active listings
    active_listings = db.query(TradeListing).filter(
        TradeListing.expires_at > datetime.utcnow()
    ).count()

    # === FORGE CREDITS ===
    # Get achievement mappings to determine which credits are actually useable
    achievement_mappings = get_achievement_mappings()
    mapping_keys = set(achievement_mappings.keys())  # Set of "app_id:api_name"

    # Get all original claim credits with their achievement details
    credits_with_achievements = db.query(AchievementCredit, Achievement).join(
        Achievement, AchievementCredit.achievement_id == Achievement.id
    ).filter(
        AchievementCredit.is_original_claim == True
    ).all()

    # Count useable credits (those with valid achievement mappings)
    useable_credits = 0
    for credit, achievement in credits_with_achievements:
        key = f"{achievement.app_id}:{achievement.api_name}"
        if key in mapping_keys:
            useable_credits += 1

    total_credits = len(credits_with_achievements)

    # Users with ANY credits (for display)
    users_with_credits = db.query(func.count(func.distinct(AchievementCredit.user_id))).filter(
        AchievementCredit.is_original_claim == True
    ).scalar() or 0

    # Credits used (forged into items)
    credits_used = db.query(ForgedAchievement).filter(
        ForgedAchievement.achievement_credit_id.isnot(None)
    ).count()

    credits_available = useable_credits - credits_used

    # === SUSPICIOUS ACTIVITY ===
    # Large gold trades (>10k)
    large_trades = db.query(ItemTrade).filter(
        ItemTrade.traded_at >= cutoff,
        ItemTrade.price_gold >= 10000
    ).count()

    # Very large trades (>50k) - potential RMT
    very_large_trades = db.query(ItemTrade).filter(
        ItemTrade.traded_at >= cutoff,
        ItemTrade.price_gold >= 50000
    ).count()

    # High frequency traders (>5 trades in period)
    high_freq_traders = db.query(ItemTrade.from_user_id).filter(
        ItemTrade.traded_at >= cutoff
    ).group_by(ItemTrade.from_user_id).having(
        func.count(ItemTrade.id) > 5
    ).count()

    # Bridge activity
    bridge_out_requests = db.query(BridgeTransaction).filter(
        BridgeTransaction.requested_at >= cutoff,
        BridgeTransaction.transaction_type == "bridge_out"
    ).count()

    bridge_in_requests = db.query(BridgeTransaction).filter(
        BridgeTransaction.requested_at >= cutoff,
        BridgeTransaction.transaction_type == "bridge_in"
    ).count()

    return {
        "time_window_hours": hours,
        "circulation": {
            "total_forged": total_forged,
            "in_game": in_game,
            "bridged_out": bridged_out,
            "bridging": bridging,
            "destroyed": destroyed,
            "by_rarity": {
                "common": rarity_counts.get("Common", 0),
                "uncommon": rarity_counts.get("Uncommon", 0),
                "rare": rarity_counts.get("Rare", 0),
                "epic": rarity_counts.get("Epic", 0),
                "legendary": rarity_counts.get("Legendary", 0),
            }
        },
        "trading": {
            "total_trades": total_trades,
            "paid_trades": paid_trades,
            "gift_trades": gift_trades,
            "gold_volume": gold_volume,
            "tax_collected": tax_collected,
            "avg_trade_price": avg_trade_price,
            "active_listings": active_listings,
        },
        "forge_credits": {
            "users_with_credits": users_with_credits,
            "total_credits": total_credits,
            "useable_credits": useable_credits,
            "credits_used": credits_used,
            "credits_available": credits_available,
            "unmapped_credits": total_credits - useable_credits,
        },
        "recent_activity": {
            "forges": recent_forges,
            "bridge_out": bridge_out_requests,
            "bridge_in": bridge_in_requests,
        },
        "alerts": {
            "large_trades_10k": large_trades,
            "very_large_trades_50k": very_large_trades,
            "high_frequency_traders": high_freq_traders,
        }
    }


@router.get("/economy/details/{section}")
async def get_economy_section_details(
    section: str,
    hours: int = Query(default=24, ge=1, le=720),
    limit: int = Query(default=50, ge=1, le=200),
    db: DbSession = Depends(get_db)
):
    """
    Get detailed data for a specific economy section.

    Sections:
    - circulation: Items by rarity and status
    - trading: Recent trades with details
    - credits: Users with forge credits
    - alerts: Suspicious activity details
    """
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    if section == "circulation":
        # Get items grouped by status and rarity
        items = db.query(ForgedAchievement).filter(
            ForgedAchievement.destroyed_at.is_(None)
        ).order_by(ForgedAchievement.forged_at.desc()).limit(limit).all()

        # Get rarity breakdown
        rarity_counts = dict(
            db.query(ForgedAchievement.item_rarity, func.count(ForgedAchievement.id))
            .filter(ForgedAchievement.destroyed_at.is_(None))
            .group_by(ForgedAchievement.item_rarity)
            .all()
        )

        # Get status breakdown
        status_counts = dict(
            db.query(ForgedAchievement.bridge_status, func.count(ForgedAchievement.id))
            .filter(ForgedAchievement.destroyed_at.is_(None))
            .group_by(ForgedAchievement.bridge_status)
            .all()
        )

        # Get destroyed count
        destroyed_count = db.query(ForgedAchievement).filter(
            ForgedAchievement.destroyed_at.isnot(None)
        ).count()

        return {
            "section": "circulation",
            "summary": {
                "by_rarity": rarity_counts,
                "by_status": status_counts,
                "destroyed": destroyed_count,
            },
            "items": [
                {
                    "token_id": item.token_id,
                    "item_id": item.item_id,
                    "item_name": item.item_name,
                    "item_rarity": item.item_rarity,
                    "bridge_status": item.bridge_status,
                    "forged_at": item.forged_at.isoformat() if item.forged_at else None,
                    "trade_count": item.trade_count,
                    "current_owner_id": item.current_owner_id,
                }
                for item in items
            ]
        }

    elif section == "trading":
        # Get recent trades with full details
        trades = db.query(ItemTrade).filter(
            ItemTrade.traded_at >= cutoff
        ).order_by(ItemTrade.traded_at.desc()).limit(limit).all()

        # Get top traders by volume
        top_sellers = db.query(
            ItemTrade.from_user_id,
            func.count(ItemTrade.id).label('trade_count'),
            func.sum(ItemTrade.price_gold).label('gold_volume')
        ).filter(
            ItemTrade.traded_at >= cutoff
        ).group_by(ItemTrade.from_user_id).order_by(
            func.count(ItemTrade.id).desc()
        ).limit(10).all()

        # Get user names for top sellers
        seller_ids = [s[0] for s in top_sellers]
        users = {u.id: u.username for u in db.query(User).filter(User.id.in_(seller_ids)).all()}

        return {
            "section": "trading",
            "time_window_hours": hours,
            "top_traders": [
                {
                    "user_id": s[0],
                    "username": users.get(s[0], "Unknown"),
                    "trade_count": s[1],
                    "gold_volume": s[2] or 0,
                }
                for s in top_sellers
            ],
            "recent_trades": [
                {
                    "trade_id": t.id,
                    "traded_at": t.traded_at.isoformat() if t.traded_at else None,
                    "item_name": t.forged_item.item_name if t.forged_item else "Unknown",
                    "item_rarity": t.forged_item.item_rarity if t.forged_item else None,
                    "from_user": t.from_user.username if t.from_user else "Unknown",
                    "to_user": t.to_user.username if t.to_user else "Unknown",
                    "price_gold": t.price_gold or 0,
                    "tax_applied": t.tax_applied or 0,
                    "is_gift": (t.price_gold or 0) == 0,
                }
                for t in trades
            ]
        }

    elif section == "credits":
        # Get achievement mappings to determine useable credits
        achievement_mappings = get_achievement_mappings()
        mapping_keys = set(achievement_mappings.keys())

        # Get all credits with achievements for all users
        all_credits = db.query(
            AchievementCredit.user_id,
            Achievement.app_id,
            Achievement.api_name
        ).join(
            Achievement, AchievementCredit.achievement_id == Achievement.id
        ).filter(
            AchievementCredit.is_original_claim == True
        ).all()

        # Count per user: total and useable
        user_stats = {}
        for user_id, app_id, api_name in all_credits:
            if user_id not in user_stats:
                user_stats[user_id] = {"total": 0, "useable": 0}
            user_stats[user_id]["total"] += 1
            key = f"{app_id}:{api_name}"
            if key in mapping_keys:
                user_stats[user_id]["useable"] += 1

        # Get user names
        user_ids = list(user_stats.keys())
        users = {u.id: u.username for u in db.query(User).filter(User.id.in_(user_ids)).all()}

        # Get forged counts per user
        forged_counts = dict(
            db.query(
                WalletAccount.user_id,
                func.count(ForgedAchievement.id)
            ).join(ForgedAchievement, ForgedAchievement.wallet_account_id == WalletAccount.id)
            .group_by(WalletAccount.user_id).all()
        )

        # Sort by useable credits descending
        sorted_users = sorted(user_stats.items(), key=lambda x: x[1]["useable"], reverse=True)[:limit]

        return {
            "section": "credits",
            "achievement_mappings_count": len(mapping_keys),
            "users": [
                {
                    "user_id": user_id,
                    "username": users.get(user_id, "Unknown"),
                    "total_credits": stats["total"],
                    "useable_credits": stats["useable"],
                    "unmapped_credits": stats["total"] - stats["useable"],
                    "items_forged": forged_counts.get(user_id, 0),
                    "credits_available": stats["useable"] - forged_counts.get(user_id, 0),
                }
                for user_id, stats in sorted_users
            ]
        }

    elif section == "alerts":
        # Get detailed alert information

        # Large trades (>10k)
        large_trades = db.query(ItemTrade).filter(
            ItemTrade.traded_at >= cutoff,
            ItemTrade.price_gold >= 10000
        ).order_by(ItemTrade.price_gold.desc()).limit(limit).all()

        # High frequency traders
        high_freq = db.query(
            ItemTrade.from_user_id,
            func.count(ItemTrade.id).label('trade_count')
        ).filter(
            ItemTrade.traded_at >= cutoff
        ).group_by(ItemTrade.from_user_id).having(
            func.count(ItemTrade.id) > 5
        ).order_by(func.count(ItemTrade.id).desc()).all()

        # Get user names
        user_ids = list(set([t.from_user_id for t in large_trades] + [h[0] for h in high_freq]))
        users = {u.id: u.username for u in db.query(User).filter(User.id.in_(user_ids)).all()}

        return {
            "section": "alerts",
            "time_window_hours": hours,
            "large_trades": [
                {
                    "trade_id": t.id,
                    "traded_at": t.traded_at.isoformat() if t.traded_at else None,
                    "item_name": t.forged_item.item_name if t.forged_item else "Unknown",
                    "from_user": users.get(t.from_user_id, "Unknown"),
                    "to_user": t.to_user.username if t.to_user else "Unknown",
                    "price_gold": t.price_gold,
                    "severity": "critical" if t.price_gold >= 50000 else "warning",
                }
                for t in large_trades
            ],
            "high_frequency_traders": [
                {
                    "user_id": h[0],
                    "username": users.get(h[0], "Unknown"),
                    "trade_count": h[1],
                }
                for h in high_freq
            ]
        }

    else:
        raise HTTPException(status_code=400, detail=f"Unknown section: {section}")


# =============================================================================
# BLOCKCHAIN STATUS
# =============================================================================

@router.get("/blockchain")
async def get_blockchain_status(
    db: DbSession = Depends(get_db)
):
    """
    Get blockchain integration status.

    Includes:
    - Relayer status (connected, balance, address)
    - Indexer status (running, last block scanned)
    - Bridge activity (pending, completed, items bridged out)
    """
    import os

    # === RELAYER STATUS ===
    relayer_initialized = relayer_service._initialized
    relayer_address = relayer_service.get_relayer_address()
    relayer_balance = None

    if relayer_initialized:
        try:
            relayer_balance = relayer_service.get_balance()
        except:
            pass

    relayer_status = {
        "configured": bool(os.environ.get("POLYGON_RPC_URL") and os.environ.get("RELAYER_PRIVATE_KEY")),
        "connected": relayer_initialized,
        "address": relayer_address,
        "balance_matic": relayer_balance,
        "contract_address": os.environ.get("FORGED_ITEMS_CONTRACT", "Not configured"),
    }

    # === INDEXER STATUS ===
    indexer_status = get_indexer_status()

    # === BRIDGE ACTIVITY ===
    # Pending bridge-out requests
    pending_bridge_out = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "bridge_out",
        BridgeTransaction.status == "pending"
    ).count()

    # Pending bridge-in requests
    pending_bridge_in = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "bridge_in",
        BridgeTransaction.status == "pending"
    ).count()

    # Items currently bridged out (not in game)
    items_bridged_out = db.query(ForgedAchievement).filter(
        ForgedAchievement.bridge_status == "bridged",
        ForgedAchievement.destroyed_at.is_(None)
    ).count()

    # Items currently bridging (in transit)
    items_bridging = db.query(ForgedAchievement).filter(
        ForgedAchievement.bridge_status.in_(["bridging_out", "bridging_in"]),
        ForgedAchievement.destroyed_at.is_(None)
    ).count()

    # Recent bridge transactions (last 24h)
    cutoff = datetime.utcnow() - timedelta(hours=24)
    recent_bridges = db.query(BridgeTransaction).filter(
        BridgeTransaction.requested_at >= cutoff
    ).order_by(BridgeTransaction.requested_at.desc()).limit(10).all()

    # External transfers detected (OpenSea sales, etc)
    external_transfers_24h = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "external_transfer",
        BridgeTransaction.requested_at >= cutoff
    ).count()

    # Total bridge transactions ever
    total_bridge_out = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "bridge_out",
        BridgeTransaction.status == "completed"
    ).count()

    total_bridge_in = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "bridge_in",
        BridgeTransaction.status == "completed"
    ).count()

    total_external = db.query(BridgeTransaction).filter(
        BridgeTransaction.transaction_type == "external_transfer"
    ).count()

    bridge_activity = {
        "pending": {
            "bridge_out": pending_bridge_out,
            "bridge_in": pending_bridge_in,
        },
        "items": {
            "bridged_out": items_bridged_out,
            "bridging": items_bridging,
        },
        "totals": {
            "bridge_out_completed": total_bridge_out,
            "bridge_in_completed": total_bridge_in,
            "external_transfers": total_external,
        },
        "last_24h": {
            "external_transfers": external_transfers_24h,
        },
        "recent_transactions": [
            {
                "id": tx.id,
                "type": tx.transaction_type,
                "status": tx.status,
                "requested_at": tx.requested_at.isoformat() if tx.requested_at else None,
                "completed_at": tx.completed_at.isoformat() if tx.completed_at else None,
                "tx_hash": tx.tx_hash[:16] + "..." if tx.tx_hash else None,
            }
            for tx in recent_bridges
        ]
    }

    # === CHAIN CONFIG ===
    chain_config = {
        "chain_id": os.environ.get("CHAIN_ID", "Not configured"),
        "rpc_url": os.environ.get("RPC_URL") or os.environ.get("POLYGON_RPC_URL", "Not configured"),
        "platform_wallet": os.environ.get("PLATFORM_WALLET_ADDRESS", "Not configured"),
    }

    return {
        "relayer": relayer_status,
        "indexer": indexer_status,
        "bridge_activity": bridge_activity,
        "chain_config": chain_config,
    }
