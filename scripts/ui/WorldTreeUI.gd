extends CanvasLayer
class_name WorldTreeUI

## World Tree UI - Main hub for World Tree v2.1 features
##
## Features:
## - Seed plot claiming with faction display
## - Tree management (upgrade, watering)
## - Building placement system
## - Warehouse management (safe + overflow)
## - Resource mine claiming and collection
## - Bane system (plant and defend)
## - Guild management
## - Seasonal rankings

signal ui_closed()
signal plot_claimed(chunk_id: int)
signal tree_upgraded(chunk_id: int, new_rank: int)
signal building_placed(chunk_id: int, building_type: String, slot: String)
signal warehouse_deposited(chunk_id: int, resources: Dictionary)
signal warehouse_withdrawn(chunk_id: int, resources: Dictionary)
signal mine_claimed(chunk_id: int, mine_id: int)
signal mine_collected(chunk_id: int, mine_id: int)
signal bane_planted(target_chunk_id: int, attacker_guild: String)
signal guild_changed(chunk_id: int, new_guild: String)

# Stone Gray UI Palette (matching project standard)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.85)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)
const ITEM_BG_COLOR = Color(0.08, 0.08, 0.10, 0.9)
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)

# Faction colors (World Tree v2.1)
const FACTION_COLORS = {
	"azura": Color(0.3, 0.6, 0.9),       # Blue
	"crimson": Color(0.9, 0.3, 0.3),     # Red
	"verdant": Color(0.3, 0.8, 0.3),     # Green
	"obsidian": Color(0.2, 0.2, 0.2),    # Black
	"celestial": Color(0.9, 0.9, 0.5),   # Gold
	"guild": Color(0.7, 0.4, 0.9),       # Purple
	"individual": Color(0.5, 0.5, 0.5)   # Gray
}

# Tree rank icons/colors
const RANK_COLORS = {
	0: Color(0.5, 0.5, 0.5),   # Seedling - Gray
	1: Color(0.6, 0.4, 0.2),   # Sapling - Brown
	2: Color(0.4, 0.6, 0.3),   # Young - Light Green
	3: Color(0.3, 0.7, 0.3),   # Mature - Green
	4: Color(0.3, 0.8, 0.5),   # Ancient - Deep Green
	5: Color(0.5, 0.8, 0.9),   # Elder - Cyan
	6: Color(0.8, 0.7, 0.9),   # Mythic - Purple
	7: Color(0.9, 0.8, 0.4)    # Legendary - Gold
}

@onready var main_panel: PanelContainer = $Control/Panel
@onready var close_button: Button = $Control/Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var tab_container: TabContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer

# Tab content nodes
@onready var my_tree_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/MyTree/VBoxContainer
@onready var claim_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Claim/VBoxContainer
@onready var buildings_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Buildings/VBoxContainer
@onready var warehouse_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Warehouse/VBoxContainer
@onready var mines_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Mines/VBoxContainer
@onready var bane_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Bane/VBoxContainer
@onready var rankings_tab: VBoxContainer = $Control/Panel/MarginContainer/VBoxContainer/TabContainer/Rankings/VBoxContainer

# Current state
var current_plot: Dictionary = {}
var chunk_expansion_manager: Node = null
var player: Node = null

