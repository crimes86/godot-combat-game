extends RefCounted
class_name WeaponStatsDisplay

## WeaponStatsDisplay - Helper for formatting weapon stats for UI
## Provides data extraction methods for different display surfaces:
## - Quick tooltip (inventory hover)
## - Inspect panel (detailed view)
## - Trade preview (buyer evaluation)
## - Armory display (collection showcase)

# ============================================
# QUICK TOOLTIP DATA (Tier 1)
# ============================================

static func get_quick_tooltip_data(weapon: Weapon) -> Dictionary:
	"""Get data for quick tooltip display (inventory hover)"""
	var data = {
		"name": weapon.get_display_name(),
		"rarity": weapon.get_rarity_name(),
		"rarity_color": weapon.get_rarity_color(),
		"damage": weapon.get_total_damage(),
		"is_forged": weapon.is_forged,
		"is_virgin": false,
		"visual_tier": "",
		"kills": 0,
		"crit_rate": 0.0,
		"level": 0,
		"top_achievements": [],
	}

	if weapon.is_forged and weapon.weapon_stats:
		var stats = weapon.weapon_stats
		data["is_virgin"] = stats.is_virgin()
		data["visual_tier"] = stats.get_visual_tier_name()
		data["kills"] = stats.kills_total
		data["crit_rate"] = stats.get_crit_rate_lifetime()
		data["level"] = stats.level

		# Get top 2 achievements with icons
		var achievement_count = mini(stats.achievements.size(), 2)
		for i in range(achievement_count):
			var ach = stats.achievements[i]
			data["top_achievements"].append({
				"id": ach,
				"icon": stats.get_achievement_icon(ach)
			})

	return data

# ============================================
# INSPECT PANEL DATA (Tier 2)
# ============================================

static func get_inspect_panel_data(weapon: Weapon) -> Dictionary:
	"""Get full data for inspect panel display"""
	var data = get_quick_tooltip_data(weapon)

	if weapon.is_forged and weapon.weapon_stats:
		var stats = weapon.weapon_stats
		data.merge({
			# Kill breakdown
			"kills_by_type": stats.kills_by_type.duplicate(),
			"kills_elite": stats.kills_elite,
			"kills_boss": stats.kills_boss,

			# Damage stats
			"damage_total": stats.damage_total,
			"damage_max_hit": stats.damage_max_hit,
			"damage_overkill": stats.damage_overkill,

			# Crit stats
			"crits_landed": stats.crits_landed,
			"hits_total": stats.hits_total,
			"weakpoints_destroyed": stats.weakpoints_destroyed,
			"chain_max": stats.chain_max_reached,

			# Usage stats
			"swings_total": stats.swings_total,
			"shots_fired": stats.shots_fired,
			"bursts_fired": stats.bursts_fired,
			"time_equipped": format_time(stats.time_equipped_seconds),
			"sessions_equipped": stats.sessions_equipped,

			# All achievements
			"achievements": _get_all_achievements(stats),

			# Milestones
			"milestones": _get_milestones(stats),

			# Level progress
			"experience": stats.experience,
			"experience_to_next": stats.get_experience_to_next_level(),
			"level_progress": stats.get_level_progress(),
			"damage_bonus": stats.get_damage_bonus(),
			"crit_bonus": stats.get_crit_bonus() * 100,  # As percentage
		})

		# Negative stats (if shown)
		if stats.show_negative_stats:
			data["deaths"] = stats.deaths_equipped
			data["misses"] = stats.misses_total
			data["battles_lost"] = stats.battles_lost
		else:
			data["negative_stats_hidden"] = true

	return data

# ============================================
# TRADE PREVIEW DATA
# ============================================

static func get_trade_preview_data(weapon: Weapon) -> Dictionary:
	"""Get data for trade preview display"""
	var data = get_quick_tooltip_data(weapon)

	if weapon.is_forged and weapon.weapon_stats:
		var stats = weapon.weapon_stats
		data.merge({
			"damage_max_hit": stats.damage_max_hit,
			"forged_id": weapon.forged_id,

			# Top 3 achievements for trade preview
			"achievements": [],
		})

		var achievement_count = mini(stats.achievements.size(), 3)
		for i in range(achievement_count):
			var ach = stats.achievements[i]
			data["achievements"].append({
				"id": ach,
				"icon": stats.get_achievement_icon(ach)
			})

		# Negative stats only if shown
		if stats.show_negative_stats:
			data["deaths"] = stats.deaths_equipped
		else:
			data["deaths_hidden"] = true

	return data

# ============================================
# ARMORY DISPLAY DATA
# ============================================

