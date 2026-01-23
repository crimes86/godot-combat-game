# Global Battlefield Design

## Vision

A massively scalable real-time combat system where:
- **Infinite scale**: Battle size limited only by server budget (just spin up more)
- **Global participation**: Players from any region can fight together fairly
- **Fair latency**: All players experience normalized 200ms perceived latency regardless of geographic location
- **Country vs Country**: Enable literal nation-scale conflicts in real-time

**Design Philosophy**: The server infrastructure should be invisible. A player in Tokyo fighting a player in New York should feel no different than two players in the same city.

---

## Core Problems to Solve

### 1. Latency Normalization (Solved in v1)

**Problem**: A player with 20ms RTT has massive advantage over 200ms RTT player.

**Solution**: Baseline all players at 200ms perceived latency.
- Client predicts locally for instant feedback
- Server validates asynchronously
- Low-latency players have their actions "held" to match high-latency players
- Result: Everyone experiences the same 200ms action-to-confirmation window

**Status**: ✅ Foundation implemented (client prediction, server reconciliation)

**Remaining Work**:
- [ ] Explicit latency measurement per player
- [ ] Server-side action queuing for low-latency players
- [ ] Latency normalization algorithm

---

### 2. Spatial Sharding (Horizontal Scale)

**Problem**: One server can only handle N players/enemies before physics/networking breaks down.

**Solution**: Divide the world into zones, each owned by a dedicated server.

```
┌─────────────────────────────────────────────────────┐
│                   GLOBAL WORLD                       │
├─────────────┬─────────────┬─────────────┬───────────┤
│   Zone A    │   Zone B    │   Zone C    │  Zone D   │
│  Server 1   │  Server 2   │  Server 3   │ Server 4  │
│  (50 players)│ (50 players)│ (200 players)│(50 players)│
└─────────────┴─────────────┴─────────────┴───────────┘
```

**Key Challenges**:
- **Handoff**: Player moving from Zone A to Zone B
- **Border Combat**: Two players fighting across zone boundary
- **Load Balancing**: Dynamic zone splitting when one area gets crowded
- **State Sync**: Zones need to share state at boundaries

---

### 3. Cross-Zone Combat

**Problem**: Player in Zone A attacks player in Zone B. Which server is authoritative?

**Possible Solutions**:

**Option A: Boundary Overlap**
- Zones overlap by X meters at boundaries
- Both servers simulate entities in overlap region
- Primary authority based on entity's "home" zone

**Option B: Combat Arbiter**
- Dedicated server handles cross-zone combat resolution
- Adds latency but ensures consistency

**Option C: Temporary Migration**
- When combat starts across boundary, both entities migrate to same zone
- Zone boundary shifts dynamically

---

### 4. Global State Coordination

**Problem**: Some state must be globally consistent (leaderboards, territory control, world events).

**Solution**: Hierarchical state management

```
┌────────────────────────────────────────┐
│         GLOBAL COORDINATOR             │
│   (Territory, Events, Leaderboards)    │
└──────────────────┬─────────────────────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
┌────▼────┐  ┌────▼────┐  ┌────▼────┐
│ Region  │  │ Region  │  │ Region  │
│  NA     │  │  EU     │  │  ASIA   │
└────┬────┘  └────┬────┘  └────┬────┘
     │            │            │
   Zones        Zones        Zones
```

- Zone servers handle moment-to-moment combat (authoritative for their area)
- Region coordinators aggregate zone state
- Global coordinator handles world-level events

---

## Technical Architecture

### Server Types

| Server Type | Responsibility | Scale |
|-------------|----------------|-------|
| **Zone Server** | Physics, combat, AI for one area | 50-200 players |
| **Region Coordinator** | Zone management, player routing | 1 per geographic region |
| **Global Coordinator** | World state, events, matchmaking | 1 globally (replicated) |
| **Gateway** | Player connection, routing to correct zone | Multiple per region |

### Player Connection Flow

