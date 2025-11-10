# 🎯 Weakpoint Positioning Tool - Usage Guide

## What This Tool Does

The **Weakpoint Positioner** is a visual tool that lets you:
- See the skeleton at 2.8x scale (crit window size)
- View all current weakpoint positions as colored dots
- Click to add new positions
- Right-click to remove positions
- Export final positions as copy-paste GDScript arrays

## 🚀 Quick Start

### Step 1: Open the Tool
1. In Godot, open `scenes/tools/weakpoint_positioner.tscn`
2. Click the "Play Scene" button (or press F6)

### Step 2: Edit Positions
The tool loads all 20 current positions from Enemy.gd:
- 🔴 **Red dots** = Upper section (head, neck, shoulders)
- 🟢 **Green dots** = Mid section (chest, ribs, arms, hips)
- 🔵 **Blue dots** = Lower section (pelvis, legs)
- ⚪ **White dots** = Unassigned (newly added)

### Step 3: Modify Positions

**Add a position:**
- Left-click anywhere on the skeleton

**Remove a position:**
- Right-click near a dot (within 15 pixels)

**Assign section to last added:**
- Press `1` for Upper section
- Press `2` for Mid section
- Press `3` for Lower section

**Other shortcuts:**
- `SPACE` = Export positions to console
- `R` = Reset to current positions from Enemy.gd
- `C` = Clear all positions

### Step 4: Export and Apply

1. When happy with positions, press `SPACE`
2. Check the Godot console (Output tab at bottom)
3. Copy the three arrays that appear
4. Open `scripts/enemies/Enemy.gd`
5. Find the `spawn_weakpoints()` function (around line 456)
6. Replace the three position arrays with your new ones
7. Save and test!

## 🎨 Design Tips for Good Positions

### What Makes Good Weakpoint Positions?

✅ **Good spacing:**
- Minimum 8-10 pixels apart at normal scale
- Spread across head, torso, and legs
- Not all clustered in one area

✅ **Visual clarity:**
- On actual body parts (skull, shoulders, ribs, hips, legs)
- Not floating in empty space
- Clear which part of skeleton they're attached to

✅ **Section balance:**
- Upper: 4-6 positions (head/shoulders area)
- Mid: 8-12 positions (torso/arms/hips - largest area)
- Lower: 2-4 positions (legs area)

### Common Problems to Avoid

❌ **Too close together:**
- Positions less than 6 pixels apart will overlap
- Especially bad when blown up 2.8x

❌ **Off-body placement:**
- Floating positions look weird
- Stick to the actual skeleton body parts

❌ **Section imbalance:**
- All positions in one area = feels repetitive
- Need variety across the skeleton

## 📐 Current Position Analysis

### Identified Clustering Issues

Looking at the current positions, here are the problematic clusters:

**Head area (all within 4-6 pixels):**
- `Vector2(0, -12)` - Top of skull
- `Vector2(-4, -10)` - Left head  
- `Vector2(4, -10)` - Right head
- `Vector2(0, -4)` - Neck

**Mid-chest (too many in 4-pixel range):**
- `Vector2(-4, -2)` - Left chest
- `Vector2(4, -2)` - Right chest
- `Vector2(-5, 0)` - Left ribs
- `Vector2(5, 0)` - Right ribs
- `Vector2(0, 0)` - Center spine

**Arms (redundant with chest positions):**
- `Vector2(-7, 0)` - Left arm (only 2 pixels from left ribs)
- `Vector2(7, 0)` - Right arm (only 2 pixels from right ribs)

## 🛠️ Recommended Fix Strategy

### Option 1: Quick Fix (10 minutes)
1. Open the positioning tool
2. Remove obvious clusters (right-click the dots)
3. Add new positions with better spacing
4. Aim for 15-18 total positions instead of 20
5. Export and test

### Option 2: Clean Slate (20 minutes)
1. Press `C` to clear all positions
2. Manually place 15-20 new positions
3. Focus on major body landmarks:
   - Top/sides of skull (3 positions)
   - Shoulders (2 positions)
   - Upper chest (2 positions)
   - Mid ribs (2-3 positions)
   - Lower ribs/hips (2-3 positions)
   - Pelvis (1-2 positions)
   - Upper legs (2 positions)
