extends CanvasLayer
## Blacksmith Forge UI - PLAYTEST ITEM CLAIMING
## This is COMPLETELY ISOLATED from the production NFT forge system in Armory.gd
## Shows ALL ForgeItemDB items for one-time claiming during playtesting

signal closed

# UI references
var _content_container: Control = null
var _item_grid: GridContainer = null

# Constants from UITheme
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.95)
const BORDER_GLOW = Color(0.0, 0.75, 0.85)
const SHADOW_GLOW = Color(0.0, 0.75, 0.85, 0.3)
const TEXT_PRIMARY = Color(0.92, 0.92, 0.94)
const TEXT_SECONDARY = Color(0.75, 0.78, 0.82)
const ASHBANE_ACCENT = Color(0.0, 0.75, 0.85)

const RARITY_COLORS = {
	"common": Color(0.6, 0.6, 0.6),
	"uncommon": Color(0.4, 0.8, 0.4),
	"rare": Color(0.3, 0.5, 0.9),
	"epic": Color(0.6, 0.2, 0.8),
	"legendary": Color(1.0, 0.5, 0.1)
}

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_build_ui()

func _build_forge_item_tooltip(item_id: String, is_claimed: bool) -> String:
	"""Build a detailed tooltip for a forge item"""
	var forge_db = ForgeItemDB.get_item_by_id(item_id)
	if forge_db.is_empty():
		return item_id

	var lines = []

	# Item name
	var item_name = forge_db.get("item_name", "Unknown")
	lines.append(item_name)
	lines.append("─────────────────")

	# Rarity and type
	var rarity = ForgeItemDB.ItemRarity.keys()[forge_db.get("rarity", 0)].capitalize()
	var item_type_enum = forge_db.get("item_type", 0)
	var item_type = ForgeItemDB.ItemType.keys()[item_type_enum].replace("_", " ").capitalize()
	lines.append("%s %s" % [rarity, item_type])

	# Weapon type and damage
	if item_type_enum == ForgeItemDB.ItemType.WEAPON:
		var weapon_type = forge_db.get("weapon_type", "")
		if weapon_type != "":
			lines.append("Type:  %s" % weapon_type.capitalize())

		var dmg_min = forge_db.get("base_damage_min", 0)
		var dmg_max = forge_db.get("base_damage_max", 0)
		if dmg_min > 0 or dmg_max > 0:
			lines.append("Damage:  %d-%d" % [dmg_min, dmg_max])

		var attack_speed = forge_db.get("attack_speed", "")
		if attack_speed != "":
			lines.append("Speed:  %s" % str(attack_speed).capitalize())

	# Defense for armor
	var defense = forge_db.get("defense", 0)
	if defense > 0:
		lines.append("Defense:  +%d" % defense)

	# HP bonus
	var hp_bonus = forge_db.get("hp_bonus", 0)
	if hp_bonus > 0:
		lines.append("HP:  +%d" % hp_bonus)

	# Stat bonuses
	var stat_bonuses = forge_db.get("stat_bonuses", {})
	if stat_bonuses is Dictionary:
		var stat_parts = []
		for stat_key in ["str", "agi", "dex", "int", "wis", "vit"]:
			var val = stat_bonuses.get(stat_key, 0)
			if val > 0:
				stat_parts.append("+%d %s" % [val, stat_key.to_upper()])
		if stat_parts.size() > 0:
			lines.append("Stats:  %s" % ", ".join(stat_parts))

	# Abilities - use ForgeItemDB lookup for proper names
	if ForgeItemDB.has_abilities(item_id):
		var passive_name = ForgeItemDB.get_passive_ability_name(item_id)
		var passive_desc = ForgeItemDB.get_passive_ability_description(item_id)
		var active_name = ForgeItemDB.get_active_ability_name(item_id)
		var active_desc = ForgeItemDB.get_active_ability_description(item_id)

		if passive_name != "":
			lines.append("Passive:  %s" % passive_name)
			if passive_desc != "":
				lines.append("   %s" % passive_desc)

		if active_name != "":
			lines.append("Active:  %s" % active_name)
			if active_desc != "":
				lines.append("   %s" % active_desc)
	else:
		# Fallback to raw effects
		var effects = forge_db.get("effects", [])
		if effects is Array and effects.size() > 0:
			var effect_names = []
			for e in effects:
				effect_names.append(str(e).replace("_", " ").capitalize())
			lines.append("Effects:  %s" % ", ".join(effect_names))

	# Lore/description
	var lore = forge_db.get("lore", forge_db.get("description", ""))
	if lore != "":
		lines.append("")
		lines.append("\"%s\"" % lore)

	# Source info
	lines.append("")
	var achievement_name = forge_db.get("achievement_name", "")
	if achievement_name != "":
		lines.append("Achievement:  %s" % achievement_name)

	# Claimed status
	lines.append("─────────────────")
	if is_claimed:
		lines.append("✓ CLAIMED")
	else:
		lines.append("Click to Claim")

	return "\n".join(lines)

