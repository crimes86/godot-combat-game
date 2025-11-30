extends Node

## Inventory System
## Autoload singleton managing player inventory and gold display
## Add to project.godot as "InventorySystem"

# ============================================
# INVENTORY DATA
# ============================================

const MAX_INVENTORY_SLOTS: int = 32  # 8 rows x 4 columns

var inventory_items: Array = []  # Array of item dictionaries
var suppress_signals: bool = false  # Flag to suppress signal emissions

# Tool slots - for gathering tools
var equipped_axe: Dictionary = {}  # Axe slot for tree chopping
var equipped_pickaxe: Dictionary = {}  # Pickaxe slot for rock mining

# ============================================
# SIGNALS
# ============================================

signal inventory_changed()
signal item_added(item: Dictionary)
signal item_removed(item: Dictionary, slot: int)
signal axe_equipped(axe: Dictionary)
signal axe_unequipped(axe: Dictionary)
signal pickaxe_equipped(pickaxe: Dictionary)
signal pickaxe_unequipped(pickaxe: Dictionary)

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	DebugConfig.debug_log("═══════════════════════════════════════")
	DebugConfig.debug_log("InventorySystem initialized")
	DebugConfig.debug_log("Max slots: %d" % MAX_INVENTORY_SLOTS)
	DebugConfig.debug_log("═══════════════════════════════════════")

	# Initialize empty inventory
	for i in range(MAX_INVENTORY_SLOTS):
		inventory_items.append(null)

# ============================================
# INVENTORY MANAGEMENT
# ============================================

func add_item(item: Dictionary) -> bool:
	"""Add an item to inventory (stacks if possible)"""
	var item_name = item.get("name", "Unknown")
	var is_stackable = item.get("stackable", false)
	var quantity = item.get("quantity", 1)
	var max_stack = item.get("max_stack", 1)

	# If stackable, try to add to existing stack first
	if is_stackable:
		for i in range(inventory_items.size()):
			var existing_item = inventory_items[i]
			if existing_item != null and existing_item.get("name") == item_name:
				var current_quantity = existing_item.get("quantity", 1)
				var space_available = max_stack - current_quantity

				if space_available > 0:
					var amount_to_add = min(quantity, space_available)
					existing_item["quantity"] = current_quantity + amount_to_add
					if not suppress_signals:
						# Emit item_added with the amount that was added (for quest tracking)
						var added_item = item.duplicate()
						added_item["quantity"] = amount_to_add
						item_added.emit(added_item)
						inventory_changed.emit()

					# If we added everything, we're done
					if amount_to_add >= quantity:
						return true

					# Otherwise, reduce quantity and continue looking for more stacks
					quantity -= amount_to_add

	# If not stackable or couldn't stack all, find empty slot
	for i in range(inventory_items.size()):
		if inventory_items[i] == null:
			# Create new item with remaining quantity
			var new_item = item.duplicate()
			new_item["quantity"] = quantity
			inventory_items[i] = new_item
			if not suppress_signals:
				item_added.emit(new_item)
				inventory_changed.emit()
			return true

	return false

func remove_item(slot: int) -> Dictionary:
	"""Remove item from specific slot"""
	if slot < 0 or slot >= inventory_items.size():
		return {}

	var item = inventory_items[slot]
	if item:
		inventory_items[slot] = null
		item_removed.emit(item, slot)
		inventory_changed.emit()
		return item

	return {}

func get_item(slot: int) -> Dictionary:
	"""Get item at specific slot (returns null if empty)"""
	if slot < 0 or slot >= inventory_items.size():
		return {}

	var item = inventory_items[slot]
	return item if item else {}

func set_item(slot: int, item: Dictionary) -> void:
	"""Set item at specific slot (use empty dict {} to clear slot)"""
	if slot < 0 or slot >= inventory_items.size():
		return

	if item.is_empty():
		inventory_items[slot] = null
	else:
		inventory_items[slot] = item

	inventory_changed.emit()

func has_empty_slot() -> bool:
	"""Check if there's any empty slot"""
	for item in inventory_items:
		if item == null:
			return true
	return false

func get_item_count() -> int:
	"""Return number of items in inventory"""
	var count = 0
	for item in inventory_items:
		if item != null:
			count += 1
	return count

# ============================================
# GOLD ACCESS (Proxy to CharacterStats)
# ============================================

func get_gold() -> int:
	"""Get current gold amount from CharacterStats"""
	return CharacterStats.gold

# ============================================
# DEBUG
# ============================================

func print_inventory() -> void:
	"""Debug: Print all inventory contents"""
	for i in range(inventory_items.size()):
		var item = inventory_items[i]

# ============================================
# TOOL SLOT MANAGEMENT
# ============================================

func equip_axe(axe: Dictionary) -> bool:
	"""Equip an axe to the axe slot"""
	if axe.is_empty():
		return false

	# Check if it's a valid axe
	if axe.get("type", "") != "tool" or axe.get("tool_type", "") != "axe":
		print("⚠️ Cannot equip non-axe item to axe slot")
		return false

	# If there's already an axe equipped, unequip it first
	if not equipped_axe.is_empty():
		if not unequip_axe():
			return false

	# Equip the new axe
	equipped_axe = axe.duplicate()
	axe_equipped.emit(axe)
	print("🪓 Equipped axe: ", axe.get("name", "Unknown"))
	return true

