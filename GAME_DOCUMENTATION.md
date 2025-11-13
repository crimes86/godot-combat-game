# Rhythm RPG - Game Documentation

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

### Multiplayer Crit/Weakpoint System Design

**Design Philosophy**: Owner-only weakpoint visibility for fair PvP/PvE and optimal performance

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

**Phase 1: Multiplayer Foundation** (Current: Single-player working)
- Add Godot's built-in multiplayer (RPC/NetworkMultiplayerENet)
- Implement server authority for combat
- Add `owner_player_id` to weakpoint nodes
- Network crit trigger events

**Phase 2: Crit Window Synchronization**
- Server generates weakpoint positions (server-authoritative)
- Send positions only to owner
- Validate all weakpoint hits server-side
- Broadcast crit window notifications (for visual effects)

**Phase 3: Anti-Cheat Implementation**
- Rate limiting system
- Pattern analysis for bot detection
- Spatial validation
- Success rate monitoring
- Admin tools for reviewing flagged players

**Phase 4: Optimization**
- Spatial partitioning for network events
- Message batching (send every 50ms, not instantly)
- Client-side prediction for smooth gameplay
- Object pooling for weakpoint nodes
- Particle effect culling

**Phase 5: Testing & Tuning**
- Stress test with 5, 10, 15, 25 players
- Measure network bandwidth and latency
- Tune anti-cheat thresholds
- Balance PvP crit window difficulty
- Optimize render performance

#### Code Structure Changes

**Minimal changes to existing code!**

**Current (Single-Player)**:
```gdscript
# Enemy.gd
func spawn_weakpoints():
    for i in range(num_weakpoints):
        var weakpoint = weakpoint_scene.instantiate()
        weakpoint.position = chosen_positions[i]
        add_child(weakpoint)
```

**Future (Multiplayer)**:
```gdscript
# Enemy.gd (Server)
func spawn_weakpoints(owner_player_id: int):
    # Server generates positions
    var positions = generate_weakpoint_positions()

    # Send only to owner
    rpc_id(owner_player_id, "_receive_weakpoints", positions, window_id)

    # Track server-side
    register_crit_window(owner_player_id, get_instance_id(), positions)

# Enemy.gd (Client)
@rpc("authority", "call_remote")
func _receive_weakpoints(positions: Array, window_id: int):
    # Only spawn if we own this window
    for pos in positions:
        var weakpoint = weakpoint_scene.instantiate()
        weakpoint.position = pos
        weakpoint.owner_id = multiplayer.get_unique_id()
        weakpoint.window_id = window_id
        add_child(weakpoint)
```

**Weakpoint Click** (Multiplayer):
```gdscript
# weakpoint.gd
func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton and event.pressed:
        # Send to server for validation
        rpc_id(1, "_validate_weakpoint_hit",
               multiplayer.get_unique_id(),
               owner_id,
               get_parent().get_instance_id(),
               window_id,
               weakpoint_index,
               event.position)

# Server validates
@rpc("any_peer", "call_remote")
func _validate_weakpoint_hit(player_id, owner_id, target_id, window_id, index, pos):
    if validate_weakpoint_hit(player_id, window_id, target_id, index, pos):
        # Valid! Apply damage
        apply_crit_damage(target_id, player_id)
        # Notify all clients
        rpc("_weakpoint_destroyed", window_id, index)
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
- **Mouse Wheel**: Camera zoom (disabled while shop is open)
- **E**: Open/close vendor shop (when near vendor) OR Convert ruins to campfire (when in range and killed a skeleton)
- **ESC**: Close shop (when shop is open)
- **F**: Toggle character gender (MALE/FEMALE)
- **F12**: Toggle screenshot mode

### Debug Controls
- **F3**: Debug mode toggle (shows coordinates, enemy names)
- **F4**: Add 1 level
- **F5**: Add 5 levels

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

## Next Steps & Planned Features

### High Priority
1. **Armor Equipping System**
   - Implement armor slots (chest, boots, gloves, helm)
   - Apply defense bonuses to CharacterStats
   - Visual feedback when armor is equipped
   - Inventory management for owned armor

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

This documentation reflects the current state of the Rhythm RPG build.
