# Dedicated Server Operations Guide

This document covers the complete setup, configuration, and maintenance of the Ashbane dedicated server. It consolidates lessons learned from debugging memory leaks, CPU issues, and multiplayer desync problems.

---

## Quick Reference

```bash
# Start server
systemctl start ashbane-game

# Stop server
systemctl stop ashbane-game

# Check status and memory
systemctl status ashbane-game

# View live logs
journalctl -u ashbane-game -f

# Rebuild and deploy (USE THIS - handles project file swap)
cd /opt/ashbane-game/source
./build_server.sh
systemctl restart ashbane-game
```

**Note:** The service is `ashbane-game.service` (port 7777), not `ashbane-server.service` (deprecated, port 7000).

**IMPORTANT:** Always use `./build_server.sh` instead of running godot export directly. The script handles swapping `project.server.godot` in place of `project.godot` during export, then restores it. This prevents server stub autoloads from polluting the client config in git.

---

## 1. Server Export Configuration

### Godot Export Settings

The server uses a separate export profile "Linux Server" in `export_presets.cfg`:

```ini
[preset.1]
name="Linux Server"
platform="Linux"
runnable=true
dedicated_server=true
custom_features="dedicated_server"
export_filter="all_resources"
```

Key settings:
- `dedicated_server=true` - Enables headless mode
- No need for `--headless` flag at runtime (baked in)

### Project Configuration

**Monorepo Workflow:**
```
project.godot          # CLIENT version (real UI autoloads) - committed from client only
project.server.godot   # SERVER version (stubs) - used for server exports
build_server.sh        # Handles project file swap during export
```

The server uses `project.server.godot` which replaces UI autoloads with stubs:
- AccountAdmin, CursorManager, VFXLayer, ItemIconGenerator
- GroupUI, TutorialManager, QuestTrackerUI, BugReportUI
- MobileInput, AshbaneCosmetics, ForgeVisualEffects
- Various UI managers

**Git Configuration (on server machine):**
```bash
# Prevent server from pushing project.godot changes
git update-index --skip-worktree project.godot
```

This ensures pulls update scripts but don't overwrite the local project.godot, and pushes don't include server stub changes.

---

## 2. Systemd Service Configuration

### /etc/systemd/system/ashbane-game.service

```ini
[Unit]
Description=Ashbane Game Server (Godot)
After=network.target

[Service]
Type=simple
User=root
Nice=10
WorkingDirectory=/opt/ashbane-game/server
Environment=GODOT_SILENCE_ROOT_WARNING=1
ExecStartPre=/bin/bash -c 'fuser -k 7777/udp 2>/dev/null || true'
ExecStart=/opt/ashbane-game/server/ashbane-server.x86_64 --headless --max-fps 30 -- --server --port 7777 --shard shard-1
Restart=always
RestartSec=10
StandardOutput=append:/opt/ashbane-game/logs/game.log
StandardError=append:/opt/ashbane-game/logs/game.log

# Resource limits
LimitNOFILE=65536
MemoryMax=1500M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
```

### Key Points:
- **Port 7777** - Matches client `DEFAULT_PORT` in NetworkManager.gd
- `Restart=always` - Auto-restart on crash
- `RestartSec=10` - Wait 10 seconds before restart (prevents rapid restart loops)
- `ExecStartPre` - Kills any zombie processes on port 7777 before starting
- `--max-fps 30` - Limits server to 30 FPS to reduce CPU usage
- Logs go to `/opt/ashbane-game/logs/game.log`

### Commands:
```bash
# Reload after editing service file
systemctl daemon-reload

# Enable auto-start on boot
systemctl enable ashbane-game

# Disable auto-start
systemctl disable ashbane-game
```

### Deprecated Service
The old `ashbane-server.service` (port 7000) is deprecated and disabled. Do not use it.

---

## 3. Memory Leak Prevention

### Critical Pattern: Server Guards

