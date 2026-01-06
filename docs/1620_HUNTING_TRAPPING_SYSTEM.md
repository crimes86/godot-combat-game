# 1620 Hunting & Trapping System Design

## Historical Context: St. Louis to Three Forks Fur Trade Route

The Missouri River fur trade (1807-1840) was the backbone of the American frontier economy. Trappers ("mountain men") would travel from St. Louis upriver to the Rocky Mountain headwaters, spending months or years trapping beaver and other fur-bearers.

### Historically Accurate Animals by Zone

**Zone 1 (Cave/Forest - "St. Louis Frontier")**
Limited wildlife - introduction to hunting mechanics:

| Animal | Rarity | Behavior | Value |
|--------|--------|----------|-------|
| **Rabbit/Cottontail** | Common | Skittish, runs from player | Low |
| **Squirrel** | Common | Tree-dwelling, scatters | Very Low |
| **Whitetail Deer** | Uncommon | Alert, flees in groups | Medium |
| **Raccoon** | Uncommon | Nocturnal, near water | Low-Medium |
| **Red Fox** | Rare | Solitary, cunning | Medium |
| **Coyote** | Rare | Opportunistic, may attack | Medium |

**Zone 2 (Trading Hub Forest - "Lower Missouri")**
Full trapping grounds - primary gameplay:

| Animal | Rarity | Behavior | Value |
|--------|--------|----------|-------|
| **Beaver** | Common | Semi-aquatic, dam builders | **HIGH** |
| **Muskrat** | Common | Aquatic, near beaver lodges | Low |
| **River Otter** | Uncommon | Playful, fast swimmer | High |
| **Mink** | Uncommon | Small, aggressive | Medium-High |
| **Rabbit/Hare** | Common | Forest floor | Low |
| **Red Fox** | Uncommon | Forest edges | Medium |
| **Gray Fox** | Rare | Climbs trees | Medium |
| **Raccoon** | Common | Nocturnal, clever | Low-Medium |
| **Whitetail Deer** | Common | Herds in clearings | Medium |
| **Elk** | Uncommon | Large herds | High |
| **Black Bear** | Rare | Dangerous, solitary | High |
| **Gray Wolf** | Rare | Pack hunter, **DANGEROUS** | High |
| **Bobcat** | Very Rare | Ambush predator | Very High |

**Future Zone 3+ (Upper Missouri / Three Forks)**
End-game content:

| Animal | Rarity | Behavior | Value |
|--------|--------|----------|-------|
| **Beaver (Prime)** | Common | Thicker winter coat | Very High |
| **Pine Marten** | Uncommon | Tree-dwelling | Very High |
| **Fisher** | Rare | Large mustelid | Very High |
| **Wolverine** | Very Rare | Extremely aggressive | Extremely High |
| **Ermine/Stoat** | Uncommon | Winter-white coat | High |
| **Grizzly Bear** | Rare | **VERY DANGEROUS** | Trophy |
| **Mountain Lion** | Rare | Stalks players | Very High |
| **Bison** | Common (herds) | Massive, stampede | High (multiple resources) |
| **Pronghorn** | Common | Fastest land animal | Medium |

---

## Wildlife System Architecture

### Animal Types

```gdscript
enum AnimalType {
    # Small Game (trappable + huntable)
    RABBIT,
    SQUIRREL,
    MUSKRAT,
    RACCOON,

    # Fur-Bearers (primarily trappable)
    BEAVER,
    MINK,
    OTTER,
    FOX_RED,
    FOX_GRAY,
    MARTEN,
    FISHER,
    ERMINE,
    BOBCAT,

    # Medium Game (huntable)
    DEER,
    ELK,
    PRONGHORN,

    # Large/Dangerous (huntable only, challenging)
    BLACK_BEAR,
    GRIZZLY_BEAR,
    WOLF,
    MOUNTAIN_LION,
    WOLVERINE,

    # Herd Animals (special mechanics)
    BISON
}

enum AnimalBehavior {
    SKITTISH,      # Flees immediately when player detected
    ALERT,         # Watches player, flees if approached
    CURIOUS,       # May approach briefly before fleeing
    TERRITORIAL,   # Warns before attacking
    AGGRESSIVE,    # Attacks on sight
    PACK,          # Coordinates with others
    NOCTURNAL,     # Only active at night
    AQUATIC        # Stays near/in water
}
```

### Roaming Wildlife (Visible Animals)

Animals spawn in the world and roam with simple AI:

