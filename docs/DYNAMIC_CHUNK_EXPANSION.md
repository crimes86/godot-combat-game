# Dynamic Horizontal Chunk Expansion System

## Overview

The world starts with 3 **origin chunks** and expands/contracts dynamically based on player activity through a **seed plot** claiming system.

```
Initial World (3 chunks):
┌────────┬────────┬────────┐
│ Chunk  │ Chunk  │ Chunk  │
│  -1    │   0    │   1    │
│ (Edge) │(Origin)│ (Edge) │
│  🌱    │        │  🌱    │
└────────┴────────┴────────┘

After Both Seed Plots Claimed (5 chunks):
┌────────┬────────┬────────┬────────┬────────┐
│ Chunk  │ Chunk  │ Chunk  │ Chunk  │ Chunk  │
│  -2    │  -1    │   0    │   1    │   2    │
│ (Edge) │        │(Origin)│        │ (Edge) │
│  🌱    │        │        │        │  🌱    │
└────────┴────────┴────────┴────────┴────────┘
```

---

## Core Concepts

### Origin Chunks
- **Chunk 0**: Spawn area, campfire, always exists
- **Chunk -1**: West origin edge
- **Chunk 1**: East origin edge
- **Cannot be removed**: These 3 chunks are permanent

### Seed Plots
- **Location**: One per edge chunk (current edges: -1 and 1)
- **Purpose**: Claimable territory that allows world expansion
- **Requirement**: Both edge plots must be claimed to trigger expansion
- **Decay**: Unclaimed/abandoned plots trigger chunk removal

### Edge Chunks
- **Definition**: The leftmost and rightmost chunks in the current world
- **Dynamic**: Created when seed plots are claimed, removed when they decay
- **Infinite**: Can expand infinitely (limited by server capacity)

---

## Expansion Mechanics

### Trigger: Both Seed Plots Claimed

When both current edge chunks have claimed seed plots:
1. Generate new chunk on west side (chunk_id - 1)
2. Generate new chunk on east side (chunk_id + 1)
3. Spawn new seed plot on each new edge chunk
4. Update world boundaries
5. Broadcast expansion to all connected clients

**Example**:
```
Current State:
  Chunks: [-1, 0, 1]
  Seed Plots: [-1: claimed, 1: claimed]

Trigger Expansion:
  Add Chunk -2 (west)
  Add Chunk 2 (east)

New State:
  Chunks: [-2, -1, 0, 1, 2]
  Seed Plots: [-2: unclaimed, 2: unclaimed]
```

### Contraction: Seed Plot Decay

When a seed plot is abandoned/decayed:
1. Mark chunk for removal (grace period starts)
2. Warn players in that chunk
3. After grace period, despawn chunk
4. Teleport any remaining players to nearest safe chunk
5. Update world boundaries
6. Broadcast contraction to all clients

**Important**: Only the outermost edge chunks can be removed. Interior chunks are protected.

---

## Seed Plot System

### Claiming a Seed Plot

**Requirements**:
- Player must be at the seed plot location
- Player must meet claim cost (gold/resources)
- Seed plot must be unclaimed

**Claim Cost** (scales with distance from origin):
```gdscript
var distance_from_origin = abs(chunk_id)
var base_cost = 1000  # 1000 gold
var cost = base_cost * pow(2, distance_from_origin - 1)

# Chunk -1/+1: 1000 gold
# Chunk -2/+2: 2000 gold
# Chunk -3/+3: 4000 gold
# Chunk -4/+4: 8000 gold
```

**On Claim**:
- Player becomes plot owner
- Plot enters "active" state
- Reset decay timer
- Broadcast claim to all clients

### Seed Plot States

```gdscript
enum SeedPlotState {
    UNCLAIMED,      # Available for claiming
    CLAIMED,        # Actively owned by player
    ABANDONED,      # Owner inactive, decay timer started
    DECAYING        # Grace period before chunk removal
}
```

### Decay System

**Trigger Conditions** (any one triggers decay):
- Owner hasn't visited plot in 7 days
- Owner account deleted
- Owner manually abandons plot

