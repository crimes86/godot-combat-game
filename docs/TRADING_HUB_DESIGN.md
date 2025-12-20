# Trading Hub & Zone Transition System

> **Status**: Phase 1 Implemented
> **Version**: 1.1
> **Last Updated**: December 2024

---

## Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| Tunnel Entrances (Zone 1) | ✅ Implemented | 3 entrances at north edge of each chunk |
| Level 10 Gate | ✅ Implemented | Shows denial message for lower levels |
| Scene Transition | ✅ Implemented | Fade to black, load hub scene |
| Trading Hub Scene | ✅ Implemented | Full layout with lighting, props, signs |
| Hub Exit (South → Zone 1) | ✅ Implemented | Walk south to return |
| Hub Exit (North → Zone 2) | ⏳ Placeholder | Shows "coming soon" message |
| Shard System | ⏳ Stub Only | Single shard, manager tracks state |
| Stash Access | ❌ Not Started | UI placeholder only |
| Tunnel Trader NPC | ❌ Not Started | Sign placeholder only |
| Multiplayer Sync | ❌ Not Started | Single player only for now |

### Quick Test Instructions

1. Open project in Godot 4.5
2. For testing, change `LEVEL_REQUIREMENT` in `scripts/trading_hub/TunnelEntrance.gd` from `10` to `1`
3. Run the game and walk north to any chunk's edge
4. Enter the tunnel entrance (stone archway with torches)
5. Explore the hub - walk south to exit back to Zone 1

---

## Table of Contents

