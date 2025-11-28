# Distributed Chunk Architecture

## Overview

A **server-authoritative distributed compute** model where the central server owns all game state, but player machines perform the heavy simulation work (AI, physics, spawning) for nearby chunks. Players act as **compute workers**, not hosts with authority.

This naturally integrates with dynamic chunk expansion - more players = more compute resources = more chunks can exist.

> **Status**: 📋 Design Document - Not Yet Implemented

---

## Core Principle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CENTRAL SERVER                                  │
│                     (Authority - Single Source of Truth)                │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    AUTHORITATIVE STATE                           │   │
│  │  • All enemy positions, health, AI state                        │   │
│  │  • All player positions, inventory, stats                       │   │
│  │  • All loot, resources, world state                             │   │
│  │  • Chunk existence (which chunks are active)                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    WORKER MANAGEMENT                             │   │
│  │  • Assigns chunks to nearby players                             │   │
│  │  • Receives simulation reports from workers                     │   │
│  │  • Validates all reported state changes                         │   │
│  │  • Broadcasts validated state to all clients                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
            ┌───────────────────┼───────────────────┐
            │                   │                   │
            ▼                   ▼                   ▼
   ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
   │  PLAYER A       │ │  PLAYER B       │ │  PLAYER C       │
   │  (Worker)       │ │  (Worker)       │ │  (Worker)       │
   │                 │ │                 │ │                 │
   │  Simulates:     │ │  Simulates:     │ │  Simulates:     │
   │  Chunk [0,0]    │ │  Chunk [3,0]    │ │  Chunk [6,0]    │
   │  Chunk [1,0]    │ │  Chunk [4,0]    │ │  Chunk [7,0]    │
   │                 │ │                 │ │                 │
   │  NO AUTHORITY   │ │  NO AUTHORITY   │ │  NO AUTHORITY   │
   │  Just compute   │ │  Just compute   │ │  Just compute   │
   └─────────────────┘ └─────────────────┘ └─────────────────┘
```

**Key difference from traditional "player hosting":**
- Players don't OWN chunks - they WORK on them
- Server validates EVERYTHING - workers can't cheat
- Workers are interchangeable - if one disconnects, another takes over
- All traffic goes through central server - no P2P connections needed

---

## How It Works

### 1. Chunk Assignment

Server assigns chunks to players based on proximity. Each player simulates 1-3 chunks.

```gdscript
# === CENTRAL SERVER ===
# ChunkWorkerManager.gd

var chunk_workers: Dictionary = {}      # chunk_coords -> worker_peer_id
var worker_chunks: Dictionary = {}      # peer_id -> Array of chunk_coords
var unassigned_chunks: Array = []       # Chunks needing workers

const MAX_CHUNKS_PER_WORKER = 3
const CHUNK_REASSIGN_DISTANCE = 2000.0  # Reassign if worker moves too far

func _physics_process(delta):
    _update_worker_assignments()

func _update_worker_assignments():
    # Check each active chunk
    for chunk_coords in get_active_chunks():
        var current_worker = chunk_workers.get(chunk_coords, -1)
        var chunk_center = _get_chunk_center(chunk_coords)

        # Find best worker (nearest player not at capacity)
        var best_worker = _find_best_worker_for_chunk(chunk_coords, chunk_center)

        if best_worker == -1:
            # No workers available - server simulates this chunk (fallback)
            if current_worker != -1:
                _unassign_chunk(chunk_coords)
            _server_simulate_chunk(chunk_coords)
            continue

        # Reassign if current worker is too far or disconnected
        if current_worker != best_worker:
            if current_worker != -1:
                _unassign_chunk(chunk_coords)
            _assign_chunk(chunk_coords, best_worker)