```gdscript
class_name WildlifeAI extends CharacterBody2D

@export var animal_type: AnimalType
@export var behavior: AnimalBehavior
@export var detection_range: float = 300.0
@export var flee_range: float = 500.0
@export var roam_radius: float = 400.0
@export var speed: float = 100.0

var home_position: Vector2
var current_state: State = State.IDLE
var player_detected: bool = false

enum State {
    IDLE,
    ROAMING,
    GRAZING,
    ALERT,
    FLEEING,
    ATTACKING,
    TRAPPED,
    DEAD
}

func _physics_process(delta: float) -> void:
    match current_state:
        State.IDLE:
            # Idle animation, occasional look around
            if randf() < 0.01:  # 1% chance per frame to start roaming
                pick_roam_destination()
                current_state = State.ROAMING

        State.ROAMING:
            move_toward_destination(delta)
            if reached_destination():
                current_state = State.IDLE

        State.ALERT:
            face_player()
            # If player gets closer, flee
            # If player backs off, return to IDLE

        State.FLEEING:
            flee_from_player(delta)
            if distance_to_player() > flee_range:
                current_state = State.ROAMING
```

### Wildlife Spawning

```gdscript
class_name WildlifeSpawner extends Node2D

@export var spawn_table: Array[WildlifeSpawnEntry]
@export var max_active: int = 20  # Per zone
@export var spawn_radius: float = 2000.0
@export var player_proximity_required: float = 3000.0

var active_animals: Array[WildlifeAI] = []

func _process(delta: float) -> void:
    cleanup_despawned()

    if active_animals.size() < max_active:
        try_spawn_animal()

func try_spawn_animal() -> void:
    # Only spawn if player is in zone
    var player = get_nearest_player()
    if not player or player.global_position.distance_to(global_position) > player_proximity_required:
        return

    # Pick random spawn point away from player
    var spawn_pos = get_spawn_position_away_from_player(player)

    # Roll for animal type based on spawn table weights
    var entry = roll_spawn_table()
    if entry:
        spawn_animal(entry.animal_type, spawn_pos)
```

---

## Trap System (Time-Based)

### Core Concept

Traps operate on **real time** (with optional game-time multiplier). Player sets traps, and over time there's a chance for each trap to trigger based on multiple factors.

### Trap Check Interval

Every **5 minutes real time** (configurable), each placed trap rolls for a catch:

```gdscript
const TRAP_CHECK_INTERVAL: float = 300.0  # 5 minutes in seconds
const GAME_TIME_MULTIPLIER: float = 12.0  # 1 real hour = 12 game hours

var time_since_last_check: float = 0.0

func _process(delta: float) -> void:
    if not is_server():
        return

    time_since_last_check += delta
    if time_since_last_check >= TRAP_CHECK_INTERVAL:
        time_since_last_check = 0.0
        process_all_traps()

func process_all_traps() -> void:
    for trap in active_traps:
        if trap.state == TrapState.SET:
            roll_trap_catch(trap)
```

### Catch Probability Formula

```gdscript
func calculate_catch_chance(trap: Trap) -> float:
    var base_chance: float = trap.base_catch_rate  # 0.0 - 1.0

    # Modifiers (multiplicative)
    var location_mod: float = get_location_modifier(trap)
    var bait_mod: float = get_bait_modifier(trap)
    var population_mod: float = get_population_modifier(trap)
    var trap_quality_mod: float = get_quality_modifier(trap)
    var time_of_day_mod: float = get_time_modifier(trap)
    var weather_mod: float = get_weather_modifier(trap)
    var scent_mod: float = get_scent_modifier(trap)
    var competition_mod: float = get_competition_modifier(trap)

    var final_chance = base_chance * location_mod * bait_mod * population_mod * \
                       trap_quality_mod * time_of_day_mod * weather_mod * \
                       scent_mod * competition_mod

    return clamp(final_chance, 0.01, 0.95)  # Always 1-95% chance
```

### Modifier Breakdown

#### 1. Location Modifier (1.0 - 2.5x)
Where you place the trap matters:

| Placement | Modifier | Target Animals |
|-----------|----------|----------------|
| Beaver dam | 2.5x | Beaver, Muskrat |
| Riverbank | 2.0x | Otter, Mink, Beaver |
| Game trail | 1.8x | Deer, Elk, Fox |
| Forest clearing | 1.5x | Rabbit, Deer |
| Dense forest | 1.2x | Squirrel, Marten |
| Random placement | 1.0x | Any |
| Near campfire/structures | 0.5x | Animals avoid |

