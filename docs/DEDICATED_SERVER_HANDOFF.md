# Dedicated Server Setup - Godot Engineer Handoff

## Overview

This document covers setting up Ashbane to run with a dedicated headless server on DigitalOcean, with hotfixable balance constants from the backend API.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│                    DigitalOcean Droplet                         │
│                                                                 │
│   ┌─────────────────┐         ┌─────────────────┐              │
│   │ Backend API     │         │ Godot Headless  │              │
│   │ (FastAPI)       │         │ Server          │              │
│   │ Port 8000       │         │ Port 7000       │              │
│   │ ✅ DONE         │         │ 📋 TODO         │              │
│   └────────┬────────┘         └────────┬────────┘              │
└────────────┼───────────────────────────┼────────────────────────┘
             │                           │
        Players connect to both via api.ashbane.net
```

---

## Part 1: Game Config API (Backend - DONE)

The backend now serves hotfixable balance constants at:

```
GET https://api.ashbane.net/api/game/config
```

### Response Format

```json
{
  "combat": {
    "player_base_damage": 2.0,
    "player_attack_cooldown": 0.70,
    "player_attack_range": 100.0,
    "player_attack_cone_angle": 90.0,
    "crit_damage_multiplier": 1.5,
    "defense_constant": 100.0
  },
  "weapon_speeds": {
    "very_fast": 0.50,
    "fast": 0.65,
    "medium": 0.80,
    "slow": 0.95,
    "very_slow": 1.10
  },
  "duel": {
    "request_timeout": 30.0,
    "safe_aura_duration": 10.0,
    "max_distance": 100.0,
    "cancel_distance": 500.0,
    "countdown_duration": 3.0
  },
  "pvp_weakpoint": {
    "hp_thresholds": [0.70, 0.35],
    "window_duration": 3.5,
    "damage_per_hit": 3,
    "scale": 0.5
  },
  "enemies": {
    "base_health": 120.0,
    "health_scaling": 1.12,
    "base_damage": 7.0,
    "damage_scaling": 1.08
  },
  "ttk": {
    "trash_window": 4.0,
    "elite_window": 12.0,
    "boss_window": 45.0,
    "base_window_damage": 25.0
  },
  "economy": {
    "trade_tax_percent": 5.0,
    "trade_cooldown_hours": 24.0
  },
  "player": {
    "base_health": 100.0,
    "base_stamina": 100.0,
    "stamina_regen_rate": 15.0,
    "dash_stamina_cost": 25.0,
    "dash_cooldown": 0.5,
    "dash_duration": 0.2,
    "dash_speed": 400.0
  }
}
```

---

## Part 2: Godot Changes Required

### 2.1 Create GameConfig Autoload

Create `scripts/autoloads/GameConfig.gd`:

```gdscript
extends Node

# Cached config from backend
var config: Dictionary = {}
var config_loaded: bool = false

# Fallback defaults (used if API fails)
const DEFAULTS = {
    "combat": {
        "player_base_damage": 2.0,
        "player_attack_cooldown": 0.70,
        "player_attack_range": 100.0,
        "player_attack_cone_angle": 90.0,
        "crit_damage_multiplier": 1.5,
        "defense_constant": 100.0,
    },
    "weapon_speeds": {
        "very_fast": 0.50,
        "fast": 0.65,
        "medium": 0.80,
        "slow": 0.95,
        "very_slow": 1.10,
    },
    "duel": {
        "request_timeout": 30.0,
        "safe_aura_duration": 10.0,
        "max_distance": 100.0,
        "cancel_distance": 500.0,
        "countdown_duration": 3.0,
    },
    "pvp_weakpoint": {
        "hp_thresholds": [0.70, 0.35],
        "window_duration": 3.5,
        "damage_per_hit": 3,
        "scale": 0.5,
    },
    "enemies": {
        "base_health": 120.0,
        "health_scaling": 1.12,
        "base_damage": 7.0,
        "damage_scaling": 1.08,
    },
    "player": {
        "base_health": 100.0,
        "base_stamina": 100.0,
        "stamina_regen_rate": 15.0,
        "dash_stamina_cost": 25.0,
        "dash_cooldown": 0.5,
        "dash_duration": 0.2,
        "dash_speed": 400.0,
    },
}

signal config_ready


