extends CanvasLayer
class_name LootBodyUI

## Loot Body UI for looting corpses
## Displays aggregated loot from multiple corpses in AOE range
## Uses icon-based grid layout with hoverable tooltips (like inventory)

signal loot_ui_closed()
signal item_looted(item: Dictionary, corpse)
signal all_corpses_looted()

@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var take_all_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton

# Grid container for icon-based loot slots (created dynamically)
var loot_grid: GridContainer = null

var corpses_looted = []  # All corpses in AOE

# UI Style constants (matching InventoryUI)
const SLOT_SIZE = Vector2(52, 52)  # Slightly smaller slots
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)
const GRID_COLUMNS = 3  # 3 columns for compact layout
const MIN_SLOTS = 3  # Always show at least 3 slots

func _ready() -> void:
	print("💀 LootBodyUI initialized")
	hide()

	# Apply stone gray theme to panel
	apply_panel_style()

	# Connect buttons
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	if take_all_button:
		take_all_button.pressed.connect(_on_take_all_pressed)

	# Create loot grid in the LootContainer
	_create_loot_grid()

func apply_panel_style() -> void:
	"""Apply standardized stone gray theme to panel"""
	var panel = get_node_or_null("Panel")
	if not panel:
		return

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.95)  # Dark stone gray
	style.border_color = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

func _create_loot_grid() -> void:
	"""Get reference to the loot grid from scene"""
	loot_grid = get_node_or_null("Panel/MarginContainer/VBoxContainer/LootGrid")
	if loot_grid:
		loot_grid.columns = GRID_COLUMNS

func _input(event: InputEvent) -> void:
	# Allow ESC to close or F to take all items
	if visible and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_ui()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_on_take_all_pressed()
			get_viewport().set_input_as_handled()

func open_loot_ui(primary_corpse, nearby_corpses: Array) -> void:
	"""Open the loot UI with aggregated loot from all nearby corpses"""
	# Combine all corpses
	corpses_looted = [primary_corpse] + nearby_corpses

	# Hide [F] Loot prompts on all corpses while UI is open
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			corpse.loot_ui_open = true  # Set flag to prevent prompt from showing
			if corpse.loot_prompt:
				corpse.loot_prompt.visible = false
			print("💀 Hiding loot prompt and setting UI open flag for corpse")

	var corpse_count = corpses_looted.size()
	print("💀 Opening loot body UI with %d corpse(s)" % corpse_count)

	populate_loot_grid()

	# Auto-close if nothing to loot (no items and no gold)
	var total_items = 0
	var total_gold = 0
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			total_items += corpse.corpse_loot.size()
			total_gold += corpse.corpse_gold

	if total_items == 0 and total_gold == 0:
		print("💀 No items or gold to loot - auto-closing")
		for corpse in corpses_looted:
			if is_instance_valid(corpse):
				corpse.check_if_looted_empty()
		await get_tree().create_timer(0.5).timeout
		close_ui()
		return

	show()

func close_ui() -> void:
	"""Close the loot UI"""
	# Clear loot_ui_open flag on all corpses
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			corpse.loot_ui_open = false

	hide()
	loot_ui_closed.emit()
	print("💀 Loot body UI closed")

	# Prompts will auto-show again via update_loot_proximity if corpses still have loot

func populate_loot_grid() -> void:
	"""Populate the loot grid with icon slots from all corpses (including gold)"""
	if not loot_grid:
		_create_loot_grid()
	if not loot_grid:
		return

	# Clear existing items
	for child in loot_grid.get_children():
		child.queue_free()

	var total_slots = 0

	# First, add gold slots for each corpse that has gold
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue
		if corpse.corpse_gold > 0:
			var gold_slot = create_gold_slot(corpse.corpse_gold, corpse)
			loot_grid.add_child(gold_slot)
			total_slots += 1

	# Then add item slots
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue

		for item in corpse.corpse_loot:
			if item:  # Skip null items (already looted)
				var slot = create_loot_slot(item, corpse)
				loot_grid.add_child(slot)
				total_slots += 1

	# Add empty slots to reach minimum (always show at least MIN_SLOTS)
	while total_slots < MIN_SLOTS:
		var empty_slot = create_empty_slot()
		loot_grid.add_child(empty_slot)
		total_slots += 1

	# If everything was looted, close after brief delay
	var actual_loot_count = 0
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			actual_loot_count += corpse.corpse_loot.size()
			if corpse.corpse_gold > 0:
				actual_loot_count += 1

	if actual_loot_count == 0:
		# Check if corpses are fully empty
		for corpse in corpses_looted:
			if is_instance_valid(corpse):
				corpse.check_if_looted_empty()

		# Close after showing empty state
		await get_tree().create_timer(0.5).timeout
		close_ui()