func unequip_axe() -> bool:
	"""Unequip the current axe and add it back to inventory"""
	if equipped_axe.is_empty():
		return false

	# Try to add axe back to inventory
	var axe_copy = equipped_axe.duplicate()
	if add_item(axe_copy):
		var old_axe = equipped_axe.duplicate()
		equipped_axe = {}
		axe_unequipped.emit(old_axe)
		print("🪓 Unequipped axe: ", old_axe.get("name", "Unknown"))
		return true
	else:
		print("⚠️ Cannot unequip axe - inventory full")
		return false

func equip_pickaxe(pickaxe: Dictionary) -> bool:
	"""Equip a pickaxe to the pickaxe slot"""
	if pickaxe.is_empty():
		return false

	# Check if it's a valid pickaxe
	if pickaxe.get("type", "") != "tool" or pickaxe.get("tool_type", "") != "pickaxe":
		print("⚠️ Cannot equip non-pickaxe item to pickaxe slot")
		return false

	# If there's already a pickaxe equipped, unequip it first
	if not equipped_pickaxe.is_empty():
		if not unequip_pickaxe():
			return false

	# Equip the new pickaxe
	equipped_pickaxe = pickaxe.duplicate()
	pickaxe_equipped.emit(pickaxe)
	print("⛏️ Equipped pickaxe: ", pickaxe.get("name", "Unknown"))
	return true

func unequip_pickaxe() -> bool:
	"""Unequip the current pickaxe and add it back to inventory"""
	if equipped_pickaxe.is_empty():
		return false

	# Try to add pickaxe back to inventory
	var pickaxe_copy = equipped_pickaxe.duplicate()
	if add_item(pickaxe_copy):
		var old_pickaxe = equipped_pickaxe.duplicate()
		equipped_pickaxe = {}
		pickaxe_unequipped.emit(old_pickaxe)
		print("⛏️ Unequipped pickaxe: ", old_pickaxe.get("name", "Unknown"))
		return true
	else:
		print("⚠️ Cannot unequip pickaxe - inventory full")
		return false

func has_axe_equipped() -> bool:
	"""Check if an axe is equipped"""
	return not equipped_axe.is_empty()

func has_pickaxe_equipped() -> bool:
	"""Check if a pickaxe is equipped"""
	return not equipped_pickaxe.is_empty()

func get_equipped_axe() -> Dictionary:
	"""Get the currently equipped axe"""
	return equipped_axe

func get_equipped_pickaxe() -> Dictionary:
	"""Get the currently equipped pickaxe"""
	return equipped_pickaxe

# ============================================
# SAVE/LOAD DATA (for Database Persistence)
# ============================================

func get_save_data() -> Dictionary:
	"""Serialize inventory state for database storage"""
	# Convert inventory to saveable format (filter out nulls, keep indices)
	var items_data: Array = []
	for i in range(inventory_items.size()):
		if inventory_items[i] != null:
			items_data.append({
				"slot": i,
				"item": inventory_items[i].duplicate()
			})

	return {
		"items": items_data,
		"equipped_axe": equipped_axe.duplicate() if not equipped_axe.is_empty() else {},
		"equipped_pickaxe": equipped_pickaxe.duplicate() if not equipped_pickaxe.is_empty() else {},
		"version": 1  # For future migration
	}

func load_save_data(data: Dictionary) -> void:
	"""Restore inventory state from database"""
	if data.is_empty():
		return

	# Suppress signals during bulk load
	suppress_signals = true

	# Clear current inventory
	for i in range(inventory_items.size()):
		inventory_items[i] = null
	equipped_axe = {}
	equipped_pickaxe = {}

	# Restore items to their slots
	var items_data = data.get("items", [])
	for item_entry in items_data:
		var slot = item_entry.get("slot", -1)
		var item = item_entry.get("item", {})
		if slot >= 0 and slot < inventory_items.size() and not item.is_empty():
			inventory_items[slot] = item.duplicate()

	# Restore equipped tools
	var saved_axe = data.get("equipped_axe", {})
	if not saved_axe.is_empty():
		equipped_axe = saved_axe.duplicate()

	var saved_pickaxe = data.get("equipped_pickaxe", {})
	if not saved_pickaxe.is_empty():
		equipped_pickaxe = saved_pickaxe.duplicate()

	# Re-enable signals and emit change
	suppress_signals = false
	inventory_changed.emit()
	print("📦 Inventory loaded from save data")

func clear_inventory() -> void:
	"""Clear all inventory data (for new character or reset)"""
	suppress_signals = true
	for i in range(inventory_items.size()):
		inventory_items[i] = null
	equipped_axe = {}
	equipped_pickaxe = {}
	suppress_signals = false
	inventory_changed.emit()
