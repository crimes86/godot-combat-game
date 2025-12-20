extends CanvasLayer
## TradeWindowUI - Proximity-based trading between players
## Players must be within 5 tiles to trade forged items
##
## Flow:
## 1. /trade <player> - Request trade (must be within range)
## 2. /accepttrade - Accept pending request
## 3. Trade window opens for both players
## 4. Each player selects forged items and gold amount
## 5. Both players "Lock In" their offer
## 6. Trade executes when both locked

signal trade_requested(target_id: int)
signal trade_accepted(partner_id: int)
signal trade_declined(partner_id: int)
signal trade_completed(my_items: Array, their_items: Array, gold_diff: int)
signal trade_cancelled(reason: String)

# Constants
const TRADE_REQUEST_TIMEOUT: float = 30.0
const MAX_TRADE_DISTANCE: float = 160.0  # 5 tiles * 32 pixels
const TRADE_CANCEL_DISTANCE: float = 300.0  # Cancel if too far

# UI colors from UITheme
var BG_COLOR: Color:
	get: return UITheme.BG_COLOR
var BORDER_COLOR: Color:
	get: return UITheme.BORDER_COLOR
var ACCENT_COLOR: Color:
	get: return UITheme.ACCENT_COLOR
var TEXT_COLOR: Color:
	get: return UITheme.TEXT_COLOR
var HEADER_COLOR: Color:
	get: return UITheme.HEADER_COLOR
var INPUT_BG: Color:
	get: return UITheme.INPUT_BG

# Trade state
var is_trading: bool = false
var trade_partner_id: int = -1
var trade_partner_name: String = ""

# Pending requests: {my_id: {requester_id, requester_name, timestamp}}
var pending_requests: Dictionary = {}
var sent_requests: Dictionary = {}  # {target_id: timestamp}

# Trade offers
var my_offered_items: Array = []  # Array of forged item token_ids
var my_offered_gold: int = 0
var their_offered_items: Array = []
var their_offered_gold: int = 0

var my_locked: bool = false
var their_locked: bool = false

# UI elements
var main_panel: PanelContainer
var my_items_grid: GridContainer
var their_items_grid: GridContainer
var my_gold_input: SpinBox
var their_gold_label: Label
var my_lock_button: Button
var cancel_button: Button
var status_label: Label
var my_name_label: Label
var their_name_label: Label

# Item picker popup
var item_picker_popup: PanelContainer = null
var item_picker_grid: GridContainer = null
var item_picker_target_slot: PanelContainer = null

func _ready() -> void:
	layer = 120  # Above most UI
	_create_ui()
	_create_item_picker_popup()
	hide_trade_window()

func _process(_delta: float) -> void:
	_process_request_timeouts()
	_check_trade_distance()

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func request_trade(target_id: int) -> Dictionary:
	"""Start immediate trade with target player - opens window for both. Returns {success, message}"""
	print("[Trade] request_trade called for target_id: %d" % target_id)

	var check = can_request_trade(target_id)
	if not check.valid:
		print("[Trade] can_request_trade failed: %s" % check.reason)
		return {success = false, message = check.reason}

	var my_id = multiplayer.get_unique_id()
	var target_name = _get_player_name(target_id)

	# If we're the server, handle directly (rpc_id to self doesn't work without call_local)
	if multiplayer.is_server():
		print("[Trade] Server handling trade request directly for target: %s (%d)" % [target_name, target_id])
		_handle_trade_start(my_id, target_id)
	else:
		print("[Trade] Client sending _server_start_immediate_trade RPC to server for target: %s (%d)" % [target_name, target_id])
		rpc_id(1, "_server_start_immediate_trade", target_id)

	return {success = true, message = "Starting trade with %s..." % target_name}

func accept_trade() -> Dictionary:
	"""Accept pending trade request. Returns {success, message}"""
	if not has_pending_request():
		return {success = false, message = "No pending trade request"}

	var request = get_pending_request_info()
	var requester_id = request.requester_id

	# Check distance again
	var distance = _get_player_distance(multiplayer.get_unique_id(), requester_id)
	if distance > MAX_TRADE_DISTANCE:
		_remove_pending_request(multiplayer.get_unique_id())
		return {success = false, message = "Requester is too far away"}

	# Send accept to server
	rpc_id(1, "_server_accept_trade", requester_id)

	return {success = true, message = "Trade accepted!"}

