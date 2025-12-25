# Massive Battle Optimization Spec

## Goal

Support **100+ players in a single battle** with responsive PvP combat (sub-100ms hit registration).

---

## Current Bottlenecks

### 1. Naive Broadcasting (O(n²))
```
Current: Every player sends position to EVERY other player
50 players = 2,500 updates per tick
100 players = 10,000 updates per tick
200 players = 40,000 updates per tick  ← Server melts
```

### 2. Single-Threaded Godot Server
- All network processing on main thread
- Hit detection blocks other updates
- No parallelization of player processing

### 3. Full State Sync
- Sending complete position every frame
- No delta compression
- Wasted bandwidth on unchanged data

---

## Part 1: Interest Management (Priority 1)

Only sync entities within player's **Area of Interest (AOI)**.

### 1.1 AOI Radius

```gdscript
const AOI_RADIUS_FULL = 800      # Full sync (30 Hz) - combat range
const AOI_RADIUS_REDUCED = 1600  # Reduced sync (10 Hz) - visible but not fighting
const AOI_RADIUS_MINIMAL = 3200  # Minimal sync (2 Hz) - distant awareness
# Beyond 3200px = no sync until they get closer
```

### 1.2 Spatial Grid System

Divide world into cells for O(1) neighbor lookup:

```gdscript
# In NetworkManager.gd or new SpatialGrid.gd

class_name SpatialGrid
extends Node

const CELL_SIZE = 400  # pixels per cell

var cells: Dictionary = {}  # Vector2i -> Array[int] (player IDs)

func _get_cell(pos: Vector2) -> Vector2i:
    return Vector2i(int(pos.x / CELL_SIZE), int(pos.y / CELL_SIZE))


func update_player_cell(player_id: int, old_pos: Vector2, new_pos: Vector2) -> void:
    var old_cell = _get_cell(old_pos)
    var new_cell = _get_cell(new_pos)

    if old_cell != new_cell:
        # Remove from old cell
        if cells.has(old_cell):
            cells[old_cell].erase(player_id)

        # Add to new cell
        if not cells.has(new_cell):
            cells[new_cell] = []
        cells[new_cell].append(player_id)


func get_nearby_players(pos: Vector2, radius: float) -> Array[int]:
    var results: Array[int] = []
    var center_cell = _get_cell(pos)
    var cell_radius = int(ceil(radius / CELL_SIZE))

    # Check surrounding cells
    for dx in range(-cell_radius, cell_radius + 1):
        for dy in range(-cell_radius, cell_radius + 1):
            var check_cell = center_cell + Vector2i(dx, dy)
            if cells.has(check_cell):
                for player_id in cells[check_cell]:
                    # Fine-grained distance check
                    var player_pos = _get_player_position(player_id)
                    if pos.distance_to(player_pos) <= radius:
                        results.append(player_id)

    return results
```

### 1.3 Tiered Sync Rates

```gdscript
# In NetworkManager.gd

var player_sync_timers: Dictionary = {}  # player_id -> time_since_last_sync

func _process_network_tick() -> void:
    for player_id in connected_players:
        var player_pos = get_player_position(player_id)

        for other_id in connected_players:
            if other_id == player_id:
                continue

            var other_pos = get_player_position(other_id)
            var distance = player_pos.distance_to(other_pos)

            var sync_interval: float
            if distance <= AOI_RADIUS_FULL:
                sync_interval = 0.033  # 30 Hz - combat ready
            elif distance <= AOI_RADIUS_REDUCED:
                sync_interval = 0.1    # 10 Hz - visible
            elif distance <= AOI_RADIUS_MINIMAL:
                sync_interval = 0.5    # 2 Hz - awareness only
            else:
                continue  # Don't sync at all

            var key = "%d_%d" % [player_id, other_id]
            if not player_sync_timers.has(key):
                player_sync_timers[key] = 0.0

            player_sync_timers[key] += delta
            if player_sync_timers[key] >= sync_interval:
                _send_player_state(player_id, other_id)
                player_sync_timers[key] = 0.0
```

---

## Part 2: Delta Compression (Priority 2)

Only send what changed since last sync.

### 2.1 State Tracking

