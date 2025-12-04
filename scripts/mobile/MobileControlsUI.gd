extends Control
## Mobile Controls UI
## Handles visual feedback for touch controls and coordinates with MobileInput singleton.

# Node references
@onready var joystick_base: Control = $JoystickBase
@onready var base_circle: ColorRect = $JoystickBase/BaseCircle
@onready var stick_circle: ColorRect = $JoystickBase/StickCircle
@onready var aim_hint: Label = $AimZoneHint

# Action buttons (created dynamically)
var dash_button: Button = null
var interact_button: Button = null
var inventory_button: Button = null
var character_button: Button = null

# Configuration
var joystick_radius: float = 75.0
var stick_size: float = 50.0
var dynamic_joystick: bool = true  # Joystick appears where you touch

# State
var _joystick_touch_index: int = -1
var _joystick_center := Vector2.ZERO
var _joystick_active := false

# Colors
var base_color_inactive := Color(0.2, 0.2, 0.2, 0.3)
var base_color_active := Color(0.3, 0.3, 0.3, 0.5)
var stick_color := Color(0.6, 0.6, 0.6, 0.8)
var aim_hint_color := Color(1.0, 1.0, 1.0, 0.3)


func _ready() -> void:
	# Hide on non-mobile platforms (unless testing)
	if not MobileInput.is_mobile_platform() and not OS.has_feature("editor"):
		hide()
		return

	# Set up initial appearance
	_setup_visuals()

	# Connect to MobileInput signals for aim feedback
	if MobileInput:
		MobileInput.aim_touch_started.connect(_on_aim_started)
		MobileInput.aim_touch_ended.connect(_on_aim_ended)

	# Hide aim hint after a few seconds
	if aim_hint:
		aim_hint.modulate = aim_hint_color
		var tween = create_tween()
		tween.tween_interval(5.0)
		tween.tween_property(aim_hint, "modulate:a", 0.0, 1.0)


func _setup_visuals() -> void:
	# Make base circle round using a shader or just accept rectangular for now
	if base_circle:
		base_circle.color = base_color_inactive

	if stick_circle:
		stick_circle.color = stick_color

	# Position joystick in bottom-left
	if joystick_base:
		var screen_size = get_viewport().get_visible_rect().size
		joystick_base.position = Vector2(50, screen_size.y - 200)
		_joystick_center = joystick_base.position + joystick_base.size / 2

		if dynamic_joystick:
			joystick_base.modulate.a = 0.5

	# Create action buttons
	_create_dash_button()
	_create_interact_button()
	_create_menu_buttons()


func _create_dash_button() -> void:
	"""Create the dash button in bottom-right area."""
	var screen_size = get_viewport().get_visible_rect().size

	dash_button = Button.new()
	dash_button.name = "DashButton"
	dash_button.text = "DASH"
	dash_button.custom_minimum_size = Vector2(100, 60)

	# Position above where right thumb naturally rests (bottom-right, but not too low)
	dash_button.position = Vector2(screen_size.x - 130, screen_size.y - 180)

	# Style the button
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.3, 0.4, 0.7)
	style.border_color = Color(0.5, 0.5, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	dash_button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.4, 0.4, 0.5, 0.8)
	dash_button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.5, 0.5, 0.6, 0.9)
	dash_button.add_theme_stylebox_override("pressed", pressed_style)

	# Connect button press
	dash_button.pressed.connect(_on_dash_pressed)

	add_child(dash_button)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var screen_size = get_viewport().get_visible_rect().size
	var joystick_zone_width = screen_size.x * 0.35

	if event.pressed:
		# Check if touch is in joystick zone (left side)
		if event.position.x < joystick_zone_width and _joystick_touch_index == -1:
			_joystick_touch_index = event.index
			_joystick_active = true

			if dynamic_joystick:
				# Move joystick to touch position
				_joystick_center = event.position
				joystick_base.position = event.position - joystick_base.size / 2
				joystick_base.modulate.a = 1.0

			base_circle.color = base_color_active
			_update_stick(event.position)
	else:
		# Touch released
		if event.index == _joystick_touch_index:
			_release_joystick()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_index and _joystick_active:
		_update_stick(event.position)


func _update_stick(touch_pos: Vector2) -> void:
	var offset = touch_pos - _joystick_center
	var distance = offset.length()

	# Clamp to radius
	if distance > joystick_radius:
		offset = offset.normalized() * joystick_radius

	# Update stick visual position (relative to base center)
	if stick_circle:
		var base_center = joystick_base.size / 2
		stick_circle.position = base_center + offset - stick_circle.size / 2


