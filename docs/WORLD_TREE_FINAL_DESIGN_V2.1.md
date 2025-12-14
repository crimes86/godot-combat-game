# World Tree System - Final Unified Design v2.1

**Status**: Design Reviewed & Fixed
**Date**: 2024-12-14
**Version**: 2.1 (With Critical Fixes - REVISED)

This document defines the complete World Tree system with all design flaws addressed and fixes integrated.

---

## 🎯 Core Principles

1. **Individual → Guild**: Players claim solo, auto-joins their guild if they have one
2. **Neutral Factions**: Unguilded players assigned to neutral factions (with 1.5x multiplier)
3. **Single Winner Competition**: All ranks compete together, ONE champion promoted weekly
4. **Universal Bane System**: ANY tree can be sieged (not just origin) - creates natural competitive tiers
5. **Champion Duplication**: Winner duplicates to origin chunk, original decays over 7 days
6. **Protected Migration**: 3-day champion protection + diminishing siege rewards
7. **Dual Ownership**: Original owner + current guild with transfer cooldowns
8. **Extended Persistence**: 90-day decay for dynamic chunks (3-month vacation buffer)

---

## 🔧 Critical Fixes Applied

### **Fix #1: Dual Ownership Model**

**Problem**: Players kicked from guild lose access to trees they paid for.

**Solution**:
```gdscript
# Permanent original owner + transferable guild association
tree.original_owner_id = player_id  // Never changes (unless manually transferred)
tree.current_guild_id = guild_id    // Can change with 7-day cooldown
tree.last_guild_change = timestamp  // Cooldown tracking

# Transfer permanent ownership
func transfer_ownership(new_owner_id: String):
    require(caller == tree.original_owner_id)
    require(new_owner_id in current_guild_members)
    tree.original_owner_id = new_owner_id
    tree.last_ownership_transfer = now()

# Change guild association (7-day cooldown)
func change_guild(new_guild_id: String):
    require(now - tree.last_guild_change > 7 * 86400)
    tree.current_guild_id = new_guild_id
    tree.last_guild_change = now()
```

**Rights**:
- **Original Owner**: Transfer ownership, change guild, delete tree, all permissions
- **Guild Members**: Building placement, warehouse deposit/withdraw, respawn binding

---

### **Fix #2: Champion Tree Duplication System**

**Problem**: Moving tree from Chunk -5 → Chunk -1 disrupts 50 active players mid-gameplay.

**Solution - Migration Flow**:

```
SUNDAY 00:00 UTC: Winner Declared
├─ Duplicate winner tree → Chunk -1 (origin)
├─ Original tree @ Chunk -5 → "decaying" state
├─ Champion benefits activate on duplicated tree
└─ 7-day migration period begins

DAYS 1-7: Migration Period
├─ Old tree: Fully functional (buildings, respawn, mines)
├─ New tree: Champion bonuses active
├─ Buildings: Copied layouts (need 50% cost activation)
├─ Warehouse: Manual transfer or 10,000g instant
├─ Respawn: Auto-migrates to new tree
├─ Players: Gradually move to new location
└─ Mines: Duplicated, need reclaiming at new location

DAY 7: Migration Complete
├─ Old tree despawns at Chunk -5
├─ Seed plot @ Chunk -5 → "unclaimed" (free for claiming)
├─ New tree fully operational @ Chunk -1
└─ All guild members at new location

NEXT WEEK: If Lose Championship
├─ Previous champion tree migrates BACK to original chunk
├─ Tree duplicated back to Chunk -5
├─ Reverse migration (7 days)
└─ New winner promoted to origin
```

**Migration Mechanics**:

| Feature | Migration Behavior |
|---------|-------------------|
| **Duration** | 7 days |
| **Building Layouts** | Copied to new tree, activate at 50% cost |
| **Warehouse Transfer** | Manual or 10,000g instant transfer |
| **Respawn Binding** | Auto-migrates day 1 |
| **Old Seed Plot** | Becomes unclaimed after despawn |
| **Previous Champion** | Migrates back to original chunk |

```gdscript
func duplicate_tree_to_origin(winner_tree_id: int):
    var original = get_seed_plot(winner_tree_id)

    # Create duplicate at origin chunk
    var duplicate = create_seed_plot(-1)  # West origin chunk
    duplicate.original_owner_id = original.original_owner_id
    duplicate.current_guild_id = original.current_guild_id
    duplicate.tree_rank = original.tree_rank
    duplicate.is_origin_champion = true
    duplicate.champion_since = now()
    duplicate.migration_expires = now() + 7 * 86400
    duplicate.original_chunk_id = original.chunk_id

    # Copy building layouts (inactive)
    for building in original.buildings:
        var copy = duplicate_building(building)
        copy.is_active = false
        copy.activation_cost = building.original_cost * 0.5
        duplicate.buildings.append(copy)

    # Mark original as decaying
    original.is_decaying = true
    original.decay_complete_at = now() + 7 * 86400

    # Auto-migrate respawn bindings
    migrate_respawn_bindings(original.id, duplicate.id)
```

---

### **Fix #3: Neutral Faction Balance**

**Problem**: 50 unguilded players ÷ 5 factions = 10 each. 20-member organized guild = 2x power. Neutral trees can't compete.

**Solution - Contribution Multiplier**:
```gdscript
const NEUTRAL_FACTION_MULTIPLIER = 1.5

func add_contribution(tree_id: int, player_id: String, contribution: Dictionary):
    var tree = get_seed_plot(tree_id)
    var base_score = calculate_contribution_score(contribution)

    # Apply multiplier for neutral faction trees
    if tree.faction.begins_with("neutral_"):
        base_score *= NEUTRAL_FACTION_MULTIPLIER

    tree.contribution_score += base_score
```

**Example**:
- 10 random players contributing 100 points each to neutral tree
- Effective score: 10 × 100 × 1.5 = **1,500 points**
- Guild with 20 organized members: 20 × 50 = **1,000 points**
- Neutral tree competitive despite coordination disadvantage

---

### **Fix #4: Single Winner + Universal Bane System**

**Problem (original misunderstanding)**: I incorrectly suggested 3-tier competition. You want natural competition where trees fight within their power level.

**Actual Solution**:

