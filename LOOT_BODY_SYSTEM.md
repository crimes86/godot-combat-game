# Loot Body System Design Document

## Overview
Implementation of a lootable corpse system for enemies that provides a visual, interactive looting experience with AOE collection and timed decay.

## Current System Analysis

### Enemy Death (Enemy.gd:616-663)
```gdscript
func die() -> void:
    - Grants XP and gold immediately to player
    - Plays "hurt" animation (6 frames)
    - Waits for animation to finish (animation_finished signal)
    - Emits died signal
    - Calls queue_free() (immediate despawn)
```

### Spawn System (enemy_spawner.gd:105-135)
```gdscript
func _on_enemy_died(spawn_index: int):
    - Triggered by died signal
    - Waits respawn_delay (3.0 seconds)
    - Spawns new enemy at same position
```

### Loot UI (ChestLootUI.gd)
- Slot-based UI showing items
- Click individual items or "Take All"
- Supports item filtering and empty state
- Similar style to character sheet

## New System Requirements

### 1. Corpse Visual State
- **Death Animation**: Play full "hurt" animation (6 frames)
- **Frozen State**: Freeze on last frame of hurt animation
- **Lootable Indicator**: Add visual indicator (glow/outline) when corpse has items
- **Decay State**: Optional visual change as 5-minute timer progresses

### 2. Loot Generation
```gdscript
# Each enemy generates 0-2 items based on:
- Enemy level (higher level = better loot chance)
- Rarity system (Common, Uncommon, Rare, Epic)
- Loot tables per enemy type (skeleton has bone-themed items)

# Example skeleton loot table:
{
    "Ancient Skull": {rarity: "Uncommon", value: 15, drop_chance: 0.3},
    "Bone Shard": {rarity: "Common", value: 5, drop_chance: 0.6},
    "Cursed Femur": {rarity: "Rare", value: 35, drop_chance: 0.1}
}
```

### 3. Gold Distribution
**IMPORTANT**: Gold is distributed immediately on death (current behavior maintained)
- Gold awarded instantly to player
- Combat text shows gold amount
- Only items remain on corpse

### 4. AOE Looting System
```gdscript
# When player right-clicks one corpse:
- Find all corpses within AOE_LOOT_RADIUS (e.g., 300 pixels)
- Collect gold from ALL corpses (immediate award)
- Aggregate ALL items from ALL corpses into one UI
- Mark items with corpse source (for visual clarity)
- Open single LootBodyUI showing all aggregated loot
```

### 5. Corpse States
```gdscript
enum CorpseState {
    FRESH,      # 0-60s: Full loot, visible indicator
    DECAYING,   # 60s-5min: Loot available, visual decay
    ROTTED      # 5min+: Despawn, loot lost
}
```

### 6. Interaction Flow
```
1. Enemy dies
   ↓
2. Play hurt animation to completion
   ↓
3. Freeze on last frame
   ↓
4. Generate loot items (0-2 items)
   ↓
5. Trigger respawn immediately (spawn system)
   ↓
6. Start 5-minute decay timer
   ↓
7. Player right-clicks corpse
   ↓
8. Find all corpses in AOE radius
   ↓
9. Collect gold from all (instant award)
   ↓
10. Aggregate items from all corpses
   ↓
11. Open LootBodyUI with aggregated items
   ↓
12. Player loots items (click or take all)
   ↓
13. Empty corpses despawn gracefully
   ↓
14. Corpses with items remaining continue decay
   ↓
15. After 5 minutes, rotted corpses despawn (loot lost)
```

## Implementation Plan

### Phase 1: Corpse State System
**File**: `scripts/enemies/Enemy.gd`

