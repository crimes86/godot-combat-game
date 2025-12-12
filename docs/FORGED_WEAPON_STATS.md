# Forged Weapon Stats System

## Overview

Every forged weapon maintains an **immutable combat biography** - a permanent record of kills, crits, damage, and history. This creates:

1. **Virgin Weapons (0/0/0/0)** - Pristine collectors' items that can never be restored once used
2. **Battle-Tested Weapons** - Tell stories through their stats ("2,847 kills, 12.4% crit rate")
3. **Infinite Progression** - Weapons level forever, gaining power and prestige
4. **Blockchain Provenance** - Stats are periodically committed on-chain for verification

---

## Stat Categories

### 1. Core Kill Stats
```
kills_total        Total enemies killed with this weapon
kills_by_type      Breakdown by enemy type (skeleton, wolf, guardian, etc.)
kills_elite        Elite/Guardian enemy kills
kills_boss         Boss kills (rarer, more prestigious)
kills_pvp          Player kills in PvP (future feature)
```

### 2. Damage Stats
```
damage_total       Lifetime damage dealt
damage_max_hit     Highest single-hit damage ever recorded
damage_overkill    Damage dealt beyond enemy HP (wasted power, fun trivia)
```

### 3. Critical Hit Stats
```
crits_landed           Total critical hits
hits_total             All hits (for calculating crit rate)
crit_rate_lifetime     Calculated: (crits / hits) * 100
weakpoints_destroyed   Crit window weakpoints popped
chain_max_reached      Highest chain level achieved (0-10)
```

### 4. Usage Stats
```
swings_total           Melee attacks made
shots_fired            Gun shots fired
bursts_fired           Battle rifle burst sequences
time_equipped_seconds  Total time spent equipped
sessions_equipped      Number of play sessions used
```

### 5. Negative Stats (Virgin Weapon Value)
```
deaths_equipped    Times player died while using this weapon
misses_total       Attacks that hit nothing
battles_lost       Combat encounters ended in death
show_negative_stats  Toggleable: owner controls visibility to others
```

**Why negative stats matter:** A virgin weapon (0/0/0/0) is pristine and can never be restored. Once you swing it, it's blooded forever. The pool of virgin weapons only shrinks over time.

### 6. Milestone Timestamps
```
first_equipped_at         When first taken into battle
first_kill_at             First blood
first_crit_at             First critical hit
milestone_100_kills_at    Centurion milestone
milestone_1000_kills_at   Slayer milestone
milestone_10000_kills_at  Legend milestone
```

### 7. Level System (Infinite with Soft Cap)
```
level           Current level (no cap)
experience      XP toward next level

XP Formula: experience_to_next = floor(100 * 1.08^level)
  Level 1:   100 XP
  Level 10:  215 XP
  Level 50:  4,690 XP
  Level 100: 219,976 XP

Stat Bonuses:
  Levels 1-50:  +1.0 damage/level, +0.2% crit/level
  Levels 51+:   +0.1 damage/level, +0.02% crit/level (diminishing)

Example totals:
  Level 50:  +50 damage, +10% crit (strong)
  Level 100: +55 damage, +11% crit (modest gain for 50 more levels)
  Level 200: +65 damage, +12% crit (prestige territory)
```

### 8. Per-Weapon Achievements
```
FIRST_BLOOD      First kill
CENTURION        100 kills
SLAYER           1,000 kills
LEGEND           10,000 kills
PERFECTIONIST    100 kills with 0 deaths
CRIT_MASTER      50% lifetime crit rate (min 100 hits)
CHAIN_KING       Reached chain level 10
UNTOUCHED        500 kills with 0 misses
OVERKILL         Single hit dealt 500+ overkill damage
VETERAN          100+ hours equipped
```

### 9. Visual Tiers
```
PRISTINE     0 kills, 0 deaths, 0 misses (virgin)
BLOODED      1+ kills
VETERAN      100+ kills
BATTLE-WORN  1,000+ kills
LEGENDARY    10,000+ kills
MYTHIC       50,000+ kills
```

---

## Display Surfaces

### Quick Tooltip (Inventory Hover)
Shows at-a-glance info:
- Name with level: "Adamant Rail [Lv. 47]"
- Rarity + visual tier: "★★★☆☆ Rare · BATTLE-WORN"
- Kill count + crit rate: "2,847 kills · 12.4% crit"
- Top 2 achievement icons: 🩸💯⚔️
- Virgin badge if pristine: "✧ PRISTINE ✧"

