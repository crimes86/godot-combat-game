# Wasteland: Game Design Roadmap

## Vision Statement

A sandbox survival game with emergent player-driven communities. Players establish personal or guild bases in dynamically managed chunks, progress through vendor quest lines, and migrate north to harder biomes. Bases become siegeable under specific conditions, creating meaningful PvP stakes.

---

## Core Design Pillars

### 1. Dynamic Horizontal World
- **Chunks spawn/despawn based on population** - Server resources scale with player activity
- **Infinite horizontal expansion** - World grows as players explore
- **No arbitrary boundaries** - Natural difficulty gradient replaces hard walls

### 2. Loose Vertical Progression
- **Graceful zone transitions** - No hard level gates, just increasing risk/reward
- **Skill > Gear** - Player skill matters more than equipment at any level
- **Catch-up mechanics** - Lower level players can contribute meaningfully

### 3. Player-Driven Economy
- **Vendor quest progression** - Unlock specialist vendors through gameplay
- **Base building** - Cookie-cutter templates with upgrade paths
- **Player-placed stations** - Enable trading, crafting, socializing

### 4. Meaningful PvP Stakes
- **Siegeable bases** - Risk vs reward for territory control
- **World Trees** - Guild anchors that can be contested
- **Opt-in conflict** - Clear rules for when PvP is enabled

---

## World Structure

### Biome Layout (North = Harder)

```
NORTH (Harder)
    ↑
┌─────────────────────────────────────────────────────┐
│  TIER 4: VOID WASTES (Level 60+)                    │
│  - Corrupted terrain, environmental damage          │
│  - Raid-level world bosses                          │
│  - Legendary material nodes                         │
│  - Guild-only bases viable                          │
├─────────────────────────────────────────────────────┤
│  TIER 3: SHADOW REALM (Level 30-60)                 │
│  - Dark forest, haunted ruins                       │
│  - Elite skeleton variants, mini-bosses             │
│  - Rare crafting materials                          │
│  - Contested PvP zones                              │
├─────────────────────────────────────────────────────┤
│  TIER 2: CURSED LANDS (Level 15-30)                 │
│  - Dead forest, corrupted ground                    │
│  - Armored skeletons, roaming packs                 │
│  - Uncommon materials                               │
│  - Base building unlocked                           │
├─────────────────────────────────────────────────────┤
│  TIER 1: THE WASTELAND (Level 1-15)                 │
│  - Current game area (Campfire → Castle)            │
│  - Basic skeletons, tutorial experience             │
│  - Common materials                                 │
│  - Safe zone: Campfire area                         │
└─────────────────────────────────────────────────────┘
    ↓
SOUTH (Spawn/Safe)
```

### Chunk System Enhancement

**Current:** 3 static chunks (8000x8000 each), enemies per chunk
**Proposed:** Dynamic chunk grid with population-based loading

```gdscript
# ChunkManager enhancements
const CHUNK_SIZE = 4000  # Smaller chunks for finer control
const MIN_ACTIVE_CHUNKS = 9  # 3x3 around spawn
const MAX_ACTIVE_CHUNKS = 100  # Server resource limit

# Population-based chunk loading
func _evaluate_chunk_activation(chunk_coord: Vector2i) -> bool:
    var players_nearby = get_players_within_chunks(chunk_coord, 2)
    var has_player_base = base_registry.has_base_in_chunk(chunk_coord)

    # Keep chunk loaded if:
    # - Players are nearby (within 2 chunk radius)
    # - Player base exists (even if owner offline - for sieges)
    # - Is spawn area (always loaded)
    return players_nearby > 0 or has_player_base or is_spawn_chunk(chunk_coord)
```

---

## Vendor Progression System

### Core Concept
NPCs start at the Campfire (Tier 1) and "migrate" with players as they progress. Each vendor has a quest line that unlocks new tiers and eventually allows player placement.

### Vendor Types

