extends Node
## ChunkExpansionManager - Manages dynamic chunk expansion and World Tree competition
##
## Responsibilities:
## - Track seed plot claims and trigger world expansion
## - Calculate World Tree rankings weekly
## - Handle chunk removal when seed plots decay
## - Record winners on Ashbane blockchain
##
## Architecture:
## - Origin chunks (-1, 0, 1): Permanent, connected to campfire
## - Dynamic chunks: Created when edge seed plots are claimed
## - Seed plots decay after 7 days of inactivity

# ═══════════════════════════════════════════════════════════════════════════════
# SIGNALS
# ═══════════════════════════════════════════════════════════════════════════════

signal chunk_expanded(new_min_chunk: int, new_max_chunk: int)
signal chunk_removed(chunk_id: int)
signal seed_plot_claimed(chunk_id: int, player_id: String)
signal seed_plot_abandoned(chunk_id: int)
signal world_tree_ranked(week_number: int, rankings: Array)
signal world_tree_promoted(winner_id: String, seed_plot_id: int)

# World Tree v2.1 signals
signal tree_upgraded(chunk_id: int, new_rank: int)
signal building_placed(chunk_id: int, building_type: String)
signal building_destroyed(chunk_id: int, building_id: int)
signal bane_stone_planted(target_chunk_id: int, attacker_guild: String)
signal bane_stone_destroyed(bane_id: int, outcome: String)
signal guild_changed(chunk_id: int, new_guild: String)
signal ownership_transferred(chunk_id: int, new_owner: String)
signal tree_duplicated(original_chunk: int, champion_chunk: int)  # Fix #2

# ═══════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

# World Tree v2.1 - Starting chunks (11 total: -5 to +5)
const STARTING_CHUNKS: Array = [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5]
const ORIGIN_CHUNKS: Array = [-1, 0, 1]  # Permanent origin chunks
const ORIGIN_CHAMPION_CHUNK: int = -1  # World Tree position (Fix #2 - renamed)

# Chunk configuration
const CHUNK_SIZE: int = 8000  # Pixels
const BASE_CLAIM_COST: int = 1000  # Gold

# World Tree v2.1 - Extended decay timings (Fix #3)
const DYNAMIC_CHUNK_DECAY_DAYS: int = 90  # Extended from 7
const CHAMPION_MIGRATION_DAYS: int = 14  # 2 weeks for champion migration
const MIGRATION_DURATION_DAYS: int = 7  # 1 week migration period after winning

# Contribution scoring
const GOLD_POINTS: int = 1
const WOOD_POINTS: int = 5
const STONE_POINTS: int = 5
const GEM_POINTS: int = 50
const KILL_POINTS: int = 2
const BOSS_KILL_POINTS: int = 20  # World Tree v2.1 - Fix #11
const TIME_POINTS_PER_HOUR: float = 1.0

# Neutral factions (Fix #4)
const NEUTRAL_FACTIONS: Array = ["azura", "crimson", "verdant", "obsidian", "celestial"]
const NEUTRAL_FACTION_MULTIPLIER: float = 1.5

# Tree ranks (Fix #8)
const MAX_TREE_RANK: int = 7

# Building costs
const BUILDING_COSTS: Dictionary = {
	"campfire": 5000,
	"warehouse": 10000,
	"vendor": 15000,
	"shrine": 20000,
	"smithy": 25000,
	"fortress": 30000
}

# Warehouse limits (Fix #6)
const WAREHOUSE_SAFE_LIMITS: Dictionary = {
	"gold": 50000,
	"wood": 5000,
	"stone": 5000,
	"gems": 5000
}

# Bane system (Fix #5, #10)
const BANE_PLANT_COST: int = 50000
const BANE_HEALTH: int = 50000
const BANE_WINDOW_HOURS: int = 1

# ═══════════════════════════════════════════════════════════════════════════════
# STATE
# ═══════════════════════════════════════════════════════════════════════════════

# Active chunks
var active_chunks: Dictionary = {}  # chunk_id -> {type: "origin"|"dynamic", player_count: int}
var current_min_chunk: int = -1
var current_max_chunk: int = 1

# Seed plots
var seed_plots: Dictionary = {}  # chunk_id -> SeedPlotData

# Current shard ID
var shard_id: String = "default"

# Weekly rankings
var current_week: int = 0
var rankings: Array = []

