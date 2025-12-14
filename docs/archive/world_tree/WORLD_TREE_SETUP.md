# World Tree & Chunk Expansion Setup Guide

## ✅ Implementation Status

**Backend**: Complete ✓
- Database tables created
- 8 API endpoints active
- Models integrated
- Migration stamped

**Godot**: Ready for integration
- ChunkExpansionManager.gd created
- Ready to add as autoload

---

## 🗄️ Database Tables

All tables exist and are ready:

| Table | Purpose |
|-------|---------|
| `seed_plots` | Player-claimable territories that trigger expansion |
| `active_chunks` | Tracks loaded chunks per shard (origin vs dynamic) |
| `world_tree_rankings` | Weekly competition winners with blockchain records |
| `world_tree_contributions` | Player contributions per week for scoring |

---

## 🔌 API Endpoints (Live)

All endpoints available at `http://localhost:8000/api/world-tree/`:

### Seed Plot Management
- `GET /seed-plots` - List all plots
- `GET /seed-plots/{chunk_id}` - Get specific plot
- `POST /seed-plots/{chunk_id}/claim` - Claim a plot (costs gold)
- `POST /seed-plots/{chunk_id}/contribute` - Add resources

### Rankings
- `GET /rankings` - Finalized weekly rankings
- `GET /rankings/current` - Live leaderboard
- `GET /rankings/player/{user_id}` - Player's current rank

### Blockchain
- `POST /record` - Record winner on Mantle L2

---

## 🎮 Godot Integration Steps

### 1. Add ChunkExpansionManager as Autoload

**Path**: Project → Project Settings → Autoload

- **Path**: `res://scripts/systems/ChunkExpansionManager.gd`
- **Name**: `ChunkExpansionManager`
- **Enable**: ✓

### 2. Hook Up Contribution Tracking

When players contribute resources to their seed plot:

```gdscript
# Example: Player deposits gold at seed plot
func deposit_gold_to_seed_plot(amount: int):
    var player_chunk = get_current_chunk()

    ChunkExpansionManager.add_contribution(
        player_chunk,
        str(player.user_id),
        {
            "gold": amount,
            "wood": 0,
            "stone": 0,
            "gems": 0,
            "kills": 0,
            "time_minutes": 0
        }
    )
```

### 3. Track Player Time at Seed Plots

```gdscript
# In player script
var _time_at_seed_plot: float = 0.0
var _current_seed_plot: int = -999

func _process(delta: float):
    var current_chunk = int(global_position.x / 8000)

    # Check if player is at a seed plot chunk
    var plot = ChunkExpansionManager.get_seed_plot(current_chunk)
    if plot and plot.owner_id == str(user_id):
        _time_at_seed_plot += delta
        _current_seed_plot = current_chunk

        # Submit time every 5 minutes
        if _time_at_seed_plot >= 300:
            ChunkExpansionManager.add_contribution(
                current_chunk,
                str(user_id),
                {"time_minutes": 5}
            )
            _time_at_seed_plot = 0
```

### 4. Track Kills Near Seed Plot

```gdscript
# In enemy death handler
func _on_enemy_died(enemy_position: Vector2):
    var chunk_id = int(enemy_position.x / 8000)
    var plot = ChunkExpansionManager.get_seed_plot(chunk_id)

    if plot and plot.owner_id == str(player.user_id):
        ChunkExpansionManager.add_contribution(
            chunk_id,
            str(player.user_id),
            {"kills": 1}
        )
```

### 5. Listen to Expansion Events

```gdscript
func _ready():
    ChunkExpansionManager.chunk_expanded.connect(_on_chunk_expanded)
    ChunkExpansionManager.chunk_removed.connect(_on_chunk_removed)
    ChunkExpansionManager.world_tree_ranked.connect(_on_weekly_ranking)
    ChunkExpansionManager.world_tree_promoted.connect(_on_world_tree_promoted)

func _on_chunk_expanded(new_min: int, new_max: int):
    print("🌍 World expanded! New chunks: %d to %d" % [new_min, new_max])
    # Spawn enemies/props in new chunks
    # Update world map UI

func _on_chunk_removed(chunk_id: int):
    print("🌍 Chunk %d removed due to decay" % chunk_id)
    # Despawn entities (handled automatically)

func _on_weekly_ranking(week: int, rankings: Array):
    print("🏆 Weekly rankings calculated!")
    # Show notification to players
    # Update leaderboard UI

func _on_world_tree_promoted(winner_id: String, plot_id: int):
    print("🌳 New World Tree champion: %s" % winner_id)
    # Move tree visual to Chunk -1
    # Show server-wide announcement
```

