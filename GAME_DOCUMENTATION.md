# Wasteland - Game Documentation

## World System

### World Dimensions
- **World Size**: 12000x5000 pixels
- **World Bounds**: X: -3000 to 9000, Y: -2500 to 2500
- **Ground Coverage**: Extends from -5000 to 13000 x, -3000 to 3000 y (18,000 x 6,000 pixels)

### Key Positions
| Element | Position | Description |
|---------|----------|-------------|
| **Campfire** | (400, 0) | Player spawn point and safe zone |
| **Ruins** | (2184, -1216) | Ruins farming spot with 8 skeleton guardians |
| **Castle** | (7600, 0) | Journey destination / Boss zone |
| **Player Spawn** | (400, 0) | At campfire |
| **Journey Distance** | 7,200 pixels | Campfire to castle horizontal travel |

### World Baking System
The game uses a pre-baked world texture system for optimal performance:

1. **Generate Once**: Run `bake_world_offline.tscn` (F5) to create the world texture
2. **Output**: Creates `res://assets/environment/baked_world_background.png`
3. **Load Instantly**: Game loads single PNG instead of generating 267,000+ nodes
4. **Expected Behavior**: Baker freezes during generation (1-5 minutes) - this is normal

**Important**:
- World texture format: PNG (lossless, 8-15 MB)
- Load time: <100ms
- Only regenerate when changing world appearance

### Screenshot Mode
Press **F12** during gameplay to toggle:
- **ON**: Hides player, enemies, UI, campfire (static background only)
- **OFF**: Shows everything normally

---

## Environment & Props

### Prop Distribution (2,500 total)
Props are loaded dynamically from `prop_placements.json`:
```
Trees (dead_tree_1 & 2):     607 props
Rocks (large/medium/small):  707 props
Skulls:                      170 props
Bones:                       183 props
Ground Cracks:               639 props
Broken Swords:               101 props
Ash Piles:                    93 props
```

### Scattering Algorithm
- Props scattered across FULL world area (not just center)
- **Path Clearance**: 100-150px radius around path waypoints
- **Density Gradient**: Increases LEFT→RIGHT (0.5x near campfire → 1.6x near castle)
- **Vertical Distribution**: Full screen height (-324 to +324)

### Tree Shadows
- Proper oval shadows that connect to tree base
- Shadow positioning fixed in recent builds

---

## Path System

### Winding Path (19 waypoints)
The path creates an S-curve through the wasteland, winding north and south:
- Starts at Campfire (400, 0)
- Winds through center with multiple direction changes
- Ends at Castle (7600, 0)
- **Path Markers**: 25 yellowish rocks guide the player

### Path Characteristics
- **Not linear** - requires multi-dimensional navigation
- **Vertical Movement**: Path reaches y = -350 (north) and y = +280 (south)
- **Total Path Length**: ~7,200 pixels horizontal + vertical movement

---

## Combat System

### Enemy Progression & Zone Design

**Journey**: 7,200 pixels from Campfire (400, 0) to Castle (7,600, 0)

#### Zone-Based Level Scaling

**Zone 1: The Wasteland** (Campfire → Ruins 1: ~2,000px)
- **Roaming enemies**: Levels 1, 3, 5, 7 (scattered along path)
- **Ruins 1 guardians**: 8x Level 8 skeletons
- **Player expected level**: 1-10
- **Theme**: Tutorial area, learn combat mechanics
- **Enemy type**: Basic Skeletons (white bone, light gear)

**Zone 2: The Cursed Lands** (Ruins 1 → Ruins 2: ~2,200px)
- **Roaming enemies**: Levels 9, 11, 13, 15 (more frequent spawns)
- **Ruins 2 guardians**: 8x Level 16 skeletons
- **Player expected level**: 10-18
- **Theme**: Difficulty ramps up, need better gear
- **Enemy type**: Armored Skeletons (gray metal, shields)

**Zone 3: The Shadow Realm** (Ruins 2 → Ruins 3: ~2,000px)
- **Roaming enemies**: Levels 17, 19, 21, 23 (dense spawns)
- **Ruins 3 guardians**: 8x Level 24 skeletons
- **Player expected level**: 18-26
- **Theme**: Late game, need max stats soon
- **Enemy type**: Shadow Skeletons (dark purple, faster attacks)

**Zone 4: Castle Approach** (Ruins 3 → Castle: ~1,000px)
- **Elite guards**: 3-4 encounters with levels 26, 28, 30
- **Door guardians**: 2x Level 30 (must defeat to unlock boss)
- **Player expected level**: 25-30 (max stats + good gear)
- **Theme**: Gauntlet before boss, prove you're ready
- **Enemy type**: Royal Guards (golden trim, elite warriors)

**Boss Zone: Castle Interior**
- **Boss**: Level 33 (Necromancer King / Shadow Lord)
- **Mechanics**: 2-phase fight or summon system
- **Requires**: Level 25+ stats + upgraded weapons/armor
- **Rewards**: 2,000-5,000 gold, guaranteed legendary weapon (Level 33-35)

#### Enemy Placement Formula

**Smooth progression**: Every ~300px = +1 enemy level

| Position | Enemy Level | Type |
|----------|-------------|------|
| 400 | Level 1 | Campfire (safe zone) |
| 700 | Level 1 | Roaming skeleton |
| 1000 | Level 2 | Roaming skeleton |
| 1300 | Level 3 | Roaming skeleton |
| 1600 | Level 5 | Roaming skeleton |
| 1900 | Level 7 | Roaming skeleton |
| **2184** | **Level 8** | **Ruins 1 Guardians (8x)** |
| 2500 | Level 9 | Roaming skeleton |
| 3000 | Level 11 | Roaming skeleton |
| 3500 | Level 13 | Roaming skeleton |
| 4000 | Level 15 | Roaming skeleton |
| **4200** | **Level 16** | **Ruins 2 Guardians (8x)** |
| 4700 | Level 18 | Roaming skeleton |
| 5200 | Level 20 | Roaming skeleton |
| 5700 | Level 22 | Roaming skeleton |
| **6000** | **Level 24** | **Ruins 3 Guardians (8x)** |
| 6400 | Level 26 | Elite guard |
| 6800 | Level 28 | Elite guard |
| 7200 | Level 30 | Door Guardians (2x) |
| **7600** | **Level 33** | **BOSS (Necromancer King)** |

#### Roaming vs Stationary Behavior

**Roaming Enemies**:
- Patrol 200-300px path segments
- Lower density (1 every ~400px)
- Drop standard loot
- Can be avoided with skillful movement

**Ruins Guardians**:
- Circle ruins in formation (180-unit radius)
- Higher level than nearby roamers
- Better loot drops (mini-boss quality)
- Must defeat at least 1 to convert ruins to campfire

#### Progression Gates

**Soft Gates** (recommended level):
- Zone 1: Suggested level 1-10
- Zone 2: Suggested level 10-18
- Zone 3: Suggested level 18-26
- Boss: Suggested level 25-30

**Hard Gates** (required):
1. **Ruins 1 Conversion**: Must kill at least 1 guardian to unlock vendor
2. **Castle Door**: Must be level 20+ to attempt door guardians
3. **Door Guardians**: Must defeat 2x Level 30 elites to unlock boss room

#### Loot Scaling by Zone

**Zone 1** (Levels 1-8):
- Gold: 5-20 per kill
- Weapon drop rate: 3%
- Drop quality: Level 5-10 gear

**Zone 2** (Levels 9-16):
- Gold: 25-60 per kill
- Weapon drop rate: 5%
- Drop quality: Level 12-18 gear

**Zone 3** (Levels 17-24):
- Gold: 70-120 per kill
- Weapon drop rate: 7%
- Drop quality: Level 20-26 gear

**Zone 4** (Levels 25-30):
- Gold: 150-250 per kill
- Weapon drop rate: 10%
- Drop quality: Level 28-30 gear

**Boss** (Level 33):
- Gold: 2,000-5,000
- Guaranteed legendary weapon (Level 33-35)
- Cosmetic reward (title, special armor skin)

#### Ruins as Checkpoints & Vendors

**Ruins 1** (Level 8 area):
- Convert to unlock vendor access
- Sells Level 10-12 weapons and armor
- Respawn point for Zones 1-2
- Acts as mid-point safe zone

**Ruins 2** (Level 16 area):
- Sells Level 18-20 gear
- Weapons with stat bonuses (+AGI, +STR)
- Respawn point for Zones 2-3
- Required for progressing to Zone 3

**Ruins 3** (Level 24 area):
- Sells Level 26-28 gear (best pre-boss)
- High-tier weapons with crit chance bonuses
- Respawn point for Zones 3-4 and boss attempts
- Final preparation before boss fight

#### Death & Respawn System

**Respawn Locations**:
- Die in Zone 1 → Respawn at main Campfire (400, 0)
- Die in Zone 2 → Respawn at Ruins 1 (if converted)
- Die in Zone 3 → Respawn at Ruins 2 (if converted)
- Die in Zone 4 or Boss → Respawn at Ruins 3 (if converted)

**Death Penalty**:
- Lose 10% of current XP progress (not enough to de-level)
- Encourages converting ruins for closer respawns
- Creates risk/reward for pushing forward

#### Boss Design

**Level 33 Necromancer King**

**Stats**:
- HP: 5,000-8,000 (long endurance fight)
- Damage: 30-40 per hit (punishing but not one-shot)
- Crit chance: 15% (dangerous crit windows)
- Attack speed: 1.0s (slower than player but hits hard)

**Mechanics** (choose one):

**Option A: Summon Mechanic**
- Boss summons 2x Level 28 skeleton adds every 30 seconds
- Must manage adds while DPSing boss
- Tests multi-target combat skill

**Option B: Phase Transition**
- Phase 1 (100%-50% HP): Normal combat
- Phase 2 (50%-0% HP): Gains shadow armor, requires weakpoint hits to break
- Forces players to master crit system

**Option C: Arena Hazards**
- Purple zones spawn on ground (10 damage/sec)
- Forces movement during combat
- Tests positioning + combat skill

**Rewards**:
- 2,000-5,000 gold
- Guaranteed legendary weapon (Level 33-35, best in game)
- Cosmetic title: "Necromancer Slayer"
- Special armor skin (visual only)

#### Visual Zone Progression

**Zone 1**: Brown wasteland, sparse dead trees, bright lighting (tutorial feel)
**Zone 2**: Darker terrain, fog increasing, ominous atmosphere (danger rising)
**Zone 3**: Purple/black corruption on ground, thick mist (nightmare zone)
**Zone 4**: Castle walls visible, red sky, foreboding (end is near)
**Boss Arena**: Dark throne room, dramatic lighting, boss on elevated platform

#### Post-Boss Content (Future)

**Option 1: New Game+**
- Replay journey with all enemies +5 levels
- Boss becomes Level 38
- Better loot drops (Level 38-40 gear)

**Option 2: Boss Rush Mode**
- Fight Ruins 1, 2, 3 guardians + boss back-to-back
- No healing between fights
- Leaderboard for fastest clear time

**Option 3: Endless Mode**
- After boss defeat, unlock "Nightmare Path"
- Endless waves of enemies, increasing difficulty
- See how far you can survive

#### Multiplayer Scaling & Group Mechanics

**Design Philosophy**: Hybrid Dynamic Scaling
- **Base tuning**: Designed for 2 players (duo)
- **Solo**: Hard but possible with skill
- **Groups (3+)**: Easier, faster progression
- **Grouping is rewarded, not required**

**Difficulty Tiers:**

| Players | Difficulty | Enemy HP | Enemy Damage | XP Per Player | Loot Bonus |
|---------|-----------|----------|--------------|---------------|------------|
| 1 (Solo) | HARD | 100% | 100% | 100% | 0% |
| 2 (Duo) | BALANCED | 140% | 110% | 110% | +5% |
| 3 (Trio) | EASY | 180% | 115% | 105% | +10% |
| 4-5 (Party) | VERY EASY | 220-260% | 120% | 100% | +15% |

