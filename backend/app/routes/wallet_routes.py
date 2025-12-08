"""
Wallet authentication and NFT forging routes.

These endpoints allow users to:
1. Connect a crypto wallet (SIWE)
2. Forge (mint) their verified achievements as NFTs
3. Check token ownership for Godot integration
"""
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session as DbSession
from pydantic import BaseModel
from typing import Optional, List, Callable
from datetime import datetime, timedelta
import logging

from app.models import (
    User, WalletAccount, AchievementCredit, Achievement, ForgedAchievement, ProviderAccount, Game
)
from app.database import SessionLocal
from app.routes.chat_routes import post_forge_announcement
from app.services.item_forge_service import compute_forged_item

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/wallet", tags=["wallet"])

# These will be set by init_wallet_routes()
_get_current_user_func: Callable = None
_wallet_service = None


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
        raise HTTPException(status_code=500, detail="Wallet routes not initialized")
    return _get_current_user_func(request, db)


def init_wallet_routes(get_db_func: Callable, get_current_user: Callable):
    """Initialize wallet routes with dependencies from main app."""
    global _get_current_user_func, _wallet_service
    _get_current_user_func = get_current_user

    # Try to import wallet service (may fail if deps not installed)
    try:
        from app.services import wallet_service
        _wallet_service = wallet_service
        logger.info("Wallet service initialized successfully")
    except ImportError as e:
        logger.warning(f"Wallet service not available (missing deps?): {e}")
        _wallet_service = None


# =============================================================================
# REQUEST/RESPONSE MODELS
# =============================================================================

class NonceRequest(BaseModel):
    wallet_address: str


class NonceResponse(BaseModel):
    nonce: str
    message: str
    expires_at: str


class VerifyRequest(BaseModel):
    message: str
    signature: str


class VerifyResponse(BaseModel):
    success: bool
    wallet_address: Optional[str] = None


class ForgeRequest(BaseModel):
    achievement_credit_ids: List[int]


class ForgeResponse(BaseModel):
    forged: List[dict]
    failed: List[dict]


class OwnershipCheckRequest(BaseModel):
    wallet_address: str
    achievement_ids: List[str]


# =============================================================================
# WALLET CONNECTION ENDPOINTS
# =============================================================================

@router.post("/nonce", response_model=NonceResponse)
async def get_wallet_nonce(
    request_body: NonceRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Step 1 of wallet connection: Get a nonce for SIWE."""
    # Get current user
    current_user = get_current_user_dep(request, db)

    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available. Install: pip install web3 siwe eth-account")

    nonce = _wallet_service.generate_nonce()
    expires_at = datetime.utcnow() + timedelta(minutes=10)
    chain_id = _wallet_service.CHAIN_ID
    wallet_address_lower = request_body.wallet_address.lower()

    # Check if this wallet address is already connected to another user
    existing_by_address = db.query(WalletAccount).filter(
        WalletAccount.wallet_address == wallet_address_lower
    ).first()

    if existing_by_address and existing_by_address.user_id != current_user.id:
        # Wallet belongs to another user - block this
        raise HTTPException(
            status_code=409,
            detail="This wallet is already connected to another account. Disconnect it there first."
        )

    # Check if user already has a wallet for this chain
    existing = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id
    ).first()

    if existing:
        # User already has a wallet for this chain - update it
        existing.current_nonce = nonce
        existing.nonce_expires_at = expires_at
        existing.wallet_address = wallet_address_lower
    elif existing_by_address:
        # Wallet belongs to same user but different chain - update chain
        existing_by_address.chain_id = chain_id
        existing_by_address.current_nonce = nonce
        existing_by_address.nonce_expires_at = expires_at
    else:
        # New wallet
        wallet = WalletAccount(
            user_id=current_user.id,
            wallet_address=wallet_address_lower,
            chain_id=chain_id,
            current_nonce=nonce,
            nonce_expires_at=expires_at,
        )
        db.add(wallet)

    db.commit()

    message = _wallet_service.create_siwe_message(
        wallet_address=request_body.wallet_address,
        nonce=nonce,
        chain_id=chain_id,
    )

    return NonceResponse(
        nonce=nonce,
        message=message,
        expires_at=expires_at.isoformat() + "Z",
    )


@router.post("/verify", response_model=VerifyResponse)
async def verify_wallet_signature(
    request_body: VerifyRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Step 2 of wallet connection: Verify the signed SIWE message."""
    current_user = get_current_user_dep(request, db)

    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available")

    chain_id = _wallet_service.CHAIN_ID

    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id,
        WalletAccount.nonce_expires_at > datetime.utcnow()
    ).first()

    if not wallet:
        raise HTTPException(status_code=400, detail="No pending wallet verification found")

    verified_address = _wallet_service.verify_siwe_signature(
        message=request_body.message,
        signature=request_body.signature,
        expected_nonce=wallet.current_nonce,
    )

    if not verified_address:
        raise HTTPException(status_code=401, detail="Invalid signature")

    if verified_address.lower() != wallet.wallet_address.lower():
        raise HTTPException(status_code=401, detail="Wallet address mismatch")

    wallet.current_nonce = None
    wallet.nonce_expires_at = None
    wallet.linked_at = datetime.utcnow()
    db.commit()

    logger.info(f"User {current_user.username} linked wallet {verified_address}")

    return VerifyResponse(success=True, wallet_address=verified_address)


