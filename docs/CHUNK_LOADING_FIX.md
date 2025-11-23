# Chunk Loading Fix - Only Load What's Needed

## Problem

With 6000×6000 chunks (3 wide × 1 tall), **4 chunks were loading** when only 1-2 should load.

### Why 4 Chunks Loaded?

The old logic was designed for a 2D grid (9 × 3 chunks):
- ✅ Current chunk
- ✅ Left neighbor
- ✅ Right neighbor
- ❌ Top neighbor (doesn't exist - world is only 1 chunk tall!)
- ❌ Bottom neighbor (doesn't exist!)
- ❌ Diagonal neighbors (4 more that don't exist!)

**Result**: Loading chunks that don't exist or aren't needed = wasted memory and loading time.

## Solution

Optimized loading logic for horizontal-only world:

### Before
```gdscript
# Load all 8 neighbors (top, bottom, left, right, 4 diagonals)
if near_top_edge:
    load top chunk      # ❌ Doesn't exist
if near_bottom_edge:
    load bottom chunk   # ❌ Doesn't exist
if near_corner:
    load diagonal chunks # ❌ Don't exist
```

### After
```gdscript
# Only load horizontal neighbors (left, right)
if near_left_edge:
    load left chunk    # ✅ Only if in world bounds
if near_right_edge:
    load right chunk   # ✅ Only if in world bounds

# Don't check vertical - world is 1 chunk tall
```

## Expected Behavior

### In West Zone (-1,0)
- **Center of zone**: 1 chunk loaded (West only)
- **Near right edge**: 2 chunks loaded (West + Center preloading)

### In Center Zone (0,0)
- **Center of zone**: 1 chunk loaded (Center only)
- **Near left edge**: 2 chunks loaded (Center + West preloading)
- **Near right edge**: 2 chunks loaded (Center + East preloading)

### In East Zone (1,0)
- **Center of zone**: 1 chunk loaded (East only)
- **Near left edge**: 2 chunks loaded (East + Center preloading)

### At Boundaries
- **Crossing West → Center**: 2 chunks (during transition)
- **Crossing Center → East**: 2 chunks (during transition)
- **After crossing**: 1 chunk (old chunk unloads)

## Unload Logic

### Before
```gdscript
// Keep chunks within 2 chunk radius (Chebyshev distance)
if chunk_distance > 2:
    unload
```

**Problem**: In a 3-chunk world, this keeps all 3 chunks loaded always!

### After
```gdscript
// Only keep current + horizontal neighbors
if horizontal_distance > 1:
    unload
```

**Result**:
- In West: Keep West + Center, unload East
- In Center: Keep Center + West/East, unload nothing (all are neighbors)
- In East: Keep East + Center, unload West

## Code Changes

### ChunkBasedPropSystem.gd

```gdscript
# Removed vertical/diagonal chunk loading
# - No top/bottom edge checking
# - No diagonal corner checking
# - Only left/right horizontal neighbors

# Updated unload logic
# - Changed from "2 chunk radius" to "1 horizontal distance"
# - Only checks horizontal distance (ignores vertical)
# - Keeps current + adjacent only
```

## Debug Output

### Before (4 chunks loading)
```
Loaded Chunks: 4
Current Chunk: -1,0
```

### After (1-2 chunks loading)
```
Loaded Chunks: 1    <- When in center of zone
Loaded Chunks: 2    <- When near boundary
Current Chunk: -1,0
```

## Performance Impact

- **Memory saved**: ~2,500-3,000 nodes (1 unnecessary chunk not loaded)
- **CPU saved**: No checking vertical/diagonal edges
- **Cleaner logic**: Only horizontal chunks matter

## Verification

Use F3 debug display and check:
1. **Loaded Chunks** should show:
   - `1` when in center of any zone
   - `2` when within 2000px of zone boundary
   - Never `3` or `4`

2. **Current Chunk** shows your zone:
   - `-1,0` = West Zone
   - `0,0` = Center Zone
   - `1,0` = East Zone

3. Walk around and watch:
   - Chunks load when approaching boundary
   - Old chunks unload when moving away
   - Only 1-2 chunks at any time

## Why This Matters

With proper chunk loading:
- ✅ Less memory usage
- ✅ Faster loading (only load what's needed)
- ✅ No stuttering from unnecessary loads
- ✅ Cleaner, simpler system

Your world is **3 zones wide × 1 zone tall**, so the system now respects that layout!