func create_loot_slot(item: Dictionary, source_corpse) -> Control:
	"""Create an icon-based slot for a loot item (click to loot)"""
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP

	# Store item data and corpse reference
	slot_control.set_meta("item_data", item)
	slot_control.set_meta("source_corpse", source_corpse)

	# Get rarity for border color
	var rarity = item.get("rarity", "Common")
	var rarity_color = get_rarity_color(rarity)

	# Add panel for styling with rarity glow
	var panel = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(SLOT_BG, rarity_color, 3, true)
	panel.add_theme_stylebox_override("panel", slot_style)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# Add icon texture rect
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)

	# Try to get icon from ItemIconGenerator
	if ItemIconGenerator:
		var icon_texture = ItemIconGenerator.get_item_icon(item)
		if icon_texture:
			icon.texture = icon_texture

	# Fallback label if no icon
	var label = Label.new()
	label.name = "ItemLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = (icon.texture == null)
	if label.visible:
		label.text = item.get("name", "???")
	center.add_child(label)

	# Build tooltip with item info
	var item_name = item.get("name", "Unknown")
	var tooltip = "[%s] %s\n" % [rarity, item_name]
	var desc = item.get("description", "")
	if desc:
		tooltip += desc + "\n"

	if item.get("type") == "weapon":
		if item.has("base_damage"):
			tooltip += "Damage: +%.1f\n" % item.get("base_damage", 0)
		if item.has("attack_speed_bonus"):
			var speed_bonus = item.get("attack_speed_bonus", 0.0)
			if speed_bonus != 0:
				tooltip += "Attack Speed: %+.1f%%\n" % (speed_bonus * 100)
		if item.has("crit_chance_bonus"):
			var crit_bonus = item.get("crit_chance_bonus", 0.0)
			if crit_bonus != 0:
				tooltip += "Crit Chance: +%.1f%%\n" % (crit_bonus * 100)

	if item.has("defense"):
		tooltip += "Defense: +%d\n" % item.get("defense", 0)

	if item.has("value"):
		tooltip += "Value: 🪙 %d\n" % item.get("value", 0)

	tooltip += "\nClick to loot"
	slot_control.tooltip_text = tooltip

	# Connect click to loot
	slot_control.gui_input.connect(_on_loot_slot_input.bind(slot_control))

	return slot_control

func create_empty_slot() -> Control:
	"""Create an empty placeholder slot"""
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Add panel for styling (dimmed empty slot)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(Color(0.05, 0.05, 0.07, 0.5), BORDER_INNER, 1, false)
	panel.add_theme_stylebox_override("panel", slot_style)

	return slot_control

func create_gold_slot(gold_amount: int, source_corpse) -> Control:
	"""Create a clickable gold slot icon (click to loot gold)"""
	var slot_control = Control.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP

	# Store gold data and corpse reference
	slot_control.set_meta("is_gold", true)
	slot_control.set_meta("gold_amount", gold_amount)
	slot_control.set_meta("source_corpse", source_corpse)

	# Gold uses a warm golden border color
	var gold_border_color = Color(1.0, 0.85, 0.0, 1.0)  # Bright gold

	# Add panel for styling with gold glow
	var panel = PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style = create_slot_style(SLOT_BG, gold_border_color, 3, true)
	panel.add_theme_stylebox_override("panel", slot_style)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# Gold icon label (using emoji like inventory/shop)
	var gold_icon = Label.new()
	gold_icon.name = "GoldIcon"
	gold_icon.text = "🪙"
	gold_icon.add_theme_font_size_override("font_size", 28)
	gold_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(gold_icon)

	# Build tooltip
	var tooltip = "Gold: %d\n\nClick to loot" % gold_amount
	slot_control.tooltip_text = tooltip

	# Connect click to loot gold
	slot_control.gui_input.connect(_on_gold_slot_input.bind(slot_control))

	return slot_control

