extends CanvasLayer

## Inventory UI - Standalone inventory window
## Stone Gray UI theme matching CharacterUI
## Press I to toggle

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_EQUIP: bool = true  # Debug equipping items from inventory
const DEBUG_FORGED_DISPLAY: bool = false  # Debug forged item display in inventory

var is_visible: bool = false

# Deferred refresh system to prevent race conditions during rapid equip/unequip
var _needs_refresh: bool = false
var _refresh_scheduled: bool = false

# Pending deletion data (for confirmation dialog)
var pending_delete_data: Dictionary = {}

# Mouse click-and-hold tracking for inspection
var _long_hold_timer: Timer = null
var _long_hold_slot_index: int = -1
var _long_hold_start_time: float = 0.0
var _radial_progress: Control = null
const LONG_HOLD_DURATION = 0.6  # seconds (snappy but intentional)

# UI References
var main_panel: PanelContainer
var inventory_slots: Array[Control] = []
var gold_label: Label
var slot_counter_label: Label

# Stone Gray UI Palette (matching CharacterUI)
const BG_COLOR = Color(0.12, 0.12, 0.14, 0.75)  # Dark stone gray (transparent for combat)
const BORDER_COLOR = Color(0.35, 0.38, 0.42, 1.0)  # Steel gray border
const BORDER_INNER = Color(0.06, 0.06, 0.08, 1.0)  # Dark inner shadow
const ACCENT_COLOR = Color(0.55, 0.58, 0.62, 1.0)  # Light steel accent
const TEXT_COLOR = Color(0.92, 0.92, 0.94, 1.0)  # Clean white text
const HEADER_COLOR = Color(0.75, 0.78, 0.82, 1.0)  # Silver headers
const SLOT_BG = Color(0.08, 0.08, 0.10, 0.8)  # Dark stone inset
const SLOT_SIZE = UITheme.SLOT_SIZE  # Use centralized slot size (54px)

func _ready() -> void:
	# Set layer above other UI panels so bag is always accessible on top
	# Character sheet = 110, Skills panel = 115, Inspection = 120
	layer = 125

	# Add to group for tutorial system to find
	add_to_group("inventory_ui")

	# Start hidden
	visible = false

	# Create UI
	create_inventory_ui()

	# Connect to signals
	CharacterStats.gold_changed.connect(_on_gold_changed)
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	InventorySystem.slots_expanded.connect(_on_slots_expanded)

	# Initial update
	refresh_all()

func _input(event: InputEvent) -> void:
	"""Global input handler for ESC key"""
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			toggle_ui()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	"""Update cursor-following radial progress indicator"""
	if not visible:
		return

	# Update radial progress position and fill
	if _radial_progress and _long_hold_start_time > 0:
		_radial_progress.global_position = get_viewport().get_mouse_position() - Vector2(24, 24)
		var elapsed = (Time.get_ticks_msec() / 1000.0) - _long_hold_start_time
		var progress = clampf(elapsed / LONG_HOLD_DURATION, 0.0, 1.0)
		_radial_progress.set_meta("progress", progress)
		_radial_progress.queue_redraw()

func create_inventory_ui() -> void:
	"""Create standalone inventory window"""

	# NOTE: We no longer use a full-screen drop zone as it blocks input to other UIs
	# (like ShopUI) due to CanvasLayer input priority. Instead, we handle item deletion
	# by detecting drops outside the inventory panel directly on the panel itself.

	# Create confirmation dialog for deletion
	var delete_dialog = ConfirmationDialog.new()
	delete_dialog.name = "DeleteConfirmDialog"
	delete_dialog.title = "Delete Item"
	delete_dialog.dialog_text = "Are you sure you want to delete this item?"
	delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(delete_dialog)

	# Main panel container - positioned at bottom-right corner
	main_panel = PanelContainer.new()
	main_panel.name = "InventoryPanel"

	# Position at bottom-right - use custom_minimum_size and anchor to bottom-right
	# The panel will grow upward from the bottom-right corner
	main_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	main_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # Grow left from right edge
	main_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN    # Grow up from bottom edge
	main_panel.anchor_left = 1.0
	main_panel.anchor_top = 1.0
	main_panel.anchor_right = 1.0
	main_panel.anchor_bottom = 1.0
	# Position from bottom-right corner with padding
	# 5 columns: 54px*5 slots + 6px*4 gaps + 20px padding + borders = ~320px
	main_panel.offset_left = -330
	main_panel.offset_right = -10
	main_panel.offset_top = 0   # Will be determined by content size + grow direction
	main_panel.offset_bottom = -10  # 10px from bottom edge

	# Dark Fantasy dreadland styling with transparency
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = BG_COLOR
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = BORDER_COLOR
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.shadow_size = 8
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_offset = Vector2(0, 4)

	main_panel.add_theme_stylebox_override("panel", panel_style)

	# Main layout with padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	main_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Scrollable inventory container
	var scroll_container = ScrollContainer.new()
	scroll_container.name = "InventoryScroll"
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Set max visible height (shows all 5 rows of 5x5 grid)
	scroll_container.custom_minimum_size = Vector2(0, 294)
	main_vbox.add_child(scroll_container)

	# Inventory grid (5 columns, larger slots)
	var inv_grid = GridContainer.new()
	inv_grid.name = "InventoryGrid"
	inv_grid.columns = 5
	inv_grid.add_theme_constant_override("h_separation", 6)
	inv_grid.add_theme_constant_override("v_separation", 6)
	scroll_container.add_child(inv_grid)

	# Create inventory slots (starts with current_slot_count, expands dynamically)
	for i in range(InventorySystem.current_slot_count):
		var slot_button = create_inventory_slot(i)
		inv_grid.add_child(slot_button)
		inventory_slots.append(slot_button)

	# Bottom bar with gold and slot counter
	var bottom_bar = HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_bar.add_theme_constant_override("separation", 20)
	main_vbox.add_child(bottom_bar)

	# Gold display
	var gold_container = HBoxContainer.new()
	gold_container.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(gold_container)

	var gold_icon = TextureRect.new()
	gold_icon.texture = preload("res://assets/icons/materials/gold_coins.png")
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.custom_minimum_size = Vector2(24, 24)
	gold_container.add_child(gold_icon)

	gold_label = create_text_label("0", 16)
	gold_label.add_theme_color_override("font_color", HEADER_COLOR)
	gold_container.add_child(gold_label)

	# Slot counter (X/100)
	slot_counter_label = create_text_label("0/100", 14)
	slot_counter_label.add_theme_color_override("font_color", ACCENT_COLOR)
	bottom_bar.add_child(slot_counter_label)

	# Sort button
	var sort_button = Button.new()
	sort_button.name = "SortButton"
	sort_button.text = "Sort"
	sort_button.custom_minimum_size = Vector2(50, 24)
	sort_button.add_theme_font_size_override("font_size", 12)

	# Style the button to match UI theme
	var sort_btn_style = StyleBoxFlat.new()
	sort_btn_style.bg_color = Color(0.2, 0.2, 0.24, 0.9)
	sort_btn_style.border_color = BORDER_COLOR
	sort_btn_style.set_border_width_all(1)
	sort_btn_style.set_corner_radius_all(4)
	sort_button.add_theme_stylebox_override("normal", sort_btn_style)

	var sort_btn_hover = sort_btn_style.duplicate()
	sort_btn_hover.bg_color = Color(0.28, 0.28, 0.32, 0.95)
	sort_button.add_theme_stylebox_override("hover", sort_btn_hover)

	var sort_btn_pressed = sort_btn_style.duplicate()
	sort_btn_pressed.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	sort_button.add_theme_stylebox_override("pressed", sort_btn_pressed)

	sort_button.add_theme_color_override("font_color", TEXT_COLOR)
	sort_button.add_theme_color_override("font_hover_color", Color.WHITE)
	sort_button.pressed.connect(_on_sort_pressed)
	bottom_bar.add_child(sort_button)

	add_child(main_panel)