1. [Overview](#overview)
2. [Design Philosophy](#design-philosophy)
3. [World Architecture](#world-architecture)
4. [Tunnel Entry System](#tunnel-entry-system)
5. [Tunnel Corridors](#tunnel-corridors)
6. [Trading Hub Layout](#trading-hub-layout)
7. [Shard System](#shard-system)
8. [Zone 2 Exit System](#zone-2-exit-system)
9. [Hub Features & Amenities](#hub-features--amenities)
10. [Atmosphere & Aesthetics](#atmosphere--aesthetics)
11. [Technical Implementation](#technical-implementation)
12. [Network Protocol](#network-protocol)
13. [Integration Points](#integration-points)
14. [Scene & Script Structure](#scene--script-structure)
15. [Future Considerations](#future-considerations)

---

## Overview

The Trading Hub is a safe, instanced zone that serves as the natural transition point between Zone 1 (levels 1-10) and Zone 2 (levels 10-20). Inspired by EverQuest's East Commonlands Tunnel, it creates an organic player marketplace by being the mandatory passage for character progression.

### Core Concept

```
ZONE 1 (dreadland)              TRADING HUB                    ZONE 2 (TBD)
Levels 1-10                     Safe Zone                      Levels 10-20
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

┌─────────────────────┐         ╔═══════════════╗         ┌─────────────────────┐
│                     │         ║               ║         │                     │
│  Dynamic chunks     │ ──────► ║  Instanced    ║ ──────► │  Dynamic chunks     │
│  scale horizontally │         ║  Sharded Hub  ║         │  scale horizontally │
│                     │         ║               ║         │                     │
└─────────────────────┘         ╚═══════════════╝         └─────────────────────┘
     Multiple                        Single                     Multiple
     Entrances                    Destination                    Exits
```

### Why This Works

1. **Natural Traffic**: Every player passes through to progress
2. **Safe Zone**: No combat pressure - players can AFK, browse, negotiate
3. **Organic Emergence**: Players discover it's THE trading spot, not forced
4. **Vertical Progression Gate**: Level 10 completion → Tunnel → Harder content
5. **Scalable**: Sharding handles any population without degrading experience

---

## Design Philosophy

### The EC Tunnel Effect

In EverQuest, the East Commonlands tunnel became the de facto marketplace not by design, but by geography. It was:
- A natural chokepoint between newbie zones and higher-level content
- Safe from wandering monsters
- Shelter from the game's weather system
- The only sensible path for progression

Players organically chose it as the trading hub because **everyone had to pass through anyway**.

### Our Implementation

We recreate this by:
1. **Geographical necessity** - The tunnel is the ONLY path to Zone 2
2. **Safety guarantee** - No combat, no enemies, no PvP
3. **Comfort amenities** - Stash access, vendor, warmth
4. **Social density** - Sharding keeps population comfortable but present
5. **Persistence** - Players can linger without penalty (until AFK timeout)

### Anti-Patterns We Avoid

| Anti-Pattern | Why It Fails | Our Solution |
|--------------|--------------|--------------|
| Dedicated "Auction House" building | Feels artificial, players rush in/out | Tunnel is a journey, not a destination |
| Global trade chat | No social presence, no trust signals | Physical proximity required |
| Instanced 1-on-1 trade rooms | Kills marketplace atmosphere | Open trading floor with alcoves |
| Fast travel to trade hub | Removes geographical meaning | Must walk through from Zone 1 |

---

## World Architecture

### Current World Layout (Zone 1)

```
Y = -4000 (NORTH) ─────────────────────────────────────────────────────────
                                    │
         ┌──────────────────────────┼──────────────────────────────────┐
         │                          │                                  │
         │                    [FOG BOUNDARY]                           │
         │                          │                                  │
         │     CHUNK -1             │    CHUNK 0         CHUNK +1      │
         │     (West)               │    (Center)        (East)        │
         │     Lv 6-10              │    Lv 1-5          Lv 6-10       │
         │                          │    Campfire                      │
         │                          │    (4000, 0)                     │
         │                          │                                  │
         └──────────────────────────┼──────────────────────────────────┘
                                    │
Y = +4000 (SOUTH) ─────────────────────────────────────────────────────────
      X=-8000                     X=0                X=8000          X=16000
```

### Extended World Layout (With Tunnel & Zone 2)

```
                              ZONE 2 - "THE DEPTHS" (Lv 10-20)
                    ┌───────────────────────────────────────────────┐
                    │                                               │
Y = -12000          │   [Origin -1]    [Origin 0]    [Origin +1]    │
                    │      Lv 10         Lv 10          Lv 10       │
                    │                                               │
                    │        │              │              │        │
                    └────────┼──────────────┼──────────────┼────────┘
                             │              │              │
                             ▼              ▼              ▼
                    ╔════════════════════════════════════════════════╗
Y = -8000           ║              TRADING HUB (Instanced)           ║
  to                ║                                                ║
Y = -4500           ║   Separate scene, not part of world grid       ║
                    ║   Multiple shards handle player load           ║
                    ╚════════════════════════════════════════════════╝
                             ▲              ▲              ▲
                             │              │              │
                    ┌────────┼──────────────┼──────────────┼────────┐
                    │        │              │              │        │
                    │   [Entry -1]     [Entry 0]     [Entry +1]     │
                    │                                               │
Y = -4000           │   ═══════════════════════════════════════     │ ← TUNNEL
  (NORTH EDGE)      │                 ENTRANCES                     │   ENTRANCES
                    │   ═══════════════════════════════════════     │
                    │                                               │
━━━━━━━━━━━━━━━━━━━━│═══════════════════════════════════════════════│━━━━━━━━━━━━
                    │                                               │
                    │     CHUNK -1      CHUNK 0       CHUNK +1      │
                    │     (West)        (Center)      (East)        │
                    │                   Campfire                    │
Y = 0               │                   (4000, 0)                   │  ZONE 1
                    │                                               │  (Lv 1-10)
                    │                                               │
                    │                                               │
Y = +4000           └───────────────────────────────────────────────┘
(SOUTH EDGE)
```

### Dynamic Horizontal Scaling Integration

Zone 1 chunks scale horizontally based on player population. The tunnel system must accommodate any number of entry points:

```
LOW POPULATION (3 chunks):
┌─────────┬─────────┬─────────┐
│ Chunk-1 │ Chunk 0 │ Chunk+1 │
└────┬────┴────┬────┴────┬────┘
     │         │         │
     ▼         ▼         ▼
  [Entry]   [Entry]   [Entry]
     │         │         │
     └─────────┼─────────┘
               │
         [TRADING HUB]


HIGH POPULATION (7 chunks):
┌────────┬────────┬────────┬────────┬────────┬────────┬────────┐
│Chunk-3 │Chunk-2 │Chunk-1 │Chunk 0 │Chunk+1 │Chunk+2 │Chunk+3 │
└───┬────┴───┬────┴───┬────┴───┬────┴───┬────┴───┬────┴───┬────┘
    │        │        │        │        │        │        │
    ▼        ▼        ▼        ▼        ▼        ▼        ▼
 [Entry] [Entry] [Entry] [Entry] [Entry] [Entry] [Entry]
    │        │        │        │        │        │        │
    └────────┴────────┴────────┼────────┴────────┴────────┘
                               │
                         [TRADING HUB]
                         (Same hub, more entrances)
```

**Key insight**: All entrances lead to the same hub (shard-selected). The number of Zone 1 chunks doesn't affect hub capacity—sharding handles that separately.

---

## Tunnel Entry System

### Entry Point Placement

Each Zone 1 chunk gets exactly one tunnel entrance at its north edge:

```gdscript
# Pseudocode for entry point generation
func generate_tunnel_entries():
    var active_chunks = ChunkManager.get_active_zone1_chunks()

    for chunk_id in active_chunks:
        var entry_x = get_chunk_center_x(chunk_id)
        var entry_y = ZONE1_NORTH_BOUNDARY  # -4000

        spawn_tunnel_entrance(Vector2(entry_x, entry_y), chunk_id)
```

### Entry Point Specifications

| Property | Value | Notes |
|----------|-------|-------|
| Position Y | -4000 (north edge) | At fog boundary |
| Position X | Chunk center | `chunk_id * CHUNK_SIZE + CHUNK_SIZE/2` |
| Collision shape | 200px wide, 100px tall | Trigger zone |
| Visual | Cave mouth / stone archway | Cuts through fog |
| Interaction | Walk into to enter | No button press |
| Minimum level | 10 | Lower levels see "The darkness repels you" |

### Entry Visual Design

```
                    ┌─────────────────────┐
                    │   FOG / DARKNESS    │
    ════════════════╪═══════════════════════════════════
                    │                     │
              ╔═════╧═════╗         ╔═════╧═════╗
              ║  ▓▓▓▓▓▓▓  ║         ║  ▓▓▓▓▓▓▓  ║
              ║ ▓       ▓ ║         ║ ▓       ▓ ║
              ║▓  ENTRY  ▓║         ║▓  ENTRY  ▓║
              ║▓         ▓║         ║▓         ▓║
              ║▓▓▓▓▓▓▓▓▓▓▓║         ║▓▓▓▓▓▓▓▓▓▓▓║
              ╚═══════════╝         ╚═══════════╝
                    │                     │
    ────────────────┴─────────────────────┴────────────
              ZONE 1 CHUNK              ZONE 1 CHUNK
```

### Entry Interaction Flow

```
Player walks north in Zone 1
         │
         ▼
Reaches fog boundary (Y < -3900)
         │
         ▼
┌────────────────────────────────┐
│ Check: Player level >= 10?     │
└────────────────┬───────────────┘
                 │
        ┌────────┴────────┐
        │ NO              │ YES
        ▼                 ▼
┌───────────────┐  ┌──────────────────────┐
│ Show message: │  │ Player enters        │
│ "The darkness │  │ tunnel collision     │
│ repels you.   │  │ trigger zone         │
│ Return when   │  └──────────┬───────────┘
│ stronger."    │             │
└───────────────┘             ▼
                  ┌──────────────────────┐
                  │ Begin transition:    │
                  │ - Fade to black      │
                  │ - Store origin chunk │
                  │ - Request hub shard  │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ Load tunnel corridor │
                  │ scene (per-player    │
                  │ instance briefly)    │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ Walk through corridor│
                  │ (10-15 seconds)      │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │ Enter hub shard      │
                  │ (multiplayer scene)  │
                  └──────────────────────┘
```

---

## Tunnel Corridors

### Design Intent

The corridor serves multiple purposes:
1. **Atmospheric transition** - Shift from dreadland to underground
2. **Loading buffer** - Time to load hub scene and sync players
3. **Anticipation builder** - Hear echoes of trading activity ahead
4. **Decompression** - Mental shift from combat mode to social mode

### Corridor Specifications

| Property | Value | Notes |
|----------|-------|-------|
| Length | ~2000px | 10-15 second walk at normal speed |
| Width | 300px | Room for 2-3 players side by side |
| Height (visual) | 400px | Feels enclosed but not claustrophobic |
| Lighting | Sparse torches every 300px | Pools of light in darkness |
| Ambient audio | Dripping water, distant echoes | Build atmosphere |

### Corridor Layout

```
    ZONE 1 ENTRY (South)
           │
           ▼
    ╔══════════════╗
    ║   ENTRANCE   ║  ← Stone archway, torches flanking
    ║              ║
    ╠══════════════╣
    ║              ║
    ║    ░    ░    ║  ← Torch (░) every 300px
    ║              ║
    ║              ║
    ║    ░    ░    ║
    ║              ║
    ║   ~puddle~   ║  ← Water puddles, dripping sounds
    ║              ║
    ║    ░    ░    ║
    ║              ║
    ║              ║
    ║    ░    ░    ║
    ║              ║
    ║   ~puddle~   ║
    ║              ║
    ║    ░    ░    ║
    ║              ║
    ╠══════════════╣
    ║    EXIT      ║  ← Opens into hub, light spills in
    ╚══════════════╝
           │
           ▼
    TRADING HUB (North)
```

### Corridor Instancing

The corridor exists in a liminal state:

```
OPTION A: Shared Corridors (Recommended)
─────────────────────────────────────────
- Corridor is part of hub scene
- Players see each other in corridors
- Creates "arrival" social moment
- Single scene to manage

OPTION B: Instanced Corridors
─────────────────────────────────────────
- Each player gets private corridor
- Lonely, misses social opportunity
- More complex scene management
- Only useful if load times are long

DECISION: Option A - Corridors are part of the hub scene
```

---

## Trading Hub Layout

### Overview

The hub is a large underground cavern with a central trading floor, side alcoves for private negotiations, and amenities along the walls.

### Dimensions

| Property | Value | Notes |
|----------|-------|-------|
| Total width | 3000px | Wide enough for 100 players |
| Total height | 2500px | North-south dimension |
| Central plaza | 2000px × 1500px | Main trading area |
| Alcove size | 400px × 400px | 4 alcoves, 2 per side |

### Detailed Layout

```
═══════════════════════════════════════════════════════════════════════════
                              NORTH (to Zone 2)
═══════════════════════════════════════════════════════════════════════════
                                    │
                    ┌───────────────┴───────────────┐
                    │         EXIT PORTAL           │
                    │    "The Passage North"        │
                    │   (System assigns Zone 2      │
                    │    chunk on entry)            │
                    └───────────────┬───────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    │                               │                               │
    │  ┌─────────────┐              │              ┌─────────────┐  │
    │  │             │              │              │             │  │
    │  │   STASH     │              │              │   TUNNEL    │  │
    │  │   ACCESS    │              │              │   TRADER    │  │
    │  │             │              │              │  (Vendor)   │  │
    │  │   [Chest]   │              │              │   [NPC]     │  │
    │  │             │              │              │             │  │
    │  └─────────────┘              │              └─────────────┘  │
    │                               │                               │
    │         ┌─────────────────────┴─────────────────────┐         │
    │         │                                           │         │
    │ ┌─────┐ │                                           │ ┌─────┐ │
    │ │     │ │          CENTRAL TRADING FLOOR            │ │     │ │
    │ │ A   │ │                                           │ │ A   │ │
    │ │ L   │ │    [Table]    ░ Torch     [Table]         │ │ L   │ │
    │ │ C   │ │                                           │ │ C   │ │
    │ │ O   │ │                                           │ │ O   │ │
    │ │ V   │ │  [Bench]    ╔═══════╗    [Bench]          │ │ V   │ │
    │ │ E   │ │             ║ FIRE  ║                     │ │ E   │ │
    │ │     │ │             ║  PIT  ║                     │ │     │ │
    │ │ 1   │ │             ╚═══════╝                     │ │ 2   │ │
    │ │     │ │                                           │ │     │ │
    │ │     │ │    [Table]    ░ Torch     [Table]         │ │     │ │
    │ └─────┘ │                                           │ └─────┘ │
    │         │                                           │         │
    │         └─────────────────────┬─────────────────────┘         │
    │                               │                               │
    │ ┌─────┐                       │                       ┌─────┐ │
    │ │     │                       │                       │     │ │
    │ │ A   │     ~water puddle~    │    ~water puddle~     │ A   │ │
    │ │ L   │                       │                       │ L   │ │
    │ │ C   │                       │                       │ C   │ │
    │ │ O   │                       │                       │ O   │ │
    │ │ V   │                       │                       │ V   │ │
    │ │ E   │                       │                       │ E   │ │
    │ │     │                       │                       │     │ │
    │ │ 3   │                       │                       │ 4   │ │
    │ │     │                       │                       │     │ │
    │ └─────┘                       │                       └─────┘ │
    │                               │                               │
    │         ┌─────────────────────┴─────────────────────┐         │
    │         │              CORRIDOR AREA                │         │
    │         │                                           │         │
    │         │   [Entry]    [Entry]    [Entry]           │         │
    │         │   Chunk-1    Chunk 0    Chunk+1           │         │
    │         │                                           │         │
    │         │   (More entries appear as Zone 1 scales)  │         │
    │         │                                           │         │
    │         └───────────────────────────────────────────┘         │
    │                                                               │
    └───────────────────────────────────────────────────────────────┘
                                    │
═══════════════════════════════════════════════════════════════════════════
                              SOUTH (from Zone 1)
═══════════════════════════════════════════════════════════════════════════
```

### Props & Furniture

| Prop | Count | Purpose |
|------|-------|---------|
| Fire pit | 1 (center) | Warmth, light, gathering point |
| Torches (wall) | 16 | Ambient lighting |
| Torches (floor) | 8 | Trading floor lighting |
| Tables | 8 | Trading surface, item display |
| Benches | 6 | Seating, idle players |
| Water puddles | 6 | Atmosphere, reflects light |
| Stalactites | ~20 | Ceiling decoration |
| Stone pillars | 4 | Structural, define spaces |
| Crates/barrels | 8 | Near vendor, storage feel |

### Alcove Design

Alcoves provide semi-private spaces for negotiations:

```
┌─────────────────────┐
│      ALCOVE         │
│                     │
│  ┌─────┐  ┌─────┐   │
│  │Bench│  │Bench│   │   ← Facing benches
│  └─────┘  └─────┘   │
│                     │
│     [Small Table]   │   ← Trade surface
│                     │
│        ░            │   ← Single torch
│      Torch          │
│                     │
│   ════════════      │   ← Partial wall, not enclosed
└───────┘    └────────┘     (Can see in/out)
        ENTRY
```

---

## Shard System

### Why Sharding?

Without sharding, a successful trading hub becomes unusable:
- **100 players**: Busy but manageable
- **500 players**: Laggy, hard to find anyone
- **1000+ players**: Unplayable, crashes

Sharding creates parallel instances of the same space, each with comfortable capacity.

### Shard Specifications

| Property | Value | Notes |
|----------|-------|-------|
| Soft cap | 100 players | Comfortable density |
| Hard cap | 150 players | Maximum before refusing entry |
| Minimum shards | 1 | Always at least one shard |
| Maximum shards | Dynamic | Created/destroyed on demand |
| Shard lifetime | Until empty for 5 min | Persists while occupied |

### Shard Assignment Algorithm

```gdscript
func assign_player_to_shard(player: Player) -> HubShard:
    # Priority 1: Same shard as party members
    if player.party:
        var party_shard = get_party_shard(player.party)
        if party_shard and party_shard.population < HARD_CAP:
            return party_shard

    # Priority 2: Same shard as friends (if any online in hub)
    var friend_shards = get_friend_shards(player)
    for shard in friend_shards:
        if shard.population < HARD_CAP:
            return shard

    # Priority 3: Lowest population shard under soft cap
    var available_shards = get_shards_under_soft_cap()
    if available_shards.size() > 0:
        available_shards.sort_custom(func(a, b): return a.population < b.population)
        return available_shards[0]

    # Priority 4: Any shard under hard cap
    var any_shard = get_shards_under_hard_cap()
    if any_shard.size() > 0:
        return any_shard[0]

    # Priority 5: Create new shard
    return create_new_shard()
```

### Shard Switching UI

Players can manually switch shards to find specific traders:

```
╔═══════════════════════════════════════════════════════════════════╗
║                        TRADING HUB SHARDS                         ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  You are in: Hub-A                                                ║
║                                                                   ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │                                                             │  ║
║  │  Hub-A    ████████████████░░░░░░░░░░░░░░  47/100   [HERE]   │  ║
║  │                                                             │  ║
║  │  Hub-B    ██████████████████████████████  89/100   [JOIN]   │  ║
║  │                                                             │  ║
║  │  Hub-C    ████████░░░░░░░░░░░░░░░░░░░░░░  23/100   [JOIN]   │  ║
║  │                                                             │  ║
║  │  Hub-D    ██████████████████████████░░░░  78/100   [JOIN]   │  ║
║  │                                                             │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                   ║
║  ┌─────────────────────────────────────────────────────────────┐  ║
║  │  Can't find what you're looking for?                        │  ║
║  │  Check another shard for more traders.                      │  ║
║  └─────────────────────────────────────────────────────────────┘  ║
║                                                                   ║
║                                              [Close]              ║
╚═══════════════════════════════════════════════════════════════════╝
```

### Shard Switching Rules

| Rule | Value | Reason |
|------|-------|--------|
| Cooldown | 30 seconds | Prevent rapid hopping |
| In-trade block | Cannot switch during active trade | Prevent scams |
| Party sync | Prompt to bring party | Keep groups together |
| Queue if full | Wait up to 60s for space | Don't reject outright |

---

## Zone 2 Exit System

### Design Intent

Unlike the entry (player chooses), the exit to Zone 2 is **system-assigned**. This allows:
1. Load balancing across Zone 2 chunks
2. Dynamic scaling (spawn new chunks when needed)
3. No "ghost town" chunks while others overflow

### Exit Portal

Single exit portal at the north end of the hub:

```
        ┌─────────────────────────────────────┐
        │                                     │
        │         ╔═══════════════╗           │
        │         ║               ║           │
        │         ║   EXIT TO     ║           │
        │         ║   ZONE 2      ║           │
        │         ║               ║           │
        │         ║   [Enter]     ║           │
        │         ║               ║           │
        │         ╚═══════════════╝           │
        │                                     │
        │    "The Passage North awaits..."    │
        │                                     │
        └─────────────────────────────────────┘
```

### Exit Assignment Algorithm

```gdscript
func assign_zone2_destination(player: Player) -> ChunkDestination:
    var zone2_state = Zone2Manager.get_state()

    # Origin chunks always exist: -1, 0, +1
    var origin_chunks = [-1, 0, 1]

    # Step 1: Try origin chunks (prefer balanced distribution)
    var origin_pops = {}
    for chunk_id in origin_chunks:
        origin_pops[chunk_id] = zone2_state.get_population(chunk_id)

    # Find lowest population origin chunk
    var sorted_origins = origin_chunks.duplicate()
    sorted_origins.sort_custom(func(a, b): return origin_pops[a] < origin_pops[b])

    for chunk_id in sorted_origins:
        if origin_pops[chunk_id] < CHUNK_SOFT_CAP:
            return ChunkDestination.new(chunk_id, false)

    # Step 2: All origins at soft cap, try existing edge chunks
    var edge_chunks = zone2_state.get_edge_chunks()  # [-2, +2, -3, +3, etc.]

    for chunk_id in edge_chunks:
        if zone2_state.get_population(chunk_id) < CHUNK_SOFT_CAP:
            return ChunkDestination.new(chunk_id, false)

    # Step 3: All chunks at soft cap, spawn new edge chunk
    var new_chunk_id = zone2_state.get_next_edge_chunk_id()
    return ChunkDestination.new(new_chunk_id, true)  # true = newly created


class ChunkDestination:
    var chunk_id: int
    var is_new_chunk: bool
    var spawn_position: Vector2

    func _init(id: int, is_new: bool):
        chunk_id = id
        is_new_chunk = is_new
        spawn_position = calculate_spawn_point(chunk_id)
```

### Zone 2 Spawn Points

Each Zone 2 chunk has a spawn point near its south edge (closest to hub):

```
ZONE 2 CHUNK LAYOUT:
                        NORTH (higher level enemies)
    ┌───────────────────────────────────────────────┐
    │                                               │
    │                    Lv 15-20                   │
    │                                               │
    │                                               │
    │                    Lv 12-15                   │
    │                                               │
    │                                               │
    │                    Lv 10-12                   │
    │                                               │
    │   ╔═══════════════════════════════════════╗   │
    │   ║         SPAWN AREA (Safe Zone)        ║   │
    │   ║                                       ║   │
    │   ║   Players appear here from hub        ║   │
    │   ║   600px safe radius, no enemies       ║   │
    │   ╚═══════════════════════════════════════╝   │
    └───────────────────────────────────────────────┘
                        SOUTH (from hub)
```

---

## Hub Features & Amenities

### 1. Stash Access

Players can access their personal stash (shared storage) in the hub:

```
┌─────────────────────────────────────────┐
│              STASH ACCESS               │
├─────────────────────────────────────────┤
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  [Copper Ore] x45              │    │
│  │  [Iron Ingot] x12              │    │
│  │  [Leather Scraps] x89          │    │
│  │  [Bone Fragments] x234         │    │
│  │  [Health Potion] x8            │    │
│  │  ...                           │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Capacity: 127 / 200 slots              │
│                                         │
│  [Deposit]  [Withdraw]  [Close]         │
│                                         │
└─────────────────────────────────────────┘
```

**Stash rules in hub:**
- Full access to deposit/withdraw
- Cannot trade directly from stash (must withdraw first)
- Stash is account-wide (all characters share)

### 2. Tunnel Trader (Vendor NPC)

A vendor unique to the hub, offering:

```
╔═══════════════════════════════════════════════════════════════════╗
║                        TUNNEL TRADER                              ║
║              "Goods from both sides of the passage..."            ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  CONSUMABLES                                                      ║
║  ├─ [Torch]               25g    Light in dark places             ║
║  ├─ [Health Potion]       50g    Restore 100 HP                   ║
║  ├─ [Stamina Elixir]      40g    +20% move speed, 60s             ║
║  └─ [Antidote]            35g    Cure poison (Zone 2)             ║
║                                                                   ║
║  ZONE 2 PREPARATION                                               ║
║  ├─ [Warmth Potion]       75g    Resist cold damage, 5 min        ║
║  ├─ [Cave Moss Salve]    100g    Slow health regen for 10 min     ║
║  └─ [Echo Stone]         150g    Reveal nearby enemies, 30s       ║
║                                                                   ║
║  TRADE UTILITIES                                                  ║
║  ├─ [Trade Ledger]       200g    View your trade history          ║
║  └─ [Merchant's Seal]    500g    +5% sell prices for 1 hour       ║
║                                                                   ║
║                                              [Close]              ║
╚═══════════════════════════════════════════════════════════════════╝
```

**Vendor backstory hook:**
- Referenced by the Zone 1 blacksmith in a quest
- "Seek the Tunnel Trader for supplies before venturing north"
- Creates breadcrumb to discover the hub

### 3. Fire Pit (Central)

The central fire pit serves multiple purposes:

| Function | Effect |
|----------|--------|
| Warmth aura | Players near fire have subtle warm glow |
| Gathering point | Natural center for socializing |
| Light source | Primary illumination for trading floor |
| Ambient sound | Crackling fire, comforting |

**Note:** Unlike the Zone 1 campfire, this fire does NOT heal. The hub is safe—healing is unnecessary.

### 4. Trade Advertisement Board (Future)

Placeholder for a bulletin board system:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRADE ADVERTISEMENTS                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [WTS] Copper Plate Helm +2 - 500g - PlayerOne (Hub-A)          │
│  [WTB] Iron Ore x50 - paying 200g - TradeMaster (Hub-B)         │
│  [WTS] Forged Ember Blade - 2000g - LegendarySmith (Hub-A)      │
│  [WTB] Leather Scraps x100 - 150g - CrafterGuy (Hub-C)          │
│  ...                                                            │
│                                                                 │
│  [Post Advertisement]  [Search]  [Close]                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Implementation**: Future feature, not MVP.

---

## Atmosphere & Aesthetics

### Visual Theme: Underground Cavern

The hub should feel like a natural cave system that's been minimally adapted for human use:

| Element | Description |
|---------|-------------|
| Walls | Rough stone, dark gray/brown, wet sheen |
| Floor | Uneven stone, darker where wet |
| Ceiling | High (400px+), stalactites, lost in shadow |
| Lighting | Sparse torches, fire pit glow, no sunlight |
| Water | Puddles, dripping from ceiling, reflects light |
| Props | Crude wooden tables/benches, crates, barrels |

### Color Palette

```
PRIMARY COLORS:
┌────────────────────────────────────────────┐
│  #2D2A26  Dark stone (walls, floor)        │
│  #1A1816  Deep shadow (corners, ceiling)   │
│  #4A433C  Wet stone (puddle edges)         │
│  #8B7355  Torch light warm zones           │
│  #D4A574  Fire pit glow                    │
└────────────────────────────────────────────┘

ACCENT COLORS:
┌────────────────────────────────────────────┐
│  #3D5C5C  Puddle water (teal reflection)   │
│  #6B4423  Wood (tables, benches)           │
│  #8B4513  Torch flame orange               │
│  #FFD700  Fire pit flame yellow            │
└────────────────────────────────────────────┘
```

### Lighting Design

```
LIGHTING ZONES:

    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    ← Dim (ambient only)
    ░░░░░░░░░░████████████░░░░░░░░░░░░░░░░
    ░░░░░░░███            ███░░░░░░░░░░░░░    ← Torch pools
    ░░░░░██                  ██░░░░░░░░░░░
    ░░░░█    ████████████      █░░░░░░░░░░
    ░░░█   ██            ██     █░░░░░░░░░    ← Fire pit glow
    ░░░█  █                █    █░░░░░░░░░       (brightest)
    ░░░█   ██            ██     █░░░░░░░░░
    ░░░░█    ████████████      █░░░░░░░░░░
    ░░░░░██                  ██░░░░░░░░░░░
    ░░░░░░░███            ███░░░░░░░░░░░░░
    ░░░░░░░░░░████████████░░░░░░░░░░░░░░░░
    ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

### Audio Design

| Sound | Type | Notes |
|-------|------|-------|
| Dripping water | Ambient loop | Random intervals, echo |
| Fire crackle | Ambient loop | Central pit, warm |
| Footsteps | Player action | Stone echo |
| Distant voices | Ambient loop | Murmur of traders |
| Torch flicker | Ambient spot | Near torches |
| Metal clink | Ambient rare | Coins, trade sounds |

### Ambient Effects

1. **Fog/mist** - Low-lying, near puddles
2. **Dust particles** - Float in torch light
3. **Water drips** - Particle effect from ceiling
4. **Torch flicker** - Light intensity variation
5. **Breath vapor** - Player exhale (cold cave)

---

## Technical Implementation

### Scene Structure

```
trading_hub/
├── TradingHub.tscn              # Main hub scene (instanced per shard)
│   ├── Environment/
│   │   ├── Walls                # TileMap or StaticBody2D
│   │   ├── Floor                # TileMap
│   │   ├── Ceiling              # Parallax or static
│   │   └── Props/
│   │       ├── Tables
│   │       ├── Benches
│   │       ├── Puddles
│   │       └── Stalactites
│   │
│   ├── Lighting/
│   │   ├── FirePit              # PointLight2D, animated
│   │   ├── Torches[]            # PointLight2D array
│   │   └── AmbientLight         # CanvasModulate
│   │
│   ├── Interactables/
│   │   ├── StashAccess          # Area2D + UI trigger
│   │   ├── TunnelTrader         # NPC + shop UI
│   │   └── ExitPortal           # Area2D + transition
│   │
│   ├── SpawnPoints/
│   │   ├── EntryPoints[]        # Where players arrive from Zone 1
│   │   └── ExitPoint            # Where players go to Zone 2
│   │
│   ├── Audio/
│   │   ├── AmbientPlayer        # AudioStreamPlayer (loop)
│   │   ├── FireAudio            # AudioStreamPlayer2D
│   │   └── DripsAudio[]         # AudioStreamPlayer2D array
│   │
│   └── UI/
│       ├── ShardSwitcher        # CanvasLayer UI
│       └── AFKWarning           # CanvasLayer UI

├── TunnelCorridor.tscn          # Corridor section (part of hub scene)
│   ├── Walls
│   ├── Floor
│   ├── Torches[]
│   └── Puddles[]

└── TunnelEntrance.tscn          # Placed in Zone 1 chunks
    ├── Archway                  # Visual
    ├── TriggerZone              # Area2D
    └── BlockerForLowLevel       # Collision (level < 10)
```

### Script Structure

```
scripts/
├── systems/
│   ├── TradingHubManager.gd     # Shard management, player routing
│   ├── TradingHubShard.gd       # Individual shard state
│   └── Zone2ExitManager.gd      # Zone 2 chunk assignment
│
├── world/
│   ├── TunnelEntrance.gd        # Zone 1 entry point logic
│   ├── TradingHubScene.gd       # Hub scene controller
│   └── TunnelCorridor.gd        # Corridor ambiance
│
├── npcs/
│   └── TunnelTrader.gd          # Vendor NPC logic
│
├── ui/
│   ├── ShardSwitcherUI.gd       # Shard selection interface
│   ├── AFKWarningUI.gd          # AFK timeout warning
│   └── TunnelTraderShopUI.gd    # Vendor shop interface
│
└── networking/
    └── HubNetworkManager.gd     # Hub-specific networking
```

### Manager Classes

#### TradingHubManager (Autoload)

```gdscript
# scripts/systems/TradingHubManager.gd
extends Node

signal player_entered_hub(player_id: int, shard_id: String)
signal player_exited_hub(player_id: int, destination: String)
signal shard_created(shard_id: String)
signal shard_destroyed(shard_id: String)

const SOFT_CAP: int = 100
const HARD_CAP: int = 150
const AFK_WARNING_TIME: float = 480.0  # 8 minutes
const AFK_KICK_TIME: float = 600.0     # 10 minutes
const SHARD_EMPTY_TIMEOUT: float = 300.0  # 5 minutes

var active_shards: Dictionary = {}  # shard_id -> TradingHubShard
var player_shards: Dictionary = {}  # player_id -> shard_id
var player_afk_timers: Dictionary = {}  # player_id -> float

func request_hub_entry(player: Player, origin_chunk: int) -> String:
    """Request entry to hub, returns assigned shard_id"""
    var shard = _assign_shard(player)
    _register_player_in_shard(player, shard)
    player_entered_hub.emit(player.peer_id, shard.shard_id)
    return shard.shard_id

func request_hub_exit_south(player: Player) -> int:
    """Exit to Zone 1, returns origin chunk_id"""
    var origin = _get_player_origin(player)
    _unregister_player(player)
    player_exited_hub.emit(player.peer_id, "zone1")
    return origin

func request_hub_exit_north(player: Player) -> ChunkDestination:
    """Exit to Zone 2, returns assigned chunk"""
    var destination = Zone2ExitManager.assign_destination(player)
    _unregister_player(player)
    player_exited_hub.emit(player.peer_id, "zone2")
    return destination

func request_shard_switch(player: Player, target_shard_id: String) -> bool:
    """Switch player to different shard, returns success"""
    # ... implementation
    pass

func _assign_shard(player: Player) -> TradingHubShard:
    # ... shard assignment algorithm from earlier
    pass
```

#### TradingHubShard

```gdscript
# scripts/systems/TradingHubShard.gd
extends RefCounted

var shard_id: String
var population: int = 0
var players: Dictionary = {}  # player_id -> PlayerHubState
var created_at: float
var last_activity: float

class PlayerHubState:
    var player_id: int
    var origin_chunk: int
    var entered_at: float
    var last_input: float
    var position: Vector2

func add_player(player: Player, origin: int) -> void:
    var state = PlayerHubState.new()
    state.player_id = player.peer_id
    state.origin_chunk = origin
    state.entered_at = Time.get_unix_time_from_system()
    state.last_input = state.entered_at
    state.position = _get_entry_spawn_point()

    players[player.peer_id] = state
    population += 1
    last_activity = state.entered_at

func remove_player(player_id: int) -> void:
    if players.has(player_id):
        players.erase(player_id)
        population -= 1
        last_activity = Time.get_unix_time_from_system()

func is_under_soft_cap() -> bool:
    return population < TradingHubManager.SOFT_CAP

func is_under_hard_cap() -> bool:
    return population < TradingHubManager.HARD_CAP

func is_empty() -> bool:
    return population == 0
```

---

## Network Protocol

### New RPC Methods

#### Hub Entry/Exit

```gdscript
# Client -> Server: Request hub entry
@rpc("any_peer", "call_remote", "reliable")
func request_enter_trading_hub(origin_chunk: int):
    var peer_id = multiplayer.get_remote_sender_id()
    var player = get_player(peer_id)

    # Validate level requirement
    if player.level < 10:
        rpc_id(peer_id, "hub_entry_denied", "Level 10 required")
        return

    # Assign shard
    var shard_id = TradingHubManager.request_hub_entry(player, origin_chunk)

    # Notify client to load hub scene
    rpc_id(peer_id, "hub_entry_approved", shard_id)

# Server -> Client: Entry approved
@rpc("authority", "call_remote", "reliable")
func hub_entry_approved(shard_id: String):
    # Client loads hub scene, connects to shard
    _transition_to_hub(shard_id)

# Server -> Client: Entry denied
@rpc("authority", "call_remote", "reliable")
func hub_entry_denied(reason: String):
    # Client shows denial message
    _show_denial_message(reason)
```

#### Shard Management

```gdscript
# Client -> Server: Request shard list
@rpc("any_peer", "call_remote", "reliable")
func request_shard_list():
    var peer_id = multiplayer.get_remote_sender_id()
    var shards = TradingHubManager.get_shard_summary()
    rpc_id(peer_id, "receive_shard_list", shards)

# Server -> Client: Shard list
@rpc("authority", "call_remote", "reliable")
func receive_shard_list(shards: Array):
    # shards = [{ "id": "Hub-A", "population": 47, "is_current": true }, ...]
    ShardSwitcherUI.update_list(shards)

# Client -> Server: Request shard switch
@rpc("any_peer", "call_remote", "reliable")
func request_shard_switch(target_shard_id: String):
    var peer_id = multiplayer.get_remote_sender_id()
    var success = TradingHubManager.request_shard_switch(get_player(peer_id), target_shard_id)

    if success:
        rpc_id(peer_id, "shard_switch_approved", target_shard_id)
    else:
        rpc_id(peer_id, "shard_switch_denied", "Shard is full or on cooldown")
```

#### Zone 2 Exit

```gdscript
# Client -> Server: Request Zone 2 exit
@rpc("any_peer", "call_remote", "reliable")
func request_zone2_exit():
    var peer_id = multiplayer.get_remote_sender_id()
    var player = get_player(peer_id)

    var destination = TradingHubManager.request_hub_exit_north(player)

    rpc_id(peer_id, "zone2_exit_approved", {
        "chunk_id": destination.chunk_id,
        "spawn_position": destination.spawn_position,
        "is_new_chunk": destination.is_new_chunk
    })

# Server -> Client: Zone 2 approved
@rpc("authority", "call_remote", "reliable")
func zone2_exit_approved(destination: Dictionary):
    _transition_to_zone2(destination)
```

#### AFK Management

```gdscript
# Server -> Client: AFK warning
@rpc("authority", "call_remote", "reliable")
func afk_warning(seconds_remaining: float):
    AFKWarningUI.show(seconds_remaining)

# Server -> Client: AFK kick
@rpc("authority", "call_remote", "reliable")
func afk_kicked():
    _transition_to_zone1_campfire()
    _show_message("Returned to campfire - idle too long")

# Client -> Server: Activity ping (automatic on input)
@rpc("any_peer", "call_remote", "unreliable")
func hub_activity_ping():
    var peer_id = multiplayer.get_remote_sender_id()
    TradingHubManager.reset_afk_timer(peer_id)
```

---

## Integration Points

### With Existing Systems

| System | Integration |
|--------|-------------|
| **ChunkBasedPropSystem** | Tunnel entrances added to chunk north edges |
| **ChunkAwareSpawnManager** | No enemies spawn in tunnel entrance area |
| **NetworkEnemyManager** | Hub is enemy-free, no sync needed |
| **AshbaneAuth** | Stash access requires authentication |
| **InventorySystem** | Stash deposit/withdraw |
| **TradingSystem** | All trading UI/logic works in hub |
| **PlayerDatabase** | Track hub visit stats (optional) |

### New Constants (constants.gd)

```gdscript
# Trading Hub
const HUB_LEVEL_REQUIREMENT: int = 10
const HUB_SHARD_SOFT_CAP: int = 100
const HUB_SHARD_HARD_CAP: int = 150
const HUB_AFK_WARNING_SECONDS: float = 480.0
const HUB_AFK_KICK_SECONDS: float = 600.0
const HUB_SHARD_SWITCH_COOLDOWN: float = 30.0

# Zone 2
const ZONE2_ORIGIN_CHUNKS: Array = [-1, 0, 1]
const ZONE2_CHUNK_SOFT_CAP: int = 50  # Players per chunk
```

### Tunnel Entrance Placement (game_world.gd)

```gdscript
func _spawn_tunnel_entrances():
    var active_chunks = ChunkManager.get_active_chunks()

    for chunk_id in active_chunks:
        var entry_x = chunk_id * CHUNK_SIZE + CHUNK_SIZE / 2
        var entry_y = WORLD_NORTH_BOUNDARY  # -4000

        var entrance = preload("res://scenes/world/TunnelEntrance.tscn").instantiate()
        entrance.position = Vector2(entry_x, entry_y)
        entrance.chunk_id = chunk_id
        add_child(entrance)

        _tunnel_entrances[chunk_id] = entrance

func _on_chunk_activated(chunk_id: int):
    if not _tunnel_entrances.has(chunk_id):
        _spawn_tunnel_entrance_for_chunk(chunk_id)

func _on_chunk_deactivated(chunk_id: int):
    if _tunnel_entrances.has(chunk_id):
        _tunnel_entrances[chunk_id].queue_free()
        _tunnel_entrances.erase(chunk_id)
```

---

## Scene & Script Structure

### Implemented Files (Phase 1)

```
scenes/trading_hub/
├── TunnelEntrance.tscn          # ✅ Entry point (stone archway + torches)
└── TradingHub.tscn              # ✅ Main hub scene (all-in-one)

scripts/trading_hub/
├── TunnelEntrance.gd            # ✅ Entry trigger, level gate, transition
├── TradingHub.gd                # ✅ Hub controller, player spawn, exits
└── TradingHubManager.gd         # ✅ Autoload - state tracking

scripts/game_world.gd            # ✅ Modified - spawn_tunnel_entrances()
project.godot                    # ✅ Modified - TradingHubManager autoload
```

### Planned Files (Phase 2+)

```
scenes/
├── trading_hub/
│   ├── TradingHubEnvironment.tscn  # Tilemap/walls subscene
│   ├── TradingHubLighting.tscn     # Lights subscene
│   └── TradingHubProps.tscn        # Furniture subscene
│
├── npcs/
│   └── TunnelTrader.tscn           # Vendor NPC
│
└── ui/
    ├── ShardSwitcher.tscn          # Shard selection UI
    ├── AFKWarning.tscn             # AFK timeout warning
    └── TunnelTraderShop.tscn       # Vendor shop UI

scripts/
├── trading_hub/
│   ├── TradingHubShard.gd          # Shard state class
│   ├── Zone2ExitManager.gd         # Zone 2 assignment
│   ├── HubExitPortal.gd            # Zone 2 exit trigger
│   └── HubFirePit.gd               # Central fire effects
│
├── npcs/
│   └── TunnelTrader.gd             # Vendor logic
│
├── ui/
│   ├── ShardSwitcherUI.gd          # Shard UI logic
│   ├── AFKWarningUI.gd             # AFK warning logic
│   └── TunnelTraderShopUI.gd       # Shop UI logic
│
└── networking/
    └── HubNetworkManager.gd        # Hub networking additions
```

### Autoload Registration (project.godot)

```ini
[autoload]
# ... existing autoloads ...
TradingHubManager="*res://scripts/trading_hub/TradingHubManager.gd"
```

---

## Future Considerations

### Phase 2 Enhancements

1. **Trade Advertisement Board**
   - Post WTS/WTB listings
   - Cross-shard visibility
   - Expiration timer

2. **Trade History**
   - View past trades
   - Price tracking
   - Reputation building

3. **Auction System**
   - Timed auctions
   - Buyout option
   - Notification on outbid

### Phase 3 Enhancements

1. **Guild Stalls**
   - Guilds rent permanent spots
   - Branded stall appearance
   - Guild bank integration

2. **Trading Achievements**
   - "First Trade"
   - "100 Trades Completed"
   - "Million Gold Traded"

3. **Seasonal Events**
   - Holiday decorations
   - Special vendor items
   - Trading contests

### Zone 2 Specifics (Separate Doc)

The Zone 2 design (The Depths?) deserves its own specification:
- Biome/theme
- Enemy types (levels 10-20)
- New mechanics (cold damage? darkness?)
- POI generation
- Boss encounters

---

## Appendix A: EC Tunnel Reference

For historical context, EverQuest's East Commonlands tunnel:

- **Location**: Between West Freeport and Oasis of Marr
- **Safety**: No roaming monsters inside tunnel
- **Size**: ~200 meter long narrow passage
- **Peak usage**: 1999-2001, before Bazaar zone added
- **Social dynamics**: Shouting sales, forming queues, trust-based trading

Key lessons:
1. Geography creates marketplaces, not features
2. Safety enables commerce
3. Passage traffic guarantees audience
4. Limited space creates density (social proof)

---

## Appendix B: Shard Naming Convention

Shards are named alphabetically for easy reference:

| Shard # | Name | Display |
|---------|------|---------|
| 1 | Hub-A | "Hub-A (47/100)" |
| 2 | Hub-B | "Hub-B (89/100)" |
| 3 | Hub-C | "Hub-C (23/100)" |
| ... | ... | ... |
| 26 | Hub-Z | "Hub-Z (12/100)" |
| 27 | Hub-AA | "Hub-AA (55/100)" |

If we ever need more than 26 shards, we've succeeded beyond expectations.

---

## Appendix C: AFK Detection

AFK is determined by lack of meaningful input:

| Input Type | Resets AFK Timer |
|------------|------------------|
| Movement (WASD) | Yes |
| Mouse movement | Yes |
| Chat message sent | Yes |
| Trade interaction | Yes |
| UI interaction | Yes |
| Inventory management | Yes |
| Just standing still | No |
| Camera pan only | No |

```gdscript
func _input(event: InputEvent):
    if _is_in_hub and _is_meaningful_input(event):
        TradingHubManager.reset_afk_timer(peer_id)

func _is_meaningful_input(event: InputEvent) -> bool:
    return event is InputEventKey or \
           event is InputEventMouseButton or \
           (event is InputEventMouseMotion and event.relative.length() > 5)
```

---

*Document version 1.0 - December 2024*