```gdscript
# New variables
var is_corpse: bool = false
var corpse_loot: Array = []  # Generated items
var corpse_creation_time: float = 0.0
const CORPSE_DECAY_TIME: float = 300.0  # 5 minutes
var corpse_state: CorpseState = CorpseState.FRESH

# Modified die() function
func die() -> void:
    if is_dying:
        return
    is_dying = true

    # Grant XP immediately
    var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
    if player and player.has_method("gain_experience"):
        player.gain_experience(xp_reward)

    # Grant gold immediately
    CharacterStats.add_gold(gold_drop)

    # Play death animation
    var anim_sprite = sprite as AnimatedSprite2D
    if anim_sprite and anim_sprite.sprite_frames.has_animation("hurt"):
        anim_sprite.play("hurt")
        await anim_sprite.animation_finished

        # FREEZE on last frame
        anim_sprite.stop()
        anim_sprite.frame = anim_sprite.sprite_frames.get_frame_count("hurt") - 1

    # Generate loot
    corpse_loot = generate_corpse_loot()

    # Emit died signal (triggers respawn)
    died.emit()

    # Transition to corpse state
    become_corpse()

func become_corpse() -> void:
    is_corpse = true
    corpse_creation_time = Time.get_ticks_msec() / 1000.0
    corpse_state = CorpseState.FRESH

    # Disable AI and combat
    if has_node("EnemyAI"):
        get_node("EnemyAI").queue_free()

    # Disable health bar
    if health_bar:
        health_bar.visible = false

    # Disable collision (can't be hit)
    collision_layer = 0
    collision_mask = 0

    # Change to corpse group
    remove_from_group(Constants.GROUP_ENEMIES)
    add_to_group("corpses")

    # Add loot indicator if has items
    if corpse_loot.size() > 0:
        add_loot_indicator()

    # Start decay timer
    start_decay_timer()

func generate_corpse_loot() -> Array:
    # Implement loot generation based on level and tables
    var loot = []
    var num_items = randi_range(0, 2)  # 0-2 items per corpse

    # Use skeleton loot table
    for i in range(num_items):
        var item = roll_loot_item()
        if item:
            loot.append(item)

    return loot
```

### Phase 2: Loot Body UI
**File**: `scripts/ui/LootBodyUI.gd` (based on ChestLootUI.gd)

```gdscript
extends CanvasLayer
class_name LootBodyUI

# Similar to ChestLootUI but:
# - Shows corpse count ("Looting 3 bodies")
# - Shows gold collected ("Collected 45 gold")
# - Shows source corpse for each item (optional)
# - Uses darker/bone theme instead of golden chest theme

var corpses_looted: Array[Enemy] = []  # All corpses in AOE
var aggregated_loot: Array = []
var total_gold_collected: int = 0

func open_loot_ui(primary_corpse: Enemy, nearby_corpses: Array) -> void:
    corpses_looted = [primary_corpse] + nearby_corpses

    # Collect gold from all
    for corpse in corpses_looted:
        total_gold_collected += corpse.gold_drop

    # Aggregate all loot
    aggregated_loot.clear()
    for corpse in corpses_looted:
        for item in corpse.corpse_loot:
            aggregated_loot.append(item)

    populate_loot_list()
    show()
```

### Phase 3: AOE Loot Collection
**File**: `scripts/enemies/Enemy.gd`

```gdscript
const AOE_LOOT_RADIUS: float = 300.0  # 300 pixels

func _on_corpse_clicked() -> void:
    if not is_corpse:
        return

    # Find all corpses in radius
    var nearby_corpses = get_nearby_corpses(AOE_LOOT_RADIUS)

    # Open loot UI with aggregated loot
    var loot_ui = create_loot_body_ui()
    loot_ui.open_loot_ui(self, nearby_corpses)

func get_nearby_corpses(radius: float) -> Array:
    var corpses = []
    var all_corpses = get_tree().get_nodes_in_group("corpses")

    for corpse in all_corpses:
        if corpse == self:
            continue
        if is_instance_valid(corpse) and corpse.global_position.distance_to(global_position) <= radius:
            corpses.append(corpse)

    return corpses
```

### Phase 4: Decay System
**File**: `scripts/enemies/Enemy.gd`

```gdscript
func start_decay_timer() -> void:
    # Process decay over 5 minutes
    pass

func _process(delta: float) -> void:
    if not is_corpse:
        return

    var elapsed = (Time.get_ticks_msec() / 1000.0) - corpse_creation_time

    # Update state
    if elapsed > CORPSE_DECAY_TIME:
        rot_and_despawn()
    elif elapsed > 60.0:
        if corpse_state == CorpseState.FRESH:
            corpse_state = CorpseState.DECAYING
            update_decay_visual()

func rot_and_despawn() -> void:
    corpse_state = CorpseState.ROTTED

    # Fade out animation
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 2.0)
    await tween.finished

    queue_free()

func check_if_looted_empty() -> void:
    # Called when item is taken from corpse
    if corpse_loot.is_empty():
        # Graceful despawn
        graceful_despawn()

func graceful_despawn() -> void:
    # Fade out quickly since fully looted
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.5)
    await tween.finished
    queue_free()
```

