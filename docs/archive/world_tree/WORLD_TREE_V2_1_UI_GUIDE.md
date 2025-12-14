# World Tree v2.1 UI Guide

**Created**: 2024-12-14
**Status**: Initial UI Framework Complete
**Related**: `docs/WORLD_TREE_V2_1_IMPLEMENTATION_STATUS.md`

---

## Overview

The World Tree v2.1 UI provides a comprehensive interface for all new features:
- Seed plot claiming with faction assignment
- Tree management (upgrading, watering, stats)
- Building placement system (6 building types)
- Warehouse management (safe + overflow storage)
- Resource mine management
- Bane system (siege warfare)
- Guild management
- Rankings and leaderboards

---

## Files Created

### 1. **WorldTreeUI.gd** (`scripts/ui/WorldTreeUI.gd`)

Main UI controller script with 7 tabs:

```gdscript
class_name WorldTreeUI
extends CanvasLayer
```

**Features**:
- Modern stone gray theme matching project standards
- Faction-based color coding (5 neutral factions + guild + individual)
- Tree rank progression display (ranks 0-7 with unique colors)
- Warehouse safe/overflow visualization
- Live rankings display

**Signals**:
- `plot_claimed(chunk_id)`
- `tree_upgraded(chunk_id, new_rank)`
- `building_placed(chunk_id, building_type, slot)`
- `warehouse_deposited/withdrawn(chunk_id, resources)`
- `mine_claimed/collected(chunk_id, mine_id)`
- `bane_planted(target_chunk_id, attacker_guild)`
- `guild_changed(chunk_id, new_guild)`

### 2. **WorldTreeUI.tscn** (`scenes/ui/WorldTreeUI.tscn`)

Godot scene file with tab-based layout:
- 800x600 centered panel
- 7 tabs (My Tree, Claim, Buildings, Warehouse, Mines, Bane, Rankings)
- ScrollContainer for each tab content

---

## Tab Breakdown

### Tab 1: My Tree 🌳

**Purpose**: View and manage your claimed tree

**Features**:
- Tree rank display (0-7) with color-coded text
- Faction display with faction colors
- Guild affiliation (if applicable)
- Champion status indicator (⭐ for origin champion trees)
- Upgrade button (if rank < 7)
- Water tree button (shows times watered)
- Growth bonus display (+X%)
- Contribution statistics:
  - Gold/Wood/Stone contributed
  - Kills and Boss Kills
  - Total contribution score

**Empty State**: Shows message to go to Claim tab if unclaimed

### Tab 2: Claim 🌱

**Purpose**: Claim unclaimed seed plots

**Features**:
- Claim cost display (logarithmic formula)
- Chunk distance from origin
- Claim button with cost
- Informational text about claiming benefits:
  - Dual ownership (original owner + current guild)
  - Neutral faction assignment (if unguilded)
  - Starting rank 0 tree
  - Building placement unlocked at rank 1
  - Contribution to weekly rankings

**Already Claimed**: Shows current owner

### Tab 3: Buildings 🏗️

**Purpose**: Place buildings on your tree (rank 1+ required)

**Features**:
- Slot availability display (A-F)
- Building list with:
  - Name
  - Description
  - Cost (5k-30k gold)
  - Place button

**Building Types**:
1. **Campfire** (5,000g) - Free respawn point
2. **Warehouse** (10,000g) - Protected resource storage
3. **Vendor** (15,000g) - Sells potions/gear
4. **Shrine** (20,000g) - Provides buffs
5. **Smithy** (25,000g) - Repairs equipment
6. **Fortress** (30,000g) - Defensive structure

**Locked States**:
- Unclaimed: "Claim this plot first"
- Rank 0: "Upgrade to rank 1 to unlock buildings"

### Tab 4: Warehouse 📦

**Purpose**: Manage protected and overflow storage

**Features**:
- **Safe Storage** (🔒 Protected from raids):
  - Gold: X / 50,000
  - Wood: X / 5,000
  - Stone: X / 5,000
  - Gems: X / 5,000

- **Overflow Storage** (⚠️ Vulnerable):
  - Gold: X (unlimited)
  - Wood: X
  - Stone: X
  - Gems: X