#### Blacksmith (Combat Equipment)
**Current:** Sells weapons at Campfire
**Quest Line:**
1. **Apprentice** - Deliver 10 Iron Ore → Unlocks weapon repairs
2. **Journeyman** - Defeat 50 Skeletons with his weapons → Unlocks armor crafting
3. **Master** - Bring Ancient Forge Blueprints (dungeon drop) → Unlocks legendary crafting
4. **Portable Forge** - Reach Level 20, Gold investment → Place in your base

#### Alchemist (Consumables)
**New vendor to add**
**Quest Line:**
1. **Herbalist** - Gather 20 Bone Ember → Sells basic potions
2. **Chemist** - Defeat Poison Skeleton Boss → Unlocks buff potions
3. **Alchemist** - Brew 50 potions → Unlocks transmutation (material conversion)
4. **Alchemy Station** - Place in base for autonomous potion production

#### Jeweler (Accessories)
**New vendor to add**
**Quest Line:**
1. **Trinket Maker** - Deliver 10 Dusty Gems → Sells basic rings/amulets
2. **Gem Cutter** - Find Rare Gem (Zone 3 drop) → Unlocks stat gems
3. **Master Jeweler** - Craft 10 enchanted items → Unlocks socketing system
4. **Jewelry Workbench** - Place in base

#### Gambler (Risk/Reward)
**New vendor to add**
**Quest Line:**
1. **Street Dealer** - Win 5 gambles → Appears at Campfire
2. **High Roller** - Lose 500 gold total → Unlocks rare item pool
3. **House Master** - Win jackpot once → Unlocks daily jackpot feature
4. **Gambling Den** - Place in base (attracts visitors, takes cut)

#### Artificer (Base Building)
**New vendor to add** - Key for base building system
**Quest Line:**
1. **Handyman** - Repair 10 structures → Sells basic building materials
2. **Architect** - Build your first base → Unlocks advanced structures
3. **Siege Engineer** - Successfully defend a siege → Unlocks defensive structures
4. **Mobile Workshop** - Always available at your base

### Vendor Migration System

```gdscript
# VendorMigration system concept
class_name VendorMigration

# Vendors track highest tier player has unlocked
var player_vendor_progress: Dictionary = {}  # player_id -> {vendor_type -> tier}

# When player moves to new biome, vendors can follow
func migrate_vendors_for_player(player_id: int, new_biome_tier: int):
    var progress = player_vendor_progress.get(player_id, {})

    for vendor_type in progress:
        var vendor_tier = progress[vendor_type]
        if vendor_tier >= 3:  # Master tier can migrate
            spawn_vendor_at_player_base(player_id, vendor_type)
```

---

## Base Building System

### Design Philosophy
- **Cookie-cutter templates** - Standardized base layouts prevent griefing/ugly bases
- **Upgrade paths** - Templates evolve as player progresses
- **Portable** - Bases can migrate north with the player

### Base Templates

#### Tier 1: Camp (Unlocked at Level 5)
- 1x Bedroll (respawn point)
- 1x Storage Chest (20 slots)
- 1x Campfire (existing system)
- **Footprint:** 3x3 chunk tiles

#### Tier 2: Outpost (Unlocked at Level 15, costs 500g)
- 1x Tent (logout safety)
- 2x Storage Chests (40 slots total)
- 1x Crafting Station slot
- 1x Vendor slot
- Basic wooden palisade
- **Footprint:** 5x5 chunk tiles

#### Tier 3: Homestead (Unlocked at Level 25, costs 2000g)
- 1x Small House (full logout safety)
- 4x Storage (80 slots)
- 2x Crafting Station slots
- 2x Vendor slots
- Stone walls, gate
- 1x Basic Defense slot (turret/trap)
- **Footprint:** 8x8 chunk tiles

#### Tier 4: Fortress (Guild only, costs 10000g)
- Guild Hall
- 8x Storage (160 slots, shared)
- 4x Crafting Station slots
- 4x Vendor slots
- Reinforced walls, multiple gates
- 4x Defense slots
- 1x World Tree slot (siege objective)
- **Footprint:** 15x15 chunk tiles