**Decay Timeline**:
```
Day 0: Plot marked ABANDONED
Day 1-3: Warning period (owner can reclaim for free)
Day 4-7: DECAYING state (anyone can claim for half price)
Day 7: Plot becomes UNCLAIMED, chunk queued for removal
```

**Chunk Removal Check**:
```gdscript
# Only remove chunk if:
# 1. It's an edge chunk
# 2. Its seed plot is UNCLAIMED
# 3. No players currently in the chunk
# 4. Grace period (6 hours) has passed
```

---

## Technical Implementation

### Database Schema

**New Table: `seed_plots`**
```sql
CREATE TABLE seed_plots (
    plot_id TEXT PRIMARY KEY,           -- "shard_id:chunk_id"
    chunk_id INTEGER NOT NULL,          -- -2, -1, 1, 2, etc.
    shard_id TEXT NOT NULL,             -- Shard identifier
    state TEXT NOT NULL,                -- UNCLAIMED, CLAIMED, ABANDONED, DECAYING
    owner_id TEXT,                      -- Player username (nullable)
    claim_date INTEGER,                 -- Unix timestamp
    last_visit INTEGER,                 -- Unix timestamp
    decay_started INTEGER,              -- Unix timestamp (nullable)
    created_at INTEGER NOT NULL,        -- Unix timestamp
    FOREIGN KEY (owner_id) REFERENCES players(username)
);
```

**New Table: `active_chunks`**
```sql
CREATE TABLE active_chunks (
    chunk_id INTEGER PRIMARY KEY,
    shard_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    is_origin BOOLEAN NOT NULL DEFAULT 0,  -- Origin chunks cannot be removed
    has_seed_plot BOOLEAN NOT NULL DEFAULT 0
);
```

**Initial Data** (seed during first server start):
```sql
INSERT INTO active_chunks (chunk_id, shard_id, is_origin, has_seed_plot, created_at)
VALUES
    (-1, 'default', 0, 1, unixepoch()),  -- West origin edge
    (0, 'default', 1, 0, unixepoch()),   -- Spawn origin
    (1, 'default', 0, 1, unixepoch());   -- East origin edge

INSERT INTO seed_plots (plot_id, chunk_id, shard_id, state, created_at)
VALUES
    ('default:-1', -1, 'default', 'UNCLAIMED', unixepoch()),
    ('default:1', 1, 'default', 'UNCLAIMED', unixepoch());
```

### Server-Side Manager

**New Autoload: `ChunkExpansionManager.gd`**

