# Ossuary Influence & Corruption System

## Design Spec v2.0

### Overview

Two meters drive a repeating **push-pull gameplay loop** at every Point of Interest:

- **Corruption** (per-POI, community-shared) — the skeleton faction's grip on the land. Starts maxed out on server restart. All player kills in the area chip it down. Left alone, it grows back. High corruption = dangerous world, bosses present, high-tier loot. Low corruption = safe, farmable, culminating reward.

- **Influence** (per-player, server-authoritative) — your personal kill momentum. The harder and faster you fight, the longer and stronger your weakpoint windows become. Decays when you stop fighting.

Together they create a cycle: arrive at a corrupted POI → fight the corruption boss (hard, influence is low) → clear the remaining mobs (influence rises, corruption falls) → claim the purification reward at low corruption (easy, influence is high) → leave → corruption rebuilds → repeat.

---

## The Core Loop

Every POI follows the same cycle. Chunk 0 (home campfire) is the intro version. Outer chunks are tuned for groups.

```
    ┌─────────────────────────────────────────────┐
    │          CORRUPTION HIGH (100%)             │
    │  Area is dangerous. Enemies swarm campfire. │
    │  CORRUPTION BOSS spawns.                    │
    │  Player influence is LOW → fight is hard.   │
    │  ★ REWARD: Boss loot (rare/epic)            │
    ├─────────────────────────────────────────────┤
    │              ↓ Players kill mobs ↓          │
    │  Corruption drops. Influence rises.         │
    │  Mini-bosses at 75%, 50%, 25% thresholds.   │
    │  Weakpoint windows getting stronger.        │
    │  Area becomes progressively safer.          │
    ├─────────────────────────────────────────────┤
    │          CORRUPTION LOW (0%)                │
    │  Area is safe. Enemies sparse/gone.         │
    │  PURIFICATION EVENT triggers.               │
    │  Player influence is HIGH → damage is juiced│
    │  ★ REWARD: Purified cache (equal to boss)   │
    ├─────────────────────────────────────────────┤
    │              ↓ Players leave ↓              │
    │  Corruption passively rebuilds.             │
    │  Influence decays per-player.               │
    │  Boss respawns when corruption hits 100%.   │
    └──────────── CYCLE RESTARTS ─────────────────┘
```

### Why Both Sides Need Equal Rewards

The loop only works if both endpoints are worth reaching:

| Phase | Challenge | Reward | Player State |
|-------|-----------|--------|-------------|
| **High corruption** (boss) | Hard — influence is low, weak windows | Corruption Boss loot (rare/epic tier) | Arriving fresh, building momentum |
| **Low corruption** (purge) | Easier — influence is high, big windows | Purification Cache (equal value to boss) | At peak power, harvesting the payoff |

Without the low-corruption reward, players would kill the boss and leave immediately. The purification reward incentivizes completing the full clear — which is the satisfying part where you feel powerful.

### The Clearing Phase (Mid-Cycle)

The journey from high to low corruption isn't just "kill trash until bar empties." Threshold events create structure:

| Corruption | Event |
|------------|-------|
| 100% | **Corruption Boss** spawns (hardest fight) |
| 75% | Mini-boss + reinforcement wave |
| 50% | Elite patrol spawns (armored, weapon-equipped) |
| 25% | Final mini-boss + desperate last wave |
| ~0% | **Purification Event** — cache/altar activates |

Each threshold rewards loot and pushes player influence higher, building toward the payoff.

---

## Corruption (Per-POI, Community-Shared)

| Property | Value |
|----------|-------|
| Range | 0.0 — 100.0 |
| Starting value | 100.0 (server restart = fully corrupted) |
| Scope | Per-POI / per-chunk (each area independent) |
| Reduced by | ALL player kills in the area (community effort) |
| Grows from | Time with no kills (passive regrowth) |
| Authority | Server-authoritative, broadcast to all clients |

### What Corruption Controls

**Spawn behavior:**
- 75-100% (Cursed): Max enemy density, enemies aggro toward campfire, full armor/weapons
- 50-75% (Blighted): High density, enemies patrol aggressively, mixed equipment
- 25-50% (Tainted): Moderate density, normal patrol behavior, light equipment
- 0-25% (Clean): Minimal spawns, passive patrol, bare skeletons

