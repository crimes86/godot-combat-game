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

# Weapon Skill & Title System

**Status: READY FOR IMPLEMENTATION**

Weapon proficiency system where players develop mastery through combat. Each weapon type has independent skill that affects hit chance, damage, and unlocks abilities and titles.

**Design Philosophy:** Old-school skill progression with modern QOL. Players start competent but imperfect, mastering weapons through use.

## Architecture Overview

```
+-------------------------------------------------------------+
|  PLAYER IDENTITY                                            |
|  Title earned through weapon mastery                        |
|  "Kensei Kevin" / "Reaper Sarah" / "Archon Mike"            |
+-------------------------------------------------------------+
                              ^
                              |
+-------------------------------------------------------------+
|  WEAPON SKILLS (10 types)                                   |
|  Independent skill per weapon type (0-300)                  |
|  Affects: Hit chance, damage, unlocks passives & abilities  |
|  Swords: 247/300 | Bows: 89/300 | Healing: 150/300          |
+-------------------------------------------------------------+
```

> **FUTURE EXPANSION:** Disciplines (how you play) and Runes (socketed abilities) are planned for a later update. See "Future: Disciplines & Runes" section below.

---

## Weapon Skills

Each weapon TYPE has an independent skill level that determines your effectiveness.

### Level-Based Skill Cap

```
Weapon Skill Cap = Player Level × 10

Level 1  -> Cap: 10   (new player)
Level 10 -> Cap: 100  (unlock passives possible)
Level 20 -> Cap: 200  (unlock abilities possible)
Level 30 -> Cap: 300  (maximum mastery)
```

### Weapon Skill Types

| Skill | Associated Weapons | Primary Stat | Fantasy |
|-------|-------------------|--------------|---------|
| Swords | Longsword, Rapier, Katana, Scimitar | STR/AGI | Honorable warrior |
| Daggers | Dagger, Stiletto, Kris | AGI | Shadow assassin |
| Axes | Axe, Greataxe, Hatchet | STR | Brutal raider |
| Maces | Mace, Morning Star, Club | STR | Crushing enforcer |
| Hammers | Warhammer, Maul | STR | Armor breaker |
| Spears | Spear, Pike, Halberd | STR/AGI | Disciplined soldier |
| Bows | Shortbow, Longbow, Recurve | AGI | Patient hunter |
| Healing | Healing Staff, Restoration Wand | VIT | Divine healer |
| Arcane | Wizard Staff, Battle Staff | INT | Battle mage |
| Guns | Pistol, Rifle, Battle Rifle | AGI | Precise marksman |

### Skill Effects (Relative to Cap)

**Design:** Start competent (not helpless), master to perfection. Miss chance is noticeable but not crippling.

| Fill % | Miss Chance | Damage | Status | Combat Feel |
|--------|-------------|--------|--------|-------------|
| 0-10% | 15% miss | 70% | Untrained | Rough but manageable |
| 11-25% | 12% miss | 75% | Novice | Getting the hang of it |
| 26-50% | 8% miss | 82% | Competent | Comfortable |
| 51-75% | 4% miss | 90% | Skilled | Reliable |
| 76-99% | 2% miss | 96% | Expert | Confident |
| 100% | 0% miss | 100% | Master | Perfect execution |

**Balance Note:** At 0% skill, effective DPS is ~60% of max (0.70 damage × 0.85 hit rate). This is challenging but not frustrating for early game enemies.

### Skill Gain Formula

```gdscript
const SKILL_GAIN = {
    "hit": 0.5,       # Landing a hit
    "miss": 0.2,      # Missing (still learning)
    "kill": 2.0,      # Killing blow
    "crit": 0.5,      # Critical hit bonus
}

# Catch-up: faster gains when far from cap (3x at empty, 0.5x near cap)
var fill_ratio = current_skill / float(skill_cap)
var catch_up_mult = lerp(3.0, 0.5, fill_ratio)
final_gain = base_gain * catch_up_mult
```

**Time to Cap Estimates:**
- Skill 0 → 50: ~30 minutes (fast early progression)
- Skill 50 → 100: ~1 hour
- Skill 100 → 200: ~3-4 hours
- Skill 200 → 300: ~8-10 hours
- **Total 0 → 300:** ~15-20 hours per weapon

---

## Weapon-Specific Unlocks

### Passives (Skill 100)

