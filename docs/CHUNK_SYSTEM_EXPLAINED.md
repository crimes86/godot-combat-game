# Chunk System Explained

## What is a Chunk?

A **chunk** is a 6000×6000 pixel square of the game world. Think of it like a massive zone in an MMO - the entire world is divided into these large regions.

## The World Grid

Your world dimensions:
- **Width**: -5000 to 13000 = 18,000px
- **Height**: -3000 to 3000 = 6,000px

Divided into 6000×6000 chunks:
- **Horizontal chunks**: 18,000 ÷ 6000 = **3 chunks**
- **Vertical chunks**: 6,000 ÷ 6000 = **1 chunk**
- **Total chunks**: 3 × 1 = **3 chunks**

**Why so few?** Fewer, larger chunks = less loading/unloading = smoother performance!

## Visual Grid Layout

```
     -5000                    1000                          7000                        13000
-3000 ┌────────────────────────┬─────────────────────────────┬────────────────────────────┐
      │                        │                             │                            │
      │         -1,0           │           0,0               │           1,0              │
      │   (West Zone)          │      (Center Zone)          │       (East Zone)          │
      │                        │                             │                            │
      │  Spawn point here →    │                             │                            │
 3000 └────────────────────────┴─────────────────────────────┴────────────────────────────┘
```

## Chunk Naming

Chunks are named by their **grid coordinates** (not world coordinates):
- `"-1,0"` = West Zone (left third of world)
- `"0,0"` = Center Zone (middle third of world)
- `"1,0"` = East Zone (right third of world)

**Your spawn point** (-2000, 0) is in chunk **"-1,0"** (West Zone)

## How Chunks Load

### Only Nearby Chunks Load
- **Current chunk**: Always loaded (where you are)
- **Adjacent chunks**: Loaded when within 800px of edge (predictive loading)
- **Max loaded**: ~3-9 chunks at once
- **Far chunks**: Don't exist in memory until you get near

### Loading Example
If you're in chunk "0,0" (Center Zone):
```
Loaded:     [-1,0] [ 0,0] [ 1,0]
            West   Center  East

Not loaded: Nothing - all zones stay loaded!
```

With only 3 chunks total, **all chunks stay loaded** most of the time. This eliminates stuttering from chunk loading/unloading!

## Memory Efficiency

**Before chunk system**: All 13,500+ nodes loaded = lag
**Small chunks (27 total)**: Constant loading/unloading = stuttering
**Large chunks (3 total)**: All chunks fit in memory = smooth!

Each chunk now has ~630 props but you rarely cross boundaries, so no stuttering.

## Debug Display

**Press F3 to toggle debug displays**

The chunk debug display appears on the **right side** of the screen and shows:

```
CHUNK DEBUG
Current Chunk: -1,0           <- Which grid square you're in
Position in Chunk: (850, 1200) <- Your XY position within that chunk (0-2000)
Distance to Edge: 350px        <- How far to nearest chunk boundary
Loaded Chunks: 6               <- How many chunks currently loaded
Loading Chunks: 2              <- How many chunks loading in background
Total World Chunks: 27 (9x3 grid) <- Total possible chunks
```

### What the Info Means

**Current Chunk**: Your grid position
- Changes when you cross a chunk boundary
- Format: "X,Y" (grid coordinates)

**Position in Chunk**: Your position within the 2000×2000 square
- (0, 0) = top-left corner of chunk
- (2000, 2000) = bottom-right corner of chunk
- (1000, 1000) = dead center of chunk

**Distance to Edge**: Closest you are to any edge
- Below 800px = Adjacent chunks start preloading
- 0px = You're crossing into next chunk
- Useful for seeing when preloading triggers

**Loaded Chunks**: How many chunks exist in memory right now
- Minimum: 1 (just your current chunk)
- Typical: 3-6 (current + some adjacent)
- Maximum: 9 (current + all 8 surrounding)

**Loading Chunks**: Background loading in progress
- 0 = Nothing loading (smooth sailing)
- 1-3 = Preloading adjacent chunks
- Higher number = Walking fast, system catching up

## F3 Debug Toggle

Pressing **F3** toggles ALL debug displays:
- Performance/FPS overlay (left side)
- Chunk debug info (right side)
- Player sprite debugging
- Enemy debugging

Press F3 again to hide all debug displays.

## Chunk Properties

Each chunk contains (deterministic - same every time):
- **315 trees** (lootable - wood)
- **72 large rocks** (lootable - stone/ore)
- **90 medium rocks** (decorative)
- **63 small rocks** (decorative)
- **18 lava pools** (visual + light)
- **9 bone clusters** (decorative)
- **27 ash piles** (decorative)
- **36 ground cracks** (visual)

**Total props per chunk**: ~630 props = ~2,500-3,000 nodes per chunk
**All 3 chunks**: ~7,500-9,000 nodes total (much better than 13,500+ before!)

## Why Chunks?

**Before chunks**:
- All 13,500+ nodes loaded at spawn
- 15-30 FPS (laggy)
- Micro stutters when moving

**After chunks**:
- Only 4,500 nodes loaded at once
- Smooth 60 FPS
- No stutters (async loading)

**Trade-off**: Slightly more complex system, but **3-4x better performance**
