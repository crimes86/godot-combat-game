# Ossuary Influence & Corruption System

## Design Spec v1.0

### Overview

Two opposing meters create persistent tension in the world. **Influence** rises from
active play (killing skeletons) and represents the Ossuary fighting back against
players. **Corruption** rises from inactivity and represents the Ossuary settling
into the land unchallenged. The player can never be fully safe — grind hard and the
Ossuary retaliates with campfire waves; idle and the world rots around you.

The campfire **bone ember** system ties into this as the wave trigger. Players
stockpile bone embers from skeleton kills, add them to the campfire, and when the
threshold fills, a wave auto-spawns scaled to the current influence level.

---

## The Two Meters

### Influence (Active Threat)

| Property | Value |
|----------|-------|
| Range | 0.0 — 100.0 |
| Starting value | 0.0 (fresh server) |
| Grows from | Killing skeleton-type enemies |
| Decays from | Time with no skeleton kills |
| Decay rate | ~1.0 per minute after 60s of no kills |
| Player feel | "I stirred the hornet's nest" |

**What influence affects:**
- Wave difficulty at campfire (primary effect)
- Future: skeleton equipment quality at ruins POIs
- Future: elite/boss spawn chance at high influence
- Future: better loot drops from wave enemies

**Growth formula:**
```
Per skeleton kill:
  base_gain = 1.0
  level_bonus = enemy_level * 0.15
  guardian_bonus = 2.0 (if guardian)
  total = base_gain + level_bonus + guardian_bonus
```

**Decay formula:**
```
After 60 seconds with no skeleton kills:
  decay = 1.0 per minute (0.0167 per second)
  Slow enough that influence lingers between farming sessions
  but drains fully overnight on an idle server
```

### Corruption (Passive Threat)

| Property | Value |
|----------|-------|
| Range | 0.0 — 100.0 |
| Starting value | 0.0 (fresh server) |
| Grows from | Time with no skeleton kills (passive) |
| Decays from | Killing skeleton-type enemies |
| Growth rate | ~0.5 per minute (always ticking) |
| Player feel | "This place is rotting around me" |

**What corruption affects (future phases):**
- Skeleton visual mutations (darker tint, green rot particles)
- Skeleton debuff attacks (poison, slow) at high corruption
- Environmental decay (fog, darker lighting near skeleton spawns)
- Corrupted material drops (crafting currency)

**Growth formula:**
```
Every tick (5 seconds):
  growth = 0.04  (~0.5 per minute)
  Always grows unless actively being suppressed by kills
```

**Decay formula:**
```
Per skeleton kill:
  base_decay = 0.5
  level_bonus = enemy_level * 0.05
  Corruption drops from farming, opposite of influence
```

### Meter Relationship

The two meters are **inversely pressured** but not directly linked:

```
Killing skeletons:  Influence UP,   Corruption DOWN
Idling:             Influence DOWN, Corruption UP
```

Both can be at moderate levels simultaneously (e.g., influence 40, corruption 30)
during normal mixed play. The extremes are what create distinct gameplay:

| Player Activity | Influence | Corruption | World State |
|----------------|-----------|------------|-------------|
| Heavy grinding | HIGH | LOW | Big waves, clean skeletons |
| Moderate play | MID | MID | Normal, balanced |
| AFK / just logged in | LOW | HIGH | No waves, rotted skeletons |
| Fresh server | 0 | 0 | Calm, building up |

---

## Campfire Fuel Rework

### Current System
- **Wood (Dry Log):** Healing buff (5-25 HP/s based on count), max 50
- **Bone Embers:** Crit buff (0-16.5% crit chance), max 100

### New System
- **Wood (Dry Log):** Healing buff + Crit buff (consolidated)
- **Bone Embers:** Wave fuel only (fills wave meter, no direct buff)

### Wood Buff (consolidated)

Wood provides BOTH healing and crit, scaling with count:

```
Healing:  5.0 + (wood_percent * 20.0) HP/s         (same as current)
Crit:     wood_percent * 0.165                       (moved from bone embers)

At 50 wood: 25 HP/s heal + 16.5% crit bonus
At 25 wood: 15 HP/s heal + 8.25% crit bonus
At 0 wood:  5 HP/s base heal + 0% crit
```

Wood burn rate stays the same: 1 log per 3000 seconds.
Crit aura visual moves to wood (green + cyan combined aura).

### Bone Ember Wave Meter

Bone embers no longer provide a buff. Instead they accumulate toward a visible
**wave threshold meter** on the campfire UI. Each campfire has its own bone ember
pool and wave meter (per-campfire, not global).

