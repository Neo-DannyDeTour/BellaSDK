## Editor 3D gizmo drawing directional arrows from [EventSequenceTrigger] to target nodes.
@tool
class_name EventSequencerGizmoPlugin
extends EditorNode3DGizmoPlugin

## Material key for action step target lines (Amber).
const MAT_STEP: String = "step_line"
## Material key for gate condition target lines (Cyan).
const MAT_COND: String = "cond_line"
## Material key for node parameter argument lines (Magenta).
const MAT_PARAM: String = "param_line"
## Length of 3D arrowhead fins in meters.
const ARROW_SIZE: float = 0.35
## Half-width spread of 3D arrowhead fins in meters.
const ARROW_SPREAD: float = 0.14


## Registers unshaded line materials for step, condition, and parameter links.
func _init() -> void:
	create_material(MAT_STEP, Color(1.0, 0.75, 0.15, 0.95), false, true)
	create_material(MAT_COND, Color(0.2, 0.85, 1.0, 0.95), false, true)
	create_material(MAT_PARAM, Color(0.95, 0.3, 0.9, 0.95), false, true)


## Returns true if [param for_node_3d] is an [EventSequenceTrigger].
func _has_gizmo(for_node_3d: Node3D) -> bool:
	return for_node_3d is EventSequenceTrigger


## Returns the display name of this gizmo in the Godot Editor 3D View menu.
func _get_gizmo_name() -> String:
	return "EventSequenceTriggerLinks"


## Rebuilds 3D connection lines and arrowheads for all targets on [param gizmo].
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var trigger: EventSequenceTrigger = gizmo.get_node_3d() as EventSequenceTrigger
	if not is_instance_valid(trigger) or not trigger.is_inside_tree():
		return

	var inv_xform: Transform3D = trigger.global_transform.affine_inverse()

	var cond_lines: PackedVector3Array = PackedVector3Array()
	for cond: EventCondition in trigger.conditions:
		if cond == null or cond.target_is_activator or cond.target_path.is_empty():
			continue
		var target_node: Node3D = trigger.get_node_or_null(cond.target_path) as Node3D
		if is_instance_valid(target_node):
			var end_local: Vector3 = inv_xform * target_node.global_position
			_append_arrow(cond_lines, Vector3.ZERO, end_local)

	if not cond_lines.is_empty():
		gizmo.add_lines(cond_lines, get_material(MAT_COND, gizmo), false)

	var step_lines: PackedVector3Array = PackedVector3Array()
	var param_lines: PackedVector3Array = PackedVector3Array()

	for step: EventStep in trigger.steps:
		if step == null:
			continue
		if not step.target_is_activator and not step.target_path.is_empty():
			var step_target: Node3D = trigger.get_node_or_null(step.target_path) as Node3D
			if is_instance_valid(step_target):
				var end_local: Vector3 = inv_xform * step_target.global_position
				_append_arrow(step_lines, Vector3.ZERO, end_local)

		var clean_param: String = step.parameter.strip_edges()
		if not clean_param.is_empty() and clean_param.contains("/"):
			var param_node: Node3D = trigger.get_node_or_null(NodePath(clean_param)) as Node3D
			if is_instance_valid(param_node):
				var end_local: Vector3 = inv_xform * param_node.global_position
				_append_arrow(param_lines, Vector3.ZERO, end_local)

	if not step_lines.is_empty():
		gizmo.add_lines(step_lines, get_material(MAT_STEP, gizmo), false)
	if not param_lines.is_empty():
		gizmo.add_lines(param_lines, get_material(MAT_PARAM, gizmo), false)


## Appends a line segment and a 4-fin 3D arrowhead from [param from_pos] to [param to_pos].
func _append_arrow(lines: PackedVector3Array, from_pos: Vector3, to_pos: Vector3) -> void:
	var diff: Vector3 = to_pos - from_pos
	var dist_sq: float = diff.length_squared()
	if dist_sq < 0.001:
		return

	lines.append(from_pos)
	lines.append(to_pos)

	var dir: Vector3 = diff / sqrt(dist_sq)
	var up_ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side: Vector3 = dir.cross(up_ref).normalized()
	var ortho_up: Vector3 = side.cross(dir).normalized()
	var base_pt: Vector3 = to_pos - (dir * ARROW_SIZE)

	lines.append(to_pos)
	lines.append(base_pt + side * ARROW_SPREAD)
	lines.append(to_pos)
	lines.append(base_pt - side * ARROW_SPREAD)
	lines.append(to_pos)
	lines.append(base_pt + ortho_up * ARROW_SPREAD)
	lines.append(to_pos)
	lines.append(base_pt - ortho_up * ARROW_SPREAD)