func _build_ui() -> void:
	"""Build the blacksmith forge UI"""
	# Background overlay
	var bg = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Center wrapper to keep panel centered on viewport
	var center = CenterContainer.new()
	center.name = "CenterWrapper"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)

	# Main panel
	var panel = PanelContainer.new()
	panel.name = "MainPanel"
	panel.custom_minimum_size = Vector2(900, 640)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(panel)

	# Panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_color = BORDER_GLOW
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_size = 20
	panel_style.shadow_color = SHADOW_GLOW
	panel.add_theme_stylebox_override("panel", panel_style)

	# Content
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vbox.add_child(header_row)

	var forge_icon = Label.new()
	forge_icon.text = "⚒"
	forge_icon.add_theme_font_size_override("font_size", 32)
	forge_icon.add_theme_color_override("font_color", ASHBANE_ACCENT)
	header_row.add_child(forge_icon)

	var title = Label.new()
	title.text = "BLACKSMITH FORGE - PLAYTEST"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEXT_PRIMARY)
	header_row.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(_on_close_pressed)
	header_row.add_child(close_btn)

	# Info label
	var info = Label.new()
	info.text = "Select any item to claim it once (isolated from NFT system)"
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", TEXT_SECONDARY)
	vbox.add_child(info)

	# Stats row
	var stats_row = HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stats_row)

	var claimed_label = Label.new()
	claimed_label.name = "ClaimedLabel"
	claimed_label.add_theme_font_size_override("font_size", 16)
	claimed_label.add_theme_color_override("font_color", TEXT_SECONDARY)
	stats_row.add_child(claimed_label)

	# Scrollable item grid
	var scroll = ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP  # ensure wheel events scroll
	vbox.add_child(scroll)

	var grid_margin = MarginContainer.new()
	grid_margin.add_theme_constant_override("margin_left", 10)
	grid_margin.add_theme_constant_override("margin_right", 10)
	grid_margin.add_theme_constant_override("margin_top", 10)
	grid_margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(grid_margin)

	_item_grid = GridContainer.new()
	_item_grid.columns = 10
	_item_grid.add_theme_constant_override("h_separation", 6)
	_item_grid.add_theme_constant_override("v_separation", 6)
	grid_margin.add_child(_item_grid)

	# Populate grid
	_refresh_items()