### Phase 5: Spawn System Update
**File**: `scripts/systems/enemy_spawner.gd`

```gdscript
func _on_enemy_died(spawn_index: int) -> void:
    # CHANGED: No longer wait for corpse to despawn
    # Respawn immediately when died signal received

    print("☠️ Enemy died at position ", spawn_index)
    print("✨ Spawning replacement immediately...")

    # Remove from tracking
    if enemy_at_position.has(spawn_index):
        enemy_at_position.erase(spawn_index)

    respawn_queue.append(spawn_index)

    # Immediate respawn (or short delay for visual clarity)
    await get_tree().create_timer(respawn_delay).timeout

    spawn_enemy_at(spawn_index, true)
```

## Visual Design

### Corpse Indicator
- Subtle glow around corpse if it has loot
- Color: Bone white or pale green
- Pulsing animation to draw attention

### Loot Body UI Theme
```
┌─────────────────────────────────────┐
│  Looting 3 Bodies                 X │
│  Collected 45 gold                  │
├─────────────────────────────────────┤
│ ┌─────────────────────────────┐    │
│ │ 💀 Ancient Skull        LOOT│    │
│ │ A weathered skull...         │    │
│ │ Value: 15 gold              │    │
│ └─────────────────────────────┘    │
│ ┌─────────────────────────────┐    │
│ │ 🦴 Bone Shard           LOOT│    │
│ │ Sharp fragment...            │    │
│ │ Value: 5 gold               │    │
│ └─────────────────────────────┘    │
├─────────────────────────────────────┤
│              [TAKE ALL] [F]         │
└─────────────────────────────────────┘
```

## File Structure

```
scripts/
  enemies/
    Enemy.gd              # Modified - corpse state system
    CorpseState.gd        # New - enum and constants
  ui/
    LootBodyUI.gd         # New - based on ChestLootUI
  systems/
    enemy_spawner.gd      # Modified - immediate respawn
    LootTableManager.gd   # New - centralized loot tables

scenes/
  ui/
    loot_body_ui.tscn     # New - corpse loot UI scene
```

## Testing Checklist

- [ ] Enemy dies and freezes on last hurt frame
- [ ] Loot is generated (0-2 items)
- [ ] Gold is awarded immediately on death
- [ ] Corpse is clickable and shows loot UI
- [ ] AOE looting collects from multiple corpses
- [ ] Aggregated UI shows all items correctly
- [ ] Taking items removes them from corpse
- [ ] Empty corpses despawn gracefully
- [ ] Corpses with items decay over 5 minutes
- [ ] Rotted corpses despawn and lose loot
- [ ] Respawn triggers immediately on death
- [ ] New enemy spawns while corpse remains
- [ ] Visual indicators work correctly

## Configuration Constants

```gdscript
# Add to Constants.gd
const AOE_LOOT_RADIUS: float = 300.0  # AOE loot collection radius
const CORPSE_DECAY_TIME: float = 300.0  # 5 minutes in seconds
const CORPSE_FRESH_TIME: float = 60.0  # First minute is "fresh"
const CORPSE_LOOT_GLOW_COLOR: Color = Color(0.8, 1.0, 0.8, 0.5)  # Pale green
```

## Balance Considerations

### Loot Drop Rates
- **0 items**: 40% chance (most corpses are empty)
- **1 item**: 45% chance (common)
- **2 items**: 15% chance (lucky)

### Item Rarity Weights
- **Common**: 70% (bone shards, rusty items)
- **Uncommon**: 25% (skulls, old weapons)
- **Rare**: 4.5% (cursed bones, gems)
- **Epic**: 0.5% (ancient artifacts)

### AOE Radius
300 pixels = ~4-5 corpses in typical combat scenario
- Not too large (would trivialize looting)
- Not too small (would be annoying with many corpses)

## Future Enhancements

1. **Auto-loot option**: Setting to automatically collect loot
2. **Loot filters**: Only show items above certain rarity
3. **Corpse piles**: Multiple corpses combine visually
4. **Necromancy**: Revive corpses as temporary allies
5. **Desecration**: Destroy corpses for bonus resources
6. **Trophy system**: Harvest special parts from corpses
