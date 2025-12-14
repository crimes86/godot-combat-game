extends Resource
class_name WeaponStats

## Forged Weapon Stats - Immutable Combat Biography
## Tracks kills, crits, damage, and all combat history for forged weapons.
## Virgin weapons (0/0/0/0) are pristine collectors' items.
## Stats can never be reset - that's the point.

# ============================================
# CORE KILL STATS
# ============================================

@export var kills_total: int = 0
@export var kills_by_type: Dictionary = {}  # enemy_type -> count
@export var kills_elite: int = 0
@export var kills_boss: int = 0
@export var kills_pvp: int = 0  # Future: player kills in PvP

# ============================================
# DAMAGE STATS
# ============================================

@export var damage_total: int = 0
@export var damage_max_hit: int = 0
@export var damage_overkill: int = 0  # Damage dealt beyond enemy HP

# ============================================
# CRITICAL HIT STATS
# ============================================

@export var crits_landed: int = 0
@export var hits_total: int = 0  # For calculating crit rate
@export var weakpoints_destroyed: int = 0
@export var chain_max_reached: int = 0

# ============================================
# USAGE STATS
# ============================================

@export var swings_total: int = 0  # Melee attacks
@export var shots_fired: int = 0   # Gun shots
@export var bursts_fired: int = 0  # Battle rifle bursts
@export var time_equipped_seconds: int = 0
@export var sessions_equipped: int = 0

# ============================================
# NEGATIVE STATS (Virgin Weapon Value)
# ============================================

@export var deaths_equipped: int = 0
@export var misses_total: int = 0
@export var battles_lost: int = 0
@export var show_negative_stats: bool = true  # Toggleable visibility

# ============================================
# MILESTONE TIMESTAMPS
# ============================================

@export var first_equipped_at: String = ""  # ISO datetime
@export var first_kill_at: String = ""
@export var first_crit_at: String = ""
@export var milestone_100_kills_at: String = ""
@export var milestone_1000_kills_at: String = ""
@export var milestone_10000_kills_at: String = ""

# ============================================
# INFINITE LEVEL SYSTEM (Soft Cap)
# ============================================

@export var level: int = 0
@export var experience: int = 0

# ============================================
# PER-WEAPON ACHIEVEMENTS
# ============================================

@export var achievements: Array[String] = []

# Achievement definitions
const ACHIEVEMENT_FIRST_BLOOD = "FIRST_BLOOD"       # First kill
const ACHIEVEMENT_CENTURION = "CENTURION"           # 100 kills
const ACHIEVEMENT_SLAYER = "SLAYER"                 # 1000 kills
const ACHIEVEMENT_LEGEND = "LEGEND"                 # 10000 kills
const ACHIEVEMENT_PERFECTIONIST = "PERFECTIONIST"   # 100 kills, 0 deaths
const ACHIEVEMENT_CRIT_MASTER = "CRIT_MASTER"       # 50% lifetime crit rate
const ACHIEVEMENT_CHAIN_KING = "CHAIN_KING"         # Reached chain 10
const ACHIEVEMENT_UNTOUCHED = "UNTOUCHED"           # 500 kills, 0 misses
const ACHIEVEMENT_OVERKILL = "OVERKILL"             # Single hit 500+ overkill
const ACHIEVEMENT_VETERAN = "VETERAN"               # 100+ hours equipped

# ============================================
# VISUAL TIER
# ============================================

enum VisualTier {
	PRISTINE,     # 0 kills, 0 deaths, 0 misses
	BLOODED,      # 1+ kills
	VETERAN,      # 100+ kills
	BATTLE_WORN,  # 1000+ kills
	LEGENDARY,    # 10000+ kills
	MYTHIC        # 50000+ kills
}

# ============================================
# COMPUTED PROPERTIES
# ============================================

func is_virgin() -> bool:
	"""A virgin weapon has never been used in combat"""
	return kills_total == 0 and hits_total == 0 and swings_total == 0 and shots_fired == 0

func get_crit_rate_lifetime() -> float:
	"""Calculate lifetime crit rate as percentage"""
	if hits_total == 0:
		return 0.0
	return (float(crits_landed) / float(hits_total)) * 100.0

func get_visual_tier() -> VisualTier:
	"""Calculate visual tier based on kills (BLOODED requires first blood)"""
	if kills_total >= 50000:
		return VisualTier.MYTHIC
	elif kills_total >= 10000:
		return VisualTier.LEGENDARY
	elif kills_total >= 1000:
		return VisualTier.BATTLE_WORN
	elif kills_total >= 100:
		return VisualTier.VETERAN
	elif kills_total >= 1:
		return VisualTier.BLOODED  # First blood earned
	else:
		return VisualTier.PRISTINE  # No kills yet (even if used)

