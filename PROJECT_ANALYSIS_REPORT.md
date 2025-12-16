# Godot 4 Project Analysis Report
## Dreadland - Comprehensive System Map & Refactoring Opportunities

**Generated:** Phase A Analysis (No File Edits)
**Project Size:** ~100k LOC
**Godot Version:** 4.5

---

## 1. ENTRY POINTS

### Main Scene
- **Entry Point:** `res://scenes/ui/MainMenu.tscn` (configured in `project.godot`)
- **Boot Flow:**
  1. MainMenu.tscn loads → `scripts/ui/MainMenu.gd`
  2. User authenticates (MantleAuth) or plays as guest
  3. Host/Join game → NetworkManager creates/joins server
  4. Loads `main.tscn` → Contains GameWorld, LevelUI, GameMenu
  5. GameWorld spawns players and initializes world

### Autoloads / Singletons (28 total)

**Core Systems:**
- `ServerRunner` - Server hosting utilities
- `Constants` - Game constants and configuration
- `LogManager` - Centralized logging with verbosity levels
- `GameInput` - Input handling and UI state checks

**Game State:**
- `CharacterStats` - Player progression, stats, equipment, chain system
- `InventorySystem` - Inventory management (100 slots, tools)
- `DatabaseManager` - Player persistence (JSON-based, shard support)
- `TimeManager` - Game time tracking

**Combat & Enemies:**
- `LootSpawnManager` - Enemy loot tables
- `EnemyPoolManager` - Enemy pooling/reuse
- `WeaponStatsTracker` - Weapon usage statistics
- `WeaponSkillManager` - Weapon skill progression

**Networking:**
- `NetworkManager` - Core multiplayer (ENet, host-as-server model)
- `NetworkEnemyManager` - Enemy sync (10Hz position, server-authoritative)

**UI Systems:**
- `UITheme` - Theme management
- `NotificationManager` - Item gain/loss notifications
- `InteractionManager` - World interaction prompts
- `AccountAdmin` - Admin panel
- `GroupUI` - Party frames
- `QuestTrackerUI` - Quest display
- `BugReportUI` - Bug reporting
- `ItemInspectionUI` - Item detail view
- `RecentlyAdvertisedUI` - Trading hub UI
- `TradeWindowUI` - Trading interface

**Audio:**
- `SoundManager` - SFX, music, procedural sound generation

**Specialized Systems:**
- `CursorManager` - Cursor customization
- `ItemIconGenerator` - Procedural item icons
- `GroupManager` - Party system
- `TutorialManager` - Tutorial flow
- `QuestManager` - Quest system
- `DuelManager` - PvP dueling
- `MobileInput` - Mobile controls
- `MantleAuth` - Authentication (OAuth, badges)
- `MantleCosmetics` - Cosmetic system
- `ForgeItemDB` - Forged item database
- `ForgeItemManager` - Forged item management
- `ForgeVisualEffects` - Forge VFX
- `TradingManager` - Trading system
- `TradingHubManager` - Trading hub management
- `WorldTreeManager` - World tree progression
- `GlobalDebugOverlay` - Debug UI

---

## 2. SYSTEM MAP

### Player System
**Core Files:**
- `scripts/player/Player.gd` (~4,946 lines) - Main player controller
- `scripts/player/PlayerCombat.gd` (~443 lines) - Combat subsystem (RefCounted)
- `scripts/player/PlayerMovement.gd` - Movement subsystem (RefCounted)

**Key Features:**
- CharacterBody2D-based movement
- Cone-based melee attacks
- Ranged weapons (guns, bows, staffs)
- Dash with i-frames
- Passive healing (out-of-combat regen)
- PvP duel system integration
- LPC sprite system for appearance
- Health, damage, stats synced from CharacterStats

**Dependencies:**
- CharacterStats (equipment, stats)
- NetworkManager (multiplayer sync)
- SoundManager (audio feedback)
- AttackFeedbackSystem (visual feedback)

