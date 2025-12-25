extends Node

## Inventory System
## Autoload singleton managing player inventory and gold display
## Add to project.godot as "InventorySystem"

# ============================================
# DEBUG SETTINGS - Set to true to enable verbose logging
# ============================================
const DEBUG_EQUIP: bool = true  # Debug tool equipping

# ============================================
# INVENTORY DATA
# ============================================

const MAX_INVENTORY_SLOTS: int = 100  # Maximum slots (20 rows x 5 columns)
const SLOTS_PER_ROW: int = 5          # Columns in grid
const MIN_VISIBLE_ROWS: int = 5       # Minimum rows shown (5x5 = 25 slots)

var inventory_items: Array = []  # Array of item dictionaries
var suppress_signals: bool = false  # Flag to suppress signal emissions
var current_slot_count: int = 25  # Current number of slots (grows dynamically)

# Tool slots - for gathering tools
var equipped_axe: Dictionary = {}  # Axe slot for tree chopping
var equipped_pickaxe: Dictionary = {}  # Pickaxe slot for rock mining

# ============================================
# SIGNALS
# ============================================

signal inventory_changed()
signal item_added(item: Dictionary)
signal item_removed(item: Dictionary, slot: int)
signal slots_expanded(new_count: int)  # Emitted when inventory grows
signal axe_equipped(axe: Dictionary)
signal axe_unequipped(axe: Dictionary)
signal pickaxe_equipped(pickaxe: Dictionary)
signal pickaxe_unequipped(pickaxe: Dictionary)

# ============================================
# INITIALIZATION
# ============================================

func _ready() -> void:
	Constants.debug_log("═══════════════════════════════════════")
	Constants.debug_log("InventorySystem initialized")
	Constants.debug_log("Max slots: %d, Starting slots: %d" % [MAX_INVENTORY_SLOTS, current_slot_count])
	Constants.debug_log("═══════════════════════════════════════")

	# Initialize with minimum visible slots (5x5 = 25)
	current_slot_count = MIN_VISIBLE_ROWS * SLOTS_PER_ROW
	for i in range(current_slot_count):
		inventory_items.append(null)

func get_needed_slot_count() -> int:
	"""Calculate slots needed to fit all items + complete the row"""
	var item_count = 0
	for item in inventory_items:
		if item != null:
			item_count += 1

	# Need at least one more row than items fill (for adding new items)
	var rows_needed = ceili(float(item_count + 1) / SLOTS_PER_ROW)
	# Minimum 5 rows visible
	rows_needed = max(rows_needed, MIN_VISIBLE_ROWS)
	# Cap at max
	var slots_needed = min(rows_needed * SLOTS_PER_ROW, MAX_INVENTORY_SLOTS)
	return slots_needed

func expand_slots_if_needed() -> bool:
	"""Expand inventory slots if needed. Returns true if expanded."""
	var needed = get_needed_slot_count()
	if needed > current_slot_count:
		var old_count = current_slot_count
		current_slot_count = needed
		# Add new null slots
		for i in range(old_count, current_slot_count):
			inventory_items.append(null)
		Constants.debug_log("Inventory expanded: %d -> %d slots" % [old_count, current_slot_count])
		slots_expanded.emit(current_slot_count)
		return true
	return false

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
			# Check if we need to expand for next item
			expand_slots_if_needed()
			return true

	# No empty slot found - try to expand inventory
	if expand_slots_if_needed():
		# Retry adding to new slots
		for i in range(inventory_items.size()):
			if inventory_items[i] == null:
				var new_item = item.duplicate()
				new_item["quantity"] = quantity
				inventory_items[i] = new_item
				if not suppress_signals:
					item_added.emit(new_item)
					inventory_changed.emit()
				return true

	return false  # Inventory completely full (100 slots)

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

func reduce_quantity(slot: int, amount: int) -> int:
	"""Reduce quantity of stackable item at slot. Returns amount actually removed."""
	if slot < 0 or slot >= inventory_items.size():
		return 0

	var item = inventory_items[slot]
	if not item:
		return 0

	var current_qty = item.get("quantity", 1)
	var to_remove = min(amount, current_qty)

	if to_remove >= current_qty:
		# Remove entire stack
		inventory_items[slot] = null
		item_removed.emit(item, slot)
	else:
		# Reduce quantity
		item["quantity"] = current_qty - to_remove

	inventory_changed.emit()
	return to_remove

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

func has_item_by_name(item_name: String) -> bool:
	"""Check if inventory contains an item with the given name"""
	for item in inventory_items:
		if item != null and item.get("name", "") == item_name:
			return true
	return false

# ============================================
# GOLD ACCESS (Proxy to CharacterStats)
# ============================================

