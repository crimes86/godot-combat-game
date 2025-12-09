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

func _ready() -> void:
	layer = 120  # Above most UI
	_create_ui()
	hide_trade_window()

func _process(_delta: float) -> void:
	_process_request_timeouts()
	_check_trade_distance()

# ═══════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════

func request_trade(target_id: int) -> Dictionary:
	"""Request a trade with target player. Returns {success, message}"""
	var check = can_request_trade(target_id)
	if not check.valid:
		return {success = false, message = check.reason}

	var my_id = multiplayer.get_unique_id()
	sent_requests[target_id] = Time.get_unix_time_from_system()

	# Send request to server
	rpc_id(1, "_server_request_trade", target_id)

	var target_name = _get_player_name(target_id)
	return {success = true, message = "Trade request sent to %s" % target_name}

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

	# Check if authenticated with Mantle (required for forged item trading)
	if not MantleAuth or not MantleAuth.is_logged_in():
		return {valid = false, reason = "Trading requires Mantle authentication"}

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

func _create_offer_column(title: String, is_mine: bool) -> VBoxContainer:
	"""Create a column for offers"""
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

	# Items scroll area
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(180, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll_style = StyleBoxFlat.new()
	scroll_style.bg_color = INPUT_BG
	scroll_style.corner_radius_top_left = 4
	scroll_style.corner_radius_top_right = 4
	scroll_style.corner_radius_bottom_left = 4
	scroll_style.corner_radius_bottom_right = 4
	scroll.add_theme_stylebox_override("panel", scroll_style)
	column.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)

	if is_mine:
		my_items_grid = grid
	else:
		their_items_grid = grid

	# Gold row
	var gold_row = HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	column.add_child(gold_row)

	var gold_icon = Label.new()
	gold_icon.text = "Gold:"
	gold_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	gold_row.add_child(gold_icon)

	if is_mine:
		my_gold_input = SpinBox.new()
		my_gold_input.min_value = 0
		my_gold_input.max_value = 999999
		my_gold_input.step = 100
		my_gold_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		my_gold_input.value_changed.connect(_on_gold_changed)
		gold_row.add_child(my_gold_input)
	else:
		their_gold_label = Label.new()
		their_gold_label.text = "0"
		their_gold_label.add_theme_color_override("font_color", TEXT_COLOR)
		their_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gold_row.add_child(their_gold_label)

	return column

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
		NotificationManager.show_notification(reason, NotificationManager.NotificationType.SYSTEM)

func _populate_my_items() -> void:
	"""Populate grid with player's forged items"""
	# Clear existing
	for child in my_items_grid.get_children():
		child.queue_free()

	if not ForgeItemManager:
		return

	var items = ForgeItemManager.get_all_forged_items()
	for item in items:
		var btn = _create_item_button(item, true)
		my_items_grid.add_child(btn)

	if items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No forged items"
		empty_label.add_theme_color_override("font_color", ACCENT_COLOR)
		my_items_grid.add_child(empty_label)

func _clear_their_items() -> void:
	for child in their_items_grid.get_children():
		child.queue_free()

func _create_item_button(item: Dictionary, is_mine: bool) -> Button:
	"""Create a button for a forged item"""
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(80, 60)
	btn.text = item.get("item_name", "???").substr(0, 10)

	var token_id = item.get("token_id", -1)
	var is_selected = token_id in my_offered_items if is_mine else token_id in their_offered_items

	var rarity = item.get("item_rarity", "COMMON")
	var rarity_color = _get_rarity_color(rarity)

	var style = StyleBoxFlat.new()
	style.bg_color = rarity_color.darkened(0.7) if not is_selected else rarity_color.darkened(0.3)
	style.border_width_left = 2
	style.border_color = rarity_color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_font_size_override("font_size", 10)

	if is_mine and not my_locked:
		btn.pressed.connect(_on_my_item_clicked.bind(token_id))

	btn.set_meta("token_id", token_id)
	btn.set_meta("item", item)

	return btn

func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_upper():
		"COMMON": return Color(0.6, 0.6, 0.6)
		"UNCOMMON": return Color(0.3, 0.8, 0.3)
		"RARE": return Color(0.3, 0.5, 1.0)
		"EPIC": return Color(0.6, 0.3, 0.9)
		"LEGENDARY": return Color(1.0, 0.6, 0.1)
		"ARTIFACT": return Color(0.9, 0.2, 0.2)
		_: return Color(0.6, 0.6, 0.6)

func _on_my_item_clicked(token_id: int) -> void:
	"""Toggle item selection"""
	if my_locked:
		return

	if token_id in my_offered_items:
		my_offered_items.erase(token_id)
	else:
		my_offered_items.append(token_id)

	# Update UI
	_populate_my_items()

	# Sync to partner
	rpc_id(1, "_server_update_offer", trade_partner_id, my_offered_items, my_offered_gold)

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
	"""Update display of partner's offer"""
	their_offered_items = items
	their_offered_gold = gold
	their_gold_label.text = str(gold)

	# Update their items display
	_clear_their_items()
	for token_id in items:
		# We don't have their item details, just show token ID
		var placeholder = Button.new()
		placeholder.text = "Item #%d" % token_id
		placeholder.custom_minimum_size = Vector2(80, 60)
		placeholder.disabled = true

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.3, 0.35)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		placeholder.add_theme_stylebox_override("normal", style)
		placeholder.add_theme_color_override("font_color", TEXT_COLOR)

		their_items_grid.add_child(placeholder)

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

@rpc("any_peer", "reliable")
func _server_request_trade(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var requester_id = multiplayer.get_remote_sender_id()
	var requester_name = _get_player_name(requester_id)

	# Notify target
	rpc_id(target_id, "_client_trade_requested", requester_id, requester_name)

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
func _client_trade_requested(requester_id: int, requester_name: String) -> void:
	var my_id = multiplayer.get_unique_id()
	_add_pending_request(my_id, requester_id, requester_name)

	# Show notification
	var chat_ui = get_node_or_null("/root/ChatUI")
	if chat_ui:
		chat_ui.add_system_message("%s wants to trade! Type /accepttrade or /declinetrade" % requester_name)

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
