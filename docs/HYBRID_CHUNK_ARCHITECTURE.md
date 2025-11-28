# Hybrid Chunk Architecture

## Overview

A federated server model where the central server hosts core gameplay chunks while players host their own territory chunks. This reduces hosting costs from ~$0.50/player to ~$0.05/player while creating meaningful ownership gameplay.

> **Status**: 📋 Design Document - Not Yet Implemented

---

## Architecture Diagram

```
                            CENTRAL SERVER
                         (You host: $10-20/mo)
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │  Chunk -1   │  │  Chunk 0    │  │  Chunk 1    │   CORE       │
│  │  (Spawn W)  │  │  (Spawn)    │  │  (Spawn E)  │   CHUNKS     │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                     SERVICES                             │    │
│  │  • Authentication      • Chunk Registry                  │    │
│  │  • Player Database     • PvP Event Coordinator           │    │
│  │  • Matchmaking         • Snapshot Storage                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└──────────────────────────────────┬───────────────────────────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │              │              │
                    ▼              ▼              ▼
          ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
          │ Player A PC │  │ Player B PC │  │ Guild VPS   │
          │ Chunk [5,0] │  │ Chunk [8,0] │  │ Chunk [12]  │
          │ "Outpost"   │  │ "Fortress"  │  │ "Guild Hall"│
          │             │  │             │  │ (24/7)      │
          └─────────────┘  └─────────────┘  └─────────────┘
               PLAYER-OWNED CHUNKS (They host: $0 to you)
```

---

## Chunk Types

### 1. Core Chunks (Central Server)

**Always online, you pay for hosting.**

| Chunk | Purpose | Contents |
|-------|---------|----------|
| -1, 0 | West Spawn | Campfire, Blacksmith, Training Dummy |
| 0, 0 | Central Spawn | Safe zone, new player area |
| 1, 0 | East Spawn | Path to first ruins |

**Responsibilities:**
- New player spawn point
- Core NPCs (vendors, quest givers)
- Tutorial/onboarding area
- Always accessible regardless of player hosts

### 2. Player-Owned Chunks (Player Hosts)

**Online when owner is online. Owner's PC hosts.**

| Feature | Behavior |
|---------|----------|
| Ownership | Claimed by player, registered in central DB |
| Availability | Only accessible when owner is online |
| Persistence | Saved locally on owner's machine + backup to central |
| Visiting | Other players can visit while owner hosts |
| Offline | Chunk is "dormant" - inaccessible but safe |

**Benefits:**
- Player investment in "their" territory
- Natural protection (offline = safe)
- Zero hosting cost to you

### 3. Guild Chunks (Guild Hosts)

**Optionally 24/7 if guild pays for VPS.**

| Feature | Behavior |
|---------|----------|
| Ownership | Claimed by guild, managed by guild leader |
| Hosting Options | Member's PC (rotating) OR cheap VPS ($5/mo) |
| Shared Access | All guild members can host when online |
| Persistence | Synced to central server for redundancy |

---

## Chunk Registry System

The central server maintains a registry of all claimed chunks.

### Data Structure

```gdscript
# Central server: ChunkRegistry.gd

# Chunk ownership database
var chunk_registry: Dictionary = {
    # chunk_coords (string) -> ChunkInfo
    "5,0": {
        "owner_id": "player_uuid_123",
        "owner_name": "PlayerA",
        "chunk_name": "A's Outpost",
        "claimed_at": 1701234567,
        "type": "player",  # "player", "guild", "core"
        "host_status": "offline",  # "online", "offline", "pvp_event"
        "host_ip": "",
        "host_port": 0,
        "last_snapshot": 1701234000,
        "snapshot_hash": "abc123...",
    },
    "12,0": {
        "owner_id": "guild_uuid_456",
        "owner_name": "ShadowWolves",
        "chunk_name": "Wolf Den",
        "claimed_at": 1701200000,
        "type": "guild",
        "host_status": "online",
        "host_ip": "123.45.67.89",
        "host_port": 7778,
        "authorized_hosts": ["player_uuid_a", "player_uuid_b"],  # Guild members who can host
        "last_snapshot": 1701234500,
        "snapshot_hash": "def456...",
    }
}

# Active host connections
var active_hosts: Dictionary = {
    # chunk_coords -> peer_id of current host
    "5,0": 12345,
    "12,0": 67890,
}
```

