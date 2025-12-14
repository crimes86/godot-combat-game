# World Tree Competition System

## Overview

Players compete to have their **seed plot tree** promoted to the prestigious **Origin Tree** position in an origin edge chunk, gaining massive bonuses and prestige.

```
Origin Chunks (Special - Connected to Campfire):
┌────────────┬────────────┬────────────┐
│  Chunk -1  │  Chunk 0   │  Chunk 1   │
│   (West    │  (Spawn)   │   (East    │
│   Origin)  │            │   Origin)  │
│            │            │            │
│  🌳 WORLD  │  🔥 BASE   │  🌱 Seed   │
│    TREE    │  CAMPFIRE  │    Plot    │
│  (Winner)  │            │            │
└────────────┴────────────┴────────────┘

Dynamic Chunks (Scale with Distance):
┌────────────┬────────────┐     ┌────────────┬────────────┐
│  Chunk -2  │  Chunk -3  │ ... │  Chunk 2   │  Chunk 3   │ ...
│  Lv 6-7    │  Lv 8-9    │     │  Lv 6-7    │  Lv 8-9    │
│  🌱         │  🌱        │     │  🌱        │  🌱        │
└────────────┴────────────┘     └────────────┴────────────┘
```

---

## Core Concepts

### Origin Edge Chunks
- **Chunk -1** (West Origin): Connected to base campfire, **World Tree slot**
- **Chunk 1** (East Origin): Connected to base campfire, standard seed plot
- **Special Properties**:
  - Cannot be removed (permanent)
  - Safe zones (reduced enemy spawns)
  - Proximity to campfire (social hub, teleport access)
  - **Prestige location** for competitive World Tree

### Dynamic Chunks
- **Chunks beyond origin**: -2, -3, 2, 3, etc.
- **Scale with distance**: Higher level enemies, better loot, harder content
- **Standard seed plots**: Can be claimed, contributed to, compete for World Tree

### World Tree
- **Definition**: The seed plot with the highest contribution score
- **Location**: Promoted to Chunk -1 (West Origin)
- **Duration**: Holds position for 1 week, then recalculated
- **Benefits**: Massive bonuses for the owning guild/players

---

## Competition Mechanics

### Contribution System

Players contribute resources to their claimed seed plot to increase its **Tree Score**:

**Contribution Types**:
| Resource | Points | Notes |
|----------|--------|-------|
| Gold | 1 point/gold | Direct investment |
| Materials (wood, stone) | 5 points/item | Crafting resources |
| Rare materials (gems, relics) | 50 points/item | High value items |
| Enemy kills in chunk | 2 points/kill | Activity bonus |
| Time spent in chunk | 1 point/hour | Presence bonus |
| Buildings constructed | 500 points/building | Future feature |

**Contribution Tracking**:
```gdscript
class TreeContribution:
    var chunk_id: int
    var total_score: int = 0
    var contributors: Dictionary = {}  # {player_id: contribution_amount}
    var weekly_score: int = 0  # Reset every ranking period
    var last_reset: int = 0  # Unix timestamp
    var is_banned: bool = false
```

### Ranking Calculation

**Every Week** (Sunday at midnight UTC):
1. Calculate total weekly score for all eligible trees
2. Exclude banned trees
3. Sort by weekly score (descending)
4. Top tree becomes new World Tree
5. Previous World Tree returns to its original chunk
6. Reset weekly scores for next competition

**Eligibility Requirements**:
- Seed plot must be claimed (state = CLAIMED)
- Not banned from competition
- Minimum 3 unique contributors
- Minimum 1000 weekly score

### Promotion Flow

**When New World Tree is Selected**:
```
1. Previous World Tree (if exists):
   - Remove from Chunk -1
   - Teleport back to original chunk
   - Lose World Tree benefits
   - Keep historical status ("Former World Tree")

2. New World Tree:
   - Copy seed plot data to Chunk -1
   - Apply World Tree visual effects
   - Grant World Tree benefits
   - Broadcast announcement to all players

3. Original Seed Plot:
   - Remains in its chunk (can still be visited)
   - Gains "World Tree Clone" status
   - Contributions still count for next week
```

---

## World Tree Benefits

### For Plot Owner
- **Title**: "World Tree Guardian" (displayed above name)
- **Gold Bonus**: 50% increased gold from all sources
- **XP Bonus**: 25% increased XP from all sources
- **Teleport Access**: Free instant teleport to World Tree from campfire
- **Prestige**: Global announcement, leaderboard prominence

