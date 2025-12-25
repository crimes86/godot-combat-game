# Item XP & Camp Grinding System Spec

## Vision

Even at max character level (30), players continue grinding to **level up their items**. This creates an infinite progression loop:

```
Kill Enemies → Item gains XP → Item levels up → Stronger stats → Harder camps → Repeat
```

The core gameplay loop is EQ-style camp grinding: find a spot, form a party, get into a rhythm, grind for hours.

---

## Part 1: Item XP System

### 1.1 Current State (What Exists)

`scripts/resources/WeaponStats.gd` already tracks:
```gdscript
var level: int = 1
var experience: int = 0
var kills_total: int = 0
var damage_total: float = 0.0
var crits_landed: int = 0
```

**Missing:** Code that actually awards XP when enemies die.

### 1.2 XP Formula

```gdscript
# XP required to reach next level
func get_xp_for_next_level() -> int:
    return int(100 * pow(1.08, level))

# Examples:
# Level 1 → 2:    100 XP
# Level 10 → 11:  215 XP
# Level 25 → 26:  685 XP
# Level 50 → 51:  4,690 XP
# Level 100→101:  219,976 XP
```

### 1.3 XP Per Kill

```gdscript
func calculate_item_xp(enemy_level: int, is_elite: bool, party_size: int) -> int:
    # Base XP scales with enemy level
    var base_xp = enemy_level * 5

    # Elite bonus
    if is_elite:
        base_xp = int(base_xp * 1.5)

    # Group bonus: +10% per party member beyond 1
    var group_multiplier = 1.0 + (party_size - 1) * 0.10

    return int(base_xp * group_multiplier)

# Examples (solo):
# Level 1 enemy:   5 XP
# Level 5 enemy:   25 XP
# Level 10 enemy:  50 XP
# Level 10 elite:  75 XP

# With 4-person party (1.3x):
# Level 10 elite:  97 XP
```

### 1.4 Stat Bonuses Per Level

```gdscript
func get_level_bonuses() -> Dictionary:
    var damage_bonus: float
    var crit_bonus: float

    if level <= 50:
        # Linear scaling: +1 damage, +0.2% crit per level
        damage_bonus = level * 1.0
        crit_bonus = level * 0.002
    else:
        # Soft cap: diminishing returns after 50
        damage_bonus = 50.0 + (level - 50) * 0.1
        crit_bonus = 0.10 + (level - 50) * 0.0002

    return {
        "damage_bonus": damage_bonus,
        "crit_bonus": crit_bonus
    }

# Examples:
# Level 10:  +10 damage, +2% crit
# Level 25:  +25 damage, +5% crit
# Level 50:  +50 damage, +10% crit (soft cap starts)
# Level 100: +55 damage, +11% crit
```

### 1.5 Implementation

**File:** `scripts/resources/WeaponStats.gd`

Add these methods:

```gdscript
signal leveled_up(new_level: int)

func gain_experience(amount: int) -> void:
    experience += amount

    # Check for level ups (can be multiple at once)
    while experience >= get_xp_for_next_level():
        experience -= get_xp_for_next_level()
        level += 1
        leveled_up.emit(level)
        print("[WEAPON] Leveled up to %d!" % level)


func get_xp_for_next_level() -> int:
    return int(100 * pow(1.08, level))


func get_damage_bonus() -> float:
    if level <= 50:
        return level * 1.0
    else:
        return 50.0 + (level - 50) * 0.1


func get_crit_bonus() -> float:
    if level <= 50:
        return level * 0.002
    else:
        return 0.10 + (level - 50) * 0.0002


func get_xp_progress() -> float:
    """Returns 0.0 - 1.0 progress to next level"""
    return float(experience) / float(get_xp_for_next_level())
```

**File:** `scripts/player/PlayerCombat.gd`

Hook into enemy death:

```gdscript
func _on_enemy_killed(enemy: Enemy) -> void:
    # Existing kill tracking
    if equipped_weapon and equipped_weapon.stats:
        var stats = equipped_weapon.stats as WeaponStats
        stats.kills_total += 1

        # NEW: Award item XP
        var party_size = GroupManager.get_group_size() if GroupManager.has_group() else 1
        var item_xp = _calculate_item_xp(enemy.level, enemy.is_elite, party_size)
        stats.gain_experience(item_xp)

        # Sync to backend periodically (every 10 kills or on level up)
        if stats.kills_total % 10 == 0:
            _sync_weapon_stats_to_backend()


func _calculate_item_xp(enemy_level: int, is_elite: bool, party_size: int) -> int:
    var base_xp = enemy_level * 5
    if is_elite:
        base_xp = int(base_xp * 1.5)
    var group_multiplier = 1.0 + (party_size - 1) * 0.10
    return int(base_xp * group_multiplier)
```

---

## Part 2: Group XP Sharing

### 2.1 Character XP Split