func create_inventory_slot(slot_index: int) -> Control:
	"""Create a single inventory slot button with drag-drop support"""
	var slot_control = Control.new()
	slot_control.name = "InvSlot_" + str(slot_index)
	slot_control.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot_control.size = Vector2(SLOT_SIZE, SLOT_SIZE)  # Explicitly set size for child positioning
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP  # Ensure we receive input
	slot_control.set_meta("slot_index", slot_index)
	slot_control.set_meta("slot_type", "inventory")

	# Enable drag-drop
	slot_control.set_drag_forwarding(
		Callable(self, "_get_inventory_drag_data").bind(slot_index),
		Callable(self, "_can_drop_inventory_data").bind(slot_index),
		Callable(self, "_drop_inventory_data").bind(slot_index)
	)

	# Add panel for styling
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_control.add_child(panel)

	var slot_style_normal = create_slot_style(SLOT_BG, BORDER_INNER, 2)
	panel.add_theme_stylebox_override("panel", slot_style_normal)

	# Center container for icon
	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)

	# Add icon texture rect (scaled to fit most of the slot)
	var icon = TextureRect.new()
	icon.name = "ItemIcon"
	icon.custom_minimum_size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)  # Icon fills most of slot
	icon.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)  # Force size
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false  # Hidden until we have an icon
	center.add_child(icon)

	# Add label for item text (fallback when no icon)
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
	center.add_child(label)

	# Stack count label (bottom-right corner) - uses absolute positioning
	var stack_label = Label.new()
	stack_label.name = "StackLabel"
	stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	stack_label.add_theme_font_size_override("font_size", 10)
	stack_label.add_theme_color_override("font_color", Color.WHITE)
	stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
	stack_label.add_theme_constant_override("outline_size", 2)
	stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position at bottom-right corner (absolute positioning)
	# SLOT_SIZE is 54, label needs ~30px width for "x99", positioned inside the border
	stack_label.position = Vector2(SLOT_SIZE - 34, SLOT_SIZE - 23)  # x=20, y=31 for 54px slot
	stack_label.size = Vector2(30, 14)
	stack_label.visible = false
	stack_label.z_index = 10  # Ensure it's on top
	slot_control.add_child(stack_label)

	# Forged badge (top-left corner) - shows for forged items
	# Added to slot_control (not panel) so it's on top of everything
	var forged_badge = TextureRect.new()
	forged_badge.name = "ForgedBadge"
	var forge_badge_tex = load("res://assets/ui/forge_icon.png")
	if forge_badge_tex:
		forged_badge.texture = forge_badge_tex
	forged_badge.custom_minimum_size = Vector2(18, 18)
	forged_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	forged_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	forged_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forged_badge.z_index = 10  # On top of everything
	forged_badge.position = Vector2(1, 1)  # Top-left with small padding
	forged_badge.visible = false
	slot_control.add_child(forged_badge)

	# Connect click event
	slot_control.gui_input.connect(_on_inventory_slot_gui_input.bind(slot_index))

	# Connect hover events for F key inspection
	slot_control.mouse_entered.connect(_on_slot_mouse_entered.bind(slot_index))
	slot_control.mouse_exited.connect(_on_slot_mouse_exited)

	return slot_control

func create_header_label(text: String, size: int = 18) -> Label:
	"""Create a header label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", HEADER_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func create_text_label(text: String, size: int = 14) -> Label:
	"""Create a standard text label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	return label

func create_styled_separator() -> Control:
	"""Create a styled separator line"""
	var separator_container = MarginContainer.new()
	separator_container.add_theme_constant_override("margin_top", 8)
	separator_container.add_theme_constant_override("margin_bottom", 8)
	separator_container.add_theme_constant_override("margin_left", 20)
	separator_container.add_theme_constant_override("margin_right", 20)

	var separator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 2)

	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = BORDER_COLOR
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", sep_style)

	separator_container.add_child(separator)
	return separator_container

func create_slot_style(bg_color: Color, border_color: Color = BORDER_COLOR, border_width: int = 2, use_glow: bool = false) -> StyleBoxFlat:
	"""Create style for inventory slots"""
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

func create_inner_panel_style() -> StyleBoxFlat:
	"""Create style for inner panels"""
	var style = StyleBoxFlat.new()
	style.bg_color = SLOT_BG
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = BORDER_INNER
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.shadow_size = 4
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func get_rarity_glow_color(rarity_str: String) -> Color:
	"""Get glow color for item rarity - brighter/more saturated for visibility"""
	match rarity_str.to_upper():
		"COMMON":
			return Color(0.5, 0.5, 0.5, 1.0)  # Gray
		"UNCOMMON":
			return Color(0.2, 0.9, 0.2, 1.0)  # Bright green
		"RARE":
			return Color(0.3, 0.5, 1.0, 1.0)  # Bright blue
		"EPIC":
			return Color(0.8, 0.3, 1.0, 1.0)  # Bright purple
		"LEGENDARY":
			return Color(1.0, 0.6, 0.1, 1.0)  # Bright orange
		"ARTIFACT":
			return Color(1.0, 0.85, 0.2, 1.0)  # Bright gold
		_:
			return BORDER_INNER

# ============================================
# INVENTORY SORTING
# ============================================

# Rarity order (higher = better, sorted first)
const RARITY_ORDER = {
	"ARTIFACT": 6,
	"LEGENDARY": 5,
	"EPIC": 4,
	"RARE": 3,
	"UNCOMMON": 2,
	"COMMON": 1,
}

# Item type order (grouped together)
const TYPE_ORDER = {
	"weapon": 1,
	"armor": 2,
	"tool": 3,
	"consumable": 4,
	"material": 5,
	"misc": 6,
}

func _on_sort_pressed() -> void:
	"""Sort inventory by rarity (best first) then by item type"""
	SoundManager.play_button_click_sound()
	_sort_inventory()
	refresh_all()