```
Wave threshold: dynamic, scales with nearby player count
  Base: 25 bone embers (solo player)
  Per additional player in zone: +25 embers
  2 players = 50, 3 players = 75, etc.

After wave: bone ember count resets to 0
Hidden cooldown: 60 seconds between waves (prevents spam)
Bone embers still burn slowly (current rate) if not triggered
```

The threshold scales with players, but wave DIFFICULTY scales with influence:

| Influence | Wave Composition | Loot Quality |
|-----------|-----------------|--------------|
| 0-25 (Quiet) | 4-6 basic skeletons | Common drops |
| 25-50 (Stirring) | 6-8 skeletons, some with weapons | Common + uncommon |
| 50-75 (Rising) | 8-12 armored skeletons, 1-2 elites | Uncommon + rare |
| 75-100 (Surging) | 12-16 full armor, 2-3 elites, named boss | Rare + epic |

### Bone Ember Visual on Campfire

As bone embers accumulate toward the 25 threshold:
- Campfire gains a **ghostly green underglow** that intensifies
- Bone particles rise from the fire (similar to current bone ember particles)
- At 20+ embers: fire flickers erratically, warning pulse
- At 25: flash + wave spawns from darkness beyond campfire warmth radius

---

## Wave System

### Trigger
- Auto-triggers when bone embers reach threshold (25 x nearby player count)
- Bone embers reset to 0 after wave triggers
- **Hidden cooldown: 60 seconds** between waves per campfire (prevents spam)
- Only one wave active at a time per campfire
- Influence is NOT consumed — stays at current level
- Each campfire has its own independent wave meter and cooldown
- **Anyone can fuel** — rogues included. Griefing mitigated by noob protection.
- **Meters reset on server restart** — no backend persistence needed

### Spawn Behavior
- Skeletons spawn from outside the campfire warmth radius
- Converge toward the campfire center
- Spawn in a ring at ~800-1000px radius, approach inward
- Staggered spawn (not all at once): 2-3 per second over 3-5 seconds

### Wave Scaling (Influence-based)

```
Base enemies = 4
Influence bonus = floor(influence / 10)    # 0-10 extra enemies
Elite count = floor(influence / 35)        # 0-2 elites
Boss spawns at influence >= 80             # 1 named boss

Total at Surging (influence 90):
  4 base + 9 bonus = 13 skeletons + 2 elites + 1 boss = 16 enemies
```

### Wave Enemy Levels
- Base level: average of nearby player levels
- Influence scaling: +1 level per 25 influence
- Elite/boss: +2 levels above wave base

```
Example: Player is L5, influence is 60
  Wave skeletons: L5 + 2 = L7
  Wave elites: L7 + 2 = L9
```

### Wave Equipment (LPC Modular)
- Low influence: No equipment (bare skeletons)
- Mid influence (25-50): Random weapon (25% chance per skeleton)
- High influence (50-75): Weapon + 1 armor piece
- Surging (75+): Full armor set + weapon, elites have tier 1 gear

### Noob Protection
- Wave enemies **aggro the nearest player first**, not lowest level
- Players below level 3 are **ignored by wave enemies** unless they attack first
- Campfire warmth radius provides **25% damage reduction** during active waves
- Contribution-based loot: any damage dealt = loot eligibility (existing system)
- Low-level players can participate safely by landing hits from warmth zone

### Wave Completion
- Wave is "cleared" when all wave enemies are killed
- Loot chest spawns at campfire center (similar to ruins chest system)
- Chest loot scales with influence level at time of wave trigger
- Small influence decay on wave clear: -5.0 (reward for defending)

---

## HUD Changes

### Ossuary Bar (existing, reworked)

Position: Below minimap, above quest tracker.

Shows TWO values now:

```
[Skull Icon] [Influence Bar ||||||||---] Stirring
[Rot Icon]  [Corruption Bar |||--------] Low
```

- Influence bar: green (low) → yellow → orange → red (high)
- Corruption bar: grey (low) → purple → dark green → sickly green (high)
- Tier labels update per meter

### Campfire Wave Meter (new)

Visible when near a community campfire (within interaction range).
Shows bone ember progress toward wave threshold:

```
[Bone Icon] [Wave Meter ||||||||||||---] 18/25
```

- Integrated into existing campfire fuel UI
- Pulses/glows as it approaches threshold
- Flash effect when wave triggers

---

## Tier Names

### Influence Tiers
| Range | Name | Color |
|-------|------|-------|
| 0-25 | Quiet | Muted green |
| 25-50 | Stirring | Yellow-green |
| 50-75 | Rising | Orange |
| 75-100 | Surging | Red |

