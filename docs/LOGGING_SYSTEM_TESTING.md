# Logging System Testing Guide

This document provides validation steps for the enhanced LogManager and TelemetryManager systems.

---

## Quick Start Testing

### 1. Basic Smoke Test (2 minutes)

1. Open Godot and run the game
2. Check the Output panel for initialization messages:
   ```
   [HH:MM:SS] [INF] 📋 default: LogManager initialized (level: DEBUG, file: false, session: a1b2c3d4...)
   [HH:MM:SS] [INF] 📡 telemetry: TelemetryManager initialized (enabled: true)
   ```
3. If you see both messages, basic initialization works

---

## Detailed Test Cases

### Test 1: Session ID Generation

**Purpose:** Verify unique session ID is generated each launch

**Steps:**
1. Run the game
2. In Godot debugger or console, access: `LogManager.session_id`
3. Note the value (e.g., `a1b2c3d4-5678-4abc-9def-0123456789ab`)
4. Quit the game
5. Run the game again
6. Check `LogManager.session_id` again

**Expected Result:**
- Session ID should be a valid UUID format (36 chars with dashes)
- Session ID should be DIFFERENT on each launch

**Validation Command (in debugger):**
```gdscript
print("Session: ", LogManager.session_id)
print("Valid UUID: ", LogManager.session_id.length() == 36)
```

---

### Test 2: Device ID Persistence

**Purpose:** Verify device ID persists across sessions

**Steps:**
1. Delete `user://device_id.txt` if it exists (use OS file explorer)
   - Windows: `%APPDATA%\Godot\app_userdata\Dreadland\device_id.txt`
2. Run the game
3. Note `LogManager.device_id`
4. Quit and run again
5. Check `LogManager.device_id`

**Expected Result:**
- Device ID should be SAME across launches
- File `device_id.txt` should exist in user data folder

**Validation Command:**
```gdscript
print("Device ID: ", LogManager.device_id)
print("File exists: ", FileAccess.file_exists("user://device_id.txt"))
```

---

### Test 3: File Logging (Release Build)

**Purpose:** Verify logs are written to disk in release builds

**Steps:**
1. Export a release build (not debug)
2. Run the exported game
3. Play for 30 seconds (trigger some logs)
4. Quit the game
5. Check `user://logs/` folder for log files

**Expected Result:**
- Log file exists: `game_YYYY-MM-DD.log`
- File contains session header with session ID, device ID, platform
- File contains log entries with timestamps

**Log File Location:**
- Windows: `%APPDATA%\Godot\app_userdata\Dreadland\logs\`
- Linux: `~/.local/share/godot/app_userdata/Dreadland/logs/`
- macOS: `~/Library/Application Support/Godot/app_userdata/Dreadland/logs/`

**Sample Log Content:**
```
================================================================================
SESSION START: 2024-12-21T15:30:45
Session ID: a1b2c3d4-5678-4abc-9def-0123456789ab
Device ID: x9y8z7w6-5432-4fed-cba0-9876543210fe
Platform: Windows
================================================================================

[15:30:45] [INF] 📋 default: LogManager initialized (level: WARN, file: true, session: a1b2c3d4...)
[15:30:46] [INF] 🌐 network: Connected to server
```

---

### Test 4: Log Rotation

**Purpose:** Verify old logs are deleted after 7 days

**Steps:**
1. Manually create fake old log files in `user://logs/`:
   - `game_2024-01-01.log` (content: "test")
   - `game_2024-01-02.log` (content: "test")
2. Set their file modified time to 10 days ago (use OS tools)
3. Run the game
4. Check `user://logs/` folder

**Expected Result:**
- Old fake log files should be deleted
- Console should show: `[LogManager] Rotated old log: game_2024-01-01.log`

