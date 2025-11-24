# Wasteland MMO - Multiplayer Demo Roadmap

## Goal: Minimal Playable Demo in 4 Weeks

**Demo Target**: 2-4 players fighting skeletons together in one chunk, with basic PvP

## Week 1: Network Foundation (Local Testing)

### Day 1-2: Godot Multiplayer Setup
```gdscript
# 1. Add to game_world.gd
extends Node2D

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 4

var peer = null
var player_scenes = {}

func _ready():
    multiplayer.peer_connected.connect(_on_player_connected)
    multiplayer.peer_disconnected.connect(_on_player_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)

func host_game():
    peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
    if error == OK:
        multiplayer.multiplayer_peer = peer
        print("Server started on port %d" % DEFAULT_PORT)
        spawn_player(multiplayer.get_unique_id())

func join_game(ip: String):
    peer = ENetMultiplayerPeer.new()
    peer.create_client(ip, DEFAULT_PORT)
    multiplayer.multiplayer_peer = peer
```

### Day 3-4: Player Sync
```gdscript
# 2. Create NetworkPlayer.gd
extends CharacterBody2D
class_name NetworkPlayer

@export var player_id := 1
@export var username := "Player"

# Synchronized variables
@export var sync_position := Vector2.ZERO
@export var sync_animation := "idle_down"
@export var sync_health := 100

func _ready():
    if is_multiplayer_authority():
        # This is our player
        $Camera2D.enabled = true
    else:
        # Remote player
        $Camera2D.enabled = false
        set_physics_process(false)

@rpc("any_peer", "call_local", "unreliable_ordered")
func update_position(new_pos: Vector2, anim: String):
    if not is_multiplayer_authority():
        position = new_pos
        play_animation(anim)

func _physics_process(delta):
    if is_multiplayer_authority():
        # Send our position to others
        rpc("update_position", position, current_animation)
```

### Day 5-7: Test & Debug
- [ ] Test with 2 local instances
- [ ] Fix position sync issues
- [ ] Add player name labels
- [ ] Test on LAN between 2 computers

**Milestone 1**: Two players can see each other move around

---

## Week 2: Combat Synchronization

### Day 8-9: Enemy Sync
```gdscript
# 3. Modify Enemy.gd
extends CharacterBody2D
class_name Enemy

var server_position: Vector2
var is_server := false

func _ready():
    is_server = multiplayer.is_server()

    if not is_server:
        # Clients don't run AI
        set_physics_process(false)
        $EnemyAI.process_mode = Node.PROCESS_MODE_DISABLED

@rpc("authority", "call_local", "unreliable_ordered")
func sync_enemy_state(pos: Vector2, hp: int, target_id: int):
    position = pos
    health = hp
    if target_id > 0:
        current_target = get_node("/root/Game/Players/%d" % target_id)

func _physics_process(delta):
    if is_server:
        # Only server runs AI
        process_ai(delta)

        # Sync to all clients
        rpc("sync_enemy_state", position, health,
            current_target.get_instance_id() if current_target else 0)
```

### Day 10-11: Damage System
```gdscript
# 4. Synchronized damage
@rpc("any_peer", "call_local", "reliable")
func request_attack(target_path: NodePath):
    if not multiplayer.is_server():
        return  # Only server validates attacks

    var target = get_node(target_path)
    if not is_valid_target(target):
        return

    var damage = calculate_damage()
    rpc("apply_damage", target_path, damage)

@rpc("authority", "call_local", "reliable")
func apply_damage(target_path: NodePath, damage: int):
    var target = get_node(target_path)
    target.take_damage(damage)
    show_damage_number(damage, target.position)
```

### Day 12-14: Death & Respawn
```gdscript
# 5. Handle death/respawn
@rpc("authority", "call_local", "reliable")
func handle_death(player_id: int):
    var player = get_player(player_id)
    player.die()

    # Respawn after 5 seconds
    await get_tree().create_timer(5.0).timeout

    if multiplayer.is_server():
        var spawn_pos = get_random_spawn_point()
        rpc("respawn_player", player_id, spawn_pos)

@rpc("authority", "call_local", "reliable")
func respawn_player(player_id: int, pos: Vector2):
    var player = get_player(player_id)
    player.position = pos
    player.health = player.max_health
    player.revive()
```

**Milestone 2**: Players can fight enemies together with synchronized combat

---

## Week 3: Basic PvP & Polish

### Day 15-16: PvP Toggle
```gdscript
# 6. Add PvP system
var pvp_enabled := true

@rpc("any_peer", "call_local", "reliable")
func request_pvp_attack(attacker_id: int, target_id: int):
    if not multiplayer.is_server():
        return

    if not pvp_enabled:
        rpc_id(attacker_id, "show_message", "PvP is disabled")
        return

    var attacker = get_player(attacker_id)
    var target = get_player(target_id)

    if can_attack(attacker, target):
        var damage = calculate_pvp_damage(attacker, target)
        rpc("apply_pvp_damage", target_id, damage, attacker_id)
```

### Day 17-18: Chat System
```gdscript
# 7. Simple chat
@rpc("any_peer", "call_local", "reliable")
func send_chat_message(player_name: String, message: String):
    # Sanitize message
    message = message.substr(0, 100)  # Max 100 chars

    # Display in chat box
    add_to_chat("[%s]: %s" % [player_name, message])

    # Server relays to all
    if multiplayer.is_server():
        rpc("receive_chat", player_name, message)
```