### For Contributors
- **Top 10 Contributors**:
  - Title: "World Tree Champion"
  - 25% gold bonus
  - 15% XP bonus
  - Free teleport to World Tree
- **All Contributors**:
  - Title: "World Tree Supporter"
  - 10% gold bonus
  - Access to exclusive World Tree merchant

### For All Players
- **Social Hub**: World Tree becomes gathering spot
- **Buffs**: Standing near World Tree grants regen buff
- **Quests**: Special weekly quests from World Tree
- **Merchant**: Exclusive shop at World Tree location

---

## Technical Implementation

### Database Schema

**New Table: `tree_contributions`**
```sql
CREATE TABLE tree_contributions (
    contribution_id INTEGER PRIMARY KEY AUTOINCREMENT,
    chunk_id INTEGER NOT NULL,
    player_id TEXT NOT NULL,
    contribution_type TEXT NOT NULL,  -- 'gold', 'material', 'kills', etc.
    amount INTEGER NOT NULL,
    points INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    week_number INTEGER NOT NULL,     -- ISO week number for grouping
    FOREIGN KEY (chunk_id) REFERENCES seed_plots(chunk_id),
    FOREIGN KEY (player_id) REFERENCES players(username)
);

CREATE INDEX idx_contributions_chunk ON tree_contributions(chunk_id, week_number);
CREATE INDEX idx_contributions_player ON tree_contributions(player_id, week_number);
```

**New Table: `world_tree_history`**
```sql
CREATE TABLE world_tree_history (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    chunk_id INTEGER NOT NULL,
    owner_id TEXT NOT NULL,
    week_start INTEGER NOT NULL,
    week_end INTEGER NOT NULL,
    total_score INTEGER NOT NULL,
    top_contributors TEXT NOT NULL,  -- JSON array of top 10 [{player_id, score}]
    FOREIGN KEY (chunk_id) REFERENCES seed_plots(chunk_id),
    FOREIGN KEY (owner_id) REFERENCES players(username)
);
```

**Update: `seed_plots` table**
```sql
ALTER TABLE seed_plots ADD COLUMN is_world_tree BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN is_banned BOOLEAN DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN original_chunk_id INTEGER;  -- For promoted trees
ALTER TABLE seed_plots ADD COLUMN weekly_score INTEGER DEFAULT 0;
ALTER TABLE seed_plots ADD COLUMN last_score_reset INTEGER;
```

### Manager Extension

**Add to `ChunkExpansionManager.gd`**:

