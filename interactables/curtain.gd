## A cloth-physics curtain that can react to external forces and player interactions.
##
## Manages internal `SoftBody3D` parameters to create responsive swinging and pulling behaviors.
class_name PhysicsCurtain
extends SoftBody3D

## The resting rigidity of the curtain. Higher values result in less deformation.
@export var default_stiffness: float = 0.5
## Determines if the player is allowed to trigger the manual tug sequence.
@export var is_interactable: bool = true


## Sets the resting parameters for the soft body physics mesh.
func _ready() -> void:
	linear_stiffness = default_stiffness
	print("PlasticCurtain: Physics mesh initialized at global position ", global_position)


## Called by the player script to simulate an intentional pull or tug.
## [param force_multiplier]: Scales the intensity of the temporary deformation effect.
func tug_curtain(force_multiplier: float) -> void:
	print("Player tugged the curtain with force multiplier: ", force_multiplier)

	if not is_interactable:
		return

	# Temporarily reduce stiffness to simulate a flowing tug
	linear_stiffness = 0.1

	# Reset the stiffness after a short delay
	await get_tree().create_timer(0.5).timeout
	linear_stiffness = default_stiffness
