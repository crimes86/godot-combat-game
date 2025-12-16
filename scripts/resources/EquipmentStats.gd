extends Resource
class_name EquipmentStats

## Forged Equipment Stats - Immutable Combat Biography for Armor & Accessories
## Tracks damage taken, survivorship, and all usage history for forged equipment.
## Virgin equipment (never worn in combat) is a pristine collectors' item.
## Stats can never be reset - that's the point.

# ============================================
# DEFENSIVE STATS (Armor-focused)
# ============================================

@export var damage_absorbed: int = 0        # Total damage mitigated by armor
@export var damage_taken_total: int = 0     # Total damage received while equipped
@export var hits_received: int = 0          # Total hits taken while wearing
@export var hits_survived: int = 0          # Hits that didn't kill you
@export var damage_max_hit_survived: int = 0  # Biggest hit you survived

# ============================================
# SURVIVAL STATS
# ============================================

@export var deaths_wearing: int = 0         # Deaths while equipped
@export var close_calls: int = 0            # Times dropped below 25% HP
@export var boss_fights_survived: int = 0   # Boss encounters survived
@export var boss_fights_total: int = 0      # Total boss encounters
@export var elite_fights_survived: int = 0  # Elite enemy encounters survived

# ============================================
# USAGE STATS
# ============================================

@export var time_equipped_seconds: int = 0
@export var sessions_equipped: int = 0
@export var zones_visited: Dictionary = {}  # zone_id -> times entered

# ============================================
# HEAL/SUPPORT STATS (Accessories)
# ============================================

@export var healing_received: int = 0       # Total healing while equipped
@export var buffs_received: int = 0         # Buff applications
@export var effects_triggered: int = 0      # Special effect activations

# ============================================
# NEGATIVE STATS (Virgin Equipment Value)
# ============================================

@export var battles_lost: int = 0
@export var show_negative_stats: bool = true

# ============================================
# MILESTONE TIMESTAMPS
# ============================================

@export var first_equipped_at: String = ""
@export var first_hit_taken_at: String = ""
@export var first_death_at: String = ""
@export var milestone_1000_hits_at: String = ""
@export var milestone_100_survivals_at: String = ""

# ============================================
# INFINITE LEVEL SYSTEM (Soft Cap)
# ============================================

@export var level: int = 0
@export var experience: int = 0

# ============================================
# PER-EQUIPMENT ACHIEVEMENTS
# ============================================

@export var achievements: Array[String] = []

# Achievement definitions
const ACHIEVEMENT_FIRST_BLOOD = "FIRST_BLOOD"       # Took first hit
const ACHIEVEMENT_IRON_WALL = "IRON_WALL"           # 1000 hits survived
const ACHIEVEMENT_IMMORTAL = "IMMORTAL"             # 100 boss fights survived
const ACHIEVEMENT_UNTOUCHABLE = "UNTOUCHABLE"       # 1000 hits, 0 deaths
const ACHIEVEMENT_SURVIVOR = "SURVIVOR"             # Survived 100 close calls
const ACHIEVEMENT_VETERAN = "VETERAN"               # 100+ hours equipped
const ACHIEVEMENT_EXPLORER = "EXPLORER"             # Visited 10+ zones
const ACHIEVEMENT_TANK = "TANK"                     # 100,000 damage absorbed
const ACHIEVEMENT_LUCKY = "LUCKY"                   # Survived hit >50% max HP

# ============================================
# VISUAL TIER
# ============================================

enum VisualTier {
	PRISTINE,     # Never worn in combat
	TESTED,       # 1+ hits taken
	PROVEN,       # 100+ hits survived
	BATTLE_WORN,  # 1000+ hits survived
	LEGENDARY,    # 10000+ hits survived
	MYTHIC        # 50000+ hits survived
}

# ============================================
# COMPUTED PROPERTIES
# ============================================

func is_virgin() -> bool:
	"""Virgin equipment has never been worn in combat"""
	return hits_received == 0 and damage_taken_total == 0 and time_equipped_seconds == 0

func get_survival_rate() -> float:
	"""Calculate survival rate as percentage"""
	if hits_received == 0:
		return 100.0
	return (float(hits_survived) / float(hits_received)) * 100.0

