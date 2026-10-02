## Single sequence step executing method calls, signal listeners, or branching logic.
class_name EventStep
extends Resource

## Action type determining step execution behavior.
enum StepType { CALL_METHOD, WAIT_SIGNAL, LOGIC_BRANCH }

## Comparison operator used when evaluating logic branch conditions.
enum ConditionOp { EQUAL, NOT_EQUAL, GREATER, LESS }

## Execution category for this event step.
@export var step_type: StepType = StepType.CALL_METHOD

## Target [NodePath] to invoke methods on or monitor for signals.
@export var target_path: NodePath = NodePath()

## Target method or input name to call on [member target_path].
@export var method_name: StringName = &""

## Target signal name to await when [member step_type] is WAIT_SIGNAL.
@export var signal_name: StringName = &""

## Optional parameter string passed to the invoked method.
@export var parameter: String = ""

## Delay in seconds before triggering this step or dispatching output.
@export var delay: float = 0.0

## Property name evaluated on target when [member step_type] is LOGIC_BRANCH.
@export var condition_property: StringName = &""

## Comparison operator applied to condition property value.
@export var condition_operator: ConditionOp = ConditionOp.EQUAL

## Expected value string compared against target property.
@export var condition_value: String = "true"

## Target step index to jump to when logic condition evaluates to true.
@export var branch_jump_step: int = -1

## If true, step executes only once and is ignored on repeat triggers.
@export var fire_once: bool = false

## Internal flag tracking if step has executed previously.
var _has_fired: bool = false


## Dispatches method call on target entity, supporting optional arguments.
func execute(caller: Node) -> void:
	print("EventStep: Executing step on ", target_path, " -> ", method_name)
	var target: Node = caller.get_node_or_null(target_path)
	if not is_instance_valid(target):
		print("EventStep: Target node not found: ", target_path)
		return

	var clean_param: String = parameter.strip_edges()
	if clean_param == '""' or clean_param == "''":
		clean_param = ""

	var method_arg_count: int = 0
	var method_found: bool = false
	for m: Dictionary in target.get_method_list():
		if m.get("name") == method_name:
			method_arg_count = (m.get("args", []) as Array).size()
			method_found = true
			break

	if clean_param.is_empty():
		if method_found and method_arg_count == 0:
			target.call(method_name)
		else:
			target.call(method_name)
	else:
		var resolved_arg: Variant = _resolve_parameter(caller, clean_param)
		target.call(method_name, resolved_arg)
	_has_fired = true


## Resolves parameter string into typed node, number, boolean, or string.
func _resolve_parameter(caller: Node, raw_param: String) -> Variant:
	var node_lookup: Node = caller.get_node_or_null(NodePath(raw_param))
	if not is_instance_valid(node_lookup) and caller.is_inside_tree():
		node_lookup = caller.get_tree().get_root().find_child(raw_param, true, false)
	if is_instance_valid(node_lookup):
		return node_lookup

	if raw_param.to_lower() == "true":
		return true
	if raw_param.to_lower() == "false":
		return false
	if raw_param.is_valid_int():
		return raw_param.to_int()
	if raw_param.is_valid_float():
		return raw_param.to_float()

	return raw_param


## Evaluates condition property against expected value using comparison operator.
func evaluate_condition(caller: Node) -> bool:
	print("EventStep: Evaluating branch condition on ", target_path)
	var target: Node = caller.get_node_or_null(target_path)
	if not is_instance_valid(target):
		return false

	var current_val: Variant = target.get(condition_property)
	var val_str: String = str(current_val).to_lower()
	var expected_str: String = condition_value.strip_edges().to_lower()

	match condition_operator:
		ConditionOp.EQUAL:
			return val_str == expected_str
		ConditionOp.NOT_EQUAL:
			return val_str != expected_str
		ConditionOp.GREATER:
			return val_str.to_float() > expected_str.to_float()
		ConditionOp.LESS:
			return val_str.to_float() < expected_str.to_float()
	return false