```gdscript
func get_location_modifier(trap: Trap) -> float:
    var trap_spot = trap.placement_spot
    if trap_spot:
        return trap_spot.location_bonus

    # Check environment manually
    if is_near_beaver_dam(trap.global_position):
        return 2.5
    elif is_near_river(trap.global_position):
        return 2.0
    elif is_on_game_trail(trap.global_position):
        return 1.8
    # etc.
    return 1.0
```

#### 2. Bait Modifier (1.0 - 3.0x)
Using the right bait dramatically increases success:

| Bait | Best For | Modifier | Duration |
|------|----------|----------|----------|
| None | - | 1.0x | - |
| Castoreum (beaver gland) | Beaver | 3.0x | 24h game |
| Fish scraps | Otter, Mink, Raccoon | 2.0x | 12h game |
| Raw meat | Fox, Wolf, Bear | 2.5x | 6h game (attracts predators!) |
| Berries | Rabbit, Deer | 1.5x | 24h game |
| Acorns/Seeds | Squirrel | 2.0x | 48h game |
| Musk lure (craftable) | Fox, Mink | 2.5x | 12h game |

```gdscript
func get_bait_modifier(trap: Trap) -> float:
    if not trap.bait_item:
        return 1.0

    var bait_effectiveness = BAIT_TABLE.get(trap.bait_item.id, {})
    var target_animal = trap.target_animal_type

    if target_animal in bait_effectiveness.get("best_for", []):
        return bait_effectiveness.get("modifier", 1.0)
    elif target_animal in bait_effectiveness.get("good_for", []):
        return bait_effectiveness.get("modifier", 1.0) * 0.5
    else:
        return 1.0
```

#### 3. Animal Population Modifier (0.2 - 2.0x)
Dynamic population based on zone state:

```gdscript
class_name AnimalPopulation

# Per-zone population tracking
var zone_populations: Dictionary = {
    "zone1_forest": {
        "beaver": 1.0,  # Normal
        "rabbit": 1.0,
        "deer": 1.0,
    },
    "zone2_forest": {
        "beaver": 1.5,  # Abundant
        "rabbit": 1.2,
        "deer": 0.8,   # Slightly depleted
    }
}

# Population recovery over time
const POPULATION_RECOVERY_RATE: float = 0.01  # Per hour
const MIN_POPULATION: float = 0.2
const MAX_POPULATION: float = 2.0

func animal_caught(zone: String, animal_type: String) -> void:
    var current = zone_populations[zone].get(animal_type, 1.0)
    zone_populations[zone][animal_type] = max(MIN_POPULATION, current - 0.1)

func _on_hour_passed() -> void:
    for zone in zone_populations:
        for animal in zone_populations[zone]:
            var current = zone_populations[zone][animal]
            if current < 1.0:
                zone_populations[zone][animal] = min(MAX_POPULATION, current + POPULATION_RECOVERY_RATE)
```

#### 4. Trap Quality Modifier (0.5 - 1.5x)

| Quality | Modifier | Notes |
|---------|----------|-------|
| Damaged | 0.5x | Needs repair |
| Worn | 0.75x | After 10+ catches |
| Normal | 1.0x | New trap |
| Well-Maintained | 1.2x | Oiled, repaired |
| Mastercraft | 1.5x | Crafted with high skill |

#### 5. Time of Day Modifier (0.5 - 2.0x)

| Time | Diurnal (Deer) | Nocturnal (Raccoon) | Crepuscular (Rabbit) |
|------|----------------|---------------------|----------------------|
| Dawn | 1.5x | 1.5x | 2.0x |
| Day | 1.5x | 0.5x | 0.8x |
| Dusk | 1.5x | 1.5x | 2.0x |
| Night | 0.5x | 2.0x | 0.5x |

#### 6. Weather Modifier (0.3 - 1.5x)

| Weather | Modifier | Reason |
|---------|----------|--------|
| Clear | 1.0x | Normal |
| Overcast | 1.2x | Animals more active |
| Light rain | 1.5x | Covers scent |
| Heavy rain | 0.5x | Animals shelter |
| Snow | 1.3x | Hungry animals forage |
| Storm | 0.3x | Everyone hides |

#### 7. Player Scent Modifier (0.5 - 1.0x)
Handling traps repeatedly leaves scent:

```gdscript
var trap_handle_count: int = 0
const SCENT_DECAY_TIME: float = 3600.0  # 1 hour for scent to fade

func get_scent_modifier(trap: Trap) -> float:
    # Each time player checks/resets trap, scent increases
    # Scent decays over time
    var scent_level = calculate_current_scent(trap)
    return clamp(1.0 - (scent_level * 0.1), 0.5, 1.0)
```

