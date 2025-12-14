extends Node

## Game-wide constants
## Add to project.godot autoloads as "Constants"

func _ready():
	print("✅ Constants autoload initialized")
	if ENABLE_DEBUG:
		debug_log("🐛 Debug mode ENABLED")
	else:
		debug_log("🚀 Debug mode DISABLED (production)")
	debug_log("Press F3 to toggle debug displays")

# ============================================
# COMBAT SYSTEM
# ============================================

# Player Combat
const PLAYER_ATTACK_RANGE: float = 100.0
const PLAYER_ATTACK_RANGE_BUFFER: float = 20.0  # Extra forgiveness for edge clicks
const PLAYER_ATTACK_CONE_ANGLE: float = 90.0
const PLAYER_BASE_SPEED: float = 200.0
const PLAYER_BASE_ATTACK_DAMAGE: float = 10.0
const PLAYER_ATTACK_COOLDOWN: float = 0.10
const PLAYER_HOLD_ATTACK_INTERVAL: float = 0.13  # Slightly slower than manual clicking

# Crit Window System
const CRIT_WINDOW_DURATION: float = 4.0
const CRIT_WINDOW_SCALE_MULTIPLIER: float = 2.8  # Enemy grows to 2.8x size
const CRIT_WINDOW_SCALE_THRESHOLD: float = 0.9  # Skip growth if already 90% scaled
const CRIT_WINDOW_SCALE_DURATION: float = 0.25  # Growth animation duration
const CRIT_WINDOW_Z_INDEX: int = 100  # Enemy z-index during crit window
const CRIT_WINDOW_SPAM_PROTECTION: float = 0.1  # Short delay after weakpoints spawn

# Weakpoints
const WEAKPOINT_COUNT: int = 3  # Max weakpoints (at level 10+)
const WEAKPOINT_COUNTER_SCALE_DIVISOR: float = 3.2  # Counter-scale weakpoints (1/3.2)
const WEAKPOINT_MAX_PER_SECTION: int = 1  # Exactly 1 weakpoint per body section
const CRIT_DAMAGE_MULTIPLIER: float = 2.0  # Weakpoint damage multiplier

# Weakpoint Window Triggers (decoupled from crit)
# Windows trigger on hit count OR health thresholds - NOT on random crits
const WEAKPOINT_TRIGGER_HIT_COUNT: int = 8  # Trigger window every X hits on same enemy
const WEAKPOINT_TRIGGER_HEALTH_THRESHOLDS: Array = [0.75, 0.50, 0.25]  # Trigger at 75%, 50%, 25% HP
const WEAKPOINT_TRIGGER_ON_CRIT: bool = false  # Legacy: if true, crits still trigger windows

# ============================================
# TTK (TIME-TO-KILL) FRAMEWORK
# ============================================
# HP pools are designed around expected weakpoint windows to kill.
# This ensures consistent TTK regardless of player damage scaling.

# Expected weakpoint windows to kill each enemy type
const TTK_WINDOWS_TRASH: int = 2       # Regular mobs: 2 perfect windows (native weapons)
const TTK_WINDOWS_ELITE: int = 3       # Elite/Guardian mobs: 2-3 windows
const TTK_WINDOWS_BOSS: int = 7        # Bosses: 6-8 windows
const TTK_WINDOWS_PLAYER_PVP: int = 4  # Players in PvP: 3-5 windows

# Base damage per perfect weakpoint window (at level 1)
# Formula: 3 weakpoints × base_damage × crit_mult = 3 × 7 × 2.0 = 42 damage
# This scales with player level automatically via base_damage
const TTK_BASE_WINDOW_DAMAGE: float = 42.0  # Level 1 perfect window damage

# Enemy HP multipliers (applied on top of base scaling)
# These tune individual enemy types to hit TTK targets
const TTK_MULT_TRASH: float = 1.0      # Standard HP
const TTK_MULT_ELITE: float = 1.75     # 75% more HP (guardians already have this)
const TTK_MULT_BOSS: float = 4.0       # 4x HP for extended fights

# Player base HP for PvP (separate from PvE vitality scaling)
const PLAYER_PVP_BASE_HP: float = 800.0  # ~4 windows with average gear
const PLAYER_PVP_HP_PER_VIT: float = 15.0  # More impactful than PvE (+15 vs +10)

# ============================================
# ENEMY SCALING
# ============================================

# Enemy Level Scaling Formulas
const ENEMY_BASE_HEALTH: float = 100.0  # Base health at level 1 (scales for fast-paced combat)
const ENEMY_HEALTH_SCALING: float = 1.27  # 27% exponential health growth per level
const ENEMY_BASE_DAMAGE: float = 5.0  # Base damage at level 1
const ENEMY_DAMAGE_SCALING: float = 1.11  # 11% exponential damage growth per level
const ENEMY_XP_BASE: int = 10  # Base XP reward at level 1
const ENEMY_GOLD_BASE: int = 5  # Base gold drop at level 1
const ENEMY_XP_GOLD_SCALING: float = 1.15  # XP and gold scale together
const ENEMY_RESPAWN_TIME: float = 60.0  # Respawn delay in seconds

# ============================================
# CHAIN SYSTEM
# ============================================

const CHAIN_TIMEOUT: float = 5.0
const CHAIN_DAMAGE_PER_LEVEL: float = 10.0  # 10% damage boost per chain level
const CHAIN_MAX_LEVEL: int = 10  # Maximum chain multiplier (2x damage at max)
const CHAIN_MILESTONE_INTERVAL: int = 5  # Play sound every 5 chain levels

# ============================================
# CHARACTER PROGRESSION
# ============================================

