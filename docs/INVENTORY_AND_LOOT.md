# Inventory and Loot System - Complete Guide

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Inventory System](#inventory-system)
4. [Loot System](#loot-system)
5. [Corpse Looting System](#corpse-looting-system)
6. [Testing & Debugging](#testing--debugging)
7. [Configuration & Balance](#configuration--balance)
8. [Future Enhancements](#future-enhancements)

---

## Overview

The Dreadland inventory and loot system manages item collection, storage, and distribution across multiple subsystems. It features a global inventory accessible throughout the game, pickable items in the world, treasure chests with randomized loot, a sophisticated enemy loot drop system, and an interactive corpse looting experience.

### Key Features
- **Global Inventory**: Persistent storage for items and gold
- **Pickable Items**: Interactive world items with proximity detection
- **Treasure Chests**: One-time openable containers with tier-based loot
- **Enemy Loot Drops**: Probabilistic item generation on death
- **Corpse Looting**: Visual, interactive looting of enemy bodies with AOE collection
- **Corpse Decay**: Timed despawn system (5-minute decay)

---

## Architecture

### Core Components

#### 1. InventorySystem (Autoload)
**File**: `scripts/systems/InventorySystem.gd`
- Global inventory management
- Item addition and tracking
- Gold currency system

#### 2. PickableItem
**File**: `scripts/items/PickableItem.gd`
- Individual items dropped in the world
- Interactive prompts ([F] to pick up)
- Auto-collection on proximity

#### 3. TreasureChest
**File**: `scripts/items/TreasureChest.gd`
- Container for multiple items
- Open/close animations
- Loot generation
- One-time opening mechanic

#### 4. LootSpawnManager (Autoload)
**File**: `scripts/systems/LootSpawnManager.gd`
- Enemy loot drop tables
- Drop chance calculations
- Loot rarity system

#### 5. ChestLootUI
**File**: `scripts/ui/ChestLootUI.gd`
- Visual display of chest contents
- Item collection interface
- Gold reward display

#### 6. LootBodyUI
**File**: `scripts/ui/LootBodyUI.gd`
- Corpse loot display
- AOE looting interface
- Multiple corpse aggregation

#### 7. Enemy Corpse System
**File**: `scripts/enemies/Enemy.gd`
- Corpse state management
- Loot generation on death
- Decay timer system
- AOE loot collection

---

## Inventory System

### Global Inventory (InventorySystem.gd)

The inventory system is an autoloaded singleton that manages the player's collected items and gold.

#### Core Functions

```gdscript
# Add item to inventory
InventorySystem.add_item(item_name: String, quantity: int = 1) -> void

# Add gold
InventorySystem.add_gold(amount: int) -> void

# Check if player has item
InventorySystem.has_item(item_name: String) -> bool

# Get item quantity
InventorySystem.get_item_count(item_name: String) -> int

# Get current gold
InventorySystem.get_gold() -> int
```

#### Storage Structure

- **Items**: Dictionary mapping item names to quantities
- **Gold**: Single integer value
- **Capacity**: Currently unlimited (no cap implemented)

---

### Pickable Items (PickableItem.gd)

Items that appear in the world and can be collected by the player.

#### Properties

```gdscript
@export var item_name: String = "Gold Coin"
@export var quantity: int = 1
@export var is_gold: bool = false
@export var auto_pickup_radius: float = 50.0  # Proximity collection distance
```

#### Interaction Flow

1. **Player Enters Proximity** (50px radius)
   - Interaction prompt appears: "[F] Pick up {item_name}"
   - Prompt positioned 10px below player's feet

2. **Player Presses F**
   - Item added to InventorySystem
   - Collection sound plays
   - Item despawns from world

3. **Auto-Pickup** (Optional)
   - If player is very close, item can be collected automatically
   - Useful for gold coins and common drops

#### Visual Feedback

- **Sprite**: Simple colored square representing the item
- **Prompt**: White text with black outline, high visibility
- **Animation**: Slight bob/hover effect (future enhancement)

#### Usage Example

```gdscript
# Spawn a health potion
var item = preload("res://scenes/items/pickable_item.tscn").instantiate()
item.item_name = "Health Potion"
item.quantity = 1
item.is_gold = false
item.global_position = Vector2(100, 100)
get_tree().current_scene.add_child(item)
```

---

## Loot System

### Treasure Chests (TreasureChest.gd)

Containers that hold multiple items and gold. Chests can only be opened once.

#### Properties

```gdscript
@export var chest_id: String = ""  # Unique identifier
@export var loot_tier: int = 1  # Determines quality (1-4)
@export var guaranteed_gold: int = 50
@export var item_count: int = 3  # Number of items to generate
```

#### Interaction Flow

1. **Player Approaches Chest**
   - Interaction prompt appears: "[F] Open Chest"
   - Prompt displayed in golden color

2. **Player Opens Chest**
   - Chest sprite changes from closed to open
   - Loot generation occurs
   - ChestLootUI displays contents
   - Chest marked as opened (cannot reopen)

3. **Loot Collection**
   - Items automatically added to inventory
   - Gold automatically added to inventory
   - UI shows each collected item

#### Loot Generation

Chests use the LootSpawnManager to generate contents based on tier:

- **Tier 1** (Zone 1): 10-50 gold, common items
- **Tier 2** (Zone 2): 50-150 gold, uncommon items
- **Tier 3** (Zone 3): 150-300 gold, rare items
- **Tier 4** (Zone 4): 300-500 gold, epic items

#### Visual States

- **Closed**: Default sprite, interactive
- **Open**: Open sprite, non-interactive
- **Persistent State**: Uses `chest_id` to remember opened chests across sessions (future feature)

---

### Loot Drop System (LootSpawnManager.gd)

Manages enemy loot drops and randomized reward distribution.

#### Loot Tables

Each enemy type has a loot table defining:
- **Drop Chance**: Probability of dropping loot (0.0 - 1.0)
- **Gold Range**: Min/max gold that can drop
- **Item Pool**: List of possible item drops with individual chances

#### Drop Mechanics

```gdscript
# Called when enemy dies
LootSpawnManager.spawn_loot(enemy_type: String, position: Vector2, enemy_level: int) -> void
```

**Drop Resolution:**
1. Roll for gold drop (base chance + level modifier)
2. If successful, roll gold amount within range
3. Roll for each item in the pool
4. Spawn PickableItem nodes at enemy position
5. Apply scatter effect (items spread in small radius)

#### Rarity System

Items have weighted drop chances:
- **Common**: 70% chance
- **Uncommon**: 20% chance
- **Rare**: 8% chance
- **Epic**: 2% chance

#### Enemy-Specific Loot Tables

**Skeleton (Zone 1-4)**
```gdscript
{
  "gold_chance": 0.6,
  "gold_min": 5,
  "gold_max": 20,
  "items": [
    {"name": "Bone Shard", "chance": 0.7},
    {"name": "Rusty Sword", "chance": 0.1},
    {"name": "Health Potion", "chance": 0.3}
  ]
}
```

Loot quality scales with enemy level.

---

### Chest Loot UI (ChestLootUI.gd)

Dedicated UI for displaying chest contents when opened.

#### Display Features

- **Title**: "Chest Opened!" header
- **Item List**: Each item with icon and quantity
- **Gold Display**: Total gold received
- **Auto-Close**: UI disappears after 3 seconds

#### Visual Design

- **Background**: Semi-transparent dark panel
- **Text**: White with black outline for readability
- **Layout**: Vertical list, centered on screen
- **Z-Index**: 1000 (always on top)

---

## Corpse Looting System

### Overview

Implementation of a lootable corpse system that provides a visual, interactive looting experience with AOE collection and timed decay.

### Corpse Visual State

- **Death Animation**: Play full "hurt" animation (6 frames)
- **Frozen State**: Freeze on last frame of hurt animation
- **Lootable Indicator**: Visual indicator (glow/outline) when corpse has items
- **Decay State**: Visual changes as 5-minute timer progresses

### Loot Generation on Death

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

### Gold Distribution

**IMPORTANT**: Gold is distributed immediately on death (current behavior maintained)
- Gold awarded instantly to player
- Combat text shows gold amount
- Only items remain on corpse

### AOE Looting System

```gdscript
# When player right-clicks one corpse:
- Find all corpses within AOE_LOOT_RADIUS (e.g., 300 pixels)
- Collect gold from ALL corpses (immediate award)
- Aggregate ALL items from ALL corpses into one UI
- Mark items with corpse source (for visual clarity)
- Open single LootBodyUI showing all aggregated loot
```

### Corpse States

```gdscript
enum CorpseState {
    FRESH,      # 0-60s: Full loot, visible indicator
    DECAYING,   # 60s-5min: Loot available, visual decay
    ROTTED      # 5min+: Despawn, loot lost
}
```

### Interaction Flow

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

### Implementation Details

#### Enemy.gd - Corpse State System

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

#### LootBodyUI.gd - Corpse Loot Display

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

#### Enemy.gd - AOE Loot Collection

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

#### Enemy.gd - Decay System

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

#### enemy_spawner.gd - Spawn System Update

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

### Visual Design

#### Corpse Indicator
- Subtle glow around corpse if it has loot
- Color: Bone white or pale green
- Pulsing animation to draw attention

#### Loot Body UI Theme
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

---

## Testing & Debugging

### Testing Procedures

#### 1. Kill an Enemy
- Attack a skeleton until it dies
- **Expected**: Hurt animation plays, then freezes on last frame
- **Expected**: Gold is awarded immediately (shown in combat text)
- **Expected**: XP is awarded immediately
- **Expected**: Console shows loot generation (0-2 items)

#### 2. Check Corpse Visual State
- Look at the dead skeleton
- **Expected**: Frozen in final hurt pose
- **Expected**: If corpse has loot, you'll see a pulsing pale green glow around it
- **Expected**: Corpse is slightly darker/grayed out compared to living enemies

#### 3. Check Respawn System
- Wait 3 seconds after enemy death
- **Expected**: New skeleton spawns at same location
- **Expected**: Corpse remains in the world (doesn't disappear)
- **Expected**: Both corpse and new enemy exist simultaneously

#### 4. Loot a Single Corpse
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

#### 5. Test AOE Looting
- Kill multiple skeletons near each other (within ~300 pixels)
- Right-click on one corpse
- **Expected**: UI shows "Looting X Bodies" (where X is number of corpses)
- **Expected**: All items from all nearby corpses appear in the list
- **Expected**: Taking items removes them from their respective corpses

#### 6. Test Empty Corpse Despawn
- Loot all items from a corpse
- **Expected**: Corpse fades out gracefully (0.5 second fade)
- **Expected**: Green glow disappears immediately when last item taken
- **Expected**: Corpse despawns after fade completes

#### 7. Test Corpse Decay (Long Test)
- Kill an enemy and don't loot it
- Wait 1 minute
- **Expected**: Corpse transitions to "DECAYING" state
- **Expected**: Corpse becomes more transparent
- **Expected**: Console shows "Corpse is now decaying..."

#### 8. Test Corpse Rot (Very Long Test)
- Leave a corpse unlooted for 5 minutes
- **Expected**: At exactly 5 minutes, corpse starts fade-out (2 second fade)
- **Expected**: Console shows "Corpse fully rotted - despawning with X uncollected items"
- **Expected**: Items are lost (cannot be looted after rot begins)

#### 9. Test Inventory Full
- Fill your inventory to 32/32 slots
- Try to loot items from corpse
- **Expected**: Console shows "Inventory full!" message
- **Expected**: Items remain on corpse
- **Expected**: Can still loot later after making space

#### 10. Test UI Controls
- Open loot UI
- Press ESC
- **Expected**: UI closes
- Press F while UI is open
- **Expected**: All items looted
- Click the X button
- **Expected**: UI closes

### Known Loot Table

#### Skeleton Drops (0-2 items per corpse)

| Item Name | Rarity | Value | Drop Weight | Drop Chance |
|-----------|--------|-------|-------------|-------------|
| Bone Shard | Common | 5 gold | 70 | ~70% |
| Ancient Skull | Uncommon | 15 gold | 25 | ~25% |
| Cursed Femur | Rare | 35 gold | 4 | ~4% |
| Lich's Finger Bone | Epic | 100 gold | 1 | ~1% |

#### Item Count Distribution
- **0 items**: 40% chance (most corpses are empty)
- **1 item**: 45% chance (common)
- **2 items**: 15% chance (lucky drop)

### Debug Console Messages

#### On Enemy Death
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

#### On Corpse Becoming Active
```
💀 Becoming corpse...
  ✅ AI disabled
  ✅ Health bar hidden
  ✅ Collision updated to corpse layer
  ✅ Moved to corpses group
  ✅ Loot indicator added
💀 Corpse state active - will decay in 300s
```

#### On Corpse Click
```
💀 Corpse clicked at (1234.5, 678.9)
📦 Found 2 nearby corpses (AOE radius: 300)
✅ Loot UI opened with 3 total corpses
```

#### On Looting
```
✨ Looted: Bone Shard from corpse
💀 Corpse fully looted - despawning gracefully
```

#### On Decay
```
💀 Corpse is now decaying... (240s remaining)
```

#### On Rot
```
💀 Corpse fully rotted - despawning with 1 uncollected items
```

### Common Issues & Fixes

#### Issue: Corpse immediately despawns
**Fix**: Check Enemy.gd - make sure `become_corpse()` is called instead of `queue_free()`

#### Issue: Can't click corpse
**Fix**: Check collision layer in `become_corpse()` - should be layer 4 (value 8)

#### Issue: No loot UI appears
**Fix**: Check game_world.gd - ensure `setup_corpse_loot_system()` is called in _ready()

#### Issue: UI shows "No loot remaining" immediately
**Fix**: Check loot generation in `generate_corpse_loot()` - items might not be generating

#### Issue: New enemy doesn't spawn
**Fix**: Check enemy_spawner.gd - `died` signal should still trigger respawn

#### Issue: Multiple corpses at same location
**Fix**: This is intended! New enemies spawn while old corpses persist

#### Issue: Corpse never decays
**Fix**: Check `_process()` function - `process_corpse_decay()` might not be called

### Debug Commands

Enable debug mode with F3 to test inventory system:

```gdscript
# Add item manually (console command)
InventorySystem.add_item("Health Potion", 5)

# Add gold manually
InventorySystem.add_gold(1000)

# Check inventory contents
print(InventorySystem.items)
print("Gold: ", InventorySystem.get_gold())
```

---

## Configuration & Balance

### Pickup Radius Tuning

Adjust `auto_pickup_radius` in PickableItem to balance between:
- **Larger radius**: More convenient, less precise
- **Smaller radius**: More intentional collection, can miss items

Current default: 50 pixels

### Loot Drop Rates

Edit loot tables in LootSpawnManager.gd:
```gdscript
func _ready():
    # Example: Increase skeleton gold drops
    loot_tables["skeleton"]["gold_chance"] = 0.8
    loot_tables["skeleton"]["gold_max"] = 50
```

### Chest Tiers

Modify chest loot quality by setting `loot_tier` in scene:
- Zone 1 chests: `loot_tier = 1`
- Zone 2 chests: `loot_tier = 2`
- etc.

### Configuration Constants

```gdscript
# Add to Constants.gd
const AOE_LOOT_RADIUS: float = 300.0  # AOE loot collection radius
const CORPSE_DECAY_TIME: float = 300.0  # 5 minutes in seconds
const CORPSE_FRESH_TIME: float = 60.0  # First minute is "fresh"
const CORPSE_LOOT_GLOW_COLOR: Color = Color(0.8, 1.0, 0.8, 0.5)  # Pale green
```

### Balance Considerations

#### Loot Drop Rates
- **0 items**: 40% chance (most corpses are empty)
- **1 item**: 45% chance (common)
- **2 items**: 15% chance (lucky)

#### Item Rarity Weights
- **Common**: 70% (bone shards, rusty items)
- **Uncommon**: 25% (skulls, old weapons)
- **Rare**: 4.5% (cursed bones, gems)
- **Epic**: 0.5% (ancient artifacts)

#### AOE Radius
300 pixels = ~4-5 corpses in typical combat scenario
- Not too large (would trivialize looting)
- Not too small (would be annoying with many corpses)

---

## Integration with Other Systems

### Combat System

When enemies die:
1. Enemy.gd calls LootSpawnManager.spawn_loot()
2. Loot position set to enemy's death location
3. Multiple items can drop simultaneously
4. Enemy becomes lootable corpse

### Economy System

- Collected gold tracked by InventorySystem
- Shop/Vendor systems query InventorySystem.get_gold()
- Purchasing items deducts gold from inventory

### Equipment System

Inventory items can be equipped:
- **Weapons**: Main hand, off hand
- **Armor Slots**: Head, chest, legs, feet, armguards (arms), hands, cloak
- **Accessories**: Rings, amulets

### Quest System (Future)

- Quest requirements can check InventorySystem.has_item()
- Quest rewards add items via InventorySystem.add_item()

---

## Technical Notes

### Performance Considerations

- **Loot Pooling**: PickableItem nodes are instantiated on demand (not pooled)
- **Cleanup**: Items auto-despawn after 60 seconds if uncollected (future feature)
- **Collision**: Items use Area2D for pickup detection (low overhead)
- **Corpse Limit**: No hard limit, but old corpses auto-despawn after 5 minutes
- **Max Simultaneous Corpses**: Depends on combat, but typically 10-20 max
- **AOE Loot Radius**: 300 pixels = ~4-5 corpses in typical combat
- **Memory**: Each corpse ~500 bytes (minimal overhead)

### Save System Integration

Currently, inventory does NOT persist between sessions. Future implementation will:
- Save items dictionary to save file
- Save gold amount
- Save opened chest IDs

### Multiplayer Considerations

In multiplayer mode:
- Each player has separate inventory
- Loot drops are instanced per player
- Chests have "first to open" rules (future)

### File Structure

```
scripts/
  enemies/
    Enemy.gd              # Modified - corpse state system
    CorpseState.gd        # New - enum and constants
  items/
    PickableItem.gd       # Pickable world items
    TreasureChest.gd      # Treasure chest container
  ui/
    ChestLootUI.gd        # Chest loot display
    LootBodyUI.gd         # Corpse loot display
  systems/
    InventorySystem.gd    # Global inventory (autoload)
    LootSpawnManager.gd   # Loot drop manager (autoload)
    enemy_spawner.gd      # Modified - immediate respawn
    LootTableManager.gd   # Centralized loot tables

scenes/
  items/
    pickable_item.tscn    # Pickable item scene
    treasure_chest.tscn   # Chest scene
  ui/
    chest_loot_ui.tscn    # Chest loot UI scene
    loot_body_ui.tscn     # Corpse loot UI scene
```

---

## Future Enhancements

### Planned Features

#### Inventory System
1. **Inventory Capacity**
   - Maximum item slots
   - Weight/encumbrance system
   - Bag upgrades

2. **Item Categories**
   - Equipment (weapons, armor)
   - Consumables (potions, scrolls)
   - Crafting materials
   - Quest items

3. **Inventory UI**
   - Full inventory screen (I key)
   - Grid-based layout
   - Item tooltips with stats
   - Drag-and-drop support

4. **Item Stacking**
   - Stackable vs non-stackable items
   - Max stack size limits

#### Loot System
1. **Chest Persistence**
   - Save opened chest states
   - Prevent chest respawning

2. **Loot Animations**
   - Items arc out from enemy/chest
   - Magnetic pull toward player
   - Collection particles/effects

3. **Rare Loot Notifications**
   - Special UI for epic/legendary drops
   - Screen flash for rare finds

#### Corpse Looting
1. **Auto-loot option**: Setting to automatically collect loot
2. **Loot filters**: Only show items above certain rarity
3. **Corpse piles**: Multiple corpses combine visually
4. **Necromancy**: Revive corpses as temporary allies
5. **Desecration**: Destroy corpses for bonus resources
6. **Trophy system**: Harvest special parts from corpses
7. **Different loot tables per enemy type**
8. **Boss corpses**: Longer decay time, better loot

---

## Testing Checklist

### Inventory System
- [ ] Items add to inventory correctly
- [ ] Gold adds to inventory correctly
- [ ] Item counts update properly
- [ ] Inventory persists across scenes

### Pickable Items
- [ ] Items spawn in world
- [ ] Interaction prompt appears
- [ ] F key picks up items
- [ ] Auto-pickup works within radius
- [ ] Items despawn after collection
- [ ] Collection sound plays

### Treasure Chests
- [ ] Chest opens on first interaction
- [ ] Chest cannot be reopened
- [ ] Loot is generated based on tier
- [ ] Chest UI displays correctly
- [ ] Items are added to inventory

### Corpse Looting
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

---

## See Also

- [GAME_DOCUMENTATION.md](../GAME_DOCUMENTATION.md) - Overall game design
- [GAME_BALANCE.md](../GAME_BALANCE.md) - Economy and pricing
- Vendor/Shop system for spending gold
- Equipment system for wearing items
- Crafting system for combining items