func _ready() -> void:
    config = DEFAULTS.duplicate(true)
    fetch_config()


func fetch_config() -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_config_received.bind(http))

    var url = AshbaneAuth.get_api_base() + "/api/game/config"
    var error = http.request(url)
    if error != OK:
        push_warning("GameConfig: Failed to start config request")
        config_loaded = true
        config_ready.emit()


func _on_config_received(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
    http.queue_free()

    if result == HTTPRequest.RESULT_SUCCESS and code == 200:
        var json = JSON.new()
        if json.parse(body.get_string_from_utf8()) == OK:
            var data = json.get_data()
            if data is Dictionary:
                _merge_config(data)
                print("GameConfig: Loaded from backend")
    else:
        push_warning("GameConfig: Using defaults (API returned %d)" % code)

    config_loaded = true
    config_ready.emit()


func _merge_config(remote: Dictionary) -> void:
    # Deep merge remote into config
    for key in remote:
        if config.has(key) and config[key] is Dictionary and remote[key] is Dictionary:
            for subkey in remote[key]:
                config[key][subkey] = remote[key][subkey]
        else:
            config[key] = remote[key]


# Helper getters
func get_combat(key: String, default = null):
    return config.get("combat", {}).get(key, default)

func get_weapon_speed(speed_class: String) -> float:
    return config.get("weapon_speeds", {}).get(speed_class, 0.80)

func get_duel(key: String, default = null):
    return config.get("duel", {}).get(key, default)

func get_enemy(key: String, default = null):
    return config.get("enemies", {}).get(key, default)

func get_player(key: String, default = null):
    return config.get("player", {}).get(key, default)
```

### 2.2 Register Autoload

In Project Settings → Autoload, add:
- Name: `GameConfig`
- Path: `res://scripts/autoloads/GameConfig.gd`
- Enable: ✓

### 2.3 Update Constants.gd Usage

Replace hardcoded values throughout the codebase:

**Before:**
```gdscript
const PLAYER_BASE_ATTACK_DAMAGE: float = 2.0
var damage = PLAYER_BASE_ATTACK_DAMAGE * modifier
```

**After:**
```gdscript
var damage = GameConfig.get_combat("player_base_damage", 2.0) * modifier
```

### 2.4 Key Files to Update

| File | What to Change |
|------|----------------|
| `Constants.gd` | Keep as fallbacks, but systems should read from GameConfig |
| `PlayerCombat.gd` | Use `GameConfig.get_combat()` for damage values |
| `DuelManager.gd` | Use `GameConfig.get_duel()` for duel rules |
| `Player.gd` | Use `GameConfig.get_player()` for stamina, dash, HP |
| `Enemy.gd` | Use `GameConfig.get_enemy()` for health/damage scaling |
| `CharacterStats.gd` | Use GameConfig for base values |

---

## Part 3: Dedicated Server Mode

### 3.1 Detect Headless Mode

Add to `NetworkManager.gd` or create new `DedicatedServer.gd`:

```gdscript
extends Node

var is_dedicated_server: bool = false

func _ready() -> void:
    is_dedicated_server = _detect_headless()

    if is_dedicated_server:
        print("=== DEDICATED SERVER MODE ===")
        _start_dedicated_server()


func _detect_headless() -> bool:
    # Check for headless/server feature tags
    if OS.has_feature("dedicated_server"):
        return true
    if DisplayServer.get_name() == "headless":
        return true
    # Command line override
    if "--server" in OS.get_cmdline_args():
        return true
    return false


func _start_dedicated_server() -> void:
    # Wait for config to load
    if not GameConfig.config_loaded:
        await GameConfig.config_ready

    print("Starting dedicated server on port 7000...")

    # Skip all menus, go straight to hosting
    var peer = ENetMultiplayerPeer.new()
    var error = peer.create_server(7000, 32)  # 32 max players

    if error != OK:
        push_error("Failed to create server: %s" % error)
        get_tree().quit(1)
        return

    multiplayer.multiplayer_peer = peer
    print("Server listening on port 7000")

    # Load the game world
    get_tree().change_scene_to_file("res://scenes/World.tscn")
```

### 3.2 Export Preset for Dedicated Server

In Godot Editor:
1. Project → Export → Add Preset → Linux
2. Name it "Linux Dedicated Server"
3. Options:
   - Embed PCK: ✓
   - Export Mode: Export as dedicated server (if available in Godot 4.x)
   - Or use feature tag: `dedicated_server`
4. Export as: `ashbane-server.x86_64`

### 3.3 Command Line Arguments

The server should support:

```bash
# Default port
./ashbane-server.x86_64 --server

# Custom port
./ashbane-server.x86_64 --server --port=7001

# With max players
./ashbane-server.x86_64 --server --max-players=64
```

---

## Part 4: Server Deployment

### 4.1 Upload Server Build

```bash
# From your local machine after exporting:
scp ashbane-server.x86_64 root@api.ashbane.net:/root/ashbane-game/
```

### 4.2 Systemd Service (I will create this)

The service file at `/etc/systemd/system/ashbane-game.service`:

```ini
[Unit]
Description=Ashbane Dedicated Game Server
After=network.target ashbane.service

[Service]
Type=simple
User=root
WorkingDirectory=/root/ashbane-game
ExecStart=/root/ashbane-game/ashbane-server.x86_64 --server --headless
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 4.3 Server Management Commands

```bash
# Start server
sudo systemctl start ashbane-game

# Stop server
sudo systemctl stop ashbane-game

# Restart (after uploading new build)
sudo systemctl restart ashbane-game

# View logs
sudo journalctl -u ashbane-game -f

# Check status
sudo systemctl status ashbane-game
```

---

## Part 5: Client Changes

### 5.1 Connect to Dedicated Server

Update client connection to use the server address:

```gdscript
func connect_to_server() -> void:
    var peer = ENetMultiplayerPeer.new()

    # Use dedicated server address
    var server_host = "api.ashbane.net"  # Or separate game.ashbane.net
    var server_port = 7000

    var error = peer.create_client(server_host, server_port)
    if error != OK:
        push_error("Failed to connect: %s" % error)
        return

    multiplayer.multiplayer_peer = peer
```

### 5.2 Remove Host Option from Client UI

Since we're using a dedicated server, players shouldn't be able to host their own games. Either:
- Remove the "Host Game" button entirely, OR
- Keep it for LAN/testing but default to "Connect to Server"

---

## Part 6: Patching Workflow

### Balance Change (Damage, HP, etc)
```
1. Edit GAME_CONFIG in backend/app/main.py
2. sudo systemctl restart ashbane
3. Done - takes effect in ~5 seconds
```

### Game Logic Change (Server-side: spawning, duels, sync)
```
1. Fix code in Godot
2. Export headless Linux build
3. scp ashbane-server.x86_64 root@api.ashbane.net:/root/ashbane-game/
4. sudo systemctl restart ashbane-game
5. Done - players reconnect automatically
```

### Client Change (UI, animations, rendering)
```
1. Fix code in Godot
2. Export Windows/Mac/Linux builds
3. Upload to itch.io
4. Players see "Update Available" and re-download
```

---

## Part 7: What Lives Where

### Backend API (instant hotfix)
- Balance constants (`/api/game/config`)
- Auth, achievements, trading
- Loot tables (if moved here)
- Player progression data

### Dedicated Godot Server (5-min patch)
- Multiplayer sync/replication
- Damage validation
- Duel state management
- Enemy spawning logic
- World state

### Client (requires player re-download)
- UI layouts and menus
- Animations and VFX
- Input handling
- Rendering
- Sound effects

---

## Checklist

- [ ] Create `GameConfig.gd` autoload
- [ ] Register autoload in Project Settings
- [ ] Update `PlayerCombat.gd` to use GameConfig
- [ ] Update `DuelManager.gd` to use GameConfig
- [ ] Update `Player.gd` to use GameConfig
- [ ] Update `Enemy.gd` to use GameConfig
- [ ] Add dedicated server detection to NetworkManager
- [ ] Create Linux export preset for dedicated server
- [ ] Test headless server locally
- [ ] Export and upload to DigitalOcean
- [ ] Test client connecting to dedicated server

---

## Testing Locally

### Run Headless Locally
```bash
# Export Linux build, then:
./ashbane-server.x86_64 --server --headless
```

### Or with Godot Editor
```bash
# Run with server flag
godot --headless -- --server
```

### Connect Client
Run the normal client and have it connect to `localhost:7000` for testing.
