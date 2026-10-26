@tool
## Synchronizes [SubViewport] [member SubViewport.world_3d] with the parent [Viewport]
## so the top-down orthographic roof camera captures scene geometry for rain occlusion.
extends SubViewport


## Assigns parent [World3D] and disables per-frame processing on enter tree.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	var parent_vp: Viewport = get_parent().get_viewport() if get_parent() != null else null
	if is_instance_valid(parent_vp):
		world_3d = parent_vp.find_world_3d()