func _sort_inventory() -> void:
	"""Sort all inventory items - rarity descending, then type, then name"""
	# Collect all non-empty items
	var items_with_indices: Array = []
	for i in range(InventorySystem.inventory_items.size()):
		var item = InventorySystem.inventory_items[i]
		if item != null and not item.is_empty():
			items_with_indices.append(item.duplicate())

	# Sort items
	items_with_indices.sort_custom(_compare_items)

	# Clear inventory and re-add sorted items
	for i in range(InventorySystem.inventory_items.size()):
		InventorySystem.inventory_items[i] = null

	for i in range(items_with_indices.size()):
		InventorySystem.inventory_items[i] = items_with_indices[i]

	# Emit signal so other UIs update
	InventorySystem.inventory_changed.emit()

func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	"""Compare two items for sorting. Returns true if a should come before b."""
	# Get rarity values (higher = better = comes first)
	var rarity_a = RARITY_ORDER.get(a.get("rarity", "COMMON").to_upper(), 0)
	var rarity_b = RARITY_ORDER.get(b.get("rarity", "COMMON").to_upper(), 0)

	# Sort by rarity descending (best first)
	if rarity_a != rarity_b:
		return rarity_a > rarity_b

	# Same rarity - sort by item type
	var type_a = TYPE_ORDER.get(a.get("type", "misc").to_lower(), 99)
	var type_b = TYPE_ORDER.get(b.get("type", "misc").to_lower(), 99)

	if type_a != type_b:
		return type_a < type_b

	# Same type - sort alphabetically by name
	var name_a = a.get("name", "").to_lower()
	var name_b = b.get("name", "").to_lower()
	return name_a < name_b

func toggle_ui() -> void:
	"""Toggle inventory UI visibility"""
	is_visible = !is_visible
	visible = is_visible

	# Play inventory open/close sound
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_inventory_open_sound()

	if is_visible:
		refresh_all()
		# Notify tutorial system
		if TutorialManager:
			TutorialManager.on_inventory_opened()
	else:
		# Notify tutorial system inventory closed
		if TutorialManager:
			TutorialManager.on_inventory_closed()

func refresh_all() -> void:
	"""Refresh all UI elements"""
	refresh_inventory()
	refresh_gold()
	refresh_slot_counter()

func refresh_gold() -> void:
	"""Update gold display"""
	if gold_label:
		gold_label.text = "%d" % CharacterStats.gold

func refresh_slot_counter() -> void:
	"""Update slot counter (X/100)"""
	if slot_counter_label:
		var item_count = 0
		for item in InventorySystem.inventory_items:
			if item != null:
				item_count += 1
		slot_counter_label.text = "%d/%d" % [item_count, InventorySystem.MAX_INVENTORY_SLOTS]

