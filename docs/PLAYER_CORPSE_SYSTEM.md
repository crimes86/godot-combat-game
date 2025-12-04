# Player Corpse System - Implementation Spec

## Status: ⏳ NOT YET IMPLEMENTED

This is a design specification document. The system has not been built yet.

---

## Overview

Classic EverQuest-style corpse system. When a player dies:
1. A corpse spawns at death location with their equipped gear + inventory + gold
2. Player respawns naked at bind point (campfire) with empty inventory
3. Player must return to corpse and loot it to retrieve their items
4. Corpse decays over time - items lost forever if not retrieved

This creates high-stakes death and memorable "corpse runs" - a core survival MMO experience.

---

## Core Flow

```
[PLAYER DIES]
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 1. Snapshot player state:                            │
│    - All equipped armor (head, chest, legs, etc.)    │
│    - Equipped weapon                                 │
│    - Full inventory contents                         │
│    - Gold                                            │
│    - Character appearance (for corpse visual)        │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 2. Spawn PlayerCorpse at death location              │
│    - Displays player model with all armor equipped   │
│    - Shows player name above corpse                  │
│    - Lootable by owner only (or group members?)      │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 3. Strip player of everything:                       │
│    - Clear equipped_armor to default clothes         │
│    - Clear equipped_weapon                           │
│    - Clear inventory_items                           │
│    - Set gold to 0                                   │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 4. Respawn player at bind point (campfire)           │
│    - Full health                                     │
│    - Wearing only default clothes                    │
│    - Empty inventory, no gold                        │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 5. Player runs back to corpse                        │
│    - Corpse visible on minimap/compass?              │
│    - "Your corpse is X meters away" notification?    │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 6. Player loots corpse                               │
│    - Opens PlayerCorpseLootUI                        │
│    - Can retrieve items to inventory                 │
│    - Can re-equip armor directly                     │
│    - Gold auto-collected                             │
└──────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────┐
│ 7. Corpse despawns when empty (or decays)            │
└──────────────────────────────────────────────────────┘
```

---

## Components

### 1. PlayerCorpse.gd (Scene: PlayerCorpse.tscn)

The physical corpse object in the world.

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

# Interaction
var loot_prompt: Label = null
var is_player_nearby: bool = false
```

**Key Functions:**
```gdscript
func initialize(player: Node, death_pos: Vector2) -> void:
    """Called when corpse is created - snapshot all player data"""
    owner_player_id = player.get_multiplayer_authority()
    owner_player_name = player.player_name  # or NetworkManager.get_player_name()
    global_position = death_pos
    death_timestamp = Time.get_unix_time_from_system()

    # Snapshot inventory (deep copy)
    stored_inventory = InventorySystem.inventory_items.duplicate(true)

    # Snapshot equipped armor (deep copy)
    stored_equipped_armor = CharacterStats.equipped_armor.duplicate(true)

    # Snapshot weapon
    if CharacterStats.equipped_weapon:
        stored_equipped_weapon = CharacterStats.equipped_weapon.duplicate()

    # Snapshot gold
    stored_gold = CharacterStats.gold

    # Snapshot appearance for visual
    stored_appearance = {
        "gender": player.selected_gender,
        "hair_style": player.selected_hair_style,
        "hair_color": player.selected_hair_color,
        "skin_color": player.selected_skin_color,
        # ... other appearance data
    }

    # Setup corpse visual with armor layers
    _setup_corpse_visual()

func can_loot(player_id: int) -> bool:
    """Check if player can loot this corpse"""
    # Owner can always loot
    if player_id == owner_player_id:
        return true

    # Group members can loot? (design decision)
    # if GroupManager.are_in_same_group(player_id, owner_player_id):
    #     return true

    return false

func get_all_loot() -> Dictionary:
    """Return all loot for UI display"""
    return {
        "inventory": stored_inventory,
        "equipped_armor": stored_equipped_armor,
        "equipped_weapon": stored_equipped_weapon,
        "gold": stored_gold
    }

