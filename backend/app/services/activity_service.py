"""
User Activity Tracking Service

Logs user interactions for analytics, debugging, and journey tracking.
Designed for async, non-blocking logging that doesn't slow down requests.
"""

from datetime import datetime, timedelta
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy import func, desc
from fastapi import Request

from app.models import UserActivity


# Activity categories
class ActivityCategory:
    AUTH = "auth"
    PROVIDER = "provider"
    TAPESTRY = "tapestry"
    CONTRIBUTION = "contribution"
    DISPUTE = "dispute"
    FORGE = "forge"
    SOCIAL = "social"
    NAVIGATION = "navigation"


# Common actions by category
class AuthAction:
    LOGIN = "login"
    LOGOUT = "logout"
    SESSION_REFRESH = "session_refresh"
    DEVICE_CODE_GENERATED = "device_code_generated"
    DEVICE_CODE_VERIFIED = "device_code_verified"


class ProviderAction:
    CONNECT = "connect"
    DISCONNECT = "disconnect"
    SYNC_START = "sync_start"
    SYNC_COMPLETE = "sync_complete"
    SYNC_ERROR = "sync_error"


class TapestryAction:
    VIEW = "view"
    MAP_OPEN = "map_open"
    MAP_SUBMIT = "map_submit"
    VOTE = "vote"


class ContributionAction:
    SUBMIT = "submit"
    APPROVE = "approve"
    REJECT = "reject"
    VOTE_UP = "vote_up"
    VOTE_DOWN = "vote_down"


class DisputeAction:
    CREATE = "create"
    VOTE = "vote"
    RESOLVE = "resolve"


class ForgeAction:
    FORGE_ITEM = "forge_item"
    TRADE_INITIATE = "trade_initiate"
    TRADE_COMPLETE = "trade_complete"


class SocialAction:
    FRIEND_REQUEST = "friend_request"
    FRIEND_ACCEPT = "friend_accept"
    CHAT_MESSAGE = "chat_message"


def log_activity(
    db: Session,
    category: str,
    action: str,
    user_id: Optional[int] = None,
    details: Optional[dict] = None,
    request: Optional[Request] = None,
    success: bool = True,
    error_message: Optional[str] = None,
    duration_ms: Optional[int] = None
) -> UserActivity:
    """
    Log a user activity event.

    Args:
        db: Database session
        category: Activity category (auth, provider, tapestry, etc.)
        action: Specific action (login, connect, view, etc.)
        user_id: User ID (optional for pre-login events)
        details: JSON-serializable context data
        request: FastAPI request for IP/user-agent extraction
        success: Whether the action succeeded
        error_message: Error details if failed
        duration_ms: How long the action took

    Returns:
        Created UserActivity record
    """
    ip_address = None
    user_agent = None

    if request:
        # Get real IP from X-Forwarded-For or fall back to client host
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            ip_address = forwarded.split(",")[0].strip()
        else:
            ip_address = request.client.host if request.client else None

        user_agent = request.headers.get("user-agent", "")[:512]

    activity = UserActivity(
        user_id=user_id,
        category=category,
        action=action,
        details=details,
        ip_address=ip_address,
        user_agent=user_agent,
        success=success,
        error_message=error_message[:512] if error_message else None,
        duration_ms=duration_ms
    )

    db.add(activity)
    db.commit()

    return activity


def get_user_journey(db: Session, user_id: int, limit: int = 50) -> list:
    """Get recent activity for a specific user."""
    return db.query(UserActivity).filter(
        UserActivity.user_id == user_id
    ).order_by(desc(UserActivity.created_at)).limit(limit).all()


def get_activity_stats(db: Session, hours: int = 24) -> dict:
    """
    Get aggregate activity stats for the last N hours.

    Returns:
        Dict with counts by category and action
    """
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    # Total activities
    total = db.query(func.count(UserActivity.id)).filter(
        UserActivity.created_at >= cutoff
    ).scalar()

    # By category
    by_category = dict(db.query(
        UserActivity.category,
        func.count(UserActivity.id)
    ).filter(
        UserActivity.created_at >= cutoff
    ).group_by(UserActivity.category).all())

    # By action (top 20)
    by_action = dict(db.query(
        UserActivity.action,
        func.count(UserActivity.id)
    ).filter(
        UserActivity.created_at >= cutoff
    ).group_by(UserActivity.action).order_by(
        desc(func.count(UserActivity.id))
    ).limit(20).all())

    # Unique users
    unique_users = db.query(
        func.count(func.distinct(UserActivity.user_id))
    ).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.user_id.isnot(None)
    ).scalar()

    # Error count
    errors = db.query(func.count(UserActivity.id)).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.success == False
    ).scalar()

    return {
        "period_hours": hours,
        "total_activities": total,
        "unique_users": unique_users,
        "error_count": errors,
        "by_category": by_category,
        "by_action": by_action
    }


def get_user_funnel(db: Session, hours: int = 24) -> dict:
    """
    Get conversion funnel stats.

    Tracks user progression through key milestones:
    1. Login
    2. Provider connected
    3. Achievement synced
    4. Tapestry viewed
    5. Mapping submitted
    """
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    # Users who logged in
    logins = db.query(func.count(func.distinct(UserActivity.user_id))).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.category == ActivityCategory.AUTH,
        UserActivity.action == AuthAction.LOGIN
    ).scalar()

    # Users who connected a provider
    provider_connects = db.query(func.count(func.distinct(UserActivity.user_id))).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.category == ActivityCategory.PROVIDER,
        UserActivity.action == ProviderAction.CONNECT
    ).scalar()

    # Users who synced achievements
    syncs = db.query(func.count(func.distinct(UserActivity.user_id))).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.category == ActivityCategory.PROVIDER,
        UserActivity.action == ProviderAction.SYNC_COMPLETE
    ).scalar()

    # Users who viewed tapestry
    tapestry_views = db.query(func.count(func.distinct(UserActivity.user_id))).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.category == ActivityCategory.TAPESTRY,
        UserActivity.action == TapestryAction.VIEW
    ).scalar()

    # Users who submitted a mapping
    mappings = db.query(func.count(func.distinct(UserActivity.user_id))).filter(
        UserActivity.created_at >= cutoff,
        UserActivity.category == ActivityCategory.CONTRIBUTION,
        UserActivity.action == ContributionAction.SUBMIT
    ).scalar()

    return {
        "period_hours": hours,
        "funnel": {
            "1_login": logins,
            "2_provider_connected": provider_connects,
            "3_achievements_synced": syncs,
            "4_tapestry_viewed": tapestry_views,
            "5_mapping_submitted": mappings
        }
    }


def get_recent_errors(db: Session, limit: int = 20) -> list:
    """Get recent failed activities for debugging."""
    errors = db.query(UserActivity).filter(
        UserActivity.success == False
    ).order_by(desc(UserActivity.created_at)).limit(limit).all()

    return [{
        "id": e.id,
        "user_id": e.user_id,
        "category": e.category,
        "action": e.action,
        "error": e.error_message,
        "details": e.details,
        "ip": e.ip_address,
        "created_at": e.created_at.isoformat()
    } for e in errors]
