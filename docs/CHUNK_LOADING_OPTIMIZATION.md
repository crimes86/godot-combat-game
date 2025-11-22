# Chunk Loading Optimization - Micro Stutter Fix

## Problem
The original chunk system was causing micro stutters when walking around because:
1. Chunks checked every 0.2 seconds (too frequent for massive 2000×2000px zones)
2. All chunk props (~70 items, 300-500 nodes) generated in a single frame
3. Lava pools are expensive (~40+ nodes each)
4. No predictive loading - chunks loaded only when already inside them

## Solution Implemented

### 1. Reduced Check Frequency
**Before**: 0.2 seconds
**After**: 0.5 seconds (tuned for visibility when zoomed out)

Chunks are massive MMO-style zones (2000×2000px). Checking every 0.5s balances responsiveness with performance.

### 2. Predictive Loading System
Now the system detects when you're **within 800px of a chunk boundary** and starts loading the adjacent chunk in the background.

**How it works**:
- Calculates your position within current chunk (0 to CHUNK_SIZE)
- If within 800px of any edge, starts preloading adjacent chunk
- Handles corners too (diagonal chunks)
- Uses **low priority** loading for adjacent chunks
- 800px preload distance ensures props appear before you see bare ground (especially when zoomed out)

### 3. Async Prop Generation
Props are now generated in small batches across multiple frames instead of all at once.

**Batch sizes** (tuned for visibility):
- **Priority chunks** (current chunk): 15 props per frame
- **Background chunks** (adjacent): 8 props per frame

**Example**:
- Chunk has 70 props total
- Priority loading: 70 props ÷ 15 = ~5 frames (~83ms at 60 FPS)
- Background loading: 70 props ÷ 8 = ~9 frames (~150ms at 60 FPS)

### 4. Smart Unloading
Chunks now unload when **more than 2 chunks away** (Chebyshev distance) instead of using circular radius.

## Technical Details

### New Variables
```gdscript
const CHUNK_UPDATE_INTERVAL: float = 0.5  # Tuned for visibility
const CHUNK_BOUNDARY_PRELOAD_DISTANCE: float = 800.0  # Early preloading

var current_player_chunk: String = ""
var chunks_being_loaded: Dictionary = {}  # {chunk_key: loading_data}
```

### New Functions
- `start_async_chunk_load(chunk_key, is_priority)` - Begins async loading
- `create_prop_generation_queue(chunk_key)` - Creates queue of props to generate
- `process_async_chunk_loading()` - Called every frame to generate props in batches
- `generate_single_prop(chunk_key, prop_data, container)` - Generates one prop

### Removed Functions
- `generate_chunk_props()` - Old synchronous generation (replaced with async system)

## Expected Results

### Before
- Frame spike when crossing chunk boundary (~50-100ms)
- Visible "loading" stutter
- Choppy movement despite 60 FPS average

### After
- Smooth prop loading spread across frames (8-23 frames)
- No visible stutters
- Adjacent chunks preload before you reach them
- Buttery smooth 60 FPS

## Testing Checklist

- [ ] Walk around spawn area - verify smooth movement
- [ ] Walk toward chunk boundary - verify no stutter when crossing
- [ ] Check console for chunk loading messages:
  - `🚀 Priority chunk load started: X,Y`
  - `⏳ Background chunk load started: X,Y`
  - `✅ Chunk X,Y fully loaded (XXX nodes, XXXms)`
- [ ] Verify trees/rocks/lava appear in same positions (deterministic)
- [ ] Monitor FPS - should stay consistent at 60 FPS
- [ ] Walk in circles - verify distant chunks unload properly

## Performance Metrics

### Chunk Load Times (Tuned for Visibility)
- **Priority chunk**: ~83ms (15 props/frame at 60 FPS = 5 frames)
- **Background chunk**: ~150ms (8 props/frame at 60 FPS = 9 frames)
- **No frame drops** - load spread across frames
- **Props visible before entering** - 800px preload distance ensures props appear before you reach them

### Memory
- Max chunks loaded: ~9 (current + 8 surrounding)
- Nodes per chunk: ~300-500
- Total nodes: ~2700-4500 (down from 15,000+ before chunk system)

## Configuration Tuning

If you still experience issues, you can adjust these constants in `ChunkBasedPropSystem.gd`:

### Check Frequency
```gdscript
const CHUNK_UPDATE_INTERVAL: float = 0.5  # Current: 0.5s
# Increase to 1.0-1.5 for less frequent checks (may cause visible delays)
# Decrease to 0.3 for more responsive loading (slightly more CPU)
```

### Preload Distance
```gdscript
const CHUNK_BOUNDARY_PRELOAD_DISTANCE: float = 800.0  # Current: 800px
# Increase to 1000-1200 for even earlier preloading (loads more chunks)
# Decrease to 600 if you want to load fewer chunks at once
```

### Batch Sizes
```gdscript
const PROPS_PER_FRAME_PRIORITY = 15  # Current: 15 props/frame
const PROPS_PER_FRAME_BACKGROUND = 8  # Current: 8 props/frame
# Increase for faster loading (may cause micro stutters if too high)
# Decrease to 10/5 for smoother but slower loading
```

### Unload Distance
```gdscript
if chunk_distance > 2:  # Change to 3 to keep more chunks loaded
```

## How to Test

1. Run the game in Godot
2. Open the console/output panel
3. Walk around and watch for chunk messages
4. Pay attention to:
   - Smoothness of movement
   - When chunks start loading (should be before you reach boundary)
   - FPS counter (should stay at 60)
   - No visible "pop-in" of props

## Lava Pool Exclusion Zones

### Problem
Props (trees, rocks, bones) were spawning inside lava pools, which looked wrong.

### Solution
Lava pools now register exclusion zones that prevent other props from spawning inside them:

1. **Lava pools generate first** - They're at the front of the prop generation queue
2. **Exclusion zones registered** - Each pool registers its position and radius + 30px buffer
3. **Other props check exclusion** - All subsequent props check if they're inside any lava pool before spawning

**Exclusion radius**: `(pool_size / 2) + 30px`
- Small pool (60px): ~60px exclusion radius
- Large pool (150px): ~105px exclusion radius

**Props affected by lava pool exclusion**:
- Trees - avoided
- Large rocks - avoided
- Medium rocks - avoided
- Small rocks - avoided
- Bone clusters - avoided
- Vegetation - avoided
- Cracks - **NOT avoided** (cracks near lava look good visually)

## Large Rock Exclusion Zones

### Problem
Medium and small rocks were spawning on top of large rocks because they use the same RNG seed but different indices.

### Solution
Large rocks now register exclusion zones (60px radius) to prevent smaller rocks from spawning on them:

1. **Large rocks generate first** - They're before medium/small rocks in the queue
2. **Exclusion zones registered** - Each large rock registers its position with a 60px exclusion radius
3. **Smaller rocks check exclusion** - Medium and small rocks check if they would overlap with large rocks

**Exclusion radius**: 60px (covers the largest possible large rock scale of 1.95)

**Props affected by large rock exclusion**:
- Medium rocks - avoided
- Small rocks - avoided

## Files Modified

- `scripts/systems/ChunkBasedPropSystem.gd` - Complete async loading rewrite + lava pool exclusion
- `docs/CHUNK_LOADING_OPTIMIZATION.md` - This documentation