### Inspect Panel (Right-Click)
Full detailed view:
- All quick tooltip info
- Kill breakdown by enemy type
- Damage stats (total, max hit, overkill)
- Crit stats (landed, rate, weakpoints, chain max)
- Usage stats (time equipped, sessions)
- Negative stats (if shown by owner)
- All achievements with unlock dates
- Milestone timestamps
- Level progress bar

### Trade Preview
Buyer-relevant info:
- Name, level, visual tier
- Kill count + crit rate
- Max hit (impressive stat)
- Original forger wallet
- Trade count
- Deaths (if shown) or "[hidden by owner]"

---

## Architecture

### Godot Files

| File | Purpose |
|------|---------|
| `scripts/resources/WeaponStats.gd` | Core stats resource class |
| `scripts/resources/Weapon.gd` | Extended with `is_forged`, `weapon_stats` |
| `scripts/player/PlayerCombat.gd` | Tracking hooks for combat events |
| `scripts/player/Player.gd` | Visual effect application on equip |
| `scripts/systems/WeaponStatsTracker.gd` | Autoload for persistence/sync |
| `scripts/systems/WeaponStatsDisplay.gd` | UI helper for tooltips |
| `scripts/systems/WeaponVisualEvolution.gd` | Evolution tier calculation + effect mapping |
| `scripts/systems/ForgeVisualEffects.gd` | Visual effect definitions + rendering |

### Backend Files

| File | Purpose |
|------|---------|
| `backend/app/models.py` | `WeaponStats` SQLAlchemy model |
| `backend/app/services/weapon_stats_service.py` | CRUD + validation |

### Data Flow

```
Combat Event (kill, crit, hit)
         ↓
PlayerCombat._track_weapon_*()
         ↓
Weapon.weapon_stats.record_*()
         ↓
WeaponStatsTracker (caches in memory)
         ↓
Auto-save to user://weapon_stats/{forged_id}.json (every 5 min)
         ↓
Sync to backend API (batched)
         ↓
Backend validates (increment-only) and stores
         ↓
Periodic on-chain commit (24h or milestone)
```

---

## Anti-Cheat Design

### Client-Side
- Stats only increment, never decrement
- Timestamps set once, never modified
- Achievements append-only

### Server-Side
- `update_weapon_stats()` validates all fields are >= current values
- Milestones only set if currently null
- Experience can decrease (on level up), but level must increase
- IP tracking for audit

### Blockchain
- Periodic commits create immutable checkpoints
- Hash of full stats stored on-chain for verification
- Detects if client stats diverge from last commit

---

## Virgin Weapon Economics

**Why 0/0/0/0 is valuable:**

1. **Pristine Status** - Only achievable at forge time, can never be restored
2. **Achievement Potential** - PERFECTIONIST requires 0 deaths at 100 kills
3. **Collector Appeal** - Like sealed trading cards or mint-condition items
4. **Gifting** - A virgin weapon is a more meaningful gift
5. **Roleplay** - "My blade has never tasted blood... until now"

**Scarcity Model:**
- Every forge creates one virgin weapon
- The moment it's used, it's forever marked
- Total virgin weapons can only decrease over time
- Long-term: virgin legendary weapons become extremely rare

---

## Integration Guide

### 1. Add WeaponStatsTracker to AutoLoad

In Godot: Project > Project Settings > AutoLoad
- Path: `res://scripts/systems/WeaponStatsTracker.gd`
- Name: `WeaponStatsTracker`

### 2. Attach Stats When Equipping Forged Weapons

```gdscript
# When equipping a forged weapon
if weapon.is_forged:
    WeaponStatsTracker.attach_stats_to_weapon(weapon)
    WeaponStatsTracker.on_weapon_equipped(weapon)
```

### 3. Track Kills in Enemy Death Handler

```gdscript
# In Enemy.gd or kill handler
func _on_death():
    # ... existing death logic ...

    # Track kill for forged weapon
    var player = get_tree().get_first_node_in_group("player")
    if player and player.combat_system:
        var is_elite = is_in_group("guardian") or is_in_group("elite")
        var is_boss = is_in_group("boss")
        player.combat_system.track_enemy_killed(enemy_type, is_elite, is_boss)
```

### 4. Track Player Death