# Database manager reference
var db: Node = null

# HTTP request for blockchain recording
var _http_request: HTTPRequest = null

# ═══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	print("🌍 ChunkExpansionManager: Initializing...")

	# Get database manager
	db = get_node_or_null("/root/DatabaseManager")
	if not db:
		push_warning("⚠️ ChunkExpansionManager: DatabaseManager not found - running in offline mode")

	# Setup HTTP request for blockchain
	_http_request = HTTPRequest.new()
	add_child(_http_request)
	_http_request.request_completed.connect(_on_blockchain_record_complete)

	# Get current shard ID
	shard_id = _get_shard_id()

	# World Tree v2.1 - Initialize 11 starting chunks (-5 to +5)
	_initialize_starting_chunks()

	# Load active chunks from database
	_load_active_chunks()

	# Load seed plots from database (or create if new server)
	_load_seed_plots()

	# World Tree v2.1 - Create starting seed plots if none exist
	if seed_plots.size() == 0:
		_create_starting_seed_plots()

	# Calculate current week number
	current_week = _get_current_week()

	# Check for weekly ranking calculation
	_check_weekly_ranking()

	print("🌍 ChunkExpansionManager: Ready! Chunks %d to %d, %d seed plots" % [current_min_chunk, current_max_chunk, seed_plots.size()])


func _process(delta: float) -> void:
	# Check for decay every minute
	if Time.get_ticks_msec() % 60000 < delta * 1000:
		_check_seed_plot_decay()


# ═══════════════════════════════════════════════════════════════════════════════
# SEED PLOT MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

## Claim a seed plot with gold payment
func claim_seed_plot(chunk_id: int, player_id: String, player_gold: int) -> Dictionary:
	# Check if seed plot exists
	if not seed_plots.has(chunk_id):
		return {"success": false, "error": "Seed plot not found"}

	var plot = seed_plots[chunk_id]

	# Check if already claimed
	if plot.state != "unclaimed" and plot.state != "decaying":
		return {"success": false, "error": "Seed plot already claimed"}

	# Calculate cost
	var cost = _calculate_claim_cost(chunk_id)
	if plot.state == "decaying":
		cost = int(cost * 0.5)  # Half price during decay

	# Check if player has enough gold
	if player_gold < cost:
		return {"success": false, "error": "Not enough gold", "cost": cost}

	# Claim the plot
	plot.owner_id = player_id
	plot.original_owner_id = player_id  # World Tree v2.1 - Fix #1 (dual ownership)
	plot.claimed_at = Time.get_datetime_dict_from_system()
	plot.last_contribution_at = plot.claimed_at
	plot.state = "claimed"
	plot.claim_cost = cost

	# World Tree v2.1 - Fix #4: Assign neutral faction if player has no guild
	if not plot.has("current_guild_id") or plot.current_guild_id == "":
		var faction_hash = hash(player_id)
		plot.faction = NEUTRAL_FACTIONS[abs(faction_hash) % NEUTRAL_FACTIONS.size()]
	else:
		plot.faction = "guild"

	# World Tree v2.1 - Initialize tree rank
	plot.tree_rank = 0
	plot.tree_health = 0
	plot.tree_max_health = 0

	# Save to database
	if db:
		_save_seed_plot_to_db(plot)

	# Check if both edge plots are claimed -> expand world
	_check_expansion_trigger()

	seed_plot_claimed.emit(chunk_id, player_id)

	return {"success": true, "cost": cost, "plot_id": chunk_id, "faction": plot.faction}