#### 8. Competition Modifier (0.3 - 1.0x)
Other traps nearby reduce effectiveness:

```gdscript
func get_competition_modifier(trap: Trap) -> float:
    var nearby_traps = get_traps_in_radius(trap.global_position, 500.0)
    var other_traps = nearby_traps.filter(func(t): return t != trap)

    match other_traps.size():
        0: return 1.0
        1: return 0.8
        2: return 0.6
        _: return 0.3
```

---

## Trap Types (Expanded)

| Trap | Size | Target Size | Base Rate | Materials | Special |
|------|------|-------------|-----------|-----------|---------|
| **Snare** | Small | Rabbit, Squirrel | 35% | 1 rope, 2 sticks | Cheap, low durability |
| **Spring Snare** | Small-Med | Rabbit, Fox | 40% | 2 rope, 3 sticks, 1 spring | Higher catch, reusable |
| **Leg-Hold (Small)** | Small-Med | Mink, Fox, Raccoon | 30% | 2 iron, 1 rope | Durable, reusable |
| **Leg-Hold (Large)** | Medium | Beaver, Otter, Bobcat | 35% | 4 iron, 2 rope | Heavy, high value targets |
| **Conibear/Body-Grip** | Small-Med | Beaver, Mink | 45% | 3 iron, 1 rope | Quick kill, best pelts |
| **Deadfall** | Any | Varies by size | 25% | 4 logs, 2 rope | Primitive, can catch large |
| **Pit Trap** | Large | Deer, Elk, Bear | 20% | Dig + 10 sticks | Dangerous prey, rare |
| **Steel Trap (Master)** | Large | Wolf, Bear, Cat | 25% | 6 iron, 2 rope | End-game, predators |

---

## "Trap Snap" Notification System

When a player's trap triggers while they're online:

### Audio Cue
```gdscript
func _on_trap_triggered(trap: Trap) -> void:
    # Play distinctive sound to player
    var player = get_player_by_id(trap.owner_id)
    if player and player.is_online():
        # 3D positioned audio from trap direction
        SoundManager.play_3d("trap_snap", trap.global_position, player)

        # Also play UI notification sound
        player.play_ui_sound("trap_notification")

        # Show map ping
        player.minimap.add_ping(trap.global_position, "trap_triggered", 30.0)
```

### Visual Cue
- Minimap ping at trap location
- Optional: Toast notification "One of your traps triggered!"
- Trap icon in world shows sparkle/glow when triggered

### Sound Design
- Distant "SNAP" metallic sound
- Volume based on distance to trap
- Directional (stereo pan toward trap)
- Maybe followed by brief animal sound (squeal, splash)

---

## Hunting System (Direct Combat)

For visible roaming animals, players can hunt directly:

### Weapon Effectiveness

| Weapon Type | Small Game | Medium Game | Large Game | Pelt Damage |
|-------------|------------|-------------|------------|-------------|
| Bow | Excellent | Good | Fair | Minimal |
| Rifle/Gun | Good | Excellent | Excellent | High |
| Spear | Poor | Good | Good | Medium |
| Knife | Poor | Poor | Very Poor | Minimal (finishing) |
| Trap | N/A | N/A | N/A | None |

### Pelt Quality from Hunting

Where you hit matters:

| Hit Location | Pelt Quality | Damage |
|--------------|--------------|--------|
| Head | Pristine (100%) | Instant kill |
| Heart/Vitals | Good (80%) | Quick kill |
| Body | Fair (50%) | Slow kill |
| Legs | Poor (30%) | May escape |
| Multiple hits | Ruined (0%) | Dead |

```gdscript
func calculate_pelt_quality(animal: WildlifeAI, hit_count: int, hit_locations: Array) -> float:
    if hit_count > 3:
        return 0.0  # Ruined

    var best_hit = get_best_hit_location(hit_locations)
    match best_hit:
        "head": return 1.0
        "vitals": return 0.8
        "body": return 0.5
        "legs": return 0.3
        _: return 0.2
```

### Hunting Skill Progression

Experience gained from successful hunts:

```gdscript
var hunting_skill: int = 0  # 0-100

# Skill bonuses
func get_detection_range_reduction() -> float:
    return hunting_skill * 0.5  # Up to 50% closer before detected

func get_critical_hit_chance() -> float:
    return 0.05 + (hunting_skill * 0.002)  # 5% to 25%

func get_tracking_ability() -> bool:
    return hunting_skill >= 25  # Can see animal trails

func get_field_dressing() -> bool:
    return hunting_skill >= 50  # Can skin in field, not just at station
```