func get_gold() -> int:
	"""Get current gold amount from CharacterStats"""
	return CharacterStats.gold

# ============================================
# CORPSE SYSTEM HELPERS
# ============================================

func get_full_snapshot() -> Array:
	"""Get deep copy of entire inventory for corpse system"""
	var snapshot = []
	for item in inventory_items:
		if item:
			snapshot.append(item.duplicate(true))
		else:
			snapshot.append(null)
	return snapshot

func clear_all() -> void:
	"""Clear entire inventory (death)"""
	for i in range(inventory_items.size()):
		inventory_items[i] = null

	# Clear tool slots too
	equipped_axe = {}
	equipped_pickaxe = {}

	inventory_changed.emit()

func has_space() -> bool:
	"""Check if there's room for at least one more item"""
	return has_empty_slot()

# ============================================
# DEBUG / PLAYTEST
# ============================================

func print_inventory() -> void:
	"""Debug: Print all inventory contents"""
	for i in range(inventory_items.size()):
		var item = inventory_items[i]

func clear_forged_items() -> int:
	"""Clear all forged items from inventory. Returns count of items cleared."""
	var cleared = 0
	for i in range(inventory_items.size()):
		var item = inventory_items[i]
		if item and item.get("is_forged", false):
			inventory_items[i] = null
			cleared += 1

	# Also unequip any forged weapons
	if CharacterStats.equipped_weapon_data.get("is_forged", false):
		CharacterStats.unequip_weapon()
		cleared += 1

	# Unequip any forged armor
	for slot in CharacterStats.equipped_armor:
		var armor_item = CharacterStats.equipped_armor[slot]
		if armor_item and armor_item.get("is_forged", false):
			CharacterStats.unequip_armor(slot)
			cleared += 1

	if cleared > 0:
		inventory_changed.emit()
		print("🔄 Cleared %d forged items from inventory and equipment" % cleared)

	return cleared

# ============================================
# TOOL SLOT MANAGEMENT
# ============================================

func equip_axe(axe: Dictionary) -> bool:
	"""Equip an axe to the axe slot"""
	if axe.is_empty():
		return false

	# Check if it's a valid axe
	if axe.get("type", "") != "tool" or axe.get("tool_type", "") != "axe":
		return false

	# If there's already an axe equipped, unequip it first
	if not equipped_axe.is_empty():
		if not unequip_axe():
			return false

	# Equip the new axe
	equipped_axe = axe.duplicate()
	axe_equipped.emit(axe)
	if DEBUG_EQUIP:
		print("[Equip] Equipped axe: %s" % axe.get("name", "Unknown"))
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
		if DEBUG_EQUIP:
			print("[Equip] Unequipped axe: %s" % old_axe.get("name", "Unknown"))
		return true
	else:
		return false

func equip_pickaxe(pickaxe: Dictionary) -> bool:
	"""Equip a pickaxe to the pickaxe slot"""
	if pickaxe.is_empty():
		return false

	# Check if it's a valid pickaxe
	if pickaxe.get("type", "") != "tool" or pickaxe.get("tool_type", "") != "pickaxe":
		return false

	# If there's already a pickaxe equipped, unequip it first
	if not equipped_pickaxe.is_empty():
		if not unequip_pickaxe():
			return false

	# Equip the new pickaxe
	equipped_pickaxe = pickaxe.duplicate()
	pickaxe_equipped.emit(pickaxe)
	if DEBUG_EQUIP:
		print("[Equip] Equipped pickaxe: %s" % pickaxe.get("name", "Unknown"))
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
		if DEBUG_EQUIP:
			print("[Equip] Unequipped pickaxe: %s" % old_pickaxe.get("name", "Unknown"))
		return true
	else:
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

func get_equipped_pickaxe_tier() -> int:
	"""Get the tier of the equipped pickaxe (-1 if none equipped)"""
	if equipped_pickaxe.is_empty():
		return -1
	return equipped_pickaxe.get("tier", 0)  # Default to tier 0 if not specified

func get_equipped_axe_tier() -> int:
	"""Get the tier of the equipped axe (-1 if none equipped)"""
	if equipped_axe.is_empty():
		return -1
	return equipped_axe.get("tier", 0)  # Default to tier 0 if not specified

# ============================================
# SAVE/LOAD DATA (for Database Persistence)
# ============================================

