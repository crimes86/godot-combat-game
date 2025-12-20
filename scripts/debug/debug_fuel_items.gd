extends Node

## Debug helper to add fuel items to inventory
## Call this from Player with: debug_fuel_items.new().add_fuel_to_inventory()
## Press F10 in-game to add fuel

func add_fuel_to_inventory() -> void:
	# Suppress signals during batch add to prevent multiple UI refreshes
	InventorySystem.suppress_signals = true

	var wood_item = {
		"name": "Dry Log",
		"description": "Dry wood from a chopped tree. Burns well in campfires.",
		"type": "material",
		"value": 2,
		"rarity": "Common",
		"stackable": true,
		"max_stack": 200,
		"quantity": 50
	}

	var bone_item = {
		"name": "Bone Ember",
		"description": "dreadland bones infused with supernatural heat. Burns with ghostly fire.",
		"value": 5,
		"rarity": "Common",
		"type": "material",
		"stackable": true,
		"max_stack": 200,
		"quantity": 100
	}

	var wood_added = InventorySystem.add_item(wood_item)
	var bone_added = InventorySystem.add_item(bone_item)

	# Re-enable signals and refresh UI once
	InventorySystem.suppress_signals = false
	InventorySystem.inventory_changed.emit()

	# Show notifications for added items (staggered to prevent overlap)
	if wood_added:
		NotificationManager.notify_item_added("Dry Log", 50, "Common")
	if bone_added:
		# Wait for first notification to position before adding second
		await get_tree().create_timer(0.3).timeout
		NotificationManager.notify_item_added("Bone Ember", 100, "Common")