# Starting Stats
const STARTING_LEVEL: int = 1
const STARTING_XP: int = 0
const STARTING_GOLD: int = 0  # Starting currency
const STARTING_STRENGTH: int = 10
const STARTING_AGILITY: int = 10
const STARTING_VITALITY: int = 10
const STARTING_LUCK: int = 10

# XP Progression
const BASE_XP_REQUIREMENT: int = 100  # XP needed for level 2
const XP_SCALING_EXPONENT: float = 1.15  # Exponential XP curve
const MAX_LEVEL: int = 30  # Maximum level cap
const STAT_GAIN_CAP_LEVEL: int = 25  # No more stat gains past this level

# ============================================
# WORLD GENERATION
# ============================================

# Chunk System
const CHUNK_SIZE: float = 8000.0  # Size of each chunk (8000x8000)
const CHUNK_COUNT: int = 3  # Number of chunks (0, 1, 2)

# World Boundaries (derived from chunk system)
const WORLD_LEFT: int = -8200  # -CHUNK_SIZE - 200 buffer
const WORLD_RIGHT: int = 16200  # CHUNK_SIZE * 2 + 200 buffer
const WORLD_TOP: int = -4200  # -CHUNK_SIZE/2 - 200 buffer
const WORLD_BOTTOM: int = 4200  # CHUNK_SIZE/2 + 200 buffer
const WORLD_WIDTH: int = 24000  # CHUNK_SIZE * 3
const WORLD_HEIGHT: int = 8000  # CHUNK_SIZE
const WORLD_BOUNDARY_THICKNESS: float = 100.0
const WORLD_EDGE_BUFFER: float = 300.0  # Keep props away from edges

# Terrain Generation
const TERRAIN_PATCH_SPACING: int = 900  # Distance between terrain patches
const TERRAIN_PATCH_COVERAGE: float = 0.8  # 80% of grid spots get patches (1 - 0.2)
const TREE_GRID_SPACING: int = 200  # Distance between tree spawn points
const TREE_SPAWN_RATE: float = 0.31  # 31% chance to spawn tree at each point (dense forest coverage)

# Prop Counts
const TERRAIN_FEATURE_COUNT: int = 30  # Large rock formations
const LARGE_ROCK_COUNT: int = 100  # Initial large rock scatter
const MEDIUM_ROCK_COUNT: int = 50  # Medium rocks
const SMALL_ROCK_COUNT: int = 1200  # Small detail rocks to fill bare spots

# ============================================
# GROUPS (for get_tree().get_nodes_in_group)
# ============================================

const GROUP_PLAYER: String = "player"
const GROUP_ENEMIES: String = "enemies"

# ============================================
# DEBUG
# ============================================

const DEBUG_UPDATE_INTERVAL: float = 0.1  # How often to refresh debug visuals (10 FPS)

## Signal emitted when F3 debug display is toggled
signal debug_display_toggled(visible: bool)

## Master debug flag - set to false for production
@export var ENABLE_DEBUG: bool = true

## F3 Debug display visibility
var debug_display_visible: bool = false

## Feature-specific debug flags
@export var DEBUG_COMBAT: bool = true
@export var DEBUG_MOVEMENT: bool = false
@export var DEBUG_AI: bool = false
@export var DEBUG_SPAWNING: bool = false
@export var DEBUG_VISUALS: bool = false

## Performance monitoring
@export var SHOW_FPS: bool = true
@export var LOG_FRAME_TIME: bool = false

## Debug visual settings
@export var SHOW_COLLISION_SHAPES: bool = false
@export var SHOW_ATTACK_CONES: bool = false
@export var SHOW_AI_PATHS: bool = false

func debug_log(message: String, category: String = "") -> void:
	# Centralized logging function
	if not ENABLE_DEBUG:
		return

	var prefix: String = "[DEBUG]"
	if category != "":
		prefix = "[%s]" % category.to_upper()

	print("%s %s" % [prefix, message])

func log_combat(message: String) -> void:
	# Log combat-related messages
	if ENABLE_DEBUG and DEBUG_COMBAT:
		debug_log(message, "COMBAT")

func log_movement(message: String) -> void:
	# Log movement-related messages
	if ENABLE_DEBUG and DEBUG_MOVEMENT:
		debug_log(message, "MOVEMENT")

func log_ai(message: String) -> void:
	# Log AI-related messages
	if ENABLE_DEBUG and DEBUG_AI:
		debug_log(message, "AI")

func log_spawning(message: String) -> void:
	# Log spawning-related messages
	if ENABLE_DEBUG and DEBUG_SPAWNING:
		debug_log(message, "SPAWN")

func log_error(message: String) -> void:
	# Log errors (always shown, even in production)
	push_error("[ERROR] %s" % message)

func log_warning(message: String) -> void:
	# Log warnings (always shown, even in production)
	push_warning("[WARNING] %s" % message)

func is_debug_enabled() -> bool:
	# Check if debug mode is enabled
	return ENABLE_DEBUG

func set_debug_mode(enabled: bool) -> void:
	# Toggle debug mode at runtime
	ENABLE_DEBUG = enabled
	debug_log("Debug mode %s" % ("ENABLED" if enabled else "DISABLED"))

func toggle_debug_display() -> void:
	"""Toggle F3 debug display visibility"""
	debug_display_visible = !debug_display_visible
	debug_display_toggled.emit(debug_display_visible)
	debug_log("Debug display %s" % ("SHOWN" if debug_display_visible else "HIDDEN"))

func _input(event: InputEvent) -> void:
	"""Listen for F3 key to toggle debug displays (debug builds only)"""
	# Only allow in editor or debug builds
	if not (OS.has_feature("editor") or OS.is_debug_build()):
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		toggle_debug_display()
