# World Tree System - Final Unified Design

**Status**: Design Approved
**Date**: 2024-12-13
**Version**: 2.0 (Merged System)

This document defines the complete World Tree system combining chunk expansion, guild progression, and siege warfare.

---

## 🎯 Core Principles

1. **Individual → Guild**: Players claim solo, auto-joins their guild if they have one
2. **Neutral Factions**: Unguilded players assigned to neutral factions
3. **All Ranks Compete**: Weekly competition open to all ranks (progressive winners)
4. **Origin Tree Siege**: Community can bane the champion tree for resources
5. **Respawn Flexibility**: Neutral trees = public, guild trees = toggleable

---

## 📋 Seed Plot Lifecycle

### **Stage 1: Unclaimed Plot**

```
STATE: unclaimed
LOCATION: Edge chunks (initially -1, 1)
VISUAL: Glowing ground circle with runes
INTERACTION: [F] Claim (cost: exponential)
```

**Claim Cost Formula**:
```gdscript
base_cost = 1000
distance = abs(chunk_id)
cost = base_cost * pow(2, max(0, distance - 1))

# Examples:
# Chunk -1, 0, 1: 1000 gold
# Chunk -2, 2: 2000 gold
# Chunk -3, 3: 4000 gold
# Chunk -4, 4: 8000 gold
```

**Who Can Claim**:
- Any player with enough gold
- No guild requirement

---

### **Stage 2: Claimed Plot (Rank 0)**

```
STATE: claimed
RANK: 0 (Seedling)
OWNER: Individual player OR guild (if player is guilded)
FACTION: Auto-assigned based on player status
VISUAL: Small green sprout, subtle glow
```

**Ownership Assignment**:
```gdscript
func claim_seed_plot(player_id: String):
    var plot = seed_plots[chunk_id]
    plot.owner_id = player_id

    # Check if player has guild
    if GroupManager.has_group():
        plot.guild_id = GroupManager.get_guild_id()
        plot.guild_name = GroupManager.get_guild_name()
        plot.faction = "guild"
    else:
        # Assign neutral faction
        plot.guild_id = _assign_neutral_faction(player_id)
        plot.guild_name = _get_neutral_faction_name(plot.guild_id)
        plot.faction = "neutral"
```

**Neutral Factions** (for unguilded players):
- `neutral_wanderers` - "The Wanderers"
- `neutral_freefolk` - "The Free Folk"
- `neutral_exiles` - "The Exiles"
- `neutral_nomads` - "The Nomads"
- `neutral_seekers` - "The Seekers"

**Assignment Logic**:
```gdscript
func _assign_neutral_faction(player_id: String) -> String:
    # Hash player ID to consistently assign faction
    var hash = player_id.hash()
    var factions = ["neutral_wanderers", "neutral_freefolk", "neutral_exiles",
                    "neutral_nomads", "neutral_seekers"]
    return factions[hash % factions.size()]
```

**Features at Rank 0**:
- ✅ Contribution tracking
- ✅ Weekly competition eligibility
- ❌ No buildings yet
- ❌ No respawn binding yet
- ❌ No watering yet

---

### **Stage 3: Rank 1-7 (Guild Tree)**

```
UPGRADE REQUIREMENTS:
- Gold cost (see table below)
- Time delay (accelerated by watering)
- Tree must not be decaying

FEATURES UNLOCK:
- Rank 1+: Respawn binding, watering, 2 building slots
- Rank 3+: Vendor placement, 4 more slots
- Rank 5+: Warehouse, mine claiming
- Rank 7: Maximum features, prestige competition
```

#### **Rank Table**

| Rank | Name | Gold Cost | Build Time | Health | Building Slots | Protection Slots | Mine Limit |
|------|------|-----------|------------|--------|----------------|------------------|------------|
| 0 | Seedling | - | - | 0 | 0 | 0 | 0 |
| 1 | Sapling | 0 | 0h | 10,000 | 2 | 2 | 1 |
| 2 | Young Tree | 10,000 | 1h | 20,000 | 4 | 4 | 1 |
| 3 | Growing Tree | 25,000 | 4h | 35,000 | 6 | 6 | 2 |
| 4 | Mature Tree | 50,000 | 12h | 55,000 | 8 | 8 | 2 |
| 5 | Ancient Tree | 100,000 | 24h | 80,000 | 10 | 10 | 3 |
| 6 | Elder Tree | 200,000 | 48h | 110,000 | 12 | 12 | 4 |
| 7 | World Tree | 500,000 | 72h | 150,000 | 15 | 15 | 5 |

