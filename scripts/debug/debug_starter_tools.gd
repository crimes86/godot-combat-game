extends Node

## Debug helper to add starter gathering tools to inventory
## Call this from Player or use F11 key to add tools

func add_starter_tools_to_inventory() -> void:
	# Suppress signals during batch add to prevent multiple UI refreshes
	InventorySystem.suppress_signals = true

	var rusty_axe = {
		"name": "Rusty Axe",
		"description": "An old, weathered axe. Still sharp enough to chop dead wasteland trees.",
		"type": "tool",
		"tool_type": "axe",
		"value": 10,
		"rarity": "COMMON",
		"stackable": false,
		"quantity": 1,
		"efficiency": 1.0,  # 100% efficiency (normal speed)
		"durability": 100
	}

	var rusty_pickaxe = {
		"name": "Rusty Pickaxe",
		"description": "A worn mining pick. Good for breaking rocks and gathering ore.",
		"type": "tool",
		"tool_type": "pickaxe",
		"value": 10,
		"rarity": "COMMON",
		"stackable": false,
		"quantity": 1,
		"efficiency": 1.0,  # 100% efficiency (normal speed)
		"durability": 100
	}

	var axe_added = InventorySystem.add_item(rusty_axe)
	var pickaxe_added = InventorySystem.add_item(rusty_pickaxe)

	# Re-enable signals and refresh UI once
	InventorySystem.suppress_signals = false
	InventorySystem.inventory_changed.emit()

	# Show notifications for added items (staggered to prevent overlap)
	if axe_added:
		NotificationManager.notify_item_added("Rusty Axe", 1, "COMMON")
	if pickaxe_added:
		# Wait for first notification to position before adding second
		await get_tree().create_timer(0.3).timeout
		NotificationManager.notify_item_added("Rusty Pickaxe", 1, "COMMON")

	print("🔧 Added starter tools to inventory")