4. Assign sections with 1/2/3 keys
5. Export and test

### Option 3: Iterative Testing (30 minutes)
1. Start with Quick Fix
2. Test in-game with 3 weakpoints
3. Screenshot and review
4. Adjust problem positions
5. Repeat until satisfied

## 🎮 Testing Checklist

After applying new positions, test these scenarios:

- [ ] Solo play: Spawn 3 weakpoints - do they look spread out?
- [ ] Kill enemy multiple times - does distribution feel varied?
- [ ] Check all viewing angles - do positions look good?
- [ ] Rapid testing - spawn 10 enemies, observe patterns

## 📊 Target Metrics

**Good distribution:**
- Average distance between any two positions: ~8-12 pixels
- No positions closer than 6 pixels
- Roughly equal density across upper/mid/lower sections
- Visual "hotspots" have max 2-3 positions nearby

## 🐛 Troubleshooting

### "I can't see the skeleton!"
- Make sure the sprite texture is loading correctly
- Check the Godot console for errors
- Verify the sprite path: `res://assets/characters/BODY_skeleton_walk.png`

### "My clicks aren't registering!"
- Make sure you're clicking inside the Godot game window
- Not the scene editor - use F6 to run the scene

### "Positions look wrong in-game!"
- Double-check you copied ALL three arrays
- Make sure you replaced the old arrays completely
- Verify the scale matches (positions are in normal scale, get multiplied by 2.8x)

### "Still seeing clustering!"
- Look for positions within 6-8 pixels of each other
- Use the tool's visual display to identify clusters
- Remove redundant positions

## 💡 Pro Tips

1. **Start with key landmarks:**
   - Place positions on obvious body parts first
   - Skull top, shoulders, chest, hips, legs

2. **Use the grid mentally:**
   - Think of the skeleton in a 3x3 grid
   - Aim for positions in each grid cell

3. **Less is more:**
   - 15 well-spaced positions > 20 clustered ones
   - System picks 3 randomly, so all positions should be "good spots"

4. **Test frequently:**
   - Don't try to perfect all 20 positions at once
   - Get 10-12 good ones, test, then refine

5. **Keep sections balanced:**
   - Players expect variety
   - Upper/Mid/Lower should all have chances to spawn

## 📝 Example: Well-Distributed Positions

Here's an example of good spacing (these are SUGGESTIONS, not final):

```gdscript
var upper_positions = [
    Vector2(0, -14),      # Top skull
    Vector2(-6, -10),     # Left temple
    Vector2(6, -10),      # Right temple
    Vector2(-8, -6),      # Left shoulder
    Vector2(8, -6),       # Right shoulder
]

var mid_positions = [
    Vector2(-5, -3),      # Left upper chest
    Vector2(5, -3),       # Right upper chest
    Vector2(0, 0),        # Center spine
    Vector2(-6, 1),       # Left mid ribs
    Vector2(6, 1),        # Right mid ribs
    Vector2(-5, 4),       # Left lower ribs
    Vector2(5, 4),        # Right lower ribs
    Vector2(-4, 6),       # Left hip
    Vector2(4, 6),        # Right hip
]

var lower_positions = [
    Vector2(0, 8),        # Center pelvis
    Vector2(-3, 11),      # Left leg
    Vector2(3, 11),       # Right leg
]
```

Note: These positions:
- Are spaced 8-12 pixels apart minimum
- Cover distinct body parts
- Don't overlap visually at 2.8x scale
- Balance coverage across all sections

## ✨ Final Thoughts

The goal is to make weakpoints feel:
- **Fair** - Players can clearly see and target them
- **Varied** - Each crit window feels different
- **Natural** - They belong on the skeleton body
- **Satisfying** - Destroying them feels good

Remember: This is iterative! Don't expect perfection on the first try. Get something working, test it, and refine based on how it feels in actual gameplay.

Good luck! 🚀
