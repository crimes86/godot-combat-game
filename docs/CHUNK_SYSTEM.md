# Chunk System

The game uses a chunk-based system for both props (trees, rocks, lava pools) and enemies. This provides efficient memory usage and smooth performance by only loading content near the player.

## Overview

The world is divided into **6 horizontal chunks** (vertical strips), each 3000px wide spanning the full 6000px world height.

```
World: -5000 to 13000 (18,000px wide) × -3000 to 3000 (6,000px tall)

   -5000    -2000     1000     4000     7000    10000    13000
     │        │        │        │        │        │        │
     ├────────┼────────┼────────┼────────┼────────┼────────┤
     │ -2,0   │ -1,0   │  0,0   │  1,0   │  2,0   │  3,0   │  <- 6000px tall
     │        │ SPAWN  │        │        │        │        │     (full height)
     ├────────┼────────┼────────┼────────┼────────┼────────┤
```

**Spawn point**: (-2000, 0) = Chunk **-1,0**

## Chunk Loading

### Loading Rules
- **Current chunk**: Always loaded
- **Adjacent chunks**: Loaded when player is within 1000px of chunk edge
- **Distant chunks**: Unloaded when no longer current or adjacent

### Typical State
- **At spawn**: 1-2 chunks loaded (chunk -1,0 + maybe 0,0 if near edge)
- **Walking around**: 1-3 chunks max loaded at any time
- **Memory efficient**: Only nearby content in memory

## Prop System (ChunkBasedPropSystem.gd)

Props are procedurally generated per chunk using deterministic seeding.

### Props Per Chunk
| Prop Type | Count | Notes |
|-----------|-------|-------|
| Trees | 158 | Lootable (wood) |
| Large Rocks | 36 | Lootable (stone/ore) |
| Medium Rocks | 45 | Decorative |
| Small Rocks | 32 | Decorative |
| Lava Pools | 9 | Visual + light effects |
| Bone Clusters | 5 | Decorative |
| Dead Vegetation | 14 | Decorative |
| Ground Cracks | 18 | Visual |
| **Total** | **~317** | Per chunk |

### Async Loading
Props generate in batches across multiple frames to prevent stuttering:
- **Priority chunks** (current): 30 props/frame
- **Background chunks** (adjacent): 15 props/frame

### Exclusion Zones
- **Lava pools**: Other props avoid spawning inside (radius + 30px buffer)
- **Large rocks**: Smaller rocks avoid spawning on top (60px radius)
- **Campfire area**: Props avoid 1050px radius around campfire at (-2000, 0)

## Enemy Spawn System (ChunkAwareSpawnManager.gd)

Enemies spawn per-chunk, managed by the chunk system rather than player distance.

### How It Works
1. **When chunk loads**: Spawn enemies to fill target count
2. **When chunk unloads**: Despawn enemies (except corpses with loot)
3. **When enemies die**: System tops up to target count
4. **Respawn timer**: Dead enemies respawn after 5 minutes

### Configuration
```gdscript
const ENEMIES_PER_CHUNK: int = 60     # Target enemies per chunk
const CHUNK_SIZE: float = 3000.0       # Must match prop system
@export var respawn_time: float = 300.0  # 5 minutes
```

### Spawn Priority
1. **Manual markers first**: Marker2D nodes with `enemy_level` metadata
2. **Procedural fills remaining**: Random positions within chunk bounds

### Level Bands
Enemy level is determined by X position:

| X Range | Level |
|---------|-------|
| -99999 to -2600 | 1 (far west) |
| -2600 to 400 | 1 (spawn area) |
| 400 to 700 | 2 |
| 700 to 1000 | 3 |
| 1000 to 1300 | 4 |
| 1300 to 1600 | 5 |
| 1600 to 1900 | 6 |
| 1900 to 2200 | 7 |
| 2200 to 2500 | 8 |
| 2500 to 2800 | 9 |
| 2800 to 99999 | 10 (far east) |

### Safe Zones (No Spawns)
- **Campfire**: 600px radius around (-2000, 0)
- **Ruins 1**: 350px radius around (2184, -1216)
- **Ruins 2**: 350px radius around (4368, 0)
- **Ruins 3**: 350px radius around (6552, 1216)

### Manual Spawn Markers
To place specific enemies in the editor:

1. Add a **Marker2D** as child of GameWorld
2. Name it `EnemySpawn_*` or `L#_*` (e.g., `EnemySpawn_L5_Boss`, `L3_Patrol_East`)
3. Set metadata:
   - `enemy_level` (int): Required - enemy level
   - `enemy_type` (String): Optional - defaults to "skeleton"
   - `aggro_range` (float): Optional - defaults to 150

Or use the `ManualEnemySpawn` tool script for visual editor support.

## Debug Display (F3)

Press F3 to see chunk and spawn info:

```
CHUNKS:
  Current: [-1,0] X=-2000
  West Edge: 1000px
  East Edge: 2000px
  Loaded: [-1,0, 0,0]

ENEMIES PER CHUNK:
  [-1,0]: 58/60
  [0,0]: 60/60
  Total: 118 enemies
```

