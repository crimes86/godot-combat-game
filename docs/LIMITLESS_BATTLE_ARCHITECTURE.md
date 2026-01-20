# Limitless Battle Architecture

## Vision

Ashbane is designed to support **organically scaling battles** - conflicts that start small and grow as reinforcements arrive, without hard player caps or loading screens. When a 10v10 skirmish at a resource node escalates to a 100v100 guild war, the infrastructure scales seamlessly.

**Core Principle**: Players should never see "Battle Full" - instead, the system gracefully adapts to any scale while maintaining combat integrity.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      ORCHESTRATOR SERVICE                        │
│   - Monitors World Server load and hotspots                      │
│   - Spins up Battle Instance Servers on demand                   │
│   - Routes player handoffs between servers                       │
│   - Tears down idle Battle Instances                             │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐     ┌───────────────┐     ┌───────────────┐
│ WORLD SERVER  │     │BATTLE INSTANCE│     │BATTLE INSTANCE│
│  (Persistent) │◄───►│   (Dynamic)   │     │   (Dynamic)   │
│               │     │               │     │               │
│ Chunks -1,0,1 │     │ Hotspot #1    │     │ Hotspot #2    │
│ Normal PvE/PvP│     │ 50v50 battle  │     │ 30v30 battle  │
│ Hotspot detect│     │ No PvE mobs   │     │ No PvE mobs   │
└───────────────┘     └───────────────┘     └───────────────┘
```

## Key Components

### 1. World Server (Always Running)
- Handles normal gameplay: PvE, questing, trading, exploration
- Monitors for battle hotspots using spatial clustering
- Detects reinforcement vectors (players moving toward battles)
- Manages handoff boundaries when Battle Instances exist
- Single beefy server runs all chunks (expandable via Zone Expansion)

### 2. Battle Instance Servers (On-Demand)
- Spawned when hotspot exceeds threshold (e.g., 20+ players in combat)
- Stripped-down scene: No PvE enemies, optimized for pure PvP
- Dedicated resources for smooth combat at scale
- Dynamic tick rate scaling (30Hz → 15Hz as battle grows)
- Automatically shut down when battle ends

### 3. Orchestrator Service
- Kubernetes/Docker-based server management
- Monitors metrics from all servers
- Spin-up latency target: <2 seconds
- Handles server-to-server communication routing

## The "Battle Bubble" Concept

When a battle forms, a virtual "bubble" boundary is created:

```
                    BATTLE BUBBLE

              ╭─────────────────────╮
             ╱    BATTLE SERVER     ╲
            │                        │
            │   ⚔️  Combat Zone      │
            │   Full sync fidelity   │
            │   Dedicated resources  │
             ╲                      ╱
              ╰──────────┬─────────╯
                         │
         ────────────────┼────────────────  HANDOFF BOUNDARY
                         │
              [World Server Territory]
              Normal gameplay continues
```

**Bubble Properties:**
- **Radius**: Starts at 4000px, can expand if battle spreads
- **Center**: Dynamically tracks battle centroid
- **Boundary**: Soft edge where handoffs occur
- **Visibility**: Players outside see effects/markers, not full battle

## Player Handoff Protocol

### Entering a Battle (World → Battle Server)

```
1. DETECTION
   World Server: "Player_42 approaching hotspot boundary"
   └── Velocity vector pointing toward battle
   └── ETA calculated: 5 seconds

2. PRE-HANDOFF
   World Server → Battle Server: PrepareHandoff(player_state)
   └── Full player state: position, health, buffs, inventory, etc.
   Battle Server: Creates dormant player entity at boundary

3. BOUNDARY CROSS
   Player crosses handoff boundary
   World Server: Disconnects player (graceful, no timeout penalty)
   Battle Server: Activates player entity

4. CLIENT TRANSITION
   Client receives new server authority
   Brief visual effect (fog clearing, "entering battle")
   No loading screen, seamless combat continuation

5. CONFIRMATION
   Battle Server → World Server: HandoffComplete(player_id)
   World Server: Removes player from tracking
```

### Exiting a Battle (Battle → World Server)

```
1. BOUNDARY APPROACH
   Battle Server: "Player_42 moving toward boundary exit"

2. PRE-HANDOFF
   Battle Server → World Server: PrepareHandoff(player_state)
   └── Updated state: new health, inventory changes, etc.

3. BOUNDARY CROSS
   Same seamless process in reverse

4. CLEANUP
   If player was last in battle, begin wind-down timer
```

## Hotspot Detection Algorithm

```gdscript
# Runs on World Server every 2 seconds
func detect_battle_hotspots() -> Array[Hotspot]:
    var hotspots = []
    var player_positions = get_all_player_positions()

    # Spatial clustering using DBSCAN-like approach
    var clusters = cluster_players(player_positions,
        min_players=10,
        radius=3000.0
    )

    for cluster in clusters:
        # Check if cluster has active combat
        var combat_score = calculate_combat_density(cluster)

        if combat_score > HOTSPOT_THRESHOLD:
            hotspots.append(Hotspot.new(
                center=cluster.centroid,
                radius=cluster.radius + BUFFER,
                player_count=cluster.size,
                combat_intensity=combat_score
            ))

    return hotspots
