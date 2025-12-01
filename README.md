# Wasteland - Documentation Index

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

## Documentation Files

### Primary Documentation

#### [GAME_DOCUMENTATION.md](GAME_DOCUMENTATION.md) - **Main Game Design Document**
Comprehensive overview of all game systems and mechanics including NotificationManager system.

#### [GAME_BALANCE.md](GAME_BALANCE.md) - **Economy & Progression Balance**
Detailed balance numbers for economy, stats, and progression.

### System Documentation (docs/)

#### [docs/INVENTORY_AND_LOOT.md](docs/INVENTORY_AND_LOOT.md)
Complete guide to inventory management, loot drops, corpse looting, and treasure systems.

#### [docs/LPC_GUIDE.md](docs/LPC_GUIDE.md)
Complete guide to the LPC character system, sprite generation, armor layering, and asset management.

#### [docs/ENEMY_SPAWN_SYSTEM.md](docs/ENEMY_SPAWN_SYSTEM.md)
Complete guide to spawn location generation and enemy spawning (radial patterns, pattern learning, manual/procedural spawning).

#### [docs/PERFORMANCE_GUIDE.md](docs/PERFORMANCE_GUIDE.md)
Performance optimization strategies: node caching, view distance culling, throttled updates, particle reduction.

#### [docs/REFACTOR_HISTORY.md](docs/REFACTOR_HISTORY.md)
Historical documentation of component architecture refactoring (reference only, not integrated).

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
- **4 Zones**: Wasteland → Cursed Lands → Shadow Realm → Castle Approach
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
- See [docs/PERFORMANCE_GUIDE.md](docs/PERFORMANCE_GUIDE.md) for details

### Multiplayer Ready
- **Owner-Only Weakpoints**: Each player sees their own crit windows
- **Server Authority**: All combat validated server-side
- **Anti-Cheat**: Rate limiting, spatial validation, pattern detection
- **Group Scaling**: Dynamic HP/damage scaling based on player count

### Code Architecture
- **22 Autoloads**: Core systems including Constants, CharacterStats (with chain system), InventorySystem, SoundManager, NotificationManager, NetworkManager, DatabaseManager, and more
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

### Chat Admin Commands
Type these in chat (press Enter) when hosting a game:
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
- `scenes/items/pickable_item.tscn` - World items
- `scenes/items/treasure_chest.tscn` - Loot containers

**Scripts**:
- `scripts/player/Player.gd` - Player controller
- `scripts/enemies/Enemy.gd` - Enemy AI and combat
- `scripts/enemies/weakpoint.gd` - Crit window weakpoints
- `scripts/systems/CharacterStats.gd` - Stats, equipment, and chain multiplier system
- `scripts/systems/InventorySystem.gd` - Global inventory
- `scripts/systems/LootSpawnManager.gd` - Enemy loot tables
- `scripts/systems/ItemIconGenerator.gd` - Procedural item icons
- `scripts/systems/DatabaseManager.gd` - Player data persistence
- `scripts/systems/LogManager.gd` - Centralized logging with verbosity levels
- `scripts/systems/SoundManager.gd` - Audio system (music, SFX, tree sounds)
- `scripts/ui/CharacterUI.gd` - Character sheet UI (C key)
- `scripts/ui/InventoryUI.gd` - Inventory window (I/B key)
- `scripts/ui/ChatUI.gd` - Multiplayer chat with admin commands
- `scripts/ui/ShopUI.gd` - Vendor shop interface
- `scripts/ui/GroupUI.gd` - Party frames and invite popup
- `scripts/ui/GameMenu.gd` - In-game ESC menu

**Data**:
- `prop_placements.json` - 2,500 prop positions
- `path_markers.json` - 25 path marker positions
- `data/shop_weapons.json` - Weapon definitions
- `data/shop_armor.json` - Armor definitions

**Assets**:
- `assets/environment/baked_world_background.png` - Pre-rendered world
- `assets/sounds/combat/` - Combat sound effects
- `assets/sprites/` - Character and enemy sprites

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
- Roaming enemies along path
- Boss fight (Level 33 Necromancer King)
- Healing system (friendly targeting)

### Planned Features
- PvP combat
- Quest system
- Crafting system
- Additional zones/bosses

---

## Support & Contributing

### Reporting Issues
- Check existing documentation first
- Provide reproduction steps
- Include error messages and logs
- Specify Godot version

### Development Workflow
1. Read [DEVELOPMENT.md](DEVELOPMENT.md) for code standards
2. Create feature branch from `master`
3. Follow existing code conventions
4. Test thoroughly before committing
5. Update documentation for new features
6. Create pull request with detailed description

### Contact
- Project Repository: [Add GitHub URL]
- Discord: [Add Discord invite]
- Email: [Add contact email]

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

This documentation was last updated: 2025-12-01