func remove_item(item: Dictionary, from_equipped: bool, slot: String = "") -> bool:
    """Remove item from corpse when looted"""
    if from_equipped:
        if slot == "weapon":
            stored_equipped_weapon = null
        else:
            stored_equipped_armor[slot] = null
    else:
        # Remove from inventory array
        for i in range(stored_inventory.size()):
            if stored_inventory[i] == item:
                stored_inventory[i] = null
                break

    # Check if corpse is empty
    if _is_empty():
        _despawn()

    return true

func take_gold() -> int:
    """Take all gold from corpse"""
    var gold = stored_gold
    stored_gold = 0
    if _is_empty():
        _despawn()
    return gold

func _is_empty() -> bool:
    """Check if corpse has no more loot"""
    if stored_gold > 0:
        return false
    if stored_equipped_weapon != null:
        return false
    for slot in stored_equipped_armor:
        if stored_equipped_armor[slot] != null:
            return false
    for item in stored_inventory:
        if item != null:
            return false
    return true

func _process(delta: float) -> void:
    var time_since_death = Time.get_unix_time_from_system() - death_timestamp

    # Update decay state
    if time_since_death >= CORPSE_DECAY_TIME:
        _decay_corpse()
    elif time_since_death >= CORPSE_FRESH_TIME:
        if current_state == State.FRESH:
            current_state = State.DECAYING
            _apply_decay_visual()

func _decay_corpse() -> void:
    """Corpse has fully decayed - all loot lost"""
    current_state = State.ROTTED
    emit_signal("corpse_decayed", self)
    # Notify owner their corpse decayed
    # ... network RPC to owner
    queue_free()
```

---

### 2. PlayerCorpseLootUI.gd (Scene: PlayerCorpseLootUI.tscn)

UI for looting your own corpse. Similar to LootBodyUI but shows equipped gear separately.

```gdscript
extends CanvasLayer
class_name PlayerCorpseLootUI

signal loot_ui_closed()

var current_corpse: PlayerCorpse = null

# UI Sections
# - Equipped Gear section (paperdoll-style or grid)
# - Inventory section (grid like regular loot UI)
# - Gold display
# - "Take All" button
# - "Equip All" button (re-equips all armor to matching slots)
```

**Layout:**
```
┌─────────────────────────────────────────────┐
│  YOUR CORPSE                            [X] │
├─────────────────────────────────────────────┤
│                                             │
│  EQUIPPED GEAR:                             │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ │
│  │Head│ │Chest│ │Arms│ │Hands│ │Legs│ │Feet│ │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘ │
│  ┌────┐ ┌────┐                              │
│  │Weap│ │Off │                              │
│  └────┘ └────┘                              │
│                                             │
│  INVENTORY:                                 │
│  ┌────┬────┬────┬────┬────┬────┬────┬────┐ │
│  │    │    │    │    │    │    │    │    │ │
│  ├────┼────┼────┼────┼────┼────┼────┼────┤ │
│  │    │    │    │    │    │    │    │    │ │
│  └────┴────┴────┴────┴────┴────┴────┴────┘ │
│                                             │
│  GOLD: 1,234                                │
│                                             │
│  [TAKE ALL]  [EQUIP ALL & TAKE]             │
└─────────────────────────────────────────────┘
```

**Key Functions:**
```gdscript
func open_corpse_ui(corpse: PlayerCorpse) -> void:
    current_corpse = corpse
    var loot = corpse.get_all_loot()
    _populate_equipped_slots(loot.equipped_armor, loot.equipped_weapon)
    _populate_inventory_grid(loot.inventory)
    _update_gold_display(loot.gold)
    show()

func _on_take_item(item: Dictionary, from_equipped: bool, slot: String = "") -> void:
    """Take single item from corpse"""
    if not InventorySystem.has_space():
        NotificationManager.show_notification("Inventory full!", "WARNING")
        return

    if current_corpse.remove_item(item, from_equipped, slot):
        InventorySystem.add_item(item)
        _refresh_ui()