When in a party, character XP is split but with a group bonus:

```gdscript
# In CharacterStats.gd or XP award function

func award_xp(base_amount: int) -> void:
    var final_xp = base_amount

    if GroupManager.has_group():
        var group_size = GroupManager.get_group_size()

        # Split among party members
        var split_xp = float(base_amount) / float(group_size)

        # Group bonus: encourages grouping
        # 2 players: 1.10x, 3 players: 1.20x, 4 players: 1.25x
        var group_bonus = 1.0 + min(group_size - 1, 4) * 0.05

        final_xp = int(split_xp * group_bonus)

    experience += final_xp
    check_level_up()
```

### 2.2 XP Distribution Table

| Party Size | Split | Bonus | Per-Person | Total Efficiency |
|------------|-------|-------|------------|------------------|
| 1 (solo)   | 100%  | 1.0x  | 100%       | 100%             |
| 2          | 50%   | 1.10x | 55%        | 110%             |
| 3          | 33%   | 1.15x | 38%        | 115%             |
| 4          | 25%   | 1.20x | 30%        | 120%             |
| 5+         | 20%   | 1.25x | 25%        | 125%             |

**Note:** Item XP is NOT split - everyone gets full item XP. Only character XP splits.

---

## Part 3: Camp System

### 3.1 Camp Types

| Camp Type | Respawn Timer | Danger | Target Audience |
|-----------|---------------|--------|-----------------|
| **Chill** | 120 seconds | Low | Solo, AFK-friendly |
| **Standard** | 90 seconds | Medium | Small groups |
| **Intense** | 45 seconds | High | Full parties, active play |

### 3.2 Skeletal Ruins Layout

```
Zone 1 World (24,000 x 8,000 pixels)

[Campfire]----[Ruins West]----[Ruins Center]----[Ruins East]
   Safe         Level 3-5        Level 6-8        Level 9-12
   Zone          Chill           Standard          Intense
```

### 3.3 Camp Spawner Implementation

**New File:** `scripts/systems/CampSpawner.gd`

```gdscript
class_name CampSpawner
extends Node2D

@export var camp_name: String = "Unnamed Camp"
@export var camp_type: String = "standard"  # chill, standard, intense
@export var enemy_level_min: int = 1
@export var enemy_level_max: int = 5
@export var max_enemies: int = 6
@export var elite_chance: float = 0.1

# Respawn timers by camp type
const RESPAWN_TIMERS = {
    "chill": 120.0,
    "standard": 90.0,
    "intense": 45.0
}

var spawn_points: Array[Marker2D] = []
var active_enemies: Dictionary = {}  # spawn_point_index -> enemy
var respawn_timers: Dictionary = {}  # spawn_point_index -> time_remaining

func _ready() -> void:
    # Find all Marker2D children as spawn points
    for child in get_children():
        if child is Marker2D:
            spawn_points.append(child)

    # Initial spawn
    for i in spawn_points.size():
        _spawn_at_point(i)


func _process(delta: float) -> void:
    # Process respawn timers
    for idx in respawn_timers.keys():
        respawn_timers[idx] -= delta
        if respawn_timers[idx] <= 0:
            _spawn_at_point(idx)
            respawn_timers.erase(idx)


func _spawn_at_point(index: int) -> void:
    if index >= spawn_points.size():
        return

    var spawn_pos = spawn_points[index].global_position
    var enemy_level = randi_range(enemy_level_min, enemy_level_max)
    var is_elite = randf() < elite_chance

    var enemy = _create_enemy(enemy_level, is_elite)
    enemy.global_position = spawn_pos
    enemy.died.connect(_on_enemy_died.bind(index))

    active_enemies[index] = enemy
    get_tree().current_scene.add_child(enemy)


func _on_enemy_died(index: int) -> void:
    active_enemies.erase(index)

    # Start respawn timer (placeholder respawn - same spot)
    var timer = RESPAWN_TIMERS.get(camp_type, 90.0)
    respawn_timers[index] = timer


func _create_enemy(level: int, is_elite: bool) -> Enemy:
    var enemy = preload("res://scenes/enemies/Skeleton.tscn").instantiate()
    enemy.level = level
    enemy.is_elite = is_elite
    return enemy
```

### 3.4 Scene Setup

Create camp scenes with spawn point markers:

```
RuinsWestCamp (CampSpawner)
├── SpawnPoint1 (Marker2D) @ (0, 0)
├── SpawnPoint2 (Marker2D) @ (100, 50)
├── SpawnPoint3 (Marker2D) @ (-80, 100)
├── SpawnPoint4 (Marker2D) @ (150, -30)
├── SpawnPoint5 (Marker2D) @ (-50, -80)
└── SpawnPoint6 (Marker2D) @ (200, 100)

Export vars:
  camp_name = "Ruins West"
  camp_type = "chill"
  enemy_level_min = 3
  enemy_level_max = 5
  max_enemies = 6
  elite_chance = 0.05
```