## Add contribution to a seed plot
func add_contribution(chunk_id: int, player_id: String, contribution: Dictionary) -> void:
	if not seed_plots.has(chunk_id):
		return

	var plot = seed_plots[chunk_id]

	# Update totals
	plot.total_gold_contributed += contribution.get("gold", 0)
	plot.total_wood_contributed += contribution.get("wood", 0)
	plot.total_stone_contributed += contribution.get("stone", 0)
	plot.total_kills += contribution.get("kills", 0)

	# World Tree v2.1 - Fix #11: Track boss kills separately
	if not plot.has("total_boss_kills"):
		plot.total_boss_kills = 0
	plot.total_boss_kills += contribution.get("boss_kills", 0)

	plot.total_time_minutes += contribution.get("time_minutes", 0)

	# Recalculate score
	plot.contribution_score = _calculate_contribution_score(plot)

	# World Tree v2.1 - Fix #4: Apply neutral faction multiplier
	if plot.faction in NEUTRAL_FACTIONS:
		plot.contribution_score = int(plot.contribution_score * NEUTRAL_FACTION_MULTIPLIER)

	# Update last contribution time
	plot.last_contribution_at = Time.get_datetime_dict_from_system()

	# Reset abandoned state if it was decaying
	if plot.state == "abandoned" or plot.state == "decaying":
		plot.state = "claimed"
		plot.abandoned_at = null
		plot.decay_warning_sent = false

	# Save to database
	if db:
		_save_seed_plot_to_db(plot)
		_save_contribution_to_db(chunk_id, player_id, contribution)


## Get seed plot data
func get_seed_plot(chunk_id: int) -> Dictionary:
	return seed_plots.get(chunk_id, {})


## Get all seed plots
func get_all_seed_plots() -> Array:
	return seed_plots.values()


# ═══════════════════════════════════════════════════════════════════════════════
# CHUNK EXPANSION
# ═══════════════════════════════════════════════════════════════════════════════

## Expand world by adding chunks on both edges
func expand_world() -> void:
	print("🌍 Expanding world...")

	# Add chunks on both sides
	var new_min = current_min_chunk - 1
	var new_max = current_max_chunk + 1

	# Create new chunks
	_create_chunk(new_min, "dynamic")
	_create_chunk(new_max, "dynamic")

	# Create seed plots for new edge chunks
	_create_seed_plot(new_min)
	_create_seed_plot(new_max)

	# Update range
	current_min_chunk = new_min
	current_max_chunk = new_max

	# Save to database
	if db:
		_save_active_chunks_to_db()

	chunk_expanded.emit(new_min, new_max)

	print("🌍 World expanded! New range: %d to %d" % [current_min_chunk, current_max_chunk])


## Remove a chunk when its seed plot decays
func remove_chunk(chunk_id: int) -> void:
	if chunk_id in ORIGIN_CHUNKS:
		push_error("❌ Cannot remove origin chunk: %d" % chunk_id)
		return

	print("🌍 Removing chunk %d..." % chunk_id)

	# Teleport players in chunk
	_teleport_players_from_chunk(chunk_id)

	# Despawn enemies and props
	_despawn_chunk_entities(chunk_id)

	# Remove from active chunks
	active_chunks.erase(chunk_id)
	seed_plots.erase(chunk_id)

	# Update chunk range if this was an edge
	if chunk_id == current_min_chunk:
		current_min_chunk += 1
	elif chunk_id == current_max_chunk:
		current_max_chunk -= 1

	# Save to database
	if db:
		_save_active_chunks_to_db()
		_delete_seed_plot_from_db(chunk_id)

	chunk_removed.emit(chunk_id)

	print("🌍 Chunk %d removed. New range: %d to %d" % [chunk_id, current_min_chunk, current_max_chunk])


# ═══════════════════════════════════════════════════════════════════════════════
# WORLD TREE COMPETITION
# ═══════════════════════════════════════════════════════════════════════════════

## Calculate weekly rankings
func calculate_weekly_rankings() -> void:
	print("🏆 Calculating World Tree rankings for week %d..." % current_week)

	# Get all claimed seed plots
	var claimed_plots = []
	for plot in seed_plots.values():
		if plot.state == "claimed" and plot.owner_id != "":
			claimed_plots.append(plot)

	# Sort by contribution score
	claimed_plots.sort_custom(func(a, b): return a.contribution_score > b.contribution_score)

	# Create rankings
	rankings.clear()
	for i in range(claimed_plots.size()):
		var plot = claimed_plots[i]
		rankings.append({
			"rank": i + 1,
			"seed_plot_id": plot.chunk_id,
			"owner_id": plot.owner_id,
			"total_score": plot.contribution_score,
			"chunk_id": plot.chunk_id
		})

	# Save to database
	if db:
		_save_rankings_to_db()

	# Promote winner to origin chunk
	if rankings.size() > 0:
		var winner = rankings[0]
		_promote_to_world_tree(winner)

	world_tree_ranked.emit(current_week, rankings)

	print("🏆 Rankings calculated! Winner: %s with %d points" % [rankings[0].owner_id if rankings.size() > 0 else "none", rankings[0].total_score if rankings.size() > 0 else 0])


