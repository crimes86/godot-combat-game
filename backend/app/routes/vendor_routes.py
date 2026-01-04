"""
Vendor purchase routes - Server-side purchase validation.

Validates gold balance and item availability before processing purchases.
Prevents client-side exploits by making the server the source of truth.

See docs/VENDOR_PURCHASE_SPEC.md for full specification.
"""
import json
import logging
from datetime import datetime
from typing import Callable, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session as DbSession

from app.database import SessionLocal
from app.models import User, Character
from app.services.vendor_service import vendor_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/vendor", tags=["vendor"])

# Will be set by init_vendor_routes()
_get_current_user_func: Callable = None
_limiter = None


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
        raise HTTPException(status_code=500, detail="Vendor routes not initialized")
    return _get_current_user_func(request, db)


def init_vendor_routes(get_current_user: Callable, limiter=None):
    """Initialize vendor routes with dependencies from main app."""
    global _get_current_user_func, _limiter
    _get_current_user_func = get_current_user
    _limiter = limiter
    # Pre-load catalogs at startup
    vendor_service.ensure_loaded()
    logger.info("Vendor routes initialized")


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_active_character(user: User, db: DbSession) -> Character:
    """
    Get the active character for a user.

    If no active character exists, creates a default one.
    """
    character = db.query(Character).filter(
        Character.user_id == user.id,
        Character.is_active == True
    ).first()

    if character is None:
        # Auto-create a default character for the user
        character = Character(
            user_id=user.id,
            name=user.username or f"Hero_{user.id}",
            level=1,
            gold=100,
            character_data={},
            is_active=True
        )
        db.add(character)
        db.commit()
        db.refresh(character)
        logger.info(f"Created default character for user {user.id}: {character.name}")

    return character


def add_item_to_inventory(character: Character, item: dict, quantity: int = 1):
    """
    Add purchased item to character's inventory.

    Handles stackable items by incrementing quantity if already owned.
    """
    data = character.character_data or {}

    if "inventory" not in data:
        data["inventory"] = []

    # Check if item is stackable and already exists
    is_stackable = item.get("stackable", False) or item.get("stack_size", 1) > 1
    if is_stackable:
        for inv_item in data["inventory"]:
            if inv_item.get("id") == item["id"]:
                inv_item["quantity"] = inv_item.get("quantity", 1) + quantity
                character.character_data = data
                return

    # Add new item entry
    new_item = {
        "id": item["id"],
        "name": item["name"],
        "type": item.get("type", item.get("weapon_type", item.get("armor_type", "misc"))),
        "quantity": quantity,
        "purchased_at": datetime.utcnow().isoformat(),
    }

    # Include relevant item properties
    if "weapon_type" in item:
        new_item["weapon_type"] = item["weapon_type"]
    if "armor_type" in item:
        new_item["armor_type"] = item["armor_type"]
    if "slot" in item:
        new_item["slot"] = item["slot"]
    if "base_damage" in item:
        new_item["base_damage"] = item["base_damage"]
    if "defense" in item:
        new_item["defense"] = item["defense"]
    if "rarity" in item:
        new_item["rarity"] = item["rarity"]

    data["inventory"].append(new_item)
    character.character_data = data


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class PurchaseRequest(BaseModel):
    """Request body for vendor purchase."""
    item_id: str = Field(..., min_length=1, max_length=64)
    vendor_type: str = Field(..., pattern="^(weapons|armor|misc|tools)$")
    quantity: int = Field(default=1, ge=1, le=99)


class PurchaseResponse(BaseModel):
    """Response for successful purchase."""
    success: bool
    item: Optional[dict] = None
    gold_spent: int = 0
    new_gold_balance: int = 0
    error: Optional[str] = None
    message: Optional[str] = None


class CharacterInfoResponse(BaseModel):
    """Response for character info endpoint."""
    character_id: int
    name: str
    level: int
    gold: int
    inventory_count: int


# =============================================================================
# ENDPOINTS
# =============================================================================

