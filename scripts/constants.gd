extends Node

## Game-wide constants
## Add to project.godot autoloads as "Constants"

# === COMBAT ===
const PLAYER_ATTACK_RANGE: float = 100.0
const PLAYER_ATTACK_CONE_ANGLE: float = 90.0

# === GROUPS ===
const GROUP_PLAYER: String = "player"
const GROUP_ENEMIES: String = "enemies"

# === TIMING ===
const CRIT_WINDOW_DURATION: float = 4.0
const CHAIN_TIMEOUT: float = 5.0

# === DEBUG ===
const DEBUG_UPDATE_INTERVAL: float = 0.1  # How often to refresh debug visuals