```gdscript
extends Node

# Configuration
const DECAY_WARNING_DAYS: int = 3
const DECAY_GRACE_DAYS: int = 4
const CHUNK_REMOVAL_GRACE_HOURS: int = 6
const BASE_CLAIM_COST: int = 1000

# State
var active_chunks: Array[int] = []  # List of chunk IDs currently active
var seed_plots: Dictionary = {}     # {chunk_id: SeedPlotData}
var pending_removals: Dictionary = {} # {chunk_id: removal_timestamp}

class SeedPlotData:
    var chunk_id: int
    var state: String  # UNCLAIMED, CLAIMED, ABANDONED, DECAYING
    var owner_id: String
    var claim_date: int
    var last_visit: int
    var decay_started: int

    func is_edge_plot() -> bool:
        var manager = get_node("/root/ChunkExpansionManager")
        return chunk_id == manager.get_west_edge() or chunk_id == manager.get_east_edge()

func _ready() -> void:
    # Load active chunks and seed plots from database
    load_from_database()

    # Start decay check timer (check daily)
    var decay_timer = Timer.new()
    decay_timer.wait_time = 3600.0  # 1 hour
    decay_timer.timeout.connect(_check_seed_plot_decay)
    add_child(decay_timer)
    decay_timer.start()

    # Start chunk removal timer (check every 10 minutes)
    var removal_timer = Timer.new()
    removal_timer.wait_time = 600.0  # 10 minutes
    removal_timer.timeout.connect(_check_chunk_removals)
    add_child(removal_timer)
    removal_timer.start()

func load_from_database() -> void:
    """Load active chunks and seed plots from database"""
    var db = DatabaseManager

    # Load active chunks
    var chunk_data = db.query("SELECT chunk_id FROM active_chunks WHERE shard_id = ?", [db.get_shard_id()])
    for row in chunk_data:
        active_chunks.append(row.chunk_id)

    # Load seed plots
    var plot_data = db.query("SELECT * FROM seed_plots WHERE shard_id = ?", [db.get_shard_id()])
    for row in plot_data:
        var plot = SeedPlotData.new()
        plot.chunk_id = row.chunk_id
        plot.state = row.state
        plot.owner_id = row.owner_id
        plot.claim_date = row.claim_date
        plot.last_visit = row.last_visit
        plot.decay_started = row.decay_started
        seed_plots[row.chunk_id] = plot

    print("🗺️ Chunk Expansion: Loaded %d chunks, %d seed plots" % [active_chunks.size(), seed_plots.size()])

func get_west_edge() -> int:
    """Get the westmost chunk ID"""
    return active_chunks.min()

func get_east_edge() -> int:
    """Get the eastmost chunk ID"""
    return active_chunks.max()

func get_world_bounds() -> Dictionary:
    """Get current world min/max X coordinates"""
    var west = get_west_edge()
    var east = get_east_edge()
    var chunk_size = Constants.CHUNK_SIZE
    return {
        "min_x": west * chunk_size,
        "max_x": (east + 1) * chunk_size,
        "min_chunk": west,
        "max_chunk": east
    }

func claim_seed_plot(chunk_id: int, player_id: String) -> Dictionary:
    """Attempt to claim a seed plot. Returns {success: bool, message: String}"""

    # Validate chunk has a seed plot
    if not seed_plots.has(chunk_id):
        return {"success": false, "message": "No seed plot exists in this chunk"}

    var plot = seed_plots[chunk_id]

    # Check if plot is claimable
    if plot.state == "CLAIMED":
        return {"success": false, "message": "This plot is already claimed"}

    # Calculate cost
    var cost = get_claim_cost(chunk_id)
    var is_reclaim = plot.state == "ABANDONED" and plot.owner_id == player_id

    if is_reclaim:
        cost = 0  # Free reclaim during warning period
    elif plot.state == "DECAYING":
        cost = cost / 2  # Half price during decay

    # Check player has enough gold
    var player_data = DatabaseManager.get_player_data(player_id)
    if player_data.gold < cost:
        return {"success": false, "message": "Not enough gold (need %d)" % cost}

    # Deduct cost
    DatabaseManager.modify_gold(player_id, -cost)

    # Claim plot
    plot.state = "CLAIMED"
    plot.owner_id = player_id
    plot.claim_date = Time.get_unix_time_from_system()
    plot.last_visit = Time.get_unix_time_from_system()
    plot.decay_started = 0

    # Save to database
    save_seed_plot(plot)

    # Broadcast claim to all clients
    _broadcast_seed_plot_claimed.rpc(chunk_id, player_id)

    # Check if we should expand world
    _check_for_expansion()

    return {"success": true, "message": "Seed plot claimed! Cost: %d gold" % cost}

func get_claim_cost(chunk_id: int) -> int:
    """Calculate claim cost based on distance from origin"""
    var distance = abs(chunk_id)
    if distance <= 1:
        return BASE_CLAIM_COST
    return BASE_CLAIM_COST * int(pow(2, distance - 1))

func _check_for_expansion() -> void:
    """Check if both edge plots are claimed, trigger expansion if so"""
    var west_edge = get_west_edge()
    var east_edge = get_east_edge()

    var west_plot = seed_plots.get(west_edge)
    var east_plot = seed_plots.get(east_edge)

    if not west_plot or not east_plot:
        return

    # Both edge plots must be claimed
    if west_plot.state != "CLAIMED" or east_plot.state != "CLAIMED":
        return

    print("🌍 Expansion triggered! Both edge plots claimed")
    expand_world()

func expand_world() -> void:
    """Add new chunks on both edges"""
    var west_edge = get_west_edge()
    var east_edge = get_east_edge()

    var new_west = west_edge - 1
    var new_east = east_edge + 1

    # Add chunks to active list
    active_chunks.append(new_west)
    active_chunks.append(new_east)
    active_chunks.sort()

    # Create new seed plots
    var west_plot = SeedPlotData.new()
    west_plot.chunk_id = new_west
    west_plot.state = "UNCLAIMED"
    west_plot.claim_date = 0
    west_plot.last_visit = 0
    west_plot.decay_started = 0
    seed_plots[new_west] = west_plot

    var east_plot = SeedPlotData.new()
    east_plot.chunk_id = new_east
    east_plot.state = "UNCLAIMED"
    east_plot.claim_date = 0
    east_plot.last_visit = 0
    east_plot.decay_started = 0
    seed_plots[new_east] = east_plot

    # Save to database
    var db = DatabaseManager
    var now = Time.get_unix_time_from_system()
    db.execute("INSERT INTO active_chunks (chunk_id, shard_id, is_origin, has_seed_plot, created_at) VALUES (?, ?, 0, 1, ?)",
        [new_west, db.get_shard_id(), now])
    db.execute("INSERT INTO active_chunks (chunk_id, shard_id, is_origin, has_seed_plot, created_at) VALUES (?, ?, 0, 1, ?)",
        [new_east, db.get_shard_id(), now])

    save_seed_plot(west_plot)
    save_seed_plot(east_plot)

    # Broadcast expansion to all clients
    _broadcast_world_expanded.rpc(new_west, new_east)

    # Trigger chunk generation
    var chunk_system = get_node_or_null("/root/game_world/ChunkBasedPropSystem")
    if chunk_system:
        chunk_system.generate_chunk(new_west)
        chunk_system.generate_chunk(new_east)

    var spawn_manager = get_node_or_null("/root/game_world/ChunkAwareSpawnManager")
    if spawn_manager:
        spawn_manager.initialize_chunk(new_west)
        spawn_manager.initialize_chunk(new_east)

    print("🌍 World expanded! New chunks: %d, %d" % [new_west, new_east])

func _check_seed_plot_decay() -> void:
    """Check all seed plots for decay conditions"""
    var now = Time.get_unix_time_from_system()
    var seven_days = 7 * 24 * 60 * 60

    for chunk_id in seed_plots:
        var plot = seed_plots[chunk_id]

        if plot.state != "CLAIMED":
            continue

        # Check if owner hasn't visited in 7 days
        var days_since_visit = (now - plot.last_visit) / (24 * 60 * 60)

        if days_since_visit >= 7:
            # Start decay
            plot.state = "ABANDONED"
            plot.decay_started = now
            save_seed_plot(plot)
            _broadcast_seed_plot_abandoned.rpc(chunk_id)
            print("⚠️ Seed plot %d abandoned (owner inactive)" % chunk_id)

func _check_chunk_removals() -> void:
    """Check if any chunks are ready for removal"""
    var now = Time.get_unix_time_from_system()
    var west_edge = get_west_edge()
    var east_edge = get_east_edge()

    # Check west edge
    if seed_plots.has(west_edge):
        var plot = seed_plots[west_edge]
        if plot.state == "UNCLAIMED":
            _queue_chunk_removal(west_edge)

    # Check east edge
    if seed_plots.has(east_edge):
        var plot = seed_plots[east_edge]
        if plot.state == "UNCLAIMED":
            _queue_chunk_removal(east_edge)

    # Process pending removals
    for chunk_id in pending_removals.keys():
        var removal_time = pending_removals[chunk_id]
        if now >= removal_time:
            remove_chunk(chunk_id)

func _queue_chunk_removal(chunk_id: int) -> void:
    """Queue a chunk for removal after grace period"""
    if pending_removals.has(chunk_id):
        return  # Already queued

    # Don't remove origin chunks
    var db = DatabaseManager
    var is_origin = db.query_single("SELECT is_origin FROM active_chunks WHERE chunk_id = ? AND shard_id = ?",
        [chunk_id, db.get_shard_id()]).is_origin

    if is_origin:
        return

    var now = Time.get_unix_time_from_system()
    var removal_time = now + (CHUNK_REMOVAL_GRACE_HOURS * 60 * 60)
    pending_removals[chunk_id] = removal_time

    _broadcast_chunk_removal_warning.rpc(chunk_id, CHUNK_REMOVAL_GRACE_HOURS)
    print("⚠️ Chunk %d queued for removal in %d hours" % [chunk_id, CHUNK_REMOVAL_GRACE_HOURS])

func remove_chunk(chunk_id: int) -> void:
    """Remove a chunk from the world"""

    # Teleport any players in the chunk
    teleport_players_from_chunk(chunk_id)

    # Remove from active chunks
    active_chunks.erase(chunk_id)

    # Remove seed plot
    seed_plots.erase(chunk_id)

    # Remove from database
    var db = DatabaseManager
    db.execute("DELETE FROM active_chunks WHERE chunk_id = ? AND shard_id = ?", [chunk_id, db.get_shard_id()])
    db.execute("DELETE FROM seed_plots WHERE chunk_id = ? AND shard_id = ?", [chunk_id, db.get_shard_id()])

    # Clear pending removal
    pending_removals.erase(chunk_id)

    # Broadcast removal
    _broadcast_chunk_removed.rpc(chunk_id)

    # Trigger chunk despawn
    var chunk_system = get_node_or_null("/root/game_world/ChunkBasedPropSystem")
    if chunk_system:
        chunk_system.unload_chunk(chunk_id)

    var spawn_manager = get_node_or_null("/root/game_world/ChunkAwareSpawnManager")
    if spawn_manager:
        spawn_manager.despawn_chunk_enemies(chunk_id)

    print("🗺️ Chunk %d removed from world" % chunk_id)

func teleport_players_from_chunk(chunk_id: int) -> void:
    """Teleport all players in a chunk to safety"""
    var chunk_size = Constants.CHUNK_SIZE
    var chunk_start = chunk_id * chunk_size
    var chunk_end = (chunk_id + 1) * chunk_size

    var players = get_tree().get_nodes_in_group("player")
    for player in players:
        if not is_instance_valid(player):
            continue

        if player.global_position.x >= chunk_start and player.global_position.x < chunk_end:
            # Teleport to campfire
            var campfire_pos = Vector2(Constants.CHUNK_SIZE / 2, 0)
            player.global_position = campfire_pos

            # Notify player
            if player.has_method("show_notification"):
                player.show_notification("Teleported to safety - chunk removed!")

func save_seed_plot(plot: SeedPlotData) -> void:
    """Save seed plot data to database"""
    var db = DatabaseManager
    var now = Time.get_unix_time_from_system()

    db.execute("""
        INSERT OR REPLACE INTO seed_plots
        (plot_id, chunk_id, shard_id, state, owner_id, claim_date, last_visit, decay_started, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, [
        "%s:%d" % [db.get_shard_id(), plot.chunk_id],
        plot.chunk_id,
        db.get_shard_id(),
        plot.state,
        plot.owner_id if plot.owner_id else null,
        plot.claim_date,
        plot.last_visit,
        plot.decay_started,
        now
    ])

# Network RPCs
@rpc("authority", "call_local")
func _broadcast_seed_plot_claimed(chunk_id: int, player_id: String) -> void:
    """Broadcast seed plot claim to all clients"""
    print("🌱 Seed plot %d claimed by %s" % [chunk_id, player_id])

@rpc("authority", "call_local")
func _broadcast_seed_plot_abandoned(chunk_id: int) -> void:
    """Broadcast seed plot abandonment"""
    print("💀 Seed plot %d abandoned" % chunk_id)

@rpc("authority", "call_local")
func _broadcast_world_expanded(west_chunk: int, east_chunk: int) -> void:
    """Broadcast world expansion to all clients"""
    print("🌍 WORLD EXPANDED! New chunks: %d, %d" % [west_chunk, east_chunk])

@rpc("authority", "call_local")
func _broadcast_chunk_removal_warning(chunk_id: int, hours: int) -> void:
    """Warn players that a chunk will be removed"""
    print("⚠️ WARNING: Chunk %d will be removed in %d hours" % [chunk_id, hours])

@rpc("authority", "call_local")
func _broadcast_chunk_removed(chunk_id: int) -> void:
    """Broadcast chunk removal to all clients"""
    print("🗑️ Chunk %d removed from world" % chunk_id)
```