func _refresh_items() -> void:
	"""Refresh the item grid"""
	if not _item_grid:
		return

	# Clear existing
	for child in _item_grid.get_children():
		child.queue_free()

	# Build quick lookup of icons from ForgeItemDB (sprites.icon already normalized)
	var icon_lookup: Dictionary = {}
	for key in ForgeItemDB.FORGE_ITEMS.keys():
		var item_dict: Dictionary = ForgeItemDB.FORGE_ITEMS[key]
		var item_id = item_dict.get("item_id", "")
		if item_id == "":
			continue
		var icon_path = ""
		var sprites = item_dict.get("sprites")
		if sprites is Dictionary:
			icon_path = sprites.get("icon", "")
		if icon_path == "" and item_dict.has("icon"):
			icon_path = item_dict.get("icon")
		icon_lookup[item_id] = icon_path

	# Get all items from ForgeItemDB
	var all_items = []
	for achievement_key in ForgeItemDB.FORGE_ITEMS.keys():
		var forge_db = ForgeItemDB.FORGE_ITEMS[achievement_key]
		var item_id = forge_db.get("item_id", "")
		if item_id == "":
			continue

		all_items.append({
			"item_id": item_id,
			"name": forge_db.get("item_name", "Unknown"),
			"rarity": ForgeItemDB.ItemRarity.keys()[forge_db.get("rarity", 0)].to_lower(),
			"icon_path": icon_lookup.get(item_id, ""),
		})

	# Sort by rarity
	all_items.sort_custom(func(a, b): return _rarity_value(a.rarity) < _rarity_value(b.rarity))

	# Count claimed
	var claimed_count = 0
	var unclaimed_count = 0

	# Create cards
	for item in all_items:
		var is_claimed = CharacterStats.has_claimed_playtest_item(item.item_id)
		if is_claimed:
			claimed_count += 1
		else:
			unclaimed_count += 1

		var card = _create_item_card(item, is_claimed)
		_item_grid.add_child(card)

	# Update stats
	var stats_label = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/HBoxContainer/ClaimedLabel")
	if stats_label:
		stats_label.text = "Claimed: %d / %d" % [claimed_count, all_items.size()]

func _rarity_value(rarity: String) -> int:
	match rarity:
		"legendary": return 0
		"epic": return 1
		"rare": return 2
		"uncommon": return 3
		"common": return 4
		_: return 5

func _create_item_card(item: Dictionary, is_claimed: bool) -> Control:
	"""Create a simple item card"""
	const CARD_SIZE = 54

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_SIZE, CARD_SIZE)
	card.mouse_filter = Control.MOUSE_FILTER_STOP if not is_claimed else Control.MOUSE_FILTER_IGNORE

	var rarity_color = RARITY_COLORS.get(item.rarity, Color.GRAY)

	# Card style
	var style = StyleBoxFlat.new()
	if is_claimed:
		style.bg_color = Color(0.03, 0.03, 0.04, 1.0)
		style.border_color = Color(0.15, 0.15, 0.18)
	else:
		style.bg_color = Color(0.06, 0.06, 0.08, 1.0)
		style.border_color = rarity_color
		style.shadow_size = 6
		style.shadow_color = Color(rarity_color.r, rarity_color.g, rarity_color.b, 0.4)

	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	card.add_theme_stylebox_override("panel", style)

	# Store item data
	card.set_meta("item_data", item)
	card.set_meta("is_claimed", is_claimed)

	# Icon - determine subdirectory based on item type from ForgeItemDB
	var resolved_icon = ""
	# Prefer path from ForgeItemDB (already normalized to res:// if present)
	if item.has("icon_path") and item.icon_path != "":
		resolved_icon = item.icon_path
	else:
		# Fallback: Try to determine correct subfolder from ForgeItemDB item type
		var forged_item = ForgeItemDB.get_item_by_id(item.item_id)
		var item_type_enum = forged_item.get("item_type", ForgeItemDB.ItemType.WEAPON)
		var subfolder = "weapons"  # Default
		match item_type_enum:
			ForgeItemDB.ItemType.WEAPON:
				subfolder = "weapons"
			ForgeItemDB.ItemType.ARMOR_HEAD, ForgeItemDB.ItemType.ARMOR_CHEST, ForgeItemDB.ItemType.ARMOR_ARMS, ForgeItemDB.ItemType.ARMOR_LEGS, ForgeItemDB.ItemType.ARMOR_HANDS, ForgeItemDB.ItemType.ARMOR_FEET:
				subfolder = "armor"
			ForgeItemDB.ItemType.SHIELD:
				subfolder = "shields"
			ForgeItemDB.ItemType.CAPE:
				subfolder = "capes"
			ForgeItemDB.ItemType.ACCESSORY, ForgeItemDB.ItemType.RING, ForgeItemDB.ItemType.AMULET:
				subfolder = "accessories"
			ForgeItemDB.ItemType.TOOL:
				subfolder = "tools"
		resolved_icon = "res://assets/icons/forged/%s/%s.png" % [subfolder, item.item_id]

	# Build enhanced path with subfolder too
	var enhanced_icon_path = ""
	if resolved_icon.begins_with("res://assets/icons/forged/"):
		# Extract subfolder from resolved path and use for enhanced
		var path_parts = resolved_icon.replace("res://assets/icons/forged/", "").split("/")
		if path_parts.size() >= 2:
			enhanced_icon_path = "res://assets/icons/enhanced/forged/%s/%s" % [path_parts[0], path_parts[1]]
		else:
			enhanced_icon_path = "res://assets/icons/enhanced/forged/" + item.item_id + ".png"
	else:
		enhanced_icon_path = "res://assets/icons/enhanced/forged/" + item.item_id + ".png"

	# Try enhanced icon first, then resolved icon
	var texture = null
	if ResourceLoader.exists(enhanced_icon_path):
		texture = load(enhanced_icon_path)
	elif resolved_icon != "" and ResourceLoader.exists(resolved_icon):
		texture = load(resolved_icon)
	elif ResourceLoader.exists(resolved_icon + ".import"):
		texture = load(resolved_icon)  # .import exists, load base path
	else:
		print("[BlacksmithForge] Missing icon for %s (path tried: %s)" % [item.item_id, resolved_icon])

	if texture:
		var icon = TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if is_claimed:
			icon.modulate = Color(0.3, 0.3, 0.3, 0.5)
		card.add_child(icon)

	# Claimed checkmark
	if is_claimed:
		var check = Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 24)
		check.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		check.position = Vector2(CARD_SIZE - 20, CARD_SIZE - 24)
		card.add_child(check)

	# Click handler
	if not is_claimed:
		card.gui_input.connect(_on_card_clicked.bind(card))

	# Detailed tooltip
	card.tooltip_text = _build_forge_item_tooltip(item.item_id, is_claimed)

	return card