```
1. Player connects to nearest Gateway (low latency)
2. Gateway authenticates, determines player's zone
3. Gateway routes player to correct Zone Server
4. Player receives zone state, begins play
5. If player moves to new zone:
   a. Current zone notifies Region Coordinator
   b. Region Coordinator notifies new zone
   c. Player state handed off
   d. Gateway re-routes connection
```

---

## Latency Normalization Deep Dive

### The 200ms Baseline

**Why 200ms?**
- Covers ~95% of global player connections
- Still feels responsive with prediction
- Matches natural human reaction time floor

### Implementation Approach

```
Player A (20ms RTT) attacks Player B (180ms RTT)

WITHOUT normalization:
- A's attack registers in 20ms
- B doesn't see it for 180ms
- B is already dead before they can react

WITH normalization:
- A's attack is "held" for 180ms (200ms - 20ms)
- Both players see the attack at ~200ms from A's input
- Fair fight
```

### Client-Side Prediction Still Works

Even with normalization, clients predict locally:
- Player A presses attack, sees swing immediately (0ms)
- Server holds the action for 180ms
- At 200ms mark, server broadcasts to all
- Player A sees "confirmation" (damage numbers, etc.)
- Player B sees attack and has same reaction window

**Key Insight**: The prediction is for FEEL, normalization is for FAIRNESS.

---

## Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Game Mode | **Instanced** (for now) | Test the sync tech first, persistent world later |
| Handoff | **Seamless** | No loading screens, invisible zone transitions |
| Countries | **IP-based nations** | Literal geographic nations, not guilds |
| Scale | **TBD** | See tradeoff analysis below |

---

## Scale Tradeoff Analysis: 1,000 vs 10,000 Players

### The Physics Budget

Every player in a zone requires:
- Position sync: ~50 bytes × 20Hz = 1 KB/s
- Combat events: ~100 bytes × sporadic = 0.2 KB/s
- State updates: ~200 bytes × 2Hz = 0.4 KB/s
- **Per-player bandwidth: ~1.6 KB/s**

| Scale | Bandwidth (per zone server) | Physics Ticks |
|-------|----------------------------|---------------|
| 100 players | 160 KB/s | 60 Hz easy |
| 500 players | 800 KB/s | 60 Hz possible |
| 1,000 players | 1.6 MB/s | 30 Hz realistic |
| 5,000 players | 8 MB/s | 20 Hz, start culling |
| 10,000 players | 16 MB/s | 10 Hz, heavy culling |

### What Gets Sacrificed at 10k

| Feature | 1,000 players | 10,000 players |
|---------|---------------|----------------|
| Physics tick rate | 30 Hz | 10-15 Hz |
| Combat precision | Frame-perfect | 66-100ms windows |
| Visual fidelity | Full animations | Simplified at distance |
| Individual impact | High (you matter) | Low (zerg tactics) |
| Server cost | $50-100/battle | $500-1000/battle |
| Sync complexity | Manageable | Aggressive LOD required |

### Level of Detail (LOD) for Scale

At 10k, you CANNOT sync every player to every player. Solution: **Interest Management**

```
┌─────────────────────────────────────────────────────┐
│                    BATTLEFIELD                       │
│                                                      │
│   [You] ◄── Full sync (50m radius, ~100 players)    │
│      │                                               │
│      └── Medium sync (200m, positions only, ~500)   │
│          │                                           │
│          └── Aggregate sync (1km+, "blob" of enemies)│
│                                                      │
└─────────────────────────────────────────────────────┘
```

**Close (0-50m)**: Full player data, animations, combat
**Medium (50-200m)**: Positions, team colors, no animations
**Far (200m+)**: Aggregate "there are 847 enemies in that direction"

### Recommendation

**Start with 1,000 player target.** Reasons:
1. Still unprecedented for real-time action combat
2. Each player's actions feel meaningful
3. 30Hz physics is acceptable for our combat style
4. Server costs are reasonable for testing
5. Can scale UP later by adding LOD, harder to scale DOWN

**Stretch goal: 5,000** with aggressive LOD. Beyond that, you're in EVE territory (time dilation, not real-time).