## Performance

### Expected Node Counts
| State | Prop Nodes | Enemy Nodes | Total |
|-------|-----------|-------------|-------|
| 1 chunk | ~800 | ~100 | ~900 |
| 2 chunks | ~1600 | ~200 | ~1800 |
| 3 chunks | ~2400 | ~300 | ~2700 |

### FPS Targets
- **60 FPS**: Normal gameplay with 1-2 chunks
- **45-55 FPS**: Heavy combat or 3 chunks loaded
- **Below 45**: Check for other issues (particles, effects)

## Files

- `scripts/systems/ChunkBasedPropSystem.gd` - Prop generation and chunk loading
- `scripts/systems/ChunkAwareSpawnManager.gd` - Enemy spawning per chunk
- `scripts/debug/PerformanceProfiler.gd` - F3 debug display

## Multiplayer

Both systems support multiplayer:
- **Server**: Manages chunk loading for all players
- **Clients**: Receive enemy spawns via RPC
- **Chunks load**: When ANY player is nearby (not just host)

---

## Future Vision: Dynamic Chunk Expansion

### The Problems This Solves

**1. Login Queue Hell**
Traditional MMOs with fixed world size hit capacity limits:
- Server full → players stuck in queue for hours
- Peak times become unplayable
- Players quit out of frustration
- "Sorry, world is full" = lost players

**2. Server Crash Cascade**
When everyone crams into the same zones:
- Spawn areas become laggy death traps
- Server CPU spikes from entity density
- Physics calculations explode (N² collision checks)
- Server crashes → everyone disconnected → angry players

**3. Resource Starvation**
Fixed spawns + too many players = nothing to do:
- All enemies instantly killed, no respawns available
- Trees/rocks harvested faster than respawn
- Chests empty, no loot to find
- Players standing around waiting = boredom

**4. Griefing & Kill Stealing**
Overcrowded areas breed toxicity:
- High-level players camping low-level spawns
- Kill stealing becomes rampant
- New players can't progress
- Community becomes hostile

### The Solution: Population-Based Edge Expansion
The world dynamically grows and shrinks based on player density:

```
Low Population (5 players):
[-1,0][0,0][1,0]  ← 3 chunks, plenty of space

High Population (50 players, crowded center):
[-2,0][-1,0][0,0][1,0][2,0]  ← 5 chunks, world expanded

Players spread out, density drops:
[-1,0][0,0][1,0][2,0]  ← 4 chunks, western edge contracted
```

### How It Would Work

**1. Density Tracking**
- Server tracks player count per chunk
- Calculate density: `players_in_chunk / CHUNK_CAPACITY`
- Threshold example: 15 players per chunk = 100% density

**2. Expansion Trigger**
When an **edge chunk** exceeds density threshold (e.g., 80%):
- Generate new chunk beyond that edge
- New chunk has same props/enemies as existing chunks
- Enemy levels continue scaling outward (higher levels further from spawn)

```
[1,0] has 14/15 players (93% density)
→ Spawn [2,0] to the east
→ [2,0] has Level 6-8 enemies (harder than [1,0])
```

**3. Contraction Trigger**
When an **edge chunk** has zero players for X minutes:
- Despawn the edge chunk (unload from memory)
- World contracts back toward center
- Resources/enemies in that chunk are lost (respawn when chunk regenerates)

**4. Incentive to Spread Out**
- Crowded chunks = slower respawns, more competition
- Edge chunks = fresh spawns, less competition, but harder enemies
- Natural player distribution across the world

### How It Solves Each Problem

**Login Queues → Eliminated**
- World expands to fit demand
- No hard player cap needed
- 1000 players online? World grows to 50+ chunks
- Everyone gets in, no waiting

**Server Crashes → Prevented**
- Density thresholds prevent overcrowding
- Server load distributed across chunks
- Each chunk has manageable entity count
- Expansion triggers BEFORE server stress

**Resource Starvation → Impossible**
- New chunks = fresh spawns
- Overcrowded chunk triggers expansion
- Players migrate to new chunks for resources
- Respawn rates stay healthy

**Griefing → Naturally Discouraged**
- Edge chunks have harder enemies (level scaling)
- High-level players pushed to outer chunks
- New players have protected inner chunks
- Natural level segregation by distance from spawn

### Benefits
- **Infinite horizontal scaling** - World grows with population
- **Self-balancing** - Players naturally spread out
- **Resource efficiency** - Only load chunks that are needed
- **Progressive difficulty** - Further from spawn = higher level content
- **No login queues** - World always has room
- **Server stability** - Load distributed across chunks

### Technical Requirements
- Chunk coordinate system already supports infinite range (dictionary-based)
- Enemy level bands need to extend beyond current hardcoded values
- Server needs population tracking per chunk
- Expansion/contraction logic in ChunkAwareSpawnManager

### Not Yet Implemented
This is a **future vision** - current system uses fixed 6 chunks.