---

## Seed Plot Visuals

### World Marker
```gdscript
# SeedPlot.gd - Visual marker for seed plots
extends Area2D

@export var chunk_id: int
var plot_state: String = "UNCLAIMED"
var owner_name: String = ""

# Visual elements
var sprite: Sprite2D
var claim_prompt: Label
var ownership_label: Label

func _ready():
    # Create visual marker (glowing plot of land)
    sprite = Sprite2D.new()
    sprite.texture = load("res://assets/environment/seed_plot.png")
    sprite.modulate = Color(0.5, 0.8, 0.3, 0.7)  # Green glow
    add_child(sprite)

    # Create claim prompt
    create_interaction_ui()

    # Connect to player proximity
    body_entered.connect(_on_player_entered)
    body_exited.connect(_on_player_exited)

func update_state(new_state: String, new_owner: String = ""):
    plot_state = new_state
    owner_name = new_owner

    match plot_state:
        "UNCLAIMED":
            sprite.modulate = Color(0.5, 0.8, 0.3, 0.7)  # Green
            ownership_label.text = "Unclaimed Territory"
        "CLAIMED":
            sprite.modulate = Color(0.3, 0.5, 0.9, 0.7)  # Blue
            ownership_label.text = "Owner: %s" % owner_name
        "ABANDONED":
            sprite.modulate = Color(0.9, 0.6, 0.2, 0.7)  # Orange
            ownership_label.text = "Abandoned (Reclaim Available)"
        "DECAYING":
            sprite.modulate = Color(0.9, 0.2, 0.2, 0.7)  # Red
            ownership_label.text = "Decaying (Half Price)"

func _on_player_entered(body: Node2D):
    if body.is_in_group("player"):
        claim_prompt.visible = true

func _on_player_exited(body: Node2D):
    if body.is_in_group("player"):
        claim_prompt.visible = false
```