---

## IP-Based Nations

### How It Works

```
Player connects
    │
    ▼
Gateway extracts IP
    │
    ▼
GeoIP lookup (MaxMind/IP2Location)
    │
    ▼
Country code (US, JP, DE, BR, etc.)
    │
    ▼
Player assigned to nation faction
```

### Technical Implementation

```gdscript
# Server-side (Gateway or Auth server)
func determine_nation(ip_address: String) -> String:
    # Use GeoIP database (MaxMind GeoLite2 is free)
    var country_code = geoip_lookup(ip_address)
    return country_code  # "US", "JP", "DE", etc.
```

### Design Considerations

**Pros:**
- Zero friction - automatic team assignment
- Real national pride/rivalry
- Genuine "country vs country" feeling
- Natural load balancing (populations correlate to player counts)

**Cons:**
- VPN users can spoof (accept this? or detect/block?)
- Expatriates fight "against" their home country
- Small countries may be outnumbered
- Political sensitivity (some countries blocked/sanctioned)

### Handling Population Imbalance

| Country | Est. Gamers | Problem |
|---------|-------------|---------|
| China | 600M+ | Would dominate everything |
| USA | 150M | Large but manageable |
| Germany | 35M | Medium |
| Iceland | 200K | Tiny, always loses? |

**Solutions:**
1. **Regional matchmaking**: Asia vs Asia, West vs West initially
2. **Alliance system**: Small countries can ally
3. **Handicap scaling**: Outnumbered team gets buffs
4. **Contribution-based**: Individual performance matters, not just numbers

---

## Seamless Zone Handoff Protocol

### The Hard Problem

Player is running at full speed. They cross invisible zone boundary. They should notice NOTHING.

### Handoff Sequence

```
Timeline: Player moving from Zone A → Zone B
─────────────────────────────────────────────────────────

T-500ms: Player approaching boundary
         Zone A: "Player X heading toward Zone B"
         Zone A → Region Coordinator: HANDOFF_PREPARE

T-200ms: Player in "overlap region" (both zones aware)
         Region Coordinator → Zone B: HANDOFF_INCOMING
         Zone B: Pre-spawns player entity (invisible)

T-0ms:   Player crosses boundary
         Zone A: Still authoritative, still simulating
         Zone B: Receiving position updates, ready to take over

T+50ms:  Boundary confirmed crossed
         Region Coordinator: HANDOFF_EXECUTE
         Zone B: Takes authority, entity becomes real
         Zone A: Entity becomes "ghost" (still visible to Zone A players)

T+200ms: Player fully in Zone B
         Zone A: Removes ghost entity
         Gateway: Re-routes player connection to Zone B

T+500ms: Handoff complete, Zone A forgets player
```

### The Overlap Region

```
        Zone A                    Zone B
    ┌────────────┐            ┌────────────┐
    │            │            │            │
    │            │◄── 50m ──►│            │
    │            │  OVERLAP   │            │
    │     ●──────┼────────────┼──────►     │
    │   player   │            │            │
    │            │            │            │
    └────────────┘            └────────────┘
```

Both zones simulate the overlap region. Authority is determined by which side of the CENTER LINE the player is on.

### Gateway Connection Handling

The Gateway maintains a persistent connection to the player. It proxies to whichever Zone Server is authoritative:

```
Player ◄──── persistent ────► Gateway ◄──── switches ────► Zone A/B
```

Player's connection never drops. Gateway just starts routing packets to new zone.

---

## Instanced Battle Design (Phase 1)

Since we're starting with instanced battles to test the tech:

### Battle Lifecycle

```
1. MATCHMAKING
   - Players queue for "Global Battle"
   - System groups by region/nation
   - Minimum players reached (e.g., 100 per side)

2. INSTANCE CREATION
   - Spin up Zone Servers for this battle
   - Create battlefield map
   - Assign spawn points per nation

3. BATTLE PHASE
   - 15-30 minute time limit
   - Objective-based (capture points, eliminate, etc.)
   - Real-time combat with all the sync tech

4. RESOLUTION
   - Winner determined
   - Stats recorded (per-player, per-nation)
   - Instance torn down
   - Servers returned to pool
```