func _find_best_worker_for_chunk(chunk_coords: String, chunk_center: Vector2) -> int:
    var best_peer = -1
    var best_distance = INF

    for peer_id in connected_players:
        var player_pos = player_positions[peer_id]
        var distance = player_pos.distance_to(chunk_center)

        # Skip if player is too far
        if distance > CHUNK_REASSIGN_DISTANCE:
            continue

        # Skip if player at capacity
        var current_load = worker_chunks.get(peer_id, []).size()
        if current_load >= MAX_CHUNKS_PER_WORKER:
            continue

        # Prefer closer players
        if distance < best_distance:
            best_distance = distance
            best_peer = peer_id

    return best_peer

func _assign_chunk(chunk_coords: String, peer_id: int):
    chunk_workers[chunk_coords] = peer_id

    if not worker_chunks.has(peer_id):
        worker_chunks[peer_id] = []
    worker_chunks[peer_id].append(chunk_coords)

    # Send chunk state to new worker
    var chunk_state = _get_authoritative_chunk_state(chunk_coords)
    rpc_id(peer_id, "become_chunk_worker", chunk_coords, chunk_state)

    print("[Server] Assigned chunk %s to peer %d" % [chunk_coords, peer_id])

func _unassign_chunk(chunk_coords: String):
    var old_worker = chunk_workers.get(chunk_coords, -1)
    if old_worker != -1:
        rpc_id(old_worker, "stop_chunk_work", chunk_coords)
        worker_chunks[old_worker].erase(chunk_coords)
    chunk_workers.erase(chunk_coords)

func _on_player_disconnected(peer_id: int):
    # Reassign all chunks this player was working on
    var chunks = worker_chunks.get(peer_id, [])
    for chunk_coords in chunks:
        chunk_workers.erase(chunk_coords)
        unassigned_chunks.append(chunk_coords)
    worker_chunks.erase(peer_id)
```

### 2. Worker Simulation (Player's Machine)

Workers run AI, physics, spawning locally - but report everything to server.

```gdscript
# === PLAYER CLIENT ===
# ChunkWorker.gd

var my_assigned_chunks: Dictionary = {}  # chunk_coords -> ChunkSimulation
var report_interval: float = 0.1         # 10 Hz reports to server

class ChunkSimulation:
    var coords: String
    var enemies: Array = []
    var harvestables: Array = []
    var ground_items: Array = []
    var last_report_time: float = 0.0

@rpc("authority", "call_remote")
func become_chunk_worker(chunk_coords: String, initial_state: Dictionary):
    print("[Worker] Now simulating chunk %s" % chunk_coords)

    var sim = ChunkSimulation.new()
    sim.coords = chunk_coords

    # Initialize from server's authoritative state
    _load_chunk_state(sim, initial_state)

    my_assigned_chunks[chunk_coords] = sim

@rpc("authority", "call_remote")
func stop_chunk_work(chunk_coords: String):
    print("[Worker] Stopped simulating chunk %s" % chunk_coords)

    if my_assigned_chunks.has(chunk_coords):
        _cleanup_chunk_simulation(my_assigned_chunks[chunk_coords])
        my_assigned_chunks.erase(chunk_coords)

func _physics_process(delta):
    for chunk_coords in my_assigned_chunks:
        var sim = my_assigned_chunks[chunk_coords]

        # Run simulation locally
        _simulate_chunk(sim, delta)

        # Report to server at interval
        if Time.get_ticks_msec() / 1000.0 - sim.last_report_time > report_interval:
            _report_chunk_state(sim)
            sim.last_report_time = Time.get_ticks_msec() / 1000.0

func _simulate_chunk(sim: ChunkSimulation, delta: float):
    # === ENEMY AI ===
    for enemy in sim.enemies:
        # Find target (could be any player in chunk)
        var target = _find_nearest_player_in_chunk(sim.coords)

        # Run AI state machine
        match enemy.state:
            "idle":
                _enemy_idle_behavior(enemy, target, delta)
            "chase":
                _enemy_chase_behavior(enemy, target, delta)
            "attack":
                _enemy_attack_behavior(enemy, target, delta)
            "retreat":
                _enemy_retreat_behavior(enemy, delta)

        # Update position based on velocity
        enemy.position += enemy.velocity * delta

    # === RESPAWNING ===
    _check_enemy_respawns(sim, delta)
    _check_harvestable_respawns(sim, delta)