**Enemy Scaling Formula:**
- **HP**: Base HP × (1 + 0.4 × (players - 1))
  - 1 player: 100% HP
  - 2 players: 140% HP (tuned for this)
  - 3 players: 180% HP (easier per-player)
  - 5 players: 260% HP (much easier per-player)

- **Damage**: Base damage × (1 + 0.1 × (players - 1))
  - Scales slower than HP (groups naturally tankier)
  - 1 player: 100% damage
  - 5 players: 140% damage

**XP Bonus System:**
- **Duo (2 players)**: Each gets 110% XP (20% total bonus!)
- **Trio (3 players)**: Each gets 105% XP (15% total bonus)
- **Party (4-5)**: Each gets 100% XP (no penalty, balanced)

**Why XP Bonuses?**
- Encourages grouping without forcing it
- Rewards social play
- Duo gets biggest per-player bonus (sweet spot)
- 3+ players still beneficial (easier combat + loot bonuses)

**Loot Distribution:**
- **Gold**: Split evenly, but enemies drop more gold in groups
  - 2 players: Enemy drops 110% gold, split 55% each
  - 3 players: Enemy drops 120% gold, split 40% each
  - 5 players: Enemy drops 150% gold, split 30% each

- **Weapon/Armor Drops**: Personal loot (each player rolls separately)
  - Drop rate increases with group size
  - Solo: 3% base drop rate
  - Duo: 5% drop rate each
  - Trio: 7% drop rate each
  - Party: 10% drop rate each

- **Boss Drops**: Everyone gets guaranteed legendary weapon
  - Each player receives their own Level 33-35 weapon
  - Encourages group boss kills
  - No fighting over loot

**Zone-Specific Difficulty (Solo vs Group):**

**Zone 1 (Levels 1-8): Solo-Friendly**
- Tutorial area, designed to be soloable
- Players learn combat mechanics alone
- Grouping is optional (faster but not needed)

**Zone 2 (Levels 9-16): Duo Recommended**
- Enemy HP/damage tuned for 2 players
- Solo requires good gear or over-leveling
- Example: Level 16 skeleton has 800 HP base
  - Solo: 800 HP, 30 damage → Hard fight
  - Duo: 1,120 HP, 33 damage → Balanced fight
  - Trio: 1,440 HP, 36 damage → Easy fight

**Zone 3 (Levels 17-24): Duo Strongly Recommended**
- Enemies hit harder, have more HP
- Solo requires max stats + good gear + skill
- Example: Level 24 skeleton has 1,500 HP base
  - Solo: 1,500 HP, 50 damage → Very hard
  - Duo: 2,100 HP, 55 damage → Challenging but fair
  - Trio: 2,700 HP, 60 damage → Manageable

**Zone 4 (Levels 25-30): Group Recommended**
- Elite enemies designed for coordinated combat
- Solo is "challenge mode"
- Example: Level 30 Royal Guard has 2,500 HP base
  - Solo: 2,500 HP, 70 damage → Extreme challenge
  - Duo: 3,500 HP, 77 damage → Difficult but doable
  - Trio: 4,500 HP, 84 damage → Balanced

**Boss (Level 33): Designed for 2-3 Players**
- **Solo**: Extreme challenge mode (possible but very hard)
  - 5,000-8,000 HP, 30-40 damage
  - Requires perfect clicking, gear, and skill
  - 3-5 minute fight with no mistakes
  - Bragging rights for solo kills!

- **Duo (2 players)**: Balanced boss fight
  - 7,000-11,200 HP, 33-44 damage
  - 2-3 minute coordinated fight
  - Each player manages their own crit windows
  - Intended difficulty

- **Trio (3 players)**: Easier boss fight
  - 9,000-14,400 HP, 36-48 damage
  - 1-2 minute fight
  - More forgiving, faster clear

- **Party (4-5 players)**: Easy mode
  - 11,000-20,800 HP, 39-52 damage
  - <1 minute fight
  - Farming boss for alts/gear

**Boss Scaling Options:**

Choose one mechanic based on group size:

**Solo/Duo (1-2 players):**
- **Option B: Phase Transition** (rewards skill)
  - Phase 1: Normal combat
  - Phase 2: Shadow armor, requires weakpoint hits
  - Tests mastery of crit system

**Trio (3 players):**
- **Option A: Summon Mechanic** (tests coordination)
  - Boss summons 2x Level 28 adds every 30 seconds
  - Group must manage adds while DPSing boss
  - Tests multi-target combat

**Party (4-5 players):**
- **Option C: Arena Hazards** (keeps it interesting)
  - Purple damage zones spawn on ground
  - Prevents boss from being pure tank-and-spank
  - Still easier, but requires some movement

**Ruins Guardians (Group Tactics):**

**8x Guardians circling each ruins:**

- **Solo Strategy**: Pick off 1-2 at a time
  - Pull individual guardians away from pack
  - Risky if others aggro
  - Takes 5-10 minutes to clear

- **Duo Strategy**: Fight 3-4 at once
  - Manageable with coordination
  - Share aggro, focus fire
  - Takes 3-5 minutes to clear

- **Group Strategy**: Pull all 8 at once
  - AoE damage, mass clear
  - Fast and efficient
  - Takes 1-2 minutes to clear

**Respawn in Multiplayer:**

**Party Member Dies:**
- Respawn at nearest converted ruins
- Can run back to rejoin party
- No XP penalty if party survives

**Party Wipe (All Die):**
- All respawn together at same ruins
- 10% XP loss for each player
- Encourages safer play

**Party Member Joins Mid-Fight:**
- Can rejoin active combat
- Enemies don't reset
- Allows reinforcements

**Aggro System:**

**Threat Generation:**
- **Damage dealt**: +1 threat per damage
- **Proximity**: Closer = higher threat
- **Healing**: +0.5 threat per HP healed (future)

**Enemy Behavior:**
- Targets highest threat player
- Switches target if threat difference >50%
- Roaming enemies aggro nearest player in range

**Tank/DPS Roles Emerge Naturally:**
- High-damage players (DPS): Focus on crit windows, stay back
- Tanky players (VIT build): Get in close, draw aggro
- Balanced players (Hybrid): Flexible positioning

**Progression Gates in Multiplayer:**

**Ruins Conversion:**
- Any party member can interact to convert
- Conversion unlocks vendor for entire party
- All party members can use ruins as respawn

**Level Gates (Castle Door):**
- Checks party leader's level OR highest level in party
- Must be level 20+ to enter Zone 4
- Prevents low-level players from being carried too hard

**Door Guardians (2x Level 30):**
- Must defeat as group to unlock boss room
- Unlock persists for all party members
- Can re-enter boss room freely after unlock

**Social Features (Future):**

**Party System:**
- Party size: 1-5 players
- Party leader controls loot rules
- Shared quest progress (ruins conversion)

**Guild/Clan System:**
- Guild ruins (claim ruins as guild territory)
- Guild PvP (contest ruins ownership)
- Guild bonuses (XP/loot boosts)

**World Events:**
- Boss spawns in open world (10+ players)
- Defend ruins from skeleton invasions
- Competitive leaderboards

---

### Crit System Implementation

Detailed technical implementation of the critical hit and weakpoint system.

#### Critical Hit Calculation

**Base Formula**:
```gdscript
var crit_chance = CharacterStats.get_crit_chance()  # LUCK-based + weapon bonuses
var is_critical = randf() < crit_chance
```

**Crit Chance Sources**:
- Base chance from LUCK stat
- Weapon modifiers (+2% to +15%)
- Equipment bonuses (future)
- Buff effects (future)

**Level Scaling**:
- Level 10 (LUCK 10): ~1% base crit chance
- Level 25 (LUCK 58): ~10% base crit chance
- With weapon bonuses: Up to 25% crit chance

#### Weakpoint Spawning Algorithm

**Sectioned Spawning** (prevents clustering):

```gdscript
# Divide body into sections
var sections = ["upper", "mid", "lower"]
var section_positions = {
    "upper": [pos1, pos2, pos3, pos4, pos5],      # 5 positions
    "mid": [pos6, pos7, pos8, pos9, ...],         # 9 positions
    "lower": [pos15, pos16, pos17]                # 3 positions
}

# Choose one random position from each section
for section in sections:
    var random_pos = section_positions[section].pick_random()
    spawn_weakpoint(random_pos)
```

**Spacing Validation**:
- Minimum 8 pixel spacing at base scale
- Scaled to 22.4 pixels at 2.8x (crit window scale)
- Prevents accidental double-clicks

**Weakpoint Count by Player Level**:
- Levels 1-10: 1 weakpoint
- Levels 11-20: 2 weakpoints
- Levels 21+: 3 weakpoints

#### Weakpoint Visual Design

**Progressive Brightening**:
- Start brightness: 60% (visible but dull)
- Target brightness: 100% (full brightness)
- Progress: Based on damage taken (`current_hits / max_hits`)

**Glow System**:
- Base glow: 30% alpha at start
- Max glow: 80% alpha at max damage
- Scale: 1.1x size (tight, close to gem)
- Color: Themed to weakpoint type (blood red, bone white)

**Shine Layers** (3 layers):
- Layer 1: 30% → 70% alpha
- Layer 2: 35% → 90% alpha
- Layer 3: 15% → 30% alpha
- Creates depth and dimensionality

**Hit Feedback**:
- Pulse effect on click (scale tween)
- Particle burst (mist-like explosion on destruction)
- Sound effect (glass/bone crack)
- Combat text showing damage

#### Crit Window Lifecycle

**1. Trigger Phase** (instant):
```gdscript
# On critical hit
spawn_crit_window()
    - Hide regular weakpoints (if any exist)
    - Create 1-3 weakpoints based on player level
    - Position in sectioned locations
    - Scale up to 2.8x with animation
    - Start 4 second timer
```

**2. Active Phase** (0-4 seconds):
```gdscript
# While window is active
- Player clicks weakpoints
- Each click deals damage + registers with ChainManager
- Weakpoint destroyed on click
- Progressive brightening based on damage
- Combat text shows damage numbers
```

**3. Expiration Phase** (at 4 seconds):
```gdscript
# When timer expires
if all_weakpoints_destroyed:
    ChainManager.on_crit_window_completed(true)  # Chain++
    Play success sound
    Spawn success particles
else:
    ChainManager.on_crit_window_completed(false)  # Chain reset
    Play failure sound
    Remaining weakpoints explode (failure effect)
```

**4. Cleanup Phase**:
```gdscript
# After window ends
- Remove all weakpoint nodes
- Reset enemy state
- Resume normal combat
```

#### Damage Calculation During Crit Window

**Normal Enemy Hit**:
```gdscript
var base_damage = attack_damage
var chain_mult = ChainManager.get_damage_multiplier()
var final_damage = base_damage * chain_mult
enemy.take_damage(final_damage, false)
```

**Weakpoint Hit**:
```gdscript
var base_damage = attack_damage
var chain_mult = ChainManager.get_damage_multiplier()
var crit_mult = 2.0  # Weakpoint hits deal 2x damage
var final_damage = base_damage * chain_mult * crit_mult
weakpoint.take_damage(final_damage)
```

**Total Multiplier Example** (10x chain, weakpoint hit):
- Base: 50 damage
- Chain: 50 × 2.0 = 100 damage
- Crit: 100 × 2.0 = 200 damage per weakpoint
- 3 weakpoints = 600 total burst damage

#### Multiplayer Synchronization ✅ IMPLEMENTED

**All-Client Visibility** (current implementation):
- All clients see weakpoints when any player triggers a crit
- Server broadcasts weakpoint positions to all connected clients
- Enables cooperative gameplay where players can see each other's crit windows

**Server Authority** ✅:
- Server rolls for crits (`_server_roll_for_crit()` in NetworkEnemyManager)
- Server generates weakpoint positions and broadcasts via `broadcast_crit_window_start()`
- Server validates all weakpoint hits via `request_weakpoint_hit()` RPC
- Server applies damage and broadcasts results to all clients