func _on_take_all() -> void:
    """Take everything possible to inventory"""
    var loot = current_corpse.get_all_loot()

    # Take gold first
    var gold = current_corpse.take_gold()
    CharacterStats.add_gold(gold)

    # Take inventory items
    for item in loot.inventory:
        if item != null and InventorySystem.has_space():
            if current_corpse.remove_item(item, false):
                InventorySystem.add_item(item)

    # Take equipped items to inventory
    for slot in loot.equipped_armor:
        var armor = loot.equipped_armor[slot]
        if armor != null and InventorySystem.has_space():
            if current_corpse.remove_item(armor, true, slot):
                InventorySystem.add_item(armor)

    if loot.equipped_weapon != null and InventorySystem.has_space():
        if current_corpse.remove_item(loot.equipped_weapon, true, "weapon"):
            InventorySystem.add_item(loot.equipped_weapon)

    _refresh_ui()

func _on_equip_all_and_take() -> void:
    """Re-equip all armor, weapon, take inventory + gold"""
    var loot = current_corpse.get_all_loot()

    # Take gold
    var gold = current_corpse.take_gold()
    CharacterStats.add_gold(gold)

    # Re-equip armor directly to slots
    for slot in loot.equipped_armor:
        var armor = loot.equipped_armor[slot]
        if armor != null:
            current_corpse.remove_item(armor, true, slot)
            CharacterStats.equip_armor(armor)  # Goes to matching slot

    # Re-equip weapon
    if loot.equipped_weapon != null:
        current_corpse.remove_item(loot.equipped_weapon, true, "weapon")
        CharacterStats.equip_weapon(loot.equipped_weapon)

    # Take inventory items
    for item in loot.inventory:
        if item != null and InventorySystem.has_space():
            if current_corpse.remove_item(item, false):
                InventorySystem.add_item(item)

    close_ui()
```

---

### 3. Player.gd Modifications

**Modified die() function:**
```gdscript
func die() -> void:
    if is_dead:
        return
    is_dead = true

    # === SPAWN CORPSE WITH ALL LOOT ===
    var corpse_scene = preload("res://scenes/world/PlayerCorpse.tscn")
    var corpse = corpse_scene.instantiate()
    corpse.initialize(self, global_position)
    get_tree().current_scene.add_child(corpse)

    # Store corpse reference for tracking
    _active_corpses.append(corpse)

    # === STRIP PLAYER OF EVERYTHING ===
    # Clear inventory
    InventorySystem.clear_all()

    # Reset to default clothes only
    CharacterStats.reset_equipment_to_default()

    # Clear gold
    CharacterStats.gold = 0

    # Clear weapon
    CharacterStats.unequip_weapon()

    # === RESPAWN AT BIND POINT ===
    # ... existing respawn logic
    global_position = _get_bind_point()  # Campfire location
    current_health = max_health

    # Update visuals (now wearing default clothes only)
    refresh_all_equipment_layers()

    is_dead = false

    # Notify player
    NotificationManager.show_notification(
        "You have died. Your corpse contains your belongings.",
        "DEATH"
    )

# Track player's corpses
var _active_corpses: Array = []

func _get_bind_point() -> Vector2:
    """Get respawn location - nearest campfire or default spawn"""
    # Find nearest bound campfire, or default to chunk 0 center
    return Vector2(Constants.CHUNK_SIZE / 2, 0)
```

---

### 4. CharacterStats.gd Modifications

**New functions:**
```gdscript
func reset_equipment_to_default() -> void:
    """Reset all armor slots to default clothes (death/reset)"""
    # Clear all slots
    for slot in equipped_armor:
        equipped_armor[slot] = null

    # Re-equip starting clothes
    _equip_starting_clothes()

    emit_signal("equipment_reset")

