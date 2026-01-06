# 1620 Integration Spec: River & Trapper Camp Expansion

## Overview

Integrate 1620 gameplay systems into Ashbane as a seamless northern expansion of the Trading Hub. This validates core 1620 mechanics (trapping, skinning, crafting, keelboats) in 2D before potential 3D development.

**Philosophy**: These are Ashbane features first. They happen to also be the foundation for 1620. No over-architecture - build good expansion content.

---

## Design Decisions (Confirmed)

### Tier System Integration
Crafted fur gear is **Tier 2** equipment:
- Requires Tier 1 base piece + trapped materials
- Example: Copper Plate Helm (T1) + 2 Beaver Pelts → Fur-Lined Helm (T2)
- Fur items add warmth/layering stats on top of base armor

### Trap Ownership & Stealing
- Traps are **stealable** by other players
- Stealing a trap (or its contents) marks player as **"Rogue" faction**
- Rogue status has consequences (NPCs hostile, bounty system, etc.)
- Creates risk/reward tension in multiplayer

### Keelboat Ownership
- Boats are **locked to owner** by default
- If owner **abandons boat** (logout while boat is deployed, or explicit abandon), boat becomes stealable
- Stolen boats can be claimed by new owner

### Wildlife
- **Visible animals** roam the forest (beaver, fox, rabbit, wolf)
- Animals can be hunted directly OR caught in traps
- Traps have higher success rate but require setup/checking
- Dense forest should feel alive with movement

### Visual Direction
- Missouri River basin aesthetic
- Tree types appropriate to region (will refine based on accuracy)
- Leaving cave → entering vast forest → river should feel like wilderness transition

---

## Zone Layout

```
                    NORTH (negative Y)
                         |
    +-----------------------------------------+
    |              RIVER ZONE                 |  Y: -14000 to -11000
    |   [Keelboat Dock]    [Beaver Dams]      |  - Wide flowing river
    |   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~     |  - Current/navigation
    |   ~~~~~~~~~~~~~ RIVER ~~~~~~~~~~~~~     |  - Beaver trap spots
    |   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~     |  - Future: extends west (Missouri)
    +-----------------------------------------+
    |           TRAPPER CAMP                  |  Y: -11000 to -9500
    |   [Skinning Station] [Crafting Tent]    |  - Revenant-style camp
    |   [Campfire]  [Pelts Drying]  [NPCs]    |  - Tutorial NPCs
    |   [Keelboat Workshop]                   |  - Learn trapping/skinning
    +-----------------------------------------+
    |              FOREST ZONE                |  Y: -9500 to -5500
    |   Dense trees, wildlife, hunting        |  - Transition biome
    |   Small game (rabbits, foxes)           |  - Hunting grounds
    |   Wolf packs near river                 |  - Danger increases north
    +-----------------------------------------+
    |          EXISTING GRASS AREA            |  Y: -5500 to -2800
    |   (Current Trading Hub north zone)      |  - Already exists
    +-----------------------------------------+
    |          CLIFF / CAVE MOUTH             |  Y: -2800 to 0
    |   (Existing hub entrance)               |  - Forge, Blacksmith
    +-----------------------------------------+
    |              CAVE SYSTEM                |  Y: 0 to 7000+
    |   (Existing tunnels to Zone 1)          |  - East/West exits
    +-----------------------------------------+
                         |
                    SOUTH (positive Y)
```

**Width**: Same as existing hub (~16,000 units, -8000 to 8000 on X axis)

---

## Phase 1: River & Basic Environment

### 1.1 River Water Body
- **Visual**: Animated water shader (reuse/adapt water_trough.gdshader)
- **Width**: Full scene width (-8000 to 8000)
- **Depth**: ~3000 units (Y: -14000 to -11000)
- **Features**:
  - Gentle current flowing east (visual only initially)
  - Shoreline with rocks, reeds, mud banks
  - 3-4 beaver dam locations (trap placement points)
  - Keelboat dock on south shore (player side)

### 1.2 Forest Biome
- **Density**: Denser than Zone 1, but passable paths
- **Tree types**: Pine/evergreen sprites (different from Zone 1 deciduous)
- **Ground**: Darker earth tones, fallen leaves, moss
- **Wildlife spawn points** (for hunting system)