### Battle Types

| Type | Players | Duration | Objective |
|------|---------|----------|-----------|
| Skirmish | 100 vs 100 | 10 min | Team deathmatch |
| Siege | 500 vs 500 | 30 min | Capture the fortress |
| World War | 1000+ | 60 min | Multi-objective campaign |

---

## Prior Art / Research

- **EVE Online**: Single-shard, time dilation at scale
- **PlanetSide 2**: Continental warfare, ~2000 players per continent
- **World of Warcraft**: Sharded zones, seamless handoff
- **Fortnite**: 100 players, single authoritative server, aggressive prediction

---

## Fundamental Innovations for Mass Scale

### The Core Problem

Traditional networking: **O(N²) complexity**
- N players each need updates about N-1 others
- 1,000 players = 999,000 update pairs per tick
- 10,000 players = 99,990,000 update pairs per tick

**Every existing solution tries to reduce N** (interest management, LOD, zones).

What if we attacked the problem differently?

---

### Innovation 1: Behavioral Sync (Not Positional)

**Current approach**: Send position 20x/second
```
{player_id: 1, x: 1024.5, y: 892.3, anim: "walk_right"}  // 50 bytes × 20Hz = 1KB/s
```

**New approach**: Send behavior model, client simulates locally
```
{player_id: 1, behavior: "aggressive_melee", target: 47, skill: 0.7}  // 20 bytes × 2Hz = 40B/s
```

Client runs simple AI prediction:
- "Aggressive melee player targeting enemy 47 with 0.7 skill"
- Client simulates: moves toward target, attacks when in range
- Occasional correction packets when prediction diverges

**Reduction**: 25x less bandwidth for distant players

**Tradeoff**: Distant players aren't pixel-perfect, but who cares? You can't see them anyway.

---

### Innovation 2: Hierarchical Authority (Squad Delegation)

**Current**: Server authoritative for all 10,000 players

**New**: Hierarchical command structure
```
           ┌─────────────┐
           │   SERVER    │  (Authoritative for 100 squad leaders)
           └──────┬──────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼───┐    ┌───▼───┐    ┌───▼───┐
│Squad 1│    │Squad 2│    │Squad 3│  (Squad leaders authoritative for 10 members)
│Leader │    │Leader │    │Leader │
└───┬───┘    └───┬───┘    └───┬───┘
    │            │            │
  10 players   10 players   10 players
```

- Server only tracks 100 squad leaders (not 1,000 individuals)
- Squad leader's client is authoritative for their squad's positions
- Server validates squad-level outcomes, not individual actions

**Reduction**: 10x less server load

**Tradeoff**: Trust squad leader's client (anti-cheat at squad level, not individual)

---

### Innovation 3: Outcome Authority (Not Action Authority)

**Current**: Server validates every sword swing
```
Client: "I attack player 47"
Server: Validates range, cooldowns, damage calculation
Server: "Hit confirmed, 45 damage"
```

**New**: Server only validates outcomes, not actions
```
Client A & B: Enter combat
Server: "Combat instance started between A and B"
... clients fight locally, both predict ...
Client A: "Combat ended, I won, B has 0 HP"
Client B: "Combat ended, I lost, I have 0 HP"
Server: "Consensus reached, A wins" (or arbitrate if disagreement)
```

For mass battles:
```
Server: "100 players from Team A vs 80 from Team B in Zone 7"
Server: Simulates statistical outcome based on aggregate skill/gear
Server: "Team A wins, 67 survive, Team B: 12 survive"
Clients: Receive survivor list, animate deaths for non-survivors
```

**Reduction**: Server does 1 calculation instead of 10,000 per combat

**Tradeoff**: Individual skill matters less in large battles (historically accurate?)

---

### Innovation 4: Fog of War as Optimization

**Current**: Everyone knows everything, LOD hides distant detail

