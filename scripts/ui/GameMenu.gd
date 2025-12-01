extends CanvasLayer
## In-game Credits panel (opened from ESC menu spawn hints)
## Sound settings are now inline in the spawn hints overlay

signal menu_closed

# Panel references
@onready var credits_panel = $CreditsPanel
@onready var background = $Background

# Credits
@onready var credits_back_button = $CreditsPanel/VBoxContainer/CreditsBackButton

var is_open: bool = false

func _ready():
	# Hide initially
	visible = false
	if background:
		background.visible = false
	if credits_panel:
		credits_panel.visible = false

	# Connect credits back button
	if credits_back_button:
		credits_back_button.pressed.connect(_on_credits_back_pressed)

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if is_open:
				_on_credits_back_pressed()

func open_credits():
	## Open credits panel (called from spawn hints menu)
	is_open = true
	visible = true
	if background:
		background.visible = true
	if credits_panel:
		credits_panel.visible = true

func close_menu():
	is_open = false
	visible = false
	if background:
		background.visible = false
	if credits_panel:
		credits_panel.visible = false
	menu_closed.emit()

func _on_credits_back_pressed():
	_play_click_sound()
	close_menu()
	# Reopen spawn hints
	_reopen_spawn_hints()

func _reopen_spawn_hints():
	## Find the player and toggle spawn hints back on
	# Check if tree is still valid (may be null during scene change)
	if not is_inside_tree():
		return

	# Try to find player in game world
	var game_world = get_node_or_null("/root/main/GameWorld")
	if game_world:
		for child in game_world.get_children():
			if child.has_method("toggle_spawn_hints"):
				child.toggle_spawn_hints()
				return

	# Fallback: search all nodes
	var tree = get_tree()
	if tree and tree.root:
		_find_and_toggle_spawn_hints(tree.root)

func _find_and_toggle_spawn_hints(node: Node) -> bool:
	if node.has_method("toggle_spawn_hints"):
		node.toggle_spawn_hints()
		return true
	for child in node.get_children():
		if _find_and_toggle_spawn_hints(child):
			return true
	return false

func _play_click_sound():
	var sound_manager = get_node_or_null("/root/SoundManager")
	if sound_manager:
		sound_manager.play_button_click_sound()