### 1.3 Trapper Camp Layout (Revenant-inspired)
Reference: Opening scene of The Revenant - frontier fur trading outpost

**Core structures:**
- Large central campfire (gathering point, warmth mechanic placeholder)
- Skinning station (log with hooks, blood stains)
- Pelt drying racks (visual progression of pelts curing)
- Crafting tent (leather working, clothing)
- Keelboat workshop (boat building station)
- Storage cache (player stash in camp)

**NPCs:**
- **Bourgeois (Camp Leader)**: Quest giver, sells trapping supplies
- **Voyageur (Trapper)**: Teaches trapping mechanics, sells traps
- **Engagé (Worker)**: Teaches skinning/crafting
- **Keelboat Captain**: Teaches boat building, river navigation

**Atmosphere:**
- Smoke from fires
- Ambient audio: river, birds, distant wolves
- Drying pelts sway slightly
- NPCs doing idle animations (sharpening knives, tending fire)

---

## Phase 2: Trapping System

### 2.1 Trap Types

| Trap | Target | Materials | Set Time | Check Interval |
|------|--------|-----------|----------|----------------|
| Leg-hold Trap | Beaver, Fox | 2 Iron, 1 Rope | 2s | 5 min game time |
| Snare | Rabbit, Fox | 1 Rope, 1 Stick | 1s | 3 min game time |
| Deadfall | Beaver, Rabbit | 3 Logs, 1 Rope | 3s | 5 min game time |

### 2.2 Trap Mechanics

**Placing a trap:**
1. Player has trap in inventory (crafted or bought)
2. Approach valid trap location (beaver dam for beaver, forest for small game)
3. Hold E to place trap (progress circle like tree chopping)
4. Trap becomes world object with timer

**Trap states:**
- `EMPTY` - Waiting for prey
- `TRIGGERED` - Caught something (sparkle indicator)
- `SPRUNG` - Triggered but empty (animal escaped, needs reset)
- `DAMAGED` - Needs repair before reuse

**Checking traps:**
1. Approach placed trap
2. Press E to check
3. If triggered: receive carcass item, trap goes to EMPTY or DAMAGED
4. If sprung: can reset (hold E) or collect trap

**Catch rates** (per check):
- Beaver at beaver dam: 40%
- Fox in forest: 25%
- Rabbit in forest: 50%

### 2.3 Trap Placement Nodes
- Pre-defined "trap spots" in scene (like loot spawn points)
- Visual indicator when player has trap equipped and is near valid spot
- Only one trap per spot
- Spots respawn animals on server tick

---

## Phase 3: Skinning System

### 3.1 Carcass Items
When animal is trapped or killed, player gets carcass:
- `beaver_carcass`
- `fox_carcass`
- `rabbit_carcass`
- `wolf_carcass` (from hunting, not trapping)