```gdscript
# SINGLE WINNER - All ranks compete together
func calculate_weekly_rankings():
    var all_trees = get_all_claimed_seed_plots()

    # Sort by total score (all ranks compete)
    all_trees.sort_custom(func(a, b):
        return _calculate_total_score(a) > _calculate_total_score(b)
    )

    # ONE winner (usually Rank 7, but early on could be Rank 3-4)
    var winner = all_trees[0]
    duplicate_tree_to_origin(winner, -1)  # Single origin position

    # Record winner on blockchain
    record_on_chain(winner)

# Bane available for ANY tree (not just origin)
func can_plant_bane_stone(tree_id: int) -> bool:
    var tree = get_seed_plot(tree_id)

    # Origin champion has 3-day protection
    if tree.is_origin_champion:
        var days_as_champion = (now() - tree.champion_since) / 86400.0
        if days_as_champion < 3:
            return false  # Protected for first 3 days

    # All other trees are ALWAYS vulnerable to bane
    return true
```

**Natural Competitive Tiers** (emergent gameplay):
- **Rank 1-2 trees**: Bane each other for wood/stone to upgrade faster
- **Rank 3-4 trees**: Fight for gold, building resources, rank advancement
- **Rank 5-6 trees**: Compete for weekly top 5 positions, raid rivals for mines
- **Rank 7 trees**: Battle for #1 spot to become champion
- **Champion tree**: Defends against entire server

**Why this works better**:
- Lower ranks aren't waiting for a "participation trophy" origin position
- They're actively fighting to climb the ladder by raiding similar-strength trees
- Rank 2 guilds don't waste time attacking Rank 7 (too hard, not worth it)
- They attack other Rank 2 trees (winnable, good loot)
- Creates organic PvP matchmaking through risk/reward

---

### **Fix #5: Champion Protection + Diminishing Siege Rewards**

**Problem**: Champion tree gets farmed by entire server = punishment for winning.

**Solution**:

```gdscript
# Protection period
const CHAMPION_PROTECTION_DAYS = 3
const BANE_DIMINISHING_RETURNS = [1.0, 0.5, 0.25, 0.1]

func can_plant_bane_stone(tree_id: int) -> bool:
    var tree = get_seed_plot(tree_id)

    # Champion protected for first 3 days
    if tree.is_origin_champion:
        if now() - tree.champion_since < 3 * 86400:
            return false

    return true

func calculate_siege_loot(tree_id: int) -> Dictionary:
    var tree = get_seed_plot(tree_id)
    var sieges_this_week = count_successful_sieges_this_week(tree_id)

    # Diminishing returns
    var multiplier = BANE_DIMINISHING_RETURNS[min(sieges_this_week, 3)]

    return {
        "gold": tree.warehouse_overflow_gold * 0.5 * multiplier,
        "wood": tree.warehouse_overflow_wood * 0.5 * multiplier,
        "stone": tree.warehouse_overflow_stone * 0.5 * multiplier,
        "gems": tree.warehouse_overflow_gems * 0.5 * multiplier
    }
```

**Timeline**:
- **Sunday-Wednesday**: Protected (build up resources, set up defenses)
- **Thursday-Sunday**: Bane available
  - 1st successful siege: 100% loot
  - 2nd siege: 50% loot
  - 3rd siege: 25% loot
  - 4th+ siege: 10% loot

**Applies to ALL trees** (not just champion):
- Champion gets 3-day immunity
- All other trees vulnerable 24/7
- Diminishing returns prevent farming any tree into oblivion

---

### **Fix #6: Warehouse Safe + Overflow**

**Problem**: 500,000 gold warehouse = 250,000 gold jackpot on siege. Too punishing.

**Solution**:

```gdscript
const WAREHOUSE_SAFE_LIMITS = {
    "gold": 50000,
    "wood": 5000,
    "stone": 5000,
    "gems": 500
}

func deposit_to_warehouse(tree_id: int, resources: Dictionary):
    var tree = get_seed_plot(tree_id)

    for resource in resources:
        var current_safe = tree.get("warehouse_safe_" + resource)
        var safe_limit = WAREHOUSE_SAFE_LIMITS[resource]

        # Fill safe storage first (protected)
        var to_safe = min(resources[resource], safe_limit - current_safe)
        tree.set("warehouse_safe_" + resource, current_safe + to_safe)

        # Excess goes to overflow (vulnerable)
        var to_overflow = resources[resource] - to_safe
        if to_overflow > 0:
            var current_overflow = tree.get("warehouse_overflow_" + resource)
            tree.set("warehouse_overflow_" + resource, current_overflow + to_overflow)

func on_siege_success(tree_id: int):
    var tree = get_seed_plot(tree_id)

    # Only overflow storage is vulnerable
    var loot = {
        "gold": tree.warehouse_overflow_gold * 0.5,
        "wood": tree.warehouse_overflow_wood * 0.5,
        "stone": tree.warehouse_overflow_stone * 0.5,
        "gems": tree.warehouse_overflow_gems * 0.5
    }

    # Safe storage is immune
    return loot
```

**Storage Display**:
```
Warehouse Storage:
├─ Safe Storage (Protected): 50,000 / 50,000 gold ✓
└─ Overflow Storage (Vulnerable): 125,000 gold ⚠️
```

**Smart Strategy**:
- Keep critical funds in safe storage
- Overflow is "acceptable loss" funds
- Spend overflow quickly on upgrades
- Don't hoard 500k gold (invites attacks)

---

### **Fix #7: Resource Mine Active Collection**

**Problem**: 5 mines × 500g/hour = 60,000 gold/day passive AFK farming. Economy collapse.

**Solution**:

```gdscript
const MINE_COLLECTION_COOLDOWN = 1800  # 30 minutes
const DIMINISHING_RETURN_FACTOR = 0.8
const MAX_STORED_HOURS = 4

func collect_mine(tree_id: int, mine_id: int, player_id: String) -> int:
    var mine = get_mine(mine_id)

    # Calculate time since last collection
    var hours_since_last = (now() - mine.last_collected) / 3600.0
    var hours_accumulated = min(hours_since_last, MAX_STORED_HOURS)
    var gold_accumulated = hours_accumulated * 500

    # Check if collected too quickly (diminishing returns)
    var time_since_last = now() - mine.last_collected
    if time_since_last < MINE_COLLECTION_COOLDOWN:
        gold_accumulated *= pow(DIMINISHING_RETURN_FACTOR, mine.quick_collect_count)
        mine.quick_collect_count += 1
    else:
        # Reset penalty if waited 30+ minutes
        mine.quick_collect_count = 0

    # Require player interaction
    mine.last_collected = now()
    mine.last_collector = player_id

    return int(gold_accumulated)
```

