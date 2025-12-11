# Future Feature Specifications

Design specifications for features not yet implemented. These documents capture detailed design thinking for future development.

---

# Vision & World Design

## Vision Statement

A sandbox survival game with emergent player-driven communities. Players establish personal or guild bases in dynamically managed chunks, progress through vendor quest lines, and migrate north to harder biomes. Bases become siegeable under specific conditions, creating meaningful PvP stakes.

**Core Loop:** Explore -> Pillage -> Return Home -> Unload -> Rest -> Repeat

## Design Pillars

1. **Dynamic Horizontal World** - Chunks spawn/despawn based on population, infinite expansion
2. **Loose Vertical Progression** - Graceful zone transitions, skill > gear, catch-up mechanics
3. **Player-Driven Economy** - Vendor quests, base building, player-placed stations
4. **Meaningful PvP Stakes** - Siegeable bases, World Trees, opt-in conflict

## Biome Layout (North = Harder)

```
NORTH (Harder)
    ^
+-----------------------------------------------------+
|  TIER 4: VOID WASTES (Level 60+)                    |
|  - Corrupted terrain, environmental damage          |
|  - Raid-level world bosses                          |
|  - Legendary material nodes                         |
|  - Guild-only bases viable                          |
+----------------------------------------------------|
|  TIER 3: SHADOW REALM (Level 30-60)                 |
|  - Dark forest, haunted ruins                       |
|  - Elite skeleton variants, mini-bosses             |
|  - Rare crafting materials                          |
|  - Contested PvP zones                              |
+-----------------------------------------------------+
|  TIER 2: CURSED LANDS (Level 15-30)                 |
|  - Dead forest, corrupted ground                    |
|  - Armored skeletons, roaming packs                 |
|  - Uncommon materials                               |
|  - Base building unlocked                           |
+-----------------------------------------------------+
|  TIER 1: THE WASTELAND (Level 1-15)                 |
|  - Current game area (Campfire -> Castle)           |
|  - Basic skeletons, tutorial experience             |
|  - Common materials                                 |
|  - Safe zone: Campfire area                         |
+-----------------------------------------------------+
    v
SOUTH (Spawn/Safe)
```

---

# Vendor Progression System

**Status: NOT YET IMPLEMENTED**

NPCs start at the Campfire and "migrate" with players as they progress. Each vendor has a quest line that unlocks new tiers.

## Vendor Types

### Blacksmith (Combat Equipment)
**Current:** Sells weapons at Campfire
**Quest Line:**
1. **Apprentice** - Deliver 10 Iron Ore -> Unlocks weapon repairs
2. **Journeyman** - Defeat 50 Skeletons with his weapons -> Unlocks armor crafting
3. **Master** - Bring Ancient Forge Blueprints (dungeon drop) -> Unlocks legendary crafting
4. **Portable Forge** - Reach Level 20, Gold investment -> Place in your base

### Alchemist (Consumables) - NEW
1. **Herbalist** - Gather 20 Bone Ember -> Sells basic potions
2. **Chemist** - Defeat Poison Skeleton Boss -> Unlocks buff potions
3. **Alchemist** - Brew 50 potions -> Unlocks transmutation
4. **Alchemy Station** - Place in base for autonomous production

### Jeweler (Accessories) - NEW
1. **Trinket Maker** - Deliver 10 Dusty Gems -> Sells basic rings/amulets
2. **Gem Cutter** - Find Rare Gem (Zone 3) -> Unlocks stat gems
3. **Master Jeweler** - Craft 10 enchanted items -> Unlocks socketing
4. **Jewelry Workbench** - Place in base

### Gambler (Risk/Reward) - NEW
1. **Street Dealer** - Win 5 gambles -> Appears at Campfire
2. **High Roller** - Lose 500 gold total -> Unlocks rare item pool
3. **House Master** - Win jackpot once -> Unlocks daily jackpot
4. **Gambling Den** - Place in base (attracts visitors)

### Artificer (Base Building) - NEW
1. **Handyman** - Repair 10 structures -> Sells building materials
2. **Architect** - Build your first base -> Unlocks advanced structures
3. **Siege Engineer** - Successfully defend a siege -> Unlocks defenses
4. **Mobile Workshop** - Always available at your base