## Get current rankings
func get_rankings() -> Array:
	return rankings.duplicate()


## Get player rank
func get_player_rank(player_id: String) -> int:
	for ranking in rankings:
		if ranking.owner_id == player_id:
			return ranking.rank
	return -1


# ═══════════════════════════════════════════════════════════════════════════════
# BLOCKCHAIN INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════════

## Record World Tree winner on Ashbane blockchain
func record_world_tree_on_chain(winner: Dictionary, all_trees: Array) -> void:
	if not AshbaneAuth:
		push_warning("⚠️ AshbaneAuth not available - skipping blockchain record")
		return

	print("⛓️ Recording World Tree winner on blockchain...")

	# Get top 10 contributors with wallet addresses
	var top_contributors = []
	if db:
		top_contributors = db.query("""
			SELECT wtc.user_id, u.username, wa.wallet_address, wtc.contribution_score
			FROM world_tree_contributions wtc
			JOIN users u ON wtc.user_id = u.id
			LEFT JOIN wallet_accounts wa ON u.id = wa.user_id
			WHERE wtc.week_number = %d
			ORDER BY wtc.contribution_score DESC
			LIMIT 10
		""" % current_week)

	# Prepare payload
	var payload = {
		"week_number": current_week,
		"shard_id": shard_id,
		"chunk_id": winner.get("chunk_id", ORIGIN_WEST_CHUNK),
		"owner_id": winner.owner_id,
		"total_score": winner.total_score,
		"top_contributors": top_contributors,
		"recorded_at": Time.get_datetime_string_from_system()
	}

	# Send to Ashbane backend
	var url = "%s/api/world-tree/record" % AshbaneAuth.backend_url
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer %s" % AshbaneAuth.get_auth_token()
	]

	_http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))


## Callback when blockchain record completes
func _on_blockchain_record_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and response.success:
			print("⛓️ Blockchain record successful! TX: %s" % response.tx_hash)

			# Update database with blockchain record
			if db and rankings.size() > 0:
				db.execute("""
					UPDATE world_tree_rankings
					SET blockchain_record_id = %d,
					    blockchain_tx_hash = '%s',
					    recorded_on_chain_at = CURRENT_TIMESTAMP
					WHERE week_number = %d AND shard_id = '%s'
				""" % [response.record_id, response.tx_hash, current_week, shard_id])
		else:
			push_error("❌ Blockchain record failed: %s" % response.get("error", "unknown"))
	else:
		push_error("❌ Blockchain record HTTP error: %d" % response_code)


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

## World Tree v2.1 - Initialize starting chunks (-5 to +5)
func _initialize_starting_chunks() -> void:
	for chunk_id in STARTING_CHUNKS:
		var chunk_type = "origin" if chunk_id in ORIGIN_CHUNKS else "starting"
		active_chunks[chunk_id] = {
			"type": chunk_type,
			"player_count": 0,
			"created_at": Time.get_datetime_string_from_system()
		}

	current_min_chunk = STARTING_CHUNKS[0]
	current_max_chunk = STARTING_CHUNKS[-1]


## World Tree v2.1 - Create starting seed plots for all 11 chunks
func _create_starting_seed_plots() -> void:
	print("🌍 Creating starting seed plots for chunks -5 to +5...")

	for chunk_id in STARTING_CHUNKS:
		_create_seed_plot(chunk_id)

	# Save all to database
	if db:
		for plot in seed_plots.values():
			_save_seed_plot_to_db(plot)

	print("🌍 Created %d starting seed plots" % seed_plots.size())


## Create a new chunk
func _create_chunk(chunk_id: int, type: String) -> void:
	active_chunks[chunk_id] = {
		"type": type,
		"player_count": 0,
		"created_at": Time.get_datetime_string_from_system()
	}