### Base Migration

```gdscript
# When player wants to move north
func migrate_base(player_id: int, target_chunk: Vector2i) -> bool:
    var current_base = get_player_base(player_id)
    if not current_base:
        return false

    # Validate target chunk
    if not is_chunk_available_for_base(target_chunk):
        return false

    # Check biome requirements (can only move to same or higher tier)
    var target_biome = get_biome_tier(target_chunk)
    if target_biome < current_base.biome_tier:
        return false  # Can't move backwards

    # Migration cost (gold + time)
    var cost = calculate_migration_cost(current_base, target_chunk)
    if not player_can_afford(player_id, cost):
        return false

    # Start migration (base is vulnerable during this time!)
    start_base_migration(current_base, target_chunk, migration_duration)
    return true
```

---

## Siege System

### When Bases Become Siegeable

Bases are **protected by default**. Siege vulnerability triggers under specific conditions:

#### Automatic Siege Windows
1. **Offline for 7+ days** - Abandoned bases become raidable
2. **Failed to pay "taxes"** - Weekly gold sink for base maintenance
3. **Declared war** - Guild vs Guild war declaration
4. **World Tree maturity** - Tier 4 bases with mature trees are always contestable

#### Opt-In Siege (PvP Flagging)
- Player can enable "Warlord Mode" for bonus rewards
- Base becomes siegeable 24/7 while flagged
- +50% resource gathering, +25% XP in your chunk

### Siege Mechanics

```gdscript
class_name SiegeManager

enum SiegePhase {
    PREPARATION,  # 30 min - Attackers gather, defenders prepare
    ASSAULT,      # 60 min - Active combat window
    RESOLUTION    # Determine winner, apply consequences
}

# Siege declaration requirements
const MIN_ATTACKERS = 5  # Need party to declare siege
const DECLARATION_COST = 1000  # Gold cost to start siege
const COOLDOWN_AFTER_FAILED_SIEGE = 48 * 60 * 60  # 48 hours

# Win conditions
func check_siege_victory(siege: SiegeInstance) -> SiegeResult:
    # Attackers win if:
    # - World Tree destroyed (Tier 4 only)
    # - All defenders dead and control point held for 5 min
    # - Base core destroyed (lower tiers)

    # Defenders win if:
    # - Timer expires with base intact
    # - All attackers dead/retreated

    # Draw if:
    # - Neither side achieves objective
    pass

# Consequences
func apply_siege_result(siege: SiegeInstance, result: SiegeResult):
    match result:
        SiegeResult.ATTACKER_WIN:
            # Attackers loot percentage of storage
            # Base downgraded one tier
            # 24h protection period starts
        SiegeResult.DEFENDER_WIN:
            # Attackers lose declaration cost
            # Defender gets "Hardened" buff (+defense for 7 days)
            # Cooldown before same attackers can try again
        SiegeResult.DRAW:
            # No major consequences
            # Shorter cooldown
```

### World Trees (Guild Anchors)

World Trees are special structures for Tier 4 (Fortress) bases:

- **Growth time:** 7 real days to mature
- **Benefits while growing:**
  - +10% XP in chunk per growth day
  - Attracts rare resource spawns
  - Visible on world map (prestige)
- **Mature tree benefits:**
  - +25% all stats for guild members in chunk
  - Teleport waypoint for guild
  - Weekly rare material harvest
- **Siege target:**
  - Destroying tree is primary siege objective
  - Tree has massive HP, regenerates slowly
  - If destroyed: 30 day regrowth timer

---

## Chunk Ownership

### Personal Chunks
- Every player can claim ONE chunk as home
- Claim costs gold based on biome tier
- Chunk persists even when player offline (for base)
- Can be shared with guild

### Guild Chunks
- Guilds can claim multiple chunks
- Members contribute to maintenance costs
- Guild leader assigns chunk permissions