---

## Server Performance Impact

### Expansion Costs

**Per Expansion** (adds 2 chunks):
- CPU: +28% (2 × 14% per chunk)
- Memory: +3 MB (2 × 1.5 MB per chunk)
- Network: +28 KB/s (2 × 14 KB/s per chunk)

**Expansion Limits** (4GB VPS):
```
Expansion 0 (start):  3 chunks, 42% CPU  ✅ Comfortable
Expansion 1:          5 chunks, 70% CPU  ✅ Good
Expansion 2:          7 chunks, 98% CPU  ⚠️ At Limit
Expansion 3:          9 chunks, 126% CPU ❌ Requires Upgrade
```

**Recommendation**: Cap at 2 expansions (7 chunks max) for 4GB VPS, or implement sharding.

---

## Player Experience

### Claiming Flow
1. Player reaches edge chunk
2. Sees glowing seed plot marker
3. Approaches plot, sees "[F] Claim Territory - 1000 Gold"
4. Presses F, gold deducted, plot claimed
5. Notification: "Territory claimed! If both edge plots are claimed, the world will expand."
6. If both edges claimed: "🌍 WORLD EXPANDING! New territories discovered!"

### Decay Warnings
```
Day 0 (abandoned):
  "⚠️ Your seed plot in Chunk -2 has been abandoned due to inactivity."

Day 1-3 (warning):
  "⚠️ Your seed plot will decay in X days. Visit to reclaim for free!"

Day 4-7 (decaying):
  "💀 Your seed plot is decaying. Others can claim it for half price."

Day 7 (lost):
  "🗑️ Your seed plot in Chunk -2 was lost. The chunk will be removed."
```