func refresh_inventory() -> void:
	"""Update inventory slot displays"""
	for i in range(inventory_slots.size()):
		var slot_control = inventory_slots[i]
		var item = InventorySystem.get_item(i)

		var panel = slot_control.get_child(0) if slot_control.get_child_count() > 0 else null
		if not panel:
			continue

		# Get icon, label, and stack label nodes
		var icon_rect: TextureRect = null
		var label: Label = null
		var stack_label: Label = null

		# Try new structure: Panel > CenterContainer > ItemIcon/ItemLabel
		var center = panel.get_node_or_null("CenterContainer")
		if center:
			icon_rect = center.get_node_or_null("ItemIcon")
			label = center.get_node_or_null("ItemLabel")

		# Stack label is directly under slot_control (not panel)
		stack_label = slot_control.get_node_or_null("StackLabel")

		# Fallback: search recursively
		if not label:
			label = _find_node_recursive(panel, "ItemLabel")
		if not icon_rect:
			icon_rect = _find_node_recursive(panel, "ItemIcon")
		if not stack_label:
			stack_label = _find_node_recursive(panel, "StackLabel")

		if not label:
			print("⚠️ InventoryUI: Could not find ItemLabel in slot %d" % i)
			continue

		# IMPORTANT: Reset slot state first to prevent visual artifacts during rapid updates
		# This ensures we start from a clean state before applying new content
		if icon_rect:
			icon_rect.texture = null
			icon_rect.visible = false
		label.text = ""
		label.visible = false
		if stack_label:
			stack_label.visible = false
			stack_label.text = ""
		var forged_badge = slot_control.get_node_or_null("ForgedBadge")
		if forged_badge:
			forged_badge.visible = false

		if item and item.size() > 0:
			var item_name = item.get("name", "???")
			var quantity = item.get("quantity", 1)
			var is_stackable = item.get("stackable", false)
			var is_forged = item.get("is_forged", false)

			if DEBUG_FORGED_DISPLAY and is_forged:
				print("[InventoryUI] ────────────────────────────────────")
				print("[InventoryUI] Slot %d: FORGED item '%s'" % [i, item_name])
				print("[InventoryUI]   type: %s, weapon_type: %s" % [item.get("type", "?"), item.get("weapon_type", "?")])
				print("[InventoryUI]   glow_color: %s, rarity: %s" % [item.get("glow_color", "none"), item.get("rarity", "?")])
				print("[InventoryUI]   effect_name: %s, effort_tier: %s" % [item.get("effect_name", "none"), item.get("effort_tier", "?")])

			# Try to get icon from ItemIconGenerator
			var icon_texture: Texture2D = null
			if ItemIconGenerator:
				icon_texture = ItemIconGenerator.get_item_icon(item)
				if DEBUG_FORGED_DISPLAY and is_forged:
					print("[InventoryUI]   Icon loaded: %s" % ("✅ Yes" if icon_texture else "❌ No"))

			if icon_texture and icon_rect:
				# We have an icon - show it
				icon_rect.texture = icon_texture
				icon_rect.visible = true
				label.visible = false
				label.text = ""
				# Show stack count in bottom-right corner
				if stack_label:
					if is_stackable and quantity > 1:
						stack_label.visible = true
						stack_label.text = "x%d" % quantity
					else:
						stack_label.visible = false
						stack_label.text = ""
			else:
				# No icon - show text name
				if icon_rect:
					icon_rect.visible = false
				label.visible = true
				if is_stackable and quantity > 1:
					label.text = "%s\nx%d" % [item_name, quantity]
				else:
					label.text = item_name
				if stack_label:
					stack_label.visible = false

			var rarity = item.get("rarity", "COMMON")
			# is_forged already declared above

			# DEBUG: Print rarity info for all items
			if DEBUG_FORGED_DISPLAY:
				print("[InventoryUI] Item '%s' rarity='%s' is_forged=%s" % [item_name, rarity, is_forged])

			# Determine glow color - use custom glow_color for forged items if available
			# BUT ignore white (#ffffff) since that's not a good border color - use rarity instead
			var glow_color: Color
			if is_forged and item.has("glow_color"):
				var glow_str = item.get("glow_color", "")
				if DEBUG_FORGED_DISPLAY:
					print("[InventoryUI]   glow_str from item: '%s'" % glow_str)
				# Ignore white glow colors - fall back to rarity
				if glow_str.begins_with("#") and glow_str.to_lower() != "#ffffff" and glow_str.to_lower() != "#fff":
					glow_color = Color.from_string(glow_str, get_rarity_glow_color(rarity))
					if DEBUG_FORGED_DISPLAY:
						print("[InventoryUI]   Parsed glow_color: %s" % glow_color)
				else:
					glow_color = get_rarity_glow_color(rarity)
					if DEBUG_FORGED_DISPLAY:
						print("[InventoryUI]   Using rarity glow (white/invalid glow_color): %s" % glow_color)
			else:
				glow_color = get_rarity_glow_color(rarity)
				if DEBUG_FORGED_DISPLAY:
					print("[InventoryUI]   Using rarity glow (no glow_color field): %s" % glow_color)

			# DEBUG: Print final glow color
			if DEBUG_FORGED_DISPLAY:
				print("[InventoryUI]   Final border color: %s" % glow_color)

			var glow_style = create_slot_style(SLOT_BG, glow_color, 3, true)
			panel.add_theme_stylebox_override("panel", glow_style)

			# Show forged badge if applicable (already got reference during reset phase)
			if forged_badge:
				forged_badge.visible = is_forged
				if DEBUG_FORGED_DISPLAY and is_forged:
					print("[InventoryUI]   ForgedBadge visible: %s" % forged_badge.visible)

			# Build tooltip with item name first
			var tooltip = "[%s]\n" % item_name
			if is_forged:
				tooltip = "[FORGED] %s\n" % item_name

			var desc = item.get("description", "")
			if desc:
				tooltip += desc

			if item.get("type") == "weapon":
				if item.has("base_damage"):
					var base_dmg = item.get("base_damage", 0)
					if base_dmg is Dictionary:
						tooltip += "\nDamage: +%d-%d" % [int(base_dmg.get("min", 0)), int(base_dmg.get("max", 0))]
					elif item.has("damage_min") and item.has("damage_max"):
						tooltip += "\nDamage: +%d-%d" % [int(item.get("damage_min")), int(item.get("damage_max"))]
					else:
						tooltip += "\nDamage: +%.1f" % base_dmg
				if item.has("attack_speed_bonus"):
					var speed_bonus = item.get("attack_speed_bonus", 0.0)
					if speed_bonus != 0:
						tooltip += "\nAttack Speed: %+.1f%%" % (speed_bonus * 100)

			if item.has("defense"):
				tooltip += "\nDefense: +%d" % item.get("defense", 0)

			# Display stat bonuses (STR, VIT, DEX, AGI, INT, WIS)
			if item.has("stat_bonuses"):
				var bonuses = item.get("stat_bonuses", {})
				var stat_parts = []
				if bonuses.get("str", 0) > 0:
					stat_parts.append("+%d STR" % bonuses.get("str"))
				if bonuses.get("vit", 0) > 0:
					stat_parts.append("+%d VIT" % bonuses.get("vit"))
				if bonuses.get("dex", 0) > 0:
					stat_parts.append("+%d DEX" % bonuses.get("dex"))
				if bonuses.get("agi", 0) > 0:
					stat_parts.append("+%d AGI" % bonuses.get("agi"))
				if bonuses.get("int", 0) > 0:
					stat_parts.append("+%d INT" % bonuses.get("int"))
				if bonuses.get("wis", 0) > 0:
					stat_parts.append("+%d WIS" % bonuses.get("wis"))
				if stat_parts.size() > 0:
					tooltip += "\n" + ", ".join(stat_parts)

			# Display accessory bonuses
			if item.has("hp_bonus"):
				tooltip += "\nHP: +%d" % item.get("hp_bonus", 0)

			if item.has("value"):
				tooltip += "\nValue: %d G" % item.get("value", 0)

			# Add forged-specific info - use ForgeItemDB ability lookup
			if is_forged:
				var forged_item_id = item.get("item_id", item.get("forged_item_id", item.get("forged_id", "")))
				if forged_item_id != "" and ForgeItemDB and ForgeItemDB.has_abilities(forged_item_id):
					var passive_name = ForgeItemDB.get_passive_ability_name(forged_item_id)
					var active_name = ForgeItemDB.get_active_ability_name(forged_item_id)
					if passive_name != "":
						tooltip += "\nPassive: %s" % passive_name
					if active_name != "":
						tooltip += "\nActive: %s" % active_name
				else:
					# Fallback to legacy effect_name
					var effect_name = item.get("effect_name", "")
					if effect_name != "":
						tooltip += "\nEffect: %s" % effect_name
				var effort_tier = item.get("effort_tier", "")
				if effort_tier != "":
					tooltip += "\nTier: %s" % effort_tier

			# Add click-and-hold hint for all items
			tooltip += "\n\n[Click and hold for details]"

			slot_control.tooltip_text = tooltip
		else:
			# Empty slot - most state already reset above, just set tooltip and style
			slot_control.tooltip_text = "Empty slot"
			var default_style = create_slot_style(SLOT_BG, BORDER_INNER, 2)
			panel.add_theme_stylebox_override("panel", default_style)

func _on_slot_mouse_entered(slot_index: int) -> void:
	"""Track which slot the mouse is hovering over (for tooltips)"""
	pass  # Just for tooltip system

func _on_slot_mouse_exited() -> void:
	"""Cancel radial when mouse leaves slot"""
	_cancel_long_hold()

func _on_inventory_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	"""Handle GUI input on inventory slot (click-and-hold to inspect, double-click/right-click to equip/use)"""
	if event is InputEventMouseButton:
		if event.pressed:
			# Double-click to equip/use
			if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				_cancel_long_hold()  # Cancel any ongoing hold
				_equip_or_use_item(slot_index)
			# Right-click - add to trade if trading, otherwise equip/use
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_long_hold()  # Cancel any ongoing hold
				if TradeWindowUI and TradeWindowUI.is_trading:
					_add_item_to_trade(slot_index)
				else:
					_equip_or_use_item(slot_index)
			# Single left-click starts hold timer for inspection
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_start_long_hold(slot_index)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Mouse button released - cancel hold
			_cancel_long_hold()

