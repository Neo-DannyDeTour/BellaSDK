## Single sequence step executing method calls or property assignments with flow control.
@tool
class_name EventStep
extends Resource

## Action operation type for this step.
enum StepType {
	CALL_METHOD,
	SET_PROPERTY,
}

## Flow control mode determining whether the sequence waits or continues immediately.
enum ExecMode {
	SEQUENTIAL,
	PARALLEL,
	WAIT_SIGNAL,
}

## Operation performed when this step runs.
@export var step_type: StepType = StepType.CALL_METHOD

## Concurrency and completion awaiting mode for this step.
@export var exec_mode: ExecMode = ExecMode.SEQUENTIAL

## If true, targets the entering body instead of [member target_path].
@export var target_is_activator: bool = false

## Target [NodePath] relative to the owning [EventSequenceTrigger].
@export var target_path: NodePath = NodePath()

## Method name (for CALL_METHOD) or property name (for SET_PROPERTY).
@export var method_name: StringName = &""

## Signal name awaited on target when [member exec_mode] is WAIT_SIGNAL.
@export var signal_name: StringName = &""

## Serialized parameter passed to method call or property assignment.
@export var parameter: String = ""

## Delay in seconds before this step executes its action.
@export var delay: float = 0.0

## If true, step executes only once per level session.
@export var fire_once: bool = false

## Runtime flag tracking if this step has already fired.
var has_fired: bool = false


## Resolves target [Node] using either [param activator] or [member target_path].
func resolve_target(caller: Node, activator: Node3D) -> Node:
	if target_is_activator:
		return activator
	if not is_instance_valid(caller) or target_path.is_empty():
		return null
	return caller.get_node_or_null(target_path)


## Executes method call or property assignment on the resolved target node.
func execute(caller: Node, activator: Node3D) -> void:
	var target: Node = resolve_target(caller, activator)
	if not is_instance_valid(target):
		print("EventStep: Target invalid for path -> ", target_path)
		return

	if method_name.is_empty():
		has_fired = true
		return

	var clean_param: String = parameter.strip_edges()
	if clean_param == '""' or clean_param == "''":
		clean_param = ""

	match step_type:
		StepType.CALL_METHOD:
			_execute_method(caller, target, clean_param)
		StepType.SET_PROPERTY:
			_execute_property(caller, target, clean_param)

	has_fired = true


## Invokes [member method_name] on [param target] with zero or one resolved argument.
func _execute_method(caller: Node, target: Node, clean_param: String) -> void:
	print("EventStep: Calling ", method_name, " on ", target.name)
	var arg_count: int = 0
	for m: Dictionary in target.get_method_list():
		var raw_name: Variant = m.get("name")
		if raw_name is String and StringName(str(raw_name)) == method_name:
			var raw_args: Variant = m.get("args")
			if raw_args is Array:
				var args_array: Array = raw_args
				arg_count = args_array.size()
			break

	if clean_param.is_empty() or arg_count == 0:
		target.call(method_name)
	else:
		var resolved_arg: Variant = _resolve_parameter(caller, clean_param)
		target.call(method_name, resolved_arg)


## Assigns [member method_name] property on [param target] to resolved [param clean_param].
func _execute_property(caller: Node, target: Node, clean_param: String) -> void:
	var resolved_val: Variant = _resolve_parameter(caller, clean_param)
	print("EventStep: Setting ", method_name, " = ", resolved_val, " on ", target.name)
	target.set(method_name, resolved_val)


## Converts raw parameter string into [bool], [int], [float], [Node], or [String].
func _resolve_parameter(caller: Node, raw_param: String) -> Variant:
	var lower: String = raw_param.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	if raw_param.is_valid_int():
		return raw_param.to_int()
	if raw_param.is_valid_float():
		return raw_param.to_float()

	if is_instance_valid(caller) and not raw_param.is_empty():
		var node_lookup: Node = caller.get_node_or_null(NodePath(raw_param))
		if not is_instance_valid(node_lookup) and caller.is_inside_tree():
			node_lookup = caller.get_tree().get_root().find_child(raw_param, true, false)
		if is_instance_valid(node_lookup):
			return node_lookup

	return raw_param
