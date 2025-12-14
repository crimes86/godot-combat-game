"""
World Tree and Chunk Expansion API Routes

Endpoints for:
- Seed plot claiming
- Chunk expansion tracking
- World Tree rankings
- Contribution recording
- Blockchain integration
"""

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime, timedelta
from pydantic import BaseModel
import httpx
import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/world-tree", tags=["world-tree"])

# Will be set by init_world_tree_routes
get_db = None
get_current_user = None


# ═══════════════════════════════════════════════════════════════════════════════
# REQUEST/RESPONSE MODELS
# ═══════════════════════════════════════════════════════════════════════════════

class SeedPlotClaim(BaseModel):
    chunk_id: int
    shard_id: str = "default"


class Contribution(BaseModel):
    chunk_id: int
    shard_id: str = "default"
    gold: int = 0
    wood: int = 0
    stone: int = 0
    gems: int = 0
    kills: int = 0
    boss_kills: int = 0  # World Tree v2.1
    time_minutes: int = 0


class WorldTreeRecord(BaseModel):
    week_number: int
    shard_id: str
    chunk_id: int
    owner_id: str
    total_score: int
    top_contributors: List[dict]
    recorded_at: str


# World Tree v2.1 Request Models

class BuildingPlacement(BaseModel):
    building_type: str  # "campfire", "warehouse", "vendor", "shrine", "smithy", "fortress"
    position_slot: str  # "A"-"F"


class WarehouseDeposit(BaseModel):
    gold: int = 0
    wood: int = 0
    stone: int = 0
    gems: int = 0


class WarehouseWithdraw(BaseModel):
    gold: int = 0
    wood: int = 0
    stone: int = 0
    gems: int = 0


class OwnershipTransfer(BaseModel):
    new_owner_id: int


class GuildChange(BaseModel):
    new_guild_id: str
    new_guild_name: str


class BanePlant(BaseModel):
    target_chunk_id: int
    attacker_guild_id: str
    shard_id: str = "default"


class BaneAttack(BaseModel):
    damage: int


