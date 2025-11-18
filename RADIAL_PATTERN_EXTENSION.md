# Radial Ring Pattern Extension

## 🎯 What This Does

Analyzes your manually placed Level 1-3 enemies (in expanding rings around the campfire) and automatically generates Level 4-10 enemies following the exact same radial expansion pattern.

## 🎮 How to Use

### Step 1: Verify Your L1-3 Pattern
- Make sure you have Level 1, 2, and 3 enemies placed
- They should form expanding rings around campfire (-2000, 0)
- Closer = lower level, further = higher level

### Step 2: Run the Extension Tool
1. Open `game_world.tscn` in Godot editor
2. Open script: `scripts/tools/extend_radial_pattern.gd`
3. Run it: File > Run (or Ctrl+Shift+X)

### Step 3: Review Results
- Check console for detailed analysis
- New L4-10 spawns will be added to your scene
- All properly named and positioned

## 📊 What Gets Analyzed

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

## 🔍 Console Output Example

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

## 🎨 What You Get

After running:
- **Level 1-3**: Your manual placements (unchanged)
- **Level 4-10**: Auto-generated rings following your pattern
- **All named**: L4_Patrol_East_1, L5_Patrol_North_2, etc.
- **Proper spacing**: Matches your minimum spacing
- **Ruins avoided**: 450px exclusion around Ruins 1

## ⚙️ Technical Details

### Ring Calculation
For each new level (4-10):
1. Calculate ring radius = previous_radius + expansion_rate
2. Calculate ring width from your pattern
3. Calculate target spawn count = ring_area × your_density
4. Generate spawns randomly in that ring
5. Enforce minimum spacing between all spawns

### Ruins Exclusion
- Automatically skips spawns within 450px of Ruins 1 (1200, -2000)
- Maintains your pattern everywhere else

### Naming Convention
- Format: `L{level}_Patrol_{direction}_{count}`
- Directions: East, SE, South, SW, West, NW, North, NE
- Based on angle from campfire

## 🔧 If You Want to Adjust

### Change the script settings (top of file):
```gdscript
const CAMPFIRE_POS = Vector2(-2000, 0)  # Center of rings
const RUINS1_POS = Vector2(1200, -2000)  # Exclusion zone
const RUINS_EXCLUSION = 450.0  # Exclusion radius
```

### Change seed for different pattern:
Line 278:
```gdscript
rng.seed = 99999  # Change for different random placement
```

### Adjust minimum spacing:
Line 215:
```gdscript
"min_spacing": max(min_spacing, 150.0),  # Increase for more space
```

## 📝 Notes

- Pattern adapts if you have overlapping levels (L2-3 overlap is fine)
- Automatically calculates density from your placements
- If rings get too wide at higher levels, it adds more spawns to maintain density
- Edge cutoff is natural - spawns just stop where you want them to

## 🎯 Result

You'll have a beautiful radial progression from Level 1 (close to campfire) to Level 10 (near Zone 1 edge), all following your exact design pattern!
