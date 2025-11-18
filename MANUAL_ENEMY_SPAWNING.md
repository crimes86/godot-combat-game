# Manual Enemy Spawning Guide

You now have full control over enemy placement! Place enemies manually in the editor, and the procedural system will fill in the rest while respecting your placements.

## How to Use

### Method 1: Using the Tool Script (Recommended - Visual Editor)

1. **Open your game_world scene** in Godot editor

2. **Add a new Node** as a child of GameWorld:
   - Click the `+` button or right-click GameWorld
   - Search for and add: `ManualEnemySpawn`
   - Or add a Marker2D and attach the script: `res://scripts/tools/manual_enemy_spawn.gd`

3. **Position the marker** where you want the enemy to spawn
   - You'll see a colored circle showing the spawn point
   - The outer ring shows the aggro radius

4. **Configure in Inspector**:
   - `Enemy Level`: Set the enemy level (1-50+)
   - `Aggro Range`: How close the player must be to trigger aggro (default: 150px)
   - `Enemy Type`: Currently only "skeleton" (more types can be added)

5. **Colors in Editor**:
   - 🟢 **Green** = Level 1-3 (Noob area)
   - 🟡 **Yellow** = Level 4-7 (Low level)
   - 🟠 **Orange** = Level 8-12 (Mid level)
   - 🔴 **Red** = Level 13-18 (High level)
   - 🟣 **Purple** = Level 19+ (Boss level)

### Method 2: Using Plain Marker2D (Quick & Simple)

1. **Add a Marker2D** node as a child of GameWorld

2. **Name it** starting with `EnemySpawn`:
   - Examples: `EnemySpawn_L1`, `EnemySpawn_L3_Noob1`

3. **Add Metadata** in Inspector > Node > Metadata:
   - Add `enemy_level` (int) = the level you want
   - (Optional) Add `aggro_range` (float) = custom aggro radius
   - (Optional) Add `enemy_type` (String) = "skeleton"

4. **Position** the marker where you want the enemy

## Example Use Cases

### Noob Area (Level 1-3)
Place 5-10 level 1-3 enemies around the campfire:
- Close to path for easy finding
- Low aggro range (120px) so they don't surprise new players

### Ruins Guardian Placement
The ruins already have their own guardian system (RuinsCampfire nodes), but you can add extra:
- Place level 10 enemies around Ruins 1
- Set aggro_range to 120 for body pulls

### Dense Farming Spots
Create high-density areas:
- Place multiple level 5-7 enemies in a cluster
- Procedural spawning will avoid these areas (150px buffer)

## How It Works

1. **Manual Spawns First**: System reads all `EnemySpawn_*` markers on startup
2. **Procedural Fills In**: Procedural spawning runs but avoids:
   - Your manual spawn locations (150px radius)
   - Ruins areas (450px radius)
   - Other procedural spawns (150px radius)
3. **Perfect Blend**: You get control where you want it, automation where you don't

## Testing Your Spawns

1. **Save the scene** after placing markers
2. **Run the game** (F5)
3. **Check console** for spawn confirmation:
   ```
   📍 Scanning for manual enemy spawn markers...
   ✅ Spawned L1 skeleton at (-1500, 200) from marker 'EnemySpawn_L1_Noob1'
   ✋ Manually placed: 5 enemies
   ```

## Tips

- **Start Small**: Place 5-10 enemies manually first
- **Test Often**: Run the game to see how they feel
- **Use Variety**: Mix manual (key locations) with procedural (fill)
- **Level Progression**: Place level 1-3 near campfire, gradually increase as player moves east
- **Respect Ruins**: Don't manually place enemies near ruins (1200, -2000), (4800, 2200), (8200, -2200) - those have guardian systems

## Disabling Procedural Spawning

If you want ONLY manual spawns, edit `game_world.gd`:

```gdscript
func spawn_all_enemies():
    print("🎯 Spawning patrol enemies...")
    var manual_spawns = spawn_manual_enemies()
    print("✋ Manually placed: %d enemies" % manual_spawns)

    # Comment out to disable procedural spawning:
    # spawn_zone_1_enemies()

    print("✅ Enemy spawning complete")
```

## Current Setup

Right now, the system spawns:
- **Your manual placements** (if any)
- **Zone 1 procedural**: ~20 enemies (Level 1-10) from Campfire to Ruins 1
- **Ruins guardians**: 8 level 10 skeletons per ruins (via RuinsCampfire system)

Happy spawning! 🎮
