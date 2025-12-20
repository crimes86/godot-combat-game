extends Node

## PlayerInteractionController - Manages player-to-player interactions
## Detects nearby players and shows F-key radial for Inspect/Trade/Duel options
##
## Flow:
## 1. Player approaches another player (within MAX_INTERACTION_DISTANCE)
## 2. F prompt appears via InteractionManager priority system
## 3. Hold F for RADIAL_DURATION - RadialProgressIndicator fills
## 4. On completion, PlayerInteractionMenu appears
## 5. Player selects: Inspect, Trade, or Duel

# Constants
const MAX_INTERACTION_DISTANCE: float = 50.0  # Tight to player - need to be close
const DISTANCE_CHECK_INTERVAL: float = 0.1  # Throttle detection checks
const RADIAL_DURATION: float = 0.4  # Hold time for radial completion

# State tracking
var closest_player_node: Node2D = null
var closest_player_id: int = -1
var closest_player_name: String = ""

# F key and radial tracking
var is_holding_f: bool = false
var hold_start_time: float = 0.0
var radial_indicator: Control = null
var f_prompt_label: Label = null

# Distance check throttle
var _distance_check_timer: float = 0.0

# UI layer for prompt
var prompt_layer: CanvasLayer = null

func _ready() -> void:
	print("PlayerInteractionController initialized")
	_create_prompt_ui()

func _process(delta: float) -> void:
	# Don't process if game is paused or player is in UI
	if _is_player_busy():
		_cleanup_interaction()
		return

	# Throttled distance check
	_distance_check_timer += delta
	if _distance_check_timer >= DISTANCE_CHECK_INTERVAL:
		_distance_check_timer = 0.0
		_check_nearby_players()

	# Handle F key interaction
	_handle_f_key_input(delta)

	# Update radial position if active
	if radial_indicator and radial_indicator.visible:
		_update_radial_position()

# ═══════════════════════════════════════════════════════════════════════════
# PLAYER DETECTION
# ═══════════════════════════════════════════════════════════════════════════

func _check_nearby_players() -> void:
	"""Find closest eligible player within interaction range"""
	var local_player = _get_local_player()
	if not local_player or not is_instance_valid(local_player):
		_unregister_from_interaction_manager()
		closest_player_node = null
		closest_player_id = -1
		return

	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var my_pos = local_player.global_position

	var best_distance: float = MAX_INTERACTION_DISTANCE + 1
	var best_node: Node2D = null
	var best_id: int = -1

	# Check all players
	for node in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue

		var node_id = node.get_multiplayer_authority()

		# Skip self
		if node_id == my_id:
			continue

		# Skip dead players
		if node.has_method("is_dead") and node.is_dead():
			continue

		var distance = my_pos.distance_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best_node = node
			best_id = node_id

	# Update state
	if best_node and best_distance <= MAX_INTERACTION_DISTANCE:
		if closest_player_id != best_id:
			# New closest player
			closest_player_node = best_node
			closest_player_id = best_id
			closest_player_name = _get_player_name(best_id)
			_register_with_interaction_manager(best_distance)
		else:
			# Same player, update distance
			_update_interaction_distance(best_distance)

		# Show prompt if we're the active interactable
		_update_prompt_visibility()
	else:
		# No player in range
		if closest_player_id != -1:
			_unregister_from_interaction_manager()
		closest_player_node = null
		closest_player_id = -1
		closest_player_name = ""
		_hide_prompt()

func _register_with_interaction_manager(distance: float) -> void:
	"""Register as PLAYER interactable"""
	if InteractionManager:
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.PLAYER, distance)

func _update_interaction_distance(distance: float) -> void:
	"""Update distance for priority calculation"""
	if InteractionManager:
		InteractionManager.register_interactable(self, InteractionManager.InteractionType.PLAYER, distance)