---

# Settlement System

**Status: REPLACED BY WORLD TREE SYSTEM**

> **See:** [WORLD_TREE_SYSTEM.md](./WORLD_TREE_SYSTEM.md) for the full specification.

The original Settlement System has been replaced by the World Tree System, which is inspired by Shadowbane's Tree of Life mechanics. The World Tree system provides:

- **Rank 1-7 progression** with gold costs and upgrade times
- **Runekeeper protection** for buildings (invulnerable outside sieges)
- **Building placement** (warehouse, vendors, shrines, storage)
- **Resource mines** with vulnerability windows
- **Bane siege system** with 3-day countdowns and 2-hour windows
- **World map visibility** showing tree rank and guild name

Key differences from the original Settlement concept:
- Single tree replaces complex multi-building settlement
- Protection slots instead of physical walls
- Mines for passive income instead of manual gathering only
- Corruption bane replaces traditional siege mechanics

## World Structure & POI System

### Chunk Layout

```
CHUNK -1 (Edge)        CHUNK 0 (Center)       CHUNK +1 (Edge)
+------+------+       +-------------+        +------+------+
| POI  | POI  |       |             |        | POI  | POI  |
|  NW  |  NE  |       |  CAMPFIRE   |        |  NW  |  NE  |
+------+------+       |  BLACKSMITH |        +------+------+
| POI  | POI  |       |  (Safe Zone)|        | POI  | POI  |
|  SW  |  SE  |       |             |        |  SW  |  SE  |
+------+------+       +-------------+        +------+------+
   4 POI slots            Safe Zone            4 POI slots
```

### Chunk Roles

| Chunk | Role | POI Slots | Features |
|-------|------|-----------|----------|
| -1 (West Edge) | Exploration | 4 quadrants | Seed Plot, Ruins, Mines, Dangers |
| 0 (Center) | Starter/Safe | 0 | Campfire, Blacksmith, Tutorial |
| +1 (East Edge) | Exploration | 4 quadrants | Seed Plot, Ruins, Mines, Dangers |

### POI Generation

```gdscript
const GUARANTEED_POIS = ["seed_plot", "ruins"]  # 1 of each per edge chunk

const RANDOM_POI_POOL = [
    {"type": "gold_mine", "weight": 25},          # Claimable resource mine
    {"type": "monster_lava_lake", "weight": 25},  # Giant lava + elite spawns
    {"type": "resource_node", "weight": 20},      # Dense trees/rocks/ore
    {"type": "monster_den", "weight": 15},        # Elite enemy camp
    {"type": "ancient_shrine", "weight": 15},     # Buff altar / lore
]
```

## World Tree System Summary

### Fixed Layout Grid

```
SETTLEMENT PLOT (~500x500 units)
+---------------------------------------------+
|                                             |
|  [WALL_NW]              [WALL_NE]           |  <- Tier 4: Palisade slots
|       [TOWER_N]                             |  <- Tier 5: Watchtower slot
|                                             |
|  [STATION_NW]     [STATION_NE]              |  <- Tier 2-3: Crafting/utility
|                                             |
|           * CENTRAL FIRE *                  |  <- Core: Always present
|           (Control Point)                   |
|                                             |
|  [STATION_SW]     [STATION_SE]              |  <- Tier 2-3: Crafting/utility
|                                             |
|       [TOWER_S]                             |  <- Tier 5: Watchtower slot
|  [WALL_SW]    [GATE]    [WALL_SE]           |  <- Tier 4: Walls + Gate
|                                             |
+---------------------------------------------+
```

### Slot Types

| Slot Category | Count | Purpose |
|---------------|-------|---------|
| Central Fire | 1 | Control point, respawn, guild binding |
| Station Slots | 4 | Crafting, storage, services |
| Wall Slots | 4 | Defensive perimeter |
| Tower Slots | 2 | Vision, NPC defenders |
| Gate Slot | 1 | Entry/exit chokepoint |

## Building Types (Colonial FOB Theme)

### Tier 1 - Starter (Friendly Rep)
| Building | Slot Type | Function |
|----------|-----------|----------|
| Supply Tent | Station | Shared guild storage (50 slots) |
| Bedroll Camp | Station | Basic rest (slow HP regen) |

