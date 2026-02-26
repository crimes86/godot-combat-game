"""
Server-to-server routes for dedicated game server.
Authenticated via X-Server-Key header, not user tokens.

This enables the dedicated game server to sync character data to the backend
when players disconnect (camp timer complete, crash, etc.) without needing
to transmit user auth tokens over the game network.
"""
import os
import logging
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session as DbSession
from sqlalchemy.orm.attributes import flag_modified

from app.database import SessionLocal
from app.models import User, Character
from app.services.telemetry_service import log_backend_event

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/server", tags=["server"])

# Server API key from environment
SERVER_API_KEY = os.environ.get("SERVER_API_KEY", "")


def get_db():
    """Database session dependency."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def verify_server_key(x_server_key: str = Header(..., alias="X-Server-Key")):
    """Verify the server API key from header."""
    if not SERVER_API_KEY:
        logger.error("SERVER_API_KEY not configured in environment")
        raise HTTPException(status_code=500, detail="Server API key not configured")
    if x_server_key != SERVER_API_KEY:
        logger.warning(f"Invalid server key attempted")
        raise HTTPException(status_code=401, detail="Invalid server key")
    return True


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class ServerCharacterSync(BaseModel):
    """Character sync payload from dedicated server."""
    user_id: int = Field(..., ge=1, description="Ashbane user ID")
    gold: int = Field(..., ge=0, le=999999999)
    level: int = Field(..., ge=1, le=100)
    experience: int = Field(default=0, ge=0)
    inventory: list = Field(default_factory=list)
    equipped_weapon: str = Field(default="")
    equipped_armor: dict = Field(default_factory=dict)
    weapon_skills: dict = Field(default_factory=dict)
    # Character stats
    strength: int = Field(default=10, ge=1, le=999)
    agility: int = Field(default=10, ge=1, le=999)
    dexterity: int = Field(default=10, ge=1, le=999)
    intelligence: int = Field(default=10, ge=1, le=999)
    wisdom: int = Field(default=10, ge=1, le=999)
    vitality: int = Field(default=10, ge=1, le=999)
    current_hp: float = Field(default=-1.0, description="Current HP, -1 means not provided")
    # Optional context for logging
    disconnect_reason: Optional[str] = Field(default=None, max_length=64)


class ServerCharacterSyncResponse(BaseModel):
    """Response for character sync."""
    success: bool
    user_id: int
    gold: int
    level: int
    message: Optional[str] = None


class ServerCharacterFetchResponse(BaseModel):
    """Response for character fetch."""
    success: bool
    user_id: int
    gold: int
    level: int
    experience: int
    inventory: list
    equipped_weapon: str
    equipped_armor: dict
    weapon_skills: dict
    strength: int
    agility: int
    dexterity: int
    intelligence: int
    wisdom: int
    vitality: int
    current_hp: float = Field(default=-1.0)


# =============================================================================
# ENDPOINTS
# =============================================================================

@router.post("/character-sync", response_model=ServerCharacterSyncResponse)
async def server_character_sync(
    payload: ServerCharacterSync,
    db: DbSession = Depends(get_db),
    _: bool = Depends(verify_server_key)
):
    """
    Sync character data from dedicated game server.

    Called when:
    - Player camp timer completes (quit early via "Quit Now")
    - Player disconnects unexpectedly (crash, network drop)

    The game server is authoritative for final state - the player may have
    died, lost items, or gained XP during the camp period after they
    pressed "Quit Now".

    Authentication: X-Server-Key header (server-to-server auth)
    """
    # Find user by Ashbane user_id
    user = db.query(User).filter(User.id == payload.user_id).first()
    if not user:
        logger.warning(f"Server sync for unknown user_id: {payload.user_id}")
        raise HTTPException(status_code=404, detail="User not found")

    # Get active character
    character = db.query(Character).filter(
        Character.user_id == user.id,
        Character.is_active == True
    ).first()

    if not character:
        logger.warning(f"Server sync - no active character for user {user.id}")
        raise HTTPException(status_code=404, detail="No active character")

    # Store previous values for logging
    prev_gold = character.gold
    prev_level = character.level

    # Update character with server's authoritative state
    character.gold = payload.gold
    character.level = min(payload.level, 100)

    # Update character_data blob
    data = character.character_data or {}
    data["experience"] = payload.experience
    data["equipped_weapon"] = payload.equipped_weapon
    data["equipped_armor"] = payload.equipped_armor
    data["weapon_skills"] = payload.weapon_skills
    data["inventory"] = payload.inventory
    data["strength"] = payload.strength
    data["agility"] = payload.agility
    data["dexterity"] = payload.dexterity
    data["intelligence"] = payload.intelligence
    data["wisdom"] = payload.wisdom
    data["vitality"] = payload.vitality
    if payload.current_hp >= 0:
        data["current_hp"] = payload.current_hp

    character.character_data = data
    character.last_played_at = datetime.utcnow()
    flag_modified(character, 'character_data')

    # Log telemetry event
    log_backend_event(
        db=db,
        user_id=user.id,
        character_id=character.id,
        event_type="server_character_sync",
        event_data={
            "gold": character.gold,
            "gold_delta": character.gold - prev_gold,
            "level": character.level,
            "level_delta": character.level - prev_level,
            "experience": payload.experience,
            "inventory_count": len(payload.inventory),
            "disconnect_reason": payload.disconnect_reason,
        },
        ip_address=None  # Server-side sync, no client IP
    )

    db.commit()

    logger.info(
        f"[SERVER_SYNC] user={user.id} ({user.username}) "
        f"gold={prev_gold}->{character.gold} level={prev_level}->{character.level} "
        f"xp={payload.experience} "
        f"inventory={len(payload.inventory)} reason={payload.disconnect_reason}"
    )

    return ServerCharacterSyncResponse(
        success=True,
        user_id=user.id,
        gold=character.gold,
        level=character.level,
        message="Character synced from game server"
    )


@router.get("/character/{user_id}", response_model=ServerCharacterFetchResponse)
async def server_fetch_character(
    user_id: int,
    db: DbSession = Depends(get_db),
    _: bool = Depends(verify_server_key)
):
    """
    Fetch character data for a user from backend.

    Called when an Ashbane user connects to the game server.
    The server uses this to get authoritative character data
    instead of relying on stale local JSON cache.

    Authentication: X-Server-Key header (server-to-server auth)
    """
    # Find user by Ashbane user_id
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        logger.warning(f"Server fetch for unknown user_id: {user_id}")
        raise HTTPException(status_code=404, detail="User not found")

    # Get active character
    character = db.query(Character).filter(
        Character.user_id == user.id,
        Character.is_active == True
    ).first()

    if not character:
        logger.warning(f"Server fetch - no active character for user {user.id}")
        raise HTTPException(status_code=404, detail="No active character")

    # Extract character data
    data = character.character_data or {}

    logger.info(
        f"[SERVER_FETCH] user={user.id} ({user.username}) "
        f"level={character.level} gold={character.gold} xp={data.get('experience', 0)}"
    )

    return ServerCharacterFetchResponse(
        success=True,
        user_id=user.id,
        gold=character.gold,
        level=character.level,
        experience=data.get("experience", 0),
        inventory=data.get("inventory", []),
        equipped_weapon=data.get("equipped_weapon", ""),
        equipped_armor=data.get("equipped_armor", {}),
        weapon_skills=data.get("weapon_skills", {}),
        strength=data.get("strength", 10),
        agility=data.get("agility", 10),
        dexterity=data.get("dexterity", 10),
        intelligence=data.get("intelligence", 10),
        wisdom=data.get("wisdom", 10),
        vitality=data.get("vitality", 10),
        current_hp=data.get("current_hp", -1.0)
    )


@router.get("/health")
async def server_health_check(
    _: bool = Depends(verify_server_key)
):
    """
    Health check endpoint for game server.

    Can be used by the dedicated server to verify connectivity
    and that the API key is valid.
    """
    return {
        "status": "ok",
        "service": "ashbane-backend",
        "server_auth": "valid"
    }
