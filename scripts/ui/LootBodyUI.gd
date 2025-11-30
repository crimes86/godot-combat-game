extends CanvasLayer
class_name LootBodyUI

## Loot Body UI for looting corpses
## Displays aggregated loot from multiple corpses in AOE range
## Similar to ChestLootUI but with corpse-specific theming

signal loot_ui_closed()
signal item_looted(item: Dictionary, corpse)
signal all_corpses_looted()

@onready var loot_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/LootContainer/LootList
@onready var close_button: Button = $Panel/MarginContainer/VBoxContainer/Header/CloseButton
@onready var take_all_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/TakeAllButton
@onready var header_label: Label = $Panel/MarginContainer/VBoxContainer/Header/TitleLabel
@onready var gold_label: Label = $Panel/MarginContainer/VBoxContainer/Header/GoldLabel

var corpses_looted = []  # All corpses in AOE
var total_gold_collected: int = 0

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

	# Calculate total gold from all corpses and request loot via network
	total_gold_collected = 0
	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()

	for corpse in corpses_looted:
		if is_instance_valid(corpse) and corpse.corpse_gold > 0:
			total_gold_collected += corpse.corpse_gold

			# In multiplayer, request gold loot through server
			if is_multiplayer and network_enemy_mgr and corpse.network_id > 0:
				network_enemy_mgr.request_loot_gold.rpc_id(1, corpse.network_id)
			else:
				# Single player - award directly
				CharacterStats.add_gold(corpse.corpse_gold)
				corpse.corpse_gold = 0

	# Play gold loot sound if we got gold (in multiplayer, sound plays via RPC callback)
	if total_gold_collected > 0 and not is_multiplayer:
		print("💰 Auto-looted %d gold when opening UI" % total_gold_collected)
		var sound_manager = get_node_or_null("/root/SoundManager")
		if sound_manager:
			sound_manager.play_sound_2d(sound_manager.SoundType.GOLD_LOOT, -10.0)

	# Update header
	var corpse_count = corpses_looted.size()
	if header_label:
		if corpse_count == 1:
			header_label.text = "Looting Body"
		else:
			header_label.text = "Looting %d Bodies" % corpse_count

	# Show gold label with total (showing what was just awarded)
	if gold_label:
		if total_gold_collected > 0:
			gold_label.text = "Looted: %d Gold" % total_gold_collected
			gold_label.visible = true
		else:
			gold_label.visible = false

	print("💀 Opening loot body UI with %d corpse(s), %d gold auto-awarded" % [corpse_count, total_gold_collected])

	populate_loot_list()

	# Auto-close if no items left after gold is looted
	var total_items = 0
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			total_items += corpse.corpse_loot.size()

	if total_items == 0:
		print("💀 No items to loot - auto-closing")
		# Check if all corpses are now empty (gold was looted, no items)
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

func populate_loot_list() -> void:
	"""Populate the loot list with items from all corpses"""
	if not loot_list:
		return

	# Clear existing items
	for child in loot_list.get_children():
		child.queue_free()

	# Collect all items from all corpses
	var total_items = 0
	for corpse in corpses_looted:
		if not is_instance_valid(corpse):
			continue

		for item in corpse.corpse_loot:
			if item:  # Skip null items (already looted)
				var item_row = create_loot_item_row(
					item.get("name", "Unknown"),
					item.get("description", ""),
					item.get("value", 0),
					item.get("rarity", "Common"),
					corpse,
					item
				)
				loot_list.add_child(item_row)
				total_items += 1

	# Show message if all items looted
	if total_items == 0:
		var empty_label = Label.new()
		empty_label.text = "No loot remaining"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		loot_list.add_child(empty_label)

		# Check if corpses are fully empty (no gold, no items)
		for corpse in corpses_looted:
			if is_instance_valid(corpse):
				corpse.check_if_looted_empty()

		# Close after showing empty message
		await get_tree().create_timer(1.0).timeout
		close_ui()