```gdscript
# World Tree Competition
const WORLD_TREE_CHUNK: int = -1  # West origin chunk
const RANKING_PERIOD_DAYS: int = 7  # Weekly rankings
const MIN_CONTRIBUTORS: int = 3
const MIN_WEEKLY_SCORE: int = 1000

var current_world_tree: int = -1  # chunk_id of current World Tree
var world_tree_owner: String = ""
var ranking_timer: Timer

func _ready() -> void:
    # ... existing code ...

    # Start weekly ranking timer
    ranking_timer = Timer.new()
    ranking_timer.wait_time = 3600.0  # Check every hour
    ranking_timer.timeout.connect(_check_ranking_schedule)
    add_child(ranking_timer)
    ranking_timer.start()

    # Load current World Tree
    load_current_world_tree()

func load_current_world_tree() -> void:
    """Load the current World Tree from database"""
    var db = DatabaseManager
    var result = db.query_single(
        "SELECT chunk_id, owner_id FROM seed_plots WHERE is_world_tree = 1 AND shard_id = ?",
        [db.get_shard_id()]
    )

    if result:
        current_world_tree = result.chunk_id
        world_tree_owner = result.owner_id
        print("🌳 Current World Tree: Chunk %d (Owner: %s)" % [current_world_tree, world_tree_owner])

func contribute_to_tree(chunk_id: int, player_id: String, type: String, amount: int) -> void:
    """Record a contribution to a seed plot tree"""

    if not seed_plots.has(chunk_id):
        return

    var plot = seed_plots[chunk_id]
    if plot.state != "CLAIMED":
        return

    # Calculate points based on contribution type
    var points = calculate_contribution_points(type, amount)

    # Save to database
    var db = DatabaseManager
    var now = Time.get_unix_time_from_system()
    var week_number = Time.get_date_dict_from_unix_time(now)["weekday"]  # ISO week

    db.execute("""
        INSERT INTO tree_contributions
        (chunk_id, player_id, contribution_type, amount, points, timestamp, week_number)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, [chunk_id, player_id, type, amount, points, now, week_number])

    # Update weekly score
    plot.weekly_score += points
    save_seed_plot(plot)

    # Broadcast contribution
    _broadcast_tree_contribution.rpc(chunk_id, player_id, points)

func calculate_contribution_points(type: String, amount: int) -> int:
    """Calculate points for a contribution"""
    match type:
        "gold":
            return amount  # 1:1
        "wood", "stone":
            return amount * 5
        "gem", "relic":
            return amount * 50
        "enemy_kill":
            return amount * 2
        "time_spent":
            return amount  # 1 point per hour
        "building":
            return amount * 500
        _:
            return 0

func _check_ranking_schedule() -> void:
    """Check if it's time for weekly ranking recalculation"""
    var now = Time.get_unix_time_from_system()
    var current_time = Time.get_datetime_dict_from_unix_time(now)

    # Check if it's Sunday at midnight UTC
    if current_time["weekday"] == 0 and current_time["hour"] == 0:
        # Check if we already ran this week
        var last_reset = get_last_ranking_reset()
        var hours_since_reset = (now - last_reset) / 3600.0

        if hours_since_reset >= 168:  # 7 days
            recalculate_world_tree()

func recalculate_world_tree() -> void:
    """Recalculate World Tree winner and promote"""
    print("🌳 Recalculating World Tree rankings...")

    # Get all eligible trees
    var eligible_trees = get_eligible_trees()

    if eligible_trees.is_empty():
        print("⚠️ No eligible trees for World Tree competition")
        return

    # Sort by weekly score
    eligible_trees.sort_custom(func(a, b): return a.weekly_score > b.weekly_score)

    var winner = eligible_trees[0]

    # Check if winner changed
    if winner.chunk_id != current_world_tree:
        promote_world_tree(winner)
    else:
        print("🌳 Current World Tree retained position")

    # Save to history
    save_world_tree_history(winner)

    # Reset weekly scores
    reset_weekly_scores()

    # Broadcast results
    _broadcast_world_tree_rankings.rpc(eligible_trees)

func get_eligible_trees() -> Array:
    """Get all trees eligible for World Tree competition"""
    var db = DatabaseManager
    var trees = []

    # Get all claimed, non-banned plots with weekly scores
    var results = db.query("""
        SELECT
            chunk_id,
            owner_id,
            weekly_score,
            (SELECT COUNT(DISTINCT player_id)
             FROM tree_contributions
             WHERE tree_contributions.chunk_id = seed_plots.chunk_id
               AND week_number = ?) as contributor_count
        FROM seed_plots
        WHERE state = 'CLAIMED'
          AND is_banned = 0
          AND shard_id = ?
          AND weekly_score >= ?
    """, [get_current_week(), db.get_shard_id(), MIN_WEEKLY_SCORE])

    for row in results:
        if row.contributor_count >= MIN_CONTRIBUTORS:
            trees.append({
                "chunk_id": row.chunk_id,
                "owner_id": row.owner_id,
                "weekly_score": row.weekly_score,
                "contributor_count": row.contributor_count
            })

    return trees

func promote_world_tree(winner: Dictionary) -> void:
    """Promote a tree to World Tree status"""

    # Demote previous World Tree
    if current_world_tree != -1:
        demote_world_tree(current_world_tree)

    var db = DatabaseManager

    # If winner is already in World Tree chunk, just mark it
    if winner.chunk_id == WORLD_TREE_CHUNK:
        db.execute("UPDATE seed_plots SET is_world_tree = 1 WHERE chunk_id = ? AND shard_id = ?",
            [WORLD_TREE_CHUNK, db.get_shard_id()])
    else:
        # Copy winner to World Tree chunk
        var winner_plot = seed_plots[winner.chunk_id]

        # Save original chunk ID
        db.execute("""
            UPDATE seed_plots
            SET is_world_tree = 1,
                original_chunk_id = ?
            WHERE chunk_id = ? AND shard_id = ?
        """, [winner.chunk_id, WORLD_TREE_CHUNK, db.get_shard_id()])

        # Mark original as clone
        db.execute("""
            UPDATE seed_plots
            SET is_world_tree = 0
            WHERE chunk_id = ? AND shard_id = ?
        """, [winner.chunk_id, db.get_shard_id()])

    # Update state
    current_world_tree = winner.chunk_id
    world_tree_owner = winner.owner_id

    # Spawn World Tree visuals
    spawn_world_tree_visual(WORLD_TREE_CHUNK)

    # Grant benefits to owner and contributors
    apply_world_tree_benefits(winner.chunk_id)

    # Global announcement
    _broadcast_world_tree_promoted.rpc(winner.chunk_id, winner.owner_id, winner.weekly_score)

    print("🌳 NEW WORLD TREE: Chunk %d (Owner: %s, Score: %d)" %
        [winner.chunk_id, winner.owner_id, winner.weekly_score])

func demote_world_tree(chunk_id: int) -> void:
    """Demote current World Tree"""
    var db = DatabaseManager

    # Get original chunk
    var result = db.query_single(
        "SELECT original_chunk_id FROM seed_plots WHERE chunk_id = ? AND shard_id = ?",
        [WORLD_TREE_CHUNK, db.get_shard_id()]
    )

    # Remove World Tree status
    db.execute("UPDATE seed_plots SET is_world_tree = 0, original_chunk_id = NULL WHERE chunk_id = ? AND shard_id = ?",
        [WORLD_TREE_CHUNK, db.get_shard_id()])

    # Remove visual
    despawn_world_tree_visual(WORLD_TREE_CHUNK)

    # Remove benefits
    remove_world_tree_benefits(chunk_id)

    print("🍂 World Tree demoted from Chunk %d" % chunk_id)

func apply_world_tree_benefits(chunk_id: int) -> void:
    """Grant World Tree benefits to owner and contributors"""
    var db = DatabaseManager

    # Get owner
    var plot = seed_plots[chunk_id]
    var owner_id = plot.owner_id

    # Grant owner title and bonuses
    db.execute("""
        UPDATE players
        SET title = 'World Tree Guardian',
            gold_multiplier = 1.5,
            xp_multiplier = 1.25
        WHERE username = ?
    """, [owner_id])

    # Get top 10 contributors
    var top_contributors = db.query("""
        SELECT player_id, SUM(points) as total_points
        FROM tree_contributions
        WHERE chunk_id = ? AND week_number = ?
        GROUP BY player_id
        ORDER BY total_points DESC
        LIMIT 10
    """, [chunk_id, get_current_week()])

    # Grant champion benefits
    for i in range(top_contributors.size()):
        var contributor = top_contributors[i]
        db.execute("""
            UPDATE players
            SET title = 'World Tree Champion',
                gold_multiplier = 1.25,
                xp_multiplier = 1.15
            WHERE username = ?
        """, [contributor.player_id])

func reset_weekly_scores() -> void:
    """Reset weekly scores for all trees"""
    var db = DatabaseManager
    db.execute("UPDATE seed_plots SET weekly_score = 0, last_score_reset = ? WHERE shard_id = ?",
        [Time.get_unix_time_from_system(), db.get_shard_id()])

    for chunk_id in seed_plots:
        seed_plots[chunk_id].weekly_score = 0

func ban_tree(chunk_id: int, reason: String) -> void:
    """Ban a tree from World Tree competition"""
    var db = DatabaseManager
    db.execute("UPDATE seed_plots SET is_banned = 1 WHERE chunk_id = ? AND shard_id = ?",
        [chunk_id, db.get_shard_id()])

    if seed_plots.has(chunk_id):
        seed_plots[chunk_id].is_banned = true

    _broadcast_tree_banned.rpc(chunk_id, reason)
    print("🚫 Tree in Chunk %d banned from competition: %s" % [chunk_id, reason])

func unban_tree(chunk_id: int) -> void:
    """Unban a tree"""
    var db = DatabaseManager
    db.execute("UPDATE seed_plots SET is_banned = 0 WHERE chunk_id = ? AND shard_id = ?",
        [chunk_id, db.get_shard_id()])

    if seed_plots.has(chunk_id):
        seed_plots[chunk_id].is_banned = false

    print("✅ Tree in Chunk %d unbanned" % chunk_id)

func get_current_week() -> int:
    """Get current ISO week number"""
    var now = Time.get_unix_time_from_system()
    return Time.get_date_dict_from_unix_time(now)["weekday"]

# Network RPCs
@rpc("authority", "call_local")
func _broadcast_tree_contribution(chunk_id: int, player_id: String, points: int) -> void:
    print("🌱 %s contributed %d points to Chunk %d" % [player_id, points, chunk_id])

@rpc("authority", "call_local")
func _broadcast_world_tree_promoted(chunk_id: int, owner_id: String, score: int) -> void:
    print("🌳 NEW WORLD TREE! Chunk %d (Owner: %s) promoted with %d points!" %
        [chunk_id, owner_id, score])

@rpc("authority", "call_local")
func _broadcast_world_tree_rankings(rankings: Array) -> void:
    print("📊 World Tree Rankings Updated")
    for i in range(min(5, rankings.size())):
        var tree = rankings[i]
        print("  #%d: Chunk %d - %d points" % [i+1, tree.chunk_id, tree.weekly_score])

@rpc("authority", "call_local")
func _broadcast_tree_banned(chunk_id: int, reason: String) -> void:
    print("🚫 Tree in Chunk %d banned: %s" % [chunk_id, reason])
```

