"""
Game client logging routes.

Receives batched logs from Godot clients and provides admin query endpoints.
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import desc, func
from typing import Optional, Callable, List
from datetime import datetime, timedelta
from pydantic import BaseModel, Field
import logging

from app.models import User, GameLog
from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/logs", tags=["logs"])

# Injected from main app
_get_current_user_func: Callable = None
_limiter = None  # Rate limiter from main app

# Configuration
MAX_BATCH_SIZE = 200
MAX_MESSAGE_LENGTH = 2000


# ═══════════════════════════════════════════════════════════════════════════
# REQUEST/RESPONSE MODELS
# ═══════════════════════════════════════════════════════════════════════════

class LogEntry(BaseModel):
    ts: float  # Unix timestamp from client
    level: int  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
    category: str = "default"
    message: str
    session_id: Optional[str] = None
    device_id: Optional[str] = None


class LogBatchRequest(BaseModel):
    logs: List[LogEntry] = Field(..., max_length=MAX_BATCH_SIZE)
    client_version: Optional[str] = None
    platform: Optional[str] = None
    is_host: bool = False


class LogBatchResponse(BaseModel):
    status: str
    count: int


class LogEntryResponse(BaseModel):
    id: int
    user_id: Optional[int]
    session_id: Optional[str]
    device_id: Optional[str]
    level: int
    category: Optional[str]
    message: str
    client_timestamp: Optional[datetime]
    created_at: datetime
    client_version: Optional[str]
    platform: Optional[str]
    is_host: bool
    ip_address: Optional[str]


class SessionSummary(BaseModel):
    session_id: str
    started_at: datetime
    log_count: int
    error_count: int
    platform: Optional[str]
    client_version: Optional[str]


# ═══════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════

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
        raise HTTPException(status_code=500, detail="Logging routes not initialized")
    return _get_current_user_func(request, db)


def _check_rate_limit(request: Request, limit: str):
    """Check rate limit using the main app's limiter."""
    if _limiter:
        from slowapi.util import get_remote_address
        try:
            _limiter._check_request_limit(request, None, limit, get_remote_address, 1)
        except Exception as e:
            if "Rate limit exceeded" in str(e) or "429" in str(e):
                raise HTTPException(status_code=429, detail=f"Rate limit exceeded. {limit}")


def init_logging_routes(get_current_user: Callable, limiter=None):
    """Initialize logging routes with dependencies from main app."""
    global _get_current_user_func, _limiter
    _get_current_user_func = get_current_user
    _limiter = limiter


def require_admin(user: User):
    """Verify user is an admin."""
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")


# ═══════════════════════════════════════════════════════════════════════════
# ROUTES
# ═══════════════════════════════════════════════════════════════════════════