Permanent bonuses while wielding the weapon type.

| Weapon | Passive Name | Effect |
|--------|--------------|--------|
| Swords | Blade Precision | +3% crit chance |
| Daggers | Arterial Cuts | Critical hits cause 3s bleed (2 dmg/s) |
| Axes | Cleaving Strikes | 30% damage to adjacent enemies |
| Maces | Crushing Force | 10% chance to stagger (interrupt) |
| Hammers | Armor Sunder | -5% enemy defense per hit (stacks 3x) |
| Spears | Extended Reach | +15% attack range |
| Bows | Eagle Eye | +20% effective range, no damage falloff |
| Healing | Blessed Touch | +25% healing power, heals remove 1 debuff |
| Arcane | Spell Weaving | +15% spell damage, -10% cooldowns |
| Guns | Steady Aim | -25% spread, +10% headshot zone |

### Abilities (Skill 200)

Active abilities with cooldowns. Bound to ability key when weapon equipped.

| Weapon | Ability | Effect | Cooldown |
|--------|---------|--------|----------|
| Swords | Blade Flurry | 3 rapid strikes at 50% damage each | 20s |
| Daggers | Eviscerate | 200% damage from behind, 150% otherwise | 15s |
| Axes | Whirlwind | 360° spin attack, 80% damage to all nearby | 18s |
| Maces | Concussive Slam | AOE ground pound, 1.5s stun | 30s |
| Hammers | Execution | 300% damage to enemies below 20% HP | 25s |
| Spears | Impale | Thrust pierces up to 2 enemies | 12s |
| Bows | Rain of Arrows | AOE volley, 60% damage to all in area | 25s |
| Healing | Sanctuary | Create healing zone, 15 HP/s for 8s | 45s |
| Arcane | Arcane Blast | 250% damage AOE explosion, knockback | 22s |
| Guns | Deadeye Shot | Guaranteed critical hit, +50% damage | 20s |

---

## Title System

Titles are earned through weapon mastery and displayed with character name. Each weapon type has its own thematic title progression.

### Title Progression by Weapon

**Swords** *(Path of the Blade - Honorable Warriors)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Kevin |
| 50-99 | Squire | Squire Kevin |
| 100-149 | Swordsman | Swordsman Kevin |
| 150-199 | Bladesman | Bladesman Kevin |
| 200-249 | Blademaster | Blademaster Kevin |
| 250-299 | Sword Saint | Sword Saint Kevin |
| 300 | Kensei | Kensei Kevin |

**Daggers** *(Path of Shadows - Silent Killers)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Sarah |
| 50-99 | Footpad | Footpad Sarah |
| 100-149 | Knifesman | Knifesman Sarah |
| 150-199 | Cutthroat | Cutthroat Sarah |
| 200-249 | Shadow | Shadow Sarah |
| 250-299 | Phantom | Phantom Sarah |
| 300 | Reaper | Reaper Sarah |

**Axes** *(Path of Fury - Berserker Raiders)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Bjorn |
| 50-99 | Woodcutter | Woodcutter Bjorn |
| 100-149 | Axeman | Axeman Bjorn |
| 150-199 | Raider | Raider Bjorn |
| 200-249 | Berserker | Berserker Bjorn |
| 250-299 | Warlord | Warlord Bjorn |
| 300 | Executioner | Executioner Bjorn |

**Maces** *(Path of Ruin - Crushing Enforcers)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Marcus |
| 50-99 | Brawler | Brawler Marcus |
| 100-149 | Clubman | Clubman Marcus |
| 150-199 | Crusher | Crusher Marcus |
| 200-249 | Enforcer | Enforcer Marcus |
| 250-299 | Devastator | Devastator Marcus |
| 300 | Juggernaut | Juggernaut Marcus |

**Hammers** *(Path of the Titan - Armor Breakers)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Thor |
| 50-99 | Laborer | Laborer Thor |
| 100-149 | Hammerman | Hammerman Thor |
| 150-199 | Smasher | Smasher Thor |
| 200-249 | Breaker | Breaker Thor |
| 250-299 | Demolisher | Demolisher Thor |
| 300 | Titan | Titan Thor |

**Spears** *(Path of the Phalanx - Disciplined Soldiers)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Leonidas |
| 50-99 | Militia | Militia Leonidas |
| 100-149 | Pikeman | Pikeman Leonidas |
| 150-199 | Hoplite | Hoplite Leonidas |
| 200-249 | Lancer | Lancer Leonidas |
| 250-299 | Dragoon | Dragoon Leonidas |
| 300 | Valkyrie | Valkyrie Leonidas |