```

## Reinforcement Detection

Proactively identify players moving toward battles:

```gdscript
func detect_reinforcements(hotspot: Hotspot) -> Array[Player]:
    var reinforcements = []

    for player in world_players:
        if player in hotspot.players:
            continue  # Already in battle

        var velocity = player.get_velocity()
        var to_battle = hotspot.center - player.position
        var approach_speed = velocity.dot(to_battle.normalized())

        if approach_speed > 100:  # Moving toward at 100+ px/s
            var distance = player.position.distance_to(hotspot.center)
            var eta = distance / approach_speed

            if eta < 60:  # Arriving within 60 seconds
                reinforcements.append({
                    "player": player,
                    "eta": eta,
                    "vector": velocity
                })

    return reinforcements
```

## Dynamic Tick Rate Integration

Battle Instances use `DynamicTickRateManager` for graceful scaling:

| Players in Battle | Tick Rate | AOI Radius | Feel |
|-------------------|-----------|------------|------|
| 1-50 | 30 Hz | 2000px | Crisp |
| 50-100 | 25 Hz | 1600px | Smooth |
| 100-200 | 20 Hz | 1200px | Intense |
| 200+ | 15 Hz | 1000px | Legendary |

**Visual Cues at High Intensity:**
- Fog/dust particles increase
- Screen shake on big abilities
- Sound design sells the chaos
- "LEGENDARY BATTLE" UI indicator

## Battle Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: DETECTION                                          │
│ - World Server detects hotspot (10+ players, combat active) │
│ - Orchestrator notified: "Potential battle forming"         │
│ - Pre-warm Battle Instance (standby)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: FORMATION                                          │
│ - Threshold crossed (20+ players or escalation detected)    │
│ - Battle Instance activated                                 │
│ - Boundary established around hotspot                       │
│ - Players inside boundary queued for handoff                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 3: ACTIVE BATTLE                                      │
│ - All combat on Battle Instance                             │
│ - World Server handles incoming handoffs                    │
│ - Bubble can expand if battle spreads                       │
│ - Dynamic tick rate scales with player count                │
│ - Reinforcements flow in seamlessly                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 4: WIND DOWN                                          │
│ - Combat stops for 60+ seconds                              │
│ - Player count drops below threshold                        │
│ - Remaining players notified: "Battle ending"               │
│ - Handoff back to World Server begins                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ PHASE 5: COLLAPSE                                           │
│ - All players returned to World Server                      │
│ - Battle state (corpses, loot) synced to World              │
│ - Battle Instance saves metrics/logs                        │
│ - Instance shut down, resources freed                       │
└─────────────────────────────────────────────────────────────┘
```

## Guild Warfare Integration

### Bane System

When a guild "banes" another guild's tree:

1. **Declaration**: Attacking guild declares bane (costs resources)
2. **Timer**: Defenders have X hours warning
3. **Battle Zone**: Area around defender's tree becomes hotspot
4. **Auto-Instance**: Battle Instance spins up at siege start time
5. **Objectives**:
   - Attackers: Destroy tree, loot vault
   - Defenders: Survive timer, repel attackers
6. **Resolution**: Winner determined, territory changes hands

### Origin Tree Wars

The "Origin Tree" at world center is the ultimate prize:

- Only top guilds can contest
- Largest battles expected here
- Multiple Battle Instances may form around single war
- Server-wide notifications draw spectators/participants
- Streamer-friendly epic events

## Horizontal Zone Expansion

For world growth (not battle scaling):

```
CURRENT (Zone 1):
┌─────────────────────────────────────────┐
│  Chunk -1  │  Chunk 0   │  Chunk 1      │
│  Campfire  │  Origin    │  Zone 2 Entry │
└─────────────────────────────────────────┘
        Single World Server

FUTURE (Multi-Zone):
┌─────────────────────────────────────────┐
│            WORLD SERVER A               │
│  Chunk -1  │  Chunk 0   │  Chunk 1      │
└─────────────────────────┬───────────────┘
                          │ Seamless
                          │ Handoff
┌─────────────────────────┴───────────────┐
│            WORLD SERVER B               │
│  Chunk 2   │  Chunk 3   │  Chunk 4      │
└─────────────────────────────────────────┘

Players walk between zones = server handoff
Same protocol as Battle Instance handoffs
```

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Battle Instance spin-up | <2s | Pre-warming helps |
| Handoff latency | <100ms | Player shouldn't notice |
| Max players per Battle | 400+ | With tick rate scaling |
| Tick rate at 200 players | 20 Hz | Acceptable for PvP |
| Boundary sync overhead | <5% | Minimal bandwidth for edge sync |

## Infrastructure Requirements

### Minimum (Launch)
- 1x World Server (beefy: 8 core, 32GB RAM)
- 2x Battle Instance pool (can share hardware)
- Redis for cross-server state
- Simple orchestrator script

### Scaled (Post-Launch)
- Kubernetes cluster
- Auto-scaling Battle Instance pool
- Dedicated orchestrator service
- Metrics/monitoring stack (Prometheus/Grafana)

## File Reference

| Component | File |
|-----------|------|
| Dynamic Tick Rate | `scripts/networking/DynamicTickRateManager.gd` |
| Battle Instance Manager | `scripts/networking/BattleInstanceManager.gd` |
| Handoff Protocol | `scripts/networking/ServerHandoffProtocol.gd` |
| Hotspot Detection | Integrated in BattleInstanceManager |
| Network Manager | `scripts/networking/NetworkManager.gd` |

## Related Documentation

- `MASSIVE_BATTLE_OPTIMIZATION.md` - Bandwidth optimization details
- `docs/network/` - General networking architecture
- `docs/guilds/` - Guild system and warfare mechanics
