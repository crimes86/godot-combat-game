# World Tree System Merge Plan

**Status**: Planning
**Date**: 2024-12-13

This document outlines how to merge the **old guild-based World Tree system** with the **new chunk expansion system**.

---

## 🔄 Two Different Systems

### **OLD SYSTEM** (Guild Trees)
- **Purpose**: Guild base building (inspired by Shadowbane)
- **Location**: Players plant trees at "seed plots" across the world
- **Ownership**: Guild-based (1 tree per guild)
- **Features**:
  - Tree ranks 1-7 (Sapling → World Tree)
  - Rank upgrades with gold + time
  - Watering for growth bonuses
  - Building placement (vendors, warehouses, shrines)
  - Runekeeper protection slots
  - Bane system (siege warfare)
  - Respawn points for guild members

### **NEW SYSTEM** (Chunk Expansion)
- **Purpose**: Player-driven world expansion
- **Location**: Edge chunks only (starts at -1 and 1)
- **Ownership**: Individual players claim with gold
- **Features**:
  - World expands when both edge plots claimed
  - Weekly competition for "World Tree" title
  - Contribution tracking (gold, resources, kills, time)
  - Top player promoted to origin chunk (-1)
  - Blockchain recording of winners
  - Decay/removal if inactive

---

## 🎯 Merged System Concept

Combine both systems so that:
1. **Edge chunks** have claimable **seed plots** for expansion (NEW)
2. **Claimed seed plots** can be upgraded to **guild World Trees** with features (OLD)
3. **Weekly competition** determines which tree becomes the **prestigious origin World Tree** (NEW)

---

## 📋 Feature Matrix

| Feature | Old Guild System | New Chunk System | **Merged System** |
|---------|------------------|------------------|-------------------|
| **Plot Claiming** | ❌ Free planting | ✅ Gold cost, exponential scaling | ✅ Keep new system |
| **World Expansion** | ❌ N/A | ✅ Both edges claimed → expand | ✅ Keep new system |
| **Tree Ranks** | ✅ Ranks 1-7 with upgrades | ❌ N/A | ✅ **Keep** - Add ranks to seed plots |
| **Watering System** | ✅ Daily watering for bonuses | ❌ N/A | ✅ **Keep** - Contributes to weekly score |
| **Building Placement** | ✅ Vendors, warehouses, shrines | ❌ N/A | ✅ **Keep** - Unlock at higher ranks |
| **Guild Ownership** | ✅ Guild-based | ❌ Individual player | ⚠️ **Modify** - Start individual, upgrade to guild |
| **Respawn Points** | ✅ Guild members bind here | ❌ N/A | ✅ **Keep** - Guild benefit |
| **Protection Slots** | ✅ Runekeeper protects buildings | ❌ N/A | ✅ **Keep** - Higher ranks unlock more |
| **Bane System** | ✅ Siege warfare | ❌ N/A | ⚠️ **Consider** - Only for high-rank trees? |
| **Weekly Competition** | ❌ N/A | ✅ Top score → origin chunk | ✅ **Keep** - Competitive layer |
| **Contribution Tracking** | ❌ N/A | ✅ Gold, resources, kills, time | ✅ **Keep** - Feeds into score |
| **Decay System** | ❌ N/A | ✅ 7 days inactivity → removal | ✅ **Keep** - Prevents dead plots |
| **Blockchain Recording** | ❌ N/A | ✅ Winners on Mantle L2 | ✅ **Keep** - Prestige value |

---

## 🏗️ Proposed Merged Architecture

### **Seed Plot Lifecycle**

```
UNCLAIMED PLOT
     │
     ├─ Player claims with gold (exponential cost)
     │
     ▼
CLAIMED PLOT (Rank 0)
     │
     ├─ Player contributes resources/kills/time
     ├─ Contribution score increases
     ├─ Can upgrade to Rank 1 (Sapling)
     │
     ▼
RANK 1: SAPLING (Guild Tree)
     │
     ├─ Watering system unlocks
     ├─ Respawn point for owner/guild
     ├─ 2 building slots unlock
     ├─ Can upgrade to Rank 2
     │
     ▼
RANK 2-6: GROWING TREE
     │
     ├─ More building slots
     ├─ More protection slots
     ├─ More resource mine claims
     ├─ Vendor placement
     │
     ▼
RANK 7: WORLD TREE
     │
     ├─ Maximum features unlocked
     ├─ Competes for origin chunk promotion
     │
     ▼
WEEKLY COMPETITION
     │
     ├─ Top score → Moved to Chunk -1 (West Origin)
     ├─ "World Tree Champion" title
     ├─ Recorded on blockchain
     └─ Server-wide prestige
```

---

## 🔧 Implementation Plan

### **Phase 1: Core Seed Plot (✅ DONE)**
- [x] Database tables
- [x] Backend API
- [x] ChunkExpansionManager autoload
- [x] Claim cost calculation
- [x] Contribution tracking
- [x] Weekly rankings

### **Phase 2: Seed Plot UI (TO DO)**
- [ ] Create SeedPlotClaimUI.tscn
- [ ] Create SeedPlotContributionUI.tscn
- [ ] Update existing SeedPlot.gd or create new one
- [ ] Add player.deduct_gold() method
- [ ] Test claim → expansion flow

