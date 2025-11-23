# Mini-MMO Server Architecture

## Overview
Authoritative dedicated server model for persistent world MMO.

## Server Types

### Headless Server (Production)
Runs without graphics on VPS/dedicated machine.

```gdscript
# scripts/server/headless_server.gd
extends Node

const MAX_PLAYERS = 50
const SERVER_PORT = 7777
const TICK_RATE = 30  # Server updates 30 times/second

var database: Database
var world: GameWorld
var connected_players: Dictionary = {}  # peer_id -> PlayerData

func _ready():
    if not OS.has_feature("dedicated_server"):
        push_error("Not running as dedicated server")
        return

    # Disable rendering
    get_tree().root.set_disable_3d(true)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

    # Initialize database
    database = Database.new()
    database.connect_to_db("user://server_data.db")
    database.initialize_tables()

    # Start network
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(SERVER_PORT, MAX_PLAYERS)
    if error != OK:
        push_error("Failed to start server: %s" % error)
        return

    multiplayer.multiplayer_peer = peer
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

    # Load world
    world = preload("res://scenes/game_world.tscn").instantiate()
    add_child(world)

    # Start server tick
    var tick_timer = Timer.new()
    tick_timer.wait_time = 1.0 / TICK_RATE
    tick_timer.timeout.connect(_server_tick)
    add_child(tick_timer)
    tick_timer.start()

    # Auto-save timer
    var save_timer = Timer.new()
    save_timer.wait_time = 300.0  # 5 minutes
    save_timer.timeout.connect(_auto_save_all_players)
    add_child(save_timer)
    save_timer.start()

    print("═══════════════════════════════════")
    print("  WASTELAND SERVER STARTED")
    print("  Port: %d" % SERVER_PORT)
    print("  Max Players: %d" % MAX_PLAYERS)
    print("  Tick Rate: %d Hz" % TICK_RATE)
    print("═══════════════════════════════════")

func _on_peer_connected(peer_id: int):
    print("Peer %d connected (awaiting authentication)" % peer_id)

func _on_peer_disconnected(peer_id: int):
    print("Peer %d disconnected" % peer_id)
    _handle_player_logout(peer_id)

func _server_tick():
    # Update all game systems
    _update_enemy_ai()
    _update_combat()
    _process_movement()
    _check_respawns()
    _sync_player_states()

func _auto_save_all_players():
    print("Auto-saving %d online players..." % connected_players.size())
    for peer_id in connected_players:
        var player_data = connected_players[peer_id]
        database.save_player(player_data)
    print("Auto-save complete")
```

### Development Server (Testing)
Runs with graphics for debugging.

```gdscript
# Same as headless but without window hiding
# Can see player positions, spawn enemies manually, etc.
```

## Network Protocol

### RPC Methods

#### Authentication
```gdscript
# Client → Server
@rpc("any_peer", "call_remote")
func request_login(username: String, password_hash: String):
    var peer_id = multiplayer.get_remote_sender_id()
    var player_data = database.authenticate_player(username, password_hash)

    if player_data:
        # Check if already online (prevent dual-login)
        for pid in connected_players:
            if connected_players[pid].username == username:
                rpc_id(peer_id, "login_failed", "Already logged in")
                return

        # Load player into world
        _spawn_player(peer_id, player_data)
        rpc_id(peer_id, "login_success", player_data)
        print("Player '%s' (ID: %d) logged in" % [username, peer_id])
    else:
        rpc_id(peer_id, "login_failed", "Invalid credentials")

# Client → Server (new account)
@rpc("any_peer", "call_remote")
func request_register(username: String, password_hash: String):
    var peer_id = multiplayer.get_remote_sender_id()

    # Validate username (3-16 chars, alphanumeric)
    if not username.is_valid_identifier() or username.length() < 3:
        rpc_id(peer_id, "register_failed", "Invalid username")
        return

    # Create account
    var success = database.create_player(username, password_hash)
    if success:
        rpc_id(peer_id, "register_success")
        print("New account created: %s" % username)
    else:
        rpc_id(peer_id, "register_failed", "Username taken")
```

#### Movement
```gdscript
# Client → Server (input only, not position)
@rpc("any_peer", "call_remote", "unreliable")
func send_input(input_direction: Vector2, mouse_position: Vector2):
    var peer_id = multiplayer.get_remote_sender_id()
    if not connected_players.has(peer_id):
        return

    var player = connected_players[peer_id].player_node
    player.input_direction = input_direction
    player.mouse_position = mouse_position

# Server → All Clients
@rpc("authority", "call_remote", "unreliable")
func sync_player_position(peer_id: int, position: Vector2, velocity: Vector2):
    # Clients update visual position
    pass
```

