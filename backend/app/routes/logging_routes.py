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
        <title>Ashbane Logs</title>
        <style>
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #1a1a1d;
                color: #e0e0e0;
                margin: 0;
                padding: 20px;
            }}
            h1 {{ color: #ff6a00; margin-bottom: 5px; }}
            .stats {{ color: #888; margin-bottom: 20px; }}
            .stats-bar {{
                display: flex;
                gap: 20px;
                background: #252528;
                padding: 15px 20px;
                border-radius: 8px;
                margin-bottom: 20px;
                flex-wrap: wrap;
            }}
            .stat-item {{
                display: flex;
                flex-direction: column;
            }}
            .stat-value {{
                font-size: 20px;
                font-weight: bold;
                color: #fff;
            }}
            .stat-value.error {{ color: #ff4444; }}
            .stat-value.warn {{ color: #f5a623; }}
            .stat-value.good {{ color: #4a9eff; }}
            .stat-label {{
                font-size: 11px;
                color: #888;
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }}
            .filters {{
                background: #252528;
                padding: 15px;
                border-radius: 8px;
                margin-bottom: 20px;
                display: flex;
                gap: 15px;
                align-items: center;
                flex-wrap: wrap;
            }}
            .filters select, .filters input {{
                background: #1a1a1d;
                border: 1px solid #444;
                color: #e0e0e0;
                padding: 8px 12px;
                border-radius: 4px;
            }}
            .filters button {{
                background: #ff6a00;
                color: white;
                border: none;
                padding: 8px 20px;
                border-radius: 4px;
                cursor: pointer;
            }}
            .filters button:hover {{ background: #ff8533; }}
            table {{
                width: 100%;
                border-collapse: collapse;
                font-size: 13px;
            }}
            th {{
                text-align: left;
                padding: 10px 8px;
                background: #252528;
                color: #ff6a00;
                position: sticky;
                top: 0;
            }}
            td {{
                padding: 8px;
                border-bottom: 1px solid #333;
                vertical-align: top;
            }}
            tr:hover {{ background: #252528; }}
            .pagination {{
                margin-top: 20px;
                padding: 15px;
                background: #252528;
                border-radius: 8px;
            }}
            a {{ text-decoration: none; }}
            a:hover {{ text-decoration: underline; }}
        </style>
    </head>
    <body>
        <h1>Ashbane Operations Dashboard</h1>

        <!-- Section: Client Telemetry (Godot) -->
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
            <h2 style="color:#4a9eff;font-size:16px;margin:0;">📱 Client Telemetry</h2>
            <span style="background:#2563eb;color:white;padding:2px 8px;border-radius:4px;font-size:10px;">GODOT</span>
            <span id="client-status" style="font-size:12px;color:#4ade80;">● Receiving</span>
        </div>
        <div class="stats-bar">
            <div class="stat-item">
                <span class="stat-value">{total_logs_all:,}</span>
                <span class="stat-label">Total Logs</span>
            </div>
            <div class="stat-item">
                <span class="stat-value good">{logs_24h:,}</span>
                <span class="stat-label">Last 24h</span>
            </div>
            <div class="stat-item">
                <span class="stat-value {'error' if errors_24h > 0 else ''}">{errors_24h}</span>
                <span class="stat-label">Errors (24h)</span>
            </div>
            <div class="stat-item">
                <span class="stat-value {'warn' if warns_24h > 0 else ''}">{warns_24h}</span>
                <span class="stat-label">Warnings (24h)</span>
            </div>
            <div class="stat-item">
                <span class="stat-value">{unique_sessions_24h}</span>
                <span class="stat-label">Sessions (24h)</span>
            </div>
            <div class="stat-item">
                <span class="stat-value">{unique_users_24h}</span>
                <span class="stat-label">Users (24h)</span>
            </div>
            <div class="stat-item">
                <span class="stat-value">{db_size_str}</span>
                <span class="stat-label">Database</span>
            </div>
            <div class="stat-item">
                <span class="stat-value">{disk_str}</span>
                <span class="stat-label">Disk Usage</span>
            </div>
            <div class="stat-item" style="margin-left:auto;">
                <button onclick="openSuspiciousModal()" style="background:#ff4444;color:white;border:none;padding:10px 20px;border-radius:6px;cursor:pointer;font-weight:bold;">
                    🚨 Suspicious IPs
                </button>
            </div>
        </div>

        <!-- Section: Server Infrastructure (Python Agents) -->
        <div id="server-stats-section" style="margin-bottom:20px;">
            <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
                <h2 style="color:#ff6a00;font-size:16px;margin:0;">🖥️ Server Infrastructure</h2>
                <span style="background:#7c3aed;color:white;padding:2px 8px;border-radius:4px;font-size:10px;">AGENTS</span>
                <span id="server-status" style="font-size:12px;color:#666;">● Loading...</span>
                <span id="server-stats-refresh" style="font-size:12px;color:#666;cursor:pointer;margin-left:auto;" onclick="loadServerStats()">🔄 Refresh</span>
            </div>
            <div id="server-stats-container" style="display:flex;gap:15px;flex-wrap:wrap;">
                <div style="color:#666;padding:20px;">Loading server stats...</div>
            </div>
        </div>

        <!-- Client Logs Section -->
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px;">
            <h2 style="color:#4a9eff;font-size:14px;margin:0;">Client Logs</h2>
            <span style="color:#666;font-size:12px;">Showing {len(logs)} of {total} logs (offset: {offset})</span>
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
                        const statusColor = server.status === 'online' ? '#4ade80' : server.status === 'stale' ? '#f5a623' : '#ff4444';
                        const statusIcon = server.status === 'online' ? '🟢' : server.status === 'stale' ? '🟡' : '🔴';
                        const cpuColor = server.cpu_percent > 80 ? '#ff4444' : server.cpu_percent > 60 ? '#f5a623' : '#4ade80';
                        const memColor = server.memory_percent > 80 ? '#ff4444' : server.memory_percent > 60 ? '#f5a623' : '#4ade80';
                        const diskColor = server.disk_percent > 80 ? '#ff4444' : server.disk_percent > 60 ? '#f5a623' : '#4ade80';

                        const isGameServer = server.server_type === 'gameserver';
                        const typeIcon = isGameServer ? '🎮' : '🖥️';
                        const typeBadge = isGameServer ?
                            '<span style="background:#7c3aed;color:white;padding:2px 6px;border-radius:4px;font-size:10px;margin-left:5px;">GAME</span>' :
                            '<span style="background:#2563eb;color:white;padding:2px 6px;border-radius:4px;font-size:10px;margin-left:5px;">API</span>';

                        const uptimeStr = formatUptime(server.uptime_seconds);
                        const playerInfo = server.players_online !== null ?
                            `<div style="margin-top:8px;padding-top:8px;border-top:1px solid #333;">
                                <span style="color:#4a9eff;font-weight:bold;font-size:18px;">${{server.players_online}}</span>
                                <span style="color:#666;">/${{server.players_max || '?'}} players</span>
                            </div>` : '';

                        html += `
                            <div style="background:#252528;border-radius:8px;padding:15px;min-width:280px;border-left:3px solid ${{statusColor}};" onclick="openServerDetail('${{server.server_id}}')" class="server-card">
                                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                                    <div>
                                        <span style="font-size:16px;">${{typeIcon}}</span>
                                        <span style="color:#fff;font-weight:bold;">${{server.server_id}}</span>
                                        ${{typeBadge}}
                                    </div>
                                    <span style="font-size:14px;" title="${{server.status}}">${{statusIcon}}</span>
                                </div>
                                <div style="color:#888;font-size:11px;margin-bottom:10px;">
                                    ${{server.hostname || 'Unknown host'}} • Up ${{uptimeStr}}
                                </div>
                                <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;">
                                    <div>
                                        <div style="color:${{cpuColor}};font-weight:bold;font-size:16px;">${{server.cpu_percent.toFixed(0)}}%</div>
                                        <div style="color:#666;font-size:10px;">CPU</div>
                                    </div>
                                    <div>
                                        <div style="color:${{memColor}};font-weight:bold;font-size:16px;">${{server.memory_percent.toFixed(0)}}%</div>
                                        <div style="color:#666;font-size:10px;">MEM</div>
                                    </div>
                                    <div>
                                        <div style="color:${{diskColor}};font-weight:bold;font-size:16px;">${{server.disk_percent.toFixed(0)}}%</div>
                                        <div style="color:#666;font-size:10px;">DISK</div>
                                    </div>
                                </div>
                                ${{playerInfo}}
                            </div>
                        `;
                    }});

                    if (servers.length === 0) {{
                        html = '<div style="color:#666;padding:20px;background:#252528;border-radius:8px;">No servers reporting. Deploy monitoring agents to see stats.</div>';
                        document.getElementById('server-status').innerHTML = '⚪ No agents';
                        document.getElementById('server-status').style.color = '#666';
                    }} else {{
                        // Update status indicator based on server health
                        const onlineCount = servers.filter(s => s.status === 'online').length;
                        const offlineCount = servers.filter(s => s.status === 'offline').length;
                        const staleCount = servers.filter(s => s.status === 'stale').length;

                        if (offlineCount > 0) {{
                            document.getElementById('server-status').innerHTML = `🔴 ${{offlineCount}} offline`;
                            document.getElementById('server-status').style.color = '#ff4444';
                        }} else if (staleCount > 0) {{
                            document.getElementById('server-status').innerHTML = `🟡 ${{staleCount}} stale`;
                            document.getElementById('server-status').style.color = '#f5a623';
                        }} else {{
                            document.getElementById('server-status').innerHTML = `🟢 ${{onlineCount}} online`;
                            document.getElementById('server-status').style.color = '#4ade80';
                        }}
                    }}

                    document.getElementById('server-stats-container').innerHTML = html;
                }})
                .catch(e => {{
                    document.getElementById('server-stats-container').innerHTML = '<div style="color:#ff4444;padding:20px;">Error loading server stats: ' + e + '</div>';
                    document.getElementById('server-status').innerHTML = '🔴 Error';
                    document.getElementById('server-status').style.color = '#ff4444';
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

        // Load server stats on page load and refresh every 30s
        loadServerStats();
        setInterval(loadServerStats, 30000);
        </script>

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
