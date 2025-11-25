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