func get_visual_tier() -> VisualTier:
	"""Calculate visual tier based on hits survived"""
	if hits_survived >= 50000:
		return VisualTier.MYTHIC
	elif hits_survived >= 10000:
		return VisualTier.LEGENDARY
	elif hits_survived >= 1000:
		return VisualTier.BATTLE_WORN
	elif hits_survived >= 100:
		return VisualTier.PROVEN
	elif hits_survived >= 1:
		return VisualTier.TESTED
	else:
		return VisualTier.PRISTINE

func get_visual_tier_name() -> String:
	"""Get display name for visual tier"""
	match get_visual_tier():
		VisualTier.PRISTINE:
			return "PRISTINE"
		VisualTier.TESTED:
			return "TESTED"
		VisualTier.PROVEN:
			return "PROVEN"
		VisualTier.BATTLE_WORN:
			return "BATTLE-WORN"
		VisualTier.LEGENDARY:
			return "LEGENDARY"
		VisualTier.MYTHIC:
			return "MYTHIC"
		_:
			return "UNKNOWN"

func get_experience_to_next_level() -> int:
	"""Calculate XP needed for next level (infinite scaling at 1.08^level)"""
	return int(100.0 * pow(1.08, level))

func get_level_progress() -> float:
	"""Returns level progress as 0-1 value"""
	var xp_needed = get_experience_to_next_level()
	if xp_needed <= 0:
		return 0.0
	return float(experience) / float(xp_needed)

func get_defense_bonus() -> float:
	"""Calculate defense bonus from level (soft cap at 50)"""
	if level <= 50:
		return level * 0.5  # +0.5% damage reduction per level
	else:
		return 25.0 + (level - 50) * 0.05  # +0.05% per level after 50