```gdscript
class PlayerNetState:
    var position: Vector2
    var velocity: Vector2
    var facing: int  # 0-3 direction
    var animation: StringName
    var health_percent: int  # 0-100, not float
    var is_attacking: bool
    var target_id: int

    func get_delta(previous: PlayerNetState) -> Dictionary:
        var delta = {}

        # Position: only if moved more than 2px
        if position.distance_to(previous.position) > 2.0:
            delta["p"] = [int(position.x), int(position.y)]  # Ints save bytes

        # Facing: only if changed
        if facing != previous.facing:
            delta["f"] = facing

        # Animation: only if changed
        if animation != previous.animation:
            delta["a"] = animation

        # Health: only if changed (and compress to 0-100)
        if health_percent != previous.health_percent:
            delta["h"] = health_percent

        # Combat state
        if is_attacking != previous.is_attacking:
            delta["atk"] = is_attacking

        return delta  # Empty dict = no update needed
```

### 2.2 Packet Size Comparison

```
Full state packet:    ~80 bytes per player
Delta packet (moving): ~20 bytes
Delta packet (idle):   ~0 bytes (skip entirely)

100 players, full sync:  8,000 bytes/tick
100 players, delta sync: ~1,500 bytes/tick (80% reduction)
```

---

## Part 3: Combat Priority Queue (Priority 2)

PvP actions get processed and synced IMMEDIATELY, everything else can wait.

### 3.1 Event Priority Levels

```gdscript
enum NetPriority {
    CRITICAL,   # Damage dealt, deaths, CC applied - IMMEDIATE
    HIGH,       # Attack started, ability used - next tick
    NORMAL,     # Position updates - batched
    LOW         # Cosmetic, emotes - when bandwidth available
}

var priority_queues: Array[Array] = [[], [], [], []]

func queue_event(event: Dictionary, priority: NetPriority) -> void:
    priority_queues[priority].append(event)


func _process_network_tick() -> void:
    # Always process ALL critical events
    for event in priority_queues[NetPriority.CRITICAL]:
        _send_event_immediate(event)
    priority_queues[NetPriority.CRITICAL].clear()

    # Process high priority if we have bandwidth
    var remaining_bandwidth = MAX_TICK_BYTES - _bytes_sent_this_tick
    # ... process HIGH, then NORMAL, then LOW based on remaining bandwidth
```

### 3.2 Combat Events Are Critical

```gdscript
func _on_player_dealt_damage(attacker_id: int, target_id: int, damage: int) -> void:
    queue_event({
        "type": "damage",
        "a": attacker_id,
        "t": target_id,
        "d": damage,
        "time": Time.get_ticks_msec()
    }, NetPriority.CRITICAL)


func _on_player_died(player_id: int, killer_id: int) -> void:
    queue_event({
        "type": "death",
        "p": player_id,
        "k": killer_id
    }, NetPriority.CRITICAL)
```

---

## Part 4: Efficient Hit Detection (Priority 3)

Replace O(n²) collision checks with spatial hashing.

### 4.1 Attack Validation

```gdscript
func validate_attack(attacker_id: int, claimed_target_id: int) -> bool:
    var attacker_pos = get_player_position(attacker_id)
    var attack_range = get_player_attack_range(attacker_id)

    # Only check players in nearby cells (not ALL players)
    var nearby = SpatialGrid.get_nearby_players(attacker_pos, attack_range + 50)

    if claimed_target_id in nearby:
        var target_pos = get_player_position(claimed_target_id)
        if attacker_pos.distance_to(target_pos) <= attack_range:
            return true

    return false  # Reject invalid hit claim
```

### 4.2 AoE Damage

```gdscript
func process_aoe_damage(center: Vector2, radius: float, damage: int, source_id: int) -> void:
    # Spatial grid makes this O(nearby) instead of O(all_players)
    var affected = SpatialGrid.get_nearby_players(center, radius)

    for player_id in affected:
        if player_id == source_id:
            continue
        apply_damage(player_id, damage, source_id)
```

---

## Part 5: Server Threading (Priority 4)

Move expensive operations off main thread.

### 5.1 Thread Pool for Network

```gdscript
# Godot 4 threading

var network_thread: Thread
var physics_thread: Thread

func _ready() -> void:
    network_thread = Thread.new()
    network_thread.start(_network_thread_loop)


func _network_thread_loop() -> void:
    while running:
        _process_incoming_packets()
        _build_outgoing_packets()
        OS.delay_msec(16)  # ~60 Hz


func _process_incoming_packets() -> void:
    # Parse packets, validate, queue for main thread
    var packets = _get_pending_packets()
    for packet in packets:
        var validated = _validate_packet(packet)  # Can be expensive
        if validated:
            _main_thread_queue.push(validated)
```

### 5.2 What Can Be Threaded

| Operation | Threadable | Notes |
|-----------|------------|-------|
| Packet parsing | Yes | Pure data, no scene access |
| Delta compression | Yes | Just math |
| Spatial grid updates | Mutex | Need sync with main thread |
| Hit validation | Partial | Read-only scene access |
| State application | No | Must be main thread |
| Scene tree changes | No | Must be main thread |