**Bows** *(Path of the Hunt - Patient Hunters)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Robin |
| 50-99 | Fletcher | Fletcher Robin |
| 100-149 | Bowman | Bowman Robin |
| 150-199 | Archer | Archer Robin |
| 200-249 | Ranger | Ranger Robin |
| 250-299 | Hawkeye | Hawkeye Robin |
| 300 | Artemis | Artemis Robin |

**Healing** *(Path of the Divine - Sacred Healers)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Elena |
| 50-99 | Acolyte | Acolyte Elena |
| 100-149 | Healer | Healer Elena |
| 150-199 | Mender | Mender Elena |
| 200-249 | Cleric | Cleric Elena |
| 250-299 | High Priest | High Priest Elena |
| 300 | Archon | Archon Elena |

**Arcane** *(Path of the Arcane - Battle Mages)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Merlin |
| 50-99 | Initiate | Initiate Merlin |
| 100-149 | Apprentice | Apprentice Merlin |
| 150-199 | Wizard | Wizard Merlin |
| 200-249 | Sorcerer | Sorcerer Merlin |
| 250-299 | Archmage | Archmage Merlin |
| 300 | Magus | Magus Merlin |

**Guns** *(Path of the Bullet - Precise Marksmen)*
| Skill | Title | Full Example |
|-------|-------|--------------|
| 0-49 | *(none)* | Dutch |
| 50-99 | Recruit | Recruit Dutch |
| 100-149 | Marksman | Marksman Dutch |
| 150-199 | Sharpshooter | Sharpshooter Dutch |
| 200-249 | Gunslinger | Gunslinger Dutch |
| 250-299 | Deadeye | Deadeye Dutch |
| 300 | Deadshot | Deadshot Dutch |

### Active Title Selection

Players can choose which earned title to display:
- Default: Highest skill weapon's title
- Option: Any title from weapons with skill 50+
- Option: "Adventurer [Name]" (hide title)

### Prestige Titles (Multi-Mastery)

Earned by mastering multiple weapons to 300.

| Achievement | Title | Example |
|-------------|-------|---------|
| Any 1 weapon at 300 | [Weapon Title] | Kensei Kevin |
| Any 2 weapons at 300 | Weapons Master | Weapons Master Kevin |
| Any 4 weapons at 300 | Battle Legend | Battle Legend Kevin |
| Any 7 weapons at 300 | Paragon | Paragon Kevin |
| All 10 weapons at 300 | The Transcendent | Kevin the Transcendent |

### Dual-Mastery Special Titles

Specific weapon combinations unlock unique titles:

| Combo | Special Title | Fantasy |
|-------|---------------|---------|
| Swords + Daggers | Blade Dancer | Master of all blades |
| Swords + Spears | Champion | Versatile warrior |
| Daggers + Guns | Hitman | Professional killer |
| Daggers + Bows | Stalker | Silent hunter |
| Axes + Hammers | Warchief | Brutal devastator |
| Maces + Hammers | Siegebreaker | Fortress destroyer |
| Spears + Bows | Sentinel | Ranged defender |
| Bows + Guns | Deadeye | Master of ranged |
| Healing + Arcane | Mystic | Master of magic |
| Healing + Any melee | Battle Priest | Healer who fights |
| Arcane + Any melee | Spellblade | Magic warrior |

---

## Player Statistics & Leaderboards

Track and display global statistics to help players see rarity and make informed decisions.

### Per-Title Statistics

The backend tracks how many players have reached each title tier. Displayed in UI as percentage.

```
Example UI display for Swords path:
┌─────────────────────────────────────────┐
│  PATH OF THE BLADE                      │
├─────────────────────────────────────────┤
│  Squire (50)      ████████████  82.3%   │
│  Swordsman (100)  ██████████    64.1%   │
│  Bladesman (150)  ██████        38.7%   │
│  Blademaster (200)████          21.2%   │
│  Sword Saint (250)██            8.4%    │
│  Kensei (300)     ▌             0.7%    │  ← "Only 0.7% of players!"
└─────────────────────────────────────────┘
```

### Backend Tracking