**Key RPC Functions** (in NetworkEnemyManager.gd):
- `request_attack()` - Client requests attack, server rolls crit
- `broadcast_crit_window_start()` - Server → all clients: start crit window
- `request_weakpoint_hit()` - Client → server: report weakpoint click
- `_client_weakpoint_hit()` - Server → all clients: sync weakpoint destruction
- `_client_enemy_damaged()` - Server → all clients: sync damage/health/sounds

#### Performance Optimization

**Object Pooling** (future):
- Reuse weakpoint nodes instead of instantiate/free
- Reduces GC pressure during intense combat
- Target: <5ms per crit window creation

**Particle Culling**:
- Limit to 10 simultaneous crit windows on screen
- Reduce particle count when >5 active
- Maintain 60 FPS with 15 players

**Z-Index Management**:
- Weakpoints: z_index 400 (always on top)
- Regular enemies: z_index 0
- Prevents visual overlap issues

---

### Weakpoint System
Optimized weakpoint positions for skeleton enemies:

**Upper Section (5 positions)**
- Head & shoulders area
- Minimum 8+ pixel spacing

**Mid Section (9 positions)**
- Torso, arms, ribs, hips
- Maximum coverage area
- Well-distributed across body

**Lower Section (3 positions)**
- Pelvis and upper legs
- Clear spacing

**Critical**: All positions maintain 8+ pixel minimum spacing to prevent clustering when scaled 2.8x during crit windows.

**Tool**: Use `scenes/tools/weakpoint_positioner.tscn` for visual editing of weakpoint positions.

### Multiplayer Crit/Weakpoint System Design ✅ IMPLEMENTED

**Current Implementation**: All-client visibility with server-authoritative crit rolls and damage

#### Weakpoint Ownership Model

**Owner-Only Visibility**:
- Only the player who triggers a crit sees the weakpoints on that target
- Multiple players can have simultaneous crit windows on the same enemy
- Each player's weakpoints are independent (different positions, separate timers)
- Prevents "kill stealing" and creates fair damage distribution

**Example Scenarios**:

**PvE (Cooperative)**:
```
Player A crits Skeleton → Only Player A sees 3 weakpoints (red)
Player B crits same Skeleton → Only Player B sees 3 weakpoints (different positions)
Both players can attack their own weakpoints simultaneously
Fair damage: Each player gets rewarded for their own crits
```

**PvP (Competitive)**:
```
Player A crits Player C → Only Player A sees weakpoints on Player C
Player B does NOT see Player A's weakpoints (can't steal damage)
Player B can also crit Player C → Gets their own independent weakpoints
Skill-based: Your crits = your reward
```

#### Network Architecture

**Crit Trigger Event** (Client → Server):
```gdscript
{
    player_id: int,        # Who triggered the crit
    target_id: int,        # What they hit (enemy or player)
    timestamp: float       # When it happened
}
# Size: ~20 bytes per crit
```

**Weakpoint Spawn Response** (Server → Client):
```gdscript
{
    positions: [Vector2, Vector2, Vector2],  # 3 weakpoint locations
    expires_at: float,                        # Window duration
    window_id: int                            # Unique crit window identifier
}
# Size: ~50 bytes (sent only to owner)
```

**Weakpoint Hit Event** (Client → Server):
```gdscript
{
    player_id: int,        # Who clicked
    target_id: int,        # What they're hitting
    window_id: int,        # Which crit window
    weakpoint_index: int,  # Which weakpoint (0-2)
    click_position: Vector2, # Where they clicked (for validation)
    timestamp: float       # When they clicked
}
# Size: ~30 bytes per hit
```

#### Server-Side Validation

**Active Crit Window Tracking**:
```gdscript
# Server maintains state for all active crit windows
var active_crit_windows = {
    "player_123": {
        "window_456": {
            target_id: 789,
            weakpoints: [Vector2(10, -45), Vector2(-8, -32), Vector2(6, -18)],
            expires_at: 1234567890.5,
            hits_remaining: 3,
            created_at: 1234567886.5
        }
    }
}
```

**Validation Checks**:
1. **Ownership**: Does this player own this crit window?
2. **Timing**: Is the window still active (not expired)?
3. **Target**: Is the target still valid (alive, in range)?
4. **Spatial**: Is click position near actual weakpoint? (±20px tolerance for latency)
5. **Rate**: Is player clicking at humanly possible rate? (<15 clicks/sec)
6. **Pattern**: Does click timing show human variance? (anti-bot detection)

**Validation Function**:
```gdscript
func validate_weakpoint_hit(player_id: int, window_id: int, target_id: int,
                            weakpoint_index: int, click_pos: Vector2) -> bool:
    # Check if player has this window
    if player_id not in active_crit_windows:
        return false  # No active windows

    var player_windows = active_crit_windows[player_id]
    if window_id not in player_windows:
        return false  # Invalid window ID

    var window = player_windows[window_id]

    # Validate target matches
    if window.target_id != target_id:
        return false  # Wrong target

    # Check expiration
    if Time.get_ticks_msec() / 1000.0 > window.expires_at:
        player_windows.erase(window_id)
        return false  # Window expired

    # Validate weakpoint index
    if weakpoint_index < 0 or weakpoint_index >= window.weakpoints.size():
        return false  # Invalid index

    # Spatial validation (allow 20px tolerance for latency)
    var actual_pos = window.weakpoints[weakpoint_index]
    if click_pos.distance_to(actual_pos) > 20.0:
        log_suspicious_activity(player_id, "Click too far from weakpoint")
        return false  # Suspicious click position

    # Rate limiting check
    if not check_click_rate(player_id):
        log_suspicious_activity(player_id, "Click rate too high")
        return false  # Clicking too fast

    # Valid hit!
    window.hits_remaining -= 1
    if window.hits_remaining <= 0:
        player_windows.erase(window_id)  # Window complete

    return true
```

#### Anti-Cheat System