### Combat System
**Core Files:**
- `scripts/player/PlayerCombat.gd` - Player combat logic
- `scripts/enemies/Enemy.gd` (~1,960 lines) - Enemy entity
- `scripts/enemies/EnemyAI.gd` - Enemy AI behavior
- `scripts/systems/crit_system.gd` - Critical hit system
- `scripts/systems/crit_window_manager.gd` - Crit window timing
- `scripts/systems/attack_feedback_system.gd` - Damage numbers, effects
- `scripts/systems/screen_shake.gd` - Screen shake effects

**Key Features:**
- Cone-based melee attacks
- Weakpoint system (uncapped attack speed)
- Crit window system (timing-based)
- Chain multiplier (0-10x damage)
- Overdrive mode
- Weapon-specific behaviors (burst fire, healing staff)
- PvP damage validation
- Server-authoritative damage in multiplayer

### Enemies System
**Core Files:**
- `scripts/enemies/Enemy.gd` - Base enemy class
- `scripts/enemies/EnemyAI.gd` - AI behavior
- `scripts/enemies/Wolf.gd` - Wolf enemy variant
- `scripts/enemies/hitflash.gd` - Hit visual feedback
- `scripts/enemies/weakpoint.gd` - Weakpoint spawns
- `scripts/networking/NetworkEnemyManager.gd` - Multiplayer sync

**Key Features:**
- Level-based scaling
- LOD system (distance-based detail)
- Weakpoint spawning
- Crit window generation
- Loot drops on death
- XP/gold rewards
- Server-authoritative spawning and sync

### UI System
**Core Files:**
- `scripts/ui/MainMenu.gd` (~2,437 lines) - Main menu, authentication
- `scripts/ui/CharacterUI.gd` - Character sheet (C key)
- `scripts/ui/InventoryUI.gd` - Inventory window (I/B key)
- `scripts/ui/ChatUI.gd` - Multiplayer chat
- `scripts/ui/ShopUI.gd` - Vendor shop
- `scripts/ui/level_ui.gd` - HUD (health, XP, gold)
- `scripts/ui/GameMenu.gd` - ESC menu
- `scripts/ui/QuestTrackerUI.gd` - Quest display
- `scripts/ui/GroupUI.gd` - Party frames
- `scripts/ui/TradeWindowUI.gd` - Trading interface
- `scripts/ui/LootBodyUI.gd` - Corpse looting
- `scripts/ui/ChestLootUI.gd` - Chest looting
- `scripts/ui/ItemInspectionUI.gd` - Item details
- `scripts/ui/Armory.gd` - Forged item claiming
- `scripts/ui/BlacksmithForgeUI.gd` - Forge interface

**Layer Hierarchy:**
- Layer 40: Interaction prompts
- Layer 50: Controls/hints
- Layer 110: Main UI windows
- Layer 1000: FPS overlay (debug)

### Audio System
**Core File:**
- `scripts/systems/sound_manager.gd` (~883 lines)

**Features:**
- Procedural sound generation (placeholders)
- Real sound file loading (combat, footsteps, UI)
- Music playlist with fade transitions
- Weapon-specific hit sounds
- 2D positional audio
- Volume controls (SFX, music)
- Sound caching

### Persistence (Save/Load)
**Core Files:**
- `scripts/systems/DatabaseManager.gd` (~844 lines) - JSON-based storage
- `scripts/systems/CharacterStats.gd` - Stats serialization
- `scripts/systems/InventorySystem.gd` - Inventory serialization
- `scripts/systems/QuestManager.gd` - Quest state serialization

**Features:**
- JSON file storage (`user://players.json`)
- Shard support (multi-server)
- Auto-save every 2 minutes
- Manual save on logout
- Server-side save for all connected players
- Data validation and sanitization
- Guest mode (no persistence)

**Save Data Structure:**
- Position (x, y)
- Health (current, max)
- Level, XP, gold
- Attributes (strength, agility, vitality, luck)
- Equipment (weapon, armor slots)
- Inventory (items with slots)
- Quest progress
- Playtime, achievements, kill counts

