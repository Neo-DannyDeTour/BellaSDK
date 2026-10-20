## Execution context providing scene, toggle state, and output facilities to console commands.
class_name ConsoleContext
extends RefCounted

## Reference to the hosting console CanvasLayer for scene tree and UI lifecycle queries.
var host: CanvasLayer = null

## Shared dictionary of boolean command toggle states.
var toggle_states: Dictionary = {}


## Constructs a new [ConsoleContext] binding the host console node and toggle store.
func _init(p_host: CanvasLayer, p_toggle_states: Dictionary) -> void:
	host = p_host
	toggle_states = p_toggle_states


## Appends formatted text to the console terminal display.
func write(message: String, color: String = "white") -> void:
	if is_instance_valid(host) and host.has_method(&"write"):
		host.call(&"write", message, color)
	else:
		print("Console Output [", color, "]: ", message)


## Outputs an informational message to the console.
func log_info(msg: String) -> void:
	write("[INFO] " + msg, "white")


## Outputs a warning message to the console.
func log_warn(msg: String) -> void:
	write("[WARN] " + msg, "yellow")


## Outputs an error message to the console.
func log_error(msg: String) -> void:
	write("[ERROR] " + msg, "red")


## Parses boolean toggle argument from input tokens.
## Returns target boolean value, or null if arguments are invalid.
func parse_toggle_arg(args: PackedStringArray, current_state: bool, cmd_name: String) -> Variant:
	if args.is_empty():
		return not current_state

	var token: String = args[0].to_lower()
	if token in ["1", "on", "true", "enable", "enabled"]:
		return true
	if token in ["0", "off", "false", "disable", "disabled"]:
		return false

	write("Usage: " + cmd_name + " [on/off | 1/0]", "yellow")
	return null


## Returns autocomplete candidates for boolean toggle commands.
func get_toggle_options() -> Array[String]:
	return ["on", "off", "1", "0"]


## Returns boolean toggle state for [param key], defaulting to [param default_value].
func get_toggle_state(key: String, default_value: bool = false) -> bool:
	var state: Variant = toggle_states.get(key, default_value)
	return state == true


## Returns the active [SceneTree] via host console.
func get_tree() -> SceneTree:
	if is_instance_valid(host) and host.is_inside_tree():
		return host.get_tree()
	return Engine.get_main_loop() as SceneTree


## Returns the active [Viewport] associated with the console host.
func get_viewport() -> Viewport:
	if is_instance_valid(host) and host.is_inside_tree():
		return host.get_viewport()
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree) and is_instance_valid(tree.root):
		return tree.root
	return null


## Returns the active player [Node3D] by group query.
func get_player() -> Node3D:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree):
		return null
	var player_node: Node = NodeQuery.get_single_node_in_group(tree, &"player")
	return player_node as Node3D