**Boss spawns:**
- 100%: Corruption Boss (guaranteed, spawns on reaching 100%)
- Threshold mini-bosses at 75%, 50%, 25% during clearing

**Loot quality:**
- Corruption boss and high-corruption enemies drop best loot
- Mini-boss loot scales with the threshold they spawn at
- Purification cache at 0% matches total boss loot value

**Campfire threat:**
- 75%+: Enemies actively path toward campfire, threaten idle players
- 50-75%: Occasional aggro toward campfire
- Below 50%: Campfire is safe, enemies stay at spawn points

### Corruption Constants

```
CORRUPTION_MAX = 100.0
CORRUPTION_START = 100.0               # Fully corrupted on restart
CORRUPTION_GROWTH_RATE = 0.04/tick     # ~0.5/min passive regrowth
CORRUPTION_KILL_DECAY = 0.5            # Per skeleton kill (all players)
CORRUPTION_LEVEL_BONUS = 0.05          # Extra per enemy level above 1
CORRUPTION_BOSS_THRESHOLD = 100.0      # Boss spawns at max
CORRUPTION_MINI_BOSS_THRESHOLDS = [75, 50, 25]
CORRUPTION_PURIFY_THRESHOLD = 5.0      # Below this triggers purification event
```

### Per-POI Tracking

Each POI has its own corruption instance:

```
Chunk 0: Home Campfire (solo intro)
  - Faster corruption growth (teaches the cycle quickly)
  - Scaled for solo/duo play
  - Corruption boss is a named skeleton (intro difficulty)

Chunk 1+: Outer POIs (group endgame)
  - Slower corruption growth (longer cycles for coordinated play)
  - Scaled for 3-6 player groups
  - Corruption bosses are harder, better loot
  - Multiple POIs allow rotation farming
```

---

## Influence (Per-Player, Server-Authoritative)

| Property | Value |
|----------|-------|
| Range | 0.0 — 100.0 |
| Starting value | 0.0 |
| Scope | Per-player (YOUR kill momentum) |
| Grows from | You killing skeleton-type enemies |
| Decays from | Time without killing |
| Authority | **Server-authoritative** (affects damage output) |

### Why Server-Authoritative

Influence directly buffs weakpoint window duration and damage. A client-authoritative meter would be trivially exploitable. The server tracks a `peer_id -> influence` dictionary and validates all weakpoint interactions against the player's actual influence.

### What Influence Affects

**Weakpoint windows (primary effect):**

| Influence | Window Duration | Damage Multiplier | Feel |
|-----------|----------------|-------------------|------|
| 0-25 (Quiet) | Base (4.0s) | 1.0x | Normal combat |
| 25-50 (Stirring) | +25% (5.0s) | 1.15x | Noticeable improvement |
| 50-75 (Rising) | +50% (6.0s) | 1.30x | Hitting hard |
| 75-100 (Surging) | +75% (7.0s) | 1.50x | Peak power fantasy |

This creates the intended dynamic:
- Arrive at corrupted POI → influence is 0 → boss fight is genuinely hard
- After clearing for a while → influence is high → you feel powerful
- The purification reward comes when you're at peak strength

**Future effects:**
- PvP: influence buffs weakpoint windows against players too (risk/reward for area control)
- Group "guarding" an area to build corruption → PvP to protect the mobs → corruption boss spawns → group clears and farms at high influence

### Influence Constants

```
INFLUENCE_BASE_GAIN = 1.0              # Per skeleton kill
INFLUENCE_LEVEL_BONUS = 0.15           # Per enemy level above 1
INFLUENCE_GUARDIAN_BONUS = 2.0         # Extra for guardian kills
INFLUENCE_DECAY_DELAY = 60.0           # Seconds before decay starts
INFLUENCE_DECAY_RATE = 0.0167/s        # ~1.0/min after idle
```

### Server Tracking

```gdscript
# Server tracks per-player influence (keyed by peer_id)
var _player_influence: Dictionary = {}  # peer_id -> {value, last_kill_time}

# On skeleton kill, server knows which player dealt the killing blow
# and updates THAT player's influence
func on_skeleton_killed(killer_peer_id: int, enemy_level: int, is_guardian: bool):
    # Corruption: shared, reduce for everyone
    _reduce_corruption(enemy_level, is_guardian)
    # Influence: per-player, increase for killer only
    _increase_player_influence(killer_peer_id, enemy_level, is_guardian)

# Broadcast: corruption to all, influence individually
func _broadcast_state():
    _broadcast_corruption.rpc(corruption)  # Everyone gets same corruption
    for peer_id in _player_influence:
        _send_player_influence.rpc_id(peer_id, _player_influence[peer_id].value)
```