### Tier 2 - Established (Honored Rep)
| Building | Slot Type | Function |
|----------|-----------|----------|
| Armory Tent | Station | Gear repair, weapon racks |
| Crafting Station | Station | Convert raw mats -> items |
| Storage Expansion | Station | +100 storage slots |

### Tier 3 - Fortified (Revered Rep)
| Building | Slot Type | Function |
|----------|-----------|----------|
| Galley | Station | Cook food, buff meals |
| Barracks | Station | Bind respawn, recruit NPCs |
| Command Tent | Station | Guild management, war table |

### Tier 4 - Defended (Exalted Rep)
| Building | Slot Type | Function |
|----------|-----------|----------|
| Palisade Wall | Wall | 500 HP barrier |
| Reinforced Gate | Gate | 750 HP, controls entry |
| Spike Barrier | Wall | 300 HP, damages attackers |

### Tier 5 - Military (Max Rep + Resources)
| Building | Slot Type | Function |
|----------|-----------|----------|
| Watchtower | Tower | Extended vision, archer NPC |
| Ballista Platform | Tower | Siege weapon (player operated) |
| Stone Wall Upgrade | Wall | 1000 HP (replaces palisade) |

## Progression System

### Blacksmith Reputation Tiers

| Rep Level | Points | Settlement Unlocks |
|-----------|--------|-------------------|
| Neutral | 0 | Campfire access only |
| Friendly | 1000 | Claim plot, Supply Tent, Bedroll |
| Honored | 3000 | Armory, Crafting Station, Storage |
| Revered | 6000 | Galley, Barracks, Command Tent |
| Exalted | 10000 | Walls, Gates, Defenses |
| Legend | 15000 | Towers, Siege Weapons, Stone Walls |

### Building Costs (Example)

| Building | Wood | Stone | Metal | Gold |
|----------|------|-------|-------|------|
| Supply Tent | 50 | 0 | 10 | 100 |
| Armory Tent | 80 | 20 | 40 | 250 |
| Crafting Station | 60 | 40 | 30 | 200 |
| Galley | 100 | 30 | 20 | 300 |
| Barracks | 120 | 50 | 40 | 500 |
| Palisade Wall | 80 | 0 | 20 | 150 |
| Watchtower | 150 | 100 | 60 | 750 |

## Claiming & Ownership

### Claim Process
1. Player reaches Friendly rep with blacksmith
2. Player discovers unclaimed settlement plot
3. Interact with plot center -> "Claim for Guild" prompt
4. Pay claim fee (500 gold + 100 wood)
5. Central Fire spawns, plot is now owned

### Ownership Rules
- One settlement per guild
- Guild leader + officers can manage buildings
- Members can deposit/withdraw from storage
- Claim transfers if guild disbands (to highest rep member)

### Abandonment
- Settlement decays if no guild member logs in for 7 days
- Buildings lose 10% HP per day of inactivity
- After 14 days, settlement becomes unclaimed
- 50% of stored resources remain for new claimers

## Siege System

### Vulnerability Windows

Settlements can only be attacked during scheduled windows:

```gdscript
const SIEGE_WINDOW_DURATION: float = 2.0  # 2 hours
const SIEGE_WINDOWS_PER_WEEK: int = 3  # Mon/Wed/Sat
```

### Siege Mechanics

**Initiating Siege:**
1. Attacking guild places "Siege Banner" outside settlement
2. 30-minute warning period (defenders notified)
3. Siege begins, buildings become attackable

**Victory Conditions:**
- **Attackers Win:** Destroy Central Fire (capture settlement)
- **Defenders Win:** Destroy Siege Banner OR survive window
- **Stalemate:** Partial building damage, no ownership change

### Loot on Capture
- Attackers receive 25% of storage contents
- 50% remains for new owners
- 25% is destroyed/lost

## Implementation Phases

1. **Foundation** - Plot generation, discovery, claim system, central fire
2. **Building** - Slot system, tier 1-2 buildings, construction UI
3. **Storage** - Guild inventory, deposit/withdraw, upgrades
4. **Progression** - Rep tracking, rep-gated unlocks, tier 3-4 buildings
5. **Defense** - Building HP, walls, gates, watchtowers
6. **Siege** - Windows, initiation, combat, capture/loot system

