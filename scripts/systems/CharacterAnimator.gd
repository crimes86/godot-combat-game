extends Node
class_name CharacterAnimator

## Handles procedural animations for humanoid characters
## Creates walk, idle, and attack animations

enum AnimState {
	IDLE,
	WALKING,
	ATTACKING
}

# Animation parameters
var current_state: AnimState = AnimState.IDLE
var animation_time: float = 0.0
var attack_timer: float = 0.0

# Body part references (set by parent)
var head: Sprite2D = null
var torso: Sprite2D = null
var left_arm: Sprite2D = null
var right_arm: Sprite2D = null
var left_leg: Sprite2D = null
var right_leg: Sprite2D = null
var weapon: Sprite2D = null

# Original positions (for resetting)
var original_positions: Dictionary = {}

# Animation speeds
var idle_speed: float = 2.0
var walk_speed: float = 8.0
var attack_speed: float = 12.0

func _ready() -> void:
	# Store original positions when animation starts
	pass

func store_original_positions() -> void:
	"""Store the original positions of all body parts"""
	if head:
		original_positions["head"] = head.position
	if torso:
		original_positions["torso"] = torso.position
	if left_arm:
		original_positions["left_arm"] = left_arm.position
	if right_arm:
		original_positions["right_arm"] = right_arm.position
	if left_leg:
		original_positions["left_leg"] = left_leg.position
	if right_leg:
		original_positions["right_leg"] = right_leg.position
	if weapon:
		original_positions["weapon"] = weapon.position

func _process(delta: float) -> void:
	animation_time += delta
	
	# Update attack timer
	if attack_timer > 0:
		attack_timer -= delta
		if attack_timer <= 0:
			current_state = AnimState.IDLE
	
	# Run animation based on state
	match current_state:
		AnimState.IDLE:
			animate_idle(delta)
		AnimState.WALKING:
			animate_walk(delta)
		AnimState.ATTACKING:
			animate_attack(delta)

func set_state(new_state: AnimState) -> void:
	"""Change animation state"""
	current_state = new_state

func play_attack() -> void:
	"""Trigger attack animation"""
	current_state = AnimState.ATTACKING
	attack_timer = 0.3  # Attack animation duration

func animate_idle(delta: float) -> void:
	"""Subtle breathing/bobbing animation"""
	var bob = sin(animation_time * idle_speed) * 1.5
	
	if head and original_positions.has("head"):
		head.position.y = original_positions["head"].y + bob
	
	if torso and original_positions.has("torso"):
		torso.position.y = original_positions["torso"].y + bob * 0.5
	
	# Slight arm sway
	if left_arm and original_positions.has("left_arm"):
		left_arm.position.y = original_positions["left_arm"].y + bob * 0.3
	
	if right_arm and original_positions.has("right_arm"):
		right_arm.position.y = original_positions["right_arm"].y + bob * 0.3

func animate_walk(delta: float) -> void:
	"""Walking animation with leg and arm swing"""
	var walk_cycle = animation_time * walk_speed
	
	# Body bob (more pronounced than idle)
	var bob = abs(sin(walk_cycle)) * 2.0
	
	if head and original_positions.has("head"):
		head.position.y = original_positions["head"].y - bob
	
	if torso and original_positions.has("torso"):
		torso.position.y = original_positions["torso"].y - bob * 0.7
	
	# Leg swing (opposite legs)
	var leg_swing = sin(walk_cycle) * 3.0
	
	if left_leg and original_positions.has("left_leg"):
		left_leg.position.y = original_positions["left_leg"].y + leg_swing
		left_leg.position.x = original_positions["left_leg"].x + leg_swing * 0.5
	
	if right_leg and original_positions.has("right_leg"):
		right_leg.position.y = original_positions["right_leg"].y - leg_swing
		right_leg.position.x = original_positions["right_leg"].x - leg_swing * 0.5
	
	# Arm swing (opposite arms, opposite to legs)
	var arm_swing = sin(walk_cycle) * 2.0
	
	if left_arm and original_positions.has("left_arm"):
		left_arm.position.y = original_positions["left_arm"].y - arm_swing * 0.5
	
	if right_arm and original_positions.has("right_arm"):
		right_arm.position.y = original_positions["right_arm"].y + arm_swing * 0.5

func animate_attack(delta: float) -> void:
	"""Attack animation - weapon swing"""
	var attack_progress = 1.0 - (attack_timer / 0.3) if attack_timer > 0 else 1.0
	
	# Attack has 3 phases: windup (0-0.33), swing (0.33-0.66), recover (0.66-1.0)
	var phase_time = attack_progress * 3.0
	
	if weapon and original_positions.has("weapon"):
		if phase_time < 1.0:
			# Windup - pull back
			var windup = phase_time
			weapon.position.x = original_positions["weapon"].x - windup * 10.0
			weapon.position.y = original_positions["weapon"].y - windup * 5.0
			weapon.rotation = -windup * 0.5
		elif phase_time < 2.0:
			# Swing - fast forward
			var swing = (phase_time - 1.0)
			weapon.position.x = original_positions["weapon"].x + swing * 15.0
			weapon.position.y = original_positions["weapon"].y + swing * 10.0
			weapon.rotation = swing * 1.2
		else:
			# Recover - return to position
			var recover = (phase_time - 2.0)
			weapon.position.x = lerp(original_positions["weapon"].x + 15.0, original_positions["weapon"].x, recover)
			weapon.position.y = lerp(original_positions["weapon"].y + 10.0, original_positions["weapon"].y, recover)
			weapon.rotation = lerp(1.2, 0.0, recover)
	
	# Body lunge during swing
	if phase_time >= 1.0 and phase_time < 2.0:
		var lunge = (phase_time - 1.0) * 3.0
		
		if torso and original_positions.has("torso"):
			torso.position.x = original_positions["torso"].x + lunge
		
		if head and original_positions.has("head"):
			head.position.x = original_positions["head"].x + lunge * 0.8