**1. Client-Side Obfuscation**:
- Weakpoints only rendered for owner (other players can't see positions)
- Weakpoint positions randomized server-side (client can't predict)
- Visual elements use generic node names (harder to memory-scan)

**2. Server-Side Enforcement**:
- All weakpoint hits validated server-side
- Reject hits from non-owners immediately
- Track and log suspicious patterns

**3. Rate Limiting**:
```gdscript
# Track clicks per player
var player_click_history = {}  # player_id: [timestamp1, timestamp2, ...]

func check_click_rate(player_id: int) -> bool:
    var now = Time.get_ticks_msec() / 1000.0

    # Initialize history
    if player_id not in player_click_history:
        player_click_history[player_id] = []

    var history = player_click_history[player_id]

    # Remove clicks older than 1 second
    history = history.filter(func(t): return now - t < 1.0)

    # Check if too many clicks in last second
    if history.size() >= 15:  # Max 15 clicks/sec (human limit ~10-12)
        return false  # Too fast!

    # Add this click
    history.append(now)
    player_click_history[player_id] = history

    return true
```

**4. Pattern Analysis**:
```gdscript
# Detect bot-like consistent timing
func analyze_click_pattern(player_id: int) -> float:
    var history = player_click_history[player_id]
    if history.size() < 5:
        return 0.0  # Not enough data

    # Calculate variance in click intervals
    var intervals = []
    for i in range(1, history.size()):
        intervals.append(history[i] - history[i-1])

    # Human clicks have variance, bots are consistent
    var variance = calculate_variance(intervals)

    # Low variance = suspicious (< 0.01s variance)
    if variance < 0.01:
        return 1.0  # High suspicion score

    return 0.0  # Normal variance
```

**5. Success Rate Monitoring**:
```gdscript
# Track weakpoint hit accuracy
var player_stats = {}  # player_id: {hits: int, misses: int}

func track_weakpoint_attempt(player_id: int, success: bool):
    if player_id not in player_stats:
        player_stats[player_id] = {hits: 0, misses: 0}

    if success:
        player_stats[player_id].hits += 1
    else:
        player_stats[player_id].misses += 1

    # Check accuracy over time
    var stats = player_stats[player_id]
    var total = stats.hits + stats.misses

    if total > 100:  # After 100 attempts
        var accuracy = float(stats.hits) / float(total)
        if accuracy > 0.95:  # >95% accuracy is suspicious
            log_suspicious_activity(player_id, "Unusually high accuracy: %.2f" % accuracy)
```

**6. Spatial Validation**:
- Server knows exact weakpoint positions
- Compares client click position to actual position
- Allows 20px tolerance for network latency
- Repeated off-target hits = flagged

#### Performance & Scale Estimates

**Network Traffic Per Crit Window**:
- Crit trigger: 20 bytes
- Weakpoint spawn: 50 bytes (to owner only)
- 3 weakpoint hits: 90 bytes (30 bytes × 3)
- **Total: ~160 bytes per complete crit window**

**Scale Calculations** (15 players, active combat):
- Average player stats at mid-level:
  - 5 attacks/second
  - 50% crit rate
  - 2.5 crits/second per player
- 15 players × 2.5 crits/sec = **37.5 crit windows/second**
- Network traffic: 37.5 × 160 bytes = **6 KB/second** (negligible!)

**Maximum Supported Players**:

| Scenario | Players | Crits/sec | Network | Feasible? |
|----------|---------|-----------|---------|-----------|
| Small PvP | 5-10 | 12-25 | 2-4 KB/s | ✅ Excellent |
| Medium PvP | 10-15 | 25-37 | 4-6 KB/s | ✅ Great |
| Large PvP | 15-25 | 37-62 | 6-10 KB/s | ✅ Good |
| World PvE | 50+ | 125+ | 20 KB/s | ✅ Manageable |

**Optimization: Spatial Partitioning**:
- Only send crit events to nearby players (within 1000px radius)
- Reduces network traffic by ~70% in spread-out combat
- 50 players across large world: Only 10-15 players receive each event

**Client Performance** (15 players visible):
- Render only YOUR weakpoints: 3 nodes × 60 FPS = negligible
- Other players' crit windows: Subtle glow effect (1 shader per enemy)
- Particle effects: Cull when >10 simultaneous crit windows
- **Target: 60 FPS with 15 players in combat**

#### Visual Clarity (Multi-Player)

**Your Weakpoints** (High Priority):
- Full brightness (themed colors: blood/bone)
- z_index 400 (top layer)
- Full particle effects
- Clear hit indicators

**Other Players' Crit Windows** (Low Priority):
- Subtle enemy glow (white outline, 0.3 alpha)
- z_index 50 (behind UI)
- No weakpoint markers visible
- Minimal particle effects

**UI Indicators**:
- "[Player Name] triggered crit window!" (brief notification)
- Enemy nameplate shows: "🎯 Active Crits: 3" (all players' windows)
- Your crit timer: Large, bright
- Others' crits: Small icon on enemy

#### Implementation Roadmap

**Phase 1: Multiplayer Foundation** ✅ COMPLETED
- Add Godot's built-in multiplayer (RPC/NetworkMultiplayerENet) ✅
- Implement server authority for combat ✅
- Add `network_id` to enemy and TrainingDummy nodes ✅
- Network attack and damage events ✅

**Phase 2: Crit Window Synchronization** ✅ COMPLETED
- Server generates weakpoint positions (server-authoritative) ✅
- Server rolls for crits (`_server_roll_for_crit()` in NetworkEnemyManager) ✅
- Broadcast weakpoint positions to all clients (`broadcast_crit_window_start()`) ✅
- Clients spawn weakpoints at server-provided positions ✅
- Server validates all weakpoint hits (`request_weakpoint_hit()`) ✅
- Broadcast weakpoint destruction to sync visual effects ✅

**Phase 3: Anti-Cheat Implementation** (Planned)
- Rate limiting system
- Pattern analysis for bot detection
- Spatial validation
- Success rate monitoring
- Admin tools for reviewing flagged players

**Phase 4: Optimization** (Planned)
- Spatial partitioning for network events
- Message batching (send every 50ms, not instantly)
- Client-side prediction for smooth gameplay
- Object pooling for weakpoint nodes
- Particle effect culling

**Phase 5: Testing & Tuning** (Planned)
- Stress test with 5, 10, 15, 25 players
- Measure network bandwidth and latency
- Tune anti-cheat thresholds
- Balance PvP crit window difficulty
- Optimize render performance

#### Code Structure (Implemented)

**NetworkEnemyManager.gd** - Central multiplayer coordinator:
```gdscript
# Server-side attack handling with crit roll
@rpc("any_peer", "reliable")
func request_attack(enemy_network_id: int, damage: float) -> void:
    var is_crit = _server_roll_for_crit(attacker_id)
    if is_crit:
        var crit_window_mgr = _get_server_crit_window_manager()
        crit_window_mgr.start_window(enemy)  # Triggers spawn_weakpoints()

# Broadcast crit window to all clients
func broadcast_crit_window_start(enemy_network_id: int, weakpoint_positions: Array):
    rpc("_client_crit_window_start", enemy_network_id, serialized_positions)

# Client receives and spawns weakpoints
@rpc("authority", "call_local", "reliable")
func _client_crit_window_start(enemy_network_id: int, serialized_positions: Array):
    enemy.grow_for_crit_window_client(weakpoint_positions)
```

**Enemy.gd** - Server spawns, broadcasts positions:
```gdscript
func spawn_weakpoints() -> void:
    # ... generate positions ...
    # In multiplayer, broadcast to clients
    if multiplayer.is_server() and network_id >= 0:
        network_enemy_mgr.broadcast_crit_window_start(network_id, chosen_positions)

func grow_for_crit_window_client(weakpoint_positions: Array) -> void:
    # Client-side: grow sprite and spawn weakpoints at server positions
    spawn_weakpoints_at_positions(weakpoint_positions)
```

**weakpoint.gd** - Client reports hits to server:
```gdscript
func _on_input(event):
    if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
        _report_hit_to_server()  # Send to server for validation
    else:
        hit()  # Server/single player: process directly

func _report_hit_to_server():
    var weakpoint_index = find_self_in_parent_array()
    network_enemy_mgr.request_weakpoint_hit.rpc_id(1, enemy_net_id, weakpoint_index)
```

**NetworkEnemyManager.gd** - Weakpoint hit validation:
```gdscript
@rpc("any_peer", "reliable")
func request_weakpoint_hit(enemy_network_id: int, weakpoint_index: int):
    # Server validates and processes hit
    weakpoint.hit()
    # Broadcast destruction to all clients
    for peer_id in multiplayer.get_peers():
        _client_weakpoint_hit.rpc_id(peer_id, enemy_network_id, weakpoint_index, is_destroyed)
```

#### Security Considerations

**Trust Model**: Never trust the client
- Client sends: "I clicked here at this time"
- Server validates: "Is that a valid click for this player?"
- Server decides: "Apply damage or reject"

**Preventing Common Exploits**:
1. **Speed hacks**: Server tracks timing, rejects impossible sequences
2. **Teleport hacks**: Server validates player position relative to target
3. **Damage hacks**: Server calculates damage, client never sends damage values
4. **ESP/Wallhacks**: Weakpoints only sent to owner, can't see others' weakpoints
5. **Aimbots**: Spatial validation + pattern analysis detects perfect accuracy

**Logging & Monitoring**:
```gdscript
# Log suspicious activity
func log_suspicious_activity(player_id: int, reason: String):
    var log_entry = {
        player_id: player_id,
        timestamp: Time.get_unix_time_from_system(),
        reason: reason,
        severity: calculate_severity(reason)
    }

    # Store in database
    save_to_anticheat_log(log_entry)

    # Auto-kick for severe violations
    if log_entry.severity >= 8:
        kick_player(player_id, reason)
```

#### Future Enhancements

**Cooperative PvE Bonuses**:
- "Combo" system: If 2+ players hit weakpoints within 1 second → bonus damage
- Shared crit windows (opt-in): Party members can see each other's weakpoints
- Difficulty scaling: More players = more weakpoints (up to 5)

**PvP Balance**:
- Diminishing returns: Multiple crits on same player reduce window duration
- Crit resistance stat: Reduce weakpoint count or window duration
- Counter-crit: Getting crit triggers auto-crit window for defender

**Spectator Mode**:
- Show all players' weakpoints for spectators
- Combat analytics: Crit success rate, average weakpoint clear time
- Highlight reel: Best crit window clears

---

## Ruins System

### Ruins Campfire Location
- **Position**: (2184, -1216) - Dark spot on path
- **Skeleton Guardians**: 8 skeletons spawn and patrol
- **Guard Formation**: Skeletons form 180-unit radius circle around ruins
- **Conversion**: Player must kill at least 1 skeleton to convert ruins to campfire
- **Abandonment**: Campfire reverts to ruins after 2 minutes without player

### Skeleton Behavior
1. **Spawn**: Random positions 400-1000 units from ruins (avoiding main campfire and path)
2. **Patrol**: 5 second patrol at spawn location (RUINS mode) or skip patrol (CAMPFIRE mode)
3. **Converge**: Walk to designated guard position around ruins
4. **Guard**: Patrol 60-unit radius around designated position
5. **Respawn**: 60 second respawn timer after death

### Stuck Detection
- Checks every 3 seconds if skeleton moved <30 units
- Physical unstick: Move backwards 40px + random Y-axis shift (-50 to +50)
- Only triggers when actively moving (velocity > 5.0) and not paused

---

## Character System

### Gender Selection
At game start, players choose between:
- **MALE WARRIOR**: Original male character sprites
- **FEMALE WARRIOR**: Custom female character sprites with hair layer

**Character Sprites Required**:
- Walk: `BODY_[gender]_walk.png`
- Attack: `BODY_[gender]_slash.png`
- Hurt: `BODY_[gender]_hurt.png`
- Female Hair: `HAIR_female.png` (rendered over armor)

**Animation Structure** (LPC Format):
- Walk: 4 rows (up/left/down/right) × 9 frames
- Attack: 4 rows × 6 frames
- Hurt: 1 row × 6 frames

---

## Campfire System

### Main Campfire
- **Position**: (400, 0) - left side near spawn
- **Warmth Radius**: 150 units
- **Healing Rate**: 5 HP every 0.5 seconds while in warmth
- **Visual**: Animated flickering flames with warm glow circle

### Ruins Campfire
- **Position**: (2184, -1216) - converted from ruins
- **Requires**: Kill at least 1 skeleton guardian to activate
- **Abandonment Timer**: 2 minutes → reverts to ruins
- **Skeleton Behavior**: Spawn directly instead of patrolling first

### Enemy Deterrent
- Enemies blocked at campfire edge during combat
- Stay at edge with small frustrated movements (5% chance per frame)
- Provides strategic safe zone for player

---

## Z-Index Layering

Proper render order for all elements:
```
z = -10: Ground ColorRect (brown wasteland)
z = -9:  Ground patches/texture variations
z = -2:  Ground cracks, ash piles, path markers, castle
z = -1:  Trees, rocks, skulls, bones, swords (props)
z = 0:   Player, enemies, campfire (game entities)
```

---

## Important Data Files

### Core Files
- `scenes/game_world.tscn` - Complete world scene
- `scenes/world/campfire.tscn` - Animated campfire
- `scenes/world/ruins_campfire.tscn` - Ruins/campfire conversion system
- `prop_placements.json` - 2,500 prop positions
- `path_markers.json` - 25 path marker positions
- `bake_world_offline.tscn` - World texture baker
- `bake_world_offline.gd` - Baking script

### Scripts
- `scripts/game_world.gd` - Loads props dynamically, spawns enemies
- `scripts/player/Player.gd` - Player character with gender selection, F3 debug coordinates
- `scripts/enemies/Enemy.gd` - Enemy AI and weakpoint system
- `scripts/enemies/EnemyAI.gd` - Enemy patrol and combat AI
- `scripts/systems/Campfire.gd` - Main campfire healing and deterrent
- `scripts/systems/RuinsCampfire.gd` - Ruins conversion and skeleton management
- `scripts/systems/enemy_spawner.gd` - Enemy spawn system with respawn queue
- `scripts/ui/CombatText.gd` - Damage/heal floating numbers

---

## Known Issues & Notes

### Performance
- 2,500 props load at startup (check console for "Loaded 2500 / 2500 props")
- 15 enemy spawn points + 8 ruins skeletons
- Baked world system dramatically improves load times
- Exit freeze fixed with proper _exit_tree() cleanup

### Important Fixes
- **Exit Freeze**: Added _exit_tree() to RuinsCampfire and enemy_spawner to prevent 15-20s hang on quit
- **Skeleton 0 Bug**: Fixed by waiting one frame before spawning to ensure RuinsCampfire is in tree
- **Tree shadows**: Proper oval shadows that connect to tree base
- **Campfire deterrent**: Enemies block at edge instead of retreating
- **Debug labels**: Enemy names show above heads when F3 is on

---

## Controls & Debug

### Game Controls
- **WASD**: Move
- **Mouse**: Aim
- **Left Click**: Attack
- **Space**: Dodge roll (i-frames)
- **Mouse Wheel**: Camera zoom (disabled while shop is open)
- **C**: Character sheet (equipment, stats)
- **I / B**: Inventory
- **F**: Interact / Loot
- **Enter**: Open chat
- **ESC**: Close UI windows
- **F12**: Toggle screenshot mode

### Debug Controls
- **F3**: Debug mode toggle (shows coordinates, enemy names)
- **F4**: Add 1 level
- **F5**: Add 5 levels

### Chat Admin Commands (Host Only)
Type in chat when hosting a multiplayer game:
- **/help**: Show all admin commands
- **/accounts**: List all registered accounts
- **/select <username>**: Select account to edit
- **/info**: Show selected account details
- **/setpos <x> <y>**: Set player position
- **/resetpos**: Reset to campfire spawn
- **/setgold <amount>**: Set gold amount
- **/setlevel <1-30>**: Set player level
- **/setstats <str> <agi> <vit> <luck>**: Set base stats
- **/ban** / **/unban**: Toggle account ban
- **/forceoffline**: Fix stuck login state
- **/delete**: Delete selected account

### Group Commands
Type in chat to manage your party/group:
- **/invite <player>**: Invite a player to your group
- **/accept**: Accept pending group invite
- **/decline**: Decline pending group invite
- **/kick <player>**: Leader kicks a player from group
- **/leave**: Leave the current group
- **/promote <player>**: Leader promotes someone else to leader
- **/disband**: Leader disbands the entire group

---

## Group System

### Overview
Groups allow players to share campfire buffs and coordinate gameplay. Maximum group size is 40 players.

### GroupUI (Raid Frames)
- **Position**: Left side of screen below Level/XP display
- **Style**: WoW-style raid frames with Stone Gray theme
- **Features**:
  - Compact frames (120x40px) showing player name and health bar
  - Gold star (★) indicator for group leader
  - Cyan border highlight for your own frame
  - Health bar color changes: Green (>60%) → Yellow (30-60%) → Red (<30%)
  - Real-time health updates for all group members

### Group Mechanics
- **Creation**: Automatically created when first invite is accepted
- **Leadership**: Creator becomes leader, can promote others
- **Invites**: 60-second timeout on pending invites
- **Campfire Sharing**: Group members share campfire ownership and buffs

### Files
- `scripts/systems/GroupManager.gd` - Group state and commands
- `scripts/ui/GroupUI.gd` - Raid frame display
- `scripts/ui/GroupInvitePopup.gd` - Invite notification

---

## Campfire Ownership System

### Overview
Campfires can be claimed by a player or group. Only owners receive buffs, but everyone can see the auras (threat indicator for PvP scenarios).

### Claiming Ownership
- **First Fuel**: The first player to add fuel (wood or bone embers) claims ownership
- **Solo Players**: Claimed by individual peer ID
- **Groups**: Claimed by group (all members become owners)
- **New Members**: When invited to a group that owns a campfire, new members gain ownership

### Ownership Benefits (Owners Only)
- **Healing**: 5-25 HP/s based on wood fuel (5 base + 20 max at 50 wood)
- **Crit Buff**: 0-16.5% bonus crit chance based on bone embers (100 embers = max)

### Aura Visibility (Everyone)
- **Heal Aura**: Green circle, radius scales with wood (50-468px)
- **Crit Aura**: Orange/cyan circle, radius scales with bone embers (50-468px)
- All players see the owner's aura size (visual threat assessment)

### Release Timer
- **Trigger**: Starts when NO owner is within the aura radius
- **Duration**: 60 seconds countdown
- **UI**: Orange "Releasing: XXs" indicator above campfire
- **Cancellation**: Any owner returning to aura radius stops timer
- **Release**: Campfire becomes unowned, fuel preserved for next claimer

### Fuel System
- **Wood**: Max 50, increases heal rate
- **Bone Embers**: Max 100, increases crit buff
- **Decay**: Very slow (wood: 1/3000s, embers: 1/4500s)
- **Network Sync**: Ownership and fuel synced to all clients

### Strategic Implications
- Groups can claim ruins campfires as farming spots
- Approaching players see large auras = heavily buffed defenders
- Kill/chase away owners → 60s timer → claim their buffed campfire
- Fuel preserved on takeover (instant buff access)

---

## Art Style

### Pioneer/Revenant Theme
- Stick figure design with frontier aesthetic
- **Player**: Dark brown leather, simple hat, rugged palette
- **Enemies**: Dark red/crimson, aggressive pose, X-shaped eyes
- **Campfire**: Simple log arrangement with animated flame triangles
- **Ruins**: Stonehenge-style stonework with moss and bloodstains
- Minimal but expressive character design

---

## Troubleshooting

### Props Don't Appear
- Check Output tab for "Loaded 2500 / 2500 props"
- Props load dynamically at runtime from `prop_placements.json`

### Grey Areas Visible
- Should be fixed with extended ground coverage
- Ground now -5000 to 13000 x, -3000 to 3000 y

### Baking Freezes
- **Expected behavior** - let it run 1-5 minutes
- Console will show progress messages
- Will automatically complete and close

### Skeletons Getting Stuck
- Stuck detection runs every 3 seconds
- Physical repositioning (backwards + Y-shift) automatically applied
- If persistent, check console for spawn_position errors

### Game Freezes on Exit
- Should be fixed with _exit_tree() cleanup
- If still occurs, check for await statements in _physics_process() loops

### Can't Convert Ruins
- Must kill at least 1 skeleton guardian first
- Press E when within 100 units of ruins center
- Check console for "⚔️ Must defeat at least one skeleton guardian" message

---

## Technical Notes

### Async/Await Best Practices
- **NEVER** use `await` inside `_physics_process()` or `_process()` loops
- Use helper functions to call async operations without blocking
- Always implement `_exit_tree()` to stop processing on exit

### State Management
- RuinsCampfire uses enum states: RUINS, CAMPFIRE
- Skeleton states: PATROLLING_SPAWN, WALKING_TO_RUINS, GUARDING_RUINS
- Enemy AI states: PATROLLING, COMBAT, ATTACKING, RETREATING

### Signal Connections
- Enemy `died` signal connects to respawn systems
- Skeleton death signals to RuinsCampfire for tracking

---

## Vendor & Shop System

### Blacksmith Vendor
**Location**: Position (-253, -113) near player spawn
- Interactive NPC with proximity detection (80 pixel radius)
- Press **E** to open shop when in range
- Shop automatically closes if player walks away

### Shop UI Features
**Interface**:
- Centered CanvasLayer UI (doesn't pause gameplay)
- Tabbed interface: Weapons / Armor
- Scrollable item lists with detailed information
- Real-time gold display
- Toggle with E or ESC key

**Item Display**:
- Item name with rarity-based color coding
- Description and full stats
- Price in gold
- Level requirements
- Buy buttons (auto-disabled if can't afford or don't meet level)
- Visual feedback messages for purchases

**Rarity Colors**:
- White: Common
- Yellow-Green: Uncommon
- Blue: Rare
- Purple: Epic
- Orange: Legendary

### Currency System
- **Gold**: Used for purchasing equipment
- Starting gold: 500 (for testing)
- Managed through CharacterStats autoload
- Methods: `can_afford()`, `spend_gold()`, `add_gold()`

### Shop Inventory

**Weapons** (6 available):
1. Wooden Club - 0 gold (Dmg: 3.0) - Common
2. Iron Sword - 100 gold (Dmg: 8.0, +2% crit) - Common, Lv 3
3. Steel Blade - 300 gold (Dmg: 15.0, +5% crit, -5% speed) - Uncommon, Lv 6
4. Battle Axe - 600 gold (Dmg: 25.0, +8% crit, +15% speed) - Uncommon, Lv 10
5. Mithril Sword - 1200 gold (Dmg: 35.0, +10% crit, -15% speed) - Rare, Lv 15
6. Dragon Slayer - 2500 gold (Dmg: 50.0, +15% crit, -10% speed) - Epic, Lv 20

**Armor** (7 available):
1. Leather Vest - 50 gold (+5 Def)
2. Chainmail Armor - 250 gold (+12 Def)
3. Plate Armor - 800 gold (+25 Def)
4. Leather Boots - 30 gold (+2 Def)
5. Iron Boots - 200 gold (+5 Def)
6. Leather Gloves - 30 gold (+2 Def)
7. Iron Helm - 150 gold (+8 Def)

### Data Files
- `data/shop_weapons.json` - Weapon definitions with stats
- `data/shop_armor.json` - Armor definitions with stats
- JSON format allows easy addition of new items

### Technical Implementation
**Scripts**:
- `scripts/systems/Vendor.gd` - Vendor NPC logic, proximity detection
- `scripts/ui/ShopUI.gd` - Shop interface and purchase system
- `scenes/npcs/vendor.tscn` - Vendor scene with Area2D collision
- `scenes/ui/shop_ui.tscn` - Shop UI layout

**Features**:
- Player must be in "player" group for vendor detection
- Shop UI disables camera zoom while open
- Dynamic item row generation with proper styling
- Purchase validation (gold, level requirements)
- Signal-based communication between vendor and UI

---

## UI Systems

### Layer Hierarchy
UI elements are organized by CanvasLayer levels:
- **Layer 40**: Interaction prompts (campfire fuel, etc.)
- **Layer 50**: Controls/hints panel, NPC interaction prompts
- **Layer 110**: Main UI windows (Chat, Inventory, Character)
- **Layer 1000**: FPS overlay (debug)

### Character UI (`scripts/ui/CharacterUI.gd`)
- **Toggle**: Press C key
- **Features**: Equipment paperdoll, stat display, tool slots
- **Equipment Slots**: Head, chest, arms, hands, legs, feet, mainhand, offhand
- **Tool Slots**: Axe, pickaxe (for harvesting)
- **Drag-Drop**: Unequip items by dragging to inventory

### Inventory UI (`scripts/ui/InventoryUI.gd`)
- **Toggle**: Press I or B key
- **Features**: 20-slot grid, drag-drop support, item deletion
- **Positioning**: Bottom-right corner, grows upward
- **Icons**: Procedurally generated by ItemIconGenerator
- **Stack Display**: Bottom-right corner of slot shows quantity

### Chat UI (`scripts/ui/ChatUI.gd`)
- **Toggle**: Press Enter to focus input
- **Features**: Multiplayer chat, admin commands, hover fade effect
- **Positioning**: Bottom-left corner (570x320)
- **Fade Effect**: 30% opacity when not hovered, 100% when active
- **Admin Commands**: Type /help for list (host only)

### ItemIconGenerator (`scripts/systems/ItemIconGenerator.gd`)
Procedurally generates icons for items without pre-made sprites:
- **Weapons**: Extracts from LPC sprite sheets (slash.png)
- **Tools**: Extracts from walk.png sprite sheets
- **Armor**: Uses equipped slot sprites
- **Materials**: Procedurally drawn (bones, gems, coins, etc.)

---

## Notification System

### NotificationManager (Global Autoload)
Global notification system for displaying item gain/loss notifications throughout the game with rarity-colored text and smooth cascade animations.

**Location**: `scripts/systems/NotificationManager.gd` (autoload)
**Scene**: `scenes/ui/item_notification.tscn`
**Script**: `scripts/ui/ItemNotification.gd`

### Features
- **Rarity-Based Colors**: Items displayed in color matching their rarity
- **Cascade Animation**: Notifications smoothly shift upward as new items are gained
- **Pop-In Effect**: Scale-based pop-in with smooth bounce
- **Fade-Out**: Clean fade-out after 2 seconds
- **Queue Management**: Multiple notifications stack gracefully without overlapping

### Rarity Colors
```gdscript
COMMON:    Color(0.8, 0.8, 0.8, 1.0)  # Light gray
UNCOMMON:  Color(0.4, 0.9, 0.4, 1.0)  # Green
RARE:      Color(0.4, 0.6, 1.0, 1.0)  # Blue
EPIC:      Color(0.8, 0.4, 1.0, 1.0)  # Purple
LEGENDARY: Color(1.0, 0.7, 0.2, 1.0)  # Orange/gold
```

### API Reference
```gdscript
# Show item added notification (green indicator for positive action)
NotificationManager.notify_item_added(item_name: String, quantity: int = 1, rarity: String = "COMMON")

# Show item removed notification (red indicator for negative action)
NotificationManager.notify_item_removed(item_name: String, quantity: int = 1, rarity: String = "COMMON")
```

### Usage Examples
```gdscript
# Vendor purchase
NotificationManager.notify_item_added("Copper Plate Helmet", 1, "Common")

# Vendor sell
NotificationManager.notify_item_removed("Old Sword", 1, "Common")

# Loot pickup
NotificationManager.notify_item_added("Shadow Armguards", 1, "Epic")

# Inventory drop
NotificationManager.notify_item_removed("Health Potion", 5, "Common")
```

### Visual Design
- **Position**: Centered horizontally, 75% down screen (between player and bottom edge)
- **Width**: 400px (centered)
- **Animation Duration**:
  - Pop-in: 0.25s with bounce easing
  - Display: 2.0s total lifetime
  - Fade-out: 0.5s
- **Cascade Spacing**: 40px vertical spacing between notifications

### Technical Implementation
**Cascade System**:
1. When new notification arrives, existing notifications shift upward by 40px
2. New notification appears at bottom position (0, 0)
3. Shifting completes before new notification appears (prevents jitter)
4. On notification expiry, remaining notifications stay in place (no downward shift)

**Performance**:
- Lightweight Label nodes (minimal overhead)
- Tween-based animations (Godot optimized)
- Automatic cleanup when animations complete
- Queue managed with Array

**Integration Points**:
- Vendor shop (purchase/sell)
- Loot system (pickup/drop)
- Inventory UI (item management)
- Quest rewards (future)
- Crafting results (future)

### Configuration
```gdscript
# In NotificationManager.gd
var notification_spacing: float = 40.0  # Vertical spacing between notifications
# In ItemNotification.gd
var lifetime: float = 2.0  # How long notification stays visible
```

**Files**:
- `scripts/systems/NotificationManager.gd` - Autoload singleton managing notification queue
- `scripts/ui/ItemNotification.gd` - Individual notification label with animations
- `scenes/ui/item_notification.tscn` - Notification scene (Label with script)
- `project.godot` - NotificationManager added to autoload list

### Design Decisions
**Why No Gold Notifications?**
- Gold gain/loss already has audio feedback (coin sounds)
- Prevents notification spam during loot collection
- Keeps notifications focused on items (more important to track)
- Gold displayed in UI at all times (less need for notifications)

**Why Centered Position?**
- Visible but not intrusive
- Doesn't block combat (above player but below top UI)
- Easy to glance at without losing focus
- Consistent positioning for all notifications

---

## Environmental Hazards

### Lava Pools

Dangerous lava pools scattered throughout the wasteland that damage players who get too close.

#### Damage System
**Script**: `scripts/effects/LavaDamage.gd`

- **Damage Rate**: 15 HP per second
- **Damage Interval**: Applied every 0.5 seconds (7.5 HP per tick)
- **Safe Zone**: Outer 40% of pool radius (can walk around edges safely)
- **Danger Zone**: Inner 60% of pool radius triggers damage

**Detection**:
- Uses Area2D with CircleShape2D collision
- Detects players on collision layer 1
- Continuous damage while player remains in danger zone
- Instant damage on entry, stops on exit

#### Visual Animation
**Script**: `scripts/effects/LavaPoolAnimation.gd`

**Layered Structure**:
- 3 border layers (outer, middle, inner)
- 10 gradient layers creating depth effect
- Each layer pulses independently

**Pulsing Animation**:
- Inner (hotter) layers pulse faster than outer layers
- Frequency range: 0.5 Hz (outermost) to 1.22 Hz (innermost)
- ±20% random variation per pool (prevents synchronization)
- Subtle 3% scale variation (0.97x to 1.03x)
- Random phase offsets prevent layers from syncing

**Visual Effect**:
- Creates organic "flowing lava" appearance
- Each pool looks unique due to randomization
- Maintains performance with lightweight scaling animations

#### Technical Implementation

**Crater Shape**:
- Rounded edges using bezier-like curves
- Multiple overlapping circles create natural roundness
- Gradient layers provide depth perception

**Collision Detection**:
```gdscript
# LavaDamage.gd
collision_layer = 0  # Don't exist on any layer
collision_mask = 1   # Detect player on layer 1

# Apply damage every 0.5 seconds
damage_timer += delta
if damage_timer >= damage_interval:
    damage_timer = 0.0
    apply_lava_damage()
```

**Performance**:
- Lightweight CPU-based animation (no shaders)
- Each pool is independent Node2D
- Minimal overhead (~10 pools = negligible FPS impact)

#### Placement Strategy

**Zone Distribution**:
- Zone 1 (Wasteland): 2-3 small pools
- Zone 2 (Cursed Lands): 4-5 medium pools
- Zone 3 (Shadow Realm): 6-8 large pools
- Zone 4 (Castle Approach): 3-4 strategic pools

**Strategic Placement**:
- Near enemy spawn points (adds combat complexity)
- Along narrow path sections (creates obstacles)
- Around ruins (environmental challenge during guardian fights)
- Never block critical paths completely

---

## Resource Gathering

### Harvestable Trees

Dead wasteland trees that can be chopped for wood, which sells for gold.

#### Core Mechanics
**Script**: `scripts/environment/HarvestableTree.gd`

**Interaction**:
- Press **F** when near tree to chop
- Interaction range: 60 pixel radius around tree trunk
- Floating prompt appears: "[F] Chop Tree" (light green text)
- Prompt positioned 10 pixels below player's feet

**Wood Yield** (based on tree size):
- Small trees (scale < 2.5): 1 wood
- Medium trees (scale 2.5-4.0): 2 wood
- Large trees (scale > 4.0): 3 wood

**Resource Value**:
- Item name: "Dry Log"
- Description: "Dry wood from a dead wasteland tree. Burns well."
- Sell value: 12 gold per log
- Stackable: Yes (max 1000 per stack)

#### Respawn System

**Timing**:
- Respawn time: 120 seconds (2 minutes)
- Timer starts immediately after chopping
- Tree regrows automatically

**Visual States**:
1. **Alive Tree**: Full appearance with shadow
2. **Chopping Animation**: Tree fades out, falls upward, stump remains
3. **Stump**: Bottom 12% of tree sprite with jagged cut effect
4. **Respawn**: Tree fades back in over 0.5 seconds

#### Stump Generation

**Technical Details**:
- Extracts bottom 12% of tree texture
- Adds procedural jagged cut effect to top edge
- Random splinter depth: 3-7 pixels
- Brownish coloring: `Color(0.7, 0.6, 0.5)`
- Shadow remains visible under stump

**Jagged Cut Algorithm**:
```gdscript
for x in range(stump_width):
    var cut_depth = rng.randi_range(3, 7)  # Random splinters
    for y in range(cut_depth):
        var fade = 1.0 - (float(y) / float(cut_depth))
        pixel.a *= fade * rng.randf_range(0.3, 1.0)  # Fade edges
```

#### Economy Impact

**Income Source**:
- Alternative to combat for earning gold
- Safe activity (no combat required)
- Scales with player effort (more chopping = more gold)

**Balance**:
- 1 log = 12 gold (vs. 5-20 gold per enemy kill in Zone 1)
- Medium tree = 24 gold (comparable to 2-3 enemy kills)
- Respawn time limits farming (can't camp single tree)

**Strategy**:
- Efficient when traveling between zones
- Chop trees along path during journey
- Return to same trees after 2 minutes during grinding

#### Future Enhancements

**Crafting Integration**:
- Wood used for campfire building (custom spawn points)
- Craft wooden shields or clubs
- Build barricades for defensive gameplay

**Tool System**:
- Better axes = faster chopping
- Higher quality tools = bonus wood yield
- Durability system for tools

**Tree Varieties**:
- Oak, pine, dead trees with different yields
- Rare trees with special resources
- Seasonal variations (if day/night cycle added)

---

## Chain/Combo System

### Chain Mechanics

The chain system rewards consecutive successful crit window completions with escalating damage multipliers.

#### Core System
**Script**: `scripts/systems/chain_manager.gd`

**Chain Building**:
- Start at 0x multiplier
- Increase by 1x for each successful crit window (all weakpoints destroyed)
- Reset to 0x on any failure or timeout

**Damage Multiplier**:
- Base damage: 1.0x (no chain)
- Formula: `1.0 + (chain_level * 0.10)` = 10% damage per chain level
- Example progression:
  - 1x chain: 1.10x damage (+10%)
  - 5x chain: 1.50x damage (+50%)
  - 10x chain: 2.00x damage (+100% = OVERDRIVE!)

**Maximum Chain**: 10x (configurable via `Constants.CHAIN_MAX_LEVEL`)

#### Chain Timeout System

**Timeout Mechanics**:
- Duration: 4 seconds (configurable via `Constants.CHAIN_TIMEOUT`)
- Timer starts from last attack registered
- Resets on any player attack during crit window
- Chain breaks if no attack within timeout

**Reset Reasons**:
```gdscript
enum ResetReason {
    MANUAL,          # Player manually reset (future: keybind)
    FAILED_WINDOW,   # Failed to destroy all weakpoints
    TIMEOUT,         # No attack within timeout period
    PLAYER_DEATH,    # Player died
    STAGE_END        # Level/stage ended (future)
}
```

#### Overdrive Mode

**Activation**:
- Triggered at maximum chain (10x)
- 2.0x total damage multiplier
- Special visual effects
- Maximum risk/reward state

**Overdrive Signals**:
```gdscript
signal overdrive_activated()  # Emitted when reaching max chain
```

**Audio Feedback**:
- Milestone sound every 5 chain levels
- Special OVERDRIVE sound at max chain
- Chain broken sound on reset

#### UI Display
**Script**: `scripts/ui/chain_ui.gd`

**Visual Tiers** (color-coded by chain level):
- 0x: Gray `Color(0.5, 0.5, 0.5)` - No chain
- 1-3x: White `Color(1.0, 1.0, 1.0)` - Low chain
- 4-6x: Yellow `Color(1.0, 1.0, 0.0)` - Medium chain
- 7-9x: Orange `Color(1.0, 0.5, 0.0)` - High chain
- 10x: Magenta `Color(1.0, 0.0, 1.0)` - OVERDRIVE!

**Display Format**:
- Shows "Chain: Nx" where N is current chain level
- Updates in real-time via signal connections
- Positioned in top-left corner of screen

#### Integration with Combat

**Crit Window Completion**:
```gdscript
# Called when crit window ends
ChainManager.on_crit_window_completed(all_weakpoints_destroyed)

# If all weakpoints destroyed: chain++
# If any weakpoint survived: chain reset to 0
```

**Damage Application**:
```gdscript
# In Player.gd or Enemy.gd
var multiplier = ChainManager.get_damage_multiplier()
var final_damage = base_damage * multiplier
```

**Chain Registration**:
```gdscript
# Register attack to reset timeout timer
ChainManager.register_attack()
```

#### Gameplay Strategy

**Risk vs Reward**:
- Higher chains = massive damage boost
- One mistake = lose all progress
- Creates tension during long fights

**Skill Expression**:
- Skilled players maintain high chains
- Rewards precision and focus
- Punishes mistakes with full reset

**Combat Pacing**:
- Encourages aggressive play (maintain chain)
- Discourages hit-and-run tactics (timeout penalty)
- Creates flow state during combat

#### Multiplayer Considerations

**Per-Player Chains**:
- Each player has independent chain level
- No shared chains between party members
- Allows individual skill expression

**Competitive Element**:
- Players can compete for highest chain
- Leaderboards for max chain achieved
- "Most chains broken" stat tracking (for fun)

**Cooperative Bonus (Future)**:
- Party-wide chain multiplier
- Bonus if all party members maintain high chains
- Encourages coordination

---

## Training Dummy

### Purpose

The training dummy provides a safe, controlled environment for testing combat mechanics, practicing crit windows, and experimenting with chain building.

#### Location & Setup
**Script**: `scripts/training/TrainingDummy.gd`

**Placement**:
- Near main campfire (safe zone)
- Accessible from game start
- Does not fight back

**Visual Design**:
- Wooden mannequin appearance
- Clear target for new players
- Labeled "Training Dummy"

#### Features

**Invulnerability**:
- Cannot be killed (infinite HP)
- Takes damage normally (displays damage numbers)
- Regenerates after each hit
- Always available for practice

**Crit Window Testing**:
- Triggers crit windows on critical hits (same as enemies)
- Spawns 1-3 weakpoints based on player level
- 4 second window duration (same as combat)
- Perfect for practicing weakpoint clicking

**Combat Text Positioning**:
- Damage numbers spawn 40px behind dummy (away from player)
- Prevents overlap with weakpoints
- Same positioning logic as enemies

**Chain Building Practice**:
- Fully integrates with ChainManager
- Successful crit completions increase chain
- Failed windows reset chain
- Safe environment to learn chain mechanics

#### Use Cases

**New Player Tutorial**:
1. Learn basic attack mechanics
2. Understand crit window triggers
3. Practice clicking weakpoints quickly
4. Experience chain system safely

**Testing Builds**:
- Test weapon damage output
- Verify stat bonuses working
- Check crit chance calculations
- Measure DPS over time

**Practicing Combos**:
- Build chain to 10x safely
- Practice maintaining chain under pressure
- Develop muscle memory for weakpoint patterns

**Experimenting with Gear**:
- Compare weapon damage side-by-side
- Test armor defense values (future: dummy can attack back)
- Verify enchantment effects

#### Technical Implementation

**Damage Handling**:
```gdscript
func take_damage(damage: float, is_critical: bool = false) -> void:
    # Display combat text
    spawn_combat_text(damage)

    # Trigger crit window if critical hit
    if is_critical and weakpoint_scene:
        spawn_crit_window()

    # No HP deduction - dummy is invulnerable
```

**Weakpoint System**:
- Uses same weakpoint positions as skeleton enemies
- Same sectioned spawning algorithm
- Same 8+ pixel spacing rules
- Identical visual appearance

**Signals**:
- Connects to ChainManager signals
- Emits same events as real enemies
- Fully participates in combat systems

#### Future Enhancements

**Combat Dummy (Advanced)**:
- Fights back with configurable attack speed
- Adjustable damage output
- Practice dodging/kiting

**DPS Meter**:
- Displays damage over time
- Shows average DPS
- Tracks crit rate percentage

**Difficulty Settings**:
- Easy: Slower weakpoint timers
- Normal: Standard timers
- Hard: Faster weakpoint expiration

**Multiple Dummies**:
- AoE practice dummy (multiple targets)
- Moving dummy (practice tracking)
- Boss dummy (simulates boss mechanics)

---

## Next Steps & Planned Features

### Armor System - COMPLETE ✅

**See [ARMOR_SYSTEM.md](ARMOR_SYSTEM.md) for full documentation**

The game has a **fully functional 5-layer modular armor system**:
- ✅ 5 armor slots (head, chest, arms, legs, feet)
- ✅ Drag-and-drop equipping via Character Sheet UI
- ✅ Multi-layer sprite rendering with animation sync
- ✅ Defense calculation and stat bonuses
- ✅ **Copper Armor Tier 1** - Complete reference template (13 animations × 5 pieces)

**Copper Armor Set** serves as the base template for all future armor tiers.

### High Priority
1. **Additional Armor Tiers**
   - Bronze armor (Tier 2) for Ruins 2 / Zone 2
   - Iron armor (Tier 3) for Ruins 3 / Zone 3
   - Steel/Legendary armor (Tier 4-5) for endgame
   - Follow Copper Tier 1 template structure

2. **Gold Rewards**
   - Add gold drops from enemies
   - Scale gold rewards by enemy difficulty/level
   - Ruins skeletons drop more gold than regular enemies
   - Boss/elite enemies special gold bonuses

3. **Save System**
   - Save player progress (level, stats, gold)
   - Save equipped weapons and owned armor
   - Save world state (ruins converted, enemies killed)
   - Auto-save and manual save options

### Medium Priority
4. **Additional Vendors**
   - Potion vendor (health/mana consumables)
   - Enchanter (weapon/armor upgrades)
   - Multiple vendor locations along the path

5. **Inventory System**
   - Weapon switching (own multiple weapons)
   - Armor sets and bonuses
   - Consumable items (potions, food)
   - Inventory UI with tabs

6. **Quest System**
   - Tutorial quests near campfire
   - Kill X enemies quests
   - Reach castle quest
   - Convert ruins quest
   - Quest rewards (gold, items, XP)

7. **Character Progression**
   - Skill trees or talent points
   - Stat allocation on level up
   - Passive abilities unlock
   - Class specializations

### Polish & Balance
8. **Shop Enhancements**
   - Sell items back to vendors (50% value)
   - Item comparison tooltips
   - "New!" badges for recently added items
   - Limited stock or rotating inventory
   - Vendor dialogue system

9. **Economy Balancing**
   - Adjust gold drop rates
   - Fine-tune item prices
   - Level requirement balancing
   - Testing progression curve

10. **UI/UX Improvements**
    - Minimap with vendor/campfire icons
    - Quick-access hotbar for consumables
    - Better visual feedback for shop interactions
    - Tooltip system for items
    - Stats comparison (current vs new weapon)

### Long-term Features
11. **Multiplayer/Social**
    - Trading between players
    - Shared vendor shops
    - Player marketplace
    - Co-op combat

12. **Advanced Systems**
    - Crafting system
    - Enchanting/upgrading equipment
    - Rare/legendary item drops from enemies
    - Achievement system
    - Leaderboards

---

## Healing System Design

**Philosophy**: Mirror combat mechanics for familiarity, enable healer role for group play

### Core Mechanics

**Friendly Targeting:**
- Click on friendly player (or self) to heal
- Auto-heal projectile shoots to target (visual only, instant application)
- Same targeting system as combat (click = action)

**Base Healing:**
- Scales with **VIT** (Vitality)
  - Formula: 20 HP + (VIT - 10) × 2
  - Level 10 (VIT 10): 20 HP per heal
  - Level 25 (VIT 58): 116 HP per heal
  - Encourages tank builds to off-heal

**Crit Heal:**
- **Crit chance**: Based on LUCK (same as combat)
  - Level 10 (LUCK 10): ~1% crit chance
  - Level 25 (LUCK 58): ~10% crit chance
- **Crit heal effect**: Opens 1-3 weakpoints on healed target
  - 1-3 weakpoints based on healer level (same breakpoints as combat)
  - Level 1-10: 1 weakpoint
  - Level 11-20: 2 weakpoints
  - Level 21+: 3 weakpoints

**Crit Heal Weakpoints:**
- **Owner-only**: Only healer sees their heal weakpoints
- **Green visual theme**: Green particles, green combat text, green weakpoints
- **4 second window**: Same duration as combat crit windows
- **Click weakpoints for 2x heal**:
  - Base heal: 116 HP
  - Crit heal weakpoint: 232 HP (2x)
  - 3 weakpoints: 696 HP total burst (3 × 232)

### Visual Design

**Colors:**
- Combat: Red (damage) / Yellow (crit)
- Healing: Green (heal) / Bright Green (crit heal)

**Particles:**
- Green mist instead of blood spray
- Upward-floating sparkles (healing energy)
- Gentle glow on healed player

**Combat Text:**
- "+116" in green (instead of red damage)
- Floats upward (instead of outward)
- Larger text for crit heals

**Weakpoints:**
- Same sectioned positions as combat
- Green color theme (instead of red/white)
- Same click detection and validation

### Balance Mechanics

**Cooldown:**
- 1-2 seconds between heals
- Prevents spam healing
- Creates decision-making (who to heal?)

**Combat Healing Penalty:**
- 50% effectiveness if target damaged in last 3 seconds
- Prevents "unkillable" tanks
- Encourages proactive healing (before damage)

**Diminishing Returns:**
- Repeated heals on same target = reduced effectiveness
- Stack decay: 5 seconds
- Example:
  - 1st heal: 100 HP
  - 2nd heal (within 5s): 90 HP
  - 3rd heal (within 5s): 81 HP
  - After 5s: Reset to 100 HP

**Range:**
- Same as attack range: 100 pixels
- Forces healers to stay near party
- Creates positioning gameplay

### Stat Synergy

**Pure Healer Build (VIT + LUCK):**
- High VIT: Strong base heals (116 HP at level 25)
- High LUCK: Frequent crit heals (~10% chance)
- Low damage output
- Group-focused playstyle

**Tank/Off-Healer Build (VIT + STR):**
- Moderate VIT: Decent heals (80-100 HP)
- High STR: Can deal damage
- Low crit heal chance
- Solo + duo viable

**Hybrid Build (Balanced stats):**
- Moderate heals (60-80 HP)
- Can DPS or heal as needed
- Flexible playstyle

### Multiplayer Implementation

**Server-Authoritative:**
- Server validates heal target is friendly
- Server calculates heal amount based on healer's VIT
- Server determines crit heal (LUCK-based)
- Server generates weakpoint positions (if crit)
- Server sends weakpoints ONLY to healer (owner-only)

**Network Messages:**
```gdscript
// Heal trigger (Client → Server)
{
    healer_id: int,
    target_id: int,
    timestamp: float
}

// Heal response (Server → Healer)
{
    heal_amount: float,
    is_crit: bool,
    weakpoint_positions: [Vector2, ...],  // Only if crit
    window_id: int
}

// Heal effect (Server → All Clients)
{
    target_id: int,
    new_hp: float,
    heal_amount: float,  // For combat text
    is_crit: bool
}
```

**Weakpoint Validation:**
- Same as combat weakpoints
- Healer clicks weakpoint → Server validates ownership
- Server checks: position, timing, rate limiting
- Server applies 2x heal if valid

### Role Design

**Healer Role Benefits:**
- **Lower mechanical skill floor**: Healing is more forgiving than DPS
- **High skill ceiling**: Crit heal weakpoints reward good clicking
- **Social gameplay**: "Carry your friends" appeal
- **Strategic depth**: Who to heal? When to heal? Positioning?
- **Party enabler**: Makes group content viable

**Healer Weaknesses:**
- Low damage output (VIT build doesn't boost damage)
- Vulnerable when solo (can heal self but can't kill fast)
- Cooldown limits spam healing
- Combat penalty prevents face-tanking

### Group Dynamics

**Tank + Healer + DPS (3 players):**
- Tank (VIT build): Draws aggro, takes damage, off-heals
- Healer (VIT + LUCK): Main heals, crit heal bursts
- DPS (STR/AGI): Damage output, clicks weakpoints

**Duo (Tank + Healer OR DPS + Healer):**
- Tank + Healer: Slow but safe
- DPS + Healer: Fast clears, healer keeps DPS alive

**Solo:**
- Can self-heal (click yourself)
- Less effective than group healing
- VIT builds viable for solo sustain

### Future Enhancements

**Heal Over Time (HoT):**
- Crit heals apply HoT effect (10 HP/sec for 5 seconds)
- Stacks with burst healing

**Group Heal:**
- AoE heal (radius around target)
- Heals 3-5 nearby players for reduced amount
- High cooldown (30 seconds)

**Resurrection:**
- Revive dead party member
- Long cast time (5 seconds)
- Can be interrupted
- High cooldown (60 seconds)

**Mana/Resource System:**
- Healing costs mana
- Limits spam healing
- Adds resource management

---

## Development Roadmap: Path to Multiplayer Playtest

**Current State**: Single-player combat working with weakpoint system, level cap 30, 4-zone progression designed

**Goal**: First multiplayer playtest with 5-15 players testing PvP and co-op PvE

### Phase 0: Single-Player Content Completion (Current → 2-3 weeks)

**Status**: 60% complete

**Critical for Multiplayer Foundation**:
- [x] Basic combat system with crit windows
- [x] Weakpoint system (sectioned, level-based)
- [x] Level cap system (30 max, stats stop at 25)
- [x] Zone design (4 zones + boss)
- [x] Ruins 1 with 8 guardians
- [ ] **Ruins 2 & 3 implementation** ⭐ HIGH PRIORITY
  - Create Ruins 2 scene at position (4200, Y)
  - Create Ruins 3 scene at position (6000, Y)
  - 8x guardians each with proper level scaling
  - Vendor shops with tier-appropriate gear

- [ ] **Roaming enemies along path** ⭐ HIGH PRIORITY
  - Spawn system for levels 1-30 enemies
  - Patrol behavior (200-300px segments)
  - Smooth level progression (every ~300px)

- [ ] **Boss implementation** ⭐ MEDIUM PRIORITY
  - Level 33 Necromancer King scene
  - Boss arena at castle (7600, 0)
  - Choose mechanic: Phase transition, summons, or hazards
  - Door guardians (2x Level 30)

- [ ] **Loot system basics**
  - Gold drops from enemies (zone-scaled)
  - Weapon drops (3-10% based on zone)
  - Boss guaranteed legendary drop

- [ ] **Healing system basics** ⭐ HIGH PRIORITY (New!)
  - Friendly targeting (click player to heal)
  - Base healing calculation (VIT-based: 20 HP + (VIT-10) × 2)
  - Crit heal chance (LUCK-based, same as combat)
  - Crit heal weakpoints (green theme, 1-3 based on healer level)
  - Green visual effects (combat text, particles, weakpoints)
  - Test on training dummy or self-healing

**Can Wait for Post-Multiplayer**:
- Armor system (vendors already sell armor, just not equippable yet)
- Consumables/potions
- Quest system
- Advanced UI polish

**Estimated Time**: 2.5-3.5 weeks (+0.5 weeks for healing)
**Blockers**: None, all systems designed

---

### Phase 1: Multiplayer Foundation (4-5 weeks)

**Status**: Not started (design complete ✓)

**Goal**: Basic networking with 2-5 players in same world

**Core Networking**:
- [ ] **Godot multiplayer setup** ⭐ HIGH PRIORITY
  - ENetMultiplayerPeer for client-server model
  - Server hosting (dedicated server or player-hosted)
  - Client connection flow
  - Lobby system (5 player max for testing)

- [ ] **Player synchronization**
  - Sync player positions (smooth interpolation)
  - Sync player animations (walk, slash, hurt)
  - Sync player stats (level, HP, equipped weapon)
  - Player nameplate rendering

- [ ] **Basic combat sync**
  - Attack actions broadcast to nearby players
  - Damage calculations server-authoritative
  - HP updates synced to all clients
  - Death/respawn synchronization

**Enemy Synchronization**:
- [ ] **Server-authoritative enemies** ⭐ HIGH PRIORITY
  - Server spawns and controls all enemies
  - Enemy positions synced to clients
  - Enemy HP synced on damage events
  - Enemy death broadcast to all players

- [ ] **Enemy scaling by player count**
  - Detect nearby players (1000px radius)
  - Scale HP: Base × (1 + 0.4 × (players - 1))
  - Scale damage: Base × (1 + 0.1 × (players - 1))
  - Dynamic scaling as players join/leave area

**World State Sync**:
- [ ] Ruins conversion state synced
- [ ] Campfire warmth synced
- [ ] Vendor availability synced

**Healing System Networking** ⭐ NEW FEATURE:
- [ ] **Friendly targeting sync**
  - Click friendly player to heal (same targeting as combat)
  - Server validates heal target is friendly and in range
  - Sync heal projectile visuals to all clients

- [ ] **Healing calculations (server-authoritative)**
  - Server calculates heal amount based on healer's VIT
  - Server determines crit heal (based on LUCK)
  - Server applies healing to target HP
  - Broadcast HP updates to all clients

- [ ] **Crit heal weakpoints (owner-only)**
  - Server generates 1-3 weakpoint positions on healed target
  - Send positions ONLY to healer (owner-only)
  - Healer clicks weakpoints for 2x heal (same validation as combat)
  - Green visual theme (particles, combat text, weakpoints)

- [ ] **Healing balance**
  - Cooldown: 1-2 seconds between heals
  - Combat healing penalty: 50% effectiveness if target damaged in last 3 seconds
  - Diminishing returns: Repeated heals on same target less effective

**Testing Milestone**: 2-5 players can see each other, walk around, fight enemies together, AND heal each other

**Estimated Time**: 4-5 weeks (+1 week for healing networking)
**Blockers**: Need Phase 0 content complete for meaningful testing

---

### Phase 2: Multiplayer Combat & Weakpoints (2-3 weeks)

**Status**: Not started (design complete ✓)

**Goal**: Owner-only weakpoint system working, fair damage distribution

**Weakpoint System (Owner-Only)**:
- [ ] **Crit trigger networking** ⭐ CRITICAL
  - Client sends crit trigger to server
  - Server validates: legit crit, target valid, not cheating
  - Server generates 1-3 weakpoint positions (random sectioned)
  - Server sends positions ONLY to owner client

- [ ] **Weakpoint ownership tracking**
  - Add `owner_player_id` to weakpoint nodes
  - Client only renders weakpoints they own
  - Server tracks active crit windows per player
  - Auto-cleanup expired windows (4 second timeout)

- [ ] **Weakpoint hit validation** ⭐ CRITICAL
  - Client sends click position to server
  - Server validates:
    - Does player own this crit window?
    - Is window still active?
    - Is click position near actual weakpoint? (±20px)
    - Is click rate humanly possible? (<15/sec)
  - Server applies damage if valid, rejects if invalid
  - Broadcast weakpoint destruction to all clients (visual only)

**Visual Clarity**:
- [ ] Your weakpoints: Full brightness, z_index 400
- [ ] Other players' crit windows: Subtle enemy glow (white outline)
- [ ] Particle effects: Only for your weakpoints
- [ ] UI: "Player X triggered crit!" notifications

**Group XP & Loot**:
- [ ] **XP bonus system**
  - 2 players: 110% XP each
  - 3 players: 105% XP each
  - 4-5 players: 100% XP each

- [ ] **Loot distribution**
  - Gold split evenly (with group bonus)
  - Weapon drops: Personal loot (each player rolls)
  - Drop rate scaling: 3% solo → 10% in party

**Testing Milestone**: 5 players fighting same enemies, each getting their own crit windows, fair XP/loot

**Estimated Time**: 2-3 weeks
**Blockers**: Phase 1 networking must be stable

---

### Phase 3: Party System & Respawn (1-2 weeks)

**Status**: Not started

**Goal**: Players can form parties, respawn together, coordinate

**Party Mechanics**:
- [ ] **Party formation UI**
  - Invite/accept/decline system
  - Party list UI (5 player max)
  - Party leader designation

- [ ] **Party features**
  - Shared ruins conversion
  - Shared quest progress (future)
  - Party chat (future)
  - HP bars for party members

- [ ] **Respawn system**
  - Solo death: Respawn at nearest converted ruins
  - Party death: Can rejoin party
  - Party wipe: All respawn together at same ruins
  - 10% XP penalty on death

**Testing Milestone**: 5 players can form party, fight together, respawn correctly

**Estimated Time**: 1-2 weeks
**Blockers**: Phase 2 combat must be working

---

### Phase 4: Anti-Cheat Basics (1 week)

**Status**: Not started (design complete ✓)

**Goal**: Basic protections against common cheats

**Server Validation**:
- [ ] **Rate limiting**
  - Track clicks per player (15/sec max)
  - Track attacks per player (based on attack speed stat)
  - Reject impossible sequences

- [ ] **Spatial validation**
  - Player must be in range to attack enemy
  - Click position must be near weakpoint (±20px)
  - Player can't attack through walls

- [ ] **State validation**
  - Player can't hit weakpoints they don't own
  - Crit windows expire after 4 seconds
  - Dead players can't attack

**Logging**:
- [ ] Log suspicious activity (high click rate, off-target hits)
- [ ] Admin review tools (view flagged players)
- [ ] Auto-kick for severe violations (optional, testing only)

**Testing Milestone**: Cheaters get rejected, legitimate players unaffected

**Estimated Time**: 1 week
**Blockers**: Phase 2 weakpoint system must be working

---

### Phase 5: PvP Foundation (2-3 weeks)

**Status**: Not started

**Goal**: Players can attack each other, PvP combat works

**PvP Mechanics**:
- [ ] **Toggle PvP mode** (safe for testing)
  - Players opt-in to PvP
  - PvP zone markers (ruins to ruins?)
  - Non-PvP zones (campfires?)

- [ ] **Player vs player combat**
  - Attacks can target other players
  - Damage calculations (same as PvE)
  - Player death/respawn
  - XP loss on PvP death (5%?)

- [ ] **Crit windows on players**
  - Owner-only weakpoints (same as PvE)
  - Player can crit other players
  - Fair damage distribution

**Testing Milestone**: 5-10 players can PvP, crit system works, feels balanced

**Estimated Time**: 2-3 weeks
**Blockers**: Phase 2 & 3 must be solid

---

### Phase 6: Optimization & Polish (2 weeks)

**Status**: Not started

**Goal**: Smooth 60 FPS with 15 players in combat

**Network Optimization**:
- [ ] **Spatial partitioning**
  - Only send updates to nearby players (1000px radius)
  - Reduces network traffic by ~70%

- [ ] **Message batching**
  - Batch network messages every 50ms
  - Reduces packet spam

- [ ] **Client-side prediction**
  - Predict own movement locally
  - Smooth interpolation for other players

**Performance Optimization**:
- [ ] **Object pooling**
  - Pool weakpoint nodes (reuse instead of create/destroy)
  - Pool damage numbers
  - Pool particle effects

- [ ] **Particle culling**
  - Limit to 10 simultaneous crit windows on screen
  - Reduce particle counts when >5 players visible

- [ ] **Render optimization**
  - Cull offscreen enemies
  - Reduce shadow quality with many players
  - LOD system for distant players

**Testing Milestone**: 15 players in same zone, all fighting, 60 FPS maintained

**Estimated Time**: 2 weeks
**Blockers**: Need stress testing data from Phase 5

---

### Phase 7: First Multiplayer Playtest (GOAL!) 🎯

**Status**: Not started

**Goal**: 10-15 player playtest, gather feedback, iterate

**Playtest Scope**:
- [ ] **Content available**
  - All 4 zones (Wasteland → Castle)
  - Ruins 1, 2, 3 functional
  - Boss fight (Level 33)
  - Roaming enemies levels 1-30

- [ ] **Multiplayer features**
  - Party system (up to 5)
  - Owner-only weakpoints
  - Group scaling (HP/XP/loot)
  - Basic PvP (opt-in)
  - Respawn system

- [ ] **Testing goals**
  - Test solo vs duo vs group difficulty
  - Test boss with 1, 2, 3, 5 players
  - Test PvP balance
  - Find exploits/bugs
  - Gather performance data
  - Collect feedback on fun factor

**Success Criteria**:
- ✅ 10+ players can connect and play together
- ✅ 60 FPS with 15 players in combat
- ✅ No major bugs or crashes
- ✅ Combat feels fun and fair
- ✅ Weakpoint system works smoothly
- ✅ Players want to keep playing

**Estimated Time**: 1 week of testing + iteration
**Timeline from Start**: ~14-18 weeks (3.5-4.5 months)

---

### Post-Playtest Priorities

**Based on feedback, prioritize**:

**High Priority (Core Gameplay)**:
- Armor equipping system (vendors already sell it)
- Save/load system (preserve progress)
- Additional bosses or zones
- PvP balancing tweaks
- Guild/clan system

**Medium Priority (Polish)**:
- Quest system
- Consumables/potions
- Crafting system
- Achievement system
- Leaderboards

**Low Priority (Nice to Have)**:
- Advanced UI polish
- Minimap
- Trading system
- Player marketplace
- Cosmetics

---

### Quick Reference: Critical Path to Multiplayer

**Absolute Must-Haves** (Can't playtest without):
1. ✅ Zones 1-4 with enemies (Ruins 2 & 3 needed)
2. ✅ Boss fight (Level 33)
3. ✅ Networking foundation (Phase 1)
4. ✅ Owner-only weakpoints (Phase 2)
5. ✅ Party system (Phase 3)
6. ✅ Basic anti-cheat (Phase 4)
7. ✅ **Healing system** (Phase 0 & 1) - Attracts support players, enables healer role

**Should-Haves** (Playtest works but missing these hurts):
- PvP combat (can test PvE-only first)
- Optimization (can test with fewer players)
- Loot drops (can use vendor gear only)

**Nice-to-Haves** (Can add post-playtest):
- Armor equipping
- Save system
- Quests
- Advanced UI

---

### Timeline Summary

| Phase | Duration | Cumulative | Key Deliverable |
|-------|----------|------------|-----------------|
| Phase 0: Content + Healing | 2.5-3.5 weeks | 2.5-3.5 weeks | Ruins 2/3, roaming enemies, boss, healing basics |
| Phase 1: Networking + Healing | 4-5 weeks | 6.5-8.5 weeks | 5 players can connect, play, and heal each other |
| Phase 2: Weakpoints | 2-3 weeks | 8.5-11.5 weeks | Owner-only crits working |
| Phase 3: Party System | 1-2 weeks | 9.5-13.5 weeks | Parties, respawn, group play |
| Phase 4: Anti-Cheat | 1 week | 10.5-14.5 weeks | Basic cheat protection |
| Phase 5: PvP | 2-3 weeks | 12.5-17.5 weeks | Player vs player combat |
| Phase 6: Optimization | 2 weeks | 14.5-19.5 weeks | 60 FPS with 15 players |
| **Phase 7: PLAYTEST** | **1 week** | **15.5-20.5 weeks** | **🎯 First multiplayer test!** |

**Total Time to Playtest**: ~4-5 months (15.5-20.5 weeks)

**With Healing System Added:**
- +0.5 weeks to Phase 0 (healing basics)
- +1 week to Phase 1 (healing networking)
- Total added time: ~1.5 weeks

**Aggressive Timeline** (if focused full-time): 3.5 months
**Realistic Timeline** (part-time work): 4.5-5 months
**Conservative Timeline** (with setbacks): 6 months

---

This documentation reflects the current state of the Wasteland build.
