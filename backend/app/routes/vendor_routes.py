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
from sqlalchemy import or_
from sqlalchemy.orm import Session as DbSession
from sqlalchemy.orm.attributes import flag_modified

from app.database import SessionLocal
from app.models import User, Character, ForgedAchievement, WalletAccount
from app.services.vendor_service import vendor_service
from app.services.telemetry_service import log_backend_event

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
            gold=0,  # Starting gold is 0 - matches client
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
                flag_modified(character, 'character_data')
                return

    # Add new item entry
    # Determine item type: weapons have weapon_type, armor has armor_type
    is_weapon = "weapon_type" in item
    is_armor = "armor_type" in item

    # Set type correctly: "weapon" for weapons, "armor" for armor, else use item's type field
    if is_weapon:
        item_type = "weapon"
    elif is_armor:
        item_type = "armor"
    else:
        item_type = item.get("type", "misc")

    new_item = {
        "id": item["id"],
        "name": item["name"],
        "type": item_type,
        "quantity": quantity,
        "purchased_at": datetime.utcnow().isoformat(),
    }

    # Include relevant item properties
    if "weapon_type" in item:
        new_item["weapon_type"] = item["weapon_type"]
        # Weapons always go in mainhand slot
        new_item["slot"] = item.get("slot", "mainhand")
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
    if "attack_speed" in item:
        new_item["attack_speed"] = item["attack_speed"]
    if "required_level" in item:
        new_item["required_level"] = item["required_level"]
    if "description" in item:
        new_item["description"] = item["description"]
    if "price" in item:
        # Store sell value as half of purchase price
        new_item["value"] = max(1, int(item["price"] * 0.5))
    # Healing weapon properties
    if "attack_mode" in item:
        new_item["attack_mode"] = item["attack_mode"]
    if "healing_power" in item:
        new_item["healing_power"] = item["healing_power"]
    if "heal_radius" in item:
        new_item["heal_radius"] = item["heal_radius"]

    data["inventory"].append(new_item)
    character.character_data = data
    flag_modified(character, 'character_data')


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

        # Log telemetry event
        log_backend_event(
            db=db,
            user_id=user.id,
            character_id=character.id,
            event_type="vendor_purchase",
            event_data={
                "item_id": purchase.item_id,
                "item_name": item.get("name", "Unknown"),
                "vendor_type": purchase.vendor_type,
                "quantity": purchase.quantity,
                "gold_spent": total_cost,
                "new_balance": character.gold
            },
            ip_address=request.client.host if request.client else None
        )
        db.commit()  # Commit telemetry event

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


class SellRequest(BaseModel):
    """Request body for vendor sell."""
    item_id: str = Field(..., min_length=1, max_length=64)
    vendor_type: str = Field(..., pattern="^(weapons|armor|misc|tools|loot)$")
    quantity: int = Field(default=1, ge=1, le=99)
    # Keep item_name for logging/display (optional, not trusted for value)
    item_name: str = Field(default="Item")


class SellResponse(BaseModel):
    """Response for successful sale."""
    success: bool
    gold_earned: int = 0
    new_gold_balance: int = 0
    error: Optional[str] = None
    message: Optional[str] = None


# Sell value multiplier (items sell for 50% of purchase price)
SELL_VALUE_MULTIPLIER = 0.5

# Maximum sell value per item (anti-exploit cap)
MAX_SELL_VALUE_PER_ITEM = 10000

# Loot item base values by rarity (for items not in shop catalog)
LOOT_BASE_VALUES = {
    "common": 1,
    "uncommon": 3,
    "rare": 8,
    "epic": 20,
    "legendary": 50,
}