### Registry API

```gdscript
# ChunkRegistry.gd - Central Server

signal chunk_came_online(chunk_coords: String, host_info: Dictionary)
signal chunk_went_offline(chunk_coords: String)
signal chunk_ownership_changed(chunk_coords: String, new_owner: String)

# === QUERIES ===

func get_chunk_info(chunk_coords: String) -> Dictionary:
    if chunk_registry.has(chunk_coords):
        return chunk_registry[chunk_coords]
    return {"type": "unclaimed"}

func is_chunk_online(chunk_coords: String) -> bool:
    return active_hosts.has(chunk_coords)

func get_chunk_host(chunk_coords: String) -> Dictionary:
    if not is_chunk_online(chunk_coords):
        return {}
    var info = chunk_registry[chunk_coords]
    return {
        "ip": info.host_ip,
        "port": info.host_port,
        "host_peer_id": active_hosts[chunk_coords]
    }

func get_chunks_owned_by(player_id: String) -> Array:
    var owned = []
    for coords in chunk_registry:
        if chunk_registry[coords].owner_id == player_id:
            owned.append(coords)
    return owned

# === CLAIMING ===

func claim_chunk(player_id: String, chunk_coords: String, chunk_name: String) -> Dictionary:
    # Validate chunk is claimable
    if chunk_registry.has(chunk_coords):
        return {"success": false, "error": "Chunk already claimed"}

    if _is_core_chunk(chunk_coords):
        return {"success": false, "error": "Cannot claim core chunks"}

    # Check player doesn't own too many chunks
    var owned = get_chunks_owned_by(player_id)
    if owned.size() >= MAX_CHUNKS_PER_PLAYER:
        return {"success": false, "error": "Maximum chunks owned"}

    # Register ownership
    chunk_registry[chunk_coords] = {
        "owner_id": player_id,
        "owner_name": _get_player_name(player_id),
        "chunk_name": chunk_name,
        "claimed_at": Time.get_unix_time_from_system(),
        "type": "player",
        "host_status": "offline",
        "host_ip": "",
        "host_port": 0,
        "last_snapshot": 0,
        "snapshot_hash": "",
    }

    _save_registry()
    chunk_ownership_changed.emit(chunk_coords, player_id)

    return {"success": true}

func abandon_chunk(player_id: String, chunk_coords: String) -> Dictionary:
    if not chunk_registry.has(chunk_coords):
        return {"success": false, "error": "Chunk not claimed"}

    if chunk_registry[chunk_coords].owner_id != player_id:
        return {"success": false, "error": "Not your chunk"}

    # Remove from registry (chunk becomes unclaimed wilderness)
    chunk_registry.erase(chunk_coords)
    _save_registry()

    return {"success": true}

# === HOSTING ===

func register_chunk_host(peer_id: int, chunk_coords: String, host_ip: String, host_port: int) -> Dictionary:
    if not chunk_registry.has(chunk_coords):
        return {"success": false, "error": "Chunk not claimed"}

    var chunk_info = chunk_registry[chunk_coords]
    var player_id = _get_player_id_from_peer(peer_id)

    # Verify host authorization
    if chunk_info.type == "player":
        if chunk_info.owner_id != player_id:
            return {"success": false, "error": "Not authorized to host this chunk"}
    elif chunk_info.type == "guild":
        if player_id not in chunk_info.authorized_hosts:
            return {"success": false, "error": "Not a guild host"}

    # Register as active host
    chunk_info.host_status = "online"
    chunk_info.host_ip = host_ip
    chunk_info.host_port = host_port
    active_hosts[chunk_coords] = peer_id

    chunk_came_online.emit(chunk_coords, {
        "ip": host_ip,
        "port": host_port,
        "owner": chunk_info.owner_name,
        "name": chunk_info.chunk_name
    })

    print("[ChunkRegistry] Chunk %s now online, hosted by peer %d" % [chunk_coords, peer_id])
    return {"success": true}

func unregister_chunk_host(chunk_coords: String):
    if not active_hosts.has(chunk_coords):
        return

    active_hosts.erase(chunk_coords)

    if chunk_registry.has(chunk_coords):
        chunk_registry[chunk_coords].host_status = "offline"
        chunk_registry[chunk_coords].host_ip = ""
        chunk_registry[chunk_coords].host_port = 0

    chunk_went_offline.emit(chunk_coords)
    print("[ChunkRegistry] Chunk %s now offline" % chunk_coords)

# === HELPERS ===

func _is_core_chunk(chunk_coords: String) -> bool:
    return chunk_coords in ["-1,0", "0,0", "1,0"]

const MAX_CHUNKS_PER_PLAYER = 3
```