---

## Integration: Zone 1 vs Zone 2

### Zone 1 (Introduction)
- **5-10 animals visible** at any time
- Mostly rabbits, squirrels, occasional deer
- No trapping (tutorial teaches hunting basics)
- Animals are practice targets
- Low danger (no wolves/bears)

### Zone 2 (Full System)
- **15-25 animals visible** at any time
- Full variety including beaver, fox, predators
- **Trap spots** clearly marked
- Skinning station at Trapper Camp
- Vendor buys pelts
- Wolves patrol forest edge (danger)

---

## Economy Balance (Pelts)

| Pelt | Poor | Good | Pristine | Notes |
|------|------|------|----------|-------|
| Rabbit | 5 | 8 | 12 | Common, low effort |
| Squirrel | 2 | 4 | 6 | Very common |
| Raccoon | 10 | 16 | 24 | Night hunting |
| Muskrat | 8 | 12 | 18 | Near beaver |
| Fox | 25 | 40 | 60 | Cunning prey |
| Mink | 30 | 48 | 72 | Small but valuable |
| Beaver | 50 | 80 | 120 | **THE money maker** |
| Otter | 45 | 72 | 108 | Playful, fast |
| Bobcat | 80 | 128 | 192 | Rare, dangerous |
| Wolf | 60 | 96 | 144 | Pack danger |
| Black Bear | 100 | 160 | 240 | High risk |
| Deer (hide) | 20 | 32 | 48 | Common, meat too |
| Elk (hide) | 40 | 64 | 96 | Large, meat too |

**Reference**: A full trapping run (8 traps, 2 hours real time) should yield:
- Average: 200-400 gold worth of pelts
- Lucky: 500-800 gold
- Poor: 50-150 gold (bad placement/luck)

---

## Data Structures

### Trap Item

```json
{
  "id": "leg_hold_trap_large",
  "name": "Large Leg-Hold Trap",
  "type": "trap",
  "trap_data": {
    "size": "large",
    "base_catch_rate": 0.35,
    "target_animals": ["beaver", "otter", "bobcat", "wolf"],
    "durability_max": 20,
    "bait_slot": true,
    "set_time": 3.0
  },
  "crafting": {
    "materials": [
      {"item": "iron_ingot", "count": 4},
      {"item": "rope", "count": 2}
    ],
    "station": "crafting_station",
    "skill_required": 10
  }
}
```

### Placed Trap (World Object)

```json
{
  "trap_id": "uuid-1234",
  "item_id": "leg_hold_trap_large",
  "owner_id": "player-5678",
  "position": {"x": -2500, "y": -8000},
  "state": "SET",
  "placed_at": 1704067200,
  "bait": {"item": "castoreum", "expires_at": 1704153600},
  "durability": 18,
  "catch": null,
  "last_checked": 1704070800,
  "times_handled": 3
}
```

### Animal Spawn Entry

```json
{
  "animal_type": "beaver",
  "spawn_weight": 100,
  "zone_requirements": ["zone2_river", "zone2_forest_stream"],
  "behavior": "AQUATIC",
  "activity_pattern": "CREPUSCULAR",
  "pack_size": [1, 3],
  "flee_speed": 80,
  "detection_range": 400,
  "danger_level": 0,
  "pelt_value_base": 50,
  "meat_yield": 2
}
```

---

## Implementation Priority

### Phase 1: Core Wildlife
1. Create `WildlifeAI.gd` base class
2. Implement roaming/fleeing behavior
3. Add spawner system for Zone 2 forest
4. Create sprites for: Rabbit, Deer, Fox (start simple)

### Phase 2: Basic Hunting
1. Animals take damage and die
2. Drop carcass on death
3. Pelt quality based on hit count
4. Integrate with existing combat system

### Phase 3: Trap Placement
1. Create `Trap.gd` scene
2. Add trap spots to Zone 2
3. Implement set/check/collect interactions
4. Basic catch roll (location only)

### Phase 4: Full Trap System
1. Add all modifiers (bait, population, time, etc.)
2. Implement "trap snap" notification
3. Add trap UI (show placed traps on map)
4. Durability and repair

### Phase 5: Polish
1. All animal sprites and animations
2. Hunting skill progression
3. Full economy balance
4. Tutorial quests for hunting/trapping

---

*Document created: January 2026*
*Expands on 1620_INTEGRATION_SPEC.md trapping section*