func _equip_or_use_item(slot_index: int) -> void:
	"""Equip or use item at slot index"""
	var item = InventorySystem.get_item(slot_index)

	if item and item.size() > 0:
		if DEBUG_EQUIP:
			print("[Equip] Inventory slot %d: %s (type=%s, slot=%s)" % [slot_index, item.get("name", "?"), item.get("type", ""), item.get("slot", "")])

		# Check if it's a placeable item (like Campfire Kit)
		if item.get("type", "") == "placeable":
			use_placeable_item(item, slot_index)
			return

		# Check if it's a tool
		if item.get("type", "") == "tool":
			var tool_type = item.get("tool_type", "")
			var equipped = false

			if tool_type == "axe":
				equipped = InventorySystem.equip_axe(item)
			elif tool_type == "pickaxe":
				equipped = InventorySystem.equip_pickaxe(item)

			if equipped:
				InventorySystem.remove_item(slot_index)
				SoundManager.play_equip_sound()
				refresh_all()
		# Check if it's a weapon
		# DEBUG: Print item data to trace equip issues after login
		var is_weapon = item.get("type", "") == "weapon" and item.get("slot", "") == "mainhand"
		if DEBUG_EQUIP and not is_weapon and item.get("weapon_type", "") != "":
			# Only log weapons that aren't being recognized
			print("[Equip] NOT equippable as weapon: %s" % item.get("name", "Unknown"))
			print("[Equip] Item type='%s', slot='%s', weapon_type='%s'" % [item.get("type", "MISSING"), item.get("slot", "MISSING"), item.get("weapon_type", "MISSING")])
			print("[Equip] Full item keys: %s" % str(item.keys()))
		if is_weapon:
			var weapon = dict_to_weapon(item)
			if weapon:
				# If there's already a weapon equipped, do a direct swap
				if CharacterStats.equipped_weapon:
					if DEBUG_EQUIP:
						print("[Equip] Swapping weapons - %s for %s" % [CharacterStats.equipped_weapon.weapon_name, weapon.weapon_name])
					# Get the old weapon data before clearing it
					var old_weapon_dict = CharacterStats.get_equipped_weapon_data()
					if old_weapon_dict.is_empty():
						old_weapon_dict = CharacterStats.get_weapon_as_dict()

					# Clear the equipped weapon without adding to inventory
					CharacterStats.equipped_weapon = null
					CharacterStats.equipped_weapon_data = {}
					CharacterStats.weapon_unequipped.emit()

					# Remove new weapon from inventory slot and put old weapon there
					InventorySystem.set_item(slot_index, old_weapon_dict)

					# Equip the new weapon
					CharacterStats.equip_weapon(weapon, item)
				else:
					# No weapon equipped, just equip normally
					CharacterStats.equip_weapon(weapon, item)
					InventorySystem.remove_item(slot_index)

				SoundManager.play_equip_sound()
				refresh_all()
				# Notify tutorial system
				if TutorialManager:
					TutorialManager.on_item_equipped(item)
		# Check if it's armor, ring, or amulet
		elif item.has("slot"):
			var target_slot = item.get("slot", "")
			var item_type = item.get("type", item.get("item_type", ""))

			# Special handling for rings: can go to either ring1 or ring2
			if target_slot == "ring" or item_type == "ring":
				# Try ring1 first, then ring2
				if CharacterStats.equipped_armor["ring1"] == null:
					var ring_item = item.duplicate()
					ring_item["slot"] = "ring1"
					if CharacterStats.equip_armor(ring_item):
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
						if TutorialManager:
							TutorialManager.on_item_equipped(item)
					return
				elif CharacterStats.equipped_armor["ring2"] == null:
					var ring_item = item.duplicate()
					ring_item["slot"] = "ring2"
					if CharacterStats.equip_armor(ring_item):
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
						if TutorialManager:
							TutorialManager.on_item_equipped(item)
					return
				else:
					# Both ring slots occupied - swap with ring1
					var old_ring = CharacterStats.equipped_armor["ring1"]
					if old_ring:
						InventorySystem.set_item(slot_index, old_ring)
					CharacterStats.equipped_armor["ring1"] = null
					var ring_item = item.duplicate()
					ring_item["slot"] = "ring1"
					if CharacterStats.equip_armor(ring_item):
						InventorySystem.remove_item(slot_index)
						SoundManager.play_equip_sound()
						refresh_all()
						if TutorialManager:
							TutorialManager.on_item_equipped(item)
					return

			# Normal armor/amulet equip (slot matches equipment slot name)
			if target_slot in CharacterStats.equipped_armor:
				if CharacterStats.equip_armor(item):
					InventorySystem.remove_item(slot_index)
					SoundManager.play_equip_sound()
					refresh_all()
					# Notify tutorial system
					if TutorialManager:
						TutorialManager.on_item_equipped(item)

func _add_item_to_trade(slot_index: int) -> void:
	"""Add item from inventory slot to trade window (right-click while trading)"""
	# Can't add items if offer is locked
	if TradeWindowUI.my_locked:
		if NotificationManager:
			NotificationManager.show_notification("Unlock your offer first", "INFO")
		return

	# Check if this slot is already in trade
	if slot_index >= 0 and slot_index < inventory_slots.size():
		var slot = inventory_slots[slot_index]
		if slot and slot.get_meta("in_trade", false):
			if NotificationManager:
				NotificationManager.show_notification("Item already in trade", "INFO")
			return

	var item = InventorySystem.get_item(slot_index)
	if not item or item.is_empty():
		return

	# Only forged items can be traded (check is_forged flag, not token_id)
	if not item.get("is_forged", false):
		if NotificationManager:
			NotificationManager.show_notification("Only forged items can be traded", "INFO")
		return

	# Get token_id - can be 0 for unminted items, use forged_id as backup
	var token_id = item.get("token_id", 0)
	if token_id is float:
		token_id = int(token_id)
	# forged_id is the string version (token_id or item_id)
	var forged_id = item.get("forged_id", str(token_id) if token_id > 0 else item.get("item_id", ""))

	# Check if this item is already in the trade (by forged_id since token_id can be 0)
	for offered_id in TradeWindowUI.my_offered_items:
		if str(offered_id) == forged_id:
			if NotificationManager:
				NotificationManager.show_notification("Item already in trade", "INFO")
			return

	# Find an empty slot in the trade grid
	var empty_slot: PanelContainer = null
	for slot in TradeWindowUI.my_items_grid.get_children():
		var slot_token = slot.get_meta("item_token_id", -1)
		if slot_token <= 0:
			empty_slot = slot
			break

	if not empty_slot:
		if NotificationManager:
			NotificationManager.show_notification("Trade slots full", "INFO")
		return

	# Build item data for trade slot - use actual token_id if > 0, otherwise use item_id hash
	var trade_token = token_id if token_id > 0 else hash(forged_id)
	var trade_item = {
		"token_id": trade_token,
		"item_name": item.get("name", "???"),
		"item_rarity": item.get("rarity", "COMMON").to_upper(),
		"item_type": item.get("type", "weapon"),
		"forged_id": forged_id,
		"item_id": item.get("item_id", forged_id),  # Item catalog ID for ForgeItemDB lookup
		# Equipment slot (mainhand, chest, head, etc.)
		"slot": item.get("slot", ""),
		# Weapon-specific fields
		"weapon_type": item.get("weapon_type", ""),
		"damage": item.get("damage", 0),
		"attack_speed": item.get("attack_speed", 1.0),
		"two_handed": item.get("two_handed", false),
		# Gun-specific fields (for ranged weapons)
		"gun_subtype": item.get("gun_subtype", ""),
		"burst_count": item.get("burst_count", 1),
		"burst_delay": item.get("burst_delay", 0.0),
		# Achievement reference
		"achievement_id": item.get("achievement_id", ""),
		# Provenance fields (for ItemInspectionUI)
		"forger_name": item.get("forger_name", item.get("original_forger", "")),
		"original_forger": item.get("original_forger", item.get("forger_name", "")),
		"forged_at": item.get("forged_at", ""),
		"trade_count": item.get("trade_count", 0),
		"game": item.get("game", ""),
		"achievement_name": item.get("achievement_name", item.get("achievement", "")),
		"source_provider": item.get("source_provider", ""),
	}

	# Add to trade slot (pass inventory slot for tracking)
	TradeWindowUI._add_item_to_slot(empty_slot, trade_item, slot_index)

	# Mark this inventory slot as "in trade" - visually dim it
	_mark_slot_in_trade(slot_index, true)

	if NotificationManager:
		NotificationManager.show_notification("Added %s to trade" % item.get("name", "item"), "INFO")

