# World Tree System v2.1

**Status**: ✅ Implemented & Ready for Testing
**Version**: 2.1.0
**Date**: December 14, 2024
**Implementation**: Complete (Database → Backend → Godot → UI)

---

## Quick Links

- **Full Design Specification**: [WORLD_TREE_FINAL_DESIGN_V2.1.md](./WORLD_TREE_FINAL_DESIGN_V2.1.md)
- **Blockchain Integration**: [WORLD_TREE_BLOCKCHAIN_INTEGRATION.md](./WORLD_TREE_BLOCKCHAIN_INTEGRATION.md)
- **Implementation Archive**: `docs/archive/world_tree/` (historical docs)

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Core Features](#core-features)
4. [UI Reference](#ui-reference)
5. [Integration Guide](#integration-guide)
6. [API Reference](#api-reference)
7. [Troubleshooting](#troubleshooting)

---

## Overview

The World Tree system is the player base-building mechanic for Dreadland. Players claim seed plots across the world, grow them into powerful World Trees through contributions (kills, boss kills, gold donations), and compete weekly for the champion tree position.

### What v2.1 Provides

✅ **12 Critical Design Fixes**:
1. Dual ownership (original owner + guild)
2. Champion tree duplication (winner duplicated to origin)
3. Extended decay (90 days for dynamic chunks)
4. Neutral factions (5 auto-assigned factions with 1.5x multiplier)
5. Universal Bane system (any tree can be sieged)
6. Warehouse safe storage (50k gold, 5k resources + overflow)
7. Active mine collection (30min cooldown, diminishing returns)
8. Tree ranks (0-7 progression)
9. All-time leaderboard (seasonal rankings table)
10. Scheduled Bane windows (defender-chosen 1-hour windows)
11. Boss kill tracking (separate from regular kills, 20pts each)
12. Logarithmic claim costs (chunks ±1-3 exponential, ±4+ linear)

✅ **Full Stack Implementation**:
- Database schema with migrations
- Backend API (15 new endpoints)
- Godot game logic (ChunkExpansionManager.gd)
- UI system (WorldTreeUI with 7 tabs)
- Seed plot integration (F key interaction)

---

## Quick Start

### For Players

1. **Obtain a World Tree Seed**: Buy from vendor for 1,000 gold or obtain from quests/achievements
2. **Find a Seed Plot**: Glowing green circles with magical particles in the world
3. **Press F with Seed**: Opens the World Tree UI (shows "[F] Plant Seed" when you have one)
4. **Plant Seed**: Click "Plant Seed & Claim Plot" in the UI to consume seed and claim the plot
5. **My Tree Tab**: View your tree rank, faction, and stats
6. **Contribute**: Kill enemies and bosses near your tree to gain contribution points
7. **Upgrade**: Use gold and resources to increase tree rank (0→7)
8. **Build**: Place buildings (Campfire, Outpost, Tower, Barracks, Keep, Fortress)
9. **Compete**: Weekly rankings determine champion tree (duplicated to chunk -1)

### For Developers

**Adding WorldTreeUI to a Scene**:
```gdscript
# Already added to scenes/player/player.tscn
# The UI is available via:
var world_tree_ui = get_tree().get_first_node_in_group("world_tree_ui")
if world_tree_ui:
    world_tree_ui.open_for_plot(chunk_id, player)
```

**Connecting Signals**:
```gdscript
# In your main game script
@onready var world_tree_ui = $Player/WorldTreeUI

func _ready():
    world_tree_ui.plot_claimed.connect(_on_plot_claimed)
    world_tree_ui.tree_upgraded.connect(_on_tree_upgraded)
    world_tree_ui.building_placed.connect(_on_building_placed)
    # ... connect other signals

func _on_plot_claimed(chunk_id: int):
    # Call backend API to claim plot
    # Deduct gold from player
    # Update ChunkExpansionManager
    pass
```

---

## Core Features

### World Tree Seed Item

**Item**: `world_tree_seed`
**Name**: World Tree Seed
**Price**: 1,000 gold (from vendors)
**Category**: Consumable / Special
**Stack Size**: 1 (one seed per inventory slot)

**How to Obtain**:
- Buy from blacksmith or general vendor for 1,000g
- Quest rewards
- Achievement rewards
- Boss drops (rare)
- Player trading

**Use**:
- Required to claim any seed plot
- Consumed when planting (one-time use)
- Cannot claim a plot without a seed in inventory

This makes seed plots more immersive and creates an economy around claiming:
- Seeds can be traded between players
- Quest rewards can grant free seeds
- Achievements can unlock seeds
- Boss kills might drop seeds as rare loot

### Dual Ownership System

Each tree has two ownership fields:

```gdscript
original_owner_id: String   # Permanent owner, can transfer to guild members
current_guild_id: String    # Tree's guild association, 7-day cooldown to change
```

**Rights**:
- **Original Owner**: Transfer ownership, change guild, delete tree, all permissions
- **Guild Members**: Building placement, warehouse deposit/withdraw, respawn binding

### Neutral Faction System

Unguilded players are auto-assigned to one of 5 neutral factions:

| Faction | Color | Multiplier |
|---------|-------|------------|
| **Azura** | Blue (0.3, 0.6, 0.9) | 1.5x |
| **Crimson** | Red (0.9, 0.3, 0.3) | 1.5x |
| **Verdant** | Green (0.3, 0.8, 0.3) | 1.5x |
| **Obsidian** | Dark (0.2, 0.2, 0.2) | 1.5x |
| **Celestial** | Gold (0.9, 0.9, 0.5) | 1.5x |
| **Guild** | Purple (0.7, 0.4, 0.9) | 1.0x |
| **Individual** | Gray (0.5, 0.5, 0.5) | 1.0x |

Neutral faction trees get **1.5x contribution multiplier** to balance against organized guilds.

### Tree Rank Progression

Trees grow through 8 ranks (0-7):

| Rank | Name | Color | Upgrade Cost |
|------|------|-------|--------------|
| 0 | Seedling | Gray | - |
| 1 | Sapling | Brown | 5,000g |
| 2 | Young | Light Green | 10,000g |
| 3 | Mature | Green | 20,000g |
| 4 | Ancient | Deep Green | 40,000g |
| 5 | Elder | Cyan | 80,000g |
| 6 | Mythic | Purple | 160,000g |
| 7 | Legendary | Gold | 320,000g |

### Champion Tree Duplication

Every Sunday 00:00 UTC:
1. **Winner Declared**: Tree with highest contribution score
2. **Duplication**: Winner tree copied to champion position (chunk -1)
3. **Migration Period**: 7 days to move buildings/warehouse
4. **Previous Champion**: Decays over 14 days if not reelected

### Warehouse System

**Safe Storage** (protected from sieges):
- Gold: 50,000 max
- Wood: 5,000 max
- Stone: 5,000 max
- Gems: 5,000 max

**Overflow Storage** (vulnerable):
- Unlimited capacity
- Lost if tree successfully sieged

### Building System

6 building types with increasing costs:

| Building | Cost | Description |
|----------|------|-------------|
| **Campfire** | 5,000g | Basic respawn point |
| **Outpost** | 10,000g | Small guard tower |
| **Tower** | 15,000g | Defensive structure |
| **Barracks** | 20,000g | Training grounds |
| **Keep** | 25,000g | Fortified building |
| **Fortress** | 30,000g | Maximum defense |

Each tree has 6 building slots (A-F).

### Bane (Siege) System

**Universal Bane**: ANY tree can be sieged (not just champion)

**Process**:
1. **Plant Bane Stone**: 50,000 gold cost
2. **Choose Defense Window**: Defender selects 1-hour window
3. **Siege Battle**: Attackers vs defenders fight during window
4. **Resolution**:
   - Success: Attackers gain ownership + overflow warehouse
   - Failure: Bane stone destroyed, defenders keep tree

**Defender Advantage**: Choosing defense window allows organizing guild defense.

### Contribution Scoring

```gdscript
score = (kills × 1) + (boss_kills × 20) + (gold_donated × 0.01)

# With faction multiplier
if is_neutral_faction:
    score *= 1.5
```

---

## UI Reference

### 7-Tab System

The WorldTreeUI provides 7 tabs for tree management:

#### 1. My Tree 🌳
- **Tree Rank Display**: Shows current rank (0-7) with color coding
- **Faction Display**: Shows faction color and name
- **Guild Affiliation**: Shows current guild (if any)
- **Champion Status**: Indicates if tree is current champion
- **Upgrade Button**: Upgrade to next rank (cost shown)
- **Water Button**: Speed up growth with gold donation
- **Contribution Stats**: Your kills, boss kills, gold donated

#### 2. Claim 🌱
- **Claim Cost**: Logarithmic formula based on chunk distance
- **Chunk Distance**: How far from spawn (chunk 0)
- **Claim Button**: Pay gold to claim plot
- **Info**: Benefits of claiming

**Claim Cost Formula**:
```gdscript
# Chunks ±0-5: 1,000 gold (starting area)
# Chunks ±6-8: Exponential (2k, 4k, 8k)
# Chunks ±9+: Linear (+2k per chunk)
```

#### 3. Buildings 🏗️
- **6 Building Types**: Campfire through Fortress
- **Slot Display**: A-F slots
- **Cost & Description**: For each building
- **Place Buttons**: Select slot and building type

#### 4. Warehouse 📦
- **Safe Storage**: Shows current/max for protected storage
- **Overflow Storage**: Shows vulnerable storage amounts
- **Deposit Buttons**: Transfer from inventory to warehouse
- **Withdraw Buttons**: Transfer from warehouse to inventory

#### 5. Mines ⛏️
- **Mine Claiming**: Claim nearby resource mines
- **Collection**: Collect resources with cooldown
- **Diminishing Returns**: 100% → 80% → 64% per collection
- **Cooldown Reset**: 30 minutes

#### 6. Bane ⚔️
- **Plant Bane Stone**: 50,000 gold to siege another tree
- **Target Selection**: Choose which tree to attack
- **Defense Window**: Set 1-hour window for your tree
- **Status Display**: Shows if tree has active Bane

#### 7. Rankings 🏆
- **Top 10 Leaderboard**: Current week's rankings
- **Your Position**: Highlighted if in top 10
- **Score Display**: Contribution scores
- **Refresh Button**: Update rankings

### Color Schemes

**Faction Colors** (for tree glow and UI elements):
```gdscript
const FACTION_COLORS = {
    "azura": Color(0.3, 0.6, 0.9),      # Blue
    "crimson": Color(0.9, 0.3, 0.3),    # Red
    "verdant": Color(0.3, 0.8, 0.3),    # Green
    "obsidian": Color(0.2, 0.2, 0.2),   # Dark Gray
    "celestial": Color(0.9, 0.9, 0.5),  # Gold
    "guild": Color(0.7, 0.4, 0.9),      # Purple
    "individual": Color(0.5, 0.5, 0.5)  # Gray
}
```

**Rank Colors** (for tree appearance):
```gdscript
const RANK_COLORS = {
    0: Color(0.5, 0.5, 0.5),   # Seedling - Gray
    1: Color(0.6, 0.4, 0.2),   # Sapling - Brown
    2: Color(0.4, 0.6, 0.3),   # Young - Light Green
    3: Color(0.3, 0.7, 0.3),   # Mature - Green
    4: Color(0.3, 0.8, 0.5),   # Ancient - Deep Green
    5: Color(0.5, 0.8, 0.9),   # Elder - Cyan
    6: Color(0.8, 0.7, 0.9),   # Mythic - Purple
    7: Color(0.9, 0.8, 0.4)    # Legendary - Gold
}
```

---

## Integration Guide

### Step 1: Database Migration

```bash
cd backend
alembic upgrade head
```

This creates:
- `resource_mines` table
- `seed_plot_buildings` table
- `bane_stones` table
- `seasonal_rankings` table
- 28 new columns in `seed_plots`

### Step 2: Backend Setup

Backend is already configured with 15 new API endpoints in `backend/app/routes/world_tree_routes.py`.

Key endpoints:
- `POST /api/world-tree/seed-plots/{chunk_id}/claim`
- `POST /api/world-tree/seed-plots/{chunk_id}/upgrade`
- `POST /api/world-tree/seed-plots/{chunk_id}/contribute`
- `POST /api/world-tree/seed-plots/{chunk_id}/buildings`
- `POST /api/world-tree/seed-plots/{chunk_id}/warehouse/deposit`
- `GET /api/world-tree/rankings/seasonal`

### Step 3: Godot Signal Handling

Connect UI signals to game logic:

```gdscript
# scripts/player/Player.gd or Main.gd

@onready var world_tree_ui = $WorldTreeUI
@onready var chunk_manager = get_node("/root/ChunkExpansionManager")
@onready var stats = $CharacterStats

func _ready():
    # Connect WorldTreeUI signals
    world_tree_ui.plot_claimed.connect(_on_plot_claimed)
    world_tree_ui.tree_upgraded.connect(_on_tree_upgraded)
    world_tree_ui.tree_watered.connect(_on_tree_watered)
    world_tree_ui.building_placed.connect(_on_building_placed)
    world_tree_ui.warehouse_deposit.connect(_on_warehouse_deposit)
    world_tree_ui.warehouse_withdraw.connect(_on_warehouse_withdraw)
    world_tree_ui.bane_planted.connect(_on_bane_planted)
    world_tree_ui.guild_changed.connect(_on_guild_changed)

func _on_plot_claimed(chunk_id: int):
    var plot_data = chunk_manager.get_seed_plot(chunk_id)
    var cost = plot_data.get("claim_cost", 1000)

    if stats.gold >= cost:
        # Call backend API
        var result = await NetworkManager.claim_seed_plot(chunk_id)

        if result.success:
            stats.gold -= cost
            chunk_manager.claim_seed_plot(chunk_id, get_player_id())
            world_tree_ui.refresh_plot_data(chunk_id)
            NotificationManager.show("Plot Claimed!", "You claimed chunk %d" % chunk_id)
        else:
            NotificationManager.show("Error", result.message)
    else:
        NotificationManager.show("Insufficient Gold", "Need %dg" % cost)

func _on_tree_upgraded(chunk_id: int, new_rank: int):
    # Similar pattern: check resources → call API → update local state
    pass

func _on_building_placed(chunk_id: int, building_type: String, slot: String):
    # Check cost → call API → update visuals
    pass

# ... implement other handlers
```

### Step 4: Network Integration

Add API calls to your NetworkManager:

```gdscript
# scripts/networking/NetworkManager.gd

func claim_seed_plot(chunk_id: int) -> Dictionary:
    var headers = ["Content-Type: application/json", "Authorization: Bearer " + auth_token]
    var url = "%s/api/world-tree/seed-plots/%d/claim" % [API_URL, chunk_id]

    var response = await http_request.request(url, headers, HTTPClient.METHOD_POST)
    return parse_response(response)

func upgrade_tree(chunk_id: int, new_rank: int) -> Dictionary:
    var headers = ["Content-Type: application/json", "Authorization: Bearer " + auth_token]
    var url = "%s/api/world-tree/seed-plots/%d/upgrade" % [API_URL, chunk_id]
    var body = JSON.stringify({"new_rank": new_rank})

    var response = await http_request.request(url, headers, HTTPClient.METHOD_POST, body)
    return parse_response(response)

# ... add other API methods
```

### Step 5: Visual Integration

Seed plots already exist at `scenes/world/SeedPlot.tscn` and are integrated with WorldTreeUI.

To spawn seed plots programmatically:
```gdscript
# In your world generator or chunk manager
const SeedPlotScene = preload("res://scenes/world/SeedPlot.tscn")

func spawn_seed_plot_at_chunk(chunk_id: int):
    var plot = SeedPlotScene.instantiate()
    plot.chunk_id = chunk_id
    plot.position = Vector2(chunk_id * 8000, 0)  # CHUNK_SIZE = 8000
    world_node.add_child(plot)
```

---

## API Reference

### Core Endpoints

#### Claim Seed Plot
```http
POST /api/world-tree/seed-plots/{chunk_id}/claim
Authorization: Bearer {token}

Response:
{
    "success": true,
    "plot": {
        "chunk_id": 5,
        "state": "claimed",
        "owner_id": "player_123",
        "original_owner_id": "player_123",
        "current_guild_id": null,
        "faction": "azura",
        "tree_rank": 0,
        "claim_cost": 1000
    }
}
```

#### Contribute to Tree
```http
POST /api/world-tree/seed-plots/{chunk_id}/contribute
Authorization: Bearer {token}
Content-Type: application/json

{
    "kills": 50,
    "boss_kills": 2,
    "gold_donated": 10000
}

Response:
{
    "success": true,
    "total_score": 10550,  // (50 × 1) + (2 × 20) + (10000 × 0.01)
    "rank": 3
}
```

#### Upgrade Tree
```http
POST /api/world-tree/seed-plots/{chunk_id}/upgrade
Authorization: Bearer {token}
Content-Type: application/json

{
    "new_rank": 3
}

Response:
{
    "success": true,
    "tree_rank": 3,
    "cost_paid": 20000
}
```

#### Place Building
```http
POST /api/world-tree/seed-plots/{chunk_id}/buildings
Authorization: Bearer {token}
Content-Type: application/json

{
    "building_type": "tower",
    "slot": "C"
}

Response:
{
    "success": true,
    "building": {
        "id": 456,
        "building_type": "tower",
        "slot": "C",
        "health": 100,
        "level": 1
    }
}
```

#### Get Rankings
```http
GET /api/world-tree/rankings/seasonal
Authorization: Bearer {token}

Response:
{
    "success": true,
    "rankings": [
        {
            "rank": 1,
            "guild_id": "guild_abc",
            "score": 125000,
            "chunk_id": 5
        },
        ...
    ],
    "current_week": 202450
}
```

See `backend/app/routes/world_tree_routes.py` for all 15 endpoints.

---

## Troubleshooting

### UI Won't Open at Seed Plot

**Symptom**: Pressing F at seed plot does nothing

**Causes**:
1. WorldTreeUI not added to scene tree
2. WorldTreeUI not in "world_tree_ui" group

**Fix**:
```gdscript
# Verify WorldTreeUI is added to Player or Main scene
# Check scenes/player/player.tscn line 67:
[node name="WorldTreeUI" parent="." instance=ExtResource("6_world_tree")]

# Verify group in WorldTreeUI.gd _ready():
add_to_group("world_tree_ui")
```

### Claim Button Doesn't Work

**Symptom**: Clicking Claim button does nothing

**Causes**:
1. Signal not connected
2. Backend API not responding
3. Insufficient gold

**Fix**:
```gdscript
# Connect signal in parent script
world_tree_ui.plot_claimed.connect(_on_plot_claimed)

# Check handler implementation
func _on_plot_claimed(chunk_id: int):
    print("Claiming chunk %d" % chunk_id)  # Debug
    # ... actual claim logic
```

### Tree Rank Not Updating

**Symptom**: Tree stays at rank 0 after upgrade

**Causes**:
1. Backend not persisting changes
2. ChunkExpansionManager not refreshing
3. Seed plot visual not refreshing

**Fix**:
```gdscript
# After upgrade, refresh both manager and visuals
chunk_manager.upgrade_tree(chunk_id, new_rank)

# Refresh seed plot visuals
var plot = get_tree().get_first_node_in_group("seed_plot_%d" % chunk_id)
if plot:
    plot.refresh_state()
```

### Migration Errors

**Symptom**: Database errors about missing columns

**Fix**:
```bash
# Use smart migration script
cd backend
python run_smart_migration.py

# OR manually run migration
alembic upgrade head
```

### Rankings Not Displaying

**Symptom**: Rankings tab is empty

**Causes**:
1. No contributions yet
2. Backend ranking calculation not running
3. API endpoint not working

**Fix**:
```gdscript
# Check backend logs for ranking calculation
# Verify rankings endpoint:
GET /api/world-tree/rankings/seasonal

# Manually trigger ranking update (dev only):
chunk_manager.calculate_weekly_rankings()
```

---

## File Reference

### Godot Scripts
- `scripts/systems/ChunkExpansionManager.gd` - Core world tree logic
- `scripts/ui/WorldTreeUI.gd` - UI controller (880 lines, 7 tabs)
- `scripts/world/SeedPlot.gd` - Seed plot entity (interaction)

### Godot Scenes
- `scenes/ui/WorldTreeUI.tscn` - UI scene (800x600 panel, 7 tabs)
- `scenes/world/SeedPlot.tscn` - Seed plot entity (Area2D with visuals)
- `scenes/player/player.tscn` - Player (includes WorldTreeUI instance)

### Backend
- `backend/app/models.py` - Database models (SeedPlot, Building, Mine, Bane, Ranking)
- `backend/app/routes/world_tree_routes.py` - API routes (15 endpoints)
- `backend/alembic/versions/8f9a1b2c3d4e_add_world_tree_v2_1_features.py` - Migration

### Documentation
- `docs/WORLD_TREE_V2.1.md` - This file (main reference)
- `docs/WORLD_TREE_FINAL_DESIGN_V2.1.md` - Complete design spec
- `docs/WORLD_TREE_BLOCKCHAIN_INTEGRATION.md` - Blockchain features
- `docs/archive/world_tree/` - Historical docs (v1.x, implementation notes)

---

## Next Steps

### Testing Checklist

- [ ] Open Godot project
- [ ] Run game (F5)
- [ ] Walk to seed plot (glowing green circle)
- [ ] Press F to open UI
- [ ] Verify all 7 tabs display correctly
- [ ] Test claim button (check gold deduction)
- [ ] Test upgrade button (check rank progression)
- [ ] Test building placement
- [ ] Test warehouse deposit/withdraw
- [ ] Verify rankings display
- [ ] Test color schemes (factions and ranks)

### Implementation Checklist

- [x] Database migration
- [x] Backend models
- [x] Backend API routes
- [x] ChunkExpansionManager logic
- [x] WorldTreeUI creation
- [x] Seed plot integration
- [ ] Signal handlers (claim, upgrade, build)
- [ ] Network API calls
- [ ] Gold/resource deduction
- [ ] Visual feedback (particles, animations)
- [ ] Mine spawning system
- [ ] Bane stone entity
- [ ] Weekly ranking calculation
- [ ] Champion tree duplication
- [ ] Guild integration
- [ ] Blockchain recording (optional)

---

**Built with ❤️ using Claude Code**
**Version**: World Tree v2.1.0
**Date**: December 14, 2024