func _release_joystick() -> void:
	_joystick_touch_index = -1
	_joystick_active = false

	# Reset stick to center
	if stick_circle:
		var base_center = joystick_base.size / 2
		stick_circle.position = base_center - stick_circle.size / 2

	base_circle.color = base_color_inactive

	if dynamic_joystick:
		joystick_base.modulate.a = 0.5


func _on_aim_started(_world_pos: Vector2) -> void:
	# Could add visual feedback for aim touch
	pass


func _on_aim_ended() -> void:
	# Could add visual feedback for aim release
	pass


func _create_interact_button() -> void:
	"""Create the interact button in bottom-right area, above dash."""
	var screen_size = get_viewport().get_visible_rect().size

	interact_button = Button.new()
	interact_button.name = "InteractButton"
	interact_button.text = "[F]"
	interact_button.custom_minimum_size = Vector2(70, 70)

	# Position above dash button
	interact_button.position = Vector2(screen_size.x - 115, screen_size.y - 270)

	# Style the button - slightly different color to distinguish
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.25, 0.35, 0.3, 0.7)
	style.border_color = Color(0.4, 0.6, 0.5, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(35)  # Circular
	interact_button.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.35, 0.45, 0.4, 0.8)
	interact_button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.45, 0.55, 0.5, 0.9)
	interact_button.add_theme_stylebox_override("pressed", pressed_style)

	# Connect button press
	interact_button.pressed.connect(_on_interact_pressed)

	add_child(interact_button)


func _on_dash_pressed() -> void:
	"""Handle dash button press."""
	if MobileInput:
		MobileInput.trigger_dash()


func _on_interact_pressed() -> void:
	"""Handle interact button press."""
	if MobileInput:
		MobileInput.trigger_interact()


func show_controls() -> void:
	"""Show mobile controls."""
	show()


func hide_controls() -> void:
	"""Hide mobile controls."""
	hide()


func set_joystick_opacity(opacity: float) -> void:
	"""Set the joystick opacity (0.0 to 1.0)."""
	if joystick_base:
		joystick_base.modulate.a = opacity


func _create_menu_buttons() -> void:
	"""Create inventory and character buttons in top-right area."""
	var screen_size = get_viewport().get_visible_rect().size

	# Common style for menu buttons
	var base_style = StyleBoxFlat.new()
	base_style.bg_color = Color(0.2, 0.25, 0.35, 0.7)
	base_style.border_color = Color(0.4, 0.5, 0.6, 0.8)
	base_style.set_border_width_all(2)
	base_style.set_corner_radius_all(8)

	# Inventory button (bag icon or "INV")
	inventory_button = Button.new()
	inventory_button.name = "InventoryButton"
	inventory_button.text = "BAG"
	inventory_button.custom_minimum_size = Vector2(60, 50)
	inventory_button.position = Vector2(screen_size.x - 140, 20)

	inventory_button.add_theme_stylebox_override("normal", base_style)
	var inv_hover = base_style.duplicate()
	inv_hover.bg_color = Color(0.3, 0.35, 0.45, 0.8)
	inventory_button.add_theme_stylebox_override("hover", inv_hover)
	var inv_pressed = base_style.duplicate()
	inv_pressed.bg_color = Color(0.4, 0.45, 0.55, 0.9)
	inventory_button.add_theme_stylebox_override("pressed", inv_pressed)

	inventory_button.pressed.connect(_on_inventory_pressed)
	add_child(inventory_button)

	# Character button (person icon or "CHAR")
	character_button = Button.new()
	character_button.name = "CharacterButton"
	character_button.text = "CHAR"
	character_button.custom_minimum_size = Vector2(60, 50)
	character_button.position = Vector2(screen_size.x - 70, 20)

	var char_style = base_style.duplicate()
	char_style.bg_color = Color(0.25, 0.2, 0.35, 0.7)
	char_style.border_color = Color(0.5, 0.4, 0.6, 0.8)
	character_button.add_theme_stylebox_override("normal", char_style)
	var char_hover = char_style.duplicate()
	char_hover.bg_color = Color(0.35, 0.3, 0.45, 0.8)
	character_button.add_theme_stylebox_override("hover", char_hover)
	var char_pressed = char_style.duplicate()
	char_pressed.bg_color = Color(0.45, 0.4, 0.55, 0.9)
	character_button.add_theme_stylebox_override("pressed", char_pressed)

	character_button.pressed.connect(_on_character_pressed)
	add_child(character_button)


func _on_inventory_pressed() -> void:
	"""Handle inventory button press."""
	if MobileInput:
		MobileInput.trigger_inventory()


func _on_character_pressed() -> void:
	"""Handle character button press."""
	if MobileInput:
		MobileInput.trigger_character()
