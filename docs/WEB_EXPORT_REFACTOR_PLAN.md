# Web Export Refactor Plan

## Goal

Make the game playable in a browser with zero download. Click a link → fighting for your country in 30 seconds.

---

## Current Blockers

| Blocker | Files Affected | Solution |
|---------|----------------|----------|
| ENet networking | NetworkManager.gd | Switch to WebSocketMultiplayerPeer |
| `user://` file storage | DatabaseManager.gd, Player.gd, AshbaneAuth.gd, LogManager.gd | Backend API + LocalStorage |
| OS.execute() calls | NetworkManager.gd, AshbaneAuth.gd | Remove or replace |
| Threading | ServerRunner.gd | Remove CLI admin (server-only feature) |

---

## Phase 1: Dual-Protocol Networking (Week 1-2)

### 1.1 Server: Support Both ENet AND WebSocket

The dedicated server needs to accept both protocols so:
- Desktop clients continue using ENet (proven, working)
- Web clients use WebSocket
- Same game logic, different transport

**File: `scripts/networking/NetworkManager.gd`**

```gdscript
# Add WebSocket support alongside ENet
var enet_peer: ENetMultiplayerPeer
var websocket_server: WebSocketMultiplayerPeer
var is_web_build: bool = OS.has_feature("web")

func start_server(port: int = 7777, ws_port: int = 7778) -> Error:
    # ENet for desktop clients
    enet_peer = ENetMultiplayerPeer.new()
    var enet_error = enet_peer.create_server(port, MAX_PLAYERS)

    # WebSocket for web clients
    websocket_server = WebSocketMultiplayerPeer.new()
    var ws_error = websocket_server.create_server(ws_port)

    # Use MultiplayerPeerExtension to bridge both?
    # OR run two multiplayer instances
    # OR use a proxy layer

    return OK

func connect_to_server(address: String, port: int) -> Error:
    if is_web_build:
        # Web: Use WebSocket
        var ws_peer = WebSocketMultiplayerPeer.new()
        var url = "wss://%s:%d" % [address, port + 1]  # WS on port+1
        var error = ws_peer.create_client(url)
        multiplayer.multiplayer_peer = ws_peer
    else:
        # Desktop: Use ENet (existing code)
        var enet_peer = ENetMultiplayerPeer.new()
        var error = enet_peer.create_client(address, port)
        multiplayer.multiplayer_peer = enet_peer

    return OK
```

### 1.2 Challenge: Bridging Two Protocols

Godot's MultiplayerAPI only supports one peer at a time. Options:

**Option A: WebSocket-Only Server**
- Server uses WebSocket only
- Desktop clients also use WebSocket
- Simplest, but WebSocket has slightly more overhead than ENet

**Option B: Proxy Server**
- Separate process bridges ENet ↔ WebSocket
- Server stays ENet, proxy translates for web clients
- More complex, but best performance for desktop

**Option C: Two Server Instances**
- Run two Godot server instances (one ENet, one WebSocket)
- Share game state via backend/Redis
- Most complex, but allows independent scaling

**Recommendation: Option A (WebSocket-Only)**

For initial web launch, switch everything to WebSocket. It works on both desktop and web. Slight performance hit (~5-10% more overhead) but dramatically simpler.

### 1.3 Implementation Steps

1. [ ] Create `WebSocketNetworkManager.gd` as alternative to current ENet-based system
2. [ ] Add `is_web_build` detection: `OS.has_feature("web")`
3. [ ] Abstract the peer creation behind a factory function
4. [ ] Update server to use WebSocket: `WebSocketMultiplayerPeer.create_server()`
5. [ ] Update client to use WebSocket: `WebSocketMultiplayerPeer.create_client()`
6. [ ] Test desktop client with WebSocket server
7. [ ] Test web export with WebSocket server

---

## Phase 2: Storage Migration (Week 2-3)

### 2.1 Current Storage Usage

| File | What's Stored | Migration Strategy |
|------|---------------|-------------------|
| `DatabaseManager.gd` | Player data JSON | Already syncs to backend - make backend authoritative |
| `AshbaneAuth.gd` | Session token | Browser LocalStorage |
| `Player.gd` | Settings config | Browser LocalStorage |
| `LogManager.gd` | Log files | Console.log for web, skip file writes |
| `ServerRunner.gd` | Bug reports | Backend API endpoint |

