# Enemy Spawn Cleanup & Extension Guide

## 🎯 Goal
Clean up your messy manual spawns, standardize naming, and extend the pattern automatically!

## 📋 Step-by-Step Instructions

### Step 1: Clean Up Your Existing Spawns

1. **Open your game_world scene** in Godot
2. **Open the cleanup script**: `scripts/tools/cleanup_spawns_editor.gd`
3. **Run it**: File > Run (or Ctrl+Shift+X)

**What it does:**
- ✅ Finds ALL your spawn markers (anywhere in the scene tree)
- ✅ Moves them under a new `ManualEnemySpawns` node
- ✅ Renames them properly: `L1_Patrol_East_1`, `L2_Patrol_South_3`, etc.
- ✅ Applies the ManualEnemySpawn script
- ✅ Sets proper metadata
- ✅ Sorts by level for easy organization

**Console Output Example:**
```
🧹 CLEANING UP MANUAL ENEMY SPAWNS
📍 Found 23 spawn markers to clean up...
   ✅ Marker2D_123 -> L1_Patrol_East_1 (L1 at -1800, 350)
   ✅ Node2D_456 -> L2_Patrol_North_1 (L2 at -1500, -400)
   ...
📊 CLEANUP SUMMARY:
   Total spawns processed: 23
   Level distribution:
      Level 1: 8 spawns
      Level 2: 10 spawns
      Level 3: 5 spawns
✅ CLEANUP COMPLETE!
```

### Step 2: Extend Your Pattern (Optional)

1. **Open the extend script**: `scripts/tools/extend_spawn_pattern_editor.gd`
2. **Adjust settings** at the top (if desired):
   ```gdscript
   const MULTIPLIER = 2.0  # 2.0 = double your spawns
   const SEED_VALUE = 12345  # Change for different patterns
   ```
3. **Run it**: File > Run (or Ctrl+Shift+X)

**What it does:**
- ✅ Analyzes your spawn pattern
- ✅ Learns level progression, spacing, and distribution
- ✅ Generates 2x more spawns following your pattern
- ✅ Names them consistently
- ✅ Adds them as proper editor nodes (not runtime spawns)

**Console Output Example:**
```
🎨 EXTENDING ENEMY SPAWN PATTERN
📍 Found 23 existing spawns
📈 Pattern Analysis:
   Bounds: (-2500, -1200) to (800, 1500)
   Min spacing: 245px
   Level progression:
      0-500px: Level 1.2
      500-1000px: Level 2.1
      1000-1500px: Level 3.4
🎲 Generating 23 new spawns (2.0x multiplier)...
   Generated 10/23 spawns...
   Generated 20/23 spawns...
✅ PATTERN EXTENSION COMPLETE!
   Generated: 23 new spawns
   Total spawns: 46
```

### Step 3: Review and Adjust

1. **Check the scene tree**: Look at the `ManualEnemySpawns` node
2. **All spawns are organized** and properly named
3. **Adjust in editor** if needed:
   - Move spawns around
   - Change levels in Inspector
   - Delete ones you don't like
4. **Re-run extend script** if you want more (with different SEED_VALUE)

## 🎨 Naming Convention

After cleanup, spawns are named like:
- `L1_Patrol_East_1` = Level 1, east of campfire, #1
- `L2_Patrol_North_3` = Level 2, north of campfire, #3
- `L3_Patrol_SouthWest_2` = Level 3, southwest of campfire, #2

### Directions (8-way):
- East, SouthEast, South, SouthWest, West, NorthWest, North, NorthEast
- Based on angle from campfire at (-2000, 0)

## ⚙️ Adjusting the Extension

### Change How Many Spawns to Generate

In `extend_spawn_pattern_editor.gd` line 17:
```gdscript
const MULTIPLIER = 3.0  # 3x your current count
```

### Change Random Seed (Different Pattern)

In `extend_spawn_pattern_editor.gd` line 18:
```gdscript
const SEED_VALUE = 99999  # Different number = different pattern
```

### Change Spacing

The system uses your minimum spacing automatically, but you can force a minimum in `analyze_pattern()` line 151:
```gdscript
"min_spacing": max(min_spacing, 200.0),  # Force at least 200px
```

## 🎮 Testing

After running the scripts:
1. **Save the scene** (Ctrl+S)
2. **Run the game** (F5)
3. **Check console** - you'll see:
   ```
   📍 Scanning for manual enemy spawn markers...
   ✅ Spawned L1 skeleton at (-1800, 350) from marker 'L1_Patrol_East_1'
   ...
   ✋ Manually placed: 46 enemies
   ```

## 🔄 Workflow

**Typical workflow:**
1. Place 10-15 spawns manually in a rough pattern
2. Run cleanup script → get organized
3. Run extend script → generate more
4. Test in game
5. Adjust manually if needed
6. Run extend script again with new SEED_VALUE
7. Repeat until satisfied

## 📁 File Locations

- Cleanup Script: `scripts/tools/cleanup_spawns_editor.gd`
- Extend Script: `scripts/tools/extend_spawn_pattern_editor.gd`
- Spawn Tool: `scripts/tools/manual_enemy_spawn.gd`

## 🐛 Troubleshooting

**"No scene is currently open!"**
- Make sure `game_world.tscn` is open in the editor

**"No spawn markers found!"**
- Make sure your markers have "EnemySpawn" in the name or have `enemy_level` metadata

**"Need at least 3 manual spawns!"**
- Place at least 3 manual spawns before running extend script

**Spawns overlap after extending**
- Increase MULTIPLIER to generate more spread out
- Or manually adjust spacing after generation

## 🎯 Result

After running both scripts, you'll have:
- ✅ All spawns organized under one parent node
- ✅ Consistent naming scheme
- ✅ Proper metadata and scripts
- ✅ Extended pattern that follows your design
- ✅ Easy to manage in the editor
- ✅ Ready for the runtime pattern learning system

Now you can run the game and the runtime system will further extend your pattern procedurally! 🎮