func _report_chunk_state(sim: ChunkSimulation):
    var report = {
        "chunk": sim.coords,
        "timestamp": Time.get_ticks_msec(),
        "enemies": [],
        "harvestables": [],
        "events": sim.pending_events,  # Damage dealt, items dropped, etc.
    }

    # Compile enemy states
    for enemy in sim.enemies:
        report.enemies.append({
            "id": enemy.id,
            "position": enemy.position,
            "health": enemy.health,
            "state": enemy.state,
            "target_id": enemy.target_id,
            "velocity": enemy.velocity,
        })

    # Compile harvestable states
    for harvestable in sim.harvestables:
        report.harvestables.append({
            "id": harvestable.id,
            "remaining": harvestable.remaining,
            "respawn_timer": harvestable.respawn_timer,
        })

    # Send to server
    rpc_id(1, "worker_chunk_report", report)

    # Clear pending events
    sim.pending_events = []
```

### 3. Server Validation

Server receives reports, validates everything, then broadcasts authoritative state.

```gdscript
# === CENTRAL SERVER ===
# ChunkStateValidator.gd

var authoritative_state: Dictionary = {}  # chunk_coords -> ChunkState
var last_known_state: Dictionary = {}     # For validation comparisons

const MAX_ENEMY_SPEED = 150.0             # pixels/sec
const MAX_POSITION_DRIFT = 50.0           # Tolerance for position differences
const DAMAGE_SANITY_MIN = 0.0
const DAMAGE_SANITY_MAX = 10000.0

@rpc("any_peer", "call_remote")
func worker_chunk_report(report: Dictionary):
    var worker_id = multiplayer.get_remote_sender_id()
    var chunk_coords = report.chunk

    # Verify this worker is assigned to this chunk
    if chunk_workers.get(chunk_coords) != worker_id:
        push_warning("Unauthorized chunk report from peer %d for chunk %s" % [worker_id, chunk_coords])
        return

    # Validate and apply the report
    var validated = _validate_chunk_report(chunk_coords, report)

    # Store as authoritative
    authoritative_state[chunk_coords] = validated

    # Broadcast to all players who can see this chunk
    _broadcast_chunk_state(chunk_coords, validated)

func _validate_chunk_report(chunk_coords: String, report: Dictionary) -> Dictionary:
    var validated = {
        "enemies": [],
        "harvestables": [],
        "events": [],
    }

    var old_state = last_known_state.get(chunk_coords, {})

    # === VALIDATE ENEMIES ===
    for enemy_data in report.enemies:
        var enemy_id = enemy_data.id
        var old_enemy = _get_old_enemy_state(old_state, enemy_id)

        var valid_enemy = enemy_data.duplicate()

        # Position validation - can't teleport
        if old_enemy:
            var distance_moved = old_enemy.position.distance_to(enemy_data.position)
            var max_move = MAX_ENEMY_SPEED * report_interval * 1.5  # Some tolerance

            if distance_moved > max_move:
                push_warning("Enemy %s moved too far: %f > %f" % [enemy_id, distance_moved, max_move])
                valid_enemy.position = old_enemy.position  # Reject movement
                _flag_suspicious_worker(chunk_coords, "position_hack")

        # Health validation - can only go down (unless healed by valid mechanic)
        if old_enemy and enemy_data.health > old_enemy.health:
            push_warning("Enemy %s health increased suspiciously" % enemy_id)
            valid_enemy.health = old_enemy.health
            _flag_suspicious_worker(chunk_coords, "health_hack")

        # State validation - must be valid state
        if enemy_data.state not in ["idle", "chase", "attack", "retreat", "dead"]:
            valid_enemy.state = "idle"

        validated.enemies.append(valid_enemy)

    # === VALIDATE EVENTS ===
    for event in report.get("events", []):
        match event.type:
            "damage_dealt":
                # Validate damage is sane
                if event.amount < DAMAGE_SANITY_MIN or event.amount > DAMAGE_SANITY_MAX:
                    continue
                # Validate attacker exists and is in range
                if not _validate_attack_range(event.attacker_id, event.target_id, chunk_coords):
                    continue
                validated.events.append(event)

            "enemy_killed":
                # Validate enemy was actually low health
                var enemy = _get_enemy_from_report(report, event.enemy_id)
                if enemy and enemy.health <= 0:
                    validated.events.append(event)

            "loot_dropped":
                # Validate loot is reasonable for enemy type/level
                if _validate_loot_drop(event.enemy_id, event.loot):
                    validated.events.append(event)

    # === VALIDATE HARVESTABLES ===
    for harvestable_data in report.harvestables:
        var valid_harvestable = harvestable_data.duplicate()

        # Remaining resources can only go down
        var old_harvestable = _get_old_harvestable_state(old_state, harvestable_data.id)
        if old_harvestable and harvestable_data.remaining > old_harvestable.remaining:
            valid_harvestable.remaining = old_harvestable.remaining

        validated.harvestables.append(valid_harvestable)

    # Store for next validation
    last_known_state[chunk_coords] = validated

    return validated

