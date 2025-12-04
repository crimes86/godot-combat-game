# Settlement System Design Spec

## Overview

A guild-shared base system inspired by Shadowbane sieges and WoW garrisons. Players gather resources in the world, return to their settlement to deposit/craft, and defend it from other players during siege windows.

**Core Loop:** Explore → Pillage → Return Home → Unload → Rest → Repeat

---

## 1. World Structure & POI System

### Chunk Layout

```
CHUNK 0 (Edge)         CHUNK 1 (Center)       CHUNK 2 (Edge)
┌──────┬──────┐       ┌─────────────┐        ┌──────┬──────┐
│ POI  │ POI  │       │             │        │ POI  │ POI  │
│  NW  │  NE  │       │  CAMPFIRE   │        │  NW  │  NE  │
├──────┼──────┤       │  BLACKSMITH │        ├──────┼──────┤
│ POI  │ POI  │       │  (Noob Zone)│        │ POI  │ POI  │
│  SW  │  SE  │       │             │        │  SW  │  SE  │
└──────┴──────┘       └─────────────┘        └──────┴──────┘
   8 POI slots            Safe Zone            8 POI slots
```

### Chunk Roles

| Chunk | Role | POI Slots | Features |
|-------|------|-----------|----------|
| 0 (West Edge) | Exploration | 4 quadrants | Settlements, Ruins, Dangers |
| 1 (Center) | Starter/Safe | 0 | Campfire, Blacksmith, Tutorial |
| 2 (East Edge) | Exploration | 4 quadrants | Settlements, Ruins, Dangers |

### POI Quadrant System

Each edge chunk divided into 4 quadrants (~4000x4000 each):

```gdscript
# POI generation for edge chunks
const GUARANTEED_POIS = ["settlement_plot", "ruins"]  # 1 of each per chunk

const RANDOM_POI_POOL = [
    {"type": "monster_lava_lake", "weight": 35},  # Giant lava + elite spawns
    {"type": "resource_node", "weight": 30},       # Dense trees/rocks/ore
    {"type": "monster_den", "weight": 20},         # Elite enemy camp
    {"type": "ancient_shrine", "weight": 15},      # Buff altar / lore
]

# Per edge chunk:
# - 2 quadrants: guaranteed POIs (settlement + ruins)
# - 2 quadrants: weighted random from pool
# - Small lava pools: ambient scatter (don't compete for slots)
```

### Example World Generation

```
CHUNK 0                           CHUNK 2
┌──────────┬──────────┐          ┌──────────┬──────────┐
│Settlement│Lava Lake │          │  Ruins   │Settlement│
│  Plot    │ (Elite)  │          │          │  Plot    │
├──────────┼──────────┤          ├──────────┼──────────┤
│  Ruins   │ Resource │          │ Monster  │Lava Lake │
│          │  Node    │          │   Den    │ (Elite)  │
└──────────┴──────────┘          └──────────┴──────────┘

World Totals: 2 Settlements, 2 Ruins, 2 Lava Lakes, 1 Resource, 1 Den
(varies by seed - guaranteed: 2 settlements, 2 ruins)
```

---

## 2. Settlement Placement

Settlements are placed as one of the guaranteed POIs per edge chunk.

**Placement Rules:**
- One per edge chunk quadrant (2 total in world)
- Far enough from main path to require travel
- Minimum spacing from other POIs in same chunk
- Quadrant assignment is seeded/deterministic

**Visual Marker (Unclaimed):**
- Old foundation stones / cleared area
- "Abandoned Camp" signpost
- Faint outline showing plot boundaries

---

## 3. Settlement Structure

### Fixed Footprint, Player-Chosen Upgrades

Each settlement has a **fixed layout grid** with **slots** players fill:

```
SETTLEMENT PLOT (~500x500 units)
┌─────────────────────────────────────────┐
│                                         │
│  [WALL_NW]              [WALL_NE]       │  ← Tier 4: Palisade slots
│       [TOWER_N]                         │  ← Tier 5: Watchtower slot
│                                         │
│  [STATION_NW]     [STATION_NE]          │  ← Tier 2-3: Crafting/utility
│                                         │
│           ★ CENTRAL FIRE ★              │  ← Core: Always present
│           (Control Point)               │
│                                         │
│  [STATION_SW]     [STATION_SE]          │  ← Tier 2-3: Crafting/utility
│                                         │
│       [TOWER_S]                         │  ← Tier 5: Watchtower slot
│  [WALL_SW]    [GATE]    [WALL_SE]       │  ← Tier 4: Walls + Gate
│                                         │
└─────────────────────────────────────────┘
```

### Slot Types

| Slot Category | Count | Purpose |
|---------------|-------|---------|
| Central Fire | 1 | Control point, respawn, guild binding |
| Station Slots | 4 | Crafting, storage, services |
| Wall Slots | 4 | Defensive perimeter |
| Tower Slots | 2 | Vision, NPC defenders |
| Gate Slot | 1 | Entry/exit chokepoint |

---

## 3. Building Types (Colonial FOB Theme)