# ═══════════════════════════════════════════════════════════════════════════════
# SEED PLOT ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/seed-plots")
async def get_seed_plots(
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get all seed plots for a shard"""
    from app.models import SeedPlot

    plots = db.query(SeedPlot).filter(SeedPlot.shard_id == shard_id).all()

    return {
        "success": True,
        "seed_plots": [
            {
                "chunk_id": plot.chunk_id,
                "position_x": plot.position_x,
                "position_y": plot.position_y,
                "owner_id": plot.owner_id,
                "state": plot.state,
                "claim_cost": plot.claim_cost,
                "contribution_score": plot.contribution_score,
                "claimed_at": plot.claimed_at.isoformat() if plot.claimed_at else None,
                "last_contribution_at": plot.last_contribution_at.isoformat() if plot.last_contribution_at else None
            }
            for plot in plots
        ]
    }


@router.get("/seed-plots/{chunk_id}")
async def get_seed_plot(
    chunk_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get a specific seed plot"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    return {
        "success": True,
        "seed_plot": {
            "chunk_id": plot.chunk_id,
            "position_x": plot.position_x,
            "position_y": plot.position_y,
            "owner_id": plot.owner_id,
            "state": plot.state,
            "claim_cost": plot.claim_cost,
            "contribution_score": plot.contribution_score,
            "total_gold_contributed": plot.total_gold_contributed,
            "total_wood_contributed": plot.total_wood_contributed,
            "total_stone_contributed": plot.total_stone_contributed,
            "total_kills": plot.total_kills,
            "total_time_minutes": plot.total_time_minutes,
            "claimed_at": plot.claimed_at.isoformat() if plot.claimed_at else None,
            "last_contribution_at": plot.last_contribution_at.isoformat() if plot.last_contribution_at else None
        }
    }


@router.post("/seed-plots/{chunk_id}/claim")
async def claim_seed_plot(
    chunk_id: int,
    claim: SeedPlotClaim,
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Claim a seed plot"""
    from app.models import SeedPlot, User

    # Get user's gold
    user_db = db.query(User).filter(User.id == user.id).first()
    if not user_db:
        raise HTTPException(status_code=404, detail="User not found")

    # Get seed plot
    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == claim.shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    # Check if already claimed
    if plot.state not in ["unclaimed", "decaying"]:
        raise HTTPException(status_code=400, detail="Seed plot already claimed")

    # Calculate cost (half price if decaying)
    cost = plot.claim_cost
    if plot.state == "decaying":
        cost = int(cost * 0.5)

    # Check if user has enough gold (TODO: integrate with player gold system)
    # For now, just proceed

    # Claim the plot
    plot.owner_id = str(user.id)
    plot.claimed_at = datetime.utcnow()
    plot.last_contribution_at = datetime.utcnow()
    plot.state = "claimed"

    db.commit()

    logger.info(f"🌱 User {user.id} claimed seed plot {chunk_id} for {cost} gold")

    return {
        "success": True,
        "cost": cost,
        "plot_id": chunk_id,
        "message": f"Seed plot claimed for {cost} gold"
    }


@router.post("/seed-plots/{chunk_id}/contribute")
async def contribute_to_seed_plot(
    chunk_id: int,
    contribution: Contribution,
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Add contribution to a seed plot"""
    from app.models import SeedPlot, WorldTreeContribution

    # Get seed plot
    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == contribution.shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.state != "claimed":
        raise HTTPException(status_code=400, detail="Seed plot is not claimed")

    # Calculate week number
    week_number = int(datetime.utcnow().timestamp() / 604800)

    # Calculate contribution score
    GOLD_POINTS = 1
    WOOD_POINTS = 5
    STONE_POINTS = 5
    GEM_POINTS = 50
    KILL_POINTS = 2
    BOSS_KILL_POINTS = 20  # World Tree v2.1 - Fix #11
    TIME_POINTS_PER_HOUR = 1.0

    score = (
        contribution.gold * GOLD_POINTS +
        contribution.wood * WOOD_POINTS +
        contribution.stone * STONE_POINTS +
        contribution.gems * GEM_POINTS +
        contribution.kills * KILL_POINTS +
        contribution.boss_kills * BOSS_KILL_POINTS +
        int(contribution.time_minutes / 60.0 * TIME_POINTS_PER_HOUR)
    )

    # Update seed plot totals
    plot.total_gold_contributed += contribution.gold
    plot.total_wood_contributed += contribution.wood
    plot.total_stone_contributed += contribution.stone
    plot.total_kills += contribution.kills
    plot.total_time_minutes += contribution.time_minutes
    plot.contribution_score += score
    plot.last_contribution_at = datetime.utcnow()

    # Reset abandoned state if necessary
    if plot.state in ["abandoned", "decaying"]:
        plot.state = "claimed"
        plot.abandoned_at = None
        plot.decay_warning_sent = False

    # Get or create contribution record
    contrib = db.query(WorldTreeContribution).filter(
        WorldTreeContribution.seed_plot_id == plot.id,
        WorldTreeContribution.user_id == user.id,
        WorldTreeContribution.week_number == week_number
    ).first()

    if not contrib:
        contrib = WorldTreeContribution(
            seed_plot_id=plot.id,
            user_id=user.id,
            week_number=week_number,
            gold_contributed=0,
            wood_contributed=0,
            stone_contributed=0,
            gems_contributed=0,
            kills=0,
            boss_kills=0,
            time_minutes=0,
            contribution_score=0,
            first_contribution_at=datetime.utcnow(),
            last_contribution_at=datetime.utcnow()
        )
        db.add(contrib)

    # Update contribution
    contrib.gold_contributed += contribution.gold
    contrib.wood_contributed += contribution.wood
    contrib.stone_contributed += contribution.stone
    contrib.gems_contributed += contribution.gems
    contrib.kills += contribution.kills
    contrib.boss_kills += contribution.boss_kills
    contrib.time_minutes += contribution.time_minutes
    contrib.contribution_score += score
    contrib.last_contribution_at = datetime.utcnow()

    db.commit()

    logger.info(f"🌱 User {user.id} contributed {score} points to seed plot {chunk_id}")

    return {
        "success": True,
        "score_added": score,
        "total_score": plot.contribution_score,
        "message": f"Contributed {score} points to seed plot"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# RANKINGS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/rankings")
async def get_rankings(
    shard_id: str = "default",
    week_number: Optional[int] = None,
    db: Session = Depends(get_db)
):
    """Get World Tree rankings"""
    from app.models import WorldTreeRanking, SeedPlot, User

    # Get current week if not specified
    if week_number is None:
        week_number = int(datetime.utcnow().timestamp() / 604800)

    rankings = db.query(WorldTreeRanking).filter(
        WorldTreeRanking.shard_id == shard_id,
        WorldTreeRanking.week_number == week_number
    ).order_by(WorldTreeRanking.rank).all()

    return {
        "success": True,
        "week_number": week_number,
        "rankings": [
            {
                "rank": r.rank,
                "owner_id": r.owner_id,
                "total_score": r.total_score,
                "promoted_to_origin": r.promoted_to_origin,
                "promoted_at": r.promoted_at.isoformat() if r.promoted_at else None,
                "blockchain_tx_hash": r.blockchain_tx_hash
            }
            for r in rankings
        ]
    }


@router.get("/rankings/current")
async def get_current_rankings(
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get current week's live rankings (not finalized)"""
    from app.models import SeedPlot, User

    # Get all claimed seed plots
    plots = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.state == "claimed"
    ).order_by(SeedPlot.contribution_score.desc()).all()

    return {
        "success": True,
        "rankings": [
            {
                "rank": i + 1,
                "chunk_id": plot.chunk_id,
                "owner_id": plot.owner_id,
                "total_score": plot.contribution_score
            }
            for i, plot in enumerate(plots)
        ]
    }


@router.get("/rankings/player/{user_id}")
async def get_player_ranking(
    user_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get a player's current ranking"""
    from app.models import SeedPlot

    # Get player's seed plot
    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.owner_id == str(user_id),
        SeedPlot.state == "claimed"
    ).first()

    if not plot:
        return {
            "success": True,
            "ranked": False,
            "message": "Player has no active seed plot"
        }

    # Get all claimed plots to calculate rank
    all_plots = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.state == "claimed"
    ).order_by(SeedPlot.contribution_score.desc()).all()

    rank = next((i + 1 for i, p in enumerate(all_plots) if p.id == plot.id), -1)

    return {
        "success": True,
        "ranked": True,
        "rank": rank,
        "total_score": plot.contribution_score,
        "chunk_id": plot.chunk_id
    }