func get_evolution_tier() -> int:
	"""Calculate evolution tier for visual effects (uses both level AND kills).
	Returns WeaponVisualEvolution.EvolutionTier enum value."""
	# Use both level AND kills - whichever gives higher tier
	var level_tier = _tier_from_level(level)
	var kill_tier = _tier_from_kills(kills_total)
	return level_tier if level_tier > kill_tier else kill_tier

func _tier_from_level(lvl: int) -> int:
	"""Helper for evolution tier calculation from level"""
	if lvl <= 0:
		return 0  # VIRGIN
	elif lvl <= 10:
		return 1  # BLOODED
	elif lvl <= 25:
		return 2  # VETERAN
	elif lvl <= 40:
		return 3  # BATTLE_WORN
	elif lvl <= 60:
		return 4  # LEGENDARY
	else:
		return 5  # MYTHIC

func _tier_from_kills(kills: int) -> int:
	"""Helper for evolution tier calculation from kills"""
	if kills <= 0:
		return 0  # VIRGIN
	elif kills < 100:
		return 1  # BLOODED
	elif kills < 1000:
		return 2  # VETERAN
	elif kills < 10000:
		return 3  # BATTLE_WORN
	elif kills < 50000:
		return 4  # LEGENDARY
	else:
		return 5  # MYTHIC

func get_visual_tier_name() -> String:
	"""Get display name for visual tier"""
	match get_visual_tier():
		VisualTier.PRISTINE:
			return "PRISTINE"
		VisualTier.BLOODED:
			return "BLOODED"
		VisualTier.VETERAN:
			return "VETERAN"
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

func get_damage_bonus() -> float:
	"""Calculate damage bonus from level (soft cap at 50)"""
	if level <= 50:
		return level * 1.0  # +1 damage per level
	else:
		return 50.0 + (level - 50) * 0.1  # +0.1 damage per level after 50

func get_crit_bonus() -> float:
	"""DEPRECATED: Crit chance now comes purely from Luck stat, not weapons.
	Returns 0.0 for backwards compatibility with UI displays."""
	return 0.0

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

func record_hit(damage: float, is_crit: bool, enemy_type: String, enemy_hp_remaining: float) -> void:
	"""Record a successful hit"""
	hits_total += 1
	damage_total += int(damage)

	# Track max hit
	if int(damage) > damage_max_hit:
		damage_max_hit = int(damage)

	# Track overkill
	if enemy_hp_remaining < 0:
		var overkill = int(abs(enemy_hp_remaining))
		damage_overkill += overkill
		# Check for OVERKILL achievement
		if overkill >= 500 and not ACHIEVEMENT_OVERKILL in achievements:
			_unlock_achievement(ACHIEVEMENT_OVERKILL)

	# Track crit
	if is_crit:
		crits_landed += 1
		if first_crit_at == "":
			first_crit_at = _get_timestamp()
		# Check for CRIT_MASTER (50% crit rate, min 100 hits)
		if hits_total >= 100 and get_crit_rate_lifetime() >= 50.0:
			if not ACHIEVEMENT_CRIT_MASTER in achievements:
				_unlock_achievement(ACHIEVEMENT_CRIT_MASTER)

	# Grant XP for hitting enemies
	_grant_experience(1)

func record_kill(enemy_type: String, is_elite: bool = false, is_boss: bool = false) -> void:
	"""Record a kill"""
	kills_total += 1

	# Track by type
	if enemy_type in kills_by_type:
		kills_by_type[enemy_type] += 1
	else:
		kills_by_type[enemy_type] = 1

	# Track elite/boss
	if is_elite:
		kills_elite += 1
	if is_boss:
		kills_boss += 1

	# First kill
	if kills_total == 1:
		first_kill_at = _get_timestamp()
		_unlock_achievement(ACHIEVEMENT_FIRST_BLOOD)

	# Kill milestones
	if kills_total == 100:
		milestone_100_kills_at = _get_timestamp()
		_unlock_achievement(ACHIEVEMENT_CENTURION)
		# Check PERFECTIONIST (100 kills, 0 deaths)
		if deaths_equipped == 0:
			_unlock_achievement(ACHIEVEMENT_PERFECTIONIST)
	elif kills_total == 1000:
		milestone_1000_kills_at = _get_timestamp()
		_unlock_achievement(ACHIEVEMENT_SLAYER)
	elif kills_total == 10000:
		milestone_10000_kills_at = _get_timestamp()
		_unlock_achievement(ACHIEVEMENT_LEGEND)

	# Check UNTOUCHED (500 kills, 0 misses)
	if kills_total >= 500 and misses_total == 0:
		if not ACHIEVEMENT_UNTOUCHED in achievements:
			_unlock_achievement(ACHIEVEMENT_UNTOUCHED)

	# Grant XP for kills (more than hits)
	var xp_amount = 10
	if is_elite:
		xp_amount = 25
	if is_boss:
		xp_amount = 100
	_grant_experience(xp_amount)

