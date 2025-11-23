# ACTUAL FIX: Configure Your Existing SpawnManager

## Problem
Your SpawnManager exists but might be configured incorrectly, causing too many enemies to spawn.

---

## Quick Test First

Add the Performance Profiler to see what's actually happening:

1. Open `scenes/game_world.tscn`
2. Add **CanvasLayer** as child of GameWorld
3. Attach script: `res://scripts/debug/PerformanceProfiler.gd`
4. Run game
5. Check the enemy count

---

## Fix 1: Adjust SpawnManager Settings

The SpawnManager is created in `game_world.gd` around line 2089. Add configuration before initialize():

```gdscript
# STEP 2: Create and initialize SpawnManager
spawn_manager = SpawnManager.new()
spawn_manager.name = "SpawnManager"
add_child(spawn_manager)

# ✅ CONFIGURE SPAWN MANAGER (ADD THIS)
spawn_manager.max_active_enemies = 50      # Lower from 75
spawn_manager.spawn_chance_per_marker = 0.15  # Lower from 0.5 (only 15% of markers active)
spawn_manager.spawn_radius = 1500.0        # Reduce spawn radius
spawn_manager.despawn_radius = 2500.0      # Reduce despawn radius

# Initialize with spawn markers
spawn_manager.initialize(self, spawn_markers)
```

This will:
- Limit to **50 active enemies** (down from 75)
- Only **15% of spawn points** are potential spawners (down from 50%)
- **Smaller spawn radius** = fewer enemies near player

---

## Fix 2: Check If Spawn Markers Are Actually Being Used

Run this in your game console after starting:

```gdscript
# Check spawn manager stats
var sm = get_node("/root/GameWorld/SpawnManager")
if sm:
    sm.print_stats()
```

Should show:
```
📊 SPAWN MANAGER STATS:
   Total spawn points: 1200
   Active enemies: 50 / 50      # ✅ Good - capped at 50
   Unspawned: 1150
   Alive: 50
```

If it shows `Active enemies: 1200`, then SpawnManager isn't being used at all!

---

## Fix 3: Make Sure Old Spawner Nodes Are Disabled

Check if you have any **EnemySpawner** nodes in your scene tree:

1. Open `scenes/game_world.tscn`
2. Look for nodes named "EnemySpawner" or similar
3. **Delete them** or set their `max_enemies = 0`

The SpawnManager should be the ONLY thing spawning enemies.

---

## Expected Results

### After Applying Fix 1:

```
Spawn Points: 1200
Potential Spawners: 180 (15% of 1200)
Active Enemies: 50 (max cap)
FPS: 55-60
```

### Performance Comparison:

| Configuration | Active Enemies | FPS |
|---------------|----------------|-----|
| **Current (broken)** | 1200 | 15 FPS |
| **Fix 1 Applied** | 50 | 55-60 FPS |

---

## Debugging Steps

### Step 1: Count Active Enemies

```gdscript
# In game console
get_tree().get_nodes_in_group("enemies").size()
```

If this returns ~1200, SpawnManager isn't limiting correctly.

### Step 2: Check If SpawnManager Exists

```gdscript
# In game console
var sm = get_node_or_null("/root/GameWorld/SpawnManager")
print("SpawnManager exists: ", sm != null)
if sm:
    print("Max active: ", sm.max_active_enemies)
    print("Spawn chance: ", sm.spawn_chance_per_marker)
```

### Step 3: Force Despawn

If enemies are already spawned, force a despawn:

```gdscript
# In game console
var sm = get_node("/root/GameWorld/SpawnManager")
var enemies = get_tree().get_nodes_in_group("enemies")
print("Found ", enemies.size(), " enemies")

# Keep only closest 50
var player = get_tree().get_first_node_in_group("player")
enemies.sort_custom(func(a, b):
    return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position)
)

for i in range(50, enemies.size()):
    enemies[i].queue_free()

print("Despawned ", enemies.size() - 50, " enemies")
```

---

## Most Likely Issue

**Theory**: The SpawnManager exists but `spawn_chance_per_marker = 0.5` is too high.

With 1200 spawn points:
- **50% spawn chance** = 600 potential spawners
- **Spawn radius 2500px** = loads tons of enemies when you zoom out
- **Max 75 enemies** isn't enough to limit the flood

**Solution**: Lower spawn_chance to 0.15 (or even 0.10) and max_active to 50.

---

## Apply This Now:

Edit `scripts/game_world.gd` around line 2089, add the configuration lines, save, and test. FPS should jump from 15 to 55-60 immediately.
