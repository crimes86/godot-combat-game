extends Node2D

## Test script for LPCAnimatedSprite2D addon - CHARACTER ONLY
## Weapons disabled - waiting for new plan

var character_sprite: LPCAnimatedSprite2D
var current_anim: String = "idle"
var current_dir: String = "south"

func _ready():
	print("=".repeat(60))
	print("LPC Addon Test Scene - CHARACTER ONLY")
	print("=".repeat(60))

	# Create body sprite
	character_sprite = LPCAnimatedSprite2D.new()
	character_sprite.name = "CharacterSprite"
	character_sprite.position = Vector2(400, 300)
	character_sprite.centered = true
	character_sprite.scale = Vector2(2, 2)  # Scale up for visibility

	# Set sprite data
	character_sprite.spritesheets_path = "res://assets/characters/body_male"
	character_sprite.animation_data = CharacterAnimationData.new()

	add_child(character_sprite)
	print("Body sprite created")

	# Wait for sprites to initialize
	await get_tree().process_frame

	# Debug: Check available animations
	if character_sprite.sprite_frames:
		print("Character animations: ", character_sprite.sprite_frames.get_animation_names())
	else:
		print("WARNING: Character sprite_frames is null!")

	# Start idle animation
	character_sprite.play_animation("idle", "south")
	print("Playing idle animation facing south")

	# Create UI label
	var label = Label.new()
	label.text = "LPC Addon Test (Character Only)\\nArrow keys: Walk\\nSpace: Slash attack\\nI: Idle, W: Walk, S: Slash"
	label.position = Vector2(10, 10)
	add_child(label)

	print("Test scene ready! Weapons disabled - waiting for new plan")
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
		# Moving - play walk animation
		var new_dir = get_direction_from_velocity(velocity)
		if current_anim != "walk" or current_dir != new_dir:
			current_anim = "walk"
			current_dir = new_dir
			print("WALK: ", current_dir)
			character_sprite.play_animation(current_anim, current_dir)
	else:
		# Not moving - play idle animation
		if current_anim != "idle":
			current_anim = "idle"
			print("IDLE: ", current_dir)
			character_sprite.play_animation(current_anim, current_dir)

func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):  # Space
		current_anim = "slash"
		character_sprite.play_animation("slash", current_dir)
		print("Attack! Playing slash animation facing ", current_dir)

	# Animation type change - check if it's a keyboard event
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I:
			current_anim = "idle"
			character_sprite.play_animation(current_anim, current_dir)
			print("Idle animation")
		elif event.keycode == KEY_W:
			current_anim = "walk"
			character_sprite.play_animation(current_anim, current_dir)
			print("Walk animation")
		elif event.keycode == KEY_S:
			current_anim = "slash"
			character_sprite.play_animation("slash", current_dir)
			print("Slash animation")

func get_direction_from_velocity(velocity: Vector2) -> String:
	velocity = velocity.normalized()
	if abs(velocity.x) > abs(velocity.y):
		return "east" if velocity.x > 0 else "west"
	else:
		return "south" if velocity.y > 0 else "north"