---

# Class System

**Status: NOT YET IMPLEMENTED**

Emergent progression system where players develop their identity through gameplay rather than upfront selection.

## The Four Layers

```
+-------------------------------------------------------------+
|  LAYER 4: EMERGENT CLASS                                    |
|  Determined by: Weapon Skill + Discipline + Runes           |
|  Result: "Blademaster", "Assassin", "High Priest", etc.     |
+-------------------------------------------------------------+
                              ^
          +-------------------+-------------------+
          |                   |                   |
+---------+---------+ +-------+-------+ +--------+--------+
|  WEAPON SKILLS    | |  DISCIPLINE   | |     RUNES       |
|  What you use     | |  How you play | |  What you find  |
|  Swords: 247/300  | |  Warfare: 2.8k| |  Blood Price    |
|  Daggers: 89/300  | |  Finesse: 1.2k| |  Last Stand     |
+-------------------+ +---------------+ +-----------------+
```

## System 1: Weapon Skills

Each weapon TYPE has an independent skill level that determines your effectiveness.

### Level-Based Skill Cap

```
Weapon Skill Cap = Player Level x 10

Level 1  -> Cap: 10
Level 10 -> Cap: 100
Level 20 -> Cap: 200
Level 30 -> Cap: 300 (maximum)
```

### Weapon Skill Types

| Skill | Associated Weapons | Primary Stat |
|-------|-------------------|--------------|
| Swords | Longsword, Rapier | Strength/Agility |
| Daggers | Stiletto, Kris | Agility |
| Maces | Morning Star, Flanged Mace | Strength |
| Hammers | Warhammer, Maul | Strength |
| Spears | Pike, Halberd | Strength/Agility |
| Staves | Healing Staff, Wizard Staff | Vitality |

### Skill Effects (Relative to Cap)

| Fill % | Miss Chance | Damage | Status |
|--------|-------------|--------|--------|
| 0-15% | 25% miss | 50% | "Untrained" |
| 16-33% | 20% miss | 60% | "Novice" |
| 34-50% | 15% miss | 70% | "Competent" |
| 51-66% | 10% miss | 80% | "Skilled" |
| 67-83% | 5% miss | 90% | "Expert" |
| 84-99% | 2% miss | 95% | "Nearly Maxed" |
| 100% | 0% miss | 100% | "Maxed" |

### Skill Gain Formula

```gdscript
SKILL_GAIN_HIT = 0.5     # Landing a hit
SKILL_GAIN_MISS = 0.1    # Missing (still learning)
SKILL_GAIN_KILL = 3.0    # Killing blow
SKILL_GAIN_CRIT = 1.0    # Critical hit bonus

# Catch-up: faster gains when far from cap
var fill_ratio = current / float(cap)
var catch_up_bonus = lerp(2.0, 0.5, fill_ratio)  # 2x empty, 0.5x full
```

### Weapon-Specific Unlocks

**Passives (Skill 100):**
| Weapon | Passive | Effect |
|--------|---------|--------|
| Swords | Blade Precision | +3% crit |
| Daggers | Arterial Cuts | Crits cause bleed |
| Maces | Crushing Blows | 10% stagger |
| Hammers | Armor Break | -5% defense (stacks 3x) |
| Spears | Reach | +15% range |
| Staves | Focused Channeling | +20% healing |

**Abilities (Skill 200):**
| Weapon | Ability | Effect | CD |
|--------|---------|--------|-----|
| Swords | Blade Flurry | 3 rapid 50% attacks | 20s |
| Daggers | Eviscerate | 200% from behind | 15s |
| Maces | Concussive Slam | AOE 1.5s stun | 30s |
| Hammers | Execution | 300% under 20% HP | 25s |
| Spears | Impale | Pierce 2 enemies | 12s |
| Staves | Sanctuary | Heal zone 10HP/s | 45s |

## System 2: Runes

Rare world drops that grant abilities, passives, or special effects.

### Rune Slots

| Slot | Unlock Requirement |
|------|--------------------|
| 1 | Level 5 |
| 2 | Level 15 |
| 3 | Level 25 |
| 4 | Any weapon skill 200 |
| 5 | Any weapon skill 300 |
| 6 | Two weapon skills 300 |

