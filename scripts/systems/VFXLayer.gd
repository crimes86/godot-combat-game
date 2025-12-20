extends CanvasLayer
class_name VFXLayerClass
## VFX Layer - Renders visual effects at full brightness regardless of environment lighting
## This layer is unaffected by CanvasModulate (day/night cycle)
##
## Usage: VFXLayer.add_effect(my_effect_node)

# Layer index above CanvasModulate but below UI
const VFX_LAYER_INDEX = 5

# Container for effects
var _effects_container: Node2D = null

func _ready() -> void:
	layer = VFX_LAYER_INDEX
	follow_viewport_enabled = true

	# Create container for effects
	_effects_container = Node2D.new()
	_effects_container.name = "EffectsContainer"
	add_child(_effects_container)

	print("✨ VFXLayer initialized - weapon effects will render at full brightness")

func add_effect(effect: Node) -> void:
	"""Add a visual effect to the VFX layer (full brightness, ignores CanvasModulate)"""
	if _effects_container and is_instance_valid(effect):
		_effects_container.add_child(effect)

func add_effect_at(effect: Node, global_pos: Vector2) -> void:
	"""Add effect at specific global position"""
	if effect is Node2D or effect is Control:
		effect.global_position = global_pos
	add_effect(effect)

func clear_effects() -> void:
	"""Remove all effects (useful for scene transitions)"""
	if _effects_container:
		for child in _effects_container.get_children():
			child.queue_free()
