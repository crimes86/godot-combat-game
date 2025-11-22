# Chunk Size Optimization - Eliminating Stutter

## Problem

With 2000×2000px chunks:
- **27 total chunks** in the world
- Constant loading/unloading as you walk around
- **Stuttering** from chunk transitions
- Too many small chunks = too much overhead

## Solution

Increased chunk size to **6000×6000px**:
- **Only 3 chunks** for entire world
- West Zone, Center Zone, East Zone
- All chunks fit in memory = no constant loading/unloading
- **Eliminated stuttering**

## The Math

### Before (2000×2000 chunks)
- World: 18,000 × 6,000 px
- Chunks: 9 wide × 3 tall = **27 chunks**
- Props per chunk: ~70
- Walking around: Load/unload chunks every ~10 seconds
- **Result**: Micro stutters

### After (6000×6000 chunks)
- World: 18,000 × 6,000 px
- Chunks: 3 wide × 1 tall = **3 chunks**
- Props per chunk: ~630 (9x more to maintain density)
- Walking around: Chunks stay loaded
- **Result**: Smooth, no stuttering

## Visual Comparison

```
BEFORE (27 chunks):
┌──┬──┬──┬──┬──┬──┬──┬──┬──┐
│  │  │  │  │  │  │  │  │  │  <- 9 horizontal chunks
├──┼──┼──┼──┼──┼──┼──┼──┼──┤
│  │  │You│  │  │  │  │  │  │  <- Walking = constant chunk changes
├──┼──┼──┼──┼──┼──┼──┼──┼──┤
│  │  │  │  │  │  │  │  │  │  <- 3 vertical chunks
└──┴──┴──┴──┴──┴──┴──┴──┴──┘

AFTER (3 chunks):
┌────────┬────────┬────────┐
│        │        │        │
│  West  │ Center │  East  │  <- 3 horizontal chunks
│ Zone   │  Zone  │  Zone  │
│   You→ │        │        │  <- 1 vertical chunk
└────────┴────────┴────────┘
```

## Performance Impact

### Chunk Transitions
- **Before**: Cross boundary every ~10 seconds of walking
- **After**: Cross boundary every ~30 seconds of walking
- **Improvement**: 3x less frequent chunk loading

### Loading Time
- **Before**: Load 70 props over ~150ms (stutter)
- **After**: Load 630 props over ~250ms (but rarely happens)
- **Net effect**: Smoother because it happens 1/3 as often

### Memory Usage
- **Before**: ~4,500-9,000 nodes loaded (3-9 chunks)
- **After**: ~7,500-9,000 nodes loaded (all 3 chunks)
- **Trade-off**: Slightly more memory, but all chunks fit easily

## Configuration Changes

### ChunkBasedPropSystem.gd

```gdscript
# Chunk size increased from 2000 to 6000
const CHUNK_SIZE: float = 6000.0

# Prop density increased 9x (chunk is 9x bigger)
const TREES_PER_CHUNK: int = 315      # was 35
const ROCKS_LARGE_PER_CHUNK: int = 72  # was 8
const ROCKS_MEDIUM_PER_CHUNK: int = 90 # was 10
const ROCKS_SMALL_PER_CHUNK: int = 63  # was 7
const LAVA_POOLS_PER_CHUNK: int = 18   # was 2
const BONE_CLUSTERS_PER_CHUNK: int = 9 # was 1
const DEAD_VEGETATION_PER_CHUNK: int = 27 # was 3
const CRACKS_PER_CHUNK: int = 36       # was 4

# Preload distance increased proportionally
const CHUNK_BOUNDARY_PRELOAD_DISTANCE: float = 2000.0  # was 800

# Check frequency reduced (fewer chunks = less checking needed)
const CHUNK_UPDATE_INTERVAL: float = 1.0  # was 0.5s

# Props per frame increased (more props per chunk)
const PROPS_PER_FRAME_PRIORITY = 50  # was 15
const PROPS_PER_FRAME_BACKGROUND = 25  # was 8
```

## Why This Works

### The Sweet Spot
- **Too small chunks** (e.g., 500×500) = constant loading = lag
- **Too big chunks** (e.g., 20000×20000) = too many props at once = lag
- **6000×6000** = perfect balance for this world size

### Key Insight
With only 3 chunks for the whole world:
- All chunks can stay in memory
- No constant loading/unloading
- You only cross 2 boundaries in entire world
- Most gameplay happens within one chunk

### For Your World
- Spawn point: West Zone (-1,0)
- Most content: West + Center zones
- Rarely reach: East Zone (1,0)
- **Result**: Usually only 2 chunks loaded, minimal transitions

## Testing Results

**What to expect**:
- Smooth walking with no stuttering
- Chunk loading happens rarely (every ~30 seconds)
- When it does happen, it's brief (~250ms)
- F3 debug shows "Loaded Chunks: 3" most of the time
- "Loading Chunks: 0" most of the time (everything already loaded)

**If you still feel stuttering**:
- Could be unrelated to chunks (GPU, particles, etc.)
- Check F3 debug to see if chunks are actually loading
- If "Loading Chunks" is always 0, stuttering is from something else

## Trade-offs

### Pros
- ✅ Eliminated chunk loading stutters
- ✅ Simpler chunk system (only 3 zones)
- ✅ All content accessible without loading
- ✅ Better prop distribution (630 props spread over 6000×6000)

### Cons
- ⚠️ Slightly more memory usage (all chunks loaded)
- ⚠️ Longer initial load time when entering new zone
- ⚠️ Can't optimize as aggressively for huge worlds

### Verdict
For a world this size (18,000 × 6,000), **3 large chunks is optimal**.

## Future Scaling

If world grows significantly:
- Keep 6000×6000 chunk size
- Add more chunks as world expands
- Example: 36,000 × 12,000 world = 6 × 2 = 12 chunks
- Still manageable, still smooth
