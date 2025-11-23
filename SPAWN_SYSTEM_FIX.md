# Spawn System Fix - Proper Zone Management

## Problem
You have 1200+ spawn points in the game world, and they're ALL spawning enemies at once, causing 15 FPS.

## Solution: Zone-Based Spawning

Instead of spawning enemies at all 1200 points, only spawn enemies in zones near the player.

---

## How to Fix

### Step 1: Add ZonedSpawnManager to Your Scene

1. Open `scenes/game_world.tscn` in Godot
2. Add a **Node** as child of GameWorld (at the root level)
3. Rename it to **"ZonedSpawnManager"**
4. Attach script: `res://scripts/systems/ZonedSpawnManager.gd`

### Step 2: Configure the Manager

In the Inspector for ZonedSpawnManager, set these properties:

```
Max Active Enemies: 50         # Total enemies in world at once
Zone Size: 2000                # Each zone is 2000×2000px
Active Zone Radius: 1          # Load 3×3 grid of zones around player
Enemies Per Zone: 5            # Max 5 enemies per zone
Enemy Scene: res://scenes/enemies/enemy.tscn  # Your enemy prefab
```

### Step 3: Tag Your Spawn Points (Optional)

If your spawn points aren't being detected, add them to a group:

For each spawn point node:
- Select the node
- Go to Node tab → Groups
- Add to group: `spawn_points`

OR just make sure they're named with "SpawnPoint" or "EnemySpawn" in the name.

### Step 4: Remove Old Spawn Logic

If you have any scripts that spawn enemies at game start, disable or remove them. The ZonedSpawnManager will handle all spawning.

---

## How It Works

### Zone System

```
┌─────────┬─────────┬─────────┐
│ Zone    │ Zone    │ Zone    │  Each zone = 2000×2000px
│ (-1,-1) │ (0,-1)  │ (1,-1)  │
├─────────┼─────────┼─────────┤
│ Zone    │🎮PLAYER │ Zone    │  Only spawn in zones
│ (-1,0)  │ (0,0)   │ (1,0)   │  near player (3×3 grid)
├─────────┼─────────┼─────────┤
│ Zone    │ Zone    │ Zone    │
│ (-1,1)  │ (0,1)   │ (1,1)   │
└─────────┴─────────┴─────────┘
```

### Level-Based Spawning

Enemies spawn with levels based on distance from origin:
- **0-1000px from origin:** Level 1-2 enemies
- **1000-2000px:** Level 2-3 enemies
- **2000-3000px:** Level 3-4 enemies
- etc.

This creates natural level progression as player explores.

### Dynamic Loading

- **Player moves to new area** → Load nearby zones, spawn enemies
- **Player leaves area** → Unload distant zones, despawn enemies
- **Enemy dies** → Respawns at same point after delay

---

## Expected Performance

### Before (All Spawn Points Active):
```
Spawn Points: 1200
Active Enemies: 1200
FPS: 15
CPU: 100% (overloaded)
```

### After (Zone-Based):
```
Spawn Points: 1200 (total)
Active Zones: 9 (3×3 grid)
Active Enemies: 45 (5 per zone × 9 zones)
FPS: 55-60
CPU: 35-40%
```

---

## Configuration Guide

### Conservative (Low-End Hardware):
```
Max Active Enemies: 30
Zone Size: 2000
Active Zone Radius: 1  (3×3 = 9 zones)
Enemies Per Zone: 3
Expected: 27 enemies, 60 FPS
```

### Balanced (Your Current Target):
```
Max Active Enemies: 50
Zone Size: 2000
Active Zone Radius: 1
Enemies Per Zone: 5
Expected: 45 enemies, 55-60 FPS
```

### Aggressive (High-End Hardware):
```
Max Active Enemies: 100
Zone Size: 1500
Active Zone Radius: 2  (5×5 = 25 zones)
Enemies Per Zone: 4
Expected: 100 enemies, 45-50 FPS
```

---

## Debugging

### Check If It's Working:

Add this to test console:
```gdscript
# Count active enemies
var enemies = get_tree().get_nodes_in_group("enemies")
print("Active enemies: %d" % enemies.size())

# Should print: ~45-50, NOT 1200!
```

### Enable Debug Output:

The ZonedSpawnManager prints zone activity:
```
📍 Found 1200 spawn points
🗺️ ZonedSpawnManager: 1200 spawn points in 45 zones
  Zone 0,0: 28 spawns, levels 1-2
  Zone 1,0: 35 spawns, levels 2-3
✅ Activating zone 0,0 (levels 1-2)
✅ Activating zone 1,0 (levels 2-3)
❌ Deactivating zone -5,2
```

### Common Issues:

**Issue:** Still spawning 1200 enemies
**Fix:** Make sure old spawn scripts are disabled. Only ZonedSpawnManager should spawn.

**Issue:** No enemies spawning at all
**Fix:** Check that `Enemy Scene` is set in inspector, and spawn points are detected.

**Issue:** Enemies spawn but don't respawn
**Fix:** Make sure enemy has `died` signal that gets emitted on death.

---

## Advanced: Custom Level Ranges

To manually set level ranges for specific zones, modify the script:

```gdscript
# In organize_into_zones(), after the loop:
# Override specific zones
spawn_zones["0,0"]["level_range"] = Vector2i(1, 3)  # Starter zone
spawn_zones["5,0"]["level_range"] = Vector2i(10, 15)  # High level zone
spawn_zones["-3,-3"]["level_range"] = Vector2i(5, 8)  # Mid level zone
```

---

## Migration from Old System

If you were using individual `EnemySpawner` nodes:

1. **Keep them for now** (set `max_enemies = 0` to disable)
2. **Add ZonedSpawnManager** (will handle spawning)
3. **Test that it works**
4. **Delete old spawners** once confirmed

The new system is more efficient and MMO-like.

---

## Summary

✅ **Zone-based spawning** - Only spawn near player
✅ **Level progression** - Enemies scale with distance from origin
✅ **Dynamic loading** - Zones activate/deactivate as player moves
✅ **Performance** - 50 enemies instead of 1200 = **3-4x FPS boost**

**Add the ZonedSpawnManager now for instant performance improvement!**