#### Combat
```gdscript
# Client → Server
@rpc("any_peer", "call_remote")
func request_attack(attack_direction: Vector2):
    var peer_id = multiplayer.get_remote_sender_id()
    if not connected_players.has(peer_id):
        return

    var player = connected_players[peer_id].player_node

    # Server validates attack (cooldown, range, etc.)
    if not player.can_attack():
        return

    # Server processes damage
    var enemies_hit = player.get_enemies_in_cone(attack_direction)
    for enemy in enemies_hit:
        var damage = player.calculate_damage()
        var is_crit = player.roll_crit()
        enemy.take_damage(damage, is_crit, peer_id)

        # Broadcast to all clients
        rpc("show_attack_feedback", enemy.id, damage, is_crit)

# Server → All Clients
@rpc("authority", "call_remote")
func show_attack_feedback(enemy_id: int, damage: float, is_crit: bool):
    # Play visual/audio feedback
    pass

# Server → Specific Client (crit window for owner only)
@rpc("authority", "call_remote")
func spawn_crit_window(enemy_id: int, weakpoint_positions: Array):
    # Only sent to player who triggered crit
    pass
```

#### Inventory
```gdscript
# Client → Server
@rpc("any_peer", "call_remote")
func request_pickup_item(item_id: String):
    var peer_id = multiplayer.get_remote_sender_id()
    var player_data = connected_players[peer_id]

    # Validate item exists and is in range
    var item = world.get_item(item_id)
    if not item or item.global_position.distance_to(player_data.player_node.global_position) > 100:
        return

    # Add to inventory
    if player_data.inventory.add_item(item.data):
        world.remove_item(item_id)
        rpc_id(peer_id, "item_added", item.data)

        # If instanced loot, remove only for this player
        if item.instanced:
            rpc_id(peer_id, "hide_item", item_id)
    else:
        rpc_id(peer_id, "inventory_full")

# Client → Server
@rpc("any_peer", "call_remote")
func request_equip_item(slot: int):
    var peer_id = multiplayer.get_remote_sender_id()
    var player_data = connected_players[peer_id]

    # Server validates and equips
    var success = player_data.equip_from_slot(slot)
    if success:
        # Update stats server-side
        player_data.recalculate_stats()
        # Sync to client
        rpc_id(peer_id, "equipment_updated", player_data.equipment)
        # Broadcast visual to other players
        rpc("update_player_appearance", peer_id, player_data.get_sprite_layers())
```

#### Chat
```gdscript
# Client → Server
@rpc("any_peer", "call_remote")
func send_chat_message(message: String, channel: String = "global"):
    var peer_id = multiplayer.get_remote_sender_id()
    var player_data = connected_players[peer_id]

    # Sanitize message
    message = message.strip_edges().substr(0, 200)
    if message.is_empty():
        return

    # Check spam/mute
    if _is_player_muted(peer_id):
        rpc_id(peer_id, "chat_error", "You are muted")
        return

    # Log to database
    database.log_chat(player_data.id, message, channel)

    # Broadcast
    match channel:
        "global":
            rpc("receive_chat", player_data.username, message, "global")
        "party":
            # TODO: party system
            pass
        "whisper":
            # TODO: whisper system
            pass

# Server → Clients
@rpc("authority", "call_remote")
func receive_chat(username: String, message: String, channel: String):
    # Display in chat UI
    pass
```

## State Synchronization

### Player State (30 Hz)
```gdscript
func _sync_player_states():
    var state_packet = {}

    for peer_id in connected_players:
        var player = connected_players[peer_id].player_node
        state_packet[peer_id] = {
            "pos": player.global_position,
            "vel": player.velocity,
            "hp": player.current_hp,
            "animation": player.current_animation
        }

    # Broadcast to all clients (unreliable for performance)
    rpc("update_all_players", state_packet)
```

### Enemy State (10 Hz)
```gdscript
func _sync_enemy_states():
    var enemy_states = []

    for enemy in world.get_all_enemies():
        enemy_states.append({
            "id": enemy.id,
            "pos": enemy.global_position,
            "hp": enemy.current_hp,
            "state": enemy.ai_state
        })

    rpc("update_enemies", enemy_states)
```