---

## Visual Indicators

### World Tree Visual
```gdscript
# WorldTree.gd - Massive ancient tree visual at World Tree location
extends Node2D

var particles: GPUParticles2D
var glow: PointLight2D
var trunk_sprite: Sprite2D

func _ready():
    # Massive tree trunk
    trunk_sprite = Sprite2D.new()
    trunk_sprite.texture = load("res://assets/environment/world_tree.png")
    trunk_sprite.scale = Vector2(3.0, 3.0)
    add_child(trunk_sprite)

    # Golden glow
    glow = PointLight2D.new()
    glow.texture = preload("res://assets/effects/point_light.png")
    glow.color = Color(1.0, 0.9, 0.3)  # Golden
    glow.energy = 2.0
    glow.texture_scale = 5.0
    add_child(glow)

    # Magical particles
    particles = GPUParticles2D.new()
    particles.amount = 100
    particles.lifetime = 3.0
    particles.emitting = true
    # ... particle configuration for golden leaves falling
    add_child(particles)

    # Pulsing animation
    var tween = create_tween()
    tween.set_loops()
    tween.tween_property(glow, "energy", 2.5, 2.0)
    tween.tween_property(glow, "energy", 2.0, 2.0)
```

### Seed Plot Contribution UI
```gdscript
# In SeedPlot.gd, add contribution UI
var contribution_ui: PanelContainer

func create_contribution_ui():
    contribution_ui = PanelContainer.new()
    # ... create buttons for:
    # - Contribute Gold
    # - Contribute Materials
    # - View Rankings
    # - View Contributors
```

