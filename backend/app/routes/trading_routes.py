"""
Trading routes for forged item exchange.

Live trading system - players must be in proximity to trade.
Chat-based advertising populates a "Recently Advertised" list.

See docs/FORGE_ECONOMY_DESIGN.md for full specification.
"""
from fastapi import APIRouter, Depends, HTTPException, Request, Query
from sqlalchemy.orm import Session as DbSession
from sqlalchemy import and_, or_
from pydantic import BaseModel
from typing import Optional, List, Callable
from datetime import datetime, timedelta
import logging

from app.models import (
    User, ForgedAchievement, ItemTrade, TradeListing, WalletAccount
)
from app.database import SessionLocal

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/trades", tags=["trading"])

# Constants
TRADE_COOLDOWN_HOURS = 24
LISTING_EXPIRY_MINUTES = 30
LISTING_COOLDOWN_SECONDS = 30
TRADE_TAX_PERCENT = 5
MAX_TRADES_PER_DAY = 10

# Will be set by init_trading_routes()
_get_current_user_func: Callable = None


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
        raise HTTPException(status_code=500, detail="Trading routes not initialized")
    return _get_current_user_func(request, db)


def init_trading_routes(get_current_user: Callable):
    """Initialize trading routes with dependencies from main app."""
    global _get_current_user_func
    _get_current_user_func = get_current_user
    logger.info("Trading routes initialized")


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class DirectTradeRequest(BaseModel):
    token_id: int
    to_user_id: int
    price_gold: int = 0


class DirectTradeResponse(BaseModel):
    success: bool
    trade_id: int
    item: dict
    gold_transferred: int
    tax_applied: int
    provenance_updated: bool


class TradeHistoryItem(BaseModel):
    trade_id: int
    traded_at: str
    role: str  # "seller" or "buyer"
    item: dict
    counterparty_display: str
    price_gold: int


class TradeHistoryResponse(BaseModel):
    trades: List[TradeHistoryItem]
    total: int


class CreateListingRequest(BaseModel):
    token_id: int
    listing_type: str = "sell"  # sell or buy
    price_gold: int
    message: Optional[str] = None
    zone_id: Optional[str] = None
    position_x: Optional[float] = None
    position_y: Optional[float] = None


class CreateListingResponse(BaseModel):
    success: bool
    listing_id: int
    expires_at: str
    broadcast_to: str


class ListingItem(BaseModel):
    listing_id: int
    listing_type: str
    item: dict
    price_gold: int
    seller: dict
    message: Optional[str]
    posted_at: str
    expires_at: str


class ActiveListingsResponse(BaseModel):
    listings: List[ListingItem]


class CooldownResponse(BaseModel):
    token_id: int
    tradeable: bool
    cooldown_ends: Optional[str] = None
    seconds_remaining: Optional[int] = None


class CensusItem(BaseModel):
    item_id: str
    item_name: str
    total_forged: int
    in_game: int
    first_forged: Optional[str]


class CensusResponse(BaseModel):
    items: List[CensusItem]
    total_items: int


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_item_owner(forged: ForgedAchievement, db: DbSession) -> User:
    """Get the current owner of a forged item."""
    if forged.current_owner_id:
        return db.query(User).filter(User.id == forged.current_owner_id).first()
    # If no current_owner_id, owner is the original forger
    wallet = db.query(WalletAccount).filter(WalletAccount.id == forged.wallet_account_id).first()
    if wallet:
        return db.query(User).filter(User.id == wallet.user_id).first()
    return None


def check_trade_cooldown(forged: ForgedAchievement) -> tuple[bool, Optional[datetime]]:
    """Check if item is on trade cooldown. Returns (is_tradeable, cooldown_ends)."""
    if not forged.last_trade_at:
        return True, None

    cooldown_ends = forged.last_trade_at + timedelta(hours=TRADE_COOLDOWN_HOURS)
    if datetime.utcnow() >= cooldown_ends:
        return True, None

    return False, cooldown_ends


def calculate_tax(price_gold: int) -> int:
    """Calculate 5% trade tax."""
    return int(price_gold * TRADE_TAX_PERCENT / 100)


