"""
Chat system routes for tiered chat rooms.

Each tier has its own chat room matching the tier name.
- global: Activity feed visible to all (unlock/forge announcements)
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import desc
from typing import Optional, Callable
from datetime import datetime, timedelta
from pydantic import BaseModel
import logging
import html

from app.models import User, ChatMessage, AchievementCredit, AchievementDispute
from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["chat"])

# These will be set by init_chat_routes()
_get_current_user_func: Callable = None
_calculate_Ashbane_tier_func: Callable = None


# Tier to room mapping - each tier gets its own room
TIER_ROOMS = {
    "initiate": "initiate",
    "bronze": "bronze",
    "silver": "silver",
    "gold": "gold",
    "platinum": "platinum",
    "diamond": "diamond",
    "legendary": "legendary",
    "mythic": "mythic",
}

ROOM_DISPLAY_NAMES = {
    "initiate": "#initiate",
    "bronze": "#bronze",
    "silver": "#silver",
    "gold": "#gold",
    "platinum": "#platinum",
    "diamond": "#diamond",
    "legendary": "#legendary",
    "mythic": "#mythic",
    "global": "#global-feed",
}

ROOM_COLORS = {
    "initiate": "#666666",
    "bronze": "#cd7f32",
    "silver": "#c0c0c0",
    "gold": "#ffd700",
    "platinum": "#a0d8ef",
    "diamond": "#40e0d0",
    "legendary": "#ff6600",
    "mythic": "#ff00ff",
    "global": "#00ffc8",
}


class SendMessageRequest(BaseModel):
    content: str


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
        raise HTTPException(status_code=500, detail="Chat routes not initialized")
    return _get_current_user_func(request, db)


def init_chat_routes(get_current_user: Callable, calculate_Ashbane_tier: Callable):
    """Initialize chat routes with dependencies from main app."""
    global _get_current_user_func, _calculate_Ashbane_tier_func
    _get_current_user_func = get_current_user
    _calculate_Ashbane_tier_func = calculate_Ashbane_tier


def get_user_room(user: User, db: DbSession) -> str:
    """Determine which chat room a user belongs to based on their tier."""
    from app.models import ProviderAccount

    # Count original achievements
    achievement_count = (
        db.query(AchievementCredit)
        .filter(
            AchievementCredit.user_id == user.id,
            AchievementCredit.is_original_claim == True
        )
        .count()
    )

    # Get tier (pure achievement count, no provider bonus)
    Ashbane = _calculate_Ashbane_tier_func(achievement_count)
    tier = Ashbane["tier"]

    return TIER_ROOMS.get(tier, "newcomers")


# =============================================================================
# CHAT ENDPOINTS
# =============================================================================

@router.get("/rooms")
async def get_available_rooms(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get list of available chat rooms for the current user."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    user_room = get_user_room(current_user, db)

    rooms = []
    for room_id, display_name in ROOM_DISPLAY_NAMES.items():
        room_info = {
            "id": room_id,
            "name": display_name,
            "color": ROOM_COLORS.get(room_id, "#888"),
            "is_user_room": room_id == user_room,
            "accessible": room_id == user_room or room_id == "global",
        }
        rooms.append(room_info)

    return {
        "rooms": rooms,
        "current_room": user_room,
    }


@router.get("/messages/{room}")
async def get_messages(
    room: str,
    request: Request,
    limit: int = Query(50, ge=1, le=100),
    before_id: Optional[int] = None,
    db: DbSession = Depends(get_db),
):
    """Get messages from a chat room."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Validate room access
    user_room = get_user_room(current_user, db)
    if room != "global" and room != user_room:
        raise HTTPException(status_code=403, detail="You don't have access to this room")

    # Build query
    query = db.query(ChatMessage).filter(ChatMessage.room == room)

    if before_id:
        query = query.filter(ChatMessage.id < before_id)

    messages = query.order_by(desc(ChatMessage.created_at)).limit(limit).all()

    # Reverse to get chronological order
    messages = messages[::-1]

    # Pre-fetch disputes for dispute messages (batch query for efficiency)
    dispute_msg_ids = [msg.id for msg in messages if msg.message_type == 'dispute']
    disputes_by_msg = {}
    if dispute_msg_ids:
        disputes = db.query(AchievementDispute).filter(
            AchievementDispute.chat_message_id.in_(dispute_msg_ids)
        ).all()
        for d in disputes:
            disputes_by_msg[d.chat_message_id] = d

    result = []
    for msg in messages:
        msg_data = {
            "id": msg.id,
            "content": msg.content,
            "type": msg.message_type,
            "created_at": msg.created_at.isoformat(),
            "room": msg.room,
        }

        if msg.user:
            msg_data["user"] = {
                "id": msg.user.id,
                "username": msg.user.username,
            }
        else:
            msg_data["user"] = None

        # For dispute messages, include the achievement and dispute IDs
        if msg.message_type == 'dispute' and msg.id in disputes_by_msg:
            dispute = disputes_by_msg[msg.id]
            msg_data["dispute"] = {
                "dispute_id": dispute.id,
                "achievement_id": dispute.achievement_id,
                "status": dispute.status,
                "suggested_rarity": dispute.suggested_rarity,
                "current_rarity": dispute.current_rarity,
            }

        result.append(msg_data)

    return {"messages": result, "room": room}