**Example**:
- Collect immediately: 500 gold (100%)
- Collect again immediately: 400 gold (80%)
- Collect 3rd time: 320 gold (64%)
- Wait 30 minutes: Reset to 100%

**Effective Daily Income**:
- AFK farming (immediate collection): ~20,000 gold/day
- Active management (30-min intervals): ~35,000 gold/day
- Maximum theoretical (4h intervals): ~60,000 gold/day

---

### **Fix #8: Logarithmic Claim Cost**

**Problem**: Chunk ±10 = 1,048,576 gold. Impossible. Expansion stops at Chunk ±8.

**Solution**:

```gdscript
func calculate_claim_cost(chunk_id: int) -> int:
    var distance = abs(chunk_id)

    # Origin chunks: 1000 gold
    if distance <= 1:
        return 1000

    # Exponential for close chunks (2-3)
    if distance <= 3:
        return 1000 * pow(2, distance - 1)  # 2k, 4k, 8k

    # Logarithmic scaling for distant chunks
    var base_cost = 8000
    var additional = (distance - 3) * 5000
    return base_cost + additional
```

**Cost Progression**:
| Chunk | Cost | Notes |
|-------|------|-------|
| ±1 | 1,000g | Origin |
| ±2 | 2,000g | Early expansion |
| ±3 | 4,000g | |
| ±4 | 13,000g | Logarithmic starts |
| ±5 | 18,000g | |
| ±10 | 43,000g | Achievable for guilds |
| ±20 | 93,000g | Long-term goal |

---

### **Fix #9: Seasonal Leaderboard**

**Problem**: Weekly reset frustrating for players who contributed all week.

**Solution**:

```gdscript
# Dual leaderboard system
func update_rankings():
    # Weekly (competitive, resets Sunday)
    calculate_weekly_rankings()

    # All-time (persistent, never resets)
    calculate_seasonal_rankings()

# Seasonal achievements
const SEASONAL_MILESTONES = {
    10000: "Seedling Tender",
    50000: "Grove Guardian",
    100000: "Forest Warden",
    500000: "World Tree Keeper",
    1000000: "Eternal Champion"
}
```

**Display**:
```
Weekly Rankings (Resets Sunday):
1. Guild A - 25,000 points
2. Guild B - 24,800 points

Seasonal Rankings (All-Time):
1. Guild C - 450,000 total contribution
2. Guild A - 380,000 total contribution
```

---

### **Fix #10: Guild-Scheduled Bane Window**

**Problem**: 2-hour window out of 120 hours = 1.67% chance defenders are online.

**Solution**:

```gdscript
func plant_bane_stone(tree_id: int, attacker_guild_id: String) -> Dictionary:
    var tree = get_seed_plot(tree_id)

    # 5-day countdown
    var planted_at = now()

    # Defending guild chooses their preferred 2-hour window
    var defender_timezone_offset = tree.defense_window_timezone_offset
    var defender_preferred_hour = tree.defense_window_hour  # 20 = 8pm

    # Calculate window start (5 days from now, at defender's preferred time)
    var window_start = planted_at + (5 * 86400)
    window_start = align_to_hour(window_start, defender_preferred_hour, defender_timezone_offset)

    var bane_stone = {
        "id": generate_id(),
        "target_tree_id": tree_id,
        "attacker_guild_id": attacker_guild_id,
        "planted_at": planted_at,
        "window_start": window_start,
        "window_end": window_start + 7200,  # 2 hours
        "health": 50000
    }

    # Notify both sides
    notify_guild(tree.current_guild_id, "Bane declared! Defense window: %s" % format_time(window_start))
    notify_guild(attacker_guild_id, "Bane stone planted! Siege window: %s" % format_time(window_start))

    return bane_stone
```

**Guild Settings**:
```
Defense Window Configuration:
├─ Preferred Hour: 20:00 (8pm)
├─ Timezone: UTC-5 (EST)
└─ Bane windows will align to this time
```

---

### **Fix #11: Rebalanced Contribution Scoring**

**Problem**: 1000 kills = 2,000 points. Depositing 2,000 gold = 2,000 points. Kills are harder.

**Solution**:

```gdscript
const CONTRIBUTION_WEIGHTS = {
    "gold": 1,        # 1 point per gold
    "wood": 3,        # 3 points per wood (was 5)
    "stone": 3,       # 3 points per stone (was 5)
    "gems": 25,       # 25 points per gem (was 50)
    "kills": 5,       # 5 points per kill (was 2)
    "boss_kills": 50, # 50 points per boss
    "time_hours": 2   # 2 points per hour (was 1)
}

func calculate_contribution_score(contribution: Dictionary) -> int:
    var score = 0

    score += contribution.get("gold", 0) * CONTRIBUTION_WEIGHTS.gold
    score += contribution.get("wood", 0) * CONTRIBUTION_WEIGHTS.wood
    score += contribution.get("stone", 0) * CONTRIBUTION_WEIGHTS.stone
    score += contribution.get("gems", 0) * CONTRIBUTION_WEIGHTS.gems
    score += contribution.get("kills", 0) * CONTRIBUTION_WEIGHTS.kills
    score += contribution.get("boss_kills", 0) * CONTRIBUTION_WEIGHTS.boss_kills
    score += (contribution.get("time_minutes", 0) / 60.0) * CONTRIBUTION_WEIGHTS.time_hours

    return int(score)
```

**Comparison**:
- 1000 kills: **5,000 points** (was 2,000)
- 2000 gold: **2,000 points** (unchanged)
- 10 boss kills: **500 points** (new)
- 5 hours active: **10 points** (was 5)

---

### **Fix #12: Extended Decay for Dynamic Chunks**

**Problem**: 7 days = lose tree on vacation. Too harsh.

**Solution - Two Decay Rules**:

```gdscript
const ORIGIN_CHAMPION_DECAY_DAYS = 14  # Prestige position has responsibility
const DYNAMIC_CHUNK_DECAY_DAYS = 90    # 3 months for regular trees

func check_decay(tree_id: int):
    var tree = get_seed_plot(tree_id)
    var days_inactive = (now() - tree.last_contribution) / 86400.0

    # Origin champion: Shorter decay (prestige = responsibility)
    var decay_threshold = DYNAMIC_CHUNK_DECAY_DAYS
    if tree.is_origin_champion:
        decay_threshold = ORIGIN_CHAMPION_DECAY_DAYS

    if days_inactive >= decay_threshold:
        despawn_tree(tree_id)
        notify_owner(tree.original_owner_id, "Your tree has despawned after %d days of inactivity" % decay_threshold)
    elif days_inactive >= decay_threshold - 7:
        # 7-day warning
        notify_owner(tree.original_owner_id, "Your tree will despawn in 7 days without activity")
```