---

## Chunk Handoff Protocol

When a player moves between chunks owned by different hosts.

### Scenario: Player Moves from Core → Player Chunk

```
Player walking east from Chunk [1,0] (central) toward Chunk [5,0] (Player A's)

┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: Approach Detection                                          │
│                                                                     │
│   Player position X > chunk_boundary - 500px                        │
│   Central server checks: "What's in Chunk [5,0]?"                   │
│   Registry returns: Owner=PlayerA, Status=Online, IP=..., Port=...  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 2: Handoff Preparation                                         │
│                                                                     │
│   Central → Player A's Host: "Visitor incoming, prepare handoff"    │
│   Player A's Host: Creates visitor session, reserves slot           │
│   Player A's Host → Central: "Ready, session_token=XYZ"             │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 3: Client Redirect                                             │
│                                                                     │
│   Central → Visiting Player: "Connect to 1.2.3.4:7778 token=XYZ"    │
│   Visiting Player: Opens secondary connection to Player A's host    │
│   Visiting Player: Keeps connection to central (for auth/chat)      │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 4: Seamless Transition                                         │
│                                                                     │
│   Player A's Host: Spawns visitor at chunk entry point              │
│   Player A's Host: Sends local chunk state (enemies, props)         │
│   Visiting Player: Now receiving game state from Player A's host    │
│   Central: Tracks that visitor is "in chunk 5,0"                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Handoff Implementation

```gdscript
# === CENTRAL SERVER ===
# CentralServer.gd

func _on_player_approaching_chunk_boundary(player_peer_id: int, target_chunk: String):
    var chunk_info = ChunkRegistry.get_chunk_info(target_chunk)

    match chunk_info.type:
        "core":
            # Already on central, no handoff needed
            pass

        "unclaimed":
            # Wilderness - could spawn procedural content or block
            _handle_unclaimed_chunk(player_peer_id, target_chunk)

        "player", "guild":
            if ChunkRegistry.is_chunk_online(target_chunk):
                _initiate_handoff(player_peer_id, target_chunk)
            else:
                _notify_chunk_dormant(player_peer_id, target_chunk, chunk_info)

func _initiate_handoff(player_peer_id: int, target_chunk: String):
    var host_info = ChunkRegistry.get_chunk_host(target_chunk)
    var player_data = _get_player_data(player_peer_id)

    # Request handoff from chunk host
    var handoff_request = {
        "visitor_id": player_data.id,
        "visitor_name": player_data.username,
        "visitor_level": player_data.level,
        "visitor_appearance": player_data.appearance,
        "from_chunk": player_data.current_chunk,
    }

    # RPC to chunk host (via relay or direct if possible)
    _send_to_chunk_host(target_chunk, "prepare_visitor", handoff_request)

func _on_chunk_host_ready(target_chunk: String, session_token: String, player_peer_id: int):
    var host_info = ChunkRegistry.get_chunk_host(target_chunk)

    # Send connection details to player
    rpc_id(player_peer_id, "handoff_to_chunk", {
        "chunk_coords": target_chunk,
        "host_ip": host_info.ip,
        "host_port": host_info.port,
        "session_token": session_token,
        "chunk_name": ChunkRegistry.get_chunk_info(target_chunk).chunk_name,
    })

func _notify_chunk_dormant(player_peer_id: int, chunk_coords: String, chunk_info: Dictionary):
    rpc_id(player_peer_id, "chunk_unavailable", {
        "chunk_coords": chunk_coords,
        "owner_name": chunk_info.owner_name,
        "chunk_name": chunk_info.chunk_name,
        "reason": "Owner is offline. This territory is dormant.",
    })