@router.get("/status")
async def get_wallet_status(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Check if user has a linked wallet."""
    current_user = get_current_user_dep(request, db)
    chain_id = _wallet_service.CHAIN_ID if _wallet_service else 8453

    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id,
        WalletAccount.current_nonce.is_(None),
    ).first()

    if wallet:
        forged_count = db.query(ForgedAchievement).filter(
            ForgedAchievement.wallet_account_id == wallet.id
        ).count()

        return {
            "connected": True,
            "wallet_address": wallet.wallet_address,
            "chain_id": wallet.chain_id,
            "linked_at": wallet.linked_at.isoformat() if wallet.linked_at else None,
            "forged_count": forged_count,
        }

    return {"connected": False}


@router.delete("/disconnect")
async def disconnect_wallet(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Disconnect wallet from account."""
    current_user = get_current_user_dep(request, db)
    chain_id = _wallet_service.CHAIN_ID if _wallet_service else 8453

    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id,
    ).first()

    if wallet:
        db.delete(wallet)
        db.commit()
        logger.info(f"User {current_user.username} disconnected wallet")

    return {"success": True}


# =============================================================================
# ACHIEVEMENT FORGING ENDPOINTS
# =============================================================================

@router.get("/forgeable")
async def get_forgeable_achievements(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get achievements that can be forged (Rare+, not yet forged)."""
    current_user = get_current_user_dep(request, db)
    chain_id = _wallet_service.CHAIN_ID if _wallet_service else 8453

    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id,
        WalletAccount.current_nonce.is_(None),
    ).first()

    if not wallet:
        raise HTTPException(status_code=400, detail="No wallet connected")

    forgeable_tiers = ["Legendary", "Epic", "Rare"]

    credits = (
        db.query(AchievementCredit, Achievement)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .outerjoin(ForgedAchievement, ForgedAchievement.achievement_credit_id == AchievementCredit.id)
        .filter(
            AchievementCredit.user_id == current_user.id,
            AchievementCredit.is_original_claim == True,  # Only original claims can be forged!
            Achievement.rarity_tier.in_(forgeable_tiers),
            ForgedAchievement.id.is_(None),
        )
        .all()
    )

    return {
        "wallet_address": wallet.wallet_address,
        "forgeable": [
            {
                "credit_id": credit.id,
                "achievement_id": achievement.id,
                "display_name": achievement.display_name,
                "description": achievement.description,
                "icon_url": achievement.icon_url,
                "rarity_tier": achievement.rarity_tier,
                "percent": achievement.percent,
                "app_id": achievement.app_id,
                "api_name": achievement.api_name,
            }
            for credit, achievement in credits
        ],
    }


@router.post("/forge", response_model=ForgeResponse)
async def forge_achievements(
    request_body: ForgeRequest,
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Forge (mint) achievements as NFTs."""
    current_user = get_current_user_dep(request, db)

    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available")

    chain_id = _wallet_service.CHAIN_ID

    wallet = db.query(WalletAccount).filter(
        WalletAccount.user_id == current_user.id,
        WalletAccount.chain_id == chain_id,
        WalletAccount.current_nonce.is_(None),
    ).first()

    if not wallet:
        raise HTTPException(status_code=400, detail="No wallet connected")

    forged = []
    failed = []

    for credit_id in request_body.achievement_credit_ids:
        credit = (
            db.query(AchievementCredit)
            .filter(
                AchievementCredit.id == credit_id,
                AchievementCredit.user_id == current_user.id,
            )
            .first()
        )

        if not credit:
            failed.append({"credit_id": credit_id, "error": "Achievement not found or not owned"})
            continue

        # Anti-exploit: Only original claims can be forged
        if not credit.is_original_claim:
            failed.append({"credit_id": credit_id, "error": "Cannot forge reclaimed achievements (display only)"})
            continue

        existing = db.query(ForgedAchievement).filter(
            ForgedAchievement.achievement_credit_id == credit_id
        ).first()

        if existing:
            failed.append({"credit_id": credit_id, "error": "Already forged"})
            continue

        achievement = db.query(Achievement).filter(Achievement.id == credit.achievement_id).first()
        provider_account = db.query(ProviderAccount).filter(ProviderAccount.id == credit.provider_account_id).first()

        # Look up game name for item type mapping
        game = db.query(Game).filter(
            Game.app_id == achievement.app_id,
            Game.provider_account_id == provider_account.id
        ).first()
        game_name = game.name if game else achievement.app_id

        try:
            result = await _wallet_service.mint_achievement_nft(
                wallet_address=wallet.wallet_address,
                achievement_credit_id=credit_id,
                provider=provider_account.provider_name,
                app_id=achievement.app_id,
                api_name=achievement.api_name,
                rarity_tier=achievement.rarity_tier,
            )

            # Compute item properties from achievement data
            item_props = compute_forged_item(
                achievement_id=achievement.id,
                api_name=achievement.api_name,
                app_id=achievement.app_id,
                game_name=game_name,
                provider=provider_account.provider_name,
                rarity_tier=achievement.rarity_tier,
                effort_score=achievement.effort_score,
                hidden=achievement.hidden,
                unlocked_at=credit.unlocked_at,
            )

            forge_record = ForgedAchievement(
                achievement_credit_id=credit_id,
                wallet_account_id=wallet.id,
                token_id=result['token_id'],
                contract_address=result['contract_address'],
                chain_id=result['chain_id'],
                tx_hash=result['tx_hash'],
                # Item properties
                item_type=item_props["item_type"],
                weapon_type=item_props.get("weapon_type"),  # Only for weapons
                item_id=item_props["item_id"],
                item_name=item_props["item_name"],
                item_rarity=item_props["item_rarity"],
                effect_intensity=item_props["effect_intensity"],
                effect_name=item_props["effect_name"],
                glow_color=item_props["glow_color"],
                effort_tier=item_props["effort_tier"],
                vintage_years=item_props["vintage_years"],
                is_secret=item_props["is_secret"],
            )
            db.add(forge_record)
            db.commit()

            # Announce forge in global feed
            post_forge_announcement(db, current_user, achievement.display_name, achievement.rarity_tier)

            forged.append({
                "credit_id": credit_id,
                "token_id": result['token_id'],
                "tx_hash": result['tx_hash'],
                "achievement_name": achievement.display_name,
                "item": item_props,  # Include computed item for immediate use
            })

            logger.info(f"User {current_user.username} forged {achievement.display_name} as token {result['token_id']}")

        except Exception as e:
            logger.error(f"Failed to forge achievement {credit_id}: {e}")
            failed.append({"credit_id": credit_id, "error": str(e)})

    return ForgeResponse(forged=forged, failed=failed)


@router.get("/forged")
async def get_forged_achievements(
    request: Request,
    db: DbSession = Depends(get_db),
):
    """Get all achievements the user has forged."""
    current_user = get_current_user_dep(request, db)

    forged = (
        db.query(ForgedAchievement, Achievement, AchievementCredit)
        .join(AchievementCredit, ForgedAchievement.achievement_credit_id == AchievementCredit.id)
        .join(Achievement, AchievementCredit.achievement_id == Achievement.id)
        .filter(AchievementCredit.user_id == current_user.id)
        .all()
    )

    return {
        "forged": [
            {
                "token_id": f.token_id,
                "contract_address": f.contract_address,
                "chain_id": f.chain_id,
                "tx_hash": f.tx_hash,
                "forged_at": f.forged_at.isoformat() if f.forged_at else None,
                "achievement": {
                    "display_name": achievement.display_name,
                    "description": achievement.description,
                    "icon_url": achievement.icon_url,
                    "rarity_tier": achievement.rarity_tier,
                },
            }
            for f, achievement, credit in forged
        ],
    }


# =============================================================================
# PUBLIC ENDPOINTS (for Godot / multiplayer)
# =============================================================================

@router.post("/check-ownership")
async def check_ownership(request_body: OwnershipCheckRequest):
    """PUBLIC: Check if a wallet owns specific achievement tokens."""
    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available")

    results = {}

    for achievement_id in request_body.achievement_ids:
        try:
            owns = _wallet_service.check_wallet_owns_achievement(
                wallet_address=request_body.wallet_address,
                achievement_id=achievement_id,
            )
            results[achievement_id] = owns
        except Exception as e:
            logger.error(f"Ownership check failed for {achievement_id}: {e}")
            results[achievement_id] = False

    return {
        "wallet_address": request_body.wallet_address,
        "ownership": results,
    }


# =============================================================================
# PROVENANCE CHECK (original earner vs current owner)
# =============================================================================

@router.get("/provenance/{token_id}")
async def get_token_provenance(token_id: int):
    """
    Check if current owner is the original earner.

    Returns:
    - original_earner: wallet that forged (earned) the achievement
    - current_owner: wallet that currently holds the token
    - is_original: true if current owner earned it, false if traded/gifted
    - achievement: achievement details

    Used by Godot to show "EARNED" vs "TRADED" badges on items.
    """
    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available")

    try:
        # Get on-chain data
        from web3 import Web3
        w3 = _wallet_service.get_web3()
        contract = _wallet_service.get_contract(w3)

        # Get achievement data (includes originalEarner)
        achievement_data = contract.functions.getAchievementData(token_id).call()
        original_earner = achievement_data[0]
        achievement_id = achievement_data[1]
        provider = achievement_data[2]
        minted_at = achievement_data[3]
        rarity_tier = achievement_data[4]

        # Get current owner
        current_owner = contract.functions.ownerOf(token_id).call()

        # Check if same person
        is_original = original_earner.lower() == current_owner.lower()

        return {
            "token_id": token_id,
            "original_earner": original_earner,
            "current_owner": current_owner,
            "is_original": is_original,
            "acquisition_type": "earned" if is_original else "traded",
            "achievement": {
                "id": achievement_id,
                "provider": provider,
                "rarity_tier": rarity_tier,
                "minted_at": minted_at,
            }
        }
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Token not found or error: {e}")


@router.post("/provenance/batch")
async def get_batch_provenance(wallet_address: str, token_ids: list[int]):
    """
    Batch check provenance for multiple tokens.

    Used by Godot to check all equipped items at once.
    Returns list of items with earned/traded status.
    """
    if _wallet_service is None:
        raise HTTPException(status_code=503, detail="Wallet service not available")

    results = []

    try:
        from web3 import Web3
        w3 = _wallet_service.get_web3()
        contract = _wallet_service.get_contract(w3)

        for token_id in token_ids:
            try:
                achievement_data = contract.functions.getAchievementData(token_id).call()
                original_earner = achievement_data[0]
                current_owner = contract.functions.ownerOf(token_id).call()

                # Check if the queried wallet is the current owner
                is_owner = current_owner.lower() == wallet_address.lower()
                is_original = original_earner.lower() == wallet_address.lower()

                results.append({
                    "token_id": token_id,
                    "achievement_id": achievement_data[1],
                    "rarity_tier": achievement_data[4],
                    "is_owner": is_owner,
                    "is_original": is_original,
                    "acquisition_type": "earned" if is_original else "traded" if is_owner else "not_owned",
                })
            except:
                results.append({
                    "token_id": token_id,
                    "error": "Token not found"
                })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Batch check failed: {e}")

    return {
        "wallet_address": wallet_address,
        "items": results,
    }


# =============================================================================
# TOKEN METADATA (for NFT marketplaces)
# =============================================================================

@router.get("/metadata/{credit_id}")
async def get_token_metadata(credit_id: int):
    """ERC-721 metadata endpoint for NFT marketplaces."""
    db = SessionLocal()
    try:
        credit = (
            db.query(AchievementCredit)
            .filter(AchievementCredit.id == credit_id)
            .first()
        )

        if not credit:
            raise HTTPException(status_code=404, detail="Achievement not found")

        achievement = db.query(Achievement).filter(Achievement.id == credit.achievement_id).first()
        provider_account = db.query(ProviderAccount).filter(ProviderAccount.id == credit.provider_account_id).first()

        rarity_colors = {
            "Legendary": "ff8000",
            "Epic": "a335ee",
            "Rare": "0070dd",
            "Uncommon": "1eff00",
            "Common": "ffffff",
        }

        return {
            "name": achievement.display_name,
            "description": f"{achievement.description}\n\nVerified gaming achievement from {provider_account.provider_name}.",
            "image": achievement.icon_url,
            "external_url": f"https://mantle.gg/achievement/{credit_id}",
            "attributes": [
                {"trait_type": "Rarity", "value": achievement.rarity_tier},
                {"trait_type": "Provider", "value": provider_account.provider_name},
                {"trait_type": "Global Unlock %", "value": round(achievement.percent or 0, 2)},
                {"trait_type": "Game ID", "value": achievement.app_id},
            ],
            "background_color": rarity_colors.get(achievement.rarity_tier, "1a1a2e"),
        }
    finally:
        db.close()
