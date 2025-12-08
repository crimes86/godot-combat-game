# Combat Systems

This document covers player-vs-player combat and death mechanics.

## Table of Contents

1. [PvP Duel System](#pvp-duel-system)
2. [Player Corpse System](#player-corpse-system)

---

# PvP Duel System

**Status: IMPLEMENTED**

Consensual 1v1 dueling system where both players agree to fight. Players become isolated from outside player damage/healing during the duel. First to 1 HP loses. Both players get a 10-second "safe aura" after the duel ends.

## How to Use

1. Open chat with Enter
2. Type `/duel PlayerName` (or click on player and use context menu)
3. Target player sees popup to Accept/Decline
4. 3-2-1 countdown begins
5. Fight until one player reaches 1 HP
6. Winner/loser announced, both get 10s safe aura

## Core Components

### DuelManager.gd (Autoload Singleton)

Located at: `scripts/systems/DuelManager.gd`

```gdscript
extends Node

signal duel_requested(challenger_id: int, target_id: int)
signal duel_accepted(player1_id: int, player2_id: int)
signal duel_declined(challenger_id: int, target_id: int)
signal duel_started(player1_id: int, player2_id: int)
signal duel_ended(winner_id: int, loser_id: int)
signal countdown_tick(seconds_remaining: int)

const DUEL_REQUEST_TIMEOUT: float = 30.0
const COUNTDOWN_DURATION: int = 3
const SAFE_AURA_DURATION: float = 10.0
const MAX_DUEL_DISTANCE: float = 100.0  # Max distance to initiate
const DUEL_CANCEL_DISTANCE: float = 500.0  # Cancel if players get this far apart

# Active duels: {player_id: opponent_id} - stored both ways for quick lookup
var active_duels: Dictionary = {}

# Pending requests: {target_id: {challenger_id, challenger_name, timestamp}}
var pending_requests: Dictionary = {}

# Safe aura tracking: {player_id: time_remaining}
var safe_aura_timers: Dictionary = {}
```

**Implemented Functions:**
- `request_duel(target_id: int)` - Initiate duel request via /duel command
- `accept_duel(challenger_id: int)` - Accept pending request
- `decline_duel(challenger_id: int)` - Decline pending request
- `is_dueling(player_id: int) -> bool` - Check if player in duel
- `get_duel_opponent(player_id: int) -> int` - Get opponent's ID
- `has_safe_aura(player_id: int) -> bool` - Check safe aura status
- `report_duel_loss()` - Called when player reaches 1 HP
- `request_pvp_damage(target_id, damage)` - RPC for PvP damage
- `apply_pvp_damage(target_id, damage, attacker_id)` - RPC to apply damage

### Player.gd PvP State

```gdscript
# PvP Duel System
var is_dueling: bool = false
var duel_opponent_id: int = -1
var has_safe_aura: bool = false
var duel_aura_node: Node2D = null
var safe_aura_node: Node2D = null
var blood_color: Color = Color(0.6, 0.05, 0.05, 0.9)  # Dark blood red
var pvp_weakpoints: Array = []  # For future weakpoint system
```

**Modified take_damage():**
- Duel isolation: only duel opponent can damage
- Safe aura blocks player damage post-duel
- 1 HP threshold triggers duel loss
- Blood splash particles on PvP hits

**Modified heal():**
- Blocks campfire/ally heals during duel
- Self-heals (potions) still allowed

**New Duel Functions:**
- `enter_duel_state(opponent_id)` - Sets duel state, creates red aura
- `exit_duel_state()` - Clears duel state, removes aura
- `apply_safe_aura()` - Creates green protection aura
- `remove_safe_aura()` - Removes aura after 10s
- `spawn_blood_splash(attacker_id)` - Visual hit effect

### PlayerCombat.gd Modifications

**New Functions:**
- `get_players_in_cone()` - Detect players in attack cone during duel
- `attack_players_in_cone(players)` - Deal damage to duel opponent
- `_get_player_peer_id(target)` - Get peer ID for networking
- `_send_pvp_damage(target, damage)` - Send damage via DuelManager RPC

**Modified attempt_attack():**
- Now checks for players during duels in addition to enemies
- Only targets duel opponent, ignores other players

### Network RPCs

```gdscript
# Client -> Server
@rpc("any_peer", "reliable") func _server_request_duel(target_id)
@rpc("any_peer", "reliable") func _server_accept_duel(challenger_id)
@rpc("any_peer", "reliable") func _server_decline_duel(challenger_id)
@rpc("any_peer", "reliable") func request_pvp_damage(target_id, damage)

# Server -> Clients
@rpc("authority", "call_local", "reliable") func _client_request_received(challenger_id, name)
@rpc("authority", "call_local", "reliable") func _client_request_declined(decliner_id)
@rpc("authority", "call_local", "reliable") func _client_countdown_started(p1, p2, duration)
@rpc("authority", "call_local", "reliable") func _client_duel_ended(winner_id, loser_id)
@rpc("authority", "call_local", "reliable") func apply_pvp_damage(target_id, damage, attacker_id)
```

### UI Components

| Component | Description |
|-----------|-------------|
| **DuelRequestPopup.tscn** | Shows when receiving a duel request. Displays challenger name, Accept/Decline buttons. Auto-declines after 30s. |
| **DuelCountdownUI.tscn** | Center screen countdown overlay. Large "3... 2... 1... FIGHT!" text with both player names. |
| **DuelResultUI.tscn** | Shows winner/loser announcement. "VICTORY!" (green) or "DEFEAT" (red). Fades after 3s. |
| **ChatUI /duel Command** | Type `/duel PlayerName` to challenge. Validates player exists and is in range. |

### Visual Indicators

**Duel Aura (Red):** Pulsing red circle under player indicating active duel state.

**Safe Aura (Green):** Pulsing green circle under player for 10-second post-duel protection.

### Duel Files

**Created:**
- `scripts/systems/DuelManager.gd`
- `scenes/ui/DuelRequestPopup.tscn`
- `scenes/ui/DuelCountdownUI.tscn`
- `scenes/ui/DuelResultUI.tscn`
- `scripts/ui/DuelRequestPopup.gd`
- `scripts/ui/DuelCountdownUI.gd`
- `scripts/ui/DuelResultUI.gd`

**Modified:**
- `scripts/player/Player.gd`
- `scripts/player/PlayerCombat.gd`
- `scripts/ui/ChatUI.gd`
- `project.godot` (autoload)

### Edge Cases

| Scenario | Resolution |
|----------|------------|
| Duel request timeout | Auto-decline after 30s |
| Players too far apart | Cancel duel if >500m apart |
| Player already dueling | Reject new duel requests |
| Player has safe aura | Safe aura removed when new duel starts |
| I-frames during dash | Dash invincibility respected |

### Design Decisions

- **Use current HP** - No reset. Adds tactical depth, timing matters.
- **Allow self-heals** - Potions work during duel
- **Block external heals** - Campfire/ally heals blocked
- **Non-lethal** - Duel ends at 1 HP, no death
- **Safe aura post-duel** - 10 seconds of protection for both players

### Future PvP Enhancements

- [ ] **PvP Weakpoints** - Spawn clickable weakpoints on players during duels
- [ ] Player disconnects mid-duel handling
- [ ] Minimum HP to accept duel?
- [ ] Duel history/stats tracking
- [ ] Gold wager system
- [ ] Ranked dueling / ELO system
- [ ] Duel arenas with special rules
- [ ] Spectator mode
- [ ] Tournament system

---

# Player Corpse System

**Status: IMPLEMENTED**

Classic EverQuest-style corpse system. When a player dies:
1. A corpse spawns at death location with their equipped gear + inventory + gold
2. Player respawns naked at bind point (campfire) with empty inventory
3. Player must return to corpse and loot it to retrieve their items
4. Corpse decays over time - items lost forever if not retrieved

This creates high-stakes death and memorable "corpse runs" - a core survival MMO experience.

### Key Files
- `scripts/world/PlayerCorpse.gd` - Corpse entity with loot, decay, drag system
- `scripts/ui/DeathScreenUI.gd` - "YOU DIED" screen with respawn options
- `scripts/ui/PlayerCorpseLootUI.gd` - Corpse loot retrieval UI
- `scenes/world/PlayerCorpse.tscn` - Corpse scene
- `scenes/ui/DeathScreenUI.tscn` - Death screen scene

## Core Flow

```
[PLAYER DIES]
       |
       v
+------------------------------------------------------+
| 1. Snapshot player state:                            |
|    - All equipped armor (head, chest, legs, etc.)    |
|    - Equipped weapon                                 |
|    - Full inventory contents                         |
|    - Gold                                            |
|    - Character appearance (for corpse visual)        |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 2. Spawn PlayerCorpse at death location              |
|    - Displays player model with all armor equipped   |
|    - Shows player name above corpse                  |
|    - Lootable by owner only                          |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 3. Strip player of everything:                       |
|    - Clear equipped_armor to default clothes         |
|    - Clear equipped_weapon                           |
|    - Clear inventory_items                           |
|    - Set gold to 0                                   |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 4. Respawn player at bind point (campfire)           |
|    - Full health                                     |
|    - Wearing only default clothes                    |
|    - Empty inventory, no gold                        |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 5. Player runs back to corpse                        |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 6. Player loots corpse                               |
|    - Opens PlayerCorpseLootUI                        |
|    - Can retrieve items to inventory                 |
|    - Can re-equip armor directly                     |
|    - Gold auto-collected                             |
+------------------------------------------------------+
       |
       v
+------------------------------------------------------+
| 7. Corpse despawns when empty (or decays)            |
+------------------------------------------------------+
```

## PlayerCorpse Component

```gdscript
extends CharacterBody2D
class_name PlayerCorpse

signal corpse_looted(corpse: PlayerCorpse)
signal corpse_decayed(corpse: PlayerCorpse)

# Owner info
var owner_player_id: int = -1  # Network ID of player who died
var owner_player_name: String = ""
var death_timestamp: float = 0.0

# Stored loot (snapshot at death)
var stored_inventory: Array = []  # Full inventory array
var stored_equipped_armor: Dictionary = {}  # All armor slots
var stored_equipped_weapon = null  # WeaponData or Dictionary
var stored_gold: int = 0

# Visual appearance (to render corpse with armor)
var stored_appearance: Dictionary = {}  # gender, hair, skin, etc.

# Decay timing
const CORPSE_FRESH_TIME: float = 300.0    # 5 minutes - full loot, clear indicator
const CORPSE_DECAY_TIME: float = 1800.0   # 30 minutes - corpse despawns, loot lost
const CORPSE_WARNING_TIME: float = 1500.0 # 25 minutes - warning before decay

# State
enum State { FRESH, DECAYING, ROTTED }
var current_state: State = State.FRESH
```

**Key Functions:**
- `initialize(player, death_pos)` - Snapshot all player data at death
- `can_loot(player_id) -> bool` - Check if player can loot this corpse
- `get_all_loot() -> Dictionary` - Return all loot for UI display
- `remove_item(item, from_equipped, slot)` - Remove item when looted
- `take_gold() -> int` - Take all gold from corpse
- `_is_empty() -> bool` - Check if corpse has no more loot

## PlayerCorpseLootUI

UI for looting your own corpse. Shows equipped gear separately from inventory.

```
+---------------------------------------------+
|  YOUR CORPSE                            [X] |
+---------------------------------------------+
|                                             |
|  EQUIPPED GEAR:                             |
|  +----+ +----+ +----+ +----+ +----+ +----+  |
|  |Head| |Chest| |Arms| |Hands| |Legs| |Feet| |
|  +----+ +----+ +----+ +----+ +----+ +----+  |
|  +----+ +----+                              |
|  |Weap| |Off |                              |
|  +----+ +----+                              |
|                                             |
|  INVENTORY:                                 |
|  +----+----+----+----+----+----+----+----+  |
|  |    |    |    |    |    |    |    |    |  |
|  +----+----+----+----+----+----+----+----+  |
|  |    |    |    |    |    |    |    |    |  |
|  +----+----+----+----+----+----+----+----+  |
|                                             |
|  GOLD: 1,234                                |
|                                             |
|  [TAKE ALL]  [EQUIP ALL & TAKE]             |
+---------------------------------------------+
```

## Decay Stages

| Stage | Time | Visual | Behavior |
|-------|------|--------|----------|
| FRESH | 0-5 min | Full color, slight glow | Clear loot prompt |
| DECAYING | 5-25 min | Faded colors, flies? | Warning to owner |
| WARNING | 25-30 min | Flashing, urgent | "Corpse decaying!" notification |
| ROTTED | 30+ min | Despawns | All loot lost forever |

## XP Loss on Death

When a player dies, they lose 10% of their current level's XP progress.

```gdscript
const DEATH_XP_PENALTY_PERCENT: float = 0.10  # 10% of current level XP

func apply_death_xp_penalty() -> void:
    var xp_for_current_level = CharacterStats.get_xp_for_level(CharacterStats.level)
    var xp_for_next_level = CharacterStats.get_xp_for_level(CharacterStats.level + 1)
    var level_xp_range = xp_for_next_level - xp_for_current_level

    var xp_penalty = int(level_xp_range * DEATH_XP_PENALTY_PERCENT)
    var new_xp = max(xp_for_current_level, CharacterStats.experience - xp_penalty)
    CharacterStats.experience = new_xp
```

**Notes:**
- Can't lose a level from XP penalty (floor at level threshold)
- 10% is harsh but fair - makes death meaningful

## Corpse Dragging System

Group members (or anyone with consent) can drag a corpse to a safer location.

### Consent Flow

1. Player A approaches Player B's corpse
2. Player A presses [G] to request drag
3. Player B (on death screen) sees: "PlayerA wants to drag your corpse" [Allow] [Deny]
4. If allowed, drag starts. Dragger moves at 50% speed.
5. Corpse follows DRAG_DISTANCE (40px) behind dragger.

### Drag Mechanics

```gdscript
var is_being_dragged: bool = false
var dragger_player: Node = null
var drag_consent_granted: Dictionary = {}  # player_id -> bool

const DRAG_SPEED_MULTIPLIER: float = 0.5  # Dragger moves at 50% speed
const DRAG_DISTANCE: float = 40.0  # Corpse follows this far behind dragger
const DRAG_REQUEST_TIMEOUT: float = 30.0  # Consent request expires
```

## Death Screen UI

Player stays on death screen watching their corpse until they choose to release.

```
                +-------------------------------------+
                |           YOU DIED                  |
                |                                     |
                |   Corpse location: (1245, -892)     |
                |   (Being dragged by PlayerName)     |
                |                                     |
                |   PlayerName wants to drag          |
                |   your corpse                       |
                |                                     |
                |     [ALLOW]      [DENY]             |
                |                                     |
                |      [RELEASE TO CAMPFIRE]          |
                +-------------------------------------+

    (Camera stays centered on corpse - player watches their body)
```

**Behavior:**
- Camera locks to corpse position
- Camera follows corpse if being dragged
- Coordinates update in real-time
- Can accept/deny drag requests before releasing
- "Release to Campfire" sends player to home bind point
- XP loss applied on death (not on release)

## Network Considerations

### Server Authority
- **Corpse creation**: Server spawns corpse, syncs to all clients
- **Corpse data**: Server stores authoritative loot data
- **Loot actions**: Client requests loot, server validates and syncs

### Corpse RPCs
```gdscript
# Player death -> Server creates corpse
@rpc("any_peer", "call_remote", "reliable")
func server_player_died(player_id: int, death_position: Vector2)

# Client wants to loot corpse
@rpc("any_peer", "call_remote", "reliable")
func server_request_corpse_loot(corpse_id: int)

# Client takes item from corpse
@rpc("any_peer", "call_remote", "reliable")
func server_take_corpse_item(corpse_id: int, item_index: int, from_equipped: bool, slot: String)

# Server syncs corpse state
@rpc("authority", "call_remote", "reliable")
func client_sync_corpse_state(corpse_id: int, corpse_data: Dictionary)
```

### Drag RPCs
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func server_request_drag_consent(corpse_id: int, requester_id: int)

@rpc("any_peer", "call_remote", "reliable")
func server_drag_consent_response(corpse_id: int, requester_id: int, allowed: bool)

@rpc("authority", "call_remote", "reliable")
func client_corpse_drag_started(corpse_id: int, dragger_id: int)

@rpc("authority", "call_remote", "reliable")
func client_corpse_drag_stopped(corpse_id: int, final_position: Vector2)
```

## Edge Cases

| Scenario | Resolution |
|----------|------------|
| Player dies while corpse exists | Creates second corpse (multiple corpses allowed) |
| Player disconnects with corpse | Corpse persists, timer continues |
| Player reconnects | Can see/loot their corpses |
| Corpse in dangerous area | Player's problem - adds tension |
| Inventory full when looting | Take what fits, leave rest |

## Design Decisions

- **Group members cannot loot corpse** - Only owner can loot (for now)
- **Group members CAN drag corpse** - With consent system
- **No minimap marker** - Hardcore, remember where you died
- **XP loss on death** - Percentage of current level XP lost

## Future Death Enhancements

- [ ] "Summon Corpse" ability or NPC service
- [ ] Corpse decay protection consumable
- [ ] Grave markers (permanent memorial)
- [ ] Death recap UI (what killed you, damage breakdown)
- [ ] Corpse insurance (pay gold to reduce loss)
- [ ] Level loss on death? (Hardcore mode)
- [ ] Corpse persistence across server restart

---

## Files Summary

### PvP Duel System Files
| File | Purpose |
|------|---------|
| `scripts/systems/DuelManager.gd` | Duel logic autoload |
| `scenes/ui/DuelRequestPopup.tscn` | Request popup scene |
| `scenes/ui/DuelCountdownUI.tscn` | Countdown overlay |
| `scenes/ui/DuelResultUI.tscn` | Result announcement |
| `scripts/ui/DuelRequestPopup.gd` | Request popup logic |
| `scripts/ui/DuelCountdownUI.gd` | Countdown logic |
| `scripts/ui/DuelResultUI.gd` | Result logic |

### Player Corpse System Files
| File | Purpose |
|------|---------|
| `scripts/world/PlayerCorpse.gd` | Corpse entity |
| `scenes/world/PlayerCorpse.tscn` | Corpse scene |
| `scripts/ui/DeathScreenUI.gd` | Death screen logic |
| `scenes/ui/DeathScreenUI.tscn` | Death screen scene |
| `scripts/ui/PlayerCorpseLootUI.gd` | Loot UI logic |

### Modified Files (Both Systems)
| File | Modifications |
|------|---------------|
| `scripts/player/Player.gd` | Duel state, death handling, corpse spawning |
| `scripts/player/PlayerCombat.gd` | PvP attack detection |
| `scripts/systems/CharacterStats.gd` | Equipment reset, snapshots |
| `scripts/systems/InventorySystem.gd` | Clear all, snapshots |
| `scripts/ui/ChatUI.gd` | /duel command |
| `project.godot` | DuelManager autoload |