---

## Part 4: Kill-Rate Detection (Optional Enhancement)

Detect when players are grinding efficiently and adjust:

```gdscript
# In CampSpawner.gd

var kills_last_minute: int = 0
var kill_timestamps: Array[float] = []

func _on_enemy_died(index: int) -> void:
    # Track kill rate
    kill_timestamps.append(Time.get_ticks_msec() / 1000.0)
    _cleanup_old_timestamps()

    # If killing faster than respawns, decrease timer
    var kills_per_minute = kill_timestamps.size()
    if kills_per_minute > max_enemies * 0.8:
        # Players are efficient - speed up respawns by 20%
        respawn_timers[index] = RESPAWN_TIMERS[camp_type] * 0.8
    else:
        respawn_timers[index] = RESPAWN_TIMERS[camp_type]


func _cleanup_old_timestamps() -> void:
    var now = Time.get_ticks_msec() / 1000.0
    kill_timestamps = kill_timestamps.filter(func(t): return now - t < 60.0)
```

---

## Part 5: Backend Persistence

### 5.1 Sync Item Stats to Backend

**Endpoint:** `POST /api/items/{item_id}/stats`

```json
{
    "level": 25,
    "experience": 450,
    "kills_total": 1523,
    "damage_total": 245000.0,
    "crits_landed": 312
}
```

### 5.2 Sync Triggers

- Every 10 kills
- On level up
- On logout/disconnect
- Every 5 minutes (background sync)

---

## Part 6: UI Integration

### 6.1 Item XP Bar

Add to equipped weapon display:

```gdscript
# In HUD or inventory UI
func _update_weapon_xp_display() -> void:
    if not equipped_weapon:
        return

    var stats = equipped_weapon.stats
    xp_bar.value = stats.get_xp_progress() * 100
    level_label.text = "Lv.%d" % stats.level
    xp_label.text = "%d / %d" % [stats.experience, stats.get_xp_for_next_level()]
```

### 6.2 Level Up Notification

```gdscript
# Connect to WeaponStats.leveled_up signal
func _on_weapon_leveled_up(new_level: int) -> void:
    # Flash effect on weapon
    # Show floating text: "+1 Level!"
    # Play sound effect
    NotificationManager.show("Weapon reached Level %d!" % new_level, "legendary")
```

---

## Part 7: Progression Targets

### 7.1 Time to Level (Solo, Level 5 Camp)

| Item Level | Total XP Needed | Kills Needed | Time (1 kill/10s) |
|------------|-----------------|--------------|-------------------|
| 10         | 1,449 XP        | ~58 kills    | ~10 minutes       |
| 25         | 7,861 XP        | ~315 kills   | ~52 minutes       |
| 50         | 57,902 XP       | ~2,316 kills | ~6.4 hours        |
| 100        | 2,740,262 XP    | ~109,610     | ~304 hours        |

### 7.2 Target Session Rewards

| Session Length | Expected Item Levels | Notes |
|----------------|---------------------|-------|
| 30 minutes     | +5-8 levels         | Quick session |
| 1 hour         | +12-15 levels       | Standard grind |
| 2 hours        | +20-25 levels       | Dedicated session |
| 4+ hours       | +35-40 levels       | Long grind |

---

## Checklist

### Phase 1: Item XP (Priority)
- [ ] Add `gain_experience()` to WeaponStats.gd
- [ ] Add `get_damage_bonus()` and `get_crit_bonus()`
- [ ] Hook enemy death → item XP in PlayerCombat.gd
- [ ] Add `leveled_up` signal
- [ ] Apply damage/crit bonuses in combat calculations

### Phase 2: Group XP
- [ ] Modify character XP to split among party
- [ ] Add group bonus multiplier
- [ ] Ensure item XP is NOT split (full to everyone)

### Phase 3: Camp System
- [ ] Create CampSpawner.gd
- [ ] Set up 3 Ruins camps (West/Center/East)
- [ ] Configure spawn points as Marker2D children
- [ ] Connect enemy death → respawn timer

### Phase 4: UI
- [ ] Add XP bar to weapon display
- [ ] Level up notification/effects
- [ ] Show item level in inventory

### Phase 5: Backend
- [ ] Create item stats sync endpoint
- [ ] Periodic background sync
- [ ] Persist on logout

---

## Summary

**Core Loop:**
1. Kill enemy → Item gains XP
2. Item levels up → Stronger stats
3. Tackle harder camps → More XP
4. Max character level? Still grinding items.
5. Show off high-level items in PvP/duels

**Key Numbers:**
- Base XP: `enemy_level * 5`
- XP to level: `100 * 1.08^level`
- Damage per level: +1 (soft cap at 50)
- Crit per level: +0.2% (soft cap at 50)

This creates the "forever grind" that EQ players love.
