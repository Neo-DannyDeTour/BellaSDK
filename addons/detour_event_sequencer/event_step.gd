## Single event step storing target entity, method, delay, and parameter.
class_name EventStep
extends Resource

## Target [NodePath] to invoke the input method on.
@export var target_path: NodePath = NodePath()

## Target method or input name to call on [member target_path].
@export var method_name: StringName = &""

## Optional parameter string or value to pass to the method.
@export var parameter: String = ""

## Delay in seconds before triggering this event step.
@export var delay: float = 0.0

## If true, step executes only once and is ignored afterwards.
@export var fire_once: bool = false

## Dispatches method call on target entity, supporting optional arguments.
func execute(caller: Node) -> void:
	print("EventStep: Executing ", method_name, " on ", target_path)
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

	if clean_param.is_empty() or (method_found and method_arg_count == 0):
		target.call(method_name)
	else:
		target.call(method_name, clean_param)
