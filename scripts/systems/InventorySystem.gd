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

# ============================================
# SIGNALS
# ============================================

signal inventory_changed()
signal item_added(item: Dictionary)
signal item_removed(item: Dictionary, slot: int)

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