### Tier 1 - Starter (Friendly Rep)

| Building | Slot Type | Function |
|----------|-----------|----------|
| **Supply Tent** | Station | Shared guild storage (50 slots) |
| **Bedroll Camp** | Station | Basic rest (slow HP regen) |

### Tier 2 - Established (Honored Rep)

| Building | Slot Type | Function |
|----------|-----------|----------|
| **Armory Tent** | Station | Gear repair, weapon racks |
| **Crafting Station** | Station | Convert raw mats → items |
| **Storage Expansion** | Station | +100 storage slots |

### Tier 3 - Fortified (Revered Rep)

| Building | Slot Type | Function |
|----------|-----------|----------|
| **Galley** | Station | Cook food, buff meals |
| **Barracks** | Station | Bind respawn, recruit NPCs |
| **Command Tent** | Station | Guild management, war table |

### Tier 4 - Defended (Exalted Rep)

| Building | Slot Type | Function |
|----------|-----------|----------|
| **Palisade Wall** | Wall | 500 HP barrier |
| **Reinforced Gate** | Gate | 750 HP, controls entry |
| **Spike Barrier** | Wall | 300 HP, damages attackers |

### Tier 5 - Military (Max Rep + Resources)

| Building | Slot Type | Function |
|----------|-----------|----------|
| **Watchtower** | Tower | Extended vision, archer NPC |
| **Ballista Platform** | Tower | Siege weapon (player operated) |
| **Stone Wall Upgrade** | Wall | 1000 HP (replaces palisade) |

---

## 4. Progression System

### Blacksmith Reputation Tiers

Reputation is earned by:
- Selling materials to blacksmith
- Completing blacksmith quests
- Crafting items
- Time played (passive daily gain)

| Rep Level | Points | Settlement Unlocks |
|-----------|--------|-------------------|
| Neutral | 0 | Campfire access only |
| Friendly | 1000 | Claim plot, Supply Tent, Bedroll |
| Honored | 3000 | Armory, Crafting Station, Storage |
| Revered | 6000 | Galley, Barracks, Command Tent |
| Exalted | 10000 | Walls, Gates, Defenses |
| Legend | 15000 | Towers, Siege Weapons, Stone Walls |

### Building Costs (Example)

| Building | Wood | Stone | Metal | Gold |
|----------|------|-------|-------|------|
| Supply Tent | 50 | 0 | 10 | 100 |
| Armory Tent | 80 | 20 | 40 | 250 |
| Crafting Station | 60 | 40 | 30 | 200 |
| Galley | 100 | 30 | 20 | 300 |
| Barracks | 120 | 50 | 40 | 500 |
| Palisade Wall | 80 | 0 | 20 | 150 |
| Watchtower | 150 | 100 | 60 | 750 |

---

## 5. Claiming & Ownership

### Claim Process

1. Player reaches Friendly rep with blacksmith
2. Player discovers unclaimed settlement plot
3. Interact with plot center → "Claim for Guild" prompt
4. Pay claim fee (500 gold + 100 wood)
5. Central Fire spawns, plot is now owned

### Ownership Rules

- One settlement per guild
- Guild leader + officers can manage buildings
- Members can deposit/withdraw from storage
- Claim transfers if guild disbands (to highest rep member)

### Abandonment

- Settlement decays if no guild member logs in for 7 days
- Buildings lose 10% HP per day of inactivity
- After 14 days, settlement becomes unclaimed
- 50% of stored resources remain for new claimers

---

## 6. Storage System (The Funnel)

### Shared Guild Inventory

```gdscript
var settlement_storage = {
    "settlement_id": "plot_001",
    "owner_guild": "guild_uuid",
    "capacity": 150,  # Base 50 + expansions
    "items": [
        {"item_id": "wood", "quantity": 500},
        {"item_id": "stone", "quantity": 200},
        {"item_id": "iron_ore", "quantity": 75},
        # ...
    ],
    "deposit_log": [
        {"player": "Player123", "item": "wood", "qty": 50, "time": 1234567890},
        # ...
    ]
}
```

### Deposit/Withdraw

- Any guild member can deposit anytime
- Withdraw limits based on rank (prevent theft)
- Officer+ can set withdraw permissions
- All transactions logged

### Resource Categories

| Category | Examples | Storage Weight |
|----------|----------|----------------|
| Raw Materials | Wood, Stone, Ore | 1x |
| Processed | Planks, Ingots, Leather | 2x |
| Equipment | Weapons, Armor | 5x |
| Consumables | Food, Potions | 1x |
| Valuables | Gold, Gems | 0.1x |

---

## 7. Siege System

### Vulnerability Windows

Settlements can only be attacked during scheduled windows:

```gdscript
const SIEGE_WINDOW_DURATION: float = 2.0  # 2 hours
const SIEGE_WINDOWS_PER_WEEK: int = 3  # Mon/Wed/Sat

# Guild sets their preferred window time
var siege_schedule = {
    "settlement_id": "plot_001",
    "windows": [
        {"day": "monday", "hour": 20},  # 8 PM local
        {"day": "wednesday", "hour": 20},
        {"day": "saturday", "hour": 14}  # 2 PM local
    ]
}
```

