# PvP Duel System - Implementation Spec

## Status: ✅ IMPLEMENTED

## Overview

Consensual 1v1 dueling system where both players agree to fight. Players become isolated from outside player damage/healing during the duel. First to 1 HP loses. Both players get a 10-second "safe aura" after the duel ends.

---

## How to Use

1. Open chat with Enter
2. Type `/duel PlayerName` (or click on player and use context menu)
3. Target player sees popup to Accept/Decline
4. 3-2-1 countdown begins
5. Fight until one player reaches 1 HP
6. Winner/loser announced, both get 10s safe aura

---

## Core Components

### 1. DuelManager.gd (Autoload Singleton) ✅

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

---

### 2. Player.gd Modifications ✅

**New State Variables:**
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

**Modified take_damage():** ✅
- Duel isolation: only duel opponent can damage
- Safe aura blocks player damage post-duel
- 1 HP threshold triggers duel loss
- Blood splash particles on PvP hits

**Modified heal():** ✅
- Blocks campfire/ally heals during duel
- Self-heals (potions) still allowed

**New Duel Functions:** ✅
- `enter_duel_state(opponent_id)` - Sets duel state, creates red aura
- `exit_duel_state()` - Clears duel state, removes aura
- `apply_safe_aura()` - Creates green protection aura
- `remove_safe_aura()` - Removes aura after 10s
- `spawn_blood_splash(attacker_id)` - Visual hit effect

---

### 3. PlayerCombat.gd Modifications ✅

**New Functions:**
- `get_players_in_cone()` - Detect players in attack cone during duel
- `attack_players_in_cone(players)` - Deal damage to duel opponent
- `_get_player_peer_id(target)` - Get peer ID for networking
- `_send_pvp_damage(target, damage)` - Send damage via DuelManager RPC

**Modified attempt_attack():**
- Now checks for players during duels in addition to enemies
- Only targets duel opponent, ignores other players

---

### 4. Network RPCs ✅

**DuelManager RPCs:**
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

---

### 5. UI Components ✅

**DuelRequestPopup.tscn** ✅
- Shows when receiving a duel request
- Displays: "PlayerName challenges you to a duel!"
- Buttons: [Accept] [Decline]
- Auto-declines after 30 seconds

**DuelCountdownUI.tscn** ✅
- Center screen countdown overlay
- Large "3... 2... 1... FIGHT!" text
- Both player names displayed

**DuelResultUI.tscn** ✅
- Shows winner/loser announcement
- "VICTORY!" (green) or "DEFEAT" (red)
- Shows opponent name and safe aura duration
- Fades after 3 seconds

**ChatUI /duel Command** ✅
- Type `/duel PlayerName` to challenge
- Validates player exists and is in range
- Shows error messages for invalid requests

---

### 6. Visual Indicators ✅

**Duel Aura (Red):**
- Pulsing red circle under player
- Indicates active duel state

**Safe Aura (Green):**
- Pulsing green circle under player
- 10-second post-duel protection
- Blocks incoming player damage

---

## Files Created

| File | Status |
|------|--------|
| `scripts/systems/DuelManager.gd` | ✅ |
| `scenes/ui/DuelRequestPopup.tscn` | ✅ |
| `scenes/ui/DuelCountdownUI.tscn` | ✅ |
| `scenes/ui/DuelResultUI.tscn` | ✅ |
| `scripts/ui/DuelRequestPopup.gd` | ✅ |
| `scripts/ui/DuelCountdownUI.gd` | ✅ |
| `scripts/ui/DuelResultUI.gd` | ✅ |

## Files Modified

| File | Status |
|------|--------|
| `scripts/player/Player.gd` | ✅ |
| `scripts/player/PlayerCombat.gd` | ✅ |
| `scripts/ui/ChatUI.gd` | ✅ |
| `project.godot` (autoload) | ✅ |

---

## Edge Cases Handled

| Scenario | Resolution |
|----------|------------|
| Duel request timeout | Auto-decline after 30s ✅ |
| Players too far apart | Cancel duel if >500m apart ✅ |
| Player already dueling | Reject new duel requests ✅ |
| Player has safe aura | Safe aura removed when new duel starts ✅ |
| I-frames during dash | Dash invincibility respected ✅ |

---

## TODO / Future Enhancements

- [ ] **PvP Weakpoints** - Spawn clickable weakpoints on players during duels (like enemy crit windows)
- [ ] Player disconnects mid-duel handling
- [ ] Minimum HP to accept duel?
- [ ] Duel history/stats tracking
- [ ] Gold wager system
- [ ] Ranked dueling / ELO system
- [ ] Duel arenas with special rules
- [ ] Spectator mode
- [ ] Tournament system

---

## Design Decisions

- [x] **Use current HP** - No reset. Adds tactical depth, timing matters.
- [x] **Allow self-heals** - Potions work during duel
- [x] **Block external heals** - Campfire/ally heals blocked
- [x] **Non-lethal** - Duel ends at 1 HP, no death
- [x] **Safe aura post-duel** - 10 seconds of protection for both players

---

## Future Expansions

- **Ranked dueling** - ELO/ladder system
- **Duel arenas** - Designated zones with special rules
- **Spectator mode** - Watch ongoing duels
- **Tournament system** - Bracket-based competitions
- **Wager system** - Bet gold/items on outcome