**Build Time Acceleration**:
```gdscript
actual_time = base_time * (1.0 - min(growth_bonus_accumulated, 0.5))

# Example: Rank 7 upgrade
# Base: 72 hours
# With 30% watering bonus: 72 * 0.70 = 50.4 hours
# With 50% bonus (cap): 72 * 0.50 = 36 hours
```

---

## 💧 Watering System

**Unlocks**: Rank 1+

**Mechanic**:
- Players bring **Purified Water** (consumable item)
- Can water once per 24 hours
- Provides growth bonus + contribution points

**Bonuses**:
```gdscript
REGULAR_WATER_BONUS = 0.10      # +10% growth speed
BLESSED_WATER_BONUS = 0.25       # +25% (rare item)
CONTRIBUTION_POINTS = 100        # Added to weekly score

func water_tree(is_blessed: bool = false):
    if is_blessed:
        growth_bonus_accumulated += 0.25
        contribution_score += 250  # Blessed is worth more
    else:
        growth_bonus_accumulated += 0.10
        contribution_score += 100

    last_watered = Time.get_unix_time_from_system()
```

**Purified Water Sources**:
- Craft at cleansed lava pools (see docs/CHUNK_AND_SPAWNING.md)
- Rare drop from water-based enemies
- Purchasable at high-level vendors

---

## 🏗️ Building System

**Unlocks**: Rank 1+ (limited by rank)

### **Building Types**

| Type | Min Rank | Function | Maintenance Cost/Week |
|------|----------|----------|----------------------|
| **Vendor (Weapons)** | 3 | Sell weapons to players | 200g |
| **Vendor (Armor)** | 3 | Sell armor to players | 200g |
| **Vendor (Consumables)** | 3 | Sell potions/food | 200g |
| **Warehouse** | 5 | Shared guild storage | 500g |
| **Shrine (Warfare)** | 4 | +10% damage buff | 500g |
| **Shrine (Vitality)** | 4 | +20% HP buff | 500g |
| **Shrine (Fortune)** | 4 | +15% gold/loot | 500g |
| **Crafting Station** | 4 | Upgrade equipment | 300g |

### **Building Placement**

```
      [B]           [C]
         \         /
          \       /
      [A]  TREE  [D]
          /       \
         /         \
      [F]           [E]

Slots: A, B, C, D, E, F
Unlock with rank progression
```

**Placement Rules**:
- Buildings placed in specific slots (A-F)
- Each building type can only be placed once
- Destroyed buildings leave slot empty (can rebuild)
- Protected buildings (via Runekeeper) invulnerable outside banes

---

## 🛡️ Respawn Binding

**Unlocks**: Rank 1+

### **Neutral Trees (Faction-Based)**

```gdscript
BINDING: Open to all players
DEATH: Respawn at tree
UI PROMPT: "Bind to [Faction Name] Tree?"
```

**Benefits**:
- Any player can bind to neutral faction trees
- Provides respawn safety for solo players
- Encourages community around neutral trees

### **Guild Trees (Private/Public Toggle)**

```gdscript
BINDING: Controlled by guild leader
TOGGLE: "Allow Non-Members to Bind"
DEFAULT: Guild members only

func can_bind_to_tree(player_id: String, tree: SeedPlot) -> bool:
    # Guild member check
    if tree.guild_id == player.get_guild_id():
        return true

    # Public binding enabled?
    if tree.allow_public_binding:
        return true

    return false
```

**Guild Leader Options**:
- [x] Members Only
- [x] Members + Allies
- [x] Open to All

---

## 🏆 Weekly Competition

**Schedule**: Every Sunday 00:00 UTC