### Rune Categories

**Ability Runes** - Active abilities with cooldowns
```
[Rune of Sanguine Fury]
Ability: Blood Price
Effect: -15% HP, +30% damage (10s)
Cooldown: 60s
```

**Passive Runes** - Permanent stat bonuses
```
[Rune of the Relentless]
Effect: Chain decay -50%
```

**Trait Runes** - Conditional bonuses
```
[Rune of Last Stand]
Condition: Below 30% HP
Effect: +25% damage
```

**Title Runes** - Cosmetic + minor bonus
```
[Wolfbane Rune]
Requirement: Kill 500 wolves
Effect: +5% vs wolves, title "Wolfbane"
```

### Rune Rarity

| Rarity | Drop Rate | Trade |
|--------|-----------|-------|
| Common | 1.0x | Yes |
| Uncommon | 0.5x | Yes |
| Rare | 0.2x | Yes |
| Epic | 0.05x | Yes |
| Legendary | 0.01x | No |
| Artifact | Boss only | No |

## System 3: Discipline Affinity

Tracks HOW you play, not just what weapon you hold.

### The Disciplines

| Discipline | Playstyle | Tracks |
|------------|-----------|--------|
| Warfare | Aggressive | Damage, kills, combat time |
| Finesse | Precision | Crits, dodges, one-shots |
| Brutality | Berserker | Overkill, chains, multi-kills |
| Piety | Support | Healing, revives, buffs |
| Guardianship | Tank | Damage taken, aggro held |

### Affinity Thresholds

| Points | Tier | Unlock |
|--------|------|--------|
| 500 | Initiate | Minor title |
| 1,000 | Adept | Discipline passive |
| 2,500 | Specialist | First ability |
| 5,000 | Expert | Enhanced passive |
| 10,000 | Master | Second ability, title |

### Discipline Passives (1,000 points)

| Discipline | Passive | Effect |
|------------|---------|--------|
| Warfare | Battle Hardened | +5% damage |
| Finesse | Keen Eye | +5% crit |
| Brutality | Blood Frenzy | +2% per chain |
| Piety | Blessed Touch | +15% healing |
| Guardianship | Stalwart | +10% DR |

### Discipline Abilities (2,500 / 10,000)

| Discipline | First (2.5k) | Master (10k) |
|------------|--------------|--------------|
| Warfare | Battle Cry (+20% dmg) | Unstoppable (immune CC) |
| Finesse | Riposte (dodge->crit) | Death Mark (+30% taken) |
| Brutality | Execute (+50% low HP) | Rampage (kills extend buffs) |
| Piety | Sanctuary (heal zone) | Divine Shield (absorb) |
| Guardianship | Taunt (force aggro) | Last Stand (survive at 1HP) |

## System 4: Emergent Classes

Your "class" emerges from weapon + discipline combination.

### Class Matrix (6 Weapons x 5 Disciplines = 30 Classes)

| Weapon | Warfare | Finesse | Brutality | Piety | Guardian |
|--------|---------|---------|-----------|-------|----------|
| Swords | Blademaster | Duelist | Berserker | Templar | Sword Knight |
| Daggers | Assassin | Rogue | Cutthroat | Nightblade | Shadow Guard |
| Maces | Crusher | Brawler | Ravager | Priest | Cleric |
| Hammers | Warlord | Executioner | Berserker | Justicar | Paladin |
| Spears | Dragoon | Lancer | Impaler | Valkyrie | Hoplite |
| Staves | Battle Mage | Sage | Warlock | High Priest | Arcane Ward |

### Title Progression

```
Skill 1-49:     "Adventurer [Name]"
Skill 50-99:    "[Weapon] Initiate [Name]"
Skill 100-149:  "[Weapon] Apprentice [Name]"
Skill 150-199:  "[Class Base] [Name]"
Skill 200-249:  "[Class] [Name]"
Skill 250-299:  "[Class] Master [Name]"
Skill 300:      "Grandmaster [Class] [Name]"
```

### Prestige Titles (Multi-Mastery)

