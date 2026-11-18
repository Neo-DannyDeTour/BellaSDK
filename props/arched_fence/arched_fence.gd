## Static arched iron grate prop enforcing environment render and physics layers.
# class_name ArchedFence
extends StaticBody3D

## Mesh instance displaying the arched iron grate geometry.
@export var mesh_instance: MeshInstance3D


## Validates [member mesh_instance], sets layer bitmasks, and disables loop ticks.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(mesh_instance != null, "ArchedFence: mesh_instance must be assigned.")

	collision_layer = CollisionLayers.MASK_ENVIRONMENT
	collision_mask = CollisionLayers.MASK_NONE
	mesh_instance.layers = CollisionLayers.RENDER_LAYER_ENVIRONMENT_IDX