**New**: Information is power - you literally don't receive data about hidden enemies

```
┌─────────────────────────────────────────────┐
│              BATTLEFIELD                     │
│                                              │
│   [Team A]          ???          [Team B]   │
│   Full sync      No data         Full sync  │
│                                              │
│         Scout reveals small area            │
│              ┌─────┐                        │
│              │Scout│──► Limited data about  │
│              └─────┘    enemies in vision   │
└─────────────────────────────────────────────┘
```

- You only receive enemy data if YOUR team has vision
- Scouts/recon become gameplay-critical, not just flavor
- Removes 50%+ of sync traffic (enemy team data)

**Reduction**: 50% bandwidth instantly

**Tradeoff**: Gameplay change - requires team coordination, scouting

---

### Innovation 5: Deterministic Lockstep (RTS-style)

**Current**: FPS-style authoritative server, send positions

**New**: RTS-style deterministic simulation
```
All clients run identical simulation
Only sync: player INPUTS (not positions)
1000 players × 10 inputs/sec × 8 bytes = 80 KB/s total (not per player!)
```

Every client:
1. Receives all player inputs for frame N
2. Simulates frame N identically (deterministic)
3. All clients arrive at same world state

**Reduction**: Bandwidth independent of player count (just input count)

**Tradeoff**:
- Requires deterministic physics (no floating point variance)
- Latency = slowest player (or drop them)
- Cheating = desync detection

---

### Innovation 6: Probabilistic State Sync

**Current**: Exact positions for everyone

**New**: Statistical approximations for distant entities
```
Instead of: "Player 47 is at (1024, 892)"
Send:       "~50 enemies in sector 7, center of mass (1100, 900), spread 200m"
```

Client renders a "blob" of enemies, individual positions are locally randomized within distribution. As you get closer, individuals resolve from the probability cloud.

**Like**: Quantum mechanics - observation collapses the wavefunction

**Reduction**: O(sectors) instead of O(players)

**Tradeoff**: Distant combat is statistical, not individual

---

### Innovation 7: Client Mesh Networking

**Current**: Server broadcasts to all clients (star topology)
```
        ┌─────────┐
        │ Server  │
        └────┬────┘
    ┌────┬───┼───┬────┐
    ▼    ▼   ▼   ▼    ▼
   C1   C2  C3  C4   C5   (Server sends to each)
```

**New**: Clients relay to nearby clients (mesh topology)
```
   C1 ◄──► C2 ◄──► C3
    ▲       ▲       ▲
    │       │       │
    ▼       ▼       ▼
   C4 ◄──► C5 ◄──► C6
    │
    ▼
  Server (only validates, doesn't broadcast)
```

- Clients relay position updates to geographic neighbors
- Server only handles: validation, authoritative state, conflict resolution
- Like BitTorrent for game state

**Reduction**: Server bandwidth O(1) instead of O(N)

**Tradeoff**: P2P complexity, NAT traversal, trust issues

---

### Innovation 8: Time-Dilated Zones

**Current**: Force all zones to run at same tick rate

**New**: Let busy zones slow down, empty zones run fast
```
Zone A: 2000 players, running at 15Hz (time dilated)
Zone B: 50 players, running at 60Hz (real-time)
```

At zone boundaries, interpolate between time scales. Players in Zone A experience "bullet time" when it's overloaded.

**EVE Online does this** - it's proven at scale.

