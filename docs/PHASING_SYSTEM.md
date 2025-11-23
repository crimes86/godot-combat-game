# Phasing System for Mini-MMO

## Why Phasing?

Your game has story progression (ruins conversion, boss kill) that conflicts with persistent shared world. Phasing solves this by showing different "versions" of the world to players based on their progress.

## Phase Definitions

### Phase 0: Tutorial (Solo Instance)
- **Trigger**: New character creation
- **Location**: Starting campfire area
- **Features**:
  - Solo instance (no other players visible)
  - Tutorial NPC appears
  - 5 weak training skeletons (level 1, 50 HP)
  - Cannot leave until tutorial complete
- **Exit Condition**: Kill 5 skeletons, reach level 2

### Phase 1: Zone 1 - Unconverted (Levels 1-8)
- **Trigger**: Complete tutorial
- **Location**: Campfire → Ruins 1
- **Features**:
  - Multiplayer (see other phase 1 players)
  - Ruins 1 is hostile (skeleton guardians attack)
  - Vendor is neutral (sells but doesn't help)
  - Roaming skeletons (level 1-8)
- **Exit Condition**: Defeat 8 guardian skeletons, activate Ruins 1 conversion ritual

### Phase 2: Zone 1 Converted, Zone 2 Unconverted (Levels 9-16)
- **Trigger**: Convert Ruins 1
- **Location**: Campfire → Ruins 1 → Ruins 2
- **Features**:
  - Ruins 1 is now friendly (guardians gone, vendor enhanced)
  - Zone 2 path unlocked
  - Roaming skeletons level 9-16
  - Ruins 2 hostile
- **Exit Condition**: Convert Ruins 2

### Phase 3: Zones 1-2 Converted, Zone 3 Unconverted (Levels 17-24)
- **Trigger**: Convert Ruins 2
- **Location**: Full map to Ruins 3
- **Features**:
  - Ruins 1 & 2 friendly
  - Zone 3 path unlocked
  - Roaming skeletons level 17-24
  - Ruins 3 hostile (strongest guardians)
- **Exit Condition**: Convert Ruins 3

### Phase 4: All Ruins Converted, Castle Locked (Levels 25-30)
- **Trigger**: Convert Ruins 3
- **Location**: Full map
- **Features**:
  - All ruins friendly
  - Castle visible but gate locked
  - Roaming elite skeletons level 25-30
  - "Prepare for final battle" quests
- **Exit Condition**: Reach level 30

### Phase 5: Endgame - Castle Accessible (Level 30+)
- **Trigger**: Reach level 30
- **Location**: Full map + castle interior
- **Features**:
  - Castle gate unlocked
  - Boss fight available (repeatable)
  - Endgame farming (best loot)
  - Daily boss respawn
- **No Exit**: Final phase

## Shared Zones (Cross-Phase)

Some areas visible across all phases:

### Starting Campfire
- All phases see all players here (social hub)
- Tutorial players see "Adventurer" title on high-level players
- Good for showing off gear, trading, grouping up

### Vendor Areas (Ruins)
- Vendors accessible to all phases
- Phase determines vendor inventory:
  - Phase 1-2: Basic gear (level 1-16)
  - Phase 3-4: Advanced gear (level 17-30)
  - Phase 5: Endgame gear + boss materials
- Players from different phases can shop together

### Open Paths
- Paths between ruins are shared
- Level 5 player might see level 25 player running past
- Encourages aspiration ("I want to get there!")

## Implementation

### Server-Side Phasing

```gdscript
# scripts/server/phasing_manager.gd
extends Node

var player_phases: Dictionary = {}  # peer_id -> phase_number

func get_player_phase(peer_id: int) -> int:
    return player_phases.get(peer_id, 1)

func set_player_phase(peer_id: int, phase: int):
    player_phases[peer_id] = phase
    _update_player_visibility(peer_id)

func _update_player_visibility(peer_id: int):
    var player_phase = get_player_phase(peer_id)
    var visible_players = []

    for other_id in player_phases:
        if other_id == peer_id:
            continue

        var other_phase = get_player_phase(other_id)
        var other_pos = ServerManager.get_player_position(other_id)

        # Check if should be visible
        if _should_see_player(peer_id, player_phase, other_id, other_phase, other_pos):
            visible_players.append(other_id)

    # Send visibility list to client
    rpc_id(peer_id, "update_visible_players", visible_players)

func _should_see_player(viewer_id: int, viewer_phase: int,
                         other_id: int, other_phase: int,
                         other_pos: Vector2) -> bool:
    # Tutorial phase (0) is always solo
    if viewer_phase == 0:
        return false

    # Same phase = always visible
    if viewer_phase == other_phase:
        return true

    # Check if in shared zone
    if _is_shared_zone(other_pos):
        return true

    # Different phase, not in shared zone = invisible
    return false

func _is_shared_zone(position: Vector2) -> bool:
    # Starting campfire (radius 500px from origin)
    if position.distance_to(Vector2(-2000, 0)) < 500:
        return true

    # Ruins vendor areas
    var ruins_positions = [
        Vector2(1400, -200),   # Ruins 1
        Vector2(4200, -200),   # Ruins 2 (placeholder)
        Vector2(6000, -200),   # Ruins 3 (placeholder)
    ]

    for ruins_pos in ruins_positions:
        if position.distance_to(ruins_pos) < 300:  # 300px vendor radius
            return true

    return false
```

### Phase-Specific Entities

```gdscript
# scripts/enemies/Enemy.gd
var spawn_phase: int = 1  # Which phase this enemy belongs to

func _ready():
    # Server sets visibility based on phase
    if multiplayer.is_server():
        _update_visibility_for_phases()

func _update_visibility_for_phases():
    # Only visible to players in matching phase
    for peer_id in ServerManager.connected_players:
        var player_phase = PhasingManager.get_player_phase(peer_id)
        var should_see = (player_phase == spawn_phase)
        rpc_id(peer_id, "set_enemy_visible", id, should_see)

# Client-side
@rpc("authority")
func set_enemy_visible(enemy_id: int, visible: bool):
    var enemy = get_node_or_null("Enemies/%d" % enemy_id)
    if enemy:
        enemy.visible = visible
        enemy.set_physics_process(visible)
```

### Phase Transitions

```gdscript
# scripts/server/phase_transition.gd

func trigger_ruins_conversion(player_id: int, ruins_number: int):
    var player_phase = PhasingManager.get_player_phase(player_id)

    # Validate player is at correct ruins
    if ruins_number != player_phase:
        push_warning("Player %d tried to convert wrong ruins" % player_id)
        return

    # Check if all guardians defeated
    var guardians_alive = _count_guardians(ruins_number, player_id)
    if guardians_alive > 0:
        rpc_id(player_id, "conversion_failed", "Defeat all guardians first")
        return

    # Advance player to next phase
    var new_phase = player_phase + 1
    PhasingManager.set_player_phase(player_id, new_phase)

    # Save to database
    Database.update_player_phase(player_id, new_phase)

    # Play conversion cutscene
    rpc_id(player_id, "play_conversion_cutscene", ruins_number)

    # Respawn player in new phase version of world
    await get_tree().create_timer(5.0).timeout  # Cutscene duration
    _respawn_in_new_phase(player_id, new_phase)

func _respawn_in_new_phase(player_id: int, phase: int):
    # Teleport to appropriate spawn point
    var spawn_pos = _get_phase_spawn_position(phase)
    ServerManager.set_player_position(player_id, spawn_pos)

    # Update visible entities
    PhasingManager._update_player_visibility(player_id)

    # Send confirmation
    rpc_id(player_id, "phase_transition_complete", phase)
```

## Boss Fight Phasing

Boss is repeatable in Phase 5, but each player has daily lockout.

```gdscript
# scripts/server/boss_manager.gd

func can_fight_boss(player_id: int) -> bool:
    var player_phase = PhasingManager.get_player_phase(player_id)

    # Must be phase 5
    if player_phase < 5:
        return false

    # Check daily lockout
    var last_kill = Database.get_last_boss_kill_time(player_id)
    var now = Time.get_unix_time_from_system()
    var one_day = 86400  # seconds

    if now - last_kill < one_day:
        return false

    return true

func start_boss_fight(player_id: int):
    if not can_fight_boss(player_id):
        rpc_id(player_id, "boss_unavailable", "Come back tomorrow")
        return

    # Create solo boss instance for this player
    var boss_instance = BossArena.new()
    boss_instance.player_id = player_id
    boss_instance.boss_level = 33
    add_child(boss_instance)

    # Teleport player into instance
    rpc_id(player_id, "enter_boss_instance", boss_instance.id)

func on_boss_defeated(player_id: int):
    # Record kill time
    Database.set_boss_kill_time(player_id, Time.get_unix_time_from_system())

    # Award loot
    var loot = LootTable.roll_boss_loot()
    PlayerInventory.add_items(player_id, loot)

    # Return to world
    rpc_id(player_id, "exit_boss_instance")
```

## Player Perspective

### What Players See:

**Phase 1 Player at Starting Campfire:**
- Sees other Phase 1 players (levels 1-8)
- Sees Phase 2-5 players (levels 9-30) - cross-phase zone
- Can chat with anyone
- Can inspect high-level gear for motivation

**Phase 1 Player at Ruins 1:**
- Sees Ruins 1 as hostile (guardians attacking)
- Sees only other Phase 1 players fighting
- Phase 2+ players are invisible here (different version of ruins)

**Phase 3 Player at Ruins 1:**
- Sees Ruins 1 as friendly (no guardians)
- Sees other Phase 3+ players
- Phase 1-2 players invisible (they're in hostile version)

### Benefits:

1. **Story Progression Works**: Each player experiences conversion
2. **Natural Grouping**: Similar-level players see each other
3. **Social Hubs**: Shared zones for community
4. **Repeatable Content**: Boss fight daily reset
5. **No Griefing**: High-level players can't camp low-level areas

### Challenges:

1. **Confusing for New Players**: Need good tutorial
2. **Can Feel Empty**: If only 2 phase 3 players online
3. **Friend Grouping**: What if friends are different phases?

## Friend Grouping Solution

```gdscript
# Allow higher phase player to "sync down" to friend's phase temporarily

func sync_to_friend_phase(player_id: int, friend_id: int):
    var player_phase = PhasingManager.get_player_phase(player_id)
    var friend_phase = PhasingManager.get_player_phase(friend_id)

    if player_phase <= friend_phase:
        # Already same or lower phase
        return

    # Temporarily set player to friend's phase
    PhasingManager.set_temporary_phase(player_id, friend_phase)

    # Notify
    rpc_id(player_id, "synced_to_friend_phase", friend_phase)
    rpc_id(player_id, "warning", "Stats/loot scaled to this phase")

func unsync_from_friend_phase(player_id: int):
    # Return to true phase
    PhasingManager.clear_temporary_phase(player_id)
```

## Performance

### Memory:
- Each phase reuses same world geometry (no duplication)
- Only entity visibility changes
- ~10MB overhead per phase

### CPU:
- Visibility checks run once per second (not every frame)
- O(n²) worst case but n is capped at 50 players
- Shared zones skip phase checks

### Network:
- Clients only receive updates for visible entities
- Phase transition sends one-time update packet
- No continuous overhead
