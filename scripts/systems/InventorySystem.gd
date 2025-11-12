extends Node

## Inventory System
## Autoload singleton managing player inventory and gold display
## Add to project.godot as "InventorySystem"

# ============================================
# INVENTORY DATA
# ============================================

const MAX_INVENTORY_SLOTS: int = 4  # Starting with 4 slots (expandable later)

var inventory_items: Array = []  # Array of item dictionaries

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
					inventory_changed.emit()
					print("📦 Stacked +%d %s (now %d in slot %d)" % [amount_to_add, item_name, existing_item["quantity"], i])

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
			item_added.emit(new_item)
			inventory_changed.emit()
			print("📦 Added item to slot %d: %s x%d" % [i, item_name, quantity])
			return true

	print("❌ Inventory full! Cannot add item: %s" % item_name)
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
		print("📤 Removed item from slot %d: %s" % [slot, item.get("name", "Unknown")])
		return item

	return {}

func get_item(slot: int) -> Dictionary:
	"""Get item at specific slot (returns null if empty)"""
	if slot < 0 or slot >= inventory_items.size():
		return {}

	var item = inventory_items[slot]
	return item if item else {}

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
	print("\n═══ INVENTORY ═══")
	print("Gold: ", get_gold())
	for i in range(inventory_items.size()):
		var item = inventory_items[i]
		if item:
			print("Slot %d: %s (Value: %d)" % [i, item.get("name", "???"), item.get("value", 0)])
		else:
			print("Slot %d: [Empty]" % i)
	print("═════════════════\n")