func format_time_equipped() -> String:
	"""Format time equipped as human-readable string"""
	var hours = time_equipped_seconds / 3600
	var minutes = (time_equipped_seconds % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	else:
		return "%dm" % minutes

# ============================================
# STAT RECORDING METHODS
# ============================================

func record_hit_taken(damage: float, is_boss: bool = false, is_elite: bool = false) -> void:
	"""Record taking a hit"""
	hits_received += 1
	damage_taken_total += int(damage)

	# First hit milestone
	if hits_received == 1:
		first_hit_taken_at = _get_timestamp()
		_unlock_achievement(ACHIEVEMENT_FIRST_BLOOD)

	# 1000 hits milestone
	if hits_received == 1000:
		milestone_1000_hits_at = _get_timestamp()

	# Grant XP for surviving
	_grant_experience(1)

func record_hit_survived(damage: float) -> void:
	"""Record surviving a hit (didn't die)"""
	hits_survived += 1

	# Track max hit survived
	if int(damage) > damage_max_hit_survived:
		damage_max_hit_survived = int(damage)
		# Check LUCKY achievement (survived hit > 50% of typical max HP ~100)
		if damage >= 50:
			if not ACHIEVEMENT_LUCKY in achievements:
				_unlock_achievement(ACHIEVEMENT_LUCKY)

	# 100 survivals milestone
	if hits_survived == 100:
		milestone_100_survivals_at = _get_timestamp()

	# IRON_WALL achievement (1000 hits survived)
	if hits_survived == 1000:
		_unlock_achievement(ACHIEVEMENT_IRON_WALL)

	# UNTOUCHABLE check (1000 hits, 0 deaths)
	if hits_survived >= 1000 and deaths_wearing == 0:
		if not ACHIEVEMENT_UNTOUCHABLE in achievements:
			_unlock_achievement(ACHIEVEMENT_UNTOUCHABLE)

	_grant_experience(2)

func record_damage_absorbed(amount: float) -> void:
	"""Record damage mitigated by armor"""
	damage_absorbed += int(amount)

	# TANK achievement (100,000 damage absorbed)
	if damage_absorbed >= 100000:
		if not ACHIEVEMENT_TANK in achievements:
			_unlock_achievement(ACHIEVEMENT_TANK)

func record_close_call() -> void:
	"""Record dropping below 25% HP"""
	close_calls += 1

	# SURVIVOR achievement (100 close calls survived)
	if close_calls >= 100:
		if not ACHIEVEMENT_SURVIVOR in achievements:
			_unlock_achievement(ACHIEVEMENT_SURVIVOR)

	_grant_experience(5)

func record_death() -> void:
	"""Record death while wearing"""
	deaths_wearing += 1
	battles_lost += 1
	if first_death_at == "":
		first_death_at = _get_timestamp()

func record_boss_fight(survived: bool) -> void:
	"""Record boss encounter"""
	boss_fights_total += 1
	if survived:
		boss_fights_survived += 1
		_grant_experience(50)

		# IMMORTAL achievement (100 boss fights survived)
		if boss_fights_survived >= 100:
			if not ACHIEVEMENT_IMMORTAL in achievements:
				_unlock_achievement(ACHIEVEMENT_IMMORTAL)

func record_elite_fight(survived: bool) -> void:
	"""Record elite enemy encounter"""
	if survived:
		elite_fights_survived += 1
		_grant_experience(10)

func record_equip() -> void:
	"""Record equipment being equipped (new session)"""
	sessions_equipped += 1
	if first_equipped_at == "":
		first_equipped_at = _get_timestamp()

func add_equipped_time(seconds: int) -> void:
	"""Add time to equipped duration"""
	time_equipped_seconds += seconds
	# VETERAN achievement (100+ hours)
	if time_equipped_seconds >= 360000 and not ACHIEVEMENT_VETERAN in achievements:
		_unlock_achievement(ACHIEVEMENT_VETERAN)

func record_zone_visit(zone_id: String) -> void:
	"""Record visiting a zone"""
	if zone_id in zones_visited:
		zones_visited[zone_id] += 1
	else:
		zones_visited[zone_id] = 1

	# EXPLORER achievement (10+ unique zones)
	if zones_visited.size() >= 10:
		if not ACHIEVEMENT_EXPLORER in achievements:
			_unlock_achievement(ACHIEVEMENT_EXPLORER)

func record_healing(amount: float) -> void:
	"""Record healing received while wearing"""
	healing_received += int(amount)
	_grant_experience(1)

func record_effect_triggered() -> void:
	"""Record special effect activation"""
	effects_triggered += 1
	_grant_experience(3)

# ============================================
# EXPERIENCE & LEVELING
# ============================================

func _grant_experience(amount: int) -> void:
	"""Grant XP and handle level ups"""
	experience += amount

	# Check for level up (can level multiple times)
	while experience >= get_experience_to_next_level():
		experience -= get_experience_to_next_level()
		level += 1
		print("🛡️ Equipment leveled up to %d!" % level)

# ============================================
# ACHIEVEMENTS
# ============================================

func _unlock_achievement(achievement_id: String) -> void:
	"""Unlock a per-equipment achievement"""
	if achievement_id in achievements:
		return
	achievements.append(achievement_id)
	print("🏆 Equipment Achievement Unlocked: %s" % achievement_id)

func get_achievement_icon(achievement_id: String) -> String:
	"""Get emoji icon for achievement"""
	match achievement_id:
		ACHIEVEMENT_FIRST_BLOOD:
			return "🩸"
		ACHIEVEMENT_IRON_WALL:
			return "🧱"
		ACHIEVEMENT_IMMORTAL:
			return "👑"
		ACHIEVEMENT_UNTOUCHABLE:
			return "✨"
		ACHIEVEMENT_SURVIVOR:
			return "💪"
		ACHIEVEMENT_VETERAN:
			return "🕐"
		ACHIEVEMENT_EXPLORER:
			return "🗺️"
		ACHIEVEMENT_TANK:
			return "🛡️"
		ACHIEVEMENT_LUCKY:
			return "🍀"
		_:
			return "🏆"

# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	"""Serialize stats to dictionary for saving/chain storage"""
	return {
		# Defensive stats
		"damage_absorbed": damage_absorbed,
		"damage_taken_total": damage_taken_total,
		"hits_received": hits_received,
		"hits_survived": hits_survived,
		"damage_max_hit_survived": damage_max_hit_survived,
		# Survival stats
		"deaths_wearing": deaths_wearing,
		"close_calls": close_calls,
		"boss_fights_survived": boss_fights_survived,
		"boss_fights_total": boss_fights_total,
		"elite_fights_survived": elite_fights_survived,
		# Usage stats
		"time_equipped_seconds": time_equipped_seconds,
		"sessions_equipped": sessions_equipped,
		"zones_visited": zones_visited,
		# Heal/support stats
		"healing_received": healing_received,
		"buffs_received": buffs_received,
		"effects_triggered": effects_triggered,
		# Negative stats
		"battles_lost": battles_lost,
		"show_negative_stats": show_negative_stats,
		# Milestones
		"first_equipped_at": first_equipped_at,
		"first_hit_taken_at": first_hit_taken_at,
		"first_death_at": first_death_at,
		"milestone_1000_hits_at": milestone_1000_hits_at,
		"milestone_100_survivals_at": milestone_100_survivals_at,
		# Level
		"level": level,
		"experience": experience,
		# Achievements
		"achievements": achievements,
	}

static func from_dict(data: Dictionary) -> EquipmentStats:
	"""Deserialize stats from dictionary"""
	var stats = EquipmentStats.new()

	# Defensive stats
	stats.damage_absorbed = data.get("damage_absorbed", 0)
	stats.damage_taken_total = data.get("damage_taken_total", 0)
	stats.hits_received = data.get("hits_received", 0)
	stats.hits_survived = data.get("hits_survived", 0)
	stats.damage_max_hit_survived = data.get("damage_max_hit_survived", 0)
	# Survival stats
	stats.deaths_wearing = data.get("deaths_wearing", 0)
	stats.close_calls = data.get("close_calls", 0)
	stats.boss_fights_survived = data.get("boss_fights_survived", 0)
	stats.boss_fights_total = data.get("boss_fights_total", 0)
	stats.elite_fights_survived = data.get("elite_fights_survived", 0)
	# Usage stats
	stats.time_equipped_seconds = data.get("time_equipped_seconds", 0)
	stats.sessions_equipped = data.get("sessions_equipped", 0)
	stats.zones_visited = data.get("zones_visited", {})
	# Heal/support stats
	stats.healing_received = data.get("healing_received", 0)
	stats.buffs_received = data.get("buffs_received", 0)
	stats.effects_triggered = data.get("effects_triggered", 0)
	# Negative stats
	stats.battles_lost = data.get("battles_lost", 0)
	stats.show_negative_stats = data.get("show_negative_stats", true)
	# Milestones
	stats.first_equipped_at = data.get("first_equipped_at", "")
	stats.first_hit_taken_at = data.get("first_hit_taken_at", "")
	stats.first_death_at = data.get("first_death_at", "")
	stats.milestone_1000_hits_at = data.get("milestone_1000_hits_at", "")
	stats.milestone_100_survivals_at = data.get("milestone_100_survivals_at", "")
	# Level
	stats.level = data.get("level", 0)
	stats.experience = data.get("experience", 0)
	# Achievements
	var achievements_data = data.get("achievements", [])
	var typed_achievements: Array[String] = []
	for ach in achievements_data:
		typed_achievements.append(str(ach))
	stats.achievements = typed_achievements

	return stats

func _get_timestamp() -> String:
	"""Get current ISO timestamp"""
	var datetime = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02dT%02d:%02d:%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]

# ============================================
# DEBUG FUNCTIONS
# ============================================

func debug_add_levels(amount: int = 10) -> void:
	"""DEBUG: Add levels for testing"""
	var old_level = level
	for i in range(amount):
		level += 1
	print("🛡️ DEBUG: Equipment level %d → %d" % [old_level, level])

func debug_add_hits(amount: int = 100) -> void:
	"""DEBUG: Add hits survived for testing tier progression"""
	var old_hits = hits_survived
	var old_tier = get_visual_tier_name()

	hits_survived += amount
	hits_received += amount

	_grant_experience(amount * 2)

	var new_tier = get_visual_tier_name()
	print("🛡️ DEBUG: Equipment hits %d → %d (Tier: %s → %s)" % [old_hits, hits_survived, old_tier, new_tier])