```python
# WeaponSkillStats table
class WeaponSkillStats(Base):
    weapon_type: str       # "swords", "daggers", etc.
    skill_bracket: int     # 50, 100, 150, 200, 250, 300
    player_count: int      # Number of players who reached this
    last_updated: datetime

# API endpoint
GET /api/weapon-stats/global
Returns: { "swords": { "50": 8234, "100": 6412, ... }, ... }
```

### Leaderboard Categories

| Category | Description | Display |
|----------|-------------|---------|
| **Title Rarity** | % of players with each title | Bar chart per weapon |
| **First to Max** | First players to reach 300 in each weapon | Hall of Fame |
| **Most Versatile** | Most weapons at 200+ skill | Top 100 list |
| **Transcendents** | Players with all 10 at 300 | Exclusive list |
| **Rising Stars** | Fastest skill gains this week | Weekly spotlight |

### UI Integration

1. **Character Panel** - Show your title + "Top X%" badge
2. **Title Selection** - See rarity % next to each title option
3. **Skill Progress** - "X more to reach [Title] (held by Y% of players)"
4. **Inspect Other Players** - See their titles + rarity badges

### Rarity Badges

| % of Players | Badge | Color |
|--------------|-------|-------|
| Top 50%+ | Common | Gray |
| Top 25% | Uncommon | Green |
| Top 10% | Rare | Blue |
| Top 5% | Epic | Purple |
| Top 1% | Legendary | Orange |
| Top 0.1% | Mythic | Red glow |

---

## Technical Implementation

### New Files Required (Phase 1: Weapon Skills & Titles)

```
scripts/systems/WeaponSkillManager.gd   - Weapon skill tracking & persistence
scripts/systems/TitleManager.gd         - Title determination & display
scripts/ui/WeaponSkillUI.gd             - Skills display panel
data/weapon_skills.json                 - Skill config & title definitions
```

### Implementation Priority

1. **WeaponSkillManager.gd** - Core skill tracking
   - Track skill per weapon type (8 types)
   - Apply miss chance and damage scaling
   - Skill gain on combat events
   - Persistence (save/load)

2. **Combat Integration** - Modify PlayerCombat.gd
   - Check weapon skill before hit resolution
   - Apply miss chance roll
   - Scale damage by skill level
   - Grant skill XP on hits/kills

3. **UI Integration** ✓ IMPLEMENTED (UI scaffolding)
   - Skill bar showing current weapon skill / cap
   - Floating "+0.5 Sword Skill" notifications
   - Milestone popups ("Sword Skill 100! Unlocked: Blade Precision")
   - Title display on character nameplate

### UI Implementation Status

**CharacterUI.gd** - Weapon Mastery section added:
- Compact display showing: Weapon Category | Title | Skill/Cap | Progress Bar
- Press-and-hold (1 second) opens full Weapon Skills panel
- Full panel shows all 10 weapon types with progress bars and current titles
- Current equipped weapon type highlighted

**Standardized Press-Hold Pattern:**
The game uses a consistent press-and-hold interaction pattern for opening detailed views:

```gdscript
# Pattern: 1 second hold with radial progress indicator
const LONG_HOLD_DURATION = 1.0  # seconds

# Components:
var _long_hold_timer: Timer       # Fires after duration
var _long_hold_start_time: float  # For progress calculation
var _radial_progress: Control     # Visual indicator (follows cursor)

func _start_long_hold() -> void:
    _cancel_long_hold()
    _long_hold_start_time = Time.get_ticks_msec() / 1000.0

    _long_hold_timer = Timer.new()
    _long_hold_timer.wait_time = LONG_HOLD_DURATION
    _long_hold_timer.one_shot = true
    _long_hold_timer.timeout.connect(_on_long_hold_triggered)
    add_child(_long_hold_timer)
    _long_hold_timer.start()

    _radial_progress = _create_radial_progress()
    add_child(_radial_progress)

func _process(delta: float) -> void:
    if _radial_progress and _long_hold_start_time > 0:
        _radial_progress.global_position = get_viewport().get_mouse_position() - Vector2(24, 24)
        var elapsed = (Time.get_ticks_msec() / 1000.0) - _long_hold_start_time
        var progress = clampf(elapsed / LONG_HOLD_DURATION, 0.0, 1.0)
        _radial_progress.set_meta("progress", progress)
        _radial_progress.queue_redraw()
```