func decline_trade() -> Dictionary:
	"""Decline pending trade request. Returns {success, message}"""
	if not has_pending_request():
		return {success = false, message = "No pending trade request"}

	var request = get_pending_request_info()
	var requester_id = request.requester_id

	_remove_pending_request(multiplayer.get_unique_id())
	rpc_id(1, "_server_decline_trade", requester_id)

	return {success = true, message = "Trade declined"}

func cancel_trade() -> void:
	"""Cancel the current trade"""
	if not is_trading:
		return

	rpc_id(1, "_server_cancel_trade", trade_partner_id)
	_close_trade("Trade cancelled")

func can_request_trade(target_id: int) -> Dictionary:
	"""Check if can request trade. Returns {valid, reason}"""
	if not multiplayer.has_multiplayer_peer():
		return {valid = false, reason = "Not connected"}

	var my_id = multiplayer.get_unique_id()

	if target_id == my_id:
		return {valid = false, reason = "Cannot trade with yourself"}

	if is_trading:
		return {valid = false, reason = "Already in a trade"}

	if sent_requests.has(target_id):
		return {valid = false, reason = "Request already pending"}

	# Check distance
	var distance = _get_player_distance(my_id, target_id)
	if distance < 0:
		return {valid = false, reason = "Cannot find target player"}
	if distance > MAX_TRADE_DISTANCE:
		return {valid = false, reason = "Target too far (must be within 5 tiles)"}

	# Check if authenticated with Ashbane (required for forged item trading)
	if not AshbaneAuth or not AshbaneAuth.is_logged_in():
		return {valid = false, reason = "Trading requires Ashbane authentication"}

	return {valid = true, reason = ""}

func has_pending_request() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	var my_id = multiplayer.get_unique_id()
	return pending_requests.has(my_id)

func get_pending_request_info() -> Dictionary:
	if not multiplayer.has_multiplayer_peer():
		return {}
	var my_id = multiplayer.get_unique_id()
	return pending_requests.get(my_id, {})

# ═══════════════════════════════════════════════════════════════════════════
# TRADE WINDOW UI
# ═══════════════════════════════════════════════════════════════════════════

func _create_ui() -> void:
	"""Create the trade window UI"""
	main_panel = PanelContainer.new()
	main_panel.name = "TradeWindow"

	# Center on screen
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.custom_minimum_size = Vector2(500, 400)
	main_panel.anchor_left = 0.5
	main_panel.anchor_top = 0.5
	main_panel.anchor_right = 0.5
	main_panel.anchor_bottom = 0.5
	main_panel.offset_left = -250
	main_panel.offset_right = 250
	main_panel.offset_top = -200
	main_panel.offset_bottom = 200

	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = BORDER_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_size = 15
	style.shadow_color = Color(0, 0, 0, 0.8)
	main_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	main_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	# Header
	var header_row = HBoxContainer.new()
	vbox.add_child(header_row)

	var title = Label.new()
	title.text = "TRADE"
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(80, 0)
	_style_button(cancel_button, Color(0.6, 0.3, 0.3))
	cancel_button.pressed.connect(cancel_trade)
	header_row.add_child(cancel_button)

	# X close button
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.5, 0.2, 0.2, 0.8)
	close_style.corner_radius_top_left = 4
	close_style.corner_radius_top_right = 4
	close_style.corner_radius_bottom_left = 4
	close_style.corner_radius_bottom_right = 4
	var close_hover = close_style.duplicate()
	close_hover.bg_color = Color(0.7, 0.2, 0.2, 1.0)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.pressed.connect(cancel_trade)
	header_row.add_child(close_btn)

	# Status label
	status_label = Label.new()
	status_label.text = "Select items and gold to offer"
	status_label.add_theme_color_override("font_color", ACCENT_COLOR)
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# Trade columns
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(columns)

	# My offer column
	var my_column = _create_offer_column("Your Offer", true)
	columns.add_child(my_column)

	# Separator
	var sep = VSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	columns.add_child(sep)

	# Their offer column
	var their_column = _create_offer_column("Their Offer", false)
	columns.add_child(their_column)

	# Bottom row with lock button
	var bottom_row = HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 10)
	vbox.add_child(bottom_row)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer)

	my_lock_button = Button.new()
	my_lock_button.text = "Lock In Offer"
	my_lock_button.custom_minimum_size = Vector2(150, 35)
	_style_button(my_lock_button, Color(0.3, 0.6, 0.3))
	my_lock_button.pressed.connect(_on_lock_pressed)
	bottom_row.add_child(my_lock_button)

	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(spacer2)

	add_child(main_panel)