func get_full_equipment_snapshot() -> Dictionary:
    """Get deep copy of all equipment for corpse"""
    return {
        "armor": equipped_armor.duplicate(true),
        "weapon": equipped_weapon.duplicate() if equipped_weapon else null
    }

func clear_all_equipment() -> void:
    """Remove all equipment without re-equipping defaults"""
    for slot in equipped_armor:
        if equipped_armor[slot] != null:
            emit_signal("armor_unequipped", slot, equipped_armor[slot])
            equipped_armor[slot] = null

    if equipped_weapon:
        emit_signal("weapon_unequipped", equipped_weapon)
        equipped_weapon = null
```

---

### 5. InventorySystem.gd Modifications

**New functions:**
```gdscript
func clear_all() -> void:
    """Clear entire inventory (death)"""
    for i in range(inventory_items.size()):
        inventory_items[i] = null

    # Clear tool slots too
    equipped_axe = {}
    equipped_pickaxe = {}

    emit_signal("inventory_changed")

func get_full_snapshot() -> Array:
    """Get deep copy of inventory for corpse"""
    return inventory_items.duplicate(true)
```

---

## Network Considerations

### Server Authority
- **Corpse creation**: Server spawns corpse, syncs to all clients
- **Corpse data**: Server stores authoritative loot data
- **Loot actions**: Client requests loot, server validates and syncs

### RPCs
```gdscript
# Player death -> Server creates corpse
@rpc("any_peer", "call_remote", "reliable")
func server_player_died(player_id: int, death_position: Vector2) -> void:
    # Server creates corpse with player's loot
    # Broadcasts corpse spawn to all clients

# Client wants to loot corpse
@rpc("any_peer", "call_remote", "reliable")
func server_request_corpse_loot(corpse_id: int) -> void:
    # Validate player can loot this corpse
    # Send corpse contents to client

# Client takes item from corpse
@rpc("any_peer", "call_remote", "reliable")
func server_take_corpse_item(corpse_id: int, item_index: int, from_equipped: bool, slot: String) -> void:
    # Validate, remove from corpse, add to player inventory
    # Sync corpse state to all clients

# Server syncs corpse state
@rpc("authority", "call_remote", "reliable")
func client_sync_corpse_state(corpse_id: int, corpse_data: Dictionary) -> void:
    # Update local corpse visual/state
