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
# BACKGROUND THROTTLING
# ============================================
# Reduces CPU/GPU usage when the game window is not focused
# This prevents the game from freezing the system when running in background

var _is_window_focused: bool = true
var _normal_physics_ticks: int = 60
var _background_physics_ticks: int = 10  # Reduced physics when backgrounded

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Window lost focus - enable low processor mode
			_is_window_focused = false
			OS.low_processor_usage_mode = true
			Engine.max_fps = 10  # Cap FPS when backgrounded
			Engine.physics_ticks_per_second = _background_physics_ticks
			if ENABLE_DEBUG:
				print("[Background] Window unfocused - enabling low processor mode")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			# Window gained focus - disable low processor mode
			_is_window_focused = true
			OS.low_processor_usage_mode = false
			Engine.max_fps = 0  # Uncapped (or use your normal cap)
			Engine.physics_ticks_per_second = _normal_physics_ticks
			if ENABLE_DEBUG:
				print("[Background] Window focused - restoring normal processing")

# ============================================
# COMBAT SYSTEM
# ============================================

# Player Combat
const PLAYER_ATTACK_RANGE: float = 100.0
const PLAYER_ATTACK_RANGE_BUFFER: float = 20.0  # Extra forgiveness for edge clicks
const PLAYER_ATTACK_CONE_ANGLE: float = 90.0
const PLAYER_BASE_SPEED: float = 200.0
const PLAYER_BASE_ATTACK_DAMAGE: float = 2.0  # Reduced from 10.0 for balanced early game
const PLAYER_ATTACK_COOLDOWN: float = 0.70  # Base cooldown at level 1 (was 0.10)
const PLAYER_HOLD_ATTACK_INTERVAL: float = 0.30  # Slower held attacks (was 0.13)

# Attack Speed Scaling (back-loaded progression curve)
# Early levels (1-10): Slow, deliberate combat - minimal speed gain
# Teen levels (11-19): Speed starts ramping up noticeably
# 20s (20-30): Full attack speed unlocked - feels powerful
const ATTACK_SPEED_BASE_COOLDOWN: float = 1.0  # Base cooldown at level 1
const ATTACK_SPEED_MIN_COOLDOWN: float = 0.4   # Minimum cooldown at max level (60% reduction)
const ATTACK_SPEED_CURVE_EXPONENT: float = 2.5  # Back-loaded curve (higher = more back-loaded)

# Weapon Speed Multipliers (applied to base cooldown)
const WEAPON_SPEED_VERY_FAST: float = 0.50  # Dagger
const WEAPON_SPEED_FAST: float = 0.65       # Katana, Rapier, Saber
const WEAPON_SPEED_MEDIUM: float = 0.80     # Sword, Scimitar, Bow
const WEAPON_SPEED_SLOW: float = 0.95       # Mace, Spear, Axe, Staff
const WEAPON_SPEED_VERY_SLOW: float = 1.10  # Hammer, Halberd, Greatsword

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
const CRIT_DAMAGE_MULTIPLIER: float = 1.5  # Weakpoint damage multiplier (was 2.0 - reduced for better TTK rhythm)

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
#
# REBALANCED: With smaller damage numbers (2-6 at L1), fights last longer
# and feel more deliberate. Target TTK: 5-8 seconds for trash mobs.

# Expected weakpoint windows to kill each enemy type
const TTK_WINDOWS_TRASH: int = 2       # Regular mobs: 2 perfect windows
const TTK_WINDOWS_ELITE: int = 3       # Elite/Guardian mobs: 3 windows
const TTK_WINDOWS_BOSS: int = 6        # Bosses: 6 windows (was 7)
const TTK_WINDOWS_PLAYER_PVP: int = 4  # Players in PvP: 4 windows

# Base damage per perfect weakpoint window (at level 1)
# With shop weapons: ~6 base damage × crit_mult(1.5) × 4 hits = ~36 damage per window
# Enemy HP 100 / 36 per window = ~2.8 windows to kill (solid 2-window minimum)
const TTK_BASE_WINDOW_DAMAGE: float = 36.0  # Level 1 perfect window damage with shop weapon

# Enemy HP multipliers (applied on top of base scaling)
# These tune individual enemy types to hit TTK targets
const TTK_MULT_TRASH: float = 1.0      # Standard HP (~100 HP at L1)
const TTK_MULT_ELITE: float = 2.0      # 2x HP for guardians (was 1.75)
const TTK_MULT_BOSS: float = 5.0       # 5x HP for extended fights (was 4.0)

# Player base HP for PvP (separate from PvE vitality scaling)
const PLAYER_PVP_BASE_HP: float = 800.0  # ~4 windows with average gear
const PLAYER_PVP_HP_PER_VIT: float = 15.0  # More impactful than PvE (+15 vs +10)

# ============================================
# ENEMY SCALING
# ============================================