func _create_item_picker_popup() -> void:
	"""Create the popup for selecting items to trade"""
	item_picker_popup = PanelContainer.new()
	item_picker_popup.name = "ItemPickerPopup"
	item_picker_popup.visible = false
	item_picker_popup.custom_minimum_size = Vector2(300, 250)

	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR.lightened(0.1)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = ACCENT_COLOR
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_size = 10
	style.shadow_color = Color(0, 0, 0, 0.6)
	item_picker_popup.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	item_picker_popup.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Header with close button
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title_label = Label.new()
	title_label.text = "Select Item"
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(24, 24)
	var close_style = StyleBoxFlat.new()
	close_style.bg_color = Color(0.5, 0.2, 0.2, 0.8)
	close_style.corner_radius_top_left = 3
	close_style.corner_radius_top_right = 3
	close_style.corner_radius_bottom_left = 3
	close_style.corner_radius_bottom_right = 3
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.pressed.connect(_hide_item_picker)
	header.add_child(close_btn)

	# Scroll container for items
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(scroll)

	# Grid for item buttons
	item_picker_grid = GridContainer.new()
	item_picker_grid.columns = 3
	item_picker_grid.add_theme_constant_override("h_separation", 6)
	item_picker_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(item_picker_grid)

	add_child(item_picker_popup)

func _create_offer_column(title: String, is_mine: bool) -> VBoxContainer:
	"""Create a column for offers - 4 fixed trade slots + gold"""
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)

	# Title
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", HEADER_COLOR)
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title_label)

	if is_mine:
		my_name_label = title_label
	else:
		their_name_label = title_label

	# 4 fixed item slots (2x2 grid)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	if is_mine:
		my_items_grid = grid
	else:
		their_items_grid = grid

	# Create 4 empty slots
	for i in range(4):
		var slot = _create_trade_slot(i, is_mine)
		grid.add_child(slot)

	# Gold row
	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	column.add_child(gold_row)

	var gold_icon = Label.new()
	gold_icon.text = "💰 Gold:"
	gold_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	gold_row.add_child(gold_icon)

	if is_mine:
		my_gold_input = SpinBox.new()
		my_gold_input.min_value = 0
		my_gold_input.max_value = 999999
		my_gold_input.step = 10
		my_gold_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		my_gold_input.value_changed.connect(_on_gold_changed)
		gold_row.add_child(my_gold_input)
	else:
		their_gold_label = Label.new()
		their_gold_label.text = "0"
		their_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		their_gold_label.add_theme_font_size_override("font_size", 14)
		their_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(their_gold_label)

	return column

func _create_trade_slot(slot_index: int, is_mine: bool) -> PanelContainer:
	"""Create an individual trade slot"""
	var slot = PanelContainer.new()
	slot.custom_minimum_size = Vector2(70, 70)
	slot.set_meta("slot_index", slot_index)
	slot.set_meta("is_mine", is_mine)
	slot.set_meta("item_token_id", -1)  # -1 = empty

	# Slot background
	var style = StyleBoxFlat.new()
	style.bg_color = INPUT_BG
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = BORDER_COLOR.darkened(0.3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	slot.add_theme_stylebox_override("panel", style)

	# Center container for content
	var center = CenterContainer.new()
	slot.add_child(center)

	# Empty slot label
	var empty_label = Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = "+"
	empty_label.add_theme_font_size_override("font_size", 24)
	empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45, 0.6))
	center.add_child(empty_label)

	# Item label (hidden by default)
	var item_label = Label.new()
	item_label.name = "ItemLabel"
	item_label.text = ""
	item_label.visible = false
	item_label.add_theme_font_size_override("font_size", 10)
	item_label.add_theme_color_override("font_color", TEXT_COLOR)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	center.add_child(item_label)

	# Click handling for my slots
	if is_mine:
		slot.gui_input.connect(_on_slot_clicked.bind(slot))

	return slot