### Chunk Removal
```
6 hours before removal:
  "⚠️ WARNING: Chunk -3 will be removed in 6 hours. Teleport to safety!"

At removal:
  *Player teleported to campfire*
  "Teleported to safety - Chunk -3 was removed from the world."
```

---

---

## Regional World Structure

> **Status**: Design Vision - Builds on Dynamic Chunk Expansion

### Overview

The world is organized into **Regions** (biomes) with organic boundaries, not level stripes. Each region contains dynamically expanding chunks, but players see a **logical map** of named areas.

```
                    ┌───────────┐
                    │FROSTPEAKS │
                    │  Lv 25-35 │
                    └─────┬─────┘
                          │
           ┌──────────────┼──────────────┐
           │              │              │
     ┌─────┴─────┐  ┌─────┴─────┐  ┌─────┴─────┐
     │ DARKWOOD  │  │GREENFIELDS│  │ ASHLANDS  │
     │  Lv 15-25 │──│  Lv 1-15  │──│  Lv 20-30 │
     └─────┬─────┘  └─────┬─────┘  └───────────┘
           │              │
     ┌─────┴─────┐        │
     │  MARSHES  │────────┘
     │  Lv 10-20 │
     └───────────┘
```

### Key Principles

| Concept | Player Sees | System Manages |
|---------|-------------|----------------|
| **Regions** | Named biomes with level ranges | Dynamic chunk pools per region |
| **Sectors** | Named areas within regions | Chunks allocated to sectors as needed |
| **Transitions** | Fixed landmarks (gates, bridges) | Connection points between regions |
| **Territory** | Control %, guild ownership | Player investment per sector |
| **Map** | Logical diagram + fog of war | Actual chunk coordinates |