func record_pvp_kill() -> void:
	"""Record a PvP kill (future)"""
	kills_pvp += 1
	_grant_experience(50)

func record_weakpoint_destroyed() -> void:
	"""Record a weakpoint destruction"""
	weakpoints_destroyed += 1
	_grant_experience(5)

func record_chain_level(chain_level: int) -> void:
	"""Record chain level achieved"""
	if chain_level > chain_max_reached:
		chain_max_reached = chain_level
		# Check CHAIN_KING
		if chain_level >= 10 and not ACHIEVEMENT_CHAIN_KING in achievements:
			_unlock_achievement(ACHIEVEMENT_CHAIN_KING)

func record_swing() -> void:
	"""Record a melee swing"""
	swings_total += 1

func record_shot() -> void:
	"""Record a gun shot"""
	shots_fired += 1

func record_burst() -> void:
	"""Record a burst fire sequence"""
	bursts_fired += 1

func record_miss() -> void:
	"""Record a missed attack"""
	misses_total += 1

func record_death() -> void:
	"""Record a death while equipped"""
	deaths_equipped += 1
	battles_lost += 1

func record_equip() -> void:
	"""Record weapon being equipped (new session)"""
	sessions_equipped += 1
	if first_equipped_at == "":
		first_equipped_at = _get_timestamp()

func add_equipped_time(seconds: int) -> void:
	"""Add time to equipped duration"""
	time_equipped_seconds += seconds
	# Check VETERAN (100+ hours)
	if time_equipped_seconds >= 360000 and not ACHIEVEMENT_VETERAN in achievements:
		_unlock_achievement(ACHIEVEMENT_VETERAN)

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
		print("⚔️ Weapon leveled up to %d!" % level)

# ============================================
# ACHIEVEMENTS
# ============================================

func _unlock_achievement(achievement_id: String) -> void:
	"""Unlock a per-weapon achievement"""
	if achievement_id in achievements:
		return
	achievements.append(achievement_id)
	print("🏆 Weapon Achievement Unlocked: %s" % achievement_id)

func get_achievement_icon(achievement_id: String) -> String:
	"""Get emoji icon for achievement"""
	match achievement_id:
		ACHIEVEMENT_FIRST_BLOOD:
			return "🩸"
		ACHIEVEMENT_CENTURION:
			return "💯"
		ACHIEVEMENT_SLAYER:
			return "⚔️"
		ACHIEVEMENT_LEGEND:
			return "👑"
		ACHIEVEMENT_PERFECTIONIST:
			return "✨"
		ACHIEVEMENT_CRIT_MASTER:
			return "🎯"
		ACHIEVEMENT_CHAIN_KING:
			return "🔗"
		ACHIEVEMENT_UNTOUCHED:
			return "🎭"
		ACHIEVEMENT_OVERKILL:
			return "💥"
		ACHIEVEMENT_VETERAN:
			return "🕐"
		_:
			return "🏆"

# ============================================
# SERIALIZATION
# ============================================