**Eligibility**: ALL ranks (0-7)

**Scoring Formula**:
```gdscript
contribution_score = (
    gold_contributed * 1 +
    wood_contributed * 5 +
    stone_contributed * 5 +
    gems_contributed * 50 +
    kills * 2 +
    (time_minutes / 60) * 1
)

# Bonuses:
watering_bonus = times_watered * 100
building_bonus = building_count * 500
rank_bonus = tree_rank * 1000

total_score = contribution_score + watering_bonus + building_bonus + rank_bonus
```

### **Ranking Calculation**

```gdscript
func calculate_weekly_rankings():
    var all_trees = get_all_claimed_seed_plots()

    # Sort by total score
    all_trees.sort_custom(func(a, b):
        return _calculate_total_score(a) > _calculate_total_score(b)
    )

    # Top tree wins
    var winner = all_trees[0]

    # Move to origin chunk (Chunk -1)
    _promote_to_origin_chunk(winner)

    # Record on blockchain
    _record_on_chain(winner)

    # Reset weekly contributions
    _reset_weekly_scores()
```

### **Origin Chunk Promotion**

```
WINNER TREE:
- Moved to Chunk -1 (West Origin)
- Status: "World Tree Champion"
- Visual: Special golden particles
- Map icon: Crown symbol
- Benefits: Server-wide prestige

PREVIOUS CHAMPION:
- Moved back to original chunk
- Retains rank/buildings
- Loses champion status
```

---

## ⚔️ Bane System (Siege Warfare)

**Target**: Origin chunk tree only (current champion)

**Objective**: Community vs. holding guild for resources

### **Siege Flow**

```
STEP 1: DECLARATION
- Attacking guild plants "Bane Stone" near tree
- Cost: 50,000 gold (significant investment)
- Countdown begins: 5 days

STEP 2: PREPARATION PHASE (5 days)
- Defending guild fortifies
- Attackers gather forces
- Server-wide announcement

STEP 3: BANE WINDOW (2 hours)
- Tree becomes vulnerable
- Runekeeper protection disabled
- Buildings can be damaged
- PvP enabled in area

STEP 4: OUTCOME
├─ DEFENDERS WIN (tree survives)
│  └─ Bane stone destroyed, attackers lose gold
│
└─ ATTACKERS WIN (tree destroyed)
   ├─ Tree downgraded 2 ranks
   ├─ Buildings destroyed
   ├─ Warehouse loot drops (public)
   ├─ Tree removed from origin chunk
   └─ Next week's winner promoted
```

### **Bane Stone**

```gdscript
HP: 50,000
DAMAGE SOURCES: Player attacks only
DEFENSE: None (can be destroyed before window)
PLACEMENT: Within 200m of tree
COST: 50,000 gold (non-refundable)
```

### **Loot Distribution**

```gdscript
ON_TREE_DESTROYED:
    # Drop warehouse contents
    var loot = {
        "gold": tree.warehouse_gold,
        "wood": tree.warehouse_wood,
        "stone": tree.warehouse_stone,
        "gems": tree.warehouse_gems
    }

    # Create public loot chest
    create_loot_chest(tree.position, loot)

    # Participants get bonus
    distribute_siege_rewards(attackers, defenders)
```

**Siege Rewards** (all participants):
- Attackers (if win): Warehouse loot + bonus XP
- Defenders (if win): Bonus gold from treasury + XP
- All participants: Special "Siege Veteran" achievement

---

## 💰 Resource Mines

**Unlocks**: Rank 5+

**Mechanic**:
- Trees can claim resource mines in their chunk
- Mines generate passive income
- Limit based on rank (3-5 mines)

**Mine Types**:
- **Gold Mine**: 500g/hour
- **Stone Quarry**: 100 stone/hour
- **Lumber Mill**: 100 wood/hour
- **Gem Vein**: 5 gems/hour (rare)