func _on_card_clicked(event: InputEvent, card: PanelContainer) -> void:
	"""Handle card click"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var item_data = card.get_meta("item_data", {})
		var item_id = item_data.get("item_id", "")

		if item_id == "":
			return

		# Try to claim
		if not CharacterStats.claim_playtest_item(item_id):
			print("[BlacksmithForge] Item already claimed: %s" % item_id)
			return

		# Play sound
		if SoundManager:
			SoundManager.play_button_click_sound(-3.0)

		# Get item from ForgeItemDB
		var forge_db = ForgeItemDB.get_item_by_id(item_id)
		if forge_db.is_empty():
			print("[BlacksmithForge] Item not found in ForgeItemDB: %s" % item_id)
			return

		# Convert to forged item format
		var forged_item = {
			"item_id": item_id,
			"item_name": forge_db.get("item_name", "Unknown"),
			"item_type": ForgeItemDB.ItemType.keys()[forge_db.get("item_type", 0)].to_lower(),
			"item_rarity": ForgeItemDB.ItemRarity.keys()[forge_db.get("rarity", 0)].to_lower(),
			"description": forge_db.get("description", ""),
			"effect_name": forge_db.get("effects", ["standard_particles"])[0] if forge_db.get("effects", []).size() > 0 else "standard_particles",
		}

		# Use ForgeItemManager to convert to inventory format
		var inventory_item = ForgeItemManager._convert_to_inventory_format(forged_item)
		if inventory_item.is_empty():
			print("[BlacksmithForge] Failed to convert to inventory format")
			return

		# Add to inventory
		if InventorySystem.add_item(inventory_item):
			print("[BlacksmithForge] ✅ Claimed: %s" % inventory_item.get("name"))
			# Use NotificationManager for clean floating notification
			var item_name = inventory_item.get("name", "Item")
			var item_rarity = inventory_item.get("rarity", "COMMON")
			NotificationManager.notify_item_added(item_name, 1, item_rarity)
			_refresh_items()
		else:
			print("[BlacksmithForge] Failed to add to inventory (full?)")
			NotificationManager.show_notification("Inventory full!", "error")

func _on_close_pressed() -> void:
	"""Handle close button"""
	if SoundManager:
		SoundManager.play_button_click_sound(-6.0)
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	"""Handle ESC key"""
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