func _broadcast_chunk_state(chunk_coords: String, state: Dictionary):
    # Find all players who should receive this chunk's state
    var viewers = _get_players_viewing_chunk(chunk_coords)

    # Prepare network-optimized state packet
    var packet = _compress_state_for_network(chunk_coords, state)

    for peer_id in viewers:
        rpc_id(peer_id, "receive_chunk_state", packet)

func _flag_suspicious_worker(chunk_coords: String, reason: String):
    var worker_id = chunk_workers.get(chunk_coords)
    if worker_id == -1:
        return

    if not suspicious_workers.has(worker_id):
        suspicious_workers[worker_id] = []
    suspicious_workers[worker_id].append({
        "time": Time.get_unix_time_from_system(),
        "chunk": chunk_coords,
        "reason": reason,
    })

    # Too many flags = kick and reassign
    if suspicious_workers[worker_id].size() > 10:
        push_warning("Kicking suspicious worker %d" % worker_id)
        _kick_player(worker_id, "Suspicious activity detected")
```

### 4. Client Receives Authoritative State

All clients (including the worker) receive the validated state from server.

```gdscript
# === PLAYER CLIENT ===
# ChunkRenderer.gd

@rpc("authority", "call_remote")
func receive_chunk_state(packet: Dictionary):
    var chunk_coords = packet.chunk

    # Update local visualization
    for enemy_data in packet.enemies:
        var enemy_node = _get_or_create_enemy_node(enemy_data.id)

        # Smooth interpolation to authoritative position
        var target_pos = enemy_data.position
        enemy_node.target_position = target_pos

        # Update visual state
        enemy_node.update_health_bar(enemy_data.health)
        enemy_node.play_state_animation(enemy_data.state)

    # Process events (damage numbers, death animations, loot)
    for event in packet.get("events", []):
        match event.type:
            "damage_dealt":
                _show_damage_number(event.target_id, event.amount, event.is_crit)
            "enemy_killed":
                _play_death_animation(event.enemy_id)
            "loot_dropped":
                _spawn_loot_visuals(event.position, event.loot)
```

---

## Dynamic Chunk Expansion

This architecture naturally supports world growth/shrinkage based on player population.

### Expansion Logic

```gdscript
# === CENTRAL SERVER ===
# DynamicChunkManager.gd

var active_chunks: Dictionary = {}        # chunk_coords -> ChunkData
var chunk_player_counts: Dictionary = {}  # chunk_coords -> player count

const PLAYERS_PER_CHUNK_IDEAL = 15        # Target density
const EXPANSION_THRESHOLD = 0.8           # 80% of ideal = expand
const CONTRACTION_DELAY = 300.0           # 5 min empty before despawn
const MIN_CHUNKS = 3                      # Always keep spawn area

func _process(delta):
    _update_chunk_populations()
    _check_expansion()
    _check_contraction()

