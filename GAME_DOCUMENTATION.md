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

### Enemy Spawn Points (15 total)
Enemies spawn along the journey from campfire to castle:
```
Positions range from (1200, -350) to (7200, -80)
Progressive difficulty LEFT→RIGHT
Spread across vertical range for variety
```

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
