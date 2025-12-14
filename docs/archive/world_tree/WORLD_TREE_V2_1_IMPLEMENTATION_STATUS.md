# World Tree v2.1 Implementation Status

**Status**: Database Migration Complete ✓
**Date**: 2024-12-14
**Design**: docs/WORLD_TREE_FINAL_DESIGN_V2.1.md

---

## ✅ Completed

### **1. Database Migration (COMPLETE)**

**Migration File**: `backend/alembic/versions/8f9a1b2c3d4e_add_world_tree_v2_1_features.py`

**Smart Migration Script**: `backend/run_smart_migration.py` ✓ Executed Successfully

**New Tables Created**:
- ✅ `resource_mines` - Active collection mines (Fix #7)
- ✅ `seed_plot_buildings` - Building placement system
- ✅ `bane_stones` - Siege warfare with scheduled windows (Fix #10)
- ✅ `seasonal_rankings` - All-time leaderboard (Fix #9)

**Extended seed_plots Table** (28 new columns):
- ✅ Dual ownership (original_owner_id, current_guild_id)
- ✅ Champion migration (is_origin_champion, champion_since, is_decaying)
- ✅ Tree ranks (tree_rank, tree_health, tree_max_health)
- ✅ Guild/faction (guild_name, faction)
- ✅ Watering system (last_watered, times_watered, growth_bonus_accumulated)
- ✅ Warehouse safe + overflow (8 columns for protected/vulnerable storage)
- ✅ Resource mines (claimed_mine_ids)
- ✅ Bane defense (defense_window_hour, defense_window_timezone_offset)
- ✅ Upgrade system (upgrade_started_at, upgrade_target_rank)
- ✅ Respawn binding (allow_public_binding)

**Database Verified**:
```
[SUCCESS] World Tree v2.1 migration completed!
- All 28 seed_plots columns added
- 4 new tables created with indexes
- boss_kills column added to world_tree_contributions
```

---

## 🔨 Next Steps (Implementation Order)

### **2. Update Backend Models (backend/app/models.py)**

**Task**: Add v2.1 columns to SeedPlot model + create 4 new model classes

**Required Changes**:

```python
# Update SeedPlot class with v2.1 columns
class SeedPlot(Base):
    # ... existing columns ...

    # Fix #1: Dual ownership
    original_owner_id = Column(Integer, ForeignKey('users.id'), nullable=True)
    last_ownership_transfer = Column(DateTime, nullable=True)
    current_guild_id = Column(String(64), nullable=True)
    last_guild_change = Column(DateTime, nullable=True)

    # Fix #2: Champion migration
    is_origin_champion = Column(Boolean, default=False)
    champion_since = Column(DateTime, nullable=True)
    is_decaying = Column(Boolean, default=False)
    decay_complete_at = Column(DateTime, nullable=True)
    migration_expires = Column(DateTime, nullable=True)
    original_chunk_id = Column(Integer, nullable=True)

    # Tree ranks
    tree_rank = Column(Integer, default=0)
    tree_health = Column(Integer, default=0)
    tree_max_health = Column(Integer, default=0)

    # Guild/faction
    guild_name = Column(String(128), nullable=True)
    faction = Column(String(32), default='individual')

    # Watering
    last_watered = Column(DateTime, nullable=True)
    times_watered = Column(Integer, default=0)
    growth_bonus_accumulated = Column(Float, default=0.0)

    # Warehouse (Fix #6)
    warehouse_safe_gold = Column(Integer, default=0)
    warehouse_safe_wood = Column(Integer, default=0)
    warehouse_safe_stone = Column(Integer, default=0)
    warehouse_safe_gems = Column(Integer, default=0)
    warehouse_overflow_gold = Column(Integer, default=0)
    warehouse_overflow_wood = Column(Integer, default=0)
    warehouse_overflow_stone = Column(Integer, default=0)
    warehouse_overflow_gems = Column(Integer, default=0)

    # Mines
    claimed_mine_ids = Column(Text, nullable=True)  # JSON

    # Bane defense (Fix #10)
    defense_window_hour = Column(Integer, default=20)
    defense_window_timezone_offset = Column(Integer, default=0)

    # Respawn
    allow_public_binding = Column(Boolean, default=False)

    # Upgrades
    upgrade_started_at = Column(DateTime, nullable=True)
    upgrade_target_rank = Column(Integer, nullable=True)

    # Relationships (add)
    original_owner = relationship("User", foreign_keys=[original_owner_id])
    buildings = relationship("SeedPlotBuilding", back_populates="seed_plot")
    resource_mines = relationship("ResourceMine", back_populates="owner_tree")
    bane_stones = relationship("BaneStone", back_populates="target_tree")


# NEW MODEL: ResourceMine (Fix #7)
class ResourceMine(Base):
    __tablename__ = 'resource_mines'

    id = Column(Integer, primary_key=True)
    shard_id = Column(String(32), nullable=False, index=True)
    chunk_id = Column(Integer, nullable=False)
    mine_type = Column(String(16), nullable=False)  # "gold", "stone", "wood", "gems"
    position_x = Column(Float, nullable=False)
    position_y = Column(Float, nullable=False)

    # Ownership
    owner_tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=True)

    # Active collection tracking (Fix #7)
    last_collected = Column(DateTime, nullable=True)
    last_collector = Column(String(64), nullable=True)
    quick_collect_count = Column(Integer, default=0)

    # Accumulated resources
    resources_accumulated = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    owner_tree = relationship("SeedPlot", back_populates="resource_mines")


# NEW MODEL: SeedPlotBuilding
class SeedPlotBuilding(Base):
    __tablename__ = 'seed_plot_buildings'

    id = Column(Integer, primary_key=True)
    seed_plot_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False)
    building_type = Column(String(32), nullable=False)
    position_slot = Column(String(1), nullable=False)  # A-F

    # Health
    health = Column(Integer, default=1000)
    max_health = Column(Integer, default=1000)

    # Protection
    is_protected = Column(Boolean, default=False)

    # Migration (Fix #2)
    is_active = Column(Boolean, default=True)
    activation_cost = Column(Integer, default=0)
    original_cost = Column(Integer, nullable=False)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    destroyed_at = Column(DateTime, nullable=True)
    activated_at = Column(DateTime, nullable=True)

    # Vendor data
    vendor_inventory = Column(Text, nullable=True)  # JSON
    vendor_prices = Column(Text, nullable=True)  # JSON
    total_sales = Column(Integer, default=0)

    # Shrine data
    shrine_buff_type = Column(String(32), nullable=True)

    # Relationships
    seed_plot = relationship("SeedPlot", back_populates="buildings")


# NEW MODEL: BaneStone (Fix #5, #10)
class BaneStone(Base):
    __tablename__ = 'bane_stones'

    id = Column(Integer, primary_key=True)
    shard_id = Column(String(32), nullable=False)
    target_tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False)
    attacker_guild_id = Column(String(64), nullable=False)

    # Health
    health = Column(Integer, default=50000)
    max_health = Column(Integer, default=50000)

    # Timeline (Fix #10 - Scheduled windows)
    planted_at = Column(DateTime, default=datetime.utcnow)
    window_start = Column(DateTime, nullable=True)
    window_end = Column(DateTime, nullable=True)

    # Status
    is_active = Column(Boolean, default=False)
    outcome = Column(String(16), nullable=True)

    # Relationships
    target_tree = relationship("SeedPlot", back_populates="bane_stones")


# NEW MODEL: SeasonalRanking (Fix #9)
class SeasonalRanking(Base):
    __tablename__ = 'seasonal_rankings'

    id = Column(Integer, primary_key=True)
    shard_id = Column(String(32), nullable=False)
    tree_id = Column(Integer, ForeignKey('seed_plots.id'), nullable=False)
    guild_id = Column(String(64), nullable=False)

    # All-time stats
    total_contribution = Column(Integer, default=0)
    total_kills = Column(Integer, default=0)
    total_boss_kills = Column(Integer, default=0)
    total_waterings = Column(Integer, default=0)
    weeks_participated = Column(Integer, default=0)
    weeks_won = Column(Integer, default=0)

    # Milestones
    highest_rank_achieved = Column(Integer, default=0)
    first_contribution = Column(DateTime, nullable=True)
    last_contribution = Column(DateTime, nullable=True)

    # Relationships
    tree = relationship("SeedPlot")


# UPDATE: WorldTreeContribution - Add boss_kills
class WorldTreeContribution(Base):
    # ... existing columns ...
    boss_kills = Column(Integer, default=0)  # NEW (Fix #11)
```

---

### **3. Update API Routes (backend/app/routes/world_tree_routes.py)**

**New Endpoints Needed**:

```python
# Tree Upgrades
POST /api/world-tree/seed-plots/{chunk_id}/upgrade
  → Start upgrading tree to next rank

POST /api/world-tree/seed-plots/{chunk_id}/water
  → Water tree for growth bonus

# Buildings
POST /api/world-tree/seed-plots/{chunk_id}/buildings
  → Place building in slot
GET /api/world-tree/seed-plots/{chunk_id}/buildings
  → List all buildings
POST /api/world-tree/seed-plots/{chunk_id}/buildings/{building_id}/activate
  → Activate migrated building (50% cost)

# Warehouse
POST /api/world-tree/seed-plots/{chunk_id}/warehouse/deposit
  → Deposit resources (safe fills first, then overflow)
POST /api/world-tree/seed-plots/{chunk_id}/warehouse/withdraw
  → Withdraw resources (overflow first, then safe)
POST /api/world-tree/seed-plots/{chunk_id}/warehouse/transfer
  → Instant transfer to new tree (10k gold, during migration)

# Resource Mines
POST /api/world-tree/seed-plots/{chunk_id}/mines/{mine_id}/claim
  → Claim a resource mine
POST /api/world-tree/seed-plots/{chunk_id}/mines/{mine_id}/collect
  → Collect from mine (with active collection logic)

# Bane System
POST /api/world-tree/bane-stones
  → Plant bane stone (50k gold, target tree)
GET /api/world-tree/bane-stones/{bane_id}
  → Get bane stone status
POST /api/world-tree/bane-stones/{bane_id}/attack
  → Attack bane stone during window

# Ownership
POST /api/world-tree/seed-plots/{chunk_id}/transfer-ownership
  → Transfer permanent ownership to guild member
POST /api/world-tree/seed-plots/{chunk_id}/change-guild
  → Move tree to different guild (7-day cooldown)

# Seasonal Rankings
GET /api/world-tree/rankings/seasonal
  → All-time leaderboard
GET /api/world-tree/rankings/seasonal/{guild_id}
  → Guild's seasonal stats
```

**Update Existing Endpoints**:
- `/api/world-tree/seed-plots/{chunk_id}/claim` → Add neutral faction assignment
- `/api/world-tree/seed-plots/{chunk_id}/contribute` → Add boss_kills parameter
- `/api/world-tree/rankings` → Implement single winner + 3-tier removal
- `/api/world-tree/rankings/current` → Apply neutral faction 1.5x multiplier

---

### **4. Update ChunkExpansionManager.gd**

**New Functions Needed**:

```gdscript
# Claim cost calculation (Fix #8 - Logarithmic)
func calculate_claim_cost(chunk_id: int) -> int:
    var distance = abs(chunk_id)
    if distance <= 1:
        return 1000
    if distance <= 3:
        return 1000 * pow(2, distance - 1)
    return 8000 + (distance - 3) * 5000

# Neutral faction assignment (Fix #3)
func assign_neutral_faction(player_id: String) -> String:
    var hash = player_id.hash()
    var factions = ["neutral_wanderers", "neutral_freefolk", "neutral_exiles",
                    "neutral_nomads", "neutral_seekers"]
    return factions[hash % factions.size()]

# Contribution with neutral multiplier (Fix #3)
func add_contribution(tree_id: int, player_id: String, contribution: Dictionary):
    var tree = get_seed_plot(tree_id)
    var base_score = calculate_contribution_score(contribution)

    # Apply neutral faction multiplier
    if tree.faction.begins_with("neutral_"):
        base_score *= 1.5

    tree.contribution_score += base_score

# Tree duplication (Fix #2)
func duplicate_tree_to_origin(winner_tree_id: int):
    var original = get_seed_plot(winner_tree_id)

    # Create duplicate at origin chunk
    var duplicate = create_seed_plot(-1)
    duplicate.original_owner_id = original.original_owner_id
    duplicate.current_guild_id = original.current_guild_id
    duplicate.tree_rank = original.tree_rank
    duplicate.is_origin_champion = true
    duplicate.champion_since = Time.get_unix_time_from_system()
    duplicate.migration_expires = duplicate.champion_since + (7 * 86400)
    duplicate.original_chunk_id = original.chunk_id

    # Copy building layouts (inactive)
    for building in original.buildings:
        var copy = duplicate_building(building)
        copy.is_active = false
        copy.activation_cost = building.original_cost * 0.5
        duplicate.buildings.append(copy)

    # Mark original as decaying
    original.is_decaying = true
    original.decay_complete_at = duplicate.migration_expires

    # Auto-migrate respawn bindings
    migrate_respawn_bindings(original.id, duplicate.id)

# Mine collection with active requirement (Fix #7)
const MINE_COLLECTION_COOLDOWN = 1800  # 30 minutes
const DIMINISHING_RETURN_FACTOR = 0.8

func collect_mine(tree_id: int, mine_id: int, player_id: String) -> int:
    var mine = get_mine(mine_id)

    var hours_since_last = (now() - mine.last_collected) / 3600.0
    var hours_accumulated = min(hours_since_last, 4)
    var gold_accumulated = hours_accumulated * 500

    var time_since_last = now() - mine.last_collected
    if time_since_last < MINE_COLLECTION_COOLDOWN:
        gold_accumulated *= pow(DIMINISHING_RETURN_FACTOR, mine.quick_collect_count)
        mine.quick_collect_count += 1
    else:
        mine.quick_collect_count = 0

    mine.last_collected = now()
    mine.last_collector = player_id

    return int(gold_accumulated)

# Warehouse safe/overflow logic (Fix #6)
const WAREHOUSE_SAFE_LIMITS = {
    "gold": 50000,
    "wood": 5000,
    "stone": 5000,
    "gems": 500
}

func deposit_to_warehouse(tree_id: int, resource_type: String, amount: int):
    var tree = get_seed_plot(tree_id)
    var safe_limit = WAREHOUSE_SAFE_LIMITS[resource_type]
    var current_safe = tree.get("warehouse_safe_" + resource_type)

    # Fill safe first
    var to_safe = min(amount, safe_limit - current_safe)
    tree.set("warehouse_safe_" + resource_type, current_safe + to_safe)

    # Excess to overflow
    var to_overflow = amount - to_safe
    if to_overflow > 0:
        var current_overflow = tree.get("warehouse_overflow_" + resource_type)
        tree.set("warehouse_overflow_" + resource_type, current_overflow + to_overflow)

# Scheduled bane window (Fix #10)
func plant_bane_stone(tree_id: int, attacker_guild_id: String):
    var tree = get_seed_plot(tree_id)
    var planted_at = Time.get_unix_time_from_system()

    # Calculate window aligned to defender's preferred time
    var window_start = planted_at + (5 * 86400)  # 5 days from now
    window_start = align_to_hour(window_start, tree.defense_window_hour, tree.defense_window_timezone_offset)

    var bane_stone = {
        "planted_at": planted_at,
        "window_start": window_start,
        "window_end": window_start + 7200,  # 2 hours
        "health": 50000
    }

    # Notify both guilds
    notify_guild(tree.current_guild_id, "Bane declared! Defense on " + format_time(window_start))
    notify_guild(attacker_guild_id, "Bane planted! Siege on " + format_time(window_start))

# Decay system (Fix #12)
const ORIGIN_CHAMPION_DECAY_DAYS = 14
const DYNAMIC_CHUNK_DECAY_DAYS = 90

func check_decay(tree_id: int):
    var tree = get_seed_plot(tree_id)
    var days_inactive = (now() - tree.last_contribution) / 86400.0

    var decay_threshold = DYNAMIC_CHUNK_DECAY_DAYS
    if tree.is_origin_champion:
        decay_threshold = ORIGIN_CHAMPION_DECAY_DAYS

    if days_inactive >= decay_threshold:
        despawn_tree(tree_id)
    elif days_inactive >= decay_threshold - 7:
        notify_owner(tree.original_owner_id, "Tree will despawn in 7 days without activity")
```

---

### **5. Create Godot UI Scenes**

**Scenes to Create**:
- `scenes/ui/SeedPlotClaimUI.tscn` - Claim seed plot interface
- `scenes/ui/SeedPlotUpgradeUI.tscn` - Tree rank upgrade panel
- `scenes/ui/SeedPlotWarehouse UI.tscn` - Safe/overflow warehouse display
- `scenes/ui/BuildingPlacementUI.tscn` - Building slot placement
- `scenes/ui/MineCollectionUI.tscn` - Resource mine interface
- `scenes/ui/BanePlantUI.tscn` - Bane stone placement
- `scenes/ui/SeasonalRankingsUI.tscn` - All-time leaderboard

---

## 📊 Testing Checklist

**Once implementation is complete**:

### **Database Tests**
- [ ] Verify all 28 new seed_plots columns exist
- [ ] Verify 4 new tables created
- [ ] Test migration rollback/upgrade cycle
- [ ] Verify indexes are working

### **Backend Tests**
- [ ] Test neutral faction assignment
- [ ] Test dual ownership (original_owner_id + current_guild_id)
- [ ] Test warehouse safe/overflow separation
- [ ] Test mine collection with diminishing returns
- [ ] Test claim cost logarithmic formula
- [ ] Test tree duplication logic
- [ ] Test bane window scheduling

### **Godot Tests**
- [ ] Test claiming seed plot with logarithmic cost
- [ ] Test neutral faction 1.5x multiplier in rankings
- [ ] Test tree rank upgrades
- [ ] Test watering system
- [ ] Test building placement
- [ ] Test warehouse deposit/withdraw
- [ ] Test mine collection
- [ ] Test bane stone planting
- [ ] Test migration flow (win championship → duplicate → migrate)
- [ ] Test 90-day decay for dynamic chunks
- [ ] Test 14-day decay for champion

---

## 🎯 Critical Implementation Notes

1. **Claim Cost Formula** (Fix #8):
   - Chunks ±1-3: Exponential (1k, 2k, 4k, 8k)
   - Chunks ±4+: Linear (+5k per chunk)
   - Prevents impossible costs at distant chunks

2. **Neutral Faction Multiplier** (Fix #3):
   - ALL contributions to neutral trees × 1.5
   - Balances coordination disadvantage
   - Applied in scoring calculation

3. **Universal Bane** (Fix #4):
   - ANY tree can be sieged (not just champion)
   - Champion gets 3-day protection (Sun-Wed)
   - Creates natural competitive tiers

4. **Tree Duplication** (Fix #2):
   - Winner tree duplicated to origin chunk
   - Original tree decays over 7 days
   - Buildings copied but inactive (50% cost to activate)
   - Warehouse must be transferred (10k gold instant)

5. **Warehouse Safe Storage** (Fix #6):
   - 50k gold, 5k resources protected
   - Overflow vulnerable to sieges
   - Smart guilds keep wealth distributed

6. **Mine Active Collection** (Fix #7):
   - 30-minute cooldown for 100% yield
   - Spam collection: 100% → 80% → 64% → ...
   - Max 4-hour accumulation per mine

7. **Extended Decay** (Fix #12):
   - Dynamic chunks: 90 days (3-month vacation)
   - Origin champion: 14 days (prestige = responsibility)
   - Warnings at 7 days before despawn

---

## 📋 File Summary

**Created**:
- ✅ `docs/WORLD_TREE_FINAL_DESIGN_V2.1.md` - Complete design specification
- ✅ `backend/alembic/versions/8f9a1b2c3d4e_add_world_tree_v2_1_features.py` - Migration file
- ✅ `backend/run_smart_migration.py` - Smart migration script (executed successfully)
- ✅ `backend/complete_migration_v2_1.sql` - SQL migration script (backup)
- ✅ `docs/WORLD_TREE_V2_1_IMPLEMENTATION_STATUS.md` - This file

**To Update**:
- ⏳ `backend/app/models.py` - Add v2.1 columns + 4 new models
- ⏳ `backend/app/routes/world_tree_routes.py` - Add new endpoints
- ⏳ `scripts/systems/ChunkExpansionManager.gd` - Add v2.1 logic
- ⏳ `docs/API_CONTRACT.md` - Document new endpoints

**To Create**:
- ⏳ Godot UI scenes for World Tree interactions
- ⏳ Tests for all new features

---

## ✅ Ready for Next Phase

**Database migration is 100% complete and verified.**
**Next step**: Update `backend/app/models.py` with the code snippets above.

All design decisions are documented in `WORLD_TREE_FINAL_DESIGN_V2.1.md`.
All fixes are tracked with issue numbers (Fix #1-12) for reference.

**Implementation can proceed incrementally** - each phase can be tested independently before moving to the next.
