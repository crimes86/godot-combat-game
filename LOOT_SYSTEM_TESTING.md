# Loot Body System - Testing Guide

## How to Test

### 1. Kill an Enemy
- Attack a skeleton until it dies
- **Expected**: Hurt animation plays, then freezes on last frame
- **Expected**: Gold is awarded immediately (shown in combat text)
- **Expected**: XP is awarded immediately
- **Expected**: Console shows loot generation (0-2 items)

### 2. Check Corpse Visual State
- Look at the dead skeleton
- **Expected**: Frozen in final hurt pose
- **Expected**: If corpse has loot, you'll see a pulsing pale green glow around it
- **Expected**: Corpse is slightly darker/grayed out compared to living enemies

### 3. Check Respawn System
- Wait 3 seconds after enemy death
- **Expected**: New skeleton spawns at same location
- **Expected**: Corpse remains in the world (doesn't disappear)
- **Expected**: Both corpse and new enemy exist simultaneously

### 4. Loot a Single Corpse
- Right-click on a corpse with the green glow
- **Expected**: Loot UI opens with title "Looting Body"
- **Expected**: Shows 0-2 items with rarity-colored borders:
  - Gray = Common (Bone Shard)
  - Green = Uncommon (Ancient Skull)
  - Blue = Rare (Cursed Femur)
  - Purple = Epic (Lich's Finger Bone)
- **Expected**: Each item shows name, description, and value
- **Expected**: Can click individual "LOOT" buttons
- **Expected**: Can press F to take all items

### 5. Test AOE Looting
- Kill multiple skeletons near each other (within ~300 pixels)
- Right-click on one corpse
- **Expected**: UI shows "Looting X Bodies" (where X is number of corpses)
- **Expected**: All items from all nearby corpses appear in the list
- **Expected**: Taking items removes them from their respective corpses

### 6. Test Empty Corpse Despawn
- Loot all items from a corpse
- **Expected**: Corpse fades out gracefully (0.5 second fade)
- **Expected**: Green glow disappears immediately when last item taken
- **Expected**: Corpse despawns after fade completes

### 7. Test Corpse Decay (Long Test)
- Kill an enemy and don't loot it
- Wait 1 minute
- **Expected**: Corpse transitions to "DECAYING" state
- **Expected**: Corpse becomes more transparent
- **Expected**: Console shows "Corpse is now decaying..."

### 8. Test Corpse Rot (Very Long Test)
- Leave a corpse unlooted for 5 minutes
- **Expected**: At exactly 5 minutes, corpse starts fade-out (2 second fade)
- **Expected**: Console shows "Corpse fully rotted - despawning with X uncollected items"
- **Expected**: Items are lost (cannot be looted after rot begins)

### 9. Test Inventory Full
- Fill your inventory to 32/32 slots
- Try to loot items from corpse
- **Expected**: Console shows "Inventory full!" message
- **Expected**: Items remain on corpse
- **Expected**: Can still loot later after making space

### 10. Test UI Controls
- Open loot UI
- Press ESC
- **Expected**: UI closes
- Press F while UI is open
- **Expected**: All items looted
- Click the X button
- **Expected**: UI closes

## Known Loot Table

### Skeleton Drops (0-2 items per corpse)

| Item Name | Rarity | Value | Drop Weight | Drop Chance |
|-----------|--------|-------|-------------|-------------|
| Bone Shard | Common | 5 gold | 70 | ~70% |
| Ancient Skull | Uncommon | 15 gold | 25 | ~25% |
| Cursed Femur | Rare | 35 gold | 4 | ~4% |
| Lich's Finger Bone | Epic | 100 gold | 1 | ~1% |

### Item Count Distribution
- **0 items**: 40% chance (most corpses are empty)
- **1 item**: 45% chance (common)
- **2 items**: 15% chance (lucky drop)

## Debug Console Messages

### On Enemy Death
```
☠️ ===== ENEMY DEATH =====
Enemy: Enemy@12345 (Level 5)
✨ Granted 50 XP to player
💰 Dropping 25 gold
🎬 Playing death animation...
✅ Death animation complete - frozen on frame 5
  🎲 Rolled loot: Bone Shard (Common)
📦 Corpse has 1 loot item(s)
===== CORPSE CREATED =====
```

### On Corpse Becoming Active
```
💀 Becoming corpse...
  ✅ AI disabled
  ✅ Health bar hidden
  ✅ Collision updated to corpse layer
  ✅ Moved to corpses group
  ✅ Loot indicator added
💀 Corpse state active - will decay in 300s
```

### On Corpse Click
```
💀 Corpse clicked at (1234.5, 678.9)
📦 Found 2 nearby corpses (AOE radius: 300)
✅ Loot UI opened with 3 total corpses
```

### On Looting
```
✨ Looted: Bone Shard from corpse
💀 Corpse fully looted - despawning gracefully
```

### On Decay
```
💀 Corpse is now decaying... (240s remaining)
```

### On Rot
```
💀 Corpse fully rotted - despawning with 1 uncollected items
```

## Common Issues & Fixes

### Issue: Corpse immediately despawns
**Fix**: Check Enemy.gd - make sure `become_corpse()` is called instead of `queue_free()`

### Issue: Can't click corpse
**Fix**: Check collision layer in `become_corpse()` - should be layer 4 (value 8)

### Issue: No loot UI appears
**Fix**: Check game_world.gd - ensure `setup_corpse_loot_system()` is called in _ready()

### Issue: UI shows "No loot remaining" immediately
**Fix**: Check loot generation in `generate_corpse_loot()` - items might not be generating

### Issue: New enemy doesn't spawn
**Fix**: Check enemy_spawner.gd - `died` signal should still trigger respawn

### Issue: Multiple corpses at same location
**Fix**: This is intended! New enemies spawn while old corpses persist

### Issue: Corpse never decays
**Fix**: Check `_process()` function - `process_corpse_decay()` might not be called

## Performance Notes

- **Corpse Limit**: No hard limit, but old corpses auto-despawn after 5 minutes
- **Max Simultaneous Corpses**: Depends on combat, but typically 10-20 max
- **AOE Loot Radius**: 300 pixels = ~4-5 corpses in typical combat
- **Memory**: Each corpse ~500 bytes (minimal overhead)

## Feature Wishlist (Future)

- [ ] Auto-loot option in settings
- [ ] Loot quality filters (only show Rare+)
- [ ] Corpse piles (combine multiple corpses visually)
- [ ] Necromancy skill (revive corpses as minions)
- [ ] Trophy harvesting (special corpse parts)
- [ ] Corpse burning (destroy for bonus resources)
- [ ] Different loot tables per enemy type
- [ ] Boss corpses (longer decay time, better loot)