## Create a seed plot for a chunk
## World Tree v2.1 - Include all new fields
func _create_seed_plot(chunk_id: int) -> void:
	# Calculate position (center of chunk)
	var x = chunk_id * CHUNK_SIZE + CHUNK_SIZE / 2
	var y = 0.0

	seed_plots[chunk_id] = {
		"chunk_id": chunk_id,
		"position_x": x,
		"position_y": y,
		"owner_id": "",
		"original_owner_id": "",  # Fix #1
		"current_guild_id": "",
		"guild_name": "",
		"faction": "individual",  # Fix #4
		"claimed_at": null,
		"last_contribution_at": null,
		"state": "unclaimed",
		"claim_cost": _calculate_claim_cost(chunk_id),
		"total_gold_contributed": 0,
		"total_wood_contributed": 0,
		"total_stone_contributed": 0,
		"total_kills": 0,
		"total_boss_kills": 0,  # Fix #11
		"total_time_minutes": 0,
		"contribution_score": 0,
		"abandoned_at": null,
		"decay_warning_sent": false,
		# v2.1 tree fields
		"is_origin_champion": false,  # Fix #2
		"champion_since": null,
		"is_decaying": false,  # Fix #3
		"decay_complete_at": null,
		"migration_expires": null,
		"original_chunk_id": null,
		"tree_rank": 0,  # Fix #8
		"tree_health": 0,
		"tree_max_health": 0,
		"upgrade_started_at": null,
		"upgrade_target_rank": null,
		"last_watered": null,
		"times_watered": 0,
		"growth_bonus_accumulated": 0.0,
		"allow_public_binding": false,
		# v2.1 warehouse fields (Fix #6)
		"warehouse_safe_gold": 0,
		"warehouse_safe_wood": 0,
		"warehouse_safe_stone": 0,
		"warehouse_safe_gems": 0,
		"warehouse_overflow_gold": 0,
		"warehouse_overflow_wood": 0,
		"warehouse_overflow_stone": 0,
		"warehouse_overflow_gems": 0,
		"claimed_mine_ids": [],  # v2.1 mines
		"defense_window_hour": 20,  # Fix #10
		"defense_window_timezone_offset": 0,
		"last_ownership_transfer": null,
		"last_guild_change": null
	}


## Calculate claim cost based on distance from origin
## World Tree v2.1 - Fix #12: Logarithmic formula for balanced costs
func _calculate_claim_cost(chunk_id: int) -> int:
	var distance = abs(chunk_id)

	# Starting chunks (-5 to +5) are free/cheap
	if distance <= 5:
		return BASE_CLAIM_COST

	# Exponential for chunks 6-8 (±1 to ±3 from edge)
	if distance <= 8:
		var edge_distance = distance - 5
		return int(BASE_CLAIM_COST * pow(2, edge_distance))

	# Linear for chunks 9+ (±4+)
	# Formula: BASE * 2^3 + (distance - 8) * BASE * 2
	return int(BASE_CLAIM_COST * 8 + (distance - 8) * BASE_CLAIM_COST * 2)


## Calculate contribution score
func _calculate_contribution_score(plot: Dictionary) -> int:
	var score = 0
	score += plot.total_gold_contributed * GOLD_POINTS
	score += plot.total_wood_contributed * WOOD_POINTS
	score += plot.total_stone_contributed * STONE_POINTS
	score += plot.total_kills * KILL_POINTS

	# World Tree v2.1 - Fix #11: Add boss kills scoring
	if plot.has("total_boss_kills"):
		score += plot.total_boss_kills * BOSS_KILL_POINTS

	score += int(plot.total_time_minutes / 60.0 * TIME_POINTS_PER_HOUR)
	return score


## Check if expansion should trigger
func _check_expansion_trigger() -> void:
	# Check if both edge chunks have claimed seed plots
	var west_edge = current_min_chunk
	var east_edge = current_max_chunk

	if seed_plots.has(west_edge) and seed_plots.has(east_edge):
		var west_plot = seed_plots[west_edge]
		var east_plot = seed_plots[east_edge]

		if west_plot.state == "claimed" and east_plot.state == "claimed":
			expand_world()


