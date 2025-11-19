extends Node

## Game-wide constants
## Add to project.godot autoloads as "Constants"

func _ready():
	# Note: Can't use DebugConfig here as we initialize before it
	print("✅ Constants autoload initialized")

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

# ============================================
# ENEMY SCALING
# ============================================

# Enemy Level Scaling Formulas
const ENEMY_BASE_HEALTH: float = 100.0  # Base health at level 1 (scales for rhythm combat)
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

# World Boundaries
const WORLD_LEFT: int = -5000
const WORLD_RIGHT: int = 13000
const WORLD_TOP: int = -3000
const WORLD_BOTTOM: int = 3000
const WORLD_WIDTH: int = WORLD_RIGHT - WORLD_LEFT  # 18000
const WORLD_HEIGHT: int = WORLD_BOTTOM - WORLD_TOP  # 6000
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
