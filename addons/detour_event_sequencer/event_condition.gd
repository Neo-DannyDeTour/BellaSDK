## Pre-trigger gate condition evaluated when an activator enters [EventSequenceTrigger].
@tool
class_name EventCondition
extends Resource

## Gate evaluation mode for this condition.
enum CondType {
	VOLUME_HAS_LAYER,
	VOLUME_HAS_NODE,
	PROPERTY_COMPARE,
}

## Comparison operator for property evaluation.
enum CompareOp {
	EQUAL,
	NOT_EQUAL,
	GREATER,
	LESS,
}

## Category of check performed before sequence execution.
@export var cond_type: CondType = CondType.VOLUME_HAS_LAYER

## Physics layer bitmask checked when [member cond_type] is VOLUME_HAS_LAYER (4 = Layer 3).
@export_flags_3d_physics var required_layer_mask: int = 4

## If true, evaluates [member property_name] on the entering activator body.
@export var target_is_activator: bool = false

## Target [NodePath] evaluated for VOLUME_HAS_NODE or PROPERTY_COMPARE.
@export var target_path: NodePath = NodePath()

## Script or engine property name inspected during PROPERTY_COMPARE.
@export var property_name: StringName = &""

## Operator used to compare [member property_name] against [member compare_value].
@export var compare_op: CompareOp = CompareOp.EQUAL

## Expected value serialized as string for comparison.
@export var compare_value: String = "true"


## Returns true if this condition passes for [param trigger] and [param activator].
func evaluate(trigger: Area3D, activator: Node3D) -> bool:
	if not is_instance_valid(trigger):
		return false

	match cond_type:
		CondType.VOLUME_HAS_LAYER:
			return _evaluate_layer(trigger)
		CondType.VOLUME_HAS_NODE:
			return _evaluate_node(trigger)
		CondType.PROPERTY_COMPARE:
			return _evaluate_property(trigger, activator)
	return false


## Checks whether any overlapping body inside [param trigger] matches [member required_layer_mask].
func _evaluate_layer(trigger: Area3D) -> bool:
	var bodies: Array[Node3D] = trigger.get_overlapping_bodies()
	for body: Node3D in bodies:
		var col_obj: CollisionObject3D = body as CollisionObject3D
		if is_instance_valid(col_obj) and (col_obj.collision_layer & required_layer_mask) != 0:
			return true
	return false


## Checks whether the specific node at [member target_path] is inside [param trigger].
func _evaluate_node(trigger: Area3D) -> bool:
	var target: Node = trigger.get_node_or_null(target_path)
	if not is_instance_valid(target):
		return false
	var target_3d: Node3D = target as Node3D
	if not is_instance_valid(target_3d):
		return false
	var bodies: Array[Node3D] = trigger.get_overlapping_bodies()
	return bodies.has(target_3d)


## Evaluates [member property_name] on target or [param activator] against [member compare_value].
func _evaluate_property(trigger: Area3D, activator: Node3D) -> bool:
	var target: Node = (
		activator if target_is_activator else trigger.get_node_or_null(target_path)
	)
	if not is_instance_valid(target) or property_name.is_empty():
		return false

	var current_val: Variant = target.get(property_name)
	var val_str: String = str(current_val).to_lower()
	var exp_str: String = compare_value.strip_edges().to_lower()

	match compare_op:
		CompareOp.EQUAL:
			return val_str == exp_str
		CompareOp.NOT_EQUAL:
			return val_str != exp_str
		CompareOp.GREATER:
			return val_str.to_float() > exp_str.to_float()
		CompareOp.LESS:
			return val_str.to_float() < exp_str.to_float()
	return false