**Decay Timeline**:

| Tree Type | Warning | Despawn | Reasoning |
|-----------|---------|---------|-----------|
| **Dynamic Chunk Tree** | 83 days | 90 days | 3-month vacation buffer |
| **Origin Champion** | 7 days | 14 days | Prestige requires active defense |

**During 90-Day Vacation**:
- ✅ Tree persists (rank, buildings intact)
- ⚠️ Can be baned/sieged by rivals (that's the game)
- ⚠️ Warehouse overflow might be raided
- ✅ Safe storage protected (50k gold, 5k resources)
- ✅ Come back to exciting "revenge" story, not "start over"

**Key Philosophy**:
- Loss from siege = acceptable risk (exciting comeback potential)
- Total despawn = catastrophic (discouraging)
- 90 days = generous vacation buffer
- Origin champion = shorter decay (can't AFK squat prestige position)

---

## 🌍 Server Capacity & Launch Structure

### **Server Resources Per Seed Plot**

**Database Overhead**:
```
- seed_plots row: ~2KB (with JSON columns)
- seed_plot_buildings: ~1KB per building (avg 6 = 6KB)
- world_tree_contributions: ~500 bytes per contributor per week
- bane_stones: ~1KB per active siege

Total per tree: ~10KB
100 trees: 1MB
1000 trees: 10MB (negligible)
```

**Backend API Load**:
```
Per tree per minute:
- Contribution tracking: 1-10 requests/min
- Building interactions: 0-5 requests/min
- Watering: 1 request/day
- Rankings query: 1 request/min (live leaderboard)

100 active trees = ~1,500 req/min = 25 req/sec (very manageable)
```

**Godot Client Load**:
```
Active chunks loaded: 3-5 chunks per player
Players visiting trees: 10-50 concurrent
Chunk streaming: Non-issue (trees are static entities)
```

### **Recommended Launch Configuration**

**Option A: Small Launch (100-500 players)**
```
Origin chunks: -1, 0, 1 (3 plots)
Initial dynamic chunks: ±2, ±3 (4 plots)
Total seed plots: 7

As both edges claimed → expand to ±4, ±5
Max during first month: ~15 seed plots
```

**Option B: Medium Launch (500-2000 players) - RECOMMENDED**
```
Origin chunks: -1, 0, 1 (3 plots)
Pre-expanded: ±2 through ±5 (8 plots)
Total seed plots: 11

Allows immediate land rush
Natural expansion to ±6, ±7 as competition heats up
Enough for 5-10 guilds + solo/neutral players
```

**Option C: Large Launch (2000+ players)**
```
Origin chunks: -1, 0, 1 (3 plots)
Pre-expanded: ±2 through ±10 (16 plots)
Total seed plots: 19

Big guilds can claim distant chunks
High claim costs prevent oversaturation
```

### **Database Recommendations**

| Player Count | Database | Caching | Notes |
|--------------|----------|---------|-------|
| **<50 trees** | SQLite | None | Simple, single-server |
| **50-200 trees** | PostgreSQL | None | Better concurrency |
| **200+ trees** | PostgreSQL | Redis | Cache live rankings |

### **Scaling Path**

```
Launch: 11 seed plots (Chunks -5 to +5)
    ↓
Month 1-3: Natural expansion to ±8 (19 plots)
    ↓
Month 6: Active plots reach ±12 (27 plots)
    ↓
Year 1: Server supports 50+ active trees
    ↓
Mature server: 100+ trees across ±20 chunks
```

**Why 11 starting plots is optimal**:
- Enough for competitive land rush
- Low enough to feel valuable
- High enough to avoid bottleneck
- Scales infinitely as population grows
- 3 origin + 8 dynamic = good balance

---

## 📋 Updated Seed Plot Lifecycle

### **Stage 1: Unclaimed Plot**

```
STATE: unclaimed
LOCATION: Edge chunks (launch: -5 to +5)
VISUAL: Glowing ground circle with runes
INTERACTION: [F] Claim (cost: logarithmic)
```

**Claim Cost Formula** (UPDATED):
```gdscript
func calculate_claim_cost(chunk_id: int) -> int:
    var distance = abs(chunk_id)
    if distance <= 1:
        return 1000
    if distance <= 3:
        return 1000 * pow(2, distance - 1)
    return 8000 + (distance - 3) * 5000
```

---

### **Stage 2: Claimed Plot (Rank 0)**

```
STATE: claimed
RANK: 0 (Seedling)
OWNER: original_owner_id (permanent) + current_guild_id (7-day cooldown)
FACTION: Auto-assigned based on player status
VISUAL: Small green sprout, subtle glow
BANE: Vulnerable 24/7 (no protection for Rank 0)
```

**Ownership Assignment** (UPDATED):
```gdscript
func claim_seed_plot(player_id: String):
    var plot = seed_plots[chunk_id]

    # Permanent ownership
    plot.original_owner_id = player_id
    plot.last_ownership_transfer = now()
    plot.last_contribution = now()  # Reset decay timer

    # Guild association (7-day cooldown)
    if GroupManager.has_group():
        plot.current_guild_id = GroupManager.get_guild_id()
        plot.guild_name = GroupManager.get_guild_name()
        plot.faction = "guild"
        plot.last_guild_change = now()
    else:
        # Assign neutral faction
        plot.current_guild_id = _assign_neutral_faction(player_id)
        plot.guild_name = _get_neutral_faction_name(plot.current_guild_id)
        plot.faction = "neutral"
```

**Neutral Factions** (for unguilded players):
- `neutral_wanderers` - "The Wanderers"
- `neutral_freefolk` - "The Free Folk"
- `neutral_exiles` - "The Exiles"
- `neutral_nomads` - "The Nomads"
- `neutral_seekers` - "The Seekers"

---

### **Stage 3: Rank 1-7 (Guild Tree)**

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

## 🏆 Weekly Competition (UPDATED - Single Winner)

**Schedule**: Every Sunday 00:00 UTC

**Eligibility**: ALL ranks (0-7) compete together

**Single Winner**:
- ONE origin position (Chunk -1)
- Rank 7 trees will usually win
- Early weeks: Rank 3-4 trees might win
- Creates aspirational goal for all players

**Scoring Formula** (UPDATED):
```gdscript
contribution_score = (
    gold_contributed * 1 +
    wood_contributed * 3 +      # Was 5
    stone_contributed * 3 +     # Was 5
    gems_contributed * 25 +     # Was 50
    kills * 5 +                 # Was 2
    boss_kills * 50 +           # NEW
    (time_minutes / 60) * 2     # Was 1
)

# Apply neutral faction multiplier
if tree.faction.begins_with("neutral_"):
    contribution_score *= 1.5

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

    # Sort by total score (all ranks compete)
    all_trees.sort_custom(func(a, b):
        return _calculate_total_score(a) > _calculate_total_score(b)
    )

    # ONE winner
    var winner = all_trees[0]

    # Duplicate to origin chunk
    duplicate_tree_to_origin(winner, -1)

    # Record on blockchain
    record_on_chain(winner)

    # Update seasonal leaderboard
    update_seasonal_rankings(all_trees)

    # Reset weekly contributions
    reset_weekly_scores()
```

### **Origin Chunk Promotion**

```
WINNER TREE:
- Duplicated to Chunk -1 (West Origin)
- Status: "World Tree Champion"
- Visual: Special golden particles + crown
- Map icon: Crown symbol
- Benefits: Server-wide prestige, champion bonuses
- Protection: 3 days immunity, then vulnerable

PREVIOUS CHAMPION:
- Duplicated back to original chunk
- Retains rank/buildings
- Loses champion status
- 7-day migration period
```

---

## ⚔️ Bane System (UPDATED - Universal)

**Target**: ANY tree (not just origin champion)

**Objective**: Guild vs Guild warfare for resources and advancement

### **Bane Availability**

```gdscript
func can_plant_bane_stone(tree_id: int) -> bool:
    var tree = get_seed_plot(tree_id)

    # Origin champion has 3-day protection
    if tree.is_origin_champion:
        var days_as_champion = (now() - tree.champion_since) / 86400.0
        if days_as_champion < CHAMPION_PROTECTION_DAYS:
            return false  # Protected Sun-Wed

    # All other trees are ALWAYS vulnerable
    return true
```

**Natural Competitive Tiers**:
- **Rank 1-2**: Attack similar rank trees for wood/stone
- **Rank 3-4**: Fight for gold and building resources
- **Rank 5-6**: Raid for mine resources, competitive positioning
- **Rank 7**: Battle for #1 weekly spot
- **Champion**: Defend against server-wide attacks

**Why Universal Bane Works**:
- Rank 2 guilds won't attack Rank 7 (too hard, waste of 50k gold)
- They attack other Rank 2 trees (winnable, good loot)
- Creates organic matchmaking through risk/reward
- Accelerates progression through raiding

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
- Scheduled at defender's preferred time
- Tree becomes vulnerable
- Runekeeper protection disabled
- Buildings can be damaged
- PvP enabled in area

STEP 4: OUTCOME
├─ DEFENDERS WIN (tree survives)
│  └─ Bane stone destroyed, attackers lose 50k gold
│
└─ ATTACKERS WIN (tree destroyed)
   ├─ Tree downgraded 2 ranks
   ├─ 50% of buildings destroyed (random)
   ├─ Warehouse overflow loot drops (public)
   └─ Tree remains at location (not despawned)
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
    # Calculate loot with diminishing returns
    var sieges_this_week = count_successful_sieges_this_week(tree_id)
    var multiplier = BANE_DIMINISHING_RETURNS[min(sieges_this_week, 3)]

    # Drop warehouse overflow contents only
    var loot = {
        "gold": tree.warehouse_overflow_gold * 0.5 * multiplier,
        "wood": tree.warehouse_overflow_wood * 0.5 * multiplier,
        "stone": tree.warehouse_overflow_stone * 0.5 * multiplier,
        "gems": tree.warehouse_overflow_gems * 0.5 * multiplier
    }

    # Safe storage is PROTECTED
    # tree.warehouse_safe_gold remains untouched

    # Create public loot chest
    create_loot_chest(tree.position, loot)

    # Participants get bonus
    distribute_siege_rewards(attackers, defenders)
```

**Siege Rewards** (all participants):
- Attackers (if win): Overflow loot + bonus XP
- Defenders (if win): Bonus gold from treasury + XP
- All participants: Special "Siege Veteran" achievement

### **Diminishing Returns** (Prevents Farming)

| Siege # | Loot Multiplier | Example (100k overflow gold) |
|---------|-----------------|------------------------------|
| 1st | 100% | 50,000 gold |
| 2nd | 50% | 25,000 gold |
| 3rd | 25% | 12,500 gold |
| 4th+ | 10% | 5,000 gold |

**Resets**: Weekly (Sunday midnight)

---

## 💧 Watering System (Unchanged)

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
```

**Purified Water Sources**:
- Craft at cleansed lava pools
- Rare drop from water-based enemies
- Purchasable at high-level vendors

---

## 🏗️ Building System

**Unlocks**: Rank 1+ (limited by rank)

### **Building Types**

| Type | Min Rank | Function | Maintenance Cost/Week | Activation Cost (Migration) |
|------|----------|----------|----------------------|----------------------------|
| **Vendor (Weapons)** | 3 | Sell weapons | 200g | 50% of original |
| **Vendor (Armor)** | 3 | Sell armor | 200g | 50% of original |
| **Vendor (Consumables)** | 3 | Sell potions/food | 200g | 50% of original |
| **Warehouse** | 5 | Shared storage | 500g | 50% of original |
| **Shrine (Warfare)** | 4 | +10% damage buff | 500g | 50% of original |
| **Shrine (Vitality)** | 4 | +20% HP buff | 500g | 50% of original |
| **Shrine (Fortune)** | 4 | +15% gold/loot | 500g | 50% of original |
| **Crafting Station** | 4 | Upgrade equipment | 300g | 50% of original |

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
- Bane sieges: 50% of buildings destroyed randomly

---

## 🛡️ Respawn Binding (Unchanged)

**Unlocks**: Rank 1+

### **Neutral Trees (Faction-Based)**
- Open to all players
- Death → Respawn at tree

### **Guild Trees (Private/Public Toggle)**
- Controlled by guild leader
- Toggle: "Allow Non-Members to Bind"
- Default: Guild members only

```gdscript
func can_bind_to_tree(player_id: String, tree: SeedPlot) -> bool:
    # Guild member check
    if tree.current_guild_id == player.get_guild_id():
        return true

    # Public binding enabled?
    if tree.allow_public_binding:
        return true

    # Neutral faction trees are always public
    if tree.faction.begins_with("neutral_"):
        return true

    return false
```

---

## 💰 Resource Mines (UPDATED)

**Unlocks**: Rank 5+

**Mechanic**:
- Trees can claim resource mines in their chunk
- Mines generate passive income (with active collection)
- Limit based on rank (3-5 mines)

**Mine Types**:
- **Gold Mine**: 500g/hour (max 2000g stored)
- **Stone Quarry**: 100 stone/hour
- **Lumber Mill**: 100 wood/hour
- **Gem Vein**: 5 gems/hour (rare)

### **Active Collection Requirement** (NEW)

```gdscript
const MINE_COLLECTION_COOLDOWN = 1800  # 30 minutes
const DIMINISHING_RETURN_FACTOR = 0.8
const MAX_STORED_HOURS = 4

func collect_mine(tree_id: int, mine_id: int, player_id: String) -> int:
    var mine = get_mine(mine_id)

    # Calculate accumulated resources
    var hours_since_last = (now() - mine.last_collected) / 3600.0
    var hours_accumulated = min(hours_since_last, MAX_STORED_HOURS)
    var gold_accumulated = hours_accumulated * 500

    # Apply diminishing returns if collected too quickly
    var time_since_last = now() - mine.last_collected
    if time_since_last < MINE_COLLECTION_COOLDOWN:
        gold_accumulated *= pow(DIMINISHING_RETURN_FACTOR, mine.quick_collect_count)
        mine.quick_collect_count += 1
    else:
        mine.quick_collect_count = 0

    # Require active player interaction
    mine.last_collected = now()
    mine.last_collector = player_id

    return int(gold_accumulated)
```

**Collection Strategy**:
- Optimal: Collect every 30+ minutes for 100% yield
- Max storage: 4 hours worth (2,000 gold per mine)
- Spam collection: Diminishing returns (100% → 80% → 64% → ...)

**Effective Daily Income** (5 mines):
- AFK spam: ~20,000 gold/day
- Active management: ~35,000 gold/day
- Optimal (4h intervals): ~60,000 gold/day

---

## 🗄️ Warehouse System (UPDATED)

**Unlocks**: Rank 5+

### **Safe + Overflow Storage** (NEW)

```gdscript
const WAREHOUSE_SAFE_LIMITS = {
    "gold": 50000,
    "wood": 5000,
    "stone": 5000,
    "gems": 500
}

# Two storage pools
tree.warehouse_safe_gold      // Protected from sieges
tree.warehouse_overflow_gold  // Vulnerable to sieges (50% loss)
```

**Deposit Logic**:
```gdscript
func deposit_to_warehouse(tree_id: int, resource_type: String, amount: int):
    var tree = get_seed_plot(tree_id)
    var safe_limit = WAREHOUSE_SAFE_LIMITS[resource_type]
    var current_safe = tree.get("warehouse_safe_" + resource_type)

    # Fill safe storage first (protected)
    var to_safe = min(amount, safe_limit - current_safe)
    tree.set("warehouse_safe_" + resource_type, current_safe + to_safe)

    # Excess goes to overflow (vulnerable)
    var to_overflow = amount - to_safe
    if to_overflow > 0:
        var current_overflow = tree.get("warehouse_overflow_" + resource_type)
        tree.set("warehouse_overflow_" + resource_type, current_overflow + to_overflow)
```

**Siege Vulnerability**:
- **Safe storage**: Immune to Bane (protected)
- **Overflow storage**: 50% lost on successful siege

**UI Display**:
```
Warehouse Inventory:
├─ Safe Storage (Protected)
│  ├─ Gold: 50,000 / 50,000 ✓
│  ├─ Wood: 5,000 / 5,000 ✓
│  ├─ Stone: 4,200 / 5,000
│  └─ Gems: 500 / 500 ✓
└─ Overflow Storage (Vulnerable ⚠️)
   ├─ Gold: 85,000
   ├─ Wood: 12,000
   └─ Stone: 8,500
```

**Smart Strategy**:
- Keep critical funds in safe storage
- Use overflow as "working capital" (spend quickly)
- Don't hoard 500k gold (invites sieges)
- Distribute wealth across guild members

---

## 📊 Database Schema Updates

### **seed_plots Table (Complete with All Fixes)**

```sql
-- Core ownership (Fix #1)
ALTER TABLE seed_plots ADD COLUMN original_owner_id TEXT NOT NULL;
ALTER TABLE seed_plots ADD COLUMN last_ownership_transfer DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN current_guild_id TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN last_guild_change DATETIME NULL;

-- Migration/Champion (Fix #2)
ALTER TABLE seed_plots ADD COLUMN is_origin_champion BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN champion_since DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN is_decaying BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN decay_complete_at DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN migration_expires DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN original_chunk_id INTEGER NULL;

-- Decay (Fix #12 - Extended)
ALTER TABLE seed_plots ADD COLUMN last_contribution DATETIME DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE seed_plots ADD COLUMN decay_warning_sent BOOLEAN DEFAULT 0;

-- Warehouse (Fix #6 - Safe + Overflow)
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_gold INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_wood INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_stone INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_safe_gems INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_gold INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_wood INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_stone INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN warehouse_overflow_gems INTEGER DEFAULT 0;

-- Bane defense (Fix #10)
ALTER TABLE seed_plots ADD COLUMN defense_window_hour INTEGER DEFAULT 20;
ALTER TABLE seed_plots ADD COLUMN defense_window_timezone_offset INTEGER DEFAULT 0;

-- Existing columns (from v2.0)
ALTER TABLE seed_plots ADD COLUMN tree_rank INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_health INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN tree_max_health INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN guild_name TEXT NULL;
ALTER TABLE seed_plots ADD COLUMN faction TEXT DEFAULT 'individual';
ALTER TABLE seed_plots ADD COLUMN upgrade_started_at DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN upgrade_target_rank INTEGER NULL;
ALTER TABLE seed_plots ADD COLUMN last_watered DATETIME NULL;
ALTER TABLE seed_plots ADD COLUMN times_watered INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN growth_bonus_accumulated FLOAT DEFAULT 0.0;
ALTER TABLE seed_plots ADD COLUMN allow_public_binding BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN claimed_mine_ids JSON NULL;
```

---

### **resource_mines Table (NEW - Fix #7)**

```sql
CREATE TABLE resource_mines (
    id INTEGER PRIMARY KEY,
    chunk_id INTEGER NOT NULL,
    mine_type TEXT NOT NULL,  -- "gold", "stone", "wood", "gems"
    position_x FLOAT NOT NULL,
    position_y FLOAT NOT NULL,

    -- Ownership
    owner_tree_id INTEGER NULL,

    -- Collection tracking (Fix #7)
    last_collected DATETIME NULL,
    last_collector TEXT NULL,
    quick_collect_count INTEGER DEFAULT 0,

    -- Accumulated resources
    resources_accumulated INTEGER DEFAULT 0,

    FOREIGN KEY(owner_tree_id) REFERENCES seed_plots(id)
);
```

---

### **seed_plot_buildings Table**

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

    -- Migration (Fix #2)
    is_active BOOLEAN DEFAULT 1,
    activation_cost INTEGER DEFAULT 0,
    original_cost INTEGER NOT NULL,

    -- Timestamps
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    destroyed_at DATETIME NULL,
    activated_at DATETIME NULL,

    -- Vendor data
    vendor_inventory JSON NULL,
    vendor_prices JSON NULL,
    total_sales INTEGER DEFAULT 0,

    -- Shrine data
    shrine_buff_type TEXT NULL,

    FOREIGN KEY(seed_plot_id) REFERENCES seed_plots(id)
);
```

---

### **bane_stones Table (Extended - Fix #5, #10)**

```sql
CREATE TABLE bane_stones (
    id INTEGER PRIMARY KEY,
    target_tree_id INTEGER NOT NULL,
    attacker_guild_id TEXT NOT NULL,

    -- Health
    health INTEGER DEFAULT 50000,
    max_health INTEGER DEFAULT 50000,

    -- Timeline (Fix #10 - Scheduled windows)
    planted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    window_start DATETIME NULL,
    window_end DATETIME NULL,

    -- Status
    is_active BOOLEAN DEFAULT 0,
    outcome TEXT NULL,

    -- Tracking (Fix #5 - Diminishing returns)
    sieges_this_week INTEGER DEFAULT 0,

    FOREIGN KEY(target_tree_id) REFERENCES seed_plots(id)
);
```

---

### **seasonal_rankings Table (NEW - Fix #9)**

```sql
CREATE TABLE seasonal_rankings (
    id INTEGER PRIMARY KEY,
    tree_id INTEGER NOT NULL,
    guild_id TEXT NOT NULL,

    -- All-time stats
    total_contribution INTEGER DEFAULT 0,
    total_kills INTEGER DEFAULT 0,
    total_waterings INTEGER DEFAULT 0,
    weeks_participated INTEGER DEFAULT 0,
    weeks_won INTEGER DEFAULT 0,

    -- Milestones
    highest_rank_achieved INTEGER DEFAULT 0,
    first_contribution DATETIME NULL,

    FOREIGN KEY(tree_id) REFERENCES seed_plots(id)
);
```

---

## 🎨 Visual Progression

| Rank | Visual Description | Bane Vulnerability |
|------|-------------------|-------------------|
| **0: Seedling** | Tiny green sprout, faint glow | Always vulnerable |
| **1: Sapling** | Small tree trunk, sparse leaves, green glow | Always vulnerable |
| **2: Young Tree** | Growing trunk, more leaves, brighter glow | Always vulnerable |
| **3: Growing Tree** | Thick trunk, full canopy, particles | Always vulnerable |
| **4: Mature Tree** | Large canopy, golden tint starting | Always vulnerable |
| **5: Ancient Tree** | Massive canopy, golden glow, many particles | Always vulnerable |
| **6: Elder Tree** | Huge tree, bright golden glow, magical aura | Always vulnerable |
| **7: World Tree** | Enormous tree, radiant gold, visible from distance | Always vulnerable |
| **Champion** | World Tree + crown particles + map icon | 3-day protection |

---

## 📅 Updated Weekly Timeline

```
SUNDAY 00:00 UTC: Rankings & Promotion
├─ Calculate rankings (ALL ranks compete)
├─ ONE winner duplicated to origin chunk (-1)
├─ Previous champion migrates back to original chunk
├─ Original trees enter 7-day decay
├─ Protection period begins (champion only, 3 days)
├─ Reset weekly contributions
└─ Update seasonal leaderboard

SUNDAY-WEDNESDAY: Champion Protected Period
├─ Champion immune to Bane (3 days)
├─ All other trees vulnerable 24/7
├─ Migration period active (7 days)
├─ Guild sets up buildings at new location
├─ Players migrate respawn bindings
└─ Warehouse transfer available (10k gold instant)

THURSDAY: Champion Bane Opens
├─ Champion vulnerable to siege
├─ Attackers can plant Bane stones
└─ Defense windows scheduled (guild preference)

THURSDAY-SATURDAY: Siege Period
├─ Bane countdowns active (all trees)
├─ Siege windows trigger
├─ Diminishing returns per siege
├─ Final push for next week's ranking
└─ Lower-rank trees raid each other for resources

NEXT SUNDAY: Migration Complete
├─ Old champion tree despawns (if lost)
├─ Previous champion migration completes
├─ Cycle repeats
└─ New rankings calculated
```

---

## 🎯 Updated Player Progression Path

### **Solo Player (Unguilded)**

```
Day 1: Claim edge plot (4000g for Chunk -3)
  └─ Assigned to "The Wanderers" (neutral faction)
  └─ Contributions get 1.5x multiplier

Week 1: Contribute wood/stone, water daily
  └─ Result: Rank 12/20 in overall rankings
  └─ Neutral multiplier keeps solo competitive

Month 1: Upgrade to Rank 3, weekly ranking improving
  └─ Find similar-rank tree to bane (Rank 2-3)
  └─ Successful siege: 15k gold loot

Month 2: Join guild, tree transfers with 7-day cooldown
  └─ Guild reaches Rank 5, claims gold mine
  └─ Defend against Rank 4 guild (successful)

Month 4: Guild wins weekly competition (Rank 6 tree)
  └─ Tree duplicated to Chunk -1 (origin)
  └─ 7-day migration period
  └─ Activate key buildings (50% cost)
  └─ Protected for 3 days (Sun-Wed)

Month 5: First champion defense (Thursday)
  └─ Scheduled defense window (8pm guild timezone)
  └─ Successfully defend, overflow loot protected by diminishing returns
  └─ Continue as champion for 2nd week

Month 6: Lose championship to Rank 7 tree
  └─ Migrate back to Chunk -3
  └─ Retain Rank 6 + all buildings
  └─ Back to competing for top spot
```

### **Guild Player (Competitive)**

```
Day 1: Guild leader claims plot (18000g for chunk -5)
  └─ Tree assigned to guild immediately
  └─ 20 members focus contributions

Week 1: Guild coordination
  └─ Members contribute 100k+ resources
  └─ Result: Rank 3/20 (behind two Rank 4 trees)
  └─ Scout nearby Rank 2 tree for bane

Week 2: First bane attack (offensive)
  └─ Plant bane stone on Rank 2 tree (50k gold)
  └─ Win siege: 25k gold + resources looted
  └─ Use loot to upgrade to Rank 3

Month 1: Reach Rank 4, place shrine buildings
  └─ Defend against rival Rank 3 guild (successful)
  └─ Safe warehouse storage protects core funds

Month 2: Claim resource mines, warehouse operational
  └─ 5 mines generating ~35k gold/day with active collection
  └─ Rank 5 achieved

Month 3: WIN WEEKLY → Promoted to origin chunk!
  └─ Champion status, blockchain recorded
  └─ Protected Sun-Wed, vulnerable Thu-Sun

Month 4: DEFEND MULTIPLE BANES
  └─ 1st siege: Successfully defend (100% loot on line)
  └─ 2nd siege attempt: Win again (50% loot due to diminishing returns)
  └─ Diminishing returns prevent total wipe

Month 5: LOSE WEEKLY → New Rank 7 guild wins
  └─ Migrate back to Chunk -5
  └─ Retain Rank 5, all buildings
  └─ Push to Rank 7 for next championship run
```

---

## 🚀 Implementation Priority (Updated with Fixes)

### **Phase 1: Core Claiming (DONE)**
- ✅ Database tables
- ✅ Backend API
- ✅ ChunkExpansionManager
- ✅ Contribution tracking

### **Phase 2: Critical Fixes Implementation**
- [ ] Database migration (dual ownership, warehouse safe/overflow, decay columns)
- [ ] Update claim cost to logarithmic formula
- [ ] Implement neutral faction 1.5x multiplier
- [ ] Single winner competition (all ranks together)
- [ ] Universal Bane system (any tree can be targeted)

### **Phase 3: Migration System**
- [ ] Tree duplication logic
- [ ] 7-day decay system
- [ ] Building activation at 50% cost
- [ ] Warehouse instant transfer (10k gold)
- [ ] Respawn auto-migration
- [ ] Previous champion reverse migration

### **Phase 4: Resource Mines**
- [ ] Mine claiming system
- [ ] Active collection requirement
- [ ] Diminishing returns for quick collection
- [ ] 30-minute cooldown tracking
- [ ] Max 4-hour accumulation cap

### **Phase 5: Warehouse Safe System**
- [ ] Dual storage pools (safe + overflow)
- [ ] Safe storage limits (50k gold, 5k resources)
- [ ] Siege only affects overflow
- [ ] UI showing protected vs vulnerable storage

### **Phase 6: Bane Improvements**
- [ ] Universal Bane (any tree targetable)
- [ ] Guild-scheduled defense windows
- [ ] Diminishing siege rewards (100%, 50%, 25%, 10%)
- [ ] Champion 3-day protection
- [ ] Weekly siege counter
- [ ] Timezone-aware window calculation

### **Phase 7: Leaderboards**
- [ ] Seasonal (all-time) leaderboard
- [ ] Weekly leaderboard (resets)
- [ ] Milestone achievements
- [ ] Contribution type breakdown

### **Phase 8: Decay System**
- [ ] 90-day decay for dynamic chunks
- [ ] 14-day decay for origin champion
- [ ] Warning notifications (7 days before)
- [ ] Gradual despawn

---

## 📝 Summary of Fixes

| Issue | Severity | Fix Applied |
|-------|----------|-------------|
| **#1: Guild Ownership** | Critical | Dual ownership (original + guild) with 7-day cooldown |
| **#2: Teleportation** | Critical | Tree duplication with 7-day migration |
| **#3: Neutral Factions** | Critical | 1.5x contribution multiplier |
| **#4: Competition** | Critical | Single winner (all ranks compete) + Universal Bane |
| **#5: Winner's Curse** | Severe | 3-day protection + diminishing siege rewards |
| **#6: Warehouse Piñata** | Severe | Safe storage (protected) + overflow (vulnerable) |
| **#7: Mine Hyperinflation** | Severe | Active collection + 30-min cooldown + diminishing returns |
| **#8: Claim Cost** | Severe | Logarithmic scaling (exponential → linear) |
| **#9: Weekly Reset** | Moderate | Seasonal leaderboard (all-time tracking) |
| **#10: Bane Defense** | Moderate | Guild-scheduled defense windows |
| **#11: Contribution** | Moderate | Rebalanced weights (kills 5pts, boss 50pts) |
| **#12: Decay Timer** | Moderate | 90 days for dynamic, 14 days for champion |

---

## 🌍 Launch Configuration (Recommended)

```
Starting Seed Plots: 11
Chunk Range: -5 to +5
├─ Origin chunks: -1, 0, 1 (3 plots)
└─ Dynamic chunks: ±2, ±3, ±4, ±5 (8 plots)

Expected Guild Count: 5-10 active guilds
Solo/Neutral Players: 20-50 players across 5 factions
Database: PostgreSQL (SQLite ok for <50 trees)
Caching: None (add Redis at 200+ trees)

Expansion Path:
Month 1: Reach ±8 (19 plots)
Month 6: Reach ±12 (27 plots)
Year 1: 50+ active trees
```

---

## ✅ Design Status

**Version 2.1 (REVISED)**: All critical design flaws fixed with user corrections applied.

**Key Changes from v2.0**:
1. ✅ Removed 3-tier competition → Single winner (all ranks compete)
2. ✅ Universal Bane system → ANY tree can be sieged (not just origin)
3. ✅ Added server capacity analysis → Recommend 11 starting plots
4. ✅ Extended decay → 90 days for dynamic chunks (3-month vacation buffer)

**Ready for**:
- Database migration
- Backend implementation
- Godot integration
- Testing

**Next Step**: Create database migration script with all new columns and tables.

---

**Design Complete!** 🎉