---

## 📊 Game Mechanics

### Chunk Expansion
1. Origin chunks (-1, 0, 1) are **permanent**
2. Each edge chunk has **one seed plot**
3. When **both** edge plots claimed → world expands by 2 chunks
4. New edge chunks get seed plots → infinite expansion

### Seed Plot Claiming
- **Cost**: Exponential scaling
  - Chunk -1/0/1: 1000 gold (origin)
  - Chunk -2/2: 2000 gold
  - Chunk -3/3: 4000 gold
  - Chunk -4/4: 8000 gold
- **Half price** during decay state

### Contribution Scoring
- Gold: **1 point** each
- Wood/Stone: **5 points** each
- Gems: **50 points** each
- Kills: **2 points** each
- Time: **1 point per hour**

### Decay Timeline
1. **7 days** no contributions → ABANDONED
2. **3 days** warning period → DECAYING (half price reclaim)
3. **3 more days** → chunk removed, players teleported

### Weekly Competition
- **Every Sunday midnight UTC**: Rankings calculated
- **Top seed plot** → Promoted to World Tree (Chunk -1)
- **Winner recorded** on Mantle blockchain
- **Top 10 contributors** get rewards

---

## 🧪 Testing Checklist

### Backend API
- [ ] Start server: `python main.py`
- [ ] Test GET `/api/world-tree/seed-plots`
- [ ] Test claiming seed plot
- [ ] Test contributing resources
- [ ] Test live rankings

### Godot Integration
- [ ] Add ChunkExpansionManager autoload
- [ ] Verify origin chunks (-1, 0, 1) exist
- [ ] Test seed plot claiming UI
- [ ] Test contribution tracking
- [ ] Test chunk expansion trigger
- [ ] Test weekly ranking calculation

---

## 🔗 Related Documentation

- **Full Design**: `docs/DYNAMIC_CHUNK_EXPANSION.md`
- **World Tree Competition**: `docs/WORLD_TREE_COMPETITION.md`
- **Blockchain Integration**: `docs/WORLD_TREE_BLOCKCHAIN_INTEGRATION.md`
- **API Contract**: `docs/API_CONTRACT.md` (version 1.5)
- **Server Capacity**: `docs/SERVER_CAPACITY_ANALYSIS.md`

---

## 🎯 Next Steps

1. **Create Seed Plot Visual**
   - Scene: `scenes/world/SeedPlot.tscn`
   - Shows claim state, owner, contribution score
   - Interaction prompt: "Press F to claim" or "Press F to contribute"

2. **Create World Tree UI**
   - Rankings leaderboard
   - Contribution tracker
   - Weekly timer countdown

3. **Test World Expansion**
   - Claim both edge plots
   - Verify chunks expand
   - Check new seed plots appear

4. **Set Up Weekly Cron**
   - Server runs `ChunkExpansionManager.calculate_weekly_rankings()`
   - Every Sunday 00:00 UTC
   - Records winner on blockchain

---

## ⚠️ Important Notes

- **Don't commit/push** until tested in Godot (per user instructions)
- **Migration already applied** - database is ready
- **Backend routes active** - no restart needed
- **Blockchain recording** currently simulated (implement Web3 later)
- **Player gold deduction** needs integration with player economy system

---

## 📞 Support

If you encounter issues:
1. Check backend logs for API errors
2. Check Godot console for ChunkExpansionManager messages
3. Verify database tables exist: `alembic current`
4. Test API endpoints with curl or Postman

**Status**: Ready for Godot testing! 🚀