@router.post("/batch", response_model=LogBatchResponse)
async def receive_log_batch(
    request: Request,
    batch: LogBatchRequest,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Receive batched logs from game client.

    - Logs are associated with the authenticated user
    - Client IP is recorded for abuse tracking
    - Messages are truncated if too long
    - Rate limited to 20/minute to prevent log spam attacks
    """
    # Rate limit to prevent log flooding
    _check_rate_limit(request, "20/minute")

    if len(batch.logs) > MAX_BATCH_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"Batch too large. Maximum {MAX_BATCH_SIZE} logs per request."
        )

    # Get client IP
    client_ip = request.client.host if request.client else None

    # Bulk insert logs
    log_records = []
    for entry in batch.logs:
        # Truncate message if too long
        message = entry.message[:MAX_MESSAGE_LENGTH] if entry.message else ""

        # Convert client timestamp
        client_ts = None
        if entry.ts:
            try:
                client_ts = datetime.utcfromtimestamp(entry.ts)
            except (ValueError, OSError):
                pass  # Invalid timestamp, leave as None

        log_record = GameLog(
            user_id=user.id,
            session_id=entry.session_id,
            device_id=entry.device_id,
            level=entry.level,
            category=entry.category,
            message=message,
            client_timestamp=client_ts,
            client_version=batch.client_version,
            platform=batch.platform,
            is_host=batch.is_host,
            ip_address=client_ip
        )
        log_records.append(log_record)

    db.add_all(log_records)
    db.commit()

    logger.info(f"Received {len(log_records)} logs from user {user.id} ({user.username})")

    return LogBatchResponse(status="ok", count=len(log_records))


class LogQueryResponse(BaseModel):
    logs: List[LogEntryResponse]
    total: int
    limit: int
    offset: int


@router.get("", response_model=LogQueryResponse)
@router.get("/recent", response_model=LogQueryResponse)
async def get_logs(
    user_id: Optional[int] = Query(None, description="Filter by user ID"),
    session_id: Optional[str] = Query(None, description="Filter by session ID"),
    category: Optional[str] = Query(None, description="Filter by category"),
    level: int = Query(0, ge=0, le=3, alias="min_level", description="Minimum log level (0=DEBUG, 3=ERROR)"),
    since: Optional[float] = Query(None, description="Unix timestamp - logs after this time"),
    limit: int = Query(100, ge=1, le=1000, description="Max results"),
    offset: int = Query(0, ge=0, description="Pagination offset"),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Query logs (Admin only).

    Filters:
    - user_id: Filter by specific user
    - session_id: Filter by game session
    - category: Filter by log category (e.g., "duel", "combat")
    - level/min_level: Minimum log level (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR)
    - since: Unix timestamp - only logs after this time
    - limit: Max results (default 100, max 1000)
    - offset: Pagination offset
    """
    require_admin(current_user)

    query = db.query(GameLog)

    if user_id is not None:
        query = query.filter(GameLog.user_id == user_id)
    if session_id is not None:
        query = query.filter(GameLog.session_id == session_id)
    if category is not None:
        query = query.filter(GameLog.category == category)
    if level > 0:
        query = query.filter(GameLog.level >= level)
    if since is not None:
        try:
            since_dt = datetime.utcfromtimestamp(since)
            query = query.filter(GameLog.created_at >= since_dt)
        except (ValueError, OSError):
            raise HTTPException(status_code=400, detail="Invalid 'since' timestamp")

    # Get total count before pagination
    total = query.count()

    # Apply pagination and ordering
    logs = query.order_by(desc(GameLog.created_at)).offset(offset).limit(limit).all()

    return LogQueryResponse(
        logs=[
            LogEntryResponse(
                id=log.id,
                user_id=log.user_id,
                session_id=log.session_id,
                device_id=log.device_id,
                level=log.level,
                category=log.category,
                message=log.message,
                client_timestamp=log.client_timestamp,
                created_at=log.created_at,
                client_version=log.client_version,
                platform=log.platform,
                is_host=log.is_host,
                ip_address=log.ip_address
            )
            for log in logs
        ],
        total=total,
        limit=limit,
        offset=offset
    )


@router.get("/sessions", response_model=List[SessionSummary])
async def get_user_sessions(
    user_id: int = Query(..., description="User ID (required)"),
    limit: int = Query(20, ge=1, le=100, description="Max sessions"),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    List recent sessions for a user (Admin only).

    Returns session summaries with log counts and timestamps.
    """
    require_admin(current_user)

    # Get distinct sessions with aggregated data
    sessions = (
        db.query(
            GameLog.session_id,
            func.min(GameLog.created_at).label("started_at"),
            func.count(GameLog.id).label("log_count"),
            func.sum(func.cast(GameLog.level >= 3, db.bind.dialect.type_descriptor(type(1)))).label("error_count"),
            func.max(GameLog.platform).label("platform"),
            func.max(GameLog.client_version).label("client_version")
        )
        .filter(GameLog.user_id == user_id)
        .filter(GameLog.session_id.isnot(None))
        .group_by(GameLog.session_id)
        .order_by(desc("started_at"))
        .limit(limit)
        .all()
    )

    return [
        SessionSummary(
            session_id=s.session_id,
            started_at=s.started_at,
            log_count=s.log_count,
            error_count=s.error_count or 0,
            platform=s.platform,
            client_version=s.client_version
        )
        for s in sessions
    ]


@router.get("/stats")
async def get_log_stats(
    hours: int = Query(24, ge=1, le=168, description="Hours to look back"),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get log statistics (Admin only).

    Returns counts by level and category for the specified time window.
    """
    require_admin(current_user)

    cutoff = datetime.utcnow() - timedelta(hours=hours)

    # Total count
    total = db.query(func.count(GameLog.id)).filter(GameLog.created_at >= cutoff).scalar()

    # Count by level
    level_counts = dict(
        db.query(GameLog.level, func.count(GameLog.id))
        .filter(GameLog.created_at >= cutoff)
        .group_by(GameLog.level)
        .all()
    )

    # Count by category (top 10)
    category_counts = dict(
        db.query(GameLog.category, func.count(GameLog.id))
        .filter(GameLog.created_at >= cutoff)
        .group_by(GameLog.category)
        .order_by(desc(func.count(GameLog.id)))
        .limit(10)
        .all()
    )

    # Unique users and sessions
    unique_users = db.query(func.count(func.distinct(GameLog.user_id))).filter(GameLog.created_at >= cutoff).scalar()
    unique_sessions = db.query(func.count(func.distinct(GameLog.session_id))).filter(GameLog.created_at >= cutoff).scalar()

    return {
        "hours": hours,
        "total_logs": total,
        "by_level": {
            "debug": level_counts.get(0, 0),
            "info": level_counts.get(1, 0),
            "warn": level_counts.get(2, 0),
            "error": level_counts.get(3, 0)
        },
        "by_category": category_counts,
        "unique_users": unique_users,
        "unique_sessions": unique_sessions
    }
