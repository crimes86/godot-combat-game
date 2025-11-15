extends Node2D

## Test script for LPCAnimatedSprite2D addon
## Run this scene to verify the addon works before refactoring Player.gd

var character_sprite: LPCAnimatedSprite2D
var weapon_sprite: LPCAnimatedSprite2D
var current_anim: String = "idle"
var current_dir: String = "south"

func _ready():
	print("=".repeat(60))
	print("LPC Addon Test Scene")
	print("=".repeat(60))

	# Create body sprite
	character_sprite = LPCAnimatedSprite2D.new()
	character_sprite.name = "CharacterSprite"
	character_sprite.position = Vector2(400, 300)
	character_sprite.centered = true
	character_sprite.scale = Vector2(2, 2)  # Scale up for visibility

	# Set sprite data
	character_sprite.spritesheets_path = "res://assets/characters/body_male"
	character_sprite.animation_data = LPCAnimationData.new()

	add_child(character_sprite)
	print("Body sprite created")

	# Create weapon sprite (layered on top)
	weapon_sprite = LPCAnimatedSprite2D.new()
	weapon_sprite.name = "WeaponSprite"
	weapon_sprite.position = Vector2(400, 300)
	weapon_sprite.centered = true
	weapon_sprite.scale = Vector2(2, 2)
	weapon_sprite.z_index = 10  # In front of body

	# Set weapon data
	weapon_sprite.spritesheets_path = "res://assets/weapons/longsword"
	weapon_sprite.animation_data = LPCAnimationData.new()

	add_child(weapon_sprite)
	print("Weapon sprite created")

	# Start idle animation
	character_sprite.play_animation("idle", "south")
	weapon_sprite.play_animation("idle", "south")
	print("Playing idle animation facing south")

	# Create UI label
	var label = Label.new()
	label.text = "LPC Addon Test\\nControls:\\nArrow keys: Walk\\nSpace: Attack\\n1-4: Change direction\\nI: Idle, W: Walk, S: Slash"
	label.position = Vector2(10, 10)
	add_child(label)

	print("Test scene ready! Use controls to test animations.")
	print("=".repeat(60))

func _process(delta):
	# Arrow key movement
	var velocity = Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		velocity.x += 1
	if Input.is_action_pressed("ui_left"):
		velocity.x -= 1
	if Input.is_action_pressed("ui_down"):
		velocity.y += 1
	if Input.is_action_pressed("ui_up"):
		velocity.y -= 1

	if velocity.length() > 0:
		current_anim = "walk"
		current_dir = get_direction_from_velocity(velocity)
		character_sprite.play_animation(current_anim, current_dir)
		weapon_sprite.play_animation(current_anim, current_dir)

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):  # Space
		current_anim = "slash_oversize"  # Longsword uses oversize
		character_sprite.play_animation("slash", current_dir)
		weapon_sprite.play_animation("slash_oversize", current_dir)
		print("Attack! Playing slash animation facing ", current_dir)

	# Manual direction change
	if event.is_action_pressed("ui_page_up"):  # 1
		current_dir = "north"
		character_sprite.play_animation(current_anim, current_dir)
		weapon_sprite.play_animation(current_anim, current_dir)
		print("Changed direction to north")
	elif event.is_action_pressed("ui_page_down"):  # 2
		current_dir = "south"
		character_sprite.play_animation(current_anim, current_dir)
		weapon_sprite.play_animation(current_anim, current_dir)
		print("Changed direction to south")
	elif event.is_action_pressed("ui_home"):  # 3
		current_dir = "west"
		character_sprite.play_animation(current_anim, current_dir)
		weapon_sprite.play_animation(current_anim, current_dir)
		print("Changed direction to west")
	elif event.is_action_pressed("ui_end"):  # 4
		current_dir = "east"
		character_sprite.play_animation(current_anim, current_dir)
		weapon_sprite.play_animation(current_anim, current_dir)
		print("Changed direction to east")

	# Animation type change - check if it's a keyboard event
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I:
			current_anim = "idle"
			character_sprite.play_animation(current_anim, current_dir)
			weapon_sprite.play_animation(current_anim, current_dir)
			print("Idle animation")
		elif event.keycode == KEY_W:
			current_anim = "walk"
			character_sprite.play_animation(current_anim, current_dir)
			weapon_sprite.play_animation(current_anim, current_dir)
			print("Walk animation")
		elif event.keycode == KEY_S:
			current_anim = "slash"
			character_sprite.play_animation("slash", current_dir)
			weapon_sprite.play_animation("slash_oversize", current_dir)
			print("Slash animation")

func get_direction_from_velocity(velocity: Vector2) -> String:
	velocity = velocity.normalized()
	if abs(velocity.x) > abs(velocity.y):
		return "east" if velocity.x > 0 else "west"
	else:
		return "south" if velocity.y > 0 else "north"