# ═══════════════════════════════════════════════════════════════════════════════
# WORLD TREE v2.1 ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/seed-plots/{chunk_id}/upgrade")
async def upgrade_tree(
    chunk_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Start upgrading tree to next rank"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.original_owner_id != user.id:
        raise HTTPException(status_code=403, detail="Only original owner can upgrade tree")

    if plot.tree_rank >= 7:
        raise HTTPException(status_code=400, detail="Tree is already max rank")

    if plot.upgrade_started_at:
        raise HTTPException(status_code=400, detail="Upgrade already in progress")

    # Start upgrade
    plot.upgrade_started_at = datetime.utcnow()
    plot.upgrade_target_rank = plot.tree_rank + 1
    db.commit()

    return {
        "success": True,
        "current_rank": plot.tree_rank,
        "target_rank": plot.upgrade_target_rank,
        "message": f"Upgrade to rank {plot.upgrade_target_rank} started"
    }


@router.post("/seed-plots/{chunk_id}/water")
async def water_tree(
    chunk_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Water tree for growth bonus"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    # Check cooldown (24 hours)
    if plot.last_watered:
        hours_since = (datetime.utcnow() - plot.last_watered).total_seconds() / 3600
        if hours_since < 24:
            raise HTTPException(
                status_code=400,
                detail=f"Can water again in {24 - hours_since:.1f} hours"
            )

    # Apply watering
    plot.last_watered = datetime.utcnow()
    plot.times_watered += 1
    plot.growth_bonus_accumulated += 0.01  # 1% growth bonus
    db.commit()

    return {
        "success": True,
        "times_watered": plot.times_watered,
        "growth_bonus": plot.growth_bonus_accumulated,
        "message": "Tree watered successfully"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# BUILDING ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/seed-plots/{chunk_id}/buildings")
async def place_building(
    chunk_id: int,
    building: BuildingPlacement,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Place a building on a seed plot"""
    from app.models import SeedPlot, SeedPlotBuilding

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.original_owner_id != user.id:
        raise HTTPException(status_code=403, detail="Only original owner can place buildings")

    if plot.tree_rank < 1:
        raise HTTPException(status_code=400, detail="Tree must be rank 1+ to place buildings")

    # Check slot availability
    existing = db.query(SeedPlotBuilding).filter(
        SeedPlotBuilding.seed_plot_id == plot.id,
        SeedPlotBuilding.position_slot == building.position_slot,
        SeedPlotBuilding.destroyed_at == None
    ).first()

    if existing:
        raise HTTPException(status_code=400, detail=f"Slot {building.position_slot} already occupied")

    # Building costs
    BUILDING_COSTS = {
        "campfire": 5000,
        "warehouse": 10000,
        "vendor": 15000,
        "shrine": 20000,
        "smithy": 25000,
        "fortress": 30000
    }

    cost = BUILDING_COSTS.get(building.building_type, 10000)

    # Create building
    new_building = SeedPlotBuilding(
        seed_plot_id=plot.id,
        building_type=building.building_type,
        position_slot=building.position_slot,
        original_cost=cost,
        created_at=datetime.utcnow(),
        is_active=True,
        activated_at=datetime.utcnow()
    )
    db.add(new_building)
    db.commit()

    return {
        "success": True,
        "building_id": new_building.id,
        "cost": cost,
        "message": f"{building.building_type} placed in slot {building.position_slot}"
    }


@router.get("/seed-plots/{chunk_id}/buildings")
async def list_buildings(
    chunk_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """List all buildings on a seed plot"""
    from app.models import SeedPlot, SeedPlotBuilding

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    buildings = db.query(SeedPlotBuilding).filter(
        SeedPlotBuilding.seed_plot_id == plot.id,
        SeedPlotBuilding.destroyed_at == None
    ).all()

    return {
        "success": True,
        "buildings": [
            {
                "id": b.id,
                "type": b.building_type,
                "slot": b.position_slot,
                "health": b.health,
                "max_health": b.max_health,
                "is_active": b.is_active,
                "activation_cost": b.activation_cost,
                "created_at": b.created_at.isoformat()
            }
            for b in buildings
        ]
    }


@router.post("/seed-plots/{chunk_id}/buildings/{building_id}/activate")
async def activate_building(
    chunk_id: int,
    building_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Activate migrated building (50% cost)"""
    from app.models import SeedPlot, SeedPlotBuilding

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    building = db.query(SeedPlotBuilding).filter(
        SeedPlotBuilding.id == building_id,
        SeedPlotBuilding.seed_plot_id == plot.id
    ).first()

    if not building:
        raise HTTPException(status_code=404, detail="Building not found")

    if building.is_active:
        raise HTTPException(status_code=400, detail="Building is already active")

    # Activate building
    building.is_active = True
    building.activated_at = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "cost": building.activation_cost,
        "message": f"Building activated for {building.activation_cost} gold"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# WAREHOUSE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/seed-plots/{chunk_id}/warehouse/deposit")
async def warehouse_deposit(
    chunk_id: int,
    deposit: WarehouseDeposit,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Deposit resources (safe fills first, then overflow)"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    # Safe storage limits
    SAFE_LIMITS = {"gold": 50000, "wood": 5000, "stone": 5000, "gems": 5000}

    # Deposit each resource type
    for resource in ["gold", "wood", "stone", "gems"]:
        amount = getattr(deposit, resource)
        if amount <= 0:
            continue

        safe_key = f"warehouse_safe_{resource}"
        overflow_key = f"warehouse_overflow_{resource}"

        current_safe = getattr(plot, safe_key)
        safe_space = SAFE_LIMITS[resource] - current_safe

        if safe_space > 0:
            to_safe = min(amount, safe_space)
            setattr(plot, safe_key, current_safe + to_safe)
            amount -= to_safe

        if amount > 0:
            current_overflow = getattr(plot, overflow_key)
            setattr(plot, overflow_key, current_overflow + amount)

    db.commit()

    return {
        "success": True,
        "message": "Resources deposited",
        "safe": {
            "gold": plot.warehouse_safe_gold,
            "wood": plot.warehouse_safe_wood,
            "stone": plot.warehouse_safe_stone,
            "gems": plot.warehouse_safe_gems
        },
        "overflow": {
            "gold": plot.warehouse_overflow_gold,
            "wood": plot.warehouse_overflow_wood,
            "stone": plot.warehouse_overflow_stone,
            "gems": plot.warehouse_overflow_gems
        }
    }


@router.post("/seed-plots/{chunk_id}/warehouse/withdraw")
async def warehouse_withdraw(
    chunk_id: int,
    withdraw: WarehouseWithdraw,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Withdraw resources (overflow first, then safe)"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    # Withdraw each resource type
    for resource in ["gold", "wood", "stone", "gems"]:
        amount = getattr(withdraw, resource)
        if amount <= 0:
            continue

        safe_key = f"warehouse_safe_{resource}"
        overflow_key = f"warehouse_overflow_{resource}"

        current_overflow = getattr(plot, overflow_key)
        current_safe = getattr(plot, safe_key)

        # Take from overflow first
        from_overflow = min(amount, current_overflow)
        setattr(plot, overflow_key, current_overflow - from_overflow)
        amount -= from_overflow

        # Then from safe if needed
        if amount > 0:
            from_safe = min(amount, current_safe)
            setattr(plot, safe_key, current_safe - from_safe)
            amount -= from_safe

        if amount > 0:
            raise HTTPException(status_code=400, detail=f"Insufficient {resource}")

    db.commit()

    return {
        "success": True,
        "message": "Resources withdrawn"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# RESOURCE MINE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/seed-plots/{chunk_id}/mines/{mine_id}/claim")
async def claim_mine(
    chunk_id: int,
    mine_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Claim a resource mine"""
    from app.models import SeedPlot, ResourceMine
    import json

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.original_owner_id != user.id:
        raise HTTPException(status_code=403, detail="Only original owner can claim mines")

    mine = db.query(ResourceMine).filter(ResourceMine.id == mine_id).first()

    if not mine:
        raise HTTPException(status_code=404, detail="Mine not found")

    if mine.owner_tree_id:
        raise HTTPException(status_code=400, detail="Mine already claimed")

    # Claim mine
    mine.owner_tree_id = plot.id

    # Update plot's claimed mine list
    claimed_ids = json.loads(plot.claimed_mine_ids) if plot.claimed_mine_ids else []
    claimed_ids.append(mine_id)
    plot.claimed_mine_ids = json.dumps(claimed_ids)

    db.commit()

    return {
        "success": True,
        "mine_id": mine_id,
        "mine_type": mine.mine_type,
        "message": f"Claimed {mine.mine_type} mine"
    }


@router.post("/seed-plots/{chunk_id}/mines/{mine_id}/collect")
async def collect_mine(
    chunk_id: int,
    mine_id: int,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Collect from mine (with active collection logic)"""
    from app.models import SeedPlot, ResourceMine

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    mine = db.query(ResourceMine).filter(
        ResourceMine.id == mine_id,
        ResourceMine.owner_tree_id == plot.id
    ).first()

    if not mine:
        raise HTTPException(status_code=404, detail="Mine not found or not owned")

    # Check cooldown (30 minutes)
    if mine.last_collected:
        minutes_since = (datetime.utcnow() - mine.last_collected).total_seconds() / 60
        if minutes_since < 30:
            raise HTTPException(
                status_code=400,
                detail=f"Can collect again in {30 - minutes_since:.1f} minutes"
            )

        # Reset quick collect count if over 30 minutes
        mine.quick_collect_count = 0

    # Calculate collection amount with diminishing returns
    base_amount = 100
    multiplier = 0.8 ** mine.quick_collect_count  # 100%, 80%, 64%, ...
    amount = int(base_amount * multiplier)

    # Update mine
    mine.last_collected = datetime.utcnow()
    mine.last_collector = str(user.id)
    mine.quick_collect_count += 1
    mine.resources_accumulated += amount

    db.commit()

    return {
        "success": True,
        "amount": amount,
        "mine_type": mine.mine_type,
        "quick_collect_count": mine.quick_collect_count,
        "next_multiplier": 0.8 ** mine.quick_collect_count,
        "message": f"Collected {amount} {mine.mine_type}"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# BANE STONE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/bane-stones")
async def plant_bane_stone(
    bane: BanePlant,
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Plant bane stone to siege a tree"""
    from app.models import SeedPlot, BaneStone

    target = db.query(SeedPlot).filter(
        SeedPlot.shard_id == bane.shard_id,
        SeedPlot.chunk_id == bane.target_chunk_id
    ).first()

    if not target:
        raise HTTPException(status_code=404, detail="Target tree not found")

    if target.current_guild_id == bane.attacker_guild_id:
        raise HTTPException(status_code=400, detail="Cannot attack your own guild's tree")

    # Check for existing active bane
    existing = db.query(BaneStone).filter(
        BaneStone.target_tree_id == target.id,
        BaneStone.is_active == True
    ).first()

    if existing:
        raise HTTPException(status_code=400, detail="Tree already under siege")

    # Calculate defense window (using tree's preferred time)
    defense_hour = target.defense_window_hour
    window_start = datetime.utcnow().replace(hour=defense_hour, minute=0, second=0, microsecond=0)
    if window_start < datetime.utcnow():
        window_start += timedelta(days=1)
    window_end = window_start + timedelta(hours=1)

    # Create bane stone
    bane_stone = BaneStone(
        shard_id=bane.shard_id,
        target_tree_id=target.id,
        attacker_guild_id=bane.attacker_guild_id,
        planted_at=datetime.utcnow(),
        window_start=window_start,
        window_end=window_end,
        is_active=True
    )
    db.add(bane_stone)
    db.commit()

    return {
        "success": True,
        "bane_id": bane_stone.id,
        "window_start": window_start.isoformat(),
        "window_end": window_end.isoformat(),
        "cost": 50000,
        "message": "Bane stone planted"
    }


@router.get("/bane-stones/{bane_id}")
async def get_bane_stone(
    bane_id: int,
    db: Session = Depends(get_db)
):
    """Get bane stone status"""
    from app.models import BaneStone

    bane = db.query(BaneStone).filter(BaneStone.id == bane_id).first()

    if not bane:
        raise HTTPException(status_code=404, detail="Bane stone not found")

    return {
        "success": True,
        "bane": {
            "id": bane.id,
            "target_tree_id": bane.target_tree_id,
            "attacker_guild_id": bane.attacker_guild_id,
            "health": bane.health,
            "max_health": bane.max_health,
            "planted_at": bane.planted_at.isoformat(),
            "window_start": bane.window_start.isoformat() if bane.window_start else None,
            "window_end": bane.window_end.isoformat() if bane.window_end else None,
            "is_active": bane.is_active,
            "outcome": bane.outcome
        }
    }


@router.post("/bane-stones/{bane_id}/attack")
async def attack_bane_stone(
    bane_id: int,
    attack: BaneAttack,
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Attack bane stone during defense window"""
    from app.models import BaneStone, SeedPlot

    bane = db.query(BaneStone).filter(BaneStone.id == bane_id).first()

    if not bane:
        raise HTTPException(status_code=404, detail="Bane stone not found")

    if not bane.is_active:
        raise HTTPException(status_code=400, detail="Bane stone is not active")

    # Check if within defense window
    now = datetime.utcnow()
    if not (bane.window_start <= now <= bane.window_end):
        raise HTTPException(status_code=400, detail="Not within defense window")

    # Apply damage
    bane.health = max(0, bane.health - attack.damage)

    # Check if destroyed
    if bane.health <= 0:
        bane.is_active = False
        bane.outcome = "defender_won"

        # Bane stone destroyed - defender keeps tree
        message = "Bane stone destroyed! Defenders won."
    else:
        message = f"Dealt {attack.damage} damage to bane stone"

    db.commit()

    return {
        "success": True,
        "remaining_health": bane.health,
        "message": message
    }


# ═══════════════════════════════════════════════════════════════════════════════
# OWNERSHIP ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/seed-plots/{chunk_id}/transfer-ownership")
async def transfer_ownership(
    chunk_id: int,
    transfer: OwnershipTransfer,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Transfer permanent ownership to guild member"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.original_owner_id != user.id:
        raise HTTPException(status_code=403, detail="Only original owner can transfer ownership")

    # Transfer ownership
    plot.original_owner_id = transfer.new_owner_id
    plot.last_ownership_transfer = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "new_owner_id": transfer.new_owner_id,
        "message": "Ownership transferred"
    }


@router.post("/seed-plots/{chunk_id}/change-guild")
async def change_guild(
    chunk_id: int,
    change: GuildChange,
    shard_id: str = "default",
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    """Move tree to different guild (7-day cooldown)"""
    from app.models import SeedPlot

    plot = db.query(SeedPlot).filter(
        SeedPlot.shard_id == shard_id,
        SeedPlot.chunk_id == chunk_id
    ).first()

    if not plot:
        raise HTTPException(status_code=404, detail="Seed plot not found")

    if plot.original_owner_id != user.id:
        raise HTTPException(status_code=403, detail="Only original owner can change guild")

    # Check cooldown (7 days)
    if plot.last_guild_change:
        days_since = (datetime.utcnow() - plot.last_guild_change).total_seconds() / 86400
        if days_since < 7:
            raise HTTPException(
                status_code=400,
                detail=f"Can change guild again in {7 - days_since:.1f} days"
            )

    # Change guild
    plot.current_guild_id = change.new_guild_id
    plot.guild_name = change.new_guild_name
    plot.last_guild_change = datetime.utcnow()
    db.commit()

    return {
        "success": True,
        "new_guild_id": change.new_guild_id,
        "new_guild_name": change.new_guild_name,
        "message": f"Guild changed to {change.new_guild_name}"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# SEASONAL RANKING ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/rankings/seasonal")
async def get_seasonal_rankings(
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get all-time leaderboard"""
    from app.models import SeasonalRanking

    rankings = db.query(SeasonalRanking).filter(
        SeasonalRanking.shard_id == shard_id
    ).order_by(SeasonalRanking.total_contribution.desc()).limit(100).all()

    return {
        "success": True,
        "rankings": [
            {
                "tree_id": r.tree_id,
                "guild_id": r.guild_id,
                "total_contribution": r.total_contribution,
                "total_kills": r.total_kills,
                "total_boss_kills": r.total_boss_kills,
                "weeks_participated": r.weeks_participated,
                "weeks_won": r.weeks_won,
                "highest_rank": r.highest_rank_achieved,
                "first_contribution": r.first_contribution.isoformat() if r.first_contribution else None,
                "last_contribution": r.last_contribution.isoformat() if r.last_contribution else None
            }
            for r in rankings
        ]
    }


@router.get("/rankings/seasonal/{guild_id}")
async def get_guild_seasonal_stats(
    guild_id: str,
    shard_id: str = "default",
    db: Session = Depends(get_db)
):
    """Get guild's seasonal stats"""
    from app.models import SeasonalRanking

    ranking = db.query(SeasonalRanking).filter(
        SeasonalRanking.shard_id == shard_id,
        SeasonalRanking.guild_id == guild_id
    ).first()

    if not ranking:
        return {
            "success": True,
            "has_stats": False,
            "message": "No seasonal stats for this guild"
        }

    return {
        "success": True,
        "has_stats": True,
        "stats": {
            "total_contribution": ranking.total_contribution,
            "total_kills": ranking.total_kills,
            "total_boss_kills": ranking.total_boss_kills,
            "total_waterings": ranking.total_waterings,
            "weeks_participated": ranking.weeks_participated,
            "weeks_won": ranking.weeks_won,
            "highest_rank": ranking.highest_rank_achieved,
            "first_contribution": ranking.first_contribution.isoformat() if ranking.first_contribution else None,
            "last_contribution": ranking.last_contribution.isoformat() if ranking.last_contribution else None
        }
    }


# ═══════════════════════════════════════════════════════════════════════════════
# BLOCKCHAIN ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@router.post("/record")
async def record_world_tree(
    record: WorldTreeRecord,
    db: Session = Depends(get_db)
):
    """Record World Tree winner on blockchain"""
    from app.models import WorldTreeRanking

    logger.info(f"⛓️ Recording World Tree winner for week {record.week_number}...")

    # TODO: Implement actual blockchain recording using Web3.py or similar
    # For now, just simulate success

    # Update database with blockchain record
    ranking = db.query(WorldTreeRanking).filter(
        WorldTreeRanking.shard_id == record.shard_id,
        WorldTreeRanking.week_number == record.week_number,
        WorldTreeRanking.rank == 1
    ).first()

    if ranking:
        ranking.blockchain_record_id = 12345  # Simulated record ID
        ranking.blockchain_tx_hash = "0x" + "a" * 64  # Simulated tx hash
        ranking.recorded_on_chain_at = datetime.utcnow()
        db.commit()

    logger.info(f"⛓️ Blockchain record successful (simulated)")

    return {
        "success": True,
        "record_id": 12345,
        "tx_hash": "0x" + "a" * 64,
        "message": "World Tree winner recorded on blockchain (simulated)"
    }


# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

def init_world_tree_routes(db_dependency, user_dependency):
    """Initialize route dependencies"""
    global get_db, get_current_user
    get_db = db_dependency
    get_current_user = user_dependency
    logger.info("🌍 World Tree routes initialized")