func _update_chunk_populations():
    # Reset counts
    for chunk in active_chunks:
        chunk_player_counts[chunk] = 0

    # Count players per chunk
    for peer_id in connected_players:
        var chunk = _get_chunk_for_position(player_positions[peer_id])
        if chunk_player_counts.has(chunk):
            chunk_player_counts[chunk] += 1

func _check_expansion():
    # Check edge chunks for overcrowding
    for chunk_coords in _get_edge_chunks():
        var count = chunk_player_counts.get(chunk_coords, 0)
        var density = float(count) / PLAYERS_PER_CHUNK_IDEAL

        if density >= EXPANSION_THRESHOLD:
            # This edge is crowded - expand outward
            var new_chunk = _get_expansion_chunk(chunk_coords)
            if new_chunk and not active_chunks.has(new_chunk):
                _spawn_chunk(new_chunk)

func _check_contraction():
    # Check edge chunks for emptiness
    for chunk_coords in _get_edge_chunks():
        # Never despawn core chunks
        if _is_core_chunk(chunk_coords):
            continue

        var count = chunk_player_counts.get(chunk_coords, 0)

        if count == 0:
            # Start or continue empty timer
            if not empty_chunk_timers.has(chunk_coords):
                empty_chunk_timers[chunk_coords] = 0.0
            empty_chunk_timers[chunk_coords] += get_process_delta_time()

            if empty_chunk_timers[chunk_coords] >= CONTRACTION_DELAY:
                _despawn_chunk(chunk_coords)
        else:
            # Reset timer if players returned
            empty_chunk_timers.erase(chunk_coords)

func _spawn_chunk(chunk_coords: String):
    print("[Server] Spawning new chunk: %s" % chunk_coords)

    # Create chunk data
    var chunk = ChunkData.new()
    chunk.coords = chunk_coords
    chunk.spawned_at = Time.get_unix_time_from_system()

    # Generate enemies based on chunk position (level scaling)
    chunk.enemies = _generate_enemies_for_chunk(chunk_coords)
    chunk.harvestables = _generate_harvestables_for_chunk(chunk_coords)

    active_chunks[chunk_coords] = chunk
    chunk_player_counts[chunk_coords] = 0

    # Find a worker for this chunk
    _update_worker_assignments()

    # Notify all nearby players
    _broadcast_chunk_spawned(chunk_coords)

func _despawn_chunk(chunk_coords: String):
    print("[Server] Despawning empty chunk: %s" % chunk_coords)

    # Unassign worker
    _unassign_chunk(chunk_coords)

    # Remove from active chunks
    active_chunks.erase(chunk_coords)
    chunk_player_counts.erase(chunk_coords)
    empty_chunk_timers.erase(chunk_coords)

    # Notify players (they'll unload visuals)
    _broadcast_chunk_despawned(chunk_coords)

func _generate_enemies_for_chunk(chunk_coords: String) -> Array:
    var enemies = []
    var chunk_x = int(chunk_coords.split(",")[0])

    # Level scales with distance from spawn (chunk 0)
    var base_level = abs(chunk_x) * 2 + 1
    var level_variance = 2

    # Spawn count
    var enemy_count = ENEMIES_PER_CHUNK

    for i in range(enemy_count):
        var enemy = {
            "id": _generate_enemy_id(),
            "type": _get_enemy_type_for_level(base_level),
            "level": base_level + randi_range(-level_variance, level_variance),
            "position": _random_position_in_chunk(chunk_coords),
            "health": 0,  # Will be set based on level
            "state": "idle",
        }
        enemy.health = _calculate_enemy_max_health(enemy.level)
        enemy.max_health = enemy.health
        enemies.append(enemy)

    return enemies
```

### Scaling Visualization

```
Population: 10 players
┌─────┬─────┬─────┐
│ -1  │  0  │  1  │  3 chunks active
│     │SPAWN│     │  All players fit comfortably
└─────┴─────┴─────┘

