extends Node

## InteractionManager - Central system to handle interaction priority
## Prevents multiple F prompts from showing simultaneously
## Priority (highest to lowest):
## 1. Loot bodies (corpses with items)
## 2. Other players (inspect/trade/duel)
## 3. Treasure chests
## 4. Pickable items (bones, loot on ground)
## 5. Harvestable resources (trees, rocks)
## 6. NPCs (vendors)
## 7. Campfire (fuel)

enum InteractionType {
	LOOT_BODY = 0,      # Highest priority
	PLAYER = 1,         # Other players (inspect/trade/duel)
	TREASURE_CHEST = 2,
	PICKABLE_ITEM = 3,
	HARVESTABLE = 4,
	NPC = 5,
	CAMPFIRE = 6        # Lowest priority
}

# Currently registered interactables in range
var active_interactables: Array[Dictionary] = []

# The currently active (shown) interactable
var current_interactable: Node = null

func _ready() -> void:
	print("🎯 InteractionManager initialized")

## Register an interactable as being in range of the player
func register_interactable(node: Node, type: InteractionType, distance: float = 0.0) -> void:
	# Check if already registered
	for entry in active_interactables:
		if entry.node == node:
			# Update distance
			entry.distance = distance
			_update_active_interactable()
			return

	active_interactables.append({
		"node": node,
		"type": type,
		"distance": distance
	})
	_update_active_interactable()

## Unregister an interactable (player left range)
func unregister_interactable(node: Node) -> void:
	for i in range(active_interactables.size() - 1, -1, -1):
		if active_interactables[i].node == node:
			active_interactables.remove_at(i)
			break
	_update_active_interactable()

## Check if a specific interactable is the current active one
func is_active_interactable(node: Node) -> bool:
	return current_interactable == node

## Update which interactable should be shown
func _update_active_interactable() -> void:
	# Remove any invalid nodes
	for i in range(active_interactables.size() - 1, -1, -1):
		if not is_instance_valid(active_interactables[i].node):
			active_interactables.remove_at(i)

	if active_interactables.is_empty():
		current_interactable = null
		return

	# Sort by priority (type) first, then by distance
	active_interactables.sort_custom(func(a, b):
		if a.type != b.type:
			return a.type < b.type  # Lower type number = higher priority
		return a.distance < b.distance  # Closer = higher priority
	)

	# Set the highest priority interactable as current
	current_interactable = active_interactables[0].node

## Clear all interactables (e.g., when player dies or teleports)
func clear_all() -> void:
	active_interactables.clear()
	current_interactable = null
