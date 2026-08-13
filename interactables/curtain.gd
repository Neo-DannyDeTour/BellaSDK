class_name PhysicsCurtain
extends SoftBody3D

## Default stiffness.
@export var default_stiffness: float = 0.5
## Is interactable.
@export var is_interactable: bool = true


func _ready() -> void:
	linear_stiffness = default_stiffness
	print("PlasticCurtain: Physics mesh initialized at global position ", global_position)


## Called by the player script to simulate an intentional pull or tug.
func tug_curtain(force_multiplier: float) -> void:
	print("Player tugged the curtain with force multiplier: ", force_multiplier)

	if not is_interactable:
		return

	# Temporarily reduce stiffness to simulate a flowing tug
	linear_stiffness = 0.1

	# Reset the stiffness after a short delay
	await get_tree().create_timer(0.5).timeout
	linear_stiffness = default_stiffness
