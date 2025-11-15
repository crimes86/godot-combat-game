extends Node

## AUTO-INTEGRATION SCRIPT FOR MODULAR LPC CHARACTER
## Run this script to automatically integrate ModularLPCCharacter into Player.gd

const PLAYER_PATH = "res://scripts/player/Player.gd"
const BACKUP_PATH = "res://scripts/player/Player.gd.backup_before_modular_lpc"

func _ready():
	print("=== ModularLPCCharacter Auto-Integration ===")
	integrate()
	get_tree().quit()

func integrate():
	# Read current Player.gd
	var file = FileAccess.open(PLAYER_PATH, FileAccess.READ)
	if not file:
		push_error("Could not open Player.gd")
		return

	var content = file.get_as_text()
	file.close()

	# Backup original
	var backup = FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if backup:
		backup.store_string(content)
		backup.close()
		print("✅ Backup created at: ", BACKUP_PATH)

	# Apply transformations
	content = add_lpc_references(content)
	content = add_direction_helper(content)
	content = replace_create_sprite(content)
	content = replace_update_animation(content)
	content = replace_attempt_attack(content)

	# Write modified content
	var output = FileAccess.open(PLAYER_PATH, FileAccess.WRITE)
	if output:
		output.store_string(content)
		output.close()
		print("✅ Player.gd updated successfully!")
		print("✅ Integration complete! Test your game now.")
	else:
		push_error("Could not write to Player.gd")

func add_lpc_references(content: String) -> String:
	var search = "var selected_gender: Gender = Gender.MALE  # Will be set at game start"
	var replacement = """var selected_gender: Gender = Gender.MALE  # Will be set at game start

# LPC Modular Sprite System
const ModularLPCCharacter = preload("res://scripts/characters/ModularLPCCharacter.gd")
var lpc_character: ModularLPCCharacter = null
var last_lpc_direction := "south"  # Track last direction for animations"""

	if search in content and "var lpc_character" not in content:
		content = content.replace(search, replacement)
		print("✅ Added LPC references")
	else:
		print("⚠️  LPC references already exist or pattern not found")

	return content

func add_direction_helper(content: String) -> String:
	var helper_func = '''
func convert_to_lpc_direction(dir_string: String) -> String:
	"""Convert old animation direction names to LPC direction names"""
	match dir_string:
		"down": return "south"
		"up": return "north"
		"left": return "west"
		"right": return "east"
		_: return "south"  # Default
'''

	if "convert_to_lpc_direction" not in content:
		# Add before get_direction_string function
		var insert_point = content.find("func get_direction_string")
		if insert_point > 0:
			content = content.insert(insert_point, helper_func + "\n")
			print("✅ Added direction conversion helper")
		else:
			print("⚠️  Could not find insertion point for helper function")
	else:
		print("⚠️  Direction helper already exists")

	return content

func replace_create_sprite(content: String) -> String:
	# This is complex - we'll replace the entire function
	var new_function = '''func create_player_sprite() -> void:
	"""Create LPC modular character sprite system"""
	print("🎨 Creating LPC modular character sprite")

	# Create shadow
	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	var shadow_img = Image.create(48, 16, false, Image.FORMAT_RGBA8)
	for x in range(48):
		for y in range(16):
			var dx = (x - 24) / 24.0
			var dy = (y - 8) / 8.0
			var dist = dx * dx + dy * dy
			if dist <= 1.0:
				var alpha = (1.0 - dist) * 0.4
				shadow_img.set_pixel(x, y, Color(0, 0, 0, alpha))
	var shadow_texture = ImageTexture.create_from_image(shadow_img)
	shadow.texture = shadow_texture
	shadow.position = Vector2(0, 20)
	shadow.z_index = -5
	add_child(shadow)
	print("  ✅ Shadow created")

	# Create ModularLPCCharacter
	lpc_character = ModularLPCCharacter.new()
	lpc_character.name = "LPCCharacter"
	lpc_character.position = Vector2(0, -8)

	# Set up equipment paths
	var body_type = "body_male" if selected_gender == Gender.MALE else "body_female"
	lpc_character.base_body_path = "res://assets/characters/" + body_type + "/standard/walk.png"
	lpc_character.clothing_path = "res://assets/characters/legs_greenish/standard/walk.png"
	lpc_character.armor_path = "res://assets/characters/torso_leather/standard/walk.png"
	lpc_character.helmet_path = "res://assets/characters/hat_leather/standard/walk.png"

	# Set weapon if equipped
	if CharacterStats.equipped_weapon:
		var weapon_type = CharacterStats.equipped_weapon.weapon_type
		var weapon_name = ""
		var weapon_type_name = "sword"

		match weapon_type:
			"sword":
				weapon_name = "longsword"
				weapon_type_name = "oversize"
			"hammer":
				weapon_name = "warhammer"
				weapon_type_name = "oversize"
			"club":
				weapon_name = "club"
				weapon_type_name = "sword"
			"dagger":
				weapon_name = "dagger"
				weapon_type_name = "sword"
			"spear":
				weapon_name = "spear"
				weapon_type_name = "polearm"
			"rapier":
				weapon_name = "rapier"
				weapon_type_name = "sword"

		lpc_character.weapon_path = "res://assets/weapons/" + weapon_name + "/custom/slash_oversize.png"
		lpc_character.weapon_type = weapon_type_name
		print("  🗡️ Equipped weapon: ", weapon_name, " (type: ", weapon_type_name, ")")
	else:
		print("  👊 No weapon equipped")

	add_child(lpc_character)

	# Connect animation_finished signal
	if not lpc_character.animation_finished.is_connected(_on_attack_animation_finished):
		lpc_character.animation_finished.connect(_on_attack_animation_finished)

	print("  ✅ LPC Character created with modular layers")
'''

	# Find and replace the old function
	var start = content.find("func create_player_sprite")
	if start < 0:
		print("⚠️  create_player_sprite function not found")
		return content

	# Find the end of the function (next func or end of file)
	var search_from = start + 100
	var next_func = content.find("\nfunc ", search_from)
	if next_func < 0:
		next_func = content.length()

	# Replace the function
	content = content.substr(0, start) + new_function + "\n" + content.substr(next_func)
	print("✅ Replaced create_player_sprite()")

	return content

