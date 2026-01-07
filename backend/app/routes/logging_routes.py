"""
Game client logging routes.

Receives batched logs from Godot clients and provides admin query endpoints.
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import desc, func
from typing import Optional, Callable, List
from datetime import datetime, timedelta
from pydantic import BaseModel, Field
import logging
import html
import os
import shutil

from app.models import User, GameLog, SuspiciousIP
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

def get_optional_user(request: Request, db: DbSession = Depends(get_db)) -> Optional[User]:
    """Get current user if authenticated, None otherwise (for anonymous logs)."""
    if _get_current_user_func is None:
        return None
    try:
        return _get_current_user_func(request, db)
    except HTTPException:
        return None


@router.post("/batch", response_model=LogBatchResponse)
async def receive_log_batch(
    request: Request,
    batch: LogBatchRequest,
    db: DbSession = Depends(get_db),
    user: Optional[User] = Depends(get_optional_user)
):
    """
    Receive batched logs from game client.

    Supports both authenticated and anonymous logging:
    - Authenticated: Logs associated with user account
    - Anonymous: Logs tracked by device_id/session_id and IP

    Rate limited to 20/minute per IP to prevent abuse.
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

    # For anonymous logs, require at least device_id or session_id
    is_anonymous = user is None
    if is_anonymous:
        has_identifier = any(entry.device_id or entry.session_id for entry in batch.logs)
        if not has_identifier:
            raise HTTPException(
                status_code=400,
                detail="Anonymous logs require device_id or session_id"
            )

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
            user_id=user.id if user else None,
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

    if user:
        logger.info(f"Received {len(log_records)} logs from user {user.id} ({user.username})")
    else:
        logger.info(f"Received {len(log_records)} anonymous logs from {client_ip}")

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

    # Total count (all time)
    total_all = db.query(func.count(GameLog.id)).scalar() or 0

    # Total in time window
    total = db.query(func.count(GameLog.id)).filter(GameLog.created_at >= cutoff).scalar() or 0

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
    unique_users = db.query(func.count(func.distinct(GameLog.user_id))).filter(GameLog.created_at >= cutoff).scalar() or 0
    unique_sessions = db.query(func.count(func.distinct(GameLog.session_id))).filter(GameLog.created_at >= cutoff).scalar() or 0

    return {
        "hours": hours,
        "total_logs_all": total_all,
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


# ═══════════════════════════════════════════════════════════════════════════
# HTML LOG VIEWER (QA-friendly)
# ═══════════════════════════════════════════════════════════════════════════

LEVEL_NAMES = {0: "DEBUG", 1: "INFO", 2: "WARN", 3: "ERROR"}
LEVEL_COLORS = {0: "#888", 1: "#4a9eff", 2: "#f5a623", 3: "#ff4444"}


@router.get("/view", response_class=HTMLResponse)
async def view_logs_html(
    request: Request,
    user_id: Optional[int] = Query(None),
    session_id: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    level: int = Query(0, ge=0, le=3, alias="min_level"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """HTML log viewer for QA (Admin only)."""
    require_admin(current_user)

    # Gather system stats
    cutoff_24h = datetime.utcnow() - timedelta(hours=24)
    total_logs_all = db.query(func.count(GameLog.id)).scalar() or 0
    logs_24h = db.query(func.count(GameLog.id)).filter(GameLog.created_at >= cutoff_24h).scalar() or 0
    errors_24h = db.query(func.count(GameLog.id)).filter(
        GameLog.created_at >= cutoff_24h, GameLog.level >= 3
    ).scalar() or 0
    warns_24h = db.query(func.count(GameLog.id)).filter(
        GameLog.created_at >= cutoff_24h, GameLog.level == 2
    ).scalar() or 0
    unique_sessions_24h = db.query(func.count(func.distinct(GameLog.session_id))).filter(
        GameLog.created_at >= cutoff_24h
    ).scalar() or 0
    unique_users_24h = db.query(func.count(func.distinct(GameLog.user_id))).filter(
        GameLog.created_at >= cutoff_24h
    ).scalar() or 0

    # Database file size
    db_path = "/root/ashbane-backend/backend/socialauth.db"
    try:
        db_size_mb = os.path.getsize(db_path) / (1024 * 1024)
        db_size_str = f"{db_size_mb:.1f} MB"
    except:
        db_size_str = "N/A"

    # Disk usage
    try:
        disk = shutil.disk_usage("/")
        disk_used_gb = (disk.total - disk.free) / (1024**3)
        disk_total_gb = disk.total / (1024**3)
        disk_pct = ((disk.total - disk.free) / disk.total) * 100
        disk_str = f"{disk_used_gb:.1f}/{disk_total_gb:.0f} GB ({disk_pct:.0f}%)"
    except:
        disk_str = "N/A"

    query = db.query(GameLog)
    if user_id is not None:
        query = query.filter(GameLog.user_id == user_id)
    if session_id is not None:
        query = query.filter(GameLog.session_id == session_id)
    if category is not None:
        query = query.filter(GameLog.category == category)
    if level > 0:
        query = query.filter(GameLog.level >= level)

    total = query.count()
    logs = query.order_by(desc(GameLog.created_at)).offset(offset).limit(limit).all()

    # Get unique categories for filter dropdown
    categories = [c[0] for c in db.query(GameLog.category).distinct().all() if c[0]]

    # Build query string for pagination links
    params = []
    if user_id: params.append(f"user_id={user_id}")
    if session_id: params.append(f"session_id={session_id}")
    if category: params.append(f"category={category}")
    if level > 0: params.append(f"min_level={level}")
    params.append(f"limit={limit}")
    base_qs = "&".join(params)

    # Build log rows
    rows = []
    for log in logs:
        level_name = LEVEL_NAMES.get(log.level, "?")
        level_color = LEVEL_COLORS.get(log.level, "#888")
        ts = log.client_timestamp.strftime("%H:%M:%S.%f")[:-3] if log.client_timestamp else "-"
        msg = html.escape(log.message or "")
        cat = html.escape(log.category or "-")
        sid_short = log.session_id[:8] if log.session_id else "-"

        rows.append(f"""
        <tr>
            <td style="color:#666">{log.id}</td>
            <td>{ts}</td>
            <td style="color:{level_color};font-weight:bold">{level_name}</td>
            <td><a href="?session_id={log.session_id}&limit={limit}" style="color:#4a9eff">{sid_short}</a></td>
            <td><a href="?category={cat}&limit={limit}" style="color:#4a9eff">{cat}</a></td>
            <td style="font-family:monospace;white-space:pre-wrap;max-width:600px">{msg}</td>
            <td style="color:#666">{log.platform or '-'}</td>
            <td style="color:#666">{log.client_version or '-'}</td>
        </tr>
        """)

    # Pagination
    prev_offset = max(0, offset - limit)
    next_offset = offset + limit
    has_prev = offset > 0
    has_next = offset + limit < total

    prev_link = f'<a href="?{base_qs}&offset={prev_offset}" style="color:#4a9eff;margin-right:20px">← Previous</a>' if has_prev else ''
    next_link = f'<a href="?{base_qs}&offset={next_offset}" style="color:#4a9eff">Next →</a>' if has_next else ''

    # Category options
    cat_options = '<option value="">All Categories</option>'
    for c in sorted(categories):
        selected = 'selected' if c == category else ''
        cat_options += f'<option value="{html.escape(c)}" {selected}>{html.escape(c)}</option>'

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Ashbane Operations Dashboard</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
        <style>
            * {{ box-sizing: border-box; }}
            body {{
                font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #0f0f12 0%, #1a1a1f 100%);
                color: #e0e0e0;
                margin: 0;
                padding: 24px;
                min-height: 100vh;
            }}
            .dashboard-container {{
                max-width: 1400px;
                margin: 0 auto;
            }}

            /* Header */
            .dashboard-header {{
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 24px;
                padding-bottom: 20px;
                border-bottom: 1px solid rgba(255,255,255,0.1);
            }}
            .dashboard-title {{
                display: flex;
                align-items: center;
                gap: 16px;
            }}
            .dashboard-title h1 {{
                margin: 0;
                font-size: 28px;
                font-weight: 700;
                background: linear-gradient(135deg, #ff6a00 0%, #ff8533 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
            }}
            .dashboard-title .version {{
                background: rgba(255,106,0,0.15);
                color: #ff8533;
                padding: 4px 10px;
                border-radius: 6px;
                font-size: 11px;
                font-weight: 600;
            }}
            .itch-btn {{
                background: linear-gradient(135deg, #fa5c5c 0%, #e84545 100%);
                color: white;
                padding: 12px 24px;
                border-radius: 8px;
                font-weight: 600;
                text-decoration: none;
                display: flex;
                align-items: center;
                gap: 10px;
                box-shadow: 0 4px 12px rgba(250,92,92,0.3);
                transition: transform 0.2s, box-shadow 0.2s;
            }}
            .itch-btn:hover {{
                transform: translateY(-2px);
                box-shadow: 0 6px 20px rgba(250,92,92,0.4);
                text-decoration: none;
            }}

            /* Section Cards */
            .section-card {{
                background: rgba(30,30,35,0.8);
                border: 1px solid rgba(255,255,255,0.06);
                border-radius: 16px;
                padding: 20px 24px;
                margin-bottom: 16px;
                backdrop-filter: blur(10px);
            }}
            .section-header {{
                display: flex;
                align-items: center;
                gap: 12px;
                margin-bottom: 16px;
            }}
            .section-icon {{
                font-size: 20px;
            }}
            .section-title {{
                font-size: 15px;
                font-weight: 600;
                margin: 0;
            }}
            .section-badge {{
                padding: 3px 10px;
                border-radius: 6px;
                font-size: 10px;
                font-weight: 700;
                letter-spacing: 0.5px;
            }}
            .section-status {{
                font-size: 12px;
                display: flex;
                align-items: center;
                gap: 6px;
            }}
            .section-status .dot {{
                width: 6px;
                height: 6px;
                border-radius: 50%;
                display: inline-block;
            }}
            .section-actions {{
                margin-left: auto;
                display: flex;
                gap: 12px;
                align-items: center;
            }}
            .refresh-btn {{
                color: #666;
                cursor: pointer;
                font-size: 12px;
                padding: 6px 12px;
                border-radius: 6px;
                transition: background 0.2s;
            }}
            .refresh-btn:hover {{
                background: rgba(255,255,255,0.05);
                color: #888;
            }}

            /* Stats Grid */
            .stats-grid {{
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(100px, 1fr));
                gap: 16px;
            }}
            .stat-item {{
                display: flex;
                flex-direction: column;
                padding: 12px 16px;
                background: rgba(0,0,0,0.2);
                border-radius: 10px;
                transition: background 0.2s;
            }}
            .stat-item.clickable {{
                cursor: pointer;
            }}
            .stat-item.clickable:hover {{
                background: rgba(255,255,255,0.05);
            }}
            .stat-value {{
                font-size: 24px;
                font-weight: 700;
                color: #fff;
                line-height: 1.2;
            }}
            .stat-value.sm {{ font-size: 18px; }}
            .stat-value.error {{ color: #ef4444; }}
            .stat-value.warn {{ color: #f59e0b; }}
            .stat-value.success {{ color: #22c55e; }}
            .stat-value.info {{ color: #3b82f6; }}
            .stat-value.purple {{ color: #a855f7; }}
            .stat-value.muted {{ color: #666; }}
            .stat-label {{
                font-size: 11px;
                color: #666;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                margin-top: 4px;
                font-weight: 500;
            }}
            .stat-icon {{
                font-size: 16px;
                margin-right: 6px;
            }}

            /* Server Cards */
            .server-grid {{
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
                gap: 16px;
            }}
            .server-card {{
                background: rgba(0,0,0,0.3);
                border: 1px solid rgba(255,255,255,0.06);
                border-radius: 12px;
                padding: 16px 20px;
            }}
            .server-card.online {{
                border-left: 3px solid #22c55e;
            }}
            .server-card.offline {{
                border-left: 3px solid #ef4444;
            }}
            .server-header {{
                display: flex;
                align-items: center;
                gap: 10px;
                margin-bottom: 12px;
            }}
            .server-name {{
                font-weight: 600;
                font-size: 14px;
            }}
            .server-type {{
                padding: 2px 8px;
                border-radius: 4px;
                font-size: 10px;
                font-weight: 600;
            }}
            .server-uptime {{
                color: #666;
                font-size: 11px;
                margin-left: auto;
            }}
            .server-metrics {{
                display: flex;
                gap: 20px;
            }}
            .server-metric {{
                display: flex;
                flex-direction: column;
            }}
            .server-metric-value {{
                font-size: 16px;
                font-weight: 600;
            }}
            .server-metric-label {{
                font-size: 10px;
                color: #666;
                text-transform: uppercase;
            }}

            /* Color themes for sections */
            .section-card.client {{ border-top: 3px solid #3b82f6; }}
            .section-card.client .section-title {{ color: #60a5fa; }}
            .section-card.client .section-badge {{ background: #1e40af; color: #93c5fd; }}

            .section-card.server {{ border-top: 3px solid #8b5cf6; }}
            .section-card.server .section-title {{ color: #a78bfa; }}
            .section-card.server .section-badge {{ background: #5b21b6; color: #c4b5fd; }}

            .section-card.gameplay {{ border-top: 3px solid #22c55e; }}
            .section-card.gameplay .section-title {{ color: #4ade80; }}
            .section-card.gameplay .section-badge {{ background: #166534; color: #86efac; }}

            .section-card.backend {{ border-top: 3px solid #f59e0b; }}
            .section-card.backend .section-title {{ color: #fbbf24; }}
            .section-card.backend .section-badge {{ background: #92400e; color: #fcd34d; }}

            .section-card.forge {{ border-top: 3px solid #a855f7; }}
            .section-card.forge .section-title {{ color: #c084fc; }}
            .section-card.forge .section-badge {{ background: #6b21a8; color: #d8b4fe; }}

            .section-card.blockchain {{ border-top: 3px solid #06b6d4; }}
            .section-card.blockchain .section-title {{ color: #22d3ee; }}
            .section-card.blockchain .section-badge {{ background: #155e75; color: #67e8f9; }}

            .section-card.logs {{ border-top: 3px solid #64748b; }}
            .section-card.logs .section-title {{ color: #94a3b8; }}

            /* Alert button */
            .alert-btn {{
                background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
                color: white;
                border: none;
                padding: 10px 18px;
                border-radius: 8px;
                cursor: pointer;
                font-weight: 600;
                font-size: 13px;
                display: flex;
                align-items: center;
                gap: 8px;
                box-shadow: 0 2px 8px rgba(239,68,68,0.3);
                transition: transform 0.2s;
            }}
            .alert-btn:hover {{
                transform: translateY(-1px);
            }}

            /* Filters */
            .filters {{
                background: rgba(0,0,0,0.2);
                padding: 16px;
                border-radius: 10px;
                margin-bottom: 16px;
                display: flex;
                gap: 12px;
                align-items: center;
                flex-wrap: wrap;
            }}
            .filters select, .filters input {{
                background: rgba(0,0,0,0.3);
                border: 1px solid rgba(255,255,255,0.1);
                color: #e0e0e0;
                padding: 10px 14px;
                border-radius: 8px;
                font-size: 13px;
            }}
            .filters select:focus, .filters input:focus {{
                outline: none;
                border-color: #ff6a00;
            }}
            .filters button {{
                background: linear-gradient(135deg, #ff6a00 0%, #ff8533 100%);
                color: white;
                border: none;
                padding: 10px 24px;
                border-radius: 8px;
                cursor: pointer;
                font-weight: 600;
                font-size: 13px;
            }}
            .filters button:hover {{ opacity: 0.9; }}

            /* Table */
            table {{
                width: 100%;
                border-collapse: collapse;
                font-size: 13px;
            }}
            th {{
                text-align: left;
                padding: 12px 10px;
                background: rgba(0,0,0,0.3);
                color: #ff8533;
                font-weight: 600;
                font-size: 11px;
                text-transform: uppercase;
                letter-spacing: 0.5px;
                position: sticky;
                top: 0;
            }}
            td {{
                padding: 10px;
                border-bottom: 1px solid rgba(255,255,255,0.05);
                vertical-align: top;
            }}
            tr:hover {{ background: rgba(255,255,255,0.02); }}
            .pagination {{
                margin-top: 16px;
                padding: 16px;
                background: rgba(0,0,0,0.2);
                border-radius: 10px;
            }}
            a {{ color: #60a5fa; text-decoration: none; }}
            a:hover {{ text-decoration: underline; }}

            /* Two-column layout for top sections */
            .grid-2col {{
                display: grid;
                grid-template-columns: repeat(2, 1fr);
                gap: 16px;
            }}
            @media (max-width: 900px) {{
                .grid-2col {{ grid-template-columns: 1fr; }}
            }}
        </style>
    </head>
    <body>
        <div class="dashboard-container">

        <!-- Header -->
        <div class="dashboard-header">
            <div class="dashboard-title">
                <h1>Ashbane Operations</h1>
                <span class="version">ALPHA</span>
            </div>
            <a href="https://ashbanepvp.itch.io/ashbane" target="_blank" class="itch-btn">
                <span style="font-size:18px;">🎮</span> Download on itch.io
            </a>
        </div>

        <!-- Row 1: Client Telemetry + Server Infrastructure -->
        <div class="grid-2col">

        <!-- Section: Client Telemetry -->
        <div class="section-card client">
            <div class="section-header">
                <span class="section-icon">📊</span>
                <h2 class="section-title">Client Telemetry</h2>
                <span class="section-badge">GODOT</span>
                <span class="section-status"><span class="dot" style="background:#22c55e;"></span> Receiving</span>
                <div class="section-actions">
                    <button class="alert-btn" onclick="openSuspiciousModal()">🚨 Suspicious IPs</button>
                </div>
            </div>
            <div class="stats-grid" style="grid-template-columns: repeat(4, 1fr);">
                <div class="stat-item">
                    <span class="stat-value">{total_logs_all:,}</span>
                    <span class="stat-label">Total Logs</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value info">{logs_24h:,}</span>
                    <span class="stat-label">Last 24h</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value {'error' if errors_24h > 0 else 'muted'}">{errors_24h}</span>
                    <span class="stat-label">Errors</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value {'warn' if warns_24h > 0 else 'muted'}">{warns_24h}</span>
                    <span class="stat-label">Warnings</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value sm">{unique_sessions_24h}</span>
                    <span class="stat-label">Sessions</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value sm">{unique_users_24h}</span>
                    <span class="stat-label">Users</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value sm">{db_size_str}</span>
                    <span class="stat-label">Database</span>
                </div>
                <div class="stat-item">
                    <span class="stat-value sm">{disk_str}</span>
                    <span class="stat-label">Disk</span>
                </div>
            </div>
        </div>

        <!-- Section: Server Infrastructure -->
        <div class="section-card server" id="server-stats-section">
            <div class="section-header">
                <span class="section-icon">🖥️</span>
                <h2 class="section-title">Infrastructure</h2>
                <span class="section-badge">AGENTS</span>
                <span class="section-status" id="server-status"><span class="dot" style="background:#666;"></span> Loading...</span>
                <div class="section-actions">
                    <span class="refresh-btn" onclick="loadServerStats()">🔄 Refresh</span>
                </div>
            </div>
            <div id="server-stats-container" class="server-grid">
                <div style="color:#666;padding:20px;">Loading...</div>
            </div>
        </div>

        </div>

        <!-- Row 2: Gameplay + Backend Operations -->
        <div class="grid-2col">

        <!-- Section: Gameplay Telemetry -->
        <div class="section-card gameplay" id="gameplay-telemetry-section">
            <div class="section-header">
                <span class="section-icon">⚔️</span>
                <h2 class="section-title">Gameplay Telemetry</h2>
                <span class="section-badge">ANTI-CHEAT</span>
                <span class="section-status" id="gameplay-status"><span class="dot" style="background:#666;"></span> Loading...</span>
                <div class="section-actions">
                    <span class="refresh-btn" onclick="loadGameplayStats()">🔄 Refresh</span>
                </div>
            </div>
            <div id="gameplay-stats-container" class="stats-grid">
                <div style="color:#666;padding:10px;">Loading...</div>
            </div>
        </div>

        <!-- Section: Backend Operations -->
        <div class="section-card backend" id="backend-ops-section">
            <div class="section-header">
                <span class="section-icon">💰</span>
                <h2 class="section-title">Economy / Vendor</h2>
                <span class="section-badge">BACKEND</span>
                <span class="section-status" id="backend-ops-status"><span class="dot" style="background:#666;"></span> Loading...</span>
            </div>
            <div id="backend-ops-container" class="stats-grid">
                <div style="color:#666;padding:10px;">Loading...</div>
            </div>
        </div>

        </div>

        <!-- Row 3: Forge Economy + Blockchain -->
        <div class="grid-2col">

        <!-- Section: Forge Economy -->
        <div class="section-card forge" id="forge-economy-section">
            <div class="section-header">
                <span class="section-icon">⚒️</span>
                <h2 class="section-title">Forge Economy</h2>
                <span class="section-badge">NFT</span>
                <span class="section-status" id="forge-economy-status"><span class="dot" style="background:#666;"></span> Loading...</span>
                <div class="section-actions">
                    <span class="refresh-btn" onclick="loadForgeEconomy()">🔄 Refresh</span>
                </div>
            </div>
            <div id="forge-economy-container" class="stats-grid">
                <div style="color:#666;padding:10px;">Loading...</div>
            </div>
            <div id="forge-alerts-container" style="margin-top:12px;display:none;"></div>
        </div>

        <!-- Section: Blockchain -->
        <div class="section-card blockchain" id="blockchain-section">
            <div class="section-header">
                <span class="section-icon">⛓️</span>
                <h2 class="section-title">Blockchain</h2>
                <span class="section-badge">POLYGON</span>
                <span class="section-status" id="blockchain-status"><span class="dot" style="background:#666;"></span> Loading...</span>
                <div class="section-actions">
                    <span class="refresh-btn" onclick="loadBlockchainStatus()">🔄 Refresh</span>
                </div>
            </div>
            <div id="blockchain-container" class="stats-grid">
                <div style="color:#666;padding:10px;">Loading...</div>
            </div>
            <div id="bridge-activity-container" style="margin-top:12px;display:none;"></div>
        </div>

        </div>

        <!-- Section: Client Logs -->
        <div class="section-card logs">
            <div class="section-header">
                <span class="section-icon">📋</span>
                <h2 class="section-title">Client Logs</h2>
                <span style="color:#666;font-size:12px;margin-left:8px;">Showing {len(logs)} of {total} logs</span>
            </div>

        <form class="filters" method="get">
            <select name="category">{cat_options}</select>
            <select name="min_level">
                <option value="0" {'selected' if level==0 else ''}>All Levels</option>
                <option value="1" {'selected' if level==1 else ''}>INFO+</option>
                <option value="2" {'selected' if level==2 else ''}>WARN+</option>
                <option value="3" {'selected' if level==3 else ''}>ERROR only</option>
            </select>
            <input type="text" name="session_id" placeholder="Session ID" value="{session_id or ''}" style="width:200px">
            <input type="number" name="limit" value="{limit}" style="width:80px" min="1" max="1000">
            <button type="submit">Filter</button>
            <a href="/api/logs/view" style="color:#888;margin-left:10px">Reset</a>
        </form>

        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Time</th>
                    <th>Level</th>
                    <th>Session</th>
                    <th>Category</th>
                    <th>Message</th>
                    <th>Platform</th>
                    <th>Version</th>
                </tr>
            </thead>
            <tbody>
                {''.join(rows)}
            </tbody>
        </table>

        <div class="pagination">
            {prev_link}
            Page {(offset // limit) + 1} of {(total // limit) + 1}
            {next_link}
        </div>

        </div><!-- /section-card logs -->
        </div><!-- /dashboard-container -->

        <!-- Suspicious IPs Modal -->
        <div id="suspiciousModal" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.8);z-index:1000;overflow-y:auto;">
            <div style="max-width:900px;margin:40px auto;background:#1a1a1d;border-radius:12px;border:1px solid #333;">
                <div style="padding:20px;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center;">
                    <h2 style="margin:0;color:#ff6a00;">🚨 Suspicious IPs</h2>
                    <button onclick="closeSuspiciousModal()" style="background:none;border:none;color:#888;font-size:24px;cursor:pointer;">×</button>
                </div>
                <div id="suspiciousContent" style="padding:20px;">Loading...</div>
            </div>
        </div>

        <script>
        function openSuspiciousModal() {{
            document.getElementById('suspiciousModal').style.display = 'block';
            fetch('/api/logs/suspicious-ips')
                .then(r => r.json())
                .then(data => {{
                    let html = '<table style="width:100%;font-size:13px;"><thead><tr>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">IP Address</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">Type</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">Threat</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">Hits</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">First Seen</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">Last Seen</th>' +
                        '<th style="text-align:left;padding:8px;color:#ff6a00;">Paths</th>' +
                        '</tr></thead><tbody>';
                    if (data.ips && data.ips.length > 0) {{
                        data.ips.forEach(ip => {{
                            const threatColor = ip.threat_level === 'high' ? '#ff4444' : ip.threat_level === 'medium' ? '#f5a623' : '#888';
                            const paths = (ip.paths_hit || []).slice(0, 3).join(', ') + (ip.paths_hit && ip.paths_hit.length > 3 ? '...' : '');
                            html += '<tr style="border-bottom:1px solid #333;">' +
                                '<td style="padding:8px;font-family:monospace;">' + ip.ip_address + '</td>' +
                                '<td style="padding:8px;">' + ip.detection_type + '</td>' +
                                '<td style="padding:8px;color:' + threatColor + ';font-weight:bold;">' + ip.threat_level.toUpperCase() + '</td>' +
                                '<td style="padding:8px;">' + ip.hit_count + '</td>' +
                                '<td style="padding:8px;color:#666;">' + new Date(ip.first_seen).toLocaleString() + '</td>' +
                                '<td style="padding:8px;color:#666;">' + new Date(ip.last_seen).toLocaleString() + '</td>' +
                                '<td style="padding:8px;font-size:11px;color:#888;max-width:200px;overflow:hidden;text-overflow:ellipsis;">' + paths + '</td>' +
                                '</tr>';
                        }});
                    }} else {{
                        html += '<tr><td colspan="7" style="padding:20px;text-align:center;color:#666;">No suspicious IPs detected yet</td></tr>';
                    }}
                    html += '</tbody></table>';
                    html += '<div style="margin-top:15px;padding-top:15px;border-top:1px solid #333;color:#666;font-size:12px;">' +
                        'Total: ' + (data.stats?.total_suspicious_ips || 0) + ' suspicious IPs | ' +
                        'High threat: ' + (data.stats?.high_threat_count || 0) + '</div>';
                    document.getElementById('suspiciousContent').innerHTML = html;
                }})
                .catch(e => {{
                    document.getElementById('suspiciousContent').innerHTML = '<p style="color:#ff4444;">Error loading data: ' + e + '</p>';
                }});
        }}
        function closeSuspiciousModal() {{
            document.getElementById('suspiciousModal').style.display = 'none';
        }}
        document.getElementById('suspiciousModal').addEventListener('click', function(e) {{
            if (e.target === this) closeSuspiciousModal();
        }});

        // Server Infrastructure Stats
        function loadServerStats() {{
            document.getElementById('server-stats-container').innerHTML = '<div style="color:#666;padding:20px;">Loading...</div>';
            fetch('/api/server-stats/servers')
                .then(r => r.json())
                .then(servers => {{
                    let html = '';
                    servers.forEach(server => {{
                        const statusColor = server.status === 'online' ? '#22c55e' : server.status === 'stale' ? '#f59e0b' : '#ef4444';
                        const cpuColor = server.cpu_percent > 80 ? '#ef4444' : server.cpu_percent > 60 ? '#f59e0b' : '#22c55e';
                        const memColor = server.memory_percent > 80 ? '#ef4444' : server.memory_percent > 60 ? '#f59e0b' : '#22c55e';
                        const diskColor = server.disk_percent > 80 ? '#ef4444' : server.disk_percent > 60 ? '#f59e0b' : '#22c55e';
                        const statusClass = server.status === 'online' ? 'online' : 'offline';

                        const isGameServer = server.server_type === 'gameserver';
                        const typeIcon = isGameServer ? '🎮' : '🖥️';
                        const typeBadge = isGameServer ?
                            '<span class="server-type" style="background:#5b21b6;color:#c4b5fd;">GAME</span>' :
                            '<span class="server-type" style="background:#1e40af;color:#93c5fd;">API</span>';

                        const uptimeStr = formatUptime(server.uptime_seconds);
                        const playerInfo = server.players_online !== null ?
                            `<div style="margin-top:12px;padding-top:12px;border-top:1px solid rgba(255,255,255,0.06);">
                                <span style="color:#3b82f6;font-weight:700;font-size:20px;">${{server.players_online}}</span>
                                <span style="color:#666;font-size:12px;">/ ${{server.players_max || '?'}} players</span>
                            </div>` : '';

                        const instancesInfo = (isGameServer && server.game_instances_count > 0) ?
                            `<div style="margin-top:12px;padding-top:12px;border-top:1px solid rgba(255,255,255,0.06);">
                                <span style="color:#a855f7;font-weight:600;font-size:14px;">🎮 ${{server.game_instances_count}}</span>
                                <span style="color:#666;font-size:11px;"> instance${{server.game_instances_count > 1 ? 's' : ''}} running</span>
                            </div>` : '';

                        html += `
                            <div class="server-card ${{statusClass}}" onclick="openServerDetail('${{server.server_id}}')" style="cursor:pointer;">
                                <div class="server-header">
                                    <span style="font-size:16px;">${{typeIcon}}</span>
                                    <span class="server-name">${{server.server_id}}</span>
                                    ${{typeBadge}}
                                    <span class="server-uptime">Up ${{uptimeStr}}</span>
                                </div>
                                <div class="server-metrics">
                                    <div class="server-metric">
                                        <span class="server-metric-value" style="color:${{cpuColor}};">${{server.cpu_percent.toFixed(0)}}%</span>
                                        <span class="server-metric-label">CPU</span>
                                    </div>
                                    <div class="server-metric">
                                        <span class="server-metric-value" style="color:${{memColor}};">${{server.memory_percent.toFixed(0)}}%</span>
                                        <span class="server-metric-label">MEM</span>
                                    </div>
                                    <div class="server-metric">
                                        <span class="server-metric-value" style="color:${{diskColor}};">${{server.disk_percent.toFixed(0)}}%</span>
                                        <span class="server-metric-label">DISK</span>
                                    </div>
                                </div>
                                ${{playerInfo}}
                                ${{instancesInfo}}
                            </div>
                        `;
                    }});

                    if (servers.length === 0) {{
                        html = '<div style="color:#666;padding:20px;text-align:center;">No servers reporting</div>';
                        document.getElementById('server-status').innerHTML = '<span class="dot" style="background:#666;"></span> No agents';
                    }} else {{
                        const onlineCount = servers.filter(s => s.status === 'online').length;
                        const offlineCount = servers.filter(s => s.status === 'offline').length;
                        const staleCount = servers.filter(s => s.status === 'stale').length;

                        if (offlineCount > 0) {{
                            document.getElementById('server-status').innerHTML = `<span class="dot" style="background:#ef4444;"></span> ${{offlineCount}} offline`;
                        }} else if (staleCount > 0) {{
                            document.getElementById('server-status').innerHTML = `<span class="dot" style="background:#f59e0b;"></span> ${{staleCount}} stale`;
                        }} else {{
                            document.getElementById('server-status').innerHTML = `<span class="dot" style="background:#22c55e;"></span> ${{onlineCount}} online`;
                        }}
                    }}

                    document.getElementById('server-stats-container').innerHTML = html;
                }})
                .catch(e => {{
                    document.getElementById('server-stats-container').innerHTML = '<div style="color:#ef4444;padding:20px;">Error loading</div>';
                    document.getElementById('server-status').innerHTML = '<span class="dot" style="background:#ef4444;"></span> Error';
                }});
        }}

        function formatUptime(seconds) {{
            if (!seconds) return 'N/A';
            const days = Math.floor(seconds / 86400);
            const hours = Math.floor((seconds % 86400) / 3600);
            const mins = Math.floor((seconds % 3600) / 60);
            if (days > 0) return days + 'd ' + hours + 'h';
            if (hours > 0) return hours + 'h ' + mins + 'm';
            return mins + 'm';
        }}

        // Server Detail Modal
        function openServerDetail(serverId) {{
            const modal = document.getElementById('serverDetailModal');
            const content = document.getElementById('serverDetailContent');
            modal.style.display = 'block';
            content.innerHTML = '<div style="padding:20px;color:#666;">Loading...</div>';

            fetch('/api/server-stats/servers/' + serverId)
                .then(r => r.json())
                .then(data => {{
                    let html = `
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">
                            <div>
                                <h3 style="color:#ff6a00;margin-bottom:10px;">System</h3>
                                <div style="background:#1a1a1d;padding:10px;border-radius:6px;">
                                    <div style="margin-bottom:8px;"><span style="color:#666;">Hostname:</span> <span style="color:#fff;">${{data.hostname || 'N/A'}}</span></div>
                                    <div style="margin-bottom:8px;"><span style="color:#666;">CPU:</span> <span style="color:#fff;">${{data.cpu_percent?.toFixed(1) || 0}}% (${{data.cpu_count || '?'}} cores)</span></div>
                                    <div style="margin-bottom:8px;"><span style="color:#666;">Load:</span> <span style="color:#fff;">${{data.load_avg_1m?.toFixed(2) || 'N/A'}} / ${{data.load_avg_5m?.toFixed(2) || 'N/A'}} / ${{data.load_avg_15m?.toFixed(2) || 'N/A'}}</span></div>
                                    <div style="margin-bottom:8px;"><span style="color:#666;">Memory:</span> <span style="color:#fff;">${{(data.memory_used_mb/1024).toFixed(1) || 0}} / ${{(data.memory_total_mb/1024).toFixed(1) || 0}} GB (${{data.memory_percent?.toFixed(0) || 0}}%)</span></div>
                                    <div><span style="color:#666;">Uptime:</span> <span style="color:#fff;">${{formatUptime(data.uptime_seconds)}}</span></div>
                                </div>
                            </div>
                            <div>
                                <h3 style="color:#ff6a00;margin-bottom:10px;">Disks</h3>
                                <div style="background:#1a1a1d;padding:10px;border-radius:6px;">
                                    ${{(data.disks || []).map(d => `
                                        <div style="margin-bottom:8px;">
                                            <span style="color:#666;">${{d.mount}}:</span>
                                            <span style="color:#fff;">${{d.used_gb?.toFixed(1) || 0}} / ${{d.total_gb?.toFixed(0) || 0}} GB (${{d.percent?.toFixed(0) || 0}}%)</span>
                                        </div>
                                    `).join('') || '<div style="color:#666;">No disk info</div>'}}
                                </div>
                            </div>
                        </div>

                        <h3 style="color:#ff6a00;margin:20px 0 10px 0;">Listening Ports</h3>
                        <div style="background:#1a1a1d;padding:10px;border-radius:6px;max-height:150px;overflow-y:auto;">
                            <table style="width:100%;font-size:12px;">
                                <tr style="color:#666;"><th style="text-align:left;padding:4px;">Port</th><th style="text-align:left;padding:4px;">Process</th><th style="text-align:left;padding:4px;">PID</th></tr>
                                ${{(data.connections || []).filter(c => c.status === 'LISTEN').map(c => `
                                    <tr><td style="padding:4px;color:#4a9eff;">${{c.local_port}}</td><td style="padding:4px;color:#fff;">${{c.process_name || '-'}}</td><td style="padding:4px;color:#666;">${{c.pid || '-'}}</td></tr>
                                `).join('') || '<tr><td colspan="3" style="color:#666;padding:4px;">No listening ports</td></tr>'}}
                            </table>
                        </div>

                        <h3 style="color:#ff6a00;margin:20px 0 10px 0;">Top Processes</h3>
                        <div style="background:#1a1a1d;padding:10px;border-radius:6px;max-height:200px;overflow-y:auto;">
                            <table style="width:100%;font-size:12px;">
                                <tr style="color:#666;"><th style="text-align:left;padding:4px;">Process</th><th style="text-align:right;padding:4px;">CPU%</th><th style="text-align:right;padding:4px;">MEM MB</th><th style="text-align:left;padding:4px;">Ports</th></tr>
                                ${{(data.processes || []).slice(0, 10).map(p => `
                                    <tr>
                                        <td style="padding:4px;color:#fff;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${{p.cmdline || p.name}}">${{p.name}}</td>
                                        <td style="padding:4px;color:${{p.cpu_percent > 50 ? '#ff4444' : '#4ade80'}};text-align:right;">${{p.cpu_percent?.toFixed(1) || 0}}</td>
                                        <td style="padding:4px;text-align:right;color:#fff;">${{p.memory_mb?.toFixed(0) || 0}}</td>
                                        <td style="padding:4px;color:#4a9eff;font-size:11px;">${{(p.ports || []).join(', ') || '-'}}</td>
                                    </tr>
                                `).join('') || '<tr><td colspan="4" style="color:#666;padding:4px;">No process info</td></tr>'}}
                            </table>
                        </div>

                        ${{(data.game_instances && data.game_instances.length > 0) ? `
                            <h3 style="color:#7c3aed;margin:20px 0 10px 0;">🎮 Game Server Instances</h3>
                            <div style="display:grid;grid-template-columns:repeat(auto-fill, minmax(250px, 1fr));gap:10px;">
                                ${{data.game_instances.map(inst => `
                                    <div style="background:#1a1a1d;padding:12px;border-radius:6px;border-left:3px solid #7c3aed;">
                                        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                                            <span style="color:#fff;font-weight:bold;">${{inst.shard_id || inst.name}}</span>
                                            <span style="color:#666;font-size:11px;">PID ${{inst.pid}}</span>
                                        </div>
                                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;font-size:12px;">
                                            <div>
                                                <div style="color:#4ade80;font-weight:bold;">${{formatUptime(inst.uptime_seconds)}}</div>
                                                <div style="color:#666;font-size:10px;">UPTIME</div>
                                            </div>
                                            <div>
                                                <div style="color:#4a9eff;font-weight:bold;">${{inst.port || '-'}}</div>
                                                <div style="color:#666;font-size:10px;">PORT</div>
                                            </div>
                                            <div>
                                                <div style="color:${{inst.cpu_percent > 50 ? '#ff4444' : '#fff'}};">${{inst.cpu_percent?.toFixed(1) || 0}}%</div>
                                                <div style="color:#666;font-size:10px;">CPU</div>
                                            </div>
                                            <div>
                                                <div style="color:#fff;">${{inst.memory_mb?.toFixed(0) || 0}} MB</div>
                                                <div style="color:#666;font-size:10px;">MEM</div>
                                            </div>
                                        </div>
                                    </div>
                                `).join('')}}
                            </div>
                        ` : ''}}
                    `;
                    content.innerHTML = html;
                }})
                .catch(e => {{
                    content.innerHTML = '<div style="color:#ff4444;padding:20px;">Error: ' + e + '</div>';
                }});
        }}

        function closeServerDetail() {{
            document.getElementById('serverDetailModal').style.display = 'none';
        }}

        // Client Telemetry Stats
        function loadClientStats() {{
            fetch('/api/logs/stats?hours=24')
                .then(r => r.json())
                .then(data => {{
                    // Update stat values
                    const totalEl = document.getElementById('stat-total-logs');
                    const logs24hEl = document.getElementById('stat-logs-24h');
                    const errorsEl = document.getElementById('stat-errors-24h');
                    const warnsEl = document.getElementById('stat-warns-24h');
                    const sessionsEl = document.getElementById('stat-sessions-24h');
                    const usersEl = document.getElementById('stat-users-24h');

                    if (totalEl) totalEl.textContent = data.total_logs_all.toLocaleString();
                    if (logs24hEl) logs24hEl.textContent = data.total_logs.toLocaleString();
                    if (errorsEl) {{
                        errorsEl.textContent = data.by_level.error;
                        errorsEl.className = data.by_level.error > 0 ? 'stat-value error' : 'stat-value';
                    }}
                    if (warnsEl) {{
                        warnsEl.textContent = data.by_level.warn;
                        warnsEl.className = data.by_level.warn > 0 ? 'stat-value warn' : 'stat-value';
                    }}
                    if (sessionsEl) sessionsEl.textContent = data.unique_sessions;
                    if (usersEl) usersEl.textContent = data.unique_users;

                    // Update status indicator
                    const statusEl = document.getElementById('client-status');
                    if (statusEl) {{
                        if (data.by_level.error > 0) {{
                            statusEl.innerHTML = '● ' + data.by_level.error + ' errors';
                            statusEl.style.color = '#ff4444';
                        }} else if (data.total_logs > 0) {{
                            statusEl.innerHTML = '● Receiving';
                            statusEl.style.color = '#4ade80';
                        }} else {{
                            statusEl.innerHTML = '○ No recent logs';
                            statusEl.style.color = '#666';
                        }}
                    }}
                }})
                .catch(e => {{
                    console.error('Failed to load client stats:', e);
                    const statusEl = document.getElementById('client-status');
                    if (statusEl) {{
                        statusEl.innerHTML = '● Error';
                        statusEl.style.color = '#ff4444';
                    }}
                }});
        }}

        // Load stats on page load and refresh every 15s
        loadClientStats();
        setInterval(loadClientStats, 15000);

        // Load server stats on page load and refresh every 30s
        loadServerStats();
        setInterval(loadServerStats, 30000);

        // Gameplay Telemetry Stats
        function loadGameplayStats() {{
            document.getElementById('gameplay-stats-container').innerHTML = '<div style="color:#666;padding:10px;">Loading...</div>';
            fetch('/api/telemetry/stats?hours=24')
                .then(r => r.json())
                .then(data => {{
                    const suspiciousClass = data.suspicious.count > 0 ? 'error' : 'muted';
                    const duels = data.duels || {{}};
                    const duelErrorClass = duels.error > 0 ? 'error' : 'muted';

                    const html = `
                        <div class="stat-item">
                            <span class="stat-value success">${{data.total_events_all.toLocaleString()}}</span>
                            <span class="stat-label">Total Events</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value info">${{data.total_events.toLocaleString()}}</span>
                            <span class="stat-label">Last 24h</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value error">⚔️ ${{data.by_type.kills.toLocaleString()}}</span>
                            <span class="stat-label">PvE Kills</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value warn">💰 ${{data.totals.gold_looted.toLocaleString()}}</span>
                            <span class="stat-label">Gold Looted</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value info">✨ ${{data.totals.xp_granted.toLocaleString()}}</span>
                            <span class="stat-label">XP Granted</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value ${{suspiciousClass}}">🚨 ${{data.suspicious.count}}</span>
                            <span class="stat-label">Suspicious</span>
                        </div>
                        <div class="stat-item" style="border-left:2px solid #f59e0b;padding-left:14px;">
                            <span class="stat-value warn">🤺 ${{duels.initiated || 0}}</span>
                            <span class="stat-label">Duels Started</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value success">✓ ${{duels.completed || 0}}</span>
                            <span class="stat-label">Completed</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value ${{duels.forfeit > 0 ? 'warn' : 'muted'}}">🏳️ ${{duels.forfeit || 0}}</span>
                            <span class="stat-label">Forfeits</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-value ${{duelErrorClass}}">⚠️ ${{duels.error || 0}}</span>
                            <span class="stat-label">Errors</span>
                        </div>
                    `;
                    document.getElementById('gameplay-stats-container').innerHTML = html;

                    const statusEl = document.getElementById('gameplay-status');
                    if (data.suspicious.count > 0) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#ef4444;"></span> ' + data.suspicious.count + ' suspicious';
                    }} else if (data.total_events > 0) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#22c55e;"></span> Active';
                    }} else {{
                        statusEl.innerHTML = '<span class="dot" style="background:#666;"></span> No events';
                    }}

                    if (data.backend_ops) {{
                        const ops = data.backend_ops;
                        const totalOps = ops.purchases + ops.sells + ops.saves + ops.loads;
                        const backendHtml = `
                            <div class="stat-item">
                                <span class="stat-value warn">🛒 ${{ops.purchases}}</span>
                                <span class="stat-label">Purchases</span>
                            </div>
                            <div class="stat-item">
                                <span class="stat-value success">💸 ${{ops.sells}}</span>
                                <span class="stat-label">Sales</span>
                            </div>
                            <div class="stat-item">
                                <span class="stat-value error sm">-${{ops.gold_spent.toLocaleString()}}</span>
                                <span class="stat-label">Gold Spent</span>
                            </div>
                            <div class="stat-item">
                                <span class="stat-value success sm">+${{ops.gold_earned.toLocaleString()}}</span>
                                <span class="stat-label">Gold Earned</span>
                            </div>
                            <div class="stat-item">
                                <span class="stat-value info">💾 ${{ops.saves}}</span>
                                <span class="stat-label">Saves</span>
                            </div>
                            <div class="stat-item">
                                <span class="stat-value purple">📂 ${{ops.loads}}</span>
                                <span class="stat-label">Loads</span>
                            </div>
                        `;
                        document.getElementById('backend-ops-container').innerHTML = backendHtml;

                        const backendStatus = document.getElementById('backend-ops-status');
                        if (totalOps > 0) {{
                            backendStatus.innerHTML = '<span class="dot" style="background:#22c55e;"></span> ' + totalOps + ' ops';
                        }} else {{
                            backendStatus.innerHTML = '<span class="dot" style="background:#666;"></span> No ops';
                        }}
                    }}
                }})
                .catch(e => {{
                    document.getElementById('gameplay-stats-container').innerHTML = '<div style="color:#666;padding:20px;text-align:center;">Awaiting data</div>';
                    document.getElementById('gameplay-status').innerHTML = '<span class="dot" style="background:#666;"></span> Pending';
                    document.getElementById('backend-ops-container').innerHTML = '<div style="color:#666;padding:20px;text-align:center;">No data</div>';
                    document.getElementById('backend-ops-status').innerHTML = '<span class="dot" style="background:#666;"></span> Pending';
                }});
        }}

        // Load gameplay stats on page load and refresh every 30s
        loadGameplayStats();
        setInterval(loadGameplayStats, 30000);

        // Forge Economy Stats
        function loadForgeEconomy() {{
            document.getElementById('forge-economy-container').innerHTML = '<div style="color:#666;padding:10px;">Loading...</div>';
            fetch('/api/telemetry/economy?hours=24')
                .then(r => r.json())
                .then(data => {{
                    const c = data.circulation;
                    const t = data.trading;
                    const f = data.forge_credits;
                    const a = data.alerts;

                    const alertCount = a.large_trades_10k + a.very_large_trades_50k + a.high_frequency_traders;
                    const alertClass = alertCount > 0 ? 'error' : 'muted';

                    const html = `
                        <div class="stat-item clickable" onclick="showEconomyModal('circulation')" title="Click for details">
                            <span class="stat-value purple">🔮 ${{c.total_forged}}</span>
                            <span class="stat-label">Total Forged</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('circulation')" title="Click for details">
                            <span class="stat-value success">🎮 ${{c.in_game}}</span>
                            <span class="stat-label">In-Game</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('circulation')" title="Click for details">
                            <span class="stat-value info">🌉 ${{c.bridged_out}}</span>
                            <span class="stat-label">Bridged Out</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('circulation')" title="Click for details">
                            <span class="stat-value ${{c.destroyed > 0 ? 'error' : 'muted'}}">💀 ${{c.destroyed}}</span>
                            <span class="stat-label">Destroyed</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('trading')" title="Click for details">
                            <span class="stat-value warn">🔄 ${{t.total_trades}}</span>
                            <span class="stat-label">Trades (24h)</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('trading')" title="Click for details">
                            <span class="stat-value warn sm">💰 ${{t.gold_volume.toLocaleString()}}</span>
                            <span class="stat-label">Gold Volume</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('credits')" title="Click for details">
                            <span class="stat-value info">🎫 ${{f.credits_available}}</span>
                            <span class="stat-label">Credits</span>
                        </div>
                        <div class="stat-item clickable" onclick="showEconomyModal('alerts')" title="Click for details">
                            <span class="stat-value ${{alertClass}}">🚨 ${{alertCount}}</span>
                            <span class="stat-label">Alerts</span>
                        </div>
                    `;
                    document.getElementById('forge-economy-container').innerHTML = html;

                    const alertsDiv = document.getElementById('forge-alerts-container');
                    if (alertCount > 0) {{
                        let alertHtml = '<div style="background:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.3);border-radius:10px;padding:12px;">';
                        alertHtml += '<div style="color:#ef4444;font-weight:600;margin-bottom:8px;font-size:13px;">⚠️ Economy Alerts (24h)</div>';
                        if (a.very_large_trades_50k > 0) {{
                            alertHtml += `<div style="color:#fca5a5;font-size:12px;margin-bottom:4px;">• ${{a.very_large_trades_50k}} trades over 50k gold</div>`;
                        }}
                        if (a.large_trades_10k > 0) {{
                            alertHtml += `<div style="color:#fcd34d;font-size:12px;margin-bottom:4px;">• ${{a.large_trades_10k}} trades over 10k gold</div>`;
                        }}
                        if (a.high_frequency_traders > 0) {{
                            alertHtml += `<div style="color:#fcd34d;font-size:12px;">• ${{a.high_frequency_traders}} high-frequency traders</div>`;
                        }}
                        alertHtml += '</div>';
                        alertsDiv.innerHTML = alertHtml;
                        alertsDiv.style.display = 'block';
                    }} else {{
                        alertsDiv.style.display = 'none';
                    }}

                    const statusEl = document.getElementById('forge-economy-status');
                    if (alertCount > 0) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#ef4444;"></span> ' + alertCount + ' alerts';
                    }} else if (c.total_forged > 0) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#22c55e;"></span> ' + c.total_forged + ' items';
                    }} else {{
                        statusEl.innerHTML = '<span class="dot" style="background:#666;"></span> No items';
                    }}
                }})
                .catch(e => {{
                    document.getElementById('forge-economy-container').innerHTML = '<div style="color:#666;padding:20px;text-align:center;">Unavailable</div>';
                    document.getElementById('forge-economy-status').innerHTML = '<span class="dot" style="background:#666;"></span> Unavailable';
                }});
        }}

        // Load forge economy on page load and refresh every 60s
        loadForgeEconomy();
        setInterval(loadForgeEconomy, 60000);

        // Blockchain Status
        function loadBlockchainStatus() {{
            document.getElementById('blockchain-container').innerHTML = '<div style="color:#666;padding:10px;">Loading...</div>';
            fetch('/api/telemetry/blockchain')
                .then(r => r.json())
                .then(data => {{
                    const r = data.relayer;
                    const i = data.indexer;
                    const b = data.bridge_activity;

                    const relayerConnected = r.connected;
                    const indexerRunning = i.running;
                    const pendingTotal = b.pending.bridge_out + b.pending.bridge_in;

                    const html = `
                        <div class="stat-item clickable" onclick="showBlockchainModal('relayer')" title="Click for details">
                            <span class="stat-value sm ${{relayerConnected ? 'success' : 'error'}}">
                                ${{relayerConnected ? '✓ Online' : '✗ Offline'}}
                            </span>
                            <span class="stat-label">Relayer</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('relayer')" title="Click for details">
                            <span class="stat-value sm ${{r.balance_matic !== null ? 'success' : 'muted'}}">
                                ${{r.balance_matic !== null ? r.balance_matic.toFixed(4) : '—'}}
                            </span>
                            <span class="stat-label">MATIC</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('indexer')" title="Click for details">
                            <span class="stat-value sm ${{indexerRunning ? 'success' : 'warn'}}">
                                ${{indexerRunning ? '✓ Running' : '○ Stopped'}}
                            </span>
                            <span class="stat-label">Indexer</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('indexer')" title="Click for details">
                            <span class="stat-value sm muted">
                                ${{i.last_processed_block > 0 ? '#' + i.last_processed_block.toLocaleString() : '—'}}
                            </span>
                            <span class="stat-label">Block</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('bridge')" title="Click for details">
                            <span class="stat-value info">🌉 ${{b.items.bridged_out}}</span>
                            <span class="stat-label">Bridged</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('bridge')" title="Click for details">
                            <span class="stat-value ${{pendingTotal > 0 ? 'warn' : 'muted'}}">⏳ ${{pendingTotal}}</span>
                            <span class="stat-label">Pending</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('bridge')" title="Click for details">
                            <span class="stat-value info sm">↗ ${{b.totals.bridge_out_completed}}</span>
                            <span class="stat-label">Out</span>
                        </div>
                        <div class="stat-item clickable" onclick="showBlockchainModal('bridge')" title="Click for details">
                            <span class="stat-value success sm">↙ ${{b.totals.bridge_in_completed}}</span>
                            <span class="stat-label">In</span>
                        </div>
                    `;
                    document.getElementById('blockchain-container').innerHTML = html;

                    const statusEl = document.getElementById('blockchain-status');
                    if (!r.configured) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#666;"></span> Not Configured';
                    }} else if (relayerConnected && indexerRunning) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#22c55e;"></span> Online';
                    }} else if (relayerConnected || indexerRunning) {{
                        statusEl.innerHTML = '<span class="dot" style="background:#f59e0b;"></span> Partial';
                    }} else {{
                        statusEl.innerHTML = '<span class="dot" style="background:#ef4444;"></span> Offline';
                    }}

                    window._blockchainData = data;
                }})
                .catch(e => {{
                    document.getElementById('blockchain-container').innerHTML = '<div style="color:#666;padding:20px;text-align:center;">Unavailable</div>';
                    document.getElementById('blockchain-status').innerHTML = '<span class="dot" style="background:#666;"></span> Error';
                }});
        }}

        function showBlockchainModal(section) {{
            const data = window._blockchainData;
            if (!data) return;

            const modal = document.getElementById('economyDetailModal');
            const content = document.getElementById('economyDetailContent');
            const title = document.getElementById('economyModalTitle');

            const titles = {{
                relayer: '⛓️ Relayer Status',
                indexer: '📡 Transfer Indexer',
                bridge: '🌉 Bridge Activity'
            }};
            title.textContent = titles[section] || section;
            modal.style.display = 'block';

            let html = '';

            if (section === 'relayer') {{
                const r = data.relayer;
                const c = data.chain_config;
                html = `
                    <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;">
                        <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                            <h4 style="color:#3b82f6;margin:0 0 15px 0;">Connection</h4>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Status</span>
                                <span style="color:${{r.connected ? '#22c55e' : '#ef4444'}};">${{r.connected ? 'Connected' : 'Disconnected'}}</span>
                            </div>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Configured</span>
                                <span style="color:${{r.configured ? '#22c55e' : '#ef4444'}};">${{r.configured ? 'Yes' : 'No'}}</span>
                            </div>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Balance</span>
                                <span style="color:#fff;">${{r.balance_matic !== null ? r.balance_matic.toFixed(6) + ' MATIC' : 'Unknown'}}</span>
                            </div>
                        </div>
                        <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                            <h4 style="color:#3b82f6;margin:0 0 15px 0;">Configuration</h4>
                            <div style="padding:8px 0;border-bottom:1px solid #333;">
                                <div style="color:#888;font-size:11px;">Relayer Address</div>
                                <div style="color:#fff;font-family:monospace;font-size:12px;word-break:break-all;">${{r.address || 'Not set'}}</div>
                            </div>
                            <div style="padding:8px 0;border-bottom:1px solid #333;">
                                <div style="color:#888;font-size:11px;">Contract Address</div>
                                <div style="color:#fff;font-family:monospace;font-size:12px;word-break:break-all;">${{r.contract_address || 'Not set'}}</div>
                            </div>
                            <div style="padding:8px 0;">
                                <div style="color:#888;font-size:11px;">RPC URL</div>
                                <div style="color:#fff;font-family:monospace;font-size:12px;word-break:break-all;">${{c.rpc_url}}</div>
                            </div>
                        </div>
                    </div>
                    ${{!r.configured ? '<div style="background:#2e1a1a;border:1px solid #ef4444;border-radius:8px;padding:15px;margin-top:20px;color:#ef4444;">⚠️ Set POLYGON_RPC_URL, RELAYER_PRIVATE_KEY, and FORGED_ITEMS_CONTRACT env vars to enable blockchain</div>' : ''}}
                `;
            }} else if (section === 'indexer') {{
                const i = data.indexer;
                html = `
                    <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                        <h4 style="color:#3b82f6;margin:0 0 15px 0;">Transfer Indexer</h4>
                        <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                            <span style="color:#888;">Status</span>
                            <span style="color:${{i.running ? '#22c55e' : '#f59e0b'}};">${{i.running ? 'Running' : 'Stopped'}}</span>
                        </div>
                        <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                            <span style="color:#888;">Last Block Scanned</span>
                            <span style="color:#fff;">${{i.last_processed_block > 0 ? '#' + i.last_processed_block.toLocaleString() : 'Not started'}}</span>
                        </div>
                        <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                            <span style="color:#888;">Chain ID</span>
                            <span style="color:#fff;">${{i.chain_id || 'Not set'}}</span>
                        </div>
                        <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                            <span style="color:#888;">Poll Interval</span>
                            <span style="color:#fff;">${{i.poll_interval_seconds || 30}}s</span>
                        </div>
                        <div style="padding:8px 0;">
                            <div style="color:#888;font-size:11px;">Contract Address</div>
                            <div style="color:#fff;font-family:monospace;font-size:12px;word-break:break-all;">${{i.contract_address || 'Not set'}}</div>
                        </div>
                    </div>
                    <div style="background:#1a2e1a;padding:15px;border-radius:8px;margin-top:15px;color:#888;font-size:12px;">
                        The indexer watches for NFT Transfer events on-chain to detect external sales (OpenSea, etc.) and sync ownership back to the database.
                    </div>
                `;
            }} else if (section === 'bridge') {{
                const b = data.bridge_activity;
                html = `
                    <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px;">
                        <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                            <h4 style="color:#f59e0b;margin:0 0 15px 0;">Pending</h4>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Bridge Out</span>
                                <span style="color:${{b.pending.bridge_out > 0 ? '#f59e0b' : '#666'}};">${{b.pending.bridge_out}}</span>
                            </div>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;">
                                <span style="color:#888;">Bridge In</span>
                                <span style="color:${{b.pending.bridge_in > 0 ? '#f59e0b' : '#666'}};">${{b.pending.bridge_in}}</span>
                            </div>
                        </div>
                        <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                            <h4 style="color:#22c55e;margin:0 0 15px 0;">Completed (All Time)</h4>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Bridge Out</span>
                                <span style="color:#06b6d4;">${{b.totals.bridge_out_completed}}</span>
                            </div>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">Bridge In</span>
                                <span style="color:#22c55e;">${{b.totals.bridge_in_completed}}</span>
                            </div>
                            <div style="display:flex;justify-content:space-between;padding:8px 0;">
                                <span style="color:#888;">External Transfers</span>
                                <span style="color:#a855f7;">${{b.totals.external_transfers}}</span>
                            </div>
                        </div>
                    </div>
                    <h4 style="color:#fff;margin:0 0 10px 0;">Recent Transactions (24h)</h4>
                    ${{b.recent_transactions.length === 0 ? '<div style="color:#666;padding:20px;text-align:center;">No bridge transactions in the last 24 hours</div>' : `
                        <div style="max-height:200px;overflow-y:auto;">
                            <table style="width:100%;border-collapse:collapse;">
                                <thead>
                                    <tr style="background:#1f1f23;">
                                        <th style="padding:8px;text-align:left;color:#888;">Type</th>
                                        <th style="padding:8px;text-align:left;color:#888;">Status</th>
                                        <th style="padding:8px;text-align:left;color:#888;">Time</th>
                                        <th style="padding:8px;text-align:left;color:#888;">Tx Hash</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    ${{b.recent_transactions.map(tx => `
                                        <tr style="border-bottom:1px solid #333;">
                                            <td style="padding:8px;color:${{tx.type === 'bridge_out' ? '#06b6d4' : tx.type === 'bridge_in' ? '#22c55e' : '#a855f7'}};">${{tx.type}}</td>
                                            <td style="padding:8px;color:${{tx.status === 'completed' ? '#22c55e' : tx.status === 'pending' ? '#f59e0b' : '#ef4444'}};">${{tx.status}}</td>
                                            <td style="padding:8px;color:#888;">${{tx.requested_at ? new Date(tx.requested_at).toLocaleString() : '—'}}</td>
                                            <td style="padding:8px;color:#666;font-family:monospace;font-size:11px;">${{tx.tx_hash || '—'}}</td>
                                        </tr>
                                    `).join('')}}
                                </tbody>
                            </table>
                        </div>
                    `}}
                `;
            }}

            content.innerHTML = html;
        }}

        // Load blockchain status on page load and refresh every 60s
        loadBlockchainStatus();
        setInterval(loadBlockchainStatus, 60000);

        // Economy Detail Modals
        function showEconomyModal(section) {{
            const modal = document.getElementById('economyDetailModal');
            const content = document.getElementById('economyDetailContent');
            const title = document.getElementById('economyModalTitle');

            const titles = {{
                circulation: '🔮 Item Circulation',
                trading: '🔄 Trading Activity',
                credits: '🎫 Forge Credits',
                alerts: '🚨 Economy Alerts'
            }};
            title.textContent = titles[section] || section;
            content.innerHTML = '<div style="text-align:center;padding:40px;color:#666;">Loading...</div>';
            modal.style.display = 'block';

            fetch(`/api/telemetry/economy/details/${{section}}?hours=24`)
                .then(r => r.json())
                .then(data => {{
                    let html = '';

                    if (section === 'circulation') {{
                        html = renderCirculationDetail(data);
                    }} else if (section === 'trading') {{
                        html = renderTradingDetail(data);
                    }} else if (section === 'credits') {{
                        html = renderCreditsDetail(data);
                    }} else if (section === 'alerts') {{
                        html = renderAlertsDetail(data);
                    }}

                    content.innerHTML = html;
                }})
                .catch(e => {{
                    content.innerHTML = '<div style="color:#ef4444;padding:20px;">Failed to load details</div>';
                }});
        }}

        function closeEconomyModal() {{
            document.getElementById('economyDetailModal').style.display = 'none';
        }}

        function renderCirculationDetail(data) {{
            const s = data.summary;
            let html = `
                <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;margin-bottom:20px;">
                    <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                        <h4 style="color:#a855f7;margin:0 0 10px 0;">By Rarity</h4>
                        ${{Object.entries(s.by_rarity).map(([r, c]) => `
                            <div style="display:flex;justify-content:space-between;padding:4px 0;border-bottom:1px solid #333;">
                                <span style="color:${{getRarityColor(r)}};">${{r || 'Unknown'}}</span>
                                <span style="color:#fff;">${{c}}</span>
                            </div>
                        `).join('')}}
                    </div>
                    <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                        <h4 style="color:#3b82f6;margin:0 0 10px 0;">By Status</h4>
                        ${{Object.entries(s.by_status).map(([st, c]) => `
                            <div style="display:flex;justify-content:space-between;padding:4px 0;border-bottom:1px solid #333;">
                                <span style="color:#888;">${{st}}</span>
                                <span style="color:#fff;">${{c}}</span>
                            </div>
                        `).join('')}}
                        <div style="display:flex;justify-content:space-between;padding:4px 0;">
                            <span style="color:#ef4444;">Destroyed</span>
                            <span style="color:#fff;">${{s.destroyed}}</span>
                        </div>
                    </div>
                </div>
                <h4 style="color:#fff;margin:0 0 10px 0;">Recent Forged Items</h4>
                <div style="max-height:300px;overflow-y:auto;">
                    <table style="width:100%;border-collapse:collapse;">
                        <thead>
                            <tr style="background:#1f1f23;">
                                <th style="padding:8px;text-align:left;color:#888;">Token</th>
                                <th style="padding:8px;text-align:left;color:#888;">Item</th>
                                <th style="padding:8px;text-align:left;color:#888;">Rarity</th>
                                <th style="padding:8px;text-align:left;color:#888;">Status</th>
                                <th style="padding:8px;text-align:left;color:#888;">Trades</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${{data.items.map(i => `
                                <tr style="border-bottom:1px solid #333;">
                                    <td style="padding:8px;color:#666;">#${{i.token_id}}</td>
                                    <td style="padding:8px;color:#fff;">${{i.item_name || i.item_id}}</td>
                                    <td style="padding:8px;color:${{getRarityColor(i.item_rarity)}};">${{i.item_rarity || '-'}}</td>
                                    <td style="padding:8px;color:#888;">${{i.bridge_status}}</td>
                                    <td style="padding:8px;color:#888;">${{i.trade_count}}</td>
                                </tr>
                            `).join('')}}
                        </tbody>
                    </table>
                </div>
            `;
            return html;
        }}

        function renderTradingDetail(data) {{
            let html = '';

            if (data.top_traders.length > 0) {{
                html += `
                    <h4 style="color:#f59e0b;margin:0 0 10px 0;">Top Traders (24h)</h4>
                    <div style="background:#1f1f23;padding:15px;border-radius:8px;margin-bottom:20px;">
                        ${{data.top_traders.map((t, i) => `
                            <div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #333;">
                                <span><span style="color:#666;">#${{i+1}}</span> <span style="color:#fff;">${{t.username}}</span></span>
                                <span><span style="color:#eab308;">${{t.trade_count}} trades</span> · <span style="color:#f59e0b;">${{t.gold_volume.toLocaleString()}}g</span></span>
                            </div>
                        `).join('')}}
                    </div>
                `;
            }}

            html += `<h4 style="color:#fff;margin:0 0 10px 0;">Recent Trades</h4>`;

            if (data.recent_trades.length === 0) {{
                html += '<div style="color:#666;padding:20px;text-align:center;">No trades in the last 24 hours</div>';
            }} else {{
                html += `
                    <div style="max-height:300px;overflow-y:auto;">
                        <table style="width:100%;border-collapse:collapse;">
                            <thead>
                                <tr style="background:#1f1f23;">
                                    <th style="padding:8px;text-align:left;color:#888;">Time</th>
                                    <th style="padding:8px;text-align:left;color:#888;">Item</th>
                                    <th style="padding:8px;text-align:left;color:#888;">From</th>
                                    <th style="padding:8px;text-align:left;color:#888;">To</th>
                                    <th style="padding:8px;text-align:right;color:#888;">Price</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${{data.recent_trades.map(t => `
                                    <tr style="border-bottom:1px solid #333;">
                                        <td style="padding:8px;color:#666;">${{new Date(t.traded_at).toLocaleString()}}</td>
                                        <td style="padding:8px;color:${{getRarityColor(t.item_rarity)}};">${{t.item_name}}</td>
                                        <td style="padding:8px;color:#888;">${{t.from_user}}</td>
                                        <td style="padding:8px;color:#888;">${{t.to_user}}</td>
                                        <td style="padding:8px;text-align:right;color:${{t.is_gift ? '#22c55e' : '#eab308'}};">${{t.is_gift ? '🎁 Gift' : t.price_gold.toLocaleString() + 'g'}}</td>
                                    </tr>
                                `).join('')}}
                            </tbody>
                        </table>
                    </div>
                `;
            }}
            return html;
        }}

        function renderCreditsDetail(data) {{
            if (data.users.length === 0) {{
                return '<div style="color:#666;padding:40px;text-align:center;">No users with forge credits</div>';
            }}

            return `
                <div style="background:#1f1f23;padding:15px;border-radius:8px;margin-bottom:20px;">
                    <div style="color:#888;font-size:12px;margin-bottom:8px;">Achievement Mappings in items.json: <span style="color:#22c55e;">${{data.achievement_mappings_count || 0}}</span></div>
                    <div style="color:#888;font-size:12px;">Only achievements with mappings can be forged into items.</div>
                </div>
                <div style="max-height:350px;overflow-y:auto;">
                    <table style="width:100%;border-collapse:collapse;">
                        <thead>
                            <tr style="background:#1f1f23;">
                                <th style="padding:8px;text-align:left;color:#888;">User</th>
                                <th style="padding:8px;text-align:right;color:#888;">Useable</th>
                                <th style="padding:8px;text-align:right;color:#888;">Unmapped</th>
                                <th style="padding:8px;text-align:right;color:#888;">Forged</th>
                                <th style="padding:8px;text-align:right;color:#888;">Available</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${{data.users.map(u => `
                                <tr style="border-bottom:1px solid #333;">
                                    <td style="padding:8px;color:#fff;">${{u.username}}</td>
                                    <td style="padding:8px;text-align:right;color:#22c55e;">${{u.useable_credits}}</td>
                                    <td style="padding:8px;text-align:right;color:#666;">${{u.unmapped_credits.toLocaleString()}}</td>
                                    <td style="padding:8px;text-align:right;color:#a855f7;">${{u.items_forged}}</td>
                                    <td style="padding:8px;text-align:right;color:${{u.credits_available > 0 ? '#06b6d4' : '#666'}};">${{u.credits_available}}</td>
                                </tr>
                            `).join('')}}
                        </tbody>
                    </table>
                </div>
            `;
        }}

        function renderAlertsDetail(data) {{
            let html = '';

            if (data.large_trades.length > 0) {{
                html += `
                    <h4 style="color:#ef4444;margin:0 0 10px 0;">Large Trades (>10k gold)</h4>
                    <div style="max-height:200px;overflow-y:auto;margin-bottom:20px;">
                        <table style="width:100%;border-collapse:collapse;">
                            <thead>
                                <tr style="background:#1f1f23;">
                                    <th style="padding:8px;text-align:left;color:#888;">Time</th>
                                    <th style="padding:8px;text-align:left;color:#888;">Item</th>
                                    <th style="padding:8px;text-align:left;color:#888;">From → To</th>
                                    <th style="padding:8px;text-align:right;color:#888;">Amount</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${{data.large_trades.map(t => `
                                    <tr style="border-bottom:1px solid #333;background:${{t.severity === 'critical' ? 'rgba(239,68,68,0.1)' : 'transparent'}};">
                                        <td style="padding:8px;color:#666;">${{new Date(t.traded_at).toLocaleString()}}</td>
                                        <td style="padding:8px;color:#fff;">${{t.item_name}}</td>
                                        <td style="padding:8px;color:#888;">${{t.from_user}} → ${{t.to_user}}</td>
                                        <td style="padding:8px;text-align:right;color:${{t.severity === 'critical' ? '#ef4444' : '#f59e0b'}};">${{t.price_gold.toLocaleString()}}g ${{t.severity === 'critical' ? '⚠️' : ''}}</td>
                                    </tr>
                                `).join('')}}
                            </tbody>
                        </table>
                    </div>
                `;
            }} else {{
                html += '<div style="background:#1a2e1a;padding:15px;border-radius:8px;color:#22c55e;margin-bottom:20px;">✓ No large trades detected</div>';
            }}

            if (data.high_frequency_traders.length > 0) {{
                html += `
                    <h4 style="color:#f59e0b;margin:0 0 10px 0;">High Frequency Traders (>5 trades/24h)</h4>
                    <div style="background:#1f1f23;padding:15px;border-radius:8px;">
                        ${{data.high_frequency_traders.map(t => `
                            <div style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #333;">
                                <span style="color:#fff;">${{t.username}}</span>
                                <span style="color:#f59e0b;">${{t.trade_count}} trades</span>
                            </div>
                        `).join('')}}
                    </div>
                `;
            }} else {{
                html += '<div style="background:#1a2e1a;padding:15px;border-radius:8px;color:#22c55e;">✓ No high-frequency traders detected</div>';
            }}

            return html;
        }}

        function getRarityColor(rarity) {{
            const colors = {{
                'Common': '#9ca3af',
                'Uncommon': '#22c55e',
                'Rare': '#3b82f6',
                'Epic': '#a855f7',
                'Legendary': '#f59e0b'
            }};
            return colors[rarity] || '#666';
        }}
        </script>

        <!-- Economy Detail Modal -->
        <div id="economyDetailModal" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.85);z-index:1001;overflow-y:auto;">
            <div style="max-width:800px;margin:40px auto;background:#1a1a1d;border-radius:12px;border:1px solid #a855f7;">
                <div style="padding:20px;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center;">
                    <h2 id="economyModalTitle" style="margin:0;color:#a855f7;">Economy Details</h2>
                    <button onclick="closeEconomyModal()" style="background:none;border:none;color:#888;font-size:24px;cursor:pointer;">×</button>
                </div>
                <div id="economyDetailContent" style="padding:20px;"></div>
            </div>
        </div>

        <!-- Server Detail Modal -->
        <div id="serverDetailModal" style="display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.8);z-index:1000;overflow-y:auto;">
            <div style="max-width:800px;margin:40px auto;background:#1a1a1d;border-radius:12px;border:1px solid #333;">
                <div style="padding:20px;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center;">
                    <h2 style="margin:0;color:#ff6a00;">Server Details</h2>
                    <button onclick="closeServerDetail()" style="background:none;border:none;color:#888;font-size:24px;cursor:pointer;">×</button>
                </div>
                <div id="serverDetailContent" style="padding:20px;"></div>
            </div>
        </div>

        <style>
            .server-card {{ cursor: pointer; transition: transform 0.1s, box-shadow 0.1s; }}
            .server-card:hover {{ transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.3); }}
        </style>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)


@router.get("/suspicious-ips")
async def get_suspicious_ips(
    limit: int = Query(100, ge=1, le=500),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """Get list of suspicious IPs (Admin only)."""
    require_admin(current_user)

    ips = db.query(SuspiciousIP)\
        .order_by(desc(SuspiciousIP.last_seen))\
        .limit(limit)\
        .all()

    # Stats
    total = db.query(func.count(SuspiciousIP.id)).scalar() or 0
    high_threat = db.query(func.count(SuspiciousIP.id))\
        .filter(SuspiciousIP.threat_level == 'high').scalar() or 0

    return {
        "ips": [
            {
                "ip_address": ip.ip_address,
                "detection_type": ip.detection_type,
                "threat_level": ip.threat_level,
                "hit_count": ip.hit_count,
                "paths_hit": ip.paths_hit or [],
                "user_agents": ip.user_agents or [],
                "first_seen": ip.first_seen.isoformat() if ip.first_seen else None,
                "last_seen": ip.last_seen.isoformat() if ip.last_seen else None,
                "is_blocked": ip.is_blocked,
            }
            for ip in ips
        ],
        "stats": {
            "total_suspicious_ips": total,
            "high_threat_count": high_threat,
        }
    }