def _announce_legendary_trade(forged, seller, buyer, price_gold: int) -> None:
    """
    Announce a legendary/epic item trade to global chat.
    This creates excitement and FOMO for rare items.
    """
    try:
        # Import chat module to broadcast
        from app.routes.chat_routes import broadcast_system_message

        rarity = forged.item_rarity or "Legendary"
        item_name = forged.item_name or "Unknown Item"
        seller_name = seller.username if seller else "Unknown"
        buyer_name = buyer.username if buyer else "Unknown"

        # Format price
        if price_gold > 0:
            price_str = f" for {price_gold:,}g"
        else:
            price_str = " as a gift"

        # Build announcement message
        if rarity == "Legendary":
            message = f"[LEGENDARY TRADE] {buyer_name} acquired {item_name} from {seller_name}{price_str}!"
        else:
            message = f"[EPIC TRADE] {buyer_name} acquired {item_name} from {seller_name}{price_str}!"

        # Broadcast to global chat
        broadcast_system_message(message, "trade_announcement")
        logger.info(f"Trade announcement sent: {message}")

    except Exception as e:
        # Don't fail the trade if announcement fails
        logger.warning(f"Failed to announce trade: {e}")


# =============================================================================
# ROUTES
# =============================================================================

@router.post("/direct", response_model=DirectTradeResponse)
async def record_direct_trade(
    request: DirectTradeRequest,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Record a direct trade between two players.
    Godot validates proximity before calling this endpoint.

    - 5% gold tax applied to seller
    - 24-hour trade cooldown starts for buyer
    - Provenance updated (batched to chain later)
    """
    # Find the forged item by token_id
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request.token_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    # Verify current user owns the item
    owner = get_item_owner(forged, db)
    if not owner or owner.id != current_user.id:
        raise HTTPException(status_code=403, detail="You don't own this item")

    # Check trade cooldown
    is_tradeable, cooldown_ends = check_trade_cooldown(forged)
    if not is_tradeable:
        raise HTTPException(
            status_code=400,
            detail=f"Item on cooldown until {cooldown_ends.isoformat()}"
        )

    # Verify recipient exists
    recipient = db.query(User).filter(User.id == request.to_user_id).first()
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    if recipient.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot trade with yourself")

    # Calculate tax
    tax = calculate_tax(request.price_gold)
    gold_after_tax = request.price_gold - tax

    # Create trade record
    trade = ItemTrade(
        forged_item_id=forged.id,
        from_user_id=current_user.id,
        to_user_id=recipient.id,
        price_gold=request.price_gold,
        tax_applied=tax,
        trade_type='direct'
    )
    db.add(trade)

    # Update item ownership
    forged.current_owner_id = recipient.id
    forged.owned_since = datetime.utcnow()
    forged.trade_count += 1
    forged.last_trade_at = datetime.utcnow()

    # Remove any active listing for this item
    db.query(TradeListing).filter(
        TradeListing.forged_item_id == forged.id
    ).delete()

    db.commit()
    db.refresh(trade)

    logger.info(f"Trade completed: {forged.item_name} from {current_user.username} to {recipient.username} for {request.price_gold}g")

    # Announce legendary trades to global chat
    if forged.item_rarity in ["Legendary", "Epic"]:
        _announce_legendary_trade(forged, current_user, recipient, request.price_gold)

    return DirectTradeResponse(
        success=True,
        trade_id=trade.id,
        item={
            "token_id": forged.token_id,
            "item_id": forged.item_id,
            "new_owner_id": recipient.id
        },
        gold_transferred=gold_after_tax,
        tax_applied=tax,
        provenance_updated=True
    )


@router.get("/history", response_model=TradeHistoryResponse)
async def get_trade_history(
    limit: int = Query(default=50, le=100),
    offset: int = Query(default=0, ge=0),
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """Get trade history for the current user."""
    # Get trades where user was buyer or seller
    trades = db.query(ItemTrade).filter(
        or_(
            ItemTrade.from_user_id == current_user.id,
            ItemTrade.to_user_id == current_user.id
        )
    ).order_by(ItemTrade.traded_at.desc()).offset(offset).limit(limit).all()

    total = db.query(ItemTrade).filter(
        or_(
            ItemTrade.from_user_id == current_user.id,
            ItemTrade.to_user_id == current_user.id
        )
    ).count()

    result = []
    for trade in trades:
        forged = trade.forged_item
        is_seller = trade.from_user_id == current_user.id
        counterparty = trade.to_user if is_seller else trade.from_user

        result.append(TradeHistoryItem(
            trade_id=trade.id,
            traded_at=trade.traded_at.isoformat(),
            role="seller" if is_seller else "buyer",
            item={
                "token_id": forged.token_id,
                "item_id": forged.item_id,
                "item_name": forged.item_name
            },
            counterparty_display=counterparty.username if counterparty else "Unknown",
            price_gold=trade.price_gold or 0
        ))

    return TradeHistoryResponse(trades=result, total=total)


@router.post("/listing", response_model=CreateListingResponse)
async def create_listing(
    request: CreateListingRequest,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Create a trade listing (chat auction).
    Listings expire after 30 minutes.
    """
    # Find the forged item
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == request.token_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    # Verify ownership
    owner = get_item_owner(forged, db)
    if not owner or owner.id != current_user.id:
        raise HTTPException(status_code=403, detail="You don't own this item")

    # Check trade cooldown
    is_tradeable, cooldown_ends = check_trade_cooldown(forged)
    if not is_tradeable:
        raise HTTPException(
            status_code=400,
            detail=f"Item on cooldown until {cooldown_ends.isoformat()}"
        )

    # Check for existing listing
    existing = db.query(TradeListing).filter(
        TradeListing.forged_item_id == forged.id,
        TradeListing.seller_id == current_user.id,
        TradeListing.expires_at > datetime.utcnow()
    ).first()

    if existing:
        # Update existing listing
        existing.price_gold = request.price_gold
        existing.message = request.message
        existing.zone_id = request.zone_id
        existing.position_x = request.position_x
        existing.position_y = request.position_y
        existing.posted_at = datetime.utcnow()
        existing.expires_at = datetime.utcnow() + timedelta(minutes=LISTING_EXPIRY_MINUTES)
        db.commit()

        return CreateListingResponse(
            success=True,
            listing_id=existing.id,
            expires_at=existing.expires_at.isoformat(),
            broadcast_to="trade_chat"
        )

    # Create new listing
    listing = TradeListing(
        forged_item_id=forged.id,
        seller_id=current_user.id,
        listing_type=request.listing_type,
        price_gold=request.price_gold,
        message=request.message,
        zone_id=request.zone_id,
        position_x=request.position_x,
        position_y=request.position_y,
        expires_at=datetime.utcnow() + timedelta(minutes=LISTING_EXPIRY_MINUTES)
    )
    db.add(listing)
    db.commit()
    db.refresh(listing)

    logger.info(f"Listing created: {forged.item_name} for {request.price_gold}g by {current_user.username}")

    return CreateListingResponse(
        success=True,
        listing_id=listing.id,
        expires_at=listing.expires_at.isoformat(),
        broadcast_to="trade_chat"
    )


@router.get("/listings", response_model=ActiveListingsResponse)
async def get_active_listings(
    zone_id: Optional[str] = Query(default=None),
    db: DbSession = Depends(get_db)
):
    """
    Get active trade listings (Recently Advertised).
    Public endpoint - no auth required.
    Optionally filter by zone.
    """
    query = db.query(TradeListing).filter(
        TradeListing.expires_at > datetime.utcnow()
    )

    if zone_id:
        query = query.filter(TradeListing.zone_id == zone_id)

    listings = query.order_by(TradeListing.posted_at.desc()).limit(50).all()

    result = []
    for listing in listings:
        forged = listing.forged_item
        seller = listing.seller

        result.append(ListingItem(
            listing_id=listing.id,
            listing_type=listing.listing_type,
            item={
                "token_id": forged.token_id,
                "item_id": forged.item_id,
                "item_name": forged.item_name,
                "rarity": forged.item_rarity
            },
            price_gold=listing.price_gold,
            seller={
                "user_id": seller.id,
                "display_name": seller.username,
                "position": {
                    "x": listing.position_x,
                    "y": listing.position_y
                } if listing.position_x else None
            },
            message=listing.message,
            posted_at=listing.posted_at.isoformat(),
            expires_at=listing.expires_at.isoformat()
        ))

    return ActiveListingsResponse(listings=result)


@router.delete("/listing/{listing_id}")
async def cancel_listing(
    listing_id: int,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """Cancel an active trade listing."""
    listing = db.query(TradeListing).filter(
        TradeListing.id == listing_id
    ).first()

    if not listing:
        raise HTTPException(status_code=404, detail="Listing not found")

    if listing.seller_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not your listing")

    db.delete(listing)
    db.commit()

    return {"success": True}


@router.get("/cooldown/{token_id}", response_model=CooldownResponse)
async def get_trade_cooldown(
    token_id: int,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """Check if an item is on trade cooldown."""
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == token_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    is_tradeable, cooldown_ends = check_trade_cooldown(forged)

    if is_tradeable:
        return CooldownResponse(token_id=token_id, tradeable=True)

    seconds_remaining = int((cooldown_ends - datetime.utcnow()).total_seconds())
    return CooldownResponse(
        token_id=token_id,
        tradeable=False,
        cooldown_ends=cooldown_ends.isoformat(),
        seconds_remaining=seconds_remaining
    )


@router.get("/census", response_model=CensusResponse)
async def get_item_census(db: DbSession = Depends(get_db)):
    """
    Get census of all forged items (public endpoint).
    Shows total counts per item type.
    """
    from sqlalchemy import func

    # Group by item_id and count
    results = db.query(
        ForgedAchievement.item_id,
        ForgedAchievement.item_name,
        func.count(ForgedAchievement.id).label('total'),
        func.min(ForgedAchievement.forged_at).label('first_forged')
    ).filter(
        ForgedAchievement.item_id.isnot(None)
    ).group_by(
        ForgedAchievement.item_id,
        ForgedAchievement.item_name
    ).all()

    items = []
    total = 0
    for r in results:
        count = r.total
        total += count
        items.append(CensusItem(
            item_id=r.item_id,
            item_name=r.item_name or r.item_id,
            total_forged=count,
            in_game=count,  # For now, all are in-game (no bridge-out yet)
            first_forged=r.first_forged.isoformat() if r.first_forged else None
        ))

    # Sort by total_forged descending
    items.sort(key=lambda x: x.total_forged, reverse=True)

    return CensusResponse(items=items, total_items=total)


# =============================================================================
# PROVENANCE ENDPOINT
# =============================================================================

class ProvenanceUserInfo(BaseModel):
    user_id: int
    username: str


class ProvenanceTradeInfo(BaseModel):
    trade_id: int
    traded_at: str
    from_user: ProvenanceUserInfo
    to_user: ProvenanceUserInfo
    price_gold: int


class ProvenanceResponse(BaseModel):
    token_id: int
    item_id: str
    item_name: str
    item_rarity: str
    forger: ProvenanceUserInfo
    forged_at: str
    current_owner: ProvenanceUserInfo
    owned_since: Optional[str]
    trade_count: int
    trades: List[ProvenanceTradeInfo]
    is_on_chain: bool
    contract_address: Optional[str]


@router.get("/provenance/{token_id}", response_model=ProvenanceResponse)
async def get_item_provenance(
    token_id: int,
    db: DbSession = Depends(get_db),
    current_user: User = Depends(get_current_user_dep)
):
    """
    Get full provenance (ownership history) for a forged item.
    Includes forger, trade history, and chain verification status.
    """
    import os

    # Find the forged item
    forged = db.query(ForgedAchievement).filter(
        ForgedAchievement.token_id == token_id
    ).first()

    if not forged:
        raise HTTPException(status_code=404, detail="Item not found")

    # Get the original forger
    forger_wallet = db.query(WalletAccount).filter(
        WalletAccount.id == forged.wallet_account_id
    ).first()
    forger = None
    if forger_wallet:
        forger = db.query(User).filter(User.id == forger_wallet.user_id).first()

    forger_info = ProvenanceUserInfo(
        user_id=forger.id if forger else 0,
        username=forger.username if forger else "Unknown"
    )

    # Get current owner
    current_owner = get_item_owner(forged, db)
    current_owner_info = ProvenanceUserInfo(
        user_id=current_owner.id if current_owner else 0,
        username=current_owner.username if current_owner else "Unknown"
    )

    # Get trade history
    trades = db.query(ItemTrade).filter(
        ItemTrade.forged_item_id == forged.id
    ).order_by(ItemTrade.traded_at.desc()).limit(50).all()

    trade_list = []
    for trade in trades:
        from_user = trade.from_user
        to_user = trade.to_user
        trade_list.append(ProvenanceTradeInfo(
            trade_id=trade.id,
            traded_at=trade.traded_at.isoformat() if trade.traded_at else "",
            from_user=ProvenanceUserInfo(
                user_id=from_user.id if from_user else 0,
                username=from_user.username if from_user else "Unknown"
            ),
            to_user=ProvenanceUserInfo(
                user_id=to_user.id if to_user else 0,
                username=to_user.username if to_user else "Unknown"
            ),
            price_gold=trade.price_gold or 0
        ))

    # Check if on-chain (has any chain_tx_hash in trades or was minted)
    is_on_chain = forged.token_id is not None and forged.token_id > 0
    contract_address = os.getenv("FORGED_ITEMS_CONTRACT", None)

    return ProvenanceResponse(
        token_id=forged.token_id or 0,
        item_id=forged.item_id or "",
        item_name=forged.item_name or "Unknown",
        item_rarity=forged.item_rarity or "Common",
        forger=forger_info,
        forged_at=forged.forged_at.isoformat() if forged.forged_at else "",
        current_owner=current_owner_info,
        owned_since=forged.owned_since.isoformat() if forged.owned_since else None,
        trade_count=forged.trade_count or 0,
        trades=trade_list,
        is_on_chain=is_on_chain,
        contract_address=contract_address
    )
