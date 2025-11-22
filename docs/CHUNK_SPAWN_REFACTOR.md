# Chunk-Aware Spawn System Refactor

**Date:** 2025-01-21
**Status:** ✅ COMPLETE - Ready for Testing

---

## Overview

Refactored the enemy spawn system to integrate with the chunk-based prop system, preserving all carefully placed spawn markers while adding intelligent chunk-aware spawning and performance optimization via LOD (Level of Detail).

---

## What Changed

### 1. New System: `ChunkAwareSpawnManager.gd`

**Location:** `scripts/systems/ChunkAwareSpawnManager.gd`

**Features:**
- ✅ Integrates with `ChunkBasedPropSystem` - spawns only in loaded chunks
- ✅ Retains all 300+ manually placed spawn markers
- ✅ Tunable activation rates per level range
- ✅ State preservation (dead/looted enemies won't respawn)
- ✅ LOD system for performance scaling

**Configuration:**
```gdscript
activation_rates = {
    "L1-3": 0.6,   # 60% of low-level spawns active
    "L4-7": 0.4,   # 40% of mid-level spawns active
    "L8-10": 0.3   # 30% of high-level spawns active
}
max_active_enemies = 50
```

### 2. LOD System Added to `Enemy.gd`

**Proximity-Based Resource Scaling:**

| Distance Range | LOD Level | Behavior |
|----------------|-----------|----------|
| < 400px | **FULL** | Full AI, particles, animations |
| 400-800px | **MEDIUM** | Reduced AI update rate, 50% particles |
| 800-1500px | **MINIMAL** | Visible sprite only, no AI/particles |
| > 1500px | **INVISIBLE** | Completely disabled |

**New Method:**
```gdscript
func set_lod_level(lod_level: int) -> void
```

### 3. Updated `game_world.gd`

**Changes:**
- Removed old `SpawnManager` (distance-based spawning)
- Added `ChunkAwareSpawnManager` (chunk-based spawning)
- Removed manual player position updates (spawn manager handles internally)
- Removed view distance culling from `_process()` (LOD handles visibility)

---

## How It Works

### Initialization Flow

1. **Collect Spawn Markers** (game_world.gd)
   - Scans scene for all `Marker2D` nodes with `enemy_level` metadata
   - Finds ~300 markers placed manually (L1-10)

2. **Group by Chunk** (ChunkAwareSpawnManager)
   - Assigns each marker to a chunk based on position
   - Example: Marker at X=1200 → Chunk "0,0" (chunk size 3000px)

3. **Determine Activation** (per activation rate)
   - Uses fixed RNG seed for consistency
   - L1-3: 60% active, L4-7: 40% active, L8-10: 30% active

4. **Chunk Lifecycle Integration**
   - When chunk loads → spawn active markers in that chunk
   - When chunk unloads → despawn enemies (unless corpse with loot)

### Runtime Flow

**Every 1 second:**
1. Get loaded chunks from `ChunkBasedPropSystem`
2. Spawn enemies in loaded chunks (up to max 50)
3. Despawn enemies in unloaded chunks

**Every 0.5 seconds:**
1. Update LOD for all active enemies
2. Apply performance scaling based on distance

---

## Spawn Marker Distribution

### By Level (Estimated from your radial pattern)

| Level Range | Total Markers | Active (60/40/30%) | Purpose |
|-------------|---------------|-------------------|---------|
| L1-3 | ~120 | ~72 | Early game around campfire |
| L4-7 | ~120 | ~48 | Mid-game toward ruins |
| L8-10 | ~60 | ~18 | End game near ruins |
| **TOTAL** | **~300** | **~138** | Distributed across 6 chunks |

### By Chunk (Estimated)

World divided into 6 horizontal chunks (3000px wide):

| Chunk | X Range | Contains | Markers |
|-------|---------|----------|---------|
| -2,0 | -6000 to -3000 | Campfire west edge | ~30 |
| -1,0 | -3000 to 0 | Campfire main area | ~80 |
| 0,0 | 0 to 3000 | Ruins 1 approach | ~120 |
| 1,0 | 3000 to 6000 | Mid-game area | ~40 |
| 2,0 | 6000 to 9000 | Late-game area | ~20 |
| 3,0 | 9000 to 12000 | Castle approach | ~10 |

**Player starts in chunks -1,0 and 0,0** (campfire + ruins approach)

---

## Performance Benefits

### Before (Old System)
- ❌ 15% of ALL 300 markers spawned globally = ~45 enemies
- ❌ Distance-based spawning (2500px radius)
- ❌ No LOD - all enemies fully processed
- ❌ View culling at 1400px (pop-in/pop-out)

### After (New System)
- ✅ Only spawns in loaded chunks (2-3 chunks max)
- ✅ Smart activation rates (60/40/30% by level)
- ✅ LOD reduces processing for distant enemies
- ✅ Smooth visibility - enemies stay visible in loaded chunks

**Expected Active Enemies:**
- Chunk -1,0 (campfire): ~48 active spawns × 60% L1-3 = ~29 enemies
- Chunk 0,0 (ruins): ~72 active spawns × 40% L4-7 = ~29 enemies
- **Total in view: ~58 active spawns** (capped at 50 max)

**Performance Scaling:**
- Close range (< 400px): ~10 enemies fully processed
- Medium range (400-800px): ~15 enemies reduced AI
- Far range (800-1500px): ~25 enemies minimal processing

---

## Tuning Parameters

### Easy to Adjust

**Spawn Density (ChunkAwareSpawnManager.gd:24-28):**
```gdscript
activation_rates = {
    "L1-3": 0.6,   # Increase for more low-level enemies
    "L4-7": 0.4,   # Increase for more mid-level enemies
    "L8-10": 0.3   # Increase for more high-level enemies
}
```

**Max Enemies (game_world.gd:2035):**
```gdscript
spawn_manager.max_active_enemies = 50  # Increase for more spawns
```

**LOD Distances (ChunkAwareSpawnManager.gd:31-33):**
```gdscript
const LOD_CLOSE: float = 400.0   # Full detail threshold
const LOD_MEDIUM: float = 800.0  # Medium detail threshold
const LOD_FAR: float = 1500.0    # Minimal detail threshold
```

---

## Testing Checklist

### Basic Functionality
- [ ] Start game - enemies spawn around campfire
- [ ] Walk toward ruins - new enemies spawn as chunks load
- [ ] Walk back to campfire - ruins enemies despawn
- [ ] Kill an enemy - corpse stays, enemy won't respawn
- [ ] Loot corpse - corpse disappears, spawn point available

### LOD System
- [ ] Close enemies (< 400px) - full animations, particles
- [ ] Medium enemies (400-800px) - visible, moving
- [ ] Far enemies (800-1500px) - visible but static
- [ ] Zoom out - can see all enemies in loaded chunks

### Performance
- [ ] Check FPS with 50 active enemies
- [ ] Verify only 2-3 chunks loaded at once
- [ ] Confirm distant enemies use less CPU (via profiler)

### Edge Cases
- [ ] Dead enemies with loot stay when chunk unloads
- [ ] Enemies respawn correctly when chunk reloads (if not killed)
- [ ] No duplicate spawns at chunk boundaries
- [ ] State persists across chunk load/unload cycles

---

## Migration Notes

### Old Files (Can Remove After Testing)
- `scripts/systems/SpawnManager.gd` - ✅ Replaced by ChunkAwareSpawnManager
- `scripts/systems/EnemyPoolManager.gd` - ✅ LOD system replaces this
- `scripts/systems/ZonedSpawnManager.gd` - ⚠️ Unused (keep for reference)

### Compatibility
- ✅ All existing spawn markers work unchanged
- ✅ Marker metadata format unchanged
- ✅ Enemy.gd backward compatible (LOD optional)
- ✅ Can regenerate markers with `extend_radial_pattern.gd` if needed

---

## Future Enhancements

### Easy Additions
1. **Per-Chunk Activation Rates**
   - Different rates for campfire vs ruins vs castle
   - Example: Campfire 80% active, Ruins 40% active

2. **Dynamic Difficulty Scaling**
   - Increase activation rates based on player level
   - More enemies as player gets stronger

3. **Respawn Timers**
   - Add cooldown before enemy respawns at marker
   - Prevents instant respawn when chunk reloads

4. **Multiplayer Support**
   - Already designed for it (see SpawnManager.gd comments)
   - Just need to sync spawn state across clients

---

## Known Limitations

1. **No Real-Time Marker Addition**
   - Spawn markers must be in scene at startup
   - Can't add new spawn points at runtime (without reinitializing)

2. **Fixed Chunk Size**
   - Chunks are 3000px wide (hardcoded to match ChunkBasedPropSystem)
   - Changing chunk size requires updating both systems

3. **No Spawn Point Randomization**
   - Enemies always spawn at exact marker positions
   - Could add random offset for variety

---

## Architecture Summary

```
ChunkBasedPropSystem
    ├── loaded_chunks: Dictionary  (chunk_key → ChunkData)
    └── Loads/unloads props based on player position

ChunkAwareSpawnManager
    ├── spawn_registry_by_chunk: Dictionary  (chunk_key → Array[SpawnData])
    ├── spawn_registry_global: Dictionary  (spawn_id → SpawnData)
    ├── active_enemies: Dictionary  (spawn_id → Enemy)
    │
    ├── initialize()  - Groups markers by chunk, determines activation
    ├── update_spawns()  - Spawns/despawns based on loaded chunks
    └── update_enemy_lod()  - Scales performance by distance

Enemy.gd
    ├── current_lod: int  (LOD.FULL/MEDIUM/MINIMAL/INVISIBLE)
    └── set_lod_level(level)  - Applies performance scaling
```

---

## Credits

- **Spawn Marker Placement:** Manual + `extend_radial_pattern.gd` script
- **Chunk System:** `ChunkBasedPropSystem.gd`
- **LOD Concept:** Industry standard (used in most open-world games)
- **Implementation:** Claude Code + Kevin (design feedback)

---

## Questions?

**"How do I add more spawns?"**
- Use `extend_radial_pattern.gd` editor script
- Or manually add `Marker2D` nodes in Godot editor
- Set `enemy_level` metadata

**"How do I make enemies harder/easier?"**
- Adjust activation rates (higher = more enemies)
- Adjust max_active_enemies (higher = more spawns)
- Adjust enemy level in markers

**"Enemies not spawning?"**
- Check console for ChunkAwareSpawnManager initialization messages
- Verify chunks are loading (press F3 for debug display)
- Check activation rates aren't too low

**"Performance still bad?"**
- Lower max_active_enemies (try 30)
- Reduce LOD distances (try 300/600/1200)
- Check profiler for non-spawn performance issues

---

**Next Steps:** Test in Godot and adjust activation rates as needed!
