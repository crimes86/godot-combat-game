# Gameplay Telemetry Integration Spec

**Status:** Backend + TelemetryManager Complete - Integration Points Pending
**Priority:** High (Security/Anti-Cheat)
**Affects:** Godot Client + Godot Server (requires rebuild of both)

## What's Done

- ✅ Backend endpoints (`/api/telemetry/*`)
- ✅ `TelemetryManager.gd` updated with gameplay telemetry methods
- ⏳ Integration hooks in Enemy.gd, NetworkEnemyManager.gd (see below)

---

## Overview

The backend now provides gameplay telemetry endpoints for logging kills, loot pickups, and other events. This creates an audit trail for anti-cheat detection without blocking gameplay.

**This is Phase 1 of the security hardening plan.** Events are logged for analysis but not yet validated (validation comes in Phase 2).

---

## New API Endpoints

### `POST /api/telemetry/kill`

Log an enemy kill event.

**Auth:** Bearer token (same as other authenticated endpoints)

**Request Body:**
```json
{
    "enemy_type": "skeleton",
    "enemy_level": 5,
    "enemy_network_id": 12345,
    "xp_granted": 50,
    "gold_dropped": 25,
    "weapon_used": "iron_longsword",
    "was_critical": false,
    "overkill_damage": 10
}
```

**Query Parameters:**
- `session_id` (optional): Game session UUID
- `is_multiplayer` (optional): Boolean
- `zone_id` (optional): Current zone
- `position_x`, `position_y` (optional): World position

**Response:**
```json
{
    "success": true,
    "events_logged": 1,
    "events_flagged": 0
}
```

---

### `POST /api/telemetry/loot`

Log a loot pickup event (gold or item).

**Request Body:**
```json
{
    "loot_type": "gold",
    "source_type": "enemy_corpse",
    "source_id": "12345",
    "gold_amount": 25,
    "item_id": null,
    "item_name": null,
    "item_rarity": null,
    "quantity": 1
}
```

For items:
```json
{
    "loot_type": "item",
    "source_type": "enemy_corpse",
    "source_id": "12345",
    "gold_amount": 0,
    "item_id": "iron_helmet",
    "item_name": "Iron Helmet",
    "item_rarity": "Uncommon",
    "quantity": 1
}
```

**Valid `source_type` values:** `enemy_corpse`, `chest`, `tree`, `rock`, `ground`

---

### `POST /api/telemetry/batch`

Batch multiple events in a single request (more efficient).

**Request Body:**
```json
{
    "session_id": "abc-123-def",
    "client_version": "0.9.5",
    "events": [
        {
            "event_type": "kill",
            "event_data": {
                "enemy_type": "skeleton",
                "enemy_level": 5,
                "xp_granted": 50,
                "gold_dropped": 25
            },
            "zone_id": "graveyard",
            "position_x": 1234.5,
            "position_y": 678.9,
            "client_timestamp": 1704326400.123
        },
        {
            "event_type": "loot",
            "event_data": {
                "loot_type": "gold",
                "source_type": "enemy_corpse",
                "gold_amount": 25
            }
        }
    ]
}
```

---

## Godot Integration Points

### ⚠️ REQUIRES CLIENT REBUILD

The following changes require rebuilding and redistributing the Godot client.

---

### 1. Kill Event Logging

**File:** `scripts/enemies/Enemy.gd`
**Location:** Around line 1549-1574 (in the death/XP grant section)

**Current Code:**
```gdscript
if should_grant_xp:
    var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
    if player and player.has_method("gain_experience"):
        player.gain_experience(xp_reward)
```

**Add After:**
```gdscript
# Log kill to backend telemetry
if AshbaneAuth.is_authenticated():
    var kill_data = {
        "enemy_type": enemy_type,
        "enemy_level": enemy_level,
        "enemy_network_id": get_meta("network_id", 0),
        "xp_granted": xp_reward,
        "gold_dropped": gold_drop,
        "weapon_used": CharacterStats.get_equipped_weapon_id(),
        "was_critical": false,  # TODO: Track if killing blow was crit
        "overkill_damage": 0
    }
    TelemetryManager.log_kill(kill_data)
```

---

### 2. Gold Loot Logging

**File:** `scripts/networking/NetworkEnemyManager.gd`
**Location:** Around line 1677-1706 (`request_loot_gold` function)

**After gold is successfully looted, add:**
```gdscript
# Log gold loot to backend telemetry
if AshbaneAuth.is_authenticated():
    var loot_data = {
        "loot_type": "gold",
        "source_type": "enemy_corpse",
        "source_id": str(enemy_network_id),
        "gold_amount": gold,
        "quantity": 1
    }
    TelemetryManager.log_loot(loot_data)
```

---

### 3. Item Loot Logging

**File:** `scripts/networking/NetworkEnemyManager.gd`
**Location:** Around line 1758-1810 (`request_loot_item` function)