func _mark_slot_in_trade(slot_index: int, in_trade: bool) -> void:
	"""Mark an inventory slot as in trade (visually dim it)"""
	if slot_index < 0 or slot_index >= inventory_slots.size():
		return

	var slot = inventory_slots[slot_index]
	if not slot:
		return

	if in_trade:
		# Dim the slot to show it's in trade
		slot.modulate = Color(0.5, 0.5, 0.5, 0.6)
		slot.set_meta("in_trade", true)
	else:
		# Restore normal appearance
		slot.modulate = Color(1, 1, 1, 1)
		slot.set_meta("in_trade", false)

# ============================================
# MOUSE CLICK-AND-HOLD RADIAL SYSTEM
# ============================================

func _start_long_hold(slot_index: int) -> void:
	"""Start long-hold timer with cursor-following radial progress indicator"""
	_cancel_long_hold()
	_long_hold_slot_index = slot_index
	_long_hold_start_time = Time.get_ticks_msec() / 1000.0

	_long_hold_timer = Timer.new()
	_long_hold_timer.wait_time = LONG_HOLD_DURATION
	_long_hold_timer.one_shot = true
	_long_hold_timer.timeout.connect(_on_long_hold_triggered)
	add_child(_long_hold_timer)
	_long_hold_timer.start()

	# Create cursor-following radial progress indicator
	_radial_progress = _create_radial_progress()
	add_child(_radial_progress)

func _cancel_long_hold() -> void:
	"""Cancel long-hold timer and hide radial progress"""
	if _long_hold_timer:
		_long_hold_timer.stop()
		_long_hold_timer.queue_free()
		_long_hold_timer = null
	if _radial_progress:
		_radial_progress.queue_free()
		_radial_progress = null
	_long_hold_slot_index = -1
	_long_hold_start_time = 0.0

func _create_radial_progress() -> Control:
	"""Create a cursor-following radial progress indicator"""
	var radial = Control.new()
	radial.custom_minimum_size = Vector2(48, 48)
	radial.size = Vector2(48, 48)
	radial.z_index = 100
	radial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial.set_meta("progress", 0.0)

	radial.draw.connect(func():
		var progress = radial.get_meta("progress", 0.0)
		var center = Vector2(24, 24)
		var radius = 18.0
		var inner_radius = 12.0

		# Dark backdrop disc
		radial.draw_circle(center, radius + 4, Color(0.0, 0.0, 0.0, 0.6))

		# Inner dark circle
		radial.draw_circle(center, inner_radius, Color(0.08, 0.08, 0.1, 0.9))

		# Track ring (subtle)
		radial.draw_arc(center, radius, 0, TAU, 48, Color(0.3, 0.3, 0.35, 0.5), 4.0)

		# Progress arc with glow effect
		if progress > 0:
			var start_angle = -PI/2
			var end_angle = -PI/2 + (progress * TAU)

			# Outer glow
			radial.draw_arc(center, radius, start_angle, end_angle, 48, Color(1.0, 0.75, 0.2, 0.3), 8.0)
			# Main arc
			radial.draw_arc(center, radius, start_angle, end_angle, 48, Color(1.0, 0.85, 0.3, 1.0), 4.0)
			# Inner bright edge
			radial.draw_arc(center, radius - 1, start_angle, end_angle, 48, Color(1.0, 0.95, 0.6, 0.8), 1.5)

			# Tip indicator dot
			var tip_pos = center + Vector2(cos(end_angle), sin(end_angle)) * radius
			radial.draw_circle(tip_pos, 4.0, Color(1.0, 0.95, 0.7, 1.0))
			radial.draw_circle(tip_pos, 2.5, Color(1.0, 1.0, 1.0, 1.0))

		# Center icon (magnifying glass hint)
		var icon_color = Color(0.6, 0.6, 0.65, 0.8) if progress == 0 else Color(1.0, 0.9, 0.5, 1.0)
		radial.draw_arc(center + Vector2(-2, -2), 5.0, 0, TAU, 16, icon_color, 1.5)
		radial.draw_line(center + Vector2(2, 2), center + Vector2(6, 6), icon_color, 1.5)
	)

	return radial

func _on_long_hold_triggered() -> void:
	"""Called when long-hold duration reached - open inspection panel"""
	var slot_index = _long_hold_slot_index
	_cancel_long_hold()

	if slot_index < 0:
		return

	var item = InventorySystem.get_item(slot_index)
	if item and not item.is_empty():
		_open_item_inspection(item)

func _open_inspection_for_slot(slot_index: int) -> void:
	"""Open inspection panel for item in slot"""
	var item = InventorySystem.get_item(slot_index)
	if item and not item.is_empty():
		_open_item_inspection(item)

func _open_item_inspection(item_data: Dictionary) -> void:
	"""Open the item inspection panel"""
	var inspection_ui = get_tree().get_first_node_in_group("item_inspection_ui")
	if not inspection_ui:
		inspection_ui = get_node_or_null("/root/ItemInspectionUI")

	if not inspection_ui:
		var InspectionUIScene = load("res://scripts/ui/ItemInspectionUI.gd")
		if InspectionUIScene:
			inspection_ui = InspectionUIScene.new()
			inspection_ui.add_to_group("item_inspection_ui")
			get_tree().root.add_child(inspection_ui)

	if inspection_ui:
		inspection_ui.inspect_item(item_data)