static func get_armory_display_data(weapon: Weapon) -> Dictionary:
	"""Get data for armory/collection display"""
	var data = {
		"name": weapon.get_display_name(),
		"rarity": weapon.get_rarity_name(),
		"rarity_color": weapon.get_rarity_color(),
		"weapon_type": weapon.weapon_type,
		"is_forged": weapon.is_forged,
		"is_virgin": false,
		"visual_tier": "",
		"kills": 0,
		"level": 0,
		"achievements": [],
		"milestones": [],
	}

	if weapon.is_forged and weapon.weapon_stats:
		var stats = weapon.weapon_stats
		data["is_virgin"] = stats.is_virgin()
		data["visual_tier"] = stats.get_visual_tier_name()
		data["kills"] = stats.kills_total
		data["level"] = stats.level
		data["achievements"] = _get_all_achievements(stats)
		data["milestones"] = _get_milestones(stats)

	return data

# ============================================
# FORMATTING HELPERS
# ============================================

static func format_time(seconds: int) -> String:
	"""Format seconds as human-readable duration"""
	var hours = seconds / 3600
	var minutes = (seconds % 3600) / 60

	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	else:
		return "%dm" % minutes

static func format_number(num: int) -> String:
	"""Format large numbers with commas"""
	var s = str(num)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

static func format_timestamp(iso_timestamp: String) -> String:
	"""Format ISO timestamp as readable date"""
	if iso_timestamp == "":
		return ""

	# Parse YYYY-MM-DDTHH:MM:SS
	var parts = iso_timestamp.split("T")
	if parts.size() < 1:
		return iso_timestamp

	var date_parts = parts[0].split("-")
	if date_parts.size() < 3:
		return parts[0]

	var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
				  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var month_idx = int(date_parts[1]) - 1
	if month_idx < 0 or month_idx > 11:
		return parts[0]

	return "%s %s, %s" % [months[month_idx], date_parts[2], date_parts[0]]

static func _get_all_achievements(stats: WeaponStats) -> Array:
	"""Get all achievements with icons and display names"""
	var achievements = []
	for ach in stats.achievements:
		achievements.append({
			"id": ach,
			"icon": stats.get_achievement_icon(ach),
			"name": _get_achievement_display_name(ach)
		})
	return achievements

static func _get_achievement_display_name(ach_id: String) -> String:
	"""Get display name for achievement"""
	match ach_id:
		WeaponStats.ACHIEVEMENT_FIRST_BLOOD:
			return "First Blood"
		WeaponStats.ACHIEVEMENT_CENTURION:
			return "Centurion"
		WeaponStats.ACHIEVEMENT_SLAYER:
			return "Slayer"
		WeaponStats.ACHIEVEMENT_LEGEND:
			return "Legend"
		WeaponStats.ACHIEVEMENT_PERFECTIONIST:
			return "Perfectionist"
		WeaponStats.ACHIEVEMENT_CRIT_MASTER:
			return "Crit Master"
		WeaponStats.ACHIEVEMENT_CHAIN_KING:
			return "Chain King"
		WeaponStats.ACHIEVEMENT_UNTOUCHED:
			return "Untouched"
		WeaponStats.ACHIEVEMENT_OVERKILL:
			return "Overkill"
		WeaponStats.ACHIEVEMENT_VETERAN:
			return "Veteran"
		_:
			return ach_id

static func _get_milestones(stats: WeaponStats) -> Array:
	"""Get milestone timestamps formatted for display"""
	var milestones = []

	if stats.first_equipped_at != "":
		milestones.append({
			"label": "First Equipped",
			"date": format_timestamp(stats.first_equipped_at)
		})

	if stats.first_kill_at != "":
		milestones.append({
			"label": "First Blood",
			"date": format_timestamp(stats.first_kill_at)
		})

	if stats.first_crit_at != "":
		milestones.append({
			"label": "First Critical",
			"date": format_timestamp(stats.first_crit_at)
		})

	if stats.milestone_100_kills_at != "":
		milestones.append({
			"label": "100 Kills",
			"date": format_timestamp(stats.milestone_100_kills_at)
		})

	if stats.milestone_1000_kills_at != "":
		milestones.append({
			"label": "1,000 Kills",
			"date": format_timestamp(stats.milestone_1000_kills_at)
		})

	if stats.milestone_10000_kills_at != "":
		milestones.append({
			"label": "10,000 Kills",
			"date": format_timestamp(stats.milestone_10000_kills_at)
		})

	return milestones

# ============================================
# BBCode TOOLTIP GENERATION
# ============================================

