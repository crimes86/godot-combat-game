# Dreadland - Documentation Index

A fast-paced action RPG featuring a unique critical hit weakpoint system and chain multipliers.

## Quick Start

1. **Install Godot 4.x** (tested with Godot 4.2+)
2. **Clone repository** and open in Godot
3. **Run game**: Press F5 or click Play button
4. **Controls**: WASD to move, click to attack, E to interact

## Core Game Loop

- Journey through 4 zones from Campfire (start) to Castle (boss)
- Fight enemies and build chain multipliers
- Trigger critical hit windows with weakpoint clicking
- Level up, buy gear, and convert ruins to safe zones
- Defeat the Level 33 Necromancer King

---

## Developer Onboarding

### First Day Setup

1. **Install Godot 4.2+** from [godotengine.org](https://godotengine.org)
2. **Clone this repo** and open `project.godot` in Godot
3. **Press F5** to run the game and verify it works
4. **Press F3** in-game for debug overlay (shows chunk info, enemy counts, FPS)

### Architecture Overview

```
+------------------+     +------------------+     +------------------+
|   28 Autoloads   |     |   Game World     |     |    UI Layer      |
|  (Global State)  |---->|  (Scene Tree)    |---->|  (CanvasLayer)   |
+------------------+     +------------------+     +------------------+
        |                        |                        |
        v                        v                        v
  CharacterStats           Player.gd              InventoryUI.gd
  InventorySystem          Enemy.gd               CharacterUI.gd
  NetworkManager           ChunkBasedPropSystem   ShopUI.gd
  DatabaseManager          ChunkAwareSpawnManager ChatUI.gd
  SoundManager            Campfire.gd             GroupUI.gd
  DuelManager             PlayerCorpse.gd         GameMenu.gd
```

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `scripts/systems/` | Core autoloads and managers |
| `scripts/player/` | Player character scripts |
| `scripts/enemies/` | Enemy AI and behaviors |
| `scripts/ui/` | All UI components |
| `scripts/networking/` | Multiplayer sync |
| `scenes/` | Godot scene files (.tscn) |
| `assets/` | Sprites, audio, icons |
| `data/` | JSON configs (weapons, armor, props) |

### Common Tasks

**Add a new weapon:**
1. Add entry to `data/shop_weapons.json`
2. Add sprites to `assets/equipment/weapons/<type>/`
3. Test in Armory or Shop

**Add a new enemy:**
1. Duplicate `scenes/enemies/enemy.tscn`
2. Modify `scripts/enemies/Enemy.gd` or create subclass
3. Register in `ChunkAwareSpawnManager.gd`

**Debug performance:**
1. Press F3 for in-game overlay
2. Check `docs/PERFORMANCE.md` for profiling tips
3. Use Godot's built-in profiler (Debugger -> Profiler)

### Code Conventions

- **Autoloads** are accessed globally: `CharacterStats.level`, `InventorySystem.add_item()`
- **Signals** for decoupled communication (check `_ready()` for signal connections)
- **snake_case** for functions/variables, **PascalCase** for classes
- **GDScript static typing** preferred: `func foo(bar: int) -> String:`

### Reading Order for New Developers

1. This README (you're here!)
2. `GAME_DOCUMENTATION.md` - Full game systems overview
3. `docs/CHUNK_AND_SPAWNING.md` - How the world works
4. `docs/PERFORMANCE.md` - F3 debug and optimization
5. `.claude/CLAUDE.md` - Asset structure guidelines

---

## Documentation Files

### Primary Documentation

| Document | Description |
|----------|-------------|
| [GAME_DOCUMENTATION.md](GAME_DOCUMENTATION.md) | Main game design document - all systems overview |
| [GAME_BALANCE.md](GAME_BALANCE.md) | Economy, stats, and progression balance |
| [TODO.md](TODO.md) | Task tracking and feature status |

### Technical Documentation (docs/)

| Document | Description |
|----------|-------------|
| [docs/CHUNK_AND_SPAWNING.md](docs/CHUNK_AND_SPAWNING.md) | Chunk system, prop generation, enemy spawning, multiplayer sync |
| [docs/COMBAT_SYSTEMS.md](docs/COMBAT_SYSTEMS.md) | PvP duels, player corpse system, death mechanics |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | F3 debug, optimization, profiling, node management |
| [docs/INVENTORY_AND_LOOT.md](docs/INVENTORY_AND_LOOT.md) | Inventory, loot drops, treasure systems |
| [docs/LPC_GUIDE.md](docs/LPC_GUIDE.md) | LPC sprites, armor layering, asset generation |
| [docs/FORGE_AND_MANTLE.md](docs/FORGE_AND_MANTLE.md) | Mantle integration, forge system, Armory UI |
| [docs/SERVER_ARCHITECTURE.md](docs/SERVER_ARCHITECTURE.md) | Multiplayer networking (host-as-server, future dedicated) |
| [docs/SHARD_SYSTEM.md](docs/SHARD_SYSTEM.md) | Multi-server sharding for horizontal scaling |
| [docs/DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | Game world database (SQLite) - player data, persistence |
| [docs/ITCH_RELEASE_GUIDE.md](docs/ITCH_RELEASE_GUIDE.md) | Export settings, itch.io publishing |
| [docs/FUTURE_SPECS.md](docs/FUTURE_SPECS.md) | Settlement, class, vendor systems (NOT YET IMPLEMENTED) |

---

## Key Features

### Combat System
- **Click-based Combat**: Point and click to attack enemies
- **Critical Hit System**: Random crits based on LUCK stat
- **Weakpoint Windows**: 4-second windows with 1-3 clickable weakpoints
- **Chain Multipliers**: Build up to 10x damage with consecutive crit completions
- **Overdrive Mode**: Maximum chain grants 2.0x total damage multiplier

### Progression
- **Level Cap**: 30 (stats stop at level 25)
- **4 Zones**: dreadland → Cursed Lands → Shadow Realm → Castle Approach
- **3 Ruins**: Convertible checkpoints with vendors
- **Boss Fight**: Level 33 Necromancer King at castle

### World Features
- **Massive World**: 12,000x5,000 pixel explorable area
- **2,500 Props**: Trees, rocks, skulls, bones dynamically loaded
- **Winding Path**: 19 waypoints with 25 path markers
- **Lava Pools**: Environmental hazards with animated effects
- **Harvestable Trees**: Chop for wood, sell for gold

### Economy
- **Vendor System**: Blacksmith sells weapons and armor
- **Currency**: Gold from enemies, chests, and resource gathering
- **Loot Drops**: Randomized drops with rarity tiers
- **Treasure Chests**: Zone-specific loot generation

### Visual Polish
- **LPC Character Sprites**: Gender selection (male/female)
- **Animated Weakpoints**: Progressive brightening, glow effects
- **Particle Effects**: Combat hits, weakpoint destruction, explosions
- **Combat Text**: Floating damage numbers with positioning
- **Shadows**: Proper oval shadows for trees and props

---

## Technical Highlights

### Performance Optimization
- **World Baking**: Pre-rendered background texture (1-5 minute bake, <100ms load)
- **Dynamic Loading**: Props loaded from JSON at runtime
- **Node Caching**: Campfire animations use cached references (no searching per frame)
- **View Distance Culling**: Enemies invisible beyond 1400px (saves rendering cost)
- **Throttled Updates**: Enemy checks run at 5fps instead of 60fps for non-critical systems
- **Particle Reduction**: Optimized particle counts (40% reduction)
- **Camera Zoom Limit**: 0.75x-2.0x zoom range (prevents map reveal, maintains performance)
- **Target**: 60 FPS on mid-range laptops ✅
- See [docs/PERFORMANCE.md](docs/PERFORMANCE.md) for details

### Multiplayer Ready
- **Owner-Only Weakpoints**: Each player sees their own crit windows
- **Server Authority**: All combat validated server-side
- **Anti-Cheat**: Rate limiting, spatial validation, pattern detection
- **Group Scaling**: Dynamic HP/damage scaling based on player count

### Code Architecture
- **28 Autoloads**: Core systems including Constants, CharacterStats, InventorySystem, SoundManager, NetworkManager, DatabaseManager, DuelManager, MantleAuth, and more
- **Signal-Based**: Clean communication between systems
- **State Machines**: Enemy AI, ruins conversion, chain management
- **Modular Design**: Easy to extend and maintain
- **Global Notifications**: Item gain/loss notifications with rarity colors and cascade animations
- **Procedural Icons**: ItemIconGenerator creates icons for weapons, armor, tools, and materials
- **Centralized Logging**: LogManager with toggleable verbosity levels

---

## Quick Reference

### Controls
- **WASD**: Move
- **Mouse**: Aim
- **Left Click**: Attack
- **Space**: Dodge roll
- **Mouse Wheel**: Zoom camera
- **C**: Character sheet
- **I / B**: Inventory
- **F**: Interact / Loot
- **Enter**: Chat
- **ESC**: Close UI windows
- **F1**: Bug report (submit feedback)
- **F2**: Admin panel (host only)
- **F3**: Debug overlay (dev builds only)
- **F4**: Advance time 1 hour (dev builds only)
- **ESC**: In-game menu (Settings, Credits, Disconnect)

### Chat Commands
Type these in chat (press Enter):
- **/duel \<PlayerName\>**: Challenge player to a 1v1 duel

### Chat Admin Commands (Host Only)
- **/help**: Show all admin commands
- **/accounts**: List all registered accounts
- **/select \<username\>**: Select account to edit
- **/info**: Show selected account details
- **/setpos \<x\> \<y\>**: Set player position
- **/resetpos**: Reset to campfire spawn
- **/setgold \<amount\>**: Set gold amount
- **/setlevel \<1-30\>**: Set player level
- **/setstats \<str\> \<agi\> \<vit\> \<luck\>**: Set base stats
- **/ban** / **/unban**: Toggle account ban
- **/forceoffline**: Fix stuck login state
- **/delete**: Delete selected account

### File Locations

**Scenes**:
- `scenes/game_world.tscn` - Main game scene
- `scenes/player/player.tscn` - Player character
- `scenes/enemies/enemy.tscn` - Skeleton enemy
- `scenes/ui/shop_ui.tscn` - Vendor shop interface
- `scenes/npcs/vendor.tscn` - Blacksmith NPC

**Scripts**:
- `scripts/player/Player.gd` - Player controller
- `scripts/enemies/Enemy.gd` - Enemy AI and combat
- `scripts/enemies/weakpoint.gd` - Crit window weakpoints
- `scripts/items/PickableItem.gd` - World items (instantiated programmatically)
- `scripts/items/TreasureChest.gd` - Loot containers (instantiated programmatically)
- `scripts/systems/CharacterStats.gd` - Stats, equipment, and chain multiplier system
- `scripts/systems/InventorySystem.gd` - Global inventory
- `scripts/systems/LootSpawnManager.gd` - Enemy loot tables
- `scripts/systems/ItemIconGenerator.gd` - Procedural item icons
- `scripts/systems/DatabaseManager.gd` - Player data persistence
- `scripts/systems/LogManager.gd` - Centralized logging with verbosity levels
- `scripts/systems/sound_manager.gd` - Audio system (music, SFX, tree sounds)
- `scripts/ui/CharacterUI.gd` - Character sheet UI (C key)
- `scripts/ui/InventoryUI.gd` - Inventory window (I/B key)
- `scripts/ui/ChatUI.gd` - Multiplayer chat with admin commands
- `scripts/ui/ShopUI.gd` - Vendor shop interface
- `scripts/ui/GroupUI.gd` - Party frames and invite popup
- `scripts/ui/GameMenu.gd` - In-game ESC menu

**Data**:
- `data/prop_placements.json` - Prop positions for world generation
- `data/path_markers.json` - Path marker positions
- `data/shop_weapons.json` - Weapon definitions
- `data/shop_armor.json` - Armor definitions

**Assets**:
- `assets/audio/sfx/combat/` - Combat sound effects
- `assets/characters/` - Character and enemy sprites

---

## Development Status

### Implemented Features
- Core combat with click-based attacking
- Critical hit system with weakpoint windows
- Chain multiplier system (0-10x)
- Dodge roll with i-frames
- 4-zone world with winding path
- Ruins 1 with 8 guardians
- Vendor shop with weapons/armor
- Inventory system with loot drops and procedural icons
- Armor equipping system (6 slots: head, chest, arms, hands, legs, feet)
- Tool equipping (axe, pickaxe)
- Global notification system (item gain/loss with rarity colors)
- Environmental hazards (lava pools)
- Resource gathering (harvestable trees and rocks)
- Campfire with fuel system (bone embers, dry logs)
- Training dummy for practice
- Character sheet UI with paperdoll equipment display
- Separate inventory UI with drag-drop support
- Multiplayer chat system with admin commands
- Player authentication and database persistence
- Gender selection
- Sound system with background music playlist
- Performance optimizations (60fps target on laptops)

### In Progress
- Ruins 2 & 3 implementation
- Boss fight (Level 33 Necromancer King)

### Recently Added
- **Player Corpse System** - EverQuest-style death with corpse loot recovery
- **PvP Duel System** - Consensual 1v1 duels with `/duel` command
- **Wolf Enemies** - Pack-based AI with howling and pursuit behavior
- **Group/Party System** - Up to 40 players, shared XP, party frames
- **Quest System** - Tutorial and progression quests with tracker UI
- **Harvest Tools** - Axe and pickaxe for gathering resources

### Planned Features
- Base building system
- Settlement sieges
- Crafting system
- Additional biomes (Cursed Lands, Shadow Realm)

---

## Support & Contributing

### Reporting Issues
- Check existing documentation first
- Provide reproduction steps
- Include error messages and logs
- Specify Godot version
- Use F1 in-game to submit bug reports

### Development Workflow
1. Read `Developer Onboarding` section above
2. Create feature branch from `master`
3. Follow code conventions (snake_case, static typing)
4. Test thoroughly before committing
5. Update documentation for new features
6. Check `.claude/CLAUDE.md` for asset guidelines

---

## License

[Add license information]

---

## Credits

### Development
- Game Design & Programming: [Your Name]
- Art: LPC (Liberated Pixel Cup) community assets
- Sound Effects: [Credit sound sources]

### Special Thanks
- Godot Engine community
- LPC sprite contributors
- Playtesters and early supporters

---

This documentation was last updated: 2025-12-08