## Check for seed plot decay
## World Tree v2.1 - Fix #3: Extended decay timings
func _check_seed_plot_decay() -> void:
	var now = Time.get_datetime_dict_from_system()
	var now_unix = Time.get_unix_time_from_datetime_dict(now)

	for plot in seed_plots.values():
		if plot.state != "claimed":
			continue

		if not plot.last_contribution_at:
			continue

		var last_unix = Time.get_unix_time_from_datetime_dict(plot.last_contribution_at)
		var days_inactive = (now_unix - last_unix) / 86400.0

		# Determine decay threshold based on tree type
		var decay_threshold = DYNAMIC_CHUNK_DECAY_DAYS
		if plot.has("is_origin_champion") and plot.is_origin_champion:
			decay_threshold = CHAMPION_MIGRATION_DAYS  # 14 days for champion trees

		if days_inactive >= decay_threshold:
			# Mark as decaying
			plot.state = "decaying"
			plot.is_decaying = true
			plot.decay_complete_at = Time.get_datetime_dict_from_unix_time(now_unix + MIGRATION_DURATION_DAYS * 86400)
			seed_plot_abandoned.emit(plot.chunk_id)

			if db:
				_save_seed_plot_to_db(plot)

		# Check if decay period is complete
		if plot.state == "decaying" and plot.has("decay_complete_at"):
			var decay_complete_unix = Time.get_unix_time_from_datetime_dict(plot.decay_complete_at)
			if now_unix >= decay_complete_unix:
				# Remove chunk (unless it's origin or starting chunk)
				if plot.chunk_id not in STARTING_CHUNKS:
					remove_chunk(plot.chunk_id)


## Check if weekly ranking should run
func _check_weekly_ranking() -> void:
	var now = Time.get_datetime_dict_from_system()

	# Check if it's Sunday midnight UTC
	if now.weekday == 7 and now.hour == 0:
		var week = _get_current_week()

		# Only run once per week
		if week > current_week:
			current_week = week
			calculate_weekly_rankings()


## Get current week number (weeks since epoch)
func _get_current_week() -> int:
	return int(Time.get_unix_time_from_system() / 604800)  # 604800 = seconds in a week


## Get shard ID from environment or config
func _get_shard_id() -> String:
	# TODO: Read from server config or environment
	return "default"


## Promote winner to World Tree position
## World Tree v2.1 - Fix #2: Duplicate tree instead of teleporting
func _promote_to_world_tree(winner: Dictionary) -> void:
	print("🌳 Promoting seed plot %d to World Tree!" % winner.seed_plot_id)

	var original_plot = seed_plots.get(winner.seed_plot_id, {})
	if original_plot.is_empty():
		push_error("❌ Cannot promote: Original plot not found")
		return

	# Create duplicate tree at origin champion chunk (-1)
	var champion_chunk = ORIGIN_CHAMPION_CHUNK
	var champion_plot = {
		"chunk_id": champion_chunk,
		"position_x": champion_chunk * CHUNK_SIZE + CHUNK_SIZE / 2,
		"position_y": 0.0,
		"owner_id": original_plot.owner_id,
		"original_owner_id": original_plot.get("original_owner_id", original_plot.owner_id),
		"current_guild_id": original_plot.get("current_guild_id", ""),
		"guild_name": original_plot.get("guild_name", ""),
		"faction": original_plot.get("faction", "individual"),
		"claimed_at": Time.get_datetime_dict_from_system(),
		"last_contribution_at": Time.get_datetime_dict_from_system(),
		"state": "claimed",
		"is_origin_champion": true,  # Mark as champion
		"champion_since": Time.get_datetime_dict_from_system(),
		"original_chunk_id": winner.seed_plot_id,  # Remember where it came from
		"tree_rank": original_plot.get("tree_rank", 0),
		"tree_health": original_plot.get("tree_health", 0),
		"tree_max_health": original_plot.get("tree_max_health", 0),
		"claim_cost": 0,  # Champion trees are not for sale
		"total_gold_contributed": 0,
		"total_wood_contributed": 0,
		"total_stone_contributed": 0,
		"total_kills": 0,
		"total_boss_kills": 0,
		"total_time_minutes": 0,
		"contribution_score": 0
	}

	# Replace existing champion if one exists
	if seed_plots.has(champion_chunk):
		var old_champion = seed_plots[champion_chunk]
		print("🌳 Replacing previous champion: %s" % old_champion.owner_id)

		# Start migration period for old champion (7 days)
		old_champion.is_decaying = true
		old_champion.is_origin_champion = false
		old_champion.migration_expires = Time.get_datetime_dict_from_unix_time(
			Time.get_unix_time_from_system() + MIGRATION_DURATION_DAYS * 86400
		)

	# Add new champion
	seed_plots[champion_chunk] = champion_plot

	# Mark original tree as having produced champion (but keep it active)
	original_plot.champion_since = champion_plot.champion_since

	# Update ranking in database
	if db:
		db.execute("""
			UPDATE world_tree_rankings
			SET promoted_to_origin = 1,
			    promoted_at = CURRENT_TIMESTAMP
			WHERE week_number = %d AND shard_id = '%s' AND rank = 1
		""" % [current_week, shard_id])

		_save_seed_plot_to_db(champion_plot)
		_save_seed_plot_to_db(original_plot)

	# Record on blockchain
	record_world_tree_on_chain(winner, rankings)

	tree_duplicated.emit(winner.seed_plot_id, champion_chunk)
	world_tree_promoted.emit(winner.owner_id, winner.seed_plot_id)

	print("🌳 Tree duplicated! Original: %d → Champion: %d" % [winner.seed_plot_id, champion_chunk])


