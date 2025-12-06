# DREADLAND - Remaining Tasks

## Recently Completed Features
- [x] Player Corpse System - EverQuest-style corpse runs with loot recovery
- [x] Death Screen UI - minimalist banner with XP lost, coordinates, respawn timer
- [x] PvP Duel System - consensual 1v1 combat with `/duel` command
- [x] Wolf Enemies - pack behavior, howling mechanics
- [x] Quest System - tutorial and progression quests with tracker UI
- [x] Group/Party System - 40 players, shared XP, raid frames
- [x] Harvest Tools - axe and pickaxe for resource gathering

## Completed This Session
- [x] CRITICAL: Add Windows export preset to export_presets.cfg
- [x] CRITICAL: Configure default resolution (1280x720) in project.godot
- [x] CRITICAL: Fix empty array crash in CorpseState.gd:27 (loot_table[0])
- [x] CRITICAL: Add null checks for unchecked get_node() calls in Enemy.gd, LavaDamage.gd, EnemyAI.gd
- [x] SECURITY: Implement admin role system - restrict /setgold, /ban, /delete commands
- [x] SECURITY: Add input validation/bounds checking for admin commands (gold, position, level)
- [x] SECURITY: Add rate limiting with exponential backoff for anti-cheat violations
- [x] SECURITY: Validate save data structure before loading (schema validation)
- [x] LOGGING: Create LogManager system to replace debug prints (toggleable verbosity)
- [x] LOGGING: Convert NetworkManager.gd prints to LogManager (~46 prints)
- [x] LOGGING: Convert NetworkEnemyManager.gd prints to LogManager (~29 prints)
- [x] LOGGING: Convert DatabaseManager.gd prints to LogManager (~19 prints)
- [x] UI: Complete main menu (add Settings, Credits, Exit buttons)
- [x] UI: Create settings menu (volume sliders, graphics options)
- [x] UI: Create credits scene with consolidated asset attributions
- [x] UI: Add Exit Game button functionality
- [x] UI: Add in-game ESC menu (Settings, Credits, Disconnect)
- [x] UI: Fix dark screen after disconnect (TutorialBlackout cleanup)
- [x] UI: Add 10-second logout timer with cancel on move/damage
- [x] UI: Add resolution toggle in settings (main menu + in-game ESC menu)
- [x] UI: Disable resolution dropdown when in fullscreen mode
- [x] UI: Fix Bug Report cancel button, add X close button
- [x] UI: Fix tutorial skip to clean up all elements (blackout, arrows, indicators)
- [x] UI: Add "Quit Now" button to logout timer (exits game immediately)
- [x] UI: Add Alpha Build indicator with version and F1 bug report button

## Pending - Bugs to Investigate
- [x] Gold icon showing placeholder instead of 🪙 emoji (replaced with gold_coins.png texture)
- [x] Item loot notifications not appearing (fixed: layer 200, gold notifications, stacking)
- [x] Quest UI not showing up after disconnect/reconnect (fixed: restore UI autoloads in game_world._ready)
- [x] Ruins campfire aura not healing (fixed: unclaimed campfires now heal anyone)

## Pending - Polish
- [x] Consolidate all asset credits from subdirectories into one file (CREDITS.md)
- [x] Add proper LICENSE file (proprietary license)
- [x] Fix resolution scaling (1280x720 with "keep" aspect ratio)
- [x] Test on multiple resolutions (720p, 1080p, 1440p)

## Pending - Tech Debt
- [x] Split Player.gd into subsystems (Movement, Combat, Healing, Input) - created helper classes
  - Created scripts/player/PlayerCombat.gd (attack, healing, crit windows)
  - Created scripts/player/PlayerMovement.gd (dash, speed modifiers)
  - NOTE: Player.gd still has original code - subsystems available for gradual adoption
- [x] Split game_world.gd (extract path/prop managers)
  - Created scripts/world/WorldPathManager.gd (paths, torches, terrain)
  - Created scripts/world/WorldPropSpawner.gd (trees, rocks, bones, props)
  - NOTE: game_world.gd still has original code - managers available for gradual adoption
- [x] Consolidate 7 weapon animation data files into single template (WeaponAnimationData.gd)
- [x] Create UITheme.gd singleton for shared color constants
- [x] Add signal disconnects in _exit_tree() to prevent memory leaks
- [x] Resolve TODO comments:
  - CharacterUI.gd - Fixed: Use NetworkManager.player_name instead of hardcoded "Adventurer"
  - CampfireFuelUI.gd - Fixed: Implemented custom fuel amount adding with InventorySystem.reduce_quantity()
  - CharacterStats.gd:378 - Not a TODO (was section header, line numbers shifted)
  - CharacterStats.gd - Fixed: Use equipped_weapon.sell_value instead of hardcoded 0
  - Note: 1 minor TODO remains (crit sync to server) - deferred as future feature

## Pending - Architecture
- [x] Reduce autoloads from 26 to 22 (consolidated DebugConfig, TreeAudioManager, GroupInvitePopup, ChainManager)
- [ ] Create EventBus for decoupled system communication (optional/future)

## Pending - Testing
- [ ] Add unit tests for CharacterStats, InventorySystem, Weapon

## Pending - Major Features (Designed, Not Implemented)
- [ ] Settlement/Base Building - guild bases with sieges (see docs/SETTLEMENT_SYSTEM_SPEC.md)
- [ ] PvP Weakpoints - clickable weakpoints during duels (like enemy crit windows)
- [ ] Additional Biomes - Cursed Lands, Shadow Realm, Void Wastes
- [ ] Ranked Dueling - ELO/ladder system