func _ready() -> void:
	print("🌳 WorldTreeUI initialized")
	hide()

	# Set layer to 100
	layer = 100

	# Add to UI group
	add_to_group("world_tree_ui")

	# Apply modern styling
	apply_modern_styling()

	# Get manager references
	chunk_expansion_manager = get_node_or_null("/root/ChunkExpansionManager")
	if not chunk_expansion_manager:
		push_warning("⚠️ WorldTreeUI: ChunkExpansionManager not found")

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect tab changes
	if tab_container:
		tab_container.tab_changed.connect(_on_tab_changed)

	# Connect to ChunkExpansionManager signals
	if chunk_expansion_manager:
		chunk_expansion_manager.seed_plot_claimed.connect(_on_plot_claimed)
		chunk_expansion_manager.tree_upgraded.connect(_on_tree_upgraded)
		chunk_expansion_manager.building_placed.connect(_on_building_placed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		close_ui()
		get_viewport().set_input_as_handled()


## Open the UI for a specific seed plot
func open_for_plot(chunk_id: int, _player: Node) -> void:
	player = _player

	# Load seed plot data
	if chunk_expansion_manager:
		current_plot = chunk_expansion_manager.get_seed_plot(chunk_id)

	if current_plot.is_empty():
		push_error("❌ Cannot open World Tree UI: Plot %d not found" % chunk_id)
		return

	# Refresh all tabs
	_refresh_my_tree_tab()
	_refresh_claim_tab()
	_refresh_buildings_tab()
	_refresh_warehouse_tab()
	_refresh_mines_tab()
	_refresh_bane_tab()
	_refresh_rankings_tab()

	# Default to appropriate tab
	if current_plot.owner_id == "":
		tab_container.current_tab = 1  # Claim tab
	else:
		tab_container.current_tab = 0  # My Tree tab

	show()
	print("🌳 Opened World Tree UI for chunk %d" % chunk_id)


## Close the UI
func close_ui() -> void:
	hide()
	current_plot = {}
	ui_closed.emit()


func _on_close_pressed() -> void:
	close_ui()


func _on_tab_changed(tab: int) -> void:
	# Refresh active tab content
	match tab:
		0: _refresh_my_tree_tab()
		1: _refresh_claim_tab()
		2: _refresh_buildings_tab()
		3: _refresh_warehouse_tab()
		4: _refresh_mines_tab()
		5: _refresh_bane_tab()
		6: _refresh_rankings_tab()


# ═══════════════════════════════════════════════════════════════════════════════
# MY TREE TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_my_tree_tab() -> void:
	if not my_tree_tab:
		return

	# Clear existing content
	for child in my_tree_tab.get_children():
		child.queue_free()

	if current_plot.owner_id == "":
		var label = Label.new()
		label.text = "This plot is unclaimed.\nGo to the Claim tab to claim it!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		my_tree_tab.add_child(label)
		return

	# Tree info header
	var header = _create_header("🌳 Tree Information")
	my_tree_tab.add_child(header)

	# Rank display
	var rank = current_plot.get("tree_rank", 0)
	var rank_label = Label.new()
	rank_label.text = "Rank: %d / 7" % rank
	rank_label.add_theme_color_override("font_color", RANK_COLORS.get(rank, TEXT_COLOR))
	my_tree_tab.add_child(rank_label)

	# Faction display
	var faction = current_plot.get("faction", "individual")
	var faction_label = Label.new()
	faction_label.text = "Faction: %s" % faction.capitalize()
	faction_label.add_theme_color_override("font_color", FACTION_COLORS.get(faction, TEXT_COLOR))
	my_tree_tab.add_child(faction_label)

	# Guild info
	if current_plot.has("current_guild_id") and current_plot.current_guild_id != "":
		var guild_label = Label.new()
		guild_label.text = "Guild: %s" % current_plot.get("guild_name", "Unknown")
		guild_label.add_theme_color_override("font_color", FACTION_COLORS["guild"])
		my_tree_tab.add_child(guild_label)

	# Champion status
	if current_plot.get("is_origin_champion", false):
		var champion_label = Label.new()
		champion_label.text = "⭐ Origin Champion Tree"
		champion_label.add_theme_color_override("font_color", RANK_COLORS[7])
		my_tree_tab.add_child(champion_label)

	# Add spacing
	my_tree_tab.add_child(HSeparator.new())

	# Upgrade button (if not max rank)
	if rank < 7:
		var upgrade_btn = Button.new()
		upgrade_btn.text = "Upgrade to Rank %d" % (rank + 1)
		upgrade_btn.pressed.connect(_on_upgrade_tree_pressed)
		my_tree_tab.add_child(upgrade_btn)

	# Water button
	var water_btn = Button.new()
	var times_watered = current_plot.get("times_watered", 0)
	water_btn.text = "Water Tree (Watered: %d times)" % times_watered
	water_btn.pressed.connect(_on_water_tree_pressed)
	my_tree_tab.add_child(water_btn)

	# Growth bonus display
	var growth_bonus = current_plot.get("growth_bonus_accumulated", 0.0)
	if growth_bonus > 0:
		var bonus_label = Label.new()
		bonus_label.text = "Growth Bonus: +%.1f%%" % (growth_bonus * 100)
		bonus_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
		my_tree_tab.add_child(bonus_label)

	# Add spacing
	my_tree_tab.add_child(HSeparator.new())

	# Contribution stats
	var stats_header = _create_header("📊 Contribution Stats")
	my_tree_tab.add_child(stats_header)

	var stats_label = Label.new()
	stats_label.text = """Gold: %d
Wood: %d
Stone: %d
Kills: %d
Boss Kills: %d
Score: %d""" % [
		current_plot.get("total_gold_contributed", 0),
		current_plot.get("total_wood_contributed", 0),
		current_plot.get("total_stone_contributed", 0),
		current_plot.get("total_kills", 0),
		current_plot.get("total_boss_kills", 0),
		current_plot.get("contribution_score", 0)
	]
	stats_label.add_theme_color_override("font_color", TEXT_COLOR)
	my_tree_tab.add_child(stats_label)


# ═══════════════════════════════════════════════════════════════════════════════
# CLAIM TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_claim_tab() -> void:
	if not claim_tab:
		return

	# Clear existing content
	for child in claim_tab.get_children():
		child.queue_free()

	if current_plot.owner_id != "":
		var label = Label.new()
		label.text = "This plot is already claimed by:\n%s" % current_plot.owner_id
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		claim_tab.add_child(label)
		return

	# Claim header
	var header = _create_header("🌱 Plant World Tree Seed")
	claim_tab.add_child(header)

	# Seed requirement display
	var seed_label = Label.new()
	seed_label.text = "Required: World Tree Seed"
	seed_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	claim_tab.add_child(seed_label)

	# Chunk info
	var chunk_id = current_plot.get("chunk_id", 0)
	var info_label = Label.new()
	info_label.text = "Chunk: %d\nDistance from origin: %d chunks" % [chunk_id, abs(chunk_id)]
	info_label.add_theme_color_override("font_color", TEXT_COLOR)
	claim_tab.add_child(info_label)

	# Add spacing
	claim_tab.add_child(HSeparator.new())

	# Claim button
	var claim_btn = Button.new()
	claim_btn.text = "Plant Seed & Claim Plot"
	claim_btn.pressed.connect(_on_claim_plot_pressed)
	claim_tab.add_child(claim_btn)

	# Info text
	var info = Label.new()
	info.text = """
Claiming this plot will:
• Assign you as the original owner
• Assign a neutral faction (if unguilded)
• Start a rank 0 tree
• Enable building placement
• Contribute to weekly rankings"""
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", ACCENT_COLOR)
	claim_tab.add_child(info)


# ═══════════════════════════════════════════════════════════════════════════════
# BUILDINGS TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_buildings_tab() -> void:
	if not buildings_tab:
		return

	# Clear existing content
	for child in buildings_tab.get_children():
		child.queue_free()

	if current_plot.owner_id == "":
		var label = Label.new()
		label.text = "Claim this plot first to place buildings."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		buildings_tab.add_child(label)
		return

	var rank = current_plot.get("tree_rank", 0)
	if rank < 1:
		var label = Label.new()
		label.text = "Upgrade to rank 1 to unlock buildings."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		buildings_tab.add_child(label)
		return

	# Buildings header
	var header = _create_header("🏗️ Building Placement")
	buildings_tab.add_child(header)

	# Slot grid (A-F)
	var slot_label = Label.new()
	slot_label.text = "Available Slots: A B C D E F"
	slot_label.add_theme_color_override("font_color", TEXT_COLOR)
	buildings_tab.add_child(slot_label)

	# Add spacing
	buildings_tab.add_child(HSeparator.new())

	# Building types
	var buildings = [
		{"name": "Campfire", "cost": 5000, "desc": "Free respawn point"},
		{"name": "Warehouse", "cost": 10000, "desc": "Protected resource storage"},
		{"name": "Vendor", "cost": 15000, "desc": "Sells potions and gear"},
		{"name": "Shrine", "cost": 20000, "desc": "Provides buffs"},
		{"name": "Smithy", "cost": 25000, "desc": "Repairs equipment"},
		{"name": "Fortress", "cost": 30000, "desc": "Defensive structure"}
	]

	for building in buildings:
		var hbox = HBoxContainer.new()

		var name_label = Label.new()
		name_label.text = building.name
		name_label.custom_minimum_size = Vector2(120, 0)
		name_label.add_theme_color_override("font_color", HEADER_COLOR)
		hbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = building.desc
		desc_label.custom_minimum_size = Vector2(200, 0)
		desc_label.add_theme_color_override("font_color", TEXT_COLOR)
		hbox.add_child(desc_label)

		var cost_label = Label.new()
		cost_label.text = "%dg" % building.cost
		cost_label.custom_minimum_size = Vector2(60, 0)
		cost_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		hbox.add_child(cost_label)

		var place_btn = Button.new()
		place_btn.text = "Place"
		place_btn.custom_minimum_size = Vector2(80, 0)
		place_btn.pressed.connect(_on_place_building_pressed.bind(building.name.to_lower()))
		hbox.add_child(place_btn)

		buildings_tab.add_child(hbox)


# ═══════════════════════════════════════════════════════════════════════════════
# WAREHOUSE TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_warehouse_tab() -> void:
	if not warehouse_tab:
		return

	# Clear existing content
	for child in warehouse_tab.get_children():
		child.queue_free()

	if current_plot.owner_id == "":
		var label = Label.new()
		label.text = "Claim this plot first to use warehouse."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		warehouse_tab.add_child(label)
		return

	# Warehouse header
	var header = _create_header("📦 Warehouse Storage")
	warehouse_tab.add_child(header)

	# Safe storage (protected)
	var safe_header = Label.new()
	safe_header.text = "🔒 Safe Storage (Protected)"
	safe_header.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	warehouse_tab.add_child(safe_header)

	var safe_label = Label.new()
	safe_label.text = """Gold: %d / 50,000
Wood: %d / 5,000
Stone: %d / 5,000
Gems: %d / 5,000""" % [
		current_plot.get("warehouse_safe_gold", 0),
		current_plot.get("warehouse_safe_wood", 0),
		current_plot.get("warehouse_safe_stone", 0),
		current_plot.get("warehouse_safe_gems", 0)
	]
	safe_label.add_theme_color_override("font_color", TEXT_COLOR)
	warehouse_tab.add_child(safe_label)

	# Add spacing
	warehouse_tab.add_child(HSeparator.new())

	# Overflow storage (vulnerable)
	var overflow_header = Label.new()
	overflow_header.text = "⚠️ Overflow Storage (Vulnerable to raids)"
	overflow_header.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	warehouse_tab.add_child(overflow_header)

	var overflow_label = Label.new()
	overflow_label.text = """Gold: %d
Wood: %d
Stone: %d
Gems: %d""" % [
		current_plot.get("warehouse_overflow_gold", 0),
		current_plot.get("warehouse_overflow_wood", 0),
		current_plot.get("warehouse_overflow_stone", 0),
		current_plot.get("warehouse_overflow_gems", 0)
	]
	overflow_label.add_theme_color_override("font_color", TEXT_COLOR)
	warehouse_tab.add_child(overflow_label)

	# Add spacing
	warehouse_tab.add_child(HSeparator.new())

	# Deposit/Withdraw buttons
	var btn_hbox = HBoxContainer.new()

	var deposit_btn = Button.new()
	deposit_btn.text = "Deposit Resources"
	deposit_btn.pressed.connect(_on_deposit_pressed)
	btn_hbox.add_child(deposit_btn)

	var withdraw_btn = Button.new()
	withdraw_btn.text = "Withdraw Resources"
	withdraw_btn.pressed.connect(_on_withdraw_pressed)
	btn_hbox.add_child(withdraw_btn)

	warehouse_tab.add_child(btn_hbox)


# ═══════════════════════════════════════════════════════════════════════════════
# MINES TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_mines_tab() -> void:
	if not mines_tab:
		return

	# Clear existing content
	for child in mines_tab.get_children():
		child.queue_free()

	if current_plot.owner_id == "":
		var label = Label.new()
		label.text = "Claim this plot first to manage mines."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		mines_tab.add_child(label)
		return

	# Mines header
	var header = _create_header("⛏️ Resource Mines")
	mines_tab.add_child(header)

	var info = Label.new()
	info.text = "Claim mines to generate passive resources.\n30-minute cooldown with diminishing returns (100% → 80% → 64%)."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", ACCENT_COLOR)
	mines_tab.add_child(info)

	# Add spacing
	mines_tab.add_child(HSeparator.new())

	# TODO: Add actual mine list when mine system is implemented
	var placeholder = Label.new()
	placeholder.text = "Mine claiming UI will be added when\nmine spawning system is implemented."
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.add_theme_color_override("font_color", TEXT_COLOR)
	mines_tab.add_child(placeholder)


# ═══════════════════════════════════════════════════════════════════════════════
# BANE TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_bane_tab() -> void:
	if not bane_tab:
		return

	# Clear existing content
	for child in bane_tab.get_children():
		child.queue_free()

	# Bane header
	var header = _create_header("⚔️ Bane System (Siege Warfare)")
	bane_tab.add_child(header)

	var info = Label.new()
	info.text = """Plant a Bane Stone to siege any tree.
Cost: 50,000 gold
Defense: 1-hour window (defender chooses time)
Win: Claim the tree if Bane survives
Lose: Bane destroyed, defender keeps tree"""
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", ACCENT_COLOR)
	bane_tab.add_child(info)

	# Add spacing
	bane_tab.add_child(HSeparator.new())

	# Plant bane button
	var plant_btn = Button.new()
	plant_btn.text = "Plant Bane Stone (50,000g)"
	plant_btn.pressed.connect(_on_plant_bane_pressed)
	bane_tab.add_child(plant_btn)

	# Defense window settings
	if current_plot.owner_id != "":
		bane_tab.add_child(HSeparator.new())

		var defense_header = Label.new()
		defense_header.text = "🛡️ Defense Window Settings"
		defense_header.add_theme_color_override("font_color", HEADER_COLOR)
		bane_tab.add_child(defense_header)

		var current_hour = current_plot.get("defense_window_hour", 20)
		var window_label = Label.new()
		window_label.text = "Defense window: %02d:00 UTC" % current_hour
		window_label.add_theme_color_override("font_color", TEXT_COLOR)
		bane_tab.add_child(window_label)

		var change_btn = Button.new()
		change_btn.text = "Change Defense Time"
		change_btn.pressed.connect(_on_change_defense_window_pressed)
		bane_tab.add_child(change_btn)


# ═══════════════════════════════════════════════════════════════════════════════
# RANKINGS TAB
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_rankings_tab() -> void:
	if not rankings_tab:
		return

	# Clear existing content
	for child in rankings_tab.get_children():
		child.queue_free()

	# Rankings header
	var header = _create_header("🏆 World Tree Rankings")
	rankings_tab.add_child(header)

	# Get current rankings
	var rankings = []
	if chunk_expansion_manager:
		rankings = chunk_expansion_manager.get_rankings()

	if rankings.is_empty():
		var label = Label.new()
		label.text = "No rankings yet. Claim a plot and start contributing!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", TEXT_COLOR)
		rankings_tab.add_child(label)
		return

	# Rankings list
	for i in range(min(10, rankings.size())):
		var ranking = rankings[i]
		var hbox = HBoxContainer.new()

		var rank_label = Label.new()
		rank_label.text = "#%d" % ranking.rank
		rank_label.custom_minimum_size = Vector2(40, 0)
		if ranking.rank == 1:
			rank_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
		else:
			rank_label.add_theme_color_override("font_color", HEADER_COLOR)
		hbox.add_child(rank_label)

		var owner_label = Label.new()
		owner_label.text = ranking.owner_id
		owner_label.custom_minimum_size = Vector2(150, 0)
		owner_label.add_theme_color_override("font_color", TEXT_COLOR)
		hbox.add_child(owner_label)

		var score_label = Label.new()
		score_label.text = "%d pts" % ranking.total_score
		score_label.custom_minimum_size = Vector2(100, 0)
		score_label.add_theme_color_override("font_color", ACCENT_COLOR)
		hbox.add_child(score_label)

		rankings_tab.add_child(hbox)