func to_dict() -> Dictionary:
	"""Serialize stats to dictionary for saving"""
	return {
		# Kill stats
		"kills_total": kills_total,
		"kills_by_type": kills_by_type,
		"kills_elite": kills_elite,
		"kills_boss": kills_boss,
		"kills_pvp": kills_pvp,
		# Damage stats
		"damage_total": damage_total,
		"damage_max_hit": damage_max_hit,
		"damage_overkill": damage_overkill,
		# Crit stats
		"crits_landed": crits_landed,
		"hits_total": hits_total,
		"weakpoints_destroyed": weakpoints_destroyed,
		"chain_max_reached": chain_max_reached,
		# Usage stats
		"swings_total": swings_total,
		"shots_fired": shots_fired,
		"bursts_fired": bursts_fired,
		"time_equipped_seconds": time_equipped_seconds,
		"sessions_equipped": sessions_equipped,
		# Negative stats
		"deaths_equipped": deaths_equipped,
		"misses_total": misses_total,
		"battles_lost": battles_lost,
		"show_negative_stats": show_negative_stats,
		# Milestones
		"first_equipped_at": first_equipped_at,
		"first_kill_at": first_kill_at,
		"first_crit_at": first_crit_at,
		"milestone_100_kills_at": milestone_100_kills_at,
		"milestone_1000_kills_at": milestone_1000_kills_at,
		"milestone_10000_kills_at": milestone_10000_kills_at,
		# Level
		"level": level,
		"experience": experience,
		# Achievements
		"achievements": achievements,
	}

static func from_dict(data: Dictionary) -> WeaponStats:
	"""Deserialize stats from dictionary"""
	var stats = WeaponStats.new()

	# Kill stats
	stats.kills_total = data.get("kills_total", 0)
	stats.kills_by_type = data.get("kills_by_type", {})
	stats.kills_elite = data.get("kills_elite", 0)
	stats.kills_boss = data.get("kills_boss", 0)
	stats.kills_pvp = data.get("kills_pvp", 0)
	# Damage stats
	stats.damage_total = data.get("damage_total", 0)
	stats.damage_max_hit = data.get("damage_max_hit", 0)
	stats.damage_overkill = data.get("damage_overkill", 0)
	# Crit stats
	stats.crits_landed = data.get("crits_landed", 0)
	stats.hits_total = data.get("hits_total", 0)
	stats.weakpoints_destroyed = data.get("weakpoints_destroyed", 0)
	stats.chain_max_reached = data.get("chain_max_reached", 0)
	# Usage stats
	stats.swings_total = data.get("swings_total", 0)
	stats.shots_fired = data.get("shots_fired", 0)
	stats.bursts_fired = data.get("bursts_fired", 0)
	stats.time_equipped_seconds = data.get("time_equipped_seconds", 0)
	stats.sessions_equipped = data.get("sessions_equipped", 0)
	# Negative stats
	stats.deaths_equipped = data.get("deaths_equipped", 0)
	stats.misses_total = data.get("misses_total", 0)
	stats.battles_lost = data.get("battles_lost", 0)
	stats.show_negative_stats = data.get("show_negative_stats", true)
	# Milestones
	stats.first_equipped_at = data.get("first_equipped_at", "")
	stats.first_kill_at = data.get("first_kill_at", "")
	stats.first_crit_at = data.get("first_crit_at", "")
	stats.milestone_100_kills_at = data.get("milestone_100_kills_at", "")
	stats.milestone_1000_kills_at = data.get("milestone_1000_kills_at", "")
	stats.milestone_10000_kills_at = data.get("milestone_10000_kills_at", "")
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
	"""DEBUG: Add levels to weapon for testing visual effects"""
	var old_level = level
	var old_tier = get_visual_tier_name()

	# Grant enough XP to level up the specified amount
	for i in range(amount):
		level += 1

	var new_tier = get_visual_tier_name()
	print("⚔️ DEBUG: Weapon level %d → %d (Tier: %s → %s)" % [old_level, level, old_tier, new_tier])

func debug_add_kills(amount: int = 100) -> void:
	"""DEBUG: Add kills to weapon for testing tier progression"""
	var old_kills = kills_total
	var old_tier = get_visual_tier_name()

	kills_total += amount

	# Also add some XP
	_grant_experience(amount * 10)

	var new_tier = get_visual_tier_name()
	print("💀 DEBUG: Weapon kills %d → %d (Tier: %s → %s)" % [old_kills, kills_total, old_tier, new_tier])

func debug_set_tier(tier_name: String) -> void:
	"""DEBUG: Set weapon to specific tier for testing"""
	match tier_name.to_upper():
		"PRISTINE":
			kills_total = 0
			level = 0
		"BLOODED":
			kills_total = 50
			level = 5
		"VETERAN":
			kills_total = 500
			level = 20
		"BATTLE-WORN", "BATTLEWORN":
			kills_total = 5000
			level = 35
		"LEGENDARY":
			kills_total = 25000
			level = 50
		"MYTHIC":
			kills_total = 60000
			level = 70
	print("⚔️ DEBUG: Weapon set to tier %s (Level: %d, Kills: %d)" % [get_visual_tier_name(), level, kills_total])
