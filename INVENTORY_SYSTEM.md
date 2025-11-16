# Inventory System Documentation

## Overview

The RhythmRPG inventory system manages item collection, storage, and loot distribution. It features a global inventory accessible throughout the game, pickable items in the world, treasure chests with randomized loot, and a sophisticated loot drop system.

## Architecture

### Core Components

1. **InventorySystem (Autoload)** - `scripts/systems/InventorySystem.gd`
   - Global inventory management
   - Item addition and tracking
   - Gold currency system

2. **PickableItem** - `scripts/items/PickableItem.gd`
   - Individual items dropped in the world
   - Interactive prompts ([F] to pick up)
   - Auto-collection on proximity

3. **TreasureChest** - `scripts/items/TreasureChest.gd`
   - Container for multiple items
   - Open/close animations
   - Loot generation
   - One-time opening mechanic

4. **LootSpawnManager (Autoload)** - `scripts/systems/LootSpawnManager.gd`
   - Enemy loot drop tables
   - Drop chance calculations
   - Loot rarity system

5. **ChestLootUI** - `scripts/ui/ChestLootUI.gd`
   - Visual display of chest contents
   - Item collection interface
   - Gold reward display

---

## System Details

### 1. Global Inventory (InventorySystem.gd)

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

### 2. Pickable Items (PickableItem.gd)

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

### 3. Treasure Chests (TreasureChest.gd)

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

### 4. Loot Drop System (LootSpawnManager.gd)

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

### 5. Chest Loot UI (ChestLootUI.gd)

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

## Integration with Other Systems

### Combat System

When enemies die:
1. Enemy.gd calls LootSpawnManager.spawn_loot()
2. Loot position set to enemy's death location
3. Multiple items can drop simultaneously

### Economy System

- Collected gold tracked by InventorySystem
- Shop/Vendor systems query InventorySystem.get_gold()
- Purchasing items deducts gold from inventory

### Quest System (Future)

- Quest requirements can check InventorySystem.has_item()
- Quest rewards add items via InventorySystem.add_item()

---

## Configuration

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

---

## Future Enhancements

### Planned Features

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

5. **Chest Persistence**
   - Save opened chest states
   - Prevent chest respawning

6. **Loot Animations**
   - Items arc out from enemy/chest
   - Magnetic pull toward player
   - Collection particles/effects

7. **Rare Loot Notifications**
   - Special UI for epic/legendary drops
   - Screen flash for rare finds

---

## Debug Commands

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

## Technical Notes

### Performance Considerations

- **Loot Pooling**: PickableItem nodes are instantiated on demand (not pooled)
- **Cleanup**: Items auto-despawn after 60 seconds if uncollected (future feature)
- **Collision**: Items use Area2D for pickup detection (low overhead)

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

---

## See Also

- [GAME_DOCUMENTATION.md](GAME_DOCUMENTATION.md) - Overall game design
- [GAME_BALANCE.md](GAME_BALANCE.md) - Economy and pricing
- Vendor/Shop system for spending gold
