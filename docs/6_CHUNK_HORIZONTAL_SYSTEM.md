# 6-Chunk Horizontal System

## Overview

The chunk system has been redesigned to use **6 horizontal chunks** (vertical strips) instead of a 2D grid. This creates a simpler, more predictable loading system.

## World Layout

```
World: -5000 to 13000 (18,000px wide) × -3000 to 3000 (6,000px tall)

Chunks (6 vertical strips, 3000px wide each):

   -5000    -2000     1000     4000     7000    10000    13000
     │        │        │        │        │        │        │
     ├────────┼────────┼────────┼────────┼────────┼────────┤
     │ -2,0   │ -1,0   │  0,0   │  1,0   │  2,0   │  3,0   │  <- 6000px tall
     │        │ SPAWN  │        │        │        │        │     (full world height)
     ├────────┼────────┼────────┼────────┼────────┼────────┤
```

**Spawn point**: (-2000, 0) = Chunk **-1,0**

## Key Changes

### Before (3 Large Chunks)
- 6000×6000px chunks
- 3 chunks total (West, Center, East)
- Complex loading logic checking distances
- Still had issues with 3-4 chunks loading

### After (6 Horizontal Chunks)
- 3000px wide × 6000px tall chunks
- 6 chunks total (horizontal strips)
- **Simple rule**: Always load current + left + right
- Guaranteed 2-3 chunks loaded (2 at edges, 3 in middle)

## Loading Behavior

### At Spawn (Chunk -1,0)
- **Loads**: `-2,0`, `-1,0`, `0,0`
- **Total**: 3 chunks

### Left Edge (Chunk -2,0)
- **Loads**: `-2,0`, `-1,0`
- **Total**: 2 chunks (no left chunk exists)

### Center (Chunk 0,0)
- **Loads**: `-1,0`, `0,0`, `1,0`
- **Total**: 3 chunks

### Right Edge (Chunk 3,0)
- **Loads**: `2,0`, `3,0`
- **Total**: 2 chunks (no right chunk exists)

## Prop Density

Each chunk is 3000px × 6000px = 18,000,000 px² (half the size of old 6000×6000 chunks)

Props per chunk:
- **158 trees** (lootable - wood)
- **36 large rocks** (lootable - stone/ore)
- **45 medium rocks** (decorative)
- **32 small rocks** (decorative)
- **9 lava pools** (visual + light)
- **5 bone clusters** (decorative)
- **14 ash piles** (decorative)
- **18 ground cracks** (visual)

**Total**: ~317 props per chunk

With 2-3 chunks loaded:
- **Minimum**: ~634 props (2 chunks)
- **Maximum**: ~951 props (3 chunks)
- **Typical**: ~951 props (3 chunks most of the time)

## Code Changes

### ChunkBasedPropSystem.gd

1. **Chunk size reduced**:
   ```gdscript
   const CHUNK_SIZE: float = 3000.0  # Was 6000.0
   ```

2. **Prop density halved** (chunks are half the size):
   ```gdscript
   const TREES_PER_CHUNK: int = 158  # Was 315
   const ROCKS_LARGE_PER_CHUNK: int = 36  # Was 72
   # ... etc
   ```

3. **Chunk key calculation** (Y always 0):
   ```gdscript
   func get_chunk_key(world_pos: Vector2) -> String:
       var chunk_x = int(floor(world_pos.x / CHUNK_SIZE))
       return "%d,0" % chunk_x  # Y is always 0
   ```

4. **Simplified loading logic**:
   ```gdscript
   func update_chunks() -> void:
       # Always load: current + left + right
       var chunks_to_load = []
       chunks_to_load.append(player_chunk)
       chunks_to_load.append(left_chunk)   # If exists
       chunks_to_load.append(right_chunk)  # If exists

       # Unload anything NOT in that list
   ```

5. **Prop position generation** (full world height):
   ```gdscript
   var world_height = WORLD_MAX.y - WORLD_MIN.y  # 6000px
   var pos = chunk_center + Vector2(
       rng.randf_range(-CHUNK_SIZE / 2, CHUNK_SIZE / 2),    # ±1500px horizontal
       rng.randf_range(-world_height / 2, world_height / 2)  # ±3000px vertical
   )
   ```

## Benefits

### Simplicity
- ✅ No complex distance calculations
- ✅ No edge detection or boundary checking
- ✅ Just "current + left + right"
- ✅ Always predictable: 2-3 chunks

### Performance
- ✅ Fewer chunks = less management overhead
- ✅ No unnecessary loading/unloading
- ✅ Consistent memory usage (634-951 props)
- ✅ No stuttering from unexpected chunk loads

### Debugging
- ✅ Easy to verify: Check F3 debug
- ✅ Should always show 2-3 loaded chunks
- ✅ Clear which chunks are loaded
- ✅ Simple to reason about

## Debug Display (F3)

Press **F3** to see chunk debug info:

```
CHUNK DEBUG (6 Horizontal Chunks)
Current Chunk: -1,0
Position in Chunk: 850px from left edge
Distance to Edge: 850px
Loaded Chunks: 3 (always 2-3)
Loading Chunks: 0
Total World Chunks: 6 (horizontal strip)
```

## Expected Behavior

### Walking Around
- **In center of chunk**: 2-3 chunks loaded, no loading activity
- **Crossing boundary**: Briefly loads new chunk, unloads old chunk
- **After crossing**: Stable at 2-3 chunks again

### Memory Usage
- **Minimum**: ~2,500 nodes (2 chunks at edges)
- **Maximum**: ~3,750 nodes (3 chunks in middle)
- **Typical**: ~3,750 nodes (most of the time)

### Console Output

When entering new chunk:
```
🗺️ Player entered new chunk: 0,0 (from -1,0)
🗑️ Unloading chunk -2,0 (not current/left/right)
📦 Chunk summary: 3 loaded, 0 loading, current=0,0, keep=[-1,0, 0,0, 1,0]
```

## Testing

1. **Start game at spawn** (-2000, 0)
   - Should show "Current Chunk: -1,0"
   - Should show "Loaded Chunks: 3"

2. **Walk left to chunk boundary**
   - At -3500px, should enter chunk -2,0
   - Should unload chunk 0,0
   - Should show "Loaded Chunks: 2" (edge of world)

3. **Walk right through chunks**
   - Each boundary crossing should swap out far chunk
   - Should always maintain 2-3 chunks
   - No stuttering

## Why This Works

With the old system:
- Complex 2D grid logic
- Distance-based loading
- Edge cases and corner cases
- Diagonal chunks causing issues

With the new system:
- **One rule**: Current + Left + Right
- No special cases
- No diagonals
- No unexpected loads

The world is essentially a horizontal scrolling level divided into 6 zones. You're always in one zone with one zone on each side loaded. Simple!

## Future Scaling

If the world expands horizontally:
- Keep 3000px chunk width
- Add more chunks as needed
- Example: 24,000px wide world = 8 chunks
- Still same rule: Current + Left + Right

If the world needs vertical expansion:
- Could add Y-axis chunking if needed
- But current system handles 6000px height easily
- Most games don't need it