# ═══════════════════════════════════════════════════════════════════════════════
# BUTTON HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_upgrade_tree_pressed() -> void:
	if not player:
		return

	var chunk_id = current_plot.get("chunk_id", -999)
	print("🌳 Requesting tree upgrade for chunk %d" % chunk_id)
	tree_upgraded.emit(chunk_id, current_plot.get("tree_rank", 0) + 1)

	# Refresh UI
	_refresh_my_tree_tab()


func _on_water_tree_pressed() -> void:
	if not player:
		return

	var chunk_id = current_plot.get("chunk_id", -999)
	print("💧 Watering tree at chunk %d" % chunk_id)

	# TODO: Call API to water tree
	# For now, just show message
	_show_message("Tree watered! +1% growth bonus")

	# Refresh UI
	_refresh_my_tree_tab()


func _on_claim_plot_pressed() -> void:
	if not player:
		return

	var chunk_id = current_plot.get("chunk_id", -999)

	# Check if player has World Tree Seed
	if not _player_has_seed():
		print("❌ Player doesn't have World Tree Seed!")
		# TODO: Show error message in UI
		return

	# Consume the seed from inventory
	if not _consume_seed():
		print("❌ Failed to consume World Tree Seed!")
		return

	print("🌱 Planted World Tree Seed at chunk %d" % chunk_id)

	# Signal the game to claim the plot
	plot_claimed.emit(chunk_id)

	close_ui()