func dict_to_weapon(item_dict: Dictionary) -> Weapon:
	"""Convert a weapon dictionary to a Weapon resource"""
	var weapon = Weapon.new()

	weapon.weapon_name = item_dict.get("name", "Unknown")
	weapon.weapon_type = item_dict.get("weapon_type", "sword")
	weapon.damage_type = "unified"
	weapon.description = item_dict.get("description", "")

	# Handle base_damage - can be a number or a Dictionary with min/max
	var base_damage = item_dict.get("base_damage", 5.0)
	if base_damage is Dictionary:
		# Use average of min/max for the weapon's base damage
		var dmg_min = base_damage.get("min", 5)
		var dmg_max = base_damage.get("max", 5)
		weapon.damage_min = float(dmg_min)
		weapon.damage_max = float(dmg_max)
		weapon.base_damage = (dmg_min + dmg_max) / 2.0
	elif base_damage is float or base_damage is int:
		weapon.base_damage = float(base_damage)
		# Check for separate damage_min/damage_max fields
		if item_dict.has("damage_min") and item_dict.has("damage_max"):
			weapon.damage_min = float(item_dict.get("damage_min"))
			weapon.damage_max = float(item_dict.get("damage_max"))
	else:
		weapon.base_damage = 5.0

	# Healing weapon properties
	weapon.attack_mode = item_dict.get("attack_mode", "melee")
	weapon.healing_power = item_dict.get("healing_power", 0.0)
	weapon.heal_radius = item_dict.get("heal_radius", 80.0)

	# Gun weapon properties (use explicit null checks since .get() returns null if key exists with null value)
	weapon.gun_radius = item_dict.get("gun_radius") if item_dict.get("gun_radius") != null else 28.0
	weapon.gun_range = item_dict.get("gun_range") if item_dict.get("gun_range") != null else 550.0
	weapon.gun_subtype = item_dict.get("gun_subtype") if item_dict.get("gun_subtype") != null else "railgun"
	weapon.burst_count = item_dict.get("burst_count") if item_dict.get("burst_count") != null else 1
	weapon.burst_delay = item_dict.get("burst_delay") if item_dict.get("burst_delay") != null else 0.10

	var attack_speed_category = item_dict.get("attack_speed", "medium")
	match attack_speed_category:
		"fast":
			weapon.attack_speed_bonus = -0.30
		"slow":
			weapon.attack_speed_bonus = 0.30
		_:
			weapon.attack_speed_bonus = 0.0

	weapon.crit_chance_bonus = item_dict.get("crit_chance", 0.0)
	weapon.required_level = item_dict.get("required_level", 1)
	weapon.can_trade = item_dict.get("can_trade", true)
	weapon.sell_value = item_dict.get("value", 0)

	var rarity_str = item_dict.get("rarity", "COMMON").to_upper()
	match rarity_str:
		"COMMON":
			weapon.rarity = Weapon.Rarity.COMMON
		"UNCOMMON":
			weapon.rarity = Weapon.Rarity.UNCOMMON
		"RARE":
			weapon.rarity = Weapon.Rarity.RARE
		"EPIC":
			weapon.rarity = Weapon.Rarity.EPIC
		"LEGENDARY":
			weapon.rarity = Weapon.Rarity.LEGENDARY

	# Two-handed property - guns and bows are always two-handed (blocks offhand slot)
	var is_two_handed_type = weapon.weapon_type in ["gun", "rifle", "pistol", "shotgun", "railgun", "battle_rifle", "bow", "crossbow"]
	weapon.is_two_handed = item_dict.get("is_two_handed", is_two_handed_type)

	# Forged item properties - critical for proper icon/sprite loading
	weapon.is_forged = item_dict.get("is_forged", false)
	weapon.forged_id = item_dict.get("forged_item_id", item_dict.get("item_id", item_dict.get("forged_id", "")))

	return weapon

# ============================================
# DRAG AND DROP FUNCTIONS
# ============================================

func _get_inventory_drag_data(at_position: Vector2, slot_index: int) -> Variant:
	"""Start dragging an inventory item"""
	var item = InventorySystem.get_item(slot_index)
	if not item or item.is_empty():
		_current_drag_data = null
		return null
	var preview = Label.new()
	preview.text = item.get("name", "Item")
	preview.add_theme_font_size_override("font_size", 16)
	preview.add_theme_color_override("font_color", Color.GOLD)
	preview.modulate = Color(1, 1, 1, 0.8)

	var slot_control = inventory_slots[slot_index]
	slot_control.set_drag_preview(preview)

	var drag_data = {
		"source_type": "inventory",
		"source_index": slot_index,
		"item": item,
		"source_ui": "inventory_ui"
	}

	# Store for deletion detection when drag ends
	_current_drag_data = drag_data

	return drag_data

func _can_drop_inventory_data(at_position: Vector2, data: Variant, slot_index: int) -> bool:
	"""Check if data can be dropped on this inventory slot"""
	if not data is Dictionary:
		return false
	return data.has("item")

func _drop_inventory_data(at_position: Vector2, data: Dictionary, slot_index: int) -> void:
	"""Handle dropping data on an inventory slot"""
	if not data.has("item"):
		return

	# Clear drag data since this is a valid drop
	_current_drag_data = null

	var source_type = data.get("source_type", "")
	var source_index = data.get("source_index", -1)
	var dragged_item = data.get("item", {})

	if source_type == "inventory":
		# Swap inventory items
		if source_index != slot_index:
			var target_item = InventorySystem.get_item(slot_index)

			InventorySystem.set_item(source_index, {})
			InventorySystem.set_item(slot_index, {})

			InventorySystem.set_item(slot_index, dragged_item)
			if target_item and not target_item.is_empty():
				InventorySystem.set_item(source_index, target_item)

			SoundManager.play_inventory_move_sound()
			refresh_all()

	elif source_type == "equipment":
		# Move from equipment to inventory
		var source_slot_name = data.get("source_slot_name", "")
		if source_slot_name:
			if source_slot_name == "mainhand" and CharacterStats.equipped_weapon:
				CharacterStats.unequip_weapon()
				SoundManager.play_equip_sound()
				refresh_all()
			elif CharacterStats.unequip_armor(source_slot_name):
				SoundManager.play_equip_sound()
				refresh_all()

	elif source_type == "tool":
		# Move from tool slot to inventory
		var source_tool_name = data.get("source_tool_name", "")
		if source_tool_name == "axe":
			InventorySystem.unequip_axe()
			SoundManager.play_equip_sound()
			refresh_all()
		elif source_tool_name == "pickaxe":
			InventorySystem.unequip_pickaxe()
			SoundManager.play_equip_sound()
			refresh_all()

# ============================================
# ITEM DELETION (DROP OUTSIDE PANEL)
# ============================================

# Track the current drag data for deletion detection
var _current_drag_data: Variant = null

func _notification(what: int) -> void:
	# Detect when drag ends to check if item was dropped outside panel
	if what == NOTIFICATION_DRAG_END:
		_on_drag_ended()

func _on_drag_ended() -> void:
	"""Called when any drag operation ends - check if we should delete an item"""
	if not is_visible or not _current_drag_data:
		_current_drag_data = null
		return

	var data = _current_drag_data
	_current_drag_data = null

	# Only handle inventory items from this UI
	if not data is Dictionary or not data.has("item"):
		return
	if data.get("source_ui") != "inventory_ui":
		return

	# Check if mouse is outside the inventory panel
	var mouse_pos = get_viewport().get_mouse_position()
	if main_panel:
		var panel_rect = main_panel.get_global_rect()
		if not panel_rect.has_point(mouse_pos):
			# Dropped outside - prompt for deletion
			_prompt_delete_item(data)