## Teleport players from removed chunk
func _teleport_players_from_chunk(chunk_id: int) -> void:
	# Get all players in chunk
	var players = get_tree().get_nodes_in_group("player")

	for player in players:
		var player_pos = player.global_position
		var player_chunk = int(player_pos.x / CHUNK_SIZE)

		if player_chunk == chunk_id:
			# Teleport to spawn (chunk 0)
			player.global_position = Vector2(0, 0)
			print("📍 Teleported %s from removed chunk %d" % [player.name, chunk_id])


## Despawn entities in chunk
func _despawn_chunk_entities(chunk_id: int) -> void:
	# Despawn enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		var enemy_pos = enemy.global_position
		var enemy_chunk = int(enemy_pos.x / CHUNK_SIZE)

		if enemy_chunk == chunk_id:
			enemy.queue_free()

	# Despawn props
	var props = get_tree().get_nodes_in_group("props")
	for prop in props:
		var prop_pos = prop.global_position
		var prop_chunk = int(prop_pos.x / CHUNK_SIZE)

		if prop_chunk == chunk_id:
			prop.queue_free()


# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE PERSISTENCE
# ═══════════════════════════════════════════════════════════════════════════════

func _load_active_chunks() -> void:
	if not db:
		return

	var result = db.query("SELECT * FROM active_chunks WHERE shard_id = '%s'" % shard_id)
	for row in result:
		active_chunks[row.chunk_id] = {
			"type": row.chunk_type,
			"player_count": row.player_count,
			"created_at": row.created_at
		}

		# Update chunk range
		if row.chunk_id < current_min_chunk:
			current_min_chunk = row.chunk_id
		if row.chunk_id > current_max_chunk:
			current_max_chunk = row.chunk_id


func _load_seed_plots() -> void:
	if not db:
		return

	var result = db.query("SELECT * FROM seed_plots WHERE shard_id = '%s'" % shard_id)
	for row in result:
		seed_plots[row.chunk_id] = {
			"chunk_id": row.chunk_id,
			"position_x": row.position_x,
			"position_y": row.position_y,
			"owner_id": row.owner_id,
			"claimed_at": row.claimed_at,
			"last_contribution_at": row.last_contribution_at,
			"state": row.state,
			"claim_cost": row.claim_cost,
			"total_gold_contributed": row.total_gold_contributed,
			"total_wood_contributed": row.total_wood_contributed,
			"total_stone_contributed": row.total_stone_contributed,
			"total_kills": row.total_kills,
			"total_time_minutes": row.total_time_minutes,
			"contribution_score": row.contribution_score,
			"abandoned_at": row.abandoned_at,
			"decay_warning_sent": row.decay_warning_sent
		}


func _save_active_chunks_to_db() -> void:
	if not db:
		return

	for chunk_id in active_chunks:
		var chunk = active_chunks[chunk_id]
		db.execute("""
			INSERT OR REPLACE INTO active_chunks
			(shard_id, chunk_id, chunk_type, created_at, player_count, is_loaded)
			VALUES ('%s', %d, '%s', '%s', %d, 1)
		""" % [shard_id, chunk_id, chunk.type, chunk.created_at, chunk.player_count])