ALL visual/UI code MUST be guarded on the server. The server doesn't need:
- Sprites, textures, images
- Tweens for visual animations
- Particle effects
- UI elements

### Standard Server Guard Pattern

```gdscript
var _is_server_mode: bool = false

func _ready() -> void:
    _is_server_mode = "--server" in OS.get_cmdline_user_args()

    # Server only needs collision/stats, no visuals
    if _is_server_mode:
        if sprite:
            sprite.queue_free()
        if health_bar:
            health_bar.queue_free()
        return

    # Client-only visual setup below
    setup_sprite()
    setup_effects()
```

### Known Leak Sources (Fixed)

| File | Issue | Fix |
|------|-------|-----|
| Enemy.gd | `rot_and_despawn()` created tweens | Skip tween, direct `queue_free()` |
| Enemy.gd | `graceful_despawn()` created tweens | Skip tween, direct `queue_free()` |
| Enemy.gd | `create_shadow_layer()` created textures | Server guard |
| Spider.gd | `_ready()` created sprites | Server guard |
| Wolf.gd | `_ready()` created sprites | Server guard |
| PlayerCorpse.gd | `_ready()` created visuals | Server guard |
| HealthBar.gd | `update_health()` created tweens | Check `if not fill: return` |
| EnemyAI.gd | Attack feedback tweens | Server guard |

### Detecting Memory Leaks

Monitor heartbeat logs for node count growth:
```
[HEARTBEAT] uptime=10m | objects=3350 | nodes=1548 | orphans=0
[HEARTBEAT] uptime=11m | objects=3398 | nodes=1596 | orphans=0  # +48 nodes = LEAK
```

Stable server should have ~0 node growth when idle (no players).

### Finding Leak Sources

Search for patterns that create nodes on server:
```bash
grep -rn "create_tween" scripts/ --include="*.gd"
grep -rn "Image.create\|ImageTexture" scripts/ --include="*.gd"
grep -rn "\.instantiate()" scripts/ --include="*.gd"
```

---

## 4. CPU Optimization

### Headless Mode Settings

The server runs in headless mode which disables rendering, but physics and scripts still run.

### Frame Rate Limiting

Server should run at lower FPS than clients:
```gdscript
# In ServerRunner.gd or game_world.gd
if "--server" in OS.get_cmdline_user_args():
    Engine.max_fps = 30  # Server doesn't need 60fps
```

Or via command line:
```bash
./ashbane-server.x86_64 --headless --max-fps 30 -- --server --port 7000
```

### Process Throttling

Disable unnecessary processing on server:
```gdscript
if _is_server_mode:
    set_process(false)  # Disable _process()
    set_physics_process(false)  # If not needed
```

---

## 5. Preventing Zombie Servers

### Problem
Multiple server processes can accumulate if:
- Service restarts while old process is still running
- Manual starts without stopping service
- Export/test runs without cleanup

### Solution: Always Check Before Starting

```bash
# Check for running servers
pgrep -a ashbane

# Kill all server processes
pkill -9 -f ashbane-server

# Then start fresh
systemctl start ashbane-server
```

### Clean Restart Script

```bash
#!/bin/bash
# restart_server.sh
systemctl stop ashbane-server 2>/dev/null
pkill -9 -f ashbane-server 2>/dev/null
sleep 2
systemctl start ashbane-server
systemctl status ashbane-server
```

---

## 6. Multiplayer Synchronization

### Spawn Position Authority

**Problem**: If spawn position is generated client-side, each client gets different positions causing desync ("magnetization").

**Solution**: Server generates all spawn positions and sends to clients:
```gdscript
# WRONG - each client generates different position
spawn_player.rpc(id, Vector2.ZERO, ...)

# CORRECT - server generates authoritative position
var server_spawn_pos = get_spawn_point()
spawn_player.rpc(id, server_spawn_pos, ...)
```

### Position Sync Flow