# Enemy Level Scaling Formulas (rebalanced for smaller numbers)
const ENEMY_BASE_HEALTH: float = 120.0  # Base health at level 1 (tuned for 3-window TTK)

# Damage Mitigation Formula: mitigation = defense / (defense + DEFENSE_CONSTANT)
# Higher constant = defense is less effective. Lower = more effective.
# At K=100: 65 defense (full copper plate) = 39% mitigation
const DEFENSE_CONSTANT: float = 100.0  # Tuning constant for armor effectiveness
const MIN_DAMAGE_AFTER_MITIGATION: float = 1.0  # Minimum damage dealt after mitigation
const ENEMY_HEALTH_SCALING: float = 1.12  # 12% exponential health growth per level (was 1.27)
const ENEMY_BASE_DAMAGE: float = 7.0    # Reference base damage (wolves=7.0, spiders=5.8)
const ENEMY_DAMAGE_SCALING: float = 1.08  # 8% exponential damage growth per level (was 1.11)
const ENEMY_XP_BASE: int = 10  # Base XP reward at level 1
const ENEMY_GOLD_BASE: int = 5  # Base gold drop at level 1
const ENEMY_XP_GOLD_SCALING: float = 1.15  # XP and gold scale together
const ENEMY_RESPAWN_TIME: float = 60.0  # Respawn delay in seconds

# ============================================
# CHAIN SYSTEM (DEPRECATED)
# ============================================
# Chain system removed - constants kept for compatibility during transition
# TODO: Remove these once all references are cleaned up

const CHAIN_TIMEOUT: float = 5.0
const CHAIN_DAMAGE_PER_LEVEL: float = 10.0
const CHAIN_MAX_LEVEL: int = 10
const CHAIN_MILESTONE_INTERVAL: int = 5

# ============================================
# CHARACTER PROGRESSION
# ============================================

# Starting Stats (6-stat system)
const STARTING_LEVEL: int = 1
const STARTING_XP: int = 0
const STARTING_GOLD: int = 0  # Starting currency
const STARTING_STRENGTH: int = 10      # Heavy/2H weapon damage (Plate DPS)
const STARTING_AGILITY: int = 10       # Light weapon damage (Leather DPS)
const STARTING_DEXTERITY: int = 10     # Melee crit chance
const STARTING_INTELLIGENCE: int = 10  # Staff damage + healing (Caster)
const STARTING_WISDOM: int = 10        # Caster crit chance
const STARTING_VITALITY: int = 10      # Max HP (Tank)

# XP Progression
const BASE_XP_REQUIREMENT: int = 200  # XP needed for level 2 (was 100)
const XP_SCALING_EXPONENT: float = 1.25  # Exponential XP curve (was 1.15)
const MAX_LEVEL: int = 30  # Maximum level cap
const STAT_GAIN_CAP_LEVEL: int = 25  # No more stat gains past this level

# ============================================
# WORLD GENERATION
# ============================================

# Chunk System
const CHUNK_SIZE: float = 8000.0  # Size of each chunk (8000x8000)
const CHUNK_COUNT: int = 3  # Number of chunks (0, 1, 2)

# Cell Streaming System (sub-chunk loading for smooth transitions)
const CELL_SIZE: float = 1000.0  # Size of each cell (1000x1000) - 64 cells per chunk
const CELL_LOAD_RADIUS: float = 2500.0  # Load cells within this radius of player
const CELL_UNLOAD_RADIUS: float = 3500.0  # Unload cells beyond this radius (hysteresis)
const CELL_CACHE_TIME: float = 30.0  # Keep unloaded cells in memory for this long
const CELL_MAX_LOADS_PER_FRAME: int = 8  # Max props to load per frame
const CELL_MAX_UNLOADS_PER_FRAME: int = 5  # Max cells to unload per frame

# World Boundaries (derived from chunk system)
const WORLD_LEFT: int = -8200  # -CHUNK_SIZE - 200 buffer
const WORLD_RIGHT: int = 16200  # CHUNK_SIZE * 2 + 200 buffer
const WORLD_TOP: int = -4200  # -CHUNK_SIZE/2 - 200 buffer
const WORLD_BOTTOM: int = 4200  # CHUNK_SIZE/2 + 200 buffer
const WORLD_WIDTH: int = 24000  # CHUNK_SIZE * 3
const WORLD_HEIGHT: int = 8000  # CHUNK_SIZE
const WORLD_BOUNDARY_THICKNESS: float = 100.0
const WORLD_EDGE_BUFFER: float = 300.0  # Keep props away from edges

# Alpha Test Barrier - limits players to chunk -1 during alpha
const ALPHA_MODE: bool = true  # Set to false to unlock full world
const ALPHA_BARRIER_X: float = -100.0  # Eastern boundary for alpha (chunk -1 ends at X=0)

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

## Master debug flag - auto-detects based on build type
@export var ENABLE_DEBUG: bool = OS.has_feature("editor") or OS.is_debug_build()

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