### 2.2 Browser LocalStorage Wrapper

**New file: `scripts/systems/WebStorage.gd`**

```gdscript
extends Node
class_name WebStorage

## Cross-platform storage that works on both desktop and web
## Desktop: uses user:// files
## Web: uses browser LocalStorage via JavaScript

static func save_string(key: String, value: String) -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.eval("localStorage.setItem('%s', '%s')" % [key, value.c_escape()])
    else:
        var file = FileAccess.open("user://%s.dat" % key, FileAccess.WRITE)
        if file:
            file.store_string(value)

static func load_string(key: String, default: String = "") -> String:
    if OS.has_feature("web"):
        var result = JavaScriptBridge.eval("localStorage.getItem('%s')" % key)
        return result if result else default
    else:
        var file = FileAccess.open("user://%s.dat" % key, FileAccess.READ)
        if file:
            return file.get_as_text()
        return default

static func delete(key: String) -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.eval("localStorage.removeItem('%s')" % key)
    else:
        DirAccess.remove_absolute("user://%s.dat" % key)

static func save_json(key: String, data: Variant) -> void:
    save_string(key, JSON.stringify(data))

static func load_json(key: String, default: Variant = null) -> Variant:
    var json_string = load_string(key, "")
    if json_string.is_empty():
        return default
    return JSON.parse_string(json_string)
```

### 2.3 Migration Steps

1. [ ] Create `WebStorage.gd` utility class
2. [ ] Update `AshbaneAuth.gd`: session token → WebStorage
3. [ ] Update `Player.gd`: settings → WebStorage
4. [ ] Update `LogManager.gd`: skip file writes on web, use console
5. [ ] Update `DatabaseManager.gd`: ensure backend is authoritative, local cache optional
6. [ ] Remove/guard all `DirAccess` operations with `not OS.has_feature("web")`

---

## Phase 3: OS-Specific Code (Week 3)

### 3.1 Things That Don't Work on Web

| Code | Location | Fix |
|------|----------|-----|
| `OS.execute("git", ...)` | NetworkManager.gd | Skip on web, use build-time version |
| `OS.shell_open(url)` | Multiple files | Use JavaScriptBridge.eval("window.open()") |
| `Thread.new()` | ServerRunner.gd | Skip CLI admin on web (not needed) |
| `DirAccess.make_dir()` | Multiple | Guard with `not OS.has_feature("web")` |

### 3.2 Implementation

**URL opening on web:**
```gdscript
func open_url(url: String) -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.eval("window.open('%s', '_blank')" % url)
    else:
        OS.shell_open(url)
```

**Version string:**
```gdscript
func get_version() -> String:
    if OS.has_feature("web"):
        return "web-1.0.0"  # Or read from bundled version.txt
    else:
        # Existing git hash code
        ...
```

---

## Phase 4: Web Export Configuration (Week 3-4)

### 4.1 Export Preset

**File: `export_presets.cfg`** (add web preset)

```ini
[preset.web]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="exports/web/index.html"

[preset.web.options]
html/export_icon=true
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=true
progressive_web_app/offline_page="offline.html"
```

### 4.2 HTTPS Requirement

WebSocket connections from HTTPS pages must use WSS (secure WebSocket).

**Server needs:**
- SSL certificate (Let's Encrypt)
- WSS endpoint on port 443 or custom port
- Reverse proxy (nginx) to handle SSL termination

**Nginx config example:**
```nginx
server {
    listen 443 ssl;
    server_name game.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    location /ws {
        proxy_pass http://localhost:7778;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### 4.3 CORS for Backend API

Backend needs to allow cross-origin requests from the web game:

```python
# FastAPI
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://yourgame.itch.io", "https://yourdomain.com"],
    allow_methods=["*"],
    allow_headers=["*"],
)
```

---

## Phase 5: Testing & Polish (Week 4-5)

### 5.1 Browser Testing Matrix

| Browser | Priority | Notes |
|---------|----------|-------|
| Chrome | High | Most users |
| Firefox | High | Second most |
| Safari | Medium | iOS/Mac users, strictest security |
| Edge | Low | Uses Chromium |

### 5.2 Known Web Issues to Test

- [ ] WebSocket connection stability (browsers close idle connections after ~60s)
- [ ] Audio autoplay restrictions (need user interaction first)
- [ ] Fullscreen API differences
- [ ] Mobile touch input (if supporting mobile browsers)
- [ ] Memory limits (~2GB in most browsers)
- [ ] IndexedDB quota warnings

### 5.3 Keepalive for WebSocket

Browsers close idle WebSocket connections. Add ping/pong:

```gdscript
# Server-side
var keepalive_timer: Timer

