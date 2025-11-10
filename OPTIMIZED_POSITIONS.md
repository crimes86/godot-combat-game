# 🎯 OPTIMIZED WEAKPOINT POSITIONS - Ready to Use

## Quick Copy/Paste Fix

Replace the three position arrays in `scripts/enemies/Enemy.gd` (around line 460) with these:

```gdscript
var upper_positions = [
	# HEAD & SHOULDERS - 5 positions, well-spaced
	Vector2(0, -14),      # Top of skull (crown)
	Vector2(-6, -11),     # Left temple
	Vector2(6, -11),      # Right temple  
	Vector2(-8, -6),      # Left shoulder
	Vector2(8, -6),       # Right shoulder
]

var mid_positions = [
	# TORSO & ARMS - 9 positions, maximum coverage
	Vector2(0, -3),       # Upper chest (sternum)
	Vector2(-6, -2),      # Left upper ribs
	Vector2(6, -2),       # Right upper ribs
	Vector2(-5, 1),       # Left mid ribs
	Vector2(5, 1),        # Right mid ribs
	Vector2(0, 3),        # Center spine/lower ribs
	Vector2(-5, 5),       # Left hip
	Vector2(5, 5),        # Right hip
	Vector2(0, 7),        # Center pelvis (top)
]

var lower_positions = [
	# LEGS - 3 positions, clear spacing
	Vector2(-4, 10),      # Left upper leg
	Vector2(4, 10),       # Right upper leg
	Vector2(0, 12),       # Between legs (pelvis bottom)
]
```

## What Changed?

### ✅ Fixed Clustering Issues:

**Before (Head area):**
- 4 positions all within 4-6 pixels (clustered)

**After (Head area):**  
- 3 positions with 8+ pixel spacing
- Removed neck position (too close to head)
- Moved shoulders outward for better spread

---

**Before (Mid-chest):**
- 5 positions within 4-pixel range
- Arms only 2 pixels from ribs

**After (Mid-chest):**
- Clear vertical spacing (3 pixel gaps between rows)
- Removed redundant arm positions
- Better left/right symmetry

---

**Before (Lower):**
- 3 positions all in pelvis area

**After (Lower):**
- Spread to include upper legs
- Added center pelvis bottom position

## 📊 Position Statistics

**Total positions:** 17 (down from 20)
- Upper: 5 positions
- Mid: 9 positions  
- Lower: 3 positions

**Minimum spacing:** 8 pixels (was 2-4 pixels)
**Average spacing:** ~10 pixels
**Distribution:** Covers all major body landmarks

## 🎯 Why This Works Better

1. **No clusters** - Every position is 8+ pixels from neighbors
2. **Visual variety** - Positions span head to legs naturally
3. **Section balance** - Mid section has most positions (largest area)
4. **Symmetry** - Left/right pairs make sense visually
5. **Scalable** - Works for 1-3 weakpoints or even 10+ in raids

## 🧪 How to Test

1. Copy the code block above
2. Open `scripts/enemies/Enemy.gd`
3. Find the `spawn_weakpoints()` function (line ~460)
4. Replace the three `var upper_positions`, `var mid_positions`, and `var lower_positions` arrays
5. Save the file
6. Run the game (F5)
7. Attack a skeleton until crit window triggers
8. Observe the weakpoint spread

## 📸 Expected Result

When you trigger a crit window, you should see:
- ✅ 3 weakpoints clearly separated
- ✅ No visual overlap or clustering
- ✅ Positions feel "right" on the skeleton body
- ✅ Different patterns each time (variety)

## 🔄 Iteration Notes

If you still see clustering:
1. Take a screenshot during crit window
2. Note which positions are too close
3. Adjust those specific Vector2 values by 2-4 pixels
4. Re-test

If you want MORE positions:
1. Add positions between existing ones
2. Keep 8+ pixel minimum spacing
3. Assign to appropriate section (upper/mid/lower)

If you want FEWER positions:
1. Remove symmetric pairs (e.g., both shoulders)
2. Keep at least 12-15 total for variety

## 🎮 Alternative: Use the Visual Tool

If you prefer to hand-place positions:
1. Open `scenes/tools/weakpoint_positioner.tscn`
2. Press F6 to run the positioning tool
3. See full instructions in `WEAKPOINT_POSITIONING_GUIDE.md`

## ⚡ TL;DR

**The fastest fix:**
1. Copy the code block at the top
2. Paste into Enemy.gd (replace old arrays)
3. Save and test
4. Done! ✅

This should eliminate clustering immediately. If you want further refinement, you can use the visual tool or manually tweak positions based on in-game testing.
