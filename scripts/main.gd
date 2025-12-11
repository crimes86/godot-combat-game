# main.gd
extends Node2D

@onready var game_world = $GameWorld

func _ready():
	# Player spawning is now handled by game_world.gd multiplayer code
	pass

func _notification(what):
	# Handle window close request (Alt+F4, X button, etc.)
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("🚪 Game closing - syncing state before exit...")
		_graceful_shutdown()

func _graceful_shutdown() -> void:
	"""Sync player state to server before quitting to prevent data loss."""
	# Stop all tweens to prevent hang
	get_tree().call_group("tweens", "kill")

	# Sync state to server if we're a connected client
	if NetworkManager and NetworkManager.is_authenticated and not NetworkManager.is_host:
		print("📤 Syncing player state to server...")
		NetworkManager.client_sync_state()
		# Small delay to let the RPC go through before disconnecting
		await get_tree().create_timer(0.2).timeout

	# Close network connection gracefully (this also triggers server-side save)
	if NetworkManager:
		NetworkManager.close_connection()

	print("✅ Shutdown complete")
	get_tree().quit()