func create_loot_item_row(item_name: String, description: String, value: int, rarity: String, source_corpse, item_data: Dictionary) -> PanelContainer:
	"""Create a row for a loot item with corpse-themed styling"""
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 70)

	# Add background with steel gray styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.12, 0.6)  # Dark stone
	style.border_width_left = 4

	# Border color based on rarity
	var border_color = get_rarity_color(rarity)
	style.border_color = border_color

	style.corner_radius_top_left = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Left side - Item info
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	# Item name (with rarity color)
	var name_label = Label.new()
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", border_color)
	vbox.add_child(name_label)

	# Description
	var desc_label = Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(desc_label)

	# Value
	var value_label = Label.new()
	value_label.text = "Value: %d gold" % value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(value_label)

	# Right side - Loot button
	var loot_button = Button.new()
	loot_button.text = "LOOT"
	loot_button.custom_minimum_size = Vector2(80, 50)
	loot_button.pressed.connect(func(): loot_item(source_corpse, item_data))
	hbox.add_child(loot_button)

	return panel

func get_rarity_color(rarity: String) -> Color:
	"""Get color based on item rarity"""
	match rarity:
		"Common":
			return Color(0.7, 0.7, 0.7)  # Gray
		"Uncommon":
			return Color(0.2, 1.0, 0.2)  # Green
		"Rare":
			return Color(0.3, 0.5, 1.0)  # Blue
		"Epic":
			return Color(0.7, 0.3, 1.0)  # Purple
		"Legendary":
			return Color(1.0, 0.6, 0.2)  # Orange
		_:
			return Color(1.0, 1.0, 1.0)  # White fallback

func loot_item(corpse, item: Dictionary) -> void:
	"""Loot a specific item from a corpse"""
	if not is_instance_valid(corpse):
		print("❌ Corpse no longer valid")
		populate_loot_list()
		return

	# Find item index in corpse loot by matching properties (not reference)
	# This is needed because items may have been duplicated via RPC serialization
	var item_index = -1
	var item_name = item.get("name", "")
	var item_type = item.get("type", "")
	var item_rarity = item.get("rarity", "")

	for i in range(corpse.corpse_loot.size()):
		var corpse_item = corpse.corpse_loot[i]
		if corpse_item and corpse_item.get("name", "") == item_name and \
		   corpse_item.get("type", "") == item_type and \
		   corpse_item.get("rarity", "") == item_rarity:
			item_index = i
			break

	if item_index == -1:
		print("❌ Item '%s' no longer in corpse loot (corpse has %d items)" % [item_name, corpse.corpse_loot.size()])
		populate_loot_list()
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
		populate_loot_list()
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
			populate_loot_list()
		else:
			print("❌ Inventory full! Cannot loot %s" % item_name)

func _on_take_all_pressed() -> void:
	"""Take all items from all corpses (gold already awarded when UI opened)"""
	var looted_count = 0
	var total_count = 0

	var network_enemy_mgr = get_node_or_null("/root/NetworkEnemyManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()

	# Count total items
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			total_count += corpse.corpse_loot.size()

	# Collect all items to loot first (with their indices for network sync)
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
				print("❌ Inventory full! Looted %d of %d items" % [looted_count, total_count])
				# Check which corpses are empty
				for c in corpses_looted:
					if is_instance_valid(c):
						c.check_if_looted_empty()
				populate_loot_list()
				return

	# Check all corpses if empty
	for corpse in corpses_looted:
		if is_instance_valid(corpse):
			corpse.check_if_looted_empty()

	if looted_count > 0:
		print("✨ Looted all %d items from %d corpse(s)" % [looted_count, corpses_looted.size()])
		all_corpses_looted.emit()

	# Refresh and potentially close
	populate_loot_list()

func _on_close_pressed() -> void:
	"""Handle close button press"""
	close_ui()