func _on_place_building_pressed(building_type: String) -> void:
	print("🏗️ Placing %s building" % building_type)

	# TODO: Show slot selection dialog
	var slot = "A"  # Placeholder

	var chunk_id = current_plot.get("chunk_id", -999)
	building_placed.emit(chunk_id, building_type, slot)

	_refresh_buildings_tab()


func _on_deposit_pressed() -> void:
	print("📦 Opening deposit dialog")
	# TODO: Show deposit dialog with amount inputs
	_show_message("Deposit dialog coming soon!")


func _on_withdraw_pressed() -> void:
	print("📦 Opening withdraw dialog")
	# TODO: Show withdraw dialog with amount inputs
	_show_message("Withdraw dialog coming soon!")


func _on_plant_bane_pressed() -> void:
	print("⚔️ Opening bane target selection")
	# TODO: Show target selection dialog
	_show_message("Bane planting coming soon!")


func _on_change_defense_window_pressed() -> void:
	print("🛡️ Opening defense window selector")
	# TODO: Show hour selection dialog
	_show_message("Defense window change coming soon!")


# ═══════════════════════════════════════════════════════════════════════════════
# SIGNAL HANDLERS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_plot_claimed(chunk_id: int, player_id: String) -> void:
	if current_plot.get("chunk_id", -999) == chunk_id:
		# Reload plot data
		if chunk_expansion_manager:
			current_plot = chunk_expansion_manager.get_seed_plot(chunk_id)
		_refresh_my_tree_tab()
		_refresh_claim_tab()