@router.post("/purchase", response_model=PurchaseResponse)
async def purchase_item(
    request: Request,
    purchase: PurchaseRequest,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Purchase an item from a vendor.

    Validates gold balance and item availability, then atomically
    deducts gold and adds item to inventory.

    Rate limited to 30 purchases per minute.
    """
    # Rate limiting
    if _limiter:
        try:
            from slowapi.util import get_remote_address
            _limiter._check_request_limit(request, None, "30/minute", get_remote_address, 1)
        except Exception as e:
            if "Rate limit exceeded" in str(e) or "429" in str(e):
                raise HTTPException(status_code=429, detail="Rate limit exceeded. 30/minute")

    # 1. Validate vendor type (already validated by Pydantic, but double-check)
    if purchase.vendor_type not in vendor_service.get_valid_vendor_types():
        return PurchaseResponse(
            success=False,
            error="INVALID_VENDOR_TYPE",
            message=f"Unknown vendor type: {purchase.vendor_type}"
        )

    # 2. Get item from catalog
    item = vendor_service.get_item(purchase.vendor_type, purchase.item_id)
    if not item:
        return PurchaseResponse(
            success=False,
            error="ITEM_NOT_FOUND",
            message=f"Item not found: {purchase.item_id}"
        )

    # 3. Get player's active character
    character = get_active_character(user, db)

    # 4. Check level requirement
    required_level = item.get("required_level", 1)
    if character.level < required_level:
        return PurchaseResponse(
            success=False,
            error="LEVEL_REQUIREMENT_NOT_MET",
            message=f"Requires level {required_level}, you are level {character.level}"
        )

    # 5. Calculate total cost
    price = vendor_service.get_price(purchase.vendor_type, purchase.item_id)
    total_cost = price * purchase.quantity

    # 6. Check gold balance
    if character.gold < total_cost:
        return PurchaseResponse(
            success=False,
            error="INSUFFICIENT_GOLD",
            message=f"You need {total_cost} gold but only have {character.gold}",
            gold_spent=0,
            new_gold_balance=character.gold
        )

    # 7. Atomic transaction: deduct gold + add item
    try:
        character.gold -= total_cost
        add_item_to_inventory(character, item, purchase.quantity)
        character.last_played_at = datetime.utcnow()
        db.commit()
        db.refresh(character)

        logger.info(
            f"Purchase: user={user.id} char={character.id} item={purchase.item_id} "
            f"qty={purchase.quantity} cost={total_cost} new_balance={character.gold}"
        )

    except Exception as e:
        db.rollback()
        logger.error(f"Purchase failed for user {user.id}: {e}")
        return PurchaseResponse(
            success=False,
            error="PURCHASE_FAILED",
            message="Transaction failed, please try again"
        )

    # 8. Return success with item details
    return PurchaseResponse(
        success=True,
        item=item,
        gold_spent=total_cost,
        new_gold_balance=character.gold
    )


@router.get("/character", response_model=CharacterInfoResponse)
async def get_character_info(
    request: Request,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Get current character's info including gold balance.

    Used by client to sync gold display after login.
    """
    character = get_active_character(user, db)
    data = character.character_data or {}
    inventory = data.get("inventory", [])

    return CharacterInfoResponse(
        character_id=character.id,
        name=character.name,
        level=character.level,
        gold=character.gold,
        inventory_count=len(inventory)
    )


@router.post("/character/sync")
async def sync_character(
    request: Request,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Sync character data from client.

    Updates level and other stats (but NOT gold - that's server-authoritative).
    Used when client logs out or periodically during gameplay.
    """
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON body")

    character = get_active_character(user, db)

    # Update level if provided (but not gold - that's server-side only)
    if "level" in body and isinstance(body["level"], int) and body["level"] >= 1:
        character.level = body["level"]

    # Update character_data (inventory sync from client is allowed for non-purchased items)
    # Note: Server-side purchased items should not be overwritten
    if "character_data" in body and isinstance(body["character_data"], dict):
        # Merge carefully - preserve server-side inventory
        server_data = character.character_data or {}
        client_data = body["character_data"]

        # Keep server inventory, merge other data
        server_inventory = server_data.get("inventory", [])
        character.character_data = {
            **client_data,
            "inventory": server_inventory  # Preserve server inventory
        }

    character.last_played_at = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "character_id": character.id,
        "gold": character.gold,
        "level": character.level
    }


@router.get("/catalog/{vendor_type}")
async def get_vendor_catalog(
    vendor_type: str,
    request: Request,
    user: User = Depends(get_current_user_dep)
):
    """
    Get full catalog for a vendor type.

    Used by client to display shop UI with current prices.
    """
    if vendor_type not in vendor_service.get_valid_vendor_types():
        raise HTTPException(status_code=400, detail=f"Invalid vendor type: {vendor_type}")

    catalog = vendor_service.get_catalog(vendor_type)

    # Include effective prices (with test price fallback)
    items_with_prices = []
    for item_id, item in catalog.items():
        item_copy = dict(item)
        item_copy["effective_price"] = vendor_service.get_price(vendor_type, item_id)
        items_with_prices.append(item_copy)

    return {
        "vendor_type": vendor_type,
        "items": items_with_prices,
        "count": len(items_with_prices)
    }