@router.post("/sell", response_model=SellResponse)
async def sell_item(
    request: Request,
    sell: SellRequest,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Sell an item to vendor - validates item and calculates gold server-side.

    Security: Server determines sell value from its own catalog, never trusts client.
    Items sell for 50% of their purchase price (SELL_VALUE_MULTIPLIER).
    Loot items use rarity-based values since they're not in shop catalog.
    """
    character = get_active_character(user, db)

    # Calculate server-authoritative sell value
    sell_value = 0

    if sell.vendor_type == "loot":
        # Loot items aren't in shop catalog - use rarity-based values
        # Client must send item_id in format "item_name" or with rarity suffix
        # For safety, use minimum loot value
        sell_value = LOOT_BASE_VALUES.get("common", 1) * sell.quantity
        logger.info(f"Loot sell: {sell.item_name} x{sell.quantity} = {sell_value}g (base loot value)")
    else:
        # Look up item in server catalog
        item = vendor_service.get_item(sell.vendor_type, sell.item_id)

        if item is None:
            # Item not in catalog - could be a loot drop or invalid
            # Allow minimal value for unknown items (1g each) to not break gameplay
            sell_value = 1 * sell.quantity
            logger.warning(
                f"Sell unknown item: user={user.id} item_id={sell.item_id} "
                f"type={sell.vendor_type} - awarding minimal value {sell_value}g"
            )
        else:
            # Calculate sell value from catalog price
            buy_price = item.get("price", 0)
            item_sell_value = int(buy_price * SELL_VALUE_MULTIPLIER)

            # Cap per-item sell value
            item_sell_value = min(item_sell_value, MAX_SELL_VALUE_PER_ITEM)

            sell_value = item_sell_value * sell.quantity

    # Final safety cap
    sell_value = min(sell_value, MAX_SELL_VALUE_PER_ITEM * sell.quantity)

    # Add gold
    character.gold += sell_value
    character.last_played_at = datetime.utcnow()

    # Log telemetry event
    log_backend_event(
        db=db,
        user_id=user.id,
        character_id=character.id,
        event_type="vendor_sell",
        event_data={
            "item_id": sell.item_id,
            "item_name": sell.item_name,
            "vendor_type": sell.vendor_type,
            "quantity": sell.quantity,
            "gold_earned": sell_value,
            "new_balance": character.gold
        },
        ip_address=request.client.host if request.client else None
    )

    db.commit()
    db.refresh(character)

    logger.info(
        f"Sell: user={user.id} char={character.id} item={sell.item_id} ({sell.item_name}) "
        f"qty={sell.quantity} value={sell_value}g new_balance={character.gold}"
    )

    return SellResponse(
        success=True,
        gold_earned=sell_value,
        new_gold_balance=character.gold,
        message=f"Sold {sell.item_name} for {sell_value} gold"
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


class LogoutSyncRequest(BaseModel):
    """Request body for full character sync on logout."""
    gold: int = Field(..., ge=0, le=999999999)
    level: int = Field(..., ge=1, le=100)
    experience: int = Field(default=0, ge=0, le=999999999)
    inventory: list = []
    equipped_weapon: str = ""
    equipped_armor: dict = {}  # slot -> armor_id mapping
    weapon_skills: dict = {}  # category -> skill value (0.0 to 300.0)


class LogoutSyncResponse(BaseModel):
    """Response for logout sync."""
    success: bool
    message: str
    gold: int = 0
    level: int = 1


@router.post("/character/logout-sync", response_model=LogoutSyncResponse)
async def logout_sync(
    payload: LogoutSyncRequest,
    request: Request,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Full character sync on logout - saves everything for persistent world.

    Called when player disconnects to save:
    - Gold (from all sources: loot, chests, harvesting)
    - Level and experience
    - Full inventory (looted items, harvested materials, etc.)
    - Equipped items

    Note: This trusts client data since user is authenticated.
    Anti-cheat measures should be server-side during gameplay, not at save time.
    """
    character = get_active_character(user, db)

    # Update gold (accept client value - persistent world)
    character.gold = payload.gold

    # Update level (with sanity cap)
    character.level = min(payload.level, 100)

    # Update character_data with full inventory and equipment
    data = character.character_data or {}
    data["experience"] = payload.experience
    data["equipped_weapon"] = payload.equipped_weapon
    data["equipped_armor"] = payload.equipped_armor
    data["weapon_skills"] = payload.weapon_skills  # Weapon skill mastery

    # Trust client inventory - user is authenticated, respect their sales/deletions
    # But preserve purchased_at metadata from server for provenance tracking
    server_inventory = data.get("inventory", [])

    # Build lookup of server items with purchased_at metadata
    server_metadata = {}
    for item in server_inventory:
        item_id = item.get("id")
        if item_id and item.get("purchased_at"):
            server_metadata[item_id] = item.get("purchased_at")

    # Trust client inventory, preserving purchased_at metadata where applicable
    final_inventory = []
    for item in payload.inventory:
        # Convert to dict if needed (Pydantic model or dict)
        item_dict = dict(item) if hasattr(item, '__iter__') and not isinstance(item, dict) else item
        if hasattr(item, 'dict'):
            item_dict = item.dict()
        elif hasattr(item, 'model_dump'):
            item_dict = item.model_dump()
        else:
            item_dict = dict(item) if not isinstance(item, dict) else item

        item_id = item_dict.get("id")

        # Preserve purchased_at metadata from server if not already present
        if item_id and item_id in server_metadata and "purchased_at" not in item_dict:
            item_dict["purchased_at"] = server_metadata[item_id]

        final_inventory.append(item_dict)

    data["inventory"] = final_inventory

    character.character_data = data
    character.last_played_at = datetime.utcnow()
    flag_modified(character, 'character_data')

    # Log telemetry event
    log_backend_event(
        db=db,
        user_id=user.id,
        character_id=character.id,
        event_type="character_save",
        event_data={
            "gold": character.gold,
            "level": character.level,
            "experience": payload.experience,
            "inventory_count": len(final_inventory),
            "server_items_before": len(server_inventory),
            "metadata_preserved": len(server_metadata),
            "equipped_weapon": payload.equipped_weapon,
        },
        ip_address=request.client.host if request.client else None
    )

    db.commit()
    db.refresh(character)

    logger.info(
        f"[LOGOUT_SYNC] User {user.id}: gold={character.gold}, level={character.level}, "
        f"inventory={len(final_inventory)} items (was {len(server_inventory)}, preserved {len(server_metadata)} purchase timestamps)"
    )

    return LogoutSyncResponse(
        success=True,
        message="Character saved",
        gold=character.gold,
        level=character.level
    )


class CharacterInitializeRequest(BaseModel):
    gold: int = 0
    level: int = 1
    experience: int = 0
    inventory: list = []
    equipped_weapon: str = ""


class CharacterInitializeResponse(BaseModel):
    success: bool
    message: str
    character: dict


@router.post("/character/initialize", response_model=CharacterInitializeResponse)
async def initialize_character(
    payload: CharacterInitializeRequest,
    request: Request,
    db: DbSession = Depends(get_db),
    user: User = Depends(get_current_user_dep)
):
    """
    Initialize character with guest progress (only if character is brand new).

    Called when a guest user authenticates mid-game to preserve their progress.
    If character already exists with progress, returns existing character data.
    """
    character = get_active_character(user, db)

    # Check if this is a "played" character (not brand new)
    # Check multiple indicators: level, gold, inventory, forge items, or any prior play

    # ForgedAchievement uses wallet_account_id (for forger) and current_owner_id (for trades)
    # Items owned by user: forged by them (current_owner_id NULL) OR traded to them (current_owner_id == user.id)

    # Count items user currently owns (either forged or received via trade)
    forge_items_count = db.query(ForgedAchievement).join(
        WalletAccount, ForgedAchievement.wallet_account_id == WalletAccount.id
    ).filter(
        or_(
            # Items forged by user and still owned (current_owner_id is NULL)
            (WalletAccount.user_id == user.id) & (ForgedAchievement.current_owner_id == None),
            # Items traded to user
            ForgedAchievement.current_owner_id == user.id
        )
    ).count()

    has_forge_items = forge_items_count > 0
    has_played_before = character.last_played_at is not None
    inventory_len = len((character.character_data or {}).get("inventory", []))

    # Debug logging
    logger.info(f"[GUEST_INIT] User {user.id} ({user.username}): level={character.level}, gold={character.gold}, "
                f"inventory_len={inventory_len}, forge_items={forge_items_count}, "
                f"last_played={character.last_played_at}")

    is_existing_character = (
        character.level > 1 or
        character.gold > 0 or  # Starting gold is 0
        inventory_len > 0 or
        has_forge_items or
        has_played_before
    )

    logger.info(f"[GUEST_INIT] User {user.id}: is_existing={is_existing_character} "
                f"(level>1:{character.level > 1}, gold>0:{character.gold > 0}, "
                f"inv:{inventory_len > 0}, forge:{has_forge_items}, played:{has_played_before})")
    
    if is_existing_character:
        # Return existing character with full data - don't overwrite with guest data
        logger.info(f"User {user.id} has existing character (level {character.level}, {character.gold} gold) - not applying guest progress")
        char_data = character.character_data or {}

        # Log telemetry event for character load
        log_backend_event(
            db=db,
            user_id=user.id,
            character_id=character.id,
            event_type="character_load",
            event_data={
                "gold": character.gold,
                "level": character.level,
                "experience": char_data.get("experience", 0),
                "inventory_count": len(char_data.get("inventory", [])),
                "is_new": False,
                "has_forge_items": has_forge_items,
            },
            ip_address=request.client.host if request.client else None
        )
        db.commit()

        return CharacterInitializeResponse(
            success=True,
            message="Existing character loaded",
            character={
                "gold": character.gold,
                "level": character.level,
                "experience": char_data.get("experience", 0),
                "inventory": char_data.get("inventory", []),
                "equipped_weapon": char_data.get("equipped_weapon", ""),
                "equipped_armor": char_data.get("equipped_armor", {}),
                "weapon_skills": char_data.get("weapon_skills", {}),
                "is_new": False
            }
        )
    
    # Apply guest progress with caps (anti-cheat)
    capped_gold = min(payload.gold, 1000)  # Cap at 1000 gold
    capped_level = min(payload.level, 5)   # Cap at level 5
    capped_xp = min(payload.experience, 2000)  # Cap XP
    
    character.gold = max(capped_gold, character.gold)  # Take higher value
    character.level = max(capped_level, character.level)
    
    # Update character_data with experience
    data = character.character_data or {}
    data["experience"] = capped_xp
    data["equipped_weapon"] = payload.equipped_weapon
    character.character_data = data
    flag_modified(character, 'character_data')

    # Log telemetry event for new character initialization
    log_backend_event(
        db=db,
        user_id=user.id,
        character_id=character.id,
        event_type="character_load",
        event_data={
            "gold": character.gold,
            "level": character.level,
            "experience": capped_xp,
            "inventory_count": 0,
            "is_new": True,
            "guest_gold": payload.gold,
            "guest_level": payload.level,
        },
        ip_address=request.client.host if request.client else None
    )

    db.commit()

    logger.info(f"Initialized character for user {user.id} with guest progress: level {character.level}, {character.gold} gold")
    
    return CharacterInitializeResponse(
        success=True,
        message="Character initialized with guest progress",
        character={
            "gold": character.gold,
            "level": character.level,
            "experience": capped_xp,
            "is_new": True
        }
    )
