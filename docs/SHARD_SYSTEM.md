# Shard System

> **Status**: Implemented (basic isolation). Server discovery UI is future work.

Run multiple game server instances with isolated player data for horizontal scaling.

---

## Overview

Each shard is an independent game server instance with:
- Its own player database (`players.json`)
- Its own bug reports
- Its own network port
- Complete data isolation from other shards

```
┌─────────────────────────────────────────────────────────────┐
│                    PLAYER'S PERSPECTIVE                      │
│                                                              │
│   Main Menu → Server List → Pick Shard → Play               │
│                                                              │
│   [us-west-1]  32/50 players  ████████░░  ONLINE            │
│   [us-west-2]  48/50 players  █████████░  BUSY              │
│   [us-east-1]  12/50 players  ██░░░░░░░░  ONLINE            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    SERVER-SIDE LAYOUT                        │
│                                                              │
│  user://                                                     │
│  ├── players.json          # "default" shard (backwards     │
│  │                         #  compatible single-server)     │
│  └── shards/                                                 │
│      ├── us-west-1/                                         │
│      │   ├── players.json  # Shard-specific player data     │
│      │   └── bug_reports.json                               │
│      ├── us-west-2/                                         │
│      │   ├── players.json                                   │
│      │   └── bug_reports.json                               │
│      └── us-east-1/                                         │
│          ├── players.json                                   │
│          └── bug_reports.json                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Running a Single Server (Default)

```bash
# No shard argument = "default" shard (backwards compatible)
./Godot --headless -- --server --port 7000
```

Data stored in: `user://players.json`

### Running Multiple Shards

```bash
# Terminal 1: US West shard
./Godot --headless -- --server --port 7000 --shard us-west-1

# Terminal 2: US East shard
./Godot --headless -- --server --port 7001 --shard us-east-1

# Terminal 3: Beta/test shard
./Godot --headless -- --server --port 7002 --shard beta
```

Each shard has completely isolated data in `user://shards/{shard_id}/`.

---

## CLI Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--server` | Start as dedicated server (required) | - |
| `--port XXXX` | Network port to listen on | 7000 |
| `--shard ID` | Shard identifier for data isolation | "default" |

### Shard ID Rules

- Alphanumeric characters, hyphens, underscores only
- Examples: `001`, `us-west-1`, `beta_test`, `prod-2`
- Invalid characters are stripped automatically

---

## File Structure

### Default Mode (Single Server)
```
user://
├── players.json        # Player accounts and data
└── bug_reports.json    # Bug reports
```

### Multi-Shard Mode
```
user://
├── players.json        # "default" shard (if used)
└── shards/
    ├── us-west-1/
    │   ├── players.json
    │   └── bug_reports.json
    ├── us-west-2/
    │   ├── players.json
    │   └── bug_reports.json
    └── beta/
        ├── players.json
        └── bug_reports.json
```

---

## Code Integration

### DatabaseManager

```gdscript
# Set shard BEFORE initializing database
DatabaseManager.set_shard_id("us-west-1")
DatabaseManager.initialize_database()

# Query current shard
var shard = DatabaseManager.get_shard_id()  # "us-west-1"
var path = DatabaseManager.players_file_path  # "user://shards/us-west-1/players.json"
```

### ServerRunner

The `--shard` argument is automatically parsed and applied:

```gdscript
# Parsed from CLI args in _start_dedicated_server()
DatabaseManager.set_shard_id(shard)
DatabaseManager.initialize_database()
```

---

## Systemd Service Templates

For production deployments, use systemd service templates:

### `/etc/systemd/system/wasteland@.service`

```ini
[Unit]
Description=Wasteland Game Server - Shard %i
After=network.target

[Service]
Type=simple
User=gameserver
WorkingDirectory=/opt/wasteland
ExecStart=/opt/wasteland/server --headless -- --server --port %i --shard shard-%i
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Usage

```bash
# Start shards on different ports
sudo systemctl start wasteland@7000  # shard-7000
sudo systemctl start wasteland@7001  # shard-7001
sudo systemctl start wasteland@7002  # shard-7002

# Check status
sudo systemctl status wasteland@7000

# View logs
sudo journalctl -u wasteland@7000 -f
```

---

## Monitoring

### Server Startup Output

```
═══════════════════════════════════════════════════════════
   WASTELAND DEDICATED SERVER
═══════════════════════════════════════════════════════════
🖥️  Initializing server...
   PID: 12345
   Port: 7000
   Shard: us-west-1
📀 Database initialized: user://shards/us-west-1/players.json
✅ Server started successfully!
   Version: 1.0.0
   Port: 7000
   Shard: us-west-1
   Max Players: 50
═══════════════════════════════════════════════════════════
```

### Periodic Status (Every 60s)

```
📊 [Shard:us-west-1] Players: 32 | Uptime: 4h 23m
```

---

## Player Data Isolation

**Important**: Players on different shards have completely separate accounts.

- A player on `us-west-1` cannot access their character on `us-east-1`
- Gold, items, level, position are all shard-specific
- This is intentional for launch capacity, not for persistent cross-shard play

### Future: Cross-Shard Features

These features are NOT yet implemented but planned:

- [ ] Server browser UI (show available shards)
- [ ] Cross-shard trading hub (centralized)
- [ ] Cross-shard leaderboards
- [ ] Account migration between shards
- [ ] Shard registry in Mantle backend

---

## Troubleshooting

### "Cannot change shard_id after initialization!"

You called `set_shard_id()` after `initialize_database()`. The shard must be set first:

```gdscript
# Wrong
DatabaseManager.initialize_database()
DatabaseManager.set_shard_id("001")  # ERROR!

# Correct
DatabaseManager.set_shard_id("001")
DatabaseManager.initialize_database()
```

### Shard directory not created

Check file permissions on `user://` directory. The system automatically creates:
1. `user://shards/` directory
2. `user://shards/{shard_id}/` subdirectory

### Players appearing on wrong shard

Each shard has isolated data. If a player creates an account on `shard-001`, that account doesn't exist on `shard-002`. They need to create a new account on each shard.

---

## Key Files

| File | Purpose |
|------|---------|
| `scripts/systems/DatabaseManager.gd` | Shard-aware player data storage |
| `scripts/ServerRunner.gd` | CLI argument parsing, shard initialization |
| `docs/SHARD_SYSTEM.md` | This documentation |

---

## Summary

| Feature | Status |
|---------|--------|
| Per-shard player databases | ✅ Implemented |
| Per-shard bug reports | ✅ Implemented |
| CLI `--shard` argument | ✅ Implemented |
| Shard ID in logs | ✅ Implemented |
| Server browser UI | ❌ Future |
| Cross-shard features | ❌ Future |