**Tradeoff**: Time dilation feels weird in action combat (works for EVE's strategic pace)

---

### Innovation 9: Eventual Consistency (Not Strong Consistency)

**Current**: All clients must agree on world state every frame

**New**: Clients can diverge, reconcile periodically
```
Frame 1-60: Clients simulate independently
Frame 61:   Server sends "checkpoint" - authoritative state
            Clients snap to checkpoint, continue
```

Between checkpoints, clients predict. Prediction errors are corrected at checkpoint.

**Like**: Git branches - work independently, merge periodically

**Reduction**: 60x less sync traffic (1Hz checkpoints vs 60Hz state)

**Tradeoff**: Visible "corrections" at checkpoint (smooth with interpolation)

---

### Innovation 10: Combat Commitment Windows

**Current**: Validate every 16ms action

**New**: Actions are "committed" in 200ms windows
```
Window 1 (0-200ms):    Collect all player inputs
Window 2 (200-400ms):  Server processes Window 1, broadcast results
                       Clients animate Window 1 results
                       Meanwhile: collect Window 2 inputs
```

- Natural 200ms latency baked into design
- All players equally "delayed" = fair
- Server processes in batches = efficient

**Reduction**: 5x less processing (batched vs per-frame)

**This is what we already proposed** for latency normalization - it's also a scaling solution.

---

### Combining Innovations

The real power is combining these:

```
MEGA-SCALE ARCHITECTURE (50,000+ players)
─────────────────────────────────────────

1. Fog of War: Only sync visible enemies (50% reduction)
2. Behavioral Sync: Distant = behavior model (25x reduction)
3. Probabilistic State: Very distant = statistical blob
4. Hierarchical Authority: Squads reduce server entity count 10x
5. Outcome Authority: Mass battles = statistical resolution
6. Commitment Windows: 200ms batches, naturally fair

Result:
- Server tracks ~500 squad leaders (not 50,000 individuals)
- Bandwidth: ~100KB/s instead of 80MB/s
- Fair latency: Everyone at 200ms baseline
- Scales horizontally: Add zones as needed
```

---

### Which Innovations Are Novel?

| Innovation | Used Today? | Novel Aspect |
|------------|-------------|--------------|
| Behavioral Sync | Partially (NPC AI) | Apply to distant PLAYERS |
| Hierarchical Authority | No | Player-as-server for squad |
| Outcome Authority | No | Statistical combat resolution |
| Fog of War Optimization | Partial | As PRIMARY scaling strategy |
| Deterministic Lockstep | RTS games | Apply to action combat |
| Probabilistic State | No | Quantum-inspired sync |
| Client Mesh | Some P2P games | Hybrid with authoritative |
| Time Dilation | EVE only | Apply to action combat |
| Eventual Consistency | Databases | Apply to games |
| Commitment Windows | Fighting games | At 200ms for MMO scale |

**Most novel combination**: Behavioral Sync + Probabilistic State + Fog of War

"Enemies you can't see are simulated locally from behavior models. Enemies you can barely see are probability clouds. Only nearby enemies are precisely synced."

---

## Testing at Scale

### The Problem

You can't find 1,000 friends to test with. But you need to validate:
- Server handles 1,000 concurrent connections
- Latency normalization works across regions
- Zone handoffs are seamless
- Combat feels fair at 200ms

### The Solution: Headless Bot Clients

Create "fake players" that:
- Connect to server with real network stack
- Simulate realistic movement patterns
- Execute combat actions
- Report metrics back

```
┌─────────────────────────────────────────────────────┐
│                 BOT ORCHESTRATOR                     │
│         (Spawns/controls thousands of bots)          │
└─────────────────────┬───────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
   ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
   │ Bot VM  │   │ Bot VM  │   │ Bot VM  │
   │ (100)   │   │ (100)   │   │ (100)   │
   │ Tokyo   │   │ Frankfurt│  │ Virginia│
   └────┬────┘   └────┬────┘   └────┬────┘
        │             │             │
        └─────────────┼─────────────┘
                      │
                      ▼
              ┌───────────────┐
              │  GAME SERVER  │
              │  (Under Test) │
              └───────────────┘
```

### Headless Client Architecture

```gdscript
# scripts/testing/headless_bot.gd
extends Node

## Headless bot - no rendering, just network + AI

var peer: ENetMultiplayerPeer
var bot_id: int
var target_position: Vector2
var current_state: String = "wandering"
var attack_target: int = -1

# Configurable behavior
var aggression: float = 0.5  # 0 = passive, 1 = always fighting
var skill_level: float = 0.5  # Reaction time, aim accuracy
var latency_sim_ms: int = 0  # Artificial latency to simulate region

func _ready():
    # No rendering - headless mode
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func connect_to_server(address: String, port: int, simulated_latency: int = 0):
    latency_sim_ms = simulated_latency
    peer = ENetMultiplayerPeer.new()
    peer.create_client(address, port)
    multiplayer.multiplayer_peer = peer

func _physics_process(delta):
    match current_state:
        "wandering":
            _wander_behavior(delta)
        "seeking":
            _seek_enemy(delta)
        "combat":
            _combat_behavior(delta)
        "fleeing":
            _flee_behavior(delta)

    # Simulate latency by delaying outgoing packets
    if latency_sim_ms > 0:
        await get_tree().create_timer(latency_sim_ms / 1000.0).timeout

    _send_position_update()

func _wander_behavior(delta):
    # Random movement, occasionally switch to seeking
    if randf() < 0.01 * aggression:
        current_state = "seeking"

func _combat_behavior(delta):
    # Attack logic - skill_level affects timing
    var reaction_delay = lerp(0.5, 0.1, skill_level)
    # ... attack patterns
```

### Bot Behavior Profiles

Different bots simulate different player types:

| Profile | Aggression | Skill | Movement | Purpose |
|---------|------------|-------|----------|---------|
| Newbie | 0.3 | 0.2 | Erratic | Test low-skill chaos |
| Average | 0.5 | 0.5 | Normal | Baseline behavior |
| Tryhard | 0.8 | 0.8 | Optimal | Test high-skill combat |
| AFK | 0.0 | 0.0 | None | Test idle connections |
| Zerg | 1.0 | 0.3 | Blobbing | Test mass combat |

### Staged Scale Testing

Don't jump to 1,000. Validate at each stage:

```
Stage 1: 10 bots (local machine)
├── Verify basic connectivity
├── Confirm combat sync works
└── Baseline metrics

Stage 2: 50 bots (local machine)
├── First stress on physics
├── Identify obvious bottlenecks
└── Tune tick rates

Stage 3: 100 bots (2-3 VMs)
├── Real network latency enters
├── Test cross-region sync
└── Zone handoff testing

Stage 4: 500 bots (10 VMs across regions)
├── Serious load testing
├── Interest management validation
└── Bandwidth profiling

Stage 5: 1000 bots (20+ VMs)
├── Full scale validation
├── Latency normalization testing
└── Cost projection accuracy
```

### Geographic Distribution

Spin up bot VMs in different cloud regions to test real latency:

| Cloud Region | Simulates | Latency to US-East |
|--------------|-----------|-------------------|
| us-east-1 | East Coast US | 10-20ms |
| us-west-2 | West Coast US | 60-80ms |
| eu-west-1 | Europe | 80-100ms |
| ap-northeast-1 | Japan | 150-180ms |
| ap-southeast-1 | Singapore | 200-250ms |
| sa-east-1 | Brazil | 120-150ms |

**Cost estimate**: 20 VMs × $0.10/hr × 4 hours = ~$8 per full-scale test

### Metrics to Collect

```gdscript
# Bot reports these metrics to orchestrator
var metrics = {
    "bot_id": bot_id,
    "region": simulated_region,
    "rtt_ms": current_rtt,
    "perceived_latency_ms": time_to_damage_confirm,
    "position_desync_m": distance_from_server_position,
    "combat_events_per_sec": combat_rate,
    "zone_handoff_ms": last_handoff_duration,
    "packet_loss_pct": lost_packets / total_packets,
}
```

### Orchestrator Dashboard

```
┌─────────────────────────────────────────────────────────┐
│              SCALE TEST DASHBOARD                        │
├─────────────────────────────────────────────────────────┤
│ Connected Bots: 847/1000     Server CPU: 67%            │
│ Avg RTT: 142ms               Server RAM: 2.1GB          │
│ Avg Perceived Latency: 198ms Bandwidth: 1.2 MB/s        │
├─────────────────────────────────────────────────────────┤
│ Region Breakdown:                                        │
│   US-East:  203 bots, 18ms avg RTT                      │
│   US-West:  198 bots, 72ms avg RTT                      │
│   EU:       156 bots, 94ms avg RTT                      │
│   Japan:    189 bots, 168ms avg RTT                     │
│   Brazil:   101 bots, 134ms avg RTT                     │
├─────────────────────────────────────────────────────────┤
│ Alerts:                                                  │
│   ⚠️  3 bots experiencing >300ms latency                │
│   ✅ Zone handoffs averaging 487ms (target: <500ms)     │
│   ✅ Combat fairness index: 0.94 (target: >0.90)        │
└─────────────────────────────────────────────────────────┘
```

### Automated Test Scenarios

```gdscript
# test_scenarios.gd

func test_mass_combat():
    """500 bots converge on single point - stress test"""
    orchestrator.set_all_bots_target(Vector2(5000, 5000))
    orchestrator.set_all_bots_aggressive(1.0)
    await orchestrator.wait_for_convergence(timeout=60)
    assert metrics.server_tick_rate >= 20, "Tick rate dropped below 20Hz"

func test_zone_boundary_rush():
    """200 bots cross zone boundary simultaneously"""
    var boundary = Vector2(10000, 5000)  # Zone A/B boundary
    orchestrator.position_bots_near(boundary, count=200, spread=100)
    orchestrator.command_all_move(Vector2(1, 0))  # Move east
    await orchestrator.wait_seconds(10)
    var failed_handoffs = metrics.get_failed_handoffs()
    assert failed_handoffs == 0, "Handoffs failed: %d" % failed_handoffs

func test_latency_fairness():
    """Pit 10ms bots against 200ms bots - verify normalized"""
    var fast_bots = orchestrator.get_bots_by_region("us-east")
    var slow_bots = orchestrator.get_bots_by_region("japan")
    orchestrator.force_combat_pairs(fast_bots, slow_bots)
    await orchestrator.wait_seconds(60)
    var win_rate_fast = metrics.get_win_rate(fast_bots)
    var win_rate_slow = metrics.get_win_rate(slow_bots)
    # Should be roughly 50/50 if normalized correctly
    assert abs(win_rate_fast - 0.5) < 0.1, "Fast bots winning too much: %.1f%%" % (win_rate_fast * 100)
```

### Local Development Testing

Before cloud VMs, test locally with artificial latency:

```gdscript
# Add to any bot or client
func simulate_latency(ms: int):
    # Delay all outgoing RPCs
    var original_rpc = multiplayer.rpc
    multiplayer.rpc = func(method, args):
        await get_tree().create_timer(ms / 1000.0).timeout
        original_rpc.call(method, args)
```

Or use Clumsy (Windows) / tc (Linux) for network-level simulation.

### CI/CD Integration

```yaml
# .github/workflows/scale_test.yml
name: Scale Test

on:
  schedule:
    - cron: '0 3 * * *'  # Nightly at 3 AM
  workflow_dispatch:  # Manual trigger

jobs:
  scale_test:
    runs-on: ubuntu-latest
    steps:
      - name: Deploy test server
        run: ./deploy_test_server.sh

      - name: Spawn bot VMs
        run: |
          terraform apply -var="bot_count=100" -var="regions=us,eu,asia"

      - name: Run test suite
        run: ./run_scale_tests.sh --bots=100 --duration=300

      - name: Collect metrics
        run: ./collect_metrics.sh > scale_report.json

      - name: Teardown
        run: terraform destroy -auto-approve

      - name: Upload report
        uses: actions/upload-artifact@v3
        with:
          name: scale-test-report
          path: scale_report.json
```

---

## Next Steps

1. Define target scale (players per battle) - **1,000 recommended**
2. Build headless bot client
3. Create bot orchestrator
4. Set up multi-region VM infrastructure
5. Design metrics dashboard
6. Prototype latency normalization

---

## Revision History

| Date | Change |
|------|--------|
| 2026-01-22 | Initial design document |