# === CHUNK HOST (Player's PC) ===
# ChunkHost.gd

var visitor_sessions: Dictionary = {}  # session_token -> visitor_data
var connected_visitors: Dictionary = {}  # peer_id -> player_data

const MAX_VISITORS = 10  # Limit visitors to prevent overload

@rpc("authority", "call_remote")
func prepare_visitor(request: Dictionary):
    if connected_visitors.size() >= MAX_VISITORS:
        _notify_central("visitor_rejected", {
            "reason": "Chunk at capacity",
            "visitor_id": request.visitor_id
        })
        return

    # Generate session token
    var token = _generate_session_token()

    visitor_sessions[token] = {
        "visitor_id": request.visitor_id,
        "visitor_name": request.visitor_name,
        "visitor_level": request.visitor_level,
        "visitor_appearance": request.visitor_appearance,
        "created_at": Time.get_unix_time_from_system(),
        "expires_at": Time.get_unix_time_from_system() + 30,  # 30 sec to connect
    }

    # Notify central we're ready
    _notify_central("visitor_ready", {
        "session_token": token,
        "visitor_id": request.visitor_id,
    })

func _on_peer_connected(peer_id: int):
    # New connection - wait for authentication
    pass

@rpc("any_peer", "call_remote")
func authenticate_visitor(session_token: String):
    var peer_id = multiplayer.get_remote_sender_id()

    if not visitor_sessions.has(session_token):
        rpc_id(peer_id, "authentication_failed", "Invalid session")
        # Disconnect after short delay
        _schedule_disconnect(peer_id, 1.0)
        return

    var session = visitor_sessions[session_token]

    # Check expiry
    if Time.get_unix_time_from_system() > session.expires_at:
        rpc_id(peer_id, "authentication_failed", "Session expired")
        visitor_sessions.erase(session_token)
        _schedule_disconnect(peer_id, 1.0)
        return

    # Valid! Register visitor
    connected_visitors[peer_id] = {
        "id": session.visitor_id,
        "name": session.visitor_name,
        "level": session.visitor_level,
        "appearance": session.visitor_appearance,
    }
    visitor_sessions.erase(session_token)

    # Spawn visitor in chunk
    _spawn_visitor(peer_id, connected_visitors[peer_id])

    # Send chunk state
    rpc_id(peer_id, "chunk_state", _get_full_chunk_state())

    print("[ChunkHost] Visitor %s connected" % session.visitor_name)

func _spawn_visitor(peer_id: int, visitor_data: Dictionary):
    # Create network player for visitor
    var entry_point = _get_chunk_entry_point()

    # Notify all connected players (owner + other visitors)
    rpc("visitor_joined", {
        "peer_id": peer_id,
        "name": visitor_data.name,
        "level": visitor_data.level,
        "appearance": visitor_data.appearance,
        "position": entry_point,
    })


# === VISITING PLAYER CLIENT ===
# PlayerClient.gd

var central_connection: ENetMultiplayerPeer  # Always connected
var chunk_connection: ENetMultiplayerPeer    # Connected to current chunk host
var current_chunk_type: String = "core"      # "core" or "player_hosted"

@rpc("authority", "call_remote")
func handoff_to_chunk(handoff_data: Dictionary):
    print("Handoff to chunk: %s (%s)" % [handoff_data.chunk_name, handoff_data.chunk_coords])

    # Show loading/transition UI
    _show_chunk_transition_ui(handoff_data.chunk_name)

    # Connect to chunk host
    chunk_connection = ENetMultiplayerPeer.new()
    var err = chunk_connection.create_client(handoff_data.host_ip, handoff_data.host_port)

    if err != OK:
        _show_error("Failed to connect to chunk")
        return

    # Store token for authentication
    _pending_session_token = handoff_data.session_token
    _pending_chunk_coords = handoff_data.chunk_coords

    # Wait for connection, then authenticate
    chunk_connection.connect("peer_connected", _on_chunk_host_connected)

func _on_chunk_host_connected(peer_id: int):
    # Authenticate with session token
    chunk_connection.rpc_id(1, "authenticate_visitor", _pending_session_token)
    current_chunk_type = "player_hosted"