---

## PvP Integration (Group Endgame)

The corruption/influence loop creates natural PvP hotspots in outer chunks:

### The Guard Strategy

1. A group finds a POI and **guards it** — protects the corrupted mobs from being killed
2. Corruption stays high (or builds to 100%)
3. Boss spawns → group clears it for top-tier loot
4. Group then clears all remaining mobs → influence skyrockets
5. At peak influence, weakpoint windows are massive → group farms at peak power
6. Purification event triggers → second reward
7. Group moves to next POI, lets this one rebuild

### PvP Conflict Points

- Rival groups want the same POI → fight over who gets to farm it
- A group guarding mobs creates a PvP target → attackers try to kill the mobs
- Defending the corruption = defending future loot
- High-influence players are stronger in PvP (longer weakpoint windows) but influence decays if they stop killing PvE mobs → can't just camp PvP indefinitely

---

## Zone Scaling

### Chunk 0 — Home Campfire (Introduction)

The first campfire teaches the corruption/influence loop in a safe, solo-friendly environment:

- Corruption growth rate is faster (learn the cycle in ~15-20 minutes)
- Enemies are level-appropriate for new characters
- Corruption boss is a named skeleton (not overwhelming)
- Purification reward is a starter cache (useful early gear/materials)
- The bone ember / campfire wave system ties into this as supplemental content
- Single corruption tracker for the whole chunk

### Chunk 1+ — Outer POIs (Group Endgame)

Each POI in outer chunks has its own corruption tracker:

- Corruption growth is slower (30-60 min full cycle for group coordination)
- Enemies scale to chunk difficulty
- Corruption bosses are unique per POI with specific loot tables
- Purification rewards are endgame tier
- Multiple POIs in a chunk allow rotation: farm one while others rebuild
- Group coordination required — solo players can't clear fast enough to beat regrowth

---

## HUD

### Ossuary Bar (below minimap)

Two rows showing personal influence and area corruption:

```
[Skull Icon] [Influence Bar ||||||||---] Stirring    (your kill momentum)
[Rot Icon]  [Corruption Bar |||--------] Tainted     (area corruption)
```

- **Influence bar**: green (low) → yellow → orange → red (high)
  - Flash/pulse effect on kill (white flash, quick fade) so small changes are visible
- **Corruption bar**: grey (low) → yellow-green → green → vivid toxic green (high)
  - Flash effect on kill (brief brighten then fade)
- Tier labels update per meter

### Kill Feedback

On skeleton kill, both bars briefly flash to show movement:
- Influence bar: white flash → fade back to normal (bar went up)
- Corruption bar: white flash → fade back to normal (bar went down)
- Even if the movement is tiny (0.5-1.0 points), the flash confirms progress

---

## Tier Names

### Influence Tiers (per-player)
| Range | Name | Color | Weakpoint Bonus |
|-------|------|-------|-----------------|
| 0-25 | Quiet | Muted green | Base duration |
| 25-50 | Stirring | Yellow-green | +25% duration, 1.15x damage |
| 50-75 | Rising | Orange | +50% duration, 1.30x damage |
| 75-100 | Surging | Red | +75% duration, 1.50x damage |

### Corruption Tiers (per-POI)
| Range | Name | Color | World State |
|-------|------|-------|-------------|
| 0-25 | Clean | Grey | Safe, minimal spawns |
| 25-50 | Tainted | Pale yellow-green | Moderate, normal patrols |
| 50-75 | Blighted | Sickly green | Dangerous, aggressive enemies |
| 75-100 | Cursed | Vivid toxic green | Maximum threat, campfire under siege |

---

## Implementation Phases

### Phase 1.5: Base Meters + HUD (DONE)
- [x] Flip influence direction (kills increase, idle decays)
- [x] Add corruption meter (passive growth, kill decay)
- [x] Two-row HUD with both bars
- [x] Start corruption at 100% on server restart

### Phase 2: Per-Player Influence (Server-Authoritative)
- Move influence tracking to server-side per-player dictionary
- Pass killer peer_id through `on_skeleton_killed()`
- Server sends each player their own influence via targeted RPC
- Each player's influence decays independently on server
- Client HUD displays local player's influence from server updates
- Add kill flash effect on both HUD bars