1. Local player moves via `_physics_process()` + `move_and_slide()`
2. Local player broadcasts position via `_sync_local_player_position()`
3. Remote clients receive via `_receive_player_position()`
4. Remote player interpolates to received position

### RPC Security

Always verify sender matches claimed player:
```gdscript
var sender_id = multiplayer.get_remote_sender_id()
if sender_id != player_id and sender_id != 1:  # 1 = server
    return  # Reject spoofed updates
```

---

## 7. Logging and Monitoring

### Log Locations

- **Systemd journal**: `journalctl -u ashbane-server`
- **Game log**: `/opt/ashbane-game/logs/game.log`

### Heartbeat Monitoring

The server logs heartbeat every minute with key metrics:
```
[HEARTBEAT] uptime=10m | mem=72.8MB | objects=3350 | nodes=1548 | orphans=0
```

Watch for:
- `mem` - Should stay stable (72-80MB typical)
- `nodes` - Should not grow continuously
- `orphans` - Should always be 0

### Useful Commands

```bash
# Live memory monitoring
watch -n 5 'systemctl status ashbane-server | grep Memory'

# Check for errors
journalctl -u ashbane-server | grep -i error | tail -20

# Check player connections
journalctl -u ashbane-server | grep -i "player.*connect" | tail -20
```

---

## 8. Deployment Checklist

### Before Deploying New Build

1. [ ] Stop the server: `systemctl stop ashbane-server`
2. [ ] Kill any zombie processes: `pkill -9 -f ashbane-server`
3. [ ] Pull latest code: `cd /opt/ashbane-game/source && git pull`
4. [ ] Export server build:
   ```bash
   /usr/local/bin/godot45 --headless --export-release "Linux Server" /opt/ashbane-game/server/ashbane-server.x86_64
   ```
5. [ ] Clear old logs: `echo "" > /opt/ashbane-game/logs/game.log`
6. [ ] Start server: `systemctl start ashbane-server`
7. [ ] Verify startup: `systemctl status ashbane-server`
8. [ ] Check for errors: `journalctl -u ashbane-server -n 50`

### Health Check After Deploy

1. [ ] Memory stable at ~72-73MB
2. [ ] No error spam in logs
3. [ ] Players can connect
4. [ ] Players spawn at different positions
5. [ ] No node count growth when idle

---

## 9. Common Issues and Solutions

### Server Crashes on Startup

**Cause**: UI autoload tries to access display
**Fix**: Check `project.server.godot` has UI autoloads removed

### Memory Growing Continuously

**Cause**: Visual code creating nodes on server
**Fix**: Add server guards (see Section 3)

### Players "Magnetized" Together

**Cause**: Spawn position generated client-side
**Fix**: Server generates and broadcasts spawn position

### "Tween started with no Tweeners" Spam

**Cause**: Tween created but visual elements are null on server
**Fix**: Guard tween creation with null checks

### High CPU Usage

**Cause**: Running at client frame rate, unnecessary processing
**Fix**: Limit FPS, disable visual processing on server

### Multiple Server Processes

**Cause**: Restart without killing old process
**Fix**: Always `pkill -9 -f ashbane-server` before starting

---

## 10. File Locations

```
/opt/ashbane-game/
├── source/                    # Git repo with game code
│   ├── project.godot         # Client project file
│   ├── project.server.godot  # Server project file (fewer autoloads)
│   ├── export_presets.cfg    # Export configurations
│   └── scripts/              # Game scripts
├── server/                    # Deployed server build
│   ├── ashbane-server.x86_64 # Server executable
│   └── ashbane-server.pck    # Server resources
└── logs/
    └── game.log              # Game-specific logs

/etc/systemd/system/
└── ashbane-server.service    # Systemd service definition

/usr/local/bin/
└── godot45                   # Godot 4.5 editor for exports
```

---

## Revision History

- **2026-01-02**: Initial documentation after fixing memory leaks, spawn desync, and HealthBar tween spam