func _on_gold_slot_input(event: InputEvent, slot: Control) -> void:
	"""Handle click on gold slot to loot the gold"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var gold_amount = slot.get_meta("gold_amount")
		var corpse = slot.get_meta("source_corpse")
		if gold_amount > 0 and is_instance_valid(corpse):
			loot_gold(corpse, gold_amount)

func loot_gold(corpse, gold_amount: int) -> void:
	"""Loot gold from a corpse"""
	if not is_instance_valid(corpse):
		print("❌ Corpse no longer valid")
		populate_loot_grid()
		return

	if corpse.corpse_gold <= 0:
		print("❌ No gold left on corpse")
		populate_loot_grid()
		return

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()

	# In multiplayer, request gold loot through server
	if is_multiplayer and network_enemy_mgr and corpse.network_id > 0:
		network_enemy_mgr.request_loot_gold.rpc_id(1, corpse.network_id)
		# Server will handle gold award and broadcast
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(self):
			return
		populate_loot_grid()
	else:
		# Single player - award directly
		CharacterStats.add_gold(corpse.corpse_gold)
		print("💰 Looted %d gold" % corpse.corpse_gold)

		# Play gold loot sound
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -10.0)

		corpse.corpse_gold = 0

		# Check if corpse is now empty
		corpse.check_if_looted_empty()

		# Refresh the grid
		populate_loot_grid()

func create_slot_style(bg_color: Color, border_color: Color = BORDER_COLOR, border_width: int = 2, use_glow: bool = false) -> StyleBoxFlat:
	"""Create style for loot slots (matching InventoryUI)"""
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	if use_glow and border_color != BORDER_INNER:
		style.shadow_size = 3
		style.shadow_color = Color(border_color.r, border_color.g, border_color.b, 0.3)
	else:
		style.shadow_size = 3
		style.shadow_color = BORDER_INNER

	return style

func _on_loot_slot_input(event: InputEvent, slot: Control) -> void:
	"""Handle click on loot slot to loot the item"""
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var item = slot.get_meta("item_data")
		var corpse = slot.get_meta("source_corpse")
		if item and is_instance_valid(corpse):
			loot_item(corpse, item)

func get_rarity_color(rarity: String) -> Color:
	"""Get color based on item rarity"""
	match rarity.to_upper():
		"COMMON":
			return Color(0.6, 0.6, 0.6, 0.9)
		"UNCOMMON":
			return Color(0.4, 0.8, 0.4, 1.0)
		"RARE":
			return Color(0.4, 0.5, 0.9, 1.0)
		"EPIC":
			return Color(0.7, 0.4, 0.9, 1.0)
		"LEGENDARY":
			return Color(0.9, 0.6, 0.2, 1.0)
		_:
			return BORDER_INNER

func loot_item(corpse, item: Dictionary) -> void:
	"""Loot a specific item from a corpse"""
	if not is_instance_valid(corpse):
		print("❌ Corpse no longer valid")
		populate_loot_grid()
		return

	# Find item index in corpse loot by matching properties (not reference)
	# This is needed because items may have been duplicated via RPC serialization
	var item_index = -1
	var item_name = item.get("name", "")
	var item_type = item.get("type", "")
	var item_rarity = item.get("rarity", "")

	print("🔍 Looking for item: name='%s' type='%s' rarity='%s'" % [item_name, item_type, item_rarity])
	print("🔍 Corpse has %d items in loot array" % corpse.corpse_loot.size())

	for i in range(corpse.corpse_loot.size()):
		var corpse_item = corpse.corpse_loot[i]
		if corpse_item:
			print("   [%d] name='%s' type='%s' rarity='%s'" % [
				i,
				corpse_item.get("name", ""),
				corpse_item.get("type", ""),
				corpse_item.get("rarity", "")
			])
		# Match by name only to be more lenient with sync issues
		if corpse_item and corpse_item.get("name", "") == item_name:
			item_index = i
			break

	if item_index == -1:
		print("❌ Item '%s' no longer in corpse loot (corpse has %d items)" % [item_name, corpse.corpse_loot.size()])
		populate_loot_grid()
		return

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()

	# In multiplayer, request item loot through server
	if is_multiplayer and network_enemy_mgr and corpse.network_id > 0:
		network_enemy_mgr.request_loot_item.rpc_id(1, corpse.network_id, item_index)
		# Server will handle inventory add and broadcast removal
		# Refresh list after small delay to allow RPC to process
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(self):
			return  # UI was closed during await
		populate_loot_grid()
	else:
		# Single player - handle directly
		if InventorySystem.add_item(item):
			print("✨ Looted: %s from corpse" % item_name)
			item_looted.emit(item, corpse)

			# Show notification and play pickup sound
			if NotificationManager and is_instance_valid(NotificationManager):
				NotificationManager.notify_item_added(item_name, 1, item_rarity)

			# Remove from corpse's loot array
			corpse.corpse_loot.erase(item)

			# Check if corpse is now empty
			corpse.check_if_looted_empty()

			# Refresh the list
			populate_loot_grid()
		else:
			print("❌ Inventory full! Cannot loot %s" % item_name)

func _on_take_all_pressed() -> void:
	"""Take all gold and items from all corpses"""
	var looted_count = 0
	var total_gold = 0

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()

	# First, loot all gold from all corpses
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue
		if corpse.corpse_gold > 0:
			total_gold += corpse.corpse_gold
			if is_multiplayer and network_enemy_mgr and corpse.network_id > 0:
				network_enemy_mgr.request_loot_gold.rpc_id(1, corpse.network_id)
			else:
				CharacterStats.add_gold(corpse.corpse_gold)
				corpse.corpse_gold = 0

	# Play gold sound if we looted gold
	if total_gold > 0 and not is_multiplayer:
		print("💰 Looted %d total gold" % total_gold)
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -10.0)

	# Collect all items to loot (with their indices for network sync)
	var all_items_to_loot: Array = []
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue
		for i in range(corpse.corpse_loot.size()):
			var item = corpse.corpse_loot[i]
			if item:
				all_items_to_loot.append({"item": item, "corpse": corpse, "index": i})

	# Loot items - in multiplayer we request each from server
	for entry in all_items_to_loot:
		var item = entry["item"]
		var corpse = entry["corpse"]

		if not is_instance_valid(corpse):
			continue

		if is_multiplayer and network_enemy_mgr and corpse.network_id > 0:
			# In multiplayer, always request from index 0 since items shift after each removal
			network_enemy_mgr.request_loot_item.rpc_id(1, corpse.network_id, 0)
			looted_count += 1
			# Small delay to allow server to process and broadcast
			await get_tree().create_timer(0.15).timeout
			if not is_instance_valid(self):
				return  # UI was closed during await
		else:
			# Single player - handle directly
			if InventorySystem.add_item(item):
				var item_name = item.get("name", "Unknown")
				var item_rarity = item.get("rarity", "Common")

				looted_count += 1
				item_looted.emit(item, corpse)
				corpse.corpse_loot.erase(item)

				# Show notification and play pickup sound
				if NotificationManager and is_instance_valid(NotificationManager):
					NotificationManager.notify_item_added(item_name, 1, item_rarity)

				# Small delay between each notification for cascade effect
				await get_tree().create_timer(0.12).timeout
				if not is_instance_valid(self):
					return  # UI was closed during await
			else:
				print("❌ Inventory full! Looted %d items" % looted_count)
				# Check which corpses are empty
				for c in corpses_looted:
					if is_instance_valid(c):
						c.check_if_looted_empty()
				populate_loot_grid()
				return

	# Check all corpses if empty
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			corpse.check_if_looted_empty()

	if looted_count > 0 or total_gold > 0:
		print("✨ Looted all: %d gold, %d items from %d corpse(s)" % [total_gold, looted_count, corpses_looted.size()])
		all_corpses_looted.emit()

	# Refresh and potentially close
	populate_loot_grid()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_ui()
