# Mini-MMO Database Schema

## Overview
SQLite database for persistent world state and player data.

## Tables

### players
Stores all player account and character data.

```sql
CREATE TABLE players (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_login INTEGER NOT NULL,

    -- Character Data
    character_name TEXT,
    gender TEXT DEFAULT 'male',
    level INTEGER DEFAULT 1,
    xp INTEGER DEFAULT 0,
    gold INTEGER DEFAULT 100,

    -- Stats
    strength INTEGER DEFAULT 10,
    agility INTEGER DEFAULT 10,
    vitality INTEGER DEFAULT 10,
    luck INTEGER DEFAULT 10,

    -- Current State
    current_hp REAL DEFAULT 100.0,
    position_x REAL DEFAULT -2000.0,
    position_y REAL DEFAULT 0.0,
    current_phase INTEGER DEFAULT 1,

    -- Inventory (JSON blob)
    inventory TEXT DEFAULT '[]',

    -- Equipment (JSON blob)
    equipment TEXT DEFAULT '{}',

    -- Playtime
    total_playtime_seconds INTEGER DEFAULT 0,

    -- Flags
    is_online INTEGER DEFAULT 0,
    is_banned INTEGER DEFAULT 0
);

CREATE INDEX idx_username ON players(username);
CREATE INDEX idx_online ON players(is_online);
```

### world_state
Tracks respawnable world objects (chests, trees, etc).

```sql
CREATE TABLE world_state (
    object_id TEXT PRIMARY KEY,
    object_type TEXT NOT NULL,  -- 'chest', 'tree', 'boss'
    last_interaction INTEGER,   -- Unix timestamp
    respawn_time INTEGER,        -- When it respawns
    phase INTEGER DEFAULT 0,     -- Which phase this object belongs to
    data TEXT                    -- JSON for additional state
);

CREATE INDEX idx_respawn ON world_state(respawn_time);
```

### player_chests
Tracks which chests each player has opened (for one-time chests).

```sql
CREATE TABLE player_chests (
    player_id INTEGER NOT NULL,
    chest_id TEXT NOT NULL,
    opened_at INTEGER NOT NULL,
    PRIMARY KEY (player_id, chest_id),
    FOREIGN KEY (player_id) REFERENCES players(id)
);
```

### player_kills
Tracks enemy kills for quests/achievements.

```sql
CREATE TABLE player_kills (
    player_id INTEGER NOT NULL,
    enemy_type TEXT NOT NULL,
    enemy_level INTEGER NOT NULL,
    killed_at INTEGER NOT NULL,
    FOREIGN KEY (player_id) REFERENCES players(id)
);

CREATE INDEX idx_player_kills ON player_kills(player_id, enemy_type);
```

### chat_log
Stores chat messages for moderation/history.

```sql
CREATE TABLE chat_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id INTEGER NOT NULL,
    message TEXT NOT NULL,
    channel TEXT DEFAULT 'global',  -- 'global', 'party', 'whisper'
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (player_id) REFERENCES players(id)
);

CREATE INDEX idx_chat_time ON chat_log(timestamp);
```

### server_config
Stores server-wide settings.

```sql
CREATE TABLE server_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Default values
INSERT INTO server_config VALUES ('server_version', '0.1.0');
INSERT INTO server_config VALUES ('max_players', '50');
INSERT INTO server_config VALUES ('maintenance_mode', '0');
INSERT INTO server_config VALUES ('xp_multiplier', '1.0');
INSERT INTO server_config VALUES ('drop_rate_multiplier', '1.0');
```

## Player Inventory Format (JSON)

```json
[
    {
        "slot": 0,
        "name": "Dry Log",
        "type": "material",
        "quantity": 50,
        "max_stack": 200,
        "value": 2,
        "rarity": "Common"
    },
    {
        "slot": 5,
        "name": "Iron Sword",
        "type": "weapon",
        "damage": 15,
        "value": 100,
        "rarity": "Uncommon"
    }
]
```

## Player Equipment Format (JSON)

```json
{
    "mainhand": {
        "name": "Iron Sword",
        "damage": 15,
        "attack_speed_bonus": 0,
        "value": 100
    },
    "offhand": null,
    "head": {
        "name": "Leather Cap",
        "defense": 2,
        "value": 50
    },
    "chest": null,
    "arms": null,
    "hands": null,
    "legs": null,
    "feet": null
}
```

## Queries

### Get Player Data
```sql
SELECT * FROM players WHERE username = ? AND password_hash = ?;
```

### Save Player Data
```sql
UPDATE players SET
    level = ?,
    xp = ?,
    gold = ?,
    current_hp = ?,
    position_x = ?,
    position_y = ?,
    inventory = ?,
    equipment = ?,
    last_login = ?,
    total_playtime_seconds = total_playtime_seconds + ?
WHERE id = ?;
```

### Get Online Players
```sql
SELECT username, level, position_x, position_y, current_phase
FROM players
WHERE is_online = 1;
```

### Check Chest Opened
```sql
SELECT 1 FROM player_chests
WHERE player_id = ? AND chest_id = ?;
```

### Get Respawnable Objects
```sql
SELECT object_id, object_type, data
FROM world_state
WHERE respawn_time <= ? AND phase = ?;
```

## Maintenance

### Auto-Save Every 5 Minutes
Server runs auto-save for all online players.

### Cleanup Old Data
```sql
-- Remove chat older than 30 days
DELETE FROM chat_log WHERE timestamp < ?;

-- Reset offline status for crashed sessions (older than 1 hour)
UPDATE players SET is_online = 0
WHERE is_online = 1 AND last_login < ?;
```

### Backup Strategy
- SQLite file copied every hour to `backups/server_data_YYYYMMDD_HHMMSS.db`
- Keep last 24 backups (1 per hour)
- Keep daily snapshots for 7 days

## Chat Admin Commands

The host can use admin commands in the chat (press Enter) to manage player accounts.

### Command Reference

| Command | Description |
|---------|-------------|
| `/help` | Show all available admin commands |
| `/accounts` | List all registered accounts with levels |
| `/select <username>` | Select an account to edit |
| `/info` | Show details of selected account |
| `/setpos <x> <y>` | Set player's world position |
| `/resetpos` | Reset position to campfire spawn (0,0) |
| `/setgold <amount>` | Set player's gold amount |
| `/setlevel <1-30>` | Set player's level |
| `/setstats <str> <agi> <vit> <luck>` | Set player's base stats |
| `/ban` | Ban the selected account |
| `/unban` | Unban the selected account |
| `/forceoffline` | Reset is_online flag (fixes stuck logins) |
| `/delete` | Permanently delete selected account |

### Usage Example

```
/accounts                    # List all accounts
/select PlayerOne           # Select "PlayerOne"
/info                       # View their stats
/setgold 5000              # Give them 5000 gold
/setlevel 15               # Set to level 15
/resetpos                  # Move to campfire
```

### Implementation

Admin commands are handled in `scripts/ui/ChatUI.gd` in the `_handle_admin_command()` function. Commands modify data directly in `DatabaseManager.players_data` and call `DatabaseManager.save_database()` to persist changes.

**Security Note**: Admin commands only work for the game host. The DatabaseManager is only initialized on the server/host.