### Day 19-21: Performance & Optimization
```gdscript
# 8. Area of Interest management
func get_visible_entities(player: Node) -> Array:
    var visible = []
    var max_distance = 1000  # Only sync enemies within 1000 units

    for enemy in get_tree().get_nodes_in_group("enemies"):
        if player.position.distance_to(enemy.position) < max_distance:
            visible.append(enemy)

    return visible

# Only send updates for visible entities
func sync_world_state():
    for player_id in connected_players:
        var player = get_player(player_id)
        var visible = get_visible_entities(player)

        for entity in visible:
            rpc_id(player_id, "update_entity", entity.get_path(),
                   entity.position, entity.health)
```

**Milestone 3**: Basic PvP works, chat works, performance acceptable for 4 players

---

## Week 4: Demo Polish & Deployment

### Day 22-23: Lobby System
```gdscript
# 9. Simple lobby
var lobby_scene = preload("res://scenes/Lobby.tscn")

func create_lobby():
    var lobby = {
        "host": multiplayer.get_unique_id(),
        "players": {},
        "max_players": 4,
        "status": "waiting"
    }

    return lobby

func join_lobby(lobby_id: String):
    rpc_id(1, "request_join_lobby", lobby_id)

@rpc("any_peer", "call_remote", "reliable")
func request_join_lobby(lobby_id: String):
    var lobby = get_lobby(lobby_id)

    if lobby.players.size() >= lobby.max_players:
        rpc_id(multiplayer.get_remote_sender_id(),
               "lobby_full")
        return

    # Add player to lobby
    lobby.players[multiplayer.get_remote_sender_id()] = {
        "ready": false,
        "name": "Player%d" % multiplayer.get_remote_sender_id()
    }

    # Update all players
    for player_id in lobby.players:
        rpc_id(player_id, "update_lobby", lobby)
```

### Day 24-25: Connection Management
```gdscript
# 10. Handle disconnections gracefully
func _on_player_disconnected(id: int):
    print("Player %d disconnected" % id)

    # Remove their character
    if player_scenes.has(id):
        player_scenes[id].queue_free()
        player_scenes.erase(id)

    # Notify others
    rpc("player_left", id)

    # If host left, migrate or close
    if id == 1 and not multiplayer.is_server():
        show_message("Host disconnected - returning to menu")
        return_to_menu()
```

### Day 26-27: Testing & Bug Fixes
- [ ] Test with 4 players on LAN
- [ ] Fix desync issues
- [ ] Stress test with rapid actions
- [ ] Document known issues

### Day 28: Package Demo
```gdscript
# Create main menu
extends Control

func _on_host_button_pressed():
    get_tree().change_scene_to_file("res://scenes/game_world.tscn")
    await get_tree().process_frame
    get_node("/root/GameWorld").host_game()

func _on_join_button_pressed():
    var ip = $IPInput.text
    get_tree().change_scene_to_file("res://scenes/game_world.tscn")
    await get_tree().process_frame
    get_node("/root/GameWorld").join_game(ip)
```

**Milestone 4**: Playable demo with lobby, 4 players can fight together

---

## Testing Checklist

### Local Testing (Week 1)
- [ ] 2 instances on same PC
- [ ] Movement sync works
- [ ] No crashes

### LAN Testing (Week 2)
- [ ] 2-4 PCs on same network
- [ ] Combat feels responsive
- [ ] Enemies sync properly

### Internet Testing (Week 3-4)
- [ ] Port forwarding works
- [ ] Acceptable with 100ms ping
- [ ] Graceful disconnection handling

### Stress Testing
- [ ] 4 players fighting 20 enemies
- [ ] Rapid clicking/actions
- [ ] Network interruption recovery

## File Structure Changes

```
wasteland/
├── scenes/
│   ├── MainMenu.tscn (NEW)
│   ├── Lobby.tscn (NEW)
│   ├── game_world.tscn (MODIFIED)
│   └── NetworkPlayer.tscn (NEW)
├── scripts/
│   ├── networking/
│   │   ├── NetworkManager.gd (NEW)
│   │   ├── NetworkPlayer.gd (NEW)
│   │   └── ServerAuthority.gd (NEW)
│   ├── player/
│   │   └── Player.gd (MODIFIED - add RPC)
│   └── enemies/
│       └── Enemy.gd (MODIFIED - server only AI)
```

## Quick Start Commands

```bash
# Host a server (for testing)
godot --headless --server

# Connect as client
godot --client --ip=127.0.0.1

# Debug mode
godot --verbose --debug-collisions
```

## Known Limitations for Demo

1. **No persistent servers** - Host player must stay online
2. **No matchmaking** - Direct IP connection only
3. **No accounts** - Just temporary usernames
4. **Max 4 players** - Hardcoded limit for demo
5. **LAN/Hamachi only** - No dedicated servers yet

## Success Metrics

✅ **Week 1**: Two players see each other move
✅ **Week 2**: Players fight enemies together
✅ **Week 3**: Basic PvP works
✅ **Week 4**: 4-player demo ready to share

## Next Steps After Demo

1. **Dedicated Server** (Week 5-6)
2. **Account System** (Week 7)
3. **Chunk System** (Week 8-9)
4. **Scale Testing** (Week 10)

This gets you a REAL multiplayer demo in 4 weeks that you can show to people!