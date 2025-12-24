# Godot Client Version Check - Implementation Handoff

## Overview
Add startup version check so players are prompted to update when a new version is released.

## Backend Endpoint (Already Done)

**GET** `/api/version` - No auth required

```json
{
  "version": "0.1.0",
  "download_url": "https://ashbane.itch.io/ashbane",
  "update_required": true
}
```

## Client Implementation

### 1. Add Version Check Function

Location: `scripts/ui/MainMenu.gd` (or create `scripts/systems/VersionChecker.gd` autoload)

```gdscript
func _ready():
    # Existing code...
    _check_for_updates()

func _check_for_updates() -> void:
    var http = HTTPRequest.new()
    add_child(http)
    http.request_completed.connect(_on_version_check_completed.bind(http))

    var url = AshbaneAuth.get_api_base() + "/api/version"
    var error = http.request(url)
    if error != OK:
        LogManager.warn("Version check failed to start", "update")

func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
    http.queue_free()

    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        LogManager.warn("Version check failed: %d" % response_code, "update")
        return

    var json = JSON.new()
    if json.parse(body.get_string_from_utf8()) != OK:
        return

    var data = json.get_data()
    var server_version = data.get("version", "")
    var download_url = data.get("download_url", "")
    var client_version = NetworkManager.NETWORK_VERSION

    if _is_outdated(client_version, server_version):
        _show_update_prompt(server_version, download_url)

func _is_outdated(client: String, server: String) -> bool:
    # Simple string comparison - works if versions are consistent format
    # For semver, could parse and compare major.minor.patch
    return client != server and server != ""

func _show_update_prompt(new_version: String, download_url: String) -> void:
    # Option 1: Use existing popup system
    # Option 2: Create dedicated update dialog

    var message = "Update Available!\n\nNew version: %s\nYour version: %s" % [new_version, NetworkManager.NETWORK_VERSION]

    # Example using AcceptDialog:
    var dialog = AcceptDialog.new()
    dialog.title = "Update Available"
    dialog.dialog_text = message
    dialog.add_button("Download", false, "download")
    dialog.custom_action.connect(func(action):
        if action == "download":
            OS.shell_open(download_url)
    )
    add_child(dialog)
    dialog.popup_centered()
```

### 2. Version Format

Current `NetworkManager.NETWORK_VERSION` uses git commit hash. Options:

**Option A: Keep git hash** (requires backend to also use git hash)
- Update `CLIENT_VERSION` in `.env` to git hash on each deploy
- Exact match required

**Option B: Switch to semver** (recommended)
- Add `const CLIENT_VERSION = "0.1.0"` to NetworkManager.gd
- Easier to manage, human-readable
- Can do proper semver comparison

### 3. Where to Hook In

Best places to call `_check_for_updates()`:
- `MainMenu._ready()` - Checks every time player returns to menu
- New autoload `VersionChecker` - Checks once on game start

### 4. UI Considerations

- Don't block the game - let them play even if outdated
- Show non-intrusive prompt (can dismiss)
- "Download" button opens itch.io in browser
- Optional: "Don't remind me" for this session

## Testing

1. Set `CLIENT_VERSION=99.0.0` in backend `.env`
2. Restart backend: `sudo systemctl restart ashbane`
3. Launch client - should see update prompt
4. Reset to real version after testing

## Files to Modify

- `scripts/ui/MainMenu.gd` - Add version check
- `scripts/networking/NetworkManager.gd` - Optional: add semver constant
- New UI scene for update dialog (optional, can use built-in AcceptDialog)
