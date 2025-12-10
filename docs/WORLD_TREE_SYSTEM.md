# World Tree System

> **Status**: Design Specification (NOT YET IMPLEMENTED)
> **Version**: 1.1
> **Last Updated**: December 2024
> **Replaces**: Settlement System (FUTURE_SPECS.md)
> **Inspiration**: Shadowbane's Tree of Life system

---

## Table of Contents

1. [Overview](#overview)
2. [Shadowbane Inspiration](#shadowbane-inspiration)
3. [World Structure Integration](#world-structure-integration)
4. [World Tree Seed](#world-tree-seed)
5. [Planting Process](#planting-process)
6. [Rank System](#rank-system)
7. [Runekeeper Protection](#runekeeper-protection)
8. [Building & NPC System](#building--npc-system)
9. [Resource Mines](#resource-mines)
10. [Warehouse & Economy](#warehouse--economy)
11. [Bane (Siege) System](#bane-siege-system)
12. [World Map Integration](#world-map-integration)
13. [Technical Implementation](#technical-implementation)
14. [Implementation Phases](#implementation-phases)

---

## Overview

The World Tree system is the player base-building mechanic for Dreadland. Players plant magical seeds that grow into World Trees - living guild anchors that provide respawn points, building protection, vendor services, and economic infrastructure.

### Core Concept

```
PROGRESSION PATH:

  Campfire → Blacksmith → Find Plot → Plant Seed → Rank Up Tree → Place Buildings
      ↓           ↓            ↓            ↓              ↓              ↓
  [Safe Zone]  [Gear Up]  [Explore]    [Claim]     [Invest Gold]    [Economy]
                                                                         ↓
                                              Vendors, Storage, Mines, Guild Services
```

### What a World Tree Provides

A "landed" guild (one with a World Tree) gains:

| Feature | Benefit |
|---------|---------|
| **Respawn Point** | Guild members bind here and respawn on death |
| **Building Protection** | Runekeeper makes structures invulnerable outside banes |
| **Vendor Placement** | Player-run shops with custom inventory and pricing |
| **Storage** | Warehouse for guild gold and resources |
| **Resource Income** | Claim mines for passive gold/material generation |
| **Map Presence** | Tree visible on world map (prestige + target) |
| **Safe Zone** | Protection radius with no enemy spawns |

---

## Shadowbane Inspiration

Our World Tree system draws heavily from [Shadowbane's Tree of Life](https://morloch.shadowbaneemulator.com/index.php/Tree_of_Life), adapting its core mechanics for Dreadland's scope:

### What We're Taking from Shadowbane

| Shadowbane Feature | Our Adaptation |
|-------------------|----------------|
| Tree of Life as city heart | World Tree as guild anchor |
| Rank 1-8 progression | Rank 1-7 progression (no Palace) |
| Runemaster protection slots | Runekeeper protection system |
| Building placement via deeds | Building placement via UI |
| Warehouse gold management | Simplified warehouse system |
| Resource mines | Claimable mines with hourly gold |
| Bane siege windows | Corruption siege windows |
| World map visibility | Tree rank visible on map |
| NPCs via contracts | NPCs via vendor slots |

### What We're Simplifying

| Shadowbane Complexity | Our Simplification |
|----------------------|-------------------|
| 120 limited city slots per server | Unlimited trees (1 per guild) |
| Palace/Realm rulership | No realm system (future consideration) |
| Complex resource types | Gold + 3 basic resources |
| Grid-based wall placement | No physical walls (tree provides protection) |
| 20+ building types | 8 core building types |
| Hermit blessing quests | No blessing requirements |

---

## World Structure Integration

### POI Generation

World Trees use the existing POI system. Each edge chunk has one guaranteed Seed Plot:

```gdscript
const GUARANTEED_POIS = ["seed_plot", "ruins"]  # 1 of each per edge chunk

const RANDOM_POI_POOL = [
    {"type": "monster_lava_lake", "weight": 35},
    {"type": "resource_node", "weight": 30},
    {"type": "monster_den", "weight": 20},
    {"type": "ancient_shrine", "weight": 15},
]
```

### Chunk Layout

```
CHUNK -1 (Edge)        CHUNK 0 (Center)       CHUNK +1 (Edge)
+------+------+       +-------------+        +------+------+
| POI  | POI  |       |             |        | POI  | POI  |
|  NW  |  NE  |       |  CAMPFIRE   |        |  NW  |  NE  |
+------+------+       |  BLACKSMITH |        +------+------+
| POI  | POI  |       |  (Safe Zone)|        | POI  | POI  |
|  SW  |  SE  |       |             |        |  SW  |  SE  |
+------+------+       +-------------+        +------+------+

Each edge chunk has exactly ONE Seed Plot (guaranteed POI)
```

### Seed Plot Specifications

| Property | Value | Notes |
|----------|-------|-------|
| Size | 600x600 units | Large circular area for tree + buildings |
| Visual | Glowing fertile soil | Magical particles, ancient runes |
| Interaction | "[F] Examine Plot" | 150 unit range |
| Spawn | 1 per edge chunk | Guaranteed POI |
| Claim requirement | World Tree Seed + Guild Leader/Officer |

---

## World Tree Seed

### Obtaining the Seed

**Phase 1 (Initial Implementation):**
- Available at the Blacksmith vendor
- Cost: 1,000 gold (significant investment)
- Listed under "Tools" tab
- One seed per purchase

**Phase 2+ (Future):**
- Rare drop from elite enemies
- Quest reward from Blacksmith quest line
- Found in ruins exploration

### Seed Item Definition

```gdscript
# data/shop_tools.json
{
    "id": "world_tree_seed",
    "name": "World Tree Seed",
    "description": "A magical seed that grows into a World Tree when planted in fertile soil. Establishes your guild's presence in the world.",
    "price": 1000,
    "icon": "res://assets/icons/tools/world_tree_seed.png",
    "type": "tool",
    "consumable": true,
    "stack_size": 1,
    "guild_item": true
}
```

---

## Planting Process

### Requirements

To plant a World Tree:
1. Player must be Guild Leader or Officer
2. Player must have World Tree Seed in inventory
3. Guild must not already have a World Tree
4. Seed Plot must be unclaimed

### Planting Flow

```
Player approaches unclaimed Seed Plot
         │
         ▼
┌────────────────────────────────┐
│ "[F] Examine Plot"             │
│ Player presses F               │
└────────────┬───────────────────┘
             │
             ▼
┌────────────────────────────────┐
│ Validation checks:             │
│ - Has seed?                    │
│ - Is guild leader/officer?     │
│ - Guild has no tree?           │
│ - Plot unclaimed?              │
└────────────┬───────────────────┘
             │
     ┌───────┴───────┐
     │ FAIL          │ PASS
     ▼               ▼
┌──────────────┐  ┌──────────────────────────────┐
│ Show reason: │  │ Show planting confirmation:  │
│ "Your guild  │  │                              │
│ already has  │  │ "Plant World Tree Seed for   │
│ a tree."     │  │ [GuildName] at this location?│
│              │  │                              │
│ "Must be     │  │ This will consume the seed   │
│ guild leader │  │ and bind your guild here.    │
│ to plant."   │  │                              │
└──────────────┘  │     [Plant]    [Cancel]      │
                  └────────────┬─────────────────┘
                               │
                               ▼ (Confirm)
                  ┌────────────────────────────────┐
                  │ - Consume seed                 │
                  │ - Create Rank 1 tree           │
                  │ - Broadcast server message:    │
                  │   "A new World Tree has been   │
                  │    planted by [GuildName]!"    │
                  │ - Tree appears on world map    │
                  └────────────────────────────────┘
```

### Ownership Rules

| Rule | Description |
|------|-------------|
| One tree per guild | Guilds can only have one World Tree |
| Guild-bound | Tree belongs to guild, not individual player |
| Non-transferable | Cannot give/sell tree to another guild |
| Persistent | Tree exists when all members offline |
| Destructible | Can be destroyed during bane siege |

---

## Rank System

Inspired by [Shadowbane's Tree of Life ranks](https://morloch.shadowbaneemulator.com/index.php/Tree_of_Life), our trees progress through 7 ranks:

### Rank Progression

| Rank | Name | Gold Cost | Health | Upgrade Time | Protection Slots | Mine Limit |
|------|------|-----------|--------|--------------|------------------|------------|
| 1 | Sapling | - | 10,000 | - | 2 | 1 |
| 2 | Young Tree | 10,000 | 20,000 | 1 hour | 4 | 1 |
| 3 | Growing Tree | 25,000 | 35,000 | 4 hours | 6 | 2 |
| 4 | Mature Tree | 50,000 | 55,000 | 12 hours | 8 | 2 |
| 5 | Ancient Tree | 100,000 | 80,000 | 24 hours | 10 | 3 |
| 6 | Elder Tree | 200,000 | 110,000 | 48 hours | 12 | 4 |
| 7 | World Tree | 500,000 | 150,000 | 72 hours | 15 | 5 |

### Rank Benefits

Each rank unlocks additional capabilities:

| Rank | Unlocks |
|------|---------|
| 1 | Basic respawn, Runekeeper (2 slots), 1 mine claim |
| 2 | Warehouse, first vendor slot |
| 3 | Second vendor slot, storage expansion |
| 4 | Shrine slot (buffs), safe zone expansion |
| 5 | Third vendor slot, teleport bind |
| 6 | Fourth vendor slot, extended protection radius |
| 7 | All features, maximum prestige, siege resistance |

### Watering System

Trees require **Purified Water** to grow and thrive. This creates an exploration loop where players venture into the world to gather water for their tree.

#### Cleansing Lava Pools

Lava pools scattered throughout the world can be **cleansed** to collect water:

```
Player approaches Lava Pool with Empty Vial
         │
         ▼
"[F] Cleanse Pool" (requires Empty Vial)
         │
         ▼
┌────────────────────────────────────────┐
│ Cleansing animation plays (3 seconds)  │
│ - Lava cools and darkens               │
│ - Steam rises                          │
│ - Water forms in center                │
└────────────────────────────────────────┘
         │
         ▼
Player receives "Purified Water" item
Lava Pool enters cooldown (5 minutes)
Pool visually "depleted" until reset
```

#### Watering Benefits

| Action | Effect |
|--------|--------|
| Water tree (daily) | +10% growth speed toward next rank |
| Water tree (during upgrade) | Reduces upgrade time by 10% |
| Neglect watering (7+ days) | Tree growth pauses (no decay, just stasis) |

#### Water Items

| Item | Source | Stack Size | Use |
|------|--------|------------|-----|
| Empty Vial | Blacksmith (50g) | 20 | Required to collect water |
| Purified Water | Cleansed lava pool | 10 | Water your World Tree |
| Blessed Water | Rare drop / shrine | 5 | +25% growth boost (one-time) |

#### Lava Pool Mechanics

- **Respawn**: Lava pools regenerate water every 5 minutes
- **Contested**: Multiple players can cleanse the same pool (first come, first served per cycle)
- **Visual States**:
  - Active (glowing orange) = ready to cleanse
  - Cooling (dark red/gray) = recently cleansed, on cooldown
  - Ready (blue shimmer) = water available

This system encourages:
1. **Exploration** - Find lava pools in the world
2. **Regular play** - Daily watering for growth bonus
3. **Resource management** - Carry vials, plan routes
4. **Soft competition** - Race to cleanse pools in busy areas

### Visual Progression

```
RANK 1: SAPLING            RANK 3: GROWING           RANK 5: ANCIENT
      |                        ###                      #####
     /|\                      #####                   #########
    / | \                    #######                 ###########
   ~~~|~~~                      |                    ####|||####
                               /|\                      /|||\
                              / | \                    //|||\\\
                           ~~~~/|\~~~~              ~~~~|||~~~~

RANK 7: WORLD TREE
           ######
        ############
      ################
     ##################
    ####################
       #####||||#####
           /||||\
          //||||\\\
        ///||||||\\\\\
     ~~~~~~~~||||~~~~~~~~
        [Glowing Runes]
```

### World Map Display

Trees display their rank on the world map (like Shadowbane):

```
┌─────────────────────────────────────────────────────┐
│                    WORLD MAP                         │
├─────────────────────────────────────────────────────┤
│                                                      │
│    [R3]                              [R7]           │
│     │                                  │            │
│   Growing Tree                    World Tree        │
│   "Iron Guard"                   "The Defenders"    │
│                                                      │
│                  [R1]                               │
│                    │                                │
│               Sapling                               │
│            "New Guild"                              │
│                                                      │
└─────────────────────────────────────────────────────┘

Lower rank trees signal weakness - potential bane targets
Higher rank trees signal strength - harder to siege
```

---

## Runekeeper Protection

Inspired by [Shadowbane's Runemaster](https://morloch.shadowbaneemulator.com/index.php/City_Building_Guide), the Runekeeper protects buildings from damage:

### How Protection Works

1. **Runekeeper NPC** automatically spawns when tree reaches Rank 1
2. Runekeeper has **protection slots** based on tree rank
3. Each building/vendor must be assigned to a slot to be protected
4. **Protected buildings are INVULNERABLE** outside of bane windows
5. **Unprotected buildings can be damaged any time**

### Protection Slot Management

```
╔═══════════════════════════════════════════════════════════════════╗
║                        RUNEKEEPER                                  ║
║                  "Guardian of the Grove"                           ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Protection Slots: 8/10 used (Rank 5 Tree)                        ║
║                                                                    ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  PROTECTED BUILDINGS                                        │  ║
║  ├─────────────────────────────────────────────────────────────┤  ║
║  │  [1] Warehouse ................ PROTECTED                   │  ║
║  │  [2] Weapon Vendor ............ PROTECTED                   │  ║
║  │  [3] Armor Vendor ............. PROTECTED                   │  ║
║  │  [4] Potion Vendor ............ PROTECTED                   │  ║
║  │  [5] Shrine of Warfare ........ PROTECTED                   │  ║
║  │  [6] Storage Chest #1 ......... PROTECTED                   │  ║
║  │  [7] Storage Chest #2 ......... PROTECTED                   │  ║
║  │  [8] Crafting Station ......... PROTECTED                   │  ║
║  │  [_] (empty slot)                                           │  ║
║  │  [_] (empty slot)                                           │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  UNPROTECTED:                                                      ║
║  - Decorative Banner (vulnerable to damage)                        ║
║                                                                    ║
║                                              [Manage]  [Close]     ║
╚═══════════════════════════════════════════════════════════════════╝
```

### Protection Rules

| Rule | Description |
|------|-------------|
| Tree always protected | World Tree itself is always protected (its own entity) |
| Slots are limited | Choose which buildings matter most |
| Unprotected = vulnerable | Buildings outside slots can be attacked anytime |
| During bane = all vulnerable | ALL buildings can be damaged during active siege |

---

## Building & NPC System

Inspired by [Shadowbane's building and NPC system](https://morloch.shadowbaneemulator.com/index.php/Buildings), players can place various structures around their tree:

### Building Types

| Building | Cost | Protection Slots | Function |
|----------|------|------------------|----------|
| **Warehouse** | 5,000g | 1 | Stores guild gold and resources |
| **Weapon Vendor** | 2,000g | 1 | Player-stocked weapon shop |
| **Armor Vendor** | 2,000g | 1 | Player-stocked armor shop |
| **Potion Vendor** | 2,000g | 1 | Player-stocked consumables |
| **General Vendor** | 3,000g | 1 | Sells any item type |
| **Shrine** | 10,000g | 1 | Grants buff to guild members |
| **Storage Chest** | 1,000g | 1 | Additional storage space |
| **Crafting Station** | 5,000g | 1 | Convert materials to items |

### Shrine Types

Shrines provide powerful buffs (inspired by [Shadowbane shrines](https://morloch.shadowbaneemulator.com/index.php/Buildings)):

| Shrine | Buff | Duration |
|--------|------|----------|
| Shrine of Warfare | +10% damage | 30 minutes |
| Shrine of Vitality | +15% max HP | 30 minutes |
| Shrine of Swiftness | +10% movement speed | 30 minutes |
| Shrine of Fortune | +10% gold drops | 30 minutes |
| Shrine of Protection | +10% damage reduction | 30 minutes |

Only one shrine buff active at a time per player.

### Building Placement UI

```
╔═══════════════════════════════════════════════════════════════════╗
║                      PLACE BUILDING                                ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Building: Weapon Vendor                                           ║
║  Cost: 2,000 gold                                                  ║
║  Protection Slots Required: 1                                      ║
║                                                                    ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │                                                              │  ║
║  │                    [TREE VISUAL]                             │  ║
║  │                         |||                                  │  ║
║  │              [A]       /|||\       [B]                       │  ║
║  │                       //|||\\\                                │  ║
║  │         [C]         ~~~|||~~~         [D]                    │  ║
║  │                                                              │  ║
║  │              [E]                   [F]                       │  ║
║  │                                                              │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  Click a position (A-F) to place the building.                    ║
║  Occupied: [C] Warehouse, [E] Armor Vendor                        ║
║                                                                    ║
║  Your Gold: 12,450                                                 ║
║  Protection Slots: 6/10 available                                  ║
║                                                                    ║
║                                   [Cancel]                         ║
╚═══════════════════════════════════════════════════════════════════╝
```

### Vendor Operation

Once placed, vendors work like player shops:

1. **Owner/Officer stocks inventory** - Drag items, set prices
2. **Visitors browse and buy** - Standard shop interface
3. **Revenue goes to warehouse** - 5% tax deducted
4. **Stock depletes** - Must restock when sold out

---

## Resource Mines

Inspired by [Shadowbane's mine system](https://morloch.shadowbaneemulator.com/index.php/Mine), guilds can claim resource mines for passive income:

### Mine Types

Mines spawn in the world as contested POIs:

| Mine Type | Hourly Yield | Location |
|-----------|--------------|----------|
| Gold Mine | 500 gold | Various |
| Stone Quarry | 100 stone | Mountains |
| Lumber Camp | 100 lumber | Forests |
| Iron Deposit | 50 iron | Caves |

### Mine Claiming

```
MINE CLAIMING FLOW:

Player approaches unclaimed mine
         │
         ▼
"[F] Claim Mine for [GuildName]"
         │
         ▼
┌────────────────────────────────────────┐
│ Claiming requires:                     │
│ - Guild must have World Tree           │
│ - Tree rank determines max mines       │
│ - 30-second channel (interruptible)    │
└────────────────────────────────────────┘
         │
         ▼
Channel completes → Mine claimed
         │
         ▼
Resources deposited to Warehouse hourly
```

### Mine Limits by Tree Rank

| Tree Rank | Max Mines |
|-----------|-----------|
| 1-2 | 1 |
| 3-4 | 2 |
| 5 | 3 |
| 6 | 4 |
| 7 | 5 |

### Mine Vulnerability Windows

Like Shadowbane, mines have [vulnerability windows](https://morloch.shadowbaneemulator.com/index.php/Mine):

- Each mine is vulnerable for **30 minutes per day**
- Window time is set by the owning guild
- During window, enemies can attack and reclaim
- Outside window, mine is invulnerable

```
╔═══════════════════════════════════════════════════════════════════╗
║                        MINE MANAGEMENT                             ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  Guild Mines: 2/3 (Rank 5 Tree)                                   ║
║                                                                    ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  [1] Eastern Gold Mine                                      │  ║
║  │      Yield: 500g/hour                                       │  ║
║  │      Vulnerability: 8:00 PM - 8:30 PM                       │  ║
║  │      Status: SECURE                                         │  ║
║  │                                             [Set Window]    │  ║
║  ├─────────────────────────────────────────────────────────────┤  ║
║  │  [2] Northern Lumber Camp                                   │  ║
║  │      Yield: 100 lumber/hour                                 │  ║
║  │      Vulnerability: 9:00 PM - 9:30 PM                       │  ║
║  │      Status: SECURE                                         │  ║
║  │                                             [Set Window]    │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║                                                      [Close]       ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

## Warehouse & Economy

Inspired by [Shadowbane's warehouse system](https://morloch.shadowbaneemulator.com/index.php/City_Building_Guide):

### Warehouse Functions

1. **Gold Storage** - Holds guild treasury
2. **Resource Storage** - Stone, lumber, iron
3. **Maintenance Payments** - Auto-deducts weekly upkeep
4. **Revenue Collection** - Vendor sales deposited here
5. **Mine Income** - Hourly deposits from claimed mines

### Maintenance Costs

Buildings require weekly maintenance (like Shadowbane):

| Asset | Weekly Cost |
|-------|-------------|
| World Tree (any rank) | 1,000g |
| Warehouse | 500g |
| Each Vendor | 200g |
| Each Shrine | 500g |
| Storage Chest | 100g |
| Crafting Station | 300g |

### Maintenance Failure

If warehouse lacks gold for maintenance:
1. **Week 1**: Warning notification
2. **Week 2**: Building begins degrading (reduced functionality)
3. **Week 3**: Building collapses (must rebuild)

### Warehouse UI

```
╔═══════════════════════════════════════════════════════════════════╗
║                          WAREHOUSE                                 ║
║                    "Guild Treasury"                                ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                    ║
║  TREASURY                                                          ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  Gold: 45,230                                               │  ║
║  │  Stone: 1,200 / 5,000                                       │  ║
║  │  Lumber: 890 / 5,000                                        │  ║
║  │  Iron: 340 / 2,000                                          │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  WEEKLY MAINTENANCE (Due in 3 days)                               ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  World Tree ............... 1,000g                          │  ║
║  │  Warehouse ................ 500g                            │  ║
║  │  Weapon Vendor ............ 200g                            │  ║
║  │  Armor Vendor ............. 200g                            │  ║
║  │  Shrine of Warfare ........ 500g                            │  ║
║  │  ─────────────────────────────────                          │  ║
║  │  TOTAL .................... 2,400g                          │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  INCOME THIS WEEK                                                  ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  Vendor Sales ............. +3,450g (after 5% tax)          │  ║
║  │  Gold Mine ................ +84,000g (168 hours)            │  ║
║  │  ─────────────────────────────────                          │  ║
║  │  TOTAL .................... +87,450g                        │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                    ║
║  [Deposit]  [Withdraw]  [History]                    [Close]       ║
╚═══════════════════════════════════════════════════════════════════╝
```

---

## Bane (Siege) System

Inspired by [Shadowbane's bane mechanics](https://morloch.shadowbaneemulator.com/index.php/Bane_Guide), World Trees can be sieged through a "Corruption Bane":

### Bane Overview

| Shadowbane Term | Our Term | Description |
|-----------------|----------|-------------|
| Bane Circle | Corruption Stone | Placed to initiate siege |
| Bane Window | Corruption Window | Time when siege is active |
| Tree Destruction | Tree Corruption | Victory condition |

### Initiating a Bane

To bane another guild's tree:

1. **Purchase Corruption Stone** from special vendor (cost based on target tree rank)
2. **Carry stone to target tree** (within 500 units)
3. **Plant stone** (30-second channel, interruptible)
4. **3-day countdown begins** - Both sides prepare

### Corruption Stone Costs

| Target Tree Rank | Stone Cost |
|------------------|------------|
| 1-2 | 5,000g |
| 3-4 | 15,000g |
| 5-6 | 50,000g |
| 7 | 100,000g |

### Bane Timeline

```
DAY 0: Stone Planted
├── Server broadcast: "[AttackGuild] has placed a Corruption Stone
│                      at [DefendGuild]'s World Tree!"
├── Stone visible to all players
└── Countdown timer visible

DAYS 1-2: Preparation Phase (Challenge/Standoff)
├── Both sides gather allies
├── Defenders set bane window time (within server's allowed hours)
├── All buildings remain PROTECTED (invulnerable)
└── Normal gameplay continues

DAY 3: Bane Window Opens
├── Duration: 2 hours
├── ALL buildings become vulnerable (Runekeeper protection suspended)
├── Attackers: Destroy World Tree to win
├── Defenders: Destroy Corruption Stone to win
└── PvP enabled in area regardless of flags

OUTCOMES:
├── ATTACKERS WIN: Tree corrupted, 7-day cooldown before replanting
│   └── All buildings destroyed, resources lost
├── DEFENDERS WIN: Stone destroyed, 24-hour immunity from new banes
│   └── Buildings restored to protected state
└── STALEMATE: Neither destroyed, stone expires
    └── Attackers lose stone investment
```

### Bane Window Rules

- **Defenders choose time** within server's window of opportunity
- **Server window**: 6:00 PM - 11:00 PM local time (5 hours)
- **If not set**: Defaults to latest hour (10:00 PM - 12:00 AM)
- **Duration**: 2 hours once active

### Combat During Bane

During an active bane:
- All buildings vulnerable (including protected ones)
- PvP enabled for all players in zone
- Respawns at tree still work (until tree destroyed)
- Tree HP visible to all combatants

### Victory Rewards

**Attackers Win:**
- Target tree destroyed (corruption spreads, dies)
- Defenders cannot replant for 7 days
- 25% of warehouse contents looted
- Attackers gain "Conqueror" title (temporary)

**Defenders Win:**
- Corruption stone destroyed
- 24-hour bane immunity
- Defenders gain "Defender" title (temporary)
- Attacking guild pays 50% of stone cost as "war reparations"

---

## World Map Integration

### Map Visibility

All World Trees appear on the world map:

| Element | Visibility | Information Shown |
|---------|------------|-------------------|
| Tree Location | All players | Position on map |
| Tree Rank | All players | [R1] through [R7] |
| Guild Name | All players | Owner guild |
| Bane Status | All players | "UNDER SIEGE" if active |
| Your Tree | Guild only | Highlighted gold |
| Allied Trees | Alliance only | Highlighted blue |

### Map Legend

```
┌──────────────────────────────────────────────────────────────────┐
│                        WORLD MAP                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Legend:                                                          │
│  [R#] = Tree Rank (1-7)                                          │
│  Gold = Your Guild                                                │
│  Green = Allied Guild                                             │
│  Gray = Neutral Guild                                             │
│  Red Pulse = Under Siege (Bane Active)                           │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                              │ │
│  │        [R3]                                                  │ │
│  │      Iron Guard                      [R7]                    │ │
│  │        (gray)                     The Defenders              │ │
│  │                                      (GOLD)                  │ │
│  │                                                              │ │
│  │   [R5]                    [R1]                               │ │
│  │  Shadow Clan            New Guild                            │ │
│  │   (green)                (gray)                              │ │
│  │                                                              │ │
│  │              [R4]                                            │ │
│  │           Blood Ravens                                       │ │
│  │         (RED - SIEGE!)                                       │ │
│  │                                                              │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

### Strategic Implications

Like Shadowbane, low-rank trees signal vulnerability:
- **Rank 1-2**: "Easy target" - attracts raiders
- **Rank 3-4**: "Established" - moderate threat
- **Rank 5-6**: "Powerful" - serious investment required to bane
- **Rank 7**: "Fortress" - only attempt with strong alliance

---

## Technical Implementation

### Data Structures

```gdscript
class WorldTreeData:
    var tree_id: String
    var guild_id: String
    var guild_name: String
    var chunk_id: int
    var position: Vector2
    var rank: int                      # 1-7
    var health: int
    var max_health: int
    var planted_at: float              # Unix timestamp
    var last_maintenance: float
    var runekeeper_slots: int          # Based on rank
    var protected_buildings: Array     # Building IDs in protection
    var buildings: Array               # All building data
    var claimed_mines: Array           # Mine IDs
    var warehouse_gold: int
    var warehouse_resources: Dictionary
    var bane_status: BaneStatus        # null or active bane data

class BaneStatus:
    var attacker_guild_id: String
    var stone_planted_at: float
    var window_start: float
    var window_end: float
    var stone_health: int
    var is_active: bool

class BuildingData:
    var building_id: String
    var building_type: String          # "vendor_weapons", "shrine", etc.
    var position_slot: String          # "A" through "F"
    var health: int
    var is_protected: bool
    var vendor_inventory: Array        # If vendor type
    var vendor_prices: Dictionary
    var pending_gold: int
```

### New Files Required

```
scripts/
├── systems/
│   ├── WorldTreeManager.gd          # Global tree tracking (autoload)
│   ├── RunekeeperManager.gd         # Protection slot management
│   ├── MineManager.gd               # Mine claiming and income
│   ├── BaneManager.gd               # Siege system
│   ├── WarehouseManager.gd          # Treasury operations
│   └── WateringManager.gd           # Lava pool cleansing, water tracking
│
├── world/
│   ├── SeedPlot.gd                  # Unclaimed plot
│   ├── WorldTree.gd                 # Tree scene controller
│   ├── TreeBuilding.gd              # Generic building
│   ├── TreeVendor.gd                # Vendor building
│   ├── TreeShrine.gd                # Shrine building
│   ├── CorruptionStone.gd           # Bane stone
│   ├── ResourceMine.gd              # Claimable mine
│   └── CleanseableLavaPool.gd       # Lava pool with cleanse interaction
│
├── ui/
│   ├── WorldTreeUI.gd               # Main tree interface
│   ├── RunekeeperUI.gd              # Protection management
│   ├── WarehouseUI.gd               # Treasury interface
│   ├── MineManagementUI.gd          # Mine window settings
│   ├── BuildingPlacementUI.gd       # Place buildings
│   ├── VendorManagementUI.gd        # Stock vendors
│   └── BaneStatusUI.gd              # Siege information
│
└── networking/
    └── WorldTreeNetwork.gd          # All tree-related RPCs

scenes/
├── world/
│   ├── SeedPlot.tscn
│   ├── WorldTree.tscn               # Base tree (rank visuals as children)
│   ├── TreeBuildings/
│   │   ├── Warehouse.tscn
│   │   ├── VendorStall.tscn
│   │   ├── Shrine.tscn
│   │   └── StorageChest.tscn
│   ├── CorruptionStone.tscn
│   ├── ResourceMine.tscn
│   └── CleanseableLavaPool.tscn     # Modified lava pool with cleanse states
│
└── ui/
    ├── WorldTreeUI.tscn
    ├── RunekeeperUI.tscn
    ├── WarehouseUI.tscn
    └── BaneStatusUI.tscn

data/
├── shop_tools.json                  # Add Empty Vial (50g)
└── items/
    ├── empty_vial.json              # Consumable container
    ├── purified_water.json          # Standard water from lava pools
    └── blessed_water.json           # Rare water with +25% boost
```

---

## Implementation Phases

### Phase 1: Core Tree System
- [ ] Seed Plot POI generation
- [ ] World Tree Seed at Blacksmith (1,000g)
- [ ] Planting mechanic (guild-bound)
- [ ] Basic tree visual (Rank 1 only)
- [ ] Tree appears on world map
- [ ] Basic respawn binding

### Phase 2: Watering System
- [ ] Empty Vial item at Blacksmith (50g)
- [ ] CleanseableLavaPool.gd script (extends existing lava pools)
- [ ] Lava pool visual states (active/cooling/ready)
- [ ] Cleanse interaction (3-sec channel, consumes vial)
- [ ] Purified Water item
- [ ] Lava pool cooldown system (5 minutes)
- [ ] Water tree interaction in WorldTreeUI
- [ ] Daily watering bonus (+10% growth speed)
- [ ] Blessed Water rare drop

### Phase 3: Rank & Protection
- [ ] Rank upgrade system (1-7)
- [ ] Gold costs and upgrade timers
- [ ] Rank visuals (all 7 stages)
- [ ] Runekeeper NPC
- [ ] Protection slot system
- [ ] Tree health system

### Phase 4: Buildings & Vendors
- [ ] Building placement system
- [ ] Warehouse building
- [ ] Vendor buildings (weapon, armor, potion, general)
- [ ] Vendor stocking and pricing
- [ ] Revenue collection (5% tax)
- [ ] Storage chest buildings

### Phase 5: Economy
- [ ] Maintenance cost system
- [ ] Maintenance failure/degradation
- [ ] Resource mines spawning
- [ ] Mine claiming mechanic
- [ ] Mine vulnerability windows
- [ ] Hourly income deposits

### Phase 6: Shrines & Buffs
- [ ] Shrine buildings
- [ ] 5 shrine types (warfare, vitality, etc.)
- [ ] Buff application system
- [ ] Buff duration and stacking rules

### Phase 7: Bane System
- [ ] Corruption Stone item
- [ ] Stone placement mechanic
- [ ] 3-day countdown system
- [ ] Bane window selection
- [ ] Combat rules during bane
- [ ] Victory/defeat outcomes
- [ ] War reparations system

### Phase 8: Polish
- [ ] World map integration complete
- [ ] Alliance tree visibility
- [ ] Tree teleportation (Rank 5+)
- [ ] Ambient effects (particles, audio)
- [ ] Tutorial/onboarding

---

## Appendix: Shadowbane Reference Links

For deeper understanding of the source inspiration:

- [Tree of Life](https://morloch.shadowbaneemulator.com/index.php/Tree_of_Life) - Core tree mechanics
- [City Building Guide](https://morloch.shadowbaneemulator.com/index.php/City_Building_Guide) - Building placement and NPCs
- [Bane Guide](https://morloch.shadowbaneemulator.com/index.php/Bane_Guide) - Siege system details
- [Mine System](https://morloch.shadowbaneemulator.com/index.php/Mine) - Resource generation
- [Realm and Rulership](https://morloch.shadowbaneemulator.com/index.php/Realm_and_Rulership) - Advanced governance (future consideration)
- [Buildings](https://morloch.shadowbaneemulator.com/index.php/Buildings) - Building types and costs

---

## Summary

The World Tree system provides:

1. **Guild Identity** - Tree is the guild's home in the world
2. **Progression** - 7 ranks with meaningful unlocks
3. **Nurturing Loop** - Cleanse lava pools, water tree, accelerate growth
4. **Economy** - Vendors, warehouse, mines create gold flow
5. **Protection** - Runekeeper makes investment meaningful
6. **Conflict** - Bane system creates high-stakes PvP
7. **Visibility** - Map presence signals strength/weakness
8. **Maintenance** - Ongoing engagement to keep tree alive

This system captures the core magic of Shadowbane's city-building while simplifying for Dreadland's scope and playerbase.

---

*Document version 1.1 - December 2024*
*Inspired by Shadowbane's Tree of Life*