---

## Player Commands

**Contribute Resources**:
```
/contribute gold 1000        # Contribute 1000 gold to current chunk's tree
/contribute wood 50          # Contribute 50 wood
/contribute [type] [amount]
```

**View Rankings**:
```
/rankings            # Show current week's tree rankings
/rankings history    # Show past winners
/rankings chunk -2   # Show specific chunk's stats
```

**Admin Commands**:
```
/worldtree promote -2       # Manually promote chunk -2
/worldtree ban -3 "reason"  # Ban chunk -3 from competition
/worldtree unban -3         # Unban chunk -3
/worldtree reset            # Reset all weekly scores
```

---

## Achievements

- **First Contributor**: Contribute to any tree
- **Generous Patron**: Contribute 10,000+ points to a tree
- **World Tree Guardian**: Own a World Tree for 1 week
- **World Tree Dynasty**: Own World Tree for 4 consecutive weeks
- **World Tree Champion**: Be top contributor to winning tree
- **Tree Supporter**: Contribute to 5 different trees

---

## Balance Considerations

### Preventing Dominance
- **Diminishing Returns**: Each consecutive week as World Tree reduces bonuses by 10%
- **Catch-Up Mechanic**: Non-World Trees get 25% bonus contribution points
- **Rotation Lock**: Trees can only be World Tree every other week minimum

### Preventing Exploitation
- **Contribution Cap**: Max 10,000 points per player per week
- **Minimum Contributors**: At least 3 unique players must contribute
- **Ban System**: Admins can ban trees for exploiting/cheating

---

## Future Enhancements

1. **Guild Integration**: Guilds can claim trees collectively
2. **Tree Abilities**: World Tree unlocks special guild abilities
3. **Tree Wars**: PvP events to challenge World Tree
4. **Tree Upgrades**: Permanent improvements to trees
5. **Seasonal Events**: Special contribution bonuses during events

---

## Notes

- World Tree should be visually stunning (large particle effects, unique lighting)
- Consider audio ambience for World Tree area (ethereal music)
- Track historical World Tree winners for prestige/bragging rights
- Consider leaderboard UI in-game showing current rankings
- Weekly reset announcement should be dramatic (global notification)