### Phase 3: Influence → Weakpoint Buff
- Server validates weakpoint window duration against player's influence
- Window duration scales: base 4.0s → up to 7.0s at max influence
- Weakpoint damage multiplier scales: 1.0x → 1.50x at max influence
- Display influence buff indicator during weakpoint windows

### Phase 4: Corruption Boss + Threshold Events
- Corruption boss spawns at 100% per POI
- Mini-boss spawns at 75%, 50%, 25% corruption thresholds
- Reinforcement waves at threshold crossings
- Campfire aggro behavior scales with corruption level

### Phase 5: Purification Event (Low-Corruption Reward)
- Purification cache/altar activates near 0% corruption
- Loot value matches corruption boss (balances both sides of the loop)
- Visual event (area cleanses, particle effects)
- Marks cycle completion

### Phase 6: Campfire Fuel Rework
- Consolidate heal + crit into wood only
- Bone embers become wave fuel (no direct buff)
- Wave meter on campfire UI
- Waves scale with influence (supplemental to corruption loop)

### Phase 7: Multi-Chunk POI System
- Per-POI corruption trackers for outer chunks
- POI rotation gameplay (farm one, let others rebuild)
- Chunk-appropriate scaling (solo chunk 0, group chunk 1+)
- PvP interactions around POI control

---

## Campfire Fuel System (Supplemental)

The bone ember / campfire wave system is **supplemental** to the corruption loop,
not the primary driver. It provides additional content while camping near the fire:

### Current System (unchanged for now)
- **Wood (Dry Log):** Healing buff (5-25 HP/s), max 50
- **Bone Embers:** Crit buff (0-16.5% crit chance), max 100

### Future Rework (Phase 6)
- Wood provides BOTH healing and crit (consolidated)
- Bone embers become wave fuel only
- Wave difficulty scales with influence level
- Waves are opt-in content, not required for the corruption loop

---

## Constants Reference

```
# Corruption (per-POI, community)
CORRUPTION_MAX = 100.0
CORRUPTION_START = 100.0
CORRUPTION_GROWTH_RATE = 0.04/tick        # ~0.5/min
CORRUPTION_KILL_DECAY = 0.5               # Per kill (any player)
CORRUPTION_LEVEL_BONUS = 0.05             # Per enemy level
CORRUPTION_BOSS_THRESHOLD = 100.0
CORRUPTION_MINI_BOSS_THRESHOLDS = [75, 50, 25]
CORRUPTION_PURIFY_THRESHOLD = 5.0

# Influence (per-player)
INFLUENCE_BASE_GAIN = 1.0
INFLUENCE_LEVEL_BONUS = 0.15
INFLUENCE_GUARDIAN_BONUS = 2.0
INFLUENCE_DECAY_DELAY = 60.0              # Seconds before decay
INFLUENCE_DECAY_RATE = 0.0167/s           # ~1.0/min

# Influence → Weakpoint Scaling
INFLUENCE_WINDOW_BASE = 4.0              # Base weakpoint duration
INFLUENCE_WINDOW_MAX_BONUS = 0.75        # +75% at max influence
INFLUENCE_DAMAGE_MAX_BONUS = 0.50        # +50% at max influence

# Wave System (supplemental, Phase 6)
WAVE_EMBER_THRESHOLD_PER_PLAYER = 25
WAVE_COOLDOWN = 60.0
WAVE_BASE_ENEMIES = 4
```

---

## Resolved Decisions

1. **Influence is server-authoritative** — it directly affects damage. Cannot trust clients.
2. **Corruption is per-POI** — each area cycles independently. Allows rotation farming.
3. **Corruption starts at 100%** on server restart. World begins dangerous.
4. **Both cycle endpoints reward equally** — boss loot at high corruption, purification cache at low corruption. Neither side is "the real reward."
5. **Outer chunks are group content** — solo players handle chunk 0, groups coordinate on outer POIs.
6. **PvP integration is natural** — guarding corruption = guarding future loot. Creates organic conflict.
7. **Meters reset on server restart** — no backend persistence needed for corruption. Influence resets per-player on login.
8. **Kill flash on HUD bars** — visual confirmation that small per-kill changes registered.