**Claiming**:
```gdscript
func claim_mine(tree_id: String, mine_id: String):
    var tree = get_tree_data(tree_id)

    # Check limit
    if tree.claimed_mine_ids.size() >= tree.get_mine_limit_for_rank():
        return false

    # Check distance
    var mine = get_mine_data(mine_id)
    if mine.chunk_id != tree.chunk_id:
        return false

    # Claim
    tree.claimed_mine_ids.append(mine_id)
    mine.owner_tree_id = tree_id
    return true
```

---

## 🗄️ Warehouse System

**Unlocks**: Rank 5+

**Storage**:
- Shared guild bank
- Stores gold, wood, stone, gems
- Permissions: Leader/Officers can withdraw
- Weekly maintenance cost: 500g

**Contribution**:
```gdscript
func deposit_to_warehouse(tree_id: String, resources: Dictionary):
    var tree = get_tree_data(tree_id)

    tree.warehouse_gold += resources.get("gold", 0)
    tree.warehouse_wood += resources.get("wood", 0)
    tree.warehouse_stone += resources.get("stone", 0)
    tree.warehouse_gems += resources.get("gems", 0)

    # Add to contribution score
    add_contribution(tree_id, player_id, resources)
```

---

## 📊 Database Schema Updates

### **seed_plots Table (Extended)**

```sql
ALTER TABLE seed_plots ADD COLUMN tree_rank INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_health INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_max_health INTEGER DEFAULT 0;

-- Guild/Faction
ALTER TABLE seed_plots ADD COLUMN guild_id TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN guild_name TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN faction TEXT DEFAULT 'individual';

-- Upgrades
ALTER TABLE seed_plots ADD COLUMN upgrade_started_at DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN upgrade_target_rank INTEGER NULL;

-- Watering
ALTER TABLE seed_plots ADD COLUMN last_watered DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN times_watered INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN growth_bonus_accumulated FLOAT DEFAULT 0.0;

-- Respawn
ALTER TABLE seed_plots ADD COLUMN allow_public_binding BOOLEAN DEFAULT 0;

-- Warehouse
ALTER TABLE seed_plots ADD COLUMN warehouse_gold INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_wood INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_stone INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_gems INTEGER DEFAULT 0;

-- Mines
ALTER TABLE seed_plots ADD COLUMN claimed_mine_ids JSON NULL;

-- Origin chunk
ALTER TABLE seed_plots ADD COLUMN is_origin_champion BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN champion_since DATETIME NULL;
```

### **seed_plot_buildings Table (NEW)**

```sql
CREATE TABLE seed_plot_buildings (
    id INTEGER PRIMARY KEY,
    seed_plot_id INTEGER NOT NULL,
    building_type TEXT NOT NULL,
    position_slot TEXT NOT NULL,

    -- Health
    health INTEGER DEFAULT 1000,
    max_health INTEGER DEFAULT 1000,

    -- Protection
    is_protected BOOLEAN DEFAULT 0,

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    destroyed_at DATETIME NULL,

    -- Vendor data
    vendor_inventory JSON NULL,
    vendor_prices JSON NULL,
    total_sales INTEGER DEFAULT 0,

    -- Shrine data
    shrine_buff_type TEXT NULL,

    FOREIGN KEY(seed_plot_id) REFERENCES seed_plots(id)
);
```

### **bane_stones Table (NEW)**

```sql
CREATE TABLE bane_stones (
    id INTEGER PRIMARY KEY,
    target_tree_id INTEGER NOT NULL,
    attacker_guild_id TEXT NOT NULL,

    -- Health
    health INTEGER DEFAULT 50000,
    max_health INTEGER DEFAULT 50000,

    -- Timeline
    planted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    window_start DATETIME NULL,
    window_end DATETIME NULL,

    -- Status
    is_active BOOLEAN DEFAULT 0,
    outcome TEXT NULL,  -- "defenders_win", "attackers_win"

    FOREIGN KEY(target_tree_id) REFERENCES seed_plots(id)
);
```

---

## 🎨 Visual Progression

