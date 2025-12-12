# Chunk System & Enemy Spawning

The game uses a chunk-based system for props (trees, rocks, lava pools) and enemies, providing efficient memory usage and smooth performance by only loading content near the player.

---

## Table of Contents

1. [World Overview](#world-overview)
2. [Chunk Loading](#chunk-loading)
3. [Prop System](#prop-system)
4. [Enemy Spawn System](#enemy-spawn-system)
5. [Multiplayer](#multiplayer)
6. [Spawn Marker Tools (Editor)](#spawn-marker-tools-editor)
7. [Debug Display (F3)](#debug-display-f3)
8. [Performance](#performance)
9. [Future Vision: Dynamic Expansion](#future-vision-dynamic-expansion)
10. [Future Vision: Distributed Compute](#future-vision-distributed-compute)

---

## World Overview

The world is divided into **3 horizontal chunks** (vertical strips), each 8000px wide spanning the full 8000px world height.

```
World: -8000 to 16000 (24,000px wide) x -4000 to 4000 (8,000px tall)

   -8000         0         8000        16000
     |           |           |           |
     +-----------+-----------+-----------+
     |    -1     |     0     |     1     |  <- 8000px tall
     |           |  SPAWN    |           |     (full height)
     +-----------+-----------+-----------+
```

**Spawn point**: (4000, 0) = Center of Chunk **0**

---

## Chunk Loading

### Loading Rules
- **Current chunk**: Always loaded
- **Adjacent chunks**: Loaded when player is within 1000px of chunk edge
- **Distant chunks**: Unloaded when no longer current or adjacent

### Typical State
- **At spawn**: 1-2 chunks loaded
- **Walking around**: 1-3 chunks max loaded at any time
- **Memory efficient**: Only nearby content in memory

---

## Prop System

**File:** `scripts/systems/ChunkBasedPropSystem.gd`

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
- **Campfire area**: Props avoid 1050px radius around campfire at (4000, 0)

---

## Enemy Spawn System

**File:** `scripts/systems/ChunkAwareSpawnManager.gd`

Enemies spawn per-chunk, managed by the chunk system rather than player distance.

### How It Works
1. **When chunk loads**: Spawn enemies to fill target count
2. **When chunk unloads**: Despawn enemies (except corpses with loot)
3. **When enemies die**: System tops up to target count
4. **Respawn timer**: Dead enemies respawn after 90 seconds

### Configuration
```gdscript
const ENEMIES_PER_CHUNK: int = 120      # Target enemies per chunk
var CHUNK_SIZE: float:
    get: return Constants.CHUNK_SIZE    # 8000.0
@export var respawn_time: float = 90.0  # 90 seconds
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
- **Campfire**: 600px radius around (4000, 0)
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

---

## Multiplayer

Both systems support multiplayer with server-authoritative architecture.

### Chunk Loading in Multiplayer

**Server (Host):**
- Tracks ALL connected players' positions
- Loads chunks needed by ANY player (union of all player chunks)
- If host is in chunk 0 and client is in chunk 5, server loads both
- Uses `update_chunks_for_all_players()` to collect chunks for everyone

**Clients:**
- Load props locally for visual rendering (same chunk logic)
- Do NOT spawn enemies (receive them via RPC from server)
- Enemy AI is disabled on clients (positions come from server)

### Enemy Sync System

**Spawning (Server -> Clients):**
```
Server spawns enemy
  -> NetworkEnemyManager.register_enemy() assigns network_id
  -> spawn_enemy_on_clients.rpc() broadcasts to all clients
  -> Clients instantiate enemy with AI disabled
  -> Clients mark enemy as "network puppet"
```

**Position Sync (10Hz, Server -> Clients):**
```gdscript
# Server broadcasts every 100ms:
{
  network_id: {
    "pos": Vector2,        # Global position
    "anim": String,        # Current animation
    "health": float,       # Current HP
    "max_health": float,   # Max HP
    "in_crit_window": bool,# Crit window active
    "is_dying": bool       # Death state
  }
}
# Clients interpolate position (lerp 0.3)
```

**Damage System (Client -> Server -> All Clients):**
```
Player attacks enemy
  -> apply_damage_with_feedback() routes to network
  -> Client: request_damage.rpc_id(1, ...) to server
  -> Server validates (enemy alive, damage sane 0-10000)
  -> Server applies damage, tracks attacker for kill credit
  -> Server broadcasts _client_enemy_damaged to ALL clients
  -> All clients see: hit flash, combat text, health bar update
```

**Death & XP Attribution:**
```
Enemy health <= 0
  -> Server calls _handle_enemy_death(network_id, killer_peer_id)
  -> Server generates loot deterministically
  -> Server broadcasts _client_enemy_died with killer_id, loot
  -> Each client's enemy stores killer_peer_id in metadata
  -> Enemy.die() grants XP ONLY to player whose peer_id matches killer
```

### LOD (Level of Detail) in Multiplayer

LOD is calculated **per-client** based on local player distance:
- Each player sees enemies at their own appropriate LOD level
- Host in chunk 0 sees enemies there at full detail
- Client in chunk 5 sees their nearby enemies at full detail

```gdscript
# Enemy._process() on each client:
var distance = global_position.distance_to(local_player.global_position)
if distance < LOD_NEAR_DISTANCE:    # 1200px
    current_lod = 0  # Full detail
elif distance < LOD_FAR_DISTANCE:   # 2500px
    current_lod = 1  # Reduced (no shadow, slow anims)
else:
    current_lod = 2  # Minimal (paused anims)
```

### Key Networking Files

- `scripts/networking/NetworkEnemyManager.gd` - Enemy sync hub (autoload)
- `scripts/networking/NetworkPlayer.gd` - Player sync wrapper
- `scripts/systems/ChunkBasedPropSystem.gd` - Prop/chunk loading (multiplayer aware)
- `scripts/systems/ChunkAwareSpawnManager.gd` - Enemy spawning (server-only in MP)

---

## Spawn Marker Tools (Editor)

These tools help create and organize enemy spawn markers in the Godot editor.

### Using the ManualEnemySpawn Tool

1. **Open your game_world scene** in Godot editor
2. **Add a new Node** as a child of GameWorld:
   - Add a Marker2D and attach: `res://scripts/tools/manual_enemy_spawn.gd`
3. **Position the marker** where you want the enemy to spawn
   - You'll see a colored circle showing the spawn point
   - The outer ring shows the aggro radius
4. **Configure in Inspector**:
   - `Enemy Level`: Set the enemy level (1-50+)
   - `Aggro Range`: How close player must be to trigger aggro (default: 150px)
   - `Enemy Type`: Currently only "skeleton"
5. **Colors in Editor**:
   - Green = Level 1-3 (Noob area)
   - Yellow = Level 4-7 (Low level)
   - Orange = Level 8-12 (Mid level)
   - Red = Level 13-18 (High level)
   - Purple = Level 19+ (Boss level)

### Radial Ring Pattern Tool

Analyzes your manually placed Level 1-3 enemies and automatically generates Level 4-10 enemies following the same radial expansion pattern.

**How to use:**
1. Place Level 1, 2, and 3 enemies in expanding rings around campfire
2. Open script: `scripts/tools/extend_radial_pattern.gd`
3. Run it: File > Run (or Ctrl+Shift+X)
4. Review results in console

**What it does:**
- Measures ring radius, width, expansion rate, density from your pattern
- Generates L4-10 spawns following the same pattern
- Names them: `L4_Patrol_East_1`, `L5_Patrol_North_2`, etc.
- Avoids ruins areas (450px exclusion)

### Cleanup Tool

Organizes messy spawn markers with consistent naming.

**How to use:**
1. Open `scripts/tools/cleanup_spawns_editor.gd`
2. Run it: File > Run (or Ctrl+Shift+X)

**What it does:**
- Finds ALL spawn markers anywhere in scene tree
- Moves them under a `ManualEnemySpawns` node
- Renames them: `L1_Patrol_East_1`, `L2_Patrol_South_3`, etc.
- Applies ManualEnemySpawn script and proper metadata
- Sorts by level

### Pattern Extension Tool

Extends your spawn pattern by learning from existing placements.

**How to use:**
1. Open `scripts/tools/extend_spawn_pattern_editor.gd`
2. Adjust settings:
   ```gdscript
   const MULTIPLIER = 2.0  # 2.0 = double your spawns
   const SEED_VALUE = 12345  # Change for different patterns
   ```
3. Run it: File > Run (or Ctrl+Shift+X)

### Pattern Learning AI (Runtime)

The system learns from your manual enemy placements at runtime:

1. **Analysis Phase**: Measures level progression, spacing, distribution, density
2. **Generation Phase**: Generates 3x your manual count following learned pattern
3. **Exclusion Zones**: Avoids manual spawns (150px), ruins (450px)

Adjust density multiplier in `game_world.gd`:
```gdscript
var target_total = manual_count * 3  # Change 3 to 2, 4, 5, etc.
```

### Tool File Locations

- `scripts/tools/manual_enemy_spawn.gd` - Visual editor spawn tool
- `scripts/tools/cleanup_spawns_editor.gd` - Cleanup and organize tool
- `scripts/tools/extend_spawn_pattern_editor.gd` - Pattern extension tool
- `scripts/tools/extend_radial_pattern.gd` - Radial ring pattern generator

---

## Debug Display (F3)

Press F3 to see chunk and spawn info:

```
CHUNKS:
  Current: [0] X=4000
  West Edge: 4000px
  East Edge: 4000px
  Loaded: [-1, 0]

ENEMIES PER CHUNK:
  [-1]: 58/60
  [0]: 60/60
  Total: 118 enemies
```

---

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

---

## Future Vision: Dynamic Expansion

> **Status**: Design Document - Not Yet Implemented

### The Problems This Solves

1. **Login Queue Hell** - Traditional MMOs hit capacity limits
2. **Server Crash Cascade** - Everyone in same zones = lag
3. **Resource Starvation** - Fixed spawns + too many players = nothing to do
4. **Griefing** - Overcrowded areas breed toxicity

### The Solution: Population-Based Edge Expansion

The world dynamically grows and shrinks based on player density:

```
Low Population (5 players):
[-1][0][1]  <- 3 chunks, plenty of space

High Population (50 players, crowded center):
[-2][-1][0][1][2]  <- 5 chunks, world expanded

Players spread out, density drops:
[-1][0][1][2]  <- 4 chunks, western edge contracted
```

### How It Would Work

1. **Density Tracking**: Server tracks player count per chunk
2. **Expansion Trigger**: Edge chunk exceeds 80% density -> spawn new chunk
3. **Contraction Trigger**: Edge chunk empty for 5 min -> despawn
4. **Incentive to Spread**: Crowded = slower respawns, Edge = fresh spawns but harder

### Benefits
- **Infinite horizontal scaling** - World grows with population
- **Self-balancing** - Players naturally spread out
- **Resource efficiency** - Only load chunks that are needed
- **Progressive difficulty** - Further from spawn = higher level content
- **No login queues** - World always has room

---

## Future Vision: Distributed Compute

> **Status**: Design Document - Not Yet Implemented

A **server-authoritative distributed compute** model where the central server owns all game state, but player machines perform heavy simulation work (AI, physics, spawning) for nearby chunks.

### Core Principle

```
+-----------------------------------------------------------------------+
|                         CENTRAL SERVER                                 |
|                     (Authority - Single Source of Truth)               |
|                                                                        |
|  - All enemy positions, health, AI state                              |
|  - All player positions, inventory, stats                             |
|  - All loot, resources, world state                                   |
|  - Chunk existence (which chunks are active)                          |
|                                                                        |
|  WORKER MANAGEMENT:                                                    |
|  - Assigns chunks to nearby players                                   |
|  - Receives simulation reports from workers                           |
|  - Validates all reported state changes                               |
|  - Broadcasts validated state to all clients                          |
+-----------------------------------------------------------------------+
                               |
            +------------------+------------------+
            |                  |                  |
            v                  v                  v
   +----------------+ +----------------+ +----------------+
   |  PLAYER A      | |  PLAYER B      | |  PLAYER C      |
   |  (Worker)      | |  (Worker)      | |  (Worker)      |
   |                | |                | |                |
   |  Simulates:    | |  Simulates:    | |  Simulates:    |
   |  Chunk [0]     | |  Chunk [3]     | |  Chunk [6]     |
   |  Chunk [1]     | |  Chunk [4]     | |  Chunk [7]     |
   |                | |                | |                |
   |  NO AUTHORITY  | |  NO AUTHORITY  | |  NO AUTHORITY  |
   |  Just compute  | |  Just compute  | |  Just compute  |
   +----------------+ +----------------+ +----------------+
```

**Key differences from traditional "player hosting":**
- Players don't OWN chunks - they WORK on them
- Server validates EVERYTHING - workers can't cheat
- Workers are interchangeable - if one disconnects, another takes over
- All traffic goes through central server - no P2P needed

### Anti-Cheat Summary

| Threat | Prevention |
|--------|------------|
| Speed hack (enemies) | Server validates position delta vs max speed |
| Health hack | Server only allows health to decrease |
| Spawn hack | Server tracks expected enemy count per chunk |
| Loot hack | Server validates drops against enemy type/level |
| Damage hack | Damage RPCs go to server, not worker |

**Workers can't cheat because:**
1. They don't have authority - server validates everything
2. Player damage goes directly to server, bypassing worker
3. Loot is validated against expected drop tables
4. Suspicious patterns trigger reassignment + potential kick

### Cost Comparison

| Model | 50 Players | 200 Players | 1000 Players |
|-------|------------|-------------|--------------|
| **Traditional** | $25/mo | $100/mo | $500+/mo |
| **Distributed** | $10/mo | $20-30/mo | $50-80/mo |

### Summary

This architecture turns players into a distributed compute cluster:
1. **Server is authoritative** - No cheating possible
2. **Players do the heavy lifting** - AI, physics run on their machines
3. **Server just validates** - Lightweight, cheap to host
4. **Dynamic scaling** - More players = more chunks = more workers
5. **Self-healing** - Worker disconnects are handled seamlessly

---

## Key Files

- `scripts/systems/ChunkBasedPropSystem.gd` - Prop generation and chunk loading
- `scripts/systems/ChunkAwareSpawnManager.gd` - Enemy spawning per chunk
- `scripts/networking/NetworkEnemyManager.gd` - Enemy sync hub (autoload)
- `scripts/debug/PerformanceProfiler.gd` - F3 debug display
- `scripts/constants.gd` - CHUNK_SIZE, world bounds
- `scripts/tools/manual_enemy_spawn.gd` - Editor spawn tool
- `scripts/tools/extend_radial_pattern.gd` - Radial ring generator
- `scripts/tools/cleanup_spawns_editor.gd` - Spawn marker cleanup
- `scripts/tools/extend_spawn_pattern_editor.gd` - Pattern extension