func _unregister_from_interaction_manager() -> void:
	"""Unregister from InteractionManager"""
	if InteractionManager:
		InteractionManager.unregister_interactable(self)

# ═══════════════════════════════════════════════════════════════════════════
# F KEY HANDLING
# ═══════════════════════════════════════════════════════════════════════════

func _handle_f_key_input(delta: float) -> void:
	"""Handle F key hold for radial progress"""
	# Only handle if we're the active interactable and have a target
	if closest_player_id == -1:
		if is_holding_f:
			_cancel_radial()
		return

	if not InteractionManager or not InteractionManager.is_active_interactable(self):
		if is_holding_f:
			_cancel_radial()
		return

	var f_pressed = Input.is_physical_key_pressed(KEY_F)

	if f_pressed and not is_holding_f:
		# Started holding F
		_start_radial()
	elif f_pressed and is_holding_f:
		# Continue holding F - update progress
		var elapsed = (Time.get_ticks_msec() / 1000.0) - hold_start_time
		var progress = clampf(elapsed / RADIAL_DURATION, 0.0, 1.0)
		_update_radial_progress(progress)

		if progress >= 1.0:
			_complete_radial()
	elif not f_pressed and is_holding_f:
		# Released F early
		_cancel_radial()

func _start_radial() -> void:
	"""Start the radial progress indicator"""
	is_holding_f = true
	hold_start_time = Time.get_ticks_msec() / 1000.0

	if radial_indicator:
		radial_indicator.visible = true
		radial_indicator.set_meta("progress", 0.0)
		radial_indicator.queue_redraw()

		# Fade in
		var tween = create_tween()
		tween.tween_property(radial_indicator, "modulate:a", 1.0, 0.1)

func _update_radial_progress(progress: float) -> void:
	"""Update radial fill amount"""
	if radial_indicator:
		radial_indicator.set_meta("progress", progress)
		radial_indicator.queue_redraw()

func _cancel_radial() -> void:
	"""Cancel the radial progress (key released early)"""
	is_holding_f = false
	hold_start_time = 0.0

	if radial_indicator:
		var tween = create_tween()
		tween.tween_property(radial_indicator, "modulate:a", 0.0, 0.1)
		tween.tween_callback(func(): radial_indicator.visible = false)

func _complete_radial() -> void:
	"""Radial completed - show interaction menu"""
	is_holding_f = false
	hold_start_time = 0.0

	# Flash effect on radial
	if radial_indicator:
		var tween = create_tween()
		tween.tween_property(radial_indicator, "modulate:a", 1.5, 0.1)
		tween.tween_property(radial_indicator, "modulate:a", 0.0, 0.15)
		tween.tween_callback(func(): radial_indicator.visible = false)

	# Hide prompt
	_hide_prompt()

	# Show interaction menu
	_show_interaction_menu()

func _update_radial_position() -> void:
	"""Position radial at mouse cursor"""
	if radial_indicator:
		var mouse_pos = get_viewport().get_mouse_position()
		radial_indicator.global_position = mouse_pos - Vector2(24, 24)

# ═══════════════════════════════════════════════════════════════════════════
# PROMPT UI
# ═══════════════════════════════════════════════════════════════════════════

func _create_prompt_ui() -> void:
	"""Create the F prompt and radial indicator"""
	# Canvas layer for UI
	prompt_layer = CanvasLayer.new()
	prompt_layer.layer = 100  # Above game, below menus
	add_child(prompt_layer)

	# F prompt label (shows above target player)
	f_prompt_label = Label.new()
	f_prompt_label.text = "[F] Interact"
	f_prompt_label.add_theme_font_size_override("font_size", 14)
	f_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	f_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	f_prompt_label.add_theme_constant_override("outline_size", 2)
	f_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f_prompt_label.visible = false
	prompt_layer.add_child(f_prompt_label)

	# Radial progress indicator (follows cursor)
	radial_indicator = Control.new()
	radial_indicator.custom_minimum_size = Vector2(48, 48)
	radial_indicator.size = Vector2(48, 48)
	radial_indicator.visible = false
	radial_indicator.modulate.a = 0.0
	radial_indicator.set_meta("progress", 0.0)
	radial_indicator.draw.connect(_draw_radial)
	prompt_layer.add_child(radial_indicator)

