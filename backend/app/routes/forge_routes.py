"""
Forge item destruction and management routes.

Endpoints for destroying and unclaiming forged items from the game.
Game client calls these when items are deleted/sold.
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session as DbSession
from pydantic import BaseModel
from typing import Optional, Callable
from datetime import datetime
import logging
import os

from app.models import User, ForgedAchievement, AchievementCredit, WalletAccount, BridgeStatus
from app.database import SessionLocal
from app.services.telemetry_service import log_backend_event


logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/forge", tags=["forge"])

# Dependencies set by init_forge_routes()
_get_current_user_func: Callable = None
_get_admin_user_func: Callable = None

# Gold values for vendor sales (by rarity)
VENDOR_SELL_VALUES = {
    "common": 50,
    "uncommon": 150,
    "rare": 300,
    "epic": 600,
    "legendary": 1200,
}

# Treasury user ID for destroyed items (set via env or defaults to system user 1)
TREASURY_USER_ID = int(os.getenv("TREASURY_USER_ID", "1"))


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
        raise HTTPException(status_code=500, detail="Forge routes not initialized")
    return _get_current_user_func(request, db)


def get_admin_user_dep(request: Request, db: DbSession = Depends(get_db)):
    """Get admin user - wraps the main app's admin auth logic."""
    if _get_admin_user_func is None:
        raise HTTPException(status_code=500, detail="Forge routes not initialized")
    return _get_admin_user_func(request, db)


def init_forge_routes(get_current_user: Callable, get_admin_user: Callable = None):
    """Initialize forge routes with dependencies from main app."""
    global _get_current_user_func, _get_admin_user_func
    _get_current_user_func = get_current_user
    _get_admin_user_func = get_admin_user
    logger.info("Forge routes initialized")


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class DestroyRequest(BaseModel):
    token_id: int
    reason: str  # player_delete, vendor_sale, dropped_decay


class DestroyResponse(BaseModel):
    success: bool
    gold_received: int = 0
    item_name: str
    transferred_to: str = "treasury"


class UnclaimRequest(BaseModel):
    token_id: int


class UnclaimResponse(BaseModel):
    success: bool
    item_name: str


class RestoreRequest(BaseModel):
    token_id: int
    restore_to_user_id: Optional[int] = None  # Defaults to original owner
    reason: str  # e.g., "Support ticket #1234"


# =============================================================================
# ITEM DESTRUCTION ENDPOINTS
# =============================================================================

