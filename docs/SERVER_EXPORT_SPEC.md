# Dedicated Server Export Specification

## Problem
The game crashes on Linux headless servers because UI autoloads try to access display APIs that don't exist on headless Linux.

## Solution
Create a separate `project.server.godot` with UI autoloads removed, and a build script that uses it for server exports.

---

## Step 1: Create `project.server.godot`

Copy `project.godot` to `project.server.godot` and modify the `[autoload]` section.

### KEEP these autoloads (server needs them):
```ini
ServerRunner="*res://scripts/ServerRunner.gd"
Constants="*res://scripts/constants.gd"
UITheme="*res://scripts/systems/UITheme.gd"
LogManager="*res://scripts/systems/LogManager.gd"
SoundManager="*res://scripts/systems/sound_manager.gd"
CharacterStats="*res://scripts/systems/CharacterStats.gd"
InventorySystem="*res://scripts/systems/InventorySystem.gd"
LootSpawnManager="*res://scripts/systems/LootSpawnManager.gd"
NotificationManager="*res://scripts/systems/NotificationManager.gd"
InteractionManager="*res://scripts/systems/InteractionManager.gd"
DatabaseManager="*res://scripts/systems/DatabaseManager.gd"
NetworkManager="*res://scripts/networking/NetworkManager.gd"
NetworkEnemyManager="*res://scripts/networking/NetworkEnemyManager.gd"
TimeManager="*res://scripts/systems/TimeManager.gd"
GroupManager="*res://scripts/systems/GroupManager.gd"
QuestManager="*res://scripts/systems/QuestManager.gd"
DuelManager="*res://scripts/systems/DuelManager.gd"
GameInput="*res://scripts/systems/GameInput.gd"
AshbaneAuth="*res://scripts/systems/AshbaneAuth.gd"
GameConfig="*res://scripts/systems/GameConfig.gd"
TelemetryManager="*res://scripts/systems/TelemetryManager.gd"
ForgeItemDB="*res://scripts/systems/ForgeItemDB.gd"
ForgeItemManager="*res://scripts/systems/ForgeItemManager.gd"
TradingManager="*res://scripts/systems/TradingManager.gd"
SpatialGrid="*res://scripts/systems/SpatialGrid.gd"
TradingHubManager="*res://scripts/trading_hub/TradingHubManager.gd"
WorldTreeManager="*res://scripts/systems/WorldTreeManager.gd"
WeaponStatsTracker="*res://scripts/systems/WeaponStatsTracker.gd"
WeaponSkillManager="*res://scripts/systems/WeaponSkillManager.gd"
PlayerInteractionController="*res://scripts/systems/PlayerInteractionController.gd"
PlaytestBot="*res://scripts/debug/PlaytestBot.gd"
```

### REMOVE these autoloads (client-only, need display):
```ini
# DO NOT INCLUDE IN SERVER:
# AccountAdmin - extends CanvasLayer
# CursorManager - uses Input.set_custom_mouse_cursor
# VFXLayer - extends CanvasLayer
# ItemIconGenerator - generates textures for UI
# GroupUI - extends CanvasLayer
# TutorialManager - UI-heavy
# QuestTrackerUI - extends CanvasLayer
# BugReportUI - extends CanvasLayer
# MobileInput - touch/display dependent
# AshbaneCosmetics - visual effects
# ForgeVisualEffects - visual effects
# RecentlyAdvertisedUI - extends CanvasLayer
# TradeWindowUI - extends CanvasLayer
# ItemInspectionUI - extends CanvasLayer
# PlayerInteractionMenu - extends CanvasLayer
# PlayerInspectUI - extends CanvasLayer
# Minimap - extends CanvasLayer
# CombatJuice - visual effects (screen shake, etc.)
```

---

## Step 2: Create build script `build_server.sh`

Create in project root:

```bash
#!/bin/bash
# build_server.sh - Build dedicated server with UI autoloads removed

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "=== Building Dedicated Server ==="

# Backup original project.godot
cp project.godot project.godot.backup

# Use server-specific project file
cp project.server.godot project.godot

# Export the server build
echo "Exporting Linux Server..."
/usr/local/bin/godot --headless --export-release "Linux Server" builds/server/ashbane-server.x86_64

# Restore original project.godot
mv project.godot.backup project.godot

echo "=== Server build complete: builds/server/ashbane-server.x86_64 ==="
```

Make executable: `chmod +x build_server.sh`

---

## Step 3: Verify autoloads that need headless guards

Even with removed autoloads, some KEPT autoloads may still need guards. Check these:

### SoundManager
May try to create audio buses. Add at top of `_ready()`:
```gdscript
if DisplayServer.get_name() == "headless":
    set_process(false)
    return
```

### PlayerInteractionController
May reference UI elements. Add guard.

### TimeManager
Should be fine (just manages time), but verify.

---

## Step 4: Handle missing autoload references

Scripts that reference removed autoloads will error. Add null checks:

```gdscript
# Before:
CursorManager.apply_cursor()

# After:
if CursorManager:
    CursorManager.apply_cursor()
```

Common references to check:
- `CursorManager` - used in Player.gd, various UI
- `Minimap` - used in GameWorld
- `VFXLayer` - used in combat effects
- `CombatJuice` - used in hit effects
- `ItemIconGenerator` - used in inventory UI

For server, these are fine to be null since no rendering happens.

---

## Step 5: Test locally before deploying

```bash
# On Linux (or WSL):
./ashbane-server.x86_64 --server --port 7000

# Should see:
# DEDICATED SERVER
# Server started successfully!
# No crashes about display/canvas
```

---

## Step 6: Update deployment

On DO server, pull the new build and run:

```bash
./ashbane-server.x86_64 --server --port 7000
```

No need for `xvfb` or `--headless` flag (it's baked in).

---

## Files to create/modify:

1. **CREATE**: `project.server.godot` - copy of project.godot with UI autoloads removed
2. **CREATE**: `build_server.sh` - build script
3. **MODIFY**: Any scripts that reference removed autoloads (add null checks)

---

## Rollback plan

If this doesn't work:
1. The headless guards are already in place (previous commit)
2. Can try `xvfb-run` wrapper on DO as fallback
3. Can investigate specific crash with `gdb` if needed