func _on_slot_clicked(event: InputEvent, slot: PanelContainer) -> void:
	"""Handle clicking on a trade slot"""
	if my_locked:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var slot_index = slot.get_meta("slot_index", 0)
		var current_token = slot.get_meta("item_token_id", -1)

		if current_token > 0:
			# Slot has item - remove it
			_remove_item_from_slot(slot)
		else:
			# Slot empty - show item picker
			_show_item_picker(slot)

func _style_button(button: Button, color: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	var hover = style.duplicate()
	hover.bg_color = color.lightened(0.2)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_font_size_override("font_size", 13)

func show_trade_window(partner_id: int, partner_name: String) -> void:
	"""Open trade window with partner"""
	print("[Trade] show_trade_window called: partner_id=%d, partner_name=%s" % [partner_id, partner_name])

	is_trading = true
	trade_partner_id = partner_id
	trade_partner_name = partner_name

	# Reset state
	my_offered_items.clear()
	their_offered_items.clear()
	my_offered_gold = 0
	their_offered_gold = 0
	my_locked = false
	their_locked = false

	# Update UI
	my_name_label.text = "Your Offer"
	their_name_label.text = "%s's Offer" % partner_name
	status_label.text = "Select items and gold to offer"
	my_lock_button.text = "Lock In Offer"
	my_lock_button.disabled = false
	my_gold_input.value = 0
	their_gold_label.text = "0"

	_populate_my_items()
	_clear_their_items()

	main_panel.visible = true

func hide_trade_window() -> void:
	main_panel.visible = false
	if item_picker_popup:
		item_picker_popup.visible = false

func _close_trade(reason: String) -> void:
	"""Close trade and reset state"""
	is_trading = false
	trade_partner_id = -1
	trade_partner_name = ""
	my_offered_items.clear()
	their_offered_items.clear()

	hide_trade_window()
	trade_cancelled.emit(reason)

	# Show notification
	if NotificationManager:
		NotificationManager.show_notification(reason, "SYSTEM")

func _populate_my_items() -> void:
	"""Reset my trade slots to empty"""
	for slot in my_items_grid.get_children():
		_clear_slot(slot)
	my_offered_items.clear()

func _clear_their_items() -> void:
	"""Reset their trade slots to empty"""
	for slot in their_items_grid.get_children():
		_clear_slot(slot)
	their_offered_items.clear()

func _clear_slot(slot: PanelContainer) -> void:
	"""Reset a slot to empty state"""
	slot.set_meta("item_token_id", -1)
	slot.set_meta("item_data", null)

	var center = slot.get_child(0)
	if center:
		var empty_label = center.get_node_or_null("EmptyLabel")
		var item_label = center.get_node_or_null("ItemLabel")
		if empty_label:
			empty_label.visible = true
		if item_label:
			item_label.visible = false
			item_label.text = ""

	# Reset border color
	var style = slot.get_theme_stylebox("panel").duplicate()
	style.border_color = BORDER_COLOR.darkened(0.3)
	slot.add_theme_stylebox_override("panel", style)

func _remove_item_from_slot(slot: PanelContainer) -> void:
	"""Remove item from a slot"""
	var token_id = slot.get_meta("item_token_id", -1)
	if token_id > 0:
		my_offered_items.erase(token_id)

	_clear_slot(slot)

	# Sync to partner
	if trade_partner_id > 0:
		rpc_id(1, "_server_update_offer", trade_partner_id, my_offered_items, my_offered_gold)

func _show_item_picker(slot: PanelContainer) -> void:
	"""Show picker popup for selecting an item to add to slot"""
	if not ForgeItemManager:
		return

	var items = ForgeItemManager.get_all_forged_items()
	if items.is_empty():
		if NotificationManager:
			NotificationManager.show_notification("No forged items to trade", "INFO")
		return

	# Filter out already offered items
	var available_items = []
	for item in items:
		var token_id = item.get("token_id", -1)
		if token_id not in my_offered_items:
			available_items.append(item)

	if available_items.is_empty():
		if NotificationManager:
			NotificationManager.show_notification("All items already in trade", "INFO")
		return

	# Store target slot
	item_picker_target_slot = slot

	# Clear and populate picker grid
	for child in item_picker_grid.get_children():
		child.queue_free()

	for item in available_items:
		var btn = _create_picker_item_button(item)
		item_picker_grid.add_child(btn)

	# Position popup near the slot
	var slot_rect = slot.get_global_rect()
	item_picker_popup.global_position = slot_rect.position + Vector2(slot_rect.size.x + 10, 0)

	# Ensure popup stays on screen
	var viewport_size = get_viewport().get_visible_rect().size
	if item_picker_popup.global_position.x + 300 > viewport_size.x:
		item_picker_popup.global_position.x = slot_rect.position.x - 310
	if item_picker_popup.global_position.y + 250 > viewport_size.y:
		item_picker_popup.global_position.y = viewport_size.y - 260

	item_picker_popup.visible = true

func _create_picker_item_button(item: Dictionary) -> Button:
	"""Create a button for item picker"""
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(85, 50)

	var item_name = item.get("item_name", "???")
	var rarity = item.get("item_rarity", "COMMON")
	btn.text = item_name.substr(0, 10)

	var rarity_color = _get_rarity_color(rarity)
	var style = StyleBoxFlat.new()
	style.bg_color = rarity_color.darkened(0.6)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = rarity_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	var hover = style.duplicate()
	hover.bg_color = rarity_color.darkened(0.4)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_font_size_override("font_size", 10)

	btn.pressed.connect(_on_picker_item_selected.bind(item))

	return btn

func _on_picker_item_selected(item: Dictionary) -> void:
	"""Handle item selection from picker"""
	if item_picker_target_slot:
		_add_item_to_slot(item_picker_target_slot, item)
	_hide_item_picker()

func _hide_item_picker() -> void:
	"""Hide the item picker popup"""
	item_picker_popup.visible = false
	item_picker_target_slot = null

func _add_item_to_slot(slot: PanelContainer, item: Dictionary) -> void:
	"""Add an item to a trade slot"""
	var token_id = item.get("token_id", -1)
	var item_name = item.get("item_name", "???")
	var rarity = item.get("item_rarity", "COMMON")

	slot.set_meta("item_token_id", token_id)
	slot.set_meta("item_data", item)

	# Update visuals
	var center = slot.get_child(0)
	if center:
		var empty_label = center.get_node_or_null("EmptyLabel")
		var item_label = center.get_node_or_null("ItemLabel")
		if empty_label:
			empty_label.visible = false
		if item_label:
			item_label.visible = true
			item_label.text = item_name.substr(0, 12)

	# Set border color based on rarity
	var rarity_color = _get_rarity_color(rarity)
	var style = slot.get_theme_stylebox("panel").duplicate()
	style.border_color = rarity_color
	slot.add_theme_stylebox_override("panel", style)

	# Add to offered items
	if token_id not in my_offered_items:
		my_offered_items.append(token_id)

	# Sync to partner
	if trade_partner_id > 0:
		rpc_id(1, "_server_update_offer", trade_partner_id, my_offered_items, my_offered_gold)

func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_upper():
		"COMMON": return Color(0.6, 0.6, 0.6)
		"UNCOMMON": return Color(0.3, 0.8, 0.3)
		"RARE": return Color(0.3, 0.5, 1.0)
		"EPIC": return Color(0.6, 0.3, 0.9)
		"LEGENDARY": return Color(1.0, 0.6, 0.1)
		"ARTIFACT": return Color(0.9, 0.2, 0.2)
		_: return Color(0.6, 0.6, 0.6)

func _on_gold_changed(value: float) -> void:
	if my_locked:
		my_gold_input.value = my_offered_gold
		return

	my_offered_gold = int(value)
	rpc_id(1, "_server_update_offer", trade_partner_id, my_offered_items, my_offered_gold)

func _on_lock_pressed() -> void:
	if my_locked:
		# Unlock
		my_locked = false
		my_lock_button.text = "Lock In Offer"
		_style_button(my_lock_button, Color(0.3, 0.6, 0.3))
		status_label.text = "Offer unlocked"
	else:
		# Lock
		my_locked = true
		my_lock_button.text = "Unlock"
		_style_button(my_lock_button, Color(0.6, 0.6, 0.3))
		status_label.text = "Waiting for partner to lock in..."

	rpc_id(1, "_server_lock_offer", trade_partner_id, my_locked)

func _update_their_offer(items: Array, gold: int) -> void:
	"""Update display of partner's offer using fixed slots"""
	their_offered_items = items
	their_offered_gold = gold
	their_gold_label.text = str(gold)

	# Update their slots
	var slots = their_items_grid.get_children()
	for i in range(slots.size()):
		var slot = slots[i]
		if i < items.size():
			# Show item in this slot
			var token_id = items[i]
			_update_their_slot(slot, token_id)
		else:
			# Clear this slot
			_clear_slot(slot)

func _update_their_slot(slot: PanelContainer, token_id: int) -> void:
	"""Update a partner's slot with an item"""
	slot.set_meta("item_token_id", token_id)

	var center = slot.get_child(0)
	if center:
		var empty_label = center.get_node_or_null("EmptyLabel")
		var item_label = center.get_node_or_null("ItemLabel")
		if empty_label:
			empty_label.visible = false
		if item_label:
			item_label.visible = true
			item_label.text = "Item #%d" % token_id

	# Set a neutral color for their items
	var style = slot.get_theme_stylebox("panel").duplicate()
	style.border_color = ACCENT_COLOR
	slot.add_theme_stylebox_override("panel", style)

func _update_their_lock(locked: bool) -> void:
	their_locked = locked

	if my_locked and their_locked:
		status_label.text = "Both locked! Executing trade..."
		_execute_trade()
	elif their_locked:
		status_label.text = "%s has locked in!" % trade_partner_name

func _execute_trade() -> void:
	"""Execute the trade via backend"""
	# For each forged item I'm offering, call the direct trade API
	for token_id in my_offered_items:
		TradingManager.execute_direct_trade(token_id, trade_partner_id, 0)

	# Gold transfer would be handled via local inventory (not backend)
	if my_offered_gold > 0:
		CharacterStats.add_gold(-my_offered_gold)

	if their_offered_gold > 0:
		CharacterStats.add_gold(their_offered_gold)

	trade_completed.emit(my_offered_items, their_offered_items, their_offered_gold - my_offered_gold)
	_close_trade("Trade completed!")

# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _get_player_distance(id1: int, id2: int) -> float:
	var node1 = _get_player_node(id1)
	var node2 = _get_player_node(id2)
	if not node1 or not node2:
		return -1.0
	return node1.global_position.distance_to(node2.global_position)

func _get_player_node(peer_id: int) -> Node2D:
	var tree = get_tree()
	if not tree:
		return null
	for node in tree.get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == peer_id:
			return node
	return null

func _get_player_name(peer_id: int) -> String:
	var network_manager = get_node_or_null("/root/NetworkManager")
	if network_manager and network_manager.connected_players.has(peer_id):
		return network_manager.connected_players[peer_id].get("name", "Player")
	return "Player"

func _add_pending_request(target_id: int, requester_id: int, requester_name: String) -> void:
	pending_requests[target_id] = {
		requester_id = requester_id,
		requester_name = requester_name,
		timestamp = Time.get_unix_time_from_system()
	}

func _remove_pending_request(target_id: int) -> void:
	pending_requests.erase(target_id)

func _process_request_timeouts() -> void:
	var current = Time.get_unix_time_from_system()
	var expired: Array = []
	for target_id in pending_requests:
		if current - pending_requests[target_id].timestamp > TRADE_REQUEST_TIMEOUT:
			expired.append(target_id)
	for target_id in expired:
		pending_requests.erase(target_id)
		sent_requests.erase(target_id)

func _check_trade_distance() -> void:
	if not is_trading:
		return
	var distance = _get_player_distance(multiplayer.get_unique_id(), trade_partner_id)
	if distance > TRADE_CANCEL_DISTANCE:
		cancel_trade()

# ═══════════════════════════════════════════════════════════════════════════
# RPC - SERVER HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _handle_trade_start(requester_id: int, target_id: int) -> void:
	"""Core trade start logic - called by server for both local and remote requests"""
	var requester_name = _get_player_name(requester_id)
	var target_name = _get_player_name(target_id)

	print("[Trade] Processing trade request: requester=%s (%d), target=%s (%d)" % [requester_name, requester_id, target_name, target_id])

	# For the requester: if they're the server (peer 1), call directly; otherwise RPC
	if requester_id == 1:
		print("[Trade] Requester is server, calling _client_trade_started directly")
		_client_trade_started(target_id, target_name)
	else:
		print("[Trade] Sending _client_trade_started RPC to requester %d" % requester_id)
		rpc_id(requester_id, "_client_trade_started", target_id, target_name)

	# For the target: if they're the server (peer 1), call directly; otherwise RPC
	if target_id == 1:
		print("[Trade] Target is server, calling _client_trade_started directly")
		_client_trade_started(requester_id, requester_name)
	else:
		print("[Trade] Sending _client_trade_started RPC to target %d" % target_id)
		rpc_id(target_id, "_client_trade_started", requester_id, requester_name)

	print("[Trade] Started immediate trade: %s <-> %s" % [requester_name, target_name])

@rpc("any_peer", "reliable")
func _server_start_immediate_trade(target_id: int) -> void:
	"""Server RPC handler - for when clients initiate trades"""
	print("[Trade] _server_start_immediate_trade RPC received with target_id: %d" % target_id)

	if not multiplayer.is_server():
		print("[Trade] ERROR: Not server, returning")
		return

	var requester_id = multiplayer.get_remote_sender_id()
	print("[Trade] Remote sender ID: %d" % requester_id)

	_handle_trade_start(requester_id, target_id)

@rpc("any_peer", "reliable")
func _server_request_trade(target_id: int) -> void:
	"""Legacy - redirects to immediate trade"""
	if not multiplayer.is_server():
		return
	# Redirect to immediate trade flow
	_server_start_immediate_trade(target_id)

@rpc("any_peer", "reliable")
func _server_accept_trade(requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	var accepter_id = multiplayer.get_remote_sender_id()
	var accepter_name = _get_player_name(accepter_id)

	# Notify both to open trade window
	rpc_id(requester_id, "_client_trade_accepted", accepter_id, accepter_name)
	rpc_id(accepter_id, "_client_trade_accepted", requester_id, _get_player_name(requester_id))

@rpc("any_peer", "reliable")
func _server_decline_trade(requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	var decliner_id = multiplayer.get_remote_sender_id()
	rpc_id(requester_id, "_client_trade_declined", decliner_id)

@rpc("any_peer", "reliable")
func _server_cancel_trade(partner_id: int) -> void:
	if not multiplayer.is_server():
		return
	var canceller_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_trade_cancelled", canceller_id)

@rpc("any_peer", "reliable")
func _server_update_offer(partner_id: int, items: Array, gold: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_offer_updated", sender_id, items, gold)

@rpc("any_peer", "reliable")
func _server_lock_offer(partner_id: int, locked: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	rpc_id(partner_id, "_client_lock_updated", sender_id, locked)

# ═══════════════════════════════════════════════════════════════════════════
# RPC - CLIENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _client_trade_started(partner_id: int, partner_name: String) -> void:
	"""Immediately open trade window with partner"""
	print("[Trade] _client_trade_started received: partner_id=%d, partner_name=%s" % [partner_id, partner_name])

	# Check if we're already busy
	if is_trading:
		print("[Trade] Already trading, ignoring new trade request")
		return

	print("[Trade] Opening trade window with partner: %s" % partner_name)

	# Open the trade window immediately
	show_trade_window(partner_id, partner_name)

	# Show notification
	if NotificationManager:
		NotificationManager.show_notification("Trade started with %s" % partner_name, "INFO")

@rpc("authority", "call_local", "reliable")
func _client_trade_requested(requester_id: int, requester_name: String) -> void:
	"""Legacy handler - now also opens trade immediately"""
	_client_trade_started(requester_id, requester_name)

@rpc("authority", "call_local", "reliable")
func _client_trade_accepted(partner_id: int, partner_name: String) -> void:
	sent_requests.erase(partner_id)
	_remove_pending_request(multiplayer.get_unique_id())
	show_trade_window(partner_id, partner_name)

@rpc("authority", "call_local", "reliable")
func _client_trade_declined(decliner_id: int) -> void:
	sent_requests.erase(decliner_id)
	var decliner_name = _get_player_name(decliner_id)

	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui:
		chat_ui.add_system_message("%s declined the trade request" % decliner_name)

@rpc("authority", "call_local", "reliable")
func _client_trade_cancelled(canceller_id: int) -> void:
	if is_trading and trade_partner_id == canceller_id:
		_close_trade("Trade cancelled by partner")

@rpc("authority", "call_local", "reliable")
func _client_offer_updated(sender_id: int, items: Array, gold: int) -> void:
	if is_trading and trade_partner_id == sender_id:
		_update_their_offer(items, gold)

@rpc("authority", "call_local", "reliable")
func _client_lock_updated(sender_id: int, locked: bool) -> void:
	if is_trading and trade_partner_id == sender_id:
		_update_their_lock(locked)