### 3.2 Skinning Station
Located in trapper camp - required for skinning (can't skin in field initially)

**Skinning process:**
1. Approach skinning station with carcass in inventory
2. Open skinning UI (like forge UI pattern)
3. Select carcass to skin
4. Hold E to skin (progress bar, 3-5 seconds)
5. Receive: pelt + meat + (chance) bone/sinew

**Yield table:**

| Carcass | Primary Pelt | Meat | Bonus |
|---------|--------------|------|-------|
| Beaver | beaver_pelt | 2 game_meat | 10% beaver_tail |
| Fox | fox_pelt | 1 game_meat | 15% fox_tail |
| Rabbit | rabbit_pelt | 1 game_meat | - |
| Wolf | wolf_pelt | 3 game_meat | 20% wolf_fang |

### 3.3 Pelt Quality (stretch goal)
Based on trap type and player skill:
- Poor (50%): Base value
- Good (35%): 1.5x value
- Pristine (15%): 2x value

---

## Phase 4: Crafting System

### 4.1 Crafting Station
Tent in trapper camp with crafting UI

**Crafting categories:**
- Clothing (from pelts)
- Traps (from materials)
- Boat parts (for keelboat)
- Tools (stretch goal)

### 4.2 Initial Recipes

**Clothing (equippable armor/cosmetic):**

| Recipe | Materials | Slot | Stats |
|--------|-----------|------|-------|
| Beaver Hat | 2 beaver_pelt | Head | +5 cold resist (placeholder) |
| Fox Fur Cloak | 3 fox_pelt | Cape | +10 cold resist |
| Rabbit Fur Gloves | 2 rabbit_pelt | Hands | +2 cold resist |
| Wolf Pelt Coat | 2 wolf_pelt, 1 leather | Chest | +15 cold resist, +5 armor |

**Traps:**

| Recipe | Materials | Output |
|--------|-----------|--------|
| Leg-hold Trap | 2 iron_ingot, 1 rope | leg_hold_trap |
| Snare | 1 rope, 2 wood | snare_trap |
| Deadfall | 4 wood, 1 rope | deadfall_trap |

**Keelboat parts:**

| Recipe | Materials | Output |
|--------|-----------|--------|
| Hull Planks | 10 wood | boat_hull_section (need 4) |
| Keelboat Frame | 20 wood, 5 rope | boat_frame |
| Oar | 3 wood | boat_oar (need 2) |
| Sail | 5 cloth, 3 rope | boat_sail (optional) |

### 4.3 Crafting UI Pattern
Reuse Forge UI pattern:
- Left panel: Recipe list (categorized)
- Center: Selected recipe details + requirements
- Right: Player inventory
- Bottom: Craft button + progress

---

## Phase 5: Keelboat System

### 5.1 Boat Building
At Keelboat Workshop in camp:

**Requirements to build keelboat:**
- 4x boat_hull_section
- 1x boat_frame
- 2x boat_oar
- (Optional) 1x boat_sail

**Building process:**
1. Interact with workshop
2. Deposit parts into build slots
3. When all parts present, hold E to assemble (10s)
4. Keelboat appears at nearby dock

### 5.2 Keelboat Properties
- **Capacity**: Player + 2 passengers (or cargo)
- **Speed**: 1.5x walking speed with current, 0.75x against
- **Durability**: Takes damage from rocks, needs repair
- **Storage**: 10 inventory slots for pelts/cargo

### 5.3 River Navigation (Minigame)

**Controls:**
- WASD or arrow keys for rowing direction
- Space to drop anchor (stop)
- E to interact (set trap, fish, dock)

**River features:**
- Current pushes boat east
- Rocks/obstacles to avoid
- Beaver dam locations (trap spots accessible from boat)
- Fish spawns (for fishing minigame)
- Fog of war on unexplored river sections

**Docking:**
- Multiple dock points along river
- Press E near dock to disembark
- Boat stays at dock until retrieved

### 5.4 Fishing (from boat)
While anchored:
1. Press E to cast line
2. Wait for bite (visual/audio cue)
3. Timing minigame (press E at right moment)
4. Catch fish (trout, bass, catfish)

---

## Phase 6: Integration Points

### 6.1 Existing Systems to Leverage

| System | Use Case |
|--------|----------|
| InventorySystem | Store traps, pelts, carcasses, boat parts |
| EquipmentSystem | Equip crafted clothing |
| HarvestableTree pattern | Base for skinning station interaction |
| Vendor/Shop UI | NPCs sell supplies, buy pelts |
| ForgeItemDB | Define new items (pelts, traps, clothing) |
| SoundManager | Trap sounds, skinning, crafting, river ambience |

### 6.2 New Items to Add (items.json)

**Raw materials:**
- `beaver_carcass`, `fox_carcass`, `rabbit_carcass`, `wolf_carcass`
- `beaver_pelt`, `fox_pelt`, `rabbit_pelt`, `wolf_pelt`
- `game_meat`
- `beaver_tail`, `fox_tail`, `wolf_fang`
- `rope` (craftable from plant fiber or buyable)

**Traps:**
- `leg_hold_trap`, `snare_trap`, `deadfall_trap`

**Clothing:**
- `beaver_hat`, `fox_cloak`, `rabbit_gloves`, `wolf_coat`

**Boat parts:**
- `boat_hull_section`, `boat_frame`, `boat_oar`, `boat_sail`

**Fish:**
- `trout`, `bass`, `catfish`

### 6.3 New Scripts Structure

```
scripts/
├── 1620/
│   ├── TrapSystem.gd           # Global trap manager
│   ├── Trap.gd                 # Individual trap node
│   ├── TrapSpot.gd             # Valid placement location
│   ├── SkinningStation.gd      # Skinning interaction
│   ├── CraftingStation.gd      # Crafting tent
│   ├── Keelboat.gd             # Boat controller
│   ├── KeelboatWorkshop.gd     # Boat building
│   ├── RiverNavigation.gd      # River current/obstacles
│   └── FishingMinigame.gd      # Fishing mechanics
└── ...
```

### 6.4 Scene Structure

```
scenes/
├── trading_hub/
│   ├── TradingHub.tscn         # Expanded with forest/river zones
│   ├── TrapperCamp.tscn        # Instanced sub-scene
│   ├── RiverZone.tscn          # Water + docks + obstacles
│   └── ForestZone.tscn         # Trees + wildlife spawns
├── 1620/
│   ├── traps/
│   │   ├── LegHoldTrap.tscn
│   │   ├── Snare.tscn
│   │   └── Deadfall.tscn
│   ├── stations/
│   │   ├── SkinningStation.tscn
│   │   ├── CraftingStation.tscn
│   │   └── KeelboatWorkshop.tscn
│   ├── Keelboat.tscn
│   └── TrapSpot.tscn
└── ...
```

---

## Implementation Order

### Milestone 1: Environment (Visual Foundation)
1. Extend Trading Hub scene north with forest zone
2. Add river water body with basic shader
3. Create trapper camp layout (static props)
4. Add forest trees (reuse HarvestableTree visually)

### Milestone 2: Trapping Core
1. Create Trap item types in items.json
2. Implement TrapSpot nodes (placement locations)
3. Build Trap.gd with state machine
4. Add trap placement/checking interaction
5. Wire up to inventory system

### Milestone 3: Skinning & Pelts
1. Add carcass/pelt items to items.json
2. Create SkinningStation scene + script
3. Implement skinning UI (simplified forge pattern)
4. Add pelt to vendor sell lists

### Milestone 4: Basic Crafting
1. Create CraftingStation scene
2. Implement crafting UI
3. Add clothing recipes
4. Add trap recipes
5. Wire up to equipment system

### Milestone 5: Keelboat Basics
1. Create Keelboat scene (player-controlled vehicle)
2. Implement river water as navigable area
3. Add dock interactions
4. Basic boat movement (no current yet)

### Milestone 6: River Polish
1. Add current mechanics
2. Add obstacles (rocks, logs)
3. Implement fishing minigame
4. Add boat durability/repair

### Milestone 7: NPCs & Economy
1. Add trapper camp NPCs
2. Create pelt economy (buy/sell prices)
3. Add tutorial quests for each system
4. Balance catch rates, craft times, prices

---

## Success Metrics

1. **Player can complete trapping loop**: Buy trap → Place trap → Check trap → Get carcass → Skin → Sell pelt
2. **Player can craft clothing**: Gather pelts → Craft item → Equip
3. **Player can build and use keelboat**: Gather materials → Build boat → Navigate river
4. **Systems feel like natural Ashbane expansion**, not a separate game bolted on

---

## Open Questions

1. **Cold/warmth mechanics**: Add now or defer? (Currently just placeholder stats)
2. **Multiplayer traps**: Can other players steal from your traps? See your traps?
3. **Boat permissions**: Can anyone use a player's boat? Theft possible?
4. **River expansion**: When to add "next zone" via river travel?
5. **Animal AI**: Should trapped animals have corpse state like enemies, or instant despawn?

---

## Art Assets Needed

### Environment
- [ ] Pine/evergreen tree sprites (different from Zone 1)
- [ ] River water tileset or polygon + shader
- [ ] Beaver dam sprite
- [ ] Mud bank / shoreline tiles
- [ ] Camp structures (tent, skinning log, drying rack, workshop)

### Items
- [ ] Trap icons (leg-hold, snare, deadfall)
- [ ] Pelt icons (beaver, fox, rabbit, wolf)
- [ ] Carcass icons
- [ ] Boat part icons
- [ ] Clothing sprites (LPC format for equippable)

### Characters
- [ ] NPC sprites (Bourgeois, Voyageur, Engagé, Captain)
- [ ] Beaver sprite (for traps/dams)
- [ ] Fox, Rabbit sprites (if visible in traps)

---

*Document created: January 2026*
*Based on 1620_GDD.md and existing Ashbane systems*