### World Events (On Change)
```gdscript
func _on_chest_opened(chest_id: String, player_id: int):
    # Mark chest as opened in DB
    database.mark_chest_opened(player_id, chest_id)

    # Hide chest only for this player (instanced)
    rpc_id(player_id, "hide_chest", chest_id)

func _on_ruins_converted(ruins_id: int, player_id: int):
    # Advance player to next phase
    var player_data = connected_players[player_id]
    player_data.phase += 1
    database.save_player_phase(player_data.id, player_data.phase)

    # Move player to new phase world
    _respawn_player_in_phase(player_id, player_data.phase)
```

## Performance Optimizations

### Area of Interest (AOI)
Only send updates for entities near player.

```gdscript
func _get_players_in_range(player: Node2D, radius: float = 1500.0) -> Array:
    var nearby = []
    for peer_id in connected_players:
        var other = connected_players[peer_id].player_node
        if other == player:
            continue
        if player.global_position.distance_to(other.global_position) <= radius:
            nearby.append(peer_id)
    return nearby

func _sync_player_states():
    for peer_id in connected_players:
        var player = connected_players[peer_id].player_node
        var nearby = _get_players_in_range(player)

        var state_packet = {}
        for other_id in nearby:
            var other = connected_players[other_id].player_node
            state_packet[other_id] = {
                "pos": other.global_position,
                # ...
            }

        # Send only nearby players to this client
        rpc_id(peer_id, "update_nearby_players", state_packet)
```

### Update Rate Scaling
```gdscript
# Nearby: 30 Hz
# Medium range: 10 Hz
# Far: 2 Hz
# Out of range: no updates

func _get_update_rate_for_distance(distance: float) -> int:
    if distance < 500:
        return 30
    elif distance < 1500:
        return 10
    elif distance < 3000:
        return 2
    else:
        return 0  # No updates
```

## Security

### Anti-Cheat Measures

1. **Server Authority**: All gameplay logic on server
2. **Input Validation**: Reject impossible movements/actions
3. **Rate Limiting**: Prevent spam attacks
4. **Sanity Checks**: Verify positions, inventory, stats

```gdscript
func validate_player_position(player_id: int, claimed_pos: Vector2) -> bool:
    var player = connected_players[player_id].player_node
    var distance = player.global_position.distance_to(claimed_pos)
    var max_move = player.speed * get_physics_process_delta_time() * 2

    if distance > max_move:
        push_warning("Player %d position desync: %f > %f" % [player_id, distance, max_move])
        # Force correction
        rpc_id(player_id, "force_position", player.global_position)
        return false

    return true
```

### Authentication Security

```gdscript
# Use bcrypt for password hashing (via GDExtension)
# Never store plaintext passwords
# Use secure random salts

func hash_password(password: String) -> String:
    return BCrypt.hashpw(password, BCrypt.gensalt(12))

func verify_password(password: String, hash: String) -> bool:
    return BCrypt.checkpw(password, hash)
```

## Monitoring

### Server Stats
```gdscript
func _process(delta):
    # Every 60 seconds, print stats
    if int(Time.get_ticks_msec() / 1000) % 60 == 0:
        print("═══ SERVER STATS ═══")
        print("Online Players: %d / %d" % [connected_players.size(), MAX_PLAYERS])
        print("Enemies Alive: %d" % world.get_enemy_count())
        print("Avg Tick Time: %.2f ms" % _avg_tick_time)
        print("Memory: %.2f MB" % (OS.get_static_memory_usage() / 1024.0 / 1024.0))
```

### Crash Recovery
```gdscript
# On server crash, players marked offline
# Next startup, cleanup:
func _cleanup_crashed_sessions():
    database.reset_online_status()
```

## Deployment

### Docker Container (Recommended)
```dockerfile
FROM barichello/godot-ci:4.3

WORKDIR /app
COPY . .

# Export headless server
RUN godot --headless --export "Linux/X11" server.x86_64

EXPOSE 7777/udp

CMD ["./server.x86_64", "--dedicated-server"]
```

### Systemd Service (Linux VPS)
```ini
[Unit]
Description=Wasteland Server
After=network.target

[Service]
Type=simple
User=gameserver
WorkingDirectory=/opt/wasteland
ExecStart=/opt/wasteland/server.x86_64 --dedicated-server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Monitoring & Logs
```bash
# View logs
journalctl -u wasteland -f

# Check status
systemctl status wasteland

# Restart server
systemctl restart wasteland
```
