# Pattern Learning AI System

## What It Does

The system now **learns from your manual enemy placements** and automatically generates more enemies that follow your pattern!

## How It Works

### 1. Analysis Phase
When the game starts, it analyzes your manual spawns:
- **Level Progression**: What level enemies did you place at different distances from campfire?
- **Spacing**: How far apart did you place them?
- **Distribution**: How far from the main path (y=0) did you place them?
- **Density**: How many enemies per area?

### 2. Generation Phase
Then it generates **3x your manual count** using the learned pattern:
- Places enemies at appropriate levels based on distance from campfire
- Respects your spacing preferences
- Follows your path offset distribution
- Avoids your manual spawns (maintains spacing)
- Avoids ruins areas (450px radius)

### 3. Console Output Example

When you run the game, you'll see:
```
📍 Scanning for manual enemy spawn markers...
✅ Spawned L1 skeleton at (-1800, 350) from marker 'EnemySpawn_L1_1'
✅ Spawned L2 skeleton at (-1600, -200) from marker 'EnemySpawn_L2_1'
✅ Spawned L3 skeleton at (-1200, 450) from marker 'EnemySpawn_L3_1'
... (more manual spawns)
📊 Manual spawn summary: 15 enemies placed

🔍 Analyzing your spawn pattern...
📈 Pattern Analysis:
   Total manual spawns: 15
   Avg level: 2.3
   Avg distance from campfire: 850px
   Avg distance from path: 380px
   Min spacing between spawns: 245px
   Level progression by distance:
      0-500px: Level 1.5 (n=4)
      500-1000px: Level 2.2 (n=7)
      1000-1500px: Level 3.1 (n=4)

🤖 AI will now learn from your 15 manual spawns and continue the pattern...

🎯 Continuing your spawn pattern...
🎲 Generating 30 enemies based on your pattern...
📏 Using spacing: 245px, Path offset: 380px
Zone 1: Spawned 30 procedural patrol enemies

✅ Enemy spawning complete
```

## Adjusting the System

### Change Density Multiplier
In `game_world.gd` line 2214:
```gdscript
var target_total = manual_count * 3  # Change 3 to 2 or 4 or 5, etc.
```
- `* 2` = Spawn 2x your manual count (less dense)
- `* 3` = Spawn 3x your manual count (default)
- `* 5` = Spawn 5x your manual count (very dense)

### Disable Pattern Learning
In `game_world.gd` line 1987:
```gdscript
var enable_procedural_spawning = false  # Only your manual spawns
```

### Change World Bounds
In `game_world.gd` lines 2221-2224, adjust where procedural spawns can appear:
```gdscript
var world_min_x = campfire_pos.x - 500  # Start 500px west of campfire
var world_max_x = 1500  # Stop at x=1500 (before Ruins 1)
var world_min_y = -2500  # Northern boundary
var world_max_y = 2500   # Southern boundary
```

## Tips for Best Results

1. **Place at least 10-15 manual spawns** for good pattern learning
2. **Vary your levels** as distance increases from campfire
3. **Spread them out** in the pattern you want repeated
4. **Test iteratively**:
   - Place a few enemies
   - Run game to see pattern
   - Adjust manual placements
   - Re-run to see new pattern

## What Gets Learned

✅ **Level scaling by distance** - "Level 1 near campfire, Level 5 far away"
✅ **Spacing preferences** - "I want 200px between enemies"
✅ **Path offset** - "I want them 400px from the main path"
✅ **Density** - "I want 15 enemies in this area"

❌ **Not learned** - Specific formations, groupings, or intentional gaps (system fills randomly)

## Current Behavior

With your manual spawns placed, the system will:
1. Spawn all your manual placements exactly where you put them
2. Analyze the pattern (level progression, spacing, distribution)
3. Generate 3x more enemies following that pattern
4. Fill the world from campfire to Ruins 1 (x: -2500 to 1500)
5. Maintain all spacing and avoid ruins areas

The result: A naturally populated world that feels consistent with your design vision! 🎮