@rpc("authority", "call_remote")  # From chunk host
func chunk_state(state: Dictionary):
    # Load chunk content
    _hide_chunk_transition_ui()
    _load_chunk_state(state)
    print("Now in player-hosted chunk")

@rpc("authority", "call_remote")  # From central
func chunk_unavailable(info: Dictionary):
    # Show "dormant" message
    _show_dormant_chunk_ui(info)
    # Block movement into chunk
    _set_movement_boundary(info.chunk_coords)
```

---

## Chunk Snapshot System

For PvP events and backup/restore.

### Snapshot Data Structure

```gdscript
# ChunkSnapshot.gd

class_name ChunkSnapshot

var chunk_coords: String
var captured_at: int  # Unix timestamp
var owner_id: String
var version: int

# World state
var props: Array = []        # Trees, rocks, decorations
var enemies: Array = []      # Enemy positions, health, type
var structures: Array = []   # Player-built structures (future)
var loot_drops: Array = []   # Ground items
var harvestables: Array = [] # Resource node states

# Metadata
var hash: String             # For integrity verification

func capture_from_world(world: Node) -> void:
    captured_at = Time.get_unix_time_from_system()

    # Capture props
    for prop in world.get_node("Props").get_children():
        props.append({
            "type": prop.prop_type,
            "position": var_to_str(prop.global_position),
            "variant": prop.variant,
            "state": prop.get_state() if prop.has_method("get_state") else {},
        })

    # Capture enemies
    for enemy in world.get_node("Enemies").get_children():
        enemies.append({
            "type": enemy.enemy_type,
            "level": enemy.level,
            "position": var_to_str(enemy.global_position),
            "health": enemy.current_health,
            "max_health": enemy.max_health,
            "state": enemy.ai_state,
        })

    # Capture harvestables
    for harvestable in world.get_node("Harvestables").get_children():
        harvestables.append({
            "type": harvestable.resource_type,
            "position": var_to_str(harvestable.global_position),
            "remaining": harvestable.remaining_resources,
            "respawn_time": harvestable.respawn_timer,
        })

    # Capture ground loot
    for item in world.get_node("GroundItems").get_children():
        loot_drops.append({
            "item_data": item.item_data,
            "position": var_to_str(item.global_position),
        })

    # Generate hash
    hash = _generate_hash()

func restore_to_world(world: Node) -> void:
    # Clear existing
    _clear_node_children(world.get_node("Props"))
    _clear_node_children(world.get_node("Enemies"))
    _clear_node_children(world.get_node("Harvestables"))
    _clear_node_children(world.get_node("GroundItems"))

    # Restore props
    for prop_data in props:
        var prop = _create_prop(prop_data)
        world.get_node("Props").add_child(prop)

    # Restore enemies
    for enemy_data in enemies:
        var enemy = _create_enemy(enemy_data)
        world.get_node("Enemies").add_child(enemy)

    # Restore harvestables
    for harvestable_data in harvestables:
        var harvestable = _create_harvestable(harvestable_data)
        world.get_node("Harvestables").add_child(harvestable)

    # Restore ground items
    for item_data in loot_drops:
        var item = _create_ground_item(item_data)
        world.get_node("GroundItems").add_child(item)

func to_bytes() -> PackedByteArray:
    var data = {
        "coords": chunk_coords,
        "captured_at": captured_at,
        "owner_id": owner_id,
        "version": version,
        "props": props,
        "enemies": enemies,
        "structures": structures,
        "loot_drops": loot_drops,
        "harvestables": harvestables,
        "hash": hash,
    }
    return var_to_bytes(data).compress(FileAccess.COMPRESSION_GZIP)