### Difficulty Within Regions

Each region has internal difficulty gradients (not flat):

```
THE DARKWOOD (Lv 15-25)

         [Deeper = Harder]
               ↑
    ┌──────────┴──────────┐
    │   Lv 23-25  ☠️       │  ← Ancient ruins, elite mobs
    │   Lv 19-22  🐺       │  ← Wolf packs, harder content
    │   Lv 15-18  🌲       │  ← Forest edge, entry level
    └──────────┬──────────┘
               ↓
        [Edge = Easier]
    (connects to Greenfields)
```

### Regional Expansion

Each region expands independently based on its population:

```
Region population high?
    │
    ▼
Region expands at its frontier edges
(direction depends on region geography)
    │
    ▼
More chunks allocated to that region
Higher level content at new deep edges
Entry-level content stays near transition points
```

### Sectors (Strategic Map Layer)

Within each region, **Sectors** are named areas for conquest gameplay:

```
DARKWOOD - SECTOR VIEW

┌─────────┬─────────┬─────────┬─────────┐
│ DEEP    │ ANCIENT │ WOLVES  │ SHADOW  │
│ WOODS   │ RUINS   │ DEN     │ HOLLOW  │
│ Lv24-25 │ Lv22-24 │ Lv20-22 │ Lv21-23 │
├─────────┼─────────┼─────────┼─────────┤
│ TWISTED │ HUNTER'S│ FALLEN  │ EASTERN │
│ PATH    │ CAMP    │ BRIDGE  │ EDGE    │
│ Lv19-21 │ Lv18-20 │ Lv17-19 │ Lv16-18 │
├─────────┴─────────┼─────────┴─────────┤
│ WOODSMAN'S GATE   │ CLEARINGS         │
│ (to Greenfields)  │ Lv15-17           │
└───────────────────┴───────────────────┘
```

**Sectors are fixed named areas.** The chunks WITHIN them scale dynamically, but "Wolves Den" is always north of "Hunter's Camp" on the map.

### Sector Data Per Player

