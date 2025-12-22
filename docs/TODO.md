# Ashbane - Development TODO

> Last updated: December 2025

---

## Recently Completed Features
- [x] Player Corpse System - EverQuest-style corpse runs with loot recovery
- [x] Death Screen UI - minimalist banner with XP lost, coordinates, respawn timer
- [x] PvP Duel System - consensual 1v1 combat with `/duel` command
- [x] Wolf Enemies - pack behavior, howling mechanics
- [x] Quest System - tutorial and progression quests with tracker UI
- [x] Group/Party System - 40 players, shared XP, raid frames
- [x] Harvest Tools - axe and pickaxe for resource gathering

## Completed This Session (Dec 9, 2024)
- [x] FIX: Inventory icons showing text labels after rapid equip/unequip stress test
- [x] FIX: Added WEAPON_TYPE_FALLBACKS to ItemIconGenerator (greatsword→sword, crossbow→staff, etc.)
- [x] FIX: Added deferred refresh to InventoryUI to coalesce rapid signal emissions
- [x] SECURITY: Implemented security audit fixes (see docs/archive/SECURITY_AUDIT.md)
  - Backend: Admin secret production guard, chat XSS sanitization, trading input validation
  - GDScript: RPC sender validation on all multiplayer functions, debug prints wrapped
  - Cleanup: Deleted backup files, updated .gitignore, added contract README warning

## Completed Previous Session
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

## Forge System - Documentation Complete

The forge system (achievement-to-item) documentation is complete. See these docs:
- `docs/FORGE_ITEM_PHILOSOPHY.md` - Core design, twinking system, trading vision
- `docs/FORGE_ECONOMY_DESIGN.md` - Trading, monetization, market dynamics
- `docs/FORGE_PROVENANCE_SYSTEM.md` - Blockchain backing, history tracking
- `docs/FORGE_ITEM_EFFECTS.md` - Passive effects, active abilities
- `docs/FORGE_ACHIEVEMENT_SHORTLIST.md` - Curated achievement list
- `docs/ACHIEVEMENT_ITEM_CREATION_PROCESS.md` - Item creation workflow

### Forge Backend - Completed
- [x] Achievement-to-item mapping (items.json with 20+ items)
- [x] Effort scoring system (0-100 unified scale)
- [x] Item forge service (item generation from achievements)
- [x] Basic forging API endpoints
- [x] Provenance response schema defined
- [x] Trading models (ForgedAchievement trading fields, ItemTrade, TradeListing)
- [x] Trading routes (`app/routes/trading_routes.py`)
  - [x] `POST /api/trades/direct` - Record direct trades (5% tax, 24h cooldown)
  - [x] `GET /api/trades/history` - Trade history
  - [x] `GET /api/trades/cooldown/{token_id}` - Check trade cooldown
  - [x] `POST /api/trades/listing` - Create chat auction listing
  - [x] `GET /api/trades/listings` - Get active listings (Recently Advertised)
  - [x] `DELETE /api/trades/listing/{id}` - Cancel listing
  - [x] `GET /api/trades/census` - Item census endpoint

### Forge Backend - Completed
- [x] Database migration for new trading tables (alembic)
- [x] Chain batching service (queue trades, batch to Polygon every 5 min)
  - Created `app/services/chain_batching_service.py`
  - Auto-starts on app startup, batches pending trades
  - Records `chain_tx_hash` and `chain_recorded_at` on trades
- [x] Trade announcements for legendary items (integrate with chat_routes)
  - Added `broadcast_system_message()` to chat_routes
  - Legendary/Epic trades announced to global feed

### Forge Godot - Completed
- [x] Trade window UI (TradeWindowUI.gd, /trade command, 5-tile proximity)
- [x] "Recently Advertised" UI panel (RecentlyAdvertisedUI.gd, Tab to toggle)
- [x] /sell and /listings chat commands (TradingManager.gd, ChatUI.gd)
- [x] Trade cooldown indicator on items
  - Added TradingSection to Armory detail panel
  - Shows "Tradeable" or "Cooldown: Xh Ym"
- [x] "Only X exist" census display on tooltips
  - TradingManager fetches census data
  - Armory shows "Only X exist!" for rare items
- [x] Whisper seller / Show on map buttons
  - Whisper pre-fills chat input
  - Map creates waypoint marker in game world

### Forge Testing & Inventory - Completed
- [x] Test forge endpoints (no blockchain required)
  - `/api/forge/claim` - Forge an achievement into item (test mode)
  - `/api/forge/test-grant-all` - Admin endpoint to grant all catalog items
  - `/api/forge/catalog` - Get full item catalog for Armory
- [x] Inventory sync for forged items
  - ForgeItemManager.sync_to_inventory() - Syncs forged items to player inventory
  - Converts forged items to inventory format (weapons, armor, etc.)
  - Stats scale by rarity (damage, defense, crit)

### Forge Godot - Completed
- [x] Armory scene redesign for tradeable items
  - Forge detail panel with 2-row layout (stats, description, trading section)
  - Binding section (bind/unbind buttons, lockbox connection)
  - Catalog with 400px fixed height, grid overlay, card animations
  - UI terminology: bind/unbind (not bridge), lockbox (not wallet)
- [x] Item inspection UI with provenance display
  - Created ItemInspectionUI.gd autoload
  - Modal panel with provenance, trade history, chain status
  - Added /api/trades/provenance/{token_id} endpoint

### Forge Smart Contract - Completed
- [x] Update ForgedItems contract with provenance struct
  - Created ForgedItems.sol with full Provenance struct
  - Tracks forger, currentOwner, tradeCount, forgedAt, lastTradeAt
  - ERC-2981 royalty support (5% default)
- [x] Add trade recording function (relayer only)
  - recordTradeBatch() for batch processing
  - recordTrade() for immediate processing
  - Replay protection via txRef hashes
- [x] Relayer service for gasless transactions
  - Created relayer_service.py
  - forge_item(), record_trade_batch(), get_provenance()
  - Chain batching service uses relayer
- [ ] Deploy to Polygon testnet

## Pending - Security (Deferred from Audit)
- [ ] CRIT-1: Rotate all API keys (before production - currently closed test)
- [ ] CRIT-3: Generate real SESSION_SECRET (manual .env update before production)
- [ ] MED-1: Encrypt OAuth tokens at rest (needs DB migration + encryption key)
- [ ] MED-2: Move device codes to Redis/DB (needs infrastructure decision)

## Pending - Dev Mode Cleanup (Before Production)
- [ ] Re-enable chain_id filtering in `wallet_routes.py` lines 1038-1042, 1107-1111
- [ ] Set DEV_MODE=false and configure real blockchain transactions
- [ ] Update dashboard chain ID from Base Sepolia to mainnet
- [ ] Update Godot MantleAuth API base URL to production domain
- See `docs/DEV_MODE_CHECKLIST.md` for full list

## Pending - Major Features (Designed, Not Implemented)
- [ ] Settlement/Base Building - guild bases with sieges (see docs/FUTURE_SPECS.md)
- [ ] Class System - emergent classes from weapon skills + disciplines (see docs/FUTURE_SPECS.md)
- [ ] Vendor Progression - quest lines to unlock vendor tiers (see docs/FUTURE_SPECS.md)
- [ ] PvP Weakpoints - clickable weakpoints during duels (like enemy crit windows)
- [ ] Additional Biomes - Cursed Lands, Shadow Realm, Void Wastes
- [ ] Ranked Dueling - ELO/ladder system