### **Phase 3: Tree Upgrades (TO DO)**
- [ ] Add rank system to seed_plots table
- [ ] Upgrade UI (show rank, cost, progress)
- [ ] Implement upgrade timer (from WorldTreeData)
- [ ] Visual changes per rank (canopy size, glow)
- [ ] Merge watering into contribution system

### **Phase 4: Guild Features (TO DO)**
- [ ] Allow plot owner to form guild
- [ ] Guild member permissions
- [ ] Building placement system
  - Vendor NPCs
  - Warehouse (shared storage)
  - Shrines (buffs)
- [ ] Runekeeper protection slots
- [ ] Respawn binding

### **Phase 5: Bane System (OPTIONAL)**
- [ ] Siege stone placement
- [ ] Bane window scheduling
- [ ] Tree damage mechanics
- [ ] Tree destruction consequences

### **Phase 6: Origin Chunk Promotion (TO DO)**
- [ ] Weekly ranking calculation (Sunday midnight)
- [ ] Move winning tree to Chunk -1
- [ ] Blockchain recording integration
- [ ] Champion titles and rewards
- [ ] Ban system for exploitation

---

## 📊 Updated Database Schema

### **seed_plots Table (EXPAND)**

Add columns for tree progression:

```sql
ALTER TABLE seed_plots ADD COLUMN tree_rank INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_health INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_max_health INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN upgrade_started_at DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN last_watered DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN times_watered INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN growth_bonus_accumulated FLOAT DEFAULT 0.0;
ALTER TABLE seed_plots ADD COLUMN guild_id TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN guild_name TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN warehouse_gold INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_resources JSON NULL;
```

### **seed_plot_buildings Table (NEW)**

Track buildings placed around trees:

```sql
CREATE TABLE seed_plot_buildings (
    id INTEGER PRIMARY KEY,
    seed_plot_id INTEGER NOT NULL,
    building_type TEXT NOT NULL,  -- "vendor", "warehouse", "shrine"
    position_slot TEXT NOT NULL,  -- "A" through "F"
    health INTEGER DEFAULT 1000,
    is_protected BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    -- Vendor-specific
    vendor_inventory JSON NULL,
    vendor_prices JSON NULL,

    FOREIGN KEY(seed_plot_id) REFERENCES seed_plots(id)
);
```

---

## 🎮 Gameplay Flow Examples

### **Example 1: Solo Player → Small Guild**

1. Player claims edge plot for **1000 gold**
2. Contributes resources over time, builds **contribution score**
3. Upgrades to **Rank 1 (Sapling)** - respawn point activated
4. Invites friends, forms **guild** of 3 players
5. Upgrades to **Rank 3** - places **vendor building**
6. All guild members can use respawn + vendor
7. Competes in weekly rankings for **origin chunk promotion**

### **Example 2: Large Guild Competition**

1. Guild A claims **Chunk -2** plot, reaches **Rank 7**
2. Guild B claims **Chunk 2** plot, also **Rank 7**
3. Both compete all week:
   - Guild A: 25,000 contribution points
   - Guild B: 24,800 contribution points
4. **Sunday midnight**: Guild A wins, tree moved to **Chunk -1 (West Origin)**
5. Guild A gets "**World Tree Champion**" title
6. Winner recorded on **Mantle blockchain**
7. Next week, competition resets

---

## 🎨 Visual Differences

| Tree State | Visual |
|------------|--------|
| **Unclaimed Plot** | Glowing ground circle, runes |
| **Rank 0 (Claimed)** | Small sapling, green glow |
| **Rank 1-2** | Young tree, leaves appearing |
| **Rank 3-4** | Mature tree, larger canopy |
| **Rank 5-6** | Ancient tree, golden tint |
| **Rank 7 (World Tree)** | Massive tree, bright golden glow |
| **Origin Champion** | World Tree + special particles, visible on map |

---

## ⚠️ Key Decisions Needed

1. **Should seed plots start as individual or guild-owned?**
   - **Option A**: Individual → upgrade to guild later
   - **Option B**: Guild-only from start
   - **Recommendation**: Option A (more accessible)

2. **Should all seed plots compete, or only Rank 7 trees?**
   - **Option A**: All ranks compete (score-based)
   - **Option B**: Only Rank 7 trees eligible
   - **Recommendation**: Option A (encourages participation)

3. **Should bane system be included?**
   - **Option A**: Include for PvP guilds
   - **Option B**: Exclude, keep peaceful
   - **Recommendation**: Optional toggle per server

4. **How should expansion + building work?**
   - **Option A**: Seed plots can have buildings
   - **Option B**: Buildings require separate placement
   - **Recommendation**: Option A (simpler)

---

## 📝 Next Steps

1. **User Decision**: Review merged concept, approve/modify
2. **Database Migration**: Add tree columns to seed_plots
3. **Update ChunkExpansionManager**: Add rank upgrade logic
4. **Create UI**: Claim, contribute, upgrade interfaces
5. **Test Flow**: Claim → contribute → upgrade → compete
6. **Iterate**: Add building placement, guild features
7. **Polish**: Visual upgrades, blockchain integration

---

## 📚 Related Documents

- **Old System**: `docs/WORLD_TREE_SYSTEM.md`
- **New System**: `docs/DYNAMIC_CHUNK_EXPANSION.md`, `docs/WORLD_TREE_COMPETITION.md`
- **Current Setup**: `docs/WORLD_TREE_SETUP.md`
- **API**: `docs/API_CONTRACT.md` (v1.5)