@router.post("/messages/{room}")
async def send_message(
    room: str,
    body: SendMessageRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Send a message to a chat room."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Validate room access (can't post to global - system only)
    user_room = get_user_room(current_user, db)
    if room == "global":
        raise HTTPException(status_code=403, detail="Cannot post to global feed")
    if room != user_room:
        raise HTTPException(status_code=403, detail="You don't have access to this room")

    # Validate and sanitize content
    content = body.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    if len(content) > 500:
        raise HTTPException(status_code=400, detail="Message too long (max 500 chars)")
    # XSS prevention: escape HTML entities before storing
    content = html.escape(content)

    # Rate limiting: max 1 message per 2 seconds
    recent = db.query(ChatMessage).filter(
        ChatMessage.user_id == current_user.id,
        ChatMessage.created_at > datetime.utcnow() - timedelta(seconds=2)
    ).first()

    if recent:
        raise HTTPException(status_code=429, detail="Please wait before sending another message")

    # Create message
    message = ChatMessage(
        user_id=current_user.id,
        room=room,
        content=content,
        message_type="chat",
    )
    db.add(message)
    db.commit()
    db.refresh(message)

    logger.info(f"[CHAT] User {current_user.id} sent message in {room}")

    return {
        "success": True,
        "message": {
            "id": message.id,
            "content": message.content,
            "type": message.message_type,
            "created_at": message.created_at.isoformat(),
            "room": message.room,
            "user": {
                "id": current_user.id,
                "username": current_user.username,
            }
        }
    }


@router.get("/online")
async def get_online_count(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get approximate online user count (users with recent activity)."""
    current_user = get_current_user_dep(request, db)
    if not current_user:
        raise HTTPException(status_code=401, detail="Not authenticated")

    # Count users who sent a message in the last 5 minutes
    recent_threshold = datetime.utcnow() - timedelta(minutes=5)

    user_room = get_user_room(current_user, db)

    online_in_room = db.query(ChatMessage.user_id).filter(
        ChatMessage.room == user_room,
        ChatMessage.created_at > recent_threshold,
        ChatMessage.user_id.isnot(None)
    ).distinct().count()

    return {
        "room": user_room,
        "online": max(1, online_in_room),  # At least 1 (current user)
    }


# =============================================================================
# GLOBAL FEED HELPERS (called from sync/forge endpoints)
# =============================================================================

def post_unlock_announcement(db: DbSession, user: User, achievement_credit: AchievementCredit, achievement_name: str, rarity: str):
    """Post an unlock announcement to the global feed."""
    try:
        content = f"{user.username} unlocked \"{achievement_name}\" ({rarity})"

        message = ChatMessage(
            user_id=user.id,
            room="global",
            content=content,
            message_type="unlock",
            achievement_credit_id=achievement_credit.id,
        )
        db.add(message)
        db.commit()
    except Exception as e:
        logger.error(f"Failed to post unlock announcement: {e}")


def post_forge_announcement(db: DbSession, user: User, achievement_name: str, rarity: str):
    """Post a forge announcement to the global feed."""
    try:
        content = f"{user.username} forged \"{achievement_name}\" into a Relic!"

        message = ChatMessage(
            user_id=user.id,
            room="global",
            content=content,
            message_type="forge",
        )
        db.add(message)
        db.commit()
    except Exception as e:
        logger.error(f"Failed to post forge announcement: {e}")


def post_user_joined_announcement(db: DbSession, user: User, provider_name: str):
    """Post an announcement when a new user joins Ashbane."""
    try:
        provider_display = {
            "steam": "Steam",
            "battlenet": "Battle.net",
            "xbox": "Xbox",
            "psn": "PlayStation",
        }.get(provider_name, provider_name.title())

        content = f"{user.username} joined Ashbane via {provider_display}"

        message = ChatMessage(
            user_id=user.id,
            room="global",
            content=content,
            message_type="join",
        )
        db.add(message)
        db.commit()
        logger.info(f"[CHAT] Posted join announcement for {user.username}")
    except Exception as e:
        logger.error(f"Failed to post user joined announcement: {e}")


def post_sync_announcement(db: DbSession, user: User, provider_name: str, new_count: int, rarity_breakdown: dict = None):
    """Post an announcement when a user syncs new achievements."""
    if new_count == 0:
        return  # Don't announce empty syncs

    try:
        provider_display = {
            "steam": "Steam",
            "battlenet": "Battle.net",
            "xbox": "Xbox",
            "psn": "PlayStation",
        }.get(provider_name, provider_name.title())

        # Build message based on what was synced
        if new_count == 1:
            content = f"{user.username} synced 1 new achievement from {provider_display}"
        else:
            content = f"{user.username} synced {new_count} new achievements from {provider_display}"

        # Add rarity highlight if there's something notable
        if rarity_breakdown:
            notable = []
            if rarity_breakdown.get("Legendary", 0) > 0:
                notable.append(f"{rarity_breakdown['Legendary']} Legendary")
            if rarity_breakdown.get("Epic", 0) > 0:
                notable.append(f"{rarity_breakdown['Epic']} Epic")
            if rarity_breakdown.get("Rare", 0) > 0:
                notable.append(f"{rarity_breakdown['Rare']} Rare")

            if notable:
                content += f" ({', '.join(notable)})"

        message = ChatMessage(
            user_id=user.id,
            room="global",
            content=content,
            message_type="sync",
        )
        db.add(message)
        db.commit()
        logger.info(f"[CHAT] Posted sync announcement for {user.username}: {new_count} achievements")
    except Exception as e:
        logger.error(f"Failed to post sync announcement: {e}")


def broadcast_system_message(content: str, message_type: str = "system") -> None:
    """
    Broadcast a system message to the global feed.
    Used for trade announcements, server events, etc.
    """
    db = SessionLocal()
    try:
        message = ChatMessage(
            user_id=None,  # System message - no user
            room="global",
            content=content,
            message_type=message_type,
        )
        db.add(message)
        db.commit()
        logger.info(f"[CHAT] Broadcast system message: {content}")
    except Exception as e:
        logger.error(f"Failed to broadcast system message: {e}")
    finally:
        db.close()


import random

# Mock data pools for realistic generation
MOCK_USERNAMES = [
    "xXDragonSlayerXx", "CryptoKnight", "AchievementHunter", "ProGamer2024",
    "RetroGamer", "SpeedRunner", "NightOwl", "ShadowBlade", "PixelWarrior",
    "GhostRider", "IronWolf", "StormChaser", "BlazeMaster", "FrostByte",
    "ThunderStrike", "NeonNinja", "CyberPunk77", "QuantumLeap", "VoidWalker",
    "StarDust", "MoonKnight", "SolarFlare", "DarkMatter", "CosmicRay",
    "TurboGamer", "EliteSniper", "RogueAgent", "PhantomX", "ZeroGravity",
    "InfinityEdge", "CrimsonTide", "GoldenEagle", "SilverFox", "BronzeKing",
    "DiamondDog", "PlatinumPro", "TitanFall", "ApexLegend", "VanguardOne",
]

MOCK_ACHIEVEMENTS = [
    ("Dragon Slayer", "Legendary"), ("World First", "Legendary"), ("Impossible Dream", "Legendary"),
    ("Speed Demon", "Legendary"), ("Completionist", "Legendary"), ("No Death Run", "Legendary"),
    ("Master Tactician", "Epic"), ("Treasure Hunter", "Epic"), ("Champion Rising", "Epic"),
    ("Legendary Explorer", "Epic"), ("Boss Crusher", "Epic"), ("Elite Warrior", "Epic"),
    ("Dungeon Master", "Epic"), ("Raid Leader", "Epic"), ("Perfect Victory", "Epic"),
    ("Sharpshooter", "Rare"), ("First Blood", "Rare"), ("Combo King", "Rare"),
    ("Secret Finder", "Rare"), ("Speed Run", "Rare"), ("Collector", "Rare"),
    ("Survivor", "Rare"), ("Team Player", "Rare"), ("Strategist", "Rare"),
    ("Quick Draw", "Uncommon"), ("Explorer", "Uncommon"), ("Helper", "Uncommon"),
    ("First Steps", "Common"), ("Tutorial Complete", "Common"), ("Welcome", "Common"),
]

MOCK_PROVIDERS = ["Steam", "Xbox", "PlayStation", "Battle.net"]


def generate_random_notification() -> tuple:
    """Generate a random global feed notification."""
    username = random.choice(MOCK_USERNAMES)

    # Weighted random event type (more unlocks/syncs, fewer joins/forges)
    event_type = random.choices(
        ["unlock", "sync", "join", "forge"],
        weights=[40, 35, 15, 10],  # 40% unlock, 35% sync, 15% join, 10% forge
        k=1
    )[0]

    if event_type == "join":
        provider = random.choice(MOCK_PROVIDERS)
        return (f"{username} joined Ashbane via {provider}", "join")

    elif event_type == "sync":
        provider = random.choice(MOCK_PROVIDERS)
        count = random.choices(
            [random.randint(1, 10), random.randint(11, 50), random.randint(51, 200)],
            weights=[50, 35, 15],  # Most syncs are small
            k=1
        )[0]

        # Generate rarity breakdown for larger syncs
        notable = []
        if count > 20:
            legendary = random.randint(0, min(3, count // 30))
            epic = random.randint(0, min(8, count // 15))
            rare = random.randint(0, min(20, count // 5))
            if legendary > 0:
                notable.append(f"{legendary} Legendary")
            if epic > 0:
                notable.append(f"{epic} Epic")
            if rare > 0:
                notable.append(f"{rare} Rare")

        content = f"{username} synced {count} new achievement{'s' if count > 1 else ''} from {provider}"
        if notable:
            content += f" ({', '.join(notable)})"
        return (content, "sync")

    elif event_type == "unlock":
        # Weight toward rarer achievements being announced (they're more exciting)
        achievement, rarity = random.choices(
            MOCK_ACHIEVEMENTS,
            weights=[3 if a[1] == "Legendary" else 2 if a[1] == "Epic" else 1.5 if a[1] == "Rare" else 0.5 for a in MOCK_ACHIEVEMENTS],
            k=1
        )[0]

        return (f"{username} unlocked \"{achievement}\" ({rarity})", "unlock")

    else:  # forge
        # Only rare+ can be forged
        forgeable = [(a, r) for a, r in MOCK_ACHIEVEMENTS if r in ["Legendary", "Epic", "Rare"]]
        achievement, rarity = random.choice(forgeable)
        return (f"{username} forged \"{achievement}\" into a Relic!", "forge")


def seed_mock_global_feed(message_count: int = 30, hours_back: int = 4):
    """Seed random mock global feed messages for demo purposes."""
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        # Check if global feed already has messages
        existing = db.query(ChatMessage).filter(ChatMessage.room == "global").count()
        if existing > 0:
            return  # Already seeded

        # Generate random messages with varied timestamps
        base_time = datetime.utcnow() - timedelta(hours=hours_back)
        total_minutes = hours_back * 60

        # Generate random timestamps and sort them
        timestamps = sorted([
            base_time + timedelta(minutes=random.randint(0, total_minutes))
            for _ in range(message_count)
        ])

        for timestamp in timestamps:
            content, msg_type = generate_random_notification()
            message = ChatMessage(
                user_id=None,  # System/mock messages
                room="global",
                content=content,
                message_type=msg_type,
                created_at=timestamp,
            )
            db.add(message)

        db.commit()
        logger.info(f"[CHAT] Seeded {message_count} random mock global feed messages")
    except Exception as e:
        logger.error(f"Failed to seed mock global feed: {e}")
        db.rollback()
    finally:
        db.close()


# =============================================================================
# LIVE MOCK ACTIVITY GENERATOR
# =============================================================================

import asyncio

_mock_activity_task = None
_mock_activity_enabled = False


async def _mock_activity_loop(min_interval: int = 15, max_interval: int = 45):
    """Background loop that generates random activity at random intervals."""
    from app.database import SessionLocal

    logger.info("[MOCK] Live activity generator started")

    while _mock_activity_enabled:
        # Wait random interval (simulates sporadic real user activity)
        wait_time = random.randint(min_interval, max_interval)
        await asyncio.sleep(wait_time)

        if not _mock_activity_enabled:
            break

        # Generate and post a random notification
        db = SessionLocal()
        try:
            content, msg_type = generate_random_notification()
            message = ChatMessage(
                user_id=None,
                room="global",
                content=content,
                message_type=msg_type,
            )
            db.add(message)
            db.commit()
            logger.debug(f"[MOCK] Generated: {msg_type} - {content[:50]}...")
        except Exception as e:
            logger.error(f"[MOCK] Failed to generate activity: {e}")
            db.rollback()
        finally:
            db.close()

    logger.info("[MOCK] Live activity generator stopped")


def start_mock_activity(min_interval: int = 15, max_interval: int = 45):
    """Start the live mock activity generator."""
    global _mock_activity_task, _mock_activity_enabled

    if _mock_activity_enabled:
        logger.warning("[MOCK] Activity generator already running")
        return

    _mock_activity_enabled = True
    _mock_activity_task = asyncio.create_task(_mock_activity_loop(min_interval, max_interval))
    logger.info(f"[MOCK] Started live activity generator (interval: {min_interval}-{max_interval}s)")


def stop_mock_activity():
    """Stop the live mock activity generator."""
    global _mock_activity_enabled

    _mock_activity_enabled = False
    logger.info("[MOCK] Stopping live activity generator...")