func _prompt_delete_item(data: Dictionary) -> void:
	"""Show confirmation dialog for item deletion"""
	pending_delete_data = data

	var item = data.get("item", {})
	var item_name = item.get("name", "Unknown")
	var is_forged = item.get("is_forged", false)

	var dialog = get_node_or_null("DeleteConfirmDialog")
	if dialog:
		if is_forged:
			# Extra warning for forged items - this is permanent!
			dialog.dialog_text = "⚠️ WARNING: '%s' is a FORGED item!\n\nThis action is PERMANENT. The item will be transferred to the treasury and cannot be recovered without submitting a support ticket.\n\nAre you absolutely sure?" % item_name
		else:
			dialog.dialog_text = "Are you sure you want to delete '%s'?" % item_name
		dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if pending_delete_data.is_empty():
		return

	var source_type = pending_delete_data.get("source_type", "")
	var dragged_item = pending_delete_data.get("item", {})

	if source_type == "inventory":
		var source_index = pending_delete_data.get("source_index", -1)
		if source_index >= 0:
			# Check if this is a forged item - need to notify backend
			if dragged_item.get("is_forged", false):
				var token_id = dragged_item.get("token_id", 0)
				if token_id is float:
					token_id = int(token_id)
				if token_id > 0 and ForgeItemManager:
					# Destroy on backend first, then remove locally
					var result = await ForgeItemManager.destroy_item(token_id, "player_delete")
					if result.get("success", false):
						InventorySystem.remove_item(source_index)
						print("🗑️ Forged item destroyed: %s (token_id: %d)" % [dragged_item.get("name", "?"), token_id])
					else:
						# Backend rejected - don't delete locally
						print("❌ Failed to destroy forged item on backend - keeping in inventory")
						push_warning("Could not delete forged item - server rejected")
				else:
					# No token_id, just delete locally (shouldn't happen for real forged items)
					InventorySystem.remove_item(source_index)
			else:
				# Regular item - just delete locally
				InventorySystem.remove_item(source_index)
			refresh_all()

			# Trigger immediate save to prevent item coming back if user logs out quickly
			if DatabaseManager and DatabaseManager.current_username != "":
				DatabaseManager.save_current_player_state()

	pending_delete_data = {}

func _on_gold_changed(_amount: int, _total: int) -> void:
	refresh_gold()

func _on_inventory_changed() -> void:
	# Use deferred refresh to coalesce multiple rapid inventory changes
	# This prevents race conditions when rapidly equipping/unequipping items
	_schedule_refresh()

func _on_slots_expanded(new_count: int) -> void:
	"""Add new slot buttons when inventory expands"""
	var inv_grid = _find_node_recursive(main_panel, "InventoryGrid")
	if not inv_grid:
		return

	# Add new slots from current count to new count
	var current_ui_slots = inventory_slots.size()
	for i in range(current_ui_slots, new_count):
		var slot_button = create_inventory_slot(i)
		inv_grid.add_child(slot_button)
		inventory_slots.append(slot_button)

	# Refresh to update display
	_schedule_refresh()

func _schedule_refresh() -> void:
	"""Schedule a deferred refresh to coalesce rapid updates"""
	_needs_refresh = true
	if not _refresh_scheduled:
		_refresh_scheduled = true
		# Use call_deferred to process at the end of the current frame
		call_deferred("_do_deferred_refresh")

func _do_deferred_refresh() -> void:
	"""Perform the actual refresh after all signals have been processed"""
	_refresh_scheduled = false
	if _needs_refresh:
		_needs_refresh = false
		refresh_inventory()
		refresh_slot_counter()

func _find_node_recursive(parent: Node, node_name: String) -> Node:
	"""Recursively search for a node by name"""
	for child in parent.get_children():
		if child.name == node_name:
			return child
		var found = _find_node_recursive(child, node_name)
		if found:
			return found
	return null

# ============================================
# PLACEABLE ITEMS (Campfire Kit, etc)
# ============================================

func use_placeable_item(item: Dictionary, slot_index: int) -> void:
	"""Use a placeable item like Campfire Kit"""
	var placeable_type = item.get("placeable_type", "")

	if placeable_type == "campfire":
		place_campfire(item, slot_index)
	else:
		print("⚠️ Unknown placeable type: %s" % placeable_type)

func place_campfire(item: Dictionary, slot_index: int) -> void:
	"""Place a campfire at the player's location"""
	var player = get_tree().get_first_node_in_group(Constants.GROUP_PLAYER)
	if not player:
		print("❌ Cannot place campfire - no player found")
		return

	var player_pos = player.global_position
	var min_distance = item.get("min_ruins_distance", 1000.0)

	# Check distance from all ruins
	var game_world = get_tree().get_first_node_in_group("game_world")
	if not game_world:
		game_world = get_node_or_null("/root/GameWorld")

	if game_world and game_world.has_method("get") and "RUINS_POSITIONS" in game_world:
		var ruins_positions = game_world.RUINS_POSITIONS
		for ruins_key in ruins_positions:
			var ruins_data = ruins_positions[ruins_key]
			var ruins_pos = ruins_data.position if ruins_data is Dictionary else ruins_data
			var distance = player_pos.distance_to(ruins_pos)
			if distance < min_distance:
				print("❌ Too close to ruins! Must be at least %.0f pixels away (currently %.0f)" % [min_distance, distance])
				_show_placement_error("Too close to ruins! Move at least %.0f pixels away." % min_distance)
				return

	# Check distance from home campfire (can't place too close to spawn)
	var home_campfire_pos = Vector2(2000, 0)  # Default home campfire position
	var home_distance = player_pos.distance_to(home_campfire_pos)
	if home_distance < 500:
		print("❌ Too close to home campfire!")
		_show_placement_error("Too close to home campfire!")
		return

	# All checks passed - place the campfire
	var campfire_scene = load("res://scenes/world/placeable_campfire.tscn")
	if not campfire_scene:
		# Fallback to regular campfire scene if placeable doesn't exist
		campfire_scene = load("res://scenes/world/campfire.tscn")

	if not campfire_scene:
		print("❌ Could not load campfire scene!")
		return

	var campfire = campfire_scene.instantiate()
	campfire.global_position = player_pos
	campfire.name = "PlayerCampfire_%d" % Time.get_ticks_msec()

	# Mark as player-placed campfire (not community, starts unlit)
	if "is_community_campfire" in campfire:
		campfire.is_community_campfire = false
	if "starts_unlit" in campfire:
		campfire.starts_unlit = true
	if campfire.has_method("set_unlit"):
		campfire.set_unlit(true)

	# Mark as player-placed (allows owner to extinguish with X)
	if "is_player_placed" in campfire:
		campfire.is_player_placed = true
	if "placer_peer_id" in campfire:
		var peer_id = 1
		if multiplayer.has_multiplayer_peer():
			peer_id = multiplayer.get_unique_id()
		campfire.placer_peer_id = peer_id

	# Add to world
	if game_world:
		game_world.add_child(campfire)
	else:
		get_tree().root.add_child(campfire)

	# Consume the item
	var quantity = item.get("quantity", 1)
	if quantity > 1:
		item["quantity"] = quantity - 1
		InventorySystem.set_item(slot_index, item)
	else:
		InventorySystem.remove_item(slot_index)

	# Close inventory
	toggle_ui()

	# Play placement sound
	SoundManager.play_button_click_sound()

	print("🔥 Placed campfire at %s" % player_pos)

func _show_placement_error(message: String) -> void:
	"""Show a temporary error message for placement failures"""
	var notification_manager = get_node_or_null("/root/NotificationManager")
	if notification_manager and notification_manager.has_method("show_notification"):
		notification_manager.show_notification(message, "ERROR")
	else:
		print("⚠️ %s" % message)