func _on_tree_upgraded(chunk_id: int, new_rank: int) -> void:
	if current_plot.get("chunk_id", -999) == chunk_id:
		current_plot.tree_rank = new_rank
		_refresh_my_tree_tab()
		_refresh_buildings_tab()


func _on_building_placed(chunk_id: int, building_type: String) -> void:
	if current_plot.get("chunk_id", -999) == chunk_id:
		_refresh_buildings_tab()


# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _create_header(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADER_COLOR)
	label.add_theme_font_size_override("font_size", 18)
	return label


func _show_message(text: String) -> void:
	# TODO: Show temporary message popup
	print("💬 %s" % text)


func _player_has_seed() -> bool:
	# Check if player has a World Tree Seed in their inventory
	if not player:
		return false

	# Try to get InventorySystem from player
	var inventory = player.get_node_or_null("InventorySystem")
	if not inventory:
		# Fallback: try to get global inventory system
		inventory = get_node_or_null("/root/InventorySystem")

	if inventory and inventory.has_method("has_item"):
		return inventory.has_item("world_tree_seed")

	return false


func _consume_seed() -> bool:
	# Remove World Tree Seed from player's inventory
	if not player:
		return false

	# Try to get InventorySystem from player
	var inventory = player.get_node_or_null("InventorySystem")
	if not inventory:
		# Fallback: try to get global inventory system
		inventory = get_node_or_null("/root/InventorySystem")

	if inventory and inventory.has_method("remove_item"):
		return inventory.remove_item("world_tree_seed", 1)

	return false


func apply_modern_styling() -> void:
	if not main_panel:
		return

	# Apply stone gray theme to panel
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	main_panel.add_theme_stylebox_override("panel", style)