func _save_seed_plot_to_db(plot: Dictionary) -> void:
	if not db:
		return

	db.execute("""
		INSERT OR REPLACE INTO seed_plots
		(shard_id, chunk_id, position_x, position_y, owner_id, claimed_at,
		 last_contribution_at, state, claim_cost, total_gold_contributed,
		 total_wood_contributed, total_stone_contributed, total_kills,
		 total_time_minutes, contribution_score, abandoned_at, decay_warning_sent)
		VALUES ('%s', %d, %f, %f, '%s', '%s', '%s', '%s', %d, %d, %d, %d, %d, %d, %d, '%s', %d)
	""" % [
		shard_id, plot.chunk_id, plot.position_x, plot.position_y,
		plot.owner_id, plot.claimed_at, plot.last_contribution_at,
		plot.state, plot.claim_cost, plot.total_gold_contributed,
		plot.total_wood_contributed, plot.total_stone_contributed,
		plot.total_kills, plot.total_time_minutes, plot.contribution_score,
		plot.abandoned_at, 1 if plot.decay_warning_sent else 0
	])


func _delete_seed_plot_from_db(chunk_id: int) -> void:
	if not db:
		return

	db.execute("DELETE FROM seed_plots WHERE shard_id = '%s' AND chunk_id = %d" % [shard_id, chunk_id])


func _save_contribution_to_db(chunk_id: int, player_id: String, contribution: Dictionary) -> void:
	if not db:
		return

	# World Tree v2.1 - Include boss_kills in scoring
	var score = (
		contribution.get("gold", 0) * GOLD_POINTS +
		contribution.get("wood", 0) * WOOD_POINTS +
		contribution.get("stone", 0) * STONE_POINTS +
		contribution.get("gems", 0) * GEM_POINTS +
		contribution.get("kills", 0) * KILL_POINTS +
		contribution.get("boss_kills", 0) * BOSS_KILL_POINTS +
		int(contribution.get("time_minutes", 0) / 60.0 * TIME_POINTS_PER_HOUR)
	)

	# Get or create seed plot ID
	var seed_plot_id = db.query_single(
		"SELECT id FROM seed_plots WHERE shard_id = '%s' AND chunk_id = %d" % [shard_id, chunk_id]
	)

	if not seed_plot_id:
		return

	# Upsert contribution (with boss_kills)
	db.execute("""
		INSERT INTO world_tree_contributions
		(seed_plot_id, user_id, week_number, gold_contributed, wood_contributed,
		 stone_contributed, gems_contributed, kills, boss_kills, time_minutes, contribution_score,
		 first_contribution_at, last_contribution_at)
		VALUES (%d, '%s', %d, %d, %d, %d, %d, %d, %d, %d, %d, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
		ON CONFLICT(seed_plot_id, user_id, week_number) DO UPDATE SET
		 gold_contributed = gold_contributed + %d,
		 wood_contributed = wood_contributed + %d,
		 stone_contributed = stone_contributed + %d,
		 gems_contributed = gems_contributed + %d,
		 kills = kills + %d,
		 boss_kills = boss_kills + %d,
		 time_minutes = time_minutes + %d,
		 contribution_score = contribution_score + %d,
		 last_contribution_at = CURRENT_TIMESTAMP
	""" % [
		seed_plot_id.id, player_id, current_week,
		contribution.get("gold", 0), contribution.get("wood", 0),
		contribution.get("stone", 0), contribution.get("gems", 0),
		contribution.get("kills", 0), contribution.get("boss_kills", 0),
		contribution.get("time_minutes", 0), score,
		contribution.get("gold", 0), contribution.get("wood", 0),
		contribution.get("stone", 0), contribution.get("gems", 0),
		contribution.get("kills", 0), contribution.get("boss_kills", 0),
		contribution.get("time_minutes", 0), score
	])


func _save_rankings_to_db() -> void:
	if not db:
		return

	for ranking in rankings:
		var plot = seed_plots.get(ranking.seed_plot_id, {})
		var seed_plot_db_id = db.query_single(
			"SELECT id FROM seed_plots WHERE shard_id = '%s' AND chunk_id = %d" % [shard_id, ranking.seed_plot_id]
		)

		if not seed_plot_db_id:
			continue

		db.execute("""
			INSERT OR REPLACE INTO world_tree_rankings
			(shard_id, week_number, week_start, week_end, seed_plot_id, owner_id,
			 total_score, rank, is_active, promoted_to_origin)
			VALUES ('%s', %d, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, %d, '%s', %d, %d, 1, 0)
		""" % [
			shard_id, current_week, seed_plot_db_id.id,
			ranking.owner_id, ranking.total_score, ranking.rank
		])