```gdscript
# In Player.gd death handler
func _on_player_death():
    if combat_system:
        combat_system.track_player_death()
```

### 5. Track Chain Level

```gdscript
# In chain system when level changes
func _on_chain_level_changed(new_level: int):
    var player = get_tree().get_first_node_in_group("player")
    if player and player.combat_system:
        player.combat_system.track_chain_level(new_level)
```

### 6. Create Database Migration

```bash
cd backend
alembic revision -m "add_weapon_stats_table"
alembic upgrade head
```

### 7. Add API Endpoint

```python
# In backend/app/routes/weapon_stats_routes.py
@router.put("/weapon-stats/{forged_id}")
async def update_stats(forged_id: str, stats: dict, request: Request, db: Session):
    # Validate ownership
    # Call weapon_stats_service.update_weapon_stats()
    # Return updated stats
```

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Soft cap at level 50** | Strong early investment, diminishing returns prevent runaway power |
| **Toggleable negative stats** | Players choose their shame visibility |
| **Increment-only validation** | Prevents stat manipulation |
| **Local-first persistence** | Works offline, syncs when connected |
| **Per-weapon achievements** | Each weapon has its own journey |
| **No stat reset** | Virgin status is permanent and irreversible |
| **PvP kills reserved** | Future-proofed for PvP mode |

---

## FAQ

**Q: Can I reset my weapon to virgin status?**
A: No. Once used, forever marked. That's the point.

**Q: Why track negative stats?**
A: They make virgin weapons valuable and create interesting history.

**Q: Can I hide my death count?**
A: Yes, toggle `show_negative_stats` to hide from other players.

**Q: How often do stats sync to backend?**
A: Every 5 minutes automatically, plus on game exit.

**Q: What happens if I play offline?**
A: Stats save locally and sync when you reconnect.

**Q: Can I cheat my stats higher?**
A: Server validates increments only. You can't decrease kills or remove deaths.

---

## Visual Evolution System

Weapons visually evolve as they gain levels and kills. A virgin weapon has subtle effects, while a mythic weapon has dramatic, unmistakable visual presence.

### Evolution Tiers

| Tier | Level | Kills | Glow | Particles | Trail | Aura |
|------|-------|-------|------|-----------|-------|------|
| VIRGIN | 0 | 0 | 20% | None | No | No |
| BLOODED | 1-10 | 1-99 | 50% | Sparse (30%) | No | No |
| VETERAN | 11-25 | 100-999 | 75% | Moderate (60%) | Yes | No |
| BATTLE-WORN | 26-40 | 1K-9,999 | 100% | Full | Yes | Pulsing |
| LEGENDARY | 41-60 | 10K-49,999 | 125% | Dense (150%) | Long | Strong |
| MYTHIC | 61+ | 50K+ | 150% | Overwhelming (200%) | Max | Massive |

### Theme-Specific Evolution

Each game theme has its own visual evolution path:

- **Dark Souls/Elden Ring**: Ember Path - Weapons glow with increasing fire intensity
- **Hollow Knight**: Void Path - Shadow tendrils and void particles grow
- **Hades**: Infernal Path - Blood red to divine golden overlay
- **Stardew Valley**: Nature Path - Sparkles to rainbow trails
- **Terraria**: Prismatic Path - Terra beams and projectiles
- **Halo**: Spartan Path - Tactical glow to divine light

### Achievement Effects

Per-weapon achievements unlock special visual effects:

| Achievement | Effect |
|-------------|--------|
| FIRST_BLOOD | Blood drip animation |
| SLAYER | Skull orbit |
| LEGEND | Golden crown/halo |
| PERFECTIONIST | Pristine sparkle |
| CRIT_MASTER | Lightning crackle on crits |
| CHAIN_KING | Chain links orbit |

### Implementation Files

| File | Purpose |
|------|---------|
| `scripts/systems/WeaponVisualEvolution.gd` | Tier calculation + effect mapping |
| `scripts/systems/ForgeVisualEffects.gd` | Effect definitions + rendering |
| `scripts/player/Player.gd` | Effect application on equip |

---

## Changelog

- **Dec 2024**: Initial implementation
  - Core stats tracking (kills, damage, crits, usage, negative)
  - Infinite level system with soft cap
  - Per-weapon achievements
  - Visual tier system
  - Local persistence + backend sync
  - Display helpers for tooltips
  - Visual evolution system with theme-specific effects
  - Achievement-unlocked special effects