| Achievement | Title |
|-------------|-------|
| 1x Grandmaster | "Grandmaster [Class]" |
| 2x Grandmaster | "[Dual Class Title]" |
| 3x Grandmaster | "Legendary [Class]" |
| 4x Grandmaster | "Mythic [Class]" |
| 5x Grandmaster | "Paragon" |
| All Grandmaster | "[Name] the Transcendent" |

### Dual-Mastery Titles

| Combo | Title |
|-------|-------|
| Swords + Daggers | Sword Saint |
| Swords + Maces | Battle Lord |
| Swords + Staves | Spellblade |
| Daggers + Hammers | Shadow Crusher |
| Maces + Staves | Holy Warrior |
| Hammers + Spears | Warlord Prime |

## Example Player Progression

**Level 5:** Adventurer -> trying weapons, discipline unformed

**Level 15:** Sword Apprentice -> Warfare growing from kills

**Level 25:** Blademaster -> Maxed sword + Warfare Specialist

**Level 30:** Grandmaster Blademaster -> Working on 2nd weapon

**Prestige:** Sword Saint -> Swords + Daggers both at 300

## Technical Implementation

### New Files Required

```
scripts/systems/WeaponSkillManager.gd   - Weapon skill tracking
scripts/systems/DisciplineManager.gd    - Discipline affinity
scripts/systems/RuneManager.gd          - Rune inventory & slots
scripts/systems/ClassManager.gd         - Class/title determination
scripts/resources/Rune.gd               - Rune resource definition
scripts/ui/WeaponSkillUI.gd             - Skills display
scripts/ui/DisciplineUI.gd              - Discipline display
scripts/ui/RuneUI.gd                    - Rune management UI
data/runes.json                         - Rune definitions
data/disciplines.json                   - Discipline config
data/class_matrix.json                  - Class determination
```

### Balance Targets

| Level | Skill Cap | Time to Reach |
|-------|-----------|---------------|
| 5 | 50 | ~1 hour |
| 10 | 100 | ~3 hours |
| 15 | 150 | ~6 hours |
| 20 | 200 | ~10 hours |
| 25 | 250 | ~15 hours |
| 30 | 300 | ~20-25 hours |

**Catch-up:** ~100 kills to cap a new weapon (~1-2 hours)

### Rune Drop Rates

| Rarity | Expected Per Hour |
|--------|-------------------|
| Common | 2-3 |
| Uncommon | 0.5-1 |
| Rare | 1 per 3-4 hours |
| Epic | 1 per 10-15 hours |
| Legendary | 1 per 30-50 hours |

---

## Design Principles Summary

### Settlement System
- Resource gathering creates reasons to explore
- Settlement defense creates reasons to cooperate
- Siege windows allow PvP without 24/7 vulnerability
- Progression tied to reputation with NPCs

### Class System
- No upfront class selection - identity emerges
- Weapon skill capped by level (fair at all levels)
- Discipline tracks behavior automatically
- 30 unique classes from weapon x discipline matrix
- Runes provide customization independent of weapon
- Prestige path for post-max-level goals

---

# World Trees (Guild Anchors)

**Status: FULL SPECIFICATION AVAILABLE**

> **See:** [WORLD_TREE_SYSTEM.md](./WORLD_TREE_SYSTEM.md) for the complete specification.

World Trees are the core guild base system, inspired by Shadowbane's Tree of Life:

### Quick Reference

| Rank | Name | Cost | Health | Protection Slots | Mine Limit |
|------|------|------|--------|------------------|------------|
| 1 | Sapling | - | 10,000 | 2 | 1 |
| 2 | Young Tree | 10,000g | 20,000 | 4 | 1 |
| 3 | Growing Tree | 25,000g | 35,000 | 6 | 2 |
| 4 | Mature Tree | 50,000g | 55,000 | 8 | 2 |
| 5 | Ancient Tree | 100,000g | 80,000 | 10 | 3 |
| 6 | Elder Tree | 200,000g | 110,000 | 12 | 4 |
| 7 | World Tree | 500,000g | 150,000 | 15 | 5 |

### Key Features

- **Runekeeper Protection** - Buildings in protection slots are invulnerable outside banes
- **Building Placement** - Warehouse, vendors, shrines, storage, crafting
- **Resource Mines** - Claim mines for passive gold/resource income
- **Bane Siege System** - 3-day countdown, 2-hour vulnerability window
- **World Map Visibility** - Tree rank visible to all players (prestige + target signal)