**Visual Design:**
- 48x48 pixel radial indicator
- Dark backdrop disc with inner dark circle
- Golden progress arc with glow effect
- Tip indicator dot at progress edge
- Center icon (magnifying glass for inspection)

**Current Uses:**
| Location | Element | Opens |
|----------|---------|-------|
| InventoryUI | Item slot | Item Inspection Panel |
| CharacterUI | Equipment slot | Item Inspection Panel |
| CharacterUI | Mastery section | Full Weapon Skills Panel |

**Standardized Side-by-Side Panel Layout:**
When opening secondary panels (inspection, skills, etc.), use consistent positioning:

```gdscript
# Constants in CharacterUI.gd
const PANEL_GAP: int = 8  # Minimal gap between panels
const CHARACTER_PANEL_WIDTH: int = 580
const INSPECTION_PANEL_WIDTH: int = 360
const SKILLS_PANEL_WIDTH: int = 500

# Calculate positions to center both panels together
func _shift_panel_left_for(secondary_width: int) -> void:
    var total_width = CHARACTER_PANEL_WIDTH + PANEL_GAP + secondary_width
    var left_panel_left = -total_width / 2
    var left_panel_right = left_panel_left + CHARACTER_PANEL_WIDTH
    # Tween to new position...

func _get_secondary_panel_position(secondary_width: int) -> Dictionary:
    var total_width = CHARACTER_PANEL_WIDTH + PANEL_GAP + secondary_width
    var left_panel_right = -total_width / 2 + CHARACTER_PANEL_WIDTH
    return {
        "offset_left": left_panel_right + PANEL_GAP,
        "offset_right": left_panel_right + PANEL_GAP + secondary_width
    }
```

**Layout Behavior:**
- Primary panel shifts left smoothly (0.15s tween)
- Secondary panel appears with 8px gap
- Combined panels centered on screen
- ESC closes secondary first, then primary
- Closing secondary restores primary to center

4. **Passive System** - Apply bonuses at skill 100
5. **Ability System** - Unlock abilities at skill 200

### QOL Features

- **Weapon swap grace period** - No miss penalty for 3s after swap (encourages experimentation)
- **Training dummy** - Practice weapon skills without risk
- **Skill preview** - Show what unlocks at next milestone
- **Miss feedback** - Clear "MISS" text with whoosh sound (not silent failure)

---

## Future Expansion: Disciplines & Runes

> **STATUS: DEFERRED** - These systems are planned for a future expansion after weapon skills are stable.

### Disciplines (How You Play)

Tracks playstyle automatically to influence emergent class identity.

| Discipline | Playstyle | Tracks |
|------------|-----------|--------|
| Warfare | Aggressive | Damage dealt, kills, combat time |
| Finesse | Precision | Crits, dodges, one-shots |
| Brutality | Berserker | Overkill, chains, multi-kills |
| Piety | Support | Healing, revives, buffs given |
| Guardianship | Tank | Damage taken, aggro held |

When implemented, disciplines will combine with weapon mastery to create emergent classes (e.g., Sword + Warfare = Blademaster, Sword + Finesse = Duelist).

### Runes (What You Find)

Socketable items that grant abilities, passives, or conditional bonuses.

- **Ability Runes** - Active abilities with cooldowns
- **Passive Runes** - Permanent stat bonuses
- **Trait Runes** - Conditional bonuses (e.g., +25% damage below 30% HP)
- **Title Runes** - Cosmetic titles with minor bonuses

Rune slots would unlock at character levels and weapon skill milestones.

### Full Class Matrix (Future)

When disciplines are implemented, 10 weapons × 5 disciplines = 50 emergent classes.

---

## Design Principles Summary

### Weapon Skill System
- Old-school feel with modern QOL
- 10 weapon types with independent skill tracks
- Start competent (not helpless), master to perfection
- Fast early progression, slower mastery grind
- Clear milestones with tangible rewards (passives, abilities, titles)
- Multiple weapons encouraged through prestige titles

### Title System
- Thematic titles per weapon path (10 unique progressions)
- Player choice in displayed title
- Prestige rewards for multi-weapon mastery
- Social signaling of player accomplishment
- Rarity statistics show % of players at each tier

### Statistics & Social
- Global tracking of player progression
- Rarity badges (Common → Mythic) based on percentile
- Leaderboards for prestige achievements
- Helps players see diversity and make decisions

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
