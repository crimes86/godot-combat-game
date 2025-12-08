"""
Friend system routes.

These endpoints allow users to:
1. Send friend requests
2. Accept/decline friend requests
3. View friends list
4. Search for users
5. Remove friends
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import or_, and_, func
from typing import Optional, List, Callable
from datetime import datetime, timedelta
import logging

from app.models import User, Friendship, ProviderAccount, AchievementCredit, Achievement, ChatMessage
from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/friends", tags=["friends"])

# These will be set by init_friend_routes()
_get_current_user_func: Callable = None
_calculate_mantle_tier_func: Callable = None


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
        raise HTTPException(status_code=500, detail="Friend routes not initialized")
    return _get_current_user_func(request, db)


def init_friend_routes(get_current_user: Callable, calculate_mantle_tier: Callable):
    """Initialize friend routes with dependencies from main app."""
    global _get_current_user_func, _calculate_mantle_tier_func
    _get_current_user_func = get_current_user
    _calculate_mantle_tier_func = calculate_mantle_tier


def get_user_summary(user: User, db: DbSession) -> dict:
    """Build a summary of a user for friend lists."""
    # Count achievements
    achievement_count = (
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user.id,
            AchievementCredit.is_original_claim == True
        )
        .count()
    )

    # Count providers
    provider_count = (
        db.query(ProviderAccount)
        .filter(ProviderAccount.user_id == user.id, ProviderAccount.is_active == True)
        .count()
    )

    # Get mantle tier
    mantle = _calculate_mantle_tier_func(achievement_count, provider_count)

    # Get rarity breakdown
    rarity_counts = {"Common": 0, "Uncommon": 0, "Rare": 0, "Epic": 0, "Legendary": 0}
    rarity_query = (
        db.query(Achievement.rarity_tier, func.count(AchievementCredit.id))
        .join(AchievementCredit, AchievementCredit.achievement_id == Achievement.id)
        .filter(
            AchievementCredit.user_id == user.id,
            AchievementCredit.is_original_claim == True
        )
        .group_by(Achievement.rarity_tier)
        .all()
    )
    for tier, count in rarity_query:
        if tier in rarity_counts:
            rarity_counts[tier] = count

    return {
        "user_id": user.id,
        "username": user.username,
        "achievement_count": achievement_count,
        "mantle": {
            "tier": mantle["tier"],
            "name": mantle["name"],
            "color": mantle["color"],
        },
        "by_rarity": rarity_counts,
    }


# =============================================================================
# FRIEND REQUEST ENDPOINTS
# =============================================================================

@router.post("/request/{friend_id}")
async def send_friend_request(
    friend_id: int,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Send a friend request to another user."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    if current_user.id == friend_id:
        raise HTTPException(status_code=400, detail="Cannot send friend request to yourself")

    # Check friend exists
    friend = db.query(User).filter(User.id == friend_id).first()
    if not friend:
        raise HTTPException(status_code=404, detail="User not found")

    # Check if already friends or pending
    existing = db.query(Friendship).filter(
        or_(
            and_(Friendship.user_id == current_user.id, Friendship.friend_id == friend_id),
            and_(Friendship.user_id == friend_id, Friendship.friend_id == current_user.id)
        )
    ).first()

    if existing:
        if existing.status == 'accepted':
            raise HTTPException(status_code=400, detail="Already friends")
        elif existing.status == 'pending':
            # If they sent us a request, accept it
            if existing.user_id == friend_id:
                existing.status = 'accepted'
                existing.accepted_at = datetime.utcnow()
                db.commit()
                return {"success": True, "message": "Friend request accepted", "status": "accepted"}
            else:
                raise HTTPException(status_code=400, detail="Friend request already pending")
        elif existing.status == 'blocked':
            raise HTTPException(status_code=400, detail="Cannot send request")

    # Create new request
    friendship = Friendship(
        user_id=current_user.id,
        friend_id=friend_id,
        status='pending'
    )
    db.add(friendship)
    db.commit()

    logger.info(f"[FRIENDS] User {current_user.id} sent friend request to {friend_id}")
    return {"success": True, "message": "Friend request sent", "status": "pending"}


@router.post("/accept/{request_id}")
async def accept_friend_request(
    request_id: int,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Accept a pending friend request."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    friendship = db.query(Friendship).filter(
        Friendship.id == request_id,
        Friendship.friend_id == current_user.id,  # Must be recipient
        Friendship.status == 'pending'
    ).first()

    if not friendship:
        raise HTTPException(status_code=404, detail="Friend request not found")

    friendship.status = 'accepted'
    friendship.accepted_at = datetime.utcnow()
    db.commit()

    logger.info(f"[FRIENDS] User {current_user.id} accepted friend request from {friendship.user_id}")
    return {"success": True, "message": "Friend request accepted"}


@router.post("/decline/{request_id}")
async def decline_friend_request(
    request_id: int,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Decline a pending friend request."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    friendship = db.query(Friendship).filter(
        Friendship.id == request_id,
        Friendship.friend_id == current_user.id,  # Must be recipient
        Friendship.status == 'pending'
    ).first()

    if not friendship:
        raise HTTPException(status_code=404, detail="Friend request not found")

    # Delete the request (or could set status='declined')
    db.delete(friendship)
    db.commit()

    logger.info(f"[FRIENDS] User {current_user.id} declined friend request from {friendship.user_id}")
    return {"success": True, "message": "Friend request declined"}


@router.delete("/{friend_id}")
async def remove_friend(
    friend_id: int,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Remove a friend."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    friendship = db.query(Friendship).filter(
        or_(
            and_(Friendship.user_id == current_user.id, Friendship.friend_id == friend_id),
            and_(Friendship.user_id == friend_id, Friendship.friend_id == current_user.id)
        ),
        Friendship.status == 'accepted'
    ).first()

    if not friendship:
        raise HTTPException(status_code=404, detail="Friendship not found")

    db.delete(friendship)
    db.commit()

    logger.info(f"[FRIENDS] User {current_user.id} removed friend {friend_id}")
    return {"success": True, "message": "Friend removed"}


# =============================================================================
# FRIEND LIST ENDPOINTS
# =============================================================================

@router.get("")
async def get_friends(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get list of accepted friends with their stats."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Get all accepted friendships (either direction)
    friendships = db.query(Friendship).filter(
        or_(
            Friendship.user_id == current_user.id,
            Friendship.friend_id == current_user.id
        ),
        Friendship.status == 'accepted'
    ).all()

    friends = []
    recent_threshold = datetime.utcnow() - timedelta(minutes=5)

    for f in friendships:
        # Get the other user's ID
        friend_id = f.friend_id if f.user_id == current_user.id else f.user_id
        friend_user = db.query(User).filter(User.id == friend_id).first()
        if friend_user:
            summary = get_user_summary(friend_user, db)
            summary["friendship_id"] = f.id
            summary["friends_since"] = f.accepted_at.isoformat() if f.accepted_at else None

            # Check if friend is online (sent chat message in last 5 minutes)
            is_online = db.query(ChatMessage).filter(
                ChatMessage.user_id == friend_id,
                ChatMessage.created_at > recent_threshold
            ).first() is not None
            summary["is_online"] = is_online

            friends.append(summary)

    return {"friends": friends, "count": len(friends)}


@router.get("/pending")
async def get_pending_requests(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get incoming friend requests."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Get pending requests where current user is the recipient
    pending = db.query(Friendship).filter(
        Friendship.friend_id == current_user.id,
        Friendship.status == 'pending'
    ).all()

    requests = []
    for f in pending:
        sender = db.query(User).filter(User.id == f.user_id).first()
        if sender:
            summary = get_user_summary(sender, db)
            summary["request_id"] = f.id
            summary["sent_at"] = f.created_at.isoformat() if f.created_at else None
            requests.append(summary)

    return {"requests": requests, "count": len(requests)}


@router.get("/sent")
async def get_sent_requests(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get outgoing friend requests."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Get pending requests where current user is the sender
    sent = db.query(Friendship).filter(
        Friendship.user_id == current_user.id,
        Friendship.status == 'pending'
    ).all()

    requests = []
    for f in sent:
        recipient = db.query(User).filter(User.id == f.friend_id).first()
        if recipient:
            summary = get_user_summary(recipient, db)
            summary["request_id"] = f.id
            summary["sent_at"] = f.created_at.isoformat() if f.created_at else None
            requests.append(summary)

    return {"requests": requests, "count": len(requests)}


# =============================================================================
# USER SEARCH
# =============================================================================

@router.get("/search")
async def search_users(
    request: Request,
    q: str = Query(..., min_length=2, description="Search query"),
    db: DbSession = Depends(get_db),
):
    """Search for users by username."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Search by username (case-insensitive)
    users = db.query(User).filter(
        User.username.ilike(f"%{q}%"),
        User.id != current_user.id  # Exclude self
    ).limit(20).all()

    results = []
    for user in users:
        summary = get_user_summary(user, db)

        # Check friendship status
        friendship = db.query(Friendship).filter(
            or_(
                and_(Friendship.user_id == current_user.id, Friendship.friend_id == user.id),
                and_(Friendship.user_id == user.id, Friendship.friend_id == current_user.id)
            )
        ).first()

        if friendship:
            summary["friendship_status"] = friendship.status
            if friendship.status == 'pending':
                summary["pending_direction"] = "sent" if friendship.user_id == current_user.id else "received"
        else:
            summary["friendship_status"] = None

        results.append(summary)

    return {"users": results, "count": len(results)}