```
┌─────────────────────────────────────┐
│  WOLVES DEN                         │
│  Level 20-22                        │
│                                     │
│  Control: Iron Wolves (78%)         │
│  ████████████████░░░░               │
│                                     │
│  Landmarks:                         │
│  • Wolf Alpha Spawn (controlled)    │
│  • Iron Keep [Guild Base]           │
│  • Ancient Well (resource)          │
│  • 3 Seed Plots (2 claimed)         │
│                                     │
│  Activity: 🔴 High (12 players)     │
└─────────────────────────────────────┘
```

### Player-Facing Map

Players see a **logical diagram**, not chunk coordinates:

- Region connections (which regions border which)
- Sector names within regions
- Territory control percentages
- Fog of war for unexplored sectors
- Landmarks and bases

The actual chunk count (whether Darkwood is 50 chunks or 500) is invisible.

### Chunk Decay Rules (Regional)

```
PERMANENT (never despawn):
• Core town/transition chunks
• Player bases/structures
• Seeded plots
• Road tiles connecting permanent areas

TEMPORARY (can despawn):
• Wilderness chunks with no player investment
• Frontier chunks nobody claimed
• Decay timer: 7 days no visits → warning → despawn
```

### Integration with Seed Plot System

The existing seed plot mechanics apply per-sector:
- Each sector has seed plots at its edges
- Claiming plots expands that sector's chunk allocation
- Abandoned plots cause sector contraction
- Player investment (bases, seeds) makes chunks permanent

---

## Future Enhancements

### 1. Guild Claiming
- Guilds can pool resources to claim plots
- Plot ownership shared among guild members

### 2. Plot Buildings
- Players can build structures on claimed plots
- Structures persist with the plot
- Lost when plot decays (inventory returned to owner)

### 3. Plot Benefits
- Claimed plots reduce enemy spawns near owner
- Special resources spawn on owned plots
- Teleport waypoint to owned plots

### 4. Plot Trading
- Players can sell/transfer plot ownership
- Auction system for decaying plots

### 5. Conquest System
- Players can challenge plot owners for ownership
- PvP arena at plot location
- Winner takes plot

---

## Implementation Checklist

- [ ] Create database schema (`seed_plots`, `active_chunks` tables)
- [ ] Implement `ChunkExpansionManager.gd` autoload
- [ ] Create `SeedPlot.gd` world marker scene
- [ ] Update `ChunkBasedPropSystem.gd` to support dynamic chunk IDs
- [ ] Update `ChunkAwareSpawnManager.gd` to support dynamic chunks
- [ ] Implement claim UI and RPC system
- [ ] Implement decay checking timer
- [ ] Implement chunk removal system with teleport
- [ ] Add player notifications for all events
- [ ] Test expansion/contraction flow
- [ ] Add admin commands for testing (`/expand`, `/contract`, `/claim`)
- [ ] Document in player guide

---

## Testing Plan

### 1. Basic Expansion Test
```
1. Start server with 3 origin chunks
2. Admin claim plot in Chunk -1
3. Admin claim plot in Chunk 1
4. Verify chunks -2 and 2 spawn
5. Verify new seed plots appear
```

### 2. Decay Test
```
1. Claim a seed plot
2. Set last_visit to 8 days ago (manual DB edit)
3. Trigger decay check
4. Verify plot enters ABANDONED state
5. Wait for removal timer
6. Verify chunk despawns
```

### 3. Performance Test
```
1. Expand to 5 chunks
2. Spawn 50 bot players dispersed
3. Monitor CPU, memory, network
4. Expand to 7 chunks
5. Monitor for degradation
```

### 4. Edge Cases
```
1. Player in chunk when it's removed → verify teleport
2. Both plots claimed simultaneously → verify single expansion
3. Plot abandoned then reclaimed → verify free reclaim
4. Server restart → verify chunks/plots persist
```

---

## Notes

- Seed plots should be visually prominent (glowing markers, particle effects)
- Consider audio cues for claim/expansion/removal events
- Add world map UI showing claimed vs unclaimed territories
- Track expansion history for achievements ("World Explorer" badge)
- Consider seasonal events that reduce decay rates