- Deposit button (safe fills first, then overflow)
- Withdraw button (overflow first, then safe)

**Storage Logic** (Fix #6):
- Deposits fill safe storage to limits first
- Excess goes to overflow (raidable)
- Withdrawals take from overflow first
- Safe storage is protected from sieges

### Tab 5: Mines ⛏️

**Purpose**: Claim and collect from resource mines

**Features** (Active Collection - Fix #7):
- Mine claiming UI
- Collection button with cooldown display
- Diminishing returns indicator:
  - First collection: 100%
  - Second: 80%
  - Third: 64%
  - Resets after 30-minute cooldown

**Current Status**: Placeholder until mine spawning system implemented

### Tab 6: Bane ⚔️

**Purpose**: Plant bane stones and manage defense

**Features** (Fix #5, #10):
- **Attack Section**:
  - Plant Bane Stone button (50,000g)
  - Target selection (any tree can be sieged)
  - Bane health: 50,000 HP

- **Defense Section** (if you own the plot):
  - Defense window display (e.g., "20:00 UTC")
  - Change defense time button
  - 1-hour defense window info

**Info Display**:
```
Plant a Bane Stone to siege any tree.
Cost: 50,000 gold
Defense: 1-hour window (defender chooses time)
Win: Claim the tree if Bane survives
Lose: Bane destroyed, defender keeps tree
```

### Tab 7: Rankings 🏆

**Purpose**: View weekly and all-time rankings

**Features**:
- Top 10 current rankings display
- Rank number (gold color for #1)
- Owner ID
- Total score
- Highlights your own ranking

**Display Format**:
```
#1  PlayerName   12,345 pts
#2  AnotherName   9,876 pts
...
```

---

## Color Scheme

### Faction Colors (Fix #4)
```gdscript
const FACTION_COLORS = {
    "azura": Color(0.3, 0.6, 0.9),       # Blue
    "crimson": Color(0.9, 0.3, 0.3),     # Red
    "verdant": Color(0.3, 0.8, 0.3),     # Green
    "obsidian": Color(0.2, 0.2, 0.2),    # Black
    "celestial": Color(0.9, 0.9, 0.5),   # Gold
    "guild": Color(0.7, 0.4, 0.9),       # Purple
    "individual": Color(0.5, 0.5, 0.5)   # Gray
}
```

### Tree Rank Colors (Fix #8)
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

## Integration Steps

### 1. Add to Player Scene

Add WorldTreeUI as a child of your Player or Main scene:

```gdscript
# In Player.gd or Main.gd
@onready var world_tree_ui = $WorldTreeUI

func _ready():
    # Connect signals
    if world_tree_ui:
        world_tree_ui.plot_claimed.connect(_on_plot_claimed)
        world_tree_ui.tree_upgraded.connect(_on_tree_upgraded)
        # ... connect other signals
```

### 2. Open UI on Seed Plot Interaction

```gdscript
# When player interacts with seed plot
func _on_seed_plot_interacted(chunk_id: int):
    if world_tree_ui:
        world_tree_ui.open_for_plot(chunk_id, self)
```

### 3. Handle UI Signals

```gdscript
func _on_plot_claimed(chunk_id: int):
    # Call ChunkExpansionManager to claim plot
    var player_gold = CharacterStats.gold
    var result = ChunkExpansionManager.claim_seed_plot(chunk_id, str(player_id), player_gold)

    if result.success:
        CharacterStats.gold -= result.cost
        print("✅ Claimed plot %d for %dg" % [chunk_id, result.cost])
    else:
        print("❌ Failed to claim: %s" % result.error)

func _on_tree_upgraded(chunk_id: int, new_rank: int):
    # Call backend API to upgrade tree
    # POST /api/world-tree/seed-plots/{chunk_id}/upgrade
    pass

func _on_building_placed(chunk_id: int, building_type: String, slot: String):
    # Call backend API to place building
    # POST /api/world-tree/seed-plots/{chunk_id}/buildings
    pass
```

### 4. Connect to Backend APIs

Each button action should call the appropriate backend endpoint:

```gdscript
# Example: Tree upgrade
func upgrade_tree(chunk_id: int):
    var url = "%s/api/world-tree/seed-plots/%d/upgrade" % [API_URL, chunk_id]
    var headers = ["Authorization: Bearer %s" % auth_token]
    http_request.request(url, headers, HTTPClient.METHOD_POST, "")

# Example: Water tree
func water_tree(chunk_id: int):
    var url = "%s/api/world-tree/seed-plots/%d/water" % [API_URL, chunk_id]
    var headers = ["Authorization: Bearer %s" % auth_token]
    http_request.request(url, headers, HTTPClient.METHOD_POST, "")
```

---

## Future Enhancements

### Dialogs Needed
1. **Slot Selection Dialog** - Choose A-F when placing buildings
2. **Deposit Dialog** - Enter amounts for gold/wood/stone/gems
3. **Withdraw Dialog** - Enter amounts to withdraw
4. **Bane Target Dialog** - Select which tree to siege
5. **Defense Window Dialog** - Select hour (0-23) for defense window

### Additional UI Components
1. **Tree Visualization** - 3D or sprite representation of tree rank
2. **Building Slots** - Visual grid showing A-F slots with buildings
3. **Mine Map** - Show nearby mines on minimap
4. **Bane Status** - Active bane stones attacking/defending
5. **Seasonal Stats Graph** - Contribution over time

### Polish
1. **Animations** - Smooth tab transitions
2. **Sound Effects** - Button clicks, success/failure sounds
3. **Tooltips** - Hover info for buildings, stats, etc.
4. **Icons** - Custom icons for buildings, resources, ranks
5. **Progress Bars** - Visual bars for warehouse limits, tree health, etc.

---

## Testing Checklist

### UI Display
- [ ] UI opens when interacting with seed plot
- [ ] All 7 tabs load without errors
- [ ] Close button works
- [ ] ESC key closes UI
- [ ] Correct tab shows based on plot state (claimed vs unclaimed)

### My Tree Tab
- [ ] Shows "unclaimed" message when plot is empty
- [ ] Displays tree rank with correct color
- [ ] Shows faction with correct color
- [ ] Guild name appears if tree is guilded
- [ ] Champion status shows for origin champion trees
- [ ] Upgrade button appears when rank < 7
- [ ] Water button shows times watered
- [ ] Growth bonus displays correctly
- [ ] Contribution stats are accurate

### Claim Tab
- [ ] Shows claim cost
- [ ] Displays chunk ID and distance
- [ ] Claim button triggers claim action
- [ ] Shows "already claimed" when appropriate

### Buildings Tab
- [ ] Shows "claim first" when unclaimed
- [ ] Shows "upgrade to rank 1" when rank 0
- [ ] Lists all 6 building types
- [ ] Costs are correct (5k-30k)
- [ ] Place button is functional

### Warehouse Tab
- [ ] Safe storage shows current/max correctly
- [ ] Overflow storage shows current amounts
- [ ] Deposit button opens dialog
- [ ] Withdraw button opens dialog

### Mines Tab
- [ ] Shows placeholder message
- [ ] Ready for mine system integration

### Bane Tab
- [ ] Plant Bane button shows correct cost
- [ ] Defense window displays current time
- [ ] Change defense button is functional

### Rankings Tab
- [ ] Shows "no rankings" when empty
- [ ] Displays top 10 rankings
- [ ] Rank #1 is highlighted in gold
- [ ] Scores are formatted correctly

---

## Implementation Status

✅ **Completed**:
- WorldTreeUI.gd script with all 7 tabs
- WorldTreeUI.tscn scene file
- Modern stone gray theme
- Faction and rank color coding
- Basic button handlers
- Signal system for all actions

⏳ **Pending**:
- Dialog windows for complex inputs
- Backend API integration
- Sound effects and animations
- Tree and building visualizations
- Testing and polish

---

## Notes

- The UI follows the project's existing style (stone gray theme)
- All text colors use the standard palette for consistency
- Tab content is dynamically generated to match current plot state
- Placeholder messages guide users when features are locked
- Signal-based architecture allows easy integration with game logic
- All World Tree v2.1 fixes (1-12) are represented in the UI