Population: 50 players (crowded center)
┌─────┬─────┬─────┬─────┬─────┐
│ -2  │ -1  │  0  │  1  │  2  │  5 chunks active
│     │     │SPAWN│     │     │  Expanded east and west
└─────┴─────┴─────┴─────┴─────┘

Population: 200 players
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ -4  │ -3  │ -2  │ -1  │  0  │  1  │  2  │  3  │  4  │  9 chunks
│L17+ │L13  │ L9  │ L5  │SPAWN│ L5  │ L9  │L13  │L17+ │  Levels scale
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

Population drops to 30 (late night)
┌─────┬─────┬─────┬─────┬─────┐
│ -2  │ -1  │  0  │  1  │  2  │  Edge chunks despawned
│     │     │SPAWN│     │     │  after 5 min empty
└─────┴─────┴─────┴─────┴─────┘
```

---

## Worker Failover

When a worker disconnects, their chunks are seamlessly reassigned.

```gdscript
# === CENTRAL SERVER ===
# WorkerFailover.gd

func _on_player_disconnected(peer_id: int):
    var orphaned_chunks = worker_chunks.get(peer_id, [])

    if orphaned_chunks.is_empty():
        return

    print("[Server] Worker %d disconnected, reassigning %d chunks" % [peer_id, orphaned_chunks.size()])

    for chunk_coords in orphaned_chunks:
        # Server temporarily simulates while finding new worker
        _server_simulate_chunk(chunk_coords)

        # Queue for reassignment
        pending_reassignment.append(chunk_coords)

    # Clean up
    worker_chunks.erase(peer_id)

    # Trigger immediate reassignment check
    _update_worker_assignments()

func _server_simulate_chunk(chunk_coords: String):
    # Fallback: server does the work
    # This is expensive but ensures no interruption
    server_simulated_chunks.append(chunk_coords)

func _physics_process(delta):
    # Server simulates orphaned chunks until workers assigned
    for chunk_coords in server_simulated_chunks:
        if chunk_workers.has(chunk_coords):
            # Worker assigned, stop server simulation
            server_simulated_chunks.erase(chunk_coords)
            continue

        # Run simulation on server (same logic as client)
        _simulate_chunk_on_server(chunk_coords, delta)
```

---

## Network Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                            DATA FLOW                                 │
└──────────────────────────────────────────────────────────────────────┘

1. ASSIGNMENT (Server → Worker)
   Server: "You simulate chunk [3,0]"
   ────────────────────────────────────►  Worker receives chunk state
                                          Worker starts local simulation

2. SIMULATION (Worker local)
   Worker runs enemy AI, physics
   Worker tracks damage, deaths, drops
   [No network traffic - all local]

3. REPORT (Worker → Server, 10 Hz)
   Worker: "Here's chunk [3,0] state"
   ────────────────────────────────────►  Server receives report
                                          Server VALIDATES everything
                                          Server stores authoritative state

4. BROADCAST (Server → All Clients, 10 Hz)
   Server: "Authoritative chunk [3,0] state"
   ◄────────────────────────────────────  All players in/near chunk
                                          receive validated state
                                          Clients render from server state

5. PLAYER ACTIONS (Client → Server)
   Player attacks enemy
   ────────────────────────────────────►  Server validates attack
                                          Server applies damage
                                          Server broadcasts result

   NOTE: Damage goes to SERVER, not to worker!
   Worker will see damage in next state broadcast.
```

---

## Bandwidth Analysis

### Per-Player Bandwidth

| Direction | Data | Frequency | Size | Bandwidth |
|-----------|------|-----------|------|-----------|
| Worker → Server | Chunk report | 10 Hz | ~2 KB | ~20 KB/s |
| Server → Client | Chunk state | 10 Hz | ~1 KB | ~10 KB/s |
| Client → Server | Player input | 20 Hz | ~100 B | ~2 KB/s |
| Server → Client | Player positions | 20 Hz | ~200 B | ~4 KB/s |
| **Total per player** | | | | **~36 KB/s** |

### Server Bandwidth (200 players)