### Contested Chunks (PvP Zones)
- Some chunks are permanently contested
- No bases allowed, but rich resources
- FFA PvP enabled
- Rare boss spawns

```gdscript
# Chunk ownership data
class ChunkOwnership:
    var owner_type: OwnerType  # NONE, PLAYER, GUILD, CONTESTED
    var owner_id: int  # player_id or guild_id
    var claimed_at: int  # Unix timestamp
    var maintenance_paid_until: int  # Unix timestamp
    var siege_status: SiegeStatus
    var base_template: BaseTemplate
    var placed_structures: Array[Structure]
```

---

## Implementation Priority

### Phase 1: Foundation (Current + Near Term)
- [x] Chunk-based enemy spawning
- [x] Group system (40 players)
- [x] Campfire ownership mechanics
- [x] Healing staff (support role)
- [x] Quest system framework (tutorial + progression quests)
- [x] PvP duel system (consensual 1v1 combat)
- [x] Wolf enemies with pack behavior
- [ ] Basic base template (Tier 1 Camp)

### Phase 2: Economy
- [ ] Alchemist vendor + potions
- [ ] Jeweler vendor + accessories
- [ ] Material gathering system
- [ ] Player trading

### Phase 3: Base Building
- [ ] Tier 2-3 base templates
- [ ] Placeable crafting stations
- [ ] Storage persistence
- [ ] Base migration system

### Phase 4: PvP & Sieges
- [x] PvP duel system (consensual 1v1) - see docs/PVP_DUEL_SYSTEM.md
- [ ] PvP flagging system (open world)
- [ ] Siege declaration and windows
- [ ] Defense structures
- [ ] World Trees (Tier 4)

### Phase 5: World Expansion
- [ ] Tier 2 biome (Cursed Lands)
- [ ] Dynamic chunk loading based on population
- [ ] Northern progression
- [ ] Guild system integration

---

## Technical Considerations

### Current Systems to Leverage
- **ChunkAwareSpawnManager** - Extend for base placement validation
- **GroupManager** - Extend for guild system
- **Campfire ownership** - Model for all placeable structures
- **NetworkManager RPC patterns** - Base for siege/ownership sync

### New Systems Needed
- **BaseManager** - Handles templates, placement, upgrades
- **VendorProgressManager** - Quest tracking, migration
- **SiegeManager** - Declaration, phases, resolution
- **ChunkOwnershipManager** - Claims, permissions, taxes
- **WorldTreeManager** - Growth, benefits, destruction

### Database Schema Extensions
```gdscript
# Player data additions
{
    "home_chunk": Vector2i,
    "base_template_tier": int,
    "vendor_progress": {
        "blacksmith": 2,
        "alchemist": 1,
        # ...
    },
    "guild_id": String,
    "pvp_flagged": bool
}

# New collections
bases_data = {
    "chunk_key": {
        "owner_id": int,
        "template": String,
        "structures": Array,
        "storage": Array,
        "siege_status": String
    }
}

guilds_data = {
    "guild_id": {
        "name": String,
        "leader_id": int,
        "members": Array,
        "claimed_chunks": Array,
        "world_tree_chunk": Vector2i,
        "treasury": int
    }
}
```

---

## Open Questions

1. **Migration friction** - How much should it cost to move north? Too cheap = no attachment, too expensive = stuck
2. **Siege timing** - Global windows (e.g., weekends only) or per-base scheduling?
3. **Solo vs Guild balance** - Can solo players meaningfully participate in Tier 3-4?
4. **Persistence vs Performance** - How many offline bases can server handle?
5. **New player experience** - How to prevent high-level players griefing spawn area?

---

## References

- Current codebase: `GAME_DOCUMENTATION.md`
- Security considerations: `SECURITY.md`
- Chunk system: `scripts/systems/ChunkAwareSpawnManager.gd`
- Group system: `scripts/systems/GroupManager.gd`
- Campfire ownership: `scripts/systems/Campfire.gd`