---

# Implementation Roadmap

## Phase 1: Foundation (Completed)
- [x] Chunk-based enemy spawning
- [x] Group system (40 players)
- [x] Campfire ownership mechanics
- [x] Healing staff (support role)
- [x] Quest system framework
- [x] PvP duel system
- [x] Wolf enemies with pack behavior
- [x] Gun weapon system

## Phase 2: Economy & Forge Trading
- [ ] Alchemist vendor + potions
- [ ] Jeweler vendor + accessories
- [ ] Material gathering system
- [ ] Player trading (native items)
- [ ] **Forge Trading System** (see `FORGE_ECONOMY_DESIGN.md`)
  - [ ] Trade routes in backend
  - [ ] Trade window UI in Godot
  - [ ] Marketplace (auction house)
  - [ ] Provenance tracking

## Phase 3: World Tree System (see `WORLD_TREE_SYSTEM.md`)

### Phase 3.1: Core Tree System
- [ ] Seed Plot POI generation in edge chunks
- [ ] World Tree Seed item at Blacksmith (1,000g)
- [ ] Planting mechanic (guild-bound)
- [ ] Basic tree visual (Rank 1)
- [ ] Tree appears on world map with rank
- [ ] Basic respawn binding for guild members

### Phase 3.2: Watering System
- [ ] Empty Vial item at Blacksmith (50g)
- [ ] CleanseableLavaPool.gd (extends existing lava pools)
- [ ] Lava pool visual states (active/cooling/ready)
- [ ] Cleanse interaction (3-sec channel, consumes vial)
- [ ] Purified Water item
- [ ] Lava pool cooldown system (5 minutes)
- [ ] Water tree interaction in WorldTreeUI
- [ ] Daily watering bonus (+10% growth speed)

### Phase 3.3: Rank & Protection
- [ ] Rank upgrade system (1-7)
- [ ] Gold costs and upgrade timers
- [ ] Rank visuals (all 7 stages)
- [ ] Runekeeper NPC (auto-spawns at tree)
- [ ] Protection slot system
- [ ] Tree health system

### Phase 3.4: Buildings & Vendors
- [ ] Building placement UI (6 slots around tree)
- [ ] Warehouse building (gold/resource storage)
- [ ] Vendor buildings (weapon, armor, potion, general)
- [ ] Vendor stocking and pricing UI
- [ ] Revenue collection to warehouse (5% tax)
- [ ] Storage chest buildings

### Phase 3.5: Economy & Mines
- [ ] Weekly maintenance cost system
- [ ] Maintenance failure/degradation
- [ ] Resource mine POI spawning
- [ ] Mine claiming mechanic (30-sec channel)
- [ ] Mine vulnerability windows (30 min/day)
- [ ] Hourly income deposits to warehouse

### Phase 3.6: Shrines & Buffs
- [ ] Shrine buildings (10,000g each)
- [ ] 5 shrine types (warfare, vitality, swiftness, fortune, protection)
- [ ] Buff application system
- [ ] Buff duration (30 min) and exclusivity rules

### Phase 3.7: Bane Siege System
- [ ] Corruption Stone item (costs scale with target rank)
- [ ] Stone placement mechanic (30-sec channel)
- [ ] 3-day countdown system with server broadcast
- [ ] Bane window selection UI for defenders
- [ ] Combat rules during bane (all vulnerable, PvP enabled)
- [ ] Victory/defeat outcomes
- [ ] War reparations system

### Phase 3.8: Polish
- [ ] World map integration (rank, guild name, siege status)
- [ ] Alliance tree visibility (future)
- [ ] Tree teleportation (Rank 5+)
- [ ] Ambient effects (particles, audio)
- [ ] Tutorial/onboarding for new tree owners

## Phase 4: PvP & Open World
- [ ] PvP flagging system (open world)
- [ ] Territory control bonuses
- [ ] Alliance system

## Phase 5: World Expansion
- [ ] Tier 2 biome (Cursed Lands)
- [ ] Dynamic chunk loading based on population
- [ ] Northern progression
- [ ] Higher-tier World Tree seeds for Zone 2+

---

*Status: Design Specifications - Implementation Starting*