### Siege Mechanics

**Initiating Siege:**
1. Attacking guild places "Siege Banner" outside settlement
2. 30-minute warning period (defenders notified)
3. Siege begins, buildings become attackable

**Victory Conditions:**
- **Attackers Win:** Destroy Central Fire (capture settlement)
- **Defenders Win:** Destroy Siege Banner OR survive window
- **Stalemate:** Partial building damage, no ownership change

### Building Combat

| Building | HP | Repair Cost | Rebuild Cost |
|----------|-----|-------------|--------------|
| Supply Tent | 200 | 10% mats | 100% mats |
| Palisade | 500 | 20% mats | 100% mats |
| Watchtower | 400 | 25% mats | 100% mats |
| Central Fire | 1000 | Cannot repair during siege | N/A |

### Loot on Capture

- Attackers receive 25% of storage contents
- 50% remains for new owners
- 25% is destroyed/lost

---

## 8. Data Structures

### Settlement Plot (World Gen)

```gdscript
var settlement_plot = {
    "plot_id": "plot_chunk1_001",
    "position": Vector2(5000, -2000),
    "chunk_id": 1,
    "radius": 250.0,
    "claimed": false,
    "owner_guild": null,
    "buildings": {},
    "storage": {},
    "siege_schedule": null
}
```

### Built Settlement

```gdscript
var settlement = {
    "plot_id": "plot_chunk1_001",
    "owner_guild": "guild_uuid_here",
    "claimed_at": 1234567890,
    "last_activity": 1234567890,
    "buildings": {
        "central_fire": {"type": "central_fire", "hp": 1000, "max_hp": 1000, "tier": 1},
        "station_nw": {"type": "supply_tent", "hp": 200, "max_hp": 200, "tier": 1},
        "station_ne": {"type": "armory_tent", "hp": 250, "max_hp": 250, "tier": 2},
        "station_sw": null,
        "station_se": {"type": "crafting_station", "hp": 200, "max_hp": 200, "tier": 2},
        "wall_nw": {"type": "palisade", "hp": 500, "max_hp": 500, "tier": 4},
        "wall_ne": null,
        "tower_n": null,
        # ...
    },
    "storage": {
        "capacity": 150,
        "items": []
    },
    "siege": {
        "windows": [],
        "last_siege": null,
        "protection_until": null  # 48h immunity after siege
    }
}
```

---

## 9. Implementation Phases

### Phase 1: Foundation
- [ ] Settlement plot generation (like ruins)
- [ ] Plot discovery/visibility
- [ ] Claim system (simple ownership)
- [ ] Central Fire placement

### Phase 2: Building
- [ ] Building slot system
- [ ] Tier 1-2 buildings (tents)
- [ ] Construction UI
- [ ] Resource costs

### Phase 3: Storage
- [ ] Shared guild inventory
- [ ] Deposit/withdraw mechanics
- [ ] Storage building upgrades

### Phase 4: Progression
- [ ] Blacksmith reputation tracking
- [ ] Rep-gated unlocks
- [ ] Tier 3-4 buildings

### Phase 5: Defense
- [ ] Building HP system
- [ ] Walls and gates
- [ ] Watchtowers

### Phase 6: Siege
- [ ] Vulnerability windows
- [ ] Siege initiation
- [ ] Combat mechanics
- [ ] Capture/loot system

---

## 10. Questions to Resolve

1. **Single vs Multi Settlement:** Can a guild have multiple settlements?
2. **Solo Players:** Can solo players claim plots, or guild-only?
3. **PvE Sieges:** Should NPC raids occur outside windows?
4. **Fast Travel:** Can players teleport to their settlement?
5. **Cross-Chunk:** What if settlement plot spans chunk boundary?
6. **Instanced vs Open:** Is settlement interior instanced or in open world?

---

## 11. Visual Reference

### Unclaimed Plot
```
     ~ ~ ~ ~ ~ ~
   ~             ~
  ~   [stones]    ~     ← Scattered foundation stones
  ~      ▢        ~     ← Faint boundary marker
  ~   [signpost]  ~     ← "Abandoned Camp"
   ~             ~
     ~ ~ ~ ~ ~ ~
```

### Tier 2 Settlement
```
    ════════════════
   ║                ║
   ║  [Armory]      ║
   ║       🔥       ║    ← Central Fire
   ║  [Supply]      ║
   ║                ║
    ════════════════
```

### Tier 5 Settlement (Fortified)
```
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
   ▓ 🗼            🗼 ▓   ← Watchtowers
   ▓                  ▓
   ▓ [Galley][Armory] ▓
   ▓       🔥        ▓   ← Central Fire
   ▓ [Supply][Craft]  ▓
   ▓                  ▓
   ▓ 🗼    ⛩️    🗼 ▓   ← Gate + Towers
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
```

---

*Last Updated: 2024*
*Status: Design Spec - Not Implemented*