### Networking
**Core Files:**
- `scripts/networking/NetworkManager.gd` (~988 lines) - Core networking
- `scripts/networking/NetworkPlayer.gd` - Player sync (20Hz)
- `scripts/networking/NetworkEnemyManager.gd` - Enemy sync (10Hz)

**Architecture:**
- **Model:** Host-as-server (one player hosts, others join)
- **Protocol:** ENet (Godot's built-in)
- **Port:** 7000 (default)
- **Max Players:** 50

**Sync Systems:**
- **Player Position:** 20Hz updates with interpolation
- **Player Appearance:** Full LPC sprite sync (gender, armor, weapon)
- **Enemy Position:** 10Hz with interest management (distance-based)
- **Enemy State:** Health, animation, crit window, dying state
- **Damage:** Server-authoritative validation
- **Chat:** Rate-limited (500ms between messages)
- **Version Check:** Git commit hash for compatibility

**Anti-Cheat:**
- Damage validation (50% buffer)
- Rate limiting
- Violation tracking with exponential backoff
- Server-side state validation

---

## 3. CODE ISSUES IDENTIFIED

### God Scripts (>400 lines)

**Critical:**
1. **`scripts/game_world.gd`** - ~4,046 lines
   - World generation, chunk loading, prop spawning, ruins generation
   - Multiplayer player management
   - Terrain generation, POI management
   - **Risk:** Extremely high - single point of failure

2. **`scripts/player/Player.gd`** - ~4,946 lines
   - Player controller, movement, combat, equipment, sprite management
   - Health, damage, PvP, networking
   - **Risk:** Very high - core gameplay logic

3. **`scripts/ui/MainMenu.gd`** - ~2,437 lines
   - Authentication, server connection, UI management
   - Mantle integration, profile display
   - **Risk:** High - complex UI logic

**Large Files:**
4. **`scripts/enemies/Enemy.gd`** - ~1,960 lines
   - Enemy behavior, AI, damage, loot, networking
   - **Risk:** High - enemy logic

5. **`scripts/systems/DatabaseManager.gd`** - ~844 lines
   - Save/load, authentication, data validation
   - **Risk:** Medium - persistence critical

6. **`scripts/systems/sound_manager.gd`** - ~883 lines
   - Audio system, sound generation
   - **Risk:** Low - isolated system

7. **`scripts/networking/NetworkManager.gd`** - ~988 lines
   - Multiplayer core, authentication, RPC handling
   - **Risk:** High - networking critical

8. **`scripts/systems/CharacterStats.gd`** - ~992 lines
   - Stats, equipment, chain system, progression
   - **Risk:** High - core game state

9. **`scripts/systems/InventorySystem.gd`** - ~477 lines
   - Inventory management, tool equipping
   - **Risk:** Medium - inventory logic

### Hardcoded Node Paths

**Found:** 92 matches across 26 files

**Common Patterns:**
- `get_node("/root/SoundManager")` - 35+ occurrences
- `get_node("/root/CharacterStats")` - 111+ occurrences
- `get_node("/root/InventorySystem")` - 49+ occurrences
- `get_node("/root/NetworkManager")` - 19+ occurrences
- `get_node("/root/DatabaseManager")` - 15+ occurrences
- `get_node("/root/main/GameMenu")` - Scene structure dependency

**Risk:** Medium-High
- Brittle to scene structure changes
- Breaks if autoload names change
- Harder to test (tight coupling)

**Recommendation:** Use groups or direct autoload access (autoloads are already global)

### Circular Dependencies

**Status:** ✅ **No circular dependencies found**

Checked for:
- Classes extending autoloads (none found)
- Mutual imports (none found)
- Circular signal connections (none detected)

### Duplicated Logic Patterns

**Identified Patterns:**

1. **Player Reference Lookup**
   - Pattern: `get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)`
   - Found in: 50+ files
   - **Recommendation:** Centralize in GameInput or create PlayerManager

2. **Sound Manager Access**
   - Pattern: `get_node_or_null("/root/SoundManager")` or `SoundManager.play_sound(...)`
   - Inconsistency: Some use autoload directly, others use get_node
   - **Recommendation:** Standardize on autoload access

3. **UI Visibility Checks**
   - Pattern: Multiple files check `is_any_ui_open()` or manually check UI visibility
   - Found in: GameInput, Player, EnemyAI, etc.
   - **Recommendation:** Centralize in GameInput (already exists but not used everywhere)

4. **Damage Number Spawning**
   - Pattern: `CombatText.create_damage(...)` scattered across files
   - Found in: Player, Enemy, PlayerCombat, etc.
   - **Recommendation:** Already centralized, but usage could be more consistent

5. **Item Validation**
   - Pattern: Item dictionary validation repeated in multiple UI files
   - Found in: InventoryUI, CharacterUI, ShopUI, LootBodyUI
   - **Recommendation:** Create ItemValidator utility class

6. **Network Authority Checks**
   - Pattern: `if multiplayer.has_multiplayer_peer() and is_multiplayer_authority()` repeated
   - Found in: Player, Enemy, NetworkPlayer
   - **Recommendation:** Create helper function

7. **Save Data Serialization**
   - Pattern: `get_save_data()` / `load_save_data()` pattern repeated
   - Found in: CharacterStats, InventorySystem, QuestManager
   - **Recommendation:** Create Saveable interface/base class

---

## 4. TOP 5 HIGHEST-LEVERAGE REFACTORS

### #1: Extract World Generation from game_world.gd
**Files Involved:**
- `scripts/game_world.gd` (4,046 lines → target: ~1,500 lines)
- New: `scripts/world/WorldGenerator.gd`
- New: `scripts/world/ChunkManager.gd`
- New: `scripts/world/PropSpawner.gd`
- New: `scripts/world/RuinsGenerator.gd`

**Why It Helps:**
- Reduces game_world.gd from 4,046 to ~1,500 lines
- Separates concerns: world generation vs. runtime management
- Makes world generation testable in isolation
- Easier to add new world features (new biomes, structures)
- Reduces merge conflicts (large file = conflict magnet)

**Risk Level:** **Medium**
- Large refactor but well-isolated
- World generation is mostly independent
- Can be done incrementally (extract one system at a time)
- Risk: Breaking world generation logic (test thoroughly)

**Approach:**
1. Extract terrain generation → WorldGenerator
2. Extract chunk loading → ChunkManager
3. Extract prop spawning → PropSpawner
4. Extract ruins generation → RuinsGenerator
5. Keep multiplayer/player management in game_world.gd

---

### #2: Split Player.gd into Subsystems
**Files Involved:**
- `scripts/player/Player.gd` (4,946 lines → target: ~1,500 lines)
- Already exists: `scripts/player/PlayerCombat.gd` (443 lines)
- Already exists: `scripts/player/PlayerMovement.gd`
- New: `scripts/player/PlayerEquipment.gd` (equipment, sprite management)
- New: `scripts/player/PlayerHealth.gd` (health, healing, death)
- New: `scripts/player/PlayerNetworking.gd` (multiplayer sync)

**Why It Helps:**
- Reduces Player.gd from 4,946 to ~1,500 lines
- Better separation of concerns
- Easier to test subsystems independently
- Reduces cognitive load (smaller files = easier to understand)
- Combat and Movement already extracted (proven pattern)

**Risk Level:** **High**
- Core gameplay logic - breaking changes affect entire game
- Many dependencies on Player.gd
- Need careful testing of all player interactions
- Risk: Breaking combat, movement, or networking

**Approach:**
1. Extract equipment/sprite logic → PlayerEquipment
2. Extract health/healing → PlayerHealth
3. Extract networking sync → PlayerNetworking
4. Keep core CharacterBody2D logic in Player.gd
5. Test incrementally after each extraction

---

### #3: Replace Hardcoded Node Paths with Groups/Autoloads
**Files Involved:**
- 26 files with hardcoded paths
- Most affected: Player.gd, Enemy.gd, game_world.gd, UI files

**Why It Helps:**
- Reduces coupling to scene structure
- Makes code more testable (can mock autoloads)
- Prevents breakage from scene reorganization
- Standardizes access patterns
- Improves code clarity (explicit dependencies)

**Risk Level:** **Low**
- Mechanical refactor (find/replace)
- Autoloads already exist, just need to use them directly
- Low risk of breaking functionality
- Can be done incrementally (file by file)

**Approach:**
1. Replace `get_node("/root/SoundManager")` → `SoundManager` (direct autoload)
2. Replace `get_node("/root/CharacterStats")` → `CharacterStats`
3. Replace scene paths with groups: `get_tree().get_first_node_in_group("game_world")`
4. Add validation where needed: `if not SoundManager: return`
5. Test each file after changes

---

### #4: Centralize Player Reference Lookup
**Files Involved:**
- 50+ files that look up player
- New: `scripts/systems/PlayerManager.gd` (or extend GameInput)

**Why It Helps:**
- Reduces duplication (50+ occurrences)
- Single source of truth for player reference
- Caching support (avoid repeated tree traversal)
- Easier to add multiplayer player selection
- Consistent error handling

**Risk Level:** **Low**
- Additive change (new utility, doesn't break existing)
- Can be adopted incrementally
- Low risk - just a convenience wrapper

**Approach:**
1. Create PlayerManager with `get_local_player()` method
2. Add caching for performance
3. Replace lookups incrementally
4. Keep fallback to group lookup for compatibility

---

### #5: Extract MainMenu Authentication Logic
**Files Involved:**
- `scripts/ui/MainMenu.gd` (2,437 lines → target: ~1,200 lines)
- New: `scripts/ui/AuthenticationUI.gd` (auth forms, login/register)
- New: `scripts/ui/ServerConnectionUI.gd` (host/join UI)
- New: `scripts/ui/ProfileDisplayUI.gd` (Mantle profile display)

**Why It Helps:**
- Reduces MainMenu.gd from 2,437 to ~1,200 lines
- Separates concerns: auth vs. connection vs. profile
- Makes auth logic reusable
- Easier to test authentication flow
- Cleaner UI code organization

**Risk Level:** **Medium**
- UI refactor - visual changes possible
- Authentication is critical (must work correctly)
- Need to preserve all auth flows
- Risk: Breaking login/registration

**Approach:**
1. Extract authentication forms → AuthenticationUI
2. Extract host/join UI → ServerConnectionUI
3. Extract profile display → ProfileDisplayUI
4. Keep menu orchestration in MainMenu.gd
5. Test all auth flows thoroughly

---

## SUMMARY

**Project Health:**
- ✅ No circular dependencies
- ⚠️ 9 god scripts (>400 lines)
- ⚠️ 92 hardcoded node paths
- ⚠️ Multiple duplicated patterns

**Refactoring Priority:**
1. **High Impact, Medium Risk:** World generation extraction
2. **High Impact, High Risk:** Player.gd subsystem split
3. **Medium Impact, Low Risk:** Hardcoded path replacement
4. **Medium Impact, Low Risk:** Player reference centralization
5. **Medium Impact, Medium Risk:** MainMenu authentication extraction

**Recommended Order:**
1. Start with #3 (hardcoded paths) - Low risk, quick wins
2. Then #4 (player reference) - Low risk, reduces duplication
3. Then #5 (MainMenu) - Medium risk, isolated UI
4. Then #1 (world generation) - Medium risk, large but isolated
5. Finally #2 (Player.gd) - High risk, core gameplay

**Estimated Effort:**
- #3: 2-3 days (mechanical)
- #4: 1-2 days (new utility)
- #5: 3-5 days (UI refactor)
- #1: 1-2 weeks (large extraction)
- #2: 2-3 weeks (core gameplay, needs extensive testing)

---

**End of Report**