func replace_update_animation(content: String) -> String:
	var new_function = '''func update_lpc_animation(velocity_dir: Vector2) -> void:
	"""Update animation using ModularLPCCharacter system"""
	if not lpc_character:
		return

	# Don't interrupt attack animations
	if lpc_character.current_animation == ModularLPCCharacter.AnimState.SLASH and lpc_character.is_playing:
		return

	# Get direction string and convert to LPC format
	var is_moving = velocity_dir.length() > 0.1
	var dir_str = get_direction_string(velocity_dir) if is_moving else get_direction_string(attack_direction)
	var lpc_dir = convert_to_lpc_direction(dir_str)

	# Store last direction
	last_lpc_direction = lpc_dir

	# Play appropriate animation
	if is_moving:
		lpc_character.play_animation(ModularLPCCharacter.AnimState.WALK, lpc_dir)
	else:
		lpc_character.play_animation(ModularLPCCharacter.AnimState.IDLE, lpc_dir)
'''

	var start = content.find("func update_lpc_animation")
	if start < 0:
		print("⚠️  update_lpc_animation function not found")
		return content

	var search_from = start + 100
	var next_func = content.find("\nfunc ", search_from)
	if next_func < 0:
		next_func = content.length()

	content = content.substr(0, start) + new_function + "\n" + content.substr(next_func)
	print("✅ Replaced update_lpc_animation()")

	return content

func replace_attempt_attack(content: String) -> String:
	# Just replace the sprite animation part
	var old_pattern = """	# Trigger attack animation on ALL sprite layers (paper doll system)
	var dir_str = get_direction_string(attack_direction)
	var attack_anim = "attack_" + dir_str

	var body_sprite = get_node_or_null("BodySprite") as AnimatedSprite2D
	var legs_sprite = get_node_or_null("LegsSprite") as AnimatedSprite2D
	var torso_sprite = get_node_or_null("TorsoSprite") as AnimatedSprite2D
	var hat_sprite = get_node_or_null("HatSprite") as AnimatedSprite2D
	var weapon_front = get_node_or_null("WeaponFrontSprite") as AnimatedSprite2D
	var weapon_behind = get_node_or_null("WeaponBehindSprite") as AnimatedSprite2D

	# Play attack animation on all layers and make weapons visible
	for sprite in [body_sprite, legs_sprite, torso_sprite, hat_sprite, weapon_front, weapon_behind]:
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(attack_anim):
			sprite.play(attack_anim)
			sprite.visible = true  # Show weapons during attack even if hidden during walk"""

	var new_pattern = """	# Play attack animation on LPC character
	if lpc_character:
		var dir_str = get_direction_string(attack_direction)
		var lpc_dir = convert_to_lpc_direction(dir_str)
		lpc_character.play_animation(ModularLPCCharacter.AnimState.SLASH, lpc_dir)"""

	if old_pattern in content:
		content = content.replace(old_pattern, new_pattern)
		print("✅ Updated attempt_attack() animation code")
	else:
		print("⚠️  Could not find exact attack animation pattern to replace")

	return content