### Corruption Tiers
| Range | Name | Color |
|-------|------|-------|
| 0-25 | Clean | Grey |
| 25-50 | Tainted | Purple |
| 50-75 | Blighted | Dark green |
| 75-100 | Cursed | Sickly yellow-green |

---

## Implementation Phases

### Phase 1.5: Flip Influence + Add Corruption (current sprint)
- Rework OssuaryManager: kills increase influence, idle decays it
- Add corruption meter (inverse: grows passively, decays on kills)
- Update HUD to show both meters
- Cosmetic only — no gameplay effects yet

### Phase 2: Campfire Fuel Rework
- Consolidate heal + crit into wood only
- Bone embers become wave fuel (no buff)
- Add wave meter to campfire UI
- Update bone ember visual effects on campfire

### Phase 3: Wave Spawner
- Auto-trigger waves at 25 bone ember threshold
- Wave composition scaled by influence
- Spawn ring around campfire, converge inward
- Noob protection (level gate, warmth damage reduction)
- Wave completion chest with influence-scaled loot

### Phase 4: Corruption Effects
- Skeleton visual mutations at high corruption
- Debuff attacks (poison, slow) on corrupted skeletons
- Environmental visuals (fog, darkening)
- Corrupted material drops

### Phase 5: POI Integration
- Ruins respond to influence (guardian scaling)
- Per-chunk influence/corruption tracking (when alpha barrier drops)
- POI rotation gameplay (farm one area, let another corrupt, rotate)

---

## Constants (for OssuaryManager.gd)

```
# Influence
INFLUENCE_BASE_GAIN = 1.0           # Per skeleton kill
INFLUENCE_LEVEL_BONUS = 0.15        # Per enemy level
INFLUENCE_GUARDIAN_BONUS = 2.0      # Extra for guardians
INFLUENCE_DECAY_DELAY = 60.0        # Seconds before decay starts
INFLUENCE_DECAY_RATE = 0.0167       # Per second (~1.0/min)

# Corruption
CORRUPTION_GROWTH_RATE = 0.04       # Per tick (~0.5/min)
CORRUPTION_KILL_DECAY = 0.5         # Per skeleton kill
CORRUPTION_LEVEL_BONUS = 0.05       # Extra decay per enemy level

# Wave
WAVE_EMBER_THRESHOLD_PER_PLAYER = 25  # Bone embers per nearby player
WAVE_COOLDOWN = 60.0                  # Seconds between waves per campfire
WAVE_BASE_ENEMIES = 4                 # Minimum wave size
WAVE_INFLUENCE_BONUS_DIVISOR = 10     # Extra enemies per 10 influence
WAVE_ELITE_DIVISOR = 35               # Elites per 35 influence
WAVE_BOSS_THRESHOLD = 80              # Influence needed for boss
WAVE_LEVEL_INFLUENCE_DIVISOR = 25     # +1 enemy level per 25 influence
WAVE_COMPLETION_INFLUENCE_DECAY = 5.0
```

---

## Resolved Decisions

1. **Persistence**: Reset on server restart. No backend storage needed.
2. **Wave scope**: Per-campfire. Each campfire has its own bone ember pool and wave.
3. **Wave frequency**: Player-driven with dynamic threshold. 25 embers per player
   in zone. Hidden 60s cooldown prevents spam. Drop rates tuned so solo player
   triggers a wave every ~8-12 minutes of active grinding.
4. **PvP griefing**: Anyone can fuel, including rogues. Mitigated by noob protection
   (L3 gate, warmth DR, contribution loot). Adds chaos — intentional design.

## Resolved Decisions (cont.)

5. **Corruption visuals**: Always visible. Even at 10+ corruption, faint purple
   tint on skeletons. The world never feels fully clean. Scaling:
   - 10+: Faint purple/green tint on skeletons
   - 25+: Tint deepens, subtle rot particles
   - 50+: Obvious mutation, green glow, poison trail particles
   - 75+: Full corruption — glowing eyes, dark aura, debuff attacks

6. **Bone ember drops**: 50% chance per skeleton kill to drop 1-2 bone embers.
   Average ~1 per kill. At ~3 kills/min solo = ~25 embers in ~8 min. Variable
   drops feel lootier than guaranteed 1. Pickable world bones still exist as
   supplemental source.

7. **Wave pathing**: Beeline to campfire center. Wave skeletons march straight
   to the campfire — players intercept them. Tower defense feel. The campfire
   is the objective to protect. Elites and bosses follow the same behavior
   (no special aggro logic).
