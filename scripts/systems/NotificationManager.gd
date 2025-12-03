extends Node

## Global notification system for items and gold
## Displays floating notifications that stack gracefully
## Can be used for inventory changes, loot, vendor transactions, etc.

signal notification_created(notification: ItemNotification)

## Notification queue to manage multiple simultaneous notifications
var notification_queue: Array[ItemNotification] = []
var notification_container: Control = null
var notification_spacing: float = 40.0  # Vertical spacing between stacked notifications
const MAX_VISIBLE_NOTIFICATIONS: int = 4  # Maximum notifications visible at once

## Pending notifications queue for staggered display
var pending_notifications: Array = []  # Array of {type, data} dicts
var is_processing_queue: bool = false
const STAGGER_DELAY: float = 0.12  # Delay between each notification

func _ready() -> void:
	# Create a CanvasLayer to display notifications on top of everything
	var canvas_layer = CanvasLayer.new()
	canvas_layer.name = "NotificationCanvas"
	canvas_layer.layer = 200  # Above all game UI (shop=100, inventory=105, chat=110, etc.)
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
	print("📢 NotificationManager.notify_item_added: %s x%d (%s)" % [item_name, quantity, rarity])
	_queue_notification({
		"type": "item_added",
		"item_name": item_name,
		"quantity": quantity,
		"rarity": rarity
	})

## Show an item removed notification
func notify_item_removed(item_name: String, quantity: int = 1, rarity: String = "COMMON") -> void:
	_queue_notification({
		"type": "item_removed",
		"item_name": item_name,
		"quantity": quantity,
		"rarity": rarity
	})

## Show a gold added notification
func notify_gold_added(amount: int) -> void:
	print("📢 NotificationManager.notify_gold_added: %d gold" % amount)
	if amount <= 0:
		return
	_queue_notification({
		"type": "gold_added",
		"amount": amount
	})

## Show an XP gained notification
func notify_xp_gained(amount: int, source: String = "") -> void:
	print("📢 NotificationManager.notify_xp_gained: %d XP from %s" % [amount, source])
	if amount <= 0:
		return
	_queue_notification({
		"type": "xp_gained",
		"amount": amount,
		"source": source
	})

## Show a generic text notification (for system messages like "Game saved")
## type: "INFO", "SUCCESS", "WARNING", "ERROR"
func show_notification(message: String, type: String = "INFO") -> void:
	_queue_notification({
		"type": "system",
		"message": message,
		"msg_type": type
	})

## Queue a notification for staggered display
func _queue_notification(data: Dictionary) -> void:
	pending_notifications.append(data)
	print("📋 Queued notification (queue size: %d, processing: %s)" % [pending_notifications.size(), is_processing_queue])
	if not is_processing_queue:
		_start_processing_queue()

## Start processing the queue (async)
func _start_processing_queue() -> void:
	if is_processing_queue:
		return
	is_processing_queue = true
	_process_next_notification()

## Process next notification in queue with delay
func _process_next_notification() -> void:
	if pending_notifications.is_empty():
		is_processing_queue = false
		print("📋 Queue empty, done processing")
		return

	var data = pending_notifications.pop_front()
	print("📋 Processing notification: %s (remaining: %d)" % [data.get("type", "unknown"), pending_notifications.size()])

	# Create and show the notification based on type
	var notification = _create_notification()
	match data.type:
		"item_added":
			notification.setup_item_added(data.item_name, data.quantity, data.rarity)
			# Play item pickup sound
			var sound_manager = get_node_or_null("/root/SoundManager")
			if sound_manager:
				sound_manager.play_sound_2d(sound_manager.SoundType.ITEM_PICKUP, -8.0)
		"item_removed":
			notification.setup_item_removed(data.item_name, data.quantity, data.rarity)
		"gold_added":
			notification.setup_gold_added(data.amount)
		"xp_gained":
			notification.setup_xp_gained(data.amount, data.source)
		"system":
			notification.setup_system_message(data.message, data.msg_type)

	_show_notification(notification)

	# Schedule next notification with delay
	if not pending_notifications.is_empty():
		await get_tree().create_timer(STAGGER_DELAY).timeout
		_process_next_notification()
	else:
		is_processing_queue = false
		print("📋 Queue empty, done processing")

func _create_notification() -> ItemNotification:
	var notification_scene = preload("res://scenes/ui/item_notification.tscn")
	var notification = notification_scene.instantiate() as ItemNotification
	return notification

func _show_notification(notification: ItemNotification) -> void:
	# If we're at max capacity, push out the oldest notification
	if notification_queue.size() >= MAX_VISIBLE_NOTIFICATIONS:
		_push_out_oldest()

	# Shift all existing notifications upward to make room (animated)
	var shift_duration = 0.15  # Quick shift

	for i in range(notification_queue.size()):
		var existing_notification = notification_queue[i]
		if is_instance_valid(existing_notification):
			# Move up by one notification_spacing
			var new_y = -(notification_queue.size() - i) * notification_spacing
			var tween = create_tween()
			tween.tween_property(existing_notification, "position:y", new_y, shift_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Add the new notification at the bottom (position 0) immediately
	notification_queue.append(notification)
	notification.position = Vector2(0, 0)
	notification_container.add_child(notification)

	# Connect to cleanup signal
	notification.notification_finished.connect(_on_notification_finished.bind(notification))

	# Emit signal
	notification_created.emit(notification)

func _push_out_oldest() -> void:
	"""Push the oldest notification up and fade it out quickly to make room."""
	if notification_queue.is_empty():
		return

	var oldest = notification_queue[0]
	if not is_instance_valid(oldest):
		notification_queue.remove_at(0)
		return

	# Remove from queue immediately
	notification_queue.remove_at(0)

	# Animate it pushing up and fading out
	var push_tween = create_tween()
	push_tween.set_parallel(true)
	# Push up by one more spacing
	push_tween.tween_property(oldest, "position:y", oldest.position.y - notification_spacing, 0.2).set_ease(Tween.EASE_OUT)
	# Fade out quickly
	push_tween.tween_property(oldest, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)

	# Delete after animation
	push_tween.chain().tween_callback(oldest.queue_free)

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