| Component | Calculation | Total |
|-----------|-------------|-------|
| Receiving reports | 200 × 20 KB/s | 4 MB/s in |
| Broadcasting state | 200 × 14 KB/s | 2.8 MB/s out |
| **Total** | | **~7 MB/s** |

This is manageable on a $20-40/mo VPS with 1 Gbps port.

---

## Server Load Analysis

### Without Distributed Compute (Traditional)

```
Server simulates ALL chunks:
- 20 chunks × 60 enemies = 1200 AI updates/tick
- 200 players position updates
- All physics calculations
- CPU: 80-100% on 4-core server
```

### With Distributed Compute

```
Server only validates:
- Receives 20 chunk reports/second (validation only)
- Broadcasts state (just copying data)
- Player action validation
- CPU: 20-30% on 4-core server

Workers do heavy lifting:
- Each player simulates 1-3 chunks
- AI runs on player CPUs
- Physics runs on player CPUs
- Your server bill: much lower
```

---

## Anti-Cheat Summary

| Threat | Prevention |
|--------|------------|
| Speed hack (enemies) | Server validates position delta vs max speed |
| Health hack | Server only allows health to decrease |
| Spawn hack | Server tracks expected enemy count per chunk |
| Loot hack | Server validates drops against enemy type/level |
| Damage hack | Damage RPCs go to server, not worker |
| Position hack (player) | Standard server-side position validation |

**Workers can't cheat because:**
1. They don't have authority - server validates everything
2. Player damage goes directly to server, bypassing worker
3. Loot is validated against expected drop tables
4. Suspicious patterns trigger reassignment + potential kick

---

## Implementation Phases

### Phase 1: Worker Assignment (1 week)
- [ ] ChunkWorkerManager on server
- [ ] Worker assignment/unassignment RPCs
- [ ] Basic chunk simulation on client
- [ ] Report submission system

### Phase 2: Validation Layer (1 week)
- [ ] Position validation
- [ ] Health validation
- [ ] Event validation
- [ ] Suspicious worker flagging

### Phase 3: Dynamic Expansion (3-4 days)
- [ ] Population tracking per chunk
- [ ] Expansion trigger logic
- [ ] Contraction with delay
- [ ] Level scaling for new chunks

### Phase 4: Failover & Polish (3-4 days)
- [ ] Worker disconnect handling
- [ ] Server fallback simulation
- [ ] Seamless reassignment
- [ ] Load balancing optimization

---

## File Structure

```
scripts/
├── networking/
│   ├── ChunkWorkerManager.gd   # Server: assigns workers to chunks
│   ├── ChunkStateValidator.gd  # Server: validates worker reports
│   ├── ChunkWorker.gd          # Client: runs chunk simulation
│   └── ChunkRenderer.gd        # Client: renders authoritative state
├── systems/
│   ├── DynamicChunkManager.gd  # Server: expansion/contraction
│   ├── ChunkSimulation.gd      # Shared: simulation logic
│   └── WorkerFailover.gd       # Server: handles disconnects
└── debug/
    └── ChunkDebugOverlay.gd    # Shows worker assignments, load
```

---

## Cost Comparison

| Model | 50 Players | 200 Players | 1000 Players |
|-------|------------|-------------|--------------|
| **Traditional (server does all)** | $25/mo | $100/mo | $500+/mo |
| **Distributed Compute** | $10/mo | $20-30/mo | $50-80/mo |

**Why it's cheaper:**
- Server CPU load is 70-80% lower
- Can use smaller/cheaper VPS
- Scales with player count automatically
- Players bring their own compute

---

## Summary

This architecture turns your players into a distributed compute cluster:

1. **Server is authoritative** - No cheating possible
2. **Players do the heavy lifting** - AI, physics run on their machines
3. **Server just validates** - Lightweight, cheap to host
4. **Dynamic scaling** - More players = more chunks = more workers
5. **Self-healing** - Worker disconnects are handled seamlessly

The world grows with your population and shrinks when quiet - and it costs you almost nothing extra either way.