func get_save_data() -> Dictionary:
	"""Serialize inventory state for database storage"""
	# Convert inventory to saveable format (filter out nulls, keep indices)
	var items_data: Array = []
	var forged_count = 0
	for i in range(inventory_items.size()):
		if inventory_items[i] != null:
			items_data.append({
				"slot": i,
				"item": inventory_items[i].duplicate()
			})
			if inventory_items[i].get("is_forged", false):
				forged_count += 1

	print("[InventorySystem] Saving %d items (%d forged)" % [items_data.size(), forged_count])

	return {
		"items": items_data,
		"equipped_axe": equipped_axe.duplicate() if not equipped_axe.is_empty() else {},
		"equipped_pickaxe": equipped_pickaxe.duplicate() if not equipped_pickaxe.is_empty() else {},
		"version": 1  # For future migration
	}

func load_save_data(data: Dictionary) -> void:
	"""Restore inventory state from database"""
	if data.is_empty():
		print("[InventorySystem] load_save_data called with empty data!")
		return

	var items_data = data.get("items", [])
	var forged_count = 0
	for item_entry in items_data:
		var item = item_entry.get("item", {})
		if item.get("is_forged", false):
			forged_count += 1
	print("[InventorySystem] Loading %d items (%d forged) from save" % [items_data.size(), forged_count])

	# Suppress signals during bulk load
	suppress_signals = true

	# Clear current inventory
	for i in range(inventory_items.size()):
		inventory_items[i] = null
	equipped_axe = {}
	equipped_pickaxe = {}

	# Restore items to their slots from saved data
	for item_entry in items_data:
		var slot = item_entry.get("slot", -1)
		var item = item_entry.get("item", {})
		if slot >= 0 and slot < inventory_items.size() and not item.is_empty():
			inventory_items[slot] = item.duplicate()

	# Migration: Mark items as forged if they match ForgeItemDB entries but aren't flagged
	_migrate_forged_items()

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

func clear_inventory() -> void:
	"""Clear all inventory data (for new character or reset)"""
	suppress_signals = true
	for i in range(inventory_items.size()):
		inventory_items[i] = null
	equipped_axe = {}
	equipped_pickaxe = {}
	suppress_signals = false
	inventory_changed.emit()

func _migrate_forged_items() -> void:
	"""Migration: Fix forged item metadata for proper icon/sprite loading"""
	var migrated_count = 0
	var fixed_count = 0

	for i in range(inventory_items.size()):
		var item = inventory_items[i]
		if item == null or item.is_empty():
			continue

		var item_name = item.get("name", "")
		var item_id = item.get("item_id", item.get("forged_item_id", ""))
		var is_already_forged = item.get("is_forged", false)

		# For items marked as forged, check if they have proper item_id
		if is_already_forged:
			# Check if item_id is missing or doesn't match ForgeItemDB
			var needs_fix = false
			var forge_data = {}

			if item_id != "":
				forge_data = ForgeItemDB.get_item_by_id(item_id)

			# If item_id doesn't resolve, try by name
			if forge_data.is_empty() and item_name != "":
				forge_data = ForgeItemDB.get_item_by_name(item_name)
				if not forge_data.is_empty():
					needs_fix = true  # Found by name but not by current item_id

			if needs_fix and not forge_data.is_empty():
				var correct_item_id = forge_data.get("item_id", "")
				if correct_item_id != "" and correct_item_id != item_id:
					item["item_id"] = correct_item_id
					item["forged_id"] = correct_item_id
					item["forged_item_id"] = correct_item_id
					fixed_count += 1
					print("[InventorySystem] Fixed forged item ID: %s -> %s" % [item_name, correct_item_id])
			continue

		# Check if this item matches a ForgeItemDB entry by name or item_id
		var forge_data = {}
		# Try by item_id first
		if item_id != "":
			forge_data = ForgeItemDB.get_item_by_id(item_id)
		# Try by name if not found
		if forge_data.is_empty() and item_name != "":
			forge_data = ForgeItemDB.get_item_by_name(item_name)

		if not forge_data.is_empty():
			# This item matches a forged item but wasn't flagged - fix it
			var forged_item_id = forge_data.get("item_id", item_id)
			item["is_forged"] = true
			item["forged_id"] = forged_item_id
			item["forged_item_id"] = forged_item_id
			item["item_id"] = forged_item_id
			# Copy visual properties if missing
			if not item.has("glow_color") or item.get("glow_color", "") == "":
				var visuals = forge_data.get("visuals", {})
				if visuals.has("glow_color"):
					item["glow_color"] = visuals.get("glow_color")
				if visuals.has("effect"):
					item["effect_name"] = visuals.get("effect")
			migrated_count += 1
			print("[InventorySystem] Migrated forged item: %s (now has is_forged=true, item_id=%s)" % [item_name, forged_item_id])

	if migrated_count > 0 or fixed_count > 0:
		print("[InventorySystem] Migration complete: %d items marked as forged, %d item IDs fixed" % [migrated_count, fixed_count])