```

---

## Corpse Visual

The corpse should display the player's body with all their equipped armor, lying on the ground.

**Options:**
1. **Full LPC sprite recreation** - Render all armor layers on a "dead" pose
2. **Simplified approach** - Single "corpse" sprite with equipment glow/indicator
3. **Hybrid** - Chest/helm visible, rest simplified

**Recommended: Option 1 (Full LPC)**
- Reuse existing `SimpleLPCSprite` system
- Set animation to a "death" or "lying down" frame
- Apply all armor layers from `stored_appearance`
- Add subtle ground shadow/blood pool

---

## Decay Stages

| Stage | Time | Visual | Behavior |
|-------|------|--------|----------|
| FRESH | 0-5 min | Full color, slight glow | Clear loot prompt |
| DECAYING | 5-25 min | Faded colors, flies? | Warning to owner |
| WARNING | 25-30 min | Flashing, urgent | "Corpse decaying!" notification |
| ROTTED | 30+ min | Despawns | All loot lost forever |

---

## Edge Cases

| Scenario | Resolution |
|----------|------------|
| Player dies while corpse exists | Creates second corpse (multiple corpses allowed) |
| Player disconnects with corpse | Corpse persists, timer continues |
| Player reconnects | Can see/loot their corpses |
| Server restart | Corpses should persist to database (future) |
| Corpse in dangerous area | Player's problem - adds tension |
| Inventory full when looting | Take what fits, leave rest |
| Group member loots corpse? | Design decision - EQ allowed this |

---

## Files to Create

1. `scenes/world/PlayerCorpse.tscn` - Corpse scene
2. `scripts/world/PlayerCorpse.gd` - Corpse logic
3. `scenes/ui/PlayerCorpseLootUI.tscn` - Loot UI scene
4. `scripts/ui/PlayerCorpseLootUI.gd` - Loot UI logic
5. `scenes/ui/DeathScreenUI.tscn` - Death screen overlay
6. `scripts/ui/DeathScreenUI.gd` - Death screen logic (coords, drag requests, release)

---

## Files to Modify

1. `scripts/player/Player.gd`
   - Modify `die()` to spawn corpse and strip player
   - Add corpse tracking
   - Add bind point logic

2. `scripts/systems/CharacterStats.gd`
   - Add `reset_equipment_to_default()`
   - Add `get_full_equipment_snapshot()`

3. `scripts/systems/InventorySystem.gd`
   - Add `clear_all()`
   - Add `get_full_snapshot()`

4. `scripts/networking/NetworkManager.gd` (or new NetworkCorpseManager.gd)
   - Corpse sync RPCs

---

## Implementation Order

1. **PlayerCorpse scene/script** - Basic corpse spawning at death location
2. **Player.gd death changes** - Spawn corpse, strip items
3. **CharacterStats/InventorySystem changes** - Clear/snapshot functions
4. **PlayerCorpseLootUI** - UI for looting corpse
5. **Corpse interaction** - F to loot, proximity detection
6. **Decay system** - Timer, visual states, despawn
7. **Network sync** - Multiplayer corpse state
8. **Polish** - Corpse visual with armor, notifications, minimap marker

---

## Design Decisions

- [x] **Use current HP at death** - No changes needed, natural consequence
- [x] **Group members cannot loot corpse** - Only owner can loot (for now)
- [x] **Group members CAN drag corpse** - With consent system (see below)
- [x] **No minimap marker** - Hardcore, remember where you died
- [x] **XP loss on death** - Percentage of current level XP lost
- [ ] "Summon Corpse" ability for later? (EQ had this)
- [ ] Level loss on death? (Hardcore mode?)
- [ ] Loot-all keybind? (F while UI open)
- [ ] Corpse persistence across server restart?

---

## XP Loss on Death

When a player dies, they lose a percentage of their current level's XP progress.

```gdscript
const DEATH_XP_PENALTY_PERCENT: float = 0.10  # 10% of current level XP

func apply_death_xp_penalty() -> void:
    # Calculate XP needed for current level
    var xp_for_current_level = CharacterStats.get_xp_for_level(CharacterStats.level)
    var xp_for_next_level = CharacterStats.get_xp_for_level(CharacterStats.level + 1)
    var level_xp_range = xp_for_next_level - xp_for_current_level

    # Calculate penalty (10% of level range)
    var xp_penalty = int(level_xp_range * DEATH_XP_PENALTY_PERCENT)

    # Apply penalty (can't go below current level threshold)
    var new_xp = max(xp_for_current_level, CharacterStats.experience - xp_penalty)
    var actual_loss = CharacterStats.experience - new_xp
    CharacterStats.experience = new_xp

    NotificationManager.show_notification(
        "You lost %d XP" % actual_loss,
        "DEATH"
    )