func _ready():
    keepalive_timer = Timer.new()
    keepalive_timer.wait_time = 30.0
    keepalive_timer.timeout.connect(_send_keepalive)
    add_child(keepalive_timer)
    keepalive_timer.start()

func _send_keepalive():
    # Send ping to all connected clients
    rpc("_client_keepalive", Time.get_unix_time_from_system())

@rpc("authority", "reliable")
func _client_keepalive(server_time: float):
    pass  # Just keeping the connection alive
```

---

## Phase 6: Deployment (Week 5-6)

### 6.1 Hosting Options

| Platform | Pros | Cons |
|----------|------|------|
| **Itch.io** | Free, built-in audience, easy | Limited customization |
| **GitHub Pages** | Free, custom domain | Static only, need separate WS server |
| **Netlify/Vercel** | Free tier, fast CDN | Static only |
| **DigitalOcean App** | Full control | Costs money |

**Recommendation:** Itch.io for the game files, your existing DigitalOcean for the WebSocket server.

### 6.2 Itch.io Upload

1. Export web build from Godot
2. Zip the output folder
3. Upload to itch.io
4. Set "This file will be played in the browser"
5. Configure embed dimensions (viewport size)

### 6.3 WebSocket Server Deployment

Add to your existing DigitalOcean server:

```bash
# WebSocket server (for web clients) - default
godot --headless -- --server --port 7777

# ENet server (for desktop clients only)
godot --headless -- --server --port 7777 --enet
```

The server now defaults to WebSocket, which supports both web and desktop clients.

---

## File Change Summary

| File | Changes | Status |
|------|---------|--------|
| `scripts/networking/NetworkManager.gd` | Add WebSocket peer option | DONE |
| `scripts/systems/WebStorage.gd` | NEW - cross-platform storage | DONE |
| `scripts/systems/AshbaneAuth.gd` | Use WebStorage for session | DONE |
| `scripts/systems/DatabaseManager.gd` | Guard file ops, use backend | N/A (server-only) |
| `scripts/systems/LogManager.gd` | Skip file writes on web | DONE |
| `scripts/player/Player.gd` | Settings via WebStorage | Deferred |
| `scripts/ServerRunner.gd` | WebSocket server support + CLI args | DONE |
| `export_presets.cfg` | Web export preset | EXISTS |
| `project.godot` | Web-compatible settings | TODO |
| Backend nginx config | Add WSS proxy | TODO |
| Backend FastAPI | Add CORS headers | TODO |

---

## Success Criteria

- [ ] Game loads in Chrome, Firefox, Safari
- [ ] Player can connect to server via WebSocket
- [ ] Combat works identically to desktop
- [ ] Settings persist across browser sessions
- [ ] Auth tokens persist (stay logged in)
- [ ] Can play full match without disconnection
- [ ] Works on itch.io embed

---

## Timeline

| Week | Focus |
|------|-------|
| 1 | WebSocket networking (client + server) |
| 2 | Storage migration + testing |
| 3 | OS-specific fixes + export config |
| 4 | Browser testing + bug fixes |
| 5 | Deployment + itch.io setup |
| 6 | Buffer for issues |

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| WebSocket less reliable than ENet | Add reconnection logic, keepalive |
| Browser memory limits | Monitor memory, optimize assets |
| Safari being difficult | Test early, have fallback messaging |
| SSL certificate issues | Use Let's Encrypt auto-renewal |

---

## Revision History

| Date | Change |
|------|--------|
| 2026-01-23 | Initial plan |
| 2026-01-23 | Implemented: NetworkManager WebSocket, WebStorage, AshbaneAuth, LogManager, ServerRunner |