static func from_bytes(bytes: PackedByteArray) -> ChunkSnapshot:
    var data = bytes_to_var(bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
    var snapshot = ChunkSnapshot.new()
    snapshot.chunk_coords = data.coords
    snapshot.captured_at = data.captured_at
    snapshot.owner_id = data.owner_id
    snapshot.version = data.version
    snapshot.props = data.props
    snapshot.enemies = data.enemies
    snapshot.structures = data.structures
    snapshot.loot_drops = data.loot_drops
    snapshot.harvestables = data.harvestables
    snapshot.hash = data.hash
    return snapshot

func _generate_hash() -> String:
    var content = str(props) + str(enemies) + str(harvestables) + str(loot_drops)
    return content.sha256_text().substr(0, 16)
```

### Snapshot Triggers

```gdscript
# ChunkHost.gd - When to capture snapshots

# 1. Periodic auto-save (every 5 minutes while hosting)
func _on_autosave_timer():
    var snapshot = ChunkSnapshot.new()
    snapshot.capture_from_world(world)

    # Save locally
    _save_snapshot_locally(snapshot)

    # Upload to central (compressed, ~10-50KB typically)
    _upload_snapshot_to_central(snapshot)

# 2. When stopping hosting (player logging off)
func _on_stop_hosting():
    var snapshot = ChunkSnapshot.new()
    snapshot.capture_from_world(world)
    _save_snapshot_locally(snapshot)
    _upload_snapshot_to_central(snapshot)

    # Notify central we're going offline
    _notify_central("chunk_going_offline", my_chunk_coords)

# 3. Before PvP event (forced snapshot)
@rpc("authority", "call_remote")  # From central
func request_pvp_snapshot():
    var snapshot = ChunkSnapshot.new()
    snapshot.capture_from_world(world)

    # Send directly to central for PvP instance
    _upload_snapshot_to_central(snapshot, "pvp_event")
```

---

## PvP Event System

Wars and raids happen on neutral ground (central server) using snapshots.

### PvP Event Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: War Declaration                                             │
│                                                                     │
│   Player B declares war on Player A's chunk [5,0]                   │
│   Central server: Validates B has war tokens/requirements           │
│   Central server: Notifies A of incoming war (24hr warning?)        │
│   Central server: Schedules PvP event                               │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 2: Event Preparation (T-5 minutes)                             │
│                                                                     │
│   Central → A's Host: "Request snapshot for PvP"                    │
│   A's Host → Central: Uploads current chunk snapshot                │
│   Central: Spins up temporary PvP instance with snapshot            │
│   Central: Notifies both players event starting soon                │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 3: PvP Event (30 minute war)                                   │
│                                                                     │
│   Both players teleported to PvP instance (on central server)       │
│   A defends their chunk layout                                      │
│   B attacks, tries to destroy/capture objectives                    │
│   PvP damage enabled, respawns at edges                             │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│ STEP 4: Resolution                                                  │
│                                                                     │
│   War ends: Score calculated (kills, objectives, survival)          │
│   Winner determined                                                 │
│                                                                     │
│   IF ATTACKER WINS:                                                 │
│     - Attacker can loot X% of chunk resources                       │
│     - OR claim chunk ownership (defender loses it)                  │
│     - Snapshot updated with damage/losses                           │
│                                                                     │
│   IF DEFENDER WINS:                                                 │
│     - Defender keeps everything                                     │
│     - Attacker loses war tokens/entry fee                           │
│     - Defender gets bonus rewards                                   │
│                                                                     │
│   Central → A's Host: "Here's post-war snapshot" (if any changes)   │
│   Both players returned to their previous locations                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### PvP Instance Implementation

```gdscript
# CentralServer.gd - PvP Event Manager

class PvPEvent:
    var event_id: String
    var attacker_id: String
    var defender_id: String
    var target_chunk: String
    var scheduled_time: int
    var status: String  # "scheduled", "preparing", "active", "completed"
    var instance_scene: Node
    var snapshot: ChunkSnapshot
    var scores: Dictionary = {"attacker": 0, "defender": 0}

var active_pvp_events: Dictionary = {}  # event_id -> PvPEvent

func declare_war(attacker_peer_id: int, target_chunk: String) -> Dictionary:
    var attacker_id = _get_player_id(attacker_peer_id)
    var chunk_info = ChunkRegistry.get_chunk_info(target_chunk)

    # Validations
    if chunk_info.type != "player":
        return {"success": false, "error": "Can only attack player chunks"}

    if chunk_info.owner_id == attacker_id:
        return {"success": false, "error": "Cannot attack your own chunk"}

    if not _player_has_war_tokens(attacker_id):
        return {"success": false, "error": "Need war tokens to declare war"}

    # Check defender not already in a war
    for event in active_pvp_events.values():
        if event.defender_id == chunk_info.owner_id and event.status != "completed":
            return {"success": false, "error": "Defender already in active war"}

    # Create event
    var event = PvPEvent.new()
    event.event_id = _generate_event_id()
    event.attacker_id = attacker_id
    event.defender_id = chunk_info.owner_id
    event.target_chunk = target_chunk
    event.scheduled_time = Time.get_unix_time_from_system() + WAR_NOTICE_PERIOD
    event.status = "scheduled"

    active_pvp_events[event.event_id] = event

    # Consume war token
    _consume_war_token(attacker_id)

    # Notify both players
    _notify_player(attacker_id, "war_declared", {
        "event_id": event.event_id,
        "target_chunk": target_chunk,
        "defender_name": chunk_info.owner_name,
        "scheduled_time": event.scheduled_time,
    })

    _notify_player(chunk_info.owner_id, "war_incoming", {
        "event_id": event.event_id,
        "attacker_name": _get_player_name(attacker_id),
        "chunk_name": chunk_info.chunk_name,
        "scheduled_time": event.scheduled_time,
    })

    return {"success": true, "event_id": event.event_id}

func _start_pvp_event(event_id: String):
    var event = active_pvp_events[event_id]
    event.status = "preparing"

    # Request snapshot from defender's host (if online)
    if ChunkRegistry.is_chunk_online(event.target_chunk):
        _request_snapshot_from_host(event.target_chunk, event_id)
    else:
        # Use last known snapshot from central storage
        event.snapshot = _load_stored_snapshot(event.target_chunk)
        _launch_pvp_instance(event)

func _on_snapshot_received(event_id: String, snapshot: ChunkSnapshot):
    var event = active_pvp_events[event_id]
    event.snapshot = snapshot
    _launch_pvp_instance(event)

func _launch_pvp_instance(event: PvPEvent):
    # Create isolated game world instance
    var instance = preload("res://scenes/pvp_arena.tscn").instantiate()
    instance.name = "PvP_" + event.event_id
    add_child(instance)

    # Load chunk snapshot into instance
    event.snapshot.restore_to_world(instance.get_node("World"))

    # Configure PvP rules
    instance.pvp_enabled = true
    instance.friendly_fire = true
    instance.respawn_time = 10.0
    instance.time_limit = PVP_DURATION

    event.instance_scene = instance
    event.status = "active"

    # Teleport players to instance
    _teleport_player_to_instance(event.attacker_id, instance, "attacker_spawn")
    _teleport_player_to_instance(event.defender_id, instance, "defender_spawn")

    # Start event timer
    _start_pvp_timer(event.event_id, PVP_DURATION)

func _end_pvp_event(event_id: String):
    var event = active_pvp_events[event_id]
    event.status = "completed"

    # Calculate winner
    var winner = "defender" if event.scores.defender >= event.scores.attacker else "attacker"

    # Apply results
    if winner == "attacker":
        _apply_attacker_victory(event)
    else:
        _apply_defender_victory(event)

    # Return players to normal world
    _return_player_from_instance(event.attacker_id)
    _return_player_from_instance(event.defender_id)

    # Cleanup instance
    event.instance_scene.queue_free()

    # Archive event
    _archive_pvp_event(event)

const WAR_NOTICE_PERIOD = 86400  # 24 hours
const PVP_DURATION = 1800        # 30 minutes
```

---

## NAT Traversal Options

For player-to-player connections.

### Option 1: Steam Relay (Recommended if on Steam)

```gdscript
# Uses Steam's free relay network - handles NAT automatically
# Requires Steamworks SDK integration

# GodotSteam plugin handles this
func connect_via_steam_relay(steam_id: int):
    Steam.acceptP2PSessionWithUser(steam_id)
    # Steam handles NAT traversal automatically
```

### Option 2: Epic Online Services (Free)

```gdscript
# Epic provides free relay/NAT services
# Works even for non-Epic-exclusive games
```

### Option 3: UDP Hole Punching + TURN Fallback

```gdscript
# DIY approach with fallback relay

# 1. Try direct connection (works ~60% of time)
# 2. Try UDP hole punch via STUN (works ~80% of remaining)
# 3. Fall back to TURN relay (always works, you pay bandwidth)

# Cheap TURN providers:
# - Cloudflare (free tier available)
# - Twilio (pay per GB, cheap)
# - Self-hosted coturn on $5 VPS
```

### Option 4: Simple Relay on Central Server

```gdscript
# All chunk traffic routes through central
# Simpler but higher latency and bandwidth cost

# Good for testing, not ideal for production
```

---

## File Structure

```
scripts/
├── networking/
│   ├── CentralServer.gd      # Main server + services
│   ├── ChunkRegistry.gd      # Chunk ownership database
│   ├── ChunkHost.gd          # Player-side chunk hosting
│   ├── ChunkHandoff.gd       # Handoff protocol
│   ├── VisitorManager.gd     # Managing visitors in hosted chunk
│   └── PvPEventManager.gd    # War/raid coordination
├── systems/
│   ├── ChunkSnapshot.gd      # Snapshot capture/restore
│   └── ChunkPersistence.gd   # Local + cloud save
└── ui/
    ├── ChunkClaimUI.gd       # Claiming interface
    ├── ChunkMapUI.gd         # World map showing chunk ownership
    └── WarDeclarationUI.gd   # PvP event interface
```

---

## Migration Path

### Phase 1: Foundation (Current → Hybrid Ready)
1. Implement ChunkRegistry on central server
2. Add chunk claiming UI/mechanics
3. Test with "fake" player hosts (all on central)

### Phase 2: Player Hosting
1. Implement ChunkHost.gd for player PCs
2. Add handoff protocol
3. Test NAT traversal options
4. Implement snapshot system

### Phase 3: PvP Events
1. Build PvP instance system
2. Implement war declaration flow
3. Add PvP scoring and rewards
4. Balance war mechanics

### Phase 4: Polish
1. Add guild chunk support
2. Improve chunk map UI
3. Add chunk upgrades/customization
4. Performance optimization

---

## Cost Analysis

| Component | Who Pays | Monthly Cost |
|-----------|----------|--------------|
| Central server (3 core chunks + services) | Developer | $10-20 |
| Player chunk hosting | Players (their PCs) | $0 |
| Guild 24/7 hosting (optional) | Guilds | $5-10 each |
| PvP instance compute | Developer | ~$0.01/event |
| NAT relay (if needed) | Developer | $0-10 |
| **Total for 200 players** | **Developer** | **$15-40** |

**Per-player cost: $0.075 - $0.20** (down from $0.50)

---

## Security Considerations

### Chunk Host Trust Model

Player-hosted chunks are **semi-trusted**:

| What Host Controls | Trust Level | Mitigation |
|--------------------|-------------|------------|
| Enemy spawns/behavior | Full control | PvP uses central snapshots |
| Loot drops | Full control | Valuable items validated centrally |
| Visitor damage | Can cheat | PvP only on central server |
| Resource nodes | Full control | Trading validated centrally |

**Key principle:** Anything competitive (PvP, leaderboards, economy) runs on central server. Player chunks are for casual PvE and personal content.

### Preventing Abuse

```gdscript
# Central server validates:
# - Items brought OUT of player chunks (prevent item duping)
# - XP/gold gains (cap per hour from player chunks)
# - PvP results (only central-hosted PvP counts)

func validate_items_from_chunk(player_id: String, items: Array) -> Array:
    var validated = []
    for item in items:
        # Check item isn't impossibly rare
        if item.rarity == "legendary" and not _item_was_tracked(item.id):
            push_warning("Untracked legendary from player chunk - rejected")
            continue
        validated.append(item)
    return validated
```

---

## Summary

This hybrid architecture gives you:

1. **Low hosting costs** - Only pay for core infrastructure
2. **Infinite scaling** - More players = more player-hosted chunks
3. **Meaningful ownership** - Players host their own territory
4. **Fair PvP** - Wars happen on neutral central server
5. **Natural protection** - Offline chunks are dormant, not raidable

The tradeoff is complexity in the handoff system, but the code above provides a solid foundation.
