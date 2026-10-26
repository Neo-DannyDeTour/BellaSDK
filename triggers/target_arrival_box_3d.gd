@tool
## Destination volume defining the arrival endpoint for ragdoll attraction sequences.
## Provides an invisible bounding hull with editor visualizer synchronization.
class_name TargetArrivalBox3D
extends BaseTriggerArea3D


## Configures default destination visualizer styling in the editor.
func _ready() -> void:
	if trigger_text == "TRIGGER":
		trigger_text = "DESTINATION"
	if trigger_color == Color(0.9, 0.5, 0.1, 0.25):
		trigger_color = Color(0.1, 0.85, 0.4, 0.25)
	if outline_color == Color(1.0, 0.8, 0.3, 0.9):
		outline_color = Color(0.2, 1.0, 0.5, 0.9)
	super._ready()


## Returns the global center of this arrival target volume.
func get_target_center() -> Vector3:
	return global_transform * trigger_offset


## Tests whether [param world_pos] falls inside this arrival boundary.
func contains_point(world_pos: Vector3) -> bool:
	if shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		var center: Vector3 = get_target_center()
		var radius: float = trigger_size.x * 0.5
		return world_pos.distance_squared_to(center) <= (radius * radius)

	# Box containment in local coordinates including trigger_offset
	var local_pos: Vector3 = global_transform.affine_inverse() * world_pos - trigger_offset
	var half_size: Vector3 = trigger_size * 0.5
	return (
		absf(local_pos.x) <= half_size.x
		and absf(local_pos.y) <= half_size.y
		and absf(local_pos.z) <= half_size.z
	)