**After item is successfully looted, add:**
```gdscript
# Log item loot to backend telemetry
if AshbaneAuth.is_authenticated():
    var item = JSON.parse_string(item_json)
    var loot_data = {
        "loot_type": "item",
        "source_type": "enemy_corpse",
        "source_id": str(enemy_network_id),
        "gold_amount": 0,
        "item_id": item.get("id", ""),
        "item_name": item.get("name", ""),
        "item_rarity": item.get("rarity", "Common"),
        "quantity": item.get("quantity", 1)
    }
    TelemetryManager.log_loot(loot_data)
```

---

### 4. TelemetryManager (Already Updated ✅)

**File:** `scripts/systems/TelemetryManager.gd` - **ALREADY UPDATED**

The TelemetryManager autoload has been extended with gameplay telemetry methods:

```gdscript
# New methods available:
TelemetryManager.log_kill(enemy_type, enemy_level, xp_granted, gold_dropped, weapon_used, was_critical, overkill_damage, enemy_network_id)
TelemetryManager.log_loot_gold(source_type, source_id, gold_amount)
TelemetryManager.log_loot_item(source_type, source_id, item_id, item_name, item_rarity, quantity)
TelemetryManager.log_resource(resource_type, source_type, amount)
TelemetryManager.get_session_id()
```

**Already registered as Autoload** - no changes needed to `project.godot`.

---

### 5. AshbaneAuth (No Changes Needed ✅)

TelemetryManager handles its own HTTP requests using the existing `AshbaneAuth.auth_token` and `AshbaneAuth.get_api_base()` methods. No changes needed to AshbaneAuth.

---

## Server-Side Changes

### ⚠️ REQUIRES SERVER REBUILD

If running a dedicated Godot server, these same telemetry calls should be added. The server can batch events for all connected players.

**Alternative:** Have the server forward kill/loot events to the backend on behalf of players. This is more secure since the server is trusted.

**Recommended approach for multiplayer:**
1. Client does NOT send telemetry directly
2. Godot server collects events and sends to backend
3. Backend trusts server-reported events more than client-reported

```gdscript
# In NetworkEnemyManager.gd on the SERVER
func _on_enemy_killed(enemy, killer_peer_id):
    # ... existing kill logic ...

    # Server sends telemetry for the killer
    if killer_peer_id > 0:
        var kill_data = {
            "enemy_type": enemy.enemy_type,
            "enemy_level": enemy.enemy_level,
            # ... etc
        }
        # Send to backend with killer's user context
        ServerTelemetry.log_kill_for_player(killer_peer_id, kill_data)
```

---

## Anti-Cheat Detection (Backend)

The backend automatically flags suspicious events:

| Check | Threshold | Flag |
|-------|-----------|------|
| Kill rate | > 60 kills/minute | `Kill rate exceeded` |
| XP per kill | > enemy_level × 200 | `XP too high for enemy level` |
| Gold per kill | > enemy_level × 100 | `Gold too high for enemy level` |
| Loot gold amount | > 50,000 per pickup | `Large gold pickup` |

Flagged events are logged with `is_suspicious = true` for review.

---

## Testing Checklist

1. [x] TelemetryManager autoload registered (already was)
2. [x] TelemetryManager gameplay methods added
3. [ ] Kill events logged in Enemy.gd ⚠️ **REQUIRES CLIENT REBUILD**
4. [ ] Gold loot events logged in NetworkEnemyManager.gd ⚠️ **REQUIRES CLIENT REBUILD**
5. [ ] Item loot events logged in NetworkEnemyManager.gd ⚠️ **REQUIRES CLIENT REBUILD**
6. [ ] Events appear in backend database
7. [ ] Batch submission working (check every 5 seconds)
8. [ ] Suspicious events flagged correctly
9. [ ] Server build updated ⚠️ **REQUIRES SERVER REBUILD**
10. [ ] Client build redistributed

---

## Files Changed Summary

### Backend (Complete ✅)
- `app/models.py` - Added `GameEventLog` model
- `app/routes/telemetry_routes.py` - New file with endpoints
- `app/main.py` - Registered telemetry router
- `alembic/versions/d9e3b2c4f5a6_*.py` - Migration

### Godot Client (Partial ✅)
- `scripts/systems/TelemetryManager.gd` - **UPDATED** with gameplay telemetry
- `scripts/enemies/Enemy.gd` - **TODO:** Add kill logging hook
- `scripts/networking/NetworkEnemyManager.gd` - **TODO:** Add loot logging hooks

### Godot Server (TODO ⚠️ REQUIRES REBUILD)
- Same changes as client will be picked up automatically
- Consider: Centralized server-side telemetry (recommended for security)

---

## Next Steps (Phase 2)

Once telemetry is flowing, Phase 2 adds validation:

1. **Server-stored loot pools** - Backend knows what each corpse contains
2. **Damage validation** - Backend verifies damage amounts
3. **XP verification** - Backend calculates expected XP
4. **Gold balance tracking** - Backend tracks all gold sources

This creates a "trust but verify" system where gameplay continues smoothly but cheaters are detected and flagged.