```

**Notes:**
- Can't lose a level from XP penalty (floor at level threshold)
- 10% is harsh but fair - makes death meaningful
- Could scale with level (higher levels = higher penalty?)

---

## Corpse Dragging System

Group members (or anyone with consent) can drag a corpse to a safer location.

### Consent Flow

```
[PLAYER A APPROACHES PLAYER B's CORPSE]
              │
              ▼
┌─────────────────────────────────────────┐
│ Player A presses [G] to request drag    │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│ Player B (dead, spectating?) sees:      │
│ "PlayerA wants to drag your corpse"     │
│ [Allow] [Deny]                          │
│                                         │
│ OR if B is offline/AFK:                 │
│ - Group members auto-allowed?           │
│ - Timeout = deny?                        │
└─────────────────────────────────────────┘
              │
       ┌──────┴──────┐
       ▼             ▼
   [ALLOW]        [DENY]
       │             │
       ▼             ▼
   Drag starts   "Request denied"
```

### Drag Mechanics

```gdscript
# PlayerCorpse.gd additions

var is_being_dragged: bool = false
var dragger_player: Node = null
var drag_consent_granted: Dictionary = {}  # player_id -> bool

const DRAG_SPEED_MULTIPLIER: float = 0.5  # Dragger moves at 50% speed
const DRAG_DISTANCE: float = 40.0  # Corpse follows this far behind dragger
const DRAG_REQUEST_TIMEOUT: float = 30.0  # Consent request expires

func request_drag(requester: Node) -> void:
    """Player requests to drag this corpse"""
    var requester_id = requester.get_multiplayer_authority()

    # Check if consent already granted
    if drag_consent_granted.get(requester_id, false):
        start_drag(requester)
        return

    # Send consent request to corpse owner
    _send_drag_consent_request(requester_id)

func grant_drag_consent(player_id: int) -> void:
    """Owner grants drag permission to player"""
    drag_consent_granted[player_id] = true
    # Notify requester they can now drag

func deny_drag_consent(player_id: int) -> void:
    """Owner denies drag permission"""
    drag_consent_granted[player_id] = false
    # Notify requester

func start_drag(dragger: Node) -> void:
    """Begin dragging corpse"""
    is_being_dragged = true
    dragger_player = dragger

    # Slow down dragger
    dragger.apply_speed_modifier("corpse_drag", DRAG_SPEED_MULTIPLIER)

    # Visual: rope/connection between dragger and corpse?

func stop_drag() -> void:
    """Stop dragging (dragger pressed G again, or got too far)"""
    if dragger_player:
        dragger_player.remove_speed_modifier("corpse_drag")
    is_being_dragged = false
    dragger_player = null

func _physics_process(delta: float) -> void:
    if is_being_dragged and is_instance_valid(dragger_player):
        # Corpse follows behind dragger
        var target_pos = dragger_player.global_position - \
            (dragger_player.velocity.normalized() * DRAG_DISTANCE)

        # Smooth follow
        global_position = global_position.lerp(target_pos, 5.0 * delta)

        # Cancel if dragger gets too far (teleport/disconnect)
        if global_position.distance_to(dragger_player.global_position) > 200:
            stop_drag()
```

### Player.gd Additions (for dragger)

```gdscript
# Speed modifier system
var speed_modifiers: Dictionary = {}  # name -> multiplier

func apply_speed_modifier(name: String, multiplier: float) -> void:
    speed_modifiers[name] = multiplier
    _recalculate_speed()

func remove_speed_modifier(name: String) -> void:
    speed_modifiers.erase(name)
    _recalculate_speed()

func _recalculate_speed() -> void:
    var final_multiplier = 1.0
    for mod in speed_modifiers.values():
        final_multiplier *= mod
    # Apply to movement speed
    current_speed = base_speed * final_multiplier

# Drag interaction
var currently_dragging_corpse: PlayerCorpse = null

func _input(event: InputEvent) -> void:
    # ... existing input handling

    # G to drag/drop corpse
    if event.is_action_pressed("interact_drag"):  # Need to add this input action
        if currently_dragging_corpse:
            _stop_dragging()
        else:
            _try_drag_nearby_corpse()

func _try_drag_nearby_corpse() -> void:
    """Find nearby player corpse and request drag"""
    var corpses = get_tree().get_nodes_in_group("player_corpses")
    for corpse in corpses:
        if corpse.global_position.distance_to(global_position) < 60:
            if corpse.owner_player_id != get_multiplayer_authority():
                corpse.request_drag(self)
                return

func _stop_dragging() -> void:
    if currently_dragging_corpse:
        currently_dragging_corpse.stop_drag()
        currently_dragging_corpse = null
```

### Consent UI (for dead player)

When dead and someone requests to drag your corpse:

```
┌─────────────────────────────────────────┐
│  CORPSE DRAG REQUEST                    │
│                                         │
│  "PlayerName wants to drag your corpse" │
│                                         │
│  [ALLOW]              [DENY]            │
│                                         │
│  Request expires in: 25s                │
└─────────────────────────────────────────┘
```

### Dead Player State

Player stays on death screen watching their corpse until they choose to release.

**Death Screen UI:**
```
                    ┌─────────────────────────────────┐
                    │           YOU DIED              │
                    │                                 │
                    │   Corpse location: (1245, -892) │
                    │                                 │
                    │      [RELEASE TO CAMPFIRE]      │
                    └─────────────────────────────────┘

    (Camera stays centered on corpse - player watches their body)
```

**When drag request comes in:**
```
                    ┌─────────────────────────────────┐
                    │           YOU DIED              │
                    │                                 │
                    │   Corpse location: (1245, -892) │
                    │                                 │
                    │   PlayerName wants to drag      │
                    │   your corpse                   │
                    │                                 │
                    │     [ALLOW]      [DENY]         │
                    │                                 │
                    │      [RELEASE TO CAMPFIRE]      │
                    └─────────────────────────────────┘
```

**While being dragged:**
```
                    ┌─────────────────────────────────┐
                    │           YOU DIED              │
                    │                                 │
                    │   Corpse location: (1312, -756) │
                    │   (Being dragged by PlayerName) │
                    │                                 │
                    │      [RELEASE TO CAMPFIRE]      │
                    └─────────────────────────────────┘

    (Camera follows corpse as it's dragged - coordinates update live)
```

**Death Screen Behavior:**
- Camera locks to corpse position (not player - player is "dead")
- Camera follows corpse if being dragged
- Coordinates update in real-time
- Compact UI, centered but doesn't block corpse view
- Can accept/deny drag requests before releasing
- "Release to Campfire" sends player to home bind point
- XP loss applied on death (not on release)

```gdscript
# Player.gd death state

var is_on_death_screen: bool = false
var death_corpse: PlayerCorpse = null  # Reference to our corpse

func die() -> void:
    # ... spawn corpse, strip items, apply XP penalty ...

    death_corpse = corpse  # Store reference
    is_on_death_screen = true

    # Disable player controls
    set_physics_process(false)
    visible = false  # Hide player node (we're "dead")

    # Lock camera to corpse
    _attach_camera_to_corpse()

    # Show death screen UI
    var death_ui = preload("res://scenes/ui/DeathScreenUI.tscn").instantiate()
    death_ui.setup(death_corpse)
    get_tree().root.add_child(death_ui)
    death_ui.released_to_campfire.connect(_on_release_to_campfire)

func _attach_camera_to_corpse() -> void:
    """Move camera to follow corpse instead of player"""
    var camera = get_node_or_null("Camera2D")
    if camera and death_corpse:
        # Reparent camera to corpse temporarily
        camera.get_parent().remove_child(camera)
        death_corpse.add_child(camera)
        camera.position = Vector2.ZERO

func _on_release_to_campfire() -> void:
    """Player clicked release - respawn at bind point"""
    is_on_death_screen = false

    # Return camera to player
    _return_camera_to_player()

    # Respawn at home campfire
    global_position = _get_home_bind_point()
    current_health = max_health
    visible = true
    set_physics_process(true)
    is_dead = false

    # Refresh visuals (now in default clothes)
    refresh_all_equipment_layers()

func _return_camera_to_player() -> void:
    """Return camera from corpse to player"""
    if death_corpse:
        var camera = death_corpse.get_node_or_null("Camera2D")
        if camera:
            death_corpse.remove_child(camera)
            add_child(camera)
            camera.position = Vector2.ZERO
    death_corpse = null
```

### DeathScreenUI.gd

```gdscript
extends CanvasLayer
class_name DeathScreenUI

signal released_to_campfire()

var corpse: PlayerCorpse = null
var pending_drag_request: Dictionary = {}  # {requester_id, requester_name}

@onready var coords_label: Label = $Panel/CoordsLabel
@onready var status_label: Label = $Panel/StatusLabel
@onready var release_button: Button = $Panel/ReleaseButton
@onready var drag_request_container: Control = $Panel/DragRequestContainer
@onready var allow_button: Button = $Panel/DragRequestContainer/AllowButton
@onready var deny_button: Button = $Panel/DragRequestContainer/DenyButton

func _ready() -> void:
    release_button.pressed.connect(_on_release_pressed)
    allow_button.pressed.connect(_on_allow_drag)
    deny_button.pressed.connect(_on_deny_drag)
    drag_request_container.visible = false

func setup(player_corpse: PlayerCorpse) -> void:
    corpse = player_corpse
    corpse.drag_requested.connect(_on_drag_requested)
    corpse.drag_started.connect(_on_drag_started)
    corpse.drag_stopped.connect(_on_drag_stopped)
    _update_display()

func _process(_delta: float) -> void:
    if corpse and is_instance_valid(corpse):
        _update_display()

func _update_display() -> void:
    # Update coordinates
    var pos = corpse.global_position
    coords_label.text = "Corpse location: (%d, %d)" % [int(pos.x), int(pos.y)]

    # Update drag status
    if corpse.is_being_dragged:
        var dragger_name = corpse.get_dragger_name()
        status_label.text = "(Being dragged by %s)" % dragger_name
        status_label.visible = true
    else:
        status_label.visible = false

func _on_drag_requested(requester_id: int, requester_name: String) -> void:
    pending_drag_request = {
        "id": requester_id,
        "name": requester_name
    }
    drag_request_container.visible = true
    $Panel/DragRequestContainer/RequestLabel.text = "%s wants to drag\nyour corpse" % requester_name

func _on_allow_drag() -> void:
    if pending_drag_request:
        corpse.grant_drag_consent(pending_drag_request.id)
    drag_request_container.visible = false
    pending_drag_request = {}

func _on_deny_drag() -> void:
    if pending_drag_request:
        corpse.deny_drag_consent(pending_drag_request.id)
    drag_request_container.visible = false
    pending_drag_request = {}

func _on_drag_started() -> void:
    # Hide request UI if visible
    drag_request_container.visible = false

func _on_drag_stopped() -> void:
    pass  # Could show notification

func _on_release_pressed() -> void:
    emit_signal("released_to_campfire")
    queue_free()
```

### Network RPCs for Dragging

```gdscript
# Request drag consent
@rpc("any_peer", "call_remote", "reliable")
func server_request_drag_consent(corpse_id: int, requester_id: int) -> void:
    # Server forwards request to corpse owner (if online)

# Owner responds to drag request
@rpc("any_peer", "call_remote", "reliable")
func server_drag_consent_response(corpse_id: int, requester_id: int, allowed: bool) -> void:
    # Server updates corpse consent, notifies requester

# Sync drag state
@rpc("authority", "call_remote", "reliable")
func client_corpse_drag_started(corpse_id: int, dragger_id: int) -> void:
    # All clients see corpse being dragged

@rpc("authority", "call_remote", "reliable")
func client_corpse_drag_stopped(corpse_id: int, final_position: Vector2) -> void:
    # All clients update corpse position
```

---

## Future Expansions

- **Corpse summoning** - High-level ability or NPC service to summon corpse to safe location
- **Corpse decay protection** - Consumable item that pauses decay timer
- **Grave markers** - Permanent marker where you died (memorial)
- **Death recap** - UI showing what killed you, damage breakdown
- **Corpse insurance** - Pay gold to NPC to "insure" gear (reduced loss on death)