**Alternative Test (without date manipulation):**
1. Set `LogManager.max_log_files = 1` in code temporarily
2. Create 3 log files manually
3. Run game
4. Only 1 log file should remain (plus today's)

---

### Test 5: User Context Integration

**Purpose:** Verify user context is set after authentication

**Steps:**
1. Run the game
2. Check initial state: `LogManager.user_id` should be `-1`
3. Log in via Ashbane (any provider)
4. Check after login: `LogManager.user_id` and `LogManager.username`

**Expected Result:**
- Before login: `user_id = -1`, `username = ""`
- After login: `user_id > 0`, `username = "ashbane-xxxxx"`

**Validation Command:**
```gdscript
print("User ID: ", LogManager.user_id)
print("Username: ", LogManager.username)
print("Context: ", LogManager.get_log_context())
```

---

### Test 6: User Context Cleared on Logout

**Purpose:** Verify user context is cleared when logging out

**Steps:**
1. Log in via Ashbane
2. Verify `LogManager.user_id > 0`
3. Log out (via settings or menu)
4. Check `LogManager.user_id`

**Expected Result:**
- After logout: `user_id = -1`, `username = ""`

---

### Test 7: TelemetryManager Batching

**Purpose:** Verify logs are batched before sending

**Steps:**
1. Run game with network monitor (browser dev tools or Wireshark)
2. Log in to Ashbane
3. Trigger 10 log events (walk around, attack enemies, pick up items)
4. Wait 5+ seconds
5. Check network traffic

**Expected Result:**
- Single POST request to `/api/logs/batch` containing multiple log entries
- Not 10 separate requests

**Validation (in debugger):**
```gdscript
print("Pending logs: ", TelemetryManager._pending_logs.size())
print("Stats: ", TelemetryManager.get_stats())
```

---

### Test 8: TelemetryManager Offline Queueing

**Purpose:** Verify logs are queued when not authenticated

**Steps:**
1. Run game without logging in (guest mode or no internet)
2. Trigger log events
3. Check `TelemetryManager._pending_logs.size()`

**Expected Result:**
- Logs should accumulate in `_pending_logs`
- No HTTP requests should be made
- Queue should not exceed `MAX_OFFLINE_QUEUE` (500)

---

### Test 9: Log Level Filtering

**Purpose:** Verify DEBUG logs don't go to remote in production

**Steps:**
1. Set `LogManager.global_level = LogManager.LogLevel.DEBUG`
2. Call `LogManager.debug("Test debug message", "test")`
3. Check `TelemetryManager._pending_logs`

**Expected Result:**
- DEBUG message should appear in console
- DEBUG message should NOT be in TelemetryManager queue (unless category is in `always_send_categories`)

**Validation:**
```gdscript
LogManager.debug("Test debug", "test")
print("In queue: ", TelemetryManager._pending_logs.size())  # Should be 0
LogManager.info("Test info", "test")
print("In queue: ", TelemetryManager._pending_logs.size())  # Should be 1
```

---

### Test 10: Error Always Sent

**Purpose:** Verify ERROR logs are always queued for remote

**Steps:**
1. Call `LogManager.error("Test error", "test")`
2. Check `TelemetryManager._pending_logs`

**Expected Result:**
- ERROR message should be in queue regardless of `remote_min_level`
- Should trigger immediate flush attempt

---

## Backend Integration Testing

### Prerequisites
- Backend `/api/logs/batch` endpoint deployed
- Valid Ashbane authentication

### Test 11: End-to-End Log Delivery

**Steps:**
1. Log in to Ashbane
2. Play for 60 seconds (trigger various events)
3. Check backend database or logs

**Expected Result:**
- Logs appear in backend with correct:
  - `user_id` matching authenticated user
  - `session_id` matching client
  - `device_id` matching client
  - `client_version`, `platform`, `is_host`

### Test 12: Retry on Failure

**Steps:**
1. Temporarily block the API endpoint (firewall or backend down)
2. Trigger log events
3. Restore connectivity
4. Wait for retry (2s, 4s, 8s exponential backoff)

**Expected Result:**
- Logs should eventually be sent after connectivity restored
- Console should show retry messages

---

## Debugging Commands

Run these in Godot's debugger or via a debug console:

```gdscript
# Check logging state
print("=== LogManager ===")
print("Level: ", LogManager.LogLevel.keys()[LogManager.global_level])
print("File logging: ", LogManager.log_to_file)
print("Log path: ", LogManager.log_file_path)
print("Session: ", LogManager.session_id)
print("Device: ", LogManager.device_id)
print("User: ", LogManager.username, " (", LogManager.user_id, ")")

# Check telemetry state
print("\n=== TelemetryManager ===")
print("Enabled: ", TelemetryManager.enabled)
print("Stats: ", TelemetryManager.get_stats())
print("Pending: ", TelemetryManager._pending_logs.size())

# Force flush telemetry
TelemetryManager.force_flush()

# Enable client file logging (debug builds)
LogManager.enable_client_logging()

# Disable remote telemetry
TelemetryManager.set_enabled(false)

# Get all log files for bug report
print("Log files: ", LogManager.get_all_log_files())
```

---

## Troubleshooting

### Logs not appearing in file
1. Check `LogManager.log_to_file` is true
2. Check `LogManager.log_file_path` is valid
3. Verify `user://logs/` directory exists
4. Check file permissions

### Telemetry not sending
1. Verify `TelemetryManager.enabled` is true
2. Check `AshbaneAuth.is_authenticated` is true
3. Look for network errors in console
4. Verify API endpoint is reachable

### Session ID is empty
1. Ensure LogManager is in autoloads
2. Check it runs before other systems (position 4)
3. Look for errors in _ready()

### User context not set
1. Verify AshbaneAuth integration
2. Check `auth_completed` signal is firing
3. Look for errors in `set_user_context()`

---

## Performance Notes

- File logging adds ~1-2ms per write (with flush)
- Telemetry batching reduces HTTP overhead significantly
- Queue size capped at 500 to prevent memory issues
- Log rotation runs once at startup (not continuously)

---

## Files Modified

| File | Changes |
|------|---------|
| `scripts/systems/LogManager.gd` | Session/device ID, file rotation, user context |
| `scripts/systems/TelemetryManager.gd` | NEW - batched remote logging |
| `scripts/systems/AshbaneAuth.gd` | Calls set_user_context / clear_user_context |
| `project.godot` | Added TelemetryManager autoload |