---

## Part 6: Client-Side Prediction (Priority 4)

Reduce perceived latency for local player.

### 6.1 Movement Prediction

```gdscript
# Client predicts own movement, server corrects if wrong

var predicted_position: Vector2
var server_position: Vector2
var pending_inputs: Array[Dictionary] = []

func _physics_process(delta: float) -> void:
    # Apply input locally immediately
    var input = _get_current_input()
    predicted_position = _apply_movement(predicted_position, input, delta)

    # Send input to server
    pending_inputs.append({
        "seq": input_sequence,
        "input": input,
        "time": Time.get_ticks_msec()
    })
    _send_input_to_server(input, input_sequence)
    input_sequence += 1


func _on_server_state_received(server_state: Dictionary) -> void:
    var acked_seq = server_state["ack_seq"]
    server_position = Vector2(server_state["x"], server_state["y"])

    # Remove acknowledged inputs
    pending_inputs = pending_inputs.filter(func(i): return i["seq"] > acked_seq)

    # Re-predict from server state + unacked inputs
    var reconciled_pos = server_position
    for pending in pending_inputs:
        reconciled_pos = _apply_movement(reconciled_pos, pending["input"], 0.016)

    # Snap or interpolate to reconciled position
    if predicted_position.distance_to(reconciled_pos) > 50:
        predicted_position = reconciled_pos  # Hard snap (we were wrong)
    else:
        predicted_position = predicted_position.lerp(reconciled_pos, 0.3)
```

---

## Part 7: Sharding Strategy (Fallback)

If single server can't handle the battle, shard dynamically.

### 7.1 Zone Sharding

```
Zone 1 hits 80 players:
├── Zone 1-A (West half, X: 0-12000)
└── Zone 1-B (East half, X: 12000-24000)

Players near boundary (X: 11000-13000) exist on BOTH shards
Cross-shard combat syncs through backend API
```

### 7.2 Battle Instance Sharding

```
Massive battle detected (50+ in 2000px radius):
1. Spin up battle instance server
2. Migrate combatants to instance
3. Instance handles high-frequency sync
4. Return players to main shard when battle ends
```

---

## Implementation Priority

### Phase 1: Quick Wins (1-2 days)
- [ ] Implement SpatialGrid for O(1) neighbor lookup
- [ ] Add AOI radius - stop syncing distant players
- [ ] Combat priority queue - damage/deaths always immediate

### Phase 2: Bandwidth Optimization (2-3 days)
- [ ] Delta compression for position updates
- [ ] Tiered sync rates by distance
- [ ] Compress integers, remove floats from packets

### Phase 3: Server Performance (3-5 days)
- [ ] Thread pool for packet processing
- [ ] Spatial hash for hit detection
- [ ] Profile and optimize hot paths

### Phase 4: Client Feel (2-3 days)
- [ ] Client-side movement prediction
- [ ] Server reconciliation
- [ ] Interpolation for other players

### Phase 5: Scaling (if needed)
- [ ] Dynamic zone sharding
- [ ] Battle instance servers
- [ ] Cross-shard combat sync

---

## Target Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Max players (responsive PvP) | ~50 | **150+** |
| Tick rate at 100 players | ~10 Hz | **30 Hz** |
| Bandwidth per player | ~8 KB/s | **2 KB/s** |
| Hit registration latency | ~150ms | **<80ms** |
| Server CPU at 100 players | 100% | **<60%** |

---

## Testing Massive Battles

### Bot Stress Test

```gdscript
# Create N bot clients that move and attack randomly
func spawn_test_bots(count: int) -> void:
    for i in count:
        var bot = BotPlayer.new()
        bot.position = Vector2(randf_range(0, 24000), randf_range(0, 8000))
        bot.behavior = "aggressive"  # Constantly attack nearby
        add_child(bot)
```

### Metrics to Monitor

```gdscript
func _log_performance() -> void:
    print("Players: %d" % connected_players.size())
    print("Tick time: %.2fms" % (tick_end - tick_start))
    print("Packets/sec: %d" % packets_this_second)
    print("Bytes/sec: %d KB" % (bytes_this_second / 1024))
    print("Dropped packets: %d" % dropped_packets)
```

---

## Summary

**The key insight:** Don't sync everything to everyone.

1. **Spatial grid** - O(1) "who's nearby?" queries
2. **AOI radius** - Ignore distant players
3. **Delta compression** - Only send changes
4. **Priority queue** - Combat first, cosmetics last
5. **Threading** - Parse packets off main thread

With these optimizations, 150+ player battles should be achievable on current hardware.