func _draw_radial() -> void:
	"""Custom draw for radial progress"""
	if not radial_indicator:
		return

	var progress: float = radial_indicator.get_meta("progress", 0.0)
	var center = Vector2(24, 24)
	var radius: float = 18.0
	var thickness: float = 4.0

	# Background circle
	radial_indicator.draw_arc(center, radius, 0, TAU, 64, Color(0.2, 0.2, 0.2, 0.6), thickness, true)

	# Progress arc
	if progress > 0.0:
		var angle = progress * TAU
		var color = Color(0.3, 1.0, 0.3, 1.0) if progress >= 1.0 else Color(1.0, 0.9, 0.3, 0.9)
		radial_indicator.draw_arc(center, radius, -PI/2, -PI/2 + angle, 64, color, thickness, true)

	# F key hint in center
	var font = ThemeDB.fallback_font
	var font_size = 16
	radial_indicator.draw_string(font, center - Vector2(5, -5), "F", HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func _update_prompt_visibility() -> void:
	"""Show/hide prompt based on InteractionManager state"""
	if not InteractionManager or not InteractionManager.is_active_interactable(self):
		_hide_prompt()
		return

	if closest_player_node and is_instance_valid(closest_player_node) and f_prompt_label:
		f_prompt_label.visible = true
		f_prompt_label.text = "[F] %s" % closest_player_name

		# Position above target player's head
		var camera = get_viewport().get_camera_2d()
		if camera:
			var world_pos = closest_player_node.global_position + Vector2(0, -60)
			var screen_pos = camera.get_viewport().get_canvas_transform() * world_pos
			f_prompt_label.global_position = screen_pos - Vector2(f_prompt_label.size.x / 2, 0)

func _hide_prompt() -> void:
	"""Hide the F prompt"""
	if f_prompt_label:
		f_prompt_label.visible = false

# ═══════════════════════════════════════════════════════════════════════════
# INTERACTION MENU
# ═══════════════════════════════════════════════════════════════════════════

func _show_interaction_menu() -> void:
	"""Show the Inspect/Trade/Duel menu"""
	if not PlayerInteractionMenu:
		push_error("PlayerInteractionMenu autoload not found")
		return

	PlayerInteractionMenu.show_menu(closest_player_id, closest_player_name, closest_player_node)

# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _get_local_player() -> Node2D:
	"""Get the local player node"""
	var my_id = multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	for node in get_tree().get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == my_id:
			return node
	return null

func _get_player_name(peer_id: int) -> String:
	"""Get player name from NetworkManager"""
	if NetworkManager and NetworkManager.connected_players.has(peer_id):
		return NetworkManager.connected_players[peer_id].get("name", "Player")
	return "Player"

func _is_player_busy() -> bool:
	"""Check if player is in a UI or state that blocks interaction"""
	# Check trade/duel states (autoloads)
	if TradeWindowUI and TradeWindowUI.is_trading:
		return true
	if DuelManager and DuelManager.is_dueling():
		return true
	if PlayerInteractionMenu and PlayerInteractionMenu.is_visible:
		return true

	# Check scene-based UIs via tree
	var char_ui = get_node_or_null("/root/GameWorld/UI/CharacterUI")
	if char_ui and char_ui.visible:
		return true
	var inv_ui = get_node_or_null("/root/GameWorld/UI/InventoryUI")
	if inv_ui and inv_ui.visible:
		return true

	return false

func _cleanup_interaction() -> void:
	"""Cleanup state when player becomes busy"""
	if is_holding_f:
		_cancel_radial()
	_hide_prompt()