@router.post("/destroy")
async def destroy_forged_item(
    request_body: DestroyRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Permanently destroy a forged item (soft delete).

    Used when:
    - Player deletes item from inventory (drag to trash)
    - Player sells item to vendor
    - (Future) Item decays after being dropped

    Items are soft-deleted and transferred to treasury for potential restoration.
    """
    current_user = get_current_user_dep(request, db)

    # Validate reason
    valid_reasons = ["player_delete", "vendor_sale", "dropped_decay"]
    if request_body.reason not in valid_reasons:
        raise HTTPException(status_code=400, detail=f"Invalid reason. Must be one of: {valid_reasons}")

    # Find the item by token_id (not destroyed)
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request_body.token_id,
        ForgedAchievement.destroyed_at.is_(None)
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    # Check ownership - try current_owner_id, then achievement_credit owner, then wallet owner
    owner_id = forged.current_owner_id
    if not owner_id and forged.achievement_credit_id:
        owner_id = db.query(AchievementCredit.user_id).filter(
            AchievementCredit.id == forged.achievement_credit_id
        ).scalar()
    if not owner_id and forged.wallet_account_id:
        owner_id = db.query(WalletAccount.user_id).filter(
            WalletAccount.id == forged.wallet_account_id
        ).scalar()

    if owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not owned by you")

    # Check item is claimed in game (can't destroy unclaimed items via game)
    if not forged.claimed_in_game_at:
        raise HTTPException(status_code=400, detail="Item not claimed in game")

    # Check bridge status (can't destroy bridged items)
    if forged.bridge_status != BridgeStatus.IN_GAME.value:
        raise HTTPException(status_code=400, detail="Cannot destroy bridged item")

    # Calculate gold for vendor sales
    gold_received = 0
    if request_body.reason == "vendor_sale":
        rarity = (forged.item_rarity or "common").lower()
        gold_received = VENDOR_SELL_VALUES.get(rarity, 100)

    # Soft delete - transfer to treasury
    forged.previous_owner_id = owner_id
    forged.destroyed_at = datetime.utcnow()
    forged.destroyed_reason = request_body.reason
    forged.destroyed_by_user_id = current_user.id
    forged.current_owner_id = TREASURY_USER_ID
    forged.claimed_in_game_at = None  # No longer in anyone's inventory

    # Log telemetry for item destruction
    log_backend_event(
        db=db,
        user_id=current_user.id,
        character_id=0,
        event_type="forged_item_destroy",
        event_data={
            "token_id": forged.token_id,
            "item_id": forged.item_id,
            "item_name": forged.item_name,
            "item_rarity": forged.item_rarity,
            "reason": request_body.reason,
            "gold_received": gold_received,
        },
        ip_address=request.client.host if request.client else None
    )

    db.commit()

    logger.info(f"User {current_user.username} destroyed item {forged.item_name} (token_id={forged.token_id}, reason={request_body.reason})")

    return DestroyResponse(
        success=True,
        gold_received=gold_received,
        item_name=forged.item_name or "Unknown Item",
        transferred_to="treasury"
    )


@router.post("/unclaim-from-game")
async def unclaim_from_game(
    request_body: UnclaimRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Unclaim item from game inventory.

    Item still exists, can be re-claimed from Armory.
    Use case: "Stash" functionality, or softer removal option.
    """
    current_user = get_current_user_dep(request, db)

    # Find the item by token_id (not destroyed)
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request_body.token_id,
        ForgedAchievement.destroyed_at.is_(None)
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    # Check ownership
    owner_id = forged.current_owner_id
    if not owner_id and forged.achievement_credit_id:
        owner_id = db.query(AchievementCredit.user_id).filter(
            AchievementCredit.id == forged.achievement_credit_id
        ).scalar()
    if not owner_id and forged.wallet_account_id:
        owner_id = db.query(WalletAccount.user_id).filter(
            WalletAccount.id == forged.wallet_account_id
        ).scalar()

    if owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not owned by you")

    # Unclaim from game
    forged.claimed_in_game_at = None
    db.commit()

    logger.info(f"User {current_user.username} unclaimed item {forged.item_name} from game")

    return UnclaimResponse(
        success=True,
        item_name=forged.item_name or "Unknown Item"
    )


# =============================================================================
# ADMIN ENDPOINTS
# =============================================================================

@router.post("/admin/restore")
async def admin_restore_item(
    request_body: RestoreRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """
    Admin endpoint to restore a destroyed item.

    Used for support tickets where a player accidentally deleted an item.
    """
    if _get_admin_user_func is None:
        raise HTTPException(status_code=501, detail="Admin auth not configured")

    admin_user = get_admin_user_dep(request, db)
    if not admin_user:
        raise HTTPException(status_code=403, detail="Admin access required")

    # Find destroyed item by token_id
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request_body.token_id,
        ForgedAchievement.destroyed_at.isnot(None)
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Destroyed item not found")

    # Determine restore target
    restore_to = request_body.restore_to_user_id or forged.previous_owner_id
    if not restore_to:
        raise HTTPException(status_code=400, detail="No user to restore to (no previous owner)")

    # Verify target user exists
    target_user = db.query(User).filter(User.id == restore_to).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    # Restore item
    forged.destroyed_at = None
    forged.destroyed_reason = None
    forged.destroyed_by_user_id = None
    forged.current_owner_id = restore_to
    forged.previous_owner_id = None
    forged.claimed_in_game_at = None  # Must re-claim from Armory

    db.commit()

    logger.info(f"Admin {admin_user.username} restored item {forged.item_name} to user {target_user.username} (reason: {request_body.reason})")

    return {
        "success": True,
        "restored": {
            "token_id": forged.token_id,
            "item_name": forged.item_name,
            "restored_to_user": target_user.username,
            "restored_to_user_id": restore_to,
        },
        "note": "Item must be re-claimed from Armory"
    }
