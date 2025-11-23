extends Node

## Global notification system for items and gold
## Displays floating notifications that stack gracefully
## Can be used for inventory changes, loot, vendor transactions, etc.

signal notification_created(notification: ItemNotification)

## Notification queue to manage multiple simultaneous notifications
var notification_queue: Array[ItemNotification] = []
var notification_container: Control = null
var notification_spacing: float = 40.0  # Vertical spacing between stacked notifications

func _ready() -> void:
	# Create a CanvasLayer to display notifications on top of everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "NotificationCanvas"
	canvas_layer.layer = 100  # High layer to appear above most UI
	add_child(canvas_layer)

	# Create container for notifications (centered horizontally, positioned between player and bottom of screen)
	notification_container = Control.new()
	notification_container.name = "NotificationContainer"
	notification_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	notification_container.anchor_left = 0.5
	notification_container.anchor_right = 0.5
	notification_container.anchor_top = 0.75  # 75% down the screen (between player and bottom)
	notification_container.anchor_bottom = 0.75
	notification_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notification_container.grow_vertical = Control.GROW_DIRECTION_END
	notification_container.offset_left = -200  # Half of width for centering
	notification_container.offset_right = 200  # Half of width for centering
	notification_container.custom_minimum_size = Vector2(400, 0)
	canvas_layer.add_child(notification_container)

	print("✅ NotificationManager initialized")

## Show an item added notification
## rarity: "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"
func notify_item_added(item_name: String, quantity: int = 1, rarity: String = "COMMON") -> void:
	var notification = _create_notification()
	notification.setup_item_added(item_name, quantity, rarity)
	_show_notification(notification)

## Show an item removed notification
func notify_item_removed(item_name: String, quantity: int = 1, rarity: String = "COMMON") -> void:
	var notification = _create_notification()
	notification.setup_item_removed(item_name, quantity, rarity)
	_show_notification(notification)

func _create_notification() -> ItemNotification:
	var notification_scene = preload("res://scenes/ui/item_notification.tscn")
	var notification = notification_scene.instantiate() as ItemNotification
	return notification

func _show_notification(notification: ItemNotification) -> void:
	# First, shift all existing notifications upward to make room
	var shift_duration = 0.25  # How long the shift takes

	if notification_queue.size() > 0:
		# Calculate new positions for existing notifications (they move up one slot)
		for i in range(notification_queue.size()):
			var existing_notification = notification_queue[i]
			if is_instance_valid(existing_notification):
				# Move up by one notification_spacing
				var current_y = existing_notification.position.y
				var new_y = current_y - notification_spacing
				var tween = create_tween()
				tween.tween_property(existing_notification, "position:y", new_y, shift_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

		# Wait for shift to complete before adding new notification
		await get_tree().create_timer(shift_duration).timeout

	# Now add the new notification at the bottom (position 0)
	notification_queue.append(notification)
	notification.position = Vector2(0, 0)
	notification_container.add_child(notification)

	# Connect to cleanup signal
	notification.notification_finished.connect(_on_notification_finished.bind(notification))

	# Emit signal
	notification_created.emit(notification)

func _on_notification_finished(notification: ItemNotification) -> void:
	# Remove from queue
	var index = notification_queue.find(notification)
	if index >= 0:
		notification_queue.remove_at(index)

	# Reposition remaining notifications
	_reposition_notifications()

func _reposition_notifications() -> void:
	# Don't reposition - notifications should stay in place when one expires
	# They were already positioned correctly when added, and will fade out naturally
	# This prevents the "shifting down" bug when notifications expire
	pass
