# Enemy Spawn System - Complete Guide

This comprehensive guide covers the complete enemy spawn system, including spawn location generation and enemy spawning mechanics. These systems work together but remain separate in implementation.

---

## Table of Contents

1. [Spawn Location Generation System](#spawn-location-generation-system)
   - [Radial Ring Pattern](#radial-ring-pattern)
   - [Pattern Learning AI](#pattern-learning-ai)
   - [Cleanup and Extension Tools](#cleanup-and-extension-tools)
2. [Enemy Spawning System](#enemy-spawning-system)
   - [Manual Enemy Spawning](#manual-enemy-spawning)
   - [Procedural Spawning](#procedural-spawning)
   - [Testing and Debugging](#testing-and-debugging)

---

# Spawn Location Generation System

The spawn location generation system provides tools to create, organize, and extend enemy spawn point patterns in the game world. These tools run in the Godot editor and create spawn markers that the enemy spawning system uses at runtime.

## Radial Ring Pattern

### What This Does

Analyzes your manually placed Level 1-3 enemies (in expanding rings around the campfire) and automatically generates Level 4-10 enemies following the exact same radial expansion pattern.

### How to Use

#### Step 1: Verify Your L1-3 Pattern
- Make sure you have Level 1, 2, and 3 enemies placed
- They should form expanding rings around campfire (-2000, 0)
- Closer = lower level, further = higher level

#### Step 2: Run the Extension Tool
1. Open `game_world.tscn` in Godot editor
2. Open script: `scripts/tools/extend_radial_pattern.gd`
3. Run it: File > Run (or Ctrl+Shift+X)

#### Step 3: Review Results
- Check console for detailed analysis
- New L4-10 spawns will be added to your scene
- All properly named and positioned

### What Gets Analyzed

The tool measures your existing pattern:

1. **Ring Radius**: How far each level is from campfire
   - Example: L1 at 200-400px, L2 at 400-700px, L3 at 700-1000px

2. **Ring Width**: How thick each level's ring is
   - Example: ~300px per ring

3. **Expansion Rate**: How much each level expands
   - Example: Each level adds 300px to radius

4. **Density**: How many spawns per area
   - Maintains your spacing preferences

5. **Minimum Spacing**: Distance between individual spawns
   - Example: ~150-200px between enemies

### Console Output Example

```
🎯 ANALYZING RADIAL RING PATTERN AND EXTENDING TO LEVEL 10
================================================================================
📂 Scene: GameWorld
📍 Found 45 existing spawns

📊 EXISTING PATTERN ANALYSIS:
   Total spawns: 45
   Level range: 1 - 3

   Ring structure:
      Level 1: 15 spawns | Radius: 200 - 450 (avg: 325)
      Level 2: 18 spawns | Radius: 450 - 750 (avg: 600)
      Level 3: 12 spawns | Radius: 750 - 1050 (avg: 900)

🔍 EXPANSION PATTERN DETECTED:
   Avg ring width: 300px
   Avg expansion per level: 300px
   Spawn density: 0.000125 per px²
   Min spacing: 175px
   Last ring (L3): 900px avg radius

📏 Ring Generation Settings:
   Starting level: 4
   Starting radius: 1050px
   Ring expansion: 300px per level
   Ring width: 300px
   Min spacing: 175px

⚙️  Generating Level 4 ring...
   Ring: 1050 - 1350px (avg: 1200)
   Target spawns: 16
   ✅ Generated 16 spawns for Level 4

⚙️  Generating Level 5 ring...
   Ring: 1350 - 1650px (avg: 1500)
   Target spawns: 20
   ✅ Generated 20 spawns for Level 5

... (continues for L6-10)

✅ PATTERN EXTENSION COMPLETE!
   Generated 120 new spawns (L4-10)
   Total spawns: 165
```

### What You Get

After running:
- **Level 1-3**: Your manual placements (unchanged)
- **Level 4-10**: Auto-generated rings following your pattern
- **All named**: L4_Patrol_East_1, L5_Patrol_North_2, etc.
- **Proper spacing**: Matches your minimum spacing
- **Ruins avoided**: 450px exclusion around Ruins 1

### Technical Details

#### Ring Calculation
For each new level (4-10):
1. Calculate ring radius = previous_radius + expansion_rate
2. Calculate ring width from your pattern
3. Calculate target spawn count = ring_area × your_density
4. Generate spawns randomly in that ring
5. Enforce minimum spacing between all spawns

#### Ruins Exclusion
- Automatically skips spawns within 450px of Ruins 1 (1200, -2000)
- Maintains your pattern everywhere else

#### Naming Convention
- Format: `L{level}_Patrol_{direction}_{count}`
- Directions: East, SE, South, SW, West, NW, North, NE
- Based on angle from campfire

### Configuration Options

#### Change script settings (top of file):
```gdscript
const CAMPFIRE_POS = Vector2(-2000, 0)  # Center of rings
const RUINS1_POS = Vector2(1200, -2000)  # Exclusion zone
const RUINS_EXCLUSION = 450.0  # Exclusion radius
```

#### Change seed for different pattern:
Line 278:
```gdscript
rng.seed = 99999  # Change for different random placement
```

#### Adjust minimum spacing:
Line 215:
```gdscript
"min_spacing": max(min_spacing, 150.0),  # Increase for more space
```

### Notes

- Pattern adapts if you have overlapping levels (L2-3 overlap is fine)
- Automatically calculates density from your placements
- If rings get too wide at higher levels, it adds more spawns to maintain density
- Edge cutoff is natural - spawns just stop where you want them to

---

## Pattern Learning AI

### What It Does

The system learns from your manual enemy placements and automatically generates more enemies that follow your pattern.

### How It Works

#### 1. Analysis Phase
When the game starts, it analyzes your manual spawns:
- **Level Progression**: What level enemies did you place at different distances from campfire?
- **Spacing**: How far apart did you place them?
- **Distribution**: How far from the main path (y=0) did you place them?
- **Density**: How many enemies per area?

#### 2. Generation Phase
Then it generates **3x your manual count** using the learned pattern:
- Places enemies at appropriate levels based on distance from campfire
- Respects your spacing preferences
- Follows your path offset distribution
- Avoids your manual spawns (maintains spacing)
- Avoids ruins areas (450px radius)

#### 3. Console Output Example

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

### Adjusting the System

#### Change Density Multiplier
In `game_world.gd` line 2214:
```gdscript
var target_total = manual_count * 3  # Change 3 to 2 or 4 or 5, etc.
```
- `* 2` = Spawn 2x your manual count (less dense)
- `* 3` = Spawn 3x your manual count (default)
- `* 5` = Spawn 5x your manual count (very dense)

#### Disable Pattern Learning
In `game_world.gd` line 1987:
```gdscript
var enable_procedural_spawning = false  # Only your manual spawns
```

#### Change World Bounds
In `game_world.gd` lines 2221-2224, adjust where procedural spawns can appear:
```gdscript
var world_min_x = campfire_pos.x - 500  # Start 500px west of campfire
var world_max_x = 1500  # Stop at x=1500 (before Ruins 1)
var world_min_y = -2500  # Northern boundary
var world_max_y = 2500   # Southern boundary
```

### Tips for Best Results

1. **Place at least 10-15 manual spawns** for good pattern learning
2. **Vary your levels** as distance increases from campfire
3. **Spread them out** in the pattern you want repeated
4. **Test iteratively**:
   - Place a few enemies
   - Run game to see pattern
   - Adjust manual placements
   - Re-run to see new pattern

### What Gets Learned

✅ **Level scaling by distance** - "Level 1 near campfire, Level 5 far away"
✅ **Spacing preferences** - "I want 200px between enemies"
✅ **Path offset** - "I want them 400px from the main path"
✅ **Density** - "I want 15 enemies in this area"

❌ **Not learned** - Specific formations, groupings, or intentional gaps (system fills randomly)

### Current Behavior

With your manual spawns placed, the system will:
1. Spawn all your manual placements exactly where you put them
2. Analyze the pattern (level progression, spacing, distribution)
3. Generate 3x more enemies following that pattern
4. Fill the world from campfire to Ruins 1 (x: -2500 to 1500)
5. Maintain all spacing and avoid ruins areas

The result: A naturally populated world that feels consistent with your design vision!

---

## Cleanup and Extension Tools

### Goal
Clean up your messy manual spawns, standardize naming, and extend the pattern automatically!

### Step-by-Step Instructions

#### Step 1: Clean Up Your Existing Spawns

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

#### Step 2: Extend Your Pattern (Optional)

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

#### Step 3: Review and Adjust

1. **Check the scene tree**: Look at the `ManualEnemySpawns` node
2. **All spawns are organized** and properly named
3. **Adjust in editor** if needed:
   - Move spawns around
   - Change levels in Inspector
   - Delete ones you don't like
4. **Re-run extend script** if you want more (with different SEED_VALUE)

### Naming Convention

After cleanup, spawns are named like:
- `L1_Patrol_East_1` = Level 1, east of campfire, #1
- `L2_Patrol_North_3` = Level 2, north of campfire, #3
- `L3_Patrol_SouthWest_2` = Level 3, southwest of campfire, #2

#### Directions (8-way):
- East, SouthEast, South, SouthWest, West, NorthWest, North, NorthEast
- Based on angle from campfire at (-2000, 0)

### Adjusting the Extension

#### Change How Many Spawns to Generate

In `extend_spawn_pattern_editor.gd` line 17:
```gdscript
const MULTIPLIER = 3.0  # 3x your current count
```

#### Change Random Seed (Different Pattern)

In `extend_spawn_pattern_editor.gd` line 18:
```gdscript
const SEED_VALUE = 99999  # Different number = different pattern
```

#### Change Spacing

The system uses your minimum spacing automatically, but you can force a minimum in `analyze_pattern()` line 151:
```gdscript
"min_spacing": max(min_spacing, 200.0),  # Force at least 200px
```

### Testing

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

### Workflow

**Typical workflow:**
1. Place 10-15 spawns manually in a rough pattern
2. Run cleanup script → get organized
3. Run extend script → generate more
4. Test in game
5. Adjust manually if needed
6. Run extend script again with new SEED_VALUE
7. Repeat until satisfied

### File Locations

- Cleanup Script: `scripts/tools/cleanup_spawns_editor.gd`
- Extend Script: `scripts/tools/extend_spawn_pattern_editor.gd`
- Spawn Tool: `scripts/tools/manual_enemy_spawn.gd`

### Troubleshooting

**"No scene is currently open!"**
- Make sure `game_world.tscn` is open in the editor

**"No spawn markers found!"**
- Make sure your markers have "EnemySpawn" in the name or have `enemy_level` metadata

**"Need at least 3 manual spawns!"**
- Place at least 3 manual spawns before running extend script

**Spawns overlap after extending**
- Increase MULTIPLIER to generate more spread out
- Or manually adjust spacing after generation

### Result

After running both scripts, you'll have:
- ✅ All spawns organized under one parent node
- ✅ Consistent naming scheme
- ✅ Proper metadata and scripts
- ✅ Extended pattern that follows your design
- ✅ Easy to manage in the editor
- ✅ Ready for the runtime pattern learning system

---

# Enemy Spawning System

The enemy spawning system takes the spawn locations (created manually or via generation tools) and instantiates actual enemy entities at runtime. This system is separate from spawn location generation but uses the markers created by those tools.

## Manual Enemy Spawning

You now have full control over enemy placement! Place enemies manually in the editor, and the procedural system will fill in the rest while respecting your placements.

### How to Use

#### Method 1: Using the Tool Script (Recommended - Visual Editor)

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
   - Green = Level 1-3 (Noob area)
   - Yellow = Level 4-7 (Low level)
   - Orange = Level 8-12 (Mid level)
   - Red = Level 13-18 (High level)
   - Purple = Level 19+ (Boss level)

#### Method 2: Using Plain Marker2D (Quick & Simple)

1. **Add a Marker2D** node as a child of GameWorld

2. **Name it** starting with `EnemySpawn`:
   - Examples: `EnemySpawn_L1`, `EnemySpawn_L3_Noob1`

3. **Add Metadata** in Inspector > Node > Metadata:
   - Add `enemy_level` (int) = the level you want
   - (Optional) Add `aggro_range` (float) = custom aggro radius
   - (Optional) Add `enemy_type` (String) = "skeleton"

4. **Position** the marker where you want the enemy

### Example Use Cases

#### Noob Area (Level 1-3)
Place 5-10 level 1-3 enemies around the campfire:
- Close to path for easy finding
- Low aggro range (120px) so they don't surprise new players

#### Ruins Guardian Placement
The ruins already have their own guardian system (RuinsCampfire nodes), but you can add extra:
- Place level 10 enemies around Ruins 1
- Set aggro_range to 120 for body pulls

#### Dense Farming Spots
Create high-density areas:
- Place multiple level 5-7 enemies in a cluster
- Procedural spawning will avoid these areas (150px buffer)

### How It Works

1. **Manual Spawns First**: System reads all `EnemySpawn_*` markers on startup
2. **Procedural Fills In**: Procedural spawning runs but avoids:
   - Your manual spawn locations (150px radius)
   - Ruins areas (450px radius)
   - Other procedural spawns (150px radius)
3. **Perfect Blend**: You get control where you want it, automation where you don't

---

## Procedural Spawning

### Overview

The procedural spawning system works in conjunction with manual spawns to fill the game world with enemies. It respects manual placements and uses pattern learning to create a cohesive experience.

### How It Works

1. **Manual Spawns Execute First**
   - All manual spawn markers are processed
   - Enemies are instantiated at their exact positions
   - System records these positions as exclusion zones

2. **Pattern Analysis**
   - Analyzes manual spawn distribution
   - Calculates level progression by distance
   - Determines spacing and density preferences
   - Identifies path offset patterns

3. **Procedural Generation**
   - Generates additional enemies following learned pattern
   - Maintains minimum spacing from all other spawns
   - Avoids ruins exclusion zones (450px radius)
   - Fills designated world bounds

### Configuration

#### Enable/Disable Procedural Spawning

In `game_world.gd`:
```gdscript
func spawn_all_enemies():
    print("🎯 Spawning patrol enemies...")
    var manual_spawns = spawn_manual_enemies()
    print("✋ Manually placed: %d enemies" % manual_spawns)

    # Comment out to disable procedural spawning:
    # spawn_zone_1_enemies()

    print("✅ Enemy spawning complete")
```

#### Adjust Spawn Density

Default multiplier is 3x manual spawn count. Adjust in `game_world.gd`:
```gdscript
var target_total = manual_count * 3  # Modify multiplier here
```

#### Change World Bounds

Define where procedural spawns can appear:
```gdscript
var world_min_x = campfire_pos.x - 500
var world_max_x = 1500
var world_min_y = -2500
var world_max_y = 2500
```

### Exclusion Zones

The system automatically avoids:
- **Manual spawn locations**: 150px radius
- **Ruins areas**: 450px radius around each ruins
- **Other procedural spawns**: 150px minimum spacing

### Current Setup

Right now, the system spawns:
- **Your manual placements** (if any)
- **Zone 1 procedural**: ~20 enemies (Level 1-10) from Campfire to Ruins 1
- **Ruins guardians**: 8 level 10 skeletons per ruins (via RuinsCampfire system)

---

## Testing and Debugging

### Testing Your Spawns

1. **Save the scene** after placing markers
2. **Run the game** (F5)
3. **Check console** for spawn confirmation:
   ```
   📍 Scanning for manual enemy spawn markers...
   ✅ Spawned L1 skeleton at (-1500, 200) from marker 'EnemySpawn_L1_Noob1'
   ✋ Manually placed: 5 enemies
   ```

### Debug Information

The console provides detailed spawn information:
- Manual spawn locations and levels
- Pattern analysis results
- Procedural spawn generation progress
- Total enemy counts by zone

### Tips

- **Start Small**: Place 5-10 enemies manually first
- **Test Often**: Run the game to see how they feel
- **Use Variety**: Mix manual (key locations) with procedural (fill)
- **Level Progression**: Place level 1-3 near campfire, gradually increase as player moves east
- **Respect Ruins**: Don't manually place enemies near ruins coordinates - those have guardian systems
  - Ruins 1: (1200, -2000)
  - Ruins 2: (4800, 2200)
  - Ruins 3: (8200, -2200)

### Common Issues

**Enemies not spawning:**
- Check marker names start with `EnemySpawn`
- Verify `enemy_level` metadata is set
- Check console for error messages

**Too many/few enemies:**
- Adjust procedural multiplier in `game_world.gd`
- Modify manual spawn count
- Check world bounds settings

**Enemies spawning in wrong locations:**
- Verify campfire position is correct (-2000, 0)
- Check ruins exclusion zones
- Ensure minimum spacing is appropriate

---

## Summary

The enemy spawn system consists of two separate but integrated components:

### Spawn Location Generation (Editor-time)
- **Radial Ring Pattern**: Creates expanding rings of spawn points
- **Pattern Learning AI**: Analyzes and extends spawn patterns
- **Cleanup Tools**: Organizes and standardizes spawn markers
- **Extension Tools**: Multiplies spawn patterns systematically

### Enemy Spawning (Runtime)
- **Manual Spawning**: Reads markers and spawns exact placements
- **Procedural Spawning**: Fills world following learned patterns
- **Pattern Analysis**: Understands level progression and spacing
- **Exclusion System**: Respects manual spawns and special zones

Together, these systems provide full control over enemy placement while automating the tedious work of populating large game worlds.