| Rank | Visual Description |
|------|-------------------|
| **0: Seedling** | Tiny green sprout, faint glow |
| **1: Sapling** | Small tree trunk, sparse leaves, green glow |
| **2: Young Tree** | Growing trunk, more leaves, brighter glow |
| **3: Growing Tree** | Thick trunk, full canopy, particles |
| **4: Mature Tree** | Large canopy, golden tint starting |
| **5: Ancient Tree** | Massive canopy, golden glow, many particles |
| **6: Elder Tree** | Huge tree, bright golden glow, magical aura |
| **7: World Tree** | Enormous tree, radiant gold, visible from distance |
| **Champion** | World Tree + crown particles + map icon |

---

## 📅 Weekly Timeline

```
MONDAY 00:00 UTC:
- New week begins
- Contribution scores reset
- Previous champion logged to history

THROUGHOUT WEEK:
- Players contribute resources
- Trees get watered
- Buildings maintained
- Rankings update live

SATURDAY:
- Final push for top spot
- Bane declarations finalized

SUNDAY 00:00 UTC:
- Rankings calculated
- Winner promoted to origin chunk
- Champion crowned
- Blockchain record created
- Server announcement
```

---

## 🎯 Player Progression Path

### **Solo Player (Unguilded)**

```
Day 1: Claim edge plot (1000g) → Assigned to "The Wanderers"
Week 1: Contribute wood/stone, reach 5,000 points
  └─ Result: Rank 15/30 trees

Week 2: Upgrade to Rank 1, bind respawn
Week 3: Farm resources, water daily
  └─ Result: Rank 8/35 trees

Month 2: Reach Rank 3, place vendor building
Month 3: Join a guild, tree auto-transferred
Month 4: Guild reaches Rank 5, claims gold mine
Month 6: Compete for origin chunk (Rank 6 tree)
```

### **Guild Player**

```
Day 1: Guild leader claims plot (2000g for chunk -2)
  └─ Tree assigned to guild immediately

Week 1: Guild focuses contributions
  └─ 20 members contributing = high score
  └─ Result: Rank 2/30 trees (behind Rank 4 tree)

Month 1: Reach Rank 4, place shrine buildings
Month 2: Claim resource mines, warehouse operational
Month 3: WIN WEEKLY → Promoted to origin chunk!
  └─ Champion status, blockchain recorded

Month 4: DEFEND BANE → Community attacks
  └─ Guild rallies, successfully defends

Month 5: LOSE WEEKLY → New guild wins
  └─ Moved back to chunk -2, retain rank
```

---

## 🚀 Implementation Priority

### **Phase 1: Core Claiming (DONE)**
- ✅ Database tables
- ✅ Backend API
- ✅ ChunkExpansionManager
- ✅ Contribution tracking

### **Phase 2: Guild Integration (NEXT)**
- [ ] Neutral faction assignment
- [ ] Auto-guild assignment for guilded players
- [ ] Update claim flow with faction logic
- [ ] Test faction assignment

### **Phase 3: Rank System**
- [ ] Database migration (add rank columns)
- [ ] Rank upgrade logic
- [ ] Visual progression (canopy/glow scaling)
- [ ] Watering system integration

### **Phase 4: Buildings**
- [ ] Building placement UI
- [ ] Vendor NPC spawning
- [ ] Warehouse storage system
- [ ] Shrine buff application

### **Phase 5: Respawn Binding**
- [ ] Player-tree binding system
- [ ] Respawn logic at tree location
- [ ] Public/private toggle
- [ ] Neutral tree access

### **Phase 6: Weekly Competition**
- [ ] Ranking calculation (all scores)
- [ ] Origin chunk promotion
- [ ] Champion visual effects
- [ ] Blockchain integration

### **Phase 7: Bane System**
- [ ] Bane stone placement
- [ ] Countdown/window mechanics
- [ ] Building damage system
- [ ] Loot distribution

---

## 📝 Next Steps

1. ✅ **User approval** - Design confirmed
2. ⏳ **Database migration** - Add rank/guild columns
3. ⏳ **Update ChunkExpansionManager** - Faction assignment
4. ⏳ **Create neutral faction system**
5. ⏳ **Build rank upgrade UI**
6. ⏳ **Implement watering mechanics**
7. ⏳ **Test full progression flow**

---

**Ready to begin Phase 2 implementation!** 🚀