static func generate_quick_tooltip_bbcode(weapon: Weapon) -> String:
	"""Generate BBCode tooltip for RichTextLabel"""
	var data = get_quick_tooltip_data(weapon)

	var text = "[b]%s[/b]\n" % data["name"]
	text += "[color=#%s]%s[/color]" % [data["rarity_color"].to_html(false), data["rarity"]]

	if data["is_forged"] and data["visual_tier"] != "":
		text += " · %s" % data["visual_tier"]
	text += "\n\n"

	text += "Damage: +%.1f\n" % data["damage"]

	if data["is_forged"]:
		if data["is_virgin"]:
			text += "\n[color=gold]✧ PRISTINE ✧[/color]\n"
			text += "[i]Never drawn in battle[/i]\n"
		else:
			text += "\n%s kills" % format_number(data["kills"])
			if data["crit_rate"] > 0:
				text += " · %.1f%% crit" % data["crit_rate"]
			text += "\n"

			if data["top_achievements"].size() > 0:
				var icons = ""
				for ach in data["top_achievements"]:
					icons += ach["icon"]
				text += icons + "\n"

		text += "\n[color=#666666][Right-click to inspect][/color]"

	return text

static func generate_inspect_panel_bbcode(weapon: Weapon) -> String:
	"""Generate full BBCode for inspect panel"""
	var data = get_inspect_panel_data(weapon)

	var text = "[b][font_size=18]%s[/font_size][/b]\n" % data["name"]
	text += "[color=#%s]%s[/color]" % [data["rarity_color"].to_html(false), data["rarity"]]

	if data["is_forged"] and data["visual_tier"] != "":
		text += " · [b]%s[/b]" % data["visual_tier"]
	text += "\n\n"

	# Combat stats
	text += "[b]Combat Stats[/b]\n"
	text += "  Damage: +%.1f" % data["damage"]
	if data.get("damage_bonus", 0) > 0:
		text += " [color=#88ff88](+%.1f from level)[/color]" % data["damage_bonus"]
	text += "\n"

	if data.get("crit_bonus", 0) > 0:
		text += "  Crit Bonus: +%.1f%%\n" % data["crit_bonus"]

	if data["is_forged"]:
		text += "\n[b]Kill Stats[/b]\n"
		text += "  Total Kills: %s\n" % format_number(data["kills"])

		if data.get("kills_by_type", {}).size() > 0:
			for enemy_type in data["kills_by_type"]:
				text += "    • %s: %s\n" % [enemy_type.capitalize(), format_number(data["kills_by_type"][enemy_type])]

		if data.get("kills_elite", 0) > 0:
			text += "  Elite Kills: %s\n" % format_number(data["kills_elite"])
		if data.get("kills_boss", 0) > 0:
			text += "  Boss Kills: %s\n" % format_number(data["kills_boss"])

		text += "\n[b]Damage Stats[/b]\n"
		text += "  Total Damage: %s\n" % format_number(data.get("damage_total", 0))
		text += "  Max Hit: %s\n" % format_number(data.get("damage_max_hit", 0))
		text += "  Overkill: %s\n" % format_number(data.get("damage_overkill", 0))

		text += "\n[b]Critical Hits[/b]\n"
		text += "  Crits Landed: %s\n" % format_number(data.get("crits_landed", 0))
		text += "  Crit Rate: %.1f%%\n" % data["crit_rate"]
		text += "  Weakpoints: %s\n" % format_number(data.get("weakpoints_destroyed", 0))
		text += "  Max Chain: %d\n" % data.get("chain_max", 0)

		text += "\n[b]Usage[/b]\n"
		text += "  Time Equipped: %s\n" % data.get("time_equipped", "0m")
		text += "  Sessions: %d\n" % data.get("sessions_equipped", 0)

		if not data.get("negative_stats_hidden", false):
			text += "\n[b]Negative Stats[/b]\n"
			text += "  Deaths: %d\n" % data.get("deaths", 0)
			text += "  Misses: %d\n" % data.get("misses", 0)
		else:
			text += "\n[color=#666666][Negative stats hidden by owner][/color]\n"

		# Level progress
		text += "\n[b]Level %d[/b]\n" % data["level"]
		var progress_pct = data.get("level_progress", 0.0) * 100
		text += "  Progress: %.0f%% (%s / %s XP)\n" % [
			progress_pct,
			format_number(data.get("experience", 0)),
			format_number(data.get("experience_to_next", 100))
		]

		# Achievements
		if data.get("achievements", []).size() > 0:
			text += "\n[b]Achievements[/b]\n"
			for ach in data["achievements"]:
				text += "  %s %s\n" % [ach["icon"], ach["name"]]

		# Milestones
		if data.get("milestones", []).size() > 0:
			text += "\n[b]Milestones[/b]\n"
			for milestone in data["milestones"]:
				text += "  %s: %s\n" % [milestone["label"], milestone["date"]]

	return text
